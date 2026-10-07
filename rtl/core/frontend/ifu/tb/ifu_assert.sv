// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for the ifu top (BP-116): the rules that span more
// than one owner, stated on the unit's boundary ports.
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
//
//   U1  IF-6 / IF-7   an L1I identifier is reused only after its
//                     response lands
//   U2  IFU-19        the writeback returns the generation the request
//                     carried, unchanged
//   U3  IFU-32        RESTATED by BP-118 (TD#134). It was the TD#134
//                     stub "no flush while an L1I or ITLB request is
//                     outstanding". It is now: after the flush cycle,
//                     no writeback is presented for a block the flush
//                     dropped
//   U4  IFU-31        no new block is accepted for translation while a
//                     lookup of a block the flush dropped is still in
//                     flight, including the cycle its response arrives
//
// U3 and U4 decide survival themselves, from ftq_ifu_flush_idx and
// ftq_ifu_commit_ptr (IFU-28), and know which blocks the unit holds
// only from the FTQ handshakes and the writeback.
//
// Each model is kept here from the boundary handshakes of earlier
// cycles; none reads a register inside the unit.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ifu_assert (
  input logic                    clk,
  input logic                    rstn,
  input logic                    ftq_ifu_req_val,
  input logic                    ftq_ifu_req_rdy,
  input logic [FTQ_IDX_BITS-1:0] ftq_ifu_idx,
  input logic                    ftq_ifu_gen,
  input logic                    ftq_ifu_flush_val,
  input logic [FTQ_IDX_BITS-1:0] ftq_ifu_flush_idx,
  input logic [FTQ_IDX_BITS-1:0] ftq_ifu_commit_ptr,
  input logic                    ftq_ifu_xlate_val,
  input logic                    ftq_ifu_xlate_rdy,
  input logic [FTQ_IDX_BITS-1:0] ftq_ifu_xlate_idx,
  input logic                    ifu_ftq_pdwb_val,
  input logic [FTQ_IDX_BITS-1:0] ifu_ftq_pdwb_idx,
  input logic                    ifu_ftq_pdwb_gen,
  input logic                    ifu_l1i_req_val,
  input logic                    ifu_l1i_req_rdy,
  input logic [REQ_ID_BITS-1:0]  ifu_l1i_req_id,
  input logic                    l1i_ifu_rsp_val,
  input logic [REQ_ID_BITS-1:0]  l1i_ifu_rsp_id,
  input logic                    ifu_itlb_req_val,
  input logic                    ifu_itlb_req_rdy,
  input logic                    ifu_itlb_tag,
  input logic                    itlb_ifu_rsp_val,
  input logic                    itlb_ifu_tag
);

  logic [MAX_OUTSTANDING-1:0] r_id_out;   // L1I ids in flight
  logic [FTQ_DEPTH-1:0]       r_gen;      // gen accepted per index
  logic [1:0]                 r_itlb_out; // ITLB lookups, per tag
  // U3. Blocks accepted on the fetch port and not yet written back,
  // and the blocks a flush dropped, each with its generation.
  logic [FTQ_DEPTH-1:0]       r_held;
  logic [FTQ_DEPTH-1:0]       r_dead;
  logic [FTQ_DEPTH-1:0]       r_dead_gen;
  // U4. The block most recently accepted for translation, and its
  // lookups a flush made dead.
  logic [FTQ_IDX_BITS-1:0]    r_xblk;
  logic [1:0]                 r_xdead;

  logic       w_l1i_fire;
  logic       w_itlb_fire;
  logic       w_facc;
  logic       w_xacc;
  logic [1:0] w_out_nx;

  // IFU-28, computed here rather than read from the unit.
  function automatic logic survives(input logic [FTQ_IDX_BITS-1:0] i,
                                    input logic [FTQ_IDX_BITS-1:0] f,
                                    input logic [FTQ_IDX_BITS-1:0] c);
    return FTQ_IDX_BITS'(i - c) < FTQ_IDX_BITS'(f - c);
  endfunction

  always_comb begin : ev
    w_l1i_fire  = ifu_l1i_req_val && ifu_l1i_req_rdy;
    w_itlb_fire = ifu_itlb_req_val && ifu_itlb_req_rdy;
    w_facc      = ftq_ifu_req_val && ftq_ifu_req_rdy && !ftq_ifu_flush_val;
    w_xacc      = ftq_ifu_xlate_val && ftq_ifu_xlate_rdy &&
                  !ftq_ifu_flush_val;
    for (int t = 0; t < 2; t++) begin
      w_out_nx[t] = (r_itlb_out[t] &&
                     !(itlb_ifu_rsp_val && (itlb_ifu_tag == t[0]))) ||
                    (w_itlb_fire && (ifu_itlb_tag == t[0]));
    end
  end

  always_ff @(posedge clk or negedge rstn) begin : hist
    if (!rstn) begin
      r_id_out   <= '0;
      r_gen      <= '0;
      r_itlb_out <= '0;
      r_held     <= '0;
      r_dead     <= '0;
      r_dead_gen <= '0;
      r_xblk     <= '0;
      r_xdead    <= '0;
    end else begin
      for (int i = 0; i < MAX_OUTSTANDING; i++) begin
        if (w_l1i_fire && (ifu_l1i_req_id == REQ_ID_BITS'(i)))
          r_id_out[i] <= 1'b1;
        else if (l1i_ifu_rsp_val && (l1i_ifu_rsp_id == REQ_ID_BITS'(i)))
          r_id_out[i] <= 1'b0;
      end
      if (w_facc)
        r_gen[ftq_ifu_idx] <= ftq_ifu_gen;
      r_itlb_out <= w_out_nx;

      // U3. A writeback retires the block; a flush moves the blocks it
      // drops from held to dead; a new fetch of an index retires the
      // dead record of that index.
      for (int i = 0; i < FTQ_DEPTH; i++) begin
        if (w_facc && (ftq_ifu_idx == FTQ_IDX_BITS'(i))) begin
          r_held[i] <= 1'b1;
          r_dead[i] <= 1'b0;
        end else if (ifu_ftq_pdwb_val &&
                     (ifu_ftq_pdwb_idx == FTQ_IDX_BITS'(i))) begin
          r_held[i] <= 1'b0;
        end else if (ftq_ifu_flush_val && r_held[i] &&
                     !survives(FTQ_IDX_BITS'(i), ftq_ifu_flush_idx,
                               ftq_ifu_commit_ptr)) begin
          r_held[i]     <= 1'b0;
          r_dead[i]     <= 1'b1;
          r_dead_gen[i] <= r_gen[i];
        end
      end

      // U4. The block in translation is the last one accepted; its
      // lookups still out after this cycle become dead if a flush
      // drops it. A dead tag clears on its response.
      if (w_xacc) r_xblk <= ftq_ifu_xlate_idx;
      for (int t = 0; t < 2; t++) begin
        if (ftq_ifu_flush_val &&
            !survives(r_xblk, ftq_ifu_flush_idx, ftq_ifu_commit_ptr))
          r_xdead[t] <= r_xdead[t] || w_out_nx[t];
        else if (itlb_ifu_rsp_val && (itlb_ifu_tag == t[0]))
          r_xdead[t] <= 1'b0;
      end
    end
  end

  // U1  IF-6, IF-7. An identifier is accepted only when no earlier
  //     request on it is still unanswered: the slot it reserved is
  //     the one its response lands in, and the response has no ready.
  property p_id_reused_after_rsp;
    @(posedge clk) disable iff (!rstn)
      w_l1i_fire |-> !r_id_out[ifu_l1i_req_id];
  endproperty

  // U2  IFU-19, ftq_ifu_interfaces.md 6.1 X4. The writeback carries
  //     the generation accepted with that index's request. A tag
  //     altered anywhere in F0 to WB makes the FTQ drop a current
  //     writeback, or accept a stale one.
  property p_gen_unchanged;
    @(posedge clk) disable iff (!rstn)
      ifu_ftq_pdwb_val |-> (ifu_ftq_pdwb_gen == r_gen[ifu_ftq_pdwb_idx]);
  endproperty

  // U3  IFU-32 (BP-118). A block the flush dropped presents no
  //     writeback after the flush cycle. One in the flush cycle itself
  //     is allowed and is the one the generation bit rejects; the dead
  //     record is registered, so it is not yet set in that cycle.
  //     This is what keeps one generation bit sufficient (IFU-20).
  property p_no_wb_after_drop;
    @(posedge clk) disable iff (!rstn)
      ifu_ftq_pdwb_val |->
        !(r_dead[ifu_ftq_pdwb_idx] &&
          (r_dead_gen[ifu_ftq_pdwb_idx] == ifu_ftq_pdwb_gen));
  endproperty

  // U4  IFU-31 (BP-118). While a lookup of a dropped block is in
  //     flight no new block is accepted for translation, and the
  //     record is registered, so not in the cycle the last dead
  //     response arrives either: a tag is never shared between a dead
  //     and a live lookup.
  property p_no_xlate_while_dead;
    @(posedge clk) disable iff (!rstn)
      (ftq_ifu_xlate_val && ftq_ifu_xlate_rdy) |-> (r_xdead == 2'b00);
  endproperty

  a_l1i_id_reuse:   assert property (p_id_reused_after_rsp)
    else $error("U1 IF-7 an L1I identifier was reused before its response");
  a_gen_unchanged:  assert property (p_gen_unchanged)
    else $error("U2 IFU-19 the writeback generation was altered");
  a_no_wb_dropped:  assert property (p_no_wb_after_drop)
    else $error("U3 IFU-32 a writeback for a dropped block after the flush");
  a_no_xlate_dead:  assert property (p_no_xlate_while_dead)
    else $error("U4 IFU-31 a block accepted with a dead lookup in flight");

endmodule : ifu_assert

// Bind BY MODULE NAME.
bind ifu ifu_assert u_assert (
  .clk               (clk),
  .rstn              (rstn),
  .ftq_ifu_req_val   (ftq_ifu_req_val),
  .ftq_ifu_req_rdy   (ftq_ifu_req_rdy),
  .ftq_ifu_idx       (ftq_ifu_idx),
  .ftq_ifu_gen       (ftq_ifu_gen),
  .ftq_ifu_flush_val (ftq_ifu_flush_val),
  .ftq_ifu_flush_idx (ftq_ifu_flush_idx),
  .ftq_ifu_commit_ptr (ftq_ifu_commit_ptr),
  .ftq_ifu_xlate_val (ftq_ifu_xlate_val),
  .ftq_ifu_xlate_rdy (ftq_ifu_xlate_rdy),
  .ftq_ifu_xlate_idx (ftq_ifu_xlate_idx),
  .ifu_ftq_pdwb_val  (ifu_ftq_pdwb_val),
  .ifu_ftq_pdwb_idx  (ifu_ftq_pdwb_idx),
  .ifu_ftq_pdwb_gen  (ifu_ftq_pdwb_gen),
  .ifu_l1i_req_val   (ifu_l1i_req_val),
  .ifu_l1i_req_rdy   (ifu_l1i_req_rdy),
  .ifu_l1i_req_id    (ifu_l1i_req_id),
  .l1i_ifu_rsp_val   (l1i_ifu_rsp_val),
  .l1i_ifu_rsp_id    (l1i_ifu_rsp_id),
  .ifu_itlb_req_val  (ifu_itlb_req_val),
  .ifu_itlb_req_rdy  (ifu_itlb_req_rdy),
  .ifu_itlb_tag      (ifu_itlb_tag),
  .itlb_ifu_rsp_val  (itlb_ifu_rsp_val),
  .itlb_ifu_tag      (itlb_ifu_tag)
);
