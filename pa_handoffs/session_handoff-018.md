<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 018
Written by Claude.ai at end of session-018 (claude.ai session).
Date: 2026-04-05
This session was a requirements Q&A session for BP-008
(tage_cntrl.sv). No RTL was produced. No prompts were executed.
Read PROJECT_STATUS.md, then this file, then CLAUDE.md to
restore full context.

---

## What This Session Covered

Session context restored from session_handoff-017.
tage_interfaces.md, tage_table_interfaces.md, and
tage_table.sv loaded as additional context.

Primary work:
- Full Q&A session to specify tage_cntrl.sv requirements.
- Produced four design reference documents (see below).
- Resolved all open items except one manual file edit.
- Defined BP-008 decomposition into BP-008a and BP-008b.

---

## Decisions Made This Session

### BP-008 decomposed into two prompts
BP-008a: tage_cntrl.sv prediction side logic only.
BP-008b: tage_cntrl.sv update logic added to BP-008a result.
Each prompt asks Claude Code to compile and lint clean only.
No testbench until BP-010.

### BP-009 and BP-010 defined
BP-009: tage.sv top level. Instantiates tage_hash, tage_table
(via generate loop), and tage_cntrl. Stitches all components.
BP-010: testbench for the complete TAGE predictor.

### T0 behavior settled (closes prediction side of debt #18)
No valid bit. tage_cntrl treats T0 as always-hit.
T0 uses 2b saturating counter. Initializes to 2'b10.
T0 is never the alternate provider.
Update side of debt #18 (T0 fields in tage_table) remains
open until T0 implementation.

### use_alt_on_na counters
Two 4b saturating counters, uaon_0 and uaon_1, one per slot.
Both owned by tage_cntrl. Independent operation.
TAGE_UAON_THRES = 8, was manually added to bp_defines_pkg.sv.
Trigger: provider CTR == 3'b011 or 3'b100 (boundary states).
tage_pred_strong reflects NOT WEAK on the final provider CTR
after UAON mux selection, not strictly the primary CTR.

### CTR encoding settled
3b saturating counter for T1-T4.
Direction = CTR[2] (MSB).
Boundary states 3'b011 and 3'b100 are the UAON trigger points.
Newly allocated entries initialize to 3'b100 (weakest taken).

### Allocation no-candidate sentinel
tage_alloc_comp == 0 (T0) indicates no allocation candidate
found. T0 is never a valid allocation target. This sentinel
is consistent with comp == 0 as tagged-table-miss indicator
in the CTR update rules. When tage_alloc_comp == 0 at update
time, alc_wr_u0 is suppressed for all tables.

### Useful bit decrement on failed allocation not implemented
If no useful == 0 candidate exists: no action.
Epoch aging handles starvation prevention.

### Concurrent CTR and USE writes
When CTR and USE updates target the same table and index in
the same cycle, tage_cntrl performs a single RAM write.
Both field ranges are enabled simultaneously in bweb_n.
Write data for both fields aligned in ram_din in the same
cycle. tage_table handles the merged write structurally.

### Aging enable and interval inputs
tage_enable_aging  : 1b primary input to tage and tage_cntrl.
tage_aging_interval: 32b primary input to tage and tage_cntrl.
On reset: lcl_aging_interval_0/1 loaded from tage_aging_interval.
Interval counters decrement on tage_pred_rdy_0/1_p2 assertion.
No pred_src gating -- decrement is unconditional on rdy.

### tage_pred_meta_t field renames -- applied manually
tage_pred_idx    -> tage_prm_idx
tage_pred_comp   -> tage_prm_comp
tage_pred_useful -> tage_prm_useful
tage_pred_ctr    -> tage_prm_ctr
Fields added:
  tage_prm_pred_tkn  -- primary component CTR MSB
  tage_alt_pred_tkn  -- alternate component CTR MSB
These changes have been applied to bp_structs_pkg.sv manually.
Claude Code must not re-apply them.

### tage_interfaces.md struct blocks to be replaced
The three struct definitions in tage_interfaces.md
(tage_pred_inp_t, tage_pred_meta_t, tage_upd_inp_t) were
manually replaced with a pointer line:
  "See bp_structs_pkg.sv for the authoritative definition."
Prose descriptions above each struct are retained.

---

## Reference Documents Produced This Session

All four files are in planning/interfaces/ or equivalent.
Load all four as additional context for BP-008a and BP-008b.

  tage_cntrl_decisions.md
    -- Settled design decisions for tage_cntrl.sv.
    -- Cross-cutting rules including concurrent write behavior.
    -- References the three rules files below.
    -- Status: SETTLED.

  tage_cntrl_ctr_update_rules.md
    -- CTR update truth table, rows 1-21.
    -- Status: SETTLED.

  tage_cntrl_useful_update_rules.md
    -- UAON background, component selection, UAON update rules.
    -- Table 7 useful update truth table.
    -- Aging interval and epoch operation.
    -- u_eff computation formula.
    -- Status: SETTLED.

  tage_cntrl_alloc_rules.md
    -- Allocation trigger, candidate selection, initialization.
    -- Write data assembly and strobe generation.
    -- No-candidate sentinel definition.
    -- Status: SETTLED.

---

## Technical Debt Added This Session

None added. Prediction side of debt #18 closed by T0
behavior decision above. Update side of debt #18 remains.

---

## Technical Debt Modified This Session

| 18 | Definition of T0 fields/behavior   | Prediction side closed.  |
|    |                                     | Update side (tage_table  |
|    |                                     | T0 entry layout) remains |
|    |                                     | TBD at T0 implementation.|

---

## Files Created This Session

  tage_cntrl_decisions.md       -- new
  tage_cntrl_ctr_update_rules.md -- new
  tage_cntrl_useful_update_rules.md -- new
  tage_cntrl_alloc_rules.md     -- new

## Files Modified This Session

  bp_structs_pkg.sv             -- tage_pred_meta_t field renames
                                   and additions. Applied manually.

## Files Pending Manual Edit Before BP-008a

  tage_interfaces.md            -- struct blocks were replaced manually
                                   with bp_structs_pkg.sv pointer.
  bp_defines_pkg.sv             -- TAGE_UAON_THRES = 8 was added manually.

---

## Next Session

### BP-008a: tage_cntrl.sv prediction side
Load as context:
  tage_interfaces.md
  tage_table_interfaces.md
  tage_cntrl_decisions.md
  tage_cntrl_ctr_update_rules.md
  tage_cntrl_useful_update_rules.md
  tage_cntrl_alloc_rules.md
Deliverable: tage_cntrl.sv prediction logic only.
Compile and lint clean. No testbench.

### BP-008b: tage_cntrl.sv update side
Load same context as BP-008a plus BP-008a result.
Deliverable: tage_cntrl.sv with update logic added.
Compile and lint clean. No testbench.

### BP-009: tage.sv top level
Instantiate tage_hash, tage_table (generate loop),
and tage_cntrl. Stitch all components.
Compile and lint clean. No testbench.

### BP-010: TAGE testbench
tb_tage.sv. Full self-checking testbench.

---

## PROJECT_STATUS.md Updates Needed

1. Module table: add tage_cntrl.sv row, status In Progress,
   note BP-008a/008b decomposition.
2. Debt #18: update resolution path to reflect prediction
   side closed, update side pending T0 implementation.
3. Add BP-008a, BP-008b, BP-009, BP-010 to TAGE decomposition
   section under Architectural Decisions.

