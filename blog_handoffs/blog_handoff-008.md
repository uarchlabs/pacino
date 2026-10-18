<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Overview
```
 FILE:    blog_handoff-008.md
 SOURCE:  RVA23 Blog-Gen Part 7
 STATUS:  DRAFT
 UPDATED: 2026-10-17
 CONTACT: Jeff Nye
```
Blog generation session handoff.

# Blog Handoff 008

Written by the PA at end of session `RVA23 Blog-Gen Part 7`.

Date: 2026-10-17

This session produced THREE drafts covering PA sessions 064-067 and
IA interactive sessions IA-004 and IA-005:

  - BLOG_bpu_20_cluster_simulation.md    (sessions 064-066)
  - BLOG_fetch_1_ftq_specification.md    (IA-004, IA-005)
  - BLOG_fetch_2_ftq_rtl.md              (session 067)

All three are complete and delivered; none has been reviewed.
bpu/17-19 from handoff-007 remain unreviewed in this record; no
review changes were made to them this session.

Together the three drafts cover 064-067 plus IA-004/005 with no gap
and no overlap. IA-001 to IA-003 are excluded by architect ruling.
Session 068 (cachegen) is held for a separate tools series.

The session also corrected and reformatted pa_session_map.md (see
Map Changes). No edits were made to BLOG_GENERATION_PROCESS.md.

Read this file, then BLOG_GENERATION_PROCESS.md, then the drafts,
before continuing.

---

## Post Identity

### bpu/20

- Series / number / short description: bpu / 20 / cluster_simulation
- Target filename: BLOG_bpu_20_cluster_simulation.md
- Title: "Branch Prediction Cluster Simulation and Mutation-Based
  Verification" -- CONFIRMED by the architect
- Source range: Parts 064-066, BP-091, BP-092, BP-092a, BP-093
  through BP-097
- Range type: Standard (Experiment Summary table, 8 rows)

### Fetch 1

- Series / number / short description: fetch / 1 / ftq_specification
- Target filename: BLOG_fetch_1_ftq_specification.md
- Title: "Specifying the Fetch Target Queue" -- CONFIRMED
- Source range: IA-004, IA-005 (interactive), BP-098 through BP-105
- Range type: Standard (Experiment Summary table, 8 rows). Runtime
  column reads "interactive"; most Context cells "not recorded".
- First post of the new Fetch series.

### Fetch 2

- Series / number / short description: fetch / 2 / ftq_rtl
- Target filename: BLOG_fetch_2_ftq_rtl.md
- Title: "Building the Fetch Target Queue: Eleven Modules and
  Fault-Injected Properties" -- CONFIRMED
- Source range: Part 067, BP-106, BP-107, BP-108
- Range type: Standard (Experiment Summary table, 3 rows)

---

## Inputs Status

