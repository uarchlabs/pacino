<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Overview
```
 FILE:    blog_handoff-006.md
 SOURCE:  RVA23 Blog-Gen Part 5
 STATUS:  DRAFT
 UPDATED: 2026-09-22
 CONTACT: Jeff Nye
```
Blog generation session handoff.

# Blog Handoff 006

Written by the PA at end of session `RVA23 Blog-Gen Part 5`.

Date: 2026-09-22

This session produced TWO drafts covering PA sessions 050-055:

  - BLOG_bpu_15_specification_under_test.md  (sessions 050-053, RAS+FTB)
  - BLOG_bpu_16_external_anchors.md          (sessions 054-055, bp_history)

Both are complete and delivered; neither has been reviewed. bpu/14 was
closed and published by the architect outside a session, so its four
review items from handoff-005 were not worked and are moot.

Together the two drafts cover 050-055 with no gap and no overlap.
Session 052 falls inside bpu/15 and produced no experiments.

Read this file, then the two drafts, before continuing.

---

## Post Identity

### bpu/15

- Series / number / short description: bpu / 15 / specification_under_test
- Target filename: BLOG_bpu_15_specification_under_test.md
- Working title: "Specification Under Test: What Bringup Proves About
  the Document" — CONFIRMED by architect
- Source range: Parts 050-053 (four PA sessions), BP-062 through BP-068
- Range type: Standard (Experiment Summary table, 10 rows)

### bpu/16

- Series / number / short description: bpu / 16 / external_anchors
- Target filename: BLOG_bpu_16_external_anchors.md
- Working title: "External Anchors: When a Proof and Its Reference Share
  the Same Error" — NOT CONFIRMED, PA's choice, open below
- Source range: Parts 054-055 (two PA sessions), BP-069 through BP-074
- Range type: Standard (Experiment Summary table, 6 rows)

---

## Inputs Status

Supplied this session:
  - session_handoff files: 050 through 056. These bound both ranges; 050
    opens bpu/15 (written at end of session-049) and 056 closes bpu/16
    (written at end of session-055).
  - experiment files, bpu/15: all 10. BP-062, 063 (session 050); BP-064
    (session 051); BP-065, 065a, 066, 066a, 066b, 067, 068 (session 053).
    Session 052 produced none.
  - experiment files, bpu/16: all 6. BP-069, 070, 071, 072 (sessions
    054-055); BP-073, 074 (session 055). BP-070 is ABANDONED and carries
    Run time and Ctx % of n/a.
  - PROJECT_STATUS.md and CLOSED_TECH_DEBT.md: supplied.
  - BLOG_GENERATION_PROCESS.md: supplied.
  - prior post: BLOG_bpu_14_directed_validation.md supplied as the
    structural template, and treated as published.
  - pa_session_map.md: supplied by the architect as an ad hoc guideline,
    explicitly not a spec or planning document. Used for orientation
    only; every boundary was confirmed against the handoffs.

PA sessions read directly:
  - Parts 050 through 055 are readable in the project and were used for
    prompt content and surrounding decisions, per the input rule now in
    the process doc. Confirmed working. This halves what the architect
    has to gather; only the completed experiment files are needed.

Still needed / outstanding requests to user:
  - None for these two drafts. The open items below are review decisions
    and process rulings, not missing inputs.

