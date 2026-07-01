// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_sc_cntrl.sv
// DATE:    2026-07-01
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking unit testbench for sc_cntrl (SC control layer).
// DUT instantiated directly as u_dut. NUM_PRED_SLOTS=2. The five SC
// tables are NOT instantiated (sc_cntrl is logic only, BP-077); the
// tb drives the table read ports (t_ctr_p3, t_idx_hash_p2) and
// samples the table write ports (t_ctr_wd_u0, t_ctr_wr_u0,
// t_upd_index_u0) directly.
//
// Prediction is a two-phase drive: tage_pred_meta_p2 and
// t_idx_hash_p2 are presented at p2 and clocked; t_ctr_p3 is then
// presented at p3, where sc_pred_meta_p3 forms combinationally.
//
// Global control state (threshold, tc_reg, choose_hi_vlo,
// choose_med_vvlo, br_imli, bb_hist, last_back_pc) is scalar and is
// read / seeded by hierarchical reference (u_dut.<name>), the same
// convention used by tb_tage_tasks / tb_ittage_cntrl.
//
// TC1 sum/direction  -- signed sum, abs_sum, lcl direction, capture.
// TC2 bands          -- vlo/vvlo boundary vs threshold>>1 / >>2.
// TC3 chooser corners-- agree, corner1 +/-, corner2 +/-, differ.
// TC4 update gate    -- sc_wrong x sc_lo_upd -> do_update (ctr_wr).
// TC5 threshold adapt-- TC to max/min steps threshold, TC resets;
//                       sat_thr bounds at SC_THRSH_MIN/MAX.
// TC6 counter update -- sat_sc step toward resolved, saturation,
//                       index passthrough, gate-off suppression.
// TC7 chooser train  -- HIGH / MED arms, inc/dec, sat_ch bounds.
// TC8 BrIMLI         -- region match inc (saturating), region change
//                       shift + reset, last_back_pc capture.
// ===================================================================
`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  localparam int P_SLOTS = NUM_PRED_SLOTS;   // 2
  localparam int NT      = SC_NUM_TABLES;    // 5

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
  logic                        rstn;

  logic [P_SLOTS-1:0]          tage_pred_rdy_p2;
  tage_pred_meta_t             tage_pred_meta_p2[0:P_SLOTS-1];
  logic [VA_WIDTH-1:1]         inp_pc_p2[0:P_SLOTS-1];
  logic [9:0]                  sc_phr_p2;
  logic [SC_MAX_FH-1:0]        sc_t1_idx_fh_p2;
  logic [SC_MAX_FH-1:0]        sc_t2_idx_fh_p2;
  logic [SC_MAX_FH-1:0]        sc_t3_idx_fh_p2;
  br_imli_mode_e               br_imli_mode;
  logic [P_SLOTS-1:0]          sc_pred_rdy_p3;
  sc_pred_meta_t               sc_pred_meta_p3[0:P_SLOTS-1];

  logic [P_SLOTS-1:0]          sc_upd_val_u0;
  sc_upd_inp_t                 sc_upd_inp_u0[0:P_SLOTS-1];
  logic [P_SLOTS-1:0]          sc_upd_rdy_u1;

  logic [P_SLOTS-1:0]          t_sc_pred_val_p2;
  logic [VA_WIDTH-1:1]         t_inp_pc_p2[0:P_SLOTS-1];
  logic [SC_MAX_FH-1:0]        t_idx_fh_p2[0:NT-1];
  logic [9:0]                  t_sc_phr_p2;
  logic [9:0]                  t_br_imli;
  br_imli_mode_e               t_br_imli_mode;

  logic [SC_MAX_CTR_WIDTH-1:0] t_ctr_p3[0:NT-1][0:P_SLOTS-1];
  logic [SC_MAX_IDX_WIDTH-1:0] t_idx_hash_p2[0:NT-1][0:P_SLOTS-1];

  logic [P_SLOTS-1:0]          t_sc_upd_val_u0[0:NT-1];
  logic [SC_MAX_CTR_WIDTH-1:0] t_ctr_wd_u0[0:NT-1][0:P_SLOTS-1];
  logic [P_SLOTS-1:0]          t_ctr_wr_u0[0:NT-1];
  logic [SC_MAX_IDX_WIDTH-1:0] t_upd_index_u0[0:NT-1][0:P_SLOTS-1];

  // ----------------------------------------------------------------
  // DUT instantiation
  // ----------------------------------------------------------------
  sc_cntrl #(
    .NUM_PRED_SLOTS(P_SLOTS)
  ) u_dut (
    .clk             (clk),
    .rstn            (rstn),
    .tage_pred_rdy_p2(tage_pred_rdy_p2),
    .tage_pred_meta_p2(tage_pred_meta_p2),
    .inp_pc_p2       (inp_pc_p2),
    .sc_phr_p2       (sc_phr_p2),
    .sc_t1_idx_fh_p2 (sc_t1_idx_fh_p2),
    .sc_t2_idx_fh_p2 (sc_t2_idx_fh_p2),
    .sc_t3_idx_fh_p2 (sc_t3_idx_fh_p2),
    .br_imli_mode    (br_imli_mode),
    .sc_pred_rdy_p3  (sc_pred_rdy_p3),
    .sc_pred_meta_p3 (sc_pred_meta_p3),
    .sc_upd_val_u0   (sc_upd_val_u0),
    .sc_upd_inp_u0   (sc_upd_inp_u0),
    .sc_upd_rdy_u1   (sc_upd_rdy_u1),
    .t_sc_pred_val_p2(t_sc_pred_val_p2),
    .t_inp_pc_p2     (t_inp_pc_p2),
    .t_idx_fh_p2     (t_idx_fh_p2),
    .t_sc_phr_p2     (t_sc_phr_p2),
    .t_br_imli       (t_br_imli),
    .t_br_imli_mode  (t_br_imli_mode),
    .t_ctr_p3        (t_ctr_p3),
    .t_idx_hash_p2   (t_idx_hash_p2),
    .t_sc_upd_val_u0 (t_sc_upd_val_u0),
    .t_ctr_wd_u0     (t_ctr_wd_u0),
    .t_ctr_wr_u0     (t_ctr_wr_u0),
    .t_upd_index_u0  (t_upd_index_u0)
  );

  // ----------------------------------------------------------------
  // Pass / fail counters and per-test enables
  // ----------------------------------------------------------------
  int pass_cnt;
  int fail_cnt;

  int verbose      = 1;
  int _sum_dir     = 1;
  int _bands       = 1;
  int _chooser     = 1;
  int _gate        = 1;
  int _thr_adapt   = 1;
  int _ctr_upd     = 1;
  int _ch_train    = 1;
  int _brimli      = 1;

  // ----------------------------------------------------------------
  // Prediction stimulus (module-level, consumed by do_predict)
  // ----------------------------------------------------------------
  logic signed [4:0]           p_extd;   // tage_extd_ctr, 5b signed
  logic                        p_strong;
  logic                        p_medium;
  logic                        p_tage_tkn;
  logic [FTQ_IDX_BITS-1:0]     p_bid;
  logic signed [SC_MAX_CTR_WIDTH-1:0] p_ctr[0:NT-1];
  logic [SC_MAX_IDX_WIDTH-1:0]        p_idx[0:NT-1];

  // ----------------------------------------------------------------
  // Update stimulus (module-level, consumed by drive_update)
  // ----------------------------------------------------------------
  logic                        u_lcl;
  logic                        u_final;
  logic                        u_tage;
  logic                        u_resolved;
  logic                        u_back;
  logic [SC_LSUM_BITS-1:0]     u_abs;
  bp_sc_chooser_e              u_chooser;
  logic signed [SC_MAX_CTR_WIDTH-1:0] u_ctr[0:NT-1];
  logic [SC_MAX_IDX_WIDTH-1:0]        u_idx[0:NT-1];
  logic [9:0]                  u_range;

  // ----------------------------------------------------------------
  // Generic width-masked check.
  // chkw takes 64-bit got/exp so any DUT signal width can be checked
  // through one helper; the narrower actuals are zero-extended into
  // the 64-bit formals. That widening is benign here (values are
  // masked to w bits before compare), so WIDTHEXPAND is suppressed
  // for the check-helper region only.
  // ----------------------------------------------------------------
  /* verilator lint_off WIDTHEXPAND */
  task automatic chkw(input string nm, input int w,
                      input logic [63:0] got, input logic [63:0] exp);
    logic [63:0] m;
    m = (w >= 64) ? '1 : ((64'd1 << w) - 64'd1);
    if ((got & m) === (exp & m)) begin
      pass_cnt++;
      if (verbose != 0) $display("[PASS] %s", nm);
    end else begin
      fail_cnt++;
      $display("[FAIL] %s got=%0h exp=%0h", nm, got & m, exp & m);
    end
  endtask

  // ----------------------------------------------------------------
  // Reference saturating counter step (mirrors sc_cntrl sat_sc)
  // ----------------------------------------------------------------
  function automatic logic [SC_MAX_CTR_WIDTH-1:0] ref_sat_sc(
      input logic signed [SC_MAX_CTR_WIDTH-1:0] c, input int d);
    logic signed [SC_MAX_CTR_WIDTH-1:0] r;
    if (d == 0)                          r = c;
    else if ((c == SC_CTR_MIN) && d < 0) r = c;
    else if ((c == SC_CTR_MAX) && d > 0) r = c;
    else                                 r = c + SC_MAX_CTR_WIDTH'(d);
    return r;
  endfunction

  // ----------------------------------------------------------------
  // Seed the scalar global state by hierarchical reference
  // ----------------------------------------------------------------
  task automatic set_state(
      input logic [9:0]         thr,
      input logic signed [6:0]  tc,
      input logic signed [5:0]  chi,
      input logic signed [5:0]  cmed,
      input logic [9:0]         bri,
      input logic [9:0]         bbh,
      input logic [10:0]        lbp);
    u_dut.threshold       = thr;
    u_dut.tc_reg          = tc;
    u_dut.choose_hi_vlo   = chi;
    u_dut.choose_med_vvlo = cmed;
    u_dut.br_imli         = bri;
    u_dut.bb_hist         = bbh;
    u_dut.last_back_pc    = lbp;
    #1;
  endtask

  // ----------------------------------------------------------------
  // Clear prediction and update inputs
  // ----------------------------------------------------------------
  task automatic clr_inputs();
    tage_pred_rdy_p2 = '0;
    sc_upd_val_u0    = '0;
    for (int s = 0; s < P_SLOTS; s++) begin
      tage_pred_meta_p2[s] = '0;
      inp_pc_p2[s]         = '0;
      sc_upd_inp_u0[s]     = '0;
    end
    sc_phr_p2       = '0;
    sc_t1_idx_fh_p2 = '0;
    sc_t2_idx_fh_p2 = '0;
    sc_t3_idx_fh_p2 = '0;
    br_imli_mode    = IDX_IMLI_PHR;
    for (int t = 0; t < NT; t++)
      for (int s = 0; s < P_SLOTS; s++) begin
        t_ctr_p3[t][s]      = '0;
        t_idx_hash_p2[t][s] = '0;
      end
  endtask

  // ----------------------------------------------------------------
  // Two-phase prediction drive on slot s. Presents meta+index at p2,
  // clocks, then presents counters at p3 where the result forms.
  // ----------------------------------------------------------------
  task automatic do_predict(input int s);
    tage_pred_rdy_p2       = '0;
    tage_pred_rdy_p2[s]    = 1'b1;
    tage_pred_meta_p2[s]   = '0;
    tage_pred_meta_p2[s].tage_extd_ctr    = p_extd;
    tage_pred_meta_p2[s].tage_pred_strong = p_strong;
    tage_pred_meta_p2[s].tage_pred_medium = p_medium;
    tage_pred_meta_p2[s].tage_pred_tkn    = p_tage_tkn;
    tage_pred_meta_p2[s].branch_id        = p_bid;
    for (int t = 0; t < NT; t++) t_idx_hash_p2[t][s] = p_idx[t];
    @(posedge clk); #1;
    for (int t = 0; t < NT; t++) t_ctr_p3[t][s] = p_ctr[t];
    #1;
  endtask

  // ----------------------------------------------------------------
  // Build the update bundle on slot s from module-level u_* stimulus.
  // Combinational drive only; caller decides whether to clock.
  // ----------------------------------------------------------------
  task automatic drive_update(input int s);
    sc_upd_val_u0      = '0;
    sc_upd_val_u0[s]   = 1'b1;
    sc_upd_inp_u0[s]   = '0;
    sc_upd_inp_u0[s].sc_pred_meta.sc_lcl_pred_tkn  = u_lcl;
    sc_upd_inp_u0[s].sc_pred_meta.sc_pred_tkn      = u_final;
    sc_upd_inp_u0[s].sc_pred_meta.sc_tage_pred_tkn = u_tage;
    sc_upd_inp_u0[s].sc_pred_meta.sc_abs_sum       = u_abs;
    sc_upd_inp_u0[s].sc_pred_meta.sc_chooser       = u_chooser;
    for (int t = 0; t < NT; t++) begin
      sc_upd_inp_u0[s].sc_pred_meta.sc_upd_ctr[t] =
        SC_MAX_DATA_WIDTH'(u_ctr[t]);
      sc_upd_inp_u0[s].sc_pred_meta.sc_upd_idx[t] = u_idx[t];
    end
    sc_upd_inp_u0[s].resolved_taken   = u_resolved;
    sc_upd_inp_u0[s].backwards_branch = u_back;
    sc_upd_inp_u0[s].branch_range     = u_range;
    #1;
  endtask

  // ----------------------------------------------------------------
  // Clocked single-cycle update on slot s. Aligns to a negedge so the
  // drive setup does not straddle a clock edge, applies exactly one
  // posedge, then deasserts the request. Used by the state-updating
  // tests (threshold, chooser training, BrIMLI). The scalar global
  // state must advance by exactly one update per clock.
  // ----------------------------------------------------------------
  task automatic clk_update(input int s);
    @(posedge clk); #1;    // land just after an edge (request still 0)
    drive_update(s);       // assert the request; settles well before edge
    @(posedge clk); #1;    // exactly one edge samples the request
    sc_upd_val_u0 = '0;
    #1;
  endtask

  // ================================================================
  // TC1: signed sum, magnitude, local direction, capture.
  // ================================================================
  task automatic test_sum_dir();
    int exp_sum;
    // Positive case: ctr=[3,-2,5,0,-1] extd=2 -> vals 7,-3,11,1,-1
    //   sum=15+2=17, abs=17, lcl=1.
    clr_inputs();
    p_ctr[0]=6'sd3;  p_ctr[1]=-6'sd2; p_ctr[2]=6'sd5;
    p_ctr[3]=6'sd0;  p_ctr[4]=-6'sd1;
    p_idx[0]=10'h011; p_idx[1]=10'h022; p_idx[2]=10'h033;
    p_idx[3]=10'h044; p_idx[4]=10'h055;
    p_extd=5'sd2; p_strong=0; p_medium=0; p_tage_tkn=0; p_bid=6'd7;
    do_predict(0);
    exp_sum = 17;
    chkw("TC1 pos sc_sum",     SC_LSUM_BITS,
         sc_pred_meta_p3[0].sc_sum, exp_sum);
    chkw("TC1 pos abs_sum",    SC_LSUM_BITS,
         sc_pred_meta_p3[0].sc_abs_sum, 17);
    chkw("TC1 pos lcl_tkn",    1,
         sc_pred_meta_p3[0].sc_lcl_pred_tkn, 1);
    chkw("TC1 pos rdy_p3",     1, sc_pred_rdy_p3[0], 1);
    chkw("TC1 pos branch_id",  FTQ_IDX_BITS,
         sc_pred_meta_p3[0].branch_id, 7);
    // captured counters and indices
    for (int t = 0; t < NT; t++) begin
      chkw($sformatf("TC1 cap ctr[%0d]", t), SC_MAX_CTR_WIDTH,
           sc_pred_meta_p3[0].sc_upd_ctr[t], p_ctr[t]);
      chkw($sformatf("TC1 cap idx[%0d]", t), SC_MAX_IDX_WIDTH,
           sc_pred_meta_p3[0].sc_upd_idx[t], p_idx[t]);
    end

    // Negative case: ctr all -5 -> val -9 each, sum=-45, abs=45, lcl=0
    clr_inputs();
    for (int t = 0; t < NT; t++) begin p_ctr[t]=-6'sd5; p_idx[t]='0; end
    p_extd=5'sd0; p_strong=0; p_medium=0; p_tage_tkn=1; p_bid=6'd0;
    do_predict(1);
    exp_sum = -45;
    chkw("TC1 neg sc_sum",  SC_LSUM_BITS,
         sc_pred_meta_p3[1].sc_sum, exp_sum);
    chkw("TC1 neg abs_sum", SC_LSUM_BITS,
         sc_pred_meta_p3[1].sc_abs_sum, 45);
    chkw("TC1 neg lcl_tkn", 1,
         sc_pred_meta_p3[1].sc_lcl_pred_tkn, 0);
  endtask

  // ================================================================
  // TC2: vlo/vvlo band boundaries. threshold=10 -> >>1=5, >>2=2.
  // sc_chooser reveals the band: CHOOSE_HIGH iff (tage_hi & sc_vlo);
  // CHOOSE_MED iff (tage_med & sc_vvlo). All cases use lcl!=tage.
  // With ctr all 0 (val=1 each => 5) sum = 5 + extd.
  // ================================================================
  task automatic test_bands();
    clr_inputs();
    set_state(10'd10, '0, '0, '0, '0, '0, '0);

    // -- vlo boundary: tage_hi=1, tage_med=0, lcl=1 (sum>=0), tage=0
    for (int t = 0; t < NT; t++) p_ctr[t] = '0;
    p_strong=1; p_medium=0; p_tage_tkn=0;

    // abs=4 (<5): extd=-1 -> sum=4 -> CHOOSE_HIGH
    p_extd = -5'sd1;
    do_predict(0);
    chkw("TC2 vlo in  (abs4)  chooser", 2,
         sc_pred_meta_p3[0].sc_chooser, CHOOSE_HIGH);
    // abs=5 (not<5): extd=0 -> sum=5 -> no corner -> CHOOSE_NONE
    p_extd = 5'sd0;
    do_predict(0);
    chkw("TC2 vlo out (abs5)  chooser", 2,
         sc_pred_meta_p3[0].sc_chooser, CHOOSE_NONE);

    // -- vvlo boundary: tage_hi=0, tage_med=1
    p_strong=0; p_medium=1; p_tage_tkn=0;
    // abs=1 (<2): extd=-4 -> sum=1 -> CHOOSE_MED
    p_extd = -5'sd4;
    do_predict(0);
    chkw("TC2 vvlo in  (abs1) chooser", 2,
         sc_pred_meta_p3[0].sc_chooser, CHOOSE_MED);
    // abs=2 (not<2): extd=-3 -> sum=2 -> CHOOSE_NONE
    p_extd = -5'sd3;
    do_predict(0);
    chkw("TC2 vvlo out (abs2) chooser", 2,
         sc_pred_meta_p3[0].sc_chooser, CHOOSE_NONE);
  endtask

  // ================================================================
  // TC3: chooser corner selection (final_pred, override, chooser).
  // threshold=10. ctr all 0 -> sum=5+extd.
  // ================================================================
  task automatic test_chooser();
    clr_inputs();
    for (int t = 0; t < NT; t++) p_ctr[t] = '0;

    // -- agree: lcl==tage. sum=5 (lcl=1), tage=1.
    set_state(10'd10, '0, '0, '0, '0, '0, '0);
    p_extd=5'sd0; p_strong=1; p_medium=0; p_tage_tkn=1;
    do_predict(0);
    chkw("TC3 agree final",    1, sc_pred_meta_p3[0].sc_pred_tkn, 1);
    chkw("TC3 agree override", 1, sc_pred_meta_p3[0].sc_override, 0);
    chkw("TC3 agree chooser",  2,
         sc_pred_meta_p3[0].sc_chooser, CHOOSE_NONE);

    // -- corner1 positive (choose_hi_vlo>=0): final=lcl, override=1.
    // tage_hi=1, vlo (abs4<5), differ (lcl=1,tage=0).
    set_state(10'd10, '0, '0, '0, '0, '0, '0);
    p_extd=-5'sd1; p_strong=1; p_medium=0; p_tage_tkn=0;
    do_predict(0);
    chkw("TC3 c1+ final",    1, sc_pred_meta_p3[0].sc_pred_tkn, 1);
    chkw("TC3 c1+ override", 1, sc_pred_meta_p3[0].sc_override, 1);
    chkw("TC3 c1+ chooser",  2,
         sc_pred_meta_p3[0].sc_chooser, CHOOSE_HIGH);

    // -- corner1 negative (choose_hi_vlo<0): final=tage, override=0.
    set_state(10'd10, '0, 6'sh3F, '0, '0, '0, '0);   // chi = -1
    p_extd=-5'sd1; p_strong=1; p_medium=0; p_tage_tkn=0;
    do_predict(0);
    chkw("TC3 c1- final",    1, sc_pred_meta_p3[0].sc_pred_tkn, 0);
    chkw("TC3 c1- override", 1, sc_pred_meta_p3[0].sc_override, 0);
    chkw("TC3 c1- chooser",  2,
         sc_pred_meta_p3[0].sc_chooser, CHOOSE_HIGH);

    // -- corner2 positive (choose_med_vvlo>=0): tage_med, vvlo.
    set_state(10'd10, '0, '0, '0, '0, '0, '0);
    p_extd=-5'sd4; p_strong=0; p_medium=1; p_tage_tkn=0;  // abs1
    do_predict(0);
    chkw("TC3 c2+ final",    1, sc_pred_meta_p3[0].sc_pred_tkn, 1);
    chkw("TC3 c2+ override", 1, sc_pred_meta_p3[0].sc_override, 1);
    chkw("TC3 c2+ chooser",  2,
         sc_pred_meta_p3[0].sc_chooser, CHOOSE_MED);

    // -- corner2 negative (choose_med_vvlo<0): final=tage.
    set_state(10'd10, '0, '0, 6'sh3F, '0, '0, '0);   // cmed = -1
    p_extd=-5'sd4; p_strong=0; p_medium=1; p_tage_tkn=0;
    do_predict(0);
    chkw("TC3 c2- final",    1, sc_pred_meta_p3[0].sc_pred_tkn, 0);
    chkw("TC3 c2- override", 1, sc_pred_meta_p3[0].sc_override, 0);
    chkw("TC3 c2- chooser",  2,
         sc_pred_meta_p3[0].sc_chooser, CHOOSE_MED);

    // -- general differ (no corner): tage_hi=0,tage_med=0, differ.
    set_state(10'd10, '0, '0, '0, '0, '0, '0);
    p_extd=5'sd0; p_strong=0; p_medium=0; p_tage_tkn=0;   // sum5,lcl1
    do_predict(0);
    chkw("TC3 gen final",    1, sc_pred_meta_p3[0].sc_pred_tkn, 1);
    chkw("TC3 gen override", 1, sc_pred_meta_p3[0].sc_override, 1);
    chkw("TC3 gen chooser",  2,
         sc_pred_meta_p3[0].sc_chooser, CHOOSE_NONE);
  endtask

  // ================================================================
  // TC4: update gate do_update = sc_wrong || sc_lo_upd, observed on
  // the table counter write strobe (t_ctr_wr_u0 = val & do_update).
  // threshold=10.
  // ================================================================
  task automatic test_gate();
    clr_inputs();
    set_state(10'd10, '0, '0, '0, '0, '0, '0);
    u_chooser = CHOOSE_NONE;
    for (int t = 0; t < NT; t++) begin u_ctr[t]='0; u_idx[t]='0; end
    u_final=0; u_tage=0; u_back=0; u_range='0;

    // wrong=0, lo=0: lcl==res, abs(20)>=thr(10) -> no update
    u_lcl=1; u_resolved=1; u_abs=10'd20;
    drive_update(0);
    chkw("TC4 !wrong !lo  wr", 1, t_ctr_wr_u0[0][0], 0);
    // wrong=1, lo=0
    u_lcl=0; u_resolved=1; u_abs=10'd20;
    drive_update(0);
    chkw("TC4  wrong !lo  wr", 1, t_ctr_wr_u0[0][0], 1);
    // wrong=0, lo=1: abs(5)<thr(10)
    u_lcl=1; u_resolved=1; u_abs=10'd5;
    drive_update(0);
    chkw("TC4 !wrong  lo  wr", 1, t_ctr_wr_u0[0][0], 1);
    // wrong=1, lo=1
    u_lcl=0; u_resolved=1; u_abs=10'd5;
    drive_update(0);
    chkw("TC4  wrong  lo  wr", 1, t_ctr_wr_u0[0][0], 1);
    // no valid -> no strobe on any table
    sc_upd_val_u0 = '0; #1;
    chkw("TC4 !val wr", 1, t_ctr_wr_u0[0][0], 0);
  endtask

  // ================================================================
  // TC5: dynamic threshold adaptation and sat_thr bounds.
  // ================================================================
  task automatic test_thr_adapt();
    clr_inputs();
    u_chooser = CHOOSE_NONE;
    for (int t = 0; t < NT; t++) begin u_ctr[t]='0; u_idx[t]='0; end
    u_final=0; u_tage=0; u_back=0; u_range='0;

    // TC to +max via sc_wrong: tc=62 -> +1 -> 63 (LCL_TC_MAX)
    //   -> tc resets 0, threshold 10 -> 11.
    set_state(10'd10, 7'sd62, '0, '0, '0, '0, '0);
    u_lcl=0; u_resolved=1; u_abs=10'd20;   // wrong=1
    clk_update(0);
    chkw("TC5 tc->max thr",  SC_THRSH_BITS, u_dut.threshold, 11);
    chkw("TC5 tc->max reset", SC_TC_BITS,   u_dut.tc_reg,     0);

    // TC to -min via sc_lo_upd: tc=-63 -> -1 -> -64 (LCL_TC_MIN)
    //   -> tc resets 0, threshold 10 -> 9.
    set_state(10'd10, -7'sd63, '0, '0, '0, '0, '0);
    u_lcl=1; u_resolved=1; u_abs=10'd5;    // wrong=0, lo=1
    clk_update(0);
    chkw("TC5 tc->min thr",  SC_THRSH_BITS, u_dut.threshold, 9);
    chkw("TC5 tc->min reset", SC_TC_BITS,   u_dut.tc_reg,     0);

    // sat_thr at MAX: threshold=512, tc=62, wrong -> step +1 saturates
    set_state(10'(SC_THRSH_MAX), 7'sd62, '0, '0, '0, '0, '0);
    u_lcl=0; u_resolved=1; u_abs=10'd20;
    clk_update(0);
    chkw("TC5 sat_thr MAX", SC_THRSH_BITS,
         u_dut.threshold, SC_THRSH_MAX);

    // sat_thr at MIN: threshold=1, tc=-63, lo (abs0<1) -> step -1 sat
    set_state(10'(SC_THRSH_MIN), -7'sd63, '0, '0, '0, '0, '0);
    u_lcl=1; u_resolved=1; u_abs=10'd0;
    clk_update(0);
    chkw("TC5 sat_thr MIN", SC_THRSH_BITS,
         u_dut.threshold, SC_THRSH_MIN);
  endtask

  // ================================================================
  // TC6: counter update write data (sat_sc), index passthrough, and
  // gate suppression. do_update forced via sc_wrong. Observed
  // combinationally on the table write ports.
  // ================================================================
  task automatic test_ctr_upd();
    clr_inputs();
    set_state(10'd10, '0, '0, '0, '0, '0, '0);
    u_chooser = CHOOSE_NONE;
    u_final=0; u_tage=0; u_back=0; u_range='0;
    u_abs=10'd20;             // >= thr so lo=0; gate via wrong only

    // resolved=1 (+1): ctr [31,5,-32,0,-1] -> [31,6,-31,1,0]
    u_ctr[0]=6'sd31; u_ctr[1]=6'sd5; u_ctr[2]=-6'sd32;
    u_ctr[3]=6'sd0;  u_ctr[4]=-6'sd1;
    u_idx[0]=10'h101; u_idx[1]=10'h102; u_idx[2]=10'h103;
    u_idx[3]=10'h104; u_idx[4]=10'h105;
    u_lcl=0; u_resolved=1;    // wrong=1 -> do_update
    drive_update(0);
    for (int t = 0; t < NT; t++) begin
      chkw($sformatf("TC6 +1 wd[%0d]", t), SC_MAX_CTR_WIDTH,
           t_ctr_wd_u0[t][0], ref_sat_sc(u_ctr[t], +1));
      chkw($sformatf("TC6 +1 idx[%0d]", t), SC_MAX_IDX_WIDTH,
           t_upd_index_u0[t][0], u_idx[t]);
      chkw($sformatf("TC6 +1 wr[%0d]", t), 1, t_ctr_wr_u0[t][0], 1);
    end

    // resolved=0 (-1): ctr [-32,5,31,0,1] -> [-32,4,30,-1,0]
    u_ctr[0]=-6'sd32; u_ctr[1]=6'sd5; u_ctr[2]=6'sd31;
    u_ctr[3]=6'sd0;   u_ctr[4]=6'sd1;
    u_lcl=1; u_resolved=0;    // lcl(1)!=res(0) -> wrong=1
    drive_update(0);
    for (int t = 0; t < NT; t++)
      chkw($sformatf("TC6 -1 wd[%0d]", t), SC_MAX_CTR_WIDTH,
           t_ctr_wd_u0[t][0], ref_sat_sc(u_ctr[t], -1));

    // gate off: lcl==res and abs>=thr -> do_update=0 -> no wr
    u_lcl=1; u_resolved=1; u_abs=10'd20;
    drive_update(0);
    for (int t = 0; t < NT; t++)
      chkw($sformatf("TC6 off wr[%0d]", t), 1, t_ctr_wr_u0[t][0], 0);
  endtask

  // ================================================================
  // TC7: chooser training. HIGH / MED arms, inc/dec, sat_ch bounds.
  // ================================================================
  task automatic test_ch_train();
    clr_inputs();
    for (int t = 0; t < NT; t++) begin u_ctr[t]='0; u_idx[t]='0; end
    u_back=0; u_range='0; u_abs=10'd20;

    // HIGH, sc_match -> +1 : chi 0 -> 1
    set_state(10'd10, '0, '0, '0, '0, '0, '0);
    u_chooser=CHOOSE_HIGH; u_final=1; u_tage=0; u_resolved=1; u_lcl=1;
    clk_update(0);
    chkw("TC7 HIGH inc", SC_CHOOSER_BITS, u_dut.choose_hi_vlo, 1);

    // HIGH, !sc_match & tg_match -> -1 : chi 5 -> 4
    set_state(10'd10, '0, 6'sd5, '0, '0, '0, '0);
    u_chooser=CHOOSE_HIGH; u_final=0; u_tage=1; u_resolved=1; u_lcl=0;
    clk_update(0);
    chkw("TC7 HIGH dec", SC_CHOOSER_BITS, u_dut.choose_hi_vlo, 4);

    // HIGH sat at MAX: chi=31, sc_match -> stays 31
    set_state(10'd10, '0, 6'(SC_CHOOSER_MAX), '0, '0, '0, '0);
    u_chooser=CHOOSE_HIGH; u_final=1; u_tage=0; u_resolved=1;
    clk_update(0);
    chkw("TC7 HIGH sat max", SC_CHOOSER_BITS,
         u_dut.choose_hi_vlo, SC_CHOOSER_MAX);

    // HIGH sat at MIN: chi=-32, !sc_match & tg_match -> stays -32
    set_state(10'd10, '0, 6'(SC_CHOOSER_MIN), '0, '0, '0, '0);
    u_chooser=CHOOSE_HIGH; u_final=0; u_tage=1; u_resolved=1;
    clk_update(0);
    chkw("TC7 HIGH sat min", SC_CHOOSER_BITS,
         u_dut.choose_hi_vlo, SC_CHOOSER_MIN);

    // MED, sc_match -> +1 : cmed 0 -> 1 (chi held)
    set_state(10'd10, '0, 6'sd7, '0, '0, '0, '0);
    u_chooser=CHOOSE_MED; u_final=1; u_tage=0; u_resolved=1;
    clk_update(0);
    chkw("TC7 MED inc",   SC_CHOOSER_BITS, u_dut.choose_med_vvlo, 1);
    chkw("TC7 MED chi held", SC_CHOOSER_BITS, u_dut.choose_hi_vlo, 7);

    // MED, !sc_match & tg_match -> -1 : cmed 3 -> 2
    set_state(10'd10, '0, '0, 6'sd3, '0, '0, '0);
    u_chooser=CHOOSE_MED; u_final=0; u_tage=1; u_resolved=1;
    clk_update(0);
    chkw("TC7 MED dec",   SC_CHOOSER_BITS, u_dut.choose_med_vvlo, 2);
  endtask

  // ================================================================
  // TC8: BrIMLI register maintenance (section 12).
  // ================================================================
  task automatic test_brimli();
    logic [9:0] exp_bb;
    clr_inputs();
    for (int t = 0; t < NT; t++) begin u_ctr[t]='0; u_idx[t]='0; end
    u_chooser=CHOOSE_NONE; u_final=0; u_tage=0; u_lcl=0; u_abs=10'd20;

    // region match: last_back valid, range==region -> br_imli++,
    //   bb_hist unchanged, last_back_pc reloaded.
    set_state(10'd10, '0, '0, '0, 10'd5, 10'h000, {1'b1,10'h123});
    u_resolved=1; u_back=1; u_range=10'h123;
    clk_update(0);
    chkw("TC8 match br_imli", 10, u_dut.br_imli, 6);
    chkw("TC8 match bb_hist", 10, u_dut.bb_hist, 10'h000);
    chkw("TC8 match last_pc", 11, u_dut.last_back_pc, {1'b1,10'h123});

    // region change: range!=region -> bb_hist shift/xor, br_imli=0.
    //   bb=(0x0AA<<1)^0x100^0x055 = 0x154^0x100^0x055 = 0x001
    set_state(10'd10, '0, '0, '0, 10'd7, 10'h0AA, {1'b1,10'h100});
    u_resolved=1; u_back=1; u_range=10'h055;
    clk_update(0);
    exp_bb = (10'h0AA << 1) ^ 10'h100 ^ 10'h055;
    chkw("TC8 chg br_imli", 10, u_dut.br_imli, 0);
    chkw("TC8 chg bb_hist", 10, u_dut.bb_hist, exp_bb);
    chkw("TC8 chg last_pc", 11, u_dut.last_back_pc, {1'b1,10'h055});

    // previously invalid last_back_pc -> region-change path.
    set_state(10'd10, '0, '0, '0, 10'd0, 10'h000, 11'h000);
    u_resolved=1; u_back=1; u_range=10'h0AB;
    clk_update(0);
    exp_bb = (10'h000 << 1) ^ 10'h000 ^ 10'h0AB;
    chkw("TC8 inv bb_hist", 10, u_dut.bb_hist, exp_bb);
    chkw("TC8 inv last_pc", 11, u_dut.last_back_pc, {1'b1,10'h0AB});

    // saturating increment at BRIMLI_MAX (0x3FF), region match.
    set_state(10'd10, '0, '0, '0, 10'h3FF, 10'h000, {1'b1,10'h123});
    u_resolved=1; u_back=1; u_range=10'h123;
    clk_update(0);
    chkw("TC8 sat br_imli", 10, u_dut.br_imli, 10'h3FF);

    // not backward -> no change to br_imli/last_back_pc.
    set_state(10'd10, '0, '0, '0, 10'd9, 10'h000, {1'b1,10'h123});
    u_resolved=1; u_back=0; u_range=10'h200;
    clk_update(0);
    chkw("TC8 fwd br_imli", 10, u_dut.br_imli, 9);
    chkw("TC8 fwd last_pc", 11, u_dut.last_back_pc, {1'b1,10'h123});

    // not taken -> no change even if backward.
    set_state(10'd10, '0, '0, '0, 10'd9, 10'h000, {1'b1,10'h123});
    u_resolved=0; u_back=1; u_range=10'h055;
    clk_update(0);
    chkw("TC8 ntk br_imli", 10, u_dut.br_imli, 9);
  endtask

  // ----------------------------------------------------------------
  // Main sequence
  // ----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    clr_inputs();
    rstn = 1'b0;
    repeat (3) @(posedge clk);
    @(posedge clk); #1; rstn = 1'b1;
    @(posedge clk); #1;

    // Reset default check: threshold seeded to SC_THRSH_MID.
    chkw("RST threshold=MID", SC_THRSH_BITS,
         u_dut.threshold, SC_THRSH_MID);
    chkw("RST tc=0",   SC_TC_BITS, u_dut.tc_reg, 0);
    chkw("RST brimli=0", 10, u_dut.br_imli, 0);

    if (_sum_dir   != 0) test_sum_dir();
    if (_bands     != 0) test_bands();
    if (_chooser   != 0) test_chooser();
    if (_gate      != 0) test_gate();
    if (_thr_adapt != 0) test_thr_adapt();
    if (_ctr_upd   != 0) test_ctr_upd();
    if (_ch_train  != 0) test_ch_train();
    if (_brimli    != 0) test_brimli();

    @(posedge clk); #1;
    $display("--------------------------------------------");
    $display("Results: %0d PASS  %0d FAIL", pass_cnt, fail_cnt);
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

  /* verilator lint_on WIDTHEXPAND */

endmodule : tb

`default_nettype wire
