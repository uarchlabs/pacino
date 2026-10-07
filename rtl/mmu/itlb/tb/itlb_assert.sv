// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for itlb (BP-118). itlb_ifu_interfaces.md IT-4, IT-9,
// ITLB-5, ITLB-10; itlb_l2tlb_interfaces.md IL-1, IL-2.
//
// BOUND BY MODULE NAME, never by instance name (TD#109). Every input
// is an itlb port; no hierarchical reference.
//
// Each property compares a port against a model this file keeps from
// the port events of EARLIER cycles: the request taken last cycle,
// and the set of L2 TLB requests taken and not yet answered. None
// restates the RTL that drives the checked signal (CLAUDE.md
// Verification - assertions).
//
//   I1  a_rsp_one_cycle  a response is presented exactly in the cycle
//                        after a request is taken, with its tag
//                        (ITLB-5, IT-3)
//   I2  a_no_rsvd        the reserved status is never presented
//                        (IT-4)
//   I3  a_no_dup_walk    no L2 TLB request names a VA and identity
//                        that already has one outstanding, unless an
//                        invalidate has intervened (ITLB-10, IT-9)
//   I4  a_tag_free       no L2 TLB request reuses a tag that is still
//                        outstanding (IL-1, IL-2)
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module itlb_assert (
  input logic                  clk,
  input logic                  rstn,
  input logic                  ifu_itlb_req_val,
  input logic                  ifu_itlb_req_rdy,
  input logic                  ifu_itlb_tag,
  input logic                  itlb_ifu_rsp_val,
  input logic                  itlb_ifu_tag,
  input logic [1:0]            itlb_ifu_status,
  input logic                  itlb_l2t_req_val,
  input logic                  itlb_l2t_req_rdy,
  input logic [VA_WIDTH-13:0]  itlb_l2t_vpn,
  input logic [ASID_WIDTH-1:0] itlb_l2t_asid,
  input logic [VMID_WIDTH-1:0] itlb_l2t_vmid,
  input logic                  itlb_l2t_v,
  input logic [1:0]            itlb_l2t_tag,
  input logic                  l2t_itlb_rsp_val,
  input logic [1:0]            l2t_itlb_tag,
  input logic                  bkend_itlb_inv_val
);

  localparam int VW = VA_WIDTH - 12;

  // ---- the request taken last cycle -----------------------------------
  logic r_took;
  logic r_tag;

  // ---- L2 TLB requests outstanding, per tag ----------------------------
  logic                  r_out  [0:3];
  logic                  r_dead [0:3];   // an invalidate intervened
  logic [VW-1:0]         r_vpn  [0:3];
  logic [ASID_WIDTH-1:0] r_asid [0:3];
  logic [VMID_WIDTH-1:0] r_vmid [0:3];
  logic                  r_v    [0:3];

  logic w_fire;
  logic w_dup;
  logic w_reuse;

  always_comb begin : model
    w_fire  = itlb_l2t_req_val && itlb_l2t_req_rdy;
    w_dup   = 1'b0;
    w_reuse = 1'b0;
    for (int t = 0; t < 4; t++) begin
      if (r_out[t] && !r_dead[t] && (r_vpn[t] == itlb_l2t_vpn) &&
          (r_asid[t] == itlb_l2t_asid) && (r_vmid[t] == itlb_l2t_vmid) &&
          (r_v[t] == itlb_l2t_v))
        w_dup = 1'b1;
      if (r_out[t] && (itlb_l2t_tag == 2'(t)))
        w_reuse = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rstn) begin : track
    if (!rstn) begin
      r_took <= 1'b0;
      r_tag  <= 1'b0;
      for (int t = 0; t < 4; t++) begin
        r_out[t]  <= 1'b0;
        r_dead[t] <= 1'b0;
        r_vpn[t]  <= '0;
        r_asid[t] <= '0;
        r_vmid[t] <= '0;
        r_v[t]    <= 1'b0;
      end
    end else begin
      r_took <= ifu_itlb_req_val && ifu_itlb_req_rdy;
      r_tag  <= ifu_itlb_tag;
      for (int t = 0; t < 4; t++) begin
        if (bkend_itlb_inv_val) r_dead[t] <= 1'b1;
        if (l2t_itlb_rsp_val && (l2t_itlb_tag == 2'(t))) begin
          r_out[t]  <= 1'b0;
          r_dead[t] <= 1'b0;
        end
        if (w_fire && (itlb_l2t_tag == 2'(t))) begin
          r_out[t]  <= 1'b1;
          r_dead[t] <= 1'b0;
          r_vpn[t]  <= itlb_l2t_vpn;
          r_asid[t] <= itlb_l2t_asid;
          r_vmid[t] <= itlb_l2t_vmid;
          r_v[t]    <= itlb_l2t_v;
        end
      end
    end
  end

  property p_rsp_one_cycle;
    @(posedge clk) disable iff (!rstn)
      (itlb_ifu_rsp_val == r_took) &&
      (!itlb_ifu_rsp_val || (itlb_ifu_tag == r_tag));
  endproperty
  a_rsp_one_cycle: assert property (p_rsp_one_cycle)
    else $error("I1 ITLB response not exactly one cycle after request");

  property p_no_rsvd;
    @(posedge clk) disable iff (!rstn)
      itlb_ifu_rsp_val |-> (itlb_ifu_status != 2'b11);
  endproperty
  a_no_rsvd: assert property (p_no_rsvd)
    else $error("I2 ITLB presented the reserved status");

  property p_no_dup_walk;
    @(posedge clk) disable iff (!rstn)
      w_fire |-> !w_dup;
  endproperty
  a_no_dup_walk: assert property (p_no_dup_walk)
    else $error("I3 second walk for a VA already in flight");

  property p_tag_free;
    @(posedge clk) disable iff (!rstn)
      w_fire |-> !w_reuse;
  endproperty
  a_tag_free: assert property (p_tag_free)
    else $error("I4 L2 TLB tag reused while outstanding");

endmodule : itlb_assert

// Bind BY MODULE NAME.
bind itlb itlb_assert u_assert (
  .clk                (clk),
  .rstn               (rstn),
  .ifu_itlb_req_val   (ifu_itlb_req_val),
  .ifu_itlb_req_rdy   (ifu_itlb_req_rdy),
  .ifu_itlb_tag       (ifu_itlb_tag),
  .itlb_ifu_rsp_val   (itlb_ifu_rsp_val),
  .itlb_ifu_tag       (itlb_ifu_tag),
  .itlb_ifu_status    (itlb_ifu_status),
  .itlb_l2t_req_val   (itlb_l2t_req_val),
  .itlb_l2t_req_rdy   (itlb_l2t_req_rdy),
  .itlb_l2t_vpn       (itlb_l2t_vpn),
  .itlb_l2t_asid      (itlb_l2t_asid),
  .itlb_l2t_vmid      (itlb_l2t_vmid),
  .itlb_l2t_v         (itlb_l2t_v),
  .itlb_l2t_tag       (itlb_l2t_tag),
  .l2t_itlb_rsp_val   (l2t_itlb_rsp_val),
  .l2t_itlb_tag       (l2t_itlb_tag),
  .bkend_itlb_inv_val (bkend_itlb_inv_val)
);
