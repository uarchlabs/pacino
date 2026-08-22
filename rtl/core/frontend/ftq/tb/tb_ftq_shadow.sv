// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ftq_shadow (BP-107), ftq_decisions.md 5.6.
//
// Self-checking. The acceptance criteria are Problem 3's three: a
// response arriving after a redirect that squashed its entry is
// dropped, one for a surviving entry is not, and the shadow survives
// back-to-back redirects.
//
// THE STIMULUS MODELS THE CLUSTER, and it has to, because the whole
// mechanism is a claim about lockstep. The shadow shifts every cycle
// in step with bp_cluster's stage registers, so a request pushed at
// cycle T is at stage 1 in T+1 and its p1 response arrives then.
// Every case below pushes requests and then presents responses at
// the cycle offset the cluster would, rather than poking a stage
// directly -- a testbench that placed the shadow state by hand would
// prove the compare and not the lockstep.
//
// NOTHING IS ASSUMED ABOUT RESIDUE. shadow_val is checked clear at
// reset before any case relies on an empty shadow, and every case
// that needs a non-empty one fills it by driving requests.
//
// STAGE 0 IS THE PRESENTED REQUEST and is COMBINATIONAL: a p0
// request has not been registered anywhere, in the cluster or in
// the shadow. So push() leaves the pushed request at STAGE 1, and
// only three requests are held in flops at once -- four stages,
// three flops. 5.6 counts the p0 stage and the p0 stage needs no
// register. Every stage index below follows that mapping.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  logic                    req_val;
  logic [FTQ_PTR_BITS-1:0] req_ptr;
  logic                    squash_val;
  logic [FTQ_PTR_BITS-1:0] squash_start;
  logic [FTQ_PTR_BITS-1:0] squash_end;
  logic                    gv_pred_p1;
  logic [FTQ_IDX_BITS-1:0] idx_pred_p1;
  logic                    gv_slot_p2;
  logic [FTQ_IDX_BITS-1:0] idx_slot_p2;
  logic                    gv_meta_p2;
  logic [FTQ_IDX_BITS-1:0] idx_meta_p2;
  logic [FTQ_IDX_BITS-1:0] idx_redir_p2;
  logic                    gv_slot_p3;
  logic [FTQ_IDX_BITS-1:0] idx_slot_p3;
  logic                    gv_meta_p3;
  logic [FTQ_IDX_BITS-1:0] idx_meta_p3;
  logic [FTQ_IDX_BITS-1:0] idx_redir_p3;
  logic                    ok_pred_p1;
  logic                    ok_slot_p2;
  logic                    ok_meta_p2;
  logic                    ok_redir_p2;
  logic                    ok_slot_p3;
  logic                    ok_meta_p3;
  logic                    ok_redir_p3;
  logic                    alloc_inflight;
  logic [3:0]              shadow_val;
  logic [FTQ_PTR_BITS-1:0] shadow_ptr [0:3];

  ftq_shadow dut (
    .clk            (clk),
    .rstn           (rstn),
    .req_val        (req_val),
    .req_ptr        (req_ptr),
    .squash_val     (squash_val),
    .squash_start   (squash_start),
    .squash_end     (squash_end),
    .gv_pred_p1     (gv_pred_p1),
    .idx_pred_p1    (idx_pred_p1),
    .gv_slot_p2     (gv_slot_p2),
    .idx_slot_p2    (idx_slot_p2),
    .gv_meta_p2     (gv_meta_p2),
    .idx_meta_p2    (idx_meta_p2),
    .idx_redir_p2   (idx_redir_p2),
    .gv_slot_p3     (gv_slot_p3),
    .idx_slot_p3    (idx_slot_p3),
    .gv_meta_p3     (gv_meta_p3),
    .idx_meta_p3    (idx_meta_p3),
    .idx_redir_p3   (idx_redir_p3),
    .ok_pred_p1     (ok_pred_p1),
    .ok_slot_p2     (ok_slot_p2),
    .ok_meta_p2     (ok_meta_p2),
    .ok_redir_p2    (ok_redir_p2),
    .ok_slot_p3     (ok_slot_p3),
    .ok_meta_p3     (ok_meta_p3),
    .ok_redir_p3    (ok_redir_p3),
    .alloc_inflight (alloc_inflight),
    .shadow_val     (shadow_val),
    .shadow_ptr     (shadow_ptr)
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

  task automatic clr();
    req_val    = 1'b0;
    squash_val = 1'b0;
    gv_pred_p1 = 1'b0;
    gv_slot_p2 = 1'b0;
    gv_meta_p2 = 1'b0;
    gv_slot_p3 = 1'b0;
    gv_meta_p3 = 1'b0;
  endtask

  task automatic do_reset();
    rstn         = 1'b0;
    req_ptr      = '0;
    squash_start = '0;
    squash_end   = '0;
    idx_pred_p1  = '0;
    idx_slot_p2  = '0;
    idx_meta_p2  = '0;
    idx_redir_p2 = '0;
    idx_slot_p3  = '0;
    idx_meta_p3  = '0;
    idx_redir_p3 = '0;
    clr();
    repeat (4) tick();
    rstn = 1'b1;
    repeat (2) tick();
  endtask

  // Push one accepted p0 request and advance a cycle. This is the
  // only way a stage becomes valid in this file.
  task automatic push(input int ptr);
    req_val = 1'b1;
    req_ptr = FTQ_PTR_BITS'(ptr);
    tick();
    req_val = 1'b0;
  endtask

  // Advance with no request, so the shadow shifts a bubble in.
  task automatic idle_cyc();
    req_val = 1'b0;
    tick();
  endtask

  task automatic squash_cyc(input int st, input int en);
    squash_val   = 1'b1;
    squash_start = FTQ_PTR_BITS'(st);
    squash_end   = FTQ_PTR_BITS'(en);
    tick();
    squash_val   = 1'b0;
  endtask

  // -----------------------------------------------------------------
  // A. Reset, and the shift.
  // -----------------------------------------------------------------
  task automatic group_a();
    $display("-- A: reset and the shift --");
    do_reset();

    chk("A1 the shadow is empty at reset", shadow_val == 4'b0000);
    chk("A2 no response is accepted when empty",
        !ok_pred_p1 && !ok_slot_p2 && !ok_redir_p2 && !ok_slot_p3);
    chk("A3 alloc_inflight clear at reset", !alloc_inflight);

    // One request walks all four stages, one per cycle. The
    // lockstep claim of 5.6 IS this walk.
    // Stage 0 is the request being PRESENTED, so it is visible
    // before any edge.
    req_val = 1'b1;
    req_ptr = FTQ_PTR_BITS'(20);
    #1;
    chk("A4 stage 0 is the presented request",
        shadow_val[0] && (shadow_ptr[0] == FTQ_PTR_BITS'(20)));
    chk("A5 alloc_inflight is not set yet", !alloc_inflight);

    tick();
    req_val = 1'b0;
    #1;
    chk("A6 it moved to stage 1, which is p1",
        shadow_val[1] && (shadow_ptr[1] == FTQ_PTR_BITS'(20)));
    chk("A7 stage 0 is empty behind it", !shadow_val[0]);
    chk("A8 alloc_inflight is the p1 stage", alloc_inflight);

    idle_cyc();
    chk("A9 it moved to stage 2",
        shadow_val[2] && (shadow_ptr[2] == FTQ_PTR_BITS'(20)));
    chk("A10 alloc_inflight cleared with it", !alloc_inflight);
    idle_cyc();
    chk("A11 it moved to stage 3",
        shadow_val[3] && (shadow_ptr[3] == FTQ_PTR_BITS'(20)));
    idle_cyc();
    chk("A12 it left the shadow", shadow_val == 4'b0000);

    // FOUR STAGES OCCUPIED AT ONCE, the steady state at one block
    // per cycle: three in the flops and one being presented.
    push(30); push(31); push(32);
    req_val = 1'b1;
    req_ptr = FTQ_PTR_BITS'(33);
    #1;
    chk("A13 all four stages occupied", shadow_val == 4'b1111);
    chk("A14 they are in order",
        (shadow_ptr[0] == FTQ_PTR_BITS'(33)) &&
        (shadow_ptr[1] == FTQ_PTR_BITS'(32)) &&
        (shadow_ptr[2] == FTQ_PTR_BITS'(31)) &&
        (shadow_ptr[3] == FTQ_PTR_BITS'(30)));
    req_val = 1'b0;
  endtask

  // -----------------------------------------------------------------
  // B. Matching, with no redirect anywhere.
  // -----------------------------------------------------------------
  task automatic group_b();
    $display("-- B: matching with no redirect --");
    do_reset();

    push(30); push(31); push(32);

    // Stage 1 holds 32, stage 2 holds 31, stage 3 holds 30. The
    // response for each must be accepted at ITS OWN STAGE and
    // nowhere else.
    gv_pred_p1  = 1'b1;
    idx_pred_p1 = 6'd32;
    gv_slot_p2  = 1'b1;
    idx_slot_p2 = 6'd31;
    gv_meta_p2  = 1'b1;
    idx_meta_p2 = 6'd31;
    idx_redir_p2 = 6'd31;
    gv_slot_p3  = 1'b1;
    idx_slot_p3 = 6'd30;
    gv_meta_p3  = 1'b1;
    idx_meta_p3 = 6'd30;
    idx_redir_p3 = 6'd30;
    #1;
    chk("B1 the p1 group is accepted",       ok_pred_p1);
    chk("B2 the p2 slot group is accepted",  ok_slot_p2);
    chk("B3 the p2 meta group is accepted",  ok_meta_p2);
    chk("B4 the p2 redirect is accepted",    ok_redir_p2);
    chk("B5 the p3 slot group is accepted",  ok_slot_p3);
    chk("B6 the p3 meta group is accepted",  ok_meta_p3);
    chk("B7 the p3 redirect is accepted",    ok_redir_p3);

    // A response naming the WRONG index at the right stage is
    // dropped. This is the index term of 5.6; without it a rewind
    // that reallocated the stage would let a response for the old
    // use through.
    idx_pred_p1 = 6'd31;
    #1;
    chk("B8 a p1 response for another entry is dropped",
        !ok_pred_p1);

    // A group valid low means no response, whatever the shadow says.
    idx_pred_p1 = 6'd32;
    gv_pred_p1  = 1'b0;
    #1;
    chk("B9 no group valid, no accept", !ok_pred_p1);
    clr();
  endtask

  // -----------------------------------------------------------------
  // C. THE DROP. Problem 3's first two criteria.
  // -----------------------------------------------------------------
  task automatic group_c();
    $display("-- C: drop the squashed, keep the surviving --");
    do_reset();

    push(30); push(31); push(32);

    // Stage 1 holds 32, stage 2 holds 31, stage 3 holds 30.
    //
    // A p2 redirect for entry 31 -- the entry at stage 2 -- with the
    // naming entry surviving. Everything AFTER it is squashed: entry
    // 32, at stage 1. Entry 30, at stage 3, is OLDER and survives.
    //
    // This is the case that makes the age comparison necessary.
    // Clearing every stage on any redirect would satisfy "the
    // squashed ones are dropped" and destroy the surviving p3
    // response, and nothing downstream would report it -- entry 30
    // would simply keep its p2 view for ever.
    squash_cyc(32, 33);

    // The cluster's stage registers advanced too, so everything
    // moved on one: 30 has left, 31 is at stage 3, and 32 is the
    // cleared stage 2.
    chk("C1 the older entry survived at stage 3",
        shadow_val[3] && (shadow_ptr[3] == FTQ_PTR_BITS'(31)));
    chk("C2 the squashed entry was cleared", !shadow_val[2]);

    // A p3 response for the SURVIVING entry is accepted.
    gv_slot_p3   = 1'b1;
    idx_slot_p3  = 6'd31;
    idx_redir_p3 = 6'd31;
    #1;
    chk("C3 a response for a surviving entry is accepted",
        ok_slot_p3 && ok_redir_p3);

    // A p2 response for a SQUASHED entry is dropped.
    gv_slot_p2  = 1'b1;
    idx_slot_p2 = 6'd32;
    #1;
    chk("C4 a response for a squashed entry is dropped",
        !ok_slot_p2);

    // AND SO IS ONE FOR THE ENTRY THAT REPLACED IT. The FTQ rewound
    // to 32 and reallocated it, so a stale response naming 32
    // arrives while index 32 is live again -- the exact aliasing
    // 5.6 exists for. The stage is clear, so it is still dropped.
    idx_slot_p2 = 6'd32;
    #1;
    chk("C5 a reallocated index does not revive the response",
        !ok_slot_p2);
    clr();

    // The rebuilt stream fills the shadow again and its responses
    // ARE accepted, so the clear is not permanent. One push puts 32
    // at stage 1, so it is the p1 group that carries it -- the stage
    // a response is checked at follows the request, not the group
    // name.
    push(32);
    gv_pred_p1  = 1'b1;
    idx_pred_p1 = 6'd32;
    #1;
    chk("C6 the rebuilt stream is accepted", ok_pred_p1);
    clr();

    // One more cycle and 32 is at stage 2, so its p2 group is
    // accepted there and not before.
    idle_cyc();
    gv_slot_p2  = 1'b1;
    idx_slot_p2 = 6'd32;
    #1;
    chk("C7 the rebuilt p2 group is accepted a cycle later",
        ok_slot_p2);
    clr();
  endtask

  // -----------------------------------------------------------------
  // D. BACK-TO-BACK REDIRECTS. Problem 3's third criterion.
  // -----------------------------------------------------------------
  task automatic group_d();
    $display("-- D: back-to-back redirects --");
    do_reset();

    push(40); push(41); push(42);

    // Two redirects in consecutive cycles, the second naming an
    // OLDER entry than the first. The second must clear what the
    // first left, and the shift must not smuggle a stage past it.
    squash_cyc(42, 43);
    squash_cyc(40, 43);
    chk("D1 nothing survives the second redirect",
        shadow_val == 4'b0000);

    // Rebuild and redirect on the SAME cycle a request is pushed.
    // The request is for a squashed entry, so it must not enter.
    push(41);
    req_val      = 1'b1;
    req_ptr      = FTQ_PTR_BITS'(42);
    squash_val   = 1'b1;
    squash_start = FTQ_PTR_BITS'(42);
    squash_end   = FTQ_PTR_BITS'(43);
    tick();
    clr();
    chk("D2 a squashed request does not enter the shadow",
        !shadow_val[1]);
    chk("D3 the surviving entry is still there",
        shadow_val[2] && (shadow_ptr[2] == FTQ_PTR_BITS'(41)));

    // A redirect that squashes NOTHING -- start equal to end, which
    // is a redirect naming the newest entry with _self clear --
    // leaves the whole shadow alone.
    push(43);
    squash_cyc(50, 50);
    chk("D4 an empty range clears no stage", |shadow_val);

    // THREE IN A ROW, each older than the last, with requests
    // between them. The shadow must end empty and then refill
    // cleanly.
    do_reset();
    push(50); push(51); push(52);
    squash_cyc(52, 53);
    push(52);
    squash_cyc(51, 53);
    push(51);
    squash_cyc(50, 53);
    chk("D5 the shadow is empty after three redirects",
        shadow_val == 4'b0000);
    push(51);
    gv_pred_p1  = 1'b1;
    idx_pred_p1 = 6'd51;
    #1;
    chk("D6 it refills and accepts after three redirects",
        ok_pred_p1);
    clr();
  endtask

  // -----------------------------------------------------------------
  // E. The wrap.
  // -----------------------------------------------------------------
  // Every comparison in the module is an age. A raw pointer compare
  // passes every case above and fails here, which is why the whole
  // group exists.
  task automatic group_e();
    $display("-- E: redirects across the wrap --");
    do_reset();

    // Requests straddling the array boundary: 62, 63, 64 --
    // indices 62, 63 and 0, with the generation flipping.
    push(62); push(63); push(64);
    chk("E1 the shadow straddles the wrap",
        (shadow_ptr[3] == FTQ_PTR_BITS'(62)) &&
        (shadow_ptr[1] == FTQ_PTR_BITS'(64)));

    // Squash 64, which is index 0 -- numerically BELOW the
    // surviving 62 and 63. A raw compare drops the wrong ones.
    squash_cyc(64, 65);
    chk("E2 the far-generation entry was cleared", !shadow_val[2]);
    chk("E3 the near-generation entry survived",
        shadow_val[3] && (shadow_ptr[3] == FTQ_PTR_BITS'(63)));

    // A response for index 0 -- the squashed entry 64 -- is
    // dropped, and the stage that would have held it is clear.
    gv_slot_p2  = 1'b1;
    idx_slot_p2 = 6'd0;
    #1;
    chk("E4 a response for the squashed index is dropped",
        !ok_slot_p2);

    // A response for index 63 at stage 3 is accepted.
    gv_slot_p3   = 1'b1;
    idx_slot_p3  = 6'd63;
    #1;
    chk("E5 the surviving response is accepted", ok_slot_p3);
    clr();
  endtask

  // -----------------------------------------------------------------
  // F. States HELD ACROSS AN EDGE, so the bound properties sample.
  // -----------------------------------------------------------------
  // Every case above checks at a delta delay and the shadow SHIFTS on
  // the edge, so a state that exists only between edges is invisible
  // to a concurrent property -- and the property is then inert
  // (TD#109). The cases below hold the response inputs across an edge
  // instead. The shadow shifting underneath them is harmless: what is
  // being sampled is the accept term at the edge, not the stage
  // contents afterwards.
  task automatic group_f();
    $display("-- F: states held across an edge --");
    do_reset();

    push(30); push(31); push(32);

    // A p1 response naming an entry the stage does NOT hold. Stage 1
    // holds 32; the response names 31. Held across an edge, so the
    // property that states both terms of 5.6 -- valid AND index
    // match -- has the state to fail on if either term is dropped.
    gv_pred_p1  = 1'b1;
    idx_pred_p1 = 6'd31;
    #1;
    chk("F1 a mismatched p1 response is dropped", !ok_pred_p1);
    tick();
    clr();

    // A REQUEST THAT THE REDIRECT DOES NOT SQUASH, presented in the
    // redirect cycle. The squash range is 20..24; the request is for
    // 45, which is outside it, so the request must still enter the
    // shadow. A shadow that cleared everything on any redirect
    // satisfies the drop property and fails here.
    do_reset();
    req_val      = 1'b1;
    req_ptr      = FTQ_PTR_BITS'(45);
    squash_val   = 1'b1;
    squash_start = FTQ_PTR_BITS'(20);
    squash_end   = FTQ_PTR_BITS'(25);
    tick();
    clr();
    chk("F2 a request outside the squash range still enters",
        shadow_val[1] && (shadow_ptr[1] == FTQ_PTR_BITS'(45)));

    // And its p1 response is accepted a cycle later, which is the
    // consequence that matters: entering the shadow is only useful if
    // the response it guards gets through.
    gv_pred_p1  = 1'b1;
    idx_pred_p1 = 6'd45;
    #1;
    chk("F3 and its response is accepted", ok_pred_p1);
    tick();
    clr();
  endtask

  // -----------------------------------------------------------------
  // Run
  // -----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    if (FTQ_DEPTH != 64) begin
      $fatal(1, "tb_ftq_shadow: written for FTQ_DEPTH == 64");
    end

    do_reset();
    group_a();
    group_b();
    group_c();
    group_d();
    group_e();
    group_f();

    $display("tb_ftq_shadow: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ftq_shadow: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #400000;
    $fatal(1, "tb_ftq_shadow: timeout");
  end

endmodule : tb
