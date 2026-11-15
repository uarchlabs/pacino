<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header 
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | INFRA-014               |                          |
| Date         | 2026.11.15              |                          |
| Module       | regression              | regress.sh run time      |
| Run time     | 13m.19s                 |                          |
| Ctx %        | 18%                     |                          |
| Model        | claude-opus-5-5 low     |                          |
| Resume sha   | 63d024b1-5d14-4114-a734-8fb220e1938e |             |
| PA session   | 085                     |                          |

Task:   [ ] experiment  [x] implementation  [ ] debug
        [x] cleanup     [ ] testbench       [x] verification
Mode:   [x] automated   [ ] manual          [ ] interactive
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview
tools/regress.sh takes about 11 minutes with a warm compiler cache and
about 32 after an edit to tb_fe_top. Both are too long for a regression
that gates every push (tools/hooks/pre-push). The fe_top Makefile is the
critical path. This task cuts its time without dropping a target or a
check:
1. fe_top's per-program targets, and its assert_labels, run the binary
   that sim_fe_top built in the same job, instead of rebuilding it.
2. fe_top's 1-slot half runs as its own Makefile, in parallel with the
   2-slot half.
3. ccache's base directory, so a scratch copy of the tree can hit the
   cache, if the generated C++ allows it.
4. Regression targets for pt_gen's two error paths (BP-149).
The target is about 5 minutes warm and 12 cold, with bpu the critical
path. Every time is measured, not estimated.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion 

## Claude.code Console Output

INFRA-014 is finished and Results Capture is written in prompts/INFRA-014.md, but
  neither time target was met: the warm run took 608s against 5 minutes, and the cold
  run 3445s against 12 minutes. All four runs passed:

  ┌────────────────────────────────┬─────────┬───────┬────────┐
  │              Run               │ Targets │ Time  │ Result │
  ├────────────────────────────────┼─────────┼───────┼────────┤
  │ Baseline, before any change    │ 283     │ 708s  │ PASS   │
  ├────────────────────────────────┼─────────┼───────┼────────┤
  │ Final, warm                    │ 285     │ 608s  │ PASS   │
  ├────────────────────────────────┼─────────┼───────┼────────┤
  │ Final, cold (CCACHE_DISABLE=1) │ 285     │ 3445s │ PASS   │
  ├────────────────────────────────┼─────────┼───────┼────────┤
  │ Weekly                         │ 15 runs │ 53s   │ PASS   │
  └────────────────────────────────┴─────────┴───────┴────────┘

  Every check count matches BP-149, and no run had a set error.

  What changed
  - One build per slot count: in the baseline, 88 targets each compiled tb_fe_top. In
    both final runs only sim_fe_top and sim_fe_top_1slot compiled it, and the other 86
    targets reused that binary. assert_labels no longer re-runs the programs. A target
    run alone builds first if the binary is missing, stale or built with other flags,
    with or without -B.
  - 1-slot half in parallel: it is now its own Makefile,
    rtl/core/frontend/fe_top/slot1/Makefile, running as a separate job with the same
    target names. Each half wrote files only in its own object directory. The weekly
    run found it unchanged and ran sim_fe_top_1slot at sv39, sv48 and sv57.
  - ccache base directory: tried and removed, as Binding requires. Verilator writes
    absolute source paths into the generated C++, so the scratch-copy build missed on
    the large files (41 hits, 15 misses). rtl/Vars.mk is back to its original content.
  - pt_gen error targets: sim_pt_gen_noncanon and sim_pt_gen_mem_top both pass. Each
    one failed on the scratch copy once pt_gen.sv was edited to accept its input.

  Why the times are over target
  - Warm: sim_fe_top (582s) and sim_fe_top_1slot (568s) compiled with no cache hits.
    Earlier builds in this session had the base-directory setting on, and the absolute
    TB_DIR changed the generated C++, so the cache had nothing that matched. In the
    weekly run that followed, a sim_fe_top that compiled and ran every program took 14
    to 19s. A full warm regression with a current cache was not measured, because the
    task allows only three runs.
  - Cold: the bpu job took 3437s. It is one job whose 95 targets run one after another,
    and without the cache each recompiles its C++. BP-149's 1913s run was cold only
    for tb_fe_top, with bpu at 293s, so the two are not the same measure.

  One problem in a .sv file, which this task may not change: tb_fe_top.sv:3436 loads
  ../ifu/tb/ifu_rvc_exp_oracle.hex by a path relative to the working directory. Because
  of that, the 1-slot targets have to run make from fe_top/; their output still lands
  under slot1/.

  The weekly run's sim_fe_top and sim_fe_top_1slot runs took 14 to 19s each, compile
  included. No change to PROJECT_CORE.md is required; Results Capture offers one
  optional paragraph. No known_failures entries are proposed. No git commands were run,
  and the Grep tool was missing, so searches went through grep -n in Bash; all of this
  is reported in Results Capture.

## My Assessment

NTR worked as intended.

## Claude.ai Assessment

INFRA-014 is complete and accepted. The mechanism works. The time
figures were not shown, and the main reason is my task design, not the
work.

### What it achieved
- **One build per slot count.** In the baseline run, 88 target logs
  compiled tb_fe_top. In the final runs, 2 did. The other 86 reuse the
  binary.
  - The per-program, init_walk and assert_labels targets fell from
    651s to 19s, across both slot counts together.
  - assert_labels greps the model and no longer re-runs the programs.
- **The freshness test is sound.** It runs inside the recipe, so
  `make -B` cannot defeat it, and it compares three things:
  - Verilator's own dependency file, so a new `include needs no
    Makefile edit;
  - the Makefiles;
  - a stamp of the build flags.
  A failed build leaves no stamp, so a broken binary is never reused.
  Nine run-alone cases are shown. The one not shown is a change of
  build flags alone; it is a small gap.
- **slot1.** It reads its target list from fe_top's regress_list, so
  the two lists cannot drift apart. Each half writes only under its own
  object directory, shown with find -newer. slot1's output is already
  in .gitignore.
- **ccache base_dir was tried, measured and removed, as ruled.**
  Verilator writes absolute source paths into the generated C++, 3,743
  strings in one file, and base_dir does not rewrite file contents.
  That ends the scratch-copy idea; nothing in the tree can fix it.
- **The pt_gen error targets** match the message, not only the exit
  code. The fail-first shows why that matters: with the checks
  disabled, pt_gen still failed, but later and for a different reason,
  and only the message match told the two apart.

### The time figures, read correctly
- **Warm.** The final "warm" run was cold for tb_fe_top, because
  making TB_DIR absolute changed the generated C++. That is a one-time
  cost.
  - With a current cache, the IA measured sim_fe_top at 17-19s and
    sim_fe_top_1slot at 14-16s, in the weekly run.
  - The fe_top and slot1 jobs then come to about 35s and 30s, so bpu
    (278s) becomes the critical path. A warm regress.sh should come to
    about 5 minutes. That run was not made, because the task allowed
    three, so I count the figure as likely but unmeasured.
- **Cold.** My task file defined "cold" as CCACHE_DISABLE=1, which
  disables the cache for every Makefile. That made bpu, 95 targets in
  one job, take 3,437s. The figure Jeff cares about is cold after a
  tb_fe_top edit, with everything else warm.
  - In this layout, that is the fe_top and slot1 compiles running in
    parallel. They took 699s and 651s with 15 jobs compiling at once;
    alone, BP-149 measured 547s.
  - So about 10-12 minutes, set by the tb_fe_top compile itself. That
    is TD#201.
  - The 3,445s figure is a no-cache worst case, not a regression
    figure.

### Problem 0 corrections (my errors)
- **TB_DIR was relative.** RTL_DIR, VER_OUT, TB_DIR and TB_MODELS were
  all relative to the Makefile's directory, not derived from RVA_ROOT.
- **Line ranges.** Three were off by a line or more.
- **The timing history does not fully carry over.** known_failures.txt
  and .git/regress_times are keyed by directory as well as target
  name. No waiver is lost, because known_failures.txt is empty. The
  time history of the 1-slot targets starts again under slot1.

### Findings for later
- **A relative path in tb_fe_top.sv.** Line 3436 reads
  `../ifu/tb/ifu_rvc_exp_oracle.hex` relative to the working
  directory, so slot1 has to run make from fe_top/. It belongs with
  TD#201, which edits tb_fe_top's files anyway.
- **bpu is the next floor.** Two pieces dominate:
  - sim_bp_cluster_init and its 1-slot twin take 72s;
  - the seven cov targets take 88s.
  Together they are 58% of the job. Splitting bpu's 1-slot half into
  its own Makefile, as fe_top's was, would run the halves in parallel.
  That would be INFRA-015, if the warm figure needs to go below about
  5 minutes.
- **Stale build output.** fe_top/obj_dir and fe_top/obj_1slot_fe_top
  can be deleted by hand.

### Process
- No git command was run, and regress.sh ran three times as allowed.
- The Grep fallback was used. Counting pipes into wc and sort were
  disclosed, and no summary was cut.
- rm -rf of the tree's obj_fe_top and one touch were disclosed. The
  clean-directory test needed them.
- Run time was 13m19s active.

### Planning updates (PA)
- PROJECT_CORE.md "The regression": add the IA's paragraph on one job
  per Makefile and reuse of the model. It records why slot1 exists.
- PROJECT_STATUS.md:
  - the INFRA-014 COMPLETE entry, with the warm and cold figures read
    as above;
  - TD#201 gains tb_fe_top.sv:3436;
  - INFRA-015 (the bpu split) noted as a candidate, not opened.
- The closed-debt move is still uncommitted. I will carry it in the
  same set, with CLOSED_TECH_DEBT.md, BLOG_GENERATION_PROCESS.md and
  check_planning.sh at 74 files.

### Follow-on Actions
- [ ] Jeff: a warm regress.sh on the next push confirms about 5
      minutes.
- [ ] Jeff: delete fe_top/obj_dir and fe_top/obj_1slot_fe_top.
- [ ] TD#201: the tb_fe_top cold compile, and tb_fe_top.sv:3436.
- [ ] INFRA-015, if wanted: the bpu 1-slot split.

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
INFRA-014

## Context Loaded
@planning/PROJECT_CORE.md
@tools/regress.sh
@tools/regress_weekly.sh
@rtl/Vars.mk
@rtl/core/frontend/fe_top/Makefile
@rtl/core/frontend/fe_top/fe_top_srcs.mk
@rtl/mmu/ptw/Makefile

## Context Comments
PROJECT_CORE.md "The regression" is the rule regress.sh keeps:
- It runs every target of every Makefile under rtl/.
- It fails on a target in neither REGRESS_TARGETS nor REGRESS_EXCLUDE.
- tools/known_failures.txt is the only waiver list, and only Jeff edits
  it.
- tools/hooks/pre-push refuses a push on a red run.
None of that changes here.

BP-121 made each tb_fe_top program its own regression target,
sim_fe_top_<p>, so a program's pass or fail has its own line. BP-128
added the 1-slot twin of every fe_top target. Both stay: a target may
change how it gets its binary, but not what it runs or checks.

THE BASELINE is BP-149's tools/regress.sh run: 283 targets, RESULT:
PASS, 1913s (prompts/BP-149.md, Test Case Results). That run was cold
for tb_fe_top. The IA may read prompts/BP-149.md's Test Case Results
and Other Notes, read only, for the times and the cold-compile
findings.

## Hypothesis
regress.sh runs every target with `make -B`, so every prerequisite is
remade. Each sim_fe_top_<p> depends on the phony build_fe_top. So each
of the 84 per-program targets runs Verilator again, and recompiles
through ccache, for about 6 to 10 s, to run a program of about 1 s.
assert_labels depends on sim_fe_top, so under -B it re-runs every
program as well. The 2-slot and 1-slot halves are one Makefile, so
they run in one job, one after the other.

## Background
Checked by the PA against the tree at 82e67d1. The IA confirms each
fact it uses.
- tools/regress.sh:
  - :11-23 and :424-438: the targets of one Makefile run in one job,
    one after another, in REGRESS_TARGETS order. Makefiles run in
    parallel, up to N at once, with the Makefile with the most targets
    started first (:442-448).
  - :32 and :430 run each target with `make -B -C <dir> <t>`.
  - :13-15: as measured on 2026-10-28, no target writes a file under
    another Makefile's directory.
  - Makefiles are found under ROOT/rtl by path (:269).
- rtl/core/frontend/fe_top/Makefile:
  - :33 RVA_ROOT ?= $(abspath ../../../..) and :53 TB_DIR := tb. Other
    paths are from RVA_ROOT.
  - build_fe_top (:168-174) is phony. sim_fe_top (:180-195) runs every
    program from it. Each sim_fe_top_<p> (:197-199) and
    sim_fe_top_init_walk (:203-205) depends on it.
  - assert_labels (:223-237) depends on sim_fe_top. It reads the
    generated model's .cpp files.
  - The 1-slot targets (:248-256) are sub-makes with SLOT_DEFS and
    VER_OUT=$(VER_OUT)_1slot, in the same directory.
  - REGRESS_TARGETS (:264-265) lists the 2-slot targets, then the
    1-slot targets. REGRESS_WEEKLY (:272) is sim_fe_top and
    sim_fe_top_1slot.
