// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    sc.sv
// DATE:    2026-07-01
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Statistical Corrector (SC) structural top level. Parallels tage.sv.
// Wires the three completed SC layers together; adds no new control
// logic (BP-078 binding decisions):
//   - one sc_cntrl instance (the control/logic layer, BP-077).
//   - ST0-ST3 via one generate loop of sc_table.
//   - ST4 via a separate sc_brimli instance.
//   - one sram_init sized to the largest table (ST4), with the
//     SC_FAST_INIT tie-off mux (tage.sv pattern).
//
// The sc_cntrl index/counter buses are uniform SC_MAX_IDX_WIDTH (10) /
// SC_MAX_CTR_WIDTH (6). ST0-ST3 index ports are SC_TBL_IDX (9) wide, so
// this level zero-extends the table idx_hash_p2 up to the controller
// bus and slices the controller upd_index_u0 down to the table width.
// The counter buses need no adaptation (SC_MAX_CTR_WIDTH == SC_TBL_CTR
// at the current geometry). ST4 index width equals SC_MAX_IDX_WIDTH, so
// its index ports connect directly.
//
// Prediction and update valids entering sc_cntrl are gated on sc_ready
// so no prediction or update proceeds before RAM init completes.
//
// Arbitration-layer ports (sc_uq_not_full, sc_upd_rdy) have no producer
// in this unit (SC UQ / credit arbiter deferred to bp_cluster, TD#73/
// #94). They are presented and stubbed with safe constants. sc_enable
// is presented but not internally qualified (IC-SC-05); the cluster
// gates SC consumption.
//
// NUM_PRED_SLOTS shadows bp_defines_pkg::NUM_PRED_SLOTS. sc_cntrl,
// sc_table and sc_brimli each shadow it too. -Wno-VARHIDDEN required.
// sram_init uses an async reset; rstn also feeds the sync flops in
// sc_cntrl, so -Wno-SYNCASYNCNET is required (same as tage/ittage).
// ===================================================================
`ifndef SC_SV
`define SC_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module sc #(
  parameter int NUM_PRED_SLOTS = bp_defines_pkg::NUM_PRED_SLOTS,
  // BrIMLI ST4 index mode is a compile-time selector (sc_decisions.md
  // section 12), passed down to the sc_brimli ST4 instance. Not a port.
  parameter br_imli_mode_e SC_BR_IMLI_MODE = IDX_IMLI_PHR
) (
  input  logic                        clk,
  input  logic                        rstn,

  // -- prediction interface: TAGE response (p2 in)
  input  logic [NUM_PRED_SLOTS-1:0]   tage_pred_rdy_p2,
  input  tage_pred_meta_t             tage_pred_meta_p2[0:NUM_PRED_SLOTS-1],

  // -- prediction interface: staged p0 inputs presented at p2
  input  logic [VA_WIDTH-1:1]         inp_pc_p2[0:NUM_PRED_SLOTS-1],
  input  logic [9:0]                  sc_phr_p2,
  input  logic [SC_MAX_FH-1:0]        sc_t1_idx_fh_p2,
  input  logic [SC_MAX_FH-1:0]        sc_t2_idx_fh_p2,
  input  logic [SC_MAX_FH-1:0]        sc_t3_idx_fh_p2,

  // -- prediction interface: SC result (p3 out)
  output logic [NUM_PRED_SLOTS-1:0]   sc_pred_rdy_p3,
  output sc_pred_meta_t               sc_pred_meta_p3[0:NUM_PRED_SLOTS-1],

  // -- update interface
  input  logic [NUM_PRED_SLOTS-1:0]   sc_upd_val_u0,
  input  sc_upd_inp_t                 sc_upd_inp_u0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]   sc_upd_rdy_u1,

  // -- arbitration status outputs (stubbed; no UQ in this unit)
  output logic                        sc_uq_not_full,
  output logic [NUM_PRED_SLOTS-1:0]   sc_upd_rdy,

  // -- CSR enable (presented, not internally qualified; IC-SC-05)
  input  logic                        sc_enable,

  // -- ram init interface
  output logic                        sc_ready
);

  // ----------------------------------------------------------------
  // Local parameters (all derived from bp_defines_pkg)
  // ----------------------------------------------------------------
  localparam int NT  = SC_NUM_TABLES;      // 5
  localparam int ST4 = SC_NUM_TABLES - 1;  // 4 (BrIMLI table)

  // SC entry is the counter only: no tag/USE/EPC/valid. This mirrors
  // the ALLOC_DATA_WIDTH derivation in sc_table.sv / sc_brimli.sv.
  localparam int ALLOC_DATA_WIDTH = SC_MAX_VAL_WIDTH
                                  + SC_MAX_CTR_WIDTH
                                  + SC_MAX_USE_WIDTH
                                  + SC_MAX_EPC_WIDTH
                                  + SC_MAX_TAG_WIDTH;   // = 6

  // sram_init sized to the largest table (ST4).
  localparam int RI_ADDR_BITS = SC_TBL_IDX[ST4];      // 10
  localparam int RI_ENTRIES   = SC_TBL_ENTRIES[ST4];  // 1024

  // ----------------------------------------------------------------
  // Interconnect wires: sc_cntrl <-> table instances.
  // sc_cntrl drives the *_p2 / *_u0 outputs; the tables drive the
  // ctr_p3 / idx_hash_p2 inputs collected back into sc_cntrl.
  // ----------------------------------------------------------------
  // -- prediction, controller -> tables
  logic [NUM_PRED_SLOTS-1:0]   w_sc_pred_val_p2;
  logic [VA_WIDTH-1:1]         w_inp_pc_p2[0:NUM_PRED_SLOTS-1];
  logic [SC_MAX_FH-1:0]        w_idx_fh_p2[0:NT-1];
  logic [9:0]                  w_sc_phr_p2;
  logic [9:0]                  w_br_imli;

  // -- prediction, tables -> controller (uniform SC_MAX_* widths)
  logic [SC_MAX_CTR_WIDTH-1:0]
    w_ctr_p3[0:NT-1][0:NUM_PRED_SLOTS-1];
  logic [SC_MAX_IDX_WIDTH-1:0]
    w_idx_hash_p2[0:NT-1][0:NUM_PRED_SLOTS-1];

  // -- update, controller -> tables
  logic [NUM_PRED_SLOTS-1:0]   w_sc_upd_val_u0[0:NT-1];
  logic [SC_MAX_CTR_WIDTH-1:0]
    w_ctr_wd_u0[0:NT-1][0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]   w_ctr_wr_u0[0:NT-1];
  logic [SC_MAX_IDX_WIDTH-1:0]
    w_upd_index_u0[0:NT-1][0:NUM_PRED_SLOTS-1];

  // ----------------------------------------------------------------
  // sc_ready gating. No prediction or update enters sc_cntrl before
  // RAM init completes (sc_interfaces.md RAM Init Interface).
  // ----------------------------------------------------------------
  logic [NUM_PRED_SLOTS-1:0]   pred_rdy_p2_gated;
  logic [NUM_PRED_SLOTS-1:0]   upd_val_u0_gated;

  assign pred_rdy_p2_gated = tage_pred_rdy_p2 & {NUM_PRED_SLOTS{sc_ready}};
  assign upd_val_u0_gated  = sc_upd_val_u0    & {NUM_PRED_SLOTS{sc_ready}};

  // ----------------------------------------------------------------
  // Arbitration-layer stubs (no SC UQ / credit arbiter in this unit).
  // sc_uq_not_full: no queue yet -> always room.
  // sc_upd_rdy: safe constant. With no UQ the update channel always
  //   has room; drive all-ones (parallels tage upd_rdy when uq never
  //   full). Do not build a UQ (TD#73/#94).
  // ----------------------------------------------------------------
  assign sc_uq_not_full = 1'b1;
  assign sc_upd_rdy     = {NUM_PRED_SLOTS{1'b1}};

  // sc_enable is presented but not consumed here (IC-SC-05). Kept as
  // a documented, unqualified input; the cluster gates consumption.
  logic unused_sc_enable;
  assign unused_sc_enable = sc_enable;

  // ================================================================
  // sram_init: one shared instance sized to the largest table (ST4).
  // ================================================================
  logic                     ri_active_raw;
  logic                     ri_wr_raw;
  logic [RI_ADDR_BITS-1:0]  ri_wa_raw;
  logic [ALLOC_DATA_WIDTH-1:0] ri_wd_raw;
  logic                     ri_cs;       // unused (sram_init cs)
  logic                     ri_rdy_raw;

  // fast_init_r: set at time zero from +SC_FAST_INIT. Drives the
  // tbl_ri_* / sc_ready tie-off muxes (tage.sv pattern).
  logic fast_init_r;
  initial begin
    int fi;
    fi = 0;
    void'($value$plusargs("SC_FAST_INIT=%d", fi));
    fast_init_r = (fi != 0) ? 1'b1 : 1'b0;
  end

  // tbl_ri_* mux: fast_init_r=1 straps the init path to zero (the
  // table initial blocks seed the RAMs) and asserts sc_ready
  // immediately. fast_init_r=0 passes through sram_init raw outputs.
  // sram_init still runs its full FSM in fast mode; outputs ignored.
  logic                     tbl_ri_active;
  logic                     tbl_ri_wr;
  logic [RI_ADDR_BITS-1:0]  tbl_ri_wa;
  logic [ALLOC_DATA_WIDTH-1:0] tbl_ri_wd;

  assign tbl_ri_active = fast_init_r ? 1'b0 : ri_active_raw;
  assign tbl_ri_wr     = fast_init_r ? 1'b0 : ri_wr_raw;
  assign tbl_ri_wa     = fast_init_r ? '0   : ri_wa_raw;
  assign tbl_ri_wd     = fast_init_r ? '0   : ri_wd_raw;

  assign sc_ready = fast_init_r ? 1'b1 : ri_rdy_raw;

  sram_init #(
    .NUM_ENTRIES (RI_ENTRIES),
    .ADDR_BITS   (RI_ADDR_BITS),
    .DATA_WIDTH  (ALLOC_DATA_WIDTH),
    .INIT_VAL    (SC_SRAM_INIT_VALUE),
    .START_DELAY (8'h00)
  ) u_sram_init (
    .clk    (clk),
    .rstn   (rstn),
    .cs     (ri_cs),
    .wr     (ri_wr_raw),
    .waddr  (ri_wa_raw),
    .wdata  (ri_wd_raw),
    .active (ri_active_raw),
    .ready  (ri_rdy_raw)
  );

  // ================================================================
  // sc_cntrl: SC control / logic layer (BP-077). All SC-top-facing
  // valids are gated on sc_ready.
  // ================================================================
  sc_cntrl #(
    .NUM_PRED_SLOTS   (NUM_PRED_SLOTS)
  ) u_sc_cntrl (
    .clk              (clk),
    .rstn             (rstn),
    .tage_pred_rdy_p2 (pred_rdy_p2_gated),
    .tage_pred_meta_p2(tage_pred_meta_p2),
    .inp_pc_p2        (inp_pc_p2),
    .sc_phr_p2        (sc_phr_p2),
    .sc_t1_idx_fh_p2  (sc_t1_idx_fh_p2),
    .sc_t2_idx_fh_p2  (sc_t2_idx_fh_p2),
    .sc_t3_idx_fh_p2  (sc_t3_idx_fh_p2),
    .sc_pred_rdy_p3   (sc_pred_rdy_p3),
    .sc_pred_meta_p3  (sc_pred_meta_p3),
    .sc_upd_val_u0    (upd_val_u0_gated),
    .sc_upd_inp_u0    (sc_upd_inp_u0),
    .sc_upd_rdy_u1    (sc_upd_rdy_u1),
    .t_sc_pred_val_p2 (w_sc_pred_val_p2),
    .t_inp_pc_p2      (w_inp_pc_p2),
    .t_idx_fh_p2      (w_idx_fh_p2),
    .t_sc_phr_p2      (w_sc_phr_p2),
    .t_br_imli        (w_br_imli),
    .t_ctr_p3         (w_ctr_p3),
    .t_idx_hash_p2    (w_idx_hash_p2),
    .t_sc_upd_val_u0  (w_sc_upd_val_u0),
    .t_ctr_wd_u0      (w_ctr_wd_u0),
    .t_ctr_wr_u0      (w_ctr_wr_u0),
    .t_upd_index_u0   (w_upd_index_u0)
  );

  // ================================================================
  // ST0-ST3: sc_table via one generate loop.
  // Per-instance THIS_* come from the vectored bp_defines_pkg
  // parameters by index. Index-width adapters bridge the 9-bit table
  // ports and the 10-bit controller buses.
  // ================================================================
  genvar t;
  generate
    for (t = 0; t < ST4; t++) begin : gen_st
      localparam int T_IDX = SC_TBL_IDX[t];   // 9

      // Table-side (THIS_INDEX_BITS-wide) index wires.
      logic [T_IDX-1:0] st_idx_hash_p2[0:NUM_PRED_SLOTS-1];
      logic [T_IDX-1:0] st_upd_index_u0[0:NUM_PRED_SLOTS-1];

      // Index-bus adaptation, per slot:
      //   - zero-extend the 9-bit table idx up to the 10-bit bus.
      //   - slice the 10-bit controller upd index to 9-bit table in.
      for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : gen_adapt
        assign w_idx_hash_p2[t][s] =
          SC_MAX_IDX_WIDTH'(st_idx_hash_p2[s]);
        assign st_upd_index_u0[s] =
          w_upd_index_u0[t][s][T_IDX-1:0];
      end

      sc_table #(
        .THIS_TABLE     (t),
        .THIS_INDEX_BITS(SC_TBL_IDX[t]),
        .THIS_CTR_WIDTH (SC_TBL_CTR[t]),
        .THIS_ENTRIES   (SC_TBL_ENTRIES[t]),
        .THIS_FH        (SC_TBL_FH[t]),
        .NUM_PRED_SLOTS (NUM_PRED_SLOTS)
      ) u_st (
        .ctr_p3        (w_ctr_p3[t]),
        .idx_hash_p2   (st_idx_hash_p2),
        .sc_pred_val_p2(w_sc_pred_val_p2),
        .inp_pc_p2     (w_inp_pc_p2),
        .idx_fh_p2     (w_idx_fh_p2[t]),
        .sc_upd_val_u0 (w_sc_upd_val_u0[t]),
        .ctr_wd_u0     (w_ctr_wd_u0[t]),
        .ctr_wr_u0     (w_ctr_wr_u0[t]),
        .upd_index_u0  (st_upd_index_u0),
        .tbl_ri_active (tbl_ri_active),
        .tbl_ri_wr     (tbl_ri_wr),
        .tbl_ri_wa     (tbl_ri_wa[T_IDX-1:0]),
        .tbl_ri_wd     (tbl_ri_wd),
        .rstn          (rstn),
        .clk           (clk)
      );
    end
  endgenerate

  // ================================================================
  // ST4: sc_brimli. Its index ports are SC_MAX_IDX_WIDTH wide, so the
  // ctr/index buses connect directly (no adaptation). sc_brimli slices
  // inp_pc_p2[15:6] internally; do not slice here.
  // ================================================================
  sc_brimli #(
    .THIS_TABLE     (ST4),
    .THIS_INDEX_BITS(SC_TBL_IDX[ST4]),
    .THIS_CTR_WIDTH (SC_TBL_CTR[ST4]),
    .THIS_ENTRIES   (SC_TBL_ENTRIES[ST4]),
    .NUM_PRED_SLOTS (NUM_PRED_SLOTS),
    .BR_IMLI_MODE   (SC_BR_IMLI_MODE)
  ) u_st4 (
    .ctr_p3        (w_ctr_p3[ST4]),
    .idx_hash_p2   (w_idx_hash_p2[ST4]),
    .sc_pred_val_p2(w_sc_pred_val_p2),
    .inp_pc_p2     (w_inp_pc_p2),
    .sc_phr_p2     (w_sc_phr_p2),
    .br_imli       (w_br_imli),
    .sc_upd_val_u0 (w_sc_upd_val_u0[ST4]),
    .ctr_wd_u0     (w_ctr_wd_u0[ST4]),
    .ctr_wr_u0     (w_ctr_wr_u0[ST4]),
    .upd_index_u0  (w_upd_index_u0[ST4]),
    .tbl_ri_active (tbl_ri_active),
    .tbl_ri_wr     (tbl_ri_wr),
    .tbl_ri_wa     (tbl_ri_wa),
    .tbl_ri_wd     (tbl_ri_wd),
    .rstn          (rstn),
    .clk           (clk)
  );

endmodule : sc

`endif // SC_SV

`default_nettype wire
