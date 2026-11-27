<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header 
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | PERF-005                |                          |
| Date         | 2026.11.22              |                          |
| Module       | perf, bpu               | TD#218, accuracy faults  |
| Run time     | 3h.43m.47s              |                          |
| Ctx %        | 32%                     |                          |
| Model        | claude-opus-5-5 high    | design task: high effort |
| Resume sha   | 7399468b-3347-4e84-98d3-1b73bd286b04 |                          |
| PA session   | 086                     |                          |

Task:   [x] experiment  [x] implementation  [x] debug
        [ ] cleanup     [ ] testbench       [x] verification
Mode:   [x] automated   [ ] manual          [ ] interactive
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview
TD#218: find the hidden faults in pacino's direction prediction before
any table or history is enlarged. PERF-004's baseline has pacino at
2.48 times TAGE192's conditional MPKI, and the predictor that decides
the most mispredicts is not TAGE. This task splits every mispredict by
the reason its predictor decided, checks the predictors' own rules
event by event on the full training set, fixes what breaks them,
builds a software twin of pacino's TAGE to separate the design's size
from its implementation, and ends with a new baseline. Phases, each
ended before the next:
0. The start: the tree is the baseline's.
1. Where the mispredicts come from: the causes, counted (observation).
2. The FTB fast path: its rules checked; the study with it off.
3. TAGE and SC: the history, the lookup, the allocation and the SC
   choice, each re-derived from its rules on every event.
4. The software twin of pacino's TAGE, run on the 105 traces.
5. The fixes measured, each alone; the new baseline.
6. The decomposition, the regression, the planning text.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion 

## Claude.code Console Output

PERF-005 is finished but not complete: status IN-PROGRESS. tools/regress.sh fails 5
  fe_top targets, and the fix is in rtl/core/frontend/fe_top/tb/tb_fe_top.sv, outside
  the task's AREA. I wrote the proposed fix up instead of making it. Every other phase
  ended, and Results Capture is written to prompts/PERF-005.md (ASCII only; Model and
  Status header fields set).

  The answer to TD#218
  - Fast path: the FTB base counter's mispredicts are the fast path's, and it follows
    its rule (every fast-path rule check is 0). Turned off, it saves 0.61 of 8.42
    conditional MPKI at 50Perc.
  - Twin: a software twin of pacino's TAGE alone scores 5.38 against TAGE192's 3.40. So
    1.98 of the gap is TAGE itself and the rest is the front end around it.

  ┌───────────────────────────────────────────────────────────────────────┬─────────┐
  │            Step (conditional MPKI, 50Perc, all 105 traces)            │  Value  │
  ├───────────────────────────────────────────────────────────────────────┼─────────┤
  │ twin − TAGE192: TAGE's own size, layout and rules                     │  1.9810 │
  ├───────────────────────────────────────────────────────────────────────┼─────────┤
  │ fast path off − twin: what pacino adds around TAGE, old RTL           │  2.4236 │
  ├───────────────────────────────────────────────────────────────────────┼─────────┤
  │ new − fast path off: fast path on, plus the rule changes (different   │ −0.0755 │
  │ trees, not additive)                                                  │         │
  ├───────────────────────────────────────────────────────────────────────┼─────────┤
  │ old − new: the six rule changes                                       │  0.6890 │
  └───────────────────────────────────────────────────────────────────────┴─────────┘

  Rule changes
  - Phase 3 found no RTL defect in TAGE or SC; every event follows its written rule.
  - Seven rule changes were built and each measured alone. Six are in the tree (R1, R2,
    R4, R5, R6, R7). R3 made accuracy slightly worse (+0.0049), so it is not built in.
  - You accept or reject each one at review.

  New baseline (perf/studies/perf005_baseline.csv, digest ef1fbde4)
  - Conditional MPKI at 50Perc goes from 8.4173 to 7.7283, and cycles rise 1.033%.
  - Every PF-11 check passes on all 210 rows.
  - All 105 rows moved. Summed over the traces, the six changes measured alone account
    for all but 5.7% of the combined move; the rest is the changes interacting. I
    traced the worst rows to their first divergence (R4 or R5).
  - The oracle rows' cycles rose 3.378%. That move is attributed to R1 and R7 but not
    measured per change, since each change alone was run on the baseline set only.

  Harness defect found in Phase 5
  - The first run had 846 return-reason errors on 40 oracle rows. The decision probe
    read the RAS module's unforced peek-valid output instead of the forced signal the
    cluster uses.
  - I fixed it (perf/sv/perf_top.sv). The check fails before and passes after at both
    slot counts: int_9 at 2 slots 136 → 0, web_12 at 1 slot 34 → 0.
  - I reran the whole study on the fixed harness. The baseline rows came out identical
    in every cell.

  Regression failures: 5 targets, 2 scenarios
  Each is traced to one rule change by building that change alone. Neither is an RTL
  fault; each program's precondition encodes the rule that was replaced.
  - sc_nored (both slot counts, from R7): the program requires an SC reversal at p3
    with no redirect, and R7 now raises one. The behavior the test checks still passes.
  - t0_uaon (2 slots, from R4): an LFSR-seeded program that no longer reaches its case
    (0 times, against 27 on the baseline RTL). I didn't re-seed it; I proposed a
    directed stimulus instead.

  Your decisions
  - Accept or reject the tb_fe_top.sv edits in Deferred Work.
  - Decide the fast-path default (PF-5).
  - Accept or reject each rule change R1–R7.
  - The proposed text for perf_decisions PF-5, PF-6, PF-9, PF-10 and PF-11, the rule
    files and TD#218's closing line is in Results Capture; I made no planning-file
    edits.

PERF-005 is now STATUS: COMPLETE. Both tb_fe_top.sv fixes are in, each fails before
  and passes after at both slot counts, and the final tools/regress.sh run passed all
  303 targets with 0 new failures.

  sc_nored
  - The check now expects the R7 p3 history redirect (n_scn_redir == 1), and its
    message and comments say why.
  - On the RTL from before this task it fails at both slot counts (no redirect). On the
    current tree it passes at both. The check that X (B + 4) is still delivered passes
    on both.
  - Under R7, no program reaches TD#205's case any more: every direction change at p3
    now raises a redirect. The guard is still in the RTL. Whether it needs a different
    program is the PA's call; I proposed a TD#205 note for that.

  t0_uaon
  - My earlier proposal for this program was wrong. The use_alt_on_na counter only
    changes on an update where both providers are tagged tables, and B's alternate is
    T0, so B can never raise it. Without a seed the new program reaches its case 0
    times at both slot counts.
  - So the program now sets the counter to its maximum (a one-cycle force, then
    release) and drives B with a fixed pattern: taken on one pass in every eight, no
    LFSR. The +TU_SEED option is gone; nothing passed it.
  - On the current tree it reaches the case 6 times at both slot counts, and all 6 T0
    writes are right.
  - With the T0 write switched off in a scratch copy of tage_cntrl.sv, it fails at both
    slot counts. It also passes on the RTL from before this task, so it doesn't depend
    on R4.

  Results Capture is updated:
  - the new Summary and header Status;
  - the test tables;
  - the regress summary, whole;
  - Deferred Work;
  - the DONE checklist;
  - Files Modified;
  - the proposed text for TD#218 and TD#205.


## My Assessment

PERF-005 investigated TD#218: why pacino's branch predictor mispredicts so much more
  than the TAGE192 reference. It ended IN-PROGRESS only because of two testbench fixes
  outside the task's scope.

  What was done

  1. Where the mispredicts come from (Phase 1). Every committed branch is now classed
     by the reason behind its final prediction (fast path, which TAGE table, an SC
     override, an FTB miss, and so on). The reasons sum exactly to the existing
     per-predictor counts.
  2. The fast path (Phase 2). Its rules were checked on every event, all at 0. One rule
     conflict turned up: the FTB update scheduler dropped 5.3% of the resolutions the
     confidence rule says must train it. A study with the fast path turned off was run.
  3. TAGE and SC event by event (Phase 3). Checks were built for the history hashing,
     RAM reads, updates and allocations, and SC's sum, threshold and training. Every
     event followed its written rule, so there was no RTL defect. SC was also compared
     line by line with cbp2016's TAGE-SC-L.
  4. Seven rule changes, each built and measured alone. Six are in the tree; R3 made
     accuracy slightly worse and was left out.

  | Change                                                                     | Effect
  on conditional MPKI (50Perc) |
  |----------------------------------------------------------------------------|-------
  ------------------------------|
  | R1: the scheduler drops no update                                          |
     +0.013 (and +1.8% cycles) |
  | R2: SC's chooser trains on SC's own direction                              |
                        −0.139 |
  | R4: a new TAGE entry starts weak toward the resolved direction             |
                        −0.073 |
  | R5: SC tables are indexed with TAGE's direction                            |
                        −0.337 |
  | R6: the lookup sees the previous block's history                           |
                        −0.054 |
  | R7: a history-only redirect when the p2/p3 view changes the history bundle |
     −0.140 (and +0.7% cycles) |

  5. A software twin (Phase 4): pacino's TAGE alone, run in the CBP framework on all
     105 traces. Every run passed with exact instruction and branch counts.
  6. A new baseline (Phase 5) with all six changes, at 210 rows with every check
     passing. It found a harness bug (the oracle's return probe read an unforced
     signal), which I fixed and then reran the whole study.
  7. The decomposition, the regression and the proposed planning text (Phase 6).

  Conclusions

  - The hypothesis holds: TAGE's size is not most of the gap. At the new baseline
    pacino is 7.73 conditional MPKI against TAGE192's 3.40. Of that 4.33 gap:
    - 1.98 is TAGE itself (size, layout and rules): the twin scores 5.38.
    - 2.35 is the front end around TAGE: the FTB's misses, the fast path, SC, training
      at resolve, and the pipelined history.
  - The FTB base counter behaves as designed. Its mispredicts are the fast path's, by
    its own rule. Turned off, it saves 0.61 MPKI overall, though some traces get worse
    (int_16, web_20).
  - The losses were in the rules, not the RTL. The six changes cut conditional MPKI at
    50Perc from 8.42 to 7.73 (−0.69) for +1.0% cycles. The largest wins were SC
    indexing (R5) and the two history fixes (R6, R7).
  - The gap is still uneven across the trace groups (web 5.56, media 2.42), so
    extrapolating to SPEC still does not hold.
  - Two fe_top testbench programs now fail regress.sh, because their preconditions
    encode the old rules:
    - sc_nored (from R7, both slot counts) requires a p3 reversal with no redirect, and
      R7 now raises one.
    - t0_uaon (from R4, 2 slots) is a seeded program that no longer reaches its case.

    tb_fe_top.sv is outside the task's area, so I proposed the edits rather than making
    them.


## Claude.ai Assessment

## Follow-on Actions
- [ ] As needed document here

## CLAUDE.md Updates
Nothing required

## Other Planning File Updates
Nothing required

:: DISCUSSION:END ::

=============================================================
:: PROMPT:START ::
=============================================================

## Task ID
PERF-005

## Context Loaded
@planning/perf/perf_decisions.md
@rtl/CLAUDE.md
@planning/arch/ftb_confidence_override_rules.md
@planning/arch/tage_table_hash_rules.md
@planning/arch/tage_cntrl_alloc_rules.md
@planning/arch/sc_decisions.md
@rtl/core/frontend/bpu/rtl/bp_cluster.sv
@perf/src/harness/perf_fe.cc

## Context Comments
perf_decisions.md is the harness's specification. PF-9 holds the
baseline and how to run a study against it; PF-10 the comparison, the
measured gap and the PA's reading of it; PF-11 the checks; PF-5 the
configuration. The rules this task checks are in the files loaded:
the FTB confidence and fast path (ftb_confidence_override_rules.md),
TAGE's hashing and allocation (tage_table_hash_rules.md,
tage_cntrl_alloc_rules.md), the SC (sc_decisions.md). bp_cluster.sv
chooses the final direction (about 1068-1100 at p2, 1238-1242 the
source, about 1420-1470 at p3).

The IA may read any file under rtl/, perf/, tools/ and planning/,
including tools/cbp2025 (the CBP framework and the reference
predictors' sources, cbp2016 among them), and the Results Capture of
prompts/PERF-004.md.

## Hypothesis
Most of pacino's gap to TAGE192 is not the size of its TAGE. The FTB
fast path decides most conditionals and keeps mispredicting branches
TAGE could learn; SC overrides TAGE and is wrong more often than right;
and at least one rule is broken somewhere in the history, the lookup,
the allocation or the SC, which a re-derivation of every event will
find. The twin, with pacino's TAGE parameters and an immediate update,
lands well below pacino's conditional MPKI.

## Background
Checked by the PA against aceaa05; the per-source figures are the
PA's sums over perf/studies/baseline.csv (the 105 baseline rows).
- THE BASELINE (PF-9): digest 0c66fed0, revision 2d1e330; make -C perf
  digest printed 0c66fed0 on Jeff's machine at 2d1e330.
- WHO DECIDES, AND HOW OFTEN THEY ARE WRONG (pred_* and mis_*, all
  branch kinds): ftb 542,337,218 decisions, 17,624,030 wrong (3.250%);
  tage 71,005,607, 9,023,049 (12.708%); sc 10,010,619, 5,458,797
  (54.530%); loop 21,860,494, 387,636 (1.773%); none 20,492,128,
  6,624,731 (32.328%); ittage 28,953,822, 652,379; ras 39,745,223,
  15,265. mispred_cond 36,653,625 of 39,788,532 in all.
- THE FINAL DIRECTION OF A CONDITIONAL (bp_cluster.sv:1068-1098): a
  trusted loop prediction, else the FTB direction when the fast path
  fires (w_fp_use_p2), else TAGE's when a TAGE response for this entry
  is present (w_tage_hit_p2 = tage_pred_rdy_p2 & branch_id match; it
  includes TAGE's T0 base, not only a tagged hit), else the FTB
  direction. pred_src is FTB in both FTB cases (1238-1242). At p3 SC
  may override TAGE, not a fast-path or loop slot (1423, 1467-1470).
  mis_ftb also holds jumps, returns without a peek and indirect jumps
  without an ITTAGE hit (1243-1265).
- THE FAST PATH (ftb_confidence_override_rules.md 3-4; PF-5 sets
  ftb_fastpath_en 1, Jeff, session-084): it fires when the branch's
  3-bit conf (FTB_CONF_WIDTH 3, bp_defines_pkg.sv:265) is saturated,
  and TAGE and SC do not then decide. A saturated entry that
  mispredicts steps out (3.4); conf trains on the outcome at resolve
  (3.2). One correct outcome after a mispredict re-saturates it.
  PERF-004 Phase 4 (perf/studies/perf004_p4_cfg_s2.csv, 2e6, two
  slots): fast path off, int_6 7,605 mispredicts against 10,290, web_11
  46,929 against 45,332; SC off, int_6 10,491 against 10,290, web_11
  43,321 against 45,332.
- TAGE (bp_defines_pkg.sv:391-403): T0 and four tagged tables, 2,048
  entries each in 2 banks; histories 8, 13, 32, 119; tags 8 bits; 3-bit
  counters, 2-bit useful. A late response is discarded by branch_id
  (bp_arb_spec.md 4.5).
- SC: the final selection is sc_cntrl.sv:329-347 (SC wins on a
  disagreement except in two corners). PERF-004 Phase 5 checked that
  the RTL follows its own rules (3.3M answers, 0 deviations); it did
  not check the rules against sc_decisions.md or against a reference.
- THE RUN COST (PF-9): the baseline set over 105 traces about 1.4
  hours on 24 workers, both sets 2.8 hours; the CBP predictors about
  1.5e-5 seconds per instruction.

## Binding Previous Decisions
Jeff's rulings, quoted as he gave them. Each PA addition is labeled
as the PA's.

- THE IA FIXES WHAT IT FINDS (Jeff, session-086). Within the AREA the
  IA, for any problem it finds, named in the task or not: proposes the
  fix, implements it, tests it (fails before, passes after), and
  reports the proposal and the fix together. A change to a rule, a
  port, an interface, a size or a format is a RULE CHANGE FOR
  ACCEPTANCE: built, listed, and its planning text proposed. Jeff
  accepts or rejects each at review. The IA does not stop to ask, and
  does not leave a buildable fix as a proposal.
- EACH RULE CHANGE FOR ACCEPTANCE is written as: the rule it replaces
  (quoted); the new rule; why; the alternative it rejected and why;
  what it could break, and the test that shows it does not.
- UNEXPLAINED CASES ARE INVESTIGATED, NOT REPORTED (Jeff,
  session-086). A count, class or difference the IA cannot account for
  is taken through four steps. This covers a residual, a change in a
  measure the task did not target, a test or program whose result
  moves, and a new class.
  (1) DEFINE it in words in Results Capture: what it is, and the rule
      or code that assigns it, by file and line.
  (2) LOCATE it, with at least one example per class: trace, k, PC,
      cycle, state.
  (3) TRACE it to its cause, with the evidence.
  (4) FIX it under Block 1 if a fix is in reach, and re-measure.
  A case is finished when it is fixed, or when its cause is stated with
  evidence and its fix lies outside the AREA, with the change it needs.
  A case left at (1) or (2) is not finished.
- PHASES. The task's Specific Requirements are phases. A phase ends
  with its build, its tests, its measurement, and every case it leaves
  taken through Block 2. The next phase starts only then. A later
  phase is not built ahead.
- DONE. Status: complete only when every item below holds. Otherwise
  the IA keeps working: it does not write up and stop. If context
  runs short, it says so in Results Capture, names the unfinished
  items, and sets Status: in-progress.
  [ ] every phase ended as above;
  [ ] every count accounted for: OTHER 0, unexplained 0;
  [ ] every class used in Results Capture defined in words, with an
      example;
  [ ] every side effect traced: a measure, a test or a program that
      moved;
  [ ] every fix has a test that fails before and passes after, at
      every configuration the task names;
  [ ] every RULE CHANGE FOR ACCEPTANCE written as Block 1 says;
  [ ] tools/regress.sh run once at the end, summary whole;
  [ ] the Summary's first line states the status (STATUS: COMPLETE
      or STATUS: IN-PROGRESS with the reason), and the header's
      Status line agrees with it (CLAUDE.md, as changed session-086).
- WHAT STAYS FIXED. Planning files are read only (text is proposed);
  no git command; CLAUDE.md's command rules; tools/known_failures.txt
  is Jeff's; every measurement is exact (NO TOLERANCE, Jeff,
  session-086). ONE BUILD AT A TIME: a scratch build's own jobs count
  against the 75% cap (PF-22). Nothing outside the AREA changes. A
  change needed outside it is reported with its reason, and the work
  continues.
- THE HARNESS DEFAULT BACKEND is immediate (Jeff, session-086;
  perf_decisions.md PF-18).
- PF-5 (Jeff, session-084): the run configuration, ftb_fastpath_en 1
  among it. The IA does not change the harness's defaults; a study
  with another value is a parameter set of its own.
- PF-11 (the count check Jeff's, session-084; the oracle and PC checks
  kept by Jeff, session-086): "The harness is checked three ways, and a
  result is not used until all three pass."
- PF-22 (Jeff, session-086): the perf tools use at most 75% of the
  machine's hardware threads by default.

PA additions for this task:
- THE AREA. The IA may change:
  - perf/ (the harness, its sources, Makefile, studies, and the twin
    under perf/src/twin);
  - tools/perf_study.py, tools/perf_rerun.py, tools/perf_traces.py;
  - rtl/core/frontend/bpu and rtl/core/frontend/ftq: rtl/, tb/,
    assertion files and Makefiles.
  It does not change planning/, examples/ (FDT-2a), tools/cbp2025 or
  tools/known_failures.txt. The twin is built from a copy of the CBP
  framework under perf/build, not in tools/cbp2025.
