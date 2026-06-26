<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 055
Written by Claude.ai at end of session-054.
Date: 2026-06-25

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

Session-054 resolved the bp_history G-series TBDs (G20/G21/G22),
reworked bp_history.sv to a module-owned pointer, and found and
fixed a folded-history geometry bug. The bp_history testbench is
NOT yet re-greened; BP-072 (written, not run) does that.

The two bp_history planning docs are the authority:
  planning/arch/bp_history_decisions.md        (new this session)
  planning/interfaces/bp_history_interfaces.md (rewritten to target)

---

## Read This First

The natural next unit was bp_cluster, which needs G20/G21/G22 first.
This session resolved those three, and in doing so reopened
bp_history.sv (which was marked Complete but was single-slot and
rollback-light). The rework surfaced a real RTL bug in the folded-
history math. State at session end:

  - bp_history_decisions.md: created. Resolves G20/G21/G22; rules
    the GHR/PHR pointer module-owned (internal, sequential-advance,
    rollback by checkpoint index). COMPLETE for these items.
  - bp_history_interfaces.md: rewritten from the stale BP-002 draft
    to the target interface (module-owned pointer, dual-slot,
    rollback by index, stale-fold-allowed).
  - bp_history.sv: reworked (BP-069 pointer model) and fixed
    (BP-071 fold geometry). Lint-clean, all non-history bpu targets
    green.
  - tb_bp_history.sv: NOT updated. Still on the old ports and the
    old fold geometry. sim_history / cov_history WAIVED through
    BP-069 and BP-071. BP-072 (written, queued) re-greens them.

Task files written this session: BP-069 (done), BP-070 (ABANDONED),
BP-071 (done), BP-072 (written, NOT run). Run BP-072 first in 055.

---

## Session Summary

1. Resolved G20/G21/G22 (= bp_history HI1/HI3/HI4):
   - G20 dual-slot update: combined slot-0-then-slot-1 in one
     cycle, bundle-granularity checkpoint.
   - G21 rollback_valid + prediction same cycle: rollback wins,
     mutually exclusive with update.
   - G22 one-cycle fold window after rollback: folds are STALE, not
     invalid; predictions allowed on stale folds (accepted perf
     cost, no stall/handshake). Decoupled G22 from G15 -- G15 is now
     a perf measurement, not a correctness gate.
   Created bp_history_decisions.md to record these.

2. Pointer ownership (the larger decision). The BP-002 draft and the
   as-built RTL disagreed; the RTL took the pointer as an input
   (caller-owned). Ruled MODULE-OWNED: bp_history holds the live
   GHR/PHR pointer, advances it by num_branches, exposes it as a
   registered output, and rolls back by checkpoint INDEX (not an
   external pointer value). Sequential-only advance; reset and
   checkpoint-restore are the only non-incremental loads. Confirmed
   against Alpha 21264 and IBM GHV recovery practice -- no surveyed
   design needs a non-sequential pointer. Checkpoint-restore applies
   only to branch-mispredict redirects (which always hit a
   checkpointed bundle); exceptions/interrupts reinitialize history
   and do not use the checkpoint path, so there is no no-branch-
   flush restore case.

3. BP-069 (implementation, done). Reworked bp_history.sv to the
   module-owned pointer: pointer in->out, rollback_*_ptr inputs
   replaced by rollback_ckpt_idx, internal pointer advance. No
   package change. make lint clean; all non-history bpu targets
   green. tb_bp_history waived to BP-070 (later BP-072).

4. BP-070 (testbench, ABANDONED). While planning the dual-slot test,
   the IA reported the DUT's incremental fold and rollback recompute
   use two different conventions. Investigation (against the
   Xiangshan FoldedHistory it mimics) confirmed a real bug, not a
   test nuance. BP-070 was abandoned rather than written to mirror
   the broken paths.

5. Fold bug (the central finding). bp_history.sv diverged from
   Xiangshan FoldedHistory in three ways:
     (1) incremental insert at fold bit 0 instead of the high end;
     (2) wrap-out bit removed at position 0 instead of (H-1) % W;
     (3) rollback recompute (fold_ghr) used a separate, inequivalent
         fold definition (forward walk i->i) vs the incremental
         path.
   The TAGE/ITTAGE table hashes were checked and are CORRECT and
   Xiangshan-faithful; only bp_history produced the wrong fold bit
   order, so only bp_history needed fixing. The old 12-test
   tb_bp_history passed because the fold window never filled past
   TC7 -- the bug lived in the full-window region.

6. BP-071 (debug, done). Rewrote the fold to one Xiangshan-geometry
   definition shared by update and recompute (newest at high end;
   leaving bit at (H-1) % W; recompute posmap(i) = (i+W-1) % W).
   Necessary catch by the IA: widened the fold helpers 32b->64b
   because SC ST3 has H=W=64 and is unrepresentable at 32b (a fourth,
   width defect in the original fold, independent of the three
   geometry ones). No package/struct/param change -- only the in-file
   helper type and casts. Single-slide equivalence proven offline
   across all in-use (H,W). Lint clean; all non-history bpu targets
   green. sim_history now compiles and fails only at TC8 because the
   testbench golden still uses the old geometry -- positive
   confirmation the DUT geometry changed as intended.

