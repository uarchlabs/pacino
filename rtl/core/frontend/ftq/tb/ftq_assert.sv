// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ftq, the unit top (BP-122, TD#170).
//
// BOUND BY MODULE NAME, never by instance name (TD#109). The bind
// reads the port list and makes no hierarchical reference.
//
// A PROPERTY BETWEEN TWO LEAVES. The TD#162 hold (BP-121 D7, ruled by
// Jeff) is formed in ftq_npc from the FTB scheduler's issue_next, and
// stated inside ftq_npc it could only restate the hold term of one
// assign (the reason ftq_npc N6 was removed, TD#144). Stated here it
// relates two outputs that two different leaves drive: the request
// ftq_npc presents and the update ftq_ftb_sched issues.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_assert (
  input logic clk,
  input logic rstn,
  input logic ftq_pred_val_p0,
  input logic ftb_upd_valid_u0
);

  // F1  BP-121 D7, TD#162 (m07). A request presented at p0 reaches
  //     the FTB read port at p1, the next cycle; an FTB update in
  //     that cycle takes the single read port and the lookup is
  //     dropped. So no FTB update issues in the cycle after a request.
  property p_no_update_after_request;
    @(posedge clk) disable iff (!rstn)
      ftq_pred_val_p0 |=> !ftb_upd_valid_u0;
  endproperty

  a_no_update_after_request: assert property (p_no_update_after_request)
    else $error("F1 an FTB update issued under a request's FTB read");

endmodule : ftq_assert

// Bind BY MODULE NAME.
bind ftq ftq_assert u_assert (
  .clk              (clk),
  .rstn             (rstn),
  .ftq_pred_val_p0  (ftq_pred_val_p0),
  .ftb_upd_valid_u0 (ftb_upd_valid_u0)
);
