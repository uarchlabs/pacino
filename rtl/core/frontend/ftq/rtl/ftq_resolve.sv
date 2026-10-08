// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FTQ resolution intake and update fan-out (BP-107),
// ftq_backend_interfaces.md 4 and fe_decisions.md 7.2.
//
// THREE EVENTS, NOT ONE (backend_interfaces 3). RESOLVE forms
// predictor updates and does NOT free the entry and does NOT
// redirect. REDIRECT squashes. COMMIT frees. A mispredicting branch
// RESOLVEs, REDIRECTs, and later COMMITs -- three events, one
// branch, many cycles apart. This module handles only the first.
//
// THE BACKEND NAMES A POSITION, NOT A SLOT. Prediction slots are
// the two branch fields of one FTB block (FE-10) and nothing outside
// the BPU and the FTQ has reason to know which field a branch landed
// in: the IFU tags each instruction from its own predecode, and
// predecode yields a position. This module maps position to slot by
// matching pos against the entry's two bp_ftq_slot_t.pos fields.
//
// THE MAPPING IS EXACT. Positions are unique within an entry --
// FTB_BR_POS_BITS is 4, one position per 2-byte slot, so no two
// branches in a block can share one. It was ambiguous until the
// field was widened on 2026-08-19.
//
// A POSITION NAMING NO SLOT IS PLACED AND TRAINED (BP-119, ruled in
// session by Jeff). It is the first execution of a branch the entry
// does not hold: the p2 slot correction carries only what the FTB
// returned, and predecode writes a slot only on a structural
// mispredict, which it raises for a JAL alone (ifu_f3 M1). Until
// BP-119 such a resolution formed no update of any kind, so the FTB
// could never learn a conditional or a JALR it did not already hold,
// and TAGE, SC, LP and ITTAGE never trained in the integrated front
// end. Now the branch is PLACED in a slot by the rule ftq_ifu W1 uses
// for a branch predecode found -- program order: the lowest slot that
// is free or holds a position at or after this one, else the last
// slot -- and trained as a mapped branch: FTB (allocating on a miss,
// with the hit and way carried in the slot's metadata), uBTB, and
// the table predictors from that slot's metadata, with no R2
// suppression (the ruling: train them on the first execution). The
// placed slot is also written into the entry (rsv_wr_*), so the
// commit walk sees a call or return it holds (ftq_entry 5.4).
// rsv_nomap still reports the condition, per channel.
//
// WHAT R2 OF ftq_entry_formats.md 3.1 DOES. When the entry's stored
// br_type for the mapped slot DISAGREES with the resolved br_type,
// the metadata describes a different predictor set than the branch
// that executed. Form the uBTB and FTB updates ONLY: both derive
// from the resolved facts and from ftb, which lies outside the
// deferred union. Suppress TAGE, SC, LP and ITTAGE -- their payload
// types embed metadata that was never captured for this branch
// type. The FTB update corrects the stored classification, so the
// next occurrence selects the right arm.
//
// FAN-OUT BY RESOLVED br_type, fe_decisions.md 7.2:
//
//   conditional     uBTB, LP, FTB, TAGE, SC
//   indirect        uBTB, FTB, ITTAGE
//   return          uBTB, FTB, RAS
//   direct uncond   uBTB, FTB
//   direct call     uBTB, FTB, RAS
//   indirect call   uBTB, FTB, ITTAGE, RAS
//   return-call     uBTB, FTB, RAS (pop, then push)
//   no branch       none
//
// RETURN_CALL (3'b111, TD#152) trains the FTB with is_call, is_ret
// and is_jalr all set, so the next prediction of the block classifies
// it RETURN_CALL at p2; it does not train ITTAGE (7.2, FE-U9). Before
// BP-119 3'b111 trained the FTB as a plain direct jump. RAS is NOT
// updated from here -- its update is the commit group, fed from the
// commit walk of 5.4 -- so a RETURN or a CALL forms no RAS traffic on
// this path.
//
// THE PREDICTOR VALIDS ARE REQUESTS (BP-119, TD#150, TD#151). This
// module presents, per slot, which predictors the resolution trains,
// qualified by the FTB scheduler's ready for its channel but NOT by
// any predictor's ready. ftq_upd_conv forms the per-predictor payloads
// from them, gates each predictor's valid on the slot being accepted
// by EVERY predictor it trains, and returns that acceptance on
// upd_acc. The channel's ready is the scheduler's ready and upd_acc of
// its slot. The valids are not gated here because the SC accept
// (bp_cluster sc_upd_rdy) is a function of the SC valid: gating the
// request on it would close a combinational loop.
//
// R3, THE SQUASHED RESOLUTION. A resolution naming an entry that has
// been squashed is DROPPED SILENTLY. This is normal traffic, not an
// error: a branch in flight when an older branch redirects will
// resolve after the squash. The test built here is the LIVE WINDOW,
// [commit_ptr, alloc_ptr).
//
// R3 ALSO ASKS FOR A GENERATION TEST AND IT CANNOT BE MADE.
// ftq_resolve_t.ftq_idx is FTQ_IDX_BITS with no generation, and no
// generation tag travels with the instruction (A1 carries
// FTQ_IDX_BITS + FTB_BR_POS_BITS and nothing more). So a resolution
// for a squashed entry whose index has since been REALLOCATED
// inside the live window is indistinguishable from a resolution for
// the new use of that index, and the live-window test does not
// catch it. Section 9 calls the generation bit "FE-U7 work"; FE-U7
// resolved without adding one to this path. Reported in the BP-107
// Results Capture.
//
// FE-5 AND FE-5a. ftq_bkend_rsv_rdy deasserts when the FTQ cannot
// accept: a full predictor update queue, or the FTB scheduler
// protecting a HIGH-value update from being dropped (5.7.3 S6). The
// backend holds valid until accepted (A4) and a resolution is never
// dropped for capacity.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_resolve (
  // COMBINATIONAL MODULE, for the same reason as ftq_ifu: the entry,
  // the metadata and the pointers are owned elsewhere. clk and rstn
  // are here for the concurrent SVA bound by module name.
  input  logic                     clk,
  input  logic                     rstn,

  // ---- pointers, for the R3 live-window test -----------------------
  input  logic [FTQ_PTR_BITS-1:0]  commit_ptr,
  input  logic [FTQ_PTR_BITS-1:0]  alloc_ptr,

  // ---- resolution in, backend_interfaces 4 -------------------------
  input  logic [NUM_RESOLVE_PORTS-1:0] bkend_rsv_val,
  input  ftq_resolve_t             bkend_rsv [0:NUM_RESOLVE_PORTS-1],
  output logic [NUM_RESOLVE_PORTS-1:0] ftq_bkend_rsv_rdy,

  // ---- the entries the two channels name ---------------------------
  // rsv_rd_idx addresses ftq_entry and ftq_meta; both come back
  // combinationally in the same cycle. The two channels may name
  // DIFFERENT entries, which is why there are two of each.
  output logic [FTQ_IDX_BITS-1:0]  rsv_rd_idx [0:NUM_RESOLVE_PORTS-1],
  input  bp_ftq_entry_t            rsv_entry  [0:NUM_RESOLVE_PORTS-1],
  input  bp_ftq_meta_t             rsv_meta   [0:NUM_RESOLVE_PORTS-1]
                                              [0:NUM_PRED_SLOTS-1],

  // ---- backpressure from the update path ---------------------------
  // ftb_sched_rdy is ftq_ftb_sched's upd_rdy: the scheduler owns
  // only the FTB reason for deasserting ready and the FTQ ANDs it
  // with its others (5.7.4). upd_acc is ftq_upd_conv's: slot s's
  // update is accepted by every predictor it trains (TD#150).
  input  logic [NUM_RESOLVE_PORTS-1:0] ftb_sched_rdy,
  input  logic [NUM_PRED_SLOTS-1:0] upd_acc,

  // ---- update out, the per-slot channels ---------------------------
  // bp_update_t is arrayed by SLOT and the slot IS the array index
  // (FE-10), so a channel's payload is written to the element its
  // position mapped to. A channel whose position maps to slot 1
  // therefore drives element 1, not element 0.
  output bp_update_t               upd [0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0] upd_ubtb_val,
  output logic [NUM_PRED_SLOTS-1:0] upd_lp_val,
  output logic [NUM_PRED_SLOTS-1:0] upd_tage_val,
  output logic [NUM_PRED_SLOTS-1:0] upd_ittage_val,
  output logic [NUM_PRED_SLOTS-1:0] upd_sc_val,

  // ---- the slow-path metadata that goes with each update -----------
  output bp_ftq_meta_t             upd_meta [0:NUM_PRED_SLOTS-1],
  // ---- the fast-path entry that goes with each update --------------
  // ftq_upd_conv reads the slot's pos and the block's pft_addr from it
  // (ftq_bpu_interfaces.md 8: every payload field has a source in
  // bp_update_t, bp_ftq_meta_t or the fast-path entry).
  output bp_ftq_entry_t            upd_entry [0:NUM_PRED_SLOTS-1],

  // ---- update out, to ftq_ftb_sched --------------------------------
  // The scheduler takes the flat payload as one struct plus the two
  // value bits of 5.7.2. hit comes from the slow path, mispredict
  // from the resolution channel; neither needs new state.
  output logic [NUM_RESOLVE_PORTS-1:0] ftb_upd_val,
  output ftb_upd_t                 ftb_upd [0:NUM_RESOLVE_PORTS-1],
  output logic [NUM_RESOLVE_PORTS-1:0] ftb_upd_hit,
  output logic [NUM_RESOLVE_PORTS-1:0] ftb_upd_mispred,

  // ---- observation, for the bound properties -----------------------
  // rsv_nomap: the position named no slot in the entry. Reported,
  // not dropped silently -- see the header.
  // rsv_drop_sq: dropped by R3, the live-window test.
  // rsv_type_dis: R2 of ftq_entry_formats.md 3.1 fired.
  output logic [NUM_RESOLVE_PORTS-1:0] rsv_nomap,
  output logic [NUM_RESOLVE_PORTS-1:0] rsv_drop_sq,
  output logic [NUM_RESOLVE_PORTS-1:0] rsv_type_dis,
  output logic [NUM_RESOLVE_PORTS-1:0] rsv_accept,
  output logic [TRX_SLOT_BITS-1:0] rsv_slot [0:NUM_RESOLVE_PORTS-1],

  // ---- the placement write, to ftq_entry (BP-119) ------------------
  // One slot of the named entry, written when a placed resolution is
  // accepted (its channel ready), so the commit walk sees it.
  output logic [NUM_RESOLVE_PORTS-1:0] rsv_wr_val,
  output logic [FTQ_IDX_BITS-1:0]  rsv_wr_idx  [0:NUM_RESOLVE_PORTS-1],
  output logic [TRX_SLOT_BITS-1:0] rsv_wr_sel  [0:NUM_RESOLVE_PORTS-1],
  output bp_ftq_slot_t             rsv_wr_slot [0:NUM_RESOLVE_PORTS-1]
);

  logic [FTQ_PTR_BITS-1:0] w_live_len;
  logic [FTQ_PTR_BITS-1:0] w_age [0:NUM_RESOLVE_PORTS-1];
  logic [NUM_RESOLVE_PORTS-1:0] w_live;
  logic [NUM_RESOLVE_PORTS-1:0] w_slot_hit;
  logic [TRX_SLOT_BITS-1:0] w_map_slot [0:NUM_RESOLVE_PORTS-1];
  logic [TRX_SLOT_BITS-1:0] w_plc_slot [0:NUM_RESOLVE_PORTS-1];
  logic [NUM_RESOLVE_PORTS-1:0] w_plc_val;
  bp_ftq_slot_t             w_new_slot [0:NUM_RESOLVE_PORTS-1];
  logic [NUM_RESOLVE_PORTS-1:0] w_rdy_pred;

  // -----------------------------------------------------------------
  // Intake: the live-window test and the position-to-slot mapping.
  // -----------------------------------------------------------------
  // One always_comb in textual order: the mapping depends on the
  // entry read, which depends on the index this block drives, and
  // the fan-out below depends on the mapping. CLAUDE.md requires
  // that form for a dependency chain.
  always_comb begin : intake
    w_live_len = alloc_ptr - commit_ptr;

    for (int c = 0; c < NUM_RESOLVE_PORTS; c++) begin
      rsv_rd_idx[c] = bkend_rsv[c].ftq_idx;

      // R3. An age below the live length is an entry between
      // commit_ptr and alloc_ptr. Wrap-aware, as everywhere in this
      // unit; a raw index compare would report the wrong answer on
      // every window that crosses the array boundary.
      w_age[c] = {1'b0, bkend_rsv[c].ftq_idx -
                        commit_ptr[FTQ_IDX_BITS-1:0]};
      w_live[c] = (w_age[c] < w_live_len);

      // Position to slot. Descending so the LOWEST matching slot
      // wins, though the mapping is exact and at most one can match.
      w_slot_hit[c] = 1'b0;
      w_map_slot[c] = '0;
      for (int s = NUM_PRED_SLOTS - 1; s >= 0; s--) begin
        if (rsv_entry[c].slot[s].slot_valid &&
            (rsv_entry[c].slot[s].pos == bkend_rsv[c].pos)) begin
          w_map_slot[c] = TRX_SLOT_BITS'(s);
          w_slot_hit[c] = 1'b1;
        end
      end

      // Placement for a position naming no slot (ftq_ifu W1's rule):
      // the lowest slot free or at or after the position, else the
      // last. Descending so the lowest qualifying slot wins.
      w_plc_slot[c]  = TRX_SLOT_BITS'(NUM_PRED_SLOTS - 1);
      for (int s = NUM_PRED_SLOTS - 1; s >= 0; s--) begin
        if (!rsv_entry[c].slot[s].slot_valid ||
            (rsv_entry[c].slot[s].pos >= bkend_rsv[c].pos)) begin
          w_plc_slot[c] = TRX_SLOT_BITS'(s);
        end
      end
      rsv_slot[c] = w_slot_hit[c] ? w_map_slot[c] : w_plc_slot[c];

      rsv_drop_sq[c] = bkend_rsv_val[c] & ~w_live[c];
      rsv_nomap[c]   = bkend_rsv_val[c] &  w_live[c] & ~w_slot_hit[c];

      // Every live resolution is accepted: mapped, or placed.
      rsv_accept[c]  = bkend_rsv_val[c] &  w_live[c];

      // R2 of ftq_entry_formats.md 3.1. The stored classification
      // against the resolved one, for a MAPPED branch only: a placed
      // branch has no stored classification of its own, and the
      // ruling trains the table predictors on it.
      rsv_type_dis[c] = rsv_accept[c] && w_slot_hit[c] &&
        (rsv_entry[c].slot[rsv_slot[c]].br_type != bkend_rsv[c].br_type);

      // The placed slot, as the entry will hold it.
      w_plc_val[c]               = rsv_nomap[c] &&
                                   (bkend_rsv[c].br_type != NO_BRANCH);
      w_new_slot[c]              = '0;
      w_new_slot[c].slot_valid   = 1'b1;
      w_new_slot[c].target       = bkend_rsv[c].target;
      w_new_slot[c].br_type      = bkend_rsv[c].br_type;
      w_new_slot[c].taken        = bkend_rsv[c].taken;
      w_new_slot[c].pos          = bkend_rsv[c].pos;
      w_new_slot[c].pred_src     = PRED_NONE;
    end
  end

  // -----------------------------------------------------------------
  // Ready. FE-5, FE-5a, backend_interfaces 4.
  // -----------------------------------------------------------------
  // A channel is ready when the FTB scheduler can take its FTB update
  // (per channel, 5.7.3 S6) and, for a resolution that forms an
  // update, when ftq_upd_conv reports its slot accepted by every
  // predictor that slot trains (upd_acc, TD#150). A resolution that
  // forms no update -- squashed or unmapped -- needs no predictor.
  //
  // Before BP-119 the three queued predictors' scalar readies gated
  // every channel whatever it trained. The cluster's SC ready is
  // asserted only in a cycle SC grants an update (bp_cluster
  // sc_upd_rdy), so under that rule a resolution that trains no SC
  // could never be accepted once the readies were connected.
  always_comb begin : ready
    for (int c = 0; c < NUM_RESOLVE_PORTS; c++) begin
      w_rdy_pred[c] = ~rsv_accept[c] | upd_acc[rsv_slot[c]];
      ftq_bkend_rsv_rdy[c] = w_rdy_pred[c] & ftb_sched_rdy[c];
    end
  end

  // -----------------------------------------------------------------
  // Fan-out.
  // -----------------------------------------------------------------
  // bp_update_t is indexed by SLOT and ftq_resolve_t arrives per
  // CHANNEL, so the loop is over channels and writes the element
  // rsv_slot names. Slots no channel maps to are driven invalid.
  //
  // The type used for fan-out is the RESOLVED br_type, not the
  // stored one: fe_decisions.md 7.2 says the slot's br_type
  // determines the predictor set and means the FTB classification
  // placed there by the p2 correction, but when the two disagree R2
  // governs and only uBTB and FTB form. Using the resolved type and
  // then applying R2 gives the same answer in the agreeing case and
  // the right one in the disagreeing case.
  always_comb begin : fanout
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      upd[s]            = '0;
      upd_meta[s]       = '0;
      upd_entry[s]      = '0;
      upd_ubtb_val[s]   = 1'b0;
      upd_lp_val[s]     = 1'b0;
      upd_tage_val[s]   = 1'b0;
      upd_ittage_val[s] = 1'b0;
      upd_sc_val[s]     = 1'b0;
    end

    // A request is formed for an accepted resolution whose FTB update
    // the scheduler can take this cycle. NOT gated by upd_acc: see the
    // header, THE PREDICTOR VALIDS ARE REQUESTS.
    for (int c = 0; c < NUM_RESOLVE_PORTS; c++) begin
      if (rsv_accept[c] && ftb_sched_rdy[c]) begin
        upd[rsv_slot[c]].branch_id     = bkend_rsv[c].ftq_idx;
        upd[rsv_slot[c]].pc            = rsv_entry[c].pc;
        upd[rsv_slot[c]].actual_taken  = bkend_rsv[c].taken;
        upd[rsv_slot[c]].actual_target = bkend_rsv[c].target;
        upd[rsv_slot[c]].br_type       = bkend_rsv[c].br_type;
        upd[rsv_slot[c]].mispredicted  = bkend_rsv[c].mispredict;
        upd[rsv_slot[c]].valid         = 1'b1;

        upd_meta[rsv_slot[c]]  = rsv_meta[c][rsv_slot[c]];
        upd_entry[rsv_slot[c]] = rsv_entry[c];
        // A placed branch is presented in its slot, so ftq_upd_conv
        // reads its position (not the slot's previous occupant's).
        if (w_plc_val[c]) begin
          upd_entry[rsv_slot[c]].slot[rsv_slot[c]] = w_new_slot[c];
        end

        // uBTB updates on every resolved branch type that forms an
        // update at all. NO_BRANCH forms none.
        upd_ubtb_val[rsv_slot[c]] =
          (bkend_rsv[c].br_type != NO_BRANCH);

        // The four suppressed by R2. Each is additionally gated by
        // its own branch type: TAGE, SC and LP train only on
        // conditionals, ITTAGE only on indirects, and INDIRECT_CALL
        // is an indirect for this purpose because it updates ITTAGE
        // for the target (FE-U9, session-061). RETURN_CALL is not:
        // its target is the RAS pop (7.2).
        if (!rsv_type_dis[c]) begin
          upd_tage_val[rsv_slot[c]] = (bkend_rsv[c].br_type == COND);
          upd_sc_val[rsv_slot[c]]   = (bkend_rsv[c].br_type == COND);
          upd_lp_val[rsv_slot[c]]   = (bkend_rsv[c].br_type == COND);
          upd_ittage_val[rsv_slot[c]] =
            (bkend_rsv[c].br_type == INDIRECT_NONRET) ||
            (bkend_rsv[c].br_type == INDIRECT_CALL);
        end
      end
    end
  end

  // -----------------------------------------------------------------
  // The FTB update, to ftq_ftb_sched.
  // -----------------------------------------------------------------
  // The FTB is updated on every resolved type except NO_BRANCH, R2
  // included: ftb lies OUTSIDE the deferred union, so its metadata
  // is valid whatever the stored classification was, and the update
  // is what CORRECTS that classification for the next occurrence.
  //
  // The scheduler's S1 reads is_br | is_jmp rather than a br_type
  // port, so the two must agree: a resolved NO_BRANCH sets neither
  // and is not FTB-bound, which is exactly S1.
  //
  // hit and way are the carried writeWay scheme (IC-FTB-10): the FTB
  // determines them at the prediction read and does not re-look-up
  // the tag at update, so they come out of the slow path unchanged.
  // They are scalar within the entry, so either slot's copy serves.
  always_comb begin : ftb_update
    for (int c = 0; c < NUM_RESOLVE_PORTS; c++) begin
      ftb_upd_val[c]     = rsv_accept[c] &&
                           (bkend_rsv[c].br_type != NO_BRANCH);
      ftb_upd_hit[c]     = rsv_meta[c][rsv_slot[c]].ftb.hit;
      ftb_upd_mispred[c] = bkend_rsv[c].mispredict;

      ftb_upd[c]            = '0;
      ftb_upd[c].pc         = rsv_entry[c].pc;
      ftb_upd[c].hit        = rsv_meta[c][rsv_slot[c]].ftb.hit;
      ftb_upd[c].way        = rsv_meta[c][rsv_slot[c]].ftb.way;
      ftb_upd[c].pos        = bkend_rsv[c].pos;
      ftb_upd[c].taken      = bkend_rsv[c].taken;
      ftb_upd[c].pft_addr   = rsv_entry[c].pft_addr;

      // A conditional fills a BRANCH field; everything else fills
      // the block's single JUMP field. br_idx names which
      // conditional field, and the slot IS that index: the slot
      // array is program ordered (IC-FTB-16) and br0 maps to slot 0
      // at the cluster boundary (ftq_bpu_interfaces.md 5.1).
      ftb_upd[c].is_br      = (bkend_rsv[c].br_type == COND);
      ftb_upd[c].br_idx     = rsv_slot[c][0];
      ftb_upd[c].target     = bkend_rsv[c].target;

      ftb_upd[c].is_jmp     = (bkend_rsv[c].br_type != COND) &&
                              (bkend_rsv[c].br_type != NO_BRANCH);
      ftb_upd[c].jmp_target = bkend_rsv[c].target;
      // RETURN_CALL is a call AND a return AND a JALR, the three bits
      // the cluster's p2 classification reads it from (TD#152).
      ftb_upd[c].is_call    =
        (bkend_rsv[c].br_type == DIRECT_CALL)   ||
        (bkend_rsv[c].br_type == INDIRECT_CALL) ||
        (bkend_rsv[c].br_type == RETURN_CALL);
      ftb_upd[c].is_ret     =
        (bkend_rsv[c].br_type == RETURN)        ||
        (bkend_rsv[c].br_type == RETURN_CALL);
      ftb_upd[c].is_jalr    =
        (bkend_rsv[c].br_type == INDIRECT_NONRET) ||
        (bkend_rsv[c].br_type == INDIRECT_CALL)   ||
        (bkend_rsv[c].br_type == RETURN)          ||
        (bkend_rsv[c].br_type == RETURN_CALL);
    end
  end

  // -----------------------------------------------------------------
  // The placement write. On acceptance only: a held resolution is
  // re-presented and placed again, and writing before acceptance
  // would make the retry map onto its own placement.
  // -----------------------------------------------------------------
  always_comb begin : place_write
    for (int c = 0; c < NUM_RESOLVE_PORTS; c++) begin
      rsv_wr_val[c]  = w_plc_val[c] & ftq_bkend_rsv_rdy[c];
      rsv_wr_idx[c]  = bkend_rsv[c].ftq_idx;
      rsv_wr_sel[c]  = rsv_slot[c];
      rsv_wr_slot[c] = w_new_slot[c];
    end
  end

  // clk and rstn are read by the bound properties, not by this
  // module. See the port list.
  logic w_unused;
  assign w_unused = clk | rstn;

endmodule : ftq_resolve
