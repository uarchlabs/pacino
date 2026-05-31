=============================================================
# Task Header 
=============================================================
:: HEADER:START ::
| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | INFRA-004               |                          |
| Date         | 2026.04.24              |                          |
| Module       | repo-wide / bpu         |                          |
| Run time     | 4m.26s                  |                          |
| Ctx %        | 23%                     |                          |
| Model        | Sonnet 4.6 medium       |                          |
| Resume sha   | dd3422cc-4180-4dee-9338-03dd6f29473c               |
Task:   [ ] experiment  [ ] implementation  [ ] debug
        [x] cleanup     [ ] testbench
Mode:   [x] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned
# Overview of task
# Fix genhtml writing annotation HTML outside the coverage/
# tree into rtl/core/frontend/bpu/lib/rtl/. All genhtml
# output must be confined to coverage/*/html/.
:: HEADER:END ::
=============================================================
# Paste c.code console output and c.ai discussion
=============================================================
:: DISCUSSION:START ::
# Results Discussion 
## Claude.code Console Output

  Step 1 — Found 6 genhtml calls in cov_history, cov_ubtb, cov_loop_pred, 
  cov_tage_table, cov_tage, cov_bpu.
  Step 2 — Fix applied to all 6: --prefix $(RVA_ROOT) added, argument 
  order rewritten  to match the required pattern. No other Makefile 
  content changed. 
  Step 3 — Stray files removed: 9 HTML files deleted from lib/rtl/. 
  That directory was entirely a genhtml artifact (actual sources are at 
  rtl/lib/rtl/); it is now empty.
  Step 4 — Coverage verified: All six HTML reports confined to 
  coverage/*/html/. Zero  HTML files under lib/ or anywhere outside 
  coverage/. All rates match baseline: history 100%, ubtb 92.8%, 
  loop_pred 97.7%, tage_table 75.5%, tage 70.1%, bpu 76.5%.  
  Step 5 — Regression: All 5 lint targets and 7 sim targets pass, 
  exit zero, zero      warnings.
  Results Capture written to prompts/INFRA-004.md.
## My Assessment

Pending

I need to refresh c.ai with the prompt template

## Claude.ai Assessment

Clean result. Fix confirmed working — all six HTML reports contained within coverage/*/html/, stray files removed, all rates match baseline exactly, full regression clean.
Two notes for the record:
On the Discussion section: You flagged that Claude.ai assessment text was placed there incorrectly — that was me pre-populating it when I generated the prompt. The Discussion section is meant to be filled in after the session, not pre-loaded. I'll stop doing that in future prompts.
On the empty lib/rtl/ directory: The Other Notes mention it exists but is empty. Worth adding to .gitignore or removing with rmdir manually — an empty directory with a misleading path sitting in the bpu tree is a minor confusion risk.


This was placed in this section by claude.ai this is not the place 
to put this.

INFRA-003 introduced a defect: genhtml wrote annotated source
HTML for lib components (bw_ram.sv, sram_init.sv) into
rtl/core/frontend/bpu/lib/rtl/ in addition to the intended
coverage/*/html/ directories. Root cause: genhtml resolves
source file paths from the .info file and writes annotation
HTML relative to those source paths when --output-directory
is not sufficient to contain them. Fix requires --prefix to
strip the source path root so all output lands inside the
specified --output-directory.

The prompt did not specify --prefix or enforce that genhtml
output must be fully contained within the coverage/ tree.
This is a prompt gap, not a Claude Code deviation.

## Follow-on Actions
- [ ] Remove stray HTML files from lib/rtl/ after fix confirmed
## CLAUDE.md Updates
TBD as needed document here
## Other Planning File Updates
TBD as needed document here
:: DISCUSSION:END ::
=============================================================
# Claude.code Prompt 
=============================================================
:: PROMPT:START ::
## Task ID
INFRA-004

## Context Loaded
@rtl/core/frontend/bpu/Makefile

## Hypothesis
Adding --prefix $(RVA_ROOT) to all genhtml calls in the
bpu Makefile coverage targets will confine all genhtml
HTML output to the specified --output-directory and
prevent annotation files from being written into source
tree directories such as rtl/core/frontend/bpu/lib/rtl/.

## Background
INFRA-003 added cov_* coverage targets to the bpu Makefile.
During cov_bpu execution, genhtml processed the merged
coverage.info and wrote annotated source HTML for lib
components (bw_ram.sv, sram_init.sv) into:

  rtl/core/frontend/bpu/lib/rtl/

This was not specified or intended. The correct output
location for all genhtml output is within:

  rtl/core/frontend/bpu/coverage/*/html/

