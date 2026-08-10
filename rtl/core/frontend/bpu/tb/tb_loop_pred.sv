// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_loop_pred.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking testbench for loop_pred.sv.
//
// TC1-TC13 and TC18 are the directed algorithm set: cold miss,
// backward alloc, forward no-alloc, low-conf hit, confidence build,
// trusted taken, trusted exit, correct exit, wrong exit,
// mispredicted exit, victim selection, way conflict, curr_itr
// saturation, conf saturation. Each runs once per prediction slot
// (BP-091).
//
// TC14-TC17 are the slot retrofit set:
//   TC14  slot independence -- an update to one slot must not
//         perturb any other slot's bank or prediction
//   TC14B the same, with a live update payload held on the quiet
//         slot behind a deasserted valid
//   TC15  both slots predicting in the same cycle
//   TC16  both slots updating in the same cycle
//   TC17  reset -- every bank reaches the documented reset state
//
// Start state. Every test case begins with do_reset(), which drives
// every input to its idle value and holds rstn low for two cycles.
// No test case carries state from another, and no check relies on
// the absence of residue: reset is the invalidation of every set of
// every bank and TC17 proves reset does that.
//
// A failed check calls $fatal(1). $finish(1) does not produce a
// non-zero process exit under Verilator v5.048, which is how a
// failing run once reported a passing make target (BP-086).
// ===================================================================


