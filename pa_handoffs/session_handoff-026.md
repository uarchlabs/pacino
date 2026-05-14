# Session Handoff 026
Written by Claude.ai at end of session_handoff-025, for use at start of session_handoff-026.

Date: 2026-04-09
This session executed the cleanup pass (BP-015 through
BP-019a), closing debts #24, #27, #34 and CLI items
001, 002, 004, 008, 011, 012. Read PROJECT_STATUS.md,
then this file, then CLAUDE.md to restore full context.

---

## What This Session Covered

Session context restored from session_handoff-025.

Primary work -- RTL fixes:
- BP-015 executed: debt #34 closed. T0 CTR update
  direction fixed in tage_cntrl.sv. Changed INC/DEC
  select from u_pred_crt[s] to u_resolved[s].
  TC-36 expected value updated (2'b10 -> 2'b00).
  TC-34 and upd_ctr_min_sat_tst Part 2 also required
  expected value updates (same root cause). 45/45 PASS.
- BP-016 executed: T0 DEC min saturation coverage gap
  closed. TC-46 (t0_dec_min_sat_tst) added to tb_tage.
  PC=40'h1200, bank=1, row=128. Row 13c at DEC boundary.
  46/46 PASS.

Primary work -- cleanup pass:
- BP-017a executed: CLI-001, CLI-002, CLI-004 closed.
  lp_hit added to loop_pred_interfaces.md field lists.
  CLI-002 audit found zero field name mismatches.
  bp_loop_meta_t: lp_set renamed to lp_idx.
  bp_cluster.md:411 lp_set reference noted -- fixed
  manually by user.
- BP-017b executed: CLI-008, CLI-011 closed.
  lp_pred_t and lp_upd_t fields renamed with lp_ prefix
  (12 fields each). loop_pred.sv, tb_loop_pred.sv,
  loop_pred_interfaces.md all updated. 13/13 PASS.
  Note: double-replacement artifact (lp_lp_pred_is_loop)
  caught and corrected within session.
- BP-018 executed: CLI-012 closed. ubtb.sv port naming
  retrofit: pred_pc->pred_pc_p0, pred->pred_p1,
  upd->upd_u0. tb_ubtb.sv port connections updated.
  10/10 PASS.
- BP-019 executed: debt #27 closed. debt #24 partial.
  tage_bim.sv and tage_table.sv: NUM_BANKS localparam
  added, BANKS=2 magic number eliminated.
  tage_cntrl.sv: TAGE_TAG_BITS->MAX_TAG_WIDTH (one site),
  TAGE_T0_CTR_BITS->TAGE_TBL_CTR[0] (6 sites + comment).
  bp_structs_pkg.sv: TAGE_CTR_BITS->MAX_CTR_WIDTH,
  TAGE_USEFUL_BITS->MAX_USE_WIDTH in tage_pred_meta_t
  and deprecated bp_tage_meta_t.
  bp_defines_pkg.sv: TAGE_T0_CTR_BITS, TAGE_CTR_BITS,
  TAGE_USEFUL_BITS removed. TAGE_TAG_BITS retained --
  stop-and-report guard fired: tage_hash.sv and
  tb_tage_hash.sv were unexpected consumers.
  46/46 PASS.
- BP-019a drafted (not yet run): completes debt #24.
  Fixes tb_tage_table.sv PINMISSING compile error
  (idx_hash_p0 and tag_hash_p0 ports unconnected).
  Replaces remaining TAGE_TAG_BITS in tage_cntrl.sv
  with MAX_TAG_WIDTH. Removes TAGE_TAG_BITS from
  bp_defines_pkg.sv. Removes lint_tage_hash and
  sim_tage_hash from Makefile. User to manually
  delete tage_hash.sv and tb_tage_hash.sv after
  BP-019a completes.

Additional decisions made this session:
- Debt #25 (context loaded path prefix corrections)
  closed as will-not-fix.
- Debt #28 (planning/arch and planning/interfaces doc
  drift) fixed manually by user.
- bp_cluster.md:411 lp_set reference fixed manually
  by user after BP-017a.
- tage_prm_tkn / tage_prm_pred_tkn field name drift
  found during BP-016 -- fixed manually by user,
  planning now matches RTL.

---

## Decisions Made This Session

### lp_pred_t and lp_upd_t field naming (settled)

All fields now carry consistent lp_ prefix:
  idx->lp_idx, tag->lp_tag, way->lp_way,
  pred_is_loop->lp_pred_is_loop,
  pred_taken->lp_pred_taken, age->lp_age,
  conf->lp_conf, past_itr->lp_past_itr,
  curr_itr->lp_curr_itr, curs->lp_curs,
  curs_v->lp_curs_v, victim->lp_victim.
  lp_hit was already correct.
  pc, target, actual_taken in lp_upd_t not prefixed
  (not loop-predictor-specific fields).
  bp_loop_meta_t not modified (lp_pst_itr and
  lp_cur_itr abbreviations intentional and settled).

### ubtb.sv port naming (settled)

  pred_pc -> pred_pc_p0
  pred    -> pred_p1
  upd     -> upd_u0

### tage_hash.sv status (settled)