Supplied this session:
  - blog_handoff-007.md
  - BLOG_GENERATION_PROCESS.md (2026-09-22, unchanged)
  - Published BLOG_bpu_16_external_anchors.md (structural template)
  - BLOG_bpu_19_bp_cluster_build.md (the 2026-09-22 DRAFT, not a
    reviewed version)
  - pa_session_map.md (original, then the architect's partial update)
  - PROJECT_STATUS.md, CLOSED_TECH_DEBT.md (current)
  - session_handoff-064 through session_handoff-068
  - ia_session_handoff-001 through ia_session_handoff-005
  - BP-091 through BP-108, BP-092a, INFRA-012

PA sessions not read with conversation_search this session.

Still needed / outstanding requests to user:
  - None for the three drafts.

Source reliability flags:
  - INFRA-012 is session 068 (cachegen), not 064. Handoffs 065-067
    each give INFRA-012 as the next free number. Removed from 064 on
    the map.
  - cov_tage denominator: BP-096 measured 8689 -> 8700 (6407 ->
    6418). PROJECT_STATUS TD #100 row says 8468 -> 8700. bpu/20 uses
    BP-096.
  - 407 vs 973 in sim_bp_cluster: 407 is printed PASS lines, 973 the
    check count. 407 appears only as the discrepancy explained.
  - handoff-065's "tage_assert_inhibit not declared" is false;
    corrected by BP-096 (bind scope resolution).
  - BP-097 Results Capture carries four figures handoff-067 says not
    to copy: watchdog ratio 20x-2083x (table says 20x-439x),
    cov_bp_cluster 4499/5286 (baseline, not final 4501/5289), TD
    #100 per-file breakdown (does not sum), TD #110 wording. None
    used.
  - BP-102 gives the rollback index as 7 bits; PROJECT_STATUS
    (session 072) corrects to FTQ_IDX_BITS, 6. Fetch 1 footnote F2.
  - BP-104 says "eight sites" and lists ten lines across seven
    documents. Fetch 1 avoids the count in narrative.
  - BP-105 says "nine files" and lists eight. Fetch 1 avoids the
    count.
  - PROJECT_STATUS heads the IA work "Session-067, first half"; the
    map lists it as IA-004/005. Posts follow the map.
  - BP-106 checks: handoff-068 gives 174 (after BP-107 extended
    tb_ftq_ptr); BP-106's own result is 155. Fetch 2 uses 155.
    handoff-068 says all ten BP-106 properties fired; BP-106 injected
    two faults. All ten shown live in BP-107.
  - Rejected index widening touched three predictor metadata structs
    (BP-103) or four (BP-106, PA assessment). Fetch 2 avoids the
    number.
  - BP-107 Background describes the ICache as behind the IFU; true
    when written, changed later in session 067.
  - BP-100, BP-103, BP-104, BP-105 were written retrospectively with
    reconstructed prompts. BP-101 was done before BP-098/099 and
    numbered after them (the map asterisk).

---

## Process Progress

Per BLOG_GENERATION_PROCESS.md Step-by-Step Process. All three
drafts completed all steps.

  [x] 1. Ranges confirmed. bpu/20 = cluster simulated and test
         infrastructure proven able to fail. Fetch 1 = FTQ specified
         (IA waiver range). Fetch 2 = FTQ RTL built. 067 split from
         IA-004/005 on mode and on what each closes.
  [x] 2. Experiment inventories built: 8, 8, 3.
  [x] 3-8. Clusters, artifacts, decisions, friction, PA/IA split,
         generalization.
  [x] 9. Assembled in template, Abstract last, navigation blocks
         present and empty.

---

## Working Material Captured So Far

### Range confirmation (Step 1)

- bpu/20, 064-066: ports settled (BP-091/092/092a), first simulation
  finds the tage_cntrl branch_id staging defect (BP-093), fix and
  groups G/H (BP-094), then mutation-style proof that each pass/fail
  mechanism can fail, swept per class (BP-095-097).
- Fetch 1, IA-004/005: specification by the IA under the one-time
  planning-doc waiver; ends "FTQ specification complete, nothing
  blocks RTL".
- Fetch 2, 067: PA-written tasks, standing read-only rule; ends with
  the FTQ unit complete (11 modules, 22 targets, 670 checks, 73
  properties).

### Framing rulings (architect, this session)

- A built-but-unsimulated state at a range boundary is the planned
  sequence working, not a shortfall. Do not frame it negatively.
- Breaking a check to show it fails is mutation testing, a standard
  verification practice, not a list of broken tests. Titles must not
  be negative.

### Key figures

  - bpu/20: tb_loop_pred 9,342; tb_bp_cluster 530 -> 973; 245 ->
    258/258 lines; mutants 8, 13, 20; tb_tage 22 failures on unfixed
    RTL; 5 binds in 46 files; 18 testbenches swept; 450 check sites;
    47/47 targets.
  - Fetch 1: entry 182 -> 222 -> 224 bits; group I 24, group J 30;
    sim_bp_cluster 973 -> 997 -> 1765 -> 1795; 177 literals; +9,472
    bits (3.0%); 67 sched checks, 5 properties; status 192 bits.
  - Fetch 2: 155 checks / 10 properties (BP-106); 22 targets, 670
    checks, 73 properties, 46 not firing on first pass (BP-107);
    watermark alias at 64 live entries.

### Generalization (Step 8)

  - bpu/20: a check counts only after it has been shown to fail; a
    silent-pass defect found once is swept for its class and the
    count reported, including zero.
  - Fetch 1: specification found defects in RTL that passed every
    test (no test checks an output a module lacks); a decision has
    one home and others point to it; sweeps are mechanical.
  - Fetch 2: a module result is evidence about that module in that
    tree; a property counts after a fault makes it fire in the build
    that is run.

Series thread across bpu/16-20 and Fetch 1-2: checks that cannot
fail ($isunknown under two-state, exit 0 on failure, dead binds,
cycle watchdogs, properties never sampled or never elaborated).

---

## Draft State

| Post    | Words excl. tables | With tables | Abstract |
|---------|--------------------|-------------|----------|
| bpu/20  | 3,845              | 4,099       | 297      |
| fetch/1 | 3,598              | 3,816       | 308      |
| fetch/2 | 3,109              | 3,209       | 277      |

All three follow the published bpu/16 structure, DATE in the header
(bpu/20 2026-09-23, fetch 2026-09-24), STATUS REVIEW BEFORE POSTING.

### bpu/20

- My contribution lists rulings taken from task files and handoffs;
  architect to confirm and add.
- Discussion-block frustration reported only as its consequence
  (constraint scoping changed).
- Ref [1] IEEE 1800 clause 23.11, no year (sources give none).
- F1 p1 miss operand (session 069); F2 planning-doc rule from BP-106;
  F3 TD #112 closed 2026-09-17.

### Fetch 1

- PA contribution states the PA wrote no task file and the waiver
  followed repeated rework of PA task specs (PROJECT_STATUS wording).
  Architect to confirm the framing.
- Who made FE-5a, the deferrals and the decomposition is not in the
  sources; architect to say if any were theirs.
- Refs: XiangShan [1], RVA23 profile [2], no accessed dates.
- F1 pft_addr uncorrectable after p1; F2 index width; F3 read-only
  rule from BP-106.

### Fetch 2

- My contribution from handoff-068 decisions and the BP-107
  assessment. The "no decode.md" ruling is omitted as out of scope;
  architect may want it.
- PA errors included only where they changed an artifact (BP-106
  scope, package sequencing, /compact constraint, session-number
  inference).
- TD table names pft_addr and census by name; F1/F2 give TD #113 and
  #114 (both open).

---

## Map Changes

pa_session_map.md corrected and reformatted this session (delivered
to the architect):
  - INFRA-012 removed from 064.
  - 065/066 description "tb sweep", BLOG_bpu_20 on second row.
  - 067 "ftq rtl", BLOG_fetch_2. IA-004/005 BLOG_fetch_1, with a note
    on the BP-101 asterisk.
  - 068 "BLOG tools TBD".
  - Historical fixes: stray "J" in preamble; 053 output and 054 input
    -> handoff-054; duplicate 060 output removed; 062 output ->
    handoff-063.
  - Table fits 80 columns (widths 6/21/43), code fence closed, ASCII.
  - The 054 input change was inferred; architect to revert if 054
    started from a file named -053.

---

## Open Questions / Decisions Pending

Resolved this session:
  - bpu/20, Fetch 1, Fetch 2 titles and ranges.
  - IA-001 to IA-003 excluded. Fetch is a new series. Cachegen
    (068) is a future uarchlabs tools series.
  - bpu/19 = 063 now on the map.

Still open (carried from handoff-007):
  - Confirm or replace the bpu/17, bpu/18 and bpu/19 titles.
  - bpu/17 source flag: BP-077 TC8 `^ range` vs cookbook predictor.h;
    check sc_decisions.md s12.
  - ST0 zero-fold path untested at unit level (INFRA-009 F12), no TD.
  - bpu/19: block-descriptor uBTB decision in "My contribution" if
    the architect's. (bpu/20 now credits the architect with ruling no
    separate uBTB decisions document.)

