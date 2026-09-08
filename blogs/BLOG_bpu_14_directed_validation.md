<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>  -->

```
TITLE:     "Directed Validation: Proving the Test Before Trusting the Result"
FILE:      BLOG_bpu_14_directed_validation.md
AUTHOR:    Jeff Nye
DATE:      2026-09-04
STATUS:    REVIEW BEFORE POSTING
COPYRIGHT: "Copyright 2026 Jeff Nye"
```

<!--
---

::SERIES DESCRIPTION::
::BEGIN LINKS::
::END LINKS::
-->

# Directed Validation: Proving the Test Before Trusting the Result

## Abstract

A TAGE or ITTAGE table entry holds a counter (CTR), a usefulness field
(USE), an epoch field (EPC), and, in ITTAGE, an indirect branch target
(TGT). An update writes these fields individually; an allocation writes
a whole entry. Which write happens under which condition is set out in
the update rules documents, one row per condition, and those documents
are the authority the RTL is checked against.

Three RVA23 Co-Design sessions ran twenty-one tasks to finish unit-level
verification of the TAGE and ITTAGE branch predictors of Pacino, an
8-issue RVA23 RISC-V design, by working through those rules row by row.
Each test seeds an entry directly into table memory, drives the update
the row describes, then reads the entry back out of RAM to confirm the
field changed as the row requires. Of the sixteen verification tasks,
eleven found the design already conforming on every row they checked,
three fixed RTL defects, one found a defect and argued it away, and one
was abandoned. A fourth defect was fixed by the repair task that
adjudicated the counter direction; two of the four are the same defect
appearing independently in both predictors.

Four kinds of failure ran through the sessions, and they are the more
instructive result. Counts were carried forward that no run in the
session had produced. One task concluded that the counter write strobes
were swapped in the RTL without opening the update rules document that
would have settled it; the RTL conformed on all 33 rows and the swap was
in five test cases, so acting on that conclusion would have broken
working logic. One found a defect and argued it was harmless. It marked
itself complete without testing that argument; the defect was real and
corrupted the higher-priority table. One offered a passing test as proof
when the test had never been run against a design that could make it
fail; that task was abandoned.

The last of the four produced the requirement that governs the rest of
this work: every check must demonstrate it can fail, whether by running
against an unfixed design, by introducing a defect and reverting it, or
by seeding stimulus that makes a wrong answer visible. Fifteen technical
debt items closed, and both predictors are now directed-validated at the
unit level.

## What had not been tested

Before these sessions, the TAGE and ITTAGE update paths had been fixed
where they were known to be broken and left alone where they were not.
The counter and usefulness write paths had been proven by RAM readback.
The epoch, target, allocation, aging and prediction-side paths had not.
Some had never been driven at all: aging ran with `tage_enable_aging`
and `ittage_enable_aging` held at zero in every test written to that
point, so the entire epoch mechanism was dark. Every remaining untested
path was enumerated as technical debt items #55 through #74.

Two rules governed how that work would be done. The first was isolation
before round-trip: prove each field alone, then mix. The second was the
backdoor RAM write, a testbench task that seeds a complete entry
directly into a table's memory using hierarchical paths to the RAM
entry.

Both rules were inherited. These sessions added a third, that every
check must demonstrate it can fail. The requirement was written after
BP-050 was abandoned for arguing its test would have caught a defect
without ever showing that it did.

## Structural rework, and what it exposed

The redundant bus dimensioning was not found in this work. It was
recorded in session-040 as TD #45, an update-index simplification, and
the description was wrong: it asked for per-table ports when the
per-table dimension was the defect. session-046 marked the entry wrong
in `CLOSED_TECH_DEBT.md` and moved the real fix to TD #66. BP-045 was
the first task to work it, seven sessions after it was first recorded.

The TAGE controller drove ten separate update and allocation buses
dimensioned `[table][slot]`, one slice per table. Only one table per
slot is the provider or the allocation target on any update, so every
update drove one meaningful slice and `TAGE_NUM_TABLES-1` unused ones.
BP-045 collapsed them to `[slot]`, with the target table identified by
the `*_tbl_sel_u0` selects that already existed. The per-table strobe
assignments stayed in the existing `gen_tbl` generate loop; the
collapsed data, selector and address buses moved to a new `gen_upd_bus`
block keyed on slot alone. `tage_table.sv` needed no change. Its input
ports were already dimensioned by slot, and only the interconnect above
the module had the redundant dimension.

