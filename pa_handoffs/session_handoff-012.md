# Session Handoff 012
Written by Claude.ai at end of session-011 (claude.ai session).
Date: 2026-03-31
This is the delta from BP-005 completion and the TAGE
interface specification work.
Read PROJECT_STATE.md first, then PROJECT_STATUS.md,
then this file, then CLAUDE.md to restore full context.
---
## What This Session Covered
BP-005 complete. Three new structs added to bp_structs_pkg.sv
(tage_pred_inp_t, tage_pred_meta_t, tage_upd_inp_t). Five
per-table TAGE IDX_BITS localparams added to bp_defines_pkg.sv.
TAGE_MAX_AWIDTH corrected to nested ternary max across T0-T4.
make lint and make sim both exit zero, zero warnings, 16 checks
passed.

tage_interfaces.md drafted and finalized. Port naming convention
established and applied. Struct definitions finalized.

A port naming convention was established this session and will
need to be retrofitted to loop_pred and ubtb in a future cleanup.
---
## Decisions Made This Session

### Port naming convention established
Signal names follow the pattern:
  `<signal>_<slot>_<pipestage>`
- slot      : 0 or 1. Indicates prediction slot.
- pipestage : p0, p1, p2 for prediction path.
              u0, u1 for update path.
              px for flush signals (not yet defined).
Signals shared across slots carry no slot index.
clk and rstn carry no pipe stage suffix.
This convention is now the project standard. Loop_pred and
ubtb ports predate this convention and require retrofit.

### TAGE pipeline stage naming
The s-stage notation (s0, s1, s2) from bp_cluster.md maps
to p-stage notation (p0, p1, p2) in RTL port names.
p0 = index hash (combinational).
p1 = SRAM read, tag match, hit processing.
p2 = flopped output, final prediction valid.

### Update path naming
Update inputs are _u0. Update completes in one cycle, ready
signal is _u1. This applies to TAGE and is the expected
pattern for other predictors.

### tage_pred_rdy semantics
tage_pred_rdy_0_p2 = 1 validates the prediction output.
It is not a backpressure signal at present.

### tage_pred_meta_t is a rename of bp_tage_meta_t
bp_tage_meta_t is retained in bp_structs_pkg.sv during
transition. Migration to tage_pred_meta_t is a deferred
cleanup task (TI7).

### tage_upd_inp_t embeds tage_pred_meta_t as sub-struct
This is an explicit exception to the flat struct rule.
The update path carries the full prediction metadata as
a unit.

### fld_hist_p0 is shared across both prediction slots
Simultaneous prediction requests use the same history
state. No per-slot folded history input required under
current uarch plans.

### tb_bp_packages.sv path correction
The Context Loaded in BP-005 referenced tb_bp_packages.sv
which does not exist. The correct file is tb/tb_bp_pkg.sv.
All future experiment files referencing the BP packages
testbench must use tb/tb_bp_pkg.sv.

---
## Cleanup Items Accumulated This Session

| ID      | Item                                | File                        |
|---------|-------------------------------------|-----------------------------|
| CLI-001 | lp_hit missing from field list      | loop_pred_interfaces.md     |
| CLI-002 | idx/tag vs lp_set/lp_tag naming     | loop_pred_interfaces.md     |
| CLI-004 | lp_set vs idx in bp_loop_meta_t     | bp_structs_pkg.sv           |
| CLI-008 | Mixed prefix in lp_pred_t           | bp_structs_pkg.sv           |
| CLI-011 | Port naming convention not applied  | loop_pred.sv                |
| CLI-012 | Port naming convention not applied  | ubtb.sv                     |
| TI7     | bp_tage_meta_t migration to         | bp_structs_pkg.sv           |
|         | tage_pred_meta_t                    |                             |

---
## Files Modified This Session
  frontend/branch_predictor/rtl/bp_defines_pkg.sv -- BP-005
  frontend/branch_predictor/rtl/bp_structs_pkg.sv -- BP-005
  planning/interfaces/tage_interfaces.md          -- created
  prompts/frontend/branch_predictor/BP-005.md     -- created
  PROJECT_STATUS.md                               -- update needed
  PROJECT_STATE.md                                -- update needed

---
## Next Session
1. Begin TAGE RTL implementation (BP-006).
   Assess Claude Code generation feasibility for a module
   of this complexity before committing to full experiment
   file authoring. Generation timeout risk applies.
2. Carry forward loop_pred deferred work (cursor tracking,
   age decay, conf saturation clamp) -- address before
   bp_cluster integration, not necessarily next session.
3. Cleanup tasks CLI-001 through CLI-012 and TI7 --
   address as a dedicated cleanup session before
   bp_cluster integration.
4. Revisit Python API streaming as Claude Code replacement
   if BP-006 generation hits timeout.

---
## PROJECT_STATUS.md Updates Needed
- Add tage_interfaces.md row to Module Status table.
- Add BP-005 to completed Open Items.
- Add CLI-001, CLI-002, CLI-004, CLI-008, CLI-011,
  CLI-012, TI7 to Technical Debt table.

## PROJECT_STATE.md Updates Needed
- Add port naming convention decision to Architectural
  Decisions section.
- Add tb_bp_pkg.sv path correction note.
