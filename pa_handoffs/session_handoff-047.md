<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 047
Written by Claude.ai at end of session-046.
Date: 2026-06-07

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Session Summary

Session-046 was a PA session. No work followed the
original session-046 plan (INFRA-007 re-run, BP-043/044/045
as written, BP-040 verification). That plan was overtaken
by a chain of ITTAGE/TAGE update-path bug fixes that the
verification work exposed.

Net outcome: the TAGE CTR path and the ITTAGE CTR and USE
paths are now fixed and proven by RAM readback. A planning-
document error in the TAGE T0 CTR rules was found and
corrected. A backdoor RAM-seeding method was established in
tb_ittage.sv and is the basis for all future ITTAGE unit
testing. The full remaining unit-test surface for TAGE and
ITTAGE was enumerated as technical debt #55-#74.

BP-045 (ITTAGE manual testbench shell) was scrapped.

---

## What This Session Accomplished

### BP-043 -- TAGE CTR/USE test audit (complete)

Audited CTR/USE tests in tb_tage.sv against the session-045
planning docs. Five tests had stale expected values, one had
invalid stimulus. All traced to one root cause: BP-015
resolved_taken expected values surviving HAND-FIX-003's
switch to !u_mispredict. No RTL bug. 68 tests pass.

### Planning-doc error found: TAGE T0 CTR rows 13a-d

The IA flagged that the BP-043 result implied T0 behaves as
a confidence counter (INC on correct / DEC on wrong), which
is wrong for a bimodal direction counter. Investigation
confirmed rows 13a-d of tage_cntrl_ctr_update_rules.md were
authored with confidence semantics -- a mental bleed-over
from ITTAGE, where CTR is confidence. Corrected to direction-
toward-resolved: DEC, INC, DEC, INC. This is the second
contradiction-detection win of the project (the IA caught a
wrong premise in a planning doc, not a code-vs-spec mismatch).

### BP-043a -- TAGE T0 correction (complete)

Reversed HAND-FIX-003 for the T0 path (!u_mispredict ->
u_resolved). Re-corrected the five BP-043 tests to the
direction reading. Only rows 13a/13b change behavior; 13c/13d
agree under both readings, which served as a built-in scope
check. All tests pass. HAND-FIX-003 record and BUG-001 noted
as superseded in PROJECT_STATUS.

### BP-044 -- ITTAGE CTR/USE test audit (complete, superseded)

Added 5 tests (CTR row 1, USE rows 1-4). Confirmed the CTR
write path broken: no provider CTR update landed in RAM.
Stopped per constraint. USE rows 1-4 covered and still valid.
Note: the prompt over-blocked -- it told the IA to halt on
Bug C, a KNOWN bug, rather than pre-authorizing the cited fix.
Lesson for future prompts: pre-authorize fixes for already-
characterized bugs; reserve stop-and-report for new failures.

### BP-044a -- ITTAGE CTR fix (ABANDONED)

Fixed the CTR strobe swap and passed 53 checks, but proved
the UP=0 alternate-provider rows using one table in both
roles (IT1 as primary and alternate). That is not valid
proof of a real alternate provider. Abandoned and redone.

### BP-044b -- ITTAGE CTR fix, redone (complete)

Root cause: ittage_cntrl.sv g_ctr_upd had TWO bugs --
(A) strobe/data swapped between UP=1 and UP=0 branches, and
(B) no ittage_hit gate, so H=0 updates wrote CTR (row 1
violation). 044a only ever found (A). Both fixed.
Established the backdoor RAM-seeding method: bw_write task
writes a full entry (VAL/CTR/USE/EPC/TGT/TAG) directly to
u_ram_s0/u_ram_s1 inside each generated ittage_table. UP=0
rows now proven with a genuine second-table alternate
(IT2 primary, IT1 alternate). All reachable CTR rows proven
by readback. 64 checks pass.

### BP-044c -- ITTAGE USE full table (complete)

Confirmed the TD #51 thesis a second time. Bug: use_we and
epc_we in ittage_table.sv gated on prm_match only, so UP=0
USE/EPC writes to the alternate table never landed. Fixed by
gating on (prm_ctr_wr & prm_match | alt_ctr_wr & alt_match).
All 6 USE rows + saturation proven by readback, UP=0 with a
real alternate provider. 81 checks pass. EPC gate was changed
as a USE rider but EPC itself was NOT proven by readback ->
TD #55/#56.

### Backdoor RAM-seeding method (reusable)

Path: dut.<...>.gen_ittage_tables[T].gen_active.u_table.
u_ram_s0.mem[bank][ent] (slot 0), u_ram_s1 (slot 1).
Entry packing: VAL[0], CTR[3:1], USE[5:4], EPC[7:6],
TGT[45:8], TAG[ALLOC_DATA_WIDTH-1:46]. Address split:
bank=idx[INDEX_BITS-1], ent=idx[INDEX_BITS-2:0]. This is the
standard mechanism for all future ITTAGE unit tests. Do not
build allocate-then-predict scaffolding. An equivalent
backdoor path exists for TAGE tables and should be derived
the same way for the TAGE tasks.

### Technical debt #55-#74 enumerated

