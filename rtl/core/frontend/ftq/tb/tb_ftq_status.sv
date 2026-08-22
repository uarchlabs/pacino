// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ftq_status (BP-107), ftq_entry_formats.md 4.
//
// Self-checking. The three vectors are outputs, so every case reads
// the whole state rather than sampling a port.
//
// THE ACCEPTANCE CRITERION IS THE RANGE CLEAR: it touches exactly
// the entries in the range and no others, across a wrap. Group C is
// that, and it checks the COMPLEMENT as well as the range -- a clear
// that took the whole vector satisfies "the range is clear" and is
// the failure 4.1's masked-clear argument exists to prevent.
//
// EVERY MECHANISM THE CASES RELY ON IS ESTABLISHED, not assumed:
//
//   the reset value of all three vectors is checked in A1, not
//   taken on trust, because C's complement check reads entries no
//   case wrote;
//   gen starts at zero and is checked before any toggle, so B's
//   toggle checks compare against a known value rather than
//   against a previous read;
//   the live-window mask of R1 is exercised at both ends -- a fault
//   inside the window holds, the same bit outside it does not --
//   because a module that ignored the mask passes the first alone.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  logic [FTQ_PTR_BITS-1:0] commit_ptr;
  logic [FTQ_PTR_BITS-1:0] alloc_ptr;
  logic                    alloc_val;
  logic [FTQ_IDX_BITS-1:0] alloc_idx;
  logic                    wb_set_val;
  logic [FTQ_IDX_BITS-1:0] wb_set_idx;
  logic                    fault_set_val;
  logic [FTQ_IDX_BITS-1:0] fault_set_idx;
  logic                    squash_val;
  logic [FTQ_PTR_BITS-1:0] squash_start;
  logic [FTQ_PTR_BITS-1:0] squash_end;
  logic [FTQ_IDX_BITS-1:0] gen_rd_idx;
  logic                    gen_rd_val;
  logic [FTQ_IDX_BITS-1:0] gen_chk_idx;
  logic                    gen_chk_val;
  logic [FTQ_IDX_BITS-1:0] wb_rd_idx;
  logic                    wb_rd_val;
  logic                    fault_hold;
  logic [FTQ_DEPTH-1:0]    wb_rcvd;
  logic [FTQ_DEPTH-1:0]    fault;
  logic [FTQ_DEPTH-1:0]    gen;

  ftq_status dut (
    .clk           (clk),
    .rstn          (rstn),
    .commit_ptr    (commit_ptr),
    .alloc_ptr     (alloc_ptr),
    .alloc_val     (alloc_val),
    .alloc_idx     (alloc_idx),
    .wb_set_val    (wb_set_val),
    .wb_set_idx    (wb_set_idx),
    .fault_set_val (fault_set_val),
    .fault_set_idx (fault_set_idx),
    .squash_val    (squash_val),
    .squash_start  (squash_start),
    .squash_end    (squash_end),
    .gen_rd_idx    (gen_rd_idx),
    .gen_rd_val    (gen_rd_val),
    .gen_chk_idx   (gen_chk_idx),
    .gen_chk_val   (gen_chk_val),
    .wb_rd_idx     (wb_rd_idx),
    .wb_rd_val     (wb_rd_val),
    .fault_hold    (fault_hold),
    .wb_rcvd       (wb_rcvd),
    .fault         (fault),
    .gen           (gen)
  );

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

  task automatic tick();
    @(posedge clk);
    #1;
  endtask

  // PRESENT THE STATE ACROSS A CLOCK EDGE so the bound properties
  // SAMPLE it. A concurrent property samples at posedge clk, and a
  // case that drives its pointers, checks at a delta delay and moves
  // on never presents that state at an edge -- the property is then
  // inert (TD#109). Every write enable is low by the time a case
  // checks, so the edge leaves the three vectors unchanged; what it
  // changes is whether the properties see them.
  task automatic settle();
    #1;
    @(posedge clk);
    #1;
  endtask

  task automatic clr();
    alloc_val     = 1'b0;
    wb_set_val    = 1'b0;
    fault_set_val = 1'b0;
    squash_val    = 1'b0;
  endtask

  task automatic do_reset();
    rstn          = 1'b0;
    commit_ptr    = '0;
    alloc_ptr     = '0;
    alloc_idx     = '0;
    wb_set_idx    = '0;
    fault_set_idx = '0;
    squash_start  = '0;
    squash_end    = '0;
    gen_rd_idx    = '0;
    gen_chk_idx   = '0;
    wb_rd_idx     = '0;
    clr();
    repeat (4) tick();
    rstn = 1'b1;
    repeat (2) tick();
  endtask

  task automatic alloc(input int idx);
    alloc_val = 1'b1;
    alloc_idx = FTQ_IDX_BITS'(idx);
    tick();
    alloc_val = 1'b0;
  endtask

  task automatic set_wb(input int idx);
    wb_set_val = 1'b1;
    wb_set_idx = FTQ_IDX_BITS'(idx);
    tick();
    wb_set_val = 1'b0;
  endtask

  task automatic set_fault(input int idx);
    fault_set_val = 1'b1;
    fault_set_idx = FTQ_IDX_BITS'(idx);
    tick();
    fault_set_val = 1'b0;
  endtask

  task automatic squash(input int st, input int en);
    squash_val   = 1'b1;
    squash_start = FTQ_PTR_BITS'(st);
    squash_end   = FTQ_PTR_BITS'(en);
    tick();
    squash_val   = 1'b0;
  endtask

  // Membership of the half-open range [st, en) in index space, as
  // an independent model. The module takes an age; this takes the
  // same age. Written out so a case can state its expectation over
  // all 64 entries rather than over the two or three it touched.
  function automatic logic in_range(input int e, input int st,
                                    input int en);
    int len;
    int age;
    len = (en - st) & ((1 << FTQ_PTR_BITS) - 1);
    age = (e  - st) & (FTQ_DEPTH - 1);
    return (age < len);
  endfunction

  // -----------------------------------------------------------------
  // A. Reset.
  // -----------------------------------------------------------------
  task automatic group_a();
    $display("-- A: reset --");
    do_reset();

    chk("A1 wb_rcvd clear at reset", wb_rcvd == '0);
    chk("A2 fault clear at reset",   fault   == '0);
    chk("A3 gen clear at reset",     gen     == '0);
    chk("A4 no fault hold at reset", !fault_hold);
  endtask

  // -----------------------------------------------------------------
  // B. W1, W2, W3: allocation, writeback, fault.
  // -----------------------------------------------------------------
  task automatic group_b();
    $display("-- B: allocation, writeback and fault --");
    do_reset();

    alloc_ptr  = FTQ_PTR_BITS'(40);
    commit_ptr = '0;

    // W1. Allocation TOGGLES gen and clears the other two. gen was
    // proved zero by A3, so the toggle is checked against a known
    // value.
    alloc(5);
    chk("B1 allocation toggles gen", gen[5]);
    chk("B2 only the named entry toggled",
        gen == (64'b1 << 5));
    chk("B3 wb_rcvd still clear", wb_rcvd == '0);

    // W2 and W3. Both set, on different indices in one cycle -- the
    // writeback carries both and they may name different entries
    // when two are in flight.
    set_wb(5);
    chk("B4 wb_rcvd set on the writeback", wb_rcvd[5]);
    set_fault(6);
    chk("B5 fault set on the fault report", fault[6]);
    chk("B6 the fault did not set wb_rcvd", !wb_rcvd[6]);

    wb_set_val    = 1'b1;
    wb_set_idx    = 6'd7;
    fault_set_val = 1'b1;
    fault_set_idx = 6'd7;
    tick();
    clr();
    chk("B7 W2 and W3 fire together", wb_rcvd[7] && fault[7]);

    // W1 again on the same index. gen toggles BACK, and the other
    // two clear -- this is the stale bit surviving a wrap that W1
    // exists to prevent.
    alloc(5);
    chk("B8 gen toggles back", !gen[5]);
    chk("B9 allocation cleared wb_rcvd", !wb_rcvd[5]);

    alloc(7);
    chk("B10 allocation cleared both bits",
        !wb_rcvd[7] && !fault[7]);

    // ALLOCATION BEATS A WRITEBACK IN THE SAME CYCLE. The writeback
    // belongs to the OLD use of the index -- the generation test
    // that admitted it read the pre-toggle value -- so it must not
    // survive the reallocation. This is the TD-FE-8 race at the
    // status vector.
    alloc_val     = 1'b1;
    alloc_idx     = 6'd6;
    wb_set_val    = 1'b1;
    wb_set_idx    = 6'd6;
    fault_set_val = 1'b1;
    fault_set_idx = 6'd6;
    tick();
    clr();
    chk("B11 allocation beats a same-cycle writeback",
        !wb_rcvd[6] && !fault[6]);
    chk("B12 the allocation still toggled gen", gen[6]);

    // The same-cycle allocation and writeback of B11 is the state S4
    // guards. One more edge with the enables low presents it to the
    // properties; without it the group ends and the next group's
    // reset disables them before they ever sample it.
    tick();
  endtask

  // -----------------------------------------------------------------
  // C. W4: the masked range clear.
  // -----------------------------------------------------------------
  // ACCEPTANCE, Problem 2: a range clear touches exactly the entries
  // in the range and no others, across a wrap.
  task automatic group_c();
    $display("-- C: the masked range clear --");
    do_reset();

    commit_ptr = '0;
    alloc_ptr  = FTQ_PTR_BITS'(FTQ_DEPTH);

    // Set every bit of both vectors, so the clear has the whole
    // array to get wrong in either direction.
    for (int i = 0; i < FTQ_DEPTH; i++) begin
      wb_set_val    = 1'b1;
      wb_set_idx    = FTQ_IDX_BITS'(i);
      fault_set_val = 1'b1;
      fault_set_idx = FTQ_IDX_BITS'(i);
      tick();
    end
    clr();
    chk("C1 every wb_rcvd bit set", wb_rcvd == '1);
    chk("C2 every fault bit set",   fault   == '1);

    // A range in the middle: 20 through 34 inclusive, so
    // [20, 35). Fifteen entries.
    squash(20, 35);
    begin
      int bad_in;
      int bad_out;
      bad_in  = 0;
      bad_out = 0;
      for (int i = 0; i < FTQ_DEPTH; i++) begin
        if (in_range(i, 20, 35)) begin
          if (wb_rcvd[i] || fault[i]) bad_in++;
        end else begin
          if (!wb_rcvd[i] || !fault[i]) bad_out++;
        end
      end
      chk("C3 every entry in the range cleared", bad_in  == 0);
      chk("C4 no entry outside it cleared",      bad_out == 0);
    end
    chk("C5 the clear left gen alone", gen == '0);

    // ACROSS A WRAP. 58 through 66, which is 58..63 and 0..2 in
    // index space, so [58, 67) as pointers. A raw index compare
    // reports the empty set or the complement here and passes every
    // non-wrapping case above.
    for (int i = 0; i < FTQ_DEPTH; i++) begin
      wb_set_val    = 1'b1;
      wb_set_idx    = FTQ_IDX_BITS'(i);
      fault_set_val = 1'b1;
      fault_set_idx = FTQ_IDX_BITS'(i);
      tick();
    end
    clr();
    squash(58, 67);
    begin
      int bad_in;
      int bad_out;
      bad_in  = 0;
      bad_out = 0;
      for (int i = 0; i < FTQ_DEPTH; i++) begin
        if (in_range(i, 58, 67)) begin
          if (wb_rcvd[i] || fault[i]) bad_in++;
        end else begin
          if (!wb_rcvd[i] || !fault[i]) bad_out++;
        end
      end
      chk("C6 the wrapping range cleared",       bad_in  == 0);
      chk("C7 the wrapping complement survived", bad_out == 0);
    end

    // THE WHOLE WINDOW. RC_UNSPEC at full occupancy squashes 64
    // entries, and a length of 64 must not be read as a length of
    // zero -- the reason the length is taken on FTQ_PTR_BITS.
    for (int i = 0; i < FTQ_DEPTH; i++) begin
      wb_set_val = 1'b1;
      wb_set_idx = FTQ_IDX_BITS'(i);
      tick();
    end
    clr();
    squash(0, FTQ_DEPTH);
    chk("C8 a 64-entry range clears everything", wb_rcvd == '0);

    // AN EMPTY RANGE clears nothing. A redirect naming the newest
    // entry with _self clear produces start == end, and reading
    // that as a full window would wipe the live queue.
    set_wb(9);
    squash(30, 30);
    chk("C9 an empty range clears nothing", wb_rcvd[9]);

    // IN ONE CYCLE. The clear is not a walk: the whole range is
    // gone the cycle after squash_val, which is 4.1's decisive
    // reason these are flops.
    for (int i = 0; i < FTQ_DEPTH; i++) begin
      wb_set_val = 1'b1;
      wb_set_idx = FTQ_IDX_BITS'(i);
      tick();
    end
    clr();
    squash_val   = 1'b1;
    squash_start = FTQ_PTR_BITS'(10);
    squash_end   = FTQ_PTR_BITS'(50);
    tick();
    squash_val = 1'b0;
    begin
      int bad;
      bad = 0;
      for (int i = 0; i < FTQ_DEPTH; i++) begin
        if (in_range(i, 10, 50) && wb_rcvd[i]) bad++;
      end
      chk("C10 the whole range cleared in one cycle", bad == 0);
    end
  endtask

  // -----------------------------------------------------------------
  // D. The read ports.
  // -----------------------------------------------------------------
  task automatic group_d();
    $display("-- D: the read ports --");
    do_reset();

    alloc_ptr = FTQ_PTR_BITS'(FTQ_DEPTH);
    alloc(3);
    alloc(4);
    alloc(4);   // toggled twice, so back to zero
    set_wb(3);

    gen_rd_idx  = 6'd3;
    gen_chk_idx = 6'd4;
    wb_rd_idx   = 6'd3;
    settle();
    chk("D1 gen_rd reads its index",  gen_rd_val);
    chk("D2 gen_chk reads its index", !gen_chk_val);
    chk("D3 wb_rd reads its index",   wb_rd_val);

    // The two gen ports are independent: the request is at
    // fetch_ptr and the writeback names whatever entry it belongs
    // to, so a single port wired to both fails here.
    gen_rd_idx  = 6'd4;
    gen_chk_idx = 6'd3;
    settle();
    chk("D4 the two gen ports swap",
        !gen_rd_val && gen_chk_val);

    wb_rd_idx = 6'd5;
    settle();
    chk("D5 wb_rd on an unset entry", !wb_rd_val);
  endtask

  // -----------------------------------------------------------------
  // E. R1, the fault hold and its live-window mask.
  // -----------------------------------------------------------------
  task automatic group_e();
    $display("-- E: the fault hold --");
    do_reset();

    // A live window of entries 10 through 29.
    commit_ptr = FTQ_PTR_BITS'(10);
    alloc_ptr  = FTQ_PTR_BITS'(30);
    settle();
    chk("E1 no hold with no fault", !fault_hold);

    // A fault INSIDE the window holds.
    set_fault(15);
    settle();
    chk("E2 a fault in the live window holds", fault_hold);

    // THE SAME BIT, once the window has moved past it, does NOT
    // hold. A committed entry keeps its fault bit until its index
    // is reallocated, so an unmasked OR would hold the front end
    // for ever after the first fault -- the front end would stop
    // predicting and never resume.
    commit_ptr = FTQ_PTR_BITS'(20);
    settle();
    chk("E3 a fault behind commit_ptr does not hold", !fault_hold);
    chk("E4 the bit is still set",                    fault[15]);

    // A fault AHEAD of alloc_ptr does not hold either: those
    // entries are not live.
    set_fault(45);
    settle();
    chk("E5 a fault past alloc_ptr does not hold", !fault_hold);

    // Extending the window over it starts the hold.
    alloc_ptr = FTQ_PTR_BITS'(50);
    settle();
    chk("E6 extending the window over it holds", fault_hold);

    // An EMPTY queue never holds, whatever the vector says.
    commit_ptr = FTQ_PTR_BITS'(50);
    settle();
    chk("E7 an empty queue never holds", !fault_hold);

    // ACROSS A WRAP. A window from 60 to 68 covers 60..63 and 0..3;
    // a fault at index 2 is inside it and a fault at index 30 is
    // not, and a raw index compare gets both wrong.
    do_reset();
    commit_ptr = FTQ_PTR_BITS'(60);
    alloc_ptr  = FTQ_PTR_BITS'(68);
    set_fault(30);
    settle();
    chk("E8 a fault outside the wrapping window", !fault_hold);
    set_fault(2);
    settle();
    chk("E9 a fault inside the wrapping window",  fault_hold);
  endtask

  // -----------------------------------------------------------------
  // Run
  // -----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    if (FTQ_DEPTH != 64) begin
      $fatal(1, "tb_ftq_status: written for FTQ_DEPTH == 64");
    end

    do_reset();
    group_a();
    group_b();
    group_c();
    group_d();
    group_e();

    $display("tb_ftq_status: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ftq_status: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #400000;
    $fatal(1, "tb_ftq_status: timeout");
  end

endmodule : tb