One of the ten could not collapse. The primary and alternate CTR writes
can both assert in the same cycle, to different tables, at different
history lengths, and therefore at different hashed indices. A single
shared index bus carries one value per slot. `t_alt_upd_index_u0` was
added alongside the primary update index. That gives three index buses:
primary update, alternate update, and allocation. None of this was in
the prompt, which assumed a single shared index. The implementation
assistant derived the requirement from the CTR update rules and reported
it as a deviation. Three index buses are the correct structure, and the
deviation was accepted on that basis. It also exposed that ITTAGE had
the same requirement and lacked the same bus. That became TD #66's
counterpart, TD #76, closed across BP-046 and BP-048.

BP-046 mirrored the change into ITTAGE and renamed twenty-two
`ittage_cntrl` ports that cross the table boundary to the `t_`
convention. Renaming ports broke `tb_ittage_cntrl.sv` compilation, and
the task edited that file to keep the count stable even though it was
not in the manifest. The edit was mechanical and was reported under the
stop-and-report policy. The prompt-writing rule that followed is that a
task which renames a module's ports lists every instantiating testbench
in its manifest from the start.

The regression counts that BP-045 and BP-046 ran to confirm no
behavioral change reported something else. `sim_ittage_cntrl` returned
32 passing and 44 failing. `sim_ittage_table` returned 30 and 2,
forty-six failures in total. Neither figure had appeared in any status
file. `tb_ittage_cntrl.sv` had been authored green at 76 checks several
sessions earlier; the ITTAGE RTL had changed underneath it repeatedly
since, and that suite had not been run again. The proven-by-readback
claims from the intervening work were true, but they were made against
directed rows in `tb_ittage`, not against the controller suite.
`PROJECT_STATUS.md` carried the stale 76 throughout.

## Classification is not adjudication

BP-047 ran triage and fixed nothing. It classified all 46 failures into
two root-cause groups.

Of the 46, 32 were stale testbench scaffolding. Thirty of those traced
to one defect in the `pred_s0` task: it drove `tbl_hit_p1`,
`tbl_cntrl_bits_p1` and `tbl_pred_tgt_p1` before the p0-to-p1 posedge
and cleared them one time unit after it. The `prv_alt_scan` block in
`ittage_cntrl.sv` is classified `nba_sequent` because it reads a flop
output, as required. After `pred_val_p1` captures, the block evaluates
against the correct values, then re-evaluates against the cleared inputs
and produces zeros. Every failing check in TC-PRED-02 through TC-PRED-06
returned an actual value of zero regardless of stimulus, and TC-PRED-01,
which expects all zeros, passed trivially. The other two stale failures
were the `sim_ittage_table` pair, a co-assertion requirement the test
violated.

The remaining 14 were classified as an RTL counter routing inversion in
`ittage_cntrl.sv`. The reasoning was that USE and EPC pass under the
same `using_primary` signal, which isolates the fault to the CTR branch
assignments.

That classification was diagnosed entirely against what the testbench
expected. TC-UPD-01 through TC-UPD-05 asserted that `using_primary=1`
should fire `alt_ctr_wr`, and the RTL fired `prm_ctr_wr`. Treating the
test as the reference makes the RTL wrong. Standard TAGE and ITTAGE
train the provider's counter toward the resolved outcome, which is the
opposite of what the tests expected. The repair task was therefore
required to load `ittage_cntrl_ctr_update_rules.md` and settle the
direction against the rules table before changing any code, with the
swap pre-authorized only if the document agreed with the test.

It did not. BP-048 read the 33-row table and found row 1 is the no-hit
case with no write, rows 2 through 17 govern the UP=0 regime with
`alt_ctr_wr` as the governing strobe, and rows 18 through 33 govern UP=1
with `prm_ctr_wr`. The RTL matched the document on every row. All five
test cases had the strobes transposed. Only the tests were repaired;
`g_ctr_upd` was not modified. Had the RTL swap been pre-authorized on
the strength of the classification, a conforming block would have been
broken and the suite would have gone green over it.

BP-048 also fixed a real RTL defect in the same task. `t_alc_index_u0`
was driven from the primary update index. The correct source is the
allocation index field carried in the prediction metadata. No existing
test could see it, because the test fixture happened to make `alc_idx`
equal `prm_idx`. TC-UPD-06 was modified so the two differ. The modified
test failed before the fix and passed after, and the defect was
corrected against `ittage_cntrl_alloc_rules.md`.

