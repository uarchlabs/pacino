<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Overview
```
 FILE:    blog_handoff-003.md
 SOURCE:  RVA23 Blog-Gen Part 2
 STATUS:  DRAFT
 UPDATED: 2026-07-12
 CONTACT: Jeff Nye
```
Template for BLOG generation session handoff. Populate as needed.

# Blog Handoff 003

Written by the PA at end of session `RVA23 Blog-Gen Part 2`
(chat session name is unpadded; this handoff file's own NNN
numbering is a separate, zero-padded convention — see
BLOG_GENERATION_PROCESS.md Definitions).

Date: 2026-07-12

This session produced a complete draft of BLOG_bpu_12_manual_tbs.md
covering PA sessions 043-045. All Step-by-Step Process steps except
series navigation are complete. One process-document conflict was
identified and is being fixed by Jeff.

Read this file, then the current draft (attached), before continuing.

---

## Post Identity

- Series / number / short description: bpu / 12 / manual_tbs
- Target filename: BLOG_bpu_12_manual_tbs.md
- Working title: "Manual Testbenches: Removing the Agent from the
  Expected-Value Path"
- Source range: Part 043 to Part 045
- Range type: Standard (Experiment Summary table)

---

## Inputs Status

Supplied this session:
  - session chats: none supplied directly. The range was reconstructed
    from the handoff files and experiment files only.
  - experiment files: TB-001, TB-002, BP-040, BP-041, BP-042, BP-042a,
    BP-042b, INFRA-007
  - session_handoff files: 044, 045, 046 (see numbering flag below)
  - prior post: not supplied. BLOG_bpu_11 was not read this session.

Still needed / outstanding requests to user:
  - Prior post (BLOG_bpu_11_*.md) for Step 8. The generalization in the
    current draft was written without checking it against the prior
    post's generalization. This is the one Step-by-Step requirement that
    was not satisfied as written.
  - Confirmation of References [1] and [2]. The ITTAGE USE rules document
    contains a "Seznec deviation note" but the source material does not
    name the paper. The draft cites the standard TAGE (JILP 2006) and
    ITTAGE (JWAC-2 2011) papers. Verify these are the intended citations.
  - Check counts for BP-041 and INFRA-007 for the Experiment Summary
    table, if they exist in the session logs. Currently thin.
  - Series navigation link text and target for Step 10.

Source reliability flags:
  - BP-040 disputes its own results. Claude Code reported 76 PASS / 0 FAIL
    after making three RTL changes to ittage_cntrl.sv (Bug B, C, D). Jeff
    rejected the results; Bug C and Bug D reverse fixes recorded in BP-039
    (Bug 4 and Bug 2 respectively). TD #46 and TD #50 are explicitly not
    closable. The draft reports the pass count as the source states it and
    marks the experiment DISPUTED. The dispute is not resolved in the post.
  - BP-041 HAND-FIX-003 / BUG-001 was reverted in BP-043a, which is outside
    this range. The header note in BP-041 states the fix was a false fail
    caused by an error in the T0 CTR planning document. The draft reports
    both the fix and the reversal.
  - INFRA-007 Claude.ai Assessment claims Claude Code populated Ctx% = 19%
    from its own runtime. Jeff's annotation states this is wrong — the value
    was entered by hand via the interactive /context command. The draft
    reports the PA claim and the correction, and attributes the correction
    to Jeff.
  - Handoff numbering off-by-one. Two handoff files in the supplied set are
    both titled "Session Handoff 046". The first (dated 2026-05-31) covers
    session-044 and ends with "Next Session (045)"; it should be titled 045.
    The second (dated 2026-06-04) is correctly 046. The draft does not cite
    handoff numbers in prose, so this does not affect the post text, but the
    source files need correcting.
  - ho.md contains BP-042 twice, identical content. Treated as a paste
    artifact, counted once.
  - TB-002 header has no Status checkbox marked. Handoff-044 records it as
    complete. Draft treats it as complete.

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
  [~] 8. Generalization drafted — written, but NOT checked against the
         prior post's generalization. Prior post was not supplied.
  [x] 9. Assembled in template (Abstract drafted last)
  [ ] 10. Series navigation updated — ::BEGIN LINKS:: / ::END LINKS::
          block is present and empty.

---

## Working Material Captured So Far

(Reference notes, not final prose.)

