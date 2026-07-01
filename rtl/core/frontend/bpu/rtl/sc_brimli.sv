// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    sc_brimli.sv
// DATE:    2026-07-01
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Parameterized Statistical Corrector (SC) BrIMLI counter table (ST4).
// Structurally identical to sc_table except the prediction index is
// get_br_imli_idx instead of sc_idx_hash. Wraps two bw_ram instances
// to support dual prediction slots (NUM_PRED_SLOTS=2). RAM0 -> slot 0,
// RAM1 -> slot 1. Selection is structural. ST0-ST3 use sc_table.
//
// Entry layout:
//   The SC entry is a single signed confidence counter of width
//   THIS_CTR_WIDTH. There is no tag, no USE, no EPC, no valid bit,
//   and no allocation. ALLOC_DATA_WIDTH == the counter width.
//
// Prediction pipeline: index applied at p2, counter out at p3
//   (bw_ram one-cycle read latency). Prediction is a RAM read only.
// Update: single counter write at upd_index_u0, gated by
//   sc_upd_val_u0 & ctr_wr_u0. Update is a RAM write only.
// Prediction and update phases are mutually exclusive by design;
//   no read-modify-write, no read-during-write forwarding.
// tbl_ri_active + tbl_ri_wr: RAM-init path overrides all writes.
//
// Index hash: get_br_imli_idx (planning/arch/sc_table_hash_rules.md,
//   sc_decisions.md section 12). Inputs are PC[15:6] (from
//   inp_pc_p2[s][15:6]), the low 10 path-history bits sc_phr_p2, the
//   BrIMLI counter br_imli, and the mode selector br_imli_mode:
//     f_idx = case(br_imli_mode)
//               IDX_IMLI_PHR : (br_imli==0) ? phr : br_imli
//               IDX_PHR_ONLY : phr
//               IDX_IMLI_ONLY: br_imli
//     index = pc ^ f_idx ^ (pc >> 4)
//   br_imli is an input port; the register lives in sc_cntrl. This
//   module does no BrIMLI register maintenance. No re-hash on update.
//
// ===================================================================

