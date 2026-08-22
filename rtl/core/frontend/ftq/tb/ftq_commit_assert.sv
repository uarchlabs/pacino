// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ftq_commit. The rules of ftq_decisions.md 5.3,
// 5.4 and 5.5 R2 (BP-106).
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_commit_assert (
  input logic                    clk,
  input logic                    rstn,
  input logic [FTQ_PTR_BITS-1:0] commit_ptr,
  input logic [FTQ_PTR_BITS-1:0] alloc_ptr,
  input logic                    commit_step_val,
  input logic                    redir_val,
  input ftq_redir_cause_e        redir_cause
);

  // C1  commit_ptr NEVER REWINDS (5.5 R2). Committed is
  //     architectural. The pointer either holds or advances by
  //     exactly one; there is no other transition, under any input,
  //     including a malformed watermark behind it.
  property p_commit_never_rewinds;
    @(posedge clk) disable iff (!rstn)
      1'b1 |=> (commit_ptr == $past(commit_ptr)) ||
               (commit_ptr == $past(commit_ptr) + 1'b1);
  endproperty

  // C2  At most one entry per cycle (5.4). C1 states it as a
  //     pointer transition; this states it as the step itself, so a
  //     step that advanced the pointer by more would fail both.
  property p_step_matches_ptr;
    @(posedge clk) disable iff (!rstn)
      commit_step_val |=> (commit_ptr == $past(commit_ptr) + 1'b1);
  endproperty

  // C3  No step in a suppression cycle. ras_decisions.md 4.5 orders
  //     BOS restore > commit > hold, so a redirect that restores
  //     takes the cycle. RC_UNSPEC does not restore but abandons the
  //     walk, so no cause steps.
  property p_no_step_on_redirect;
    @(posedge clk) disable iff (!rstn)
      redir_val |-> !commit_step_val;
  endproperty

  // C4  RC_UNSPEC leaves no walk behind it. 5.1 U3 squashes every
  //     entry, so the walk has nothing left to reach. The FQ-1
  //     guard depends on this: a walk end left ahead of a rewound
  //     alloc_ptr would stall the walk permanently.
  property p_unspec_clears_walk;
    @(posedge clk) disable iff (!rstn)
      (redir_val && redir_cause == RC_UNSPEC) |=> !commit_step_val;
  endproperty

  // C5  FQ-1 at this end. commit_ptr may not pass alloc_ptr, so a
  //     step requires a live entry to step over.
  property p_step_needs_entry;
    @(posedge clk) disable iff (!rstn)
      commit_step_val |-> (commit_ptr != alloc_ptr);
  endproperty

  a_commit_never_rewinds: assert property (p_commit_never_rewinds)
    else $error("C1 commit_ptr moved by something other than 0 or 1");
  a_step_matches_ptr:     assert property (p_step_matches_ptr)
    else $error("C2 a commit step did not advance commit_ptr by one");
  a_no_step_on_redirect:  assert property (p_no_step_on_redirect)
    else $error("C3 the walk advanced in a redirect cycle");
  a_unspec_clears_walk:   assert property (p_unspec_clears_walk)
    else $error("C4 a walk survived RC_UNSPEC");
  a_step_needs_entry:     assert property (p_step_needs_entry)
    else $error("C5 commit_ptr stepped with no live entry");

endmodule : ftq_commit_assert

// Bind BY MODULE NAME.
bind ftq_commit ftq_commit_assert u_assert (
  .clk             (clk),
  .rstn            (rstn),
  .commit_ptr      (commit_ptr),
  .alloc_ptr       (alloc_ptr),
  .commit_step_val (commit_step_val),
  .redir_val       (redir_val),
  .redir_cause     (redir_cause)
);