### Thematic clusters (Step 3)

  - The failure that forced the change: BP-040
  - The three-layer split: TB-001, TB-002
  - The first rule-row test set: BP-041 (manual, session-044)
  - The assertion rollout and its cost: BP-042, BP-042a, BP-042b
  - Context capture: INFRA-007
  - Tooling and record-keeping: TOOLS step (session-045, PA task, no
    experiment file)

### Artifacts (Step 4)

  - Split: tb_tage_tasks.sv; utils.svh; tb_tage_manual_tasks.svh;
    tb_tage_manual.sv; tage_ram_entry_t (field 'use' renamed 'useful');
    Makefile targets sim_tage_tasks, sim_tage_manual;
    planning/testbenches/manual_tb_decisions.md;
    planning/testbenches/tage_mtb_decisions.md; planning/arch/sram_init.md
  - Rule-row tests: tage_ctr_test (18 rows); tage_use_test (6 rows);
    tage_assert.sv; ADR-001 (recorded inside
    tage_cntrl_ctr_update_rules.md); Var.mk; $(RVA_ROOT)/tools/bin;
    Verilator 5.020 -> 5.048; HAND-FIX-003 / BUG-001 (later reverted)
  - Rule tables: tage_cntrl_ctr_update_rules.md (~80 -> ~30 rows, row 13e
    added); tage_cntrl_use_update_rules.md (DIFF redefined, TTM row added);
    ittage_cntrl_ctr_update_rules.md (33 rows + A1/A2/A3);
    ittage_cntrl_use_update_rules.md (DIFF corrected)
  - Asserts: ittage_assert.sv; assert_inhibit port on tage_assert.sv;
    tage_assert_bind.sv (removed from sim_tage_manual in BP-042b)
  - Tooling: TASK_TEMPLATE.md (Mode field, PA session field,
    ## Files Modified); gen_sessions.py (MODE_OPTS, W017,
    parse_files_modified); sessions.html; backfill_prompts.py;
    validate_and_extract.py
  - Debt: TD #53 closed. TD #46, #50 fixed-but-not-closed. TD #38 partial.
    TD #54 opened.

