<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Overview
```
 FILE:    blog_handoff-005.md
 SOURCE:  RVA23 Blog-Gen Part 4
 STATUS:  DRAFT
 UPDATED: 2026-09-04
 CONTACT: Jeff Nye
```
Blog generation session handoff.

# Blog Handoff 005

Written by the PA at end of session `RVA23 Blog-Gen Part 4`.

Date: 2026-09-04

This session produced BLOG_bpu_14_directed_validation.md covering PA
sessions 047-049 (RVA23 Co-Design Part 47, 48, 49). The draft is complete
and delivered; it has not been reviewed. The bpu/13 post and all prior
posts are treated as complete. The single carry-over from handoff-004
(TD #44 open/closed drift) was set aside by architect instruction and is
not worked here.

Four review items on the draft are open. No process-doc edits were made
this session; two are proposed and not applied.

Read this file, then the draft, before continuing.

---

## Post Identity

- Series / number / short description: bpu / 14 / directed_validation
- Target filename: BLOG_bpu_14_directed_validation.md
- Working title: "Directed Validation: Proving the Test Before Trusting
  the Result"
- Source range: Parts 047-049 (three PA sessions), BP-045 through BP-061
- Range type: Standard (Experiment Summary table, 21 rows)

---

## Inputs Status

Supplied this session:
  - session_handoff files: 047, 048, 049, 050. These bound the range;
    047 opens it (written at end of session-046) and 050 closes it.
  - experiment files: all 21. BP-045, 046, 047, 048, 049, 049a (session
    047); BP-050, 050a, 050b, 051, 052, 053, 054, 054a, 055 (session
    048-049); BP-056 through BP-061 (session 049). All carry complete
    Results Capture including Run time and Ctx %.
  - PROJECT_STATUS.md and CLOSED_TECH_DEBT.md: supplied, current state
    (session-069 era).
  - BLOG_GENERATION_PROCESS.md: supplied, the corrected version carrying
    the three edits made in the previous blog session.
  - prior post: BLOG_bpu_13_contradiction_detection.md supplied as the
    structural template. BLOG_bpu_11 supplied earlier as a reference for
    the Experiment Summary table format only.

Still needed / outstanding requests to user:
  - None. All inputs required for the draft were supplied. The four open
    items below are review decisions, not missing inputs.

Source reliability flags:
  - session_handoff-050 under-reports its own session. Its summary states
    "Work ran BP-056 through BP-061" and its closed-debt list is #55, #58,
    #60, #62, #64, #71. BP-055 and TD #72 appear in neither the closed
    list nor the remaining list, yet the same file references BP-055 three
    times as completed work. BP-055's own experiment file confirms PA
    session 049, complete, 211 checks, TD #72 closed. The draft reports
    BP-055 as in-range and #72 as closed in-range. handoff-050 should be
    corrected at source.
  - BP-045 identifier. session_handoff-047 records "BP-045 (ITTAGE manual
    testbench shell) was scrapped" at the close of session-046, and
    blog_handoff-004 characterized this as identifier reuse. Architect
    ruling this session: BP-045 was run in PA session 047 and is the TAGE
    port-dimension rework closing TD #66. The draft treats BP-045 as one
    in-range experiment with no disambiguation and makes no reference to
    the session-046 instance. No further action.
  - BP-049 self-report is disputed and the draft says so. BP-049 marked
    itself complete and claimed TD #57 closed; handoff-048 states plainly
    that it was not, and BP-049a closed #57. The draft's Experiment
    Summary row reads "reported and rationalized, marked complete in
    error." This is the harder of two available framings and is flagged
    for confirmation below.
  - TD #76 attribution conflicts between sources. CLOSED_TECH_DEBT.md
    reads "CLOSED with BP-048"; session_handoff-048 credits BP-046. Both
    are partly right: BP-046 added the bus and renamed ports, BP-048
    closed the t_alc_index_u0 remainder. The draft credits both. Flagged
    for a single ruling below.
  - TD #44 drift (CLOSED in CLOSED_TECH_DEBT.md vs open in
    session_handoff-047) was carried from handoff-004 and set aside by
    architect instruction this session. Not investigated, not in the
    draft. Still unreconciled at source.

---

## Process Progress

