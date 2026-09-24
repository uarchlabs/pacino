// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ftq_ptr. INVARIANT FQ-1 of ftq_decisions.md 5.1
// and the pointer rules that follow from it (BP-106).
//
// FQ-1 spans all four pointers and ftq_ptr owns only three, so this
// is the right place to bind it: commit_ptr is a port here, so the
// whole invariant is visible on one port list and the file makes no
// hierarchical reference into module internals.
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
//
// Every comparison is on an AGE, not a raw pointer. Ages are taken
// against commit_ptr, which maps the live window onto 0..FTQ_DEPTH
// where plain unsigned compare is the wrap-aware compare 5.1 asks
// for. Comparing raw pointers would report a violation on every wrap.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_ptr_assert (
  input logic                    clk,
  input logic                    rstn,
  input logic [FTQ_PTR_BITS-1:0] commit_ptr,
  input logic [FTQ_PTR_BITS-1:0] alloc_ptr,
  input logic [FTQ_PTR_BITS-1:0] xlate_ptr,
  input logic [FTQ_PTR_BITS-1:0] fetch_ptr,
  input logic                    ftq_full,
  input logic                    ftq_empty,
  input logic                    ptr_alias_full,
  input logic                    alloc_req_val,
  input logic                    alloc_req_rdy,
  input logic                    xlate_req_val,
  input logic                    xlate_req_rdy,
  input logic                    redir_val,
  input ftq_redir_cause_e        redir_cause,
  input logic [5:1]              redir_arm
);

  // ftq_npc's arm numbering, as ftq_ptr declares it.
  localparam int ARM_PD = 2;
  localparam int ARM_P3 = 3;
  localparam int ARM_P2 = 4;

  // The 5.1 condition, restored by BP-107 when the commit watermark
  // gained its generation bit. Was FTQ_DEPTH-1 under BP-106.
  localparam int FTQ_ALLOC_LIMIT = FTQ_DEPTH;

  logic [FTQ_PTR_BITS-1:0] w_age_alloc;
  logic [FTQ_PTR_BITS-1:0] w_age_xlate;
  logic [FTQ_PTR_BITS-1:0] w_age_fetch;
  logic                    w_fe_redir;

  always_comb begin : ages
    w_age_alloc = alloc_ptr - commit_ptr;
    w_age_xlate = xlate_ptr - commit_ptr;
    w_age_fetch = fetch_ptr - commit_ptr;
    w_fe_redir  = redir_arm[ARM_PD] | redir_arm[ARM_P3] |
                  redir_arm[ARM_P2];
  end

  // Q1  FQ-1, first half. CHANGED BY BP-112: it read fetch_ptr never
  //     leads alloc_ptr. xlate_ptr now sits between them, so the
  //     statement is two orderings, Q1 and Q1b, and the old one is
  //     their conjunction.
  //
  //     fetch_ptr never leads xlate_ptr. The FTQ cannot issue a fetch
  //     for an entry whose translation has not been presented
  //     (ftq_ifu_interfaces.md 4).
  property p_fq1_fetch_le_xlate;
    @(posedge clk) disable iff (!rstn)
      w_age_fetch <= w_age_xlate;
  endproperty

  // Q1b xlate_ptr never leads alloc_ptr. The FTQ cannot present a
  //     translation for an entry no prediction has allocated.
  property p_fq1_xlate_le_alloc;
    @(posedge clk) disable iff (!rstn)
      w_age_xlate <= w_age_alloc;
  endproperty

  // Q2  FQ-1, second half. commit_ptr never leads fetch_ptr, stated
  //     as the queue never holding more than the array. An age is
  //     unsigned and taken against commit_ptr, so commit_ptr leading
  //     shows up here as an age that has wrapped past the depth.
  property p_fq1_depth_bounded;
    @(posedge clk) disable iff (!rstn)
      w_age_alloc <= FTQ_PTR_BITS'(FTQ_ALLOC_LIMIT);
  endproperty

  // Q3  RE-AIMED BY BP-107. It read !ptr_alias_full, which guarded
  //     the FTQ_DEPTH-1 allocation limit BP-106 held to remove the
  //     aliased 65th watermark value. bkend_ftq_commit_idx now
  //     carries the generation, the limit is back at FTQ_DEPTH, and
  //     the alias state is the ordinary 64-live full condition --
  //     reachable, correct, and entered by group B of the
  //     testbench. Left as !ptr_alias_full the property would be
  //     inert until it fired on legal traffic, which is worse than
  //     retiring it.
  //
  //     What is worth proving in its place is that the two
  //     statements of full AGREE: the literal 5.1 low-bits-equal /
  //     generations-differ form and the age form the module
  //     actually gates allocation on. A future change that moves the
  //     limit off FTQ_DEPTH breaks the agreement and fires here, so
  //     the guard the old property provided is kept without the
  //     stale bound.
  property p_alias_full_is_full;
    @(posedge clk) disable iff (!rstn)
      ptr_alias_full == ftq_full;
  endproperty

  // Q4  Full blocks allocation. An accepted request in a full cycle
  //     would put alloc_ptr past the limit. Redirect excluded: a
  //     redirect rewinds and does not allocate.
  property p_full_blocks_alloc;
    @(posedge clk) disable iff (!rstn)
      (ftq_full && alloc_req_val && alloc_req_rdy && !redir_val) |=>
        ($stable(alloc_ptr) || redir_val);
  endproperty

  // Q5  Full and empty are mutually exclusive. This is what the wrap
  //     generation bit exists for: the low bits alias at both, and
  //     without the generation the two are the same state.
  property p_full_not_empty;
    @(posedge clk) disable iff (!rstn)
      !(ftq_full && ftq_empty);
  endproperty

  // Q6  xlate_ptr moves only on an accepted translation request or a
  //     redirect (5.1). Anything else presents an entry twice or
  //     skips one.
  property p_xlate_moves_on_handshake;
    @(posedge clk) disable iff (!rstn)
      (!redir_val && !(xlate_req_val && xlate_req_rdy)) |=>
        $stable(xlate_ptr);
  endproperty

  // Q7  5.5 R1. A redirect NEVER MOVES xlate_ptr OR fetch_ptr FORWARD:
  //     each becomes the minimum of its current value and F. Ages
  //     are taken against the commit_ptr of the redirect cycle, which
  //     ftq_commit holds still in a restore cycle and on RC_UNSPEC.
  //     The consequent is sampled one edge after the redirect, so a
  //     testbench that resets in that cycle never checks it.
  property p_redirect_not_forward;
    @(posedge clk) disable iff (!rstn)
      redir_val |=>
        ((xlate_ptr - $past(commit_ptr)) <= $past(w_age_xlate)) &&
        ((fetch_ptr - $past(commit_ptr)) <= $past(w_age_fetch));
  endproperty

  // Q8  7 W3. A p2, p3 or predecode redirect leaves K to be
  //     translated and fetched again: F = K and alloc_ptr = K+1, so
  //     neither xlate_ptr nor fetch_ptr is left AT alloc_ptr. TD#126
  //     built F = K+1, which leaves both there when they were ahead.
  property p_fe_redirect_keeps_k;
    @(posedge clk) disable iff (!rstn)
      (redir_val && w_fe_redir && (redir_cause != RC_UNSPEC)) |=>
        (xlate_ptr != alloc_ptr) && (fetch_ptr != alloc_ptr);
  endproperty

  a_fq1_fetch_le_xlate:  assert property (p_fq1_fetch_le_xlate)
    else $error("FQ-1 fetch_ptr leads xlate_ptr");
  a_fq1_xlate_le_alloc:  assert property (p_fq1_xlate_le_alloc)
    else $error("FQ-1 xlate_ptr leads alloc_ptr");
  a_xlate_on_handshake:  assert property (p_xlate_moves_on_handshake)
    else $error("Q6 xlate_ptr moved without a handshake or redirect");
  a_redirect_not_fwd:    assert property (p_redirect_not_forward)
    else $error("Q7 a redirect moved xlate_ptr or fetch_ptr forward");
  a_fe_redirect_keeps_k: assert property (p_fe_redirect_keeps_k)
    else $error("Q8 a front-end redirect did not rewind to K");
  a_fq1_depth_bounded:   assert property (p_fq1_depth_bounded)
    else $error("FQ-1 live entries exceed the allocation limit");
  a_alias_full_is_full:  assert property (p_alias_full_is_full)
    else $error("Q3 the 5.1 full condition disagrees with ftq_full");
  a_full_blocks_alloc:   assert property (p_full_blocks_alloc)
    else $error("Q4 allocation advanced while full");
  a_full_not_empty:      assert property (p_full_not_empty)
    else $error("Q5 full and empty asserted together");

endmodule : ftq_ptr_assert

// Bind BY MODULE NAME. Every ftq_ptr instance gets the properties,
// including instances that do not exist yet.
bind ftq_ptr ftq_ptr_assert u_assert (
  .clk            (clk),
  .rstn           (rstn),
  .commit_ptr     (commit_ptr),
  .alloc_ptr      (alloc_ptr),
  .xlate_ptr      (xlate_ptr),
  .fetch_ptr      (fetch_ptr),
  .ftq_full       (ftq_full),
  .ftq_empty      (ftq_empty),
  .ptr_alias_full (ptr_alias_full),
  .alloc_req_val  (alloc_req_val),
  .alloc_req_rdy  (alloc_req_rdy),
  .xlate_req_val  (xlate_req_val),
  .xlate_req_rdy  (xlate_req_rdy),
  .redir_val      (redir_val),
  .redir_cause    (redir_cause),
  .redir_arm      (redir_arm)
);
