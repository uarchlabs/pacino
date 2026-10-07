// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ifu_xlate (BP-116), itlb_ifu_interfaces.md 6.
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
//
// Each property compares the module's ITLB request against a model
// this file keeps from the port events of earlier cycles, never
// against the RTL that drives the request (CLAUDE.md Verification -
// assertions).
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ifu_xlate_assert (
  input logic                 clk,
  input logic                 rstn,
  input logic                 ftq_ifu_flush_val,
  input logic                 ftq_ifu_xlate_val,
  input logic                 ftq_ifu_xlate_rdy,
  input logic [VA_WIDTH-1:0]  ftq_ifu_xlate_pc,
  input logic                 ifu_itlb_req_val,
  input logic                 ifu_itlb_req_rdy,
  input logic [VA_WIDTH-13:0] ifu_itlb_vpn,
  input logic                 ifu_itlb_tag,
  input logic                 itlb_ifu_rsp_val,
  input logic                 itlb_ifu_tag,
  input logic                 xq_val,
  input logic                 xq_uc,
  input logic                 xq_pop
);

  // IT-16: the lookup VPN is the fetch address above the page offset.
  localparam int LK_VPN_W = VA_WIDTH - 12;

  // A request presented and not taken last cycle.
  logic                 r_stall;
  logic [LK_VPN_W-1:0]  r_vpn;
  logic                 r_tag;

  // The page of the block whose lookups are in progress, taken from
  // the FTQ translation handshake (ftq_ifu_interfaces.md 4.1), not
  // from the module's own lookup register.
  logic                 w_xacc;
  logic [LK_VPN_W-1:0]  w_xacc_vpn;
  logic [LK_VPN_W-1:0]  r_blk_vpn;
  logic [LK_VPN_W-1:0]  w_exp_vpn;

  always_comb begin : blk_page
    w_xacc     = ftq_ifu_xlate_val && ftq_ifu_xlate_rdy &&
                 !ftq_ifu_flush_val;
    w_xacc_vpn = ftq_ifu_xlate_pc[VA_WIDTH-1:12];
    // A block accepted this cycle presents its own first lookup now;
    // otherwise the lookup belongs to the block accepted earlier, its
    // own page on tag 0 and the next page on tag 1 (IT-2).
    if (w_xacc)            w_exp_vpn = w_xacc_vpn;
    else if (ifu_itlb_tag) w_exp_vpn = r_blk_vpn + LK_VPN_W'(1);
    else                   w_exp_vpn = r_blk_vpn;
  end

  // Lookups in flight per tag, from the request and response ports.
  logic [1:0]           r_out;

  always_ff @(posedge clk or negedge rstn) begin : hist
    if (!rstn) begin
      r_stall <= 1'b0;
      r_blk_vpn <= '0;
      r_vpn   <= '0;
      r_tag   <= 1'b0;
      r_out   <= '0;
    end else begin
      r_stall <= ifu_itlb_req_val && !ifu_itlb_req_rdy;
      if (w_xacc) r_blk_vpn <= w_xacc_vpn;
      r_vpn   <= ifu_itlb_vpn;
      r_tag   <= ifu_itlb_tag;
      for (int t = 0; t < 2; t++) begin
        if (ifu_itlb_req_val && ifu_itlb_req_rdy && (ifu_itlb_tag == t[0]))
          r_out[t] <= 1'b1;
        else if (itlb_ifu_rsp_val && (itlb_ifu_tag == t[0]))
          r_out[t] <= 1'b0;
      end
    end
  end

  // T1  IT-13. A lookup the ITLB did not take is held: presented
  //     again, same VPN and tag, in the next cycle. A flush discards
  //     it (TD#134, ftq_ifu_interfaces.md 5).
  property p_req_held;
    @(posedge clk) disable iff (!rstn)
      (r_stall && !ftq_ifu_flush_val) |->
        (ifu_itlb_req_val && (ifu_itlb_vpn == r_vpn) &&
         (ifu_itlb_tag == r_tag));
  endproperty

  // T2  IT-14. The IFU accepts every response because it has one slot
  //     per tag and never issues a second lookup on a tag whose first
  //     is still in flight. A response is then always attributable,
  //     and the two-outstanding bound of IT-1 holds. A response
  //     presented in the issue cycle frees its tag in that cycle: the
  //     IFU takes it then (IT-14), which is what lets a new block's
  //     first lookup follow the last response with no gap (IFU-U5).
  property p_tag_free_on_issue;
    @(posedge clk) disable iff (!rstn)
      (ifu_itlb_req_val && ifu_itlb_req_rdy) |->
        (!r_out[ifu_itlb_tag] ||
         (itlb_ifu_rsp_val && (itlb_ifu_tag == ifu_itlb_tag)));
  endproperty

  // T3  TD#135 STUB. The uncached path is not built, so a block IFU-26
  //     marked must never be taken by F0. The testbench returns only
  //     cacheable, idempotent PMAs; this fires if that changes.
  property p_no_uncached_at_f0;
    @(posedge clk) disable iff (!rstn)
      (xq_val && xq_pop) |-> !xq_uc;
  endproperty

  // T4  IT-16, IT-1, IT-2 (TD#146, BP-117). Every lookup carries the
  //     whole fetch address above the page offset: the block's own
  //     page on tag 0 and the next page on tag 1, compared against the
  //     page this file took from the FTQ's translation handshake. A
  //     lookup presented with the acceptance is tag 0 of the new block.
  //     A port narrower than VA_WIDTH-12 drops the high bits and fires
  //     here for any fetch address above bit VPN_WIDTH+11.
  property p_lookup_vpn_is_block_page;
    @(posedge clk) disable iff (!rstn)
      (ifu_itlb_req_val && !ftq_ifu_flush_val) |->
        ((ifu_itlb_vpn == w_exp_vpn) && !(w_xacc && ifu_itlb_tag));
  endproperty

  a_itlb_req_held:   assert property (p_req_held)
    else $error("T1 IT-13 an ITLB lookup was not held until taken");
  a_itlb_tag_free:   assert property (p_tag_free_on_issue)
    else $error("T2 IT-14 an ITLB lookup reused a tag in flight");
  a_no_uncached_f0:  assert property (p_no_uncached_at_f0)
    else $error("T3 TD#135 a marked uncached block reached F0");
  a_itlb_vpn_page:   assert property (p_lookup_vpn_is_block_page)
    else $error("T4 IT-16 the lookup VPN is not the block's page");

endmodule : ifu_xlate_assert

// Bind BY MODULE NAME.
bind ifu_xlate ifu_xlate_assert u_assert (
  .clk               (clk),
  .rstn              (rstn),
  .ftq_ifu_flush_val (ftq_ifu_flush_val),
  .ftq_ifu_xlate_val (ftq_ifu_xlate_val),
  .ftq_ifu_xlate_rdy (ftq_ifu_xlate_rdy),
  .ftq_ifu_xlate_pc  (ftq_ifu_xlate_pc),
  .ifu_itlb_req_val  (ifu_itlb_req_val),
  .ifu_itlb_req_rdy  (ifu_itlb_req_rdy),
  .ifu_itlb_vpn      (ifu_itlb_vpn),
  .ifu_itlb_tag      (ifu_itlb_tag),
  .itlb_ifu_rsp_val  (itlb_ifu_rsp_val),
  .itlb_ifu_tag      (itlb_ifu_tag),
  .xq_val            (xq_val),
  .xq_uc             (xq_uc),
  .xq_pop            (xq_pop)
);
