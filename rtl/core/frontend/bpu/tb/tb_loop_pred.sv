// tb_loop_pred.sv
// Self-checking testbench for loop_pred.sv.
// TC1-TC7: cold miss, backward alloc, forward no-alloc,
// low-conf hit, confidence build, trusted taken, trusted exit.
// Date: 2026-03-31

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  // ----------------------------------------------------------------
  // DUT signals
  // ----------------------------------------------------------------
  logic                clk;
  logic                rstn;
  logic [VA_WIDTH-1:0] pred_pc_p0;
  logic                pred_valid_p0;
  lp_pred_t            pred_p0;
  lp_upd_t             upd_p0;
  logic                upd_valid_p0;

  loop_pred dut (
    .clk           (clk),
    .rstn          (rstn),
    .pred_pc_p0    (pred_pc_p0),
    .pred_valid_p0 (pred_valid_p0),
    .pred_p0       (pred_p0),
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
  // Index and tag helpers (mirror loop_pred.sv hash functions)
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
  int fail_count;

  task automatic check(
    input string tc,
    input logic  cond,
    input string msg
  );
    if (!cond) begin
      $display("FAIL [%s]: %s", tc, msg);
      fail_count++;
    end
  endtask

  // 2-cycle active reset, deassert, 1 settling cycle
  task automatic do_reset;
    rstn          = 1'b0;
    pred_pc_p0    = '0;
    pred_valid_p0 = 1'b0;
    upd_p0        = '0;
    upd_valid_p0  = 1'b0;
    @(posedge clk); #1;
    @(posedge clk); #1;
    rstn = 1'b1;
    @(posedge clk); #1;
  endtask

  // Allocate one entry via a backward branch miss (lp_hit=0).
  // victim must be set to the way chosen at prediction time.
  task automatic alloc_entry(
    input logic [VA_WIDTH-1:0]    pc,
    input logic [VA_WIDTH-1:0]    target,
    input logic [LP_WAY_BITS-1:0] victim
  );
    upd_p0              = '0;
    upd_p0.pc           = pc;
    upd_p0.target       = target;
    upd_p0.actual_taken = 1'b1;
    upd_p0.lp_hit       = 1'b0;
    upd_p0.lp_pred_is_loop = 1'b0;
    upd_p0.lp_idx          = idx_of(pc);
    upd_p0.lp_tag          = tag_of(pc);
    upd_p0.lp_victim       = victim;
    upd_valid_p0        = 1'b1;
    @(posedge clk); #1;
    upd_valid_p0        = 1'b0;
    upd_p0              = '0;
  endtask

  // ----------------------------------------------------------------
  // Test body
  // ----------------------------------------------------------------
  initial begin : test_body
    fail_count = 0;
    do_reset();

    // ============================================================
    // TC1: Cold miss -- pred_is_loop must be 0
    // ============================================================
    begin
      pred_pc_p0    = 40'h0000_1100;
      pred_valid_p0 = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0 = 1'b0;
      check("TC1", pred_p0.lp_pred_is_loop == 1'b0,
            "cold lookup: pred_is_loop should be 0");
      $display("TC1 -- Cold miss: %s",
               (!pred_p0.lp_pred_is_loop) ? "PASS" : "FAIL");
    end

    // ============================================================
    // TC2: Backward branch miss allocates; lookup shows lp_hit=1
    // After reset all ways invalid -> victim=0, way=0.
    // ============================================================
    begin : tc2
      logic [VA_WIDTH-1:0] pc2, tgt2;
      pc2  = 40'h0000_2200;
      tgt2 = pc2 - 40'd256; // backward: tgt < pc
      alloc_entry(pc2, tgt2, 2'b00);
      pred_pc_p0    = pc2;
      pred_valid_p0 = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0 = 1'b0;
      check("TC2a", pred_p0.lp_hit == 1'b1,
            "after alloc: lp_hit should be 1");
      check("TC2b", pred_p0.lp_pred_is_loop == 1'b0,
            "after alloc: cnf=0, pred_is_loop should be 0");
      check("TC2c", pred_p0.lp_way == 2'b00,
            "after alloc: entry should be at way 0");
      $display("TC2 -- Backward alloc: %s",
               (pred_p0.lp_hit && !pred_p0.lp_pred_is_loop &&
                pred_p0.lp_way == 2'b00) ? "PASS" : "FAIL");
    end

    // ============================================================
    // TC3: Forward branch miss -- no allocation, lp_hit stays 0
    // target > pc disables the alloc path in loop_pred.
    // ============================================================
    begin : tc3
      logic [VA_WIDTH-1:0] pc3, tgt3;
      pc3  = 40'h0000_3300;
      tgt3 = pc3 + 40'd256; // forward: tgt > pc -> no alloc
      upd_p0              = '0;
      upd_p0.pc           = pc3;
      upd_p0.target       = tgt3;
      upd_p0.actual_taken = 1'b1;
      upd_p0.lp_hit       = 1'b0;
      upd_p0.lp_pred_is_loop = 1'b0;
      upd_p0.lp_idx          = idx_of(pc3);
      upd_p0.lp_tag          = tag_of(pc3);
      upd_p0.lp_victim       = 2'b00;
      upd_valid_p0        = 1'b1;
      @(posedge clk); #1;
      upd_valid_p0        = 1'b0;
      upd_p0              = '0;
      pred_pc_p0          = pc3;
      pred_valid_p0       = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0       = 1'b0;
      check("TC3", pred_p0.lp_hit == 1'b0,
            "forward branch: no alloc, lp_hit should be 0");
      $display("TC3 -- Forward no-alloc: %s",
               (!pred_p0.lp_hit) ? "PASS" : "FAIL");
    end

    // ============================================================
    // TC4: Hit with cnf < LP_CONF_LEVEL -- pred_is_loop=0
    // Entry present (lp_hit=1) but confidence not yet at max.
    // ============================================================
    begin : tc4
      logic [VA_WIDTH-1:0] pc4, tgt4;
      pc4  = 40'h0000_4400;
      tgt4 = pc4 - 40'd256;
      alloc_entry(pc4, tgt4, 2'b00);
      pred_pc_p0    = pc4;
      pred_valid_p0 = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0 = 1'b0;
      check("TC4a", pred_p0.lp_hit == 1'b1,
            "TC4: entry present, lp_hit should be 1");
      check("TC4b", pred_p0.lp_pred_is_loop == 1'b0,
            "TC4: cnf<LP_CONF_LEVEL, pred_is_loop should be 0");
      $display("TC4 -- Low-conf hit: %s",
               (pred_p0.lp_hit && !pred_p0.lp_pred_is_loop) ?
               "PASS" : "FAIL");
    end

    // ============================================================
    // TC5/TC6/TC7 share one entry (PC=0x5500, 2-iteration loop).
    //
    // Confidence build sequence:
    //   alloc       -> cnf=0, curr=1,  past=0
    //   wrong exit  -> cnf=0, curr=0,  past=1
    //   [x LP_CONF_LEVEL rounds]:
    //     cond5 taken     -> curr: 0->1 (no cnf change)
    //     correct exit    -> cnf++, curr=0, past=1
    //   After rounds: cnf=LP_CONF_LEVEL, past=1, curr=0.
    //   lookup -> TC5 (pred_is_loop=1) and TC6 (pred_taken=1).
    //   cond1 update -> curr: 0->1 (=past).
    //   lookup -> TC7 (pred_taken=0, exit).
    // ============================================================
    begin : tc567
      logic [VA_WIDTH-1:0]    pc5, tgt5;
      logic [LP_IDX_BITS-1:0] idx5;
      logic [LP_TAG_BITS-1:0] tag5;
      int                     c;

      pc5  = 40'h0000_5500;
      tgt5 = pc5 - 40'd256;
      idx5 = idx_of(pc5);
      tag5 = tag_of(pc5);

      // --- Step 1: allocate ---
      // mem after: v=1, cnf=0, curr_itr=1, past_itr=0, age=max
      alloc_entry(pc5, tgt5, 2'b00);

      // --- Step 2: wrong exit (curr=1 != past=0) ---
      // mem after: cnf=0, past_itr=1, curr_itr=0
      upd_p0              = '0;
      upd_p0.lp_hit       = 1'b1;
      upd_p0.lp_pred_is_loop = 1'b0;
      upd_p0.actual_taken = 1'b0; // not taken (attempted exit)
      upd_p0.lp_curr_itr     = LP_ITR_BITS'(1);
      upd_p0.lp_past_itr     = LP_ITR_BITS'(0);
      upd_p0.lp_conf         = LP_CNF_BITS'(0);
      upd_p0.lp_idx          = idx5;
      upd_p0.lp_tag          = tag5;
      upd_p0.lp_way          = 2'b00;
      upd_p0.pc           = pc5;
      upd_p0.target       = tgt5;
      upd_valid_p0        = 1'b1;
      @(posedge clk); #1;
      upd_valid_p0        = 1'b0;

      // --- Steps 3-N: LP_CONF_LEVEL rounds of cond5 + exit ---
      // Round i: cond5 increments curr (0->1); correct exit
      // increments cnf by 1, resets curr to 0. past stays 1.
      c = 0;
      for (int i = 0; i < LP_CONF_LEVEL; i++) begin
        // Cond5: lp_hit=1, pred_is_loop=0, actual_taken=1
        // curr_itr in mem (=0) increments to 1; cnf unchanged.
        upd_p0              = '0;
        upd_p0.lp_hit       = 1'b1;
        upd_p0.lp_pred_is_loop = 1'b0;
        upd_p0.actual_taken = 1'b1;
        upd_p0.lp_curr_itr     = LP_ITR_BITS'(0);
        upd_p0.lp_past_itr     = LP_ITR_BITS'(1);
        upd_p0.lp_conf         = LP_CNF_BITS'(c);
        upd_p0.lp_idx          = idx5;
        upd_p0.lp_tag          = tag5;
        upd_p0.lp_way          = 2'b00;
        upd_p0.pc           = pc5;
        upd_p0.target       = tgt5;
        upd_valid_p0        = 1'b1;
        @(posedge clk); #1;
        upd_valid_p0        = 1'b0;
        // mem after: cnf=c, curr_itr=1, past_itr=1

        // Correct exit: actual_taken=0, curr_itr=1==past_itr=1
        // -> cnf = c+1, past_itr=1, curr_itr=0
        upd_p0              = '0;
        upd_p0.lp_hit       = 1'b1;
        upd_p0.lp_pred_is_loop = 1'b0;
        upd_p0.actual_taken = 1'b0;
        upd_p0.lp_curr_itr     = LP_ITR_BITS'(1);
        upd_p0.lp_past_itr     = LP_ITR_BITS'(1);
        upd_p0.lp_conf         = LP_CNF_BITS'(c);
        upd_p0.lp_idx          = idx5;
        upd_p0.lp_tag          = tag5;
        upd_p0.lp_way          = 2'b00;
        upd_p0.pc           = pc5;
        upd_p0.target       = tgt5;
        upd_valid_p0        = 1'b1;
        @(posedge clk); #1;
        upd_valid_p0        = 1'b0;
        c = c + 1;
        // mem after: cnf=c, past_itr=1, curr_itr=0
      end
      upd_p0 = '0;
      // mem: cnf=LP_CONF_LEVEL=3, past_itr=1, curr_itr=0

      // TC5/TC6 lookup: curr_itr=0 < past_itr=1
      pred_pc_p0    = pc5;
      pred_valid_p0 = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0 = 1'b0;

      // -- TC5 check --
      check("TC5", pred_p0.lp_pred_is_loop == 1'b1,
            "cnf=LP_CONF_LEVEL: pred_is_loop should be 1");
      $display("TC5 -- Confidence at max: %s",
               pred_p0.lp_pred_is_loop ? "PASS" : "FAIL");

      // -- TC6 check (same lookup: curr=0 < past=1 -> taken) --
      check("TC6a", pred_p0.lp_pred_is_loop == 1'b1,
            "TC6: pred_is_loop should be 1 (trusted)");
      check("TC6b", pred_p0.lp_pred_taken == 1'b1,
            "TC6: curr_itr<past_itr, pred_taken should be 1");
      $display("TC6 -- Trusted taken: %s",
               (pred_p0.lp_pred_is_loop && pred_p0.lp_pred_taken) ?
               "PASS" : "FAIL");

      // -- TC7: advance curr_itr to past_itr, then verify exit --
      // Cond1 update: pred_is_loop=1, pred_taken=1, actual_taken=1
      // -> curr_itr: 0 -> 1 (= past_itr). cnf unchanged.
      upd_p0              = '0;
      upd_p0.lp_pred_is_loop = 1'b1;
      upd_p0.lp_hit       = 1'b1;
      upd_p0.actual_taken = 1'b1;
      upd_p0.lp_pred_taken   = 1'b1;
      upd_p0.lp_curr_itr     = LP_ITR_BITS'(0);
      upd_p0.lp_past_itr     = LP_ITR_BITS'(1);
      upd_p0.lp_conf         = LP_CNF_BITS'(LP_CONF_LEVEL);
      upd_p0.lp_idx          = idx5;
      upd_p0.lp_tag          = tag5;
      upd_p0.lp_way          = 2'b00;
      upd_p0.pc           = pc5;
      upd_p0.target       = tgt5;
      upd_valid_p0        = 1'b1;
      @(posedge clk); #1;
      upd_valid_p0        = 1'b0;
      upd_p0              = '0;
      // mem: cnf=3, past_itr=1, curr_itr=1

      pred_pc_p0    = pc5;
      pred_valid_p0 = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0 = 1'b0;
      check("TC7a", pred_p0.lp_pred_is_loop == 1'b1,
            "TC7: pred_is_loop should be 1 (trusted)");
      check("TC7b", pred_p0.lp_pred_taken == 1'b0,
            "TC7: curr_itr==past_itr, pred_taken should be 0");
      $display("TC7 -- Trusted exit: %s",
               (pred_p0.lp_pred_is_loop && !pred_p0.lp_pred_taken) ?
               "PASS" : "FAIL");
    end

    // ============================================================
    // TC8: Correct exit -- conf++, past_itr=curr_itr,
    //      curr_itr=0, age=max
    // ============================================================
    begin : tc8
      logic [VA_WIDTH-1:0]    pc8;
      logic [LP_IDX_BITS-1:0] idx8;
      logic [LP_TAG_BITS-1:0] tag8;

      do_reset();
      pc8  = 40'hC800;
      idx8 = idx_of(pc8);
      tag8 = tag_of(pc8);
      // lp_hit=1, pred_is_loop=0, actual_taken=0,
      // curr_itr==past_itr=5 -> correct exit fires.
      // Expected: conf->3, past_itr=5, curr_itr=0, age=max
      upd_p0              = '0;
      upd_p0.lp_hit       = 1'b1;
      upd_p0.lp_pred_is_loop = 1'b0;
      upd_p0.actual_taken = 1'b0;
      upd_p0.lp_curr_itr     = LP_ITR_BITS'(5);
      upd_p0.lp_past_itr     = LP_ITR_BITS'(5);
      upd_p0.lp_conf         = LP_CNF_BITS'(2);
      upd_p0.lp_age          = 8'h64;
      upd_p0.lp_idx          = idx8;
      upd_p0.lp_tag          = tag8;
      upd_p0.lp_way          = 2'b00;
      upd_p0.pc           = pc8;
      upd_p0.target       = pc8 - 40'd256;
      upd_valid_p0        = 1'b1;
      @(posedge clk); #1;
      upd_valid_p0        = 1'b0;
      upd_p0              = '0;
      pred_pc_p0    = pc8;
      pred_valid_p0 = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0 = 1'b0;
      check("TC8a",
            pred_p0.lp_conf == LP_CNF_BITS'(LP_CONF_LEVEL),
            "correct exit: conf should increment to max");
      check("TC8b",
            pred_p0.lp_past_itr == LP_ITR_BITS'(5),
            "correct exit: past_itr should hold prev curr_itr");
      check("TC8c",
            pred_p0.lp_curr_itr == '0,
            "correct exit: curr_itr should reset to 0");
      check("TC8d",
            pred_p0.lp_age == {LP_AGE_BITS{1'b1}},
            "correct exit: age should reset to max");
      $display("TC8 -- Correct exit: %s",
        (pred_p0.lp_conf     == LP_CNF_BITS'(LP_CONF_LEVEL) &&
         pred_p0.lp_past_itr == LP_ITR_BITS'(5)             &&
         pred_p0.lp_curr_itr == '0                          &&
         pred_p0.lp_age      == {LP_AGE_BITS{1'b1}}) ?
        "PASS" : "FAIL");
    end

    // ============================================================
    // TC9: Wrong exit -- conf=0, past_itr=curr_itr, curr_itr=0
    // ============================================================
    begin : tc9
      logic [VA_WIDTH-1:0]    pc9;
      logic [LP_IDX_BITS-1:0] idx9;
      logic [LP_TAG_BITS-1:0] tag9;

      do_reset();
      pc9  = 40'hD900;
      idx9 = idx_of(pc9);
      tag9 = tag_of(pc9);
      // lp_hit=1, pred_is_loop=0, actual_taken=0,
      // curr_itr(7) != past_itr(3) -> wrong exit fires.
      // Expected: conf=0, past_itr=7, curr_itr=0
      upd_p0              = '0;
      upd_p0.lp_hit       = 1'b1;
      upd_p0.lp_pred_is_loop = 1'b0;
      upd_p0.actual_taken = 1'b0;
      upd_p0.lp_curr_itr     = LP_ITR_BITS'(7);
      upd_p0.lp_past_itr     = LP_ITR_BITS'(3);
      upd_p0.lp_conf         = LP_CNF_BITS'(2);
      upd_p0.lp_idx          = idx9;
      upd_p0.lp_tag          = tag9;
      upd_p0.lp_way          = 2'b00;
      upd_p0.pc           = pc9;
      upd_p0.target       = pc9 - 40'd256;
      upd_valid_p0        = 1'b1;
      @(posedge clk); #1;
      upd_valid_p0        = 1'b0;
      upd_p0              = '0;
      pred_pc_p0    = pc9;
      pred_valid_p0 = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0 = 1'b0;
      check("TC9a",
            pred_p0.lp_conf == '0,
            "wrong exit: conf should reset to 0");
      check("TC9b",
            pred_p0.lp_past_itr == LP_ITR_BITS'(7),
            "wrong exit: past_itr should hold prev curr_itr");
      check("TC9c",
            pred_p0.lp_curr_itr == '0,
            "wrong exit: curr_itr should reset to 0");
      $display("TC9 -- Wrong exit: %s",
        (pred_p0.lp_conf     == '0              &&
         pred_p0.lp_past_itr == LP_ITR_BITS'(7) &&
         pred_p0.lp_curr_itr == '0) ? "PASS" : "FAIL");
    end

    // ============================================================
    // TC10: Mispredicted exit (cond4) -- conf=0, curr_itr=0,
    //       past_itr unchanged
    // ============================================================
    begin : tc10
      logic [VA_WIDTH-1:0]    pc10;
      logic [LP_IDX_BITS-1:0] idx10;
      logic [LP_TAG_BITS-1:0] tag10;

      do_reset();
      pc10  = 40'hE100;
      idx10 = idx_of(pc10);
      tag10 = tag_of(pc10);
      // pred_is_loop=1, pred_taken=0, actual_taken=1 -> cond4.
      // Expected: conf=0, curr_itr=0, past_itr=5 (unchanged)
      upd_p0              = '0;
      upd_p0.lp_hit       = 1'b1;
      upd_p0.lp_pred_is_loop = 1'b1;
      upd_p0.lp_pred_taken   = 1'b0;
      upd_p0.actual_taken = 1'b1;
      upd_p0.lp_curr_itr     = LP_ITR_BITS'(4);
      upd_p0.lp_past_itr     = LP_ITR_BITS'(5);
      upd_p0.lp_conf         = LP_CNF_BITS'(LP_CONF_LEVEL);
      upd_p0.lp_idx          = idx10;
      upd_p0.lp_tag          = tag10;
      upd_p0.lp_way          = 2'b00;
      upd_p0.pc           = pc10;
      upd_p0.target       = pc10 - 40'd256;
      upd_valid_p0        = 1'b1;
      @(posedge clk); #1;
      upd_valid_p0        = 1'b0;
      upd_p0              = '0;
      pred_pc_p0    = pc10;
      pred_valid_p0 = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0 = 1'b0;
      check("TC10a",
            pred_p0.lp_conf == '0,
            "mispred exit: conf should reset to 0");
      check("TC10b",
            pred_p0.lp_curr_itr == '0,
            "mispred exit: curr_itr should reset to 0");
      check("TC10c",
            pred_p0.lp_past_itr == LP_ITR_BITS'(5),
            "mispred exit: past_itr should be unchanged (=5)");
      $display("TC10 -- Mispredicted exit: %s",
        (pred_p0.lp_conf     == '0              &&
         pred_p0.lp_curr_itr == '0              &&
         pred_p0.lp_past_itr == LP_ITR_BITS'(5)) ?
        "PASS" : "FAIL");
    end

    // ============================================================
    // TC11: Victim selection -- all ways valid, priority 3.
    //       Fill ways 0-3 at idx11 (age=max each).
    //       Lower way 1 age to 1 via cond5 hit update.
    //       Predict PC_11 (miss) -> victim must be way 1.
    // PC_11=0x80: idx=8, tag=0x0082 (distinct from tags 1..4)
    // ============================================================
    begin : tc11
      logic [VA_WIDTH-1:0]    pc11;
      logic [LP_IDX_BITS-1:0] idx11;
      logic [LP_TAG_BITS-1:0] tag11;

      do_reset();
      pc11  = 40'h0000_0080;
      idx11 = idx_of(pc11);   // = 8
      tag11 = tag_of(pc11);   // = 0x0082, distinct from 1..4
      // Allocate all 4 ways at idx11 with tags 1..4.
      // alloc_entry_alloc: age=max(0xFF), curr_itr=1.
      upd_p0              = '0;
      upd_p0.actual_taken = 1'b1;
      upd_p0.lp_hit       = 1'b0;
      upd_p0.lp_pred_is_loop = 1'b0;
      upd_p0.lp_idx          = idx11;
      upd_p0.pc           = 40'hFF00;
      upd_p0.target       = 40'hF000;   // target < pc -> backward
      for (int w = 0; w < LP_TBL_WAYS; w++) begin
        upd_p0.lp_tag    = LP_TAG_BITS'(w + 1);
        upd_p0.lp_victim = LP_WAY_BITS'(w);
        upd_valid_p0  = 1'b1;
        @(posedge clk); #1;
        upd_valid_p0  = 1'b0;
      end
      upd_p0 = '0;
      // Ways 0-3: valid, age=0xFF, tags 1..4.
      // Lower way 1 age to 0x01 via cond5 (lp_hit=1,
      // pred_is_loop=0, actual_taken=1). Cond5 does not
      // override age, so upd_p0.lp_age=1 passes through.
      upd_p0              = '0;
      upd_p0.lp_hit       = 1'b1;
      upd_p0.lp_pred_is_loop = 1'b0;
      upd_p0.actual_taken = 1'b1;
      upd_p0.lp_idx          = idx11;
      upd_p0.lp_tag          = LP_TAG_BITS'(2);  // way 1 tag
      upd_p0.lp_way          = 2'b01;
      upd_p0.lp_age          = 8'h01;
      upd_p0.pc           = 40'hFF00;
      upd_p0.target       = 40'hF000;
      upd_valid_p0        = 1'b1;
      @(posedge clk); #1;
      upd_valid_p0        = 1'b0;
      upd_p0              = '0;
      // way0: age=0xFF. way1: age=0x01. ways2,3: age=0xFF.
      // Prio 3: way1.age(1)<way0.age(0xFF) -> victim=way 1
      pred_pc_p0    = pc11;  // tag=0x0082 != 1..4 -> miss
      pred_valid_p0 = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0 = 1'b0;
      check("TC11a",
            pred_p0.lp_hit == 1'b0,
            "TC11: non-matching tags on all ways, miss expected");
      check("TC11b",
            pred_p0.lp_victim == 2'b01,
            "TC11: way 1 has lowest age, victim should be way 1");
      $display("TC11 -- Victim selection: %s",
        (!pred_p0.lp_hit && pred_p0.lp_victim == 2'b01) ?
        "PASS" : "FAIL");
    end

    // ============================================================
    // TC12: Way conflict -- two PCs same set, independent track.
    //       PC_12a=0x1000 (idx=0, tag=0x1041) -> way 0
    //       PC_12b=0x2000 (idx=0, tag=0x2082) -> way 1
    // ============================================================
    begin : tc12
      logic [VA_WIDTH-1:0]    pc12a, pc12b;
      logic [LP_IDX_BITS-1:0] idx12;
      logic [LP_TAG_BITS-1:0] tag12a, tag12b;
      int                     tc12_f0;

      do_reset();
      pc12a   = 40'h0000_1000;
      pc12b   = 40'h0000_2000;
      idx12   = idx_of(pc12a);  // = idx_of(pc12b) = 0
      tag12a  = tag_of(pc12a);  // = 0x1041
      tag12b  = tag_of(pc12b);  // = 0x2082
      tc12_f0 = fail_count;

      alloc_entry(pc12a, pc12a - 40'd256, 2'b00);
      alloc_entry(pc12b, pc12b - 40'd256, 2'b01);
      // Both entries: curr_itr=1, past_itr=0, cnf=0, age=max.

      // Cond5 update for entry A: curr_itr 2 -> 3
      upd_p0              = '0;
      upd_p0.lp_hit       = 1'b1;
      upd_p0.lp_pred_is_loop = 1'b0;
      upd_p0.actual_taken = 1'b1;
      upd_p0.lp_curr_itr     = LP_ITR_BITS'(2);
      upd_p0.lp_past_itr     = LP_ITR_BITS'(5);
      upd_p0.lp_idx          = idx12;
      upd_p0.lp_tag          = tag12a;
      upd_p0.lp_way          = 2'b00;
      upd_p0.pc           = pc12a;
      upd_p0.target       = pc12a - 40'd256;
      upd_valid_p0        = 1'b1;
      @(posedge clk); #1;
      upd_valid_p0        = 1'b0;
      upd_p0              = '0;

      // Cond5 update for entry B: curr_itr 4 -> 5
      upd_p0              = '0;
      upd_p0.lp_hit       = 1'b1;
      upd_p0.lp_pred_is_loop = 1'b0;
      upd_p0.actual_taken = 1'b1;
      upd_p0.lp_curr_itr     = LP_ITR_BITS'(4);
      upd_p0.lp_past_itr     = LP_ITR_BITS'(5);
      upd_p0.lp_idx          = idx12;
      upd_p0.lp_tag          = tag12b;
      upd_p0.lp_way          = 2'b01;
      upd_p0.pc           = pc12b;
      upd_p0.target       = pc12b - 40'd256;
      upd_valid_p0        = 1'b1;
      @(posedge clk); #1;
      upd_valid_p0        = 1'b0;
      upd_p0              = '0;

      pred_pc_p0    = pc12a;
      pred_valid_p0 = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0 = 1'b0;
      check("TC12a",
            pred_p0.lp_curr_itr == LP_ITR_BITS'(3),
            "way conflict: entry A curr_itr should be 3");

      pred_pc_p0    = pc12b;
      pred_valid_p0 = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0 = 1'b0;
      check("TC12b",
            pred_p0.lp_curr_itr == LP_ITR_BITS'(5),
            "way conflict: entry B curr_itr should be 5");
      $display("TC12 -- Way conflict: %s",
        (fail_count == tc12_f0) ? "PASS" : "FAIL");
    end

    // ============================================================
    // TC13: curr_itr saturates at LP_ITR_BITS max (no overflow).
    //       RTL cond1: (&curr_itr)?curr_itr : curr_itr+1.
    //       Drive max-1 -> max, then verify max stays at max.
    // ============================================================
    begin : tc13
      logic [VA_WIDTH-1:0]    pc13;
      logic [LP_IDX_BITS-1:0] idx13;
      logic [LP_TAG_BITS-1:0] tag13;
      logic [LP_ITR_BITS-1:0] itr_max;
      int                     tc13_f0;

      do_reset();
      pc13    = 40'hA000;
      idx13   = idx_of(pc13);
      tag13   = tag_of(pc13);
      itr_max = {LP_ITR_BITS{1'b1}};  // 14'h3FFF
      tc13_f0 = fail_count;

      alloc_entry(pc13, pc13 - 40'd256, 2'b00);

      // Cond1 (pred_is_loop=1, actual_taken=1, pred_taken=1):
      // curr_itr = max-1 -> max (one increment to saturation).
      upd_p0              = '0;
      upd_p0.lp_hit       = 1'b1;
      upd_p0.lp_pred_is_loop = 1'b1;
      upd_p0.lp_pred_taken   = 1'b1;
      upd_p0.actual_taken = 1'b1;
      upd_p0.lp_curr_itr     = itr_max - LP_ITR_BITS'(1);
      upd_p0.lp_past_itr     = itr_max;
      upd_p0.lp_conf         = LP_CNF_BITS'(LP_CONF_LEVEL);
      upd_p0.lp_idx          = idx13;
      upd_p0.lp_tag          = tag13;
      upd_p0.lp_way          = 2'b00;
      upd_p0.pc           = pc13;
      upd_p0.target       = pc13 - 40'd256;
      upd_valid_p0        = 1'b1;
      @(posedge clk); #1;
      upd_valid_p0        = 1'b0;
      upd_p0              = '0;
      pred_pc_p0    = pc13;
      pred_valid_p0 = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0 = 1'b0;
      check("TC13a",
            pred_p0.lp_curr_itr == itr_max,
            "saturate: curr_itr should reach max after incr");

      // Cond1 again at max: must stay at max (no overflow).
      upd_p0              = '0;
      upd_p0.lp_hit       = 1'b1;
      upd_p0.lp_pred_is_loop = 1'b1;
      upd_p0.lp_pred_taken   = 1'b1;
      upd_p0.actual_taken = 1'b1;
      upd_p0.lp_curr_itr     = itr_max;
      upd_p0.lp_past_itr     = itr_max;
      upd_p0.lp_conf         = LP_CNF_BITS'(LP_CONF_LEVEL);
      upd_p0.lp_idx          = idx13;
      upd_p0.lp_tag          = tag13;
      upd_p0.lp_way          = 2'b00;
      upd_p0.pc           = pc13;
      upd_p0.target       = pc13 - 40'd256;
      upd_valid_p0        = 1'b1;
      @(posedge clk); #1;
      upd_valid_p0        = 1'b0;
      upd_p0              = '0;
      pred_pc_p0    = pc13;
      pred_valid_p0 = 1'b1;
      @(posedge clk); #1;
      pred_valid_p0 = 1'b0;
      check("TC13b",
            pred_p0.lp_curr_itr == itr_max,
            "saturate: curr_itr must not overflow past max");
      $display("TC13 -- curr_itr saturation: %s",
        (fail_count == tc13_f0) ? "PASS" : "FAIL");
    end

    // ============================================================
    // Final verdict: TC1-TC13
    // ============================================================
    if (fail_count == 0) begin
      $display("ALL TC1-TC13 TESTS PASSED");
      $finish(0);
    end else begin
      $display("FAILURES DETECTED: %0d", fail_count);
      $finish(1);
    end
  end

endmodule : tb
