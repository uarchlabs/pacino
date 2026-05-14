# Session Handoff 008

Written by Claude.ai at end of session-007.
Date: 2026-03-30

This is the delta from the PROJECT_STATE restructure,
bp_pkg.sv split, and BP-004b abandonment. Read
PROJECT_STATE.md first, then PROJECT_STATUS.md, then
this file, then CLAUDE.md to restore full context.

---

## What This Session Covered

PROJECT_STATE.md restructured into three files:
  PROJECT_CORE.md   -- stable methodology reference
  PROJECT_STATE.md  -- thin index, pasted every session
  PROJECT_STATUS.md -- current tables, pasted every session

PROJECT_CORE.md is pasted only when methodology is under
discussion. Routine sessions paste the other three plus
the latest handoff.

bp_pkg.sv split manually into:
  bp_defines_pkg.sv -- package bp_defines_pkg, parameters
  bp_structs_pkg.sv -- package bp_structs_pkg, structs,
                       enums, typedefs
bp_pkg.sv deleted. All dependent files updated manually.
tb_bp_pkg.sv updated to import both new packages.
Makefile updated to reference both new files.

BP-004b abandoned. Token limit exhausted before any
output was generated. Root cause: prompt scope too large
for a single session.

planning/arch/decode.md noted as absent. Decoder
architectural decisions currently live in PROJECT_STATE.md
only. No action taken this session.

---

## Decisions Made This Session

### PROJECT_STATE restructure (Option C)
Three-file split as described above. Settled.

### bp_pkg.sv split naming convention
File names match package names exactly, consistent with
existing project pattern (bp_pkg.sv / package bp_pkg).
  bp_defines_pkg.sv -- package bp_defines_pkg
  bp_structs_pkg.sv -- package bp_structs_pkg
Import order mandatory in every file:
  import bp_defines_pkg::*;
  import bp_structs_pkg::*;
CLAUDE.md updated with import order rule.

### BP-004b split into BP-004c/d/e
BP-004c: loop_pred.sv RTL only, no testbench.
BP-004d: tb_loop_pred.sv TC1-TC7, prediction path.
         Plus Makefile sim_loop target.
BP-004e: tb_loop_pred.sv TC8-TC13 appended, update path.

### PROJECT_STATUS is track-specific
BP cluster sessions paste BP-only content. Decoder rows
removed from BP session PROJECT_STATUS. If decoder
sessions resume, a decoder-focused PROJECT_STATUS is
used instead.

---

## Files Modified This Session (manual edits)

  PROJECT_CORE.md          -- created
  PROJECT_STATE.md         -- replaced monolith
  PROJECT_STATUS.md        -- created
  CLAUDE.md                -- import order rule added
  bp_defines_pkg.sv        -- created from bp_pkg.sv
  bp_structs_pkg.sv        -- created from bp_pkg.sv
  bp_pkg.sv                -- deleted
  tb/tb_bp_pkg.sv          -- imports updated
  rtl/bp_history.sv        -- imports updated
  rtl/ubtb.sv              -- imports updated
  Makefile                 -- source list updated

---

## Next Session

1. Run BP-004c: loop_pred.sv RTL only.
   Context: bp_defines_pkg.sv, bp_structs_pkg.sv,
   loop_pred_interfaces.md, bp_cluster.md, CLAUDE.md.
2. Report results to Claude.ai.
3. If PASS: run BP-004d.
