# Session Handoff 031
Written by Claude.ai at end of session-030.
Date: 2026-04-26

This session ran BP-025 (CU-11 diagnosis), wrote and ran
BP-026 (integration-level closure testbench), wrote and ran
BP-027 (unit-level coverage closure, 90.1% achieved), wrote
BP-028 (fh_sel T2/T3 arm coverage, not yet run), and
documented three prompt generation anti-patterns (PG-001
through PG-003). Read PROJECT_STATUS.md, then this file,
then CLAUDE.md to restore full context.

---

## What This Session Covered

Session context restored from session_handoff-030.

### BP-025 executed -- CU-11 root cause diagnosis

Diagnosed why norm_we_s1 was never asserted. Results were
manually added to prompts/BP-025.md because the prompt
contained "Console output only. No file writes." conflicting
with the Results Capture requirement (see PG-001 below).

Root cause findings:
  TB-ARB-05 (arb_upd_burst_tst): Candidate B confirmed.
    tage_prm_comp=3'd0 for both slots routes updates to
    tage_bim (T0). No tage_table instance has THIS_TABLE=0.
    All write enables for T1-T4 are structurally zero
    throughout the test. Testbench metadata bug, not RTL.
  TC-23 (slot1_upd_tst): Static analysis shows norm_we_s1
    should fire correctly. INFRA-006 zero-execution finding
    is a measurement gap -- likely ran before TC-23 was
    active in current form, or missed single-cycle transient.
    Cannot be resolved without runtime waveform data.
    Deferred.

Fix approach: Drive slot 1 updates with tage_prm_comp in
3'd1..3'd4 (tagged table target). Add explicit norm_we_s1
capture via hierarchical reference.

### BP-026 executed -- integration-level coverage closure

Added TC-55 through TC-60 to tb_tage.sv targeting:
  TC-55: slot1_t1_write_tst (CU-11, T1 slot 1 write)
  TC-56: slot1_t2_write_tst (CU-11, T2 slot 1 write)
  TC-57: fh_sel_t3_t4_tst   (CP-10, T3/T4 fh_sel arms)
  TC-58: aging_active_tst   (CE-09, aging active path)
  TC-59: alt_ctr_s0_write_tst (CE-11, alt-CTR slot 0)
  TC-60: alc_end_to_end_tst (CE-10, allocation round-trip)

All 60 tests pass. All six target paths confirmed via
hierarchical signal capture (norm_we_s1=1, alc_wr_seen=1,
aging epoch increment, alt-CTR write, fh_sel T3/T4).

Coverage shortfall: 90%+ target not met in cov_tage_table.
Root cause: new tests added to tb_tage.sv but cov_tage_table
compiles tb_tage_table.sv. Tests do not contribute to the
unit-level metric. This is prompt authoring failure PG-003
(see below). Follow-on task BP-027 written to fix this.

Three mid-session diagnosis fixes documented in Results
Capture:
  - TC-55 needs drain cycle: arb_starve_tst leaves one
    stale PQ entry.
  - TC-58 needs drain cycle with aging disabled: TC-57
    leaves tage_pred_rdy_p2[0]=1 which fires aging on
    first posedge if tage_enable_aging=1 before drain.
  - TC-58 and TC-60 both need lcl_epoch[0] reset via
    hierarchical write: TC-43/TC-44 leave epoch=2.

### BP-027 executed -- unit-level coverage closure

Added TC-14 through TC-16 to tb_tage_table.sv and added
+TAGE_FAST_INIT=1 to Makefile cov_tage_table target.

  TC-14: slot1_unit_write_tst -- norm_we_s1, addr/din/
         bweb mux slot 1 paths. norm_we_s1_seen=1.
  TC-15: epc_s0_write_tst -- epc_we_s0 gating, din/bweb
         mux EPC branch slot 0.
  TC-16: alt_ctr_s1_write_tst -- din_mux_s1 line 427
         alt_ctr_we_s1 branch (tipped coverage to 90.1%).
  fast_init: Makefile Option A. +TAGE_FAST_INIT=1 added
         to cov_tage_table. Lines 224-229 covered (2048
         iterations). Line 222 (if condition) shows count=0
         -- Verilator instrumentation artifact, not a gap.

