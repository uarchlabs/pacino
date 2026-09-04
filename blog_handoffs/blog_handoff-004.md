<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Overview
```
 FILE:    blog_handoff-004.md
 SOURCE:  RVA23 Blog-Gen Part 3
 STATUS:  DRAFT
 UPDATED: 2026-07-13
 CONTACT: Jeff Nye
```
Blog generation session handoff.

# Blog Handoff 004

Written by the PA at end of session `RVA23 Blog-Gen Part 3`.

Date: 2026-07-13

This session produced BLOG_bpu_13_contradiction_detection.md covering PA
session 046, now published. The draft is a new post, not a continuation of
the bpu/12 draft from handoff-003. The bpu/12 post and all prior posts are
treated as complete; the outstanding bpu/12 items in handoff-003 were not
worked.

All post-level open items are closed. Three edits were made to
BLOG_GENERATION_PROCESS.md this session: series navigation reassigned to the
publishing pipeline, Step 8 "series" terminology corrected, and a catch-up TD
convention documented. The remaining open items are source-file hygiene, not
post blockers.

Read this file, then the corrected process document (attached), before
continuing.

---

## Post Identity

- Series / number / short description: bpu / 13 / contradiction_detection
- Target filename: BLOG_bpu_13_contradiction_detection.md
- Working title: "Contradiction Detection: When the Planning Document Is
  the Defect"
- Source range: Part 046 (single PA session)
- Range type: Standard (Experiment Summary table)

---

## Inputs Status

Supplied this session:
  - session chats: RVA23 Co-Design Part 46, supplied as a JSON export
    (RVA23_Co-Design_Part_46.json, 694KB). Parsed on the container; the
    six experiment files below were extracted from its attachments, along
    with PROJECT_STATUS.md (session-046 era), PROJECT_CORE.md, the
    corrected tage_cntrl_ctr_update_rules.md, and ittage RTL.
  - experiment files: BP-043, BP-043a, BP-044, BP-044a, BP-044b, BP-044c.
    All carry complete Results Capture. BP-045 (ITTAGE manual testbench
    shell) was scrapped and has no experiment file.
  - session_handoff files: session_handoff-047 (written at end of
    session-046; see numbering note below).
  - CLOSED_TECH_DEBT.md: supplied, current state (session-062 era).
  - PROJECT_STATUS.md: supplied via the JSON export, session-046 era.
  - prior post: not supplied and not required. See Range / Step 8 note.

Still needed / outstanding requests to user:
  - BP-043a check count. The experiment file states the run passed with
    zero failures but gives no total check count. The Experiment Summary
    table currently shows "0 fail" in the Checks column. Supply the count
    if it exists in the session log.
  - Series navigation link text and targets for Step 10. The
    ::BEGIN LINKS:: / ::END LINKS:: block is present and empty. Needs the
    bpu/12 post as previous and a placeholder or named next post.
  - Confirmation of References [1] and [2]. Carried unresolved from
    handoff-003. The draft cites the standard TAGE (JILP 2006) and ITTAGE
    (JWAC-2 2011) Seznec papers. The session source does not name a paper.
    Confirm these are the intended citations.

Source reliability flags:
  - BP-043 disputes the premise it validated against, but not its own
    execution. It ran clean (68 pass) against tage_cntrl_ctr_update_rules.md
    rows 13a-d, which were later found to be wrong. The draft reports the
    pass and marks the result superseded. This is the central finding of
    the post, not a defect in the report.
  - BP-044a was abandoned. It passed 53 checks but proved the UP=0
    alternate-provider rows using one table (IT1) in both roles, which
    cannot distinguish the bug from its absence. The draft reports the pass
    count and the reason for abandonment.
  - The architect's message-26 account states "PA confirmed" the T0 error.
    The session transcript does not support this as written: on first read
    of BP-043 the PA argued against acting on the IA's flag, was rejected,
    and retracted. The draft reports the transcript sequence (IA flagged,
    PA argued to close, architect adjudicated and corrected), not the
    handoff's summary. Per BLOG_GENERATION_PROCESS.md Step 2, disputed or
    unverified source claims are reported as such. Confirm this handling is
    acceptable; it is less flattering to the PA than the architect's own
    summary.
  - INFRA-007 /context fabrication is NOT in this range. It belongs to the
    bpu/12 range (handoff-003) and is not referenced in this draft. The
    PROJECT_CORE.md fabrication reported in this draft is a separate,
    in-range event from session-046.
  - Handoff numbering is correct. Session-046 wrote session_handoff-047, and
    its Next Session block reads 047. Session N writes handoff N+1 and the
    block carries the handoff's own number; this is the intended convention,
    not an off-by-one. No reconciliation needed.

