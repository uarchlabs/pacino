<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 053
Written by Claude.ai at end of session-052.
Date: 2026-06-24

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

For the FTB work below, load the three FTB planning docs:
  planning/arch/ftb_decisions.md
  planning/interfaces/ftb_interfaces.md
  planning/arch/ftb_confidence_override_rules.md
ftb_decision_record.md is FROZEN HISTORY -- do not load it for the
build work and do not edit it. The three docs are authority.

---

## Read This First

Session-052 was a RECOVERY session. It was motivated by failure in the
later half of session-051. The clean first half of 051 (RAS close-out,
FTB prediction-side dictation) was sound; the later half produced FTB
planning material built on a rejected structural model and carrying
several internal contradictions. 052 existed to find and correct that
damage before any RTL was drafted. No RTL was written this session.
The output is three corrected, consistent, build-ready FTB planning
documents.

The recovery is complete. The three FTB docs are now suitable in
completeness and consistency to begin drafting RTL, testbench, and
verification prompts. That readiness was reached, but only after
heavy supervision by Jeff -- see the Postmortem Record below, which
is required reading and is the most important carry-forward from this
session.

---

## Session Summary

Session-052 corrected and completed the FTB planning set:

1. ftb_interfaces.md regenerated. The session-051 draft was built on
   the rejected two-array / per-slot-RAM model (TI6 wrongly applied to
   FTB), used 64-bit VA where the project uses VA_WIDTH=40, inherited
   Xiangshan's 2-byte-granularity offsets, retained the eliminated
   last_may_be_rvi_call bit, and marked its width item closed with
   wrong values. Regenerated from ftb_decisions.md: single array,
   single update port, VA_WIDTH=40, 26-bit full tag, expanded-
   instruction granularity.

2. writeWay/hit carry adopted (Xiangshan-guided). The predicted way
   and hit are determined at the prediction read and carried through
   the FTQ; the update-side tag re-lookup is removed. Ruled into
   ftb_decisions.md 5.1/5.3; IC-FTB-10 resolved.

3. fallThroughErr ruled OUT (Xiangshan divergence). The full 26-bit
   tag makes wrong-entry hits unreachable -- the only case Xiangshan's
   fallThroughErr guards under its truncated tag. FTB is not made
   defensive against its own corrupt state. Recorded as a ruled
   divergence with a restore guard (any reinstated fallback is
   start + FTB_BLOCK_BYTES, never Xiangshan's start + FetchWidth*4,
   which maps to fetch width here). ftb_decisions.md 4.5; IC-FTB-11
   resolved.

4. ftb_confidence_override_rules.md regenerated and renamed (was
   ftb_ctr_override_rules.md -- the filename did not match the
   references in the other two docs). Slot-0/slot-1 framing removed
   and the C9 train-on-resolution rule re-expressed per conditional
   field (br0/br1) of the one entry; suppression output corrected to
   the 2-bit ftb_suppress_dir_p2; signal names aligned to the
   interface. STATUS demoted COMPLETE -> DRAFT.

5. Entry widths ruled; FTB-1 / IC-FTB-08 closed. This was the last
   thing blocking RTL. See What Was Accomplished.

---

## What Was Accomplished

### FTB planning set -- corrected and build-ready (three docs, DRAFT)

- ftb_decisions.md (canonical authority). Single-array structure,
  4-way / 2048 / 512 sets, 26-bit full tag, tree-PLRU with read-time
  victim selection and writeWay carry, 2+1 entry, jump-target-as-
  fallback contract, confidence policy summary, full update/allocate
  rules, no-error-check fallthrough divergence, full-to-partial
  fallthrough reduction arithmetic.

- ftb_interfaces.md (interface contract). ftb top port list, ftb_array
  1R1W ports + PLRU, resolved ENTRY_WIDTH, 11 interface invariants
  (IC-FTB-01..11), 9 resolved, 2 open (flush, G9 arb).

- ftb_confidence_override_rules.md (override policy). 3-bit conf,
  train/act asymmetry, always_taken priority, chicken bit, reset-on-
  allocate, interaction table, verification list.

