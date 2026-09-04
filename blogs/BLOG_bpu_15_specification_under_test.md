<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->

```
TITLE:     "Specification Under Test: What Bringup Proves About the Document"
FILE:      BLOG_bpu_15_specification_under_test.md
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

# Specification Under Test: What Bringup Proves About the Document

## Abstract

The Pacino RVA23 branch prediction cluster contains seven predictors. Two
of them, the return address stack and the fetch target buffer, were
brought from planning document to verified unit across four sessions and
ten implementation tasks. The two received unequal specification effort
before any RTL was written. The RAS had two planning documents authored
in the same session as its RTL and its testbench. The FTB had an
architectural decision pass, then an entire session that regenerated
three planning documents, ruled the last open entry widths, and verified
that every shared parameter resolved identically across all three
documents before the first line of RTL was drafted. Neither document set
was correct. The RAS testbench found two RTL defects during bringup, one
of which could not be fixed as first proposed without giving up the
invariant that makes pointer-only misprediction recovery work. The FTB
build reopened its storage partition, redefined its confidence field,
moved its entry width three times, and found a stored field with no
producer. Both units closed with their documents reconciled to the RTL as
built and promoted to Complete, at 87 and 99 directed checks. The
transferable result is that a specification acquires its errors from
never having been built against, and the session of document work
between the two did not change that. It also produced the range's
clearest defect: a repair operation labelled "push" in a table, where the
correct behavior was a pointer move over a still-resident entry, and the
implementation followed the label into an allocation path.

## Two units, two amounts of document work

The RAS and the FTB sit at the same pipeline stage, s2, alongside TAGE
and ITTAGE. Both were unbuilt when this range opened. What differed was
how much specification work preceded the RTL.

The RAS planning documents, `ras_decisions.md` and `ras_interfaces.md`,
were written in the same session that produced `ras.sv` and `tb_ras.sv`.
They record the decisions that had been open in the cluster document:
a static partition of 16 speculative and 32 commit entries, a 4-bit
recursion counter, a fixed boundary bundle split, slot 1's PC as
`pred_pc+32`, and a simple circular buffer as the internal structure.
`ras_interfaces.md` was corrected inside that session to the array-form
port list, where the slot dimension is `[0:NUM_PRED_SLOTS-1]` rather than
a `_p0`/`_p1` suffix, because the p-stage suffix names the pipeline stage
and the two conventions collide.

The FTB took three sessions before any RTL. The first produced a decision
record covering structure, sizing, the entry format, the ITTAGE-miss
target fallback and a confidence override policy. The second was a
recovery pass. The material from the first had been built on a structural
model that had been rejected: the per-slot RAM decision from the TAGE
work was applied to the FTB, 64-bit virtual addresses were used where the
project uses `VA_WIDTH=40`, a two-byte instruction granularity was
carried into the offsets from a surveyed design rather than derived
from Pacino's expanded-instruction layout, a bit that had been
eliminated was retained, and the width item was marked closed carrying
wrong values. `ftb_interfaces.md` was regenerated from `ftb_decisions.md`
to a single array, a single update port, `VA_WIDTH=40` and a 26-bit full
tag.

Two rulings came out of that recovery. The predicted way and hit are
determined at the prediction read and carried through the FTQ, which
removes the update-side tag re-lookup entirely. And a fallthrough error
check was ruled out. Such a check guards against a hit on the wrong
entry, which is reachable only under a truncated tag; the full 26-bit tag
makes it unreachable here. The FTB is not made defensive against its own
corrupt state. A restore guard was recorded with the ruling: any
reinstated fallback is `start + FTB_BLOCK_BYTES`, never a value derived
from the fetch width.

The last item blocking RTL was the entry widths, and they closed at the
end of that session: `FTB_BR_POS_BITS=3`, `FTB_BR_TGT_BITS=13`,
`FTB_JMP_TGT_BITS=21`, `TAR_STAT_BITS=2`, giving `ENTRY_WIDTH=108` and
`SET_WIDTH=432`. The reasoning separates two classes of width. Position
and `pftAddr` depend on instruction granularity, which is a Pacino
property, and are derived here. Target displacements follow from ISA
reach: a B-type branch reaches plus or minus 4 KB, which becomes plus or
minus 8 KB under the expanded-instruction layout and needs 13 bits; a
J-type jump reaches plus or minus 1 MB, which becomes plus or minus 2 MB
and needs 21 bits. `ftb_decisions.md` section 4.4 had carried a blanket
instruction not to take any width from a reference design, which was too
broad, since the ISA reach is the same quantity whoever encodes it.

The session closed with cross-document consistency verified: every shared
parameter resolving to the same value in all three documents, the entry
and set widths stated identically in the decisions and the interfaces,
and the confidence width named in all three. The three documents were
declared build-ready.

## The RAS defect that the invariant decided

`ras.sv` was implemented as a single self-contained module: two
register-file stacks, a p0 top-of-stack read, p2 dual-slot push and pop
with slot 0 ordered before slot 1 and a same-cycle call-to-return bypass,
a recursion counter, post-operation snapshots, pointer-only misprediction
restore, p3 repair, and a commit stack with an empty fallback. It linted
clean.

The testbench found the first defect immediately. After reset,
`tosr`, `tosw` and `bos` are all zero. A push writes at `tosw`, sets
`tosr` to the old `tosw`, and advances `tosw`. After one push from reset,
`tosr` is 0, `tosw` is 1, and `bos` is 0. Emptiness is tested as
`tosr != bos`. With one live entry, `tosr` and `bos` are both 0, so the
stack reads empty. The test cannot distinguish zero entries from one.
The consequences were that a single entry was invisible at p0, a
subsequent pop fell through to the commit stack, and the bottom-most
speculative entry could never be popped. The first run was 10 passing
and 6 failing.

The implementation assistant stopped, reported, and offered three fixes.
The planning assistant selected the first: change the emptiness test to
`tosw == bos`, described as the smallest RTL change.

That recommendation was wrong, and the implementation assistant said so
before implementing it. A pop decrements only `tosr`. `tosw` is monotonic
by design, which is what preserves popped entries in the circular buffer
so that a misprediction can be recovered by restoring three pointers with
no data replay. `ras_decisions.md` section 3.2 states it directly: no
data is overwritten on pop. With a monotonic `tosw`, an emptied stack
still has `tosw` at the frontier and `bos` at the floor, so `tosw == bos`
would report non-empty when the stack is empty. Making that test correct
requires the pop to decrement `tosw` as well, which makes `tosw`
non-monotonic and gives up pointer-only restore. A wrong-path pop
followed by a push could then overwrite a still-live entry, and a later
restore would re-expose corrupted data.

The revised diagnosis is narrower than the original. `tosr == bos` is the
semantically correct emptiness test. The defect is only that the first
push lands on the `bos` slot, which makes one entry indistinguishable
from none. That points at the allocation, not the test.

The choice then carried a real cost, and it was the architect's. Re-base
allocation keeps the emptiness test and treats the `bos` index as a
permanent sentinel: a push that would land on `bos`, which happens only
at cold start or a full wrap, allocates at `bos+1` instead. Reset values
are unchanged, `tosw` stays monotonic, and the usable speculative depth
becomes 15 rather than 16. The alternatives were the literal first
option, which keeps 16 entries and passes every directed test while
leaving a latent corruption path the directed suite does not cover, or an
explicit empty count, which keeps both depth and restore semantics at the
cost of more state and a larger change. Re-base allocation was selected
on the grounds that the monotonic `tosw` invariant is foundational and
in-flight call depth under realistic workloads is well under 15. The
allocation sites compute
`w_alloc = (w_tosw == bos) ? (w_tosw + 1) : w_tosw`.

## A repair operation named after the wrong thing

The second defect was found by TC-17 after the first fix landed, at 77
passing and 2 failing.

The p3 repair path `rep_push` covered two rows of the IC-RAS-11 repair
table with identical logic. One row is a missed push, where p2 was a
no-op and p3 resolves a call: a real entry is absent and allocating one
at the frontier from the registered fallthrough is correct. The other row
is an undo-pop, where p2 was a pop and p3 disagrees: a pop happened that
should not have, and the entry it consumed is still physically resident,
because pop does not overwrite. Undoing it means moving `tosr` back and
reloading the address and recursion count from the array. There is no
entry to create, and the registered fallthrough is not a call return
address.

The implementation allocated in both cases. TC-17 seeded one entry at
index 1, popped it, and forced p3 to disagree. The expected state was
`tosr=1` with the top reading `0x9000`. The observed state was `tosr=2`,
`tosw=3`, with the top reading `0x0000`.

The cause is in the document. Both `ras_decisions.md` section 1 and
IC-RAS-11 label the undo-pop repair as "push". In that table "push" means
restoration of stack height over a still-resident entry, and the same
applies in the other direction, where undo-push is a `tosr` retract of a
still-resident frontier slot rather than a data clear. Only the
missed-push row allocates and writes. The bare label routed the
implementation into the allocate path, and nothing in the document
contradicted it.

The fix splits `rep_push` on the registered p2 operation. When it was a
pop, the repair performs a `tosr`-only re-expose with no array write and
`tosw` held. When it was a no-op against a resolved call, the frontier
allocation is kept. The suite closed at 79 of 79, with all 22 Makefile
targets exiting zero.

The fix left one behavior unreversed. A pop that only decremented a
recursion counter, holding `tosr`, cannot be undone, because the pre-pop
recursion count is not recoverable from post-pop state. That became
TD #78.

## The reconciliation round

BP-064 changed no RTL. It ran as a single pass that fixed the documents,
added one test, and re-ran the suite, so that documents, RTL and tests
were proven aligned together rather than separately.

One item was reversed before the task ran. The commit-stack recursion
counter had been recorded as a defect to fix: `ras_decisions.md`
section 5 states the counter is updated when a recursive call commits,
and the RTL writes zero on every commit push. The field turned out to be
write-only, never read by any output path, and the commit interface
carries no recursion count to forward. A wrong value degrades a fallback
prediction and cannot cause a functional break. It was re-scoped to a
deferral, TD #79, and `ras.sv` was left unchanged.

TC-21 pins TD #78 rather than fixing it. It asserts the current
non-reversing behavior in eight checks, including the two intermediate
states, so that a later change to the recursion-pop path fails at the
step that changed rather than at the end. Both TD entries were filed by
hand before the task ran, section 5 was hand-reconciled first, and the
pinned values were verified against the RTL by hand and matched.

The document edits followed the RTL as built: section 3.2 gained the
sentinel rule and the 15-entry usable depth, sections 1 and 1.2 gained
the repair-label semantics and the TD #78 limitation note, sections 3.3
and 4.5 recorded that BOS on commit advances to the committing entry's
post-operation `tosr` with restore winning over commit, and IC-RAS-11
gained the same repair-semantics clarification. `sim_ras` closed at 87
of 87.

## Building against a document that had been checked

The FTB build ran four tasks in planned order, array then control then
structural top then testbench, and three more that were not planned.

The first task found the FTB parameter block in `bp_defines_pkg.sv`
syntactically broken: five localparams missing semicolons, a duplicate
`FETCH_BLOCK_BYTES` definition, and a placeholder entry width built from
the wrong fields. One error was substantive rather than mechanical.
`FTB_TAG_BITS` was derived from `FETCH_BLOCK_BYTES`, which is 64, rather
than from `FTB_BLOCK_BYTES`, which is 32. That collapses the FTB block
into the fetch width, which `ftb_decisions.md` section 2.3 explicitly
bans. The whole block was rewritten and the tag is now derived from
`FTB_OFFSET_BITS`. The task had also been directed to change `FTB_WAYS`
from 8 to 4; the package already read 4, and it was the documents that
were stale.

`ftb_array` was built with a combinational read and a synchronous write.
That gives read-old-on-collision without a state element, which is the
behavior the specification requires, and leaves a registered 1R1W SRAM a
valid substitute.

The storage partition was then reopened. `ftb_array` was reduced to pure
data RAM with no reset and active-low enables, and a new `ftb_plru` was
created to hold, per set, the four entry-valid bits and the three
tree-PLRU bits in resettable flops, 3584 flops in total. The reason is
migration: the data array becomes a substitutable SRAM macro with no
reset, and validity lives in flops, because the FTB has no `sram_init`
mechanism. This split the width into a logical value and a RAM value,
`FTB_RAM_ENTRY_WIDTH=107` against the logical 108.

`ftb_cntrl` took the whole of the logic: prediction read, way match
against the array tag and the PLRU valid, tree-PLRU victim selection,
branch-type classification, fallthrough reduce and reconstruct,
allocation and eviction on the carried way, update field writes, and the
confidence output. It drives both storage peers and instantiates neither.

It also made a decision the prompt did not cover. Each storage module
exposes one read port. An update needs the carried way's current entry,
because confidence training and the stored target are read-modify-write,
and it needs the set's current PLRU state to compute the mark-used
next state. So an active update borrows both read ports, addressed by the
carried set index rather than by a tag re-lookup, which keeps the
carried-way rule intact. Update has priority, and a prediction in the
same cycle self-bubbles. The justification given is that the FTB already
costs a bubble at s2 and that update-channel scheduling belongs to the
FTQ, which does not exist yet. One consequence falls out without being
written: because a prediction cannot be granted while an update is
active, the prediction-hit PLRU touch and the update touch are mutually
exclusive on the single PLRU write port, so update-wins holds with no
explicit arbitration.

The same task reported a gap it was not asked to look for. The in-block
position field is stored in the entry, and the update port carries no
position to write into it. It stored zero and said so.

## Two design points reopened, and the width

The confidence field was then redefined. It had been specified as a
saturating counter that suppresses TAGE and SC direction overrides above
a threshold, sitting alongside an `always_taken` bit. It became a bimodal
direction counter, where the most significant bit is the predicted
direction, with `always_taken` deleted and threshold suppression replaced
by a fast path that acts only at the saturated endpoints. The
`FTB_CONF_SUPPRESS_THRESH` and `FTB_CONF_INIT` parameters were removed
and separate taken and not-taken weak-init values added. The correctness
comparison and its input were removed with them, because training is now
against the resolved outcome directly.

The position field was then sourced and sunk: a producer on the update
port and three consumers at p2, written only on allocation or free-field
fill and preserved on an in-place update, closing FTB-4.

The entry width therefore moved three times inside one session. It was
ruled at 108 over a 432-bit set at the close of the specification
session. It was confirmed at 108 by the array task. It was split into a
logical 108 over a RAM 107 by the storage partition. It became a logical
106 over a RAM 105 when `always_taken` was deleted, with the set at 424
and the RAM set at 420. The three documents were reconciled to the
as-built RTL at the end of the session, and `ftb_decisions.md` was
promoted from Draft to Complete at that point and not before.

The structural top was written between the two reopenings. It contains
three instances and the nets that wire them, with named connections
throughout, `clk` to all three and `rstn` to the PLRU and control
modules but not to the array, which has no reset. It was then revised
twice by the two lettered tasks that followed it, which carry lower
numbers. The RTL is correct; the record of the task that produced it no
longer describes the file.

## The FTB testbench

`tb_ftb` drives the structural top through its ports only, with no
hierarchical reference into any of the three leaf modules, which keeps
the array-substitution property honest. It runs 99 checks in five groups:
the confidence-init invariant, direction and training, the fast path,
structural behavior, and the position round trip.

Two properties of its construction are worth stating. Every expected
target and fallthrough value is derived inside the testbench by
replicating the encode and reconstruct arithmetic, rather than being
written down as a constant. And the tree-PLRU victim in the eviction test
is derived from the documented touch function over a known allocation
order, arriving at way 0, rather than read off whatever the state
happened to be. The victim is sampled from a clean allocation sequence
before any hit prediction perturbs the state, because a miss does not
touch PLRU.

Three items are waived with citations rather than left silently
untested: flush, which has no protocol; the FTQ round trip, because the
carried way's predict-to-update timing needs an FTQ that does not exist
and no FTQ model was fabricated to stand in for it; and same-cycle
predict-and-update arbitration beyond the separate-cycle sequencing the
suite uses. The suite closed at 99 of 99, with the full unit green.

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| BP-062 | ras.sv implemented; RAS parameter block replaced; authorized tb_bp_pkg.sv width fix | PASS | 9 lint / 12 sim green | 15m 8s+ | 15% (understated) |
| BP-063 | tb_ras.sv, 20 directed cases; two ras.sv defects found and fixed under authorization | PASS | 79/0, 22/22 targets | 21m 12s | 22.4% |
| BP-064 | RAS verification and reconciliation round; TC-21 pins TD #78; no RTL change | PASS | 87/0, 22/22 targets | 8m 16s | 15% |
| BP-065 | ftb_array; FTB parameter block found broken and rewritten | PASS | 10 lint / 13 sim green | 6m 57s | 10% |
| BP-065a | Storage split finalized; ftb_array to pure RAM, ftb_plru created | PASS | 11 lint / 13 sim green | 4m 51s | 10% |
| BP-066 | ftb_cntrl, all FTB logic; shared read-port borrow; position gap reported | PASS | 11 lint / 13 sim green | 14m 11s | 18% |
| BP-066a | Confidence redefined to bimodal direction; always_taken removed; widths to 106/105 | PASS | 13 lint / 13 sim green | 7m 8s | 12% |
| BP-066b | In-block position sourced and sunk, FTB-4 closed | PASS | 26/26 targets | 5m 3s | 9% |
| BP-067 | ftb structural top; later revised by BP-066a and BP-066b | PASS | 26/26 targets | 2m 57s | 9% |
| BP-068 | tb_ftb self-checking directed suite against the top | PASS | 99/0, 27/27 targets | 18m 13s | 22% |

BP-062's context figure is the value recorded in its header. The task's
own context report states that the measurement predates a large document
load in the same session and that actual usage was higher.

## Design Process Notes

### What the implementation assistant contributed

The implementation assistant produced all the RTL and both testbenches in
this range, and it stopped rather than proceeding on four occasions where
the task as written could not be executed as written. It stopped on a
prompt that directed it to add parameters that already existed with wrong
values. It stopped before touching a file outside its manifest when a
package width change broke hardcoded literals in it. It stopped on each
of the two RAS defects and reported before changing anything.

Two contributions were analytical rather than procedural. The first is
the retraction described above: presented with its own three options and
told to implement the one that had been chosen, it re-derived the
consequence against the monotonic pointer invariant, established that the
chosen option would trade a latent corruption path for a passing suite,
and said so before writing code. The second is the FTB read-port
question, where a single read port on each storage module and a
read-modify-write update path is a conflict the specification does not
resolve, and the resolution given is bounded and justified against the
stage the FTB already occupies.

It also reported three things it was not asked about: the broken FTB
parameter block and specifically the tag derived from the wrong block
size, the stored position field with no producer, and the stale
`FTB_WAYS` value in the documents rather than in the package.

Its failure mode in this range differs from the one recorded in the
previous range. Here it followed a document label rather than a document
rule. The IC-RAS-11 table says the undo-pop repair is a "push", and the
implementation used the allocate path that word names. The rest of the
document supports the correct reading, and the label was the only thing
pointing the other way.

### What the planning assistant contributed

The planning assistant sequenced both bringups, and the FTB ordering held
under a build that reopened two design points: array first because it has
no dependencies, control next, structural top after, testbench against
the top rather than against the internals.

Its errors in this range were in preparation and in analysis. The BP-062
prompt was written without reading `bp_defines_pkg.sv`, which is what
produced the first stop. The recommendation on the RAS emptiness test was
made without checking it against the invariant that the same document
states, and was retracted by the implementation assistant rather than by
its author. The FTB material produced in the first architecture session
was built on a structural model that had already been rejected, which
cost the whole of the following session to correct. And the target
displacement widths were derivable throughout from ISA branch and jump
reach, but were carried as open across several document regenerations
and were ruled only when the architect required it.

The two lettered tasks that revised the structural top after it had been
produced are a numbering error with a bookkeeping consequence: the task
record no longer describes the file it created, though the file itself is
correct.

### What the architect contributed

Every expected value in both testbenches originated with the architect,
as did both defect fixes. The choice of re-base allocation over the two
alternatives was made against a stated invariant with a stated cost, one
entry of speculative depth, rather than against which option passed the
suite. The `tosr`-only re-expose was chosen with the accompanying
instruction that the repair table's wording be corrected so the authority
document stops carrying the ambiguity that produced the defect.

The reversal of the commit-stack recursion counter from a fix to a
deferral was made after the field was established as write-only and the
commit interface was established to carry no source for the value. Both
technical debt entries were filed by hand before the reconciliation task
ran, one document section was hand-reconciled first, and the pinned
values in TC-21 were checked against the RTL by hand before the run.

The FTB storage split and the confidence redefinition were both architect
decisions taken during the build rather than during the specification
sessions that preceded it.

Two process rules also came from the architect. A per-task constraint
that the implementation assistant writes only within the results markers
was added after it edited a discussion block, stated per task rather than
as a global rule. When that constraint collided with the separate rule
requiring the implementation assistant to fill the model field in the
task header, an explicit exception was added rather than leaving two
rules in contradiction. And when a task edited `PROJECT_STATUS.md` under
prompt authorization, the ruling was that this stays a per-prompt
decision rather than becoming a standing rule, because the file's size
argues against loading it into every manifest.

### The generalization

The FTB received three sessions of specification work before its first
line of RTL, one of them spent entirely on finding and correcting errors
in the specification produced by the one before it, ending with every
shared parameter verified identical across three documents. The RAS
received two documents written alongside the code. If document readiness
predicted build outcomes, these two units should have diverged.

They did not. Both closed with their documents reconciled to the RTL as
built. The FTB's verified widths moved twice more during the build. Its
storage partition and its confidence field were both redefined after the
documents describing them were declared build-ready. A field the entry
format specified had no producer anywhere in the update port. The RAS
needed one reconciliation round. The difference in cost between them is
not in the ratio of document effort to build effort.

The reason is that the errors in both document sets were of a kind that
review cannot reach. Cross-document consistency checking finds a
parameter stated at two values. It does not find a parameter stated
consistently at the wrong value, which is what the tag width was, nor a
field with no producer, which is what the position was, nor a repair
labelled with the name of an operation it does not perform, which is what
cost the RAS its second defect. Each of those is internally consistent.
Each requires something to be built before the inconsistency has anything
to appear against.

This is the same argument the previous range made about tests, one level
up. A test that has only been run against conforming RTL cannot be
distinguished from a test that cannot fail, and the way to separate them
is to inject the defect and watch it fail. A specification that has only
been reviewed against other documents cannot be distinguished from a
specification that is correct, and the way to separate them is to build
against it. Both are claims about a system that has never been exercised,
and both cost more the longer they are trusted.

The practical form is narrower than "write less specification". The FTB's
specification work was not wasted: the widths it ruled were the last
thing blocking RTL, the rejected structural model would have been more
expensive to discover in code, and the rulings on what to omit are
decisions that the build had no basis to make. What the range shows is
that document review has a floor it cannot go below, and that treating
"build-ready" as a state a document reaches through review overstates
what review establishes. The document is a draft until something has
been built against it, whatever its status field says. Both units'
authority documents were promoted to Complete only after the RTL existed,
and in both cases that was the correct order.

## Technical Debt Referenced

The table below reports status as of the close of this range. Later
experiments outside the range have since changed the state of some items
carried alongside these.

| # | Item | Resolution path |
|---|---|---|
| 78 | RAS p3 undo-pop repair does not reverse a recursion-decrement pop. | PINNED by tb_ras TC-21 (BP-064). The pre-pop recursion count is not recoverable from post-pop working state. Left as-is deliberately; the test locks the limitation open. Revisit at bp_cluster integration if a p2/p3 repair over a recursion pop is ever required. Related: #79. |
| 79 | RAS commit-stack recursion depth not preserved. | DEFER. The field is write-only and never read by any output path, so a wrong value degrades the fallback prediction only. A real fix needs a recursion-count source on the commit interface. Decide at FTQ integration. Re-scoped from a fix to a deferral in BP-064. |
| 80 | FTB confidence hysteresis tuning. | FTB_CONF_WIDTH is the knob. Revisit at bp_cluster SPEC numbers. The entry's wording predates the BP-066a confidence redefinition and still describes threshold suppression; the mechanism is now the saturated-endpoint fast path. |
| 81 | tb_ftb coverage skews to br0. | Optional symmetric br1 augment. The br1 direction and confidence init are exercised once, through the free-field write; the second fast-path bit and a br1 saturation path are not directly exercised. The fast path is generated per field in a loop sharing logic with the tested bit, so the risk is bounded. Not a blocker; sim_ftb 99/0. |

## What comes next

Both units close this range complete and verified at the unit level, with
their authority documents reconciled to the RTL as built. Every remaining
item on either is downstream at cluster integration rather than open at
the unit: the FTB flush protocol, which has no definition yet; the
interaction between the FTB fast path and the TAGE and SC metadata, which
is a cluster obligation because the fast path suppresses the override and
not the training; update-channel arbitration onto the FTB's single update
port; the FTQ round trip for the carried way; and the source of the
fast-path enable. On the RAS side, both filed items wait on interfaces
that do not exist yet.

That leaves `bp_history`, which the cluster work needs before it can
start, and the statistical corrector, which is the last unbuilt
predictor.

---

## References

*No references required for this post.*

---
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*

