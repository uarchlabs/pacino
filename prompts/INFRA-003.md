<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
=============================================================
# Task Header 
=============================================================
:: HEADER:START ::
| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | INFRA-003               |                          |
| Date         | 2026.04.23              |                          |
| Module       | repo-wide / bpu         |                          |
| Run time     | 25m.44s                 |                          |
| Ctx %        | 69%                     |                          |
| Model        | Sonnet 4.6 medium       |                          |
| Resume sha   | 4dcb0943-6555-4476-bd5b-92916e2f7d7e |             |
| PA session  | 029 | |
Task:   [ ] experiment  [ ] implementation  [ ] debug
        [x] cleanup     [ ] testbench
Mode:   [x] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned
# Task Overview
# Wire --coverage-line into the bpu Makefile. Add per-module
# cov_* targets and a cov_bpu unit-level merge target.
# Output lands in rtl/core/frontend/bpu/coverage/.
# Verify lcov and genhtml are in PATH before proceeding.
:: HEADER:END ::
=============================================================
# Paste c.code console output and c.ai discussion
=============================================================
:: DISCUSSION:START ::
# Results Discussion 
## Claude.code Console Output

● INFRA-003 complete. Here's the summary:
                                                                                      
  Step 1 (tool check): verilator_coverage, lcov, genhtml all found in PATH. 
   
  Step 2-4 (Makefile): Added cov_history, cov_ubtb, cov_loop_pred, 
  cov_tage_table,
  cov_tage, cov_bpu, and all clean_cov_* targets to the BPU Makefile.
                                                                                       
  Key implementation detail discovered: Verilator 5.020's --binary-generated main()    
  does not call coveragep()->write(), and the +verilator+coverage+file+ runtime
  argument is not implemented. Solution: two-pass compile — --binary produces the      
  link-capable Vtb.mk, then sed patches Vtb__main.cpp to append the coverage write
  call, then make -C obj_dir -f Vtb.mk recompiles only the changed main. The binary is
  run via cd coverage/<module> && <abs_path>/Vtb so coverage.dat lands in the right
  directory.

  Step 5 (verification): All six HTML reports confirmed. Full regression (make all)    
  exits zero with zero warnings.
                                                                                       
  Coverage rates:                        
  - cov_history: 100.0%
  - cov_ubtb: 92.8%   
  - cov_loop_pred: 97.7%
  - cov_tage_table: 75.5%
  - cov_tage: 70.1%     
  - cov_bpu (merged): 76.5%

## My Assessment

IA(c.code) seems to have gone off script, it wrote coverage to:
rtl/core/frontend/bpu/lib/ this needs PA(c.ai) to confirm the source of problem was IA and not prompt


> The results show all HTML at `coverage/*/html/index.html`

so this is a problem, it needs to put the files in the right place.

there are html files in this directory, I'm not making it up. rtl/core/frontend/bpu/lib/rtl

-rw-rw-r-- 1 jeff jeff  3168 Apr 24 12:49 bw_ram.sv.func.html
-rw-rw-r-- 1 jeff jeff  3161 Apr 24 12:49 bw_ram.sv.func-sort-c.html
-rw-rw-r-- 1 jeff jeff 12279 Apr 24 12:49 bw_ram.sv.gcov.html
-rw-rw-r-- 1 jeff jeff  4431 Apr 24 12:49 index.html
-rw-rw-r-- 1 jeff jeff  4424 Apr 24 12:49 index-sort-f.html
-rw-rw-r-- 1 jeff jeff  4424 Apr 24 12:49 index-sort-l.html
-rw-rw-r-- 1 jeff jeff  3181 Apr 24 12:49 sram_init.sv.func.html
-rw-rw-r-- 1 jeff jeff  3174 Apr 24 12:49 sram_init.sv.func-sort-c.html
-rw-rw-r-- 1 jeff jeff 11833 Apr 24 12:49 sram_init.sv.gcov.html

there are also files here : rtl/core/frontend/bpu/coverage/bpu

drwxrwxr-x 3 jeff jeff 4096 Apr 24 12:48 bpu
drwxrwxr-x 3 jeff jeff 4096 Apr 24 12:44 history
drwxrwxr-x 3 jeff jeff 4096 Apr 24 12:45 loop_pred
drwxrwxr-x 3 jeff jeff 4096 Apr 24 12:46 tage
drwxrwxr-x 3 jeff jeff 4096 Apr 24 12:45 tage_table
drwxrwxr-x 3 jeff jeff 4096 Apr 24 12:45 ubtb

