// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ftq_npc (BP-107), ftq_decisions.md 4.
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
//
// N4 IS THE ONE THAT MATTERS. It is a SAME-CYCLE implication from
// the p1 group to ftq_pred_pc_p0, so it holds only if the successor
// path is combinational. Registering that path -- which passes every
// functional test and costs a cycle on every prediction (Binding
// Decision 3, 4.4) -- leaves the previous PC on the output in the
// arm-5 cycle and fails N4 immediately. This is the property that
// makes the zero-bubble loop a checked fact rather than a comment.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_npc_assert (
  input logic                    clk,
  input logic                    rstn,
  input logic                    bkend_redir_val,
  input logic [FTQ_IDX_BITS-1:0] bkend_redir_idx,
  input logic [VA_WIDTH-1:0]     bkend_redir_pc,
  input logic                    pd_redir_val,
  input logic [VA_WIDTH-1:0]     pd_redir_pc,
  input logic                    p1_val,
  input bp_ftq_slot_t            p1_slot [0:NUM_PRED_SLOTS-1],
  input logic [VA_WIDTH-1:0]     p1_pft_addr,
  input logic [VA_WIDTH-1:0]     ftq_pred_pc_p0,
  input logic [VA_WIDTH-1:0]     pred_pc_p1,
  input logic                    redir_val,
  input logic [FTQ_IDX_BITS-1:0] redir_idx,
  input logic                    redir_self,
  input ftq_redir_cause_e        redir_cause,
  input logic                    rollback_val,
  input logic [FTQ_IDX_BITS-1:0] rollback_idx,
  input logic [5:1]              arm_win,
  // BP-122, N11 and N12 (TD#170).
  input ftq_redir_cause_e        bkend_redir_cause,
  input logic                    bkend_redir_self,
  input logic [FTB_BR_POS_BITS-1:0] bkend_redir_pos,
  input logic                    bkend_redir_taken,
  input bp_ftq_entry_t           redir_entry,
  input logic                    rollback_corr,
  input logic [1:0]              rollback_n,
  input logic [1:0]              rollback_tkn,
  input logic [NUM_PRED_SLOTS-1:0] rollback_slot_ex,
  input logic [NUM_PRED_SLOTS-1:0] rollback_slot_tkn
);

  // A REGISTERED COPY OF THE PRESENTED PC, not $past. pred_pc_p1 is
  // combinationally r_next_pc, and ftq_pred_pc_p0 is w_sel_pc whose
  // hold arm reads r_next_pc, so the two sit in one combinational
  // cone around a flop. $past over that cone does not reliably
  // return the value the flop captured. An independent registered
  // model does, and it is the form ftq_status_assert and
  // ftq_shadow_assert already use.
  logic [VA_WIDTH-1:0] r_prev_pc;

  always_ff @(posedge clk or negedge rstn) begin : hist
    if (!rstn) r_prev_pc <= RESET_VECTOR;
    else       r_prev_pc <= ftq_pred_pc_p0;
  end

  // N1  Exactly one arm wins, or none. None is arm 6, the hold of
  //     4.5. Two arms winning would mean the priority encoder of
  //     4.2 had been rewritten as a set of parallel enables, which
  //     is the shape that silently ORs two target addresses.
  property p_one_arm;
    @(posedge clk) disable iff (!rstn)
      $onehot0(arm_win);
  endproperty

  // N2  A redirect is published exactly when a redirecting arm won.
  //     Arms 1 to 4 are corrections; arm 5 is the ordinary next
  //     block and publishes nothing. A redirect on arm 5 would
  //     rewind the queue on every prediction.
  property p_redir_is_arm_1_to_4;
    @(posedge clk) disable iff (!rstn)
      redir_val == |arm_win[4:1];
  endproperty

  // N3  THE BACKEND OUTRANKS EVERYTHING, unconditionally and
  //     without comparison (backend_interfaces 5). The other three
  //     are speculative corrections; this is architectural fact, and
  //     it is the one place FE-3's stage order does not decide the
  //     winner.
  property p_backend_wins;
    @(posedge clk) disable iff (!rstn)
      bkend_redir_val |-> arm_win[1] &&
                          (ftq_pred_pc_p0 == bkend_redir_pc) &&
                          (redir_idx == bkend_redir_idx);
  endproperty

  // N4  THE ZERO-BUBBLE LOOP. Binding Decision 3 and 4.4.
  //
  //     A SAME-CYCLE implication: when arm 5 wins, the PC presented
  //     at p0 is this cycle's p1 successor. The three arms of
  //     fe_decisions.md 2.4 are stated separately so the property
  //     covers the selection and not only the path -- an
  //     implementation that always took the fall-through would
  //     satisfy a one-arm version.
  //
  //     A REGISTERED IMPLEMENTATION FAILS THIS AND PASSES EVERY
  //     FUNCTIONAL TEST. That is why the property exists.
  //
  //     Written against slots 0 and 1 by name rather than as a
  //     loop: NUM_PRED_SLOTS is 2 and 5.6 and FE-10 both treat the
  //     count as fixed by the FTB block shape, not as a knob.
  property p_p1_combinational;
    @(posedge clk) disable iff (!rstn)
      arm_win[5] |->
        (ftq_pred_pc_p0 ==
          ((p1_slot[0].slot_valid && p1_slot[0].taken)
             ? p1_slot[0].target
             : (p1_slot[1].slot_valid && p1_slot[1].taken)
               ? p1_slot[1].target
               : p1_pft_addr));
  endproperty

  // N4a Arm 5 is the p1 arm. Stated separately so N4's same-cycle
  //     equality is anchored to a real p1 response and cannot be
  //     satisfied by an arm that fired with no prediction present.
  property p_arm5_needs_p1;
    @(posedge clk) disable iff (!rstn)
      arm_win[5] |-> p1_val;
  endproperty

  // N5  Arm 2 beats arms 3 and 4. Predecode follows fetch, which
  //     follows p1, so its entry is always older than the entry at
  //     p2 or p3 (4.3).
  property p_predecode_beats_cluster;
    @(posedge clk) disable iff (!rstn)
      (pd_redir_val && !bkend_redir_val) |->
        arm_win[2] && (ftq_pred_pc_p0 == pd_redir_pc);
  endproperty

  // N6 removed (BP-116, TD#144): w_hold |-> !pred_val restated one assign.

  // N7  The hold arm retains. When no source wins, the PC presented
  //     is the one presented last cycle. pred_pc_p1 IS the register,
  //     so the retention is stated on it directly.
  property p_hold_retains;
    @(posedge clk) disable iff (!rstn)
      (arm_win == '0) |-> (ftq_pred_pc_p0 == pred_pc_p1);
  endproperty

  // N8  pred_pc_p1 is the PC presented one cycle earlier. The entry
  //     write at p1 takes bp_ftq_entry_t.pc from it and no p1 port
  //     carries the block start, so a stale or early value here
  //     writes the wrong PC into every entry -- and every FTB and
  //     uBTB update formed from that entry then trains the wrong
  //     block.
  property p_pred_pc_p1_is_prev;
    @(posedge clk) disable iff (!rstn)
      pred_pc_p1 == r_prev_pc;
  endproperty

  // N9  RC_UNSPEC PERFORMS NO RESTORE (backend_interfaces 5.1 U5).
  //     It names no entry to restore from -- _idx is meaningless on
  //     it -- so a restore would apply some other block's checkpoint
  //     and RAS snapshot. It is the only cause that skips D1 and D2.
  property p_unspec_no_restore;
    @(posedge clk) disable iff (!rstn)
      (redir_val && (redir_cause == RC_UNSPEC)) |-> !rollback_val;
  endproperty

  // N10 The restore index derivation of 3.2. With _self CLEAR the
  //     naming entry completed and survives, so it is that entry;
  //     with _self SET the naming entry is squashed too and it is
  //     the one BEFORE it. The cluster applies the index it is given
  //     and does not validate it, so this is the only place the
  //     derivation is checked.
  property p_rollback_idx;
    @(posedge clk) disable iff (!rstn)
      rollback_val |-> (rollback_idx ==
        (redir_self ? (redir_idx - 1'b1) : redir_idx));
  endproperty

  // N11 BP-121 D14 (m13), bp_history_decisions.md 3.5 as ruled, and
  //     TD#170. A backend MISPREDICT redirect (_self clear) carries
  //     the corrected history bundle of its entry: the branches of the
  //     entry before the named position, which execution passed not
  //     taken, then the named branch with its resolved direction; at
  //     most two bits. The expected length is counted here from the
  //     entry the redirect read port returns.
  logic [1:0] w_n_exp;
  always_comb begin : n_exp
    int nb;
    nb = 0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      if (redir_entry.slot[s].slot_valid &&
          (redir_entry.slot[s].pos < bkend_redir_pos))
        nb++;
    end
    w_n_exp = (nb >= 1) ? 2'd2 : 2'd1;
  end

  property p_mispredict_bundle;
    @(posedge clk) disable iff (!rstn)
      (bkend_redir_val && (bkend_redir_cause == RC_MISPREDICT) &&
       !bkend_redir_self) |->
        rollback_corr && (rollback_n == w_n_exp) &&
        // the newest bit: index n-1, which is n[1] for n in {1, 2}
        (rollback_tkn[rollback_n[1]] == bkend_redir_taken) &&
        ((rollback_n != 2'd2) || !rollback_tkn[0]);
  endproperty

  // N12 BP-122 (TD#169). The rollback slots for the loop predictor:
  //     a slot is marked executed only under a corrected bundle, and
  //     only a conditional at or before the named position; only the
  //     named slot can be marked taken, and only with the resolved
  //     direction; the named slot, when the entry holds it as a
  //     conditional, is marked.
  property p_slot_ex_bounded(int s);
    @(posedge clk) disable iff (!rstn)
      rollback_slot_ex[s] |->
        rollback_corr && redir_entry.slot[s].slot_valid &&
        (redir_entry.slot[s].br_type == COND) &&
        (redir_entry.slot[s].pos <= bkend_redir_pos);
  endproperty

  property p_slot_tkn_named(int s);
    @(posedge clk) disable iff (!rstn)
      rollback_slot_tkn[s] |->
        rollback_slot_ex[s] && bkend_redir_taken &&
        (redir_entry.slot[s].pos == bkend_redir_pos);
  endproperty

  property p_named_slot_marked(int s);
    @(posedge clk) disable iff (!rstn)
      (rollback_corr && redir_entry.slot[s].slot_valid &&
       (redir_entry.slot[s].br_type == COND) &&
       (redir_entry.slot[s].pos == bkend_redir_pos)) |->
        rollback_slot_ex[s] && (rollback_slot_tkn[s] == bkend_redir_taken);
  endproperty

  a_mispredict_bundle:      assert property (p_mispredict_bundle)
    else $error("N11 a backend mispredict carried a wrong history bundle");
  a_slot_ex_bounded_s0:     assert property (p_slot_ex_bounded(0))
    else $error("N12 slot 0 marked executed outside the bundle");
  a_slot_ex_bounded_s1:     assert property (p_slot_ex_bounded(1))
    else $error("N12 slot 1 marked executed outside the bundle");
  a_slot_tkn_named_s0:      assert property (p_slot_tkn_named(0))
    else $error("N12 slot 0 marked taken but not the named branch");
  a_slot_tkn_named_s1:      assert property (p_slot_tkn_named(1))
    else $error("N12 slot 1 marked taken but not the named branch");
  a_named_slot_marked_s0:   assert property (p_named_slot_marked(0))
    else $error("N12 the named slot 0 was not marked");
  a_named_slot_marked_s1:   assert property (p_named_slot_marked(1))
    else $error("N12 the named slot 1 was not marked");
  a_one_arm:                assert property (p_one_arm)
    else $error("N1 more than one redirect arm won");
  a_redir_is_arm_1_to_4:    assert property (p_redir_is_arm_1_to_4)
    else $error("N2 redir_val disagrees with the winning arm");
  a_backend_wins:           assert property (p_backend_wins)
    else $error("N3 a speculative arm outranked the backend");
  a_p1_combinational:       assert property (p_p1_combinational)
    else $error("N4 the p1 successor path is not combinational");
  a_arm5_needs_p1:          assert property (p_arm5_needs_p1)
    else $error("N4a arm 5 won with no p1 response");
  a_predecode_beats:        assert property (p_predecode_beats_cluster)
    else $error("N5 a cluster arm outranked predecode");
  a_hold_retains:           assert property (p_hold_retains)
    else $error("N7 the hold arm did not retain the PC");
  a_pred_pc_p1_is_prev:     assert property (p_pred_pc_p1_is_prev)
    else $error("N8 pred_pc_p1 is not the previous p0 PC");
  a_unspec_no_restore:      assert property (p_unspec_no_restore)
    else $error("N9 RC_UNSPEC performed a restore");
  a_rollback_idx:           assert property (p_rollback_idx)
    else $error("N10 the rollback index derivation is wrong");

endmodule : ftq_npc_assert

// Bind BY MODULE NAME.
bind ftq_npc ftq_npc_assert u_assert (
  .clk                (clk),
  .rstn               (rstn),
  .bkend_redir_val    (bkend_redir_val),
  .bkend_redir_idx    (bkend_redir_idx),
  .bkend_redir_pc     (bkend_redir_pc),
  .pd_redir_val       (pd_redir_val),
  .pd_redir_pc        (pd_redir_pc),
  .p1_val             (p1_val),
  .p1_slot            (p1_slot),
  .p1_pft_addr        (p1_pft_addr),
  .ftq_pred_pc_p0     (ftq_pred_pc_p0),
  .pred_pc_p1         (pred_pc_p1),
  .redir_val          (redir_val),
  .redir_idx          (redir_idx),
  .redir_self         (redir_self),
  .redir_cause        (redir_cause),
  .rollback_val       (rollback_val),
  .rollback_idx       (rollback_idx),
  .arm_win            (arm_win),
  .bkend_redir_cause  (bkend_redir_cause),
  .bkend_redir_self   (bkend_redir_self),
  .bkend_redir_pos    (bkend_redir_pos),
  .bkend_redir_taken  (bkend_redir_taken),
  .redir_entry        (redir_entry),
  .rollback_corr      (rollback_corr),
  .rollback_n         (rollback_n),
  .rollback_tkn       (rollback_tkn),
  .rollback_slot_ex   (rollback_slot_ex),
  .rollback_slot_tkn  (rollback_slot_tkn)
);
