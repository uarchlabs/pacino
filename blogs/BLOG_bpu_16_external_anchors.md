<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->

```
TITLE:     "External Anchors: When a Proof and Its Reference Share the Same Error"
FILE:      BLOG_bpu_16_external_anchors.md
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

# External Anchors: When a Proof and Its Reference Share the Same Error

EDITED: 2026-09-21, ticfinder/clarity/length

## Abstract

The `bp_history` module maintains the 256b global history (GHR) and the 32b
path history (PHR), together with the folded history registers consumed by the
TAGE/SC and ITTAGE predictors. It was built early in Pacino development, ahead
of the modules that consume it. Cluster integration required the design to be
re-opened.

Six tasks reworked the unit. The history pointer inputs were pulled inside
the module and an external raw pointer into the history vectors was changed
to an index into a checkpoint array holding the pointers.

Defects were found in the folding logic: in the folding field bounds, and in
narrowing function arguments in the folding functions. Two fold definitions
were combined into one which eliminated that class of error. A single fold
definition is now shared across all fold functions.

These defects had escaped previous detection. The previous tests did not fully
exercise the full fold window. 

I attribute these defects to the absence of a written fold definition. The 
geometry was taken from an external implementation and never recorded in the 
project. The incremental update and the rollback recompute logic 
implemented different schemes. This difference was detected in BP-070.

A complete definition of the folding process based on Seznec's O-GEHL and TAGE
predictors was added to the planning documents as section 6 of
`bp_history_decisions.md`. Golden reference in the form of hand generated expect
data was also added. This broke the inadvertant loop where, in the absence of
guidance, the RTL was used to create the reference for validation.

A final task, BP-074, performed an audit of that section against the RTL and
re-derived all constants from its rules.  `bp_history` closed at the unit
level. The unit runs 33/33 targets, with 19,224 fold comparisons. 

## Implementation with implied requirements as a source of bugs

Pacino's `bp_history` implements the 256b GHR, the 32b PHR and the folding
logic.  The PHR register is implemented but not utilized in the current design.
This implementation is sufficient for early validation with final configuration
of the history module deferred until frontend performance assessment. This is
recorded as TD#128.

The history folding scheme was implemented from external reference material
[1] [2] [3]. This material was accessed twice, when the `bp_history`
module was developed and again when the hashing operations of TAGE and ITTAGE
were checked. The TAGE/ITTAGE implementation were correct but the `bp_history`
implementation was not. The original unit tests did not detect this 
because the fold window was not fully exercised.

No Pacino planning document specified the LSB/MSB for shift in and did not
specify the position of the evicted bit. IA/PA performed external discovery
in the two cases, resulting in incompatible implementations.

Failure to capture the fold geometry explicitly in a Pacino planning document
was a source of the defects and this was discovered and fixed in these
sessions.


## Cluster integration decisions

Cluster integration was dependent on three unresolved decisions:

    - dual prediction slot single cycle operation
        - how is history updated in history modules supporting dual prediction
    - simultaneous prediction and rollback
        - what was the expected behavior when a rollback and a prediction 
           occur in the same cycle
    - how to interpret the folded outputs in the cycle following a rollback
        - the outputs will be stale, should the design stall or accept
          precision loss using stale folded outputs.

These decisions were captured in a new planning document
`bp_history_decisions.md`. The decisions were:

    - dual prediction slot single cycle operation
        - straight forward two bit update with slot 0 first, then slot 1
    - simultaneous prediction and rollback
        - rollback is given priority, the prediction update is dropped.
    - how to interpret the folded outputs in the cycle following a rollback
        - to avoid the stall a loss in prediction accuracy is accepted.

The decisions document is where the assumption that the two fold paths agreed
entered the record. Section 3.3 required the incremental update to equal the
recompute, and named the recompute's linear walk as the reference order. The
recompute was defective, and BP-071 later replaced both paths with a
single definition. The section recorded the equivalence as not yet proven.

Another integration gating decision was management of the history pointer.  In
the orignal design the GHR and PHR pointers were primary inputs to the history
module and managed outside. Similarly the rollback pointers were supplied. This
was simplified by moving pointers and their management into the history module.
The gap in this case was not in the planning document but in execution. The RTL
had the exposed pointers. Rollback by checkpoint index was a new decision. In
this session the internal pointer logic was implemented in BP-069.

BP-069 changed the pointers from inputs to registered outputs. It also removed
the two rollback pointer inputs replacing these with a rollback checkpoint
index.  Finally moved the advance inside the module. Simulation and coverage
was waived until BP-072.

BP-069 reported a discrepancy between the interface and decisions documents.
The interface document specified the checkpoint captures the pointer values
after the cycle's advance. The decisions document specified capture of the
current internal pointer pair, before the advance. The task implemented the
decisions document's reading and flagged the contradiction before any test
could be written against either one.

## The four defects

The defects discovered in these sessions were:

    - newest history bit inserted at the wrong end of the fold
    - evicted bit removed at the wrong position
    - rollback recompute used a second fold definition, so a fold rebuilt by
      a rollback differed in bit order from the incremental fold
    - fold helper functions were 32 bits wide, and the statistical
      corrector's third table requires 64

These were caused by imprecision/gaps in the planning document.[F1]

## Discovering the bugs

The defects were found by directed probe during BP-070, a testbench task
meant to prove decisions section 3.3: that the incremental fold over a
two-slot bundle equals a forward linear walk of the buffer from the
bundle-start pointer. The probe used one table with history depth and fold
width both 8. At H = W the window fills exactly and the wrap-out term is
inactive, so any disagreement between the paths comes from bit ordering
alone.

Eight single-slot updates wrote `0100_1101` to buffer positions 0 through 7.
The forward walk returned `0100_1101`. The incremental path returned
`1011_0010`, the exact bit reverse, which is what insertion at the wrong end
of the fold produces. The two paths implemented opposite orderings.

The IA had also built a testbench that passed 18 cases and 12,896
assertions, because its reference model reproduced the RTL. Any reference
derived from the DUT will obviously agree with the DUT. The IA reported the
deviation in its results summary. A review confirmed it, and the task was abandoned and
reverted.

Of the two corrections the IA proposed, changing the specification would have
left the two paths in different bit orders, so a rollback would not restore
the fold that was held. The RTL was changed instead, in BP-071, so both paths
share one ordering.

The investigation also found that the recompute read buffer entries written
after the checkpoint instead of the history before it, and identified the
32-bit accumulator as the fourth defect listed above.

### A single project definition

BP-071 replaced both fold paths with one definition. The incremental step is
a circular left rotate with the newest bit XORed in at the high end and the
leaving bit removed at (H-1) mod W. The recompute uses the same position
mapping, so one incremental step applied to the recompute at one pointer
yields the recompute at the next. That single-step identity was verified
offline for every (H, W) pair in use, including H = W and H > W.

The fold helpers were widened from 32 to 64 bits. At 32 bits the 64-bit fold
of the statistical corrector's third table cannot be represented, and the
two paths drop different bits of it, so they cannot agree for that table. The
package widths were already correct. Only the accumulator was too narrow.

The history simulation target was waived. The testbench passed its first
seven cases and failed the eighth, because its own golden reference still 
used the old position mapping. That failure confirms the geometry changed.
The offline identity is what establishes that the new geometry is
self-consistent.

### Merging the changes and anchoring the reference

BP-072 was written as a testbench task, on the premise that the pointer
rework and the fold repair were both in the RTL. They were not. The file the
Makefile compiles still had the caller-owned pointers. The pointer rework
existed only in a copy outside the repository, and that copy predated the
fold repair. Both changes had been recorded as complete and lint-clean. Each
record was accurate about its own change. The combination had never been
compiled or run.

Merging them failed on the first rollback. Rolling back to a checkpoint
nothing had diverged from changed the fold from `0x92` to `0x00`. The fold
repair assumed a decrementing pointer. The pointer rework used an
incrementing one. Each change was correct against its own task, and the pair
was not. Re-orienting the fold addressing for an incrementing pointer fixed
it without changing any fold value a table consumes.

The same task settled the checkpoint question from BP-069 in the opposite
direction: the checkpoint stores the post-advance pointer. That is the only
orientation in which a dual-slot rollback reproduces the fold the
incremental path would have held.

The resulting suite runs 13 directed cases and 19,224 golden fold
comparisons, covering single-slot, dual-slot, a bundle crossing the buffer
boundary, and the statistical corrector's 64-bit table.

That suite shows the two fold paths and the golden reference agree. The
golden reference uses the same position mapping as the design, so the
agreement is self-consistency. It cannot detect an error in the mapping.


BP-073 set out to derive the expected fold from the TAGE and ITTAGE
documents, as an authority independent of `bp_history`. Those documents
define how a fold is consumed by the index and tag hashes. None defines how
the fold is computed. There was no independent definition to check against.

The task instead computed three folds by hand from known histories and
committed them as constants: `0xE5` for a full 8-bit window, `0x9` for a
half-filled window, and `0xC000_0000_0000_0000` for a 64-bit window crossing
the buffer boundary. The design matched all three. A reference computed from
the shared geometry follows any later change to it. A fixed constant does
not, so the constants are what detect drift.

## Specifying the fold inside the project

The fold had no definition inside the project, and each artifact that needed
one filled the gap locally. The RTL had two, one per path. The decisions
document adopted the recompute's order and required the incremental path to
match it. The IA's first testbench reproduced the RTL. None of these could be
checked, because the definition they approximated was outside the tree.

Consulting an external source leaves nothing behind. Later there is no record
of what was read. A second reading cannot be compared with the first, and a
test has nothing to cite.

Section 6 of
`bp_history_decisions.md` was added to define the fold characteristics: age indexing with the newest
bit at age zero, the position mapping, the eviction position, the invariant
that the recompute equals the incremental path, and a worked example that
reaches one of the committed constants. 
            

BP-074 audited the section by re-deriving all three constants from its rules
alone, without reference to the design, and reproduced both the constants and
the design's output. The full unit ran 33 of 33 targets.
## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| BP-069 | bp_history reworked to the module-owned pointer, rollback by checkpoint index | PASS | lint gate clean; all non-waived targets green | 9m 54s | 11% |
| BP-070 | Dual-slot testbench; specification contradicted the RTL fold ordering | ABANDONED | 18/18 cases, 12896 assertions (investigation only, reverted) | -- | -- |
| BP-071 | Single fold definition for both paths; three geometry defects fixed; helpers widened to 64b | PASS | lint gate clean; sim_history waived on stale golden | 16m 47s | 18% |
| BP-072 | Merge of the two prior tasks; incremental-versus-recompute divergence found and fixed; testbench rewritten | PASS | 13 cases, 19224 fold comparisons, 33/33 targets | 32m 38s | 31% |
| BP-073 | External fold anchor; three literal constants committed; documentation gap identified | PASS | 16 cases, 3 anchors, 33/33 targets | 14m 14s | 16% |
| BP-074 | Consistency audit of the canonical fold definition against the RTL and the anchors | PASS | 6/6 requirements, 33/33 targets | 6m 53s | 14% |

## Design Process Notes

### The IA contribution

BP-070 stopped when its requirement contradicted the design.
It had a passing testbench, but the testbench's reference reproduced the
RTL. The IA reported that the bench did not prove the requirement. BP-072
stopped when its premise was false. The pointer rework and the fold repair
were not in the same file, and it showed this with the port list and the
version-control history.

The BP-072 stop also contains the most useful single behavior in these
sessions. Asked to confirm that the copy of `bp_history.sv` held outside the
repository was the expected version, the IA read it before using it. The copy
still carried the old 32-bit fold geometry, and copying it in would have
silently undone BP-071.

BP-069 completed its change and flagged the checkpoint-timing contradiction
between the interface and decisions documents. BP-074 completed its audit and
reported a stale line in the decisions document without editing it, as the
project rules require.

### The PA contribution

The planning assistant wrote the decisions document that resolved the three
cluster-blocking items, and the interface rewrite the pointer rework was
built against.

Its errors were assertions about an artifact written without reading the
artifact. The section 3.3 requirement went into the decisions document and
then into BP-070 without being checked against the RTL. BP-072 was written on
the premise that both prior changes were in the RTL, without checking the
file. A line in the decisions document naming the cluster as the pointer
authority, which contradicted the document's own module-owned ruling, was
carried through a section renumber without being re-read.

The sequencing held. The cluster items were resolved before the RTL was
touched. The pointer rework, the fold repair and the reference check were
kept as separate tasks.

### My contribution

I contributed judgement calls and two mistakes.

I made the pointer ownership ruling and the three cluster decisions, including
accepting an accuracy cost on stale folds to avoid a stall.

The false premise in BP-072 most likely began with me. The BP-069
RTL was not copied into the repository after that task closed, and the task
records did not show it.

BP-072 needed two scope expansions, both authorized with the alternatives
stated: merging the two changes into the active RTL, and correcting the fold
orientation after the merge failed. Keeping the merge in the same task
mattered, because the defect existed only in the combination.

I made the initial call not to define the folding operations in a planning
document on the assumption they were rote and well known. That may be true in
general, in hindsight it would have been better to define them explicitly.
The definition went into section 6 after BP-073 reported that none existed in
the project.

### The generalization

The twelve-test bench never filled the fold window, so it did not exercise
the region where the defects were. The task records for the pointer rework and
the fold repair each described their own change correctly, and neither
described the file the design was built from.

The eighteen-case bench passed because its reference reproduced the RTL, and
the golden reference that followed it used the design's own position mapping.
Both follow from the missing fold definition. When a specification does not
state the expected value, a generated reference takes it from the only source
available, the design under test.

For work divided between an architect and AI assistants, a definition taken
from an outside source has to be written into the project before it is used.
Consulting the source leaves no artifact. Later work cannot be checked
against it, and each artifact built from it can be compared only with the
others.

In these sessions that meant section 6 of `bp_history_decisions.md` and three
hand-derived constants in the testbench. The section defines the fold. The
constants check the design against values that do not change when the
design does.

## What comes next

`bp_history` closes this range complete at the unit level and tagged: the
module-owned pointer, one increment-oriented fold geometry shared by both
paths, the definition captured in the project's own authority document,
proven in simulation across 19,224 comparisons, anchored to three fixed
constants, and audited for document-to-RTL consistency. The full unit runs 33
of 33 targets green.

What remains to be done are bookkeeping and cluster-deferred work.
 The rollback recompute items for TAGE and
ITTAGE are unblocked by the decisions these sessions resolved but require
cluster stimulus, and the end-to-end checks.

The remaining unbuilt predictor is the statistical corrector[F2].  The SC required decisions and interface documents.

## Technical Debt Referenced

The table below reports status as of the close of this range. Later
experiments outside the range have since changed the state of some items
carried alongside these.

| # | Item | Resolution path |
|---|---|---|
| 74 | Dual-slot configuration testing, tracked separately from the slot-count reduction. | bp_history part CLOSED BP-072. The dual-slot fold equivalence is proven in simulation, incremental against recompute, for the single-slot case, the dual-slot case, the buffer-boundary wrap and the 64-bit statistical corrector table. The broader cluster dual-slot work remains deferred. |
| 82 | bp_history if/else-if slot-case cleanup. | decisions.md 3.5. No behavior change. Scoped out of the fold repair, which was limited to fold arithmetic, and out of the merge task, which minimized deviation from reviewed logic. Fold into the next bp_history RTL touch or a small cleanup task. |
| 83 | bp_history decisions.md origin citation placeholders. | Fill the external commit identifier and capture date in the origin footnote. Informational only; the canonical section is the authority, not the citation. Manual, low priority. |
| 84 | Producer and consumer end-to-end fold check. | BP-073 proved the fold VALUE against the canonical definition and three committed literals. It did NOT run that fold through the TAGE or ITTAGE table index hash to confirm the derived index. The table hash-rule documents define fold consumption only, which is the gap that forced the fallback. Needs cluster stimulus. |
| 69 | tage rollback and history recompute. | The blocking cluster decisions are resolved. Still deferred to bp_cluster, which is where the rollback stimulus exists. |
| 70 | ittage rollback and history recompute. | Same as #69 for ITTAGE. |

## References
<!-- ticfinder_off -->

[1] A. Seznec, L-TAGE branch predictor source, folded_history class, IRISA.
https://www.irisa.fr/caps/projects/Architecture/L-TAGE.h

[2] A. Seznec, "Analysis of the O-GEometric History Length Branch
Predictor," ISCA-32, 2005, pp. 394-405.

[3] Y. Xu et al., "Towards Developing High Performance RISC-V Processors
Using Agile Methodology," in Proc. 55th IEEE/ACM International Symposium on
Microarchitecture (MICRO), 2022, pp. 1178-1199. DOI:
10.1109/MICRO56248.2022.00080
<!-- ticfinder_on -->

## See Also

<!-- ticfinder_off -->
A. Seznec and P. Michaud, "A Case for (Partially) TAgged GEometric
History Length Branch Prediction," JILP, vol. 8, 2006, pp. 1-23.

A. Seznec, "A 256 Kbits L-TAGE Branch Predictor," JILP, vol. 9, 2007.

P. Michaud, "A PPM-like, Tag-based Branch Predictor," JILP, vol. 7,
2005.

A. Seznec, "TAGE-SC-L Branch Predictors," CBP-4, 2014.
<!-- ticfinder_on -->

## Footnotes

<!-- ticfinder_off -->
[F1] The source of the Pacino problem was that bit order was not specified.
But I have noticed confusion in LSB/MSB assignment in other cases. In general
this problem occurs often enough to require some care.

[F2] At the close of this range the statistical corrector was unbuilt and had
neither a decisions document nor an interface document. It has since been built
-- `sc.sv`, `sc_table.sv`, `sc_cntrl.sv` and `sc_brimli.sv` -- and
`sc_decisions.md` exists.
<!-- ticfinder_on -->

---
<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->

