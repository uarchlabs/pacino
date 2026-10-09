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
// trusted taken, trusted exit, correct exit, wrong exit, taken past
// the trip count, victim selection, way conflict, curr_itr
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
// BP-122 (TD#169, LI4; loop_pred_interfaces.md Ruled Change). The
// update reads the entry before it writes it and trains from the
// iteration number the prediction carried (lp_curs / lp_curs_v); the
// speculative count advances at p2, is checkpointed per FTQ entry and
// restored or invalidated on a redirect. TC5-TC16 and TC18 drive the
// update that way (they drove the update from a predict-time snapshot
// before; the Results Capture lists every expected value that moved).
// New cases, each run once per slot:
//   TC19  read before write: updates carrying one stale snapshot
//         still train from the entry
//   TC20  order independence: the carried iteration numbers, not the
//         order of arrival, decide the learned trip count
//   TC21  the update looks the tag up again: a stale way still finds
//         the entry, and a replaced entry is not written
//   TC22  p2 re-read: back-to-back predictions of one entry carry
//         consecutive iteration numbers
//   TC23  an unknown count is not trusted; an exit makes it known
//   TC24  restore from the checkpoint: re-advance by the corrected
//         direction, or put back when the slot did not execute
//   TC25  invalidate every count; a restore in the same cycle wins
//   TC26  a restore whose entry was replaced writes nothing
//   TC27  a prediction in the same cycle as an update to its entry
//         sees the old value
//
// Start state. Every test case begins with do_reset(), which drives
// every input to its idle value and holds rstn low for two cycles.
// No test case carries state from another, and no check relies on
// the absence of residue: reset is the invalidation of every set of
// every bank and TC17 proves reset does that. seed() writes one entry
// directly, a known driven state, where a case needs an entry the
// update path cannot reach in a few steps (an age, a count).
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
  lp_pred_t                  pred_p2    [0:NUM_PRED_SLOTS-1];
  logic                      spec_ck_p2;
  logic [FTQ_IDX_BITS-1:0]   spec_idx_p2;
  logic [NUM_PRED_SLOTS-1:0] spec_val_p2;
  logic [NUM_PRED_SLOTS-1:0] spec_tkn_p2;
  logic                      rst_val;
  logic [FTQ_IDX_BITS-1:0]   rst_idx;
  logic [NUM_PRED_SLOTS-1:0] rst_ex;
  logic [NUM_PRED_SLOTS-1:0] rst_tkn;
  logic                      inv_val;
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
    .pred_p2       (pred_p2),
    .spec_ck_p2    (spec_ck_p2),
    .spec_idx_p2   (spec_idx_p2),
    .spec_val_p2   (spec_val_p2),
    .spec_tkn_p2   (spec_tkn_p2),
    .rst_val       (rst_val),
    .rst_idx       (rst_idx),
    .rst_ex        (rst_ex),
    .rst_tkn       (rst_tkn),
    .inv_val       (inv_val),
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
  // Time-based, not cycle-based, so it fires even when the hang stops
  // the clock. Normal completion measured at 8000 time units before
  // BP-122 added TC19-TC27; 400000 leaves the same margin.
  initial begin
    #400000;
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
  localparam logic [LP_ITR_BITS-1:0] ITR_MAX = {LP_ITR_BITS{1'b1}};

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
    spec_ck_p2    = 1'b0;
    spec_idx_p2   = '0;
    spec_val_p2   = '0;
    spec_tkn_p2   = '0;
    rst_val       = 1'b0;
    rst_idx       = '0;
    rst_ex        = '0;
    rst_tkn       = '0;
    inv_val       = 1'b0;
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

  // Allocation update: backward branch miss (lp_hit=0). The victim is
  // chosen by the DUT from the set as it is at the update (BP-122);
  // the argument is carried in lp_victim as the prediction would.
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

  // A resolution of the loop branch at pc: its direction and the
  // iteration number its prediction carried (BP-122). The snapshot
  // fields stay zero: the update must not read them.
  function automatic lp_upd_t mk_res(
    input logic [VA_WIDTH-1:0]    pc,
    input logic                   tkn,
    input logic [LP_ITR_BITS-1:0] itr,
    input logic                   itr_v
  );
    lp_upd_t u;
    u              = '0;
    u.pc           = pc;
    u.target       = pc - VA_WIDTH'('d256);
    u.actual_taken = tkn;
    u.lp_hit       = 1'b1;
    u.lp_idx       = idx_of(pc);
    u.lp_tag       = tag_of(pc);
    u.lp_curs      = itr;
    u.lp_curs_v    = itr_v;
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

  // Write one entry directly (a known driven state). g_slot is a
  // generate loop, so the bank index is a literal; the package value
  // of NUM_PRED_SLOTS is 2 and a third slot fails elaboration below.
  task automatic seed(
    input int                     sl,
    input logic [VA_WIDTH-1:0]    pc,
    input logic [LP_WAY_BITS-1:0] way,
    input logic [LP_ITR_BITS-1:0] past,
    input logic [LP_ITR_BITS-1:0] curr,
    input logic [LP_CNF_BITS-1:0] cnf,
    input logic [LP_AGE_BITS-1:0] age,
    input logic [LP_ITR_BITS-1:0] curs,
    input logic                   curs_v
  );
    lp_entry_t e;
    e          = '0;
    e.v        = 1'b1;
    e.tag      = tag_of(pc);
    e.past_itr = past;
    e.curr_itr = curr;
    e.cnf      = cnf;
    e.age      = age;
    e.curs     = curs;
    e.curs_v   = curs_v;
    if (sl == 0) dut.g_slot[0].mem[idx_of(pc)][way] = e;
    else         dut.g_slot[NUM_PRED_SLOTS-1].mem[idx_of(pc)][way] = e;
  endtask

  // One block through p0, p1 and p2 on slot sl: the p2 re-read is
  // returned, and at p2 the advance (val, tkn) and the checkpoint at
  // FTQ index ck_idx are presented.
  task automatic do_p2(
    input  int                      sl,
    input  logic [VA_WIDTH-1:0]     pc,
    input  logic                    val,
    input  logic                    tkn,
    input  logic [FTQ_IDX_BITS-1:0] ck_idx,
    output lp_pred_t                p2
  );
    idle_all();
    pred_pc_p0[sl]    = pc;
    pred_valid_p0[sl] = 1'b1;
    @(posedge clk); #1;
    idle_all();
    @(posedge clk); #1;
    p2               = pred_p2[sl];
    spec_ck_p2       = 1'b1;
    spec_idx_p2      = ck_idx;
    spec_val_p2[sl]  = val;
    spec_tkn_p2[sl]  = tkn;
    @(posedge clk); #1;
    idle_all();
  endtask

  // A restore of FTQ entry k on slot sl.
  task automatic do_rst(
    input int                      sl,
    input logic [FTQ_IDX_BITS-1:0] k,
    input logic                    ex,
    input logic                    tkn,
    input logic                    inv
  );
    idle_all();
    rst_val     = 1'b1;
    rst_idx     = k;
    rst_ex[sl]  = ex;
    rst_tkn[sl] = tkn;
    inv_val     = inv;
    @(posedge clk); #1;
    idle_all();
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
    do_pred(sl, VA_WIDTH'('h0000_1100));
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
    pc2  = VA_WIDTH'('h0000_2200);
    tgt2 = pc2 - VA_WIDTH'('d256);  // backward: tgt < pc
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
    // BP-122: later instances are in flight at the allocation, so the
    // speculative count is not known.
    check($sformatf("TC2d.%s", sl_of(sl)),
          pred_p1[sl].lp_curs_v == 1'b0,
          "after alloc: the speculative count is not known");
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
    pc3  = VA_WIDTH'('h0000_3300);
    tgt3 = pc3 + VA_WIDTH'('d256);  // forward: tgt > pc -> no alloc
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
    pc4  = VA_WIDTH'('h0000_4400);
    tgt4 = pc4 - VA_WIDTH'('d256);
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
  // TC5/TC6/TC7 share one entry (PC=0x5500, a 1-taken loop: taken
  // once, then the exit).
  //
  // Confidence build, every update carrying its iteration number:
  //   alloc                    -> cnf=0, past=0, count unknown
  //   exit carrying 1          -> learned: cnf=0, past=1
  //   LP_CONF_LEVEL x (taken carrying 0, exit carrying 1)
  //                            -> cnf=1 .. LP_CONF_LEVEL
  //   TC5x: confidence at max, count still unknown: not trusted
  //   p2 exit advance          -> count 0, known
  //   lookup -> TC5 (trusted) and TC6 (count 0 < past 1: taken)
  //   p2 taken advance         -> count 1
  //   lookup -> TC7 (count 1 == past 1: the exit, not taken)
  // ================================================================
  task automatic tc567(input int sl);
    logic [VA_WIDTH-1:0] pc5, tgt5;
    lp_pred_t            p2;

    do_reset();
    pc5  = VA_WIDTH'('h0000_5500);
    tgt5 = pc5 - VA_WIDTH'('d256);

    alloc_entry(sl, pc5, tgt5, LP_WAY_BITS'(0));
    send_upd(sl, mk_res(pc5, 1'b0, LP_ITR_BITS'(1), 1'b1));
    for (int i = 0; i < LP_CONF_LEVEL; i++) begin
      send_upd(sl, mk_res(pc5, 1'b1, LP_ITR_BITS'(0), 1'b1));
      send_upd(sl, mk_res(pc5, 1'b0, LP_ITR_BITS'(1), 1'b1));
    end

    do_pred(sl, pc5);
    check($sformatf("TC5x.%s", sl_of(sl)),
          (pred_p1[sl].lp_conf == LP_CNF_BITS'(LP_CONF_LEVEL)) &&
          !pred_p1[sl].lp_pred_is_loop,
          "cnf at max but count unknown: not trusted");

    do_p2(sl, pc5, 1'b1, 1'b0, FTQ_IDX_BITS'(1), p2);
    do_pred(sl, pc5);
    check($sformatf("TC5.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_is_loop == 1'b1,
          "cnf=LP_CONF_LEVEL and count known: lp_pred_is_loop is 1");
    $display("TC5  slot %0d -- Confidence at max: PASS", sl);

    check($sformatf("TC6a.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_is_loop == 1'b1,
          "TC6: lp_pred_is_loop should be 1 (trusted)");
    check($sformatf("TC6b.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_taken == 1'b1,
          "TC6: count 0 < past_itr 1, lp_pred_taken should be 1");
    $display("TC6  slot %0d -- Trusted taken: PASS", sl);

    do_p2(sl, pc5, 1'b1, 1'b1, FTQ_IDX_BITS'(2), p2);
    do_pred(sl, pc5);
    check($sformatf("TC7a.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_is_loop == 1'b1,
          "TC7: lp_pred_is_loop should be 1 (trusted)");
    check($sformatf("TC7b.%s", sl_of(sl)),
          pred_p1[sl].lp_pred_taken == 1'b0,
          "TC7: count 1 == past_itr 1, lp_pred_taken should be 0");
    $display("TC7  slot %0d -- Trusted exit: PASS", sl);
  endtask

  // ================================================================
  // TC8: Correct exit -- conf++, past_itr unchanged, curr_itr=0,
  //      age=max. The entry holds past 5, cnf 2, age 0x64; the exit
  //      carries iteration number 5.
  // ================================================================
  task automatic tc8(input int sl);
    logic [VA_WIDTH-1:0] pc8;
    do_reset();
    pc8 = VA_WIDTH'('hC800);
    seed(sl, pc8, LP_WAY_BITS'(0), LP_ITR_BITS'(5), LP_ITR_BITS'(5),
         LP_CNF_BITS'(2), 8'h64, '0, 1'b0);
    send_upd(sl, mk_res(pc8, 1'b0, LP_ITR_BITS'(5), 1'b1));
    do_pred(sl, pc8);
    check($sformatf("TC8a.%s", sl_of(sl)),
          pred_p1[sl].lp_conf == LP_CNF_BITS'(LP_CONF_LEVEL),
          "correct exit: conf should increment to max");
    check($sformatf("TC8b.%s", sl_of(sl)),
          pred_p1[sl].lp_past_itr == LP_ITR_BITS'(5),
          "correct exit: past_itr should hold the carried count");
    check($sformatf("TC8c.%s", sl_of(sl)),
          pred_p1[sl].lp_curr_itr == '0,
          "correct exit: curr_itr should reset to 0");
    check($sformatf("TC8d.%s", sl_of(sl)),
          pred_p1[sl].lp_age == {LP_AGE_BITS{1'b1}},
          "correct exit: age should reset to max");
    $display("TC8  slot %0d -- Correct exit: PASS", sl);
  endtask

  // ================================================================
  // TC9: Wrong exit -- conf=0, past_itr=the carried count, curr=0.
  //      The entry holds past 3, cnf 2; the exit carries 7.
  // ================================================================
  task automatic tc9(input int sl);
    logic [VA_WIDTH-1:0] pc9;
    do_reset();
    pc9 = VA_WIDTH'('hD900);
    seed(sl, pc9, LP_WAY_BITS'(0), LP_ITR_BITS'(3), LP_ITR_BITS'(7),
         LP_CNF_BITS'(2), 8'h40, '0, 1'b0);
    send_upd(sl, mk_res(pc9, 1'b0, LP_ITR_BITS'(7), 1'b1));
    do_pred(sl, pc9);
    check($sformatf("TC9a.%s", sl_of(sl)),
          pred_p1[sl].lp_conf == '0,
          "wrong exit: conf should reset to 0");
    check($sformatf("TC9b.%s", sl_of(sl)),
          pred_p1[sl].lp_past_itr == LP_ITR_BITS'(7),
          "wrong exit: past_itr should take the carried count");
    check($sformatf("TC9c.%s", sl_of(sl)),
          pred_p1[sl].lp_curr_itr == '0,
          "wrong exit: curr_itr should reset to 0");
    $display("TC9  slot %0d -- Wrong exit: PASS", sl);
  endtask

  // ================================================================
  // TC10: Taken at the learned trip count -- the loop ran longer
  //       than learned (the trusted exit prediction was wrong):
  //       conf=0, past_itr unchanged, curr_itr steps.
  //       The entry holds past 5, cnf max, curr 4; the taken
  //       resolution carries iteration number 5.
  // ================================================================
  task automatic tc10(input int sl);
    logic [VA_WIDTH-1:0] pc10;
    do_reset();
    pc10 = VA_WIDTH'('hE100);
    seed(sl, pc10, LP_WAY_BITS'(0), LP_ITR_BITS'(5), LP_ITR_BITS'(4),
         LP_CNF_BITS'(LP_CONF_LEVEL), 8'hFF, LP_ITR_BITS'(6), 1'b1);
    send_upd(sl, mk_res(pc10, 1'b1, LP_ITR_BITS'(5), 1'b1));
    do_pred(sl, pc10);
    check($sformatf("TC10a.%s", sl_of(sl)),
          pred_p1[sl].lp_conf == '0,
          "taken at the trip count: conf should reset to 0");
    check($sformatf("TC10b.%s", sl_of(sl)),
          pred_p1[sl].lp_curr_itr == LP_ITR_BITS'(5),
          "taken at the trip count: curr_itr steps 4 -> 5");
    check($sformatf("TC10c.%s", sl_of(sl)),
          pred_p1[sl].lp_past_itr == LP_ITR_BITS'(5),
          "taken at the trip count: past_itr unchanged (=5)");
    check($sformatf("TC10d.%s", sl_of(sl)),
          pred_p1[sl].lp_curs == LP_ITR_BITS'(6),
          "taken at the trip count: the speculative count is untouched");
    $display("TC10 slot %0d -- Taken past the trip count: PASS", sl);
  endtask

  // ================================================================
  // TC11: Victim selection -- all ways valid, priority 3.
  //       Ways 0-3 at idx11 hold tags 1..4, way 1 at age 1 and the
  //       others at max. Predict PC_11 (miss) -> victim way 1, and an
  //       allocation of PC_11 lands in way 1 (the victim the update
  //       chooses, BP-122).
  // ================================================================
  task automatic tc11(input int sl);
    logic [VA_WIDTH-1:0]    pc11;
    logic [LP_IDX_BITS-1:0] idx11;
    logic [LP_TAG_BITS-1:0] tag11;
    lp_upd_t                u;

    do_reset();
    pc11  = VA_WIDTH'('h0000_0080);
    idx11 = idx_of(pc11);
    tag11 = tag_of(pc11);
    check($sformatf("TC11pre.%s", sl_of(sl)),
          (tag11 != LP_TAG_BITS'(1)) && (tag11 != LP_TAG_BITS'(2)) &&
          (tag11 != LP_TAG_BITS'(3)) && (tag11 != LP_TAG_BITS'(4)),
          "TC11: probe tag must not alias the four filler tags");

    // Allocate all 4 ways at idx11 with tags 1..4, each through the
    // update path (the DUT picks the lowest invalid way).
    for (int w = 0; w < LP_TBL_WAYS; w++) begin
      u                 = '0;
      u.actual_taken    = 1'b1;
      u.lp_idx          = idx11;
      u.pc              = VA_WIDTH'('hFF00);
      u.target          = VA_WIDTH'('hF000);  // target < pc -> backward
      u.lp_tag          = LP_TAG_BITS'(w + 1);
      send_upd(sl, u);
    end
    // Way 1's age lowered directly: no update lowers an age.
    if (sl == 0) dut.g_slot[0].mem[idx11][1].age = 8'h01;
    else         dut.g_slot[NUM_PRED_SLOTS-1].mem[idx11][1].age = 8'h01;

    do_pred(sl, pc11);
    check($sformatf("TC11a.%s", sl_of(sl)),
          pred_p1[sl].lp_hit == 1'b0,
          "TC11: non-matching tags on all ways, miss expected");
    check($sformatf("TC11b.%s", sl_of(sl)),
          pred_p1[sl].lp_victim == LP_WAY_BITS'(1),
          "TC11: way 1 has lowest age, victim should be way 1");

    alloc_entry(sl, pc11, pc11 - VA_WIDTH'('d16), LP_WAY_BITS'(3));
    do_pred(sl, pc11);
    check($sformatf("TC11c.%s", sl_of(sl)),
          pred_p1[sl].lp_hit && (pred_p1[sl].lp_way == LP_WAY_BITS'(1)),
          "TC11: the update allocates at its own victim, way 1");
    $display("TC11 slot %0d -- Victim selection: PASS", sl);
  endtask

  // ================================================================
  // TC12: Way conflict -- two PCs in one set, tracked independently.
  //       PC_12a=0x1000 -> way 0, PC_12b=0x2000 -> way 1. A takes one
  //       taken resolution, B two; each starts at curr_itr 1.
  // ================================================================
  task automatic tc12(input int sl);
    logic [VA_WIDTH-1:0]    pc12a, pc12b;
    logic [LP_IDX_BITS-1:0] idx12;
    logic [LP_TAG_BITS-1:0] tag12a, tag12b;

    do_reset();
    pc12a  = VA_WIDTH'('h0000_1000);
    pc12b  = VA_WIDTH'('h0000_2000);
    idx12  = idx_of(pc12a);
    tag12a = tag_of(pc12a);
    tag12b = tag_of(pc12b);
    check($sformatf("TC12pre.%s", sl_of(sl)),
          (idx_of(pc12b) == idx12) && (tag12a != tag12b),
          "TC12: the two PCs must share a set and differ in tag");

    alloc_entry(sl, pc12a, pc12a - VA_WIDTH'('d256), LP_WAY_BITS'(0));
    alloc_entry(sl, pc12b, pc12b - VA_WIDTH'('d256), LP_WAY_BITS'(1));

    send_upd(sl, mk_res(pc12a, 1'b1, LP_ITR_BITS'(1), 1'b1));
    send_upd(sl, mk_res(pc12b, 1'b1, LP_ITR_BITS'(1), 1'b1));
    send_upd(sl, mk_res(pc12b, 1'b1, LP_ITR_BITS'(2), 1'b1));

    do_pred(sl, pc12a);
    check($sformatf("TC12a.%s", sl_of(sl)),
          (pred_p1[sl].lp_curr_itr == LP_ITR_BITS'(2)) &&
          (pred_p1[sl].lp_way == LP_WAY_BITS'(0)),
          "way conflict: entry A (way 0) curr_itr should be 2");

    do_pred(sl, pc12b);
    check($sformatf("TC12b.%s", sl_of(sl)),
          (pred_p1[sl].lp_curr_itr == LP_ITR_BITS'(3)) &&
          (pred_p1[sl].lp_way == LP_WAY_BITS'(1)),
          "way conflict: entry B (way 1) curr_itr should be 3");
    $display("TC12 slot %0d -- Way conflict: PASS", sl);
  endtask

  // ================================================================
  // TC13: curr_itr saturates at LP_ITR_BITS max (no overflow).
  //       The entry holds curr max-1; two taken resolutions.
  // ================================================================
  task automatic tc13(input int sl);
    logic [VA_WIDTH-1:0] pc13;

    do_reset();
    pc13 = VA_WIDTH'('hA000);
    seed(sl, pc13, LP_WAY_BITS'(0), ITR_MAX, ITR_MAX - LP_ITR_BITS'(1),
         LP_CNF_BITS'(LP_CONF_LEVEL), 8'hFF, '0, 1'b0);

    send_upd(sl, mk_res(pc13, 1'b1, '0, 1'b0));
    do_pred(sl, pc13);
    check($sformatf("TC13a.%s", sl_of(sl)),
          pred_p1[sl].lp_curr_itr == ITR_MAX,
          "saturate: curr_itr should reach max after incr");

    send_upd(sl, mk_res(pc13, 1'b1, '0, 1'b0));
    do_pred(sl, pc13);
    check($sformatf("TC13b.%s", sl_of(sl)),
          pred_p1[sl].lp_curr_itr == ITR_MAX,
          "saturate: curr_itr must not overflow past max");
    $display("TC13 slot %0d -- curr_itr saturation: PASS", sl);
  endtask

  // ================================================================
  // TC18: confidence saturates at LP_CONF_LEVEL (no wrap).
  //       Correct exit increments conf; at max it must stay at max.
  //       Without the saturation guard a 2-bit conf wraps to 0 and a
  //       trusted entry silently becomes untrusted.
  // ================================================================
  task automatic tc18(input int sl);
    logic [VA_WIDTH-1:0] pc18;

    do_reset();
    pc18 = VA_WIDTH'('hB100);
    seed(sl, pc18, LP_WAY_BITS'(0), LP_ITR_BITS'(6), '0,
         LP_CNF_BITS'(LP_CONF_LEVEL - 1), 8'hFF, '0, 1'b1);

    send_upd(sl, mk_res(pc18, 1'b0, LP_ITR_BITS'(6), 1'b1));
    do_pred(sl, pc18);
    check($sformatf("TC18a.%s", sl_of(sl)),
          pred_p1[sl].lp_conf == LP_CNF_BITS'(LP_CONF_LEVEL),
          "conf saturate: conf should reach max after incr");

    send_upd(sl, mk_res(pc18, 1'b0, LP_ITR_BITS'(6), 1'b1));
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
  // TC19: READ BEFORE WRITE (BP-122, TD#169).
  //       Every update carries the snapshot taken at one prediction
  //       (lp_conf 0, lp_past_itr 0, lp_curr_itr 4) because all were
  //       predicted before the first update landed. The update must
  //       train from the entry: an exit carrying 4 learns past 4,
  //       then each later exit carrying 4 raises the confidence.
  //       Two taken resolutions carrying the same stale curr_itr step
  //       curr_itr twice.
  // ================================================================
  task automatic tc19(input int sl);
    logic [VA_WIDTH-1:0] pc19;
    lp_upd_t             u;

    do_reset();
    pc19 = VA_WIDTH'('h0001_9000);
    alloc_entry(sl, pc19, pc19 - VA_WIDTH'('d64), LP_WAY_BITS'(0));

    for (int i = 0; i <= LP_CONF_LEVEL; i++) begin
      u             = mk_res(pc19, 1'b0, LP_ITR_BITS'(4), 1'b1);
      u.lp_conf     = '0;
      u.lp_past_itr = '0;
      u.lp_curr_itr = LP_ITR_BITS'(4);
      u.lp_way      = LP_WAY_BITS'(0);
      send_upd(sl, u);
    end
    do_pred(sl, pc19);
    check($sformatf("TC19a.%s", sl_of(sl)),
          pred_p1[sl].lp_past_itr == LP_ITR_BITS'(4),
          "read before write: the trip count is learned (4)");
    check($sformatf("TC19b.%s", sl_of(sl)),
          pred_p1[sl].lp_conf == LP_CNF_BITS'(LP_CONF_LEVEL),
          "read before write: stale snapshots still reach max conf");

    for (int i = 0; i < 2; i++) begin
      u             = mk_res(pc19, 1'b1, LP_ITR_BITS'(i), 1'b1);
      u.lp_curr_itr = '0;
      u.lp_way      = LP_WAY_BITS'(0);
      send_upd(sl, u);
    end
    do_pred(sl, pc19);
    check($sformatf("TC19c.%s", sl_of(sl)),
          pred_p1[sl].lp_curr_itr == LP_ITR_BITS'(2),
          "read before write: two takens on one snapshot step twice");
    $display("TC19 slot %0d -- Read before write: PASS", sl);
  endtask

  // ================================================================
  // TC20: ORDER INDEPENDENCE (BP-122). Resolutions of one run of a
  //       3-taken loop arrive out of order, and the next run's first
  //       taken arrives before this run's exit. The exit carries 3
  //       and teaches past 3; the next run's exit carrying 3 raises
  //       the confidence to 1.
  // ================================================================
  task automatic tc20(input int sl);
    logic [VA_WIDTH-1:0] pc20;

    do_reset();
    pc20 = VA_WIDTH'('h0002_0000);
    alloc_entry(sl, pc20, pc20 - VA_WIDTH'('d64), LP_WAY_BITS'(0));

    send_upd(sl, mk_res(pc20, 1'b1, LP_ITR_BITS'(2), 1'b1));
    send_upd(sl, mk_res(pc20, 1'b1, LP_ITR_BITS'(0), 1'b1));
    send_upd(sl, mk_res(pc20, 1'b1, LP_ITR_BITS'(0), 1'b1)); // next run
    send_upd(sl, mk_res(pc20, 1'b1, LP_ITR_BITS'(1), 1'b1));
    send_upd(sl, mk_res(pc20, 1'b0, LP_ITR_BITS'(3), 1'b1));
    do_pred(sl, pc20);
    check($sformatf("TC20a.%s", sl_of(sl)),
          (pred_p1[sl].lp_past_itr == LP_ITR_BITS'(3)) &&
          (pred_p1[sl].lp_conf == '0),
          "order: the exit's carried count is learned (3)");

    send_upd(sl, mk_res(pc20, 1'b1, LP_ITR_BITS'(2), 1'b1));
    send_upd(sl, mk_res(pc20, 1'b0, LP_ITR_BITS'(3), 1'b1));
    send_upd(sl, mk_res(pc20, 1'b1, LP_ITR_BITS'(1), 1'b1));
    do_pred(sl, pc20);
    check($sformatf("TC20b.%s", sl_of(sl)),
          (pred_p1[sl].lp_past_itr == LP_ITR_BITS'(3)) &&
          (pred_p1[sl].lp_conf == LP_CNF_BITS'(1)),
          "order: a matching exit raises conf whatever the order");

    // An exit whose count is unknown trains nothing.
    send_upd(sl, mk_res(pc20, 1'b0, LP_ITR_BITS'(9), 1'b0));
    do_pred(sl, pc20);
    check($sformatf("TC20c.%s", sl_of(sl)),
          (pred_p1[sl].lp_past_itr == LP_ITR_BITS'(3)) &&
          (pred_p1[sl].lp_conf == LP_CNF_BITS'(1)),
          "order: an exit with an unknown count trains nothing");
    $display("TC20 slot %0d -- Order independence: PASS", sl);
  endtask

  // ================================================================
  // TC21: THE UPDATE LOOKS THE TAG UP AGAIN (BP-122).
  //       a: entry at way 2, update carrying way 0: way 2 trains and
  //          way 0 (another tag) is untouched.
  //       b: the entry the prediction hit has been replaced by
  //          another tag: a not-taken update writes nothing.
  // ================================================================
  task automatic tc21(input int sl);
    logic [VA_WIDTH-1:0] pca, pcb;
    lp_upd_t             u;
    lp_pred_t            pre;

    do_reset();
    pca = VA_WIDTH'('h0002_1000);
    pcb = VA_WIDTH'('h0002_2000);
    check($sformatf("TC21pre.%s", sl_of(sl)),
          (idx_of(pca) == idx_of(pcb)) && (tag_of(pca) != tag_of(pcb)),
          "TC21: the two PCs must share a set and differ in tag");
    seed(sl, pcb, LP_WAY_BITS'(0), LP_ITR_BITS'(9), LP_ITR_BITS'(2),
         LP_CNF_BITS'(2), 8'h80, '0, 1'b0);
    seed(sl, pca, LP_WAY_BITS'(2), LP_ITR_BITS'(4), '0,
         LP_CNF_BITS'(1), 8'h80, '0, 1'b0);

    do_pred(sl, pcb);
    pre      = pred_p1[sl];
    u        = mk_res(pca, 1'b0, LP_ITR_BITS'(4), 1'b1);
    u.lp_way = LP_WAY_BITS'(0);
    send_upd(sl, u);
    do_pred(sl, pca);
    check($sformatf("TC21a.%s", sl_of(sl)),
          (pred_p1[sl].lp_way == LP_WAY_BITS'(2)) &&
          (pred_p1[sl].lp_conf == LP_CNF_BITS'(2)),
          "re-lookup: the entry is found by tag, not the carried way");
    do_pred(sl, pcb);
    check($sformatf("TC21b.%s", sl_of(sl)), pred_p1[sl] == pre,
          "re-lookup: the carried way's other entry is untouched");

    // The pca entry is replaced by another tag in its way.
    seed(sl, VA_WIDTH'('h0004_1000), LP_WAY_BITS'(2), LP_ITR_BITS'(9),
         LP_ITR_BITS'(9), LP_CNF_BITS'(1), 8'h80, '0, 1'b0);
    send_upd(sl, mk_res(pca, 1'b0, LP_ITR_BITS'(4), 1'b1));
    do_pred(sl, VA_WIDTH'('h0004_1000));
    check($sformatf("TC21c.%s", sl_of(sl)),
          (idx_of(VA_WIDTH'('h0004_1000)) == idx_of(pca)) &&
          pred_p1[sl].lp_hit && (pred_p1[sl].lp_way == LP_WAY_BITS'(2)) &&
          (pred_p1[sl].lp_conf == LP_CNF_BITS'(1)) &&
          (pred_p1[sl].lp_past_itr == LP_ITR_BITS'(9)),
          "re-lookup: a replaced entry is not written by a miss");
    $display("TC21 slot %0d -- Update looks the tag up again: PASS", sl);
  endtask

  // ================================================================
  // TC22: P2 RE-READ AND THE ITERATION NUMBER (BP-122).
  //       Three blocks of one entry, back to back, each advancing
  //       taken at p2. The p0 read of the third sees none of the
  //       advances of the two ahead of it; its p2 re-read sees both.
  //       Each p2 carries its own iteration number: 2, 3, 4.
  // ================================================================
  task automatic tc22(input int sl);
    logic [VA_WIDTH-1:0]    pc22;
    logic [LP_ITR_BITS-1:0] got [3];
    logic [LP_ITR_BITS-1:0] p1c;

    do_reset();
    pc22 = VA_WIDTH'('h0002_2200);
    seed(sl, pc22, LP_WAY_BITS'(1), LP_ITR_BITS'(6), '0,
         LP_CNF_BITS'(LP_CONF_LEVEL), 8'hFF, LP_ITR_BITS'(2), 1'b1);

    idle_all();
    for (int c = 0; c < 5; c++) begin
      // p0 of block c (blocks 0..2), p2 of block c-2.
      pred_pc_p0[sl]    = pc22;
      pred_valid_p0[sl] = (c < 3);
      spec_val_p2[sl]   = (c >= 2);
      spec_tkn_p2[sl]   = 1'b1;
      spec_ck_p2        = (c >= 2);
      spec_idx_p2       = FTQ_IDX_BITS'(c);
      #1;
      if (c >= 2) got[c-2] = pred_p2[sl].lp_curs;
      @(posedge clk); #1;
      if (c == 2) p1c = pred_p1[sl].lp_curs;
    end
    idle_all();
    check($sformatf("TC22a.%s", sl_of(sl)),
          (got[0] == LP_ITR_BITS'(2)) && (got[1] == LP_ITR_BITS'(3)) &&
          (got[2] == LP_ITR_BITS'(4)),
          $sformatf("p2 re-read: iteration numbers %0d %0d %0d (2 3 4)",
                    got[0], got[1], got[2]));
    check($sformatf("TC22b.%s", sl_of(sl)), p1c == LP_ITR_BITS'(2),
          "p0 read of the third block predates both advances (2)");
    do_pred(sl, pc22);
    check($sformatf("TC22c.%s", sl_of(sl)),
          (pred_p1[sl].lp_curs == LP_ITR_BITS'(5)) && pred_p1[sl].lp_curs_v,
          "three taken advances leave the count at 5");
    $display("TC22 slot %0d -- p2 re-read, iteration number: PASS", sl);
  endtask

  // ================================================================
  // TC23: AN UNKNOWN COUNT (BP-122). A trained entry (cnf max) whose
  //       count is unknown is not trusted at p1 or p2; a taken
  //       advance leaves it unknown; an exit advance makes it 0,
  //       known, and the entry is trusted.
  // ================================================================
  task automatic tc23(input int sl);
    logic [VA_WIDTH-1:0] pc23;
    lp_pred_t            p2;

    do_reset();
    pc23 = VA_WIDTH'('h0002_3300);
    seed(sl, pc23, LP_WAY_BITS'(0), LP_ITR_BITS'(4), '0,
         LP_CNF_BITS'(LP_CONF_LEVEL), 8'hFF, LP_ITR_BITS'(3), 1'b0);

    do_p2(sl, pc23, 1'b1, 1'b1, FTQ_IDX_BITS'(5), p2);
    check($sformatf("TC23a.%s", sl_of(sl)),
          p2.lp_hit && !p2.lp_pred_is_loop && !p2.lp_curs_v,
          "unknown count: the p2 read is not trusted");
    do_pred(sl, pc23);
    check($sformatf("TC23b.%s", sl_of(sl)),
          !pred_p1[sl].lp_curs_v && !pred_p1[sl].lp_pred_is_loop,
          "a taken advance leaves the count unknown");

    do_p2(sl, pc23, 1'b1, 1'b0, FTQ_IDX_BITS'(6), p2);
    do_pred(sl, pc23);
    check($sformatf("TC23c.%s", sl_of(sl)),
          pred_p1[sl].lp_curs_v && (pred_p1[sl].lp_curs == '0) &&
          pred_p1[sl].lp_pred_is_loop && pred_p1[sl].lp_pred_taken,
          "an exit advance makes the count 0, known; trusted, taken");
    $display("TC23 slot %0d -- Unknown count, exit resync: PASS", sl);
  endtask

  // ================================================================
  // TC24: RESTORE FROM THE CHECKPOINT (BP-122). Block k reads count
  //       4 at p2 and advances taken (5); block k+1 advances taken
  //       (6). Restoring k with the slot executed not taken gives 0;
  //       restoring k with the slot executed taken gives 5; restoring
  //       k with the slot not executed puts back 4.
  // ================================================================
  task automatic tc24(input int sl);
    logic [VA_WIDTH-1:0]     pc24;
    logic [FTQ_IDX_BITS-1:0] k;
    lp_pred_t                p2;

    k    = FTQ_IDX_BITS'(9);
    pc24 = VA_WIDTH'('h0002_4400);
    for (int m = 0; m < 3; m++) begin
      do_reset();
      seed(sl, pc24, LP_WAY_BITS'(3), LP_ITR_BITS'(8), '0,
           LP_CNF_BITS'(LP_CONF_LEVEL), 8'hFF, LP_ITR_BITS'(4), 1'b1);
      do_p2(sl, pc24, 1'b1, 1'b1, k, p2);
      do_p2(sl, pc24, 1'b1, 1'b1, k + FTQ_IDX_BITS'(1), p2);
      check($sformatf("TC24pre.%s.%0d", sl_of(sl), m),
            p2.lp_curs == LP_ITR_BITS'(5),
            "the second block read the first block's advance");
      case (m)
        0: do_rst(sl, k, 1'b1, 1'b0, 1'b0);
        1: do_rst(sl, k, 1'b1, 1'b1, 1'b0);
        default: do_rst(sl, k, 1'b0, 1'b0, 1'b0);
      endcase
      do_pred(sl, pc24);
      case (m)
        0: check($sformatf("TC24a.%s", sl_of(sl)),
                 pred_p1[sl].lp_curs_v && (pred_p1[sl].lp_curs == '0),
                 "restore, executed not taken: count 0, known");
        1: check($sformatf("TC24b.%s", sl_of(sl)),
                 pred_p1[sl].lp_curs_v &&
                 (pred_p1[sl].lp_curs == LP_ITR_BITS'(5)),
                 "restore, executed taken: count 4 + 1");
        default: check($sformatf("TC24c.%s", sl_of(sl)),
                 pred_p1[sl].lp_curs_v &&
                 (pred_p1[sl].lp_curs == LP_ITR_BITS'(4)),
                 "restore, not executed: count put back to 4");
      endcase
    end
    $display("TC24 slot %0d -- Restore from the checkpoint: PASS", sl);
  endtask

  // ================================================================
  // TC25: INVALIDATE (BP-122). Two entries with known counts. A
  //       rollback that invalidates and restores one of them leaves
  //       that one known (the restore wins) and the other unknown.
  // ================================================================
  task automatic tc25(input int sl);
    logic [VA_WIDTH-1:0] pca, pcb;
    lp_pred_t            p2;

    do_reset();
    pca = VA_WIDTH'('h0002_5500);
    pcb = VA_WIDTH'('h0002_5A00);
    seed(sl, pca, LP_WAY_BITS'(0), LP_ITR_BITS'(8), '0,
         LP_CNF_BITS'(LP_CONF_LEVEL), 8'hFF, LP_ITR_BITS'(2), 1'b1);
    seed(sl, pcb, LP_WAY_BITS'(0), LP_ITR_BITS'(8), '0,
         LP_CNF_BITS'(LP_CONF_LEVEL), 8'hFF, LP_ITR_BITS'(7), 1'b1);
    do_p2(sl, pca, 1'b1, 1'b1, FTQ_IDX_BITS'(20), p2);
    do_rst(sl, FTQ_IDX_BITS'(20), 1'b1, 1'b1, 1'b1);
    do_pred(sl, pca);
    check($sformatf("TC25a.%s", sl_of(sl)),
          pred_p1[sl].lp_curs_v && (pred_p1[sl].lp_curs == LP_ITR_BITS'(3)),
          "invalidate: the restored entry keeps a known count (3)");
    do_pred(sl, pcb);
    check($sformatf("TC25b.%s", sl_of(sl)),
          !pred_p1[sl].lp_curs_v && !pred_p1[sl].lp_pred_is_loop,
          "invalidate: every other count becomes unknown, untrusted");
    $display("TC25 slot %0d -- Invalidate: PASS", sl);
  endtask

  // ================================================================
  // TC26: A RESTORE WHOSE ENTRY WAS REPLACED (BP-122). The
  //       checkpointed way now holds another tag: the restore writes
  //       nothing.
  // ================================================================
  task automatic tc26(input int sl);
    logic [VA_WIDTH-1:0] pca, pcx;
    lp_pred_t            p2;

    do_reset();
    pca = VA_WIDTH'('h0002_1000);
    pcx = VA_WIDTH'('h0004_1000);
    check($sformatf("TC26pre.%s", sl_of(sl)),
          (idx_of(pca) == idx_of(pcx)) && (tag_of(pca) != tag_of(pcx)),
          "TC26: the two PCs must share a set and differ in tag");
    seed(sl, pca, LP_WAY_BITS'(1), LP_ITR_BITS'(8), '0,
         LP_CNF_BITS'(LP_CONF_LEVEL), 8'hFF, LP_ITR_BITS'(4), 1'b1);
    do_p2(sl, pca, 1'b1, 1'b1, FTQ_IDX_BITS'(30), p2);
    seed(sl, pcx, LP_WAY_BITS'(1), LP_ITR_BITS'(8), '0,
         LP_CNF_BITS'(1), 8'hFF, LP_ITR_BITS'(11), 1'b1);
    do_rst(sl, FTQ_IDX_BITS'(30), 1'b1, 1'b0, 1'b0);
    do_pred(sl, pcx);
    check($sformatf("TC26a.%s", sl_of(sl)),
          pred_p1[sl].lp_curs_v &&
          (pred_p1[sl].lp_curs == LP_ITR_BITS'(11)),
          "a restore of a replaced entry writes nothing");
    $display("TC26 slot %0d -- Restore of a replaced entry: PASS", sl);
  endtask

  // ================================================================
  // TC27: A PREDICTION IN THE SAME CYCLE AS AN UPDATE TO ITS ENTRY
  //       SEES THE OLD VALUE (Ruled Change; Read-during-write
  //       contract). The exit update raises cnf 2 -> 3 in the cycle
  //       of the lookup: the lookup reports 2, the next one 3.
  // ================================================================
  task automatic tc27(input int sl);
    logic [VA_WIDTH-1:0] pc27;

    do_reset();
    pc27 = VA_WIDTH'('h0002_7700);
    seed(sl, pc27, LP_WAY_BITS'(0), LP_ITR_BITS'(5), '0,
         LP_CNF_BITS'(2), 8'hFF, '0, 1'b1);
    idle_all();
    pred_pc_p0[sl]    = pc27;
    pred_valid_p0[sl] = 1'b1;
    upd_p0[sl]        = mk_res(pc27, 1'b0, LP_ITR_BITS'(5), 1'b1);
    upd_valid_p0[sl]  = 1'b1;
    @(posedge clk); #1;
    idle_all();
    check($sformatf("TC27a.%s", sl_of(sl)),
          pred_p1[sl].lp_conf == LP_CNF_BITS'(2),
          "same-cycle update: the prediction sees the old conf (2)");
    do_pred(sl, pc27);
    check($sformatf("TC27b.%s", sl_of(sl)),
          pred_p1[sl].lp_conf == LP_CNF_BITS'(LP_CONF_LEVEL),
          "the next prediction sees the update (3)");
    $display("TC27 slot %0d -- Same-cycle update, old value: PASS", sl);
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
    lp_pred_t            pre_a, pre_b, post_a, post_b;

    pc14 = VA_WIDTH'('h0001_4000);

    for (int a = 0; a < NUM_PRED_SLOTS; a++) begin
      for (int b = 0; b < NUM_PRED_SLOTS; b++) begin
        if (a == b) continue;

        do_reset();

        // Seed BOTH slots with the same entry so "unchanged" is a
        // real value, not the reset value.
        alloc_entry(a, pc14, pc14 - VA_WIDTH'('d256), LP_WAY_BITS'(0));
        alloc_entry(b, pc14, pc14 - VA_WIDTH'('d256), LP_WAY_BITS'(0));

        do_pred(a, pc14);
        pre_a = pred_p1[a];
        do_pred(b, pc14);
        pre_b = pred_p1[b];

        check($sformatf("TC14pre.%0d%0d", a, b),
              pre_a.lp_hit && pre_b.lp_hit &&
              (pre_a.lp_curr_itr == LP_ITR_BITS'(1)) &&
              (pre_b.lp_curr_itr == LP_ITR_BITS'(1)),
              "TC14: both slots must start from the seeded entry");

        // An exit carrying 9 on slot a only: past_itr 0 -> 9,
        // curr_itr 1 -> 0.
        send_upd(a, mk_res(pc14, 1'b0, LP_ITR_BITS'(9), 1'b1));

        do_pred(a, pc14);
        post_a = pred_p1[a];
        do_pred(b, pc14);
        post_b = pred_p1[b];

        check($sformatf("TC14a.%0d%0d", a, b),
              post_a.lp_curr_itr == '0,
              "TC14: the updated slot must clear curr_itr");
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

    pca = VA_WIDTH'('h0001_4A00);
    pcb = VA_WIDTH'('h0001_4B00);

    for (int a = 0; a < NUM_PRED_SLOTS; a++) begin
      for (int b = 0; b < NUM_PRED_SLOTS; b++) begin
        if (a == b) continue;

        do_reset();
        alloc_entry(a, pca, pca - VA_WIDTH'('d256), LP_WAY_BITS'(0));
        alloc_entry(b, pcb, pcb - VA_WIDTH'('d256), LP_WAY_BITS'(0));

        do_pred(b, pcb);
        pre_b = pred_p1[b];
        check($sformatf("TC14Bpre.%0d%0d", a, b),
              pre_b.lp_hit && (pre_b.lp_curr_itr == LP_ITR_BITS'(1)),
              "TC14B: the quiet slot must start from its own entry");

        // Live payload on slot a, live payload on slot b, but only
        // slot a's valid is asserted.
        ua = mk_res(pca, 1'b1, LP_ITR_BITS'(1), 1'b1);

        // The decoy: an exit with a known count at slot b's own entry,
        // and a taken backward branch, so the training path and the
        // allocation path would both be visible if either fired.
        ub        = mk_res(pcb, 1'b0, LP_ITR_BITS'(3000), 1'b1);
        ub.lp_way = LP_WAY_BITS'(0);

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

    do_reset();

    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      pc[s] = VA_WIDTH'('h0001_5000) + (VA_WIDTH'(s) * VA_WIDTH'('h400));
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

    // Seed slot s with curr_itr = s+1 at its own PC: the allocation
    // gives 1 and each taken resolution steps it.
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      alloc_entry(s, pc[s], pc[s] - VA_WIDTH'('d256), LP_WAY_BITS'(0));
      for (int k = 0; k < s; k++) begin
        send_upd(s, mk_res(pc[s], 1'b1, LP_ITR_BITS'(k + 1), 1'b1));
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
  // slot lands one slot's payload in another slot's bank. The
  // update of slot s is an exit carrying 10*(s+1), which slot s
  // learns as its past_itr.
  // ================================================================
  task automatic tc16;
    logic [VA_WIDTH-1:0] pc16;

    do_reset();
    pc16 = VA_WIDTH'('h0001_6000);

    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      alloc_entry(s, pc16, pc16 - VA_WIDTH'('d256), LP_WAY_BITS'(0));
    end

    idle_all();
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      upd_p0[s]       = mk_res(pc16, 1'b0, LP_ITR_BITS'(10 * (s + 1)),
                               1'b1);
      upd_valid_p0[s] = 1'b1;
    end
    @(posedge clk); #1;
    upd_valid_p0 = '0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) upd_p0[s] = '0;

    // Read every slot back, one at a time.
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      do_pred(s, pc16);
      check($sformatf("TC16a.s%0d", s),
            pred_p1[s].lp_curr_itr == '0,
            "TC16: each slot must clear its curr_itr");
      check($sformatf("TC16b.s%0d", s),
            pred_p1[s].lp_past_itr == LP_ITR_BITS'(10 * (s + 1)),
            "TC16: each slot must hold its own past_itr");
      check($sformatf("TC16c.s%0d", s),
            pred_p1[s].lp_conf == '0,
            "TC16: each slot learned, conf 0");
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
  //
  // Part C (BP-122) proves every checkpoint is empty: a restore of
  // any FTQ entry, with every slot executed, writes nothing.
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
      pc17  = VA_WIDTH'('h0000_0080);
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
        u.pc              = VA_WIDTH'('hFF00);
        u.target          = VA_WIDTH'('hF000);  // backward
        send_upd(s, u);
      end
    end

    // ---- Part C: every checkpoint empty after reset (BP-122) ----
    do_reset();
    pc17 = VA_WIDTH'('h0001_7700);
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      seed(s, pc17, LP_WAY_BITS'(0), LP_ITR_BITS'(5), '0,
           LP_CNF_BITS'(1), 8'hFF, LP_ITR_BITS'(3), 1'b1);
    end
    for (int k = 0; k < FTQ_DEPTH; k++) begin
      idle_all();
      rst_val = 1'b1;
      rst_idx = FTQ_IDX_BITS'(k);
      rst_ex  = '1;
      rst_tkn = '0;
      @(posedge clk); #1;
    end
    idle_all();
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      do_pred(s, pc17);
      check($sformatf("TC17m.s%0d", s),
            pred_p1[s].lp_curs_v && (pred_p1[s].lp_curs == LP_ITR_BITS'(3)),
            "reset: a restore from an empty checkpoint writes nothing");
    end
    $display("TC17 -- Reset state of every bank: PASS");
  endtask

  // ----------------------------------------------------------------
  // Test body
  // ----------------------------------------------------------------
  initial begin : test_body
    if (NUM_PRED_SLOTS > 2)
      $fatal(1, "tb_loop_pred: seed() names banks 0 and 1 only");
    fail_count  = 0;
    check_count = 0;
    idle_all();
    rstn = 1'b0;

    // -- Directed algorithm set, once per slot.
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
      tc19(sl);
      tc20(sl);
      tc21(sl);
      tc22(sl);
      tc23(sl);
      tc24(sl);
      tc25(sl);
      tc26(sl);
      tc27(sl);
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
      $display("ALL TC1-TC27 TESTS PASSED");
      $finish(0);
    end else begin
      $display("FAILURES DETECTED: %0d", fail_count);
      $fatal(1, "tb_loop_pred failed");
    end
  end

endmodule : tb