Source reliability flags:
  - session_handoff-054 is unreliable about its own session, twice.
    (a) It asserts BP-069 and BP-071 both landed and lint-clean. Neither
    statement was true of any single file; corrected in PROJECT_STATUS
    via BUG-005 in session-055. handoff-056 lists fixing the handoff
    itself as optional; it has not been done.
    (b) Its Postmortem item 1 asserts the PA fabricated a nonexistent
    file, ftb_decision_record.md. handoff-052 names
    ftb_decision_record-051.md, with the session suffix, and states the
    architect supplied it as session context. handoff-053 refers to the
    same thing three times without the suffix. The likely reading is a
    dropped suffix diagnosed as a fabricated file. The architect
    confirmed this session that no file by either name is part of the
    FTB planning set — the authority documents are ftb_decisions.md,
    ftb_interfaces.md and ftb_confidence_override_rules.md. Under the
    artifact-only postmortem ruling the item is out of scope for the
    post either way and was dropped. handoff-054's account remains
    questionable at source.
  - session_handoff-052 and session_handoff-053 contradict each other
    about session-051. 052 opens by calling it clean and productive, a
    deliberate contrast to 050. 053 states its later half produced FTB
    material built on a rejected structural model, with five specific
    errors, and that session 052 existed to undo it. The bpu/15 draft
    reports the sequence from 053 without adjudicating 052's
    self-assessment.
  - PROJECT_STATUS.md as supplied is session-068 era: UPDATED
    2026-08-22, newest narrative section Session-068, TD to #120, BP
    references to BP-109. handoff-005 described the prior session's copy
    as session-069 era. No session-069 content is present in this copy.
    Not blocking; the rollback convention applies to both ranges anyway.
  - BP-062's Ctx % is understated by its own report. The header records
    15%; the task's Context Usage Report states the snapshot predates a
    large document load in the same session and that actual usage was
    higher. The bpu/15 Experiment Summary prints the recorded figure
    marked understated and footnotes the reason.
  - BP-067 record drift, recorded by the architect in the task file
    itself. BP-066a and BP-066b re-edited ftb.sv after BP-067 produced
    it, so BP-067's Results no longer describe the file. The RTL is
    correct. Reported in bpu/15 as a bookkeeping consequence.
  - The checkpoint pre/post-advance question was resolved twice in
    opposite directions. BP-069 flagged the decisions-vs-interfaces
    contradiction and implemented pre-advance; the task's discussion
    block records the interfaces doc then being corrected to match.
    BP-072 resolved it to POST-advance in favor of the interfaces doc,
    because that is the only orientation under which a dual-slot
    rollback reproduces the incremental fold. bpu/16 reports the
    reversal with the reason rather than as a preference between docs.
  - pa_session_map.md contains off-by-ones, consistent with its stated
    ad hoc status. Sessions 52 and 53 both show handoff-053 as output;
    session 54 shows handoff-053 as input. It also attributes the three
    FTB planning documents to session 51; session 51 produced the
    decision record and session 52 produced the three documents. No
    boundary was set from the map.

---

## Process Progress

Per BLOG_GENERATION_PROCESS.md Step-by-Step Process. Both drafts
completed all steps.

  [x] 1. Ranges confirmed as real arcs, and the split confirmed against
         the alternative. See "Range confirmation" below.
  [x] 2. Experiment inventories built. 10 and 6, all with Results
         Capture except the abandoned BP-070, which carries a full
         Results block but no Run time or Ctx %.
  [x] 3. Thematic clusters identified
  [x] 4. Artifacts extracted per cluster
  [x] 5. Decisions and rationale extracted
  [x] 6. Friction / methodology events extracted, filtered by the
         artifact-only ruling below.
  [x] 7. PA/IA contribution separated
  [x] 8. Generalization drafted, checked across the clusters in each
         range per the Step 8 ruling recorded in handoff-004. bpu/16's
         generalization continues bpu/15's explicitly, which is a
         continuation rather than the prior-post comparison Step 8 does
         not require.
  [x] 9. Assembled in template (Abstract drafted last for both)
  [x] 10. Series navigation. Blocks present and empty. Step remains
          retired as a per-post item.

---

## Working Material Captured So Far

(Reference notes, not final prose.)

### Range confirmation and the split (Step 1)

The architect's opening proposal was one post covering three topics —
RAS (050/051), FTB (052/053), bp_history (054/055) — with three smaller
posts named as the undesirable alternative. The PA recommended two, and
the recommendation was taken.

