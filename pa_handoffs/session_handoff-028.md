# Session Handoff 028
Written by Claude.ai at end of session-027.
Date: 2026-04-10

This session executed BP-022 through BP-022b, completing
a full parameter naming and vectorization cleanup of
bp_defines_pkg.sv and all consumer files. Read
PROJECT_STATUS.md, then this file, then CLAUDE.md to
restore full context.

---

## What This Session Covered

Session context restored from session_handoff-027.

- Debt #33 resolved by design document. bp_arb_spec.md
  (planning/arch/bp_arb_spec.md) was reviewed and
  accepted as the resolution. Open item A (same-entry
  conflict ordering) closed: prediction goes first,
  reads pre-update state, no address comparison at
  arbiter. Open items B-I remain in the spec.

- BP-022 executed: four-part parameter cleanup of
  bp_defines_pkg.sv.
  Change 1: six MAX_* localparams renamed to TAGE_MAX_*.
  All consumer sites updated in bp_structs_pkg.sv,
  tage_table.sv, tage_cntrl.sv, tage.sv, tb_tage.sv.
  Changes 3a/3b: SC_TBL_ENTRIES, SC_TBL_DATA,
  SC_TBL_HIST vectors added. SC_MAX_IDX_WIDTH and
  SC_MAX_DATA_WIDTH localparams added.
  Changes 4a/4b: IT_NUM_TABLES and IT_TBL_* vectors
  added. IT_MAX_* localparams added.
  Changes 2, 3c, 4c: STOPPED -- bp_history.sv outside
  context. All 12 targets green. 46/46 PASS.

- BP-022a executed: completed deferred scalar removals.
  Added TAGE_MAX_FH/FH1/FH2, IT_MAX_FH/FH1/FH2,
  SC_MAX_FH localparams to bp_defines_pkg.sv.
  Removed 16 TAGE per-table scalars (T1-T4 FH/FH1/
  FH2/HIST), all SC per-table scalars, all IT per-table
  scalars from bp_defines_pkg.sv.
  Updated bp_folded_hist_t in bp_structs_pkg.sv: all
  27 field widths replaced with MAX-width params.
  Updated bp_history.sv: cast widths replaced with
  MAX params, fold W and H arguments replaced with
  TBL vector indexing.
  Updated tb_bp_history.sv: TAGE_T1_FH references
  updated to TAGE_MAX_FH and TBL vector indexing.
  Eight backward-compat aliases added temporarily for
  tb_tage_table.sv (out of context). SC_NUM_MAIN_TBLS
  and SC_TBL_INDEX_BITS retained temporarily.
  All 12 targets green. 46/46 PASS. 12/12 sim_history.

- BP-022b executed: removed all temporary aliases.
  Eight backward-compat aliases removed from
  bp_defines_pkg.sv.
  SC_NUM_MAIN_TBLS removed from bp_defines_pkg.sv.
  bp_structs_pkg.sv: [SC_NUM_MAIN_TBLS-1:0] replaced
  with literal [3:0] in bp_sc_meta_t.
  tb_tage_table.sv: 8 symbol substitutions applied.
  tb_bp_pkg.sv: SC_TBL_INDEX_BITS -> SC_MAX_IDX_WIDTH.
  All 12 targets green. All test counts match.

---

## Decisions Made This Session

### Debt #33 resolution approach

bp_arb_spec.md defines a credit-based PQ/UQ arbiter
per RAM-based predictor. Same-entry conflict: predict
goes first, reads pre-update state. SC chains from
TAGE response buffer. Merged metadata structs
cond_pred_meta_t and cond_pred_upd_inp_t defined.
Debt #33 marked closed. RTL work deferred to BP-023
(TAGE arbitration additions).

### MAX_* parameter naming

All field-width parameters now carry predictor prefix:
TAGE_MAX_*, SC_MAX_*, IT_MAX_*. Unprefixed MAX_*
names are fully removed from the codebase including
testbenches.

### Fold-width max parameters

TAGE_MAX_FH/FH1/FH2, IT_MAX_FH/FH1/FH2, SC_MAX_FH
added as explicit localparams. bp_folded_hist_t fields
and bp_history.sv casts use these maxima. Individual
table fold width and history length arguments use
TBL vector indexing (TAGE_TBL_FH[n] etc.).

### SC_NUM_MAIN_TBLS removed

Replaced with literal [3:0] in bp_sc_meta_t. The
4-table count is a fixed architectural constant.

---

## Technical Debt Status After This Session

Closed this session:
  #33 -- simultaneous pred+update protocol (bp_arb_spec.md)

