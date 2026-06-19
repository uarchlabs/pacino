<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 046
Written by Claude.ai at end of session-045.
Date: 2026-05-31

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Session Summary

Session-044 was a manual testbench development and
debugging session. No Claude Code sessions were run.
Jeff wrote and debugged tage_ctr_test covering all 18
rows of tage_cntrl_ctr_update_rules.md. One RTL bug
was found and fixed. Verilator was upgraded. Assertion
infrastructure was established. The CTR update rule
planning document was significantly revised. Build
infrastructure was improved.

All work is recorded in BP-041.md.

This work generated the first ADR, ADR-001 which
defines the use of tage_using_primary when the
all tagged tables miss. tage_using_primary is
asserted when the provider is the BIM.

The RTL planned work from session_handoff-045
(Steps 1-4) is carried forward unchanged.

---

## What This Session Accomplished

### Mode field added to TASK_TEMPLATE.md (complete)

Jeff applied this change directly. The header
block now contains:

    Task:   [ ] experiment  [ ] implementation  [ ] debug
            [ ] cleanup     [ ] testbench       [ ] verification
    Mode:   [ ] automated   [ ] manual
    Status: [ ] in-progress [ ] complete        [ ] abandoned

### tage_ctr_test (complete)

All 18 rows of tage_cntrl_ctr_update_rules.md covered:
  - Rows 1-17: pass under Verilator 5.048.
  - Row 18: covered by assertion in tage_assert.sv.
    Unreachable condition, no test row needed.

### HAND-FIX-003 (complete)

NOTE: HAND-FIX-003 was later reverted in BP-043a. The fix
was a false fail caused by an error in the planning document 
for T0 CTR updates.

RTL bug found by manual test row 13a.
tage_cntrl.sv ctr_upd_comb u_both_t0 path:
  - u_resolved replaced with !u_mispredict.
  - BIM prediction correctness is the correct
    INC/DEC gate, not branch outcome alone.
  - Citeable: tage_cntrl_ctr_update_rules.md
    rows 13a-d.
  - BUG-001 assigned. Recorded in BP-041.md.

### Verilator upgrade (complete)

Upgraded from 5.020 to 5.048 2026-04-26.
  - inout optimizer bug resolved.
  - All workaround $display calls removed from
    tb_tage_manual_tasks.svh.
  - Rows 1-17 pass cleanly under 5.048.
  - TD #38 partially addressed. Covergroup/
    coverpoint issue #7099 re-check still pending.

### tage_assert.sv (complete)

New assertion module bound to tage.sv via
SystemVerilog bind. Sim-only, not synthesized.
Two assertions implemented:

  Row 18 invariant:
    prm_comp=0 and alt_comp>0 is invalid.
    Fires on both pred and upd boundaries.

  ADR-001 invariant:
    tage_using_primary shall be 1 when
    prm_comp=0 and alt_comp=0.
    Fires on both pred and upd boundaries.

Error message format uses bracket prefix for
grep-based log filtering:
  [TAGE_ASSERT][PRED] or [TAGE_ASSERT][UPD]
  [ADR-001][TAGE_ASSERT][PRED] or [UPD]

tage_assert.sv added to sim_tage_manual target.

### ADR-001 established (complete)

First architectural decision record for the
project. Recorded in tage_cntrl_ctr_update_rules.md
rather than a separate directory. Convention:
ADRs live in the planning document that governs
the decision. Rationale: context minimization.
Claude Code loads the ADR automatically when it
loads the rule doc.

ADR-001: tage_using_primary shall be 1 when
pCMP=aCMP=0. BIM is the sole provider. The
concept of primary vs alternate does not apply.
RTL confirmed: pred_logic default sets
using_prm_p1 to 1'b1. UAON override is gated
on prm_comp != 0, cannot fire in BIM case.
Status: ACTIVE. RTL verified. Assertion
implemented.

### tage_cntrl_ctr_update_rules.md (complete)

Significant revision. Original table contained
X entries for pred_diff, pT, and aT. Expanding
those X entries exposed two structural constraints:

Constraint 1: UP=1 requires PT=pT (tautology).
  When using_primary=1, pred_tkn is by definition
  prm_tkn. Rows violating this are structurally
  impossible. Removed from table, no assertion
  needed.

Constraint 2: pCMP=aCMP=0 requires diff=0.
  When both providers are BIM, prm_tkn and alt_tkn
  are the same signal. diff=1 rows in groups 13a-d
  are unreachable. Removed from table.

Row 13e added: UP=0 when pCMP=aCMP=0 is invalid.
  Handled by ADR-001 assertion. No RTL action.

Net result: ~80 rows reduced to ~30 rows. All
surviving rows are reachable and internally
consistent.

### Build infrastructure (complete)

Var.mk created at RTL tree root:
  VERILATOR=$(RVA_ROOT)/tools/bin/verilator
  SPIKE=$(RVA_ROOT)/tools/bin/spike
  SURFER=$(USER)/.cargo/bin/surfer

$(RVA_ROOT)/tools/bin established as common
install directory for all submodule tools.
All RTL Makefiles include Var.mk.