- examples/fe_demo/Makefile includes fe_top_srcs.mk (:77), not the
  fe_top Makefile.
- BP-149's times:
  - regress.sh took 1913s; fe_top took 1905s.
  - sim_fe_top took 547s and sim_fe_top_1slot 702s. Both were cold
    compiles.
  - Each sim_fe_top_<p> took 6 to 10s.
  - assert_labels took 20s and assert_labels_1slot 16s.
  - bpu took 293s, the next longest Makefile.
  - Warm, the weekly run gave sim_fe_top 14 to 16s and
    sim_fe_top_1slot 13 to 15s.
- BP-149 Other Notes: Verilator's object cache (OBJCACHE) is ccache. A
  scratch copy of the tree compiled cold, about 11 minutes per fe_top
  build, because ccache hashes the include paths. Nothing in the tree
  sets a ccache option today.
- rtl/mmu/ptw/Makefile:
  - sim_pt_gen (:118-120) runs pt_gen on the sample.
  - sim_ptw_img (:124-126) depends on build_ptw and sim_pt_gen.
  - pt_gen stops with $fatal on a non-canonical input line, and on an
    input too large for main memory given +MEM_TOP. BP-149 showed both
    by hand, not as targets.

## Binding Previous Decisions
Jeff, session-085, as recorded in PROJECT_STATUS.md (INFRA-014
OPENED) and in this task:
- NOTHING DROPPED. Every target in BP-149's run is still a regression
  target, under the same name or under a name the IA reports. Every
  check is still made. No target is moved to REGRESS_EXCLUDE.
  sim_fe_top_<p> and sim_fe_top_<p>_1slot each still run program <p>
  in its own simulation and report its own PASS and FAIL.
- ONE BUILD PER SLOT COUNT. In a regress.sh run, tb_fe_top is built
  once at each slot count, by sim_fe_top or sim_fe_top_1slot. The
  per-program targets, sim_fe_top_init_walk and assert_labels then use
  that binary and that model. assert_labels does not re-run the
  programs.
- NEVER A STALE BINARY. The same targets, run alone (`make
  sim_fe_top_bare` in a clean tree, or after a source edit), build the
  binary first, or stop with a message that names the target to run.
  They never run a binary older than its sources. This must hold
  under regress.sh's `make -B` and without it. The IA states which
  behavior it built and shows both cases.
- THE 1-SLOT HALF IN PARALLEL. The 1-slot targets move to a Makefile
  of their own under rtl/core/frontend/fe_top (for example slot1/),
  which reuses the fe_top Makefile's rules with SLOT_DEFS set. It
  writes only under its own directory, so the rule at regress.sh:13-15
  still holds. Each target keeps its name, so known_failures.txt and
  the timing history in .git/regress_times carry over. The weekly
  line moves with sim_fe_top_1slot.
- CCACHE BASE DIRECTORY. ccache's base_dir (CCACHE_BASEDIR) is set
  for every Verilator build, in rtl/Vars.mk, so that a scratch copy of
  the tree can hit the cache the tree filled. It is kept only if it
  works: a scratch build of tb_fe_top, after a warm build in the tree,
  shows ccache hits. If the generated C++ differs between the two trees
  (for example because absolute paths are written into it), the
  setting is removed and the reason is reported.
- PT_GEN ERROR TARGETS. Two regression targets in rtl/mmu/ptw:
  - one runs pt_gen on a checked-in input with a non-canonical line;
  - one runs it on the sample with a +MEM_TOP too small to hold it.
  Each passes only when pt_gen exits non-zero and prints its error
  message, which the target matches. The l1i_param_chk lint_neg target
  is the model. The inputs are checked in under rtl/mmu/ptw/tb.
- MEASURED, NOT ESTIMATED. Every time reported comes from a run in this
  task.
- AUTHORITY. The IA may change any Makefile and .mk file under rtl/,
  add the slot1 Makefile, add the pt_gen inputs, and change
  tools/regress_weekly.sh if the weekly line moves. It does not change
  tools/regress.sh, tools/hooks, tools/known_failures.txt, any .sv or
  .svh file, or examples/. If the work needs a change to one of those,
  the IA stops and reports it.

## Specific Requirements

Problem 0: the baseline
- Report each Background fact found false, with what the files say.
- Run tools/regress.sh once, in the background, before any change. This
  is the warm baseline: BP-149's 1913s was cold, so it cannot be
  compared. Report its summary whole, and the time of each fe_top
  target, of fe_top in all, of bpu, and of the run.
- Report how the bpu time splits across its targets, for the next step.
  Do not change bpu.

Problem 1: one build per slot count
Build ONE BUILD PER SLOT COUNT and NEVER A STALE BINARY in the fe_top
Makefile.
Acceptance:
- In a regress.sh-style run (`make -B` per target, in REGRESS_TARGETS
  order), Verilator runs once for the 2-slot half and once for the
  1-slot half. Show it from the logs.
- Each per-program target gives its BP-149 check count.
- Run alone, a per-program target in a clean object directory builds
  first or stops with its message. After a touch of a source file, it
  does not run the old binary. Show both.

Problem 2: the 1-slot half in parallel
Build THE 1-SLOT HALF IN PARALLEL.
Acceptance:
- regress.sh finds both Makefiles, runs them as two jobs, and reports
  every 1-slot target under its old name.
- No set error. Every 1-slot check count is BP-149's.
- No file is written outside each Makefile's own directory. Show it
  with a list of the files each half wrote.
- regress_weekly.sh still runs sim_fe_top_1slot at each mode.

Problem 3: ccache base_dir
Build CCACHE BASE DIRECTORY, then test it:
- build tb_fe_top in the tree;
- then build it in a scratch copy of the tree, with RVA_ROOT set to
  the copy;
- report ccache's hit and miss counts for the scratch build. Use
  `ccache -s` before and after, or CCACHE_LOGFILE.
Keep the setting or remove it, as Binding says.

Problem 4: pt_gen error targets
Build PT_GEN ERROR TARGETS.
Acceptance:
- Both targets pass.
- Each fails on the scratch copy when pt_gen is made to accept its
  input. A small edit to pt_gen.sv is allowed in the scratch copy
  only.

Problem 5: the measurement
Run tools/regress.sh twice at the end, in the background, one after
the other:
- the first warm, as it is;
- the second with CCACHE_DISABLE=1 in its environment, so every C++
  compile is cold. That uses no cache, and clears none.
Acceptance:
- Both runs pass, with the target count of Problem 0's run plus the
  pt_gen targets.
- Report a time table: each fe_top target, fe_top and slot1 in all,
  bpu, and each run's total. Compare each to Problem 0's warm run and
  to BP-149's cold run.
- If a run is over 5 minutes warm or 12 minutes cold, report what holds
  it there. Do not change anything to meet those figures.
- Then run regress_weekly.sh once, and report its summary whole.

## Constraints
- The planning files are read only. Results Capture proposes the
  exact text, but only for the planning files in Context Loaded. The
  PA updates the others.
- The IA runs no git command. Running tools/regress.sh, which makes
  git calls of its own, is permitted; that grant is to run the
  script, not any command it contains.
- tools/regress.sh runs three times in this task: Problem 0's baseline
  and Problem 5's two. Each runs in the background, the IA waits for
  it, and no file changes while it runs. Each summary goes into
  Results Capture whole, sha line included, not cut by a pipe.
- tools/regress_demo.sh is not run (fe_demo_tb_decisions.md FDT-2a).
  examples/fe_demo/Makefile is read only if the IA needs to confirm
  that it does not include the fe_top Makefile.
- COMMANDS (CLAUDE.md Commands, Experiment File Rules):
  - A Bash command names its files by literal paths. It uses no shell
    variable (no S=..., no $S, no $? and no ${PIPESTATUS[...]}), no
    $(...) or backticks, no loop and no xargs. The one exception is an
    environment setting on the command itself, such as
    CCACHE_DISABLE=1 or RVA_ROOT=<path>.
  - Files are read and searched with the Read, Grep and Glob tools.
    If the Grep tool is not available in the session, `grep -n` with
    literal paths through Bash is allowed; say so in Results Capture.
  - Files are created and changed with the Write and Edit tools. No
    sed -i, no heredoc, no redirect, except that a build or run log
    may be redirected to a file in the scratchpad.
  - Every command runs from the repo root: no cd, except a subshell
    ( cd <dir> && ... ) where a tool must run in another directory.
  - The scratch copy of the tree is made with one mkdir and one
    cp -r --parents naming literal paths.
  - Every build in the scratch copy sets RVA_ROOT to the copy on its
    command line, and the IA checks from the verbose compile line that
    the sources are the copy's.
- No ccache setting is changed outside the tree. The user's ccache
  configuration file is not edited, and the cache is not cleared.

## Deliverables
Note: If a new module is to be created ensure that claude.code is allowed
or told to modify the Makefile for lint checking at the minimum.

Files the IA may change:
- the Makefiles and .mk files under rtl/ that the work needs, and a
  new rtl/core/frontend/fe_top/slot1/Makefile (Binding, AUTHORITY);
- new pt_gen input files under rtl/mmu/ptw/tb;
- tools/regress_weekly.sh, only if the weekly line moves;
- prompts/INFRA-014.md, Results Capture filled in below.

Results Capture reports:
- Problem 0: the false facts, the baseline summary whole, and the bpu
  split.
- How the per-program targets get their binary, and both run-alone
  cases.
- The slot1 Makefile, the target names, and the files each half wrote.
- The ccache test: the counts, and whether the setting was kept.
- The pt_gen error targets and their failures on the scratch copy.
- The time table (Problem 5).
- The planning text proposed (PROJECT_CORE.md "The regression", if the
  job layout changes what it says).
- The two final regress.sh summaries and the regress_weekly.sh
  summary, whole.

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary
All five problems are done, and tools/regress.sh passed three times:
- Problem 0, the warm baseline: 283 targets, 708s.
- Problem 5, warm: 285 targets, 608s.
- Problem 5, cold (CCACHE_DISABLE=1): 285 targets, 3445s.
tools/regress_weekly.sh: 15 runs, PASS, 53s. Every check count is
BP-149's, and set errors are 0.

- Problem 1. tb_fe_top is now built once per slot count. In the
  baseline, 88 target logs compiled tb_fe_top: every per-program
  target, init_walk and assert_labels at both slot counts. In both
  final runs, only sim_fe_top and sim_fe_top_1slot compiled it. The
  other 43 targets of each half reused the binary, and assert_labels
  no longer re-runs the programs. Run alone, a target builds first,
  under -B and without it, both in a clean object directory and after
  a source is touched.
- Problem 2. The 1-slot half is its own Makefile,
  rtl/core/frontend/fe_top/slot1/Makefile, run as its own job. The
  target names are unchanged.
- Problem 3. CCACHE_BASEDIR was tried and REMOVED, as Binding says.
  The generated C++ holds absolute source paths. The scratch build hit
  41 times and missed 15 times, and the misses are the large files.
- Problem 4. Two pt_gen error targets were added and pass. Each fails
  on the scratch copy when pt_gen.sv is made to accept its input.

Neither final run meets the time targets. Nothing was changed to meet
them (Problem 5):
- WARM 608s, over 5 min. sim_fe_top (582s) and sim_fe_top_1slot
  (568s) each compiled cold. Earlier builds in this session had
  CCACHE_BASEDIR set, and the TB_DIR change alters the generated C++,
  so ccache held no entry for the current C++. With the cache that
  run filled, the weekly run's sim_fe_top, which compiles and runs
  every program, took 14 to 19s. The next longest job in the warm run
  was bpu, at 278s.
- COLD 3445s, over 12 min. The bpu job held it at 3437s. Its 95
  targets run one after another, and each recompiles all of its C++.
  BP-149's 1913s run was cold only for tb_fe_top (its bpu took 293s),
  so it is not the same measure.

One finding for a .sv file, which this task may not change:
tb_fe_top.sv:3436 reads ../ifu/tb/ifu_rvc_exp_oracle.hex by a path
relative to the working directory. Because of that, the slot1 targets
run make in fe_top/, not in slot1/. See Decisions.

Status: every acceptance item is met, but the time figures the Task
Overview aimed at are not. Status in the header is left for Jeff.

## Test Matrix (testbench sessions only, omit otherwise)
Not a testbench session. The two new targets are listed under What was
delivered.

## What was delivered

