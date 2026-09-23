<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Overview
```
 FILE:    blog_handoff-007.md
 SOURCE:  RVA23 Blog-Gen Part 6
 STATUS:  DRAFT
 UPDATED: 2026-09-22
 CONTACT: Jeff Nye
```
Blog generation session handoff.

# Blog Handoff 007

Written by the PA at end of session `RVA23 Blog-Gen Part 6`.

Date: 2026-09-22

This session produced THREE drafts covering PA sessions 056-063:

  - BLOG_bpu_17_statistical_corrector.md  (sessions 056-059, SC)
  - BLOG_bpu_18_before_the_cluster.md     (sessions 060-062, TAGE
                                           repair, doc audit, FE)
  - BLOG_bpu_19_bp_cluster_build.md       (session 063, bp_cluster)

All three are complete and delivered; none has been reviewed. bpu/15
and bpu/16 were published by the architect outside a session, so the
bpu/15 and bpu/16 review items from handoff-006 are moot.

Together the three drafts cover 056-063 with no gap and no overlap.
Sessions 056, 057 and 062 produced no experiments.

The session also applied six edits to BLOG_GENERATION_PROCESS.md
(see Process Note).

Read this file, then BLOG_GENERATION_PROCESS.md, then the drafts,
before continuing.

---

## Post Identity

### bpu/17

- Series / number / short description: bpu / 17 / statistical_corrector
- Target filename: BLOG_bpu_17_statistical_corrector.md
- Working title: "The Statistical Corrector: Design Choices at p3"
  -- NOT CONFIRMED, PA's choice, patterned on the published bpu/15
  title
- Source range: Parts 056-059 (four PA sessions), BP-075, BP-075a,
  BP-076 through BP-080
- Range type: Standard (Experiment Summary table, 7 rows)

### bpu/18

- Series / number / short description: bpu / 18 / before_the_cluster
- Target filename: BLOG_bpu_18_before_the_cluster.md
- Working title: "Before the Cluster: Reconciling the Predictors and
  Their Documents" -- NOT CONFIRMED (architect said "go for it" to the
  angle; title not separately confirmed)
- Source range: Parts 060-062 (three PA sessions), BP-081,
  INFRA-008, INFRA-009, INFRA-010
- Range type: Standard (Experiment Summary table, 4 rows)

### bpu/19

- Series / number / short description: bpu / 19 / bp_cluster_build
- Target filename: BLOG_bpu_19_bp_cluster_build.md
- Working title: "The Branch Prediction Cluster: Built and Not Yet
  Run" -- NOT CONFIRMED, PA's choice
- Source range: Part 063 (one PA session), INFRA-011, BP-082
  through BP-090
- Range type: Standard (Experiment Summary table, 10 rows)

The architect updated pa_session_map.md for bpu/17 and bpu/18.
bpu/19 = 063 is not yet on the map.

---

## Inputs Status

