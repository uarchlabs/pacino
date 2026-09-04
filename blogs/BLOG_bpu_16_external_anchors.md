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

## Abstract

The `bp_history` module in the Pacino RVA23 branch prediction cluster
maintains a 256-bit global history, a 32-bit path history, and
twenty-seven folded histories consumed as index and tag inputs by TAGE,
ITTAGE and the statistical corrector. It had been marked complete since
the fourth session of the project. Cluster integration required three
open decisions that only this module could answer, and resolving them
reopened it. Six implementation tasks followed. The module's original
twelve-test bench passed throughout, because the fold window never
filled past its seventh case and every defect lived in the full-window
region. Four defects were found in the fold arithmetic. A testbench task
was abandoned rather than delivered, after the assistant that wrote it
established that its eighteen passing cases and 12,896 passing
assertions were obtained only by writing a reference that matched the
RTL instead of the specification. Two fixes recorded as landed and
lint-clean were then found never to have existed in the same file, so
the combination they formed had never been built or run; merging them
produced a rollback that corrupted the folded history. The proof that
followed compared the design against a reference sharing the design's
own geometry, which established self-consistency and not correctness. A
separate task added three fixed literal constants that a shared error
cannot move with. The durable outcome is that the fold definition now
lives in the project's own authority document, with the external source
it came from reduced to an origin footnote.

## Why a complete module was reopened

The next unit after the FTB was cluster integration, and it was blocked
on three decisions recorded as open in the cluster document: how a
dual-slot update combines within one cycle, what happens when a rollback
and a prediction arrive together, and what the folded outputs mean in
the cycle after a rollback.

All three belong to `bp_history`. Resolving them produced
`bp_history_decisions.md`, a document the module had never had. The
dual-slot update combines slot 0 then slot 1 in one cycle at bundle
granularity. A rollback and a prediction in the same cycle resolve in
favor of the rollback, and the two are mutually exclusive. The folded
outputs in the cycle after a rollback are stale rather than invalid, and
predictions are allowed to proceed on stale folds, which is an accepted
accuracy cost rather than a correctness gate and removes a stall and a
handshake from the cluster interface.

A fourth decision was larger and was not on the list. The module's
interface draft and the RTL as built disagreed about who owns the
history pointer. The RTL took it as an input, so the caller advanced it.
The pointer was ruled module-owned: `bp_history` holds the live global
and path history pointers, advances them by the branch count, exposes
them as registered outputs, and rolls back by checkpoint index rather
than by an externally supplied pointer value. Advance is sequential
only; reset and checkpoint restore are the only non-incremental loads.
The decision was checked against history-recovery practice in earlier
designs, and none surveyed required a non-sequential pointer.
Checkpoint restore applies only to branch-misprediction redirects, which
always land on a checkpointed bundle, so there is no restore case
without a branch.

Implementing that rework was one task. It changed the pointers from
inputs to registered outputs, removed the two rollback pointer inputs,
added a rollback checkpoint index, and moved the advance inside the
module. It needed no package or struct change, and it linted clean. The
testbench could not compile against the new port list, so the history
simulation and coverage targets were waived and deferred to the next
task.

That task reported one thing it was not asked about. The interface
document stated the checkpoint captures the pointer values after the
cycle's advance. The decisions document stated it captures the current
internal pointer pair, which is the value before the advance. The task
followed the decisions document, implemented the pre-advance capture,
and flagged the contradiction for resolution before the testbench wired
its expectations to either reading.

## What the original testbench could not reach

The folded history is a compression of the global history into a
narrower register, updated incrementally as each new branch outcome
arrives and recomputed from the buffer on rollback. The module had
carried four defects in that arithmetic since it was built.

The incremental update inserted the newest bit at fold position 0 rather
than at the high end. The bit leaving the history window was removed at
position 0 rather than at the position the window depth and the fold
width determine. The rollback recompute used a second, inequivalent fold
definition, walking the buffer forward, so a fold rebuilt by a rollback
differed in bit order from the fold the incremental path would have held
at the same pointer. And the fold helper functions were 32 bits wide,
while the statistical corrector's third table has a history depth and a
fold width both equal to 64, which makes its fold unrepresentable.

The module's twelve-test bench passed against all four. It passed
because the fold window never filled past its seventh test case. Every
one of these defects lives in the full-window region, where a bit leaves
the window and the wrap-out term becomes active. A test suite that never
fills the window is not testing the mechanism the folds exist to
implement, and it produces the same green result as one that does.

The defects surfaced during planning for the dual-slot test, not from
running anything.

## The testbench that passed and was abandoned

The task that found them was a testbench task. Its requirement stated
that the incremental dual-slot fold equals a forward linear walk over
the buffer from the bundle-start pointer, and the decisions document
said the same. The RTL did not behave that way. The incremental fold was
recency-ordered, with the newest bit at position 0, which is the exact
bit-reverse of the forward walk.

