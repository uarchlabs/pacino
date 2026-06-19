<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 048
Written by Claude.ai at end of session-047.
Date: 2026-06-09

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Session Summary

Session-047 closed the ITTAGE structural and target-write
defects and brought the ITTAGE unit suites to green. Work ran
BP-045 through BP-049a. Two technical debts closed (#66, #57)
and one structural defect found-and-fixed that an earlier task
had wrongly reported as complete.

Net outcome: TAGE update buses collapsed to shared per-slot
form (#66). ITTAGE given independent primary/alternate update
index buses and t_ port naming (#76). The ITTAGE unit-suite
escapes that had gone unreported for several sessions were
triaged, classified, and repaired -- including a CTR routing
defect that was in the TEST, not the RTL. The ITTAGE target
write path was verified and a provider-gating defect in it
corrected and proven by readback (#57).

Two specification documents were corrected during the session:
ittage_cntrl_decisions.md (CTR/TGT mutual-exclusivity relaxed)
and ittage_interfaces.md (provider-only target write made
explicit).

---

## What This Session Accomplished

### BP-045 -- TAGE port-dimension rework (#66, complete)

Collapsed ten per-table update/alloc buses in tage_cntrl from
[table][slot] to shared [slot] buses, routed by the existing
*_tbl_sel_u0 selects. Lint clean, all 68 tb_tage tests pass,
no expected-value edits.

Deviation accepted as a design refinement: a single shared
update index could not be preserved because primary and
alternate CTR writes can occur in the same cycle to different
tables at different history lengths. t_alt_upd_index_u0 was
added as a companion to the primary update index. This is the
correct three-index form (prm update, alt update, alloc), not
a workaround. #66 closed.

### BP-046 -- ITTAGE index buses + port naming (#76, complete)

Added the alternate update index bus to ITTAGE (the same
prm/alt independence as TAGE) and renamed the ittage_cntrl
ports that touch the tables to the t_ convention. Escapes held
constant before and after (the count check was the gate). #76
closed.

This task renamed cntrl ports, which required an out-of-scope
edit to tb_ittage_cntrl.sv to keep it compiling. Lesson folded
into prompt practice: when a task renames ports, the
instantiating testbench goes in the manifest from the start.

### BP-047 -- ITTAGE escape triage (debug, in-progress by design)

Classified all 46 ITTAGE unit-suite failures. sim_ittage was
81/0; the failures were in sim_ittage_cntrl (44) and
sim_ittage_table (2). Two root-cause groups: testbench
scaffolding (32) and an RTL CTR routing direction error (14).
No fixes -- triage only. The escape mechanism: tb_ittage_cntrl
was authored green at BP-036, the ITTAGE RTL churned across
BP-040/044, and that unit testbench was never re-run; the
"proven by readback" claims were against tb_ittage directed
rows, not the full cntrl suite, and PROJECT_STATUS carried a
stale 76-passing count throughout.

### BP-048 -- ITTAGE escape repair (complete)

Adjudicated the CTR routing direction against
ittage_cntrl_ctr_update_rules.md FIRST, before changing any
code. Finding: the RTL conformed to the rules table on every
row; the TEST (tb_ittage_cntrl TC-UPD-01..05) had the strobe
expectations transposed. BP-047's group-(c) "RTL inverted"
classification was therefore wrong -- it had treated the test
as correct. Only the test was repaired; the RTL g_ctr_upd was
not touched. Had the RTL been "fixed" to match the test, a
conforming block would have been broken.

Also fixed in the same task: the TC-USE-EPC co-assertion gap
(testbench), the pred_s0 pipeline-timing error (testbench),
and the t_alc_index_u0 source defect (RTL: was driven from the
primary update index, corrected to the allocation index field,
proven by a discriminating test where alc_idx != prm_idx,
fail-before/pass-after). Final: sim_ittage_cntrl 77/0,
sim_ittage_table 32/0, sim_ittage 81/0.

### BP-049 -- ITTAGE target write verification (#57, superseded)

Verified the target is written when the provider CTR is zero on
misprediction. RTL conformed on the provider-gating-on-CTR-zero
condition. Four directed tests added (TC-TGT-A..D). The IA
reported -- but rationalized away -- that the per-table target
write gate used (prm_match | alt_match), so a target write also
hit the non-provider table. The task marked itself complete and
claimed #57 closed. It was not: the tests read back only the
provider, so the non-provider corruption was invisible. See
BP-049a.

### BP-049a -- ITTAGE target write gating fix (#57, complete)

The interfaces document was NOT in BP-049's context, which is
why the defect was rationalized rather than flagged. With
ittage_interfaces.md "Target Write Gating" in context, the
provider-only invariant was explicit. Fix: split t_tgt_wr_u0
into t_prm_tgt_wr_u0 (UP=1, prm_ctr==0) and t_alt_tgt_wr_u0
(UP=0, alt_ctr==0); ittage_table tgt_we now
(prm_tgt_wr & prm_match | alt_tgt_wr & alt_match), mutually
exclusive, provider table only. Both regimes corrected. Tests
extended to read back the non-provider entry and confirm it is
unchanged; both extended checks fail-before/pass-after
(exp=c000 act=e000 and exp=c000 act=b000 showed the exact
corruption). sim_ittage 113/0, lint clean. #57 closed.

The IA tried a using_primary table-input approach first and
backed out after Verilator scheduling on partial-bit generate
assignments gave wrong results; the split-strobe approach
reuses the proven per-slot CTR-strobe pattern.

---

## Specification and Process Changes This Session

### Document corrections
- ittage_cntrl_decisions.md: added "Concurrent CTR and TGT
  Writes". CTR/TGT mutual-exclusivity relaxed. On misprediction:
  non-zero CTR decrements, no target write; zero CTR writes the
  target, CTR stays zero (a zero-to-zero CTR write is a no-op).
- ittage_interfaces.md: "Target Write Gating (tgt_wr_u0)" made
  explicit that only the provider's target field is written even
  when both hitting tables satisfy the conditions.

### CLAUDE.md changes
- Verification Expectations: suite-gating rules added. Every
  verification/testbench/debug/cleanup task runs the complete
  existing suite for each named module; a non-green in-scope
  suite blocks complete; waived failures must cite a TD number;
  status counts come from a current-session run; scope is the
  named module's suite only.
- Style Rules: banned-terms rule for non-engineering language
  (assert/deassert not "fire"; reference document not "ground
  truth"; etc.).

### PROJECT_CORE.md changes
- Prompt generation rules: suite-gating waiver rule added (a
  prompt for a unit with known failures must enumerate the
  waived tests and cite TD numbers in Constraints).
- Prompt content: clarified that waiver lists are
  experiment-specific and belong in Constraints.

---

## Prompt-author reminder (carry forward each session)

Verification/testbench/debug/cleanup prompts must list waived
failures and their TD numbers in the Constraints section
(authority: PROJECT_CORE prompt generation rules). Banned-terms
rule applies to all output (authority: CLAUDE.md Style Rules).

---

## Stale Status To Reconcile (carry-over, still not done)

These were flagged in handoff-047 and remain. Now reconcilable
against this session's green runs:
- ittage_cntrl.sv Module Status: PROJECT_STATUS now reads
  "81 tests passing." Current truth is sim_ittage_cntrl 77/0
  from BP-048. Update the count and drop any residual
  "Bug B/C/D" text.
- ittage.sv Module Status: still reads "sim_ittage 32 pass /
  3 fail (pre-existing, BP-042b)." Current truth is sim_ittage
  113/0 (BP-049a). Update.
- HAND-FIX-003 / BUG-001: superseded-by-BP-043a note present;
  wording confirmed clear that T0 now uses u_resolved.

---

## Open Technical Debt

ITTAGE unit verification is nearly complete. Closed this
session: #66, #76, #57. Remaining ITTAGE unit surface:
  - TD #56: ITTAGE EPC write proof (next, see below).
  - TD #61: ITTAGE aging / epoch path (next, see below).
  - TD #59: ITTAGE UAON trigger rules.
  - TD #63: ITTAGE allocation policy + write gating.
  - TD #65: ITTAGE prediction-side correctness.
TAGE unit surface (untouched this session):
  - TD #55 (EPC), #58 (UAON), #60 (aging), #62 (alloc),
    #64 (prediction-side). TAGE is green (68/68); not urgent.
Carried, unchanged:
  - TD #38 covergroup #7099; #43 ITTAGE CTR 3b->2b (will churn
    CTR tests written before it lands); #44 ittage_pred_strong;
    #49 arb queue port renaming; #52/#73 arb submodule + test;
    #67/#68 sram_init non-fast path; #69/#70 rollback;
    #71/#72 round-trip capstones.
  - TD #75 (no sim_ittage_fast target); #77 (scrub absolute
    paths from prompts, use RVA_ROOT -- non-design, infra).

---

## Next Session (048)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-048.md (this file)
  CLAUDE.md

### Planned work -- ITTAGE EPC then aging

Goal: close ITTAGE unit verification. The EPC and aging paths
are the remaining dark write/read paths for ITTAGE.

**Step 1 -- TD #56: ITTAGE EPC write proof**

epc_we_s0/s1 was changed in BP-044c as a USE rider and never
proven by readback. Seed an entry, drive an EPC-writing update,
read EPC back through a prediction (or direct RAM read where
post-alloc prediction ambiguity applies, per BP-049a). Prove
per provider, UP=1 and UP=0. The provider-gating defect class
(CTR, USE, TGT all had it) is the suspect -- check the EPC gate
is provider-only and add a discriminating non-provider readback
if the same (prm_match | alt_match) pattern appears.

**Step 2 -- TD #61: ITTAGE aging / epoch path**

Entire path dark (aging always disabled). Drive aging enabled,
exercise the EPC-vs-epoch compare and the USE decrement over
the interval. First confirm the aging interval is reachable at
current params (cf TD #39, where a different mechanism is
untestable at current params -- check before assuming the
interval can be hit). EPC proof (Step 1) must land first: aging
consumes the EPC field, so the EPC write must be proven before
testing the mechanism that reads it.

### Sequencing note
EPC before aging, same reason as the TAGE track: aging reads
EPC. After #56 and #61, the remaining ITTAGE items (#59 UAON,
#63 alloc, #65 prediction-side) finish the unit, then the #72
round-trip capstone.

