<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 007

Written by Claude.ai at end of session-007.
Date: 2026-03-28

This is the delta from the BP-004 split, BP-004a completion,
and methodology fixes. Read PROJECT_STATE.md first, then
this file, then CLAUDE.md to restore full context.

---

## What This Session Covered

Housekeeping: STATUS.md confirmed redundant and deleted.
Planning directory renamed from .planning to planning in
all files. Duplicate bp_cluster.md at planning root
confirmed empty and moved to planning/arch/bp_cluster.md.
CLAUDE.md duplicate -Wno-IMPORTSTAR/-Wno-VARHIDDEN block
removed.

REPORT_TEMPLATE.md reviewed and confirmed consistent with
methodology. Two undocumented sections found (Model field,
Overview of task). PROJECT_STATE.md methodology block
updated to reflect these.

loop_pred_interfaces.md written by Claude.ai/Jeff and
placed in planning/interfaces/.

BP-004 written, then abandoned -- output token limit
exceeded at 80% context. Split into BP-004a and BP-004b.
BP-004a confirmed PASS. BP-004b not yet run.

---

## Decisions Made This Session

### backward branch filter on loop predictor allocation
Allocation only occurs when upd_valid_p0=1,
pred_is_loop=0, actual_taken=1, AND target < pc.
Forward branches do not trigger allocation.
target field added to lp_upd_t to support this filter.

### lp_upd_t target field
lp_upd_t now has 16 fields (was 15 in original BP-004):
pc, target, actual_taken, plus all 12 lp_pred_t fields.
target is VA_WIDTH bits. Used for backward branch filter.

### -Wno-UNUSED graduated to permanent rule
Add to CLAUDE.md Verilator Makefile Conventions:
  - Always include -Wno-UNUSED in VER_FLAGS. Package-only
    files and structs not yet consumed by any module will
    trigger unused warnings. This is structural and
    suppressed project-wide.

### Experiment file rules added to CLAUDE.md
Two new rules under a new Experiment File Rules heading:
  - Only read or write files explicitly listed in the
    Context Loaded manifest or Deliverables section. Do
    not create, modify, or write to any file not in
    these lists.
  - When writing Results Capture, write it into the exact
    file path named in Deliverables. Fill in every section
    completely. Do not leave any section as TBD if
    information is available.

### REPORT_TEMPLATE.md Deliverables section update
Last bullet changed to name exact file path and require
complete fill-in of all Results Capture sections.

### Technical debt #6 added
curs/curs_v rollback behavior undefined. Seznec
externalizes this via SLIM structure. Inline fields in
lp_entry_t have no defined checkpoint/rollback path.
Resolve at bp_cluster impl or migrate to SLIM-style
external structure.

---

## BP-004a Results Confirmed

PASS. make lint and make sim both exit zero, zero warnings.
Existing testbench: BP-001 16 checks passed.

Files modified by Claude Code:
  rtl/bp_pkg.sv -- LP_CONF_LEVEL added to LP parameter
                   block. lp_entry_t, lp_pred_t, lp_upd_t
                   added after uBTB struct block.

Note: LP parameter block was already present from a prior
session. Only LP_CONF_LEVEL was new. LP_WAY_BITS is an
extra localparam already in the file:
  localparam int LP_WAY_BITS = $clog2(LP_TBL_WAYS);
It is equivalent to $clog2(LP_TBL_WAYS) and is used by
loop_pred.sv for way/victim field widths. Retained.

Note: -Wno-UNUSED was already in VER_FLAGS from a prior
session. Not added by BP-004a. Graduated to permanent
rule this session.

Note: Results Capture was written to prompt.md instead
of BP-004a.md. Root cause: prompt did not name the exact
target file. Fixed in CLAUDE.md, REPORT_TEMPLATE.md, and
PROJECT_STATE.md methodology block.

---

## BP-004b Status

Not yet run. Prompt is ready. Key differences from
original BP-004:
  - Context Loaded does not include ubtb_interfaces.md
  - Backward branch filter added to miss allocation
    condition
  - target field present in lp_upd_t
  - TC3 added (forward branch filter verification)
    bumping original TC3-TC12 to TC4-TC13
  - Deliverables names exact file path for Results Capture
  - Experiment File Rules constraint added

---

## Files to Update Before BP-004b

Manual edits to PROJECT_STATE.md:

1. Module Status table:
   - Add loop_pred row:
     Status=In Progress, Tests=tb_loop_pred,
     Notes="BP-004a PASS, BP-004b pending"
   - bp_pkg.sv notes: add "BP-004a lp_entry_t, lp_pred_t,
     lp_upd_t added, LP_CONF_LEVEL added"

2. Technical Debt table -- add item #6:
   | 6 | curs/curs_v rollback undefined.  | Resolve at bp_cluster  |
   |   | Seznec uses SLIM structure.      | impl or migrate to     |
   |   | Inline fields have no defined    | SLIM-style external    |
   |   | checkpoint/rollback path.        | structure.             |

3. Open Items table:
   - Priority 1: BP-004b Loop Predictor module, Status=READY

4. Planning directory: confirm all references updated
   from .planning to planning throughout.

Manual edits to CLAUDE.md:

5. Verilator Makefile Conventions: add -Wno-UNUSED rule
   (exact text above).

6. Add Experiment File Rules section (exact text above).

Manual edits to REPORT_TEMPLATE.md:

7. Deliverables last bullet: name exact file path and
   require complete Results Capture fill-in (exact text
   above).

File system:

8. Confirm planning/interfaces/loop_pred_interfaces.md
   is saved with backward branch filter decision reflected
   in LI5 and update behavior section.

9. Save BP-004a.md with Results Capture copied from
   prompt.md. Mark status complete.

10. Save BP-004b.md prompt ready to run.

11. Delete or archive original BP-004.md marked abandoned.

---

## Next Session

1. Apply all manual edits above.
2. Run BP-004b.
3. Report results back to Claude.ai.
4. If PASS: write BP-005 (FTB).