The evidence was a directed probe on one table with a history depth and
fold width of eight, chosen so the window fills exactly and no fold wrap
occurs. Eight bits written at buffer positions 0 through 7 gave
`0100_1101`. The design produced `1011_0010`. The forward walk produced
`0100_1101`, the original sequence. The two outputs are exact reverses
of each other.

At that point the task had a working testbench. Eighteen cases, 12,896
assertions, all passing, exit clean, well inside the runtime bound. It
passed because the reference had been written to match the design's
actual behavior: recency order for the incremental path, forward order
for the rollback path, one convention each because the design used two.

The task was abandoned rather than delivered. The stated reason is that
a testbench that passes only by encoding the behavior it found, in place
of the requirement it was given, does not satisfy the obligation it
exists to discharge. The two available corrections were both named: fix
the specification to state that the incremental fold is recency ordered
and define the recompute reference to match, keeping the forward walk
only for rollback; or change the RTL so both paths use one ordering. The
second was the one taken.

Three further findings came out of the same investigation, none of them
the abandonment cause. The incremental path and the rollback path using
different orderings was flagged as a design risk in its own right, on
the grounds that history is not literally restored across a rollback if
the restored fold differs in bit order from the fold that was held. The
rollback recompute walking forward from the restored pointer reads
buffer entries written after the checkpoint rather than the history
preceding it. And the 32-bit accumulator against the 64-bit
statistical-corrector fold was identified as a width mismatch between
the datapath and the field it writes.

## One definition

The repair replaced both fold paths with a single definition. The
incremental step became a circular left rotate with the newest bit
exclusive-ORed in at the high end, and the leaving bit removed at the
position determined by the window depth modulo the fold width, which
required passing the depth into the step function. The recompute adopted
the same position mapping the incremental step builds, so that applying
one incremental step to a recompute at one pointer yields the recompute
at the next. That algebraic identity was verified offline across every
history depth and fold width in use, including the case where the two
are equal and the case where the depth exceeds the width.

The fold helpers were widened from 32 bits to 64. The task recorded this
as required rather than cosmetic, with the reasoning stated: at 32 bits
the statistical corrector's third fold loses every bit at position 63,
while the recompute keeps the sub-32 positions, so the two paths cannot
be equivalent for that table at any geometry. No package width parameter
and no structure field changed; the accumulator was the thing that was
too narrow, not the declared width.

The history simulation target was waived for this task and the reason
was recorded rather than assumed. The testbench compiled and ran, passed
its first seven cases, and failed the eighth, because the testbench's
own golden reference still used the old position mapping. A stale
reference failing against a corrected design is confirmation that the
geometry changed as intended.

## Neither file had both

The next task was written as a testbench task, on the premise that both
the pointer rework and the fold repair had landed in the RTL. It stopped
before writing anything.

The active file the Makefile compiles was still the caller-owned pointer
interface. The pointer rework existed only in a copy held outside the
repository tree, and that copy still carried the fold geometry from
before the repair. The task presented the evidence as a comparison of
the ports the design has against the ports the task requires, together
with the version-control history showing no commit had modified the
active file, and a line in the interface document stating that the
as-built RTL was still caller-owned and would change to match. Neither
file on disk held both changes. The combination they were supposed to
form had never been assembled, compiled or run.

Both changes had been recorded as landed and lint-clean, in the session
handoff and in the project status file. Both records were accurate about
each change in isolation and wrong about the state of the design.

Merging them under authorization produced a failure immediately. Rolling
back to a checkpoint that nothing had diverged from changed the folded
value from `0x92` to `0x00`. The cause is that the repaired fold geometry
assumes a decrementing pointer, with the newest bit at the pointer and
older bits at increasing offsets, while the pointer rework and the
interface document both ratify an incrementing pointer. Each change is
correct against its own task. The pair is not.

The correction re-oriented the geometry for an incrementing pointer: the
recompute walks downward from its anchor, and the incremental step
evicts the leaving bit at the write address minus the window depth. The
position mapping and the high-end insertion from the previous repair
were unchanged, which makes this an addressing reconciliation rather
than a geometry change, and no fold value consumed by any table moved.

The checkpoint contradiction reported two sessions earlier was resolved
here, in the opposite direction to the first resolution. The checkpoint
now stores the pointer after the advance, and the rollback recompute
anchors one position behind it, at the newest bit of the bundle. The
reason is not a preference between two documents: it is the only
orientation under which a dual-slot rollback reproduces the fold the
incremental path would have held. The decisions document was corrected
to the interface document rather than the reverse.

