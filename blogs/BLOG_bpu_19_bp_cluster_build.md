<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

```
TITLE:     "The Branch Prediction Cluster: Built and Not Yet Run"
FILE:      BLOG_bpu_19_bp_cluster_build.md
AUTHOR:    Jeff Nye
DATE:      2026-09-22
STATUS:    REVIEW BEFORE POSTING
COPYRIGHT: "Copyright 2026 Jeff Nye"
```

<!--
---

::SERIES DESCRIPTION::
::BEGIN LINKS::
::END LINKS::
-->

# The Branch Prediction Cluster: Built and Not Yet Run

## Abstract

Session 063 built `bp_cluster`, the top level of the Pacino branch prediction
unit. It instantiates the seven predictors and the history module, carries
requests from p0 to p3, forms the p1 prediction, derives redirects at p2 and
p3, fans resolved updates out by branch type, arbitrates the statistical
corrector's single-port RAM, and writes each prediction's metadata to the fetch
target queue (FTQ). It elaborates and lints clean, and all 45 unit targets
pass. Nothing was driven through it in the range.

The session started with a port inventory. Of the 140 ports on the eight
top-level modules, 136 matched their interface documents. The four that did
not were in the two documents the previous audit had not covered.

Building the cluster to the FTQ interface exposed a contradiction in shipped
RTL. The micro-BTB (uBTB) did two lookups per cycle, one per 32-byte PC range,
which the FTB decisions had ruled out. It was rewritten to one lookup that
describes one block and supplies both prediction slots.

Three of the ten tasks were abandoned because the planning assistant
specified them incompletely. Each changed a type and specified only
the breakage in front of it. The task that replaced them was written against
the state a failed run reported, and it closed in one run. It added the
metadata write path without which no update could work, and a redirect operand
that detects a case the previous comparison masked.

## Where the range starts

The previous range ended with all seven predictors passing at the unit level,
their planning documents audited against the RTL, and the FTQ boundary
described in `fe_decisions.md`. The interface file for that boundary had not
been written, because it depends on the port lists of all eight top-level
modules and those could not be read in the chat session. This range moved the
work to the implementation assistant, which reads the repository directly.

## The port inventory

INFRA-011 read the port declaration of each top-level module and compared it
with the module's interface document. It was written as evidence-gathering
only. The task stated no hypothesis and barred the IA from assessing what it
found. The RTL was the authority for names, directions, widths and types, and a
missing file was a reason to stop rather than to search for a substitute.

The eight modules declare 140 ports, and 136 match their documents. All four
findings were in `ubtb_interfaces.md` and `bp_history_interfaces.md`, two of
the three documents the audit in session 061 had not covered. Three were uBTB
ports whose stage suffixes had been added to the RTL and not to the document.
The fourth was a `bp_history` port whose document gave an unpacked dimension
as packed. The third unaudited document, for the loop predictor, matched. The
FTB, TAGE, ITTAGE, SC and RAS documents, which session 061 had corrected, also
matched.

The inventory recorded how each module names and shapes its ports, and the
modules do not agree. TAGE, ITTAGE and SC use a predictor prefix, a stage
suffix and an unpacked slot array. The RAS does the same without queue-status
ports. The uBTB puts the slot dimension on the packed type. The loop predictor
had a single slot and a p0 suffix on its update. The FTB has flat ports, no
structs and no slot dimension. `bp_history` has no stage suffixes and literal
dimensions. The interface file uses each module's ports as declared and
proposes no renaming.

### The interface file

`ftq_bpu_interfaces.md` was written from the inventory. It specifies the
boundary between the cluster and the FTQ and the route from each boundary
signal to each predictor port: the request, the p1 prediction, the later
predictions, the redirects, the prediction metadata, the updates and the
history checkpoint. Its last section lists corrections that other documents
still need.

## The dual-slot FTQ entry

`fe_decisions.md` had defined the FTQ entry as block-level fields plus a
per-slot array. BP-082 was to apply that split to `bp_structs_pkg.sv`. It found
the change already in the tree from an earlier commit, verified each field
against the specification, and made no edit.

The task also required a search of the unit for anything that used the fields
the split had moved. It found one, `tb_bp_pkg.sv`, a zero-time check of the
package types. It failed to elaborate with seven errors naming the moved
fields. The task forbade editing it, so BP-082 stopped and reported.

