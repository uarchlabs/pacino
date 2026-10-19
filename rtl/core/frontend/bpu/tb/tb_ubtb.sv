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
// fall-through with no carry bit (TD#124, BP-110). Since BP-140 the
// entry is the block from ONE start PC (the start offset is in the
// tag and folded into the index), positions and the end are stored
// start-relative in ascending position, and an entry holds at most
// N_SLOTS branches: an update that would make it hold more keeps the
// lowest positions and ends the block at the first one not kept (the
// split). The jump is reported in the lowest slot carrying no
// conditional field. A conditional's update end is the predicted end
// of its block and is not written; an end comes from a jump or the
// split.
//
// BP-110 deleted ubtb_pred_t.carry. Each check that read it now
// checks the same boundary fact on blk_p1.pft_addr, one for one.
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
// TC06 jump field reported in a slot, all six jump types (BP-119)
// TC07 jump placed in the lowest slot with no conditional field
// TC08 conf trained to both saturation points; position held
// TC09 target reconstruction, conditional and jump displacements
// TC10 fall-through reconstruction, both sides of the boundary
// TC11 both update channels writing one entry in the same cycle
// TC12 NUM_PRED_SLOTS=1 reports br0 only
// TC13 two distinct tags coexisting in one set
// TC14 round-robin replacement across UBTB_WAYS
// TC15 read-during-write: prediction sees the pre-update state
// TC16 TD#124: a block end 64 bytes above the region base
// TC17 BP-140: two starts in one region keep separate entries
// TC18 TD#156: the same branch is the same position (BP-120)
// TC19 BP-140: the split at update, both slot counts, every order
// TC20 BP-140: starts of one region in different sets
// TC21 BP-140: two channels splitting one entry in one cycle
// ===================================================================