Supplied this session:
  - blog_handoff-006.md
  - Published BLOG_bpu_15_specification_under_test.md and
    BLOG_bpu_16_external_anchors.md
  - BLOG_GENERATION_PROCESS.md (edited this session, see below)
  - pa_session_map.md (original, then the architect's update)
  - PROJECT_STATUS.md, CLOSED_TECH_DEBT.md (current)
  - session_handoff-056 through session_handoff-068
  - BP-075, BP-075a, BP-076 through BP-081, BP-082 through BP-090
  - INFRA-008, INFRA-009, INFRA-010, INFRA-011
  - fe_decisions.md (current only; end-of-062 state taken from
    handoff-063 and the document's own history section)
  - tage_cntrl_uaon_update_rules.md, bpu_port_inventory.md,
    ftq_bpu_interfaces.md, ubtb_interfaces.md (current versions)

PA sessions read directly (conversation_search):
  - Parts 056, 058 and 060-061 for the SC update-gate discussion, the
    cookbook predictor.h BrIMLI quotation, and SC table geometry.

Still needed / outstanding requests to user:
  - None for the three drafts.

Source reliability flags:
  - handoff-057 places the cond_pred_* retirement in session 056;
    handoff-060 places it in 057. bpu/17 says "planning sessions".
  - handoff-062 gives "32 findings ... plus 2 asides" for the
    session-061 audit. The task files give 0 + 12 + 10 = 22. bpu/18
    uses 22.
  - BP-078 header date 2026.07.01; session 059 was 2026-07-02.
    BP-080 run time is an estimate. BP-089 has no run time or
    context figure. Header defects ignored per architect instruction.
  - BP-088 header marks it abandoned; its results report complete,
    45/45. Reason for abandonment taken from handoff-064: the new
    field was driven by no test.
  - handoff-064 first revision overclaimed testbench readiness;
    corrected in review by session 064. bpu/19 reports this.
  - Architect instruction: ignore header bookkeeping defects in
    source files (dates, checkboxes, published-post headers) where
    they do not change the work.

---

## Process Progress

Per BLOG_GENERATION_PROCESS.md Step-by-Step Process. All three
drafts completed all steps.

  [x] 1. Ranges confirmed as real arcs. bpu/17 one unit (SC); bpu/18
         three preconditions for the cluster; bpu/19 cluster built.
         See "Range confirmation" below.
  [x] 2. Experiment inventories built. 7, 4 and 10. All carry Results
         Capture; BP-089 has no run time or context figure.
  [x] 3. Thematic clusters identified
  [x] 4. Artifacts extracted per cluster
  [x] 5. Decisions and rationale extracted
  [x] 6. Friction / methodology events extracted, filtered by the
         artifact-only rule (now in the process doc, Step 6).
  [x] 7. PA/IA contribution separated
  [x] 8. Generalization drafted for each post
  [x] 9. Assembled in template (Abstract drafted last). Series
         navigation blocks present and empty (now in the process
         doc, end of Step 9).

---

## Working Material Captured So Far

(Reference notes, not final prose.)

### Range confirmation (Step 1)

- bpu/17, 056-059: one unit, SC, specification (056-057) then build
  (058-059). BP-080 is inside the range: it investigates the TAGE
  break the SC package edits caused, and stops at the Phase 1 report.
  Session 060 (BP-081) is the TAGE repair and opens bpu/18.
- bpu/18, 060-062: the cluster was the planned next step throughout;
  060 repaired TAGE as planned, 061 and 062 were each redirected from
  the cluster build to a precondition (doc audit; FTQ boundary). 062
  belongs because fe_decisions.md is what the cluster is built
  against.
- bpu/19, 063 alone: "structurally complete and functionally
  unverified above the unit level" (handoff-064). 063-066 together
  would be ~18 tasks, bpu/14 size. Split by theme: 063 build;
  064-066 simulation and checks that could not fail (bpu/20).

### Thematic clusters (Step 3)

bpu/17: source-checked specification (update gate, O-GEHL
parameters, counter capture, chooser, BrIMLI); standalone-SC
arbitration; decomposition and four unit tasks; structural top and
br_imli_mode parameter; package edits never compiled and the TAGE
break; what the testbenches establish.

bpu/18: TAGE restored and the tage_pred_strong narrowing; manifest
omission (BUG-006) and make all gap (TD #99); three-group doc audit;
two ITTAGE rulings; T0 initial value; fe_decisions.md decisions;
interface file blocked.

bpu/19: port inventory; dual-slot FTQ entry; structural top;
behavior and two conflicts; uBTB block descriptor; three abandoned
tasks; BP-090 (metadata write path, p1 operand, br_type rederive,
SC fold staging, refused instruction); not yet simulated.

### Artifacts (Step 4)

Key figures carried into prose:
  - bpu/17: SC_THRSH_MID 2048 -> 10, SC_THRSH_MAX 4096 -> 512,
    SC_THRSH_BITS 12 -> 10, SC_TC_BITS 10 -> 7, achievable |sum|
    ~322; tests 6/7/98, sc 55 (52 fast); tb_sc_cntrl sum 17,
    tb_sc 35.
  - bpu/18: tage_extd_ctr = 2*ctr - 7 (-7..+7); sim_tage 105/0,
    cov_tage 73.7%, cov_tage_table 79.5%; audit 0 + 12 + 10.
  - bpu/19: 140 ports, 136 match; bp_cluster 537 -> 1166 lines;
    uBTB tb 15 cases, 259 checks, 5 mutants, 98.6%; tb_bp_pkg
    16 -> 23 -> 28 checks; 13 mutants BP-090.

### Friction / methodology events (Step 6)

Filtered by the artifact-only rule. Included:
  - bpu/17: task-text update gate replaced by the source rule;
    fabricated import-order rationale removed from sc_decisions.md
    and BP-079; BP-078 port-not-parameter (why BP-079 exists); BP-080
    manifest corrected by hand; BP-075 tb omitted (why BP-075a).
  - bpu/18: BP-081 manifest omission (BUG-006); make all gap (TD
    #99); shared-doc skip policy tightened; T0 grouped as text fix;
    PA asked which doc governed when documents settled it; attachment
    failure reported in one sentence as why the interface file was
    not written.
  - bpu/19: contradictory constraints BP-084 and BP-087; three
    abandoned tasks; BP-089 built on an abandoned task's results;
    testbench-readiness overclaim.
Excluded: postmortem trend narrative, verbosity and jargon items,
Claude Code login failure (063), Mode-field misread and Ctx %
populated by the IA (061).

### Technical Debt Referenced

End-of-range status in each post. Items closed after the range take
their end-of-range text from the handoffs, not the current row.
  - bpu/17: #84-#98.
  - bpu/18: #87, #88, #94, #95 (closed BP-081), #99, #100, #101-#104.
  - bpu/19: #39, #91, #92, #101, #102, #105-#108.

### PA / IA split (Step 7)

Each post has IA, PA and "My contribution" subsections, first person
for the architect, following the published bpu/16. bpu/19's "My
contribution" is thin: sources say little about the architect's role
in 063 beyond abandoning BP-087/088, catching the contradictory
constraints and asking whether the RTL was ready for a testbench.

### Generalization (Step 8)

  - bpu/17: an edit to a compiled file is an RTL change regardless of
    the session that makes it; a planning session that edits a
    package needs a compile and full regression, and the next task
    runs every target.
  - bpu/18: a consistency audit finds disagreement, not which side is
    wrong (T0 / TD#103; IT5 / TD#102). A finding that changes a
    documented VALUE needs the owner's intended value before the doc
    is edited toward the RTL.
  - bpu/19: a type change without its dependents changing. A task
    changing a type names every consumer, found by searching the
    tree, and drives each new field with a value a wrong
    implementation gets wrong.

Series threads across 16-19: checks whose two sides come from the
same source (bpu/16 fold reference; bpu/17 index expressions in the
table testbenches; bpu/19 p1 operand), and changes whose dependents
were not followed (bpu/17 package edits; bpu/19 type changes).

---

## Draft State

| Post   | Words excl. tables | With tables | Abstract |
|--------|--------------------|-------------|----------|
| bpu/17 | 3,780              | 4,442       | 271      |
| bpu/18 | 3,139              | 3,611       | 270      |
| bpu/19 | 3,432              | 3,993       | 239      |

All three follow the published bpu/16 structure: first person for
the architect, References, Footnotes, ticfinder markers, corrected
license header, DATE 2026-09-22, STATUS REVIEW BEFORE POSTING.

### bpu/17

- F1 cites tools/regress.sh (TOOLS-006, session-073) as the later
  fix for the scoped-regression gap.
- "At the draft seed of 2048 ... training gate open on every branch,
  both chooser bands cover every achievable sum" is PA arithmetic
  from the stated rules, not sourced.
- F2: TD #96 later closed (flush is a redirect).

### bpu/18

- "same centered form the SC applies to its own counters" (2*ctr-7
  vs 2*ctr+1) is PA inference; cut if unwanted.
- F1: TD #100 later data (testbench lines dominate cov_tage).
- F2: fe_decisions.md later revisions (RAS read at p0; stage-named
  redirect groups; prediction block vs fetch block, session 071).
  The post uses "prediction block" throughout.

### bpu/19

- F1: the p1 miss operand later changed from block-aligned PC to
  lookup PC (session 069).
- FTB jump drop (two conditionals + jump; BP-085) stated without a
  TD number; none found in sources.

---

## Process Note: process-doc state

Six edits applied to BLOG_GENERATION_PROCESS.md this session,
UPDATED 2026-09-22. These close handoff-006 findings 1-4 and record
two session-5 rulings.

  1. License template: missing `>` added on the
     SPDX-FileCopyrightText line.
  2. TD notation in prose is `TD #NN`.
  3. Series navigation blocks are left present and empty; filled at
     publication (end of Step 9). Resolves the 9-vs-10 step count.
  4. Range sizing: a range spanning more than one design unit is
     split on unit boundaries before compressing.
  5. Step 6: PA postmortem material only where the event changed an
     artifact (file, task, rule, decision).
  6. References: cite an external design or codebase only where the
     project took something from it (mechanism, rule, value verified
     against it). Designs surveyed and not copied are not named.

Rule 6 in practice: bpu/17 cites the Seznec papers, the TAGE
cookbook predictor.h and gem5's SC. bpu/18 and bpu/19 do not name
the external design studied in session 062 or cited in handoff-064
for the block-descriptor uBTB.

---

## Open Questions / Decisions Pending

Resolved this session (recorded for the record):
  - handoff-006 process-doc findings 1-4: applied (above).
  - bpu/17-19 ranges: confirmed by the architect.
  - Header defects in source files: ignore where they do not change
    the work.

Still open:
  - Confirm or replace the bpu/17, bpu/18 and bpu/19 titles.
  - bpu/17 SOURCE FLAG, not in the post: BP-077 TC8 expects
    bb_hist = (bb_hist<<1) ^ last_back_pc ^ range. The cookbook
    predictor.h (as quoted in PA Part 056) XORs only LastBackPC.
    Check sc_decisions.md s12 for whether the ^ range term is
    intended.
  - bpu/18: ST0 zero-fold path untested at the unit level (INFRA-009
    F12), no TD assigned. A bpu/17 loose end; the architect may want
    a TD.
  - bpu/19: if the block-descriptor uBTB decision was the
    architect's, add it to "My contribution".
  - Add bpu/19 = 063 to pa_session_map.md.

Carry-over source hygiene (not blocking any post):
  - The source reliability flags under Inputs Status.

---

## Next Session (007)

Three drafts are complete and unreviewed. The next blog-generation
session either works review changes on bpu/17-19, or starts bpu/20
if the architect reviews and publishes outside a session.

Next post scoping:
  - bpu/20 = sessions 064-066. Entry handoff-064, exit handoff-067.
    BP-091, BP-092, BP-092a, BP-093, BP-094, BP-095, BP-096, BP-097,
    and INFRA-012 (map places it in session 064; placement in the
    post not yet determined -- read it first).
  - Theme: the cluster simulated, and checks that could not fail.
    BP-091/092/092a settle TD #105-#108 before the testbench. BP-093
    is the first simulation and finds the tage_cntrl branch_id
    staging defect, which defeated the branch_id qualification
    described in bpu/19 and was invisible to unit suites because none
    varied branch_id. BP-094 fixes it (973 checks, 258/258 lines, 20
    mutants) and finds tb_tage $finish(1). BP-095 sweeps seven
    testbenches that exited 0 on failure under Verilator 5.048, and
    finds the dead assertion bind. BP-096 bounds the bind class at
    two, corrects the PA's "not declared" diagnosis with the module
    bind scope-resolution rule, adds watchdogs, and exposes a
    concealed stimulus defect in alc_we_gate_tst. BP-097 uses the
    problems-with-acceptance-criteria task form, finds an inert
    $isunknown check under two-state simulation and a cycle-based
    watchdog that cannot fire when the clock stops, and returns three
    negative results; the IA edited planning documents as the task
    instructed and the edits were reverted (rule: an IA task never
    edits planning documents).
  - Estimate: one post. Watch the word count; bpu/14 at 21
    experiments reached the bound.
  - After bpu/20: session 067 with IA-001 to IA-005 (FTQ specified
    and built, BP-098 to BP-108, one-time IA planning-doc waiver) is
    its own unit. Session 068 starts the instruction cache.

Inputs to request for the next post:
  - session_handoff-064 (entry; re-send, context will be fresh),
    -065, -066, -067.
  - BP-091, BP-092, BP-092a, BP-093, BP-094, BP-095, BP-096, BP-097,
    INFRA-012: header block plus RESULTS:START to end.
  - Current PROJECT_STATUS.md and CLOSED_TECH_DEBT.md.
  - BLOG_GENERATION_PROCESS.md (2026-09-22) and pa_session_map.md.
  - The reviewed or published bpu/19, for continuity of the opening;
    the published bpu/16 as structural template.

Process:
  - Upload files to /mnt/user-data/uploads/; inline attachments may
    arrive empty (session-062 regression). Verify readability first.
  - PA sessions in the project are readable with conversation_search.
  - Short answers; facts only; no rankings or significance claims
    unless asked.
