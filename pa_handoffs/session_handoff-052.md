<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 052
Written by Claude.ai at end of session-051.
Date: 2026-06-24

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

For the FTB work below, also load ftb_decision_record-051.md
(included with this session's context by Jeff).

---

## Read This First

Session-051 was a clean, productive session -- a deliberate contrast
to session-050. Two things were accomplished: RAS was closed out
(BP-064 landed, RAS is now Complete), and the FTB predictor was taken
through a full architectural-decision pass. No RTL was written this
session beyond the BP-064 testbench addition; the FTB output is a
decision record, not code.

The methodology held this session. The PA stated invariants before
recommending, searched for reference data rather than asserting from
memory, and surfaced decision forks for Jeff rather than guessing.
No outage, no model switch required.

---

## Session Summary

Session-051 had two phases:

1. RAS cleanup (BP-064). Closed out the RAS work that session-050 left
   dubious. The commit_rctr item was re-scoped from fix to defer after
   establishing the field is write-only/inert and the commit interface
   carries no recursion count. BP-064 ran clean: no RTL change, one new
   directed test pinning TD #78, doc reconciliations, full suite green
   (sim_ras 87/0, 22/22 targets). RAS is Complete.

2. FTB architecture. A full dictate-vs-propose pass over the FTB
   predictor: structure, sizing, entry format, the ITTAGE-miss target
   fallback, and a new confidence-override policy. All decisions
   captured in ftb_decision_record-051.md. No planning docs written
   yet -- that is session-052's job.

---

## What Was Accomplished

### BP-064 -- RAS verification/reconciliation round (Complete)

- Re-scoped from the session-050 handoff's plan. The commit_rctr
  "defect to fix" was reversed by Jeff to a deferral (TD #79) after
  the PA established the field is never read by any output path
  (write-only) and the commit interface carries no recursion count to
  carry forward. A wrong value cannot cause a functional break -- only
  a degraded fallback prediction on recursive call/return patterns.

- TD #78 and TD #79 filed by hand by Jeff before the task ran:
    - TD #78: p3 undo-pop does not reverse a recursion-decrement pop.
      LEAVE AS-IS, pinned by a new test.
    - TD #79: commit_rctr commit-stack recursion depth not preserved.
      DEFER to bp_cluster/FTQ integration.
  ras_decisions.md section 5 was also hand-reconciled by Jeff before
  the run (commit_rctr documented as a deferred limitation).

- BP-064 deliverables (IA, Opus 4.8): tb_ras TC-21 added, pinning the
  TD #78 non-reversing behavior (asserts current behavior, does NOT
  fix it -- the test locks the limitation open on purpose). Verified
  the pinned values (spec_rctr[1] stays 0, tosr=2, tosw=2) against the
  RTL by hand -- they match. ras_decisions.md (3.2 sentinel/15-depth,
  1/1.2 repair semantics, 3.3/4.5 BOS-on-commit) and ras_interfaces.md
  (IC-RAS-11 only) reconciled to the RTL as built. PROJECT_STATUS
  updated: ras.sv -> Complete, ras_interfaces.md row added, BP-062 RAS
  param block and tb_bp_pkg.sv 6->4b literal fix recorded.

- Full BPU suite this session: 22/22 targets exit 0, all sims green,
  all lints zero-warning. sim_ras 87/0. No waivers.

- A CLAUDE.md consistency fix was applied by Jeff: the
  "write only within RESULTS markers" rule contradicted the
  "Model Reporting in Task Files" rule (which requires the IA to write
  the Model header field). Added an explicit exception line under
  Experiment File Rules pointing at the Model Reporting section.

### FTB architecture decisions (decision record only, no docs yet)

Full detail in ftb_decision_record-051.md. Summary of what was decided
this session:

- Structure: per-slot RAMs per TI6 (RAM0->slot0, RAM1->slot1), single-
  read each, no dual-port. Independent-blocks model (slot 1 always
  reads at pred_pc+32, static per G17; cross-slot priority resolved
  downstream). 4-way, parameterized FTB_WAYS. 2048 entries PER SLOT
  baseline (512 sets x 4-way), parameterized FTB_SETS, 1024/slot as
  documented area/timing relief lever. Growth path is multi-level
  (L2 FTB victim), not fatter-flat.

- Timing: FTB at s2 is off the zero-bubble path (uBTB covers s1). FTB
  overrides uBTB at s2; that override is an s2 redirect with a bubble,
  documented as the cost buying FTB its timing latitude.

- Entry: 2+1 (two conditional slots + one terminal jump slot), no
  Xiangshan slot-sharing. Targets stored as offsets EXCEPT the jump-
  slot target, which is full-width because it is the architectural
  fallback for ITTAGE misses (no IT0 base table) and RAS-empty
  returns. always_taken kept. Offset/pftAddr widths sized for pacino's
  expanded-instruction layout, NOT Xiangshan's 12/20-bit RVC widths.

- Confidence override (its own planning doc): 3-bit saturating counter
  per conditional slot. Trains unconditionally on FTB correctness at
  execute (pure observer). Acts at s2 to suppress TAGE/SC DIRECTION
  overrides only, when conf >= FTB_CONF_SUPPRESS_THRESH (=6).
  always_taken has priority over it. Chicken bit gates suppression
  only; training always runs. Reset on (re)allocation to FTB_CONF_INIT
  (=3'b011). Invariant: FTB_CONF_INIT < FTB_CONF_SUPPRESS_THRESH.
  Slot-1 training gated on the executed path (train on resolution, not
  on read).

---

## Open Work

### FTB -- next, session-052

Expand ftb_decision_record-051.md into the three formal planning docs:
  - planning/arch/ftb_decisions.md            (canonical authority)
  - planning/interfaces/ftb_interfaces.md     (interface contract)
  - planning/arch/ftb_confidence_override_rules.md  (override policy)

Mirror the RAS pair for the first two. The confidence doc is new (no
RAS analog).

IMPORTANT process notes for 052:
- Once the three docs are written, the decision record becomes FROZEN
  HISTORY. Do not maintain it in parallel with the three docs -- the
  three docs are authority. Maintaining all four reintroduces the
  doc-vs-doc drift the project keeps fighting.
- Two items in the record are genuinely OPEN, not settled. Do not let
  them be silently resolved during expansion:
    1. Update/allocation path (replacement policy, allocation trigger,
       how conf/always_taken are written at update, pseudo-LRU vs
       other). This is NOT doc-crafting -- it is another architecture-
       dictation pass like the FTB prediction-side pass. 052 may
       PROPOSE options for Jeff but must NOT bake one in (do not pick
       pseudo-LRU just because Xiangshan does). The FTB model is
       complete on the read/prediction side and unspecified on the
       write/evict side.
    2. F12 last_may_be_rvi_call equivalent: raised, not ruled. May be
       moot under pacino RVC pre-expansion. Verify against block-
       boundary behavior; Jeff to rule.
- Index/tag/offset exact widths depend on the F12 expanded-instruction
  layout and final FTB_SETS; derive during doc-crafting.

### Standing candidates (unchanged, Jeff's priority call)

- bp_cluster integration. Unblocks rollback items #69/#70 and the
  arbitration cluster #73/#37/#39/#40/#49/#52. Needs G20/G21/G22
  resolved first. bp_cluster.md LOCKED, bp_arb_spec.md In progress.
  Note: the FTB confidence-override policy may interact with TAGE's
  update/meta path at integration -- flagged in the record, not yet
  analyzed.
- SC predictor (not started). FTB is now architecturally specified
  but not yet built; SC and FTB are the two remaining unbuilt
  predictors.
- Carried infra/cleanup: #43 ITTAGE CTR 3b->2b, #75 sim_ittage_fast,
  #77 path scrub, #67/#68 sram_init non-fast, #38 covergroup re-check.
  Small, independent, good low-context filler.

---

## RAS State: Complete

ras.sv and tb_ras.sv are complete (BP-062/063/064). Directed suite
sim_ras 87/0. Two limitations are filed and bounded:
  - TD #78 (pinned by TC-21): undo-pop does not reverse a recursion
    pop. Revisit at bp_cluster if an s2/s3 repair over a recursion pop
    is ever required.
  - TD #79 (deferred): commit_rctr recursion depth not preserved.
    Needs a recursion-count source on the commit interface; decide at
    bp_cluster/FTQ integration.
RAS-3 (flush behavior) remains reserved pending the flush protocol.

A caution note was added to the top of BP-063 by Jeff flagging the
session-050 authorship issues. BP-062 was clean. Use the TAGE/ITTAGE
bringup sequence as the RTL-bringup template, NOT BP-063.

---

## Trust and Stability

Session-051 ran clean. The PA stated invariants before recommending,
retrieved reference data (Zen/Apple/Xiangshan sizing, BTB
associativity literature) rather than asserting from training memory,
and surfaced architectural forks for Jeff's dictation rather than
guessing. No Anthropic outage, no mid-session model switch.

One process observation worth carrying: PROJECT_STATUS was edited by
the IA in BP-064 under explicit prompt authorization. Jeff's ruling is
that this stays a PER-PROMPT decision (the task author confirms all
non-task files are committed before authorizing it), NOT a CLAUDE.md
rule -- the size of PROJECT_STATUS argues against loading it into
every task's manifest. Good for keeping the file current when used
with that discipline.

---

## Next Session (052)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-052.md (this file)
  CLAUDE.md
  ftb_decision_record-051.md (for the FTB doc-crafting work)

Priority is Jeff's call. The obvious next step is FTB doc-crafting
(expand the decision record into the three planning docs), followed by
the FTB update/allocation architecture pass (which is dictation, not
doc-crafting). After the docs and the update-path decision, FTB task
files (BP-0xx) can be generated and FTB RTL bringup can begin.

The TAGE/ITTAGE directed-validation sequence remains the template for
unit-level validation. RAS BP-062/063 is NOT a clean template (it
needed two defect fixes and a verification round); learn from it but
do not copy its task-authorship mistakes.