BP-083 retargeted the seven references at the slot array and added seven
checks: the widths of the slot and the entry, read-back of the slot array, and
independence of the two slots. The IA then made four deliberate defects in a
scratch copy outside the tree and confirmed that each was caught by the check
meant for it. The task had asked for the checks to exist, not for that proof.

## The structural top

BP-084 built `bp_cluster.sv` as a structural module: eight instances, every pin
connected by name, the per-slot input structures, the request fan-out and
tie-offs, and no sequential or combinational logic. It elaborated and linted
clean on the first attempt, and no existing module changed.

The task required the redirect outputs to be declared and left undriven, and
also required zero lint warnings. Both could hold only with a suppression. The
IA added `-Wno-UNDRIVEN` to the cluster lint target, listed all eight signals
it masked so that nothing else was hidden, and noted that the suppression
should come out once the outputs had producers. Tying the outputs off would
have avoided it.

## The behavior

BP-085 added the logic to the structural top without changing its port list or
any instantiated module. The file grew from 537 to 1,166 lines, every boundary
output gained a producer, and `-Wno-UNDRIVEN` was removed.

The cluster holds three groups of stage registers, p0 to p1, p1 to p2 and p2
to p3. The p1 to p2 group carries the p1 prediction forward as the value every
later redirect compares against.

The IA found one alignment the task had not stated. The uBTB reads a
registered array combinationally, so its result appears in the p0 cycle. The
loop predictor registers its output, so its result appears in the p1 cycle.
Without correction the p1 selection would combine the uBTB result for one
request with the loop predictor result for the previous one. The cluster
registers the uBTB result once so that both describe the same request.

The p1 selection takes, per slot, the loop predictor when it identifies a
loop, otherwise the uBTB when the slot holds a branch, otherwise no
prediction. Slot 1 has no loop predictor producer. A uBTB return takes its
target from the registered RAS top of stack. An FTQ entry is allocated at p1
for every request.

### Redirects

No predictor declares a redirect port; the inventory confirmed this across all
140. The cluster derives a redirect by comparing a predictor's later output
with the prediction it formed at p1. It does not read the FTQ. The redirect
outputs are named by stage, `bpu_redir_p2` and `bpu_redir_p3`, each a per-slot
array with one FTQ index beside it.

Each comparison reduces both views of a slot to one quantity, the address
fetched after that slot, so two not-taken views compare equal and raise no
redirect. The p3 comparison is against the value published at p2, so a p3
redirect fires only when the SC changes what the cluster published at p2.

TAGE, ITTAGE and the SC carry the FTQ index of their request in their
metadata as `branch_id`. Every p2 and p3 comparison requires that value to
equal the index in the matching stage register. A response that is queued or
held back cannot be compared against the wrong entry, so the redirect logic
does not assume a fixed predictor latency.

### Two conflicts

BP-085 reported two conflicts it was not allowed to resolve.

The first was in the uBTB. `ubtb.sv` performed two lookups per cycle, slot 0
at the request PC and slot 1 at the request PC plus 32. That is the model of
two 32-byte PC ranges that `ftb_decisions.md` had ruled out and that session
062 had replaced in `fe_decisions.md`. The contradiction was in shipped RTL,
not only in a document. The cluster was built to the interface file, and the
uBTB rewrite became its own task.

The second was in the FTB. An FTB block has three branch fields, two
conditional and one jump, and there are two prediction slots. The interface
file places the jump in the lowest slot that holds no conditional branch. A
block with two conditional branches and a jump therefore has no slot for the
jump, and the cluster drops it without recording that it did. The FTB is
consulted at p2, so the cost is a missed p2 correction, not a wrong result.

## The uBTB as a block descriptor

BP-086 rewrote `ubtb.sv` and its testbench. The uBTB entry now has the shape of
the FTB entry: two conditional branch fields, one jump field, a partial
fall-through address with a carry, and targets stored as displacements with a
status for whether each fits. One index, one tag and one way search return
one entry, which describes one 32-byte block and supplies both prediction
slots. The PC-plus-32 lookup is gone.

The uBTB now reports a hit once per lookup, on a new output, `blk_p1`, which
also carries the reconstructed fall-through. A slot's own valid bit now says
only that the slot holds a branch. A hit with no valid slot is legal: the
block is known and has no recorded branch, and the next fetch is its
fall-through.

