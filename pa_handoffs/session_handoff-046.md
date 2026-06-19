<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 046
Written by Claude.ai at end of session-045.
Date: 2026-06-04

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Session Summary

Session-045 was a PA session focused on tooling
infrastructure, planning document corrections, assert
integration, and preparation of IA task prompts BP-042
through BP-045. No RTL was written. Several planning
documents were substantially corrected. The assert
infrastructure for ITTAGE was established. A significant
number of PA errors occurred during the context capture
investigation; these are recorded below.

---

## What This Session Accomplished

### TOOLS Step 1 -- Session browser tooling (complete)

Four files updated or created:

TASK_TEMPLATE.md:
  - ## Files Modified section added inside Results Capture.
  - Mode: [ ] automated [ ] manual field added to header.
  - PA session field added to header.
  - Ctx % placeholder changed to <cntx>.
  - Model placeholder changed to <model> <effort>.

gen_sessions.py:
  - MODE_OPTS = ["automated", "manual"] added.
  - Mode checkbox parsing added. Stored as modes list.
  - W017: warn if Mode absent or unchecked.
  - parse_files_modified() added.
  - files_modified list in session JSON.
  - PA session check added (fail not warn).

sessions.html:
  - Manual indicator on card and detail header.
  - Collapsible overview panel above // discussion.
  - // files modified section at bottom of detail.
  - Auto-select last session on load.

backfill_prompts.py (new):
  - Inserts Mode: and ## Files Modified into existing
    prompt files that lack them.
  - Dry-run mode supported.
  - Warn but not fail when fields absent.

validate_and_extract.py:
  - PA session check added. Fails if absent or NNN.

### TAGE USE manual tests (complete)

Jeff wrote and ran tage_use_test covering all 6 rows
of tage_cntrl_use_update_rules.md Table 7. All pass.

Bug found and fixed: pred_meta index fields
(tage_prm_idx, tage_alt_idx) were not set in
tage_use_test after pred_meta='0 clear. Same root
cause as the tage_ctr_test bug found earlier. Fix:
add the two idx assignments after the clear block.

### tage_cntrl_use_update_rules.md (complete)

Corrections applied:
  - DIFF redefined: tage_prm_tkn != tage_alt_tkn.
    Previous definition (pred_tkn vs alt_tkn) wrong.
    Made rows 4/5 structurally unreachable.
  - TTM row (row 2) added: no tagged hit, no update.
  - Row notes corrected -- all three were misaligned
    to wrong rows in the previous version.
  - Legend moved into code block.
  - Aging disabled section added.
  - Row priority note added: rows 1 and 2 have no
    priority relationship between them.

### ittage_cntrl_ctr_update_rules.md (complete)

TBD draft table replaced with fully specified 33-row
table. Structure:
  - Row 1: H=0, no update.
  - Rows 2-17: UP=0, alt is provider. 16 rows covering
    all pT/aT/pCMP/aCMP combinations.
  - Rows 18-33: UP=1, primary is provider. 16 rows.
  - Assert rows A1/A2/A3: impossible conditions, cite
    ittage_assert.sv.
MIS column populated from PT!=RT.
pACT/aACT populated from provider and MIS.
pT/pCMP retained in UP=0 rows for test coverage.
aT/aCMP retained in UP=1 rows for test coverage.

### ittage_cntrl_use_update_rules.md (corrected)

  - DIFF corrected: ittage_prm_tgt != ittage_alt_tgt.
    Previous definition (pred_tgt vs alt_tgt) wrong.
  - HIT=0 row added as row 2.
  - Row notes corrected and aligned.
  - Aging disabled section added.
  - Background section added with Seznec deviation note.
  - Legend into code block.

### ittage_assert.sv (new file)

Three assertions, checked on pred and update boundaries:
  1. ittage_hit=1 with pCMP=0 and aCMP=0 impossible.
  2. ittage_using_primary=1 with pCMP=0 impossible.
     Gated on ittage_hit (DEFERRED-3 fix in BP-042b).
  3. ittage_using_primary=0 with hit=1 and aCMP=0
     impossible.
File location: rtl/core/frontend/bpu/tb/ittage_assert.sv
Bound to ittage.sv via bind in tb_ittage.sv.

### BP-042 cluster (complete)

BP-042: Assert integration.
  - tage_assert.sv added to all TAGE sim targets.
  - ittage_assert.sv placed and added to sim_ittage.
  - Bind added to tb_ittage.sv.
  - Two deferred items: path error (fixed interactively)
    and string syntax / CE-06 conflict.

BP-042a: Three fixes.
  - DEFERRED-1: ittage_assert.sv $error() string syntax
    fixed for Verilator 5.048.
  - DEFERRED-2: assert_inhibit port added to
    tage_assert.sv. CE-06 test gated. Bind added to
    tb_tage.sv. tb_tage_manual.sv and
    tage_assert_bind.sv updated.
  - VARS-MK: already correct, no change needed.
  Note: tage_assert.sv had 2 always_ff blocks not 3
  as stated in the prompt. Both gated.

