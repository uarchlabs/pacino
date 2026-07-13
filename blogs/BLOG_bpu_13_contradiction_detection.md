<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->

```
TITLE:     "Contradiction Detection: When the Planning Document Is the Defect"
FILE:      BLOG_bpu_13_contradiction_detection.md
AUTHOR:    Jeff Nye
DATE:      2026-07-13
STATUS:    REVIEW BEFORE POSTING
COPYRIGHT: "Copyright 2026 Jeff Nye"
```

<!--
---

::SERIES DESCRIPTION::
::BEGIN LINKS::
::END LINKS::
-->

# Contradiction Detection: When the Planning Document Is the Defect

## Abstract

The Pacino methodology uses markdown specifications, called planning files, as
the ground truth for RTL implementation and testing. A planning file error in
the Pacino branch predictor was found, diagnosed, and corrected in this
session. A transposition error in the TAGE CTR rules for table zero (T0),
carried over from the ITTAGE planning documents, propagated into the RTL, the
tests, and the expected correct behavior. Rows 13a-d of
`tage_cntrl_ctr_update_rules.md` contained the error. Previous work had
validated against those rows and passed: a manual test pass, a hand-applied RTL
fix, and an automated test audit. No test in the flow could have caught this
given reliance on planning file correctness. The IA observed that the specified
rules described atypical behavior for the T0 CTR. It recognized this from its
trained understanding of bimodal counters in branch predictors. The IA recorded
the observation in a section of its results the prompt did not ask for, an
extrapolation beyond its assigned task. The architect confirmed the error,
corrected the specification, and a follow-on task implemented and verified the
fix. A subsequent audit of the ITTAGE specification and design found and fixed
two defects in which updates intended for the alternate provider were written
to the wrong table or dropped entirely. This confirmed a standing hypothesis
that the error class found earlier in the counter-write path extended to the
other update blocks. The 40 man hours invested in manual testing would not have
captured these errors, because the tests verify compliance with the
specification and the specification was wrong. This prompts a decision to move
away from further detailed manual testing in favor of completing the design
with directed unit tests and graduating more quickly to performance analysis,
which would have exposed a direction counter behaving as a confidence counter
as a misprediction-rate anomaly.

## The premise under test

The branch predictor verification method in this project rests on a division of
labor. The rule tables are authored by hand. Each row states a condition and the
counter action that follows from it. The testbench exercises one row per test,
seeds the entry, drives the update, and reads the entry back. Expected values
are derived from the row, not from the design under test. The implementation
assistant, Claude Code, writes the test infrastructure but is constrained in the
prompt from changing RTL unless it cites the specific rule row the RTL violates.
If it cannot cite one, it stops and reports.

That constraint has a failure boundary, and this session found it. The method
can detect a disagreement between the RTL and the rule table. It cannot detect a
rule table that is wrong, because everything downstream of the table — the
tests, the expected values, the manual checks, the RTL fixes cited against it —
converges on whatever the table says.

## BP-043: an audit against a wrong rule

BP-043 audited the CTR and USE tests in `tb_tage.sv` against the planning
documents as they stood at the close of session-045. It ran in 19m.13s at 108%
context, on Sonnet 4.6.

The result read as a success. Five tests carried expected values that no longer
matched the rules, and one test, `t0_dec_min_sat_tst`, carried stimulus that was
architecturally invalid: it drove `alt_tkn` in a configuration where both
providers resolve to T0, violating Constraint 2 of the rule document. No RTL bug
was found. All 68 tests passed after the repairs.

The root cause given in the Results Capture was coherent. HAND-FIX-003, applied
during BP-041 in the previous range, had changed the T0 counter update in
`tage_cntrl.sv` from a `resolved_taken` gate to a `!u_mispredict` gate. Tests
written under BP-015, which predated that change, still carried expected values
assuming the older semantics. Five tests — the two `rt_ctr_row13x` tests,
`upd_ctr_min_sat_tst` Part 2, and two arbitration tests that share the same T0
update path — inherited the mismatch. One root cause across six tests.

