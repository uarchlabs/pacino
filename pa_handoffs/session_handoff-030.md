<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 030
Written by Claude.ai at end of session-029.
Date: 2026-04-24

This session executed BP-023c, established coverage
infrastructure (INFRA-001 through INFRA-006), diagnosed
two coverage gaps (BP-024, BP-025 written but not run),
and created the TAGE coverage plan. Read PROJECT_STATUS.md,
then this file, then CLAUDE.md to restore full context.

---

## What This Session Covered

Session context restored from session_handoff-029.

### Directory restructure and RVA_ROOT (INFRA-001)

Repository restructured under new directory layout.
Three renames completed before this session:
  frontend/branch_predictor/ -> rtl/core/frontend/bpu/
  frontend/decoder/          -> rtl/core/frontend/decode/
  components/                -> rtl/lib/

RVA_ROOT environment variable introduced. Always set
externally, never defined inside any Makefile or script.
Makefiles use $(RVA_ROOT), shell/python use $RVA_ROOT.

INFRA-001 ran: verified tree vs README, scrubbed stale
paths from 4 files, all 20 make targets green.
INFRA-002: README tree update and handoff.sh fix done
manually (no Claude Code session). Not formally recorded.

Package files are now at:
  rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
  rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
Do not use short-form or old paths for these files.

### BP-023c executed

consumer_ready promoted from internal tie-off to input
port on tage.sv (Option A selected). tb_tage.sv wired
with default 1'b1 preserving all 46 existing tests.
TB-ARB-01 through TB-ARB-08 implemented as TC-47 through
TC-54. Test count 46 -> 54. All 54 pass. All 12 targets
green. Lint exit 0.

Debt #37 closed: arb_grant_upd combinational forward
confirmed stable through TB-ARB-03 and TB-ARB-04.
tage_cntrl.sv not modified.

Two spec discrepancies found -- new debt assigned:
  #39: TB-ARB-08 Rule 2 starvation untestable with
       current parameters (PRED_CREDITS=4 <
       STARVE_THRESH=8). Rule 4 is effective ceiling.
  #40: TB-ARB-05 spec describes backpressure that does
       not match TAGE_UQ_DEPTH=8. Spec needs update.

-Wno-PINMISSING retained in Makefile: pq_not_full and
upd_rdy[1:0] remain unconnected DUT ports (accessed
hierarchically in tests only).

### Coverage infrastructure (INFRA-003, INFRA-004)

lcov and genhtml installed via apt (Ubuntu 22.04).
Added to prereqs.sh.

INFRA-003: cov_* and clean_cov_* targets added to
rtl/core/frontend/bpu/Makefile. Per-module targets:
cov_history, cov_ubtb, cov_loop_pred, cov_tage_table,
cov_tage. Unit-level merge: cov_bpu.

Coverage output at: rtl/core/frontend/bpu/coverage/
  tage/html/index.html      -- per-module HTML
  bpu/html/index.html       -- merged unit HTML

Two-pass Verilator compile required (--binary then sed
patch of Vtb__main.cpp to append coveragep()->write()).
Verilator 5.020 does not support runtime coverage file
path argument.

INFRA-004: Fixed genhtml writing HTML into source tree
(lib/rtl/). Root cause: missing --prefix $(RVA_ROOT)
on all genhtml calls. Fix applied to all 6 calls.
Stray files removed from lib/rtl/.

Baseline coverage rates (INFRA-003/004):
  cov_history:    100.0%
  cov_ubtb:        92.8%
  cov_loop_pred:   97.7%
  cov_tage_table:  75.5%
  cov_tage:        70.1%
  cov_bpu merged:  76.5%

### /run slash command

Created .claude/commands/run.md. Usage: /run <TASK-ID>
Searches ./prompts/ for <ID>.md, runs
validate_and_extract.py, reports and stops if non-zero,
executes .claude/tmp/current-prompt.md if valid.

### Coverage gap analysis (INFRA-005, INFRA-006)

