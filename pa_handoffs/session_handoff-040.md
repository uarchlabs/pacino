# Session Handoff 040
Written by Claude.ai at end of session-039.
Date: 2026-04-29

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Session Summary

Session-039 completed BP-033 / BP-033-FIX-1: the
ittage_table.sv implementation and testbench. A first
attempt (BP-033) passed simulation but contained a
correlated RTL+testbench bug. The bug was identified
during Claude.ai review, the prompt was corrected, and
BP-033-FIX-1 produced a clean result with 32/32 checks
passing and zero lint warnings.

This session also produced a methodology improvement:
pre-computing testbench expected values in the prompt
is now a confirmed requirement.

---

## What This Session Accomplished

### BP-033 (abandoned)

First attempt at ittage_table.sv. Completed with 24/24
checks passing and lint clean. Abandoned after Claude.ai
review identified:

  - ittage_pred_val_p0[s] was incorrectly gating
    hit_p1[s]. A p0 signal cannot gate a p1 output.
    The hit path must be derived from ram_dout and
    tag_hash_p1 only, identical to tage_table.

  - The testbench did not catch this because expected
    values were not specified in the prompt. Claude Code
    wrote tests that matched its own (incorrect) RTL.

Files written then removed:
  rtl/core/frontend/bpu/rtl/ittage_table.sv
  rtl/core/frontend/bpu/tb/tb_ittage_table.sv

---

### BP-033-FIX-1 (complete)

Re-implementation with corrected prompt. Key prompt
changes from BP-033:

  - Binding decision 11 added: hit_p1[s] derived solely
    from ram_dout and tag_hash_p1. ittage_pred_val_p0
    must not appear on the hit or read path. Explicit
    instruction to copy tage_table.sv hit_p1 assign
    verbatim.

  - Test Vector Table added to prompt with all expected
    values pre-computed from spec before any code is
    written. Claude Code cannot fit tests to RTL when
    expected values are fixed in the prompt.

  - TC-PRED-VAL-ZERO added: valid entry loaded, predict
    with pred_val=0, expected hit_p1=1. This is the
    specific test that catches the p0/p1 gating bug.

  - Requirement 6 made explicit: if a check fails, fix
    the RTL -- do not adjust the expected value.

Result: 32/32 checks pass, lint clean, 41 minutes,
83% context with compaction.

Files delivered:
  rtl/core/frontend/bpu/rtl/ittage_table.sv
  rtl/core/frontend/bpu/tb/tb_ittage_table.sv
  rtl/core/frontend/bpu/Makefile (sim_ittage_table added)
  prompts/BP-033-FIX-1.md

---

### Methodology updates confirmed this session

  1. Pre-computed expected values in prompt.
     Test Vector Tables with expected values derived
     from spec must be included in all testbench prompts.
     Claude Code must not derive expected values from
     the RTL it writes.

  2. Split implementation and testbench tasks.
     Combined implementation+testbench in one prompt
     consumed 83% context. Future tasks should split
     RTL implementation and testbench into separate
     prompts to reduce context pressure and reduce
     correlated-bug risk.

  3. Prompt scope confirmed in ANTIPATTERNS.md.
     These items should be added there.

---

### Follow-on actions noted (not yet done)

  - Research verible-verilog-format for SV formatting.
    artistic-style supports Verilog but has trouble
    with SystemVerilog constructs.

  - Add the two methodology items above to
    ANTIPATTERNS.md.

---

## Open Items Carried Forward

None.

---

## Next Session (040)

ittage_table.sv is complete. Next module is
ittage_cntrl.sv.

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-040.md (this file)
  CLAUDE.md
  ittage_cntrl planning documents

After loading, Claude.ai and Jeff will review the
ittage_cntrl planning context and decide how to
decompose the implementation into appropriately
scoped prompts before writing any task files.

### Files likely needed for ittage_cntrl

  ittage_interfaces.md
  ittage_cntrl_decisions.md
  ittage_cntrl_alloc_rules.md
  ittage_cntrl_ctr_update_rules.md
  ittage_cntrl_uaon_update_rules.md
  ittage_cntrl_use_update_rules.md
  ittage_table_interfaces.md
  bp_defines_pkg.sv
  bp_structs_pkg.sv
  rtl/core/frontend/bpu/rtl/ittage_table.sv

