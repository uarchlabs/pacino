// ===================================================================
// FILE:    tage_cntrl.sv
// DATE:    2026-04-05
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// TAGE predictor control module.
// Drives all tage_table inputs, collects tage_table outputs,
// applies provider selection and UAON mux, and produces
// tage_pred_meta_t outputs at p2.
//
// Prediction logic complete: BP-008a-2.
// Update logic added in BP-008b.
//
// NUM_PRED_SLOTS shadows bp_defines_pkg::NUM_PRED_SLOTS.
// -Wno-VARHIDDEN required for this module.
// ===================================================================
`ifndef TAGE_CNTRL_SV
`define TAGE_CNTRL_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tage_cntrl #(
  parameter  int NUM_PRED_SLOTS   = 2,
  // Derived: do not override
  localparam int CNTRL_BITS_WIDTH = TAGE_MAX_EPC_WIDTH + TAGE_MAX_USE_WIDTH
                                  + TAGE_MAX_CTR_WIDTH + TAGE_MAX_VAL_WIDTH,
  localparam int ALLOC_DATA_WIDTH = CNTRL_BITS_WIDTH
                                  + TAGE_MAX_TAG_WIDTH,
  // TBL_SEL_WIDTH: selector width, matches TAGE_TBL_SEL_WIDTH.
  parameter  int TBL_SEL_WIDTH    = TAGE_TBL_SEL_WIDTH
) (
  input  logic                             clk,
  input  logic                             rstn,

  // -- prediction interface
  input  logic [NUM_PRED_SLOTS-1:0]        tage_pred_val_p0,
  input  tage_pred_inp_t
    tage_pred_inp_p0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]        tage_pred_rdy_p2,
  output tage_pred_meta_t
    tage_pred_meta_p2[0:NUM_PRED_SLOTS-1],

  // -- update interface
  input  logic [NUM_PRED_SLOTS-1:0]        tage_upd_val_u0,
  input  tage_upd_inp_t
    tage_upd_inp_u0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]        tage_upd_rdy_u1,

  // -- arbitration (BP-023b): 0=PRED 1=UPD
  input  logic                             trx_type,

  // -- aging control, shared across both slots
  input  logic                             tage_enable_aging,
  input  logic [31:0]                      tage_aging_interval,

  // -- prediction inputs driven to tage_table instances
  // - pred val forwarded to all tables
  output logic [NUM_PRED_SLOTS-1:0]
    t_pred_val_p0[0:TAGE_NUM_TABLES-1],
  // -- prediction outputs collected from tage_table instances
  // - T0 hit: NOT USED (T0 always hits); T1-T4: tag match
  input  logic [NUM_PRED_SLOTS-1:0]
    t_hit_p1[0:TAGE_NUM_TABLES-1],
  // - CTR MSB direction from each table
  input  logic [NUM_PRED_SLOTS-1:0]
    t_taken_p1[0:TAGE_NUM_TABLES-1],
  // - {EPC,USE,CTR,VAL} packed at MAX widths per tage_table
  input  logic [CNTRL_BITS_WIDTH-1:0]
    t_cntrl_bits_p1[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],

  // -- update enables forwarded to tage_table instances
  output logic [NUM_PRED_SLOTS-1:0]
    t_upd_val_u0[0:TAGE_NUM_TABLES-1],

  // -- update write data (cntrl -> tables)
  output logic [TAGE_MAX_CTR_WIDTH-1:0]
    t_prm_ctr_wd_u0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  output logic [TAGE_MAX_CTR_WIDTH-1:0]
    t_alt_ctr_wd_u0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  output logic [TAGE_MAX_USE_WIDTH-1:0]
    t_use_wd_u0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  output logic [TAGE_MAX_EPC_WIDTH-1:0]
    t_epc_wd_u0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  output logic [ALLOC_DATA_WIDTH-1:0]
    t_alc_wd_u0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],

  // -- update write strobes (cntrl -> tables)
  output logic [NUM_PRED_SLOTS-1:0]
    t_prm_ctr_wr_u0[0:TAGE_NUM_TABLES-1],
  output logic [NUM_PRED_SLOTS-1:0]
    t_alt_ctr_wr_u0[0:TAGE_NUM_TABLES-1],
  output logic [NUM_PRED_SLOTS-1:0]
    t_use_wr_u0[0:TAGE_NUM_TABLES-1],
  output logic [NUM_PRED_SLOTS-1:0]
    t_epc_wr_u0[0:TAGE_NUM_TABLES-1],
  output logic [NUM_PRED_SLOTS-1:0]
    t_alc_wr_u0[0:TAGE_NUM_TABLES-1],

  // -- table selector buses (cntrl -> tables)
  output logic [TBL_SEL_WIDTH-1:0]
    t_prm_tbl_sel_u0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  output logic [TBL_SEL_WIDTH-1:0]
    t_alt_tbl_sel_u0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  // - alc_tbl_sel: tage_table.sv port absent until BP-007d
  output logic [TBL_SEL_WIDTH-1:0]
    t_alc_tbl_sel_u0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],

  // -- update and alloc address buses (cntrl -> tables)
  output logic [TAGE_MAX_IDX_WIDTH-1:0]
    t_upd_index_u0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  // - alc_index: tage_table.sv port absent until BP-007d
  output logic [TAGE_MAX_IDX_WIDTH-1:0]
    t_alc_index_u0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],

  // -- p0 index and tag hashes from table instances (-> r1)
  input  logic [TAGE_MAX_IDX_WIDTH-1:0]
    t_idx_p0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  input  logic [TAGE_MAX_TAG_WIDTH-1:0]
    t_tag_p0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1]
);

  // ----------------------------------------------------------------
  // Local parameters
  // ----------------------------------------------------------------

  // cntrl_bits_p1 field positions (matches tage_table CB_* params).
  // Layout: [0]=VAL, [CB_CTR_H:1]=CTR, [CB_USE_H:CB_CTR_H+1]=USE,
  //         [CB_EPC_H:CB_USE_H+1]=EPC.
  localparam int CB_CTR_H = TAGE_MAX_CTR_WIDTH;
  localparam int CB_USE_H = TAGE_MAX_CTR_WIDTH + TAGE_MAX_USE_WIDTH;
  localparam int CB_EPC_H = TAGE_MAX_CTR_WIDTH + TAGE_MAX_USE_WIDTH
                          + TAGE_MAX_EPC_WIDTH;

  // TAGE_MAX_TBL: index of the longest tagged table (T4).
  // Provider must be < TAGE_MAX_TBL for allocation to fire.
  localparam int TAGE_MAX_TBL = TAGE_NUM_TABLES - 1;

  // ----------------------------------------------------------------
  // Internal signals
  // ----------------------------------------------------------------

  // p0 -> p1 -> p2 valid pipeline (vector over all slots)
  logic [NUM_PRED_SLOTS-1:0] pred_val_p1;
  logic [NUM_PRED_SLOTS-1:0] pred_val_p2;

  // Provider selection results (p1, combinational, per slot)
  logic [TAGE_TBL_SEL_WIDTH-1:0]
    prm_comp_p1[NUM_PRED_SLOTS-1:0];
  logic [TAGE_TBL_SEL_WIDTH-1:0]
    alt_comp_p1[NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    prm_idx_p1[NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    alt_idx_p1[NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_CTR_WIDTH-1:0]
    prm_ctr_p1[NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_CTR_WIDTH-1:0]
    alt_ctr_p1[NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_USE_WIDTH-1:0]
    prm_use_p1[NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_USE_WIDTH-1:0]
    alt_use_p1[NUM_PRED_SLOTS-1:0];
  logic prm_tkn_p1[NUM_PRED_SLOTS-1:0];
  logic alt_tkn_p1[NUM_PRED_SLOTS-1:0];

  // UAON trigger and mux select (p1, combinational, per slot)
  logic uaon_trig_p1  [NUM_PRED_SLOTS-1:0];
  logic using_prm_p1  [NUM_PRED_SLOTS-1:0];

  // Final direction and confidence flags (p1, combinational)
  logic pred_tkn_p1   [NUM_PRED_SLOTS-1:0];
  logic pred_strong_p1[NUM_PRED_SLOTS-1:0];
  logic high_conf_p1  [NUM_PRED_SLOTS-1:0];

  // Pre-mux (primary) and post-mux (final) CTR values
  logic [TAGE_MAX_CTR_WIDTH-1:0]
    pre_mux_ctr_p1[NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_CTR_WIDTH-1:0]
    post_mux_ctr_p1[NUM_PRED_SLOTS-1:0];

  // Allocation candidate (p1, combinational, per slot)
  logic [TAGE_TBL_SEL_WIDTH-1:0]
    alc_comp_p1[NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    alc_idx_p1[NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_TAG_WIDTH-1:0]
    alc_tag_p1[NUM_PRED_SLOTS-1:0];

  // Prediction metadata at p1 (flopped -> tage_pred_meta_p2)
  tage_pred_meta_t meta_p1[0:NUM_PRED_SLOTS-1];

  // UAON saturating counters: 4b, one per slot
  logic [3:0] uaon[NUM_PRED_SLOTS-1:0];

  // Aging interval down counters: 32b, one per slot
  logic [31:0] lcl_aging_interval[NUM_PRED_SLOTS-1:0];

  // Epoch counters: 2b wrapping, one per slot
  logic [1:0] lcl_epoch[NUM_PRED_SLOTS-1:0];

  // Registered p0 index and tag hashes (p0 -> p1).
  // Needed because p0 signals may change before p1 logic fires.
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    t_idx_r1[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_TAG_WIDTH-1:0]
    t_tag_r1[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];

  // Entry field extracts and u_eff per table per slot (p1)
  logic [TAGE_MAX_EPC_WIDTH-1:0]
    t_epc_p1[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_USE_WIDTH-1:0]
    t_use_p1[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [1:0]
    t_age_p1[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_USE_WIDTH-1:0]
    ueff_p1[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];

  // -- Update-side internal signals (combinational, per slot).
  // Aliases into tage_upd_inp_u0[s].tage_pred_meta and derived
  // correctness / control signals. "u_" prefix = update time.

  logic [TAGE_TBL_SEL_WIDTH-1:0]
    u_prm_comp [NUM_PRED_SLOTS-1:0];
  logic [TAGE_TBL_SEL_WIDTH-1:0]
    u_alt_comp [NUM_PRED_SLOTS-1:0];
  logic [TAGE_TBL_SEL_WIDTH-1:0]
    u_alc_comp [NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    u_prm_idx  [NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    u_alt_idx  [NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    u_alc_idx  [NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_TAG_WIDTH-1:0]
    u_alc_tag  [NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_CTR_WIDTH-1:0]
    u_prm_ctr  [NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_CTR_WIDTH-1:0]
    u_alt_ctr  [NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_USE_WIDTH-1:0]
    u_prm_use  [NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_USE_WIDTH-1:0]
    u_alt_use  [NUM_PRED_SLOTS-1:0];
  logic u_prm_tkn    [NUM_PRED_SLOTS-1:0];
  logic u_alt_tkn    [NUM_PRED_SLOTS-1:0];
  logic u_using_prm  [NUM_PRED_SLOTS-1:0];
  logic u_pred_str   [NUM_PRED_SLOTS-1:0];
  logic u_resolved   [NUM_PRED_SLOTS-1:0];
  logic u_mispredict [NUM_PRED_SLOTS-1:0];

  // Derived per-slot update correctness flags
  logic u_prm_tagged [NUM_PRED_SLOTS-1:0]; // prm_comp != 0
  logic u_alt_tagged [NUM_PRED_SLOTS-1:0]; // alt_comp != 0
  logic u_both_t0    [NUM_PRED_SLOTS-1:0]; // both == 0
  logic u_pred_diff  [NUM_PRED_SLOTS-1:0]; // prm_tkn != alt_tkn
  logic u_prm_crt    [NUM_PRED_SLOTS-1:0]; // prm predicted correctly
  logic u_alt_crt    [NUM_PRED_SLOTS-1:0]; // alt predicted correctly
  logic u_pred_crt   [NUM_PRED_SLOTS-1:0]; // provider correct

  // CTR update next-values and per-slot write enables
  logic [TAGE_MAX_CTR_WIDTH-1:0]
    u_prm_ctr_nxt [NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_CTR_WIDTH-1:0]
    u_alt_ctr_nxt [NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_CTR_WIDTH-1:0]
    u_t0_ctr_nxt  [NUM_PRED_SLOTS-1:0];
  logic u_prm_ctr_wr [NUM_PRED_SLOTS-1:0];
  logic u_alt_ctr_wr [NUM_PRED_SLOTS-1:0];
  logic u_t0_ctr_wr  [NUM_PRED_SLOTS-1:0];

  // USE/EPC update: new values, target comp/idx, write enable
  logic [TAGE_MAX_USE_WIDTH-1:0]
    u_use_nxt  [NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_EPC_WIDTH-1:0]
    u_epc_nxt  [NUM_PRED_SLOTS-1:0];
  logic [TAGE_TBL_SEL_WIDTH-1:0]
    u_use_comp [NUM_PRED_SLOTS-1:0];
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    u_use_idx  [NUM_PRED_SLOTS-1:0];
  logic u_use_wr [NUM_PRED_SLOTS-1:0];

  // Allocation write data and per-slot write enable
  logic [ALLOC_DATA_WIDTH-1:0]
    u_alc_wd [NUM_PRED_SLOTS-1:0];
  logic u_alc_wr [NUM_PRED_SLOTS-1:0];

  // ----------------------------------------------------------------
  // Valid pipeline: p0 -> p1 -> p2, all slots as packed vector
  // ----------------------------------------------------------------

  always_ff @(posedge clk) begin : valid_pipe_ff
    if (!rstn) begin
      pred_val_p1 <= '0;
      pred_val_p2 <= '0;
    end else begin
      pred_val_p1 <= tage_pred_val_p0
                     & {NUM_PRED_SLOTS{~trx_type}};
      pred_val_p2 <= pred_val_p1;
    end
  end

  // Register p0 index and tag hashes -> r1.
  // t_idx_p0/t_tag_p0 driven from tage.sv interconnect wires
  // which are driven by tage_bim and tage_table outputs.
  always_ff @(posedge clk) begin : idx_tag_pipe_ff
    if (!rstn) begin
      for (int t = 0; t < TAGE_NUM_TABLES; t++) begin
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          t_idx_r1[t][s] <= '0;
          t_tag_r1[t][s] <= '0;
        end
      end
    end else begin
      for (int t = 0; t < TAGE_NUM_TABLES; t++) begin
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          t_idx_r1[t][s] <= t_idx_p0[t][s];
          t_tag_r1[t][s] <= t_tag_p0[t][s];
        end
      end
    end
  end

  assign tage_pred_rdy_p2 = pred_val_p2;

  // ----------------------------------------------------------------
  // upd_rdy: register tage_upd_val_u0 -> tage_upd_rdy_u1
  // ----------------------------------------------------------------

  always_ff @(posedge clk) begin : upd_rdy_ff
    if (!rstn)
      tage_upd_rdy_u1 <= '0;
    else
      tage_upd_rdy_u1 <= tage_upd_val_u0;
  end

  // ----------------------------------------------------------------
  // Per-slot: meta flop p1->p2, UAON update at u0, aging counters
  // ----------------------------------------------------------------

  generate
    for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : gen_slot
      // -- meta pipeline register p1 -> p2
      always_ff @(posedge clk) begin : meta_p2_ff
        if (!rstn)
          tage_pred_meta_p2[s] <= '0;
        else
          tage_pred_meta_p2[s] <= meta_p1[s];
      end

      // -- UAON saturating counter: 4b, updated at update time (u0).
      // Rules: tage_cntrl_uaon_update_rules.md.
      // Only fires when prm is a tagged table (prm_comp != 0).
      // pred_strong -> no action.
      // prm wrong && alt correct -> INC (saturate at 4'hF).
      // prm correct && alt wrong -> DEC (saturate at 4'h0).
      always_ff @(posedge clk) begin : uaon_upd_ff
        if (!rstn) begin
          uaon[s] <= 4'h0;
        end else if (tage_upd_val_u0[s] && u_prm_tagged[s]) begin
          if (!u_pred_str[s]) begin
            if (!u_prm_crt[s] && u_alt_crt[s]) begin
              uaon[s] <= (uaon[s] == 4'hF)
                           ? 4'hF : uaon[s] + 4'h1;
            end else if (u_prm_crt[s] && !u_alt_crt[s]) begin
              uaon[s] <= (uaon[s] == 4'h0)
                           ? 4'h0 : uaon[s] - 4'h1;
            end
          end
        end
      end

      // -- Aging interval and epoch counters.
      // Decrement interval on pred_rdy_p2 when aging enabled.
      // On zero: increment epoch (2b wrapping), reload interval.
      always_ff @(posedge clk) begin : aging_ff
        if (!rstn) begin
          lcl_aging_interval[s] <= tage_aging_interval;
          lcl_epoch[s]          <= 2'b00;
        end else if (tage_pred_rdy_p2[s] && tage_enable_aging) begin
          if (lcl_aging_interval[s] == 32'h0) begin
            lcl_epoch[s] <= lcl_epoch[s] + 2'b01;
            lcl_aging_interval[s] <= tage_aging_interval;
          end else begin
            lcl_aging_interval[s] <=
              lcl_aging_interval[s] - 32'h1;
          end
        end
      end
    end
  endgenerate

  // ----------------------------------------------------------------
  // Effective useful (u_eff) per table per slot (p1, combinational)
  // age = (lcl_epoch[s] - EPC) mod 4  (2b subtraction wraps)
  // u_eff = USEFUL       when age == 0
  //       = USEFUL >> 1  when age == 1
  //       = 0            when age >= 2
  // T0 has no EPC/USE: set to zero.
  // ----------------------------------------------------------------

  generate
    for (genvar t = 0; t < TAGE_NUM_TABLES; t++) begin : gen_ueff
      for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : gen_ueff_s
        if (t == 0) begin : gen_ueff_t0
          assign t_epc_p1[t][s] = '0;
          assign t_use_p1[t][s] = '0;
          assign t_age_p1[t][s] = 2'b00;
          assign ueff_p1[t][s]  = '0;
        end else begin : gen_ueff_t1t4
          assign t_epc_p1[t][s] =
            t_cntrl_bits_p1[t][s][CB_EPC_H:CB_USE_H+1];
          assign t_use_p1[t][s] =
            t_cntrl_bits_p1[t][s][CB_USE_H:CB_CTR_H+1];
          assign t_age_p1[t][s] =
            lcl_epoch[s] - t_epc_p1[t][s];
          assign ueff_p1[t][s] =
            (t_age_p1[t][s] == 2'b00)
              ? t_use_p1[t][s]
              : (t_age_p1[t][s] == 2'b01)
                ? {1'b0, t_use_p1[t][s][TAGE_MAX_USE_WIDTH-1]}
                : 2'b00;
        end
      end
    end
  endgenerate

  // ----------------------------------------------------------------
  // Prediction logic: provider, alt, UAON mux, alloc candidate
  // ----------------------------------------------------------------
  // Provider scan: T1->T4 ascending, last hit wins -> T4 priority.
  // Alt scan: T1->T(prm-1) ascending, last hit wins.
  // T0 fallback is the default when no tagged table hits.
  // T0 CTR is zero-padded to TAGE_MAX_CTR_WIDTH for storage in meta.
  // UAON trigger: prm must be tagged AND CTR in {011,100}.
  // UAON mux: triggered and uaon MSB set -> use alt provider.
  // Alloc: scan T(prm+1)->T4, take first with ueff==0 (shortest).
  // ----------------------------------------------------------------

  generate
    for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : gen_pred_zero
      always_comb begin : pred_logic
        // -- Defaults: T0 fallback for all provider fields.
        // T0 2b CTR zero-padded to TAGE_MAX_CTR_WIDTH (3b).
        prm_comp_p1[s]     = '0;
        prm_idx_p1[s]      = t_idx_r1[0][s];
        prm_ctr_p1[s]      = TAGE_MAX_CTR_WIDTH'(
          t_cntrl_bits_p1[0][s][TAGE_TBL_CTR[0]:1]);
        prm_use_p1[s]      = '0;
        prm_tkn_p1[s]      = t_taken_p1[0][s];
        alt_comp_p1[s]     = '0;
        alt_idx_p1[s]      = t_idx_r1[0][s];
        alt_ctr_p1[s]      = TAGE_MAX_CTR_WIDTH'(
          t_cntrl_bits_p1[0][s][TAGE_TBL_CTR[0]:1]);
        alt_use_p1[s]      = '0;
        alt_tkn_p1[s]      = t_taken_p1[0][s];
        alc_comp_p1[s]     = '0;
        alc_idx_p1[s]      = '0;
        alc_tag_p1[s]      = '0;
        uaon_trig_p1[s]    = 1'b0;
        using_prm_p1[s]    = 1'b1;
        pred_tkn_p1[s]     = 1'b0;
        pred_strong_p1[s]  = 1'b0;
        high_conf_p1[s]    = 1'b0;
        pre_mux_ctr_p1[s]  = '0;
        post_mux_ctr_p1[s] = '0;

        // -- Primary provider: scan T1->T4.
        // Last assignment wins -> T4 has highest priority.
        for (int t = 1; t < TAGE_NUM_TABLES; t++) begin
          if (t_hit_p1[t][s]) begin
            prm_comp_p1[s] = TAGE_TBL_SEL_WIDTH'(t);
            prm_idx_p1[s]  = t_idx_r1[t][s];
            prm_ctr_p1[s]  =
              t_cntrl_bits_p1[t][s][CB_CTR_H:1];
            prm_use_p1[s]  = ueff_p1[t][s];
            prm_tkn_p1[s]  = t_taken_p1[t][s];
          end
        end

        // -- Alternate provider: scan T1->T(prm-1).
        // Last assignment wins -> nearest-to-prm wins.
        // T0 fallback defaults already set above.
        for (int t = 1; t < TAGE_NUM_TABLES; t++) begin
          if (t_hit_p1[t][s] &&
              t < int'(prm_comp_p1[s])) begin
            alt_comp_p1[s] = TAGE_TBL_SEL_WIDTH'(t);
            alt_idx_p1[s]  = t_idx_r1[t][s];
            alt_ctr_p1[s]  =
              t_cntrl_bits_p1[t][s][CB_CTR_H:1];
            alt_use_p1[s]  = ueff_p1[t][s];
            alt_tkn_p1[s]  = t_taken_p1[t][s];
          end
        end

        // -- UAON trigger: primary is tagged, CTR is boundary.
        // Boundary states: 3'b011 (wn0) and 3'b100 (wt0).
        // T0 provider (prm_comp==0) never triggers.
        pre_mux_ctr_p1[s] = prm_ctr_p1[s];
        if (prm_comp_p1[s] != '0) begin
          uaon_trig_p1[s] =
            (prm_ctr_p1[s] == 3'b011) ||
            (prm_ctr_p1[s] == 3'b100);
        end

        // -- UAON mux: triggered and uaon MSB set -> use alt.
        // uaon MSB set means uaon >= TAGE_UAON_THRES (8).
        if (uaon_trig_p1[s] && uaon[s][3]) begin
          using_prm_p1[s]     = 1'b0;
          post_mux_ctr_p1[s]  = alt_ctr_p1[s];
          pred_tkn_p1[s]      = alt_tkn_p1[s];
        end else begin
          using_prm_p1[s]     = 1'b1;
          post_mux_ctr_p1[s]  = pre_mux_ctr_p1[s];
          pred_tkn_p1[s]      = prm_tkn_p1[s];
        end

        // -- Confidence flags on post-mux CTR.
        // pred_strong: NOT WEAK -- CTR not in {011, 100}.
        // high_conf: strongly NT (000) or strongly T (111).
        pred_strong_p1[s] =
          (post_mux_ctr_p1[s] != 3'b011) &&
          (post_mux_ctr_p1[s] != 3'b100);
        high_conf_p1[s] =
          (post_mux_ctr_p1[s] == 3'b000) ||
          (post_mux_ctr_p1[s] == 3'b111);

        // -- Allocation candidate: scan T(prm+1)->T4.
        // Select first (shortest) table with ueff==0.
        // alc_comp==0 (T0) is the no-candidate sentinel.
        for (int t = 1; t < TAGE_NUM_TABLES; t++) begin
          if (t > int'(prm_comp_p1[s]) &&
              alc_comp_p1[s] == '0      &&
              ueff_p1[t][s] == 2'b00) begin
            alc_comp_p1[s] = TAGE_TBL_SEL_WIDTH'(t);
            alc_idx_p1[s]  = t_idx_r1[t][s];
            alc_tag_p1[s]  = t_tag_r1[t][s];
          end
        end
      end
    end
  endgenerate

  // ----------------------------------------------------------------
  // Populate meta_p1 struct (p1, combinational)
  // ----------------------------------------------------------------

  generate
    for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : gen_meta_p1
      always_comb begin : meta_assign
        meta_p1[s]                    = '0;
        meta_p1[s].tage_prm_idx       = prm_idx_p1[s];
        meta_p1[s].tage_alt_idx       = alt_idx_p1[s];
        meta_p1[s].tage_prm_comp      = prm_comp_p1[s];
        meta_p1[s].tage_alt_comp      = alt_comp_p1[s];
        meta_p1[s].tage_prm_useful    = prm_use_p1[s];
        meta_p1[s].tage_alt_useful    = alt_use_p1[s];
        meta_p1[s].tage_prm_ctr       = prm_ctr_p1[s];
        meta_p1[s].tage_alt_ctr       = alt_ctr_p1[s];
        meta_p1[s].tage_alc_comp      = alc_comp_p1[s];
        meta_p1[s].tage_alc_idx       = alc_idx_p1[s];
        meta_p1[s].tage_alc_tag       = alc_tag_p1[s];
        meta_p1[s].tage_prm_tkn       = prm_tkn_p1[s];
        meta_p1[s].tage_alt_tkn       = alt_tkn_p1[s];
        meta_p1[s].tage_pred_strong   = pred_strong_p1[s];

        //HAND-FIX-002 set tage_use_alt_on_na when it had impact on source
        //             of prediction
        meta_p1[s].tage_use_alt_on_na = uaon_trig_p1[s] & uaon[s][3];
        meta_p1[s].tage_using_primary = using_prm_p1[s];
        meta_p1[s].tage_high_conf     = high_conf_p1[s];
        meta_p1[s].tage_pred_tkn      = pred_tkn_p1[s];
        meta_p1[s].branch_id          =
          tage_pred_inp_p0[s].branch_id;
      end
    end
  endgenerate

  // ----------------------------------------------------------------
  // Update-side alias and derived signal assignments (per slot)
  // ----------------------------------------------------------------

  generate
    for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : gen_upd_sig
      assign u_prm_comp[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_prm_comp;
      assign u_alt_comp[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_alt_comp;
      assign u_alc_comp[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_alc_comp;
      assign u_prm_idx[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_prm_idx;
      assign u_alt_idx[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_alt_idx;
      assign u_alc_idx[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_alc_idx;
      assign u_alc_tag[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_alc_tag;
      assign u_prm_ctr[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_prm_ctr;
      assign u_alt_ctr[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_alt_ctr;
      assign u_prm_use[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_prm_useful;
      assign u_alt_use[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_alt_useful;
      assign u_prm_tkn[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_prm_tkn;
      assign u_alt_tkn[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_alt_tkn;
      assign u_using_prm[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_using_primary;
      assign u_pred_str[s] =
        tage_upd_inp_u0[s].tage_pred_meta.tage_pred_strong;
      assign u_resolved[s]   =
        tage_upd_inp_u0[s].resolved_taken;
      assign u_mispredict[s] =
        tage_upd_inp_u0[s].cond_mispredict;

      // Derived correctness and control flags
      assign u_prm_tagged[s] = (u_prm_comp[s] != '0);
      assign u_alt_tagged[s] = (u_alt_comp[s] != '0);
      assign u_both_t0[s]    = !u_prm_tagged[s]
                                && !u_alt_tagged[s];
      assign u_pred_diff[s]  = (u_prm_tkn[s] != u_alt_tkn[s]);
      assign u_prm_crt[s]    = (u_prm_tkn[s] == u_resolved[s]);
      assign u_alt_crt[s]    = (u_alt_tkn[s] == u_resolved[s]);
      assign u_pred_crt[s]   = u_using_prm[s]
                                 ? u_prm_crt[s]
                                 : u_alt_crt[s];
    end
  endgenerate

  // ----------------------------------------------------------------
  // CTR update: new values and per-slot write enables.
  // Rules: tage_cntrl_ctr_update_rules.md
  //
  // Both-T0 path (rows 13a-d): INC/DEC T0 CTR (2b saturating).
  //   T0 CTR is stored in prm_ctr[TAGE_TBL_CTR[0]-1:0].
  //   prm_ctr[2] is always 0 for T0; direction from prm_tkn.
  // Tagged prm path: INC when prm correct, DEC when wrong.
  //   Also INC prm when using alt, pred_diff, prm correct.
  // Tagged alt path: INC when alt correct, DEC when wrong.
  //   Only INC alt when using prm if pred_diff and alt correct.
  // ----------------------------------------------------------------

  always_comb begin : ctr_upd_comb
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      u_prm_ctr_wr[s]  = 1'b0;
      u_alt_ctr_wr[s]  = 1'b0;
      u_t0_ctr_wr[s]   = 1'b0;
      u_prm_ctr_nxt[s] = u_prm_ctr[s];
      u_alt_ctr_nxt[s] = u_alt_ctr[s];
      u_t0_ctr_nxt[s]  = '0;

      if (tage_upd_val_u0[s]) begin
        if (u_both_t0[s]) begin
          // Both providers T0: update T0 2b CTR (rows 13a-d)
          u_t0_ctr_wr[s] = 1'b1;
          if (u_resolved[s]) begin
            // INC T0 CTR (resolved_taken=1), sat 2'b11, 0-pad
            u_t0_ctr_nxt[s] =
              (u_prm_ctr[s][TAGE_TBL_CTR[0]-1:0] == 2'b11)
                ? TAGE_MAX_CTR_WIDTH'(2'b11)
                : TAGE_MAX_CTR_WIDTH'(
                    u_prm_ctr[s][TAGE_TBL_CTR[0]-1:0]
                    + 2'b01);
          end else begin
            // DEC T0 CTR, saturate at 2'b00
            u_t0_ctr_nxt[s] =
              (u_prm_ctr[s][TAGE_TBL_CTR[0]-1:0] == 2'b00)
                ? TAGE_MAX_CTR_WIDTH'(2'b00)
                : TAGE_MAX_CTR_WIDTH'(
                    u_prm_ctr[s][TAGE_TBL_CTR[0]-1:0]
                    - 2'b01);
          end
        end else begin
          // At least one tagged provider
          // -- Primary CTR update (prm_comp > 0)
          if (u_prm_tagged[s]) begin
            if (u_using_prm[s]) begin
              // Provider = prm: INC correct, DEC wrong
              u_prm_ctr_wr[s] = 1'b1;
              if (u_prm_crt[s]) begin
                u_prm_ctr_nxt[s] =
                  (u_prm_ctr[s] == 3'b111)
                    ? 3'b111
                    : u_prm_ctr[s] + 3'b001;
              end else begin
                u_prm_ctr_nxt[s] =
                  (u_prm_ctr[s] == 3'b000)
                    ? 3'b000
                    : u_prm_ctr[s] - 3'b001;
              end
            end else begin
              // Provider = alt: INC prm if pred_diff and prm right
              if (u_pred_diff[s] && u_prm_crt[s]) begin
                u_prm_ctr_wr[s] = 1'b1;
                u_prm_ctr_nxt[s] =
                  (u_prm_ctr[s] == 3'b111)
                    ? 3'b111
                    : u_prm_ctr[s] + 3'b001;
              end
            end
          end
          // -- Alt CTR update (alt_comp > 0)
          if (u_alt_tagged[s]) begin
            if (!u_using_prm[s]) begin
              // Provider = alt: INC correct, DEC wrong
              u_alt_ctr_wr[s] = 1'b1;
              if (u_alt_crt[s]) begin
                u_alt_ctr_nxt[s] =
                  (u_alt_ctr[s] == 3'b111)
                    ? 3'b111
                    : u_alt_ctr[s] + 3'b001;
              end else begin
                u_alt_ctr_nxt[s] =
                  (u_alt_ctr[s] == 3'b000)
                    ? 3'b000
                    : u_alt_ctr[s] - 3'b001;
              end
            end else begin
              // Provider = prm: INC alt if pred_diff and alt right
              if (u_pred_diff[s] && u_alt_crt[s]) begin
                u_alt_ctr_wr[s] = 1'b1;
                u_alt_ctr_nxt[s] =
                  (u_alt_ctr[s] == 3'b111)
                    ? 3'b111
                    : u_alt_ctr[s] + 3'b001;
              end
            end
          end
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // USE/EPC update: per slot.
  // Rules: tage_cntrl_use_update_rules.md Table 7.
  // Fires when: pred_diff AND NOT both-T0 (rows 3-6).
  // Target comp: prm when using_primary, alt otherwise.
  // Action: INC u_eff when correct (mispredict=0),
  //         DEC u_eff when wrong  (mispredict=1).
  // u_eff stored in prm/alt_useful; written back as USEFUL.
  // lcl_epoch written to EPC field on every USE update.
  // ----------------------------------------------------------------

  always_comb begin : use_upd_comb
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      u_use_wr[s]   = 1'b0;
      u_use_nxt[s]  = '0;
      u_epc_nxt[s]  = lcl_epoch[s];
      u_use_comp[s] = '0;
      u_use_idx[s]  = '0;

      if (tage_upd_val_u0[s]
          && u_pred_diff[s]
          && !u_both_t0[s]) begin
        u_use_wr[s] = 1'b1;
        if (u_using_prm[s]) begin
          // Rows 3,4: select prm useful
          u_use_comp[s] = u_prm_comp[s];
          u_use_idx[s]  = u_prm_idx[s];
          if (!u_mispredict[s]) begin
            // INC u_eff (row 3)
            u_use_nxt[s] =
              (u_prm_use[s] == 2'b11)
                ? 2'b11 : u_prm_use[s] + 2'b01;
          end else begin
            // DEC u_eff (row 4)
            u_use_nxt[s] =
              (u_prm_use[s] == 2'b00)
                ? 2'b00 : u_prm_use[s] - 2'b01;
          end
        end else begin
          // Rows 5,6: select alt useful
          u_use_comp[s] = u_alt_comp[s];
          u_use_idx[s]  = u_alt_idx[s];
          if (!u_mispredict[s]) begin
            // INC u_eff (row 5)
            u_use_nxt[s] =
              (u_alt_use[s] == 2'b11)
                ? 2'b11 : u_alt_use[s] + 2'b01;
          end else begin
            // DEC u_eff (row 6)
            u_use_nxt[s] =
              (u_alt_use[s] == 2'b00)
                ? 2'b00 : u_alt_use[s] - 2'b01;
          end
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // Allocation write: per slot.
  // Rules: tage_cntrl_alloc_rules.md.
  // Fires when: cond_mispredict AND prm_comp < TAGE_MAX_TBL
  //             AND alc_comp != 0 (valid candidate from predict).
  // Entry layout: {TAG[7:0], EPC[1:0], USE[1:0], CTR[2:0], VAL}
  //             = {alc_tag, lcl_epoch, 2'b00, 3'b100, 1'b1}
  // ----------------------------------------------------------------

  always_comb begin : alc_upd_comb
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      u_alc_wr[s] = 1'b0;
      u_alc_wd[s] = '0;

      if (tage_upd_val_u0[s]
          && u_mispredict[s]
          && (u_prm_comp[s] <
              TAGE_TBL_SEL_WIDTH'(TAGE_MAX_TBL))
          && (u_alc_comp[s] != '0)) begin
        u_alc_wr[s] = 1'b1;
        u_alc_wd[s] = {
          u_alc_tag[s],
          lcl_epoch[s],
          2'b00,
          3'b100,
          1'b1
        };
      end
    end
  end

  // ----------------------------------------------------------------
  // Table-facing outputs: pred/upd_val forwarded; update buses
  // driven per the CTR, USE, alloc logic above.
  // tbl_sel buses broadcast the component index to all tables;
  // each table self-gates its write on THIS_TABLE == tbl_sel.
  // ----------------------------------------------------------------

  generate
    for (genvar t = 0; t < TAGE_NUM_TABLES; t++) begin : gen_tbl
      // Forward prediction and update valid to all tables
      assign t_pred_val_p0[t] = tage_pred_val_p0;
      assign t_upd_val_u0[t]  = tage_upd_val_u0;

      for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : gen_tbl_s
        // -- Table selector broadcast: same comp value to all tables
        assign t_prm_tbl_sel_u0[t][s] =
          TBL_SEL_WIDTH'(u_prm_comp[s]);
        assign t_alt_tbl_sel_u0[t][s] =
          TBL_SEL_WIDTH'(u_alt_comp[s]);
        assign t_alc_tbl_sel_u0[t][s] =
          TBL_SEL_WIDTH'(u_alc_comp[s]);

        // -- CTR write data
        // T0 path uses u_t0_ctr_nxt; tagged tables use prm/alt.
        assign t_prm_ctr_wd_u0[t][s] =
          (t == 0) ? u_t0_ctr_nxt[s] : u_prm_ctr_nxt[s];
        assign t_alt_ctr_wd_u0[t][s] = u_alt_ctr_nxt[s];

        // -- CTR write strobes (gated: trx_type==1 = UPD only)
        // T0 uses the prm_ctr_wr path (T0 is never an alt).
        // Tagged tables: strobe asserted only for target table.
        assign t_prm_ctr_wr_u0[t][s] =
          trx_type &&
          ((t == 0)
            ? u_t0_ctr_wr[s]
            : (u_prm_ctr_wr[s] &&
               (TAGE_TBL_SEL_WIDTH'(t) == u_prm_comp[s])));
        assign t_alt_ctr_wr_u0[t][s] =
          trx_type &&
          ((t == 0)
            ? 1'b0
            : (u_alt_ctr_wr[s] &&
               (TAGE_TBL_SEL_WIDTH'(t) == u_alt_comp[s])));

        // -- USE/EPC write data and strobes
        assign t_use_wd_u0[t][s] = u_use_nxt[s];
        assign t_epc_wd_u0[t][s] = u_epc_nxt[s];
        assign t_use_wr_u0[t][s] =
          trx_type &&
          u_use_wr[s] &&
          (TAGE_TBL_SEL_WIDTH'(t) == u_use_comp[s]);
        assign t_epc_wr_u0[t][s] =
          trx_type &&
          u_use_wr[s] &&
          (TAGE_TBL_SEL_WIDTH'(t) == u_use_comp[s]);

        // -- Allocation write data and strobe
        assign t_alc_wd_u0[t][s] = u_alc_wd[s];
        assign t_alc_wr_u0[t][s] =
          trx_type &&
          u_alc_wr[s] &&
          (TAGE_TBL_SEL_WIDTH'(t) == u_alc_comp[s]);

        // -- Update address: prm index for prm table,
        //    alt index for alt table. USE addr covered by same.
        assign t_upd_index_u0[t][s] =
          (TAGE_TBL_SEL_WIDTH'(t) == u_prm_comp[s])
            ? u_prm_idx[s]
            : (TAGE_TBL_SEL_WIDTH'(t) == u_alt_comp[s])
              ? u_alt_idx[s]
              : '0;

        // -- Allocation address
        assign t_alc_index_u0[t][s] =
          (TAGE_TBL_SEL_WIDTH'(t) == u_alc_comp[s])
            ? u_alc_idx[s] : '0;
      end
    end
  endgenerate

endmodule : tage_cntrl

`endif // TAGE_CNTRL_SV

`default_nettype wire
