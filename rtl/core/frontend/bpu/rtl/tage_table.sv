// ===================================================================
// FILE:    tage_table.sv
// DATE:    2026-04-03
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Parameterized TAGE predictor table. Wraps two bw_ram instances
// to support dual prediction slots (NUM_PRED_SLOTS=2).
// RAM0 -> slot 0, RAM1 -> slot 1. Selection is structural.
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
  parameter  int NUM_PRED_SLOTS  = 2,
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
  // T0: index = pc[INST_OFFSET +: THIS_INDEX_BITS]. No tag.
  // T1-T4: index = (pc >> INST_OFFSET) ^ fh,
  //         lower THIS_INDEX_BITS.
  //         tag  = (pc >> THIS_INDEX_BITS) ^ fh1 ^ (fh2 << 1),
  //         lower THIS_TAG_BITS.
  // folded_hist is //NOT USED on T0 per interface convention.
  // Slot 0 and slot 1 are independent (separate pc inputs).
  // ============================================================
  // Byte offset for instruction address (RISC-V: 4-byte insns).
  localparam int INST_OFFSET = 2;

  // Zero-extended folded history selected by THIS_TABLE.
  logic [VA_WIDTH-1:0] fh_idx_ext; // idx folded hist, extended
  logic [VA_WIDTH-1:0] fh1_ext;    // tag fh1, extended
  logic [VA_WIDTH-1:0] fh2_ext;    // tag fh2, extended

  // Locally derived prediction hashes.
  logic [THIS_INDEX_BITS-1:0] idx_hash[0:1]; // index per slot
  logic [TAGE_MAX_TAG_WIDTH-1:0]   tag_hash[0:1]; // tag per slot

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

  // Index hash: T0 uses pc[INST_OFFSET +: THIS_INDEX_BITS].
  // T1-T4: (pc >> INST_OFFSET) ^ fh_idx_ext,
  //         truncated to THIS_INDEX_BITS.
  assign idx_hash[0] = (THIS_TABLE == 0)
    ? tage_pred_inp_p0[0].pc[INST_OFFSET +: THIS_INDEX_BITS]
    : THIS_INDEX_BITS'(
        (tage_pred_inp_p0[0].pc >> INST_OFFSET) ^ fh_idx_ext);
  assign idx_hash[1] = (THIS_TABLE == 0)
    ? tage_pred_inp_p0[1].pc[INST_OFFSET +: THIS_INDEX_BITS]
    : THIS_INDEX_BITS'(
        (tage_pred_inp_p0[1].pc >> INST_OFFSET) ^ fh_idx_ext);

  // Tag hash: (pc >> THIS_INDEX_BITS) ^ fh1 ^ (fh2 << 1),
  // truncated to THIS_TAG_BITS, zero-extended to TAGE_MAX_TAG_WIDTH.
  assign tag_hash[0] = TAGE_MAX_TAG_WIDTH'(THIS_TAG_BITS'(
    (tage_pred_inp_p0[0].pc >> THIS_INDEX_BITS)
    ^ fh1_ext ^ (fh2_ext << 1)));
  assign tag_hash[1] = TAGE_MAX_TAG_WIDTH'(THIS_TAG_BITS'(
    (tage_pred_inp_p0[1].pc >> THIS_INDEX_BITS)
    ^ fh1_ext ^ (fh2_ext << 1)));

  // Expose hash outputs (combinational, p0).
  assign idx_hash_p0[0] = idx_hash[0];
  assign idx_hash_p0[1] = idx_hash[1];
  assign tag_hash_p0[0] = tag_hash[0];
  assign tag_hash_p0[1] = tag_hash[1];

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

  // p0 -> p1 registered tag hash (one per slot).
  logic [TAGE_MAX_TAG_WIDTH-1:0] tag_hash_p1[0:1];

  // Shared RAM-init write enable. Both slots see the same
  // tbl_ri signals.
  logic ri_we;
  assign ri_we = tbl_ri_active & tbl_ri_wr;

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
            ALLOC_DATA_WIDTH'(TAGE_SRAM_INIT_VALUE);
          u_ram_s1.mem[b][i] =
            ALLOC_DATA_WIDTH'(TAGE_SRAM_INIT_VALUE);
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

  logic prm_match_s0, alt_match_s0, alc_match_s0;
  logic prm_ctr_we_s0, alt_ctr_we_s0;
  logic use_we_s0, epc_we_s0, alc_we_s0, norm_we_s0;

  // All write-enables in one always_comb to avoid evaluation-order
  // ambiguity with cascaded assign statements in the simulator.
  // prm_match_s0 must be computed before use_we_s0/epc_we_s0.
  // (HAND-FIX-001 root cause corrected here.)
  always_comb begin : we_s0
    prm_match_s0  = (prm_tbl_sel_u0[0] == THIS_TBL_SEL);
    alt_match_s0  = (alt_tbl_sel_u0[0] == THIS_TBL_SEL);
    // alc_match: table match AND not zero (no-alloc sentinel).
    alc_match_s0  = (alc_tbl_sel_u0[0] == THIS_TBL_SEL)
                  & (alc_tbl_sel_u0[0] != '0);
    prm_ctr_we_s0 = tage_upd_val_u0[0]
                  & prm_ctr_wr_u0[0] & prm_match_s0;
    alt_ctr_we_s0 = tage_upd_val_u0[0]
                  & alt_ctr_wr_u0[0] & alt_match_s0;
    // USE/EPC: prm OR alt match (HAND-FIX-001 intent).
    use_we_s0     = tage_upd_val_u0[0]
                  & use_wr_u0[0]
                  & (prm_match_s0 | alt_match_s0);
    epc_we_s0     = tage_upd_val_u0[0]
                  & epc_wr_u0[0]
                  & (prm_match_s0 | alt_match_s0);
    alc_we_s0     = tage_upd_val_u0[0]
                  & alc_wr_u0[0] & alc_match_s0;
    norm_we_s0    = prm_ctr_we_s0 | alt_ctr_we_s0
                  | use_we_s0 | epc_we_s0 | alc_we_s0;
  end

  assign ram_wen_n_s0 = ~(norm_we_s0 | ri_we);


  always_comb begin : addr_mux_s0
    if (tbl_ri_active)
      ram_addr_s0 = tbl_ri_wa;
    else if (alc_we_s0)
      ram_addr_s0 = alc_index_u0[0];
    else if (norm_we_s0)
      ram_addr_s0 = upd_index_u0[0];
    else
      ram_addr_s0 = idx_hash[0];
  end

  always_comb begin : din_mux_s0
    ram_din_s0 = {ALLOC_DATA_WIDTH{1'b0}};
    if (tbl_ri_active) begin
      ram_din_s0 = tbl_ri_wd;
    end else if (alc_we_s0) begin
      ram_din_s0 = alc_wd_u0[0];
    end else begin
      // Independent per-field: any combination of enables is legal.
      if (prm_ctr_we_s0)
        ram_din_s0[CTR_MSB:CTR_LSB] = prm_ctr_wd_u0[0];
      else if (alt_ctr_we_s0)
        ram_din_s0[CTR_MSB:CTR_LSB] = alt_ctr_wd_u0[0];
      if (use_we_s0)
        ram_din_s0[USE_MSB:USE_LSB] = use_wd_u0[0];
      if (epc_we_s0)
        ram_din_s0[EPC_MSB:EPC_LSB] = epc_wd_u0[0];
    end
  end

  always_comb begin : bweb_mux_s0
    ram_bweb_n_s0 = {ALLOC_DATA_WIDTH{1'b1}};
    if (ri_we || alc_we_s0) begin
      ram_bweb_n_s0 = {ALLOC_DATA_WIDTH{1'b0}};
    end else begin
      if (prm_ctr_we_s0 || alt_ctr_we_s0) begin
        for (int i = CTR_LSB; i <= CTR_MSB; i++)
          ram_bweb_n_s0[i] = 1'b0;
      end
      if (use_we_s0) begin
        for (int i = USE_LSB; i <= USE_MSB; i++)
          ram_bweb_n_s0[i] = 1'b0;
      end
      if (epc_we_s0) begin
        for (int i = EPC_LSB; i <= EPC_MSB; i++)
          ram_bweb_n_s0[i] = 1'b0;
      end
    end
  end

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

  always_ff @(posedge clk) begin : tag_p1_s0
    if (!rstn)
      tag_hash_p1[0] <= '0;
    else
      tag_hash_p1[0] <= tag_hash[0];
  end

  assign hit_p1[0] = ram_dout_s0[VAL_LSB] &
      (ram_dout_s0[TAG_MSB:TAG_LSB] ==
       tag_hash_p1[0][THIS_TAG_BITS-1:0]);

  assign taken_p1[0] = ram_dout_s0[CTR_MSB];

  // cntrl_bits_p1[0]: VAL at [0], CTR at [CB_CTR_H:1],
  // USE at [CB_USE_H:CB_CTR_H+1], EPC at [CB_EPC_H:CB_USE_H+1].
  always_comb begin : cntrl_out_s0
    cntrl_bits_p1[0] = {CNTRL_BITS_WIDTH{1'b0}};
    cntrl_bits_p1[0][0]              = ram_dout_s0[VAL_LSB];
    cntrl_bits_p1[0][CB_CTR_H:1]     = ram_dout_s0[CTR_MSB:CTR_LSB];
    cntrl_bits_p1[0][CB_USE_H:CB_CTR_H+1] =
        ram_dout_s0[USE_MSB:USE_LSB];
    cntrl_bits_p1[0][CB_EPC_H:CB_USE_H+1] =
        ram_dout_s0[EPC_MSB:EPC_LSB];
  end

  // ============================================================
  // Slot 1
  // ============================================================
  logic [THIS_INDEX_BITS-1:0]  ram_addr_s1;
  logic [ALLOC_DATA_WIDTH-1:0] ram_din_s1;
  logic [ALLOC_DATA_WIDTH-1:0] ram_bweb_n_s1;
  logic                        ram_wen_n_s1;
  logic [ALLOC_DATA_WIDTH-1:0] ram_dout_s1;

  logic prm_match_s1, alt_match_s1, alc_match_s1;
  logic prm_ctr_we_s1, alt_ctr_we_s1;
  logic use_we_s1, epc_we_s1, alc_we_s1, norm_we_s1;

  // All write-enables in one always_comb (same fix as s0).
  always_comb begin : we_s1
    prm_match_s1  = (prm_tbl_sel_u0[1] == THIS_TBL_SEL);
    alt_match_s1  = (alt_tbl_sel_u0[1] == THIS_TBL_SEL);
    // alc_match: table match AND not zero (no-alloc sentinel).
    alc_match_s1  = (alc_tbl_sel_u0[1] == THIS_TBL_SEL)
                  & (alc_tbl_sel_u0[1] != '0);
    prm_ctr_we_s1 = tage_upd_val_u0[1]
                  & prm_ctr_wr_u0[1] & prm_match_s1;
    alt_ctr_we_s1 = tage_upd_val_u0[1]
                  & alt_ctr_wr_u0[1] & alt_match_s1;
    // USE/EPC: prm OR alt match (HAND-FIX-001 intent).
    use_we_s1     = tage_upd_val_u0[1]
                  & use_wr_u0[1]
                  & (prm_match_s1 | alt_match_s1);
    epc_we_s1     = tage_upd_val_u0[1]
                  & epc_wr_u0[1]
                  & (prm_match_s1 | alt_match_s1);
    alc_we_s1     = tage_upd_val_u0[1]
                  & alc_wr_u0[1] & alc_match_s1;
    norm_we_s1    = prm_ctr_we_s1 | alt_ctr_we_s1
                  | use_we_s1 | epc_we_s1 | alc_we_s1;
  end

  assign ram_wen_n_s1 = ~(norm_we_s1 | ri_we);

  always_comb begin : addr_mux_s1
    if (tbl_ri_active)
      ram_addr_s1 = tbl_ri_wa;
    else if (alc_we_s1)
      ram_addr_s1 = alc_index_u0[1];
    else if (norm_we_s1)
      ram_addr_s1 = upd_index_u0[1];
    else
      ram_addr_s1 = idx_hash[1];
  end

  always_comb begin : din_mux_s1
    ram_din_s1 = {ALLOC_DATA_WIDTH{1'b0}};
    if (tbl_ri_active) begin
      ram_din_s1 = tbl_ri_wd;
    end else if (alc_we_s1) begin
      ram_din_s1 = alc_wd_u0[1];
    end else begin
      // Independent per-field: any combination of enables is legal.
      if (prm_ctr_we_s1)
        ram_din_s1[CTR_MSB:CTR_LSB] = prm_ctr_wd_u0[1];
      else if (alt_ctr_we_s1)
        ram_din_s1[CTR_MSB:CTR_LSB] = alt_ctr_wd_u0[1];
      if (use_we_s1)
        ram_din_s1[USE_MSB:USE_LSB] = use_wd_u0[1];
      if (epc_we_s1)
        ram_din_s1[EPC_MSB:EPC_LSB] = epc_wd_u0[1];
    end
  end

  always_comb begin : bweb_mux_s1
    ram_bweb_n_s1 = {ALLOC_DATA_WIDTH{1'b1}};
    if (ri_we || alc_we_s1) begin
      ram_bweb_n_s1 = {ALLOC_DATA_WIDTH{1'b0}};
    end else begin
      if (prm_ctr_we_s1 || alt_ctr_we_s1) begin
        for (int i = CTR_LSB; i <= CTR_MSB; i++)
          ram_bweb_n_s1[i] = 1'b0;
      end
      if (use_we_s1) begin
        for (int i = USE_LSB; i <= USE_MSB; i++)
          ram_bweb_n_s1[i] = 1'b0;
      end
      if (epc_we_s1) begin
        for (int i = EPC_LSB; i <= EPC_MSB; i++)
          ram_bweb_n_s1[i] = 1'b0;
      end
    end
  end

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

  always_ff @(posedge clk) begin : tag_p1_s1
    if (!rstn)
      tag_hash_p1[1] <= '0;
    else
      tag_hash_p1[1] <= tag_hash[1];
  end

  assign hit_p1[1] = ram_dout_s1[VAL_LSB] &
      (ram_dout_s1[TAG_MSB:TAG_LSB] ==
       tag_hash_p1[1][THIS_TAG_BITS-1:0]);

  assign taken_p1[1] = ram_dout_s1[CTR_MSB];

  // cntrl_bits_p1[1]: VAL at [0], CTR at [CB_CTR_H:1],
  // USE at [CB_USE_H:CB_CTR_H+1], EPC at [CB_EPC_H:CB_USE_H+1].
  always_comb begin : cntrl_out_s1
    cntrl_bits_p1[1] = {CNTRL_BITS_WIDTH{1'b0}};
    cntrl_bits_p1[1][0]              = ram_dout_s1[VAL_LSB];
    cntrl_bits_p1[1][CB_CTR_H:1]     = ram_dout_s1[CTR_MSB:CTR_LSB];
    cntrl_bits_p1[1][CB_USE_H:CB_CTR_H+1] =
        ram_dout_s1[USE_MSB:USE_LSB];
    cntrl_bits_p1[1][CB_EPC_H:CB_USE_H+1] =
        ram_dout_s1[EPC_MSB:EPC_LSB];
  end

endmodule : tage_table

`endif // TAGE_TABLE_SV

`default_nettype wire
