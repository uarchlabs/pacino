// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ftq_ftb_sched. The five properties of
// ftq_decisions.md 5.7.4 (BP-100).
//
// THE FIRST CONCURRENT SVA IN THIS PROJECT. The three BPU assertion
// files use procedural immediate assertions and are simulation only;
// these are written in the form a formal tool consumes.
//
// BOUND BY MODULE NAME, never by instance name. TD#109 is the
// precedent: an assertion file bound to an instance name was
// instantiated by nothing and warned about by nothing under -Wall.
// A module-name bind attaches to every instance that exists.
//
// The properties read only the DUT's port list, so this file makes
// no hierarchical reference into module internals. The observation
// ports on ftq_ftb_sched exist for exactly that reason.
//
// P4 DIFFERS FROM 5.7.4 AS ORIGINALLY WRITTEN, by one operator.
// The document had |-> ; it must be |=>. P1 asserts the output
// valid with |=>, which requires a REGISTERED output. P4 with |->
// requires the same signal to be combinational in the same cycle.
// No implementation can satisfy both. The registered form was
// built, P1 is unchanged, and P4 was corrected in the document.
// The intent of P4 is unchanged: when the skid is occupied, the
// NEXT issue comes from the skid.
// ===================================================================
module ftq_ftb_sched_assert #(
  parameter int NUM_UPD_CHAN = 2
) (
  input logic                        clk,
  input logic                        rstn,
  input logic [NUM_UPD_CHAN-1:0]     upd_rdy,
  input logic                        ftb_upd_valid_u0,
  input logic                        ftb_upd_from_skid,
  input logic                        skid_val,
  input logic                        skid_wr,
  input logic                        skid_issue,
  input logic                        drop_val,
  input logic                        drop_is_high,
  input logic [$clog2(NUM_UPD_CHAN+2)-1:0] n_acc_ftb,
  input logic [$clog2(NUM_UPD_CHAN+2)-1:0] n_pend_ftb,
  input logic                        any_pend_high
);

  // P1  A lone FTB-bound update is never dropped and never held.
  property p_ftb_lone_issues;
    @(posedge clk) disable iff (!rstn)
      (n_acc_ftb == 1 && !skid_val) |=> ftb_upd_valid_u0;
  endproperty

  // P2  A HIGH-value update is never dropped. This is the whole of
  //     the FE-5 relaxation: only LOW updates may be lost.
  property p_ftb_high_never_dropped;
    @(posedge clk) disable iff (!rstn)
      drop_val |-> !drop_is_high;
  endproperty

  // P3  The skid never overflows. It is one deep, so a write may
  //     only coincide with the entry leaving.
  property p_ftb_skid_bounded;
    @(posedge clk) disable iff (!rstn)
      (skid_val && skid_wr) |-> skid_issue;
  endproperty

  // P4  An occupied skid always issues NEXT, so the older update
  //     goes first and resolution order is preserved (FE-6).
  property p_ftb_skid_first;
    @(posedge clk) disable iff (!rstn)
      skid_val |=> (ftb_upd_valid_u0 && ftb_upd_from_skid);
  endproperty

  // P5  Resolution is never stalled when every pending FTB update
  //     is LOW. This is the throughput claim of 5.7.1: training
  //     pressure must not reach the backend.
  property p_ftb_no_stall_on_low;
    @(posedge clk) disable iff (!rstn)
      (n_pend_ftb > 0 && !any_pend_high) |-> (&upd_rdy);
  endproperty

  a_ftb_lone_issues:       assert property (p_ftb_lone_issues)
    else $error("P1 a lone FTB-bound update did not issue");
  a_ftb_high_never_dropped: assert property (p_ftb_high_never_dropped)
    else $error("P2 a HIGH-value update was dropped");
  a_ftb_skid_bounded:      assert property (p_ftb_skid_bounded)
    else $error("P3 the skid was written while occupied and held");
  a_ftb_skid_first:        assert property (p_ftb_skid_first)
    else $error("P4 an occupied skid did not issue next");
  a_ftb_no_stall_on_low:   assert property (p_ftb_no_stall_on_low)
    else $error("P5 resolution stalled with no HIGH update pending");

endmodule : ftq_ftb_sched_assert

// Bind BY MODULE NAME. Every ftq_ftb_sched instance gets the
// properties, including instances that do not exist yet.
bind ftq_ftb_sched ftq_ftb_sched_assert #(
  .NUM_UPD_CHAN (NUM_UPD_CHAN)
) u_assert (
  .clk               (clk),
  .rstn              (rstn),
  .upd_rdy           (upd_rdy),
  .ftb_upd_valid_u0  (ftb_upd_valid_u0),
  .ftb_upd_from_skid (ftb_upd_from_skid),
  .skid_val          (skid_val),
  .skid_wr           (skid_wr),
  .skid_issue        (skid_issue),
  .drop_val          (drop_val),
  .drop_is_high      (drop_is_high),
  .n_acc_ftb         (n_acc_ftb),
  .n_pend_ftb        (n_pend_ftb),
  .any_pend_high     (any_pend_high)
);