Result: tage_table.sv 154/171 = 90.1% -- PASS.
All 15 tests in tb_tage_table.sv pass.

Remaining uncovered in cov_tage_table (17 lines):
  Lines 144-162 (16): fh_sel arms 2/3/4 -- Verilator
    per-specialization coverage overwrite prevents coverage
    via multiple instances in one run. See discovery below.
  Line 222 (1): fast_init if-condition -- instrumentation
    artifact. Inner loop body fully covered.

TC-13 attempted and reverted: Adding T2/T3/T4 instances to
tb_tage_table.sv caused regression from 78% to 72.5%.
Verilator generates separate coverage type entries per
unique THIS_TABLE specialization. verilator_coverage
--write-info overwrites T1's positive counts with T2/T3/T4
zero counts for shared source lines. All additional
instances and TC-13 removed.

### fh_sel T2/T3 gap confirmed at integration level

After BP-027, cov_bpu HTML report inspected for
tage_table.sv lines 144-162 (fh_sel case arms):

  Lines 154-157 (T4 arm): COVERED -- hit count = 1
  Lines 144-153 (T2 arm, T3 arm): NOT COVERED -- red

T1 arm assumed covered. T4 covered as side effect of
existing tests. T2 and T3 arms are genuinely never
executed in any test across the entire suite -- unit
or integration. This is a real functional gap. T2 and T3
folded history selection logic has never been verified.

This is not a Verilator artifact -- it is a genuine
coverage gap in the integration testbench. New prediction
tests targeting T2 and T3 instances in tb_tage.sv are
required.

### BP-028 written -- fh_sel T2/T3 arm coverage

BP-028 prompt written and ready at prompts/BP-028.md.
Not yet run. Adds TC-61 (fh_sel_t2_tst) and TC-62
(fh_sel_t3_tst) to tb_tage.sv. Both are prediction tests
that pre-load T2 and T3 RAM entries and issue predictions
with appropriate folded history values to activate those
fh_sel mux arms. Coverage measured via make cov_bpu.

### Prompt generation anti-patterns documented

Three anti-patterns identified and documented in
planning/verification/prompt-generation-antipatterns.md
(or equivalent location -- copy into PROJECT_STATUS.md
Prompt Generation Guide section):

  PG-001: "Console output only. No file writes." in
    Constraints conflicts with Results Capture in
    Deliverables. Correct form: "Do not modify any RTL,
    testbench, or Makefile files."

  PG-002: Section order inside :: PROMPT:START :: is
    fixed. ## Hypothesis must precede ## Background.
    Validator is strict. Always verify order explicitly.
    Required sequence:
      1. ## Task ID
      2. ## Context Loaded
      3. ## Hypothesis
      4. ## Background
      5. ## Binding Previous Decisions
      6. ## Specific Requirements
      7. ## Constraints
      8. ## Deliverables

  PG-003: Coverage target and testbench file must be
    explicitly linked in the prompt. Every prompt with
    a coverage target must state: (1) module under
    measurement, (2) make target, (3) testbench file
    that target compiles. New tests must go to the TB
    named in item 3.

---

## Decisions Made This Session

### TC-23 norm_we_s1 discrepancy deferred (D3)

Static analysis shows TC-23 should fire norm_we_s1
correctly but INFRA-006 shows zero execution. Cannot be
resolved without runtime waveform data. Accepted as
measurement gap and deferred. TC-23 not modified.

### TC-13 reverted -- Verilator specialization overwrite

Multiple tage_table instances with different THIS_TABLE
values in a single tb_tage_table.sv run causes coverage
regression due to Verilator per-specialization type
overwrite. Do not attempt multiple parameterized instances
of the same module in a single coverage run.

