// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tage_table.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Parameterized TAGE predictor table. Wraps one bw_ram instance per
// prediction slot, g_slot[s].u_ram for slot s (NUM_PRED_SLOTS, 1 or
// 2). Selection is structural.
// Instantiate once per TAGE table (T0-T4) with per-table params.
//
// Entry layout (bit 0 = LSB):
//   [0]                              = VALID
//   [THIS_CTR_WIDTH:1]               = CTR
//   [THIS_CTR_WIDTH+THIS_USE_WIDTH:
//    THIS_CTR_WIDTH+1]               = USE
//   [THIS_CTR_WIDTH+THIS_USE_WIDTH+
//    THIS_EPC_WIDTH:
//    THIS_CTR_WIDTH+THIS_USE_WIDTH+1]= EPC
//   [ALLOC_DATA_WIDTH-1:TAG_LSB]     = TAG
//
// Prediction pipeline: inputs at p0, outputs at p1 (1-cycle).
// Update: write-enable gated by THIS_TABLE vs prm/alt_tbl_sel.
// tbl_ri_active + tbl_ri_wr: RAM-init path overrides all writes.
//
// This requires manual verification checks
//
// ===================================================================

`ifndef TAGE_TABLE_SV
`define TAGE_TABLE_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tage_table #(
  parameter  int THIS_TABLE      = 0,
  parameter  int THIS_INDEX_BITS = 4,
  parameter  int THIS_TAG_BITS   = 4,
  parameter  int THIS_EPC_WIDTH  = 2,
  parameter  int THIS_USE_WIDTH  = 2,
  parameter  int THIS_CTR_WIDTH  = 3,
  parameter  int THIS_VAL_WIDTH  = 1,
  parameter  int TBL_SEL_WIDTH   = TAGE_TBL_SEL_WIDTH,
  // Derived - do not override
  // cntrl_bits_p1 width: VAL+CTR+USE+EPC at MAX widths.
  localparam int CNTRL_BITS_WIDTH = TAGE_MAX_EPC_WIDTH
                                  + TAGE_MAX_USE_WIDTH
                                  + TAGE_MAX_CTR_WIDTH
                                  + TAGE_MAX_VAL_WIDTH,
  // RAM entry: CNTRL_BITS fields + THIS_TAG_BITS.
  localparam int ALLOC_DATA_WIDTH = CNTRL_BITS_WIDTH
                                  + THIS_TAG_BITS
) (
  // -- prediction outputs
  output logic [NUM_PRED_SLOTS-1:0]   hit_p1,
  output logic [NUM_PRED_SLOTS-1:0]   taken_p1,
  output logic [CNTRL_BITS_WIDTH-1:0] cntrl_bits_p1[0:NUM_PRED_SLOTS-1],
  // -- hash outputs (p0, combinational; registered in tage_cntrl)
  output logic [THIS_INDEX_BITS-1:0] idx_hash_p0[0:NUM_PRED_SLOTS-1],
  output logic [TAGE_MAX_TAG_WIDTH-1:0] tag_hash_p0[0:NUM_PRED_SLOTS-1],
  // -- prediction inputs
  input  logic [NUM_PRED_SLOTS-1:0]   tage_pred_val_p0,
  input  tage_pred_inp_t              tage_pred_inp_p0[0:NUM_PRED_SLOTS-1],
  input  bp_folded_hist_t             folded_hist,      // NOT USED on T0
  // -- update enables
  input  logic [NUM_PRED_SLOTS-1:0]   tage_upd_val_u0,
  // -- update write data
  input  logic [THIS_CTR_WIDTH-1:0]   prm_ctr_wd_u0[0:NUM_PRED_SLOTS-1],
  input  logic [THIS_CTR_WIDTH-1:0]   alt_ctr_wd_u0[0:NUM_PRED_SLOTS-1],
  input  logic [THIS_USE_WIDTH-1:0]   use_wd_u0[0:NUM_PRED_SLOTS-1],
  input  logic [THIS_EPC_WIDTH-1:0]   epc_wd_u0[0:NUM_PRED_SLOTS-1],
  input  logic [ALLOC_DATA_WIDTH-1:0] alc_wd_u0[0:NUM_PRED_SLOTS-1],
  // -- update write strobes
  input  logic [NUM_PRED_SLOTS-1:0]   prm_ctr_wr_u0,
  input  logic [NUM_PRED_SLOTS-1:0]   alt_ctr_wr_u0,
  input  logic [NUM_PRED_SLOTS-1:0]   use_wr_u0,
  input  logic [NUM_PRED_SLOTS-1:0]   epc_wr_u0,
  input  logic [NUM_PRED_SLOTS-1:0]   alc_wr_u0,
  // -- table selectors (gate write enables)
  input  logic [TBL_SEL_WIDTH-1:0]    prm_tbl_sel_u0[0:NUM_PRED_SLOTS-1],
  input  logic [TBL_SEL_WIDTH-1:0]    alt_tbl_sel_u0[0:NUM_PRED_SLOTS-1],
  input  logic [TBL_SEL_WIDTH-1:0]    alc_tbl_sel_u0[0:NUM_PRED_SLOTS-1],
  // -- update address
  input  logic [THIS_INDEX_BITS-1:0]  upd_index_u0[0:NUM_PRED_SLOTS-1],
  input  logic [THIS_INDEX_BITS-1:0]  alc_index_u0[0:NUM_PRED_SLOTS-1],
  // -- RAM initialization
  input  logic                        tbl_ri_active,
  input  logic                        tbl_ri_wr,
  input  logic [THIS_INDEX_BITS-1:0]  tbl_ri_wa,
  input  logic [ALLOC_DATA_WIDTH-1:0] tbl_ri_wd,
  // -- clock and reset
  input  logic                        rstn,
  input  logic                        clk
);

  // Entry field LSB positions within ALLOC_DATA_WIDTH.
  localparam int VAL_LSB = 0;
  localparam int CTR_LSB = VAL_LSB + THIS_VAL_WIDTH;
  localparam int USE_LSB = CTR_LSB + THIS_CTR_WIDTH;
  localparam int EPC_LSB = USE_LSB + THIS_USE_WIDTH;
  localparam int TAG_LSB = EPC_LSB + THIS_EPC_WIDTH;
  localparam int CTR_MSB = CTR_LSB + THIS_CTR_WIDTH - 1;
  localparam int USE_MSB = USE_LSB + THIS_USE_WIDTH - 1;
  localparam int EPC_MSB = EPC_LSB + THIS_EPC_WIDTH - 1;
  localparam int TAG_MSB = TAG_LSB + THIS_TAG_BITS  - 1;

  localparam int RAM_DEPTH   = 1 << THIS_INDEX_BITS;
  localparam int NUM_BANKS   = 2;
  // RAM rows per bank: index MSB selects bank, lower bits select row.
  localparam int RAM_ENTRIES = RAM_DEPTH / NUM_BANKS;

  // ============================================================
  // Local index and tag hash (combinational, p0).
  // T0: index = pc[PC_HASH_SHIFT +: THIS_INDEX_BITS]. No tag.
  // T1-T4: index = (pc >> PC_HASH_SHIFT) ^ fh,
  //         lower THIS_INDEX_BITS.
  //         tag  = (pc >> THIS_INDEX_BITS) ^ fh1 ^ (fh2 << 1),
  //         lower THIS_TAG_BITS.
  // folded_hist is //NOT USED on T0 per interface convention.
  // The slots are independent (separate pc inputs).
  // ============================================================
  // The index hash shift is bp_defines_pkg::PC_HASH_SHIFT. It was a
  // hardcoded local of 2 here, shadowing the package and commented
  // "RISC-V: 4-byte insns" -- wrong under RVA23, which mandates C.
  // A change to the package value would silently have missed this
  // file. The local is removed; the package value is used.

  // Zero-extended folded history selected by THIS_TABLE.
  logic [VA_WIDTH-1:0] fh_idx_ext; // idx folded hist, extended
  logic [VA_WIDTH-1:0] fh1_ext;    // tag fh1, extended
  logic [VA_WIDTH-1:0] fh2_ext;    // tag fh2, extended

  // Locally derived prediction hashes.
  logic [THIS_INDEX_BITS-1:0]    idx_hash[0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_TAG_WIDTH-1:0] tag_hash[0:NUM_PRED_SLOTS-1];

  // Folded history field selection by THIS_TABLE.
  // T0: folded_hist NOT USED -- fields default to 0.
  always_comb begin : fh_sel
    fh_idx_ext = '0;
    fh1_ext    = '0;
    fh2_ext    = '0;
    case (THIS_TABLE)
      1: begin
        fh_idx_ext = VA_WIDTH'(folded_hist.tage_t1_idx_fh);
        fh1_ext    = VA_WIDTH'(folded_hist.tage_t1_tag_fh1);
        fh2_ext    = VA_WIDTH'(folded_hist.tage_t1_tag_fh2);
      end
      2: begin
        fh_idx_ext = VA_WIDTH'(folded_hist.tage_t2_idx_fh);
        fh1_ext    = VA_WIDTH'(folded_hist.tage_t2_tag_fh1);
        fh2_ext    = VA_WIDTH'(folded_hist.tage_t2_tag_fh2);
      end
      3: begin
        fh_idx_ext = VA_WIDTH'(folded_hist.tage_t3_idx_fh);
        fh1_ext    = VA_WIDTH'(folded_hist.tage_t3_tag_fh1);
        fh2_ext    = VA_WIDTH'(folded_hist.tage_t3_tag_fh2);
      end
      4: begin
        fh_idx_ext = VA_WIDTH'(folded_hist.tage_t4_idx_fh);
        fh1_ext    = VA_WIDTH'(folded_hist.tage_t4_tag_fh1);
        fh2_ext    = VA_WIDTH'(folded_hist.tage_t4_tag_fh2);
      end
      default: begin
        fh_idx_ext = '0;
        fh1_ext    = '0;
        fh2_ext    = '0;
      end
    endcase
  end

  // Constant table selector for this instance.
  localparam logic [TBL_SEL_WIDTH-1:0] THIS_TBL_SEL =
    TBL_SEL_WIDTH'(THIS_TABLE);

  // cntrl_bits_p1 output field boundary positions.
  // [0]=VAL, [CB_CTR_H:1]=CTR, [CB_USE_H:CB_CTR_H+1]=USE,
  // [CB_EPC_H:CB_USE_H+1]=EPC.
  localparam int CB_CTR_H = THIS_CTR_WIDTH;
  localparam int CB_USE_H = THIS_CTR_WIDTH + THIS_USE_WIDTH;
  localparam int CB_EPC_H = THIS_CTR_WIDTH
                          + THIS_USE_WIDTH
                          + THIS_EPC_WIDTH;

  // Shared RAM-init write enable. Every slot sees the same
  // tbl_ri signals.
  logic ri_we;
  assign ri_we = tbl_ri_active & tbl_ri_wr;

  // ============================================================
  // One hash, RAM and output set per slot (BP-128: the slot 0 and
  // slot 1 blocks were two copies; the loop follows NUM_PRED_SLOTS).
  // Slot s is g_slot[s]; its RAM g_slot[s].u_ram was u_ram_s0 /
  // u_ram_s1, and its enables g_slot[s].norm_we etc. were norm_we_s0
  // / norm_we_s1.
  // ============================================================
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_slot
    logic [THIS_INDEX_BITS-1:0]  ram_addr;
    logic [ALLOC_DATA_WIDTH-1:0] ram_din;
    logic [ALLOC_DATA_WIDTH-1:0] ram_bweb_n;
    logic                        ram_wen_n;
    logic [ALLOC_DATA_WIDTH-1:0] ram_dout;

    logic prm_match, alt_match, alc_match;
    logic prm_ctr_we, alt_ctr_we;
    logic use_we, epc_we, alc_we, norm_we;

    // p0 -> p1 registered tag hash.
    logic [TAGE_MAX_TAG_WIDTH-1:0] tag_hash_p1;

    // Index hash: T0 uses pc[PC_HASH_SHIFT +: THIS_INDEX_BITS].
    // T1-T4: (pc >> PC_HASH_SHIFT) ^ fh_idx_ext,
    //         truncated to THIS_INDEX_BITS.
    assign idx_hash[s] = (THIS_TABLE == 0)
      ? tage_pred_inp_p0[s].pc[PC_HASH_SHIFT +: THIS_INDEX_BITS]
      : THIS_INDEX_BITS'(
          (tage_pred_inp_p0[s].pc >> PC_HASH_SHIFT) ^ fh_idx_ext);

    // Tag hash: (pc >> THIS_INDEX_BITS) ^ fh1 ^ (fh2 << 1),
    // truncated to THIS_TAG_BITS, zero-extended to TAGE_MAX_TAG_WIDTH.
    assign tag_hash[s] = TAGE_MAX_TAG_WIDTH'(THIS_TAG_BITS'(
      (tage_pred_inp_p0[s].pc >> THIS_INDEX_BITS)
      ^ fh1_ext ^ (fh2_ext << 1)));

    // Expose hash outputs (combinational, p0).
    assign idx_hash_p0[s] = idx_hash[s];
    assign tag_hash_p0[s] = tag_hash[s];

    // Fast init: write the bw_ram mem array at time zero via
    // hierarchical reference. Active only when +TAGE_FAST_INIT=1.
    // bw_ram mem is 2D: mem[BANKS][ENTRIES]. Loop covers both banks.
    initial begin
      int fast_init;
      fast_init = 0;
      void'($value$plusargs("TAGE_FAST_INIT=%d", fast_init));
      if (fast_init != 0) begin
        for (int b = 0; b < NUM_BANKS; b++) begin
          for (int i = 0; i < RAM_ENTRIES; i++) begin
            u_ram.mem[b][i] =
              ALLOC_DATA_WIDTH'(TAGE_SRAM_INIT_VALUE);
          end
        end
      end
    end

    // All write-enables in one always_comb to avoid evaluation-order
    // ambiguity with cascaded assign statements in the simulator.
    // prm_match must be computed before use_we/epc_we.
    // (HAND-FIX-001 root cause corrected here.)
    always_comb begin : we
      prm_match  = (prm_tbl_sel_u0[s] == THIS_TBL_SEL);
      alt_match  = (alt_tbl_sel_u0[s] == THIS_TBL_SEL);
      // alc_match: table match AND not zero (no-alloc sentinel).
      alc_match  = (alc_tbl_sel_u0[s] == THIS_TBL_SEL)
                 & (alc_tbl_sel_u0[s] != '0);
      prm_ctr_we = tage_upd_val_u0[s]
                 & prm_ctr_wr_u0[s] & prm_match;
      alt_ctr_we = tage_upd_val_u0[s]
                 & alt_ctr_wr_u0[s] & alt_match;
      // USE/EPC: prm OR alt match (HAND-FIX-001 intent).
      use_we     = tage_upd_val_u0[s]
                 & use_wr_u0[s]
                 & (prm_match | alt_match);
      epc_we     = tage_upd_val_u0[s]
                 & epc_wr_u0[s]
                 & (prm_match | alt_match);
      alc_we     = tage_upd_val_u0[s]
                 & alc_wr_u0[s] & alc_match;
      norm_we    = prm_ctr_we | alt_ctr_we
                 | use_we | epc_we | alc_we;
    end

    assign ram_wen_n = ~(norm_we | ri_we);

    always_comb begin : addr_mux
      if (tbl_ri_active)
        ram_addr = tbl_ri_wa;
      else if (alc_we)
        ram_addr = alc_index_u0[s];
      else if (norm_we)
        ram_addr = upd_index_u0[s];
      else
        ram_addr = idx_hash[s];
    end

    always_comb begin : din_mux
      ram_din = {ALLOC_DATA_WIDTH{1'b0}};
      if (tbl_ri_active) begin
        ram_din = tbl_ri_wd;
      end else if (alc_we) begin
        ram_din = alc_wd_u0[s];
      end else begin
        // Independent per-field: any combination of enables is legal.
        if (prm_ctr_we)
          ram_din[CTR_MSB:CTR_LSB] = prm_ctr_wd_u0[s];
        else if (alt_ctr_we)
          ram_din[CTR_MSB:CTR_LSB] = alt_ctr_wd_u0[s];
        if (use_we)
          ram_din[USE_MSB:USE_LSB] = use_wd_u0[s];
        if (epc_we)
          ram_din[EPC_MSB:EPC_LSB] = epc_wd_u0[s];
      end
    end

    always_comb begin : bweb_mux
      ram_bweb_n = {ALLOC_DATA_WIDTH{1'b1}};
      if (ri_we || alc_we) begin
        ram_bweb_n = {ALLOC_DATA_WIDTH{1'b0}};
      end else begin
        if (prm_ctr_we || alt_ctr_we) begin
          for (int i = CTR_LSB; i <= CTR_MSB; i++)
            ram_bweb_n[i] = 1'b0;
        end
        if (use_we) begin
          for (int i = USE_LSB; i <= USE_MSB; i++)
            ram_bweb_n[i] = 1'b0;
        end
        if (epc_we) begin
          for (int i = EPC_LSB; i <= EPC_MSB; i++)
            ram_bweb_n[i] = 1'b0;
        end
      end
    end

    bw_ram #(
      .ENTRIES(RAM_ENTRIES),
      .WIDTH  (ALLOC_DATA_WIDTH),
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

    always_ff @(posedge clk) begin : tag_p1
      if (!rstn)
        tag_hash_p1 <= '0;
      else
        tag_hash_p1 <= tag_hash[s];
    end

    assign hit_p1[s] = ram_dout[VAL_LSB] &
        (ram_dout[TAG_MSB:TAG_LSB] ==
         tag_hash_p1[THIS_TAG_BITS-1:0]);

    assign taken_p1[s] = ram_dout[CTR_MSB];

    // cntrl_bits_p1[s]: VAL at [0], CTR at [CB_CTR_H:1],
    // USE at [CB_USE_H:CB_CTR_H+1], EPC at [CB_EPC_H:CB_USE_H+1].
    always_comb begin : cntrl_out
      cntrl_bits_p1[s] = {CNTRL_BITS_WIDTH{1'b0}};
      cntrl_bits_p1[s][0]              = ram_dout[VAL_LSB];
      cntrl_bits_p1[s][CB_CTR_H:1]     = ram_dout[CTR_MSB:CTR_LSB];
      cntrl_bits_p1[s][CB_USE_H:CB_CTR_H+1] =
          ram_dout[USE_MSB:USE_LSB];
      cntrl_bits_p1[s][CB_EPC_H:CB_USE_H+1] =
          ram_dout[EPC_MSB:EPC_LSB];
    end
  end

endmodule : tage_table

`endif // TAGE_TABLE_SV

`default_nettype wire