### Problem 0: Background facts found false
- fe_top Makefile, "Other paths are from RVA_ROOT": false. At 82e67d1,
  RTL_DIR := rtl, VER_OUT := obj, TB_DIR := tb and TB_MODELS
  ($(TB_DIR)/models) were relative to the Makefile's directory. This
  task makes TB_DIR absolute ($(FE_TOP)/tb), so Verilator's dependency
  file names every file by its full path.
- assert_labels spans :223-238, not :223-237.
- The 1-slot block spans :244-255, not :248-256.
- tools/regress.sh: the jobs comment starts at :12, not :11.
- Binding, "Each target keeps its name, so known_failures.txt and the
  timing history in .git/regress_times carry over": only partly true.
  Both are keyed on "<makefile dir> <target>", and the directory of
  the 1-slot targets becomes rtl/core/frontend/fe_top/slot1:
  - known_failures.txt has no entries (each run: 0 known, 0 stale), so
    no waiver is lost.
  - The time history of the 1-slot targets starts again under the new
    directory.
- The Hypothesis was confirmed. In the baseline logs (/tmp/regress.O1Sa23),
  88 target logs show "[compiling]  tb_fe_top": every per-program
  target, sim_fe_top, assert_labels and init_walk, at both slot
  counts. assert_labels re-ran all 41 programs.

### Problem 0: bpu time split (baseline run, 280s job)
| Part | Targets | Sum of target times |
|---|---|---|
| 2-slot lint | 20 | 6s |
| 2-slot sim | 24 | 112s (sim_bp_cluster_init 47s, sim_history 9s, the others 0 to 6s) |
| 2-slot cov | 7 | 88s (cov_bpu 32s, cov_bp_cluster 23s, cov_history 10s, cov_tage 9s, cov_ubtb 7s, cov_loop_pred 6s, cov_tage_table 1s) |
| 1-slot lint | 20 | 4s |
| 1-slot sim | 24 | 68s (sim_bp_cluster_init_1slot 25s, the others 0 to 6s) |
| bpu in all | 95 | 278s of the 280s job |
The two sim_bp_cluster_init targets (72s) and the seven cov targets
(88s) together take 160s, 58% of the job. bpu was not changed.

### Problem 1: how the per-program targets get their binary
rtl/core/frontend/fe_top/Makefile:
- New phony target fe_top_bin. The per-program targets,
  sim_fe_top_init_walk and assert_labels now depend on it, not on
  build_fe_top or sim_fe_top. sim_fe_top still depends on build_fe_top,
  so it always compiles, and in a regress.sh run it runs first and
  builds the binary.
- fe_top_bin runs the freshness test inside its recipe, so make -B
  cannot defeat it. The binary is current when all of these hold:
  - obj_fe_top/Vtb exists;
  - Verilator's dependency file obj_fe_top/Vtb__ver.d exists;
  - the stamp file obj_fe_top/fe_top_bin.stamp exists, and its content
    equals the build key: the Verilator path and every Verilator flag,
    SLOT_DEFS included;
  - no file is newer than the stamp, checked with find over every file
    Vtb__ver.d lists, the Makefiles read (MAKEFILE_LIST) and
    FE_EXTRA_MK (the slot1 Makefile). Vtb__ver.d lists every source,
    every `include file and verilator_bin.
- When the binary is current, fe_top_bin prints "[reusing]". Otherwise
  it prints "[compiling]", names the newer files, and builds. Behavior
  chosen: BUILD FIRST, not stop with a message.
- Every build deletes the stamp first and writes it only after
  Verilator succeeds, so a failed build is never reused.
- .NOTPARALLEL: was added, so that make -j cannot run two builds into
  one object directory.
- assert_labels depends on fe_top_bin. It greps obj_fe_top/*.cpp and
  no longer runs the programs. Its count (169/0, 161/0) is unchanged.

Evidence. Logs are in the session scratchpad; the PASS count is the
tb's.
| Case | Command | Log shows | Result |
|---|---|---|---|
| regress.sh run, 2-slot | warm and cold runs | only sim_fe_top compiles; 43 targets reuse | counts = BP-149 |
| regress.sh run, 1-slot | warm and cold runs | only sim_fe_top_1slot compiles; 43 targets reuse | counts = BP-149 |
| clean object directory, no -B | rm -rf obj_fe_top, then make sim_fe_top_bare | [compiling], then the run | 22/0 |
| touch a source, -B | touch tb/models/fe_tb_mem.svh, make -B sim_fe_top_bare | [compiling], names fe_tb_mem.svh | 22/0 |
| touch a source, no -B | same touch, make sim_fe_top_bare | [compiling], names fe_tb_mem.svh | 22/0 |
| nothing changed, -B | make -B sim_fe_top_bare | [reusing] | 22/0 |
| nothing changed, no -B | make sim_fe_top_bare | [reusing] | 22/0 |
| Makefile edited, -B | comment edit, make -B sim_fe_top_bare | [compiling], "newer than the binary: .../fe_top/Makefile" | 22/0 |
| assert_labels alone, -B | make -B assert_labels | [reusing], no program run | PASS=169 FAIL=0 |
| init_walk alone | make -B sim_fe_top_init_walk | [reusing] | 34/0 |
Not shown: a change of build flags alone (the stamp-key mismatch path).

Set check (scratchpad/defined.sh, against make's rule database):
- fe_top defines 50 targets: 45 in REGRESS_TARGETS and 5 in
  REGRESS_EXCLUDE.
- slot1 defines 48 targets: 45 in REGRESS_TARGETS and 3 in
  REGRESS_EXCLUDE.
- Neither has a target in neither list, and every regress.sh run
  reported set errors 0.

### Problem 2: the slot1 Makefile
rtl/core/frontend/fe_top/slot1/Makefile (new):
- It includes rtl/Vars.mk and fe_top_srcs.mk. It reads the 2-slot
  target list from `make -f ../Makefile regress_list` and adds _1slot
  to each name, so the two lists cannot drift apart. It stops with
  $(error) if the list comes back empty.
- Each <t>_1slot runs `$(MAKE) -C $(FE_TOP) <t>` with:
  - SLOT_DEFS=$(FE_SLOT1_DEFS);
  - VER_OUT=slot1/obj_1slot;
  - FE_EXTRA_MK=<the slot1 Makefile>;
  - PT_MODE.
  It reuses the fe_top Makefile's rules unchanged.
- Target names are unchanged: lint_fe_top_1slot, sim_fe_top_1slot,
  assert_labels_1slot, the 41 sim_fe_top_<p>_1slot targets and
  sim_fe_top_init_walk_1slot, 45 in all.
- REGRESS_WEEKLY := sim_fe_top_1slot. regress_weekly.sh found it with
  no change and ran it at sv39, sv48 and sv57 (weekly summary below).
- The 1-slot section, SLOT1_DEFS and the 1-slot weekly entry were
  removed from the fe_top Makefile.
- REGRESS_EXCLUDE in fe_top gained fe_top_bin. In slot1 it is all,
  clean and regress_list.

Files written by each half, the warm Problem 5 run. They were listed
with find -newer against a marker file written just before the run.
| Directory | Files written |
|---|---|
| rtl/core/frontend/fe_top/obj_fe_top/ | 160 (the 2-slot model, Vtb, Vtb__ver.d, fe_top_bin.stamp, the program images and logs) |
| rtl/core/frontend/fe_top/slot1/obj_1slot_fe_top/ | 152 (the same, for 1 slot) |
| anywhere else under rtl/core/frontend/fe_top/ | none |
Outside the object directories, only the bpu coverage files were
written, and those are the bpu job's own. The rule at
regress.sh:13-15 holds.

Left in place, not written by this task: a stale fe_top/obj_dir and
the old fe_top/obj_1slot_fe_top from before the move. Both are build
output and may be deleted.

### Problem 3: ccache base_dir (removed)
- `export CCACHE_BASEDIR ?= $(RVA_ROOT)` was added to rtl/Vars.mk.
- tb_fe_top was built in the tree, then in a scratch copy:
  - The copy was made with one mkdir and one cp -r --parents of the
    sources tb_fe_top needs, tools/bin and tools/share.
  - The build ran `make build_fe_top RVA_ROOT=<copy> VERBOSE=1`.
  - The verbose compile line names the copy's tools/bin/verilator and
    the copy's tb_fe_top.sv. Not one tree path appears in it.
- ccache -s, before and after the scratch build:
| Count | Before | After | Change |
|---|---|---|---|
| hits | 1121381 | 1121422 | +41 |
| misses | 43968 | 43983 | +15 |
| uncacheable | 3990 | 3992 | +2 |
- The misses are the large Vtb_tb__N and root .cpp files, which hold
  most of the compile time. Verilator writes absolute source paths
  into the generated C++ as string literals:
  - 17 generated files in the copy contain the copy's path.
  - The tree's Vtb_tb__0.cpp alone holds 3743 such strings, for
    example ".../tb/models/fe_tb_mem.svh".
  ccache base_dir rewrites paths in the compiler's arguments, not in
  file contents, so those files differ between the trees and miss.
- Binding: "If the generated C++ differs between the two trees (for
  example because absolute paths are written into it), the setting is
  removed". It was removed, and rtl/Vars.mk is back to its 82e67d1
  content.

### Problem 4: pt_gen error targets (rtl/mmu/ptw/Makefile)
- sim_pt_gen_noncanon runs pt_gen on rtl/mmu/ptw/tb/pt_gen_noncanon.txt
  (new). Line 13 holds 0100000000000000, which is not canonical under
  Sv57.
- sim_pt_gen_mem_top runs pt_gen on tb/pt_gen_sample.txt with
  +MEM_TOP=80100000, 256 pages, smaller than the sample's 607 pages
  plus 24 table pages.
- Both depend on build_pt_gen and use one macro, gen_neg, modeled on
  l1i_param_chk lint_neg. A target passes only when pt_gen exits
  non-zero AND its log contains the expected message, matched with
  grep -F. It fails, saying which, when pt_gen exits 0, or when it
  fails without the message.
- Messages matched:
  - noncanon: "pt_gen: <in> line 13: address 0100000000000000 is not
    canonical under Sv57"
  - mem_top: "table pages do not fit main memory, 0000000080000000 to
    0000000080100000, 256 pages"
- Both are in .PHONY, `all`, and REGRESS_TARGETS after sim_ptw_img.
  Each passed in all three runs.
- Fail-first on the scratch copy. The two checks in the copy's
  pt_gen.sv were disabled, at :127
  `if (1'b0 && (a[63:56] != 8'h00) ...` and at :190
  `if (1'b0 && (64'(pages.size() + nt) > cap))`. Both targets then
  FAILED:
  - noncanon: "FAIL - pt_gen failed without the message". pt_gen went
    on, and pt_build_pkg.sv:272 stopped it later with "CONFLICT: level
    0 holds 000000002000085b, not 000000002000105b at
    000000008000d000".
  - mem_top: "FAIL - pt_gen failed without the message".
    pt_build_pkg.sv:208 stopped it with "bad pool 0000000080260000 to
    0000000080100000".
  Both failures came from the message match, which is what tells
  pt_gen's own check apart from a later failure. The "exited 0" branch
  was not exercised, because no input reached a clean exit.

## Test Case Results

### Problem 5: time table
Every figure is from a run in this task, except the BP-149 column, which
is from prompts/BP-149.md Test Case Results. "per-program" gives the
range of the 41 sim_fe_top_<p> targets and, in brackets, their sum.
| Item | P0 warm (baseline) | P5 warm | P5 cold (CCACHE_DISABLE=1) | BP-149 cold |
|---|---|---|---|---|
| lint_fe_top | 3s | 4s | 4s | 4s |
| sim_fe_top | 25s | 582s | 699s | 547s |
| assert_labels | 20s | 2s | 2s | 20s |
| sim_fe_top_<p>, 2-slot | 7-11s [313s] | 0-2s [8s] | 0-2s [9s] | 6-10s |
| sim_fe_top_init_walk | 7s | 0s | 1s | 8s |
| lint_fe_top_1slot | 3s | 3s | 4s | 3s |
| sim_fe_top_1slot | 14s | 568s | 651s | 702s |
| assert_labels_1slot | 17s | 2s | 2s | 16s |
| sim_fe_top_<p>_1slot | 6-8s [287s] | 0-2s [7s] | 0-2s [9s] | 6-10s |
| sim_fe_top_init_walk_1slot | 7s | 0s | 0s | 7s |
| fe_top job | 700s (both halves) | 599s | 715s | 1905s (both halves) |
| slot1 job | (in fe_top) | 582s | 666s | (in fe_top) |
| bpu job | 280s | 278s | 3437s | 293s |
| ptw job | 28s | 31s | 447s | 34s |
| run total | 708s | 608s | 3445s | 1913s |
| targets | 283 | 285 | 285 | 283 |

Comparison:
- Against P0 warm, the per-program, init_walk and assert_labels targets
  fell from 651s to 19s (P5 warm), at both slot counts together.
- Neither final run shows the warm fe_top figure the task aims at,
  because sim_fe_top and sim_fe_top_1slot were cold compiles in the
  "warm" run (see Summary).
- The warm compile was measured in the weekly run. sim_fe_top took 17
  to 19s and sim_fe_top_1slot 14 to 16s, and each log shows one
  "[compiling]  tb_fe_top".
- A full warm regress.sh with a current cache was not run: this task
  allows three runs.
- Against BP-149 cold: P5 cold took 1532s longer. Its fe_top and slot1
  jobs (715s, 666s) ran in parallel and replaced BP-149's single 1905s
  job. Without ccache, bpu went from 293s to 3437s and became the
  critical path. BP-149 was cold only for tb_fe_top, so its 1913s is
  not a no-cache figure.

What holds each run over its figure (no change made):
- Warm, 608s against 300s. The fe_top job (599s), almost all of it
  the cold compile in sim_fe_top (582s). The cause was a cache with no
  entry for the new C++ (see Summary). Next is bpu, at 278s.
- Cold, 3445s against 720s. The bpu job (3437s). It is one job of 95
  targets that run one after another, and without the cache each one
  recompiles its C++. The largest targets:
  - cov_bpu 463s, cov_bp_cluster 345s, sim_bp_cluster_init 202s,
    cov_history 161s, sim_bp_cluster 156s;
  - sim_bp_cluster_init_1slot 146s, sim_bp_cluster_1slot 125s,
    sim_ras 116s, cov_tage 113s.
  Fifteen jobs were compiling at once, so each compile also ran slower
  than it would alone. After bpu, the longest jobs were fe_top (715s)
  and slot1 (666s), each its one tb_fe_top compile.

### Binary reuse in the final runs (from the per-target logs)
| Run | Logs with "[compiling]  tb_fe_top" | Logs with "[reusing]" |
|---|---|---|
| P0 baseline (/tmp/regress.O1Sa23) | 88 | 0 (the mechanism did not exist) |
| P5 warm (/tmp/regress.QzmVrQ) | 2: fe_top sim_fe_top, slot1 sim_fe_top_1slot | 86 (43 in slot1) |
| P5 cold (/tmp/regress.ls1W1T) | 2: fe_top sim_fe_top, slot1 sim_fe_top_1slot | 86 |

### Problem 0: baseline tools/regress.sh summary (before any change)
```
==================================================================
REGRESSION SUMMARY  git 82e67d1 (dirty)
root /home/jeff/Development/jeffnye-gh/pacino
jobs 15 (default: 32 threads / 2, 31 GB / 2); priority: nice -n 10, ionice -c 3
==================================================================
== rtl/core/csr
  PASS       lint_csr_pkg           rc=0   warn=0  err=0  -              0s
  PASS       lint_csr_tb_pkg        rc=0   warn=0  err=0  -              0s
  PASS       sim_csr_tb_pkg         rc=0   warn=0  err=0  200/0          1s
  time 1s
