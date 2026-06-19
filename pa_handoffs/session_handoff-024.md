<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 024
Written by Claude.ai at end of session-023, for use at start of session-024.

Date: 2026-04-08
This session ran BP-010f, BP-011, BP-012, BP-013,
generated BP-014a (ready to run), and established
the validation plan for TAGE through to ITTAGE.
Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## What This Session Covered

Session context restored from session_handoff-023.

Primary work:
- BP-010f executed: slot 1 symmetry tests added to
  tb_tage.sv. TC-22 (slot 1 prediction) and TC-23
  (slot 1 update) both pass. All 23 tests passing.
  No RTL defects found.
- BP-011 executed: four round-trip tests added to
  tb_tage.sv. All 27 tests passing.
  Two RTL defects found (not fixed in BP-011):
  Defect 1: t_idx_r1/t_tag_r1 always zero in
    tage_cntrl.sv -- hash signals not exposed from
    tage_table.sv or tage_bim.sv.
  Defect 2: T0 prm_ctr mis-extracted in
    tage_cntrl.sv -- [TAGE_T0_CTR_BITS-1:0]
    extracts {CTR[0],VAL} instead of CTR[1:0].
  Testbench worked around both defects via meta
  field overrides after capture.
- BP-012 executed: both RTL defects fixed.
  tage_table.sv: idx_hash_p0 and tag_hash_p0
    output ports added.
  tage_bim.sv: idx_hash_p0 output port added.
  tage_cntrl.sv: t_idx_p0/t_tag_p0 input ports
    added, register stage added, T0 CTR extraction
    fixed at two sites ([TAGE_T0_CTR_BITS-1:0]
    changed to [TAGE_T0_CTR_BITS:1]).
  tage.sv: w_idx_p0/w_tag_p0 interconnect wires
    added and wired through.
  All 27 tests pass after fixes. Lint clean.
- BP-013 executed: cleanup session.
  tb_tage.sv: 13 redundant meta override statements
    removed from four round-trip tests. Associated
    stale NOTE comments removed.
  tage_table_interfaces.md: idx_hash_p0 and
    tag_hash_p0 added to T1-TN port list and
    semantics section.
  All 27 tests still pass.
- BP-014a generated: four CTR round-trip tests
  covering rule rows 1/2, 3/4, 5/6, 7/8.
  Prompt ready at prompts/BP-014a.md.
  To be run and assessed in session-024.
- Tech debt #33 recorded: simultaneous/competing
  prediction and update protocol undefined.

---

## Decisions Made This Session

### TAGE full validation plan (settled this session)

