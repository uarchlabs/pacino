<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 010
Written by Claude.ai at end of session-009 (claude.ai session).
Date: 2026-03-31
This is the delta from BP-004e completion and the
validate_and_extract.py tooling addition.
Read PROJECT_STATE.md first, then PROJECT_STATUS.md,
then this file, then CLAUDE.md to restore full context.
---
## What This Session Covered
BP-004e completed by Claude Code. tb_loop_pred.sv
delivered, TC1-TC7 all PASS. Sim and lint both exit
zero with zero warnings.
BP-004e first attempt failed due to context window
exhaustion (5-hour allotment). Root cause: the
run-prompt SKILL was loading the full experiment file
including all template scaffolding into Claude Code
context.
Fix: validate_and_extract.py script added to project
tooling. Script validates full experiment file format
then extracts only the PROMPT section to a known path.
Claude Code reads only the extracted prompt, not the
full file.
Claude Code slash command registration issue resolved.
Root cause was missing YAML frontmatter name field in
.claude/commands/run-prompt.md. Migrated to
.claude/skills/run-prompt/SKILL.md with correct
frontmatter. Command now registers and prompts for
argument correctly.
---
## Decisions Made This Session
### validate_and_extract.py adopted as standard tooling
Script lives in project tools directory. Validates all
8 block markers in order, all HEADER fields, all PROMPT
subsections, all RESULTS subsections, all DISCUSSION
subsections. Exits non-zero with specific error messages
on any failure. On success extracts PROMPT section to
.claude/tmp/current-prompt.md.
Workflow going forward:
  python3 validate_and_extract.py <experiment_file>
  Then in Claude Code:
  Read .claude/tmp/current-prompt.md and execute it
### run-prompt migrated to skills
.claude/commands/run-prompt.md replaced by
.claude/skills/run-prompt/SKILL.md with YAML
frontmatter. validate_and_extract.py now handles
validation and extraction outside Claude Code context.
### -Wno-VARHIDDEN scope confirmed
Added to both lint_loop_pred and sim_loop_pred targets.
loop_pred module parameters shadow bp_defines_pkg
parameters (LP_TBL_ENTRIES, LP_TBL_WAYS, LP_TAG_BITS,
LP_ITR_BITS, LP_CNF_BITS, LP_AGE_BITS, LP_N_SETS,
LP_IDX_BITS, LP_CONF_LEVEL, NUM_PRED_SLOTS).
Consistent with CLAUDE.md rule.
---
## Key Testbench Notes for BP-004f
- tb_loop_pred.sv mirrors idx_of() and tag_of() hash
  functions from loop_pred.sv to compute expected
  indices and tags without reading RTL internals.
- Assumption in TC2/TC4/TC5: victim=2'b00 because all
  ways invalid after reset, way 0 selected by priority
  scan. TC11 (BP-004f) tests victim selection under
  full-set conditions -- verify this assumption does
  not conflict before writing TC11.
- wrong-exit step (curr=1, past=0) used before
  confidence-build sequence in TC5 to establish
  past_itr=1 in memory. TC6 and TC7 depend on this.
- curs/curs_v fields left as zero in all TC1-TC7
  update bundles. Cursor tracking is TC8+ territory.
---
## Files Modified This Session
  frontend/branch_predictor/tb/tb_loop_pred.sv  -- created
  frontend/branch_predictor/Makefile            -- updated
  prompts/frontend/branch_predictor/BP-004e.md  -- results written
  tools/validate_and_extract.py                 -- created
  .claude/skills/run-prompt/SKILL.md            -- created
---
## Next Session
1. Run BP-004f: tb_loop_pred TC8-TC13 appended.
   Context: frontend/branch_predictor/rtl/bp_defines_pkg.sv
            frontend/branch_predictor/rtl/bp_structs_pkg.sv
            frontend/branch_predictor/rtl/loop_pred.sv
            frontend/branch_predictor/tb/tb_loop_pred.sv
            CLAUDE.md
2. Before writing TC11, review tb_loop_pred.sv
   assumption that victim=way 0 after reset. Confirm
   it does not conflict with TC11 full-set victim
   selection test.
3. Report results to Claude.ai.
---
## PROJECT_STATE.md Updates Needed
One change only:
  Last updated: 2026-03-30 (session-008)
Change to:
  Last updated: 2026-03-31 (session-010)