Full remaining TAGE/ITTAGE unit-test surface captured in
PROJECT_STATUS. Dedup pass merged/closed #51 (CTR/USE done,
survivors -> #57/#62/#63), #15 (EPC implemented -> #55/#56),
and folded #41 into #60. See PROJECT_STATUS for the full
table and cross-references.

---

## Methodology Notes

- Manual testing did not find the T0 error; first-principles
  IA reasoning against domain knowledge did. Jeff's decision:
  deprioritize lengthy manual testing in favor of completing
  the design to first principles and enabling formal and
  mutation testing. The contradiction-detection capability
  (IA cross-checking artifacts against domain priors) is the
  property to preserve.
- Cross-track contamination (ITTAGE confidence-counter
  semantics bleeding into the TAGE T0 direction-counter rules)
  is a recurring error class wherever TAGE and ITTAGE share
  vocabulary (CTR, USE, provider, strong). Consider an explicit
  note that CTR means direction in TAGE T0 and confidence in
  ITTAGE.
- Prompt discipline: keep prompts minimal. Do not restate the
  planning doc, prior-session history, or rules already in
  CLAUDE.md. State only what the IA cannot read for itself.
- Isolation before round-trip: prove each field/mechanism
  alone before mixing. Mixing before isolation reproduces the
  multi-cause ambiguity that stalled BP-044.

---

## Stale Status To Reconcile (not yet done)

- Module Status line for ittage_cntrl.sv still reads
  "BP-040 Bug B/C/D unverified." Bug C is fixed (BP-044b).
  Bug B/D origin descriptions were never in context this
  session; reconcile against current RTL or close.
- Module Status line for ittage.sv still reads "32 pass /
  3 fail (pre-existing)." Those 3 (TC-P04 prm_ctr, TC-P04
  pred_strong, TC-ARB-04 pred_ctr) were repaired by BP-044b.
  Update the count.
- HAND-FIX-003 / BUG-001 records: superseded-by-BP-043a note
  added; confirm wording is clear that the T0 path now uses
  u_resolved.

---

## Open Technical Debt

See PROJECT_STATUS #55-#74 for the full TAGE/ITTAGE unit-test
surface. Highest-suspicion untested items, per the two
confirmed provider-gating bugs (CTR, USE):
  - TD #57: ITTAGE TGT write path (same gating-defect suspect).
  - TD #62/#63: allocation write path (same suspect).
Carried, unchanged:
  - TD #38: covergroup #7099 re-check.
  - TD #43: ITTAGE CTR width 3b->2b (will churn any CTR tests
    written before it lands -- sequence consideration).
  - TD #44: ittage_pred_strong definition.
  - TD #66: tage_cntrl per-table index rework.
  - TD #49: arb queue status port renaming.
  - TD #52/#73: arb logic submodule + arb behavioral test.

---

## Next Session (047)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-047.md (this file)
  CLAUDE.md

### Planned work -- TAGE first, then ITTAGE

Each item is a verification task following the BP-044b/044c
pattern: seed entries by backdoor RAM write, drive the
update, prove the result by readback through a prediction.
RTL fixes authorized where a genuine bug is found and cited
against the planning doc rows; the TGT/allocation/USE blocks
are TD #51 suspects so expect possible provider-gating
defects analogous to CTR/USE.

**Step 0 -- TD #66: Tage port dimensions**

See the description in PROJECT_STATUS.md for tech
debt #66.

**Step 1 -- TD #55: TAGE EPC write proof**

Derive the TAGE backdoor RAM path. Seed an entry, drive an
EPC-writing update, read EPC back through a prediction,
confirm it lands in the provider entry.

**Step 2 -- TD #58: TAGE UAON**

tage_cntrl_uaon_update_rules.md is Draft -- promote to
authority. Directed test per row; prove use_alt_on_na
fires/clears per rule. UAON was only ever used as test setup
before, never verified as the unit under test.

**Step 3 -- TD #60: TAGE aging / epoch**

Entire path dark (tage_enable_aging always 0). Drive aging
high, exercise the EPC-vs-epoch compare and USE decrement
over the interval. First confirm the aging interval is
reachable at current params (cf TD #39, where a different
mechanism is untestable at current params).

**Step 4 -- TD #56: ITTAGE EPC write proof**

epc_we_s0/s1 was fixed in BP-044c as a USE rider but never
proven. Readback-verify per provider, UP=1 and UP=0, using
the established bw_write backdoor.

**Step 5 -- TD #59: ITTAGE UAON**

ittage_cntrl_uaon_update_rules.md is Draft -- promote to
authority. Same as Step 2 for ittage.

**Step 6 -- TD #61: ITTAGE aging / epoch**

Same as Step 3 for ittage. Consumes the EPC field whose
write changed in BP-044c (Step 4 should land first).

**Step 7 -- TD #57: ITTAGE TGT writes**

Target replacement. TD #51 suspect. Target written on
mispredict when CTR is null only. Trace the TGT write path,
readback-verify all reachable rows.

### Sequencing note
EPC proof (Steps 1, 4) before aging (Steps 3, 6): aging
consumes EPC, so prove the EPC write lands before testing the
mechanism that reads it.