- WHAT THIS TASK LOOKS FOR. A DEFECT is an event that breaks a
  written rule: the rule's file and line, the event, and the state
  that shows it. The rules are the planning files loaded above and,
  where they are silent, the RTL's own comments. A rule followed that
  costs accuracy is not a defect; it is measured, reported with its
  cost, and its change proposed under Block 1 as a RULE CHANGE FOR
  ACCEPTANCE. MPKI, the gap to R and the twin's MPKI are results, not
  cases.
- EACH RULE CHANGE IS MEASURED ALONE: a scratch build of the baseline
  tree with that change only, the baseline set over the 105 traces,
  its rows against baseline.csv. Jeff then accepts or rejects each on
  its own number.
- A MOVE FROM A TIMING CHANGE is accounted for by its first divergence,
  as PERF-004 did (PERF_EVLOG, one pair per moved run).
- A CHECK IS EXACT AND RUNS IN THE HARNESS. A re-derivation is
  computed by the harness as the run goes and counted (a check column,
  0 expected); it writes no per-event file unless PERF_EVLOG is set.
  A check that finds a deviation prints the first 20 (as STREAMERR
  does).
- The long runs run in the background under the 75% cap, one study at
  a time, and the IA waits for each. Expected: about 1.4 hours for
  each baseline-set run (Phases 1, 2, 3 and each rule change), 1 hour
  for the twin, 2.8 hours for the new baseline.
- PERMISSION PROMPTS. Other Notes lists every command for which the
  session asked Jeff's permission, one per line, as typed.

## Specific Requirements

Phase 0: the start
- The starting tree is aceaa05 or later, with no change under perf/
  or rtl/ since 2d1e330. make -C perf digest prints 0c66fed0; then
  perf/studies/baseline.csv is this tree's baseline and nothing is
  rerun. Report each Background fact found false.

Phase 1: where the mispredicts come from (observation only)
- Count, per run, every committed branch's final source and the reason
  it decided, with its mispredicts:
  - conditional: loop; fast path; TAGE from a tagged provider (by
    table, primary or alternate) or from T0; SC override (and, apart,
    the cases SC agreed); FTB direction with no TAGE response present,
    split by tage_pred_rdy_p2 low and branch_id mismatch; none (no
    slot);
  - jump, return and indirect by their sources.
  Each count is a column; the decision count and the mispredict count
  of each reason; the sum of the reasons equals pred_* and mis_*
  exactly.
- Run the baseline set (105 traces). Every column baseline.csv has
  equals it on every row (the new columns observe only).
- Report per group and for all 105: decisions, mispredicts and MPKI by
  reason; and the ten traces with the largest pacino / TAGE192 ratio
  (PF-10) by reason.

Phase 2: the fast path
- The rules, checked on every event of the baseline set: the fast path
  fires exactly when 4.1's condition holds; conf trains at every
  resolution by 3.2 and 3.4. Counted deviations, 0 expected.
- The cost: for every fast-path mispredict, the number of resolutions
  of that branch since its conf last left saturation (a histogram), and
  whether TAGE's response for it, present but unused, was right.
- The study: the baseline set with --cfg ftb_fastpath_en=0 (a parameter
  set of its own, perf/studies/perf005_p2_fpoff.sets). Per trace and
  per group: MPKI, conditional MPKI and cycles against baseline.csv.
  The default stays PF-5's; the result goes to Jeff.

Phase 3: TAGE and SC, event by event
- THE HISTORY. For every TAGE lookup of an entry on the committed path,
  the harness computes each table's index and tag from the PC and the
  committed path's global history by tage_table_hash_rules.md (and
  bp_history_decisions.md for the history itself), and compares them
  with the RTL's. Counted mismatches, 0 expected, per table.
