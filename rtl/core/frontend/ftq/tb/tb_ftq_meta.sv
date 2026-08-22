// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ftq_meta (BP-107).
//
// Self-checking. ftq_meta has no reset and does not need one: the
// array is read only at resolution and a resolution can only name an
// entry a prediction wrote. THIS TESTBENCH HONOURS THAT -- no case
// below reads a location it has not first written, and there is no
// check of the form "an unwritten slot reads zero", because that is
// not a property the module has.
//
// The acceptance criterion is that a resolution read returns the
// metadata written at prediction. The cases are built around the two
// ways that fails: a write group landing in the wrong entry, and the
// p2 and p3 groups clobbering each other. The second is the one
// ftq_bpu_interfaces.md 7.1 and 7.2 promise cannot happen because
// the two touch DISJOINT members, and it is the promise the deferred
// union of ftq_entry_formats.md 3.1 narrows to a single arm -- so it
// is worth a case now, while it still holds across the whole struct.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  logic                    p2_wr_val;
  logic [FTQ_IDX_BITS-1:0] p2_wr_idx;
  tage_pred_meta_t         p2_wr_tage   [0:NUM_PRED_SLOTS-1];
  ittage_pred_meta_t       p2_wr_ittage [0:NUM_PRED_SLOTS-1];
  lp_pred_t                p2_wr_lp     [0:NUM_PRED_SLOTS-1];
  ftb_pred_meta_t          p2_wr_ftb    [0:NUM_PRED_SLOTS-1];
  logic                    p3_wr_val;
  logic [FTQ_IDX_BITS-1:0] p3_wr_idx;
  sc_pred_meta_t           p3_wr_sc     [0:NUM_PRED_SLOTS-1];
  logic [FTQ_IDX_BITS-1:0] rd_idx  [0:NUM_RESOLVE_PORTS-1];
  bp_ftq_meta_t            rd_meta [0:NUM_RESOLVE_PORTS-1]
                                   [0:NUM_PRED_SLOTS-1];

  ftq_meta dut (
    .clk          (clk),
    .rstn         (rstn),
    .p2_wr_val    (p2_wr_val),
    .p2_wr_idx    (p2_wr_idx),
    .p2_wr_tage   (p2_wr_tage),
    .p2_wr_ittage (p2_wr_ittage),
    .p2_wr_lp     (p2_wr_lp),
    .p2_wr_ftb    (p2_wr_ftb),
    .p3_wr_val    (p3_wr_val),
    .p3_wr_idx    (p3_wr_idx),
    .p3_wr_sc     (p3_wr_sc),
    .rd_idx       (rd_idx),
    .rd_meta      (rd_meta)
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

  // Every write carries a value derived from its index and slot, so
  // a read of the wrong entry or the wrong slot is visible as a
  // value and not merely as an inequality. branch_id is the field
  // used, because every predictor metadata struct carries one.
  task automatic wr_p2(input int idx, input int seed);
    p2_wr_val = 1'b1;
    p2_wr_idx = FTQ_IDX_BITS'(idx);
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      p2_wr_tage[s]             = '0;
      p2_wr_tage[s].branch_id   = FTQ_IDX_BITS'(seed + s);
      p2_wr_ittage[s]           = '0;
      p2_wr_ittage[s].branch_id = FTQ_IDX_BITS'(seed + s + 8);
      p2_wr_lp[s]               = '0;
      p2_wr_lp[s].lp_idx        = LP_IDX_BITS'(seed + s);
      p2_wr_ftb[s]              = '0;
      p2_wr_ftb[s].hit          = (s == 0);
      p2_wr_ftb[s].way          = FTB_WAY_BITS'(seed + s);
      p2_wr_ftb[s].jmp_pos      = FTB_BR_POS_BITS'(seed + s);
    end
    tick();
    p2_wr_val = 1'b0;
  endtask

  task automatic wr_p3(input int idx, input int seed);
    p3_wr_val = 1'b1;
    p3_wr_idx = FTQ_IDX_BITS'(idx);
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      p3_wr_sc[s]           = '0;
      p3_wr_sc[s].branch_id = FTQ_IDX_BITS'(seed + s);
      p3_wr_sc[s].sc_pred_tkn = (s == 1);
    end
    tick();
    p3_wr_val = 1'b0;
  endtask

  task automatic do_reset();
    rstn      = 1'b0;
    p2_wr_val = 1'b0;
    p3_wr_val = 1'b0;
    p2_wr_idx = '0;
    p3_wr_idx = '0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      p2_wr_tage[s]   = '0;
      p2_wr_ittage[s] = '0;
      p2_wr_lp[s]     = '0;
      p2_wr_ftb[s]    = '0;
      p3_wr_sc[s]     = '0;
    end
    for (int p = 0; p < NUM_RESOLVE_PORTS; p++) rd_idx[p] = '0;
    repeat (4) tick();
    rstn = 1'b1;
    repeat (2) tick();
  endtask

  // -----------------------------------------------------------------
  // A. A resolution read returns the metadata written at prediction.
  // -----------------------------------------------------------------
  // ACCEPTANCE, Problem 2.
  task automatic group_a();
    $display("-- A: write at predict, read at resolution --");
    do_reset();

    wr_p2(9, 21);
    wr_p3(9, 33);

    rd_idx[0] = 6'd9;
    #1;
    chk("A1 tage slot 0 read back",
        rd_meta[0][0].tage.branch_id == FTQ_IDX_BITS'(21));
    chk("A2 tage slot 1 read back",
        rd_meta[0][1].tage.branch_id == FTQ_IDX_BITS'(22));
    chk("A3 ittage read back",
        rd_meta[0][0].ittage.branch_id == FTQ_IDX_BITS'(29));
    chk("A4 lp read back",
        rd_meta[0][0].lp.lp_idx == LP_IDX_BITS'(21));
    chk("A5 ftb hit read back", rd_meta[0][0].ftb.hit);
    chk("A6 ftb way read back",
        rd_meta[0][0].ftb.way == FTB_WAY_BITS'(21));
    chk("A7 sc slot 0 read back",
        rd_meta[0][0].sc.branch_id == FTQ_IDX_BITS'(33));
    chk("A8 sc slot 1 read back",
        rd_meta[0][1].sc.branch_id == FTQ_IDX_BITS'(34));
    chk("A9 the sc direction is per slot",
        !rd_meta[0][0].sc.sc_pred_tkn &&
         rd_meta[0][1].sc.sc_pred_tkn);
  endtask

  // -----------------------------------------------------------------
  // B. The p2 and p3 write groups are DISJOINT.
  // -----------------------------------------------------------------
  // ftq_bpu_interfaces.md 7.1 and 7.2: each writes a disjoint set of
  // members, so the FTQ never has to merge. A module that wrote the
  // whole struct from either group would destroy the other's members
  // and this is the case that catches it.
  task automatic group_b();
    $display("-- B: disjoint write groups --");
    do_reset();

    // p2 first, then p3, then check p2's members survived.
    wr_p2(14, 5);
    wr_p3(14, 60);
    rd_idx[0] = 6'd14;
    #1;
    chk("B1 the p3 write left tage alone",
        rd_meta[0][0].tage.branch_id == FTQ_IDX_BITS'(5));
    chk("B2 the p3 write left ittage alone",
        rd_meta[0][0].ittage.branch_id == FTQ_IDX_BITS'(13));
    chk("B3 the p3 write left lp alone",
        rd_meta[0][0].lp.lp_idx == LP_IDX_BITS'(5));
    chk("B4 the p3 write left ftb alone",
        rd_meta[0][0].ftb.way == FTB_WAY_BITS'(5));
    chk("B5 the p3 write landed",
        rd_meta[0][0].sc.branch_id == FTQ_IDX_BITS'(60));

    // The other order, which is the one that actually occurs in a
    // moving stream: p3 for block N arrives in the same cycle as p2
    // for block N+1, so for a STALLED stream both name one entry
    // and p2 lands after p3.
    wr_p2(14, 41);
    #1;
    chk("B6 the p2 write left sc alone",
        rd_meta[0][0].sc.branch_id == FTQ_IDX_BITS'(60));
    chk("B7 the p2 write landed",
        rd_meta[0][0].tage.branch_id == FTQ_IDX_BITS'(41));

    // BOTH IN ONE CYCLE, one entry. The disjointness has to hold
    // inside a cycle, not only across cycles.
    p2_wr_val = 1'b1;
    p2_wr_idx = 6'd14;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      p2_wr_tage[s]           = '0;
      p2_wr_tage[s].branch_id = FTQ_IDX_BITS'(7);
    end
    p3_wr_val = 1'b1;
    p3_wr_idx = 6'd14;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      p3_wr_sc[s]           = '0;
      p3_wr_sc[s].branch_id = FTQ_IDX_BITS'(19);
    end
    tick();
    p2_wr_val = 1'b0;
    p3_wr_val = 1'b0;
    #1;
    chk("B8 both groups landed in one cycle",
        (rd_meta[0][0].tage.branch_id == FTQ_IDX_BITS'(7)) &&
        (rd_meta[0][0].sc.branch_id   == FTQ_IDX_BITS'(19)));
  endtask

  // -----------------------------------------------------------------
  // C. Two entries, two read ports, one array.
  // -----------------------------------------------------------------
  task automatic group_c();
    $display("-- C: two read ports --");
    do_reset();

    wr_p2(2,  10);
    wr_p3(2,  11);
    wr_p2(50, 20);
    wr_p3(50, 21);

    // The two channels naming DIFFERENT entries is the case one read
    // port cannot serve, and the reason ftq_meta has two.
    rd_idx[0] = 6'd2;
    rd_idx[1] = 6'd50;
    #1;
    chk("C1 port 0 reads its entry",
        rd_meta[0][0].tage.branch_id == FTQ_IDX_BITS'(10));
    chk("C2 port 1 reads its entry",
        rd_meta[1][0].tage.branch_id == FTQ_IDX_BITS'(20));
    chk("C3 port 0 sc",
        rd_meta[0][0].sc.branch_id == FTQ_IDX_BITS'(11));
    chk("C4 port 1 sc",
        rd_meta[1][0].sc.branch_id == FTQ_IDX_BITS'(21));

    // Swapped, so a port hard-wired to one index fails.
    rd_idx[0] = 6'd50;
    rd_idx[1] = 6'd2;
    #1;
    chk("C5 the ports swap",
        (rd_meta[0][0].tage.branch_id == FTQ_IDX_BITS'(20)) &&
        (rd_meta[1][0].tage.branch_id == FTQ_IDX_BITS'(10)));

    // Both naming ONE entry agree. This is what property M1 states.
    rd_idx[0] = 6'd50;
    rd_idx[1] = 6'd50;
    #1;
    chk("C6 both ports on one entry agree",
        rd_meta[0][0] === rd_meta[1][0]);

    // A write to one entry does not disturb the other. 421 bits per
    // slot and two slots per entry; a decode that ignored a bit of
    // the index would alias 2 and 50 only through a wider pattern,
    // so the whole array is swept in group D.
    wr_p2(2, 44);
    rd_idx[0] = 6'd2;
    rd_idx[1] = 6'd50;
    #1;
    chk("C7 the rewrite landed",
        rd_meta[0][0].tage.branch_id == FTQ_IDX_BITS'(44));
    chk("C8 the other entry survived",
        rd_meta[1][0].tage.branch_id == FTQ_IDX_BITS'(20));
  endtask

  // -----------------------------------------------------------------
  // D. The whole index space.
  // -----------------------------------------------------------------
  task automatic group_d();
    $display("-- D: all 64 entries --");
    do_reset();

    for (int i = 0; i < FTQ_DEPTH; i++) begin
      wr_p2(i, i);
      wr_p3(i, i + 1);
    end

    begin
      int bad;
      bad = 0;
      for (int i = 0; i < FTQ_DEPTH; i++) begin
        rd_idx[0] = FTQ_IDX_BITS'(i);
        #1;
        if (rd_meta[0][0].tage.branch_id !== FTQ_IDX_BITS'(i)) bad++;
        if (rd_meta[0][1].tage.branch_id !==
              FTQ_IDX_BITS'(i + 1)) bad++;
        if (rd_meta[0][0].sc.branch_id !==
              FTQ_IDX_BITS'(i + 1)) bad++;
      end
      chk("D1 all 64 entries hold their own metadata", bad == 0);
    end
  endtask

  // -----------------------------------------------------------------
  // Run
  // -----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    if (FTQ_DEPTH != 64 || NUM_PRED_SLOTS != 2) begin
      $fatal(1, "tb_ftq_meta: written for FTQ_DEPTH 64, slots 2");
    end

    do_reset();
    group_a();
    group_b();
    group_c();
    group_d();

    $display("tb_ftq_meta: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ftq_meta: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #400000;
    $fatal(1, "tb_ftq_meta: timeout");
  end

endmodule : tb
