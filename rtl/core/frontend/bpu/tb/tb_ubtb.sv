// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_ubtb.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking testbench for ubtb.sv (BP-086 entry format).
//
// The uBTB now performs ONE lookup per cycle against a reshaped entry
// that describes ONE UBTB_BLOCK_BYTES block: two conditional fields
// (br0, br1), one block-terminating jump field, and a partial
// fall-through plus carry. Prediction slot 0 comes from br0, slot 1
// from br1, and the jump is reported in the lowest slot carrying no
// valid conditional field.
//
// Every test establishes its own start state with a reset plus a
// known driven sequence; no test carries state from another, and no
// test relies on residue in an unrelated way. Addressing stimulus
// (same-set / distinct-tag) is DERIVED and asserted before use rather
// than assumed.
//
// TC01 reset state and lookup miss
// TC02 one entry supplying both conditional slots
// TC03 hit with only br0 occupied
// TC04 hit with no field occupied -- successor is the fall-through
// TC05 miss: same set, different tag; and a different set
// TC06 jump field reported in a slot, all five jump types
// TC07 jump placed in the lowest slot with no conditional field
// TC08 conf trained to both saturation points; position held
// TC09 target reconstruction, conditional and jump displacements
// TC10 fall-through reconstruction, carry in both states
// TC11 both update channels writing one entry in the same cycle
// TC12 NUM_PRED_SLOTS=1 reports br0 only
// TC13 two distinct tags coexisting in one set
// TC14 round-robin replacement across UBTB_WAYS
// TC15 read-during-write: prediction sees the pre-update state
// ===================================================================