The agreed validation and development sequence is:

  1. Full validation of non-overlapping prediction
     and update against all known rules (BP-014
     series). Covers all CTR update rows, all
     Table 7 useful rows, all allocation rules,
     all UAON rules, aging enabled round-trips.
  2. Cleanup pass: CLI-001/002/004/008/011/012,
     TI7, debts #24/#25/#27/#28, delete run-prompt
     skill. Before bp_cluster integration.
  3. Implementation and validation of overlapping
     prediction and update (debt #33). Requires
     protocol definition and additional signals.
  4. ITTAGE: largely pro forma reuse of TAGE
     control. New metadata to be documented and
     tested. TAGE must be fully validated and
     clean before ITTAGE begins.

### BP-014 series scope

BP-014a: CTR rows 1/2, 3/4, 5/6, 7/8.
  All four tests use T1 as prm, T2 as alt
  (both tagged, both hitting). TC-31 uses
  hierarchical write to uaon[0]=4'h8 to force
  using_prm=0 for rows 7/8. uaon[0] restored
  to 4'h0 after TC-31.

BP-014b and beyond (scope TBD in session-024
after BP-014a results reviewed):
  Remaining CTR rows to cover:
    Rows 9/10: using_prm=0, pred_diff=1, alt wrong
      -- prm INC + alt DEC.
    Rows 11/12: using_prm=0, pred_diff=0, alt wrong
      -- alt DEC only.
    Rows 13b/13c: both T0, wrong -- T0 DEC.
    Rows 15/17: prm tagged, alt T0, wrong/correct.
    Rows 18-21: prm T0, alt tagged.
  Table 7 useful rows not yet covered by round-trip:
    Row 4: preds_diff=1, using_prm=1, mispredict=1
      -- Dec u_eff on prm.
    Row 5: preds_diff=1, using_prm=0, mispredict=0
      -- Inc u_eff on alt.
    Row 6: preds_diff=1, using_prm=0, mispredict=1
      -- Dec u_eff on alt.
  Allocation rules not yet covered by round-trip:
    No-consecutive-table constraint.
    Provider=T0 misprediction, alloc into T1-T4.
  UAON full round-trip not yet covered:
    Predict with weak CTR, update, verify counter
    changed, re-predict and verify mux behavior
    changed.
  Aging round-trip not yet covered:
    Any round-trip with aging enabled
    (lcl_epoch > 0, u_eff != USEFUL).

### T1/T2 table pairing for dual-tagged tests

T1 as primary, T2 as alternate is the standard
pairing for all dual-tagged round-trip tests in
the BP-014 series. Finer table combination coverage
(T1/T3, T2/T4, etc.) is deferred -- no process
defined for that yet.

### UAON counter setup via hierarchical write

For tests requiring using_prm=0, write
tb.u_dut.u_tage_cntrl.uaon[0] directly via
hierarchical reference before predicting.
Restore to 4'h0 after the test completes to
avoid contaminating subsequent tests.

### Tech debt #33 (recorded this session)

Simultaneous/competing prediction and update
protocol is undefined. No signals defined for
same-cycle pred+upd to overlapping entries.
Read-during-write contract covers mutual exclusion
assumption but does not define arbitration,
ordering, or stall signaling. Resolution path:
define protocol and additional signals before
bp_cluster integration. Requires interface doc
update and new testbench coverage.

---

## Technical Debt Modified This Session

None modified. Debt #33 added (open).

---

## Files Created This Session

  prompts/BP-010f.md  -- experiment file, PASS
  prompts/BP-011.md   -- experiment file, PASS
  prompts/BP-012.md   -- experiment file, PASS
  prompts/BP-013.md   -- experiment file, PASS
  prompts/BP-014a.md  -- prompt ready to run

---

## Files Modified This Session

  frontend/branch_predictor/rtl/tage_table.sv
    -- BP-012: idx_hash_p0 and tag_hash_p0 output
       ports added.

  frontend/branch_predictor/rtl/tage_bim.sv
    -- BP-012: idx_hash_p0 output port added.

  frontend/branch_predictor/rtl/tage_cntrl.sv
    -- BP-012: t_idx_p0/t_tag_p0 input ports added.
       idx_tag_pipe_ff always_ff added to register
       into t_idx_r1/t_tag_r1. T0 CTR extraction
       fixed at two sites in pred_logic.

  frontend/branch_predictor/rtl/tage.sv
    -- BP-012: w_idx_p0/w_tag_p0 interconnect wires
       added. tage_bim, tage_table, and tage_cntrl
       port maps updated.

  frontend/branch_predictor/tb/tb_tage.sv
    -- BP-010f: TC-22 slot1_pred_tst added.
       TC-23 slot1_upd_tst added. Test count 23.
    -- BP-011: TC-24 through TC-27 added (four
       round-trip tests). Test count 27.
    -- BP-013: 13 redundant meta overrides removed
       from TC-24 through TC-27.

  planning/interfaces/tage_table_interfaces.md
    -- BP-013: idx_hash_p0 and tag_hash_p0 added
       to T1-TN port list and semantics section.

---

## Next Session (024)

### Step 1: Run BP-014a

Prompt is ready at prompts/BP-014a.md.

Run in a fresh Claude Code session.
Context load:
  frontend/branch_predictor/rtl/tage.sv
  frontend/branch_predictor/rtl/tage_bim.sv
  frontend/branch_predictor/rtl/tage_table.sv
  frontend/branch_predictor/rtl/tage_cntrl.sv
  frontend/branch_predictor/rtl/bp_defines_pkg.sv
  frontend/branch_predictor/rtl/bp_structs_pkg.sv
  frontend/branch_predictor/tb/tb_tage.sv
  planning/interfaces/tage_interfaces.md
  planning/interfaces/tage_table_interfaces.md
  planning/arch/tage_cntrl_decisions.md
  planning/arch/tage_cntrl_ctr_update_rules.md
  planning/arch/tage_cntrl_use_update_rules.md
  planning/arch/tage_cntrl_alloc_rules.md
  planning/arch/tage_cntrl_uaon_update_rules.md
  planning/testbenches/tage_tb_decisions.md

### Step 2: Assess BP-014a results

Paste BP-014a results into session-024 Claude.ai.
Assess for RTL defects, unexpected behavior, and
coverage gaps before proceeding to BP-014b.

### Step 3: Scope and generate BP-014b

Based on BP-014a results, scope BP-014b from the
remaining coverage list above. Candidate scope for
BP-014b: CTR rows 9/10, 11/12, 13b/13c. Rows
15/17 and 18-21 may form BP-014c depending on
context budget.

### PROJECT_STATUS.md Updates Needed
This is complete:

1. Module table:
   - tage_table.sv: note BP-012 adds idx_hash_p0
     and tag_hash_p0 output ports.
   - tage_bim.sv: note BP-012 adds idx_hash_p0
     output port.
   - tage_cntrl.sv: note BP-012 fixes t_idx_r1/
     t_tag_r1 undriven and T0 prm_ctr extraction.
   - tage.sv: note BP-012 wiring additions.
   - tb_tage.sv: update test count to 27 passing
     after BP-010f through BP-013. BP-014a pending.

2. Technical Debt table:
   - Debt #33: add as OPEN. Simultaneous prediction
     and update protocol undefined. Resolution path:
     before bp_cluster integration.

3. Architectural Decisions / TAGE decomposition:
   - Add BP-010f as complete.
   - Add BP-011 as complete. Note two RTL defects
     found and fixed in BP-012.
   - Add BP-012 as complete.
   - Add BP-013 as complete.
   - Add BP-014a as ready to run.
   - Note t_idx_r1/t_tag_r1 fix and T0 CTR
     extraction fix applied in BP-012.

4. Open Items: add TAGE full validation plan
   and sequence as described in Decisions section.
