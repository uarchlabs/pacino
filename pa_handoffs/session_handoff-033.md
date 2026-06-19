<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 033
Written by Claude.ai at end of session-032.
Date: 2026-04-26

This session ran BP-029 (CE-01 through CE-04, saturating
arithmetic boundary tests, PASS) and BP-030 (CE-05 and
CE-06, no-candidate sentinel and no-write update path,
PASS). All TAGE coverage targets are now closed or
deferred with documented rationale. Decision made to
move on to ITTAGE after a research session.
Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## What This Session Covered

Session context restored from session_handoff-032.

### BP-029 executed -- CE-01 through CE-04

TC-63 through TC-66 added to tb_tage.sv.
All 66 tests pass.

  TC-63: ctr_t1_max_sat_tst (CE-01) PASS
  TC-64: ctr_t1_min_sat_tst (CE-02) PASS
  TC-65: use_t1_max_sat_tst (CE-03) PASS
  TC-66: use_t1_min_sat_tst (CE-04) PASS

Key finding: sat_alu is not instantiated inside bw_ram
or tage_table. Saturating arithmetic is inline in
tage_cntrl.sv using ternary expressions. The BP-029
prompt background was inaccurate on this point. Claude
Code identified the discrepancy in Step 1 and adapted.
Coverage annotation from tage_cntrl.sv:
  CE-01 CTR max: lines 689-690, hit 8 times
  CE-02 CTR min: lines 694-695, hit 14 times
  CE-03 USE max: lines 771-772, hit 5 times
  CE-04 USE min: lines 776-777, hit 10 times

VERDICT: PASS.

### BP-030 executed -- CE-05 and CE-06

TC-67 and TC-68 added to tb_tage.sv.
All 68 tests pass.

  TC-67: no_alloc_candidate_tst (CE-05) PASS
  TC-68: no_ram_write_upd_tst   (CE-06) PASS

CE-05: allocation scan with all candidates blocked by
USE > 0. tage_alloc_comp == 0 sentinel confirmed.
alc_wr_u0 suppressed for all tables verified via
hierarchical reference.

CE-06 code path identified in Step 1 before test was
written: u_prm_comp=0 (T0), u_alt_comp=1 (T1),
u_using_prm=1, u_pred_diff=0, u_mispredict=0.
All five write-enable conditions evaluate false.
No RAM write asserts. tage_upd_rdy_u1[0] asserts.

Lines 536-539 (allocation scan body inside always_comb
inside generate-for) remain at count=0. Pre-existing
Verilator instrumentation gap. Not introduced by BP-030.
Code executes correctly -- TC-60 alc_end_to_end_tst
verifies allocation writes. Gap documented and accepted.

VERDICT: PASS.

### Decision: move on to ITTAGE

All TAGE coverage targets closed or deferred with
documented rationale. Three BPU predictors remain:
FTB, ITTAGE, SC. Decision made to begin ITTAGE next,
with a research session before implementation.
ITTAGE chosen first because it shares the TAGE table
architecture. BP-029/BP-030 tests are documented
reference material for ITTAGE verification.

### Planning doc updates pending

The following updates were identified but not yet
applied this session:

  PROJECT_STATUS.md:
    - Header date needs update to session_handoff-032
    - tage.sv module row: BP-029 and BP-030 entries
      need proper notes (currently stubs)
    - Open Item 6: mark Complete (CE-01 through CE-06
      now closed)
    - TAGE decomposition: BP-029 and BP-030 need
      full detail entries

  tage_coverage_plan.md:
    - CE-01 through CE-06: mark covered
    - Coverage Closure Sessions table: add BP-029
      and BP-030 rows
    - Overall status update

These updates should be the first task of session-033
before ITTAGE research begins.

---

## Decisions Made This Session

### Move on to ITTAGE

TAGE coverage process proven. All targets closed or
deferred. Remaining BPU predictors: FTB, ITTAGE, SC.
ITTAGE is next. Research session required before
implementation.

