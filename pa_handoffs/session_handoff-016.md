<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 016
Written by Claude.ai at end of session-016 (claude.ai session).
Date: 2026-04-03
This session defined tage_table_interfaces.md, produced and
executed BP-007a and BP-007b, and recorded several process
failures for follow-on cleanup.
Read PROJECT_STATE.md first, then PROJECT_STATUS.md,
then this file, then CLAUDE.md to restore full context.
---
## What This Session Covered

Session context restored from session_handoff-015.
bp_cluster.md and tage_interfaces.md loaded as additional
context.

Primary work:
- Defined tage_table_interfaces.md through iterative
  review.
- Resolved TI6 (bank selection policy).
- Produced and executed BP-007a. 10/10 PASS.
- Identified and corrected CNTRL_BITS_WIDTH error.
- Produced and executed BP-007b. 10/10 PASS.
- Recorded multiple process failures (see below).

---
## Decisions Made This Session

### TI6 resolved -- bank selection policy
Banks in TAGE tables are not address-banked SRAMs. Each
table contains two independent RAMs, one per prediction
slot. RAM0 serves slot 0, RAM1 serves slot 1. Selection
is structural -- slot index is the RAM select. No runtime
bank selection mux. No PC-bit steering. Unrelated to the
bw_ram BANKS parameter or the sram_init bank scheme.

### NUM_PRED_SLOTS=2 is the project default for TAGE work
NUM_PRED_SLOTS is retained as a parameter but always 2
for current design work. Slot 1 logic is always present
unconditionally. Reduction to 1 is a deferred cleanup
task recorded in technical debt.

### tage_cntrl is retained as a separate module
The decomposition is:
  BP-006: tage_hash.sv   -- complete, correct
  BP-007: tage_table.sv  -- complete (BP-007b)
                            signal naming cleanup pending
                            (BP-007c, technical debt)
  BP-008: tage_cntrl.sv  -- not yet started
  BP-009: tage.sv        -- not yet started

### CNTRL_BITS_WIDTH corrected
BP-007a defined CNTRL_BITS_WIDTH without EPC. This was
wrong. EPC is a control field. Correct definition:
  CNTRL_BITS_WIDTH = MAX_EPC_WIDTH+MAX_USE_WIDTH
                   + MAX_CTR_WIDTH+MAX_VAL_WIDTH
ALLOC_DATA_WIDTH:
  ALLOC_DATA_WIDTH = CNTRL_BITS_WIDTH+THIS_TAG_BITS
The original ALLOC_DATA_WIDTH spec formula was never
wrong. The error was in CNTRL_BITS_WIDTH omitting
MAX_EPC_WIDTH. Corrected in BP-007b.

### EPC field
EPC is present in the entry layout and in
tage_table_interfaces.md. Its semantic definition is
not yet documented. Recorded as technical debt.

### Prompt generation rules added to PROJECT_STATE.md
- Do not add CLAUDE.md to Context Loaded in generated
  prompts. Claude Code loads it automatically.
- Do not explicitly restate style rules already in
  CLAUDE.md.
- Do not use results capture marker syntax in prompt
  guidance text -- causes validation script failures.
- Describe generate style explicitly in prompts to
  prevent context explosion.

---
## Process Failures This Session

### PF-001: CNTRL_BITS_WIDTH omitted EPC
CNTRL_BITS_WIDTH was defined in tage_table_interfaces.md
without MAX_EPC_WIDTH. EPC was added to the entry layout
later in the session and the derived parameters section
was not updated. Claude Code implemented the wrong spec.
Required BP-007b to correct. Root cause: spec drift
during iterative editing not caught before prompt
execution.

### PF-002: Signal naming convention ignored in BP-007b
tage_table_interfaces.md explicitly states slot is not
part of the signal name in this module and that array
indexing is used instead. The BP-007b prompt invented
_s0/_s1 suffixes in violation of the spec. Claude Code
implemented the nonconforming names. Root cause: prompt
author (claude.ai) did not apply the specification that
was loaded in context. Requires BP-007c to correct.
Deferred to fresh session.

