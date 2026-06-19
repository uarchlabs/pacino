<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
---
title: "TAGE -- Validation"
author: Jeff Nye
date: 2026-04-22
copyright: "Copyright 2026 Jeff Nye"
---

*This is part 7 of a series on branch predictor co-design.
[Part 1: Cluster Architecture](BLOG_bpu_1_cluster_arch.md) |
[Part 2: History and uBTB](BLOG_bpu_2_history_ubtb.md) |
[Part 3: Loop Predictor](BLOG_bpu_3_loop_pred.md) |
[Part 4: When the Tools Fail](BLOG_bpu_4_limits.md) |
[Part 5: TAGE -- Architecture and the Decomposition Problem](BLOG_bpu_5_tage_arch.md) |
[Part 6: TAGE -- Implementation](BLOG_bpu_6_tage_impl.md) |
[Part 7: TAGE -- Validation](BLOG_bpu_7_tage_validation.md)*

---

## Where Things Stood

The previous post ended with a working testbench
infrastructure -- reset, initialization, and SRAM
hierarchy verification -- but no branch prediction
behavior tested. The update path had not been exercised.
The provider selection logic, the useful bit mechanics,
the allocation scan, and the UAON threshold behavior were
all untested.

This post covers the sessions that built the TAGE
validation suite from that starting point: the open-loop
update and prediction tests, the round-trip tests that
exercised the full predict-update-re-predict cycle, the
RTL defects found along the way, and the cleanup pass
that normalized the codebase before integration. Five
sessions of dense testing work, four RTL defects found
and fixed, and a final test count of 46 passing cases.

---

## Open-Loop Testing: Update Path

The first testbench expansion session added update path
tests for slot 0. Seven tests covered the core update
mechanics: CTR write on correct prediction, CTR write
on misprediction, USE and EPC field update when using
the primary provider, allocation write to a tagged table,
the no-allocation sentinel (tage_alloc_comp == 0), CTR
saturation at the 3b maximum, and CTR saturation at the
3b minimum.

Two RTL defects were found during this expansion.

The first was in tage_table.sv. The use_we and epc_we
write enables for both slots were gating on prm_match
alone -- the condition that the primary table selector
matches this instance. Table 7 of the useful update
rules requires USE and EPC updates when either the
primary or the alternate provider is this table. The
correct gate is prm_match OR alt_match. A new signal,
prm_alt_match, was added for both slots and the gating
corrected. This was HAND-FIX-001.

The second was in tage_cntrl.sv. The tage_use_alt_on_na
field in the prediction metadata was being set from the
UAON trigger condition alone -- whether the provider CTR
was at a boundary state. The correct semantics require
both the trigger condition and the UAON counter having
reached the threshold (counter MSB set). A prediction
that triggers UAON but has not yet accumulated enough
evidence to cross the threshold should not set
tage_use_alt_on_na. This was HAND-FIX-002.

Seven additional tests were added to close coverage
gaps revealed by the initial update tests: USE and EPC
update when using_primary is false (Table 7 rows 5 and
6, which required HAND-FIX-001 to function), UAON
counter increment and decrement, CTR saturation at the
T0 2b boundaries, and the no-allocation path. A further
six tests covered the prediction path for slot 0: T0-only
prediction, single tagged table hit, dual hit with
provider selection, UAON override active, UAON override
suppressed by threshold, and tage_pred_rdy_p2 timing.

The prediction path tests surfaced a Verilator 5.020
constraint that had appeared in the update tests: blocking
assignments to struct-typed array elements in initial
block coroutines do not propagate through always_comb.
The staging always_ff pattern required for update inputs
also applies to prediction inputs. This was documented as
a universal rule in tage_tb_decisions.md.

Slot 1 symmetry was confirmed with two tests: one
prediction and one update. The primary goal was to
verify slot 1 elaboration, routing, and RAM independence
from slot 0, not to duplicate the full slot 0 coverage.
Both tests passed without finding new defects.

---

