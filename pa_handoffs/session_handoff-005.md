# Session Handoff 005

Written by Claude.ai at end of session-005.
Date: 2026-03-28

This is the delta from session-005. Read PROJECT_STATE.md first,
then this file, then CLAUDE.md to restore full context.

---

## What This Session Covered

Session-005 was the BP-002 results review and bookkeeping session.
No new RTL was written. BP-002 was confirmed PASS and two issues
were identified for resolution in BP-003.

---

## BP-002 Results Confirmed

PASS. 12/12 checks. Exit code 0. Zero warnings after two
suppressions (both established project pattern):
  - BLKSEQ: inline in testbench clock generator
  - UNUSED: Makefile flag for package-only compile

Files written by Claude Code:
  rtl/bp_pkg.sv       452 lines  (modified: 4 str_replace edits)
  rtl/bp_history.sv   537 lines  (created)
  tb/tb_bp_history.sv 450 lines  (created)
  tb/tb_bp_pkg.sv           --   (modified: ghr_snapshot removed,
                                  ghist_ptr + phist_ptr added,
                                  check count 15 -> 16)
  Makefile             44 lines  (modified: sim_history added)

TC8 rollback semantics confirmed correct: rollback restores pointer
only; ghr_mem and phr_mem are not cleared. Folds recompute from
current buffer state at restored pointer. TC8 reference model
correctly uses post-advance ghr_buf, so the test exercises the
contamination case (4 post-checkpoint writes land within the T1
fold window). Semantics match XiangShan model and are locked.

---

## Decisions Made This Session

### num_branches valid range (locked)
Valid values: 0, 1, 2 only. Value 3 (2'b11) is undefined behavior.
bp_history.sv does not need to handle it. Add to KEY PARAMETERS
in PROJECT_STATE.md.

### Package import style (new project rule)
File-scope import is required. Module-header import is not
permitted. Correct form:

  import bp_pkg::*;
  module bp_history
    (

Incorrect form (Verilator accepts but project rejects):

  module bp_history
    import bp_pkg::*;
  (

This rule applies to all modules going forward. Add to CLAUDE.md.
bp_history.sv currently uses the incorrect form -- fix in BP-003
Step 0 via str_replace before any other edits.

### PHR folding deferred (architectural note)
bp_history.sv maintains phr_mem and accepts PHR updates, but
phr_buf is not used in any folded history computation. All folds
in bp_folded_hist_t are GHR-derived only. PHR contribution to
index and tag hashing is TBD -- resolved at TAGE and ITTAGE
implementation sessions. Add explicit note to bp_cluster.md
History Module section so it is visible when those sessions run.

---

## Files to Update Before BP-003

The following manual edits to PROJECT_STATE.md are needed:

1. Module Status table:
   - bp_pkg.sv notes: "BP-001 + BP-002 PASS, all pkg edits applied"
   - bp_history.sv: Status=Complete, Tests=tb_bp_history,
     Notes="12 passing"

2. Key Parameters block -- confirm present, add if missing:
     PHR_WIDTH      = 32
     GHIST_PTR_BITS = 8
     PHIST_PTR_BITS = 5
     SC_T1_HIST     = 4
     SC_T2_HIST     = 10
     SC_T3_HIST     = 16
   Add: num_branches valid range: 0-2. Value 3 undefined.

3. Open Items table:
   - Remove or close BP-002 row
   - Priority 1: "Run BP-003 -- uBTB module", Status=READY to write

The following edits to CLAUDE.md are needed:

4. Add package import style rule (file-scope import required,
   see form above).

The following edit to bp_cluster.md is needed:

5. History Module section: add PHR folding deferred note.

---

## BP-003 Step 0 (carry into prompt)

Before any new RTL work, Claude Code must fix the import style
in bp_history.sv:

  str_replace in rtl/bp_history.sv:
  OLD:
    module bp_history
      import bp_pkg::*;
    (
  NEW:
    import bp_pkg::*;
    module bp_history
    (

Re-run make all after this edit. Expect exit 0, zero warnings.
Document in Results Capture as a carried fix, not a new finding.

---

## Next Session

1. Apply manual PROJECT_STATE.md, CLAUDE.md, and bp_cluster.md
   edits listed above.
2. Write BP-003 experiment prompt (uBTB module).
3. BP-003 Step 0: fix bp_history.sv import style.
4. Implement and verify uBTB.