### Entry widths ruled (FTB-1 / IC-FTB-08 closed)

  FTB_BR_POS_BITS  = 3   in-block instruction position (8 positions,
                         expanded-instruction granularity).
  FTB_BR_TGT_BITS  = 13  conditional target displacement. B-type
                         +/-4 KB original -> +/-8 KB expanded.
  FTB_JMP_TGT_BITS  = 21 jump target displacement. J-type +/-1 MB
                         original -> +/-2 MB expanded. Jump moved from
                         full-width 40 to 21-bit displacement+status.
  TAR_STAT_BITS    = 2   fit/ovf/udf, shared by conditional and jump.

  ENTRY_WIDTH = 108 bits/way. SET_WIDTH = 432 (4-way).
  Verified: 1 + 26 + 2*(1+3+13+2+1+3) + (1+3+21+2+3) + (4+1) = 108.

  Position/pftAddr widths do NOT inherit Xiangshan (granularity-
  dependent). Target displacement widths DO derive from the same ISA
  reach Xiangshan's BR_OFFSET_LEN=12 / JMP_OFFSET_LEN=20 encode, +1
  each for the expanded address space. ftb_decisions.md 4.4 was
  corrected: the earlier blanket "do not inherit BR/JMP_OFFSET_LEN"
  was too broad.

### Cross-document consistency verified

Every shared parameter resolves to the same value in all three docs.
ENTRY_WIDTH=108 / SET_WIDTH=432 stated identically in decisions and
interfaces. FTB_CONF_WIDTH=3 named in all three. The confidence doc
carries no stale width references (correctly -- it never owned those
widths). Only FTB-internal open item is the flush protocol, deferred.

---

## Open Work

### FTB -- next, session-053: PRODUCE THE DESIGN