One item did not resolve. On TC-UPD-05 the task found two authority
documents in conflict: rows 22 through 29 of the CTR rules table imply
the primary strobe fires on a null counter under misprediction with the
data saturating at zero, while `ittage_cntrl_decisions.md` stated there
is no counter write in that case. The task chose the rules table, called
the decisions note subordinate implementation guidance, and updated the
test to match the RTL. Test and RTL then agreed, and the suite was
green. Agreement between two artifacts is not evidence when the
authority governing both is the thing in dispute. The resolution was a
specification change rather than a code change:
`ittage_cntrl_decisions.md` gained a "Concurrent CTR and TGT Writes"
section relaxing the mutual-exclusivity claim, on the grounds that
writing zero to a counter already at zero has no effect.

## A defect reported and argued away

TD #57 covered the ITTAGE target write path, which had never been
audited. BP-049 verified that the target is written when the provider's
counter is zero on misprediction and added four directed tests covering
both provider regimes. The suite went from 81 to 105 checks with no
failures. It marked itself complete and reported TD #57 closed.

In its own notes it recorded that the per-table target write enable in
`ittage_table.sv` gated on `(prm_match | alt_match)`, so a target write
reached every hitting table. Only the provider should have been written.
It classified this as existing behavior not prohibited by the
specification, and stated that the incidental update had no observable
effect on correctness.

Both statements were wrong. The interfaces document specifies that only
the component that provided the prediction has its target field
modified; absence of an explicit prohibition is not authorization. The
effect is also observable. In the UP=0 case the non-provider is the
primary table, which has the longer history and the higher priority. Its
target field is overwritten with a value resolved under a different
history length. On the next prediction at that address the primary hits
and is selected as provider ahead of the alternate. The corrupted entry
is the one consulted first.

The tests could not have caught it. Each read back only the entry it
expected to change. A test that verifies a write landed says nothing
about whether a second write landed somewhere it should not have. The
same blind spot had produced the `alc_index` defect one task earlier.