INFRA-005: verilator_coverage --annotate run on
cov_tage baseline. 13 gap regions found across 4 files.
Key findings:
  - CA-08 (Rule 2 starvation) confirmed gap
  - CE-10 (allocation end-to-end) confirmed gap
  - CU-11 (slot 1 tage_table writes) conflict --
    plan marked covered but zero annotation counts
  - CU-08/CU-09 (aging) conflict -- inferred, medium
    confidence, tage_enable_aging never driven high
  - 4 new plan rows suggested: CE-09, CE-10, CE-11,
    CP-10

After INFRA-005, cov_tage re-run with current testbench
produced improved rates:
  tage:        95.2%  (was 70.1%)
  tage_cntrl:  94.8%
  tage_bim:    83.3%
  tage_table:  76.0%  (was 75.5%)

INFRA-006: Targeted annotate on tage_table.sv only.
18 gap regions found. Hypothesis confirmed: 24% gap is
concentrated in CU-11 slot 1 write paths (9 regions)
and CP-10 fh_sel cases (4 regions). Key new finding:
norm_we_s1 was never asserted -- not just that writes
didn't fire, but the we_s1 enable was false throughout.

### Coverage plan created

New document: planning/verification/tage_coverage_plan.md
Contains:
  - Status table with per-module baseline rates
  - Coverage matrix: CP-xx, CU-xx, CA-xx, CE-xx rows
  - Conflicts table: CU-08, CU-09, CU-11
  - Gap Analysis Process section
  - Coverage Closure Sessions table
  - Deferred section

### BP-024 executed -- CE-10 allocation root cause

Root Cause C confirmed. alc_en gate u_alc_comp[s] != '0
(tage_cntrl.sv line 816) was permanently false during
INFRA-005 baseline. All synthetic-meta update tests left
tage_alc_comp at zero default. TC-42/TC-43 are
structurally correct and close CE-10 -- the INFRA-005
baseline was stale (run before TC-42/TC-43 were
integrated in their current form).

Additional undocumented gate discovered: trx_type
(arb_grant_upd) gates all tage_table RAM writes
(tage.sv line 262, tage_cntrl.sv lines 887-890). Must
be asserted for any RAM write to fire.

### Verilator migration debt recorded

Debt #38: Verilator pinned to 5.020. Upgrade blocked
on covergroup/coverpoint support (issue #7099, open
as of 2026-04-23, not merged in any release including
5.047). Expression coverage added in 5.034 available
but insufficient justification to upgrade mid-project.
Track issue #7099 for merge status.

### BP-025 written -- CU-11 diagnosis

BP-025 prompt written but NOT yet run. Diagnoses why
norm_we_s1 was never asserted. Two candidates:
  A: TC-23/TB-ARB-05 don't correctly drive
     tage_upd_val_u0[1]
  B: Table selector routing of slot 1 updates to
     non-matching tage_table instance
Both investigated in parallel. Console output only,
no RTL changes.

---

## Decisions Made This Session

### Directory structure and RVA_ROOT

New canonical paths in effect. All Makefiles and scripts
updated. Old paths (frontend/branch_predictor/,
frontend/decoder/, components/) are stale -- do not use.

### consumer_ready promoted to port (reverses D1)

Decision D1 from session-028 reversed. consumer_ready
is now an input port on tage.sv. Default 1'b1 in
testbench. This unblocked TB-ARB-07.

### trx_type combinational forward confirmed stable (D2)

Debt #37 closed. arb_grant_upd combinational path
confirmed stable through concurrent pred+upd tests.
tage_cntrl.sv write-enable timing requires no change.

### Coverage tool stack

Verilator --coverage-line for line/branch coverage.
verilator_coverage --annotate for source annotation.
genhtml --prefix $(RVA_ROOT) for HTML reports.
All output confined to rtl/core/frontend/bpu/coverage/.
Functional coverage (covergroup) deferred to post-5.020.

### Prompts directory flattened

prompts/ subdirectory structure will be flattened to
./prompts/ after BP-023c completes. All new prompts
go directly in ./prompts/.

---

## Technical Debt Status After This Session

Closed this session:
  #37 -- trx_type combinational forward confirmed stable
         via TB-ARB-03 and TB-ARB-04. No RTL change.