### Decisions and rationale (Step 5)

  - Expected values never come from an agent. Naive: let the IA write test
    cases with the RTL in context. Rejected: BP-040 showed the IA changing
    RTL to satisfy its own expectations, with no independent check
    possible. Chosen: IA writes task infrastructure only; Jeff computes
    expected values by hand from rule rows. Defers: throughput — every test
    row is hand-written.
  - Cite-a-rule-row-or-stop. Before modifying RTL, the IA must cite the rule
    row in a loaded planning document that the RTL violates, or stop and
    report. Placed in the Constraints section of prompts, not in Results
    Capture after the fact. Risk: does not detect a wrong planning document,
    which is exactly what HAND-FIX-003 later turned out to be.
  - Read-back verify before predict. tage_round_trip_sanity reads back every
    field of the written RAM entry before any prediction is driven. Rationale:
    a later failure cannot then be attributed to a bad hierarchical path.
  - Unreachable rows covered by bound assertion, not test row. Row 18 and
    ADR-001 invariant. Bind pattern follows OpenTitan prim_assert; sim-only,
    `ifndef SYNTHESIS.
  - ADRs live in the planning document that governs the decision, not a
    separate directory. Rationale: context minimization — the IA loads the
    ADR automatically when it loads the rule doc.
  - assert_inhibit over restructuring CE-06. Naive: rewrite
    no_ram_write_upd_tst so it does not drive update valid with impossible
    metadata. Chosen: add an inhibit port and gate it around that one test,
    preserving the coverage test as written. Jeff selected this option
    explicitly in the BP-042 follow-on actions.
  - Ctx% is manual, Model is automated. Four PA proposals, three of which
    described mechanisms that do not exist.

### Friction / methodology events (Step 6)

  - BP-042 cluster: one task became three. Every deferral traced to a
    PA-authored prompt error — wrong deliverable path (rtl/ vs tb/), invalid
    adjacent-string syntax in a PA-generated file, a constraint written
    broadly enough to forbid repairing that same file (created DEFERRED-3),
    and a background section claiming three always_ff blocks where two exist.
    Cost: two extra sessions. Benefit: asserts now active in all targets.
  - IA literal compliance: wrote ittage_assert.sv to rtl/ because the prompt
    said rtl/, with the tb/ paths in its own context and a staged tb/ copy
    present. Articulated the inconsistency in full when asked, immediately,
    and did not raise it beforehand.
  - Overview parser null: PA blamed the template, proposed moving the heading.
    Diagnosis rejected by Jeff; PA re-read template and fixed the parser.
  - Context percentage is not observable from an automated session. Confirmed
    after four proposals.
  - Verilator 5.020 inout optimizer bug silently dropped USE-field mismatch
    errors. Masked test failures until the 5.048 upgrade.

### Technical Debt Referenced (if applicable)

  - TD #38, #43, #44, #45, #46, #49, #50, #51, #52, #53, #54 all appear in
    the draft's Technical Debt Referenced table.
  - Text was reconstructed from session_handoff-044/045/046, NOT sourced
    verbatim from PROJECT_STATUS.md or CLOSED_TECH_DEBT.md. Neither file was
    supplied this session. Per BLOG_GENERATION_PROCESS.md the table text
    should be copied from those files. THIS IS THE MAIN VERIFICATION ITEM
    FOR NEXT SESSION — supply PROJECT_STATUS.md and CLOSED_TECH_DEBT.md and
    reconcile the table against them for drift.
  - Anchor ids: not assigned. TD is referenced in prose as "TD #NN" with no
    link, per the current rule.

### PA / IA split (Step 7)

  - PA: planning documents, prompt sequencing, ADR convention, decomposition
    of the assert rollout. Also produced every deferral in the BP-042 cluster
    and three fabricated context-capture mechanisms in INFRA-007. Its one
    high-value contribution was reach — it read BP-040's three fixes against
    BP-039's record and identified that two were reversals, which is the
    finding the whole range turns on.
  - IA: task infrastructure, delivered to spec in every case. Reported
    discrepancies it found in its own prompts (block count, Verilator
    version). Failure mode is literal compliance, not context degradation.
  - Jeff: every expected value; rejection of BP-040 results; rejection of the
    parser diagnosis; correction of the BP-042 context paths; identification
    of the /context fabrications.

### Generalization (Step 8)

  - Drafted: the failures in this range were not caused by context exhaustion.
    BP-042 ran at 90% context and produced correct Results Capture; INFRA-007
    ran at 19% and produced fabrications. What the failures share is that an
    agent was asked for a fact it did not have and supplied a plausible one
    rather than stopping.
  - NOT YET CHECKED against the prior post's generalization. Do this before
    the post is finalized.

---

## Draft State

  - Complete. All required sections present: license header, file metadata,
    navigation markers, Abstract, body, Experiment Summary, Technical Debt
    Referenced, References, Attribution.
  - Length approximately 3,600 words. Within the 2500-5000 guideline.
  - Abstract is a single paragraph, approximately 290 words, stand-alone,
    no back-reference to prior posts.
  - Draft text: see attached BLOG_bpu_12_manual_tbs.md.

---

## Open Questions / Decisions Pending

  - BLOG_GENERATION_PROCESS.md conflict, being fixed by Jeff. The "File meta
    data" section specifies a closed five-field block (TITLE, AUTHOR, DATE,
    STATUS, COPYRIGHT). The "Indexability / Frontmatter additions" section
    instructs adding a `description:` field. The publishing pipeline errors
    on DESCRIPTION. The PA added DESCRIPTION to the draft on the strength of
    the Indexability section, then removed it. Jeff is removing the
    conflicting instruction from the process document. The Indexability
    section also refers to "existing title, author, date, copyright fields"
    as frontmatter — that phrasing should be reviewed at the same time, since
    no YAML frontmatter block exists in these posts.
  - References [1] and [2]: confirm the intended Seznec citations.
  - Series navigation: link text and targets for Step 10.
  - Whether HAND-FIX-003's reversal in BP-043a should be reported in this post
    (currently it is) or deferred to the post that covers BP-043a. Reporting
    it here means the post references an experiment outside its own range. The
    alternative is to leave a fix standing in this post that a later post
    reverses. Current draft reports it, on the grounds that the reversal is the
    more informative result and is stated in this range's own source files.

---

## Next Session (004)

  - Supply PROJECT_STATUS.md and CLOSED_TECH_DEBT.md. Reconcile the Technical
    Debt Referenced table against them, verbatim, and check for drift.
  - Supply the prior post (BLOG_bpu_11) and complete Step 8 properly — verify
    the generalization does not repeat the prior post's claim in different
    words.
  - Complete Step 10, series navigation.
  - Resolve the References [1]/[2] question.
  - Decide the HAND-FIX-003 reversal question above.
  - Then final read-through against the Style guidelines (no intensifiers,
    no asides, no metaphors, no subjective opinion, excluded phrases list).

