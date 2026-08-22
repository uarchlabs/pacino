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
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_ifu_assert (
  input logic                     clk,
  input logic                     rstn,
  input logic [FTQ_IDX_BITS-1:0]  fetch_idx,
  input logic                     fetch_pending,
  input bp_ftq_entry_t            fetch_entry,
  input logic                     gen_fetch,
  input logic                     gen_pdwb,
  input logic                     wb_rcvd_pdwb,
  input logic                     redir_val,
  input logic                     ftq_ifu_req_val,
  input logic [VA_WIDTH-1:0]      ftq_ifu_start_pc,
  input logic [VA_WIDTH-1:0]      ftq_ifu_next_pc,
  input logic [FTQ_IDX_BITS-1:0]  ftq_ifu_idx,
  input logic                     ftq_ifu_taken_val,
  input logic [FTB_BR_POS_BITS-1:0] ftq_ifu_taken_pos,
  input logic                     ftq_ifu_gen,
  input logic                     ftq_ifu_flush_val,
  input logic                     ifu_ftq_pdwb_val,
  input logic                     ifu_ftq_pdwb_gen,
  input logic                     ifu_ftq_mis_val,
  input logic                     ifu_ftq_fault_val,
  input logic                     wb_set_val,
  input logic                     fault_set_val,
  input logic                     pd_wr_val,
  input logic [TRX_SLOT_BITS-1:0] pd_wr_sel,
  input bp_ftq_slot_t             pd_wr_slot,
  input logic                     pd_redir_val,
  input logic [VA_WIDTH-1:0]      pd_redir_pc,
  input logic                     wb_accept,
  input logic                     wb_drop_gen
);

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

  // I4  R3 of ftq_entry_formats.md 4.3. An entry derives AT MOST
  //     ONE predecode redirect, and only from its own writeback. A
  //     second writeback naming an entry that already has wb_rcvd
  //     set is a protocol violation, not a second redirect -- and
  //     acting on it would redirect the front end to a block it has
  //     already fetched past.
  property p_one_redirect_per_entry;
    @(posedge clk) disable iff (!rstn)
      wb_rcvd_pdwb |-> !pd_redir_val;
  endproperty

  // I5  THE ENTRY REWRITE AND THE REDIRECT ARE ONE EVENT. W1 and W3
  //     of section 7 fire together: the slot is corrected and fetch
  //     restarts from the corrected successor. Correcting without
  //     redirecting leaves the front end fetching the wrong stream;
  //     redirecting without correcting sends it back to an entry
  //     that still describes the branch predecode disproved, so the
  //     next fetch of that entry repeats the mistake.
  property p_write_and_redirect_together;
    @(posedge clk) disable iff (!rstn)
      pd_wr_val == pd_redir_val;
  endproperty

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

  // I7  The request carries the entry's OWN index and generation.
  //     ftq_ifu_gen is an opaque tag the IFU stores and returns
  //     unchanged (section 4), so if the wrong one leaves here every
  //     writeback for that entry fails the 6.1 test and is dropped
  //     -- the entry never receives its predecode correction and
  //     nothing reports it.
  property p_request_self;
    @(posedge clk) disable iff (!rstn)
      ftq_ifu_req_val |-> (ftq_ifu_idx == fetch_idx) &&
                          (ftq_ifu_gen == gen_fetch) &&
                          (ftq_ifu_start_pc == fetch_entry.pc);
  endproperty

  // I8  No request without a pending entry. fetch_pending is the
  //     run-ahead of 5.1 measured to the WRITTEN frontier, so this
  //     is also what stops a request for an entry whose p1 write has
  //     not landed.
  property p_request_needs_pending;
    @(posedge clk) disable iff (!rstn)
      ftq_ifu_req_val |-> fetch_pending;
  endproperty

  // I9  The flush is driven by the redirect and by nothing else.
  //     ONE group, not two: every source -- p2, p3, predecode,
  //     backend -- has already been resolved into the winning
  //     redirect before it reaches here (section 5, FE-3).
  property p_flush_is_redirect;
    @(posedge clk) disable iff (!rstn)
      ftq_ifu_flush_val == redir_val;
  endproperty

  // I10 taken_val is set exactly when a slot of the entry is valid
  //     and taken. It tells the IFU to TRUNCATE the bundle, so
  //     setting it with no taken branch cuts a block short and
  //     clearing it with one lets the IFU present instructions past
  //     a branch the FTQ predicted taken.
  property p_taken_val_has_slot;
    @(posedge clk) disable iff (!rstn)
      (ftq_ifu_req_val && ftq_ifu_taken_val) |->
        ((fetch_entry.slot[0].slot_valid && fetch_entry.slot[0].taken)
      || (fetch_entry.slot[1].slot_valid && fetch_entry.slot[1].taken));
  endproperty

  // I11 The complement, and the other half of section 4: "not valid
  //     means fetch the whole block". With no taken slot the
  //     successor is the fall-through, which is fe_decisions.md
  //     2.4's third arm read off the stored entry.
  property p_not_taken_is_pft;
    @(posedge clk) disable iff (!rstn)
      (ftq_ifu_req_val && !ftq_ifu_taken_val) |->
        (ftq_ifu_next_pc == fetch_entry.pft_addr);
  endproperty

  a_stale_wb_dropped:   assert property (p_stale_wb_dropped)
    else $error("I1 a stale writeback was not dropped entirely");
  a_accept_needs_match: assert property (p_accept_needs_match)
    else $error("I2 the writeback accept does not track the gen test");
  a_redir_needs_mis:    assert property (p_redir_needs_mis)
    else $error("I3 a predecode redirect with no structural mispredict");
  a_one_redirect:       assert property (p_one_redirect_per_entry)
    else $error("I4 a second predecode redirect for one entry");
  a_write_and_redirect: assert property (p_write_and_redirect_together)
    else $error("I5 the slot rewrite and the redirect disagree");
  a_redir_pc_corrected: assert property (p_redir_pc_is_corrected)
    else $error("I6 the redirect PC is not the corrected successor");
  a_request_self:       assert property (p_request_self)
    else $error("I7 the fetch request does not describe its entry");
  a_request_pending:    assert property (p_request_needs_pending)
    else $error("I8 a fetch was requested for no pending entry");
  a_flush_is_redirect:  assert property (p_flush_is_redirect)
    else $error("I9 the IFU flush does not track the redirect");
  a_taken_val_has_slot: assert property (p_taken_val_has_slot)
    else $error("I10 taken_val set with no taken slot in the entry");
  a_not_taken_is_pft:   assert property (p_not_taken_is_pft)
    else $error("I11 no taken slot but next_pc is not the pft_addr");

  logic w_unused;
  assign w_unused = |ftq_ifu_taken_pos | |pd_wr_sel |
                    ifu_ftq_fault_val;

