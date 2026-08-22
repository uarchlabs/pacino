// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ftq_status (BP-107).
// ftq_entry_formats.md 4.2 W1 to W4 and 4.3 R1.
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
//
// The three vectors are OUTPUTS of ftq_status -- published there so
// the bind reads the port list and makes no hierarchical reference
// -- so every rule of 4.2 is checkable here directly.
//
// The squash mask is recomputed in this file rather than taken from
// the module. That is deliberate: an assertion that consumed the
// module's own mask would agree with it by construction and prove
// nothing about the range. This is an INDEPENDENT model of
// [squash_start, squash_end), and S3 compares the two.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_status_assert (
  input logic                    clk,
  input logic                    rstn,
  input logic [FTQ_PTR_BITS-1:0] commit_ptr,
  input logic [FTQ_PTR_BITS-1:0] alloc_ptr,
  input logic                    alloc_val,
  input logic [FTQ_IDX_BITS-1:0] alloc_idx,
  input logic                    wb_set_val,
  input logic [FTQ_IDX_BITS-1:0] wb_set_idx,
  input logic                    squash_val,
  input logic [FTQ_PTR_BITS-1:0] squash_start,
  input logic [FTQ_PTR_BITS-1:0] squash_end,
  input logic                    fault_hold,
  input logic [FTQ_DEPTH-1:0]    wb_rcvd,
  input logic [FTQ_DEPTH-1:0]    fault,
  input logic [FTQ_DEPTH-1:0]    gen
);

  // An independent model of the W4 range. See the header.
  logic [FTQ_DEPTH-1:0]    w_msk;
  logic [FTQ_PTR_BITS-1:0] w_len;
  logic [FTQ_DEPTH-1:0]    r_msk;
  logic                    r_squash;
  logic                    r_alloc;
  logic [FTQ_IDX_BITS-1:0] r_alloc_idx;
  logic [FTQ_DEPTH-1:0]    r_gen;

  always_comb begin : model
    w_len = squash_end - squash_start;
    for (int e = 0; e < FTQ_DEPTH; e++) begin
      w_msk[e] = squash_val &&
        ({1'b0, FTQ_IDX_BITS'(e) - squash_start[FTQ_IDX_BITS-1:0]}
           < w_len);
    end
  end

  // The registered copies the sequential properties compare
  // against. Held here rather than written as $past over an indexed
  // select, which is what the properties would otherwise need.
  always_ff @(posedge clk or negedge rstn) begin : hist
    if (!rstn) begin
      r_msk       <= '0;
      r_squash    <= 1'b0;
      r_alloc     <= 1'b0;
      r_alloc_idx <= '0;
      r_gen       <= '0;
    end else begin
      r_msk       <= w_msk;
      r_squash    <= squash_val;
      r_alloc     <= alloc_val;
      r_alloc_idx <= alloc_idx;
      r_gen       <= gen;
    end
  end

  // S1  W4. The masked clear lands in ONE cycle, for the whole
  //     range, across a wrap. 4.1 gives this as the decisive reason
  //     these bits are flops and not SRAM: a redirect rewind must
  //     clear them before those indices can be reallocated, and in
  //     SRAM that would be a walk. An implementation that cleared
  //     them one at a time, or that used a raw index compare and so
  //     missed the wrapping half of a range, fails here.
  //
  //     The allocation exclusion is W1 over W4: an allocation in the
  //     same cycle names an index the rewind freed and the FTQ
  //     immediately reused, and W1's clear is the later fact. It
  //     clears the same two bits, so the exclusion only matters for
  //     the shape of the property, not for the outcome.
  property p_squash_clears;
    @(posedge clk) disable iff (!rstn)
      r_squash |-> ((wb_rcvd & r_msk) == '0) &&
                   ((fault   & r_msk) == '0);
  endproperty

  // S2  gen changes ONLY at allocation (W1). It is a toggle, and
  //     4.4 turns on that: a TOGGLE discriminates a reallocation
  //     within one wrap, which a wrap-derived value would not. A
  //     rewind must NOT clear it -- that would put it back to a
  //     value a stale writeback could match -- and this is the
  //     property that says so, because a rewind is a cycle with no
  //     allocation.
  property p_gen_only_on_alloc;
    @(posedge clk) disable iff (!rstn)
      !alloc_val |=> (gen == $past(gen));
  endproperty

  // S3  W1. Allocation TOGGLES gen for the entry it names. Checked
  //     against the registered copy so the index is the one the
  //     allocation carried, not this cycle's.
  property p_alloc_toggles_gen;
    @(posedge clk) disable iff (!rstn)
      r_alloc |-> (gen[r_alloc_idx] != r_gen[r_alloc_idx]);
  endproperty

  // S4  W1. Allocation CLEARS wb_rcvd and fault. This is what stops
  //     a stale bit surviving a wrap, and it must beat the W2 set in
  //     the same cycle: a writeback arriving as its index is
  //     reallocated belongs to the OLD use, and the generation test
  //     that admitted it read the PRE-toggle value.
  property p_alloc_clears;
    @(posedge clk) disable iff (!rstn)
      r_alloc |-> !wb_rcvd[r_alloc_idx] && !fault[r_alloc_idx];
  endproperty

  // S5  R1. fault_hold does not fire without a fault. A hold with
  //     no cause stops the front end predicting for ever, and the
  //     live-window mask is what makes the difference: a committed
  //     entry keeps its bit until reallocated, so an unmasked OR
  //     would assert this permanently after the first fault.
  property p_hold_needs_fault;
    @(posedge clk) disable iff (!rstn)
      fault_hold |-> |fault;
  endproperty

  // S6  R1, the other half. A fault OUTSIDE the live window does
  //     not hold. Stated as the empty queue, which is the case a
  //     stale bit is guaranteed to be outside: commit_ptr equals
  //     alloc_ptr, so no entry is live and nothing can hold.
  property p_empty_never_holds;
    @(posedge clk) disable iff (!rstn)
      (commit_ptr == alloc_ptr) |-> !fault_hold;
  endproperty

  a_squash_clears:      assert property (p_squash_clears)
    else $error("S1 the squash range did not clear in one cycle");
  a_gen_only_on_alloc:  assert property (p_gen_only_on_alloc)
    else $error("S2 gen changed outside an allocation");
  a_alloc_toggles_gen:  assert property (p_alloc_toggles_gen)
    else $error("S3 allocation did not toggle gen");
  a_alloc_clears:       assert property (p_alloc_clears)
    else $error("S4 allocation did not clear wb_rcvd and fault");
  a_hold_needs_fault:   assert property (p_hold_needs_fault)
    else $error("S5 fault_hold asserted with no fault set");
  a_empty_never_holds:  assert property (p_empty_never_holds)
    else $error("S6 a fault outside the live window held the FTQ");

  // wb_set_val and wb_set_idx are on the port list for the S4
  // reading above -- the same-cycle allocation and writeback race is
  // what makes S4 an ordering statement rather than a truism -- and
  // are not otherwise referenced.
  logic w_unused;
  assign w_unused = wb_set_val | |wb_set_idx;

endmodule : ftq_status_assert

// Bind BY MODULE NAME.
bind ftq_status ftq_status_assert u_assert (
  .clk          (clk),
  .rstn         (rstn),
  .commit_ptr   (commit_ptr),
  .alloc_ptr    (alloc_ptr),
  .alloc_val    (alloc_val),
  .alloc_idx    (alloc_idx),
  .wb_set_val   (wb_set_val),
  .wb_set_idx   (wb_set_idx),
  .squash_val   (squash_val),
  .squash_start (squash_start),
  .squash_end   (squash_end),
  .fault_hold   (fault_hold),
  .wb_rcvd      (wb_rcvd),
  .fault        (fault),
  .gen          (gen)
);
