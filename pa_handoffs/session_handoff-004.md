<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 004

Written by Claude.ai at end of session-004.
Date: 2026-03-28

This is the delta from session-004. Read PROJECT_STATE.md first,
then this file, then CLAUDE.md to restore full context.

---

## What This Session Covered

Session-004 was the history module architecture session. It produced:

1. Full history module micro-architecture -- GHR/PHR as circular
   buffers with external pointers, folded histories, checkpoints
2. bp_cluster.md updated with History Module section and corrections
3. BP-002 experiment prompt written and corrected
4. Multiple corrections to ITTAGE IT5, SC ST4, and SC history
   values caught and fixed
5. Session ended early due to context length reliability concerns
   before BP-002 was run

BP-002 is READY but has not been run. Commit the corrected files
(bp_cluster.md, BP-002.md) from this session before starting BP-002.

---

## Decisions Made This Session

### History module architecture (locked)

GHR: 256b circular buffer, pointer GHIST_PTR_BITS=8b, external input.
PHR: 32b circular buffer, pointer PHIST_PTR_BITS=5b, external input.
Buffer storage is internal to bp_history module.
Pointers are driven externally -- not managed inside the module.

PHR update rule (locked):
  PHR[phist_ptr] = pred_pc[2] ^ pred_pc[3]
  Bit selection subject to future tuning.

Rollback: accept new pointer value as input, recompute all folds
from circular buffer contents. No fold checkpointing.

Checkpoint per FTQ slot: ghist_ptr (8b) + phist_ptr (5b) only.
Folds are NOT checkpointed -- recomputed on rollback (G15).

bp_ftq_entry_t change: ghr_snapshot (256b) removed, replaced
with ghist_ptr (8b) and phist_ptr (5b). This requires a
str_replace update to bp_pkg.sv in BP-002 Step 2d.

### Folded history scope (locked)

TAGE T1-T4: three folds each (idx, tag_fh1, tag_fh2).
ITTAGE IT1-IT4: three folds each. IT5 is BrIMLI -- NO folds.
SC ST1-ST3: one index fold each.
SC ST0 (hist=0) and ST4 (hist=none): NO folds.

SC history depths (locked, original values restored):
  ST1: 4b
  ST2: 10b
  ST3: 16b

### SC ST4 label (correction)
ST4 has no label. It is simply a 1024-entry direct-mapped 6b
wide table with no history. The label "IMLI" must NOT appear
in SC context -- it belongs only to ITTAGE IT5 (BrIMLI).
This was a fabrication error caught this session.

### New parameters for bp_pkg.sv (BP-002 Step 2)
To be added by Claude Code in BP-002:
  PHR_WIDTH      = 32
  GHIST_PTR_BITS = $clog2(GHR_WIDTH)
  PHIST_PTR_BITS = $clog2(PHR_WIDTH)
  SC_T1_HIST     = 4
  SC_T2_HIST     = 10
  SC_T3_HIST     = 16

New struct to be added:
  bp_folded_hist_t -- all fold outputs, added to bp_pkg.sv

### G15 logged (fold recompute timing concern)
Fold recompute from circular buffer on rollback is the chosen
strategy for now. Timing impact (27 folds in one cycle) is a
known concern, deferred until critical path is characterized.

---

## Files Changed This Session

  planning/arch/bp_cluster.md  -- History Module section added,
                                   IT5/SC corrections applied,
                                   FTQ entry checkpoint updated
  prompts/frontend/branch_predictor/BP-002.md  -- written, READY

---

## Known Errors Fixed This Session

1. SC ST4 incorrectly labelled "IMLI" -- removed. ST4 has no label.
2. SC history depths were transiently corrupted to 16/64b -- restored
   to correct values: ST1=4b, ST2=10b, ST3=16b.
3. ITTAGE IT5 folds were present in bp_folded_hist_t -- removed.
   IT5 is BrIMLI with no history.
4. bp_cluster.md History Module section incorrectly stated checkpoints
   store folded histories -- corrected to pointer-only.
5. bp_cluster.md History Module section listed IT1-IT5 folds --
   corrected to IT1-IT4.

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
| G15 | Fold recompute timing concern      | Deferred, revisit later |

---

## Next Session

1. Verify bp_cluster.md and BP-002.md are correct before running.
   Key things to check:
   - SC ST4 has no IMLI label
   - SC history depths: ST1=4b, ST2=10b, ST3=16b
   - IT5 absent from bp_folded_hist_t field list
   - bp_ftq_entry_t has ghist_ptr+phist_ptr, not ghr_snapshot

2. Run BP-002 (history module). Report Results Capture here.

3. After BP-002 PASS: graduate decisions to PROJECT_STATE.md
   and write session_handoff-005.md.

