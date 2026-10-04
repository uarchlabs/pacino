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
//   U3  TD#134 stub   no flush while an L1I or ITLB request is
//                     outstanding
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
  input logic                    itlb_ifu_rsp_val
);

  logic [MAX_OUTSTANDING-1:0] r_id_out;   // L1I ids in flight
  logic [FTQ_DEPTH-1:0]       r_gen;      // gen accepted per index
  logic [1:0]                 r_itlb_out; // ITLB lookups in flight

  logic w_l1i_fire;
  logic w_itlb_fire;

  always_comb begin : ev
    w_l1i_fire  = ifu_l1i_req_val && ifu_l1i_req_rdy;
    w_itlb_fire = ifu_itlb_req_val && ifu_itlb_req_rdy;
  end

  always_ff @(posedge clk or negedge rstn) begin : hist
    if (!rstn) begin
      r_id_out   <= '0;
      r_gen      <= '0;
      r_itlb_out <= '0;
    end else begin
      for (int i = 0; i < MAX_OUTSTANDING; i++) begin
        if (w_l1i_fire && (ifu_l1i_req_id == REQ_ID_BITS'(i)))
          r_id_out[i] <= 1'b1;
        else if (l1i_ifu_rsp_val && (l1i_ifu_rsp_id == REQ_ID_BITS'(i)))
          r_id_out[i] <= 1'b0;
      end
      if (ftq_ifu_req_val && ftq_ifu_req_rdy && !ftq_ifu_flush_val)
        r_gen[ftq_ifu_idx] <= ftq_ifu_gen;
      r_itlb_out <= r_itlb_out + 2'(w_itlb_fire) - 2'(itlb_ifu_rsp_val);
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

  // U3  TD#134 STUB. Wrong-path responses after a flush are deferred:
  //     a flush clears all IFU state, which is right only with
  //     nothing outstanding. A response in the flush cycle counts as
  //     outstanding until it is presented.
  property p_flush_when_idle;
    @(posedge clk) disable iff (!rstn)
      ftq_ifu_flush_val |-> (r_id_out == '0) && (r_itlb_out == '0);
  endproperty

  a_l1i_id_reuse:   assert property (p_id_reused_after_rsp)
    else $error("U1 IF-7 an L1I identifier was reused before its response");
  a_gen_unchanged:  assert property (p_gen_unchanged)
    else $error("U2 IFU-19 the writeback generation was altered");
  a_flush_idle:     assert property (p_flush_when_idle)
    else $error("U3 TD#134 a flush arrived with a request outstanding");

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
  .itlb_ifu_rsp_val  (itlb_ifu_rsp_val)
);
