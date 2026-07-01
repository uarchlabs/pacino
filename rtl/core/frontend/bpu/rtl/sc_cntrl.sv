// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    sc_cntrl.sv
// DATE:    2026-07-01
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Statistical Corrector (SC) control layer. Parallels tage_cntrl.
// Logic only: the five SC tables (ST0-ST3 sc_table, ST4 sc_brimli)
// and sram_init are instantiated in sc.sv (not here). sc_cntrl drives
// the table index inputs, consumes ctr_p3 / idx_hash_p2 from the
// tables, forms the SC prediction (sc_decisions.md section 9), and on
// update applies the counter-update gate, adapts the dynamic
// threshold via the TC counter, trains the two-corner chooser, and
// maintains the BrIMLI registers (sc_decisions.md sections 10-12).
//
// Pipeline (sc_decisions.md section 3, sc_interfaces.md):
//   p2 : tage_pred_meta_p2 and the staged p2 inputs (inp_pc_p2,
//        sc_phr_p2, sc_t{1,2,3}_idx_fh_p2) present. Table index
//        inputs are driven; tables compute idx_hash_p2 and issue the
//        RAM read.
//   p3 : ctr_p3 returns (one-cycle bw_ram read). SC sum, bands,
//        chooser and final direction form here; sc_pred_meta_p3 is
//        combinational from ctr_p3 and the p2->p3 staged tage meta.
//   u0 : sc_upd_inp_u0 present. Counter write ports and the global
//        state next-values are driven combinationally.
//   u1 : table RAM write commits; global state registers update.
//
// Global control state (sc_decisions.md section 8) is scalar:
// threshold, TC, choose_hi_vlo, choose_med_vvlo, br_imli, bb_hist,
// last_back_pc. It is shared across both prediction slots. When both
// slots present an update in the same cycle, the lowest-indexed valid
// slot drives the shared threshold/TC/chooser/BrIMLI adaptation; the
// per-table counter writes proceed for every valid slot independently
// (each slot has its own per-slot table RAM, no conflict). This
// resolves the two-slot case the scalar section-8 state does not
// address (recorded as an assumption in BP-077 Results Capture).
//
// Derived port list (authorized by BP-077, sources: sc_decisions.md
// sections 8-12, sc_interfaces.md, sc_table_interfaces.md):
//   clk, rstn
//   -- prediction, SC top facing --
//   in  tage_pred_rdy_p2 [slot]
//   in  tage_pred_meta_p2[slot]      (tage_pred_meta_t)
//   in  inp_pc_p2        [slot]      staged branch PC
//   in  sc_phr_p2                    staged path history low 10b
//   in  sc_t1_idx_fh_p2 / _t2_ / _t3_  staged per-table folds
//   in  br_imli_mode                (br_imli_mode_e, ST4 index mode)
//   out sc_pred_rdy_p3   [slot]
//   out sc_pred_meta_p3  [slot]      (sc_pred_meta_t)
//   -- update, SC top facing --
//   in  sc_upd_val_u0    [slot]
//   in  sc_upd_inp_u0    [slot]      (sc_upd_inp_t)
//   out sc_upd_rdy_u1    [slot]
//   -- prediction, table facing --
//   out t_sc_pred_val_p2 [slot]      read enable, broadcast
//   out t_inp_pc_p2      [slot]      PC to all tables
//   out t_idx_fh_p2      [table]     fold: ST0=0, ST1-3 folds, ST4=0
//   out t_sc_phr_p2                  PHR to ST4
//   out t_br_imli                    BrIMLI counter to ST4
//   out t_br_imli_mode               ST4 index mode
//   in  t_ctr_p3         [table][slot]  signed counter read at p3
//   in  t_idx_hash_p2    [table][slot]  table index computed at p2
//   -- update, table facing --
//   out t_sc_upd_val_u0  [table][slot]
//   out t_ctr_wd_u0      [table][slot]  sat_sc stepped counter
//   out t_ctr_wr_u0      [table][slot]  counter write strobe
//   out t_upd_index_u0   [table][slot]  captured index (no re-hash)
//
// NUM_PRED_SLOTS shadows bp_defines_pkg::NUM_PRED_SLOTS.
// -Wno-VARHIDDEN required for this module.
// ===================================================================
`ifndef SC_CNTRL_SV
`define SC_CNTRL_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module sc_cntrl #(
  parameter int NUM_PRED_SLOTS = bp_defines_pkg::NUM_PRED_SLOTS
) (
  input  logic                        clk,
  input  logic                        rstn,

  // -- prediction interface (SC top facing)
  input  logic [NUM_PRED_SLOTS-1:0]   tage_pred_rdy_p2,
  input  tage_pred_meta_t             tage_pred_meta_p2[0:NUM_PRED_SLOTS-1],
  input  logic [VA_WIDTH-1:1]         inp_pc_p2[0:NUM_PRED_SLOTS-1],
  input  logic [9:0]                  sc_phr_p2,
  input  logic [SC_MAX_FH-1:0]        sc_t1_idx_fh_p2,
  input  logic [SC_MAX_FH-1:0]        sc_t2_idx_fh_p2,
  input  logic [SC_MAX_FH-1:0]        sc_t3_idx_fh_p2,
  input  br_imli_mode_e               br_imli_mode,
  output logic [NUM_PRED_SLOTS-1:0]   sc_pred_rdy_p3,
  output sc_pred_meta_t               sc_pred_meta_p3[0:NUM_PRED_SLOTS-1],

  // -- update interface (SC top facing)
  input  logic [NUM_PRED_SLOTS-1:0]   sc_upd_val_u0,
  input  sc_upd_inp_t                 sc_upd_inp_u0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]   sc_upd_rdy_u1,

  // -- prediction outputs driven to the SC table instances (p2)
  output logic [NUM_PRED_SLOTS-1:0]   t_sc_pred_val_p2,
  output logic [VA_WIDTH-1:1]         t_inp_pc_p2[0:NUM_PRED_SLOTS-1],
  output logic [SC_MAX_FH-1:0]        t_idx_fh_p2[0:SC_NUM_TABLES-1],
  output logic [9:0]                  t_sc_phr_p2,
  output logic [9:0]                  t_br_imli,
  output br_imli_mode_e               t_br_imli_mode,

  // -- prediction inputs collected from the SC table instances (p3/p2)
  input  logic [SC_MAX_CTR_WIDTH-1:0]
    t_ctr_p3[0:SC_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  input  logic [SC_MAX_IDX_WIDTH-1:0]
    t_idx_hash_p2[0:SC_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],

  // -- update outputs driven to the SC table instances (u0)
  output logic [NUM_PRED_SLOTS-1:0]
    t_sc_upd_val_u0[0:SC_NUM_TABLES-1],
  output logic [SC_MAX_CTR_WIDTH-1:0]
    t_ctr_wd_u0[0:SC_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]
    t_ctr_wr_u0[0:SC_NUM_TABLES-1],
  output logic [SC_MAX_IDX_WIDTH-1:0]
    t_upd_index_u0[0:SC_NUM_TABLES-1][0:NUM_PRED_SLOTS-1]
);

  // ----------------------------------------------------------------
  // Local parameters (sc_decisions.md sections 8, 11)
  // ----------------------------------------------------------------
  // TC saturation limits (section 8). Signed SC_TC_BITS wide.
  localparam logic signed [SC_TC_BITS-1:0] LCL_TC_MAX =
    {1'b0, {(SC_TC_BITS-1){1'b1}}};   // 0111..1  = +max
  localparam logic signed [SC_TC_BITS-1:0] LCL_TC_MIN =
    {1'b1, {(SC_TC_BITS-1){1'b0}}};   // 1000..0  = -max

  // Counter and chooser signed saturation limits (section 11).
  localparam logic signed [SC_MAX_CTR_WIDTH-1:0] CTR_MIN_S =
    SC_MAX_CTR_WIDTH'(SC_CTR_MIN);
  localparam logic signed [SC_MAX_CTR_WIDTH-1:0] CTR_MAX_S =
    SC_MAX_CTR_WIDTH'(SC_CTR_MAX);
  localparam logic signed [SC_CHOOSER_BITS-1:0] CH_MIN_S =
    SC_CHOOSER_BITS'(SC_CHOOSER_MIN);
  localparam logic signed [SC_CHOOSER_BITS-1:0] CH_MAX_S =
    SC_CHOOSER_BITS'(SC_CHOOSER_MAX);

  // Threshold unsigned bounds and seed (section 11, bp_defines_pkg).
  localparam logic [SC_THRSH_BITS-1:0] THR_MIN_U =
    SC_THRSH_BITS'(SC_THRSH_MIN);
  localparam logic [SC_THRSH_BITS-1:0] THR_MAX_U =
    SC_THRSH_BITS'(SC_THRSH_MAX);
  localparam logic [SC_THRSH_BITS-1:0] THR_MID_U =
    SC_THRSH_BITS'(SC_THRSH_MID);

  // BrIMLI counter saturates at all-ones (10b, section 12).
  localparam logic [9:0] BRIMLI_MAX = 10'h3FF;

  // ----------------------------------------------------------------
  // Helper functions (sc_decisions.md section 11)
  // delta is +1 or -1; the width cast makes -1 the all-ones pattern
  // so the signed/unsigned add carries correctly at the given width.
  // ----------------------------------------------------------------
  function automatic logic signed [SC_TC_BITS-1:0] sat_tc(
      input logic signed [SC_TC_BITS-1:0] curr_tc,
      input int                           delta);
    if (delta == 0)
      sat_tc = curr_tc;
    else if ((curr_tc == LCL_TC_MIN) && (delta < 0))
      sat_tc = curr_tc;
    else if ((curr_tc == LCL_TC_MAX) && (delta > 0))
      sat_tc = curr_tc;
    else
      sat_tc = signed'(curr_tc + SC_TC_BITS'(delta));
  endfunction

  function automatic logic [SC_THRSH_BITS-1:0] sat_thr(
      input logic [SC_THRSH_BITS-1:0] curr_thr,
      input int                       delta);
    if (delta == 0)
      sat_thr = curr_thr;
    else if ((curr_thr == THR_MIN_U) && (delta < 0))
      sat_thr = curr_thr;
    else if ((curr_thr == THR_MAX_U) && (delta > 0))
      sat_thr = curr_thr;
    else
      sat_thr = curr_thr + SC_THRSH_BITS'(delta);
  endfunction

  function automatic logic signed [SC_MAX_CTR_WIDTH-1:0] sat_sc(
      input logic signed [SC_MAX_CTR_WIDTH-1:0] curr_ctr,
      input int                                 delta);
    if (delta == 0)
      sat_sc = curr_ctr;
    else if ((curr_ctr == CTR_MIN_S) && (delta < 0))
      sat_sc = curr_ctr;
    else if ((curr_ctr == CTR_MAX_S) && (delta > 0))
      sat_sc = curr_ctr;
    else
      sat_sc = signed'(curr_ctr + SC_MAX_CTR_WIDTH'(delta));
  endfunction

  function automatic logic signed [SC_CHOOSER_BITS-1:0] sat_ch(
      input logic signed [SC_CHOOSER_BITS-1:0] curr_ch,
      input int                                delta);
    if (delta == 0)
      sat_ch = curr_ch;
    else if ((curr_ch == CH_MIN_S) && (delta < 0))
      sat_ch = curr_ch;
    else if ((curr_ch == CH_MAX_S) && (delta > 0))
      sat_ch = curr_ch;
    else
      sat_ch = signed'(curr_ch + SC_CHOOSER_BITS'(delta));
  endfunction

  // ----------------------------------------------------------------
  // Global control state (sc_decisions.md section 8). Scalar, shared
  // across prediction slots. _d suffix is the combinational next.
  // ----------------------------------------------------------------
  logic [SC_THRSH_BITS-1:0]         threshold, threshold_d;
  logic signed [SC_TC_BITS-1:0]     tc_reg, tc_reg_d;
  logic signed [SC_CHOOSER_BITS-1:0] choose_hi_vlo,   choose_hi_vlo_d;
  logic signed [SC_CHOOSER_BITS-1:0] choose_med_vvlo, choose_med_vvlo_d;
  logic [9:0]  br_imli,      br_imli_d;
  logic [9:0]  bb_hist,      bb_hist_d;
  logic [10:0] last_back_pc, last_back_pc_d;   // [10] = valid

  // ----------------------------------------------------------------
  // Prediction pipeline registers (p2 -> p3).
  // The tage meta and the p2 table indices are staged one cycle so
  // they align with ctr_p3 when the SC result forms at p3.
  // ----------------------------------------------------------------
  logic [NUM_PRED_SLOTS-1:0] pred_rdy_p3;
  tage_pred_meta_t           tage_meta_p3[0:NUM_PRED_SLOTS-1];
  logic [SC_MAX_IDX_WIDTH-1:0]
    idx_hash_r3[0:SC_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];

  // ----------------------------------------------------------------
  // Prediction table-facing drives (p2, combinational passthrough)
  // ----------------------------------------------------------------
  assign t_sc_pred_val_p2 = tage_pred_rdy_p2;
  assign t_sc_phr_p2      = sc_phr_p2;
  assign t_br_imli        = br_imli;
  assign t_br_imli_mode   = br_imli_mode;

  generate
    for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : gen_pc_fanout
      assign t_inp_pc_p2[s] = inp_pc_p2[s];
    end
  endgenerate

  // Per-table index fold: ST0 unhashed (0), ST1-3 use their folds,
  // ST4 (BrIMLI) does not use a fold (sc_table_hash_rules.md).
  assign t_idx_fh_p2[0] = '0;
  assign t_idx_fh_p2[1] = sc_t1_idx_fh_p2;
  assign t_idx_fh_p2[2] = sc_t2_idx_fh_p2;
  assign t_idx_fh_p2[3] = sc_t3_idx_fh_p2;
  assign t_idx_fh_p2[4] = '0;

  // ----------------------------------------------------------------
  // Prediction pipeline flops p2 -> p3
  // ----------------------------------------------------------------
  always_ff @(posedge clk) begin : pred_pipe_ff
    if (!rstn) begin
      pred_rdy_p3 <= '0;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        tage_meta_p3[s] <= '0;
        for (int t = 0; t < SC_NUM_TABLES; t++)
          idx_hash_r3[t][s] <= '0;
      end
    end else begin
      pred_rdy_p3 <= tage_pred_rdy_p2;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        tage_meta_p3[s] <= tage_pred_meta_p2[s];
        for (int t = 0; t < SC_NUM_TABLES; t++)
          idx_hash_r3[t][s] <= t_idx_hash_p2[t][s];
      end
    end
  end

  assign sc_pred_rdy_p3 = pred_rdy_p3;

  // ----------------------------------------------------------------
  // Prediction result formation at p3 (sc_decisions.md section 9).
  // Combinational; reads ctr_p3 (an FF output in the real design)
  // plus the p2->p3 staged tage meta and the global threshold /
  // chooser FFs. Reading FF outputs forces nba_sequent scheduling
  // (stl_sequent rule, CLAUDE.md).
  // ----------------------------------------------------------------
  generate
    for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : gen_pred
      always_comb begin : pred_form
        logic signed [SC_MAX_CTR_WIDTH+1:0] c_ext;   // 8b sign-ext
        logic signed [SC_MAX_CTR_WIDTH+1:0] val;     // 2*ctr+1
        logic signed [15:0]                 sum_wide;
        logic signed [SC_LSUM_BITS-1:0]     sc_sum;
        logic [SC_LSUM_BITS-1:0]            abs_sum;
        logic                               lcl_tkn;
        logic                               sc_vlo, sc_vvlo;
        logic                               tage_hi, tage_med, tage_tkn;
        logic                               preds_differ;
        logic                               final_pred, sc_override;
        bp_sc_chooser_e                     use_chooser;

        // -- signed counter reads and perceptron values, summed with
        //    the TAGE extended counter at weight 1 (TD#86 8x term
        //    deferred). value* = (ctr<<<1)+1 is local to the sum.
        sum_wide = '0;
        for (int t = 0; t < SC_NUM_TABLES; t++) begin
          c_ext    = (SC_MAX_CTR_WIDTH+2)'(signed'(t_ctr_p3[t][s]));
          val      = (c_ext <<< 1) + 8'sd1;
          sum_wide = sum_wide + 16'(val);
        end
        sum_wide = sum_wide
                 + 16'(signed'(tage_meta_p3[s].tage_extd_ctr));
        sc_sum   = sum_wide[SC_LSUM_BITS-1:0];   // fits, see section 9

        // -- local SC direction and magnitude
        lcl_tkn = ~sc_sum[SC_LSUM_BITS-1];       // sc_sum >= 0
        abs_sum = sc_sum[SC_LSUM_BITS-1]
                    ? (~sc_sum[SC_LSUM_BITS-1:0] + 1'b1)
                    : sc_sum[SC_LSUM_BITS-1:0];

        // -- confidence bands (threshold>>1, threshold>>2, section 9)
        sc_vlo  = (abs_sum < (threshold >> 1));
        sc_vvlo = (abs_sum < (threshold >> 2));

        // -- TAGE confidence and direction
        tage_hi  = tage_meta_p3[s].tage_pred_strong;
        tage_med = tage_meta_p3[s].tage_pred_medium;
        tage_tkn = tage_meta_p3[s].tage_pred_tkn;

        preds_differ = (lcl_tkn != tage_tkn);

        // -- final selection: SC wins except in the two corners
        if (!preds_differ) begin
          final_pred  = lcl_tkn;
          sc_override = 1'b0;
          use_chooser = CHOOSE_NONE;
        end else if (tage_hi && sc_vlo) begin       // corner 1
          final_pred  = (choose_hi_vlo >= 0) ? lcl_tkn : tage_tkn;
          sc_override = (choose_hi_vlo >= 0);
          use_chooser = CHOOSE_HIGH;
        end else if (tage_med && sc_vvlo) begin      // corner 2
          final_pred  = (choose_med_vvlo >= 0) ? lcl_tkn : tage_tkn;
          sc_override = (choose_med_vvlo >= 0);
          use_chooser = CHOOSE_MED;
        end else begin                               // general differ
          final_pred  = lcl_tkn;
          sc_override = 1'b1;
          use_chooser = CHOOSE_NONE;
        end

        // -- capture prediction meta (consumed by the update path)
        sc_pred_meta_p3[s]                 = '0;
        sc_pred_meta_p3[s].sc_pred_tkn     = final_pred;
        sc_pred_meta_p3[s].sc_lcl_pred_tkn = lcl_tkn;
        sc_pred_meta_p3[s].sc_tage_pred_tkn = tage_tkn;
        sc_pred_meta_p3[s].sc_override     = sc_override;
        sc_pred_meta_p3[s].sc_sum          = sc_sum;
        sc_pred_meta_p3[s].sc_abs_sum      = abs_sum;
        sc_pred_meta_p3[s].sc_chooser      = use_chooser;
        sc_pred_meta_p3[s].branch_id       = tage_meta_p3[s].branch_id;
        for (int t = 0; t < SC_NUM_TABLES; t++) begin
          sc_pred_meta_p3[s].sc_upd_idx[t] = idx_hash_r3[t][s];
          sc_pred_meta_p3[s].sc_upd_ctr[t] =
            SC_MAX_DATA_WIDTH'(t_ctr_p3[t][s]);
        end
      end
    end
  endgenerate

  // ----------------------------------------------------------------
  // Update-phase per-slot gate and counter write drives
  // (sc_decisions.md section 10). do_update reads the global
  // threshold FF -> nba_sequent.
  // ----------------------------------------------------------------
  logic [NUM_PRED_SLOTS-1:0] do_update;

  generate
    for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : gen_gate
      always_comb begin : gate_form
        logic sc_wrong;
        logic sc_lo_upd;
        sc_wrong  = (sc_upd_inp_u0[s].sc_pred_meta.sc_lcl_pred_tkn
                     != sc_upd_inp_u0[s].resolved_taken);
        sc_lo_upd = (sc_upd_inp_u0[s].sc_pred_meta.sc_abs_sum
                     < threshold);
        do_update[s] = sc_wrong || sc_lo_upd;
      end
    end
  endgenerate

  // Table-facing update buses. Every consulted counter (all five
  // tables) steps toward the resolved direction when do_update fires
  // for that slot. The captured index is used directly (no re-hash).
  generate
    for (genvar t = 0; t < SC_NUM_TABLES; t++) begin : gen_upd_tbl
      assign t_sc_upd_val_u0[t] = sc_upd_val_u0;
      for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : gen_upd_slot
        assign t_ctr_wr_u0[t][s] = sc_upd_val_u0[s] & do_update[s];
        assign t_upd_index_u0[t][s] =
          sc_upd_inp_u0[s].sc_pred_meta.sc_upd_idx[t];
        assign t_ctr_wd_u0[t][s] =
          sat_sc(signed'(sc_upd_inp_u0[s].sc_pred_meta.sc_upd_ctr[t]),
                 sc_upd_inp_u0[s].resolved_taken ? +1 : -1);
      end
    end
  endgenerate

  // ----------------------------------------------------------------
  // Winning update slot for the shared threshold/TC/chooser/BrIMLI
  // adaptation: lowest-indexed valid slot. Iterating high -> low
  // leaves the lowest valid slot as the final assignment.
  // ----------------------------------------------------------------
  // SEL_BITS: index width for the slot array, clamped to 1 when
  // NUM_PRED_SLOTS == 1 (mirrors TRX_SLOT_BITS in bp_defines_pkg).
  localparam int SEL_BITS = (NUM_PRED_SLOTS > 1)
                              ? $clog2(NUM_PRED_SLOTS) : 1;

  logic                w_valid;
  logic [SEL_BITS-1:0] w_sel;

  always_comb begin : win_sel
    w_valid = 1'b0;
    w_sel   = '0;
    for (int s = NUM_PRED_SLOTS-1; s >= 0; s--) begin
      if (sc_upd_val_u0[s]) begin
        w_valid = 1'b1;
        w_sel   = SEL_BITS'(s);
      end
    end
  end

  // ----------------------------------------------------------------
  // Global state next-value logic (sc_decisions.md sections 10, 12).
  // Reads the current global FFs -> nba_sequent.
  // ----------------------------------------------------------------
  always_comb begin : global_next
    sc_pred_meta_t win_meta;
    logic          win_resolved;
    logic          win_backwards;
    logic [9:0]    win_range;
    logic          sc_wrong_w, sc_lo_w;
    logic signed [SC_TC_BITS-1:0] tc_inc;
    logic          sc_match, tg_match;

    // -- hold by default
    threshold_d       = threshold;
    tc_reg_d          = tc_reg;
    choose_hi_vlo_d   = choose_hi_vlo;
    choose_med_vvlo_d = choose_med_vvlo;
    br_imli_d         = br_imli;
    bb_hist_d         = bb_hist;
    last_back_pc_d    = last_back_pc;

    win_meta      = sc_upd_inp_u0[w_sel].sc_pred_meta;
    win_resolved  = sc_upd_inp_u0[w_sel].resolved_taken;
    win_backwards = sc_upd_inp_u0[w_sel].backwards_branch;
    win_range     = sc_upd_inp_u0[w_sel].branch_range;

    // -- temporaries default (avoid inferred latches)
    sc_wrong_w = 1'b0;
    sc_lo_w    = 1'b0;
    tc_inc     = tc_reg;
    sc_match   = 1'b0;
    tg_match   = 1'b0;

    if (w_valid) begin
      // -- TC adaptation and dynamic threshold step (section 10)
      sc_wrong_w = (win_meta.sc_lcl_pred_tkn != win_resolved);
      sc_lo_w    = (win_meta.sc_abs_sum < threshold);

      if      (sc_wrong_w) tc_inc = sat_tc(tc_reg, +1);
      else if (sc_lo_w)    tc_inc = sat_tc(tc_reg, -1);
      else                 tc_inc = tc_reg;

      if (tc_inc == LCL_TC_MAX) begin
        tc_reg_d    = '0;
        threshold_d = sat_thr(threshold, +1);
      end else if (tc_inc == LCL_TC_MIN) begin
        tc_reg_d    = '0;
        threshold_d = sat_thr(threshold, -1);
      end else begin
        tc_reg_d    = tc_inc;
        threshold_d = threshold;
      end

      // -- chooser training: only the corner that was consulted
      sc_match = (win_meta.sc_pred_tkn      == win_resolved);
      tg_match = (win_meta.sc_tage_pred_tkn == win_resolved);

      if (win_meta.sc_chooser == CHOOSE_HIGH) begin
        if      (sc_match) choose_hi_vlo_d = sat_ch(choose_hi_vlo, +1);
        else if (tg_match) choose_hi_vlo_d = sat_ch(choose_hi_vlo, -1);
      end else if (win_meta.sc_chooser == CHOOSE_MED) begin
        if      (sc_match) choose_med_vvlo_d = sat_ch(choose_med_vvlo, +1);
        else if (tg_match) choose_med_vvlo_d = sat_ch(choose_med_vvlo, -1);
      end

      // -- BrIMLI maintenance (section 12). SC sees conditional
      //    branches only; the conditional test is implied. Only a
      //    resolved-taken backward branch touches the registers.
      if (win_resolved && win_backwards) begin
        if (last_back_pc[10] && (win_range == last_back_pc[9:0])) begin
          // same region: saturating increment
          br_imli_d = (br_imli == BRIMLI_MAX) ? BRIMLI_MAX
                                              : br_imli + 10'd1;
        end else begin
          // region change: fold into bb_hist, reset the counter
          bb_hist_d = (bb_hist << 1) ^ last_back_pc[9:0] ^ win_range;
          br_imli_d = '0;
        end
        last_back_pc_d = {1'b1, win_range};
      end
    end
  end

  // ----------------------------------------------------------------
  // Global state registers (sc_decisions.md section 8 reset values)
  // ----------------------------------------------------------------
  always_ff @(posedge clk) begin : global_ff
    if (!rstn) begin
      threshold       <= THR_MID_U;
      tc_reg          <= '0;
      choose_hi_vlo   <= '0;
      choose_med_vvlo <= '0;
      br_imli         <= '0;
      bb_hist         <= '0;
      last_back_pc    <= '0;
    end else begin
      threshold       <= threshold_d;
      tc_reg          <= tc_reg_d;
      choose_hi_vlo   <= choose_hi_vlo_d;
      choose_med_vvlo <= choose_med_vvlo_d;
      br_imli         <= br_imli_d;
      bb_hist         <= bb_hist_d;
      last_back_pc    <= last_back_pc_d;
    end
  end

  // ----------------------------------------------------------------
  // Update ready: register sc_upd_val_u0 -> sc_upd_rdy_u1
  // ----------------------------------------------------------------
  always_ff @(posedge clk) begin : upd_rdy_ff
    if (!rstn)
      sc_upd_rdy_u1 <= '0;
    else
      sc_upd_rdy_u1 <= sc_upd_val_u0;
  end

endmodule : sc_cntrl

`endif // SC_CNTRL_SV

`default_nettype wire
