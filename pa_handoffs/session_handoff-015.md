<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 015
Written by Claude.ai at end of session-015 (claude.ai session).
Date: 2026-04-02
This session attempted to author BP-006 through BP-009 prompt
files for the full TAGE predictor decomposition.
Read PROJECT_STATE.md first, then PROJECT_STATUS.md,
then this file, then CLAUDE.md to restore full context.
---
## What This Session Covered
Session context restored from session_handoff-014. bp_cluster.md
loaded as additional context. Full component signatures loaded:
bw_ram.sv, sat_alu.sv, dual_lm1.sv, sram_init.sv.

Attempted to decompose TAGE into four prompts:
  BP-006: tage_hash.sv  -- combinational index/tag hash
  BP-007: tage_table.sv -- parameterized table storage wrapper
  BP-008: tage_cntrl.sv -- all control logic
  BP-009: tage.sv       -- top-level integration

BP-006 prompt was completed and is correct.
BP-007 through BP-009 were drafted but the decomposition was
found to be architecturally unsound during review. Session
abandoned before BP-007 was finalized.
---
## Decisions Made This Session

### TAGE decomposition decisions (settled)
- tage_hash.sv is valid as a standalone combinational module.
  Inputs: pc per slot, fld_hist_p0 (shared).
  Outputs: hashed index and tag per table per slot.
  T0 index is pc[12:2] direct (no XOR).
  T1-T4 index: pc[12:2] XOR idx_fh (zero-extended to 11b).
  T1-T4 tag: (pc[12:2] XOR tag_fh1 XOR tag_fh2)[7:0].
  Slot 1 generate-gated on NUM_PRED_SLOTS==2.
  BP-006 prompt is complete and correct.

### TAGE decomposition problems found (not resolved)
The tage_table / tage_cntrl boundary is broken for these
reasons:

1. Parameterized port count is not supported in SystemVerilog.
   tage_cntrl cannot have one port per table when the number
   of tables is a parameter (TAGE_NUM_TABLES).

2. Packed arrays as a workaround require uniform width across
   all tables. T0 (DATA_WIDTH=2) and T1-T4 (DATA_WIDTH=14)
   are not uniform. This complicates the array approach.

3. The update path must complete in one cycle (u0->u1 per
   tage_interfaces.md). A one-cycle update across a
   parameterized number of tables with variable write targets
   (provider CTR, useful decrements, allocation) is not
   trivially decomposed across a tage_cntrl/tage_table
   boundary.

4. Tag comparison: tage_table needs the hashed tag as an
   input to perform the comparison internally, but this
   was not correctly reflected in the initial BP-007 draft
   which exposed raw rd_data words instead of hit/ctr/useful.

5. The session did not return to bp_cluster.md and
   tage_interfaces.md to ground the update path design
   before attempting to write the prompts. This was the
   root cause of the decomposition failure.

### What needs to be resolved before BP-007
- Re-read tage_interfaces.md update behavior section and
  bp_cluster.md update policy section carefully.
- Determine correct module boundary for tag compare:
  inside tage_table or in tage.sv after raw read.
- Determine how update writes to multiple tables in one
  cycle are handled across a parameterized generate block.
- Determine whether tage_cntrl remains a separate module
  or whether its logic folds into tage.sv.
- A more granular prompting approach is required. Do not
  attempt to write all N prompts in one session without
  resolving the above.

---
## Files Modified This Session
  prompts/bp/BP-006.md  -- created, complete, correct
  prompts/bp/BP-007.md  -- created, incomplete, do not use
  prompts/bp/BP-008.md  -- created, incomplete, do not use
  prompts/bp/BP-009.md  -- created, incomplete, do not use

BP-007 through BP-009 should be deleted or marked abandoned
before the next session begins TAGE work.

---
## Next Session
1. Fix BP-007 through BP-009 delimiter errors and content
   before use, or delete and restart with a more granular
   approach.
2. Re-read tage_interfaces.md and bp_cluster.md update
   sections carefully before designing the tage_table and
   tage_cntrl module boundaries.
3. Resolve the parameterized table count vs port list
   problem before writing any further prompts.
4. Consider whether tage_cntrl should be eliminated and
   its logic absorbed into tage.sv given the port count
   constraints.
5. Pending cleanup session (CLI-001, CLI-002, CLI-004,
   CLI-008, CLI-011, CLI-012, TI7) still required before
   bp_cluster integration -- deferred again this session.

---
## PROJECT_STATUS.md Updates Needed
- Add BP-006 row to prompt/experiment tracking if such a
  section exists, marked complete.
- Add note that BP-007 through BP-009 are abandoned/draft
  and require rework.
- No module status rows change this session. No RTL was
  produced.

## PROJECT_STATE.md Updates Needed
- No changes required this session.
- TAGE decomposition decisions above should be added to
  the BP cluster track section if the next session author
  finds them useful. Leave to next session discretion.

