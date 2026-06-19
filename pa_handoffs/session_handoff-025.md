<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 025
Written by Claude.ai at end of session-024, for use at start of session-025.

Date: 2026-04-09
This session ran BP-014a through BP-014h (eight prompt
sessions), completing the full TAGE validation plan
established in session-023. Read PROJECT_STATUS.md,
then this file, then CLAUDE.md to restore full context.

---

## What This Session Covered

Session context restored from session_handoff-024.

Primary work:
- BP-014a executed: four CTR round-trip tests added
  (TC-28 through TC-31). CTR rows 1/2, 3/4, 5/6, 7/8.
  All 31 tests passing.
  Finding: RTL ascending scan makes T2 primary and T1
  alternate when both hit. Prompt incorrectly labeled
  T1 as primary. Claude Code followed RTL correctly.
  Provider labeling clarified for all subsequent prompts:
  primary = longest-history tagged table that hits;
  alternate = next longest below primary.
- BP-014b executed: two CTR round-trip tests added
  (TC-32, TC-33). CTR rows 9/10, 11/12. Both using_prm=0
  via UAON. All 33 tests passing.
  Prompt discrepancy: TC-33 specified T2 CTR=3'b101 but
  that is not a UAON boundary. Claude Code used 3'b100
  per Background section. Prompt authoring error.
- BP-014c executed: two CTR round-trip tests added
  (TC-34, TC-35). CTR rows 13b, 13c. T0 sole provider,
  wrong prediction, CTR DEC. All 35 tests passing.
  Note: BIM RAM hierarchical path in prompt said u_ram0
  but RTL uses u_ram_s0. Claude Code used correct path
  from tage_tb_decisions.md.
- BP-014d executed: two CTR round-trip tests added
  (TC-36, TC-37). CTR rows 13a, 13d. T0 sole provider,
  correct prediction, CTR INC. All 37 tests passing.
  RTL DEFECT FOUND: T0 CTR update in tage_cntrl.sv
  keys on pred_crt (correct/wrong) not resolved_taken
  to determine INC vs DEC direction. Standard BIM
  behavior requires resolved_taken to drive direction.
  Row 13a (NT correct): RTL adds 1 (01->10) instead of
  subtracting 1 (01->00). Recorded as debt #34.
  Tests derive expected values from RTL behavior.
- BP-014e executed: two CTR round-trip tests added
  (TC-38, TC-39). CTR rows 14/15, 16/17. T1 prm, T0
  alt. Both tests exercise Table 7 USE updates via
  pred_diff=1. All 39 tests passing. No RTL defects.
- BP-014f executed: two UAON full round-trip tests
  added (TC-40, TC-41). UAON INC 7->8 causes mux
  switch to alt on re-predict. UAON DEC 8->7 restores
  mux to prm on re-predict. All 41 tests passing.
  Note: Claude Code initially reported Results Capture
  already written (saw populated markers from prompt
  template). Debt #35 recorded: add automated test
  count validation. lcl_epoch hierarchical path is
  lcl_epoch[0] (array), not lcl_epoch_0 (scalar).
- BP-014g executed: two allocation round-trip tests
  added (TC-42, TC-43). T0-provider positive allocation
  into T1 verified. T1-provider allocation into T2
  with T3 unchanged (no-consecutive guard) verified.
  All 43 tests passing.
  Note: PC=40'h1100 aliased bank=1 row=64 with BP-014a
  test PC=40'h09100. T2 at that address had USE=01 from
  prior test, causing T3 to be selected instead of T2.
  Fixed by explicit zeroing of T2-T4 before TC-43.
  General rule established: always explicitly zero
  T1-T4 entries at test PC when cond_mispredict=1
  and allocation behavior is under test.
- BP-014h executed: two aging round-trip tests added
  (TC-44, TC-45). age=1 entry (u_eff=USEFUL>>1=01)
  correctly skipped as allocation candidate. age=2
  entry (u_eff=0 despite USEFUL=10) correctly selected
  as allocation candidate. EPC=lcl_epoch=2 written
  correctly in allocated entry. All 45 tests passing.

Additional work this session:
- CTR update rules table row 18 redefined as
  unreachable/invalid (prm_comp=0 and alt_comp>0
  cannot occur through normal prediction flow).
  Rows 19-21 eliminated.
- Table 7 row 2 confirmed as invalid/don't-care:
  TTM=1 means both providers are T0 so pred_diff
  cannot be 1. pred_diff column corrected to x.
- Document title settled:
  "RISC-V RVA23 Decoupled Dual-Prediction Frontend
   Microarchitecture Specification"
- Tech debts #34 and #35 recorded (see below).

---

## Decisions Made This Session

### Provider labeling (settled this session)

The primary provider is the longest-history tagged
table that hits. The alternate provider is the next
longest-history tagged table that hits below the
primary. When both T1 and T2 hit and T3/T4 do not,
T2 is primary (comp=2, 13b history) and T1 is
alternate (comp=1, 8b history).

This replaces the incorrect "T1 as primary" language
used in the BP-014a prompt and session-023 handoff.

### CTR INC/DEC semantics (settled this session)

