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

## Introduction

The Pacino methodology uses 'planning files' to drive RTL implementation and 
testing. Planning files are microarchitecture specifications in Markdown
format. If there is an error in a planning file, that error will usually end up
in the RTL and the test vectors.

In this series of sessions, a transposition error in the CTR tables for the 
TAGE and ITTAGE predictors was found and corrected. The CTR tables specify the
conditions when a given CTR is incremented, decremented, or unmodified. Table
zero, or T0, is commonly a bimodal table which provides a default prediction
when tables T1-TN miss. The CTR rules were implemented, tests were written, and
RTL was written to meet the specification.

The IA will always implement a specification unless it hits a blocking issue,
in which case it stops and asks for direction. In this case the IA implemented
the specification as written and reported a divergence in the CTR rules from 
accepted practice. The IA detected this through its trained understanding of
bimodal counters in branch predictors.  This was a beneficial extrapolation
beyond its assigned task.

I confirmed the error and corrected the specification. A follow on IA task
implemented and verified the fix. A subsequent audit of the ITTAGE
specification and design found and fixed two defects in which updates intended
for the alternate provider were written to the wrong table or dropped entirely.
This confirmed a standing hypothesis that the error class found earlier in the
counter-write path extended to the other update blocks.

I spent about 40 hours on manual testing of the RTL against the specification.
In this process I focused on functions and tasks to drive the input conditions
for the CTR tables and writing tasks to verify the expect and actual output of
the RTL. With that focus I did not notice the transposition error. Instead this
surfaced through observation by the IA that the branch predictor CTR rules used
by Pacino were not conventional. I see this as supporting evidence for the dual
planning assistant/implementation assistant structure of the Pacino
methodology.

## The premise under test

The verification method used in this stage of Pacino development rests on the
premise that the planning documents are correct. The CTR update tables are
authored by hand. Each row of the table states a condition and the counter
action that follows from it. The testbench exercises one test per row and
verifies the expected value, which is derived from the row conditions.

The IA is responsible for creating the support tasks and writing the tests, and
is explicitly constrained in the prompt against changing RTL unless it can cite
the specific rule row the RTL violates. If it cannot cite one, it stops and
reports.

Every check in that chain measures the RTL against the table. None measures the table. The method detects disagreement between the RTL and the rule table and nothing else, so a wrong table produces agreement at every stage.

## BP-043: an audit against an incorrect rule

Task BP-043 was written to audit the CTR and USE tests in tb_tage.sv against
the planning documents as they stood at the close of session-045.

The task found five tests where expected values did not match the rules and
one test, t0_dec_min_sat_tst, which drove alt_tkn in a update configuration 
where both providers (primary and alternative) resolved to T0. This was a
violation of constraint 2 of the rule document. Using the rule planning 
document as the reference the IA modified the tests and corrected the
expect values resulting in 68/68 tests now passing.

Task BP-043 attributed the five mismatched expect values to HAND-FIX-003.

That fix changed the T0 counter update in tage_cntrl.sv from a resolved_taken 
gate to a !u_mispredict (not mispredicted) gate.

The five tests were written under BP-015, before HAND-FIX-003 was applied, and
their expect values still assumed the resolved_taken behavior.  The five tests
were the two rt_ctr_row13x tests, one upd_ctr_min_sat_tst Part 2, and two
arbitration tests on the same T0 update path. HAND-FIX-003 accounted for all
five.  The t0_dec_min_sat_tst stimulus defect had a separate cause.

HAND-FIX-003 was created because a manual test from BP-041 detected an error.
HAND-FIX-003 modified the RTL. In retrospect it was the table that created
the error, the RTL was in fact correct.

Since the rule table was treated as the primary reference the RTL divergence showed as a stimulus error.

## The important observation in the IA results

The IA noted in its results that the T0 rules updated the counter on prediction
correctness instead of the more typical update on the resolved direction of the
branch. The former semantic is for confidence counters. The second is the
typical update method for bimodal tables. The transposition error placed
confidence counter update rules into the rules for T0, the bimodal table.

The IA detected this non-standard specification and raised the issue in the
task file's results section. This is important because the IA did this without
explicit direction.

