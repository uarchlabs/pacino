// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    bp_history.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Branch predictor history module.
// Owns GHR (256b) and PHR (32b) circular buffers plus all folded
// histories for TAGE T1-T4, ITTAGE IT1-IT5, and SC ST1-ST3.
// Pointer is module-owned: internal GHR/PHR pointer registers
// advance by num_branches each cycle and are exposed as registered
// outputs (BP-069). Buffer and checkpoint storage live here.
// Rollback: restore the pointer from an internal checkpoint by
// index, then recompute all folds at the restored position.
// Fold geometry is the Xiangshan FoldedHistory convention (BP-071):
// newest bit at the high end of the W-wide register; leaving bit
// removed at (H-1) % W; one fold definition shared by the
// incremental update and the rollback recompute. Helpers are 64b so
// the SC ST3 fold (H = W = 64) is representable.
// ===================================================================

import bp_defines_pkg::*;
import bp_structs_pkg::*;
module bp_history
(
  input  logic                         clk,
  input  logic                         rstn,

  // -- Prediction update, indexed by branch number b, not by slot
  // (BP-129: one entry per predicted branch, NUM_PRED_SLOTS entries).
  // pred_taken[b]/pred_pc[b]: branch b, written when num_branches > b
  input  logic [NUM_PRED_SLOTS-1:0]    pred_taken,
  input  logic [VA_WIDTH-1:0]          pred_pc  [NUM_PRED_SLOTS],
  input  logic [PRED_CNT_BITS-1:0]     num_branches, // 0..NUM_PRED_SLOTS

  // -- Checkpoint write (one write port, indexed by FTQ slot)
  input  logic                         ckpt_wr_en,
  input  logic [FTQ_IDX_BITS-1:0]     ckpt_wr_idx,

  // -- Rollback: restore pointer from internal checkpoint by index
  input  logic                         rollback_valid,
  input  logic [FTQ_IDX_BITS-1:0]     rollback_ckpt_idx,
  // -- Corrected rollback (BP-121; bp_history_decisions.md 3.5
  //    reopened and ruled by Jeff: correct on redirect). With
  //    rollback_corr set the pointer is restored to the FIRST bit of
  //    the named entry's bundle, rollback_n corrected bits are written
  //    there (rollback_tkn, and rollback_pbit into the PHR), and the
  //    pointer advances past them; the entry's checkpoint is rewritten
  //    to match. Clear: the pointer is restored past the bundle as
  //    before BP-121.
  input  logic                         rollback_corr,
  input  logic [PRED_CNT_BITS-1:0]     rollback_n,   // 0..NUM_PRED_SLOTS
  input  logic [NUM_PRED_SLOTS-1:0]    rollback_tkn,
  input  logic [NUM_PRED_SLOTS-1:0]    rollback_pbit,

  // -- Current pointer outputs (module-owned, for FTQ build)
  output logic [GHIST_PTR_BITS-1:0]   ghist_ptr,
  output logic [PHIST_PTR_BITS-1:0]   phist_ptr,

  // -- Checkpoint snapshot outputs (for FTQ entry construction)
  output logic [GHIST_PTR_BITS-1:0]   ckpt_ghist_ptr,
  output logic [PHIST_PTR_BITS-1:0]   ckpt_phist_ptr,

  // -- Raw buffer outputs
  output logic [GHR_WIDTH-1:0]         ghr_buf,
  output logic [PHR_WIDTH-1:0]         phr_buf,

  // -- Folded history outputs
  output bp_folded_hist_t              folded
);

  // ----------------------------------------------------------------
  // Internal storage
  // ----------------------------------------------------------------
  logic [GHR_WIDTH-1:0] ghr_mem;
  logic [PHR_WIDTH-1:0] phr_mem;

  // Module-owned live pointers. Advanced by num_branches each cycle;
  // restored from a checkpoint on rollback. Exposed on the
  // ghist_ptr / phist_ptr registered outputs.
  logic [GHIST_PTR_BITS-1:0] ghist_ptr_r;
  logic [PHIST_PTR_BITS-1:0] phist_ptr_r;

  logic [GHIST_PTR_BITS-1:0] ckpt_gptr [FTQ_DEPTH];
  logic [PHIST_PTR_BITS-1:0] ckpt_pptr [FTQ_DEPTH];
  // The bundle size of each checkpoint, so the bundle's first bit is
  // the checkpoint minus it (BP-121, the corrected rollback).
  logic [PRED_CNT_BITS-1:0]  ckpt_nb   [FTQ_DEPTH];

  bp_folded_hist_t fh_r;

  // ----------------------------------------------------------------
  // Single fold definition (Xiangshan FoldedHistory geometry, BP-071
  // position mapping, BP-072 increment-oriented walk).
  //
  // Both the incremental update (fold_step) and the rollback
  // recompute (fold_ghr) use ONE position mapping so that
  // recompute(history) == incremental(history) for the same history.
  //
  // The module-owned pointer INCREMENTS by num_branches each cycle and
  // the newest bit is written at the position just below the live
  // pointer. The fold window therefore walks the GHR DOWNWARD from the
  // newest bit: offset i = 0 is the newest bit (at the anchor), offset
  // i = H-1 is the oldest in window (ghr_mem[anchor-(H-1)]). The bit
  // leaving the H-deep window is at ghr_mem[anchor-H].
  //
  // Position mapping: posmap(i) = (i + W - 1) % W.
  //   - The newest bit (offset 0) lands at the high end, position W-1
  //     (circular_shift_left insertion end).
  //   - Each older bit is one position lower (modulo W), a left
  //     rotate per step.
  //   - The bit leaving the H-deep window is removed at posmap(H) =
  //     (H - 1) % W.
  //
  // Helpers are 64b wide so the SC ST3 fold (H = W = 64) is fully
  // representable; callers cast the result down to the field width.
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // fold_ghr: recompute the fold from ghr_mem[ptr..ptr-(H-1)] (walked
  // downward) into W bits by the single position mapping above. Used
  // for rollback recompute. Returns 64b (upper bits zero).
  // ----------------------------------------------------------------
  function automatic logic [63:0] fold_ghr(
    input logic [GHR_WIDTH-1:0] mem,
    input int                   ptr_in,
    input int                   H,
    input int                   W
  );
    logic [63:0] acc;
    int          i, bit_idx, pos;
    acc = 64'b0;
    for (i = 0; i < H; i++) begin
      bit_idx = (ptr_in - i + GHR_WIDTH) % GHR_WIDTH;
      pos     = (i + W - 1) % W;
      if (mem[bit_idx]) acc[pos] = acc[pos] ^ 1'b1;
    end
    return acc;
  endfunction

  // ----------------------------------------------------------------
  // fold_step: one incremental fold step (Xiangshan
  // circular_shift_left). Equivalent to one window slide of fold_ghr.
  // new_bit: incoming prediction bit (newest); enters at the high end
  //          (folded position W-1) after a circular left rotate by 1.
  // bit_out: bit leaving the H-deep window (fetched by the caller at
  //          ghr_mem[write_addr - H]); removed at folded position
  //          (H-1) % W.
  // H:       history length (window depth) of this fold.
  // W:       folded (compressed) width of this fold.
  // Returns updated 64b fold (upper bits zero).
  // ----------------------------------------------------------------
  function automatic logic [63:0] fold_step(
    input logic [63:0] fold_in,
    input logic        new_bit,
    input logic        bit_out,
    input int          H,
    input int          W
  );
    logic [63:0] f;
    logic [63:0] mask;
    int          wrap_pos;
    mask        = (64'b1 << W) - 64'b1;
    f           = fold_in & mask;
    // circular_shift_left by one within the W-bit folded register
    f           = ((f << 1) | (f >> (W-1))) & mask;
    // newest history bit enters at the high end (position W-1)
    f[W-1]      = f[W-1] ^ new_bit;
    // bit leaving the H-deep window is removed at (H-1) % W
    wrap_pos    = (H - 1) % W;
    f[wrap_pos] = f[wrap_pos] ^ bit_out;
    f           = f & mask;
    return f;
  endfunction

  // leave_bit: the bit leaving an H-deep window when a bit is written
  // at wr_addr, ghr_mem[wr_addr - H] modulo the buffer width.
  function automatic logic leave_bit(
    input logic [GHR_WIDTH-1:0] mem,
    input int                   wr_addr,
    input int                   H
  );
    return mem[(wr_addr - H + GHR_WIDTH) % GHR_WIDTH];
  endfunction

  // ----------------------------------------------------------------
  // fold_all_step: one incremental step of every fold (TAGE T1-T4,
  // ITTAGE IT1-IT5, SC ST1-ST3) for one history bit. wr_addr is the
  // GHR address the bit is written at; the bit leaving each H-deep
  // window is read at mem[wr_addr - H]. mem is the buffer as it was
  // before this cycle's writes, so a second bit of the same cycle
  // reads the same buffer the first did (BP-129: the per-branch step
  // that the slot-0 and slot-1 blocks each wrote out in full).
  // ----------------------------------------------------------------
  function automatic bp_folded_hist_t fold_all_step(
    input bp_folded_hist_t      f_in,
    input logic                 new_bit,
    input logic [GHR_WIDTH-1:0] mem,
    input int                   wr_addr
  );
    bp_folded_hist_t f;
    f = f_in;
    // TAGE T1-T4
    f.tage_t1_idx_fh  = TAGE_MAX_FH'(fold_step(64'(f.tage_t1_idx_fh),
      new_bit, leave_bit(mem, wr_addr, TAGE_TBL_HIST[1]),
      TAGE_TBL_HIST[1], TAGE_TBL_FH[1]));
    f.tage_t1_tag_fh1 = TAGE_MAX_FH1'(fold_step(64'(f.tage_t1_tag_fh1),
      new_bit, leave_bit(mem, wr_addr, TAGE_TBL_HIST[1]),
      TAGE_TBL_HIST[1], TAGE_TBL_FH1[1]));
    f.tage_t1_tag_fh2 = TAGE_MAX_FH2'(fold_step(64'(f.tage_t1_tag_fh2),
      new_bit, leave_bit(mem, wr_addr, TAGE_TBL_HIST[1]),
      TAGE_TBL_HIST[1], TAGE_TBL_FH2[1]));
    f.tage_t2_idx_fh  = TAGE_MAX_FH'(fold_step(64'(f.tage_t2_idx_fh),
      new_bit, leave_bit(mem, wr_addr, TAGE_TBL_HIST[2]),
      TAGE_TBL_HIST[2], TAGE_TBL_FH[2]));
    f.tage_t2_tag_fh1 = TAGE_MAX_FH1'(fold_step(64'(f.tage_t2_tag_fh1),
      new_bit, leave_bit(mem, wr_addr, TAGE_TBL_HIST[2]),
      TAGE_TBL_HIST[2], TAGE_TBL_FH1[2]));
    f.tage_t2_tag_fh2 = TAGE_MAX_FH2'(fold_step(64'(f.tage_t2_tag_fh2),
      new_bit, leave_bit(mem, wr_addr, TAGE_TBL_HIST[2]),
      TAGE_TBL_HIST[2], TAGE_TBL_FH2[2]));
    f.tage_t3_idx_fh  = TAGE_MAX_FH'(fold_step(64'(f.tage_t3_idx_fh),
      new_bit, leave_bit(mem, wr_addr, TAGE_TBL_HIST[3]),
      TAGE_TBL_HIST[3], TAGE_TBL_FH[3]));
    f.tage_t3_tag_fh1 = TAGE_MAX_FH1'(fold_step(64'(f.tage_t3_tag_fh1),
      new_bit, leave_bit(mem, wr_addr, TAGE_TBL_HIST[3]),
      TAGE_TBL_HIST[3], TAGE_TBL_FH1[3]));
    f.tage_t3_tag_fh2 = TAGE_MAX_FH2'(fold_step(64'(f.tage_t3_tag_fh2),
      new_bit, leave_bit(mem, wr_addr, TAGE_TBL_HIST[3]),
      TAGE_TBL_HIST[3], TAGE_TBL_FH2[3]));
    f.tage_t4_idx_fh  = TAGE_MAX_FH'(fold_step(64'(f.tage_t4_idx_fh),
      new_bit, leave_bit(mem, wr_addr, TAGE_TBL_HIST[4]),
      TAGE_TBL_HIST[4], TAGE_TBL_FH[4]));
    f.tage_t4_tag_fh1 = TAGE_MAX_FH1'(fold_step(64'(f.tage_t4_tag_fh1),
      new_bit, leave_bit(mem, wr_addr, TAGE_TBL_HIST[4]),
      TAGE_TBL_HIST[4], TAGE_TBL_FH1[4]));
    f.tage_t4_tag_fh2 = TAGE_MAX_FH2'(fold_step(64'(f.tage_t4_tag_fh2),
      new_bit, leave_bit(mem, wr_addr, TAGE_TBL_HIST[4]),
      TAGE_TBL_HIST[4], TAGE_TBL_FH2[4]));
    // ITTAGE IT1-IT5
    f.it_t1_idx_fh    = IT_MAX_FH'(fold_step(64'(f.it_t1_idx_fh),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[1]),
      IT_TBL_HIST[1], IT_TBL_FH[1]));
    f.it_t1_tag_fh1   = IT_MAX_FH1'(fold_step(64'(f.it_t1_tag_fh1),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[1]),
      IT_TBL_HIST[1], IT_TBL_FH1[1]));
    f.it_t1_tag_fh2   = IT_MAX_FH2'(fold_step(64'(f.it_t1_tag_fh2),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[1]),
      IT_TBL_HIST[1], IT_TBL_FH2[1]));
    f.it_t2_idx_fh    = IT_MAX_FH'(fold_step(64'(f.it_t2_idx_fh),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[2]),
      IT_TBL_HIST[2], IT_TBL_FH[2]));
    f.it_t2_tag_fh1   = IT_MAX_FH1'(fold_step(64'(f.it_t2_tag_fh1),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[2]),
      IT_TBL_HIST[2], IT_TBL_FH1[2]));
    f.it_t2_tag_fh2   = IT_MAX_FH2'(fold_step(64'(f.it_t2_tag_fh2),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[2]),
      IT_TBL_HIST[2], IT_TBL_FH2[2]));
    f.it_t3_idx_fh    = IT_MAX_FH'(fold_step(64'(f.it_t3_idx_fh),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[3]),
      IT_TBL_HIST[3], IT_TBL_FH[3]));
    f.it_t3_tag_fh1   = IT_MAX_FH1'(fold_step(64'(f.it_t3_tag_fh1),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[3]),
      IT_TBL_HIST[3], IT_TBL_FH1[3]));
    f.it_t3_tag_fh2   = IT_MAX_FH2'(fold_step(64'(f.it_t3_tag_fh2),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[3]),
      IT_TBL_HIST[3], IT_TBL_FH2[3]));
    f.it_t4_idx_fh    = IT_MAX_FH'(fold_step(64'(f.it_t4_idx_fh),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[4]),
      IT_TBL_HIST[4], IT_TBL_FH[4]));
    f.it_t4_tag_fh1   = IT_MAX_FH1'(fold_step(64'(f.it_t4_tag_fh1),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[4]),
      IT_TBL_HIST[4], IT_TBL_FH1[4]));
    f.it_t4_tag_fh2   = IT_MAX_FH2'(fold_step(64'(f.it_t4_tag_fh2),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[4]),
      IT_TBL_HIST[4], IT_TBL_FH2[4]));
    f.it_t5_idx_fh    = IT_MAX_FH'(fold_step(64'(f.it_t5_idx_fh),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[5]),
      IT_TBL_HIST[5], IT_TBL_FH[5]));
    f.it_t5_tag_fh1   = IT_MAX_FH1'(fold_step(64'(f.it_t5_tag_fh1),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[5]),
      IT_TBL_HIST[5], IT_TBL_FH1[5]));
    f.it_t5_tag_fh2   = IT_MAX_FH2'(fold_step(64'(f.it_t5_tag_fh2),
      new_bit, leave_bit(mem, wr_addr, IT_TBL_HIST[5]),
      IT_TBL_HIST[5], IT_TBL_FH2[5]));
    // SC ST1-ST3 (H = W = SC_TBL_HIST)
    f.sc_t1_idx_fh    = SC_MAX_FH'(fold_step(64'(f.sc_t1_idx_fh),
      new_bit, leave_bit(mem, wr_addr, SC_TBL_HIST[1]),
      SC_TBL_HIST[1], SC_TBL_HIST[1]));
    f.sc_t2_idx_fh    = SC_MAX_FH'(fold_step(64'(f.sc_t2_idx_fh),
      new_bit, leave_bit(mem, wr_addr, SC_TBL_HIST[2]),
      SC_TBL_HIST[2], SC_TBL_HIST[2]));
    f.sc_t3_idx_fh    = SC_MAX_FH'(fold_step(64'(f.sc_t3_idx_fh),
      new_bit, leave_bit(mem, wr_addr, SC_TBL_HIST[3]),
      SC_TBL_HIST[3], SC_TBL_HIST[3]));
    return f;
  endfunction

  // ----------------------------------------------------------------
  // Path bit of each predicted branch, by branch number
  // ----------------------------------------------------------------
  logic [NUM_PRED_SLOTS-1:0] path_bit;
  always_comb begin : path_bits
    for (int b = 0; b < NUM_PRED_SLOTS; b++)
      path_bit[b] = pred_pc[b][2] ^ pred_pc[b][3];
  end

  // ----------------------------------------------------------------
  // Sequential update logic
  // ----------------------------------------------------------------
  integer idx_i;

  always_ff @(posedge clk or negedge rstn) begin : seq_main
    if (!rstn) begin
      ghr_mem        <= {GHR_WIDTH{1'b0}};
      phr_mem        <= {PHR_WIDTH{1'b0}};
      ghist_ptr_r    <= {GHIST_PTR_BITS{1'b0}};
      phist_ptr_r    <= {PHIST_PTR_BITS{1'b0}};
      fh_r           <= '0;
      ckpt_ghist_ptr <= {GHIST_PTR_BITS{1'b0}};
      ckpt_phist_ptr <= {PHIST_PTR_BITS{1'b0}};
      for (idx_i = 0; idx_i < FTQ_DEPTH; idx_i++) begin
        ckpt_gptr[idx_i] <= {GHIST_PTR_BITS{1'b0}};
        ckpt_pptr[idx_i] <= {PHIST_PTR_BITS{1'b0}};
        ckpt_nb[idx_i]   <= '0;
      end

    end else if (rollback_valid) begin : rb_apply
      // Rollback by index (module-owned pointer): read the checkpoint
      // at rollback_ckpt_idx, load the live pointer from it, and
      // recompute all folds from ghr_mem at the restored position
      // using the single fold definition (fold_ghr position mapping).
      // The checkpoint stores the POST-advance live pointer (the next
      // write address as of the checkpointed bundle); the newest
      // history bit is one position behind it, so the fold recompute
      // anchors at rb_anchor = rb_gptr - 1 and walks backward into
      // older bits. Folds are GHR-derived, so rb_anchor drives every
      // fold_ghr recompute.
      logic [GHIST_PTR_BITS-1:0] rb_gptr;
      logic [PHIST_PTR_BITS-1:0] rb_pptr;
      logic [GHIST_PTR_BITS-1:0] rb_gbase;
      logic [PHIST_PTR_BITS-1:0] rb_pbase;
      logic [GHR_WIDTH-1:0]      rb_ghr;
      logic [PHR_WIDTH-1:0]      rb_phr;
      int                        rb_anchor;
      rb_gptr     = ckpt_gptr[rollback_ckpt_idx];
      rb_pptr     = ckpt_pptr[rollback_ckpt_idx];
      rb_ghr      = ghr_mem;
      rb_phr      = phr_mem;
      // The corrected rollback (BP-121): back to the bundle's first
      // bit, write the corrected bits, advance past them, and record
      // the corrected bundle in the entry's checkpoint.
      if (rollback_corr) begin
        rb_gbase = rb_gptr - GHIST_PTR_BITS'(ckpt_nb[rollback_ckpt_idx]);
        rb_pbase = rb_pptr - PHIST_PTR_BITS'(ckpt_nb[rollback_ckpt_idx]);
        for (int k = 0; k < NUM_PRED_SLOTS; k++) begin
          if (k < int'(rollback_n)) begin
            rb_ghr[(int'(rb_gbase) + k) % GHR_WIDTH] = rollback_tkn[k];
            rb_phr[(int'(rb_pbase) + k) % PHR_WIDTH] = rollback_pbit[k];
          end
        end
        rb_gptr = rb_gbase + GHIST_PTR_BITS'(rollback_n);
        rb_pptr = rb_pbase + PHIST_PTR_BITS'(rollback_n);
        ckpt_gptr[rollback_ckpt_idx] <= rb_gptr;
        ckpt_pptr[rollback_ckpt_idx] <= rb_pptr;
        ckpt_nb[rollback_ckpt_idx]   <= rollback_n;
        ghr_mem <= rb_ghr;
        phr_mem <= rb_phr;
      end
      rb_anchor   = (int'(rb_gptr) - 1 + GHR_WIDTH) % GHR_WIDTH;
      ghist_ptr_r <= rb_gptr;
      phist_ptr_r <= rb_pptr;
      // TAGE T1
      fh_r.tage_t1_idx_fh  <= TAGE_MAX_FH'(fold_ghr(rb_ghr,
        rb_anchor, TAGE_TBL_HIST[1], TAGE_TBL_FH[1]));
      fh_r.tage_t1_tag_fh1 <= TAGE_MAX_FH1'(fold_ghr(rb_ghr,
        rb_anchor, TAGE_TBL_HIST[1], TAGE_TBL_FH1[1]));
      fh_r.tage_t1_tag_fh2 <= TAGE_MAX_FH2'(fold_ghr(rb_ghr,
        rb_anchor, TAGE_TBL_HIST[1], TAGE_TBL_FH2[1]));
      // TAGE T2
      fh_r.tage_t2_idx_fh  <= TAGE_MAX_FH'(fold_ghr(rb_ghr,
        rb_anchor, TAGE_TBL_HIST[2], TAGE_TBL_FH[2]));
      fh_r.tage_t2_tag_fh1 <= TAGE_MAX_FH1'(fold_ghr(rb_ghr,
        rb_anchor, TAGE_TBL_HIST[2], TAGE_TBL_FH1[2]));
      fh_r.tage_t2_tag_fh2 <= TAGE_MAX_FH2'(fold_ghr(rb_ghr,
        rb_anchor, TAGE_TBL_HIST[2], TAGE_TBL_FH2[2]));
      // TAGE T3
      fh_r.tage_t3_idx_fh  <= TAGE_MAX_FH'(fold_ghr(rb_ghr,
        rb_anchor, TAGE_TBL_HIST[3], TAGE_TBL_FH[3]));
      fh_r.tage_t3_tag_fh1 <= TAGE_MAX_FH1'(fold_ghr(rb_ghr,
        rb_anchor, TAGE_TBL_HIST[3], TAGE_TBL_FH1[3]));
      fh_r.tage_t3_tag_fh2 <= TAGE_MAX_FH2'(fold_ghr(rb_ghr,
        rb_anchor, TAGE_TBL_HIST[3], TAGE_TBL_FH2[3]));
      // TAGE T4
      fh_r.tage_t4_idx_fh  <= TAGE_MAX_FH'(fold_ghr(rb_ghr,
        rb_anchor, TAGE_TBL_HIST[4], TAGE_TBL_FH[4]));
      fh_r.tage_t4_tag_fh1 <= TAGE_MAX_FH1'(fold_ghr(rb_ghr,
        rb_anchor, TAGE_TBL_HIST[4], TAGE_TBL_FH1[4]));
      fh_r.tage_t4_tag_fh2 <= TAGE_MAX_FH2'(fold_ghr(rb_ghr,
        rb_anchor, TAGE_TBL_HIST[4], TAGE_TBL_FH2[4]));
      // ITTAGE IT1
      fh_r.it_t1_idx_fh    <= IT_MAX_FH'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[1], IT_TBL_FH[1]));
      fh_r.it_t1_tag_fh1   <= IT_MAX_FH1'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[1], IT_TBL_FH1[1]));
      fh_r.it_t1_tag_fh2   <= IT_MAX_FH2'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[1], IT_TBL_FH2[1]));
      // ITTAGE IT2
      fh_r.it_t2_idx_fh    <= IT_MAX_FH'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[2], IT_TBL_FH[2]));
      fh_r.it_t2_tag_fh1   <= IT_MAX_FH1'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[2], IT_TBL_FH1[2]));
      fh_r.it_t2_tag_fh2   <= IT_MAX_FH2'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[2], IT_TBL_FH2[2]));
      // ITTAGE IT3
      fh_r.it_t3_idx_fh    <= IT_MAX_FH'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[3], IT_TBL_FH[3]));
      fh_r.it_t3_tag_fh1   <= IT_MAX_FH1'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[3], IT_TBL_FH1[3]));
      fh_r.it_t3_tag_fh2   <= IT_MAX_FH2'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[3], IT_TBL_FH2[3]));
      // ITTAGE IT4
      fh_r.it_t4_idx_fh    <= IT_MAX_FH'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[4], IT_TBL_FH[4]));
      fh_r.it_t4_tag_fh1   <= IT_MAX_FH1'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[4], IT_TBL_FH1[4]));
      fh_r.it_t4_tag_fh2   <= IT_MAX_FH2'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[4], IT_TBL_FH2[4]));
      // ITTAGE IT5
      fh_r.it_t5_idx_fh    <= IT_MAX_FH'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[5], IT_TBL_FH[5]));
      fh_r.it_t5_tag_fh1   <= IT_MAX_FH1'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[5], IT_TBL_FH1[5]));
      fh_r.it_t5_tag_fh2   <= IT_MAX_FH2'(fold_ghr(rb_ghr,
        rb_anchor, IT_TBL_HIST[5], IT_TBL_FH2[5]));
      // SC ST1-ST3 (H = W = SC_TBL_HIST)
      fh_r.sc_t1_idx_fh    <= SC_MAX_FH'(fold_ghr(rb_ghr,
        rb_anchor, SC_TBL_HIST[1], SC_TBL_HIST[1]));
      fh_r.sc_t2_idx_fh    <= SC_MAX_FH'(fold_ghr(rb_ghr,
        rb_anchor, SC_TBL_HIST[2], SC_TBL_HIST[2]));
      fh_r.sc_t3_idx_fh    <= SC_MAX_FH'(fold_ghr(rb_ghr,
        rb_anchor, SC_TBL_HIST[3], SC_TBL_HIST[3]));

    end else begin : nrm
      // -- Advance the module-owned pointer by num_branches this
      // cycle (0 holds, 1 to NUM_PRED_SLOTS advance), modulo buffer
      // width.
      // nxt_*ptr is the POST-advance live pointer (the next write
      // address). The checkpoint stores this post-advance value so a
      // later rollback restores the pointer to where the next write
      // continues, and recomputes folds from one position behind it
      // (rb_anchor = ckpt - 1, the newest history bit of the bundle).
      logic [GHIST_PTR_BITS-1:0] nxt_gptr;
      logic [PHIST_PTR_BITS-1:0] nxt_pptr;
      bp_folded_hist_t           fh_nxt;
      nxt_gptr = GHIST_PTR_BITS'(
        (int'(ghist_ptr_r) + int'(num_branches)) % GHR_WIDTH);
      nxt_pptr = PHIST_PTR_BITS'(
        (int'(phist_ptr_r) + int'(num_branches)) % PHR_WIDTH);
      ghist_ptr_r <= nxt_gptr;
      phist_ptr_r <= nxt_pptr;

      // -- Normal update, one history bit per predicted branch, in
      // branch order. Branch b is written at ghist_ptr_r + b and each
      // fold takes one incremental step per branch, all from the
      // buffer as it was before this cycle (the leaving bit of every
      // step is read from ghr_mem, not from this cycle's writes).
      // Branch b is written when num_branches > b. Branch 0 is also
      // written on a count above NUM_PRED_SLOTS, which no driver
      // produces, as the slot-0 block did before BP-129.
      fh_nxt = fh_r;
      for (int b = 0; b < NUM_PRED_SLOTS; b++) begin
        if ((int'(num_branches) > b) &&
            ((b == 0) || (int'(num_branches) <= NUM_PRED_SLOTS))) begin
          ghr_mem[(int'(ghist_ptr_r) + b) % GHR_WIDTH] <= pred_taken[b];
          phr_mem[(int'(phist_ptr_r) + b) % PHR_WIDTH] <= path_bit[b];
          fh_nxt = fold_all_step(fh_nxt, pred_taken[b], ghr_mem,
                                 int'(ghist_ptr_r) + b);
        end
      end
      fh_r <= fh_nxt;

      // Checkpoint write. Captures the POST-advance pointer pair (the
      // next write address for the cycle after this bundle) and
      // exposes it on the snapshot outputs. Rollback restores the
      // pointer to this value and recomputes folds from one position
      // behind it (rb_anchor = ckpt - 1).
      if (ckpt_wr_en) begin
        ckpt_gptr[ckpt_wr_idx] <= nxt_gptr;
        ckpt_pptr[ckpt_wr_idx] <= nxt_pptr;
        ckpt_nb[ckpt_wr_idx]   <= num_branches;
        ckpt_ghist_ptr         <= nxt_gptr;
        ckpt_phist_ptr         <= nxt_pptr;
      end
    end
  end : seq_main

  // ----------------------------------------------------------------
  // Combinational output assignments
  // ----------------------------------------------------------------
  assign ghist_ptr = ghist_ptr_r;
  assign phist_ptr = phist_ptr_r;
  assign ghr_buf   = ghr_mem;
  assign phr_buf   = phr_mem;
  assign folded    = fh_r;

endmodule : bp_history