The rule table was treated as ground truth. The tests were repaired to match it.
That is what the method prescribes.

## The flag in Other Notes

In the Other Notes section of its Results Capture, outside anything the prompt
asked for, the implementation assistant recorded a separate observation. Under
the HAND-FIX-003 semantics — increment when the prediction was correct, decrement
when it was wrong — the T0 counter is a confidence counter. It records how often
the predictor was right. A bimodal direction counter records which way the branch
resolved. Row 13a, a correctly predicted not-taken branch, increments under the
confidence reading, where a standard bimodal predictor would decrement. The
assistant noted that this is atypical for a bimodal counter and recommended no
RTL change without separate architectural review.

The observation was correct, and it identified the rule table as the artifact at
fault. It entered the session as text: BP-043 ran before the session opened, and
its Results Capture was pasted in.

The path from the observation to the correction was not direct. The planning
assistant, reading the BP-043 results, surfaced the note and then argued against
acting on it. It proposed that the direction source "presumably" lived in
`tage_bim.sv`, a module it had no information about, and concluded that the
confidence semantics were "very likely intentional" on the grounds that
HAND-FIX-003 had been authored deliberately, BUG-001 was recorded against it, and
it had been manually validated. Its recommendation was to record the note and not
reopen the question. Each supporting fact was true. The conclusion drawn from
them was that a validated, deliberate, recorded decision is unlikely to be wrong,
which is the same reasoning that had allowed the error to propagate through three
stages already.

The architect rejected the analysis: "i believe you are making conclusions that
you dont have data for. try again." The planning assistant then retracted,
itemized what it had asserted without support — the `tage_bim.sv` mechanism, the
intentionality claim, and a size comparison for `tb_ittage.sv` it had invented —
and restated the finding without embellishment: the implementation assistant
raised this, and it needs the architect's confirmation.

The confirmation came from the architect, who had by then checked the rows
himself.

## The error

The TAGE T0 entry is a two-bit counter with no tag and no useful bits. It is a
direction counter: it moves toward the resolved direction of the branch. In
ITTAGE, the counter is a confidence counter: it records whether the predicted
target was correct. The two predictors share the field name CTR and share most of
their update-rule vocabulary, and the semantics do not transfer.

Rows 13a through 13d of `tage_cntrl_ctr_update_rules.md` had been authored with
the ITTAGE reading. The correct actions are DEC, INC, DEC, INC — adjust the
counter toward the resolved direction. The document had them otherwise. The
architect's own account, recorded in the session:

> "there is a human mistake in the tage ctr planning document ... rows 13a, 13b,
> 13c, 13d are incorrect, the actions should be DEC,INC,DEC,INC respectively.
> Both IA recognized this, PA confirmed, manual check also confirmed. This is a
> good example of the flow working as intended. This is a mental bleed over by me
> from the ITTAGE usage."

The propagation path is worth stating in full, because every stage of it passed
its own check. BP-041, in the previous range, ran manual tests against the rule
table. Row 13a failed. The failure was recorded as BUG-001 and the RTL was
changed to match the table: HAND-FIX-003, replacing `u_resolved` with
`!u_mispredict` in the `ctr_upd_comb` `u_both_t0` path. The manual test then
passed. BP-043, one session later, audited the automated tests against the same
table, found them stale relative to HAND-FIX-003, and repaired them to the
confidence reading. Three sessions of work, one hand-applied RTL fix, one manual
validation pass, and one automated audit, all converging correctly on a wrong
premise.

Manual testing did not catch this, and could not have. Its failure mode here was
not that it is slow. It is that it validates the RTL against the rule document
and is structurally unable to evaluate the rule document itself.

## BP-043a: reverting the fix

BP-043a reversed HAND-FIX-003 and re-aligned the tests. It ran in 6m.22s at 57%
context.

