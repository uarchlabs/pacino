// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tage.sv
// DATE:    2026-05-12
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// TAGE predictor structural top level.
// T0: tage_bim (untagged bimodal, no hit_p1, no folded_hist).
// T1-T4: tage_table via generate loop (gen_tage_tbl).
// tage_cntrl: one instance. sram_init: one instance.
// tage_cntrl drives all table buses at MAX_* widths.
// Per-table intermediate wires in generate loop slice cntrl
// outputs to THIS_* widths for each tage_table instance.
// T0 cntrl_bits: 2b CTR zero-extended to CNTRL_BITS_W=8b.
// T0 hit_p1: driven '1 (T0 always hits, no tag comparison).
// BP-023b: PQ, UQ, credit arbiter, response buffer added.
// trx_type forwarded to tage_cntrl (combinational, not registered).
// BP-023c: consumer_ready promoted to input port (SC drives it).
// BP-132: the arbitration layer moved to tage_arb (TD#52); the queue
// status ports renamed tage_pq_not_full / tage_uq_not_full (TD#49).
// ===================================================================

`ifndef TAGE_SV
`define TAGE_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tage (
  input  logic                             clk,
  input  logic                             rstn,
  // -- prediction interface
  input  logic [NUM_PRED_SLOTS-1:0]        tage_pred_val_p0,
  input  tage_pred_inp_t                   tage_pred_inp_p0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]        tage_pred_rdy_p2,
  output tage_pred_meta_t                  tage_pred_meta_p2[0:NUM_PRED_SLOTS-1],
  // -- update interface
  input  logic [NUM_PRED_SLOTS-1:0]        tage_upd_val_u0,
  input  tage_upd_inp_t                    tage_upd_inp_u0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]        tage_upd_rdy_u1,
  // -- arbitration status outputs (BP-023b; TD#49 names, BP-132)
  output logic                             tage_pq_not_full,
  output logic [NUM_PRED_SLOTS-1:0]        tage_uq_not_full,
  // -- aging control (shared across both slots)
  input  logic                             tage_enable_aging,
  input  logic [31:0]                      tage_aging_interval,
  // -- consumer ready (SC drives; 1=ready to accept result)
  input  logic                             consumer_ready,
  // -- folded history (T1-T4 only; tage_bim does not use)
  input  bp_folded_hist_t                  folded_hist,
  // -- RAM init ready
  output logic                             tage_rdy
);

  // ----------------------------------------------------------------
  // Local parameters
  // ----------------------------------------------------------------
  // CNTRL_BITS_W: packed control field width at MAX_* widths.
  localparam int CNTRL_BITS_W =
    TAGE_MAX_EPC_WIDTH + TAGE_MAX_USE_WIDTH
    + TAGE_MAX_CTR_WIDTH + TAGE_MAX_VAL_WIDTH; // = 8
  // ALLOC_DATA_W: tage_table T1-T4 RAM entry width.
  localparam int ALLOC_DATA_W =
    CNTRL_BITS_W + TAGE_MAX_TAG_WIDTH;   // = 16
  // TBL_SEL_W: matches TAGE_TBL_SEL_WIDTH in bp_defines_pkg.
  localparam int TBL_SEL_W = TAGE_TBL_SEL_WIDTH; // = 3

  // The arbitration FIFO and counter sizing is in tage_arb (BP-132).

  // ----------------------------------------------------------------
  // Interconnect wires: tage_cntrl <-> table instances
  // ----------------------------------------------------------------

  // -- prediction val forwarded to each table
  logic [NUM_PRED_SLOTS-1:0]
    w_pred_val_p0[0:TAGE_NUM_TABLES-1];

  // -- prediction results collected from each table
  // w_hit_p1[0]: T0 always hits; driven constant 1 below.
  // w_hit_p1[1:4]: driven by tage_table instances.
  logic [NUM_PRED_SLOTS-1:0]
    w_hit_p1[0:TAGE_NUM_TABLES-1];
  logic [NUM_PRED_SLOTS-1:0]
    w_taken_p1[0:TAGE_NUM_TABLES-1];
  logic [CNTRL_BITS_W-1:0]
    w_cntrl_bits_p1
      [0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];

  // -- update enables
  logic [NUM_PRED_SLOTS-1:0]
    w_upd_val_u0[0:TAGE_NUM_TABLES-1];

  // -- update write data: shared per slot (collapsed)
  logic [TAGE_MAX_CTR_WIDTH-1:0]
    w_prm_ctr_wd_u0[0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_CTR_WIDTH-1:0]
    w_alt_ctr_wd_u0[0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_USE_WIDTH-1:0]
    w_use_wd_u0[0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_EPC_WIDTH-1:0]
    w_epc_wd_u0[0:NUM_PRED_SLOTS-1];
  logic [ALLOC_DATA_W-1:0]
    w_alc_wd_u0[0:NUM_PRED_SLOTS-1];

  // -- update write strobes
  logic [NUM_PRED_SLOTS-1:0]
    w_prm_ctr_wr_u0[0:TAGE_NUM_TABLES-1];
  logic [NUM_PRED_SLOTS-1:0]
    w_alt_ctr_wr_u0[0:TAGE_NUM_TABLES-1];
  logic [NUM_PRED_SLOTS-1:0]
    w_use_wr_u0[0:TAGE_NUM_TABLES-1];
  logic [NUM_PRED_SLOTS-1:0]
    w_epc_wr_u0[0:TAGE_NUM_TABLES-1];
  logic [NUM_PRED_SLOTS-1:0]
    w_alc_wr_u0[0:TAGE_NUM_TABLES-1];

  // -- table selector buses: shared per slot (collapsed)
  logic [TBL_SEL_W-1:0]
    w_prm_tbl_sel_u0[0:NUM_PRED_SLOTS-1];
  logic [TBL_SEL_W-1:0]
    w_alt_tbl_sel_u0[0:NUM_PRED_SLOTS-1];
  logic [TBL_SEL_W-1:0]
    w_alc_tbl_sel_u0[0:NUM_PRED_SLOTS-1];

  // -- update and allocation address buses: shared per slot
  // w_upd_index_u0: prm address; w_alt_upd_index_u0: alt address
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    w_upd_index_u0[0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    w_alt_upd_index_u0[0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    w_alc_index_u0[0:NUM_PRED_SLOTS-1];

  // -- p0 index and tag hashes collected from table instances
  // w_idx_p0[0]: from tage_bim.idx_hash_p0
  // w_idx_p0[1:4], w_tag_p0[1:4]: from tage_table instances
  // w_tag_p0[0]: T0 has no tag -- driven to zero below
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    w_idx_p0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_TAG_WIDTH-1:0]
    w_tag_p0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];

  // ----------------------------------------------------------------
  // sram_init raw outputs (before fast_init_r mux).
  // ----------------------------------------------------------------
  logic                      ri_active_raw;
  logic                      ri_wr_raw;
  logic [TAGE_MAX_IDX_WIDTH-1:0]  ri_wa_raw;
  logic [ALLOC_DATA_W-1:0]   ri_wd_raw;
  logic                      tbl_ri_cs;  // unused (sram_init cs)
  logic                      ri_rdy_raw;

  // ----------------------------------------------------------------
  // fast_init_r: set at time zero from +TAGE_FAST_INIT plusarg.
  // Drives the tbl_ri_* and tage_rdy muxes.
  // ----------------------------------------------------------------
  logic fast_init_r;
  initial begin
    int fi;
    fi = 0;
    void'($value$plusargs("TAGE_FAST_INIT=%d", fi));
    fast_init_r = (fi != 0) ? 1'b1 : 1'b0;
  end

  // ----------------------------------------------------------------
  // tbl_ri_* mux: fast_init_r=1 straps to zero (sram_init bypass).
  // fast_init_r=0: pass through sram_init raw outputs.
  // ----------------------------------------------------------------
  logic                      tbl_ri_active;
  logic                      tbl_ri_wr;
  logic [TAGE_MAX_IDX_WIDTH-1:0]  tbl_ri_wa;
  logic [ALLOC_DATA_W-1:0]   tbl_ri_wd;

  assign tbl_ri_active = fast_init_r ? 1'b0 : ri_active_raw;
  assign tbl_ri_wr     = fast_init_r ? 1'b0 : ri_wr_raw;
  assign tbl_ri_wa     = fast_init_r ? '0   : ri_wa_raw;
  assign tbl_ri_wd     = fast_init_r ? '0   : ri_wd_raw;

  // ----------------------------------------------------------------
  // T0 intermediate wires for tage_bim connections
  // tage_bim output width: THIS_CTR_WIDTH = TAGE_TBL_CTR[0] = 2b.
  // ----------------------------------------------------------------
  // tage_bim prediction outputs.
  logic [NUM_PRED_SLOTS-1:0]
    bim_taken_p1;
  logic [TAGE_TBL_CTR[0]-1:0]
    bim_cntrl_p1[0:NUM_PRED_SLOTS-1];
  // Update input slices: MAX_*-wide buses sliced to THIS_* widths.
  logic [TAGE_TBL_IDX[0]-1:0] bim_upd_idx_u0[0:NUM_PRED_SLOTS-1];
  logic [TAGE_TBL_CTR[0]-1:0] bim_prm_ctr_wd_u0[0:NUM_PRED_SLOTS-1];
  logic [TAGE_TBL_CTR[0]-1:0] bim_alt_ctr_wd_u0[0:NUM_PRED_SLOTS-1];

  // T0 hit: T0 (tage_bim) has no tag match; always hits.
  // Drive constant 1 for all slots.
  assign w_hit_p1[0]   = {NUM_PRED_SLOTS{1'b1}};
  // Wire T0 taken direction from tage_bim.
  assign w_taken_p1[0] = bim_taken_p1;
  // Per slot (BP-128: the slot 0 and slot 1 assigns were two
  // copies; the loop follows NUM_PRED_SLOTS).
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_t0_slot
    // Wire T0 cntrl_bits: zero-extend 2b CTR to CNTRL_BITS_W=8b.
    // Layout: [0]=VAL=1, [3:1]=CTR(2b padded to 3b), [7:4]=0.
    assign w_cntrl_bits_p1[0][s] =
      {5'b0, bim_cntrl_p1[s], 1'b1};
    // Slice update index: MAX_IDX -> TAGE_TBL_IDX[0]=11 (same). The
    // prm index when T0 is the prm target, else the alt index (BP-133,
    // TD#18: T0 is written as the alternate), as for gen_tage_tbl.
    assign bim_upd_idx_u0[s] = (w_prm_tbl_sel_u0[s] == '0)
      ? w_upd_index_u0[s][TAGE_TBL_IDX[0]-1:0]
      : w_alt_upd_index_u0[s][TAGE_TBL_IDX[0]-1:0];
    // Slice CTR write data: MAX_CTR=3 -> TAGE_TBL_CTR[0]=2.
    assign bim_prm_ctr_wd_u0[s] =
      w_prm_ctr_wd_u0[s][TAGE_TBL_CTR[0]-1:0];
    assign bim_alt_ctr_wd_u0[s] =
      w_alt_ctr_wd_u0[s][TAGE_TBL_CTR[0]-1:0];
    // T0 has no tag. Drive w_tag_p0[0] to zero for every slot.
    assign w_tag_p0[0][s] = '0;
  end

  // ================================================================
  // Arbitration layer (BP-023b). The PQ, the UQ, the arbiter, the
  // competing stage mux and the response buffer are in tage_arb since
  // BP-132 (TD#52); this module only connects it.
  // ================================================================

  // -- Arbitrated signals (competing stage -> tage_cntrl)
  logic [NUM_PRED_SLOTS-1:0]       cntrl_pred_val_p0;
  tage_pred_inp_t
    cntrl_pred_inp_p0[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]       cntrl_pred_rdy_p2;
  tage_pred_meta_t
    cntrl_pred_meta_p2[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]       cntrl_upd_val_u0;
  tage_upd_inp_t
    cntrl_upd_inp_u0[0:NUM_PRED_SLOTS-1];
  // trx_type_comb: combinational from the arbiter (not registered).
  logic                            trx_type_comb;

  tage_arb u_tage_arb (
    .clk                (clk),
    .rstn               (rstn),
    .tage_pred_val_p0   (tage_pred_val_p0),
    .tage_pred_inp_p0   (tage_pred_inp_p0),
    .tage_upd_val_u0    (tage_upd_val_u0),
    .tage_upd_inp_u0    (tage_upd_inp_u0),
    .tage_pred_rdy_p2   (tage_pred_rdy_p2),
    .tage_pred_meta_p2  (tage_pred_meta_p2),
    .tage_pq_not_full   (tage_pq_not_full),
    .tage_uq_not_full   (tage_uq_not_full),
    .consumer_ready     (consumer_ready),
    .cntrl_pred_val_p0  (cntrl_pred_val_p0),
    .cntrl_pred_inp_p0  (cntrl_pred_inp_p0),
    .cntrl_upd_val_u0   (cntrl_upd_val_u0),
    .cntrl_upd_inp_u0   (cntrl_upd_inp_u0),
    .trx_type           (trx_type_comb),
    .cntrl_pred_rdy_p2  (cntrl_pred_rdy_p2),
    .cntrl_pred_meta_p2 (cntrl_pred_meta_p2)
  );

  // ================================================================
  // tage_cntrl instance
  // ================================================================
  tage_cntrl u_tage_cntrl (
    .clk                 (clk),
    .rstn                (rstn),
    .tage_pred_val_p0    (cntrl_pred_val_p0),
    .tage_pred_inp_p0    (cntrl_pred_inp_p0),
    .tage_pred_rdy_p2    (cntrl_pred_rdy_p2),
    .tage_pred_meta_p2   (cntrl_pred_meta_p2),
    .tage_upd_val_u0     (cntrl_upd_val_u0),
    .tage_upd_inp_u0     (cntrl_upd_inp_u0),
    .tage_upd_rdy_u1     (tage_upd_rdy_u1),
    .trx_type            (trx_type_comb),
    .tage_enable_aging   (tage_enable_aging),
    .tage_aging_interval (tage_aging_interval),
    .t_pred_val_p0       (w_pred_val_p0),
    .t_hit_p1            (w_hit_p1),
    .t_taken_p1          (w_taken_p1),
    .t_cntrl_bits_p1     (w_cntrl_bits_p1),
    .t_upd_val_u0        (w_upd_val_u0),
    .t_prm_ctr_wd_u0     (w_prm_ctr_wd_u0),
    .t_alt_ctr_wd_u0     (w_alt_ctr_wd_u0),
    .t_use_wd_u0         (w_use_wd_u0),
    .t_epc_wd_u0         (w_epc_wd_u0),
    .t_alc_wd_u0         (w_alc_wd_u0),
    .t_prm_ctr_wr_u0     (w_prm_ctr_wr_u0),
    .t_alt_ctr_wr_u0     (w_alt_ctr_wr_u0),
    .t_use_wr_u0         (w_use_wr_u0),
    .t_epc_wr_u0         (w_epc_wr_u0),
    .t_alc_wr_u0         (w_alc_wr_u0),
    .t_prm_tbl_sel_u0    (w_prm_tbl_sel_u0),
    .t_alt_tbl_sel_u0    (w_alt_tbl_sel_u0),
    .t_alc_tbl_sel_u0    (w_alc_tbl_sel_u0),
    .t_upd_index_u0      (w_upd_index_u0),
    .t_alt_upd_index_u0  (w_alt_upd_index_u0),
    .t_alc_index_u0      (w_alc_index_u0),
    .t_idx_p0            (w_idx_p0),
    .t_tag_p0            (w_tag_p0)
  );

  // ================================================================
  // sram_init: one shared instance for all table instances.
  // DATA_WIDTH=ALLOC_DATA_W (16b) covers tage_table T1-T4 entry.
  // INIT_VAL=TAGE_SRAM_INIT_VALUE initializes the tagged tables. T0
  // takes TAGE_T0_SRAM_INIT_VALUE (2'b10, weakly taken, TD#103) on the
  // same walk; see the tage_bim instance.
  // ================================================================
  sram_init #(
    .NUM_ENTRIES (1 << TAGE_MAX_IDX_WIDTH),
    .ADDR_BITS   (TAGE_MAX_IDX_WIDTH),
    .DATA_WIDTH  (ALLOC_DATA_W),
    .INIT_VAL    (TAGE_SRAM_INIT_VALUE),
    .START_DELAY (8'h00)
  ) u_sram_init (
    .clk    (clk),
    .rstn   (rstn),
    .cs     (tbl_ri_cs),
    .wr     (ri_wr_raw),
    .waddr  (ri_wa_raw),
    .wdata  (ri_wd_raw),
    .active (ri_active_raw),
    .ready  (ri_rdy_raw)
  );

  // tage_rdy: muxed on fast_init_r.
  // fast_init_r=1: assert immediately (sram_init bypassed).
  // fast_init_r=0: follow sram_init ready output.
  assign tage_rdy = fast_init_r ? 1'b1 : ri_rdy_raw;

  // ================================================================
  // T0: tage_bim instance (outside generate).
  // Parameters bound from TAGE_TBL_* at index 0.
  // hit_p1: not present; w_hit_p1[0] driven constant 1 above.
  // tbl_ri_wd: the T0 reset value, TAGE_T0_SRAM_INIT_VALUE (2'b10,
  // weakly taken, TD#103), not the tagged tables' walk data. The walk
  // address and write enable are shared.
  // tage_pred_inp_p0: routed from arbitration (cntrl_pred_inp_p0).
  // ================================================================
  tage_bim #(
    .THIS_TABLE      (0),
    .THIS_INDEX_BITS (TAGE_TBL_IDX[0]),
    .THIS_CTR_WIDTH  (TAGE_TBL_CTR[0]),
    .TBL_SEL_WIDTH   (TAGE_TBL_SEL_WIDTH)
  ) u_tage_bim (
    .taken_p1         (bim_taken_p1),
    .cntrl_bits_p1    (bim_cntrl_p1),
    .tage_pred_val_p0 (w_pred_val_p0[0]),
    .tage_pred_inp_p0 (cntrl_pred_inp_p0),
    .tage_upd_val_u0  (w_upd_val_u0[0]),
    .prm_ctr_wd_u0    (bim_prm_ctr_wd_u0),
    .prm_ctr_wr_u0    (w_prm_ctr_wr_u0[0]),
    .prm_tbl_sel_u0   (w_prm_tbl_sel_u0),
    .alt_ctr_wd_u0    (bim_alt_ctr_wd_u0),
    .alt_ctr_wr_u0    (w_alt_ctr_wr_u0[0]),
    .alt_tbl_sel_u0   (w_alt_tbl_sel_u0),
    .upd_index_u0     (bim_upd_idx_u0),
    .tbl_ri_active    (tbl_ri_active),
    .tbl_ri_wr        (tbl_ri_wr),
    .tbl_ri_wa        (tbl_ri_wa),
    .tbl_ri_wd        (TAGE_TBL_CTR[0]'(TAGE_T0_SRAM_INIT_VALUE)),
    .rstn             (rstn),
    .clk              (clk),
    .idx_hash_p0      (w_idx_p0[0])
  );

  // ================================================================
  // T1-T4: tage_table instances via generate loop.
  // gen_tage_tbl: one instance per table index t=1..4.
  // Parameters bound from TAGE_TBL_* at index t.
  // Intermediate wires inside loop slice MAX_*-wide cntrl buses
  // to THIS_*_BITS for each tage_table instance.
  // tage_pred_inp_p0: routed from arbitration (cntrl_pred_inp_p0).
  // ================================================================
  genvar t;
  generate
    for (t = 1; t < TAGE_NUM_TABLES; t++) begin : gen_tage_tbl
      // Per-table width aliases.
      localparam int T_IDX_W = TAGE_TBL_IDX[t]; // = 11
      localparam int T_CTR_W = TAGE_TBL_CTR[t]; // = 3

      // Width-matched intermediate wires.
      // upd_index and alc_index: slice MAX_IDX -> THIS_INDEX.
      logic [T_IDX_W-1:0] upd_idx_w[0:NUM_PRED_SLOTS-1];
      logic [T_IDX_W-1:0] alc_idx_w[0:NUM_PRED_SLOTS-1];
      // prm_ctr and alt_ctr: slice MAX_CTR -> THIS_CTR.
      logic [T_CTR_W-1:0] prm_ctr_w[0:NUM_PRED_SLOTS-1];
      logic [T_CTR_W-1:0] alt_ctr_w[0:NUM_PRED_SLOTS-1];

      // One set per slot (BP-128: literal [0] / [1] before).
      for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_slot
        // prm index when this table is the prm target; else alt index.
        assign upd_idx_w[s] = (TBL_SEL_W'(t) == w_prm_tbl_sel_u0[s])
          ? w_upd_index_u0[s][T_IDX_W-1:0]
          : w_alt_upd_index_u0[s][T_IDX_W-1:0];
        assign alc_idx_w[s] = w_alc_index_u0[s][T_IDX_W-1:0];
        assign prm_ctr_w[s] = w_prm_ctr_wd_u0[s][T_CTR_W-1:0];
        assign alt_ctr_w[s] = w_alt_ctr_wd_u0[s][T_CTR_W-1:0];
      end

      tage_table #(
        .THIS_TABLE      (t),
        .THIS_INDEX_BITS (TAGE_TBL_IDX[t]),
        .THIS_TAG_BITS   (TAGE_TBL_TAG[t]),
        .THIS_EPC_WIDTH  (TAGE_TBL_EPC[t]),
        .THIS_USE_WIDTH  (TAGE_TBL_USE[t]),
        .THIS_CTR_WIDTH  (TAGE_TBL_CTR[t]),
        .TBL_SEL_WIDTH   (TAGE_TBL_SEL_WIDTH)
      ) u_tage_tbl (
        .clk              (clk),
        .rstn             (rstn),
        .hit_p1           (w_hit_p1[t]),
        .taken_p1         (w_taken_p1[t]),
        .cntrl_bits_p1    (w_cntrl_bits_p1[t]),
        .tage_pred_val_p0 (w_pred_val_p0[t]),
        .tage_pred_inp_p0 (cntrl_pred_inp_p0),
        .folded_hist      (folded_hist),
        .tage_upd_val_u0  (w_upd_val_u0[t]),
        .prm_ctr_wd_u0    (prm_ctr_w),
        .alt_ctr_wd_u0    (alt_ctr_w),
        .use_wd_u0        (w_use_wd_u0),
        .epc_wd_u0        (w_epc_wd_u0),
        .alc_wd_u0        (w_alc_wd_u0),
        .prm_ctr_wr_u0    (w_prm_ctr_wr_u0[t]),
        .alt_ctr_wr_u0    (w_alt_ctr_wr_u0[t]),
        .use_wr_u0        (w_use_wr_u0[t]),
        .epc_wr_u0        (w_epc_wr_u0[t]),
        .alc_wr_u0        (w_alc_wr_u0[t]),
        .prm_tbl_sel_u0   (w_prm_tbl_sel_u0),
        .alt_tbl_sel_u0   (w_alt_tbl_sel_u0),
        .alc_tbl_sel_u0   (w_alc_tbl_sel_u0),
        .upd_index_u0     (upd_idx_w),
        .alc_index_u0     (alc_idx_w),
        .tbl_ri_active    (tbl_ri_active),
        .tbl_ri_wr        (tbl_ri_wr),
        .tbl_ri_wa        (tbl_ri_wa),
        .tbl_ri_wd        (tbl_ri_wd),
        .idx_hash_p0      (w_idx_p0[t]),
        .tag_hash_p0      (w_tag_p0[t])
      );
    end
  endgenerate

endmodule : tage

`endif // TAGE_SV

`default_nettype wire
