<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Overview
```
 FILE:    blog_handoff-009.md
 SOURCE:  RVA23 Blog-Gen Part 8
 STATUS:  DRAFT
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```
Blog generation session handoff.

# Blog Handoff 009

Written by the PA at end of session `RVA23 Blog-Gen Part 8`.

Date: 2026-10-19

This session did three things:

  - Scoped PA sessions 069-081 into a set of proposed posts (proposal
    text below). Proposed, not assigned, except fetch/3.
  - Corrected pa_session_map.md rows 069-081 and added row 081.
  - Drafted BLOG_fetch_3_spec_audit_build.md (sessions 069-073).

No review changes were made to bpu/17-20 or Fetch 1-2. Reviewing
drafts is the architect's job, not the PA's; the PA applies review
changes the architect supplies.

Read this file, then BLOG_GENERATION_PROCESS.md, then the fetch/3
draft, before continuing.

---

## Post Identity

### fetch/3

- Series / number / short description: fetch / 3 / spec_audit_build
- Target filename: BLOG_fetch_3_spec_audit_build.md
- Title: "Specifying the Instruction Side, and What Building Against
  It Found" -- PROPOSED, not confirmed
- Source range: Parts 069-073; TOOLS-006, BP-109 to BP-114
- Range type: Standard (Experiment Summary table, 7 rows)
- Exception accepted (architect): 073 spans the bpu and ftq units.

---

## Blog Proposal (sessions 069-081)

