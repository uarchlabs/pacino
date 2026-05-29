// ===================================================================
// FILE:    tage_assert.sv
// DATE:    2026-05-27
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Assertions for tage.sv. Bound via bind in simulation only.
// Checks invariants at the tage module boundary.
// ===================================================================
`ifndef TAGE_ASSERT_SV
`define TAGE_ASSERT_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tage_assert #(
  parameter int NUM_PRED_SLOTS = 2
) (
  input logic                          clk,
  input logic                          rstn,
  input logic [NUM_PRED_SLOTS-1:0]     tage_pred_rdy_p2,
  input tage_pred_meta_t               tage_pred_meta_p2[0:NUM_PRED_SLOTS-1],
  input logic [NUM_PRED_SLOTS-1:0]     tage_upd_val_u0,
  input tage_upd_inp_t                 tage_upd_inp_u0[0:NUM_PRED_SLOTS-1]
);

`ifndef SYNTHESIS
  // --------------------------------------------------------------------
  // Assert: alt provider cannot be tagged when primary is BIM.
  // Citeable: tage_cntrl_ctr_update_rules.md row 18 unreachable.
  // --------------------------------------------------------------------
  always_ff @(posedge clk) begin
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin

      //Prediction - assert if prm_comp == 0 and alt_comp != 0
      if (tage_pred_rdy_p2[s]) begin
        assert (   tage_pred_meta_p2[s].tage_prm_comp != '0
                || tage_pred_meta_p2[s].tage_alt_comp == '0)
          else $error(
             "tage_assert: pred slot %0d prm_comp=0 alt_comp>0 invalid", s);
      end

      //Update - assert if prm_comp == 0 and alt_comp != 0
      if (tage_upd_val_u0[s]) begin
        assert (   tage_upd_inp_u0[s].tage_pred_meta.tage_prm_comp != '0
                || tage_upd_inp_u0[s].tage_pred_meta.tage_alt_comp == '0)
          else $error(
             "tage_assert: upd slot %0d prm_comp=0 alt_comp>0 invalid", s);
      end
    end
  end
  // --------------------------------------------------------------------
  // ADR-001: tage_using_primary shall be 1 when BIM is
  // sole provider (prm_comp=0 and alt_comp=0).
  // tage_cntrl_ctr_update_rules.md ADR-001.
  // --------------------------------------------------------------------
  always_ff @(posedge clk) begin
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin

      if (tage_pred_rdy_p2[s]
          && tage_pred_meta_p2[s].tage_prm_comp == '0
          && tage_pred_meta_p2[s].tage_alt_comp == '0)
        assert (tage_pred_meta_p2[s].tage_using_primary == 1'b1)
          else $error("[ADR-001][TAGE_ASSERT][PRED] slot=%0d using_primary=0 when prm_comp=0 alt_comp=0", s);

      if (tage_upd_val_u0[s]
          && tage_upd_inp_u0[s].tage_pred_meta.tage_prm_comp == '0
          && tage_upd_inp_u0[s].tage_pred_meta.tage_alt_comp == '0)
        assert (tage_upd_inp_u0[s].tage_pred_meta.tage_using_primary == 1'b1)
          else $error("[ADR-001][TAGE_ASSERT][UPD] slot=%0d using_primary=0 when prm_comp=0 alt_comp=0", s);

    end
  end
`endif

endmodule : tage_assert

`endif // TAGE_ASSERT_SV

`default_nettype wire