The new testbench runs 15 cases and 259 checks. Each case starts from reset,
and cases that need two addresses to share a set build them from an explicit
set and tag instead of relying on the hash. The IA introduced five defects into
the RTL, and each was caught by between 6 and 17 failing checks. Line coverage
is 98.6%.

The old testbench exited through `$finish(1)` on failure. Verilator does not
turn that into a non-zero exit status, so a failing run would have reported a
passing target. The new testbench uses `$fatal(1)`.

## Three abandoned tasks

The uBTB rewrite changed `ubtb_pred_t` and `ubtb_upd_t` and added `blk_p1`, so
the cluster had to be rewired. The same work added the metadata write path,
described below, and a position field to the per-slot FTQ entry. Three tasks
attempted this and were abandoned. None of their RTL reached the tree.

BP-087 rewired the cluster and passed the cluster lint target. The package's
new position field had widened the slot type from 52 to 55 bits, and the
package testbench computed the expected width from a formula with no term for
it. The task forbade editing any testbench and required every target to pass.
The IA made the required changes, confirmed that the one failure was not its
own by reproducing it with its edit set aside, and stopped.

BP-088 was written to allow the testbench fix, and it reported every target
passing. Its testbench scope was the width formula only, so the new field was
driven by no test and passed without a value ever being checked. I abandoned
it.

BP-089 was written on the premise that BP-088's changes were in the tree. They
were not, because BP-088 had been abandoned. The IA ran the full baseline
before editing anything, found 43 of 45 targets passing and the cluster lint
failing on fields that did not exist, and showed that the task's constraints
forbade both possible repairs. It stopped before modifying any deliverable and
reported that the task needed re-scoping rather than a retry.

## BP-090

BP-090 was written against the tree state BP-089 had reported, and it carried
all of the work of the three abandoned tasks. It closed in one run with all 45
targets passing.

### The metadata write path

The FTQ's slow path holds, per slot, what each predictor needs at update time
and cannot recompute. The cluster had no port to write it. The update inputs of
TAGE, ITTAGE and the SC each embed the metadata their prediction produced, so
without that port no update could work.

BP-090 added two write groups with disjoint members, so the FTQ never has to
merge them. The p2 group writes the TAGE, ITTAGE, loop predictor and FTB
metadata. The p3 group writes the SC metadata. The loop predictor finishes at
p1, and its result is carried forward into the p2 group so that the FTQ makes
one slow-path write.

The FTB metadata needed a new type, `ftb_pred_meta_t`, holding the FTB hit,
way and jump position. The FTB writes back to the way it predicted from, so
the hit and way have to travel through the FTQ and return on the update port.
The per-slot branch position went into the fast-path slot entry, because
locating the taken branch in the fetched bytes is every-cycle work.

### The p1 redirect operand

BP-085's p2 comparison used the FTB fall-through on both sides. A redirect
exists to catch a block whose end the FTB places differently from the uBTB,
and a comparison whose two operands come from the same source cannot see that
difference.

The p1 operand is now formed at p1 from the p1 view only: the slot target when
the slot is taken, the uBTB fall-through on a hit, and the block-aligned PC
plus 32 bytes on a miss. It is staged to p2. A not-taken slot where the uBTB
and the FTB disagree on the end of the block now raises a p2 redirect, where
before the front end would have fetched past a boundary the FTB had already
contradicted.[F1]

### Update branch type

The uBTB update no longer carries a branch type field. The cluster derives the
type from the update's own branch, jump, call, return and indirect bits, in the
same order the uBTB and the FTB classify. A branch type that reads as zero
decodes as a conditional branch. Restoring the field to clear the lint error,
rather than deriving the type, would have left it at zero and classified every
update as conditional. ITTAGE would never have been updated, and the uBTB would
have accepted updates for blocks with no branch.

### SC fold staging