The reasoning, recorded because it generalizes:
  - Sixteen experiments across six sessions and three units. handoff-005
    records that bpu/14 reached 4,999 words against a 5,000 maximum with
    21 experiments across two units that shared one method and one
    specification family, and states that a future range of that size
    should be assumed to need the same treatment or a split. Three units
    do not share setup cost, so cost per experiment is higher, not
    lower, than bpu/14's.
  - A single post budgets to 5,000-5,600 words, and the compression
    falls on the FTB sessions 051-052 specification-recovery arc, which
    is the most novel process material in the range.
  - The range mostly OPENS technical debt (#78-#84) rather than closing
    it, so there is no closure spine equivalent to bpu/14's 15 closures.
  - Three posts was rejected because RAS alone closes nothing a reader
    needs a post to learn, and because RAS finishes into FTB inside
    session 051 while session 052 exists only because of session 051.

Outcome: bpu/15 at 4,484 words and bpu/16 at 4,184, both inside the
band with margin. The split is the right precedent for a multi-unit
range.

Both are catch-up posts. Latest PA session at drafting time is 069 (068
by the supplied PROJECT_STATUS); the ranges close at 053 and 055. TD
status rolled back to end-of-range for both, with the required note
above each table. Session-063 and session-064 annotations were stripped
from the TD #84 entry, which is the only in-range item carrying them.

### Thematic clusters (Step 3)

bpu/15:
  - Two units, two amounts of document work before RTL.
  - The RAS empty/valid defect and the invariant that decided it.
  - A repair operation named after the wrong thing.
  - The reconciliation round (BP-064).
  - Building against a document that had been checked.
  - Two design points reopened, and the entry width.
  - The FTB testbench.

bpu/16:
  - Why a complete module was reopened.
  - What the original testbench could not reach.
  - The testbench that passed and was abandoned.
  - One definition (BP-071).
  - Neither file had both (BP-072, BUG-005).
  - A reference that shared the geometry (BP-073).
  - The definition becomes the project's own (section 6 capture, BP-074).

### Artifacts (Step 4)

bpu/15:
  - RAS: ras.sv single self-contained module; BOS sentinel re-base,
    w_alloc = (w_tosw == bos) ? (w_tosw + 1) : w_tosw, usable depth 15
    of 16; rep_push split on registered p2 op, TOSR-only re-expose for
    undo-pop. bp_defines_pkg.sv RAS block replaced (16/32/4,
    RAS_PTR_BITS=4, RAS_COMMIT_PTR_BITS=5); authorized tb_bp_pkg.sv
    6->4-bit literal fix. sim_ras 79/79 then 87/0.
  - FTB: bp_defines_pkg FTB block rewritten (five missing semicolons,
    duplicate FETCH_BLOCK_BYTES, FTB_TAG_BITS derived from the 64-byte
    fetch block rather than the 32-byte FTB block — the collapse
    ftb_decisions.md 2.3 bans). ftb_array pure RAM, ftb_plru resettable
    flops (3584), ftb_cntrl all logic, ftb structural top. Shared
    read-port borrow with prediction self-bubble. conf redefined to
    bimodal direction, always_taken deleted, saturated-endpoint fast
    path. Position sourced and sunk (FTB-4). Widths 108/432 -> logical
    108 / RAM 107 -> logical 106/424, RAM 105/420. sim_ftb 99/0.

bpu/16:
  - bp_history.sv module-owned pointer, rollback by checkpoint index
    (BP-069). Single fold definition, three geometry defects fixed,
    helpers widened 32b->64b for the SC H=W=64 case (BP-071).
    Increment-oriented re-orientation plus POST-advance checkpoint with
    recompute anchor ckpt-1 (BP-072). tb_bp_history rewritten: 13 cases,
    19,224 golden fold comparisons. Three committed literals 0xE5, 0x9,
    0xC000_0000_0000_0000 (BP-073). bp_history_decisions.md section 6
    canonical fold definition; sections 6-10 renumbered 7-11 (BP-074).
    33/33 targets.

### Friction / methodology events (Step 6)

Filtered by the artifact-only ruling. What survived into bpu/15:
  - PA did not read bp_defines_pkg.sv before writing BP-062 -> IA stop
    -> prompt rewritten to replace the block in full.
  - IA edited outside the RESULTS markers in BP-063 -> per-task
    Constraints line added.
  - That rule collided with the Model Reporting rule -> explicit
    CLAUDE.md exception added under Experiment File Rules.
  - PA's emptiness-test recommendation, retracted by the IA.
  - Session-051 FTB material on the rejected structural model -> session
    052 regeneration.
  - Target widths derivable throughout, ruled only when forced ->
    FTB-1 / IC-FTB-08 closed, ftb_decisions.md 4.4 corrected.
  - BP-066a/066b revising ftb.sv after BP-067 -> record drift.
  - PROJECT_STATUS edited by the IA under prompt authorization ->
    architect ruled it stays per-prompt, not a CLAUDE.md rule.

What survived into bpu/16:
  - Decisions-vs-interfaces checkpoint contradiction reported by BP-069.
  - BP-070 abandoned rather than delivered, with both corrections named.
  - BP-072 stopped on a false premise with port, git and doc evidence.
  - BP-074 reported the stale section-10 line rather than correcting it,
    under do-not-self-heal; architect applied the reword.
  - The PA's three errors, all of one shape: an assertion about an
    artifact's state written without reading the artifact.

Excluded by ruling: the 2026-06-23 outage, the session-050 mid-session
PA model switch, all trend narrative and supervision-cost claims from
the five Postmortem Records, and the fabricated-filename item.

### Technical Debt Referenced

  - bpu/15 table: #78, #79, #80, #81. All opened in range, none closed.
    This is the opposite character to bpu/14's 15 closures and is noted
    as such in the post's framing.
  - bpu/16 table: #74 (bp_history part closed), #82, #83, #84, #69, #70.
  - TD anchor ids: not assigned. Prose references are "TD #NN" with no
    link, per current rule.

### PA / IA split (Step 7)

  - IA, bpu/15: four stops (stale params, out-of-manifest file, two RAS
    defects). Two analytical contributions — the BP-063 retraction on
    the monotonic-TOSW invariant, and the BP-066 read-port borrow
    decision. Three unprompted reports: the broken FTB parameter block,
    the position field with no producer, the stale FTB_WAYS in the docs.
    Failure mode: followed a document LABEL rather than a document rule
    (IC-RAS-11 "push"), where the rest of the document supported the
    correct reading.
  - IA, bpu/16: four stops, and each stop is what produced the range's
    result. Abandoned a passing testbench rather than deliver one that
    encoded behavior as requirement. Stated the limit of its own
    external anchor — structural independence delivered, geometric
    independence not available, guarantee carried by the literals.
  - PA, both: sequencing held in both ranges, including an FTB ordering
    that survived two mid-build reopenings. Errors are preparation and
    analysis: writing tasks without reading the artifacts they assert
    about, and carrying a stale line through a renumber performed for
    consistency.
  - Jeff: every expected value in both ranges; both RAS defect fixes
    chosen against stated invariants with stated costs; the commit_rctr
    reversal from fix to deferral; TD #78/#79 filed by hand before
    BP-064 ran and TC-21's pinned values hand-verified; the FTB storage
    split and confidence redefine, both taken during the build; two
    authorized scope expansions in bpu/16; the decision to capture the
    fold geometry natively; retiring per-experiment tagging once the
    unit froze.

### Generalization (Step 8)

  - bpu/15: the FTB received three sessions of specification work and
    the RAS two documents written alongside the code, and both ended
    with their documents reconciled to the RTL as built. The errors in
    both sets were of a kind review cannot reach — a parameter stated
    consistently at the wrong value, a field with no producer, a repair
    labelled with the name of an operation it does not perform. Each is
    internally consistent. The document is a draft until something has
    been built against it, whatever its status field says. The post
    takes the position that the FTB's specification work was not wasted
    and gives three reasons; this is the harder of two framings and is
    flagged below.
  - bpu/16: four results that were true and did not mean what they
    appeared to mean — a 12-test bench that never filled the window, an
    18-case suite whose reference was written to match the design, two
    accurate records describing a state that never existed, and a
    three-way agreement where two of the three shared one definition.
    Each is a true claim about a comparison whose sides were not
    independent. Independence is a property to be checked, not inferred
    from different names in different files. The three committed
    literals are the practical form: worth less than a model in every
    respect except that they cannot co-move.

---

## Draft State

Both drafts: all required sections present — license header, file
metadata (six fields, closed set), navigation markers (empty), Abstract,
body, Experiment Summary, Technical Debt Referenced, References,
Attribution. Excluded-phrase and intensifier scans clean. One H1 each.
Body organized by problem, not by session. References sections carry
the no-references form.

### bpu/15
  - 4,484 words excluding tables; 5,107 including. Inside the bound with
    roughly 500 words of margin.
  - Abstract 254 words, single paragraph, stand-alone, no
    back-reference.
  - The RAS defect section is the longest in the post at roughly 600
    words, carried by the BP-063 retraction. Flagged below.
  - Title confirmed by the architect.

### bpu/16
  - 4,184 words excluding tables; 4,754 including.
  - Abstract 244 words.
  - BP-070 gets its own section. The handoff had compressed it to one
    line; the task file shows a complete passing testbench abandoned on
    principle, with both corrections proposed and the second taken by
    BP-071.
  - The generalization is built on BP-073's own statement of what it did
    not achieve, not on the anchor task succeeding.
  - Title is the PA's and is NOT confirmed.

### Known defect in both drafts
  - The DATE field in both metadata blocks reads 2026-09-04, copied from
    handoff-005 rather than set to the drafting date. Should be
    2026-09-22. Fix before publishing.

---

## Process Note: process-doc state

### Both edits proposed in handoff-005 are ALREADY APPLIED

BLOG_GENERATION_PROCESS.md as supplied this session (dated 2026-09-04)
contains both:
  1. Style / "Frustration in source material", which narrows the
     quoting exception as proposed.
  2. Process Summary / "What the PA reads directly, and what must be
     supplied", which states the read-directly / supply-the-results
     input rule.

handoff-005's Process Note and its second Open Question are therefore
stale. This session treated both as applied and worked to them; the
input rule was exercised and confirmed working. Confirm the applied text
is the ruling and both close.

### Findings on the process doc, not yet decided

  1. Step numbering. The Step-by-Step Process ends at Step 9. This
     handoff and handoff-005 both track ten steps with Step 10 retired
     per handoff-004. Consistent in intent, mismatched in the document.
  2. License header template. Line 104 reads
     `<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->`
     with no closing angle bracket. PROJECT_CORE.md and
     PROJECT_STATUS.md have it correct; the blog template does not, and
     both drafts this session inherited it, as bpu/14 did. Every
     published post carries it until the template is fixed.
  3. TD notation. The "Technical debt referenced" section writes the
     in-prose form as `TD# N`; practice and both drafts use `TD #NN`.
     The Terminology consistency rule wants one canonical form.
  4. Experiment count guidance. The doc's 2-8 reference range has now
     been exceeded by every recent post (21, 10, 6). The split decision
     recorded above is the useful rule and could be stated: a range
     spanning more than one unit costs more per experiment than a range
     within one unit, and should be split on unit boundaries before it
     is compressed.

---

## Open Questions / Decisions Pending

Resolved this session (recorded for the record):
  - bpu/14 closed and published outside a session. Its four handoff-005
    review items are moot. CLOSED.
  - Range split: two posts, 050-053 and 054-055, not one and not three.
    CLOSED.
  - PA postmortem material: include only where it changed an artifact.
    CLOSED. Applied to both drafts.
  - Session-050 mid-session PA model switch: omit. CLOSED.
  - 2026-06-23 outage: omit. CLOSED.
  - Fabricated-filename item: dropped, changed no design artifact.
    CLOSED for the post; source record still questionable.
  - External reference removal. The architect directed that the external
    open-source design be removed from bpu/15, on the grounds that it
    was one of many designs surveyed and was not copied. Applied: five
    passages reworded, the References entry removed, target widths
    re-derived from ISA reach directly, and the fallthrough-error ruling
    restated on its own terms with its restore guard. bpu/16 was written
    the same way from the start and names no external design; handoff-056's
    own framing — that a citation to a living external repo was never a
    real spec — carried the point without a name. CLOSED, and it should
    be treated as a standing rule for future posts.
  - bpu/15 title. CLOSED.

Still open:
  - bpu/16 title. "External Anchors: When a Proof and Its Reference
    Share the Same Error" is the PA's choice and was not put to the
    architect. Confirm or replace.
  - bpu/15 generalization stance. The closing section argues the FTB's
    specification work was not wasted and gives three reasons. The
    softer alternative reports the sequence and draws no conclusion.
    Changing it is the last paragraph of that section only.
  - bpu/15 section balance. The RAS defect section is the longest in the
    post. If the two units should be more evenly weighted, that is where
    the length is.
  - DATE field 2026-09-04 in both drafts. Fix to the publication date.
  - Process-doc findings 1-4 above. Decide and apply.

Carry-over source hygiene (not blocking any post):
  - session_handoff-054 asserts BP-069 and BP-071 both landed clean.
    False. PROJECT_STATUS supersedes it via BUG-005. handoff-056 lists
    the correction as optional; still not done.
  - session_handoff-054 Postmortem item 1 (fabricated file) is
    questionable — see Source reliability flags.
  - session_handoff-050 omits BP-055 and TD #72 from its own record.
    Carried from handoff-005. Unreconciled.
  - TD #44 open/closed drift, carried from handoff-004 and set aside
    twice. Unreconciled.
  - pa_session_map.md off-by-ones. The architect has stated the map is
    not a planning document, so this is optional.

---

## Next Session (006)

Two drafts are complete and unreviewed. The next blog-generation session
either closes the open items above and publishes both, or starts bpu/17
if the architect publishes them outside a session, as happened with
bpu/14.

Next post scoping:
  - The range begins at session-056. session_handoff-056 sets the
    direction plainly: SC is the agreed next unit, and it is greenfield.
    It has no decisions document and no interfaces document, so the
    first SC session is architectural, not implementation. Known SC
    facts are scattered across bp_cluster.md and PROJECT_STATUS and are
    listed in handoff-056's SC section: five pure counter tables with no
    tag bits, the index/IMLI split, s3 with SC as the final override in
    the chain, ST0 with no history, ST4 as the loop-counter table, and
    ST1-ST3 consuming folds whose geometry bpu/16's range made
    canonical, including the H=W=64 case. G7 (threshold) and the update
    rule are unspecified in any project document.
  - That shape suggests an SC arc of specification-then-build, which is
    the same two-phase structure bpu/15 covered for the FTB. If it runs
    that way, the bpu/15 generalization is directly continued and should
    not simply be restated.
  - The current PA session is 069 by handoff-005's account, 068 by the
    supplied PROJECT_STATUS. PROJECT_STATUS carries narrative sections
    for sessions 061-068 and BP references to BP-109, which suggests SC
    occupies roughly 056-060 and cluster integration follows. This is
    inference from the status file, not confirmed — set the boundary
    from the handoffs.
  - bp_cluster integration is the larger arc after SC and is where a
    long list of deferred items land: the FTB flush protocol, the
    confidence-versus-TAGE/SC metadata interaction, update-channel
    arbitration, the FTQ round trip, TD #69/#70 rollback recompute, and
    TD #84's end-to-end fold check. Both of this session's posts point
    at it. It is likely to be large enough to need the same split
    treatment recorded above.

Inputs to request for the next post:
  - session_handoff-056 (already supplied) through the handoff that
    closes the chosen range.
  - The completed experiment files for the range, header block plus
    RESULTS:START to end. PA sessions can be read directly.
  - A current PROJECT_STATUS.md and CLOSED_TECH_DEBT.md if either has
    moved past 2026-08-22.
  - Whichever of bpu/15 and bpu/16 is published, as the structural
    template.

Process:
  - Confirm the two handoff-005 edits are closed as applied.
  - Decide process-doc findings 1-4 before the next drafting session
    relies on any of them. Finding 2, the license header template, is
    the one that reaches published output.
