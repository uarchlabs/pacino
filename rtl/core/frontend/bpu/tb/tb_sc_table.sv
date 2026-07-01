// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_sc_table.sv
// DATE:    2026-07-01
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking unit testbench for sc_table (ST0-ST3).
// DUT instantiated directly as u_dut with the ST1 parameters
// (THIS_TABLE=1, hashed index, non-zero fold). NUM_PRED_SLOTS=2.
//
// sc_table is a counter-only RAM table: combinational index hash at
// p2, one-cycle bw_ram read (ctr_p3 at p3), whole-word update write
// at upd_index_u0 gated by sc_upd_val_u0 & ctr_wr_u0, and a tbl_ri
// override path that gates all writes. No tag, no USE, no EPC, no
// valid bit, no allocation.
//
// Fast init: +SC_FAST_INIT=1 lets the sc_table initial block seed the
// RAMs at time zero; the tb skips the tbl_ri init sequence. Without
// the plusarg the tb drives the tbl_ri override path to init.
//
// Hierarchical RAM content is checked through the two named bw_ram
// instances: u_dut.u_ram_s0.mem[b][row], u_dut.u_ram_s1.mem[b][row].
// bw_ram mem is 2D mem[BANKS][ENTRIES]. For ST1: bank = index[8],
// row = index[7:0], 256 rows/bank.
//
// TC1: init check       -- every entry, both banks, both RAMs == 0.
// TC2: prediction read  -- idx hash (with fold) + one-cycle read.
// TC3: update write     -- whole-word write, no other entry moves,
//                          no write when val=0 or wr=0.
// TC4: slot independence-- slot 0 and slot 1 write disjoint RAMs.
// TC5: tbl_ri override  -- init path wins, concurrent update dropped.
// TC6: bank decomposition- index[8]=0 -> bank 0, index[8]=1 -> bank 1.
// ===================================================================
`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  // ----------------------------------------------------------------
  // DUT parameters -- ST1 from bp_defines_pkg.sv
  // ----------------------------------------------------------------
  localparam int P_THIS_TABLE  = 1;
  localparam int P_INDEX_BITS  = SC_TBL_IDX[1];      // 9
  localparam int P_CTR_WIDTH   = SC_TBL_CTR[1];      // 6
  localparam int P_ENTRIES     = SC_TBL_ENTRIES[1];  // 512
  localparam int P_FH          = SC_TBL_FH[1];       // 4
  localparam int P_NUM_SLOTS   = NUM_PRED_SLOTS;     // 2

  // Derived widths matching the sc_table localparams.
  // The SC entry is the counter only: no tag/USE/EPC/valid.
  localparam int ALLOC_DATA_W  = SC_MAX_VAL_WIDTH
                               + SC_MAX_CTR_WIDTH
                               + SC_MAX_USE_WIDTH
                               + SC_MAX_EPC_WIDTH
                               + SC_MAX_TAG_WIDTH;   // 6

  localparam int NUM_BANKS     = 2;
  localparam int RAM_ENTRIES   = P_ENTRIES / NUM_BANKS;  // 256
  localparam int ROW_BITS      = P_INDEX_BITS - 1;       // 8

  localparam logic [ALLOC_DATA_W-1:0] INIT_VAL =
    ALLOC_DATA_W'(SC_SRAM_INIT_VALUE);

  // ----------------------------------------------------------------
  // Clock
  // ----------------------------------------------------------------
  logic clk;
  initial clk = 1'b0;
  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  // ----------------------------------------------------------------
  // DUT port signals
  // ----------------------------------------------------------------
  logic [P_CTR_WIDTH-1:0]    ctr_p3[0:P_NUM_SLOTS-1];
  logic [P_INDEX_BITS-1:0]   idx_hash_p2[0:P_NUM_SLOTS-1];

  logic [P_NUM_SLOTS-1:0]    sc_pred_val_p2;
  logic [VA_WIDTH-1:1]       inp_pc_p2[0:P_NUM_SLOTS-1];
  logic [SC_MAX_FH-1:0]      idx_fh_p2;

  logic [P_NUM_SLOTS-1:0]    sc_upd_val_u0;
  logic [P_CTR_WIDTH-1:0]    ctr_wd_u0[0:P_NUM_SLOTS-1];
  logic [P_NUM_SLOTS-1:0]    ctr_wr_u0;
  logic [P_INDEX_BITS-1:0]   upd_index_u0[0:P_NUM_SLOTS-1];

  logic                      tbl_ri_active;
  logic                      tbl_ri_wr;
  logic [P_INDEX_BITS-1:0]   tbl_ri_wa;
  logic [ALLOC_DATA_W-1:0]   tbl_ri_wd;

  logic                      rstn;

  // ----------------------------------------------------------------
  // DUT instantiation (ST1)
  // ----------------------------------------------------------------
  sc_table #(
    .THIS_TABLE     (P_THIS_TABLE),
    .THIS_INDEX_BITS(P_INDEX_BITS),
    .THIS_CTR_WIDTH (P_CTR_WIDTH),
    .THIS_ENTRIES   (P_ENTRIES),
    .THIS_FH        (P_FH),
    .NUM_PRED_SLOTS (P_NUM_SLOTS)
  ) u_dut (
    .ctr_p3        (ctr_p3),
    .idx_hash_p2   (idx_hash_p2),
    .sc_pred_val_p2(sc_pred_val_p2),
    .inp_pc_p2     (inp_pc_p2),
    .idx_fh_p2     (idx_fh_p2),
    .sc_upd_val_u0 (sc_upd_val_u0),
    .ctr_wd_u0     (ctr_wd_u0),
    .ctr_wr_u0     (ctr_wr_u0),
    .upd_index_u0  (upd_index_u0),
    .tbl_ri_active (tbl_ri_active),
    .tbl_ri_wr     (tbl_ri_wr),
    .tbl_ri_wa     (tbl_ri_wa),
    .tbl_ri_wd     (tbl_ri_wd),
    .rstn          (rstn),
    .clk           (clk)
  );

  // ----------------------------------------------------------------
  // Pass / fail counters
  // ----------------------------------------------------------------
  int pass_cnt;
  int fail_cnt;

  // Per-test enables (sc_tb_decisions.md Test Structure). Use
  // if (x != 0), not if (x), to avoid WIDTHTRUNC warnings.
  int verbose      = 1;
  int _init_check  = 1;
  int _pred_read   = 1;
  int _upd_write   = 1;
  int _slot_indep  = 1;
  int _tbl_ri      = 1;
  int _bank_decomp = 1;

  // ----------------------------------------------------------------
  // Index hash reference. Mirrors sc_idx_hash for ST1:
  //   idx = THIS_INDEX_BITS'((SC_MAX_FH'(pc) >> INST_OFFSET) ^ fh)
  // fh_ext = idx_fh_p2 for ST1-ST3.
  // ----------------------------------------------------------------
  function automatic logic [P_INDEX_BITS-1:0] calc_idx(
      input logic [VA_WIDTH-1:1]  pc,
      input logic [SC_MAX_FH-1:0] fh);
    calc_idx = P_INDEX_BITS'(
      (SC_MAX_FH'(pc) >> INST_OFFSET) ^ fh);
  endfunction

  // ----------------------------------------------------------------
  // Hierarchical RAM read. bank = index MSB, row = lower bits.
  // ----------------------------------------------------------------
  function automatic logic [ALLOC_DATA_W-1:0] ram_rd(
      input int                     s,
      input logic [P_INDEX_BITS-1:0] idx);
    logic                 b;
    logic [ROW_BITS-1:0]  row;
    b   = idx[P_INDEX_BITS-1];
    row = idx[ROW_BITS-1:0];
    if (s == 0) ram_rd = u_dut.u_ram_s0.mem[b][row];
    else        ram_rd = u_dut.u_ram_s1.mem[b][row];
  endfunction

  // ----------------------------------------------------------------
  // Stimulus helpers
  // ----------------------------------------------------------------
  task automatic clr_upd();
    sc_upd_val_u0 = '0;
    ctr_wr_u0     = '0;
    for (int s = 0; s < P_NUM_SLOTS; s++) begin
      ctr_wd_u0[s]    = '0;
      upd_index_u0[s] = '0;
    end
  endtask

  task automatic clr_pred();
    for (int s = 0; s < P_NUM_SLOTS; s++) inp_pc_p2[s] = '0;
    idx_fh_p2 = '0;
  endtask

  task automatic clr_ri();
    tbl_ri_active = 1'b0;
    tbl_ri_wr     = 1'b0;
    tbl_ri_wa     = '0;
    tbl_ri_wd     = '0;
  endtask

  // Drive both slots' prediction inputs; deassert update and RI so
  // the address mux selects the prediction (read) path.
  task automatic drive_pred(
      input logic [VA_WIDTH-1:1]  pc0,
      input logic [VA_WIDTH-1:1]  pc1,
      input logic [SC_MAX_FH-1:0] fh);
    clr_upd();
    clr_ri();
    inp_pc_p2[0] = pc0;
    inp_pc_p2[1] = pc1;
    idx_fh_p2    = fh;
  endtask

  // Single-slot whole-word write at idx (one cycle).
  task automatic wr_entry(
      input int                      s,
      input logic [P_INDEX_BITS-1:0] idx,
      input logic [P_CTR_WIDTH-1:0]  dat);
    clr_ri();
    sc_upd_val_u0[s] = 1'b1;
    ctr_wr_u0[s]     = 1'b1;
    upd_index_u0[s]  = idx;
    ctr_wd_u0[s]     = dat;
    @(posedge clk); #1;
    clr_upd();
  endtask

  // Dual-slot write in the same cycle.
  task automatic wr_entry2(
      input logic [P_INDEX_BITS-1:0] i0,
      input logic [P_CTR_WIDTH-1:0]  d0,
      input logic [P_INDEX_BITS-1:0] i1,
      input logic [P_CTR_WIDTH-1:0]  d1);
    clr_ri();
    sc_upd_val_u0   = 2'b11;
    ctr_wr_u0       = 2'b11;
    upd_index_u0[0] = i0;
    ctr_wd_u0[0]    = d0;
    upd_index_u0[1] = i1;
    ctr_wd_u0[1]    = d1;
    @(posedge clk); #1;
    clr_upd();
  endtask

  // ----------------------------------------------------------------
  // RAM initialization. Fast mode: sc_table initial block seeds the
  // RAMs, the tb only clocks a few cycles. Slow mode: the tb walks
  // the tbl_ri override path across the full index range (both
  // banks) writing SC_SRAM_INIT_VALUE.
  // ----------------------------------------------------------------
  task automatic do_init(input int fast);
    if (fast != 0) begin
      // sc_table initial block already wrote both RAMs at time 0.
      repeat (2) @(posedge clk);
      #1;
    end else begin
      clr_upd();
      clr_pred();
      tbl_ri_active = 1'b1;
      tbl_ri_wr     = 1'b1;
      tbl_ri_wd     = INIT_VAL;
      // Index MSB selects the bank, so walking 0..P_ENTRIES-1 covers
      // both banks (rows 0..RAM_ENTRIES-1 each).
      for (int a = 0; a < P_ENTRIES; a++) begin
        tbl_ri_wa = P_INDEX_BITS'(a);
        @(posedge clk); #1;
      end
      clr_ri();
      @(posedge clk); #1;
    end
  endtask

  // ----------------------------------------------------------------
  // TC1: init check. Every entry in both banks of both RAMs holds
  // SC_SRAM_INIT_VALUE after initialization.
  // ----------------------------------------------------------------
  task automatic test_init_check(input int vb);
    int errs;
    errs = 0;
    for (int b = 0; b < NUM_BANKS; b++) begin
      for (int i = 0; i < RAM_ENTRIES; i++) begin
        if (u_dut.u_ram_s0.mem[b][i] !== INIT_VAL) errs++;
        if (u_dut.u_ram_s1.mem[b][i] !== INIT_VAL) errs++;
      end
    end
    if (errs == 0) begin
      $display("[PASS] TC1: init check (all entries == %0d)",
               SC_SRAM_INIT_VALUE);
      pass_cnt++;
    end else begin
      $display("[FAIL] TC1: init check, %0d mismatched entries", errs);
      fail_cnt++;
    end
  endtask

  // ----------------------------------------------------------------
  // TC2: prediction read and index hash.
  // Drive both slots with distinct PCs and a non-zero fold. Verify
  // idx_hash_p2[s] matches the reference hash. Seed a counter at
  // each computed index via the update path, then read it back on
  // the prediction path (one-cycle read, ctr_p3 at p3).
  // ----------------------------------------------------------------
  task automatic test_pred_read(input int vb);
    logic [VA_WIDTH-1:1]     pc0, pc1;
    logic [SC_MAX_FH-1:0]    fh;
    logic [P_INDEX_BITS-1:0] eidx0, eidx1;
    logic [P_CTR_WIDTH-1:0]  seed0, seed1;
    logic ihok, rdok;
    pc0   = 39'h0000_0044;   // (pc>>2)=0x11
    pc1   = 39'h0000_0060;   // (pc>>2)=0x18
    fh    = 64'h0000_0000_0000_0005;
    eidx0 = calc_idx(pc0, fh);
    eidx1 = calc_idx(pc1, fh);
    seed0 = 6'h2A;
    seed1 = 6'h15;

    // Index hash check (combinational at p2).
    drive_pred(pc0, pc1, fh);
    #1;
    ihok = (idx_hash_p2[0] === eidx0) &&
           (idx_hash_p2[1] === eidx1);

    // Seed both entries, then read back on the prediction path.
    wr_entry2(eidx0, seed0, eidx1, seed1);
    drive_pred(pc0, pc1, fh);
    @(posedge clk); #1;
    rdok = (ctr_p3[0] === seed0) &&
           (ctr_p3[1] === seed1);
    clr_pred();

    if (ihok && rdok) begin
      $display("[PASS] TC2: prediction read / index hash");
      pass_cnt++;
    end else begin
      $display(
        "[FAIL] TC2: ih=%b idx=%0h/%0h(exp %0h/%0h) rd=%b c=%0h/%0h",
        ihok, idx_hash_p2[0], idx_hash_p2[1], eidx0, eidx1,
        rdok, ctr_p3[0], ctr_p3[1]);
      fail_cnt++;
    end
  endtask

  // ----------------------------------------------------------------
  // TC3: update write. Whole-word write of ctr_wd_u0 at
  // upd_index_u0. Snapshot slot 0, write one entry, confirm only the
  // addressed entry changed. Then confirm no write when
  // sc_upd_val_u0=0 and no write when ctr_wr_u0=0.
  // ----------------------------------------------------------------
  task automatic test_upd_write(input int vb);
    logic [ALLOC_DATA_W-1:0] snap[0:P_ENTRIES-1];
    logic [P_INDEX_BITS-1:0] idx, idxa, idxb;
    logic [P_CTR_WIDTH-1:0]  wdat;
    logic [ALLOC_DATA_W-1:0] exp;
    int   errs;
    logic gv, gw;
    idx  = 9'd100;
    wdat = 6'h3F;
    idxa = 9'd200;
    idxb = 9'd201;

    // Snapshot slot 0 before the write.
    for (int k = 0; k < P_ENTRIES; k++)
      snap[k] = ram_rd(0, P_INDEX_BITS'(k));

    wr_entry(0, idx, wdat);

    // Only the addressed entry may change.
    errs = 0;
    for (int k = 0; k < P_ENTRIES; k++) begin
      exp = (k == int'(idx)) ? wdat : snap[k];
      if (ram_rd(0, P_INDEX_BITS'(k)) !== exp) errs++;
    end

    // No write when sc_upd_val_u0=0 (ctr_wr asserted).
    clr_ri();
    sc_upd_val_u0[0] = 1'b0;
    ctr_wr_u0[0]     = 1'b1;
    upd_index_u0[0]  = idxa;
    ctr_wd_u0[0]     = 6'h3F;
    @(posedge clk); #1;
    clr_upd();
    gv = (ram_rd(0, idxa) === INIT_VAL);

    // No write when ctr_wr_u0=0 (sc_upd_val asserted).
    clr_ri();
    sc_upd_val_u0[0] = 1'b1;
    ctr_wr_u0[0]     = 1'b0;
    upd_index_u0[0]  = idxb;
    ctr_wd_u0[0]     = 6'h3F;
    @(posedge clk); #1;
    clr_upd();
    gw = (ram_rd(0, idxb) === INIT_VAL);

    if (errs == 0 && ram_rd(0, idx) === wdat && gv && gw) begin
      $display("[PASS] TC3: update write");
      pass_cnt++;
    end else begin
      $display(
        "[FAIL] TC3: errs=%0d wr=%0h(exp %0h) gv=%b gw=%b",
        errs, ram_rd(0, idx), wdat, gv, gw);
      fail_cnt++;
    end
  endtask

  // ----------------------------------------------------------------
  // TC4: slot independence. Drive both slots the same cycle with
  // different indices and data. Each RAM must receive only its
  // slot's transaction (cross entries stay at INIT_VAL).
  // ----------------------------------------------------------------
  task automatic test_slot_indep(input int vb);
    logic [P_INDEX_BITS-1:0] i0, i1;
    logic [P_CTR_WIDTH-1:0]  d0, d1;
    logic ok;
    i0 = 9'd50;  d0 = 6'h1B;
    i1 = 9'd77;  d1 = 6'h07;

    wr_entry2(i0, d0, i1, d1);

    ok = (ram_rd(0, i0) === d0)       &&  // slot 0 wrote its index
         (ram_rd(1, i1) === d1)       &&  // slot 1 wrote its index
         (ram_rd(0, i1) === INIT_VAL) &&  // slot 0 RAM: no slot-1 idx
         (ram_rd(1, i0) === INIT_VAL);    // slot 1 RAM: no slot-0 idx

    if (ok) begin
      $display("[PASS] TC4: slot independence");
      pass_cnt++;
    end else begin
      $display(
        "[FAIL] TC4: s0[i0]=%0h s1[i1]=%0h s0[i1]=%0h s1[i0]=%0h",
        ram_rd(0, i0), ram_rd(1, i1),
        ram_rd(0, i1), ram_rd(1, i0));
      fail_cnt++;
    end
  endtask

  // ----------------------------------------------------------------
  // TC5: tbl_ri override. Assert tbl_ri_active with a concurrent
  // update request. The RI address/data/enable must win (both RAMs
  // written at tbl_ri_wa) and the update must be suppressed (its
  // index stays at INIT_VAL).
  // ----------------------------------------------------------------
  task automatic test_tbl_ri(input int vb);
    logic [P_INDEX_BITS-1:0] iri, iup;
    logic [ALLOC_DATA_W-1:0] dri;
    logic [P_CTR_WIDTH-1:0]  dup;
    logic ok;
    iri = 9'd150; dri = 6'h2C;
    iup = 9'd160; dup = 6'h11;

    clr_pred();
    tbl_ri_active   = 1'b1;
    tbl_ri_wr       = 1'b1;
    tbl_ri_wa       = iri;
    tbl_ri_wd       = dri;
    // Concurrent update request (must be dropped).
    sc_upd_val_u0   = 2'b11;
    ctr_wr_u0       = 2'b11;
    upd_index_u0[0] = iup;
    ctr_wd_u0[0]    = dup;
    upd_index_u0[1] = iup;
    ctr_wd_u0[1]    = dup;
    @(posedge clk); #1;
    clr_ri();
    clr_upd();

    ok = (ram_rd(0, iri) === dri)       &&  // RI won, slot 0 RAM
         (ram_rd(1, iri) === dri)       &&  // RI won, slot 1 RAM
         (ram_rd(0, iup) === INIT_VAL)  &&  // update suppressed
         (ram_rd(1, iup) === INIT_VAL);

    if (ok) begin
      $display("[PASS] TC5: tbl_ri override");
      pass_cnt++;
    end else begin
      $display(
        "[FAIL] TC5: ri0=%0h ri1=%0h up0=%0h up1=%0h",
        ram_rd(0, iri), ram_rd(1, iri),
        ram_rd(0, iup), ram_rd(1, iup));
      fail_cnt++;
    end
  endtask

  // ----------------------------------------------------------------
  // TC6: bank decomposition. index[8]=0 lands in mem[0][row],
  // index[8]=1 lands in mem[1][row]. Same row, both banks.
  // ----------------------------------------------------------------
  task automatic test_bank_decomp(input int vb);
    logic [P_INDEX_BITS-1:0] ilo, ihi;
    logic [P_CTR_WIDTH-1:0]  dlo, dhi;
    logic ok;
    ilo = 9'h020;  // bank 0, row 0x20
    ihi = 9'h120;  // bank 1, row 0x20
    dlo = 6'h05;
    dhi = 6'h0A;

    wr_entry(0, ilo, dlo);
    wr_entry(0, ihi, dhi);

    ok = (u_dut.u_ram_s0.mem[0][ROW_BITS'('h20)] === dlo) &&
         (u_dut.u_ram_s0.mem[1][ROW_BITS'('h20)] === dhi);

    if (ok) begin
      $display("[PASS] TC6: bank decomposition");
      pass_cnt++;
    end else begin
      $display(
        "[FAIL] TC6: bank0[0x20]=%0h(exp %0h) bank1[0x20]=%0h(exp %0h)",
        u_dut.u_ram_s0.mem[0][ROW_BITS'('h20)], dlo,
        u_dut.u_ram_s0.mem[1][ROW_BITS'('h20)], dhi);
      fail_cnt++;
    end
  endtask

  // ----------------------------------------------------------------
  // Main sequence
  // ----------------------------------------------------------------
  int fast_init;
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    // sc_pred_val_p2 is unconnected in the DUT; tie it high and do
    // not test it (BP-075a binding decision).
    sc_pred_val_p2 = 2'b11;
    rstn           = 1'b0;
    clr_upd();
    clr_pred();
    clr_ri();

    // Reset window. sc_table has no reset-driven state; the bw_ram
    // arrays carry no reset. This also lets any time-zero fast-init
    // block settle before the init check.
    repeat (3) @(posedge clk);
    @(posedge clk); #1; rstn = 1'b1;
    @(posedge clk); #1;

    fast_init = 0;
    void'($value$plusargs("SC_FAST_INIT=%d", fast_init));
    if (fast_init != 0)
      $display("[info] SC_FAST_INIT=1 (fast init, tb skips tbl_ri)");
    else
      $display("[info] SC_FAST_INIT=0 (tb drives tbl_ri init)");

    do_init(fast_init);

    if (_init_check  != 0) test_init_check(verbose);
    if (_pred_read   != 0) test_pred_read(verbose);
    if (_upd_write   != 0) test_upd_write(verbose);
    if (_slot_indep  != 0) test_slot_indep(verbose);
    if (_tbl_ri      != 0) test_tbl_ri(verbose);
    if (_bank_decomp != 0) test_bank_decomp(verbose);

    @(posedge clk); #1;
    $display("--------------------------------------------");
    $display("Results: %0d PASS  %0d FAIL  (of 6 TCs)",
             pass_cnt, fail_cnt);
    if (fail_cnt != 0)
      $fatal(1, "TESTBENCH FAILED");
    else
      $display("TESTBENCH PASSED");
    $finish;
  end

  // ----------------------------------------------------------------
  // Timeout watchdog
  // ----------------------------------------------------------------
  initial begin : watchdog
    #200000;
    $display("[TIMEOUT] simulation exceeded time limit");
    $fatal(1, "Timeout");
  end

endmodule : tb

`default_nettype wire