### sat_alu discrepancy accepted

sat_alu is a standalone library component used only
in tb_components. It is not instantiated in the TAGE
predictor. Saturating arithmetic is inline in
tage_cntrl.sv. Future prompts referencing sat_alu in
TAGE context should be corrected before running.
ITTAGE will likely follow the same inline pattern.

---

## Technical Debt Status After This Session

No new debt added this session.

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
  cov_tage:        95.2%  (baseline, pre-BP-029/030)
  cov_bpu merged:  rerun pending

  CE-01 through CE-04: covered (BP-029)
  CE-05, CE-06: covered (BP-030)
  CE-07, CE-08: deferred to bp_cluster
  CA-08: deferred (debt #39)
  CU-08, CU-09: deferred (debt #41)
  Lines 536-539: Verilator instrumentation gap,
                 accepted and documented

---

## Test Count After This Session

  tb_tage.sv:       68 tests (TC-1 through TC-68)
  tb_tage_table.sv: 15 tests (TC-1 through TC-16,
                    no TC-13)

---

## Files Modified This Session

  rtl/core/frontend/bpu/tb/tb_tage.sv
    -- BP-029: TC-63 through TC-66 appended
               Test count 62 -> 66
    -- BP-030: TC-67 and TC-68 appended
               Test count 66 -> 68

  prompts/BP-029.md -- complete, results written
  prompts/BP-030.md -- complete, results written

  Pending (not yet applied):
    PROJECT_STATUS.md -- see gaps listed above
    planning/verification/tage_coverage_plan.md
      -- CE-01 through CE-06 and closure table

---

## Next Session (033)

### Step 1: Apply pending planning doc updates

  PROJECT_STATUS.md:
    - Update header date to session_handoff-032
    - Fix tage.sv BP-029 and BP-030 module row entries
    - Mark Open Item 6 Complete
    - Add proper BP-029 and BP-030 entries to TAGE
      decomposition section

  tage_coverage_plan.md:
    - Mark CE-01 through CE-06 covered
    - Add BP-029 and BP-030 to Coverage Closure
      Sessions table
    - Update overall status

### Step 2: ITTAGE research

Research questions to resolve before implementation:

  1. History length configuration. TAGE uses geometric
     series (T1-T4). ITTAGE typically uses a separate
     geometric series tuned for indirect branches.
     What lengths fit within GHR_WIDTH=256 and the
     existing bp_defines_pkg parameter set?

  2. Tag width policy. TAGE tags are THIS_TAG_BITS
     derived from MAX_TAG_WIDTH. ITTAGE tags may
     need to be wider to reduce aliasing on indirect
     branch targets. What tag width is appropriate?

  3. Target address storage. ITTAGE predicts a target
     address, not just taken/not-taken. Target width
     is VA_WIDTH=40. Storage implications for the
     table entry format need to be defined before
     bp_structs_pkg.sv is extended.

  4. Number of tables. TAGE has T0 (BIM) plus T1-T4.
     ITTAGE in Seznec's work typically uses a similar
     count. Confirm table count fits pipeline stage s3.

  5. Interaction with RAS. At s3, ITTAGE and RAS both
     operate. Priority and override policy for
     CALL/RETURN vs indirect branch needs to be
     defined before ITTAGE interfaces are written.

  6. Update policy differences from TAGE. TAGE updates
     CTR and USE. ITTAGE updates CTR, USE, and target.
     Confirm whether target is always updated on a
     hit or only on misprediction.

  Research should produce an ittage_interfaces.md
  planning document analogous to tage_interfaces.md
  before any RTL is written.

### Step 3: Write ITTAGE interfaces document

  ittage_interfaces.md covering:
    - Port list with pipeline stage annotations
    - Table entry format
    - History length series
    - Tag width
    - Target storage width
    - Update policy
    - Interaction with RAS and SC at bp_cluster level
