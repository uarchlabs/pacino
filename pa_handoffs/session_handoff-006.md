# Session Handoff 006

Written by Claude.ai at end of session-005 (continued).
Date: 2026-03-28

This is the delta from the BP-003 results review and BP-003-FIX
completion. Read PROJECT_STATE.md first, then this file, then
CLAUDE.md to restore full context.

---

## What This Session Covered

BP-003 (uBTB module) was run and confirmed PASS. BP-003-FIX
(retire UBTB_BR_* localparams) was run and confirmed PASS.
Two Verilator suppressions were graduated to project rules.
One encoding conflict was identified and resolved. Two
interface documents were written.

---

## BP-003 Results Confirmed

PASS. TC1-TC10 all pass. Exit code 0. Zero warnings after
suppressions.

Files written by Claude Code:
  rtl/bp_pkg.sv    -- modified: UBTB_TAG_BITS, UBTB_BR_*
                      localparams, ubtb_entry_t, ubtb_pred_t,
                      ubtb_upd_t structs added
  rtl/ubtb.sv      -- created: 256-entry 4-way uBTB
  tb/tb_ubtb.sv    -- created: TC1-TC10 self-checking
  Makefile         -- modified: sim_ubtb target added,
                      all target updated

Suppressions added by BP-003:
  -Wno-IMPORTSTAR  added to VER_FLAGS (permanent, see below)
  -Wno-VARHIDDEN   added to sim_ubtb target only (intentional
                   module parameter shadows package parameter)

## BP-003-FIX Results Confirmed

PASS. TC1-TC10 all pass. Exit code 0. Zero warnings.

Files modified by Claude Code:
  rtl/bp_pkg.sv    -- UBTB_BR_* localparam block removed (11
                      lines). br_type field in ubtb_entry_t,
                      ubtb_pred_t, ubtb_upd_t changed from
                      logic [2:0] to bp_br_type_e.
  rtl/ubtb.sv      -- no changes. Module stores and forwards
                      br_type without interpreting encoding
                      values. No UBTB_BR_* references existed.
  tb/tb_ubtb.sv    -- all UBTB_BR_* refs replaced with
                      bp_br_type_e values across TC2, TC4,
                      TC5, TC7, TC8, TC9, TC10. write_entry
                      task parameter changed from logic [2:0]
                      to bp_br_type_e. TC6 expanded from 6
                      to 7 entries covering all enum values:
                      NO_BRANCH, COND, DIRECT_UNC, DIRECT_CALL,
                      INDIRECT_CALL, INDIRECT_NONRET, RETURN.
  BP-003.md        -- Results Capture appended, marked
                      BP-003-FIX.

Note: one residual UBTB_BR_COND reference in TC10 was caught
by Verilator compile and fixed before declaring clean. RVA23
gap item from BP-003 (encoding mismatch requiring translation
at integration) is resolved -- bp_br_type_e is now the single
branch type encoding project-wide.

---

## Decisions Made This Session

### -Wno-IMPORTSTAR graduated to CLAUDE.md (permanent rule)
File-scope wildcard import (import bp_pkg::*; before module
declaration) is the mandated project style. Verilator 5.020
warns on wildcard imports in $unit scope. The warning is
structural and must be suppressed project-wide.

Add to CLAUDE.md Verilator Makefile Conventions section:

  - Always include -Wno-IMPORTSTAR in VER_FLAGS. The project
    mandates file-scope wildcard import (import bp_pkg::*;
    before the module declaration). Verilator 5.020 warns on
    wildcard imports in $unit scope. This is structural and
    suppressed project-wide.

### -Wno-VARHIDDEN scoping rule
When a module declares a parameter with the same name as a
bp_pkg parameter (e.g. NUM_PRED_SLOTS), Verilator warns
VARHIDDEN. This is intentional -- the module parameter is
the override point. Suppress per sim target only.

Add to CLAUDE.md Verilator Makefile Conventions section:

  - -Wno-VARHIDDEN: add to individual sim targets only when
    a module parameter intentionally shadows a bp_pkg
    parameter (e.g. NUM_PRED_SLOTS). Do not add to VER_FLAGS.

### UBTB_BR_* retired -- bp_br_type_e is the single encoding
bp_br_type_e is now the single branch type encoding used
project-wide. UBTB_BR_* localparams are gone. No translation
needed at bp_cluster integration. The pre-decoder resolves
full branch type from instruction bits before the post-execute
update channel fires.

---

## New Interface Documents Written

Place in planning/interfaces/ (replace README.md placeholder):

  ubtb_interfaces.md       -- uBTB prediction and update
                              port semantics, timing contracts,
                              miss signaling contract, known gaps
  bp_history_interfaces.md -- bp_history port semantics,
                              prediction update, checkpoint,
                              rollback, folded output contracts,
                              known gaps

---

## Files to Update Before BP-004

Manual edits to PROJECT_STATE.md:

1. Module Status table:
   - bp_pkg.sv notes: "BP-001+BP-002+BP-003 PASS, all pkg
     edits applied, UBTB_BR_* removed"
   - ubtb row: Status=Complete, Tests=tb_ubtb,
     Notes="TC1-TC10 passing"

2. Key Parameters block -- add:
   UBTB_ENTRIES  = 256
   UBTB_WAYS     = 4
   UBTB_SETS     = 64
   UBTB_IDX_BITS = 6
   UBTB_TAG_BITS = 20

3. Open Items table:
   - Remove BP-003-FIX row (complete)
   - Priority 1: BP-004 Loop Predictor, Status=READY to write

4. BP cluster open TBDs table -- mark G16 CLOSED, add G17-G23:

| G16 | planning/interfaces/ docs for     | CLOSED: written         |
|     | uBTB and bp_history                | session-006             |
| G17 | Slot 1 PC derivation (pred_pc+32)  | TBD at fetch interface  |
|     | assumed at BP-003. Ties to G8.     |                         |
| G18 | carry field consumer behavior in   | TBD at bp_cluster impl  |
|     | cluster top                        |                         |
| G19 | NO_BRANCH target field on hit:     | TBD                     |
|     | fall-through PC or zero?           |                         |
| G20 | bp_history dual slot update path   | Resolve before          |
|     | not defined for NUM_PRED_SLOTS=2   | bp_cluster impl         |
| G21 | rollback_en + pred_valid same-     | Resolve before          |
|     | cycle priority undefined           | bp_cluster impl         |
| G22 | One-cycle folded output invalid    | Tied to G15             |
|     | window after rollback              |                         |
| G23 | Checkpoint slot reclaim protocol   | TBD at FTQ impl         |

Manual edits to CLAUDE.md:

5. Verilator Makefile Conventions section: add
   -Wno-IMPORTSTAR rule and -Wno-VARHIDDEN scoping rule
   (exact text above).

File system:

6. Copy ubtb_interfaces.md and bp_history_interfaces.md
   into planning/interfaces/.
7. Remove or replace README.md placeholder in
   planning/interfaces/.

---

## Next Session

1. Apply all manual edits above.
2. Commit BP-003, BP-003-FIX results and interface docs
   to git.
3. Write BP-004 experiment prompt (Loop Predictor) in
   Claude.ai.

