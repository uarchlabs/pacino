<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 032
Written by Claude.ai at end of session-031.
Date: 2026-04-26

This session ran BP-028 (fh_sel T2/T3 arm coverage, COND
PASS), completed all PROJECT_STATUS.md and
tage_coverage_plan.md updates, deferred CU-08/CU-09 with
documented rationale, built cov_table.py coverage script,
and wrote BP-029 and BP-030 prompts (ready to run).
Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## What This Session Covered

Session context restored from session_handoff-031.

### BP-028 executed -- fh_sel T2/T3 arm coverage

TC-61 (fh_sel_t2_tst) and TC-62 (fh_sel_t3_tst) added
to tb_tage.sv. All 62 tests pass.

T2 arm (lines 144-148) and T3 arm (lines 149-153)
functionally covered. Per-instance raw counts confirm
pi2=1, pi3=1. verilator_coverage --annotate displays 0
for these lines due to multi-instance aggregation
artifact (tool reports count from highest-indexed
instance for shared source lines). Documented in
BP-028 Results Capture.

VERDICT: CONDITIONAL PASS. Functional coverage confirmed.
Annotation artifact accepted and documented.

### tage_coverage_plan.md updated

All matrix rows updated to current status:
  - CP-10: covered (TC-57, BP-026)
  - CP-11, CP-12: covered/annotation artifact (BP-028)
  - CU-11: covered (BP-026, BP-027)
  - CE-09, CE-10, CE-11: covered (BP-026)
  - CU-08, CU-09: deferred (see below)
  - CE-07, CE-08: deferred to bp_cluster
  - CA-08: deferred (debt #39)
  - CE-01 through CE-06: unknown, TBD in BP-029/BP-030

Coverage Closure Sessions table updated through BP-028.
Conflicts table updated -- CU-11 resolved, CU-08/CU-09
marked deferred.

### PROJECT_STATUS.md updated

Changes applied this session:
  - Header date updated to 2026-04-26 (session-031)
  - tage.sv module row updated: BP-026 through BP-028
    noted, test counts 62 (tb_tage) and 15 (tb_tage_table)
  - Technical debt #41 added: CU-08/CU-09 aging deferral
  - Technical debt #41 duplicate (truncated copy of #40)
    replaced with correct entry
  - Stray code fence removed from debt table header
  - Open item row 6 updated: CE-01 through CE-06 closure
    noted as before bp_cluster, ITTAGE reference material
  - TAGE decomposition section updated: BP-025 through
    BP-028 appended

### CU-08/CU-09 aging deferral accepted

tage_enable_aging never driven high in TC-44/TC-45.
Aging paths may be reached via alternate code path or
plan description is incorrect. Accepted gap per
session-031 decision. Debt #41 recorded. Revisit at
bp_cluster aging integration.

### cov_table.py built and working

Script at repo root parses Verilator .dat files and
emits coverage table. Key implementation notes:
  - Verilator .dat files use SOH (0x01) as field-name
    prefix and STX (0x02) as field-name/value separator.
    These are invisible when cat/pasting -- always check
    raw bytes if parser fails.
  - Parser finds \x01f\x02 field to extract source path.
    Does not rely on pagev_ or quote characters.
  - Open files with encoding="latin-1" for byte
    transparency.
  - Default dat root: rtl/core/frontend/bpu/coverage
  - Target subdirs: history, ubtb, loop_pred, tage_table,
    tage, bpu
  - Run with --diagnose flag to debug 0/0 N/A results.

### BP-029 written -- CE-01 through CE-04

Prompt written and ready. Adds TC-63 through TC-66 to
tb_tage.sv targeting saturating arithmetic boundaries:
  TC-63: ctr_t1_max_sat_tst (CE-01, CTR=3'b111, INC)
  TC-64: ctr_t1_min_sat_tst (CE-02, CTR=3'b000, DEC)
  TC-65: use_t1_max_sat_tst (CE-03, USE=2'b11, INC)
  TC-66: use_t1_min_sat_tst (CE-04, USE=2'b00, DEC)

Coverage measured via make cov_tage.

Flag: TC-65/TC-66 require pred_diff=1 which needs two
table instances to produce differing predictions. If
Claude Code struggles, fallback is to drive pred_diff
directly via the update input struct.

### BP-030 written -- CE-05 and CE-06

Prompt written and ready. Adds TC-67 and TC-68 to
tb_tage.sv targeting tage_cntrl control paths:
  TC-67: no_alloc_candidate_tst (CE-05)
         All candidates T(provider+1)-T4 have USE > 0.
         tage_alloc_comp == 0 sentinel. alc_wr_u0
         suppressed for all tables.
  TC-68: no_ram_write_upd_tst (CE-06)
         Update presented with conditions that produce
         no RAM write enable. CE-06 code path must be
         found by reading tage_cntrl.sv in Step 1.

Coverage measured via make cov_tage.

Flag: CE-06 has a read-first requirement. Claude Code
must identify the exact code path before writing the
test. Verify the path it finds matches expectations
before accepting BP-030 as complete.

---

## Decisions Made This Session

### CU-08/CU-09 deferred -- aging paths accepted gap

tage_enable_aging never driven high in TC-44/TC-45.
Root cause unresolved. Accepted as measurement gap.
Debt #41. Revisit at bp_cluster aging integration.

### CE-07/CE-08 deferred to bp_cluster

PQ full and UQ full paths deferred. Queue depth and
backpressure will be exercised at cluster interface.

### cov_table.py script completed

Working coverage table emitter. Uses SOH/STX-aware
parser. Located at repo root. See implementation notes
above.

---

## Technical Debt Status After This Session

New debt added:
  #41 -- CU-08/CU-09 aging paths deferred.

Still open:
  #1  -- NUM_PRED_SLOTS=2 generate cleanup deferred
  #7  -- curs/curs_v rollback undefined
  #38 -- Verilator pinned to 5.020
  #39 -- TB-ARB-08 Rule 2 starvation untestable
  #40 -- TB-ARB-05 spec backpressure discrepancy
  #41 -- CU-08/CU-09 aging deferral

---

## Coverage Status After This Session

  cov_history:    100.0%  (unchanged)
  cov_ubtb:        92.8%  (unchanged)
  cov_loop_pred:   97.7%  (unchanged)
  cov_tage_table:  90.1%  (unchanged)
  cov_tage:        95.2%  (unchanged)
  cov_bpu merged:  rerun pending after BP-029/BP-030

  tage_table.sv fh_sel arms in cov_bpu:
    T1 arm: assumed covered
    T2 arm: functionally covered, annotation artifact
    T3 arm: functionally covered, annotation artifact
    T4 arm: covered (hit count=1)

---

## Test Count After This Session

  tb_tage.sv:       62 tests (TC-1 through TC-62)
  tb_tage_table.sv: 15 tests (TC-1 through TC-16,
                    no TC-13)

---

## Files Modified This Session

  rtl/core/frontend/bpu/tb/tb_tage.sv
    -- BP-028: TC-61, TC-62 appended
               Test count 60 -> 62

  planning/verification/tage_coverage_plan.md
    -- All matrix rows updated to current status
    -- Conflicts table updated
    -- Coverage Closure Sessions table updated
    -- Deferred section updated

  PROJECT_STATUS.md
    -- Header date updated
    -- tage.sv module row updated
    -- Debt #41 added
    -- Open items updated
    -- TAGE decomposition updated

  cov_table.py (new file, repo root)
    -- Coverage table emitter script

  prompts/BP-029.md -- WRITTEN, not yet run
  prompts/BP-030.md -- WRITTEN, not yet run

---

## Next Session (032)

### Step 1: Run BP-029

BP-029 prompt is written and ready at prompts/BP-029.md.
Adds TC-63 through TC-66 to tb_tage.sv.
Coverage target: make cov_tage.
Run with /run BP-029.

Watch for: TC-65/TC-66 pred_diff complexity. If Claude
Code fails to establish pred_diff=1 via real prediction,
fall back to driving pred_diff directly in the update
input struct and document the deviation.

### Step 2: Run BP-030

BP-030 prompt is written and ready at prompts/BP-030.md.
Adds TC-67 and TC-68 to tb_tage.sv.
Coverage target: make cov_tage.
Run with /run BP-030.

Watch for: CE-06 read-first step. Verify the code path
Claude Code identifies in tage_cntrl.sv before accepting
the test as correct.

### Step 3: Update tage_coverage_plan.md

After BP-029 and BP-030 pass:
  - Update CE-01 through CE-06 status to covered
  - Update Coverage Closure Sessions table
  - Update cov_tage baseline rate

### Step 4: Begin bp_cluster integration

Gating conditions after BP-029 and BP-030:
  - All TAGE coverage targets met or deferred with
    documented rationale
  - tage_coverage_plan.md current
  - PROJECT_STATUS.md current