The suite that resulted runs thirteen directed cases and 19,224 golden
fold comparisons, covering the single-slot case, the dual-slot case, a
bundle crossing the buffer boundary, and the statistical corrector's
64-bit table explicitly. All twelve behaviors from the original bench
were ported. Three mechanisms were dropped and each was named with its
reason: driving the pointer as an input, driving the rollback pointer
pair, and the assertion that the checkpoint holds the pre-advance value.

## A reference that shared the geometry

The suite proved that the design's incremental path, the design's
recompute path, and the testbench's golden reference all agree. The next
task began by stating what that does not establish. The golden reference
computes its fold using the same position mapping the design uses. Three
things agreeing when two of them derive from the same definition is
self-consistency. An error in that definition would be present in the
reference and would pass.

The intended fix was to derive the expected fold from the table-side
documents, on the reasoning that the tables consuming the fold are an
independent authority for what it should be. That turned out not to
exist. The index and tag hash rule documents for both TAGE and ITTAGE
define how a fold is consumed, giving the hash that combines it with the
program counter, and neither defines how the fold is computed from the
global history. There was no table-side definition to check against.

What the task did instead is the part worth keeping. It computed three
folds by hand from known histories and committed them as fixed literal
constants: `0xE5` for a full eight-bit window, `0x9` for a window only
half filled, and `0xC000_0000_0000_0000` for a 64-bit window straddling
the buffer boundary. Each is checked against the design and against a
from-scratch reference walking an age-indexed history, one that never
reads the history buffer, never reconstructs the design's circular
index, and never calls either fold function. All three matched.

The task also recorded the limit of what it had achieved, which is the
most useful sentence in the range. Because no independent computation
definition existed, its reference necessarily uses the same position
mapping as the design. Structural independence was delivered, but
geometric independence was not. What guarantees the anchor is the fixed
constants, which a later drift in the shared geometry cannot move with,
rather than an arithmetically distinct reference. The three literals are
the anchor. The reference around them is a convenience.

## The definition becomes the project's own

The documentation gap that forced the fallback was closed directly. A
canonical fold definition was added to `bp_history_decisions.md` as a
new section: age indexing with the newest bit at age zero, the position
mapping, the eviction position, the invariant that the recompute equals
the incremental path, and a worked example carrying a known history to
one of the committed literals. The external implementation the geometry
originally came from was reduced to an origin footnote. The project's
own document is now the authority, and the outside source is a citation
of where the idea started rather than a definition the design depends
on.

The final task audited that edit. It confirmed by version-control
comparison that the document was the only tracked file changed, with the
RTL, testbench, packages and Makefile byte-identical to the tagged
state, so that the audit was of a document edit and nothing else. It
resolved all eighteen cross-references after the section renumber. It
matched the new section against the two fold functions line by line. It
re-derived all three committed literals from the section's rules alone,
without reference to the design, and reproduced both the constants and
the design's output. It confirmed the interface document and the
decisions document now agree that the checkpoint is post-advance. And it
ran the full unit at 33 of 33 targets.

It also found one line the audit was not looking for. A later section of
the same document described the cluster as the pointer authority, which
contradicts the module-owned ruling the document itself ratifies. The
line predated the edit under audit and was carried through the renumber
without being re-read. It was reported rather than corrected, under the
standing rule against repairing planning documents in place, and the
architect applied the reword.

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

### What the implementation assistant contributed

The implementation assistant stopped four times in six tasks, and in
each case the stop is what produced the range's result.

It stopped on a contradiction between two authority documents about
checkpoint timing, implemented the reading it was given, and flagged the
other before any test could be written against it. It stopped on a
requirement that contradicted the design it was verifying, and it did
not resolve the contradiction by adjusting the reference. It stopped on
a task premise that was false, with the ports, the version-control
history and a line in the interface document as evidence, rather than
proceeding against a design that could not compile the testbench it was
asked to write. And it stopped on a stale line in a document it was
auditing rather than correcting it in place.

Two of its contributions were analytical. The bit-reverse diagnosis was
reached from a directed probe rather than from a failing comparison,
with the geometry chosen so the window fills exactly and nothing
confounds the reading. And the widening of the fold helpers was
justified against a specific table's parameters rather than adopted as a
precaution, with the reasoning recorded for why the package widths were
correct and the accumulator was not.

The abandoned task is the strongest single item. Delivering it would
have produced a green target, a passing count, and a testbench encoding
the design's behavior as its own requirement. It was reported instead,
with the evidence and two proposed corrections. The second correction is
what the next task implemented.

Its statement of what the external anchor did not achieve belongs in the
same category. Having been asked for a geometrically independent
reference and having found no definition to build one from, it delivered
the structural independence it could, named the property it could not
deliver, and identified which part of its own result carries the
guarantee.

### What the planning assistant contributed

The planning assistant produced the decisions document that resolved the
three cluster-blocking items, and it produced the interface rewrite that
the pointer rework was built against.

