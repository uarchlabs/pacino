<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 023
Written by Claude.ai at end of session-022, for use at start of session-023.

Date: 2026-04-08
This session ran BP-010c, BP-010d, BP-010e, applied
HAND-FIX-001 and HAND-FIX-002, generated BP-010f
(ready to run), and updated tage_tb_decisions.md.
Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## What This Session Covered

Session context restored from session_handoff-022.

Primary work:
- BP-010c executed: 7 update path tests added to
  tb_tage.sv for slot 0. All 8 tests passing
  (tage_rdy_tst + 7 update tests). Lint clean.
  RTL bug found: use_we/epc_we gated by prm_match
  only, USE/EPC writes silently dropped when
  using_primary=0. Not fixed in BP-010c per session
  constraint. Fixed by HAND-FIX-001 after session.
- HAND-FIX-001 applied to tage_table.sv:
  use_we_s0/s1 and epc_we_s0/s1 now gate on
  prm_alt_match (prm_match | alt_match) instead of
  prm_match alone. prm_alt_match_s0 and
  prm_alt_match_s1 signals added. Both slots fixed.
  Debt #29 added and immediately closed.
- BP-010d executed: 7 coverage gap tests added to
  tb_tage.sv. All 15 tests passing. Covers:
  USE/EPC update when using_primary=0 (Table 7
  rows 5 and 6, confirmed working with HAND-FIX-001),
  UAON INC and DEC, CTR saturation at max and min
  for T0 (2b) and T1 (3b), alloc no-candidate path.
  No new bugs found.
- BP-010e executed: 6 prediction path tests added to
  tb_tage.sv. All 21 tests passing. Covers: T0-only
  prediction, single T1 hit, dual T1+T2 hit with
  provider selection, UAON override active, UAON
  override suppressed, tage_pred_rdy_p2 timing.
  RTL bug found: tage_use_alt_on_na set from
  uaon_trig only, not gated by counter threshold.
  Fixed by HAND-FIX-002 after session.
  Staging always_ff required for prediction inputs
  -- same Verilator 5.020 limitation as update path.
  Added to tage_tb_decisions.md.
- HAND-FIX-002 applied to tage_cntrl.sv:
  tage_use_alt_on_na now set only when uaon_trig
  AND counter MSB both set:
  meta_p1[s].tage_use_alt_on_na =
    uaon_trig_p1[s] & uaon[s][3];
  TC-E in tb_tage.sv updated to expect
  tage_use_alt_on_na==0 when counter below threshold.
  Debt #30 added and immediately closed.
- BP-010f generated: slot 1 symmetry tests.
  Prompt ready at prompts/BP-010f.md.
- run-prompt skill identified as unused. Delete in
  cleanup pass.

---

## Decisions Made This Session

### Staging always_ff is universal
Verilator 5.020 --timing does not propagate blocking
assignments to struct-typed array elements in initial
block coroutines through always_comb. This applies to
both update inputs (tage_upd_inp_u0) and prediction
inputs (tage_pred_inp_p0). The staging always_ff
pattern is mandatory for ALL struct-typed array DUT
inputs in tb_tage.sv. Document added to
tage_tb_decisions.md.

### HAND-FIX-001: tage_table.sv use_we/epc_we
use_we and epc_we for both slots now gate on
prm_alt_match = prm_match | alt_match.
Signals prm_alt_match_s0 and prm_alt_match_s1 added.
Required for Table 7 rows 5 and 6 to function.
Found BP-010c, fixed session-022.

### HAND-FIX-002: tage_cntrl.sv tage_use_alt_on_na
tage_use_alt_on_na reflects whether UAON mux actually
switched prediction source, not merely whether trigger
condition was met. Fix: gate on uaon_trig AND
uaon[s][3] (counter at or above threshold).
Found BP-010e, fixed session-022.

### Prediction test coverage complete (slot 0)
Open-loop prediction tests for slot 0 are complete.
Round-trip testing (predict + update same entry)
deferred to BP-011 as its own context.

### BP-010f scope
Slot 1 symmetry only. Two tests: one prediction,
one update. Primary goal is to confirm slot 1
elaboration, routing, and RAM independence from
slot 0. Not exhaustive coverage of slot 1.

---

## Technical Debt Modified This Session

Debt #29: CLOSED. HAND-FIX-001 applied to
  tage_table.sv. use_we/epc_we gating corrected
  for both slots. Found BP-010c, fixed session-022.

Debt #30: CLOSED. HAND-FIX-002 applied to
  tage_cntrl.sv. tage_use_alt_on_na semantics
  corrected. Found BP-010e, fixed session-022.

---

## Technical Debt Added This Session

None. Debts #29 and #30 added and immediately closed.

---

## Files Created This Session

  prompts/BP-010c.md  -- experiment file, PASS
  prompts/BP-010d.md  -- experiment file, PASS
  prompts/BP-010e.md  -- experiment file, PASS
  prompts/BP-010f.md  -- prompt ready to run

---

## Files Modified This Session

  tage_table.sv
    -- HAND-FIX-001: prm_alt_match_s0/s1 added.
       use_we_s0/s1 and epc_we_s0/s1 gating changed
       from prm_match to prm_alt_match. Both slots.

  tage_cntrl.sv
    -- HAND-FIX-002: tage_use_alt_on_na now gated
       on uaon_trig_p1[s] & uaon[s][3].

  frontend/branch_predictor/tb/tb_tage.sv
    -- BP-010c: 7 update path tests added (slot 0)
    -- BP-010d: 7 coverage gap tests added (slot 0)
    -- BP-010e: 6 prediction path tests added (slot 0)
    -- staging always_ff extended for prediction
       inputs (BP-010e)
    -- TC-E expected value corrected for
       tage_use_alt_on_na after HAND-FIX-002

  planning/testbenches/tage_tb_decisions.md
    -- staging always_ff universal rule added
       (prediction inputs require staging, same
       as update inputs)

---

## Next Session

### BP-010f: slot 1 symmetry tests
Prompt is ready at prompts/BP-010f.md.

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
  planning/testbenches/tage_tb_decisions.md
  planning/arch/tage_cntrl_decisions.md

After BP-010f passes:
  BP-011: round-trip tests (predict + update same
    entry, misprediction scenarios). New context.
  Cleanup pass: CLI-001/002/004/008/011/012, TI7,
    debts #27/#28, delete run-prompt skill.
    Before bp_cluster integration.

### PROJECT_STATUS.md Updates Needed

1. Module table:
   - tage_table.sv: note HAND-FIX-001 applied.
     prm_alt_match added. use_we/epc_we gating fixed.
   - tage_cntrl.sv: note HAND-FIX-002 applied.
     tage_use_alt_on_na semantics corrected.
   - tb_tage.sv: update test count. 21 tests passing
     after BP-010c/d/e. BP-010f pending.

2. Technical Debt table:
   - Debt #29: add as CLOSED.
   - Debt #30: add as CLOSED.

3. Architectural Decisions / TAGE decomposition:
   - Add BP-010c as complete.
   - Add BP-010d as complete.
   - Add BP-010e as complete.
   - Add BP-010f as ready to run.
   - Note HAND-FIX-001 and HAND-FIX-002 applied.
   - Note staging always_ff is universal for all
     struct-typed array DUT inputs in tb_tage.sv.

4. Add testbench decisions section reference:
   - planning/testbenches/tage_tb_decisions.md is
     authoritative for all TAGE testbench decisions.
     Load in all BP-010* prompts.
