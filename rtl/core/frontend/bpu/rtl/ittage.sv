// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    ittage.sv
// DATE:    2026-05-18
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// ITTAGE structural wrapper. Instantiates ittage_cntrl and five
// ittage_table instances (IT1-IT5) with one shared sram_init.
// BP-038: PQ, UQ, credit arbiter, response buffer added.
// trx_type_comb forwarded combinationally (not registered).
// consumer_ready tied to 1'b1 internally; not a port.
// BP-038a: trx_type_comb connected to ittage_cntrl trx_type port.
// BP-038b: Response buffer removed; outputs driven directly from
//          ittage_cntrl. Six active arbitration rules remain.
// BP-132: the arbitration layer moved to ittage_arb (TD#52); the
//          queue status ports renamed ittage_pq_not_full /
//          ittage_uq_not_full (TD#49).
// ===================================================================
`ifndef ITTAGE_SV
`define ITTAGE_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ittage (
  input  logic                      clk,
  input  logic                      rstn,

  // prediction interface
  input  logic [NUM_PRED_SLOTS-1:0] ittage_pred_val_p0,
  input  ittage_pred_inp_t          ittage_pred_inp_p0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0] ittage_pred_rdy_p2,
  output ittage_pred_meta_t         ittage_pred_meta_p2[0:NUM_PRED_SLOTS-1],

  // update interface
  input  logic [NUM_PRED_SLOTS-1:0] ittage_upd_val_u0,
  input  ittage_upd_inp_t           ittage_upd_inp_u0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0] ittage_upd_rdy_u1,

  // arbitration status outputs (BP-038; TD#49 names, BP-132)
  output logic                      ittage_pq_not_full,
  output logic [NUM_PRED_SLOTS-1:0] ittage_uq_not_full,

  // aging control (shared across slots)
  input  logic                      ittage_enable_aging,
  input  logic [31:0]               ittage_aging_interval,

  // folded history (shared across prediction slots)
  input  bp_folded_hist_t           folded_hist,

  // ram init ready
  output logic                      ittage_rdy
);

  // ================================================================
  // Localparams -- must match ittage_cntrl and ittage_table.
  // ================================================================
  localparam int CNTRL_BITS_WIDTH =
    IT_MAX_VAL_WIDTH  + IT_MAX_CTR_WIDTH
    + IT_MAX_USE_WIDTH + IT_MAX_EPC_WIDTH
    + IT_MAX_TGT_WIDTH;  // 1+3+2+2+40 = 48

  localparam int IT_MAX_ALLOC_DATA_WIDTH =
    CNTRL_BITS_WIDTH + IT_MAX_TAG_WIDTH;  // 48+11 = 59

  // Max entries: 2^IT_MAX_IDX_WIDTH covers largest table (IT3-5).
  localparam int IT_MAX_NUM_ENTRIES = 1 << IT_MAX_IDX_WIDTH;

  // The arbitration FIFO and counter sizing is in ittage_arb (BP-132).

  // ================================================================
  // Fast-init mode: plusarg +ITTAGE_FAST_INIT=1.
  // When active: ittage_rdy driven high immediately.
  // sram_init still elaborates and cycles normally.
  // ================================================================
  logic fast_init;
  initial begin
    int fi;
    fi        = 0;
    fast_init = 1'b0;
    void'($value$plusargs("ITTAGE_FAST_INIT=%d", fi));
    if (fi != 0) fast_init = 1'b1;
  end

  // ================================================================
  // Shared sram_init: single instance at top level; MAX parameters
  // cover all five tables. All tables receive the same init signals.
  // ================================================================
  logic                               ri_cs;
  logic                               ri_wr;
  logic [IT_MAX_IDX_WIDTH-1:0]        ri_wa;
  logic [IT_MAX_ALLOC_DATA_WIDTH-1:0] ri_wd;
  logic                               ri_active;
  logic                               ri_rdy;

  sram_init #(
    .NUM_ENTRIES(IT_MAX_NUM_ENTRIES),
    .ADDR_BITS  (IT_MAX_IDX_WIDTH),
    .DATA_WIDTH (IT_MAX_ALLOC_DATA_WIDTH),
    .INIT_VAL   (IT_SRAM_INIT_VALUE)
  ) u_sram_init (
    .clk   (clk),
    .rstn  (rstn),
    .cs    (ri_cs),
    .wr    (ri_wr),
    .waddr (ri_wa),
    .wdata (ri_wd),
    .active(ri_active),
    .ready (ri_rdy)
  );

  // ================================================================
  // Internal bus: ittage_table outputs -> ittage_cntrl inputs.
  // All arrays [0:IT_NUM_TABLES-1]. Index 0 tied to zero (no IT0).
  // ================================================================
  logic [NUM_PRED_SLOTS-1:0] tbl_hit_p1[0:IT_NUM_TABLES-1];
  logic [IT_MAX_TGT_WIDTH-1:0]
    tbl_pred_tgt_p1[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [CNTRL_BITS_WIDTH-1:0]
    tbl_cntrl_bits_p1[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  // idx_hash output is THIS_INDEX_BITS; zero-extended to IT_MAX here.
  logic [IT_MAX_IDX_WIDTH-1:0]
    tbl_idx_hash_p0[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_TAG_WIDTH-1:0]
    tbl_tag_hash_p0[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];

  // IT0 placeholder -- never instantiated.
  assign tbl_hit_p1[0] = '0;
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : gen_tbl0_tie
    assign tbl_pred_tgt_p1[0][s]   = '0;
    assign tbl_cntrl_bits_p1[0][s] = '0;
    assign tbl_idx_hash_p0[0][s]   = '0;
    assign tbl_tag_hash_p0[0][s]   = '0;
  end : gen_tbl0_tie

  // ================================================================
  // Internal bus: ittage_cntrl outputs -> ittage_table inputs.
  // Write data fanned to all tables; alc_wd sliced per table width.
  // ================================================================
  logic [IT_MAX_CTR_WIDTH-1:0]
    cntrl_prm_ctr_wd[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_CTR_WIDTH-1:0]
    cntrl_alt_ctr_wd[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_USE_WIDTH-1:0]
    cntrl_use_wd[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_EPC_WIDTH-1:0]
    cntrl_epc_wd[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_TGT_WIDTH-1:0]
    cntrl_tgt_wd[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_ALLOC_DATA_WIDTH-1:0]
    cntrl_alc_wd[0:NUM_PRED_SLOTS-1];
  // Write strobes.
  logic [NUM_PRED_SLOTS-1:0] cntrl_prm_ctr_wr;
  logic [NUM_PRED_SLOTS-1:0] cntrl_alt_ctr_wr;
  logic [NUM_PRED_SLOTS-1:0] cntrl_use_wr;
  logic [NUM_PRED_SLOTS-1:0] cntrl_epc_wr;
  // Split tgt write strobes: prm fires UP=1, alt fires UP=0.
  logic [NUM_PRED_SLOTS-1:0] cntrl_prm_tgt_wr;
  logic [NUM_PRED_SLOTS-1:0] cntrl_alt_tgt_wr;
  logic [NUM_PRED_SLOTS-1:0] cntrl_alc_wr;
  // Table selectors.
  logic [IT_TBL_SEL_WIDTH-1:0]
    cntrl_prm_tbl_sel[0:NUM_PRED_SLOTS-1];
  logic [IT_TBL_SEL_WIDTH-1:0]
    cntrl_alt_tbl_sel[0:NUM_PRED_SLOTS-1];
  logic [IT_TBL_SEL_WIDTH-1:0]
    cntrl_alc_tbl_sel[0:NUM_PRED_SLOTS-1];
  // Update and allocation addresses (max width; sliced per table).
  logic [IT_MAX_IDX_WIDTH-1:0]
    cntrl_prm_upd_index[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_IDX_WIDTH-1:0]
    cntrl_alt_upd_index[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_IDX_WIDTH-1:0]
    cntrl_alc_index[0:NUM_PRED_SLOTS-1];

  // ================================================================
  // Arbitration layer (BP-038). The PQ, the UQ, the arbiter and the
  // competing stage mux are in ittage_arb since BP-132 (TD#52); this
  // module only connects it. ittage_cntrl's prediction results and
  // ittage_upd_rdy_u1 go to the ittage ports directly (no response
  // buffer, BP-038b).
  // ================================================================

  // -- Arbitrated signals (competing stage -> ittage_cntrl)
  logic [NUM_PRED_SLOTS-1:0]        cntrl_pred_val_p0;
  ittage_pred_inp_t
    cntrl_pred_inp_p0[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]        cntrl_upd_val_u0;
  ittage_upd_inp_t
    cntrl_upd_inp_u0[0:NUM_PRED_SLOTS-1];
  // trx_type_comb: combinational from the arbiter (not registered).
  logic                             trx_type_comb;

  // consumer_ready = 1'b1 internally; no downstream SC chain.

  ittage_arb u_ittage_arb (
    .clk                (clk),
    .rstn               (rstn),
    .ittage_pred_val_p0 (ittage_pred_val_p0),
    .ittage_pred_inp_p0 (ittage_pred_inp_p0),
    .ittage_upd_val_u0  (ittage_upd_val_u0),
    .ittage_upd_inp_u0  (ittage_upd_inp_u0),
    .ittage_pq_not_full (ittage_pq_not_full),
    .ittage_uq_not_full (ittage_uq_not_full),
    .cntrl_pred_val_p0  (cntrl_pred_val_p0),
    .cntrl_pred_inp_p0  (cntrl_pred_inp_p0),
    .cntrl_upd_val_u0   (cntrl_upd_val_u0),
    .cntrl_upd_inp_u0   (cntrl_upd_inp_u0),
    .trx_type           (trx_type_comb)
  );

  // ================================================================
  // ittage_cntrl instantiation. All ports connected.
  // ================================================================
  ittage_cntrl u_cntrl (
    .clk                  (clk),
    .rstn                 (rstn),
    .ittage_pred_val_p0   (cntrl_pred_val_p0),
    .ittage_pred_inp_p0   (cntrl_pred_inp_p0),
    .ittage_pred_rdy_p2   (ittage_pred_rdy_p2),
    .ittage_pred_meta_p2  (ittage_pred_meta_p2),
    .ittage_upd_val_u0    (cntrl_upd_val_u0),
    .ittage_upd_inp_u0    (cntrl_upd_inp_u0),
    .ittage_upd_rdy_u1    (ittage_upd_rdy_u1),
    .ittage_enable_aging  (ittage_enable_aging),
    .ittage_aging_interval(ittage_aging_interval),
    .trx_type             (trx_type_comb),
    .t_hit_p1             (tbl_hit_p1),
    .t_pred_tgt_p1        (tbl_pred_tgt_p1),
    .t_cntrl_bits_p1      (tbl_cntrl_bits_p1),
    .t_idx_hash_p0        (tbl_idx_hash_p0),
    .t_tag_hash_p0        (tbl_tag_hash_p0),
    .t_prm_ctr_wd_u0      (cntrl_prm_ctr_wd),
    .t_alt_ctr_wd_u0      (cntrl_alt_ctr_wd),
    .t_use_wd_u0          (cntrl_use_wd),
    .t_epc_wd_u0          (cntrl_epc_wd),
    .t_tgt_wd_u0          (cntrl_tgt_wd),
    .t_alc_wd_u0          (cntrl_alc_wd),
    .t_prm_ctr_wr_u0      (cntrl_prm_ctr_wr),
    .t_alt_ctr_wr_u0      (cntrl_alt_ctr_wr),
    .t_use_wr_u0          (cntrl_use_wr),
    .t_epc_wr_u0          (cntrl_epc_wr),
    .t_prm_tgt_wr_u0      (cntrl_prm_tgt_wr),
    .t_alt_tgt_wr_u0      (cntrl_alt_tgt_wr),
    .t_alc_wr_u0          (cntrl_alc_wr),
    .t_prm_tbl_sel_u0     (cntrl_prm_tbl_sel),
    .t_alt_tbl_sel_u0     (cntrl_alt_tbl_sel),
    .t_alc_tbl_sel_u0     (cntrl_alc_tbl_sel),
    .t_prm_upd_index_u0   (cntrl_prm_upd_index),
    .t_alt_upd_index_u0   (cntrl_alt_upd_index),
    .t_alc_index_u0       (cntrl_alc_index)
  );

  // ================================================================
  // IT1-IT5: ittage_table instances.
  // t=0 skipped (no IT0 base table).
  // - alc_wd sliced to each table's ALLOC_DATA_WIDTH = 46+TH_TAG.
  // - upd_index and alc_index sliced to TH_IDX bits.
  // - idx_hash_p0 zero-extended from TH_IDX to IT_MAX_IDX_WIDTH.
  // - tbl_ri_* driven from shared sram_init; wa/wd sliced per table.
  // - pred/upd val and inp routed through arbitration layer.
  // ================================================================
  for (genvar t = 0;
       t < IT_NUM_TABLES; t++) begin : gen_ittage_tables
    if (t != 0) begin : gen_active

      localparam int TH_IDX = IT_TBL_IDX[t];
      localparam int TH_TAG = IT_TBL_TAG[t];
      localparam int TH_ALC = CNTRL_BITS_WIDTH + TH_TAG;

      // Per-slot signals sliced to this table's widths.
      logic [TH_ALC-1:0]  alc_wd_s[0:NUM_PRED_SLOTS-1];
      logic [TH_IDX-1:0]  upd_idx_s[0:NUM_PRED_SLOTS-1];
      logic [TH_IDX-1:0]  alc_idx_s[0:NUM_PRED_SLOTS-1];
      // idx_hash at table width before extension to max.
      logic [TH_IDX-1:0]  idx_hash_local[0:NUM_PRED_SLOTS-1];
      logic               tbl_ri_active_w;
      logic               tbl_ri_wr;
      logic [TH_IDX-1:0]  tbl_ri_wa;
      logic [TH_ALC-1:0]  tbl_ri_wd;
      assign tbl_ri_active_w = fast_init ? 1'b0 : ri_active;
      assign tbl_ri_wr = fast_init ? '0 : ri_wr;
      assign tbl_ri_wa = fast_init ? '0 : ri_wa[TH_IDX-1:0];
      assign tbl_ri_wd = fast_init ? '0 : ri_wd[TH_ALC-1:0];

      for (genvar s = 0;
           s < NUM_PRED_SLOTS; s++) begin : gen_slot_signals
        assign alc_wd_s[s]  = cntrl_alc_wd[s][TH_ALC-1:0];
        // Route prm or alt update index: prm if this table is the
        // primary provider, alt otherwise. Prm and alt are always
        // different tables so the comparison is exclusive.
        assign upd_idx_s[s] =
          (cntrl_prm_tbl_sel[s] == IT_TBL_SEL_WIDTH'(t))
          ? TH_IDX'(cntrl_prm_upd_index[s])
          : TH_IDX'(cntrl_alt_upd_index[s]);
        assign alc_idx_s[s] = cntrl_alc_index[s][TH_IDX-1:0];
        assign tbl_idx_hash_p0[t][s] =
          IT_MAX_IDX_WIDTH'(idx_hash_local[s]);
      end : gen_slot_signals

      ittage_table #(
        .THIS_TABLE     (t),
        .THIS_INDEX_BITS(TH_IDX),
        .THIS_TAG_BITS  (TH_TAG)
      ) u_table (
        .hit_p1             (tbl_hit_p1[t]),
        .pred_tgt_p1        (tbl_pred_tgt_p1[t]),
        .cntrl_bits_p1      (tbl_cntrl_bits_p1[t]),
        .idx_hash_p0        (idx_hash_local),
        .tag_hash_p0        (tbl_tag_hash_p0[t]),
        .ittage_pred_val_p0 (cntrl_pred_val_p0),
        .ittage_pred_inp_p0 (cntrl_pred_inp_p0),
        .folded_hist        (folded_hist),
        .ittage_upd_val_u0  (cntrl_upd_val_u0),
        .prm_ctr_wd_u0      (cntrl_prm_ctr_wd),
        .alt_ctr_wd_u0      (cntrl_alt_ctr_wd),
        .use_wd_u0          (cntrl_use_wd),
        .epc_wd_u0          (cntrl_epc_wd),
        .tgt_wd_u0          (cntrl_tgt_wd),
        .alc_wd_u0          (alc_wd_s),
        .prm_ctr_wr_u0      (cntrl_prm_ctr_wr),
        .alt_ctr_wr_u0      (cntrl_alt_ctr_wr),
        .use_wr_u0          (cntrl_use_wr),
        .epc_wr_u0          (cntrl_epc_wr),
        .prm_tgt_wr_u0      (cntrl_prm_tgt_wr),
        .alt_tgt_wr_u0      (cntrl_alt_tgt_wr),
        .alc_wr_u0          (cntrl_alc_wr),
        .prm_tbl_sel_u0     (cntrl_prm_tbl_sel),
        .alt_tbl_sel_u0     (cntrl_alt_tbl_sel),
        .alc_tbl_sel_u0     (cntrl_alc_tbl_sel),
        .upd_index_u0       (upd_idx_s),
        .alc_index_u0       (alc_idx_s),
        .tbl_ri_active      (tbl_ri_active_w),
        .tbl_ri_wr          (tbl_ri_wr),
        .tbl_ri_wa          (tbl_ri_wa),
        .tbl_ri_wd          (tbl_ri_wd),
        .rstn               (rstn),
        .clk                (clk)
      );

    end : gen_active
  end : gen_ittage_tables

  // ================================================================
  // ittage_rdy: sram_init complete or fast_init active.
  // ================================================================
  assign ittage_rdy = fast_init | ri_rdy;

endmodule : ittage

`endif // ITTAGE_SV

`default_nettype wire