== rtl/core/frontend/bpu
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       lint_loop_pred         rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_table        rc=0   warn=0  err=0  -              1s
  PASS       lint_sc_table          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_brimli         rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_cntrl          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc                rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_table      rc=0   warn=0  err=0  -              1s
  PASS       lint_ittage_cntrl      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_arb        rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage            rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_cntrl        rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_arb          rc=0   warn=0  err=0  -              0s
  PASS       lint_tage              rc=0   warn=0  err=0  -              1s
  PASS       lint_ras               rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_array         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru          rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl         rc=0   warn=0  err=0  -              1s
  PASS       lint_ftb               rc=0   warn=0  err=0  -              0s
  PASS       lint_bp_cluster        rc=0   warn=0  err=0  -              1s
  PASS       sim                    rc=0   warn=0  err=0  31/0           1s
  PASS       sim_history            rc=0   warn=0  err=0  45442/0        9s
  PASS       sim_ubtb               rc=0   warn=0  err=0  341/0          6s
  PASS       sim_loop_pred          rc=0   warn=0  err=0  11548/0        3s
  PASS       sim_tage_table         rc=0   warn=0  err=0  15/0           0s
  PASS       sim_sc_table           rc=0   warn=0  err=0  7/0            0s
  PASS       sim_sc_table_fast      rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_brimli          rc=0   warn=0  err=0  7/0            0s
  PASS       sim_sc_brimli_fast     rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_cntrl           rc=0   warn=0  err=0  98/0           4s
  PASS       sim_sc                 rc=0   warn=0  err=0  144/0          3s
  PASS       sim_sc_fast            rc=0   warn=0  err=0  140/0          3s
  PASS       sim_ittage_table       rc=0   warn=0  err=0  32/0           0s
  PASS       sim_ittage_cntrl       rc=0   warn=0  err=0  147/0          3s
  PASS       sim_ittage             rc=0   warn=0  err=0  389/0          4s
  PASS       sim_ittage_fast        rc=0   warn=0  err=0  389/0          3s
  PASS       sim_bp_cluster         rc=0   warn=0  err=0  2112/0         6s
  PASS       sim_bp_cluster_init    rc=0   warn=0  err=0  2112/0        47s
  PASS       sim_ras                rc=0   warn=0  err=0  602/0          3s
  PASS       sim_ftb                rc=0   warn=0  err=0  239/0          3s
  PASS       sim_tage               rc=0   warn=0  err=0  109/0          3s
  PASS       sim_tage_fast          rc=0   warn=0  err=0  109/0          3s
  PASS       sim_tage_tasks         rc=0   warn=0  err=0  1/0            3s
  PASS       sim_tage_manual        rc=0   warn=0  err=0  1267/0         3s
  PASS       cov_history            rc=0   warn=0  err=0  45442/0       10s
  PASS       cov_ubtb               rc=0   warn=0  err=0  341/0          7s
  PASS       cov_loop_pred          rc=0   warn=0  err=0  11548/0        6s
  PASS       cov_tage_table         rc=0   warn=0  err=0  15/0           1s
  PASS       cov_tage               rc=0   warn=0  err=0  218/0          9s
  PASS       cov_bp_cluster         rc=0   warn=0  err=0  2112/0        23s
  PASS       cov_bpu                rc=0   warn=0  err=0  57564/0       32s
             sum of sub-runs:tage=218/0 tage_table=15/0 loop_pred=11548/0 bp_history=45442/0 ubtb=341/0
  PASS       lint_1slot             rc=0   warn=0  err=0  -              0s
  PASS       lint_loop_pred_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_table_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_table_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_brimli_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_cntrl_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_1slot          rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_table_1slot rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_cntrl_1slot rc=0   warn=0  err=0  -              1s
  PASS       lint_ittage_arb_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_1slot      rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_cntrl_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_arb_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_1slot        rc=0   warn=0  err=0  -              1s
  PASS       lint_ras_1slot         rc=0   warn=0  err=0  -              1s
  PASS       lint_ftb_array_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_1slot         rc=0   warn=0  err=0  -              0s
  PASS       lint_bp_cluster_1slot  rc=0   warn=0  err=0  -              1s
  PASS       sim_1slot              rc=0   warn=0  err=0  27/0           1s
  PASS       sim_history_1slot      rc=0   warn=0  err=0  26590/0        2s
  PASS       sim_ubtb_1slot         rc=0   warn=0  err=0  341/0          3s
  PASS       sim_loop_pred_1slot    rc=0   warn=0  err=0  5765/0         2s
  PASS       sim_tage_table_1slot   rc=0   warn=0  err=0  11/0           0s
  PASS       sim_sc_table_1slot     rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_table_fast_1slot rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_brimli_1slot    rc=0   warn=0  err=0  6/0            1s
  PASS       sim_sc_brimli_fast_1slot rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_cntrl_1slot     rc=0   warn=0  err=0  98/0           2s
  PASS       sim_sc_1slot           rc=0   warn=0  err=0  108/0          0s
  PASS       sim_sc_fast_1slot      rc=0   warn=0  err=0  104/0          1s
  PASS       sim_ittage_table_1slot rc=0   warn=0  err=0  26/0           0s
  PASS       sim_ittage_cntrl_1slot rc=0   warn=0  err=0  138/0          3s
  PASS       sim_ittage_1slot       rc=0   warn=0  err=0  258/0          3s
  PASS       sim_ittage_fast_1slot  rc=0   warn=0  err=0  258/0          3s
  PASS       sim_bp_cluster_1slot   rc=0   warn=0  err=0  1534/0         6s
  PASS       sim_bp_cluster_init_1slot rc=0   warn=0  err=0  1534/0        25s
  PASS       sim_ras_1slot          rc=0   warn=0  err=0  502/0          4s
  PASS       sim_ftb_1slot          rc=0   warn=0  err=0  186/0          3s
  PASS       sim_tage_1slot         rc=0   warn=0  err=0  105/0          3s
  PASS       sim_tage_fast_1slot    rc=0   warn=0  err=0  105/0          3s
  PASS       sim_tage_tasks_1slot   rc=0   warn=0  err=0  1/0            0s
  PASS       sim_tage_manual_1slot  rc=0   warn=0  err=0  534/0          3s
  time 280s
== rtl/core/frontend/decode
  PASS       lint_dec               rc=0   warn=0  err=0  -              0s
  PASS       sim_dec                rc=0   warn=0  err=0  1355/0        11s
  PASS       coverage               rc=0   warn=0  err=0  -              9s
  PASS       sim_dec_sweep          rc=0   warn=0  err=0  458752/0      41s
  PASS       oracle_dec_sweep       rc=0   warn=0  err=0  -              2s
  PASS       asm_dec_words          rc=0   warn=0  err=0  492/0          1s
  time 64s