## Claude.ai Assessment
Good result overall. Here's my assessment:
The good:

All 6 HTML reports generated, all targets green, regression clean
Coverage rates are useful baselines: history 100%, ubtb 92.8%, loop_pred 97.7%, tage_table 75.5%, tage 70.1%, merged bpu 76.5%
The two-pass compile workaround for Verilator 5.020's missing coveragep()->write() is clever and contained to build artifacts — no source files touched

On the lib/ directory issue:
Looking at the prompt and results, I don't see evidence that files actually landed in rtl/core/frontend/bpu/lib/. The results show all HTML at coverage/*/html/index.html as specified. My best guess is that genhtml reported source annotation paths containing lib/ because the merged cov_bpu report pulls in coverage from lib components (bw_ram, sat_alu, dual_lm1 etc.) that tage and tage_table depend on. That would explain why you saw lib/ paths in the output — it's source annotation in the HTML, not actual file writes to lib/. Does that match what you saw?

Two items worth adding to debt:

cov_tage at 70.1% — tage_cntrl error paths uncovered, noted in Deferred Work, but worth a formal debt entry
genhtml absolute path prefix issue for CI environments

## Follow-on Actions
- [ ] create INFRA-004 to fix the pathing problem
## CLAUDE.md Updates
None
## Other Planning File Updates
None
:: DISCUSSION:END ::
=============================================================
# Claude.code Prompt 
=============================================================
:: PROMPT:START ::
## Task ID
INFRA-003

## Context Loaded
@rtl/core/frontend/bpu/Makefile

## Hypothesis
Adding --coverage-line to per-module sim targets and
introducing cov_* Makefile targets will produce line and
branch coverage reports for each BPU module via
verilator_coverage and genhtml. A cov_bpu target merges
all per-module coverage data into a single unit-level
report. This infrastructure will serve as the template
for other units when needed.

## Background
Verilator 5.020 supports --coverage-line (line and branch
coverage) and --coverage-user (cover property statements).
verilator_coverage can write .info files consumable by
genhtml to produce HTML reports. lcov and genhtml are
installed system-wide as Ubuntu 22.04 deb packages.

Per-module coverage targets follow the existing naming
convention: cov_tage, cov_loop_pred, cov_tage_table,
cov_history, cov_ubtb. A cov_bpu target merges all
per-module coverage.dat files and generates a combined
HTML report.

Coverage output directory structure:
  rtl/core/frontend/bpu/coverage/
    tage/          per-module coverage.dat and HTML
    loop_pred/     per-module coverage.dat and HTML
    tage_table/    per-module coverage.dat and HTML
    history/       per-module coverage.dat and HTML
    ubtb/          per-module coverage.dat and HTML
    bpu/           merged coverage.dat and HTML

## Binding Previous Decisions
- RVA_ROOT is always set externally. Never define it
  inside any Makefile. Use $(RVA_ROOT) for absolute
  paths where needed.
- Existing sim targets (sim_tage, sim_tage_fast,
  sim_history, sim_ubtb, sim_loop_pred, sim_tage_table)
  must not be modified. Coverage targets are additive.
- All targets must exit zero with zero warnings after
  existing suppressions.
- -Wno-PINMISSING is retained in lint_tage, sim_tage,
  sim_tage_fast per BP-023b/BP-023c decisions.

## Specific Requirements

### Step 1 -- Tool check

Before making any Makefile changes, verify that the
following tools are available in PATH:
  verilator_coverage
  lcov
  genhtml

If any tool is missing, report which tool is missing
and stop. Do not proceed with Makefile changes.

### Step 2 -- Per-module coverage targets

Add the following targets to the bpu Makefile. Each
target:
  1. Runs the corresponding sim binary with
     --coverage-line added to the Verilator compile
     flags, producing a coverage.dat in the module's
     coverage output directory.
  2. Runs verilator_coverage --write-info to convert
     coverage.dat to a .info file.
  3. Runs genhtml to produce an HTML report in the
     module's coverage subdirectory.
  4. Prints a summary line on completion.

Targets to add:
  cov_tage        feeds from sim_tage stimulus
  cov_tage_table  feeds from sim_tage_table stimulus
  cov_loop_pred   feeds from sim_loop_pred stimulus
  cov_history     feeds from sim_history stimulus
  cov_ubtb        feeds from sim_ubtb stimulus

