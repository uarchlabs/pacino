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
  input logic [NUM_PRED_SLOTS-1:0] upd_ubtb_val,
  // BP-120, for R16 to R19.
  input logic [NUM_RESOLVE_PORTS-1:0] ftb_sched_rdy,
  input logic [NUM_RESOLVE_PORTS-1:0] rsv_wr_val,
  input logic [FTQ_IDX_BITS-1:0] rsv_wr_idx [0:NUM_RESOLVE_PORTS-1],
  input logic [TRX_SLOT_BITS-1:0] rsv_wr_sel [0:NUM_RESOLVE_PORTS-1]
);

  genvar gc;
  generate
    for (gc = 0; gc < NUM_RESOLVE_PORTS; gc++) begin : g_chan

      // R1  Every presented resolution lands in EXACTLY ONE bucket:
      //     accepted or dropped as squashed; an unmapped one is
      //     accepted (placed, BP-119) and also reported. A resolution
      //     that fell through both would vanish with no update formed
      //     and nothing said -- the silent drop the acceptance
      //     criterion forbids. This read "$onehot({accept, nomap,
      //     drop_sq})" while an unmapped resolution formed nothing.
      property p_one_bucket;
        @(posedge clk) disable iff (!rstn)
          bkend_rsv_val[gc] |->
            $onehot({rsv_accept[gc], rsv_drop_sq[gc]}) &&
            (!rsv_nomap[gc] || rsv_accept[gc]);
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

      // R3  An unmapped position is PLACED IN PROGRAM ORDER (BP-119):
      //     the slot it takes holds no EARLIER branch of the entry,
      //     unless every slot does (then it takes the last). Stated on
      //     the entry the module read, not on its selection loop.
      //     This read "an unmapped position forms NO update" before
      //     the ruling to train the first execution.
      property p_nomap_placed_in_order;
        @(posedge clk) disable iff (!rstn)
          rsv_nomap[gc] |->
            !(rsv_entry[gc].slot[rsv_slot[gc]].slot_valid &&
              (rsv_entry[gc].slot[rsv_slot[gc]].pos < bkend_rsv[gc].pos))
            || (rsv_slot[gc] == TRX_SLOT_BITS'(NUM_PRED_SLOTS - 1) &&
                rsv_entry[gc].slot[0].slot_valid &&
                (rsv_entry[gc].slot[0].pos < bkend_rsv[gc].pos));
      endproperty
      a_nomap_placed_in_order: assert property (p_nomap_placed_in_order)
        else $error("R3 an unmapped branch was placed out of order");

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

  // -----------------------------------------------------------------
  // BP-120. TD#157, THE FTB TRAINED ONCE PER RESOLUTION, and TD#158,
  // TWO RESOLUTIONS NEVER GIVEN ONE SLOT. Each is stated against a
  // source the RTL does not drive: a model of the presentation built
  // here from earlier cycles (R16, R17), or a program order this file
  // derives itself from the pointers and the resolutions (R18).
  // -----------------------------------------------------------------

  // The presentation model. m_taken[c]: the scheduler has taken
  // channel c's FTB update (presented with the scheduler ready) at
  // some cycle of the CURRENT presentation, which is the run of cycles
  // the backend holds one branch -- one entry index and position --
  // valid, until the channel is accepted (A4). Built from the ports,
  // cycle by cycle.
  logic [NUM_RESOLVE_PORTS-1:0] m_taken;
  ftq_resolve_t                 m_prev [0:NUM_RESOLVE_PORTS-1];

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      m_taken <= '0;
      for (int c = 0; c < NUM_RESOLVE_PORTS; c++) m_prev[c] <= '0;
    end else begin
      for (int c = 0; c < NUM_RESOLVE_PORTS; c++) begin
        m_prev[c]  <= bkend_rsv[c];
        m_taken[c] <= bkend_rsv_val[c] && !ftq_bkend_rsv_rdy[c] &&
                      (w_taken_now[c] || w_same_held[c]);
      end
    end
  end

  logic [NUM_RESOLVE_PORTS-1:0] w_taken_now;
  logic [NUM_RESOLVE_PORTS-1:0] w_same_held;
  always_comb begin
    for (int c = 0; c < NUM_RESOLVE_PORTS; c++) begin
      w_taken_now[c] = ftb_upd_val[c] && ftb_sched_rdy[c];
      // Still the presentation m_taken describes: m_taken set means
      // the channel was presented and not accepted last cycle, and the
      // same resolution is presented now.
      w_same_held[c] = m_taken[c] && bkend_rsv_val[c] &&
                       (bkend_rsv[c].ftq_idx == m_prev[c].ftq_idx) &&
                       (bkend_rsv[c].pos     == m_prev[c].pos);
    end
  end

  // The program order of the two channels, derived here: the entry
  // nearer commit_ptr is older; within one entry the lower position;
  // then channel 0. Ages are wrap-aware, (idx - commit) modulo the
  // queue, so the order holds across the array boundary.
  logic [FTQ_IDX_BITS-1:0] w_age0;
  logic [FTQ_IDX_BITS-1:0] w_age1;
  logic                    w_ch1_older;
  always_comb begin
    w_age0 = bkend_rsv[0].ftq_idx - commit_ptr[FTQ_IDX_BITS-1:0];
    w_age1 = bkend_rsv[1].ftq_idx - commit_ptr[FTQ_IDX_BITS-1:0];
    w_ch1_older = (w_age1 < w_age0) ||
                  ((w_age1 == w_age0) &&
                   (bkend_rsv[1].pos < bkend_rsv[0].pos));
  end

  genvar gt;
  generate
    for (gt = 0; gt < NUM_RESOLVE_PORTS; gt++) begin : g_once

      // R16 TD#157. Once the scheduler has taken a held resolution's
      //     FTB update, the FTB update is not presented again for the
      //     same presentation. Before BP-120 it was presented every
      //     cycle the resolution was held for a predictor.
      property p_ftb_once;
        @(posedge clk) disable iff (!rstn)
          w_same_held[gt] |-> !ftb_upd_val[gt];
      endproperty
      a_ftb_once: assert property (p_ftb_once)
        else $error("R16 a held resolution trained the FTB again");

      // R17 TD#157, the other half of "exactly once". An FTB-bound
      //     live resolution is not accepted unless its FTB update was
      //     taken this cycle or earlier in the presentation. An FE-5a
      //     LOW drop is taken by the scheduler and counts.
      property p_ftb_not_lost;
        @(posedge clk) disable iff (!rstn)
          (bkend_rsv_val[gt] && ftq_bkend_rsv_rdy[gt] && rsv_accept[gt] &&
           (bkend_rsv[gt].br_type != NO_BRANCH)) |->
            (w_taken_now[gt] || w_same_held[gt]);
      endproperty
      a_ftb_not_lost: assert property (p_ftb_not_lost)
        else $error("R17 a resolution was accepted without its FTB update");

    end
  endgenerate

  // R18 TD#158, ONE SLOT, ONE CHANNEL, OLDER FIRST. When both channels
  //     are live and name the same slot, the younger in program order
  //     (derived above) is not accepted, and the slot's update, when
  //     formed, is the older's. Before BP-120 both were reported ready
  //     and the later channel's payload overwrote the earlier's.
  property p_slot_older_first;
    @(posedge clk) disable iff (!rstn)
      (rsv_accept[0] && rsv_accept[1] && (rsv_slot[0] == rsv_slot[1])) |->
        (w_ch1_older ? !ftq_bkend_rsv_rdy[0] : !ftq_bkend_rsv_rdy[1]) &&
        (!upd[rsv_slot[0]].valid ||
         (w_ch1_older
            ? ((upd[rsv_slot[0]].branch_id     == bkend_rsv[1].ftq_idx) &&
               (upd[rsv_slot[0]].actual_target == bkend_rsv[1].target))
            : ((upd[rsv_slot[0]].branch_id     == bkend_rsv[0].ftq_idx) &&
               (upd[rsv_slot[0]].actual_target == bkend_rsv[0].target))));
  endproperty
  a_slot_older_first: assert property (p_slot_older_first)
    else $error("R18 two resolutions were given one slot, or the younger first");

  // R19 TD#158. Two placement writes in one cycle to one entry name
  //     different slots, so the entry holds both. Before BP-120 the
  //     two placements of one entry read the same bare entry and could
  //     name the same free slot; the later write won.
  property p_place_two_slots;
    @(posedge clk) disable iff (!rstn)
      (rsv_wr_val[0] && rsv_wr_val[1] && (rsv_wr_idx[0] == rsv_wr_idx[1]))
        |-> (rsv_wr_sel[0] != rsv_wr_sel[1]);
  endproperty
  a_place_two_slots: assert property (p_place_two_slots)
    else $error("R19 two placements of one entry took the same slot");

  // R20, R21 (BP-122, TD#170): the BP-121 fixes in this unit.
  genvar gw;
  generate
    for (gw = 0; gw < NUM_RESOLVE_PORTS; gw++) begin : g_bp121

      // R20 BP-121 D2 (m02). EVERY accepted resolution of a branch
      //     writes its slot of the entry it names, at the slot its
      //     position maps or is placed to, on the cycle its channel is
      //     ready -- a mapped one too. Before BP-121 only a placed
      //     (unmapped) resolution wrote, so a mapped slot kept its
      //     PREDICTION and the commit walk committed what the front
      //     end guessed, not what executed. Stated from the resolution
      //     and the acceptance, not from the write enable's terms.
      property p_every_resolved_slot_written;
        @(posedge clk) disable iff (!rstn)
          (rsv_accept[gw] && ftq_bkend_rsv_rdy[gw] &&
           (bkend_rsv[gw].br_type != NO_BRANCH)) |->
            rsv_wr_val[gw] &&
            (rsv_wr_idx[gw] == bkend_rsv[gw].ftq_idx) &&
            (rsv_wr_sel[gw] == rsv_slot[gw]);
      endproperty
      a_every_rsv_written: assert property (p_every_resolved_slot_written)
        else $error("R20 an accepted resolution did not write its slot");

      // R21 BP-121 D3, TD#164 (m03). The FTB update of a TAKEN JUMP
      //     carries that jump's own end as the block fall-through: the
      //     update's block PC, plus the jump's position, plus its
      //     length (2 for a compressed jump). The value is derived
      //     here from three other fields of the same payload, which
      //     the FTB stores separately and which must agree. Before
      //     BP-121 it was the entry's PREDICTED fall-through, which for
      //     a block first predicted without the jump is the start plus
      //     one block, so the FTB learned that and the RAS pushed it.
      property p_jump_ft_is_jump_end;
        @(posedge clk) disable iff (!rstn)
          (ftb_upd_val[gw] && bkend_rsv[gw].taken &&
           (bkend_rsv[gw].br_type != COND) &&
           (bkend_rsv[gw].br_type != NO_BRANCH)) |->
            (ftb_upd[gw].pft_addr ==
             ftb_upd[gw].pc
             + (VA_WIDTH'(ftb_upd[gw].pos) << POS_OFFSET_BITS)
             + (ftb_upd[gw].jmp_rvc ? VA_WIDTH'(2) : VA_WIDTH'(4)));
      endproperty
      a_jump_ft_is_jump_end: assert property (p_jump_ft_is_jump_end)
        else $error("R21 a taken jump trained the FTB with another end");

    end
  endgenerate

  // R15 REMOVED, BP-119. It read "(ftq_bkend_rsv_rdy == '0) |-> no
  //     upd valid": no update formed while no channel was ready. The
  //     predictor valids are now REQUESTS (ftq_resolve header): they
  //     are qualified by the FTB scheduler's ready only, and
  //     ftq_upd_conv gates them on the slot being accepted by every
  //     predictor it trains. The guarantee R15 carried is the
  //     converter's V1 and V2. Restated on the scheduler's ready it
  //     would repeat the fan-out's own gate, which is not a check
  //     (CLAUDE.md, assertions).

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
  .upd_ubtb_val      (upd_ubtb_val),
  .ftb_sched_rdy     (ftb_sched_rdy),
  .rsv_wr_val        (rsv_wr_val),
  .rsv_wr_idx        (rsv_wr_idx),
  .rsv_wr_sel        (rsv_wr_sel)
);
