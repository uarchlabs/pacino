// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ftq_ifu (BP-107), ftq_ifu_interfaces.md.
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
//
// I1 IS THE TD-FE-8 CLOSURE. A writeback whose generation does not
// match is DROPPED ENTIRELY -- no status bit set, no redirect
// derived, no field rewritten (6.1 X3). "Entirely" is four separate
// outputs and the property states all four, because a partial drop
// is the failure that produced TD-FE-8 in the first place: the
// status bits set on the wrong use of a reallocated index.
//
// BP-116, TD#144. Nine labels restated a direct assignment in this
// module and could not fail (CLAUDE.md Verification - assertions).
// Each is removed with a one-line note at its old place. Their
// rules are checked where an independent source exists: ftq_ptr Q11
// and Q12, ftq_entry E8, E9 and E10, ftq_npc N5, and tb_ftq_ifu
// groups A, G and I.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_ifu_assert (
  input logic                     clk,
  input logic                     rstn,
  input logic [FTQ_PTR_BITS-1:0]  commit_ptr,
  input logic                     gen_pdwb,
  input logic                     wb_rcvd_pdwb,
  input logic                     redir_val,
  input logic [FTQ_IDX_BITS-1:0]  redir_idx,
  input logic                     redir_self,
  input ftq_redir_cause_e         redir_cause,
  input logic [5:1]               redir_arm,
  input logic [FTQ_IDX_BITS-1:0]  ftq_ifu_flush_idx,
  input logic                     ifu_ftq_pdwb_val,
  input logic                     ifu_ftq_pdwb_gen,
  input logic                     ifu_ftq_mis_val,
  input logic                     wb_set_val,
  input logic                     fault_set_val,
  input logic                     pd_wr_val,
  input bp_ftq_slot_t             pd_wr_slot,
  input logic                     pd_redir_val,
  input logic [VA_WIDTH-1:0]      pd_redir_pc,
  input logic                     wb_accept,
  input logic                     wb_drop_gen
);

  // ftq_npc's arm numbering, as ftq_ifu declares it.
  localparam int ARM_PD = 2;
  localparam int ARM_P3 = 3;
  localparam int ARM_P2 = 4;

  // The two front-end sets of 5.5 R1, by arm. p2 and p3 keep K;
  // predecode flushes past it (BP-117, TD#146).
  logic w_keep_k;
  logic w_pd_redir;
  always_comb begin : fe_set
    w_keep_k   = redir_arm[ARM_P3] | redir_arm[ARM_P2];
    w_pd_redir = redir_arm[ARM_PD];
  end

  // I1  A stale writeback is dropped ENTIRELY. 6.1 X3, and the four
  //     outputs are the whole of "entirely".
  property p_stale_wb_dropped;
    @(posedge clk) disable iff (!rstn)
      wb_drop_gen |-> !wb_set_val && !fault_set_val &&
                      !pd_redir_val && !pd_wr_val;
  endproperty

  // I2  A writeback is accepted only on a generation MATCH, and
  //     only when one was presented. The complement of I1: a module
  //     that dropped everything would satisfy I1 and never accept a
  //     current writeback, so the entry would keep its p1 view and
  //     no predecode correction would ever land.
  property p_accept_needs_match;
    @(posedge clk) disable iff (!rstn)
      wb_accept == (ifu_ftq_pdwb_val && (ifu_ftq_pdwb_gen ==
                                         gen_pdwb));
  endproperty

  // I3  No predecode redirect without an accepted writeback
  //     carrying a STRUCTURAL mispredict. M1 to M4 are the four
  //     shapes predecode can prove without executing anything; a
  //     conditional's direction is not among them, and the IFU
  //     reports the result on ifu_ftq_mis_val.
  property p_redir_needs_mis;
    @(posedge clk) disable iff (!rstn)
      pd_redir_val |-> wb_accept && ifu_ftq_mis_val;
  endproperty

  // I4  R3 and R3a of ftq_entry_formats.md 4.3 (TD#140, BP-114). A
  //     second writeback naming an entry that already has wb_rcvd set
  //     is LEGAL, with gen unchanged. R3a was written for the W3
  //     refetch of K, which BP-117 (TD#146) removed by flushing a
  //     predecode redirect at K+1; the rule is kept as the bound. So
  //     a current one (gen matches) is ACCEPTED and sets the status
  //     like any other, and it
  //     derives NO redirect whatever its predecode result -- R3's
  //     bound of one predecode redirect per entry is what stops a
  //     refetch loop. A stale one (gen differs) is I1's case.
  //     This read "a protocol violation" until BP-114; the redirect
  //     half was already the property, the acceptance half is new.
  property p_refetch_wb_no_redirect;
    @(posedge clk) disable iff (!rstn)
      wb_rcvd_pdwb |-> !pd_redir_val;
  endproperty

  property p_refetch_wb_accepted;
    @(posedge clk) disable iff (!rstn)
      (ifu_ftq_pdwb_val && wb_rcvd_pdwb && (ifu_ftq_pdwb_gen == gen_pdwb))
        |-> wb_accept && wb_set_val;
  endproperty

  // I5 removed: pd_wr_val == pd_redir_val is one assign; see E9, N5.

  // I6  W3. The redirect PC is the successor of the CORRECTED
  //     entry. When the correction leaves a taken branch in the slot
  //     it wrote, that slot's target is where fetch resumes; the
  //     kill of the slots above it is what makes this the whole
  //     selection and not just one arm of it.
  property p_redir_pc_is_corrected;
    @(posedge clk) disable iff (!rstn)
      (pd_redir_val && pd_wr_slot.slot_valid && pd_wr_slot.taken)
        |-> (pd_redir_pc == pd_wr_slot.target);
  endproperty

  // I7 removed: request idx/gen/pc restated the assign; tb groups A, I.
  // I8 removed: req_val |-> fetch_pending is one assign; see ptr Q12.
  // I9 removed: flush_val == redir_val is one assign; no other source.
  // I10 removed: taken_val restated the slot loop; tb groups A, I.
  // I11 removed: next_pc == pft restated the slot loop; tb groups A, I.

  // I12 7 W3 and ifu_ibuf_interfaces.md IB-13. A p2 or p3 redirect
  //     flushes AT K: K survives, corrected, and a fetch of K issued
  //     against the old prediction truncates in the wrong place.
  //     TD#126 flushed at K+1 for every surviving entry. CHANGED BY
  //     BP-117: the antecedent included the predecode arm.
  property p_fe_flush_at_k;
    @(posedge clk) disable iff (!rstn)
      (redir_val && w_keep_k && (redir_cause != RC_UNSPEC)) |->
        (ftq_ifu_flush_idx == redir_idx);
  endproperty

  // I12a 7 W3, IB-13 and 5.5 R1, ruled session-074 (TD#146, BP-117).
  //     A predecode redirect flushes at K+1: K is fetched and its head
  //     is in the ibuf, which does not clear on it (IB-12), so a
  //     refetch of K delivers that head twice. The index is formed
  //     here from redir_idx, not taken from the arm decode ftq_ifu
  //     uses, and _self is not read: the predecode row is K+1
  //     whatever it carries.
  property p_pd_flush_past_k;
    @(posedge clk) disable iff (!rstn)
      (redir_val && w_pd_redir && (redir_cause != RC_UNSPEC)) |->
        (ftq_ifu_flush_idx == FTQ_IDX_BITS'(redir_idx + 1'b1));
  endproperty

  // I13 The backend half, unchanged by BP-112 (ftq_backend_interfaces
  //     .md 5 D5). _self clear flushes at K+1, _self set at K. CHANGED
  //     BY BP-117: the predecode arm is I12a's, not this row's.
  property p_bkend_flush_by_self;
    @(posedge clk) disable iff (!rstn)
      (redir_val && !w_keep_k && !w_pd_redir &&
       (redir_cause != RC_UNSPEC)) |->
        (ftq_ifu_flush_idx == (redir_self ? redir_idx
                                          : redir_idx + 1'b1));
  endproperty

  // I14 removed: xlate idx/pc restated the assign; see entry E10.
  // I15 removed: xlate_val |-> xlate_pending is one assign; see Q11.

  a_stale_wb_dropped:   assert property (p_stale_wb_dropped)
    else $error("I1 a stale writeback was not dropped entirely");
  a_accept_needs_match: assert property (p_accept_needs_match)
    else $error("I2 the writeback accept does not track the gen test");
  a_redir_needs_mis:    assert property (p_redir_needs_mis)
    else $error("I3 a predecode redirect with no structural mispredict");
  a_refetch_no_redir:   assert property (p_refetch_wb_no_redirect)
    else $error("I4 a writeback on a set wb_rcvd derived a redirect");
  a_refetch_accepted:   assert property (p_refetch_wb_accepted)
    else $error("I4 a current writeback on a set wb_rcvd was rejected");
  a_redir_pc_corrected: assert property (p_redir_pc_is_corrected)
    else $error("I6 the redirect PC is not the corrected successor");
  a_fe_flush_at_k:      assert property (p_fe_flush_at_k)
    else $error("I12 a p2 or p3 redirect did not flush at K");
  a_pd_flush_past_k:    assert property (p_pd_flush_past_k)
    else $error("I12a a predecode redirect did not flush at K+1");
  a_bkend_flush_self:   assert property (p_bkend_flush_by_self)
    else $error("I13 the backend flush index does not follow _self");
  // I16 ftq_backend_interfaces.md 5.1 U3 (TD#141, BP-114). RC_UNSPEC
  //     squashes EVERY entry, so the flush names the oldest live one,
  //     commit_ptr's index, and section 5 drops every in-flight fetch.
  //     fetch_idx left those between commit_ptr and fetch_ptr alive.
  property p_unspec_flush_at_commit;
    @(posedge clk) disable iff (!rstn)
      (redir_val && (redir_cause == RC_UNSPEC)) |->
        (ftq_ifu_flush_idx == commit_ptr[FTQ_IDX_BITS-1:0]);
  endproperty

  // I17 removed: commit_ptr export is one assign; tb_ftq_ifu group H.

  a_unspec_flush:       assert property (p_unspec_flush_at_commit)
    else $error("I16 RC_UNSPEC did not flush at commit_ptr");

endmodule : ftq_ifu_assert

// Bind BY MODULE NAME.
bind ftq_ifu ftq_ifu_assert u_assert (
  .clk               (clk),
  .rstn              (rstn),
  .commit_ptr        (commit_ptr),
  .gen_pdwb          (gen_pdwb),
  .wb_rcvd_pdwb      (wb_rcvd_pdwb),
  .redir_val         (redir_val),
  .redir_idx         (redir_idx),
  .redir_self        (redir_self),
  .redir_cause       (redir_cause),
  .redir_arm         (redir_arm),
  .ftq_ifu_flush_idx (ftq_ifu_flush_idx),
  .ifu_ftq_pdwb_val  (ifu_ftq_pdwb_val),
  .ifu_ftq_pdwb_gen  (ifu_ftq_pdwb_gen),
  .ifu_ftq_mis_val   (ifu_ftq_mis_val),
  .wb_set_val        (wb_set_val),
  .fault_set_val     (fault_set_val),
  .pd_wr_val         (pd_wr_val),
  .pd_wr_slot        (pd_wr_slot),
  .pd_redir_val      (pd_redir_val),
  .pd_redir_pc       (pd_redir_pc),
  .wb_accept         (wb_accept),
  .wb_drop_gen       (wb_drop_gen)
);
