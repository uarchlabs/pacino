<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# bp_history Micro-Architectural Decisions
```
 FILE:    bp_history_decisions.md
 SOURCE:  session-054
 STATUS:  DRAFT
 UPDATED: 2026-06-25
 CONTACT: Jeff Nye
```

Decision record for bp_history. Companion to
bp_history_interfaces.md (interface contract). This file records
the resolution of G20/G21/G22 (= HI1/HI3/HI4 in the interface
doc).

The three G-item policy choices (dual-slot update, rollback
priority, stale-fold handling) ratify behavior already in the
as-built RTL (bp_history.sv, dated 2026-05-21). The pointer-
ownership decision (section 2) does NOT: it rules module-owned
where the RTL is caller-owned, and so changes both the RTL and the
interface port list. Section 8 separates the doc-only
reconciliation from the RTL changes.

The interface DRAFT (BP-002, dated 2026-03-28) predates the RTL
and is stale on several ports.

---

## 1. Role and Ownership

bp_history owns all branch history state for the BP cluster: the
GHR (256b), the PHR (32b), and every folded history consumed by
TAGE (T1-T4), ITTAGE (IT1-IT4), and SC (ST1-ST3). It is owned by
the BP cluster, not by rename or dispatch. It contains no SRAM;
all state is registered flops.

GHR and PHR are single registered buffers (ghr_mem, phr_mem), not
shift registers. bp_history also owns the live GHR/PHR pointers and
the checkpoint array, so all history state -- buffers, pointers,
checkpoints, folds -- is internal (section 2). A prediction writes
one bit per slot at the internal pointer; folds advance
incrementally. On rollback the pointer is restored from an internal
checkpoint and the folds are recomputed from buffer contents at the
restored pointer.

---

## 2. Pointer Model: module-owned

bp_history owns all of its pointer state. The live GHR and PHR
pointers are internal registers, advanced inside the module; the
checkpoint array is internal; rollback restores the pointer from a
checkpoint by index. No pointer value is driven into the module.

This diverges from the as-built RTL (bp_history.sv, 2026-05-21),
which takes ghist_ptr/phist_ptr and rollback_ghist_ptr/
rollback_phist_ptr as inputs. The interface DRAFT (BP-002)
specified module-owned and outputs; the RTL flipped to caller-owned
without a recorded rationale. This document rules module-owned as
the decision. The RTL and interface port list change to match
(section 8).

### 2.1  Advance

  The internal pointer advances by num_branches each cycle (0, 1,
  or 2), modulo buffer width. The advance is sequential only:
  reset and checkpoint-restore are the only events that load a
  non-incremented value. There is no external pointer-load path.

  Sequential-only advance with checkpoint-indexed restore matches
  standard speculative-history recovery practice: the Alpha 21264
  saves prior history in an outstanding-branch queue and restores
  on misprediction; IBM's GHV scheme tags each fetch group with a
  shift count and restores by that count. Both index recovery by a
  monotonic per-fetch-group value, neither injects an arbitrary
  pointer. No surveyed design requires a non-sequential pointer.

### 2.2  Rollback by index

  Rollback supplies a checkpoint INDEX, not a pointer value. On
  rollback the module reads ckpt_gptr[idx] / ckpt_pptr[idx],
  loads the live pointer from it, and recomputes the folds from
  ghr_mem/phr_mem at that restored position (section 5).

  BP-072 reconciliation (pointer-walk addressing; geometry UNCHANGED).
  The fold geometry -- position mapping posmap(i) = (i+W-1)%W, newest
  bit inserted at the high end (W-1), leaving bit removed at (H-1)%W --
  is the BP-071 Xiangshan convention and did NOT change. What BP-072
  set is the buffer-walk ADDRESSING that feeds that geometry under the
  module-owned incrementing pointer (section 2.1): the newest bit sits
  just below the live pointer, so the recompute walks the GHR DOWNWARD
  (offset i -> ghr_mem[anchor - i]) and the incremental fold_step
  fetches its leaving bit at write_addr - H. The recompute anchors at
  ckpt - 1 because the checkpoint stores the post-advance pointer
  (section 6) and the newest bit of the bundle is one position behind
  it. fold_step is the exact incremental form of fold_ghr for this
  mapping, so the rollback recompute reproduces the incremental fold;
  TD #74 (tb_bp_history) confirms it in simulation for single-slot,
  dual-slot, GHR-boundary wrap, and SC ST3 (H=W=64). No fold value
  consumed by the TAGE/ITTAGE/SC tables changed -- only the recompute
  walk direction and the checkpoint anchor were fixed to match the
  incrementing pointer.

