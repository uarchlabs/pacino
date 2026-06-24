<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 051
Written by Claude.ai at end of session-050.
Date: 2026-06-23

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Read This First

Session-050 was largely unproductive and the RAS is NOT signed
off. Treat ras.sv as work-in-progress with one known unfixed
defect and a pending verification round (BP-064), not as a
complete module. The sim suite is green, but green here does
not mean done -- see "RAS State: Dubious" below.

If you are the session-051 PA: the methodology itself is under
scrutiny after this session. Read the "Trust and Stability"
section. 

---

## Session Summary

Session-050 was meant to bring up the RAS predictor end to end:
planning documents, RTL (BP-062), testbench (BP-063), then a
verification round. The planning documents were written and the
RTL and testbench exist and pass, but the session was badly
degraded by an Anthropic outage, by repeated PA failures
generating task files and answering architectural questions. A
mid-session model switch to Opus was required to constrain the
issues. RAS is functional enough that the
directed suite passes 79/79, but it carries one unfixed defect,
several unapplied documentation reconciliations, and one new
technical debt item. A verification round (BP-064) is required
before RAS can be called complete.

Honest assessment: the value extracted from this session came
mostly from the IA (Claude Code) catching the PA's errors and
from the testbench structurally catching two real RTL defects.
The PA (Claude.ai) was unreliable for a large part of the
session.

---

## What Was Accomplished

### RAS planning documents (written, mostly reconciled)

- ras_decisions.md -- canonical RAS decision record. Records
  G5 (16 spec + 32 commit, static partition), G6 (4b recursion
  counter), G8 (fixed boundary bundle split), G17 (slot 1 PC =
  pred_pc+32), and the simple-circular-buffer internal
  structure decision. STILL NEEDS reconciliation edits, see
  "Open Work" -- §3.2 sentinel/15-depth, §1 repair semantics,
  §3.3 BOS-on-commit, §5 commit_rctr.

- ras_interfaces.md -- ras.sv interface contract. Was corrected
  this session to the array-form port list (slot dimension is
  [0:NUM_PRED_SLOTS-1], not a _p0/_p1 suffix; p-stage suffix is
  the pipeline stage). Includes p0 TOS read ports and p3 repair
  ports. This file is current and matches the RTL. IC-RAS-11
  still needs the repair-semantics clarification (see Open Work).

- Reconciliation edits were also phrased for bp_cluster.md,
  bp_arb_spec.md, and PROJECT_STATUS.md (G5/G6/G8/G17 marked
  resolved, RAS quick-refs corrected 48 -> 16+32, stale 6b
  snapshot comment -> 4b). Confirm these landed; some were
  applied earlier in the session before the outage.

### BP-062 -- ras.sv RTL (ran, green, but see defect below)

ras.sv implemented as a single self-contained module: two
register-file stacks (16 speculative simple-circular-buffer,
32 commit), p0 TOS read, p2 dual-slot push/pop with slot-0-
before-slot-1 ordering and the same-cycle call/return bypass,
recursion counter, post-op snapshots, pointer-only mispredict
restore, p3 repair, commit-stack update with empty fallback.
Named generate block for the per-slot p0 fan-out. lint clean.

bp_defines_pkg.sv: the stale pre-session RAS block
(RAS_SPEC_ENTRIES=48, RAS_RET_ADDR_BITS=41, linked-array
comment) was replaced with the session-050 values
(16/32/4, RAS_PTR_BITS=4, RAS_COMMIT_PTR_BITS=5,
RAS_ADDR_WIDTH=VA_WIDTH). The IA correctly STOPPED on the
first attempt because the PA had not read bp_defines_pkg.sv
before writing the task and the prompt said "add missing
params" when the params existed with wrong values. The prompt
was rewritten to replace the block in full.

bp_structs_pkg.sv: bp_ras_snapshot_t comment updated to remove
the linked-array reference; struct fields unchanged.

Induced fix: the RAS_PTR_BITS 6 -> 4 change broke hardcoded
6-bit literals in tb/tb_bp_pkg.sv:203-205. Fixed under
authorization to RAS_PTR_BITS-width values. This was an
out-of-scope file; the IA stopped and reported before touching
it. Record this in PROJECT_STATUS notes for bp_defines_pkg.sv /
bp_structs_pkg.sv.

### BP-063 -- tb_ras.sv testbench (ran, green)

20 directed test cases TC-01..TC-20. Final: sim_ras 79/79 PASS,
full Makefile suite 22/22 targets exit 0. Two real ras.sv
defects were found during bring-up and fixed under explicit
per-defect authorization:

- DEFECT 1 (fixed): empty/valid off-by-one. The first push
  landed on the BOS slot, so one live entry read identical to
  empty (TOSR==BOS==0 after a cold-start push). FIX: the BOS
  index is a permanent sentinel; a push that would land on BOS
  (cold-start or full wrap) allocates at BOS+1. Empty test
  stays TOSR==BOS. TOSW stays monotonic (preserves pointer-only
  restore). COST: usable speculative depth is 15, not 16.

- DEFECT 2 (fixed): p3 undo-pop repair re-allocated a frontier
  slot and wrote the fallthrough instead of re-exposing the
  still-resident popped entry. FIX: split the repair path --
  undo-pop (p3_op_q==OP_POP) does a TOSR-only re-expose (move
  TOSR back, reload addr/rctr from the array, no write, TOSW
  unchanged); the missed-push case keeps frontier allocation.
  TC-17 passes after the fix.

Both defects were caught structurally -- DEFECT 1 because the
testbench could not pass with a one-entry stack invisible, and
DEFECT 2 because the prompt required TC-17 to test undo-pop as
a feature in its own right rather than as setup. This is the
methodology working even where the PA's analysis failed.

---

## RAS State: Dubious -- Do Not Treat As Complete

ras.sv passes its directed suite but is NOT signed off. Open
items that block completion:

1. UNFIXED DEFECT -- commit_rctr. ras_decisions.md §5 states the
   commit-stack recursion counter is updated when a recursive
   call commits. The RTL writes commit_rctr <= 0 on every commit
   push and never accounts for recursion. Jeff has ruled this a
   DEFECT to FIX (not defer) -- the doc is the intent, the RTL is
   incomplete. This is in scope for BP-064. The fix must make the
   commit-stack push carry the committing entry's recursion
   count rather than zeroing it. Confirm the source of that count
   at the commit interface when scoping the fix.

2. TD #78 (new) -- p3 undo-pop does not reverse a recursion pop.
   The undo-pop re-expose reverses a TOSR-moving pop only. A pop
   that only decremented a recursion counter (TOSR held) is not
   reversible -- the pre-pop rctr is not recoverable from post-pop
   state. Jeff's ruling: LEAVE AS-IS, but ADD a directed test
   that confirms the current (non-reversing) behavior so it is
   pinned, and revisit at bp_cluster integration if an s2/s3
   repair over a recursion pop is ever required.

3. UNAPPLIED documentation reconciliations (see Open Work). The
   planning docs do not yet describe the RTL as built (sentinel
   rule, 15-entry depth, repair semantics, BOS-on-commit source).
   Until these land, the authority docs disagree with the RTL.

Bottom line for 051: RAS needs one verification round (BP-064)
that fixes the commit_rctr defect, applies the doc
reconciliations, adds the TD #78 confirming test, and re-runs
the full suite. Only then is ras.sv Complete.

---

## Open Work -- BP-064 Verification Round

This is the next RAS task. It is a verification/reconciliation
round, deliberately bundling RTL fix + doc edits + one test so
the docs, RTL, and tests are proven aligned in a single pass.

RTL fix:
- Fix commit_rctr (item 1 above). Carry the committing entry's
  recursion count into the commit-stack push instead of zeroing.

Test:
- Add the TD #78 directed test confirming undo-pop does not
  reverse a recursion pop (pins current behavior).
- Re-run sim_ras and the full Makefile suite; report per-target
  counts from the run.

Documentation reconciliations (apply, do not just phrase):

ras_decisions.md
- §3.2: BOS slot is a permanent sentinel; push allocates above
  BOS when TOSW would land on BOS; empty stays TOSR==BOS; usable
  depth = RAS_SPEC_ENTRIES-1 = 15 (16 physical). Correct the
  Push prose, which currently omits the sentinel skip.
- §1 / §1.2: clarify that the repair-table "push"/"pop" labels
  mean stack-height restoration of resident entries, not
  allocation/clear. Undo-pop = TOSR re-expose (no write, TOSW
  held). Undo-push = TOSR retract of a still-resident frontier
  slot. Only missed-push allocates+writes. Add the recursion-pop
  limitation note citing TD #78.
- §3.3 / §4.5: BOS on commit advances to the committing entry's
  post-op TOSR (commit_snapshot.tosr); restore wins over commit
  for BOS in the same cycle.
- §5: reconcile to whatever the commit_rctr fix implements.

ras_interfaces.md
- IC-RAS-11: append the same repair-semantics clarification
  (height restoration, not allocation/clear).