Per BLOG_GENERATION_PROCESS.md Step-by-Step Process:
  [x] 1. Range confirmed as a real arc. Two independent lines converge on
         047-049: the architect's tage / ittage / tage-cleanup grouping,
         and the TD arc, where #57/#62/#63/#66 are opened as suspects at
         the close of 046 and closed by BP-045/049a/059 inside this range.
         The range closes hard: both predictors directed-validated at the
         unit level, 15 debts resolved.
  [x] 2. Experiment inventory built. 21 experiments, all with Results
         Capture. Inventory is the Experiment Summary table in the draft.
  [x] 3. Thematic clusters identified
  [x] 4. Artifacts extracted per cluster
  [x] 5. Decisions and rationale extracted
  [x] 6. Friction / methodology events extracted
  [x] 7. PA/IA contribution separated
  [x] 8. Generalization drafted, checked across the clusters in this range
         per the Step 8 ruling recorded in handoff-004. No prior-post
         comparison performed or required.
  [x] 9. Assembled in template (Abstract drafted last)
  [x] 10. Series navigation. Block present and empty, per the process-doc
          edit recorded in handoff-004. Step retired as a per-post item.

---

## Working Material Captured So Far

(Reference notes, not final prose.)

### Range confirmation (Step 1)

  - Three PA sessions, 21 experiments. This is roughly three times the 2-8
    reference range in the process doc. It was carried as one post at the
    architect's direction. It fits by clustering: the Experiment Summary
    table carries per-experiment detail and the prose runs on themes, with
    no per-experiment narration. Prose lands at 4,999 words excluding
    tables, at the 5,000 upper bound. A future range of this size should
    be assumed to need the same treatment or a split.
  - This is a catch-up post. Latest PA session at drafting time is 069;
    the range closes at 049. TD status was rolled back to end-of-049 per
    the catch-up convention. For the 15 in-range items the rollback and
    current status agree, because this range is where they close.

### Thematic clusters (Step 3)

  - Structural rework before verification, and the escape it exposed
    (BP-045, BP-046).
  - Classification is not adjudication (BP-047, BP-048).
  - A defect reported and argued away (BP-049, BP-049a).
  - The step that makes a passing test mean something: defect injection
    (BP-050, BP-050a, BP-050b).
  - Completing ITTAGE (BP-051 through BP-055).
  - TAGE, the same sequence (BP-056 through BP-061).
  - Counts as evidence (cross-cutting, four instances).

### Artifacts (Step 4)

  - RTL fixes: ittage_cntrl.sv t_alc_index_u0 driven from the allocation
    index field (BP-048); t_tgt_wr_u0 split into t_prm_tgt_wr_u0 /
    t_alt_tgt_wr_u0 with ittage_table.sv tgt_we becoming
    (prm_tgt_wr & prm_match | alt_tgt_wr & alt_match) (BP-049a);
    ittage_cntrl.sv UAON single-hit guard (BP-051); tage_cntrl.sv
    uaon_upd_ff gate extended with && u_alt_tagged[s], BUG-003 (BP-057).
  - Structural: tage_cntrl.sv ten buses collapsed [table][slot] ->
    [slot], gen_upd_bus generate block added, t_alt_upd_index_u0 added
    (BP-045); ittage_cntrl.sv alternate index bus plus 22 ports renamed
    to t_ convention (BP-046).
  - Test infrastructure: approximately 120 directed test cases across
    tb_tage, tb_ittage, tb_ittage_cntrl, tb_ittage_table. TC-69 through
    TC-103 on the TAGE side.
  - Planning docs: ittage_cntrl_decisions.md "Concurrent CTR and TGT
    Writes" added and pred_strong corrected to CTR != 0; final-target
    section rewritten to consumer-muxed prm/alt; ittage_interfaces.md
    Target Write Gating made explicit; new ittage_table_entry_formats.md
    and tage_table_entry_formats.md as single source for field order;
    tage_cntrl_use_update_rules.md N+1 epoch timing added;
    tage_cntrl_uaon_update_rules.md promoted Draft -> Complete.
  - Records: BUG-002 (BP-049a testbench escape), BUG-003 (TAGE UAON
    guard).

