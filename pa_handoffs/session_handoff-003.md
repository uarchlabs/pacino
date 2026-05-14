# Session Handoff 003

Written by Claude.ai at end of session-003.
Date: 2026-03-27

This is the delta from session-003. Read PROJECT_STATE.md first,
then this file, then CLAUDE.md to restore full context.

---

## What This Session Covered

Session-003 was the BP cluster architecture extraction and
interface-first planning session. It produced:

1. Full BP cluster micro-architecture extraction from Jeff
2. bp_cluster.md -- locked planning document
3. BP-001 experiment prompt -- bp_pkg.sv definition
4. BP-001 execution and clean pass (15 checks, zero warnings)
5. CLAUDE.md and prompt discipline improvements
6. Graduation of BP-001 decisions into bp_cluster.md and CLAUDE.md

---

## Decisions Made This Session

### BP cluster predictor hierarchy (locked)
Seven predictors: uBTB, Loop, FTB, TAGE, SC, ITTAGE, RAS.
Xiangshan Kunminghu-inspired. Loop predictor is Jeff's addition --
not present in Xiangshan. All parameters locked in bp_cluster.md.

### Pipeline staging (locked)
  s0: PC input, index calculations, SRAM address dispatch
  s1: uBTB + Loop fire, fetch begins speculatively
  s2: FTB + TAGE + RAS fire, s2_redirect if != s1
  s3: SC + ITTAGE final, s3_redirect if SC overrides TAGE

### Override chain (locked)
  SC > TAGE > FTB > uBTB (conditional branch direction/target)
  Loop overrides uBTB at s1 when trusted (override control decides)
  ITTAGE and RAS are type-gated, outside the conditional chain

### Dual prediction (locked)
Xiangshan model. Runtime-selectable. NUM_PRED_SLOTS is an
elaboration-time parameter (1 or 2), not a runtime signal.
One update channel per active prediction slot.

### Update policy (locked)
Post-execute, not retire. One or two channels per dual_pred_en.
Each channel carries both conditional and indirect resolution.
RAS updated speculatively at s2, separately from main channels.
Commit stack updated at retire (Xiangshan model preserved).

### RAS micro-architecture (locked)
Xiangshan dual-stack design exactly:
- Speculative stack: 48 entries, persistent linked circular array
  Entry: 41b ret_addr, 6b NOS pointer, recursion counter (TBD width)
  Pointers: TOSR, TOSW, BOS
  Recovery: restore (TOSR, TOSW, BOS) snapshot from FTQ entry
- Commit stack: conventional circular, entry count TBD
- bp_ras_snapshot_t bundled as sub-struct in bp_ftq_entry_t
  Access pattern: entry.ras.tosr / .tosw / .bos

### FTQ split (locked)
Two parallel SRAMs indexed by same FTQ slot:
- bp_ftq_entry_t: fast path, read every cycle
- bp_ftq_meta_t: slow path, read on update only
FTQ depth: 64 entries, FTQ_IDX_BITS = 6.
BPC owns the FTQ.

### Key parameters (all locked)
  VA_WIDTH          = 40
  GHR_WIDTH         = 256
  FTQ_DEPTH         = 64
  FTQ_IDX_BITS      = 6
  FETCH_BLOCK_BYTES = 64
  FTQ_CONF_BITS     = 4  (confidence field, purpose reserved)

### TAGE entry layout (locked)
  T0 (base): 2b CTR only. No tag, valid, or useful fields.
  T1-T4 (tagged): 1b valid, 8b tag, 3b CTR, 2b useful.

### G11 resolved -- bp_pkg.sv localparams (locked)
  TAGE_MAX_AWIDTH    = $clog2(2048) = 11
  TAGE_TBL_SEL_WIDTH = $clog2(5)   = 3
  TAGE_MAX_DWIDTH    = TAGE_TAG_BITS = 8
  TAGE_CTR_BITS      = 3
  SC_NUM_MAIN_TBLS   = 4
  SC_NUM_ALL_TBLS    = 5

### SC index array split (locked, BP-001 structural decision)
ST0-ST3 and ST4 (IMLI) have different index widths. Two fields:
  sc_upd_idx  [SC_NUM_MAIN_TBLS-1:0][SC_TBL_INDEX_BITS-1:0]
  sc_imli_idx [SC_IMLI_INDEX_BITS-1:0]
sc_upd_ctr is uniform 24b; ST4 uses lower 6b only.

### BPU is decoupled frontend (locked)
BPU self-generates next PC. It is not fetch-driven. BPU pushes
prediction results into FTQ. Fetch consumes from FTQ.
There is no bp_pred_req_t from fetch -- BPU owns the PC.

### History module (locked)
GHR and folded histories live in a dedicated history module inside
the BP cluster. Checkpoint support required for redirect recovery.
History management is inside BPC, not at rename/dispatch.

### Prompt discipline improvements (settled)
Binding Previous Decisions in experiment prompts should contain
only what is NOT in bp_cluster.md or is genuinely easy to
guess wrong. Everything else belongs in the planning document.
Constraints section contains only experiment-specific items --
global style rules belong in CLAUDE.md only.

### CLAUDE.md updates applied this session
- -Wno-DECLFILENAME added as a standing project convention.
  Suppress in all sim targets. Not a defect -- caused by the
  project naming convention (module tb in tb_<dut>.sv).
- Session discipline rules added: Context Loaded manifest
  isolation, Results Capture as required deliverable without
  being asked.
- Style rules consolidated -- tab/indent/linewidth rules now
  appear exactly once.
- ASCII comment rule corrected (was self-contradictory).
- Current Scope section now points to experiment prompt rather
  than containing a stale example.

---

## BP-001 Results Summary

PASS. Clean first run after one Verilator flag addition.
  - frontend/branch_predictor/rtl/bp_pkg.sv     397 lines
  - frontend/branch_predictor/tb/tb_bp_pkg.sv   207 lines
  - frontend/branch_predictor/Makefile            33 lines
  - 15 self-checking combinational tests, all pass
  - Zero Verilator errors, zero warnings

---

## Files Changed This Session

  planning/arch/bp_cluster.md   -- created and locked
  prompts/frontend/branch_predictor/BP-001.md  -- created, PASS
  CLAUDE.md                      -- updated (see above)
  frontend/branch_predictor/rtl/bp_pkg.sv      -- created (Claude Code)
  frontend/branch_predictor/tb/tb_bp_pkg.sv    -- created (Claude Code)
  frontend/branch_predictor/Makefile           -- created (Claude Code)

---

## Open Items Carried Forward

| ID  | Item                               | Status                  |
|-----|------------------------------------|-------------------------|
| G5  | RAS commit stack entry count       | TBD at implementation   |
| G6  | RAS recursion counter width        | TBD at implementation   |
| G7  | SC threshold value                 | TBD, fixed at impl      |
| G8  | Dual pred bundle split point       | TBD at fetch interface  |
| G9  | Update channel arbitration         | TBD                     |
| G10 | TAGE/ITTAGE meta overload scheme   | TBD at implementation   |
| G14 | Confidence counter purpose         | Reserved, 4b            |

---

## Next Session

BP-002: first implementation experiment. Scope History Module

  GHR + PHR + folded history management with checkpoint support.
  No SRAM, pure registers. Required by all TAGE-family predictors
  before they can be implemented. Unblocks everything downstream.

Jeff decides scope of BP-002.

