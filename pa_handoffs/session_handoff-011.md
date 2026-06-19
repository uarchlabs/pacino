<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 011
Written by Claude.ai at end of session-010 (claude.ai session).
Date: 2026-03-31
This is the delta from BP-004f completion and tooling/workflow
observations leading to the decision to advance to TAGE next.
Read PROJECT_STATE.md first, then PROJECT_STATUS.md,
then this file, then CLAUDE.md to restore full context.
---
## What This Session Covered
BP-004f completed. TC8-TC13 appended to tb_loop_pred.sv.
All 13 TCs pass under Verilator 5.020, zero warnings, exit 0.
Makefile unchanged. Results Capture written to BP-004f.md.

Claude Code generation timeout hit during BP-004f execution.
Task completed after approximately 90 minutes total. Output
was 378 lines of new testbench code (lines 357-735).
This is the known data point for where the generation limit
sits. Identified as a potential project-blocking issue for
larger modules.

Decision made to advance to TAGE next, skipping FTB, to
evaluate whether the Claude Code generation flow is feasible
for more complex modules before investing further in tooling
fixes.
---
## Decisions Made This Session
### CLAUDE.md: Results Capture write region rule added
Claude Code must write only within <!-- RESULTS:START --> and
<!-- RESULTS:END --> markers. No content outside these markers
may be modified.

### CLAUDE.md: ASCII only in Results Capture
Results Capture content must be ASCII only. No Unicode, no
special characters, no checkmark symbols, no non-ASCII arrows,
no emoji.

### CLAUDE.md: Redundant context load instruction removed
Removed the instruction telling Claude Code to read the
Context Loaded manifest. The @ reference syntax in the
experiment prompt handles file loading directly. The
instruction was redundant and caused Claude Code to narrate
a false validation step.

### Generation timeout is a known project risk
378 lines of new testbench output took ~90 minutes and hit
the generation limit. Single complex test cases may exceed
the limit on their own. No tooling fix exists for generation
timeout -- it is governed by the Anthropic API and is not
configurable. A Python script driving the API directly with
streaming has been noted as a potential future replacement
for Claude Code in the generation role. To be revisited
after TAGE feasibility is assessed.

### TAGE advanced in priority
Decision to move to TAGE next, ahead of FTB, to stress-test
the flow on a complex module. FTB deferred.
---
## Deferred Work Carried Forward from BP-004f
- Cursor (curs/curs_v) tracking tests. All TC8-TC13 bundles
  leave curs/curs_v at 0. Cursor behavior under cond1 is
  not yet covered.
- Age decay / replacement policy under normal prediction
  traffic. Age decrements not exercised in any TC.
- LP_CONF_LEVEL saturation clamp: no TC starts at conf=3
  to verify clamp behavior.
---
## Files Modified This Session
  frontend/branch_predictor/tb/tb_loop_pred.sv -- TC8-TC13 appended
  prompts/frontend/branch_predictor/BP-004f.md -- results written
  CLAUDE.md                                    -- three updates
  PROJECT_STATUS.md                            -- updated by user
  PROJECT_STATE.md                             -- updated by user
---
## Next Session
1. Begin TAGE implementation.
   Assess feasibility of Claude Code generation flow for a
   module of this complexity before committing to full
   experiment file authoring.
2. Carry forward loop_pred deferred work (cursor tracking,
   age decay, conf saturation clamp) -- address before
   bp_cluster integration, not necessarily next session.
3. Revisit Python API streaming as Claude Code replacement
   if TAGE generation hits the same timeout problem.
---
## PROJECT_STATE.md Updates Needed
None. User has already updated.