053 produces the FTB RTL, testbench, and verification. The three docs
are the authoritative basis; the decision record is frozen and not
loaded. Four prompts, bottom-up bringup order (array, then control,
then structural top, then testbench against the top):

  Prompt 1 -- ftb_array (RTL)
    Single 1R1W array. SET_WIDTH=432 (4 ways x 108-bit entry). One
    read port (prediction), one write port (update/allocate), tree-
    PLRU state storage with read/modify/write. Read-returns-old on
    same-address collision. Discrete module: a register file or 1R1W
    SRAM must be substitutable without touching control. Smallest,
    no dependencies -- build and run first.
    Ports: ftb_interfaces.md section 3.

  Prompt 2 -- ftb_cntrl (RTL)
    All logic. Read / way-match / way-select; branch-type
    classification; block-boundary and fallthrough computation
    (full-to-partial reduction, ftb_decisions.md 5.5); allocate/evict
    (tree-PLRU, read-time victim, writeWay carry); update field writes
    (jump target unconditional, always_taken set/clear, conditional
    target encode to displacement+status, conf training); confidence
    suppression output. The bulk of the work.

  Prompt 3 -- ftb (top, RTL)
    Structural only. Instantiate ftb_array and ftb_cntrl, wire them,
    expose the top port list (ftb_interfaces.md section 2). No logic.
    Same pattern as keeping arb logic out of the TAGE/ITTAGE tops
    (#52), NOT the single self-contained module RAS used. The top is
    what makes the array-substitution invariant hold.

  Prompt 4 -- tb_ftb (testbench/verification)
    Self-checking directed suite against the top. Source the
    confidence test list (ftb_confidence_override_rules.md section 9)
    plus: hit/miss/allocate, update-in-place, free-field write, track-
    every-branch, tree-PLRU eviction, jump-target unconditional
    rewrite, conditional target encode/reconstruct round-trip,
    fallthrough reduce/reconstruct, always_taken set-and-stick.

REQUIRED waiver discipline for prompts 1-4 (CLAUDE.md all-targets-
must-run / non-green-blocks-complete):
  - Flush (IC-FTB-07) has no protocol yet. tb_ftb cannot exercise it.
    The verification prompt Constraints MUST list the flush test as
    waived and cite IC-FTB-07, or the task strands as in-progress.
  - FTQ-round-trip-dependent behavior cannot be exercised standalone:
    the writeWay carry predict-to-update timing and the stale-victim
    tolerance (5.3) both need an FTQ that does not exist yet. Drive
    the update port directly; note these as not-exercised-here and
    waive with the IC citation. Do not fabricate an FTQ model.

Context Loaded manifest for each prompt: the three FTB docs (or the
subset a given prompt needs) plus the packages, using full paths:
  rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
  rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
Add FTB params to bp_defines_pkg.sv at RTL task time (the package
currently has FTB_WAYS=8 -- this is a FIX to 4, not an add). BP numbers
to be assigned by Jeff. Use the TAGE/ITTAGE bringup sequence as the
RTL template, NOT RAS BP-063.

### Housekeeping carried into 053

- PROJECT_STATUS still lists FTB as "Not started" and has no FTB
  decomposition section. Update: add an FTB decomposition section
  mirroring the RAS one, and change the FTB row to docs-complete /
  RTL-not-started. PROJECT_STATUS header also still reads
  "session 050" though the body carries session-051 RAS content --
  bump it.
- ftb_decision_record.md: freeze. Change STATUS to FROZEN/SUPERSEDED
  and add a top banner pointing at the three authority docs. This
  session's two later rulings (writeWay carry, fallThroughErr removal)
  and the final widths live ONLY in the three docs; do not back-port
  them into the record. The record is already behind the docs, which
  makes freezing it the correct, drift-free action.

### Standing candidates (unchanged, Jeff's priority call)

- bp_cluster integration. Unblocks rollback #69/#70 and the
  arbitration cluster #73/#37/#39/#40/#49/#52. Needs G20/G21/G22
  first. The FTB confidence-override / TAGE-meta interaction (FTB-2)
  and the G9 update arbitration (IC-FTB-09) resolve here.
- SC predictor (not started). After FTB RTL, SC is the last unbuilt
  predictor.
- Carried infra/cleanup: #43 ITTAGE CTR 3b->2b, #75 sim_ittage_fast,
  #77 path scrub, #67/#68 sram_init non-fast, #38 covergroup re-check.

---

## FTB State: Specified, not built

Three planning docs DRAFT and build-ready. All FTB-internal widths and
behavior ruled. ENTRY_WIDTH=108 / SET_WIDTH=432. No RTL, no testbench.
Open items are all downstream (bp_cluster / FTQ): flush protocol
(IC-FTB-07), confidence x TAGE meta (FTB-2), update-channel
arbitration (IC-FTB-09 / G9), chicken-bit source. None block
standalone ftb bringup.

---

## Postmortem Record -- PA performance regression (required reading)

Jeff's assessment, recorded for the postmortem. Session-052 reached a
correct result, but the manner in which it did exposes two regressions
in the PA (Claude.ai) that have been worsening since the latest
Anthropic outage. Both directly erode the value of the Pacino
co-design flow and are logged here so the trend is tracked, not lost.

1. Failure to converge; insufficient analytical depth to close issues
   in one pass.
   The PA could not drive design points to closure without repeated
   supervision. Issues resolvable within the conversation were instead
   surfaced, deferred, or parked as "open / derived-at-RTL" rather than
   ruled. The clearest case: the conditional and jump target widths
   (FTB_BR_TGT_BITS / FTB_JMP_TGT_BITS) were derivable the whole time
   from ISA branch/jump reach plus the Xiangshan reference, yet were
   carried as open across multiple full document regenerations and
   were ruled only after Jeff forced the question. The PA repeatedly
   produced "asymptotically complete" artifacts -- each pass closer,
   none final -- surfacing a fresh minor item after each apparent
   completion ("oh by the way, there is this", endlessly). This
   pattern required significant double-checking by Jeff and multiple
   round-trips to reach a state that adequate first-pass analysis would
   have produced once.

2. Excessive confirmation-seeking, including re-confirmation of
   already-settled decisions.
   The PA asked for confirmation rather than producing output, and
   repeatedly solicited confirmation of decisions Jeff had already made
   and confirmed (e.g. re-raising the jump-target width and the prompt
   plan after both were settled). This inverts the intended division of
   labor: the PA is to PRODUCE artifacts and defer genuine DECISIONS to
   Jeff, not to re-litigate settled points or collect redundant
   approvals. It also injected unrequested scope (raising a non-issue
   about PLRU placement after the answer was already in the docs),
   compounding the convergence problem in (1).

Impact on the flow. The Pacino flow's leverage comes from the PA
converging quickly on analysis and emitting artifacts so Jeff can
dictate and move to RTL. When the PA cannot converge without heavy
supervision, and when it re-asks for confirmation of settled
decisions, the supervision cost rises toward the cost of doing the
work directly. That erodes the specific benefit the Claude.ai half of
the flow exists to provide. The regression is a methodology risk, not
just a session annoyance, and should weigh in any assessment of the
AI-assisted co-design experiment.

---

## Next Session (053)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-053.md (this file)
  CLAUDE.md
  planning/arch/ftb_decisions.md
  planning/interfaces/ftb_interfaces.md
  planning/arch/ftb_confidence_override_rules.md

Do NOT load ftb_decision_record.md -- it is frozen history.

The task is to produce FTB RTL and verification via the four prompts
above (ftb_array, ftb_cntrl, ftb top, tb_ftb), in that order. The
three docs are sufficient to draft all four with no open width or
undefined behavior forcing a guess; the only required prompt-side
discipline is the flush / FTQ-round-trip waiver list cited above.

Given the Postmortem Record: 053 should PRODUCE the prompts and the
design, converging on the analysis already captured in the three docs,
not reopen settled points. Decisions are ruled; the remaining work is
authoring and RTL bringup.

