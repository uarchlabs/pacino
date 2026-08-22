// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FTQ per-entry fetch status (BP-107).
//
// Owns the three vectors of ftq_entry_formats.md 4: wb_rcvd, fault
// and gen, each FTQ_DEPTH deep. 192 flops.
//
// THESE ARE FLOPS, NOT SRAM, and 4.1 gives three reasons of which
// the third is decisive: a redirect rewind squashes every entry
// after an index and must clear their status in ONE cycle. In flops
// that is a masked clear; in SRAM it is a walk, and the walk would
// have to finish before those indices could be reallocated. That is
// also why this is a separate module from ftq_entry -- a different
// STORAGE CLASS, made structural rather than left as a comment
// (ftq_decisions.md 7.4).
//
// WRITE AND CLEAR, ftq_entry_formats.md 4.2:
//
//   W1  wb_rcvd and fault CLEAR at allocation, and gen TOGGLES.
//       Allocation is the only producer of a fresh entry, so it is
//       the one place a stale bit could otherwise survive a wrap.
//   W2  wb_rcvd SETS on a writeback naming this index with a
//       matching gen. The gen test is made in ftq_ifu, which reads
//       the vector; a writeback that fails it never reaches here.
//   W3  fault SETS on a fault naming this index. The writeback
//       carries both, so W2 and W3 can fire together.
//   W4  A redirect rewind clears both for every entry it squashes,
//       in the same cycle it moves the pointer.
//
// THE SQUASH RANGE ARRIVES RESOLVED, from ftq_ptr. ftq_decisions.md
// 7.3 publishes the winning REDIRECT here and leaves the mask to
// this module, which would mean repeating the wrap-generation
// reconstruction ftq_ptr already performs on redir_idx -- two
// copies of one derivation, free to disagree. The range is taken
// from its owner instead. Reported in the BP-107 Results Capture.
//
// GEN IS NOT CLEARED BY W4. It is a toggle, and 4.4 is explicit
// that a TOGGLE is what discriminates a reallocation within one
// wrap. Clearing it on a rewind would put it back to a value a
// stale writeback could match.
//
// READERS, ftq_entry_formats.md 4.3:
//
//   R1  fault holds the next-PC request. The FTQ stops requesting
//       past a faulting block. Published as fault_hold, MASKED TO
//       THE LIVE WINDOW: a committed entry's bit stays set until
//       its index is reallocated, so an unmasked OR would hold the
//       front end forever after the first fault.
//   R2  fault does NOT hold commit. No output for it; the absence
//       is the behaviour.
//   R3  wb_rcvd qualifies the predecode redirect. An entry derives
//       at most one, and only from its own writeback. Published
//       per-index to ftq_ifu.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_status (
  input  logic                     clk,
  input  logic                     rstn,

  // ---- pointers, for the live-window mask of R1 --------------------
  input  logic [FTQ_PTR_BITS-1:0]  commit_ptr,
  input  logic [FTQ_PTR_BITS-1:0]  alloc_ptr,

  // ---- W1, allocation ----------------------------------------------
  input  logic                     alloc_val,
  input  logic [FTQ_IDX_BITS-1:0]  alloc_idx,

  // ---- W2 and W3, the accepted writeback ---------------------------
  // Already gen-checked by ftq_ifu. Both may assert together.
  input  logic                     wb_set_val,
  input  logic [FTQ_IDX_BITS-1:0]  wb_set_idx,
  input  logic                     fault_set_val,
  input  logic [FTQ_IDX_BITS-1:0]  fault_set_idx,

  // ---- W4, the squash range from ftq_ptr ---------------------------
  // Half open: [squash_start, squash_end). Both FTQ_PTR_BITS, so the
  // mask is taken on an age and needs no generation reconstruction.
  input  logic                     squash_val,
  input  logic [FTQ_PTR_BITS-1:0]  squash_start,
  input  logic [FTQ_PTR_BITS-1:0]  squash_end,

  // ---- reads --------------------------------------------------------
  // gen_rd_val is the tag that leaves with the fetch request;
  // gen_chk_val is the tag the writeback is tested against. Two
  // ports because the two indices differ: the request is at
  // fetch_ptr and the writeback names whatever entry it belongs to.
  input  logic [FTQ_IDX_BITS-1:0]  gen_rd_idx,
  output logic                     gen_rd_val,
  input  logic [FTQ_IDX_BITS-1:0]  gen_chk_idx,
  output logic                     gen_chk_val,

  input  logic [FTQ_IDX_BITS-1:0]  wb_rd_idx,
  output logic                     wb_rd_val,

  // ---- R1, the fault hold -------------------------------------------
  output logic                     fault_hold,

  // ---- observation, for the bound properties ------------------------
  output logic [FTQ_DEPTH-1:0]     wb_rcvd,
  output logic [FTQ_DEPTH-1:0]     fault,
  output logic [FTQ_DEPTH-1:0]     gen
);

  // The masks. w_squash_msk is W4; w_live_msk is the live window
  // R1 is taken over.
  logic [FTQ_DEPTH-1:0]    w_squash_msk;
  logic [FTQ_DEPTH-1:0]    w_live_msk;
  logic [FTQ_PTR_BITS-1:0] w_squash_len;
  logic [FTQ_PTR_BITS-1:0] w_live_len;

  // -----------------------------------------------------------------
  // Range masks.
  // -----------------------------------------------------------------
  // A range is a START pointer and a LENGTH, and membership is an
  // AGE taken against the start: entry i is in the range when
  // (i - start) modulo FTQ_DEPTH is below the length. That is the
  // wrap-aware test, and it is the same one ftq_ptr and ftq_commit
  // make on pointers. Comparing raw indices would report the wrong
  // set on every range that crosses the array boundary.
  //
  // The length is taken on FTQ_PTR_BITS so a full-window range
  // (FTQ_DEPTH entries, which RC_UNSPEC produces at full occupancy)
  // is length 64 and not length 0.
  // The reads sit in the same block, after the masks they depend on.
  // One always_comb in textual order rather than two blocks and a
  // dependency between them: CLAUDE.md requires that form for a
  // dependency chain, and it puts a flop output -- fault -- inside
  // the block that computes the mask, which keeps Verilator from
  // classifying the mask logic as input-only stl_sequent.
  always_comb begin : masks_and_reads
    w_squash_len = squash_end - squash_start;
    w_live_len   = alloc_ptr  - commit_ptr;

    for (int e = 0; e < FTQ_DEPTH; e++) begin
      w_squash_msk[e] =
        squash_val &&
        ({1'b0, FTQ_IDX_BITS'(e) - squash_start[FTQ_IDX_BITS-1:0]}
           < w_squash_len);
      w_live_msk[e] =
        ({1'b0, FTQ_IDX_BITS'(e) - commit_ptr[FTQ_IDX_BITS-1:0]}
           < w_live_len);
    end

    gen_rd_val  = gen[gen_rd_idx];
    gen_chk_val = gen[gen_chk_idx];
    wb_rd_val   = wb_rcvd[wb_rd_idx];

    // R1. Masked to the live window; see the header.
    fault_hold  = |(fault & w_live_msk);
  end

  // -----------------------------------------------------------------
  // State.
  // -----------------------------------------------------------------
  // Statement order is W4 then W1 then W2/W3, which is the order the
  // events supersede one another for one index in one cycle:
  //
  //   W4 before W1  a rewind and an allocation can name the same
  //                 index -- the redirect frees it and the FTQ
  //                 reallocates it at once. The allocation is the
  //                 later fact and its clear and toggle must stand.
  //   W1 before W2  an allocation clears the entry a writeback in
  //                 the same cycle would set. The writeback belongs
  //                 to the OLD use of the index; the gen test in
  //                 ftq_ifu reads the PRE-toggle value, so a
  //                 writeback that passes it is for the old use and
  //                 must not survive the reallocation.
  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      wb_rcvd <= '0;
      fault   <= '0;
      gen     <= '0;
    end else begin
      // W4. A masked range clear, one cycle, any range.
      wb_rcvd <= wb_rcvd & ~w_squash_msk;
      fault   <= fault   & ~w_squash_msk;

      // W1.
      if (alloc_val) begin
        wb_rcvd[alloc_idx] <= 1'b0;
        fault[alloc_idx]   <= 1'b0;
        gen[alloc_idx]     <= ~gen[alloc_idx];
      end

      // W2, W3. Both may fire in one cycle and they may name
      // different indices, so they are separate ports rather than
      // one index with two enables.
      if (wb_set_val && !(alloc_val && (alloc_idx == wb_set_idx))) begin
        wb_rcvd[wb_set_idx] <= 1'b1;
      end
      if (fault_set_val &&
          !(alloc_val && (alloc_idx == fault_set_idx))) begin
        fault[fault_set_idx] <= 1'b1;
      end
    end
  end

endmodule : ftq_status
