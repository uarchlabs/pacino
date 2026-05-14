# Session Handoff 020
Written by Claude.ai at end of session-019, for use at start of session-020.

Date: 2026-04-06
This session completed the BP-007d/e/f cleanup sequence and
produced BP-008b prompt. All three cleanup tasks passed.
tage_cntrl.sv and tage_table.sv are now architecturally
correct. BP-008b is ready to run. Read PROJECT_STATUS.md,
then this file, then CLAUDE.md to restore full context.

---

## What This Session Covered

Session context restored from session_handoff-019.

Primary work:
- Updated validate_and_extract.py: added Task ID populated
  check, Task ID consistency check between header and prompt
  block, and strengthened Context Loaded @ prefix validation
  (no spaces in filename, bare @ flagged, blank items ignored).
- Executed BP-007d: patch tage_table.sv alc ports. PASS.
  10/10 test cases passing.
- Executed BP-007e: remove hash logic from tage_cntrl.sv.
  PASS. Lint clean.
- Executed BP-007f: add local hash logic to tage_table.sv.
  PASS. 12/12 test cases passing.
- Generated BP-008b prompt. Ready to run next session.
- Resolved tage_table_hash_rules.md as planning document
  for BP-007f.
- tage_hash.sv abandoned in favor of per-table local hash
  generation. Retained in repo.
- INST_OFFSET = 2 added to bp_defines_pkg.sv as global
  parameter.
- pc[11:1] corrected to pc[12:2] in tage_table_interfaces.md
  T0 semantics section.
- Port naming convention section of tage_table_interfaces.md
  updated to match tage_interfaces.md (slot dimension via
  vector index, slot independence invariant added).

---

## Decisions Made This Session

### tage_hash.sv abandoned
Hash logic moves entirely into each tage_table instance.
tage_hash.sv is retained in the repo but its Makefile
targets will fail if invoked. Cleanup deferred.

### tage_table port changes (BP-007f)
Removed: index_hash_p0, tag_hash_p0
Added:   tage_pred_inp_p0[0:NUM_PRED_SLOTS-1] (tage_pred_inp_t)
         folded_hist (bp_folded_hist_t) -- //NOT USED on T0

### Hash functions settled in tage_table_hash_rules.md
Index hash (T1-T4):
  tmpA = (PC >> INST_OFFSET) ^ fh
  output = tmpA[THIS_INDEX_BITS-1:0]
Tag hash (T1-T4):
  tmpA = PC >> THIS_INDEX_BITS
  tmpB = tmpA ^ fh1 ^ (fh2 << 1)
  output = tmpB[THIS_TAG_BITS-1:0]
T0: index = pc[12:2] direct, no tag hash.
Per-table fh fields selected by case(THIS_TABLE).

### BP-008b context load reduced
tage_cntrl_decisions.md, tage_interfaces.md, and
tage_table_interfaces.md removed from BP-008b context
to reduce token load. The six remaining files are
sufficient: tage_cntrl.sv, the three rules documents,
bp_defines_pkg.sv, bp_structs_pkg.sv.

### validate_and_extract.py Task ID rules
Header Task ID must not be placeholder <BLOCK-NUMBER>.
Prompt ## Task ID must not be placeholder text.
Both values must match. Validation fails on any violation.
## Task ID section added to PROMPT_SECTIONS_ORDERED.

### Testbench always in scope when port list changes
When RTL port list changes, the testbench is always in
scope. List it explicitly in Context Loaded and
Deliverables. Do not rely on Claude Code to determine
this independently.

### alc_index_u0 width uses MAX_IDX_WIDTH not THIS_INDEX_BITS
BP-007d used MAX_IDX_WIDTH for alc_index_u0 width instead
of THIS_INDEX_BITS. This is nonconforming per the module
parameter spec. Cleanup deferred to BP-007c signal naming
pass.

---

## Technical Debt Modified This Session

