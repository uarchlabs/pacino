// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FTQ side of the IFU boundary (BP-107), ftq_ifu_interfaces.md.
//
// THE IFU DOES NOT EXIST. rtl/core/frontend/ifu/rtl holds a
// .gitkeep. This is the FTQ half of the contract and nothing else;
// the testbench models the other side.
//
// FIVE JOBS, and they are the five groups of the interface:
//
//   4.1 the translation request, driven from xlate_ptr (BP-112,
//      TD#127). Decoupled like the fetch request and flow controlled
//      independently of it.
//   4  the fetch request. Decoupled -- the FTQ presents, the IFU
//      accepts when its first stage is free. ftq_ifu_commit_ptr
//      rides on this group with no handshake (BP-114, TD#142).
//   5  the flush. ONE group, not two: the FTQ has already resolved
//      stage supersession before anything leaves it (FE-3), so
//      exporting both stages would ask the IFU to redo a decision
//      the FTQ has made.
//   6  the predecode writeback, and the generation test of 6.1.
//   7  what the writeback does to the entry, and the predecode
//      redirect derived from it.
//
// THE GENERATION BIT, 6.1. A writeback in flight when its entry is
// squashed and its index REALLOCATED would arrive after the new
// allocation cleared the status bits and set them on the wrong use
// of the index. One bit, ftq_ifu_gen out with the request and
// ifu_ftq_pdwb_gen back, TOGGLED each time the entry is allocated
// (the toggle is in ftq_status). A writeback whose tag does not
// match is DROPPED ENTIRELY: no status bit set, no redirect
// derived, no field rewritten.
//
// ONE BIT IS SUFFICIENT BECAUSE OF A BOUND, NOT ARITHMETIC. A single
// bit fails if the same index is reallocated TWICE while one
// writeback is outstanding, because the second toggle restores the
// original value. Section 5 has the IFU discard everything it holds
// for flushed entries, so the only stale writeback that survives a
// redirect is one already presented in the flush cycle, and it
// arrives immediately. IF THE IFU FLUSH CONTRACT CHANGES so a
// writeback can survive arbitrarily long after a flush, the width
// must be revisited.
//
// NO PREDICTOR UPDATE IS FORMED HERE (FE-8, section 7). A structural
// mispredict corrects the ENTRY and redirects; the predictors learn
// it when the branch resolves. Forming an update here would give
// them two producers in different orders and break FE-6. There is
// no update port on this module and that absence is the rule.
//
// THERE IS NO SEPARATE IFU-TO-FTQ REDIRECT PORT. The redirect is
// DERIVED from the writeback, exactly as XiangShan does; a second
// path would let the two disagree.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_ifu (
  // COMBINATIONAL MODULE. It holds no state: the entry, the status
  // bits and the pointers are all owned elsewhere and arrive as
  // inputs, and every output is a function of this cycle's inputs.
  // clk and rstn are here for the CONCURRENT SVA bound to this
  // module by name -- a concurrent property needs a clock and a
  // disable, and TD#109 requires the bind to read the port list and
  // make no hierarchical reference. CLAUDE.md's rule that a
  // combinational module does not require them is satisfied by
  // "only as needed"; these are needed.
  input  logic                     clk,
  input  logic                     rstn,

  // ---- from ftq_ptr, the entry to translate ------------------------
  input  logic [FTQ_IDX_BITS-1:0]  xlate_idx,
  input  logic                     xlate_pending,

  // ---- from ftq_entry, bp_ftq_entry_t.pc at xlate_idx ---------------
  input  logic [VA_WIDTH-1:0]      xlate_pc,

  // ---- from ftq_ptr, the entry to request --------------------------
  input  logic [FTQ_IDX_BITS-1:0]  fetch_idx,
  input  logic                     fetch_pending,

  // ---- from ftq_entry, the entry at fetch_idx ----------------------
  input  bp_ftq_entry_t            fetch_entry,

  // ---- from ftq_commit, the oldest live entry ----------------------
  // FTQ_PTR_BITS, as ftq_commit owns it. Only the index is read: it is
  // exported on section 4 as ftq_ifu_commit_ptr, and it is the flush
  // index of an RC_UNSPEC redirect. The wrap bit has no reader here.
  input  logic [FTQ_PTR_BITS-1:0]  commit_ptr,

  // ---- from ftq_status ---------------------------------------------
  // gen_fetch is gen[fetch_idx], the tag that leaves with the
  // request. gen_pdwb is gen[ifu_ftq_pdwb_idx], the tag the
  // writeback is tested against.
  input  logic                     gen_fetch,
  input  logic                     gen_pdwb,
  // R3 of ftq_entry_formats.md 4.3: an entry derives AT MOST ONE
  // predecode redirect, and only from its own writeback. A second
  // writeback naming an entry that already has the bit set derives
  // no redirect. It is LEGAL, not a protocol violation (R3a): the W3
  // refetch of a predecode-redirected entry produces it by design.
  input  logic                     wb_rcvd_pdwb,

  // ---- from ftq_entry, the entry the writeback names ---------------
  input  bp_ftq_entry_t            pdwb_entry,

  // ---- the winning redirect, from ftq_npc --------------------------
  // Drives the flush group of section 5. EVERY source resolves into
  // this one group: p2, p3, predecode and backend.
  input  logic                     redir_val,
  input  logic [FTQ_IDX_BITS-1:0]  redir_idx,
  input  logic                     redir_self,
  input  ftq_redir_cause_e         redir_cause,
  // The winning arm, one-hot, as numbered on ftq_npc's arm_win. The
  // SOURCE of the redirect is visible nowhere else: p2, p3 and
  // predecode arrive as RC_MISPREDICT with _self clear, which is also
  // how a backend mispredict whose entry survives arrives.
  input  logic [5:1]               redir_arm,

  // ---- section 4.1, the translation request ------------------------
  output logic                     ftq_ifu_xlate_val,
  input  logic                     ftq_ifu_xlate_rdy,
  output logic [VA_WIDTH-1:0]      ftq_ifu_xlate_pc,
  output logic [FTQ_IDX_BITS-1:0]  ftq_ifu_xlate_idx,

  // ---- section 4, the fetch request --------------------------------
  output logic                     ftq_ifu_req_val,
  input  logic                     ftq_ifu_req_rdy,
  output logic [VA_WIDTH-1:0]      ftq_ifu_start_pc,
  output logic [VA_WIDTH-1:0]      ftq_ifu_next_pc,
  output logic [FTQ_IDX_BITS-1:0]  ftq_ifu_idx,
  output logic                     ftq_ifu_taken_val,
  output logic [FTB_BR_POS_BITS-1:0] ftq_ifu_taken_pos,
  output logic                     ftq_ifu_gen,
  // IFU-22. Driven continuously: no valid, and not part of the
  // request handshake (BP-114, TD#142).
  output logic [FTQ_IDX_BITS-1:0]  ftq_ifu_commit_ptr,

  // ---- section 5, the flush ----------------------------------------
  output logic                     ftq_ifu_flush_val,
  output logic [FTQ_IDX_BITS-1:0]  ftq_ifu_flush_idx,

  // ---- section 6, the predecode writeback --------------------------
  input  logic                     ifu_ftq_pdwb_val,
  input  logic [FTQ_IDX_BITS-1:0]  ifu_ftq_pdwb_idx,
  input  logic                     ifu_ftq_pdwb_gen,
  input  ftq_pd_info_t             ifu_ftq_pd [0:FTQ_PD_WIDTH-1],
  input  logic [FTQ_PD_WIDTH-1:0]  ifu_ftq_pd_range,
  input  logic                     ifu_ftq_cfi_val,
  input  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_cfi_pos,
  input  logic                     ifu_ftq_mis_val,
  input  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_mis_pos,
  input  logic [VA_WIDTH-1:0]      ifu_ftq_target,
  input  logic                     ifu_ftq_fault_val,
  input  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_fault_pos,

  // ---- to ftq_status, W2 and W3 ------------------------------------
  output logic                     wb_set_val,
  output logic [FTQ_IDX_BITS-1:0]  wb_set_idx,
  output logic                     fault_set_val,
  output logic [FTQ_IDX_BITS-1:0]  fault_set_idx,

  // ---- to ftq_entry, the section 7 W1 slot correction --------------
  output logic                     pd_wr_val,
  output logic [FTQ_IDX_BITS-1:0]  pd_wr_idx,
  output logic [TRX_SLOT_BITS-1:0] pd_wr_sel,
  output bp_ftq_slot_t             pd_wr_slot,
  output logic                     pd_wr_kill,

  // ---- to ftq_npc, arm 2 -------------------------------------------
  output logic                     pd_redir_val,
  output logic [FTQ_IDX_BITS-1:0]  pd_redir_idx,
  output logic [VA_WIDTH-1:0]      pd_redir_pc,

  // ---- observation, for the bound properties -----------------------
  // wb_accept is the 6.1 X3 gate: the writeback passed the
  // generation test. wb_drop_gen is the same writeback failing it.
  output logic                     wb_accept,
  output logic                     wb_drop_gen
);

  // The arms of ftq_npc's arbitration (ftq_decisions.md 4.2), as
  // numbered on arm_win. Arm 5 is the p1 successor and publishes no
  // redirect.
  localparam int ARM_BKEND = 1;
  localparam int ARM_PD    = 2;
  localparam int ARM_P3    = 3;
  localparam int ARM_P2    = 4;
  localparam int ARM_P1    = 5;

  // The redirect is one of the front-end causes of W3.
  logic                w_fe_redir;

  // The predecode slot the writeback names, and the bp_ftq_slot_t
  // built from it.
  ftq_pd_info_t        w_pd_at_mis;
  bp_br_type_e         w_pd_br_type;
  logic                w_pd_is_cfi;
  logic                w_pd_has_target;
  bp_ftq_slot_t        w_new_slot;

  // The corrected slot array, and the successor re-derived over it.
  bp_ftq_slot_t        w_corr_slot [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] w_corr_succ;

  logic [TRX_SLOT_BITS-1:0] w_sel;
  logic                     w_sel_found;

  // -----------------------------------------------------------------
  // Section 4.1. The translation request.
  // -----------------------------------------------------------------
  // The same entry is presented twice: here first, from xlate_ptr,
  // and on the fetch request later, from fetch_ptr. The two pointers
  // reach it at different times, so the pc is read twice.
  //
  // xlate_pending is the 5.1 run-ahead measured from xlate_ptr to the
  // WRITTEN frontier, so an entry whose p1 write has not landed is
  // never presented. The acceptance advances xlate_ptr, which is
  // ftq_ptr's state, so ftq_ifu_xlate_rdy is consumed there.
  //
  // NO RESULT RETURNS. The translation lands in the IFU's own queue
  // (IFU-25) and the FTQ never sees a physical address. Nor does the
  // request carry a generation tag: the one-bit scheme of 6.1 is on
  // the fetch request and the writeback, and no second scheme is
  // built for this port.
  always_comb begin : xlate_request
    ftq_ifu_xlate_val = xlate_pending;
    ftq_ifu_xlate_idx = xlate_idx;
    ftq_ifu_xlate_pc  = xlate_pc;
  end

  // -----------------------------------------------------------------
  // Section 4. The fetch request.
  // -----------------------------------------------------------------
  // ftq_ifu_next_pc is the block successor, the fe_decisions.md 2.4
  // selection over the ENTRY'S slots. The IFU does not recompute it:
  // it exists so the IFU knows where the block ends without reading
  // the prediction. The same selection appears in ftq_npc over the
  // LIVE p1 group and here over the STORED entry, and the two
  // sources are genuinely different -- the p1 group is present only
  // in the p1 cycle and the entry is what survives a redirect
  // rewriting a slot (2.4).
  //
  // ftq_ifu_taken_val / _pos name the predicted taken branch so the
  // IFU truncates the bundle there. Not valid means fetch the whole
  // block.
  //
  // The request is presented in FTQ entry order and only for an
  // entry whose translation has been presented and whose fetch has
  // not yet issued, which is exactly fetch_pending (FQ-1).
  //
  // ftq_ifu_commit_ptr is DRIVEN CONTINUOUSLY from commit_ptr, in
  // every cycle and independent of fetch_pending and
  // ftq_ifu_req_rdy. It carries no valid and is not part of the
  // handshake (section 4, IFU-22). It exists for uncached fetch
  // alone: the IFU issues an uncached block's bus read only when the
  // block's index equals this pointer, meaning everything older has
  // committed. A cached fetch never reads it.
  always_comb begin : request
    ftq_ifu_req_val    = fetch_pending;
    ftq_ifu_idx        = fetch_idx;
    ftq_ifu_gen        = gen_fetch;
    ftq_ifu_commit_ptr = commit_ptr[FTQ_IDX_BITS-1:0];
    ftq_ifu_start_pc  = fetch_entry.pc;
    ftq_ifu_next_pc   = fetch_entry.pft_addr;
    ftq_ifu_taken_val = 1'b0;
    ftq_ifu_taken_pos = '0;

    // Descending, so the LOWEST valid taken slot is assigned last
    // and wins. Program order: slot 0 is the block's first branch
    // (FE-10, IC-FTB-16) and a taken branch ends the block.
    for (int s = NUM_PRED_SLOTS - 1; s >= 0; s--) begin
      if (fetch_entry.slot[s].slot_valid &&
          fetch_entry.slot[s].taken) begin
        ftq_ifu_next_pc   = fetch_entry.slot[s].target;
        ftq_ifu_taken_val = 1'b1;
        ftq_ifu_taken_pos = fetch_entry.slot[s].pos;
      end
    end
  end

  // -----------------------------------------------------------------
  // Section 5. The flush.
  // -----------------------------------------------------------------
  // Drop every in-flight fetch whose index is AT OR AFTER the flush
  // index, and discard whatever the IFU holds for those entries.
  //
  // The index is the first entry to drop, the flush index F of 5.5
  // R1. It is K or K+1 BY SOURCE, not by _self alone:
  //
  //   p2, p3, predecode      K.   7 W3 and ifu_ibuf_interfaces.md
  //                               IB-13. K SURVIVES, CORRECTED, and
  //                               must be fetched again: the
  //                               correction changes taken_val and
  //                               taken_pos, which is what the IFU
  //                               truncates on, so a fetch of K issued
  //                               against the old prediction ends in
  //                               the wrong place. For predecode K is
  //                               already fetched and including it
  //                               costs nothing.
  //   backend, _self set     K.   K does not survive.
  //   backend, _self clear   K+1. K's instructions stand, and
  //                               refetching K would deliver them
  //                               twice (ftq_backend_interfaces.md 5
  //                               D5).
  //
  // The front-end set is named by arm because every member arrives
  // _self clear, the same encoding as the backend K+1 row. Keying on
  // _self alone was TD#126: K+1 for a surviving entry on every cause.
  //
  //   RC_UNSPEC              commit_ptr. ftq_backend_interfaces.md
  //                               5.1 U3 squashes EVERY entry, and U1
  //                               and U2 make _idx and _self
  //                               meaningless, so neither is read.
  //                               The live window starts at
  //                               commit_ptr, so its index is the one
  //                               flush index that drops every
  //                               in-flight fetch. It is also where
  //                               ftq_ptr rewinds xlate_ptr and
  //                               fetch_ptr on this cause. fetch_idx
  //                               left the fetches between commit_ptr
  //                               and fetch_ptr unflushed (BP-114,
  //                               TD#141).
  //
  // A flush and a request may be presented in the same cycle. The
  // flush applies first and the accompanying request is the first
  // fetch of the corrected stream; that is the IFU's obligation,
  // stated in section 5, and needs nothing here.
  always_comb begin : flush
    w_fe_redir = redir_arm[ARM_PD] | redir_arm[ARM_P3] |
                 redir_arm[ARM_P2];

    ftq_ifu_flush_val = redir_val;
    if (redir_cause == RC_UNSPEC) begin
      ftq_ifu_flush_idx = commit_ptr[FTQ_IDX_BITS-1:0];
    end else if (w_fe_redir) begin
      ftq_ifu_flush_idx = redir_idx;
    end else if (redir_self) begin
      ftq_ifu_flush_idx = redir_idx;
    end else begin
      ftq_ifu_flush_idx = redir_idx + 1'b1;
    end
  end

  // -----------------------------------------------------------------
  // Section 6.1. The generation test.
  // -----------------------------------------------------------------
  always_comb begin : gen_test
    wb_accept   = ifu_ftq_pdwb_val &&  (ifu_ftq_pdwb_gen == gen_pdwb);
    wb_drop_gen = ifu_ftq_pdwb_val && !(ifu_ftq_pdwb_gen == gen_pdwb);
  end

  // -----------------------------------------------------------------
  // Section 7. What the writeback does to the entry.
  // -----------------------------------------------------------------
  // W1  rewrite the named slot: slot_valid, br_type and taken from
  //     the predecode info, target from ifu_ftq_target when
  //     predecode computed one. pred_src becomes PRED_NONE -- no
  //     predictor supplied this, and the field is diagnostic
  //     (TD-FE-4).
  // W2  ifu_ftq_mis_pos goes STRAIGHT into bp_ftq_slot_t.pos. The
  //     two widths are equal and the conversion is the identity
  //     (section 3). Written with an explicit width equality check
  //     below rather than a shift, because it WAS a lossy shift
  //     until the position field was widened.
  // W3  re-derive the block successor over the corrected slots and
  //     drive the flush with this entry's index, so fetch restarts
  //     from the corrected successor. The flush index falls out of
  //     the redirect this module publishes to ftq_npc and comes back
  //     as redir_idx, so W3's flush is the section 5 group above and
  //     not a second one.
  // W4  restore the history pointers and the RAS snapshot from this
  //     entry. Also falls out: ftq_npc drives rollback_val and
  //     ras_restore_val from the winning redirect, and the predecode
  //     redirect is one of its arms, so the restore is the same one
  //     a p2 or p3 redirect performs and is not duplicated here.
  //
  // WHICH SLOT. The documents say "the named slot" and do not say
  // how a position names one when no slot holds it -- the M1 case,
  // where the block was predicted to have no taken branch and
  // predecode found an unconditional one. The rule built here is
  // program order, which is what FE-10 and IC-FTB-16 already make
  // the slot array:
  //
  //   the lowest slot s with slot_valid clear, or with pos at or
  //   after mis_pos; every slot above s is killed
  //
  // A predecode-found branch at mis_pos is taken, so everything
  // after it in the block is off the path and the kill is not
  // optional. This rule is an implementation decision, not a
  // reading of the documents; reported in the BP-107 Results
  // Capture.
  always_comb begin : predecode_correct
    w_pd_at_mis = ifu_ftq_pd[ifu_ftq_mis_pos];

    // The predecode classification is two bits plus is_call and
    // is_ret (ftq_pd_info_t). Map it onto bp_br_type_e.
    //   00 not CFI, 01 branch, 10 jal, 11 jalr
    w_pd_is_cfi = w_pd_at_mis.valid && (w_pd_at_mis.br_type != 2'b00);
    unique case (w_pd_at_mis.br_type)
      2'b01:   w_pd_br_type = COND;
      2'b10:   w_pd_br_type = w_pd_at_mis.is_call ? DIRECT_CALL
                                                  : DIRECT_UNC;
      2'b11:   w_pd_br_type = w_pd_at_mis.is_ret  ? RETURN
                            : (w_pd_at_mis.is_call ? INDIRECT_CALL
                                                   : INDIRECT_NONRET);
      default: w_pd_br_type = NO_BRANCH;
    endcase

    // Predecode computes a target for every DIRECT branch and JAL.
    // For JALR ifu_ftq_target carries no meaning and is not read
    // (section 6), so the entry's own target stands.
    w_pd_has_target = w_pd_is_cfi && (w_pd_at_mis.br_type != 2'b11);

    w_new_slot.slot_valid = w_pd_is_cfi;
    w_new_slot.br_type    = w_pd_br_type;
    // Predecode proves a direction only for an unconditional. A
    // conditional's direction it cannot know, and TAGE and SC
    // already own it (section 6), so the entry's prediction stands
    // for the COND case.
    w_new_slot.taken      = w_pd_is_cfi && (w_pd_br_type != COND);
    w_new_slot.target     = w_pd_has_target ? ifu_ftq_target
                          : pdwb_entry.slot[0].target;
    // W2. The identity conversion, guarded: if the two position
    // widths ever diverge again this drives zero rather than
    // silently truncating, and the guard is the record of why.
    w_new_slot.pos        = (FTQ_PD_POS_BITS == FTB_BR_POS_BITS)
                          ? FTB_BR_POS_BITS'(ifu_ftq_mis_pos) : '0;
    w_new_slot.pred_src   = PRED_NONE;
    w_new_slot.confidence = '0;

    // Program-order slot placement. Descending so the lowest
    // qualifying slot is assigned last and wins.
    w_sel       = '0;
    w_sel_found = 1'b0;
    for (int s = NUM_PRED_SLOTS - 1; s >= 0; s--) begin
      if (!pdwb_entry.slot[s].slot_valid ||
          (pdwb_entry.slot[s].pos >=
             FTB_BR_POS_BITS'(ifu_ftq_mis_pos))) begin
        w_sel       = TRX_SLOT_BITS'(s);
        w_sel_found = 1'b1;
      end
    end
    // Every slot is valid and every position is below mis_pos: the
    // new branch is later than both, so it takes the last slot and
    // nothing above it survives to be killed.
    if (!w_sel_found) begin
      w_sel = TRX_SLOT_BITS'(NUM_PRED_SLOTS - 1);
    end

    // The corrected array, used only to re-derive the successor.
    // ftq_entry applies the same correction to its own copy from
    // pd_wr_*; this is the combinational view of the result, which
    // W3 needs in the SAME cycle and cannot wait a clock for.
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      if (TRX_SLOT_BITS'(s) == w_sel) begin
        w_corr_slot[s] = w_new_slot;
      end else if (TRX_SLOT_BITS'(s) > w_sel) begin
        w_corr_slot[s]            = pdwb_entry.slot[s];
        w_corr_slot[s].slot_valid = 1'b0;
        w_corr_slot[s].taken      = 1'b0;
      end else begin
        w_corr_slot[s] = pdwb_entry.slot[s];
      end
    end

    // W3. fe_decisions.md 2.4 over the corrected slots.
    w_corr_succ = pdwb_entry.pft_addr;
    for (int s = NUM_PRED_SLOTS - 1; s >= 0; s--) begin
      if (w_corr_slot[s].slot_valid && w_corr_slot[s].taken) begin
        w_corr_succ = w_corr_slot[s].target;
      end
    end
  end

  // -----------------------------------------------------------------
  // Outputs of the writeback path.
  // -----------------------------------------------------------------
  // R3 qualifies the REDIRECT, not the status set. An entry derives
  // at most one predecode redirect and only from its own writeback;
  // a second writeback naming an entry that already has wb_rcvd set
  // derives none, whatever its predecode result. That second
  // writeback is EXPECTED (R3a, session-073, TD#140): a predecode
  // redirect on K flushes at K and K is fetched again (7 W3), so its
  // writeback returns with wb_rcvd set and gen[K] unchanged. It is
  // accepted by 6.1 X3 like any other, and R3's bound is what stops
  // a refetch loop. The status set is idempotent -- setting a bit
  // that is already set is a no-op -- so it is not gated.
  always_comb begin : wb_outputs
    wb_set_val    = wb_accept;
    wb_set_idx    = ifu_ftq_pdwb_idx;
    fault_set_val = wb_accept & ifu_ftq_fault_val;
    fault_set_idx = ifu_ftq_pdwb_idx;

    pd_redir_val  = wb_accept & ifu_ftq_mis_val & ~wb_rcvd_pdwb;
    pd_redir_idx  = ifu_ftq_pdwb_idx;
    pd_redir_pc   = w_corr_succ;

    pd_wr_val     = pd_redir_val;
    pd_wr_idx     = ifu_ftq_pdwb_idx;
    pd_wr_sel     = w_sel;
    pd_wr_slot    = w_new_slot;
    pd_wr_kill    = 1'b1;
  end

  // ifu_ftq_pd_range, ifu_ftq_cfi_val, ifu_ftq_cfi_pos and
  // ifu_ftq_fault_pos are DECLARED AND NOT READ, and each absence is
  // a decision rather than an omission:
  //
  //   pd_range   marks the slots actually fetched. M4 -- a predicted
  //              taken position outside the range -- is the IFU's
  //              test to make, and it reports the result on
  //              ifu_ftq_mis_val. Re-deriving it here would be a
  //              second producer of one fact.
  //   cfi_*      name the FIRST control-flow instruction predecode
  //              found. The correction of section 7 is driven by
  //              mis_pos, which names the MISPREDICTED position;
  //              the two coincide in the M1 case and do not in M2
  //              and M3, and section 7 W1 and W2 both cite mis_pos.
  //   fault_pos  ftq_entry_formats.md 4.2 is explicit that it is NOT
  //              stored and the fault code is not carried at all:
  //              the architectural exception travels with the
  //              instruction stream to the backend. The FTQ needs
  //              only to know the block ended early.
  //
  // ftq_ifu_req_rdy and ftq_ifu_xlate_rdy are likewise not read
  // HERE. Each acceptance advances a pointer, which is ftq_ptr's
  // state, so the ports are consumed there; they are on this port
  // list because sections 4 and 4.1 declare them on this interface.
  // redir_arm[ARM_BKEND] and the p1 arm are not read: the backend
  // row is every redirect outside the front-end set. The wrap bit of
  // commit_ptr is not read: both of its uses here are indices.
  //
  // clk and rstn are read by the bound properties, not by this
  // module. See the port list.
  logic w_unused;
  assign w_unused = |ifu_ftq_pd_range | ifu_ftq_cfi_val |
                    |ifu_ftq_cfi_pos  | |ifu_ftq_fault_pos |
                    ftq_ifu_req_rdy   | ftq_ifu_xlate_rdy |
                    redir_arm[ARM_BKEND] | redir_arm[ARM_P1] |
                    commit_ptr[FTQ_IDX_BITS] | rstn | clk;

endmodule : ftq_ifu
