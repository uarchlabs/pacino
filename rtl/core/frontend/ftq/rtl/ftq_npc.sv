// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FTQ next-PC register and redirect arbitration (BP-107),
// ftq_decisions.md 4.
//
// THE FTQ IS THE REQUESTER. bp_cluster takes ftq_pred_pc_p0 as an
// INPUT and does not self-steer, so the front end's steady-state
// loop closes through this module and not through the predictors.
//
// THE ARBITER IS HERE, and 7.3 says why: four redirect sources reach
// the FTQ and 4.3 orders them by AGE. That ordering exists to answer
// one question -- what does fetch do next -- so the winner IS the
// next-PC source. Putting the arbiter anywhere else would mean
// exporting the priority result to the module that already has to
// consume it. This module publishes the winner to ftq_ptr for the
// rewind of 5.5, to ftq_status for the masked clear, and to
// ftq_commit for suppression. Those act on it; none decides it.
//
// PRIORITY, 4.2, highest first:
//
//   0  reset               the reset vector (4.7)
//   1  backend redirect    bkend_ftq_redir_pc
//   2  predecode redirect  derived from the IFU writeback
//   3  p3 redirect         bpu_redir_p3[s].target_pc
//   4  p2 redirect         bpu_redir_p2[s].target_pc
//   5  p1 successor        fe_decisions.md 2.4 across the slots
//   6  hold                retain r_next_pc, deassert the request
//
// IT IS AGE ORDER, NOT AN AXIOM (4.3). The rule that matters is that
// the correction naming the OLDEST entry wins, because everything
// younger is squashed by it anyway. The fixed priority above IS that
// order in a correctly operating pipeline: the backend is many
// stages behind fetch, predecode follows fetch which follows p1, and
// p3 lags p2 by one cycle so in a moving stream p3 names the older
// entry. When the stream is stalled the two hold the same entry and
// FE-3 decides -- the later stage wins. No wrap-aware age comparator
// is needed on this path. A future source that does NOT fit the
// depth ordering is not covered by this and 4.3 says so.
//
// THE p1 SUCCESSOR PATH IS COMBINATIONAL, and this is the one place
// in the unit where correct and correct-but-slow are
// indistinguishable to a testbench. The request for the next block
// is presented in the SAME CYCLE this block's prediction is formed:
// the p1 group drives w_sel_pc, which drives ftq_pred_pc_p0, with no
// flop between. A registered implementation passes every functional
// test and costs a cycle on every prediction. This is the critical
// loop of the front end and the reason the uBTB exists (4.4).
//
// Redirect targets do NOT get the same treatment and do not need it.
// A redirect has already cost the cycles between the mispredicted
// block and the correcting stage, so a register stage there is off
// the critical loop. The four redirect sources are REGISTERED by
// their producers -- bpu_redir_p2/p3 are cluster stage outputs, the
// backend group is a backend output, and the predecode redirect is
// derived in ftq_ifu from a registered writeback -- so this module
// muxes them straight through and adds no stage of its own.
//
// THE REGISTER OF 4.1 IS STILL A REGISTER. It captures the selected
// value every cycle and supplies arm 6, the hold. 4.5 says
// "r_next_val deasserts and r_next_pc holds": the deassert is on the
// OUTPUT valid, and the hold is the register retaining what it
// captured. Both are built.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_npc (
  input  logic                     clk,
  input  logic                     rstn,

  // ---- arm 1, the backend redirect --------------------------------
  input  logic                     bkend_redir_val,
  input  logic [FTQ_IDX_BITS-1:0]  bkend_redir_idx,
  input  logic [VA_WIDTH-1:0]      bkend_redir_pc,
  input  logic                     bkend_redir_self,
  input  ftq_redir_cause_e         bkend_redir_cause,

  // ---- arm 2, the predecode redirect, from ftq_ifu ----------------
  // Always RC_MISPREDICT in cause and always _self CLEAR: the
  // predecode correction repairs the naming entry and fetch resumes
  // from its corrected successor (ftq_ifu_interfaces.md 7 W3), so
  // the entry survives.
  input  logic                     pd_redir_val,
  input  logic [FTQ_IDX_BITS-1:0]  pd_redir_idx,
  input  logic [VA_WIDTH-1:0]      pd_redir_pc,

  // ---- arms 3 and 4, the cluster redirects ------------------------
  // Already qualified by the shadow of 5.6 before they arrive: a
  // group naming a squashed entry is dropped there, not here.
  input  logic                     p3_redir_val,
  input  logic [FTQ_IDX_BITS-1:0]  p3_redir_idx,
  input  bp_redirect_t             p3_redir [0:NUM_PRED_SLOTS-1],
  input  logic                     p2_redir_val,
  input  logic [FTQ_IDX_BITS-1:0]  p2_redir_idx,
  input  bp_redirect_t             p2_redir [0:NUM_PRED_SLOTS-1],

  // ---- arm 5, the p1 successor ------------------------------------
  // THE ZERO-BUBBLE PATH. Combinational to ftq_pred_pc_p0.
  input  logic                     p1_val,
  input  bp_ftq_slot_t             p1_slot [0:NUM_PRED_SLOTS-1],
  input  logic [VA_WIDTH-1:0]      p1_pft_addr,

  // ---- hold conditions, 4.5 ----------------------------------------
  //   H1  a queued predictor cannot accept a request. The cluster
  //       has NO request-ready output, so ftq_bpu_interfaces.md 3
  //       makes this the FTQ's obligation.
  //   H2  the FTQ has no free entry.
  //   R1  a live entry faulted (ftq_entry_formats.md 4.3 R1). NOT
  //       one of 4.5's two conditions; see the Results Capture.
  //
  // NOT a hold: ftq_ifu_req_rdy low. The IFU being unable to accept
  // a fetch does not stop the FTQ predicting ahead -- that is the
  // point of a decoupled front end. There is no port for it here.
  // H1 is taken as the three queue-status outputs themselves rather
  // than as a precomputed term, so 4.5's list is the port list and
  // ftq.sv adds no gate of its own (7.1).
  input  logic                     tage_pq_not_full,
  input  logic                     ittage_pq_not_full,
  input  logic                     sc_uq_not_full,
  input  logic                     h2_ftq_full,
  input  logic                     r1_fault_hold,

  // ---- the p0 request, to bp_cluster -------------------------------
  output logic                     ftq_pred_val_p0,
  output logic [VA_WIDTH-1:0]      ftq_pred_pc_p0,

  // ---- the p0 PC, one cycle later ----------------------------------
  // A PORT 7.3 DOES NOT ANTICIPATE. bp_ftq_entry_t.pc is the fetch
  // block start PC and the entry is written at p1, but NO p1 port
  // carries the PC back: bpu_pred_slot_p1 is per-slot,
  // bpu_pred_pft_p1 is the fall-through, and the block start exists
  // only as the ftq_pred_pc_p0 the FTQ itself issued a cycle
  // earlier. So the FTQ has to stage it, and r_next_pc already IS
  // that value one cycle on -- it captured w_sel_pc, which is what
  // went out at p0. Publishing it costs no state.
  //
  // The alternative homes are worse: ftq_entry would have to hold a
  // PC register, which is not its state, and ftq_shadow would have
  // to widen by VA_WIDTH per stage to carry something only stage 1
  // ever needs. Reported in the BP-107 Results Capture.
  output logic [VA_WIDTH-1:0]      pred_pc_p1,

  // ---- the winning redirect, to ftq_ptr / _status / _commit -------
  output logic                     redir_val,
  output logic [FTQ_IDX_BITS-1:0]  redir_idx,
  output logic                     redir_self,
  output ftq_redir_cause_e         redir_cause,

  // ---- the restore, D1 and D2 of backend_interfaces 5 -------------
  // rollback_idx names the entry whose END-of-block pointer state is
  // to be restored, which is the FTQ's derivation and not the
  // cluster's: on _self clear that is the redirecting entry itself,
  // on _self set the naming entry is squashed too and it is the one
  // before it (ftq_decisions.md 3.2). It also addresses ftq_entry's
  // redirect read port, so the RAS snapshot presented on
  // ras_restore_snapshot comes from the same entry.
  //
  // SKIPPED ON RC_UNSPEC. U5: there is no entry to restore from and
  // both structures are self-correcting from committed state.
  output logic                     rollback_val,
  output logic [FTQ_IDX_BITS-1:0]  rollback_idx,

  // ---- observation, for the bound properties -----------------------
  // The arm that won, one-hot, arms 1 to 5. Zero means arm 6, hold.
  output logic [5:1]               arm_win
);

  // The successor selection of fe_decisions.md 2.4, formed from the
  // LIVE p1 group. This is the combinational term.
  logic [VA_WIDTH-1:0] w_p1_succ;

  // The per-arm redirect terms, reduced across slots.
  logic                w_p2_slot;
  logic                w_p3_slot;
  logic                w_p2_any;
  logic                w_p3_any;
  logic [VA_WIDTH-1:0] w_p2_pc;
  logic [VA_WIDTH-1:0] w_p3_pc;

  logic                w_hold;
  logic [VA_WIDTH-1:0] w_sel_pc;

  logic [VA_WIDTH-1:0] r_next_pc;

  // -----------------------------------------------------------------
  // Arm 5: the p1 successor, fe_decisions.md 2.4.
  // -----------------------------------------------------------------
  // Priority top to bottom across the slots:
  //
  //   slot 0 valid and taken   ->  slot 0 target
  //   slot 1 valid and taken   ->  slot 1 target
  //   otherwise                ->  the fall-through address
  //
  // The fall-through arrives on bpu_pred_pft_p1 and is the not-taken
  // arm (TD#108). It is one value per prediction, qualified by the
  // p1 valid and carrying no valid of its own.
  //
  // Written as a descending loop so the LOWEST valid taken slot ends
  // up assigned last and therefore wins. That is program order:
  // slot 0 is the block's first branch (FE-10, IC-FTB-16), and a
  // taken branch ends the block, so no later slot is on the path.
  always_comb begin : p1_successor
    w_p1_succ = p1_pft_addr;
    for (int s = NUM_PRED_SLOTS - 1; s >= 0; s--) begin
      if (p1_slot[s].slot_valid && p1_slot[s].taken) begin
        w_p1_succ = p1_slot[s].target;
      end
    end
  end

  // -----------------------------------------------------------------
  // Arms 3 and 4: reduce the cluster groups across slots.
  // -----------------------------------------------------------------
  // bp_redirect_t is per slot and the index is scalar alongside it,
  // since both slots occupy one FTQ entry. A redirect fires when a
  // slot's successor differs from the p1 view, so the LOWEST
  // redirecting slot is the one that resteers -- the same program
  // order argument as the successor selection.
  always_comb begin : cluster_arms
    w_p2_slot = 1'b0;
    w_p3_slot = 1'b0;
    w_p2_pc   = '0;
    w_p3_pc   = '0;
    for (int s = NUM_PRED_SLOTS - 1; s >= 0; s--) begin
      if (p2_redir[s].valid) begin
        w_p2_slot = 1'b1;
        w_p2_pc   = p2_redir[s].target_pc;
      end
      if (p3_redir[s].valid) begin
        w_p3_slot = 1'b1;
        w_p3_pc   = p3_redir[s].target_pc;
      end
    end

    // The group valid is the shadow's verdict: a group naming a
    // squashed entry is dropped there (5.6). Kept as a separate net
    // from the slot reduction rather than folded back into it --
    // reassigning w_p2_slot from itself reads as circular
    // combinational logic and Verilator reports it as UNOPTFLAT.
    w_p2_any = w_p2_slot & p2_redir_val;
    w_p3_any = w_p3_slot & p3_redir_val;
  end

  // -----------------------------------------------------------------
  // The arbitration, 4.2, and the register of 4.1.
  // -----------------------------------------------------------------
  // One always_comb in priority order rather than a chain of
  // assigns: every term below depends on the ones above it, and
  // CLAUDE.md requires the textual-order form for a dependency
  // chain. It is also what makes the priority READ as the priority.
  always_comb begin : arbitrate
    // 4.5. The hold gates the OUTPUT valid; the register retains
    // what it captured either way.
    w_hold = ~tage_pq_not_full | ~ittage_pq_not_full |
             ~sc_uq_not_full    |  h2_ftq_full | r1_fault_hold;

    arm_win     = '0;
    redir_val   = 1'b0;
    redir_idx   = '0;
    redir_self  = 1'b0;
    redir_cause = RC_MISPREDICT;

    if (bkend_redir_val) begin
      // Arm 1. A backend redirect OUTRANKS every BPU-derived
      // redirect and the predecode redirect, unconditionally and
      // without comparison: those are speculative corrections, this
      // is architectural fact (backend_interfaces 5). It is the one
      // place FE-3's stage order does not decide the winner.
      arm_win[1]  = 1'b1;
      w_sel_pc    = bkend_redir_pc;
      redir_val   = 1'b1;
      redir_idx   = bkend_redir_idx;
      redir_self  = bkend_redir_self;
      redir_cause = bkend_redir_cause;
    end else if (pd_redir_val) begin
      // Arm 2. Predecode follows fetch, which follows p1, so its
      // entry is always older than the entry at p2 or p3.
      arm_win[2]  = 1'b1;
      w_sel_pc    = pd_redir_pc;
      redir_val   = 1'b1;
      redir_idx   = pd_redir_idx;
      redir_self  = 1'b0;
      redir_cause = RC_MISPREDICT;
    end else if (w_p3_any) begin
      // Arm 3. p3 lags p2 by one cycle, so in a moving stream it
      // names the older entry; when the stream is stalled the two
      // hold the same entry and FE-3 gives the later stage. Either
      // way p3 outranks p2, which is what 4.3 argues.
      arm_win[3]  = 1'b1;
      w_sel_pc    = w_p3_pc;
      redir_val   = 1'b1;
      redir_idx   = p3_redir_idx;
      redir_self  = 1'b0;
      redir_cause = RC_MISPREDICT;
    end else if (w_p2_any) begin
      arm_win[4]  = 1'b1;
      w_sel_pc    = w_p2_pc;
      redir_val   = 1'b1;
      redir_idx   = p2_redir_idx;
      redir_self  = 1'b0;
      redir_cause = RC_MISPREDICT;
    end else if (p1_val) begin
      // Arm 5. THE ZERO-BUBBLE PATH. No redirect is published: the
      // successor is the ordinary next block, not a correction.
      arm_win[5]  = 1'b1;
      w_sel_pc    = w_p1_succ;
    end else begin
      // Arm 6. Hold. Retain r_next_pc.
      w_sel_pc    = r_next_pc;
    end

    // 4.1 names a valid beside the register, r_next_val. It is
    // CONSTANT TRUE after reset in the built design and is not
    // carried as state: arm 0 loads the register with the reset
    // vector, and every arm above replaces it with another real
    // address, so the register never holds a meaningless value and
    // there is no event that would clear the valid. The only thing
    // that deasserts the request is the hold of 4.5, which is what
    // "r_next_val deasserts and r_next_pc holds" describes. Carrying
    // a flop that could never be zero would be dead state.
    // Reported in the BP-107 Results Capture.
    ftq_pred_pc_p0  = w_sel_pc;
    ftq_pred_val_p0 = ~w_hold;
  end

  // -----------------------------------------------------------------
  // The restore index, ftq_decisions.md 3.2.
  // -----------------------------------------------------------------
  // The index names the entry whose END-of-block pointer state is to
  // be restored. With _self CLEAR the naming entry completed and
  // survives, so it is that entry. With _self SET the naming entry
  // is squashed too, so it is the one BEFORE it.
  //
  // Only the backend group carries _self; the three speculative arms
  // are all _self clear by construction, so the subtraction is only
  // ever taken on arm 1. It is written against redir_self rather
  // than against the arm so a future _self-carrying source needs no
  // change here.
  //
  // RC_UNSPEC performs NO restore (U5). It is the only cause that
  // does not, and the reason is that it names no entry to restore
  // from -- _idx is meaningless on it, so the index this block
  // computes would be meaningless too.
  always_comb begin : restore
    rollback_val = redir_val && (redir_cause != RC_UNSPEC);
    rollback_idx = redir_self ? (redir_idx - 1'b1) : redir_idx;
  end

  // -----------------------------------------------------------------
  // State. Arm 0 of 4.2 is the reset.
  // -----------------------------------------------------------------
  // RESET_VECTOR is bp_defines_pkg's, VA_WIDTH wide, block aligned,
  // 40'h00_8000_0000 by default (4.7). It is ISSUED, not merely
  // held: with no hold asserted the first thing the front end does
  // is request it, in the first cycle out of reset.
  //
  // The capture is UNCONDITIONAL. It has to be: a request presented
  // and not accepted -- H1 or H2 -- must still be retained, and the
  // hold arm reads exactly this register to retain it. Capturing
  // only on acceptance would lose the successor of a p1 response
  // that arrived in a stalled cycle.
  assign pred_pc_p1 = r_next_pc;

  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      r_next_pc <= RESET_VECTOR;
    end else begin
      r_next_pc <= w_sel_pc;
    end
  end

endmodule : ftq_npc