== rtl/core/frontend/fe_top
  PASS       lint_fe_top            rc=0   warn=0  err=0  -              3s
  PASS       sim_fe_top             rc=0   warn=0  err=0  829/0         25s
  PASS       assert_labels          rc=0   warn=0  err=0  169/0         20s
  PASS       sim_fe_top_bare        rc=0   warn=0  err=0  22/0           8s
  PASS       sim_fe_top_sv39        rc=0   warn=0  err=0  23/0           8s
  PASS       sim_fe_top_loops       rc=0   warn=0  err=0  26/0           8s
  PASS       sim_fe_top_coro        rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_calls       rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_lp          rc=0   warn=0  err=0  21/0           7s
  PASS       sim_fe_top_hist        rc=0   warn=0  err=0  19/0           8s
  PASS       sim_fe_top_twocond     rc=0   warn=0  err=0  18/0           8s
  PASS       sim_fe_top_ftbonly     rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_nest        rc=0   warn=0  err=0  18/0           8s
  PASS       sim_fe_top_recur       rc=0   warn=0  err=0  18/0           8s
  PASS       sim_fe_top_t0_uaon     rc=0   warn=0  err=0  20/0           8s
  PASS       sim_fe_top_deep        rc=0   warn=0  err=0  18/0           8s
  PASS       sim_fe_top_indir       rc=0   warn=0  err=0  19/0           8s
  PASS       sim_fe_top_region      rc=0   warn=0  err=0  18/0           8s
  PASS       sim_fe_top_multistart  rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_cross       rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_rvc         rc=0   warn=0  err=0  18/0           8s
  PASS       sim_fe_top_misp_call   rc=0   warn=0  err=0  20/0           8s
  PASS       sim_fe_top_jals        rc=0   warn=0  err=0  19/0           7s
  PASS       sim_fe_top_fencei      rc=0   warn=0  err=0  22/0           8s
  PASS       sim_fe_top_cboinval    rc=0   warn=0  err=0  22/0           7s
  PASS       sim_fe_top_uc_nc       rc=0   warn=0  err=0  20/0           8s
  PASS       sim_fe_top_uc_io       rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_pt_faults_s rc=0   warn=0  err=0  20/0           8s
  PASS       sim_fe_top_pt_faults_h rc=0   warn=0  err=0  19/0           8s
  PASS       sim_fe_top_pt_napot_s  rc=0   warn=0  err=0  19/0           8s
  PASS       sim_fe_top_pt_napot_h  rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_pt_rsv_s    rc=0   warn=0  err=0  20/0           8s
  PASS       sim_fe_top_pt_rsv_h    rc=0   warn=0  err=0  20/0          11s
  PASS       sim_fe_top_pt_ad_s     rc=0   warn=0  err=0  21/0           7s
  PASS       sim_fe_top_pt_ad_h     rc=0   warn=0  err=0  23/0           8s
  PASS       sim_fe_top_pt_inv      rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_zstar       rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_pt_gonly    rc=0   warn=0  err=0  19/0           8s
  PASS       sim_fe_top_pt_vsonly   rc=0   warn=0  err=0  19/0           7s
  PASS       sim_fe_top_pt_upriv    rc=0   warn=0  err=0  25/0           7s
  PASS       sim_fe_top_sv48        rc=0   warn=0  err=0  23/0           7s
  PASS       sim_fe_top_sv57        rc=0   warn=0  err=0  23/0           8s
  PASS       sim_fe_top_h57         rc=0   warn=0  err=0  24/0           7s
  PASS       sim_fe_top_pt_gonly_x4 rc=0   warn=0  err=0  21/0           7s
  PASS       sim_fe_top_init_walk   rc=0   warn=0  err=0  34/0           7s
  PASS       lint_fe_top_1slot      rc=0   warn=0  err=0  -              3s
  PASS       sim_fe_top_1slot       rc=0   warn=0  err=0  827/0         14s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  161/0         17s
  PASS       sim_fe_top_bare_1slot  rc=0   warn=0  err=0  22/0           7s
  PASS       sim_fe_top_sv39_1slot  rc=0   warn=0  err=0  23/0           6s
  PASS       sim_fe_top_loops_1slot rc=0   warn=0  err=0  24/0           7s
  PASS       sim_fe_top_coro_1slot  rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_calls_1slot rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_lp_1slot    rc=0   warn=0  err=0  21/0           7s
  PASS       sim_fe_top_hist_1slot  rc=0   warn=0  err=0  19/0           7s
  PASS       sim_fe_top_twocond_1slot rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_ftbonly_1slot rc=0   warn=0  err=0  18/0           8s
  PASS       sim_fe_top_nest_1slot  rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_recur_1slot rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_t0_uaon_1slot rc=0   warn=0  err=0  20/0           6s
  PASS       sim_fe_top_deep_1slot  rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_indir_1slot rc=0   warn=0  err=0  19/0           7s
  PASS       sim_fe_top_region_1slot rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_multistart_1slot rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_cross_1slot rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_rvc_1slot   rc=0   warn=0  err=0  18/0           8s
  PASS       sim_fe_top_misp_call_1slot rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_jals_1slot  rc=0   warn=0  err=0  19/0           7s
  PASS       sim_fe_top_fencei_1slot rc=0   warn=0  err=0  22/0           7s
  PASS       sim_fe_top_cboinval_1slot rc=0   warn=0  err=0  22/0           7s
  PASS       sim_fe_top_uc_nc_1slot rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_uc_io_1slot rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_pt_faults_s_1slot rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_pt_faults_h_1slot rc=0   warn=0  err=0  19/0           8s
  PASS       sim_fe_top_pt_napot_s_1slot rc=0   warn=0  err=0  19/0           6s
  PASS       sim_fe_top_pt_napot_h_1slot rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_pt_rsv_s_1slot rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_pt_rsv_h_1slot rc=0   warn=0  err=0  20/0           8s
  PASS       sim_fe_top_pt_ad_s_1slot rc=0   warn=0  err=0  21/0           7s
  PASS       sim_fe_top_pt_ad_h_1slot rc=0   warn=0  err=0  23/0           8s
  PASS       sim_fe_top_pt_inv_1slot rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_zstar_1slot rc=0   warn=0  err=0  20/0           6s
  PASS       sim_fe_top_pt_gonly_1slot rc=0   warn=0  err=0  19/0           7s
  PASS       sim_fe_top_pt_vsonly_1slot rc=0   warn=0  err=0  19/0           7s
  PASS       sim_fe_top_pt_upriv_1slot rc=0   warn=0  err=0  25/0           8s
  PASS       sim_fe_top_sv48_1slot  rc=0   warn=0  err=0  23/0           7s
  PASS       sim_fe_top_sv57_1slot  rc=0   warn=0  err=0  23/0           7s
  PASS       sim_fe_top_h57_1slot   rc=0   warn=0  err=0  24/0           7s
  PASS       sim_fe_top_pt_gonly_x4_1slot rc=0   warn=0  err=0  21/0           7s
  PASS       sim_fe_top_init_walk_1slot rc=0   warn=0  err=0  32/0           7s
  time 700s
== rtl/core/frontend/ftq
  PASS       lint_ftq_ftb_sched     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ftb_sched      rc=0   warn=0  err=0  67/0           0s
  PASS       lint_ftq_ptr           rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_ptr            rc=0   warn=0  err=0  207/0          8s
  PASS       lint_ftq_commit        rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_commit         rc=0   warn=0  err=0  72/0           0s
  PASS       lint_ftq_entry         rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_entry          rc=0   warn=0  err=0  72/0           8s
  PASS       lint_ftq_meta          rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta           rc=0   warn=0  err=0  26/0           0s
  PASS       lint_ftq_status        rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_status         rc=0   warn=0  err=0  45/0           0s
  PASS       lint_ftq_shadow        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_shadow         rc=0   warn=0  err=0  53/0           1s
  PASS       lint_ftq_npc           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_npc            rc=0   warn=0  err=0  84/0           0s
  PASS       lint_ftq_ifu           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ifu            rc=0   warn=0  err=0  237/0          4s
  PASS       lint_ftq_resolve       rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_resolve        rc=0   warn=0  err=0  146/0          4s
  PASS       lint_ftq_upd_conv      rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_upd_conv       rc=0   warn=0  err=0  192/0          4s
  PASS       lint_ftq               rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq                rc=0   warn=0  err=0  158/0          3s
  PASS       assert_labels          rc=0   warn=0  err=0  226/0          2s
  PASS       lint_ftq_ftb_sched_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ftb_sched_1slot rc=0   warn=0  err=0  67/0           0s
  PASS       lint_ftq_ptr_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ptr_1slot      rc=0   warn=0  err=0  207/0          3s
  PASS       lint_ftq_commit_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_commit_1slot   rc=0   warn=0  err=0  72/0           0s
  PASS       lint_ftq_entry_1slot   rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_entry_1slot    rc=0   warn=0  err=0  61/0           2s
  PASS       lint_ftq_meta_1slot    rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_meta_1slot     rc=0   warn=0  err=0  19/0           0s
  PASS       lint_ftq_status_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_status_1slot   rc=0   warn=0  err=0  45/0           0s
  PASS       lint_ftq_shadow_1slot  rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_shadow_1slot   rc=0   warn=0  err=0  53/0           0s
  PASS       lint_ftq_npc_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_npc_1slot      rc=0   warn=0  err=0  80/0           1s
  PASS       lint_ftq_ifu_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ifu_1slot      rc=0   warn=0  err=0  222/0          2s
  PASS       lint_ftq_resolve_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_resolve_1slot  rc=0   warn=0  err=0  105/0          4s
  PASS       lint_ftq_upd_conv_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_upd_conv_1slot rc=0   warn=0  err=0  106/0          3s
  PASS       lint_ftq_1slot         rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_1slot          rc=0   warn=0  err=0  158/0          4s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  205/0          1s
  time 61s
== rtl/core/frontend/ibuf
  PASS       lint_ibuf              rc=0   warn=0  err=0  -              0s
  PASS       sim_ibuf               rc=0   warn=0  err=0  52/0           8s
  PASS       assert_labels          rc=0   warn=0  err=0  3/0            1s
  time 9s
== rtl/core/frontend/icache
  PASS       lint_l1i               rc=0   warn=0  err=0  -              0s
  PASS       sim_l1i_emitted        rc=0   warn=0  err=0  67/0           9s
  PASS       sim_l1i                rc=0   warn=0  err=0  296/0          7s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0            6s
  time 22s
== rtl/core/frontend/ifu
  PASS       lint_ifu_rvc_exp       rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_predecode     rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_xlate         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_lbuf          rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_fetch         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_f3            rc=0   warn=0  err=0  -              1s
  PASS       lint_ifu_wb            rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_maint         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu               rc=0   warn=0  err=0  -              1s
  PASS       sim_ifu_rvc_exp        rc=0   warn=0  err=0  2457618/0      9s
  PASS       sim_ifu_predecode      rc=0   warn=0  err=0  63/0           8s
  PASS       sim_ifu                rc=0   warn=0  err=0  738/0          9s
  PASS       assert_labels          rc=0   warn=0  err=0  16/0           0s
  PASS       oracle_ifu_rvc_exp     rc=0   warn=0  err=0  -              1s
  time 30s
== rtl/core/frontend/l1i_param_chk
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       lint_neg               rc=0   warn=0  err=0  -              0s
  time 0s
== rtl/lib
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       sim                    rc=0   warn=0  err=0  34/0           1s
  time 1s
== rtl
  time 0s
== rtl/mmu/itlb
  PASS       lint_itlb              rc=0   warn=0  err=0  -              0s
  PASS       sim_itlb               rc=0   warn=0  err=0  228/0         11s
  PASS       sim_itlb_d2            rc=0   warn=0  err=0  231/0          9s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0            0s
  time 20s
== rtl/mmu/pmp
  PASS       lint_pmp_pma_chk       rc=0   warn=0  err=0  -              0s
  PASS       sim_pmp_pma_chk        rc=0   warn=0  err=0  73/0           8s
  PASS       lint_neg_pma           rc=0   warn=0  err=0  -              0s
  PASS       lint_neg_pma_dflt      rc=0   warn=0  err=0  -              0s
  time 8s
== rtl/mmu/ptw
  PASS       lint_ptw               rc=0   warn=0  err=0  -              0s
  PASS       lint_pt_build_pkg      rc=0   warn=0  err=0  -              0s
  PASS       sim_ptw                rc=0   warn=0  err=0  1564/0        12s
  PASS       assert_labels          rc=0   warn=0  err=0  13/0           9s
  PASS       sim_pt_gen             rc=0   warn=0  err=0  -              0s
  PASS       sim_ptw_img            rc=0   warn=0  err=0  5465/0         6s
  time 28s
------------------------------------------------------------------
targets run: 283   total time: 708s
new failures: 0   known failures: 0   now passing: 0   stale entries: 0   malformed entries: 0   set errors: 0
logs: /tmp/regress.O1Sa23
pass NOT recorded: tracked changes or untracked rtl/ files, or HEAD moved during the run (push will be refused)
RESULT: PASS
```

### Problem 5: warm tools/regress.sh summary
```
==================================================================
REGRESSION SUMMARY  git 82e67d1 (dirty)
root /home/jeff/Development/jeffnye-gh/pacino
jobs 15 (default: 32 threads / 2, 31 GB / 2); priority: nice -n 10, ionice -c 3
==================================================================
== rtl/core/csr
  PASS       lint_csr_pkg           rc=0   warn=0  err=0  -              0s
  PASS       lint_csr_tb_pkg        rc=0   warn=0  err=0  -              0s
  PASS       sim_csr_tb_pkg         rc=0   warn=0  err=0  200/0          2s
  time 2s
