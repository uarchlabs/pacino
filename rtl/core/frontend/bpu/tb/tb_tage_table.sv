// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_tage_table.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking testbench for tage_table.
// DUT is T1-style (THIS_TABLE=1, 11b index, 8b tag,
// 2b EPC, 2b USE, 3b CTR, 1b VAL, NUM_PRED_SLOTS=2).
//
// Hash inputs: tage_pred_inp_p0 + folded_hist. Local hash:
//   idx  = (pc >> INST_OFFSET) ^ fh_idx, [THIS_INDEX_BITS-1:0]
//   tag  = (pc >> THIS_INDEX_BITS) ^ fh1 ^ (fh2<<1),
//          [THIS_TAG_BITS-1:0]
//
// PC stimulus formula (with folded_hist=0):
//   idx_hash = pc[12:2], tag_hash = pc[18:11]
//   Constraint: tag[1:0]==00, idx[10:9]==00 (no pc-bit conflict)
//   pc = ((tag >> 2) << 13) | (idx << 2)
//
// TC1:  prediction read -- hit, taken, cntrl_bits correct.
// TC2:  tag mismatch -- hit=0.
// TC3:  valid bit gate -- entry valid=0, hit=0.
// TC4:  primary CTR update gate (wrong table / correct table).
// TC5:  alt CTR update gate (wrong table / correct table).
// TC6:  USE field update -- cntrl_bits USE bits updated.
// TC7:  allocation write -- full entry verified.
// TC8:  tbl_ri_active override -- RI path overrides writes.
// TC9:  slot 1 independent read -- RAM0/RAM1 independent.
// TC10: dual slot simultaneous predict -- both slots correct.
// TC11: non-zero fh_idx -- index hash adjusted by fh.
// TC12: non-zero fh1    -- tag hash adjusted by fh1.
// TC14: slot 1 write paths -- norm_we_s1 asserted, RAM updated.
// TC15: epc_we_s0 slot 0  -- EPC field updated via epc_wr path.
// TC16: alt CTR slot 1    -- else-if alt_ctr_we_s1 branch covered.
//
// These results need to be checked against results from manual testbench
// ===================================================================
`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  // ----------------------------------------------------------------
  // DUT parameters
  // ----------------------------------------------------------------
  localparam int P_THIS_TABLE      = 1;
  localparam int P_THIS_INDEX_BITS = 11;
  localparam int P_THIS_TAG_BITS   = 8;
  localparam int P_THIS_EPC_WIDTH  = 2;
  localparam int P_THIS_USE_WIDTH  = 2;
  localparam int P_THIS_CTR_WIDTH  = 3;
  localparam int P_THIS_VAL_WIDTH  = 1;
  localparam int P_NUM_PRED_SLOTS  = 2;
  localparam int P_TBL_SEL_WIDTH   = TAGE_TBL_SEL_WIDTH;

  // Derived widths matching DUT localparams
  localparam int CNTRL_BITS_W = TAGE_MAX_EPC_WIDTH
                              + TAGE_MAX_USE_WIDTH
                              + TAGE_MAX_CTR_WIDTH
                              + TAGE_MAX_VAL_WIDTH;          // 8
  localparam int ALLOC_DATA_W = P_THIS_VAL_WIDTH
                              + P_THIS_CTR_WIDTH
                              + P_THIS_USE_WIDTH
                              + P_THIS_EPC_WIDTH
                              + P_THIS_TAG_BITS;        // 16

  // Entry field offsets (must match tage_table localparams)
  localparam int VAL_LSB = 0;
  localparam int CTR_LSB = 1;   // VAL_LSB + 1
  localparam int USE_LSB = 4;   // CTR_LSB + 3
  localparam int EPC_LSB = 6;   // USE_LSB + 2
  localparam int TAG_LSB = 8;   // EPC_LSB + 2

  // ----------------------------------------------------------------
  // PC stimulus constants.
  // Formula (folded_hist=0): idx_hash=pc[12:2], tag_hash=pc[18:11]
  // Constraint: tag[1:0]==00 and idx[10:9]==00.
  // pc = ((tag >> 2) << 13) | (idx << 2)
  //
  // TC1 : idx=0x001, tag=0xAC -> pc=0x56004
  // TC2  mismatch: idx=0x001, tag=0xCC -> pc=0x66004
  // TC3 : idx=0x005, tag=0xEC -> pc=0x76014
  // TC4 : idx=0x010, tag=0xA8 -> pc=0x54040
  // TC4  wrong-tag: idx=0x010, tag=0xC8 -> pc=0x64040
  // TC5 : idx=0x015, tag=0xCC -> pc=0x66054
  // TC6 : idx=0x020, tag=0xDC -> pc=0x6E080
  // TC7 : idx=0x030, tag=0xEC -> pc=0x760C0
  // TC8  predict: idx=0x040, tag=0xAC -> pc=0x56100
  // TC9/TC10 slot0: idx=0x055, tag=0xAC -> pc=0x56154
  // TC9/TC10 slot1: idx=0x055, tag=0xBC -> pc=0x5E154
  // TC11: idx=0x101, tag=0xAC -> pc=0x56404
  //       with fh_idx=0x01: idx_hash=0x101^0x01=0x100
  // TC12: idx=0x008, tag=0x40 -> pc=0x20020
  //       with fh1=0x10: tag_hash=0x40^0x10=0x50
  // TC14: idx=0x050, tag=0xAC -> pc=0x56140 (slot 1 write test)
  // TC15: idx=0x060, tag=0xAC -> pc=0x56180 (epc_we_s0 test)
  // TC16: idx=0x070, tag=0xAC -> pc=0x561C0 (alt CTR slot 1 test)
  // ----------------------------------------------------------------
  localparam logic [VA_WIDTH-1:0] PC_TC1       = 40'h5_6004;
  localparam logic [VA_WIDTH-1:0] PC_TC2_MISS  = 40'h6_6004;
  localparam logic [VA_WIDTH-1:0] PC_TC3       = 40'h7_6014;
  localparam logic [VA_WIDTH-1:0] PC_TC4       = 40'h5_4040;
  localparam logic [VA_WIDTH-1:0] PC_TC4_MISS  = 40'h6_4040;
  localparam logic [VA_WIDTH-1:0] PC_TC5       = 40'h6_6054;
  localparam logic [VA_WIDTH-1:0] PC_TC6       = 40'h6_E080;
  localparam logic [VA_WIDTH-1:0] PC_TC7       = 40'h7_60C0;
  localparam logic [VA_WIDTH-1:0] PC_TC8_PRED  = 40'h5_6100;
  localparam logic [VA_WIDTH-1:0] PC_TC9_S0    = 40'h5_6154;
  localparam logic [VA_WIDTH-1:0] PC_TC9_S1    = 40'h5_E154;
  localparam logic [VA_WIDTH-1:0] PC_TC11      = 40'h5_6404;
  localparam logic [VA_WIDTH-1:0] PC_TC12      = 40'h2_0020;
  localparam logic [VA_WIDTH-1:0] PC_TC14_S1   = 40'h5_6140;
  localparam logic [VA_WIDTH-1:0] PC_TC15_EPC  = 40'h5_6180;
  localparam logic [VA_WIDTH-1:0] PC_TC16_S1   = 40'h5_61C0;

  // ----------------------------------------------------------------
  // Test entry data (ALLOC_DATA_W=16b).
  // Format: [15:8]=TAG, [7:6]=EPC, [5:4]=USE, [3:1]=CTR, [0]=VAL
  // ----------------------------------------------------------------
  // TC1 : tag=AC, ctr=110(T), use=11, epc=10, val=1 -> ACBDh
  localparam logic [ALLOC_DATA_W-1:0] DATA_TC1  = 16'hACBD;
  // TC3 : tag=EC, ctr=100, use=01, epc=01, val=0 -> EC58h
  localparam logic [ALLOC_DATA_W-1:0] DATA_TC3  = 16'hEC58;
  // TC4 : tag=A8, ctr=100(T), use=00, epc=00, val=1 -> A809h
  localparam logic [ALLOC_DATA_W-1:0] DATA_TC4  = 16'hA809;
  // TC5 : tag=CC, ctr=111(T), use=00, epc=00, val=1 -> CC0Fh
  localparam logic [ALLOC_DATA_W-1:0] DATA_TC5  = 16'hCC0F;
  // TC6 : tag=DC, ctr=100(T), use=00, epc=00, val=1 -> DC09h
  localparam logic [ALLOC_DATA_W-1:0] DATA_TC6  = 16'hDC09;
  // TC7 : tag=EC, ctr=101(T), use=10, epc=01, val=1 -> EC6Bh
  localparam logic [ALLOC_DATA_W-1:0] DATA_TC7  = 16'hEC6B;
  // TC9 slot0: tag=AC, ctr=111(T), val=1 -> AC0Fh
  localparam logic [ALLOC_DATA_W-1:0] DATA_TC9_S0 = 16'hAC0F;
  // TC9 slot1: tag=BC, ctr=000(NT), val=1 -> BC01h
  localparam logic [ALLOC_DATA_W-1:0] DATA_TC9_S1 = 16'hBC01;
  // TC11: tag=AC, ctr=110(T), use=11, epc=10, val=1 -> ACBDh
  localparam logic [ALLOC_DATA_W-1:0] DATA_TC11 = 16'hACBD;
  // TC12: tag=50, ctr=110(T), use=11, epc=10, val=1 -> 50BDh
  localparam logic [ALLOC_DATA_W-1:0] DATA_TC12 = 16'h50BD;
  // TC14: slot 1 preload tag=AC, ctr=100(T), use=00, epc=00,
  //       val=1 -> AC09h
  localparam logic [ALLOC_DATA_W-1:0] DATA_TC14_PRE = 16'hAC09;
  // TC15: slot 0 preload tag=AC, ctr=110(T), use=11, epc=00,
  //       val=1 -> AC3Dh
  localparam logic [ALLOC_DATA_W-1:0] DATA_TC15_PRE = 16'hAC3D;
  // TC16: slot 1 preload tag=AC, ctr=111(T), use=00, epc=00,
  //       val=1 -> AC0Fh
  localparam logic [ALLOC_DATA_W-1:0] DATA_TC16_PRE = 16'hAC0F;

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
  logic [P_NUM_PRED_SLOTS-1:0]  hit_p1;
  logic [P_NUM_PRED_SLOTS-1:0]  taken_p1;
  logic [CNTRL_BITS_W-1:0]      cntrl_bits_p1[0:P_NUM_PRED_SLOTS-1];

  logic [P_NUM_PRED_SLOTS-1:0]  tage_pred_val_p0;
  tage_pred_inp_t               tage_pred_inp_p0[0:P_NUM_PRED_SLOTS-1];
  bp_folded_hist_t              folded_hist;

  logic [P_NUM_PRED_SLOTS-1:0]  tage_upd_val_u0;
  logic [P_THIS_CTR_WIDTH-1:0]  prm_ctr_wd_u0[0:P_NUM_PRED_SLOTS-1];
  logic [P_THIS_CTR_WIDTH-1:0]  alt_ctr_wd_u0[0:P_NUM_PRED_SLOTS-1];
  logic [P_THIS_USE_WIDTH-1:0]  use_wd_u0[0:P_NUM_PRED_SLOTS-1];
  logic [P_THIS_EPC_WIDTH-1:0]  epc_wd_u0[0:P_NUM_PRED_SLOTS-1];
  logic [ALLOC_DATA_W-1:0]      alc_wd_u0[0:P_NUM_PRED_SLOTS-1];

  logic [P_NUM_PRED_SLOTS-1:0]  prm_ctr_wr_u0;
  logic [P_NUM_PRED_SLOTS-1:0]  alt_ctr_wr_u0;
  logic [P_NUM_PRED_SLOTS-1:0]  use_wr_u0;
  logic [P_NUM_PRED_SLOTS-1:0]  epc_wr_u0;
  logic [P_NUM_PRED_SLOTS-1:0]  alc_wr_u0;

  logic [P_TBL_SEL_WIDTH-1:0]   prm_tbl_sel_u0[0:P_NUM_PRED_SLOTS-1];
  logic [P_TBL_SEL_WIDTH-1:0]   alt_tbl_sel_u0[0:P_NUM_PRED_SLOTS-1];
  logic [P_TBL_SEL_WIDTH-1:0]   alc_tbl_sel_u0[0:P_NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_IDX_WIDTH-1:0]     upd_index_u0[0:P_NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_IDX_WIDTH-1:0]     alc_index_u0[0:P_NUM_PRED_SLOTS-1];

  logic                         tbl_ri_active;
  logic                         tbl_ri_wr;
  logic [TAGE_MAX_IDX_WIDTH-1:0]     tbl_ri_wa;
  logic [ALLOC_DATA_W-1:0]      tbl_ri_wd;

  logic                         rstn;

  logic [P_THIS_INDEX_BITS-1:0]
    idx_hash_p0[0:P_NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_TAG_WIDTH-1:0]
    tag_hash_p0[0:P_NUM_PRED_SLOTS-1];

  // Mandatory pass criterion for TC14: norm_we_s1 must assert.
  logic norm_we_s1_seen;

  // ----------------------------------------------------------------
  // DUT instantiation
  // ----------------------------------------------------------------
  tage_table #(
    .THIS_TABLE     (P_THIS_TABLE),
    .THIS_INDEX_BITS(P_THIS_INDEX_BITS),
    .THIS_TAG_BITS  (P_THIS_TAG_BITS),
    .THIS_EPC_WIDTH (P_THIS_EPC_WIDTH),
    .THIS_USE_WIDTH (P_THIS_USE_WIDTH),
    .THIS_CTR_WIDTH (P_THIS_CTR_WIDTH),
    .THIS_VAL_WIDTH (P_THIS_VAL_WIDTH),
    .NUM_PRED_SLOTS (P_NUM_PRED_SLOTS),
    .TBL_SEL_WIDTH  (P_TBL_SEL_WIDTH)
  ) u_dut (
    .hit_p1          (hit_p1),
    .taken_p1        (taken_p1),
    .cntrl_bits_p1   (cntrl_bits_p1),
    .idx_hash_p0     (idx_hash_p0),
    .tag_hash_p0     (tag_hash_p0),
    .tage_pred_val_p0(tage_pred_val_p0),
    .tage_pred_inp_p0(tage_pred_inp_p0),
    .folded_hist     (folded_hist),
    .tage_upd_val_u0 (tage_upd_val_u0),
    .prm_ctr_wd_u0   (prm_ctr_wd_u0),
    .alt_ctr_wd_u0   (alt_ctr_wd_u0),
    .use_wd_u0       (use_wd_u0),
    .epc_wd_u0       (epc_wd_u0),
    .alc_wd_u0       (alc_wd_u0),
    .prm_ctr_wr_u0   (prm_ctr_wr_u0),
    .alt_ctr_wr_u0   (alt_ctr_wr_u0),
    .use_wr_u0       (use_wr_u0),
    .epc_wr_u0       (epc_wr_u0),
    .alc_wr_u0       (alc_wr_u0),
    .prm_tbl_sel_u0  (prm_tbl_sel_u0),
    .alt_tbl_sel_u0  (alt_tbl_sel_u0),
    .alc_tbl_sel_u0  (alc_tbl_sel_u0),
    .upd_index_u0    (upd_index_u0),
    .alc_index_u0    (alc_index_u0),
    .tbl_ri_active   (tbl_ri_active),
    .tbl_ri_wr       (tbl_ri_wr),
    .tbl_ri_wa       (tbl_ri_wa),
    .tbl_ri_wd       (tbl_ri_wd),
    .rstn            (rstn),
    .clk             (clk)
  );

  // ----------------------------------------------------------------
  // Pass / fail counters
  // ----------------------------------------------------------------
  int pass_cnt;
  int fail_cnt;

  // ----------------------------------------------------------------
  // Helper: clear all update control signals for one slot
  // ----------------------------------------------------------------
  task automatic clr_upd(input int s);
    tage_upd_val_u0[s]  = 1'b0;
    prm_ctr_wr_u0[s]    = 1'b0;
    alt_ctr_wr_u0[s]    = 1'b0;
    use_wr_u0[s]        = 1'b0;
    epc_wr_u0[s]        = 1'b0;
    alc_wr_u0[s]        = 1'b0;
    prm_ctr_wd_u0[s]    = '0;
    alt_ctr_wd_u0[s]    = '0;
    use_wd_u0[s]        = '0;
    epc_wd_u0[s]        = '0;
    alc_wd_u0[s]        = '0;
    prm_tbl_sel_u0[s]   = '0;
    alt_tbl_sel_u0[s]   = '0;
    alc_tbl_sel_u0[s]   = '0;
    upd_index_u0[s]     = '0;
    alc_index_u0[s]     = '0;
  endtask

  // Helper: clear predict inputs for one slot.
  // folded_hist is shared and managed by the caller.
  task automatic clr_pred(input int s);
    tage_pred_val_p0[s]           = 1'b0;
    tage_pred_inp_p0[s].pc        = '0;
    tage_pred_inp_p0[s].branch_id = '0;
  endtask

  // Helper: write one full entry via alloc write for slot s.
  task automatic do_alc_wr(
    input int                        s,
    input logic [TAGE_MAX_IDX_WIDTH-1:0]  idx,
    input logic [ALLOC_DATA_W-1:0]   data
  );
    tage_upd_val_u0[s]  = 1'b1;
    alc_wr_u0[s]        = 1'b1;
    alc_tbl_sel_u0[s]   = P_TBL_SEL_WIDTH'(P_THIS_TABLE);
    alc_index_u0[s]     = idx;
    alc_wd_u0[s]        = data;
    @(posedge clk); #1;
    clr_upd(s);
  endtask

  // Helper: predict one slot (folded_hist=0) and wait for p1.
  // pc_val must encode desired idx/tag per stimulus formula.
  task automatic do_pred(
    input int                   s,
    input logic [VA_WIDTH-1:0]  pc_val
  );
    tage_pred_val_p0[s]           = 1'b1;
    tage_pred_inp_p0[s].pc        = pc_val;
    tage_pred_inp_p0[s].branch_id = '0;
    folded_hist                   = '0;
    @(posedge clk); #1;
    clr_pred(s);
  endtask

  // ----------------------------------------------------------------
  // TC14: slot 1 write paths
  // Covers norm_we_s1 and lines in addr_mux_s1, din_mux_s1,
  // bweb_mux_s1 for THIS_TABLE=1. Pre-load slot 1 at idx=0x050
  // via alc, then do a combined prm_ctr+use+epc update. Sample
  // norm_we_s1 via hierarchical reference. Predict to confirm
  // written values.
  // Expected after update: ctr=010(NT), use=11, epc=11
  //   -> cntrl_bits_p1[1] = F5h, taken=0.
  // ----------------------------------------------------------------
  task automatic slot1_unit_write_tst();
    do_alc_wr(1, 11'h050, DATA_TC14_PRE);
    tage_upd_val_u0[1] = 1'b1;
    prm_ctr_wr_u0[1]   = 1'b1;
    use_wr_u0[1]       = 1'b1;
    epc_wr_u0[1]       = 1'b1;
    prm_tbl_sel_u0[1]  = P_TBL_SEL_WIDTH'(P_THIS_TABLE);
    upd_index_u0[1]    = 11'h050;
    prm_ctr_wd_u0[1]   = 3'b010;
    use_wd_u0[1]       = 2'b11;
    epc_wd_u0[1]       = 2'b11;
    @(posedge clk); #1;
    norm_we_s1_seen = (u_dut.norm_we_s1 === 1'b1);
    clr_upd(1);
    do_pred(1, PC_TC14_S1);
    if (norm_we_s1_seen === 1'b1 &&
        hit_p1[1]        === 1'b1 &&
        taken_p1[1]      === 1'b0 &&
        cntrl_bits_p1[1] === 8'hF5) begin
      $display("[PASS] TC14: slot 1 write paths");
      pass_cnt++;
    end else begin
      $display(
        "[FAIL] TC14: we=%b hit=%b taken=%b cntrl=%h (exp 1 1 0 F5)",
        norm_we_s1_seen, hit_p1[1],
        taken_p1[1], cntrl_bits_p1[1]);
      fail_cnt++;
    end
  endtask

  // ----------------------------------------------------------------
  // TC15: epc_we_s0 slot 0
  // Covers epc_we_s0 gating (din_mux_s0 and bweb_mux_s0 EPC
  // paths). Pre-load slot 0 at idx=0x060 with epc=00, use=11,
  // ctr=110(T), val=1. Drive epc_wr with prm_match to update
  // EPC to 11. Predict to confirm cntrl EPC field changed.
  // Expected after update: epc=11
  //   -> cntrl_bits_p1[0] = FDh, taken=1.
  // ----------------------------------------------------------------
  task automatic epc_s0_write_tst();
    do_alc_wr(0, 11'h060, DATA_TC15_PRE);
    tage_upd_val_u0[0] = 1'b1;
    epc_wr_u0[0]       = 1'b1;
    prm_tbl_sel_u0[0]  = P_TBL_SEL_WIDTH'(P_THIS_TABLE);
    upd_index_u0[0]    = 11'h060;
    epc_wd_u0[0]       = 2'b11;
    @(posedge clk); #1;
    clr_upd(0);
    do_pred(0, PC_TC15_EPC);
    if (hit_p1[0]        === 1'b1 &&
        taken_p1[0]      === 1'b1 &&
        cntrl_bits_p1[0] === 8'hFD) begin
      $display("[PASS] TC15: epc_we_s0 slot 0");
      pass_cnt++;
    end else begin
      $display(
        "[FAIL] TC15: hit=%b taken=%b cntrl=%h (exp 1 1 FD)",
        hit_p1[0], taken_p1[0], cntrl_bits_p1[0]);
      fail_cnt++;
    end
  endtask

  // ----------------------------------------------------------------
  // TC16: alt CTR write slot 1
  // Covers tage_table.sv din_mux_s1 line 427 (else-if alt_ctr_we_s1
  // branch). Pre-load slot 1 at idx=0x070 with ctr=111(T).
  // Write alt CTR=000 (not taken). Verify taken=0.
  // Expected cntrl: epc=00, use=00, ctr=000, val=1 -> 8'h01.
  // ----------------------------------------------------------------
  task automatic alt_ctr_s1_write_tst();
    do_alc_wr(1, 11'h070, DATA_TC16_PRE);
    tage_upd_val_u0[1] = 1'b1;
    alt_ctr_wr_u0[1]   = 1'b1;
    alt_tbl_sel_u0[1]  = P_TBL_SEL_WIDTH'(P_THIS_TABLE);
    upd_index_u0[1]    = 11'h070;
    alt_ctr_wd_u0[1]   = 3'b000;
    @(posedge clk); #1;
    clr_upd(1);
    do_pred(1, PC_TC16_S1);
    if (hit_p1[1]        === 1'b1 &&
        taken_p1[1]      === 1'b0 &&
        cntrl_bits_p1[1] === 8'h01) begin
      $display("[PASS] TC16: alt CTR write slot 1");
      pass_cnt++;
    end else begin
      $display(
        "[FAIL] TC16: hit=%b taken=%b cntrl=%h (exp 1 0 01)",
        hit_p1[1], taken_p1[1], cntrl_bits_p1[1]);
      fail_cnt++;
    end
  endtask

  // ----------------------------------------------------------------
  // Main test sequence
  // ----------------------------------------------------------------
  initial begin
    // Initialize all inputs
    pass_cnt = 0; fail_cnt = 0;
    rstn = 1'b0;
    tbl_ri_active = 1'b0;
    tbl_ri_wr     = 1'b0;
    tbl_ri_wa     = '0;
    tbl_ri_wd     = '0;
    folded_hist   = '0;
    clr_upd(0); clr_upd(1);
    clr_pred(0); clr_pred(1);
    norm_we_s1_seen = 1'b0;

    // Reset sequence
    repeat(3) @(posedge clk);
    @(posedge clk); #1; rstn = 1'b1;
    @(posedge clk); #1;

    // ============================================================
    // TC1: prediction read
    // Write entry {tag=AC, ctr=110, use=11, epc=10, valid=1}
    // at idx=0x001. Predict at same idx with matching tag.
    // fh=0: idx_hash=pc[12:2]=0x001, tag_hash=pc[18:11]=0xAC.
    // Expected: hit=1, taken=1 (CTR MSB=1), cntrl=8'hBD.
    // ============================================================
    do_alc_wr(0, 11'h001, DATA_TC1);
    do_pred(0, PC_TC1);
    if (hit_p1[0] === 1'b1 &&
        taken_p1[0] === 1'b1 &&
        cntrl_bits_p1[0] === 8'hBD) begin
      $display("[PASS] TC1: prediction read");
      pass_cnt++;
    end else begin
      $display("[FAIL] TC1: hit=%b taken=%b cntrl=%h (exp 1 1 BD)",
               hit_p1[0], taken_p1[0], cntrl_bits_p1[0]);
      fail_cnt++;
    end

    // ============================================================
    // TC2: tag mismatch
    // Reuse TC1 entry (idx=0x001, tag=0xAC). Predict with
    // pc that produces tag=0xCC. Expected: hit=0.
    // ============================================================
    do_pred(0, PC_TC2_MISS);
    if (hit_p1[0] === 1'b0) begin
      $display("[PASS] TC2: tag mismatch");
      pass_cnt++;
    end else begin
      $display("[FAIL] TC2: hit=%b (expected 0)", hit_p1[0]);
      fail_cnt++;
    end

    // ============================================================
    // TC3: valid bit gate
    // Write entry valid=0 at idx=0x005, tag=0xEC.
    // Predict with matching pc. Expected: hit=0.
    // ============================================================
    do_alc_wr(0, 11'h005, DATA_TC3);
    do_pred(0, PC_TC3);
    if (hit_p1[0] === 1'b0) begin
      $display("[PASS] TC3: valid bit gate");
      pass_cnt++;
    end else begin
      $display("[FAIL] TC3: hit=%b (expected 0)", hit_p1[0]);
      fail_cnt++;
    end

    // ============================================================
    // TC4: primary CTR update gate
    // Step A: write entry at idx=0x010, ctr=100(T), tag=0xA8.
    //         initial predict -> hit=1, taken=1.
    // Step B: CTR write with wrong table (tbl=0, not THIS_TABLE=1)
    //         -> CTR unchanged, predict again -> taken still 1.
    // Step C: CTR write correct table -> CTR=010(NT).
    //         predict -> hit=1, taken=0.
    // ============================================================
    do_alc_wr(0, 11'h010, DATA_TC4);
    do_pred(0, PC_TC4);
    if (hit_p1[0] !== 1'b1 || taken_p1[0] !== 1'b1) begin
      $display("[FAIL] TC4 init: hit=%b taken=%b (exp 1 1)",
               hit_p1[0], taken_p1[0]);
      fail_cnt++;
    end
    // Step B: wrong table (no-op)
    tage_upd_val_u0[0] = 1'b1;
    prm_ctr_wr_u0[0]   = 1'b1;
    prm_tbl_sel_u0[0]  = P_TBL_SEL_WIDTH'(0); // wrong table
    upd_index_u0[0]    = 11'h010;
    prm_ctr_wd_u0[0]   = 3'b010;              // would clear taken
    @(posedge clk); #1;
    clr_upd(0);
    do_pred(0, PC_TC4);
    if (hit_p1[0] !== 1'b1 || taken_p1[0] !== 1'b1) begin
      $display("[FAIL] TC4 wrong-tbl: hit=%b taken=%b (exp 1 1)",
               hit_p1[0], taken_p1[0]);
      fail_cnt++;
    end
    // Step C: correct table CTR write
    tage_upd_val_u0[0] = 1'b1;
    prm_ctr_wr_u0[0]   = 1'b1;
    prm_tbl_sel_u0[0]  = P_TBL_SEL_WIDTH'(P_THIS_TABLE);
    upd_index_u0[0]    = 11'h010;
    prm_ctr_wd_u0[0]   = 3'b010;              // not taken
    @(posedge clk); #1;
    clr_upd(0);
    do_pred(0, PC_TC4);
    if (hit_p1[0] === 1'b1 && taken_p1[0] === 1'b0) begin
      $display("[PASS] TC4: primary CTR update gate");
      pass_cnt++;
    end else begin
      $display("[FAIL] TC4 correct-tbl: hit=%b taken=%b (exp 1 0)",
               hit_p1[0], taken_p1[0]);
      fail_cnt++;
    end

    // ============================================================
    // TC5: alt CTR update gate
    // Write entry at idx=0x015, ctr=111(T), tag=0xCC.
    // Step A: alt write wrong table -> no change.
    // Step B: alt write correct table -> CTR=000(NT).
    // ============================================================
    do_alc_wr(0, 11'h015, DATA_TC5);
    // Step A: wrong table alt CTR (no-op)
    tage_upd_val_u0[0] = 1'b1;
    alt_ctr_wr_u0[0]   = 1'b1;
    alt_tbl_sel_u0[0]  = P_TBL_SEL_WIDTH'(0); // wrong table
    upd_index_u0[0]    = 11'h015;
    alt_ctr_wd_u0[0]   = 3'b000;
    @(posedge clk); #1;
    clr_upd(0);
    do_pred(0, PC_TC5);
    if (hit_p1[0] !== 1'b1 || taken_p1[0] !== 1'b1) begin
      $display("[FAIL] TC5 wrong-tbl: hit=%b taken=%b (exp 1 1)",
               hit_p1[0], taken_p1[0]);
      fail_cnt++;
    end
    // Step B: correct table alt CTR write
    tage_upd_val_u0[0] = 1'b1;
    alt_ctr_wr_u0[0]   = 1'b1;
    alt_tbl_sel_u0[0]  = P_TBL_SEL_WIDTH'(P_THIS_TABLE);
    upd_index_u0[0]    = 11'h015;
    alt_ctr_wd_u0[0]   = 3'b000;
    @(posedge clk); #1;
    clr_upd(0);
    do_pred(0, PC_TC5);
    if (hit_p1[0] === 1'b1 && taken_p1[0] === 1'b0) begin
      $display("[PASS] TC5: alt CTR update gate");
      pass_cnt++;
    end else begin
      $display("[FAIL] TC5 correct-tbl: hit=%b taken=%b (exp 1 0)",
               hit_p1[0], taken_p1[0]);
      fail_cnt++;
    end

    // ============================================================
    // TC6: USE field update
    // Write entry at idx=0x020, tag=0xDC, use=00.
    // Update USE to 2'b11. Verify cntrl_bits USE=11.
    // cntrl: [0]=VAL, [3:1]=CTR, [5:4]=USE, [7:6]=EPC.
    // After update: EPC=00, USE=11, CTR=100, VAL=1 -> 8'h39.
    // ============================================================
    do_alc_wr(0, 11'h020, DATA_TC6);
    tage_upd_val_u0[0] = 1'b1;
    use_wr_u0[0]       = 1'b1;
    prm_tbl_sel_u0[0]  = P_TBL_SEL_WIDTH'(P_THIS_TABLE);
    upd_index_u0[0]    = 11'h020;
    use_wd_u0[0]       = 2'b11;
    @(posedge clk); #1;
    clr_upd(0);
    do_pred(0, PC_TC6);
    if (hit_p1[0] === 1'b1 && cntrl_bits_p1[0] === 8'h39) begin
      $display("[PASS] TC6: USE field update");
      pass_cnt++;
    end else begin
      $display("[FAIL] TC6: hit=%b cntrl=%h (exp 1 39)",
               hit_p1[0], cntrl_bits_p1[0]);
      fail_cnt++;
    end

    // ============================================================
    // TC7: allocation write
    // Full entry at idx=0x030: tag=EC, ctr=101(T), use=10,
    // epc=01, valid=1. cntrl expected: 8'h6B.
    // ============================================================
    do_alc_wr(0, 11'h030, DATA_TC7);
    do_pred(0, PC_TC7);
    if (hit_p1[0] === 1'b1 &&
        taken_p1[0] === 1'b1 &&
        cntrl_bits_p1[0] === 8'h6B) begin
      $display("[PASS] TC7: allocation write");
      pass_cnt++;
    end else begin
      $display("[FAIL] TC7: hit=%b taken=%b cntrl=%h (exp 1 1 6B)",
               hit_p1[0], taken_p1[0], cntrl_bits_p1[0]);
      fail_cnt++;
    end

    // ============================================================
    // TC8: tbl_ri_active override
    // RI write: tag=AC, EPC=11, USE=00, CTR=110(T), VAL=1
    // tbl_ri_wd=ACCDh to idx=0x040 via RI path.
    // After RI: predict at idx=0x040, tag=0xAC -> hit=1, taken=1.
    // Note: RI write also populates T2/T3/T4 at idx=0x040 --
    //   used by TC13 fh_sel_arms_tst.
    // ============================================================
    tbl_ri_active = 1'b1;
    tbl_ri_wr     = 1'b1;
    tbl_ri_wa     = 11'h040;
    tbl_ri_wd     = 16'hACCD;
    @(posedge clk); #1;
    tbl_ri_active = 1'b0;
    tbl_ri_wr     = 1'b0;
    tbl_ri_wa     = '0;
    tbl_ri_wd     = '0;
    do_pred(0, PC_TC8_PRED);
    if (hit_p1[0] === 1'b1 && taken_p1[0] === 1'b1) begin
      $display("[PASS] TC8: tbl_ri_active override");
      pass_cnt++;
    end else begin
      $display("[FAIL] TC8: hit=%b taken=%b (exp 1 1)",
               hit_p1[0], taken_p1[0]);
      fail_cnt++;
    end

    // ============================================================
    // TC9: slot 1 independent read
    // Write different entries to idx=0x055 in each slot's RAM.
    // Slot 0: tag=AC, ctr=111(T) data=AC0Fh
    // Slot 1: tag=BC, ctr=000(NT) data=BC01h
    // Predict slot 0 -> hit=1, taken=1.
    // Predict slot 1 -> hit=1, taken=0.
    // ============================================================
    tage_upd_val_u0     = 2'b11;
    alc_wr_u0           = 2'b11;
    alc_tbl_sel_u0[0]   = P_TBL_SEL_WIDTH'(P_THIS_TABLE);
    alc_tbl_sel_u0[1]   = P_TBL_SEL_WIDTH'(P_THIS_TABLE);
    alc_index_u0[0]     = 11'h055;
    alc_index_u0[1]     = 11'h055;
    alc_wd_u0[0]        = DATA_TC9_S0;
    alc_wd_u0[1]        = DATA_TC9_S1;
    @(posedge clk); #1;
    clr_upd(0); clr_upd(1);
    // Predict slot 0 only
    do_pred(0, PC_TC9_S0);
    if (hit_p1[0] !== 1'b1 || taken_p1[0] !== 1'b1) begin
      $display("[FAIL] TC9 slot0: hit=%b taken=%b (exp 1 1)",
               hit_p1[0], taken_p1[0]);
      fail_cnt++;
    end
    // Predict slot 1 only
    do_pred(1, PC_TC9_S1);
    if (hit_p1[1] === 1'b1 && taken_p1[1] === 1'b0) begin
      $display("[PASS] TC9: slot 1 independent read");
      pass_cnt++;
    end else begin
      $display("[FAIL] TC9 slot1: hit=%b taken=%b (exp 1 0)",
               hit_p1[1], taken_p1[1]);
      fail_cnt++;
    end

    // ============================================================
    // TC10: dual slot simultaneous predict
    // Entries from TC9 still at idx=0x055.
    // Each slot uses its own PC encoding a different tag.
    // fh=0: tag_s0 = pc_s0[18:11]=0xAC, tag_s1 = pc_s1[18:11]=0xBC
    // Both tage_pred_val_p0 asserted same cycle.
    // Expected: hit[1:0]=2'b11, taken[0]=1, taken[1]=0.
    // ============================================================
    tage_pred_val_p0              = 2'b11;
    tage_pred_inp_p0[0].pc        = PC_TC9_S0;
    tage_pred_inp_p0[0].branch_id = '0;
    tage_pred_inp_p0[1].pc        = PC_TC9_S1;
    tage_pred_inp_p0[1].branch_id = '0;
    folded_hist                   = '0;
    @(posedge clk); #1;
    clr_pred(0); clr_pred(1);
    if (hit_p1[0] === 1'b1 && taken_p1[0] === 1'b1 &&
        hit_p1[1] === 1'b1 && taken_p1[1] === 1'b0) begin
      $display("[PASS] TC10: dual slot simultaneous predict");
      pass_cnt++;
    end else begin
      $display("[FAIL] TC10: h0=%b t0=%b h1=%b t1=%b (exp 1 1 1 0)",
               hit_p1[0], taken_p1[0], hit_p1[1], taken_p1[1]);
      fail_cnt++;
    end

    // ============================================================
    // TC11: non-zero fh_idx -- index hash adjusted by fh.
    // Write entry at explicit idx=0x100, tag=0xAC, data=ACBDh.
    // Predict with pc[12:2]=0x101 and fh.tage_t1_idx_fh=0x01:
    //   idx_hash = 0x101 ^ 0x01 = 0x100 -> hits the entry.
    // tag_hash = pc[18:11] ^ fh1 ^ (fh2<<1) = 0xAC ^ 0 ^ 0 = 0xAC.
    // Expected: hit=1, taken=1 (CTR=110).
    // ============================================================
    do_alc_wr(0, 11'h100, DATA_TC11);
    tage_pred_val_p0[0]           = 1'b1;
    tage_pred_inp_p0[0].pc        = PC_TC11;
    tage_pred_inp_p0[0].branch_id = '0;
    folded_hist                   = '0;
    folded_hist.tage_t1_idx_fh    = TAGE_MAX_FH'('h01);
    @(posedge clk); #1;
    clr_pred(0);
    folded_hist = '0;
    if (hit_p1[0] === 1'b1 && taken_p1[0] === 1'b1) begin
      $display("[PASS] TC11: non-zero fh_idx adjusts index hash");
      pass_cnt++;
    end else begin
      $display("[FAIL] TC11: hit=%b taken=%b (exp 1 1)",
               hit_p1[0], taken_p1[0]);
      fail_cnt++;
    end

    // ============================================================
    // TC12: non-zero fh1 -- tag hash adjusted by fh1.
    // Write entry at idx=0x008, tag=0x50, data=50BDh.
    // Predict with pc[12:2]=0x008, pc[18:11]=0x40,
    // fh.tage_t1_tag_fh1=0x10:
    //   tag_hash = 0x40 ^ 0x10 ^ 0 = 0x50 -> hits the entry.
    //   idx_hash = pc[12:2] ^ 0 = 0x008 -> correct address.
    // Expected: hit=1, taken=1 (CTR=110).
    // ============================================================
    do_alc_wr(0, 11'h008, DATA_TC12);
    tage_pred_val_p0[0]            = 1'b1;
    tage_pred_inp_p0[0].pc         = PC_TC12;
    tage_pred_inp_p0[0].branch_id  = '0;
    folded_hist                    = '0;
    folded_hist.tage_t1_tag_fh1    = TAGE_MAX_FH1'('h10);
    @(posedge clk); #1;
    clr_pred(0);
    folded_hist = '0;
    if (hit_p1[0] === 1'b1 && taken_p1[0] === 1'b1) begin
      $display("[PASS] TC12: non-zero fh1 adjusts tag hash");
      pass_cnt++;
    end else begin
      $display("[FAIL] TC12: hit=%b taken=%b (exp 1 1)",
               hit_p1[0], taken_p1[0]);
      fail_cnt++;
    end

    // ============================================================
    // TC14: slot 1 write paths
    // ============================================================
    slot1_unit_write_tst();

    // ============================================================
    // TC15: epc_we_s0 slot 0
    // ============================================================
    epc_s0_write_tst();

    // ============================================================
    // TC16: alt CTR write slot 1
    // ============================================================
    alt_ctr_s1_write_tst();

    // ============================================================
    // Summary
    // ============================================================
    @(posedge clk); #1;
    $display("--------------------------------------------");
    $display("Results: %0d PASS  %0d FAIL  (of 15 TCs)",
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