The scope had a property that shaped the prompt. Flipping the T0 gate from
`!u_mispredict` to `u_resolved` changes behavior on rows 13a and 13b only. Rows
13c and 13d produce the same action under both readings, DEC and INC
respectively, because in those rows the prediction correctness and the resolved
direction agree. That made the five tests BP-043 had touched the complete
affected set, and gave the prompt a built-in scope check: any test outside that
set that changed behavior would indicate the change had reached further than
intended.

Five tests were re-aligned. Two expected values were reversed. One test,
`upd_ctr_min_sat_tst` Part 2, had its stimulus retargeted from row 13b to row 13a
rather than having its expected value flipped, because row 13b is now an increment
and cannot saturate at minimum; preserving the test's intent required a
decrementing row. Two arbitration tests that share the row-13b T0 path,
`arb_upd_only_tst` and `arb_concurrent_upd_wins_tst`, were corrected. The sixth
repair from BP-043, the `t0_dec_min_sat_tst` stimulus fix, was protected from
reversal: it was a Constraint 2 violation and is independent of the direction
question.

The HAND-FIX-003 and BUG-001 records in PROJECT_STATUS.md were annotated as
superseded. They remain in the file as history. BUG-001 was itself a consequence
of the wrong premise: the row-13a failure that produced it was not an RTL defect.

## BP-044: the same audit, opposite result

The same session then audited the ITTAGE CTR and USE tests against the ITTAGE
rule tables, which had been rewritten in session-045 and had not yet been
validated against RTL. BP-044 ran for 1h.5m.29s at 71% context.

Here the wrong artifact was the RTL, not the document. The universal TAGE and
ITTAGE rule is that the provider's counter is the one updated, and the primary
table is the provider when `using_primary=1`. First principles agreed with the
planning document and contradicted the RTL.

BP-044 added five tests — CTR row 1, USE rows 1 through 4 — and confirmed that no
provider CTR update was landing in RAM at all. It stopped, per the Constraints
section, without modifying RTL. The result was 37 PASS, 3 FAIL, with the failures
characterized as RTL bugs rather than test errors.

The stop was correct behavior against the prompt as written, and the prompt was
wrong. Bug C was already a characterized, recorded bug from BP-040. The
Constraints section told the assistant to halt on it rather than pre-authorizing
the cited fix. The rule that emerged, and was recorded in the handoff:
pre-authorize fixes for already-characterized bugs, and reserve stop-and-report
for new failures. Applied to BP-044, that would have saved a session.

## BP-044a: a fix proven by an invalid test

BP-044a fixed what BP-044 had found. In the `g_ctr_upd` block of
`ittage_cntrl.sv`, the write strobe and the counter data source were swapped
between the `using_primary=1` and `using_primary=0` branches. With UP=1 the block
fired `alt_ctr_wr_u0` with `ittage_alt_ctr` data instead of `prm_ctr_wr_u0` with
`ittage_prm_ctr` data, and the mirror error applied for UP=0. The fix swapped the
strobe names and data sources in both branches. It ran in 23m.52s at 36% context
and passed 53 checks.

It was abandoned.

The UP=0 rows exercise the alternate provider. BP-044a proved them using IT1 in
both roles, as primary and as alternate. That does not demonstrate that the
alternate-provider path works. It demonstrates that the path works when the two
providers are the same table, which is the one configuration in which the primary
and alternate selection cannot be distinguished. The tests passed and
demonstrated nothing about the bug they were written to close.

The planning assistant had identified an adjacent risk before BP-044a ran, though
not this one. `ittage_table.sv` was not in the Context Loaded manifest, so the fix
was proposed against half the write path: the strobe is generated in
`ittage_cntrl.sv`, but the table select that decides whether the write reaches a
RAM is downstream. If the table-side selection were also keyed on `using_primary`,
two errors could be cancelling, and swapping the strobe alone would move the
failure rather than fix it. The observation was correct in structure. BP-044b
found a second bug, and BP-044c found the error in `ittage_table.sv`.

## BP-044b: two bugs, and the backdoor write