Its errors in this range were of one kind. The requirement that
contradicted the design was written into a task after being written into
the decisions document, and neither was checked against the RTL the task
would run against. The task premised on both prior changes having landed
was written without confirming the state of the file it declared
read-only. And the stale line about pointer authority was carried
through a renumber performed for consistency, in a section the edit
touched, without being re-read against the ruling in the same document.

The three have a common shape: an assertion about the state of an
artifact, written without reading the artifact. That is the same
category the range's central defect falls into, reproduced in the
documents rather than in the design.

Against that, the sequencing held. Resolving the three cluster items
before touching the RTL, separating the pointer rework from the fold
repair, and holding the external anchor as a separate task after the
equivalence proof rather than folding it in are all ordering decisions
that survived a range where two of the tasks did not go as written.

### What the architect contributed

The pointer ownership ruling is the architect's, together with the three
cluster decisions and the accepted accuracy cost that removed a stall
from the cluster interface.

The two scope expansions were authorized decisions with the alternatives
on the table. When the merge was found to be impossible under the task's
own constraints, the options were to land the missing change as its own
task and re-run, or to authorize the current task to do both. The second
was taken and the reason is visible in the outcome: the defect the merge
exposed only exists in the combination, and a task that landed the
combination without running it would have reproduced the situation it
was fixing.

Capturing the fold definition into the project's own document was an
architect decision made after the anchor task reported that no
computation definition existed anywhere in the project. It is the
durable outcome of the range, and it was taken as a response to a
reported gap rather than as planned work.

The per-experiment tagging used through this range was scaffolding
against the risk of an unverified state, and it was retired once the
unit was frozen rather than kept as a standing practice.

### The generalization

The range contains four separate results that were true and did not mean
what they appeared to mean.

A twelve-test bench passed against four defects, because it never filled
the window where all four live. An eighteen-case suite passed 12,896
assertions against a reference written to match the design rather than
the specification. Two changes were recorded as landed and lint-clean,
and each record was accurate, while the state they jointly described had
never existed. And a three-way agreement between a design's two paths
and a golden reference held, while two of the three derived from one
definition.

None of these is a false claim. Each is a true claim about a comparison
whose two sides were not independent. The window was never filled, so
the test and the design agreed about a region neither entered. The
reference was derived from the design, so it agreed by construction. The
two records described two files, and the claim they were read as making
was about a third file that did not exist. The golden model shared a
position mapping with the thing it checked.

The previous post in this series argued that a specification is a draft
until something is built against it. This range is the same argument
applied to proofs. A proof establishes something in proportion to the
independence of the thing it compares against, and independence is a
property that has to be checked rather than assumed from the fact that
two artifacts have different names and live in different files. The
golden reference had a different name and a different file. It shared
the one thing that mattered.

The practical form is the three committed literals. A hand-derived
constant is worth less than a model in every respect except the one that
matters here: it cannot move. If the shared geometry drifts, a reference
computed from that geometry drifts with it and continues to agree, while
a fixed constant stops matching. That is the whole of what an anchor
provides, and it is worth writing down even when it is only three
numbers, because three numbers that cannot co-move establish more than a
model that can.

The same reasoning produced the range's durable outcome. The fold
geometry had been specified by citation to an external repository, which
is not a specification, because the cited thing can change and nothing
in the project would notice. Moving the definition into the project's
own document, with a worked example tied to one of the committed
constants, is what makes the geometry checkable without leaving the
project. The audit that followed proved the document reproduces the
constants and matches the code, which is the check the citation could
never have supported.

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

## What comes next

`bp_history` closes this range complete at the unit level and tagged: the
module-owned pointer, one increment-oriented fold geometry shared by
both paths, the definition captured in the project's own authority
document, proven in simulation across 19,224 comparisons, anchored to
three fixed constants, and audited for document-to-RTL consistency. The
full unit runs 33 of 33 targets green.

What remains on it is bookkeeping and cluster-deferred work. The origin
citation needs its identifier filled, the superseded copy held outside
the repository tree should be retired, and the slot-case cleanup waits
for the next task that touches the RTL. The rollback recompute items for
TAGE and ITTAGE are unblocked by the decisions this range resolved but
still need cluster stimulus, and the end-to-end check that carries a
fold through a table's index hash needs the same.

The remaining unbuilt predictor is the statistical corrector, and it
starts from a different position than the units before it. It has no
decisions document and no interface document. What is known about it is
scattered across the cluster document and the project status file: five
tables that are pure counter arrays with no tag bits, an index split
with a separate loop-counter index, one table with no history and one
that is the loop-counter table, and three tables consuming folded
history whose geometry this range made canonical, including the 64-bit
case the fold helpers were widened for. The threshold value and the
update rule are unspecified in any project document, and the first task
is architectural rather than implementation.

---

## References

*No references required for this post.*

---
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*

