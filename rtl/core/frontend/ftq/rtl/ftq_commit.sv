// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FTQ tail pointer and the commit walk (BP-106).
//
// Owns commit_ptr of ftq_decisions.md 5.1 and the walk of 5.4.
// alloc_ptr arrives as an INPUT and is never written here.
//
// COMMIT AND FREE ARE ONE POINTER, not two (5.4). The commit payload
// reads bp_ras_snapshot_t out of the entry, so an entry cannot be
// freed before its RAS commit has been issued. There is no separate
// deallocation pointer. ftq_backend_interfaces.md 6 asks for a
// commit-walk pointer distinct from the deallocation pointer; 5.4
// governs and that fourth pointer is not built.
//
// THE INPUT IS A WATERMARK, NOT A PULSE (backend_interfaces 6).
// It is FTQ_PTR_BITS wide and carries the wrap generation.
// bkend_commit_idx names the NEWEST entry all of whose instructions
// have architecturally retired. Every entry from commit_ptr through
// that index inclusive is to be freed, so the watermark may jump
// several entries at once. It is idempotent: repeating it is
// harmless and a cycle in which it does not advance costs nothing.
//
// ONE ENTRY PER CYCLE. The limit is the RAS, not the FTQ. The
// ras_commit_* group on bp_cluster is SCALAR -- no slot dimension --
// so one commit operation per cycle is the port's capacity. FE-11
// guarantees at most one RAS operation per entry, so one entry per
// cycle is exactly one RAS commit per cycle and the walk never falls
// behind what the port can carry.
//
// THE TARGET IS LATCHED, not recomputed from a live input. A
// watermark states a fact about architectural retirement; that fact
// does not become untrue when bkend_commit_val deasserts. So the
// walk end is registered when it is accepted and the walk runs to it
// whether or not the input is still asserted. This is what makes a
// jump of several entries, a stalled watermark and a watermark that
// deasserts mid-walk all one behaviour rather than three.
//
// COMMIT_PTR NEVER REWINDS (5.5 R2). Committed is architectural. The
// walk end only ever moves forward: a watermark naming an entry
// behind the current end -- including one behind commit_ptr itself,
// which is malformed -- is ignored, not applied. A redirect can only
// name an index at or after commit_ptr and this module does not
// arbitrate that; it simply has no path that moves commit_ptr back.
//
// SUPPRESSION (5.4, ras_decisions.md 4.5). BOS priority is
// restore > commit > hold, so in a cycle where a redirect restore
// fires the FTQ suppresses the RAS commit it would have issued and
// the walk does not advance. RC_UNSPEC performs NO restore
// (backend_interfaces 5.1 U5), so it does not suppress; it abandons
// the walk instead, because U3 squashes every entry the walk was
// still to reach.
//
// WRAP-AWARE ORDER IS DONE BY AGE, as in ftq_ptr.sv: subtracting
// commit_ptr maps the live window onto 0..FTQ_DEPTH where plain
// unsigned compare is the wrap-aware compare.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_commit (
  input  logic                     clk,
  input  logic                     rstn,

  // ---- alloc_ptr, from ftq_ptr.sv ---------------------------------
  // Read only, and only to keep FQ-1 an invariant of the RTL rather
  // than a contract obligation on the backend. See the header of the
  // walk-end block.
  input  logic [FTQ_PTR_BITS-1:0]  alloc_ptr,

  // ---- commit watermark, from the backend -------------------------
  // FTQ_PTR_BITS WIDE. It carries the wrap generation
  // (ftq_backend_interfaces.md 6), so nothing is reconstructed for
  // it here. BP-106 built against an FTQ_IDX_BITS port and had to
  // rebuild the generation against commit_ptr; that reconstruction
  // is DELETED, and with it the FTQ_DEPTH-1 allocation limit in
  // ftq_ptr.sv that existed only to make it unambiguous.
  input  logic                     bkend_commit_val,
  input  logic [FTQ_PTR_BITS-1:0]  bkend_commit_idx,

  // ---- redirect, from ftq_npc.sv ----------------------------------
  // Needed for two distinct things: suppression of the RAS commit on
  // a restoring cause, and abandonment of the walk on RC_UNSPEC.
  input  logic                     redir_val,
  input  ftq_redir_cause_e         redir_cause,

  // ---- pointer out -------------------------------------------------
  output logic [FTQ_PTR_BITS-1:0]  commit_ptr,

  // ---- the entry freed this cycle ----------------------------------
  // commit_step_val is the RAS commit request of 5.4 and the free of
  // 5.3 -- one event, one pointer. commit_step_idx addresses the
  // entry whose bp_ras_snapshot_t forms the payload.
  //
  // FE-11 says at most one RAS operation per entry; it does not say
  // every entry has one. The has-a-RAS-operation qualification is
  // applied where the payload is formed, in ftq_entry, because that
  // is where the fact lives. This module issues the step; it does
  // not carry a copy of the entry to qualify it with.
  output logic                     commit_step_val,
  output logic [FTQ_IDX_BITS-1:0]  commit_step_idx,

  // ---- status ------------------------------------------------------
  output logic                     walk_active
);

  localparam logic [FTQ_PTR_BITS-1:0] PTR_ONE =
    {{(FTQ_PTR_BITS-1){1'b0}}, 1'b1};

  // -----------------------------------------------------------------
  // The walk end. One past the last entry to free, so the walk runs
  // while commit_ptr != w_end_r.
  // -----------------------------------------------------------------
  logic [FTQ_PTR_BITS-1:0] w_end_r;

  logic                    w_unspec;
  logic                    w_suppress;
  logic                    w_unspec_squash;
  logic                    w_walk_stop;
  logic [FTQ_PTR_BITS-1:0] w_wm_end;
  logic [FTQ_PTR_BITS-1:0] w_end_nxt;
  logic                    w_take_wm;

  logic [FTQ_PTR_BITS-1:0] w_age_end;
  logic [FTQ_PTR_BITS-1:0] w_age_wm;
  logic [FTQ_PTR_BITS-1:0] w_age_alloc;

  // -----------------------------------------------------------------
  // Decode the redirect.
  // -----------------------------------------------------------------
  always_comb begin : redir_decode
    w_unspec = (redir_cause == RC_UNSPEC);

    // A restoring cause. RC_MISPREDICT, RC_TRAP and RC_REPLAY all
    // perform D2, the RAS restore; RC_UNSPEC does not (U5). Only a
    // cycle in which the restore actually fires SUPPRESSES, and
    // suppression is 5.4's rule: restore outranks commit for BOS.
    w_suppress      = redir_val & ~w_unspec;

    // RC_UNSPEC does not suppress -- it ABANDONS. Different reason,
    // same effect on this cycle's step.
    w_unspec_squash = redir_val &  w_unspec;

    // The walk therefore stops on ANY redirect, but for two
    // different reasons, and they are kept apart because they differ
    // in what happens to the walk END: suppression leaves it alone
    // and the walk resumes next cycle, abandonment clears it.
    //
    // Stepping on an RC_UNSPEC cycle would be a pointer overrun, not
    // just a wasted commit: the end snaps to the CURRENT commit_ptr
    // while commit_ptr moves to commit_ptr+1, leaving an age of -1
    // and a walk of 2**FTQ_PTR_BITS - 1 entries.
    w_walk_stop     = w_suppress | w_unspec_squash;
  end

  // -----------------------------------------------------------------
  // The watermark, and whether it is accepted.
  // -----------------------------------------------------------------
  // bkend_commit_idx CARRIES ITS OWN GENERATION, so the walk end is
  // simply that entry plus one -- the watermark is inclusive. There
  // is nothing to reconstruct. The FTQ_IDX_BITS reconstruction
  // BP-106 needed here was deleted by BP-107 when the port widened
  // (ftq_backend_interfaces.md 6).
  //
  // The redirect index in ftq_ptr.sv is a DIFFERENT case and its
  // reconstruction stays: bkend_ftq_redir_idx is still
  // FTQ_IDX_BITS, and it has no aliasing problem because 5.5 R2
  // bounds it to at or after commit_ptr -- 64 values, not 65.
  always_comb begin : walk_end
    w_age_end   = w_end_r    - commit_ptr;
    w_age_alloc = alloc_ptr  - commit_ptr;

    w_wm_end = bkend_commit_idx + PTR_ONE;
    w_age_wm = w_wm_end - commit_ptr;

    // Accept only a watermark that moves the end FORWARD. This is
    // R2 made structural: a malformed watermark behind commit_ptr
    // reconstructs to an age near FTQ_DEPTH*2 and is rejected by the
    // alloc_ptr bound below, and one behind the current end is
    // rejected by the first term. There is no path that lowers the
    // end, so there is no path that rewinds commit_ptr.
    //
    // The alloc_ptr bound is the FQ-1 guard. A watermark past
    // alloc_ptr cannot happen against a working backend -- R2 makes
    // it the backend's obligation and 5.5 R2 says the FTQ does not
    // arbitrate it -- but bounding here costs one compare and turns
    // FQ-1 from a contract into an invariant of this RTL.
    //
    // IT IS ALSO WHAT REJECTS A HELD STALE WATERMARK. Section 6
    // promises that repeating a watermark is harmless. Once the walk
    // has consumed one, commit_ptr sits at that entry plus one, so
    // the repeat names commit_ptr-1 -- and because the watermark now
    // carries its own generation, that is an age of 2**FTQ_PTR_BITS
    // minus one, far past w_age_alloc, and is rejected at EVERY
    // occupancy including 64 live entries. Under BP-106's narrow
    // port the same repeat reconstructed to an age of exactly
    // FTQ_DEPTH, which is why allocation had to stop one short to
    // keep it out of range. That constraint is gone.
    //
    // This does NOT reject a watermark that regresses further than
    // one entry. That input is malformed, R2 places it outside the
    // FTQ's obligation, and the guarantee this module does make
    // holds regardless: there is no path that lowers commit_ptr.
    w_take_wm = bkend_commit_val &&
                (w_age_wm > w_age_end) &&
                (w_age_wm <= w_age_alloc);

    // RC_UNSPEC squashes EVERY entry (5.1 U3), including the ones
    // between commit_ptr and the walk end that the walk had not yet
    // reached. There is nothing left to walk to, so the end snaps
    // back to commit_ptr. This is the only path that lowers the end,
    // and it lowers it to commit_ptr, never below.
    if (w_unspec_squash) begin
      w_end_nxt = commit_ptr;
    end else if (w_take_wm) begin
      w_end_nxt = w_wm_end;
    end else begin
      w_end_nxt = w_end_r;
    end
  end

  // -----------------------------------------------------------------
  // The walk. At most one entry per cycle.
  // -----------------------------------------------------------------
  always_comb begin : walk
    walk_active = (w_age_end != '0);

    // Three terms, and each is a separate rule:
    //   walk_active   there is an entry left to free (5.4)
    //   ~w_walk_stop  suppressed by a restore, or abandoned by
    //                 RC_UNSPEC -- see redir_decode
    //   age_alloc     FQ-1: commit_ptr may not pass alloc_ptr
    commit_step_val = walk_active & ~w_walk_stop & (w_age_alloc != '0);

    // The entry being freed is the one AT commit_ptr. The pointer
    // moves past it at the end of this cycle.
    commit_step_idx = commit_ptr[FTQ_IDX_BITS-1:0];
  end

  // -----------------------------------------------------------------
  // State.
  // -----------------------------------------------------------------
  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      commit_ptr <= '0;
      w_end_r    <= '0;
    end else begin
      w_end_r    <= w_end_nxt;
      if (commit_step_val) begin
        commit_ptr <= commit_ptr + PTR_ONE;
      end
    end
  end

endmodule : ftq_commit