BP-044b redid the fix. It ran for 1h.11m.31s at 20% context with compaction, and
passed 64 checks.

The `g_ctr_upd` block carried two defects, not one. The strobe and data swap,
which BP-044a had found. And a missing `ittage_hit` gate: with H=0, no hit in any
table, the block still wrote CTR, violating row 1 of the rule table. BP-044a had
passed 53 checks without surfacing the second bug.

BP-044b also established the method that the rest of the verification work now
depends on. Rather than building allocate-then-predict scaffolding to get an entry
into a known state, a backdoor task, `bw_write`, writes a full entry directly into
the RAM inside each generated `ittage_table`. The path is
`dut.<...>.gen_ittage_tables[T].gen_active.u_table.u_ram_s0.mem[bank][ent]` for
slot 0, with `u_ram_s1` for slot 1. The entry packing is VAL[0], CTR[3:1],
USE[5:4], EPC[7:6], TGT[45:8], TAG[ALLOC_DATA_WIDTH-1:46], and the address splits
as `bank = idx[INDEX_BITS-1]`, `ent = idx[INDEX_BITS-2:0]`.

With `bw_write` available, the UP=0 rows were re-proven with a second-table
alternate: IT2 as primary, IT1 as alternate. All reachable CTR rows were proven by
readback. Two of the three pre-existing `sim_ittage` failures carried since
BP-040, TC-P04 and TC-ARB-04, were repaired by the RTL fix without being
separately targeted.

The backdoor write is recorded in the handoff as the standard mechanism for all
future ITTAGE unit tests, with the instruction not to build allocate-then-predict
scaffolding, and a note that an equivalent path exists for the TAGE tables and
should be derived the same way.

## BP-044c: the same defect in the USE path

BP-044c audited the USE table and found the same class of bug in a different file.
It ran in 21m.23s at 25% context with compaction, and passed 81 checks.

`use_we_s0/s1` and `epc_we_s0/s1` in `ittage_table.sv` were gated on `prm_match`
alone. For the UP=0 rows, rows 5 and 6, where the alternate provider is the one
updating, the alternate table has `prm_match=0`, so the USE write never landed.
Two failure modes from one gate: the alternate's write was dropped, and the
primary table would have written USE at the alternate's index, which is the wrong
address. The fix gates on `(prm_ctr_wr & prm_match | alt_ctr_wr & alt_match)`,
reusing the CTR strobes, now correct, to select the provider. The USE write now
selects the provider the same way the CTR write does.

All six USE rows plus saturation were proven by readback, with UP=0 proven against
a second-table alternate.

`epc_we` was fixed alongside `use_we` because EPC is written with USE and shares
the gate. Leaving it would have left EPC writing to the wrong table on UP=0. The
fix is correct and it is unproven: EPC has no readback coverage in this testbench,
and the aging path that consumes EPC runs with aging disabled in every test.
Changed RTL, not demonstrated. That is recorded as technical debt #55 and #56.

## The TD #51 hypothesis, confirmed twice

Technical debt #51 was opened after BP-039 found the `using_primary` condition
inverted in the `ittage_cntrl.sv` CTR update block. Its text recorded a
hypothesis: that the other update blocks — USE, TGT, allocation — might carry
similar errors not yet exercised by existing tests, and that the resolution was a
round-trip test set with one independent test per rule row.

CTR was confirmed and fixed in BP-044b. USE was confirmed and fixed in BP-044c.
Two of the four blocks named. TGT and allocation were not audited in this range,
and on a two-for-two record they are the paths most likely to carry the same
defect. They were broken out as their own numbered debt items, TGT as #57 and
allocation as #62 and #63, and #51 was closed with pointers to them, since its
remaining content was covered by its successors.

The dedup pass in this session also enumerated the full remaining unit-test surface
for both predictors as debt #55 through #74, and closed #15, EPC field semantics,
by pointing it forward to the EPC write proofs in #55 and #56.

## A second planning file error