tage_hash.sv is abandoned. Tables generate hashes
locally. tage_hash.sv and tb_tage_hash.sv will be
deleted by the user after BP-019a completes.

### Double-replacement artifact pattern (noted)

Sequential string replace on names sharing substrings
risks lp_lp_ or _p0_p0 artifacts. Claude Code has
caught these within sessions but prompt authors
should be aware. Explicit before/after rename tables
in prompts help prevent this.

---

## Technical Debt Status After This Session

Closed this session:
  #24 -- TAGE_TBL_* scalar parameter cleanup
         (partial in BP-019, completed in BP-019a)
  #25 -- context loaded path prefix corrections
         (will-not-fix)
  #27 -- bw_ram BANKS=2 magic number
  #28 -- planning/arch and interfaces doc drift
         (manually fixed)
  #34 -- T0 CTR update direction (BP-015)
  CLI-001, CLI-002, CLI-004, CLI-008 (BP-017a)
  CLI-011 (BP-017b)
  CLI-012 (BP-018)
  T0 DEC min saturation coverage gap (BP-016)

Still open:
  #7  -- curs/curs_v rollback undefined
  #14 -- bp_tage_meta_t migration to tage_pred_meta_t
         (TI7 -- not yet started)
  #33 -- simultaneous pred+update protocol undefined
  #35 -- test count validation script

---

## Files Modified This Session

  frontend/branch_predictor/rtl/tage_cntrl.sv
    -- BP-015: T0 CTR INC/DEC select fixed.
    -- BP-019: TAGE_TAG_BITS->MAX_TAG_WIDTH (1 site),
               TAGE_T0_CTR_BITS->TAGE_TBL_CTR[0]
               (6 sites + comment).

  frontend/branch_predictor/rtl/tage_bim.sv
    -- BP-019: NUM_BANKS localparam added.

  frontend/branch_predictor/rtl/tage_table.sv
    -- BP-019: NUM_BANKS localparam added.

  frontend/branch_predictor/rtl/bp_structs_pkg.sv
    -- BP-017a: bp_loop_meta_t lp_set->lp_idx.
    -- BP-017b: lp_pred_t and lp_upd_t field renames.
    -- BP-019: TAGE_CTR_BITS->MAX_CTR_WIDTH,
               TAGE_USEFUL_BITS->MAX_USE_WIDTH.

  frontend/branch_predictor/rtl/bp_defines_pkg.sv
    -- BP-019: TAGE_T0_CTR_BITS, TAGE_CTR_BITS,
               TAGE_USEFUL_BITS removed.

  frontend/branch_predictor/rtl/loop_pred.sv
    -- BP-017b: field name updates throughout.

  frontend/branch_predictor/rtl/ubtb.sv
    -- BP-018: port naming retrofit.

  frontend/branch_predictor/tb/tb_tage.sv
    -- BP-015: TC-36, TC-34, upd_ctr_min_sat_tst
               Part 2 expected values updated.
    -- BP-016: TC-46 added. Test count now 46.

  frontend/branch_predictor/tb/tb_loop_pred.sv
    -- BP-017b: field name updates throughout.

  frontend/branch_predictor/tb/tb_ubtb.sv
    -- BP-018: port connection names updated.

  planning/interfaces/loop_pred_interfaces.md
    -- BP-017a: lp_hit added to field lists.
    -- BP-017b: field name labels updated.

---

## Next Session (026)

### Step 1: Run BP-019a

BP-019a prompt is drafted and ready. File is at
prompts/BP-019a.md (saved as BP-019b.md on disk --
content is correct, filename cosmetic).

After BP-019a completes:
  - Delete tage_hash.sv manually
  - Delete tb_tage_hash.sv manually
  - Run make all to confirm clean build
  - Update PROJECT_STATUS.md to fully close debt #24

### Step 2: TI7 -- bp_tage_meta_t migration

bp_tage_meta_t is deprecated (marked THIS IS OLD DO
NOT USE in bp_structs_pkg.sv). It is still present
and bp_ftq_meta_t.tage still references it. Migration
to tage_pred_meta_t required before bp_cluster.

Before drafting: read current bp_structs_pkg.sv,
bp_ftq_meta_t, and any RTL that accesses the tage
field of bp_ftq_meta_t to confirm no active consumer
exists outside the struct definition itself.

### Step 3: Debt #33

Simultaneous prediction and update protocol undefined.
Requires interface doc update and new testbench
coverage. Scope before drafting.

### Step 4: Debt #35

Test count validation script. Add to sim target or
standalone script comparing expected test count in
prompt header against PASS lines in sim output.

### Step 5: bp_cluster integration

Begins after steps 1-4 complete.

---

## Prompt Files Created This Session

  prompts/BP-015.md   -- PASS, 45 tests
  prompts/BP-016.md   -- PASS, 46 tests
  prompts/BP-017a.md  -- PASS, no sim
  prompts/BP-017b.md  -- PASS, 13 tests
  prompts/BP-018.md   -- PASS, 10 tests
  prompts/BP-019.md   -- PASS, 46 tests (debt #24 partial)
  prompts/BP-019a.md  -- NOT YET RUN