Debt #20: CLOSED on tage_cntrl side (BP-007e complete).
Debt #21: CLOSED (BP-007f complete).
Debt #17: BP-007c scope expanded to include alc_index_u0
  width fix (MAX_IDX_WIDTH -> THIS_INDEX_BITS) and stale
  T0 tag hash compute-and-discard cleanup.

---

## Technical Debt Added This Session

None added.

---

## Files Created This Session

  BP-007d.md               -- experiment file, PASS
  BP-007e.md               -- experiment file, PASS
  BP-007f.md               -- experiment file, PASS
  BP-008b.md               -- prompt ready to run
  tage_table_hash_rules.md -- planning document, COMPLETE
  validate_and_extract.py  -- updated, Task ID checks added

## Files Modified This Session

  tage_table.sv
    -- alc_tbl_sel_u0, alc_index_u0 ports added (BP-007d).
    -- index_hash_p0, tag_hash_p0 ports removed (BP-007f).
    -- tage_pred_inp_p0, folded_hist ports added (BP-007f).
    -- Local index and tag hash logic added (BP-007f).

  tage_cntrl.sv
    -- fld_hist_p0 input removed (BP-007e).
    -- T1-T4 hash output ports removed (BP-007e).
    -- All associated hash logic removed (BP-007e).
    -- t_idx_r1, t_tag_r1 retained undriven (interim state).

  tage_table_interfaces.md
    -- Port naming convention updated to match
       tage_interfaces.md.
    -- Slot independence invariant added.
    -- pc[11:1] corrected to pc[12:2] in T0 semantics.
    -- alc_tbl_sel_u0, alc_index_u0 added to T0 and
       T1-TN port lists (BP-007d).
    -- index_hash_p0, tag_hash_p0 removed (BP-007f).
    -- tage_pred_inp_p0, folded_hist added (BP-007f).
    -- T1-TN semantics updated: hashes derived locally.

  tage_interfaces.md
    -- fld_hist_p0 removed from port list (BP-007e).
    -- Timing and Folded History sections updated to
       reflect folded_hist rename and local hash
       architecture (BP-007f).

  bp_defines_pkg.sv
    -- INST_OFFSET = 2 added as global parameter.

  tb_tage_table.sv
    -- index_hash_p0, tag_hash_p0 connections removed.
    -- tage_pred_inp_p0, folded_hist connections added.
    -- TC11, TC12 added covering hash-derived behavior.
    -- 10 existing test cases updated with PC stimulus.

---

## Next Session

### BP-008b: tage_cntrl.sv update logic
Prompt is ready at prompts/BP-008b.md.

Run in a fresh Claude Code session.
Context load (6 files, reduced from 9):
  tage_cntrl.sv
  tage_cntrl_ctr_update_rules.md
  tage_cntrl_useful_update_rules.md
  tage_cntrl_alloc_rules.md
  bp_defines_pkg.sv
  bp_structs_pkg.sv

After BP-008b passes:
  BP-009: tage.sv top level
  BP-010: tage.sv testbench

### PROJECT_STATUS.md Updates Needed

This edits have been completed:

1. Module table:
   - tage_table.sv: update notes to reflect BP-007d, BP-007f
     complete. Signal naming cleanup still pending (BP-007c).
   - tage_cntrl.sv: update notes to reflect BP-007e complete,
     BP-008b ready to run.
2. Technical Debt table:
   - Debt #20: mark CLOSED (BP-007e complete).
   - Debt #21: mark CLOSED (BP-007f complete).
   - Debt #17: add note that alc_index_u0 width and T0
     tag hash cleanup added to BP-007c scope.
   - Debt #23: validate_and_extract.py Task ID check is
     now implemented. Mark CLOSED.
3. Architectural Decisions / TAGE decomposition:
   - Add BP-007d, BP-007e, BP-007f as complete.
   - Note tage_hash.sv abandoned.
   - Add tage_table_hash_rules.md as planning document.
   - Update BP-008b status to prompt ready.
4. Add INST_OFFSET to BP Cluster Key Parameters section.