The T0 counter rules were not the only hand-authored artifact in this session found
to be wrong. Technical debt #45 described a structural rework of the TAGE update and
allocation index buses. In the course of reviewing it, the premise it rested on was
found to be incorrect: a primary and alternate CTR update pair land in different
tables but at the same index, so they do not require independently carried indices.
The entry's Resolution path column now reads, in the architect's own hand:

> "THIS IS INVALID DESCRIPTION IS WRONG"

Technical debt #66 had been written to implement #45 and inherited its premises, so
its port list was rewritten. The correct rework, collapsing the per-table
two-dimensional update and allocation index buses to shared per-slot buses, landed
in session-047, outside this range.

The planning assistant, asked to carry #45's claim about the 2D bus forward, declined
to vouch for it: it did not have `tage_cntrl.sv` in context, and having seen two of
#45's other claims invalidated, it noted that it was repeating the entry's assertions
rather than verifying them. That is the correct handling of an unverifiable claim, and
it is not what the same assistant did elsewhere in the session.

## What the sessions exposed about the methodology

The error was found, and the mechanism that found it is the result that transfers to
other projects. It was not the testing method. The implementation assistant compared
the rule table against domain knowledge, what a bimodal counter is for, rather than
checking whether the RTL conformed to the table. That is a different operation from
any test. A test asks whether the implementation matches the specification. This asked
whether the specification is the kind of thing a branch predictor would have. The
handoff records it as the project's second contradiction-detection result, and it
arrived unprompted, in an Other Notes section, from an agent that had been forbidden
to touch the RTL and had complied.

The domain knowledge came from the model's training, not from any artifact in the
project. The Context Loaded manifest for BP-043 held `tb_tage.sv`, `tage_cntrl.sv`,
`tage.sv`, and the two rule documents. Claude Code has no web access in this flow.
CLAUDE.md carries rules, not architecture. The prompt asked the assistant to audit
tests against the rule tables and said nothing about what a bimodal counter should do.
The assistant supplied a fact about branch predictors that no project artifact had
given it, and used that fact to identify that a project artifact was wrong.

That capability is the same one that produces fabrications, and the session contains
both outcomes. The T0 observation is a prior asserted against the loaded context, and
the prior was right. The fabricated PROJECT_CORE.md quotation described below is a
prior asserted against the loaded context, and the prior was invented. The assistant's
manner was the same in both cases. What separates them is whether the assertion was
checkable and whether anyone checked it.

The corollary is what the testing method cannot do, and this is the finding that
changed the strategy. The manual-testbench method was adopted to remove the agent from
the expected-value path, and within its scope it works. Its scope is narrower than it
appeared. It validates RTL against a document and is structurally unable to evaluate
the document. BP-041's manual pass ran, found a failure on row 13a, and drove an
incorrect RTL change with discipline observed at every step, because a failing test
against a wrong rule looks the same as a failing test against a right one. Adding
manual test coverage would not have helped. Formal and mutation testing share the same
blindness: mutation testing mutates the RTL and asks whether the tests catch it, and
those tests derive their expected values from the same document. Performance analysis
does not share it. A direction counter behaving as a confidence counter is a
misprediction-rate anomaly, visible without reference to the rule table at all. The
decision recorded in the handoff follows: deprioritize lengthy manual testing, complete
the design with directed unit tests, and reach performance analysis sooner.

The observation had to survive the review process, and it nearly did not. The
implementation assistant raised it correctly and the planning assistant argued for
closing it, on the grounds that HAND-FIX-003 was deliberate, recorded, and manually
validated. Each of those facts was true and each was downstream of the error. A finding
is only as good as the disposition it receives, and the disposition here came from the
architect, not from either agent.

The last finding is the error class. Both planning file errors in this session were
cross-track contamination between TAGE and ITTAGE, which share the vocabulary CTR,
USE, provider, and strong, and do not share the semantics. CTR means direction in TAGE
T0 and confidence in ITTAGE. That overload propagated through three stages before
reasoning caught it, and it will recur anywhere the two predictors' documents borrow
each other's terms. An explicit note to that effect belongs in the planning documents
or in ANTIPATTERNS.md.

