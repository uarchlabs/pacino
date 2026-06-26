<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# bp_history Interface Specification
```
 FILE:    bp_history_interfaces.md
 SOURCE:  various
 STATUS:  DRAFT, target state (session-054)
 UPDATED: 2026-06-25
 CONTACT: Jeff Nye
```

---

## Overview

bp_history owns all branch history state for the BP cluster:
the GHR (Global History Register), the PHR (Path History
Register), the GHR/PHR pointers, the per-slot checkpoint array,
and all folded histories consumed by TAGE, ITTAGE, and SC. It is
owned by BPC (branch predictor cluster), not by rename or
dispatch. It contains no SRAM -- purely registered state.

All types defined in bp_pkg.sv. This document describes port
semantics, timing contracts, and consumer/producer obligations.

This is the TARGET-STATE interface. The G20/G21/G22 resolutions
and the module-owned pointer decision (bp_history_decisions.md)
are reflected here. The as-built RTL (bp_history.sv, 2026-05-21)
is caller-owned-pointer and single-rollback-pointer; it changes
to match this document. Where this doc and current RTL differ,
this doc is the target the implementation task closes to.

---

## Module Parameters

None. All widths and depths are localparams from bp_pkg.sv.

  GHR_WIDTH      = 256   -- circular buffer depth in bits
  PHR_WIDTH      = 32    -- circular buffer depth in bits
  GHIST_PTR_BITS = 8     -- pointer into GHR buffer
  PHIST_PTR_BITS = 5     -- pointer into PHR buffer
  FTQ_DEPTH      = 64    -- number of checkpoint slots
  FTQ_IDX_BITS   = 6     -- index into checkpoint array
  NUM_PRED_SLOTS = 2     -- branches updated per cycle (0,1,2)

---

## Port List

  clk          : input  logic                       -- rising edge
  rstn         : input  logic                       -- active low

  -- Prediction update (dual slot, one bundle per cycle)
  num_branches : input  logic [1:0]                 -- 0, 1, or 2
  pred_taken   : input  logic [1:0]                 -- bit s = slot s
  pred_pc      : input  logic [VA_WIDTH-1:0] [2]    -- per-slot PC

  -- Checkpoint write
  ckpt_wr_en   : input  logic                       -- write enable
  ckpt_wr_idx  : input  logic [FTQ_IDX_BITS-1:0]    -- FTQ slot index

  -- Rollback (redirect recovery, by checkpoint index)
  rollback_valid    : input  logic                  -- restore enable
  rollback_ckpt_idx : input  logic [FTQ_IDX_BITS-1:0]

  -- Current pointer outputs (module-owned, for FTQ construction)
  ghist_ptr    : output logic [GHIST_PTR_BITS-1:0]
  phist_ptr    : output logic [PHIST_PTR_BITS-1:0]

  -- Checkpoint snapshot outputs (value written this cycle)
  ckpt_ghist_ptr : output logic [GHIST_PTR_BITS-1:0]
  ckpt_phist_ptr : output logic [PHIST_PTR_BITS-1:0]

  -- Raw buffer outputs
  ghr_buf      : output logic [GHR_WIDTH-1:0]
  phr_buf      : output logic [PHR_WIDTH-1:0]

  -- Folded history output (consumed by TAGE, ITTAGE, SC)
  folded       : output bp_folded_hist_t

Note: ghist_ptr / phist_ptr are OUTPUTS. The pointer is owned and
advanced inside bp_history (module-owned pointer,
bp_history_decisions.md section 2). No pointer value is driven
into the module; rollback supplies an INDEX, not a pointer.

---

## Pointer Ownership

bp_history owns the live GHR and PHR pointers as internal
registers and advances them itself. The pointer advances by
num_branches each cycle (0, 1, or 2), modulo buffer width. The
advance is sequential only: reset and checkpoint-restore are the
only events that load a non-incremented value. There is no
external pointer-load path.

The current pointer is exposed as a registered output
(ghist_ptr / phist_ptr) for FTQ entry construction. The cluster
reads it; it does not drive it.

See bp_history_decisions.md section 2 for rationale (sequential-
only advance, rollback by index, FTQ visibility vs ownership).

---

## Prediction Update Interface

### Producer: BP cluster (one bundle per cycle, up to two slots)
### Consumer: bp_history (GHR/PHR advance, folds update)

### Timing

  num_branches, pred_taken, pred_pc are sampled on rising clk.
  GHR, PHR, the pointer, and the folds advance synchronously.
  Updated folds are available at the start of the next cycle.