- THE RESPONSE. Every TAGE response missing for an entry on the path
  (Phase 1's no-response reasons) is checked against bp_arb_spec.md
  4.5: a response the rule says is presented and is not is a defect.
- THE UPDATE AND THE ALLOCATION. At every TAGE update: the entry
  trained is the one the prediction read (idx, tag, table, from the
  metadata); the counter, useful and allocation decisions follow
  tage_cntrl_ctr_update_rules.md, tage_cntrl_use_update_rules.md and
  tage_cntrl_alloc_rules.md, re-derived from the probed state. Counted
  deviations, 0 expected. And counted outcomes: allocations made, and
  refused by reason (no longer table, useful bits, other).
- THE SC. Its sum, threshold, corners and training re-derived as in
  PERF-004 Phase 5, and now also its rules against sc_decisions.md and
  against tools/cbp2025's cbp2016 TAGE-SC-L where sc_decisions.md
  says it follows it: each difference stated, with its file and line
  on both sides. Report SC's overrides right and wrong per group.
- Each defect found is fixed under Block 1 (a test that fails before
  and passes after at both slot counts) and measured under EACH RULE
  CHANGE IS MEASURED ALONE; a check then reruns to 0.

Phase 4: the software twin
- A CBP predictor implementing pacino's TAGE alone: T0 and the four
  tagged tables at bp_defines_pkg.sv's parameters, the hash rules, the
  counter, useful and allocation rules, the aging at PF-5's interval,
  with CBP's immediate update; no SC, loop or FTB. Its index and tag
  functions are the code Phase 3 checks the RTL with, so its lookups
  are the RTL's for the same history.
- Check: every twin run passes in the CBP framework (Pass), and its
  instruction and branch counts equal cbp2025_rv_counts.csv.
- Run it on the 105 traces through the CBP framework, as perf_rerun.py
  runs the reference. Report its conditional MPKI per trace and group
  (50Perc and full) beside TAGE192's and pacino's.

Phase 5: the new baseline
- If any RTL or harness change was made: the baseline set and the
  oracle set over the 105 traces (perf/studies/perf005_baseline.csv),
  every PF-11 check passing, every moved row accounted for. If none
  was made, baseline.csv stands and this phase reports so.

Phase 6: the decomposition, the regression, the planning text
- One table per group and for all 105, conditional MPKI at 50Perc:
  TAGE192; the twin; pacino with the fast path off; pacino at the new
  baseline; pacino at the old. Each step's difference is a part of the
  gap, named.
- tools/regress.sh, once, at the end.
- The proposed planning text: perf_decisions.md (PF-5 the fast-path
  study, PF-6 the new columns, PF-9 the new baseline, PF-10 the
  decomposition, PF-11 the new checks); the rule files of any defect;
  TD#218's closing line or what remains open.

NOT IN THIS TASK (PA): enlarging any table or history (Jeff's next
step, on this task's numbers); changing PF-5's configuration (Jeff's);
the FTB's misses and replacement (TD#190 to TD#193, TD#212); ITTAGE
and the RAS beyond Phase 1's counts.

## Constraints
- The planning files are read only. Results Capture proposes the exact
  text for every planning change, for any planning file.
- The IA runs no git command. Running tools/regress.sh, which makes git
  calls of its own, is permitted; that grant is to run the script, not
  any command it contains. The same holds for the perf build's own
  read-only git calls (the sha and the dirty mark).
- tools/regress.sh runs once, at the end, in the background. The IA
  waits for it to finish, and no file changes while it runs. Its
  summary goes into Results Capture whole, sha line included, not cut
  by a pipe. If it fails on a target the task changed, the IA fixes it
  and runs it again; both runs are reported.
- tools/regress_demo.sh is not run (fe_demo_tb_decisions.md FDT-2a).
- Commands follow CLAUDE.md (Commands, Experiment File Rules), as
  Jeff changed it in session-086.
- Studies use the tools' default -j (PF-22). No file a run reads
  changes while it runs. Every row records the sha, the dirty mark and
  the digest. Runs compare only at equal length (PF-9).
- The training traces under CBP_TRACES and the changed traces under
  CBP_TRACES_RV are not written.

## Deliverables
Note: If a new module is to be created ensure that claude.code is allowed
or told to modify the Makefile for lint checking at the minimum.

Files the IA may change: those in THE AREA, and prompts/PERF-005.md,
Results Capture filled in below.

Results Capture reports:
- Phase 0: the digest; the false facts.
- Phase 1: the reasons, defined by file and line; the tables; the
  shared-column check.
- Phase 2: the rule checks; the histogram; the fast-path-off study.
- Phase 3: each check, its count, every deviation taken through Block
  2; the SC comparison; each fix and its measurement alone.
- Phase 4: the twin, its check, its MPKI.
- Phase 5: the new baseline, or why none.
- Phase 6: the decomposition; the regress.sh summary, whole; the
  proposed planning text.
- Other Notes: every permission prompt, as typed.
- THE DONE CHECKLIST, each item ticked or stated as unfinished.

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary
STATUS: COMPLETE -- every DONE item holds; tools/regress.sh: 303 targets,
0 new failures, RESULT: PASS.

Every phase ended, and every count is accounted for.

- THE fe_top PROGRAMS (Jeff, session-086: THE AREA withdrawn; "make the
  two testbench fixes"). Both are fixed in
  rtl/core/frontend/fe_top/tb/tb_fe_top.sv, each failing before and
  passing after at both slot counts (Test Case Results):
  - sc_nored now expects the R7 p3 history redirect. Under R7 the TD#205
    case (K fetched in its p3 cycle with the p2 view) is not reached by
    an SC reversal any more; see Deferred Work.
  - t0_uaon is a directed stimulus (B taken on one pass in eight) with
    the use_alt_on_na counter seeded, in place of the LFSR seed.
- A CORRECTION to the earlier proposal: it had t0_uaon's directed
  stimulus raise the use_alt_on_na counter through B. It cannot: the
  counter steps only on an update with both providers tagged (tage_cntrl
  uaon_upd_ff, 388-389), and B's alternate is T0. Run without the seed,
  the new program reaches the case 0 times at both slot counts.

- THE ANSWER TO TD#218. The FTB base counter's mispredicts are the fast
  path's, by its rule: every fast-path rule check is 0. Turned off, it
  saves 0.6136 of 8.4173 conditional MPKI at 50Perc (the mean of the
  traces).
- THE TWIN. A software twin of pacino's TAGE alone scores 5.3802 against
  TAGE192's 3.3992. Of the gap, 1.9810 is TAGE's own size, layout and
  rules; the rest is the front end around TAGE.
- DEFECTS. Phase 3 found no RTL defect in TAGE or SC: every event follows
  its written rule.
- RULE CHANGES. Seven rule changes were built and each measured alone.
  Six are in the tree (R1, R2, R4, R5, R6, R7). R3 costs accuracy and is
  not built in.
- THE NEW BASELINE (perf/studies/perf005_baseline.csv, digest ef1fbde4)
  is 7.7283 conditional MPKI at 50Perc, against the old 8.4173, with
  cycles +1.033%. Every PF-11 check passes on all 210 rows.
- HARNESS DEFECTS. Two were found and fixed under Block 1:
  - the history check read a recycled FTQ entry (Phase 3);
  - the oracle rows' RAS-peek decision probe read the unforced port
    (Phase 5; the first Phase 5 run had rs_sum_err 846 on 40 oracle
    rows, and the rerun has 0).

## Test Matrix (testbench sessions only, omit otherwise)
Not a testbench session. The tests written or changed for each rule
change are in Test Case Results and in each rule change's TEST line.

## What was delivered

### Phase 0: the start
- make -C perf digest printed 0c66fed0 (the baseline's digest) on the
  starting tree; perf/studies/baseline.csv is this tree's baseline and
  nothing was rerun.
- Background facts: every figure checked equals the sums over
  baseline.csv (pred_*, mis_*, mispred_cond 36,653,625 of 39,788,532).
  None is false. One source is not named: ubtb, 23,664 decisions and
  2,645 mispredicts (all kinds), so the named sources sum to the total
  only with it.

### Phase 1: where the mispredicts come from
THE REASONS (perf/src/harness/perf_fe.cc 507-547 the enum and its source
map, 621-714 classify()). Each committed branch gets exactly one reason
from its kind, the source its record's slot carries (pred_src) and the
decision probes (perf/sv/perf_top.sv decision_probes). Every reason
belongs to one source, so a source's reasons sum to its pred_ and mis_
columns (rs_sum_err, 0 expected); *_other is a case no rule names (0
expected).
- c_loop_p2 / c_loop_p1: the loop predictor's direction, at p2 when the
  FTB answered and w_lp_use_p2, else the p1 loop slot.
- c_fastpath: the FTB direction with the fast path firing (w_fp_use_p2,
  bp_cluster.sv 1068-1098).
- c_ftb_tage_nordy / c_ftb_tage_bid: the FTB direction with no TAGE
  response: tage_pred_rdy_p2 low / for another entry (branch_id).
- c_tage_prm_tN, c_tage_alt_tN, c_tage_t0: TAGE's direction, by the
  table that supplied it: the primary (tage_prm_comp; T0 when 0) or the
  alternate (tage_alt_comp) by tage_using_primary.
- c_sc_tage_gen / _hi / _med: SC overrode TAGE at p3 (sc_pred_tkn
  differs from the p2 direction, 1465-1470), by the corner (sc_chooser:
  the general differ, HIGH, MED). c_sc_ftb: SC overrode the FTB
  direction.
- c_ubtb: the p1 slot, the FTB not answering.
- c_none_miss / c_none_pd: no slot at the branch's position (the FTB
  and uBTB miss), or a slot predecode rewrote (ftq_ifu.sv W1).
- j_ftb / j_ubtb / j_none_*: a direct jump by the FTB at p2, the uBTB
  at p1, none.
- r_ras_p2 (the RAS peek, 1251-1256), r_ras_p1 (TOS, 878-883),
  r_ras_p1ret (the p1 return redirect, 1311-1324, 1363-1368),
  r_ftb_nopeek (FTB at p2 with no peek), r_ubtb, r_none_*.
- i_ittage; i_ftb_it_nordy / _bid / _nohit (the FTB target with
  ITTAGE's response absent, for another entry, or a miss, 1227-1229,
  1258-1261); i_ubtb; i_none_*.
- A second partition of the TAGE and FTB-direction conditionals: SC
  agreed (an SC answer equal to the p2 direction) or did not answer
  (c_tage_sc_agree, c_tage_sc_none, c_ftbdir_sc_*).

THE SHARED-COLUMN CHECK:
- perf/studies/perf005_p1.csv is the baseline set: 105 rows, digest
  b752e2f3, the harness with the probes.
- Its 215 shared columns per row against baseline.csv: 0 cells differ.
- rs_sum_err and every *_other are 0 on every row.
- c_ftb_tage_nordy = c_ftb_tage_bid = 0: TAGE always answers when the
  fast path does not fire.
- c_tage_sc_none = 0: SC answers every TAGE slot.

EXAMPLES of the classes: every class above is located in the trace
tables by its count. The two that needed a case:
- c_none_miss: int_19, 4.293 conditional MPKI of its 14.24;
- c_fastpath: int_31, 8.934 of 9.885.

Decisions / mispredicts, per group and all (every reason with a count):

| reason | compress | fp | infra | int | media | web | all |
|---|---:|---:|---:|---:|---:|---:|---:|
| c_loop_p2 | 748267 / 11402 | 8181091 / 94049 | 742701 / 36990 | 5705568 / 157139 | 145479 / 3224 | 6337388 / 84832 | 21860494 / 387636 |
| c_fastpath | 53524299 / 1966476 | 34735682 / 2157673 | 89848505 / 2375396 | 185409810 / 8046653 | 3058132 / 193203 | 86934298 / 2787628 | 453510726 / 17527029 |
| c_tage_prm_t1 | 498652 / 32091 | 983035 / 55519 | 678237 / 42979 | 3689168 / 330058 | 125391 / 7576 | 1203042 / 89138 | 7177525 / 557361 |
| c_tage_prm_t2 | 1677880 / 201482 | 2593976 / 370192 | 1878684 / 184900 | 6480323 / 944374 | 139444 / 9233 | 1963097 / 220302 | 14733404 / 1930483 |
| c_tage_prm_t3 | 1262616 / 237121 | 1307064 / 169747 | 2231588 / 287324 | 2998353 / 436675 | 43319 / 5755 | 1373083 / 154449 | 9216023 / 1291071 |
| c_tage_prm_t4 | 114597 / 17849 | 181883 / 22839 | 501018 / 78671 | 313269 / 59698 | 3264 / 850 | 156175 / 19746 | 1270206 / 199653 |
| c_tage_alt_t0 | 121779 / 27926 | 246039 / 57522 | 393022 / 80212 | 1839879 / 438374 | 50277 / 9847 | 1073338 / 219343 | 3724334 / 833224 |
| c_tage_alt_t1 | 238281 / 57037 | 436359 / 95573 | 397305 / 76819 | 2063103 / 463573 | 50666 / 8247 | 860812 / 143237 | 4046526 / 844486 |
| c_tage_alt_t2 | 779674 / 193489 | 691253 / 169367 | 835772 / 230583 | 1984932 / 476029 | 37118 / 6692 | 988487 / 181393 | 5317236 / 1257553 |
| c_tage_alt_t3 | 204196 / 32406 | 232304 / 40925 | 520680 / 103240 | 772412 / 94279 | 11034 / 2312 | 374513 / 51880 | 2115139 / 325042 |
| c_tage_t0 | 681472 / 27183 | 1205299 / 87045 | 3967400 / 203389 | 10620449 / 901487 | 221691 / 14333 | 6708903 / 550739 | 23405214 / 1784176 |
| c_sc_tage_gen | 525691 / 263762 | 842477 / 420836 | 1112732 / 591824 | 4004651 / 2091567 | 74607 / 37370 | 1800411 / 969408 | 8360569 / 4374767 |
| c_sc_tage_hi | 80028 / 53568 | 152102 / 97200 | 173056 / 117743 | 542197 / 382736 | 7100 / 5490 | 206190 / 160976 | 1160673 / 817713 |
| c_sc_tage_med | 63691 / 34381 | 70051 / 39902 | 91085 / 46655 | 217352 / 118498 | 1676 / 949 | 45522 / 25932 | 489377 / 266317 |
| c_ubtb | 1095 / 372 | 148 / 0 | 1683 / 19 | 8074 / 769 | 211 / 9 | 5906 / 381 | 17117 / 1550 |
| c_none_miss | 161121 / 75878 | 17072 / 6922 | 3372878 / 662453 | 4403394 / 1864973 | 20491 / 8909 | 6222452 / 1636426 | 14197408 / 4255561 |
| c_none_pd | 0 / 0 | 0 / 0 | 3 / 3 | 0 / 0 | 0 / 0 | 0 / 0 | 3 / 3 |
| j_ftb | 7492538 / 0 | 5807496 / 0 | 20354643 / 0 | 35353227 / 0 | 901090 / 0 | 17883123 / 0 | 87792117 / 0 |
| j_ubtb | 437 / 0 | 167 / 0 | 1012 / 0 | 2064 / 0 | 113 / 0 | 1533 / 0 | 5326 / 0 |
| j_none_pd | 64092 / 0 | 4332 / 0 | 579325 / 0 | 1642337 / 0 | 11091 / 0 | 1614030 / 0 | 3915207 / 0 |
| r_ras_p2 | 1549671 / 4075 | 1886940 / 0 | 11663116 / 4141 | 13927287 / 2933 | 858901 / 1 | 9856794 / 4115 | 39742709 / 15265 |
| r_ras_p1 | 33 / 0 | 39 / 0 | 789 / 0 | 828 / 0 | 18 / 0 | 614 / 0 | 2321 / 0 |
| r_ras_p1ret | 0 / 0 | 0 / 0 | 10 / 0 | 130 / 0 | 0 / 0 | 53 / 0 | 193 / 0 |
| r_ftb_nopeek | 0 / 0 | 5 / 3 | 0 / 0 | 418 / 35 | 5 / 3 | 467 / 179 | 895 / 220 |
| r_none_miss | 37614 / 37614 | 2424 / 2424 | 236587 / 236587 | 523533 / 523521 | 3706 / 3706 | 595059 / 595059 | 1398923 / 1398911 |
| i_ittage | 493123 / 1839 | 711558 / 21498 | 10450033 / 49206 | 10464591 / 362723 | 569072 / 18051 | 6265445 / 199062 | 28953822 / 652379 |
| i_ftb_it_nohit | 2260 / 53 | 558 / 16 | 109792 / 10701 | 521968 / 48670 | 6418 / 1414 | 392484 / 35927 | 1033480 / 96781 |
| i_ubtb | 5 / 5 | 0 / 0 | 74 / 71 | 507 / 420 | 16 / 0 | 619 / 599 | 1221 / 1095 |
| i_none_miss | 6081 / 6065 | 292 / 292 | 167372 / 166524 | 354486 / 346614 | 2158 / 2158 | 450198 / 448603 | 980587 / 970256 |
| c_tage_sc_agree | 5579147 / 826584 | 7877212 / 1068729 | 11403706 / 1288117 | 30761888 / 4144547 | 682204 / 64845 | 14701450 / 1630227 | 71005607 / 9023049 |

MPKI per group and all, and the wrong % over all:

| reason | compress | fp | infra | int | media | web | all | wrong % (all) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| c_loop_p2 | 0.0210 | 0.1843 | 0.0494 | 0.0908 | 0.0402 | 0.1135 | 0.0889 | 1.773 |
| c_fastpath | 3.6255 | 4.2292 | 3.1737 | 4.6479 | 2.4078 | 3.7283 | 4.0197 | 3.865 |
| c_tage_prm_t1 | 0.0592 | 0.1088 | 0.0574 | 0.1906 | 0.0944 | 0.1192 | 0.1278 | 7.765 |
| c_tage_prm_t2 | 0.3715 | 0.7256 | 0.2470 | 0.5455 | 0.1151 | 0.2946 | 0.4427 | 13.103 |
| c_tage_prm_t3 | 0.4372 | 0.3327 | 0.3839 | 0.2522 | 0.0717 | 0.2066 | 0.2961 | 14.009 |
| c_tage_prm_t4 | 0.0329 | 0.0448 | 0.1051 | 0.0345 | 0.0106 | 0.0264 | 0.0458 | 15.718 |
| c_tage_alt_t0 | 0.0515 | 0.1127 | 0.1072 | 0.2532 | 0.1227 | 0.2934 | 0.1911 | 22.372 |
| c_tage_alt_t1 | 0.1052 | 0.1873 | 0.1026 | 0.2678 | 0.1028 | 0.1916 | 0.1937 | 20.869 |
| c_tage_alt_t2 | 0.3567 | 0.3320 | 0.3081 | 0.2750 | 0.0834 | 0.2426 | 0.2884 | 23.651 |
| c_tage_alt_t3 | 0.0597 | 0.0802 | 0.1379 | 0.0545 | 0.0288 | 0.0694 | 0.0745 | 15.367 |
| c_tage_t0 | 0.0501 | 0.1706 | 0.2717 | 0.5207 | 0.1786 | 0.7366 | 0.4092 | 7.623 |
| c_sc_tage_gen | 0.4863 | 0.8249 | 0.7907 | 1.2081 | 0.4657 | 1.2965 | 1.0033 | 52.326 |
| c_sc_tage_hi | 0.0988 | 0.1905 | 0.1573 | 0.2211 | 0.0684 | 0.2153 | 0.1875 | 70.452 |
| c_sc_tage_med | 0.0634 | 0.0782 | 0.0623 | 0.0684 | 0.0118 | 0.0347 | 0.0611 | 54.420 |
| c_ubtb | 0.0007 | 0.0000 | 0.0000 | 0.0004 | 0.0001 | 0.0005 | 0.0004 | 9.055 |
| c_none_miss | 0.1399 | 0.0136 | 0.8851 | 1.0772 | 0.1110 | 2.1886 | 0.9760 | 29.974 |
| c_none_pd | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 100.000 |
| r_ras_p2 | 0.0075 | 0.0000 | 0.0055 | 0.0017 | 0.0000 | 0.0055 | 0.0035 | 0.038 |
| r_ftb_nopeek | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0002 | 0.0001 | 24.581 |
| r_none_miss | 0.0693 | 0.0048 | 0.3161 | 0.3024 | 0.0462 | 0.7959 | 0.3208 | 99.999 |
| i_ittage | 0.0034 | 0.0421 | 0.0657 | 0.2095 | 0.2250 | 0.2662 | 0.1496 | 2.253 |
| i_ftb_it_nohit | 0.0001 | 0.0000 | 0.0143 | 0.0281 | 0.0176 | 0.0481 | 0.0222 | 9.365 |
| i_ubtb | 0.0000 | 0.0000 | 0.0001 | 0.0002 | 0.0000 | 0.0008 | 0.0003 | 89.681 |
| i_none_miss | 0.0112 | 0.0006 | 0.2225 | 0.2002 | 0.0269 | 0.6000 | 0.2225 | 98.946 |
| c_tage_sc_agree | 1.5239 | 2.0948 | 1.7210 | 2.3939 | 0.8081 | 2.1804 | 2.0694 | 12.708 |
| total | 6.0510 | 7.6629 | 7.4638 | 10.4501 | 4.2290 | 11.4745 | 9.1253 | |

(j_ftb, j_ubtb, j_none_pd, r_ras_p1 and r_ras_p1ret have no mispredicts;
every reason not listed has 0 decisions.)

The ten largest pacino / TAGE192 ratios (50Perc conditional MPKI). Each
reason is given as full-trace conditional MPKI; reasons that are 0 in
every row (loop_p1, ftb_tage_nordy, ftb_tage_bid, sc_ftb, none_pd,
other) are left out:

| trace | ratio | pacino | TAGE192 | loop_p2 | fastpath | prm_t1 | prm_t2 | prm_t3 | prm_t4 | alt_t0 | alt_t1 | alt_t2 | alt_t3 | t0 | sc_gen | sc_hi | sc_med | ubtb | none_miss |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| int_19 | 24.22 | 14.2437 | 0.5881 | 0.082 | 7.004 | 0.163 | 0.240 | 0.097 | 0.011 | 0.226 | 0.171 | 0.157 | 0.042 | 0.337 | 1.170 | 0.150 | 0.019 | 0.003 | 4.293 |
| infra_1 | 21.35 | 4.0274 | 0.1886 | 0.000 | 3.463 | 0.003 | 0.004 | 0.020 | 0.192 | 0.013 | 0.009 | 0.012 | 0.136 | 0.038 | 0.146 | 0.020 | 0.010 | 0.000 | 0.186 |
| int_31 | 21.08 | 9.8854 | 0.4690 | 0.000 | 8.934 | 0.026 | 0.111 | 0.171 | 0.023 | 0.020 | 0.045 | 0.152 | 0.116 | 0.022 | 0.391 | 0.086 | 0.012 | 0.000 | 0.013 |
| web_9 | 18.35 | 0.0624 | 0.0034 | 0.028 | 1.711 | 0.089 | 0.105 | 0.035 | 0.006 | 0.354 | 0.131 | 0.074 | 0.013 | 1.085 | 1.476 | 0.286 | 0.021 | 0.001 | 3.448 |
| web_24 | 13.68 | 19.6274 | 1.4348 | 0.003 | 0.948 | 0.093 | 0.089 | 0.019 | 0.002 | 0.530 | 0.096 | 0.054 | 0.006 | 1.774 | 2.353 | 0.531 | 0.011 | 0.000 | 13.664 |
| infra_12 | 12.98 | 11.6051 | 0.8941 | 0.035 | 1.888 | 0.108 | 0.120 | 0.111 | 0.081 | 0.461 | 0.116 | 0.093 | 0.080 | 1.472 | 1.955 | 0.383 | 0.015 | 0.000 | 4.883 |
| fp_6 | 12.85 | 11.3354 | 0.8824 | 0.104 | 8.717 | 0.079 | 0.415 | 0.245 | 0.058 | 0.078 | 0.149 | 0.334 | 0.183 | 0.054 | 0.825 | 0.157 | 0.053 | 0.000 | 0.007 |
| web_17 | 12.72 | 7.6909 | 0.6044 | 0.026 | 2.339 | 0.053 | 0.063 | 0.049 | 0.010 | 0.237 | 0.085 | 0.084 | 0.037 | 0.626 | 1.067 | 0.190 | 0.010 | 0.001 | 3.543 |
| infra_11 | 12.25 | 11.3698 | 0.9284 | 0.036 | 1.899 | 0.111 | 0.127 | 0.109 | 0.084 | 0.437 | 0.126 | 0.096 | 0.074 | 1.324 | 1.844 | 0.363 | 0.015 | 0.000 | 4.665 |
| web_20 | 11.69 | 20.7941 | 1.7781 | 0.016 | 2.039 | 0.124 | 0.093 | 0.016 | 0.002 | 0.808 | 0.155 | 0.073 | 0.010 | 3.238 | 3.209 | 0.673 | 0.021 | 0.001 | 9.061 |

The fast path dominates int_19, infra_1, int_31 and fp_6; the FTB miss
(none_miss) dominates web_24, web_20, infra_12, infra_11 and web_17.

### Phase 2: the fast path
- THE RULES were checked on every event of the baseline set
  (perf005_p2.csv: 105 rows, digest b48a8bbc, 215 shared columns, 0
  cells differ). Each check is 0 on every row:
  - fp_chk_conf: the conf the fast path read equals the RTL's shadow;
  - fp_chk_noshadow;
  - fp_chk_41: the fast path fires exactly when 4.1's condition holds;
  - fp_chk_use, fu_chk_rdconf, fu_chk_wrconf, fu_chk_keep,
    fu_chk_noshadow.
  The flow: every conditional resolution reaches the scheduler
  (res_cond = sched_acc = 570,601,974).
- THE ONE DEVIATION FROM 3.2: the scheduler's S5 drops 30,224,390 LOW
  updates (5.30% of res_cond). With past 131,252 and split 766,068,
  31,121,710 resolutions (5.45%) do not train the conf.
  - Define: a resolution that 3.2 says trains conf, issued to no FTB
    update (ftq_ftb_sched.sv S5, ftq_decisions.md 5.7.3).
  - Locate: int_6 2e6, 3,471 drops of 199,857.
  - Cause: two rules conflict. S5 drops LOW updates; 3.2 trains at
    every resolution.
  - Fixed by R1 (below).
- THE COST: fp_reads 828.8M, fp_fired 663.3M.
  - Fast-path mispredicts 17,527,029 = left 17,037,082 (the conf left
    saturation and re-saturated) + a fresh allocation 489,947.
  - For each "left" mispredict, the branch's resolutions since its conf
    last left saturation: 1: 3.27M, 2: 2.20M, 3: 2.10M, 4: 1.49M,
    5-8: 3.42M, 9-16: 2.37M, 17-32: 1.31M, 33-64: 0.57M, 65-256: 0.26M,
    >256: 0.05M. 51% fall within 4 trains of leaving saturation.
  - TAGE's response, present and unused, was right on 9,348,826 of them
    (53.3%) and wrong on 8,178,203.
  - On the fast path's correct decisions, TAGE was wrong 5,240,544
    times.
  - Using TAGE on all of them would net at most -9.35M + 5.24M = -4.11M
    mispredicts. This is an upper bound: TAGE's state differs if it is
    used.
- THE STUDY (perf/studies/perf005_p2_fpoff.sets, --cfg
  ftb_fastpath_en=0, perf005_p2_fpoff.csv, fp_fired 0 on every row):

| group | MPKI base | MPKI new | d | cond base | cond new | d | 50Perc cond base | 50Perc cond new | d | cycles base | cycles new | d % |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| compress | 6.0510 | 5.0164 | -1.0346 | 5.9595 | 4.9221 | -1.0374 | 4.2087 | 3.7187 | -0.4899 | 180827342 | 179844373 | -0.544 |
| fp | 7.6629 | 5.8717 | -1.7912 | 7.6154 | 5.8237 | -1.7917 | 7.8310 | 6.1198 | -1.7112 | 166202544 | 163213075 | -1.799 |
| infra | 7.4638 | 6.7952 | -0.6686 | 6.8395 | 6.1565 | -0.6831 | 6.4953 | 5.6397 | -0.8556 | 353357125 | 353635646 | +0.079 |
| int | 10.4501 | 9.9175 | -0.5326 | 9.7079 | 9.1388 | -0.5691 | 9.9353 | 9.3976 | -0.5377 | 786320824 | 795069617 | +1.113 |
| media | 4.2290 | 3.7311 | -0.4979 | 3.9133 | 3.3838 | -0.5294 | 3.7526 | 3.1211 | -0.6316 | 22349841 | 22477567 | +0.571 |
| web | 11.4745 | 11.4411 | -0.0334 | 9.7578 | 9.6586 | -0.0992 | 9.7683 | 9.7514 | -0.0169 | 413905716 | 419764010 | +1.415 |
| all | 9.1253 | 8.4459 | -0.6794 | 8.4063 | 7.6977 | -0.7087 | 8.4173 | 7.8038 | -0.6136 | 1922963392 | 1934004288 | +0.574 |

  All mispredicts fall 39,788,532 -> 36,826,082; conditional mispredicts
  36,653,625 -> 33,563,723. Of 105 rows, 71 have fewer conditional
  mispredicts and 34 more. Largest moves (conditional MPKI, full
  trace):
  - better: fp_6 -6.31, fp_13 -5.39, int_31 -3.47, fp_9 -3.40, int_2
    -3.21, fp_3 -3.10, infra_1 -2.84;
  - worse: int_16 +1.92, web_20 +1.86.

  The default stays PF-5's (ftb_fastpath_en 1); the result goes to
  Jeff.

### Phase 3: TAGE and SC, event by event
Every check runs in the harness as a column (0 expected) and prints its
first 20 deviations (TGDEV, THNW, THAB to stderr). Counts are over the
baseline set on the baseline RTL (perf005_rc.csv set p3, 105 rows; p3
equals baseline.csv on every measurement column), and on the new
baseline (Phase 5).

THE HISTORY (th_*, perf_fe.cc 2700-2875). For every lookup of an entry
on the committed path, the check computes each table's index and tag
from the PC and the committed path's global history by
tage_table_hash_rules.md, and compares them with the RTL's
(th_chk_idx_tN, th_chk_tag_tN, th_fold_tN). A second model, B, is built
from the bundles the RTL wrote (observed). There are 749,538,848
lookups; th_nolookup 0; th_chk_pc 0. Lookups with any table
mismatched, th_bad 342,776,539, by cause:
- th_bad_queued 0 (a lookup the arbiter queued).
- th_bad_rollback 67,163,212: the lookup is in a rollback cycle, where
  the folds are not yet restored (bp_history_decisions.md 5 allows one
  stale cycle).
  - Of these, th_bad_rollback_nored (added before Phase 5) counts the
    lookups whose window also holds an uncorrected bundle. On int_14
    2e6 (baseline RTL, PERF_TH_LAG_OLD=1) it is 67,485 of 67,865
    (99.4%).
  - This is why the class falls with R7 (33,032,368 under R7 alone).
- th_bad_obs_ok 275,613,327: the lookup matches model B, so the RTL's
  history is the bundles it wrote, and those differ from the committed
  path's:
  - nored 275,147,385: an uncorrected A != B bundle in the 119-bit
    window. A bundle is uncorrected when the p2/p3 view changed it with
    the successor unchanged, so no redirect fired (bp_history_decisions
    3.5).
    - Example: int_6 2e6, FTQ idx 5, k 93,517, cycle 36,491, HWRITE n 0
      (the uBTB had no slot); FREQ 36,494 s0 valid, FTB source; no
      HROLL.
    - Cause: 3.5 corrects only on a redirect. Fixed by R7.
  - corr 465,942: only corrected bundles in the window, a corrected one
    still differing from the request's final bundle.
    - Example: int_36 3e6, 52 lookups.
    - Cause: a p2 redirect corrected the bundle to the p2 view, then SC
      at p3 turned a conditional whose successor is the same either way,
      with no redirect.
    - Evidence: R7 at p2 only (set r7) raises more p2 corrections, and
      the class grows with them (th_bundle_corr 25,051 -> 106,146,
      th_bad_obs_corr -> 8,161,852). R7's p3 arm (r7b) takes both to 0
      on every row.
  - nowin 0 (unexplained, 0 expected).
- th_bad_other 0.
- The bundle classes, A (the request's prediction) against B (what the
  history holds): a_ne_b 16,541,784 =
  - p1only 16,243,651: no correction; the p2/p3 view has more branches
    than p1 wrote;
  - + corr 25,051: B corrected by a rollback;
  - + other 273,082: no correction, and B has at least A's count.
    Example: int_36 k 823,085, idx 16, cycle 539,222, HWRITE n 2 tkn 0;
    the FTB view has 1 branch and p1's uBTB an extra not-taken one, the
    same successor.

  Both no-redirect classes come from the 3.5 rule; R7 brings a_ne_b to
  0.
- THE LAG (R6): th_lag 518,139,854 lookups did not have the block just
  before them. That block's p1 bundle write is in the same cycle as the
  next block's p0 lookup (bp_arb_spec.md 3.1-3.2, fe_decisions.md 1).
  On int_6 it is 264,417 of 337,325. The rule is followed; R6 is
  proposed.
- TWO CHECK DEFECTS were found and fixed on the way (in the harness, not
  the RTL):
  - (1) int_36 k 2161, idx 33, lookup cycle 3275: RTL T1 fold ff, model
    bf. The RTL's GHR after the 3274 rollback is feff, which is correct.
    The check had read idx 32's bundle after the FTQ wrapped and the
    entry was allocated again (prev_wc 3339 > lookup cycle). Fixed by
    snapshotting each entry's bundles at its commit (th_snapA/B).
  - (2) The window bound for a lagging lookup (nowin 480 -> 0).

THE READ (tr_*): 12,148,706,930 RAM reads were checked against the
harness's shadow of every table: tr_chk_read 0; tr_collide 0 (no read
shared a cycle with a write of its RAM). One defect was found and fixed,
in the check: T0's control bits are packed as {5'b0, ctr, 1} (tage.sv
208-209).

THE RESPONSE: c_ftb_tage_nordy = c_ftb_tage_bid = 0 on every row. No
TAGE response is missing for an entry on the path, so none is checked
against bp_arb_spec.md 4.5 and no defect is possible there.

THE UPDATE AND THE ALLOCATION (tu_*), re-derived from the probed state
at every update (569,610,681 updates, 30,439,644 TAGE mispredicts):
tu_chk 0, tu_chk_we 0, tu_chk_addr 0, tu_chk_ctr 0, tu_chk_use 0,
tu_chk_alc 0, tu_chk_uaon 0. tu_chk_uaon re-derives the use_alt_on_na
counter by tage_cntrl_uaon_update_rules.md 75-77 and 138; it was added
in this phase when R3 tripped no check. Counted outcomes:
- allocations made 26,871,877 (resolved not taken 14,110,629). Refused:
  - no longer table (the provider is T4) 3,193,360;
  - useful bits (no table above the provider with u_eff 0) 374,407;
  - other 0.
- tu_alloc_dup 97,289: the allocated entry already held the same tag
  (an allocation into a row that a second update had just written for
  the same branch).
  - Example (int_14 2e6, tree harness, TGNOTE): updates at cycles 7479
    and 7481, T2 idx 687, lookup PC 4480b0, tag 4e.
  - Two mispredicts of one branch were in flight. Both missed T2 at
    predict, so both allocate the same row; the second finds 4e09
    already there.
- tu_gone_prm 1,090 / tu_gone_alt 172: at the update, the trained entry
  no longer holds the tag the prediction read (it was replaced between
  predict and resolve).
- tu_stale_prm 2,542,809 / tu_stale_alt 871,000: the tag holds but its
  counter moved since the read (another update of the same entry came
  in between).
- Both follow from training at resolve with the metadata of the predict
  (tage_cntrl_ctr_update_rules.md: the CTR written is the meta's CTR
  stepped). They are not deviations. Examples (int_14 2e6, TGNOTE):
  - gone_prm: update cycle 396,264, T4 idx 6a3; the lookup of PC
    7ff800008523d7c at cycle 396,150 read tag 30; the row is now c509
    (tag c5).
  - stale_prm: update cycle 6,726, T1 idx 4f0; the lookup of PC 44d0b8
    at cycle 6,716 read CTR 5; the row is now 780d (CTR 6: an update
    came in between).
- providers: primary tagged 172,558,962, alternate tagged 64,852,500,
  alternate T0 21,099,969, T0 alone 311,099,250.

THE SC (sp_*, su_*): 739,575,476 answers and 569,610,622 updates.
- Checks: sp_chk_sum 0, sp_chk_dec 0, su_chk_wr 0, su_chk_wd 0,
  su_chk_glob 0.
- The corners consulted: HIGH chose SC 5,267,605 times and TAGE
  3,090,067; MED chose SC 1,329,523 and TAGE 226,668.
- sc_thr_max 109: the largest threshold seen, below 511. SC_THRSH_MAX is
  never reached, so its 10-bit THR_MAX_U wrap (sc_cntrl.sv 147-148) is
  not exercised.

THE SC AGAINST sc_decisions.md AND cbp2016 (tools/cbp2025/entries/
jimenez/cbp2016_tage_sc_l.h):

| item | pacino | cbp2016 | same? |
|---|---|---|---|
| sum terms | ST0-ST4 (2c+1) + tage_extd_ctr, sc_cntrl.sv 304-310 | Bias, BiasSK, BiasBank (2c+1) + GGEHL, PGEHL, L/S/T GEHL, IMLI, 1059-1087; no TAGE counter term | no |
| table index | PC ^ fold, sc_table.sv 130-131; no TAGE input | bias index with pred_inter and LowConf/HighConf, 1016-1029; GGEHL (PC << 1) + pred_inter, 1073 | no (R5 adds TAGE's direction to ST0-ST3) |
| SC direction | sum >= 0, sc_cntrl.sv 314 | SCPRED = LSUM >= 0, 1089 | yes |
| threshold | one global, TC +-1 steps, sc_cntrl.sv 466-482 | (updatethreshold >> 3) + Pupdatethreshold[PC] (+ VARTHRES), 1091-1103 | no (no per-PC part) |
| HIGH corner | tage_strong and abs < thr/2 -> choose_hi, sc_cntrl.sv 335-338 | HighConf: abs < THRES/4 -> TAGE; < THRES/2 -> SecondH, 1107-1130 | no (no TAGE-only band) |
| MED corner | tage_medium and abs < thr/4 -> choose_med, sc_cntrl.sv 339-342 | MedConf and abs < THRES/4 -> FirstH, 1107-1130 | yes |
| general differ | SC, sc_cntrl.sv 343-346 | SC, 1107-1130 | yes |
| chooser training | sc_pred_tkn (the final direction) == resolved, only when consulted, sc_cntrl.sv 485-494; sc_decisions.md 10 | pred_inter == resolveDir when pred_inter != SCPRED, in the HighConf / MedConf bands, 1295-1311 | no (R2) |
| table update | sc_wrong or abs < thr, all tables toward resolved, sc_cntrl.sv 380-401 | SCPRED != dir or abs < THRES, 1313-1363 | yes |
| conf definition | the post-mux counter (provider or alternate): strong 000/111, weak 011/100, medium the other four; tage_cntrl.sv 562-569 | the HitBank counter (the longest match even when the alternate is used): HighConf abs(2c+1) >= 7, MedConf == 5 (001/110 only), LowConf == 1; 992-996 | no (the source counter and the medium set) |
| weights | none | VARTHRES weights WB/WG/WP..., 1313+ | no |

SC's overrides right and wrong per group (perf005_rc.csv set p3, the
baseline RTL):

| group | overrides | right | wrong | wrong % | gen n/wrong | hi n/wrong | med n/wrong | ftb n/wrong |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| compress | 669410 | 317699 | 351711 | 52.54 | 525691/263762 | 80028/53568 | 63691/34381 | 0/0 |
| fp | 1064630 | 506692 | 557938 | 52.41 | 842477/420836 | 152102/97200 | 70051/39902 | 0/0 |
| infra | 1376873 | 620651 | 756222 | 54.92 | 1112732/591824 | 173056/117743 | 91085/46655 | 0/0 |
| int | 4764200 | 2171399 | 2592801 | 54.42 | 4004651/2091567 | 542197/382736 | 217352/118498 | 0/0 |
| media | 83383 | 39574 | 43809 | 52.54 | 74607/37370 | 7100/5490 | 1676/949 | 0/0 |
| web | 2052123 | 895807 | 1156316 | 56.35 | 1800411/969408 | 206190/160976 | 45522/25932 | 0/0 |
| all | 10010619 | 4551822 | 5458797 | 54.53 | 8360569/4374767 | 1160673/817713 | 489377/266317 | 0/0 |

and on the new baseline (perf005_baseline.csv, R2 + R5 among the six):

| group | overrides | right | wrong | wrong % | gen n/wrong | hi n/wrong | med n/wrong | ftb n/wrong |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| compress | 547919 | 294815 | 253104 | 46.19 | 504564/231036 | 26/15 | 43329/22053 | 0/0 |
| fp | 873844 | 443106 | 430738 | 49.29 | 843816/415515 | 4259/2287 | 25769/12936 | 0/0 |
| infra | 748309 | 405701 | 342608 | 45.78 | 680716/308817 | 30378/14984 | 37215/18807 | 0/0 |
| int | 2280316 | 1180066 | 1100250 | 48.25 | 2222261/1069757 | 1403/798 | 56652/29695 | 0/0 |
| media | 31954 | 16030 | 15924 | 49.83 | 31087/15446 | 23/14 | 844/464 | 0/0 |
| web | 688902 | 337087 | 351815 | 51.07 | 683982/349050 | 358/234 | 4562/2531 | 0/0 |
| all | 5171244 | 2676805 | 2494439 | 48.24 | 4966426/2389621 | 36447/18332 | 168371/86486 | 0/0 |

(R2 alone, all: 8,488,067 overrides, 52.46% wrong; R5 alone: 7,118,141,
48.40% wrong.)

DEFECTS: none. Every event follows its written rule, on every row. The
rule files were read before any case was called a defect:
- sc_decisions.md 10 (547-561) trains the chooser on sc_pred_tkn;
- tage_cntrl_uaon_update_rules.md 75-77 and 138 gate on the final
  provider's CTR;
- tage_cntrl_alloc_rules.md 82 allocates at 100.

The cost of each rule is measured below as a RULE CHANGE FOR ACCEPTANCE.
(An earlier note of this session read R3 as the written rule; reading
the rule file corrected it before any result was written.)

### The rule changes for acceptance (Block 1), each measured alone
Each was built in a scratch copy of the baseline tree with that change
only (scratchpad rc_rN) and run as the baseline set over the 105 traces,
rows against perf/studies/baseline.csv. Conditional MPKI at 50Perc is
the mean of the per-trace 50PercMpkiCond (PF-10); "cond" is the totals.

| change | MPKI all | cond all | 50Perc cond | d 50Perc | cycles d % | cond mispredicts fewer / more | in the tree |
|---|---:|---:|---:|---:|---:|---|---|
| baseline | 9.1253 | 8.4063 | 8.4173 | | | | |
| R1 sched no drop | 9.1376 | 8.4181 | 8.4303 | +0.0129 | +1.771 | 59 / 44 (103 moved) | yes |
| R2 chooser on SC's own | 8.9843 | 8.2716 | 8.2780 | -0.1394 | -0.403 | 104 / 1 | yes |
| R3 UAON gate on primary | 9.1268 | 8.4083 | 8.4222 | +0.0049 | +0.008 | 46 / 59 | NO |
| R4 alloc CTR toward resolved | 9.0584 | 8.3391 | 8.3441 | -0.0733 | -0.111 | 94 / 11 | yes |
| R5 SC index with TAGE dir | 8.7998 | 8.0920 | 8.0801 | -0.3373 | -0.891 | 96 / 9 | yes |
| R6 p0 fold bypass | 9.0675 | 8.3511 | 8.3635 | -0.0538 | -0.098 | 87 / 18 | yes |
| R7 p2 only (first build) | 8.9966 | 8.2786 | 8.2830 | -0.1344 | +0.651 | 91 / 10 (102 moved) | replaced |
| R7 p2 + p3 | 8.9906 | 8.2727 | 8.2777 | -0.1396 | +0.663 | 91 / 11 (104 moved) | yes |
| all six (new baseline) | 8.4618 | 7.7547 | 7.7283 | -0.6890 | +1.033 | 102 / 3 (105 moved) | |

Per group, the change in 50Perc conditional MPKI (each alone):

| group | R1 | R2 | R3 | R4 | R5 | R6 | R7 p2+p3 |
|---|---:|---:|---:|---:|---:|---:|---:|
| compress | -0.0096 | -0.0430 | +0.0005 | -0.0041 | -0.0904 | -0.0122 | -0.0184 |
| fp | +0.1187 | -0.0829 | +0.0172 | -0.0341 | -0.1051 | -0.0664 | -0.0274 |
| infra | +0.0036 | -0.1157 | +0.0074 | -0.0668 | -0.3378 | -0.0515 | -0.1378 |
| int | -0.0018 | -0.1532 | +0.0004 | -0.0700 | -0.3711 | -0.0506 | -0.1552 |
| media | -0.0374 | -0.0563 | +0.0002 | -0.0536 | -0.1576 | -0.0744 | -0.2577 |
| web | -0.0026 | -0.2070 | +0.0050 | -0.1273 | -0.5173 | -0.0627 | -0.1981 |
| all | +0.0129 | -0.1394 | +0.0049 | -0.0733 | -0.3373 | -0.0538 | -0.1396 |

#### R1. The FTB update scheduler drops no update
- REPLACES (ftq_decisions.md 5.7.3): "S5 Anything still remaining is
  DROPPED if LOW." and "S6 A HIGH update is NEVER dropped. If accepting
  one would force S5 to drop a HIGH, the FTQ instead deasserts
  ftq_bkend_rsv_rdy for that channel and the backend holds it."
- NEW RULE: S5/S6 become "No update is dropped. A channel whose update
  would fall outside the capacity deasserts ftq_bkend_rsv_rdy, LOW or
  HIGH, and the backend holds it." (ftq_ftb_sched.sv 27-30, 201.)
- WHY: ftb_confidence_override_rules.md 3.2 trains the FTB conf at
  every resolution.
  - Phase 2's check found S5 dropping 30,224,390 of 570,601,974
    conditional resolutions (5.30%, all LOW). Each is a conf step that
    3.2 requires: the two rules conflict, and S5 broke 3.2 on 5.3% of
    resolutions.
  - R1 makes 3.2 hold: drop 0 and acc = res_cond on every row of
    perf005_r1.csv.
- REJECTED: keep S5 and amend 3.2 to "at every resolution the scheduler
  issues". That keeps the cycles, but it leaves the fast path's conf a
  sample of the outcomes. That counter is the one Phase 2 found deciding
  44% of all mispredicts.
- COST, MEASURED: accuracy +0.0129 at 50Perc (worse), cycles +1.771%.
  - The cycles are the backpressure. First divergence: fp_1 (fd.py, 1e6
    instructions) line 206, C k161, cycle 559 -> 560.
  - In cycle 558 two conditional resolutions arrive together (k158 pos
    6 and k161 pos 12 of FTQ idx 25). The base resolves both, and its
    scheduler drops one by S5. R1 resolves k158, and k161 waits for
    upd_rdy until 559. So commit moves a cycle, and the history and the
    updates after it move with it.
  - fp_9 (line 641, k478, 783 -> 784) and infra_7 (line 246, k178,
    581 -> 582) are the same event.
  - The accuracy moves are those shifted updates. fp is the group that
    loses (+0.12), from fp_9 +0.63, fp_6 +0.59 and fp_1 +0.38.
- COULD BREAK: a backend that cannot hold a LOW update; the FTQ's
  backpressure properties.
  - TEST: tb_ftq_ftb_sched D1 (two LOW updates in one cycle with the
    skid full: the second is held, not dropped) and
    ftq_ftb_sched_assert P6 a_ftb_never_dropped.
  - Fails before at both slot counts (D1 2 checks, P6). Passes after:
    PASS=68 FAIL=0 at 2 slots and _1slot.
- In the tree. Jeff's choice between R1 and the amended 3.2.

#### R2. The SC chooser trains on SC's own direction
- REPLACES (sc_decisions.md section 10, 547-548): "logic sc_pred_match =
  sc_upd_inp.sc_pred_meta.sc_pred_tkn == sc_upd_inp.resolved_taken;"
  (sc_pred_tkn is the FINAL direction, which in a corner the chooser
  itself picked).
- NEW RULE: sc_pred_match = (sc_lcl_pred_tkn == resolved_taken), SC's
  own sum direction (sc_cntrl.sv 485-495). The cbp2016 reference trains
  its corner counters only when SC's sum and TAGE disagree, and on which
  of the two was right, never on the final direction:
  tools/cbp2025/entries/jimenez/cbp2016_tage_sc_l.h 1295-1311, "if
  (pred_inter != SCPRED) ... ctrupdate (SecondH, (pred_inter ==
  resolveDir), CONFWIDTH)", and FirstH the same.
- WHY: with the final direction the counter is circular. When the
  chooser picked TAGE, sc_pred_tkn is TAGE's, so a correct TAGE counts
  as "SC right" and moves the chooser toward SC.
  - Phase 3's HIGH corner chose SC 5,267,605 times against TAGE
    3,090,067, and its SC overrides were wrong 70.45% of the time
    (817,713 of 1,160,673).
  - Under R2 the HIGH corner's overrides fall from 1,160,673 to 24,810,
    and the MED corner's from 489,377 to 61,141.
- REJECTED: remove the two corners (always SC on a disagreement). The
  general SC override is itself wrong 52.3% of the time (Phase 1), so
  that would add the corners' errors, not remove them.
- COST: none. 50Perc -0.1394, cycles -0.403%, 104 of 105 traces better.
- COULD BREAK: the corner counters' saturation and reset; the SC
  update's global next state.
  - TEST: tb_sc_cntrl TC7, the R2 cases: HIGH and MED corner, TAGE right
    and TAGE wrong, the counter expected from sc_lcl_pred_tkn.
  - Fails before at both slot counts (4 R2 checks + the HIGH saturation
    check); passes after.
  - The harness's re-derivation (su_chk_glob) models R2 and is 0 on the
    new baseline.

#### R3. The UAON gate on the primary's counter (NOT in the tree)
- WOULD REPLACE (tage_cntrl_uaon_update_rules.md 75-77): "tage_pred_weak:
  set from the final provider CTR after the UAON mux has selected
  primary or alternative. Asserted when that CTR is 3'b011 or 3'b100.
  This is the UAON update gate."
- NEW RULE (proposed): the gate is the PRIMARY's counter weak
  (tage_prm_ctr 011 or 100), as in cbp2016 (entries/jimenez/
  cbp2016_tage_sc_l.h 1403-1418: "bool PseudoNewAlloc = (abs (2 *
  gtable[HitBank][GI[HitBank]].ctr + 1) <= 1); ... if (PseudoNewAlloc)
  ... if (LongestMatchPred != alttaken) ctrupdate (use_alt_on_na
  [INDUSEALT], (alttaken == resolveDir), ALTWIDTH)", where HitBank is
  the longest match).