## Round-Trip Testing and Two More Defects

Round-trip tests exercise the full predict-update-re-predict
cycle. Each test pre-loads a RAM entry at a known address,
predicts, captures the tage_pred_meta_p2 output, feeds
it back as tage_upd_inp_u0 with a resolved outcome, then
predicts again at the same address to verify the table
state changed correctly.

Four round-trip tests were added covering correct-prediction
CTR update, misprediction CTR update with provider unchanged,
misprediction with allocation, and the no-consecutive-table
allocation constraint. All four passed -- but during review
of the captured prediction metadata, two additional RTL
defects were identified that had been masked by the meta
field overrides used in the initial round-trip implementation.

The first defect was in tage_cntrl.sv. The t_idx_r1 and
t_tag_r1 signals -- registered copies of the p0 index and
tag hashes used for provider selection and allocation at p1
-- were always zero. The hash outputs from tage_table and
tage_bim were not exposed as ports and consequently not
routed through tage.sv to tage_cntrl. Provider selection
was operating on zero indices and zero tags throughout all
prior testing.

The second defect was also in tage_cntrl.sv. The T0 CTR
extraction from cntrl_bits_p1 used the bit slice
[TAGE_T0_CTR_BITS-1:0]. T0 entry layout places VAL at
bit 0 and CTR at bits [TAGE_T0_CTR_BITS:1]. The extraction
was reading one bit too low, capturing the valid bit as
CTR[0] rather than the actual counter value.

Both defects were fixed in a single session. tage_table.sv
and tage_bim.sv each had idx_hash_p0 and tag_hash_p0 output
ports added. tage_cntrl.sv had corresponding input ports
added with a register stage, and the T0 CTR extraction was
corrected at two sites. tage.sv was updated with the
necessary interconnect wires. All 27 tests passed after
the fixes.

A cleanup session followed that removed 13 redundant meta
field override statements from the four round-trip tests.
These overrides had been written as workarounds for the
t_idx_r1/t_tag_r1 defect. With the defect corrected, the
tests could be expressed against actual RTL behavior without
overrides.

---

## The Full Validation Plan

With the round-trip infrastructure established and the
major RTL defects resolved, a full validation plan was
executed as a series of eight experiments covering all
known behavioral rules.

The CTR update truth table has 21 rows covering every
combination of provider type (T0 or tagged), using_primary
flag, correctness, and prediction difference. Four
experiments covered these systematically, including rows
that required the UAON mechanism to be active in order to
reach the using_primary=false cases. One discrepancy
emerged during this work: the provider labeling convention
in early prompts assumed T1 as the longer-history provider
when T1 and T2 both hit. The RTL scans ascending and
selects the highest-index hit, making T2 the primary.
This was a prompt authoring error, not an RTL defect. The
IA followed the RTL correctly; the subsequent prompts
used the correct labeling.

Table 7 of the useful update rules has six rows. The
remaining three -- correct prediction with pred_diff and
using_primary false, misprediction with using_primary
true decrementing the primary, and misprediction with
using_primary false decrementing the alternate -- were
each covered.

The UAON round-trip was covered in full: predict with
a weak provider CTR, update to accumulate counter, verify
the threshold crossing, re-predict and verify the mux
switched to alternate, then decrement below threshold
and verify restore.

Allocation was covered for the T0-provider misprediction
case (where the provider is the base table and allocation
proceeds into T1-T4) and for the no-consecutive-table
guard (where the selected allocation target Tj causes
Tj+1 to be skipped).

Aging round-trips were covered with aging enabled: an
entry with age count 1 was verified as a non-candidate
for useful update (u_eff computed as zero), while an
entry with age count 2 was verified as a candidate. The
EPC field write path was confirmed.

---

## One More RTL Defect: T0 CTR Direction