`ifndef SC_BRIMLI_SV
`define SC_BRIMLI_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module sc_brimli #(
  parameter  int THIS_TABLE      = 4,
  parameter  int THIS_INDEX_BITS = SC_TBL_IDX[4],
  parameter  int THIS_CTR_WIDTH  = SC_TBL_CTR[4],
  parameter  int THIS_ENTRIES    = SC_TBL_ENTRIES[4],
  parameter  int NUM_PRED_SLOTS  = bp_defines_pkg::NUM_PRED_SLOTS,
  // Derived - do not override
  // The SC entry holds the counter only; no tag/USE/EPC/valid.
  // CNTRL_BITS_WIDTH and ALLOC_DATA_WIDTH both equal the counter
  // width at the declared geometry (SC_MAX_*_WIDTH are 0 except CTR).
  localparam int CNTRL_BITS_WIDTH = SC_MAX_VAL_WIDTH
                                  + SC_MAX_CTR_WIDTH
                                  + SC_MAX_USE_WIDTH
                                  + SC_MAX_EPC_WIDTH,
  localparam int ALLOC_DATA_WIDTH = CNTRL_BITS_WIDTH
                                  + SC_MAX_TAG_WIDTH
) (
  // -- prediction outputs
  output logic [THIS_CTR_WIDTH-1:0]   ctr_p3[0:NUM_PRED_SLOTS-1],
  output logic [THIS_INDEX_BITS-1:0]  idx_hash_p2[0:NUM_PRED_SLOTS-1],
  // -- prediction inputs
  input  logic [NUM_PRED_SLOTS-1:0]   sc_pred_val_p2,
  input  logic [VA_WIDTH-1:1]         inp_pc_p2[0:NUM_PRED_SLOTS-1],
  input  logic [9:0]                  sc_phr_p2,
  input  logic [9:0]                  br_imli,
  input  br_imli_mode_e               br_imli_mode,
  // -- update inputs
  input  logic [NUM_PRED_SLOTS-1:0]   sc_upd_val_u0,
  input  logic [THIS_CTR_WIDTH-1:0]   ctr_wd_u0[0:NUM_PRED_SLOTS-1],
  input  logic [NUM_PRED_SLOTS-1:0]   ctr_wr_u0,
  input  logic [THIS_INDEX_BITS-1:0]  upd_index_u0[0:NUM_PRED_SLOTS-1],
  // -- RAM initialization (sram_init override path)
  input  logic                        tbl_ri_active,
  input  logic                        tbl_ri_wr,
  input  logic [THIS_INDEX_BITS-1:0]  tbl_ri_wa,
  input  logic [ALLOC_DATA_WIDTH-1:0] tbl_ri_wd,
  // -- clock and reset
  input  logic                        rstn,
  input  logic                        clk
);

  // Two banks per RAM; index MSB selects bank, lower bits the row.
  localparam int NUM_BANKS   = 2;
  localparam int RAM_ENTRIES = THIS_ENTRIES / NUM_BANKS;

  // BrIMLI index widths. The get_br_imli_idx operands are all 10 bits
  // (PC[15:6], sc_phr_p2[9:0], br_imli[9:0]); the resulting index is
  // THIS_INDEX_BITS wide (10 for ST4).
  localparam int BRIMLI_W = 10;

  // sc_pred_val_p2 is defined by the interface to enable the read.
  // bw_ram has no read enable; reads are harmless every cycle and the
  // prediction result is consumed downstream only when valid. The
  // port is retained for interface completeness.

  // ============================================================
  // Index hash (combinational, p2). get_br_imli_idx for ST4.
  //   pc    = inp_pc_p2[s][15:6]        (PC[15:6], 10 bits)
  //   phr   = sc_phr_p2                 (path history low 10 bits)
  //   f_idx = mode-selected IMLI/PHR contribution
  //   index = THIS_INDEX_BITS'(pc ^ f_idx ^ (pc >> 4))
  // Slot 0 and slot 1 are independent (separate pc inputs). br_imli
  // and br_imli_mode are shared inputs from sc_cntrl.
  // ============================================================
  logic [THIS_INDEX_BITS-1:0] idx_hash[0:NUM_PRED_SLOTS-1];

  always_comb begin : idx_hash_comb
    logic [BRIMLI_W-1:0] bpc;
    logic [BRIMLI_W-1:0] f_idx;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      // PC[15:6] is the get_br_imli_idx pc argument (not INST_OFFSET
      // shifted; the >>4 fold is applied below per the hash rule).
      bpc = inp_pc_p2[s][15:6];
      // Mode-selected fold. IDX_IMLI_PHR substitutes PHR when the
      // BrIMLI counter is cold (br_imli == 0); IDX_PHR_ONLY forces
      // PHR; IDX_IMLI_ONLY uses the raw counter with no substitution.
      case (br_imli_mode)
        IDX_IMLI_PHR:  f_idx = (br_imli == '0) ? sc_phr_p2 : br_imli;
        IDX_PHR_ONLY:  f_idx = sc_phr_p2;
        IDX_IMLI_ONLY: f_idx = br_imli;
        default:       f_idx = (br_imli == '0) ? sc_phr_p2 : br_imli;
      endcase
      idx_hash[s] = THIS_INDEX_BITS'(bpc ^ f_idx ^ (bpc >> 4));
    end
  end

  // Expose the index outputs (p2). Consumed by sc_cntrl to populate
  // sc_upd_idx[4] in the prediction meta.
  assign idx_hash_p2[0] = idx_hash[0];
  assign idx_hash_p2[1] = idx_hash[1];

  // Shared RAM-init write enable. Both slots see the same tbl_ri
  // signals. When active it overrides all normal write controls.
  logic ri_we;
  assign ri_we = tbl_ri_active & tbl_ri_wr;

  // Fast init: write bw_ram mem arrays at time zero via hierarchical
  // reference. Active only when +SC_FAST_INIT=1. bw_ram mem is 2D:
  // mem[BANKS][ENTRIES]. Loop covers both banks.
  initial begin
    int fast_init;
    fast_init = 0;
    void'($value$plusargs("SC_FAST_INIT=%d", fast_init));
    if (fast_init != 0) begin
      for (int b = 0; b < NUM_BANKS; b++) begin
        for (int i = 0; i < RAM_ENTRIES; i++) begin
          u_ram_s0.mem[b][i] = ALLOC_DATA_WIDTH'(SC_SRAM_INIT_VALUE);
          u_ram_s1.mem[b][i] = ALLOC_DATA_WIDTH'(SC_SRAM_INIT_VALUE);
        end
      end
    end
  end

  // ============================================================
  // Slot 0
  // ============================================================
  logic [THIS_INDEX_BITS-1:0]  ram_addr_s0;
  logic [ALLOC_DATA_WIDTH-1:0] ram_din_s0;
  logic [ALLOC_DATA_WIDTH-1:0] ram_bweb_n_s0;
  logic                        ram_wen_n_s0;
  logic [ALLOC_DATA_WIDTH-1:0] ram_dout_s0;
  logic                        ctr_we_s0;

  // Counter write enable: gated by update-valid and the counter
  // strobe. No table-select gate here -- ctr_wr_u0 is gated by
  // THIS_TABLE membership in sc_cntrl.
  assign ctr_we_s0 = sc_upd_val_u0[0] & ctr_wr_u0[0];
  assign ram_wen_n_s0 = ~(ctr_we_s0 | ri_we);

  always_comb begin : addr_mux_s0
    if (tbl_ri_active)
      ram_addr_s0 = tbl_ri_wa;         // init overrides all
    else if (ctr_we_s0)
      ram_addr_s0 = upd_index_u0[0];   // update write address
    else
      ram_addr_s0 = idx_hash[0];       // prediction read address
  end

  always_comb begin : din_mux_s0
    if (tbl_ri_active)
      ram_din_s0 = tbl_ri_wd;
    else
      ram_din_s0 = ALLOC_DATA_WIDTH'(ctr_wd_u0[0]);
  end

  // The SC entry is a whole-word counter; every write is full-word.
  // bweb_n all-zero enables all bits. wen_n controls whether the
  // write commits.
  assign ram_bweb_n_s0 = {ALLOC_DATA_WIDTH{1'b0}};

  bw_ram #(
    .ENTRIES(RAM_ENTRIES),
    .WIDTH  (ALLOC_DATA_WIDTH),
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

  // bw_ram read is one-cycle: address at p2, dout at p3.
  assign ctr_p3[0] = ram_dout_s0[THIS_CTR_WIDTH-1:0];

  // ============================================================
  // Slot 1
  // ============================================================
  logic [THIS_INDEX_BITS-1:0]  ram_addr_s1;
  logic [ALLOC_DATA_WIDTH-1:0] ram_din_s1;
  logic [ALLOC_DATA_WIDTH-1:0] ram_bweb_n_s1;
  logic                        ram_wen_n_s1;
  logic [ALLOC_DATA_WIDTH-1:0] ram_dout_s1;
  logic                        ctr_we_s1;

  assign ctr_we_s1 = sc_upd_val_u0[1] & ctr_wr_u0[1];
  assign ram_wen_n_s1 = ~(ctr_we_s1 | ri_we);

  always_comb begin : addr_mux_s1
    if (tbl_ri_active)
      ram_addr_s1 = tbl_ri_wa;
    else if (ctr_we_s1)
      ram_addr_s1 = upd_index_u0[1];
    else
      ram_addr_s1 = idx_hash[1];
  end

  always_comb begin : din_mux_s1
    if (tbl_ri_active)
      ram_din_s1 = tbl_ri_wd;
    else
      ram_din_s1 = ALLOC_DATA_WIDTH'(ctr_wd_u0[1]);
  end

  assign ram_bweb_n_s1 = {ALLOC_DATA_WIDTH{1'b0}};

  bw_ram #(
    .ENTRIES(RAM_ENTRIES),
    .WIDTH  (ALLOC_DATA_WIDTH),
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

  assign ctr_p3[1] = ram_dout_s1[THIS_CTR_WIDTH-1:0];

endmodule : sc_brimli

`endif // SC_BRIMLI_SV

`default_nettype wire