BP-049a ran with `ittage_interfaces.md` in the manifest, where the
provider-only invariant is stated explicitly, and the defect was fixed.
The single `t_tgt_wr_u0` strobe was split into `t_prm_tgt_wr_u0`,
asserted only for UP=1 with the primary counter at zero, and
`t_alt_tgt_wr_u0`, asserted only for UP=0 with the alternate counter at
zero. The table's target write enable became `prm_tgt_wr & prm_match |
alt_tgt_wr & alt_match`, mutually exclusive by construction, with the
non-provider gating to zero in both regimes. The tests were extended to
read back the non-provider entry and assert it unchanged. Both extended
checks failed before the fix and passed after, with the failing values
showing the exact corruption: expected `c000`, actual `e000`, and
expected `c000`, actual `b000`.

An earlier attempt in the same task passed `using_primary` into the
table and gated there. It was backed out after Verilator scheduling on
partial-bit generate assignments produced incorrect results. The
split-strobe form reuses the per-slot strobe pattern already proven for
the counter writes.

## Showing that a check can fail

BP-050 took up the ITTAGE epoch write. It found the write enable
provider-only, added tests that read back both the provider and the
non-provider entry, and passed. It was abandoned.

The gate was correct and the finding was right, but the task never
demonstrated that its non-provider check could fail. It argued that a
`(prm_match | alt_match)` defect would make the check trip. It did not
run the test against a defective design to find out. A test that has
only ever been run against conforming RTL is indistinguishable from a
test that cannot fail, and BP-049 had just shown what that costs.

BP-050b redid the work with the missing step. The epoch write enable was
established as provider-only by construction: it rides the mutually
exclusive primary and alternate counter strobes, and the epoch write
condition is a strict subset of the counter write condition, so no path
writes the epoch field without also writing the counter. No RTL change
was required. Then the gate was deliberately corrupted to `(prm_match |
alt_match)`, both non-provider checks failed with an expected value of 2
against an actual of 0, and the gate was reverted.

Demonstrating that a check can fail became a required step in every
verification task that followed, and it took three forms.

Where a defect was fixed, the test ran against the unfixed design first.
BP-049a extended its tests to read back the non-provider entry and
recorded an expected `c000` against an actual `e000` before the target
write was corrected. BP-051 added the missing guard on `use_alt_on_na`
(UAON, use alternate on newly allocated, a saturating counter with a
threshold of 8), removed it again to watch TC-UAON-08 return an expected
8 against an actual 9, and restored it.

Where the design already conformed there was no defect to run against,
so one was introduced on purpose. BP-050b widened the epoch gate to
`(prm_match | alt_match)`, watched both non-provider checks fail with an
expected 2 against an actual 0, and reverted. BP-056 reverted a TAGE
epoch gate to `prm_match` alone, watched two tests fail with the epoch
field unwritten, and restored it. BP-057 removed the guard it had just
added and watched the counter move. Breaking the design and putting it
back leaves no net RTL change, which is why a task reports both an
injection and a design it did not modify.

Where neither applied, the discrimination came from the stimulus. BP-052
seeded a pre-state of USE=2'b10 so an aging-disabled result could not be
mistaken for an age-1 result. BP-058 seeded USE=2'b10 in TC-87 for the
same reason. BP-060 seeded the provider counter at 3'b111 and again at
the weak-band boundary 3'b100, so `pred_strong` had to change between
the two for the test to pass.

What each task delivers is a test that has been seen to fail for the
defect it exists to catch.

BP-050 produced one more finding. At session start `tb_ittage_cntrl.sv`
and `tb_ittage_table.sv` did not compile at all. BP-049a had renamed
`t_tgt_wr_u0` across `ittage_cntrl.sv` and `ittage_table.sv` and had run
only `sim_ittage`. The 77 and 32 passing counts recorded as current
truth in the session handoff were false from the moment of the rename.
BP-050a enumerated all twenty targets, repaired both testbenches with no
RTL change, and the escape was recorded as BUG-002. BP-050's own claim
to have repaired them did not hold either, which is how the same class
of error appeared twice one task apart.

The rule that came out of this is that every simulation and lint target
in the Makefile runs, whether or not it is a dependency of `all`, and
that status counts come from a run in the current session. Its cost is
measurable. BP-054a ran for three and a half minutes and consumed 72% of
context, almost entirely from twenty targets' console output. Compaction
occurred in all seven tasks of the final session. A phased application
of the rule, so that early tasks in a sequence run fewer targets, is the
planned revision.

## Completing ITTAGE

With the epoch write proven, the remaining ITTAGE items ran in
dependency order. Aging reads the epoch field, so the epoch write is
proven first.

BP-051 found the second real RTL defect. The UAON update block was
missing its single-hit guard: with either component count at zero the
counter should hold, and without the guard a single-hit transaction with
a stale alternate target defaulting to zero could move it on a
comparison carrying no training signal. The guard was added and proven
by removal, TC-UAON-08 failing with an expected 8 against an actual 9.
The fix invalidated a test elsewhere. `tc_tgt_b_ext` in `tb_ittage` had
encoded its UAON decrement step around the missing guard. Its single-hit
scenario produced a decrement only because the guard was absent. It was
rewritten as a two-hit setup.

BP-052 proved the aging and epoch path, dark until this point. All seven
rules conformed. The task found that the epoch advances one tick after
the interval reaches zero, and wrote its tests to match the RTL while
noting the document did not specify the boundary. That is the same
resolution BP-047 made toward the testbench, resolving toward the
artifact in front of it, and here it was left standing with no
documented rule behind the test. The correction came six tasks later at
BP-058, the TAGE aging task, which was told not to assume the timing and
proved it explicitly at the boundary posedge. The N+1 rule was then
written into `tage_cntrl_use_update_rules.md`. The ITTAGE document still
carries the gap.

BP-053 proved the thirteen allocation rules with no RTL change and found
a specification error. The write-data field order in the allocation
rules document did not match the structural entry layout, with the
target and epoch fields transposed. Rather than correct one document,
the field order was extracted into `ittage_table_entry_formats.md` and
`tage_table_entry_formats.md` as the single source, referenced from the
interface documents. The task also carried more planning documents in
its manifest than it read, and after a request timeout it was rerun with
three of them removed. From that point a manifest listed only the
reference documents, the RTL under test, the packages needed to compile,
the testbench and the Makefile.

BP-054 proved the twelve prediction-path rules and found two further
specification errors. Both were carried across from TAGE.
`ittage_pred_strong` was documented as the provider counter differing
from 3 and from 4, which is the TAGE weak-band definition for a
direction counter. ITTAGE's counter is a confidence counter and the
correct condition is non-zero. Separately, the final-target section
referred to a single stored `ittage_pred_tgt` field. It was rewritten so
the consumer selects between the primary and alternate targets using
`ittage_using_primary`, which avoids storing a third 35- to 40-bit
target. BP-054a confirmed the corrected document against the RTL and
testbench with no code change.

BP-055 ran the ITTAGE round-trip capstone across counter, usefulness,
allocation, epoch and target writes in one flow. Its first failure was
again in the test, not the RTL. IT3 was seeded with an epoch value of 3
against a local epoch of 0. That gives an age of 1 and an effective
usefulness of `USE>>1`, which is zero. The usefulness increment then
wrote 1 over a seed of 1 and produced no visible change. Three
expectations were corrected. The rule recorded from it is that when a
usefulness delta must be observable, the epoch field is seeded equal to
the local epoch so the effective and raw values agree.

## TAGE, the same sequence

The ITTAGE sequence became the template for TAGE, and the outcomes
mirrored it closely enough to be useful as a comparison.

BP-056 proved the TAGE epoch write. The gate had been changed in an
earlier hand fix to `prm_match | alt_match` and never proven. The local
epoch was forced to `2'b10` against a seeded epoch of `2'b00` so the
write landed a visible change; a same-value write would have proved
nothing. Injection reverted the gate to `prm_match` alone and the two
alternate-match tests returned with the epoch field unwritten. The TAGE
epoch write rides the usefulness write enable, not the counter subset
relation that ITTAGE uses; the two predictors reach the same invariant
by different structures.

BP-057 found the fourth defect, and it is the ITTAGE defect from BP-051
in the other predictor. The `uaon_upd_ff` gate was missing `&&
u_alt_tagged[s]`. When the provider hit a tagged table and the alternate
fell through to the untagged base table T0, the counter moved on a
comparison with no tag behind it. The two-line guard was added and
recorded as BUG-003; TC-81 failed before and passed after. The TAGE
manifestation is narrower. The ITTAGE defect needed only a single hit;
the TAGE one needs a tagged provider with an untagged alternate.

BP-058 proved the aging path with no RTL change. It confirmed `age =
(lcl_epoch - EPC) mod 4`, and an effective usefulness of the raw value
at age 0, a right shift at age 1, and zero at age 2 or greater. One test
seeds usefulness at `2'b11` so the four ages produce `11`, `01`, `00`
and `00`, which distinguishes a wrong age from a right one. Another
proves the behavioral consequence instead of the counter value. A fresh
entry is not an allocation candidate; the same entry aged to an
effective usefulness of zero is. Unlike the ITTAGE interval, the TAGE
aging interval is a 32-bit input port, not a static parameter, so the
boundary is always reachable and there is no risk of a mechanism
untestable at current parameters.