== rtl/core/frontend/bpu
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       lint_loop_pred         rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_table        rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_table          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_brimli         rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_cntrl          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc                rc=0   warn=0  err=0  -              1s
  PASS       lint_ittage_table      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_cntrl      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_arb        rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage            rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_cntrl        rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_arb          rc=0   warn=0  err=0  -              0s
  PASS       lint_tage              rc=0   warn=0  err=0  -              1s
  PASS       lint_ras               rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_array         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru          rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb               rc=0   warn=0  err=0  -              0s
  PASS       lint_bp_cluster        rc=0   warn=0  err=0  -              2s
  PASS       sim                    rc=0   warn=0  err=0  31/0           0s
  PASS       sim_history            rc=0   warn=0  err=0  45442/0        9s
  PASS       sim_ubtb               rc=0   warn=0  err=0  341/0          7s
  PASS       sim_loop_pred          rc=0   warn=0  err=0  11548/0        4s
  PASS       sim_tage_table         rc=0   warn=0  err=0  15/0           0s
  PASS       sim_sc_table           rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_table_fast      rc=0   warn=0  err=0  7/0            0s
  PASS       sim_sc_brimli          rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_brimli_fast     rc=0   warn=0  err=0  7/0            0s
  PASS       sim_sc_cntrl           rc=0   warn=0  err=0  98/0           5s
  PASS       sim_sc                 rc=0   warn=0  err=0  144/0          3s
  PASS       sim_sc_fast            rc=0   warn=0  err=0  140/0          3s
  PASS       sim_ittage_table       rc=0   warn=0  err=0  32/0           0s
  PASS       sim_ittage_cntrl       rc=0   warn=0  err=0  147/0          3s
  PASS       sim_ittage             rc=0   warn=0  err=0  389/0          3s
  PASS       sim_ittage_fast        rc=0   warn=0  err=0  389/0          4s
  PASS       sim_bp_cluster         rc=0   warn=0  err=0  2112/0         5s
  PASS       sim_bp_cluster_init    rc=0   warn=0  err=0  2112/0        46s
  PASS       sim_ras                rc=0   warn=0  err=0  602/0          3s
  PASS       sim_ftb                rc=0   warn=0  err=0  239/0          3s
  PASS       sim_tage               rc=0   warn=0  err=0  109/0          3s
  PASS       sim_tage_fast          rc=0   warn=0  err=0  109/0          3s
  PASS       sim_tage_tasks         rc=0   warn=0  err=0  1/0            3s
  PASS       sim_tage_manual        rc=0   warn=0  err=0  1267/0         2s
  PASS       cov_history            rc=0   warn=0  err=0  45442/0        9s
  PASS       cov_ubtb               rc=0   warn=0  err=0  341/0          6s
  PASS       cov_loop_pred          rc=0   warn=0  err=0  11548/0        7s
  PASS       cov_tage_table         rc=0   warn=0  err=0  15/0           0s
  PASS       cov_tage               rc=0   warn=0  err=0  218/0          9s
  PASS       cov_bp_cluster         rc=0   warn=0  err=0  2112/0        23s
  PASS       cov_bpu                rc=0   warn=0  err=0  57564/0       32s
             sum of sub-runs:tage=218/0 tage_table=15/0 loop_pred=11548/0 bp_history=45442/0 ubtb=341/0
  PASS       lint_1slot             rc=0   warn=0  err=0  -              0s
  PASS       lint_loop_pred_1slot   rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_table_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_table_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_brimli_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_cntrl_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_1slot          rc=0   warn=0  err=0  -              1s
  PASS       lint_ittage_table_1slot rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_cntrl_1slot rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_arb_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_1slot      rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_cntrl_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_arb_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_1slot        rc=0   warn=0  err=0  -              1s
  PASS       lint_ras_1slot         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_array_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru_1slot    rc=0   warn=0  err=0  -              1s
  PASS       lint_ftb_cntrl_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_1slot         rc=0   warn=0  err=0  -              0s
  PASS       lint_bp_cluster_1slot  rc=0   warn=0  err=0  -              1s
  PASS       sim_1slot              rc=0   warn=0  err=0  27/0           0s
  PASS       sim_history_1slot      rc=0   warn=0  err=0  26590/0        3s
  PASS       sim_ubtb_1slot         rc=0   warn=0  err=0  341/0          3s
  PASS       sim_loop_pred_1slot    rc=0   warn=0  err=0  5765/0         2s
  PASS       sim_tage_table_1slot   rc=0   warn=0  err=0  11/0           0s
  PASS       sim_sc_table_1slot     rc=0   warn=0  err=0  6/0            1s
  PASS       sim_sc_table_fast_1slot rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_brimli_1slot    rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_brimli_fast_1slot rc=0   warn=0  err=0  6/0            1s
  PASS       sim_sc_cntrl_1slot     rc=0   warn=0  err=0  98/0           2s
  PASS       sim_sc_1slot           rc=0   warn=0  err=0  108/0          0s
  PASS       sim_sc_fast_1slot      rc=0   warn=0  err=0  104/0          1s
  PASS       sim_ittage_table_1slot rc=0   warn=0  err=0  26/0           0s
  PASS       sim_ittage_cntrl_1slot rc=0   warn=0  err=0  138/0          2s
  PASS       sim_ittage_1slot       rc=0   warn=0  err=0  258/0          3s
  PASS       sim_ittage_fast_1slot  rc=0   warn=0  err=0  258/0          4s
  PASS       sim_bp_cluster_1slot   rc=0   warn=0  err=0  1534/0         5s
  PASS       sim_bp_cluster_init_1slot rc=0   warn=0  err=0  1534/0        26s
  PASS       sim_ras_1slot          rc=0   warn=0  err=0  502/0          3s
  PASS       sim_ftb_1slot          rc=0   warn=0  err=0  186/0          3s
  PASS       sim_tage_1slot         rc=0   warn=0  err=0  105/0          2s
  PASS       sim_tage_fast_1slot    rc=0   warn=0  err=0  105/0          3s
  PASS       sim_tage_tasks_1slot   rc=0   warn=0  err=0  1/0            0s
  PASS       sim_tage_manual_1slot  rc=0   warn=0  err=0  534/0          3s
  time 278s
== rtl/core/frontend/decode
  PASS       lint_dec               rc=0   warn=0  err=0  -              0s
  PASS       sim_dec                rc=0   warn=0  err=0  1355/0        13s
  PASS       coverage               rc=0   warn=0  err=0  -             10s
  PASS       sim_dec_sweep          rc=0   warn=0  err=0  458752/0      41s
  PASS       oracle_dec_sweep       rc=0   warn=0  err=0  -              3s
  PASS       asm_dec_words          rc=0   warn=0  err=0  492/0          0s
  time 67s
== rtl/core/frontend/fe_top
  PASS       lint_fe_top            rc=0   warn=0  err=0  -              4s
  PASS       sim_fe_top             rc=0   warn=0  err=0  829/0        582s
  PASS       assert_labels          rc=0   warn=0  err=0  169/0          2s
  PASS       sim_fe_top_bare        rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_sv39        rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_loops       rc=0   warn=0  err=0  26/0           1s
  PASS       sim_fe_top_coro        rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_calls       rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_lp          rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_hist        rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_twocond     rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_ftbonly     rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_nest        rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_recur       rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_t0_uaon     rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_deep        rc=0   warn=0  err=0  18/0           1s
  PASS       sim_fe_top_indir       rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_region      rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_multistart  rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_cross       rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_rvc         rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_misp_call   rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_jals        rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_fencei      rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_cboinval    rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_uc_nc       rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_uc_io       rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_faults_s rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_pt_faults_h rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_napot_s  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_napot_h  rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_rsv_s    rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_rsv_h    rc=0   warn=0  err=0  20/0           2s
  PASS       sim_fe_top_pt_ad_s     rc=0   warn=0  err=0  21/0           1s
  PASS       sim_fe_top_pt_ad_h     rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_pt_inv      rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_zstar       rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_pt_gonly    rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_vsonly   rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_upriv    rc=0   warn=0  err=0  25/0           0s
  PASS       sim_fe_top_sv48        rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_sv57        rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_h57         rc=0   warn=0  err=0  24/0           1s
  PASS       sim_fe_top_pt_gonly_x4 rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_init_walk   rc=0   warn=0  err=0  34/0           0s
  time 599s
== rtl/core/frontend/fe_top/slot1
  PASS       lint_fe_top_1slot      rc=0   warn=0  err=0  -              3s
  PASS       sim_fe_top_1slot       rc=0   warn=0  err=0  827/0        568s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  161/0          2s
  PASS       sim_fe_top_bare_1slot  rc=0   warn=0  err=0  22/0           0s
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
  PASS       sim_fe_top_t0_uaon_1slot rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_deep_1slot  rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_indir_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_region_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_multistart_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_cross_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_rvc_1slot   rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_misp_call_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_jals_1slot  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_fencei_1slot rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_cboinval_1slot rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_uc_nc_1slot rc=0   warn=0  err=0  20/0           0s
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
  PASS       sim_fe_top_init_walk_1slot rc=0   warn=0  err=0  32/0           0s
  time 582s
== rtl/core/frontend/ftq
  PASS       lint_ftq_ftb_sched     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ftb_sched      rc=0   warn=0  err=0  67/0           1s
  PASS       lint_ftq_ptr           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ptr            rc=0   warn=0  err=0  207/0         12s
  PASS       lint_ftq_commit        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_commit         rc=0   warn=0  err=0  72/0           0s
  PASS       lint_ftq_entry         rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_entry          rc=0   warn=0  err=0  72/0           7s
  PASS       lint_ftq_meta          rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta           rc=0   warn=0  err=0  26/0           0s
  PASS       lint_ftq_status        rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_status         rc=0   warn=0  err=0  45/0           0s
  PASS       lint_ftq_shadow        rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_shadow         rc=0   warn=0  err=0  53/0           0s
  PASS       lint_ftq_npc           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_npc            rc=0   warn=0  err=0  84/0           1s
  PASS       lint_ftq_ifu           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ifu            rc=0   warn=0  err=0  237/0          3s
  PASS       lint_ftq_resolve       rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_resolve        rc=0   warn=0  err=0  146/0          4s
  PASS       lint_ftq_upd_conv      rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_upd_conv       rc=0   warn=0  err=0  192/0          3s
  PASS       lint_ftq               rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq                rc=0   warn=0  err=0  158/0          3s
  PASS       assert_labels          rc=0   warn=0  err=0  226/0          2s
  PASS       lint_ftq_ftb_sched_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ftb_sched_1slot rc=0   warn=0  err=0  67/0           0s
  PASS       lint_ftq_ptr_1slot     rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_ptr_1slot      rc=0   warn=0  err=0  207/0          2s
  PASS       lint_ftq_commit_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_commit_1slot   rc=0   warn=0  err=0  72/0           0s
  PASS       lint_ftq_entry_1slot   rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_entry_1slot    rc=0   warn=0  err=0  61/0           2s
  PASS       lint_ftq_meta_1slot    rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta_1slot     rc=0   warn=0  err=0  19/0           0s
  PASS       lint_ftq_status_1slot  rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_status_1slot   rc=0   warn=0  err=0  45/0           0s
  PASS       lint_ftq_shadow_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_shadow_1slot   rc=0   warn=0  err=0  53/0           1s
  PASS       lint_ftq_npc_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_npc_1slot      rc=0   warn=0  err=0  80/0           0s
  PASS       lint_ftq_ifu_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ifu_1slot      rc=0   warn=0  err=0  222/0          2s
  PASS       lint_ftq_resolve_1slot rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_resolve_1slot  rc=0   warn=0  err=0  105/0          2s
  PASS       lint_ftq_upd_conv_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_upd_conv_1slot rc=0   warn=0  err=0  106/0          3s
  PASS       lint_ftq_1slot         rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_1slot          rc=0   warn=0  err=0  158/0          3s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  205/0          2s
  time 63s
== rtl/core/frontend/ibuf
  PASS       lint_ibuf              rc=0   warn=0  err=0  -              0s
  PASS       sim_ibuf               rc=0   warn=0  err=0  52/0          11s
  PASS       assert_labels          rc=0   warn=0  err=0  3/0            0s
  time 11s
== rtl/core/frontend/icache
  PASS       lint_l1i               rc=0   warn=0  err=0  -              0s
  PASS       sim_l1i_emitted        rc=0   warn=0  err=0  67/0          11s
  PASS       sim_l1i                rc=0   warn=0  err=0  296/0          6s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0            6s
  time 23s
== rtl/core/frontend/ifu
  PASS       lint_ifu_rvc_exp       rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_predecode     rc=0   warn=0  err=0  -              1s
  PASS       lint_ifu_xlate         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_lbuf          rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_fetch         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_f3            rc=0   warn=0  err=0  -              1s
  PASS       lint_ifu_wb            rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_maint         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu               rc=0   warn=0  err=0  -              1s
  PASS       sim_ifu_rvc_exp        rc=0   warn=0  err=0  2457618/0     12s
  PASS       sim_ifu_predecode      rc=0   warn=0  err=0  63/0           6s
  PASS       sim_ifu                rc=0   warn=0  err=0  738/0         11s
  PASS       assert_labels          rc=0   warn=0  err=0  16/0           0s
  PASS       oracle_ifu_rvc_exp     rc=0   warn=0  err=0  -              1s
  time 33s
== rtl/core/frontend/l1i_param_chk
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       lint_neg               rc=0   warn=0  err=0  -              0s
  time 0s
== rtl/lib
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       sim                    rc=0   warn=0  err=0  34/0           1s
  time 1s
== rtl
  time 0s
== rtl/mmu/itlb
  PASS       lint_itlb              rc=0   warn=0  err=0  -              1s
  PASS       sim_itlb               rc=0   warn=0  err=0  228/0         12s
  PASS       sim_itlb_d2            rc=0   warn=0  err=0  231/0          8s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0            1s
  time 22s
== rtl/mmu/pmp
  PASS       lint_pmp_pma_chk       rc=0   warn=0  err=0  -              0s
  PASS       sim_pmp_pma_chk        rc=0   warn=0  err=0  73/0          11s
  PASS       lint_neg_pma           rc=0   warn=0  err=0  -              0s
  PASS       lint_neg_pma_dflt      rc=0   warn=0  err=0  -              0s
  time 11s
== rtl/mmu/ptw
  PASS       lint_ptw               rc=0   warn=0  err=0  -              0s
  PASS       lint_pt_build_pkg      rc=0   warn=0  err=0  -              1s
  PASS       sim_ptw                rc=0   warn=0  err=0  1564/0        14s
  PASS       assert_labels          rc=0   warn=0  err=0  13/0           8s
  PASS       sim_pt_gen             rc=0   warn=0  err=0  -              0s
  PASS       sim_ptw_img            rc=0   warn=0  err=0  5465/0         7s
  PASS       sim_pt_gen_noncanon    rc=0   warn=0  err=0  -              0s
  PASS       sim_pt_gen_mem_top     rc=0   warn=0  err=0  -              1s
  time 31s
