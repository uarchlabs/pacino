<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header 
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | INFRA-015               |                          |
| Date         | 2026.11.15              |                          |
| Module       | fe_top tb               | TD#201, cold compile     |
| Run time     |                         |                          |
| Ctx %        |                         |                          |
| Model        |                         |                          |
| Resume sha   |                         |                          |
| PA session   | 085                     |                          |

Task:   [ ] experiment  [x] implementation  [x] debug
        [x] cleanup     [x] testbench       [x] verification
Mode:   [x] automated   [ ] manual          [ ] interactive
Status: [x] in-progress [ ] complete        [ ] abandoned

# Task Overview
A cold compile of tb_fe_top takes 9 to 12 minutes per slot count. After
any edit to tb_fe_top's sources, that compile sets the time of the
whole regression (INFRA-014). This task closes TD#201:
1. Measure where the cold compile goes: which generated C++ files and
   functions take the time, and what is inlined into them.
2. Cut it by the cheapest means that work, without changing a check.
3. Make tb_fe_top.sv:3436 read its data file by a path that does not
   depend on the working directory.
Nothing a program checks may change.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion 

## Claude.code Console Output

## My Assessment

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
INFRA-015

## Context Loaded
@rtl/CLAUDE.md
@rtl/core/frontend/fe_top/Makefile
@rtl/core/frontend/fe_top/slot1/Makefile
@rtl/core/frontend/fe_top/fe_top_srcs.mk
@rtl/core/frontend/fe_top/tb/models/fe_tb_csr.svh
@rtl/core/frontend/fe_top/tb/models/fe_tb_backend.svh

## Context Comments
TD#201 (PROJECT_STATUS.md, Performance / Verification Debt) records
the problem. In short: a cold compile of tb_fe_top takes 9 to 12
minutes per slot count, and BP-149 attributed it to module tasks
inlined at every call. It also records the relative path at
tb_fe_top.sv:3436, which forces slot1's targets to run make in fe_top/.

BP-149 fixed the same kind of fault in tb_ptw. The IA may read
prompts/BP-149.md lines 868-890 (the COMPILE TIME note) and 1385-1398,
read only.

THE BASELINE is the regress.sh run of INFRA-014, 285 targets, RESULT:
PASS. The IA may read prompts/INFRA-014.md's Test Case Results, read
only, for its check counts and times.

tb_fe_top.sv (4,054 lines), fe_tb_writer.svh, the other fe_top models
and the examples/fe_demo sources are not loaded. The IA reads the parts
the work needs, and the examples/fe_demo files only to keep their
callers working.

## Hypothesis
BP-149's note on tb_ptw: Verilator inlines a module task at every call
site. One initial block that runs every test became one C++ function
holding 1574 inlined copies of a package pack function, and gcc spent
more than 30 minutes on it. The fix there made each cs_* task one call
to a class method, and kept the test list at the top level of the
initial block. That took the compile to 2 min 15 s.

tb_fe_top has the same shape: 41 program tasks, dispatched by run_prog
from one initial block, each calling the CSR helpers and reset_all. The
cause is expected to be the same, but it is measured first.

## Background
Checked by the PA against the tree at 790dfbe. The IA confirms each
fact it uses.
- fe_tb_csr.svh is a shared model, included in module tb by tb_fe_top
  and by examples/fe_demo/tb/tb_fe_demo.sv (:78). Its tasks are
  module tasks:
  - csr_sync (:27) drives fe_cfg, fe_csr and ptw_csr from
    csr_tb_pkg::pack_fe_cfg, pack_fe_csr and pack_ptw_csr.
  - Every other helper ends in csr_sync: csr_priv, csr_wr_satp,
    csr_wr_vsatp, csr_wr_hgatp, csr_satp_mode, csr_vsatp_mode,
    csr_hgatp_mode_vmid, csr_menv_adue, csr_henv_adue, csr_envcfg,
    csr_pmp, set_h2, set_h2_at, use_smode, pmp_page and pmp_all.
- tb_fe_top.sv:
  - reset_all (:1185), and run_prog (:3956), which dispatches the 41
    programs by name.
  - The initial blocks are at :594, :910, :1085, :4021 and :4049.
  - :3436 is `$readmemh("../ifu/tb/ifu_rvc_exp_oracle.hex", rvc_orc)`,
    in program zstar.
