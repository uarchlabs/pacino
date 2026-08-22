// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ftq_ptr (BP-106, retrofitted BP-107).
//
// Self-checking. Every case establishes its start state by reset
// plus a known driven sequence; the module holds two pointers and
// nothing else, and every case that needs a non-zero start walks
// there from reset rather than assuming residue.
//
// commit_ptr IS DRIVEN BY THE TESTBENCH, not by an ftq_commit
// instance. That is deliberate. Wiring the real pair would make
// commit_ptr a function of ftq_commit's walk and remove the ability
// to place it exactly where a case needs it -- one short of a wrap,
// or held while allocation laps the array. The pair is exercised
// as a pair by the properties bound to each module, which hold
// against any legal input sequence, not by a wired testbench.
//
// The commit_ptr sequences driven below are all LEGAL: commit_ptr
// only ever advances, and never past fetch_ptr. Driving it
// illegally would violate FQ-1 and the bound properties would fail,
// which is the intended behaviour and not what these cases test.
//
// THE 64-LIVE ALIAS STATE IS NOW DRIVEN, in group B. Under BP-106
// FTQ_ALLOC_LIMIT stopped one short and alloc_ptr[5:0] equal to
// commit_ptr[5:0] with differing generations was unreachable. The
// commit watermark carries its generation now
// (ftq_backend_interfaces.md 6), the limit is back at FTQ_DEPTH,
// and that state is ordinary full occupancy -- so it is reached
// deliberately and checked, and Q3 was re-aimed to say the two
// statements of full agree rather than that one never happens.
//
// The cases also still cover the adjacency the generation bit
// exists to separate: after a full lap the low bits alias at EMPTY,
// and the design must read empty rather than full.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  localparam int PB = FTQ_IDX_BITS + 1;   // pointer width, 7
  localparam int LIM = FTQ_DEPTH;         // FTQ_ALLOC_LIMIT, 64

  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  logic [PB-1:0]            commit_ptr;
  logic                     alloc_req_val;
  logic                     alloc_req_rdy;
  logic                     ifu_req_val;
  logic                     ifu_req_rdy;
  logic                     alloc_inflight;
  logic                     redir_val;
  logic [FTQ_IDX_BITS-1:0]  redir_idx;
  logic                     redir_self;
  ftq_redir_cause_e         redir_cause;

  logic [PB-1:0]            alloc_ptr;
  logic [PB-1:0]            fetch_ptr;
  logic                     ftq_full;
  logic                     ftq_empty;
  logic                     fetch_pending;
  logic                     ptr_alias_full;
  logic                     squash_val;
  logic [PB-1:0]            squash_start;
  logic [PB-1:0]            squash_end;
  logic [FTQ_IDX_BITS-1:0]  alloc_idx;
  logic [FTQ_IDX_BITS-1:0]  fetch_idx;

  ftq_ptr dut (
    .clk            (clk),
    .rstn           (rstn),
    .commit_ptr     (commit_ptr),
    .alloc_req_val  (alloc_req_val),
    .alloc_req_rdy  (alloc_req_rdy),
    .ifu_req_val    (ifu_req_val),
    .ifu_req_rdy    (ifu_req_rdy),
    .alloc_inflight (alloc_inflight),
    .redir_val      (redir_val),
    .redir_idx      (redir_idx),
    .redir_self     (redir_self),
    .redir_cause    (redir_cause),
    .alloc_ptr      (alloc_ptr),
    .fetch_ptr      (fetch_ptr),
    .ftq_full       (ftq_full),
    .ftq_empty      (ftq_empty),
    .fetch_pending  (fetch_pending),
    .ptr_alias_full (ptr_alias_full),
    .squash_val     (squash_val),
    .squash_start   (squash_start),
    .squash_end     (squash_end),
    .alloc_idx      (alloc_idx),
    .fetch_idx      (fetch_idx)
  );

  // -----------------------------------------------------------------
  // Scoreboard
  // -----------------------------------------------------------------
  int pass_cnt;
  int fail_cnt;

  task automatic chk(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
      $display("PASS: %s", nm);
    end else begin
      fail_cnt++;
      $display("FAIL: %s", nm);
    end
  endtask

  task automatic chk_eq(input string nm,
                        input logic [PB-1:0] got,
                        input logic [PB-1:0] exp);
    if (got === exp) begin
      pass_cnt++;
      $display("PASS: %s", nm);
    end else begin
      fail_cnt++;
      $display("FAIL: %s  got %02h exp %02h", nm, got, exp);
    end
  endtask

  // -----------------------------------------------------------------
  // Stimulus helpers
  // -----------------------------------------------------------------
  task automatic tick();
    @(posedge clk);
    #1;
  endtask

  task automatic clr();
    alloc_req_val = 1'b0;
    alloc_req_rdy = 1'b0;
    ifu_req_val   = 1'b0;
    ifu_req_rdy   = 1'b0;
    // The p0-to-p1 gap. Held clear for every case below, so
    // fetch_pending is the raw 5.1 gap and the existing
    // expectations stand unchanged. Group G drives it.
    alloc_inflight = 1'b0;
    redir_val     = 1'b0;
    redir_idx     = '0;
    redir_self    = 1'b0;
    redir_cause   = RC_MISPREDICT;
  endtask

  task automatic do_reset();
    rstn       = 1'b0;
    commit_ptr = '0;
    clr();
    repeat (4) tick();
    rstn = 1'b1;
    repeat (2) tick();
  endtask

  // Present n accepted prediction requests at p0, one per cycle.
  // Acceptance is alloc_req_val & alloc_req_rdy; the module applies
  // the full gate itself.
  task automatic alloc_n(input int n);
    alloc_req_val = 1'b1;
    alloc_req_rdy = 1'b1;
    repeat (n) tick();
    alloc_req_val = 1'b0;
    alloc_req_rdy = 1'b0;
  endtask

  // Issue n accepted fetch requests, one per cycle.
  task automatic fetch_n(input int n);
    ifu_req_val = 1'b1;
    ifu_req_rdy = 1'b1;
    repeat (n) tick();
    ifu_req_val = 1'b0;
    ifu_req_rdy = 1'b0;
  endtask

  // Advance the driven commit_ptr by n, one per cycle, as the real
  // ftq_commit would. Never driven past fetch_ptr.
  task automatic commit_n(input int n);
    for (int i = 0; i < n; i++) begin
      commit_ptr = commit_ptr + 1'b1;
      tick();
    end
  endtask

  // One redirect cycle. idx, self and cause are the winning
  // redirect ftq_npc publishes (7.3).
  task automatic redirect(input logic [FTQ_IDX_BITS-1:0] idx,
                          input logic                    self_sq,
                          input ftq_redir_cause_e        cause);
    redir_val   = 1'b1;
    redir_idx   = idx;
    redir_self  = self_sq;
    redir_cause = cause;
    tick();
    redir_val   = 1'b0;
    redir_idx   = '0;
    redir_self  = 1'b0;
    redir_cause = RC_MISPREDICT;
  endtask

  // -----------------------------------------------------------------
  // A. Reset, and the basic advance rules of 5.2.
  // -----------------------------------------------------------------
  task automatic group_a();
    $display("-- A: reset and basic advance --");
    do_reset();

    chk_eq("A1 alloc_ptr resets to 0", alloc_ptr, '0);
    chk_eq("A2 fetch_ptr resets to 0", fetch_ptr, '0);
    chk   ("A3 empty after reset",     ftq_empty);
    chk   ("A4 not full after reset",  !ftq_full);
    chk   ("A5 no fetch pending",      !fetch_pending);

    // An accepted request advances alloc_ptr by exactly one.
    alloc_n(1);
    chk_eq("A6 alloc_ptr advances on accept", alloc_ptr, 7'd1);
    chk   ("A7 not empty once allocated",     !ftq_empty);
    chk   ("A8 fetch pending after alloc",    fetch_pending);

    // A request that is NOT accepted does not advance it. This is
    // hold condition H1 of 4.5: a queued predictor could not take
    // the request, so the index was never spoken for.
    alloc_req_val = 1'b1;
    alloc_req_rdy = 1'b0;
    repeat (3) tick();
    chk_eq("A9 unaccepted request does not allocate", alloc_ptr, 7'd1);
    clr();

    // Ready without a request does not allocate either.
    alloc_req_val = 1'b0;
    alloc_req_rdy = 1'b1;
    repeat (3) tick();
    chk_eq("A10 rdy without val does not allocate", alloc_ptr, 7'd1);
    clr();

    // fetch_ptr advances on val & rdy, and only up to alloc_ptr.
    fetch_n(1);
    chk_eq("A11 fetch_ptr advances on accept", fetch_ptr, 7'd1);
    chk   ("A12 no fetch pending once caught up", !fetch_pending);

    // FQ-1: fetch_ptr may not pass alloc_ptr. Keep asking.
    fetch_n(5);
    chk_eq("A13 fetch_ptr held at alloc_ptr", fetch_ptr, 7'd1);
    chk_eq("A14 alloc_ptr unmoved by fetch",  alloc_ptr, 7'd1);

    // With commit_ptr driven up behind it, all three are equal.
    commit_n(1);
    chk   ("A15 empty when all three equal", ftq_empty);
  endtask

  // -----------------------------------------------------------------
  // B. Full and empty adjacency, and what the generation bit
  //    separates.
  // -----------------------------------------------------------------
  task automatic group_b();
    $display("-- B: full and empty adjacency --");
    do_reset();

    // One short of the limit.
    alloc_n(LIM - 1);
    chk_eq("B1 alloc_ptr at limit-1", alloc_ptr, PB'(LIM - 1));
    chk   ("B2 not full one short",   !ftq_full);

    // The entry that makes it full.
    alloc_n(1);
    chk_eq("B3 alloc_ptr at the limit", alloc_ptr, PB'(LIM));
    chk   ("B4 full at the limit",      ftq_full);
    chk   ("B5 not empty while full",   !ftq_empty);

    // FULL BLOCKS ALLOCATION. Accepted requests keep arriving and
    // the pointer does not move.
    alloc_n(8);
    chk_eq("B6 full blocks allocation", alloc_ptr, PB'(LIM));

    // FULL BLOCKS ALLOCATION AND NOTHING ELSE (5.1). Fetch is
    // untouched by it -- that is the decoupling the FTQ exists for.
    fetch_n(4);
    chk_eq("B7 fetch advances while full", fetch_ptr, 7'd4);
    chk   ("B8 still full after fetching", ftq_full);

    // THE 5.1 ALIAS STATE, entered deliberately. 64 live entries:
    // the low bits of alloc_ptr and commit_ptr are equal and the
    // generations differ. This is what the widened watermark made
    // safe and what the reverted FTQ_ALLOC_LIMIT restores; under
    // BP-106 it was unreachable by construction.
    chk("B9a alias-full asserted at 64 live", ptr_alias_full);
    chk("B9b alias-full agrees with ftq_full",
        ptr_alias_full == ftq_full);
    chk("B9c the 64th entry is live",
        (alloc_ptr - commit_ptr) == PB'(FTQ_DEPTH));

    // Freeing one entry unblocks allocation, and exactly one.
    commit_n(1);
    chk("B10 not full after one free", !ftq_full);
    alloc_n(1);
    chk_eq("B11 one more allocated", alloc_ptr, PB'(LIM + 1));
    chk   ("B12 full again",         ftq_full);
  endtask

  // -----------------------------------------------------------------
  // C. Wrap, forward, in all three pointers.
  // -----------------------------------------------------------------
  task automatic group_c();
    $display("-- C: forward wrap --");
    do_reset();

    // Walk the whole queue round one full lap, keeping the three
    // pointers together so nothing ever goes full. After 64 steps
    // the low bits are back at zero and the generation has flipped.
    for (int i = 0; i < FTQ_DEPTH; i++) begin
      alloc_n(1);
      fetch_n(1);
      commit_n(1);
    end

    chk_eq("C1 alloc_ptr wrapped, gen set",  alloc_ptr,  7'h40);
    chk_eq("C2 fetch_ptr wrapped, gen set",  fetch_ptr,  7'h40);
    chk_eq("C3 commit_ptr wrapped, gen set", commit_ptr, 7'h40);
    chk_eq("C4 alloc_idx back to zero", PB'(alloc_idx), '0);
    chk_eq("C5 fetch_idx back to zero", PB'(fetch_idx), '0);

    // THE ADJACENCY THE GENERATION BIT SEPARATES. The low bits of
    // alloc_ptr and commit_ptr are both zero here, exactly as they
    // were at reset. Without the generation bit a full lap and an
    // empty queue would be the same state. With it, this reads
    // empty, which is what it is.
    chk("C6 empty after a full lap",     ftq_empty);
    chk("C7 not full after a full lap",  !ftq_full);
    chk("C8 alias-full clear after lap", !ptr_alias_full);

    // A second lap behaves the same, so the generation bit toggles
    // back rather than sticking.
    for (int i = 0; i < FTQ_DEPTH; i++) begin
      alloc_n(1);
      fetch_n(1);
      commit_n(1);
    end
    chk_eq("C9 alloc_ptr after two laps", alloc_ptr, '0);
    chk   ("C10 empty after two laps",    ftq_empty);
  endtask

  // -----------------------------------------------------------------
  // D. Redirect rewind, 5.5 R1.
  // -----------------------------------------------------------------
  task automatic group_d();
    $display("-- D: redirect rewind --");
    do_reset();

    // Ten entries allocated, six fetched, none committed.
    alloc_n(10);
    fetch_n(6);
    chk_eq("D1 alloc_ptr at 10", alloc_ptr, 7'd10);
    chk_eq("D2 fetch_ptr at 6",  fetch_ptr, 7'd6);

    // _self CLEAR: the naming instruction completed, so entry 3
    // survives and allocation restarts at 4. fetch_ptr was at 6,
    // ahead of the new head, so it rewinds with it.
    // The squash range of 5.5 R3 is published for ftq_status while
    // the redirect is presented, so it is sampled inside the
    // redirect cycle rather than after it.
    redir_val   = 1'b1;
    redir_idx   = 6'd3;
    redir_self  = 1'b0;
    redir_cause = RC_MISPREDICT;
    #1;
    chk   ("D3a squash_val asserted in the redirect cycle",
           squash_val);
    chk_eq("D3b squash_start is the new head", squash_start, 7'd4);
    chk_eq("D3c squash_end is the old head",   squash_end,  7'd10);
    tick();
    clr();
    chk_eq("D3 alloc_ptr rewound to K+1", alloc_ptr, 7'd4);
    chk_eq("D4 fetch_ptr clamped to K+1", fetch_ptr, 7'd4);
    chk   ("D4a squash_val clear with no redirect", !squash_val);

    // _self SET: the naming instruction is squashed too, so entry 2
    // does not survive and allocation restarts at 2.
    redirect(6'd2, 1'b1, RC_TRAP);
    chk_eq("D5 alloc_ptr rewound to K", alloc_ptr, 7'd2);
    chk_eq("D6 fetch_ptr clamped to K", fetch_ptr, 7'd2);

    // A redirect naming an entry AHEAD of fetch_ptr leaves
    // fetch_ptr alone: those entries are still live and still need
    // issuing. Rebuild a gap first.
    do_reset();
    alloc_n(10);
    fetch_n(2);
    redirect(6'd6, 1'b0, RC_REPLAY);
    chk_eq("D7 alloc_ptr rewound to 7",      alloc_ptr, 7'd7);
    chk_eq("D8 fetch_ptr behind head, held", fetch_ptr, 7'd2);

    // A redirect outranks an allocation in the same cycle
    // (backend_interfaces 7 R1).
    do_reset();
    alloc_n(10);
    alloc_req_val = 1'b1;
    alloc_req_rdy = 1'b1;
    redirect(6'd4, 1'b0, RC_MISPREDICT);
    clr();
    chk_eq("D9 redirect outranks allocation", alloc_ptr, 7'd5);

    // REWIND ACROSS A WRAP. commit_ptr is left at 60 while
    // allocation runs past the wrap to 68, so the live window
    // straddles the boundary and the naming index must have its
    // generation reconstructed rather than read.
    do_reset();
    alloc_n(60);
    fetch_n(60);
    commit_n(60);
    alloc_n(8);
    fetch_n(8);
    chk_eq("D10 alloc_ptr past the wrap", alloc_ptr, 7'd68);
    chk_eq("D11 commit_ptr before it",    commit_ptr, 7'd60);

    // Index 2 is BELOW commit_ptr's low bits, so it belongs to the
    // next generation: entry 7'h42, not 7'h02. Allocation restarts
    // at 7'h43.
    redirect(6'd2, 1'b0, RC_MISPREDICT);
    chk_eq("D12 rewind across wrap, K+1", alloc_ptr, 7'h43);
    chk_eq("D13 fetch_ptr follows",       fetch_ptr, 7'h43);

    // Index 62 is AT OR ABOVE commit_ptr's low bits, so it belongs
    // to commit_ptr's own generation: entry 7'h3E, on the near side
    // of the wrap.
    redirect(6'd62, 1'b1, RC_TRAP);
    chk_eq("D14 rewind to the near side", alloc_ptr, 7'h3E);
    chk_eq("D15 fetch_ptr follows back",  fetch_ptr, 7'h3E);

    // A redirect naming commit_ptr itself with _self set empties
    // the queue. R2 permits an index AT commit_ptr.
    chk("D16 not empty before", !ftq_empty);
    redirect(6'd60, 1'b1, RC_REPLAY);
    chk_eq("D17 alloc_ptr back to commit_ptr", alloc_ptr, 7'd60);
    chk   ("D18 queue empty",                  ftq_empty);
  endtask

  // -----------------------------------------------------------------
  // E. RC_UNSPEC, backend_interfaces 5.1.
  // -----------------------------------------------------------------
  task automatic group_e();
    $display("-- E: RC_UNSPEC --");
    do_reset();

    alloc_n(20);
    fetch_n(12);
    commit_n(5);
    chk_eq("E1 alloc_ptr at 20",  alloc_ptr,  7'd20);
    chk_eq("E2 fetch_ptr at 12",  fetch_ptr,  7'd12);
    chk_eq("E3 commit_ptr at 5",  commit_ptr, 7'd5);

    // U1, U2, U3: _idx and _self are meaningless and every entry is
    // squashed. Both are driven to values that would give a very
    // different answer if they were read, so a module that read
    // them fails here rather than passing by coincidence.
    redir_val   = 1'b1;
    redir_idx   = 6'd17;
    redir_self  = 1'b1;
    redir_cause = RC_UNSPEC;
    #1;
    // U3 squashes EVERY entry, so the exported range is the whole
    // live window. It falls out of w_alloc_tgt being commit_ptr and
    // is not cased separately.
    chk_eq("E3a squash_start is commit_ptr", squash_start, 7'd5);
    chk_eq("E3b squash_end is the old head", squash_end,  7'd20);
    tick();
    clr();
    chk_eq("E4 alloc_ptr snaps to commit_ptr", alloc_ptr,  7'd5);
    chk_eq("E5 fetch_ptr snaps to commit_ptr", fetch_ptr,  7'd5);
    chk_eq("E6 commit_ptr never rewinds",      commit_ptr, 7'd5);
    chk   ("E7 queue empty after RC_UNSPEC",   ftq_empty);
    chk   ("E8 not full after RC_UNSPEC",      !ftq_full);

    // _self clear gives the same answer: RC_UNSPEC is
    // unconditional (U2).
    alloc_n(9);
    fetch_n(3);
    redirect(6'd0, 1'b0, RC_UNSPEC);
    chk_eq("E9 unconditional with _self clear", alloc_ptr, 7'd5);
    chk   ("E10 empty again",                   ftq_empty);

    // RC_UNSPEC on an already empty queue is a no-op.
    redirect(6'd33, 1'b1, RC_UNSPEC);
    chk_eq("E11 no-op on an empty queue", alloc_ptr, 7'd5);
    chk   ("E12 still empty",             ftq_empty);

    // RC_UNSPEC across a wrap, with commit_ptr in the far
    // generation.
    do_reset();
    alloc_n(60);
    fetch_n(60);
    commit_n(60);
    alloc_n(10);
    fetch_n(4);
    chk_eq("E13 alloc_ptr past the wrap", alloc_ptr, 7'd70);
    redirect(6'd9, 1'b0, RC_UNSPEC);
    chk_eq("E14 snaps to commit_ptr across wrap", alloc_ptr, 7'd60);
    chk_eq("E15 fetch_ptr with it",               fetch_ptr, 7'd60);
    chk   ("E16 empty across the wrap",           ftq_empty);
  endtask

  // -----------------------------------------------------------------
  // F. Full reached across a wrap, and released across it.
  // -----------------------------------------------------------------
  task automatic group_f();
    $display("-- F: full across a wrap --");
    do_reset();

    // Put commit_ptr at 40 and fill from there, so the full
    // condition is reached with the pointers in different
    // generations and the low bits nowhere near equal.
    alloc_n(40);
    fetch_n(40);
    commit_n(40);
    chk_eq("F1 commit_ptr at 40", commit_ptr, 7'd40);

    alloc_n(LIM);
    chk_eq("F2 alloc_ptr at 40+limit", alloc_ptr, PB'(40 + LIM));
    chk   ("F3 full across the wrap",   ftq_full);
    chk   ("F4 not empty",              !ftq_empty);
    chk   ("F5 alias-full set at 64 live", ptr_alias_full);
    chk   ("F6 generations differ",
           alloc_ptr[FTQ_IDX_BITS] != commit_ptr[FTQ_IDX_BITS]);

    alloc_n(4);
    chk_eq("F7 still blocked", alloc_ptr, PB'(40 + LIM));

    // Fetch drains the whole queue while full; still not a stall.
    fetch_n(LIM);
    chk_eq("F8 fetch caught up while full", fetch_ptr,
           PB'(40 + LIM));
    chk   ("F9 no fetch pending",           !fetch_pending);
    chk   ("F10 still full",                ftq_full);

    // Free the lot and the queue is empty, not full, with the low
    // bits of all three equal again.
    commit_n(LIM);
    chk("F11 empty after freeing all", ftq_empty);
    chk("F12 not full",                !ftq_full);
  endtask

  // -----------------------------------------------------------------
  // G. The p0-to-p1 allocation gap.
  // -----------------------------------------------------------------
  // alloc_ptr advances at p0 and the entry CONTENT is written at p1
  // one cycle later (5.2), so the newest entry inside the 5.1
  // run-ahead gap has an index and no content for that one cycle.
  // fetch_pending must exclude it or the FTQ issues a fetch for an
  // entry whose pc does not exist yet -- reachable in the first two
  // cycles out of reset, not in a corner.
  task automatic group_g();
    $display("-- G: the p0 to p1 allocation gap --");
    do_reset();

    // One entry allocated and its p1 write still in flight. The raw
    // gap is one; the WRITTEN gap is zero.
    alloc_n(1);
    alloc_inflight = 1'b1;
    #1;
    chk_eq("G1 alloc_ptr at 1",             alloc_ptr, 7'd1);
    chk   ("G2 no fetch pending in flight", !fetch_pending);

    // Asking for a fetch anyway does not move fetch_ptr: the module
    // enforces it rather than trusting the caller to read
    // fetch_pending.
    fetch_n(3);
    chk_eq("G3 fetch_ptr held while in flight", fetch_ptr, '0);

    // The write lands. The entry is now fetchable.
    alloc_inflight = 1'b0;
    #1;
    chk("G4 fetch pending once written", fetch_pending);
    fetch_n(1);
    chk_eq("G5 fetch_ptr advances", fetch_ptr, 7'd1);

    // With a run-ahead of several entries the gap subtracts exactly
    // one, not all of them: the older entries are written and must
    // still be fetchable while the newest is in flight.
    alloc_n(5);
    alloc_inflight = 1'b1;
    #1;
    chk_eq("G6 alloc_ptr at 6",              alloc_ptr, 7'd6);
    chk   ("G7 still pending with 4 written", fetch_pending);
    fetch_n(4);
    chk_eq("G8 fetch_ptr stops one short", fetch_ptr, 7'd5);
    chk   ("G9 no pending at the frontier", !fetch_pending);
    fetch_n(2);
    chk_eq("G10 still one short", fetch_ptr, 7'd5);

    alloc_inflight = 1'b0;
    #1;
    fetch_n(1);
    chk_eq("G11 the last entry issues once written", fetch_ptr, 7'd6);
    clr();
    tick();
  endtask

  // -----------------------------------------------------------------
  // Run
  // -----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    if (FTQ_DEPTH != 64) begin
      $fatal(1, "tb_ftq_ptr: written for FTQ_DEPTH == 64, got %0d",
             FTQ_DEPTH);
    end

    rstn       = 1'b0;
    commit_ptr = '0;
    clr();

    group_a();
    group_b();
    group_c();
    group_d();
    group_e();
    group_f();
    group_g();

    $display("tb_ftq_ptr: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ftq_ptr: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  // Watchdog. Time based, not cycle based: a cycle-based watchdog
  // waits on the very clock a hang can stop (BP-097, TD#111).
  initial begin
    #400000;
    $fatal(1, "tb_ftq_ptr: timeout");
  end

endmodule : tb
