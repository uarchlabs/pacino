<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 021
Written by Claude.ai at end of session-020, for use at start of session-021.

Date: 2026-04-07
This session ran BP-008b, generated and ran BP-009 (failed),
generated and ran BP-009a (partial pass), generated BP-009a-1
(ready to run), updated validate_and_extract.py with file
existence check, and added TAGE_TBL_* vectors to
bp_defines_pkg.sv. Read PROJECT_STATUS.md, then this file,
then CLAUDE.md to restore full context.

---

## What This Session Covered

Session context restored from session_handoff-020.

Primary work:
- BP-008b executed: tage_cntrl.sv update logic complete.
  Debts #19 and #22 closed. Lint clean.
- validate_and_extract.py updated: added file existence
  check for Context Loaded entries. Fixed bug where bare
  @path format was not recognized (script only handled
  - @path list format). Strict bare @path now enforced;
  any non-blank line not starting with @ fails validation.
- bp_defines_pkg.sv updated: TAGE_TBL_* parameter vectors
  added as authoritative per-table parameter source.
  Redundant scalar parameters commented out. Debt #24 added.
- BP-009 generated and executed: tage.sv structural top
  level. Lint passed but functionally incorrect --
  THIS_TAG_BITS=0 and THIS_USE_WIDTH=0 cause zero-size
  elaboration errors in tage_table.sv when T0 is
  instantiated through the generate loop.
- Architecture decision: T0 gets its own dedicated module
  tage_bim.sv rather than forcing T0 through tage_table.
- tage_table_interfaces.md updated: split into T0 (tage_bim)
  and T1-TN (tage_table) sections. File paths corrected.
  Bank address assignment section added. ALLOC_DATA_WIDTH
  and CNTRL_BITS_WIDTH defined separately for T0 and T1-TN.
  TBL_SEL_WIDTH corrected to use TAGE_TBL_SEL_WIDTH.
- BP-009a generated and executed: created tage_bim.sv,
  fixed 3 port width discrepancies in tage_table.sv.
  Two bugs found post-execution: bank_addr strapped to
  1'b0 in both modules, TBL_SEL_WIDTH default wrong in
  tage_table, ram_din write data uses if/else chain.
- BP-009a-1 generated: fixes all three bugs. Ready to run.
- Prompt template drift noted. Canonical template is
  prompts/REPORT_TEMPLATE.md. Note added to README.
- Debts #25, #26 added. #27 skipped (harmless, README note
  sufficient).

---

## Decisions Made This Session

### T0 separated into tage_bim.sv
tage_table.sv cannot handle THIS_TAG_BITS=0 or
THIS_USE_WIDTH=0. T0 is now a dedicated module tage_bim.sv.
tage_table.sv serves T1-T4 only. tage.sv will instantiate
tage_bim for T0 and use a generate loop for T1-T4.

### TAGE_TBL_* vectors authoritative
bp_defines_pkg.sv now contains TAGE_TBL_* parameter vectors
as the single source of truth for per-table parameters.
Redundant scalar parameters (TAGE_T1_BANKS, TAGE_T1_ENTRIES,
etc.) are commented out pending cleanup (debt #24).

### validate_and_extract.py Context Loaded rules
Bare @path is the only accepted format. Any non-blank line
between ## Context Loaded and ## Hypothesis that does not
start with @ fails validation. File existence is checked
relative to repo root (cwd). Missing files fail validation.

### Bank address decomposition (settled)
For bw_ram with BANKS=2 and THIS_INDEX_BITS-wide index:
  bank_addr = index[THIS_INDEX_BITS-1]
  row_addr  = index[THIS_INDEX_BITS-2:0]
Applies to tage_bim and tage_table, all paths (prediction,
update, tbl_ri). Documented in tage_table_interfaces.md.

### Prompt template
Canonical template is prompts/REPORT_TEMPLATE.md. Supply
it to Claude.ai when generating prompts to prevent drift.

---

## Technical Debt Modified This Session

Debt #19: CLOSED (BP-008b complete, uaon_ff removed).
Debt #22: CLOSED (BP-008b complete, T0 CTR gating fixed).
Debt #23: CLOSED (validate_and_extract.py Task ID check
  implemented in session-020, confirmed this session).

---

## Technical Debt Added This Session

Debt #24: TAGE_TBL_* vectors now authoritative. Redundant
  scalar parameters and FIXME-flagged consumers need cleanup
  pass after BP-010.