- fe_tb_writer.svh's pw_c is a class. Its methods are not inlined.
- The build: fe_top Makefile FE_BUILD (:204-210) runs `$(VERILATOR)
  --binary` with VER_FLAGS, SIM_EXTRA_FLAGS and COMMON. FE_VER_FLAGS
  and the other shared flags are in fe_top_srcs.mk, which the fe_demo
  Makefile also includes (:77). No Verilator build-parallelism or
  output-split flag is set.
- INFRA-014: the fe_top and slot1 jobs each make one tb_fe_top build
  per run. sim_fe_top took 582s to 699s cold in its runs, and 17 to
  19s warm. Verilator writes absolute source paths into the generated
  C++, so any change to the generated C++ is a cold compile.
- slot1/Makefile runs `$(MAKE) -C $(FE_TOP) <t>` with
  VER_OUT=slot1/obj_1slot, because of :3436.

## Binding Previous Decisions
Jeff, session-085, as recorded in PROJECT_STATUS.md TD#201 and in this
task:
- MEASURE FIRST. Before any change, one cold build of tb_fe_top is
  timed at each slot count, with CCACHE_DISABLE=1 on the command, and
  the generated C++ is examined:
  - the time of each C++ compile, from the build log or by timing
    each object;
  - the largest .cpp files and the largest functions in them;
  - what is inlined there, and how many copies of each.
- THE CHEAPEST MEANS THAT WORK. The IA tries the means in this order,
  measures each, and keeps what helps. Each trial is reported with its
  cold build time, whether it was kept or not.
  1. Verilator build options, with no source change: the build's job
     count (--build-jobs) and splitting of large files and functions
     (--output-split, --output-split-cfuncs). A flag set in
     fe_top_srcs.mk reaches fe_demo too; one set only in the fe_top
     Makefile does not. The IA says where each kept flag lives and
     why.
  2. Stopping the inlining that the measurement shows. Either the
     Verilator no_inline_task metacomment on the tasks concerned, or
     the BP-149 treatment: the task body becomes one call to a class
     method. The IA chooses by the measured result. A class added here
     follows the TOOLS-007 self-store loop rule (rtl/CLAUDE.md).
  3. The structure of the dispatch: run_prog and the initial block
     that calls it. This is done only if 1 and 2 leave a single
     function that still dominates.
- THE GOAL is a cold build under 3 minutes per slot count. It is a
  goal, not a gate. If it is not met, the IA reports what holds the
  time.
- NOTHING CHECKED CHANGES. Every fe_top and slot1 target gives its
  INFRA-014 result and check count, at every PT_MODE. assert_labels
  gives its INFRA-014 count. No program, check or expected value
  changes.
- THE SHARED MODELS. fe_tb_csr.svh and the other shared models keep
  every task name and argument list that examples/fe_demo calls, with
  the same effect. tb_fe_demo is built once at the end (`make -C
  examples/fe_demo build`), not run (fe_demo_tb_decisions.md FDT-2a).
  The build time of tb_fe_demo before and after is reported. Nothing
  under examples/ changes.
- THE DATA FILE PATH. tb_fe_top.sv:3436 reads the oracle file by a
  path that works from any working directory: a plusarg the Makefile
  passes, or a define built from RVA_ROOT. The IA reports which. Then
  slot1's targets run make in slot1/ itself, if the fe_top Makefile's
  rules allow it with no other change. If they do not, slot1 stays as
  it is, and the reason is reported.
- AUTHORITY. The IA may change any file under rtl/ that the work
  needs: testbenches, the shared models, Makefiles and .mk files. It
  does not change any RTL module (rtl/**/rtl/), examples/, tools/ or
  planning/. It does not stop to ask permission for such a change.

## Specific Requirements

Problem 0: the baseline
- Report each Background fact found false, with what the files say.
- Do not run a baseline regress.sh: INFRA-014's final run is the
  baseline.
- Make the MEASURE FIRST builds and report them: time, files,
  functions and the inlining counts, at both slot counts.

Problem 1: the compile
Apply THE CHEAPEST MEANS THAT WORK.
Acceptance:
- The trial table: each means, the cold build time at each slot count,
  and kept or not.