After the validation plan completed, a focused defect
was found during test result review. In tage_cntrl.sv,
the T0 CTR update direction select was using u_pred_crt
(whether the prediction was correct) rather than
u_resolved (the resolved branch direction). These are
different values. CTR update for a saturating counter
should move toward the resolved direction, not toward
correctness. A prediction can be correct and the counter
should still decrement if the resolved direction is not
taken. The fix was a single signal substitution and
required updating expected values in three tests where
the incorrect behavior had been the baseline.

---

## Cleanup Pass

With validation complete, a cleanup pass normalized the
codebase across five experiments.

The loop predictor naming inconsistencies (CLI items
001, 002, 004, 008, and 011) were resolved: lp_hit was
added to loop_pred_interfaces.md, bp_loop_meta_t had
lp_set renamed to lp_idx, and lp_pred_t and lp_upd_t
had twelve fields each retrofitted with the lp_ prefix
convention. The double-replacement artifact pattern --
where sequential string replacement on names sharing
substrings produces results like lp_lp_pred_is_loop --
was caught within the session and corrected.

The uBTB port naming retrofit (CLI-012) applied the
project convention to ubtb.sv: pred_pc became
pred_pc_p0, pred became pred_p1, and upd became upd_u0.

The parameter normalization pass (debt items 24 and 27)
eliminated a set of TAGE scalar parameters that had
become redundant once the TAGE_TBL_* vectors were
introduced. TAGE_T0_CTR_BITS, TAGE_CTR_BITS, and
TAGE_USEFUL_BITS were removed from bp_defines_pkg.sv.
Their consumers were updated to reference MAX_CTR_WIDTH,
MAX_USE_WIDTH, and TAGE_TBL_CTR[0] respectively. A
stop-and-report event fired when TAGE_TAG_BITS removal
was attempted: tage_hash.sv and tb_tage_hash.sv were
unexpected consumers. Since tage_hash.sv had been
abandoned after the hash migration, the correct response
was to defer TAGE_TAG_BITS removal to the session that
would formally delete those files. A follow-on experiment
completed that work.

---

## Experiment Summary

| Experiment | Description                               | Status | Checks | Runtime    | Context |
|------------|-------------------------------------------|--------|--------|------------|---------|
| BP-010c    | Update path tests slot 0 (7 tests)        | PASS   | 8/8    | 1h 12m 38s | 79%     |
| BP-010d    | Coverage gap tests slot 0 (7 tests)       | PASS   | 15/15  | 39m 10s    | 74%     |
| BP-010e    | Prediction path tests slot 0 (6 tests)    | PASS   | 21/21  | 33m 17s    | 80%     |
| BP-010f    | Slot 1 symmetry tests (2 tests)           | PASS   | 23/23  | 11m 0s     | 74%     |
| BP-011     | Round-trip tests (4 tests)                | PASS   | 27/27  | 48m 49s    | 45%     |
| BP-012     | RTL fixes: idx hash ports, T0 CTR extract | PASS   | 27/27  | 6m 9s      | 59%     |
| BP-013     | Cleanup: 13 redundant overrides removed   | PASS   | 27/27  | 5m 58s     | 42%     |
| BP-014a    | CTR rows 1/2, 3/4, 5/6, 7/8              | PASS   | 31/31  | 37m 53s    | 74%     |
| BP-014b    | CTR rows 9/10, 11/12 via UAON             | PASS   | 33/33  | 23m 8s     | 40%     |
| BP-014c    | CTR rows 13b, 13c                         | PASS   | 35/35  | 11m 0s     | 81%     |
| BP-014d    | CTR rows 13a, 13d                         | PASS   | 37/37  | 13m 52s    | 48%     |
| BP-014e    | CTR rows 14/15, 16/17 + Table 7           | PASS   | 39/39  | 10m 58s    | 74%     |
| BP-014f    | UAON threshold cross, dec restore         | PASS   | 41/41  | 37m 29s    | 23%     |
| BP-014g    | Allocation: T0 provider, no-consecutive   | PASS   | 43/43  | 15m 49s    | 78%     |
| BP-014h    | Aging: age=1 not candidate, age=2 is      | PASS   | 45/45  | 27m 46s    | 60%     |
| BP-015     | T0 CTR direction fix (debt #34)           | PASS   | 45/45  | 7m 42s     | 41%     |
| BP-016     | T0 DEC saturation test (TC-46)            | PASS   | 46/46  | 6m 46s     | 46%     |
| BP-017a    | CLI-001, CLI-002, CLI-004: loop pred      | PASS   | --     | 2m 22s     | 21%     |
| BP-017b    | CLI-008, CLI-011: loop pred field names   | PASS   | 13/13  | 11m 7s     | 55%     |
| BP-018     | CLI-012: ubtb.sv port naming              | PASS   | 10/10  | 2m 26s     | 24%     |
| BP-019     | Debt #27, #24 partial: param cleanup      | PASS   | 46/46  | 5m 56s     | 52%     |
| BP-019a    | Debt #24 complete: TAGE_TAG_BITS removed  | PASS   | 46/46  | 5m 19s     | 36%     |

---

## What Comes Next

With 46 passing tests and the codebase normalized, the
TAGE predictor is validated against its full behavioral
specification. Three items remain open before bp_cluster
integration: the TI7 migration of bp_tage_meta_t to
tage_pred_meta_t, debt #33 (the simultaneous prediction
and update protocol), and a test count validation script.