### PF-003: Out-of-scope file modification
Claude Code modified a header comment block in
tage_table.sv that was outside the scope of BP-007b.
This violates the explicit CLAUDE.md rule prohibiting
modifications outside the Results Capture markers.
The change was self-reported in Results Capture but
should have been stopped and flagged before execution.
CLAUDE.md rule has been strengthened to explicitly
cover content within listed files that is outside
prompt scope, and to require stop-and-report before
any out-of-scope change is made.

---
## Technical Debt Added This Session

| 1  | NUM_PRED_SLOTS=2 default.         | Cleanup session  |
|    | Generate removal and              | after tage       |
|    | NUM_PRED_SLOTS=1 tests pending.   | complete         |
| 15 | EPC field semantics not           | Define before    |
|    | yet documented.                   | BP-008           |
| 16 | Merge PROJECT_STATE.md and        | Cleanup session  |
|    | PROJECT_STATUS.md into single     |                  |
|    | file.                             |                  |
| 17 | ALLOC_DATA_WIDTH padding when     | Resolve at T0    |
|    | THIS_ < MAX_ -- unused bits       | implementation   |
|    | between EPC and TAG fields.       |                  |
| 18 | BP-007b signal naming             | Run in future    |
|    | nonconforming. _s0/_s1 suffixes   | session. Run in  |
|    | used instead of array indexing    | fresh claude.ai  |
|    | per tage_table_interfaces.md.     | session only.    |
|    | Prompt author error.              |                  |

---
## Files Created or Modified This Session
  planning/interfaces/tage_table_interfaces.md -- created
  prompts/bp/BP-007a.md -- created, executed, complete
  prompts/bp/BP-007b.md -- created, executed, complete
    (signal naming nonconforming, BP-007c pending)
  frontend/branch_predictor/rtl/tage_table.sv -- updated
  frontend/branch_predictor/tb/tb_tage_table.sv -- updated
  frontend/branch_predictor/rtl/bp_defines_pkg.sv -- updated
    MAX_IDX_WIDTH, MAX_TAG_WIDTH, MAX_EPC_WIDTH,
    MAX_USE_WIDTH, MAX_CTR_WIDTH, MAX_VAL_WIDTH added.

---
## Next Session
1. Re-read tage_interfaces.md update behavior section
   carefully before designing tage_cntrl ports.
2. Begin BP-008 (tage_cntrl.sv) 
3. Update tage_table_interfaces.md:
   - Correct ALLOC_DATA_WIDTH formula.
   - Close TI6 in Known Gaps table.
   - Document EPC field semantics (debt #15).
4. Close TI6 in tage_interfaces.md Known Gaps table.
5. Pending cleanup session (CLI-001, CLI-002, CLI-004,
   CLI-008, CLI-011, CLI-012, TI7) still deferred.

---
## PROJECT_STATUS.md Updates Needed

These edits were completed:

- Add tage_table.sv row to Module Status table:
    | tage_table.sv | Complete* | tb_tage_table | BP-007b
    |               |           |               | PASS 10/10.
    |               |           |               | *Signal naming
    |               |           |               | cleanup pending
    |               |           |               | (BP-007c)
- Add tage_table_interfaces.md row:
    | tage_table_interfaces.md | Draft | -- | Created
    |                          |       |    | session-016.
    |                          |       |    | Updates pending.
- Add technical debt rows 14-18 as listed above.

## PROJECT_STATE.md Updates Needed

These edits were completed:

- Add TI6 resolution to BP cluster track section.
- Add CNTRL_BITS_WIDTH and ALLOC_DATA_WIDTH definitions
  to BP cluster track section.
- Add NUM_PRED_SLOTS=2 default decision to BP cluster
  track section.
- Add prompt generation rules to Experiment File Rules
  section.
- Update CLAUDE.md rule for out-of-scope modifications
  (PF-003 corrective action).
