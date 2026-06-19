// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    ittage_assert.sv
// DATE:    2026-06-03
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Assertions for ittage.sv. Bound via bind in simulation only.
// Checks invariants at the ittage module boundary.
// ===================================================================
`ifndef ITTAGE_ASSERT_SV
`define ITTAGE_ASSERT_SV
`default_nettype none
import bp_defines_pkg::*;
import bp_structs_pkg::*;
module ittage_assert #(
  parameter int NUM_PRED_SLOTS = 2
) (
  input logic                          clk,
  input logic                          rstn,
  input logic [NUM_PRED_SLOTS-1:0]     ittage_pred_rdy_p2,
  input ittage_pred_meta_t             ittage_pred_meta_p2[0:NUM_PRED_SLOTS-1],
  input logic [NUM_PRED_SLOTS-1:0]     ittage_upd_val_u0,
  input ittage_upd_inp_t               ittage_upd_inp_u0[0:NUM_PRED_SLOTS-1]
);
`ifndef SYNTHESIS

  // ------------------------------------------------------------------
  // Assert: ittage_hit=1 requires at least one tagged table hit.
  // prm_comp=0 and alt_comp=0 with ittage_hit=1 is impossible.
  // Citeable: ittage_cntrl_ctr_update_rules.md impossible row group.
  // ------------------------------------------------------------------
  always_ff @(posedge clk) begin
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      if (ittage_pred_rdy_p2[s]
          && ittage_pred_meta_p2[s].ittage_hit) begin
        assert (   ittage_pred_meta_p2[s].ittage_prm_comp != '0
                || ittage_pred_meta_p2[s].ittage_alt_comp != '0)
          else $error(
            "[ITTAGE_ASSERT][PRED] slot=%0d hit=1 prm_comp=0 alt_comp=0", s);
      end
      if (ittage_upd_val_u0[s]
          && ittage_upd_inp_u0[s].ittage_pred_meta.ittage_hit) begin
        assert (
               ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_comp
               != '0
            || ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_comp
               != '0)
          else $error(
            "[ITTAGE_ASSERT][UPD] slot=%0d hit=1 prm_comp=0 alt_comp=0", s);
      end
    end
  end

  // ------------------------------------------------------------------
  // Assert: using_primary=1 requires prm_comp>0.
  // Primary cannot be provider if primary missed.
  // Citeable: ittage_cntrl_ctr_update_rules.md impossible row group.
  // ------------------------------------------------------------------
  always_ff @(posedge clk) begin
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      if (ittage_pred_rdy_p2[s]
          && ittage_pred_meta_p2[s].ittage_hit
          && ittage_pred_meta_p2[s].ittage_using_primary) begin
        assert (ittage_pred_meta_p2[s].ittage_prm_comp != '0)
          else $error(
            "[ITTAGE_ASSERT][PRED] slot=%0d using_primary=1 but prm_comp=0", s);
      end
      if (ittage_upd_val_u0[s]
          && ittage_upd_inp_u0[s].ittage_pred_meta.ittage_hit
          && ittage_upd_inp_u0[s].ittage_pred_meta.ittage_using_primary)
      begin
        assert (
          ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_comp != '0)
          else $error(
            "[ITTAGE_ASSERT][UPD] slot=%0d using_primary=1 but prm_comp=0", s);
      end
    end
  end

  // ------------------------------------------------------------------
  // Assert: using_primary=0 with ittage_hit=1 requires alt_comp>0.
  // Alternate cannot be provider if alternate missed.
  // Citeable: ittage_cntrl_ctr_update_rules.md impossible row group.
  // ------------------------------------------------------------------
  always_ff @(posedge clk) begin
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      if (ittage_pred_rdy_p2[s]
          && ittage_pred_meta_p2[s].ittage_hit
          && !ittage_pred_meta_p2[s].ittage_using_primary) begin
        assert (ittage_pred_meta_p2[s].ittage_alt_comp != '0)
          else $error(
            "[ITTAGE_ASSERT][PRED] slot=%0d using_primary=0 alt_comp=0", s);
      end
      if (ittage_upd_val_u0[s]
          && ittage_upd_inp_u0[s].ittage_pred_meta.ittage_hit
          && !ittage_upd_inp_u0[s].ittage_pred_meta.ittage_using_primary)
      begin
        assert (
          ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_comp != '0)
          else $error(
            "[ITTAGE_ASSERT][UPD] slot=%0d using_primary=0 alt_comp=0", s);
      end
    end
  end

`endif
endmodule : ittage_assert
`endif // ITTAGE_ASSERT_SV
`default_nettype wire
