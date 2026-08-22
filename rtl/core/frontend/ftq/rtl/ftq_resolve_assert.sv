// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ftq_resolve (BP-107),
// ftq_backend_interfaces.md 4 and fe_decisions.md 7.2.
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
//
// The properties are generated PER CHANNEL. NUM_RESOLVE_PORTS is 2
// and the two channels are independent -- either may name any entry
// and any position -- so a property written for channel 0 alone
// would leave half the module unproven.
//
// R1 IS THE ONE THE ACCEPTANCE CRITERION NAMES. A position naming
// no slot in the entry is REPORTED, not silently dropped: it means
// the entry describes a different set of branches than the one that
// executed, which is a stale or aliased FTB entry and is not the
// same condition as a squashed entry. Reporting it separately from
// the squash drop is what makes the two distinguishable at all.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_resolve_assert (
  input logic                    clk,
  input logic                    rstn,
  input logic [FTQ_PTR_BITS-1:0] commit_ptr,
  input logic [FTQ_PTR_BITS-1:0] alloc_ptr,
  input logic [NUM_RESOLVE_PORTS-1:0] bkend_rsv_val,
  input ftq_resolve_t            bkend_rsv [0:NUM_RESOLVE_PORTS-1],
  input logic [NUM_RESOLVE_PORTS-1:0] ftq_bkend_rsv_rdy,
  input logic [FTQ_IDX_BITS-1:0] rsv_rd_idx [0:NUM_RESOLVE_PORTS-1],
  input bp_ftq_entry_t           rsv_entry  [0:NUM_RESOLVE_PORTS-1],
  input logic [NUM_RESOLVE_PORTS-1:0] ftb_upd_val,
  input ftb_upd_t                ftb_upd [0:NUM_RESOLVE_PORTS-1],
  input logic [NUM_RESOLVE_PORTS-1:0] ftb_upd_mispred,
  input logic [NUM_RESOLVE_PORTS-1:0] rsv_nomap,
  input logic [NUM_RESOLVE_PORTS-1:0] rsv_drop_sq,
  input logic [NUM_RESOLVE_PORTS-1:0] rsv_type_dis,
  input logic [NUM_RESOLVE_PORTS-1:0] rsv_accept,
  input logic [TRX_SLOT_BITS-1:0] rsv_slot [0:NUM_RESOLVE_PORTS-1],
  input bp_update_t              upd [0:NUM_PRED_SLOTS-1],
  input logic [NUM_PRED_SLOTS-1:0] upd_tage_val,
  input logic [NUM_PRED_SLOTS-1:0] upd_sc_val,
  input logic [NUM_PRED_SLOTS-1:0] upd_lp_val,
  input logic [NUM_PRED_SLOTS-1:0] upd_ittage_val,
  input logic [NUM_PRED_SLOTS-1:0] upd_ubtb_val
);

  genvar gc;
  generate
    for (gc = 0; gc < NUM_RESOLVE_PORTS; gc++) begin : g_chan

      // R1  Every presented resolution lands in EXACTLY ONE bucket:
      //     accepted, reported as unmapped, or dropped as squashed.
      //     A resolution that fell through all three would vanish
      //     with no update formed and nothing said -- the silent
      //     drop the acceptance criterion forbids.
      property p_one_bucket;
        @(posedge clk) disable iff (!rstn)
          bkend_rsv_val[gc] |->
            $onehot({rsv_accept[gc], rsv_nomap[gc], rsv_drop_sq[gc]});
      endproperty
      a_one_bucket: assert property (p_one_bucket)
        else $error("R1 a resolution landed in no bucket, or in more than one");

      // R2  No bucket fires without a presented resolution.
      property p_no_bucket_idle;
        @(posedge clk) disable iff (!rstn)
          !bkend_rsv_val[gc] |->
            !rsv_accept[gc] && !rsv_nomap[gc] && !rsv_drop_sq[gc];
      endproperty
      a_no_bucket_idle: assert property (p_no_bucket_idle)
        else $error("R2 a bucket fired with no resolution presented");

      // R3  An unmapped position forms NO update. There is no slot
      //     whose metadata could train a predictor, so forming one
      //     would train against another branch's captured state.
      property p_nomap_forms_nothing;
        @(posedge clk) disable iff (!rstn)
          rsv_nomap[gc] |-> !ftb_upd_val[gc];
      endproperty
      a_nomap_forms_nothing: assert property (p_nomap_forms_nothing)
        else $error("R3 an unmapped position formed an update");

      // R4  R3 of backend_interfaces 7. A resolution naming a
      //     squashed entry forms nothing. This is NORMAL TRAFFIC,
      //     not an error: a branch in flight when an older branch
      //     redirects will resolve after the squash.
      property p_squashed_forms_nothing;
        @(posedge clk) disable iff (!rstn)
          rsv_drop_sq[gc] |-> !ftb_upd_val[gc];
      endproperty
      a_squashed_forms_nothing: assert property (p_squashed_forms_nothing)
        else $error("R4 a squashed resolution formed an update");

      // R5  The live-window test is what rsv_drop_sq means. An
      //     independent statement of it: a resolution naming an
      //     entry at or after alloc_ptr cannot be live, so it must
      //     drop. Written on the empty queue, where NO index is
      //     live, because that is the case a raw index compare gets
      //     wrong -- with commit_ptr equal to alloc_ptr the length
      //     is zero and every age must fail.
      property p_empty_drops_all;
        @(posedge clk) disable iff (!rstn)
          (bkend_rsv_val[gc] && (commit_ptr == alloc_ptr)) |->
            rsv_drop_sq[gc];
      endproperty
      a_empty_drops_all: assert property (p_empty_drops_all)
        else $error("R5 an empty queue did not drop the resolution");

      // R6  The read index IS the resolution's index. The entry and
      //     the metadata both come back on it, so a wrong index
      //     trains a predictor on another block's captured state --
      //     which no downstream check would catch, because the
      //     payload is well formed.
      property p_reads_its_entry;
        @(posedge clk) disable iff (!rstn)
          rsv_rd_idx[gc] == bkend_rsv[gc].ftq_idx;
      endproperty
      a_reads_its_entry: assert property (p_reads_its_entry)
        else $error("R6 the read index is not the resolution's");

      // R7  THE UPDATE REACHES ftq_ftb_sched UNCHANGED. The resolved
      //     facts pass through: the block PC from the entry, the
      //     direction, the target and the position from the
      //     resolution. The scheduler arbitrates; it does not
      //     reinterpret, so anything altered here is altered for
      //     good.
      property p_ftb_payload_intact;
        @(posedge clk) disable iff (!rstn)
          ftb_upd_val[gc] |->
            (ftb_upd[gc].pc     == rsv_entry[gc].pc)     &&
            (ftb_upd[gc].taken  == bkend_rsv[gc].taken)  &&
            (ftb_upd[gc].target == bkend_rsv[gc].target) &&
            (ftb_upd[gc].pos    == bkend_rsv[gc].pos)    &&
            (ftb_upd_mispred[gc] == bkend_rsv[gc].mispredict);
      endproperty
      a_ftb_payload_intact: assert property (p_ftb_payload_intact)
        else $error("R7 the FTB payload reached the scheduler altered");

      // R8  S1 of 5.7.3 agrees with the resolved type. The scheduler
      //     reads is_br | is_jmp rather than a br_type port, so a
      //     payload that set neither would be presented as valid and
      //     classified as not FTB-bound -- accepted and then ignored,
      //     with no drop reported.
      property p_ftb_bound_agrees;
        @(posedge clk) disable iff (!rstn)
          ftb_upd_val[gc] |-> (ftb_upd[gc].is_br | ftb_upd[gc].is_jmp);
      endproperty
      a_ftb_bound_agrees: assert property (p_ftb_bound_agrees)
        else $error("R8 an FTB update is neither a branch nor a jump");

      // R9  A resolved NO_BRANCH forms no FTB update (7.2, and the
      //     three encodings that table does not list).
      property p_no_branch_no_ftb;
        @(posedge clk) disable iff (!rstn)
          (bkend_rsv_val[gc] &&
           (bkend_rsv[gc].br_type == NO_BRANCH)) |-> !ftb_upd_val[gc];
      endproperty
      a_no_branch_no_ftb: assert property (p_no_branch_no_ftb)
        else $error("R9 a resolved NO_BRANCH formed an FTB update");

      // R10 R2 of ftq_entry_formats.md 3.1. When the stored
      //     classification disagrees with the resolved one, the
      //     metadata describes a DIFFERENT predictor set than the
      //     branch that executed, so TAGE, SC, LP and ITTAGE are
      //     suppressed -- their payload types embed metadata that
      //     was never captured for this branch type. uBTB and FTB
      //     still form: both derive from the resolved facts and from
      //     ftb, which lies outside the deferred union.
      property p_type_disagree_suppresses;
        @(posedge clk) disable iff (!rstn)
          rsv_type_dis[gc] |->
            !upd_tage_val[rsv_slot[gc]] && !upd_sc_val[rsv_slot[gc]] &&
            !upd_lp_val[rsv_slot[gc]]   &&
            !upd_ittage_val[rsv_slot[gc]];
      endproperty
      a_type_disagree_suppresses: assert property (p_type_disagree_suppresses)
        else $error("R10 a type disagreement did not suppress the four");

    end
  endgenerate

  genvar gs;
  generate
    for (gs = 0; gs < NUM_PRED_SLOTS; gs++) begin : g_slot

      // R11 Fan-out by resolved br_type, fe_decisions.md 7.2. TAGE
      //     and SC predict DIRECTION and train only on conditionals;
      //     training them on a jump would push a direction counter
      //     for a branch that has none.
      property p_tage_sc_cond_only;
        @(posedge clk) disable iff (!rstn)
          (upd_tage_val[gs] || upd_sc_val[gs] || upd_lp_val[gs]) |->
            (upd[gs].br_type == COND) && upd[gs].valid;
      endproperty
      a_tage_sc_cond_only: assert property (p_tage_sc_cond_only)
        else $error("R11 tage, sc or lp updated on a non-conditional");

      // R12 ITTAGE trains only on indirects. INDIRECT_CALL counts:
      //     it updates ITTAGE for the TARGET (FE-U9, session-061)
      //     and its RAS push reads the fast-path snapshot, not the
      //     metadata. RETURN does not -- the RAS owns it.
      property p_ittage_indirect_only;
        @(posedge clk) disable iff (!rstn)
          upd_ittage_val[gs] |->
            ((upd[gs].br_type == INDIRECT_NONRET) ||
             (upd[gs].br_type == INDIRECT_CALL)) && upd[gs].valid;
      endproperty
      a_ittage_indirect_only: assert property (p_ittage_indirect_only)
        else $error("R12 ittage updated on a non-indirect");

      // R13 The uBTB updates on every type that forms an update at
      //     all, and NO_BRANCH forms none.
      property p_ubtb_not_no_branch;
        @(posedge clk) disable iff (!rstn)
          upd_ubtb_val[gs] |-> (upd[gs].br_type != NO_BRANCH) &&
                               upd[gs].valid;
      endproperty
      a_ubtb_not_no_branch: assert property (p_ubtb_not_no_branch)
        else $error("R13 the uBTB updated on NO_BRANCH");

      // R14 No predictor valid without the channel payload behind
      //     it. A valid with upd[gs].valid clear would enqueue a
      //     zeroed update, which every predictor would read as a
      //     COND resolution of block zero.
      property p_val_needs_payload;
        @(posedge clk) disable iff (!rstn)
          (upd_tage_val[gs] | upd_sc_val[gs] | upd_lp_val[gs] |
           upd_ittage_val[gs] | upd_ubtb_val[gs]) |-> upd[gs].valid;
      endproperty
      a_val_needs_payload: assert property (p_val_needs_payload)
        else $error("R14 a predictor valid with no payload behind it");

    end
  endgenerate

  // R15 FE-5 and A4. When NO channel can be accepted, nothing is
  //     enqueued to the predictors: the backend holds the resolution
  //     and it is never dropped for capacity.
  //
  //     STATED ON THE bp_update_t FAN-OUT, NOT ON THE FTB CHANNEL,
  //     and the difference is structural. ftq_ftb_sched's upd_rdy is
  //     a FUNCTION of the valids presented to it (5.7.3 S6), so
  //     gating ftb_upd_val on ftb_sched_rdy would close a
  //     combinational loop through the scheduler. The FTB channel is
  //     therefore presented unconditionally and the scheduler
  //     answers; the queued predictors, whose readies come from
  //     their own queues, are gated.
  property p_no_update_when_not_rdy;
    @(posedge clk) disable iff (!rstn)
      (ftq_bkend_rsv_rdy == '0) |-> ((upd[0].valid == 1'b0) &&
                                     (upd[1].valid == 1'b0));
  endproperty
  a_no_update_when_not_rdy: assert property (p_no_update_when_not_rdy)
    else $error("R15 an update formed on a channel that was not ready");

endmodule : ftq_resolve_assert

// Bind BY MODULE NAME.
bind ftq_resolve ftq_resolve_assert u_assert (
  .clk               (clk),
  .rstn              (rstn),
  .commit_ptr        (commit_ptr),
  .alloc_ptr         (alloc_ptr),
  .bkend_rsv_val     (bkend_rsv_val),
  .bkend_rsv         (bkend_rsv),
  .ftq_bkend_rsv_rdy (ftq_bkend_rsv_rdy),
  .rsv_rd_idx        (rsv_rd_idx),
  .rsv_entry         (rsv_entry),
  .ftb_upd_val       (ftb_upd_val),
  .ftb_upd           (ftb_upd),
  .ftb_upd_mispred   (ftb_upd_mispred),
  .rsv_nomap         (rsv_nomap),
  .rsv_drop_sq       (rsv_drop_sq),
  .rsv_type_dis      (rsv_type_dis),
  .rsv_accept        (rsv_accept),
  .rsv_slot          (rsv_slot),
  .upd               (upd),
  .upd_tage_val      (upd_tage_val),
  .upd_sc_val        (upd_sc_val),
  .upd_lp_val        (upd_lp_val),
  .upd_ittage_val    (upd_ittage_val),
  .upd_ubtb_val      (upd_ubtb_val)
);