endmodule : ftq_ifu_assert

// Bind BY MODULE NAME.
bind ftq_ifu ftq_ifu_assert u_assert (
  .clk               (clk),
  .rstn              (rstn),
  .fetch_idx         (fetch_idx),
  .fetch_pending     (fetch_pending),
  .fetch_entry       (fetch_entry),
  .gen_fetch         (gen_fetch),
  .gen_pdwb          (gen_pdwb),
  .wb_rcvd_pdwb      (wb_rcvd_pdwb),
  .redir_val         (redir_val),
  .ftq_ifu_req_val   (ftq_ifu_req_val),
  .ftq_ifu_start_pc  (ftq_ifu_start_pc),
  .ftq_ifu_next_pc   (ftq_ifu_next_pc),
  .ftq_ifu_idx       (ftq_ifu_idx),
  .ftq_ifu_taken_val (ftq_ifu_taken_val),
  .ftq_ifu_taken_pos (ftq_ifu_taken_pos),
  .ftq_ifu_gen       (ftq_ifu_gen),
  .ftq_ifu_flush_val (ftq_ifu_flush_val),
  .ifu_ftq_pdwb_val  (ifu_ftq_pdwb_val),
  .ifu_ftq_pdwb_gen  (ifu_ftq_pdwb_gen),
  .ifu_ftq_mis_val   (ifu_ftq_mis_val),
  .ifu_ftq_fault_val (ifu_ftq_fault_val),
  .wb_set_val        (wb_set_val),
  .fault_set_val     (fault_set_val),
  .pd_wr_val         (pd_wr_val),
  .pd_wr_sel         (pd_wr_sel),
  .pd_wr_slot        (pd_wr_slot),
  .pd_redir_val      (pd_redir_val),
  .pd_redir_pc       (pd_redir_pc),
  .wb_accept         (wb_accept),
  .wb_drop_gen       (wb_drop_gen)
);
