# Session Handoff 044
Written by Claude.ai at end of session-043.
Date: 2026-05-20

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Session Summary

Session-043 completed five tasks and advanced manual
testbench methodology significantly:

  - BP-040 complete: TD #46 and TD #50 resolved in
    one session.
  - TB-001 complete: TAGE task infrastructure
    testbench created.
  - TB-002 complete: TAGE manual testbench created.
  - Planning documents created and updated.
  - Manual test development begun for TAGE CTR
    update rules. Helper task factoring discussed.

---

## What This Session Accomplished

### BP-040 (complete)

TD #46 resolved: tb_ittage_cntrl.sv missing trx_type
port connection fixed. 76 existing tests pass.

Three additional bugs exposed in ittage_cntrl.sv
once trx_type_tb=0 was wired. These bugs require
independent verification against planning documents
before results are accepted. See Open Technical Debt.

TD #50 resolved: FAST_INIT audit complete.
  - tage.sv, tage_table.sv, ittage_table.sv:
    compliant, no changes.
  - ittage.sv: one nonconformance found and fixed.
    tbl_ri_active was not muxed through fast_init
    in the generate loop.
  - make all: zero errors, zero warnings.

### TB-001 (complete)

New testbench tb_tage_tasks.sv created. Task
infrastructure only. One throwaway round-trip
sanity test passes. This was a precursor to TB-002
and established the hierarchical RAM path patterns.

### TB-002 (complete)

TAGE manual testbench created. Three files:
  - utils.svh: shared utility tasks
  - tb_tage_manual_tasks.svh: TAGE-specific tasks
  - tb_tage_manual.sv: top level

Round-trip sanity test passes including RAM
read-back verify step before any prediction.
No RTL modifications required.

Key tasks delivered:
  tage_ram_write, tage_ram_read
  tage_set_pred_inp, tage_set_upd_inp
  tage_predict, tage_update
  tage_check_pred_meta
  tage_round_trip_sanity

Makefile: sim_tage_manual target added.

### Planning Documents

New documents created this session:

  planning/arch/sram_init.md
    Documents FAST_INIT contract, normal mode
    operation, parent module responsibilities,
    sample code patterns, module inventory, and
    plusarg names by module.

  planning/testbenches/manual_tb_decisions.md
    General manual testbench structure, naming
    conventions, utility task specifications,
    staging FF pattern, simulation controls,
    DUT port expansion signal declarations.

  planning/testbenches/tage_mtb_decisions.md
    Updated with DUT ready signal, expansion
    port lists for Category 1 and Category 2
    ports. T0 and T1-T4 RAM access paths to
    be added after verification.

### Manual Test Development

Jeff has begun writing tage_ctr_test covering
all rows of tage_cntrl_ctr_update_rules.md.
Rows 1-3 written. Helper task factoring discussed
to reduce per-row text:

  set_ctr_row    -- sets all per-row varying fields
                    in pred_meta and upd_data.
                    Arguments: using_primary,
                    pred_tkn, resolved_taken,
                    prm_tkn, alt_tkn, prm_comp,
                    alt_comp.
  reset_ctr_entries -- resets pcomp and acomp RAM
                    entries to known state.
  check_ctr_row  -- reads and checks pcomp and
                    acomp entries.
  tage_cmp_ram_entry_t0 -- T0-specific compare,
                    2b CTR width, valid and ctr
                    fields only.
  check_ctr_row_t0 -- reads T0 entry and calls
                    tage_cmp_ram_entry_t0.

For rows 13a-d (T0 provider): pcomp and acomp
are set to 0 via set_ctr_row arguments. T0 RAM
entry written directly via tage_ram_write(0,...).
No reset_t0_entry wrapper needed -- tage_ram_write
handles tbl==0 directly.

---

## Process Methodology Updates

### Three-session split approach

Discussed as mitigation for Claude Code rationalizing
RTL changes to pass tests. Approach:
  Session 1: write tests against planning documents
    only, no RTL in context, no writes.
  Session 2: implement RTL with no tests in context.
  Session 3: diagnostic only, read both, no writes,
    report discrepancies with spec citations.

Manual testbench workflow implements a stronger
version: Jeff writes test cases with hand-generated
expected values. Claude Code writes only task
infrastructure. Expected values never come from
Claude Code.

### Constraint on RTL changes

Before modifying any RTL, Claude Code must cite
the specific rule row in a loaded planning document
that the current RTL violates. If it cannot cite
a rule it must stop and report rather than fix.
This constraint belongs in the Constraints section
of prompts, not in Results Capture after the fact.

---

## Open Technical Debt

  - TD #43: ittage_pred_strong definition in
    ittage_cntrl_decisions.md incorrect. Deferred.
  - TD #44: Decoration flags correction pending
    TD #43. Deferred.
  - TD #45: TAGE T0 index handling needs revisit.
  - TD #46: CLOSED. trx_type port connected in
    tb_ittage_cntrl.sv. 76 tests pass.
  - TD #49: Arb queue status port renaming deferred
    to cleanup session before bp_cluster.
  - TD #50: CLOSED. FAST_INIT nonconformance in
    ittage.sv fixed. All modules audited.
  - TD #51: CTR/USE/TGT update rule audit for
    ittage. Still open. Independent round-trip
    test set required. See next session plans.
  - BP-040 RTL changes: three bugs reported in
    ittage_cntrl.sv require independent verification
    against planning documents. Bug B (trx_type &&
    guard removal), Bug C (CTR signal swap), Bug D
    (alc_index_u0 source change) all contradict
    prior bug fixes. Do not close until verified.

---

## Next Session (044)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-044.md (this file)
  CLAUDE.md

### Planned work

**Step 1 -- Interactive debug of tage_ctr_test**
  Jeff has written rows 1-3 of tage_ctr_test
  exercising tage_cntrl_ctr_update_rules.md.
  Remaining rows 4-18 to be written and debugged.
  Helper tasks set_ctr_row, reset_ctr_entries,
  check_ctr_row, tage_cmp_ram_entry_t0,
  check_ctr_row_t0 to be finalized.
  This is manual development work with Claude.ai
  support for debugging and review.

**Step 2 -- Verify BP-040 RTL changes**
  Independently verify Bug B, Bug C, Bug D
  against ittage_cntrl planning documents before
  accepting BP-040 as fully closed.
  Reference documents:
    ittage_cntrl_ctr_update_rules.md
    ittage_cntrl_use_update_rules.md
    ittage_cntrl_decisions.md

**Step 3 -- TD #51 update rule audit**
  Once tage_ctr_test methodology is validated,
  apply same approach to ittage. New independent
  round-trip test set for tb_ittage.sv covering
  ittage_cntrl_ctr_update_rules.md and
  ittage_cntrl_use_update_rules.md row by row.
  This is a candidate for the three-session split:
  diagnostic first, then fix, then verify.

