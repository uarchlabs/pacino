// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ftq_npc (BP-107), ftq_decisions.md 4.
//
// Self-checking. Problem 4's four acceptance criteria:
//
//   each arm of 4.2 wins against every LOWER-priority arm presented
//   in the same cycle          -> group C, exhaustively
//   the reset vector is issued first
//                              -> group A
//   H1 and H2 hold the request without losing it
//                              -> group D
//   the p1 successor is combinational
//                              -> group B, and see below
//
// HOW THE COMBINATIONAL PATH IS CONFIRMED, and it is the point of
// this file. Group B drives the p1 group and reads ftq_pred_pc_p0
// WITHOUT AN INTERVENING CLOCK EDGE. The stimulus changes at some
// time t, the check runs at t + 1 time unit, and no posedge occurs
// between them. A registered implementation still shows the previous
// PC at that moment and fails; only a combinational path can have
// the new successor there.
//
// B7 makes the same point the other way: the value present before
// the p1 group arrives is checked to be DIFFERENT, so B3 cannot pass
// by the output already happening to hold the expected address. A
// test that only checked the value after the edge would pass on a
// registered build, which is exactly the trap Binding Decision 3
// names.
//
// Property N4 in ftq_npc_assert.sv states the same fact as a
// same-cycle SVA implication and runs on every cycle of this file.
// The two are independent: N4 would catch a registered path in any
// testbench, and group B catches it with no assertions elaborated.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  logic                    bkend_redir_val;
  logic [FTQ_IDX_BITS-1:0] bkend_redir_idx;
  logic [VA_WIDTH-1:0]     bkend_redir_pc;
  logic                    bkend_redir_self;
  ftq_redir_cause_e        bkend_redir_cause;
  logic                    pd_redir_val;
  logic [FTQ_IDX_BITS-1:0] pd_redir_idx;
  logic [VA_WIDTH-1:0]     pd_redir_pc;
  logic                    p3_redir_val;
  logic [FTQ_IDX_BITS-1:0] p3_redir_idx;
  bp_redirect_t            p3_redir [0:NUM_PRED_SLOTS-1];
  logic                    p2_redir_val;
  logic [FTQ_IDX_BITS-1:0] p2_redir_idx;
  bp_redirect_t            p2_redir [0:NUM_PRED_SLOTS-1];
  logic                    p1_val;
  bp_ftq_slot_t            p1_slot [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0]     p1_pft_addr;
  logic                    tage_pq_not_full;
  logic                    ittage_pq_not_full;
  logic                    sc_uq_not_full;
  logic                    h2_ftq_full;
  logic                    r1_fault_hold;
  logic                    ftq_pred_val_p0;
  logic [VA_WIDTH-1:0]     ftq_pred_pc_p0;
  logic [VA_WIDTH-1:0]     pred_pc_p1;
  logic                    redir_val;
  logic [FTQ_IDX_BITS-1:0] redir_idx;
  logic                    redir_self;
  ftq_redir_cause_e        redir_cause;
  logic                    rollback_val;
  logic [FTQ_IDX_BITS-1:0] rollback_idx;
  logic [5:1]              arm_win;

  ftq_npc dut (
    .clk                (clk),
    .rstn               (rstn),
    .bkend_redir_val    (bkend_redir_val),
    .bkend_redir_idx    (bkend_redir_idx),
    .bkend_redir_pc     (bkend_redir_pc),
    .bkend_redir_self   (bkend_redir_self),
    .bkend_redir_cause  (bkend_redir_cause),
    .pd_redir_val       (pd_redir_val),
    .pd_redir_idx       (pd_redir_idx),
    .pd_redir_pc        (pd_redir_pc),
    .p3_redir_val       (p3_redir_val),
    .p3_redir_idx       (p3_redir_idx),
    .p3_redir           (p3_redir),
    .p2_redir_val       (p2_redir_val),
    .p2_redir_idx       (p2_redir_idx),
    .p2_redir           (p2_redir),
    .p1_val             (p1_val),
    .p1_slot            (p1_slot),
    .p1_pft_addr        (p1_pft_addr),
    .tage_pq_not_full   (tage_pq_not_full),
    .ittage_pq_not_full (ittage_pq_not_full),
    .sc_uq_not_full     (sc_uq_not_full),
    .h2_ftq_full        (h2_ftq_full),
    .r1_fault_hold      (r1_fault_hold),
    .ftq_pred_val_p0    (ftq_pred_val_p0),
    .ftq_pred_pc_p0     (ftq_pred_pc_p0),
    .pred_pc_p1         (pred_pc_p1),
    .redir_val          (redir_val),
    .redir_idx          (redir_idx),
    .redir_self         (redir_self),
    .redir_cause        (redir_cause),
    .rollback_val       (rollback_val),
    .rollback_idx       (rollback_idx),
    .arm_win            (arm_win)
  );

  // The five arm addresses, distinct so a check that reads the
  // wrong arm reads a recognisable value.
  localparam logic [VA_WIDTH-1:0] PC_BKEND = 40'h00_1000_0000;
  localparam logic [VA_WIDTH-1:0] PC_PD    = 40'h00_2000_0000;
  localparam logic [VA_WIDTH-1:0] PC_P3    = 40'h00_3000_0000;
  localparam logic [VA_WIDTH-1:0] PC_P2    = 40'h00_4000_0000;
  localparam logic [VA_WIDTH-1:0] PC_S0    = 40'h00_5000_0000;
  localparam logic [VA_WIDTH-1:0] PC_S1    = 40'h00_6000_0000;
  localparam logic [VA_WIDTH-1:0] PC_PFT   = 40'h00_7000_0000;

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

  task automatic chk_va(input string nm,
                        input logic [VA_WIDTH-1:0] got,
                        input logic [VA_WIDTH-1:0] exp);
    if (got === exp) begin
      pass_cnt++;
      $display("PASS: %s", nm);
    end else begin
      fail_cnt++;
      $display("FAIL: %s  got %010h exp %010h", nm, got, exp);
    end
  endtask

  task automatic tick();
    @(posedge clk);
    #1;
  endtask

  task automatic clr();
    bkend_redir_val = 1'b0;
    pd_redir_val    = 1'b0;
    p3_redir_val    = 1'b0;
    p2_redir_val    = 1'b0;
    p1_val          = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      p2_redir[s].valid = 1'b0;
      p3_redir[s].valid = 1'b0;
      p1_slot[s]        = '0;
    end
  endtask

  task automatic no_hold();
    tage_pq_not_full   = 1'b1;
    ittage_pq_not_full = 1'b1;
    sc_uq_not_full     = 1'b1;
    h2_ftq_full        = 1'b0;
    r1_fault_hold      = 1'b0;
  endtask

  task automatic do_reset();
    rstn              = 1'b0;
    bkend_redir_idx   = '0;
    bkend_redir_pc    = PC_BKEND;
    bkend_redir_self  = 1'b0;
    bkend_redir_cause = RC_MISPREDICT;
    pd_redir_idx      = '0;
    pd_redir_pc       = PC_PD;
    p3_redir_idx      = '0;
    p2_redir_idx      = '0;
    p1_pft_addr       = PC_PFT;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      p2_redir[s].target_pc = PC_P2;
      p3_redir[s].target_pc = PC_P3;
    end
    clr();
    no_hold();
    repeat (4) tick();
    rstn = 1'b1;
    settle();
  endtask

  // Drive a p1 group with one taken slot, or none.
  task automatic set_p1(input int taken_slot);
    p1_val = 1'b1;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      p1_slot[s]            = '0;
      p1_slot[s].slot_valid = 1'b1;
      p1_slot[s].taken      = 1'b0;
      p1_slot[s].br_type    = COND;
      p1_slot[s].target     = (s == 0) ? PC_S0 : PC_S1;
    end
    if (taken_slot >= 0) p1_slot[taken_slot].taken = 1'b1;
  endtask


  // PRESENT THE STIMULUS ACROSS A CLOCK EDGE, so the properties bound
  // to ftq_npc SAMPLE it. A concurrent property samples at posedge
  // clk; a case that drives its inputs, checks with a delta delay and
  // moves on never presents that state at an edge, and the property
  // is then inert (TD#109).
  //
  // GROUP B DOES NOT USE THIS, and must not. Its checks read
  // ftq_pred_pc_p0 with NO intervening edge, which is what makes them
  // a proof that the successor path is combinational rather than
  // registered. Crossing an edge there would let a registered
  // implementation pass. Arm 5 is still sampled by the properties --
  // group C presents it in every pair of the priority loop.
  task automatic settle();
    #1;
    @(posedge clk);
    #1;
  endtask
  // -----------------------------------------------------------------
  // A. Arm 0, the reset vector.
  // -----------------------------------------------------------------
  // ACCEPTANCE: the reset vector is issued first.
  task automatic group_a();
    $display("-- A: the reset vector --");
    do_reset();

    chk_va("A1 the reset vector is on the port", ftq_pred_pc_p0,
           RESET_VECTOR);
    chk   ("A2 and it is REQUESTED, not merely held",
           ftq_pred_val_p0);
    chk   ("A3 no arm won, so this is arm 0 held by arm 6",
           arm_win == '0);
    chk   ("A4 no redirect at reset", !redir_val);

    // It is block aligned, which the FTB and the uBTB both index on
    // (4.7). An unaligned reset vector makes the first fetch a
    // partial block.
    chk("A5 the reset vector is block aligned",
        (RESET_VECTOR[FTB_OFFSET_BITS-1:0] == '0));

    // It survives idle cycles: the hold arm retains it rather than
    // letting the register drift.
    repeat (5) tick();
    chk_va("A6 the reset vector is retained while idle",
           ftq_pred_pc_p0, RESET_VECTOR);
    chk   ("A7 still requested", ftq_pred_val_p0);
  endtask

  // -----------------------------------------------------------------
  // B. Arm 5, and THE COMBINATIONAL PATH.
  // -----------------------------------------------------------------
  task automatic group_b();
    $display("-- B: the p1 successor, combinational --");
    do_reset();

    // Establish the value present BEFORE the p1 group arrives, and
    // check it is not any of the successor addresses. Without this
    // B3 could pass by coincidence on a registered build.
    chk_va("B1 the pre-p1 value is the reset vector",
           ftq_pred_pc_p0, RESET_VECTOR);
    chk("B2 and it is not the successor under test",
        ftq_pred_pc_p0 !== PC_S0);

    // DRIVE THE p1 GROUP AND READ THE OUTPUT WITH NO CLOCK EDGE
    // BETWEEN. #1 advances one time unit; the clock period is 10
    // and the last edge was 1 time unit ago, so no posedge occurs.
    set_p1(0);
    #1;
    chk_va("B3 slot 0 taken selects its target, SAME CYCLE",
           ftq_pred_pc_p0, PC_S0);
    chk   ("B4 arm 5 won", arm_win[5]);
    chk   ("B5 no redirect is published on arm 5", !redir_val);

    // Change the p1 group again, still with no edge. The output
    // must follow within the cycle.
    set_p1(1);
    #1;
    chk_va("B6 slot 1 taken selects its target, SAME CYCLE",
           ftq_pred_pc_p0, PC_S1);

    // fe_decisions.md 2.4 is priority ordered: slot 0 first. With
    // BOTH taken, slot 0 wins -- a taken branch ends the block, so
    // slot 1 is off the path.
    set_p1(0);
    p1_slot[1].taken = 1'b1;
    #1;
    chk_va("B7 both taken, slot 0 wins", ftq_pred_pc_p0, PC_S0);

    // Neither taken: the fall-through, which arrives on
    // bpu_pred_pft_p1 and is the third arm of 2.4.
    set_p1(-1);
    #1;
    chk_va("B8 neither taken, the fall-through",
           ftq_pred_pc_p0, PC_PFT);

    // A VALID SLOT THAT IS NOT TAKEN does not supply the successor,
    // and an INVALID slot marked taken does not either. Both are
    // reachable: the p1 view can mark a slot valid and not taken,
    // and a slot the uBTB missed carries no valid.
    set_p1(-1);
    p1_slot[0].slot_valid = 1'b0;
    p1_slot[0].taken      = 1'b1;
    #1;
    chk_va("B9 an invalid slot is not selected even if taken",
           ftq_pred_pc_p0, PC_PFT);

    // THE LOOP CLOSES ACROSS A CYCLE. The successor presented at p0
    // becomes the next block's start PC, and pred_pc_p1 carries it
    // to the entry write.
    set_p1(0);
    #1;
    chk_va("B10 the successor is presented", ftq_pred_pc_p0, PC_S0);
    tick();
    chk_va("B11 pred_pc_p1 carries it to the entry write",
           pred_pc_p1, PC_S0);
    clr();
  endtask

  // -----------------------------------------------------------------
  // C. The priority of 4.2, exhaustively.
  // -----------------------------------------------------------------
  // ACCEPTANCE: each arm wins against EVERY lower-priority arm
  // presented in the same cycle. The loop below presents arm i and
  // every arm below it together, for every i, so no pair is left
  // untested and no arm is tested only against its immediate
  // neighbour.
  task automatic drive_arm(input int a);
    case (a)
      1: begin
        bkend_redir_val = 1'b1;
        bkend_redir_idx = 6'd11;
      end
      2: begin
        pd_redir_val = 1'b1;
        pd_redir_idx = 6'd12;
      end
      3: begin
        p3_redir_val      = 1'b1;
        p3_redir_idx      = 6'd13;
        p3_redir[0].valid = 1'b1;
      end
      4: begin
        p2_redir_val      = 1'b1;
        p2_redir_idx      = 6'd14;
        p2_redir[0].valid = 1'b1;
      end
      5: set_p1(0);
      default: ;
    endcase
  endtask

  function automatic logic [VA_WIDTH-1:0] arm_pc(input int a);
    case (a)
      1:       return PC_BKEND;
      2:       return PC_PD;
      3:       return PC_P3;
      4:       return PC_P2;
      5:       return PC_S0;
      default: return '0;
    endcase
  endfunction

  task automatic group_c();
    $display("-- C: the 4.2 priority, every pair --");
    do_reset();

    for (int hi = 1; hi <= 5; hi++) begin
      for (int lo = hi + 1; lo <= 5; lo++) begin
        clr();
        drive_arm(hi);
        drive_arm(lo);
        settle();
        chk($sformatf("C arm %0d beats arm %0d", hi, lo),
            arm_win[hi] && (ftq_pred_pc_p0 === arm_pc(hi)));
      end
    end

    // ALL FIVE AT ONCE. The backend takes it, unconditionally and
    // without comparison.
    clr();
    for (int a = 1; a <= 5; a++) drive_arm(a);
    settle();
    chk   ("C1 all five presented, the backend wins", arm_win[1]);
    chk_va("C2 and its PC is the one issued", ftq_pred_pc_p0,
           PC_BKEND);
    chk   ("C3 exactly one arm won", $onehot(arm_win));

    // The redirect published is the winner's, not a merge of them.
    chk("C4 the published index is the backend's",
        redir_idx == 6'd11);

    // A p2 GROUP VALID WITH NO SLOT VALID IS NOT A REDIRECT. The
    // group is presented on every prediction (FE-13); only a slot
    // whose successor differs actually resteers.
    clr();
    p2_redir_val = 1'b1;
    p2_redir_idx = 6'd14;
    set_p1(0);
    settle();
    chk("C5 a p2 group with no slot valid is not a redirect",
        arm_win[5] && !redir_val);

    // AND A SLOT VALID WITH THE GROUP VALID LOW IS NOT EITHER. That
    // is the shadow having dropped the group: the response named a
    // squashed entry.
    clr();
    p2_redir_val      = 1'b0;
    p2_redir[0].valid = 1'b1;
    set_p1(0);
    settle();
    chk("C6 a shadow-dropped p2 group is not a redirect",
        arm_win[5] && !redir_val);
    clr();
  endtask

  // -----------------------------------------------------------------
  // D. H1 and H2, the holds of 4.5.
  // -----------------------------------------------------------------
  // ACCEPTANCE: H1 and H2 hold the request WITHOUT LOSING IT.
  task automatic group_d();
    $display("-- D: the hold conditions --");
    do_reset();

    // Establish a non-reset PC so the retention check is not
    // comparing against the reset value.
    set_p1(1);
    settle();
    tick();
    clr();
    settle();
    chk_va("D1 the PC advanced off the reset vector",
           ftq_pred_pc_p0, PC_S1);
    chk("D2 requested with no hold", ftq_pred_val_p0);

    // H1, each of the three queues in turn. 4.5 names all three and
    // any one of them holds.
    tage_pq_not_full = 1'b0;
    settle();
    chk   ("D3 H1 tage deasserts the request", !ftq_pred_val_p0);
    chk_va("D4 and the PC is retained", ftq_pred_pc_p0, PC_S1);
    no_hold();

    ittage_pq_not_full = 1'b0;
    settle();
    chk("D5 H1 ittage deasserts the request", !ftq_pred_val_p0);
    no_hold();

    sc_uq_not_full = 1'b0;
    settle();
    chk("D6 H1 sc deasserts the request", !ftq_pred_val_p0);
    no_hold();

    // H2.
    h2_ftq_full = 1'b1;
    settle();
    chk   ("D7 H2 full deasserts the request", !ftq_pred_val_p0);
    chk_va("D8 and the PC is retained", ftq_pred_pc_p0, PC_S1);

    // THE PC SURVIVES A LONG HOLD. This is the half a naive
    // implementation loses: deasserting the valid while letting the
    // register capture something else drops a block from the stream
    // with no other symptom.
    repeat (10) tick();
    chk_va("D9 the PC survives ten held cycles",
           ftq_pred_pc_p0, PC_S1);
    no_hold();
    settle();
    chk   ("D10 the request resumes", ftq_pred_val_p0);
    chk_va("D11 with the PC it was holding", ftq_pred_pc_p0, PC_S1);

    // R1, the fault hold of ftq_entry_formats.md 4.3. NOT one of
    // 4.5's two, and it is reported as a documentation gap; it is
    // built because the entry formats document specifies it.
    r1_fault_hold = 1'b1;
    settle();
    chk   ("D12 R1 fault holds the request", !ftq_pred_val_p0);
    chk_va("D13 and retains the PC", ftq_pred_pc_p0, PC_S1);
    no_hold();

    // A REDIRECT IS PRESENTED DURING A HOLD. The hold gates the
    // REQUEST, not the arbitration: a backend redirect that arrived
    // while the FTQ was full must still load the corrected PC, or
    // the FTQ resumes fetching the squashed stream.
    h2_ftq_full     = 1'b1;
    bkend_redir_val = 1'b1;
    settle();
    chk   ("D14 the request is still held", !ftq_pred_val_p0);
    chk_va("D15 but the redirect PC is selected",
           ftq_pred_pc_p0, PC_BKEND);
    chk   ("D16 and the redirect is published", redir_val);
    tick();
    clr();
    no_hold();
    settle();
    chk_va("D17 the corrected PC is what resumes",
           ftq_pred_pc_p0, PC_BKEND);
  endtask

  // -----------------------------------------------------------------
  // E. The restore, D1 and D2 of backend_interfaces 5.
  // -----------------------------------------------------------------
  task automatic group_e();
    $display("-- E: the rollback index and RC_UNSPEC --");
    do_reset();

    // _self CLEAR: the naming entry completed and survives, so the
    // pointer state to restore is its own.
    bkend_redir_val   = 1'b1;
    bkend_redir_idx   = 6'd20;
    bkend_redir_self  = 1'b0;
    bkend_redir_cause = RC_MISPREDICT;
    settle();
    chk("E1 a restore is requested",           rollback_val);
    chk("E2 _self clear names the entry itself",
        rollback_idx == 6'd20);

    // _self SET: the naming entry is squashed too, so it is the one
    // BEFORE it. This derivation is the FTQ's work -- the cluster
    // applies the index it is given and does not validate it.
    bkend_redir_self = 1'b1;
    settle();
    chk("E3 _self set names the entry before", rollback_idx == 6'd19);

    // ACROSS THE WRAP. Index 0 with _self set is index 63, not a
    // negative number.
    bkend_redir_idx = 6'd0;
    settle();
    chk("E4 _self set wraps to 63", rollback_idx == 6'd63);

    // RC_TRAP and RC_REPLAY restore too. D1, D2 and D4 apply to all
    // three instruction-naming causes.
    bkend_redir_self  = 1'b0;
    bkend_redir_idx   = 6'd7;
    bkend_redir_cause = RC_TRAP;
    settle();
    chk("E5 RC_TRAP restores",   rollback_val);
    bkend_redir_cause = RC_REPLAY;
    settle();
    chk("E6 RC_REPLAY restores", rollback_val);

    // RC_UNSPEC DOES NOT. U5: it names no entry to restore from,
    // and both structures are self-correcting from committed state.
    bkend_redir_cause = RC_UNSPEC;
    settle();
    chk("E7 RC_UNSPEC performs no restore", !rollback_val);
    chk("E8 but it still redirects",         redir_val);
    chk("E9 and it still selects its PC",
        ftq_pred_pc_p0 === PC_BKEND);
    chk("E10 and its cause is published",
        redir_cause == RC_UNSPEC);

    // The three speculative arms all restore, and all carry _self
    // clear by construction: a p2, p3 or predecode correction
    // repairs the naming entry and it survives.
    clr();
    pd_redir_val = 1'b1;
    pd_redir_idx = 6'd31;
    settle();
    chk("E11 predecode restores",           rollback_val);
    chk("E12 naming its own entry",         rollback_idx == 6'd31);
    chk("E13 and its cause is RC_MISPREDICT",
        redir_cause == RC_MISPREDICT);

    clr();
    p3_redir_val      = 1'b1;
    p3_redir_idx      = 6'd32;
    p3_redir[1].valid = 1'b1;
    settle();
    chk("E14 a p3 redirect from slot 1 restores",
        rollback_val && (rollback_idx == 6'd32));
    chk("E15 and takes that slot's target",
        ftq_pred_pc_p0 === PC_P3);
    clr();
  endtask

  // -----------------------------------------------------------------
  // Run
  // -----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    if (NUM_PRED_SLOTS != 2) begin
      $fatal(1, "tb_ftq_npc: written for NUM_PRED_SLOTS == 2");
    end

    do_reset();
    group_a();
    group_b();
    group_c();
    group_d();
    group_e();

    $display("tb_ftq_npc: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ftq_npc: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #400000;
    $fatal(1, "tb_ftq_npc: timeout");
  end

endmodule : tb