New minor deferred items (not assigned debt numbers):
  - SC_TBL_INDEX_BITS remains in bp_defines_pkg.sv
    with no active consumers. Remove in next housekeeping
    pass.
  - Commented-out alias block (lines 165-170) remains
    in bp_defines_pkg.sv as dead code. Remove in next
    housekeeping pass.

Still open:
  #7  -- curs/curs_v rollback undefined

---

## Files Modified This Session

  frontend/branch_predictor/rtl/bp_defines_pkg.sv
    -- BP-022:  six MAX_* -> TAGE_MAX_* renames.
                SC_TBL_ENTRIES, SC_TBL_DATA, SC_TBL_HIST
                vectors added. SC_MAX_IDX_WIDTH,
                SC_MAX_DATA_WIDTH added.
                IT_NUM_TABLES, IT_TBL_* vectors added.
                IT_MAX_* localparams added.
    -- BP-022a: TAGE_MAX_FH/FH1/FH2, IT_MAX_FH/FH1/FH2,
                SC_MAX_FH added. 16 TAGE scalars removed.
                SC per-table scalars removed. IT per-table
                scalars removed. Temporary aliases added.
    -- BP-022b: 8 temporary aliases removed.
                SC_NUM_MAIN_TBLS removed.

  frontend/branch_predictor/rtl/bp_structs_pkg.sv
    -- BP-022:  six TAGE_MAX_* consumer sites updated.
    -- BP-022a: bp_folded_hist_t 27 field widths updated
                to MAX params. bp_sc_meta_t updated to
                use SC_MAX_* params.
    -- BP-022b: [SC_NUM_MAIN_TBLS-1:0] -> [3:0] in
                bp_sc_meta_t.

  frontend/branch_predictor/rtl/bp_history.sv
    -- BP-022a: cast widths -> MAX params.
                fold W and H args -> TBL vector indexing.

  frontend/branch_predictor/rtl/tage_table.sv
    -- BP-022:  six TAGE_MAX_* consumer sites updated.

  frontend/branch_predictor/rtl/tage_cntrl.sv
    -- BP-022:  six TAGE_MAX_* consumer sites updated.

  frontend/branch_predictor/rtl/tage.sv
    -- BP-022:  six TAGE_MAX_* consumer sites updated.

  frontend/branch_predictor/tb/tb_tage.sv
    -- BP-022:  six TAGE_MAX_* consumer sites updated
                (out-of-scope edit required for build
                integrity, documented).

  frontend/branch_predictor/tb/tb_bp_history.sv
    -- BP-022a: TAGE_T1_FH -> TAGE_MAX_FH.
                fold args -> TBL vector indexing.

  frontend/branch_predictor/tb/tb_tage_table.sv
    -- BP-022b: 8 symbol substitutions applied.

  frontend/branch_predictor/tb/tb_bp_pkg.sv
    -- BP-022b: SC_TBL_INDEX_BITS -> SC_MAX_IDX_WIDTH.

---

## Next Session (028)

### Step 1: BP-022c -- minor housekeeping

Two items deferred from BP-022b:
  - Remove SC_TBL_INDEX_BITS from bp_defines_pkg.sv
    (no active consumers confirmed).
  - Remove commented-out alias block (lines 165-170)
    from bp_defines_pkg.sv.
  Lint-only verification. No sim changes expected.
  Small enough to combine with Step 2 if context allows.

### Step 2: Coverage planning

Scope the formal coverage approach before bp_cluster:
  - Coverage matrix structure
  - Per-predictor coverage tracking
  - Verilator code coverage integration
  - Tooling and Makefile targets

### Step 3: BP-023 -- TAGE arbitration

Per bp_arb_spec.md section 9:
  - bp_defines_pkg.sv: add TAGE arbitration parameters
    (section 4.2).
  - bp_structs_pkg.sv: add bp_arb_trx_t,
    cond_pred_meta_t, cond_pred_upd_inp_t, sc stubs.
  - tage.sv: add PQ, UQ, credit arbiter, competing-stage
    mux, response buffer.
  - tage_cntrl.sv: add trx_type gating.
  - tb_tage.sv: add TB-ARB-01 through TB-ARB-08.
  Package changes should precede RTL changes.

### Step 4: bp_cluster integration

Begins after Steps 2 and 3 complete.

---

## Prompt Files Created This Session

  prompts/BP-022.md   -- PASS, partial (Changes 1,3a/b,
                         4a/b complete; 2,3c,4c deferred)
  prompts/BP-022a.md  -- PASS, all 12 targets green
  prompts/BP-022b.md  -- PASS, all 12 targets green