### Semantics

  num_branches = 0  -- no branch this cycle. GHR, PHR, pointer,
                       and folds HOLD. No write, no advance.
  num_branches = 1  -- slot 0 only. One bit into GHR at the
                       pointer, one path bit into PHR, one
                       incremental fold step per table. Pointer
                       advances by 1.
  num_branches = 2  -- slot 0 then slot 1. Slot 0 writes at the
                       pointer, slot 1 writes at pointer+1 (modulo
                       width). Each fold takes two incremental
                       steps, slot 0 first. Pointer advances by 2.

  num_branches = 3 is undefined (valid range 0-2).

  GHR write (per active slot s):
    ghr_mem[ptr_s] <= pred_taken[s]
    where ptr_s is the GHR pointer for slot 0, pointer+1 for
    slot 1.

  PHR write (per active slot s):
    phr_mem[pptr_s] <= pred_pc[s][2] ^ pred_pc[s][3]

  Fold update (incremental, slot 0 then slot 1, per tagged table):
    each active slot applies one fold step in slot order. The
    two-step result for num_branches=2 must equal the full
    recompute over the same two new bits walked linearly from the
    bundle-start pointer. Slot-0-first is that order. This
    equivalence is the dual-slot correctness property (proven by
    the dual-slot directed test, TD #74).

### Producer obligations

  - Drive num_branches to the count of branches in the bundle
    (0, 1, or 2). Do not drive 3.
  - pred_taken[s] / pred_pc[s] valid for each slot s < num_branches.
  - pred_pc is the fetch block PC, not the branch PC.
  - Do not drive a pointer; the module owns it.

---

## Checkpoint Interface

### Producer: BP cluster (writes on each accepted bundle)
### Consumer: bp_history (stores pointer snapshot per FTQ slot)

### Timing

  ckpt_wr_en and ckpt_wr_idx are sampled on rising clk.
  The checkpoint captures the post-advance pointer values for the
  bundle (the pointer after this cycle's prediction advance).

### Semantics

  ckpt_wr_en = 0  -- no checkpoint write this cycle.
  ckpt_wr_en = 1  -- write the current ghist_ptr and phist_ptr
                     into checkpoint slot ckpt_wr_idx, and expose
                     them on ckpt_ghist_ptr / ckpt_phist_ptr.

  Checkpoint stores: GHR pointer (8b) + PHR pointer (5b) only.
  Folded histories are NOT stored per checkpoint slot. On
  rollback, folds are recomputed from buffer contents at the
  restored pointer (G15).

  Granularity is the bundle: one checkpoint per accepted
  prediction bundle, not per branch. There is no checkpoint
  position between slot 0 and slot 1 of one bundle.

### Producer obligations

  - ckpt_wr_idx must be a valid FTQ slot index (0 to FTQ_DEPTH-1).
  - ckpt_wr_en should be asserted in the same cycle as the bundle
    prediction update (num_branches > 0) it checkpoints.
  - Producer must not write the same ckpt_wr_idx twice without an
    intervening rollback or FTQ slot reclaim.

---

## Rollback Interface

### Producer: BP cluster redirect logic (branch mispredict)
### Consumer: bp_history (restore pointer by index, recompute folds)

### Timing

  rollback_valid and rollback_ckpt_idx are sampled on rising clk.
  Pointer restore and fold recompute are synchronous.
  Restored folds are available at the start of the next cycle.

### Semantics

  rollback_valid = 0  -- no rollback this cycle.
  rollback_valid = 1  -- read the checkpoint at rollback_ckpt_idx,
                        load the live pointer from it (ckpt_gptr /
                        ckpt_pptr), and recompute all folds from
                        ghr_mem and phr_mem at the restored
                        pointer positions.

  Rollback supplies an INDEX, not a pointer. The module restores
  the pointer from its own checkpoint array.

  Scope: rollback (checkpoint-restore) applies only to branch-
  mispredict redirects. A mispredict target is the mispredicted
  branch's bundle, which always carries a checkpoint, so the index
  always resolves. Exceptions and interrupts do NOT use this path;
  they reinitialize history on a new context and do not read a
  checkpoint. See bp_history_decisions.md section 3.4.

  ghr_mem and phr_mem are NOT cleared on rollback. Entries written
  after the checkpoint remain in the buffer but are unreachable via
  the restored pointer. This is the accepted contamination model
  (BP-002 TC8).

  Priority: if rollback_valid and num_branches > 0 are asserted in
  the same cycle, ROLLBACK WINS. The prediction update (both slots
  and the checkpoint write) is dropped for that cycle. The two are
  mutually exclusive in the update logic; no merge occurs. (This
  relaxes the BP-002 obligation "producer must not assert both" --
  the module now defines the outcome.)

### Producer obligations

  - rollback_ckpt_idx must be a previously written checkpoint slot.
  - Use this path for branch-mispredict redirects only. Route
    exception/interrupt redirects through the history reinit path,
    not rollback_valid.

---

## Folded History Output Interface

### Producer: bp_history
### Consumer: TAGE (T1-T4 index and tag folds),
###           ITTAGE (IT1-IT4 index and tag folds),
###           SC (ST1-ST3 index folds)

### Timing

  folded is a registered output.
  Valid one cycle after the prediction update that caused the
  advance (same timing as ghist_ptr output).
  On rollback: folded reflects the recomputed state one cycle
  after rollback_valid is asserted. During the rollback cycle the
  fold outputs hold their prior (pre-rollback) values -- see
  staleness note below.

### Semantics

  folded is a bp_folded_hist_t packed struct. All fields are
  GHR-derived. PHR does not contribute to any fold in the current
  implementation (deferred -- see Known Gaps).

  TAGE folds (one set of three per tagged table T1-T4):
    tage_t<N>_idx_fh  -- index fold for T<N>
    tage_t<N>_tag_fh1 -- tag fold 1 for T<N>
    tage_t<N>_tag_fh2 -- tag fold 2 for T<N>

  ITTAGE folds (one set of three per table IT1-IT4):
    it_t<N>_idx_fh    -- index fold for IT<N>
    it_t<N>_tag_fh1   -- tag fold 1 for IT<N>
    it_t<N>_tag_fh2   -- tag fold 2 for IT<N>
    IT5 has no folds (BrIMLI table).

  SC folds (one index fold per table with history, ST1-ST3):
    sc_t1_idx_fh  -- width = SC_T1_HIST = 4b
    sc_t2_idx_fh  -- width = SC_T2_HIST = 10b
    sc_t3_idx_fh  -- width = SC_T3_HIST = 16b
    ST0 (hist=0) and ST4 (IMLI) have no folds.

### Staleness on rollback (stale, not invalid)

  The fold registers are NOT cleared or driven X on rollback. They
  hold their current (pre-rollback, wrong-path) values during the
  rollback cycle and present the recomputed values from the next
  cycle. The value visible in the rollback cycle is stale, not
  undefined.

  Predictions are NOT blocked during the one-cycle recompute. The
  cluster may issue a prediction that cycle; it reads the stale
  folds and produces a lower-quality prediction for that one fetch.
  This is an accepted performance cost, taken to avoid the control
  complexity of a stall or handshake. It never corrupts
  architectural state: a stale fold yields a weak/wrong prediction
  a later redirect corrects, and because rollback and update are
  mutually exclusive, the stale value is never fed back into an
  incremental fold step.

  Cost to be quantified at detailed performance analysis (G15).

### Consumer obligations

  - Consumers must not cache or register folded outputs
    independently. Read folded directly each cycle.
  - No must-not-fire obligation in the rollback cycle. Stale folds
    are a permitted, lossy input, not an error condition. (This
    withdraws the BP-002 "must treat folded as invalid / must not
    fire" obligation.)

---

## Pointer Output Interface

### Producer: bp_history
### Consumer: BP cluster (FTQ entry construction)

  ghist_ptr : current GHR pointer (module-owned, registered
              output). Post-advance value: reflects the advance
              from the most recent num_branches > 0.
  phist_ptr : current PHR pointer. Same timing as ghist_ptr.

  ckpt_ghist_ptr / ckpt_phist_ptr : the pointer pair written into
              the checkpoint array on the most recent ckpt_wr_en.

  The cluster reads these to build the FTQ entry. It does not drive
  any pointer into bp_history.

---

## Known Gaps and Deferred Items

| ID  | Item                                      | Status           |
|-----|-------------------------------------------|------------------|
| HI1 | Dual-slot prediction update               | RESOLVED         |
|     | (NUM_PRED_SLOTS=2). Combined slot-0-      | session-054.     |
|     | then-slot-1, bundle-granularity           | bp_history_      |
|     | checkpoint. = G20.                        | decisions.md s3. |
| HI2 | PHR contribution to fold index and tag    | Deferred to TAGE |
|     | hashing. Currently all folds are GHR-     | and ITTAGE impl  |
|     | derived only. PHR mixing TBD.             | sessions.        |
| HI3 | rollback_valid + prediction same-cycle    | RESOLVED         |
|     | priority. Rollback wins; mutually         | session-054.     |
|     | exclusive with update. = G21.             | decisions.md s4. |
| HI4 | Folded output stale (not invalid) in the  | RESOLVED         |
|     | rollback cycle. Predictions permitted on  | session-054.     |
|     | stale folds; cost deferred to perf        | decisions.md s5. |
|     | analysis (G15). = G22.                    |                  |
| HI5 | Checkpoint slot reclaim protocol.         | TBD at FTQ impl. |
|     | When is a checkpoint slot safe to reuse?  |                  |

See bp_history_decisions.md for the full resolution of HI1/HI3/HI4
and the module-owned pointer decision.

