// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for bp_history (BP-122, TD#170): the BP-121 fix in
// this unit, the corrected rollback (bp_history_decisions.md 3.5 as
// ruled by Jeff in BP-121; BP-121 D14).
//
// BOUND BY MODULE NAME, never by instance name (TD#109). The bind
// reads the port list and makes no hierarchical reference.
//
// Each property compares the history state the module presents after
// a rollback with the rollback inputs of the cycle before, held in
// this module's own registers.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module bp_history_assert (
  input logic                      clk,
  input logic                      rstn,
  input logic                      ckpt_wr_en,
  input logic [FTQ_IDX_BITS-1:0]   ckpt_wr_idx,
  input logic                      rollback_valid,
  input logic [FTQ_IDX_BITS-1:0]   rollback_ckpt_idx,
  input logic                      rollback_corr,
  input logic [1:0]                rollback_n,
  input logic [1:0]                rollback_tkn,
  input logic [1:0]                rollback_pbit,
  input logic [GHIST_PTR_BITS-1:0] ghist_ptr,
  input logic [PHIST_PTR_BITS-1:0] phist_ptr,
  input logic [GHR_WIDTH-1:0]      ghr_buf,
  input logic [PHR_WIDTH-1:0]      phr_buf
);

  // The corrected rollback of the cycle before.
  logic                    r_corr;
  logic [1:0]              r_n;
  logic [1:0]              r_tkn;
  logic [1:0]              r_pbit;
  // The checkpoint a corrected rollback rewrote, armed until the
  // checkpoint of that index is written again at allocation.
  logic                    r_ck_val;
  logic                    r_ck_arm;
  logic [FTQ_IDX_BITS-1:0] r_ck_idx;
  logic [GHIST_PTR_BITS-1:0] r_ck_ptr;
  // A plain rollback of the cycle before named the armed index.
  logic                    r_plain_hit;

  always_ff @(posedge clk or negedge rstn) begin : hist
    if (!rstn) begin
      r_corr      <= 1'b0;
      r_n         <= '0;
      r_tkn       <= '0;
      r_pbit      <= '0;
      r_ck_val    <= 1'b0;
      r_ck_arm    <= 1'b0;
      r_ck_idx    <= '0;
      r_ck_ptr    <= '0;
      r_plain_hit <= 1'b0;
    end else begin
      r_corr      <= rollback_valid && rollback_corr &&
                     (rollback_n != 2'd0);
      r_n         <= rollback_n;
      r_tkn       <= rollback_tkn;
      r_pbit      <= rollback_pbit;
      r_plain_hit <= rollback_valid && !rollback_corr && r_ck_val &&
                     (rollback_ckpt_idx == r_ck_idx) &&
                     !(ckpt_wr_en && (ckpt_wr_idx == r_ck_idx));
      // Arm on a corrected rollback; the pointer it leaves is taken
      // the cycle after (r_ck_arm).
      if (rollback_valid && rollback_corr) begin
        r_ck_arm <= 1'b1;
        r_ck_val <= 1'b0;
        r_ck_idx <= rollback_ckpt_idx;
      end else begin
        r_ck_arm <= 1'b0;
        if (r_ck_arm) begin
          r_ck_val <= 1'b1;
          r_ck_ptr <= ghist_ptr;
        end
        if (ckpt_wr_en && (ckpt_wr_idx == r_ck_idx)) r_ck_val <= 1'b0;
      end
    end
  end

  // H1  BP-121 D14 (m13). After a corrected rollback the newest
  //     history bits are the corrected bundle: the bit just below the
  //     live pointer is the bundle's last direction, and with two bits
  //     the one below it is the first; the same for the path bits.
  //     Before BP-121 the pointer was restored past the predicted
  //     bundle, so the mispredicted direction stayed in the history.
  property p_corrected_newest;
    @(posedge clk) disable iff (!rstn)
      r_corr |->
        (ghr_buf[ghist_ptr - GHIST_PTR_BITS'(1)] == r_tkn[r_n[1]]) &&
        (phr_buf[phist_ptr - PHIST_PTR_BITS'(1)] == r_pbit[r_n[1]]) &&
        ((r_n != 2'd2) ||
         ((ghr_buf[ghist_ptr - GHIST_PTR_BITS'(2)] == r_tkn[0]) &&
          (phr_buf[phist_ptr - PHIST_PTR_BITS'(2)] == r_pbit[0])));
  endproperty

  // H2  BP-121 D14. The corrected rollback REWRITES the entry's
  //     checkpoint: a later plain rollback to the same entry, before
  //     the entry is allocated again, restores the corrected pointer,
  //     not the one the prediction left.
  property p_checkpoint_rewritten;
    @(posedge clk) disable iff (!rstn)
      r_plain_hit |-> (ghist_ptr == r_ck_ptr);
  endproperty

  a_corrected_newest:     assert property (p_corrected_newest)
    else $error("H1 the newest history bits are not the corrected bundle");
  a_checkpoint_rewritten: assert property (p_checkpoint_rewritten)
    else $error("H2 a rollback restored a checkpoint the correction left");

endmodule : bp_history_assert

// Bind BY MODULE NAME.
bind bp_history bp_history_assert u_assert (
  .clk               (clk),
  .rstn              (rstn),
  .ckpt_wr_en        (ckpt_wr_en),
  .ckpt_wr_idx       (ckpt_wr_idx),
  .rollback_valid    (rollback_valid),
  .rollback_ckpt_idx (rollback_ckpt_idx),
  .rollback_corr     (rollback_corr),
  .rollback_n        (rollback_n),
  .rollback_tkn      (rollback_tkn),
  .rollback_pbit     (rollback_pbit),
  .ghist_ptr         (ghist_ptr),
  .phist_ptr         (phist_ptr),
  .ghr_buf           (ghr_buf),
  .phr_buf           (phr_buf)
);
