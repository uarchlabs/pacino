// ===================================================================
// FILE:    ittage_cntrl.sv
// DATE:    2026-05-17
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// ITTAGE controller: prediction path (p0-p2). Update path stubbed.
// Testbench: BP-036.
// ===================================================================
`ifndef ITTAGE_CNTRL_SV
`define ITTAGE_CNTRL_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ittage_cntrl #(
  localparam int CNTRL_BITS_WIDTH =
    IT_MAX_VAL_WIDTH + IT_MAX_CTR_WIDTH
    + IT_MAX_USE_WIDTH + IT_MAX_EPC_WIDTH
    + IT_MAX_TGT_WIDTH,
  localparam int IT_MAX_ALLOC_DATA_WIDTH =
    CNTRL_BITS_WIDTH + IT_MAX_TAG_WIDTH
) (
  input  logic clk,
  input  logic rstn,
  // prediction inputs
  input  logic [NUM_PRED_SLOTS-1:0] ittage_pred_val_p0,
  input  ittage_pred_inp_t
    ittage_pred_inp_p0[0:NUM_PRED_SLOTS-1],
  // prediction outputs
  output logic [NUM_PRED_SLOTS-1:0] ittage_pred_rdy_p2,
  output ittage_pred_meta_t
    ittage_pred_meta_p2[0:NUM_PRED_SLOTS-1],
  // update inputs
  input  logic [NUM_PRED_SLOTS-1:0] ittage_upd_val_u0,
  input  ittage_upd_inp_t
    ittage_upd_inp_u0[0:NUM_PRED_SLOTS-1],
  // update output
  output logic [NUM_PRED_SLOTS-1:0] ittage_upd_rdy_u1,
  // aging control
  input  logic                      ittage_enable_aging,
  input  logic [31:0]               ittage_aging_interval,
  // per-table prediction inputs (index 0 unused)
  input  logic [NUM_PRED_SLOTS-1:0]
    tbl_hit_p1[0:IT_NUM_TABLES-1],
  input  logic [IT_MAX_TGT_WIDTH-1:0]
    tbl_pred_tgt_p1[0:IT_NUM_TABLES-1]
      [0:NUM_PRED_SLOTS-1],
  input  logic [CNTRL_BITS_WIDTH-1:0]
    tbl_cntrl_bits_p1[0:IT_NUM_TABLES-1]
      [0:NUM_PRED_SLOTS-1],
  input  logic [IT_MAX_IDX_WIDTH-1:0]
    tbl_idx_hash_p0[0:IT_NUM_TABLES-1]
      [0:NUM_PRED_SLOTS-1],
  input  logic [IT_MAX_TAG_WIDTH-1:0]
    tbl_tag_hash_p0[0:IT_NUM_TABLES-1]
      [0:NUM_PRED_SLOTS-1],
  // update write data (fanned to all tables by ittage.sv)
  output logic [IT_MAX_CTR_WIDTH-1:0]
    prm_ctr_wd_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_CTR_WIDTH-1:0]
    alt_ctr_wd_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_USE_WIDTH-1:0]
    use_wd_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_EPC_WIDTH-1:0]
    epc_wd_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_TGT_WIDTH-1:0]
    tgt_wd_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_ALLOC_DATA_WIDTH-1:0]
    alc_wd_u0[0:NUM_PRED_SLOTS-1],
  // update write strobes (fanned to all tables by ittage.sv)
  output logic [NUM_PRED_SLOTS-1:0] prm_ctr_wr_u0,
  output logic [NUM_PRED_SLOTS-1:0] alt_ctr_wr_u0,
  output logic [NUM_PRED_SLOTS-1:0] use_wr_u0,
  output logic [NUM_PRED_SLOTS-1:0] epc_wr_u0,
  output logic [NUM_PRED_SLOTS-1:0] tgt_wr_u0,
  output logic [NUM_PRED_SLOTS-1:0] alc_wr_u0,
  // update selectors and addresses (fanned by ittage.sv)
  output logic [IT_TBL_SEL_WIDTH-1:0]
    prm_tbl_sel_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_TBL_SEL_WIDTH-1:0]
    alt_tbl_sel_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_TBL_SEL_WIDTH-1:0]
    alc_tbl_sel_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_IDX_WIDTH-1:0]
    upd_index_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_IDX_WIDTH-1:0]
    alc_index_u0[0:NUM_PRED_SLOTS-1]
);

  // ================================================================
  // CB_* localparams: cntrl_bits field positions (match ittage_table)
  // VAL=[0], CTR=[3:1], USE=[5:4], EPC=[7:6], TGT=[45:8]
  // ================================================================
  localparam int CB_CTR_LO = 1;
  localparam int CB_CTR_HI = IT_MAX_CTR_WIDTH;
  localparam int CB_USE_LO = CB_CTR_HI + 1;
  localparam int CB_USE_HI = CB_CTR_HI + IT_MAX_USE_WIDTH;
  localparam int CB_EPC_LO = CB_USE_HI + 1;
  localparam int CB_EPC_HI = CB_USE_HI + IT_MAX_EPC_WIDTH;
  localparam int CB_TGT_LO = CB_EPC_HI + 1;
  localparam int CB_TGT_HI = CNTRL_BITS_WIDTH - 1;
  localparam int TSEL_W    = IT_TBL_SEL_WIDTH;

  // ================================================================
  // p0->p1 pipeline registers (Step 5)
  // ================================================================
  logic [IT_MAX_IDX_WIDTH-1:0]
    tbl_idx_p1[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_TAG_WIDTH-1:0]
    tbl_tag_p1[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] pred_val_p1;

  for (genvar t = 0; t < IT_NUM_TABLES; t++) begin : g_t
    for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_s
      always_ff @(posedge clk) begin : p0_to_p1
        if (!rstn) begin
          tbl_idx_p1[t][s] <= '0;
          tbl_tag_p1[t][s] <= '0;
        end else begin
          tbl_idx_p1[t][s] <= tbl_idx_hash_p0[t][s];
          tbl_tag_p1[t][s] <= tbl_tag_hash_p0[t][s];
        end
      end
    end
  end

  always_ff @(posedge clk) begin : pred_val_reg
    if (!rstn) pred_val_p1 <= '0;
    else       pred_val_p1 <= ittage_pred_val_p0;
  end

  // ================================================================
  // Provider and alternate provider scan signals (Step 6)
  // ================================================================
  logic [TSEL_W-1:0]           prm_comp[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_IDX_WIDTH-1:0] prm_idx[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_TGT_WIDTH-1:0] prm_tgt[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_USE_WIDTH-1:0] prm_use[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_CTR_WIDTH-1:0] prm_ctr[0:NUM_PRED_SLOTS-1];
  logic                        prm_hit[0:NUM_PRED_SLOTS-1];
  logic [TSEL_W-1:0]           alt_comp[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_IDX_WIDTH-1:0] alt_idx[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_TGT_WIDTH-1:0] alt_tgt[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_USE_WIDTH-1:0] alt_use[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_CTR_WIDTH-1:0] alt_ctr[0:NUM_PRED_SLOTS-1];

  // Allocation candidate signals (Step 7)
  logic [TSEL_W-1:0]           alc_comp[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_IDX_WIDTH-1:0] alc_idx[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_TAG_WIDTH-1:0] alc_tag[0:NUM_PRED_SLOTS-1];

  // ================================================================
  // Provider + alternate priority scan, one always_comb per slot.
  // Scan IT5->IT4->IT3->IT2->IT1 (longest history first).
  // No dynamic indexing per Verilator 5.020 guidance.
  // ================================================================
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_prv
    always_comb begin : prv_alt_scan
      prm_comp[s] = TSEL_W'(0);
      prm_idx[s]  = '0;
      prm_tgt[s]  = '0;
      prm_use[s]  = '0;
      prm_ctr[s]  = '0;
      prm_hit[s]  = 1'b0;
      alt_comp[s] = TSEL_W'(0);
      alt_idx[s]  = '0;
      alt_tgt[s]  = '0;
      alt_use[s]  = '0;
      alt_ctr[s]  = '0;
      if (tbl_hit_p1[5][s]) begin
        prm_comp[s] = TSEL_W'(5);
        prm_idx[s]  = tbl_idx_p1[5][s];
        prm_tgt[s]  = tbl_pred_tgt_p1[5][s];
        prm_use[s]  = tbl_cntrl_bits_p1[5][s][CB_USE_HI:CB_USE_LO];
        prm_ctr[s]  = tbl_cntrl_bits_p1[5][s][CB_CTR_HI:CB_CTR_LO];
        prm_hit[s]  = 1'b1;
        if (tbl_hit_p1[4][s]) begin
          alt_comp[s] = TSEL_W'(4);
          alt_idx[s]  = tbl_idx_p1[4][s];
          alt_tgt[s]  = tbl_pred_tgt_p1[4][s];
          alt_use[s]  =
            tbl_cntrl_bits_p1[4][s][CB_USE_HI:CB_USE_LO];
          alt_ctr[s]  =
            tbl_cntrl_bits_p1[4][s][CB_CTR_HI:CB_CTR_LO];
        end else if (tbl_hit_p1[3][s]) begin
          alt_comp[s] = TSEL_W'(3);
          alt_idx[s]  = tbl_idx_p1[3][s];
          alt_tgt[s]  = tbl_pred_tgt_p1[3][s];
          alt_use[s]  =
            tbl_cntrl_bits_p1[3][s][CB_USE_HI:CB_USE_LO];
          alt_ctr[s]  =
            tbl_cntrl_bits_p1[3][s][CB_CTR_HI:CB_CTR_LO];
        end else if (tbl_hit_p1[2][s]) begin
          alt_comp[s] = TSEL_W'(2);
          alt_idx[s]  = tbl_idx_p1[2][s];
          alt_tgt[s]  = tbl_pred_tgt_p1[2][s];
          alt_use[s]  =
            tbl_cntrl_bits_p1[2][s][CB_USE_HI:CB_USE_LO];
          alt_ctr[s]  =
            tbl_cntrl_bits_p1[2][s][CB_CTR_HI:CB_CTR_LO];
        end else if (tbl_hit_p1[1][s]) begin
          alt_comp[s] = TSEL_W'(1);
          alt_idx[s]  = tbl_idx_p1[1][s];
          alt_tgt[s]  = tbl_pred_tgt_p1[1][s];
          alt_use[s]  =
            tbl_cntrl_bits_p1[1][s][CB_USE_HI:CB_USE_LO];
          alt_ctr[s]  =
            tbl_cntrl_bits_p1[1][s][CB_CTR_HI:CB_CTR_LO];
        end
      end else if (tbl_hit_p1[4][s]) begin
        prm_comp[s] = TSEL_W'(4);
        prm_idx[s]  = tbl_idx_p1[4][s];
        prm_tgt[s]  = tbl_pred_tgt_p1[4][s];
        prm_use[s]  = tbl_cntrl_bits_p1[4][s][CB_USE_HI:CB_USE_LO];
        prm_ctr[s]  = tbl_cntrl_bits_p1[4][s][CB_CTR_HI:CB_CTR_LO];
        prm_hit[s]  = 1'b1;
        if (tbl_hit_p1[3][s]) begin
          alt_comp[s] = TSEL_W'(3);
          alt_idx[s]  = tbl_idx_p1[3][s];
          alt_tgt[s]  = tbl_pred_tgt_p1[3][s];
          alt_use[s]  =
            tbl_cntrl_bits_p1[3][s][CB_USE_HI:CB_USE_LO];
          alt_ctr[s]  =
            tbl_cntrl_bits_p1[3][s][CB_CTR_HI:CB_CTR_LO];
        end else if (tbl_hit_p1[2][s]) begin
          alt_comp[s] = TSEL_W'(2);
          alt_idx[s]  = tbl_idx_p1[2][s];
          alt_tgt[s]  = tbl_pred_tgt_p1[2][s];
          alt_use[s]  =
            tbl_cntrl_bits_p1[2][s][CB_USE_HI:CB_USE_LO];
          alt_ctr[s]  =
            tbl_cntrl_bits_p1[2][s][CB_CTR_HI:CB_CTR_LO];
        end else if (tbl_hit_p1[1][s]) begin
          alt_comp[s] = TSEL_W'(1);
          alt_idx[s]  = tbl_idx_p1[1][s];
          alt_tgt[s]  = tbl_pred_tgt_p1[1][s];
          alt_use[s]  =
            tbl_cntrl_bits_p1[1][s][CB_USE_HI:CB_USE_LO];
          alt_ctr[s]  =
            tbl_cntrl_bits_p1[1][s][CB_CTR_HI:CB_CTR_LO];
        end
      end else if (tbl_hit_p1[3][s]) begin
        prm_comp[s] = TSEL_W'(3);
        prm_idx[s]  = tbl_idx_p1[3][s];
        prm_tgt[s]  = tbl_pred_tgt_p1[3][s];
        prm_use[s]  = tbl_cntrl_bits_p1[3][s][CB_USE_HI:CB_USE_LO];
        prm_ctr[s]  = tbl_cntrl_bits_p1[3][s][CB_CTR_HI:CB_CTR_LO];
        prm_hit[s]  = 1'b1;
        if (tbl_hit_p1[2][s]) begin
          alt_comp[s] = TSEL_W'(2);
          alt_idx[s]  = tbl_idx_p1[2][s];
          alt_tgt[s]  = tbl_pred_tgt_p1[2][s];
          alt_use[s]  =
            tbl_cntrl_bits_p1[2][s][CB_USE_HI:CB_USE_LO];
          alt_ctr[s]  =
            tbl_cntrl_bits_p1[2][s][CB_CTR_HI:CB_CTR_LO];
        end else if (tbl_hit_p1[1][s]) begin
          alt_comp[s] = TSEL_W'(1);
          alt_idx[s]  = tbl_idx_p1[1][s];
          alt_tgt[s]  = tbl_pred_tgt_p1[1][s];
          alt_use[s]  =
            tbl_cntrl_bits_p1[1][s][CB_USE_HI:CB_USE_LO];
          alt_ctr[s]  =
            tbl_cntrl_bits_p1[1][s][CB_CTR_HI:CB_CTR_LO];
        end
      end else if (tbl_hit_p1[2][s]) begin
        prm_comp[s] = TSEL_W'(2);
        prm_idx[s]  = tbl_idx_p1[2][s];
        prm_tgt[s]  = tbl_pred_tgt_p1[2][s];
        prm_use[s]  = tbl_cntrl_bits_p1[2][s][CB_USE_HI:CB_USE_LO];
        prm_ctr[s]  = tbl_cntrl_bits_p1[2][s][CB_CTR_HI:CB_CTR_LO];
        prm_hit[s]  = 1'b1;
        if (tbl_hit_p1[1][s]) begin
          alt_comp[s] = TSEL_W'(1);
          alt_idx[s]  = tbl_idx_p1[1][s];
          alt_tgt[s]  = tbl_pred_tgt_p1[1][s];
          alt_use[s]  =
            tbl_cntrl_bits_p1[1][s][CB_USE_HI:CB_USE_LO];
          alt_ctr[s]  =
            tbl_cntrl_bits_p1[1][s][CB_CTR_HI:CB_CTR_LO];
        end
      end else if (tbl_hit_p1[1][s]) begin
        prm_comp[s] = TSEL_W'(1);
        prm_idx[s]  = tbl_idx_p1[1][s];
        prm_tgt[s]  = tbl_pred_tgt_p1[1][s];
        prm_use[s]  = tbl_cntrl_bits_p1[1][s][CB_USE_HI:CB_USE_LO];
        prm_ctr[s]  = tbl_cntrl_bits_p1[1][s][CB_CTR_HI:CB_CTR_LO];
        prm_hit[s]  = 1'b1;
        // primary is IT1: no alternate
      end
    end
  end

  // ================================================================
  // Allocation candidate selection (Step 7).
  // Scan IT(prm_comp+1)..IT5 for u_eff==0 (shortest-history first).
  // u_eff = raw USE field from cntrl_bits_p1 (stub, no aging adjust).
  // No consecutive-table allocation (single-entry selection inherently
  // satisfies this constraint).
  // alc_idx and alc_tag selected by case on alc_comp.
  // ================================================================
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_alc
    always_comb begin : alc_scan
      alc_comp[s] = TSEL_W'(0);
      if (prm_comp[s] == TSEL_W'(5)) begin
        // provider is IT5: no allocation
        alc_comp[s] = TSEL_W'(0);
      end else if (prm_comp[s] == TSEL_W'(4)) begin
        if (tbl_cntrl_bits_p1[5][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(5);
      end else if (prm_comp[s] == TSEL_W'(3)) begin
        if (tbl_cntrl_bits_p1[4][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(4);
        else if (tbl_cntrl_bits_p1[5][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(5);
      end else if (prm_comp[s] == TSEL_W'(2)) begin
        if (tbl_cntrl_bits_p1[3][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(3);
        else if (tbl_cntrl_bits_p1[4][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(4);
        else if (tbl_cntrl_bits_p1[5][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(5);
      end else if (prm_comp[s] == TSEL_W'(1)) begin
        // primary is IT1: scan IT2..IT5
        if (tbl_cntrl_bits_p1[2][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(2);
        else if (tbl_cntrl_bits_p1[3][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(3);
        else if (tbl_cntrl_bits_p1[4][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(4);
        else if (tbl_cntrl_bits_p1[5][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(5);
      end else begin
        // prm_comp==0 (no hit): scan IT1..IT5
        if (tbl_cntrl_bits_p1[1][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(1);
        else if (tbl_cntrl_bits_p1[2][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(2);
        else if (tbl_cntrl_bits_p1[3][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(3);
        else if (tbl_cntrl_bits_p1[4][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(4);
        else if (tbl_cntrl_bits_p1[5][s][CB_USE_HI:CB_USE_LO] == '0)
          alc_comp[s] = TSEL_W'(5);
      end
    end

    always_comb begin : alc_idx_tag
      alc_idx[s] = '0;
      alc_tag[s] = '0;
      case (alc_comp[s])
        TSEL_W'(1): begin
          alc_idx[s] = tbl_idx_p1[1][s];
          alc_tag[s] = tbl_tag_p1[1][s];
        end
        TSEL_W'(2): begin
          alc_idx[s] = tbl_idx_p1[2][s];
          alc_tag[s] = tbl_tag_p1[2][s];
        end
        TSEL_W'(3): begin
          alc_idx[s] = tbl_idx_p1[3][s];
          alc_tag[s] = tbl_tag_p1[3][s];
        end
        TSEL_W'(4): begin
          alc_idx[s] = tbl_idx_p1[4][s];
          alc_tag[s] = tbl_tag_p1[4][s];
        end
        TSEL_W'(5): begin
          alc_idx[s] = tbl_idx_p1[5][s];
          alc_tag[s] = tbl_tag_p1[5][s];
        end
        default: begin
          alc_idx[s] = '0;
          alc_tag[s] = '0;
        end
      endcase
    end
  end

  // ================================================================
  // UAON registers (Step 8): 4b saturating counters, one per slot.
  // Reset to IT_UAON_THRES. No update logic in BP-034.
  // ================================================================
  logic [IT_UAON_WIDTH-1:0] uaon[0:NUM_PRED_SLOTS-1];

  always_ff @(posedge clk) begin : uaon_reg
    if (!rstn) begin
      for (int i = 0; i < NUM_PRED_SLOTS; i++)
        uaon[i] <= IT_UAON_WIDTH'(IT_UAON_THRES);
    end
    // update logic added in BP-035
  end

  // UAON mux signals (Step 8)
  logic                        not_null[0:NUM_PRED_SLOTS-1];
  logic                        use_alt[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_TGT_WIDTH-1:0] final_tgt[0:NUM_PRED_SLOTS-1];
  logic [TSEL_W-1:0]           final_comp[0:NUM_PRED_SLOTS-1];
  logic                        using_prm[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_CTR_WIDTH-1:0] final_ctr[0:NUM_PRED_SLOTS-1];

  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_uaon
    always_comb begin : uaon_mux
      not_null[s] = (prm_ctr[s] != IT_MAX_CTR_WIDTH'(0));
      use_alt[s]  = !not_null[s]
                  & (uaon[s] >= IT_UAON_WIDTH'(IT_UAON_THRES))
                  & (alt_comp[s] != TSEL_W'(0));
      if (!prm_hit[s]) begin
        final_tgt[s]  = '0;
        final_comp[s] = TSEL_W'(0);
        using_prm[s]  = 1'b1;
        final_ctr[s]  = '0;
      end else if (use_alt[s]) begin
        final_tgt[s]  = alt_tgt[s];
        final_comp[s] = alt_comp[s];
        using_prm[s]  = 1'b0;
        final_ctr[s]  = alt_ctr[s];
      end else begin
        final_tgt[s]  = prm_tgt[s];
        final_comp[s] = prm_comp[s];
        using_prm[s]  = 1'b1;
        final_ctr[s]  = prm_ctr[s];
      end
    end
  end

  // ================================================================
  // Meta assembly (Step 9): combinational at p1
  // ittage_pred_strong = NOT NULL on the selected provider CTR.
  // ================================================================
  ittage_pred_meta_t meta_p1[0:NUM_PRED_SLOTS-1];

  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_meta
    always_comb begin : meta_asm
      meta_p1[s].ittage_prm_idx       = prm_idx[s];
      meta_p1[s].ittage_prm_comp      = prm_comp[s];
      meta_p1[s].ittage_prm_useful    = prm_use[s];
      meta_p1[s].ittage_prm_ctr       = prm_ctr[s];
      meta_p1[s].ittage_alt_idx       = alt_idx[s];
      meta_p1[s].ittage_alt_comp      = alt_comp[s];
      meta_p1[s].ittage_alt_useful    = alt_use[s];
      meta_p1[s].ittage_alt_ctr       = alt_ctr[s];
      meta_p1[s].ittage_alc_comp      = alc_comp[s];
      meta_p1[s].ittage_alc_idx       = alc_idx[s];
      meta_p1[s].ittage_alc_tag       = alc_tag[s];
      meta_p1[s].ittage_prm_tgt       = prm_tgt[s];
      meta_p1[s].ittage_alt_tgt       = alt_tgt[s];
      meta_p1[s].ittage_hit           = prm_hit[s];
      meta_p1[s].ittage_pred_strong   =
        (final_ctr[s] != IT_MAX_CTR_WIDTH'(0));
      meta_p1[s].ittage_use_alt_on_na = use_alt[s];
      meta_p1[s].ittage_using_primary = using_prm[s];
      meta_p1[s].branch_id =
        ittage_pred_inp_p0[s].branch_id;
    end
  end

  // ================================================================
  // p2 flop (Step 10)
  // ================================================================
  ittage_pred_meta_t          meta_p2_r[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]  rdy_p2_r;

  always_ff @(posedge clk) begin : meta_p2_reg
    if (!rstn) begin
      rdy_p2_r <= '0;
      for (int i = 0; i < NUM_PRED_SLOTS; i++)
        meta_p2_r[i] <= '0;
    end else begin
      rdy_p2_r <= pred_val_p1;
      for (int i = 0; i < NUM_PRED_SLOTS; i++)
        meta_p2_r[i] <= meta_p1[i];
    end
  end

  always_comb begin : meta_out
    ittage_pred_meta_p2 = meta_p2_r;
    ittage_pred_rdy_p2  = rdy_p2_r;
  end

  // ================================================================
  // Aging stubs (Step 11): reset only; decrement added in BP-035.
  // ================================================================
  logic [31:0] lcl_aging_interval[0:NUM_PRED_SLOTS-1];
  logic [1:0]  lcl_epoch[0:NUM_PRED_SLOTS-1];

  always_ff @(posedge clk) begin : aging_reg
    if (!rstn) begin
      for (int i = 0; i < NUM_PRED_SLOTS; i++) begin
        lcl_aging_interval[i] <= ittage_aging_interval;
        lcl_epoch[i]          <= 2'b00;
      end
    end
    // aging logic added in BP-035
  end

  // Touch ittage_enable_aging to prevent unused-signal warnings.
  logic age_en_nc;
  always_comb begin : aging_en_stub
    // aging logic added in BP-035
    age_en_nc = ittage_enable_aging;
  end

  // ================================================================
  // Update path stubs (Step 12). All write strobes tied 0.
  // Selectors and addresses driven from prediction-phase meta.
  // ================================================================
  assign ittage_upd_rdy_u1 = '0;
  assign prm_ctr_wr_u0     = '0;
  assign alt_ctr_wr_u0     = '0;
  assign use_wr_u0         = '0;
  assign epc_wr_u0         = '0;
  assign tgt_wr_u0         = '0;
  assign alc_wr_u0         = '0;

  always_comb begin : upd_data_stub
    for (int i = 0; i < NUM_PRED_SLOTS; i++) begin
      prm_ctr_wd_u0[i] = '0;
      alt_ctr_wd_u0[i] = '0;
      use_wd_u0[i]     = '0;
      epc_wd_u0[i]     = '0;
      tgt_wd_u0[i]     = '0;
      alc_wd_u0[i]     = '0;
    end
  end

  // Selectors/addresses from prediction phase (valid predict-time data)
  always_comb begin : upd_sel_assign
    for (int i = 0; i < NUM_PRED_SLOTS; i++) begin
      prm_tbl_sel_u0[i] = prm_comp[i];
      alt_tbl_sel_u0[i] = alt_comp[i];
      alc_tbl_sel_u0[i] = alc_comp[i];
      upd_index_u0[i]   = prm_idx[i];
      alc_index_u0[i]   = alc_idx[i];
    end
  end

  // Touch update inputs to prevent unused-signal warnings.
  logic upd_nc;
  always_comb begin : upd_inp_stub
    // update logic added in BP-035
    upd_nc = (|ittage_upd_val_u0)
           | ittage_upd_inp_u0[0].indir_mispredict
           | ittage_upd_inp_u0[1].indir_mispredict;
  end

endmodule : ittage_cntrl

`endif // ITTAGE_CNTRL_SV

`default_nettype wire