7. BP-072 (testbench, WRITTEN, NOT RUN). Rewires tb_bp_history to
   the BP-069 ports, replaces the stale golden with one independent
   reference in BP-071 geometry, and proves DUT-incremental ==
   fold_ref AND DUT-recompute == fold_ref for single-slot, dual-slot
   (TD #74), and SC ST3, plus the num_branches / checkpoint /
   rollback-by-index / rollback-wins / stale-fold directed tests.
   Restores sim_history / cov_history / cov_bpu to green. Run this
   first in 055.

---

## What Was Accomplished

  - bp_history_decisions.md created (G20/G21/G22 + module-owned
    pointer). Authority for the unit's behavior.
  - bp_history_interfaces.md rewritten to the target interface.
  - bp_history.sv: module-owned pointer (BP-069) + corrected
    Xiangshan fold geometry, 64b helpers (BP-071). Lint clean; no
    TAGE/ITTAGE/RAS/FTB regression at any point.
  - Fold bug found and fixed before it reached bp_cluster.
  - Task files: BP-069, BP-071 done; BP-072 written; BP-070
    abandoned.

---

## Open Work

### bp_history -- immediate (run first in 055)

  - BP-072: run it. Re-greens sim_history / cov_history / cov_bpu and
    proves the dual-slot fold equivalence (TD #74) in simulation.
    Until it passes, bp_history.sv's fold is proven only offline
    (BP-071), not in-sim. This is the gate before bp_history is
    Complete again.

### bp_history -- after BP-072

  - PROJECT_STATUS bp_history row: still shows the pre-session state.
    Update to reflect the module-owned pointer, the fold fix, and the
    BP-072 test result once it runs. (Not done this session; no
    target was green to cite a count from.)
  - Decisions doc open items (deferred, not blocking): HI2 (PHR fold
    mixing, -> TAGE/ITTAGE hashing), HI5 (checkpoint slot reclaim,
    -> FTQ). TD #74 closes with BP-072. TD #69/#70 (TAGE/ITTAGE
    rollback recompute) remain deferred to bp_cluster -- they were
    blocked on G20/G21/G22, which are now resolved, but still need
    cluster rollback stimulus.
  - Decisions 3.5 if/else-if cleanup of the slot cases: NOT done
    (BP-071 was scoped to fold arithmetic only). Fold into the next
    bp_history RTL touch or a small cleanup task.

### Standing candidates (Jeff's priority call)

  - bp_cluster integration. G20/G21/G22 are now resolved, which was
    the stated blocker. Owns the deferred FTB items (flush, FTB-2,
    arbitration, FTQ round-trip, fastpath_en source) and TD #69/#70.
  - SC predictor (not started) -- the last unbuilt predictor.
  - Carried infra: #43 ITTAGE CTR 3b->2b, #75 sim_ittage_fast, #77
    path scrub, #67/#68 sram_init non-fast, #38 covergroup re-check.

---

## bp_history State: reworked, fold fixed, NOT yet re-verified

bp_history.sv is at the module-owned pointer interface with the
corrected Xiangshan fold geometry, lint-clean, and causes no
regression in any other bpu unit. It is NOT re-verified: tb_bp_history
is stale and sim_history / cov_history are waived. BP-072 (written,
queued) re-greens them and proves the fold equivalence in simulation.
Do not mark bp_history Complete until BP-072 passes.

---

## Postmortem Record -- PA performance

Tracking the trend from handoff-053/054. This session the PA was
held to the corrected behavior; logged for continuity.

1. No fabricated files or invented process this session. Artifacts
   were produced only on request (the four task files and the two
   bp_history docs, each asked for). No unrequested wrap-up,
   checklist, or rule was manufactured.

2. One early-session error, corrected. The PA misapplied the
   CLAUDE.md "Context Loaded / Deliverables only" rule -- an IA
   runtime constraint -- to its own doc-drafting scope, and briefly
   claimed it could not edit a planning file on that basis. Jeff
   challenged it; the PA acknowledged the rule does not bound PA
   drafting and proceeded. No downstream effect.

3. The PA over-asked. Several times it posed questions Jeff had
   already answered (the stale-fold perf decision; a pre-advance vs
   post-advance checkpoint question) and was told to use the given
   answer. Net supervision cost was still low, but the trend to
   watch is re-asking settled points, not the 052/053 pattern of
   asserting unchecked claims.

4. Verify-before-asserting held this session. The fold bug was
   investigated against the Xiangshan source (fetched, not recalled)
   before the RTL fix was scoped; the IA's findings were checked, not
   taken on faith; the pointer decision was confirmed against named
   prior-art rather than asserted.

Impact. The session reached a correct, verified-by-construction
result (fold fixed, proven offline) with the testbench proof queued.
The methodology risk from prior sessions did not recur in the
file-fabrication / invented-process form; the residual cost this
session was re-asking answered questions. Weigh accordingly.

---

## Next Session (055)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-055.md (this file)
  CLAUDE.md
  bp_history_decisions.md and bp_history_interfaces.md (for BP-072
  or any further bp_history work)
  and, if the next unit is bp_cluster or SC, the relevant planning
  docs.

Run BP-072 first: it re-greens sim_history / cov_history / cov_bpu
and proves the dual-slot fold equivalence (TD #74) in simulation.
bp_history is not Complete until it passes. After that, update the
PROJECT_STATUS bp_history row from the BP-072 run, then bp_cluster or
SC is Jeff's call.

Given the Postmortem Record: 055 should produce only what Jeff
requests, use answers already given rather than re-asking, and verify
before asserting. Confirm the session is wrapping before writing a
handoff.

