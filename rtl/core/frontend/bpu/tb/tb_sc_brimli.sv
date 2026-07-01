// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_sc_brimli.sv
// DATE:    2026-07-01
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking unit testbench for sc_brimli (ST4, BrIMLI table).
// DUT instantiated directly as u_dut with the ST4 parameters
// (THIS_TABLE=4, get_br_imli_idx index, 10-bit index, 1024 entries).
// NUM_PRED_SLOTS=2.
//
// sc_brimli is a counter-only RAM table: combinational get_br_imli_idx
// index at p2, one-cycle bw_ram read (ctr_p3 at p3), whole-word update
// write at upd_index_u0 gated by sc_upd_val_u0 & ctr_wr_u0, and a
// tbl_ri override path that gates all writes. No tag, no USE, no EPC,
// no valid bit, no allocation.
//
// The index is get_br_imli_idx over PC[15:6] (inp_pc_p2[s][15:6]),
// sc_phr_p2, br_imli, and br_imli_mode:
//   f_idx = case(mode) IDX_IMLI_PHR : (imli==0)?phr:imli
//                      IDX_PHR_ONLY : phr
//                      IDX_IMLI_ONLY: imli
//   index = pc ^ f_idx ^ (pc >> 4)
// br_imli is an input port; sc_brimli does no register maintenance.
//
// Fast init: +SC_FAST_INIT=1 lets the sc_brimli initial block seed the
// RAMs at time zero; the tb skips the tbl_ri init sequence. Without the
// plusarg the tb drives the tbl_ri override path to init.
//
// Hierarchical RAM content is checked through the two named bw_ram
// instances: u_dut.u_ram_s0.mem[b][row], u_dut.u_ram_s1.mem[b][row].
// bw_ram mem is 2D mem[BANKS][ENTRIES]. For ST4: bank = index[9],
// row = index[8:0], 512 rows/bank.
//
// TC1: init check       -- every entry, both banks, both RAMs == 0.
// TC2: prediction read  -- get_br_imli_idx + one-cycle read.
// TC3: mode coverage    -- IDX_IMLI_PHR (cold/hot), PHR_ONLY, IMLI_ONLY.
// TC4: update write     -- whole-word write, no other entry moves,
//                          no write when val=0 or wr=0.
// TC5: slot independence-- slot 0 and slot 1 write disjoint RAMs.
// TC6: tbl_ri override  -- init path wins, concurrent update dropped.
// TC7: bank decomposition- index[9]=0 -> bank 0, index[9]=1 -> bank 1.
// ===================================================================
`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  // ----------------------------------------------------------------
  // DUT parameters -- ST4 from bp_defines_pkg.sv
  // ----------------------------------------------------------------
  localparam int P_THIS_TABLE  = 4;
  localparam int P_INDEX_BITS  = SC_TBL_IDX[4];      // 10
  localparam int P_CTR_WIDTH   = SC_TBL_CTR[4];      // 6
  localparam int P_ENTRIES     = SC_TBL_ENTRIES[4];  // 1024
  localparam int P_NUM_SLOTS   = NUM_PRED_SLOTS;     // 2

  // Derived widths matching the sc_brimli localparams.
  // The SC entry is the counter only: no tag/USE/EPC/valid.
  localparam int ALLOC_DATA_W  = SC_MAX_VAL_WIDTH
                               + SC_MAX_CTR_WIDTH
                               + SC_MAX_USE_WIDTH
                               + SC_MAX_EPC_WIDTH
                               + SC_MAX_TAG_WIDTH;   // 6

  localparam int NUM_BANKS     = 2;
  localparam int RAM_ENTRIES   = P_ENTRIES / NUM_BANKS;  // 512
  localparam int ROW_BITS      = P_INDEX_BITS - 1;       // 9

  // get_br_imli_idx operand width (PC[15:6], phr, imli are 10 bits).
  localparam int BRIMLI_W      = 10;

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
  logic [9:0]                sc_phr_p2;
  logic [9:0]                br_imli;
  br_imli_mode_e             br_imli_mode;

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
  // DUT instantiation (ST4)
  // ----------------------------------------------------------------
  sc_brimli #(
    .THIS_TABLE     (P_THIS_TABLE),
    .THIS_INDEX_BITS(P_INDEX_BITS),
    .THIS_CTR_WIDTH (P_CTR_WIDTH),
    .THIS_ENTRIES   (P_ENTRIES),
    .NUM_PRED_SLOTS (P_NUM_SLOTS)
  ) u_dut (
    .ctr_p3        (ctr_p3),
    .idx_hash_p2   (idx_hash_p2),
    .sc_pred_val_p2(sc_pred_val_p2),
    .inp_pc_p2     (inp_pc_p2),
    .sc_phr_p2     (sc_phr_p2),
    .br_imli       (br_imli),
    .br_imli_mode  (br_imli_mode),
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
  int _mode_cov    = 1;
  int _upd_write   = 1;
  int _slot_indep  = 1;
  int _tbl_ri      = 1;
  int _bank_decomp = 1;

  // ----------------------------------------------------------------
  // Index reference. Mirrors get_br_imli_idx (sc_table_hash_rules.md,
  // sc_decisions.md section 12):
  //   bpc   = pc[15:6]
  //   f_idx = mode-selected IMLI/PHR contribution
  //   idx   = P_INDEX_BITS'(bpc ^ f_idx ^ (bpc >> 4))
  // ----------------------------------------------------------------
  function automatic logic [P_INDEX_BITS-1:0] calc_idx(
      input logic [VA_WIDTH-1:1] pc,
      input logic [9:0]          phr,
      input logic [9:0]          imli,
      input br_imli_mode_e       mode);
    logic [BRIMLI_W-1:0] bpc;
    logic [BRIMLI_W-1:0] f_idx;
    bpc = pc[15:6];
    case (mode)
      IDX_IMLI_PHR:  f_idx = (imli == 10'd0) ? phr : imli;
      IDX_PHR_ONLY:  f_idx = phr;
      IDX_IMLI_ONLY: f_idx = imli;
      default:       f_idx = (imli == 10'd0) ? phr : imli;
    endcase
    calc_idx = P_INDEX_BITS'(bpc ^ f_idx ^ (bpc >> 4));
  endfunction

  // ----------------------------------------------------------------
  // Hierarchical RAM read. bank = index MSB, row = lower bits.
  // ----------------------------------------------------------------
  function automatic logic [ALLOC_DATA_W-1:0] ram_rd(
      input int                      s,
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
    sc_phr_p2    = '0;
    br_imli      = '0;
    br_imli_mode = IDX_IMLI_PHR;
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
      input logic [VA_WIDTH-1:1] pc0,
      input logic [VA_WIDTH-1:1] pc1,
      input logic [9:0]          phr,
      input logic [9:0]          imli,
      input br_imli_mode_e       mode);
    clr_upd();
    clr_ri();
    inp_pc_p2[0] = pc0;
    inp_pc_p2[1] = pc1;
    sc_phr_p2    = phr;
    br_imli      = imli;
    br_imli_mode = mode;
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
  // RAM initialization. Fast mode: sc_brimli initial block seeds the
  // RAMs, the tb only clocks a few cycles. Slow mode: the tb walks
  // the tbl_ri override path across the full index range (both
  // banks) writing SC_SRAM_INIT_VALUE.
  // ----------------------------------------------------------------
  task automatic do_init(input int fast);
    if (fast != 0) begin
      // sc_brimli initial block already wrote both RAMs at time 0.
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
  // TC2: prediction read and index (get_br_imli_idx).
  // Drive both slots with distinct PCs and a shared phr/imli/mode.
  // Verify idx_hash_p2[s] matches the reference. Seed a counter at
  // each computed index via the update path, then read it back on
  // the prediction path (one-cycle read, ctr_p3 at p3).
  // ----------------------------------------------------------------
  task automatic test_pred_read(input int vb);
    logic [VA_WIDTH-1:1]     pc0, pc1;
    logic [9:0]              phr, imli;
    br_imli_mode_e           mode;
    logic [P_INDEX_BITS-1:0] eidx0, eidx1;
    logic [P_CTR_WIDTH-1:0]  seed0, seed1;
    logic ihok, rdok;
    // inp_pc_p2 is [VA_WIDTH-1:1]; the DUT slices [15:6] for the
    // BrIMLI pc argument. Distinct PCs -> distinct indices per slot.
    pc0   = 39'h0000_1240;
    pc1   = 39'h0000_2E80;
    phr   = 10'h155;
    imli  = 10'h0AA;         // nonzero -> IDX_IMLI_PHR uses imli
    mode  = IDX_IMLI_PHR;
    eidx0 = calc_idx(pc0, phr, imli, mode);
    eidx1 = calc_idx(pc1, phr, imli, mode);
    seed0 = 6'h2A;
    seed1 = 6'h15;

    // Index check (combinational at p2).
    drive_pred(pc0, pc1, phr, imli, mode);
    #1;
    ihok = (idx_hash_p2[0] === eidx0) &&
           (idx_hash_p2[1] === eidx1);

    // Seed both entries, then read back on the prediction path.
    wr_entry2(eidx0, seed0, eidx1, seed1);
    drive_pred(pc0, pc1, phr, imli, mode);
    @(posedge clk); #1;
    rdok = (ctr_p3[0] === seed0) &&
           (ctr_p3[1] === seed1);
    clr_pred();

    if (ihok && rdok) begin
      $display("[PASS] TC2: prediction read / index");
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
  // TC3: br_imli_mode coverage. For fixed pc/phr/imli, verify the
  // index tracks the mode-selected f_idx:
  //   IDX_IMLI_PHR, imli==0  -> f_idx = phr
  //   IDX_IMLI_PHR, imli!=0  -> f_idx = imli
  //   IDX_PHR_ONLY, imli!=0  -> f_idx = phr (imli ignored)
  //   IDX_IMLI_ONLY, imli==0 -> f_idx = 0  (no PHR substitution)
  //   IDX_IMLI_ONLY, imli!=0 -> f_idx = imli
  // phr and imli are chosen distinct and nonzero so the modes yield
  // different indices; the check catches a DUT that ignores mode.
  // ----------------------------------------------------------------
  task automatic test_mode_cov(input int vb);
    logic [VA_WIDTH-1:1]     pc;
    logic [9:0]              phr, imli_nz;
    logic [P_INDEX_BITS-1:0] e0, e1, e2, e3, e4;
    logic [P_INDEX_BITS-1:0] a0, a1, a2, a3, a4;
    logic ok;
    pc      = 39'h0000_39C0;
    phr     = 10'h2D3;
    imli_nz = 10'h11C;

    // Expected indices (reference).
    e0 = calc_idx(pc, phr, 10'd0,    IDX_IMLI_PHR);
    e1 = calc_idx(pc, phr, imli_nz,  IDX_IMLI_PHR);
    e2 = calc_idx(pc, phr, imli_nz,  IDX_PHR_ONLY);
    e3 = calc_idx(pc, phr, 10'd0,    IDX_IMLI_ONLY);
    e4 = calc_idx(pc, phr, imli_nz,  IDX_IMLI_ONLY);

    // Drive each case, sample idx_hash_p2[0] combinationally.
    drive_pred(pc, pc, phr, 10'd0,   IDX_IMLI_PHR);  #1; a0 = idx_hash_p2[0];
    drive_pred(pc, pc, phr, imli_nz, IDX_IMLI_PHR);  #1; a1 = idx_hash_p2[0];
    drive_pred(pc, pc, phr, imli_nz, IDX_PHR_ONLY);  #1; a2 = idx_hash_p2[0];
    drive_pred(pc, pc, phr, 10'd0,   IDX_IMLI_ONLY); #1; a3 = idx_hash_p2[0];
    drive_pred(pc, pc, phr, imli_nz, IDX_IMLI_ONLY); #1; a4 = idx_hash_p2[0];
    clr_pred();

    ok = (a0 === e0) && (a1 === e1) && (a2 === e2) &&
         (a3 === e3) && (a4 === e4);

    // Cross-checks that the modes actually diverge (guards against a
    // DUT that hard-wires one f_idx source). With phr != imli_nz:
    //   IMLI_PHR cold (phr) != IMLI_PHR hot (imli)
    //   PHR_ONLY (phr)      != IMLI_ONLY hot (imli)
    ok = ok && (e0 !== e1) && (e2 !== e4);

    if (ok) begin
      $display("[PASS] TC3: br_imli_mode coverage");
      pass_cnt++;
    end else begin
      $display(
        "[FAIL] TC3: a=%0h/%0h/%0h/%0h/%0h exp %0h/%0h/%0h/%0h/%0h",
        a0, a1, a2, a3, a4, e0, e1, e2, e3, e4);
      fail_cnt++;
    end
  endtask

  // ----------------------------------------------------------------
  // TC4: update write. Whole-word write of ctr_wd_u0 at upd_index_u0.
  // Snapshot slot 0, write one entry, confirm only the addressed
  // entry changed. Then confirm no write when sc_upd_val_u0=0 and no
  // write when ctr_wr_u0=0.
  // ----------------------------------------------------------------
  task automatic test_upd_write(input int vb);
    logic [ALLOC_DATA_W-1:0] snap[0:P_ENTRIES-1];
    logic [P_INDEX_BITS-1:0] idx, idxa, idxb;
    logic [P_CTR_WIDTH-1:0]  wdat;
    logic [ALLOC_DATA_W-1:0] exp;
    int   errs;
    logic gv, gw;
    idx  = 10'd300;
    wdat = 6'h3F;
    idxa = 10'd400;
    idxb = 10'd401;

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
      $display("[PASS] TC4: update write");
      pass_cnt++;
    end else begin
      $display(
        "[FAIL] TC4: errs=%0d wr=%0h(exp %0h) gv=%b gw=%b",
        errs, ram_rd(0, idx), wdat, gv, gw);
      fail_cnt++;
    end
  endtask

  // ----------------------------------------------------------------
  // TC5: slot independence. Drive both slots the same cycle with
  // different indices and data. Each RAM must receive only its
  // slot's transaction (cross entries stay at INIT_VAL).
  // ----------------------------------------------------------------
  task automatic test_slot_indep(input int vb);
    logic [P_INDEX_BITS-1:0] i0, i1;
    logic [P_CTR_WIDTH-1:0]  d0, d1;
    logic ok;
    i0 = 10'd50;   d0 = 6'h1B;
    i1 = 10'd777;  d1 = 6'h07;

    wr_entry2(i0, d0, i1, d1);

    ok = (ram_rd(0, i0) === d0)       &&  // slot 0 wrote its index
         (ram_rd(1, i1) === d1)       &&  // slot 1 wrote its index
         (ram_rd(0, i1) === INIT_VAL) &&  // slot 0 RAM: no slot-1 idx
         (ram_rd(1, i0) === INIT_VAL);    // slot 1 RAM: no slot-0 idx

    if (ok) begin
      $display("[PASS] TC5: slot independence");
      pass_cnt++;
    end else begin
      $display(
        "[FAIL] TC5: s0[i0]=%0h s1[i1]=%0h s0[i1]=%0h s1[i0]=%0h",
        ram_rd(0, i0), ram_rd(1, i1),
        ram_rd(0, i1), ram_rd(1, i0));
      fail_cnt++;
    end
  endtask

  // ----------------------------------------------------------------
  // TC6: tbl_ri override. Assert tbl_ri_active with a concurrent
  // update request. The RI address/data/enable must win (both RAMs
  // written at tbl_ri_wa) and the update must be suppressed (its
  // index stays at INIT_VAL).
  // ----------------------------------------------------------------
  task automatic test_tbl_ri(input int vb);
    logic [P_INDEX_BITS-1:0] iri, iup;
    logic [ALLOC_DATA_W-1:0] dri;
    logic [P_CTR_WIDTH-1:0]  dup;
    logic ok;
    iri = 10'd150; dri = 6'h2C;
    iup = 10'd160; dup = 6'h11;

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
      $display("[PASS] TC6: tbl_ri override");
      pass_cnt++;
    end else begin
      $display(
        "[FAIL] TC6: ri0=%0h ri1=%0h up0=%0h up1=%0h",
        ram_rd(0, iri), ram_rd(1, iri),
        ram_rd(0, iup), ram_rd(1, iup));
      fail_cnt++;
    end
  endtask

  // ----------------------------------------------------------------
  // TC7: bank decomposition. index[9]=0 lands in mem[0][row],
  // index[9]=1 lands in mem[1][row]. Same row, both banks. ST4 has
  // 512 rows per bank.
  // ----------------------------------------------------------------
  task automatic test_bank_decomp(input int vb);
    logic [P_INDEX_BITS-1:0] ilo, ihi;
    logic [P_CTR_WIDTH-1:0]  dlo, dhi;
    logic ok;
    ilo = 10'h020;  // bank 0, row 0x020
    ihi = 10'h220;  // bank 1, row 0x020 (index[9]=1)
    dlo = 6'h05;
    dhi = 6'h0A;

    wr_entry(0, ilo, dlo);
    wr_entry(0, ihi, dhi);

    ok = (u_dut.u_ram_s0.mem[0][ROW_BITS'('h020)] === dlo) &&
         (u_dut.u_ram_s0.mem[1][ROW_BITS'('h020)] === dhi);

    if (ok) begin
      $display("[PASS] TC7: bank decomposition");
      pass_cnt++;
    end else begin
      $display(
        "[FAIL] TC7: bank0[0x20]=%0h(exp %0h) bank1[0x20]=%0h(exp %0h)",
        u_dut.u_ram_s0.mem[0][ROW_BITS'('h020)], dlo,
        u_dut.u_ram_s0.mem[1][ROW_BITS'('h020)], dhi);
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

    // Reset window. sc_brimli has no reset-driven state; the bw_ram
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
    if (_mode_cov    != 0) test_mode_cov(verbose);
    if (_upd_write   != 0) test_upd_write(verbose);
    if (_slot_indep  != 0) test_slot_indep(verbose);
    if (_tbl_ri      != 0) test_tbl_ri(verbose);
    if (_bank_decomp != 0) test_bank_decomp(verbose);

    @(posedge clk); #1;
    $display("--------------------------------------------");
    $display("Results: %0d PASS  %0d FAIL  (of 7 TCs)",
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
