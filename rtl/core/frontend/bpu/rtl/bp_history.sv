// ===================================================================
// FILE:    bp_history.sv
// DATE:    2026-03-28
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Branch predictor history module.
// Owns GHR (256b) and PHR (32b) circular buffers plus all folded
// histories for TAGE T1-T4, ITTAGE IT1-IT4, and SC ST1-ST3.
// Pointers are driven externally; buffer storage lives here.
// Rollback: accept restored pointer, recompute all folds.
// ===================================================================

import bp_defines_pkg::*;
import bp_structs_pkg::*;
module bp_history
(
  input  logic                         clk,
  input  logic                         rstn,

  // -- External pointer inputs (caller manages advancement)
  input  logic [GHIST_PTR_BITS-1:0]   ghist_ptr,
  input  logic [PHIST_PTR_BITS-1:0]   phist_ptr,

  // -- Prediction update
  // pred_taken[0]/pred_pc[0]: slot 0 (num_branches >= 1)
  // pred_taken[1]/pred_pc[1]: slot 1 (num_branches == 2)
  input  logic [1:0]                   pred_taken,
  input  logic [VA_WIDTH-1:0]          pred_pc  [2],
  input  logic [1:0]                   num_branches,  // 0,1,2

  // -- Rollback: restore to a prior pointer position
  input  logic                         rollback_valid,
  input  logic [GHIST_PTR_BITS-1:0]   rollback_ghist_ptr,
  input  logic [PHIST_PTR_BITS-1:0]   rollback_phist_ptr,

  // -- Checkpoint write (one write port, indexed by FTQ slot)
  input  logic                         ckpt_wr_en,
  input  logic [FTQ_IDX_BITS-1:0]     ckpt_wr_idx,

  // -- Checkpoint read outputs (for FTQ entry construction)
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

  logic [GHIST_PTR_BITS-1:0] ckpt_gptr [FTQ_DEPTH];
  logic [PHIST_PTR_BITS-1:0] ckpt_pptr [FTQ_DEPTH];

  bp_folded_hist_t fh_r;

  // ----------------------------------------------------------------
  // fold_ghr: XOR-fold H bits from ghr_mem[ptr..ptr+H-1] into W bits.
  // Used for rollback recompute. Returns 32b (upper bits zero).
  // ----------------------------------------------------------------
  function automatic logic [31:0] fold_ghr(
    input logic [GHR_WIDTH-1:0] mem,
    input int                   ptr_in,
    input int                   H,
    input int                   W
  );
    logic [31:0] acc;
    int          i, bit_idx, pos;
    acc = 32'b0;
    for (i = 0; i < H; i++) begin
      bit_idx = (ptr_in + i) % GHR_WIDTH;
      pos     = i % W;
      if (mem[bit_idx]) acc[pos] = acc[pos] ^ 1'b1;
    end
    return acc;
  endfunction

  // ----------------------------------------------------------------
  // fold_step: one incremental fold step.
  // new_bit: incoming prediction bit (writes to ghist_ptr).
  // bit_out: bit leaving the fold window (at ghist_ptr + H).
  // Returns updated 32b fold (upper bits zero).
  // ----------------------------------------------------------------
  function automatic logic [31:0] fold_step(
    input logic [31:0] fold_in,
    input logic        new_bit,
    input logic        bit_out,
    input int          W
  );
    logic [31:0] f;
    f    = fold_in;
    f    = (f << 1) | {31'b0, new_bit};
    f[0] = f[0] ^ fold_in[W-1] ^ bit_out;
    f    = f & ((32'b1 << W) - 32'b1);
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
      fh_r           <= '0;
      ckpt_ghist_ptr <= {GHIST_PTR_BITS{1'b0}};
      ckpt_phist_ptr <= {PHIST_PTR_BITS{1'b0}};
      for (idx_i = 0; idx_i < FTQ_DEPTH; idx_i++) begin
        ckpt_gptr[idx_i] <= {GHIST_PTR_BITS{1'b0}};
        ckpt_pptr[idx_i] <= {PHIST_PTR_BITS{1'b0}};
      end

    end else if (rollback_valid) begin
      // Rollback: recompute all folds from ghr_mem at restored ptr.
      // TAGE T1
      fh_r.tage_t1_idx_fh  <= TAGE_MAX_FH'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), TAGE_TBL_HIST[1], TAGE_TBL_FH[1]));
      fh_r.tage_t1_tag_fh1 <= TAGE_MAX_FH1'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), TAGE_TBL_HIST[1], TAGE_TBL_FH1[1]));
      fh_r.tage_t1_tag_fh2 <= TAGE_MAX_FH2'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), TAGE_TBL_HIST[1], TAGE_TBL_FH2[1]));
      // TAGE T2
      fh_r.tage_t2_idx_fh  <= TAGE_MAX_FH'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), TAGE_TBL_HIST[2], TAGE_TBL_FH[2]));
      fh_r.tage_t2_tag_fh1 <= TAGE_MAX_FH1'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), TAGE_TBL_HIST[2], TAGE_TBL_FH1[2]));
      fh_r.tage_t2_tag_fh2 <= TAGE_MAX_FH2'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), TAGE_TBL_HIST[2], TAGE_TBL_FH2[2]));
      // TAGE T3
      fh_r.tage_t3_idx_fh  <= TAGE_MAX_FH'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), TAGE_TBL_HIST[3], TAGE_TBL_FH[3]));
      fh_r.tage_t3_tag_fh1 <= TAGE_MAX_FH1'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), TAGE_TBL_HIST[3], TAGE_TBL_FH1[3]));
      fh_r.tage_t3_tag_fh2 <= TAGE_MAX_FH2'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), TAGE_TBL_HIST[3], TAGE_TBL_FH2[3]));
      // TAGE T4
      fh_r.tage_t4_idx_fh  <= TAGE_MAX_FH'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), TAGE_TBL_HIST[4], TAGE_TBL_FH[4]));
      fh_r.tage_t4_tag_fh1 <= TAGE_MAX_FH1'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), TAGE_TBL_HIST[4], TAGE_TBL_FH1[4]));
      fh_r.tage_t4_tag_fh2 <= TAGE_MAX_FH2'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), TAGE_TBL_HIST[4], TAGE_TBL_FH2[4]));
      // ITTAGE IT1
      fh_r.it_t1_idx_fh    <= IT_MAX_FH'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), IT_TBL_HIST[1], IT_TBL_FH[1]));
      fh_r.it_t1_tag_fh1   <= IT_MAX_FH1'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), IT_TBL_HIST[1], IT_TBL_FH1[1]));
      fh_r.it_t1_tag_fh2   <= IT_MAX_FH2'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), IT_TBL_HIST[1], IT_TBL_FH2[1]));
      // ITTAGE IT2
      fh_r.it_t2_idx_fh    <= IT_MAX_FH'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), IT_TBL_HIST[2], IT_TBL_FH[2]));
      fh_r.it_t2_tag_fh1   <= IT_MAX_FH1'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), IT_TBL_HIST[2], IT_TBL_FH1[2]));
      fh_r.it_t2_tag_fh2   <= IT_MAX_FH2'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), IT_TBL_HIST[2], IT_TBL_FH2[2]));
      // ITTAGE IT3
      fh_r.it_t3_idx_fh    <= IT_MAX_FH'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), IT_TBL_HIST[3], IT_TBL_FH[3]));
      fh_r.it_t3_tag_fh1   <= IT_MAX_FH1'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), IT_TBL_HIST[3], IT_TBL_FH1[3]));
      fh_r.it_t3_tag_fh2   <= IT_MAX_FH2'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), IT_TBL_HIST[3], IT_TBL_FH2[3]));
      // ITTAGE IT4
      fh_r.it_t4_idx_fh    <= IT_MAX_FH'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), IT_TBL_HIST[4], IT_TBL_FH[4]));
      fh_r.it_t4_tag_fh1   <= IT_MAX_FH1'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), IT_TBL_HIST[4], IT_TBL_FH1[4]));
      fh_r.it_t4_tag_fh2   <= IT_MAX_FH2'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), IT_TBL_HIST[4], IT_TBL_FH2[4]));
      // SC ST1-ST3
      fh_r.sc_t1_idx_fh    <= SC_MAX_FH'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), SC_TBL_HIST[1], SC_TBL_HIST[1]));
      fh_r.sc_t2_idx_fh    <= SC_MAX_FH'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), SC_TBL_HIST[2], SC_TBL_HIST[2]));
      fh_r.sc_t3_idx_fh    <= SC_MAX_FH'(fold_ghr(ghr_mem,
        int'(rollback_ghist_ptr), SC_TBL_HIST[3], SC_TBL_HIST[3]));

    end else begin
      // -- Normal update, slot 0
      if (num_branches >= 2'd1) begin
        ghr_mem[ghist_ptr]  <= pred_taken[0];
        phr_mem[phist_ptr]  <= path_bit_0;

        // TAGE T1
        fh_r.tage_t1_idx_fh  <= TAGE_MAX_FH'(fold_step(
          32'(fh_r.tage_t1_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[1]) % GHR_WIDTH],
          TAGE_TBL_FH[1]));
        fh_r.tage_t1_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          32'(fh_r.tage_t1_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[1]) % GHR_WIDTH],
          TAGE_TBL_FH1[1]));
        fh_r.tage_t1_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          32'(fh_r.tage_t1_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[1]) % GHR_WIDTH],
          TAGE_TBL_FH2[1]));
        // TAGE T2
        fh_r.tage_t2_idx_fh  <= TAGE_MAX_FH'(fold_step(
          32'(fh_r.tage_t2_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[2]) % GHR_WIDTH],
          TAGE_TBL_FH[2]));
        fh_r.tage_t2_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          32'(fh_r.tage_t2_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[2]) % GHR_WIDTH],
          TAGE_TBL_FH1[2]));
        fh_r.tage_t2_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          32'(fh_r.tage_t2_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[2]) % GHR_WIDTH],
          TAGE_TBL_FH2[2]));
        // TAGE T3
        fh_r.tage_t3_idx_fh  <= TAGE_MAX_FH'(fold_step(
          32'(fh_r.tage_t3_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[3]) % GHR_WIDTH],
          TAGE_TBL_FH[3]));
        fh_r.tage_t3_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          32'(fh_r.tage_t3_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[3]) % GHR_WIDTH],
          TAGE_TBL_FH1[3]));
        fh_r.tage_t3_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          32'(fh_r.tage_t3_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[3]) % GHR_WIDTH],
          TAGE_TBL_FH2[3]));
        // TAGE T4
        fh_r.tage_t4_idx_fh  <= TAGE_MAX_FH'(fold_step(
          32'(fh_r.tage_t4_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[4]) % GHR_WIDTH],
          TAGE_TBL_FH[4]));
        fh_r.tage_t4_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          32'(fh_r.tage_t4_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[4]) % GHR_WIDTH],
          TAGE_TBL_FH1[4]));
        fh_r.tage_t4_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          32'(fh_r.tage_t4_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[4]) % GHR_WIDTH],
          TAGE_TBL_FH2[4]));
        // ITTAGE IT1
        fh_r.it_t1_idx_fh  <= IT_MAX_FH'(fold_step(
          32'(fh_r.it_t1_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[1]) % GHR_WIDTH],
          IT_TBL_FH[1]));
        fh_r.it_t1_tag_fh1 <= IT_MAX_FH1'(fold_step(
          32'(fh_r.it_t1_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[1]) % GHR_WIDTH],
          IT_TBL_FH1[1]));
        fh_r.it_t1_tag_fh2 <= IT_MAX_FH2'(fold_step(
          32'(fh_r.it_t1_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[1]) % GHR_WIDTH],
          IT_TBL_FH2[1]));
        // ITTAGE IT2
        fh_r.it_t2_idx_fh  <= IT_MAX_FH'(fold_step(
          32'(fh_r.it_t2_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[2]) % GHR_WIDTH],
          IT_TBL_FH[2]));
        fh_r.it_t2_tag_fh1 <= IT_MAX_FH1'(fold_step(
          32'(fh_r.it_t2_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[2]) % GHR_WIDTH],
          IT_TBL_FH1[2]));
        fh_r.it_t2_tag_fh2 <= IT_MAX_FH2'(fold_step(
          32'(fh_r.it_t2_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[2]) % GHR_WIDTH],
          IT_TBL_FH2[2]));
        // ITTAGE IT3
        fh_r.it_t3_idx_fh  <= IT_MAX_FH'(fold_step(
          32'(fh_r.it_t3_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[3]) % GHR_WIDTH],
          IT_TBL_FH[3]));
        fh_r.it_t3_tag_fh1 <= IT_MAX_FH1'(fold_step(
          32'(fh_r.it_t3_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[3]) % GHR_WIDTH],
          IT_TBL_FH1[3]));
        fh_r.it_t3_tag_fh2 <= IT_MAX_FH2'(fold_step(
          32'(fh_r.it_t3_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[3]) % GHR_WIDTH],
          IT_TBL_FH2[3]));
        // ITTAGE IT4
        fh_r.it_t4_idx_fh  <= IT_MAX_FH'(fold_step(
          32'(fh_r.it_t4_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[4]) % GHR_WIDTH],
          IT_TBL_FH[4]));
        fh_r.it_t4_tag_fh1 <= IT_MAX_FH1'(fold_step(
          32'(fh_r.it_t4_tag_fh1), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[4]) % GHR_WIDTH],
          IT_TBL_FH1[4]));
        fh_r.it_t4_tag_fh2 <= IT_MAX_FH2'(fold_step(
          32'(fh_r.it_t4_tag_fh2), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[4]) % GHR_WIDTH],
          IT_TBL_FH2[4]));
        // SC ST1-ST3
        fh_r.sc_t1_idx_fh  <= SC_MAX_FH'(fold_step(
          32'(fh_r.sc_t1_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+SC_TBL_HIST[1]) % GHR_WIDTH],
          SC_TBL_HIST[1]));
        fh_r.sc_t2_idx_fh  <= SC_MAX_FH'(fold_step(
          32'(fh_r.sc_t2_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+SC_TBL_HIST[2]) % GHR_WIDTH],
          SC_TBL_HIST[2]));
        fh_r.sc_t3_idx_fh  <= SC_MAX_FH'(fold_step(
          32'(fh_r.sc_t3_idx_fh), pred_taken[0],
          ghr_mem[(int'(ghist_ptr)+SC_TBL_HIST[3]) % GHR_WIDTH],
          SC_TBL_HIST[3]));
      end

      // -- Slot 1: second branch, applied on top of slot-0 result.
      // Uses ghist_ptr+1 as the write address.
      if (num_branches == 2'd2) begin
        ghr_mem[(int'(ghist_ptr)+1) % GHR_WIDTH] <= pred_taken[1];
        phr_mem[(int'(phist_ptr)+1) % PHR_WIDTH] <= path_bit_1;

        // TAGE T1
        fh_r.tage_t1_idx_fh  <= TAGE_MAX_FH'(fold_step(
          fold_step(32'(fh_r.tage_t1_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[1]) % GHR_WIDTH],
            TAGE_TBL_FH[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+TAGE_TBL_HIST[1]) % GHR_WIDTH],
          TAGE_TBL_FH[1]));
        fh_r.tage_t1_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          fold_step(32'(fh_r.tage_t1_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[1]) % GHR_WIDTH],
            TAGE_TBL_FH1[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+TAGE_TBL_HIST[1]) % GHR_WIDTH],
          TAGE_TBL_FH1[1]));
        fh_r.tage_t1_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          fold_step(32'(fh_r.tage_t1_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[1]) % GHR_WIDTH],
            TAGE_TBL_FH2[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+TAGE_TBL_HIST[1]) % GHR_WIDTH],
          TAGE_TBL_FH2[1]));
        // TAGE T2
        fh_r.tage_t2_idx_fh  <= TAGE_MAX_FH'(fold_step(
          fold_step(32'(fh_r.tage_t2_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[2]) % GHR_WIDTH],
            TAGE_TBL_FH[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+TAGE_TBL_HIST[2]) % GHR_WIDTH],
          TAGE_TBL_FH[2]));
        fh_r.tage_t2_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          fold_step(32'(fh_r.tage_t2_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[2]) % GHR_WIDTH],
            TAGE_TBL_FH1[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+TAGE_TBL_HIST[2]) % GHR_WIDTH],
          TAGE_TBL_FH1[2]));
        fh_r.tage_t2_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          fold_step(32'(fh_r.tage_t2_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[2]) % GHR_WIDTH],
            TAGE_TBL_FH2[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+TAGE_TBL_HIST[2]) % GHR_WIDTH],
          TAGE_TBL_FH2[2]));
        // TAGE T3
        fh_r.tage_t3_idx_fh  <= TAGE_MAX_FH'(fold_step(
          fold_step(32'(fh_r.tage_t3_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[3]) % GHR_WIDTH],
            TAGE_TBL_FH[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+TAGE_TBL_HIST[3]) % GHR_WIDTH],
          TAGE_TBL_FH[3]));
        fh_r.tage_t3_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          fold_step(32'(fh_r.tage_t3_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[3]) % GHR_WIDTH],
            TAGE_TBL_FH1[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+TAGE_TBL_HIST[3]) % GHR_WIDTH],
          TAGE_TBL_FH1[3]));
        fh_r.tage_t3_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          fold_step(32'(fh_r.tage_t3_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[3]) % GHR_WIDTH],
            TAGE_TBL_FH2[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+TAGE_TBL_HIST[3]) % GHR_WIDTH],
          TAGE_TBL_FH2[3]));
        // TAGE T4
        fh_r.tage_t4_idx_fh  <= TAGE_MAX_FH'(fold_step(
          fold_step(32'(fh_r.tage_t4_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[4]) % GHR_WIDTH],
            TAGE_TBL_FH[4]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+TAGE_TBL_HIST[4]) % GHR_WIDTH],
          TAGE_TBL_FH[4]));
        fh_r.tage_t4_tag_fh1 <= TAGE_MAX_FH1'(fold_step(
          fold_step(32'(fh_r.tage_t4_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[4]) % GHR_WIDTH],
            TAGE_TBL_FH1[4]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+TAGE_TBL_HIST[4]) % GHR_WIDTH],
          TAGE_TBL_FH1[4]));
        fh_r.tage_t4_tag_fh2 <= TAGE_MAX_FH2'(fold_step(
          fold_step(32'(fh_r.tage_t4_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+TAGE_TBL_HIST[4]) % GHR_WIDTH],
            TAGE_TBL_FH2[4]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+TAGE_TBL_HIST[4]) % GHR_WIDTH],
          TAGE_TBL_FH2[4]));
        // ITTAGE IT1
        fh_r.it_t1_idx_fh  <= IT_MAX_FH'(fold_step(
          fold_step(32'(fh_r.it_t1_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[1]) % GHR_WIDTH],
            IT_TBL_FH[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+IT_TBL_HIST[1]) % GHR_WIDTH],
          IT_TBL_FH[1]));
        fh_r.it_t1_tag_fh1 <= IT_MAX_FH1'(fold_step(
          fold_step(32'(fh_r.it_t1_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[1]) % GHR_WIDTH],
            IT_TBL_FH1[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+IT_TBL_HIST[1]) % GHR_WIDTH],
          IT_TBL_FH1[1]));
        fh_r.it_t1_tag_fh2 <= IT_MAX_FH2'(fold_step(
          fold_step(32'(fh_r.it_t1_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[1]) % GHR_WIDTH],
            IT_TBL_FH2[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+IT_TBL_HIST[1]) % GHR_WIDTH],
          IT_TBL_FH2[1]));
        // ITTAGE IT2
        fh_r.it_t2_idx_fh  <= IT_MAX_FH'(fold_step(
          fold_step(32'(fh_r.it_t2_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[2]) % GHR_WIDTH],
            IT_TBL_FH[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+IT_TBL_HIST[2]) % GHR_WIDTH],
          IT_TBL_FH[2]));
        fh_r.it_t2_tag_fh1 <= IT_MAX_FH1'(fold_step(
          fold_step(32'(fh_r.it_t2_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[2]) % GHR_WIDTH],
            IT_TBL_FH1[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+IT_TBL_HIST[2]) % GHR_WIDTH],
          IT_TBL_FH1[2]));
        fh_r.it_t2_tag_fh2 <= IT_MAX_FH2'(fold_step(
          fold_step(32'(fh_r.it_t2_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[2]) % GHR_WIDTH],
            IT_TBL_FH2[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+IT_TBL_HIST[2]) % GHR_WIDTH],
          IT_TBL_FH2[2]));
        // ITTAGE IT3
        fh_r.it_t3_idx_fh  <= IT_MAX_FH'(fold_step(
          fold_step(32'(fh_r.it_t3_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[3]) % GHR_WIDTH],
            IT_TBL_FH[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+IT_TBL_HIST[3]) % GHR_WIDTH],
          IT_TBL_FH[3]));
        fh_r.it_t3_tag_fh1 <= IT_MAX_FH1'(fold_step(
          fold_step(32'(fh_r.it_t3_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[3]) % GHR_WIDTH],
            IT_TBL_FH1[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+IT_TBL_HIST[3]) % GHR_WIDTH],
          IT_TBL_FH1[3]));
        fh_r.it_t3_tag_fh2 <= IT_MAX_FH2'(fold_step(
          fold_step(32'(fh_r.it_t3_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[3]) % GHR_WIDTH],
            IT_TBL_FH2[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+IT_TBL_HIST[3]) % GHR_WIDTH],
          IT_TBL_FH2[3]));
        // ITTAGE IT4
        fh_r.it_t4_idx_fh  <= IT_MAX_FH'(fold_step(
          fold_step(32'(fh_r.it_t4_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[4]) % GHR_WIDTH],
            IT_TBL_FH[4]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+IT_TBL_HIST[4]) % GHR_WIDTH],
          IT_TBL_FH[4]));
        fh_r.it_t4_tag_fh1 <= IT_MAX_FH1'(fold_step(
          fold_step(32'(fh_r.it_t4_tag_fh1), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[4]) % GHR_WIDTH],
            IT_TBL_FH1[4]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+IT_TBL_HIST[4]) % GHR_WIDTH],
          IT_TBL_FH1[4]));
        fh_r.it_t4_tag_fh2 <= IT_MAX_FH2'(fold_step(
          fold_step(32'(fh_r.it_t4_tag_fh2), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+IT_TBL_HIST[4]) % GHR_WIDTH],
            IT_TBL_FH2[4]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+IT_TBL_HIST[4]) % GHR_WIDTH],
          IT_TBL_FH2[4]));
        // SC ST1-ST3
        fh_r.sc_t1_idx_fh  <= SC_MAX_FH'(fold_step(
          fold_step(32'(fh_r.sc_t1_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+SC_TBL_HIST[1]) % GHR_WIDTH],
            SC_TBL_HIST[1]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+SC_TBL_HIST[1]) % GHR_WIDTH],
          SC_TBL_HIST[1]));
        fh_r.sc_t2_idx_fh  <= SC_MAX_FH'(fold_step(
          fold_step(32'(fh_r.sc_t2_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+SC_TBL_HIST[2]) % GHR_WIDTH],
            SC_TBL_HIST[2]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+SC_TBL_HIST[2]) % GHR_WIDTH],
          SC_TBL_HIST[2]));
        fh_r.sc_t3_idx_fh  <= SC_MAX_FH'(fold_step(
          fold_step(32'(fh_r.sc_t3_idx_fh), pred_taken[0],
            ghr_mem[(int'(ghist_ptr)+SC_TBL_HIST[3]) % GHR_WIDTH],
            SC_TBL_HIST[3]),
          pred_taken[1],
          ghr_mem[(int'(ghist_ptr)+1+SC_TBL_HIST[3]) % GHR_WIDTH],
          SC_TBL_HIST[3]));
      end

      // Checkpoint write
      if (ckpt_wr_en) begin
        ckpt_gptr[ckpt_wr_idx] <= ghist_ptr;
        ckpt_pptr[ckpt_wr_idx] <= phist_ptr;
        ckpt_ghist_ptr         <= ghist_ptr;
        ckpt_phist_ptr         <= phist_ptr;
      end
    end
  end : seq_main

  // ----------------------------------------------------------------
  // Combinational output assignments
  // ----------------------------------------------------------------
  assign ghr_buf = ghr_mem;
  assign phr_buf = phr_mem;
  assign folded  = fh_r;

endmodule : bp_history