import bp_defines_pkg::*;
import bp_structs_pkg::*;
module tb;

  // ----------------------------------------------------------------
  // DUT: N_SLOTS=2 (primary). tb_ubtb builds one uBTB at each slot
  // count whatever the package NUM_PRED_SLOTS is (BP-128): the module
  // takes its slot count as a parameter, so both are tested in every
  // build.
  // ----------------------------------------------------------------
  logic                clk;
  logic                rstn;

  logic [VA_WIDTH-1:0] pred_pc2;
  ubtb_pred_t [1:0]    pred2;
  ubtb_blk_t           blk2;
  ubtb_upd_t  [1:0]    upd2;

  ubtb #(.N_SLOTS(2)) dut2 (
    .clk        (clk),
    .rstn       (rstn),
    .pred_pc_p0 (pred_pc2),
    .pred_p1    (pred2),
    .blk_p1     (blk2),
    .upd_u0     (upd2)
  );

  // ----------------------------------------------------------------
  // DUT: N_SLOTS=1 (TC12)
  // ----------------------------------------------------------------
  logic [VA_WIDTH-1:0] pred_pc1;
  ubtb_pred_t [0:0]    pred1;
  ubtb_blk_t           blk1;
  ubtb_upd_t  [0:0]    upd1;

  ubtb #(.N_SLOTS(1)) dut1 (
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
  // (ubtb_interfaces.md, Lookup; BP-140): index pc[10:5] XOR (pc[4:1]
  // << 2), tag {pc[30:11], pc[4:1]}.
  function automatic logic [UBTB_IDX_BITS-1:0] pc_idx(
      input logic [VA_WIDTH-1:0] pc);
    logic [UBTB_IDX_BITS-1:0] off;
    off    = UBTB_IDX_BITS'(pc[UBTB_OFFSET_BITS-1:1]);
    pc_idx = pc[UBTB_OFFSET_BITS +: UBTB_IDX_BITS]
           ^ (off << (UBTB_IDX_BITS - UBTB_BR_POS_BITS));
  endfunction

  function automatic logic [UBTB_TAG_BITS-1:0] pc_tag(
      input logic [VA_WIDTH-1:0] pc);
    pc_tag = {pc[UBTB_OFFSET_BITS+UBTB_IDX_BITS +: UBTB_TAG_BITS
                 - UBTB_BR_POS_BITS],
              pc[UBTB_OFFSET_BITS-1:1]};
  endfunction

  // The PC of in-block position pos of the block starting at start.
  function automatic logic [VA_WIDTH-1:0] pos_pc(
      input logic [VA_WIDTH-1:0]         start,
      input logic [UBTB_BR_POS_BITS-1:0] pos);
    pos_pc = start + (VA_WIDTH'(pos) << UBTB_POS_OFFSET_BITS);
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
      tgt_a = blk_a + VA_WIDTH'('d64);    // forward, in 13-bit reach
      tgt_b = blk_a - VA_WIDTH'('d128);   // backward, in 13-bit reach
      // br0: taken at position 1. br1: not-taken at position 5.
      // Block ends at the next block start.
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1, blk_a + VA_WIDTH'('d32));
      wr_cond(blk_a, 1'b1, 1'b0, tgt_b, 4'd5, blk_a + VA_WIDTH'('d32));
      look2(blk_a);

      check("TC02: hit",       blk2.hit == 1'b1);
      check("TC02: pft_addr",  blk2.pft_addr == blk_a + VA_WIDTH'('d32));

      check("TC02: s0 valid",  pred2[0].valid    == 1'b1);
      check("TC02: s0 COND",   pred2[0].br_type  == COND);
      check("TC02: s0 target", pred2[0].target   == tgt_a);
      check("TC02: s0 pos",    pred2[0].pos      == 4'd1);
      check("TC02: s0 conf",   pred2[0].conf     == UBTB_CONF_INIT_TKN);
      check("TC02: s0 taken",  pred2[0].br_taken == 1'b1);
      check("TC02: end crosses the block boundary",
            pc_base(blk2.pft_addr) != blk_a);

      check("TC02: s1 valid",  pred2[1].valid    == 1'b1);
      check("TC02: s1 COND",   pred2[1].br_type  == COND);
      check("TC02: s1 target", pred2[1].target   == tgt_b);
      check("TC02: s1 pos",    pred2[1].pos      == 4'd5);
      check("TC02: s1 conf",   pred2[1].conf     == UBTB_CONF_INIT_NTK);
      check("TC02: s1 taken",  pred2[1].br_taken == 1'b0);
      check("TC02: end is one block above the base, no carry term",
            blk2.pft_addr - blk_a == VA_WIDTH'(UBTB_BLOCK_BYTES));

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
      tgt_a = blk_a + VA_WIDTH'('d16);
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd2, blk_a + VA_WIDTH'('d12));
      look2(blk_a);

      // BP-140: a conditional's update end (+12, its block's predicted
      // end) is not written; the end is one block above the start.
      // OLD: "pft_addr" == blk_a + 12 and "end stays in the block".
      check("TC03: hit",       blk2.hit == 1'b1);
      check("TC03: pft_addr is start + 32, not the update's +12",
            blk2.pft_addr == blk_a + VA_WIDTH'(UBTB_BLOCK_BYTES));
      check("TC03: s0 valid",  pred2[0].valid  == 1'b1);
      check("TC03: s0 target", pred2[0].target == tgt_a);
      check("TC03: s0 pos",    pred2[0].pos    == 4'd2);
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
      upd2[0] = mk_blk(blk_a, blk_a + VA_WIDTH'('d20));
      commit();
      look2(blk_a);

      // BP-140: no branch, so the end is one block above the start, not
      // the +20 the update carries. OLD: "pft_addr" == blk_a + 20.
      check("TC04: hit",      blk2.hit == 1'b1);
      check("TC04: pft_addr", blk2.pft_addr
                              == blk_a + VA_WIDTH'(UBTB_BLOCK_BYTES));
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

      wr_cond(blk_a, 1'b0, 1'b1, blk_a + VA_WIDTH'('d32), 4'd0,
              blk_a + VA_WIDTH'('d32));

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
    // TC06 -- jump field reported in a slot, all six jump types.
    // [5] is RETURN_CALL, call+ret+jalr (ubtb_interfaces.md br_type,
    // TD#152, BP-119): before BP-119 jmp_br_type tested is_ret first
    // and reported it RETURN.
    // ==============================================================
    tc_open("TC06 jump types");
    begin
      // {is_call, is_ret, is_jalr} -> expected bp_br_type_e
      bp_br_type_e exp_ty [6];
      logic [2:0]  ty_bits[6];
      ty_bits[0] = 3'b100; exp_ty[0] = DIRECT_CALL;     // call
      ty_bits[1] = 3'b101; exp_ty[1] = INDIRECT_CALL;   // call+jalr
      ty_bits[2] = 3'b011; exp_ty[2] = RETURN;          // ret+jalr
      ty_bits[3] = 3'b001; exp_ty[3] = INDIRECT_NONRET; // jalr
      ty_bits[4] = 3'b000; exp_ty[4] = DIRECT_UNC;      // direct jmp
      ty_bits[5] = 3'b111; exp_ty[5] = RETURN_CALL;     // call+ret+jalr

      for (int i = 0; i < 6; i++) begin
        do_reset();
        blk_a = mk_pc(11, TAG_BASE);
        tgt_a = blk_a + VA_WIDTH'('h400);
        wr_jmp(blk_a, ty_bits[i][2], ty_bits[i][1], ty_bits[i][0],
               tgt_a, 4'd7, blk_a + VA_WIDTH'('d32));
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
      tgt_a = blk_a + VA_WIDTH'('d32);
      tgt_b = blk_a + VA_WIDTH'('h800);
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd0, blk_a + VA_WIDTH'('d32));
      wr_jmp (blk_a, 1'b0, 1'b1, 1'b1, tgt_b, 4'd6, blk_a + VA_WIDTH'('d32));
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
      tgt_a = blk_a + VA_WIDTH'('d32);
      tgt_b = blk_a - VA_WIDTH'('d64);
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd0, blk_a + VA_WIDTH'('d32));
      wr_cond(blk_a, 1'b1, 1'b1, tgt_b, 4'd3, blk_a + VA_WIDTH'('d32));
      wr_jmp (blk_a, 1'b1, 1'b0, 1'b0, blk_a + VA_WIDTH'('h800), 4'd7,
              blk_a + VA_WIDTH'('d32));
      look2(blk_a);

      check("TC07b: hit",        blk2.hit == 1'b1);
      check("TC07b: s0 is COND", pred2[0].br_type == COND);
      check("TC07b: s1 is COND", pred2[1].br_type == COND);
      check("TC07b: s0 target",  pred2[0].target  == tgt_a);
      check("TC07b: s1 target",  pred2[1].target  == tgt_b);
      // BP-140: the jump is the third branch; it is split off and the
      // block ends at its PC.
      check("TC07b: the block ends at the jump PC",
            blk2.pft_addr == pos_pc(blk_a, 4'd7));
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
      tgt_a = blk_a + VA_WIDTH'('d48);

      // Fill br0 taken at position 3. conf starts at the weak taken
      // init, which must be unsaturated with MSB 1.
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd3, blk_a + VA_WIDTH'('d32));
      look2(blk_a);
      gold = UBTB_CONF_INIT_TKN;
      check("TC08: fill conf is weak taken", pred2[0].conf == gold);
      check("TC08: init unsaturated",
            gold != {UBTB_CONF_WIDTH{1'b1}});
      check("TC08: fill pos", pred2[0].pos == 4'd3);

      // Train taken past the top. Each update is the SAME branch,
      // position 3, so the stored position stays put while conf steps.
      // OLD stimulus (until BP-120): each update carried a DIFFERENT
      // position, 4'd6, and the field kept 3. A different position is
      // now a different branch that refills the field (ftb_decisions.md
      // 5.5, TD#156; TC18). The expected values are unchanged.
      for (int i = 0; i < 6; i++) begin
        wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd3, blk_a + VA_WIDTH'('d32));
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
      // Same branch, position 3 (OLD stimulus 4'd6, as above).
      for (int i = 0; i < 10; i++) begin
        wr_cond(blk_a, 1'b0, 1'b0, tgt_a, 4'd3, blk_a + VA_WIDTH'('d32));
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
      wr_cond(blk_a, 1'b0, 1'b0, tgt_a, 4'd2, blk_a + VA_WIDTH'('d32));
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
      cd[0] =  VA_WIDTH'('sd0);
      cd[1] =  VA_WIDTH'('sd4);
      cd[2] = -VA_WIDTH'('sd4);
      cd[3] =  VA_WIDTH'('sd4092);
      cd[4] = -VA_WIDTH'('sd4096);

      for (int i = 0; i < 5; i++) begin
        do_reset();
        blk_a = mk_pc(21, TAG_BASE);
        tgt_a = blk_a + VA_WIDTH'(cd[i]);
        wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1, blk_a + VA_WIDTH'('d32));
        look2(blk_a);
        check($sformatf("TC09: cond disp %0d valid", i),
              pred2[0].valid == 1'b1);
        check($sformatf("TC09: cond disp %0d reconstructs", i),
              pred2[0].target == tgt_a);
      end

      // Jump displacements, inside the 21-bit signed reach
      // (-1048576 .. +1048575).
      jd[0] =  VA_WIDTH'('sd256);
      jd[1] = -VA_WIDTH'('sd256);
      jd[2] =  VA_WIDTH'('sd1048572);
      jd[3] = -VA_WIDTH'('sd1048576);

      for (int i = 0; i < 4; i++) begin
        do_reset();
        blk_a = mk_pc(22, TAG_BASE);
        tgt_a = blk_a + VA_WIDTH'(jd[i]);
        wr_jmp(blk_a, 1'b0, 1'b0, 1'b0, tgt_a, 4'd4,
               blk_a + VA_WIDTH'('d32));
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
      tgt_a = blk_a + VA_WIDTH'('d64);
      tgt_b = blk_a - VA_WIDTH'('d2048);
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1, blk_a + VA_WIDTH'('d32));
      look2(blk_a);
      check("TC09: first target", pred2[0].target == tgt_a);
      wr_cond(blk_a, 1'b0, 1'b1, tgt_b, 4'd1, blk_a + VA_WIDTH'('d32));
      look2(blk_a);
      check("TC09: moved target rewritten",
            pred2[0].target == tgt_b);
    end
    tc_close("TC09");

    // ==============================================================
    // TC10 -- fall-through reconstruction, both sides of the block
    //         boundary
    // ==============================================================
    tc_open("TC10 fall-through across the boundary");
    begin
      do_reset();
      blk_a = mk_pc(25, TAG_BASE);   // ends inside its own block
      blk_b = mk_pc(26, TAG_BASE);   // ends at the next block start
      blk_c = mk_pc(27, TAG_BASE);   // ends past the boundary

      check("TC10: three distinct sets",
            (pc_idx(blk_a) != pc_idx(blk_b))
            && (pc_idx(blk_b) != pc_idx(blk_c)));

      // Since BP-140 an end comes from a jump (its resolved end) or the
      // split; a conditional's update end is not written (TC03). The
      // three ends below are jumps' ends.
      // OLD (until BP-140): conditionals at pos 6, 7 and 2 carrying the
      // ends +28, +32 and +40, and (TC10d) a later +8 rewriting +32.
      // end is 28 bytes into the block: a 32-bit jump at pos 12.
      wr_jmp(blk_a, 1'b0, 1'b0, 1'b0, blk_a + VA_WIDTH'('d64), 4'd12,
             blk_a + VA_WIDTH'('d28));
      // end is exactly the next block start: a 32-bit jump at pos 14.
      // The partial pftAddr reaches it on its own; there is no carry.
      wr_jmp(blk_b, 1'b0, 1'b0, 1'b0, blk_b + VA_WIDTH'('d64), 4'd14,
             blk_b + VA_WIDTH'('d32));
      // end past the boundary: a 32-bit jump at pos 15, straddling.
      wr_jmp(blk_c, 1'b0, 1'b0, 1'b0, blk_c + VA_WIDTH'('d64), 4'd15,
             blk_c + VA_WIDTH'('d34));

      look2(blk_a);
      check("TC10a: hit",       blk2.hit == 1'b1);
      check("TC10a: pft_addr",  blk2.pft_addr == blk_a + VA_WIDTH'('d28));
      check("TC10a: end below the block boundary",
            blk2.pft_addr - blk_a < VA_WIDTH'(UBTB_BLOCK_BYTES));
      check("TC10a: end stays in block",
            pc_base(blk2.pft_addr) == blk_a);

      look2(blk_b);
      check("TC10b: hit",       blk2.hit == 1'b1);
      check("TC10b: pft_addr",  blk2.pft_addr == blk_b + VA_WIDTH'('d32));
      check("TC10b: end at or past the block boundary",
            blk2.pft_addr - blk_b >= VA_WIDTH'(UBTB_BLOCK_BYTES));
      check("TC10b: end is the next block base",
            pc_base(blk2.pft_addr) == blk_b + VA_WIDTH'('d32));

      look2(blk_c);
      check("TC10c: hit",       blk2.hit == 1'b1);
      check("TC10c: pft_addr",  blk2.pft_addr == blk_c + VA_WIDTH'('d34));
      check("TC10c: end at or past the block boundary",
            blk2.pft_addr - blk_c >= VA_WIDTH'(UBTB_BLOCK_BYTES));

      // The block boundary moves down when a jump before the stored one
      // resolves (an earlier first jump of the block).
      wr_jmp(blk_b, 1'b0, 1'b0, 1'b0, blk_b + VA_WIDTH'('d64), 4'd2,
             blk_b + VA_WIDTH'('d8));
      look2(blk_b);
      check("TC10d: boundary moved back into the block",
            blk2.pft_addr == blk_b + VA_WIDTH'('d8));
      check("TC10d: end back below the block boundary",
            blk2.pft_addr - blk_b < VA_WIDTH'(UBTB_BLOCK_BYTES));
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
      tgt_a = blk_a + VA_WIDTH'('d64);
      tgt_b = blk_a - VA_WIDTH'('d256);
      upd2[0] = mk_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1,
                        blk_a + VA_WIDTH'('d32));
      upd2[1] = mk_cond(blk_a, 1'b1, 1'b0, tgt_b, 4'd4,
                        blk_a + VA_WIDTH'('d32));
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
        wr_cond(blk_b, 1'b0, 1'b1, blk_b + VA_WIDTH'('d32), 4'd0,
                blk_b + VA_WIDTH'('d32));
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
      tgt_a = blk_a + VA_WIDTH'('d32);
      tgt_b = blk_a + VA_WIDTH'('h1000);
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd2, blk_a + VA_WIDTH'('d32));
      look2(blk_a);
      check("TC11b: seeded conf",
            pred2[0].conf == UBTB_CONF_INIT_TKN);

      // Channel 0 is the same branch, position 2. OLD stimulus (until
      // BP-120): position 4'd5, which the field ignored; a different
      // position is now a different branch (TD#156, TC18). The
      // expected values are unchanged.
      upd2[0] = mk_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd2,
                        blk_a + VA_WIDTH'('d32));
      upd2[1] = mk_jmp (blk_a, 1'b1, 1'b0, 1'b0, tgt_b, 4'd7,
                        blk_a + VA_WIDTH'('d32));
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
      tgt_a = blk_a + VA_WIDTH'('d64);
      tgt_b = blk_a - VA_WIDTH'('d64);

      // Both conditional fields written through the single channel.
      upd1[0] = mk_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1,
                        blk_a + VA_WIDTH'('d32));
      commit();
      upd1[0] = mk_cond(blk_a, 1'b1, 1'b0, tgt_b, 4'd5,
                        blk_a + VA_WIDTH'('d32));
      commit();
      look1(blk_a);

      // BP-140: one slot holds one branch. The pos 5 branch is split
      // off and the block ends at its PC. OLD: pft_addr blk_a + 32 (both
      // fields stored, br1 not reported).
      check("TC12a: hit",       blk1.hit == 1'b1);
      check("TC12a: pft_addr is the pos 5 branch PC",
            blk1.pft_addr == pos_pc(blk_a, 4'd5));
      check("TC12a: slot valid",  pred1[0].valid   == 1'b1);
      check("TC12a: slot is br0", pred1[0].target  == tgt_a);
      check("TC12a: slot pos",    pred1[0].pos     == 4'd1);
      check("TC12a: slot COND",   pred1[0].br_type == COND);
      check("TC12a: slot conf",
            pred1[0].conf == UBTB_CONF_INIT_TKN);

      // br0 free -> the single slot carries the jump.
      do_reset();
      blk_a = mk_pc(36, TAG_BASE);
      tgt_b = blk_a + VA_WIDTH'('h400);
      upd1[0] = mk_jmp(blk_a, 1'b0, 1'b1, 1'b1, tgt_b, 4'd6,
                       blk_a + VA_WIDTH'('d32));
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
      tgt_a = blk_a + VA_WIDTH'('d64);
      tgt_b = blk_b - VA_WIDTH'('d64);

      check("TC13: same set", pc_idx(blk_a) == pc_idx(blk_b));
      check("TC13: different tag", pc_tag(blk_a) != pc_tag(blk_b));

      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1, blk_a + VA_WIDTH'('d32));
      wr_cond(blk_b, 1'b0, 1'b1, tgt_b, 4'd2, blk_b + VA_WIDTH'('d32));

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
        tgs[i] = pcs[i] + VA_WIDTH'('d64);
        if (i > 0) begin
          check($sformatf("TC14: pc %0d shares the set", i),
                pc_idx(pcs[i]) == pc_idx(pcs[0]));
          check($sformatf("TC14: pc %0d has its own tag", i),
                pc_tag(pcs[i]) != pc_tag(pcs[0]));
        end
      end

      // Fill all UBTB_WAYS ways.
      for (int i = 0; i < UBTB_WAYS; i++) begin
        wr_cond(pcs[i], 1'b0, 1'b1, tgs[i], 4'd1, pcs[i] + VA_WIDTH'('d32));
      end
      for (int i = 0; i < UBTB_WAYS; i++) begin
        look2(pcs[i]);
        check($sformatf("TC14: way %0d present before evict", i),
              blk2.hit == 1'b1 && pred2[0].target == tgs[i]);
      end

      // One more distinct tag evicts the round-robin victim, way 0.
      wr_cond(pcs[UBTB_WAYS], 1'b0, 1'b1, tgs[UBTB_WAYS], 4'd1,
              pcs[UBTB_WAYS] + VA_WIDTH'('d32));

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
      tgt_a = blk_a + VA_WIDTH'('d96);

      // Present the lookup and the update in the same cycle. Before
      // the edge the array still holds the pre-update contents.
      pred_pc2 = blk_a;
      upd2[0]  = mk_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd1,
                         blk_a + VA_WIDTH'('d32));
      #1;
      check("TC15: no same-cycle bypass", blk2.hit == 1'b0);
      check("TC15: slot0 still zero",     pred2[0] == '0);

      commit();   // edge commits the write
      check("TC15: visible on the next cycle", blk2.hit == 1'b1);
      check("TC15: target visible", pred2[0].target == tgt_a);
    end
    tc_close("TC15");

    // ==============================================================
    // TC16 -- TD#124. A block starting at region offset 30 whose 32-bit
    //         jump at pos 15 straddles the next block ends 64 bytes
    //         above the region base, start + 34. The end must
    //         reconstruct exactly; as built before TD#124 it read back
    //         as base+32.
    //         OLD (until BP-140): a conditional at pos 3 carrying the
    //         end; a conditional's update end is no longer written.
    // ==============================================================
    tc_open("TC16 TD#124 end at region offset 64");
    begin
      do_reset();
      blk_a = mk_pc(51, TAG_BASE);                // region base
      blk_b = blk_a + VA_WIDTH'('d30);            // block start
      tgt_a = blk_b + VA_WIDTH'('d64);
      wr_jmp(blk_b, 1'b0, 1'b0, 1'b0, tgt_a, 4'd15, blk_a + VA_WIDTH'('d64));
      look2(blk_b);
      $display("TC16 pft got %h exp %h", blk2.pft_addr,
               blk_a + VA_WIDTH'('d64));

      check("TC16: hit",        blk2.hit == 1'b1);
      check("TC16: end at region offset 64",
            blk2.pft_addr == blk_a + VA_WIDTH'('d64));
      check("TC16: s0 pos start-relative", pred2[0].pos == 4'd15);
      check("TC16: s0 target",  pred2[0].target == tgt_a);
    end
    tc_close("TC16");

    // ==============================================================
    // TC17 -- BP-140, Problem 1. Two starts in one region keep separate
    //         entries (one entry per start PC, ruled by Jeff
    //         2026-10-18). A at region offset 0 records a conditional at
    //         pos 2; B at offset 10 misses until it writes, then holds
    //         only its own jump, and A's fields, end and hit are
    //         unchanged by B's updates (and B's by A's). Fails on the
    //         starting tree, where the two share one entry.
    //         OLD (TD#125, BP-110 to BP-140): the shared entry; B's fill
    //         replaced the field A's branch held and A then saw B's
    //         branch at region position 8.
    // ==============================================================
    tc_open("TC17 BP-140 separate entries, two starts");
    begin
      do_reset();
      blk_a = mk_pc(53, TAG_BASE);                // start A, offset 0
      blk_b = blk_a + VA_WIDTH'('d10);            // start B, offset 10
      tgt_a = blk_a + VA_WIDTH'('h100);
      tgt_b = blk_a + VA_WIDTH'('h300);

      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd2, blk_a + VA_WIDTH'('d32));
      look2(blk_b);
      check("TC17: B misses before it writes", blk2.hit == 1'b0);

      // B's jump, start-relative pos 3 (jump PC blk_a+16), end +20.
      wr_jmp(blk_b, 1'b1, 1'b0, 1'b0, tgt_b, 4'd3, blk_a + VA_WIDTH'('d20));
      look2(blk_b);
      check("TC17: B hits",      blk2.hit == 1'b1);
      check("TC17: B s0 is its jump, pos 3, its target",
            pred2[0].valid && (pred2[0].br_type == DIRECT_CALL)
            && (pred2[0].pos == 4'd3) && (pred2[0].target == tgt_b));
      check("TC17: B s1 empty",  pred2[1].valid  == 1'b0);
      check("TC17: B end is its jump's end",
            blk2.pft_addr == blk_a + VA_WIDTH'('d20));

      look2(blk_a);
      check("TC17: A hits",      blk2.hit == 1'b1);
      check("TC17: A s0 is A's branch, pos 2, weak taken",
            pred2[0].valid && (pred2[0].br_type == COND)
            && (pred2[0].pos == 4'd2) && (pred2[0].target == tgt_a)
            && (pred2[0].conf == UBTB_CONF_INIT_TKN));
      check("TC17: A s1 empty (no jump of B's)", pred2[1].valid == 1'b0);
      check("TC17: A end unchanged",
            blk2.pft_addr == blk_a + VA_WIDTH'(UBTB_BLOCK_BYTES));

      // A trains; B is unchanged.
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd2, blk_a + VA_WIDTH'('d32));
      look2(blk_b);
      check("TC17: after A trains, B unchanged",
            blk2.hit && pred2[0].valid && (pred2[0].pos == 4'd3)
            && (pred2[0].br_type == DIRECT_CALL)
            && (blk2.pft_addr == blk_a + VA_WIDTH'('d20)));
      look2(blk_a);
      check("TC17: A conf stepped",
            pred2[0].conf == gold_step(UBTB_CONF_INIT_TKN, 1'b1));
    end
    tc_close("TC17");

    // ==============================================================
    // TC18 -- TD#156 (ubtb_interfaces.md Allocation and field writes,
    //         ftb_decisions.md 5.5, ruled session-075). A filled field
    //         keeps its position only for an update at the stored
    //         position; since BP-140 storage is in position order, so
    //         the position names the field, not br_idx.
    // ==============================================================
    tc_open("TC18 TD#156 the same branch is the same position");
    begin
      // a: two jumps of one start. J1 a RETURN_CALL at pos 4, J2 a
      //    RETURN at pos 9 (the coro shape). The block ends at its first
      //    jump, so J2 after J1 is past it and changes nothing; J2 at
      //    pos 2, before J1, replaces it with its type, target and end.
      //    OLD (BP-120 to BP-140): J2 at pos 9 replaced J1 and J1 again
      //    replaced J2 (one shared field per region; in coro the two
      //    jumps are two starts', now two entries, TC17).
      do_reset();
      blk_a = mk_pc(57, TAG_BASE);
      tgt_a = blk_a + VA_WIDTH'('h1200);
      tgt_b = blk_a + VA_WIDTH'('h3400);
      wr_jmp(blk_a, 1'b1, 1'b1, 1'b1, tgt_a, 4'd4, blk_a + VA_WIDTH'('d12));
      look2(blk_a);
      check("TC18a: J1 holds the field: RETURN_CALL at pos 4",
            pred2[0].valid && (pred2[0].br_type == RETURN_CALL)
            && (pred2[0].pos == 4'd4));
      wr_jmp(blk_a, 1'b0, 1'b1, 1'b1, tgt_b, 4'd9, blk_a + VA_WIDTH'('d22));
      look2(blk_a);
      check("TC18a: J2 after J1 is past the block: J1 kept",
            pred2[0].valid && (pred2[0].br_type == RETURN_CALL)
            && (pred2[0].pos == 4'd4) && (pred2[0].target == tgt_a));
      check("TC18a: and the end is J1's",
            blk2.pft_addr == blk_a + VA_WIDTH'('d12));
      wr_jmp(blk_a, 1'b0, 1'b1, 1'b1, tgt_b, 4'd2, blk_a + VA_WIDTH'('d8));
      look2(blk_a);
      check("TC18a: a jump before J1 replaces it: RETURN at pos 2",
            pred2[0].valid && (pred2[0].br_type == RETURN)
            && (pred2[0].pos == 4'd2) && (pred2[0].target == tgt_b));
      check("TC18a: the block end is the new jump's",
            blk2.pft_addr == blk_a + VA_WIDTH'('d8));

      // b: a conditional at a new position with a filled field. br0
      //    holds pos 3, trained taken twice; a branch at pos 9 resolves
      //    not taken, naming br0. It is a new branch: it is stored in
      //    position order beside pos 3 (s1: pos 9, weak not-taken, its
      //    target) and pos 3 keeps its conf.
      //    OLD (BP-120 to BP-140): the field br_idx named was refilled
      //    with pos 9, discarding pos 3. Before BP-120: pos 3 kept,
      //    conf stepped 6 -> 5.
      do_reset();
      blk_a = mk_pc(58, TAG_BASE);
      tgt_a = blk_a + VA_WIDTH'('h100);
      tgt_b = blk_a + VA_WIDTH'('h900);
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd3, blk_a + VA_WIDTH'('d32));
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd3, blk_a + VA_WIDTH'('d32));
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd3, blk_a + VA_WIDTH'('d32));
      look2(blk_a);
      check("TC18b: set-up: br0 pos 3 conf INIT_TKN + 2",
            pred2[0].valid && (pred2[0].pos == 4'd3)
            && (pred2[0].conf == gold_step(gold_step(UBTB_CONF_INIT_TKN,
                                                     1'b1), 1'b1)));
      wr_cond(blk_a, 1'b0, 1'b0, tgt_b, 4'd9, blk_a + VA_WIDTH'('d32));
      look2(blk_a);
      check("TC18b: pos 3 kept in slot 0 with its conf",
            pred2[0].valid && (pred2[0].pos == 4'd3)
            && (pred2[0].conf == gold_step(gold_step(UBTB_CONF_INIT_TKN,
                                                     1'b1), 1'b1)));
      check("TC18b: the new branch's position is written (9) in slot 1",
            pred2[1].valid && (pred2[1].pos == 4'd9));
      check("TC18b: conf weak in the resolved direction",
            pred2[1].conf == UBTB_CONF_INIT_NTK);
      check("TC18b: its target is written", pred2[1].target == tgt_b);

      // c: the same branch resolving again, naming br0 (a stale slot):
      //    the position names the field, so slot 1's conf steps, the
      //    target is rewritten when it differs, the position is kept.
      wr_cond(blk_a, 1'b0, 1'b1, tgt_a, 4'd9, blk_a + VA_WIDTH'('d32));
      look2(blk_a);
      check("TC18c: same branch: conf steps",
            pred2[1].conf == gold_step(UBTB_CONF_INIT_NTK, 1'b1));
      check("TC18c: same branch: target rewritten",
            pred2[1].target == tgt_a);
      check("TC18c: same branch: position kept (9)",
            pred2[1].valid && (pred2[1].pos == 4'd9));
      check("TC18c: and slot 0 is untouched (pos 3)",
            pred2[0].valid && (pred2[0].pos == 4'd3));
    end
    tc_close("TC18");

    // ==============================================================
    // TC19 -- BP-140, Problem 2. THE SPLIT AT UPDATE, both slot counts
    //         (dut1 N_SLOTS 1, dut2 N_SLOTS 2), every resolution order.
    //         An entry never holds more than N_SLOTS branches; the
    //         lowest positions are kept and the end is the PC of the
    //         first one not kept; a jump not kept clears the field.
    //         Each order is reset plus its updates; the entries the
    //         orders leave are compared slot by slot. Fails on the
    //         starting tree, which stores 2 + 1 at both counts and
    //         writes each update's end.
    // ==============================================================
    tc_open("TC19 BP-140 split at update");
    begin
      int                          perm [6][3];
      logic [UBTB_BR_POS_BITS-1:0] cpos [3];
      logic                        cdir [3];
      logic [VA_WIDTH-1:0]         ctgt [3];
      ubtb_pred_t [1:0]            r2;
      ubtb_blk_t                   rb2;
      ubtb_pred_t [0:0]            r1;
      ubtb_blk_t                   rb1;
      perm[0] = '{0, 1, 2}; perm[1] = '{0, 2, 1}; perm[2] = '{1, 0, 2};
      perm[3] = '{1, 2, 0}; perm[4] = '{2, 0, 1}; perm[5] = '{2, 1, 0};
      blk_a   = mk_pc(61, TAG_BASE);
      cpos[0] = 4'd1;  cdir[0] = 1'b1; ctgt[0] = blk_a + VA_WIDTH'('h100);
      cpos[1] = 4'd4;  cdir[1] = 1'b0; ctgt[1] = blk_a + VA_WIDTH'('h200);
      cpos[2] = 4'd11; cdir[2] = 1'b1; ctgt[2] = blk_a + VA_WIDTH'('h300);

      // a: one slot, {a} then b > a, and the reverse: keep a, end PC(b).
      do_reset();
      upd1[0] = mk_cond(blk_a, 1'b0, cdir[0], ctgt[0], cpos[0],
                        blk_a + VA_WIDTH'('d32));
      commit();
      upd1[0] = mk_cond(blk_a, 1'b0, cdir[1], ctgt[1], cpos[1],
                        blk_a + VA_WIDTH'('d32));
      commit();
      look1(blk_a);
      r1 = pred1; rb1 = blk1;
      check("TC19a: one slot keeps a (pos 1), end PC(b)",
            pred1[0].valid && (pred1[0].pos == 4'd1)
            && (blk1.pft_addr == pos_pc(blk_a, 4'd4)));
      do_reset();
      upd1[0] = mk_cond(blk_a, 1'b0, cdir[1], ctgt[1], cpos[1],
                        blk_a + VA_WIDTH'('d32));
      commit();
      upd1[0] = mk_cond(blk_a, 1'b0, cdir[0], ctgt[0], cpos[0],
                        blk_a + VA_WIDTH'('d32));
      commit();
      look1(blk_a);
      check("TC19a: one slot, reverse order: the same entry",
            (pred1 == r1) && (blk1 == rb1));

      // b: one slot, {conditional 1, jump 9} in both orders: keep the
      //    conditional, clear the jump, end at the jump PC.
      do_reset();
      upd1[0] = mk_cond(blk_a, 1'b0, cdir[0], ctgt[0], cpos[0],
                        blk_a + VA_WIDTH'('d32));
      commit();
      upd1[0] = mk_jmp(blk_a, 1'b1, 1'b0, 1'b0, blk_a + VA_WIDTH'('h900),
                       4'd9, pos_pc(blk_a, 4'd9) + VA_WIDTH'('d4));
      commit();
      look1(blk_a);
      r1 = pred1; rb1 = blk1;
      check("TC19b: one slot, cond then jump: the conditional, end PC(j)",
            pred1[0].valid && (pred1[0].br_type == COND)
            && (blk1.pft_addr == pos_pc(blk_a, 4'd9)));
      do_reset();
      upd1[0] = mk_jmp(blk_a, 1'b1, 1'b0, 1'b0, blk_a + VA_WIDTH'('h900),
                       4'd9, pos_pc(blk_a, 4'd9) + VA_WIDTH'('d4));
      commit();
      upd1[0] = mk_cond(blk_a, 1'b0, cdir[0], ctgt[0], cpos[0],
                        blk_a + VA_WIDTH'('d32));
      commit();
      look1(blk_a);
      check("TC19b: one slot, jump then cond: the same entry",
            (pred1 == r1) && (blk1 == rb1));

      // c: two slots, three conditionals, every order: keep pos 1 and
      //    4, end PC(11).
      for (int o = 0; o < 6; o++) begin
        do_reset();
        for (int i = 0; i < 3; i++) begin
          upd2[0] = mk_cond(blk_a, 1'b0, cdir[perm[o][i]], ctgt[perm[o][i]],
                            cpos[perm[o][i]], blk_a + VA_WIDTH'('d32));
          commit();
        end
        look2(blk_a);
        if (o == 0) begin
          r2 = pred2; rb2 = blk2;
          check("TC19c: two slots keep pos 1 (s0) and 4 (s1)",
                pred2[0].valid && (pred2[0].pos == 4'd1)
                && (pred2[0].target == ctgt[0])
                && pred2[1].valid && (pred2[1].pos == 4'd4)
                && (pred2[1].target == ctgt[1]));
          check("TC19c: the end is the PC of pos 11",
                blk2.pft_addr == pos_pc(blk_a, 4'd11));
        end else begin
          check($sformatf("TC19c: order %0d%0d%0d: the same entry",
                          perm[o][0], perm[o][1], perm[o][2]),
                (pred2 == r2) && (blk2 == rb2));
        end
      end

      // d: two slots, {conditional 1, conditional 4, jump 9}, every
      //    order: the end is the jump PC and no slot carries the jump.
      cpos[2] = 4'd9;
      for (int o = 0; o < 6; o++) begin
        do_reset();
        for (int i = 0; i < 3; i++) begin
          if (perm[o][i] == 2)
            upd2[0] = mk_jmp(blk_a, 1'b0, 1'b0, 1'b0,
                             blk_a + VA_WIDTH'('h900), 4'd9,
                             pos_pc(blk_a, 4'd9) + VA_WIDTH'('d4));
          else
            upd2[0] = mk_cond(blk_a, 1'b0, cdir[perm[o][i]],
                              ctgt[perm[o][i]], cpos[perm[o][i]],
                              blk_a + VA_WIDTH'('d32));
          commit();
        end
        look2(blk_a);
        if (o == 0) begin
          r2 = pred2; rb2 = blk2;
          check("TC19d: both slots conditional (1, 4), no jump",
                (pred2[0].br_type == COND) && (pred2[1].br_type == COND)
                && (pred2[0].pos == 4'd1) && (pred2[1].pos == 4'd4));
          check("TC19d: the end is the jump PC",
                blk2.pft_addr == pos_pc(blk_a, 4'd9));
        end else begin
          check($sformatf("TC19d: order %0d%0d%0d: the same entry",
                          perm[o][0], perm[o][1], perm[o][2]),
                (pred2 == r2) && (blk2 == rb2));
        end
      end

      // e: both slot counts, a new branch below every held one with the
      //    entry full: it is kept, the highest held branch falls out and
      //    the end moves down to its PC. Two slots {4, 11} + 1: keep 1,
      //    4, end PC(11) -> then {1, 4} + 0: keep 0, 1, end PC(4). One
      //    slot {4} + 1: keep 1, end PC(4).
      do_reset();
      upd2[0] = mk_cond(blk_a, 1'b0, 1'b1, ctgt[1], 4'd4,
                        blk_a + VA_WIDTH'('d32));
      upd1[0] = mk_cond(blk_a, 1'b0, 1'b1, ctgt[1], 4'd4,
                        blk_a + VA_WIDTH'('d32));
      commit();
      upd2[0] = mk_cond(blk_a, 1'b0, 1'b1, ctgt[2], 4'd11,
                        blk_a + VA_WIDTH'('d32));
      commit();
      upd2[0] = mk_cond(blk_a, 1'b0, 1'b0, ctgt[0], 4'd1,
                        blk_a + VA_WIDTH'('d32));
      upd1[0] = mk_cond(blk_a, 1'b0, 1'b0, ctgt[0], 4'd1,
                        blk_a + VA_WIDTH'('d32));
      commit();
      look2(blk_a);
      look1(blk_a);
      check("TC19e: two slots: the new pos 1 kept, end PC(11)",
            (pred2[0].pos == 4'd1) && (pred2[1].pos == 4'd4)
            && (blk2.pft_addr == pos_pc(blk_a, 4'd11)));
      check("TC19e: one slot: the new pos 1 kept, end moved down to PC(4)",
            pred1[0].valid && (pred1[0].pos == 4'd1)
            && (blk1.pft_addr == pos_pc(blk_a, 4'd4)));
      upd2[0] = mk_cond(blk_a, 1'b0, 1'b1, ctgt[0], 4'd0,
                        blk_a + VA_WIDTH'('d32));
      commit();
      look2(blk_a);
      check("TC19e: two slots: pos 0 kept, pos 4 fell out, end PC(4)",
            (pred2[0].pos == 4'd0) && (pred2[1].pos == 4'd1)
            && (blk2.pft_addr == pos_pc(blk_a, 4'd4)));

      // f: past the end. The fallen-out pos 4 resolving again from this
      //    start, and a kept branch with a longer predicted end, leave
      //    the entry as it is. On the starting tree each rewrote the end.
      r2 = pred2; rb2 = blk2;
      upd2[0] = mk_cond(blk_a, 1'b0, 1'b1, ctgt[1], 4'd4,
                        blk_a + VA_WIDTH'('d32));
      commit();
      look2(blk_a);
      check("TC19f: the fallen-out branch again: no change",
            (pred2 == r2) && (blk2 == rb2));
      upd2[0] = mk_cond(blk_a, 1'b0, 1'b1, ctgt[0], 4'd1,
                        blk_a + VA_WIDTH'('d32));
      commit();
      look2(blk_a);
      check("TC19f: a kept branch with a longer predicted end: end kept",
            blk2.pft_addr == pos_pc(blk_a, 4'd4));

      // g: the fallen-out branch, resolving in a block from its own
      //    start, allocates there at pos 0 and is predicted from it.
      blk_b = pos_pc(blk_a, 4'd4);
      upd2[0] = mk_cond(blk_b, 1'b0, 1'b1, ctgt[1], 4'd0,
                        blk_b + VA_WIDTH'('d32));
      commit();
      look2(blk_b);
      check("TC19g: its own entry at its PC, pos 0, its target",
            blk2.hit && pred2[0].valid && (pred2[0].pos == 4'd0)
            && (pred2[0].target == ctgt[1]));
      look2(blk_a);
      check("TC19g: the first start's entry unchanged",
            (pred2[0].pos == 4'd0) && (pred2[1].pos == 4'd1)
            && (blk2.pft_addr == pos_pc(blk_a, 4'd4)));
    end
    tc_close("TC19");

    // ==============================================================
    // TC20 -- BP-140, Problem 1. Starts of one region in different
    //         sets. Under the starting index pc[10:5] every start of a
    //         region indexes one set; the BP-140 index folds pc[4:1]
    //         into its top bits. Five starts of one region (offsets 0,
    //         2, 6, 10, 30) plus UBTB_WAYS-1 other regions' starts in
    //         the offset-0 start's set: all stay resident. With one set
    //         the five would compete for its four ways.
    // ==============================================================
    tc_open("TC20 BP-140 starts in different sets");
    begin
      logic [VA_WIDTH-1:0] st [5];
      do_reset();
      blk_a = mk_pc(62, TAG_BASE);
      st[0] = blk_a;
      st[1] = blk_a + VA_WIDTH'('d2);
      st[2] = blk_a + VA_WIDTH'('d6);
      st[3] = blk_a + VA_WIDTH'('d10);
      st[4] = blk_a + VA_WIDTH'('d30);
      for (int i = 0; i < 5; i++) begin
        $display("TC20 start %h: starting set %0d, BP-140 set %0d", st[i],
                 st[i][UBTB_OFFSET_BITS +: UBTB_IDX_BITS], pc_idx(st[i]));
        check($sformatf("TC20 start %0d: one set under the starting index",
                        i), st[i][UBTB_OFFSET_BITS +: UBTB_IDX_BITS]
                            == st[0][UBTB_OFFSET_BITS +: UBTB_IDX_BITS]);
        for (int j = 0; j < i; j++)
          check($sformatf("TC20 starts %0d, %0d: different sets", j, i),
                pc_idx(st[i]) != pc_idx(st[j]));
      end
      for (int i = 0; i < 5; i++)
        wr_cond(st[i], 1'b0, 1'b1, st[i] + VA_WIDTH'('h100), 4'd1,
                st[i] + VA_WIDTH'('d32));
      for (int i = 1; i < UBTB_WAYS; i++)
        wr_cond(mk_pc(62, TAG_BASE + i), 1'b0, 1'b1,
                blk_a + VA_WIDTH'('h400), 4'd1, blk_a + VA_WIDTH'('d32));
      for (int i = 0; i < 5; i++) begin
        look2(st[i]);
        check($sformatf("TC20 start %0d resident with its own branch", i),
              blk2.hit && pred2[0].valid && (pred2[0].pos == 4'd1)
              && (pred2[0].target == st[i] + VA_WIDTH'('h100)));
      end
    end
    tc_close("TC20");

    // ==============================================================
    // TC21 -- BP-140. Two channels resolving branches of one block in
    //         one cycle (the merge of pass 2): three conditionals at
    //         two slots, the third arriving with the second in one
    //         cycle, in both channel orders. The split gives the same
    //         entry as one channel at a time (TC19c).
    // ==============================================================
    tc_open("TC21 BP-140 two-channel split");
    begin
      ubtb_pred_t [1:0] r2;
      ubtb_blk_t        rb2;
      blk_a = mk_pc(63, TAG_BASE);
      for (int o = 0; o < 2; o++) begin
        do_reset();
        upd2[0] = mk_cond(blk_a, 1'b0, 1'b1, blk_a + VA_WIDTH'('h100), 4'd4,
                          blk_a + VA_WIDTH'('d32));
        commit();
        upd2[o]     = mk_cond(blk_a, 1'b0, 1'b0, blk_a + VA_WIDTH'('h200),
                              4'd1, blk_a + VA_WIDTH'('d32));
        upd2[1 - o] = mk_cond(blk_a, 1'b1, 1'b1, blk_a + VA_WIDTH'('h300),
                              4'd11, blk_a + VA_WIDTH'('d32));
        commit();
        look2(blk_a);
        if (o == 0) begin
          r2 = pred2; rb2 = blk2;
          check("TC21: keeps 1 and 4, end PC(11)",
                (pred2[0].pos == 4'd1) && (pred2[1].pos == 4'd4)
                && (blk2.pft_addr == pos_pc(blk_a, 4'd11)));
        end else begin
          check("TC21: the other channel order: the same entry",
                (pred2 == r2) && (blk2 == rb2));
        end
      end
    end
    tc_close("TC21");

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
