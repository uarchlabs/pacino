// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tage_bim.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// TAGE base table (T0). Untagged bimodal predictor.
// Each entry is a THIS_CTR_WIDTH-bit saturating counter.
// Two bw_ram instances: RAM0 -> slot 0, RAM1 -> slot 1.
// No tag, no useful, no EPC, no allocation, no folded history.
// Prediction: inputs at p0, outputs at p1 (1-cycle latency).
// Update: write gated by THIS_TABLE == prm_tbl_sel_u0.
// tbl_ri_active + tbl_ri_wr: RAM-init overrides all writes.
//
// This requires manual validation checks
// ===================================================================
`ifndef TAGE_BIM_SV
`define TAGE_BIM_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tage_bim #(
  parameter  int THIS_TABLE      = 0,
  parameter  int THIS_INDEX_BITS = TAGE_TBL_IDX[0],
  parameter  int THIS_CTR_WIDTH  = TAGE_TBL_CTR[0],
  parameter  int TBL_SEL_WIDTH   = TAGE_TBL_SEL_WIDTH,
  parameter  int NUM_PRED_SLOTS  = 2,
  // Derived - do not override.
  // RAM entry: CTR only. No tag, no valid, no useful, no EPC.
  localparam int ALLOC_DATA_WIDTH = THIS_CTR_WIDTH
) (
  // -- prediction outputs
  output logic [NUM_PRED_SLOTS-1:0]    taken_p1,
  output logic [THIS_CTR_WIDTH-1:0]    cntrl_bits_p1[0:NUM_PRED_SLOTS-1],
  // -- hash output (p0, combinational; registered in tage_cntrl)
  output logic [THIS_INDEX_BITS-1:0]
    idx_hash_p0[0:NUM_PRED_SLOTS-1],
  // -- prediction inputs
  input  logic [NUM_PRED_SLOTS-1:0]    tage_pred_val_p0,
  input  tage_pred_inp_t               tage_pred_inp_p0[0:NUM_PRED_SLOTS-1],
  // -- update inputs
  input  logic [NUM_PRED_SLOTS-1:0]    tage_upd_val_u0,
  input  logic [THIS_CTR_WIDTH-1:0]    prm_ctr_wd_u0[0:NUM_PRED_SLOTS-1],
  input  logic [NUM_PRED_SLOTS-1:0]    prm_ctr_wr_u0,
  input  logic [TBL_SEL_WIDTH-1:0]     prm_tbl_sel_u0[0:NUM_PRED_SLOTS-1],
  input  logic [THIS_INDEX_BITS-1:0]   upd_index_u0[0:NUM_PRED_SLOTS-1],
  // -- RAM initialization
  input  logic                         tbl_ri_active,
  input  logic                         tbl_ri_wr,
  input  logic [THIS_INDEX_BITS-1:0]   tbl_ri_wa,
  input  logic [ALLOC_DATA_WIDTH-1:0]  tbl_ri_wd,
  // -- clock and reset
  input  logic                         rstn,
  input  logic                         clk
);

  // RAM depth: 2^THIS_INDEX_BITS entries total across both banks.
  localparam int RAM_DEPTH   = 1 << THIS_INDEX_BITS;
  localparam int NUM_BANKS   = 2;
  // RAM rows per bank: index MSB selects bank, lower bits select row.
  localparam int RAM_ENTRIES = RAM_DEPTH / NUM_BANKS;

  // Constant table selector for this instance (THIS_TABLE=0).
  localparam logic [TBL_SEL_WIDTH-1:0] THIS_TBL_SEL =
    TBL_SEL_WIDTH'(THIS_TABLE);

  // Fast init: write bw_ram mem arrays at time zero via
  // hierarchical reference. Active only when +TAGE_FAST_INIT=1.
  // bw_ram mem is 2D: mem[BANKS][ENTRIES]. Loop covers both banks.
  initial begin
    int fast_init;
    fast_init = 0;
    void'($value$plusargs("TAGE_FAST_INIT=%d", fast_init));
    if (fast_init != 0) begin
      for (int b = 0; b < 2; b++) begin
        for (int i = 0; i < RAM_ENTRIES; i++) begin
          u_ram_s0.mem[b][i] =
            THIS_CTR_WIDTH'(TAGE_SRAM_INIT_VALUE);
          u_ram_s1.mem[b][i] =
            THIS_CTR_WIDTH'(TAGE_SRAM_INIT_VALUE);
        end
      end
    end
  end

  // Shared RAM-init write enable. Both slots see the same
  // tbl_ri signals.
  logic ri_we;
  assign ri_we = tbl_ri_active & tbl_ri_wr;

  // ============================================================
  // Slot 0
  // ============================================================
  logic [THIS_INDEX_BITS-1:0]   ram_addr_s0;
  logic [ALLOC_DATA_WIDTH-1:0]  ram_din_s0;
  logic [ALLOC_DATA_WIDTH-1:0]  ram_bweb_n_s0;
  logic                         ram_wen_n_s0;
  logic [ALLOC_DATA_WIDTH-1:0]  ram_dout_s0;

  logic ctr_match_s0, ctr_we_s0;

  assign ctr_match_s0 = (prm_tbl_sel_u0[0] == THIS_TBL_SEL);
  assign ctr_we_s0    = tage_upd_val_u0[0]
                      & prm_ctr_wr_u0[0] & ctr_match_s0;

  // T0 entry is all CTR bits. Every write enables all bits.
  assign ram_wen_n_s0  = ~(ctr_we_s0 | ri_we);
  assign ram_bweb_n_s0 = (ctr_we_s0 | ri_we)
                       ? {ALLOC_DATA_WIDTH{1'b0}}
                       : {ALLOC_DATA_WIDTH{1'b1}};

  always_comb begin : addr_mux_s0
    if (tbl_ri_active)
      ram_addr_s0 = tbl_ri_wa;
    else if (ctr_we_s0)
      ram_addr_s0 = upd_index_u0[0];
    else
      ram_addr_s0 =
        tage_pred_inp_p0[0].pc[INST_OFFSET +: THIS_INDEX_BITS];
  end

  always_comb begin : din_mux_s0
    ram_din_s0 = {ALLOC_DATA_WIDTH{1'b0}};
    if (tbl_ri_active)
      ram_din_s0 = tbl_ri_wd;
    else if (ctr_we_s0)
      ram_din_s0 = prm_ctr_wd_u0[0];
  end

  bw_ram #(
    .ENTRIES(RAM_ENTRIES),
    .WIDTH  (THIS_CTR_WIDTH),
    .BANKS  (NUM_BANKS)
  ) u_ram_s0 (
    .clk      (clk),
    .addr     (ram_addr_s0[THIS_INDEX_BITS-2:0]),
    .bank_addr(ram_addr_s0[THIS_INDEX_BITS-1]),
    .wen_n    (ram_wen_n_s0),
    .bweb_n   (ram_bweb_n_s0),
    .din      (ram_din_s0),
    .dout     (ram_dout_s0)
  );

  // taken_p1[0]: MSB of the 2b CTR read at p1.
  // cntrl_bits_p1[0]: full CTR entry read at p1.
  assign taken_p1[0]      = ram_dout_s0[THIS_CTR_WIDTH-1];
  assign cntrl_bits_p1[0] = ram_dout_s0;

  // ============================================================
  // Slot 1
  // ============================================================
  logic [THIS_INDEX_BITS-1:0]   ram_addr_s1;
  logic [ALLOC_DATA_WIDTH-1:0]  ram_din_s1;
  logic [ALLOC_DATA_WIDTH-1:0]  ram_bweb_n_s1;
  logic                         ram_wen_n_s1;
  logic [ALLOC_DATA_WIDTH-1:0]  ram_dout_s1;

  logic ctr_match_s1, ctr_we_s1;

  assign ctr_match_s1 = (prm_tbl_sel_u0[1] == THIS_TBL_SEL);
  assign ctr_we_s1    = tage_upd_val_u0[1]
                      & prm_ctr_wr_u0[1] & ctr_match_s1;

  assign ram_wen_n_s1  = ~(ctr_we_s1 | ri_we);
  assign ram_bweb_n_s1 = (ctr_we_s1 | ri_we)
                       ? {ALLOC_DATA_WIDTH{1'b0}}
                       : {ALLOC_DATA_WIDTH{1'b1}};

  always_comb begin : addr_mux_s1
    if (tbl_ri_active)
      ram_addr_s1 = tbl_ri_wa;
    else if (ctr_we_s1)
      ram_addr_s1 = upd_index_u0[1];
    else
      ram_addr_s1 =
        tage_pred_inp_p0[1].pc[INST_OFFSET +: THIS_INDEX_BITS];
  end

  always_comb begin : din_mux_s1
    ram_din_s1 = {ALLOC_DATA_WIDTH{1'b0}};
    if (tbl_ri_active)
      ram_din_s1 = tbl_ri_wd;
    else if (ctr_we_s1)
      ram_din_s1 = prm_ctr_wd_u0[1];
  end

  bw_ram #(
    .ENTRIES(RAM_ENTRIES),
    .WIDTH  (THIS_CTR_WIDTH),
    .BANKS  (NUM_BANKS)
  ) u_ram_s1 (
    .clk      (clk),
    .addr     (ram_addr_s1[THIS_INDEX_BITS-2:0]),
    .bank_addr(ram_addr_s1[THIS_INDEX_BITS-1]),
    .wen_n    (ram_wen_n_s1),
    .bweb_n   (ram_bweb_n_s1),
    .din      (ram_din_s1),
    .dout     (ram_dout_s1)
  );

  assign taken_p1[1]      = ram_dout_s1[THIS_CTR_WIDTH-1];
  assign cntrl_bits_p1[1] = ram_dout_s1;

  // Expose T0 index hash (combinational, p0).
  // Formula: pc[INST_OFFSET +: THIS_INDEX_BITS] per slot.
  assign idx_hash_p0[0] =
    tage_pred_inp_p0[0].pc[INST_OFFSET +: THIS_INDEX_BITS];
  assign idx_hash_p0[1] =
    tage_pred_inp_p0[1].pc[INST_OFFSET +: THIS_INDEX_BITS];

endmodule : tage_bim

`endif // TAGE_BIM_SV

`default_nettype wire
