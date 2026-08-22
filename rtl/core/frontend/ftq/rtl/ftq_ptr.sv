// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FTQ head and middle pointers (BP-106).
//
// Owns alloc_ptr and fetch_ptr of ftq_decisions.md 5.1. commit_ptr
// is owned by ftq_commit.sv and arrives here as an INPUT; this
// module never writes it. That is the partition rule of 7.1 -- every
// piece of state has exactly one owner.
//
// Pointers are FTQ_PTR_BITS wide: the low FTQ_IDX_BITS index the
// 64-entry array, the top bit is the wrap generation. The generation
// bit is what separates full from empty when the low bits alias.
//
//   alloc_ptr  head.   Advances when a prediction request is
//                      ACCEPTED at p0 (5.2). The index leaves with
//                      the request as ftq_pred_idx_p0, so it is
//                      spoken for one cycle before the entry content
//                      is written at p1.
//   fetch_ptr  middle. Advances on ftq_ifu_req_val & _rdy.
//
//   empty  all three equal
//   full   alloc_ptr[IDX-1:0] == commit_ptr[IDX-1:0]
//          and alloc_ptr[IDX] != commit_ptr[IDX]
//
// FULL IS THE ONLY STALL (5.1). It is hold condition H2 of 4.5 and
// the only condition under which the FTQ stops predicting. The IFU
// being unable to accept a fetch is NOT a hold: that is the point of
// a decoupled front end.
//
// ALLOCATION IS UNCONDITIONAL (5.2). An entry is allocated for every
// prediction block, including one the p1 predictors miss, so a later
// stage has an entry to correct.
//
// WRAP-AWARE ORDER IS DONE BY AGE. Every live pointer lies in the
// window [commit_ptr, commit_ptr + FTQ_DEPTH]. Subtracting
// commit_ptr modulo 2**FTQ_PTR_BITS maps that window onto 0..64,
// where plain unsigned compare is the wrap-aware compare. Every
// ordering decision below is made on an age, never on a raw pointer.
//
// THE REDIRECT INDEX CARRIES NO WRAP BIT. bkend_ftq_redir_idx is
// FTQ_IDX_BITS wide (ftq_backend_interfaces.md 5), so the generation
// is reconstructed here from commit_ptr: the named entry is at or
// after commit_ptr (R2 makes that the backend's obligation), so an
// index below commit_ptr's low bits belongs to the next generation.
// This is the SECOND use of the commit_ptr input, alongside full.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_ptr (
  input  logic                     clk,
  input  logic                     rstn,

  // ---- commit_ptr, from ftq_commit.sv -----------------------------
  // Read only. Used for the full condition and for the generation
  // reconstruction of redir_idx. Never written here.
  input  logic [FTQ_PTR_BITS-1:0]  commit_ptr,

  // ---- allocation, p0 ---------------------------------------------
  // alloc_req_val is the prediction request the FTQ presents at p0.
  // alloc_req_rdy is the acceptance: hold condition H1 of 4.5 clear,
  // meaning every queued predictor can take the request. H2 is
  // formed here and returned as ftq_full.
  input  logic                     alloc_req_val,
  input  logic                     alloc_req_rdy,

  // ---- fetch issue -------------------------------------------------
  input  logic                     ifu_req_val,
  input  logic                     ifu_req_rdy,

  // ---- the p0-to-p1 allocation gap, from ftq_shadow ----------------
  // Set when a request accepted last cycle is at p1 now, so its
  // entry write has not landed yet. fetch_pending subtracts it: the
  // gap 5.1 calls the run-ahead is measured to the WRITTEN frontier,
  // not to alloc_ptr, because alloc_ptr advances at p0 and the entry
  // content is written at p1 (5.2). Without this the FTQ issues a
  // fetch for an entry one cycle before its pc exists, in the first
  // two cycles out of reset. A port 7.3 does not anticipate; see the
  // BP-107 Results Capture.
  input  logic                     alloc_inflight,

  // ---- redirect, from ftq_npc.sv (7.3) ----------------------------
  // The winning redirect of 4.3, already arbitrated. This module
  // acts on it; it does not decide it.
  //
  input  logic                     redir_val,
  input  logic [FTQ_IDX_BITS-1:0]  redir_idx,
  input  logic                     redir_self,
  input  ftq_redir_cause_e         redir_cause,

  // ---- pointers out ------------------------------------------------
  output logic [FTQ_PTR_BITS-1:0]  alloc_ptr,
  output logic [FTQ_PTR_BITS-1:0]  fetch_ptr,

  // ---- status ------------------------------------------------------
  // ftq_full is hold condition H2 (4.5). ftq_empty is the all-three-
  // equal condition of 5.1. fetch_pending says an allocated entry
  // has not yet been issued to the IFU; it is the run-ahead the FTQ
  // exists to provide, and it qualifies ftq_ifu_req_val.
  output logic                     ftq_full,
  output logic                     ftq_empty,
  output logic                     fetch_pending,

  // ---- observation, for the bound properties ------------------------
  // The literal full condition of 5.1: low bits equal, generation
  // differing. It is now a REACHABLE and CORRECT state -- the 64
  // live entries the widened watermark made safe -- so the property
  // bound to it says it agrees with ftq_full rather than that it
  // never occurs. Published as a port so the bind reads only the
  // port list and makes no hierarchical reference (TD#109).
  output logic                     ptr_alias_full,

  // ---- the squash range, for ftq_status (7.3) -----------------------
  // A redirect rewind frees the entries between the new alloc_ptr
  // and the old one (5.5 R3) and ftq_status must clear their wb_rcvd
  // and fault bits in the same cycle (ftq_entry_formats.md 4.2 W4).
  // The range is [squash_start, squash_end), both FTQ_PTR_BITS so
  // the consumer can take an age without repeating the generation
  // reconstruction this module already performs on redir_idx.
  //
  // 7.3 publishes the winning REDIRECT to ftq_status and leaves the
  // mask to it. Exporting the resolved range instead keeps one owner
  // for the reconstruction; see the BP-107 Results Capture.
  output logic                     squash_val,
  output logic [FTQ_PTR_BITS-1:0]  squash_start,
  output logic [FTQ_PTR_BITS-1:0]  squash_end,

  // ---- the entry index leaving with the p0 request ------------------
  output logic [FTQ_IDX_BITS-1:0]  alloc_idx,
  output logic [FTQ_IDX_BITS-1:0]  fetch_idx
);

  // -----------------------------------------------------------------
  // FTQ_ALLOC_LIMIT -- now the 5.1 condition, no longer a departure.
  // -----------------------------------------------------------------
  // 5.1 gives full as alloc_ptr[5:0] == commit_ptr[5:0] with the
  // generation bits differing, which is an age of FTQ_DEPTH: all 64
  // entries live. BP-106 built this one short, at FTQ_DEPTH-1,
  // because bkend_ftq_commit_idx was then FTQ_IDX_BITS wide and
  // carried no generation. At 64 live entries the watermark may name
  // any of 65 entries -- the 64 live ones plus the one just
  // committed, which section 6 promises may sit on the port
  // indefinitely -- and 6 bits cannot separate 65 values. Holding
  // allocation one short removed the 65th value.
  //
  // THE PORT WAS WIDENED INSTEAD (ftq_backend_interfaces.md 6,
  // 2026-08-21). The watermark now carries the generation, so
  // ftq_commit reconstructs nothing for it and the 65th value is no
  // longer ambiguous. The limit reverts and the 64th entry comes
  // back.
  //
  // IF THE PORT IS EVER NARROWED AGAIN this must return to
  // FTQ_DEPTH-1, and ftq_decisions.md 5.1 is the paragraph that
  // says why.
  localparam int FTQ_ALLOC_LIMIT = FTQ_DEPTH;

  // -----------------------------------------------------------------
  // Ages. See the header: every ordering decision is made on these.
  // -----------------------------------------------------------------
  logic [FTQ_PTR_BITS-1:0] w_age_alloc;
  logic [FTQ_PTR_BITS-1:0] w_age_fetch;
  logic [FTQ_PTR_BITS-1:0] w_age_written;

  // -----------------------------------------------------------------
  // Advance enables.
  // -----------------------------------------------------------------
  logic w_alloc_en;
  logic w_fetch_en;

  // -----------------------------------------------------------------
  // Redirect rewind targets (5.5 R1).
  // -----------------------------------------------------------------
  logic                    w_unspec;
  logic                    w_redir_gen;
  logic [FTQ_PTR_BITS-1:0] w_redir_base;
  logic [FTQ_PTR_BITS-1:0] w_alloc_tgt;
  logic [FTQ_PTR_BITS-1:0] w_fetch_tgt;
  logic [FTQ_PTR_BITS-1:0] w_age_alloc_tgt;

  // -----------------------------------------------------------------
  // Status, and the enables.
  // -----------------------------------------------------------------
  // One always_comb rather than a chain of assigns: w_alloc_en
  // depends on ftq_full, which depends on the pointers. CLAUDE.md
  // requires the textual-order form for a dependency chain.
  always_comb begin : status
    w_age_alloc = alloc_ptr - commit_ptr;
    w_age_fetch = fetch_ptr - commit_ptr;

    // The literal 5.1 condition, published for the property that it
    // never occurs. It is the age == FTQ_DEPTH case.
    ptr_alias_full = (alloc_ptr[FTQ_IDX_BITS-1:0] ==
                      commit_ptr[FTQ_IDX_BITS-1:0]) &&
                     (alloc_ptr[FTQ_IDX_BITS] !=
                      commit_ptr[FTQ_IDX_BITS]);

    // Hold condition H2. See FTQ_ALLOC_LIMIT above for why this is
    // one short of the 5.1 condition. Written >= rather than == so
    // no reachable state can walk past the limit undetected.
    ftq_full = (w_age_alloc >= FTQ_PTR_BITS'(FTQ_ALLOC_LIMIT));

    // All three equal. fetch_ptr cannot lead alloc_ptr under FQ-1,
    // so alloc == commit with the same generation is enough to make
    // fetch equal too; it is written out in full anyway because 5.1
    // states the condition over all three.
    ftq_empty = (w_age_alloc == '0) && (w_age_fetch == '0);

    // The WRITTEN frontier, not alloc_ptr. See the alloc_inflight
    // port comment. Written as a compare against a subtracted age
    // rather than as an inequality on the raw pointers, because the
    // subtraction can take the frontier back to fetch_ptr and the
    // result must then be false, not wrap.
    w_age_written = w_age_alloc - {{(FTQ_PTR_BITS-1){1'b0}},
                                   alloc_inflight};
    fetch_pending = (w_age_fetch != w_age_alloc) &&
                    (w_age_fetch < w_age_written);

    // Full blocks allocation AND NOTHING ELSE. The gate is here as
    // well as in the H2 path so the pointer cannot be walked past
    // commit_ptr by a caller that ignores ftq_full.
    w_alloc_en = alloc_req_val & alloc_req_rdy & ~ftq_full;

    // fetch_ptr may not pass alloc_ptr (FQ-1). Same reasoning:
    // fetch_pending is published for the caller to qualify its
    // request with, and enforced here regardless.
    w_fetch_en = ifu_req_val & ifu_req_rdy & fetch_pending;
  end

  assign alloc_idx = alloc_ptr[FTQ_IDX_BITS-1:0];
  assign fetch_idx = fetch_ptr[FTQ_IDX_BITS-1:0];

  // The squash range of 5.5 R3. w_alloc_tgt is the new head, so
  // everything from it up to the current head is squashed. On
  // RC_UNSPEC w_alloc_tgt is commit_ptr and the range is every live
  // entry, which is 5.1 U3 falling out rather than being cased.
  assign squash_val   = redir_val;
  assign squash_start = w_alloc_tgt;
  assign squash_end   = alloc_ptr;

  // -----------------------------------------------------------------
  // Redirect rewind, 5.5 R1.
  // -----------------------------------------------------------------
  //   _self clear -> the naming instruction COMPLETED and everything
  //                  after it is squashed. Entry K survives, so
  //                  allocation restarts at K+1.
  //   _self set   -> the naming instruction is squashed too. Entry K
  //                  does not survive, so allocation restarts at K.
  //
  // RC_UNSPEC ignores _idx and _self entirely (5.1 U1, U2, U3): it
  // squashes EVERY entry, so allocation restarts at commit_ptr and
  // the queue goes empty. commit_ptr itself never rewinds (R2).
  //
  // fetch_ptr rewinds WITH alloc_ptr, but only when it is ahead of
  // the new head. A fetch_ptr that had not yet reached the squash
  // point still has live entries in front of it and must not be
  // pushed forward.
  always_comb begin : rewind
    w_unspec = (redir_cause == RC_UNSPEC);

    // Reconstruct the generation of the naming index. R2 puts it at
    // or after commit_ptr, so a low-bit value below commit_ptr's
    // must belong to the next generation.
    w_redir_gen = (redir_idx >= commit_ptr[FTQ_IDX_BITS-1:0]) ?
                    commit_ptr[FTQ_IDX_BITS] :
                    ~commit_ptr[FTQ_IDX_BITS];

    w_redir_base = {w_redir_gen, redir_idx};

    if (w_unspec) begin
      w_alloc_tgt = commit_ptr;
    end else if (redir_self) begin
      w_alloc_tgt = w_redir_base;
    end else begin
      w_alloc_tgt = w_redir_base + {{(FTQ_PTR_BITS-1){1'b0}}, 1'b1};
    end

    w_age_alloc_tgt = w_alloc_tgt - commit_ptr;

    w_fetch_tgt = (w_age_fetch > w_age_alloc_tgt) ? w_alloc_tgt
                                                  : fetch_ptr;
  end

  // -----------------------------------------------------------------
  // State.
  // -----------------------------------------------------------------
  // A redirect outranks allocation and fetch issue in the same cycle
  // (ftq_backend_interfaces.md 7 R1): the redirect squashes entries
  // an allocation in the same cycle would extend past.
  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      alloc_ptr <= '0;
      fetch_ptr <= '0;
    end else if (redir_val) begin
      alloc_ptr <= w_alloc_tgt;
      fetch_ptr <= w_fetch_tgt;
    end else begin
      if (w_alloc_en) begin
        alloc_ptr <= alloc_ptr + {{(FTQ_PTR_BITS-1){1'b0}}, 1'b1};
      end
      if (w_fetch_en) begin
        fetch_ptr <= fetch_ptr + {{(FTQ_PTR_BITS-1){1'b0}}, 1'b1};
      end
    end
  end

endmodule : ftq_ptr
