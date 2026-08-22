// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ftq_commit (BP-106, retrofitted BP-107).
//
// Self-checking. Every case establishes its start state by reset
// plus a known driven sequence. commit_ptr is not writable from
// outside the module by design, so a case that needs a non-zero
// start walks the pointer there through the watermark and then
// checks it arrived, rather than assuming it.
//
// alloc_ptr IS DRIVEN BY THE TESTBENCH, not by an ftq_ptr instance,
// for the same reason tb_ftq_ptr drives commit_ptr: the cases below
// need the queue placed at an exact occupancy -- one short of full,
// exactly full, straddling the wrap -- and a wired ftq_ptr would
// make that a function of its own advance rules. The driven
// sequences are all legal: alloc_ptr never falls behind commit_ptr
// and the live window never exceeds FTQ_ALLOC_LIMIT.
//
// EVERY MECHANISM THE CASES RELY ON IS ESTABLISHED HERE, not
// assumed. THE WATERMARK NOW CARRIES ITS GENERATION: the port is
// FTQ_PTR_BITS wide (ftq_backend_interfaces.md 6) and the module
// reconstructs nothing for it. Cases that used to derive the
// reconstruction in a comment now drive the full pointer, and the
// wrap case of group F drives 7'd66 rather than the aliasing 6'd2
// it had to drive before.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  localparam int PB  = FTQ_IDX_BITS + 1;   // pointer width, 7
  localparam int LIM = FTQ_DEPTH;          // FTQ_ALLOC_LIMIT, 64


  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  logic [PB-1:0]           alloc_ptr;
  logic                    bkend_commit_val;
  logic [PB-1:0]           bkend_commit_idx;
  logic                    redir_val;
  ftq_redir_cause_e        redir_cause;

  logic [PB-1:0]           commit_ptr;
  logic                    commit_step_val;
  logic [FTQ_IDX_BITS-1:0] commit_step_idx;
  logic                    walk_active;

  ftq_commit dut (
    .clk              (clk),
    .rstn             (rstn),
    .alloc_ptr        (alloc_ptr),
    .bkend_commit_val (bkend_commit_val),
    .bkend_commit_idx (bkend_commit_idx),
    .redir_val        (redir_val),
    .redir_cause      (redir_cause),
    .commit_ptr       (commit_ptr),
    .commit_step_val  (commit_step_val),
    .commit_step_idx  (commit_step_idx),
    .walk_active      (walk_active)
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
    bkend_commit_val = 1'b0;
    bkend_commit_idx = '0;
    redir_val        = 1'b0;
    redir_cause      = RC_MISPREDICT;
  endtask

  task automatic do_reset();
    rstn      = 1'b0;
    alloc_ptr = '0;
    clr();
    repeat (4) tick();
    rstn = 1'b1;
    repeat (2) tick();
  endtask

  // Present the watermark for one cycle so the walk end latches,
  // and leave it asserted. The end is registered, so the walk from
  // here on is independent of what the port does next.
  task automatic present_wm(input logic [PB-1:0] idx);
    bkend_commit_val = 1'b1;
    bkend_commit_idx = idx;
    tick();
  endtask

  // Tick n times and check the pointer advances by EXACTLY ONE each
  // cycle. This is the one-entry-per-cycle rule of 5.4 checked as a
  // rate, not as an end point: a module that jumped straight to the
  // watermark would reach the same final pointer and fail here.
  task automatic walk_ticks(input string nm, input int n);
    logic [PB-1:0] prev;
    int            bad;
    bad = 0;
    for (int i = 0; i < n; i++) begin
      prev = commit_ptr;
      tick();
      if (commit_ptr !== (prev + 1'b1)) bad++;
    end
    chk(nm, bad == 0);
  endtask

  // Tick n times and check the pointer does not move at all.
  task automatic hold_ticks(input string nm, input int n);
    logic [PB-1:0] prev;
    int            bad;
    bad  = 0;
    prev = commit_ptr;
    for (int i = 0; i < n; i++) begin
      tick();
      if (commit_ptr !== prev) bad++;
    end
    chk(nm, bad == 0);
  endtask

  // Walk commit_ptr to an exact value, so a case can start from a
  // known non-zero pointer without assuming residue. The watermark
  // is applied in steps of at most FTQ_DEPTH/2 so no step is ever
  // ambiguous, and the arrival is checked by the caller.
  task automatic walk_to(input int target);
    while (commit_ptr !== PB'(target)) begin
      alloc_ptr = PB'(target);
      present_wm(PB'(target - 1));
      while (walk_active) tick();
    end
    clr();
    tick();
  endtask

  // -----------------------------------------------------------------
  // A. Reset, and a watermark that jumps several entries.
  // -----------------------------------------------------------------
  task automatic group_a();
    $display("-- A: reset and a multi-entry watermark --");
    do_reset();

    chk_eq("A1 commit_ptr resets to 0", commit_ptr, '0);
    chk   ("A2 no walk after reset",    !walk_active);
    chk   ("A3 no step after reset",    !commit_step_val);

    // An empty queue has nothing to commit. alloc_ptr is still 0,
    // so the FQ-1 bound rejects any watermark.
    present_wm(PB'(3));
    hold_ticks("A4 no commit in an empty queue", 4);
    clr();
    tick();

    // Ten entries live, 0..9. The watermark names entry 4, so
    // entries 0 through 4 inclusive are freed: five steps.
    alloc_ptr = 7'd10;
    present_wm(PB'(4));
    chk("A5 walk starts after the watermark latches", walk_active);
    walk_ticks("A6 walk advances one entry per cycle", 5);
    chk_eq("A7 commit_ptr reached watermark+1", commit_ptr, 7'd5);
    chk   ("A8 walk stops at the watermark",    !walk_active);
    chk   ("A9 no step once stopped",           !commit_step_val);

    // The watermark is still asserted and unchanged. Repeating it
    // is harmless: this is the idempotence of backend_interfaces 6,
    // and it is what FTQ_ALLOC_LIMIT exists to keep harmless at
    // every occupancy. Here the held index 4 reconstructs to a walk
    // end of age FTQ_DEPTH, which exceeds the live window of 5.
    hold_ticks("A10 a held stale watermark does not walk", 8);
    clr();
    tick();
  endtask

  // -----------------------------------------------------------------
  // B. A watermark that does not advance, and one that deasserts
  //    mid-walk.
  // -----------------------------------------------------------------
  task automatic group_b();
    $display("-- B: stalled and deasserting watermarks --");
    do_reset();

    alloc_ptr = 7'd32;

    // Commit entry 0 only, then hold the watermark for a long time.
    present_wm(PB'(0));
    walk_ticks("B1 one step for a one-entry watermark", 1);
    chk_eq("B2 commit_ptr at 1", commit_ptr, 7'd1);
    hold_ticks("B3 a stalled watermark costs nothing", 10);

    // Advance it by one and the walk takes exactly one more step.
    bkend_commit_idx = PB'(1);
    tick();
    walk_ticks("B4 one more step when it advances", 1);
    chk_eq("B5 commit_ptr at 2", commit_ptr, 7'd2);
    hold_ticks("B6 stalled again", 5);

    // A WATERMARK THAT DEASSERTS MID-WALK. Name entry 20, let two
    // steps run, then drop bkend_commit_val. The end is registered,
    // so the remaining entries are still architecturally retired
    // and the walk must finish.
    bkend_commit_idx = PB'(20);
    tick();
    walk_ticks("B7 two steps before the deassert", 2);
    chk_eq("B8 commit_ptr at 4", commit_ptr, 7'd4);

    bkend_commit_val = 1'b0;
    bkend_commit_idx = '0;
    walk_ticks("B9 walk continues after the deassert", 17);
    chk_eq("B10 commit_ptr reached 21", commit_ptr, 7'd21);
    chk   ("B11 walk complete",         !walk_active);

    hold_ticks("B12 nothing further with the port idle", 6);
  endtask

  // -----------------------------------------------------------------
  // C. commit_ptr never rewinds, 5.5 R2.
  // -----------------------------------------------------------------
  task automatic group_c();
    $display("-- C: commit_ptr never rewinds --");
    do_reset();

    alloc_ptr = 7'd16;
    present_wm(PB'(9));
    walk_ticks("C1 walk to entry 9 inclusive", 10);
    chk_eq("C2 commit_ptr at 10", commit_ptr, 7'd10);
    clr();
    tick();

    // A MALFORMED WATERMARK BEHIND commit_ptr. Index 2 is below
    // commit_ptr's low bits, so the reconstruction places it in the
    // NEXT generation, at 7'h42, an age of 56 from commit_ptr. The
    // live window is only 6 entries, so the FQ-1 bound rejects it.
    // The point of the case is not which term rejects it but that
    // commit_ptr does not move.
    present_wm(PB'(2));
    hold_ticks("C3 a watermark behind does not rewind", 8);
    clr();
    tick();

    // A watermark equal to commit_ptr-1, the entry just committed.
    present_wm(PB'(9));
    hold_ticks("C4 the just-committed entry does not rewind", 6);
    clr();
    tick();

    // A watermark far past alloc_ptr. R2 makes this the backend's
    // break, not the FTQ's, but FQ-1 must survive it: the walk must
    // not run past alloc_ptr.
    present_wm(PB'(50));
    hold_ticks("C5 a watermark past alloc_ptr does not walk", 8);
    chk_eq("C6 commit_ptr still at 10", commit_ptr, 7'd10);
    clr();
    tick();

    // And a legal one still works afterwards, so the rejections
    // above did not wedge the module.
    present_wm(PB'(12));
    walk_ticks("C7 a legal watermark still walks", 3);
    chk_eq("C8 commit_ptr at 13", commit_ptr, 7'd13);
    clr();
    tick();
  endtask

  // -----------------------------------------------------------------
  // D. Suppression during a walk, 5.4 and ras_decisions 4.5.
  // -----------------------------------------------------------------
  task automatic group_d();
    $display("-- D: suppression during a walk --");
    do_reset();

    alloc_ptr = 7'd40;
    present_wm(PB'(30));
    walk_ticks("D1 three steps before the redirect", 3);
    chk_eq("D2 commit_ptr at 3", commit_ptr, 7'd3);

    // A restoring redirect fires. BOS priority is
    // restore > commit > hold, so the RAS commit this cycle is
    // suppressed and the walk does not advance.
    redir_val   = 1'b1;
    redir_cause = RC_MISPREDICT;
    #1;   // settle the combinational path before observing it
    chk("D3 step suppressed in the redirect cycle",
        !commit_step_val);
    hold_ticks("D4 walk held for the redirect cycle", 1);
    redir_val = 1'b0;

    // It resumes immediately: the walk end was untouched.
    chk("D5 walk still active after suppression", walk_active);
    walk_ticks("D6 walk resumes the next cycle", 4);
    chk_eq("D7 commit_ptr at 7", commit_ptr, 7'd7);

    // Every restoring cause suppresses, not just mispredict.
    redir_val   = 1'b1;
    redir_cause = RC_TRAP;
    hold_ticks("D8 RC_TRAP suppresses", 1);
    redir_cause = RC_REPLAY;
    hold_ticks("D9 RC_REPLAY suppresses", 1);
    redir_val = 1'b0;

    // A multi-cycle restore holds the walk for its whole length.
    redir_val   = 1'b1;
    redir_cause = RC_MISPREDICT;
    hold_ticks("D10 a held restore holds the walk", 5);
    redir_val = 1'b0;
    walk_ticks("D11 walk resumes after a held restore", 6);
    chk_eq("D12 commit_ptr at 13", commit_ptr, 7'd13);
    clr();
    tick();
  endtask

  // -----------------------------------------------------------------
  // E. RC_UNSPEC against a queue with a walk in progress.
  // -----------------------------------------------------------------
  task automatic group_e();
    $display("-- E: RC_UNSPEC with a walk in progress --");
    do_reset();

    alloc_ptr = 7'd40;
    present_wm(PB'(35));
    walk_ticks("E1 five steps into a long walk", 5);
    chk_eq("E2 commit_ptr at 5",     commit_ptr, 7'd5);
    chk   ("E3 walk still in progress", walk_active);

    // 5.1 U3 squashes EVERY entry, including the thirty the walk
    // had not yet reached. There is nothing left to walk to.
    redir_val   = 1'b1;
    redir_cause = RC_UNSPEC;
    #1;   // settle the combinational path before observing it
    chk("E4 no step in the RC_UNSPEC cycle", !commit_step_val);
    tick();
    redir_val = 1'b0;

    // ftq_ptr snaps alloc_ptr to commit_ptr on RC_UNSPEC; model it,
    // because leaving alloc_ptr where it was would let the FQ-1
    // bound rather than the abandonment be what holds the walk.
    alloc_ptr = commit_ptr;

    chk   ("E5 walk abandoned",           !walk_active);
    chk_eq("E6 commit_ptr did not rewind", commit_ptr, 7'd5);
    hold_ticks("E7 the walk does not resume", 12);

    // The abandoned end must not be left ahead of commit_ptr. If it
    // were, refilling the queue would restart a walk over entries
    // that no longer exist. Refill and check nothing walks on its
    // own.
    alloc_ptr = 7'd30;
    hold_ticks("E8 refilling does not restart the old walk", 8);

    // A fresh watermark after RC_UNSPEC works normally.
    present_wm(PB'(8));
    walk_ticks("E9 a fresh watermark walks normally", 4);
    chk_eq("E10 commit_ptr at 9", commit_ptr, 7'd9);
    clr();
    tick();
  endtask

  // -----------------------------------------------------------------
  // F. Wrap.
  // -----------------------------------------------------------------
  task automatic group_f();
    $display("-- F: walk across the wrap --");
    do_reset();

    walk_to(60);
    chk_eq("F1 commit_ptr walked to 60", commit_ptr, 7'd60);
    chk_eq("F2 generation still clear",
           PB'(commit_ptr[FTQ_IDX_BITS]), '0);

    // Eight more entries live: 60..67, which straddles the wrap.
    // The watermark names entry 7'd66 -- the generation bit is set
    // and arrives ON THE PORT, so the walk end is 7'd67 and the age
    // is seven with nothing reconstructed. Under the narrow port
    // this case had to drive 6'd2 and depend on the module placing
    // it in the far generation.
    alloc_ptr = 7'd68;
    present_wm(7'd66);
    chk("F3 walk starts across the wrap", walk_active);
    walk_ticks("F4 seven steps across the wrap", 7);
    chk_eq("F5 commit_ptr crossed to 67", commit_ptr, 7'd67);
    chk_eq("F6 generation set after the wrap",
           PB'(commit_ptr[FTQ_IDX_BITS]), 7'd1);
    chk_eq("F7 low bits wrapped to 3",
           PB'(commit_ptr[FTQ_IDX_BITS-1:0]), 7'd3);
    chk   ("F8 walk complete", !walk_active);

    // The held watermark is now stale again, on the far side of the
    // wrap this time.
    hold_ticks("F9 stale watermark after the wrap is inert", 8);
    clr();
    tick();
  endtask

  // -----------------------------------------------------------------
  // G. Full occupancy: the case FTQ_ALLOC_LIMIT exists for.
  // -----------------------------------------------------------------
  task automatic group_g();
    $display("-- G: full occupancy and the held watermark --");
    do_reset();

    alloc_ptr = 7'd20;
    present_wm(PB'(19));
    walk_ticks("G1 empty the queue", 20);
    chk_eq("G2 commit_ptr at 20", commit_ptr, 7'd20);

    // The FTQ now refills to FULL -- all 64 entries, the limit
    // BP-107 restored -- while the backend retires nothing. The
    // watermark is still 7'd19, the last entry committed. This is
    // the exact state the narrow port could not survive: at 64 live
    // entries a held INDEX of 19 was bit-identical to a watermark
    // naming the newest live entry, 7'd83, and the two demanded
    // opposite responses. With the generation on the port the held
    // value is 7'd19 and the newest live entry is 7'd83, so they
    // are different values and the held one is simply behind the
    // walk end and rejected.
    alloc_ptr = PB'(20 + LIM);
    hold_ticks("G3 held watermark inert at full occupancy", 16);
    chk_eq("G4 commit_ptr unmoved at full", commit_ptr, 7'd20);

    // A real advance of the watermark still commits the whole
    // queue, one entry per cycle. Entry 20+LIM-1 is the newest
    // live one.
    bkend_commit_idx = PB'(20 + LIM - 1);
    tick();
    chk("G5 a real advance starts the walk", walk_active);
    walk_ticks("G6 the full queue commits one per cycle", LIM);
    chk_eq("G7 commit_ptr reached alloc_ptr", commit_ptr,
           PB'(20 + LIM));
    chk   ("G8 walk complete", !walk_active);
    clr();
    tick();
  endtask

  // -----------------------------------------------------------------
  // H. commit_step_idx addresses the entry being freed.
  // -----------------------------------------------------------------
  task automatic group_h();
    $display("-- H: the freed entry index --");
    do_reset();

    alloc_ptr = 7'd12;
    present_wm(PB'(5));

    // The step index must be the entry AT commit_ptr, because that
    // is the entry whose bp_ras_snapshot_t forms the commit
    // payload. Checking it per step is what proves an off-by-one
    // here would be caught: a module reading commit_ptr+1 would
    // still finish at the right pointer.
    begin
      int bad;
      bad = 0;
      for (int i = 0; i <= 5; i++) begin
        if (!commit_step_val) bad++;
        if (commit_step_idx !== FTQ_IDX_BITS'(i)) bad++;
        if (commit_ptr[FTQ_IDX_BITS-1:0] !== FTQ_IDX_BITS'(i)) bad++;
        tick();
      end
      chk("H1 step index tracks the entry being freed", bad == 0);
    end

    chk_eq("H2 commit_ptr at 6", commit_ptr, 7'd6);
    chk   ("H3 no step once done", !commit_step_val);
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
      $fatal(1, "tb_ftq_commit: written for FTQ_DEPTH == 64, got %0d",
             FTQ_DEPTH);
    end

    rstn      = 1'b0;
    alloc_ptr = '0;
    clr();

    group_a();
    group_b();
    group_c();
    group_d();
    group_e();
    group_f();
    group_g();
    group_h();

    $display("tb_ftq_commit: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ftq_commit: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  // Watchdog. Time based, not cycle based: a cycle-based watchdog
  // waits on the very clock a hang can stop (BP-097, TD#111).
  initial begin
    #400000;
    $fatal(1, "tb_ftq_commit: timeout");
  end

endmodule : tb