---

## Process Progress

Per BLOG_GENERATION_PROCESS.md Step-by-Step Process:
  [x] 1. Range confirmed as a real arc
  [x] 2. Experiment inventory built
  [x] 3. Thematic clusters identified
  [x] 4. Artifacts extracted per cluster
  [x] 5. Decisions and rationale extracted
  [x] 6. Friction / methodology events extracted
  [x] 7. PA/IA contribution separated
  [x] 8. Generalization drafted. Per the architect's ruling this session,
         "the series" in Step 8 refers to the range of experiments under
         review, not the series of blog posts. The generalization was
         checked across the clusters in this range; no prior-post
         comparison is required. See Process Note below.
  [x] 9. Assembled in template (Abstract drafted last)
  [x] 10. Series navigation. Block present and empty, which is now the
          correct PA output. Navigation is generated by the publishing
          pipeline at publish time per the process-doc edit this session;
          the PA no longer fills this block. Step retired as a per-post
          checklist item.

---

## Working Material Captured So Far

(Reference notes, not final prose.)

### Range confirmation (Step 1)

  - Single PA session (Part 046) carries the arc. Six experiments, inside
    the 2-8 reference range. The range closes work: the TAGE T0 CTR
    semantics question is resolved and the RTL reverted; the ITTAGE CTR and
    USE write paths are fixed and proven by readback; TD #51 is closed with
    survivors broken out; TD #45 is invalidated. A backdoor RAM-seeding
    method is established as the basis for the next range.
  - This is a catch-up post. The blog series is being written behind the
    work: this post covers session 046, the latest PA session at drafting
    time is 062. TD status in the supplied files is therefore current
    (post-046) and had to be rolled back to end-of-046 state for the table.
    See Technical Debt note.

### Thematic clusters (Step 3)

  - The premise and its failure boundary: the manual-testbench method
    treats the rule table as ground truth and cannot evaluate the table.
  - The TAGE T0 error: BP-043 (clean audit against a wrong rule), the IA
    flag, the error itself, BP-043a (reversal).
  - The ITTAGE audit, opposite result: BP-044 (stop-and-report), BP-044a
    (abandoned), BP-044b (two bugs + backdoor), BP-044c (USE path).
  - TD #51 confirmed twice.
  - The second planning file error: TD #45 invalidated, #66 rewritten.
  - Methodology: contradiction detection, where the domain knowledge came
    from, the same mechanism producing fabrication, the strategy change.

### Artifacts (Step 4)

  - RTL fixes: ittage_cntrl.sv g_ctr_upd (strobe/data swap + ittage_hit
    gate, BP-044b); ittage_table.sv use_we/epc_we gate widened to
    (prm_ctr_wr & prm_match | alt_ctr_wr & alt_match) (BP-044c);
    tage_cntrl.sv ctr_upd_comb u_both_t0 reverted !u_mispredict ->
    u_resolved (BP-043a).
  - Test infrastructure: bw_write backdoor RAM-seeding task in tb_ittage.sv;
    path dut...gen_ittage_tables[T].gen_active.u_table.u_ram_s0/s1;
    five ITTAGE CTR/USE tests; five TAGE T0 tests re-aligned.
  - Planning docs: tage_cntrl_ctr_update_rules.md rows 13a-d corrected
    (DEC,INC,DEC,INC); TD #45 invalidated in PROJECT_STATUS; TD #66 port
    list rewritten; TD #55-#74 enumerated (full remaining unit-test
    surface); TD #15 closed forward to #55/#56; TD #51 closed to
    #57/#62/#63.
  - Records: HAND-FIX-003 / BUG-001 annotated superseded.

