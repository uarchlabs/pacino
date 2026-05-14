# Session Handoff 027
Written by Claude.ai at end of session-026.
Date: 2026-04-09

This session executed BP-019a through BP-021, closing
debts #24 (fully), #36, and #14/TI7. Read
PROJECT_STATUS.md, then this file, then CLAUDE.md to
restore full context.

---

## What This Session Covered

Session context restored from session_handoff-026.

- BP-019a executed: debt #24 fully closed. TAGE_TAG_BITS
  replaced with MAX_TAG_WIDTH in tage_cntrl.sv (2 sites).
  TAGE_TAG_BITS removed from bp_defines_pkg.sv.
  tb_tage_table.sv PINMISSING fixed (idx_hash_p0 and
  tag_hash_p0 declared and connected). lint_tage_hash
  and sim_tage_hash removed from Makefile. 46/46 PASS.
  Pre-existing TC6 defect revealed (debt #36 opened).
  tage_hash.sv and tb_tage_hash.sv deleted manually
  by user after completion.

- BP-020 executed: debt #36 closed. sim_tage_table TC6
  USE field update defect fixed. Root cause: Verilator
  5.020 evaluation-order ambiguity with cascaded assign
  statements in the write-enable path. Fixed by
  consolidating slot write-enable logic into always_comb
  blocks (we_s0, we_s1) for both slots. sim_tage_table:
  12/12 PASS. sim_tage: 46/46 PASS.

- BP-021 executed: debt #14/TI7 closed. bp_tage_meta_t
  removed from bp_structs_pkg.sv. bp_ftq_meta_t.tage
  retyped from bp_tage_meta_t to tage_pred_meta_t.
  Consumer search confirmed no external consumers.
  lint, lint_tage, lint_tage_table: all 0 warnings,
  exit 0.

- Debt #35 (test count validation script) superseded.
  Replaced by a formal coverage planning item: coverage
  matrix, coverage tracking, and RTL code coverage via
  Verilator. Not yet scoped or assigned a task ID.

---

## Decisions Made This Session

### always_comb over cascaded assign (new style rule)

Prefer always_comb blocks over cascaded continuous
assign statements when signals form a dependency chain.
Verilator 5.020 may evaluate assign statements out of
order when a chain exists, producing stale values.
always_comb evaluates statements in textual order.
Added to CLAUDE.md Style Rules section.

### Debt #35 superseded

Ad-hoc test count comparison is insufficient. Formal
functional coverage (coverage matrix + tracking +
Verilator code coverage) is the correct approach.
Debt #35 marked superseded. New coverage planning
item to be scoped before bp_cluster integration.

### Prompt context list

The prompt file itself (e.g. @prompts/BP-NNN.md) need
not be listed in Context Loaded. Claude Code loads it
implicitly per CLAUDE.md Results Capture rules.

---

## Technical Debt Status After This Session

Closed this session:
  #24 -- TAGE_TBL_* scalar parameter cleanup (BP-019a)
  #36 -- sim_tage_table TC6 USE update defect (BP-020)
  #14 -- bp_tage_meta_t migration / TI7 (BP-021)
  #35 -- superseded by coverage planning item

Still open:
  #7  -- curs/curs_v rollback undefined
  #33 -- simultaneous pred+update protocol undefined

---

## Files Modified This Session

  frontend/branch_predictor/rtl/tage_cntrl.sv
    -- BP-019a: TAGE_TAG_BITS->MAX_TAG_WIDTH (2 sites).

  frontend/branch_predictor/rtl/bp_defines_pkg.sv
    -- BP-019a: TAGE_TAG_BITS parameter and FIXME
               comment removed.

  frontend/branch_predictor/rtl/tage_table.sv
    -- BP-020: always_comb blocks we_s0 and we_s1
               replace cascaded assign write-enable
               logic for both slots.

  frontend/branch_predictor/rtl/bp_structs_pkg.sv
    -- BP-021: bp_tage_meta_t typedef removed.
               bp_ftq_meta_t.tage retyped to
               tage_pred_meta_t.

  frontend/branch_predictor/tb/tb_tage_table.sv
    -- BP-019a: idx_hash_p0 and tag_hash_p0 declared
               and connected in DUT instantiation.

  frontend/branch_predictor/Makefile
    -- BP-019a: lint_tage_hash and sim_tage_hash
               targets removed.

  CLAUDE.md
    -- always_comb style rule added under Style Rules.

---

## Next Session (027)

### Step 1: Debt #33 -- simultaneous pred+update protocol

Requires design discussion before drafting. The debt
reads: no signals defined for same-cycle pred+upd to
overlapping entries. Read-during-write contract covers
mutual exclusion assumption but does not define
arbitration, ordering, or stall signaling. Define
protocol and additional signals before bp_cluster
integration. Requires interface doc update and new
testbench coverage.

Scope discussion needed at session start:
  - Which interface docs are affected?
    (tage_interfaces.md, tage_table_interfaces.md,
    and any others covering modules with both pred
    and upd ports in the same cycle)
  - Is the resolution stall, pipeline interlock,
    or defined ordering?
  - Which testbenches need new coverage?

### Step 2: Coverage planning item

Scope the formal coverage approach before bp_cluster:
  - Coverage matrix structure
  - Per-predictor coverage tracking
  - Verilator code coverage integration
  - Tooling and Makefile targets

### Step 3: bp_cluster integration

Begins after steps 1 and 2 complete.

---

## Prompt Files Created This Session

  prompts/BP-019a.md  -- PASS, 46 tests
  prompts/BP-020.md   -- PASS, 12/12 sim_tage_table,
                         46/46 sim_tage regression
  prompts/BP-021.md   -- PASS, lint only