The text of blog_proposal_069-081.md, as delivered this session:

    # Blog Proposal, Sessions 069-081
    
    Proposed, not assigned. Session 068 (BLOG_tools_1) is not covered.
    
    | Post    | Range   | Experiments                                    | Subject                                      |
    |---------|---------|------------------------------------------------|----------------------------------------------|
    | fetch/3 | 069-073 | TOOLS-006, BP-109 to BP-114                    | Specification, audit, building against it    |
    | fetch/4 | 074-077 | BP-115, INFRA-013, BP-116 to BP-121,           | Front end end to end; fetch path complete    |
    |         |         | BP-123 to BP-125                               |                                              |
    | bpu/21  | 076-077 | BP-122, BP-126, BP-127                         | Loop predictor in use; predictor findings    |
    | bpu/22  | 078-080 | BP-128 to BP-136, SYS-001, SYS-002             | Slots at 1 and 2; last debt; CSR tie-off     |
    | doc/1   | 080-081 | DOC-001 to DOC-005, BP-137, BP-138             | Front-end demonstration                      |
    
    ## Arcs
    
    | Post    | Arc                                                                                     |
    |---------|-----------------------------------------------------------------------------------------|
    | fetch/3 | Instruction side specified (069), audited (070-072, one section), built against (073). |
    |         | Building found three rules no RTL could meet and a skipped redirect target (TD#139).   |
    | fetch/4 | IFU built; front end runs end to end; task method moves from defect lists to end      |
    |         | states (BP-121); that method carries uncached fetch, FENCE.I, the walker and decode.   |
    | bpu/21  | Loop predictor put into use; predictor TD closure reported as findings only (D-1, the  |
    |         | CTR step direction); SC index change.                                                   |
    | bpu/22  | Slot parameter real at 1 and 2; BP-131 shows directed tests cannot decide the slot     |
    |         | questions; last debt as a findings list; CSR tie-off as one section (pt_ad_h).         |
    | doc/1   | Showing the design found defects the regression did not (BP-137, BP-138).             |
    
    ## Exceptions accepted
    
    - fetch/3 spans bpu and ftq units in session 073.
    - fetch/4 exceeds the 2-8 experiment reference and may exceed 5000 words.
    
    ## Open
    
    - bpu/21: separate, or folded into bpu/22.
    - Session 081: confirm in scope.
    - Row 68: what BLOG_tools_1 covers.

Architect rulings behind the proposal, this session:
  - Audits are not interesting on their own; 069-072 folded into
    fetch/3 with the audit as one section.
  - Original fetch/3, /4, /5 merged; original /6, /7 merged.
  - BP-122 moved from fetch/4 to bpu/21.
  - TD closure is reported only as a list of unexpected findings.
  - CSR work (SYS-001, SYS-002) is a section of bpu/22, not its own
    post: it ties off control signals testbenches drove ad hoc.
  - Risk items (unit span, length) accepted as a special case.

---

## Inputs Status

Supplied this session:
  - blog_handoff-008.md, PROJECT_CORE.md, PROJECT_STATUS.md,
    BLOG_GENERATION_PROCESS.md (in ho.md)
  - session_handoff-068 through session_handoff-080
  - pa_session_map.md
  - BLOG_fetch_2_ftq_rtl.md (structural template and continuity)
  - CLOSED_TECH_DEBT.md
  - TOOLS-006, BP-109 to BP-114

Read in part: BP-109 lines 676-2086 (the 1,307-site inventory
listing) were not read; the summary, per-file counts, sweep and
every results section were.

PA session chats not read with conversation_search.

Still needed for the next post (fetch/4, sessions 074-077):
  - session_handoff-081 if it exists (output of 080), only if
    doc/1 is next instead
  - BP-115, INFRA-013, BP-116 to BP-121, BP-123 to BP-125: header
    plus RESULTS:START to end
  - The reviewed fetch/3, for continuity
  - session_handoff-074 to -078 are already supplied this session;
    re-attach in a fresh conversation

Source reliability flags (fetch/3):
  - BP-111 run time is three intervals (1m43s + 1m16s + 15m51s),
    summed as 18m 50s in the table.
  - BP-112 sim_ftq_ptr: 102 -> 159 (+57) after the in-session
    H53-H56 addition; the console's first report said 155.
  - "a notable share" of audit findings were against the PA's own
    edits: handoff-070 names items 1, 2, 5, 8, 9, 11 and half of 13;
    handoff-073 says about a third of the last four batches. The post
    does not give a single figure.
  - The nested-walk cost ("up to four G-stage walks for a three-level
    VS walk") is handoff-070's wording; not used in the post.
  - pa_session_map listed BP-133 under 078; it was written in 078
    and run in 079. Corrected on the map.

---

## Draft State

| Post    | Words excl. tables | Abstract |
|---------|--------------------|----------|
| fetch/3 | about 3,650        | 278      |

DATE 2026-10-19, STATUS REVIEW BEFORE POSTING. Navigation block
present and empty.

For the architect to confirm in fetch/3:
  - The title.
  - My contribution: assembled from rulings in the handoffs and task
    files.
  - References: RVA23 profile [1] (H through Sha) and XiangShan
    documentation [2] (two-pipeline IFU). No accessed dates.
  - Footnotes give later outcomes: MMU-1 reversed (077), IFU-21
    reversed (076), CLAUDE.md package rule (074), TD#131 explained
    (BP-132), TD#134-136 closed (BP-118, BP-123).
  - Omitted as minor: sim_ftq_ptr 2s -> 20s; check_planning.sh
    location tokens.

---

## Map Changes

pa_session_map.md, rows 0-68 unchanged:
  - 069 retitled "fe I-side spec"; documents listed; audit begun.
  - 070-072 one line each of rulings; 072 audit closed.
  - 074 INFRA-013 added.
  - 075 BP-118 "ibuf, itlb, fe_top"; BP-121 "end-state task".
  - 076 "BP-121 recorded".
  - 077 BP-123 to BP-127 labelled.
  - 078 TD scrub, BP-131/132 labelled, BP-133 "written".
  - 079 BP-133 run, csr_decisions.md, SYS-001 as a build.
  - 081 new row, BP-138, output handoff "?".
  - BLOG_fetch_3 tagged on 069-073. No other proposed post is on the
    map until assigned.

---

## Open Questions / Decisions Pending

New this session:
  - fetch/3 title and My contribution list.
  - bpu/21: separate, or folded into bpu/22.
  - Session 081: confirm in scope; supply its output handoff name.
  - Row 68: BLOG_tools_1. The architect said tools_1 is
    BLOG_tools_1_ticfinder.md from 068; ticfinder appears in the
    record as a session-080 tool (FDT-13a), 068 as cachegen.
    Confirm which.
  - Which post next.

Carried from handoff-008:
  - Confirm or replace the bpu/17-19 titles.
  - bpu/17 source flag: BP-077 TC8 `^ range` vs cookbook predictor.h.
  - ST0 zero-fold path untested at unit level (INFRA-009 F12).
  - bpu/19: block-descriptor uBTB decision in My contribution.
  - Confirm the My contribution lists in bpu/20, Fetch 1, Fetch 2.

---

## Next Session (010)

Start a fresh conversation; this one ended at 78% context.

Either work review changes the architect supplies, or draft the
next post. If fetch/4: request the inputs listed under Inputs Status.

Process notes:
  - Do not add proposed posts to the map before they are assigned.
  - Do not review drafts unless asked; apply supplied changes.
  - Map edits are minimal: copy the file and change only the rows
    affected.
  - Ask the architect to attach files to the message.
  - Short answers; facts only.