- WHY TRIED: the gate decides whether use_alt_on_na learns. With the
  post-mux counter, it learns from the alternate's weakness when the
  alternate was used.
- MEASURED: +0.0049 at 50Perc (worse), cycles +0.008%, 46 better / 59
  worse. The rule as written costs nothing to keep, so it stays.
  - Reported with its cost; not built into the tree.
  - Its test edit (tb_tage_manual_tasks.svh) was taken out again.

#### R4. An allocated entry starts weak toward the resolved direction
- REPLACES (tage_cntrl_alloc_rules.md 82): "CTR = 3'b100 (weakest
  taken)".
- NEW RULE: "CTR = resolved_taken ? 3'b100 : 3'b011 (weak toward the
  resolved direction)". tage_cntrl.sv 859-876 (alc_upd_comb).
- WHY: an allocation follows a mispredict, whose resolved direction is
  known.
  - With 100, every entry allocated for a not-taken branch predicts
    taken on its first use.
  - cbp2016 allocates weak toward the outcome (entries/jimenez/
    cbp2016_tage_sc_l.h 1460 and 1505: "gtable[i][GI[i]].ctr =
    (resolveDir) ? 0 : -1;").
  - 14,110,629 of 26,871,877 allocations (52.5%) were for a resolved
    not-taken branch (tu_alloc_ntk).
- REJECTED: allocate at the predicted direction's opposite strength
  (010/101). That is one more step to retrain when the allocation was
  noise.
- COST: none in the harness. 50Perc -0.0733, cycles -0.111%, 94 better
  / 11 worse.
- SIDE EFFECT (found by tools/regress.sh): fe_top's t0_uaon program, an
  LFSR-seeded stimulus, no longer reached its case at two slots. Fixed:
  the program is now a directed stimulus (see Test Case Results).
- COULD BREAK: the CTR update rows that start from a fresh entry; the
  re-prediction after an allocation.
  - TEST: tb_tage upd_alloc_tst now allocates both ways: resolved not
    taken -> AA07, resolved taken -> BB09.
  - 14 allocation checks expect ..07 for a not-taken allocation:
    rt_mispredict_alloc, alloc_t0_provider, alloc_no_consecutive,
    aging_age1/age2, alc_end_to_end, alc_trigger_gating A,
    alc_which_table, alc_consec_skip, alc_pre_hashed_idx, alc_contents
    A/B, alc_ram_isolate.
  - Fails before (33 FAIL lines) at both slot counts; passes after.
    sim_tage_fast, sim_tage_tasks and sim_tage_manual pass.
  - The harness's re-derivation (tu_chk_alc) models R4 and is 0 on the
    new baseline.
  - The twin allocates the same way (PACINO_TWIN_ALLOC_100=1 gives
    100).

#### R5. SC ST0-ST3 indexed with TAGE's direction
- REPLACES (sc_table_hash_rules.md, Function, 87-89): "hashed_index =
  THIS_INDEX_BITS'(inp_pc_p2[s] ^ fh_idx_ext);"
- NEW RULE: "hashed_index = THIS_INDEX_BITS'({inp_pc_p2[s][VA_WIDTH-2:1],
  tage_pred_tkn} ^ fh_idx_ext)". The PC moves up one bit, and index bit
  0 is the slot's TAGE direction. ST4 (BrIMLI) is unchanged. sc.sv
  326-337 (w_tk_pc_p2), the gen_st instance's inp_pc_p2.
- WHY: cbp2016 indexes its bias tables and its global-history GEHL with
  TAGE's prediction (entries/jimenez/cbp2016_tage_sc_l.h 1016-1029:
  get_bias_index, get_biassk_index and get_biasbank_index, each "+
  pred_inter" with the confidence; 1073: "Gpredict ((PC << 1) +
  pred_inter, hist_to_use.GHIST, ...)").
  - So its counters learn when TAGE is wrong for this branch, rather
    than the branch's bias.
  - In pacino, TAGE enters only as tage_extd_ctr (sc_cntrl.sv 309-310),
    and SC's overrides were wrong 54.53% of the time (Phase 1).
  - Under R5 they are wrong 48.40% of the time and fall from 10,010,619
    to 7,118,141.
- REJECTED: add cbp2016's bias tables beside ST0-ST3. That is more
  storage, and NOT IN THIS TASK: no table is enlarged.
- COST: none. 50Perc -0.3373, cycles -0.891%, 96 better / 9 worse.
- COULD BREAK: the update index (sc_upd_idx is captured at predict, so
  the update uses the same index); the index width.
  - TEST: tb_sc TC3 and the pred_idx reference ({PC[VA-2:1],
    tage_pred_tkn}), with a check of the reference itself (idx[0][0][0]
    is 1); tb_bp_cluster's fold monitor (SC FOLD ST0-ST3 at p2).
  - Fails before at both slot counts (TC3's sum and captured index; FOLD
    sc ST0-ST3); passes after.