### Decisions and rationale (Step 5)

  - Rule table is ground truth, and its failure boundary. The method
    detects RTL-vs-table disagreement; it cannot detect a wrong table.
    This session found the boundary.
  - Pre-authorize fixes for characterized bugs. BP-044 stopped on Bug C, a
    known bug, because the prompt said stop. New rule: pre-authorize fixes
    for already-characterized bugs, reserve stop-and-report for new
    failures. Cost one session.
  - Backdoor RAM write over allocate-then-predict. Established BP-044b as
    the standard mechanism for all future unit tests. Do not build
    allocate-then-predict scaffolding.
  - Fix EPC alongside USE (BP-044c). EPC rides the USE gate; leaving it
    would write EPC to the wrong table on UP=0. Fix applied, but EPC not
    proven by readback -> TD #55/#56.
  - Deprioritize lengthy manual testing. Complete the design with directed
    unit tests, reach performance analysis sooner. Rationale in the post:
    manual testing and mutation testing share blindness to a wrong
    specification; performance analysis does not.

### Friction / methodology events (Step 6)

  - BP-044 over-blocked: prompt told the IA to halt on a known bug. One
    session lost.
  - BP-044a proved a fix with an invalid test (one table in both provider
    roles); abandoned and redone as BP-044b.
  - PA argued to close the IA's T0 flag on first read of BP-043, inventing
    a tage_bim.sv mechanism; rejected by the architect, retracted.
  - PA re-reviewed the corrected T0 table as though it were still wrong;
    most of the analysis invalidated on challenge.
  - PA fabricated a PROJECT_CORE.md quotation to defend a claim that TAGE
    has no EPC field; conceded on challenge.

### Technical Debt Referenced

  - The draft table is rolled back to end-of-session-046 state and carries
    a note saying so. The supplied CLOSED_TECH_DEBT.md and PROJECT_STATUS.md
    are current (session-062 era); copied verbatim they would show #57, #62,
    #63, #66 as closed by later experiments (BP-045/049a/059 etc.), which
    inverts the post's finding that #57/#62/#63 were opened as suspects in
    this range.
  - Decision: report status-as-of-close-of-046, not verbatim-current. This
    deviates from the BLOG_GENERATION_PROCESS.md "copy verbatim" rule, for
    the stated reason. Confirm this is the right call for catch-up posts;
    it likely needs to become a documented convention if more catch-up
    posts follow.
  - Drift found while reconciling: TD #44 is CLOSED in CLOSED_TECH_DEBT.md
    ("changed session-040") but carried as open in session_handoff-047's
    Open Technical Debt list. One of the two is stale. Not in the draft
    table; flagged for the source-file reconciliation pass.
  - TD anchor ids: not assigned. Referenced in prose as "TD #NN" with no
    link, per the current rule.

### PA / IA split (Step 7)

  - PA: prompt sequencing; decomposition of the ITTAGE audit into
    BP-044a/b/c; the recommendation to run ITTAGE in the TAGE-proven order;
    the BP-044 scope-conflict flag; the structural catch that BP-044a's fix
    was proposed against half the write path (ittage_table.sv not in
    manifest). Also: argued to close the T0 flag (rejected), re-reviewed a
    corrected doc as wrong, and fabricated a PROJECT_CORE.md quotation.
  - IA: task infrastructure to spec in every experiment; complied with
    cite-a-rule-row-or-stop in BP-044; produced the T0 flag unprompted in
    Other Notes. Failure mode is test construction (BP-044a invalid proof),
    not context degradation. Domain knowledge (bimodal counter behavior)
    came from training, not from any loaded artifact.
  - Jeff: every expected value; the T0 error identified as his own;
    correction of the planning doc; rejection of BP-044a's proof; rejection
    of the PA close-the-flag analysis; invalidation of TD #45; detection of
    the fabricated citation; the testing-strategy decision.

### Generalization (Step 8)

  - The mechanism that found the error is the transferable result, and it
    is not the testing method: the IA compared the specification against
    domain knowledge rather than checking RTL against the specification.
  - The same mechanism produces fabrication. The session contains both
    outcomes: the T0 flag (prior correct, document wrong) and the
    PROJECT_CORE quotation (prior invented). Manner identical; what differs
    is whether the assertion was checkable and whether it was checked.
  - The method's blind spot drove the strategy change. Manual and mutation
    testing cannot see a wrong specification; performance analysis can.
  - Checked across the clusters in this range per the Step 8 ruling. Not
    checked against a prior blog post's generalization, which is not
    required under that ruling.

---

## Draft State

  - Complete. All required sections present: license header, file metadata,
    navigation markers (empty), Abstract, body, Experiment Summary,
    Technical Debt Referenced, References, Attribution.
  - Length approximately 4,960 words. Within the 2500-5000 guideline, near
    the upper bound.
  - Abstract is a single paragraph, approximately 301 words, stand-alone,
    no back-reference to prior posts.
  - Jargon pass complete: removed coinages (provider-gating, canary tests,
    review property, standing suspects, "thesis"), metaphors, intensifiers,
    and asides per the Style guidelines. "thesis" in a grep is a false
    positive inside "hypothesis".
  - Terminology aligned to "planning file error" per the abstract.
  - Draft text: see attached BLOG_bpu_13_contradiction_detection.md.