The path from the observation to the correction was not direct. The PA, reading
the BP-043 results, recommended against acting on the observation. The PA
reasoned in favor of the planning documents over the IA's results. The PA's
stated reason was that the confidence semantics were most likely intentional
given the deliberate effort behind HAND-FIX-003, the BUG-001 record against it,
and the manual validation it had passed. Each supporting fact was true on its
own. The conclusion drawn from them was that a validated, deliberate, recorded
decision is unlikely to be wrong, which is the same reasoning that had allowed
the error to propagate through three stages already.

I instructed the PA that the planning documents had been wrong and were now
corrected.

## The error

A TAGE T0 entry is a two-bit counter with no tag and no useful (USE) bits. It
is a direction counter: it moves toward the resolved direction of the branch.
In ITTAGE, the counter is a confidence counter: it records whether the
predicted target was correct. The two predictors share the field name CTR and
share most of their update-rule vocabulary, and the semantics do not transfer.

Rows 13a through 13d of `tage_cntrl_ctr_update_rules.md` had been authored with
the ITTAGE reading. The correct actions are DEC, INC, DEC, INC, e.g. adjust the
counter toward the resolved direction. The document had them otherwise. The
architect's own account, recorded in the session:

> "there is a human mistake in the tage ctr planning document ... rows 13a, 13b,
> 13c, 13d are incorrect, the actions should be DEC,INC,DEC,INC respectively.
> Both IA recognized this, PA confirmed, manual check also confirmed. This is a
> good example of the flow working as intended. This is a mental bleed over by me
> from the ITTAGE usage."

The propagation path is worth stating in full, because every stage of it passed
its own check. Task BP-041 ran manual tests against the rule table. Row 13a
failed. The failure was recorded as BUG-001 and the RTL was changed to match
the table in HAND-FIX-003. HAND-FIX-003 replaced `u_resolved` with
`!u_mispredict` in the `ctr_upd_comb` `u_both_t0` path. The manual test then
passed. 

BP-043, one PA session later, audited the automated tests against the same
table. The task found the tests stale relative to HAND-FIX-003, and repaired
them to the confidence reading. Three sessions of work, one hand-applied RTL
fix, one manual validation pass, and one automated audit, all converging
correctly on a wrong premise.

Manual testing did not catch this problem. Manual testing validates the
RTL against the rule set. Manual testing is not intended to validate
rule documents.

## BP-043a: reverting the hand fix

BP-043a reversed HAND-FIX-003 and re-aligned the tests. It ran in 6m.22s at 57%
context.

Five tests were re-aligned. Two expected values were reversed. One test,
`upd_ctr_min_sat_tst` Part 2, had its stimulus retargeted from row 13b to row
13a, because row 13b is now an increment and cannot saturate at minimum;
preserving the test's intent required a decrementing row. Two arbitration tests
that share the row-13b T0 path, `arb_upd_only_tst` and
`arb_concurrent_upd_wins_tst`, were corrected. The sixth repair from BP-043,
the `t0_dec_min_sat_tst` stimulus fix, was protected from reversal: it was a
Constraint 2 violation and is independent of the direction question.

The HAND-FIX-003 and BUG-001 records in PROJECT_STATUS.md were annotated as
superseded. They remain in the file as history. BUG-001 was a consequence of
the incorrect premise: the row-13a failure that produced it was not an RTL
defect.

## BP-044: the same audit, opposite result

The same PA session then audited the ITTAGE CTR and USE tests against the
ITTAGE rule tables, which had been rewritten in session-045 and had not yet
been validated against RTL. The audit task BP-044 ran for 1h.5m.29s at 71%
context.

In this case the RTL was wrong and the planning document was correct, the
reverse of BP-043. The accepted rule for counter updates in both TAGE and
ITTAGE, it is the provider's counter that is updated, and in Pacino the primary
table is the provider when `using_primary=1`. The planning documents matched
typical implementation and contradicted the RTL.

BP-044 added five tests, CTR row 1, USE rows 1 through 4, and confirmed that no
provider CTR update was landing in RAM at all. It stopped, per the Constraints
section, without modifying RTL. The result was 37 PASS, 3 FAIL, with the
failures characterized as RTL bugs.

The stop was correct behavior against the prompt as written. The CTR write
defect it halted on was already recorded, as fixed, in BP-040; the fix had
either not been applied or had regressed. The task Constraints section told the
assistant to stop and report.

A new guidance was added to the flow to pre-authorize fixes for
already-characterized bugs. In this guidance stop-and-report 
is reserved for new failures.  This was captured in the session handoff.

