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
  input logic [FTQ_PTR_BITS-1:0] alloc_req_ptr,
  input logic                    ftq_full,
  input logic                    ftq_empty,
  input logic                    ptr_alias_full,
  input logic                    alloc_req_val,
  input logic                    alloc_req_rdy,
  input logic                    xlate_req_val,
  input logic                    xlate_req_rdy,
  input logic                    alloc_inflight,
  input logic                    xlate_pending,
  input logic                    fetch_pending,
  input logic                    redir_val,
  input logic [FTQ_IDX_BITS-1:0] redir_idx,
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
  logic                    w_keep_k;
  logic                    w_pd_redir;
  // The age of K+1, the predecode flush index. R2 puts K at or after
  // commit_ptr, so K's age is its index distance from commit_ptr's
  // index, 0 to 63, and needs no generation reconstruction.
  logic [FTQ_PTR_BITS-1:0] w_age_k1;

  always_comb begin : ages
    w_age_alloc = alloc_ptr - commit_ptr;
    w_age_xlate = xlate_ptr - commit_ptr;
    w_age_fetch = fetch_ptr - commit_ptr;
    // p2 and p3 keep K; predecode flushes past it (BP-117, TD#146).
    w_keep_k    = redir_arm[ARM_P3] | redir_arm[ARM_P2];
    w_pd_redir  = redir_arm[ARM_PD];
    w_age_k1    = {1'b0, FTQ_IDX_BITS'(redir_idx -
                                       commit_ptr[FTQ_IDX_BITS-1:0])} +
                  {{(FTQ_PTR_BITS-1){1'b0}}, 1'b1};
  end

  // A REGISTERED COPY of the p0 pointer and its acceptance, not
  // $past: alloc_req_ptr is combinational on the redirect inputs, the
  // same reason ftq_shadow_assert keeps r_prev_ptr. Acceptance is the
  // gate ftq_ptr applies, full taken from the pre-rewind head.
  logic [FTQ_PTR_BITS-1:0] r_req_ptr;
  logic                    r_req_acc;

  always_ff @(posedge clk or negedge rstn) begin : hist
    if (!rstn) begin
      r_req_ptr <= '0;
      r_req_acc <= 1'b0;
    end else begin
      r_req_ptr <= alloc_req_ptr;
      r_req_acc <= alloc_req_val && alloc_req_rdy && !ftq_full;
    end
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
  //     redirect rewinds, and the allocation made from the rewound
  //     head in that cycle is Q10's (BP-113).
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

  // Q8  7 W3. A p2 or p3 redirect leaves K to be translated and
  //     fetched again: F = K and alloc_ptr = K+1, so neither xlate_ptr
  //     nor fetch_ptr is left AT alloc_ptr. TD#126 built F = K+1,
  //     which leaves both there when they were ahead. CHANGED BY
  //     BP-117: the antecedent included the predecode arm, which now
  //     flushes at K+1 (Q8a).
  property p_fe_redirect_keeps_k;
    @(posedge clk) disable iff (!rstn)
      (redir_val && w_keep_k && (redir_cause != RC_UNSPEC)) |=>
        (xlate_ptr != alloc_ptr) && (fetch_ptr != alloc_ptr);
  endproperty

  // Q8a 5.5 R1, the predecode row, ruled session-074 (TD#146,
  //     BP-117). F = K+1: K is fetched and its head is in the ibuf,
  //     which does not clear on it, so it is not fetched again. Each
  //     of xlate_ptr and fetch_ptr becomes the wrap-aware minimum of
  //     its own value and K+1. Formed here from redir_idx and the
  //     commit_ptr of the redirect cycle, not from ftq_ptr's rewind
  //     targets: K = F would leave a pointer that was past K on K.
  property p_pd_redirect_past_k;
    @(posedge clk) disable iff (!rstn)
      (redir_val && w_pd_redir && (redir_cause != RC_UNSPEC)) |=>
        ((xlate_ptr - $past(commit_ptr)) ==
           (($past(w_age_xlate) > $past(w_age_k1)) ? $past(w_age_k1)
                                                    : $past(w_age_xlate)))
        &&
        ((fetch_ptr - $past(commit_ptr)) ==
           (($past(w_age_fetch) > $past(w_age_k1)) ? $past(w_age_k1)
                                                    : $past(w_age_fetch)));
  endproperty

  // Q10 5.2 IN EVERY CYCLE, THE REDIRECT CYCLE INCLUDED. The pointer
  //     the p0 request carries is the one allocated: alloc_ptr next
  //     cycle is that pointer, plus one if the request was accepted.
  //     Outside a redirect this says the request carries alloc_ptr.
  //     In a redirect cycle it says the request carries the rewound
  //     head, which is TD#139: the pre-rewind head went out and the
  //     redirect target was written to an entry the rewind freed.
  //     Added by BP-113.
  property p_p0_ptr_is_allocated;
    @(posedge clk) disable iff (!rstn)
      alloc_ptr == (r_req_ptr +
                    {{(FTQ_PTR_BITS-1){1'b0}}, r_req_acc});
  endproperty

  // Q11 xlate_pending, from the pointers (BP-116, TD#144; was
  //     ftq_ifu I15). A translation is pending exactly when an entry
  //     at or after xlate_ptr is WRITTEN: xlate_ptr is not at
  //     alloc_ptr, and the one entry below alloc_ptr is not the p1
  //     write still in flight. Derived here on RAW POINTER EQUALITY,
  //     not on the age compares ftq_ptr forms. The two agree only
  //     while FQ-1 holds, and Q1b checks that separately. Dropping
  //     the written-frontier term from ftq_ptr presents the in-flight
  //     entry, and fires here.
  logic [FTQ_PTR_BITS-1:0] w_xlate_nx;
  logic [FTQ_PTR_BITS-1:0] w_fetch_nx;
  logic                    w_exp_xlate_pend;
  logic                    w_exp_fetch_pend;

  always_comb begin : pend_model
    w_xlate_nx       = xlate_ptr + {{(FTQ_PTR_BITS-1){1'b0}}, 1'b1};
    w_fetch_nx       = fetch_ptr + {{(FTQ_PTR_BITS-1){1'b0}}, 1'b1};
    w_exp_xlate_pend = (xlate_ptr != alloc_ptr) &&
                       !(alloc_inflight && (w_xlate_nx == alloc_ptr));
    w_exp_fetch_pend = (fetch_ptr != xlate_ptr) &&
                       !(alloc_inflight && (w_fetch_nx == alloc_ptr));
  end

  property p_xlate_pending_from_ptrs;
    @(posedge clk) disable iff (!rstn)
      xlate_pending == w_exp_xlate_pend;
  endproperty

  // Q12 fetch_pending, from the pointers (BP-116, TD#144; was
  //     ftq_ifu I8). A fetch is pending exactly when fetch_ptr is
  //     behind xlate_ptr -- the entry's translation went out in an
  //     earlier cycle (L1I-3) -- and the entry at fetch_ptr is not
  //     the in-flight p1 write. Same derivation and same FQ-1
  //     dependence as Q11 (Q1 checks fetch against xlate).
  property p_fetch_pending_from_ptrs;
    @(posedge clk) disable iff (!rstn)
      fetch_pending == w_exp_fetch_pend;
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
    else $error("Q8 a p2 or p3 redirect did not rewind to K");
  a_pd_redirect_past_k:  assert property (p_pd_redirect_past_k)
    else $error("Q8a a predecode redirect did not rewind to min(ptr, K+1)");
  a_fq1_depth_bounded:   assert property (p_fq1_depth_bounded)
    else $error("FQ-1 live entries exceed the allocation limit");
  a_alias_full_is_full:  assert property (p_alias_full_is_full)
    else $error("Q3 the 5.1 full condition disagrees with ftq_full");
  a_full_blocks_alloc:   assert property (p_full_blocks_alloc)
    else $error("Q4 allocation advanced while full");
  a_full_not_empty:      assert property (p_full_not_empty)
    else $error("Q5 full and empty asserted together");
  a_p0_ptr_is_allocated: assert property (p_p0_ptr_is_allocated)
    else $error("Q10 the p0 index is not the entry allocated");
  a_xlate_pend_ptrs:     assert property (p_xlate_pending_from_ptrs)
    else $error("Q11 xlate_pending disagrees with the pointers");
  a_fetch_pend_ptrs:     assert property (p_fetch_pending_from_ptrs)
    else $error("Q12 fetch_pending disagrees with the pointers");

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
  .alloc_req_ptr  (alloc_req_ptr),
  .ftq_full       (ftq_full),
  .ftq_empty      (ftq_empty),
  .ptr_alias_full (ptr_alias_full),
  .alloc_req_val  (alloc_req_val),
  .alloc_req_rdy  (alloc_req_rdy),
  .xlate_req_val  (xlate_req_val),
  .xlate_req_rdy  (xlate_req_rdy),
  .alloc_inflight (alloc_inflight),
  .xlate_pending  (xlate_pending),
  .fetch_pending  (fetch_pending),
  .redir_val      (redir_val),
  .redir_idx      (redir_idx),
  .redir_cause    (redir_cause),
  .redir_arm      (redir_arm)
);