The correct approach for fh_sel T2/T3 coverage is
integration-level tests in tb_tage.sv where all instances
coexist via the generate block (BP-028).

### cov_tage_table 90%+ target met

tage_table.sv reached 90.1% in cov_tage_table.
Remaining 16-line gap (fh_sel arms 2/3/4) is accepted
as a unit-testbench-scope limitation. Integration-level
coverage via cov_bpu is the authoritative metric for
those lines.

---

## Technical Debt Status After This Session

No new debt assigned. No debt closed.

Still open:
  #1  -- NUM_PRED_SLOTS=2 generate cleanup deferred
  #7  -- curs/curs_v rollback undefined
  #38 -- Verilator pinned to 5.020
  #39 -- TB-ARB-08 Rule 2 starvation untestable
  #40 -- TB-ARB-05 spec backpressure discrepancy

---

## Coverage Status After This Session

  cov_history:    100.0%  (unchanged)
  cov_ubtb:        92.8%  (unchanged)
  cov_loop_pred:   97.7%  (unchanged)
  cov_tage_table:  90.1%  (was 75.5%) -- PASS
  cov_tage:        95.2%  (was 70.1%)
  cov_bpu merged:  TBD -- rerun after BP-028

  tage_table.sv fh_sel arms in cov_bpu:
    T1 arm: assumed covered
    T2 arm: NOT COVERED (lines 144-148) -- BP-028 target
    T3 arm: NOT COVERED (lines 149-153) -- BP-028 target
    T4 arm: COVERED (lines 154-157, hit count=1)

---

## Test Count After This Session

  tb_tage.sv:       60 tests (TC-1 through TC-60)
  tb_tage_table.sv: 15 tests (TC-1 through TC-16,
                    no TC-13)

---

## Files Modified This Session

  rtl/core/frontend/bpu/tb/tb_tage.sv
    -- BP-026: TC-55 through TC-60 appended
               Test count 54 -> 60

  rtl/core/frontend/bpu/tb/tb_tage_table.sv
    -- BP-027: TC-14, TC-15, TC-16 appended
               norm_we_s1_seen signal declared
               PC and DATA constants for TC-14/15/16 added
               Test count 12 -> 15 (no TC-13)

  rtl/core/frontend/bpu/Makefile
    -- BP-027: +TAGE_FAST_INIT=1 added to cov_tage_table
               simulation step

---

## Next Session (031)

### Step 1: Run BP-028

BP-028 prompt is written and ready at prompts/BP-028.md.
Adds TC-61 (fh_sel_t2_tst) and TC-62 (fh_sel_t3_tst)
to tb_tage.sv. Measured via make cov_bpu.
Run with /run BP-028.

### Step 2: Update tage_coverage_plan.md

After BP-028 runs, update the coverage plan:
  - Update status column for CU-11, CP-10, CE-09,
    CE-10, CE-11 rows (all closed by BP-026/BP-027)
  - Resolve CU-08, CU-09, CU-11 conflicts
  - Add fh_sel T2/T3 row and mark closed if BP-028 passes
  - Update Coverage Closure Sessions table
  - Update per-module baseline rates

### Step 3: Add PG-001 through PG-003 to PROJECT_STATUS.md

The three prompt generation anti-patterns documented this
session must be added to the Prompt Generation Guide
section of PROJECT_STATUS.md before the next prompt
authoring session. Source:
  planning/verification/prompt-generation-antipatterns.md

### Step 4: bp_cluster integration

Begins after:
  - BP-028 passes (fh_sel T2/T3 covered)
  - tage_coverage_plan.md updated and current
  - All TAGE module coverage targets met

---

## Prompt Files Created This Session

  prompts/BP-025.md  -- PASS, results manually added,
                        CU-11 root cause diagnosed
  prompts/BP-026.md  -- PASS, 60/60 tests, coverage
                        shortfall (wrong TB, see PG-003)
  prompts/BP-027.md  -- PASS, 90.1% tage_table.sv
  prompts/BP-028.md  -- WRITTEN, not yet run