The next sessions begin the TAGE arbitration
implementation -- the mechanism by which the TAGE
predictor participates in the bp_cluster update
arbitration when both prediction slots resolve in the
same cycle.

---

## Design Process Notes

### What the sessions exposed about the methodology

The defect cadence across these sessions is worth
examining. Four RTL defects were found: HAND-FIX-001
(tage_table use_we gating), HAND-FIX-002 (tage_cntrl
UAON flag semantics), the t_idx_r1/t_tag_r1 always-zero
defect, and the T0 CTR direction defect. All four were
found by the testbench, not by code review. Three of
the four were in tage_cntrl.sv, the module with the
most complex control logic and the module that had no
testbench during implementation.

The t_idx_r1/t_tag_r1 defect is the most instructive.
The signals were declared in BP-008a-2 to receive hash
data from tage_table, but the ports that would supply
that data were not added until BP-012, after the defect
was found in round-trip testing. The defect existed
through the entire implementation phase -- BP-008b,
BP-009, BP-010a, all of it -- because there was no
testbench for tage_cntrl during that phase and because
provider selection producing zeros is not visually
distinguishable from correct behavior at the lint-only
level.

The practical implication is that lint-clean and
compile-clean are necessary but not sufficient for
modules with non-trivial control logic. The
compile-only strategy used during implementation was
correct for containing generation costs, but it
created a debt that was eventually paid in the
round-trip testing phase.

### What the PA contributed

The PA designed the test sequences for BP-010c through
BP-014h, authored all prompts, identified the HAND-FIX
defects during review of test outputs, and wrote the
cleanup prompts for BP-015 through BP-019a. The provider
labeling clarification (primary is the longest-history
hit, not T1) was a PA correction to its own earlier
prompt authoring.

### What the IA contributed

The IA implemented all testbench additions across the
18 experiments in this post, each producing correct
test scaffolding against the planning documents. It
caught the double-replacement artifact in the CLI-011
cleanup session without prompting. The BP-012 RTL fixes
-- adding output ports to two modules, adding input
ports and a register stage to tage_cntrl, and updating
tage.sv interconnect -- were implemented correctly on
the first attempt.

### The generalization

The round-trip test design pattern established here --
pre-load, predict, capture meta, update with captured
meta unmodified, re-predict, verify -- is the correct
way to test a predictor whose update path is driven
entirely by metadata captured at predict time. The
pattern is reusable for ITTAGE and SC with only the
metadata struct changing. The investment in getting
tb_tage.sv right, including the staging always_ff
requirement and the hierarchical RAM access paths, is
an asset that carries directly into the remaining
predictor validation sessions.

---

*No references required for this post.*

