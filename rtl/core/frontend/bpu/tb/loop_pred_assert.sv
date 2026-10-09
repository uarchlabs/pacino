// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for loop_pred (BP-122, TD#169, TD#170),
// loop_pred_interfaces.md Ruled Change.
//
// BOUND BY MODULE NAME, never by instance name (TD#109). The bind
// reads the port list and makes no hierarchical reference.
//
// THE ITERATION NUMBER. A prediction carries the speculative count it
// read at p2 (lp_curs / lp_curs_v). The count a block reads at p2 must
// include the advance of the block ahead of it: that is what lets the
// count settle while many iterations are in flight. Each property
// compares the p2 read of one cycle with the p2 read and the advance
// of the cycle before, held in this module's own registers: the
// source is an earlier cycle, not the assignment that drives pred_p2.
// A p2 read that returned the count read at p0 (the registered p1
// result, as the p2 metadata did before BP-122), or an advance that
// did not land, fails LP1; an exit that did not make the count known
// fails LP2.
//
// Written against slots 0 and NUM_PRED_SLOTS-1 by name rather than as
// a generate loop, as ftq_npc_assert is, so the labels are plain.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module loop_pred_assert #(
  parameter int NUM_PRED_SLOTS = 1
) (
  input logic                      clk,
  input logic                      rstn,
  input lp_pred_t                  pred_p2     [0:NUM_PRED_SLOTS-1],
  input logic [NUM_PRED_SLOTS-1:0] spec_val_p2,
  input logic [NUM_PRED_SLOTS-1:0] spec_tkn_p2,
  input logic                      rst_val,
  input logic                      inv_val
);

  localparam int HI = NUM_PRED_SLOTS - 1;
  localparam logic [LP_ITR_BITS-1:0] ITR_MAX = {LP_ITR_BITS{1'b1}};

  // The previous cycle's p2 read and advance, per checked slot.
  // q_adv: a block at p2 advanced its entry and nothing else wrote a
  // count that cycle (no restore, no invalidate). q_known: the count
  // it advanced was known (LP1 needs it; an exit, LP2, does not).
  lp_pred_t q_p2  [2];
  logic     q_adv [2];
  logic     q_tkn [2];
  logic     q_known [2];

  always_ff @(posedge clk or negedge rstn) begin : hist
    if (!rstn) begin
      for (int i = 0; i < 2; i++) begin
        q_p2[i]  <= '0;
        q_adv[i] <= 1'b0;
        q_tkn[i] <= 1'b0;
        q_known[i] <= 1'b0;
      end
    end else begin
      q_p2[0]  <= pred_p2[0];
      q_p2[1]  <= pred_p2[HI];
      q_adv[0] <= spec_val_p2[0] && pred_p2[0].lp_hit &&
                  !rst_val && !inv_val;
      q_adv[1] <= spec_val_p2[HI] && pred_p2[HI].lp_hit &&
                  !rst_val && !inv_val;
      q_known[0] <= pred_p2[0].lp_curs_v;
      q_known[1] <= pred_p2[HI].lp_curs_v;
      q_tkn[0] <= spec_tkn_p2[0];
      q_tkn[1] <= spec_tkn_p2[HI];
    end
  end

  // The p2 read of this cycle is the entry the block ahead advanced.
  function automatic logic same_entry(input lp_pred_t now,
                                      input lp_pred_t prev);
    return now.lp_hit && (now.lp_idx == prev.lp_idx) &&
           (now.lp_tag == prev.lp_tag) && (now.lp_way == prev.lp_way);
  endfunction

  // LP1 A taken advance of a known count is seen by the next p2 read
  //     of the same entry: one more.
  property p_adv_taken(int i, lp_pred_t now);
    @(posedge clk) disable iff (!rstn)
      (q_adv[i] && q_known[i] && q_tkn[i] &&
       (q_p2[i].lp_curs != ITR_MAX) &&
       same_entry(now, q_p2[i]))
        |-> now.lp_curs_v &&
            (now.lp_curs == q_p2[i].lp_curs + LP_ITR_BITS'(1));
  endproperty

  // LP2 An exit makes the count zero and known, whatever it was, a
  //     count not known included (that is the resynchronisation).
  property p_adv_exit(int i, lp_pred_t now);
    @(posedge clk) disable iff (!rstn)
      (q_adv[i] && !q_tkn[i] && same_entry(now, q_p2[i]))
        |-> now.lp_curs_v && (now.lp_curs == '0);
  endproperty

  a_lp_adv_taken_s0: assert property (p_adv_taken(0, pred_p2[0]))
    else $error("LP1 slot 0: a taken advance not seen at the next p2");
  a_lp_adv_taken_s1: assert property (p_adv_taken(1, pred_p2[HI]))
    else $error("LP1 slot 1: a taken advance not seen at the next p2");
  a_lp_adv_exit_s0:  assert property (p_adv_exit(0, pred_p2[0]))
    else $error("LP2 slot 0: an exit did not make the count 0, known");
  a_lp_adv_exit_s1:  assert property (p_adv_exit(1, pred_p2[HI]))
    else $error("LP2 slot 1: an exit did not make the count 0, known");

endmodule : loop_pred_assert

// Bind BY MODULE NAME.
bind loop_pred loop_pred_assert #(.NUM_PRED_SLOTS(NUM_PRED_SLOTS))
  u_assert (
  .clk          (clk),
  .rstn         (rstn),
  .pred_p2      (pred_p2),
  .spec_val_p2  (spec_val_p2),
  .spec_tkn_p2  (spec_tkn_p2),
  .rst_val      (rst_val),
  .inv_val      (inv_val)
);
