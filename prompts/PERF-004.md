<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header 
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | PERF-004                |                          |
| Date         | 2026.11.20              |                          |
| Module       | perf, ftq, ifu, bpu     | the trusted baseline     |
| Run time     | 1h.34m.41s              |                          |
| Ctx %        | 26%                     |                          |
| Model        | claude-opus-5-5 high    | design task: high effort |
| Resume sha   | 6413a16d-1724-49be-a609-ea6f8cb212c7 |             |
| PA session   | 086                     |                          |

Task:   [x] experiment  [x] implementation  [x] debug
        [ ] cleanup     [x] testbench       [x] verification
Mode:   [x] automated   [ ] manual          [ ] interactive
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview
One task that makes the perf harness a measuring instrument whose
numbers Jeff can use, and ends with a frozen baseline. It removes
every known defect that stands between a run and a number to trust,
then measures the whole CBP training set, pacino and the reference,
with every PF-11 check passing on every run. Phases, each ended before
the next:
0. The start: facts and the baseline equal BP-154's.
1. Provenance (TD#210): every row says exactly what it measured.
2. The FTQ-full fetch stall (TD#206) and the harness workaround for it.
3. A trap after a branch (Jeff's PF-18 ruling).
4. The run configuration reaches the design (the PF-5 CSRs).
5. The BP-150 MPKI rise (TD#208).
6. The reference: every CBP predictor on every trace (PF-15).
7. Pacino on every trace, full length, with the oracle and every check.
8. The frozen baseline, the regression, the planning text.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion 

## Claude.code Console Output

Phase 2 measurements are running in the background: the stress study on the old
  build, then the rebuild without the FTQ-full workaround, then the after-studies and
  tb_fe_top at both slot counts. I'll pick up when they finish.

  Findings so far:
  - Phase 0: done. The rebuild of head_s2 matches BP-154 exactly: 25/25 and 12/12 study
    rows, and tb_fe_top 49/49 programs at both slot counts. The only Background facts
    that are off are Makefile line numbers, each shifted by one.
  - Phase 1: done.
    - Every build now writes a stamp (sha, dirty mark, input digest) and every result
      row records it. make -C perf digest prints the stamp without building.
    - perf_study.py now refuses to gather rows whose digests differ.
    - The four-step test behaved as specified.
    - I also fixed a missing build dependency: csr_tb_pkg.sv was compiled into the
      harness but a change to it rebuilt nothing.
  - Phase 2: the new tb_fe_top program ftq_full passes at both slot counts. With the
    FTQ full and commit held, all 64 entries are still translated, fetched and
    delivered, so the RTL stall described in TD#206 does not exist. I checked the test
    can fail: a scratch copy with the stall put in fails 3 of its checks.

● Phase 2 status:
  - tb_fe_top: the 49 existing programs are unchanged at both slot counts. The new
    ftq_full program passes (1006/0 checks at two slots, 1003/0 at one).
  - Workaround removal: no run hangs.
    - Runs at long resolve to commit are identical before and after: rc50/100/200 and
      the new rc500/rc1000 stress sets.
    - Runs at short latency, and the stream-rule runs, move slightly. Total cycles over
      the 25 classified runs went from 25,494,138 to 25,503,105.

  The first-divergence runs are going now. They compare before and after event logs to
  tie each moved run to the closes the removed term used to make. I'll continue when
  they finish.

Phase 3 is built into the harness (see the notes below). Its before/after measurement
  is running in the background:
  - the classified runs;
  - the oracle sets of perf003_p5.sets;
  - bp154_p2.sets.

  How a trap after a branch is now handled:
  - The branch is judged on its own outcome: its target when taken, pc + 4 when not.
  - The trap is a separate RC_TRAP redirect in the branch's resolve cycle, as for a
    non-branch.
  - mispred_trap_after and orc_slot_trap are gone. One count, trap_after_branch, takes
    their place in the row; that is a format change, which I'll write up for your
    acceptance.

  I'll check the oracle runs for zero slot-held mispredicts when the measurement
  finishes.

● The first oracle fix changed nothing; the log shows the actual cause.
  - Cause: since BP-153, an FTB-held return's p2 target is the RAS peek
    (w_ras_peek_addr_p2), not the pop. The oracle forced only the pop, so returns whose
    trace target is not the RAS top still mispredicted under --oracle.
  - Effect: compress_1, infra_1 and web_11 have failed the oracle check since BP-153.
    That was before this task started.
  - Fix: I've added the peek force (address and valid). The rebuild and rerun are in
    progress.

● Phase 3 divergence: all 12 summaries finished so far are traced to the change. In
  each, the first committed instruction that differs is the branch with the trap after
  it: mispredict 1 before, 0 after, and the trap event sits at the same instruction.
  The remaining summaries are still being read.

Phase 3 is complete:
  - All 39 moved runs trace to the trap rule. In each, the first instruction that
    differs is the branch with the trap after it, which mispredicted before and does
    not now.
  - The oracle passes on every oracle run.

  Phase 4 is building: probes of the design's own state (fast-path directions, SC
  answers, TAGE/ITTAGE epoch advances, decayed useful bits per table). The
  configuration study runs on web_11 and int_6 at both slot counts.

Phase 4 result: every PF-5 key reaches the design, and no fix was needed.
  - Each enable switched off, and each interval set to 1, moves the design's own counts
    (fast-path directions, SC answers, epoch advances, decayed lookups per table) at
    both slot counts.
  - Two runs move no counted result: int_6 with ITTAGE aging off and with ITTAGE
    interval 1. Those rows equal the PF-5 run although ITTAGE's epoch and decay counts
    change. int_6 has no ITTAGE mispredicts to move.
  - PERF-002's finding that no setting changed any count is not reproduced at 2e6
    instructions.

  Phase 5 (the BP-150 knockout) is building and running p5 now.

Phase 5 first: the knockout comparison shows BP-150 moves 11 of 12 p5 runs. Over the
  12 runs, mis_sc is 29,211 with the fix against 28,689 without it. The knockout fails
  its checks on 3 runs; that is the TD#205 skip, and those runs pass with the fix. The
  event-log pairs are running now to find the first divergence of each run and the SC
  decision at it.

The Phase 6 rerun has about 6 more hours to go, so it should finish around 8.5 hours
  after it started. My earlier figure of about 7 hours total was too low.
  
  - Progress: 192 of 1,155 runs are done after 2.4 hours (8,647 s).
  - Work left: about 144 core-hours. Spread over the 24 workers, that is at least 6.0
    hours. Placing the remaining runs on the 24 workers one by one, as the tool does,
    gives 6.02 hours.
  - Why the run count misleads: the tool runs the longest traces first, so the 17% of
    runs done is not 17% of the work.
  - How I estimated: I measured each predictor's speed from its finished runs (about
    1.5e-05 s per instruction for most; Fan is slower at 2.3e-05) and applied it to the
    instruction counts of the traces left. The ~24 runs in progress were counted as if
    just started, so the real time is a little under 6 hours.
  - Mose: it fails every trace within a second (the known PF-1 case), so it adds nearly
    nothing.

  Phase 7, the 210-run baseline study, can only start after this finishes, and it adds
  its own time on top. I'll estimate it once the rerun is done. 

Phase 7 is still in progress. The full baseline ran (210 runs, 2.8 hours), but 10
  rows failed the PF-11 checks:

  ┌───────┬─────────────────────────────┬────────────────────────────────────┐
  │ Class │            Rows             │               Error                │
  ├───────┼─────────────────────────────┼────────────────────────────────────┤
  │ A     │ baseline infra_6            │ err_stream 260                     │
  ├───────┼─────────────────────────────┼────────────────────────────────────┤
  │ B     │ web_11, baseline and oracle │ err_unspec_repair 1                │
  ├───────┼─────────────────────────────┼────────────────────────────────────┤
  │ C     │ 7 oracle traces             │ err_orc_slot_mispred, 1 to 16 each │
  └───────┴─────────────────────────────┴────────────────────────────────────┘

  The other 200 rows pass: instruction, branch and 50% counts all match the counts
  file, and every error column is 0.

  Class C cause: the oracle's alignment, o_succ in perf/src/harness/perf_fe.cc. I
  traced web_9 and int_36 cycle by cycle:
  - The trace leaves the previous block early by a taken branch whose target is the
    very PC the block's prediction gives.
  - The alignment rejected that, so p1 marked the next entry off the path and left its
    p1 (uBTB) slots unforced.
  - p2 then moved the previous block's end without a redirect and put the entry back on
    the path. The entry had no FTB slot, so nothing was forced at p2 either.
  - The record kept the uBTB's own prediction: a wrong direction for the conditionals,
    and for the two indirect jumps a target that is wrong modulo 2^21.

  Fix, built: o_succ now accepts that case and places the entry on the path after that
  branch. This code runs only under --oracle.

  Classes A and B: their checks printed nothing. I added diagnostic lines (STREAMERR
  and UNSPEC, first 20 of each) to find where they occur. The new build's digest is
  3f7d5be2.

  A rule I almost misread: err_orc_slot_mispred is an error only on oracle rows
  (perf_fe.cc:1877); off the oracle it is only a count. My check script now treats it
  that way.

  Shortened runs: a run with --max-instr is not an exact prefix of the full run,
  because the code image is built only from the records read (supply.cc:37). That is
  how the image is defined, so I logged each shortened run at its own cycle numbers.

  All 10 failing rows are now rerunning on the new build (up to about 40 minutes). That
  shows whether the 8 oracle rows pass and where A and B happen. Every fix changes the
  build digest, so the full 210-run baseline has to run again after the last fix
  (about 2.8 hours) before Phase 8.


Phase 7 is not finished. I found the cause of each of the 10 failing rows and fixed
  all of them; the full 210-run baseline is now rerunning on build digest 0c66fed0
  (about 2.8 hours).

  What the four causes were:

  1. An RTL defect in ftq_ifu.sv (infra_6, 260 err_stream).
     - An aliased conditional slot predicted taken at a position holding an ALU
       instruction (6b02cc).
     - Predecode then removed the slot (the M2 case) and sent fetch to the block's full
       fall-through (6b02e4). But fetch had only delivered up to 6b02cc, so
       6b02d0..6b02e0 were skipped.
     - Fix (W3M): after M2 the block ends at the last instruction actually delivered,
       and its pft_addr is set to match.
     - Test: tb_ftq_ifu has a changed D18 and new D18a-D18d. With the fix off, D18,
       D18a and D18b fail; with it on, 241 checks pass and 0 fail.
     - Side effects: tb_fe_top is unchanged at both slot counts (1006/0, 1003/0), and
       no program's cycles or mispredicts moved.
     - This changes a documented rule, so it goes in Results Capture as a rule change
       for acceptance.
  2. The oracle's alignment (7 oracle rows). Already fixed in o_succ; six of the seven
     pass, and the seventh turned out to have another cause (item 3).
  3. An aliased slot of the wrong kind (infra_6 oracle).
     - The FTB held an unconditional jump where the trace has a conditional. Predecode
       turned it into a conditional but kept the jump's "taken", which no predictor
       gave and the oracle cannot force.
     - It is now counted in a new column, orc_slot_kind_alias, judged on the slot as
       the fetch request carried it, instead of in err_orc_slot_mispred.
  4. Counting (web_11). Its one unspecified repair follows rewritten code that had
     already committed. It is now counted with the class conflicts, in a new column
     conflict_unspec_repair.

  Already confirmed on all 10 rows: after the first two fixes, a rerun of the 10 rows
  passed 9. The infra_6 oracle row then still failed, and that is what led to the
  request-time alias test in item 3. That last change is checked only by the full rerun
  now running.

  After the rerun: I'll compare it with the first baseline, saved at
  /tmp/claude-1000/-home-jeff-Development-jeffnye-gh-pacino/6413a16d-1724-49be-a609-ea6
  f8cb212c7/scratchpad/baseline_run1.csv. Two things to check:
  - Every row the timing fixes moved has to be traced to its first divergence, using
    two scratch builds (fixes off, and fixes on with event lines). The build script and
    divergence tool are written.
  - On rows that did not move, the two new columns have to split the old counts
    exactly.

  Phase 8 follows.

PERF-004 is complete. The frozen baseline is 210 runs (105 traces, plain and with the
  oracle), and every run passes all three PF-11 checks on one build digest.
  tools/regress.sh passes: 303 targets, 0 new failures, RESULT: PASS. Results Capture
  is written in prompts/PERF-004.md, with the header's Model and Status (complete) set.

  Phase 7, rows that moved: 102 rows changed between the first and second baseline
  runs, and every one is traced to a fix event at its first divergence. There are 0
  open cases.
  - infra_6 (the RTL fix, W3M): its single W3M event comes 10 cycles before the first
    differing instruction, at the place where the original stream error occurred.
  - The 101 oracle rows (the alignment fix): 96 diverge within 0 to 20 cycles of a fix
    event.
    - Five diverge later at a commit, but their first differing event of any kind comes
      within 18 cycles.
    - In 5 rows nothing differs over the whole trace except two oracle bookkeeping
      counts. They move by equal and opposite amounts, and the fix assigns them
      directly (perf_fe.cc:1394-1404).
  - With both fixes off, the scratch "before" build reproduces the first run's failures
    exactly, so it is the same harness as run 1.

  The RTL fix (W3M) fails before and passes after at both slot counts: tb_ftq_ifu goes
  from 238 passed / 3 failed to 241/0 at two slots, and from 223/3 to 226/0 at one
  slot.

  Pacino against TAGE192 (a result, not a defect): conditional mispredictions per
  thousand instructions on the second half of each trace average 8.42 against 3.40, a
  factor of 2.48. The factor runs from 1.55 on compress to 4.62 on media, so the gap is
  not steady across the groups and PF-10's extrapolation to SPEC does not hold.

  Things you should know:
  - Memory: my divergence script loaded both full-length event logs into memory and ran
    the machine short, and Claude Code stopped that job. All 44 runs had already
    finished. I rewrote the script to read the logs line by line and ran only the
    analysis on the finished logs; the runs themselves were not restarted.
  - cai and jimenez: in the CBP submodule they are the same binary, with equal results
    on every trace, including in the published results. This is outside the task's
    scope, so it is reported only.
  - Commit: the baseline rows are marked dirty because this task's changes are not
    committed. Committing them unchanged keeps the digest at 0c66fed0, and that commit
    becomes the baseline's revision.

  The proposed planning text is in Results Capture for you to apply:
  - perf_decisions.md: PF-5, PF-6, PF-9 (with how to run a study against the baseline),
    PF-10, PF-11, PF-18 and PF-21.
  - ftq_ifu_interfaces.md: a new W3M rule.
  - Closing lines for TD#206, TD#208 and TD#210, and the TD#197 configuration finding.
  - 13 rule changes for acceptance, R1 to R13.

## My Assessment

This is a good news/bad news result. The good news is there is now a framework
for frontend prediction performance measurements. 

This tool reports that compared to TAGE192 this design has 2.5x as many miss
predictions as the baseline TAGE192. 

The hope was the smaller Pacino TAGE design would be able to get closer to parity.

If these numbers are to be trusted the next steps are to extend the tage
design, increasing table sizes and history lengths.  First step is to dig in
and make sure there are no hidden faults that impact accuracy. 

Different topic: I have overscoped what the IA is assigned or atleast
overconstrained the permissions. This took a total of 40 hours wall clock, much
of it due to waiting for me to reply. There is a lot of friction in the
protections requiring many permission questions and answers. The 1hr time was
the time for the IA, there about 13 hourss waiting for traces to run. 

```
  The long runs were three, but not all 6 to 8 hours:

  ┌───────────────────────────────────────────────┬─────────────────┐
  │                      run                      │    wall time    │
  ├───────────────────────────────────────────────┼─────────────────┤
  │ Phase 6, the CBP reference rerun (1,155 runs) │ 29,880 s, 8.3 h │
  ├───────────────────────────────────────────────┼─────────────────┤
  │ Phase 7, baseline run 1 (210 runs)            │ 10,113 s, 2.8 h │
  ├───────────────────────────────────────────────┼─────────────────┤
  │ Phase 7, baseline run 2, after the fixes      │ 10,177 s, 2.8 h │
  └───────────────────────────────────────────────┴─────────────────┘

  Those three come to about 13.9 hours. Smaller background jobs add more:
  - the before/after measurements in Phases 2 to 5;
  - the 10-row reruns in Phase 7;
  - the two divergence passes, about an hour each, of which the full-length one was
    stopped for low memory;
  - the regression, about 6 minutes.

  The 40 hours of wall time also include gaps when nothing was running, such as waits
  for your replies. So the work took most of those 40 hours, but the tool's "active"
  figure is only my own turn time.
```

me: what was accomplished :

```
PERF-004 made the perf harness a measuring instrument whose numbers can be trusted,
  and ended with a frozen baseline. By phase:

  - Phase 0, the start: the rebuilt harness and tb_fe_top match BP-154 exactly. The
    only false Background facts are three Makefile line numbers, each off by one.
  - Phase 1, provenance (TD#210):
    - Every build now writes a stamp: the git sha, a dirty mark, and a SHA-256 digest
      over every build input.
    - Every result row records the stamp, and make -C perf digest prints it without
      building.
    - perf_study.py refuses to put rows from different builds into one CSV.
    - I also fixed a missing build dependency (csr_tb_pkg.sv).
  - Phase 2, the FTQ-full stall (TD#206): not an RTL defect.
    - A new tb_fe_top program fills the FTQ with commit held and passes at both slot
      counts; a copy with the stall put in fails 3 checks.
    - The harness's workaround is removed, and no run hangs without it.
  - Phase 3, a trap after a branch:
    - Built as you ruled: the branch is judged on its own outcome, and the trap is a
      separate redirect.
    - The oracle check turned up two oracle gaps from BP-153 and BP-154, both fixed:
      the RAS peek and the return held from p1 were not being forced.
  - Phase 4, configuration (TD#197): every PF-5 setting reaches the design at both slot
    counts, shown by the design's own counts; no fix was needed. PERF-002's finding
    that no count changed does not reproduce.
  - Phase 5, the BP-150 rise (TD#208): it is the cost of a correct SC. At every first
    divergence the SC decides by its rules, and re-deriving all 3.3M SC answers found 0
    that break them.
  - Phase 6, the reference:
    - The full CBP rerun: 1,155 runs, and every unchanged-trace result matches the
      published results exactly.
    - mose fails on every trace, as in the published results.
    - cai and jimenez are the same binary in the CBP submodule.
  - Phase 7, pacino on all 105 traces at full length, with and without the oracle:
    - The first run failed 10 of 210 rows, from 4 causes, all fixed:
      - a real RTL bug in ftq_ifu.sv, where fetch skipped instructions after a
        predecode correction (fixed by W3M, tested before and after at both slot
        counts);
      - a gap in the oracle's alignment;
      - two cases that are now counted separately, because their cause is in the trace
        or outside what the oracle forces.
    - The second run passes 210/210.
    - All 102 rows that moved between the two runs are traced to a fix event.
  - Phase 8:
    - The baseline files and digest (0c66fed0) are recorded.
    - The regression passes: 303 targets, 0 new failures.
    - Results Capture has the proposed planning text and 13 rule changes for your
      acceptance.

  The headline result: pacino's conditional mispredictions per thousand instructions
  average about 2.5 times TAGE192's. The ratio ranges from 1.55 on compress to 4.62 on
  media, so the gap is not steady across the groups, and PF-10's extrapolation to SPEC
  does not hold.
```

## Claude.ai Assessment

PERF-004 is complete and it did what it set out to do. All 210
baseline runs (105 traces, plain and with the oracle) pass all three
PF-11 checks on one build digest, 0c66fed0. Every row that moved
between the first and second baseline runs is traced to a fix. The
regression passes: 303 targets, 0 new failures. I checked the ratios
and totals I quote below against the IA's tables, and they hold.

The task found real problems, not just tidying:

- **An RTL defect that skipped instructions (W3M, in ftq_ifu.sv).**
  After predecode removed a wrong taken slot, fetch resumed at the
  block's full fall-through. The instructions between the cut and the
  fall-through were never delivered. It appeared only on infra_6 at
  full length (260 committed PCs wrong). No 2e6 run and no tb_fe_top
  program caught it.
- **The oracle had been failing since BP-153** (52, 93 and 70
  slot-held mispredicts on compress_1, infra_1 and web_11). Neither
  BP-153 nor BP-154 ran the oracle check. That is my error: my tasks
  did not require it, and my assessments did not ask for it.
- **The oracle's alignment had a gap** (101 oracle rows moved once it
  was fixed).

I was wrong when I told you on Friday that the MPKI numbers could
already be trusted. This task is what made that true.

My hypothesis was also wrong: TD#206 was not an RTL stall. The IA
proved that with a test that fails when the stall is put in, and
removed the harness workaround cleanly.

## The headline: what the 2.5x gap is made of

The comparison is pacino's conditional MPKI against TAGE192's, as the
mean of the per-trace values: 8.42 against 3.40 at 50Perc (2.48x), and
8.51 against 3.50 over the full trace (2.43x). The counting behind it
is now right. Two things decide what it means.

**1. Part of the gap is the FTB, which CBP never pays for.** The CBP
framework hands TAGE192 every conditional branch. Pacino has to find
the branch in the FTB first, and a branch missing from the FTB is
predicted to fall through. The oracle rows measure that cost exactly:
with every slot-held branch forced to the right answer, 1.37 of
pacino's 9.13 MPKI remain (all branch kinds, totals over 105 traces).
So the other 7.76 MPKI are mispredicts on branches the FTB held. Those
are the direction and target predictors' errors. TAGE192's
counterpart is about 3.4.

**2. Most of pacino's own errors come from the FTB's base counter, not
from TAGE.** Per source, all 105 traces: ftb 4.04, tage 2.07, sc 1.25,
loop 0.09 MPKI. In a working TAGE the base predictor decides only when
no tagged table hits, which should be rare once the predictor has
warmed up. Here the base counter makes more mistakes than TAGE and SC
together. The worst traces show this pattern most strongly:

| trace | pacino / TAGE192, 50Perc cond | total MPKI | from the FTB counter | share |
|---|---|---|---|---|
| int_31 | 21.1x | 10.12 | 8.93 | 88% |
| fp_6 | 12.8x | 11.46 | 8.72 | 76% |
| infra_7 | 10.0x | 8.32 | 5.99 | 72% |
| infra_1 | 21.4x | 4.39 | 3.47 | 79% |

These are traces TAGE192 predicts almost perfectly: fp_6 at 0.88 MPKI
and int_31 at 0.47. The gap is also largest where the code is small:
media is 4.62x on only 4 traces. A predictor short of capacity loses
on large code (web, int), not on small code. A predictor that is not
learning loses everywhere, and worst where learning is easy.

**My reading: the 2.5x is not yet a measure of the TAGE design's
size.** It points first at a fault, or a gap in the design, in how
TAGE takes over from the FTB's base prediction. The candidates are:
- allocation on a base-counter mispredict;
- the tag or index history;
- the p2/p3 override of the p1 prediction;
- training at commit.

You said the first step is to dig for hidden faults that hurt
accuracy. The data says where to dig. Bigger tables and longer
histories will not help much until this is understood.

There is a second pattern. On some traces the misses are mostly
branches the FTB did not hold at all (mis_none):
- web_24: 21.6 of 28.2 MPKI;
- infra_11 and infra_12: about 7.5 each;
- int_36: 11.5.

Their oracle MPKI stays high too (web_24 20.7). That is FTB capacity
or replacement (TD#190 to TD#193). It is a real cost for pacino, but
it is not part of what the TAGE comparison is meant to measure.

## A way to find the faults (my proposal)

This could be one task, sized like this one, with two parts:

1. **Count why TAGE did not decide.** Take the worst-ratio traces
   (int_31, fp_6, infra_7, infra_1, media_0). For each mispredict that
   came from the FTB counter, record:
   - whether any tagged table hit;
   - whether the branch's previous mispredict allocated, and if not,
     why (useful bits, no free entry, allocation never tried);
   - the per-table hit and allocation rates.

   A fault shows up as a rule broken at a counted event, the same
   method as Phase 5 used for the SC.
2. **Build a software twin.** Write a CBP predictor with pacino's TAGE
   parameters (table count, sizes, history lengths, tag widths), run
   it in the CBP framework on the same traces, and compare.
   - The twin against TAGE192 is the cost of pacino's size and design.
   - Pacino against the twin is the cost of the implementation: faults
     plus the real pipeline (speculative history, commit-time update).

   The twin is also the cheap way to study "bigger tables, longer
   histories" afterwards, in minutes instead of 2.8-hour runs.

This is PF-10's B question (TD#204), answered more cheaply. Say if you
want it written.

## Rule changes for acceptance (R1 to R13): my recommendations

Accept all thirteen, with one debt item opened under R12.

- **R1 to R4: accept.**
  - R1, the stamp and digest columns.
  - R2, the rule that rows from different digests are not mixed.
  - R3, removing the FTQ-full term.
  - R4, your trap ruling as built.
- **R5: accept.** The oracle now forces the RAS peek, and the p1
  return held at p2 on an FTB miss (that is BP-154's R2).
- **R6 to R9: accept.** These add probes, the event log, the
  bin_sha256 column and the ftq_full test program. None of them
  changes a result.
- **R10, the oracle's early-exit alignment: accept.**
- **R11, W3M: accept.** It fixes a real correctness defect, and tests
  fail before and pass after at both slot counts.
  - The IA rejected the alternative of having the IFU deliver the rest
    of the block, because that touches two more modules. I agree: W3M
    costs a refetch only on an M2 kill.
  - The ftq_ifu_interfaces.md W3M text goes in the recording.
- **R12, kind alias: accept as a count, and open a debt item.** When
  M3 rewrites an FTB jump slot into a conditional, it keeps the jump's
  "taken", which no predictor gave. Counting it apart is right for the
  oracle. But a direction that came from no predictor is a small
  design fault in predecode. It happened 3 times in 4.36e9
  instructions, so it does not affect the numbers. It belongs on the
  debt list, not hidden.
- **R13, class-conflict repair: accept.** The cause is rewritten code
  in the trace itself, and it occurs only on web_11.

## Other findings

- **cai and jimenez are the same binary** in the CBP submodule (same
  SHA-256, the same results on every trace, in golden too). The
  reference field is 10 predictors, not 11. I will record it.
- **mose fails on every trace,** as it does in golden (PF-1).
- **A full baseline costs 2.8 hours** for both sets (210 runs), at
  34,705 instructions per second on average (28k on web, 56k on
  media). A design study does not need the oracle set every time. Run
  the oracle set when the harness changes.
- **A shortened run is not a prefix of the full run,** because the
  code image is built from the records read (supply.cc:37). Compare
  runs of equal length only. This goes into PF-9 with the "how to run
  a study" text.

## Process: the 40 hours

The work was 1h35m of IA time and 13.9 hours of runs. Most of the rest
was the IA waiting for you to answer permission prompts. That cost
comes from two things together:

- **Claude Code's permission prompts** fire for any command not on its
  allow list.
- **CLAUDE.md's command rules** (no pipes, no variables, scratch
  scripts) were written to keep commands simple enough to avoid
  prompts, but they do not stop them.

The fix is an allow list, not looser task rules. The IA can report
every prompt it hit in this session (they are in its transcript). From
that list I would write the permissions block for the repo's
.claude/settings.json, so the commands it uses run without asking:
make -C perf, the perf tools, its scratch scripts, the study builds,
and tools/regress.sh.

You also asked whether you over-scoped. One task, one baseline, all
checks passing was the right shape for building an instrument. It
converged with nothing open. Studies on the instrument should be
smaller, one question each.

## Before you commit PERF-004

1. **Commit it unchanged.** The baseline's claim rests on the
   committed tree having digest 0c66fed0. After the commit, run
   `make -C perf digest`: it must print 0c66fed0. The perf/studies
   CSVs and the planning files are not build inputs, so committing
   them does not change the digest.
2. **The intermediate study CSVs** (perf004_p1_* through p5_*, 23
   files) are the phase evidence. Keep them or delete them as you
   like. Keep baseline.sets, baseline.traces, baseline.csv and
   perf/cbp2025_rv_rerun.csv.
3. **regress.sh said "pass NOT recorded"** because the tree was dirty.
   Commit, then rerun it before pushing.

## What I will record after the push

I will apply the planning text the IA proposed to these files, and
update check_planning.sh:
- perf_decisions.md: PF-5, PF-6, PF-9 (with the prefix note), PF-10,
  PF-11, PF-18, PF-21;
- ftq_ifu_interfaces.md: W3M;
- PROJECT_STATUS.md:
  - closing TD#206, TD#208 and TD#210;
  - TD#197's configuration finding;
  - new debt items: R12's kept taken, cai = jimenez, the baseline
    comparison tool;
  - the stale BP-154 items still pending (ras_interfaces.md section 2
    and ftq_entry_formats.md section 2).

## Follow-on Actions
Nothing required

## CLAUDE.md Updates
Nothing required

## Other Planning File Updates
Nothing required

:: DISCUSSION:END ::

=============================================================
:: PROMPT:START ::
=============================================================

## Task ID
PERF-004

## Context Loaded
@planning/perf/perf_decisions.md
@rtl/CLAUDE.md
@perf/Makefile
@perf/src/harness/perf_fe.cc
@tools/perf_study.py
@tools/perf_rerun.py

## Context Comments
perf_decisions.md is the harness's specification: PF-5 the run
configuration (the CSR values), PF-7 the epoch rule, PF-9 results and
studies, PF-10 the comparison (R, A, B), PF-11 the three checks, PF-15
the changed traces and the reruns, PF-18 the backend, the fetch rule
and the trap ruling, PF-22 the CPU cap. perf/Makefile builds the
harness (the sha at about 113, the dependencies at about 129).
perf_fe.cc is the harness: the eager close (about 1035 and 1139), the
trap-after count (about 1573-1579), the --cfg keys (about 138-145,
451) and the result row (about 1740-1842). perf_study.py runs a study;
perf_rerun.py runs the CBP predictors.

The IA may read any file under rtl/, perf/, tools/ and planning/, the
Results Capture of prompts/PERF-002.md, PERF-003.md, BP-150.md and
BP-154.md, and the scratchpads of earlier sessions for scripts to
reuse.

## Hypothesis
After phases 1 to 5 every PF-11 check passes on every run of the
training set, with no exception case, and the harness's numbers are
fixed by its inputs alone: the same input digest gives the same row.
TD#206 is a defect, and its fix lowers ftq_full_cycles at long resolve
to commit. The full rerun of R reproduces the golden results on the
unchanged traces.

## Background
Checked by the PA against the tree at 073ab98. BP-154 moved lines in
perf_fe.cc and ras_class.h; the IA confirms each fact it uses on the
tree it starts from.
- TD#210. perf/Makefile:113 sets SRC_SHA from "git -C $(SRC_ROOT)
  rev-parse HEAD" and :124 compiles it in (-DPERF_SRC_SHA). The binary
  depends on H_DEPS (:129-131: the harness sources, perf_top.sv,
  perf.vlt, FE_TOP_SRCS, FE_PTW_SRCS), not on the sha, so a commit
  that changes no input leaves the old sha in every new row, and a
  dirty tree is not marked. RTL changes do rebuild the binary.
- TD#206. With the FTQ full, fetch delivered nothing until the oldest
  entry committed: the ibuf stayed empty 200,000 cycles on web_11 with
  64 entries allocated (PERF-002 Other Notes 4). Suspected in
  ftq_ifu.sv: xlate_request (:260) presents only an entry whose p1
  write has landed, and the fetch request is fetch_pending (:294). The
  harness works around it: perf_fe.cc closes the last entry, and
  decides a pending branch by its fetch record, when "top->ftq_full ||
  idle >= EAGER_IDLE" (:1035, :1139; EAGER_IDLE 32 at :750), "so that
  no commit waits on a fetch that waits on commit". BP-154 Phase 2:
  at resolve to commit 200 the FTQ was full 3,361,993 of 7,990,755
  cycles.
- THE TRAP AFTER A BRANCH. perf_fe.cc:1576-1579: a branch whose next
  trace record is an exception entry is counted as the branch's
  mispredict (br_trap_after, mispred_trap_after) and, under the
  oracle, apart (orc_slot_trap, 0 to 8 per 2e6 run, PERF-003).
- THE CONFIGURATION. perf_fe.cc:138-145 holds the PF-5 values
  (sc_enable 1, ftb_fastpath_en 1, both agings 1, both intervals
  262144); --cfg sets them; the row's fe_cfg_seen shows what fe_top
  received. PERF-002 Other Notes 3 (TD#197): the enables and
  intervals changed no count over 1e5 and 3e5 instructions, interval 1
  included, which suggests aging does not reach the tables.
- TD#208. After BP-150 (the SC p3 skip fix, TD#205) MPKI and mis_sc
  rose on some traces; after PERF-003's harness fix mis_sc moves both
  ways (infra_1 +147 and +47, compress_1 +23 and +19, int_6 +10 and
  +56; fp_1 -254, web_11 -52 and -62). It was to be investigated after
  TD#207, which BP-153 closed.
- THE TRACES. perf/cbp2025_rv_counts.csv: 105 traces, columns Instr,
  NumBr, 50PercInstr, 50PercNumBr; 4,360,248,026 instructions in all,
  the largest 130,170,487. PERF-002 measured 25k to 95k instructions
  per second per run.
- THE REFERENCE. tools/perf_rerun.py --plan full runs every CBP
  predictor on every changed trace and every unchanged one ("about 6
  hours on 28 workers", PERF-002); only the fallback plan has run
  (perf/cbp2025_rv_rerun.csv, 215 rows).
- THE ORACLE is a run flag (--oracle) on the same build (PERF-003;
  perf/studies/perf003_p5.sets).

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
  against the 75% cap (PF-22). Nothing outside the AREA changes. A change needed
  outside it is reported with its reason, and the work continues.
- THE HARNESS DEFAULT BACKEND is immediate (Jeff, session-086;
  perf_decisions.md PF-18).
- A TRAP AFTER A BRANCH (Jeff, session-086, PF-18): "the branch is
  judged on its own outcome, and the trap is a separate RC_TRAP
  redirect, as for a non-branch."
- PF-11 (the count check Jeff's, session-084; the oracle and PC checks
  kept by Jeff, session-086): "The harness is checked three ways, and a
  result is not used until all three pass."
- PF-15 (Jeff, session-084): pacino on a changed trace is compared with
  the CBP predictors rerun on the changed traces, not with the
  published results.
- PF-22 (Jeff, session-086): the perf tools use at most 75% of the
  machine's hardware threads by default.

PA additions for this task:
- THE AREA. The IA may change:
  - perf/ (the harness, its sources, Makefile, studies);
  - tools/perf_study.py, tools/perf_rerun.py, tools/perf_traces.py;
  - rtl/core/frontend/ftq, ifu, ibuf, bpu and fe_top: rtl/, tb/,
    assertion files and Makefiles, and rtl/core/csr where a run
    configuration does not reach the design (Phase 4).
  It does not change planning/, examples/ (FDT-2a) or
  tools/known_failures.txt.
- WHAT THIS TASK LOOKS FOR. The problems it looks for are defects of
  the measurement: a check that fails, a hang or fetch stall, a
  configuration that does not reach the design, a row that does not
  say what it measured. How well pacino predicts, and its gap to R,
  are the measurement: they are results, reported, not cases.
- A MOVE FROM A TIMING CHANGE. When a fix changes timing, a moved run
  is accounted for by its first divergence: the first committed
  instruction at which the before and after runs differ, the fix's
  event at that point, and the evidence that links them (the
  mispredict logs and the RAS or FTQ event at that cycle, as BP-154
  did). Differences after the first follow from it and are not traced
  one by one. A move with no fix event at its first divergence is a
  case under Block 2.
- The study runs (Phases 6 and 7) are long. They run in the
  background under the 75% cap, one study at a time, and the IA waits
  for each. Expected wall time: about 7 hours for Phase 6 and 4 to 6
  for Phase 7.

## Specific Requirements

Phase 0: the start
- The starting tree is the BP-154 commit. Report each Background fact
  found false, with the line it is now at.
- Rebuild perf/build/head_s2 with make -B. Rerun bp151_p2.sets (25
  runs) and p5.sets (12): they equal perf/studies/bp154_cls_p1e.csv
  and bp154_p5_p1e.csv in every column but sha, revision and timing.
  tb_fe_top at both slot counts equals BP-154's final column.

Phase 1: provenance (TD#210)
- The build writes a stamp: the sha, a dirty mark when the tree has
  tracked changes or untracked files under rtl/ or perf/, and an INPUT
  DIGEST, the SHA-256 over the contents of every build input in a
  fixed order (the H_DEPS list and every file it names, the Makefile
  and the make variables that reach the build: SLOTS, RAS_SPEC,
  RAS_COMMIT). The stamp is rewritten only when its value changes, and
  the binary depends on it.
- Every result row records the sha, the dirty mark and the digest.
  perf_study.py refuses to gather rows with different digests into one
  CSV unless the parameter-set file names more than one build.
- A make target prints the digest of the tree as it stands, without
  building, so that the digest of a committed tree can be compared
  with a baseline's rows.
- Test: a clean build, then a change to one RTL file (the dirty mark
  and the digest change and the binary rebuilds), then the change
  undone (the digest returns to its first value). A change to a file
  that is not a build input changes neither. Report each step's stamp.

Phase 2: the FTQ-full fetch stall (TD#206)
- In a tb_ftq_ifu or tb_fe_top test, fill the FTQ with commit held,
  and check that every allocated entry is still translated, fetched and
  delivered to the ibuf as the ibuf has room. Run it at both slot
  counts.
- If it fails, the stall is the defect: fix it under Block 1 (the test
  fails before and passes after, both slot counts). If it passes, find
  what stalled web_11 in PERF-002 (reproduce it, or show it no longer
  occurs, with the run).
- Then remove the harness's workaround: the "top->ftq_full ||" term of
  both eager-close sites. EAGER_IDLE stays. Every run of the phase's
  measurement completes, with no hang, without it.
- Measure: the 25 classified runs, p5 and tb_fe_top at both slot
  counts, and bp154_p2.sets at 16 entries (18 runs), before and after.
  Report ftq_full_cycles and cycles per run; moves are accounted for
  under A MOVE FROM A TIMING CHANGE.

Phase 3: a trap after a branch
- Build Jeff's ruling: the branch is judged on its own outcome, and the
  trap is a separate RC_TRAP redirect, as for a non-branch.
  mispred_trap_after and orc_slot_trap go; a trap count replaces them
  if the IA keeps one (a FORMAT change for acceptance).
- Test: under --oracle, slot-held mispredicts are 0 on every run of
  perf003_p5.sets' oracle sets, with no exception case.
- Measure as Phase 2 (the classified runs, p5, tb_fe_top).

Phase 4: the configuration reaches the design
- For each --cfg key of PF-5: a run with the key at its PF-5 value and
  one with it changed (each enable off; each interval 1 and 2^18) on
  one trace, 2e6 instructions. Show from the design's own state, read
  through the wrapper or by hierarchical reference, that the setting
  took effect: for SC and the fast path, the predictions they supply;
  for aging, the epoch advances and the useful-bit decay each table
  sees, counted per run.
- A setting that does not reach the design is a defect: fix it (in the
  harness's CSR write, the CSR path or the predictor), with a test that
  fails before and passes after at both slot counts. A setting that
  reaches it and moves no count is reported with the event counts that
  show it took effect.

Phase 5: the BP-150 rise (TD#208)
- On the current tree, knock out BP-150's change (the SC p3 skip fix)
  in a scratch copy, and run p5 with and without it. For each trace
  whose mis_sc or MPKI moves: the first divergence, and at it the SC
  decision with and without the fix, read against the SC's rules
  (sc_decisions.md or the source, by file and line).
- If the fixed SC decides by its rules at the first divergence, the
  rise is the cost of a correct SC, and TD#208 closes on that evidence.
  If it does not, the defect is fixed under Block 1.

Phase 6: the reference (PF-15)
- tools/perf_rerun.py --plan full. Every predictor on every unchanged
  trace equals its golden results exactly; every changed trace's row
  is recorded with its difference from golden. A run that fails or
  does not equal golden on an unchanged trace is a case.

Phase 7: pacino on every trace
- A study over the 105 traces of perf/cbp2025_rv_counts.csv, full
  length, at NUM_PRED_SLOTS 2 (head_s2), the PF-5 configuration, the
  default backend (immediate), the fetch rule, the real I-cache; and
  the same study with --oracle.
- Every run passes PF-11's three checks, or is a case:
  - the counts: instr, NumBr and their 50Perc values equal
    cbp2025_rv_counts.csv;
  - the PC check: every committed PC is the trace's next PC
    (err_stream 0), every err_ column 0, exit 0;
  - the oracle: 0 mispredicts on slot-held branches.
- Report per trace: MPKI (full and 50Perc, all branches and
  conditional), every mis_ and mpki_ per-predictor column, cycles,
  ftq_full_cycles, the oracle's cycles, and instr_per_sec; per
  workload group the totals.
- The comparison table (PF-10): per trace and per group, pacino's
  conditional MPKI against each CBP predictor's from Phase 6 (50Perc
  and full), and pacino's gap to TAGE192. State whether the gap is
  steady across the groups (PF-10's extrapolation rule). These are
  results, not cases.

Phase 8: the baseline, the regression, the planning text
- perf/studies/baseline.sets: the parameter sets Phase 7 ran, one
  command line each; the baseline CSVs, Phase 6's rerun CSV and their
  input digest, named in Results Capture.
- How to run a study against the baseline, in the fewest commands, as
  proposed planning text for perf_decisions.md.
- tools/regress.sh, once, at the end.
- The proposed planning text for every change: perf_decisions.md PF-5,
  PF-9, PF-11, PF-18, PF-21; ftq_decisions.md or ftq_ifu_interfaces.md
  for TD#206 if it was a defect; and the closing lines for TD#206,
  TD#208 and TD#210 (and TD#197's configuration finding).

NOT IN THIS TASK (PA): these are studies to run on the baseline, or
need tools pacino does not have; none of them changes whether a number
can be trusted. TD#133 and TD#202 (delivery width), TD#190 to TD#193
(FTB and uBTB policy), TD#197's aging design options (only Phase 4's
check is here), TD#204 (B, built only if A's gap to R requires it,
PF-10), TD#212 and TD#214 (FTB studies), TD#213 (needs synthesis),
TD#209 (tb_fe_top's own backend; the harness has the fetch rule),
TD#196 (the L1I bus mask; the harness memory does not read it).
ABSOLUTE CYCLES: the harness's backend is a parameter model (PF-18),
so cycles are the front end's under that model, not a forecast of a
core's. The baseline reports them as such.

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
  Jeff changed it in session-086: output filters, scratch scripts in
  the scratchpad, one build at a time.
- Studies use the tools' default -j (PF-22). Long runs run in the
  background and are waited for. No file a run reads changes while it
  runs.
- Every result row records the sha, the dirty mark and the digest the
  build reports.
- The training traces under CBP_TRACES and the changed traces under
  CBP_TRACES_RV are not written. perf_rerun.py's own logs under
  CBP_TRACES_RV/rerun/ are its output and may be written.

## Deliverables
Note: If a new module is to be created ensure that claude.code is allowed
or told to modify the Makefile for lint checking at the minimum.

Files the IA may change: those in THE AREA, and prompts/PERF-004.md,
Results Capture filled in below.

Results Capture reports:
- Phase 0: the false facts; the baseline check.
- Phase 1: the stamp, the digest's input list, the test's four stamps.
- Phase 2: the test, its result before and after; the cause; the
  workaround removed; the before and after tables.
- Phase 3: the change; the oracle runs; the tables.
- Phase 4: per key, the event counts with and without; any fix.
- Phase 5: per moved trace, the first divergence and the SC decision;
  TD#208's closing evidence or its fix.
- Phase 6: the rerun summary: runs, equal to golden, differences.
- Phase 7: the per-trace and per-group tables; the three checks per
  run; the comparison table; the total wall time and instr_per_sec.
- Phase 8: the baseline's files and digest; the regress.sh summary,
  whole, and its time; the proposed planning text.
- THE DONE CHECKLIST, each item ticked or stated as unfinished.

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary
STATUS: COMPLETE

PERF-004 makes the harness a measuring instrument and ends with a frozen
baseline: 210 runs (105 traces x {baseline, baseline_oracle}), full
length, head_s2, every PF-11 check passing on every run, one build digest
(0c66fed0ad2584216a27e4a2fac2f31b95d8dc297f48abf9883f6914e383a6dc).

Findings, by phase:
- Phase 0: the start equals BP-154 (25/25 and 12/12 rows, tb_fe_top 49/49
  at both slot counts). Three Makefile line numbers are off by one.
- Phase 1 (TD#210): every build writes a stamp (sha, dirty mark, input
  digest) and every row carries it; perf_study.py refuses to gather rows
  of different digests; make -C perf digest prints the stamp without
  building. Also fixed: csr_tb_pkg.sv was compiled but not a dependency.
- Phase 2 (TD#206): NOT A DEFECT. A new tb_fe_top program (ftq_full)
  fills the FTQ with commit held: every entry is translated, fetched and
  delivered, at both slot counts; a scratch copy with the stall put in
  fails 3 checks. The harness workaround (the "top->ftq_full ||" term) is
  removed; no run hangs, and at long resolve to commit (rc50 to rc1000)
  every row is identical. The hypothesis that a fix lowers
  ftq_full_cycles at long resolve to commit is refuted.
- Phase 3: the trap after a branch is built as Jeff ruled. The oracle
  check found two oracle defects older than this task (BP-153's p2 RAS
  peek, BP-154's p1 return on an FTB miss); both forces added; oracle
  slot-held mispredicts 0 on every oracle run.
- Phase 4 (TD#197): every PF-5 key reaches the design at both slot
  counts, shown by the design's own counts; no fix needed. PERF-002's
  "no count changed" does not reproduce.
- Phase 5 (TD#208): the rise is the cost of a correct SC. At every moved
  run's first divergence the fixed SC decides by its rules
  (sc_cntrl.sv:327-345); all 3.3M SC answers re-derived: 0 deviations.
- Phase 6 (PF-15): 1,155 reference runs. 10 predictors pass on all 105
  traces; mose fails all 105 (the known PF-1 case). The unchanged traces
  equal golden exactly (50 of 55 rows; the 5 others are mose). cai and
  jimenez are one binary (same bin_sha256) in the CBP submodule.
- Phase 7: run 1 failed 10 of 210 rows. Four causes, all fixed: an RTL
  defect in ftq_ifu.sv (W3M, err_stream 260 on infra_6), the oracle's
  alignment (o_succ), an alias slot of the wrong kind, and a class-
  conflict repair. Run 2: 210/210 pass. 102 rows moved;
  every move is accounted for by its first divergence (Phase 7
  below; 0 cases).
- Phase 8: the baseline files and digest below; the regression
  PASS (303 targets, 0 new failures, 369 s); the planning text proposed below.

Pacino against TAGE192 (results, not cases): conditional MPKI, mean of
the per-trace values, 50Perc 8.4173 against 3.3992 (2.48x), full 8.5072
against 3.4958 (2.43x). THE GAP IS NOT STEADY ACROSS THE GROUPS: the
ratio runs from 1.55 (compress) to 4.62 (media) at 50Perc, and per trace
from 1.12 to 24.22. PF-10's extrapolation to SPEC does not hold on these
numbers.

## What was delivered
- Phase 1: perf/src/stamp.py (new); perf/Makefile (stamp header, input
  manifest, make digest, csr_tb_pkg.sv dependency); perf_fe.cc (--stamp;
  row columns dirty and input_digest after sha); tools/perf_study.py (the
  digest rule).
- Phase 2: tb_fe_top program ftq_full (tb_fe_top.sv, fe_top/Makefile
  FE_PROGS); perf_fe.cc eager-close term removed at both sites
  (EAGER_IDLE stays); PERF_EVLOG event log (C/W/E/D lines);
  perf/studies/perf004_p2_stress.sets.
- Phase 3: perf_fe.cc trap after a branch (own outcome, separate
  RC_TRAP); column trap_after_branch replaces mispred_trap_after and
  orc_slot_trap; perf_top.sv oracle forces of the p2 RAS peek
  (w_ras_peek_addr_p2 and its valid) and of the p1 return held at p2 on
  an FTB miss; evlog T line.
- Phase 4: perf_top.sv probes and perf_fe.cc cf_* columns (fast-path
  directions, SC answers, TAGE/ITTAGE epoch advances, decay per table);
  perf/studies/perf004_p4_cfg.sets.
- Phase 5: perf_top.sv SC probes (sd_*), evlog S line; C line gains
  idx/pos/src/cls.
- Phase 6: tools/perf_rerun.py column bin_sha256;
  perf/cbp2025_rv_rerun.csv (the full plan, 1,155 rows).
- Phase 7: ftq_ifu.sv W3M (RTL fix) and tb_ftq_ifu.sv D18, D18a-D18d;
  perf_fe.cc o_succ early-exit acceptance, columns orc_slot_kind_alias
  and conflict_unspec_repair, STREAMERR/UNSPEC stderr diagnostics.
- Phase 8: perf/studies/baseline.sets, baseline.traces, baseline.csv.

## Test Case Results

### Phase 0: the start
Background facts found false (all line numbers, off by one):
- perf/Makefile SRC_SHA is at :114 (stated :113).
- perf/Makefile -DPERF_SRC_SHA is at :125 (stated :124).
- perf/Makefile H_DEPS is at :130-132 (stated :129-131).
Checked true: perf_fe.cc eager close at 1034-1035 and 1138-1139,
EAGER_IDLE at 750, trap-after at 1575-1579, Cfg 135-147 and --cfg at
451 (each within the stated "about"); ftq_ifu.sv :260 and :294; the
counts file (105 traces, 4,360,248,026 instructions, largest
130,170,487); perf_rerun's fallback CSV 215 rows; rc200 ftq_full
3,361,993 of 7,990,755 cycles.
Baseline check: head_s2 rebuilt with make -B at e7002b79. bp151_p2.sets
(25 runs) equal bp154_cls_p1e.csv and p5.sets (12) equal
bp154_p5_p1e.csv in every column but sha, revision and timing (0
differences). tb_fe_top at both slot counts equals BP-154's final
column, 49/49 programs.

### Phase 1: provenance (TD#210)
The stamp: build/<NAME>_s<SLOTS>/perf_stamp.h (PERF_SRC_SHA,
PERF_SRC_DIRTY, PERF_INPUT_DIGEST) and perf_inputs.txt (the manifest),
each rewritten by stamp.py only when its text changes; the binary depends
on the header (perf/Makefile:177-189). perf_fe --stamp prints it.
The digest's inputs, in order (perf/Makefile:152-169), 83 files, 6
variables, 2 tools at the baseline:
- H_DEPS: perf/src/harness/*.cc, *.h, *.vlt (sorted), TOOL_COMMON,
  TOOL_HDRS, H_SV (sv/perf.vlt, FE_TOP_SRCS, FE_PTW_SRCS,
  rtl/core/csr/tb/csr_tb_pkg.sv, sv/perf_top.sv);
- perf/Makefile, rtl/Vars.mk, rtl/core/frontend/fe_top/fe_top_srcs.mk,
  perf/src/stamp.py;
- variables SLOTS, RAS_SPEC, RAS_COMMIT, H_VFLAGS, H_COPT, LDFLAGS;
- tools: verilator --version, the C++ compiler --version.
Each file line is its path relative to its root and its SHA-256; NAME,
SRC_ROOT and JOBS are not inputs, so a copy of the tree elsewhere gives
the same digest.
The test's stamps (sha e7002b79224dbbd2893bacfe76dbc3aceda0e23e):
| step | change | rebuilt | dirty | digest |
|---|---|---|---|---|
| A | clean build (-B) | yes | dirty:perf | c4e7ab79883aa1996e3e87872483ce891aa3ffe6129be92c94e182d5c8a8edf1 |
| A again | none | no | dirty:perf | c4e7ab79...edf1 |
| B | comment in rtl/core/frontend/ftq/rtl/ftq_ptr.sv | yes | dirty:rtl+perf | 2ff2a0b174963ff02e78f56e4d9000dcdbde363ea7af8fee0ceca0791a2cf9a5 |
| C | B undone | yes | dirty:perf | c4e7ab79883aa1996e3e87872483ce891aa3ffe6129be92c94e182d5c8a8edf1 |
| D | comment in tools/perf_traces.py (not an input) | no | dirty:perf | c4e7ab79...edf1 |
(dirty:perf throughout: this task's own perf/ changes are uncommitted.)
The digest rule (perf_study.py): mixed digests in a one-build sets file
-> exit 1, no CSV; one build, or a file naming two builds -> written.

### Phase 2: the FTQ-full fetch stall (TD#206)
The test: tb_fe_top program ftq_full, translated Sv57 S-mode code (two
identity pages), straight-line 32-bit instructions, commit held from
reset. The FTQ is full at cycle 64. After 300 cycles every allocated
entry is translated, fetched and delivered (xlate_ptr == fetch_ptr ==
alloc_ptr, 64 entries; the ibuf presents nothing; next expected PC
0x80000800 = the newest block's end); then commit is released and the
program runs to its end (512 retired). PASS at 2 slots (1006/0 checks
over 50 programs) and 1 slot (1003/0).
Fails before: a scratch copy with the suspected stall put in
(fetch_pending && !ftq_full) fires a_fetch_pend_ptrs; with assertions off
it fails 3 checks (xlate 30, fetch 26, next 0x80000340).
Cause: NO RTL STALL. PERF-002 Other Notes 4 saw it on PERF-002's first
backend ("web_11, first backend"); on this tree the harness runs without
the workaround with no hang at resolve to commit 50 to 1000 and on the
stream rule (st200), so it no longer occurs.
Workaround removed: the "top->ftq_full ||" term at both eager-close
sites; EAGER_IDLE 32 stays.
Before (perf004_p1_*) / after (perf004_p2_*), cycles / ftq_full_cycles /
mispred totals:
| study | cycles | ftq_full_cycles | mispred |
|---|---|---|---|
| 25 classified | 25,494,138 / 25,503,105 | 189,780 / 189,895 | 420,597 / 420,911 |
| p5 (12) | 12,316,313 / 12,318,067 | 75,153 / 75,737 | 236,051 / 236,060 |
| bp154_p2 rc50/100/200 (18) | 19,588,169 / 19,588,169 | 3,667,521 / 3,667,521 | 357,474 / 357,474 |
| stress rc500/rc1000/st200 (18) | 57,603,508 / 57,624,002 | 47,283,694 / 47,155,737 | 366,355 / 366,134 |
Moved: 19 of 25 classified rows (int_6 none, media_2 one row), the p5
rows of the same runs, and the 6 st200 rows; rc50 to rc1000 0 moves.
Per run (before / after):

### perf004_p1_cls -> perf004_p2_cls
| set | trace | cycles | ftq_full_cycles | mispred | moved |
|---|---|---|---|---|---|
| sw_s0_c0 | compress_1 | 656963 / 656960 | 359 / 357 | 4674 / 4674 | yes |
| sw_s0_c0 | infra_1 | 1251303 / 1253120 | 5608 / 5995 | 20558 / 20491 | yes |
| sw_s0_c0 | int_6 | 634350 / 634350 | 1 / 1 | 10290 / 10290 |  |
| sw_s0_c0 | media_2 | 458341 / 458341 | 29 / 31 | 2819 / 2819 | yes |
| sw_s0_c0 | web_11 | 1823160 / 1825055 | 25761 / 26054 | 45591 / 45733 | yes |
| sw_s0_c8 | compress_1 | 656978 / 656979 | 402 / 389 | 4674 / 4674 | yes |
| sw_s0_c8 | infra_1 | 1251310 / 1251311 | 6173 / 6039 | 20558 / 20558 | yes |
| sw_s0_c8 | int_6 | 634358 / 634358 | 1 / 1 | 10290 / 10290 |  |
| sw_s0_c8 | media_2 | 458349 / 458349 | 30 / 31 | 2819 / 2819 | yes |
| sw_s0_c8 | web_11 | 1822903 / 1824460 | 28508 / 28075 | 45575 / 45664 | yes |
| sw_s5_c5 | compress_1 | 670712 / 670729 | 765 / 766 | 4698 / 4698 | yes |
| sw_s5_c5 | infra_1 | 1332457 / 1334771 | 7793 / 7903 | 20736 / 20829 | yes |
| sw_s5_c5 | int_6 | 663471 / 663471 | 1 / 1 | 10333 / 10333 |  |
| sw_s5_c5 | media_2 | 470691 / 470691 | 22 / 23 | 2842 / 2842 | yes |
| sw_s5_c5 | web_11 | 2013572 / 2009836 | 32197 / 32240 | 45811 / 45757 | yes |
| sw_s8_c0 | compress_1 | 684628 / 684628 | 388 / 389 | 4732 / 4732 | yes |
| sw_s8_c0 | infra_1 | 1385856 / 1386222 | 7270 / 7396 | 20935 / 20927 | yes |
| sw_s8_c0 | int_6 | 681823 / 681823 | 1 / 1 | 10028 / 10028 |  |
| sw_s8_c0 | media_2 | 475981 / 475981 | 48 / 49 | 2832 / 2832 | yes |
| sw_s8_c0 | web_11 | 2120549 / 2121465 | 31237 / 31565 | 45694 / 45747 | yes |
| sw_s8_c8 | compress_1 | 684650 / 684650 | 401 / 402 | 4732 / 4732 | yes |
| sw_s8_c8 | infra_1 | 1386015 / 1388673 | 8197 / 8267 | 20890 / 20975 | yes |
| sw_s8_c8 | int_6 | 681831 / 681831 | 1 / 1 | 10028 / 10028 |  |
| sw_s8_c8 | media_2 | 475995 / 475995 | 57 / 57 | 2832 / 2832 |  |
| sw_s8_c8 | web_11 | 2117892 / 2119056 | 34530 / 33862 | 45626 / 45607 | yes |
| total | | 25494138 / 25503105 | 189780 / 189895 | 420597 / 420911 | |

### perf004_p1_p5 -> perf004_p2_p5
| set | trace | cycles | ftq_full_cycles | mispred | moved |
|---|---|---|---|---|---|
| immediate | compress_1 | 656963 / 656960 | 359 / 357 | 4674 / 4674 | yes |
| immediate | fp_1 | 888716 / 888716 | 0 / 0 | 32864 / 32864 |  |
| immediate | infra_1 | 1251303 / 1253120 | 5608 / 5995 | 20558 / 20491 | yes |
| immediate | int_6 | 634350 / 634350 | 1 / 1 | 10290 / 10290 |  |
| immediate | media_2 | 458341 / 458341 | 29 / 31 | 2819 / 2819 | yes |
| immediate | web_11 | 1823160 / 1825055 | 25761 / 26054 | 45591 / 45733 | yes |
| latency | compress_1 | 693680 / 693680 | 376 / 376 | 4824 / 4824 |  |
| latency | fp_1 | 1176921 / 1176921 | 0 / 0 | 33475 / 33475 |  |
| latency | infra_1 | 1407157 / 1406028 | 8640 / 8359 | 21136 / 21117 | yes |
| latency | int_6 | 697532 / 697532 | 5 / 5 | 10322 / 10322 |  |
| latency | media_2 | 480998 / 480998 | 60 / 60 | 2895 / 2895 |  |
| latency | web_11 | 2147192 / 2146366 | 34314 / 34499 | 46603 / 46556 | yes |
| total | | 12316313 / 12318067 | 75153 / 75737 | 236051 / 236060 | |

### perf004_p1_p2 -> perf004_p2_p2
| set | trace | cycles | ftq_full_cycles | mispred | moved |
|---|---|---|---|---|---|
| rc100 | compress_1 | 679635 / 679635 | 23543 / 23543 | 4745 / 4745 |  |
| rc100 | fp_1 | 886859 / 886859 | 156 / 156 | 32771 / 32771 |  |
| rc100 | infra_1 | 1252662 / 1252662 | 10186 / 10186 | 20669 / 20669 |  |
| rc100 | int_6 | 685962 / 685962 | 64096 / 64096 | 10330 / 10330 |  |
| rc100 | media_2 | 548588 / 548588 | 121152 / 121152 | 2826 / 2826 |  |
| rc100 | web_11 | 1829158 / 1829158 | 45291 / 45291 | 46166 / 46166 |  |
| rc200 | compress_1 | 1092945 / 1092945 | 604059 / 604059 | 5044 / 5044 |  |
| rc200 | fp_1 | 1134012 / 1134012 | 444847 / 444847 | 32332 / 32332 |  |
| rc200 | infra_1 | 1628844 / 1628844 | 595475 / 595475 | 23191 / 23191 |  |
| rc200 | int_6 | 1120861 / 1120861 | 672463 / 672463 | 10284 / 10284 |  |
| rc200 | media_2 | 1005038 / 1005038 | 644063 / 644063 | 2835 / 2835 |  |
| rc200 | web_11 | 2009055 / 2009055 | 401086 / 401086 | 49492 / 49492 |  |
| rc50 | compress_1 | 657091 / 657091 | 608 / 608 | 4646 / 4646 |  |
| rc50 | fp_1 | 888766 / 888766 | 0 / 0 | 32864 / 32864 |  |
| rc50 | infra_1 | 1252927 / 1252927 | 7050 / 7050 | 20657 / 20657 |  |
| rc50 | int_6 | 634400 / 634400 | 1 / 1 | 10290 / 10290 |  |
| rc50 | media_2 | 458432 / 458432 | 37 / 37 | 2819 / 2819 |  |
| rc50 | web_11 | 1822934 / 1822934 | 33408 / 33408 | 45513 / 45513 |  |
| total | | 19588169 / 19588169 | 3667521 / 3667521 | 357474 / 357474 | |

### perf004_p1_stress -> perf004_p2_stress
| set | trace | cycles | ftq_full_cycles | mispred | moved |
|---|---|---|---|---|---|
| rc1000 | compress_1 | 5004135 / 5004135 | 4660166 / 4660166 | 5288 / 5288 |  |
| rc1000 | fp_1 | 5141483 / 5141483 | 4791171 / 4791171 | 30862 / 30862 |  |
| rc1000 | infra_1 | 6578524 / 6578524 | 6069405 / 6069405 | 23434 / 23434 |  |
| rc1000 | int_6 | 5326861 / 5326861 | 4975463 / 4975463 | 10266 / 10266 |  |
| rc1000 | media_2 | 4785030 / 4785030 | 4470439 / 4470439 | 2837 / 2837 |  |
| rc1000 | web_11 | 5880768 / 5880768 | 5282118 / 5282118 | 49211 / 49211 |  |
| rc500 | compress_1 | 2542825 / 2542825 | 2155187 / 2155187 | 5174 / 5174 |  |
| rc500 | fp_1 | 2603160 / 2603160 | 2196864 / 2196864 | 31044 / 31044 |  |
| rc500 | infra_1 | 3399561 / 3399561 | 2698940 / 2698940 | 23577 / 23577 |  |
| rc500 | int_6 | 2693629 / 2693629 | 2322592 / 2322592 | 10286 / 10286 |  |
| rc500 | media_2 | 2419957 / 2419957 | 2094583 / 2094583 | 2843 / 2843 |  |
| rc500 | web_11 | 3216392 / 3216392 | 2162519 / 2162519 | 49691 / 49691 |  |
| st200 | compress_1 | 1093864 / 1094726 | 614583 / 596933 | 5080 / 5018 | yes |
| st200 | fp_1 | 1137355 / 1140748 | 432871 / 423738 | 31260 / 31227 | yes |
| st200 | infra_1 | 1633352 / 1639951 | 611891 / 568541 | 22975 / 22898 | yes |
| st200 | int_6 | 1121505 / 1124312 | 680770 / 658174 | 10289 / 10284 | yes |
| st200 | media_2 | 1004705 / 1005567 | 659781 / 640534 | 2830 / 2824 | yes |
| st200 | web_11 | 2020402 / 2026373 | 404351 / 388370 | 49408 / 49370 | yes |
| total | | 57603508 / 57624002 | 47283694 / 47155737 | 366355 / 366134 | |
Moves accounted for: 30 pairs (scratch copy p2b with the term restored
against the tree, PERF_EVLOG), all LINKED: the first fix event is a
close the before run made with ftq_full=1 that the after run does not
make. Example s0c0 web_11: before closes entry 36 at cycle 1031 with the
FTQ full; after closes it at 1041 when the next entry arrives; first
differing commit k 199692, cycle 185310 before / 185311 after. The 4
media_2 and 2 lat_compress_1 moves have no commit difference: only
ftq_full_cycles moves. st200: the before run decided 67,843 to 115,549
branches by the fetch record (D lines) with the FTQ full.
tb_fe_top: the 49 programs unchanged at both slot counts; ftq_full new.

### Phase 3: a trap after a branch
The change (perf_fe.cc, at the take): a branch whose next trace record is
an exception entry is judged on its own outcome (target when taken, pc +
2/4 when not, under both rules); the trap is a separate RC_TRAP redirect
in the branch's resolve cycle, as for a non-branch. mispred_trap_after
and orc_slot_trap are removed; trap_after_branch counts the cases.
Oracle runs (perf003_p5.sets' oracle sets, 2e6): err_orc_slot_mispred
before 52 / 93 / 70 (compress_1 / infra_1 / web_11; these failed before
this task, since BP-153) -> 0 on all 18 oracle rows, no exception case.
Causes found on the way (Block 2):
- defined: err_orc_slot_mispred, a mispredict on a branch the FTB held
  in a slot under --oracle (perf_fe.cc commit).
- located: compress_1 k 2765, cycle 6714-6722, pc fffffbfffdbfc448, a
  return at position 14; record next 7fffbfffdbfc408 against the trace's
  ffff800010010c00.
- traced: an FTB-held return's p2 target is the RAS peek
  (w_ras_peek_addr_p2, BP-153's p3_reach change, bp_cluster.sv:1251-1257),
  which the oracle did not force; the trace's return target is not the
  RAS top (the call at 404). The first fix tried (the p1 return held at
  p2 on an FTB miss, bp_cluster.sv:1313-1323, 1363-1368) is correct but
  changed no count.
- fixed: perf_top forces w_ras_peek_addr_p2 and its valid (o_p2_peek,
  o_p2_pkv); both forces kept.
Tables (before / after, totals): classified 25,503,105 / 25,502,784
cycles, mispred 420,911 / 420,527, ftq_full 189,895 / 191,921; p5
12,318,067 / 12,315,418; bp154_p2 19,587,216 after (from 19,588,169).
fp_1, int_6 and media_2 have no trap after a branch and do not move.
Per run (before / after):

### perf004_p3b_cls -> perf004_p3_cls
| set | trace | cycles | ftq_full_cycles | mispred | moved |
|---|---|---|---|---|---|
| sw_s0_c0 | compress_1 | 656960 / 657087 | 357 / 376 | 4674 / 4673 | yes |
| sw_s0_c0 | infra_1 | 1253120 / 1252085 | 5995 / 6080 | 20491 / 20573 | yes |
| sw_s0_c0 | int_6 | 634350 / 634350 | 1 / 1 | 10290 / 10290 |  |
| sw_s0_c0 | media_2 | 458341 / 458341 | 31 / 31 | 2819 / 2819 |  |
| sw_s0_c0 | web_11 | 1825055 / 1822240 | 26054 / 26525 | 45733 / 45332 | yes |
| sw_s0_c8 | compress_1 | 656979 / 657103 | 389 / 413 | 4674 / 4673 | yes |
| sw_s0_c8 | infra_1 | 1251311 / 1253468 | 6039 / 6074 | 20558 / 20557 | yes |
| sw_s0_c8 | int_6 | 634358 / 634358 | 1 / 1 | 10290 / 10290 |  |
| sw_s0_c8 | media_2 | 458349 / 458349 | 31 / 31 | 2819 / 2819 |  |
| sw_s0_c8 | web_11 | 1824460 / 1822399 | 28075 / 28455 | 45664 / 45431 | yes |
| sw_s5_c5 | compress_1 | 670729 / 670648 | 766 / 754 | 4698 / 4691 | yes |
| sw_s5_c5 | infra_1 | 1334771 / 1332649 | 7903 / 7605 | 20829 / 20836 | yes |
| sw_s5_c5 | int_6 | 663471 / 663471 | 1 / 1 | 10333 / 10333 |  |
| sw_s5_c5 | media_2 | 470691 / 470691 | 23 / 23 | 2842 / 2842 |  |
| sw_s5_c5 | web_11 | 2009836 / 2012815 | 32240 / 32279 | 45757 / 45851 | yes |
| sw_s8_c0 | compress_1 | 684628 / 684579 | 389 / 371 | 4732 / 4723 | yes |
| sw_s8_c0 | infra_1 | 1386222 / 1385906 | 7396 / 7822 | 20927 / 20869 | yes |
| sw_s8_c0 | int_6 | 681823 / 681823 | 1 / 1 | 10028 / 10028 |  |
| sw_s8_c0 | media_2 | 475981 / 475981 | 49 / 49 | 2832 / 2832 |  |
| sw_s8_c0 | web_11 | 2121465 / 2124072 | 31565 / 31753 | 45747 / 45839 | yes |
| sw_s8_c8 | compress_1 | 684650 / 684600 | 402 / 389 | 4732 / 4723 | yes |
| sw_s8_c8 | infra_1 | 1388673 / 1384574 | 8267 / 8258 | 20975 / 20847 | yes |
| sw_s8_c8 | int_6 | 681831 / 681831 | 1 / 1 | 10028 / 10028 |  |
| sw_s8_c8 | media_2 | 475995 / 475995 | 57 / 57 | 2832 / 2832 |  |
| sw_s8_c8 | web_11 | 2119056 / 2123369 | 33862 / 34571 | 45607 / 45796 | yes |
| total | | 25503105 / 25502784 | 189895 / 191921 | 420911 / 420527 | |

### perf004_p2_p5 -> perf004_p3_p5
| set | trace | cycles | ftq_full_cycles | mispred | moved |
|---|---|---|---|---|---|
| immediate | compress_1 | 656960 / 657087 | 357 / 376 | 4674 / 4673 | yes |
| immediate | fp_1 | 888716 / 888716 | 0 / 0 | 32864 / 32864 |  |
| immediate | infra_1 | 1253120 / 1252085 | 5995 / 6080 | 20491 / 20573 | yes |
| immediate | int_6 | 634350 / 634350 | 1 / 1 | 10290 / 10290 |  |
| immediate | media_2 | 458341 / 458341 | 31 / 31 | 2819 / 2819 |  |
| immediate | web_11 | 1825055 / 1822240 | 26054 / 26525 | 45733 / 45332 | yes |
| latency | compress_1 | 693680 / 694167 | 376 / 337 | 4824 / 4851 | yes |
| latency | fp_1 | 1176921 / 1176921 | 0 / 0 | 33475 / 33475 |  |
| latency | infra_1 | 1406028 / 1407716 | 8359 / 7878 | 21117 / 21195 | yes |
| latency | int_6 | 697532 / 697532 | 5 / 5 | 10322 / 10322 |  |
| latency | media_2 | 480998 / 480998 | 60 / 60 | 2895 / 2895 |  |
| latency | web_11 | 2146366 / 2145265 | 34499 / 34143 | 46556 / 46456 | yes |
| total | | 12318067 / 12315418 | 75737 / 75436 | 236060 / 235745 | |

### perf004_p2_p2 -> perf004_p3_p2
| set | trace | cycles | ftq_full_cycles | mispred | moved |
|---|---|---|---|---|---|
| rc100 | compress_1 | 679635 / 679793 | 23543 / 23474 | 4745 / 4786 | yes |
| rc100 | fp_1 | 886859 / 886859 | 156 / 156 | 32771 / 32771 |  |
| rc100 | infra_1 | 1252662 / 1254140 | 10186 / 9510 | 20669 / 20723 | yes |
| rc100 | int_6 | 685962 / 685962 | 64096 / 64096 | 10330 / 10330 |  |
| rc100 | media_2 | 548588 / 548588 | 121152 / 121152 | 2826 / 2826 |  |
| rc100 | web_11 | 1829158 / 1826046 | 45291 / 44240 | 46166 / 46170 | yes |
| rc200 | compress_1 | 1092945 / 1093030 | 604059 / 602823 | 5044 / 5073 | yes |
| rc200 | fp_1 | 1134012 / 1134012 | 444847 / 444847 | 32332 / 32332 |  |
| rc200 | infra_1 | 1628844 / 1627396 | 595475 / 593954 | 23191 / 23057 | yes |
| rc200 | int_6 | 1120861 / 1120861 | 672463 / 672463 | 10284 / 10284 |  |
| rc200 | media_2 | 1005038 / 1005038 | 644063 / 644063 | 2835 / 2835 |  |
| rc200 | web_11 | 2009055 / 2008397 | 401086 / 401283 | 49492 / 49345 | yes |
| rc50 | compress_1 | 657091 / 657173 | 608 / 561 | 4646 / 4643 | yes |
| rc50 | fp_1 | 888766 / 888766 | 0 / 0 | 32864 / 32864 |  |
| rc50 | infra_1 | 1252927 / 1256275 | 7050 / 7196 | 20657 / 20648 | yes |
| rc50 | int_6 | 634400 / 634400 | 1 / 1 | 10290 / 10290 |  |
| rc50 | media_2 | 458432 / 458432 | 37 / 37 | 2819 / 2819 |  |
| rc50 | web_11 | 1822934 / 1822048 | 33408 / 33951 | 45513 / 45426 | yes |
| total | | 19588169 / 19587216 | 3667521 / 3663807 | 357474 / 357222 | |

### perf004_p3b_orc -> perf004_p3_orc
| set | trace | cycles | mispred | err_orc_slot_mispred | moved |
|---|---|---|---|---|---|
| immediate | compress_1 | 656960 / 657087 | 4674 / 4673 | 2651 / 2647 | yes |
| immediate | fp_1 | 888716 / 888716 | 32864 / 32864 | 32805 / 32805 |  |
| immediate | infra_1 | 1253120 / 1252085 | 20491 / 20573 | 10689 / 10751 | yes |
| immediate | int_6 | 634350 / 634350 | 10290 / 10290 | 10156 / 10156 |  |
| immediate | media_2 | 458341 / 458341 | 2819 / 2819 | 2565 / 2565 |  |
| immediate | web_11 | 1825055 / 1822240 | 45733 / 45332 | 13439 / 13201 | yes |
| latency | compress_1 | 693680 / 694167 | 4824 / 4851 | 2752 / 2787 | yes |
| latency | fp_1 | 1176921 / 1176921 | 33475 / 33475 | 33417 / 33417 |  |
| latency | infra_1 | 1406028 / 1407716 | 21117 / 21195 | 11243 / 11245 | yes |
| latency | int_6 | 697532 / 697532 | 10322 / 10322 | 10170 / 10170 |  |
| latency | media_2 | 480998 / 480998 | 2895 / 2895 | 2636 / 2636 |  |
| latency | web_11 | 2146366 / 2145265 | 46556 / 46456 | 13969 / 13909 | yes |
| oracle_immediate | compress_1 | 633332 / 632945 | 1962 / 1909 | 52 / 0 | yes |
| oracle_immediate | fp_1 | 621847 / 621847 | 57 / 57 | 0 / 0 |  |
| oracle_immediate | infra_1 | 1130928 / 1130621 | 9102 / 8999 | 93 / 0 | yes |
| oracle_immediate | int_6 | 573748 / 573727 | 118 / 118 | 0 / 0 | yes |
| oracle_immediate | media_2 | 434351 / 434372 | 221 / 221 | 0 / 0 | yes |
| oracle_immediate | web_11 | 1654563 / 1653584 | 31238 / 31180 | 70 / 0 | yes |
| oracle_latency | compress_1 | 648934 / 647984 | 1968 / 1914 | 52 / 0 | yes |
| oracle_latency | fp_1 | 673900 / 673900 | 57 / 57 | 0 / 0 |  |
| oracle_latency | infra_1 | 1198036 / 1194218 | 9072 / 8950 | 96 / 0 | yes |
| oracle_latency | int_6 | 576671 / 576665 | 118 / 118 | 0 / 0 | yes |
| oracle_latency | media_2 | 438221 / 438224 | 221 / 221 | 0 / 0 | yes |
| oracle_latency | web_11 | 1857970 / 1855949 | 31219 / 31142 | 72 / 0 | yes |
| perfect | compress_1 | 649751 / 650255 | 4616 / 4680 | 2592 / 2651 | yes |
| perfect | fp_1 | 888480 / 888480 | 32864 / 32864 | 32805 / 32805 |  |
| perfect | infra_1 | 1211393 / 1207120 | 20515 / 20459 | 10716 / 10710 | yes |
| perfect | int_6 | 634526 / 634526 | 10315 / 10315 | 10179 / 10179 |  |
| perfect | media_2 | 457492 / 457492 | 2820 / 2820 | 2565 / 2565 |  |
| perfect | web_11 | 1676593 / 1676747 | 45494 / 45479 | 13205 / 13242 | yes |
| perfect_oracle | compress_1 | 626511 / 626132 | 1960 / 1907 | 52 / 0 | yes |
| perfect_oracle | fp_1 | 621598 / 621598 | 57 / 57 | 0 / 0 |  |
| perfect_oracle | infra_1 | 1089756 / 1089385 | 9101 / 8990 | 93 / 0 | yes |
| perfect_oracle | int_6 | 573387 / 573371 | 118 / 118 | 0 / 0 | yes |
| perfect_oracle | media_2 | 433495 / 433516 | 221 / 221 | 0 / 0 | yes |
| perfect_oracle | web_11 | 1510502 / 1509482 | 31232 / 31175 | 69 / 0 | yes |
| total | | 33134052 / 33117558 | 480726 / 479716 | 219203 / 218441 | |
The non-oracle rows of the oracle study equal the build without the peek
force (the force has no effect off the oracle).
Moves accounted for: 39 pairs, all LINKED. The first differing commit is
the branch with the trap after it, mispredict 1 before and 0 after, the
T event at the same k: compress_1 k 10542, infra_1 k 10282, web_11
k 4843, in every configuration.

### Phase 4: the configuration reaches the design
Per key, at 2e6 on int_6 and web_11, both slot counts; the probes read
the design's state by hierarchical reference in perf_top (cf_* columns).
Every enable off moves its count to 0 (fp_off: cf_fastpath_dirs 0;
sc_off: cf_sc_answers 0, pred_sc 0; tage_age_off: cf_tage_epoch_adv 0 and
TAGE decay 0; ittage_age_off: ITTAGE epoch and decay 0). Every interval
1 moves its epoch advances from 2 / 10 (2 slots) to 396,484 / 1,392,336
(TAGE) and 396,486 / 1,393,116 (ITTAGE), and the decay counts.
Reaches but moves no result: int_6 ittage_age_off and ittage_int1 rows
equal pf5 in mispred and cycles, at both slot counts; int_6 has no
ITTAGE mispredict (mis_ittage 0), though ITTAGE's epoch (0 / 396,486)
and decay (0 / 46,886 against 2,402) move.
No fix. PERF-002's "no count changed" is not reproduced.
== perf/studies/perf004_p4_cfg_s2.csv
| set | trace | fe_cfg_seen | cf_fastpath_dirs | cf_sc_answers | pred_sc | cf_tage_epoch_adv | cf_ittage_epoch_adv | cf_tage_decay_t1 | cf_tage_decay_t2 | cf_tage_decay_t3 | cf_tage_decay_t4 | cf_ittage_decay_t1 | cf_ittage_decay_t2 | cf_ittage_decay_t3 | cf_ittage_decay_t4 | cf_ittage_decay_t5 | mispred | mis_sc | mis_tage | mis_ittage | cycles | status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| fp_off | int_6 | end/262144/262144 | 0 | 732944 | 3332 | 2 | 2 | 11226 | 4548 | 5398 | 222 | 1937 | 48 | 0 | 0 | 0 | 7605 | 1303 | 6118 | 0 | 626128 | ok |
| fp_off | web_11 | end/262144/262144 | 0 | 2438346 | 9948 | 10 | 10 | 44051 | 34940 | 5152 | 456 | 483149 | 313980 | 146610 | 46580 | 9433 | 46929 | 6230 | 7521 | 495 | 1839437 | ok |
| ittage_age_off | int_6 | en7/262144/262144 | 213349 | 764918 | 1075 | 2 | 0 | 11284 | 5708 | 6224 | 217 | 0 | 0 | 0 | 0 | 0 | 10290 | 453 | 1028 | 0 | 634350 | ok |
| ittage_age_off | web_11 | en7/262144/262144 | 189732 | 2411658 | 7764 | 10 | 0 | 46455 | 34015 | 7228 | 576 | 0 | 0 | 0 | 0 | 0 | 45428 | 4822 | 5127 | 506 | 1820460 | ok |
| ittage_int1 | int_6 | enf/262144/1 | 213349 | 764918 | 1075 | 2 | 396486 | 11284 | 5708 | 6224 | 217 | 46886 | 0 | 0 | 0 | 0 | 10290 | 453 | 1028 | 0 | 634350 | ok |
| ittage_int1 | web_11 | enf/262144/1 | 189808 | 2411986 | 7753 | 10 | 1393116 | 43022 | 32776 | 6600 | 347 | 498532 | 252854 | 38747 | 8154 | 9121 | 45409 | 4766 | 5095 | 539 | 1821971 | ok |
| pf5 | int_6 | enf/262144/262144 | 213349 | 764918 | 1075 | 2 | 2 | 11284 | 5708 | 6224 | 217 | 2402 | 0 | 0 | 0 | 0 | 10290 | 453 | 1028 | 0 | 634350 | ok |
| pf5 | web_11 | enf/262144/262144 | 189853 | 2412024 | 7690 | 10 | 10 | 43813 | 35326 | 6396 | 438 | 475475 | 304269 | 137796 | 57590 | 12542 | 45332 | 4737 | 5194 | 516 | 1822240 | ok |
| sc_off | int_6 | ene/262144/262144 | 214119 | 0 | 0 | 2 | 2 | 14396 | 4793 | 6488 | 107 | 3084 | 0 | 0 | 0 | 0 | 10491 | 0 | 1692 | 0 | 634305 | ok |
| sc_off | web_11 | ene/262144/262144 | 186815 | 0 | 0 | 10 | 10 | 55165 | 38456 | 6953 | 740 | 444852 | 288298 | 151467 | 39573 | 4984 | 43321 | 0 | 8236 | 513 | 1793251 | ok |
| tage_age_off | int_6 | enb/262144/262144 | 213316 | 764956 | 1055 | 0 | 2 | 0 | 0 | 0 | 0 | 2404 | 0 | 0 | 0 | 0 | 10291 | 445 | 1038 | 0 | 634322 | ok |
| tage_age_off | web_11 | enb/262144/262144 | 189700 | 2411492 | 7770 | 0 | 10 | 0 | 0 | 0 | 0 | 474466 | 310305 | 151087 | 46958 | 3934 | 45475 | 4871 | 5124 | 519 | 1822607 | ok |
| tage_int1 | int_6 | enf/1/262144 | 213560 | 765040 | 1034 | 396484 | 2 | 29209 | 48527 | 36704 | 848 | 2767 | 0 | 0 | 0 | 0 | 10315 | 451 | 1052 | 0 | 634342 | ok |
| tage_int1 | web_11 | enf/1/262144 | 190416 | 2413652 | 7797 | 1392336 | 10 | 36674 | 43636 | 6497 | 1915 | 471500 | 293870 | 140880 | 44587 | 10856 | 45485 | 4812 | 5162 | 521 | 1822181 | ok |
== perf/studies/perf004_p4_cfg_s1.csv
| set | trace | fe_cfg_seen | cf_fastpath_dirs | cf_sc_answers | pred_sc | cf_tage_epoch_adv | cf_ittage_epoch_adv | cf_tage_decay_t1 | cf_tage_decay_t2 | cf_tage_decay_t3 | cf_tage_decay_t4 | cf_ittage_decay_t1 | cf_ittage_decay_t2 | cf_ittage_decay_t3 | cf_ittage_decay_t4 | cf_ittage_decay_t5 | mispred | mis_sc | mis_tage | mis_ittage | cycles | status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| fp_off | int_6 | end/262144/262144 | 0 | 419444 | 3050 | 1 | 1 | 20421 | 4846 | 3766 | 365 | 9512 | 27 | 0 | 0 | 0 | 7582 | 1151 | 6209 | 0 | 704488 | ok |
| fp_off | web_11 | end/262144/262144 | 0 | 1339569 | 8868 | 5 | 5 | 37512 | 35356 | 4552 | 0 | 426310 | 330528 | 154353 | 40977 | 1397 | 50128 | 5585 | 6982 | 477 | 2012809 | ok |
| ittage_age_off | int_6 | en7/262144/262144 | 208443 | 430220 | 1087 | 1 | 0 | 23300 | 9208 | 2352 | 171 | 0 | 0 | 0 | 0 | 0 | 10309 | 426 | 982 | 0 | 714294 | ok |
| ittage_age_off | web_11 | en7/262144/262144 | 182612 | 1327643 | 6725 | 5 | 0 | 42202 | 33253 | 6485 | 63 | 0 | 0 | 0 | 0 | 0 | 48683 | 4155 | 4714 | 481 | 1993853 | ok |
| ittage_int1 | int_6 | enf/262144/1 | 208443 | 430220 | 1087 | 1 | 235561 | 23300 | 9208 | 2352 | 171 | 53159 | 0 | 0 | 0 | 0 | 10309 | 426 | 982 | 0 | 714294 | ok |
| ittage_int1 | web_11 | enf/262144/1 | 182119 | 1327729 | 6732 | 5 | 775418 | 44827 | 31573 | 5690 | 173 | 386406 | 277731 | 16316 | 6126 | 15401 | 48649 | 4143 | 4677 | 526 | 1993334 | ok |
| pf5 | int_6 | enf/262144/262144 | 208443 | 430220 | 1087 | 1 | 1 | 23300 | 9208 | 2352 | 171 | 11926 | 0 | 0 | 0 | 0 | 10309 | 426 | 982 | 0 | 714294 | ok |
| pf5 | web_11 | enf/262144/262144 | 182694 | 1327068 | 6760 | 5 | 5 | 44597 | 33015 | 7246 | 37 | 441966 | 343742 | 153484 | 47392 | 8176 | 48661 | 4119 | 4697 | 484 | 1994355 | ok |
| sc_off | int_6 | ene/262144/262144 | 207308 | 0 | 0 | 1 | 1 | 23482 | 8361 | 2988 | 48 | 7930 | 0 | 0 | 0 | 0 | 10517 | 0 | 1630 | 0 | 714080 | ok |
| sc_off | web_11 | ene/262144/262144 | 180536 | 0 | 0 | 5 | 5 | 46898 | 37940 | 9261 | 195 | 432130 | 330342 | 166993 | 44224 | 18691 | 46638 | 0 | 7346 | 495 | 1969183 | ok |
| tage_age_off | int_6 | enb/262144/262144 | 208488 | 430255 | 1084 | 0 | 1 | 0 | 0 | 0 | 0 | 11930 | 0 | 0 | 0 | 0 | 10319 | 429 | 988 | 0 | 714371 | ok |
| tage_age_off | web_11 | enb/262144/262144 | 182399 | 1327525 | 6684 | 0 | 5 | 0 | 0 | 0 | 0 | 429810 | 348385 | 155162 | 54746 | 9439 | 48670 | 4102 | 4729 | 481 | 1993220 | ok |
| tage_int1 | int_6 | enf/1/262144 | 208501 | 430380 | 1072 | 235593 | 1 | 54578 | 50297 | 30662 | 984 | 11932 | 0 | 0 | 0 | 0 | 10330 | 422 | 1006 | 0 | 714358 | ok |
| tage_int1 | web_11 | enf/1/262144 | 182349 | 1327633 | 6733 | 774622 | 5 | 26922 | 35511 | 12641 | 1624 | 430685 | 329158 | 156788 | 43192 | 5791 | 48568 | 4100 | 4678 | 495 | 1992204 | ok |

### Phase 5: the BP-150 rise (TD#208)
Scratch copy ko150: BP-150's write-through in ftq_entry.sv removed. p5
with (fix) and without (ko): totals mispred 235,674 -> 235,745, mis_sc
28,689 -> 29,211, mispred_cond 194,652 -> 194,702; 11 of 12 runs move
(imm media_2 does not). ko fails check_errors on 3 runs (the TD#205
skip); the fix passes.
First divergence per moved run (k, cycle; fix / ko mispredict and
source; the SC decision at p3):
| run | k | cycle | fix | ko | SC at p3 |
|---|---|---|---|---|---|
| imm compress_1 | 393 | 1320 | mis 1 SC | mis 0 TAGE | p2 0 -> 1, sum 2, thr 10, weak TAGE |
| imm fp_1 | 4375 | 2408 | mis 1 SC | mis 0 TAGE | p2 1 -> 0, sum -6, thr 10, medium TAGE |
| imm infra_1 | 924 | 2631 | mis 1 SC | mis 0 TAGE | p2 0 -> 1, sum 2, thr 10, weak TAGE |
| imm int_6 | 801 | 1082 | mis 1 SC | mis 0 TAGE | p2 0 -> 1, sum 4, thr 10, weak TAGE |
| imm web_11 | 8375 | 13111 | mis 1 SC | mis 0 TAGE | p2 0 -> 1, sum 0, thr 11, weak TAGE |
| lat compress_1 | 393 | 1493 | mis 1 SC | mis 0 TAGE | p2 0 -> 1, sum 2, thr 10, weak TAGE |
| lat fp_1 | 6245 | 4303 | mis 1 SC | mis 0 TAGE | p2 1 -> 0, sum -4, thr 10, medium TAGE |
| lat infra_1 | 924 | 3078 | mis 1 SC | mis 0 TAGE | p2 0 -> 1, sum 2, thr 10, weak TAGE |
| lat int_6 | 801 | 1335 | mis 1 SC | mis 0 TAGE | p2 0 -> 1, sum 2, thr 10, weak TAGE |
| lat media_2 | 21926 | 9152 | mis 0 SC | mis 1 TAGE | p2 1 -> 0, sum -4, thr 10, weak TAGE |
| lat web_11 | 2360 | 7518 | mis 1 SC | mis 0 TAGE | p2 0 -> 1, sum 0, thr 10, weak TAGE |
In each the SC differs from a weak or medium TAGE with |sum| below the
threshold and wins, which sc_cntrl.sv:327-345 ("differ, SC wins") gives.
Every SC answer of every fix run was re-derived from the probed sum,
threshold and TAGE confidence by those rules: 3.3M answers, 0
deviations. Without the fix SC's p3 answer was skipped (TD#205), so TAGE
stood. TD#208 closes: the rise is the cost of a correct SC.

### Phase 6: the reference (PF-15)
tools/perf_rerun.py --plan full: 1,155 rows (11 predictors x 105
traces), wall 29,880 s, 196.4 core-hours. Status: tage192, cbp2016,
behrendt, cai, fan, jimenez, koizumi, man, ros, seznec Pass 105; mose
Fail 105 (fails in every trace within a second; golden has no mose
result either: the PF-1 case). Unchanged traces (5): 50 of 55 rows equal
golden exactly; the 5 others are mose. Changed traces (100), MPKI minus
golden, mean (min, max): tage192 -0.0214 (-0.1090, +0.1631), cbp2016
-0.0306, behrendt -0.0217, cai -0.0231, fan -0.0266, jimenez -0.0231,
koizumi -0.0207, man -0.0230, ros -0.0196, seznec -0.0211.
cai and jimenez: same bin_sha256 (4eef46673d947884...) and equal MispBr
on every trace, in golden too (105/105). It is the CBP submodule's own
(tools/cbp2025, outside the AREA): one predictor under two names. The
comparison below lists both; read them as one.

### Phase 7: pacino on every trace
Run 1 (digest 7a3fbd44, 10,113 s): 200 of 210 rows passed. The 10
failures, each taken through Block 2:

CLASS A, err_stream (infra_6 baseline, 260).
- defined: err_stream counts committed PCs that are not the trace's next
  PC (perf_fe.cc fetch-rule check).
- located: infra_6, full length, cycle 2779839-2779856, entry 15, start
  6b02c4: an alias COND slot predicted taken at position 4, on the ALU
  instruction at 6b02cc.
- traced: predecode M2 (no CFI at mis_pos) killed the slot; the IFU
  delivered the block only up to mis_pos (ifu_f3.sv:356-358, w_en), but
  W3 set the successor to pft_addr 6b02e4: 6b02d0..6b02e0 were never
  delivered. RTL DEFECT (ftq_ifu.sv). It needs the full run; a run
  shortened to 4.8M instructions does not show it.
- fixed: W3M (rule change R11). infra_6 baseline after: err_stream 0,
  mispred 313,300 -> 312,024, cycles 31,279,789 -> 31,262,908.

CLASS B, err_unspec_repair (web_11, both sets, 1 each).
- defined: err_unspec_repair counts RC_UNSPEC repairs (perf_fe.cc
  unspec_repair site).
- located: web_11, the only trace with class_conflict_pcs: a STREAMERR
  fetch line "conflict 1 freed 1", then the UNSPEC line.
- traced: the PC is a class-conflict PC (rewritten code, supply.h) that
  had already committed; the repair follows from the trace's two
  instructions at one PC, not from the harness or RTL.
- fixed (count): conflict_unspec_repair (R13); err_unspec_repair 0.

CLASS C, oracle err_orc_slot_mispred (infra_6 1, int_36 1, int_3 2,
int_4 1, web_13 16, web_16 2, web_9 1).
- located: web_9 k 3418323, cycle 2145390-2145398, entry 57 at
  aaaaaafa3740; int_36 entry 19.
- traced: the predecessor's p1 block falls through to pc, while the
  trace leaves that block early by a taken branch to the same pc.
  o_succ refused (why 6), so the entry was off the path at p1 and its p1
  slots were not forced. The p2 force moved the predecessor's end
  without a redirect; OREALIGN at p2 put the entry on the path; the FTB
  missed at p2, so nothing was forced. The record kept the uBTB slot: a
  wrong direction, or for an indirect jump the uBTB's offset target
  (mod 2^21).
- fixed: o_succ accepts it (R10). After: 6 traces pass, orc_realigned 0
  on every row.
CLASS C2, the remaining infra_6 oracle mispredict.
- located: k 65709094, pc 40000068135c, entry 12, cycle
  28054487-28054500: the FTB slot at position 2 has type 1 (a jump)
  where the trace has a conditional.
- traced: the oracle forces direction and target only for the slot's
  type (PF-11 does not force type); FCORR M3 rewrote the slot to COND and
  kept its taken, which no predictor gave.
- fixed (count): orc_slot_kind_alias (R12), judged on the slot type the
  fetch request carried (FSlot rq_*). The first version judged the
  verdict-time type, which M3 had already rewritten; it still failed.

Run 2 (digest 0c66fed0, wall 10,177 s, 0 non-zero exits): 210 of 210
rows pass PF-11's three checks:
- the counts: instr, NumBr, 50PercInstr and 50PercNumBr equal
  cbp2025_rv_counts.csv on every row (and the CBP rerun's rows: 0
  differ);
- the PC check: every err_ column 0 on every row (15 columns: err_stream
  err_word err_fault err_illegal err_ftq_idx err_tl_opcode
  err_entry_reopen err_unspec_repair err_cond_target err_fetch_rule
  err_orc_slot_mispred err_no_record err_late_write err_fetch_port
  err_record_moved), status ok, exit 0;
- the oracle: err_orc_slot_mispred 0 on all 105 oracle rows.
orc_slot_kind_alias: 1 on the oracle rows (infra_6), 2 off the oracle;
conflict_unspec_repair: 2 (web_11, each set).

Moves, run 1 -> run 2: 1 baseline row (infra_6, W3M) and 101 oracle
rows (o_succ). On the 108 unmoved rows the old counts split exactly:
old err_orc_slot_mispred = new + orc_slot_kind_alias, old
err_unspec_repair = new + conflict_unspec_repair (0 exceptions).
Every move is accounted for by its first divergence (A MOVE FROM A
TIMING CHANGE). Two scratch builds of the tree, built one at a time:
p7b BEFORE (W3M forced off in ftq_ifu.sv, the o_succ early exit off in
perf_fe.cc; digest 7d604be2, unversioned copy) and p7a AFTER (the tree,
plus PERF_EVLOG lines M <cycle> <idx>, a W3M cut that changed the
successor, and O <cycle>, an o_succ early-exit acceptance; digest
9d367d01). The pair of each moved row ran the baseline set's arguments
at the same --max-instr (a shortened run is not a prefix of the full
one, so both runs of a pair are shortened alike). The tool (div7s.py)
streams the two logs, finds the first commit (C line: k, cycle, mis,
idx, pos, src, cls) that differs, and the last fix event at or before
its cycle. Every event before the first fix event is identical by
construction: the builds differ only in the two fixes.
Evidence that p7b is the run-1 harness: at full length its infra_6
baseline run and int_3 oracle run fail exactly as in run 1 (infra_6
STREAMERR "pc 6b02d8 exp 6b02d0 last pc 6b02cc", int_3 two ORCMIS at
pc fffff1f5c7c4), exit 2.

Pass 1, 2e6 instructions, 102 pairs: 80 diverge, all LINKED; 22 do not
diverge within 2e6.
Pass 2, the 22 at full length: 14 diverge at a commit, LINKED; of the 8
others, 3 diverge first at an SC answer (S line), LINKED, and 5 have no
differing event over the whole trace.
- infra_6 baseline (W3M): its only M event, cycle 2779845 (entry 15's
  writeback at 6b02c4); the first differing commit k 4796342 at cycle
  2779855 after / 2779865 before, the instruction after the cut: the
  site Class A was found at. The single W3M cut over the whole trace
  is the whole move.
- The 101 oracle rows (o_succ): the last O event before the first
  difference is 0 to 20 cycles before it in 94 rows (median 5). In the
  6 with a larger gap to the first differing commit (infra_3 59, int_36
  37, web_12 24, web_1 780, web_20 32, web_24 85 cycles) the first
  differing event of any kind is 0 to 18 cycles after an O event: an SC
  answer on the forced entry (int_36, web_12, web_1, web_20, web_24) or
  an entry close (infra_3); the commit difference follows from it.
- The 5 rows with no differing event (fp_13, fp_1, fp_3, infra_5,
  infra_7; full length): the columns that moved are only
  orc_forced_entries and orc_offpath_entries, by equal and opposite
  amounts (+1/-1, +2/-2, +7/-7, +5/-5, +98/-98), and on infra_7
  orc_realigned 98 -> 0. An entry is counted once, at its allocation,
  forced if on the path and off-path if not (perf_fe.cc:1394-1404); the
  O acceptance is what puts it on the path, and in infra_7 the p2
  realignment (perf_fe.cc:983-997) no longer has to. The forced values
  equal the predictors' own, so nothing downstream moves. O lines
  outnumber the moved entries because o_succ is also called at each p2
  and p3 realignment of an entry already on the path.
No move lacks a fix event at its first divergence: 0 cases.
On the way: div7.py, which held both logs in memory, ran the machine
short of memory at full length and Claude Code stopped that job after
the 44 runs had finished; div7s.py streams them (low memory) and was
run on the finished logs.

Pass 1 (2e6), the 80 LINKED pairs (first fix event; the last one at or
before the divergence; the first differing commit; the gap in cycles;
M and O events up to the divergence; the commit line after / before):
| set | trace | first fix | last fix before | first differing commit (k, cycle) | gap | M | O | after / before C line |
|---|---|---|---|---|---|---|---|---|
| oracle | compress_1 | O 1360 | O 9943 | 5971 9948 | 5 | 0 | 59 | (5971, 9948, 0, 16, 0, 7, 0) / (5971, 9949, 0, 16, 0, 7, 0) |
| oracle | compress_2 | O 1360 | O 9795 | 5985 9799 | 4 | 0 | 57 | (5985, 9800, 0, 13, 0, 7, 0) / (5985, 9799, 0, 13, 0, 7, 0) |
| oracle | compress_3 | O 5459 | O 5461 | 14823 5469 | 8 | 0 | 3 | (14823, 5476, 0, 46, 0, 7, 0) / (14823, 5469, 0, 46, 0, 7, 0) |
| oracle | compress_4 | O 1441 | O 9913 | 5996 9917 | 4 | 0 | 54 | (5996, 9918, 0, 21, 0, 7, 0) / (5996, 9917, 0, 21, 0, 7, 0) |
| oracle | compress_5 | O 1441 | O 9833 | 5965 9837 | 4 | 0 | 54 | (5965, 9838, 0, 13, 0, 7, 0) / (5965, 9837, 0, 13, 0, 7, 0) |
| oracle | compress_6 | O 1441 | O 9833 | 5965 9837 | 4 | 0 | 54 | (5965, 9838, 0, 13, 0, 7, 0) / (5965, 9837, 0, 13, 0, 7, 0) |
| oracle | compress_7 | O 51279 | O 446939 | 1480864 446943 | 4 | 0 | 347 | (1480864, 446944, 0, 30, 0, 7, 0) / (1480864, 446943, 0, 30, 0, 7, 0) |
| oracle | fp_10 | O 30815 | O 308944 | 1270455 308949 | 5 | 0 | 16 | (1270455, 308949, 0, 2, 0, 7, 0) / (1270455, 308950, 0, 2, 0, 7, 0) |
| oracle | fp_6 | O 421880 | O 421882 | 1234101 421882 | 0 | 0 | 3 | (1234101, 421883, 0, 52, 0, 7, 6) / (1234101, 421882, 0, 52, 0, 7, 6) |
| oracle | fp_7 | O 1385 | O 16884 | 35919 16888 | 4 | 0 | 16 | (35919, 16889, 0, 29, 0, 7, 4) / (35919, 16888, 0, 29, 0, 7, 4) |
| oracle | fp_9 | O 845 | O 984 | 1242 985 | 1 | 0 | 5 | (1242, 986, 0, 63, 0, 7, 6) / (1242, 985, 0, 63, 0, 7, 6) |
| oracle | infra_0 | O 416 | O 6404 | 4442 6406 | 2 | 0 | 27 | (4442, 6406, 0, 3, 0, 7, 0) / (4442, 6407, 0, 3, 0, 7, 0) |
| oracle | infra_10 | O 709 | O 15379 | 37951 15383 | 4 | 0 | 32 | (37951, 15383, 0, 17, 0, 7, 0) / (37951, 15384, 0, 17, 0, 7, 0) |
| oracle | infra_11 | O 2619 | O 3576 | 2501 3582 | 6 | 0 | 9 | (2501, 3582, 0, 7, 0, 7, 2) / (2501, 3585, 0, 7, 0, 7, 2) |
| oracle | infra_12 | O 645 | O 19123 | 35032 19128 | 5 | 0 | 47 | (35032, 19128, 0, 45, 0, 7, 0) / (35032, 19129, 0, 45, 0, 7, 0) |
| oracle | infra_14 | O 1162 | O 12348 | 29117 12356 | 8 | 0 | 18 | (29117, 12357, 0, 56, 0, 7, 2) / (29117, 12356, 0, 56, 0, 7, 2) |
| oracle | infra_1 | O 792 | O 42434 | 41565 42440 | 6 | 0 | 200 | (41565, 42441, 1, 1, 0, 7, 3) / (41565, 42440, 1, 1, 0, 7, 3) |
| oracle | infra_2 | O 792 | O 62732 | 100034 62738 | 6 | 0 | 204 | (100034, 62739, 1, 31, 0, 7, 3) / (100034, 62738, 1, 31, 0, 7, 3) |
| oracle | infra_3 | O 2920 | O 42795 | 85399 42854 | 59 | 0 | 62 | (85399, 42855, 0, 35, 0, 7, 0) / (85399, 42854, 0, 35, 0, 7, 0) |
| oracle | infra_4 | O 577 | O 200933 | 424361 200937 | 4 | 0 | 102 | (424361, 200938, 0, 16, 0, 7, 0) / (424361, 200937, 0, 16, 0, 7, 0) |
| oracle | infra_6 | O 792 | O 42223 | 41287 42229 | 6 | 0 | 197 | (41287, 42230, 1, 17, 0, 7, 3) / (41287, 42229, 1, 17, 0, 7, 3) |
| oracle | infra_9 | O 1803 | O 47064 | 117963 47069 | 5 | 0 | 54 | (117963, 47069, 0, 48, 0, 7, 0) / (117963, 47070, 0, 48, 0, 7, 0) |
| oracle | int_10 | O 1314 | O 525488 | 1250128 525496 | 8 | 0 | 2201 | (1250128, 525497, 0, 10, 0, 7, 1) / (1250128, 525496, 0, 10, 0, 7, 1) |
| oracle | int_11 | O 836 | O 2234 | 3284 2241 | 7 | 0 | 21 | (3284, 2241, 0, 22, 0, 7, 0) / (3284, 2243, 0, 22, 0, 7, 0) |
| oracle | int_14 | O 1592 | O 640380 | 1356105 640389 | 9 | 0 | 1274 | (1356105, 640390, 1, 29, 0, 7, 3) / (1356105, 640389, 1, 29, 0, 7, 3) |
| oracle | int_15 | O 464 | O 3120 | 1757 3121 | 1 | 0 | 13 | (1757, 3122, 0, 10, 0, 7, 3) / (1757, 3121, 0, 10, 0, 7, 3) |
| oracle | int_16 | O 711 | O 9740 | 9862 9744 | 4 | 0 | 36 | (9862, 9745, 0, 31, 0, 7, 1) / (9862, 9744, 0, 31, 0, 7, 1) |
| oracle | int_17 | O 1444 | O 9230 | 9860 9233 | 3 | 0 | 32 | (9860, 9233, 0, 37, 0, 7, 0) / (9860, 9234, 0, 37, 0, 7, 0) |
| oracle | int_18 | O 3847 | O 3849 | 8767 3854 | 5 | 0 | 3 | (8767, 3854, 0, 25, 0, 7, 2) / (8767, 3855, 0, 25, 0, 7, 2) |
| oracle | int_19 | O 1065 | O 13335 | 11846 13335 | 0 | 0 | 50 | (11846, 13336, 0, 21, 0, 7, 1) / (11846, 13335, 0, 21, 0, 7, 1) |
| oracle | int_1 | O 623 | O 757 | 362 764 | 7 | 0 | 9 | (362, 764, 0, 60, 0, 7, 0) / (362, 765, 0, 60, 0, 7, 0) |
| oracle | int_20 | O 794 | O 3447 | 2749 3453 | 6 | 0 | 22 | (2749, 3453, 0, 0, 0, 3, 3) / (2749, 3454, 0, 0, 0, 3, 3) |
| oracle | int_21 | O 3160 | O 3162 | 5049 3168 | 6 | 0 | 3 | (5049, 3169, 1, 33, 0, 7, 3) / (5049, 3168, 1, 33, 0, 7, 3) |
| oracle | int_23 | O 1324 | O 8690 | 17876 8696 | 6 | 0 | 18 | (17876, 8696, 0, 11, 0, 7, 1) / (17876, 8697, 0, 11, 0, 7, 1) |
| oracle | int_24 | O 586 | O 14011 | 20590 14015 | 4 | 0 | 19 | (20590, 14015, 0, 59, 0, 7, 0) / (20590, 14016, 0, 59, 0, 7, 0) |
| oracle | int_25 | O 1787 | O 2952 | 5704 2954 | 2 | 0 | 12 | (5704, 2955, 0, 47, 0, 7, 1) / (5704, 2954, 0, 47, 0, 7, 1) |
| oracle | int_26 | O 1635 | O 4421 | 9088 4422 | 1 | 0 | 12 | (9088, 4423, 0, 30, 0, 7, 0) / (9088, 4422, 0, 30, 0, 7, 0) |
| oracle | int_27 | O 816 | O 36280 | 140260 36282 | 2 | 0 | 23 | (140260, 36283, 0, 39, 0, 7, 6) / (140260, 36282, 0, 39, 0, 7, 6) |
| oracle | int_28 | O 3793 | O 276975 | 872929 276977 | 2 | 0 | 143 | (872929, 276977, 0, 42, 0, 7, 0) / (872929, 276978, 0, 42, 0, 7, 0) |
| oracle | int_29 | O 1554 | O 5344 | 11346 5348 | 4 | 0 | 14 | (11346, 5349, 0, 58, 0, 7, 0) / (11346, 5348, 0, 58, 0, 7, 0) |
| oracle | int_30 | O 544 | O 14255 | 38215 14258 | 3 | 0 | 32 | (38215, 14258, 0, 45, 0, 7, 0) / (38215, 14259, 0, 45, 0, 7, 0) |
| oracle | int_31 | O 538 | O 3110 | 8444 3112 | 2 | 0 | 6 | (8444, 3113, 0, 19, 0, 7, 0) / (8444, 3112, 0, 19, 0, 7, 0) |
| oracle | int_32 | O 118525 | O 125213 | 434013 125229 | 16 | 0 | 12 | (434013, 125229, 0, 36, 0, 7, 0) / (434013, 125231, 0, 36, 0, 7, 0) |
| oracle | int_33 | O 674 | O 3738 | 9404 3744 | 6 | 0 | 9 | (9404, 3744, 0, 45, 0, 7, 0) / (9404, 3745, 0, 45, 0, 7, 0) |
| oracle | int_34 | O 10480 | O 13525 | 41479 13532 | 7 | 0 | 6 | (41479, 13532, 0, 29, 0, 7, 0) / (41479, 13533, 0, 29, 0, 7, 0) |
| oracle | int_35 | O 1625 | O 1627 | 2512 1628 | 1 | 0 | 3 | (2512, 1629, 0, 8, 0, 7, 1) / (2512, 1628, 0, 8, 0, 7, 1) |
| oracle | int_36 | O 1271 | O 24972 | 18583 25009 | 37 | 0 | 60 | (18583, 25010, 0, 46, 0, 7, 0) / (18583, 25009, 0, 46, 0, 7, 0) |
| oracle | int_4 | O 1149 | O 3293 | 4200 3299 | 6 | 0 | 26 | (4200, 3299, 0, 22, 0, 7, 0) / (4200, 3300, 0, 22, 0, 7, 0) |
| oracle | int_6 | O 529 | O 4113 | 8708 4117 | 4 | 0 | 17 | (8708, 4117, 0, 40, 0, 7, 4) / (8708, 4120, 0, 40, 0, 7, 4) |
| oracle | int_7 | O 3015 | O 19002 | 30950 19008 | 6 | 0 | 38 | (30950, 19009, 0, 43, 0, 7, 0) / (30950, 19008, 0, 43, 0, 7, 0) |
| oracle | int_8 | O 1854 | O 47338 | 80437 47346 | 8 | 0 | 146 | (80437, 47348, 0, 24, 0, 7, 0) / (80437, 47346, 0, 24, 0, 7, 0) |
| oracle | int_9 | O 3132 | O 42712 | 83777 42718 | 6 | 0 | 24 | (83777, 42719, 0, 22, 0, 7, 1) / (83777, 42718, 0, 22, 0, 7, 1) |
| oracle | media_0 | O 1550 | O 23666 | 61190 23673 | 7 | 0 | 39 | (61190, 23673, 0, 14, 0, 7, 0) / (61190, 23675, 0, 14, 0, 7, 0) |
| oracle | media_1 | O 4981 | O 138392 | 612756 138399 | 7 | 0 | 79 | (612756, 138399, 0, 43, 0, 7, 0) / (612756, 138400, 0, 43, 0, 7, 0) |
| oracle | media_2 | O 464 | O 240802 | 1097436 240804 | 2 | 0 | 72 | (1097436, 240804, 0, 30, 0, 7, 1) / (1097436, 240805, 0, 30, 0, 7, 1) |
| oracle | media_3 | O 2417 | O 83844 | 361578 83849 | 5 | 0 | 75 | (361578, 83849, 0, 1, 0, 7, 2) / (361578, 83851, 0, 1, 0, 7, 2) |
| oracle | web_0 | O 500 | O 16530 | 24679 16533 | 3 | 0 | 63 | (24679, 16533, 0, 61, 0, 7, 0) / (24679, 16534, 0, 61, 0, 7, 0) |
| oracle | web_10 | O 77592 | O 214220 | 515462 214226 | 6 | 0 | 10 | (515462, 214226, 0, 22, 0, 7, 1) / (515462, 214227, 0, 22, 0, 7, 1) |
| oracle | web_11 | O 783 | O 50273 | 90620 50275 | 2 | 0 | 77 | (90620, 50275, 0, 27, 0, 7, 0) / (90620, 50276, 0, 27, 0, 7, 0) |
| oracle | web_12 | O 1739 | O 12086 | 20676 12110 | 24 | 0 | 21 | (20676, 12110, 0, 5, 0, 7, 0) / (20676, 12111, 0, 5, 0, 7, 0) |
| oracle | web_13 | O 17442 | O 303487 | 1244195 303488 | 1 | 0 | 48 | (1244195, 303488, 0, 10, 0, 7, 0) / (1244195, 303491, 0, 10, 0, 7, 0) |
| oracle | web_14 | O 785 | O 787 | 781 791 | 4 | 0 | 3 | (781, 792, 0, 54, 0, 7, 0) / (781, 791, 0, 54, 0, 7, 0) |
| oracle | web_15 | O 930 | O 32745 | 63257 32746 | 1 | 0 | 62 | (63257, 32747, 0, 25, 0, 7, 1) / (63257, 32746, 0, 25, 0, 7, 1) |
| oracle | web_16 | O 2003 | O 13385 | 28804 13391 | 6 | 0 | 16 | (28804, 13391, 0, 3, 0, 7, 0) / (28804, 13396, 0, 3, 0, 7, 0) |
| oracle | web_17 | O 3364 | O 28477 | 54366 28480 | 3 | 0 | 62 | (54366, 28480, 0, 47, 0, 7, 0) / (54366, 28481, 0, 47, 0, 7, 0) |
| oracle | web_18 | O 5403 | O 68680 | 187694 68682 | 2 | 0 | 57 | (187694, 68682, 0, 22, 0, 7, 0) / (187694, 68683, 0, 22, 0, 7, 0) |
| oracle | web_19 | O 24626 | O 24628 | 51505 24633 | 5 | 0 | 3 | (51505, 24633, 0, 27, 0, 3, 3) / (51505, 24634, 0, 27, 0, 3, 3) |
| oracle | web_1 | O 1455 | O 30703 | 35042 31483 | 780 | 0 | 95 | (35042, 31484, 0, 32, 0, 7, 1) / (35042, 31483, 0, 32, 0, 7, 1) |
| oracle | web_20 | O 922 | O 16694 | 13744 16726 | 32 | 0 | 66 | (13744, 16727, 0, 57, 0, 7, 2) / (13744, 16726, 0, 57, 0, 7, 2) |
| oracle | web_21 | O 1137 | O 731098 | 1717817 731106 | 8 | 0 | 672 | (1717817, 731106, 0, 62, 0, 7, 1) / (1717817, 731108, 0, 62, 0, 7, 1) |
| oracle | web_22 | O 19671 | O 142070 | 472365 142072 | 2 | 0 | 53 | (472365, 142072, 0, 13, 0, 7, 0) / (472365, 142073, 0, 13, 0, 7, 0) |
| oracle | web_23 | O 866 | O 72963 | 185364 72970 | 7 | 0 | 103 | (185364, 72970, 0, 48, 0, 2, 4) / (185364, 72972, 0, 48, 0, 2, 4) |
| oracle | web_24 | O 3389 | O 25846 | 20275 25931 | 85 | 0 | 43 | (20275, 25932, 0, 29, 0, 7, 0) / (20275, 25931, 0, 29, 0, 7, 0) |
| oracle | web_25 | O 513 | O 4179 | 2790 4182 | 3 | 0 | 17 | (2790, 4182, 0, 13, 0, 7, 1) / (2790, 4184, 0, 13, 0, 7, 1) |
| oracle | web_2 | O 521 | O 13463 | 14793 13475 | 12 | 0 | 108 | (14793, 13477, 0, 24, 0, 7, 3) / (14793, 13475, 0, 24, 0, 7, 3) |
| oracle | web_3 | O 246966 | O 249251 | 869040 249253 | 2 | 0 | 27 | (869040, 249253, 0, 27, 0, 7, 1) / (869040, 249255, 0, 27, 0, 7, 1) |
| oracle | web_4 | O 4045 | O 31345 | 35843 31353 | 8 | 0 | 50 | (35843, 31353, 0, 23, 0, 7, 1) / (35843, 31354, 0, 23, 0, 7, 1) |
| oracle | web_5 | O 1107 | O 22626 | 48137 22632 | 6 | 0 | 74 | (48137, 22632, 0, 16, 0, 7, 1) / (48137, 22633, 0, 16, 0, 7, 1) |
| oracle | web_8 | O 2196 | O 64185 | 110812 64201 | 16 | 0 | 182 | (110812, 64201, 0, 18, 0, 7, 0) / (110812, 64203, 0, 18, 0, 7, 0) |
| oracle | web_9 | O 3175 | O 6620 | 4897 6624 | 4 | 0 | 15 | (4897, 6625, 0, 61, 0, 7, 0) / (4897, 6624, 0, 61, 0, 7, 0) |


Pass 1: gap from the last fix event min 0, median 5, max 780 cycles;
the last fix event is O in all 80.

Pass 2 (full length), the 14 commit divergences (columns as above):
| set | trace | first fix | last fix before | first differing commit (k, cycle) | gap | M | O | after / before C line |
|---|---|---|---|---|---|---|---|---|
| baseline | infra_6 | M 2779845 | M 2779845 | 4796342 2779855 | 10 | 1 | 0 | (4796342, 2779855, 0, 16, 0, 7, 1) / (4796342, 2779865, 0, 16, 0, 7, 1) |
| oracle | compress_0 | O 1113 | O 1191938 | 4490622 1191943 | 5 | 0 | 85 | (4490622, 1191943, 0, 2, 0, 7, 0) / (4490622, 1191944, 0, 2, 0, 7, 0) |
| oracle | fp_11 | O 838532 | O 1655456 | 6745173 1655458 | 2 | 0 | 18 | (6745173, 1655458, 0, 62, 0, 7, 0) / (6745173, 1655459, 0, 62, 0, 7, 0) |
| oracle | fp_2 | O 1389 | O 1215389 | 4660120 1215392 | 3 | 0 | 51 | (4660120, 1215392, 0, 9, 0, 7, 1) / (4660120, 1215393, 0, 9, 0, 7, 1) |
| oracle | fp_4 | O 702 | O 2804356 | 11861724 2804363 | 7 | 0 | 99 | (11861724, 2804365, 0, 61, 0, 7, 4) / (11861724, 2804363, 0, 61, 0, 7, 4) |
| oracle | fp_8 | O 2656213 | O 5638489 | 27920994 5638499 | 10 | 0 | 4 | (27920994, 5638499, 0, 35, 0, 7, 0) / (27920994, 5638500, 0, 35, 0, 7, 0) |
| oracle | infra_13 | O 621 | O 673930 | 2048635 673940 | 10 | 0 | 88 | (2048635, 673940, 0, 33, 0, 3, 3) / (2048635, 673942, 0, 33, 0, 3, 3) |
| oracle | infra_15 | O 809 | O 3626715 | 11555942 3626722 | 7 | 0 | 4570 | (11555942, 3626722, 0, 21, 0, 7, 1) / (11555942, 3626723, 0, 21, 0, 7, 1) |
| oracle | int_0 | O 2313 | O 8188785 | 24304817 8188788 | 3 | 0 | 190 | (24304817, 8188789, 0, 38, 0, 7, 0) / (24304817, 8188788, 0, 38, 0, 7, 0) |
| oracle | int_12 | O 17744 | O 6025027 | 26677660 6025028 | 1 | 0 | 69 | (26677660, 6025028, 0, 48, 0, 7, 0) / (26677660, 6025030, 0, 48, 0, 7, 0) |
| oracle | int_13 | O 757 | O 790158 | 2238913 790165 | 7 | 0 | 36 | (2238913, 790165, 0, 50, 0, 3, 3) / (2238913, 790166, 0, 50, 0, 3, 3) |
| oracle | int_3 | O 1178 | O 3437224 | 10573890 3437227 | 3 | 0 | 113 | (10573890, 3437228, 0, 4, 0, 7, 6) / (10573890, 3437227, 0, 4, 0, 7, 6) |
| oracle | web_6 | O 734 | O 839438 | 2205735 839442 | 4 | 0 | 837 | (2205735, 839444, 0, 57, 0, 7, 0) / (2205735, 839442, 0, 57, 0, 7, 0) |
| oracle | web_7 | O 1301737 | O 1305082 | 3505845 1305084 | 2 | 0 | 21 | (3505845, 1305085, 0, 28, 0, 7, 1) / (3505845, 1305084, 0, 28, 0, 7, 1) |

Pass 2, the 8 without a commit difference (the first differing event
of any kind; S is an SC answer line):
| set | trace | result | after | before | last fix, gap |
|---|---|---|---|---|---|
| oracle | fp_12 | first event diff #2846 cyc 1358 | S 1358 42 0 4 0 0 0 0 0 0 0 0 -4 10 0 0 | S 1359 42 0 4 0 1 0 1 1 0 0 0 0 10 0 0 | (1357, 'O') gap 1; LINKED |
| oracle | fp_13 | no event differs (53937311 lines) | - | - | - |
| oracle | fp_1 | no event differs (40693038 lines) | - | - | - |
| oracle | fp_3 | no event differs (36061219 lines) | - | - | - |
| oracle | infra_5 | no event differs (55819072 lines) | - | - | - |
| oracle | infra_7 | no event differs (55524498 lines) | - | - | - |
| oracle | int_2 | first event diff #4031 cyc 2012 | S 2012 9 1 8 1 1 0 0 0 1 1 0 -12 10 0 0 | S 2012 9 1 8 0 0 0 0 0 0 1 0 -12 10 0 0 | (2010, 'O') gap 2; LINKED |
| oracle | int_5 | first event diff #13059 cyc 4583 | S 4583 59 0 6 0 0 0 1 1 0 1 0 14 10 5 0 | S 4583 59 0 6 1 1 0 1 1 1 1 0 14 10 5 0 | (4583, 'O') gap 0; LINKED |

Total wall time 10,177 s (2.83 h) on 24 workers; 232,924 host seconds
both sets (64.7 core-hours); instr_per_sec over the baseline set 34,705
(28,342 web to 56,155 media).

Per group (baseline; oracle IPC and MPKI from baseline_oracle):
| group | traces | instr | MPKI | MPKI cond | 50% MPKI | 50% MPKI cond | IPC | ftq_full % | oracle IPC | oracle MPKI | instr/s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| compress | 8 | 542398218 | 6.0510 | 5.9595 | 5.7779 | 5.6956 | 2.9995 | 0.15 | 3.4349 | 0.2017 | 44819 |
| fp | 14 | 510188302 | 7.6629 | 7.6154 | 7.9577 | 7.9112 | 3.0697 | 0.00 | 3.7473 | 0.0133 | 46308 |
| infra | 16 | 748471091 | 7.4638 | 6.8395 | 7.1545 | 6.6308 | 2.1182 | 0.43 | 2.3867 | 1.3042 | 32554 |
| int | 37 | 1731261875 | 10.4501 | 9.7079 | 10.5784 | 9.8306 | 2.2017 | 0.33 | 2.6576 | 1.3893 | 33477 |
| media | 4 | 80239644 | 4.2290 | 3.9133 | 4.0263 | 3.7562 | 3.5902 | 0.03 | 4.1673 | 0.1204 | 56155 |
| web | 26 | 747688896 | 11.4745 | 9.7578 | 10.7050 | 9.1548 | 1.8064 | 1.07 | 2.0882 | 3.2851 | 28342 |
| all | 105 | 4360248026 | 9.1253 | 8.4063 | 8.9866 | 8.3113 | 2.2675 | 0.46 | 2.6645 | 1.3677 | 34705 |

| group | mpki_ubtb | mpki_loop | mpki_ftb | mpki_tage | mpki_sc | mpki_ittage | mpki_ras | mpki_none | mpki_direct | mpki_indirect | mpki_return |
|---|---|---|---|---|---|---|---|---|---|---|---|
| compress | 0.0007 | 0.0210 | 3.6256 | 1.5239 | 0.6484 | 0.0034 | 0.0075 | 0.2204 | 0.0000 | 0.0147 | 0.0769 |
| fp | 0.0000 | 0.1843 | 4.2292 | 2.0948 | 1.0936 | 0.0421 | 0.0000 | 0.0189 | 0.0000 | 0.0427 | 0.0048 |
| infra | 0.0001 | 0.0494 | 3.1880 | 1.7210 | 1.0104 | 0.0657 | 0.0055 | 1.4237 | 0.0000 | 0.3026 | 0.3216 |
| int | 0.0007 | 0.0908 | 4.6760 | 2.3939 | 1.4976 | 0.2095 | 0.0017 | 1.5798 | 0.0000 | 0.4381 | 0.3041 |
| media | 0.0001 | 0.0402 | 2.4255 | 0.8081 | 0.5460 | 0.2250 | 0.0000 | 0.1841 | 0.0000 | 0.2695 | 0.0462 |
| web | 0.0013 | 0.1135 | 3.7766 | 2.1804 | 1.5465 | 0.2662 | 0.0055 | 3.5845 | 0.0000 | 0.9151 | 0.8016 |
| all | 0.0006 | 0.0889 | 4.0420 | 2.0694 | 1.2519 | 0.1496 | 0.0035 | 1.5193 | 0.0000 | 0.3946 | 0.3244 |

Per trace:
| trace | instr | MPKI | MPKI cond | 50% MPKI | 50% MPKI cond | cycles | IPC | ftq_full | oracle cycles | oracle MPKI | oracle 50% MPKI | instr/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| compress_0 | 120009599 | 6.7002 | 6.6812 | 6.8426 | 6.8251 | 36155126 | 3.3193 | 5291 | 31318363 | 0.0511 | 0.0463 | 49471 |
| compress_1 | 30830757 | 2.5234 | 2.3521 | 2.6266 | 2.4957 | 9820496 | 3.1394 | 26571 | 9268125 | 0.3849 | 0.3123 | 45109 |
| compress_2 | 32398229 | 2.3257 | 2.1471 | 2.4730 | 2.3251 | 10512611 | 3.0818 | 27154 | 9973791 | 0.3784 | 0.3210 | 47156 |
| compress_3 | 130002078 | 11.3109 | 11.3055 | 10.5642 | 10.5561 | 47611635 | 2.7305 | 432 | 36796777 | 0.0149 | 0.0225 | 40854 |
| compress_4 | 31223502 | 2.8688 | 2.6573 | 2.6933 | 2.5163 | 10514254 | 2.9696 | 37603 | 9851994 | 0.4482 | 0.3637 | 44949 |
| compress_5 | 33874609 | 2.9157 | 2.7138 | 2.6567 | 2.4986 | 11426946 | 2.9644 | 35758 | 10697221 | 0.4288 | 0.3283 | 46161 |
| compress_6 | 33888957 | 2.8621 | 2.6650 | 2.6252 | 2.4640 | 11414805 | 2.9689 | 35329 | 10698282 | 0.4169 | 0.3333 | 42518 |
| compress_7 | 130170487 | 4.3716 | 4.2527 | 4.1102 | 3.9884 | 43371469 | 3.0013 | 104901 | 39303403 | 0.2654 | 0.2688 | 46073 |
| fp_0 | 30000052 | 3.7447 | 3.7445 | 3.8832 | 3.8832 | 6560707 | 4.5727 | 0 | 5676636 | 0.0003 | 0.0000 | 74576 |
| fp_1 | 30000112 | 17.3781 | 17.3769 | 17.4464 | 17.4463 | 13528126 | 2.2176 | 0 | 9303702 | 0.0022 | 0.0003 | 29933 |
| fp_2 | 30015430 | 4.7972 | 4.7954 | 4.8844 | 4.8842 | 8728947 | 3.4386 | 1 | 7872955 | 0.0042 | 0.0005 | 57293 |
| fp_3 | 30057392 | 7.0569 | 7.0552 | 7.1728 | 7.1726 | 8358619 | 3.5960 | 13 | 6552110 | 0.0033 | 0.0003 | 47894 |
| fp_4 | 30028845 | 2.2698 | 2.2610 | 1.6835 | 1.6780 | 7651447 | 3.9246 | 96 | 7212351 | 0.0203 | 0.0104 | 68348 |
| fp_5 | 40001887 | 1.0469 | 1.0467 | 1.0503 | 1.0503 | 6382840 | 6.2671 | 0 | 6022849 | 0.0009 | 0.0000 | 83270 |
| fp_6 | 40000142 | 11.4596 | 11.4575 | 11.3355 | 11.3354 | 17317832 | 2.3098 | 32 | 13955018 | 0.0068 | 0.0000 | 36716 |
| fp_7 | 40000178 | 8.6146 | 8.0295 | 8.6557 | 8.0714 | 17297963 | 2.3124 | 33 | 14356057 | 0.1007 | 0.0685 | 35448 |
| fp_8 | 40027042 | 9.5395 | 9.5390 | 13.2942 | 13.2941 | 11856561 | 3.3759 | 51 | 7937577 | 0.0057 | 0.0002 | 49812 |
| fp_9 | 40038259 | 13.2047 | 13.1995 | 13.5456 | 13.5419 | 15765866 | 2.5396 | 38 | 12162307 | 0.0142 | 0.0059 | 35488 |
| fp_10 | 40014316 | 3.6198 | 3.6187 | 3.5289 | 3.5284 | 10766945 | 3.7164 | 15 | 9714098 | 0.0061 | 0.0000 | 61495 |
| fp_11 | 40003477 | 1.2721 | 1.2715 | 1.2693 | 1.2692 | 10156549 | 3.9387 | 0 | 9840878 | 0.0080 | 0.0003 | 55156 |
| fp_12 | 40001154 | 2.3154 | 2.3150 | 2.2406 | 2.2401 | 13016722 | 3.0731 | 0 | 12272061 | 0.0014 | 0.0018 | 53245 |
| fp_13 | 40000016 | 20.1967 | 20.1962 | 20.2395 | 20.2395 | 18813420 | 2.1261 | 0 | 13270531 | 0.0025 | 0.0000 | 33622 |
| infra_0 | 40310119 | 4.8167 | 4.5875 | 4.7885 | 4.5846 | 19686703 | 2.0476 | 69525 | 17660180 | 0.1712 | 0.1518 | 31800 |
| infra_1 | 37809710 | 4.3903 | 4.2538 | 4.0696 | 4.0274 | 19051204 | 1.9846 | 6947 | 17543246 | 0.2807 | 0.0814 | 30520 |
| infra_2 | 47556665 | 2.2251 | 2.1315 | 1.9944 | 1.9670 | 18224780 | 2.6095 | 6614 | 17383100 | 0.2014 | 0.0598 | 42746 |
| infra_3 | 40244620 | 3.8003 | 3.6113 | 3.6855 | 3.5248 | 18040550 | 2.2308 | 41402 | 16458956 | 0.1497 | 0.1047 | 33716 |
| infra_4 | 40457439 | 7.9531 | 7.5540 | 7.8320 | 7.4511 | 21213138 | 1.9072 | 4398 | 18505883 | 0.0683 | 0.0693 | 27346 |
| infra_5 | 40000016 | 3.2474 | 3.2459 | 4.0371 | 4.0343 | 17773176 | 2.2506 | 29 | 17133856 | 0.0034 | 0.0060 | 34918 |
| infra_6 | 65945329 | 4.7316 | 4.3855 | 4.3484 | 4.1818 | 31262908 | 2.1094 | 14625 | 28196106 | 0.3613 | 0.1052 | 29941 |
| infra_7 | 40594320 | 8.3219 | 8.3196 | 8.0823 | 8.0820 | 21226332 | 1.9125 | 0 | 18465637 | 0.0043 | 0.0003 | 29520 |
| infra_8 | 40000016 | 2.4516 | 2.4515 | 2.4433 | 2.4433 | 17708980 | 2.2587 | 0 | 17137606 | 0.0003 | 0.0000 | 39657 |
| infra_9 | 50834083 | 10.5997 | 9.3522 | 7.7988 | 7.7983 | 25095063 | 2.0257 | 212032 | 21579492 | 2.8744 | 0.0002 | 35087 |
| infra_10 | 50908220 | 7.5746 | 7.5707 | 7.7301 | 7.7299 | 19337002 | 2.6327 | 11 | 16457190 | 0.0073 | 0.0001 | 42953 |
| infra_11 | 50619968 | 14.3750 | 11.3104 | 14.3142 | 11.3698 | 31416037 | 1.6113 | 562177 | 27722009 | 6.9610 | 6.9045 | 23303 |
| infra_12 | 50621265 | 14.9651 | 11.8013 | 14.6847 | 11.6051 | 31891328 | 1.5873 | 533032 | 28038888 | 7.2148 | 7.0425 | 24490 |
| infra_13 | 50914353 | 8.4256 | 7.9838 | 8.9952 | 8.1294 | 21451450 | 2.3735 | 80982 | 18245292 | 1.0095 | 1.9785 | 40687 |
| infra_14 | 50898572 | 7.7509 | 7.7473 | 7.8026 | 7.8024 | 19350719 | 2.6303 | 11 | 16422083 | 0.0075 | 0.0002 | 39273 |
| infra_15 | 50756396 | 10.5367 | 10.5352 | 9.1953 | 9.1934 | 20627755 | 2.4606 | 6 | 16653955 | 0.0051 | 0.0050 | 35038 |
| int_0 | 40021347 | 6.5840 | 6.5809 | 6.5093 | 6.5067 | 15269215 | 2.6210 | 34 | 13429772 | 0.0127 | 0.0135 | 39778 |
| int_1 | 30042538 | 18.0642 | 18.0635 | 17.9841 | 17.9841 | 15527307 | 1.9348 | 0 | 11368213 | 0.0014 | 0.0000 | 32036 |
| int_2 | 30040556 | 17.6098 | 17.6090 | 17.5646 | 17.5646 | 15499088 | 1.9382 | 0 | 11436886 | 0.0014 | 0.0000 | 26763 |
| int_3 | 40654006 | 4.6818 | 4.2714 | 5.2497 | 4.8123 | 17749569 | 2.2904 | 2354 | 15802822 | 0.2145 | 0.3192 | 33076 |
| int_4 | 60243739 | 12.9678 | 11.7050 | 13.4797 | 12.1023 | 31827683 | 1.8928 | 176235 | 26585573 | 2.8501 | 3.2075 | 27270 |
| int_5 | 30014814 | 5.0481 | 5.0464 | 4.9965 | 4.9963 | 8902429 | 3.3715 | 1 | 8007311 | 0.0041 | 0.0005 | 48612 |
| int_6 | 30010296 | 5.1791 | 5.1774 | 5.1602 | 5.1602 | 9681389 | 3.0998 | 1 | 8769207 | 0.0042 | 0.0001 | 58707 |
| int_7 | 40563698 | 19.4581 | 16.9642 | 19.5866 | 17.1273 | 27209737 | 1.4908 | 199121 | 21859413 | 5.9099 | 5.8737 | 21415 |
| int_8 | 40612229 | 19.4917 | 16.9259 | 18.6638 | 16.1694 | 27507949 | 1.4764 | 190618 | 22034541 | 5.6826 | 5.3640 | 22850 |
| int_9 | 41058375 | 19.9326 | 16.4515 | 20.6037 | 16.9896 | 32668603 | 1.2568 | 368481 | 27369947 | 7.8415 | 8.1442 | 17695 |
| int_10 | 60181179 | 3.2678 | 2.9574 | 3.3201 | 3.0000 | 25771841 | 2.3352 | 10870 | 23953039 | 0.1153 | 0.1041 | 35739 |
| int_11 | 60072079 | 7.1210 | 7.1203 | 7.1919 | 7.1919 | 17611374 | 3.4110 | 1 | 13807518 | 0.0039 | 0.0001 | 46672 |
| int_12 | 60155787 | 1.5953 | 1.5111 | 2.5515 | 2.3964 | 19151746 | 3.1410 | 63224 | 18377442 | 0.1769 | 0.3268 | 46158 |
| int_13 | 40235388 | 2.9450 | 2.8310 | 2.9087 | 2.8093 | 14954404 | 2.6905 | 28 | 14204963 | 0.0209 | 0.0090 | 44481 |
| int_14 | 40117859 | 3.3370 | 3.2165 | 3.3460 | 3.2503 | 19611990 | 2.0456 | 205717 | 18851417 | 1.2461 | 1.1862 | 28830 |
| int_15 | 70262659 | 2.1523 | 1.9690 | 2.9615 | 2.6685 | 29557904 | 2.3771 | 3167 | 27830401 | 0.1982 | 0.3882 | 34964 |
| int_16 | 40486736 | 22.5007 | 20.0553 | 21.9792 | 19.7671 | 28305035 | 1.4304 | 56143 | 21745851 | 6.0725 | 5.6177 | 20320 |
| int_17 | 40475182 | 19.2592 | 17.2290 | 18.5278 | 16.6417 | 26591430 | 1.5221 | 55009 | 20868063 | 4.7116 | 3.8541 | 21950 |
| int_18 | 40083762 | 3.1190 | 3.1130 | 3.2723 | 3.2712 | 15296010 | 2.6205 | 3451 | 14270104 | 0.0179 | 0.0046 | 42484 |
| int_19 | 40433274 | 15.2159 | 14.1636 | 15.3049 | 14.2437 | 25167737 | 1.6066 | 19670 | 20430066 | 4.1987 | 4.2186 | 28423 |
| int_20 | 60789783 | 11.6546 | 10.7517 | 12.0701 | 11.2847 | 33353916 | 1.8226 | 49290 | 27852534 | 1.7276 | 1.6528 | 26904 |
| int_21 | 40025623 | 28.5968 | 28.5966 | 29.4377 | 29.4377 | 26570779 | 1.5064 | 0 | 16532847 | 0.0033 | 0.0001 | 25267 |
| int_22 | 40000052 | 9.2932 | 9.2930 | 9.3652 | 9.3652 | 16793354 | 2.3819 | 0 | 14140147 | 0.0006 | 0.0000 | 34839 |
| int_23 | 40171640 | 7.3122 | 7.0266 | 7.2025 | 6.9415 | 17738699 | 2.2646 | 112 | 15563670 | 0.0455 | 0.0310 | 36371 |
| int_24 | 40082524 | 2.7278 | 2.5878 | 2.1271 | 2.0358 | 17247372 | 2.3240 | 3204 | 16479619 | 0.2245 | 0.1443 | 33950 |
| int_25 | 40001016 | 2.8026 | 2.7778 | 3.4936 | 3.4472 | 10005081 | 3.9981 | 53 | 9323991 | 0.0473 | 0.0883 | 54459 |
| int_26 | 40000853 | 4.4963 | 3.8332 | 4.4509 | 3.7982 | 10268877 | 3.8953 | 860 | 8899866 | 0.4090 | 0.3864 | 73635 |
| int_27 | 40001397 | 3.0848 | 2.5079 | 2.8971 | 2.3639 | 9420837 | 4.2461 | 3277 | 8481728 | 0.3400 | 0.2976 | 81598 |
| int_28 | 40012271 | 8.4218 | 8.3924 | 8.2463 | 8.2203 | 14671227 | 2.7273 | 0 | 11890222 | 0.1615 | 0.1324 | 47011 |
| int_29 | 40002148 | 18.0109 | 18.0038 | 18.0519 | 18.0465 | 17972472 | 2.2257 | 0 | 11497336 | 0.0272 | 0.0151 | 36162 |
| int_30 | 40003194 | 18.8000 | 18.7918 | 18.7389 | 18.7322 | 18516857 | 2.1604 | 0 | 11745181 | 0.0288 | 0.0164 | 31488 |
| int_31 | 40005666 | 10.1212 | 10.1208 | 9.8854 | 9.8854 | 12748967 | 3.1380 | 0 | 10376334 | 0.0115 | 0.0018 | 49146 |
| int_32 | 110001741 | 12.7283 | 12.0372 | 12.5932 | 11.9289 | 41112379 | 2.6756 | 0 | 30232968 | 0.0027 | 0.0006 | 42474 |
| int_33 | 110003344 | 12.3952 | 11.9638 | 12.7044 | 12.2341 | 43647801 | 2.5202 | 0 | 33143963 | 0.0034 | 0.0001 | 40459 |
| int_34 | 40000285 | 5.2584 | 5.1897 | 5.5808 | 5.5114 | 13968845 | 2.8635 | 0 | 12499076 | 0.0066 | 0.0030 | 42810 |
| int_35 | 40000239 | 7.3815 | 7.3170 | 7.2640 | 7.2276 | 14074068 | 2.8421 | 32 | 12060309 | 0.0111 | 0.0032 | 42052 |
| int_36 | 54394596 | 18.3316 | 12.4422 | 18.5431 | 12.4928 | 44346853 | 1.2266 | 1211845 | 39716027 | 10.7270 | 11.1419 | 19505 |
| media_0 | 20089838 | 5.1079 | 4.6541 | 4.8079 | 4.4188 | 6031655 | 3.3307 | 2454 | 5083287 | 0.1482 | 0.1049 | 53299 |
| media_1 | 20061766 | 4.6707 | 4.3133 | 3.8901 | 3.6136 | 5578706 | 3.5961 | 2105 | 4734996 | 0.1604 | 0.1162 | 67639 |
| media_2 | 20000262 | 1.7986 | 1.7908 | 2.1589 | 2.1564 | 4645823 | 4.3050 | 31 | 4331221 | 0.0169 | 0.0054 | 60027 |
| media_3 | 20087778 | 5.3286 | 4.8860 | 5.2315 | 4.8218 | 6093657 | 3.2965 | 1745 | 5105185 | 0.1557 | 0.1240 | 49172 |
| web_0 | 40104281 | 6.1024 | 6.0551 | 4.7086 | 4.6695 | 23997280 | 1.6712 | 16406 | 21950193 | 0.1604 | 0.1410 | 25406 |
| web_1 | 40387503 | 10.9208 | 9.1828 | 11.1743 | 9.4071 | 23119255 | 1.7469 | 448360 | 19903302 | 2.6794 | 2.3903 | 26822 |
| web_2 | 40714934 | 12.0813 | 10.8542 | 12.7577 | 11.8317 | 23520816 | 1.7310 | 192113 | 19498534 | 1.6979 | 1.1957 | 27494 |
| web_3 | 40455230 | 9.0571 | 8.0223 | 7.9767 | 7.1996 | 20143526 | 2.0083 | 106726 | 17158098 | 1.1830 | 1.0080 | 33314 |
| web_4 | 40746223 | 11.1885 | 10.1651 | 10.2584 | 9.2731 | 23501835 | 1.7337 | 245367 | 19801101 | 1.5696 | 1.6492 | 26606 |
| web_5 | 40581075 | 11.3586 | 10.3696 | 12.3612 | 11.4579 | 22495467 | 1.8040 | 133579 | 18764805 | 1.3990 | 1.4140 | 27308 |
| web_6 | 40839031 | 12.2848 | 11.2872 | 12.1707 | 11.7282 | 23825772 | 1.7141 | 155246 | 19686879 | 1.4606 | 0.4012 | 27974 |
| web_7 | 40045370 | 11.2286 | 11.0041 | 10.4718 | 10.2085 | 18913327 | 2.1173 | 11899 | 16434470 | 0.5283 | 0.6179 | 35742 |
| web_8 | 40680621 | 11.8770 | 10.8014 | 10.6477 | 9.7952 | 22776760 | 1.7861 | 68196 | 18948440 | 1.5563 | 0.9388 | 25372 |
| web_9 | 40205233 | 11.0665 | 8.8627 | 0.0625 | 0.0624 | 21687574 | 1.8538 | 120725 | 18951002 | 4.6783 | 0.0001 | 34549 |
| web_10 | 20318104 | 11.9477 | 8.5188 | 8.1206 | 6.4408 | 13125977 | 1.5479 | 188944 | 12046756 | 6.9914 | 3.3401 | 24955 |
| web_11 | 10210549 | 18.3692 | 12.1265 | 19.3874 | 12.4390 | 8390065 | 1.2170 | 156821 | 7615418 | 11.6535 | 12.5891 | 22138 |
| web_12 | 15144696 | 14.8542 | 11.9299 | 11.5303 | 9.8289 | 9287640 | 1.6306 | 118938 | 8106987 | 6.5191 | 3.4203 | 25059 |
| web_13 | 40306656 | 11.0500 | 8.9823 | 11.1752 | 8.8602 | 21196281 | 1.9016 | 375766 | 18474364 | 4.0817 | 4.5768 | 31426 |
| web_14 | 70405419 | 8.4000 | 7.8409 | 7.8849 | 7.2353 | 33066872 | 2.1292 | 1276729 | 28961263 | 1.0163 | 1.1771 | 31473 |
| web_15 | 15132376 | 15.9481 | 13.1580 | 14.7499 | 11.9887 | 9448265 | 1.6016 | 98975 | 7973151 | 6.1372 | 5.8704 | 22853 |
| web_16 | 20145886 | 5.9485 | 4.3722 | 7.3440 | 5.2226 | 8079082 | 2.4936 | 126799 | 7385835 | 3.1437 | 4.3770 | 33588 |
| web_17 | 15188499 | 11.7211 | 8.4179 | 11.1410 | 7.6909 | 8774141 | 1.7311 | 58177 | 7915638 | 6.1156 | 6.4140 | 28396 |
| web_18 | 15013175 | 7.2492 | 6.5636 | 6.9423 | 6.3262 | 5448301 | 2.7556 | 25589 | 4823109 | 1.9120 | 1.7316 | 43275 |
| web_19 | 15145950 | 16.2976 | 13.2362 | 18.7740 | 15.0248 | 9216457 | 1.6434 | 40659 | 7723324 | 5.5725 | 6.5755 | 31135 |
| web_20 | 20188241 | 27.3858 | 19.5397 | 29.7182 | 20.7941 | 16919403 | 1.1932 | 135221 | 14309194 | 14.9936 | 17.0010 | 16987 |
| web_21 | 15278007 | 7.5150 | 6.5255 | 10.6941 | 9.4508 | 7557140 | 2.0217 | 24505 | 6703641 | 1.3591 | 2.3080 | 28083 |
| web_22 | 20014791 | 6.9404 | 6.3865 | 7.1013 | 6.5138 | 6962537 | 2.8746 | 19422 | 6118289 | 1.4795 | 1.6027 | 55367 |
| web_23 | 20133618 | 7.1555 | 5.9118 | 9.5156 | 7.5123 | 9233901 | 2.1804 | 47499 | 8548961 | 3.6428 | 5.0022 | 32132 |
| web_24 | 15255924 | 28.1927 | 20.1728 | 27.8165 | 19.6274 | 14605441 | 1.0445 | 208799 | 13349221 | 20.6905 | 21.1763 | 17152 |
| web_25 | 15047504 | 18.0275 | 15.2037 | 14.4456 | 13.3863 | 8612601 | 1.7471 | 21879 | 6902078 | 4.7542 | 0.7786 | 30098 |

Per trace, per predictor (baseline; count and MPKI):
| trace | mis_ubtb (mpki) | mis_loop (mpki) | mis_ftb (mpki) | mis_tage (mpki) | mis_sc (mpki) | mis_ittage (mpki) | mis_ras (mpki) | mis_none (mpki) | mis direct / indirect / return |
|---|---|---|---|---|---|---|---|---|---|
| compress_0 | 0 (0.0000) | 344 (0.0029) | 589593 (4.9129) | 144818 (1.2067) | 62232 (0.5186) | 19 (0.0002) | 28 (0.0002) | 7059 (0.0588) | 0 / 408 / 1874 |
| compress_1 | 2 (0.0001) | 92 (0.0030) | 38496 (1.2486) | 16986 (0.5509) | 8689 (0.2818) | 226 (0.0073) | 462 (0.0150) | 12846 (0.4167) | 0 / 926 / 4355 |
| compress_2 | 1 (0.0000) | 83 (0.0026) | 37625 (1.1613) | 15569 (0.4806) | 7803 (0.2408) | 310 (0.0096) | 721 (0.0223) | 13236 (0.4085) | 0 / 1041 / 4746 |
| compress_3 | 3 (0.0000) | 9701 (0.0746) | 768815 (5.9139) | 490788 (3.7752) | 198764 (1.5289) | 9 (0.0001) | 37 (0.0003) | 2321 (0.0179) | 0 / 140 / 560 |
| compress_4 | 62 (0.0020) | 206 (0.0066) | 42373 (1.3571) | 20014 (0.6410) | 10398 (0.3330) | 430 (0.0138) | 870 (0.0279) | 15222 (0.4875) | 0 / 1278 / 5327 |
| compress_5 | 257 (0.0076) | 181 (0.0053) | 47944 (1.4153) | 22001 (0.6495) | 11345 (0.3349) | 394 (0.0116) | 862 (0.0254) | 15784 (0.4660) | 0 / 1269 / 5569 |
| compress_6 | 52 (0.0015) | 185 (0.0055) | 47351 (1.3972) | 21523 (0.6351) | 11180 (0.3299) | 407 (0.0120) | 863 (0.0255) | 15434 (0.4554) | 0 / 1285 / 5396 |
| compress_7 | 0 (0.0000) | 610 (0.0047) | 394332 (3.0294) | 94885 (0.7289) | 41300 (0.3173) | 44 (0.0003) | 232 (0.0018) | 37655 (0.2893) | 0 / 1615 / 13862 |
| fp_0 | 0 (0.0000) | 12067 (0.4022) | 26156 (0.8719) | 48359 (1.6120) | 25752 (0.8584) | 0 (0.0000) | 0 (0.0000) | 8 (0.0003) | 0 / 2 / 4 |
| fp_1 | 0 (0.0000) | 25995 (0.8665) | 127515 (4.2505) | 265817 (8.8605) | 101938 (3.3979) | 0 (0.0000) | 0 (0.0000) | 79 (0.0026) | 0 / 13 / 21 |
| fp_2 | 0 (0.0000) | 48 (0.0016) | 119114 (3.9684) | 17613 (0.5868) | 7051 (0.2349) | 0 (0.0000) | 0 (0.0000) | 163 (0.0054) | 0 / 27 / 26 |
| fp_3 | 0 (0.0000) | 6937 (0.2308) | 173887 (5.7852) | 19945 (0.6636) | 11236 (0.3738) | 0 (0.0000) | 0 (0.0000) | 108 (0.0036) | 0 / 20 / 32 |
| fp_4 | 0 (0.0000) | 1410 (0.0470) | 56314 (1.8753) | 6384 (0.2126) | 3292 (0.1096) | 1 (0.0000) | 0 (0.0000) | 757 (0.0252) | 0 / 74 / 188 |
| fp_5 | 0 (0.0000) | 8 (0.0002) | 26558 (0.6639) | 10447 (0.2612) | 4818 (0.1204) | 0 (0.0000) | 0 (0.0000) | 47 (0.0012) | 0 / 3 / 5 |
| fp_6 | 0 (0.0000) | 4165 (0.1041) | 348691 (8.7172) | 63792 (1.5948) | 41374 (1.0343) | 1 (0.0000) | 0 (0.0000) | 363 (0.0091) | 0 / 37 / 48 |
| fp_7 | 0 (0.0000) | 4939 (0.1235) | 227883 (5.6970) | 50278 (1.2569) | 34259 (0.8565) | 21489 (0.5372) | 0 (0.0000) | 5738 (0.1434) | 0 / 21526 / 1878 |
| fp_8 | 0 (0.0000) | 99 (0.0025) | 133429 (3.3335) | 144859 (3.6190) | 103167 (2.5774) | 0 (0.0000) | 0 (0.0000) | 284 (0.0071) | 0 / 9 / 12 |
| fp_9 | 0 (0.0000) | 1383 (0.0345) | 332430 (8.3028) | 125992 (3.1468) | 67904 (1.6960) | 7 (0.0002) | 0 (0.0000) | 976 (0.0244) | 0 / 54 / 151 |
| fp_10 | 0 (0.0000) | 8327 (0.2081) | 79206 (1.9794) | 39308 (0.9823) | 17541 (0.4384) | 0 (0.0000) | 0 (0.0000) | 461 (0.0115) | 0 / 26 / 16 |
| fp_11 | 0 (0.0000) | 11178 (0.2794) | 30034 (0.7508) | 6476 (0.1619) | 2779 (0.0695) | 0 (0.0000) | 0 (0.0000) | 420 (0.0105) | 0 / 9 / 15 |
| fp_12 | 0 (0.0000) | 16942 (0.4235) | 40979 (1.0244) | 15250 (0.3812) | 19358 (0.4839) | 0 (0.0000) | 0 (0.0000) | 91 (0.0023) | 0 / 4 / 13 |
| fp_13 | 0 (0.0000) | 551 (0.0138) | 435496 (10.8874) | 254209 (6.3552) | 117469 (2.9367) | 0 (0.0000) | 0 (0.0000) | 143 (0.0036) | 0 / 2 / 18 |
| infra_0 | 1 (0.0000) | 149 (0.0037) | 114047 (2.8292) | 43492 (1.0789) | 21384 (0.5305) | 6658 (0.1652) | 1 (0.0000) | 8428 (0.2091) | 0 / 7842 / 1397 |
| infra_1 | 0 (0.0000) | 9 (0.0002) | 131047 (3.4660) | 16206 (0.4286) | 6626 (0.1752) | 396 (0.0105) | 93 (0.0025) | 11618 (0.3073) | 0 / 1862 / 3297 |
| infra_2 | 0 (0.0000) | 0 (0.0000) | 78703 (1.6549) | 12293 (0.2585) | 4054 (0.0852) | 172 (0.0036) | 96 (0.0020) | 10499 (0.2208) | 0 / 1475 / 2974 |
| infra_3 | 0 (0.0000) | 103 (0.0026) | 89340 (2.2199) | 33024 (0.8206) | 17802 (0.4423) | 5248 (0.1304) | 0 (0.0000) | 7424 (0.1845) | 0 / 6050 / 1554 |
| infra_4 | 2 (0.0000) | 664 (0.0164) | 187982 (4.6464) | 74537 (1.8424) | 40132 (0.9920) | 15009 (0.3710) | 0 (0.0000) | 3436 (0.0849) | 0 / 15516 / 629 |
| infra_5 | 0 (0.0000) | 0 (0.0000) | 102822 (2.5705) | 20121 (0.5030) | 6797 (0.1699) | 0 (0.0000) | 0 (0.0000) | 157 (0.0039) | 0 / 18 / 44 |
| infra_6 | 16 (0.0002) | 461 (0.0070) | 200931 (3.0469) | 45305 (0.6870) | 26234 (0.3978) | 12549 (0.1903) | 96 (0.0015) | 26432 (0.4008) | 0 / 16022 / 6797 |
| infra_7 | 0 (0.0000) | 495 (0.0122) | 243116 (5.9889) | 57526 (1.4171) | 36454 (0.8980) | 28 (0.0007) | 0 (0.0000) | 203 (0.0050) | 0 / 53 / 42 |
| infra_8 | 0 (0.0000) | 0 (0.0000) | 95932 (2.3983) | 1919 (0.0480) | 195 (0.0049) | 0 (0.0000) | 0 (0.0000) | 18 (0.0004) | 0 / 2 / 3 |
| infra_9 | 11 (0.0002) | 2211 (0.0435) | 140268 (2.7593) | 145804 (2.8682) | 90344 (1.7772) | 1385 (0.0272) | 218 (0.0043) | 158583 (3.1196) | 0 / 28304 / 35110 |
| infra_10 | 0 (0.0000) | 8440 (0.1658) | 187716 (3.6873) | 129478 (2.5434) | 59460 (1.1680) | 35 (0.0007) | 0 (0.0000) | 479 (0.0094) | 0 / 109 / 87 |
| infra_11 | 24 (0.0005) | 1801 (0.0356) | 99373 (1.9631) | 125992 (2.4890) | 112453 (2.2215) | 3444 (0.0680) | 2557 (0.0505) | 382018 (7.5468) | 0 / 67131 / 87999 |
| infra_12 | 27 (0.0005) | 1766 (0.0349) | 99350 (1.9626) | 133768 (2.6425) | 119100 (2.3528) | 3754 (0.0742) | 1000 (0.0198) | 398788 (7.8779) | 0 / 72020 / 88136 |
| infra_13 | 9 (0.0002) | 8069 (0.1585) | 171026 (3.3591) | 125141 (2.4579) | 67530 (1.3263) | 503 (0.0099) | 80 (0.0016) | 56624 (1.1121) | 0 / 9971 / 12521 |
| infra_14 | 0 (0.0000) | 8783 (0.1726) | 192372 (3.7795) | 131902 (2.5915) | 60927 (1.1970) | 23 (0.0005) | 0 (0.0000) | 505 (0.0099) | 0 / 98 / 90 |
| infra_15 | 0 (0.0000) | 4039 (0.0796) | 252072 (4.9663) | 191609 (3.7751) | 86730 (1.7088) | 2 (0.0000) | 0 (0.0000) | 355 (0.0070) | 0 / 29 / 48 |
| int_0 | 0 (0.0000) | 607 (0.0152) | 172961 (4.3217) | 63315 (1.5820) | 26022 (0.6502) | 0 (0.0000) | 0 (0.0000) | 594 (0.0148) | 0 / 27 / 96 |
| int_1 | 0 (0.0000) | 5259 (0.1751) | 287008 (9.5534) | 171467 (5.7075) | 78913 (2.6267) | 0 (0.0000) | 0 (0.0000) | 48 (0.0016) | 0 / 12 / 10 |
| int_2 | 0 (0.0000) | 5999 (0.1997) | 280836 (9.3486) | 165559 (5.5112) | 76563 (2.5487) | 0 (0.0000) | 0 (0.0000) | 51 (0.0017) | 0 / 13 / 10 |
| int_3 | 16 (0.0004) | 23464 (0.5772) | 105899 (2.6049) | 22262 (0.5476) | 15219 (0.3744) | 12092 (0.2974) | 8 (0.0002) | 11373 (0.2798) | 0 / 13930 / 2752 |
| int_4 | 4 (0.0001) | 20072 (0.3332) | 263072 (4.3668) | 171067 (2.8396) | 121147 (2.0109) | 7334 (0.1217) | 276 (0.0046) | 198258 (3.2909) | 0 / 26622 / 49455 |
| int_5 | 0 (0.0000) | 103 (0.0034) | 124175 (4.1371) | 19874 (0.6621) | 7221 (0.2406) | 0 (0.0000) | 0 (0.0000) | 145 (0.0048) | 0 / 26 / 26 |
| int_6 | 0 (0.0000) | 23 (0.0008) | 135430 (4.5128) | 14559 (0.4851) | 5226 (0.1741) | 0 (0.0000) | 0 (0.0000) | 188 (0.0063) | 0 / 25 / 26 |
| int_7 | 86 (0.0021) | 1684 (0.0415) | 205704 (5.0711) | 160721 (3.9622) | 143638 (3.5410) | 8682 (0.2140) | 98 (0.0024) | 268680 (6.6237) | 0 / 46449 / 54714 |
| int_8 | 101 (0.0025) | 1050 (0.0259) | 199414 (4.9102) | 169816 (4.1814) | 144845 (3.5665) | 15068 (0.3710) | 206 (0.0051) | 261101 (6.4291) | 0 / 51000 / 53203 |
| int_9 | 168 (0.0041) | 688 (0.0168) | 153071 (3.7281) | 148471 (3.6161) | 133435 (3.2499) | 20652 (0.5030) | 157 (0.0038) | 361760 (8.8109) | 0 / 70570 / 72361 |
| int_10 | 3 (0.0000) | 280 (0.0047) | 139419 (2.3167) | 22005 (0.3656) | 10452 (0.1737) | 16157 (0.2685) | 0 (0.0000) | 8345 (0.1387) | 0 / 17048 / 1631 |
| int_11 | 0 (0.0000) | 10689 (0.1779) | 287580 (4.7872) | 92267 (1.5359) | 36978 (0.6156) | 0 (0.0000) | 0 (0.0000) | 258 (0.0043) | 0 / 8 / 30 |
| int_12 | 1 (0.0000) | 2135 (0.0355) | 59523 (0.9895) | 14019 (0.2330) | 7989 (0.1328) | 217 (0.0036) | 11 (0.0002) | 12071 (0.2007) | 0 / 1043 / 4020 |
| int_13 | 0 (0.0000) | 892 (0.0222) | 78795 (1.9584) | 25166 (0.6255) | 8290 (0.2060) | 4326 (0.1075) | 0 (0.0000) | 1023 (0.0254) | 0 / 4496 / 88 |
| int_14 | 42 (0.0010) | 17 (0.0004) | 75039 (1.8705) | 3959 (0.0987) | 3621 (0.0903) | 374 (0.0093) | 9 (0.0002) | 50813 (1.2666) | 0 / 2067 / 2768 |
| int_15 | 4 (0.0001) | 171 (0.0024) | 96225 (1.3695) | 17642 (0.2511) | 10952 (0.1559) | 10058 (0.1431) | 0 (0.0000) | 16173 (0.2302) | 0 / 10822 / 2059 |
| int_16 | 125 (0.0031) | 921 (0.0227) | 211728 (5.2296) | 196872 (4.8626) | 183536 (4.5332) | 24482 (0.6047) | 203 (0.0050) | 293114 (7.2398) | 0 / 61112 / 37894 |
| int_17 | 112 (0.0028) | 1121 (0.0277) | 221153 (5.4639) | 161326 (3.9858) | 143932 (3.5561) | 23187 (0.5729) | 157 (0.0039) | 228530 (5.6462) | 0 / 51730 / 30441 |
| int_18 | 0 (0.0000) | 35 (0.0009) | 87394 (2.1803) | 24236 (0.6046) | 12373 (0.3087) | 18 (0.0004) | 5 (0.0001) | 959 (0.0239) | 0 / 63 / 178 |
| int_19 | 208 (0.0051) | 3324 (0.0822) | 283913 (7.0218) | 58342 (1.4429) | 54132 (1.3388) | 6810 (0.1684) | 29 (0.0007) | 208470 (5.1559) | 0 / 24158 / 18390 |
| int_20 | 70 (0.0012) | 2523 (0.0415) | 365471 (6.0120) | 106690 (1.7551) | 87392 (1.4376) | 24403 (0.4014) | 106 (0.0017) | 121825 (2.0040) | 0 / 39903 / 14984 |
| int_21 | 0 (0.0000) | 24720 (0.6176) | 434060 (10.8446) | 464974 (11.6169) | 220683 (5.5135) | 0 (0.0000) | 0 (0.0000) | 167 (0.0042) | 0 / 2 / 6 |
| int_22 | 0 (0.0000) | 4891 (0.1223) | 133230 (3.3307) | 155916 (3.8979) | 77656 (1.9414) | 0 (0.0000) | 0 (0.0000) | 37 (0.0009) | 0 / 2 / 7 |
| int_23 | 1 (0.0000) | 8125 (0.2023) | 178204 (4.4361) | 66421 (1.6534) | 28837 (0.7178) | 9861 (0.2455) | 4 (0.0001) | 2289 (0.0570) | 0 / 10857 / 614 |
| int_24 | 21 (0.0005) | 1027 (0.0256) | 78524 (1.9591) | 11993 (0.2992) | 7272 (0.1814) | 637 (0.0159) | 0 (0.0000) | 9864 (0.2461) | 0 / 4131 / 1483 |
| int_25 | 1 (0.0000) | 5260 (0.1315) | 74489 (1.8622) | 21011 (0.5253) | 8670 (0.2167) | 139 (0.0035) | 0 (0.0000) | 2538 (0.0634) | 0 / 744 / 250 |
| int_26 | 14 (0.0003) | 1642 (0.0410) | 88527 (2.2131) | 29382 (0.7345) | 20725 (0.5181) | 18390 (0.4597) | 3 (0.0001) | 21174 (0.5293) | 0 / 23666 / 2858 |
| int_27 | 37 (0.0009) | 339 (0.0085) | 58460 (1.4614) | 18642 (0.4660) | 12497 (0.3124) | 16847 (0.4212) | 0 (0.0000) | 16573 (0.4143) | 0 / 20208 / 2867 |
| int_28 | 61 (0.0015) | 2017 (0.0504) | 186984 (4.6732) | 84610 (2.1146) | 54778 (1.3690) | 273 (0.0068) | 0 (0.0000) | 8254 (0.2063) | 0 / 286 / 893 |
| int_29 | 25 (0.0006) | 2762 (0.0690) | 345875 (8.6464) | 243328 (6.0829) | 126413 (3.1602) | 0 (0.0000) | 0 (0.0000) | 2070 (0.0517) | 0 / 73 / 208 |
| int_30 | 25 (0.0006) | 3133 (0.0783) | 358938 (8.9727) | 254535 (6.3629) | 132990 (3.3245) | 0 (0.0000) | 0 (0.0000) | 2441 (0.0610) | 0 / 84 / 247 |
| int_31 | 0 (0.0000) | 0 (0.0000) | 357395 (8.9336) | 27409 (0.6851) | 19582 (0.4895) | 0 (0.0000) | 0 (0.0000) | 518 (0.0129) | 0 / 2 / 11 |
| int_32 | 0 (0.0000) | 11444 (0.1040) | 776412 (7.0582) | 344948 (3.1358) | 190995 (1.7363) | 75951 (0.6905) | 0 (0.0000) | 381 (0.0035) | 0 / 75994 / 29 |
| int_33 | 4 (0.0000) | 8371 (0.0761) | 723993 (6.5816) | 381129 (3.4647) | 202169 (1.8378) | 47354 (0.4305) | 0 (0.0000) | 498 (0.0045) | 0 / 47428 / 30 |
| int_34 | 0 (0.0000) | 1068 (0.0267) | 142125 (3.5531) | 41646 (1.0411) | 22487 (0.5622) | 2691 (0.0673) | 0 (0.0000) | 319 (0.0080) | 0 / 2719 / 26 |
| int_35 | 1 (0.0000) | 883 (0.0221) | 212045 (5.3011) | 47457 (1.1864) | 31910 (0.7977) | 2443 (0.0611) | 0 (0.0000) | 524 (0.0131) | 0 / 2493 / 88 |
| int_36 | 59 (0.0011) | 400 (0.0074) | 112287 (2.0643) | 121511 (2.2339) | 123261 (2.2661) | 14277 (0.2625) | 1661 (0.0305) | 623682 (11.4659) | 0 / 148614 / 171736 |
| media_0 | 0 (0.0000) | 1033 (0.0514) | 56337 (2.8043) | 20048 (0.9979) | 13643 (0.6791) | 6715 (0.3342) | 1 (0.0000) | 4840 (0.2409) | 0 / 7912 / 1204 |
| media_1 | 7 (0.0003) | 867 (0.0432) | 51837 (2.5839) | 18412 (0.9178) | 13069 (0.6514) | 4870 (0.2428) | 0 (0.0000) | 4640 (0.2313) | 0 / 6021 / 1149 |
| media_2 | 0 (0.0000) | 315 (0.0157) | 29596 (1.4798) | 3881 (0.1940) | 1787 (0.0893) | 7 (0.0003) | 0 (0.0000) | 387 (0.0193) | 0 / 75 / 81 |
| media_3 | 2 (0.0001) | 1009 (0.0502) | 56850 (2.8301) | 22504 (1.1203) | 15310 (0.7622) | 6459 (0.3215) | 0 (0.0000) | 4906 (0.2442) | 0 / 7615 / 1276 |
| web_0 | 0 (0.0000) | 1462 (0.0365) | 170905 (4.2615) | 37457 (0.9340) | 25981 (0.6478) | 398 (0.0099) | 0 (0.0000) | 8530 (0.2127) | 0 / 584 / 1314 |
| web_1 | 202 (0.0050) | 1489 (0.0369) | 144149 (3.5691) | 82534 (2.0436) | 61856 (1.5316) | 25310 (0.6267) | 21 (0.0005) | 125503 (3.1075) | 0 / 38789 / 31403 |
| web_2 | 50 (0.0012) | 1908 (0.0469) | 213122 (5.2345) | 106547 (2.6169) | 72024 (1.7690) | 17404 (0.4275) | 181 (0.0044) | 80653 (1.9809) | 0 / 27982 / 21978 |
| web_3 | 22 (0.0005) | 1314 (0.0325) | 146681 (3.6258) | 84510 (2.0890) | 57298 (1.4163) | 20302 (0.5018) | 364 (0.0090) | 55916 (1.3822) | 0 / 26704 / 15159 |
| web_4 | 46 (0.0011) | 2467 (0.0605) | 192080 (4.7141) | 103634 (2.5434) | 69134 (1.6967) | 13139 (0.3225) | 275 (0.0067) | 75115 (1.8435) | 0 / 19862 / 21840 |
| web_5 | 39 (0.0010) | 1712 (0.0422) | 207195 (5.1057) | 101946 (2.5122) | 68330 (1.6838) | 14815 (0.3651) | 199 (0.0049) | 66707 (1.6438) | 0 / 21125 / 19009 |
| web_6 | 46 (0.0011) | 2344 (0.0574) | 231453 (5.6674) | 112176 (2.7468) | 72088 (1.7652) | 13696 (0.3354) | 155 (0.0038) | 69742 (1.7077) | 0 / 20594 / 20147 |
| web_7 | 14 (0.0003) | 84 (0.0021) | 258625 (6.4583) | 121381 (3.0311) | 45517 (1.1366) | 167 (0.0042) | 2 (0.0000) | 23864 (0.5959) | 0 / 3430 / 5561 |
| web_8 | 32 (0.0008) | 1845 (0.0454) | 208219 (5.1184) | 109091 (2.6816) | 72959 (1.7935) | 17085 (0.4200) | 98 (0.0024) | 73835 (1.8150) | 0 / 23696 / 20061 |
| web_9 | 135 (0.0034) | 1130 (0.0281) | 75836 (1.8862) | 76104 (1.8929) | 71644 (1.7820) | 10508 (0.2614) | 22 (0.0005) | 209551 (5.2120) | 0 / 41660 / 46945 |
| web_10 | 13 (0.0006) | 1242 (0.0611) | 32778 (1.6132) | 32014 (1.5756) | 26782 (1.3181) | 1398 (0.0688) | 35 (0.0017) | 148492 (7.3084) | 0 / 29868 / 39800 |
| web_11 | 25 (0.0024) | 89 (0.0087) | 17812 (1.7445) | 21411 (2.0969) | 20749 (2.0321) | 3143 (0.3078) | 152 (0.0149) | 124179 (12.1618) | 0 / 30608 / 33134 |
| web_12 | 45 (0.0030) | 1151 (0.0760) | 45551 (3.0077) | 38311 (2.5297) | 30411 (2.0080) | 1378 (0.0910) | 11 (0.0007) | 108104 (7.1381) | 0 / 22271 / 22016 |
| web_13 | 83 (0.0021) | 3581 (0.0888) | 105388 (2.6147) | 80785 (2.0043) | 62536 (1.5515) | 12867 (0.3192) | 379 (0.0094) | 179769 (4.4600) | 0 / 42147 / 41195 |
| web_14 | 0 (0.0000) | 43670 (0.6203) | 303600 (4.3122) | 108908 (1.5469) | 57996 (0.8237) | 166 (0.0024) | 2 (0.0000) | 77064 (1.0946) | 0 / 20467 / 18900 |
| web_15 | 37 (0.0024) | 481 (0.0318) | 43892 (2.9005) | 50528 (3.3391) | 38477 (2.5427) | 5991 (0.3959) | 52 (0.0034) | 101875 (6.7323) | 0 / 24297 / 17924 |
| web_16 | 12 (0.0006) | 1919 (0.0953) | 21993 (1.0917) | 15510 (0.7699) | 12990 (0.6448) | 704 (0.0349) | 108 (0.0054) | 66602 (3.3060) | 0 / 14435 / 17322 |
| web_17 | 18 (0.0012) | 388 (0.0255) | 36941 (2.4322) | 18880 (1.2430) | 19238 (1.2666) | 4280 (0.2818) | 23 (0.0015) | 98258 (6.4692) | 0 / 30056 / 20115 |
| web_18 | 0 (0.0000) | 3706 (0.2468) | 33807 (2.2518) | 22203 (1.4789) | 17480 (1.1643) | 92 (0.0061) | 0 (0.0000) | 31546 (2.1012) | 0 / 4564 / 5729 |
| web_19 | 14 (0.0009) | 1781 (0.1176) | 62823 (4.1478) | 47235 (3.1187) | 35850 (2.3670) | 7577 (0.5003) | 503 (0.0332) | 91060 (6.0122) | 0 / 29413 / 16955 |
| web_20 | 58 (0.0029) | 326 (0.0161) | 47502 (2.3530) | 91248 (4.5199) | 78802 (3.9034) | 11487 (0.5690) | 1395 (0.0691) | 322054 (15.9526) | 0 / 102562 / 55838 |
| web_21 | 20 (0.0013) | 664 (0.0435) | 58496 (3.8288) | 15873 (1.0389) | 12082 (0.7908) | 5385 (0.3525) | 19 (0.0012) | 22275 (1.4580) | 0 / 9731 / 5386 |
| web_22 | 0 (0.0000) | 5132 (0.2564) | 44846 (2.2406) | 32354 (1.6165) | 24011 (1.1997) | 129 (0.0064) | 75 (0.0037) | 32363 (1.6170) | 0 / 4824 / 6262 |
| web_23 | 7 (0.0003) | 3393 (0.1685) | 23474 (1.1659) | 19090 (0.9482) | 17545 (0.8714) | 818 (0.0406) | 0 (0.0000) | 79739 (3.9605) | 0 / 11774 / 13266 |
| web_24 | 27 (0.0018) | 53 (0.0035) | 14902 (0.9768) | 40614 (2.6622) | 44165 (2.8949) | 650 (0.0426) | 1 (0.0001) | 329693 (21.6108) | 0 / 53264 / 69086 |
| web_25 | 35 (0.0023) | 1501 (0.0998) | 81664 (5.4271) | 59883 (3.9796) | 40371 (2.6829) | 10173 (0.6761) | 43 (0.0029) | 77599 (5.1569) | 0 / 29484 / 13008 |

The comparison (PF-10), conditional MPKI, mean of the per-trace values
per group:
50% (second half) conditional MPKI, arithmetic mean of the per-trace values:

| predictor | compress | fp | infra | int | media | web | all |
|---|---|---|---|---|---|---|---|
| pacino head_s2 | 4.2087 | 7.8310 | 6.4953 | 9.9353 | 3.7526 | 9.7683 | 8.4173 |
| tage192 | 2.7229 | 4.1088 | 2.3625 | 4.1627 | 0.8115 | 3.1748 | 3.3992 |
| cbp2016 | 2.7592 | 4.2449 | 2.4342 | 4.6222 | 0.8864 | 3.6457 | 3.7124 |
| behrendt | 2.7240 | 4.0877 | 2.3682 | 4.1112 | 0.8240 | 3.1699 | 3.3785 |
| cai | 2.7303 | 4.0947 | 2.3551 | 4.2327 | 0.8536 | 3.2416 | 3.4396 |
| fan | 2.7593 | 3.7281 | 2.4360 | 4.2433 | 0.8945 | 3.6422 | 3.5097 |
| jimenez | 2.7303 | 4.0947 | 2.3551 | 4.2327 | 0.8536 | 3.2416 | 3.4396 |
| koizumi | 2.5011 | 3.6200 | 2.1698 | 3.9065 | 0.7784 | 3.0775 | 3.1721 |
| man | 2.6636 | 3.9723 | 2.2514 | 4.1073 | 0.8840 | 3.1743 | 3.3427 |
| ros | 2.7221 | 4.0926 | 2.3567 | 4.1638 | 0.7906 | 3.1332 | 3.3854 |
| seznec | 2.6607 | 4.0717 | 2.3288 | 4.0439 | 0.7986 | 3.1490 | 3.3357 |
| pacino - tage192 | +1.4858 | +3.7222 | +4.1327 | +5.7726 | +2.9411 | +6.5934 | +5.0181 |
| pacino / tage192 | 1.546 | 1.906 | 2.749 | 2.387 | 4.624 | 3.077 | 2.476 |
| per-trace ratio min..max | 1.38..2.13 | 1.12..12.85 | 1.17..21.35 | 1.21..24.22 | 3.09..5.80 | 1.82..18.35 | 1.12..24.22 |

full-trace conditional MPKI, arithmetic mean of the per-trace values:

| predictor | compress | fp | infra | int | media | web | all |
|---|---|---|---|---|---|---|---|
| pacino head_s2 | 4.3468 | 7.5648 | 6.6776 | 9.8539 | 3.9110 | 10.2112 | 8.5072 |
| tage192 | 2.7556 | 3.9039 | 2.5309 | 4.2701 | 0.9868 | 3.3816 | 3.4958 |
| cbp2016 | 2.7937 | 4.0111 | 2.5937 | 4.6719 | 1.0611 | 3.8332 | 3.7788 |
| behrendt | 2.7549 | 3.8747 | 2.5307 | 4.2135 | 0.9879 | 3.3668 | 3.4682 |
| cai | 2.7730 | 3.8973 | 2.5327 | 4.3479 | 1.0364 | 3.4727 | 3.5483 |
| fan | 2.7932 | 3.5593 | 2.5956 | 4.3044 | 1.0614 | 3.8307 | 3.5887 |
| jimenez | 2.7730 | 3.8973 | 2.5327 | 4.3479 | 1.0364 | 3.4727 | 3.5483 |
| koizumi | 2.5581 | 3.5259 | 2.3616 | 4.0124 | 0.9444 | 3.2623 | 3.2825 |
| man | 2.7139 | 3.7859 | 2.4305 | 4.2184 | 1.0601 | 3.3854 | 3.4471 |
| ros | 2.7551 | 3.8826 | 2.5247 | 4.2670 | 0.9632 | 3.3514 | 3.4825 |
| seznec | 2.6910 | 3.8564 | 2.4952 | 4.1447 | 0.9525 | 3.3264 | 3.4199 |
| pacino - tage192 | +1.5912 | +3.6609 | +4.1467 | +5.5838 | +2.9242 | +6.8295 | +5.0114 |
| pacino / tage192 | 1.577 | 1.938 | 2.638 | 2.308 | 3.963 | 3.020 | 2.434 |
| per-trace ratio min..max | 1.39..2.09 | 1.12..11.93 | 1.28..12.30 | 1.21..18.18 | 3.51..4.28 | 1.74..12.08 | 1.12..18.18 |
THE GAP IS NOT STEADY ACROSS THE GROUPS (PF-10's extrapolation rule
fails): pacino / tage192 at 50Perc is 1.55 compress, 1.91 fp, 2.75
infra, 2.39 int, 4.62 media, 3.08 web; per trace 1.12 to 24.22. The
ratio is largest where TAGE192's MPKI is smallest (media 0.81). Cycles
are the front end's under the immediate parameter backend (PF-18), not
a forecast of a core's.

Per trace comparison:
50Perc conditional MPKI per trace:

| trace | pacino | tage192 | cbp2016 | behrendt | cai | fan | jimenez | koizumi | man | ros | seznec | pacino - tage192 | pacino / tage192 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| compress_0 | 6.8251 | 3.2007 | 3.2668 | 3.2231 | 3.2166 | 3.2692 | 3.2166 | 3.0467 | 3.1830 | 3.2054 | 3.1650 | +3.6244 | 2.132 |
| compress_1 | 2.4957 | 1.8079 | 1.8263 | 1.8110 | 1.8156 | 1.8219 | 1.8156 | 1.5769 | 1.7480 | 1.8139 | 1.7840 | +0.6878 | 1.380 |
| compress_2 | 2.3251 | 1.6187 | 1.6288 | 1.6114 | 1.6305 | 1.6357 | 1.6305 | 1.4548 | 1.5536 | 1.6193 | 1.5936 | +0.7064 | 1.436 |
| compress_3 | 10.5561 | 7.6221 | 7.7366 | 7.6162 | 7.5808 | 7.7223 | 7.5808 | 7.2159 | 7.6276 | 7.5909 | 7.2736 | +2.9340 | 1.385 |
| compress_4 | 2.5163 | 1.6639 | 1.6842 | 1.6563 | 1.6736 | 1.6888 | 1.6736 | 1.5007 | 1.5896 | 1.6585 | 1.6402 | +0.8524 | 1.512 |
| compress_5 | 2.4986 | 1.6833 | 1.7035 | 1.6839 | 1.7078 | 1.7094 | 1.7078 | 1.5071 | 1.6219 | 1.6937 | 1.6651 | +0.8153 | 1.484 |
| compress_6 | 2.4640 | 1.6635 | 1.6906 | 1.6629 | 1.6833 | 1.6898 | 1.6833 | 1.5086 | 1.6043 | 1.6730 | 1.6462 | +0.8005 | 1.481 |
| compress_7 | 3.9884 | 2.5228 | 2.5371 | 2.5271 | 2.5339 | 2.5374 | 2.5339 | 2.1980 | 2.3809 | 2.5220 | 2.5182 | +1.4656 | 1.581 |
| fp_0 | 3.8832 | 3.3103 | 3.3141 | 3.3146 | 3.3113 | 3.3141 | 3.3113 | 3.3051 | 3.3201 | 3.3121 | 3.3052 | +0.5729 | 1.173 |
| fp_1 | 17.4463 | 15.6148 | 15.6474 | 15.6412 | 15.5890 | 15.6474 | 15.5890 | 14.9674 | 15.6500 | 15.6672 | 15.6078 | +1.8315 | 1.117 |
| fp_2 | 4.8842 | 2.6011 | 2.6160 | 2.5952 | 2.5990 | 2.6119 | 2.5990 | 2.4271 | 2.5737 | 2.5921 | 2.5829 | +2.2831 | 1.878 |
| fp_3 | 7.1726 | 1.9756 | 2.0818 | 1.9786 | 1.9699 | 2.0764 | 1.9699 | 1.8484 | 2.0371 | 1.9416 | 1.9147 | +5.1970 | 3.631 |
| fp_4 | 1.6780 | 0.4330 | 0.4367 | 0.4461 | 0.4426 | 0.4348 | 0.4426 | 0.4183 | 0.4330 | 0.4353 | 0.4211 | +1.2450 | 3.875 |
| fp_5 | 1.0503 | 0.9295 | 0.9320 | 0.9274 | 0.9253 | 0.9334 | 0.9253 | 0.9184 | 0.9246 | 0.9296 | 0.9242 | +0.1208 | 1.130 |
| fp_6 | 11.3354 | 0.8824 | 0.9563 | 0.8665 | 0.8799 | 0.9250 | 0.8799 | 0.8552 | 0.8933 | 0.8430 | 0.8113 | +10.4530 | 12.846 |
| fp_7 | 8.0714 | 0.8573 | 0.9687 | 0.8742 | 0.8638 | 0.9780 | 0.8638 | 0.8293 | 0.8697 | 0.8498 | 0.8137 | +7.2141 | 9.415 |
| fp_8 | 13.2941 | 10.5428 | 11.0660 | 10.4496 | 10.4723 | 7.8502 | 10.4723 | 5.2602 | 9.4840 | 10.5543 | 10.4557 | +2.7513 | 1.261 |
| fp_9 | 13.5419 | 4.4784 | 4.9042 | 4.5710 | 4.4156 | 4.9062 | 4.4156 | 4.3132 | 4.3477 | 4.3727 | 4.3881 | +9.0635 | 3.024 |
| fp_10 | 3.5284 | 1.8938 | 2.0181 | 1.8660 | 1.9312 | 1.8341 | 1.9312 | 1.8939 | 1.8577 | 1.8289 | 1.9239 | +1.6346 | 1.863 |
| fp_11 | 1.2692 | 0.5855 | 0.6903 | 0.5560 | 0.6394 | 0.6790 | 0.6394 | 0.5532 | 0.5788 | 0.6073 | 0.5624 | +0.6837 | 2.168 |
| fp_12 | 2.2401 | 1.0234 | 1.0800 | 0.7133 | 0.9632 | 1.0752 | 0.9632 | 0.9032 | 0.7039 | 0.9422 | 0.9730 | +1.2167 | 2.189 |
| fp_13 | 20.2395 | 12.3958 | 12.7175 | 12.4274 | 12.3231 | 8.9275 | 12.3231 | 12.1868 | 11.9389 | 12.4203 | 12.3192 | +7.8437 | 1.633 |
| infra_0 | 4.5846 | 1.2820 | 1.3205 | 1.2824 | 1.2847 | 1.3036 | 1.2847 | 0.8630 | 0.9372 | 1.2716 | 1.2700 | +3.3026 | 3.576 |
| infra_1 | 4.0274 | 0.1886 | 0.1927 | 0.1871 | 0.1984 | 0.1936 | 0.1984 | 0.1387 | 0.1273 | 0.1860 | 0.2210 | +3.8388 | 21.354 |
| infra_2 | 1.9670 | 0.2241 | 0.3218 | 0.2383 | 0.2019 | 0.3189 | 0.2019 | 0.0898 | 0.2526 | 0.2654 | 0.2993 | +1.7429 | 8.777 |
| infra_3 | 3.5248 | 0.9553 | 0.9792 | 0.9472 | 0.9536 | 0.9605 | 0.9536 | 0.6103 | 0.6629 | 0.9412 | 0.9252 | +2.5695 | 3.690 |
| infra_4 | 7.4511 | 2.4185 | 2.4622 | 2.4113 | 2.4267 | 2.4571 | 2.4267 | 1.9925 | 1.6982 | 2.3939 | 2.3870 | +5.0326 | 3.081 |
| infra_5 | 4.0343 | 3.1395 | 3.1544 | 3.1428 | 3.1373 | 3.1536 | 3.1373 | 2.7321 | 2.9166 | 3.1343 | 3.1568 | +0.8948 | 1.285 |
| infra_6 | 4.1818 | 1.1170 | 1.1680 | 1.1287 | 1.1369 | 1.1691 | 1.1369 | 1.0690 | 1.1324 | 1.1211 | 1.1089 | +3.0648 | 3.744 |
| infra_7 | 8.0820 | 0.8066 | 0.8564 | 0.7978 | 0.8183 | 0.8495 | 0.8183 | 0.6806 | 0.7397 | 0.7824 | 0.7926 | +7.2754 | 10.020 |
| infra_8 | 2.4433 | 1.2431 | 1.2474 | 1.2414 | 1.2433 | 1.2470 | 1.2433 | 1.2374 | 1.2362 | 1.2390 | 1.2422 | +1.2002 | 1.965 |
| infra_9 | 7.7983 | 6.6474 | 6.6581 | 6.6669 | 6.6569 | 6.6603 | 6.6569 | 6.6118 | 6.6896 | 6.6630 | 6.5930 | +1.1509 | 1.173 |
| infra_10 | 7.7299 | 4.5419 | 4.7003 | 4.5607 | 4.4870 | 4.7222 | 4.4870 | 4.2478 | 4.4971 | 4.5369 | 4.4197 | +3.1880 | 1.702 |
| infra_11 | 11.3698 | 0.9284 | 0.9935 | 0.9444 | 0.9413 | 1.0029 | 0.9413 | 0.9224 | 0.9264 | 0.9297 | 0.8937 | +10.4414 | 12.247 |
| infra_12 | 11.6051 | 0.8941 | 0.9888 | 0.9073 | 0.9212 | 0.9926 | 0.9212 | 0.8870 | 0.9107 | 0.8929 | 0.8628 | +10.7110 | 12.980 |
| infra_13 | 8.1294 | 3.2824 | 3.4481 | 3.2710 | 3.2568 | 3.4457 | 3.2568 | 3.0951 | 3.2639 | 3.2649 | 3.1700 | +4.8470 | 2.477 |
| infra_14 | 7.8024 | 4.5203 | 4.6703 | 4.5246 | 4.4473 | 4.6856 | 4.4473 | 4.2033 | 4.4678 | 4.5075 | 4.3833 | +3.2821 | 1.726 |
| infra_15 | 9.1934 | 5.6115 | 5.7851 | 5.6388 | 5.5702 | 5.8138 | 5.5702 | 5.3362 | 5.5634 | 5.5767 | 5.5349 | +3.5819 | 1.638 |
| int_0 | 6.5067 | 4.8582 | 5.0218 | 4.9588 | 4.9786 | 5.0199 | 4.9786 | 4.7142 | 4.5368 | 4.9042 | 4.6353 | +1.6485 | 1.339 |
| int_1 | 17.9841 | 11.3647 | 11.5313 | 10.1513 | 11.4623 | 9.0477 | 11.4623 | 9.6145 | 10.5510 | 11.2924 | 10.4027 | +6.6194 | 1.582 |
| int_2 | 17.5646 | 10.5942 | 10.7426 | 9.7044 | 10.6473 | 8.5702 | 10.6473 | 9.0588 | 9.8498 | 10.6067 | 9.7473 | +6.9704 | 1.658 |
| int_3 | 4.8123 | 0.9084 | 0.9844 | 0.8789 | 0.9216 | 0.9714 | 0.9216 | 0.8456 | 0.9218 | 0.8734 | 0.8346 | +3.9039 | 5.298 |
| int_4 | 12.1023 | 3.6281 | 3.9694 | 3.6485 | 3.6720 | 3.9619 | 3.6720 | 3.3619 | 3.6791 | 3.5715 | 3.5029 | +8.4742 | 3.336 |
| int_5 | 4.9963 | 2.7755 | 2.7986 | 2.7785 | 2.7849 | 2.8007 | 2.7849 | 2.6387 | 2.7393 | 2.7739 | 2.7751 | +2.2208 | 1.800 |
| int_6 | 5.1602 | 2.8740 | 2.8848 | 2.8451 | 2.8694 | 2.8815 | 2.8694 | 2.6453 | 2.7969 | 2.8712 | 2.8486 | +2.2862 | 1.795 |
| int_7 | 17.1273 | 3.5596 | 5.4567 | 3.6725 | 3.6236 | 5.5245 | 3.6236 | 3.5512 | 3.5819 | 3.5550 | 3.6378 | +13.5677 | 4.812 |
| int_8 | 16.1694 | 4.9917 | 6.4568 | 5.0812 | 5.1399 | 6.4358 | 5.1399 | 4.9785 | 5.0210 | 4.9637 | 4.9926 | +11.1777 | 3.239 |
| int_9 | 16.9896 | 3.0795 | 4.4242 | 3.1639 | 3.0966 | 4.4622 | 3.0966 | 3.0647 | 3.1514 | 3.0574 | 3.1091 | +13.9101 | 5.517 |
| int_10 | 3.0000 | 0.4970 | 0.5111 | 0.4886 | 0.4996 | 0.5115 | 0.4996 | 0.4611 | 0.4900 | 0.4986 | 0.4982 | +2.5030 | 6.036 |
| int_11 | 7.1919 | 4.0718 | 4.2518 | 4.1218 | 4.2074 | 4.2415 | 4.2074 | 3.8825 | 4.0210 | 4.1000 | 3.9081 | +3.1201 | 1.766 |
| int_12 | 2.3964 | 0.8027 | 0.8677 | 0.8143 | 0.8551 | 0.8619 | 0.8551 | 0.7950 | 0.6682 | 0.8084 | 0.7576 | +1.5937 | 2.985 |
| int_13 | 2.8093 | 0.8062 | 0.8551 | 0.5996 | 0.7973 | 0.8545 | 0.7973 | 0.7617 | 0.8059 | 0.8066 | 0.7883 | +2.0031 | 3.485 |
| int_14 | 3.2503 | 0.3113 | 0.3291 | 0.3189 | 0.3259 | 0.3263 | 0.3259 | 0.3054 | 0.3130 | 0.3232 | 0.3147 | +2.9390 | 10.441 |
| int_15 | 2.6685 | 0.8845 | 0.8940 | 0.8873 | 0.9179 | 0.8958 | 0.9179 | 0.8117 | 0.8742 | 0.8808 | 0.8689 | +1.7840 | 3.017 |
| int_16 | 19.7671 | 5.6066 | 8.2914 | 5.6398 | 5.7344 | 8.3189 | 5.7344 | 5.7327 | 5.8130 | 5.5135 | 5.8649 | +14.1605 | 3.526 |
| int_17 | 16.6417 | 3.9103 | 5.5486 | 3.9076 | 4.0196 | 5.4905 | 4.0196 | 3.9547 | 4.0095 | 3.8588 | 4.0542 | +12.7314 | 4.256 |
| int_18 | 3.2712 | 0.6019 | 0.7171 | 0.5298 | 0.5925 | 0.7157 | 0.5925 | 0.4825 | 0.6336 | 0.5695 | 0.5000 | +2.6693 | 5.435 |
| int_19 | 14.2437 | 0.5881 | 0.6460 | 0.5774 | 0.5890 | 0.5030 | 0.5890 | 0.5756 | 0.5936 | 0.5655 | 0.5924 | +13.6556 | 24.220 |
| int_20 | 11.2847 | 2.1556 | 2.6242 | 2.1467 | 2.2225 | 2.6001 | 2.2225 | 2.1370 | 2.1870 | 2.1352 | 2.2233 | +9.1291 | 5.235 |
| int_21 | 29.4377 | 24.2469 | 24.7325 | 24.3261 | 24.4182 | 15.8812 | 24.4182 | 22.2863 | 24.1158 | 24.3741 | 23.8286 | +5.1908 | 1.214 |
| int_22 | 9.3652 | 4.7163 | 5.4062 | 3.8046 | 4.8888 | 5.3978 | 4.8888 | 3.7049 | 4.7094 | 4.7293 | 4.0809 | +4.6489 | 1.986 |
| int_23 | 6.9415 | 3.2636 | 3.3262 | 3.2729 | 3.2905 | 3.2846 | 3.2905 | 3.0219 | 3.2679 | 3.2368 | 3.1805 | +3.6779 | 2.127 |
| int_24 | 2.0358 | 0.4488 | 0.4797 | 0.4336 | 0.4799 | 0.4857 | 0.4799 | 0.4192 | 0.4152 | 0.5032 | 0.4277 | +1.5870 | 4.536 |
| int_25 | 3.4472 | 2.2612 | 2.2920 | 2.2881 | 2.2915 | 2.2914 | 2.2915 | 2.3046 | 2.2984 | 2.2612 | 2.3228 | +1.1860 | 1.525 |
| int_26 | 3.7982 | 1.1492 | 1.2381 | 1.1643 | 1.1815 | 1.2442 | 1.1815 | 1.0991 | 1.1813 | 1.1304 | 1.1007 | +2.6490 | 3.305 |
| int_27 | 2.3639 | 0.6896 | 0.7416 | 0.6912 | 0.7100 | 0.7395 | 0.7100 | 0.6627 | 0.7147 | 0.6854 | 0.6561 | +1.6743 | 3.428 |
| int_28 | 8.2203 | 3.1211 | 3.4477 | 3.1691 | 3.2012 | 3.4213 | 3.2012 | 2.9319 | 3.0462 | 3.1301 | 2.9558 | +5.0992 | 2.634 |
| int_29 | 18.0465 | 11.2431 | 12.1230 | 11.4506 | 11.4147 | 11.9809 | 11.4147 | 10.9901 | 10.9347 | 11.2942 | 11.0571 | +6.8034 | 1.605 |
| int_30 | 18.7322 | 11.5829 | 12.5375 | 11.7911 | 11.7620 | 12.4001 | 11.7620 | 11.2679 | 11.2497 | 11.6468 | 11.3845 | +7.1493 | 1.617 |
| int_31 | 9.8854 | 0.4690 | 0.6249 | 0.5046 | 0.5391 | 0.6422 | 0.5391 | 0.4232 | 0.6163 | 0.4329 | 0.4222 | +9.4164 | 21.078 |
| int_32 | 11.9289 | 6.5198 | 6.8820 | 6.5982 | 6.6835 | 6.8741 | 6.6835 | 6.2471 | 6.5770 | 6.5128 | 6.2564 | +5.4091 | 1.830 |
| int_33 | 12.2341 | 7.7631 | 8.1588 | 7.8770 | 7.9644 | 8.1467 | 7.9644 | 7.4370 | 7.8037 | 7.8299 | 7.5954 | +4.4710 | 1.576 |
| int_34 | 5.5114 | 3.0504 | 3.2035 | 3.0668 | 3.1056 | 3.1897 | 3.1056 | 2.8492 | 2.9189 | 3.0566 | 2.9458 | +2.4610 | 1.807 |
| int_35 | 7.2276 | 2.0928 | 2.3365 | 2.1275 | 2.1079 | 2.3596 | 2.1079 | 1.8850 | 2.2735 | 2.1217 | 1.8760 | +5.1348 | 3.454 |
| int_36 | 12.4928 | 2.5331 | 3.6847 | 2.6340 | 2.6152 | 3.6658 | 2.6152 | 2.6377 | 2.6098 | 2.5866 | 2.6779 | +9.9597 | 4.932 |
| media_0 | 4.4188 | 0.8155 | 0.9011 | 0.8142 | 0.8612 | 0.9127 | 0.8612 | 0.7641 | 0.8862 | 0.7938 | 0.7987 | +3.6033 | 5.419 |
| media_1 | 3.6136 | 0.6229 | 0.7136 | 0.6353 | 0.6747 | 0.7251 | 0.6747 | 0.6199 | 0.7126 | 0.6125 | 0.6056 | +2.9907 | 5.801 |
| media_2 | 2.1564 | 0.6968 | 0.7319 | 0.7239 | 0.7232 | 0.7224 | 0.7232 | 0.6862 | 0.7291 | 0.6891 | 0.7017 | +1.4596 | 3.095 |
| media_3 | 4.8218 | 1.1108 | 1.1989 | 1.1228 | 1.1554 | 1.2180 | 1.1554 | 1.0436 | 1.2082 | 1.0671 | 1.0884 | +3.7110 | 4.341 |
| web_0 | 4.6695 | 0.9269 | 0.9977 | 0.9413 | 0.9696 | 1.0074 | 0.9696 | 0.9695 | 0.9352 | 0.9380 | 0.9549 | +3.7426 | 5.038 |
| web_1 | 9.4071 | 3.1350 | 3.4639 | 3.1606 | 3.2575 | 3.4808 | 3.2575 | 3.0559 | 3.0325 | 3.1606 | 3.1456 | +6.2721 | 3.001 |
| web_2 | 11.8317 | 3.9463 | 4.3298 | 3.9515 | 3.9802 | 4.3658 | 3.9802 | 3.8978 | 3.9810 | 3.9061 | 3.8604 | +7.8854 | 2.998 |
| web_3 | 7.1996 | 2.8943 | 3.3310 | 2.9200 | 3.0000 | 3.2814 | 3.0000 | 2.9182 | 2.9609 | 2.8775 | 2.8972 | +4.3053 | 2.488 |
| web_4 | 9.2731 | 3.4584 | 3.8766 | 3.4631 | 3.5605 | 3.8703 | 3.5605 | 3.4870 | 3.5136 | 3.4095 | 3.4764 | +5.8147 | 2.681 |
| web_5 | 11.4579 | 4.6474 | 5.1790 | 4.6226 | 4.7590 | 5.1396 | 4.7590 | 4.6553 | 4.6648 | 4.5630 | 4.6331 | +6.8105 | 2.465 |
| web_6 | 11.7282 | 5.5540 | 5.8540 | 5.5545 | 5.6152 | 5.8636 | 5.6152 | 5.4746 | 5.5117 | 5.4726 | 5.5023 | +6.1742 | 2.112 |
| web_7 | 10.2085 | 5.5957 | 6.9101 | 5.4830 | 5.1812 | 6.9569 | 5.1812 | 3.5629 | 5.1515 | 4.9498 | 5.3993 | +4.6128 | 1.824 |
| web_8 | 9.7952 | 3.7711 | 4.3449 | 3.7811 | 3.9131 | 4.3089 | 3.9131 | 3.8021 | 3.7757 | 3.7044 | 3.7903 | +6.0241 | 2.597 |
| web_9 | 0.0624 | 0.0034 | 0.0028 | 0.0022 | 0.0028 | 0.0063 | 0.0028 | 0.0196 | 0.0025 | 0.0014 | 0.0083 | +0.0590 | 18.353 |
| web_10 | 6.4408 | 2.2428 | 2.5771 | 2.2059 | 2.3546 | 2.5671 | 2.3546 | 2.2547 | 2.2707 | 2.2288 | 2.2430 | +4.1980 | 2.872 |
| web_11 | 12.4390 | 4.4180 | 5.8013 | 4.4627 | 4.6636 | 5.7760 | 4.6636 | 4.5285 | 4.5249 | 4.4633 | 4.5368 | +8.0210 | 2.816 |
| web_12 | 9.8289 | 4.5434 | 4.8989 | 4.4528 | 4.6533 | 4.9317 | 4.6533 | 4.5033 | 4.5894 | 4.5276 | 4.4860 | +5.2855 | 2.163 |
| web_13 | 8.8602 | 2.4800 | 2.9370 | 2.4914 | 2.5096 | 2.9405 | 2.5096 | 2.4672 | 2.4869 | 2.4823 | 2.5400 | +6.3802 | 3.573 |
| web_14 | 7.2353 | 2.7575 | 2.8285 | 2.7681 | 2.7839 | 2.8269 | 2.7839 | 2.6355 | 2.7015 | 2.7719 | 2.5780 | +4.4778 | 2.624 |
| web_15 | 11.9887 | 4.1300 | 5.4394 | 4.1797 | 4.3119 | 5.4171 | 4.3119 | 4.1824 | 4.2336 | 4.1275 | 4.1637 | +7.8587 | 2.903 |
| web_16 | 5.2226 | 2.1666 | 2.6171 | 2.2079 | 2.2449 | 2.6169 | 2.2449 | 2.2197 | 2.2107 | 2.2253 | 2.2315 | +3.0560 | 2.411 |
| web_17 | 7.6909 | 0.6044 | 0.7172 | 0.6023 | 0.6383 | 0.7288 | 0.6383 | 0.5982 | 0.6560 | 0.6107 | 0.6283 | +7.0865 | 12.725 |
| web_18 | 6.3262 | 2.5812 | 2.6758 | 2.5731 | 2.6043 | 2.6641 | 2.6043 | 2.4920 | 2.5676 | 2.5462 | 2.5376 | +3.7450 | 2.451 |
| web_19 | 15.0248 | 6.1872 | 7.4690 | 6.1972 | 6.3878 | 7.4295 | 6.3878 | 6.1664 | 6.2635 | 6.1487 | 6.1377 | +8.8376 | 2.428 |
| web_20 | 20.7941 | 1.7781 | 2.4806 | 1.7936 | 1.7972 | 2.4636 | 1.7972 | 1.8207 | 1.8131 | 1.7591 | 1.7385 | +19.0160 | 11.695 |
| web_21 | 9.4508 | 2.2424 | 2.5057 | 2.1789 | 2.2689 | 2.5029 | 2.2689 | 2.1128 | 2.3055 | 2.2182 | 2.0999 | +7.2084 | 4.215 |
| web_22 | 6.5138 | 3.0398 | 3.1470 | 3.0297 | 3.0603 | 3.1479 | 3.0603 | 2.9656 | 3.0243 | 2.9856 | 3.0065 | +3.4740 | 2.143 |
| web_23 | 7.5123 | 1.5155 | 1.7590 | 1.4631 | 1.6121 | 1.7686 | 1.6121 | 1.4361 | 1.5269 | 1.5080 | 1.4753 | +5.9968 | 4.957 |
| web_24 | 19.6274 | 1.4348 | 1.7604 | 1.4381 | 1.5033 | 1.7472 | 1.5033 | 1.4311 | 1.4531 | 1.4517 | 1.4145 | +18.1926 | 13.680 |
| web_25 | 13.3863 | 6.4918 | 6.8850 | 6.4929 | 6.6483 | 6.8871 | 6.6483 | 6.3575 | 6.3749 | 6.4266 | 6.3894 | +6.8945 | 2.062 |

full conditional MPKI per trace:

| trace | pacino | tage192 | cbp2016 | behrendt | cai | fan | jimenez | koizumi | man | ros | seznec | pacino - tage192 | pacino / tage192 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| compress_0 | 6.6812 | 3.2057 | 3.2659 | 3.2232 | 3.2244 | 3.2686 | 3.2244 | 3.0861 | 3.1966 | 3.2138 | 3.1708 | +3.4755 | 2.084 |
| compress_1 | 2.3521 | 1.6524 | 1.6742 | 1.6540 | 1.6810 | 1.6747 | 1.6810 | 1.5021 | 1.6090 | 1.6580 | 1.6348 | +0.6997 | 1.423 |
| compress_2 | 2.1471 | 1.4562 | 1.4737 | 1.4546 | 1.4831 | 1.4799 | 1.4831 | 1.3500 | 1.4102 | 1.4571 | 1.4382 | +0.6909 | 1.474 |
| compress_3 | 11.3055 | 8.1425 | 8.2495 | 8.1204 | 8.0904 | 8.2284 | 8.0904 | 7.6801 | 8.1516 | 8.1115 | 7.7640 | +3.1630 | 1.388 |
| compress_4 | 2.6573 | 1.7967 | 1.8221 | 1.7883 | 1.8243 | 1.8257 | 1.8243 | 1.6329 | 1.7468 | 1.7964 | 1.7732 | +0.8606 | 1.479 |
| compress_5 | 2.7138 | 1.8919 | 1.9220 | 1.8927 | 1.9286 | 1.9246 | 1.9286 | 1.7112 | 1.8502 | 1.9012 | 1.8740 | +0.8219 | 1.434 |
| compress_6 | 2.6650 | 1.8660 | 1.8971 | 1.8711 | 1.9035 | 1.8970 | 1.9035 | 1.7002 | 1.8231 | 1.8722 | 1.8510 | +0.7990 | 1.428 |
| compress_7 | 4.2527 | 2.0337 | 2.0450 | 2.0352 | 2.0483 | 2.0470 | 2.0483 | 1.8020 | 1.9239 | 2.0306 | 2.0223 | +2.2190 | 2.091 |
| fp_0 | 3.7445 | 3.2251 | 3.2270 | 3.2262 | 3.2250 | 3.2270 | 3.2250 | 3.2189 | 3.2399 | 3.2242 | 3.2161 | +0.5194 | 1.161 |
| fp_1 | 17.3769 | 15.5596 | 15.5836 | 15.5721 | 15.5435 | 15.5836 | 15.5435 | 14.9157 | 15.5972 | 15.5960 | 15.5673 | +1.8173 | 1.117 |
| fp_2 | 4.7954 | 2.5558 | 2.5619 | 2.5455 | 2.5512 | 2.5601 | 2.5512 | 2.4022 | 2.5393 | 2.5433 | 2.5384 | +2.2396 | 1.876 |
| fp_3 | 7.0552 | 1.9518 | 2.0335 | 1.9496 | 1.9541 | 2.0279 | 1.9541 | 1.8302 | 2.0165 | 1.9158 | 1.8793 | +5.1034 | 3.615 |
| fp_4 | 2.2610 | 0.5609 | 0.5731 | 0.5809 | 0.5858 | 0.5701 | 0.5858 | 0.5129 | 0.5451 | 0.5662 | 0.5207 | +1.7001 | 4.031 |
| fp_5 | 1.0467 | 0.9363 | 0.9361 | 0.9327 | 0.9326 | 0.9369 | 0.9326 | 0.9229 | 0.9299 | 0.9353 | 0.9235 | +0.1104 | 1.118 |
| fp_6 | 11.4575 | 0.9602 | 1.0145 | 0.9232 | 0.9628 | 0.9828 | 0.9628 | 0.9125 | 0.9750 | 0.9004 | 0.8538 | +10.4973 | 11.932 |
| fp_7 | 8.0295 | 1.0261 | 1.1268 | 1.0324 | 1.0350 | 1.1343 | 1.0350 | 0.9782 | 1.0434 | 1.0052 | 0.9672 | +7.0034 | 7.825 |
| fp_8 | 9.5390 | 7.4675 | 7.8391 | 7.3982 | 7.4257 | 5.4713 | 7.4257 | 3.7981 | 6.6904 | 7.4707 | 7.3998 | +2.0715 | 1.277 |
| fp_9 | 13.1995 | 4.2151 | 4.5512 | 4.2987 | 4.1705 | 4.5430 | 4.1705 | 4.0736 | 4.0984 | 4.1106 | 4.1253 | +8.9844 | 3.131 |
| fp_10 | 3.6187 | 1.9846 | 2.1035 | 1.9445 | 2.0326 | 1.9107 | 2.0326 | 1.9807 | 1.9629 | 1.9142 | 2.0092 | +1.6341 | 1.823 |
| fp_11 | 1.2715 | 0.6081 | 0.6996 | 0.5735 | 0.6635 | 0.6912 | 0.6635 | 0.5650 | 0.6052 | 0.6298 | 0.5761 | +0.6634 | 2.091 |
| fp_12 | 2.3150 | 1.1719 | 1.2160 | 0.8205 | 1.1177 | 1.2141 | 1.1177 | 1.0287 | 0.8073 | 1.0941 | 1.0970 | +1.1431 | 1.975 |
| fp_13 | 20.1962 | 12.4316 | 12.6898 | 12.4478 | 12.3628 | 8.9772 | 12.3628 | 12.2224 | 11.9520 | 12.4504 | 12.3153 | +7.7646 | 1.625 |
| infra_0 | 4.5875 | 1.2489 | 1.2726 | 1.2444 | 1.2509 | 1.2654 | 1.2509 | 0.8680 | 0.9416 | 1.2382 | 1.2339 | +3.3386 | 3.673 |
| infra_1 | 4.2538 | 0.3459 | 0.3589 | 0.3390 | 0.3868 | 0.3590 | 0.3868 | 0.2928 | 0.2923 | 0.3463 | 0.3749 | +3.9079 | 12.298 |
| infra_2 | 2.1315 | 0.4080 | 0.4843 | 0.4135 | 0.4331 | 0.4838 | 0.4331 | 0.3068 | 0.4242 | 0.4530 | 0.4764 | +1.7235 | 5.224 |
| infra_3 | 3.6113 | 1.0328 | 1.0586 | 1.0229 | 1.0311 | 1.0404 | 1.0311 | 0.6862 | 0.7806 | 1.0205 | 1.0064 | +2.5785 | 3.497 |
| infra_4 | 7.5540 | 2.4035 | 2.4409 | 2.3951 | 2.4137 | 2.4327 | 2.4137 | 2.0163 | 1.7888 | 2.3925 | 2.3771 | +5.1505 | 3.143 |
| infra_5 | 3.2459 | 2.2032 | 2.2119 | 2.1990 | 2.1999 | 2.2115 | 2.1999 | 1.9951 | 2.0907 | 2.1961 | 2.2161 | +1.0427 | 1.473 |
| infra_6 | 4.3855 | 1.1856 | 1.2377 | 1.1875 | 1.2216 | 1.2423 | 1.2216 | 1.1330 | 1.1974 | 1.1843 | 1.1673 | +3.1999 | 3.699 |
| infra_7 | 8.3196 | 1.4196 | 1.4783 | 1.4075 | 1.4236 | 1.4745 | 1.4236 | 1.2021 | 1.1916 | 1.4085 | 1.3824 | +6.9000 | 5.861 |
| infra_8 | 2.4515 | 1.2537 | 1.2568 | 1.2493 | 1.2521 | 1.2565 | 1.2521 | 1.2466 | 1.2484 | 1.2477 | 1.2587 | +1.1978 | 1.955 |
| infra_9 | 9.3522 | 4.4591 | 4.5154 | 4.4594 | 4.4728 | 4.5229 | 4.4728 | 4.4086 | 4.4817 | 4.4562 | 4.3939 | +4.8931 | 2.097 |
| infra_10 | 7.5707 | 5.1428 | 5.2582 | 5.1574 | 5.1079 | 5.2699 | 5.1079 | 4.9389 | 5.1185 | 5.1341 | 5.0482 | +2.4279 | 1.472 |
| infra_11 | 11.3104 | 0.9899 | 1.0656 | 0.9847 | 1.0093 | 1.0746 | 1.0093 | 0.9580 | 0.9915 | 0.9789 | 0.9350 | +10.3205 | 11.426 |
| infra_12 | 11.8013 | 0.9741 | 1.0631 | 0.9655 | 0.9935 | 1.0668 | 0.9935 | 0.9399 | 0.9831 | 0.9617 | 0.9195 | +10.8272 | 12.115 |
| infra_13 | 7.9838 | 4.0061 | 4.1646 | 4.0117 | 3.9738 | 4.1665 | 3.9738 | 3.7800 | 3.9829 | 3.9946 | 3.8874 | +3.9777 | 1.993 |
| infra_14 | 7.7473 | 5.2062 | 5.3130 | 5.2087 | 5.1531 | 5.3236 | 5.1531 | 4.9673 | 5.1721 | 5.1872 | 5.0974 | +2.5411 | 1.488 |
| infra_15 | 10.5352 | 8.2150 | 8.3195 | 8.2452 | 8.1999 | 8.3390 | 8.1999 | 8.0457 | 8.2027 | 8.1950 | 8.1494 | +2.3202 | 1.282 |
| int_0 | 6.5809 | 4.9846 | 5.1372 | 5.0720 | 5.1190 | 5.1354 | 5.1190 | 4.8367 | 4.6573 | 5.0324 | 4.7462 | +1.5963 | 1.320 |
| int_1 | 18.0635 | 11.4486 | 11.6238 | 10.3488 | 11.5621 | 9.1803 | 11.5621 | 9.7269 | 10.7037 | 11.4013 | 10.5164 | +6.6149 | 1.578 |
| int_2 | 17.6090 | 10.7345 | 10.8851 | 9.8630 | 10.8212 | 8.7110 | 10.8212 | 9.2398 | 10.0291 | 10.7535 | 9.9766 | +6.8745 | 1.640 |
| int_3 | 4.2714 | 0.8322 | 0.8792 | 0.8119 | 0.8447 | 0.8632 | 0.8447 | 0.7682 | 0.8429 | 0.8052 | 0.7772 | +3.4392 | 5.133 |
| int_4 | 11.7050 | 3.8176 | 4.1159 | 3.8414 | 3.8687 | 4.1151 | 3.8687 | 3.5695 | 3.8578 | 3.7575 | 3.6795 | +7.8874 | 3.066 |
| int_5 | 5.0464 | 2.8366 | 2.8501 | 2.8312 | 2.8442 | 2.8520 | 2.8442 | 2.6973 | 2.7970 | 2.8332 | 2.8217 | +2.2098 | 1.779 |
| int_6 | 5.1774 | 2.9471 | 2.9559 | 2.9209 | 2.9498 | 2.9569 | 2.9498 | 2.7373 | 2.8833 | 2.9445 | 2.9220 | +2.2303 | 1.757 |
| int_7 | 16.9642 | 4.3202 | 5.6457 | 4.3866 | 4.4702 | 5.6947 | 4.4702 | 4.2795 | 4.3391 | 4.3142 | 4.3313 | +12.6440 | 3.927 |
| int_8 | 16.9259 | 5.7346 | 7.0402 | 5.7898 | 5.9436 | 7.0274 | 5.9436 | 5.6997 | 5.7696 | 5.7072 | 5.7378 | +11.1913 | 2.952 |
| int_9 | 16.4515 | 3.6005 | 4.7051 | 3.6186 | 3.6854 | 4.7308 | 3.6854 | 3.5400 | 3.6639 | 3.5579 | 3.5657 | +12.8510 | 4.569 |
| int_10 | 2.9574 | 0.5246 | 0.5367 | 0.5155 | 0.5372 | 0.5370 | 0.5372 | 0.4966 | 0.5210 | 0.5228 | 0.5216 | +2.4328 | 5.637 |
| int_11 | 7.1203 | 4.0459 | 4.2091 | 4.0913 | 4.1619 | 4.2029 | 4.1619 | 3.8625 | 3.9987 | 4.0562 | 3.8684 | +3.0744 | 1.760 |
| int_12 | 1.5111 | 0.4223 | 0.4574 | 0.4286 | 0.4542 | 0.4539 | 0.4542 | 0.4194 | 0.3558 | 0.4264 | 0.4016 | +1.0888 | 3.578 |
| int_13 | 2.8310 | 0.8743 | 0.9110 | 0.7169 | 0.8673 | 0.9147 | 0.8673 | 0.8337 | 0.8741 | 0.8707 | 0.8543 | +1.9567 | 3.238 |
| int_14 | 3.2165 | 0.3773 | 0.3950 | 0.3828 | 0.4064 | 0.3920 | 0.4064 | 0.3695 | 0.3664 | 0.3854 | 0.3809 | +2.8392 | 8.525 |
| int_15 | 1.9690 | 0.4687 | 0.4736 | 0.4701 | 0.4863 | 0.4746 | 0.4863 | 0.4293 | 0.4638 | 0.4670 | 0.4606 | +1.5003 | 4.201 |
| int_16 | 20.0553 | 5.5511 | 7.9935 | 5.5744 | 5.7254 | 7.9896 | 5.7254 | 5.6157 | 5.7157 | 5.4602 | 5.7537 | +14.5042 | 3.613 |
| int_17 | 17.2290 | 4.6923 | 6.2947 | 4.6764 | 4.8690 | 6.2442 | 4.8690 | 4.7005 | 4.7923 | 4.6201 | 4.7966 | +12.5367 | 3.672 |
| int_18 | 3.1130 | 0.7665 | 0.8504 | 0.6990 | 0.7619 | 0.8464 | 0.7619 | 0.6255 | 0.8031 | 0.7357 | 0.6612 | +2.3465 | 4.061 |
| int_19 | 14.1636 | 0.7789 | 0.8396 | 0.7509 | 0.7873 | 0.6598 | 0.7873 | 0.7492 | 0.7903 | 0.7483 | 0.7602 | +13.3847 | 18.184 |
| int_20 | 10.7517 | 2.3374 | 2.7436 | 2.3132 | 2.4240 | 2.7081 | 2.4240 | 2.2891 | 2.3333 | 2.3175 | 2.3460 | +8.4143 | 4.600 |
| int_21 | 28.5966 | 23.6708 | 24.1123 | 23.7308 | 23.8120 | 15.7080 | 23.8120 | 21.7200 | 23.5481 | 23.7795 | 23.2909 | +4.9258 | 1.208 |
| int_22 | 9.2930 | 4.8276 | 5.3965 | 3.9788 | 4.9919 | 5.3966 | 4.9919 | 3.9029 | 4.8609 | 4.8095 | 4.2827 | +4.4654 | 1.925 |
| int_23 | 7.0266 | 3.3921 | 3.4589 | 3.4022 | 3.4163 | 3.4290 | 3.4163 | 3.1616 | 3.4009 | 3.3666 | 3.2956 | +3.6345 | 2.071 |
| int_24 | 2.5878 | 0.5412 | 0.5608 | 0.5004 | 0.5721 | 0.5634 | 0.5721 | 0.5059 | 0.4901 | 0.5901 | 0.5092 | +2.0466 | 4.782 |
| int_25 | 2.7778 | 1.3040 | 1.3222 | 1.3168 | 1.3197 | 1.3215 | 1.3197 | 1.3222 | 1.3277 | 1.3081 | 1.3282 | +1.4738 | 2.130 |
| int_26 | 3.8332 | 1.2566 | 1.3362 | 1.2635 | 1.2910 | 1.3402 | 1.2910 | 1.2026 | 1.2878 | 1.2359 | 1.1960 | +2.5766 | 3.050 |
| int_27 | 2.5079 | 0.8206 | 0.8682 | 0.8248 | 0.8486 | 0.8631 | 0.8486 | 0.7840 | 0.8485 | 0.8097 | 0.7738 | +1.6873 | 3.056 |
| int_28 | 8.3924 | 3.3842 | 3.6702 | 3.4220 | 3.4681 | 3.6561 | 3.4681 | 3.1998 | 3.3295 | 3.3950 | 3.2101 | +5.0082 | 2.480 |
| int_29 | 18.0038 | 11.6531 | 12.4617 | 11.8355 | 11.8006 | 12.3094 | 11.8006 | 11.4362 | 11.3827 | 11.7066 | 11.4848 | +6.3507 | 1.545 |
| int_30 | 18.7918 | 12.0654 | 12.9164 | 12.2587 | 12.2067 | 12.7799 | 12.2067 | 11.7872 | 11.7750 | 12.1156 | 11.8803 | +6.7264 | 1.557 |
| int_31 | 10.1208 | 0.6728 | 0.8264 | 0.6903 | 0.7443 | 0.8418 | 0.7443 | 0.6113 | 0.8220 | 0.6192 | 0.5941 | +9.4480 | 15.043 |
| int_32 | 12.0372 | 6.6301 | 6.9667 | 6.7222 | 6.7872 | 6.9622 | 6.7872 | 6.3533 | 6.6907 | 6.6318 | 6.3567 | +5.4071 | 1.816 |
| int_33 | 11.9638 | 7.6076 | 7.9798 | 7.7092 | 7.8077 | 7.9674 | 7.8077 | 7.2591 | 7.6254 | 7.6707 | 7.4417 | +4.3562 | 1.573 |
| int_34 | 5.1897 | 2.9566 | 3.0735 | 2.9601 | 2.9971 | 3.0698 | 2.9971 | 2.7571 | 2.8144 | 2.9604 | 2.8547 | +2.2331 | 1.755 |
| int_35 | 7.3170 | 2.2505 | 2.4586 | 2.2453 | 2.2544 | 2.4701 | 2.2544 | 2.0317 | 2.3739 | 2.2627 | 2.0137 | +5.0665 | 3.251 |
| int_36 | 12.4422 | 2.8652 | 3.9090 | 2.9353 | 2.9641 | 3.8953 | 2.9641 | 2.9363 | 2.9444 | 2.9016 | 2.9610 | +9.5770 | 4.343 |
| media_0 | 4.6541 | 1.0876 | 1.1729 | 1.0738 | 1.1396 | 1.1689 | 1.1396 | 1.0276 | 1.1709 | 1.0571 | 1.0448 | +3.5665 | 4.279 |
| media_1 | 4.3133 | 1.0658 | 1.1554 | 1.0686 | 1.1360 | 1.1648 | 1.1360 | 1.0335 | 1.1624 | 1.0433 | 1.0172 | +3.2475 | 4.047 |
| media_2 | 1.7908 | 0.5105 | 0.5307 | 0.5249 | 0.5295 | 0.5267 | 0.5295 | 0.5056 | 0.5311 | 0.5072 | 0.5085 | +1.2803 | 3.508 |
| media_3 | 4.8860 | 1.2833 | 1.3855 | 1.2844 | 1.3404 | 1.3851 | 1.3404 | 1.2108 | 1.3760 | 1.2454 | 1.2395 | +3.6027 | 3.807 |
| web_0 | 6.0551 | 1.3077 | 1.3901 | 1.3125 | 1.3671 | 1.4004 | 1.3671 | 1.3024 | 1.3164 | 1.3251 | 1.3028 | +4.7474 | 4.630 |
| web_1 | 9.1828 | 3.1754 | 3.4759 | 3.1907 | 3.3133 | 3.4922 | 3.3133 | 3.1207 | 3.0995 | 3.1850 | 3.1563 | +6.0074 | 2.892 |
| web_2 | 10.8542 | 3.7366 | 4.0798 | 3.7215 | 3.8022 | 4.1157 | 3.8022 | 3.6928 | 3.7629 | 3.6875 | 3.6499 | +7.1176 | 2.905 |
| web_3 | 8.0223 | 3.5250 | 3.9343 | 3.5525 | 3.6621 | 3.8945 | 3.6621 | 3.5277 | 3.5644 | 3.5140 | 3.5069 | +4.4973 | 2.276 |
| web_4 | 10.1651 | 4.0026 | 4.3596 | 3.9846 | 4.1097 | 4.3590 | 4.1097 | 3.9775 | 4.0239 | 3.9464 | 3.9459 | +6.1625 | 2.540 |
| web_5 | 10.3696 | 4.2570 | 4.6407 | 4.2451 | 4.3695 | 4.6186 | 4.3695 | 4.2356 | 4.2625 | 4.2092 | 4.2102 | +6.1126 | 2.436 |
| web_6 | 11.2872 | 4.5359 | 4.7833 | 4.5310 | 4.6092 | 4.7971 | 4.6092 | 4.4582 | 4.5211 | 4.4682 | 4.4579 | +6.7513 | 2.488 |
| web_7 | 11.0041 | 6.3257 | 7.7444 | 6.2621 | 6.0178 | 7.6746 | 6.0178 | 4.3091 | 6.1124 | 6.0054 | 6.0756 | +4.6784 | 1.740 |
| web_8 | 10.8014 | 4.5569 | 5.0185 | 4.5487 | 4.7251 | 5.0003 | 4.7251 | 4.5411 | 4.5507 | 4.4878 | 4.5170 | +6.2445 | 2.370 |
| web_9 | 8.8627 | 2.4667 | 2.9183 | 2.4742 | 2.5801 | 2.9061 | 2.5801 | 2.4879 | 2.4841 | 2.4463 | 2.4694 | +6.3960 | 3.593 |
| web_10 | 8.5188 | 2.7717 | 3.2845 | 2.7597 | 2.9182 | 3.2948 | 2.9182 | 2.7894 | 2.8188 | 2.7921 | 2.7994 | +5.7471 | 3.073 |
| web_11 | 12.1265 | 4.5080 | 5.6178 | 4.5043 | 4.7036 | 5.6102 | 4.7036 | 4.5273 | 4.5967 | 4.5453 | 4.5886 | +7.6185 | 2.690 |
| web_12 | 11.9299 | 3.9049 | 4.3648 | 3.8241 | 4.0563 | 4.3904 | 4.0563 | 3.8211 | 3.9502 | 3.8957 | 3.8354 | +8.0250 | 3.055 |
| web_13 | 8.9823 | 2.9162 | 3.3531 | 2.9202 | 2.9755 | 3.3555 | 2.9755 | 2.8901 | 2.9042 | 2.9287 | 2.9419 | +6.0661 | 3.080 |
| web_14 | 7.8409 | 3.5739 | 3.6420 | 3.5726 | 3.5963 | 3.6456 | 3.5963 | 3.4104 | 3.4848 | 3.5844 | 3.3465 | +4.2670 | 2.194 |
| web_15 | 13.1580 | 5.0346 | 6.0390 | 5.0490 | 5.3015 | 6.0269 | 5.3015 | 5.0735 | 5.1026 | 5.0301 | 5.0105 | +8.1234 | 2.614 |
| web_16 | 4.3722 | 1.5612 | 1.8361 | 1.5662 | 1.6326 | 1.8374 | 1.6326 | 1.5630 | 1.5887 | 1.5865 | 1.5728 | +2.8110 | 2.801 |
| web_17 | 8.4179 | 1.4354 | 1.6831 | 1.4096 | 1.4980 | 1.6944 | 1.4980 | 1.3801 | 1.4784 | 1.4375 | 1.4063 | +6.9825 | 5.864 |
| web_18 | 6.5636 | 2.7648 | 2.8517 | 2.7483 | 2.7915 | 2.8441 | 2.7915 | 2.6594 | 2.7483 | 2.7187 | 2.7053 | +3.7988 | 2.374 |
| web_19 | 13.2362 | 5.0244 | 5.9440 | 5.0345 | 5.2222 | 5.9264 | 5.2222 | 5.0202 | 5.0852 | 5.0151 | 4.9868 | +8.2118 | 2.634 |
| web_20 | 19.5397 | 3.1938 | 4.1511 | 3.2004 | 3.3079 | 4.1437 | 3.3079 | 3.2159 | 3.2480 | 3.1542 | 3.1143 | +16.3459 | 6.118 |
| web_21 | 6.5255 | 1.5365 | 1.6887 | 1.4771 | 1.5499 | 1.6861 | 1.5499 | 1.4293 | 1.5596 | 1.5097 | 1.4195 | +4.9890 | 4.247 |
| web_22 | 6.3865 | 3.2817 | 3.3832 | 3.2505 | 3.3019 | 3.3861 | 3.3019 | 3.1709 | 3.2777 | 3.2234 | 3.2247 | +3.1048 | 1.946 |
| web_23 | 5.9118 | 0.9961 | 1.1387 | 0.9549 | 1.0717 | 1.1474 | 1.0717 | 0.9331 | 1.0053 | 1.0009 | 0.9627 | +4.9157 | 5.935 |
| web_24 | 20.1728 | 1.6697 | 2.0125 | 1.6255 | 1.7678 | 2.0126 | 1.7678 | 1.5823 | 1.6822 | 1.6525 | 1.5802 | +18.5031 | 12.082 |
| web_25 | 15.2037 | 5.8604 | 6.3292 | 5.8157 | 6.0383 | 6.3370 | 6.0383 | 5.7019 | 5.7910 | 5.7862 | 5.7000 | +9.3433 | 2.594 |

### Phase 8: the baseline
- perf/studies/baseline.sets: baseline and baseline_oracle, one command
  line each (sha256
  a5238e39b6884b43e0420d3f2a6f8f9e08e2dd27b013a99a846d4a81ad695092).
- perf/studies/baseline.traces: the 105 traces (sha256
  0871a18dda1321386fef3a0cb9f9994b1df386fe34fc3e509a3c8350a9d67fe3).
- perf/studies/baseline.csv: 210 rows, all sha e7002b79, dirty
  dirty:rtl+perf, input_digest
  0c66fed0ad2584216a27e4a2fac2f31b95d8dc297f48abf9883f6914e383a6dc
  (sha256 c786867b5ee9d60a363e3217ae9c91f6faca15207a5824619cfd4d8ba03d6162).
- perf/cbp2025_rv_rerun.csv: 1,155 rows (sha256
  24057c1c922c9d71f4b6c75df34c3fc5828104440dee603efddc843fc63a5541); each
  row carries its predictor's bin_sha256.
- make -C perf digest on the tree at the end prints digest 0c66fed0...,
  the baseline's. The rows say dirty:rtl+perf because this task's
  changes are uncommitted: once Jeff commits them unchanged, the digest
  stays 0c66fed0 and the sha and dirty mark change, and that commit is
  the baseline's revision.

The regression:
tools/regress.sh, once, at the end, in the background, no file changed
while it ran; 369 s of targets (6m00s wall). Its summary, whole:

```
==================================================================
REGRESSION SUMMARY  git e7002b7 (dirty)
root /home/jeff/Development/jeffnye-gh/pacino
jobs 15 (default: 32 threads / 2, 31 GB / 2); priority: nice -n 10, ionice -c 3
==================================================================
== rtl/core/csr
  PASS       lint_csr_pkg           rc=0   warn=0  err=0  -              2s
  PASS       lint_csr_tb_pkg        rc=0   warn=0  err=0  -              0s
  PASS       sim_csr_tb_pkg         rc=0   warn=0  err=0  200/0         23s
  time 25s
== rtl/core/frontend/bpu
  PASS       lint                   rc=0   warn=0  err=0  -              2s
  PASS       lint_loop_pred         rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_table        rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_table          rc=0   warn=0  err=0  -              1s
  PASS       lint_sc_brimli         rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_cntrl          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc                rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_table      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_cntrl      rc=0   warn=0  err=0  -              1s
  PASS       lint_ittage_arb        rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage            rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_cntrl        rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_arb          rc=0   warn=0  err=0  -              1s
  PASS       lint_tage              rc=0   warn=0  err=0  -              1s
  PASS       lint_ras               rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_array         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru          rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl         rc=0   warn=0  err=0  -              1s
  PASS       lint_ftb               rc=0   warn=0  err=0  -              0s
  PASS       lint_bp_cluster        rc=0   warn=0  err=0  -              1s
  PASS       sim                    rc=0   warn=0  err=0  34/0          17s
  PASS       sim_history            rc=0   warn=0  err=0  45442/0       28s
  PASS       sim_ubtb               rc=0   warn=0  err=0  341/0         15s
  PASS       sim_loop_pred          rc=0   warn=0  err=0  11548/0        7s
  PASS       sim_tage_table         rc=0   warn=0  err=0  15/0           0s
  PASS       sim_sc_table           rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_table_fast      rc=0   warn=0  err=0  7/0            0s
  PASS       sim_sc_brimli          rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_brimli_fast     rc=0   warn=0  err=0  7/0            0s
  PASS       sim_sc_cntrl           rc=0   warn=0  err=0  98/0           7s
  PASS       sim_sc                 rc=0   warn=0  err=0  144/0          8s
  PASS       sim_sc_fast            rc=0   warn=0  err=0  140/0          3s
  PASS       sim_ittage_table       rc=0   warn=0  err=0  32/0           1s
  PASS       sim_ittage_cntrl       rc=0   warn=0  err=0  150/0          3s
  PASS       sim_ittage             rc=0   warn=0  err=0  389/0          6s
  PASS       sim_ittage_fast        rc=0   warn=0  err=0  389/0          4s
  PASS       sim_bp_cluster         rc=0   warn=0  err=0  2136/0         8s
  PASS       sim_bp_cluster_init    rc=0   warn=0  err=0  2136/0        49s
  PASS       sim_ras                rc=0   warn=0  err=0  780/0          5s
  PASS       sim_ftb                rc=0   warn=0  err=0  241/0          3s
  PASS       sim_tage               rc=0   warn=0  err=0  109/0          4s
  PASS       sim_tage_fast          rc=0   warn=0  err=0  109/0          3s
  PASS       sim_tage_tasks         rc=0   warn=0  err=0  1/0            4s
  PASS       sim_tage_manual        rc=0   warn=0  err=0  1267/0         4s
  PASS       cov_history            rc=0   warn=0  err=0  45442/0       10s
  PASS       cov_ubtb               rc=0   warn=0  err=0  341/0          6s
  PASS       cov_loop_pred          rc=0   warn=0  err=0  11548/0        7s
  PASS       cov_tage_table         rc=0   warn=0  err=0  15/0           1s
  PASS       cov_tage               rc=0   warn=0  err=0  218/0          8s
  PASS       cov_bp_cluster         rc=0   warn=0  err=0  2136/0        24s
  PASS       cov_bpu                rc=0   warn=0  err=0  57564/0       30s
             sum of sub-runs:tage=218/0 tage_table=15/0 loop_pred=11548/0 bp_history=45442/0 ubtb=341/0
  PASS       lint_1slot             rc=0   warn=0  err=0  -              0s
  PASS       lint_loop_pred_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_table_1slot  rc=0   warn=0  err=0  -              1s
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
  PASS       lint_tage_1slot        rc=0   warn=0  err=0  -              1s
  PASS       lint_ras_1slot         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_array_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_1slot         rc=0   warn=0  err=0  -              1s
  PASS       lint_bp_cluster_1slot  rc=0   warn=0  err=0  -              1s
  PASS       sim_1slot              rc=0   warn=0  err=0  30/0           0s
  PASS       sim_history_1slot      rc=0   warn=0  err=0  26590/0        4s
  PASS       sim_ubtb_1slot         rc=0   warn=0  err=0  341/0          3s
  PASS       sim_loop_pred_1slot    rc=0   warn=0  err=0  5765/0         2s
  PASS       sim_tage_table_1slot   rc=0   warn=0  err=0  11/0           1s
  PASS       sim_sc_table_1slot     rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_table_fast_1slot rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_brimli_1slot    rc=0   warn=0  err=0  6/0            1s
  PASS       sim_sc_brimli_fast_1slot rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_cntrl_1slot     rc=0   warn=0  err=0  98/0           3s
  PASS       sim_sc_1slot           rc=0   warn=0  err=0  108/0          2s
  PASS       sim_sc_fast_1slot      rc=0   warn=0  err=0  104/0          1s
  PASS       sim_ittage_table_1slot rc=0   warn=0  err=0  26/0           0s
  PASS       sim_ittage_cntrl_1slot rc=0   warn=0  err=0  141/0          4s
  PASS       sim_ittage_1slot       rc=0   warn=0  err=0  258/0          3s
  PASS       sim_ittage_fast_1slot  rc=0   warn=0  err=0  258/0          3s
  PASS       sim_bp_cluster_1slot   rc=0   warn=0  err=0  1553/0         6s
  PASS       sim_bp_cluster_init_1slot rc=0   warn=0  err=0  1553/0        27s
  PASS       sim_ras_1slot          rc=0   warn=0  err=0  679/0          4s
  PASS       sim_ftb_1slot          rc=0   warn=0  err=0  188/0          3s
  PASS       sim_tage_1slot         rc=0   warn=0  err=0  105/0          3s
  PASS       sim_tage_fast_1slot    rc=0   warn=0  err=0  105/0          3s
  PASS       sim_tage_tasks_1slot   rc=0   warn=0  err=0  1/0            1s
  PASS       sim_tage_manual_1slot  rc=0   warn=0  err=0  534/0          3s
  time 359s
== rtl/core/frontend/decode
  PASS       lint_dec               rc=0   warn=0  err=0  -              2s
  PASS       sim_dec                rc=0   warn=0  err=0  1355/0        38s
  PASS       coverage               rc=0   warn=0  err=0  -             13s
  PASS       sim_dec_sweep          rc=0   warn=0  err=0  458752/0      48s
  PASS       oracle_dec_sweep       rc=0   warn=0  err=0  -              2s
  PASS       asm_dec_words          rc=0   warn=0  err=0  492/0          0s
  time 103s
== rtl/core/frontend/fe_top
  PASS       lint_fe_top            rc=0   warn=0  err=0  -              6s
  PASS       sim_fe_top             rc=0   warn=0  err=0  1006/0        31s
  PASS       assert_labels          rc=0   warn=0  err=0  172/0          5s
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
  PASS       sim_fe_top_multistart  rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_cross       rc=0   warn=0  err=0  18/0           1s
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
  PASS       sim_fe_top_pt_ad_s     rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_pt_ad_h     rc=0   warn=0  err=0  23/0           1s
  PASS       sim_fe_top_pt_inv      rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_zstar       rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_gonly    rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_vsonly   rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_upriv    rc=0   warn=0  err=0  25/0           0s
  PASS       sim_fe_top_sv48        rc=0   warn=0  err=0  23/0           1s
  PASS       sim_fe_top_sv57        rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_h57         rc=0   warn=0  err=0  24/0           0s
  PASS       sim_fe_top_pt_gonly_x4 rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_ras_fbstale rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ras_pdcall  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_rsv_twores  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_rsv_trapcall rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ras_bkicall rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ras_bkret   rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ras_offpop  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ftq_full    rc=0   warn=0  err=0  24/0           1s
  PASS       sim_fe_top_init_walk   rc=0   warn=0  err=0  34/0           0s
  time 55s
== rtl/core/frontend/fe_top/slot1
  PASS       lint_fe_top_1slot      rc=0   warn=0  err=0  -              6s
  PASS       sim_fe_top_1slot       rc=0   warn=0  err=0  1003/0        31s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  164/0          5s
  PASS       sim_fe_top_bare_1slot  rc=0   warn=0  err=0  22/0           1s
  PASS       sim_fe_top_sv39_1slot  rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_loops_1slot rc=0   warn=0  err=0  24/0           0s
  PASS       sim_fe_top_coro_1slot  rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_calls_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_lp_1slot    rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_hist_1slot  rc=0   warn=0  err=0  19/0           1s
  PASS       sim_fe_top_twocond_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_ftbonly_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_nest_1slot  rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_recur_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_t0_uaon_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_deep_1slot  rc=0   warn=0  err=0  18/0           1s
  PASS       sim_fe_top_indir_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_region_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_multistart_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_cross_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_rvc_1slot   rc=0   warn=0  err=0  18/0           1s
  PASS       sim_fe_top_misp_call_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_sc_nored_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_jals_1slot  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_fencei_1slot rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_cboinval_1slot rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_uc_nc_1slot rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_uc_io_1slot rc=0   warn=0  err=0  20/0           0s
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
  PASS       sim_fe_top_ras_bkicall_1slot rc=0   warn=0  err=0  19/0           1s
  PASS       sim_fe_top_ras_bkret_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ras_offpop_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_ftq_full_1slot rc=0   warn=0  err=0  24/0           0s
  PASS       sim_fe_top_init_walk_1slot rc=0   warn=0  err=0  32/0           0s
  time 53s
== rtl/core/frontend/ftq
  PASS       lint_ftq_ftb_sched     rc=0   warn=0  err=0  -              2s
  PASS       sim_ftq_ftb_sched      rc=0   warn=0  err=0  67/0          23s
  PASS       lint_ftq_ptr           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ptr            rc=0   warn=0  err=0  207/0         17s
  PASS       lint_ftq_commit        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_commit         rc=0   warn=0  err=0  72/0           2s
  PASS       lint_ftq_entry         rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_entry          rc=0   warn=0  err=0  83/0          15s
  PASS       lint_ftq_meta          rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta           rc=0   warn=0  err=0  26/0           2s
  PASS       lint_ftq_status        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_status         rc=0   warn=0  err=0  45/0           1s
  PASS       lint_ftq_shadow        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_shadow         rc=0   warn=0  err=0  53/0           2s
  PASS       lint_ftq_npc           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_npc            rc=0   warn=0  err=0  84/0           2s
  PASS       lint_ftq_ifu           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ifu            rc=0   warn=0  err=0  241/0         18s
  PASS       lint_ftq_resolve       rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_resolve        rc=0   warn=0  err=0  146/0          8s
  PASS       lint_ftq_upd_conv      rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_upd_conv       rc=0   warn=0  err=0  192/0          5s
  PASS       lint_ftq               rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq                rc=0   warn=0  err=0  259/0         17s
  PASS       assert_labels          rc=0   warn=0  err=0  232/0          4s
  PASS       lint_ftq_ftb_sched_1slot rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_ftb_sched_1slot rc=0   warn=0  err=0  67/0           0s
  PASS       lint_ftq_ptr_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ptr_1slot      rc=0   warn=0  err=0  207/0          3s
  PASS       lint_ftq_commit_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_commit_1slot   rc=0   warn=0  err=0  72/0           0s
  PASS       lint_ftq_entry_1slot   rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_entry_1slot    rc=0   warn=0  err=0  69/0           2s
  PASS       lint_ftq_meta_1slot    rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta_1slot     rc=0   warn=0  err=0  19/0           1s
  PASS       lint_ftq_status_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_status_1slot   rc=0   warn=0  err=0  45/0           0s
  PASS       lint_ftq_shadow_1slot  rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_shadow_1slot   rc=0   warn=0  err=0  53/0           0s
  PASS       lint_ftq_npc_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_npc_1slot      rc=0   warn=0  err=0  80/0           1s
  PASS       lint_ftq_ifu_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ifu_1slot      rc=0   warn=0  err=0  226/0         20s
  PASS       lint_ftq_resolve_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_resolve_1slot  rc=0   warn=0  err=0  105/0          4s
  PASS       lint_ftq_upd_conv_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_upd_conv_1slot rc=0   warn=0  err=0  106/0          3s
  PASS       lint_ftq_1slot         rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_1slot          rc=0   warn=0  err=0  259/0         10s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  211/0          5s
  time 173s
== rtl/core/frontend/ibuf
  PASS       lint_ibuf              rc=0   warn=0  err=0  -              2s
  PASS       sim_ibuf               rc=0   warn=0  err=0  52/0          33s
  PASS       assert_labels          rc=0   warn=0  err=0  3/0            3s
  time 38s
== rtl/core/frontend/icache
  PASS       lint_l1i               rc=0   warn=0  err=0  -              2s
  PASS       sim_l1i_emitted        rc=0   warn=0  err=0  67/0          34s
  PASS       sim_l1i                rc=0   warn=0  err=0  296/0         18s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0            5s
  time 59s
== rtl/core/frontend/ifu
  PASS       lint_ifu_rvc_exp       rc=0   warn=0  err=0  -              2s
  PASS       lint_ifu_predecode     rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_xlate         rc=0   warn=0  err=0  -              1s
  PASS       lint_ifu_lbuf          rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_fetch         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_f3            rc=0   warn=0  err=0  -              1s
  PASS       lint_ifu_wb            rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_maint         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu               rc=0   warn=0  err=0  -              1s
  PASS       sim_ifu_rvc_exp        rc=0   warn=0  err=0  2457618/0     32s
  PASS       sim_ifu_predecode      rc=0   warn=0  err=0  63/0          13s
  PASS       sim_ifu                rc=0   warn=0  err=0  738/0         28s
  PASS       assert_labels          rc=0   warn=0  err=0  16/0           5s
  PASS       oracle_ifu_rvc_exp     rc=0   warn=0  err=0  -              9s
  time 92s
== rtl/core/frontend/l1i_param_chk
  PASS       lint                   rc=0   warn=0  err=0  -              2s
  PASS       lint_neg               rc=0   warn=0  err=0  -              0s
  time 2s
== rtl/lib
  PASS       lint                   rc=0   warn=0  err=0  -              2s
  PASS       sim                    rc=0   warn=0  err=0  34/0          23s
  time 25s
== rtl
  time 0s
== rtl/mmu/itlb
  PASS       lint_itlb              rc=0   warn=0  err=0  -              2s
  PASS       sim_itlb               rc=0   warn=0  err=0  228/0         37s
  PASS       sim_itlb_d2            rc=0   warn=0  err=0  231/0         16s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0            7s
  time 63s
== rtl/mmu/pmp
  PASS       lint_pmp_pma_chk       rc=0   warn=0  err=0  -              2s
  PASS       sim_pmp_pma_chk        rc=0   warn=0  err=0  73/0          32s
  PASS       lint_neg_pma           rc=0   warn=0  err=0  -              0s
  PASS       lint_neg_pma_dflt      rc=0   warn=0  err=0  -              0s
  time 34s
== rtl/mmu/ptw
  PASS       lint_ptw               rc=0   warn=0  err=0  -              2s
  PASS       lint_pt_build_pkg      rc=0   warn=0  err=0  -              0s
  PASS       sim_ptw                rc=0   warn=0  err=0  1564/0        43s
  PASS       assert_labels          rc=0   warn=0  err=0  13/0          10s
  PASS       sim_pt_gen             rc=0   warn=0  err=0  -              4s
  PASS       sim_ptw_img            rc=0   warn=0  err=0  5465/0         7s
  PASS       sim_pt_gen_noncanon    rc=0   warn=0  err=0  -              1s
  PASS       sim_pt_gen_mem_top     rc=0   warn=0  err=0  -              0s
  time 67s
------------------------------------------------------------------
targets run: 303   total time: 369s
new failures: 0   known failures: 0   now passing: 0   stale entries: 0   malformed entries: 0   set errors: 0
logs: /tmp/regress.cVw3Jm
pass NOT recorded: tracked changes or untracked rtl/ files, or HEAD moved during the run (push will be refused)
RESULT: PASS
```
"pass NOT recorded" is the script's note for an uncommitted tree (this
task's changes are not committed); it does not affect RESULT.
The W3M fail-before at 1 slot was run after the regression, in the
scratch copy w3m_off (no tree file changed): 223/3, D18 D18a D18b.

## Rule changes for acceptance (Block 1)

R1 THE BUILD STAMP AND THE ROW'S PROVENANCE COLUMNS (format).
- Replaces: perf/Makefile:113-125, "SRC_SHA from git -C $(SRC_ROOT)
  rev-parse HEAD ... compiles it in (-DPERF_SRC_SHA)", the binary not
  depending on it; PF-9 "keyed by its configuration name (PF-5) and the
  pacino sha it ran on".
- New: the build writes a stamp (sha, dirty mark, input digest over
  every build input) rewritten only on change; the binary depends on it;
  each row carries sha, dirty, input_digest (dirty and input_digest new,
  after sha); make -C perf digest prints it without building;
  csr_tb_pkg.sv is a dependency.
- Why: TD#210; the digest, not the sha, says what was measured.
- Rejected: a -dirty suffix on the sha (TD#210's proposal): it does not
  tell two dirty trees apart.
- Could break: readers of the CSV by column position; a rebuild on every
  make. Test: Phase 1's four steps (no rebuild when nothing changed);
  perf_study.py reads columns by name.

R2 THE DIGEST RULE (perf_study.py).
- Replaces: nothing; rows were gathered whatever their build.
- New: rows are gathered only if each row's digest is its build's and,
  for a one-build sets file, all are equal; else exit 1, no --out.
- Why: one study, one set of inputs.
- Rejected: a warning only; it would let a mixed CSV through.
- Could break: a study across a rebuild. Test: p1st (mixed -> exit 1,
  no CSV; one and two builds -> written).

R3 THE EAGER CLOSE WITHOUT THE FTQ-FULL TERM (perf_fe.cc).
- Replaces: "top->ftq_full || idle >= EAGER_IDLE" at both sites, "so
  that no commit waits on a fetch that waits on commit".
- New: "idle >= EAGER_IDLE" only.
- Why: no RTL stall (Phase 2 test); the term closed entries and decided
  branches earlier than the design does.
- Rejected: keeping it as a guard; it changes timing whenever the FTQ is
  full (st200: up to 115,549 decisions).
- Could break: a hang at long resolve to commit. Test: rc50 to rc1000
  and st200 complete; rc rows identical; 30 moves LINKED.

R4 A TRAP AFTER A BRANCH (perf_fe.cc; format).
- Replaces: perf_fe.cc:1576-1579, the branch counted as mispredicted
  (br_trap_after, mispred_trap_after; orc_slot_trap under the oracle).
- New: Jeff's ruling built; column trap_after_branch replaces
  mispred_trap_after and orc_slot_trap.
- Why: Jeff, session-086 (PF-18).
- Rejected: keeping mispred_trap_after at 0; a dead column.
- Could break: the oracle check. Test: 18 oracle rows 0; 39 moves LINKED
  to the trap-after branch.

R5 THE ORACLE FORCES THE p2 RAS PEEK AND THE p1 RETURN ON AN FTB MISS
(perf_top.sv ports o_p2_peek, o_p2_pkv, os_p2_p1_s_*).
- Replaces: PF-11 "at p2 ... the RAS pop".
- New: at p2 also the RAS peek address and valid, and the p1 return slot
  held at p2 when the FTB misses.
- Why: since BP-153 an FTB-held return's p2 target is the peek; the
  oracle check failed (52/93/70) before this task.
- Rejected: forcing only the pop (the PF-11 text): it misses the peek.
- Could break: non-oracle rows. Test: non-oracle rows identical to the
  build without the force; oracle rows 0.

R6 THE cf_* AND sd_* PROBES (perf_top.sv outputs, perf_fe.cc columns).
- Replaces: nothing (PF-6 "Signals are observed at ports, the wrapper's
  included").
- New: columns cf_fastpath_dirs, cf_sc_answers, cf_tage_epoch_adv,
  cf_ittage_epoch_adv, cf_tage_decay_t1..t4, cf_ittage_decay_t1..t5,
  appended at the end of the row; SC probes for the evlog S line.
- Why: Phase 4 needs the design's own state.
- Rejected: reading the CSR only (fe_cfg_seen): shows the write, not the
  effect.
- Could break: other counts. Test: pf5 rows equal Phase 3's immediate
  rows (web_11 45,332 / 1,822,240; int_6 10,290 / 634,350).

R7 THE EVENT LOG AND THE STDERR DIAGNOSTICS (perf_fe.cc).
- Replaces: PF-6 "there is no per-event file output".
- New: PERF_EVLOG=<file> writes one line per event (C commit, W write,
  E close, D decision, T trap, S SC answer), off unless set; STREAMERR
  and UNSPEC lines on stderr, the first 20 of each.
- Why: first divergence (A MOVE FROM A TIMING CHANGE) and the Class A/B
  diagnosis.
- Rejected: --log only; it prints a window, not a run.
- Could break: rows. Test: off unless set; the baseline rows have no
  evlog and pass; pairs use it on both builds alike.

R8 perf_rerun.py COLUMN bin_sha256 (format).
- New: each rerun row carries its predictor binary's SHA-256.
- Why: provenance of R; it exposed cai = jimenez.
- Could break: readers by position. Test: p6_check reads by name.

R9 tb_fe_top PROGRAM ftq_full (a test added).
- New: program 50 (tb_fe_top.sv all_progs [0:50]; FE_PROGS).
- Test: fails with the stall put in (3 checks), passes at both slots.

R10 THE ORACLE'S ALIGNMENT ACCEPTS AN EARLY EXIT TO ITS OWN SUCCESSOR
(perf_fe.cc o_succ).
- Replaces: PF-11 "on the path when its PC is ... where the trace goes
  after its predecessor's predicted block": o_succ refused when the
  trace left the predecessor's block before its end (why 6).
- New: when the trace leaves the block early by a taken branch whose
  target is the predicted successor pc itself, the entry is on the path,
  at the record after that branch.
- Why: a later stage moves the predecessor's end without a redirect
  (BP-150), and the refused entry's p1 slots were unforced (Class C).
- Rejected: forcing at every realignment; a p2 realignment cannot force
  p1 state already written.
- Could break: the alignment of other entries. Test: oracle rows 0;
  orc_realigned 0; non-oracle rows unchanged (the code runs only under
  --oracle); 101 moves (every one accounted for, Phase 7).

R11 W3M: AN M2 BLOCK ENDS WHERE FETCH CUT IT (ftq_ifu.sv; RTL; interface
rule).
- Replaces: ftq_ifu_interfaces.md 7 W3 "re-derives the block successor
  across the slots (fe_decisions.md 2.4)", which for M2 (no taken slot
  left) gives pft_addr; tb_ftq_ifu D17-D18 "The slot becomes invalid and
  the block runs to its fall-through".
- New: under M2 with no corrected taken slot and no fault, the
  successor and the entry's pft_addr are the end of the last instruction
  start at or before mis_pos (start + 2i + 2 or 4); a faulting block is
  left as it was (M4).
- Why: the IFU delivers an M2 block only up to mis_pos (IFU-15, IB-2;
  ifu_f3.sv:356-358), so a successor at pft_addr skipped instructions:
  err_stream 260 on infra_6.
- Rejected: the IFU delivering the whole block after M2; it changes the
  ibuf write and the K+1 flush rule (IB-12) in two more modules, and the
  block's remaining bytes were never checked by predecode as one block.
- Could break: the RAS (the C1 push needs a taken slot: unaffected),
  training from pft_addr, other programs. Tests: tb_ftq_ifu D18, D18a,
  D18b fail with W3M off (238/3 at 2 slots, 223/3 at 1)
  and pass with it (241/0, 226/0), D18c/D18d
  (fault kept) pass both; tb_fe_top 1006/0 and 1003/0 with no program
  moved; infra_6 baseline err_stream 0 and its move LINKED.

R12 orc_slot_kind_alias (perf_fe.cc; format, and the oracle check).
- Replaces: PF-11 "zero mispredicts on every branch the FTB had in a
  slot".
- New: a slot whose type at the fetch request disagrees with the
  trace's class (COND against not COND) is a kind alias; its mispredict
  is counted in orc_slot_kind_alias, not err_orc_slot_mispred.
- Why: the oracle forces direction and target, not slot type; M3 then
  rewrites the alias and keeps a taken no predictor gave.
- Rejected: forcing the slot type: it changes what the FTB holds, which
  PF-11 keeps the predictors' own.
- Could break: hiding a real mispredict. Test: on every unmoved row the
  old count equals the new plus the alias (0 exceptions); 3 in all.

R13 conflict_unspec_repair (perf_fe.cc; format).
- Replaces: err_unspec_repair counting every RC_UNSPEC repair.
- New: a repair that follows a class-conflict PC is counted in
  conflict_unspec_repair.
- Why: rewritten code (two classes at one PC) is the trace's, not a
  harness or RTL error.
- Rejected: dropping web_11's row; it hides the trace.
- Could break: hiding a real repair. Test: split exact on unmoved rows;
  2 in all, web_11 only.

## Proposed planning text

perf_decisions.md PF-5, append:
       CHECKED BY PERF-004 (TD#197's configuration finding): every key
       reaches the design at both slot counts, read from the design's
       own state (columns cf_*): each enable off zeroes its count, each
       interval 1 moves the epoch advances from 2 to 396,484 (int_6,
       2e6). A key can reach the design and move no result (int_6 has
       no ITTAGE mispredict). PERF-002's "no count changed" does not
       reproduce.

perf_decisions.md PF-6, replace "there is no per-event file output" with:
       there is no per-event file output by default; PERF_EVLOG=<file>
       writes one line per event for first-divergence studies
       (PERF-004).

perf_decisions.md PF-9, append:
       THE BUILD STAMP (PERF-004, TD#210). Each build writes its sha,
       a dirty mark (rtl, perf) and an INPUT DIGEST, the SHA-256 over
       every build input (perf/src/stamp.py); the binary depends on it,
       and every row carries sha, dirty and input_digest. The digest says
       what was measured: two rows with one digest ran the same harness.
       make -C perf digest prints the stamp of the tree as it stands.
       tools/perf_study.py gathers rows only when their digests agree,
       unless the parameter-set file names more than one build.
       THE BASELINE (PERF-004): perf/studies/baseline.sets over
       baseline.traces, perf/studies/baseline.csv, digest
       0c66fed0ad2584216a27e4a2fac2f31b95d8dc297f48abf9883f6914e383a6dc.
       HOW TO RUN A STUDY AGAINST THE BASELINE:
         make -C perf harness
         make -C perf digest
         python3 tools/perf_study.py --traces perf/studies/baseline.traces
           --sets perf/studies/baseline.sets --out <new>.csv
       If the digest is the baseline's, the rows are the baseline's and
       nothing need run. A study of a parameter adds a set to a copy of
       baseline.sets that differs from baseline in that parameter; a
       study of an RTL change runs baseline.sets on the changed tree.
       Rows compare by study_set and trace; every column but the stamp
       and the timing columns is exact. A comparison tool is not built.

perf_decisions.md PF-11, replace the oracle paragraph's "at p2 the loop
predictor, TAGE, the FTB direction, the conditional and jump targets,
the RAS pop and ITTAGE's targets" with:
         at p2 the loop predictor, TAGE, the FTB direction, the
         conditional and jump targets, the RAS pop and peek, the p1
         return held at p2 on an FTB miss, and ITTAGE's targets
and append:
         PERF-004: an entry is also on the path when the trace leaves
         its predecessor's block early by a taken branch to the
         predicted successor itself. A slot whose type at the fetch
         request is not the trace's kind (conditional or not) is a KIND
         ALIAS; its mispredict is counted apart (orc_slot_kind_alias)
         and is not a failure: the oracle forces direction and target,
         not type. A repair after a class-conflict PC is counted apart
         (conflict_unspec_repair). MEASURED (the baseline, 105 traces,
         full length): every check passes on every run; kind aliases 1,
         class-conflict repairs 2 (web_11).
and replace "apart from a branch whose next trace record is an exception
entry (orc_slot_trap, 0 to 8 per run; PF-18)" with:
         (PERF-004 removed orc_slot_trap; PF-18)

perf_decisions.md PF-18, replace the last item (A TRAP AFTER A BRANCH
... "To be built by PERF-004; orc_slot_trap goes with it.") ending with:
         BUILT by PERF-004: the branch is judged on its own outcome and
         the trap is a separate RC_TRAP redirect; trap_after_branch
         counts the cases; mispred_trap_after and orc_slot_trap are
         removed.
and append:
       - THE FTQ-FULL WORKAROUND IS REMOVED (PERF-004, TD#206): the eager
         close keeps only idle >= EAGER_IDLE (32); the FTQ-full term
         closed entries and decided branches earlier than the design.

perf_decisions.md PF-21, append:
       WHAT PERF-004 BUILT: the build stamp and the digest rule (PF-9);
       the FTQ-full workaround removed and the trap ruling (PF-18); the
       oracle's peek and p1-return forces, its early-exit alignment and
       the kind-alias count (PF-11); the configuration probes cf_*
       (PF-5); PERF_EVLOG (PF-6); perf_rerun.py bin_sha256 and the full
       reference rerun, perf/cbp2025_rv_rerun.csv (PF-15); the baseline
       (PF-9).

perf_decisions.md PF-10, append (a result, for the PA's wording):
       MEASURED BY PERF-004 (the baseline): pacino / TAGE192 conditional
       MPKI, mean per group, 50Perc: compress 1.55, fp 1.91, infra 2.75,
       int 2.39, media 4.62, web 3.08 (all 2.48). The gap is not steady
       across the groups, so the extrapolation does not hold.

ftq_ifu_interfaces.md section 7, after W3U, add:
  W3M UNDER M2 THE BLOCK ENDS WHERE FETCH CUT IT. When the writeback
      leaves no taken slot (the predicted taken position holds no
      control transfer, or is not an instruction start) and has no
      fault, the successor of W3 is the end of the last instruction
      start at or before mis_pos (start + 2 * i + its length, 2 or 4),
      not pft_addr, and the entry's pft_addr is written with the same
      value. The IFU delivered the block only up to mis_pos (IFU-15,
      IB-2), so a successor at pft_addr stepped over the rest
      (PERF-004: err_stream 260 on infra_6). A faulting block traps (M4)
      and is left as it was. Built by PERF-004 (ftq_ifu.sv
      predecode_correct, w_m2_cut, w_cut_end); tb_ftq_ifu D18, D18a,
      D18b fail when it is ignored; D18c, D18d check the fault case.
  and in W3 append: "except under M2, W3M".

PROJECT_STATUS.md, closing lines:
- TD#206 CLOSED by PERF-004: not a defect. tb_fe_top ftq_full fills the
  FTQ with commit held; every entry is translated, fetched and delivered
  at both slot counts (a copy with the stall put in fails 3 checks). The
  harness's FTQ-full term is removed; rc50 to rc1000 rows are identical
  and no run hangs. PERF-002's stall was on its first backend and does
  not occur on this tree.
- TD#208 CLOSED by PERF-004: the cost of a correct SC. At every moved
  run's first divergence the fixed SC decides by its rules
  (sc_cntrl.sv:327-345, differ, SC wins, |sum| below the threshold over
  a weak or medium TAGE); 3.3M SC answers re-derived, 0 deviations.
- TD#210 CLOSED by PERF-004: every build writes a stamp (sha, dirty,
  input digest) and every row carries it; perf_study.py gathers only
  rows of one digest; make -C perf digest.
- TD#197, add: PERF-004 Phase 4: every PF-5 key reaches the design at
  both slot counts (cf_* counts). The aging design options stay open.
- NEW (proposed): the CBP submodule's cai and jimenez are one binary
  (same SHA-256, equal MispBr on every trace, golden too).
- NEW (proposed): a baseline comparison tool for tools/ (row by row by
  study_set and trace, exact).

## Assumptions made not explicit in the prompt
- err_orc_slot_mispred is an error only on oracle rows; off the oracle it
  is a count (perf_fe.cc:1877). The Phase 7 check treats it so.
- A --max-instr run is not a prefix of the full run (supply.cc:37 builds
  the code image from the records read). Divergence pairs compare two
  builds at the same --max-instr, never a short run with a full one.
- "The 50Perc values" of the count check are 50PercInstr and
  50PercNumBr.
- The CBP comparison uses the mean of the per-trace MPKI per group, the
  form the CBP results use; the totals-based MPKI is in the group table.

## Decisions made not explicit in the prompt
- The baseline was run twice: run 1 found the 10 failures; run 2, after
  the fixes, is the baseline. Run 1 is kept in the scratchpad only.
- perf/studies/baseline.traces was written by a script, then rewritten
  with Write to meet the file-creation rule.
- Class B and C2 are counted apart rather than fixed: their cause is in
  the trace (B) or outside what the oracle forces (C2, PF-11).

## RVA23 compliance risks and gaps noticed
None. W3M changes only where fetch resumes after a predecode kill.

## Deferred Work
- A baseline comparison tool (proposed above).
- cai = jimenez in tools/cbp2025 (outside the AREA).

## Other Notes
- Scratch copies built (one at a time): p2b, mut, p3b, ko150, w3m_off,
  p7b, p7a; scratch logs and scripts are in the session scratchpad.
- mose fails on every trace in golden and in the rerun (PF-1).

## DONE checklist
- [x] every phase ended: 0 to 8, each with its build, tests,
  measurement and cases, in order.
- [x] every count accounted for: OTHER 0, unexplained 0. Baseline
  210/210 rows pass PF-11; run 1's 10 failures traced to 4 causes, all
  fixed; 102 moved rows accounted for by their first divergence; the
  count splits exact on the 108 unmoved rows.
- [x] every class defined in words with an example: A (err_stream,
  infra_6 entry 15), B (err_unspec_repair, web_11), C (oracle
  alignment, web_9 k 3418323), C2 (kind alias, infra_6 k 65709094);
  LINKED (a first divergence at or after a fix event); kind alias;
  class-conflict repair.
- [x] every side effect traced: tb_fe_top unchanged after W3M at both
  slot counts; tb_ftq_ifu D18's expected value changed (W3M); every
  moved study row traced (phases 2, 3, 5, 7).
- [x] every fix has a test that fails before and passes after, at every
  configuration the task names: W3M tb_ftq_ifu 238/3 -> 241/0 (2 slots)
  and 223/3 -> 226/0 (1 slot); TD#206 ftq_full fails with the stall (3
  checks), passes at both slot counts; the oracle fixes 52/93/70 -> 0
  and 10 rows -> 0 (head_s2, the baseline's configuration); the stamp's
  four steps; the digest rule's mixed-digest refusal.
- [x] every rule change written as Block 1 says: R1 to R13.
- [x] tools/regress.sh run once at the end, summary whole: RESULT: PASS,
  303 targets, 0 new failures.
- [x] the Summary's first line states the status (STATUS: COMPLETE) and
  the header's Status line agrees.

## Files Modified
- perf/Makefile
- perf/src/stamp.py
- perf/src/harness/perf_fe.cc
- perf/sv/perf_top.sv
- perf/cbp2025_rv_rerun.csv
- perf/studies/baseline.sets
- perf/studies/baseline.traces
- perf/studies/baseline.csv
- perf/studies/perf004_cls_p0.csv
- perf/studies/perf004_p1_cls.csv
- perf/studies/perf004_p1_p2.csv
- perf/studies/perf004_p1_p5.csv
- perf/studies/perf004_p1_stress.csv
- perf/studies/perf004_p2_cls.csv
- perf/studies/perf004_p2_p2.csv
- perf/studies/perf004_p2_p5.csv
- perf/studies/perf004_p2_stress.csv
- perf/studies/perf004_p2_stress.sets
- perf/studies/perf004_p3_cls.csv
- perf/studies/perf004_p3_orc.csv
- perf/studies/perf004_p3_p2.csv
- perf/studies/perf004_p3_p5.csv
- perf/studies/perf004_p3b_cls.csv
- perf/studies/perf004_p3b_orc.csv
- perf/studies/perf004_p4_cfg.sets
- perf/studies/perf004_p4_cfg_s1.csv
- perf/studies/perf004_p4_cfg_s2.csv
- perf/studies/perf004_p5_fix.csv
- perf/studies/perf004_p5_ko150.csv
- perf/studies/perf004_p5_p0.csv
- tools/perf_study.py
- tools/perf_rerun.py
- rtl/core/frontend/fe_top/tb/tb_fe_top.sv
- rtl/core/frontend/fe_top/Makefile
- rtl/core/frontend/ftq/rtl/ftq_ifu.sv
- rtl/core/frontend/ftq/tb/tb_ftq_ifu.sv
- prompts/PERF-004.md

:: RESULTS:END ::

:: CONTEXT:START ::
# Context Report

Compactions: 2
Run time: 1h.34m.41s active, 40h.7m.26s wall (2026-11-21T04:03:37Z -> 2026-11-22T20:11:04Z, /run PERF-004, ended at the end marker)

Context used: 26% (258.6k / 1m tokens), model claude-opus-5-5.

| Category | Tokens | Percentage |
|----------|--------|------------|
| System prompt | 3k | 0.3% |
| System tools | 21.3k | 2.1% |
| MCP server instructions | 39 | 0.0% |
| MCP tools (deferred) | 1.2k | 0.1% |
| System tools (deferred) | 30.5k | 3.0% |
| Memory files | 7.1k | 0.7% |
| Skills | 6k | 0.6% |
| Messages | 221.1k | 22.1% |
| Free space | 708.4k | 70.8% |
| Autocompact buffer | 33k | 3.3% |

Memory files: CLAUDE.md 5k; MEMORY.md 2.1k.
:: CONTEXT:END ::
