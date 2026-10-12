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
// One bw_ram instance per prediction slot: g_slot[s].u_ram is slot s
// (NUM_PRED_SLOTS, 1 or 2; u_ram_s0 / u_ram_s1 before BP-128).
// No tag, no useful, no EPC, no allocation, no folded history.
// Prediction: inputs at p0, outputs at p1 (1-cycle latency).
// Update: write gated by THIS_TABLE == prm_tbl_sel_u0 (T0 is the
// primary, rows 13a-d) or THIS_TABLE == alt_tbl_sel_u0 (T0 is the
// alternate and use_alt_on_na chose it, BP-133 TD#18, provisional rows
// 19.1-19.8). tage_cntrl never drives both at T0 in one slot.
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
  input  logic [THIS_CTR_WIDTH-1:0]    alt_ctr_wd_u0[0:NUM_PRED_SLOTS-1],
  input  logic [NUM_PRED_SLOTS-1:0]    alt_ctr_wr_u0,
  input  logic [TBL_SEL_WIDTH-1:0]     alt_tbl_sel_u0[0:NUM_PRED_SLOTS-1],
  // upd_index_u0: the prm index when T0 is the prm target, else the alt
  // index (muxed in tage.sv, as for tage_table)
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

  // Shared RAM-init write enable. Every slot sees the same
  // tbl_ri signals.
  logic ri_we;
  assign ri_we = tbl_ri_active & tbl_ri_wr;

  // ============================================================
  // One RAM per slot (BP-128: the slot 0 and slot 1 blocks were two
  // copies; the loop follows NUM_PRED_SLOTS).
  // ============================================================
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_slot
    logic [THIS_INDEX_BITS-1:0]   ram_addr;
    logic [ALLOC_DATA_WIDTH-1:0]  ram_din;
    logic [ALLOC_DATA_WIDTH-1:0]  ram_bweb_n;
    logic                         ram_wen_n;
    logic [ALLOC_DATA_WIDTH-1:0]  ram_dout;

    logic ctr_match, ctr_we;
    logic alt_match, alt_we;

    // Fast init: write the bw_ram mem array at time zero via
    // hierarchical reference. Active only when +TAGE_FAST_INIT=1.
    // bw_ram mem is 2D: mem[BANKS][ENTRIES]. Loop covers both banks.
    // The value is TAGE_T0_SRAM_INIT_VALUE, 2'b10 weakly taken
    // (TD#103), the same value tage.sv drives on the walk.
    initial begin
      int fast_init;
      fast_init = 0;
      void'($value$plusargs("TAGE_FAST_INIT=%d", fast_init));
      if (fast_init != 0) begin
        for (int b = 0; b < NUM_BANKS; b++) begin
          for (int i = 0; i < RAM_ENTRIES; i++) begin
            u_ram.mem[b][i] =
              THIS_CTR_WIDTH'(TAGE_T0_SRAM_INIT_VALUE);
          end
        end
      end
    end

    assign ctr_match = (prm_tbl_sel_u0[s] == THIS_TBL_SEL);
    assign ctr_we    = tage_upd_val_u0[s]
                     & prm_ctr_wr_u0[s] & ctr_match;
    assign alt_match = (alt_tbl_sel_u0[s] == THIS_TBL_SEL);
    assign alt_we    = tage_upd_val_u0[s]
                     & alt_ctr_wr_u0[s] & alt_match;

    // T0 entry is all CTR bits. Every write enables all bits.
    assign ram_wen_n  = ~(ctr_we | alt_we | ri_we);
    assign ram_bweb_n = (ctr_we | alt_we | ri_we)
                      ? {ALLOC_DATA_WIDTH{1'b0}}
                      : {ALLOC_DATA_WIDTH{1'b1}};

    always_comb begin : addr_mux
      if (tbl_ri_active)
        ram_addr = tbl_ri_wa;
      else if (ctr_we | alt_we)
        ram_addr = upd_index_u0[s];
      else
        ram_addr =
          tage_pred_inp_p0[s].pc[PC_HASH_SHIFT +: THIS_INDEX_BITS];
    end

    always_comb begin : din_mux
      ram_din = {ALLOC_DATA_WIDTH{1'b0}};
      if (tbl_ri_active)
        ram_din = tbl_ri_wd;
      else if (ctr_we)
        ram_din = prm_ctr_wd_u0[s];
      else if (alt_we)
        ram_din = alt_ctr_wd_u0[s];
    end

    bw_ram #(
      .ENTRIES(RAM_ENTRIES),
      .WIDTH  (THIS_CTR_WIDTH),
      .BANKS  (NUM_BANKS)
    ) u_ram (
      .clk      (clk),
      .addr     (ram_addr[THIS_INDEX_BITS-2:0]),
      .bank_addr(ram_addr[THIS_INDEX_BITS-1]),
      .wen_n    (ram_wen_n),
      .bweb_n   (ram_bweb_n),
      .din      (ram_din),
      .dout     (ram_dout)
    );

    // taken_p1[s]: MSB of the 2b CTR read at p1.
    // cntrl_bits_p1[s]: full CTR entry read at p1.
    assign taken_p1[s]      = ram_dout[THIS_CTR_WIDTH-1];
    assign cntrl_bits_p1[s] = ram_dout;

    // Expose T0 index hash (combinational, p0).
    // Formula: pc[PC_HASH_SHIFT +: THIS_INDEX_BITS] per slot.
    assign idx_hash_p0[s] =
      tage_pred_inp_p0[s].pc[PC_HASH_SHIFT +: THIS_INDEX_BITS];
  end

endmodule : tage_bim

`endif // TAGE_BIM_SV

`default_nettype wire