BP-059 proved allocation and folded RAM-level write isolation into the
same task, which the capstone would otherwise have had to carry. The
task already ran at `sim_tage` with the tables present. The selected
table is read back changed and a non-selected table seeded to a distinct
value is read back unchanged. This is the check the ITTAGE allocation
task could not reach, having run controller-only. The write-data field
order was cross-checked against the entry-format document and matched,
so the transposition found in ITTAGE has no TAGE counterpart.

The task also corrected the prompt rather than the design. The
requirement asked for a no-consecutive-skip test, a description carried
over from the ITTAGE allocation work. The TAGE guard is `alc_comp_p1[s]
== 0`, which stops the scan at the first candidate. A
no-consecutive-skip guard would carry on past a selected table. The two
policies differ only when two allocatable candidates are adjacent, which
the seeded stimulus did not produce, so the test proves first-match
selection and the label was corrected to match.

BP-060 proved the prediction path with no RTL change. The `pred_strong`
definition was the specific item under watch, given the carryover error
found in the ITTAGE document. The TAGE document states the provider
counter differs from 3 and from 4, the RTL implements `(ctr != 3'b011)
&& (ctr != 3'b100)`, and they agree. The carryover ran one direction
only.

BP-061 came last, the TAGE round-trip capstone. Entries were placed to
collide at a single RAM address, with T1 through T4 all mapping to index
512, which is the arrangement most likely to expose a cross-path write.
Aging was disabled and the epoch seeded equal to the local epoch so
usefulness deltas stayed visible. That is the BP-055 lesson applied
directly. The interference checks confirm that a counter and epoch write
survive a usefulness write to a different table, and that an allocation
disturbs neither the provider entry nor a fourth-table reference held
constant through all four steps. One field is not discriminating: with
the epoch equal to the local epoch throughout, the epoch writes are zero
over zero, so a stuck value would pass. Epoch landing is proven
separately with a real delta and an injection, and the capstone's
purpose is interference.

## Counts as evidence

Four times a status count was carried forward that no run had produced.

The controller suite carried 76 passing through several sessions of RTL
churn without being re-run. BP-049a's rename left two testbenches
uncompilable while their previous counts were recorded as current.
BP-050 reported an all-targets pass of 123, 77 and 32 that BP-050a could
not reproduce, because the repair it claimed had not held. And the TAGE
arithmetic did not close across three consecutive tasks: one task
reported 69, the next added five test cases and reported 73, which
resolves only if the prior baseline was 68; the task after that reported
a pass with no integer at all, which does not satisfy a rule requiring a
count from the current session. The ledger closed once an integer was
produced again, at which point the whole chain of 73, 81, 87, 95, 102
and 103 reconciled end to end.