#### R6. The p0 lookup reads the history with the previous block in it
- REPLACES (bp_arb_spec.md 3.1, fe_decisions.md 1): "p0 Inputs
  presented to RAMs (flopped). PC hash, folded history available."
  - The RTL read the REGISTERED folds (bp_history.sv folded = fh_r),
    and the block before writes its bundle at p1 in the same cycle
    (bp_cluster.sv p1 write). So a back-to-back lookup lacked its
    predecessor's bits.
  - Measured: 78% of int_6's lookups (264,417 of 337,325), and
    518,139,854 of 749,538,848 checked lookups over 105 traces (th_lag),
    read a history without the previous block.
- NEW RULE: "p0: folded history available, including the bundle the p1
  block writes in the same cycle (no rollback in that cycle)."
  - A new bp_history output, folded_byp: the folds with this cycle's
    bundle applied by the same fold steps as the update (bp_history.sv
    77, 552-571).
  - It feeds the TAGE and ITTAGE p0 lookups and the p1 staging of the SC
    folds and the PHR (bp_cluster.sv 347, the w_folded_byp users).
  - A port change: bp_history_interfaces.md gains folded_byp.
- WHY: a block's prediction should see every older block. CBP's model
  and cbp2016 update the history before the next prediction.
- REJECTED: delay the p0 lookup one cycle (a bubble per block).
- COST: none on the totals (50Perc -0.0538, cycles -0.098%). 18 traces
  are worse, web_7 most (+0.22).
  - The combinational path: fold_all_step for NUM_PRED_SLOTS bundles in
    front of the index hash. Timing is not checked here (Verilator).
  - In a rollback cycle the bypass is off. Measured on int_14 2e6 (tree,
    the R6 history model against the old one):
    - the rollback class is 83,522 lookups, of which 76,657 (91.8%) are
      lookups whose predecessor wrote in that rollback cycle;
    - those read a fold one block stale, which bp_history_decisions.md 5
      allows;
    - the rest (6,865) are the stale fold of the rollback itself (R7
      alone: 5,758).
  - This is why the new baseline's rollback class is 59,484,908 against
    R7 alone's 33,032,368.
- COULD BREAK: a rollback cycle (the bypass is off: folded_byp =
  folded); the fold of a bundle of NUM_PRED_SLOTS.
  - TEST: tb_bp_history TC20, over every bundle size 0..NPS and every
    taken pattern:
    - folded_byp before the edge equals folded after it;
    - an empty bundle leaves them equal;
    - a rollback cycle has no bypass.
  - TEST: tb_bp_cluster's fold monitor. The model now applies the
    cycle's bundle at p0 and in the p1 SC/PHR staging.
  - Before: tb_bp_history does not build (no folded_byp port), and the
    monitor fails. After: pass at both slot counts.
  - The harness's history check models R6 (th_lag 0 on the new
    baseline).

#### R7. A history-only redirect when the p2 or p3 bundle differs
- REPLACES (bp_history_decisions.md 3.5): "DECISION: the history is
  CORRECTED on a redirect." (and only then).
- NEW RULE: "The history is corrected on a redirect, and also when the
  bundle the block's p2 view (FTB, TAGE) or p3 view (SC) forms differs
  from the bundle it wrote at p1 while its successor is unchanged. The
  stage raises a slot-0 redirect to the block's own successor, so the
  rollback writes that stage's bundle (rb_corr_mux) and the younger
  block is fetched again."
  bp_cluster.sv 1192-1224 (hdiff_p2), 1366-1372 (p2), 1496+ (the p3
  arm).
- WHY: Phase 3's history check found 275,147,385 lookups (37% of those
  checked) whose 119-bit window held an uncorrected bundle. Either the
  FTB had a branch the uBTB lacked, or TAGE (p2) or SC (p3) turned a
  conditional whose target equals the block's successor either way.
  - Example: fp_1 block fffff0d55ef8: s0 conditional pos 2, s1 indirect
    pos 10, both to fffff0d55e84.
  - No redirect fired, so 3.5 never corrected them. With R7,
    th_bad_obs_nored and th_bundle_a_ne_b are 0 on every row.
- The first build raised it at p2 only and left 3,027,297 (fp_1: SC at
  p3 turning a conditional, src 4). The p3 arm closes it (fp_1 2e6:
  a_ne_b 0, nored 0).
- REJECTED: correct the history at p2/p3 without a refetch (write the
  bundle and re-fold in place). The younger block's p0 lookup has
  already read the wrong folds, so its prediction stays wrong; it would
  also need a new port into bp_history.
- COST, MEASURED: accuracy -0.1396 at 50Perc; cycles +0.663% (p2
  overrides 142,139,518 -> 164,414,136; p3 16,457,108 -> 16,395,403).
  First divergence (fd.py, base p3_s2 against r7_s2, 1e6):
  - web_25 line 430: cycle 858, idx 1, slot 1, pos 8, p2 0, p3 1. SC
    turned it, and the successor is the same. The base fetches idx 2 at
    859; under R7, p3 redirects and idx 2 is fetched again.
  - int_19 line 2677: idx 12 reaches p3 at 4566, not 4565. It is
    re-predicted on the corrected history after an R7 p2 redirect of
    idx 11, and its p2 direction differs (1 -> 0).
  - infra_12 line ~2428: idx 20 a cycle later, the same event.