The SC's prediction PC and path history were already staged from p0 to p2
(TD #91, TD #92). The three folded histories that index SC tables ST1 to ST3
were connected live to `bp_history`, which advances whenever a branch is
predicted. At p2 they described newer history than the block the SC was
indexing. BP-090 staged them with the rest.

### A refused instruction

Requirement 6 told the IA to replace both reads of the uBTB slot valid bit with
the new entry hit. It changed one and left the other. The second read is the
p1 selection rule, which a binding decision fixed as "the uBTB when the slot
holds a branch". Substituting the entry hit there would have turned a hit with
no valid slot, which the uBTB interface defines as a legal no-branch block,
into a prediction. The IA stated this, and it was right.

### The package testbench

`tb_bp_pkg.sv` gained the missing term in its width formula, width checks for
the two new metadata types, and stimulus for the three package fields that no
test had driven. Its checks went from 23 to 28. Each new or changed check was
proven to fail on a wrong expected value, not only on an unknown one. The
thirteen mutations first failed to compile, because the scratch build used an
older Verilator on the system path. Rebuilt with the project's pinned
Verilator, all thirteen were caught.

## Not yet simulated

The range closes with the cluster structurally complete and unverified above
the unit level. There is no cluster testbench. Everything known about the
cluster's behavior comes from reading the RTL and from elaboration.

The first draft of the exit handoff said the RTL was ready for a testbench as
it stood. It was not. Three open design items would rename or extend the ports
a testbench binds to: the loop predictor's dual-slot retrofit (TD #105),
whether the p1 output carries the block fall-through (TD #108), and which of
two loop predictor structs to keep (TD #106). The overclaim was caught in review at
the start of the next session, and the handoff was corrected to list nine
items, including three testbench decisions: how
to inject a mismatched `branch_id`, which unknown-value settings the
simulation uses, and whether the SC arbiter's starvation rule can be reached at
the current parameters (TD #39).

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| INFRA-011 | Port inventory of the eight BPU top-level modules against their interface documents | COMPLETE | 136 of 140 match; 4 findings | 6m 11s | 9% |
| BP-082 | Dual-slot FTQ entry in bp_structs_pkg | COMPLETE | found applied, verified; tb_bp_pkg consumer found; 37/38 targets | 5m 3s | 11% |
| BP-083 | tb_bp_pkg retargeted to the slot array | PASS | 16 to 23 checks; 44/44 targets; 4 mutants caught | 9m 56s | 14% |
| BP-084 | bp_cluster structural top | PASS | lint 0/0; 45/45 targets | 10m 5s | 17% |
| BP-085 | bp_cluster behavior | PASS | lint 0/0; 45/45 targets; 2 conflicts reported | 21m 39s | 26% |
| BP-086 | uBTB rewritten to one lookup per block | PASS | 15 cases, 259 checks; 5 mutants caught; 98.6% lines; cluster lint waived | 22m 39s | 20% |
| BP-087 | Cluster rewire to the new uBTB; metadata write groups | ABANDONED | stopped on tb_bp_pkg width, 55 vs 52 | 11m 43s | 15% |
| BP-088 | BP-087 with the width fix | ABANDONED | 45/45 reported; new field driven by no test | 11m 30s | 18% |
| BP-089 | Follow-on written on BP-088's results | ABANDONED | stopped at baseline, 43/45 | not recorded | not recorded |
| BP-090 | Cluster rewire, metadata write path, p1 operand, SC fold staging | PASS | 45/45; tb_bp_pkg 23 to 28 checks; 13 mutants caught | 16m 20s | 22% |

## Design Process Notes

### The IA contribution

The IA's strongest work in the range was proving that its checks could fail.
BP-083, BP-086 and BP-090 each introduced deliberate defects and confirmed that
the right checks caught them, and two of the three were not asked to. In BP-090
it found that its own harness was using the wrong Verilator, and re-ran it.

It also found what the tasks did not state. BP-085 found the one-cycle
misalignment between the uBTB and the loop predictor, and reported the uBTB
and FTB conflicts instead of resolving them outside its scope. BP-089 ran a
baseline before editing and showed that its task could not complete as
written. BP-090 declined the half of an instruction that contradicted a binding
decision, and said why. INFRA-011 kept to gathering evidence, and recorded an
undocumented loop predictor parameter under notes rather than widening its
scope.

### The PA contribution

The planning assistant wrote `ftq_bpu_interfaces.md` from the inventory and
wrote the ten task files.

BP-084 and BP-087 each carried two constraints that could not both hold. The
three abandoned tasks each changed a type and specified only the failure in
front of them. BP-089 was written on BP-088's reported results after I had said
BP-088 was abandoned. The assistant quoted the standing rule to build from the
tree inside the task that broke it. When I asked whether the RTL was ready for
a testbench, it answered yes, with the three port-changing items in front of it.

The task files that stated the failure mode held. BP-082's consumer search
found the testbench before it broke anything else, BP-086's stop rule was
scoped correctly, and BP-090's baseline requirement made each fix
attributable.

### My contribution

I abandoned BP-087 and BP-088, and caught the contradictory constraints in
BP-084 and BP-087. I asked directly whether the RTL was ready for a testbench.
The slot model the uBTB rewrite implemented was my ruling in session 062.

### The generalization

The three abandoned tasks, and the defect BP-090 avoided, trace to a type that
changed without everything that depended on it changing too.

The uBTB interface changed, and the cluster that read it had to be rewired.
The package gained a field, and a testbench that computed the package's widths
from a formula went stale. BP-088 added a field and no test drove it. A
removed branch type field would have read as zero, and zero is a valid
branch type. The tasks that worked asked for the dependents first: BP-082
searched the unit for consumers of the moved fields before editing, and BP-090
ran a baseline and named what was failing before changing anything.

In this project a task that changes a type has to name every consumer of that
type, found by searching the tree, and has to exercise each new field with a
value that a wrong implementation would get wrong. A field that is added,
compiles and is never driven is not finished.

## What comes next

The next session settles the three port-changing items and writes the cluster
testbench. The testbench acts as the FTQ: it captures the p2 and p3 metadata,
holds it against the FTQ index, and returns it on the update channels at
resolution. The metadata write path added in BP-090 is what makes that closed
predict-then-update loop possible.

The design record from this range, including the block-descriptor uBTB, the
stage-named redirects, the single-quantity comparison, the `branch_id`
qualification and the two metadata write groups, exists at the close of the
range only in the handoff and in `ftq_bpu_interfaces.md`. The uBTB has no
decisions document. The uBTB contradiction happened because a decision lived
in a document the RTL was not written against, and the handoff lists promoting
these decisions into `bp_cluster.md` and a new uBTB decisions document as open
work.

## Technical Debt Referenced

The table below reports status as of the close of this range. Later
experiments outside the range have since changed the state of some items.

| # | Item | Resolution path |
|---|---|---|
| 39 | SC arbiter starvation override reachability. | SC_PRED_CREDITS=4 < SC_STARVE_THRESH=8, so the Rule 2 override may be unreachable at current parameters and therefore untestable. Settle whether the relationship is intentional before writing the arbiter tests. |
| 91 | bpc routes the PC p0 to p2 to SC. | CLOSED session-063. |
| 92 | bpc captures phr[9:0] for SC. | CLOSED session-063 for the PC and phr. The three SC index folds were staged p0 to p2 in BP-090; bp_arb_spec.md 6.1 still to name them. |
| 101 | ras.sv declares input ras_pc_p2, unread in the module. | bp_cluster now drives it from the staged p2 PC. Confirm needed or remove from ras.sv and tb_ras.sv. |
| 102 | bp_history.sv does not generate IT5 folds. | IT5 indexes on the PC alone and contributes no history. Add IT5 fold generation, same pattern as IT1-IT4. |
| 105 | loop_pred dual-slot retrofit. | Slot dimension on the loop predictor's prediction and update ports, internal tables reworked per TI6, pred_p0 renamed pred_p1. Renames a port the cluster testbench binds to. |
| 106 | Retire one of lp_pred_t / bp_loop_meta_t. | The metadata tests check the loop metadata field by field, so the consolidation changes them. |
| 107 | bp_cluster.sv stale comments. | The port-list comment numbers the update channel 7 (it is 8); the slot-PC comment still describes the retired PC-plus-32 uBTB lookup. |
| 108 | p1 output group: block successor or fall-through. | The FTQ needs the block end on a not-taken block and blk_p1.pft_addr stays inside the cluster. Adds a port if yes; also an observability hole for the p1 redirect operand. |

## References

- Before the Cluster: Reconciling the Predictors and Their Documents
  (BLOG_bpu_18), for the audit that preceded the port inventory and the
  `fe_decisions.md` slot model.

- External Anchors: When a Proof and Its Reference Share the Same Error
  (BLOG_bpu_16), for the earlier case of a check whose two sides came from the
  same source.

## Footnotes

<!-- ticfinder_off -->
[F1] Later sessions revised this operand. Prediction blocks begin at any
2-byte address, not on a 32-byte boundary, and the miss case now uses the
lookup PC plus 32 bytes rather than the block-aligned PC (session 069).
<!-- ticfinder_on -->

---
<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