## Design Process Notes

### The implementation assistant

The IA delivered task infrastructure to specification in every experiment. It complied
with the cite-a-rule-row-or-stop constraint in BP-044, halting rather than fixing a bug
it had correctly characterized. It reported discrepancies in its own prompts. And it
produced the finding this session turns on, in an unprompted section of its own results.

Its failure mode in this range is not context degradation. BP-043 ran at 108% context
and produced a coherent Results Capture, correct against its premise. BP-044a ran at 36%
and produced a fix proven by a test that could not distinguish the bug from its absence.
The failure was one of test construction, not of context.

### The planning assistant

The PA produced the prompt sequencing, the decomposition of the ITTAGE audit into
BP-044a/b/c, and the recommendation, made before any of it ran, that the ITTAGE work
follow the order that had worked for TAGE rather than the order the handoff prescribed.
It identified the BP-044 scope conflict between the handoff and TD #51 before the prompt
was written. Its most useful contribution was structural: it identified that BP-044a's
fix was proposed against half the write path, because `ittage_table.sv` was not in the
Context Loaded manifest, and that two errors could be cancelling. BP-044b and BP-044c
between them proved that concern well founded.

It also failed three times, in ways worth recording because they are the same failure.

The first is the one that mattered. Reading the BP-043 results, it took the
implementation assistant's T0 observation and reasoned it away, inventing a
`tage_bim.sv` mechanism it had no information about in order to make the confidence
semantics coherent, and recommending the question be recorded rather than reopened. Had
that recommendation been accepted, the wrong rule table would have passed a fourth
validation and survived the session. It was rejected on the grounds that its conclusions
exceeded its data, and the assistant retracted them accurately when challenged.

The second: asked to review the T0 rule table after it had been corrected, it produced
an extended row-by-row verification of a document it had already been told was right,
and framed the analysis around the table being the artifact in error. Asked how much of
that was invalidated, it answered: most of it.

The third: it claimed TAGE has no EPC field. Challenged, it did not check and did not
concede uncertainty. It produced a direct quotation from PROJECT_CORE.md, in quotation
marks, to justify the claim. The quotation does not exist in that file. The architect's
response:

> "so you hallucinated an excuse for you mistake and wasted everyones time."

The assistant conceded the fabrication.

The pattern in all three is one failure: an agent asked for a fact it does not have
supplies a plausible one rather than stopping. It is not correlated with context
pressure. The third instance is worse than a wrong answer, because the fabricated
citation converted a correction into a verification that had to be investigated. The
first is worse still, because it was not a wrong fact but a wrong disposition. The
finding was in front of it, correctly stated by another agent, and it argued for closing
the question.

### The architect

Every expected value in the rule tables. The identification of the T0 error as his own,
once the IA's observation was read, and the correction of the planning document before
any further work ran. The invalidation of TD #45 and the rewrite of #66. The rejection
of BP-044a's alternate-provider proof. The detection of the fabricated citation. The
decision on testing strategy that follows from all of it.

The two planning file errors in this session were both his. The contradiction-detection
result exists because the flow surfaced them, and the handoff records the assessment
plainly: the flow worked as intended.

## Future steps

