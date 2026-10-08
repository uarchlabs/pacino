// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ftq_upd_conv (BP-119, TD#150, TD#151),
// ftq_bpu_interfaces.md 8 and fe_decisions.md 7.2.
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
//
// Each property compares an output against a source the converter's
// own assignment does not restate: the cluster's readies (inputs),
// the requests ftq_resolve presented (inputs), or a re-derivation
// made here.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_upd_conv_assert (
  input logic                       clk,
  input logic                       rstn,
  input logic                       sc_enable,
  input bp_update_t                 upd [0:NUM_PRED_SLOTS-1],
  input logic [NUM_PRED_SLOTS-1:0]  upd_ubtb_val,
  input logic [NUM_PRED_SLOTS-1:0]  upd_lp_val,
  input logic [NUM_PRED_SLOTS-1:0]  upd_tage_val,
  input logic [NUM_PRED_SLOTS-1:0]  upd_ittage_val,
  input logic [NUM_PRED_SLOTS-1:0]  upd_sc_val,
  input logic [NUM_PRED_SLOTS-1:0]  tage_upd_rdy,
  input logic [NUM_PRED_SLOTS-1:0]  ittage_upd_rdy,
  input logic [NUM_PRED_SLOTS-1:0]  sc_upd_rdy,
  input ubtb_upd_t [NUM_PRED_SLOTS-1:0] ubtb_upd_u0,
  input logic [NUM_PRED_SLOTS-1:0]  lp_upd_valid_p0,
  input logic [NUM_PRED_SLOTS-1:0]  tage_upd_val_u0,
  input logic [NUM_PRED_SLOTS-1:0]  ittage_upd_val_u0,
  input logic [NUM_PRED_SLOTS-1:0]  sc_upd_val_u0
);

  // The resolved type the cluster will read back from the uBTB
  // payload's structural bits. Written here in the cluster's arm
  // order (bp_cluster.sv upd_br_type), independently of how the
  // converter sets the bits.
  function automatic bp_br_type_e decode(input ubtb_upd_t u);
    if      (u.is_br)               return COND;
    else if (!u.is_jmp)             return NO_BRANCH;
    else if (u.is_ret && u.is_call) return RETURN_CALL;
    else if (u.is_ret)              return RETURN;
    else if (u.is_call)             return u.is_jalr ? INDIRECT_CALL
                                                     : DIRECT_CALL;
    else if (u.is_jalr)             return INDIRECT_NONRET;
    else                            return DIRECT_UNC;
  endfunction

  genvar gs;
  generate
    for (gs = 0; gs < NUM_PRED_SLOTS; gs++) begin : g_slot

      // V1  TD#150. A queued predictor's valid is never presented while
      //     its queue is full on EITHER slot: the readies are ANDed per
      //     predictor. Stated against the cluster's ready inputs.
      property p_tage_needs_both_rdy;
        @(posedge clk) disable iff (!rstn)
          tage_upd_val_u0[gs] |-> (&tage_upd_rdy);
      endproperty
      a_tage_needs_both_rdy: assert property (p_tage_needs_both_rdy)
        else $error("V1 a TAGE update was presented to a full queue");

      property p_ittage_needs_both_rdy;
        @(posedge clk) disable iff (!rstn)
          ittage_upd_val_u0[gs] |-> (&ittage_upd_rdy);
      endproperty
      a_ittage_needs_both_rdy: assert property (p_ittage_needs_both_rdy)
        else $error("V1 an ITTAGE update was presented to a full queue");

      // V2  NO PARTIAL ACCEPTANCE. If any predictor is given this
      //     slot's update, every predictor the slot requested is given
      //     it, and a requested SC is granted (its ready is the grant).
      //     A partial acceptance would apply the update twice when the
      //     backend re-presents the resolution (FE-5). Stated across the
      //     requests in and the valids out, not on one assignment.
      property p_all_or_nothing;
        @(posedge clk) disable iff (!rstn)
          (ubtb_upd_u0[gs].valid | lp_upd_valid_p0[gs] |
           tage_upd_val_u0[gs]   | ittage_upd_val_u0[gs]) |->
            (!upd_ubtb_val[gs]   || ubtb_upd_u0[gs].valid) &&
            (!upd_lp_val[gs]     || lp_upd_valid_p0[gs])   &&
            (!upd_tage_val[gs]   || tage_upd_val_u0[gs])   &&
            (!upd_ittage_val[gs] || ittage_upd_val_u0[gs]) &&
            (!(upd_sc_val[gs] && sc_enable) ||
             (sc_upd_val_u0[gs] && (&sc_upd_rdy)));
      endproperty
      a_all_or_nothing: assert property (p_all_or_nothing)
        else $error("V2 a slot's update was accepted by some predictors");

      // The SC-disabled rule is not a property here: stated on this
      // module's ports it would restate the SC valid's assignment
      // (CLAUDE.md, assertions). tb_ftq_upd_conv group S checks it.

      // V4  The uBTB payload's structural bits carry the resolved type:
      //     decoded in the cluster's arm order they give upd.br_type
      //     back. The cluster derives every predictor's type gate from
      //     these bits, so a wrong bit misroutes the whole update.
      property p_type_round_trip;
        @(posedge clk) disable iff (!rstn)
          upd[gs].valid |-> (decode(ubtb_upd_u0[gs]) == upd[gs].br_type);
      endproperty
      a_type_round_trip: assert property (p_type_round_trip)
        else $error("V4 the uBTB payload bits do not decode to br_type");

      // V5  Nothing is presented for a slot that carries no resolution.
      property p_val_needs_record;
        @(posedge clk) disable iff (!rstn)
          (ubtb_upd_u0[gs].valid | lp_upd_valid_p0[gs] |
           tage_upd_val_u0[gs]   | ittage_upd_val_u0[gs] |
           sc_upd_val_u0[gs]) |-> upd[gs].valid;
      endproperty
      a_val_needs_record: assert property (p_val_needs_record)
        else $error("V5 a predictor valid with no resolution behind it");

    end
  endgenerate

endmodule : ftq_upd_conv_assert

// Bind BY MODULE NAME.
bind ftq_upd_conv ftq_upd_conv_assert u_assert (
  .clk               (clk),
  .rstn              (rstn),
  .sc_enable         (sc_enable),
  .upd               (upd),
  .upd_ubtb_val      (upd_ubtb_val),
  .upd_lp_val        (upd_lp_val),
  .upd_tage_val      (upd_tage_val),
  .upd_ittage_val    (upd_ittage_val),
  .upd_sc_val        (upd_sc_val),
  .tage_upd_rdy      (tage_upd_rdy),
  .ittage_upd_rdy    (ittage_upd_rdy),
  .sc_upd_rdy        (sc_upd_rdy),
  .ubtb_upd_u0       (ubtb_upd_u0),
  .lp_upd_valid_p0   (lp_upd_valid_p0),
  .tage_upd_val_u0   (tage_upd_val_u0),
  .ittage_upd_val_u0 (ittage_upd_val_u0),
  .sc_upd_val_u0     (sc_upd_val_u0)
);
