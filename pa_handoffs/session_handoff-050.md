<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 050
Written by Claude.ai at end of session-049.
Date: 2026-06-11

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Session Summary

Session-049 closed all remaining TAGE directed-validation paths.
Work ran BP-056 through BP-061. Six technical debts closed (#55,
#58, #60, #62, #64, #71). One real RTL defect found and fixed
(BUG-003, the UAON single-hit guard). No specification document
needed rewriting; one aging-timing note was added and the
TAGE UAON rules document was promoted to Complete.

Net outcome: TAGE EPC write, UAON trigger rules, aging/epoch
path, allocation, prediction-side correctness, and the
round-trip capstone are each directed-tested as the unit under
test and proven by readback. Both predictors, TAGE and ITTAGE,
are now directed-validated at the unit level. The TAGE set
followed the ITTAGE BP-050b..055 sequence as its template.

The sim_tage count progressed 73 -> 81 -> 87 -> 95 -> 102 -> 103
across the six tasks, consistent at each step.

---

## What This Session Accomplished

### BP-056 -- TAGE EPC write proof (#55, complete)

The epc_we gate in tage_table.sv was changed in BP-044c
(HAND-FIX-001: use_we and epc_we gate on prm_alt_match =
prm_match | alt_match), never proven by readback since. Five
directed tests (TC-69..73): provider-match and alternate-match
EPC writes, UP=1 and UP=0, plus the no-write negative case.
lcl_epoch was forced to 2'b10 against seeded EPC=00 so the
write is a visible delta. Step-6 defect injection reverted the
gate to prm_match alone; TC-71/72 (alternate-match) failed with
EPC unwritten, then restored. No net RTL change. sim_tage 73/0.
#55 closed.

The TAGE EPC write rides the USE write enable (not the CTR
subset relation the ITTAGE EPC write used in BP-050b); the
authority is the USE update rules.

### BP-057 -- TAGE UAON trigger rules (#58, complete)

Found and fixed a real RTL defect (BUG-003): the uaon_upd_ff
gate was missing && u_alt_tagged[s]. When the provider hit a
tagged table (T1-T4) but the alternate fell through to the
untagged base table T0, the UAON counter moved on a comparison
that carries no training signal. Same class as the ITTAGE
defect in #59 (BP-051). The two-line guard was added and proven
by removal (TC-81 fails, counter moves) and restore. Eight
directed tests (TC-74..81): reset value, each update-rule row,
HAND-FIX-002 threshold boundary, single-hit guard. The UAON
counter and use_alt_on_na are read directly; the table entries
are seeding only. sim_tage 81/0. #58 closed.
tage_cntrl_uaon_update_rules.md promoted Draft -> Complete; doc
and RTL agree on all rows.

### BP-058 -- TAGE aging / epoch path (#60, complete)

Every prior tage test ran tage_enable_aging=0; this is the
first time aging was driven high. Six directed tests
(TC-82..87): reset values, epoch advance, epoch wrap, age
compare, USE reduction effect, enable gating. No RTL change.
Supersedes #41. sim_tage 87/0. #60 closed.

Findings:
- age = (lcl_epoch - EPC) mod 4; u_eff = USE for age 0,
  USE>>1 for age 1, 0 for age >= 2. Confirmed from the doc and
  by TC-85 (u_eff 11/01/00/00 across ages 0/1/2/3).
- TC-86 proves the aging effect on behaviour: a fresh entry
  (age 0) is not an allocation candidate; the same entry aged
  to u_eff=0 is. The u_eff alloc scan reads EPC/USE from raw
  RAM regardless of tag match or VALID.
- Epoch advances the tick after the interval reaches its
  boundary (N+1), matching ITTAGE; checked explicitly in TC-83.
- Reachability: tage_aging_interval is a 32-bit input port, not
  a static parameter. The boundary (counter == 0) is always
  reachable; no #39-class risk. The real operating interval is
  a cluster-integration input, exercised here at 0.
- Two documentation gaps reported. Jeff added the N+1
  epoch-advance timing to the aging section of
  tage_cntrl_use_update_rules.md, and declined the epoch-wrap
  note (a 2-bit register wrapping is self-evident).

### BP-059 -- TAGE allocation + write gating (#62, complete)

Eight directed tests (TC-88..95): trigger gating, which table
allocates, the no-consecutive scan stop, the alc_comp==0
sentinel and write suppression, the pre-hashed alc_idx, the
allocated entry contents, alc_we gating, and RAM-level write
isolation. No RTL change. sim_tage 95/0. #62 closed.
Prerequisite #66 was already closed (BP-045).

RAM-level write isolation (TC-95) was folded into this task
rather than deferred to the capstone: it runs at sim_tage with
the tables present, so the selected table is read back changed
and a non-selected table (seeded to a distinct value) read back
unchanged. This is the check BP-053 could not reach for ITTAGE
(it ran controller-only) and that BP-055 Phase 4 closed there.
The allocation write-data field order was cross-checked against
tage_table_entry_formats.md and matches; no BP-053-class field
swap exists in TAGE.

### BP-060 -- TAGE prediction-side (#64, complete)

Seven directed tests (TC-96..102): provider selection
(longest tagged match), alternate selection (next-longest or
T0), no-hit fallback to T0, using_primary via forced UAON,
pred_strong, direction mux, and pipeline-stage validity at p2.
The prediction outputs are read directly; the table entries are
seeding only. No RTL change. sim_tage 102/0. #64 closed.

pred_strong was the BUG-001 watch point (the ITTAGE doc had a
carryover error corrected in BP-054). The TAGE doc states
pred_strong = provider CTR != 3 and != 4; RTL implements
(ctr != 3'b011) && (ctr != 3'b100); they agree. No discrepancy.
TAGE predicts direction (CTR MSB), not a target.

### BP-061 -- TAGE round-trip capstone (#71, complete)

One mixed-flow test (TC-103) exercising CTR, USE, allocation,
and EPC together on entries that collide at one RAM address
(T1-T4 all map to idx=512). No TGT step (TAGE has no target
field). No RTL change. sim_tage 103/0. #71 closed.

The gate (#55/58/60/62/64) was met. The flow held aging
disabled and seeded EPC=epoch (age 0) so USE deltas are visible
-- this avoids the non-discriminating USE check the ITTAGE
capstone (BP-055) hit when EPC differed from the epoch. The
interference checks pass: step 3 confirms the CTR/EPC from step
2 survive a USE write to a different table; step 4 confirms the
allocation does not disturb the provider entry or the T4
interference reference. UAON forced as a read input, not
trained.

One non-discriminating field to note: because EPC=epoch=0
throughout, the EPC writes in this flow write 0 over 0, so the
EPC value landing is not tested here. EPC value landing is
proven separately in BP-056 with a real delta and injection;
the capstone's purpose is cross-path interference.

---

## Specification and Process Changes This Session

### Document changes
- tage_cntrl_uaon_update_rules.md promoted Draft -> Complete
  (BP-057); doc and RTL agree on all rows.
- tage_cntrl_use_update_rules.md aging section: N+1
  epoch-advance timing added (Jeff, BP-058).
- tage_cntrl_alloc_rules.md: confirmed Complete; write-data
  field order matches tage_table_entry_formats.md. No change.

### RTL change
- BUG-003: tage_cntrl.sv uaon_upd_ff gate extended with
  && u_alt_tagged[s] (BP-057). The one RTL change this session.
  Recorded in BUG Records.

### PROJECT_STATUS
- Updated this session to reflect BP-056..061 and to reconcile
  the handoff-049 stale-status list. tage_cntrl.sv In progress
  -> Complete; tage.sv 73 -> 103, directed validation complete;
  TAGE decomposition block updated; ittage_cntrl_uaon/use rule
  rows synced Draft -> Complete (handoff-049 recorded these
  promoted in session 048; the Module Status table had not been
  synced).

---

## Prompt-author reminder (carry forward each session)

- ALL TARGETS MUST RUN: enumerate every Makefile sim and lint
  target, run each, report per-target counts from this session
  (authority: CLAUDE.md Verification Expectations).
- Tests self-contained: seed every dependency, no carried state,
  no reliance on test order (authority: CLAUDE.md).
- Manifest minimal: reference doc(s), RTL under test, packages,
  testbench, Makefile. Nothing padded. Do not carry an ITTAGE
  manifest doc over to a TAGE task without checking the task
  reads it.
- Port-change tasks run every instantiating testbench.
- Engineering language only.
- USE-visible tests: when a USE delta must be observable, seed
  EPC = lcl_epoch (age 0) so u_eff = raw USE. When EPC != epoch,
  u_eff < USE and an increment can write a value equal to the
  seed (non-discriminating). This is the BP-055 lesson.
- Readback target: when the pass criterion is a control register
  or a prediction output (UAON counter, prediction meta), read
  that signal directly; use entry-format only to seed. When the
  pass criterion is table contents (EPC, allocation), full-entry
  readback is correct.
- sim_tage and sim_tage_fast emit a numeric pass count; report
  the integer, not a pass banner.

---

## Stale Status To Reconcile

PROJECT_STATUS was updated this session; paste the updated copy.
One unresolved item remains, flagged but not changed because the
correct value could not be verified and it was not touched this
session:

- Module Status table lists these as Draft while the
  decomposition section lists them Complete:
    ittage_interfaces.md
    ittage_table_interfaces.md
    tage_table_interfaces.md
  Determine which is authoritative and sync the two locations.

---

## Open Technical Debt

TAGE directed validation is complete. Closed this session:
#55, #58, #60, #62, #64, #71. Both predictors (TAGE and ITTAGE)
are directed-validated at the unit level.

Remaining unit-level deferred items:
  - #67/#68 sram_init non-fast path (tage / ittage)
  - #69/#70 rollback / history recompute -> bp_cluster
  - #74 dual-slot (NUM_PRED_SLOTS=2)
  - #43 ITTAGE CTR width 3b -> 2b
  - #75 sim_ittage_fast target
  - #38 covergroup #7099 re-check
  - #17 TAGE table signal naming
  - #77 path scrub (infra, possibly manual)

Arbitration / cluster items, pending bp_cluster:
  - #37 trx_type registration; #39 starvation override
    untestable at current params; #40 arb spec discrepancy;
    #49 arb queue pin renaming; #52 arb submodule refactor;
    #73 arbitration behavioral test.

Preconditions now met but still deferred:
  - #1 NUM_PRED_SLOTS reduction ("after TAGE complete") and the
    dual-slot work #74 are no longer blocked by TAGE; deferred
    until after arb #73 and full BPU.

---

## Next Session (050)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-050.md (this file)
  CLAUDE.md

No direction is set for session-050; Jeff decides priority. The
candidates and their dependencies:

- bp_cluster integration. Unblocks the deferred rollback items
  (#69/#70) and the arbitration cluster (#73, and with it #37,
  #39, #40, #49, #52). Several BP Cluster TBDs (G20, G21, G22)
  must be resolved before this. The bp_cluster.md doc is LOCKED;
  bp_arb_spec.md is In progress.
- FTB, SC, RAS predictors. Not started. The next predictor units
  after TAGE/ITTAGE. SC sits at s3, FTB/RAS at s2 alongside
  TAGE/ITTAGE. Several G-TBDs (G5-G10, G14) are TBD at
  implementation.
- Carried infra / cleanup. #43 ITTAGE CTR 3b->2b (will churn
  CTR/aging tests written before it lands -- doing it before
  more ITTAGE test work avoids rework); #75 sim_ittage_fast;
  #77 path scrub; #67/#68 sram_init non-fast; #38 covergroup.

The TAGE and ITTAGE directed-validation sequences (BP-050b..055,
BP-056..061) are the established template for any further
unit-level directed validation.

