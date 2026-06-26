<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# bp_history Micro-Architectural Decisions
```
 FILE:    bp_history_decisions.md
 SOURCE:  session-054
 STATUS:  DRAFT
 UPDATED: 2026-06-26
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
interface port list. Section 9 separates the doc-only
reconciliation from the RTL changes.

Section 6 is the canonical fold definition: the bit-exact geometry
of every folded history this module produces, stated in the
project's own terms so the RTL, the testbench reference, and any
downstream check derive expected fold values from this document
rather than from an external source.

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
(section 9).

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
  is defined canonically in section 6 (origin: BP-071 Xiangshan
  convention) and did NOT change. What BP-072 set is the buffer-walk
  ADDRESSING that feeds that geometry under the module-owned
  incrementing pointer (section 2.1): the newest bit sits just below
  the live pointer, so the recompute walks the GHR DOWNWARD (offset
  i -> ghr_mem[anchor - i]) and the incremental fold_step fetches its
  leaving bit at write_addr - H. The recompute anchors at ckpt - 1
  because the checkpoint stores the post-advance pointer (section 7)
  and the newest bit of the bundle is one position behind it.
  fold_step is the exact incremental form of fold_ghr for this
  mapping (section 6.4), so the rollback recompute reproduces the
  incremental fold; TD #74 (tb_bp_history) confirms it in simulation
  for single-slot, dual-slot, GHR-boundary wrap, and SC ST3 (H=W=64).
  No fold value consumed by the TAGE/ITTAGE/SC tables changed -- only
  the recompute walk direction and the checkpoint anchor were fixed
  to match the incrementing pointer.

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
GHR-derived (HI2, deferred -- section 9).

### 3.3  Combined fold: ordering is load-bearing

The slot-1 fold step consumes the slot-0 fold result within the
same cycle (nested fold_step in RTL). Folding slot-0-then-slot-1
is not equal to the reverse order. The ordering invariant is:

  The incremental two-step fold (slot 0 at ptr, slot 1 at ptr+1)
  must equal the full recompute over the same two new bits walked
  by age from the newest (section 6.4). The rollback recompute
  walks the buffer by age from the restored pointer, so the two
  paths agree only if the incremental order matches the age walk.
  Slot 0 first, slot 1 second is that order.

This equivalence is the core correctness property of the dual-slot
path. It is the obligation TD #74's directed test proves against
the canonical fold definition (section 6, section 9). Proven in
simulation (TD #74, tb_bp_history).

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
skew. Apply when TD #74 touches the file (section 9).

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
changes with the port edit (section 9). The priority structure is
unaffected by that change.

This places the complexity in isolation: rollback is its own
state transition, never a blend with prediction update.

Producer obligation: the cluster may assert rollback_valid and
pred/num_branches in the same cycle; if it does, the prediction
is understood to be discarded. The cluster is not required to
suppress the prediction inputs, because the RTL ignores them
under rollback_valid. (The interface DRAFT's stricter "producer
must not assert both" obligation is relaxed to "rollback wins if
both are asserted." See section 9.)

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

## 6. Fold Definition (Canonical)

This section is the authoritative definition of every folded
history bp_history produces. It is stated in the project's own
terms so that the RTL (fold_ghr / fold_step), the testbench
reference, and any downstream producer/consumer check derive
expected fold values from THIS document, not from an external
source. Origin is recorded in section 6.6; the definition here is
the contract.

A folded history compresses an H-bit window of the global history
register (GHR) into a W-bit value by XOR. Each consuming table
selects its own (H, W): H = history length, W = folded width. The
per-table (H, W) values are package localparams (section 8:
TAGE_TBL_HIST/FH/FH1/FH2, IT_TBL_HIST/FH/FH1/FH2, SC_TBL_HIST).
This section defines the mapping, not the values.

### 6.1  Age indexing

  Index the H in-window history bits by AGE, not by buffer
  position. Age i = 0 is the NEWEST bit (the most recently written
  branch outcome); age i = H-1 is the OLDEST bit still in the
  window. Aging is independent of how the GHR buffer is addressed:
  the buffer-walk that maps age to a physical ghr_mem index is a
  pointer-model concern (section 2.2), not part of this definition.
  The fold is a function of the H-bit age-ordered history alone.

### 6.2  Position mapping (full recompute)

  The bit of age i contributes, by XOR, to folded output position

      posmap(i) = (i + W - 1) mod W

  Equivalently:
    - The newest bit (age 0) lands at the high end, position W-1.
    - Each older bit sits one position lower, modulo W (a left
      rotate per age step).
    - Ages that reach or exceed W wrap and XOR-overlap onto lower
      positions; this overlap is the compression.

  The folded value is

      fold = XOR over i in [0, H-1] of
               ( history_bit(age i) << posmap(i) )

  with all arithmetic in W bits. A history bit of 0 contributes
  nothing; a bit of 1 toggles its mapped position. This is the
  full recompute; bp_history uses it on rollback (fold_ghr).

### 6.3  Window eviction (incremental form)

  The incremental form advances the fold by one new bit per branch
  without rescanning the window (fold_step). One step:

    1. Left-rotate the W-bit fold by 1 (each occupied position p
       moves to (p+1) mod W).
    2. XOR the new (age-0) bit in at position W-1.
    3. XOR OUT the bit that has just left the H-deep window -- the
       bit now at age H -- at position

           posmap(H) = (H - 1) mod W.

  Step 3 removes the contribution the departing bit made when it
  entered: after H-1 rotations that contribution now sits at
  (H-1) mod W. Without step 3 the fold would accumulate bits older
  than the window. The departing bit is read from the GHR at the
  age-H position (RTL: ghr_mem[write_addr - H], section 2.2).

### 6.4  Equivalence invariant

  The full recompute (6.2) and the incremental form (6.3) MUST
  produce the same fold for the same H-bit history:

      recompute(history) == incremental(history)

  for every history and every (H, W) in use -- including H = W (no
  compression; SC ST1-ST3) and H > W (compression; the TAGE/ITTAGE
  tag folds fh1/fh2). bp_history uses the incremental form on the
  prediction path and the full recompute on rollback (section 2.2);
  this invariant is what makes the two paths interchangeable. For
  a dual-slot bundle the incremental form is applied twice, slot 0
  then slot 1 (section 3.3), and must still equal the recompute
  over both new bits. TD #74 proves the invariant in simulation
  (tb_bp_history).

### 6.5  Worked example (checkable)

  TAGE T1 index fold, H = W = 8 (TAGE_TBL_HIST[1] = TAGE_TBL_FH[1]
  = 8). This is the BP-073 TC14 anchor; the result below is the
  committed test literal, so this example and tb_bp_history agree
  by construction.

  Drive eight single-slot branches, oldest first, taken pattern
  p0..p7 = 1,1,0,0,1,0,1,1. p0 is written first (oldest), p7 last
  (newest), giving ghr[7:0] = 0xD3 and the age-ordered history:

      age i:  0 1 2 3 4 5 6 7
      bit:    1 1 0 1 0 0 1 1      (age 0 = p7, newest)

  posmap(i) = (i + 7) mod 8, taking only the set bits:

      age 0 (1) -> pos 7
      age 1 (1) -> pos 0
      age 3 (1) -> pos 2
      age 6 (1) -> pos 5
      age 7 (1) -> pos 6

  Set positions {7, 6, 5, 2, 0} -> 1110_0101 = 0xE5.

  So bp_history.folded.tage_t1_idx_fh == 0xE5 for this history,
  matching tb_bp_history TC14. The ITTAGE IT1 anchor (0x9, H=W=4,
  sub-window) and the SC ST3 anchor (0xC000_0000_0000_0000,
  H=W=64, wrapped) in TC15/TC16 follow the same definition at
  their (H, W).

### 6.6  Origin

  The geometry above originates in the Xiangshan FoldedHistory
  implementation (newest bit folded in at the high end, leaving
  bit removed at (H-1) mod W, one definition shared by update and
  recompute). It was captured into this section as the project's
  own contract from commit <XS-COMMIT-SHA> (<XS-CAPTURE-DATE>) so
  the definition does not depend on an external, mutable source.
  Xiangshan is cited as ORIGIN only; this section is the AUTHORITY.
  If a discrepancy with the upstream implementation is ever found,
  this document and the RTL it governs are corrected together by a
  tracked task -- the citation is not a live dependency.

---

## 7. Checkpoint

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
deferred (HI5, section 9).

---

## 8. Parameters

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
the fold functions (section 6). They are not restated here;
bp_history.sv reads them from the package.

The folded output is bp_folded_hist_t (bp_structs_pkg.sv): one
idx + two tag folds per TAGE T1-T4 and ITTAGE IT1-IT4, one idx
fold per SC ST1-ST3. ST0 (hist=0), ST4 (IMLI), and ITTAGE IT5
(BrIMLI) have no folds.

---

## 9. Open Items

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
      incremental-vs-recompute equivalence against the canonical
      fold definition (section 6). Proven (BP-072).
    - TD #69 / #70: TAGE / ITTAGE rollback + history-recompute
      test. Was blocked on G20/G21/G22; this document unblocks
      it. Still gated on the cluster providing the rollback
      stimulus path.
    - Producer/consumer fold check: drive a known GHR, take the
      bp_history fold output, run it through the actual TAGE/
      ITTAGE table index hash, confirm the resulting index against
      an independently-known value. End-to-end format agreement
      between bp_history and its consumers; needs cluster stimulus.
      Distinct from the BP-073 unit anchor (which proves the fold
      value against section 6, not the index the table derives).
    - Performance item (section 5.4): stale-fold cost at SPEC.

---

## 10. Interactions With Other Planning Documents

  bp_history_interfaces.md
                  -- bp_history interface contract: port list,
                     timing, producer/consumer obligations. Carries
                     the port reconciliation listed in section 9.

  bp_cluster.md   -- the cluster reads the exposed pointer for FTQ
                     entry construction and supplies rollback
                     stimulus (the checkpoint index); it does NOT
                     own or drive the pointer. Pointer ownership is
                     module-internal (section 2). Also: rollback
                     stimulus path, FTQ entry contents, GHR 256b /
                     PHR 32b, folds recomputed on rollback.

  tage_table_hash_rules.md / ittage_table_hash_rules.md
                  -- consume the folded outputs for index/tag
                     hashing. They define fold CONSUMPTION (the
                     index/tag hash given fh/fh1/fh2); the fold
                     COMPUTATION is defined here (section 6). HI2
                     (PHR mixing) lands in the hash docs.

  bp_defines_pkg.sv / bp_structs_pkg.sv
                  -- GHR_WIDTH, PHR_WIDTH, pointer/FTQ widths,
                     per-table history and fold widths,
                     bp_folded_hist_t.

---

## 11. Document History

  2026-06-26  session-055 (fold-definition capture). Added section
              6, the canonical Fold Definition: age indexing,
              position mapping posmap(i) = (i+W-1)%W, window
              eviction, the recompute == incremental invariant, and
              a checkable worked example tied to the BP-073 TC14
              anchor (history 0xD3 -> fold 0xE5). Xiangshan demoted
              to an origin footnote (section 6.6) with a captured
              commit/date placeholder. Section 2.2 now cites section
              6 as the geometry authority rather than "the BP-071
              Xiangshan convention." Old sections 6-10 renumbered to
              7-11; all "section N>=6" cross-references updated. No
              RTL or behavior change -- this captures the frozen,
              externally-anchored (BP-073) geometry in the project's
              own terms. A verification pass confirming the RTL still
              matches the reworded authority is the follow-on task.

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
              7, pre-advance) and bp_history_interfaces.md (post-
              advance) surfaced; resolved to POST-advance (ratified)
              for the num_branches-independent anchor reason in section
              7. recompute == incremental proven in simulation (TD #74,
              tb_bp_history): 13 directed cases, 19224 golden
              comparisons, incl. single-slot, dual-slot, GHR-boundary
              wrap, SC ST3 (H=W=64). External fold-value anchor against
              the canonical definition added in BP-073 (TC14-TC16);
              the hash-rule docs were found to define fold consumption
              only, which motivated the section 6 capture above.

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
              interface port list (section 9). Sequential-only
              advance confirmed against Alpha 21264 and IBM GHV
              recovery practice; no surveyed design needs a
              non-sequential pointer. Mispredict-only restore
              (section 3.4): exceptions/interrupts reinitialize
              history, so no no-branch-flush restore case exists.
              Open: the module-owned RTL/port edit and
              TD #74 / #69 / #70 sequencing (section 9).