The defect occurs because genhtml resolves absolute source
paths from the .info file and writes annotation HTML
relative to those paths when the --prefix option is not
used to strip the common path root. Without --prefix,
genhtml cannot contain output within --output-directory
when source files live outside the coverage/ subtree.

Stray files confirmed in rtl/core/frontend/bpu/lib/rtl/:
  bw_ram.sv.func.html
  bw_ram.sv.func-sort-c.html
  bw_ram.sv.gcov.html
  index.html
  index-sort-f.html
  index-sort-l.html
  sram_init.sv.func.html
  sram_init.sv.func-sort-c.html
  sram_init.sv.gcov.html

## Binding Previous Decisions
- RVA_ROOT is always set externally. Use $(RVA_ROOT) in
  Makefile. Never define it inside the Makefile.
- Do not modify existing sim or lint targets.
- All coverage output must be confined to:
  rtl/core/frontend/bpu/coverage/
- Do not modify any RTL or testbench .sv files.

## Specific Requirements

### Step 1 -- Identify all genhtml calls

Read the current bpu Makefile and locate every genhtml
invocation in the cov_* targets. There should be one
per per-module target plus one in cov_bpu.

### Step 2 -- Add --prefix to all genhtml calls

For every genhtml call found in Step 1, add:
  --prefix $(RVA_ROOT)

This strips the RVA_ROOT prefix from all source paths
in the .info file, causing genhtml to write all output
relative to --output-directory rather than relative to
the absolute source paths.

The corrected genhtml call pattern is:
  genhtml --prefix $(RVA_ROOT) \
          --output-directory <output_dir> \
          <input.info>

### Step 3 -- Remove stray files

Remove the stray HTML files that INFRA-003 wrote into
the source tree:
  rm -rf rtl/core/frontend/bpu/lib/rtl/*.html
  rm -f  rtl/core/frontend/bpu/lib/rtl/index*.html

Confirm the directory contains only .sv source files
after removal.

### Step 4 -- Re-run coverage targets and verify

Run clean_cov then all cov_* targets to regenerate
all coverage reports:
  make clean_cov
  make cov_bpu

Verify:
  - All six HTML reports exist in coverage/*/html/
  - No HTML files exist anywhere under lib/
  - No HTML files exist anywhere outside coverage/
  - All coverage rates are consistent with INFRA-003
    baseline (within a few percent):
      history:    ~100%
      ubtb:       ~92%
      loop_pred:  ~97%
      tage_table: ~75%
      tage:       ~70%
      bpu:        ~76%

### Step 5 -- Regression

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
- Only the genhtml calls in the cov_* targets may be
  modified. No other Makefile content may change.
- Do not modify any RTL or testbench .sv files.
- Do not modify any existing sim or lint targets.
- All genhtml output must be fully contained within
  rtl/core/frontend/bpu/coverage/.
- If stray HTML files are found outside coverage/ or
  lib/rtl/ after the fix, report them before removing.

## Deliverables
1. Modified rtl/core/frontend/bpu/Makefile with
   --prefix $(RVA_ROOT) added to all genhtml calls.
2. Stray HTML files removed from lib/rtl/.
3. Console confirmation that all six HTML reports
   exist only within coverage/*/html/.
4. Console confirmation that lib/rtl/ contains only
   .sv files.
5. Console confirmation that all lint and sim targets
   exit zero with zero warnings.
6. Results Capture filled in below.
:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::
## Summary
Hypothesis confirmed. Adding --prefix $(RVA_ROOT) to all six
genhtml calls in the bpu Makefile cov_* targets fully contained
all HTML output within coverage/*/html/. Stray files in
lib/rtl/ removed. All coverage rates match INFRA-003 baseline.
All lint and sim regression targets pass with zero warnings.

## Test Matrix
Omitted -- not a testbench session.