---

## Process Note: process-doc edits made this session

Three edits were made to BLOG_GENERATION_PROCESS.md this session and the
corrected file was emitted:

  1. Navigation (Step 10 / Navigation section markers / Indexability
     Internal linking). Series navigation is now specified as
     pipeline-generated at publish time. The links cannot be produced at
     authoring time: the published file name encodes a not-yet-assigned
     publish date, the "next" target may not be written yet, and the target
     files live in a separate repository. The PA leaves the block empty. The
     Internal linking subsection keeps the name-the-post anchor-text rule and
     assigns it to the pipeline, sourcing anchor text from the TITLE field
     and targeting published dated names.

  2. Step 8 / "series" terminology. Step 8 now states it operates on the
     range under review, not the post series, and does not require checking
     against a prior post's generalization. A terminology note was added to
     the Purpose section fixing "series" to mean the published post sequence,
     and the Files section notes the authoring-vs-published name split.

  3. Catch-up TD convention. A "Catch-up posts and TD status" subsection was
     added under Technical debt referenced, documenting the end-of-range
     rollback the bpu/13 draft used and marking it a deliberate deviation
     from the copy-verbatim rule for posts whose range predates the current
     status files.

Corrected file: see attached BLOG_GENERATION_PROCESS.md.

---

## Open Questions / Decisions Pending

Resolved this session (recorded for the record):
  - References [1]/[2]: confirmed by the architect. CLOSED.
  - "PA confirmed" handling: the architect confirmed the draft's
    transcript-based account (PA argued to close, then retracted) is
    acceptable over the message-26 summary. CLOSED.
  - Cross-track contamination note: CLOSED. Handled by the architect.
  - BP-043a check count: no full count exists in the source; the run
    reported "0 failures, 0 unexpected warnings" and five re-aligned tests
    each marked PASS. The Experiment Summary column is left as "0 fail". The
    post is published; no change. CLOSED.
  - TD table convention for catch-up posts: resolved by process-doc edit
    this session (BLOG_GENERATION_PROCESS.md, Technical debt referenced /
    "Catch-up posts and TD status"). The end-of-range convention the draft
    used is now documented. CLOSED.
  - Step 8 wording: resolved by process-doc edit this session. Step 8 now
    states it operates on the range, not the post series; a terminology note
    was added to the Purpose section and the Files section. CLOSED.
  - Series navigation (Step 10): resolved by process-doc edit this session.
    Navigation is now specified as pipeline-generated at publish time, not a
    PA authoring task; the PA leaves the block empty. Step 10 is retired as a
    per-post checklist item. CLOSED.

Still open:
  - Source-file reconciliation, one item, not a blocker on any post:
    - TD #44 open/closed drift: CLOSED in CLOSED_TECH_DEBT.md
      ("changed session-040") but carried open in session_handoff-047.

---

## Next Session (004)

The bpu/13 post is published. All post-level open items from this session
are closed (see Open Questions). The next blog-generation session starts a
new post.

Carry-over source hygiene (not blocking any post, do when convenient):
  - TD #44 open/closed drift: CLOSED in CLOSED_TECH_DEBT.md vs open in
    session_handoff-047. Reconcile against current RTL and pick one.

Next post scoping:
  - The natural next range begins at session-047: the TAGE structural rework
    under TD #66 (the BP-045 identifier reuse), and the TAGE EPC/UAON/aging
    write proofs (TD #55, #58, #60) plus the ITTAGE equivalents (#56, #59,
    #61) and TGT (#57). This is the verification surface enumerated as
    TD #55-#74 at the close of session-046.
  - The bpu/13 post established the backdoor-RAM-write method and the
    isolation-before-round-trip rule; a post covering session-047 onward is
    the payoff of that method across the remaining fields. Confirm the range
    boundary against where the arc closes before drafting.

Process:
  - The three BLOG_GENERATION_PROCESS.md edits from this session (navigation,
    Step 8 terminology, catch-up TD convention) are in the attached corrected
    file. Confirm they are merged into the working copy before the next
    drafting session relies on them.