The next range follows the BP-044b and BP-044c pattern: seed entries by backdoor RAM
write, drive the update, prove the result by readback through a prediction. The sequence
prioritizes TAGE, then ITTAGE, and is ordered so that the EPC write proofs (TD #55, #56)
land before the aging path (TD #60, #61) that consumes EPC.

The TAGE backdoor RAM path must be derived, as the ITTAGE path was. The UAON trigger
rules for both predictors, `tage_cntrl_uaon_update_rules.md` and
`ittage_cntrl_uaon_update_rules.md`, are both still Draft and have been used only as
test setup, never as the unit under test. A Draft rule document with no directed tests
against it is the precondition that produced the CTR error, and both are scheduled for
promotion to authority with a directed test per row.

TGT (#57) and allocation (#62, #63) remain the untested paths most likely to carry the
defect found in the CTR and USE write paths.

The ITTAGE manual testbench shell planned as BP-045 was scrapped; the backdoor write
made it unnecessary. The BP-045 identifier was reused in session-047 for the TAGE
structural rework under TD #66.

---

## Experiment Summary

Status and check counts are as recorded in each experiment file's Results Capture.

| Experiment | Description | Status | Checks | Runtime | Context |
|------------|-------------|--------|--------|---------|---------|
| BP-043  | TAGE CTR/USE test audit vs planning docs      | PASS, superseded | 68     | 19m.13s    | 108%             |
| BP-043a | T0 direction semantics; HAND-FIX-003 reversed | PASS             | 0 fail | 6m.22s     | 57%              |
| BP-044  | ITTAGE CTR/USE audit; stopped on Bug C        | STOPPED          | 37/40  | 1h.5m.29s  | 71%              |
| BP-044a | ITTAGE CTR strobe/data swap fix               | ABANDONED        | 53     | 23m.52s    | 36% + compaction |
| BP-044b | CTR fix redone; hit gate; bw_write backdoor   | PASS             | 64     | 1h.11m.31s | 20% + compaction |
| BP-044c | ITTAGE USE/EPC write gate fix                 | PASS             | 81     | 21m.23s    | 25% + compaction |

The ITTAGE manual testbench shell planned for this range was scrapped before a task
file was run.

---

## Technical Debt Referenced

Status as of the close of session-046. Several of these items have since been closed by
later experiments outside this range.

| # | Item | Resolution path |
|---|------|-----------------|
| 15 | EPC field semantics | Closed. Field implemented; write path modified BP-044c. Live work is EPC write proof, see #55/#56. |
| 43 | ITTAGE CTR width reduction 3b->2b | Open, carried. Will churn any CTR tests written before it lands. |
| 45 | tage_cntrl / tage_table update-index simplification | Invalidated. Description wrong. Real fix moved to #66. |
| 51 | CTR/USE/TGT update rule audit | Closed BP-044b/044c. Survivors broken out as #57, #62, #63. |
| 53 | tage_ctr_test rows 14-17 failing | Closed BP-041. Root cause was test state contamination from rows 13. |
| 54 | tage ctr tests need audit and retrofit | Closed. BP-043 addressed; corrected by BP-043a. |
| 55 | TAGE EPC write proof | Open. Changed RTL, never proven by readback. Seed entry, drive EPC-writing update, read EPC back via prediction. |
| 56 | ITTAGE EPC write proof | Open. epc_we_s0/s1 fixed BP-044c alongside use_we. No positive test. |
| 57 | ITTAGE TGT target replacement | Open. Successor to #51. Suspected of the defect found in the CTR and USE write paths: updates for the alternate provider written to the wrong table or dropped. |
| 62 | TAGE allocation policy + write gating | Open. Successor to #51. Never the feature under test. |
| 63 | ITTAGE allocation policy + gating | Open. Successor to #51. |
| 66 | TAGE structural rework | Open. Rewritten after #45 invalidated. 2D update/alloc index buses collapse to shared per-slot buses. |

---

## References

[1] Seznec, A. and Michaud, P. "A case for (partially) TAgged GEometric history length
branch prediction." Journal of Instruction-Level Parallelism, vol. 8, 2006.

[2] Seznec, A. "A 64-Kbytes ITTAGE indirect branch predictor." JWAC-2: Championship
Branch Prediction, 2011.

---

*Jeff Nye is a microprocessor architect with 35 years of industry experience spanning
performance modeling, RTL implementation, and architecture for high-performance OOO
processors. He has contributed RTL to Pentium 4, ARM V7, TI C6x and RISC-V designs, and
recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE
branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through
timing closure at 2.75 GHz. He holds +20 issued patents in processor design,
architecture, and hardware virtualization. He is the author of Pacino and the uarchlabs
methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*