The pattern is the same as the one the injection step addresses. A count
and a passing test are both assertions about a system's state, and both
are worth exactly as much as the run that produced them.

## Experiment summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| BP-045 | TAGE update/alloc buses collapsed to per-slot form, third index bus added (#66) | PASS | 68/68 | 17m 54s | 82% |
| BP-046 | ITTAGE alternate index bus added, table-facing ports renamed to t_ (#76) | PASS | counts held 32/44, 30/2, 81/0 | 17m 15s | 83% |
| BP-047 | ITTAGE escape triage, 46 failures classified into two root-cause groups | TRIAGE ONLY | 46 classified, 0 fixed | 11m 52s | 60% |
| BP-048 | CTR direction adjudicated against rules table: test transposed, RTL conforming; alc_index defect fixed | PASS | cntrl 77/0, table 32/0 | 11m 9s | 58% |
| BP-049 | ITTAGE target write verification (#57): non-provider write reported and rationalized, marked complete in error | PARTIAL | 105/0 | 16m 55s | 82% |
| BP-049a | Target write strobe split, provider-only invariant proven by non-provider readback (#57) | PASS | 113/0 | 1h 1m 34s | 60% + compaction |
| BP-050 | ITTAGE EPC write, first attempt: discriminating power argued but never demonstrated | ABANDONED | -- | 17m 3s | 20% + compaction |
| BP-050a | All Makefile targets enumerated and run; BP-049a port-rename escape found and repaired (BUG-002) | PASS | 20/20 targets | 8m 54s | 57% |
| BP-050b | ITTAGE EPC write proof with defect injection and revert (#56) | PASS | sim_ittage 125/0 | 24m 20s | 47% |
| BP-051 | ITTAGE UAON single-hit guard: real RTL defect found and fixed (#59) | PASS | cntrl 92/0, ittage 125/0 | 35m 7s | 53% |
| BP-052 | ITTAGE aging / epoch path, previously dark (#61) | PASS | cntrl 112/0 | 22m 34s | 30% |
| BP-053 | ITTAGE allocation policy and gating; entry-format documents created (#63) | PASS | cntrl 147/0 | 30m 45s | 57% + compaction |
| BP-054 | ITTAGE prediction-side correctness; two document errors corrected (#65) | PASS | sim_ittage 164/0 | 28m 7s | 57% |
| BP-054a | Corrected decisions document verified against RTL and testbench (#65) | PASS | 20/20 targets | 3m 32s | 72% |
| BP-055 | ITTAGE round-trip capstone across CTR, USE, alloc, EPC, TGT (#72) | PASS | 211/0, 20 targets | 1h 12m 54s | 58% + compaction |
| BP-056 | TAGE EPC write proof with defect injection and revert (#55) | PASS | sim_tage 73/0 | 46m 6s | 24% + compaction |
| BP-057 | TAGE UAON single-hit guard: real RTL defect found and fixed, BUG-003 (#58) | PASS | sim_tage 81/0 | 36m 33s | 66% + compaction |
| BP-058 | TAGE aging / epoch path, previously dark (#60) | PASS | sim_tage 87/0 | 26m 41s | 48% + compaction |
| BP-059 | TAGE allocation with RAM-level write isolation folded in (#62) | PASS | sim_tage 95/0 | 29m 28s | 51% + compaction |
| BP-060 | TAGE prediction-side correctness (#64) | PASS | sim_tage 102/0 | 20m 45s | 25% + compaction |
| BP-061 | TAGE round-trip capstone across CTR, USE, alloc, EPC (#71) | PASS | sim_tage 103/0 | 29m 5s | 50% + compaction |

Status is the outcome of the task as specified, not a test result.
BP-046 is a PASS that reports 44 failures: it completed its structural
change and confirmed the counts were unchanged by it. Those failures
were pre-existing and, until that run, unreported.

## What comes next

Both predictors are now directed-validated at the unit level. The
remaining items are deferred, not unresolved. They are the `sram_init`
non-fast path for both units; rollback and history recompute, which move
to cluster integration; the dual-slot configuration; the ITTAGE counter
width reduction from three bits to two; and a missing fast-init
simulation target. The counter width reduction will churn any counter
and aging tests written before it lands, which argues for doing it
before any further ITTAGE test work.

The arbitration and cluster items are gated on `bp_cluster` integration,
which has open design questions of its own. The next predictor units
(FTB, SC and RAS) are not started. The directed-validation sequence used
here is the template for them.

## Technical debt referenced

The table below reports status as of the close of session-049, the last
session covered by this post. Sessions after 049 have changed the state
of some items carried alongside these.

| # | Item | Resolution path |
|---|---|---|
| 55 | tage EPC write proof. Changed RTL, never proven by readback. | CLOSED BP-056. epc_we gate changed as a USE rider in earlier work. Seed entry, drive EPC-writing update, read EPC back via prediction, confirm landing. |
| 56 | ittage EPC write proof. Changed RTL, never proven by readback. | CLOSED BP-050b. epc_we_s0/s1 fixed alongside use_we with no positive test. Readback-verify per provider, UP=1 and UP=0. |
| 57 | ittage TGT target replacement. Untested. Successor to #51. | CLOSED BP-049a. Suspect for the same provider-gating defect as CTR and USE. Target written on mispredict when CTR null only. Trace path, readback-verify reachable rows. ITTAGE only; TAGE has no target field. |
| 58 | tage UAON trigger rules. Tested only as setup, never as DUT. | CLOSED BP-057. tage_cntrl_uaon_update_rules.md promoted from Draft to authority, directed test per row, use_alt_on_na asserted and cleared per rule. BUG-003 found and fixed. |
| 59 | ittage UAON trigger rules. Tested only as setup, never as DUT. | CLOSED BP-051. ittage_cntrl_uaon_update_rules.md promoted from Draft. USE tests had relied on UAON asserting as a precondition without it ever being verified. |
| 60 | tage aging / epoch path. Entire path dark. | CLOSED BP-058. Supersedes #41. All prior tests ran with tage_enable_aging=0. Drive aging enabled, exercise EPC-versus-epoch compare and USE decrement over the interval. |
| 61 | ittage aging / epoch path. Entire path dark. | CLOSED BP-052. Same as #60 for ITTAGE. Consumes the EPC field whose write changed in earlier work; see #56. |
| 62 | tage allocation policy + write gating. Never the feature under test. Successor to #51. | CLOSED BP-059. Allocation had been treated as residue to invalidate, never verified. Which table allocates, write-enable gating, allocation index. RAM-level write isolation verified. |
| 63 | ittage allocation policy + gating. Never the feature under test. Successor to #51. | CLOSED BP-053. Same as #62. Allocation on mispredict, CTR-null condition, alloc_we gating, allocated entry state read back. |
| 64 | tage prediction-side correctness. Not directed-tested. | CLOSED BP-060. Prediction path had been exercised only as setup for update tests. Directed-test provider selection, using_primary, pred_strong and the target mux against seeded entries. |
| 65 | ittage prediction-side correctness. Not directed-tested. | CLOSED BP-054 and BP-054a. Same as #64 for ITTAGE. Resolves the #42 test aspect: provider, using_primary and target operate at s2, not s3. |
| 66 | TAGE structural rework. Per-table 2D update and allocation buses where shared per-slot buses are correct. Sequence before TAGE allocation #62. | CLOSED BP-045. Collapsed to shared per-slot buses routed by the existing selects; t_alt_upd_index_u0 added for the concurrent primary and alternate CTR write case. |
| 71 | tage round-trip. Combined test, run only after individual tests pass. | CLOSED BP-061. Mixed CTR, USE, allocation and EPC in one flow. Run only after #55, #58, #60, #62 and #64 were each proven alone; mixing before isolation reproduces multi-cause ambiguity. |
| 72 | ittage round-trip capstone. Combined test, run only after individual tests pass. | CLOSED BP-055. Mixed CTR, USE, allocation, EPC and TGT in one flow, after #56, #57, #59, #61, #63 and #65. Allocation RAM-level write isolation verified. |
| 76 | ittage should have independent index buses for primary and alternate table updates. | CLOSED across BP-046 and BP-048. History lengths differ and indices are hashed per length, so primary and alternate updates require separate buses. The t_alc_index_u0 source defect was the remainder, closed in BP-048. |

## Design process notes

### What the implementation assistant contributed

The implementation assistant produced every directed test in these
sessions, approximately 120 test cases across the two predictors, each
citing the specification row it exercises. It root-caused four RTL
defects to file and line and fixed them in the same session, and it
produced the diagnostic reasoning behind the largest failure group in
BP-047, the `nba_sequent` re-evaluation against cleared inputs, which
required tracing Verilator's block-classification behaviour, not just
re-running a failing comparison.

Three of the specification errors were found by the implementation
assistant reporting a discrepancy it was not asked to look for: the
allocation write-data field order, the `pred_strong` carryover, and the
stored final-target field. In BP-045 it went further and contradicted
the task: it derived the three-index bus requirement from the CTR update
rules and reported the prompt's single-index assumption as wrong. It
also backed out its own first approach in BP-049a after Verilator
scheduling on partial-bit generate assignments gave incorrect results,
and documented why.

It failed the same way every time. Where the task allowed judgment about
what a finding meant, it resolved toward the artifact in front of it:
BP-047 treated the testbench as the reference for the counter direction,
BP-049 treated the absence of an explicit prohibition as authorization,
BP-050 argued a check's discriminating power instead of demonstrating
it, and BP-052 wrote tests to match RTL behavior the document did not
specify. In each case the reasoning is defensible in isolation and wrong
against the specification. The pattern is not carelessness in execution;
it is the absence of the authority document at the moment the judgment
was made.

### What the planning assistant contributed

The planning assistant scoped and sequenced all twenty-one tasks,
including the dependency order that put every epoch write proof before
its corresponding aging proof, and the isolation-before-round-trip
ordering that held both capstones until every path was proven alone.

Its most consequential contribution was the guard on BP-048. Presented
with a classification that placed the swapped strobes in the RTL, it
identified that the diagnosis rested entirely on the testbench being
correct, and required the repair task to settle the direction against
the rules table before changing code, with the swap pre-authorized only
on the document's agreement. The document disagreed and a conforming
block was left alone.

It also caught the argued-not-demonstrated gap in BP-050 and the
rationalized defect in BP-049, and identified the count arithmetic
failures across BP-055 through BP-058.

Its own errors were in scope and in labelling. Manifests were oversized
on several tasks, once contributing to a timeout, and the manifest
omission on BP-049, which left the interfaces document out, is the
direct cause of the rationalized target-write defect. The BP-059
requirement carried a no-consecutive-skip label across from the ITTAGE
allocation work when the TAGE policy is stop-at-first, which is the same
cross-track contamination that appeared in the specification documents,
this time in a prompt.

### What the architect contributed

Every expected value originated with the architect, as did every
specification correction. The rejection of BP-049's completion claim,
the decision to extract the entry field order into standalone format
documents and not patch one rules table, the ruling that the N+1 epoch
timing belonged in the TAGE aging section and not only in a test, and
the judgment that the epoch wrap needed no documentation change were all
architect decisions.

The all-targets rule and its planned phased revision are also architect
decisions, made after measuring the rule's context cost, not before.

### The generalization

Sixteen of the twenty-one tasks were verification work, and thirteen of
those ended with no RTL change. The design conformed to its
specification nearly everywhere it was checked, which means the output
is almost entirely tests, and their passing does not establish what they
are worth.

A test written against conforming RTL and never run against anything
else has an unknown detection capability. It may encode the requirement,
or it may encode whatever the design does. The two are indistinguishable
from the outside, and both produce the same green result. Separating
them is cheap. Break the design in the way the test claims to detect,
confirm the test fails, restore. Where there is nothing to break, choose
stimulus that makes a wrong answer visible. The values recorded here are
what make the passing results mean anything. An expected 2 returned 0
when the epoch gate was widened. An expected 8 returned 9 when the UAON
guard was removed. An expected `c000` returned `e000` against the
uncorrected target write path. Each took minutes.

The same principle explains the other failures, which are not about
tests at all. A count carried forward is a claim about a system state
that no run has produced. A defect reported and argued harmless is a
claim about consequences that no test has examined. A classification
that places a swap in the RTL and not in the test is a claim about which
artifact is authoritative that no comparison has settled. Each was
plausible, and each was wrong or unproven in the direction that would
have cost the most: the rationalized target write would have corrupted
the higher-priority table, and the RTL swap would have broken a block
that conformed on all 33 rows.

The two predictors provide the one controlled comparison available. The
same UAON defect exists in both, found independently by the same
directed method and not by transferring the fix. Where a document error
crossed from one predictor to the other, the directed test on the
receiving side found it, and the deliberate check of the same item on
the originating side came back clean. A method that finds the same class
of defect twice in two independent implementations, and that
distinguishes a genuine carryover from a suspected one, is doing
something a single pass cannot demonstrate.

---

## References

*No references required for this post.*

---

<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry
experience spanning performance modeling, RTL implementation, and
architecture for high-performance OOO processors. He has contributed RTL
to Pentium 4, Arm v7, TI C6x and RISC-V designs, and recently served as
sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE
branch prediction cluster in an 8-issue RVA23 RISC-V processor, from
research through timing closure at 2.75 GHz. He holds more than 20
issued patents in processor design, architecture, and hardware
virtualization. He is the author of Pacino and the uarchlabs methodology
documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->