INC = add 1 (toward 11 for 3b, toward 11 for 2b).
DEC = subtract 1 (toward 00).
No directional qualification. The planning document
rows that say INC or DEC mean arithmetic increment
or decrement of the saturating counter value,
regardless of prediction direction.

### UAON hierarchical path

uaon[0] array notation confirmed:
  tb.u_dut.u_tage_cntrl.uaon[0]

### lcl_epoch hierarchical path

lcl_epoch[0] array notation confirmed:
  tb.u_dut.u_tage_cntrl.lcl_epoch[0]
Not lcl_epoch_0 (scalar). Use array notation in
all future prompts.

### BIM RAM hierarchical path

Confirmed from tage_tb_decisions.md:
  tb.u_dut.u_tage_bim.u_ram_s0.mem[bank][row]
Not u_ram0. Use u_ram_s0 in all future prompts.

### Address aliasing hygiene rule (settled this session)

When cond_mispredict=1 and allocation behavior is
under test, always explicitly zero T1-T4 entries
at the test PC before pre-loading test-specific
values, regardless of FAST_INIT state. Two different
PCs can map to the same bank/row (idx_hash collision).
FAST_INIT does not guarantee a clean state if a prior
test has written that address.

### TAGE validation plan status (complete)

All planned validation items are now covered:
  - CTR update rules: all reachable rows covered
    TC-28 through TC-39 (BP-014a through BP-014e).
    Row 18 confirmed unreachable, marked invalid.
  - Table 7 USE updates: all reachable rows covered.
    Row 2 confirmed invalid (TTM=1 implies pred_diff=0).
  - UAON: threshold crossing, mux switch, DEC restore
    covered TC-40, TC-41 (BP-014f).
  - Allocation: T0-provider positive, no-consecutive
    guard covered TC-42, TC-43 (BP-014g).
  - Aging: age=1 not candidate, age=2 is candidate,
    EPC written correctly TC-44, TC-45 (BP-014h).

---

## Technical Debt Modified This Session

Debt #34 added (open):
  T0 CTR update in tage_cntrl.sv keys on pred_crt
  (correct/wrong) not resolved_taken to determine
  INC vs DEC direction. Standard BIM behavior:
  resolved_taken=1 -> INC, resolved_taken=0 -> DEC.
  RTL pred_crt=1 always adds 1, pred_crt=0 always
  subtracts 1. Row 13a exposes defect: correctly
  predicted NT branch gets CTR pushed toward taken.
  Found BP-014d, TC-36. RTL not modified.
  Fix before bp_cluster integration.
  After fix, add targeted regression test covering
  row 13a.

Debt #35 added (open):
  No automated check that all expected test cases
  are present and executed in tb_tage.sv. Claude
  Code incorrectly reported BP-014f Results Capture
  as already written because it saw populated section
  markers. Risk: a session completes with fewer tests
  than specified and the shortfall goes undetected.
  Add a check to the sim target or a standalone
  script that compares declared test count in the
  prompt header against actual PASS lines in sim
  output. Before bp_cluster integration.

---

## Files Created This Session

  prompts/BP-014a.md  -- PASS, 31 tests
  prompts/BP-014b.md  -- PASS, 33 tests
  prompts/BP-014c.md  -- PASS, 35 tests
  prompts/BP-014d.md  -- PASS, 37 tests
  prompts/BP-014e.md  -- PASS, 39 tests
  prompts/BP-014f.md  -- PASS, 41 tests
  prompts/BP-014g.md  -- PASS, 43 tests
  prompts/BP-014h.md  -- PASS, 45 tests

---

## Files Modified This Session

  frontend/branch_predictor/tb/tb_tage.sv
    -- BP-014a: TC-28 through TC-31 added.
    -- BP-014b: TC-32, TC-33 added.
    -- BP-014c: TC-34, TC-35 added.
    -- BP-014d: TC-36, TC-37 added.
    -- BP-014e: TC-38, TC-39 added.
    -- BP-014f: TC-40, TC-41 added.
    -- BP-014g: TC-42, TC-43 added.
    -- BP-014h: TC-44, TC-45 added.
    -- Total: 45 tests passing.

---

## Next Session (025)

### Step 1: Update PROJECT_STATUS.md

See PROJECT_STATUS.md Updates Needed section below.
Do this before starting any other work.

### Step 2: Reassess remaining work

With TAGE validation complete the remaining items
before bp_cluster integration are:

1. Debt #34 fix: T0 CTR update RTL fix in
   tage_cntrl.sv. Change ctr_upd_comb to use
   resolved_taken to select INC or DEC. Add
   targeted regression test for row 13a after fix.

2. Cleanup pass:
   CLI-001, 002, 004, 008 -- interface doc naming
   CLI-011 -- loop_pred.sv port naming
   CLI-012 -- ubtb.sv port naming
   TI7 -- bp_tage_meta_t migration to tage_pred_meta_t
   Debt #24 -- TAGE_TBL_* scalar parameter cleanup
   Debt #25 -- context loaded path prefix corrections
   Debt #27 -- bw_ram BANKS=2 magic number
   Debt #28 -- planning/arch and planning/interfaces
               doc drift reconciliation

