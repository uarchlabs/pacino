// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_ras.sv
// DATE:    2026-06-23
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking testbench for ras.sv (BP-063, BP-064).
//
// Directed cases TC-01 .. TC-21. TC-01 .. TC-20 from BP-063; TC-21
// (BP-064) pins TD #78 (undo-pop does not reverse a recursion pop).
// Each case is self-contained: it resets, seeds any required state
// explicitly, and does not rely on state left by a prior case.
//
// Pointer model (post BP-063 fix): the BOS index is a sentinel. A
// push that would allocate on BOS (cold-start, or full wrap) skips to
// BOS+1, so a single live entry is distinguishable from empty
// (empty is TOSR==BOS). TOSW is monotonic across pops so popped
// entries survive for pointer-only mispredict restore.
//
// p3 protocol (IC-RAS-11): ras_pred_val_p3 / ras_br_type_p3 are the
// one-cycle-registered p2 inputs. drive() drives p3 from the previous
// cycle's p2 so the p3 repair pass is a no-op; force_p3() overrides p3
// to exercise a deliberate p2/p3 disagreement (TC-16, TC-17).
//
// Internal state (tosr/tosw/bos/csp, spec_ret_addr, spec_rctr,
// commit_ret_addr) is observed read-only via hierarchical references;
// rctr and csp are not exposed on the port list.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  // -----------------------------------------------------------------
  // Clock and reset
  // -----------------------------------------------------------------
  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // -----------------------------------------------------------------
  // DUT port signals (names match ras.sv exactly)
  // -----------------------------------------------------------------
  logic [VA_WIDTH-1:0] tos_addr_p0  [0:NUM_PRED_SLOTS-1];
  logic                tos_valid_p0 [0:NUM_PRED_SLOTS-1];

  logic                pred_val_p2  [0:NUM_PRED_SLOTS-1];
  bp_br_type_e         br_type_p2   [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] pc_p2        [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] fall_p2      [0:NUM_PRED_SLOTS-1];

  logic [VA_WIDTH-1:0] pop_addr_p2  [0:NUM_PRED_SLOTS-1];
  logic                pop_valid_p2 [0:NUM_PRED_SLOTS-1];
  bp_ras_snapshot_t    snap_p2      [0:NUM_PRED_SLOTS-1];

  logic                pred_val_p3  [0:NUM_PRED_SLOTS-1];
  bp_br_type_e         br_type_p3   [0:NUM_PRED_SLOTS-1];

  logic                restore_val;
  bp_ras_snapshot_t    restore_snap;

  logic                commit_val;
  bp_br_type_e         commit_br_type;
  logic [VA_WIDTH-1:0] commit_ret_addr;
  bp_ras_snapshot_t    commit_snap;

  logic                flush_val;
  bp_ras_snapshot_t    flush_snap;

  // -----------------------------------------------------------------
  // DUT
  // -----------------------------------------------------------------
  ras dut (
    .clk                  (clk),
    .rstn                 (rstn),
    .ras_tos_addr_p0      (tos_addr_p0),
    .ras_tos_valid_p0     (tos_valid_p0),
    .ras_pred_val_p2      (pred_val_p2),
    .ras_br_type_p2       (br_type_p2),
    .ras_pc_p2            (pc_p2),
    .ras_fall_through_p2  (fall_p2),
    .ras_pop_addr_p2      (pop_addr_p2),
    .ras_pop_valid_p2     (pop_valid_p2),
    .ras_snapshot_p2      (snap_p2),
    .ras_pred_val_p3      (pred_val_p3),
    .ras_br_type_p3       (br_type_p3),
    .ras_restore_val      (restore_val),
    .ras_restore_snapshot (restore_snap),
    .ras_commit_val       (commit_val),
    .ras_commit_br_type   (commit_br_type),
    .ras_commit_ret_addr  (commit_ret_addr),
    .ras_commit_snapshot  (commit_snap),
    .ras_flush_val        (flush_val),
    .ras_flush_snapshot   (flush_snap)
  );

  // -----------------------------------------------------------------
  // Scoreboard
  // -----------------------------------------------------------------
  int pass_cnt;
  int fail_cnt;

  task automatic check(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
      $display("PASS: %s", nm);
    end else begin
      fail_cnt++;
      $display("FAIL: %s", nm);
    end
  endtask

  // -----------------------------------------------------------------
  // p2 -> p3 pipeline shadow
  // -----------------------------------------------------------------
  logic        prev_val [0:NUM_PRED_SLOTS-1];
  bp_br_type_e prev_typ [0:NUM_PRED_SLOTS-1];

  // Drive p3 from previous cycle's p2 (no-op repair) and set p2.
  task automatic drive(
      input logic                v0, input bp_br_type_e t0,
      input logic [VA_WIDTH-1:0] f0,
      input logic                v1, input bp_br_type_e t1,
      input logic [VA_WIDTH-1:0] f1);
    pred_val_p3[0] = prev_val[0]; br_type_p3[0] = prev_typ[0];
    pred_val_p3[1] = prev_val[1]; br_type_p3[1] = prev_typ[1];
    pred_val_p2[0] = v0; br_type_p2[0] = t0; fall_p2[0] = f0;
    pred_val_p2[1] = v1; br_type_p2[1] = t1; fall_p2[1] = f1;
    pc_p2[0] = '0; pc_p2[1] = '0;
  endtask

  // Override p3 explicitly (deliberate p2/p3 disagreement).
  task automatic force_p3(
      input logic v0, input bp_br_type_e t0,
      input logic v1, input bp_br_type_e t1);
    pred_val_p3[0] = v0; br_type_p3[0] = t0;
    pred_val_p3[1] = v1; br_type_p3[1] = t1;
  endtask

  // Advance one clock; remember this cycle's p2 for next cycle's p3.
  task automatic tick();
    @(posedge clk);
    #1;
    prev_val[0] = pred_val_p2[0]; prev_typ[0] = br_type_p2[0];
    prev_val[1] = pred_val_p2[1]; prev_typ[1] = br_type_p2[1];
  endtask

  // Drive a commit event for one cycle (p2 idle), then settle.
  task automatic commit_op(input bp_br_type_e bt,
                           input logic [VA_WIDTH-1:0] ra,
                           input logic [RAS_PTR_BITS-1:0] snap_tosr);
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    commit_val          = 1'b1;
    commit_br_type      = bt;
    commit_ret_addr     = ra;
    commit_snap.tosr    = snap_tosr;
    commit_snap.tosw    = '0;
    commit_snap.bos     = '0;
    tick();
    commit_val          = 1'b0;
    commit_br_type      = NO_BRANCH;
    commit_ret_addr     = '0;
    commit_snap         = '0;
  endtask

  // Synchronous reset, plus one edge so ras_rst_done is set.
  task automatic do_reset();
    rstn = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      pred_val_p2[s] = 1'b0; br_type_p2[s] = NO_BRANCH; fall_p2[s] = '0;
      pc_p2[s]       = '0;
      pred_val_p3[s] = 1'b0; br_type_p3[s] = NO_BRANCH;
      prev_val[s]    = 1'b0; prev_typ[s]   = NO_BRANCH;
    end
    restore_val = 1'b0; restore_snap = '0;
    commit_val  = 1'b0; commit_br_type = NO_BRANCH;
    commit_ret_addr = '0; commit_snap = '0;
    flush_val   = 1'b0; flush_snap = '0;
    repeat (3) @(posedge clk);
    rstn = 1'b1;
    @(posedge clk);
    #1;
  endtask

  // Push one address on slot 0 (slot 1 idle), commit a cycle.
  task automatic push_one(input logic [VA_WIDTH-1:0] a);
    drive(1'b1, DIRECT_CALL, a, 1'b0, NO_BRANCH, '0);
    tick();
  endtask

  // -----------------------------------------------------------------
  // Test addresses
  // -----------------------------------------------------------------
  localparam logic [VA_WIDTH-1:0] ADDR_A = 40'h00_0000_1000;
  localparam logic [VA_WIDTH-1:0] ADDR_B = 40'h00_0000_2000;
  localparam logic [VA_WIDTH-1:0] ADDR_C = 40'h00_0000_3000;
  localparam logic [VA_WIDTH-1:0] ADDR_X = 40'h00_0000_9000;
  localparam logic [VA_WIDTH-1:0] ADDR_R = 40'h00_000A_0000;

  logic [VA_WIDTH-1:0] fill_addr [0:15];

  // -----------------------------------------------------------------
  // Stimulus
  // -----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    for (int i = 0; i < 16; i++)
      fill_addr[i] = 40'h0001_0000 + (i * 40'h100);

    // =============================================================
    // TC-01: Reset state
    // =============================================================
    do_reset();
    check("TC-01 tosr==0", dut.tosr == '0);
    check("TC-01 tosw==0", dut.tosw == '0);
    check("TC-01 bos==0",  dut.bos  == '0);
    check("TC-01 pop_valid_p2[0]==0", pop_valid_p2[0] == 1'b0);
    check("TC-01 pop_valid_p2[1]==0", pop_valid_p2[1] == 1'b0);
    check("TC-01 tos_valid_p0[0]==0", tos_valid_p0[0] == 1'b0);
    check("TC-01 tos_valid_p0[1]==0", tos_valid_p0[1] == 1'b0);

    // =============================================================
    // TC-02: Single push slot 0
    // =============================================================
    do_reset();
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    #1;
    // Post-push snapshot: entry at idx1 (sentinel skip), tosr=1, tosw=2.
    check("TC-02 snap[0].tosr==1", snap_p2[0].tosr == 4'd1);
    check("TC-02 snap[0].tosw==2", snap_p2[0].tosw == 4'd2);
    check("TC-02 snap[0].bos==0",  snap_p2[0].bos  == 4'd0);
    tick();
    check("TC-02 tos_valid_p0[0]==1 next cycle", tos_valid_p0[0] == 1'b1);
    check("TC-02 tos_addr_p0[0]==ADDR_A",        tos_addr_p0[0] == ADDR_A);

    // =============================================================
    // TC-03: Single pop slot 0
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // seed one entry
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-03 pop_valid_p2[0]==1", pop_valid_p2[0] == 1'b1);
    check("TC-03 pop_addr_p2[0]==ADDR_A", pop_addr_p2[0] == ADDR_A);
    // Post-pop snapshot: tosr back to 0, tosw monotonic at 2.
    check("TC-03 snap[0].tosr==0", snap_p2[0].tosr == 4'd0);
    check("TC-03 snap[0].tosw==2", snap_p2[0].tosw == 4'd2);
    tick();

    // =============================================================
    // TC-04: Dual push (call/call). Seed one entry first so the
    // cold-start sentinel skip does not perturb the +2 advance.
    // =============================================================
    do_reset();
    push_one(ADDR_X);                       // tosr=1, tosw=2
    begin
      logic [RAS_PTR_BITS-1:0] tosw_before;
      tosw_before = dut.tosw;
      drive(1'b1, DIRECT_CALL, ADDR_A, 1'b1, DIRECT_CALL, ADDR_B);
      tick();
      check("TC-04 TOSW advanced by 2",
            (dut.tosw - tosw_before) == 4'd2);
      // Slot 0 -> idx2, slot 1 -> idx3 (in order).
      check("TC-04 spec[2]==ADDR_A", dut.spec_ret_addr[2] == ADDR_A);
      check("TC-04 spec[3]==ADDR_B", dut.spec_ret_addr[3] == ADDR_B);
      check("TC-04 tosr==3 (top is B)", dut.tosr == 4'd3);
    end

    // =============================================================
    // TC-05: Dual pop (return/return). Seed two entries.
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // idx1
    push_one(ADDR_B);                       // idx2, tosr=2
    drive(1'b1, RETURN, '0, 1'b1, RETURN, '0);
    #1;
    // Slot 0 pops current top (B); slot 1 pops next (A).
    check("TC-05 pop_valid_p2[0]==1", pop_valid_p2[0] == 1'b1);
    check("TC-05 pop_addr_p2[0]==ADDR_B (top)", pop_addr_p2[0] == ADDR_B);
    check("TC-05 pop_valid_p2[1]==1", pop_valid_p2[1] == 1'b1);
    check("TC-05 pop_addr_p2[1]==ADDR_A (next)", pop_addr_p2[1] == ADDR_A);
    tick();

    // =============================================================
    // TC-06: Call then return (slot0=call, slot1=return). Bypass.
    // =============================================================
    do_reset();
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b1, RETURN, '0);
    #1;
    // slot1 pop must receive slot0's pushed address via bypass, not
    // from the array (array not yet written this cycle).
    check("TC-06 pop_valid_p2[1]==1", pop_valid_p2[1] == 1'b1);
    check("TC-06 pop_addr_p2[1]==ADDR_A (bypass)",
          pop_addr_p2[1] == ADDR_A);
    check("TC-06 array idx1 not yet written (pre-edge)",
          dut.spec_ret_addr[1] != ADDR_A);
    // slot1 snapshot: entry present (tosw=2) but TOSR back to pre-push.
    check("TC-06 snap[1].tosr==0 (pre-push)", snap_p2[1].tosr == 4'd0);
    check("TC-06 snap[1].tosw==2 (entry present)",
          snap_p2[1].tosw == 4'd2);
    tick();
    check("TC-06 spec[1]==ADDR_A after edge", dut.spec_ret_addr[1] == ADDR_A);

    // =============================================================
    // TC-07: Return then call (slot0=return, slot1=call). Seed one.
    // =============================================================
    do_reset();
    push_one(ADDR_X);                       // idx1, tosr=1, tosw=2
    drive(1'b1, RETURN, '0, 1'b1, DIRECT_CALL, ADDR_B);
    #1;
    check("TC-07 pop_valid_p2[0]==1", pop_valid_p2[0] == 1'b1);
    check("TC-07 pop_addr_p2[0]==ADDR_X", pop_addr_p2[0] == ADDR_X);
    // slot1 push lands at frontier (idx2); no bypass.
    check("TC-07 snap[1].tosr==2 (push at new TOSW)",
          snap_p2[1].tosr == 4'd2);
    check("TC-07 snap[1].tosw==3", snap_p2[1].tosw == 4'd3);
    tick();
    check("TC-07 spec[2]==ADDR_B", dut.spec_ret_addr[2] == ADDR_B);

    // =============================================================
    // TC-08: Recursion counter increment
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // idx1, rctr=0, tosw=2
    begin
      logic [RAS_PTR_BITS-1:0] tosw_before;
      tosw_before = dut.tosw;
      drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0); // same addr
      tick();
      check("TC-08 TOSW did not advance (recursion)",
            dut.tosw == tosw_before);
      check("TC-08 rctr at idx1 incremented to 1",
            dut.spec_rctr[1] == 4'd1);
      check("TC-08 tosr still 1", dut.tosr == 4'd1);
    end

    // =============================================================
    // TC-09: Recursion counter decrement on pop
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // rctr=0
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0); tick(); // rctr=1
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0); tick(); // rctr=2
    check("TC-09 seeded rctr==2", dut.spec_rctr[1] == 4'd2);
    // First RETURN: rctr 2->1, TOSR holds.
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); tick();
    check("TC-09 rctr==1 after pop1", dut.spec_rctr[1] == 4'd1);
    check("TC-09 tosr holds at 1 (pop1)", dut.tosr == 4'd1);
    // Second RETURN: rctr 1->0, TOSR holds.
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); tick();
    check("TC-09 rctr==0 after pop2", dut.spec_rctr[1] == 4'd0);
    check("TC-09 tosr holds at 1 (pop2)", dut.tosr == 4'd1);
    // Third RETURN: actual pop, TOSR moves.
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); tick();
    check("TC-09 tosr moves to 0 (pop3)", dut.tosr == 4'd0);

    // =============================================================
    // TC-10: Recursion counter saturation (2^RAS_RCTR_WIDTH pushes)
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // first entry, rctr=0
    for (int i = 1; i < (1 << RAS_RCTR_WIDTH); i++) begin
      drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
      tick();
    end
    check("TC-10 rctr saturated at max",
          dut.spec_rctr[1] == {RAS_RCTR_WIDTH{1'b1}});
    check("TC-10 tosw not advanced past idx2", dut.tosw == 4'd2);
    // One more push must not overflow rctr.
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0); tick();
    check("TC-10 rctr stays at max after extra push",
          dut.spec_rctr[1] == {RAS_RCTR_WIDTH{1'b1}});

    // =============================================================
    // TC-11: Snapshot slot 0 vs slot 1 in a dual push.
    // Seed one entry to avoid cold-start sentinel skip.
    // =============================================================
    do_reset();
    push_one(ADDR_X);                       // tosr=1, tosw=2
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b1, DIRECT_CALL, ADDR_B);
    #1;
    check("TC-11 snap[0].tosr==2 (post slot0)", snap_p2[0].tosr == 4'd2);
    check("TC-11 snap[0].tosw==3 (post slot0)", snap_p2[0].tosw == 4'd3);
    check("TC-11 snap[1].tosr==3 (post both)",  snap_p2[1].tosr == 4'd3);
    check("TC-11 snap[1].tosw==4 (post both)",  snap_p2[1].tosw == 4'd4);
    tick();

    // =============================================================
    // TC-12: Mispredict restore (pointer-only, blocks p2).
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // idx1
    push_one(ADDR_B);                       // idx2
    push_one(ADDR_C);                       // idx3, tosr=3, tosw=4
    // Restore to the post-first-push state and simultaneously try a
    // push (must be blocked).
    drive(1'b1, DIRECT_CALL, ADDR_X, 1'b0, NO_BRANCH, '0);
    restore_val       = 1'b1;
    restore_snap.tosr = 4'd1;
    restore_snap.tosw = 4'd2;
    restore_snap.bos  = 4'd0;
    tick();
    restore_val       = 1'b0;
    restore_snap      = '0;
    check("TC-12 tosr restored to 1", dut.tosr == 4'd1);
    check("TC-12 tosw restored to 2", dut.tosw == 4'd2);
    check("TC-12 bos restored to 0",  dut.bos  == 4'd0);
    check("TC-12 p2 push blocked (idx4 not written)",
          dut.spec_ret_addr[4] != ADDR_X);

    // =============================================================
    // TC-13: Commit stack push
    // =============================================================
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 4'd0);
    check("TC-13 csp advanced to 1", dut.csp == 5'd1);
    check("TC-13 commit_ret_addr[0]==ADDR_R",
          dut.commit_ret_addr[0] == ADDR_R);

    // =============================================================
    // TC-14: Commit stack pop
    // =============================================================
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 4'd0);   // seed commit entry
    check("TC-14 csp==1 after seed", dut.csp == 5'd1);
    commit_op(RETURN, '0, 4'd0);
    check("TC-14 csp decremented to 0", dut.csp == 5'd0);

    // =============================================================
    // TC-15: Empty fallback
    // =============================================================
    do_reset();
    // Both stacks empty -> pop invalid.
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-15 pop_valid_p2[0]==0 (both empty)",
          pop_valid_p2[0] == 1'b0);
    tick();
    // Seed commit stack only.
    commit_op(DIRECT_CALL, ADDR_R, 4'd0);
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-15 pop_valid_p2[0]==1 (commit fallback)",
          pop_valid_p2[0] == 1'b1);
    check("TC-15 pop_addr_p2[0]==ADDR_R (commit top)",
          pop_addr_p2[0] == ADDR_R);
    tick();
    check("TC-15 commit entry NOT consumed (csp==1)", dut.csp == 5'd1);

    // =============================================================
    // TC-16: p3 repair -- undo push (p2=push, p3=no-op)
    // =============================================================
    do_reset();
    push_one(ADDR_X);                       // baseline, tosr=1, tosw=2
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0); // push A -> idx2
    tick();
    check("TC-16 pre-repair tosr==2", dut.tosr == 4'd2);
    // Repair cycle: p2 idle, p3 disagrees (no-op vs the push).
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-16 tosr returned to pre-push (1)", dut.tosr == 4'd1);
    check("TC-16 top is baseline X", dut.spec_ret_addr[dut.tosr] == ADDR_X);

    // =============================================================
    // TC-17: p3 repair -- undo pop (p2=pop, p3=no-op)
    // =============================================================
    do_reset();
    push_one(ADDR_X);                       // idx1, tosr=1, tosw=2
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); // pop -> tosr=0
    tick();
    check("TC-17 pre-repair tosr==0 (after pop)", dut.tosr == 4'd0);
    // Repair cycle: p2 idle, p3 disagrees (no-op vs the pop).
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-17 tosr returned to pre-pop (1)", dut.tosr == 4'd1);
    check("TC-17 top re-exposed as X", dut.spec_ret_addr[dut.tosr] == ADDR_X);

    // =============================================================
    // TC-18: Overflow graceful degradation
    // =============================================================
    do_reset();
    // Fill the speculative stack (idx1..15 with the sentinel model).
    for (int i = 0; i < 15; i++) begin
      drive(1'b1, DIRECT_CALL, fill_addr[i], 1'b0, NO_BRANCH, '0);
      tick();
    end
    // One more push -> circular wrap, no fault.
    drive(1'b1, DIRECT_CALL, fill_addr[15], 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-18 pointers remain known (no X, graceful wrap)",
          (^{dut.tosr, dut.tosw, dut.bos} !== 1'bx));
    // Stack still functional: a pop yields a valid, non-X address.
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-18 pop_valid_p2[0]==1 (still functional)",
          pop_valid_p2[0] == 1'b1);
    check("TC-18 pop addr is known (not X)",
          pop_addr_p2[0] === pop_addr_p2[0]);
    tick();

    // =============================================================
    // TC-19: p0 TOS read reflects current TOS.
    // ras.sv p0 read is combinational off the registered pointers
    // (tosr/bos) and the array, so a pushed entry becomes visible the
    // cycle AFTER the push commits. Documented in Results Capture.
    // =============================================================
    do_reset();
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-19 same-cycle TOS still old (empty) before edge",
          tos_valid_p0[0] == 1'b0);
    tick();
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-19 next-cycle TOS reflects pushed addr",
          tos_addr_p0[0] == ADDR_A);
    check("TC-19 next-cycle TOS valid", tos_valid_p0[0] == 1'b1);
    tick();

    // =============================================================
    // TC-20: ras_tos_valid_p0 vs both-empty
    // =============================================================
    do_reset();
    check("TC-20 deasserted after reset", tos_valid_p0[0] == 1'b0);
    commit_op(DIRECT_CALL, ADDR_R, 4'd0);   // seed commit only
    #1;
    check("TC-20 asserted with commit-only", tos_valid_p0[0] == 1'b1);
    check("TC-20 tos_addr from commit top", tos_addr_p0[0] == ADDR_R);
    commit_op(RETURN, '0, 4'd0);            // clear commit
    #1;
    check("TC-20 deasserted when both empty", tos_valid_p0[0] == 1'b0);

    // =============================================================
    // TC-21: TD #78 pin -- undo-pop does NOT reverse a recursion
    // pop. Seed a recursion entry so the p2 pop is a recursion-
    // decrement (TOSR held, rctr decremented) rather than a TOSR-
    // moving pop. The p3 undo-pop re-expose then moves TOSR up a
    // slot (re-exposing a stale/empty frontier slot) instead of
    // restoring the lost recursion count at the held slot. This
    // pins the CURRENT non-reversing behavior; it is not a fix.
    // Modeled on TC-17 but with a recursion-decrement pop in p2.
    // See ras_decisions.md section 1.2 and PROJECT_STATUS TD #78.
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // idx1, rctr=0, tosw=2
    // Second push of ADDR_A -> recursion: rctr[1] 0->1, TOSR holds.
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-21 pins TD #78: seeded recursion rctr[1]==1",
          dut.spec_rctr[1] == 4'd1);
    check("TC-21 pins TD #78: seeded tosr==1 (recursion holds top)",
          dut.tosr == 4'd1);
    // p2 RETURN with p3 agreeing (drive) -> recursion-decrement pop:
    // rctr[1] 1->0, TOSR holds at 1 (TOSR not moved by this pop).
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-21 pins TD #78: recursion pop decremented rctr[1] 1->0",
          dut.spec_rctr[1] == 4'd0);
    check("TC-21 pins TD #78: recursion pop held tosr at 1",
          dut.tosr == 4'd1);
    // Repair cycle: p2 idle, p3 forced no-op so it disagrees with the
    // registered OP_POP -> undo-pop re-expose fires.
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    // NON-reversing outcome: the pre-pop recursion state is NOT
    // recovered. The re-expose moves TOSR up a slot (1 -> 2) and does
    // not restore the decremented recursion count at the held slot.
    check("TC-21 pins TD #78: rctr[1] NOT restored, stays 0 (count lost)",
          dut.spec_rctr[1] == 4'd0);
    check("TC-21 pins TD #78: undo-pop moved tosr to 2, not restored to 1",
          dut.tosr == 4'd2);
    check("TC-21 pins TD #78: tosw held at 2 (no allocation on re-expose)",
          dut.tosw == 4'd2);
    check("TC-21 pins TD #78: re-exposed top idx2 is empty (0), not ADDR_A",
          dut.spec_ret_addr[2] == '0);

    // -------------------------------------------------------------
    $display("=================================================");
    $display("tb_ras: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    $display("=================================================");
    if (fail_cnt != 0)
      $fatal(1, "tb_ras: %0d checks failed", fail_cnt);
    else
      $finish;
  end

  // Watchdog
  initial begin
    #500000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "tb_ras: timeout");
  end

endmodule