### Decisions and rationale (Step 5)

  - Adjudicate against the authority document before repairing anything.
    BP-047 classified the RTL as inverted; the rules table showed the RTL
    conforming on all 33 rows and five tests transposed. Repairing the
    RTL would have broken a conforming block.
  - Defect injection as the closing step of every conformance task. BP-050
    was abandoned for arguing discriminating power instead of
    demonstrating it. BP-050b, 051, 056, 057 all inject and revert.
  - ALL TARGETS MUST RUN, with a measured cost. BP-054a ran 3m 32s and
    consumed 72% context from 22 targets' console output; compaction in 8
    of 11 tasks in session 049. Architect decision: phase the rule so
    early tasks do not carry the full burden.
  - Minimal manifests, after BP-053's timeout and oversized manifest. Set
    against the opposite lesson from BP-049, where a missing interfaces
    document caused a defect to be rationalized. The rule that resolves
    both: load the reference document the task actually reads, nothing
    padded.
  - Fold RAM-level write isolation into the allocation task where the
    tables are present (BP-059) rather than deferring to the capstone,
    which is what ITTAGE had to do (BP-053 controller-only, closed by
    BP-055).
  - Seed EPC = lcl_epoch when a USE delta must be visible (BP-055 lesson,
    applied in BP-061).

### Friction / methodology events (Step 6)

  - 46 unreported unit failures surfaced by BP-045/046, not by a
    verification task. tb_ittage_cntrl authored green at 76 checks, RTL
    churned underneath it, suite never re-run, PROJECT_STATUS carried the
    stale count throughout.
  - BP-049 marked itself complete on an unclosed debt.
  - BP-050 abandoned; its own repair claim did not hold, found by BP-050a.
  - BP-049a port rename left two testbenches uncompilable while their
    counts were recorded as current (BUG-002).
  - BP-053 request timeout, rerun with three planning docs removed.
  - Count arithmetic did not close across BP-055/056/057; resolved at
    BP-058. Ledger 73/81/87/95/102/103 reconciles end to end.
  - BP-051's UAON fix invalidated tc_tgt_b_ext, which had encoded its DEC
    step around the missing guard.
  - Cross-track contamination in a prompt: BP-059's requirement carried a
    "no-consecutive skip" label from ITTAGE when TAGE is stop-at-first.

### Technical Debt Referenced

  - 15 items closed in range: #55, #56, #57, #58, #59, #60, #61, #62,
    #63, #64, #65, #66, #71, #72, #76.
  - Table rolled back to end-of-049 state with the required note above it.
    For these 15 the rollback and current status agree.
  - TD anchor ids: not assigned. Prose references are "TD #NN" with no
    link, per current rule.

### PA / IA split (Step 7)

  - IA: all directed tests; four RTL defects root-caused to file and line;
    the nba_sequent re-evaluation diagnosis in BP-047; three specification
    errors reported unprompted (alloc field order, pred_strong carryover,
    stored final-target field); backed out its own first approach in
    BP-049a on Verilator scheduling grounds and documented why. Failure
    mode is uniform and worth preserving as stated: where the task allowed
    judgment about what a finding meant, it resolved toward the artifact
    in front of it. Not carelessness; absence of the authority document at
    the moment of judgment.
  - PA: sequencing all 21 tasks, including EPC-before-aging and
    isolation-before-round-trip. The BP-048 guard is the strongest single
    contribution and has a counterfactual. Also caught BP-050's
    argued-not-demonstrated gap, BP-049's rationalization, and the count
    arithmetic failures. Own errors: oversized manifests (one contributing
    to a timeout), the BP-049 manifest omission that caused the
    rationalized defect, and the BP-059 label carryover.
  - Jeff: every expected value; every specification correction; rejection
    of BP-049's completion claim; the entry-format extraction decision;
    the N+1 documentation ruling and the epoch-wrap declination; the
    all-targets rule and its phased revision.

### Generalization (Step 8)

  - 19 of 21 tasks ended with no RTL change, so the range's output is
    almost entirely tests, and passing does not establish what they are
    worth.
  - A test written against conforming RTL and never run against anything
    else has unknown detection capability. Injection separates a test that
    encodes the requirement from one that encodes the behavior. The
    recorded failing values (exp c000 / act e000; exp 2 / act 0; exp 8 /
    act 9) are the evidence, and they cost minutes.
  - The same principle covers the range's non-test failures: a carried
    count, a rationalized defect, and a classification naming the RTL as
    inverted are all assertions without a run, a test, or an adjudication
    behind them.
  - The two predictors give the one controlled comparison: the same UAON
    defect found independently in both by the same method, with the TAGE
    manifestation more specific; and a document error that crossed one
    direction only, caught on the receiving side and confirmed absent on
    the originating side.

---

