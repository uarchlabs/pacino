<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# bp_history Interface Specification
```
 FILE:    bp_history_interfaces.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-08-09
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

Types are defined in bp_structs_pkg.sv and parameters in
bp_defines_pkg.sv. (bp_pkg.sv was split session-008 and deleted;
earlier revisions of this file named it.) This document describes
port semantics, timing contracts, and consumer/producer
obligations.

The G20/G21/G22 resolutions and the module-owned pointer decision
(bp_history_decisions.md) are reflected here and are IMPLEMENTED
in bp_history.sv. The module-owned pointer landed in BP-069;
earlier revisions of this file described the as-built RTL as
caller-owned-pointer and single-rollback-pointer and named this
document the target the implementation would close to. That gap
is closed. The RTL is now the reference; where this document and
the RTL disagree, this document is corrected.

---

## Module Parameters

None. All widths and depths are localparams from
bp_defines_pkg.sv.

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

  -- Prediction update (one bundle per cycle, indexed by BRANCH
  --                    number, not by slot number)
  num_branches : input  logic [1:0]                 -- 0, 1, or 2
  pred_taken   : input  logic [1:0]                 -- bit n = branch n
  pred_pc      : input  logic [VA_WIDTH-1:0] [2]    -- per-branch PC

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

Note: the three prediction-update ports are indexed by branch
number. The cluster compacts its valid prediction slots down
before presenting them, so a bundle whose only branch is in slot
1 presents that branch at index 0. See "Prediction Update
Interface" below.

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

### Producer: BP cluster (one bundle per cycle, up to two branches)
### Consumer: bp_history (GHR/PHR advance, folds update)

### Timing

  num_branches, pred_taken, pred_pc are sampled on rising clk.
  GHR, PHR, the pointer, and the folds advance synchronously.
  Updated folds are available at the start of the next cycle.

### Semantics

  num_branches = 0  -- no branch this cycle. GHR, PHR, pointer,
                       and folds HOLD. No write, no advance.
  num_branches = 1  -- branch 0 only. One bit into GHR at the
                       pointer, one path bit into PHR, one
                       incremental fold step per table. Pointer
                       advances by 1.
  num_branches = 2  -- branch 0 then branch 1. Branch 0 writes at
                       the pointer, branch 1 at pointer+1 (modulo
                       width). Each fold takes two incremental
                       steps, branch 0 first. Pointer advances
                       by 2.

  num_branches = 3 is undefined (valid range 0-2).

  GHR write (per active branch n):
    ghr_mem[ptr_n] <= pred_taken[n]
    where ptr_n is the GHR pointer for branch 0, pointer+1 for
    branch 1.

  PHR write (per active branch n):
    phr_mem[pptr_n] <= pred_pc[n][2] ^ pred_pc[n][3]

  Fold update (incremental, branch 0 then branch 1, per tagged
  table): each active branch applies one fold step in branch
  order. The two-step result for num_branches=2 must equal the
  full recompute over the same two new bits walked linearly from
  the bundle-start pointer. Branch-0-first is that order. This
  equivalence is the dual-slot correctness property (proven by
  the dual-slot directed test, TD #74).

### Producer obligations

  - Drive num_branches to the count of branches in the bundle
    (0, 1, or 2). Do not drive 3.
  - pred_taken[n] / pred_pc[n] valid for each branch n <
    num_branches. The index is the branch number after
    compaction, not the prediction slot number.
  - pred_pc is the BRANCH PC: the block base plus that branch's
    in-block position, TWO bytes per position. It is not the
    fetch block PC. This read "four bytes per position", which
    BP-099 superseded when POS_OFFSET_BITS went to 1 for the C
    extension; the granularity note below, ftq_bpu_interfaces.md
    7.4 and 9 and ftq_entry_formats.md 2 all say two.
    Session-070.

    An earlier revision of this file stated the opposite. It was
    wrong, and the fold arithmetic here is why: the PHR write
    above consumes pred_pc bits [3] and [2] only. With the branch
    PC, pred_pc[3:2] is simply bits [3:2] OF THE BRANCH PC and the
    path bit varies as it should. It is NOT a function of the
    in-block position alone: the branch PC is block start + 2*pos
    and the start is unaligned, so no pos-only identity holds. An
    earlier revision said pred_pc[3:2] "carries the low two bits
    of the branch's in-block position". Corrected session-070.

    THE REASON GIVEN FOR IT WAS ALSO WRONG, session-069. It said a
    fetch block PC is FTB_BLOCK_BYTES aligned so bits [4:0] are
    zero by construction. Prediction blocks are NOT aligned: a
    block begins at the lookup PC, which is a taken branch target
    and so any 2-byte address (ftq_decisions.md 4.7,
    ifu_decisions.md IFU-6). The conclusion survives without that
    premise. THE REPLACEMENT PREMISE WAS ALSO WRONG. It read "a
    block start is 2'b00 in bits [3:2] whenever it is a
    fall-through from an aligned predecessor, which is most of
    them", which is the same alignment assumption one step
    removed: blocks are unaligned, so a fall-through inherits its
    predecessor's low bits, and even from an aligned start the
    fall-through is 2'b00 there only when the block length is a
    multiple of 16 bytes. No alignment claim is needed. A block
    start moves only when the block boundary moves, while the
    branch PC moves with every branch's in-block position, so the
    block PC gives a nearly constant path bit and the branch PC
    does not. Corrected session-070.

    bp_cluster derives this value; see bp_cluster.sv
    w_slot_pc_p1 (BP-092a).

    Granularity note: the in-block position field addresses
    two-byte slots (FTB_BR_POS_BITS = 4), so every RVC branch has
    its own position and its own path bit. Until 2026-08-19 the
    field was four-byte granular and two RVC branches in one
    aligned word shared a position; that aliasing is gone.

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
  position between branch 0 and branch 1 of one bundle.

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

  Scope: rollback (checkpoint-restore) applies to RC_MISPREDICT,
  RC_TRAP and RC_REPLAY -- every backend redirect cause that names
  an FTQ entry (bp_history_decisions.md 3.4,
  ftq_backend_interfaces.md 5 D1). A mispredict target is the
  mispredicted branch's bundle, which always carries a checkpoint,
  so the index always resolves.

  THIS READ "applies only to branch-mispredict redirects" with
  exceptions and interrupts reinitializing history instead.
  Corrected session-070; 3.4 is the owner and covers all three
  causes.

  ghr_mem and phr_mem are NOT cleared on rollback. Entries written
  after the checkpoint remain in the buffer but are unreachable via
  the restored pointer. This is the accepted contamination model
  (BP-002 TC8).

  Priority: if rollback_valid and num_branches > 0 are asserted in
  the same cycle, ROLLBACK WINS. The prediction update (both
  branches and the checkpoint write) is dropped for that cycle.
  The two are mutually exclusive in the update logic; no merge
  occurs. (This relaxes the BP-002 obligation "producer must not
  assert both" -- the module now defines the outcome.)

### Producer obligations

  - rollback_ckpt_idx must be a previously written checkpoint slot.
  - Use this path for every backend redirect that names an FTQ
    entry: RC_MISPREDICT, RC_TRAP and RC_REPLAY. This read
    "branch-mispredict redirects only ... route exception/interrupt
    redirects through the history reinit path". Session-070.
  - bp_cluster drives rollback from the derived redirect. When
    both stages redirect in the same cycle the p3 index wins,
    matching the supersession rule.

---

## Folded History Output Interface

### Producer: bp_history
### Consumer: TAGE (T1-T4 index and tag folds),
###           ITTAGE (IT1-IT5 index and tag folds),
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

  ITTAGE folds (one set of three per table IT1-IT5):
    it_t<N>_idx_fh    -- index fold for IT<N>
    it_t<N>_tag_fh1   -- tag fold 1 for IT<N>
    it_t<N>_tag_fh2   -- tag fold 2 for IT<N>

    IT5 HAS REAL FOLDED HISTORY: IT_TBL_HIST[5]=32, FH=9, FH1=9,
    FH2=8, per bp_defines_pkg.sv. An earlier revision of this file
    stated "IT5 has no folds (BrIMLI table)"; that was a
    copy-paste artifact from SC's real BrIMLI table (ST4) and was
    removed session-061.

    bp_history.sv DOES NOT CURRENTLY GENERATE the IT5 folds.
    ittage.sv wires it_t5_idx_fh / tag_fh1 / tag_fh2 to outputs
    that are never driven, so they read permanently zero and IT5
    indexes on PC alone. TD#102 tracks the RTL gap. This is a
    prediction-accuracy loss, not a correctness break.

  SC folds (one index fold per table with history, ST1-ST3):
    sc_t1_idx_fh  -- width = SC_T1_HIST = 4b
    sc_t2_idx_fh  -- width = SC_TBL_FH[2] = 16b
    sc_t3_idx_fh  -- width = SC_TBL_FH[3] = 64b

    These read SC_T2_HIST = 10b and SC_T3_HIST = 16b. Neither
    parameter exists; bp_defines_pkg.sv has
    SC_TBL_FH[0:4] = '{0, 4, 16, 64, 0}, which bp_cluster.md
    Folded Histories and bp_history_decisions.md 6.4/6.5 both
    match. Corrected session-070.
    ST0 (hist=0) and ST4 (BrIMLI) have no folds.

    bp_cluster stages the three SC index folds from p0 to p2
    before presenting them to sc, alongside the SC prediction PC
    and phr (BP-090). This module presents them live; the staging
    is the consumer's.

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
|     | (NUM_PRED_SLOTS=2). Combined branch-0-    | session-054.     |
|     | then-branch-1, bundle-granularity         | bp_history_      |
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
| HI5 | Checkpoint slot reclaim. When is a        | CLOSED           |
|     | checkpoint slot safe to reuse? At entry   | session-070 by   |
|     | commit: the checkpoint is a FIELD of the  | G23.             |
|     | FTQ entry, reclaimed with it. No separate | ftq_decisions.md |
|     | protocol.                                 | 5.8, 5.3.        |
| HI6 | IT5 fold generation missing in            | TD#102 open.     |
|     | bp_history.sv. IT5 has real history but   |                  |
|     | its three fold outputs are never driven.  |                  |
| HI7 | Ports use literal [1:0] and [2] where     | Deferred.        |
|     | other modules use NUM_PRED_SLOTS.         | INFRA-011.       |

See bp_history_decisions.md for the full resolution of HI1/HI3/HI4
and the module-owned pointer decision.

---

## Document history

```
  2026-08-09  INFRA-012 / session-064. Producer obligation
              corrected: pred_pc is the BRANCH PC, not the fetch
              block PC, with the PHR fold arithmetic recorded as
              the reason (BP-092a binding decision 1). Port list
              and prediction-update semantics restated in terms of
              branch number rather than slot number, matching the
              cluster's compaction. bp_pkg.sv references corrected
              to bp_defines_pkg.sv / bp_structs_pkg.sv. The
              caller-owned-pointer target-state note retired: the
              module-owned pointer is implemented (BP-069). The
              "IT5 has no folds (BrIMLI table)" claim removed and
              replaced with the real IT5 geometry plus the TD#102
              generation gap. SC fold staging note added (BP-090).
              HI6 and HI7 opened.
```