------------------------------------------------------------------
targets run: 285   total time: 608s
new failures: 0   known failures: 0   now passing: 0   stale entries: 0   malformed entries: 0   set errors: 0
logs: /tmp/regress.QzmVrQ
pass NOT recorded: tracked changes or untracked rtl/ files, or HEAD moved during the run (push will be refused)
RESULT: PASS
```

### Problem 5: cold tools/regress.sh summary (CCACHE_DISABLE=1)
```
==================================================================
REGRESSION SUMMARY  git 82e67d1 (dirty)
root /home/jeff/Development/jeffnye-gh/pacino
jobs 15 (default: 32 threads / 2, 31 GB / 2); priority: nice -n 10, ionice -c 3
==================================================================
== rtl/core/csr
  PASS       lint_csr_pkg           rc=0   warn=0  err=0  -              0s
  PASS       lint_csr_tb_pkg        rc=0   warn=0  err=0  -              1s
  PASS       sim_csr_tb_pkg         rc=0   warn=0  err=0  200/0         13s
  time 14s
== rtl/core/frontend/bpu
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       lint_loop_pred         rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_table        rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_table          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_brimli         rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_cntrl          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc                rc=0   warn=0  err=0  -              1s
  PASS       lint_ittage_table      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_cntrl      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_arb        rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage            rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_cntrl        rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_arb          rc=0   warn=0  err=0  -              0s
  PASS       lint_tage              rc=0   warn=0  err=0  -              2s
  PASS       lint_ras               rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_array         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru          rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb               rc=0   warn=0  err=0  -              1s
  PASS       lint_bp_cluster        rc=0   warn=0  err=0  -              1s
  PASS       sim                    rc=0   warn=0  err=0  31/0          10s
  PASS       sim_history            rc=0   warn=0  err=0  45442/0       75s
  PASS       sim_ubtb               rc=0   warn=0  err=0  341/0         35s
  PASS       sim_loop_pred          rc=0   warn=0  err=0  11548/0       39s
  PASS       sim_tage_table         rc=0   warn=0  err=0  15/0          14s
  PASS       sim_sc_table           rc=0   warn=0  err=0  7/0           11s
  PASS       sim_sc_table_fast      rc=0   warn=0  err=0  7/0           13s
  PASS       sim_sc_brimli          rc=0   warn=0  err=0  7/0           13s
  PASS       sim_sc_brimli_fast     rc=0   warn=0  err=0  7/0           12s
  PASS       sim_sc_cntrl           rc=0   warn=0  err=0  98/0          25s
  PASS       sim_sc                 rc=0   warn=0  err=0  144/0         25s
  PASS       sim_sc_fast            rc=0   warn=0  err=0  140/0         25s
  PASS       sim_ittage_table       rc=0   warn=0  err=0  32/0          12s
  PASS       sim_ittage_cntrl       rc=0   warn=0  err=0  147/0         35s
  PASS       sim_ittage             rc=0   warn=0  err=0  389/0         68s
  PASS       sim_ittage_fast        rc=0   warn=0  err=0  389/0         68s
  PASS       sim_bp_cluster         rc=0   warn=0  err=0  2112/0       156s
  PASS       sim_bp_cluster_init    rc=0   warn=0  err=0  2112/0       202s
  PASS       sim_ras                rc=0   warn=0  err=0  602/0        116s
  PASS       sim_ftb                rc=0   warn=0  err=0  239/0         37s
  PASS       sim_tage               rc=0   warn=0  err=0  109/0         48s
  PASS       sim_tage_fast          rc=0   warn=0  err=0  109/0         47s
  PASS       sim_tage_tasks         rc=0   warn=0  err=0  1/0           27s
  PASS       sim_tage_manual        rc=0   warn=0  err=0  1267/0        75s
  PASS       cov_history            rc=0   warn=0  err=0  45442/0      161s
  PASS       cov_ubtb               rc=0   warn=0  err=0  341/0         83s
  PASS       cov_loop_pred          rc=0   warn=0  err=0  11548/0       89s
  PASS       cov_tage_table         rc=0   warn=0  err=0  15/0          31s
  PASS       cov_tage               rc=0   warn=0  err=0  218/0        113s
  PASS       cov_bp_cluster         rc=0   warn=0  err=0  2112/0       345s
  PASS       cov_bpu                rc=0   warn=0  err=0  57564/0      463s
             sum of sub-runs:tage=218/0 tage_table=15/0 loop_pred=11548/0 bp_history=45442/0 ubtb=341/0
  PASS       lint_1slot             rc=0   warn=0  err=0  -              0s
  PASS       lint_loop_pred_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_table_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_table_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_brimli_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_cntrl_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_1slot          rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_table_1slot rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_cntrl_1slot rc=0   warn=0  err=0  -              1s
  PASS       lint_ittage_arb_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_1slot      rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_cntrl_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_arb_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_1slot        rc=0   warn=0  err=0  -              1s
  PASS       lint_ras_1slot         rc=0   warn=0  err=0  -              1s
  PASS       lint_ftb_array_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_1slot         rc=0   warn=0  err=0  -              0s
  PASS       lint_bp_cluster_1slot  rc=0   warn=0  err=0  -              1s
  PASS       sim_1slot              rc=0   warn=0  err=0  27/0           9s
  PASS       sim_history_1slot      rc=0   warn=0  err=0  26590/0       53s
  PASS       sim_ubtb_1slot         rc=0   warn=0  err=0  341/0         34s
  PASS       sim_loop_pred_1slot    rc=0   warn=0  err=0  5765/0        36s
  PASS       sim_tage_table_1slot   rc=0   warn=0  err=0  11/0          13s
  PASS       sim_sc_table_1slot     rc=0   warn=0  err=0  6/0           11s
  PASS       sim_sc_table_fast_1slot rc=0   warn=0  err=0  6/0           11s
  PASS       sim_sc_brimli_1slot    rc=0   warn=0  err=0  6/0           12s
  PASS       sim_sc_brimli_fast_1slot rc=0   warn=0  err=0  6/0           12s
  PASS       sim_sc_cntrl_1slot     rc=0   warn=0  err=0  98/0          23s
  PASS       sim_sc_1slot           rc=0   warn=0  err=0  108/0         13s
  PASS       sim_sc_fast_1slot      rc=0   warn=0  err=0  104/0         13s
  PASS       sim_ittage_table_1slot rc=0   warn=0  err=0  26/0          11s
  PASS       sim_ittage_cntrl_1slot rc=0   warn=0  err=0  138/0         33s
  PASS       sim_ittage_1slot       rc=0   warn=0  err=0  258/0         51s
  PASS       sim_ittage_fast_1slot  rc=0   warn=0  err=0  258/0         50s
  PASS       sim_bp_cluster_1slot   rc=0   warn=0  err=0  1534/0       125s
  PASS       sim_bp_cluster_init_1slot rc=0   warn=0  err=0  1534/0       146s
  PASS       sim_ras_1slot          rc=0   warn=0  err=0  502/0         91s
  PASS       sim_ftb_1slot          rc=0   warn=0  err=0  186/0         33s
  PASS       sim_tage_1slot         rc=0   warn=0  err=0  105/0         46s
  PASS       sim_tage_fast_1slot    rc=0   warn=0  err=0  105/0         45s
  PASS       sim_tage_tasks_1slot   rc=0   warn=0  err=0  1/0           14s
  PASS       sim_tage_manual_1slot  rc=0   warn=0  err=0  534/0         66s
  time 3437s
== rtl/core/frontend/decode
  PASS       lint_dec               rc=0   warn=0  err=0  -              1s
  PASS       sim_dec                rc=0   warn=0  err=0  1355/0        52s
  PASS       coverage               rc=0   warn=0  err=0  -              9s
  PASS       sim_dec_sweep          rc=0   warn=0  err=0  458752/0      85s
  PASS       oracle_dec_sweep       rc=0   warn=0  err=0  -              3s
  PASS       asm_dec_words          rc=0   warn=0  err=0  492/0          0s
  time 150s
== rtl/core/frontend/fe_top
  PASS       lint_fe_top            rc=0   warn=0  err=0  -              4s
  PASS       sim_fe_top             rc=0   warn=0  err=0  829/0        699s
  PASS       assert_labels          rc=0   warn=0  err=0  169/0          2s
  PASS       sim_fe_top_bare        rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_sv39        rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_loops       rc=0   warn=0  err=0  26/0           0s
  PASS       sim_fe_top_coro        rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_calls       rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_lp          rc=0   warn=0  err=0  21/0           1s
  PASS       sim_fe_top_hist        rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_twocond     rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_ftbonly     rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_nest        rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_recur       rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_t0_uaon     rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_deep        rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_indir       rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_region      rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_multistart  rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_cross       rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_rvc         rc=0   warn=0  err=0  18/0           1s
  PASS       sim_fe_top_misp_call   rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_jals        rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_fencei      rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_cboinval    rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_uc_nc       rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_uc_io       rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_faults_s rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_pt_faults_h rc=0   warn=0  err=0  19/0           0s
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
  PASS       sim_fe_top_init_walk   rc=0   warn=0  err=0  34/0           1s
  time 715s
== rtl/core/frontend/fe_top/slot1
  PASS       lint_fe_top_1slot      rc=0   warn=0  err=0  -              4s
  PASS       sim_fe_top_1slot       rc=0   warn=0  err=0  827/0        651s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  161/0          2s
  PASS       sim_fe_top_bare_1slot  rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_sv39_1slot  rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_loops_1slot rc=0   warn=0  err=0  24/0           0s
  PASS       sim_fe_top_coro_1slot  rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_calls_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_lp_1slot    rc=0   warn=0  err=0  21/0           1s
  PASS       sim_fe_top_hist_1slot  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_twocond_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_ftbonly_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_nest_1slot  rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_recur_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_t0_uaon_1slot rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_deep_1slot  rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_indir_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_region_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_multistart_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_cross_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_rvc_1slot   rc=0   warn=0  err=0  18/0           1s
  PASS       sim_fe_top_misp_call_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_jals_1slot  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_fencei_1slot rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_cboinval_1slot rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_uc_nc_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_uc_io_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_faults_s_1slot rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_pt_faults_h_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_napot_s_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_napot_h_1slot rc=0   warn=0  err=0  20/0           1s
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
  PASS       sim_fe_top_init_walk_1slot rc=0   warn=0  err=0  32/0           0s
  time 666s
== rtl/core/frontend/ftq
  PASS       lint_ftq_ftb_sched     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ftb_sched      rc=0   warn=0  err=0  67/0          15s
  PASS       lint_ftq_ptr           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ptr            rc=0   warn=0  err=0  207/0         35s
  PASS       lint_ftq_commit        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_commit         rc=0   warn=0  err=0  72/0          14s
  PASS       lint_ftq_entry         rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_entry          rc=0   warn=0  err=0  72/0          24s
  PASS       lint_ftq_meta          rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta           rc=0   warn=0  err=0  26/0          13s
  PASS       lint_ftq_status        rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_status         rc=0   warn=0  err=0  45/0          13s
  PASS       lint_ftq_shadow        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_shadow         rc=0   warn=0  err=0  53/0          15s
  PASS       lint_ftq_npc           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_npc            rc=0   warn=0  err=0  84/0          14s
  PASS       lint_ftq_ifu           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ifu            rc=0   warn=0  err=0  237/0         27s
  PASS       lint_ftq_resolve       rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_resolve        rc=0   warn=0  err=0  146/0         36s
  PASS       lint_ftq_upd_conv      rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_upd_conv       rc=0   warn=0  err=0  192/0         27s
  PASS       lint_ftq               rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq                rc=0   warn=0  err=0  158/0         37s
  PASS       assert_labels          rc=0   warn=0  err=0  226/0          1s
  PASS       lint_ftq_ftb_sched_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ftb_sched_1slot rc=0   warn=0  err=0  67/0          14s
  PASS       lint_ftq_ptr_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ptr_1slot      rc=0   warn=0  err=0  207/0         31s
  PASS       lint_ftq_commit_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_commit_1slot   rc=0   warn=0  err=0  72/0          14s
  PASS       lint_ftq_entry_1slot   rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_entry_1slot    rc=0   warn=0  err=0  61/0          22s
  PASS       lint_ftq_meta_1slot    rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta_1slot     rc=0   warn=0  err=0  19/0          12s
  PASS       lint_ftq_status_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_status_1slot   rc=0   warn=0  err=0  45/0          13s
  PASS       lint_ftq_shadow_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_shadow_1slot   rc=0   warn=0  err=0  53/0          13s
  PASS       lint_ftq_npc_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_npc_1slot      rc=0   warn=0  err=0  80/0          13s
  PASS       lint_ftq_ifu_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ifu_1slot      rc=0   warn=0  err=0  222/0         25s
  PASS       lint_ftq_resolve_1slot rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_resolve_1slot  rc=0   warn=0  err=0  105/0         28s
  PASS       lint_ftq_upd_conv_1slot rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_upd_conv_1slot rc=0   warn=0  err=0  106/0         24s
  PASS       lint_ftq_1slot         rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_1slot          rc=0   warn=0  err=0  158/0         32s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  205/0          2s
  time 519s