BP-042b: Two fixes.
  - DEFERRED-3: ittage_assert assertion 2 missing
    ittage_hit guard. Added to pred and update paths.
  - D2: tage_assert_bind.sv removed from sim_tage_manual
    target. Double-bind eliminated.
  Results: make all exits 0. sim_ittage 32 pass / 3 fail
  (pre-existing). sim_tage_manual all pass.

### INFRA-007 -- context/model capture test (complete)

Outcome: partial success, partial failure.

Model field: Claude Code correctly populated Model and
effort from runtime knowledge. CLAUDE.md updated to
make this a required step for all task file sessions.

Ctx % field: /context is TUI-only and not accessible
in automated sessions. Ctx% capture is manual only.
## Context Info section removed from template.
PA proposed multiple incorrect solutions before this
conclusion was reached. See PA Behavior Failures below.

### CLAUDE.md updated

New section: ## Model Reporting in Task Files.
Detection: presence of :: HEADER:START :: in context.
Rule: populate Model header field with model name and
effort level before writing Results Capture.
Ctx%: explicitly noted as manual capture only.

### IA task prompts generated

BP-043: TAGE CTR and USE retest (IA session)
BP-044: ITTAGE CTR and USE retest (IA session)
BP-045: ITTAGE manual testbench shell (IA session)

All three prompts await execution. No IA sessions run.

---

## PA Behavior Failures

### Overview parser bug (session-046 Step 1)

PA wrote the overview extraction to look between
:: HEADER:END :: and :: DISCUSSION:START :: but the
template places # Overview of task inside the header
block before :: HEADER:END ::. When Jeff reported
overview: null in the JSON, PA blamed the template
structure and proposed moving the heading rather than
fixing the parser. Jeff rejected the diagnosis. PA
then read the template correctly and fixed the parser.

Lesson: when a parser produces null output, verify the
extraction logic against the actual template before
suggesting changes to input data.

### Context capture failures (INFRA-007)

PA proposed /context as the mechanism for Claude Code
to report context percentage without verifying it was
available in automated mode. PA then built this into
the template and test prompt before the flaw surfaced
in an actual session. Subsequent research attempts were
insufficient and produced further incorrect proposals:
  - Invented CLAUDE_CONTEXT_WINDOW_USAGE env variable
    (does not exist).
  - Proposed ~/.claude/projects/... path command
    (invented).
  - Proposed statusline-to-file approach without
    accounting for the known statusline disappearance
    bug.
Multiple sessions of research were required before the
correct answer was established: /context is TUI-only,
hooks do not expose context data, no programmatic
mechanism exists.

Resolution: Ctx% is manual. Model reporting only.

---

## Open Technical Debt

Carried forward from session_handoff-045 unchanged:
  - TD #38: Covergroup #7099 re-check still pending.
  - TD #43: ITTAGE CTR width reduction 3b->2b.
  - TD #44: ittage_pred_strong definition.
  - TD #45: tage_cntrl/tage_table simplifications.
  - TD #49: arb queue status port renaming.
  - TD #51: CTR/USE/TGT update rule audit for ittage.
  - TD #52: move arb logic into submodule.
  - TD #54: IA test audit against revised CTR table.
  - BP-040 Bug B/C/D: still unverified.

New this session:
  - sim_ittage 3 pre-existing failures (TC-P04 prm_ctr,
    TC-P04 pred_strong, TC-ARB-04 pred_ctr) remain
    open. Likely BP-040 Bug B/C/D.

---

## Next Session (046)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-046.md (this file)
  CLAUDE.md

### Planned work

**Step 1 -- INFRA-007 re-run**

Re-run INFRA-007 with corrected CLAUDE.md to confirm
Claude Code populates Model field correctly from runtime
knowledge. Trivial session -- make lint only.

**Step 2 -- BP-043: TAGE CTR and USE retest**

Audit and repair IA-generated CTR and USE tests in
tb_tage.sv against revised planning documents.
Prompt: prompts/BP-043.md

**Step 3 -- BP-044: ITTAGE CTR and USE retest**

Audit and repair IA-generated CTR and USE tests in
tb_ittage.sv against revised planning documents.
Prompt: prompts/BP-044.md

**Step 4 -- BP-045: ITTAGE manual testbench shell**

Create tb_ittage_manual.sv and tb_ittage_manual_tasks.svh
shell with infrastructure implemented and 33 CTR + 6 USE
stub tasks.
Prompt: prompts/BP-045.md

**Step 5 -- Verify BP-040 Bug B/C/D**

Independently verify Bug B, C, D in ittage_cntrl.sv
against planning documents. Deferred since session-043.

**Step 6 -- README update**

Document tools/bin layout and build instructions.
Low priority.