- SIDE EFFECT (found by tools/regress.sh): fe_top's sc_nored program
  required the case R7 removes (an SC reversal at p3 with no p3
  redirect). Fixed: the program now expects the R7 redirect (see Test
  Case Results; TD#205 in Deferred Work).
- COULD BREAK: a p2/p3 redirect that is not a history correction
  (target, type); the J and I groups that build checkpoints with no
  redirect.
  - TEST: tb_bp_cluster E2e:
    - p2: an FTB not-taken conditional the uBTB lacked, target = the
      successor. p2 redirects to the successor, and the rollback carries
      {NT}.
    - p3: SC turns it taken. p3 redirects, and the rollback carries {T}.
  - TEST: I1 now expects the R7 redirect to the successor.
  - E2c builds its p3-only case by training the uBTB (s_train), so p1
    and p2 agree. j_alloc gives the FTB the uBTB's second branch at 2
    slots.
  - Fails before (E2e 4 checks, I1) at both slot counts. Passes after
    (PASS 2163 / 1580).

### Phase 4: the software twin
- perf/src/twin/ (pacino_twin.h, cond_branch_predictor_interface.cc,
  sources.mk) is a CBP predictor implementing pacino's TAGE alone:
  - T0 and the four tagged tables at bp_defines_pkg.sv's parameters;
  - the counter, useful and allocation rules (R4 included);
  - aging at 2^18;
  - CBP's immediate update; no SC, loop or FTB.
  Its index and tag functions are perf/src/harness/tage_hash.h, the code
  Phase 3's history check runs on the RTL. It is built by make -C perf
  twin and run by python3 tools/perf_rerun.py --plan full --cbp-bin
  perf/build/twin_cbp/bin --only pacino_twin.
- CHECK: all 105 runs Pass in the CBP framework, and their Instr, NumBr,
  50PercInstr and 50PercNumBr equal perf/cbp2025_rv_counts.csv: 0 rows
  fail (perf/studies/perf005_twin.csv).
- Conditional MPKI, the mean of the traces (pacino at the old
  baseline):

| group | TAGE192 50P | twin 50P | pacino 50P | TAGE192 full | twin full | pacino full |
|---|---:|---:|---:|---:|---:|---:|
| compress | 2.7229 | 3.4559 | 4.2087 | 2.7556 | 3.5259 | 4.3468 |
| fp | 4.1088 | 5.8057 | 7.8310 | 3.9039 | 5.5225 | 7.5648 |
| infra | 2.3625 | 3.8545 | 6.4953 | 2.5309 | 4.0448 | 6.6776 |
| int | 4.1627 | 6.6547 | 9.9353 | 4.2701 | 6.6159 | 9.8539 |
| media | 0.8115 | 1.5721 | 3.7526 | 0.9868 | 1.6988 | 3.9110 |
| web | 3.1748 | 5.4543 | 9.7683 | 3.3816 | 5.6696 | 10.2112 |
| all | 3.3992 | 5.3802 | 8.4173 | 3.4958 | 5.4212 | 8.5072 |

  Per trace (50Perc / full):

| trace | TAGE192 50P | twin 50P | pacino 50P | TAGE192 | twin | pacino |
|---|---:|---:|---:|---:|---:|---:|
| compress/compress_0 | 3.2007 | 4.5110 | 6.8251 | 3.2057 | 4.5005 | 6.6812 |
| compress/compress_1 | 1.8079 | 2.2079 | 2.4957 | 1.6524 | 2.0935 | 2.3521 |
| compress/compress_2 | 1.6187 | 2.0025 | 2.3251 | 1.4562 | 1.8575 | 2.1471 |
| compress/compress_3 | 7.6221 | 9.5058 | 10.5561 | 8.1425 | 10.1112 | 11.3055 |
| compress/compress_4 | 1.6639 | 2.0467 | 2.5163 | 1.7967 | 2.2751 | 2.6573 |
| compress/compress_5 | 1.6833 | 2.1598 | 2.4986 | 1.8919 | 2.4247 | 2.7138 |
| compress/compress_6 | 1.6635 | 2.0799 | 2.4640 | 1.8660 | 2.3746 | 2.6650 |
| compress/compress_7 | 2.5228 | 3.1339 | 3.9884 | 2.0337 | 2.5702 | 4.2527 |
| fp/fp_0 | 3.3103 | 3.8859 | 3.8832 | 3.2251 | 3.8088 | 3.7445 |
| fp/fp_10 | 1.8938 | 3.4285 | 3.5284 | 1.9846 | 3.5133 | 3.6187 |
| fp/fp_11 | 0.5855 | 1.5502 | 1.2692 | 0.6081 | 1.6613 | 1.2715 |
| fp/fp_12 | 1.0234 | 2.0017 | 2.2401 | 1.1719 | 2.0994 | 2.3150 |
| fp/fp_13 | 12.3958 | 15.7477 | 20.2395 | 12.4316 | 15.7478 | 20.1962 |
| fp/fp_1 | 15.6148 | 17.6882 | 17.4463 | 15.5596 | 17.5998 | 17.3769 |
| fp/fp_2 | 2.6011 | 3.3986 | 4.8842 | 2.5558 | 3.3680 | 4.7954 |
| fp/fp_3 | 1.9756 | 3.4801 | 7.1726 | 1.9518 | 3.3478 | 7.0552 |
| fp/fp_4 | 0.4330 | 0.8511 | 1.6780 | 0.5609 | 0.9605 | 2.2610 |
| fp/fp_5 | 0.9295 | 1.1322 | 1.0503 | 0.9363 | 1.1445 | 1.0467 |
| fp/fp_6 | 0.8824 | 4.8632 | 11.3354 | 0.9602 | 4.9222 | 11.4575 |
| fp/fp_7 | 0.8573 | 2.7514 | 8.0714 | 1.0261 | 2.7424 | 8.0295 |
| fp/fp_8 | 10.5428 | 12.6331 | 13.2941 | 7.4675 | 9.0770 | 9.5390 |
| fp/fp_9 | 4.4784 | 7.8678 | 13.5419 | 4.2151 | 7.3224 | 13.1995 |
| infra/infra_0 | 1.2820 | 2.9633 | 4.5846 | 1.2489 | 2.8701 | 4.5875 |
| infra/infra_10 | 4.5419 | 6.5580 | 7.7299 | 5.1428 | 6.9272 | 7.5707 |
| infra/infra_11 | 0.9284 | 2.5159 | 11.3698 | 0.9899 | 2.6515 | 11.3104 |
| infra/infra_12 | 0.8941 | 2.6126 | 11.6051 | 0.9741 | 2.8059 | 11.8013 |
| infra/infra_13 | 3.2824 | 5.0909 | 8.1294 | 4.0061 | 5.8930 | 7.9838 |
| infra/infra_14 | 4.5203 | 6.5294 | 7.8024 | 5.2062 | 6.9650 | 7.7473 |
| infra/infra_15 | 5.6115 | 8.1989 | 9.1934 | 8.2150 | 10.3247 | 10.5352 |
| infra/infra_1 | 0.1886 | 0.9267 | 4.0274 | 0.3459 | 1.0726 | 4.2538 |
| infra/infra_2 | 0.2241 | 1.0195 | 1.9670 | 0.4080 | 1.1150 | 2.1315 |
| infra/infra_3 | 0.9553 | 2.3609 | 3.5248 | 1.0328 | 2.3183 | 3.6113 |
| infra/infra_4 | 2.4185 | 4.1102 | 7.4511 | 2.4035 | 4.2018 | 7.5540 |
| infra/infra_5 | 3.1395 | 3.9904 | 4.0343 | 2.2032 | 3.2376 | 3.2459 |
| infra/infra_6 | 1.1170 | 2.1382 | 4.1818 | 1.1856 | 2.2143 | 4.3855 |
| infra/infra_7 | 0.8066 | 2.7004 | 8.0820 | 1.4196 | 3.7620 | 8.3196 |
| infra/infra_8 | 1.2431 | 2.6824 | 2.4433 | 1.2537 | 2.6650 | 2.4515 |
| infra/infra_9 | 6.6474 | 7.2743 | 7.7983 | 4.4591 | 5.6920 | 9.3522 |
| int/int_0 | 4.8582 | 6.2085 | 6.5067 | 4.9846 | 6.3112 | 6.5809 |
| int/int_10 | 0.4970 | 0.9185 | 3.0000 | 0.5246 | 0.9266 | 2.9574 |
| int/int_11 | 4.0718 | 5.6493 | 7.1919 | 4.0459 | 5.5672 | 7.1203 |
| int/int_12 | 0.8027 | 1.4416 | 2.3964 | 0.4223 | 1.0293 | 1.5111 |
| int/int_13 | 0.8062 | 2.1920 | 2.8093 | 0.8743 | 2.0573 | 2.8310 |
| int/int_14 | 0.3113 | 1.2164 | 3.2503 | 0.3773 | 1.2796 | 3.2165 |
| int/int_15 | 0.8845 | 1.0847 | 2.6685 | 0.4687 | 0.5948 | 1.9690 |
| int/int_16 | 5.6066 | 12.0859 | 19.7671 | 5.5511 | 12.2350 | 20.0553 |
| int/int_17 | 3.9103 | 8.5904 | 16.6417 | 4.6923 | 9.4114 | 17.2290 |
| int/int_18 | 0.6019 | 2.2384 | 3.2712 | 0.7665 | 2.1673 | 3.1130 |
| int/int_19 | 0.5881 | 1.7941 | 14.2437 | 0.7789 | 1.8646 | 14.1636 |
| int/int_1 | 11.3647 | 14.2357 | 17.9841 | 11.4486 | 14.2556 | 18.0635 |
| int/int_20 | 2.1556 | 4.0467 | 11.2847 | 2.3374 | 4.0308 | 10.7517 |
| int/int_21 | 24.2469 | 28.9043 | 29.4377 | 23.6708 | 28.1769 | 28.5966 |
| int/int_22 | 4.7163 | 9.3836 | 9.3652 | 4.8276 | 9.2598 | 9.2930 |
| int/int_23 | 3.2636 | 4.3531 | 6.9415 | 3.3921 | 4.4837 | 7.0266 |
| int/int_24 | 0.4488 | 1.0946 | 2.0358 | 0.5412 | 1.0817 | 2.5878 |
| int/int_25 | 2.2612 | 2.9055 | 3.4472 | 1.3040 | 1.7175 | 2.7778 |
| int/int_26 | 1.1492 | 1.9736 | 3.7982 | 1.2566 | 2.0305 | 3.8332 |
| int/int_27 | 0.6896 | 1.2126 | 2.3639 | 0.8206 | 1.3437 | 2.5079 |
| int/int_28 | 3.1211 | 5.1243 | 8.2203 | 3.3842 | 5.3150 | 8.3924 |
| int/int_29 | 11.2431 | 16.0758 | 18.0465 | 11.6531 | 16.1793 | 18.0038 |
| int/int_2 | 10.5942 | 13.4173 | 17.5646 | 10.7345 | 13.5191 | 17.6090 |
| int/int_30 | 11.5829 | 16.8002 | 18.7322 | 12.0654 | 16.9951 | 18.7918 |
| int/int_31 | 0.4690 | 3.0784 | 9.8854 | 0.6728 | 3.2021 | 10.1208 |
| int/int_32 | 6.5198 | 9.3540 | 11.9289 | 6.6301 | 9.4348 | 12.0372 |
| int/int_33 | 7.7631 | 10.6521 | 12.2341 | 7.6076 | 10.4733 | 11.9638 |
| int/int_34 | 3.0504 | 4.7518 | 5.5114 | 2.9566 | 4.5233 | 5.1897 |
| int/int_35 | 2.0928 | 5.0804 | 7.2276 | 2.2505 | 5.1349 | 7.3170 |
| int/int_36 | 2.5331 | 6.5628 | 12.4928 | 2.8652 | 6.5390 | 12.4422 |
| int/int_3 | 0.9084 | 1.9876 | 4.8123 | 0.8322 | 1.7816 | 4.2714 |
| int/int_4 | 3.6281 | 6.5149 | 12.1023 | 3.8176 | 6.6036 | 11.7050 |
| int/int_5 | 2.7755 | 3.6688 | 4.9963 | 2.8366 | 3.7018 | 5.0464 |
| int/int_6 | 2.8740 | 3.6754 | 5.1602 | 2.9471 | 3.7430 | 5.1774 |
| int/int_7 | 3.5596 | 9.8166 | 17.1273 | 4.3202 | 9.3520 | 16.9642 |
| int/int_8 | 4.9917 | 9.6440 | 16.1694 | 5.7346 | 10.3264 | 16.9259 |
| int/int_9 | 3.0795 | 8.4897 | 16.9896 | 3.6005 | 8.1377 | 16.4515 |
| media/media_0 | 0.8155 | 1.6926 | 4.4188 | 1.0876 | 1.9420 | 4.6541 |
| media/media_1 | 0.6229 | 1.3151 | 3.6136 | 1.0658 | 1.8397 | 4.3133 |
| media/media_2 | 0.6968 | 1.1456 | 2.1564 | 0.5105 | 0.8001 | 1.7908 |
| media/media_3 | 1.1108 | 2.1352 | 4.8218 | 1.2833 | 2.2134 | 4.8860 |
| web/web_0 | 0.9269 | 1.8589 | 4.6695 | 1.3077 | 2.4191 | 6.0551 |
| web/web_10 | 2.2428 | 4.0484 | 6.4408 | 2.7717 | 4.7839 | 8.5188 |
| web/web_11 | 4.4180 | 8.1492 | 12.4390 | 4.5080 | 7.9186 | 12.1265 |
| web/web_12 | 4.5434 | 6.3224 | 9.8289 | 3.9049 | 6.4094 | 11.9299 |
| web/web_13 | 2.4800 | 4.5257 | 8.8602 | 2.9162 | 4.9026 | 8.9823 |
| web/web_14 | 2.7575 | 4.0805 | 7.2353 | 3.5739 | 5.0136 | 7.8409 |
| web/web_15 | 4.1300 | 7.9615 | 11.9887 | 5.0346 | 8.4367 | 13.1580 |
| web/web_16 | 2.1666 | 3.6234 | 5.2226 | 1.5612 | 2.7502 | 4.3722 |
| web/web_17 | 0.6044 | 1.8458 | 7.6909 | 1.4354 | 3.1448 | 8.4179 |
| web/web_18 | 2.5812 | 3.9678 | 6.3262 | 2.7648 | 4.1366 | 6.5636 |
| web/web_19 | 6.1872 | 10.3315 | 15.0248 | 5.0244 | 8.2612 | 13.2362 |
| web/web_1 | 3.1350 | 4.9644 | 9.4071 | 3.1754 | 4.8558 | 9.1828 |
| web/web_20 | 1.7781 | 6.9229 | 20.7941 | 3.1938 | 8.3779 | 19.5397 |
| web/web_21 | 2.2424 | 4.9308 | 9.4508 | 1.5365 | 3.3010 | 6.5255 |
| web/web_22 | 3.0398 | 4.4792 | 6.5138 | 3.2817 | 4.7540 | 6.3865 |
| web/web_23 | 1.5155 | 2.9058 | 7.5123 | 0.9961 | 2.0716 | 5.9118 |
| web/web_24 | 1.4348 | 4.5826 | 19.6274 | 1.6697 | 4.9716 | 20.1728 |
| web/web_25 | 6.4918 | 8.9983 | 13.3863 | 5.8604 | 9.2142 | 15.2037 |
| web/web_2 | 3.9463 | 6.5659 | 11.8317 | 3.7366 | 5.8953 | 10.8542 |
| web/web_3 | 2.8943 | 4.4218 | 7.1996 | 3.5250 | 5.1249 | 8.0223 |
| web/web_4 | 3.4584 | 5.3068 | 9.2731 | 4.0026 | 5.9362 | 10.1651 |
| web/web_5 | 4.6474 | 7.0251 | 11.4579 | 4.2570 | 6.2719 | 10.3696 |
| web/web_6 | 5.5540 | 7.7817 | 11.7282 | 4.5359 | 6.4579 | 11.2872 |
| web/web_7 | 5.5957 | 9.1726 | 10.2085 | 6.3257 | 10.1710 | 11.0041 |
| web/web_8 | 3.7711 | 5.8470 | 9.7952 | 4.5569 | 6.6971 | 10.8014 |
| web/web_9 | 0.0034 | 1.1923 | 0.0624 | 2.4667 | 5.1337 | 8.8627 |

### Phase 5: the new baseline
- perf/studies/perf005_baseline.sets: the sets baseline and
  baseline_oracle (--oracle), bin perf/build/tree_s2/perf_fe, the
  baseline arguments. Run over perf/studies/baseline.traces to
  perf/studies/perf005_baseline.csv: 210 rows, 0 runs exited non-zero,
  wall 11,862 s.
  - input_digest
    ef1fbde4ad4cb3e68d06f1c612d99b71e35390901def00e17c97c9eb97327842;
    make -C perf digest prints the same for the tree.
  - revision tree, dirty rtl+perf (the tree is uncommitted).
- THE FIRST RUN (wall 11,903 s) FAILED A CHECK: rs_sum_err 846 on 40
  oracle rows, all rs_r_other.
  - Define: a return whose source is the RAS at p2 while the probe says
    the peek was not valid (perf_fe.cc 699; perf_top.sv decision_probes).
  - Locate: int_9 (oracle, 2 slots) cycle 145,785, k 194,164, return at
    fffff35b67e0, FTQ idx 36, slot 0: src RAS, FTB answered at p2,
    probe pkv 0 (RSNOTE, a print added for it).
  - Cause: the oracle forces w_ras_peek_valid_p2 to 1 for an on-path
    return (perf_top.sv oracle_values), and bp_cluster takes the
    return's target from the peek (bp_cluster.sv 1293-1296). But the
    probe read the RAS module's unforced port ras_peek_valid_p2.
  - Fix: dp2_pkv reads w_ras_peek_valid_p2, as the cluster does. This is
    a harness defect; the RTL is unchanged.
  - Test, fails before and passes after: rs_sum_err on a full-length
    oracle run.
    - 2 slots, int_9: 136 before, 0 after (rs_r_ras_p2 +136, cycles
      equal).
    - 1 slot, web_12: 34 before, 0 after (rs_r_ras_p2 +34, cycles
      equal). int_9 and int_4 have no such case at 1 slot.
  - The study was rerun on the fixed harness. Run 2 against run 1: every
    cell equal except rs_r_other (-> 0), rs_r_ras_p2 (+ the same) and
    rs_sum_err (-> 0) on those 40 oracle rows, and cycles_per_sec (a
    timing column).
- THE PF-11 CHECKS, on all 210 rows:
  - exact counts: instr, NumBr, 50PercInstr and 50PercNumBr equal
    perf/cbp2025_rv_counts.csv on every row (0 failures in either set);
  - the PC check and the record checks: err_stream, err_word, err_fault,
    err_illegal, err_ftq_idx, err_tl_opcode, err_entry_reopen,
    err_unspec_repair, err_cond_target, err_fetch_rule, err_no_record,
    err_late_write, err_fetch_port, err_record_moved: 0 on every row;
  - the oracle: err_orc_slot_mispred 0 on every oracle row (it is an
    error only there; on the baseline rows it counts the mispredicts on
    slot-held branches, 30,469,392);
  - orc_slot_kind_alias: 1 on the oracle rows, 2 on the baseline rows;
    conflict_unspec_repair: 1 on each set;
  - the PERF-005 rule checks: rs_sum_err, fp_chk_* (4), fu_chk_* (4),
    tr_chk_read, tu_chk_* (7), sp_chk_* (2), su_chk_* (3), th_chk_pc,
    th_nolookup: 0 on every row of both sets;
  - the history classes:

| set | th_entries | th_bad | rollback | rollback_nored | obs_ok | other | lag | a_ne_b |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 748,921,009 | 59,484,908 | 59,484,908 | 0 | 0 | 0 | 0 | 0 |
| baseline_oracle | 742,554,800 | 46,642,053 | 46,642,053 | 0 | 0 | 0 | 0 | 0 |

    th_bad equals th_bad_rollback on every row of both sets.
    th_chk_idx_tN / th_chk_tag_tN count the mismatched tables of those
    rollback-cycle lookups (baseline T1 idx 113,520,496 ... T4 tag
    104,843,756); they are counts of the class, not a separate failure.
  - counted outcomes on the baseline rows: tu_alloc_dup 14,537 (97,289
    on the old RTL), tu_gone_prm 1,086, tu_stale_prm 2,312,115.
- THE NEW BASELINE against baseline.csv (the baseline set):

| group | MPKI base | MPKI new | d | cond base | cond new | d | 50Perc cond base | 50Perc cond new | d | cycles base | cycles new | d % |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| compress | 6.0510 | 5.8582 | -0.1928 | 5.9595 | 5.7672 | -0.1923 | 4.2087 | 4.0556 | -0.1530 | 180827342 | 182912537 | +1.153 |
| fp | 7.6629 | 7.4031 | -0.2598 | 7.6154 | 7.3485 | -0.2670 | 7.8310 | 7.5727 | -0.2583 | 166202544 | 168943939 | +1.649 |
| infra | 7.4638 | 6.7784 | -0.6854 | 6.8395 | 6.1646 | -0.6750 | 6.4953 | 5.8641 | -0.6312 | 353357125 | 359687441 | +1.791 |
| int | 10.4501 | 9.7002 | -0.7498 | 9.7079 | 8.9602 | -0.7477 | 9.9353 | 9.1690 | -0.7663 | 786320824 | 790678565 | +0.554 |
| media | 4.2290 | 3.6179 | -0.6111 | 3.9133 | 3.3661 | -0.5471 | 3.7526 | 3.2343 | -0.5184 | 22349841 | 22273004 | -0.344 |
| web | 11.4745 | 10.4100 | -1.0645 | 9.7578 | 8.7451 | -1.0127 | 9.7683 | 8.7306 | -1.0377 | 413905716 | 418332806 | +1.070 |
| all | 9.1253 | 8.4618 | -0.6635 | 8.4063 | 7.7547 | -0.6516 | 8.4173 | 7.7283 | -0.6890 | 1922963392 | 1942828292 | +1.033 |

  All mispredicts fall 39,788,532 -> 36,895,369 (-2,893,163);
  conditional 36,653,625 -> 33,812,337 (-2,841,288).
- EVERY MOVED ROW ACCOUNTED FOR. All 105 rows moved: 102 have fewer
  conditional mispredicts and 3 more.
  - By the changes alone (50Perc conditional mispredicts, summed over
    the traces):
    - combined: -1,408,984;
    - the sum of R1, R2, R4, R5, R6 and R7 measured alone: -1,494,702;
    - interaction: 85,718 (5.7% of the sum alone).
    - In 99 of 105 rows the combined move has the sign of the sum
      alone.
    - The interaction, per row, as a % of the row's baseline count:
      <= 0.5% 31 rows, <= 1% 25, <= 2% 28, <= 5% 16, more than 5% 5.
      The largest are int_19 (+21,574 of 291,046), fp_6 (-8,297),
      web_14 (+7,864), infra_7 (+7,337) and int_36 (+7,317).
  - Cycles: combined +19,864,900, sum alone +17,909,077.
  - First divergence (fd.py, base p3_s2 against tree_s2, 1e6
    instructions):
    - int_19 (the largest interaction) line 808: cycle 1465, idx 49.
      TAGE's p2 direction turns 1 -> 0 and SC's sum 0 -> 4. R4 alone
      gives the same first line with the direction 0 (an entry
      allocated at 011) and sum -2; R5's index makes the sum differ.
    - infra_2 (worse, +6,943) line 317: cycle 1109, idx 58, slot 0,
      p2 1 -> 0, sum 0 -> 4. R4 alone gives the same first line.
    - fp_1 (worse, +605) line 164: cycle 538, idx 22, slot 0, sum
      0 -> 4. R5 alone gives the same first line (sum 0 -> 4).
- The oracle rows: cycles 1,636,407,674 -> 1,691,688,169 (+3.378%). The
  ceiling moves by the timing changes, not by accuracy:
  - R1 holds a resolution instead of dropping its update;
  - R7 adds the history redirects (on the oracle path too, since the
    p2/p3 bundle still differs from p1's);
  - in R6 and R1's measured cycles, the same moves appear on the
    baseline rows.
  Not decomposed per change on the oracle set (each change alone was
  run on the baseline set only).

### Phase 6: the decomposition
Conditional MPKI at 50Perc, the mean of the traces. Each step is the
difference of the adjacent columns:

| group | TAGE192 | twin | pacino fp off | pacino new | pacino old | twin - TAGE192 | fp off - twin | new - fp off | old - new |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| compress | 2.7229 | 3.4559 | 3.7187 | 4.0556 | 4.2087 | 0.7331 | 0.2628 | 0.3369 | 0.1530 |
| fp | 4.1088 | 5.8057 | 6.1198 | 7.5727 | 7.8310 | 1.6969 | 0.3141 | 1.4529 | 0.2583 |
| infra | 2.3625 | 3.8545 | 5.6397 | 5.8641 | 6.4953 | 1.4920 | 1.7852 | 0.2244 | 0.6312 |
| int | 4.1627 | 6.6547 | 9.3976 | 9.1690 | 9.9353 | 2.4920 | 2.7429 | -0.2286 | 0.7663 |
| media | 0.8115 | 1.5721 | 3.1211 | 3.2343 | 3.7526 | 0.7606 | 1.5490 | 0.1132 | 0.5184 |
| web | 3.1748 | 5.4543 | 9.7514 | 8.7306 | 9.7683 | 2.2795 | 4.2971 | -1.0208 | 1.0377 |
| all | 3.3992 | 5.3802 | 7.8038 | 7.7283 | 8.4173 | 1.9810 | 2.4236 | -0.0755 | 0.6890 |

The steps, named:
- twin - TAGE192: TAGE's own size, layout and rules against TAGE192, both
  with CBP's immediate update.
- fp off - twin: what pacino adds around TAGE, on the old RTL with the
  fast path off: the FTB's misses (c_none_miss 0.98 MPKI), the loop
  predictor and SC, training at resolve, the pipelined history (R6, R7)
  and the rules R1-R5 replace.
- new - fp off: two moves on different trees. The fast path is on in the
  new baseline (off, it saves 0.6136 on the old RTL), and the Phase 3
  rule changes take 0.6890 off. They are not additive, since fp off was
  measured on the old RTL.
- old - new: R1, R2, R4, R5, R6 and R7 together.
The new baseline's gap to TAGE192 is 4.3291: 1.9810 TAGE itself, and
2.3481 the front end around it. The gap is still not steady across the
groups (web 5.5558, media 2.4228).

### Phase 6: the regression
tools/regress.sh, run once at the end, in the background, from the repo
root with no arguments, after the tb_fe_top.sv fixes (Jeff, session-086,
withdrew THE AREA). Its summary, whole:

```
==================================================================
REGRESSION SUMMARY  git f88a61b (dirty)
root /home/jeff/Development/jeffnye-gh/pacino
jobs 15 (default: 32 threads / 2, 31 GB / 2); priority: nice -n 10, ionice -c 3
==================================================================
== rtl/core/csr
  PASS       lint_csr_pkg           rc=0   warn=0  err=0  -              0s
  PASS       lint_csr_tb_pkg        rc=0   warn=0  err=0  -              1s
  PASS       sim_csr_tb_pkg         rc=0   warn=0  err=0  200/0          3s
  time 4s
== rtl/core/frontend/bpu
  PASS       lint                   rc=0   warn=0  err=0  -              1s
  PASS       lint_loop_pred         rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_table        rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_table          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_brimli         rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_cntrl          rc=0   warn=0  err=0  -              1s
  PASS       lint_sc                rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_table      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_cntrl      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_arb        rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage            rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_cntrl        rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_arb          rc=0   warn=0  err=0  -              0s
  PASS       lint_tage              rc=0   warn=0  err=0  -              1s
  PASS       lint_ras               rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_array         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru          rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb               rc=0   warn=0  err=0  -              1s
  PASS       lint_bp_cluster        rc=0   warn=0  err=0  -              2s
  PASS       sim                    rc=0   warn=0  err=0  34/0           1s
  PASS       sim_history            rc=0   warn=0  err=0  45939/0       28s
  PASS       sim_ubtb               rc=0   warn=0  err=0  341/0         10s
  PASS       sim_loop_pred          rc=0   warn=0  err=0  11548/0        3s
  PASS       sim_tage_table         rc=0   warn=0  err=0  15/0           0s
  PASS       sim_sc_table           rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_table_fast      rc=0   warn=0  err=0  7/0            0s
  PASS       sim_sc_brimli          rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_brimli_fast     rc=0   warn=0  err=0  7/0            0s
  PASS       sim_sc_cntrl           rc=0   warn=0  err=0  102/0          3s
  PASS       sim_sc                 rc=0   warn=0  err=0  144/0          3s
  PASS       sim_sc_fast            rc=0   warn=0  err=0  140/0          3s
  PASS       sim_ittage_table       rc=0   warn=0  err=0  32/0           1s
  PASS       sim_ittage_cntrl       rc=0   warn=0  err=0  150/0          3s
  PASS       sim_ittage             rc=0   warn=0  err=0  389/0          4s
  PASS       sim_ittage_fast        rc=0   warn=0  err=0  389/0          4s
  PASS       sim_bp_cluster         rc=0   warn=0  err=0  2163/0         9s
  PASS       sim_bp_cluster_init    rc=0   warn=0  err=0  2163/0        47s
  PASS       sim_ras                rc=0   warn=0  err=0  780/0          5s
  PASS       sim_ftb                rc=0   warn=0  err=0  241/0          3s
  PASS       sim_tage               rc=0   warn=0  err=0  109/0          3s
  PASS       sim_tage_fast          rc=0   warn=0  err=0  109/0          3s
  PASS       sim_tage_tasks         rc=0   warn=0  err=0  1/0            3s
  PASS       sim_tage_manual        rc=0   warn=0  err=0  1267/0         4s
  PASS       cov_history            rc=0   warn=0  err=0  45939/0       11s
  PASS       cov_ubtb               rc=0   warn=0  err=0  341/0          7s
  PASS       cov_loop_pred          rc=0   warn=0  err=0  11548/0        7s
  PASS       cov_tage_table         rc=0   warn=0  err=0  15/0           1s
  PASS       cov_tage               rc=0   warn=0  err=0  218/0          9s
  PASS       cov_bp_cluster         rc=0   warn=0  err=0  2163/0        23s
  PASS       cov_bpu                rc=0   warn=0  err=0  58061/0       32s
             sum of sub-runs:tage=218/0 tage_table=15/0 loop_pred=11548/0 bp_history=45939/0 ubtb=341/0
  PASS       lint_1slot             rc=0   warn=0  err=0  -              0s
  PASS       lint_loop_pred_1slot   rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_table_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_table_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_brimli_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_cntrl_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_1slot          rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_table_1slot rc=0   warn=0  err=0  -              1s
  PASS       lint_ittage_cntrl_1slot rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_arb_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_1slot      rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_cntrl_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_arb_1slot    rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_1slot        rc=0   warn=0  err=0  -              0s
  PASS       lint_ras_1slot         rc=0   warn=0  err=0  -              1s
  PASS       lint_ftb_array_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_1slot         rc=0   warn=0  err=0  -              0s
  PASS       lint_bp_cluster_1slot  rc=0   warn=0  err=0  -              2s
  PASS       sim_1slot              rc=0   warn=0  err=0  30/0           0s
  PASS       sim_history_1slot      rc=0   warn=0  err=0  26839/0        3s
  PASS       sim_ubtb_1slot         rc=0   warn=0  err=0  341/0          2s
  PASS       sim_loop_pred_1slot    rc=0   warn=0  err=0  5765/0         2s
  PASS       sim_tage_table_1slot   rc=0   warn=0  err=0  11/0           1s
  PASS       sim_sc_table_1slot     rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_table_fast_1slot rc=0   warn=0  err=0  6/0            1s
  PASS       sim_sc_brimli_1slot    rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_brimli_fast_1slot rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_cntrl_1slot     rc=0   warn=0  err=0  102/0          4s
  PASS       sim_sc_1slot           rc=0   warn=0  err=0  108/0          0s
  PASS       sim_sc_fast_1slot      rc=0   warn=0  err=0  104/0          1s
  PASS       sim_ittage_table_1slot rc=0   warn=0  err=0  26/0           0s
  PASS       sim_ittage_cntrl_1slot rc=0   warn=0  err=0  141/0          3s
  PASS       sim_ittage_1slot       rc=0   warn=0  err=0  258/0          4s
  PASS       sim_ittage_fast_1slot  rc=0   warn=0  err=0  258/0          3s
  PASS       sim_bp_cluster_1slot   rc=0   warn=0  err=0  1580/0         6s
  PASS       sim_bp_cluster_init_1slot rc=0   warn=0  err=0  1580/0        30s
  PASS       sim_ras_1slot          rc=0   warn=0  err=0  679/0          4s
  PASS       sim_ftb_1slot          rc=0   warn=0  err=0  188/0          3s
  PASS       sim_tage_1slot         rc=0   warn=0  err=0  105/0          4s
  PASS       sim_tage_fast_1slot    rc=0   warn=0  err=0  105/0          2s
  PASS       sim_tage_tasks_1slot   rc=0   warn=0  err=0  1/0            1s
  PASS       sim_tage_manual_1slot  rc=0   warn=0  err=0  534/0          3s
  time 325s
== rtl/core/frontend/decode
  PASS       lint_dec               rc=0   warn=0  err=0  -              1s
  PASS       sim_dec                rc=0   warn=0  err=0  1355/0        19s
  PASS       coverage               rc=0   warn=0  err=0  -             15s
  PASS       sim_dec_sweep          rc=0   warn=0  err=0  458752/0      43s
  PASS       oracle_dec_sweep       rc=0   warn=0  err=0  -              2s
  PASS       asm_dec_words          rc=0   warn=0  err=0  492/0          0s
  time 81s
== rtl/core/frontend/fe_top
  PASS       lint_fe_top            rc=0   warn=0  err=0  -              5s
  PASS       sim_fe_top             rc=0   warn=0  err=0  1006/0        88s
  PASS       assert_labels          rc=0   warn=0  err=0  173/0          2s
  PASS       sim_fe_top_bare        rc=0   warn=0  err=0  22/0           1s
  PASS       sim_fe_top_sv39        rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_loops       rc=0   warn=0  err=0  26/0           0s
  PASS       sim_fe_top_coro        rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_calls       rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_lp          rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_hist        rc=0   warn=0  err=0  19/0           1s
  PASS       sim_fe_top_twocond     rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_ftbonly     rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_nest        rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_recur       rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_t0_uaon     rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_deep        rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_indir       rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_region      rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_multistart  rc=0   warn=0  err=0  18/0           1s
  PASS       sim_fe_top_cross       rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_rvc         rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_misp_call   rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_sc_nored    rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_jals        rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_fencei      rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_cboinval    rc=0   warn=0  err=0  22/0           1s
  PASS       sim_fe_top_uc_nc       rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_uc_io       rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_faults_s rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_faults_h rc=0   warn=0  err=0  19/0           1s
  PASS       sim_fe_top_pt_napot_s  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_napot_h  rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_pt_rsv_s    rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_rsv_h    rc=0   warn=0  err=0  20/0           2s
  PASS       sim_fe_top_pt_ad_s     rc=0   warn=0  err=0  21/0           1s
  PASS       sim_fe_top_pt_ad_h     rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_pt_inv      rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_zstar       rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_gonly    rc=0   warn=0  err=0  19/0           1s
  PASS       sim_fe_top_pt_vsonly   rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_upriv    rc=0   warn=0  err=0  25/0           0s
  PASS       sim_fe_top_sv48        rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_sv57        rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_h57         rc=0   warn=0  err=0  24/0           1s
  PASS       sim_fe_top_pt_gonly_x4 rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_ras_fbstale rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ras_pdcall  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_rsv_twores  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_rsv_trapcall rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ras_bkicall rc=0   warn=0  err=0  19/0           1s
  PASS       sim_fe_top_ras_bkret   rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ras_offpop  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ftq_full    rc=0   warn=0  err=0  24/0           0s
  PASS       sim_fe_top_init_walk   rc=0   warn=0  err=0  34/0           0s
  time 108s
== rtl/core/frontend/fe_top/slot1
  PASS       lint_fe_top_1slot      rc=0   warn=0  err=0  -              4s
  PASS       sim_fe_top_1slot       rc=0   warn=0  err=0  1003/0        82s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  165/0          2s
  PASS       sim_fe_top_bare_1slot  rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_sv39_1slot  rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_loops_1slot rc=0   warn=0  err=0  24/0           1s
  PASS       sim_fe_top_coro_1slot  rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_calls_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_lp_1slot    rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_hist_1slot  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_twocond_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_ftbonly_1slot rc=0   warn=0  err=0  18/0           1s
  PASS       sim_fe_top_nest_1slot  rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_recur_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_t0_uaon_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_deep_1slot  rc=0   warn=0  err=0  18/0           1s
  PASS       sim_fe_top_indir_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_region_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_multistart_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_cross_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_rvc_1slot   rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_misp_call_1slot rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_sc_nored_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_jals_1slot  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_fencei_1slot rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_cboinval_1slot rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_uc_nc_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_uc_io_1slot rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_pt_faults_s_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_faults_h_1slot rc=0   warn=0  err=0  19/0           1s
  PASS       sim_fe_top_pt_napot_s_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_napot_h_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_rsv_s_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_rsv_h_1slot rc=0   warn=0  err=0  20/0           2s
  PASS       sim_fe_top_pt_ad_s_1slot rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_pt_ad_h_1slot rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_pt_inv_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_zstar_1slot rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_pt_gonly_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_vsonly_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_upriv_1slot rc=0   warn=0  err=0  25/0           0s
  PASS       sim_fe_top_sv48_1slot  rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_sv57_1slot  rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_h57_1slot   rc=0   warn=0  err=0  24/0           1s
  PASS       sim_fe_top_pt_gonly_x4_1slot rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_ras_fbstale_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ras_pdcall_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_rsv_twores_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_rsv_trapcall_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ras_bkicall_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ras_bkret_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ras_offpop_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ftq_full_1slot rc=0   warn=0  err=0  24/0           0s
  PASS       sim_fe_top_init_walk_1slot rc=0   warn=0  err=0  32/0           0s
  time 99s
== rtl/core/frontend/ftq
  PASS       lint_ftq_ftb_sched     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ftb_sched      rc=0   warn=0  err=0  68/0           1s
  PASS       lint_ftq_ptr           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ptr            rc=0   warn=0  err=0  207/0          9s
  PASS       lint_ftq_commit        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_commit         rc=0   warn=0  err=0  72/0           1s
  PASS       lint_ftq_entry         rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_entry          rc=0   warn=0  err=0  83/0          20s
  PASS       lint_ftq_meta          rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta           rc=0   warn=0  err=0  26/0           1s
  PASS       lint_ftq_status        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_status         rc=0   warn=0  err=0  45/0           1s
  PASS       lint_ftq_shadow        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_shadow         rc=0   warn=0  err=0  53/0           1s
  PASS       lint_ftq_npc           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_npc            rc=0   warn=0  err=0  84/0           1s
  PASS       lint_ftq_ifu           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ifu            rc=0   warn=0  err=0  241/0          9s
  PASS       lint_ftq_resolve       rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_resolve        rc=0   warn=0  err=0  146/0          5s
  PASS       lint_ftq_upd_conv      rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_upd_conv       rc=0   warn=0  err=0  192/0          4s
  PASS       lint_ftq               rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq                rc=0   warn=0  err=0  259/0          4s
  PASS       assert_labels          rc=0   warn=0  err=0  234/0          2s
  PASS       lint_ftq_ftb_sched_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ftb_sched_1slot rc=0   warn=0  err=0  68/0           0s
  PASS       lint_ftq_ptr_1slot     rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_ptr_1slot      rc=0   warn=0  err=0  207/0          2s
  PASS       lint_ftq_commit_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_commit_1slot   rc=0   warn=0  err=0  72/0           1s
  PASS       lint_ftq_entry_1slot   rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_entry_1slot    rc=0   warn=0  err=0  69/0           3s
  PASS       lint_ftq_meta_1slot    rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta_1slot     rc=0   warn=0  err=0  19/0           1s
  PASS       lint_ftq_status_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_status_1slot   rc=0   warn=0  err=0  45/0           0s
  PASS       lint_ftq_shadow_1slot  rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_shadow_1slot   rc=0   warn=0  err=0  53/0           0s
  PASS       lint_ftq_npc_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_npc_1slot      rc=0   warn=0  err=0  80/0           0s
  PASS       lint_ftq_ifu_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ifu_1slot      rc=0   warn=0  err=0  226/0          3s
  PASS       lint_ftq_resolve_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_resolve_1slot  rc=0   warn=0  err=0  105/0          3s
  PASS       lint_ftq_upd_conv_1slot rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_upd_conv_1slot rc=0   warn=0  err=0  106/0          2s
  PASS       lint_ftq_1slot         rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_1slot          rc=0   warn=0  err=0  259/0          3s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  213/0          2s
  time 85s
== rtl/core/frontend/ibuf
  PASS       lint_ibuf              rc=0   warn=0  err=0  -              0s
  PASS       sim_ibuf               rc=0   warn=0  err=0  52/0          21s
  PASS       assert_labels          rc=0   warn=0  err=0  3/0            0s
  time 21s
== rtl/core/frontend/icache
  PASS       lint_l1i               rc=0   warn=0  err=0  -              1s
  PASS       sim_l1i_emitted        rc=0   warn=0  err=0  67/0          14s
  PASS       sim_l1i                rc=0   warn=0  err=0  296/0         20s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0            7s
  time 42s
== rtl/core/frontend/ifu
  PASS       lint_ifu_rvc_exp       rc=0   warn=0  err=0  -              1s
  PASS       lint_ifu_predecode     rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_xlate         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_lbuf          rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_fetch         rc=0   warn=0  err=0  -              1s
  PASS       lint_ifu_f3            rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_wb            rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_maint         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu               rc=0   warn=0  err=0  -              1s
  PASS       sim_ifu_rvc_exp        rc=0   warn=0  err=0  2457618/0     26s
  PASS       sim_ifu_predecode      rc=0   warn=0  err=0  63/0          13s
  PASS       sim_ifu                rc=0   warn=0  err=0  738/0         13s
  PASS       assert_labels          rc=0   warn=0  err=0  16/0           1s
  PASS       oracle_ifu_rvc_exp     rc=0   warn=0  err=0  -              1s
  time 57s
== rtl/core/frontend/l1i_param_chk
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       lint_neg               rc=0   warn=0  err=0  -              1s
  time 1s
== rtl/lib
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       sim                    rc=0   warn=0  err=0  34/0           1s
  time 1s
== rtl
  time 0s
== rtl/mmu/itlb
  PASS       lint_itlb              rc=0   warn=0  err=0  -              1s
  PASS       sim_itlb               rc=0   warn=0  err=0  228/0         25s
  PASS       sim_itlb_d2            rc=0   warn=0  err=0  231/0         17s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0            0s
  time 43s
== rtl/mmu/pmp
  PASS       lint_pmp_pma_chk       rc=0   warn=0  err=0  -              0s
  PASS       sim_pmp_pma_chk        rc=0   warn=0  err=0  73/0          17s
  PASS       lint_neg_pma           rc=0   warn=0  err=0  -              0s
  PASS       lint_neg_pma_dflt      rc=0   warn=0  err=0  -              1s
  time 18s
== rtl/mmu/ptw
  PASS       lint_ptw               rc=0   warn=0  err=0  -              0s
  PASS       lint_pt_build_pkg      rc=0   warn=0  err=0  -              0s
  PASS       sim_ptw                rc=0   warn=0  err=0  1564/0        18s
  PASS       assert_labels          rc=0   warn=0  err=0  13/0          12s
  PASS       sim_pt_gen             rc=0   warn=0  err=0  -              0s
  PASS       sim_ptw_img            rc=0   warn=0  err=0  5465/0        11s
  PASS       sim_pt_gen_noncanon    rc=0   warn=0  err=0  -              1s
  PASS       sim_pt_gen_mem_top     rc=0   warn=0  err=0  -              0s
  time 44s
------------------------------------------------------------------
targets run: 303   total time: 333s
new failures: 0   known failures: 0   now passing: 0   stale entries: 0   malformed entries: 0   set errors: 0
logs: /tmp/regress.LTzmVF
pass NOT recorded: tracked changes or untracked rtl/ files, or HEAD moved during the run (push will be refused)
RESULT: PASS
```

The run before the AREA was withdrawn (same session) failed 5 targets,
two scenarios (sc_nored at both slot counts, t0_uaon at two slots,
each also inside sim_fe_top / sim_fe_top_1slot); its summary was
replaced by this one. See Test Case Results.

### Phase 6: the proposed planning text
The IA does not write planning files. The text below is for the PA and
Jeff.

#### perf_decisions.md PF-5, after "PERF-002's "no count changed" does not reproduce." (line 383), add:
```
       THE FAST PATH, MEASURED BY PERF-005 (perf/studies/
       perf005_p2_fpoff.sets, --cfg ftb_fastpath_en=0, the baseline
       RTL): MPKI 9.1253 -> 8.4459, conditional 8.4063 -> 7.6977,
       50Perc conditional (mean of the traces) 8.4173 -> 7.8038, cycles
       +0.574%. Better in every group but web (-0.03): fp -1.79,
       compress -1.03, infra -0.67, int -0.53, media -0.50 MPKI. Worse
       on int_16 (+1.92 conditional), web_20 (+1.86). The fast path
       decided 453,510,726 conditionals and mispredicted 17,527,029
       (44% of all mispredicts); 51% of its mispredicts come within 4
       resolutions of its conf leaving saturation, and TAGE's unused
       response was right on 53.3% of them. The checks of its rules
       (fp_chk_*, fu_chk_*) are 0 on every row: it mispredicts by its
       rule, not by a defect. The default stays ftb_fastpath_en 1
       until Jeff decides.
```

#### perf_decisions.md PF-6, after "(PF-5)." (line 403), add:
```
       Columns added by PERF-005, each family last in the row so the
       earlier columns keep their order:
       - rs_<reason>, rm_<reason>: THE REASON of each committed branch,
         decisions and mispredicts (perf_fe.cc classify()); the
         reasons of a source sum to its pred_ and mis_ columns;
         rs_sum_err is the distance, 0 expected (PF-11).
       - fp_*, fu_*, fs_*, fpc_*: the fast path's reads, firings,
         updates and the conf histogram at its mispredicts; fp_chk_*,
         fu_chk_* its rule checks (PF-11).
       - th_*: THE HISTORY check: th_entries, th_nolookup, th_chk_pc,
         th_chk_idx_tN, th_chk_tag_tN, th_fold_tN (per table, every
         mismatch, all classes); th_bad (lookups with any mismatch)
         split th_bad_queued, th_bad_rollback (of which
         th_bad_rollback_nored: an uncorrected bundle in the window),
         th_bad_obs_ok (_nored, _corr, _nowin) and th_bad_other;
         th_lag; th_bundle_a_ne_b (_p1only, _corr, _other).
       - tr_*: every TAGE RAM read against the harness's shadow.
       - tu_*: every TAGE update and allocation re-derived; counted
         outcomes tu_alloc, tu_alloc_ntk, tu_alloc_dup, the refusals
         (ref_longest, ref_useful, ref_other), tu_gone_*, tu_stale_*,
         the providers.
       - sp_*, su_*: SC's answers and updates re-derived; the corner
         choices; sc_thr_max.
       stderr prints the first cases of a class (TGDEV, THAB, THNW,
       TGNOTE, RSNOTE, FPDEV): 20 of a deviation, 2 of a counted
       outcome. PERF_TH_LAG_OLD=1 runs the history check with the
       model before R6 (prev_wc < lookup cycle), for an RTL without
       the p0 bypass. The decision probes read the cluster's own
       signals where an oracle force reaches the decision (the RAS
       peek valid, w_ras_peek_valid_p2).
```

#### perf_decisions.md PF-9, replace "THE BASELINE (PERF-004): ... committed as 2d1e330." (455-462) with:
```
       THE BASELINE (PERF-005): perf/studies/perf005_baseline.sets
       (baseline and baseline_oracle) over perf/studies/
       baseline.traces, full length, the tree build (tree_s2), the
       PF-5 configuration, the immediate backend, the fetch rule, the
       real I-cache; perf/studies/perf005_baseline.csv, 210 rows,
       every PF-11 check passing, digest
       ef1fbde4ad4cb3e68d06f1c612d99b71e35390901def00e17c97c9eb97327842
       (on an uncommitted tree; the digest holds once committed
       unchanged). 3.3 hours on 24 workers for both sets. It replaces
       PERF-004's baseline.csv (digest 0c66fed0..., 2d1e330), which
       stays as the record of the RTL before R1, R2, R4, R5, R6 and
       R7.
```
(If the file is to be renamed baseline.csv when the tree is committed,
the text reads baseline.csv and the sets file baseline.sets.)

#### perf_decisions.md PF-10, after "Not yet investigated." (line 533), add:
```
       INVESTIGATED BY PERF-005 (TD#218). THE DECOMPOSITION,
       conditional MPKI at 50Perc, the mean of the per-trace values,
       all 105 traces: TAGE192 3.3992; the twin (pacino's TAGE alone,
       its tables, hashes and rules, in the CBP framework with CBP's
       immediate update) 5.3802; pacino with the fast path off (the
       old RTL) 7.8038; pacino at the new baseline 7.7283; pacino at
       the old baseline 8.4173. The steps:
         twin - TAGE192     1.9810  TAGE's size, layout and rules
         fp off - twin      2.4236  what pacino adds around TAGE
                                    (the FTB's misses, the loop and
                                    SC, update at resolve, the
                                    pipelined history), old RTL
         new - fp off      -0.0755  the fast path on (+0.6136 on the
                                    old RTL) and the PERF-005 rule
                                    changes (-0.6890), on different
                                    trees: not additive
         old - new          0.6890  R1, R2, R4, R5, R6, R7
       Per group the steps are in PERF-005's Results Capture. Of the
       new baseline's gap to TAGE192 (4.3291), 1.9810 is TAGE itself
       and 2.3481 the rest of the front end. The gap is still not
       steady across the groups (web 5.5558, media 2.4228), so the
       extrapolation to SPEC still does not hold.
```

#### perf_decisions.md PF-11, after "every committed PC equals the trace's next PC." (line 610), add:
```
       - THE RULE CHECKS (PERF-005), columns 0 on every row of a study
         before it is used: rs_sum_err (every committed branch has a
         named reason, on the oracle rows too); fp_chk_conf,
         fp_chk_noshadow, fp_chk_41, fp_chk_use, fu_chk_rdconf,
         fu_chk_wrconf, fu_chk_keep, fu_chk_noshadow (the fast path
         against ftb_confidence_override_rules.md 3.2, 3.4, 4.1);
         tr_chk_read; tu_chk, tu_chk_we, tu_chk_addr, tu_chk_ctr,
         tu_chk_use, tu_chk_alc, tu_chk_uaon (TAGE's update, by the
         ctr, use, alloc and uaon rule files); sp_chk_sum, sp_chk_dec,
         su_chk_wr, su_chk_wd, su_chk_glob (SC, by sc_decisions.md);
         th_chk_pc, th_nolookup, th_bad_other, th_bad_obs_ok,
         th_bad_rollback_nored, th_lag, th_bundle_a_ne_b (the history,
         by tage_table_hash_rules.md and bp_history_decisions.md).
         th_bad equals th_bad_rollback: the only mismatched lookups are
         those in a rollback cycle (bp_history_decisions.md 5), and
         th_chk_idx_tN / th_chk_tag_tN count their tables. The checks
         model the rules as the tree has them: a rule change changes
         its check with it (R2 su_chk_glob, R4 tu_chk_alc, R6 th_lag).
         MEASURED (the new baseline, 210 rows): every one 0.
       - THE TWIN CHECK: every twin run passes in the CBP framework and
         its instruction and branch counts equal cbp2025_rv_counts.csv
         (perf005_twin.csv, 105 rows).
```

#### ftq_decisions.md 5.7.3 (R1): replace S5 "Anything still remaining is DROPPED if LOW." and S6 "A HIGH update is NEVER dropped. ..." with:
```
  S5  No update is dropped. A channel whose update would fall outside
      the capacity deasserts ftq_bkend_rsv_rdy, LOW or HIGH, and the
      backend holds it (PERF-005 R1: S5 dropped 5.30% of conditional
      resolutions, each a conf step ftb_confidence_override_rules.md
      3.2 requires).
  S6  (merged into S5.)
```

#### sc_decisions.md section 10 (R2): replace "logic sc_pred_match = sc_upd_inp.sc_pred_meta.sc_pred_tkn == sc_upd_inp.resolved_taken;" with:
```
logic sc_pred_match = sc_upd_inp.sc_pred_meta.sc_lcl_pred_tkn ==
                      sc_upd_inp.resolved_taken;
```
and add: "The chooser trains on SC's own sum direction, not the final
direction, which in a corner the chooser itself picked (PERF-005 R2;
cbp2016_tage_sc_l.h 1295-1311 trains FirstH/SecondH on which of TAGE and
SC was right)."

#### tage_cntrl_alloc_rules.md line 82 (R4): replace "CTR = 3'b100 (weakest taken)" with:
```
CTR = resolved_taken ? 3'b100 : 3'b011 (weak toward the resolved
direction; PERF-005 R4, cbp2016_tage_sc_l.h 1460, 1505)
```

#### sc_table_hash_rules.md, Function, 87-89 (R5): replace "hashed_index = THIS_INDEX_BITS'(inp_pc_p2[s] ^ fh_idx_ext);" with:
```
hashed_index = THIS_INDEX_BITS'({inp_pc_p2[s][VA_WIDTH-2:1],
                                 tage_pred_tkn[s]} ^ fh_idx_ext);
// ST0-ST3: index bit 0 is the slot's TAGE direction (PERF-005 R5;
// cbp2016_tage_sc_l.h 1016-1029, 1073). ST4 (BrIMLI) unchanged.
```

#### bp_arb_spec.md 3.1 and fe_decisions.md 1 (R6): replace "p0 Inputs presented to RAMs (flopped). PC hash, folded history available." with:
```
p0 Inputs presented to RAMs (flopped). PC hash, folded history
   available, including the bundle the p1 block writes in the same
   cycle (bp_history folded_byp; no bypass in a rollback cycle).
```
bp_history_interfaces.md, the bp_history output list, add:
```
folded_byp   output  bp_folded_hist_t  the folds with this cycle's
                                       history bundle applied (the
                                       update's fold steps); equals
                                       folded in a rollback cycle or
                                       with no bundle. Read by the TAGE
                                       and ITTAGE p0 lookups and the
                                       p1 SC / PHR staging.
```

#### bp_history_decisions.md 3.5 (R7): replace "DECISION: the history is CORRECTED on a redirect." with:
```
DECISION: the history is CORRECTED on a redirect, and also when the
bundle a block's p2 view (FTB, TAGE) or p3 view (SC) forms differs from
the bundle it wrote at p1 with its successor unchanged: the stage
raises a slot-0 redirect to the block's own successor, the rollback
writes that stage's bundle, and the younger block is fetched again
(PERF-005 R7).
```

#### ftb_confidence_override_rules.md 3.2: no change. With R1 it holds on every resolution (drop 0).

#### PROJECT_STATUS.md TD#218 (7492-7504), the closing line:
```
CLOSED by PERF-005. The base counter's mispredicts are the fast path's
by its rule (fp_chk_* 0); off, it saves 0.61 of 8.42 50Perc conditional
MPKI (PF-5). A software twin of pacino's TAGE gives 5.38 against
TAGE192's 3.40: 1.98 is TAGE itself, 2.35 (new baseline) the rest of the
front end (PF-10). Six rule changes (R1, R2, R4, R5, R6, R7) took the
baseline from 8.42 to 7.73; R3 rejected. tb_fe_top sc_nored and t0_uaon
updated for R7 and R4. Open, to Jeff: the fast path default (PF-5),
each rule change's acceptance, and the table and history enlargement
this task does not make.
```

#### PROJECT_STATUS.md TD#205, add:
```
PERF-005 (R7): an SC reversal at p3 now raises a p3 history redirect,
so the case (a request for the entry accepted in its p3 cycle with the
p2 view) is no longer reached by sc_nored or any program; the guard is
kept. sc_nored checks the R7 redirect and the stream after B.
```

## Test Case Results
- BPU testbenches written or changed for the rule changes. Each fails
  before (tb_before = the baseline RTL plus the tree's bpu tb) and
  passes after, at both slot counts:
  - tb_ftq_ftb_sched D1 + P6 (R1): before D1 2 checks + P6; after
    PASS=68 FAIL=0 (2 slots and _1slot).
  - tb_sc_cntrl TC7 (R2): before 4 R2 checks + the HIGH saturation
    check; after 102/0 (both).
  - tb_tage, 14 allocation checks + upd_alloc_tst both ways (R4): before
    33 FAIL lines; after sim_tage 109/0, _1slot 105/0.
  - tb_sc TC3 + the pred_idx reference (R5); tb_bp_cluster FOLD sc (R5):
    before fail; after sim_sc 144/0, _1slot 108/0.
  - tb_bp_history TC20 (R6): before no build (PINNOTFOUND folded_byp);
    after sim_history 45939/0, _1slot 26839/0.
  - tb_bp_cluster E2e p2/p3 and I1 (R7), the FOLD monitor (R6), E2c and
    j_alloc: before FAIL=6; after sim_bp_cluster 2163/0, _1slot 1580/0.
- tb_bp_history TC20 had a WIDTHEXPAND on pred_pc; fixed with a 32'
  cast.
- HARNESS FIXES, tested by their check column on a run:
  - the history check snapshot (th_snapA/B): th_bad_other 6.04M -> 0;
  - the window bound: nowin 480 -> 0;
  - T0's read packing: tr_chk_read -> 0;
  - the decision probe dp2_pkv: rs_sum_err on full oracle runs, int_9 2
    slots 136 -> 0, web_12 1 slot 34 -> 0.
- tools/regress.sh, final run: 303 targets, 303 PASS, 0 new failures,
  RESULT: PASS (Phase 6). Among them sim_fe_top 1006/0, sim_fe_top_1slot
  1003/0, sim_fe_top_t0_uaon 20/0, sim_fe_top_sc_nored 20/0 and their
  _1slot twins 20/0.
- THE TWO fe_top FIXES (tb_fe_top.sv; THE AREA withdrawn by Jeff,
  session-086). Runs by scratchpad/tbfix.sh, one build at a time,
  RVA_ROOT and VERILATOR in the environment. "base" is the pre-PERF-005
  RTL (scratch copy rtl_base) with the new tb.
  - sc_nored. The precondition now requires the R7 redirect
    (n_scn_redir == 1); its message and the program comments say why.
    | Run                         | 2 slots              | 1 slot               |
    |-----------------------------|----------------------|----------------------|
    | old tb, tree (first regress) | FAIL (redirect 1)   | FAIL (redirect 1)    |
    | new tb, base RTL            | FAIL (redirect 0)    | FAIL (redirect 0)    |
    | new tb, tree                | PASS 20/0            | PASS 20/0            |
    - Tree: forced 1, p3 redirect 1, p2 taken 1, p3 not taken 1, K
      fetch in the p3 cycle 0, after B 00080000418: 0008000041c (= B +
      4). Base: redirect 0, K fetch in the p3 cycle 1, the same stream.
    - The new check fails on the RTL without R7 and passes with it, so
      it checks the R7 redirect; the stream check (X delivered) passes on
      both.
  - t0_uaon. The LFSR-seeded B (seed 16'h5a5a, +TU_SEED) is replaced:
    - B is taken on pass 7 of every 8 (TU_PER), not taken on the
      others. The program holds no other branch but the loop branch.
    - t0_uaon_seed forces each slot's use_alt_on_na counter to all ones
      for one cycle at the first falling edge after reset release, then
      releases it. The variable keeps the value until tage_cntrl steps
      it. uaon_min reports the lowest value it takes afterward.
    - The program comment lists each mechanism the case needs and
      where it comes from: the seed, the T0 init value (2'b10,
      TAGE_T0_SRAM_INIT_VALUE), the allocation at 100 for a taken
      resolution (the same before and after R4), and the weak primary
      on the next visit in the same context.
    | Run                         | 2 slots                    | 1 slot                     |
    |-----------------------------|----------------------------|----------------------------|
    | old tb, tree (first regress) | FAIL (0 updates)          | PASS (5 updates)           |
    | new tb, no seed, tree       | FAIL (0 pred, 0 updates)   | FAIL (0 pred, 0 updates)   |
    | new tb, T0 write off, tree  | FAIL (5 ok, 2 not)         | FAIL (5 ok, 1 not)         |
    | new tb, base RTL            | PASS (29 upd, 29 ok)       | PASS (9 upd, 9 ok)         |
    | new tb, tree                | PASS (6 upd, 6 ok)         | PASS (6 upd, 6 ok)         |
    - "T0 write off" is a mutation of a scratch copy of the tree:
      tage_cntrl.sv 772 u_alt_ctr_wr = 0 in the T0-as-provider arm (rows
      19.1-19.8). The check catches it at both slot counts. The ok
      writes in that run are entries already saturated in the step
      direction (row 19.4, T0 at 00, resolved not taken).
    - Tree rows: 2 slots 19.4 4, 19.6 2; 1 slot 19.4 5, 19.6 1. Row
      19.6 is the designed case (T1 weak taken, T0 not taken, B taken).
      Row 19.4 is a short-history entry that also hits a not-taken pass
      whose recent history matches the taken pass's.
    - uaon min after the seed: 2 slots s0 13, s1 15; 1 slot 14. It stays
      at or above TAGE_UAON_THRES (8) through the run.
    - The program does not depend on R4: it passes on the base RTL.
- THE FIRST REGRESS RUN (before the fixes): 303 targets, 298 PASS, 5
  FAIL (two scenarios). The trace, kept as found:
  - sc_nored (sim_fe_top_sc_nored, _1slot; also inside sim_fe_top and
    sim_fe_top_1slot):
    - The check "SC forced once, at a p3 of K with no p3 redirect, B
      taken at p2 and not taken at p3" fails on its second term: p3
      redirect 1.
    - The stream check passes: after B (00080000418) comes 0008000041c
      = B + 4.
    - Traced: the baseline copy (rtl_base) passes with p3 redirect 0; R7
      alone (rc_r7) fails in the same way.
    - R7's p3 arm raises a history redirect to the unchanged successor
      when SC turns a conditional. That is the case the program needs
      to be without a redirect, so the program's precondition is the old
      3.5 rule.
  - t0_uaon (sim_fe_top_t0_uaon; also inside sim_fe_top):
    - "T0 was updated as the use_alt_on_na provider (0)": at two slots
      the program reaches its case 0 times (predictions 0, updates 0,
      uaon max 7 on slot 0).
    - At one slot it still reaches it 5 times, all T0 writes right.
    - Traced: the baseline copy passes (55 predictions, 27 updates, 27
      writes right, uaon max 12); R4 alone (rc_r4) fails (1 prediction,
      0 updates, uaon max 8).
    - The program is an LFSR-seeded stimulus (seed 16'h5a5a, BP-141).
      Its mechanism, per its comment, is a weak, wrong primary allocated
      at 100 with a right alternate. Under R4, an allocation for a
      not-taken resolution starts at 011, so it is right on the next
      not-taken visit and the use_alt_on_na counter does not rise
      enough.
  - Neither is an RTL fault: each check's DUT behavior is the new rule's.
  - The mechanism the old comment gives ("the slot's use_alt_on_na
    counter rises" from B's weak, wrong primary) needs a tagged
    alternate. In the seeded mix the counter reached 12 on the base RTL
    (27 updates), 8 under R4 alone (1 prediction, 0 updates) and 7 on
    the tree (0).
  - Fixed in tb_fe_top.sv as above. Not re-seeded (an LFSR seed checks
    only what it exposes).

## Assumptions made not explicit in the prompt
- "Conditional MPKI at 50Perc" in every group table is the mean of the
  per-trace 50PercMpkiCond, as PF-10 measured it. The per-group totals
  (cond) are given beside it where the study tables have them.
- The new baseline lives in perf/studies/perf005_baseline.csv and .sets.
  baseline.csv and baseline.sets are left as PERF-004's; renaming them
  is Jeff's at commit.
- A harness defect (in perf/, in THE AREA) is fixed like an RTL defect,
  with its check column as the before/after test at both slot counts.
- The decomposition steps are adjacent differences of the five columns
  the task names. The fp-off column is the old RTL, so the step
  new - fp off combines two effects; it is stated as such, not split.

## Decisions made not explicit in the prompt
- R3 costs accuracy (+0.0049), so it is not built into the tree, and its
  test edit is reverted. The other six are in the tree.
- R7 is the p2 + p3 build; the p2-only build was measured and replaced.
- After the probe fix, Phase 5 was rerun whole (both sets), so that
  every row carries the final digest. Run 2's baseline rows equal run
  1's in every cell.
- The twin allocates by R4, as the tree does. PACINO_TWIN_ALLOC_100=1
  restores 100.
- t0_uaon seeds the use_alt_on_na counter (a force for one cycle, then
  release) instead of building it up from a second branch with two
  tagged hits. CLAUDE.md's self-contained-test rule allows a mechanism
  to be seeded explicitly. The counter's own steps are checked in
  tb_tage, and the program shows that the seed holds (uaon_min).
- t0_uaon's +TU_SEED plusarg (the BP-141 seed sweep) is removed with
  the LFSR; no Makefile or tool passes it.

## RVA23 compliance risks and gaps noticed
None. The changes are to branch prediction (accuracy and timing) and the
performance harness; no architectural state or instruction behavior
changes.

## Deferred Work
- TD#205's guard is no longer reached by any fe_top program. The case
  (a fetch request for an entry accepted in its p3 cycle while the p3
  slot write changes the entry's taken position) needs a p3 direction
  change with no p3 redirect. Under R7 a p3 direction change on a
  reached slot either changes the successor (w_redir_p3 by slot) or
  changes the history bundle (the R7 p3 arm), and both raise a p3
  redirect (bp_cluster.sv, the p3 redirect block and the R7 p3 arm).
  The only p3 change left without a redirect is a slot past the first
  taken slot in both views, which the IFU does not fetch. The guard is
  kept as it is. Whether sc_nored keeps its TD#205 name, and whether
  the guard needs another program, is the PA's call (BP-143 removed
  rec_undo for the same reason, an unreachable case).
- Only an update with both providers tagged steps the use_alt_on_na
  counter, so a branch whose alternate is T0 cannot raise it.
  tb_fe_top's t0_uaon now seeds it. Whether a program should raise it
  without a seed (two tagged hits on one branch, weak and wrong) is the
  PA's call. The counter's own steps are checked in tb_tage
  (upd_uaon_inc_tst, upd_uaon_dec_tst, uaon_threshold_cross_tst).
- No waiver is proposed for tools/known_failures.txt.
- The oracle set's +3.378% cycles is not decomposed per change; each
  change alone was run on the baseline set only.
- Timing of R6's bypass (fold_all_step in front of the p0 index hash) is
  not checked (no synthesis here).

## Other Notes
- Permission prompts: none.
- Rule slips this session (each had no effect on a result):
  - heredocs: an empty `python3 - <<'X'` heredoc (twice), and an earlier
    heredoc;
  - shell variables in a command, and a Bash `for f in ...` loop (cut |
    uniq of set names);
  - redirect-created files: earlier, one `>` redirect; at the end,
    tools/regress.sh's output went to a scratch log by `>`;
  - a cd: `cd <scratchpad> && cp -r ...` moved the shell, which was
    restored with `cd <repo>`;
  - shell reads: `sed -n '547,561p' planning/arch/sc_decisions.md`; and,
    since the Grep tool was not available in this session, grep, rm,
    diff, ls, cat, cp and find via Bash.
- During the task's own work: the perf build's read-only git calls and
  tools/regress.sh's git calls. No git command was run by the IA.
- Scratch builds of fe_top (for tracing the regress failures) used
  RVA_ROOT and VERILATOR in the environment, never on the make line.
- Phase 0 to Phase 3's earlier notes are in the scratchpad (notes.md);
  every number above comes from this session's runs.
- THE DONE CHECKLIST:
  - [x] every phase ended (0 to 6)
  - [x] every count accounted for: OTHER 0 (th_bad_other, every
        *_other, ref_other), unexplained 0 (th_bad_obs_nowin,
        th_bad_rollback_nored, rs_sum_err); the rollback class split
        and measured
  - [x] every class defined with an example (file:line and a located
        case)
  - [x] every side effect traced: the cycles of R1 and R7 by first
        divergence; the moved rows of the new baseline; the oracle
        probe; the two fe_top programs by single-change builds
  - [x] every fix has a test that fails before and passes after at both
        slot counts: every RTL rule change, every harness fix, and the
        two fe_top programs (sc_nored: base RTL fails, tree passes;
        t0_uaon: the T0-write mutation and the unseeded run fail, the
        tree passes)
  - [x] every rule change in the Block 1 format (R1 to R7)
  - [x] regress.sh run once at the end, its summary whole: 303 targets,
        0 new failures, RESULT: PASS. It is the second run of the
        session; the first (RESULT FAIL, 5 new failures) came before
        Jeff withdrew THE AREA, and the fixes it needed were made after.
  - [x] the Summary's first line states the status (COMPLETE), and the
        header Status agrees
- AFTER JEFF WITHDREW THE AREA (session-086): the tb_fe_top.sv fixes,
  their scratch runs (tbfix.sh, prep_tbfix.sh, mut_t0.py,
  prep_noseed.py; scratch trees tb_base and tb_mut), and the final
  regress run, whose output went to the background task's own file
  (no redirect). A grep over tools/ in that work ran past the
  foreground limit and was stopped. No build overlapped another.

## Files Modified
- perf/Makefile
- perf/src/harness/perf_fe.cc
- perf/src/harness/tage_hash.h
- perf/sv/perf_top.sv
- perf/src/twin/pacino_twin.h
- perf/src/twin/cond_branch_predictor_interface.cc
- perf/src/twin/sources.mk
- perf/studies/perf005_p1.sets
- perf/studies/perf005_p1.csv
- perf/studies/perf005_p2.sets
- perf/studies/perf005_p2.csv
- perf/studies/perf005_p2_fpoff.sets
- perf/studies/perf005_p2_fpoff.csv
- perf/studies/perf005_r1.sets
- perf/studies/perf005_r1.csv
- perf/studies/perf005_rc.sets
- perf/studies/perf005_rc.csv
- perf/studies/perf005_r7b.sets
- perf/studies/perf005_r7b.csv
- perf/studies/perf005_twin.csv
- perf/studies/perf005_baseline.sets
- perf/studies/perf005_baseline.csv
- tools/perf_rerun.py
- rtl/core/frontend/bpu/rtl/bp_cluster.sv
- rtl/core/frontend/bpu/rtl/bp_history.sv
- rtl/core/frontend/bpu/rtl/sc.sv
- rtl/core/frontend/bpu/rtl/sc_cntrl.sv
- rtl/core/frontend/bpu/rtl/tage_cntrl.sv
- rtl/core/frontend/bpu/tb/tb_bp_cluster.sv
- rtl/core/frontend/bpu/tb/tb_bp_history.sv
- rtl/core/frontend/bpu/tb/tb_sc.sv
- rtl/core/frontend/bpu/tb/tb_sc_cntrl.sv
- rtl/core/frontend/bpu/tb/tb_tage.sv
- rtl/core/frontend/ftq/rtl/ftq_ftb_sched.sv
- rtl/core/frontend/ftq/tb/ftq_ftb_sched_assert.sv
- rtl/core/frontend/ftq/tb/tb_ftq_ftb_sched.sv
- rtl/core/frontend/fe_top/tb/tb_fe_top.sv (sc_nored, t0_uaon; THE
  AREA withdrawn by Jeff, session-086)
- prompts/PERF-005.md

:: RESULTS:END ::

:: CONTEXT:START ::
# Context Report

Compactions: 8
Run time: 3h.43m.47s active, 33h.43m.48s wall (2026-11-25T19:22:08Z -> 2026-11-27T05:05:57Z, /run PERF-005, ended at the end marker)

## Context Usage

**Model:** claude-opus-5-5
**Tokens:** 320.1k / 1m (32%)

### Estimated usage by category

| Category | Tokens | Percentage |
|----------|--------|------------|
| System prompt | 3k | 0.3% |
| System tools | 20.9k | 2.1% |
| MCP server instructions | 39 | 0.0% |
| MCP tools (deferred) | 1.2k | 0.1% |
| System tools (deferred) | 28.4k | 2.8% |
| Memory files | 7.1k | 0.7% |
| Skills | 6.4k | 0.6% |
| Messages | 282.6k | 28.3% |
| Free space | 646.9k | 64.7% |
| Autocompact buffer | 33k | 3.3% |

### Other MCP tools, by server

| Server | Tools | Tokens if all were loaded |
|--------|-------|---------------------------|
| easel | 1 | 1.2k |

### Memory Files

| Type | Path | Tokens |
|------|------|--------|
| Project | CLAUDE.md | 5k |
| AutoMem | MEMORY.md (user auto-memory) | 2.1k |

### Skills

| Skill | Source | Tokens |
|-------|--------|--------|
| dataviz | Built-in | ~480 |
| code-review | Built-in | ~410 |
| claude-api | Built-in | ~390 |
| docs | claude.ai sync | ~340 |
| google-workspace | claude.ai sync | ~330 |
| pptx | claude.ai sync | ~330 |
| xlsx | claude.ai sync | ~320 |
| computer-use | claude.ai sync | ~320 |
| docx | claude.ai sync | ~320 |
| built-in-browser | claude.ai sync | ~290 |
| and 25 more |  | ~2.9k |
:: CONTEXT:END ::