- Close RI-4 (s3 ports now in port list) and narrow RI-1 (s0
  TOS port exists; only the uBTB/FTQ connection is deferred).
  NOTE: the current ras_interfaces.md already has the corrected
  array-form ports and p0/p3 in the port list -- this is a small
  wording pass on the contracts/open-items, not a port rewrite.

PROJECT_STATUS.md
- ras.sv row -> Complete (only after BP-064 passes), tests
  tb_ras, sim_ras 79/0.
- Add ras_interfaces.md row.
- bp_defines_pkg.sv / bp_structs_pkg.sv notes: record the
  BP-062 RAS param replacement and the authorized tb_bp_pkg.sv
  6->4-bit literal fix.
- RAS decomposition section: "RTL not started" -> ras.sv +
  tb_ras.sv complete (BP-062/063), two defects fixed, commit_rctr
  fixed and TD #78 filed in BP-064.
- Add TD #78.

---

## Process Control Issue -- IA Editing Outside RESULTS

The IA edited content outside the RESULTS block this session
(the DISCUSSION-block "Other Planning File Updates" and status
tables). The IA should write ONLY within the
RESULTS:START/RESULTS:END markers. Every future testbench/impl
prompt must include an explicit constraint:

  "Write only within the RESULTS:START / RESULTS:END markers.
   Do not edit the HEADER or DISCUSSION blocks."

This is experiment-specific authorship control and belongs in
the prompt's Constraints. Do not restate it as a CLAUDE.md rule;
state it per-task.

---

## Trust and Stability -- Read This

Session-050 was not efficient. The causes, recorded so
051 starts with eyes open:

1. Anthropic outage. 2026-06-23, ~10am US-central / 3pm GMT.
   status.claude.com confirmed a major outage across all
   platforms (chat, Claude Code, Cowork, API).  Claude Code
   threw a 401; it was resolved by /login OAuth re-auth, which 
   normally happens automatically and should not have been necessary.

2. PA unreliability during and around the outage. The PA gave
   superficial answers and repeatedly failed to consult
   in-context planning files until explicitly reminded that the
   context was available -- after which it could see them. This
   is a context-utilization failure, not a context-availability
   failure.

3. PA architectural failures. On the RAS empty/valid pointer
   problem the PA gave three successive wrong recommendations
   before converging, each corrected only under IA or Jeff
   pushback. The correct answer was derivable in one turn from a
   small fixed invariant set (TOSW monotonic; TOSR==BOS = empty;
   reset zeroes all). The PA was reacting to the latest objection
   rather than reasoning from the invariants. Jeff switched the
   PA from Sonnet to Opus 4.8 mid-session because of this.

4. Task-file generation failures - these are considered minor
   but time consuming. The PA produced incomplete or
   malformed task files multiple times -- stray RESULTS markers
   in guidance text (a CLAUDE.md violation), duplicated
   instructions already in CLAUDE.md, and failure to read
   bp_defines_pkg.sv before writing BP-062, which caused a
   blocking IA stop on stale parameters.

Implications for the flow. This flow depends on dual agency:
Claude.ai as PA (planning, task authorship, architectural
judgment) and Claude Code as IA (implementation, verification).
When the PA degrades, the IA's "stop and report" discipline and
the testbench's structural checks are what kept the session from
producing silently-wrong RTL. That safety net held this session.
But the PA's reliability and Anthropic's platform stability are
both now explicit risks to monitor every session. The PA going
forward must: state invariants before recommending, check an
answer against all of them before sending, discard-and-rederive
when caught wrong rather than patch the latest objection, and
flag genuine uncertainty instead of emitting a confident guess.

---

## Next Session (051)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-051.md (this file)
  CLAUDE.md

Priority is Jeff's call. The obvious next step is BP-064 to
close out RAS (commit_rctr fix, doc reconciliations, TD #78
test, full suite re-run). Until BP-064 lands, RAS is not
complete regardless of the green sim count.

Other standing candidates (unchanged from 050):
- bp_cluster integration (unblocks #69/#70 rollback and the
  arbitration cluster #73/#37/#39/#40/#49/#52; needs G20/G21/G22
  resolved first; bp_cluster.md LOCKED, bp_arb_spec.md In
  progress).
- FTB, SC predictors (not started).
- Carried infra/cleanup: #43 ITTAGE CTR 3b->2b, #75
  sim_ittage_fast, #77 path scrub, #67/#68 sram_init non-fast,
  #38 covergroup re-check.

The TAGE/ITTAGE directed-validation sequences remain the
template for any further unit-level validation. The RAS BP-062/
063 sequence is NOT yet a clean template -- it required two
defect fixes and a verification round; learn from it but do not
copy its task-authorship mistakes.