README update pending: document tools/bin layout
and build instructions for Verilator and Spike.

### BUG and HAND-FIX numbering (complete)

Scheme clarified:
  HAND-FIX-NNN: manual RTL fix applied.
  BUG-NNN: bug found by manual test or assertion.

This session: HAND-FIX-003, BUG-001.
Both recorded in PROJECT_STATUS.md and BP-041.md.

---
### TOOLS task defined (complete)

gen_sessions.py, sessions.html, and
TASK_TEMPLATE.md changes fully specified.
See Step 1 in Planned Work below.

---

## Open Technical Debt

  - TD #38: partially addressed. Verilator 5.048
    inout bug fixed. Covergroup issue #7099 status
    in 5.048 release notes still needs re-check.
  - TD #43: ITTAGE CTR width reduction 3b->2b.
    Still open.
  - TD #44: ittage_pred_strong definition. Still
    open pending TD #43.
  - TD #45: tage_cntrl/tage_table simplifications.
    Still open.
  - TD #49: arb queue status port renaming. Still
    open, deferred to cleanup session before
    bp_cluster.
  - TD #51: CTR/USE/TGT update rule audit for
    ittage. Still open. Independent round-trip
    test set required.
  - TD #52: move arb logic into submodule. Still
    open.
  - TD #53: CLOSED. Root cause was test state
    contamination from rows 13 into rows 14-17.
    pred_meta.tage_prm_ctr and tage_alt_ctr not
    restored at row 14 boundary.
  - TD #54: IA-generated tests in tb_tage.sv need
    audit against revised tage_cntrl_ctr_update_
    rules.md. X-expansion and row reduction may
    have invalidated some existing test cases or
    exposed gaps.
  - BP-040 Bug B/C/D: three bugs in ittage_cntrl.sv
    still require independent verification against
    planning documents before BP-040 is fully
    closed.

---

## Next Session (045)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-045.md (this file)
  CLAUDE.md

### Planned work

**Step 1 -- Update session browser tooling (TOOLS)**

Step one is a PA task, it will not be provided as a
task to the IA. The PA will request information from
Jeff and supply changes as downloadable files.

The task template and session browser need to
support two new fields. The Mode field has already
been added to TASK_TEMPLATE.md (see above).

The following changes are required across three
files: templates/TASK_TEMPLATE.md,
tools/gen_sessions.py, and docs/sessions.html.

TASK_TEMPLATE.md:
  - Add ## Files Modified as a named section
    inside the Results Capture block.
    Instruction to IA: list every file changed
    as a bullet list. One file per line.
    No prose.

gen_sessions.py:
  - Add MODE_OPTS = ["automated", "manual"].
  - Parse Mode: checkboxes from header text.
    Store as modes list in session JSON.
  - Add W017: warn if Mode: is absent or no
    box is checked. Warn but do not fail.
  - Add parse_files_modified() function. Finds
    ## Files Modified inside the results section.
    Parses bullet list lines. Returns list of
    file path strings.
  - Store as files_modified list in session JSON.
    Initialize as [] in session dict.

sessions.html:
  - Card (left column): add visible manual
    indicator when modes contains "manual".
  - Detail header: same indicator near the
    status badge.
  - Overview: convert existing inline
    overview-block to a collapsible // overview
    panel positioned above // discussion.
  - Bottom of detail panel: add // files modified
    section rendering the files_modified list.

Backfill note: Jeff will backfill Mode: and
## Files Modified into all existing prompt files.
Parser must warn but not fail when either field
is absent.

Context needed for Claude Code prompt:
  tools/gen_sessions.py
  docs/sessions.html
  templates/TASK_TEMPLATE.md

**Step 2 -- Continue manual testing for TAGE USE updates**
  The tage manual test bench will be updated to
  test each row of the USEFULE field rules found in
  tage_cntrl_use_update_rules.md. This will be
  a manual task.

**Step 3 -- Verify BP-040 RTL changes**

Independently verify Bug B, Bug C, Bug D in
ittage_cntrl.sv against planning documents.
Deferred since session-043.
Reference documents:
  ittage_cntrl_ctr_update_rules.md
  ittage_cntrl_use_update_rules.md
  ittage_cntrl_decisions.md

**Step 4 -- TD #54 IA test audit**

Audit tb_tage.sv tests against revised
tage_cntrl_ctr_update_rules.md. Identify
test cases now invalid or missing due to
X-expansion and row reduction.
Retrofit or replace as needed.

**Step 5 -- TD #51 ITTAGE update rule audit**

Apply manual testbench methodology to ITTAGE.
New independent round-trip test set for
tb_ittage.sv covering ittage_cntrl_ctr_update_
rules.md and ittage_cntrl_use_update_rules.md
row by row. Three-session split:
  Session A: write tests against planning
    documents only, no RTL in context.
  Session B: diagnostic only, read both,
    no writes, report discrepancies.
  Session C: fix and verify.

**Step 6 -- README update**

Document tools/bin layout and build
instructions for Verilator and Spike.
Low priority, can be deferred if Steps
1-4 consume the session.