New debt assigned this session:
  #38 -- Verilator pinned to 5.020. Upgrade when
         covergroup/coverpoint support (issue #7099)
         merges into a stable release. Before upgrading:
         audit Makefile flags and suppressions, run full
         regression, update CLAUDE.md and prereqs.sh.
  #39 -- TB-ARB-08 Rule 2 starvation untestable with
         TAGE_PRED_CREDITS=4 < TAGE_STARVE_THRESH=8.
         Verify invariant is intentional at design
         finalization. Adjust parameters if Rule 2
         must be testable.
  #40 -- TB-ARB-05 spec backpressure description does
         not match TAGE_UQ_DEPTH=8. Update bp_arb_spec.md
         section 10.1 before bp_cluster integration.

Still open:
  #1  -- NUM_PRED_SLOTS=2 generate cleanup deferred
  #7  -- curs/curs_v rollback undefined
  #39 -- TB-ARB-08 Rule 2 starvation (see above)
  #40 -- TB-ARB-05 spec discrepancy (see above)

---

## Files Modified This Session

  rtl/core/frontend/bpu/Makefile
    -- INFRA-001: stale commented-out COMP_DIR fixed
    -- INFRA-003: cov_* and clean_cov_* targets added
    -- INFRA-004: --prefix $(RVA_ROOT) added to all
                  genhtml calls

  rtl/lib/Makefile
    -- INFRA-001: stale comment header fixed

  tools/check_rva23_coverage.py
    -- INFRA-001: DEFAULT_RTL path updated to new layout

  tools/mk_pkg.sh
    -- INFRA-001: all source and dest paths updated

  rtl/core/frontend/bpu/rtl/tage.sv
    -- BP-023c: consumer_ready promoted from internal
                tie-off to input port

  rtl/core/frontend/bpu/tb/tb_tage.sv
    -- BP-023c: consumer_ready declared and wired (1'b1)
                TC-47 through TC-54 appended
                Test count 46 -> 54

  .gitignore (root)
    -- INFRA-003: obj_dir_cov_* and coverage/ added

  .claude/commands/run.md
    -- Created: /run slash command for prompt execution

  planning/verification/tage_coverage_plan.md
    -- Created: TAGE coverage plan document

---

## Next Session (030)

### Step 1: Run BP-025

BP-025 prompt is written and ready at prompts/BP-025.md.
Diagnoses CU-11 root cause (norm_we_s1 never asserted).
Two candidates investigated in parallel (A and B).
Run with /run BP-025.

### Step 2: Coverage closure testbench

After BP-025 diagnosis, write the closure testbench
prompt targeting:
  - CU-11 slot 1 write paths (highest priority)
  - CP-10 T1/T2/T3 fh_sel cases
  - CE-10 allocation end-to-end
  - CE-11 alt-CTR slot 0 write
  - CE-09 aging active path
  Target: tage_table.sv from 76% to 90%+

### Step 3: Update tage_coverage_plan.md

After closure testbench runs:
  - Update status column for closed rows
  - Resolve CU-08, CU-09, CU-11 conflicts
  - Add TAGE_FAST_INIT row
  - Update Coverage Closure Sessions table

### Step 4: bp_cluster integration

Begins after coverage target (90%) achieved across
all TAGE modules and coverage plan is current.

---

## Prompt Files Created This Session

  prompts/INFRA-001.md  -- PASS, 20 targets green
  prompts/INFRA-003.md  -- PASS, all cov_* targets green
  prompts/INFRA-004.md  -- PASS, genhtml output contained
  prompts/INFRA-005.md  -- PASS, 13 gaps identified
  prompts/INFRA-006.md  -- PASS, 18 gaps in tage_table
  prompts/BP-023c.md    -- PASS, 54/54, lint green
  prompts/BP-024.md     -- PASS, root cause C confirmed
  prompts/BP-025.md     -- WRITTEN, not yet run

## Open Items Added This Session

  | 7  | Verilator upgrade to post-covergroup release  |
  |    | When issue #7099 merges into stable release   |
  | 8  | Investigate mutation testing                  |
  |    | Planned -- post coverage closure              |