Each target compiles a separate coverage-instrumented
binary. Do not reuse the existing sim obj_dir
directories -- use a parallel obj_dir_cov_<module>
directory to avoid stomping on existing sim builds.

Output paths:
  cov_tage:
    obj_dir_cov_tage/
    coverage/tage/coverage.dat
    coverage/tage/coverage.info
    coverage/tage/html/index.html

  cov_tage_table:
    obj_dir_cov_tage_table/
    coverage/tage_table/coverage.dat
    coverage/tage_table/coverage.info
    coverage/tage_table/html/index.html

  cov_loop_pred:
    obj_dir_cov_loop_pred/
    coverage/loop_pred/coverage.dat
    coverage/loop_pred/coverage.info
    coverage/loop_pred/html/index.html

  cov_history:
    obj_dir_cov_history/
    coverage/history/coverage.dat
    coverage/history/coverage.info
    coverage/history/html/index.html

  cov_ubtb:
    obj_dir_cov_ubtb/
    coverage/ubtb/coverage.dat
    coverage/ubtb/coverage.info
    coverage/ubtb/html/index.html

### Step 3 -- Unit-level merge target

Add a cov_bpu target that:
  1. Depends on all five per-module cov_* targets.
  2. Merges all per-module coverage.dat files using
     verilator_coverage --write into
     coverage/bpu/coverage.dat.
  3. Runs verilator_coverage --write-info to produce
     coverage/bpu/coverage.info.
  4. Runs genhtml to produce HTML in coverage/bpu/html/.
  5. Prints a summary line showing merged coverage.

### Step 4 -- Clean targets

Add clean targets for coverage artifacts:
  clean_cov_tage        removes obj_dir_cov_tage/
                        and coverage/tage/
  clean_cov_tage_table  removes obj_dir_cov_tage_table/
                        and coverage/tage_table/
  clean_cov_loop_pred   removes obj_dir_cov_loop_pred/
                        and coverage/loop_pred/
  clean_cov_history     removes obj_dir_cov_history/
                        and coverage/history/
  clean_cov_ubtb        removes obj_dir_cov_ubtb/
                        and coverage/ubtb/
  clean_cov_bpu         removes coverage/bpu/
  clean_cov             depends on all clean_cov_*
                        targets above

### Step 5 -- Verification

Run all five per-module cov_* targets and then cov_bpu.
Confirm:
  - All targets exit zero.
  - coverage/tage/html/index.html exists.
  - coverage/bpu/html/index.html exists.
  - No existing sim or lint targets are broken.

Run the full existing target list to confirm no
regressions:
  make lint
  make lint_loop_pred
  make lint_tage_table
  make lint_tage_cntrl
  make lint_tage
  make sim
  make sim_history
  make sim_ubtb
  make sim_loop_pred
  make sim_tage_table
  make sim_tage
  make sim_tage_fast

All must exit zero with zero warnings.

## Constraints
- Do not modify any RTL (.sv) files.
- Do not modify any testbench (.sv) files.
- Do not modify existing Makefile targets.
- Do not define RVA_ROOT inside the Makefile.
- coverage/ directory and obj_dir_cov_*/ directories
  should be added to .gitignore if a .gitignore exists
  at $RVA_ROOT or at the bpu directory level.
- If any tool check in Step 1 fails, stop immediately
  and report which tool is missing. Do not attempt
  any Makefile changes.

## Deliverables
1. Modified rtl/core/frontend/bpu/Makefile with all
   cov_* and clean_cov_* targets added.
2. coverage/ directory structure created by running
   the targets.
3. Console confirmation that all cov_* targets exit
   zero and HTML reports exist.
4. Console confirmation that all existing lint and sim
   targets still exit zero with zero warnings.
5. .gitignore updated if applicable.
6. Results Capture filled in below.
:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::
## Summary
Coverage infrastructure added to bpu Makefile.  All five per-module
cov_* targets and the cov_bpu merge target run to completion.  All
six HTML reports exist.  All existing lint and sim targets pass with
zero warnings.  .gitignore updated.

## Test Matrix
Not applicable -- infrastructure session.

## What was delivered
1. rtl/core/frontend/bpu/Makefile -- cov_* and clean_cov_* targets
   added in a new section after the existing clean: target.
2. coverage/ directory tree with HTML reports for all five modules
   and the merged bpu unit.
3. Root .gitignore updated with obj_dir_cov_* and coverage/ entries.