Debt #25: Context Loaded paths for bp_defines_pkg.sv and
  bp_structs_pkg.sv use short paths rtl/ in BP-007d through
  BP-008b. Correct to frontend/branch_predictor/rtl/ prefix.
  Fix in cleanup pass after BP-010.
Debt #26: TBL_SEL_WIDTH default in tage_table.sv uses
  $clog2(TAGE_NUM_TABLES)+1 instead of TAGE_TBL_SEL_WIDTH.
  Fix deferred -- testbench implicitly relies on wrong value.
  Resolve when testbench updated for BP-010.

---

## Files Created This Session

  BP-008b.md       -- experiment file, PASS
  BP-009.md        -- experiment file, lint PASS,
                      functionally incorrect (T0 via
                      tage_table, zero-size elaboration)
  BP-009a.md       -- experiment file, partial PASS
                      (tage_bim created, tage_table fixed,
                      bank_addr bug found post-execution)
  BP-009a-1.md     -- prompt ready to run
  validate_and_extract.py -- updated, file existence check
                      added, strict bare @path enforced

## Files Modified This Session

  bp_defines_pkg.sv
    -- TAGE_TBL_* parameter vectors added.
    -- Redundant scalar parameters commented out.
    -- TAGE_TBL_IDX[0:4] localparams now reference vectors.
    -- TAGE_MAX_AWIDTH simplified to hardcoded 11.
    -- MAX_* widths hardcoded (expressions commented out).

  tage_table_interfaces.md
    -- Split into T0 (tage_bim) and T1-TN (tage_table)
       sections throughout.
    -- File paths corrected (rtl/ subdir added).
    -- Bank address assignment section added.
    -- ALLOC_DATA_WIDTH and CNTRL_BITS_WIDTH defined
       separately for T0 and T1-TN.
    -- TBL_SEL_WIDTH corrected to TAGE_TBL_SEL_WIDTH.
    -- tbl_ri_wa sized to THIS_INDEX_BITS on T0 (not
       MAX_IDX_WIDTH).

  tage_table.sv
    -- upd_index_u0, alc_index_u0, tbl_ri_wa changed
       from [MAX_IDX_WIDTH-1:0] to [THIS_INDEX_BITS-1:0].
    -- Redundant index slices removed from addr_mux bodies.
    -- (bank_addr and ram_din bugs not yet fixed,
       pending BP-009a-1)

  tage_bim.sv  -- new file created (BP-009a)
    -- bank_addr bug present (pending BP-009a-1)

---

## Next Session

### BP-009a-1: fix bank_addr, TBL_SEL_WIDTH, ram_din
Prompt is ready at prompts/BP-009a-1.md.

Run in a fresh Claude Code session.
Context load (6 files):
  frontend/branch_predictor/rtl/tage_bim.sv
  frontend/branch_predictor/rtl/tage_table.sv
  frontend/branch_predictor/tb/tb_tage_table.sv
  components/rtl/bw_ram.sv
  frontend/branch_predictor/rtl/bp_defines_pkg.sv
  frontend/branch_predictor/rtl/bp_structs_pkg.sv

After BP-009a-1 passes:
  BP-009b: regenerate tage.sv -- instantiate tage_bim
    for T0, generate loop over tage_table for T1-T4.
  BP-010: tage testbench.

### PROJECT_STATUS.md Updates Needed

These updates have been completed.

1. Module table:
   - tage_cntrl.sv: mark complete, BP-008b done.
   - tage_table.sv: note port fixes from BP-009a,
     bank_addr/ram_din fixes pending BP-009a-1.
   - tage_bim.sv: add as new module, BP-009a created,
     bank_addr fix pending BP-009a-1.
   - tage.sv: add as in-progress, BP-009 lint passed
     but functionally incorrect, BP-009b pending.
2. Technical Debt table:
   - Debt #19: mark CLOSED.
   - Debt #22: mark CLOSED.
   - Debt #24, #25, #26: add as new items.
3. Architectural Decisions / TAGE decomposition:
   - Add BP-008b as complete.
   - Add BP-009 as complete (lint only, structural).
   - Add BP-009a as complete (tage_bim created).
   - Add BP-009a-1 as ready to run.
   - Note tage_bim.sv as new module for T0.
   - Note tage_table.sv serves T1-T4 only.
4. Add bank address decomposition decision to
   Architectural Decisions section.