<!--
  BP-072 resolution (increment-oriented geometry): because the live
  pointer INCREMENTS and the checkpoint stores the POST-advance
  pointer (the next-write address, section 6), the newest history bit
  is one position behind it. The fold recompute therefore anchors at
  ckpt - 1 and walks the GHR DOWNWARD into older bits, and the
  incremental fold_step evicts its leaving bit at write_addr - H.
  This is the only orientation under which the rollback recompute
  reproduces the incremental fold for both single-slot and dual-slot
  bundles (proven in simulation by TD #74, tb_bp_history). The BP-071
  position mapping posmap(i) = (i+W-1)%W and high-end newest insertion
  are retained unchanged.
-->

  Holding both an internal checkpoint array and an external
  rollback pointer input -- as the current RTL does -- is
  redundant. With the checkpoint internal, the index is sufficient.

### 2.3  Outputs for FTQ visibility

  Pointer VISIBILITY outside the module is separate from pointer
  OWNERSHIP and is retained. The current pointer is exposed as a
  registered output for FTQ entry construction (ghist_ptr /
  phist_ptr become outputs; ckpt_ghist_ptr / ckpt_phist_ptr
  continue to expose the snapshot written on a checkpoint). The
  cluster reads these; it does not drive them.

This makes bp_history self-contained on history state. The cluster
drives prediction bits, num_branches, checkpoint writes, and a
rollback index. Nothing pointer-valued enters the module.

---

## 3. Prediction Update: dual-slot (G20 / HI1 RESOLVED)

Decision: two branches update history in ONE cycle, applied as a
combined slot-0-then-slot-1 fold. This is the resolution of HI1
(NUM_PRED_SLOTS=2). The interface DRAFT's single
pred_valid/pred_taken/pred_pc is superseded; the RTL ports are
pred_taken[1:0], pred_pc[2], num_branches[1:0].

### 3.1  num_branches semantics

  num_branches = 0  -- no branch this cycle. GHR, PHR, the pointer,
                       and all folds HOLD. No write, no advance.
  num_branches = 1  -- slot 0 only. One bit into GHR at ghist_ptr,
                       one path bit into PHR at phist_ptr, one
                       incremental fold step per table. Pointer
                       advances by 1.
  num_branches = 2  -- slot 0 then slot 1. Slot 0 writes ghr at
                       ghist_ptr / phr at phist_ptr; slot 1 writes
                       ghr at ghist_ptr+1 / phr at phist_ptr+1
                       (both modulo buffer width). Each fold takes
                       two incremental steps, slot 0 first. Pointer
                       advances by 2.

ghist_ptr / phist_ptr here are the internal pointer registers
(section 2), not inputs. Value 3 is undefined (num_branches valid
range 0-2, per PROJECT_STATUS).

### 3.2  Write content

  GHR bit:  pred_taken[slot].
  PHR bit:  pred_pc[slot][2] ^ pred_pc[slot][3]  (path_bit).
  pred_pc is the fetch-block PC, not the branch PC.

PHR does not currently contribute to any fold; all folds are
GHR-derived (HI2, deferred -- section 8).

### 3.3  Combined fold: ordering is load-bearing

The slot-1 fold step consumes the slot-0 fold result within the
same cycle (nested fold_step in RTL). Folding slot-0-then-slot-1
is not equal to the reverse order. The ordering invariant is:

  The incremental two-step fold (slot 0 at ptr, slot 1 at ptr+1)
  must equal the full recompute over the same two new bits walked
  linearly from ptr (fold_ghr order). The rollback recompute
  walks the buffer linearly from the restored pointer, so the two
  paths agree only if the incremental order matches the linear
  walk. Slot 0 first, slot 1 second is that order.

This equivalence is the core correctness property of the dual-slot
path. It is the obligation TD #74's directed test proves against a
golden linear-fold model (section 8). It is not yet proven.

### 3.4  Checkpoint granularity

The checkpoint captures one pointer pair per FTQ slot, written at
the bundle (one checkpoint per accepted prediction bundle), not
per branch. There is no checkpoint position between slot 0 and
slot 1 of the same bundle. Given the fixed bundle split (G8/G17)
and post-execute update, bundle granularity is the intended
recovery unit. A redirect targets a bundle boundary, not an
intra-bundle slot.

Rollback-by-index (section 2.2) applies only to branch-mispredict
redirects. A mispredict rewinds to the mispredicted branch's
bundle, which by definition contained a branch and therefore has a
checkpoint. The index always resolves.

Exceptions and interrupts do not use this path. They redirect to a
handler on a new architectural context; the speculative history is
discarded and reinitialized, not restored from a checkpoint. There
is no checkpoint lookup and no no-branch-target problem.

This split (mispredict restores, exception/interrupt reinitializes)
is assumed to cover every history-affecting redirect. Confirm at
bp_cluster that no third redirect type needs history restore onto a
no-branch bundle; if the flush taxonomy holds, no restore-then-hold
mechanism is required.

### 3.5  RTL fix: if / else-if for the slot cases

The RTL applies num_branches>=1 and num_branches==2 as two
separate if blocks that both assign the fold registers. On
num_branches==2 the slot-0-only assignment is computed and then
overwritten by the dual assignment, correct only by nonblocking
last-write-wins. Convert to if / else-if (num_branches==2 else
num_branches==1) so each case assigns the registers once. No
behavior change; removes the dead assignment and the coverage
skew. Apply when TD #74 touches the file (section 8).

---

## 4. Rollback Priority (G21 / HI3 RESOLVED)

Decision: rollback wins. When rollback and a prediction update
would land in the same cycle, the history state takes the
rollback and the prediction update is dropped for that cycle.

Rationale: a redirect invalidates any same-cycle speculative
prediction. Letting rollback win keeps the recovery path the
single source of next-cycle history state and removes the need
for a merge between a restore and a forward advance.

RTL: rollback_valid is a distinct branch in the update if/else
ladder (reset / rollback_valid / normal). When rollback_valid is
asserted, the normal-update branch (including both slots and the
checkpoint write) does not execute. The two are mutually
exclusive by construction, so no priority encoder is needed. Under
the module-owned decision (section 2) the rollback branch reads the
internal checkpoint by index and loads the pointer from it; the
current RTL instead consumes an external rollback pointer, which
changes with the port edit (section 8). The priority structure is
unaffected by that change.

This places the complexity in isolation: rollback is its own
state transition, never a blend with prediction update.

Producer obligation: the cluster may assert rollback_valid and
pred/num_branches in the same cycle; if it does, the prediction
is understood to be discarded. The cluster is not required to
suppress the prediction inputs, because the RTL ignores them
under rollback_valid. (The interface DRAFT's stricter "producer
must not assert both" obligation is relaxed to "rollback wins if
both are asserted." See section 8.)

---

## 5. Folded History After Rollback: stale, not invalid
   (G22 / HI4 RESOLVED, and decoupled from G15)

Decision: on the rollback cycle the fold outputs are STALE, not
invalid, and the cluster MAY issue a prediction on stale folds.
The precision cost is accepted and handed to performance analysis.

### 5.1  Stale vs invalid

The fold register (fh_r) is neither cleared nor driven to X on
rollback. It holds its current value during the rollback cycle and
presents the recomputed value from the next cycle onward (folds
are registered, one-cycle recompute latency). The value visible in
the rollback cycle is therefore the wrong-path history that is
about to be replaced -- stale, not undefined.

The interface DRAFT's word "invalid" overstates this and its
"consumer must not fire a prediction in that cycle" obligation is
withdrawn.

### 5.2  Why stale is safe to consume

Folds feed index/tag hashing for advisory predictors. A stale
fold yields a weak or wrong prediction that a later redirect
corrects. It never corrupts architectural state. Because rollback
and normal update are mutually exclusive (section 4), the stale
fold is read by consumers in that cycle but is never fed back into
an incremental fold step -- the next cycle starts from the
recomputed-correct state. The stale value cannot poison the fold
chain.

### 5.3  Decoupling from G15

The DRAFT tied HI4/G22 to G15 because the old "must not fire"
framing required a stall or enforcement mechanism whose timing was
unresolved. Allowing stale-fold predictions removes that
mechanism. With nothing to enforce, G22 is no longer a correctness
gate on bp_cluster integration. G15 reduces to a performance
measurement: the accuracy cost of predicting on a stale fold in
the rollback cycle.

### 5.4  Performance cost (accepted, quantify later)

Decision: predictions are not blocked during the one-cycle
recompute. No handshake, no backpressure, no stall. The predictor
reads the old fold values that cycle and produces a lower-quality
prediction for that one fetch. This is an accepted performance
cost, taken to avoid the control complexity a block would add.

Action item, detailed performance analysis: quantify how often a
prediction lands in the recompute cycle and its accuracy cost.
Revisit only if it is material.

---

## 6. Checkpoint

The checkpoint array (ckpt_gptr / ckpt_pptr, internal) stores the
GHR pointer (8b) + PHR pointer (5b) per FTQ slot. Folds are NOT
stored per slot; they are recomputed on rollback from buffer
contents at the restored pointer (section 5, G15 framing).

Write: ckpt_wr_en writes the POST-advance internal pointer pair (the
next-write address for the cycle after this bundle) into ckpt_wr_idx,
and exposes it on ckpt_ghist_ptr / ckpt_phist_ptr for FTQ entry
construction.

Checkpoint timing is POST-advance (ratified -- see History 2026-06-26).
The checkpoint carries a pointer only, not num_branches. Storing the
post-advance pointer puts the newest history bit of the bundle at
ckpt - 1 whether the bundle held one branch or two, so the rollback
recompute anchors uniformly at ckpt - 1 (section 2.2). A pre-advance
snapshot would require also storing the slot count to locate the
newest bit. This supersedes the earlier pre-advance wording in this
section and matches bp_history_interfaces.md (Checkpoint Timing).

<!--
Write: ckpt_wr_en writes the POST-advance internal pointer pair (the
next-write pointer for the cycle after this bundle) into ckpt_wr_idx,
and exposes it on ckpt_ghist_ptr / ckpt_phist_ptr for FTQ entry
construction. BP-072 changed this from the earlier pre-advance
snapshot to align with bp_history_interfaces.md (Checkpoint Timing)
and to make the dual-slot rollback recompute equal the incremental
fold (section 2.2).
-->

Read (rollback): the rollback index selects ckpt_gptr[idx] /
ckpt_pptr[idx]; the module loads the live pointer from it and
recomputes folds (section 2.2, section 5). No pointer value is
driven in.

Contamination model (unchanged from BP-002 TC8): ghr_mem and
phr_mem are not cleared on rollback. Entries written after the
checkpoint remain in the buffer but are unreachable via the
restored pointer. This is accepted.

Checkpoint slot reclaim (when a slot is safe to reuse) and the
no-branch-flush target case (section 3.4) are FTQ concerns,
deferred (HI5, section 8).

---

## 7. Parameters

Defined in bp_defines_pkg.sv / bp_structs_pkg.sv. Do not use
numeric literals.

  GHR_WIDTH       = 256    GHR buffer depth, bits.
  PHR_WIDTH       = 32     PHR buffer depth, bits.
  GHIST_PTR_BITS  = 8      pointer into GHR buffer.
  PHIST_PTR_BITS  = 5      pointer into PHR buffer.
  FTQ_DEPTH       = 64     checkpoint slots.
  FTQ_IDX_BITS    = 6      checkpoint index.

Fold widths and per-table history lengths (TAGE_TBL_HIST,
TAGE_TBL_FH/FH1/FH2, IT_TBL_HIST, IT_TBL_FH/FH1/FH2, SC_TBL_HIST,
and the *_MAX_FH cast widths) are package localparams consumed by
the fold functions. They are not restated here; bp_history.sv
reads them from the package.

The folded output is bp_folded_hist_t (bp_structs_pkg.sv): one
idx + two tag folds per TAGE T1-T4 and ITTAGE IT1-IT4, one idx
fold per SC ST1-ST3. ST0 (hist=0), ST4 (IMLI), and ITTAGE IT5
(BrIMLI) have no folds.

---

## 8. Open Items

  HI1: RESOLVED (this document, section 3). Dual-slot update is
       combined slot-0-then-slot-1 in one cycle, bundle-
       granularity checkpoint. The interface doc port list must be
       reconciled to pred_taken[1:0] / pred_pc[2] / num_branches.

  HI3: RESOLVED (section 4). Rollback wins; mutually exclusive
       with normal update. Interface doc obligation relaxed from
       "must not assert both" to "rollback wins if both asserted."

  HI4: RESOLVED (section 5). Stale-fold predictions allowed;
       "must not fire" obligation withdrawn; decoupled from G15.

  HI2: DEFERRED (not in this scope). PHR contribution to fold
       index/tag hashing. All folds are GHR-derived today. Resolve
       at TAGE/ITTAGE hashing work.

  HI5: DEFERRED (not in this scope). Checkpoint slot reclaim
       protocol -- when a slot is safe to reuse. Resolve at FTQ
       implementation. (The no-branch-flush concern raised earlier
       is closed in section 3.4: checkpoint-restore is mispredict-
       only and always hits a checkpointed bundle.)

  G15: REFRAMED (section 5.3). No longer a correctness gate; now a
       performance measurement (stale-fold accuracy cost in the
       rollback cycle).

  RTL + interface change (module-owned pointer, section 2). This
  is NOT a doc-only reconciliation -- it changes bp_history.sv and
  the interface port list. The as-built RTL is caller-owned; the
  decision is module-owned. Deltas:
    - Make ghist_ptr / phist_ptr internal registers; advance by
      num_branches each cycle. Remove them as inputs; expose as
      registered outputs (FTQ visibility, 2.3).
    - Remove rollback_ghist_ptr / rollback_phist_ptr inputs. Add
      a rollback index input (rollback_ckpt_idx, FTQ_IDX_BITS).
    - Rollback reads ckpt_gptr[idx] / ckpt_pptr[idx], loads the
      pointer, recomputes folds from the restored position.
    - ckpt_ghist_ptr / ckpt_phist_ptr outputs unchanged.

  Other interface reconciliation (DRAFT is stale vs as-built):
    - rollback_en -> rollback_valid
    - ckpt_idx -> ckpt_wr_idx
    - pred_taken / pred_pc scalar -> [1:0] / [2]
    - add num_branches, ghr_buf, phr_buf
    - DRAFT obligation "must not assert rollback + pred together"
      relaxed to "rollback wins" (section 4)

  RTL fix (section 3.5): convert the slot cases to if / else-if.
  Directed, apply at TD #74. No behavior change.

  Downstream tasks (not doc edits, sequenced after this doc):
    - TD #74: dual-slot directed test. Proves the section 3.3
      incremental-vs-recompute equivalence against a golden
      linear-fold model. Currently dark.
    - TD #69 / #70: TAGE / ITTAGE rollback + history-recompute
      test. Was blocked on G20/G21/G22; this document unblocks
      it. Still gated on the cluster providing the rollback
      stimulus path.
    - Performance item (section 5.4): stale-fold cost at SPEC.

---

## 9. Interactions With Other Planning Documents

  bp_history_interfaces.md
                  -- bp_history interface contract: port list,
                     timing, producer/consumer obligations. Carries
                     the port reconciliation listed in section 8.

  bp_cluster.md   -- pointer ownership (the cluster is the pointer
                     authority, section 2), rollback stimulus,
                     FTQ entry contents, GHR 256b / PHR 32b,
                     folds recomputed on rollback.

  tage_table_hash_rules.md / ittage_table_hash_rules.md
                  -- consume the folded outputs for index/tag
                     hashing. HI2 (PHR mixing) lands here.

  bp_defines_pkg.sv / bp_structs_pkg.sv
                  -- GHR_WIDTH, PHR_WIDTH, pointer/FTQ widths,
                     per-table history and fold widths,
                     bp_folded_hist_t.

---

## 10. Document History

2026-06-26  session-055 (BP-072). Root cause found: session-054 left
              BP-069 (module-owned pointer interface) and BP-071 (fold
              geometry) in SEPARATE files -- BP-069 only in
              versions/bp_history.sv, BP-071 only in the active rtl/
              file -- so no single file held both, and the pointer-to-
              fold addressing for an incrementing module-owned pointer
              was never written or tested. handoff-054 and
              PROJECT_STATUS recorded both as landed and lint-clean;
              that was inaccurate. BP-072 merged the two into the
              active rtl/ file and wrote that addressing for the first
              time: with the pointer INCREMENTING (section 2.1) the
              recompute walks the GHR downward (anchor - i) and
              fold_step fetches its leaving bit at write_addr - H. The
              BP-071 geometry (posmap, high-end insertion, (H-1)%W
              eviction) is UNCHANGED; this was an addressing
              reconciliation, not a geometry change, and no table-
              consumed fold value moved. While writing it, the
              checkpoint-timing inconsistency between this doc (section
              6, pre-advance) and bp_history_interfaces.md (post-
              advance) surfaced; resolved to POST-advance (ratified)
              for the num_branches-independent anchor reason in section
              6. recompute == incremental proven in simulation (TD #74,
              tb_bp_history): 13 directed cases, 19224 golden
              comparisons, incl. single-slot, dual-slot, GHR-boundary
              wrap, SC ST3 (H=W=64). Open: external fold-value anchor
              against the table hash-rule docs (the suite proves
              recompute == incremental but not that the fold value
              matches the table-consumption contract -- BP-073).

<!--
  2026-06-26  session-055 (BP-072). Landed the module-owned-pointer
              RTL (BP-069) into rtl/ and reconciled it with the
              BP-071 fold geometry. Found that BP-071's geometry
              (newest at ptr, older at ptr+i, leaving bit at ptr+H)
              assumes a DECREMENTING pointer and is inconsistent with
              the ratified incrementing pointer (section 2.1): the
              incremental fold diverged from the rollback recompute.
              Resolution: increment-oriented geometry (fold_ghr walks
              downward ptr-i; fold_step evicts at write_addr-H) plus a
              POST-advance checkpoint with recompute anchor ckpt-1
              (section 2.2, section 6). incremental == recompute is
              now proven in simulation (TD #74, tb_bp_history): 13
              directed cases, 19224 golden fold comparisons, including
              single-slot, dual-slot, GHR-boundary wrap, and SC ST3
              (H=W=64). This supersedes the section-6 pre-advance
              checkpoint wording and aligns with the interface doc.
-->

  2026-06-25  session-054. Created. Resolves G20/G21/G22
              (= HI1/HI3/HI4). Decisions: dual-slot combined
              slot-0-then-slot-1 update with bundle-granularity
              checkpoint (section 3); rollback wins, mutually
              exclusive with update (section 4); stale-fold
              predictions allowed, G22 decoupled from G15
              (section 5). Pointer model ruled module-owned:
              internal pointer, sequential-only advance, internal
              checkpoint, rollback by index (section 2). This
              diverges from the as-built RTL (caller-owned input
              pointer) and changes both bp_history.sv and the
              interface port list (section 8). Sequential-only
              advance confirmed against Alpha 21264 and IBM GHV
              recovery practice; no surveyed design needs a
              non-sequential pointer. Mispredict-only restore
              (section 3.4): exceptions/interrupts reinitialize
              history, so no no-branch-flush restore case exists.
              Open: the module-owned RTL/port edit and
              TD #74 / #69 / #70 sequencing (section 8).