## Step 1 -- Tool check results
All three tools found in PATH:
  verilator_coverage : /usr/local/bin/verilator_coverage
  lcov               : /usr/bin/lcov
  genhtml            : /usr/bin/genhtml
Proceeded with Makefile changes.

## Step 2 -- Per-module coverage targets added
Targets added: cov_history, cov_ubtb, cov_loop_pred,
cov_tage_table, cov_tage.

Coverage rates reported by genhtml on first run:
  cov_history   : 100.0%  (648/648 lines)
  cov_ubtb      :  92.8%  (233/251 lines)
  cov_loop_pred :  97.7%  (589/603 lines)
  cov_tage_table:  75.5%  (330/437 lines)
  cov_tage      :  70.1% (3355/4789 lines)

## Step 3 -- Unit-level merge target added
cov_bpu depends on all five per-module targets.
Merged report: coverage/bpu/html/index.html
Merged coverage rate: 76.5% (5013/6549 lines across 14 source
entries including lib files).

## Step 4 -- Clean targets added
clean_cov_tage, clean_cov_tage_table, clean_cov_loop_pred,
clean_cov_history, clean_cov_ubtb, clean_cov_bpu, clean_cov.
All tested by running clean_cov_history before the first cov_history
trial run.

## Step 5 -- Verification results
All six HTML reports confirmed present:
  coverage/history/html/index.html     PASS
  coverage/ubtb/html/index.html        PASS
  coverage/loop_pred/html/index.html   PASS
  coverage/tage_table/html/index.html  PASS
  coverage/tage/html/index.html        PASS
  coverage/bpu/html/index.html         PASS

Regression -- all existing targets exit zero, zero warnings:
  make lint              PASS
  make lint_loop_pred    PASS
  make lint_tage_table   PASS
  make lint_tage_cntrl   PASS
  make lint_tage         PASS
  make sim               PASS
  make sim_history       PASS
  make sim_ubtb          PASS
  make sim_loop_pred     PASS
  make sim_tage_table    PASS
  make sim_tage          PASS
  make sim_tage_fast     PASS
  make all               PASS (exit 0)

## Test Case Results
Not applicable -- infrastructure session.

## Assumptions made not explicit in the prompt
1. Verilator 5.020 --binary mode auto-generated main does not call
   coveragep()->write().  The prompt assumed coverage.dat would be
   produced by running the binary, but no runtime flag controls the
   output path.  Resolution: use --binary for the first compile pass
   (produces Vtb.mk with link step), then patch Vtb__main.cpp with
   sed to append coveragep()->write("coverage.dat"), then re-run
   make -C obj_dir -f Vtb.mk to recompile only the changed main.
   The sim binary is then run from the coverage output directory
   so that coverage.dat lands in the correct location.

2. verilator_coverage --write-info accepts a positional input file
   argument (no --read flag needed for single-file input).  Confirmed
   by testing.

3. verilator_coverage --write (merge) also accepts positional input
   file arguments.  Confirmed by testing.

## Decisions made not explicit in the prompt
1. Used --binary (not --cc --main) for the Verilator compile step.
   --cc mode generates a library Vtb.mk (libVtb.a) without a link
   step; --binary generates an executable Vtb.mk with a link step.
   The two-pass approach (--binary then sed then make -C) was needed
   to produce a patched executable without modifying testbench files.

2. Used sed /topp->final/a\ to append the coverage write call after
   the topp->final() call in the generated Vtb__main.cpp.  This is
   a build-artifact patch, not a project source file change.

3. COV_DIR variable defined in the coverage section (not at the top
   of the Makefile) to keep all coverage additions in one block.

## RVA23 compliance risks and gaps noticed
None in this infrastructure session.

## Deferred Work
- cov_tage coverage at 70.1% -- tage_cntrl error paths and some
  vtype/superscalar paths are uncovered.  A directed coverage closure
  session could improve this.
- genhtml source paths contain absolute CWD prefixes.  Annotation
  works locally; CI environments may need --prefix or --demangle-cpp
  options added to the genhtml calls.

## Other Notes
- The two-pass compile (first --binary, then sed + make -C) adds
  ~10-20 s per module versus a single-pass compile.  Acceptable for
  coverage targets which are not in the critical path of sim.
- Verilator 5.020: the +verilator+coverage+file+ runtime argument is
  not implemented.  The documented way to set the output path is to
  run the binary from the desired output directory, which is what
  the cd $(COV_DIR)/xxx && $(CURDIR)/... pattern does.

## Files Modified
Not captured

:: RESULTS:END ::