import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  // ----------------------------------------------------------------
  // DUT signals. The slot dimension comes from the package; the
  // testbench writes no slot-count literal.
  // ----------------------------------------------------------------
  logic                      clk;
  logic                      rstn;
  logic [VA_WIDTH-1:0]       pred_pc_p0 [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] pred_valid_p0;
  lp_pred_t                  pred_p1    [0:NUM_PRED_SLOTS-1];
  lp_upd_t                   upd_p0     [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] upd_valid_p0;

  loop_pred #(
    .NUM_PRED_SLOTS (NUM_PRED_SLOTS)
  ) dut (
    .clk           (clk),
    .rstn          (rstn),
    .pred_pc_p0    (pred_pc_p0),
    .pred_valid_p0 (pred_valid_p0),
    .pred_p1       (pred_p1),
    .upd_p0        (upd_p0),
    .upd_valid_p0  (upd_valid_p0)
  );

  // ----------------------------------------------------------------
  // Clock: 10ns period
  // ----------------------------------------------------------------
  initial clk = 0;
  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  // ----------------------------------------------------------------
  // Timeout watchdog (BP-097, TD#111)
  // ----------------------------------------------------------------
  // TD#111 was closed at four files; this one was missed. tb_loop_pred
  // had no watchdog at all, so a DUT that never responds hung make
  // rather than failing it. Time-based, not cycle-based, so it fires
  // even when the hang stops the clock.
  // Limit: normal completion measured at 8000 time units this
  // session. 200000 is 25x that and matches the #200000 bound the sc
  // and tage_table testbenches carry.
  initial begin
    #200000;
    $fatal(1, "tb_loop_pred: TIMEOUT watchdog expired");
  end

  // ----------------------------------------------------------------
  // Index and tag helpers (mirror loop_pred.sv hash functions).
  // Neither takes a slot argument: the slot is not part of the hash,
  // so the same PC selects the same set and tag in every bank.
  // ----------------------------------------------------------------
  function automatic logic [LP_IDX_BITS-1:0]
      idx_of(input logic [VA_WIDTH-1:0] pc);
    logic [VA_WIDTH-1:0] x;
    x = pc ^ (pc >> 1) ^ (pc >> 4);
    return x[LP_IDX_BITS-1:0];
  endfunction

  function automatic logic [LP_TAG_BITS-1:0]
      tag_of(input logic [VA_WIDTH-1:0] pc);
    logic [VA_WIDTH-1:0] x;
    x = pc ^ (pc >> 6) ^ (pc >> 12);
    return x[LP_TAG_BITS-1:0];
  endfunction

  // ----------------------------------------------------------------
  // Test infrastructure
  // ----------------------------------------------------------------
  // PC sweep length for TC17 part A. Wide enough to reach every set
  // of the bank; the coverage is asserted rather than assumed.
  localparam int SWEEP_PCS = 512;

  int fail_count;
  int check_count;

  // A failed check is fatal. $fatal(1) exits non-zero; $finish(1)
  // does not (BP-086).
  task automatic check(
    input string tc,
    input logic  cond,
    input string msg
  );
    check_count++;
    if (!cond) begin
      fail_count++;
      $display("FAIL [%s]: %s", tc, msg);
      $fatal(1, "FAIL [%s]: %s", tc, msg);
    end
  endtask

  // Drive every input of every slot to its idle value.
  task automatic idle_all;
    for (int i = 0; i < NUM_PRED_SLOTS; i++) begin
      pred_pc_p0[i] = '0;
      upd_p0[i]     = '0;
    end
    pred_valid_p0 = '0;
    upd_valid_p0  = '0;
  endtask

  // 2-cycle active reset, deassert, 1 settling cycle.
  task automatic do_reset;
    rstn = 1'b0;
    idle_all();
    @(posedge clk); #1;
    @(posedge clk); #1;
    rstn = 1'b1;
    @(posedge clk); #1;
  endtask

  // One lookup on slot sl. Every other slot stays invalid, so a
  // crossed pred_valid connection is visible as a lost prediction.
  task automatic do_pred(
    input int                  sl,
    input logic [VA_WIDTH-1:0] pc
  );
    idle_all();
    pred_pc_p0[sl]    = pc;
    pred_valid_p0[sl] = 1'b1;
    @(posedge clk); #1;
    pred_valid_p0[sl] = 1'b0;
  endtask

  // One update on slot sl. Every other slot's upd_valid stays low.
  task automatic send_upd(input int sl, input lp_upd_t u);
    for (int i = 0; i < NUM_PRED_SLOTS; i++) upd_p0[i] = '0;
    upd_valid_p0   = '0;
    upd_p0[sl]     = u;
    upd_valid_p0[sl] = 1'b1;
    @(posedge clk); #1;
    upd_valid_p0[sl] = 1'b0;
    upd_p0[sl]       = '0;
  endtask

  // Allocation update: backward branch miss (lp_hit=0). victim is
  // the way chosen at prediction time.
  function automatic lp_upd_t mk_alloc(
    input logic [VA_WIDTH-1:0]    pc,
    input logic [VA_WIDTH-1:0]    target,
    input logic [LP_WAY_BITS-1:0] victim
  );
    lp_upd_t u;
    u                 = '0;
    u.pc              = pc;
    u.target          = target;
    u.actual_taken    = 1'b1;
    u.lp_hit          = 1'b0;
    u.lp_pred_is_loop = 1'b0;
    u.lp_idx          = idx_of(pc);
    u.lp_tag          = tag_of(pc);
    u.lp_victim       = victim;
    return u;
  endfunction

  // Allocate one entry on slot sl via a backward branch miss.
  task automatic alloc_entry(
    input int                     sl,
    input logic [VA_WIDTH-1:0]    pc,
    input logic [VA_WIDTH-1:0]    target,
    input logic [LP_WAY_BITS-1:0] victim
  );
    send_upd(sl, mk_alloc(pc, target, victim));
  endtask

  // Slot label for check identifiers.
  function automatic string sl_of(input int sl);
    return $sformatf("s%0d", sl);
  endfunction

  // ================================================================
  // TC1: Cold miss -- lp_pred_is_loop must be 0
  // ================================================================
  task automatic tc1(input int sl);
    do_reset();
    do_pred(sl, 40'h0000_1100);
    check($sformatf("TC1.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_is_loop == 1'b0,
          "cold lookup: lp_pred_is_loop should be 0");
    check($sformatf("TC1b.%s", sl_of(sl)),
          pred_p1[sl].lp_hit == 1'b0,
          "cold lookup: lp_hit should be 0");
    $display("TC1  slot %0d -- Cold miss: PASS", sl);
  endtask

  // ================================================================
  // TC2: Backward branch miss allocates; lookup shows lp_hit=1.
  // After reset all ways are invalid -> victim=0, way=0.
  // ================================================================
  task automatic tc2(input int sl);
    logic [VA_WIDTH-1:0] pc2, tgt2;
    do_reset();
    pc2  = 40'h0000_2200;
    tgt2 = pc2 - 40'd256;  // backward: tgt < pc
    alloc_entry(sl, pc2, tgt2, LP_WAY_BITS'(0));
    do_pred(sl, pc2);
    check($sformatf("TC2a.%s", sl_of(sl)),
          pred_p1[sl].lp_hit == 1'b1,
          "after alloc: lp_hit should be 1");
    check($sformatf("TC2b.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_is_loop == 1'b0,
          "after alloc: cnf=0, lp_pred_is_loop should be 0");
    check($sformatf("TC2c.%s", sl_of(sl)),
          pred_p1[sl].lp_way == LP_WAY_BITS'(0),
          "after alloc: entry should be at way 0");
    $display("TC2  slot %0d -- Backward alloc: PASS", sl);
  endtask

  // ================================================================
  // TC3: Forward branch miss -- no allocation, lp_hit stays 0.
  // target > pc disables the alloc path in loop_pred.
  // ================================================================
  task automatic tc3(input int sl);
    logic [VA_WIDTH-1:0] pc3, tgt3;
    lp_upd_t             u;
    do_reset();
    pc3  = 40'h0000_3300;
    tgt3 = pc3 + 40'd256;  // forward: tgt > pc -> no alloc
    u    = mk_alloc(pc3, tgt3, LP_WAY_BITS'(0));
    send_upd(sl, u);
    do_pred(sl, pc3);
    check($sformatf("TC3.%s", sl_of(sl)),
          pred_p1[sl].lp_hit == 1'b0,
          "forward branch: no alloc, lp_hit should be 0");
    $display("TC3  slot %0d -- Forward no-alloc: PASS", sl);
  endtask

  // ================================================================
  // TC4: Hit with cnf < LP_CONF_LEVEL -- lp_pred_is_loop=0.
  // Entry present (lp_hit=1) but confidence not yet at max.
  // ================================================================
  task automatic tc4(input int sl);
    logic [VA_WIDTH-1:0] pc4, tgt4;
    do_reset();
    pc4  = 40'h0000_4400;
    tgt4 = pc4 - 40'd256;
    alloc_entry(sl, pc4, tgt4, LP_WAY_BITS'(0));
    do_pred(sl, pc4);
    check($sformatf("TC4a.%s", sl_of(sl)),
          pred_p1[sl].lp_hit == 1'b1,
          "TC4: entry present, lp_hit should be 1");
    check($sformatf("TC4b.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_is_loop == 1'b0,
          "TC4: cnf<LP_CONF_LEVEL, lp_pred_is_loop should be 0");
    $display("TC4  slot %0d -- Low-conf hit: PASS", sl);
  endtask

  // ================================================================
  // TC5/TC6/TC7 share one entry (PC=0x5500, 2-iteration loop).
  //
  // Confidence build sequence:
  //   alloc       -> cnf=0, curr=1,  past=0
  //   wrong exit  -> cnf=0, curr=0,  past=1
  //   [x LP_CONF_LEVEL rounds]:
  //     cond5 taken     -> curr: 0->1 (no cnf change)
  //     correct exit    -> cnf++, curr=0, past=1
  //   After rounds: cnf=LP_CONF_LEVEL, past=1, curr=0.
  //   lookup -> TC5 (lp_pred_is_loop=1) and TC6 (lp_pred_taken=1).
  //   cond1 update -> curr: 0->1 (=past).
  //   lookup -> TC7 (lp_pred_taken=0, exit).
  // ================================================================
  task automatic tc567(input int sl);
    logic [VA_WIDTH-1:0]    pc5, tgt5;
    logic [LP_IDX_BITS-1:0] idx5;
    logic [LP_TAG_BITS-1:0] tag5;
    lp_upd_t                u;
    int                     c;

    do_reset();
    pc5  = 40'h0000_5500;
    tgt5 = pc5 - 40'd256;
    idx5 = idx_of(pc5);
    tag5 = tag_of(pc5);

    // --- Step 1: allocate ---
    // bank after: v=1, cnf=0, curr_itr=1, past_itr=0, age=max
    alloc_entry(sl, pc5, tgt5, LP_WAY_BITS'(0));

    // --- Step 2: wrong exit (curr=1 != past=0) ---
    // bank after: cnf=0, past_itr=1, curr_itr=0
    u                 = '0;
    u.lp_hit          = 1'b1;
    u.lp_pred_is_loop = 1'b0;
    u.actual_taken    = 1'b0;  // not taken (attempted exit)
    u.lp_curr_itr     = LP_ITR_BITS'(1);
    u.lp_past_itr     = LP_ITR_BITS'(0);
    u.lp_conf         = LP_CNF_BITS'(0);
    u.lp_idx          = idx5;
    u.lp_tag          = tag5;
    u.lp_way          = LP_WAY_BITS'(0);
    u.pc              = pc5;
    u.target          = tgt5;
    send_upd(sl, u);

    // --- Steps 3-N: LP_CONF_LEVEL rounds of cond5 + correct exit ---
    c = 0;
    for (int i = 0; i < LP_CONF_LEVEL; i++) begin
      // Cond5: lp_hit=1, lp_pred_is_loop=0, actual_taken=1.
      // curr_itr in the bank (=0) increments to 1; cnf unchanged.
      u                 = '0;
      u.lp_hit          = 1'b1;
      u.lp_pred_is_loop = 1'b0;
      u.actual_taken    = 1'b1;
      u.lp_curr_itr     = LP_ITR_BITS'(0);
      u.lp_past_itr     = LP_ITR_BITS'(1);
      u.lp_conf         = LP_CNF_BITS'(c);
      u.lp_idx          = idx5;
      u.lp_tag          = tag5;
      u.lp_way          = LP_WAY_BITS'(0);
      u.pc              = pc5;
      u.target          = tgt5;
      send_upd(sl, u);
      // bank after: cnf=c, curr_itr=1, past_itr=1

      // Correct exit: actual_taken=0, curr_itr=1==past_itr=1
      // -> cnf = c+1, past_itr=1, curr_itr=0
      u                 = '0;
      u.lp_hit          = 1'b1;
      u.lp_pred_is_loop = 1'b0;
      u.actual_taken    = 1'b0;
      u.lp_curr_itr     = LP_ITR_BITS'(1);
      u.lp_past_itr     = LP_ITR_BITS'(1);
      u.lp_conf         = LP_CNF_BITS'(c);
      u.lp_idx          = idx5;
      u.lp_tag          = tag5;
      u.lp_way          = LP_WAY_BITS'(0);
      u.pc              = pc5;
      u.target          = tgt5;
      send_upd(sl, u);
      c = c + 1;
      // bank after: cnf=c, past_itr=1, curr_itr=0
    end
    // bank: cnf=LP_CONF_LEVEL, past_itr=1, curr_itr=0

    // TC5/TC6 lookup: curr_itr=0 < past_itr=1
    do_pred(sl, pc5);

    check($sformatf("TC5.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_is_loop == 1'b1,
          "cnf=LP_CONF_LEVEL: lp_pred_is_loop should be 1");
    $display("TC5  slot %0d -- Confidence at max: PASS", sl);

    check($sformatf("TC6a.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_is_loop == 1'b1,
          "TC6: lp_pred_is_loop should be 1 (trusted)");
    check($sformatf("TC6b.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_taken == 1'b1,
          "TC6: curr_itr<past_itr, lp_pred_taken should be 1");
    $display("TC6  slot %0d -- Trusted taken: PASS", sl);

    // -- TC7: advance curr_itr to past_itr, then verify exit --
    // Cond1: lp_pred_is_loop=1, lp_pred_taken=1, actual_taken=1
    // -> curr_itr: 0 -> 1 (= past_itr). cnf unchanged.
    u                 = '0;
    u.lp_pred_is_loop = 1'b1;
    u.lp_hit          = 1'b1;
    u.actual_taken    = 1'b1;
    u.lp_pred_taken   = 1'b1;
    u.lp_curr_itr     = LP_ITR_BITS'(0);
    u.lp_past_itr     = LP_ITR_BITS'(1);
    u.lp_conf         = LP_CNF_BITS'(LP_CONF_LEVEL);
    u.lp_idx          = idx5;
    u.lp_tag          = tag5;
    u.lp_way          = LP_WAY_BITS'(0);
    u.pc              = pc5;
    u.target          = tgt5;
    send_upd(sl, u);
    // bank: cnf=max, past_itr=1, curr_itr=1

    do_pred(sl, pc5);
    check($sformatf("TC7a.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_is_loop == 1'b1,
          "TC7: lp_pred_is_loop should be 1 (trusted)");
    check($sformatf("TC7b.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_taken == 1'b0,
          "TC7: curr_itr==past_itr, lp_pred_taken should be 0");
    $display("TC7  slot %0d -- Trusted exit: PASS", sl);
  endtask

  // ================================================================
  // TC8: Correct exit -- conf++, past_itr=curr_itr, curr_itr=0,
  //      age=max
  // ================================================================
  task automatic tc8(input int sl);
    logic [VA_WIDTH-1:0] pc8;
    lp_upd_t             u;
    do_reset();
    pc8 = 40'hC800;
    // lp_hit=1, lp_pred_is_loop=0, actual_taken=0,
    // curr_itr==past_itr=5 -> correct exit fires.
    u                 = '0;
    u.lp_hit          = 1'b1;
    u.lp_pred_is_loop = 1'b0;
    u.actual_taken    = 1'b0;
    u.lp_curr_itr     = LP_ITR_BITS'(5);
    u.lp_past_itr     = LP_ITR_BITS'(5);
    u.lp_conf         = LP_CNF_BITS'(2);
    u.lp_age          = 8'h64;
    u.lp_idx          = idx_of(pc8);
    u.lp_tag          = tag_of(pc8);
    u.lp_way          = LP_WAY_BITS'(0);
    u.pc              = pc8;
    u.target          = pc8 - 40'd256;
    send_upd(sl, u);
    do_pred(sl, pc8);
    check($sformatf("TC8a.%s", sl_of(sl)),
          pred_p1[sl].lp_conf == LP_CNF_BITS'(LP_CONF_LEVEL),
          "correct exit: conf should increment to max");
    check($sformatf("TC8b.%s", sl_of(sl)),
          pred_p1[sl].lp_past_itr == LP_ITR_BITS'(5),
          "correct exit: past_itr should hold prev curr_itr");
    check($sformatf("TC8c.%s", sl_of(sl)),
          pred_p1[sl].lp_curr_itr == '0,
          "correct exit: curr_itr should reset to 0");
    check($sformatf("TC8d.%s", sl_of(sl)),
          pred_p1[sl].lp_age == {LP_AGE_BITS{1'b1}},
          "correct exit: age should reset to max");
    $display("TC8  slot %0d -- Correct exit: PASS", sl);
  endtask

  // ================================================================
  // TC9: Wrong exit -- conf=0, past_itr=curr_itr, curr_itr=0
  // ================================================================
  task automatic tc9(input int sl);
    logic [VA_WIDTH-1:0] pc9;
    lp_upd_t             u;
    do_reset();
    pc9 = 40'hD900;
    // curr_itr(7) != past_itr(3) -> wrong exit fires.
    u                 = '0;
    u.lp_hit          = 1'b1;
    u.lp_pred_is_loop = 1'b0;
    u.actual_taken    = 1'b0;
    u.lp_curr_itr     = LP_ITR_BITS'(7);
    u.lp_past_itr     = LP_ITR_BITS'(3);
    u.lp_conf         = LP_CNF_BITS'(2);
    u.lp_idx          = idx_of(pc9);
    u.lp_tag          = tag_of(pc9);
    u.lp_way          = LP_WAY_BITS'(0);
    u.pc              = pc9;
    u.target          = pc9 - 40'd256;
    send_upd(sl, u);
    do_pred(sl, pc9);
    check($sformatf("TC9a.%s", sl_of(sl)),
          pred_p1[sl].lp_conf == '0,
          "wrong exit: conf should reset to 0");
    check($sformatf("TC9b.%s", sl_of(sl)),
          pred_p1[sl].lp_past_itr == LP_ITR_BITS'(7),
          "wrong exit: past_itr should hold prev curr_itr");
    check($sformatf("TC9c.%s", sl_of(sl)),
          pred_p1[sl].lp_curr_itr == '0,
          "wrong exit: curr_itr should reset to 0");
    $display("TC9  slot %0d -- Wrong exit: PASS", sl);
  endtask

  // ================================================================
  // TC10: Mispredicted exit (cond4) -- conf=0, curr_itr=0,
  //       past_itr unchanged
  // ================================================================
  task automatic tc10(input int sl);
    logic [VA_WIDTH-1:0] pc10;
    lp_upd_t             u;
    do_reset();
    pc10 = 40'hE100;
    // lp_pred_is_loop=1, lp_pred_taken=0, actual_taken=1 -> cond4.
    u                 = '0;
    u.lp_hit          = 1'b1;
    u.lp_pred_is_loop = 1'b1;
    u.lp_pred_taken   = 1'b0;
    u.actual_taken    = 1'b1;
    u.lp_curr_itr     = LP_ITR_BITS'(4);
    u.lp_past_itr     = LP_ITR_BITS'(5);
    u.lp_conf         = LP_CNF_BITS'(LP_CONF_LEVEL);
    u.lp_idx          = idx_of(pc10);
    u.lp_tag          = tag_of(pc10);
    u.lp_way          = LP_WAY_BITS'(0);
    u.pc              = pc10;
    u.target          = pc10 - 40'd256;
    send_upd(sl, u);
    do_pred(sl, pc10);
    check($sformatf("TC10a.%s", sl_of(sl)),
          pred_p1[sl].lp_conf == '0,
          "mispred exit: conf should reset to 0");
    check($sformatf("TC10b.%s", sl_of(sl)),
          pred_p1[sl].lp_curr_itr == '0,
          "mispred exit: curr_itr should reset to 0");
    check($sformatf("TC10c.%s", sl_of(sl)),
          pred_p1[sl].lp_past_itr == LP_ITR_BITS'(5),
          "mispred exit: past_itr should be unchanged (=5)");
    $display("TC10 slot %0d -- Mispredicted exit: PASS", sl);
  endtask

  // ================================================================
  // TC11: Victim selection -- all ways valid, priority 3.
  //       Fill ways 0-3 at idx11 (age=max each).
  //       Lower way 1 age to 1 via a cond5 hit update.
  //       Predict PC_11 (miss) -> victim must be way 1.
  // PC_11=0x80: idx=8, tag=0x0082 (distinct from tags 1..4)
  // ================================================================
  task automatic tc11(input int sl);
    logic [VA_WIDTH-1:0]    pc11;
    logic [LP_IDX_BITS-1:0] idx11;
    logic [LP_TAG_BITS-1:0] tag11;
    lp_upd_t                u;

    do_reset();
    pc11  = 40'h0000_0080;
    idx11 = idx_of(pc11);  // = 8
    tag11 = tag_of(pc11);  // = 0x0082, distinct from 1..4
    check($sformatf("TC11pre.%s", sl_of(sl)),
          (tag11 != LP_TAG_BITS'(1)) && (tag11 != LP_TAG_BITS'(2)) &&
          (tag11 != LP_TAG_BITS'(3)) && (tag11 != LP_TAG_BITS'(4)),
          "TC11: probe tag must not alias the four filler tags");

    // Allocate all 4 ways at idx11 with tags 1..4.
    // The alloc entry carries age=max(0xFF) and curr_itr=1.
    for (int w = 0; w < LP_TBL_WAYS; w++) begin
      u                 = '0;
      u.actual_taken    = 1'b1;
      u.lp_hit          = 1'b0;
      u.lp_pred_is_loop = 1'b0;
      u.lp_idx          = idx11;
      u.pc              = 40'hFF00;
      u.target          = 40'hF000;  // target < pc -> backward
      u.lp_tag          = LP_TAG_BITS'(w + 1);
      u.lp_victim       = LP_WAY_BITS'(w);
      send_upd(sl, u);
    end

    // Ways 0-3: valid, age=0xFF, tags 1..4.
    // Lower way 1 age to 0x01 via cond5 (lp_hit=1,
    // lp_pred_is_loop=0, actual_taken=1). Cond5 does not override
    // age, so u.lp_age=1 passes through.
    u                 = '0;
    u.lp_hit          = 1'b1;
    u.lp_pred_is_loop = 1'b0;
    u.actual_taken    = 1'b1;
    u.lp_idx          = idx11;
    u.lp_tag          = LP_TAG_BITS'(2);  // way 1 tag
    u.lp_way          = LP_WAY_BITS'(1);
    u.lp_age          = 8'h01;
    u.pc              = 40'hFF00;
    u.target          = 40'hF000;
    send_upd(sl, u);
    // way0: age=0xFF. way1: age=0x01. ways2,3: age=0xFF.
    // Prio 3: way1.age(1) < way0.age(0xFF) -> victim = way 1

    do_pred(sl, pc11);
    check($sformatf("TC11a.%s", sl_of(sl)),
          pred_p1[sl].lp_hit == 1'b0,
          "TC11: non-matching tags on all ways, miss expected");
    check($sformatf("TC11b.%s", sl_of(sl)),
          pred_p1[sl].lp_victim == LP_WAY_BITS'(1),
          "TC11: way 1 has lowest age, victim should be way 1");
    $display("TC11 slot %0d -- Victim selection: PASS", sl);
  endtask

  // ================================================================
  // TC12: Way conflict -- two PCs in one set, tracked independently.
  //       PC_12a=0x1000 (idx=0, tag=0x1041) -> way 0
  //       PC_12b=0x2000 (idx=0, tag=0x2082) -> way 1
  // ================================================================
  task automatic tc12(input int sl);
    logic [VA_WIDTH-1:0]    pc12a, pc12b;
    logic [LP_IDX_BITS-1:0] idx12;
    logic [LP_TAG_BITS-1:0] tag12a, tag12b;
    lp_upd_t                u;

    do_reset();
    pc12a  = 40'h0000_1000;
    pc12b  = 40'h0000_2000;
    idx12  = idx_of(pc12a);
    tag12a = tag_of(pc12a);
    tag12b = tag_of(pc12b);
    check($sformatf("TC12pre.%s", sl_of(sl)),
          (idx_of(pc12b) == idx12) && (tag12a != tag12b),
          "TC12: the two PCs must share a set and differ in tag");

    alloc_entry(sl, pc12a, pc12a - 40'd256, LP_WAY_BITS'(0));
    alloc_entry(sl, pc12b, pc12b - 40'd256, LP_WAY_BITS'(1));
    // Both entries: curr_itr=1, past_itr=0, cnf=0, age=max.

    // Cond5 update for entry A: curr_itr 2 -> 3
    u                 = '0;
    u.lp_hit          = 1'b1;
    u.lp_pred_is_loop = 1'b0;
    u.actual_taken    = 1'b1;
    u.lp_curr_itr     = LP_ITR_BITS'(2);
    u.lp_past_itr     = LP_ITR_BITS'(5);
    u.lp_idx          = idx12;
    u.lp_tag          = tag12a;
    u.lp_way          = LP_WAY_BITS'(0);
    u.pc              = pc12a;
    u.target          = pc12a - 40'd256;
    send_upd(sl, u);

    // Cond5 update for entry B: curr_itr 4 -> 5
    u                 = '0;
    u.lp_hit          = 1'b1;
    u.lp_pred_is_loop = 1'b0;
    u.actual_taken    = 1'b1;
    u.lp_curr_itr     = LP_ITR_BITS'(4);
    u.lp_past_itr     = LP_ITR_BITS'(5);
    u.lp_idx          = idx12;
    u.lp_tag          = tag12b;
    u.lp_way          = LP_WAY_BITS'(1);
    u.pc              = pc12b;
    u.target          = pc12b - 40'd256;
    send_upd(sl, u);

    do_pred(sl, pc12a);
    check($sformatf("TC12a.%s", sl_of(sl)),
          pred_p1[sl].lp_curr_itr == LP_ITR_BITS'(3),
          "way conflict: entry A curr_itr should be 3");

    do_pred(sl, pc12b);
    check($sformatf("TC12b.%s", sl_of(sl)),
          pred_p1[sl].lp_curr_itr == LP_ITR_BITS'(5),
          "way conflict: entry B curr_itr should be 5");
    $display("TC12 slot %0d -- Way conflict: PASS", sl);
  endtask

  // ================================================================
  // TC13: curr_itr saturates at LP_ITR_BITS max (no overflow).
  //       RTL cond1: (&curr_itr) ? curr_itr : curr_itr+1.
  //       Drive max-1 -> max, then verify max stays at max.
  // ================================================================
  task automatic tc13(input int sl);
    logic [VA_WIDTH-1:0]    pc13;
    logic [LP_IDX_BITS-1:0] idx13;
    logic [LP_TAG_BITS-1:0] tag13;
    logic [LP_ITR_BITS-1:0] itr_max;
    lp_upd_t                u;

    do_reset();
    pc13    = 40'hA000;
    idx13   = idx_of(pc13);
    tag13   = tag_of(pc13);
    itr_max = {LP_ITR_BITS{1'b1}};

    alloc_entry(sl, pc13, pc13 - 40'd256, LP_WAY_BITS'(0));

    // Cond1: curr_itr = max-1 -> max (one increment to saturation).
    u                 = '0;
    u.lp_hit          = 1'b1;
    u.lp_pred_is_loop = 1'b1;
    u.lp_pred_taken   = 1'b1;
    u.actual_taken    = 1'b1;
    u.lp_curr_itr     = itr_max - LP_ITR_BITS'(1);
    u.lp_past_itr     = itr_max;
    u.lp_conf         = LP_CNF_BITS'(LP_CONF_LEVEL);
    u.lp_idx          = idx13;
    u.lp_tag          = tag13;
    u.lp_way          = LP_WAY_BITS'(0);
    u.pc              = pc13;
    u.target          = pc13 - 40'd256;
    send_upd(sl, u);
    do_pred(sl, pc13);
    check($sformatf("TC13a.%s", sl_of(sl)),
          pred_p1[sl].lp_curr_itr == itr_max,
          "saturate: curr_itr should reach max after incr");

    // Cond1 again at max: must stay at max (no overflow).
    u.lp_curr_itr = itr_max;
    send_upd(sl, u);
    do_pred(sl, pc13);
    check($sformatf("TC13b.%s", sl_of(sl)),
          pred_p1[sl].lp_curr_itr == itr_max,
          "saturate: curr_itr must not overflow past max");
    $display("TC13 slot %0d -- curr_itr saturation: PASS", sl);
  endtask

  // ================================================================
  // TC18: confidence saturates at LP_CONF_LEVEL (no wrap).
  //       Correct exit increments conf; driven at max it must stay
  //       at max. Without the saturation guard a 2-bit conf wraps
  //       to 0 and a trusted entry silently becomes untrusted.
  // ================================================================
  task automatic tc18(input int sl);
    logic [VA_WIDTH-1:0]    pc18;
    logic [LP_IDX_BITS-1:0] idx18;
    logic [LP_TAG_BITS-1:0] tag18;
    lp_upd_t                u;

    do_reset();
    pc18  = 40'hB100;
    idx18 = idx_of(pc18);
    tag18 = tag_of(pc18);

    alloc_entry(sl, pc18, pc18 - 40'd256, LP_WAY_BITS'(0));

    // Correct exit at conf = LP_CONF_LEVEL - 1 -> conf = max.
    u                 = '0;
    u.lp_hit          = 1'b1;
    u.lp_pred_is_loop = 1'b0;
    u.actual_taken    = 1'b0;
    u.lp_curr_itr     = LP_ITR_BITS'(6);
    u.lp_past_itr     = LP_ITR_BITS'(6);
    u.lp_conf         = LP_CNF_BITS'(LP_CONF_LEVEL - 1);
    u.lp_idx          = idx18;
    u.lp_tag          = tag18;
    u.lp_way          = LP_WAY_BITS'(0);
    u.pc              = pc18;
    u.target          = pc18 - 40'd256;
    send_upd(sl, u);
    do_pred(sl, pc18);
    check($sformatf("TC18a.%s", sl_of(sl)),
          pred_p1[sl].lp_conf == LP_CNF_BITS'(LP_CONF_LEVEL),
          "conf saturate: conf should reach max after incr");

    // Correct exit again at max: must stay at max, not wrap to 0.
    u.lp_conf = LP_CNF_BITS'(LP_CONF_LEVEL);
    send_upd(sl, u);
    do_pred(sl, pc18);
    check($sformatf("TC18b.%s", sl_of(sl)),
          pred_p1[sl].lp_conf == LP_CNF_BITS'(LP_CONF_LEVEL),
          "conf saturate: conf must not wrap past max");
    check($sformatf("TC18c.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_is_loop == 1'b1,
          "conf saturate: entry must stay trusted at max conf");
    $display("TC18 slot %0d -- conf saturation: PASS", sl);
  endtask

  // ================================================================
  // TC14: SLOT INDEPENDENCE.
  //
  // For every ordered pair of distinct slots (a, b): drive an
  // update on slot a only and read BOTH slots before and after.
  // Slot a must change, slot b must not. The two slots use the SAME
  // PC, so both address the same set and way of their own bank: a
  // bank index or a write enable that ignores the slot is visible
  // as slot b changing with slot a.
  // ================================================================
  task automatic tc14;
    logic [VA_WIDTH-1:0] pc14;
    lp_upd_t             u;
    lp_pred_t            pre_a, pre_b, post_a, post_b;

    pc14 = 40'h0001_4000;

    for (int a = 0; a < NUM_PRED_SLOTS; a++) begin
      for (int b = 0; b < NUM_PRED_SLOTS; b++) begin
        if (a == b) continue;

        do_reset();

        // Seed BOTH slots with the same entry so "unchanged" is a
        // real value, not the reset value.
        alloc_entry(a, pc14, pc14 - 40'd256, LP_WAY_BITS'(0));
        alloc_entry(b, pc14, pc14 - 40'd256, LP_WAY_BITS'(0));

        do_pred(a, pc14);
        pre_a = pred_p1[a];
        do_pred(b, pc14);
        pre_b = pred_p1[b];

        check($sformatf("TC14pre.%0d%0d", a, b),
              pre_a.lp_hit && pre_b.lp_hit &&
              (pre_a.lp_curr_itr == LP_ITR_BITS'(1)) &&
              (pre_b.lp_curr_itr == LP_ITR_BITS'(1)),
              "TC14: both slots must start from the seeded entry");

        // Cond5 update on slot a only: curr_itr 1 -> 2.
        u                 = '0;
        u.lp_hit          = 1'b1;
        u.lp_pred_is_loop = 1'b0;
        u.actual_taken    = 1'b1;
        u.lp_curr_itr     = LP_ITR_BITS'(1);
        u.lp_past_itr     = LP_ITR_BITS'(9);
        u.lp_idx          = idx_of(pc14);
        u.lp_tag          = tag_of(pc14);
        u.lp_way          = LP_WAY_BITS'(0);
        u.pc              = pc14;
        u.target          = pc14 - 40'd256;
        send_upd(a, u);

        do_pred(a, pc14);
        post_a = pred_p1[a];
        do_pred(b, pc14);
        post_b = pred_p1[b];

        check($sformatf("TC14a.%0d%0d", a, b),
              post_a.lp_curr_itr == LP_ITR_BITS'(2),
              "TC14: the updated slot must advance curr_itr to 2");
        check($sformatf("TC14b.%0d%0d", a, b),
              post_a.lp_past_itr == LP_ITR_BITS'(9),
              "TC14: the updated slot must take the new past_itr");
        check($sformatf("TC14c.%0d%0d", a, b),
              post_b.lp_curr_itr == pre_b.lp_curr_itr,
              "TC14: the untouched slot curr_itr must not move");
        check($sformatf("TC14d.%0d%0d", a, b),
              post_b.lp_past_itr == pre_b.lp_past_itr,
              "TC14: the untouched slot past_itr must not move");
        check($sformatf("TC14e.%0d%0d", a, b),
              post_b == pre_b,
              "TC14: the untouched slot prediction must be identical");
      end
    end
    $display("TC14 -- Slot independence: PASS");
  endtask

  // ================================================================
  // TC14B: SLOT INDEPENDENCE, live payload behind a low valid.
  //
  // TC14 leaves the untouched slot's upd_p0 at zero, so a bank whose
  // write enable ignores the slot still writes nothing -- the idle
  // payload masks the defect. Here the untouched slot carries a
  // fully formed update payload while its upd_valid_p0 bit stays
  // low. A write enable that ORs the slot valids, or one that reads
  // the wrong slot's valid, now corrupts that slot's bank.
  // ================================================================
  task automatic tc14b;
    logic [VA_WIDTH-1:0] pca, pcb;
    lp_upd_t             ua, ub;
    lp_pred_t            pre_b, post_b;

    pca = 40'h0001_4A00;
    pcb = 40'h0001_4B00;

    for (int a = 0; a < NUM_PRED_SLOTS; a++) begin
      for (int b = 0; b < NUM_PRED_SLOTS; b++) begin
        if (a == b) continue;

        do_reset();
        alloc_entry(a, pca, pca - 40'd256, LP_WAY_BITS'(0));
        alloc_entry(b, pcb, pcb - 40'd256, LP_WAY_BITS'(0));

        do_pred(b, pcb);
        pre_b = pred_p1[b];
        check($sformatf("TC14Bpre.%0d%0d", a, b),
              pre_b.lp_hit && (pre_b.lp_curr_itr == LP_ITR_BITS'(1)),
              "TC14B: the quiet slot must start from its own entry");

        // Live payload on slot a, live payload on slot b, but only
        // slot a's valid is asserted.
        ua                 = '0;
        ua.lp_hit          = 1'b1;
        ua.lp_pred_is_loop = 1'b0;
        ua.actual_taken    = 1'b1;
        ua.lp_curr_itr     = LP_ITR_BITS'(1);
        ua.lp_past_itr     = LP_ITR_BITS'(7);
        ua.lp_idx          = idx_of(pca);
        ua.lp_tag          = tag_of(pca);
        ua.lp_way          = LP_WAY_BITS'(0);
        ua.pc              = pca;
        ua.target          = pca - 40'd256;

        // The decoy. It is a valid-looking allocation AND a
        // valid-looking hit update at slot b's own set and way, so
        // either write path would be visible if it fired.
        ub                 = '0;
        ub.lp_hit          = 1'b1;
        ub.lp_pred_is_loop = 1'b1;
        ub.lp_pred_taken   = 1'b0;
        ub.actual_taken    = 1'b1;
        ub.lp_curr_itr     = LP_ITR_BITS'(3000);
        ub.lp_past_itr     = LP_ITR_BITS'(4000);
        ub.lp_conf         = LP_CNF_BITS'(LP_CONF_LEVEL);
        ub.lp_age          = 8'h5A;
        ub.lp_idx          = idx_of(pcb);
        ub.lp_tag          = tag_of(pcb);
        ub.lp_way          = LP_WAY_BITS'(0);
        ub.lp_victim       = LP_WAY_BITS'(0);
        ub.pc              = pcb;
        ub.target          = pcb - 40'd256;

        idle_all();
        upd_p0[a]       = ua;
        upd_p0[b]       = ub;
        upd_valid_p0    = '0;
        upd_valid_p0[a] = 1'b1;   // slot b valid stays low
        @(posedge clk); #1;
        upd_valid_p0 = '0;
        idle_all();

        do_pred(a, pca);
        check($sformatf("TC14Ba.%0d%0d", a, b),
              pred_p1[a].lp_curr_itr == LP_ITR_BITS'(2),
              "TC14B: the enabled slot must take its own update");

        do_pred(b, pcb);
        post_b = pred_p1[b];
        check($sformatf("TC14Bb.%0d%0d", a, b),
              post_b == pre_b,
              "TC14B: low upd_valid must write nothing, live payload");
      end
    end
    $display("TC14B -- Slot independence, live decoy: PASS");
  endtask

  // ================================================================
  // TC15: BOTH SLOTS PREDICTING IN THE SAME CYCLE.
  //
  // Each slot is seeded with a DIFFERENT entry, then both slots are
  // presented with their own PC in one cycle. A crossed pred_pc or
  // pred_p1 connection swaps the two answers and is caught.
  // Slot s is seeded at PC_BASE + s*STRIDE with curr_itr = s+1, and
  // the PCs are proved to differ in tag before use.
  // ================================================================
  task automatic tc15;
    logic [VA_WIDTH-1:0] pc  [0:NUM_PRED_SLOTS-1];
    lp_upd_t             u;

    do_reset();

    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      pc[s] = 40'h0001_5000 + (VA_WIDTH'(s) * 40'h400);
    end

    // Prove the per-slot PCs are distinguishable in the table.
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      for (int t = s + 1; t < NUM_PRED_SLOTS; t++) begin
        check($sformatf("TC15pre.%0d%0d", s, t),
              (idx_of(pc[s]) != idx_of(pc[t])) ||
              (tag_of(pc[s]) != tag_of(pc[t])),
              "TC15: per-slot PCs must not alias in the table");
      end
    end

    // Seed slot s with curr_itr = s+1 at its own PC.
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      alloc_entry(s, pc[s], pc[s] - 40'd256, LP_WAY_BITS'(0));
      if (s > 0) begin
        // Cond5 s times: curr_itr 1 -> s+1.
        for (int k = 0; k < s; k++) begin
          u                 = '0;
          u.lp_hit          = 1'b1;
          u.lp_pred_is_loop = 1'b0;
          u.actual_taken    = 1'b1;
          u.lp_curr_itr     = LP_ITR_BITS'(k + 1);
          u.lp_past_itr     = LP_ITR_BITS'(9);
          u.lp_idx          = idx_of(pc[s]);
          u.lp_tag          = tag_of(pc[s]);
          u.lp_way          = LP_WAY_BITS'(0);
          u.pc              = pc[s];
          u.target          = pc[s] - 40'd256;
          send_upd(s, u);
        end
      end
    end

    // One cycle, every slot predicting its own PC.
    idle_all();
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      pred_pc_p0[s]    = pc[s];
      pred_valid_p0[s] = 1'b1;
    end
    @(posedge clk); #1;
    pred_valid_p0 = '0;

    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      check($sformatf("TC15a.s%0d", s),
            pred_p1[s].lp_hit == 1'b1,
            "TC15: every slot must hit its own seeded entry");
      check($sformatf("TC15b.s%0d", s),
            pred_p1[s].lp_curr_itr == LP_ITR_BITS'(s + 1),
            "TC15: each slot must report its own curr_itr");
      check($sformatf("TC15c.s%0d", s),
            pred_p1[s].lp_tag == tag_of(pc[s]),
            "TC15: each slot must report the tag of its own PC");
      check($sformatf("TC15d.s%0d", s),
            pred_p1[s].lp_idx == idx_of(pc[s]),
            "TC15: each slot must report the index of its own PC");
    end
    $display("TC15 -- Both slots predict same cycle: PASS");
  endtask

  // ================================================================
  // TC16: BOTH SLOTS UPDATING IN THE SAME CYCLE.
  //
  // Every slot is updated in one cycle with a DIFFERENT value at the
  // SAME set and way of its own bank. Each slot must end up with its
  // own value; a crossed upd_p0 or a bank write that ignores the
  // slot lands one slot's payload in another slot's bank.
  // ================================================================
  task automatic tc16;
    logic [VA_WIDTH-1:0] pc16;
    lp_upd_t             u;

    do_reset();
    pc16 = 40'h0001_6000;

    // Seed every slot identically, so the only difference after the
    // simultaneous update is the update payload itself.
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      alloc_entry(s, pc16, pc16 - 40'd256, LP_WAY_BITS'(0));
    end

    // One cycle, every slot updating with its own past_itr and its
    // own curr_itr. Cond5: curr_itr increments, past_itr passes
    // through unchanged.
    idle_all();
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      u                 = '0;
      u.lp_hit          = 1'b1;
      u.lp_pred_is_loop = 1'b0;
      u.actual_taken    = 1'b1;
      u.lp_curr_itr     = LP_ITR_BITS'(10 * (s + 1));
      u.lp_past_itr     = LP_ITR_BITS'(100 * (s + 1));
      u.lp_age          = LP_AGE_BITS'(s + 1);
      u.lp_idx          = idx_of(pc16);
      u.lp_tag          = tag_of(pc16);
      u.lp_way          = LP_WAY_BITS'(0);
      u.pc              = pc16;
      u.target          = pc16 - 40'd256;
      upd_p0[s]         = u;
      upd_valid_p0[s]   = 1'b1;
    end
    @(posedge clk); #1;
    upd_valid_p0 = '0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) upd_p0[s] = '0;

    // Read every slot back, one at a time.
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      do_pred(s, pc16);
      check($sformatf("TC16a.s%0d", s),
            pred_p1[s].lp_curr_itr == LP_ITR_BITS'(10 * (s + 1) + 1),
            "TC16: each slot must hold its own incremented curr_itr");
      check($sformatf("TC16b.s%0d", s),
            pred_p1[s].lp_past_itr == LP_ITR_BITS'(100 * (s + 1)),
            "TC16: each slot must hold its own past_itr");
      check($sformatf("TC16c.s%0d", s),
            pred_p1[s].lp_age == LP_AGE_BITS'(s + 1),
            "TC16: each slot must hold its own age");
    end
    $display("TC16 -- Both slots update same cycle: PASS");
  endtask

  // ================================================================
  // TC17: RESET -- every bank reaches the documented reset state.
  //
  // Documented reset state: every entry of every bank invalid with
  // all fields zero, and pred_p1 zero.
  //
  // Part A proves way 0 of every set of every bank is zero. On a
  // miss the DUT reports hit_entry = mem[idx][0], so the reported
  // age/conf/past/curr/curs fields ARE way 0 of the addressed set.
  // A PC sweep wide enough to cover all LP_N_SETS sets is used and
  // the set coverage is asserted, so no set is left unproven.
  //
  // Part B proves ways 1..LP_TBL_WAYS-1 are invalid too: with every
  // way invalid, victim selection reports the lowest-indexed invalid
  // way, so filling one set one way at a time must report victim
  // 0,1,2,...  in order. A way left valid by reset would be skipped.
  // ================================================================
  task automatic tc17;
    logic [VA_WIDTH-1:0]    pcs;
    logic [LP_IDX_BITS-1:0] idxs;
    logic [LP_N_SETS-1:0]   seen;
    logic [VA_WIDTH-1:0]    pc17;
    logic [LP_TAG_BITS-1:0] tag17;
    lp_upd_t                u;

    // ---- Part A: way 0 of every set, every bank ----
    do_reset();
    seen = '0;
    for (int p = 0; p < SWEEP_PCS; p++) begin
      pcs  = VA_WIDTH'(p);
      idxs = idx_of(pcs);
      seen[idxs] = 1'b1;

      // Every slot looks up the same PC in the same cycle, so the
      // sweep costs one pass, not one pass per slot.
      idle_all();
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        pred_pc_p0[s]    = pcs;
        pred_valid_p0[s] = 1'b1;
      end
      @(posedge clk); #1;
      pred_valid_p0 = '0;

      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        check("TC17a", pred_p1[s].lp_hit == 1'b0,
              "reset: no set of any bank may report a hit");
        check("TC17b", pred_p1[s].lp_victim == LP_WAY_BITS'(0),
              "reset: way 0 invalid, victim must be way 0");
        check("TC17c", pred_p1[s].lp_age == '0,
              "reset: way 0 age must be zero");
        check("TC17d", pred_p1[s].lp_conf == '0,
              "reset: way 0 conf must be zero");
        check("TC17e", pred_p1[s].lp_past_itr == '0,
              "reset: way 0 past_itr must be zero");
        check("TC17f", pred_p1[s].lp_curr_itr == '0,
              "reset: way 0 curr_itr must be zero");
        check("TC17g", pred_p1[s].lp_curs == '0,
              "reset: way 0 curs must be zero");
        check("TC17h", pred_p1[s].lp_curs_v == 1'b0,
              "reset: way 0 curs_v must be zero");
        check("TC17i", pred_p1[s].lp_pred_is_loop == 1'b0,
              "reset: no bank may report a trusted prediction");
      end
    end
    check("TC17j", &seen,
          "TC17: the PC sweep must reach every set of the bank");

    // ---- Part B: ways 1..N-1 invalid, every bank ----
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      do_reset();
      pc17  = 40'h0000_0080;
      tag17 = tag_of(pc17);

      for (int w = 0; w < LP_TBL_WAYS; w++) begin
        // The probe PC must keep missing while the set fills.
        check($sformatf("TC17pre.s%0d.w%0d", s, w),
              tag17 != LP_TAG_BITS'(w + 1),
              "TC17: probe tag must not alias a filler tag");

        do_pred(s, pc17);
        check($sformatf("TC17k.s%0d.w%0d", s, w),
              pred_p1[s].lp_hit == 1'b0,
              "TC17: probe must miss while the set fills");
        check($sformatf("TC17l.s%0d.w%0d", s, w),
              pred_p1[s].lp_victim == LP_WAY_BITS'(w),
              "TC17: reset left this way valid -- victim skipped it");

        u                 = '0;
        u.actual_taken    = 1'b1;
        u.lp_hit          = 1'b0;
        u.lp_pred_is_loop = 1'b0;
        u.lp_idx          = idx_of(pc17);
        u.lp_tag          = LP_TAG_BITS'(w + 1);
        u.lp_victim       = LP_WAY_BITS'(w);
        u.pc              = 40'hFF00;
        u.target          = 40'hF000;  // backward
        send_upd(s, u);
      end
    end
    $display("TC17 -- Reset state of every bank: PASS");
  endtask

  // ----------------------------------------------------------------
  // Test body
  // ----------------------------------------------------------------
  initial begin : test_body
    fail_count  = 0;
    check_count = 0;
    idle_all();
    rstn = 1'b0;

    // -- Directed algorithm set, once per slot (TC1-TC13).
    for (int sl = 0; sl < NUM_PRED_SLOTS; sl++) begin
      $display("---- directed set on slot %0d ----", sl);
      tc1(sl);
      tc2(sl);
      tc3(sl);
      tc4(sl);
      tc567(sl);
      tc8(sl);
      tc9(sl);
      tc10(sl);
      tc11(sl);
      tc12(sl);
      tc13(sl);
      tc18(sl);
    end

    // -- Slot retrofit set (TC14-TC17).
    $display("---- slot retrofit set ----");
    tc14();
    tc14b();
    tc15();
    tc16();
    tc17();

    // ============================================================
    // Final verdict
    // ============================================================
    if (fail_count == 0) begin
      $display("tb_loop_pred: PASS=%0d FAIL=0 slots=%0d",
               check_count, NUM_PRED_SLOTS);
      $display("ALL TC1-TC18 TESTS PASSED");
      $finish(0);
    end else begin
      $display("FAILURES DETECTED: %0d", fail_count);
      $fatal(1, "tb_loop_pred failed");
    end
  end

endmodule : tb
