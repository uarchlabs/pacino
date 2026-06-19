// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    ittage_cntrl.sv
// DATE:    2026-05-17
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// ITTAGE controller: prediction path (p0-p2) and update path.
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
  input  ittage_pred_inp_t          ittage_pred_inp_p0[0:NUM_PRED_SLOTS-1],
  // prediction outputs
  output logic [NUM_PRED_SLOTS-1:0] ittage_pred_rdy_p2,
  output ittage_pred_meta_t         ittage_pred_meta_p2[0:NUM_PRED_SLOTS-1],
  // update inputs
  input  logic [NUM_PRED_SLOTS-1:0] ittage_upd_val_u0,
  input  ittage_upd_inp_t           ittage_upd_inp_u0[0:NUM_PRED_SLOTS-1],
  // update output
  output logic [NUM_PRED_SLOTS-1:0] ittage_upd_rdy_u1,
  // aging control
  input  logic                      ittage_enable_aging,
  input  logic [31:0]               ittage_aging_interval,
  input  logic                      trx_type,
  // per-table prediction inputs (index 0 unused)
  input  logic [NUM_PRED_SLOTS-1:0]
    t_hit_p1[0:IT_NUM_TABLES-1],
  input  logic [IT_MAX_TGT_WIDTH-1:0]
    t_pred_tgt_p1[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  input  logic [CNTRL_BITS_WIDTH-1:0]
    t_cntrl_bits_p1[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  input  logic [IT_MAX_IDX_WIDTH-1:0]
    t_idx_hash_p0[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  input  logic [IT_MAX_TAG_WIDTH-1:0]
    t_tag_hash_p0[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1],
  // update write data (fanned to all tables by ittage.sv)
  output logic [IT_MAX_CTR_WIDTH-1:0] t_prm_ctr_wd_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_CTR_WIDTH-1:0] t_alt_ctr_wd_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_USE_WIDTH-1:0] t_use_wd_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_EPC_WIDTH-1:0] t_epc_wd_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_TGT_WIDTH-1:0] t_tgt_wd_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_ALLOC_DATA_WIDTH-1:0]
    t_alc_wd_u0[0:NUM_PRED_SLOTS-1],
  // update write strobes (fanned to all tables by ittage.sv)
  output logic [NUM_PRED_SLOTS-1:0]   t_prm_ctr_wr_u0,
  output logic [NUM_PRED_SLOTS-1:0]   t_alt_ctr_wr_u0,
  output logic [NUM_PRED_SLOTS-1:0]   t_use_wr_u0,
  output logic [NUM_PRED_SLOTS-1:0]   t_epc_wr_u0,
  output logic [NUM_PRED_SLOTS-1:0]   t_alc_wr_u0,
  // update selectors and addresses (fanned by ittage.sv)
  output logic [IT_TBL_SEL_WIDTH-1:0] t_prm_tbl_sel_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_TBL_SEL_WIDTH-1:0] t_alt_tbl_sel_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_TBL_SEL_WIDTH-1:0] t_alc_tbl_sel_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_IDX_WIDTH-1:0] t_prm_upd_index_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_IDX_WIDTH-1:0] t_alt_upd_index_u0[0:NUM_PRED_SLOTS-1],
  output logic [IT_MAX_IDX_WIDTH-1:0] t_alc_index_u0[0:NUM_PRED_SLOTS-1],
  // separate tgt write strobes: prm fires UP=1, alt fires UP=0
  output logic [NUM_PRED_SLOTS-1:0]   t_prm_tgt_wr_u0,
  output logic [NUM_PRED_SLOTS-1:0]   t_alt_tgt_wr_u0
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
  // p0->p1 pipeline registers
  // ================================================================
  logic [IT_MAX_IDX_WIDTH-1:0]
    tbl_idx_p1[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_TAG_WIDTH-1:0]
    tbl_tag_p1[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]   pred_val_p1;
  // branch_id registered p0->p1 so meta_p2_reg reads stable value.
  logic [FTQ_IDX_BITS-1:0]
    branch_id_p1[0:NUM_PRED_SLOTS-1];

  for (genvar t = 0; t < IT_NUM_TABLES; t++) begin : g_t
    for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_s
      always_ff @(posedge clk) begin : p0_to_p1
        if (!rstn) begin
          tbl_idx_p1[t][s] <= '0;
          tbl_tag_p1[t][s] <= '0;
        end else begin
          tbl_idx_p1[t][s] <= t_idx_hash_p0[t][s];
          tbl_tag_p1[t][s] <= t_tag_hash_p0[t][s];
        end
      end
    end
  end

  always_ff @(posedge clk) begin : pred_val_reg
    if (!rstn) begin
      pred_val_p1 <= '0;
      for (int i = 0; i < NUM_PRED_SLOTS; i++)
        branch_id_p1[i] <= '0;
    end else begin
      pred_val_p1 <= ittage_pred_val_p0;
      for (int i = 0; i < NUM_PRED_SLOTS; i++)
        branch_id_p1[i] <= ittage_pred_inp_p0[i].branch_id;
    end
  end

  // ================================================================
  // Provider and alternate provider scan signals
  // ================================================================
  logic [TSEL_W-1:0]           prm_comp[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_IDX_WIDTH-1:0] prm_idx[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_TGT_WIDTH-1:0] prm_tgt[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_CTR_WIDTH-1:0] prm_ctr[0:NUM_PRED_SLOTS-1];
  logic                        prm_hit[0:NUM_PRED_SLOTS-1];
  logic [TSEL_W-1:0]           alt_comp[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_IDX_WIDTH-1:0] alt_idx[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_TGT_WIDTH-1:0] alt_tgt[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_CTR_WIDTH-1:0] alt_ctr[0:NUM_PRED_SLOTS-1];

  // Allocation candidate signals
  logic [TSEL_W-1:0]           alc_comp[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_IDX_WIDTH-1:0] alc_idx[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_TAG_WIDTH-1:0] alc_tag[0:NUM_PRED_SLOTS-1];

  // Effective useful bits per table per slot (aging-adjusted)
  logic [IT_MAX_USE_WIDTH-1:0]
    u_eff[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  // u_eff muxed to primary and alternate providers
  logic [IT_MAX_USE_WIDTH-1:0] prm_u_eff[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_USE_WIDTH-1:0] alt_u_eff[0:NUM_PRED_SLOTS-1];

  // ================================================================
  // Provider + alternate priority scan, one always_comb per slot.
  // Scan IT5->IT4->IT3->IT2->IT1 (longest history first).
  // ================================================================
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_prv
    always_comb begin : prv_alt_scan
      prm_comp[s] = TSEL_W'(0);
      prm_idx[s]  = '0;
      prm_tgt[s]  = '0;
      prm_ctr[s]  = '0;
      prm_hit[s]  = 1'b0;
      alt_comp[s] = TSEL_W'(0);
      alt_idx[s]  = '0;
      alt_tgt[s]  = '0;
      alt_ctr[s]  = '0;
      // Gate on pred_val_p1[s] (FF output) so Verilator places this
      // block in the active evaluation region, not the settle region.
      if (pred_val_p1[s]) begin
      if (t_hit_p1[5][s]) begin
        prm_comp[s] = TSEL_W'(5);
        prm_idx[s]  = tbl_idx_p1[5][s];
        prm_tgt[s]  = t_pred_tgt_p1[5][s];
        prm_ctr[s]  = t_cntrl_bits_p1[5][s][CB_CTR_HI:CB_CTR_LO];
        prm_hit[s]  = 1'b1;
        if (t_hit_p1[4][s]) begin
          alt_comp[s] = TSEL_W'(4);
          alt_idx[s]  = tbl_idx_p1[4][s];
          alt_tgt[s]  = t_pred_tgt_p1[4][s];
          alt_ctr[s]  =
            t_cntrl_bits_p1[4][s][CB_CTR_HI:CB_CTR_LO];
        end else if (t_hit_p1[3][s]) begin
          alt_comp[s] = TSEL_W'(3);
          alt_idx[s]  = tbl_idx_p1[3][s];
          alt_tgt[s]  = t_pred_tgt_p1[3][s];
          alt_ctr[s]  =
            t_cntrl_bits_p1[3][s][CB_CTR_HI:CB_CTR_LO];
        end else if (t_hit_p1[2][s]) begin
          alt_comp[s] = TSEL_W'(2);
          alt_idx[s]  = tbl_idx_p1[2][s];
          alt_tgt[s]  = t_pred_tgt_p1[2][s];
          alt_ctr[s]  =
            t_cntrl_bits_p1[2][s][CB_CTR_HI:CB_CTR_LO];
        end else if (t_hit_p1[1][s]) begin
          alt_comp[s] = TSEL_W'(1);
          alt_idx[s]  = tbl_idx_p1[1][s];
          alt_tgt[s]  = t_pred_tgt_p1[1][s];
          alt_ctr[s]  =
            t_cntrl_bits_p1[1][s][CB_CTR_HI:CB_CTR_LO];
        end
      end else if (t_hit_p1[4][s]) begin
        prm_comp[s] = TSEL_W'(4);
        prm_idx[s]  = tbl_idx_p1[4][s];
        prm_tgt[s]  = t_pred_tgt_p1[4][s];
        prm_ctr[s]  = t_cntrl_bits_p1[4][s][CB_CTR_HI:CB_CTR_LO];
        prm_hit[s]  = 1'b1;
        if (t_hit_p1[3][s]) begin
          alt_comp[s] = TSEL_W'(3);
          alt_idx[s]  = tbl_idx_p1[3][s];
          alt_tgt[s]  = t_pred_tgt_p1[3][s];
          alt_ctr[s]  =
            t_cntrl_bits_p1[3][s][CB_CTR_HI:CB_CTR_LO];
        end else if (t_hit_p1[2][s]) begin
          alt_comp[s] = TSEL_W'(2);
          alt_idx[s]  = tbl_idx_p1[2][s];
          alt_tgt[s]  = t_pred_tgt_p1[2][s];
          alt_ctr[s]  =
            t_cntrl_bits_p1[2][s][CB_CTR_HI:CB_CTR_LO];
        end else if (t_hit_p1[1][s]) begin
          alt_comp[s] = TSEL_W'(1);
          alt_idx[s]  = tbl_idx_p1[1][s];
          alt_tgt[s]  = t_pred_tgt_p1[1][s];
          alt_ctr[s]  =
            t_cntrl_bits_p1[1][s][CB_CTR_HI:CB_CTR_LO];
        end
      end else if (t_hit_p1[3][s]) begin
        prm_comp[s] = TSEL_W'(3);
        prm_idx[s]  = tbl_idx_p1[3][s];
        prm_tgt[s]  = t_pred_tgt_p1[3][s];
        prm_ctr[s]  = t_cntrl_bits_p1[3][s][CB_CTR_HI:CB_CTR_LO];
        prm_hit[s]  = 1'b1;
        if (t_hit_p1[2][s]) begin
          alt_comp[s] = TSEL_W'(2);
          alt_idx[s]  = tbl_idx_p1[2][s];
          alt_tgt[s]  = t_pred_tgt_p1[2][s];
          alt_ctr[s]  =
            t_cntrl_bits_p1[2][s][CB_CTR_HI:CB_CTR_LO];
        end else if (t_hit_p1[1][s]) begin
          alt_comp[s] = TSEL_W'(1);
          alt_idx[s]  = tbl_idx_p1[1][s];
          alt_tgt[s]  = t_pred_tgt_p1[1][s];
          alt_ctr[s]  =
            t_cntrl_bits_p1[1][s][CB_CTR_HI:CB_CTR_LO];
        end
      end else if (t_hit_p1[2][s]) begin
        prm_comp[s] = TSEL_W'(2);
        prm_idx[s]  = tbl_idx_p1[2][s];
        prm_tgt[s]  = t_pred_tgt_p1[2][s];
        prm_ctr[s]  = t_cntrl_bits_p1[2][s][CB_CTR_HI:CB_CTR_LO];
        prm_hit[s]  = 1'b1;
        if (t_hit_p1[1][s]) begin
          alt_comp[s] = TSEL_W'(1);
          alt_idx[s]  = tbl_idx_p1[1][s];
          alt_tgt[s]  = t_pred_tgt_p1[1][s];
          alt_ctr[s]  =
            t_cntrl_bits_p1[1][s][CB_CTR_HI:CB_CTR_LO];
        end
      end else if (t_hit_p1[1][s]) begin
        prm_comp[s] = TSEL_W'(1);
        prm_idx[s]  = tbl_idx_p1[1][s];
        prm_tgt[s]  = t_pred_tgt_p1[1][s];
        prm_ctr[s]  = t_cntrl_bits_p1[1][s][CB_CTR_HI:CB_CTR_LO];
        prm_hit[s]  = 1'b1;
        // primary is IT1: no alternate
      end
      end // if (pred_val_p1[s])
    end
  end

  // ================================================================
  // u_eff computation: effective useful per table per slot.
  // age = (lcl_epoch[s] - EPC) mod 4 (2b wrapping subtraction).
  // age==0 -> u_eff = USE; age==1 -> u_eff = USE>>1; else 0.
  // Explicit if-else per table index; no dynamic array indexing.
  // ================================================================
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_u_eff
    always_comb begin : u_eff_cmp
      u_eff[0][s] = '0;
      // IT1
      if ((lcl_epoch[s] -
           t_cntrl_bits_p1[1][s][CB_EPC_HI:CB_EPC_LO]) == 2'b00)
        u_eff[1][s] = t_cntrl_bits_p1[1][s][CB_USE_HI:CB_USE_LO];
      else if ((lcl_epoch[s] -
                t_cntrl_bits_p1[1][s][CB_EPC_HI:CB_EPC_LO])
               == 2'b01)
        u_eff[1][s] =
          IT_MAX_USE_WIDTH'(
            t_cntrl_bits_p1[1][s][CB_USE_HI:CB_USE_LO] >> 1);
      else
        u_eff[1][s] = '0;
      // IT2
      if ((lcl_epoch[s] -
           t_cntrl_bits_p1[2][s][CB_EPC_HI:CB_EPC_LO]) == 2'b00)
        u_eff[2][s] = t_cntrl_bits_p1[2][s][CB_USE_HI:CB_USE_LO];
      else if ((lcl_epoch[s] -
                t_cntrl_bits_p1[2][s][CB_EPC_HI:CB_EPC_LO])
               == 2'b01)
        u_eff[2][s] =
          IT_MAX_USE_WIDTH'(
            t_cntrl_bits_p1[2][s][CB_USE_HI:CB_USE_LO] >> 1);
      else
        u_eff[2][s] = '0;
      // IT3
      if ((lcl_epoch[s] -
           t_cntrl_bits_p1[3][s][CB_EPC_HI:CB_EPC_LO]) == 2'b00)
        u_eff[3][s] = t_cntrl_bits_p1[3][s][CB_USE_HI:CB_USE_LO];
      else if ((lcl_epoch[s] -
                t_cntrl_bits_p1[3][s][CB_EPC_HI:CB_EPC_LO])
               == 2'b01)
        u_eff[3][s] =
          IT_MAX_USE_WIDTH'(
            t_cntrl_bits_p1[3][s][CB_USE_HI:CB_USE_LO] >> 1);
      else
        u_eff[3][s] = '0;
      // IT4
      if ((lcl_epoch[s] -
           t_cntrl_bits_p1[4][s][CB_EPC_HI:CB_EPC_LO]) == 2'b00)
        u_eff[4][s] = t_cntrl_bits_p1[4][s][CB_USE_HI:CB_USE_LO];
      else if ((lcl_epoch[s] -
                t_cntrl_bits_p1[4][s][CB_EPC_HI:CB_EPC_LO])
               == 2'b01)
        u_eff[4][s] =
          IT_MAX_USE_WIDTH'(
            t_cntrl_bits_p1[4][s][CB_USE_HI:CB_USE_LO] >> 1);
      else
        u_eff[4][s] = '0;
      // IT5
      if ((lcl_epoch[s] -
           t_cntrl_bits_p1[5][s][CB_EPC_HI:CB_EPC_LO]) == 2'b00)
        u_eff[5][s] = t_cntrl_bits_p1[5][s][CB_USE_HI:CB_USE_LO];
      else if ((lcl_epoch[s] -
                t_cntrl_bits_p1[5][s][CB_EPC_HI:CB_EPC_LO])
               == 2'b01)
        u_eff[5][s] =
          IT_MAX_USE_WIDTH'(
            t_cntrl_bits_p1[5][s][CB_USE_HI:CB_USE_LO] >> 1);
      else
        u_eff[5][s] = '0;
    end
  end

  // u_eff muxed to primary provider table
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_prm_u_eff
    always_comb begin : prm_u_eff_mux
      prm_u_eff[s] = '0;
      case (prm_comp[s])
        TSEL_W'(5): prm_u_eff[s] = u_eff[5][s];
        TSEL_W'(4): prm_u_eff[s] = u_eff[4][s];
        TSEL_W'(3): prm_u_eff[s] = u_eff[3][s];
        TSEL_W'(2): prm_u_eff[s] = u_eff[2][s];
        TSEL_W'(1): prm_u_eff[s] = u_eff[1][s];
        default:    prm_u_eff[s] = '0;
      endcase
    end
  end

  // u_eff muxed to alternate provider table
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_alt_u_eff
    always_comb begin : alt_u_eff_mux
      alt_u_eff[s] = '0;
      case (alt_comp[s])
        TSEL_W'(5): alt_u_eff[s] = u_eff[5][s];
        TSEL_W'(4): alt_u_eff[s] = u_eff[4][s];
        TSEL_W'(3): alt_u_eff[s] = u_eff[3][s];
        TSEL_W'(2): alt_u_eff[s] = u_eff[2][s];
        TSEL_W'(1): alt_u_eff[s] = u_eff[1][s];
        default:    alt_u_eff[s] = '0;
      endcase
    end
  end

  // ================================================================
  // Allocation candidate selection.
  // Scan IT(prm_comp+1)..IT5 for u_eff==0 (shortest-history first).
  // No consecutive-table allocation.
  // ================================================================
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_alc
    always_comb begin : alc_scan
      alc_comp[s] = TSEL_W'(0);
      if (prm_comp[s] == TSEL_W'(5)) begin
        alc_comp[s] = TSEL_W'(0);
      end else if (prm_comp[s] == TSEL_W'(4)) begin
        if (u_eff[5][s] == '0) alc_comp[s] = TSEL_W'(5);
      end else if (prm_comp[s] == TSEL_W'(3)) begin
        if      (u_eff[4][s] == '0) alc_comp[s] = TSEL_W'(4);
        else if (u_eff[5][s] == '0) alc_comp[s] = TSEL_W'(5);
      end else if (prm_comp[s] == TSEL_W'(2)) begin
        if      (u_eff[3][s] == '0) alc_comp[s] = TSEL_W'(3);
        else if (u_eff[4][s] == '0) alc_comp[s] = TSEL_W'(4);
        else if (u_eff[5][s] == '0) alc_comp[s] = TSEL_W'(5);
      end else if (prm_comp[s] == TSEL_W'(1)) begin
        if      (u_eff[2][s] == '0) alc_comp[s] = TSEL_W'(2);
        else if (u_eff[3][s] == '0) alc_comp[s] = TSEL_W'(3);
        else if (u_eff[4][s] == '0) alc_comp[s] = TSEL_W'(4);
        else if (u_eff[5][s] == '0) alc_comp[s] = TSEL_W'(5);
      end else begin
        // prm_comp==0 (no hit): scan IT1..IT5
        if      (u_eff[1][s] == '0) alc_comp[s] = TSEL_W'(1);
        else if (u_eff[2][s] == '0) alc_comp[s] = TSEL_W'(2);
        else if (u_eff[3][s] == '0) alc_comp[s] = TSEL_W'(3);
        else if (u_eff[4][s] == '0) alc_comp[s] = TSEL_W'(4);
        else if (u_eff[5][s] == '0) alc_comp[s] = TSEL_W'(5);
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
  // UAON registers: 4b saturating counters, one per slot.
  // Reset to IT_UAON_THRES.
  // Update: gate on upd_val and ittage_hit; skip when pred_strong.
  // ================================================================
  logic [IT_UAON_WIDTH-1:0] uaon[0:NUM_PRED_SLOTS-1];

  always_ff @(posedge clk) begin : uaon_reg
    if (!rstn) begin
      for (int i = 0; i < NUM_PRED_SLOTS; i++)
        uaon[i] <= IT_UAON_WIDTH'(IT_UAON_THRES);
    end else begin
      for (int i = 0; i < NUM_PRED_SLOTS; i++) begin
        // guard: comp==0 is the no-component sentinel (single hit)
        if (ittage_upd_val_u0[i]
            && ittage_upd_inp_u0[i].ittage_pred_meta.ittage_hit
            && !ittage_upd_inp_u0[i].ittage_pred_meta.ittage_pred_strong
            && (ittage_upd_inp_u0[i].ittage_pred_meta.ittage_prm_comp
                != TSEL_W'(0))
            && (ittage_upd_inp_u0[i].ittage_pred_meta.ittage_alt_comp
                != TSEL_W'(0)))
        begin
          // prm_wrong && alt_correct -> INC
          if ((ittage_upd_inp_u0[i].resolved_target
               != ittage_upd_inp_u0[i].ittage_pred_meta.ittage_prm_tgt)
              && (ittage_upd_inp_u0[i].resolved_target
                  == ittage_upd_inp_u0[i].ittage_pred_meta.ittage_alt_tgt))
          begin
            if (uaon[i] != {IT_UAON_WIDTH{1'b1}})
              uaon[i] <= uaon[i] + IT_UAON_WIDTH'(1);
          // prm_correct && alt_wrong -> DEC
          end else if ((ittage_upd_inp_u0[i].resolved_target
                        == ittage_upd_inp_u0[i]
                           .ittage_pred_meta.ittage_prm_tgt)
                       && (ittage_upd_inp_u0[i].resolved_target
                           != ittage_upd_inp_u0[i]
                              .ittage_pred_meta.ittage_alt_tgt))
          begin
            if (uaon[i] != IT_UAON_WIDTH'(0))
              uaon[i] <= uaon[i] - IT_UAON_WIDTH'(1);
          end
        end
      end
    end
  end

  // UAON mux signals
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
  // p2 flop: directly capture scan outputs into meta_p2_r.
  // No meta_p1 intermediate. Verilator's nba_sequent dependency
  // DAG must schedule prv_alt_scan before this capture because
  // meta_p2_r reads prm_hit, prm_comp, etc. directly.
  // ================================================================
  ittage_pred_meta_t         meta_p2_r[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] rdy_p2_r;

  always_ff @(posedge clk) begin : meta_p2_reg
    if (!rstn) begin
      rdy_p2_r <= '0;
      for (int i = 0; i < NUM_PRED_SLOTS; i++)
        meta_p2_r[i] <= '0;
    end else begin
      rdy_p2_r <= pred_val_p1;
      for (int i = 0; i < NUM_PRED_SLOTS; i++) begin
        meta_p2_r[i] <= '0;
        if (pred_val_p1[i]) begin
          meta_p2_r[i].ittage_prm_idx       <= prm_idx[i];
          meta_p2_r[i].ittage_prm_comp      <= prm_comp[i];
          meta_p2_r[i].ittage_prm_useful    <= prm_u_eff[i];
          meta_p2_r[i].ittage_prm_ctr       <= prm_ctr[i];
          meta_p2_r[i].ittage_alt_idx       <= alt_idx[i];
          meta_p2_r[i].ittage_alt_comp      <= alt_comp[i];
          meta_p2_r[i].ittage_alt_useful    <= alt_u_eff[i];
          meta_p2_r[i].ittage_alt_ctr       <= alt_ctr[i];
          meta_p2_r[i].ittage_alc_comp      <= alc_comp[i];
          meta_p2_r[i].ittage_alc_idx       <= alc_idx[i];
          meta_p2_r[i].ittage_alc_tag       <= alc_tag[i];
          meta_p2_r[i].ittage_prm_tgt       <= prm_tgt[i];
          meta_p2_r[i].ittage_alt_tgt       <= alt_tgt[i];
          meta_p2_r[i].ittage_hit           <= prm_hit[i];
          meta_p2_r[i].ittage_pred_strong   <=
            (final_ctr[i] != IT_MAX_CTR_WIDTH'(0));
          meta_p2_r[i].ittage_use_alt_on_na <= use_alt[i];
          meta_p2_r[i].ittage_using_primary <= using_prm[i];
          meta_p2_r[i].branch_id <= branch_id_p1[i];
        end
      end
    end
  end

  always_comb begin : meta_out
    ittage_pred_meta_p2 = meta_p2_r;
    ittage_pred_rdy_p2  = trx_type ? '0 : rdy_p2_r;
  end

  // ================================================================
  // Aging interval and epoch registers, one per slot.
  // Decrement lcl_aging_interval on each assertion of rdy_p2_r[s].
  // On reaching zero: increment lcl_epoch (2b wrap), reload interval.
  // Only active when ittage_enable_aging is asserted.
  // ================================================================
  logic [31:0] lcl_aging_interval[0:NUM_PRED_SLOTS-1];
  logic [1:0]  lcl_epoch[0:NUM_PRED_SLOTS-1];

  always_ff @(posedge clk) begin : aging_reg
    if (!rstn) begin
      for (int i = 0; i < NUM_PRED_SLOTS; i++) begin
        lcl_aging_interval[i] <= ittage_aging_interval;
        lcl_epoch[i]          <= 2'b00;
      end
    end else if (ittage_enable_aging) begin
      for (int i = 0; i < NUM_PRED_SLOTS; i++) begin
        if (rdy_p2_r[i]) begin
          if (lcl_aging_interval[i] == 32'b0) begin
            lcl_epoch[i]          <= lcl_epoch[i] + 2'b01;
            lcl_aging_interval[i] <= ittage_aging_interval;
          end else begin
            lcl_aging_interval[i] <=
              lcl_aging_interval[i] - 32'b1;
          end
        end
      end
    end
  end

  // ================================================================
  // Update path: upd_rdy registered one cycle from upd_val.
  // ================================================================
  always_ff @(posedge clk) begin : upd_rdy_reg
    if (!rstn) ittage_upd_rdy_u1 <= '0;
    else       ittage_upd_rdy_u1 <= ittage_upd_val_u0;
  end

  // ================================================================
  // Update selectors and addresses.
  // t_prm_tbl_sel_u0/t_alt_tbl_sel_u0: from update input meta.
  // t_alc_tbl_sel_u0: from update input meta alc_comp.
  // t_prm_upd_index_u0: primary provider index from meta.
  // t_alt_upd_index_u0: alternate provider index from meta.
  // t_alc_index_u0: allocation RAM index, sourced from
  // ittage_alc_idx in meta (pre-hashed at predict time per
  // ittage_cntrl_alloc_rules.md). Not the prm update index.
  // Gate on ittage_upd_val_u0[s] (read by always_ff) so Verilator
  // places this block in the active evaluation region.
  // ================================================================
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_upd_sel
    always_comb begin : upd_sel
      t_prm_tbl_sel_u0[s]   = '0;
      t_alt_tbl_sel_u0[s]   = '0;
      t_alc_tbl_sel_u0[s]   = '0;
      t_prm_upd_index_u0[s] = '0;
      t_alt_upd_index_u0[s] = '0;
      t_alc_index_u0[s]     = '0;
      if (ittage_upd_val_u0[s]) begin
        t_prm_tbl_sel_u0[s] = TSEL_W'(
          ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_comp);
        t_alt_tbl_sel_u0[s] = TSEL_W'(
          ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_comp);
        t_alc_tbl_sel_u0[s] = TSEL_W'(
          ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alc_comp);
        t_prm_upd_index_u0[s] =
          ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_idx;
        t_alt_upd_index_u0[s] =
          ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_idx;
        t_alc_index_u0[s] =
          ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alc_idx;
      end
    end
  end


  // ================================================================
  // CTR update logic (per slot).
  // H gates all rows: when H=0 no CTR write (rule doc row 1).
  // When using_primary: update prm CTR (rows 18-33 of CTR table).
  // When !using_primary: update alt CTR (rows 2-17 of CTR table).
  // Saturating inc/dec per BD7.
  // ================================================================
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_ctr_upd
    always_comb begin : ctr_upd
      t_prm_ctr_wr_u0[s]  = 1'b0;
      t_alt_ctr_wr_u0[s]  = 1'b0;
      t_prm_ctr_wd_u0[s]  = '0;
      t_alt_ctr_wd_u0[s]  = '0;
      if (ittage_upd_val_u0[s]
          && ittage_upd_inp_u0[s].ittage_pred_meta.ittage_hit)
      begin
        if (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_using_primary)
        begin
          // prm CTR update: provider was primary (rows 18-33)
          if (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_comp
              != TSEL_W'(0))
          begin
            t_prm_ctr_wr_u0[s] = 1'b1;
            if (!ittage_upd_inp_u0[s].indir_mispredict) begin
              // INC saturating
              t_prm_ctr_wd_u0[s] =
                (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_ctr
                 == {IT_MAX_CTR_WIDTH{1'b1}})
                ? ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_ctr
                : IT_MAX_CTR_WIDTH'(
                    ittage_upd_inp_u0[s]
                      .ittage_pred_meta.ittage_prm_ctr + 1'b1);
            end else begin
              // DEC saturating
              t_prm_ctr_wd_u0[s] =
                (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_ctr
                 == IT_MAX_CTR_WIDTH'(0))
                ? ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_ctr
                : IT_MAX_CTR_WIDTH'(
                    ittage_upd_inp_u0[s]
                      .ittage_pred_meta.ittage_prm_ctr - 1'b1);
            end
          end
        end else begin
          // alt CTR update: provider was alternate (rows 2-17)
          if (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_comp
              != TSEL_W'(0))
          begin
            t_alt_ctr_wr_u0[s] = 1'b1;
            if (!ittage_upd_inp_u0[s].indir_mispredict) begin
              // INC saturating
              t_alt_ctr_wd_u0[s] =
                (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_ctr
                 == {IT_MAX_CTR_WIDTH{1'b1}})
                ? ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_ctr
                : IT_MAX_CTR_WIDTH'(
                    ittage_upd_inp_u0[s]
                      .ittage_pred_meta.ittage_alt_ctr + 1'b1);
            end else begin
              // DEC saturating
              t_alt_ctr_wd_u0[s] =
                (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_ctr
                 == IT_MAX_CTR_WIDTH'(0))
                ? ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_ctr
                : IT_MAX_CTR_WIDTH'(
                    ittage_upd_inp_u0[s]
                      .ittage_pred_meta.ittage_alt_ctr - 1'b1);
            end
          end
        end
      end
    end
  end

  // ================================================================
  // USE and EPC update logic (per slot). Table 7.
  // TD = prm_tgt != alt_tgt. NTH = !ittage_hit.
  // EPC always written when USE is written (lcl_epoch[s]).
  // Saturating inc/dec per BD8.
  // ================================================================
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_use_upd
    always_comb begin : use_epc_upd
      t_use_wr_u0[s] = 1'b0;
      t_epc_wr_u0[s] = 1'b0;
      t_use_wd_u0[s] = '0;
      t_epc_wd_u0[s] = '0;
      if (ittage_upd_val_u0[s]
          && ittage_upd_inp_u0[s].ittage_pred_meta.ittage_hit
          && (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_tgt
              != ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_tgt))
      begin
        t_use_wr_u0[s] = 1'b1;
        t_epc_wr_u0[s] = 1'b1;
        t_epc_wd_u0[s] = lcl_epoch[s];
        if (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_using_primary)
        begin
          // rows 4-5: update prm_useful
          if (!ittage_upd_inp_u0[s].indir_mispredict) begin
            // INC saturating
            t_use_wd_u0[s] =
              (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_useful
               == {IT_MAX_USE_WIDTH{1'b1}})
              ? ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_useful
              : IT_MAX_USE_WIDTH'(
                  ittage_upd_inp_u0[s]
                    .ittage_pred_meta.ittage_prm_useful + 1'b1);
          end else begin
            // DEC saturating
            t_use_wd_u0[s] =
              (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_useful
               == IT_MAX_USE_WIDTH'(0))
              ? ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_useful
              : IT_MAX_USE_WIDTH'(
                  ittage_upd_inp_u0[s]
                    .ittage_pred_meta.ittage_prm_useful - 1'b1);
          end
        end else begin
          // rows 6-7: update alt_useful
          if (!ittage_upd_inp_u0[s].indir_mispredict) begin
            // INC saturating
            t_use_wd_u0[s] =
              (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_useful
               == {IT_MAX_USE_WIDTH{1'b1}})
              ? ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_useful
              : IT_MAX_USE_WIDTH'(
                  ittage_upd_inp_u0[s]
                    .ittage_pred_meta.ittage_alt_useful + 1'b1);
          end else begin
            // DEC saturating
            t_use_wd_u0[s] =
              (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_useful
               == IT_MAX_USE_WIDTH'(0))
              ? ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_useful
              : IT_MAX_USE_WIDTH'(
                  ittage_upd_inp_u0[s]
                    .ittage_pred_meta.ittage_alt_useful - 1'b1);
          end
        end
      end
    end
  end

  // ================================================================
  // TGT update logic (per slot).
  // Split strobes: t_prm_tgt_wr fires UP=1 (primary provider,
  // prm_ctr=0, mispredict); t_alt_tgt_wr fires UP=0 (alternate
  // provider, alt_ctr=0, mispredict). Mutually exclusive per slot.
  // ittage_interfaces.md Target Write Gating: only provider written.
  // ================================================================
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_tgt_upd
    always_comb begin : tgt_upd
      t_prm_tgt_wr_u0[s] = 1'b0;
      t_alt_tgt_wr_u0[s] = 1'b0;
      t_tgt_wd_u0[s]     = '0;
      if (ittage_upd_val_u0[s]
          && ittage_upd_inp_u0[s].indir_mispredict)
      begin
        if (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_using_primary)
        begin
          if (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_ctr
              == IT_MAX_CTR_WIDTH'(0))
          begin
            t_prm_tgt_wr_u0[s] = 1'b1;
            t_tgt_wd_u0[s] = ittage_upd_inp_u0[s].resolved_target;
          end
        end else begin
          if (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_ctr
              == IT_MAX_CTR_WIDTH'(0))
          begin
            t_alt_tgt_wr_u0[s] = 1'b1;
            t_tgt_wd_u0[s] = ittage_upd_inp_u0[s].resolved_target;
          end
        end
      end
    end
  end

  // ================================================================
  // Allocation write strobe and data (per slot).
  // alc_wr fires on mispredict when provider != IT5 and
  // a valid candidate was found.
  // t_alc_wd_u0 = {alc_tag, resolved_tgt, lcl_epoch, 0, 0, 1b valid}.
  // ================================================================
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_alc_upd
    always_comb begin : alc_upd
      t_alc_wr_u0[s] = 1'b0;
      t_alc_wd_u0[s] = '0;
      if (ittage_upd_val_u0[s]
          && ittage_upd_inp_u0[s].indir_mispredict
          && (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_comp
              < TSEL_W'(IT_NUM_TABLES - 1))
          && (ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alc_comp
              != TSEL_W'(0)))
      begin
        t_alc_wr_u0[s] = 1'b1;
        t_alc_wd_u0[s] = {
          ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alc_tag,
          ittage_upd_inp_u0[s].resolved_target,
          lcl_epoch[s],
          {IT_MAX_USE_WIDTH{1'b0}},
          {IT_MAX_CTR_WIDTH{1'b0}},
          1'b1
        };
      end
    end
  end

endmodule : ittage_cntrl

`endif // ITTAGE_CNTRL_SV

`default_nettype wire
