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
// histories for TAGE T1-T4, ITTAGE IT1-IT4, and SC ST1-ST3.
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

  // -- Prediction update
  // pred_taken[0]/pred_pc[0]: slot 0 (num_branches >= 1)
  // pred_taken[1]/pred_pc[1]: slot 1 (num_branches == 2)
  input  logic [1:0]                   pred_taken,
  input  logic [VA_WIDTH-1:0]          pred_pc  [2],
  input  logic [1:0]                   num_branches,  // 0,1,2

  // -- Checkpoint write (one write port, indexed by FTQ slot)
  input  logic                         ckpt_wr_en,
  input  logic [FTQ_IDX_BITS-1:0]     ckpt_wr_idx,

  // -- Rollback: restore pointer from internal checkpoint by index
  input  logic                         rollback_valid,
  input  logic [FTQ_IDX_BITS-1:0]     rollback_ckpt_idx,

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

  // ----------------------------------------------------------------
  // Path bits from each prediction slot
  // ----------------------------------------------------------------
  logic path_bit_0, path_bit_1;
  assign path_bit_0 = pred_pc[0][2] ^ pred_pc[0][3];
  assign path_bit_1 = pred_pc[1][2] ^ pred_pc[1][3];

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
      int                        rb_anchor;
      rb_gptr     = ckpt_gptr[rollback_ckpt_idx];
      rb_pptr     = ckpt_pptr[rollback_ckpt_idx];
      rb_anchor   = (int'(rb_gptr) - 1 + GHR_WIDTH) % GHR_WIDTH;
      ghist_ptr_r <= rb_gptr;
      phist_ptr_r <= rb_pptr;
      // TAGE T1
      fh_r.tage_t1_idx_fh  <= TAGE_MAX_FH'(fold_ghr(ghr_mem,
        rb_anchor, TAGE_TBL_HIST[1], TAGE_TBL_FH[1]));
      fh_r.tage_t1_tag_fh1 <= TAGE_MAX_FH1'(fold_ghr(ghr_mem,
        rb_anchor, TAGE_TBL_HIST[1], TAGE_TBL_FH1[1]));
      fh_r.tage_t1_tag_fh2 <= TAGE_MAX_FH2'(fold_ghr(ghr_mem,
        rb_anchor, TAGE_TBL_HIST[1], TAGE_TBL_FH2[1]));
      // TAGE T2
      fh_r.tage_t2_idx_fh  <= TAGE_MAX_FH'(fold_ghr(ghr_mem,
        rb_anchor, TAGE_TBL_HIST[2], TAGE_TBL_FH[2]));
      fh_r.tage_t2_tag_fh1 <= TAGE_MAX_FH1'(fold_ghr(ghr_mem,
        rb_anchor, TAGE_TBL_HIST[2], TAGE_TBL_FH1[2]));
      fh_r.tage_t2_tag_fh2 <= TAGE_MAX_FH2'(fold_ghr(ghr_mem,
        rb_anchor, TAGE_TBL_HIST[2], TAGE_TBL_FH2[2]));
      // TAGE T3
      fh_r.tage_t3_idx_fh  <= TAGE_MAX_FH'(fold_ghr(ghr_mem,
        rb_anchor, TAGE_TBL_HIST[3], TAGE_TBL_FH[3]));
      fh_r.tage_t3_tag_fh1 <= TAGE_MAX_FH1'(fold_ghr(ghr_mem,
        rb_anchor, TAGE_TBL_HIST[3], TAGE_TBL_FH1[3]));
      fh_r.tage_t3_tag_fh2 <= TAGE_MAX_FH2'(fold_ghr(ghr_mem,
        rb_anchor, TAGE_TBL_HIST[3], TAGE_TBL_FH2[3]));
      // TAGE T4
      fh_r.tage_t4_idx_fh  <= TAGE_MAX_FH'(fold_ghr(ghr_mem,
        rb_anchor, TAGE_TBL_HIST[4], TAGE_TBL_FH[4]));
      fh_r.tage_t4_tag_fh1 <= TAGE_MAX_FH1'(fold_ghr(ghr_mem,
        rb_anchor, TAGE_TBL_HIST[4], TAGE_TBL_FH1[4]));
      fh_r.tage_t4_tag_fh2 <= TAGE_MAX_FH2'(fold_ghr(ghr_mem,
        rb_anchor, TAGE_TBL_HIST[4], TAGE_TBL_FH2[4]));
      // ITTAGE IT1
      fh_r.it_t1_idx_fh    <= IT_MAX_FH'(fold_ghr(ghr_mem,
        rb_anchor, IT_TBL_HIST[1], IT_TBL_FH[1]));
      fh_r.it_t1_tag_fh1   <= IT_MAX_FH1'(fold_ghr(ghr_mem,
        rb_anchor, IT_TBL_HIST[1], IT_TBL_FH1[1]));
      fh_r.it_t1_tag_fh2   <= IT_MAX_FH2'(fold_ghr(ghr_mem,
        rb_anchor, IT_TBL_HIST[1], IT_TBL_FH2[1]));
      // ITTAGE IT2
      fh_r.it_t2_idx_fh    <= IT_MAX_FH'(fold_ghr(ghr_mem,
        rb_anchor, IT_TBL_HIST[2], IT_TBL_FH[2]));
      fh_r.it_t2_tag_fh1   <= IT_MAX_FH1'(fold_ghr(ghr_mem,
        rb_anchor, IT_TBL_HIST[2], IT_TBL_FH1[2]));
      fh_r.it_t2_tag_fh2   <= IT_MAX_FH2'(fold_ghr(ghr_mem,
        rb_anchor, IT_TBL_HIST[2], IT_TBL_FH2[2]));
      // ITTAGE IT3
      fh_r.it_t3_idx_fh    <= IT_MAX_FH'(fold_ghr(ghr_mem,
        rb_anchor, IT_TBL_HIST[3], IT_TBL_FH[3]));
      fh_r.it_t3_tag_fh1   <= IT_MAX_FH1'(fold_ghr(ghr_mem,
        rb_anchor, IT_TBL_HIST[3], IT_TBL_FH1[3]));
      fh_r.it_t3_tag_fh2   <= IT_MAX_FH2'(fold_ghr(ghr_mem,
        rb_anchor, IT_TBL_HIST[3], IT_TBL_FH2[3]));
      // ITTAGE IT4
      fh_r.it_t4_idx_fh    <= IT_MAX_FH'(fold_ghr(ghr_mem,
        rb_anchor, IT_TBL_HIST[4], IT_TBL_FH[4]));
      fh_r.it_t4_tag_fh1   <= IT_MAX_FH1'(fold_ghr(ghr_mem,
        rb_anchor, IT_TBL_HIST[4], IT_TBL_FH1[4]));
      fh_r.it_t4_tag_fh2   <= IT_MAX_FH2'(fold_ghr(ghr_mem,
        rb_anchor, IT_TBL_HIST[4], IT_TBL_FH2[4]));
      // SC ST1-ST3 (H = W = SC_TBL_HIST)
      fh_r.sc_t1_idx_fh    <= SC_MAX_FH'(fold_ghr(ghr_mem,
        rb_anchor, SC_TBL_HIST[1], SC_TBL_HIST[1]));
      fh_r.sc_t2_idx_fh    <= SC_MAX_FH'(fold_ghr(ghr_mem,
        rb_anchor, SC_TBL_HIST[2], SC_TBL_HIST[2]));
      fh_r.sc_t3_idx_fh    <= SC_MAX_FH'(fold_ghr(ghr_mem,
        rb_anchor, SC_TBL_HIST[3], SC_TBL_HIST[3]));

    end else begin : nrm
      // -- Advance the module-owned pointer by num_branches this
      // cycle (0 holds, 1 or 2 advance), modulo buffer width.
      // nxt_*ptr is the POST-advance live pointer (the next write
      // address). The checkpoint stores this post-advance value so a
      // later rollback restores the pointer to where the next write
      // continues, and recomputes folds from one position behind it
      // (rb_anchor = ckpt - 1, the newest history bit of the bundle).
      logic [GHIST_PTR_BITS-1:0] nxt_gptr;
      logic [PHIST_PTR_BITS-1:0] nxt_pptr;
      nxt_gptr = GHIST_PTR_BITS'(
        (int'(ghist_ptr_r) + int'(num_branches)) % GHR_WIDTH);
      nxt_pptr = PHIST_PTR_BITS'(
        (int'(phist_ptr_r) + int'(num_branches)) % PHR_WIDTH);
      ghist_ptr_r <= nxt_gptr;
      phist_ptr_r <= nxt_pptr;

      // -- Normal update, slot 0
      if (num_branches >= 2'd1) begin
        ghr_mem[ghist_ptr_r]  <= pred_taken[0];
        phr_mem[phist_ptr_r]  <= path_bit_0;

        // TAGE T1
        fh_r.tage_t1_idx_fh  <= TAGE_MAX_FH'(fold_step(
          64'(fh_r.tage_t1_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[1], TAGE_TBL_FH[1]));
        fh_r.tage_t1_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          64'(fh_r.tage_t1_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[1], TAGE_TBL_FH1[1]));
        fh_r.tage_t1_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          64'(fh_r.tage_t1_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[1], TAGE_TBL_FH2[1]));
        // TAGE T2
        fh_r.tage_t2_idx_fh  <= TAGE_MAX_FH'(fold_step(
          64'(fh_r.tage_t2_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[2], TAGE_TBL_FH[2]));
        fh_r.tage_t2_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          64'(fh_r.tage_t2_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[2], TAGE_TBL_FH1[2]));
        fh_r.tage_t2_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          64'(fh_r.tage_t2_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[2], TAGE_TBL_FH2[2]));
        // TAGE T3
        fh_r.tage_t3_idx_fh  <= TAGE_MAX_FH'(fold_step(
          64'(fh_r.tage_t3_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[3], TAGE_TBL_FH[3]));
        fh_r.tage_t3_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          64'(fh_r.tage_t3_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[3], TAGE_TBL_FH1[3]));
        fh_r.tage_t3_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          64'(fh_r.tage_t3_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[3], TAGE_TBL_FH2[3]));
        // TAGE T4
        fh_r.tage_t4_idx_fh  <= TAGE_MAX_FH'(fold_step(
          64'(fh_r.tage_t4_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[4], TAGE_TBL_FH[4]));
        fh_r.tage_t4_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          64'(fh_r.tage_t4_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[4], TAGE_TBL_FH1[4]));
        fh_r.tage_t4_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          64'(fh_r.tage_t4_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[4], TAGE_TBL_FH2[4]));
        // ITTAGE IT1
        fh_r.it_t1_idx_fh  <= IT_MAX_FH'(fold_step(
          64'(fh_r.it_t1_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[1], IT_TBL_FH[1]));
        fh_r.it_t1_tag_fh1 <= IT_MAX_FH1'(fold_step(
          64'(fh_r.it_t1_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[1], IT_TBL_FH1[1]));
        fh_r.it_t1_tag_fh2 <= IT_MAX_FH2'(fold_step(
          64'(fh_r.it_t1_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[1], IT_TBL_FH2[1]));
        // ITTAGE IT2
        fh_r.it_t2_idx_fh  <= IT_MAX_FH'(fold_step(
          64'(fh_r.it_t2_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[2], IT_TBL_FH[2]));
        fh_r.it_t2_tag_fh1 <= IT_MAX_FH1'(fold_step(
          64'(fh_r.it_t2_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[2], IT_TBL_FH1[2]));
        fh_r.it_t2_tag_fh2 <= IT_MAX_FH2'(fold_step(
          64'(fh_r.it_t2_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[2], IT_TBL_FH2[2]));
        // ITTAGE IT3
        fh_r.it_t3_idx_fh  <= IT_MAX_FH'(fold_step(
          64'(fh_r.it_t3_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[3], IT_TBL_FH[3]));
        fh_r.it_t3_tag_fh1 <= IT_MAX_FH1'(fold_step(
          64'(fh_r.it_t3_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[3], IT_TBL_FH1[3]));
        fh_r.it_t3_tag_fh2 <= IT_MAX_FH2'(fold_step(
          64'(fh_r.it_t3_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[3], IT_TBL_FH2[3]));
        // ITTAGE IT4
        fh_r.it_t4_idx_fh  <= IT_MAX_FH'(fold_step(
          64'(fh_r.it_t4_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[4], IT_TBL_FH[4]));
        fh_r.it_t4_tag_fh1 <= IT_MAX_FH1'(fold_step(
          64'(fh_r.it_t4_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[4], IT_TBL_FH1[4]));
        fh_r.it_t4_tag_fh2 <= IT_MAX_FH2'(fold_step(
          64'(fh_r.it_t4_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[4], IT_TBL_FH2[4]));
        // SC ST1-ST3 (H = W = SC_TBL_HIST)
        fh_r.sc_t1_idx_fh  <= SC_MAX_FH'(fold_step(
          64'(fh_r.sc_t1_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-SC_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          SC_TBL_HIST[1], SC_TBL_HIST[1]));
        fh_r.sc_t2_idx_fh  <= SC_MAX_FH'(fold_step(
          64'(fh_r.sc_t2_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-SC_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          SC_TBL_HIST[2], SC_TBL_HIST[2]));
        fh_r.sc_t3_idx_fh  <= SC_MAX_FH'(fold_step(
          64'(fh_r.sc_t3_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr_r)-SC_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          SC_TBL_HIST[3], SC_TBL_HIST[3]));
      end

      // -- Slot 1: second branch, applied on top of slot-0 result.
      // Uses ghist_ptr_r+1 as the write address. Each fold takes two
      // incremental steps (slot 0 then slot 1); the slot-1 step uses
      // the same single fold definition on the once-shifted register,
      // removing its leaving bit at (H-1) % W.
      if (num_branches == 2'd2) begin
        ghr_mem[(int'(ghist_ptr_r)+1) % GHR_WIDTH] <= pred_taken[1];
        phr_mem[(int'(phist_ptr_r)+1) % PHR_WIDTH] <= path_bit_1;

        // TAGE T1
        fh_r.tage_t1_idx_fh  <= TAGE_MAX_FH'(fold_step(
          fold_step(64'(fh_r.tage_t1_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
            TAGE_TBL_HIST[1], TAGE_TBL_FH[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-TAGE_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[1], TAGE_TBL_FH[1]));
        fh_r.tage_t1_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          fold_step(64'(fh_r.tage_t1_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
            TAGE_TBL_HIST[1], TAGE_TBL_FH1[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-TAGE_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[1], TAGE_TBL_FH1[1]));
        fh_r.tage_t1_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          fold_step(64'(fh_r.tage_t1_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
            TAGE_TBL_HIST[1], TAGE_TBL_FH2[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-TAGE_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[1], TAGE_TBL_FH2[1]));
        // TAGE T2
        fh_r.tage_t2_idx_fh  <= TAGE_MAX_FH'(fold_step(
          fold_step(64'(fh_r.tage_t2_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
            TAGE_TBL_HIST[2], TAGE_TBL_FH[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-TAGE_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[2], TAGE_TBL_FH[2]));
        fh_r.tage_t2_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          fold_step(64'(fh_r.tage_t2_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
            TAGE_TBL_HIST[2], TAGE_TBL_FH1[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-TAGE_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[2], TAGE_TBL_FH1[2]));
        fh_r.tage_t2_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          fold_step(64'(fh_r.tage_t2_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
            TAGE_TBL_HIST[2], TAGE_TBL_FH2[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-TAGE_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[2], TAGE_TBL_FH2[2]));
        // TAGE T3
        fh_r.tage_t3_idx_fh  <= TAGE_MAX_FH'(fold_step(
          fold_step(64'(fh_r.tage_t3_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
            TAGE_TBL_HIST[3], TAGE_TBL_FH[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-TAGE_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[3], TAGE_TBL_FH[3]));
        fh_r.tage_t3_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          fold_step(64'(fh_r.tage_t3_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
            TAGE_TBL_HIST[3], TAGE_TBL_FH1[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-TAGE_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[3], TAGE_TBL_FH1[3]));
        fh_r.tage_t3_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          fold_step(64'(fh_r.tage_t3_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
            TAGE_TBL_HIST[3], TAGE_TBL_FH2[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-TAGE_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[3], TAGE_TBL_FH2[3]));
        // TAGE T4
        fh_r.tage_t4_idx_fh  <= TAGE_MAX_FH'(fold_step(
          fold_step(64'(fh_r.tage_t4_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
            TAGE_TBL_HIST[4], TAGE_TBL_FH[4]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-TAGE_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[4], TAGE_TBL_FH[4]));
        fh_r.tage_t4_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          fold_step(64'(fh_r.tage_t4_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
            TAGE_TBL_HIST[4], TAGE_TBL_FH1[4]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-TAGE_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[4], TAGE_TBL_FH1[4]));
        fh_r.tage_t4_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          fold_step(64'(fh_r.tage_t4_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-TAGE_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
            TAGE_TBL_HIST[4], TAGE_TBL_FH2[4]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-TAGE_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
          TAGE_TBL_HIST[4], TAGE_TBL_FH2[4]));
        // ITTAGE IT1
        fh_r.it_t1_idx_fh  <= IT_MAX_FH'(fold_step(
          fold_step(64'(fh_r.it_t1_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
            IT_TBL_HIST[1], IT_TBL_FH[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-IT_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[1], IT_TBL_FH[1]));
        fh_r.it_t1_tag_fh1 <= IT_MAX_FH1'(fold_step(
          fold_step(64'(fh_r.it_t1_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
            IT_TBL_HIST[1], IT_TBL_FH1[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-IT_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[1], IT_TBL_FH1[1]));
        fh_r.it_t1_tag_fh2 <= IT_MAX_FH2'(fold_step(
          fold_step(64'(fh_r.it_t1_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
            IT_TBL_HIST[1], IT_TBL_FH2[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-IT_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[1], IT_TBL_FH2[1]));
        // ITTAGE IT2
        fh_r.it_t2_idx_fh  <= IT_MAX_FH'(fold_step(
          fold_step(64'(fh_r.it_t2_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
            IT_TBL_HIST[2], IT_TBL_FH[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-IT_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[2], IT_TBL_FH[2]));
        fh_r.it_t2_tag_fh1 <= IT_MAX_FH1'(fold_step(
          fold_step(64'(fh_r.it_t2_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
            IT_TBL_HIST[2], IT_TBL_FH1[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-IT_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[2], IT_TBL_FH1[2]));
        fh_r.it_t2_tag_fh2 <= IT_MAX_FH2'(fold_step(
          fold_step(64'(fh_r.it_t2_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
            IT_TBL_HIST[2], IT_TBL_FH2[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-IT_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[2], IT_TBL_FH2[2]));
        // ITTAGE IT3
        fh_r.it_t3_idx_fh  <= IT_MAX_FH'(fold_step(
          fold_step(64'(fh_r.it_t3_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
            IT_TBL_HIST[3], IT_TBL_FH[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-IT_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[3], IT_TBL_FH[3]));
        fh_r.it_t3_tag_fh1 <= IT_MAX_FH1'(fold_step(
          fold_step(64'(fh_r.it_t3_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
            IT_TBL_HIST[3], IT_TBL_FH1[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-IT_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[3], IT_TBL_FH1[3]));
        fh_r.it_t3_tag_fh2 <= IT_MAX_FH2'(fold_step(
          fold_step(64'(fh_r.it_t3_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
            IT_TBL_HIST[3], IT_TBL_FH2[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-IT_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[3], IT_TBL_FH2[3]));
        // ITTAGE IT4
        fh_r.it_t4_idx_fh  <= IT_MAX_FH'(fold_step(
          fold_step(64'(fh_r.it_t4_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
            IT_TBL_HIST[4], IT_TBL_FH[4]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-IT_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[4], IT_TBL_FH[4]));
        fh_r.it_t4_tag_fh1 <= IT_MAX_FH1'(fold_step(
          fold_step(64'(fh_r.it_t4_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
            IT_TBL_HIST[4], IT_TBL_FH1[4]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-IT_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[4], IT_TBL_FH1[4]));
        fh_r.it_t4_tag_fh2 <= IT_MAX_FH2'(fold_step(
          fold_step(64'(fh_r.it_t4_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-IT_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
            IT_TBL_HIST[4], IT_TBL_FH2[4]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-IT_TBL_HIST[4]+GHR_WIDTH) % GHR_WIDTH],
          IT_TBL_HIST[4], IT_TBL_FH2[4]));
        // SC ST1-ST3 (H = W = SC_TBL_HIST)
        fh_r.sc_t1_idx_fh  <= SC_MAX_FH'(fold_step(
          fold_step(64'(fh_r.sc_t1_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-SC_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
            SC_TBL_HIST[1], SC_TBL_HIST[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-SC_TBL_HIST[1]+GHR_WIDTH) % GHR_WIDTH],
          SC_TBL_HIST[1], SC_TBL_HIST[1]));
        fh_r.sc_t2_idx_fh  <= SC_MAX_FH'(fold_step(
          fold_step(64'(fh_r.sc_t2_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-SC_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
            SC_TBL_HIST[2], SC_TBL_HIST[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-SC_TBL_HIST[2]+GHR_WIDTH) % GHR_WIDTH],
          SC_TBL_HIST[2], SC_TBL_HIST[2]));
        fh_r.sc_t3_idx_fh  <= SC_MAX_FH'(fold_step(
          fold_step(64'(fh_r.sc_t3_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr_r)-SC_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
            SC_TBL_HIST[3], SC_TBL_HIST[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr_r)+1-SC_TBL_HIST[3]+GHR_WIDTH) % GHR_WIDTH],
          SC_TBL_HIST[3], SC_TBL_HIST[3]));
      end

      // Checkpoint write. Captures the POST-advance pointer pair (the
      // next write address for the cycle after this bundle) and
      // exposes it on the snapshot outputs. Rollback restores the
      // pointer to this value and recomputes folds from one position
      // behind it (rb_anchor = ckpt - 1).
      if (ckpt_wr_en) begin
        ckpt_gptr[ckpt_wr_idx] <= nxt_gptr;
        ckpt_pptr[ckpt_wr_idx] <= nxt_pptr;
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