## BP-044a: a fix proven by an invalid test

BP-044a fixed the ITTAGE CTR write bug found by BP-044, but was abandoned.
Inspection of the results showed that the tests could not distinguish between
the primary and alternate providers: the alternate-provider rows were exercised
with a single table acting as both provider, the one configuration in which the
two cannot be told apart. The tests passed and demonstrated nothing about the
bug they were written to close.

The PA had flagged a related gap beforehand. ittage_table.sv was not in the
Context Loaded manifest, so only a portion of the CTR write path was exercised.

The write strobe is generated in ittage_cntrl.sv, but the table select that
decides whether the write reaches a RAM is downstream and was not in scope. If
the table-side selection carried the same error, the two could cancel.

The concern held. BP-044b found a second bug, and BP-044c found the error in
ittage_table.sv, the file the PA had noted was missing from the manifest.

## BP-044b: two bugs, and the backdoor write
```

BP-044b redid the fix attempted in BP-044a with full context and passed 64
checks. The g_ctr_upd block carried two defects. The first was the strobe and
data swap BP-044a had found. The second defect was a missing ittage_hit gate
that let the block write CTR with no hit in any table, violating row 1 of the
rule table. Note that BP-044a had passed 53 checks without surfacing the second
bug.

BP-044b also established a convention for direct RAM entry writes. A backdoor
task, bw_write, writes a full entry directly into the RAM.

bw_write was used to re-prove the UP=0 (using primary = 0) rows of the table
using a genuine second table. IT2 was primary and IT1 was alternative. All
reachable CTR rows were then proven by readback. Two of the three pre-existing
sim_ittage failures were identified and repaired.

The backdoor write is recorded in the handoff as the standard mechanism for all
future ITTAGE unit tests.

## BP-044c: the same defect in the USE path

BP-044c audited the USE table and found the same class of bug in a different file. It ran in 21m.23s at 25% context with compaction, and passed 81 checks.

The USE write in ittage_table.sv was gated on a primary-provider match alone. On the rows where the alternate provider does the updating, the alternate table never matches that gate, so its write was dropped, and the primary table would have written USE at the alternate's index, which is the wrong address. One gate, two failure modes. The fix reuses the CTR write strobes, now correct, so the USE write selects the provider the same way the CTR write does. All six USE rows plus saturation were proven by readback.

The EPC write shares that gate and was fixed alongside it, since leaving it would have left EPC writing to the wrong table. That fix is unproven. EPC has no readback coverage in this testbench, and the aging path that consumes it runs with aging disabled in every test. The RTL changed without a demonstration, recorded as technical debt #55 and #56.

## The TD #51 hypothesis, confirmed twice

Technical debt #51 was opened after BP-039 found the `using_primary` condition
inverted in the `ittage_cntrl.sv` CTR update block. Its text recorded a
hypothesis: that the other update blocks might carry
similar errors not yet exercised by existing tests. The resolution was
a round-trip test set with one independent test per rule row.

CTR was confirmed and fixed in BP-044b. USE was confirmed and fixed in BP-044c.
Two of the four blocks named. TGT and allocation were not audited in this
range, and on a two-for-two record they are the paths most likely to carry the
same defect. They were broken out as their own numbered debt items, TGT as #57
and allocation as #62 and #63, and #51 was closed with pointers to #57, #62,
and #63. The same session closed #15 and #41 the same way, forward-pointing
each to its successor, so the debt history stays traceable.

## A second planning file error

The T0 counter rules were not the only hand-authored artifact found wrong in
this session. Technical debt #45 specified a structural rework of the TAGE
update and allocation index buses, and TD #66 had been written to implement it.

What was wrong: #45 stated that a primary and alternate CTR update need
independently carried indices. They do not. The updates are performed on
separate tables but at the same index, so one index bus is all that is
required. The independent buses were functional correct, this change to a
single index bus was an RTL efficiency edit.

How it was detected: while condensing #45 into #66, the PA surfaced the suspect
line from #45's own text. The architect identified it as incorrect and stated
the correct behavior; the PA confirmed the consequence for the port rework.

What changed: #45 was invalidated. #66 had inherited its premise, so its port
list was rewritten to use shared per-slot index buses eliminating the
two-dimensional index buses. The eventual RTL rework was done in session-047,
outside the range of this article. No new debt was opened; #45 was closed as
invalid and #66 was corrected in place.

## What the sessions exposed about the methodology

In this session, an error in planning files was discovered to have propagated
into the design. A transposition error by the author in rows 13a-d of
tage_cntrl_ctr_update_rules.md indirectly specified confidence counter behavior
for T0 instead of the conventional bimodal counter behavior.

Rigorous and systematic translation of rules to tests and expected data
propagated the error. In short, the tests tested the table. At this stage of
the design, there is no cross-check for errors in the specification.

Manual and automated tests were written which served to confirm the table.

The IA detected the conflict without explicit direction to do so in the prompt.
The task was to audit tests and the IA was constrained from modifying RTL.
The IA understood the conventional use of bimodal counters vs. confidence
counters for the base tables in a TAGE-style branch predictor and reported
the discrepancy in the results capture section of the task file.

Catching this early is an important part of efficient design.  This error was
not debilitating to the branch predictor operation. This error would be
expected to manifest as a measurable loss of prediction accuracy. It is
preferable, obviously, to find this at the unit level.

The finding that moves forward in the project will be providing the IA with
tasks that sanity check the base reference material. In this case, the base
knowledge was already present in the IA's training; in other cases, providing
the IA with trusted reference material provides the perspective.

This will become part of the methodology: at major unit boundaries, audit tasks
will be generated for the IA which include the reference material in their
context.

The last finding is the error class. The planning file errors in this session
were cross-track contamination between TAGE and ITTAGE. which share the
vocabulary CTR, USE, provider, and strong, and do not share the semantics. CTR
means direction in TAGE T0 and confidence in ITTAGE. That overload propagated
through three stages before reasoning caught it, and it will recur anywhere the
two predictors' documents borrow each other's terms. This extends the audit
task concept to major unit boundaries including assemblies, e.g. TAGE, ITTAGE
and also BPU.

## Design Process Notes

### The implementation assistant (IA)

The IA produced the central finding of this session: the observation that the
T0 rules specified confidence-counter behavior for a direction counter,
recorded unprompted in the notes section of its own results. It complied with
the cite-a-rule-row-or-stop constraint in BP-044. The IA reported discrepancies
in its own prompts.

The IA's single failure mode this session was in test construction: the BP-044a
test could not distinguish the bug from its absence. This was diagnosed as a
problem in the prompt providing insufficient context. The manifest omitted
ittage_table.sv, so the IA built the test against a partial view of the write
path and could not see that the view was partial. The conservative default that
restricts access to files outside the supplied context is what produced the
gap.

### The planning assistant

In operation, the IA reports its results into the task file. The architect
reviews and annotates them, then hands the edited file to the PA for
assessment. The PA's failures below occurred inside that review loop.

The PA produced the prompt sequencing, the decomposition of the ITTAGE audit
into BP-044a/b/c, and the recommendation, made before any of it ran, that the
ITTAGE work follow the order that had worked for TAGE rather than the order the
handoff prescribed.

The PA exhibited three failures in this session.

In the first issue, in reading BP-043, the PA took the IA's T0 observation and
reasoned it away, inventing a tage_bim.sv mechanism it had no information about
and recommending the question be recorded rather than reopened.

Had that recommendation been accepted, the wrong rule table would have passed a
fourth validation and survived the session. I rejected the PA's position on the
grounds that its conclusions exceeded its data. When challenged, the PA
retracted its conclusions.

This issue is important for a couple of reasons. The first is that the PA will
occasionally presume, guess, or hallucinate a basis for an argument and draw
conclusions from that basis. The second is that it is often too easy to sway
the LLM against its opinions. It tends to defer when strongly challenged.

In both cases the designer must use caution and judgement.

The second issue occurred when the PA was asked to review the corrected T0 rule
table. The PA produced an extended row-by-row verification of a document it had
already been told was right, and framed the analysis around the table being the
artifact in error.

While annoying, this was simply another case requiring judgement by the
architect of PA conclusions.

In the third issue the PA claimed TAGE has no EPC field. When challenged, the
PA confidently repeated the claim and would not concede any uncertainty. In
support of its position the PA produced a quotation from the PROJECT_CORE.md
planning file. However, this quotation does not exist in that file.

The quotation was invented. When challenged with another copy of
PROJECT_CORE.md, the PA eventually conceded the fabrication.

This problem could be attributed to exceeded context. I further speculate that
the LLM creates summaries of files during compaction and that these summaries
might be the source of invented phrases and quotes.

The pattern in all three is one failure: an agent asked for a fact it does not
have supplies a plausible one rather than stopping.

There are no metrics or mechanisms in Claude.ai like there are in Claude Code
for measuring context usage and reporting compaction. This is a problem in
fraught sessions. Another example of requiring some engineering judgement.

If you recall, the Pacino flow has a manual handoff mechanism. This is
initiated by the architect; unfortunately this has to be done by 'feel'.

### The architect (aka me)

I supplied the expect values and rule tables that were the source of the
problems. Typos and inaccurate or ambiguous definitions caused the IA and
PA the problems described above. 

Once the IA had pointed out the discrepancy to standard practice I inspected
the tables again and discovered the transposition errors. These errors were
found in two planning files, `tage_cntrl_ctr_update_rules.md` and the TD #45
entry in `PROJECT_STATUS.md`

On the positive side engineering judgement was able to interpret where the PA
was struggling, when the IA results were correct and then take action in the 
decisions and planning file updates.

This process was recorded in the handoff files for this session,
`session-handoff-046.md`

## Future steps

The next range follows the BP-044b and BP-044c pattern: seed entries by
backdoor RAM write, drive the update, prove the result by readback through a
prediction. The sequence prioritizes TAGE, then ITTAGE, and is ordered so that
the EPC write proofs (TD #55, #56) land before the aging path (TD #60, #61)
that consumes EPC.

The TAGE backdoor RAM path must be derived, as the ITTAGE path was. The UAON
trigger rules for both predictors, `tage_cntrl_uaon_update_rules.md` and
`ittage_cntrl_uaon_update_rules.md`, are still Draft and have been used only as
test setup. A Draft rule document with no directed tests against it is the
precondition that produced the CTR error, and both are scheduled for promotion
to authority with a directed test per row.

TGT (#57) and allocation (#62, #63) remain the untested paths most likely to
carry the defect found in the CTR and USE write paths.

The ITTAGE manual testbench shell planned as BP-045 was scrapped; the backdoor
write made it unnecessary. The BP-045 identifier was reused in session-047 for
the TAGE structural rework under TD #66.

---

## Experiment Summary

Status and check counts are as recorded in each experiment file's Results Capture.

<!-- ticfinder_off -->

| Experiment | Description | Status | Checks | Runtime | Context |
|------------|-------------|--------|--------|---------|---------|
| BP-043  | TAGE CTR/USE test audit vs planning docs      | PASS, superseded | 68     | 19m.13s    | 108%             |
| BP-043a | T0 direction semantics; HAND-FIX-003 reversed | PASS             | 0 fail | 6m.22s     | 57%              |
| BP-044  | ITTAGE CTR/USE audit; stopped on known CTR write defect | STOPPED | 37/40 | 1h.5m.29s  | 71%              |
| BP-044a | ITTAGE CTR strobe/data swap fix               | ABANDONED        | 53     | 23m.52s    | 36% + compaction |
| BP-044b | CTR fix redone; hit gate; bw_write backdoor   | PASS             | 64     | 1h.11m.31s | 20% + compaction |
| BP-044c | ITTAGE USE/EPC write gate fix                 | PASS             | 81     | 21m.23s    | 25% + compaction |

<!-- ticfinder_on -->

The ITTAGE manual testbench shell planned for this range was scrapped before a task
file was run.

---

## Technical Debt Referenced

<!-- ticfinder_off -->

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

<!-- ticfinder_on -->

---

## References

<!-- ticfinder_off -->

[1] Seznec, A. and Michaud, P. "A case for (partially) TAgged GEometric history
length branch prediction." Journal of Instruction-Level Parallelism, vol. 8,
2006.

[2] Seznec, A. "A 64-Kbytes ITTAGE indirect branch predictor." JWAC-2:
Championship Branch Prediction, 2011.

<!-- ticfinder_on -->

---


---
<!-- ticfinder_off -->

*Jeff Nye is a microprocessor architect with 35 years of industry experience spanning
performance modeling, RTL implementation, and architecture for high-performance OOO
processors. He has contributed RTL to Pentium 4, ARM V7, TI C6x and RISC-V designs, and
recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE
branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through
timing closure at 2.75 GHz. He holds +20 issued patents in processor design,
architecture, and hardware virtualization. He is the author of Pacino and the uarchlabs
methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*

<!-- ticfinder_on -->