## What was delivered
1. rtl/core/frontend/bpu/Makefile: --prefix $(RVA_ROOT) added
   to all six genhtml calls (cov_history, cov_ubtb, cov_loop_pred,
   cov_tage_table, cov_tage, cov_bpu). Argument order changed to:
   genhtml --prefix $(RVA_ROOT) \
     --output-directory <dir> \
     <input.info>
2. Nine stray HTML files removed from lib/rtl/ (the stray
   directory had no .sv source files; actual sources are at
   rtl/lib/rtl/).
3. All six HTML index.html reports confirmed within coverage/.
4. lib/rtl/ confirmed empty; no .sv files were ever there.
5. All lint and sim targets exit zero with zero warnings.

## Step 1 -- genhtml calls found
Six genhtml calls located in the cov_* section (lines 229-230,
252-253, 275-276, 299-300, 330-331, 346-347 in original file):
  cov_history   -- coverage/history/coverage.info
  cov_ubtb      -- coverage/ubtb/coverage.info
  cov_loop_pred -- coverage/loop_pred/coverage.info
  cov_tage_table-- coverage/tage_table/coverage.info
  cov_tage      -- coverage/tage/coverage.info
  cov_bpu       -- coverage/bpu/coverage.info

## Step 2 -- --prefix added
All six calls updated to:
  genhtml --prefix $(RVA_ROOT) \
    --output-directory <module>/html \
    <module>/coverage.info
Only the genhtml invocations were changed. No other Makefile
content was modified.

## Step 3 -- Stray files removed
Nine stray HTML files removed from lib/rtl/:
  bw_ram.sv.func.html
  bw_ram.sv.func-sort-c.html
  bw_ram.sv.gcov.html
  index.html
  index-sort-f.html
  index-sort-l.html
  sram_init.sv.func.html
  sram_init.sv.func-sort-c.html
  sram_init.sv.gcov.html
Directory is now empty. Note: lib/rtl/ inside bpu was entirely
a genhtml artifact; the actual .sv sources are at rtl/lib/rtl/.

## Step 4 -- Coverage re-run results
All six HTML reports confirmed in coverage/*/html/ only.
No HTML files found under lib/ or anywhere outside coverage/.

Coverage rates (all within baseline):
  history:    100.0%  (baseline ~100%)  PASS
  ubtb:        92.8%  (baseline  ~92%)  PASS
  loop_pred:   97.7%  (baseline  ~97%)  PASS
  tage_table:  75.5%  (baseline  ~75%)  PASS
  tage:        70.1%  (baseline  ~70%)  PASS
  bpu:         76.5%  (baseline  ~76%)  PASS

## Step 5 -- Regression results
All targets pass, exit zero, zero warnings:
  make lint            PASS
  make lint_loop_pred  PASS
  make lint_tage_table PASS
  make lint_tage_cntrl PASS
  make lint_tage       PASS
  make sim             PASS  BP-001: 16 checks passed
  make sim_history     PASS  BP-002: 12 checks passed
  make sim_ubtb        PASS  ALL TESTS PASSED
  make sim_loop_pred   PASS
  make sim_tage_table  PASS
  make sim_tage        PASS  BP-023c: all tests passed
  make sim_tage_fast   PASS  BP-023c: all tests passed

## Test Case Results
Not applicable -- infrastructure session.

## Assumptions made not explicit in the prompt
- lib/rtl/ inside the bpu directory had no .sv source files.
  The prompt said "confirm only .sv files remain"; the actual
  situation was the directory became empty after HTML removal.
  Reported here; no action taken beyond removal of HTML files.

## Decisions made not explicit in the prompt
- Argument order in genhtml calls changed to match the required
  pattern (--prefix first, then --output-directory, then
  input.info), rather than simply inserting --prefix before the
  existing argument list. This is consistent with the pattern
  specified in Step 2 of the prompt.

## RVA23 compliance risks and gaps noticed
None. This is a build infrastructure change only.

## Deferred Work
None.

## Other Notes
The stray lib/rtl/ directory now exists but is empty. It can be
removed with rmdir if desired. No automated cleanup is required
since it will not accumulate new files with the --prefix fix in
place.

## Files Modified
Not captured

:: RESULTS:END ::