import bp_defines_pkg::*;
import bp_structs_pkg::*;
module tb;

  // ----------------------------------------------------------------
  // DUT: NUM_PRED_SLOTS=2 (primary)
  // ----------------------------------------------------------------
  logic                clk;
  logic                rstn;

  logic [VA_WIDTH-1:0] pred_pc2;
  ubtb_pred_t [1:0]    pred2;
  ubtb_blk_t           blk2;
  ubtb_upd_t  [1:0]    upd2;

  ubtb #(.NUM_PRED_SLOTS(2)) dut2 (
    .clk        (clk),
    .rstn       (rstn),
    .pred_pc_p0 (pred_pc2),
    .pred_p1    (pred2),
    .blk_p1     (blk2),
    .upd_u0     (upd2)
  );

  // ----------------------------------------------------------------
  // DUT: NUM_PRED_SLOTS=1 (TC12)
  // ----------------------------------------------------------------
  logic [VA_WIDTH-1:0] pred_pc1;
  ubtb_pred_t [0:0]    pred1;
  ubtb_blk_t           blk1;
  ubtb_upd_t  [0:0]    upd1;

  ubtb #(.NUM_PRED_SLOTS(1)) dut1 (
    .clk        (clk),
    .rstn       (rstn),
    .pred_pc_p0 (pred_pc1),
    .pred_p1    (pred1),
    .blk_p1     (blk1),
    .upd_u0     (upd1)
  );

  // ----------------------------------------------------------------
  // Clock: 10ns period
  // ----------------------------------------------------------------
  initial clk = 0;
  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  // ----------------------------------------------------------------
  // Scoreboard
  // ----------------------------------------------------------------
  int pass_cnt;
  int fail_cnt;
  int tc_mark;

  task automatic check(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: %s", nm);
    end
  endtask

  task automatic tc_open(input string nm);
    tc_mark = fail_cnt;
    $display("---- %s", nm);
  endtask

  task automatic tc_close(input string nm);
    $display("%s: %s", nm, (fail_cnt == tc_mark) ? "PASS" : "FAIL");
  endtask

  // ----------------------------------------------------------------
  // Address construction. Build a block PC from an explicit set index
  // and tag value so index/tag relationships are derived, never
  // assumed. TAG_BASE is chosen high enough that the largest negative
  // jump displacement under test does not wrap the VA.
  // ----------------------------------------------------------------
  localparam int unsigned TAG_BASE = 'h400;

  function automatic logic [VA_WIDTH-1:0] mk_pc(
      input int unsigned setn, input int unsigned tagv);
    mk_pc = (VA_WIDTH'(tagv) << (UBTB_OFFSET_BITS + UBTB_IDX_BITS))
          | (VA_WIDTH'(setn) << UBTB_OFFSET_BITS);
  endfunction

  // Independent restatement of the module's index/tag/base split
  // (ubtb_interfaces.md, Lookup).
  function automatic logic [UBTB_IDX_BITS-1:0] pc_idx(
      input logic [VA_WIDTH-1:0] pc);
    pc_idx = pc[UBTB_OFFSET_BITS +: UBTB_IDX_BITS];
  endfunction

  function automatic logic [UBTB_TAG_BITS-1:0] pc_tag(
      input logic [VA_WIDTH-1:0] pc);
    pc_tag = pc[UBTB_OFFSET_BITS+UBTB_IDX_BITS +: UBTB_TAG_BITS];
  endfunction

  function automatic logic [VA_WIDTH-1:0] pc_base(
      input logic [VA_WIDTH-1:0] pc);
    pc_base = {pc[VA_WIDTH-1:UBTB_OFFSET_BITS],
               {UBTB_OFFSET_BITS{1'b0}}};
  endfunction

  // Golden saturating bimodal step, independent of the DUT function.
  function automatic logic [UBTB_CONF_WIDTH-1:0] gold_step(
      input logic [UBTB_CONF_WIDTH-1:0] c, input logic up);
    if (up) gold_step = (c == {UBTB_CONF_WIDTH{1'b1}}) ? c : c + 1'b1;
    else    gold_step = (c == '0)                      ? c : c - 1'b1;
  endfunction

  // ----------------------------------------------------------------
  // Update bundle constructors. Building the whole struct and
  // assigning it in one shot keeps every unrelated field at a known
  // zero, so no test depends on a stale field left by a prior task.
  // ----------------------------------------------------------------

  // Conditional resolve into field br_idx.
  function automatic ubtb_upd_t mk_cond(
      input logic [VA_WIDTH-1:0]         pc,
      input logic                        br_idx,
      input logic                        taken,
      input logic [VA_WIDTH-1:0]         target,
      input logic [UBTB_BR_POS_BITS-1:0] pos,
      input logic [VA_WIDTH-1:0]         pft);
    ubtb_upd_t u;
    u            = '0;
    u.valid      = 1'b1;
    u.pc         = pc;
    u.is_br      = 1'b1;
    u.br_idx     = br_idx;
    u.br_taken   = taken;
    u.target     = target;
    u.pos        = pos;
    u.pft_addr   = pft;
    mk_cond      = u;
  endfunction

  // Jump resolve. The type bits are supplied verbatim.
  function automatic ubtb_upd_t mk_jmp(
      input logic [VA_WIDTH-1:0]         pc,
      input logic                        is_call,
      input logic                        is_ret,
      input logic                        is_jalr,
      input logic [VA_WIDTH-1:0]         jtgt,
      input logic [UBTB_BR_POS_BITS-1:0] pos,
      input logic [VA_WIDTH-1:0]         pft);
    ubtb_upd_t u;
    u            = '0;
    u.valid      = 1'b1;
    u.pc         = pc;
    u.is_jmp     = 1'b1;
    u.jmp_target = jtgt;
    u.is_call    = is_call;
    u.is_ret     = is_ret;
    u.is_jalr    = is_jalr;
    u.pos        = pos;
    u.pft_addr   = pft;
    mk_jmp       = u;
  endfunction

  // Boundary-only resolve: the block is known but holds no branch the
  // uBTB records. Allocates a field-less entry.
  function automatic ubtb_upd_t mk_blk(
      input logic [VA_WIDTH-1:0] pc,
      input logic [VA_WIDTH-1:0] pft);
    ubtb_upd_t u;
    u          = '0;
    u.valid    = 1'b1;
    u.pc       = pc;
    u.pft_addr = pft;
    mk_blk     = u;
  endfunction

  // ----------------------------------------------------------------
  // Stimulus tasks
  // ----------------------------------------------------------------

  // Reset both DUTs and drive every input to a known zero.
  task automatic do_reset;
    rstn     = 1'b0;
    pred_pc2 = '0;
    pred_pc1 = '0;
    upd2     = '0;
    upd1     = '0;
    @(posedge clk); #1;
    @(posedge clk); #1;
    rstn = 1'b1;
    @(posedge clk); #1;
  endtask

  // Commit whatever update bundles are currently driven, then release
  // both update ports so no write repeats.
  task automatic commit;
    @(posedge clk); #1;
    upd2 = '0;
    upd1 = '0;
  endtask

  // Present a lookup PC and let the combinational prediction settle
  // past a clock edge before sampling.
  task automatic look2(input logic [VA_WIDTH-1:0] pc);
    pred_pc2 = pc;
    @(posedge clk); #1;
  endtask

  task automatic look1(input logic [VA_WIDTH-1:0] pc);
    pred_pc1 = pc;
    @(posedge clk); #1;
  endtask

  // Single-shot conditional / jump / boundary write on channel 0.
  task automatic wr_cond(
      input logic [VA_WIDTH-1:0]         pc,
      input logic                        br_idx,
      input logic                        taken,
      input logic [VA_WIDTH-1:0]         target,
      input logic [UBTB_BR_POS_BITS-1:0] pos,
      input logic [VA_WIDTH-1:0]         pft);
    upd2[0] = mk_cond(pc, br_idx, taken, target, pos, pft);
    commit();
  endtask

  task automatic wr_jmp(
      input logic [VA_WIDTH-1:0]         pc,
      input logic                        is_call,
      input logic                        is_ret,
      input logic                        is_jalr,
      input logic [VA_WIDTH-1:0]         jtgt,
      input logic [UBTB_BR_POS_BITS-1:0] pos,
      input logic [VA_WIDTH-1:0]         pft);
    upd2[0] = mk_jmp(pc, is_call, is_ret, is_jalr, jtgt, pos, pft);
    commit();
  endtask

  // Assert that a lookup returned nothing at all.
  task automatic expect_miss(input string nm);
    check({nm, ": blk hit must be 0"},  blk2.hit == 1'b0);
    check({nm, ": slot0 must be zero"}, pred2[0] == '0);
    check({nm, ": slot1 must be zero"}, pred2[1] == '0);
  endtask

  // ----------------------------------------------------------------
  // Test body
  // ----------------------------------------------------------------
  logic [VA_WIDTH-1:0] blk_a, blk_b, blk_c;
  logic [VA_WIDTH-1:0] tgt_a, tgt_b;

  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    tc_mark  = 0;

    // ==============================================================
    // TC01 -- reset state and lookup miss
    // ==============================================================
    tc_open("TC01 reset state / miss");
    begin
      do_reset();
      blk_a = mk_pc(0, TAG_BASE);
      look2(blk_a);
      expect_miss("TC01");
      // pft_addr carries nothing on a miss.
      check("TC01: pft_addr zero on miss", blk2.pft_addr == '0);
    end
    tc_close("TC01");

    // ==============================================================
    // TC02 -- one entry supplies both conditional slots
    // ==============================================================
    tc_open("TC02 both conditional fields of one entry");
    begin
      do_reset();
      blk_a = mk_pc(0, TAG_BASE);
      tgt_a = blk_a + 40'd64;    // forward, in 13-bit reach
      tgt_b = blk_a - 40'd128;   // backward, in 13-bit reach
      // br0: taken at position 1. br1: not-taken at position 5.
      // Block ends at the next block start, so carry must be set.
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1, blk_a + 40'd32);
      wr_cond(blk_a, 1'b1, 1'b0, tgt_b, 4'd5, blk_a + 40'd32);
      look2(blk_a);

      check("TC02: hit",       blk2.hit == 1'b1);
      check("TC02: pft_addr",  blk2.pft_addr == blk_a + 40'd32);

      check("TC02: s0 valid",  pred2[0].valid    == 1'b1);
      check("TC02: s0 COND",   pred2[0].br_type  == COND);
      check("TC02: s0 target", pred2[0].target   == tgt_a);
      check("TC02: s0 pos",    pred2[0].pos      == 4'd1);
      check("TC02: s0 conf",   pred2[0].conf     == UBTB_CONF_INIT_TKN);
      check("TC02: s0 taken",  pred2[0].br_taken == 1'b1);
      check("TC02: s0 carry",  pred2[0].carry    == 1'b1);

      check("TC02: s1 valid",  pred2[1].valid    == 1'b1);
      check("TC02: s1 COND",   pred2[1].br_type  == COND);
      check("TC02: s1 target", pred2[1].target   == tgt_b);
      check("TC02: s1 pos",    pred2[1].pos      == 4'd5);
      check("TC02: s1 conf",   pred2[1].conf     == UBTB_CONF_INIT_NTK);
      check("TC02: s1 taken",  pred2[1].br_taken == 1'b0);
      check("TC02: s1 carry",  pred2[1].carry    == 1'b1);

      // The direction reported IS the conf most significant bit.
      check("TC02: s0 taken is conf MSB",
            pred2[0].br_taken == pred2[0].conf[UBTB_CONF_WIDTH-1]);
      check("TC02: s1 taken is conf MSB",
            pred2[1].br_taken == pred2[1].conf[UBTB_CONF_WIDTH-1]);
    end
    tc_close("TC02");

    // ==============================================================
    // TC03 -- hit with only br0 occupied
    // ==============================================================
    tc_open("TC03 only br0 occupied");
    begin
      do_reset();
      blk_a = mk_pc(3, TAG_BASE);
      tgt_a = blk_a + 40'd16;
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd2, blk_a + 40'd12);
      look2(blk_a);

      check("TC03: hit",       blk2.hit == 1'b1);
      check("TC03: pft_addr",  blk2.pft_addr == blk_a + 40'd12);
      check("TC03: s0 valid",  pred2[0].valid  == 1'b1);
      check("TC03: s0 target", pred2[0].target == tgt_a);
      check("TC03: s0 pos",    pred2[0].pos    == 4'd2);
      check("TC03: s0 carry",  pred2[0].carry  == 1'b0);
      // br1 free and no jump present -> slot 1 fully zero.
      check("TC03: s1 zero",   pred2[1] == '0);
    end
    tc_close("TC03");

    // ==============================================================
    // TC04 -- hit with no field occupied; fall-through is the
    //         successor
    // ==============================================================
    tc_open("TC04 hit, no field occupied");
    begin
      do_reset();
      blk_a = mk_pc(5, TAG_BASE);
      upd2[0] = mk_blk(blk_a, blk_a + 40'd20);
      commit();
      look2(blk_a);

      check("TC04: hit",      blk2.hit == 1'b1);
      check("TC04: pft_addr", blk2.pft_addr == blk_a + 40'd20);
      check("TC04: s0 zero",  pred2[0] == '0);
      check("TC04: s1 zero",  pred2[1] == '0);
    end
    tc_close("TC04");

    // ==============================================================
    // TC05 -- miss: same set different tag, and a different set
    // ==============================================================
    tc_open("TC05 miss");
    begin
      do_reset();
      blk_a = mk_pc(7, TAG_BASE);
      blk_b = mk_pc(7, TAG_BASE + 1);   // same set, other tag
      blk_c = mk_pc(8, TAG_BASE);       // other set, same tag value

      // Prove the stimulus really is same-set / distinct-tag before
      // relying on it.
      check("TC05: alias shares the set",
            pc_idx(blk_b) == pc_idx(blk_a));
      check("TC05: alias differs in tag",
            pc_tag(blk_b) != pc_tag(blk_a));
      check("TC05: other block differs in set",
            pc_idx(blk_c) != pc_idx(blk_a));

      wr_cond(blk_a, 1'b0, 1'b1, blk_a + 40'd32, 4'd0,
              blk_a + 40'd32);

      look2(blk_b);
      expect_miss("TC05 same-set-other-tag");
      look2(blk_c);
      expect_miss("TC05 other-set");
      // The written block still hits, so the misses above are not a
      // failed write.
      look2(blk_a);
      check("TC05: written block still hits", blk2.hit == 1'b1);
    end
    tc_close("TC05");

    // ==============================================================
    // TC06 -- jump field reported in a slot, all five jump types
    // ==============================================================
    tc_open("TC06 jump types");
    begin
      // {is_call, is_ret, is_jalr} -> expected bp_br_type_e
      bp_br_type_e exp_ty [5];
      logic [2:0]  ty_bits[5];
      ty_bits[0] = 3'b100; exp_ty[0] = DIRECT_CALL;     // call
      ty_bits[1] = 3'b101; exp_ty[1] = INDIRECT_CALL;   // call+jalr
      ty_bits[2] = 3'b011; exp_ty[2] = RETURN;          // ret+jalr
      ty_bits[3] = 3'b001; exp_ty[3] = INDIRECT_NONRET; // jalr
      ty_bits[4] = 3'b000; exp_ty[4] = DIRECT_UNC;      // direct jmp

      for (int i = 0; i < 5; i++) begin
        do_reset();
        blk_a = mk_pc(11, TAG_BASE);
        tgt_a = blk_a + 40'h400;
        wr_jmp(blk_a, ty_bits[i][2], ty_bits[i][1], ty_bits[i][0],
               tgt_a, 4'd7, blk_a + 40'd32);
        look2(blk_a);

        check($sformatf("TC06[%0d]: hit", i),  blk2.hit == 1'b1);
        // br0 is free, so the jump lands in slot 0.
        check($sformatf("TC06[%0d]: s0 valid", i),
              pred2[0].valid == 1'b1);
        check($sformatf("TC06[%0d]: s0 br_type", i),
              pred2[0].br_type == exp_ty[i]);
        check($sformatf("TC06[%0d]: s0 target", i),
              pred2[0].target == tgt_a);
        check($sformatf("TC06[%0d]: s0 pos", i),
              pred2[0].pos == 4'd7);
        // br_taken and conf are not meaningful for a jump.
        check($sformatf("TC06[%0d]: s0 br_taken 0", i),
              pred2[0].br_taken == 1'b0);
        check($sformatf("TC06[%0d]: s0 conf 0", i),
              pred2[0].conf == '0);
        // The jump is reported once, not in every free slot.
        check($sformatf("TC06[%0d]: s1 zero", i), pred2[1] == '0);
      end
    end
    tc_close("TC06");

    // ==============================================================
    // TC07 -- jump goes in the LOWEST slot with no conditional field
    // ==============================================================
    tc_open("TC07 jump slot placement");
    begin
      // (a) br0 occupied, br1 free -> jump reported in slot 1.
      do_reset();
      blk_a = mk_pc(13, TAG_BASE);
      tgt_a = blk_a + 40'd32;
      tgt_b = blk_a + 40'h800;
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd0, blk_a + 40'd32);
      wr_jmp (blk_a, 1'b0, 1'b1, 1'b1, tgt_b, 4'd6, blk_a + 40'd32);
      look2(blk_a);

      check("TC07a: hit",        blk2.hit == 1'b1);
      check("TC07a: s0 is COND", pred2[0].br_type == COND);
      check("TC07a: s0 target",  pred2[0].target  == tgt_a);
      check("TC07a: s1 valid",   pred2[1].valid   == 1'b1);
      check("TC07a: s1 is jump", pred2[1].br_type == RETURN);
      check("TC07a: s1 target",  pred2[1].target  == tgt_b);
      check("TC07a: s1 pos",     pred2[1].pos     == 4'd6);

      // (b) both conditionals occupied -> no free slot, jump is not
      //     reported at NUM_PRED_SLOTS=2.
      do_reset();
      blk_a = mk_pc(14, TAG_BASE);
      tgt_a = blk_a + 40'd32;
      tgt_b = blk_a - 40'd64;
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd0, blk_a + 40'd32);
      wr_cond(blk_a, 1'b1, 1'b1, tgt_b, 4'd3, blk_a + 40'd32);
      wr_jmp (blk_a, 1'b1, 1'b0, 1'b0, blk_a + 40'h800, 4'd7,
              blk_a + 40'd32);
      look2(blk_a);

      check("TC07b: hit",        blk2.hit == 1'b1);
      check("TC07b: s0 is COND", pred2[0].br_type == COND);
      check("TC07b: s1 is COND", pred2[1].br_type == COND);
      check("TC07b: s0 target",  pred2[0].target  == tgt_a);
      check("TC07b: s1 target",  pred2[1].target  == tgt_b);
    end
    tc_close("TC07");

    // ==============================================================
    // TC08 -- conf trained to both saturation points; position held
    // ==============================================================
    tc_open("TC08 conf saturation and position hold");
    begin
      logic [UBTB_CONF_WIDTH-1:0] gold;
      do_reset();
      blk_a = mk_pc(17, TAG_BASE);
      tgt_a = blk_a + 40'd48;

      // Fill br0 taken at position 3. conf starts at the weak taken
      // init, which must be unsaturated with MSB 1.
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd3, blk_a + 40'd32);
      look2(blk_a);
      gold = UBTB_CONF_INIT_TKN;
      check("TC08: fill conf is weak taken", pred2[0].conf == gold);
      check("TC08: init unsaturated",
            gold != {UBTB_CONF_WIDTH{1'b1}});
      check("TC08: fill pos", pred2[0].pos == 4'd3);

      // Train taken past the top. Each update carries a DIFFERENT
      // position: the stored position must not move once filled.
      for (int i = 0; i < 6; i++) begin
        wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd6, blk_a + 40'd32);
        look2(blk_a);
        gold = gold_step(gold, 1'b1);
        check($sformatf("TC08: taken step %0d conf", i),
              pred2[0].conf == gold);
        check($sformatf("TC08: taken step %0d taken", i),
              pred2[0].br_taken == gold[UBTB_CONF_WIDTH-1]);
        check($sformatf("TC08: taken step %0d pos held", i),
              pred2[0].pos == 4'd3);
      end
      check("TC08: saturated all-ones",
            pred2[0].conf == {UBTB_CONF_WIDTH{1'b1}});
      check("TC08: saturated predicts taken",
            pred2[0].br_taken == 1'b1);

      // Train not-taken down to the bottom, crossing the MSB flip.
      for (int i = 0; i < 10; i++) begin
        wr_cond(blk_a, 1'b0, 1'b0, tgt_a, 4'd6, blk_a + 40'd32);
        look2(blk_a);
        gold = gold_step(gold, 1'b0);
        check($sformatf("TC08: ntk step %0d conf", i),
              pred2[0].conf == gold);
        check($sformatf("TC08: ntk step %0d taken", i),
              pred2[0].br_taken == gold[UBTB_CONF_WIDTH-1]);
        check($sformatf("TC08: ntk step %0d pos held", i),
              pred2[0].pos == 4'd3);
      end
      check("TC08: saturated all-zeros", pred2[0].conf == '0);
      check("TC08: saturated predicts not-taken",
            pred2[0].br_taken == 1'b0);

      // A freshly filled field in the other direction takes the weak
      // not-taken init, which must be unsaturated with MSB 0.
      do_reset();
      wr_cond(blk_a, 1'b0, 1'b0, tgt_a, 4'd2, blk_a + 40'd32);
      look2(blk_a);
      check("TC08: fill conf is weak not-taken",
            pred2[0].conf == UBTB_CONF_INIT_NTK);
      check("TC08: weak ntk unsaturated", UBTB_CONF_INIT_NTK != '0);
      check("TC08: weak ntk predicts not-taken",
            pred2[0].br_taken == 1'b0);
    end
    tc_close("TC08");

    // ==============================================================
    // TC09 -- target reconstruction returns the original full-width
    //         target
    // ==============================================================
    tc_open("TC09 target reconstruction");
    begin
      // Conditional displacements, all inside the 13-bit signed reach
      // (-4096 .. +4095).
      logic signed [VA_WIDTH-1:0] cd [5];
      logic signed [VA_WIDTH-1:0] jd [4];
      cd[0] =  40'sd0;
      cd[1] =  40'sd4;
      cd[2] = -40'sd4;
      cd[3] =  40'sd4092;
      cd[4] = -40'sd4096;

      for (int i = 0; i < 5; i++) begin
        do_reset();
        blk_a = mk_pc(21, TAG_BASE);
        tgt_a = blk_a + VA_WIDTH'(cd[i]);
        wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1, blk_a + 40'd32);
        look2(blk_a);
        check($sformatf("TC09: cond disp %0d valid", i),
              pred2[0].valid == 1'b1);
        check($sformatf("TC09: cond disp %0d reconstructs", i),
              pred2[0].target == tgt_a);
      end

      // Jump displacements, inside the 21-bit signed reach
      // (-1048576 .. +1048575).
      jd[0] =  40'sd256;
      jd[1] = -40'sd256;
      jd[2] =  40'sd1048572;
      jd[3] = -40'sd1048576;

      for (int i = 0; i < 4; i++) begin
        do_reset();
        blk_a = mk_pc(22, TAG_BASE);
        tgt_a = blk_a + VA_WIDTH'(jd[i]);
        wr_jmp(blk_a, 1'b0, 1'b0, 1'b0, tgt_a, 4'd4,
               blk_a + 40'd32);
        look2(blk_a);
        check($sformatf("TC09: jmp disp %0d valid", i),
              pred2[0].valid == 1'b1);
        check($sformatf("TC09: jmp disp %0d reconstructs", i),
              pred2[0].target == tgt_a);
      end

      // A resolved target that moves is rewritten in place: the entry
      // already exists and the field is already occupied.
      do_reset();
      blk_a = mk_pc(23, TAG_BASE);
      tgt_a = blk_a + 40'd64;
      tgt_b = blk_a - 40'd2048;
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1, blk_a + 40'd32);
      look2(blk_a);
      check("TC09: first target", pred2[0].target == tgt_a);
      wr_cond(blk_a, 1'b0, 1'b1, tgt_b, 4'd1, blk_a + 40'd32);
      look2(blk_a);
      check("TC09: moved target rewritten",
            pred2[0].target == tgt_b);
    end
    tc_close("TC09");

    // ==============================================================
    // TC10 -- fall-through reconstruction, carry in both states
    // ==============================================================
    tc_open("TC10 fall-through and carry");
    begin
      do_reset();
      blk_a = mk_pc(25, TAG_BASE);   // ends inside its own block
      blk_b = mk_pc(26, TAG_BASE);   // ends at the next block start
      blk_c = mk_pc(27, TAG_BASE);   // ends past the boundary

      check("TC10: three distinct sets",
            (pc_idx(blk_a) != pc_idx(blk_b))
            && (pc_idx(blk_b) != pc_idx(blk_c)));

      // carry 0: end is 28 bytes into the block.
      wr_cond(blk_a, 1'b0, 1'b1, blk_a + 40'd16, 4'd6,
              blk_a + 40'd28);
      // carry 1: end is exactly the next block start; the partial
      // index is 0 and only the carry bit carries the boundary.
      wr_cond(blk_b, 1'b0, 1'b1, blk_b + 40'd16, 4'd7,
              blk_b + 40'd32);
      // carry 1 with a non-zero partial index as well.
      wr_cond(blk_c, 1'b0, 1'b1, blk_c + 40'd16, 4'd2,
              blk_c + 40'd40);

      look2(blk_a);
      check("TC10a: hit",       blk2.hit == 1'b1);
      check("TC10a: pft_addr",  blk2.pft_addr == blk_a + 40'd28);
      check("TC10a: carry 0",   pred2[0].carry == 1'b0);
      check("TC10a: end stays in block",
            pc_idx(blk2.pft_addr) == pc_idx(blk_a));

      look2(blk_b);
      check("TC10b: hit",       blk2.hit == 1'b1);
      check("TC10b: pft_addr",  blk2.pft_addr == blk_b + 40'd32);
      check("TC10b: carry 1",   pred2[0].carry == 1'b1);
      check("TC10b: end crosses the boundary",
            pc_idx(blk2.pft_addr) != pc_idx(blk_b));
      check("TC10b: end is the next block base",
            pc_base(blk2.pft_addr) == blk_b + 40'd32);

      look2(blk_c);
      check("TC10c: hit",       blk2.hit == 1'b1);
      check("TC10c: pft_addr",  blk2.pft_addr == blk_c + 40'd40);
      check("TC10c: carry 1",   pred2[0].carry == 1'b1);
      check("TC10c: end crosses the boundary",
            pc_idx(blk2.pft_addr) != pc_idx(blk_c));

      // The block boundary is rewritten on a later update.
      wr_cond(blk_b, 1'b0, 1'b1, blk_b + 40'd16, 4'd7,
              blk_b + 40'd8);
      look2(blk_b);
      check("TC10d: boundary moved back into the block",
            blk2.pft_addr == blk_b + 40'd8);
      check("TC10d: carry cleared", pred2[0].carry == 1'b0);
    end
    tc_close("TC10");

    // ==============================================================
    // TC11 -- both update channels writing one entry in one cycle
    // ==============================================================
    tc_open("TC11 dual-channel single-entry update");
    begin
      // (a) fresh allocate: channel 0 fills br0, channel 1 fills br1.
      do_reset();
      blk_a = mk_pc(31, TAG_BASE);
      tgt_a = blk_a + 40'd64;
      tgt_b = blk_a - 40'd256;
      upd2[0] = mk_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1,
                        blk_a + 40'd32);
      upd2[1] = mk_cond(blk_a, 1'b1, 1'b0, tgt_b, 4'd4,
                        blk_a + 40'd32);
      commit();
      look2(blk_a);

      check("TC11a: hit",       blk2.hit == 1'b1);
      check("TC11a: s0 valid",  pred2[0].valid  == 1'b1);
      check("TC11a: s0 target", pred2[0].target == tgt_a);
      check("TC11a: s0 pos",    pred2[0].pos    == 4'd1);
      check("TC11a: s0 conf",   pred2[0].conf   == UBTB_CONF_INIT_TKN);
      check("TC11a: s1 valid",  pred2[1].valid  == 1'b1);
      check("TC11a: s1 target", pred2[1].target == tgt_b);
      check("TC11a: s1 pos",    pred2[1].pos    == 4'd4);
      check("TC11a: s1 conf",   pred2[1].conf   == UBTB_CONF_INIT_NTK);

      // Both channels landed on ONE way, not two. Fill the remaining
      // UBTB_WAYS-1 ways with distinct tags; if the dual-channel
      // allocate had burned two ways the original would now be gone.
      for (int i = 1; i < UBTB_WAYS; i++) begin
        blk_b = mk_pc(31, TAG_BASE + i);
        check($sformatf("TC11a: filler %0d shares the set", i),
              pc_idx(blk_b) == pc_idx(blk_a));
        check($sformatf("TC11a: filler %0d has its own tag", i),
              pc_tag(blk_b) != pc_tag(blk_a));
        wr_cond(blk_b, 1'b0, 1'b1, blk_b + 40'd32, 4'd0,
                blk_b + 40'd32);
      end
      look2(blk_a);
      check("TC11a: one way consumed, entry survives UBTB_WAYS-1 fills",
            blk2.hit == 1'b1);
      check("TC11a: survivor keeps s0 target",
            pred2[0].target == tgt_a);
      check("TC11a: survivor keeps s1 target",
            pred2[1].target == tgt_b);

      // (b) existing entry: channel 0 trains br0, channel 1 writes
      //     the jump field, in the same cycle.
      do_reset();
      blk_a = mk_pc(33, TAG_BASE);
      tgt_a = blk_a + 40'd32;
      tgt_b = blk_a + 40'h1000;
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd2, blk_a + 40'd32);
      look2(blk_a);
      check("TC11b: seeded conf",
            pred2[0].conf == UBTB_CONF_INIT_TKN);

      upd2[0] = mk_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd5,
                        blk_a + 40'd32);
      upd2[1] = mk_jmp (blk_a, 1'b1, 1'b0, 1'b0, tgt_b, 4'd7,
                        blk_a + 40'd32);
      commit();
      look2(blk_a);

      check("TC11b: hit",         blk2.hit == 1'b1);
      check("TC11b: s0 is COND",  pred2[0].br_type == COND);
      check("TC11b: s0 conf stepped",
            pred2[0].conf == gold_step(UBTB_CONF_INIT_TKN, 1'b1));
      check("TC11b: s0 pos held", pred2[0].pos == 4'd2);
      check("TC11b: s1 carries the jump",
            pred2[1].valid == 1'b1);
      check("TC11b: s1 jump type",
            pred2[1].br_type == DIRECT_CALL);
      check("TC11b: s1 jump target", pred2[1].target == tgt_b);
      check("TC11b: s1 jump pos",    pred2[1].pos    == 4'd7);
    end
    tc_close("TC11");

    // ==============================================================
    // TC12 -- NUM_PRED_SLOTS=1 reports br0 only
    // ==============================================================
    tc_open("TC12 NUM_PRED_SLOTS=1");
    begin
      do_reset();
      blk_a = mk_pc(35, TAG_BASE);
      tgt_a = blk_a + 40'd64;
      tgt_b = blk_a - 40'd64;

      // Both conditional fields written through the single channel.
      upd1[0] = mk_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1,
                        blk_a + 40'd32);
      commit();
      upd1[0] = mk_cond(blk_a, 1'b1, 1'b0, tgt_b, 4'd5,
                        blk_a + 40'd32);
      commit();
      look1(blk_a);

      check("TC12a: hit",       blk1.hit == 1'b1);
      check("TC12a: pft_addr",  blk1.pft_addr == blk_a + 40'd32);
      check("TC12a: slot valid",  pred1[0].valid   == 1'b1);
      check("TC12a: slot is br0", pred1[0].target  == tgt_a);
      check("TC12a: slot pos",    pred1[0].pos     == 4'd1);
      check("TC12a: slot COND",   pred1[0].br_type == COND);
      check("TC12a: slot conf",
            pred1[0].conf == UBTB_CONF_INIT_TKN);

      // br0 free -> the single slot carries the jump.
      do_reset();
      blk_a = mk_pc(36, TAG_BASE);
      tgt_b = blk_a + 40'h400;
      upd1[0] = mk_jmp(blk_a, 1'b0, 1'b1, 1'b1, tgt_b, 4'd6,
                       blk_a + 40'd32);
      commit();
      look1(blk_a);

      check("TC12b: hit",         blk1.hit == 1'b1);
      check("TC12b: slot valid",  pred1[0].valid   == 1'b1);
      check("TC12b: slot RETURN", pred1[0].br_type == RETURN);
      check("TC12b: slot target", pred1[0].target  == tgt_b);
      check("TC12b: slot pos",    pred1[0].pos     == 4'd6);

      // Miss behaviour at one slot.
      look1(mk_pc(37, TAG_BASE));
      check("TC12c: miss hit=0", blk1.hit == 1'b0);
      check("TC12c: miss slot zero", pred1[0] == '0);
    end
    tc_close("TC12");

    // ==============================================================
    // TC13 -- two distinct tags coexist in one set
    // ==============================================================
    tc_open("TC13 tag coexistence in one set");
    begin
      do_reset();
      blk_a = mk_pc(41, TAG_BASE);
      blk_b = mk_pc(41, TAG_BASE + 1);
      tgt_a = blk_a + 40'd64;
      tgt_b = blk_b - 40'd64;

      check("TC13: same set", pc_idx(blk_a) == pc_idx(blk_b));
      check("TC13: different tag", pc_tag(blk_a) != pc_tag(blk_b));

      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1, blk_a + 40'd32);
      wr_cond(blk_b, 1'b0, 1'b1, tgt_b, 4'd2, blk_b + 40'd32);

      look2(blk_a);
      check("TC13: a hits",      blk2.hit == 1'b1);
      check("TC13: a target",    pred2[0].target == tgt_a);
      check("TC13: a pos",       pred2[0].pos    == 4'd1);
      look2(blk_b);
      check("TC13: b hits",      blk2.hit == 1'b1);
      check("TC13: b target",    pred2[0].target == tgt_b);
      check("TC13: b pos",       pred2[0].pos    == 4'd2);
    end
    tc_close("TC13");

    // ==============================================================
    // TC14 -- round-robin replacement across UBTB_WAYS
    // ==============================================================
    tc_open("TC14 round-robin replacement");
    begin
      logic [VA_WIDTH-1:0] pcs [UBTB_WAYS+1];
      logic [VA_WIDTH-1:0] tgs [UBTB_WAYS+1];
      do_reset();

      for (int i = 0; i <= UBTB_WAYS; i++) begin
        pcs[i] = mk_pc(45, TAG_BASE + i);
        tgs[i] = pcs[i] + 40'd64;
        if (i > 0) begin
          check($sformatf("TC14: pc %0d shares the set", i),
                pc_idx(pcs[i]) == pc_idx(pcs[0]));
          check($sformatf("TC14: pc %0d has its own tag", i),
                pc_tag(pcs[i]) != pc_tag(pcs[0]));
        end
      end

      // Fill all UBTB_WAYS ways.
      for (int i = 0; i < UBTB_WAYS; i++) begin
        wr_cond(pcs[i], 1'b0, 1'b1, tgs[i], 4'd1, pcs[i] + 40'd32);
      end
      for (int i = 0; i < UBTB_WAYS; i++) begin
        look2(pcs[i]);
        check($sformatf("TC14: way %0d present before evict", i),
              blk2.hit == 1'b1 && pred2[0].target == tgs[i]);
      end

      // One more distinct tag evicts the round-robin victim, way 0.
      wr_cond(pcs[UBTB_WAYS], 1'b0, 1'b1, tgs[UBTB_WAYS], 4'd1,
              pcs[UBTB_WAYS] + 40'd32);

      look2(pcs[0]);
      check("TC14: oldest evicted", blk2.hit == 1'b0);
      look2(pcs[UBTB_WAYS]);
      check("TC14: newest present",
            blk2.hit == 1'b1
            && pred2[0].target == tgs[UBTB_WAYS]);
      for (int i = 1; i < UBTB_WAYS; i++) begin
        look2(pcs[i]);
        check($sformatf("TC14: way %0d untouched by evict", i),
              blk2.hit == 1'b1 && pred2[0].target == tgs[i]);
      end
    end
    tc_close("TC14");

    // ==============================================================
    // TC15 -- read-during-write: prediction sees the pre-update state
    // ==============================================================
    tc_open("TC15 read-during-write");
    begin
      do_reset();
      blk_a = mk_pc(49, TAG_BASE);
      tgt_a = blk_a + 40'd96;

      // Present the lookup and the update in the same cycle. Before
      // the edge the array still holds the pre-update contents.
      pred_pc2 = blk_a;
      upd2[0]  = mk_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1,
                         blk_a + 40'd32);
      #1;
      check("TC15: no same-cycle bypass", blk2.hit == 1'b0);
      check("TC15: slot0 still zero",     pred2[0] == '0);

      commit();   // edge commits the write
      check("TC15: visible on the next cycle", blk2.hit == 1'b1);
      check("TC15: target visible", pred2[0].target == tgt_a);
    end
    tc_close("TC15");

    // ==============================================================
    // Verdict
    // ==============================================================
    $display("=================================================");
    $display("tb_ubtb: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    $display("=================================================");
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ubtb: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  // Watchdog
  initial begin
    #500000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "tb_ubtb: timeout");
  end

endmodule : tb
