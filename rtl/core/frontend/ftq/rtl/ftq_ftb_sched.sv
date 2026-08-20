// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FTB update scheduler. First module of the FTQ unit (BP-100).
//
// The FTQ has NUM_PRED_SLOTS update channels. Every predictor takes
// two per cycle except the FTB, whose update is 14 flat ports with
// no slot dimension and NO ready. Presenting two in one cycle
// silently loses one, so this scheduler is a correctness
// requirement, not an optimisation (ftq_decisions.md 5.7).
//
// The rule is ftq_decisions.md 5.7.3 S1-S6, implemented here, not
// re-derived:
//
//   S1  FTB-bound means the resolved br_type is not NO_BRANCH.
//   S2  Pending = the skid entry, if occupied, plus the FTB-bound
//       channels accepted this cycle. The skid is ONE deep.
//   S3  Issue exactly one: the skid when occupied, else the
//       highest-value new one, channel 0 breaking a tie.
//   S4  Retain the highest-value remaining pending in the skid.
//   S5  Anything still remaining is DROPPED if LOW.
//   S6  A HIGH update is NEVER dropped. If accepting one would
//       force S5 to drop a HIGH, the ready deasserts instead.
//
// Value (5.7.2): HIGH when the update allocates (missed at predict)
// or corrects (mispredicted). LOW is a routine conf step on a
// branch that hit and predicted correctly. Dropping a LOW update
// delays a training step; it never loses an entry.
//
// The output is REGISTERED: a channel accepted in cycle T issues in
// T+1. Property P1 of 5.7.4 states this directly, with |=>.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_ftb_sched #(
  // Number of update channels. The rule of 5.7.3 is written for the
  // two-channel case and the skid is one deep; NUM_UPD_CHAN is a
  // parameter so the width is named rather than literal, not so the
  // module generalises. Named NUM_UPD_CHAN and not NUM_PRED_SLOTS
  // so it does not shadow the package parameter (VARHIDDEN).
  parameter int NUM_UPD_CHAN = 2
) (
  input  logic                        clk,
  input  logic                        rstn,

  // ---- per-channel update input -----------------------------------
  // upd_hit and upd_mispred are the two value bits of 5.7.2. Both
  // are already to hand where the update is formed: mispredict
  // arrives on the resolution channel, hit is read from the slow
  // path with the rest of bp_ftq_meta_t. No new state.
  input  logic [NUM_UPD_CHAN-1:0]     upd_val,
  input  ftb_upd_t                    upd [0:NUM_UPD_CHAN-1],
  input  logic [NUM_UPD_CHAN-1:0]     upd_hit,
  input  logic [NUM_UPD_CHAN-1:0]     upd_mispred,

  // ---- per-channel ready (S6) -------------------------------------
  // Deasserts only to prevent dropping a HIGH update. This is the
  // ftq_bkend_rsv_rdy of ftq_backend_interfaces.md 4 as far as the
  // FTB path is concerned; the FTQ ANDs it with its other reasons.
  output logic [NUM_UPD_CHAN-1:0]     upd_rdy,

  // ---- flat FTB update group, to the cluster boundary -------------
  output logic                        ftb_upd_valid_u0,
  output logic [VA_WIDTH-1:0]         ftb_upd_pc_u0,
  output logic                        ftb_upd_hit_u0,
  output logic [FTB_WAY_BITS-1:0]     ftb_upd_way_u0,
  output logic                        ftb_upd_is_br_u0,
  output logic                        ftb_upd_br_idx_u0,
  output logic                        ftb_upd_taken_u0,
  output logic [VA_WIDTH-1:0]         ftb_upd_target_u0,
  output logic [FTB_BR_POS_BITS-1:0]  ftb_upd_pos_u0,
  output logic                        ftb_upd_is_jmp_u0,
  output logic [VA_WIDTH-1:0]         ftb_upd_jmp_target_u0,
  output logic                        ftb_upd_is_call_u0,
  output logic                        ftb_upd_is_ret_u0,
  output logic                        ftb_upd_is_jalr_u0,
  output logic [VA_WIDTH-1:0]         ftb_upd_pft_addr_u0,

  // ---- observation, for the bound properties of 5.7.4 -------------
  // Declared as ports rather than left internal so the assertion
  // file binds by MODULE NAME against the port list and does not
  // reach into module internals (TD#109).
  output logic                        ftb_upd_from_skid,
  output logic                        skid_val,
  output logic                        skid_wr,
  output logic                        skid_issue,
  output logic                        drop_val,
  output logic                        drop_is_high,
  output logic [$clog2(NUM_UPD_CHAN+2)-1:0] n_acc_ftb,
  output logic [$clog2(NUM_UPD_CHAN+2)-1:0] n_pend_ftb,
  output logic                        any_pend_high
);

  // -----------------------------------------------------------------
  // Internal state and selection nets.
  // -----------------------------------------------------------------
  // The skid of S2, one deep.
  ftb_upd_t                w_skid_pl;
  logic                    w_skid_high;
  logic                    w_skid_val_r;

  // The single update issued this cycle (S3), registered out.
  ftb_upd_t                w_issue_pl;
  logic                    w_issue_val;
  logic                    w_issue_from_skid;

  // The single update retained this cycle (S4).
  ftb_upd_t                w_retain_pl;
  logic                    w_retain_val;
  logic                    w_retain_high;

  // The best new channel is the one no other outranks; the second
  // best is the one exactly one outranks.
  logic [NUM_UPD_CHAN-1:0] w_best_new;
  logic [NUM_UPD_CHAN-1:0] w_second_new;

  // The registered output payload.
  ftb_upd_t                w_out_pl;

  // -----------------------------------------------------------------
  // S1. FTB-bound.
  // -----------------------------------------------------------------
  // 5.7.3 states this as "br_type is anything other than NO_BRANCH".
  // The scheduler is given the FLAT payload, which carries the same
  // fact as is_br | is_jmp: a resolved NO_BRANCH forms neither a
  // conditional nor a jump field. bp_cluster.sv already qualifies
  // its own FTB update the same way. Expressed here in the payload
  // the module actually has rather than adding a br_type port that
  // would carry redundant information.
  logic [NUM_UPD_CHAN-1:0] w_ftb_bound;
  logic [NUM_UPD_CHAN-1:0] w_is_high;
  logic [NUM_UPD_CHAN-1:0] w_pres_ftb;

  always_comb begin : classify
    for (int c = 0; c < NUM_UPD_CHAN; c++) begin
      w_ftb_bound[c] = upd[c].is_br | upd[c].is_jmp;
      // 5.7.2. Allocates (missed at predict) or corrects
      // (mispredicted). Anything else is a routine conf step.
      w_is_high[c]   = (~upd_hit[c]) | upd_mispred[c];
      w_pres_ftb[c]  = upd_val[c] & w_ftb_bound[c];
    end
  end

  // -----------------------------------------------------------------
  // Rank, and the ready of S6.
  // -----------------------------------------------------------------
  // rank[c] counts the presented FTB-bound channels that OUTRANK c:
  // higher value first, lower channel index breaking a tie. Channel
  // order is program order within an entry (IC-FTB-16), so the tie
  // break is not arbitrary.
  //
  // With the skid empty the module handles two new updates without
  // dropping any: one issues and one is retained. With the skid
  // occupied the skid issues, so only one new one can be retained
  // and any further one must be dropped. S6 forbids dropping a
  // HIGH, so a channel that would be the one dropped AND is HIGH is
  // not accepted at all: its ready deasserts and the backend holds
  // it.
  logic [$clog2(NUM_UPD_CHAN+1)-1:0] w_rank [0:NUM_UPD_CHAN-1];
  logic [$clog2(NUM_UPD_CHAN+2)-1:0] w_n_new_allowed;

  always_comb begin : rank_and_ready
    for (int c = 0; c < NUM_UPD_CHAN; c++) begin
      w_rank[c] = '0;
      for (int o = 0; o < NUM_UPD_CHAN; o++) begin
        if (o != c && w_pres_ftb[o] && w_pres_ftb[c]) begin
          if (w_is_high[o] && !w_is_high[c]) begin
            w_rank[c] = w_rank[c] + 1'b1;
          end else if ((w_is_high[o] == w_is_high[c]) && (o < c)) begin
            w_rank[c] = w_rank[c] + 1'b1;
          end
        end
      end
    end

    w_n_new_allowed = skid_val ? 1 : 2;

    for (int c = 0; c < NUM_UPD_CHAN; c++) begin
      // A channel is held only when it is FTB-bound, would fall
      // outside the capacity, and is HIGH. A LOW one in that
      // position is accepted and dropped, which is the whole point
      // of FE-5a.
      upd_rdy[c] = !(w_pres_ftb[c]
                     && (w_rank[c] >= w_n_new_allowed)
                     && w_is_high[c]);
    end
  end

  // -----------------------------------------------------------------
  // S2. Accepted, and the pending set.
  // -----------------------------------------------------------------
  logic [NUM_UPD_CHAN-1:0] w_acc_ftb;

  always_comb begin : accept
    for (int c = 0; c < NUM_UPD_CHAN; c++) begin
      w_acc_ftb[c] = w_pres_ftb[c] & upd_rdy[c];
    end
  end

  // Counts, for the properties. n_pend_ftb is over the skid plus
  // the PRESENTED FTB-bound channels rather than the accepted ones:
  // P5 constrains the ready, so counting accepted channels would
  // make it depend on its own conclusion.
  always_comb begin : counts
    n_acc_ftb     = '0;
    n_pend_ftb    = skid_val ? 1 : '0;
    any_pend_high = skid_val & w_skid_high;
    for (int c = 0; c < NUM_UPD_CHAN; c++) begin
      if (w_acc_ftb[c])  n_acc_ftb  = n_acc_ftb  + 1'b1;
      if (w_pres_ftb[c]) n_pend_ftb = n_pend_ftb + 1'b1;
      if (w_pres_ftb[c] && w_is_high[c]) any_pend_high = 1'b1;
    end
  end

  // -----------------------------------------------------------------
  // S3, S4, S5. Issue one, retain one, drop the rest.
  // -----------------------------------------------------------------
  always_comb begin : select
    for (int c = 0; c < NUM_UPD_CHAN; c++) begin
      w_best_new[c]   = w_acc_ftb[c] & (w_rank[c] == 0);
      w_second_new[c] = w_acc_ftb[c] & (w_rank[c] == 1);
    end

    // S3. The skid issues whenever it is occupied, so the older
    // update goes first and resolution order is preserved (FE-6).
    w_issue_from_skid = skid_val;
    w_issue_val       = skid_val | (|w_best_new);
    w_issue_pl        = w_skid_pl;
    if (!w_issue_from_skid) begin
      for (int c = 0; c < NUM_UPD_CHAN; c++) begin
        if (w_best_new[c]) w_issue_pl = upd[c];
      end
    end

    // S4. Retain the highest-value remaining. With the skid
    // occupied everything new remains, so the best new one is
    // retained; with the skid empty the best new one issued, so the
    // second best is retained.
    w_retain_val  = 1'b0;
    w_retain_pl   = '0;
    w_retain_high = 1'b0;
    for (int c = 0; c < NUM_UPD_CHAN; c++) begin
      if (skid_val ? w_best_new[c] : w_second_new[c]) begin
        w_retain_val  = 1'b1;
        w_retain_pl   = upd[c];
        w_retain_high = w_is_high[c];
      end
    end

    // S5 and S6. Anything accepted, not issued and not retained is
    // dropped. The ready of S6 is what makes drop_is_high
    // unreachable; it is computed here so the property can observe
    // it rather than being assumed.
    drop_val     = 1'b0;
    drop_is_high = 1'b0;
    for (int c = 0; c < NUM_UPD_CHAN; c++) begin
      if (w_acc_ftb[c]
          && !(!w_issue_from_skid && w_best_new[c])
          && !(skid_val ? w_best_new[c] : w_second_new[c])) begin
        drop_val     = 1'b1;
        drop_is_high = drop_is_high | w_is_high[c];
      end
    end

    skid_wr    = w_retain_val;
    skid_issue = w_issue_from_skid;
  end

  assign skid_val = w_skid_val_r;

  // -----------------------------------------------------------------
  // State. The skid, and the registered output.
  // -----------------------------------------------------------------
  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      w_skid_val_r      <= 1'b0;
      w_skid_pl         <= '0;
      w_skid_high       <= 1'b0;
      ftb_upd_valid_u0  <= 1'b0;
      ftb_upd_from_skid <= 1'b0;
      w_out_pl          <= '0;
    end else begin
      w_skid_val_r      <= w_retain_val;
      w_skid_pl         <= w_retain_pl;
      w_skid_high       <= w_retain_high;
      ftb_upd_valid_u0  <= w_issue_val;
      ftb_upd_from_skid <= w_issue_from_skid;
      w_out_pl          <= w_issue_pl;
    end
  end

  // -----------------------------------------------------------------
  // Flatten onto the cluster's update group.
  // -----------------------------------------------------------------
  assign ftb_upd_pc_u0         = w_out_pl.pc;
  assign ftb_upd_hit_u0        = w_out_pl.hit;
  assign ftb_upd_way_u0        = w_out_pl.way;
  assign ftb_upd_is_br_u0      = w_out_pl.is_br;
  assign ftb_upd_br_idx_u0     = w_out_pl.br_idx;
  assign ftb_upd_taken_u0      = w_out_pl.taken;
  assign ftb_upd_target_u0     = w_out_pl.target;
  assign ftb_upd_pos_u0        = w_out_pl.pos;
  assign ftb_upd_is_jmp_u0     = w_out_pl.is_jmp;
  assign ftb_upd_jmp_target_u0 = w_out_pl.jmp_target;
  assign ftb_upd_is_call_u0    = w_out_pl.is_call;
  assign ftb_upd_is_ret_u0     = w_out_pl.is_ret;
  assign ftb_upd_is_jalr_u0    = w_out_pl.is_jalr;
  assign ftb_upd_pft_addr_u0   = w_out_pl.pft_addr;

endmodule : ftq_ftb_sched