- The final cold build time at each slot count, measured the same way
  as Problem 0's, and against the 3-minute goal.
- lint_fe_top is clean in both slot builds, with no new waiver.
- sim_fe_top and sim_fe_top_1slot give their INFRA-014 counts at sv39,
  sv48 and sv57.

Problem 2: the data file path
Apply THE DATA FILE PATH.
Acceptance:
- sim_fe_top_zstar passes when tb_fe_top's binary is run from a
  directory other than fe_top/. Show it.
- If slot1 now runs make in slot1/, its targets still write only under
  slot1/. List the files written, as INFRA-014 did.

Problem 3: the measurement
- tools/regress.sh runs once at the end, in the background. Its fe_top
  and slot1 builds are cold, because the generated C++ has changed, so
  this run is the after-an-edit figure that TD#201 is about. Report its
  summary whole and its total time, against INFRA-014's runs.
- tools/regress_weekly.sh runs once after it. Report its summary whole.
- tb_fe_demo builds.

## Constraints
- The planning files are read only. Results Capture proposes the
  exact text, but only for the planning files in Context Loaded. The
  PA updates the others.
- The IA runs no git command. Running tools/regress.sh, which makes
  git calls of its own, is permitted; that grant is to run the
  script, not any command it contains.
- tools/regress.sh runs once, at the end, in the background. The IA
  waits for it to finish, and no file changes while it runs. Its
  summary goes into Results Capture whole, sha line included, not cut
  by a pipe. During the work, run only the targets a change affects.
- tools/regress_demo.sh is not run (fe_demo_tb_decisions.md FDT-2a).
- COMMANDS (CLAUDE.md Commands, Experiment File Rules):
  - A Bash command names its files by literal paths. It uses no shell
    variable (no S=..., no $S, no $? and no ${PIPESTATUS[...]}), no
    $(...) or backticks, no loop and no xargs. The one exception is an
    environment setting on the command itself, such as
    CCACHE_DISABLE=1.
  - Files are read and searched with the Read, Grep and Glob tools.
    If the Grep tool is not available in the session, `grep -n` with
    literal paths through Bash is allowed; say so in Results Capture.
  - Files are created and changed with the Write and Edit tools. No
    sed -i, no heredoc, no redirect, except that a build or run log
    may be redirected to a file in the scratchpad.
  - Every command runs from the repo root: no cd, except a subshell
    ( cd <dir> && ... ) where a tool must run in another directory.
- No ccache setting is changed, and the cache is not cleared.
  CCACHE_DISABLE=1 on a command is how a cold build is made.
- A cold build is timed alone, with no other build running, so the
  times can be compared.

## Deliverables
Note: If a new module is to be created ensure that claude.code is allowed
or told to modify the Makefile for lint checking at the minimum.

Files the IA may change:
- the files under rtl/ the work needs (Binding, AUTHORITY);
- prompts/INFRA-015.md, Results Capture filled in below.

Results Capture reports:
- Problem 0: the false facts, and the measurement at both slot counts.
- The trial table, and what was kept, with each change by file and
  line.
- The final cold build times, against Problem 0's and the goal.
- The data file path, and whether slot1 now runs in its own directory.
- The tb_fe_demo build result, and its time before and after.
- The regress.sh summary, whole, its total time, and every check count
  that changed against INFRA-014's. The regress_weekly.sh summary,
  whole.
- The text proposed for TD#201's closing.

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary
RESULTS NOT YET WRITTEN -- replace this line when filling in.

## Test Matrix (testbench sessions only, omit otherwise)
For each test case document:
- Test name
- Rule or rules exercised (reference rule doc and row/table)
- Setup: initial RAM state, struct fields driven
- Stimulus: which signals asserted and values
- Expected outcome: which RAM entries change and how
- Pass/fail criterion

## What was delivered

## Test Case Results

## Assumptions made not explicit in the prompt

## Decisions made not explicit in the prompt

## RVA23 compliance risks and gaps noticed

## Deferred Work

## Other Notes

## Files Modified
- List every file changed, one file per line, as a bullet.
- No prose. File paths only. Example:
- rtl/core/frontend/bpu/rtl/tage_cntrl.sv

:: RESULTS:END ::

:: CONTEXT:START ::

:: CONTEXT:END ::