New this session:
  - Confirm the My contribution lists in all three new drafts.
  - Add pa_session_map entries if the architect's copy differs from
    the corrected one.

---

## Next Session (009)

Six drafts are unreviewed: bpu/17-20 and Fetch 1-2. The next session
either works review changes, or starts the next post.

Next post scoping:
  - Fetch 3 = sessions 069 onward. handoff-068 says the next range
    begins instruction cache planning; the architect decided in 067
    that the ICache is an independent front-end module and that there
    is no FTQ-to-ICache interface. Range end not known; read the
    handoffs and the map first.
  - Session 068 (cachegen, INFRA-012, TOOLS-003 to -005) is NOT in
    Fetch 3; it belongs to the tools series, deferred.

Inputs to request for the next post:
  - session_handoff-069 (entry) through the exit handoff of the
    range.
  - Every task file in the range: header block plus RESULTS:START to
    end.
  - Current PROJECT_STATUS.md and CLOSED_TECH_DEBT.md.
  - BLOG_GENERATION_PROCESS.md and the current pa_session_map.md.
  - The reviewed or published Fetch 2, for continuity.

Process:
  - Ask the architect to attach files to the message. Do not name the
    sandbox uploads path; it confused the architect this session.
    Verify every file has content before reading.
  - Inline attachments arrived intact this session.
  - `/context` did not run in this conversation (reached the model as
    text); it works in the architect's other sessions. Start a fresh
    conversation for the next blog session.
  - Short answers; facts only.