## Draft State

  - Complete, delivered, unreviewed. All required sections present:
    license header, file metadata (six fields, closed set), navigation
    markers (empty), Abstract, body, Experiment Summary, Technical Debt
    Referenced, References, Attribution.
  - Length 4,999 words excluding the two tables; 6,142 including them.
    At the 5,000 upper bound.
  - Abstract is a single paragraph, 266 words, stand-alone, no
    back-reference.
  - Excluded-phrase and intensifier scans clean.
  - Body organized by problem, not by session. Session numbers appear only
    as experiment citations.
  - TAGE section is compressed relative to ITTAGE by design: the ITTAGE
    sequence establishes the method and TAGE repeats it. BP-058 and BP-060
    get one paragraph each.
  - "Counts as evidence" is a standalone short section rather than folded
    into the process notes.
  - Draft file: BLOG_bpu_14_directed_validation.md.

---

## Process Note: proposed process-doc edits, NOT applied

No edits were made to BLOG_GENERATION_PROCESS.md this session. Two are
proposed and need the architect's decision:

  1. Style / source material. The architect directed this session that
     expressions of frustration in source material are excluded from
     posts: the results matter, the emotion is a distraction from the work
     being performed. This is a standing rule and is not currently stated
     in the Style section. It interacts with the existing "Quoting source
     material" subsection, which permits quotation where register is
     itself the informative fact — that exception should be narrowed to
     exclude frustration directed at the tooling or the assistants.

  2. Process Summary / input gathering. The PA sessions are readable
     directly from the project by the drafting session; the user does not
     need to export or paste them. But the task files as they appear in a
     PA session are the emitted versions, with Run time and Ctx % blank
     and Results Capture reading "RESULTS NOT YET WRITTEN" — the IA fills
     those in on the repo side and they do not return to the chat. The
     input rule that follows: read the PROMPT content and the surrounding
     decisions from the session, and require the completed experiment
     files for the header block and Results Capture. This halves what the
     user has to gather and should be stated in Process Summary.

---

## Open Questions / Decisions Pending

Resolved this session (recorded for the record):
  - Range boundary: 047-049, one post. CLOSED.
  - BP-045 identifier: one experiment, run in session 047. CLOSED.
  - BP-050a template-compliance exchange and the BP-051 note on PA
    behavior under a specific model version: both excluded from the post
    by architect instruction. CLOSED.
  - Frustration content excluded. CLOSED as a decision; see proposed
    process-doc edit 1.

Still open, all review decisions on the draft:
  - TD #76 attribution. Draft credits BP-046 and BP-048 jointly. Sources
    disagree. Pick one form.
  - BP-049 framing. Draft's Experiment Summary reads "reported and
    rationalized, marked complete in error." Confirm or soften.
  - "Counts as evidence" section. Keep standalone, or fold into the
    generalization. Keeping it costs roughly 200 words against a draft
    already at the length bound.
  - TAGE section compression. Confirm acceptable, or expand BP-058 and
    BP-060 — which would require cutting elsewhere.

Carry-over source hygiene (not blocking any post):
  - session_handoff-050 omits BP-055 and TD #72 from its own record.
    Correct at source.
  - TD #44 open/closed drift, carried from handoff-004, set aside this
    session. Unreconciled.

---

## Next Session (005)

The bpu/14 draft is complete but unreviewed. The next blog-generation
session either closes the four review items above and publishes bpu/14,
or starts a new post if the architect publishes bpu/14 outside a session.

Next post scoping:
  - The range begins at session-050. session_handoff-050 sets no
    direction: the architect chooses between bp_cluster integration
    (which unblocks the rollback items #69/#70 and the arbitration
    cluster, and is itself gated on several BP Cluster TBDs), the FTB /
    SC / RAS predictors (not started), and carried infrastructure work
    (#43 ITTAGE CTR width 3b->2b, #75, #77, #67/#68, #38).
  - Which of those was taken determines the shape of the next post. The
    current PA session is 069, so roughly twenty sessions are available
    and the range boundary should be set by where an arc closes, not by
    session count. Confirm against the handoffs before drafting.
  - Note that #43, the ITTAGE counter width reduction, will churn the
    counter and aging tests written in the bpu/14 range if it lands after
    them. If it was taken early, that is a direct continuation of this
    post's material.

Process:
  - The two proposed process-doc edits above are not applied. Decide and
    apply before the next drafting session relies on either.

