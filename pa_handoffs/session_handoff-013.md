# Session Handoff 013
Written by Claude.ai at end of session-012 (claude.ai session).
Date: 2026-04-02
This is the delta from COMP-001 completion and tooling format
changes.
Read PROJECT_STATE.md first, then PROJECT_STATUS.md,
then this file, then CLAUDE.md to restore full context.
---
## What This Session Covered
COMP-001 complete. Three parameterized library primitives created:
bw_ram.sv (rewritten for 1-cycle write latency), sat_alu.sv
(pre-existing, unchanged), dual_lm1.sv (pre-existing, unchanged).
Combined extensible testbench tb_components.sv created with 21 TCs.
21/21 passing, lint and sim exit zero, zero warnings.

Prompt file format changed from <!-- HTML comment --> markers to
:: MARKER :: style. validate_and_extract.py updated accordingly.
@ prefix check added to validate_and_extract.py for Context Loaded
entries. Context minimization discipline established -- only load
files Claude Code actually needs for the task.

New top-level directory components/ created at repo root alongside
frontend/, backend/, midcore/.

---
## Decisions Made This Session

### Prompt file block marker format change
Block markers changed from HTML comment style to :: MARKER :: style:
  :: HEADER:START ::  / :: HEADER:END ::
  :: DISCUSSION:START :: / :: DISCUSSION:END ::
  :: PROMPT:START :: / :: PROMPT:END ::
  :: RESULTS:START :: / :: RESULTS:END ::
Old <!-- --> markers are retired. All future prompt files use
:: MARKER :: style.

### @ prefix required for Context Loaded entries
Every file listed under ## Context Loaded in the prompt must use
the @ prefix (e.g. @CLAUDE.md). validate_and_extract.py now
enforces this and fails with a clear error if any entry is missing
the prefix.

### Context minimization discipline
Only load context files that Claude Code actually needs for the
specific task. Standalone library primitives with no package
dependencies do not need PROJECT_STATE, PROJECT_STATUS,
session_handoff, or CLAUDE.md. Unnecessary context wastes tokens
and context window.

### Verilator 5.020 --timing flag
Any testbench using @(posedge clk) or #N delays requires --timing
in VER_FLAGS. This is a Verilator 5.020 requirement for
coroutine-based timing simulation. Apply to all future testbench
Makefiles in this project.

### BLKSEQ warning suppression
The clock generator (always #5 clk = ~clk) triggers a BLKSEQ
warning in Verilator. Suppress with a local lint_off/lint_on
pragma pair rather than a global flag.

### bw_ram 1-cycle write latency
The original bw_ram.sv had a 2-cycle write pipeline (pre-flopped
inputs). Correct behavior: inputs presented combinationally,
sampled directly in a single always_ff on the rising edge.
One clock edge, one cycle write latency. This is now the settled
spec and implementation.

### components/ directory structure
New top-level directory at repo root:
  components/rtl/   -- library RTL primitives
  components/tb/    -- combined extensible testbench

tb_components.sv is structured as named begin-end blocks
(tb_bw_ram, tb_sat_alu, tb_dual_lm1). To add a new component:
add a DUT instance, counter pair, helper tasks, and a named
begin block without restructuring existing blocks.

---
## Files Modified This Session
  components/rtl/bw_ram.sv         -- rewritten, 1-cycle write
  components/tb/tb_components.sv   -- created, 21 TCs
  components/tb/Makefile           -- created
  prompts/components/COMP-001.md   -- created, complete
  tools/validate_and_extract.py    -- :: marker style, @ check

---
## Next Session
1. Begin TAGE RTL implementation (BP-006).
   Assess Claude Code generation feasibility before committing
   to full experiment file authoring. Generation timeout risk
   applies for a module of this complexity.
2. Cleanup session (CLI-001, CLI-002, CLI-004, CLI-008,
   CLI-011, CLI-012, TI7) before bp_cluster integration.
3. Revisit Python API streaming as Claude Code replacement
   if BP-006 hits timeout.

---
## PROJECT_STATUS.md Updates Needed

These have been manually updated
- Add bw_ram, sat_alu, dual_lm1, tb_components rows to
  Module Status table. Status: Complete. Tests: tb_components.
  Notes: COMP-001, 21/21 passing.
- Mark COMP-001 complete in Open Items.
- Add Verilator --timing flag note to Technical Debt or Notes
  if a debt item is warranted.

## PROJECT_STATE.md Updates Needed

These have been manually updated
- Add components/ directory to repo structure description.
- Add context minimization discipline to methodology notes.
- Add :: MARKER :: format and @ prefix convention to tooling
  notes.
- Add Verilator --timing requirement note.

