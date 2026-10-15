// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for fe_top, the front-end top (BP-137).
//
// BOUND BY MODULE NAME, never by instance name (TD#109). The bind
// reads fe_top's own nets and makes no hierarchical reference.
//
// PROPERTIES BETWEEN TWO LEAVES. The init readies are bp_cluster
// outputs; the p0 request and the update valids are ftq outputs. The
// hold that relates them is formed in ftq_npc, and stated inside
// ftq_npc it could only restate one term of one assign (the reason
// ftq_npc N6 was removed, TD#144). Stated here it covers the hold and
// the routing of the readies from the cluster through fe_top and
// ftq.sv into ftq_npc: a ready tied off or misrouted anywhere on that
// path fires it.
//
// The contract is the RAM Init Interface sections of
// tage_interfaces.md, ittage_interfaces.md and sc_interfaces.md: no
// prediction or update cycle begins before the predictor's ready, and
// upstream logic, the FTQ, must comprehend it.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module fe_top_assert (
  input logic                      clk,
  input logic                      rstn,
  input logic                      tage_rdy,
  input logic                      ittage_rdy,
  input logic                      sc_ready,
  input logic                      ftq_pred_val_p0,
  input logic [NUM_PRED_SLOTS-1:0] tage_upd_val_u0,
  input logic [NUM_PRED_SLOTS-1:0] ittage_upd_val_u0,
  input logic [NUM_PRED_SLOTS-1:0] sc_upd_val_u0
);

  // I1  No p0 request is presented while any of the three init readies
  //     is low (BP-137, ruled by Jeff session-080).
  property p_no_req_before_init;
    @(posedge clk) disable iff (!rstn)
      !(tage_rdy && ittage_rdy && sc_ready) |-> !ftq_pred_val_p0;
  endproperty

  // I2  No update is presented to a predictor while its init ready is
  //     low. The FTQ forms updates only from committed entries, and no
  //     entry is allocated before the first request, so I1 implies I2
  //     in a correct design; I2 checks that nothing else (a stale entry
  //     or a path that bypasses the allocation) reaches the update
  //     ports during a walk.
  property p_no_upd_before_init;
    @(posedge clk) disable iff (!rstn)
      ((tage_upd_val_u0   == '0) || tage_rdy) &&
      ((ittage_upd_val_u0 == '0) || ittage_rdy) &&
      ((sc_upd_val_u0     == '0) || sc_ready);
  endproperty

  a_no_req_before_init: assert property (p_no_req_before_init)
    else $error("I1 a p0 request was presented before the init readies");
  a_no_upd_before_init: assert property (p_no_upd_before_init)
    else $error("I2 an update was presented before its predictor's ready");

endmodule : fe_top_assert

// Bind BY MODULE NAME.
bind fe_top fe_top_assert u_fe_top_assert (
  .clk               (clk),
  .rstn              (rstn),
  .tage_rdy          (bpu_tage_rdy),
  .ittage_rdy        (bpu_ittage_rdy),
  .sc_ready          (bpu_sc_ready),
  .ftq_pred_val_p0   (ftq_pred_val_p0),
  .tage_upd_val_u0   (tage_upd_val_u0),
  .ittage_upd_val_u0 (ittage_upd_val_u0),
  .sc_upd_val_u0     (sc_upd_val_u0)
);