== rtl/core/frontend/ibuf
  PASS       lint_ibuf              rc=0   warn=0  err=0  -              0s
  PASS       sim_ibuf               rc=0   warn=0  err=0  52/0          45s
  PASS       assert_labels          rc=0   warn=0  err=0  3/0            0s
  time 45s
== rtl/core/frontend/icache
  PASS       lint_l1i               rc=0   warn=0  err=0  -              1s
  PASS       sim_l1i_emitted        rc=0   warn=0  err=0  67/0          31s
  PASS       sim_l1i                rc=0   warn=0  err=0  296/0         41s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0           41s
  time 114s
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
  PASS       sim_ifu_predecode      rc=0   warn=0  err=0  63/0          24s
  PASS       sim_ifu                rc=0   warn=0  err=0  738/0        251s
  PASS       assert_labels          rc=0   warn=0  err=0  16/0           0s
  PASS       oracle_ifu_rvc_exp     rc=0   warn=0  err=0  -              1s
  time 305s
== rtl/core/frontend/l1i_param_chk
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       lint_neg               rc=0   warn=0  err=0  -              1s
  time 1s
== rtl/lib
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       sim                    rc=0   warn=0  err=0  34/0          14s
  time 14s
== rtl
  time 0s
== rtl/mmu/itlb
  PASS       lint_itlb              rc=0   warn=0  err=0  -              1s
  PASS       sim_itlb               rc=0   warn=0  err=0  228/0         81s
  PASS       sim_itlb_d2            rc=0   warn=0  err=0  231/0         78s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0            0s
  time 160s
== rtl/mmu/pmp
  PASS       lint_pmp_pma_chk       rc=0   warn=0  err=0  -              0s
  PASS       sim_pmp_pma_chk        rc=0   warn=0  err=0  73/0          47s
  PASS       lint_neg_pma           rc=0   warn=0  err=0  -              0s
  PASS       lint_neg_pma_dflt      rc=0   warn=0  err=0  -              0s
  time 48s
== rtl/mmu/ptw
  PASS       lint_ptw               rc=0   warn=0  err=0  -              0s
  PASS       lint_pt_build_pkg      rc=0   warn=0  err=0  -              1s
  PASS       sim_ptw                rc=0   warn=0  err=0  1564/0       141s
  PASS       assert_labels          rc=0   warn=0  err=0  13/0         133s
  PASS       sim_pt_gen             rc=0   warn=0  err=0  -             11s
  PASS       sim_ptw_img            rc=0   warn=0  err=0  5465/0       139s
  PASS       sim_pt_gen_noncanon    rc=0   warn=0  err=0  -             11s
  PASS       sim_pt_gen_mem_top     rc=0   warn=0  err=0  -             11s
  time 447s
------------------------------------------------------------------
targets run: 285   total time: 3445s
new failures: 0   known failures: 0   now passing: 0   stale entries: 0   malformed entries: 0   set errors: 0
logs: /tmp/regress.ls1W1T
pass NOT recorded: tracked changes or untracked rtl/ files, or HEAD moved during the run (push will be refused)
RESULT: PASS
```

### tools/regress_weekly.sh summary
```
==================================================================
WEEKLY REGRESSION SUMMARY  git 82e67d1 (dirty)
root /home/jeff/Development/jeffnye-gh/pacino
modes sv39 sv48 sv57
jobs 15 (default: 32 threads / 2, 31 GB / 2); priority: nice -n 10, ionice -c 3
==================================================================
== rtl/core/frontend/fe_top
  PASS       sim_fe_top             sv39  rc=0   warn=0  err=0  829/0         19s
  PASS       sim_fe_top             sv48  rc=0   warn=0  err=0  829/0         17s
  PASS       sim_fe_top             sv57  rc=0   warn=0  err=0  829/0         17s
  time 53s
== rtl/core/frontend/fe_top/slot1
  PASS       sim_fe_top_1slot       sv39  rc=0   warn=0  err=0  827/0         16s
  PASS       sim_fe_top_1slot       sv48  rc=0   warn=0  err=0  827/0         15s
  PASS       sim_fe_top_1slot       sv57  rc=0   warn=0  err=0  827/0         14s
  time 45s
== rtl/mmu/itlb
  PASS       sim_itlb               sv39  rc=0   warn=0  err=0  228/0          5s
  PASS       sim_itlb               sv48  rc=0   warn=0  err=0  228/0          5s
  PASS       sim_itlb               sv57  rc=0   warn=0  err=0  228/0          4s
  PASS       sim_itlb_d2            sv39  rc=0   warn=0  err=0  231/0          3s
  PASS       sim_itlb_d2            sv48  rc=0   warn=0  err=0  231/0          4s
  PASS       sim_itlb_d2            sv57  rc=0   warn=0  err=0  231/0          3s
  time 24s
== rtl/mmu/ptw
  PASS       sim_ptw                sv39  rc=0   warn=0  err=0  1564/0         6s
  PASS       sim_ptw                sv48  rc=0   warn=0  err=0  1564/0         6s
  PASS       sim_ptw                sv57  rc=0   warn=0  err=0  1564/0         5s
  time 18s
------------------------------------------------------------------
runs: 15   total time: 53s
failures: 0   set errors: 0
logs: /tmp/regress_weekly.z8Wz2Y
RESULT: PASS
```

## Assumptions made not explicit in the prompt
- "Warm" for Problem 5's first run means "as it is", as Specific
  Requirements says, not "with every compile a cache hit". The cache
  turned out to hold no entry for the new tb_fe_top C++, and that is
  reported, not worked around. A fourth regress.sh run would have broken
  the three-run limit.
- In the time table, "fe_top in all" is the fe_top job's time, as
  regress.sh reports it.

## Decisions made not explicit in the prompt
- NEVER A STALE BINARY: build first, rather than stop with a message.
  A target run alone then always works, and the freshness test is the
  same under -B and without it.
- The freshness test uses Verilator's own dependency file (Vtb__ver.d),
  not a source list kept by hand, so a new `include is covered with no
  Makefile change.
- TB_DIR was made absolute ($(FE_TOP)/tb) so that Vtb__ver.d and the
  find in the test name every file by its full path, whichever
  directory make runs in.
- The slot1 targets run `make -C $(FE_TOP)` with
  VER_OUT=slot1/obj_1slot, not make in slot1/. Reason:
  - tb_fe_top.sv:3436 reads `$readmemh("../ifu/tb/ifu_rvc_exp_oracle.hex",
    ...)`, a path relative to the working directory. Program zstar uses
    it.
  - A first version ran in slot1/, and zstar failed there:
    "%Warning: ../ifu/tb/ifu_rvc_exp_oracle.hex:0: $readmem file not
    found", 4 checks failed.
  - .sv files are outside this task's authority.
  With make in fe_top/, every output still lands in slot1/obj_1slot_fe_top
  (shown above).
  Proposed for a later task with .sv authority: build that path from a
  plusarg or from RVA_ROOT, so the 1-slot make can run in its own
  directory.
- The slot1 Makefile reads its target list from the fe_top Makefile's
  regress_list, so a program added to fe_top gets its _1slot twin with
  no edit to slot1.
- .NOTPARALLEL: was added to the fe_top Makefile, so that make -j
  cannot start two builds into one object directory.

## RVA23 compliance risks and gaps noticed
None. This task changed only the build and the regression.

## Deferred Work
- The 5-minute warm figure still needs one regress.sh run with a
  current cache. The weekly run shows that sim_fe_top then takes 17 to
  19s, but a full warm run was not measured in this task.
- bpu: the next step, per the Task Overview. Warm, sim_bp_cluster_init
  (47s), its 1-slot twin (25s) and the seven cov targets (88s) are
  58% of the job. Cold, bpu is a single 3437s job, and splitting its
  1-slot half out as fe_top's was would let the halves run in parallel.
- tb_fe_top.sv:3436, the path relative to the working directory (see
  Decisions).
- The stale build directories fe_top/obj_dir and fe_top/obj_1slot_fe_top
  can be deleted.

## Other Notes
Proposed planning text. PROJECT_CORE.md "The regression" does not
describe the job layout, and nothing it says becomes false, so no
change is required. If Jeff wants the mechanism recorded, proposed for
the end of its first paragraph:
  A Makefile's targets run in one job, one after another; separate
  Makefiles run in parallel. A target that needs a model another
  target of the same job builds reuses it when it is current, checked
  against Verilator's dependency file, the Makefiles and the build
  flags, so make -B rebuilds nothing twice (INFRA-014: fe_top's
  fe_top_bin). fe_top's 1-slot targets are a Makefile of their own,
  rtl/core/frontend/fe_top/slot1, for that reason.

Proposed tools/known_failures.txt entries: none.

rtl/Vars.mk was changed (CCACHE_BASEDIR) and restored to its 82e67d1
content. It is not in Files Modified.

Rules followed, and deviations:
- No git command was run. regress.sh made its own.
- tools/regress.sh ran three times, each in the background, with no
  file changed while it ran. tools/regress_weekly.sh ran once, in the
  background. tools/regress_demo.sh was not run.
- The Grep tool was not available in this session, so searches used
  `grep -n` with literal paths through Bash, as the task allows. Some of
  them piped into wc, sort or uniq to count. None of those pipes cut a
  summary, and every summary above was read whole with Read.
- Other Bash commands that touched files:
  - rm -rf rtl/core/frontend/fe_top/obj_fe_top, for the clean-directory
    case;
  - touch rtl/core/frontend/fe_top/tb/models/fe_tb_mem.svh, for the
    stale-source case. That changes its time stamp only, not its
    content;
  - one echo, in a command that printed a label.
- The scratch copy was made in the session scratchpad
  (scratchpad/tree) with one mkdir and one cp -r --parents. Every
  scratch build set RVA_ROOT to the copy, and the verbose compile line
  was checked.
- The copy was made while rtl/Vars.mk still held CCACHE_BASEDIR, so the
  copy's Vars.mk holds it too. That is what the Problem 3 test needed.
  The Problem 4 scratch runs do not use ccache settings.
- No ccache setting outside the tree was changed. The cache was not
  cleared.
- No Firefox folder was created.

Files read outside Context Loaded:
- rtl/CLAUDE.md, loaded automatically.
- rtl/mmu/ptw/tb/pt_gen.sv :1-220, for the error messages, and its
  scratch copy.
- rtl/mmu/ptw/tb/pt_gen_sample.txt.
- rtl/core/frontend/l1i_param_chk/Makefile, the lint_neg model.
- examples/fe_demo/Makefile, grep of its includes only (:58 Vars.mk,
  :77 fe_top_srcs.mk). It does not include the fe_top Makefile.
- A grep of every rtl/ Makefile for Vars.mk, to see what
  CCACHE_BASEDIR would reach.
- A grep of rtl/core/frontend/fe_top/tb for readmem and plusargs, and
  tb_fe_top.sv:3436.
- Build output: obj_fe_top/Vtb__ver.d line 1, greps of generated .cpp
  files in the tree and the copy, and ls of fe_top/ and obj_fe_top/.
- prompts/BP-149.md: Test Case Results and Other Notes, as allowed, and
  :89 and :671-682 for the run time.
- Logs in the scratchpad and under /tmp/regress.*.

## Files Modified
- rtl/core/frontend/fe_top/Makefile
- rtl/core/frontend/fe_top/slot1/Makefile
- rtl/mmu/ptw/Makefile
- rtl/mmu/ptw/tb/pt_gen_noncanon.txt
- prompts/INFRA-014.md

:: RESULTS:END ::

:: CONTEXT:START ::
# Context Report
Compactions: 1
Run time: 13m.19s active, 1h.27m.23s wall (2026-11-15T15:14:10Z -> 2026-11-15T16:41:33Z, /run INFRA-014)

Context used: 18%

Model: claude-opus-5-5
Tokens: 176.3k / 1m (18%)

| Category | Tokens | Percentage |
|----------|--------|------------|
| System prompt | 3k | 0.3% |
| System tools | 21.1k | 2.1% |
| MCP server instructions | 39 | 0.0% |
| MCP tools (deferred) | 1.2k | 0.1% |
| System tools (deferred) | 30.2k | 3.0% |
| Memory files | 6.6k | 0.7% |
| Skills | 6k | 0.6% |
| Messages | 139.5k | 14.0% |
| Free space | 790.7k | 79.1% |
| Autocompact buffer | 33k | 3.3% |

Memory files:
| Type | Path | Tokens |
|------|------|--------|
| Project | CLAUDE.md | 4.7k |
| AutoMem | memory/MEMORY.md | 1.9k |
:: CONTEXT:END ::
