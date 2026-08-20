// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ftq_ftb_sched (BP-100).
//
// Self-checking. Every case establishes its start state by reset
// plus a known driven sequence; the module holds a skid register and
// nothing else, so no table needs invalidating.
//
// The five concurrent properties of ftq_decisions.md 5.7.4 are bound
// to the DUT by module name and run alongside these cases. The
// directed checks below cover the DATAPATH -- which update issues,
// in what order, with what payload -- and leave the drop and stall
// rules to the properties, which is the division 5.7.4 describes.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  localparam int NCH = 2;

  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  logic [NCH-1:0] upd_val;
  ftb_upd_t       upd [0:NCH-1];
  logic [NCH-1:0] upd_hit;
  logic [NCH-1:0] upd_mispred;
  logic [NCH-1:0] upd_rdy;

  logic                        ftb_upd_valid_u0;
  logic [VA_WIDTH-1:0]         ftb_upd_pc_u0;
  logic                        ftb_upd_hit_u0;
  logic [FTB_WAY_BITS-1:0]     ftb_upd_way_u0;
  logic                        ftb_upd_is_br_u0;
  logic                        ftb_upd_br_idx_u0;
  logic                        ftb_upd_taken_u0;
  logic [VA_WIDTH-1:0]         ftb_upd_target_u0;
  logic [FTB_BR_POS_BITS-1:0]  ftb_upd_pos_u0;
  logic                        ftb_upd_is_jmp_u0;
  logic [VA_WIDTH-1:0]         ftb_upd_jmp_target_u0;
  logic                        ftb_upd_is_call_u0;
  logic                        ftb_upd_is_ret_u0;
  logic                        ftb_upd_is_jalr_u0;
  logic [VA_WIDTH-1:0]         ftb_upd_pft_addr_u0;

  logic                        ftb_upd_from_skid;
  logic                        skid_val;
  logic                        skid_wr;
  logic                        skid_issue;
  logic                        drop_val;
  logic                        drop_is_high;
  logic [$clog2(NCH+2)-1:0]    n_acc_ftb;
  logic [$clog2(NCH+2)-1:0]    n_pend_ftb;
  logic                        any_pend_high;

  ftq_ftb_sched #(
    .NUM_UPD_CHAN (NCH)
  ) dut (
    .clk                   (clk),
    .rstn                  (rstn),
    .upd_val               (upd_val),
    .upd                   (upd),
    .upd_hit               (upd_hit),
    .upd_mispred           (upd_mispred),
    .upd_rdy               (upd_rdy),
    .ftb_upd_valid_u0      (ftb_upd_valid_u0),
    .ftb_upd_pc_u0         (ftb_upd_pc_u0),
    .ftb_upd_hit_u0        (ftb_upd_hit_u0),
    .ftb_upd_way_u0        (ftb_upd_way_u0),
    .ftb_upd_is_br_u0      (ftb_upd_is_br_u0),
    .ftb_upd_br_idx_u0     (ftb_upd_br_idx_u0),
    .ftb_upd_taken_u0      (ftb_upd_taken_u0),
    .ftb_upd_target_u0     (ftb_upd_target_u0),
    .ftb_upd_pos_u0        (ftb_upd_pos_u0),
    .ftb_upd_is_jmp_u0     (ftb_upd_is_jmp_u0),
    .ftb_upd_jmp_target_u0 (ftb_upd_jmp_target_u0),
    .ftb_upd_is_call_u0    (ftb_upd_is_call_u0),
    .ftb_upd_is_ret_u0     (ftb_upd_is_ret_u0),
    .ftb_upd_is_jalr_u0    (ftb_upd_is_jalr_u0),
    .ftb_upd_pft_addr_u0   (ftb_upd_pft_addr_u0),
    .ftb_upd_from_skid     (ftb_upd_from_skid),
    .skid_val              (skid_val),
    .skid_wr               (skid_wr),
    .skid_issue            (skid_issue),
    .drop_val              (drop_val),
    .drop_is_high          (drop_is_high),
    .n_acc_ftb             (n_acc_ftb),
    .n_pend_ftb            (n_pend_ftb),
    .any_pend_high         (any_pend_high)
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

  // -----------------------------------------------------------------
  // Stimulus helpers
  // -----------------------------------------------------------------
  task automatic tick();
    @(posedge clk);
    #1;
  endtask

  task automatic clr();
    upd_val     = '0;
    upd_hit     = '0;
    upd_mispred = '0;
    for (int c = 0; c < NCH; c++) upd[c] = '0;
  endtask

  task automatic do_reset();
    rstn = 1'b0;
    clr();
    repeat (4) tick();
    rstn = 1'b1;
    repeat (2) tick();
  endtask

  // Present one update on a channel. `high` selects the value class
  // of 5.7.2 through the two value bits: a HIGH update is built as a
  // predict-time MISS, a LOW one as a hit that predicted correctly.
  // `bound` selects S1: a bound update carries a branch field, an
  // unbound one carries neither and is not FTB-bound at all.
  task automatic drive(input int c,
                       input logic [VA_WIDTH-1:0] pc,
                       input logic high,
                       input logic bound);
    upd_val[c]     = 1'b1;
    upd[c]         = '0;
    upd[c].pc      = pc;
    upd[c].is_br   = bound;
    upd[c].target  = pc + 40'h100;
    upd[c].pos     = 4'd3;
    upd[c].hit     = ~high;
    upd_hit[c]     = ~high;
    upd_mispred[c] = 1'b0;
  endtask

  // -----------------------------------------------------------------
  // Cases
  // -----------------------------------------------------------------
  task automatic group_a();
    $display("---- GROUP A: bring-up ----");
    do_reset();
    chk("A1 no update issues out of reset",
        ftb_upd_valid_u0 === 1'b0);
    chk("A1 the skid is empty out of reset", skid_val === 1'b0);
    chk("A1 nothing is dropped out of reset", drop_val === 1'b0);
    chk("A1 both channels are ready out of reset",
        upd_rdy === 2'b11);
    chk("A1 no update is pending out of reset", n_pend_ftb === '0);
    $display("---- GROUP A done (pass %0d fail %0d) ----",
             pass_cnt, fail_cnt);
  endtask

  task automatic group_b();
    $display("---- GROUP B: the lone update, P1 ----");
    do_reset();

    // -- B1. One FTB-bound update, skid empty. It issues, one cycle
    //    later, because the output is registered. This is the P1
    //    case driven directly.
    drive(0, 40'h00_1000_0000, 1'b0, 1'b1);
    #1;
    chk("B1 the channel is accepted", n_acc_ftb === 'd1);
    chk("B1 the skid is empty", skid_val === 1'b0);
    chk("B1 nothing is dropped", drop_val === 1'b0);
    chk("B1 no output yet, the issue is registered",
        ftb_upd_valid_u0 === 1'b0);
    tick();
    clr();
    chk("B1 the update issues the next cycle",
        ftb_upd_valid_u0 === 1'b1);
    chk("B1 it did not come from the skid",
        ftb_upd_from_skid === 1'b0);
    chk_eq("B1 the payload pc flattened out",
           ftb_upd_pc_u0, 40'h00_1000_0000);
    chk("B1 nothing was retained", skid_val === 1'b0);
    tick();
    chk("B1 the output falls after one cycle",
        ftb_upd_valid_u0 === 1'b0);

    // -- B2. Payload integrity. Every one of the 14 fields must
    //    flatten out unchanged, not just the pc.
    do_reset();
    upd_val[0]            = 1'b1;
    upd[0].pc             = 40'h00_2000_0000;
    upd[0].hit            = 1'b1;
    upd[0].way            = 2'd2;
    upd[0].is_br          = 1'b1;
    upd[0].br_idx         = 1'b1;
    upd[0].taken          = 1'b1;
    upd[0].target         = 40'h00_2000_0300;
    upd[0].pos            = 4'd9;
    upd[0].is_jmp         = 1'b1;
    upd[0].jmp_target     = 40'h00_2000_0400;
    upd[0].is_call        = 1'b1;
    upd[0].is_ret         = 1'b0;
    upd[0].is_jalr        = 1'b1;
    upd[0].pft_addr       = 40'h00_2000_0020;
    upd_hit[0]            = 1'b1;
    upd_mispred[0]        = 1'b0;
    tick();
    clr();
    chk("B2 valid", ftb_upd_valid_u0 === 1'b1);
    chk_eq("B2 pc", ftb_upd_pc_u0, 40'h00_2000_0000);
    chk("B2 hit", ftb_upd_hit_u0 === 1'b1);
    chk("B2 way", ftb_upd_way_u0 === 2'd2);
    chk("B2 is_br", ftb_upd_is_br_u0 === 1'b1);
    chk("B2 br_idx", ftb_upd_br_idx_u0 === 1'b1);
    chk("B2 taken", ftb_upd_taken_u0 === 1'b1);
    chk_eq("B2 target", ftb_upd_target_u0, 40'h00_2000_0300);
    chk("B2 pos", ftb_upd_pos_u0 === 4'd9);
    chk("B2 is_jmp", ftb_upd_is_jmp_u0 === 1'b1);
    chk_eq("B2 jmp_target", ftb_upd_jmp_target_u0,
           40'h00_2000_0400);
    chk("B2 is_call", ftb_upd_is_call_u0 === 1'b1);
    chk("B2 is_ret", ftb_upd_is_ret_u0 === 1'b0);
    chk("B2 is_jalr", ftb_upd_is_jalr_u0 === 1'b1);
    chk_eq("B2 pft_addr", ftb_upd_pft_addr_u0, 40'h00_2000_0020);

    // -- B3. S1. An update that is FTB-bound in neither field is not
    //    scheduled at all: it consumes no capacity, is always ready,
    //    and never issues.
    do_reset();
    drive(0, 40'h00_3000_0000, 1'b0, 1'b0);   // is_br = 0, is_jmp = 0
    #1;
    chk("B3 an unbound update is not pending", n_pend_ftb === '0);
    chk("B3 an unbound update is not accepted", n_acc_ftb === '0);
    chk("B3 its channel stays ready", upd_rdy[0] === 1'b1);
    tick();
    clr();
    chk("B3 it never issues", ftb_upd_valid_u0 === 1'b0);
    chk("B3 it never enters the skid", skid_val === 1'b0);
    $display("---- GROUP B done (pass %0d fail %0d) ----",
             pass_cnt, fail_cnt);
  endtask

  task automatic group_c();
    $display("---- GROUP C: two channels, order and the skid ----");

    // -- C1. Two LOW updates with the skid empty. S3 issues one and
    //    S4 retains the other, so NOTHING is dropped: capacity with
    //    an empty skid is two. The tie is broken by channel index,
    //    which is program order within an entry (IC-FTB-16).
    do_reset();
    drive(0, 40'h00_4000_0000, 1'b0, 1'b1);
    drive(1, 40'h00_4100_0000, 1'b0, 1'b1);
    #1;
    chk("C1 both channels are accepted", n_acc_ftb === 'd2);
    chk("C1 both stay ready, nothing is held", upd_rdy === 2'b11);
    chk("C1 nothing is dropped with an empty skid",
        drop_val === 1'b0);
    chk("C1 one is retained", skid_wr === 1'b1);
    tick();
    clr();
    chk("C1 channel 0 issues first on a tie",
        ftb_upd_valid_u0 === 1'b1);
    chk_eq("C1 the issued payload is channel 0's",
           ftb_upd_pc_u0, 40'h00_4000_0000);
    chk("C1 channel 1 is now in the skid", skid_val === 1'b1);
    tick();
    chk("C1 the skid issues next", ftb_upd_valid_u0 === 1'b1);
    chk("C1 and reports that it came from the skid",
        ftb_upd_from_skid === 1'b1);
    chk_eq("C1 the skid payload is channel 1's",
           ftb_upd_pc_u0, 40'h00_4100_0000);
    chk("C1 the skid is empty again", skid_val === 1'b0);

    // -- C2. Value beats index. Channel 1 is HIGH and channel 0 is
    //    LOW, so channel 1 issues first even though channel 0 is
    //    earlier. A scheduler that ranked on index alone fails here.
    do_reset();
    drive(0, 40'h00_5000_0000, 1'b0, 1'b1);   // LOW
    drive(1, 40'h00_5100_0000, 1'b1, 1'b1);   // HIGH
    tick();
    clr();
    chk_eq("C2 the HIGH update issues first, not channel 0",
           ftb_upd_pc_u0, 40'h00_5100_0000);
    tick();
    chk_eq("C2 the LOW update follows out of the skid",
           ftb_upd_pc_u0, 40'h00_5000_0000);
    chk("C2 it came from the skid", ftb_upd_from_skid === 1'b1);
    $display("---- GROUP C done (pass %0d fail %0d) ----",
             pass_cnt, fail_cnt);
  endtask

  task automatic group_d();
    $display("---- GROUP D: S5 drop and S6 hold ----");

    // -- D1. S5. The skid is occupied and two LOW updates arrive.
    //    The skid issues (S3), the better new one is retained (S4),
    //    and the remaining LOW one is DROPPED (S5). This is FE-5a
    //    in one cycle: a routine conf step is lost rather than
    //    stalling resolution.
    do_reset();
    drive(0, 40'h00_6000_0000, 1'b0, 1'b1);
    drive(1, 40'h00_6100_0000, 1'b0, 1'b1);
    tick();                       // ch0 issues, ch1 retained
    clr();
    chk("D1 the skid is occupied", skid_val === 1'b1);
    drive(0, 40'h00_6200_0000, 1'b0, 1'b1);   // LOW
    drive(1, 40'h00_6300_0000, 1'b0, 1'b1);   // LOW
    #1;
    chk("D1 both LOW channels stay ready", upd_rdy === 2'b11);
    chk("D1 one of them is dropped", drop_val === 1'b1);
    chk("D1 the dropped update is LOW, never HIGH",
        drop_is_high === 1'b0);
    chk("D1 the skid still issues this cycle",
        skid_issue === 1'b1);
    tick();
    clr();
    chk_eq("D1 the skid entry issued, not a new one",
           ftb_upd_pc_u0, 40'h00_6100_0000);
    chk("D1 it came from the skid", ftb_upd_from_skid === 1'b1);
    chk_eq("D1 the better new update took the skid",
           dut.w_skid_pl.pc, 40'h00_6200_0000);

    // -- D2. S6. The same collision with both new updates HIGH. A
    //    HIGH update may not be dropped, so the lower-ranked channel
    //    is NOT accepted: its ready deasserts and the backend holds
    //    it. Nothing is dropped.
    do_reset();
    drive(0, 40'h00_7000_0000, 1'b0, 1'b1);
    drive(1, 40'h00_7100_0000, 1'b0, 1'b1);
    tick();                       // fill the skid
    clr();
    chk("D2 the skid is occupied", skid_val === 1'b1);
    drive(0, 40'h00_7200_0000, 1'b1, 1'b1);   // HIGH
    drive(1, 40'h00_7300_0000, 1'b1, 1'b1);   // HIGH
    #1;
    chk("D2 channel 0 is accepted", upd_rdy[0] === 1'b1);
    chk("D2 channel 1 is HELD rather than dropped",
        upd_rdy[1] === 1'b0);
    chk("D2 nothing is dropped", drop_val === 1'b0);
    chk("D2 only one new update is accepted",
        n_acc_ftb === 'd1);

    // -- D3. S6 is narrow. One HIGH and one LOW into an occupied
    //    skid: the HIGH is retained and the LOW is dropped, so
    //    NEITHER channel is held. A scheduler that held on any
    //    collision would stall resolution here and fail P5's intent.
    do_reset();
    drive(0, 40'h00_8000_0000, 1'b0, 1'b1);
    drive(1, 40'h00_8100_0000, 1'b0, 1'b1);
    tick();                       // fill the skid
    clr();
    drive(0, 40'h00_8200_0000, 1'b0, 1'b1);   // LOW
    drive(1, 40'h00_8300_0000, 1'b1, 1'b1);   // HIGH
    #1;
    chk("D3 neither channel is held", upd_rdy === 2'b11);
    chk("D3 the LOW update is dropped", drop_val === 1'b1);
    chk("D3 the dropped one is not HIGH", drop_is_high === 1'b0);
    tick();
    clr();
    chk_eq("D3 the HIGH update was the one retained",
           dut.w_skid_pl.pc, 40'h00_8300_0000);
    $display("---- GROUP D done (pass %0d fail %0d) ----",
             pass_cnt, fail_cnt);
  endtask

  task automatic group_e();
    int held;

    $display("---- GROUP E: steady state, P5 ----");

    // -- E1. The throughput claim of 5.7.1. A sustained stream of
    //    LOW updates on both channels must never deassert a ready:
    //    training pressure must not reach the backend. Run it long
    //    enough that the skid is occupied for most of the run.
    do_reset();
    held = 0;
    for (int i = 0; i < 64; i++) begin
      drive(0, 40'h00_9000_0000 + (i << 8), 1'b0, 1'b1);
      drive(1, 40'h00_9800_0000 + (i << 8), 1'b0, 1'b1);
      #1;
      if (upd_rdy !== 2'b11) held++;
      tick();
    end
    clr();
    chk("E1 a sustained all-LOW stream never held a channel",
        held == 0);

    // -- E2. The contrast. A sustained stream of HIGH updates on
    //    both channels DOES hold one channel, which is S6 working:
    //    correctness is bought with backpressure, and only here.
    do_reset();
    held = 0;
    for (int i = 0; i < 16; i++) begin
      drive(0, 40'h00_A000_0000 + (i << 8), 1'b1, 1'b1);
      drive(1, 40'h00_A800_0000 + (i << 8), 1'b1, 1'b1);
      #1;
      if (upd_rdy !== 2'b11) held++;
      tick();
    end
    clr();
    chk("E2 a sustained all-HIGH stream does hold a channel",
        held > 0);
    $display("---- GROUP E done (pass %0d fail %0d) ----",
             pass_cnt, fail_cnt);
  endtask

  // -----------------------------------------------------------------
  // Main
  // -----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    if (NCH != 2) begin
      $fatal(1, "tb_ftq_ftb_sched: written for NCH == 2, got %0d",
             NCH);
    end

    rstn = 1'b0;
    clr();

    group_a();
    group_b();
    group_c();
    group_d();
    group_e();

    $display("tb_ftq_ftb_sched: PASS=%0d FAIL=%0d",
             pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ftq_ftb_sched: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  // Watchdog. Time based, not cycle based: a cycle-based watchdog
  // waits on the very clock a hang can stop (BP-097, TD#111).
  initial begin
    #200000;
    $fatal(1, "tb_ftq_ftb_sched: timeout");
  end

endmodule : tb