3. Debt #33: simultaneous prediction and update
   protocol definition. Requires interface doc
   update and new testbench coverage.

4. Debt #35: test count validation script.

5. bp_cluster integration begins after above complete.

### Step 3: Scope debt #34 fix

Debt #34 is a targeted single-file RTL fix in
tage_cntrl.sv. Scope as a standalone debug/fix
session before the cleanup pass. The fix is:
change the T0 CTR update path in ctr_upd_comb
to use resolved_taken (from tage_upd_inp_u0)
to select INC or DEC, not pred_crt. After fix,
add TC-36 regression (row 13a re-verify with
corrected expected value 2'b00 not 2'b10).

---

## PROJECT_STATUS.md Updates Needed

### 1. Module table updates

These edits are completed

tage.sv:
  - BP-014a through BP-014h: validation complete.
    45 tests passing in tb_tage.

tage_cntrl.sv:
  - BP-014d: T0 CTR update defect found (debt #34).
    RTL not yet fixed.

tb_tage (under tage.sv entry or separate):
  - Update test count to 45 passing after BP-014a
    through BP-014h complete.
  - BP-014a: TC-28 through TC-31 (CTR rows 1-8).
  - BP-014b: TC-32, TC-33 (CTR rows 9-12).
  - BP-014c: TC-34, TC-35 (T0 wrong, DEC).
  - BP-014d: TC-36, TC-37 (T0 correct, INC).
  - BP-014e: TC-38, TC-39 (prm tagged, alt T0).
  - BP-014f: TC-40, TC-41 (UAON full round-trip).
  - BP-014g: TC-42, TC-43 (allocation).
  - BP-014h: TC-44, TC-45 (aging).

### 2. Technical Debt table additions

These edits to tech debt are completed

Add debt #34 (open):
  T0 CTR update in tage_cntrl.sv keys on pred_crt
  not resolved_taken. pred_crt=1 always adds 1,
  pred_crt=0 always subtracts 1. Row 13a: correctly
  predicted NT branch gets CTR pushed toward taken.
  Found BP-014d TC-36. Fix before bp_cluster.
  Change ctr_upd_comb to use resolved_taken.
  Add row 13a regression after fix.

Add debt #35 (open):
  No automated check that all expected test cases
  are present and executed. Claude Code incorrectly
  claimed Results Capture already written in BP-014f
  by seeing populated section markers. Add sim target
  or standalone script comparing expected test count
  in prompt header against PASS lines in sim output.
  Before bp_cluster integration.

### 3. Architectural Decisions / TAGE decomposition
Edits to tage decomp completed - somewhat duplicates


Add under TAGE decomposition:
  BP-014a: complete. CTR rows 1/2, 3/4, 5/6, 7/8.
    TC-28 through TC-31. Provider labeling corrected:
    T2 primary (longer history), T1 alternate.
  BP-014b: complete. CTR rows 9/10, 11/12.
    TC-32, TC-33. using_prm=0 via UAON.
  BP-014c: complete. CTR rows 13b, 13c.
    TC-34, TC-35. T0 sole provider, wrong, DEC.
  BP-014d: complete. CTR rows 13a, 13d.
    TC-36, TC-37. T0 sole provider, correct, INC.
    Debt #34 found: T0 CTR update uses pred_crt
    not resolved_taken.
  BP-014e: complete. CTR rows 14/15, 16/17.
    TC-38, TC-39. T1 prm, T0 alt. USE updates
    exercised via pred_diff=1.
  BP-014f: complete. UAON full round-trip.
    TC-40, TC-41. Threshold crossing and mux
    restore verified. Debt #35 recorded.
  BP-014g: complete. Allocation round-trips.
    TC-42, TC-43. T0-provider alloc, no-consecutive
    guard verified.
  BP-014h: complete. Aging round-trips.
    TC-44, TC-45. age=1 not candidate, age=2 is
    candidate. EPC written correctly.

### 4. Open Items updates
Edits to open items completed

Update TAGE validation plan item:
  - Change status from "Before bp_cluster" to
    "COMPLETE -- BP-014a through BP-014h".

Add new open items:
  - Debt #34 RTL fix: T0 CTR update. Before bp_cluster.
  - Cleanup pass: CLI items, TI7, debts #24/#25/#27/#28.
    Before bp_cluster.
  - Debt #33: simultaneous pred+update protocol.
    Before bp_cluster.
  - Debt #35: test count validation script.
    Before bp_cluster.

### 5. Planning document corrections noted this session

Edits to planning documents completed

The following planning document corrections were
identified and should be applied during the cleanup
pass:

tage_cntrl_ctr_update_rules.md:
  - Row 18: mark as unreachable/invalid. prm_comp=0
    and alt_comp>0 cannot occur through normal
    prediction flow. Rows 19-21 eliminated.

tage_cntrl_use_update_rules.md (Table 7):
  - Row 2: pred_diff column corrected from 1 to x
    (don't care). TTM=1 means both providers are T0
    so pred_diff is structurally 0. pred_diff=1 with
    TTM=1 is unreachable.

