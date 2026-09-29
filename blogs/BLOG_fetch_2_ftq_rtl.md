<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

```
TITLE:     "Building the Fetch Target Queue: Eleven Modules and Fault-Injected Properties"
FILE:      BLOG_fetch_2_ftq_rtl.md
AUTHOR:    Jeff Nye
DATE:      2026-09-24
STATUS:    REVIEW BEFORE POSTING
COPYRIGHT: "Copyright 2026 Jeff Nye"
```

<!--
---

::SERIES DESCRIPTION::
::BEGIN LINKS::
::END LINKS::
-->

# Building the Fetch Target Queue: Eleven Modules and Fault-Injected Properties

## Abstract

The fetch target queue (FTQ) of the Pacino RVA23 front end holds one entry
per predicted fetch block between the branch predictors, the instruction
fetch unit and the backend. The previous range specified it as eleven modules
and built one. This range built the other ten in three tasks.

The first task built the pointer modules. It found that at full occupancy
the backend's commit watermark can name 65 distinct entries on a port that
carries 64 values, and that the two readings of the ambiguous value demand
opposite responses. The state is reachable in ordinary traffic. The task held
allocation one entry short, and the port was then widened by one bit instead.

The second task built the remaining eight modules and a structural top: 22
targets, 670 checks and 73 bound concurrent properties. Seven modules needed
a port the decomposition did not anticipate, and each is reported with its
reason. The unit testbench found a defect no module test could: the response
shadow, specified as four stages, had been built as four registers and
dropped every predictor response. Fault injection found 46 of the 73
properties did not fire on first pass, most because the stimulus never
crossed a clock edge. All 73 fire now, and fault injection is required for
every bound property.

The third task moved the assertion files from `rtl/` to `tb/` and proved the
move changed nothing. Its elaboration census raised an open question: two
properties that appear in lint builds may not appear in the simulation
build. The block fall-through stored in each FTQ entry was also found to have
no correction path; the fix is specified and not built.

## Where the range starts

The previous range ended with the FTQ specified in four planning documents,
divided into eleven modules by one rule, each piece of state has one owner
module, and with one module, the FTB update scheduler, built. It ran as
interactive sessions under a waiver that let the implementation assistant
(IA) write planning documents.

This range returns to the standing arrangement. The planning assistant (PA)
writes each task file, the IA runs it, and planning documents are read-only
to the IA. Each of the three task files says so, and each IA report lists the
document corrections it found rather than making them. The PA drafted those
corrections and I applied them. Each task was written as a set of problems
with acceptance criteria, leaving method and order to the IA.

## The pointers

### Three pointers

BP-106 built `ftq_ptr.sv`, which holds the allocation and fetch pointers, and
`ftq_commit.sv`, which holds the commit pointer and the commit walk. Before
the task, `ftq_backend_interfaces.md` asked for a fourth pointer, separating
commit from free. I ruled that `ftq_decisions.md` 5.4 governs: an entry is
freed when its RAS commit is issued, so commit and free are one pointer.

Pointers are seven bits: six index the 64 entries and the top bit is the
wrap generation. Every comparison in the assertion files is on an age taken
relative to the commit pointer, since a raw pointer comparison fails on every
wrap. The two testbenches ran 155 checks, and ten concurrent properties were
bound by module name. The IA injected two faults, reverting the allocation
limit and removing the walk-stop term, and the corresponding properties
fired.

### The watermark alias

The backend reports retirement as a watermark on `bkend_ftq_commit_idx`,
naming the youngest retired entry, and `ftq_backend_interfaces.md` 6 states
that repeating a watermark is harmless. The port was six bits, with no
generation, so `ftq_commit` reconstructs the generation against the commit
pointer.

At 64 live entries that reconstruction fails. With the commit pointer at 5
and the allocation pointer at 69, a held watermark of 4 can mean the entry
just committed, still on the port because nothing new has retired, or entry
68, the newest live entry, if the backend has retired the whole queue. The
values are identical. Accepting frees 63 live entries and issues 63 false RAS
commits. Rejecting deadlocks: a full FTQ predicts nothing, so nothing new
reaches the backend and the watermark never moves. The state is reached
whenever the FTQ refills to full before the backend retires one more block,
which is ordinary for a decoupled front end.

The IA held allocation one entry short, which removes the 65th value at a
cost of one entry of run-ahead, and bound a property that fires if the limit
is reverted. It recommended widening the port instead. I ruled for the
widening: `bkend_ftq_commit_idx` became `FTQ_PTR_BITS` wide. The port is off
any critical path and the backend does not exist, so the change costs nothing
now. This is not the widening `ftq_decisions.md` 5.6 had rejected, which would
have added a bit to every cluster port and to the predictor metadata
structs.

### Two further findings

`ftq_decisions.md` 7.2 said the pointer state crosses between the two modules
in one direction, the commit pointer read by `ftq_ptr` to compute full. It
crosses both ways. `ftq_ptr` also needs the commit pointer to reconstruct the
generation of a redirect index, and `ftq_commit` needs the allocation pointer
to reject a watermark outside the live window. Each pointer still has one
writer.

No document said what happens to a commit walk in progress when the redirect
that names no instruction, `RC_UNSPEC`, arrives. The IA's first draft took a
walk step in that cycle, which put the walk end behind the commit pointer and
produced a 127-entry walk. The draft was corrected before delivery, and
property C4 guards the case. The IA reported the interaction as unspecified.

BP-106 used 16 percent of its context in about 20 minutes for two modules.
I had expected it to finish the FTQ, and the next task was scoped to all
eight remaining modules.

## Between the tasks

Both BP-106 modules declared two items locally that belonged in the
packages: `FTQ_PTR_BITS` and the redirect cause enumeration. The PA drafted
the package additions and described removing the local copies as later work
for BP-107. Applied, the additions made each local declaration a shadow of a
package name, which is an error under the project's lint flags, and the four
BP-106 targets stopped building. Nothing reported it until BP-107's baseline
run.

Three rules came out of this. A task may add declarations to the two
packages, may not change or remove one, and must list each addition with its
derivation. A package addition is sequenced with the modules that stop
declaring it locally, or the task states that the tree is broken in between.
A green report records the tree when the report was written, not the tree
now.

## The rest of the FTQ

### Scope and baseline

BP-107 built `ftq_entry`, `ftq_meta`, `ftq_status`, `ftq_shadow`, `ftq_npc`,
`ftq_ifu`, `ftq_resolve` and the structural `ftq.sv`, and retrofitted the two
pointer modules to the widened port and the package declarations. It ran for
1 hour 40 minutes and used 67 percent of its context. Its baseline found four
of the six existing targets not building, for the reason above, so BP-106's
checks were restored before they were extended.

The fast-path array, 224 bits per entry, has four write ports in the stage
order and five read ports. The slow-path metadata, 421 bits per slot and two
slots per entry, is built unpacked and has no reset, since only an entry a
prediction wrote is ever read. The status module holds three 64-bit flop
vectors with a range clear. `ftq.sv` has no state, no always block and three
assigns, each a rename or a connection.

### Seven ports the decomposition did not anticipate

The task's hypothesis was that the decomposition closes with no port beyond
those `ftq_decisions.md` 7.3 lists, and it asked for each exception to be
reported rather than added quietly. There were seven. Each is a value one
module owns and another reads, so the partition rule holds.

The first is a defect in the specification. The FTQ may fetch any entry
between the fetch and allocation pointers, but the allocation pointer
advances at p0 and the entry is written at p1, so for one cycle the newest
entry has an index and no content. Fetching it presents an unwritten PC, and
this happens in the first two cycles after reset. The shadow already tracks
that request, so it reports it to `ftq_ptr`, which excludes it.

The second is the block start PC. The entry is written at p1, but no p1 port
from the cluster carries the block's PC; it exists only as the request the FTQ
issued at p0. `ftq_npc` publishes its next-PC register, which is that value
one cycle later, at no cost in state. The third exports the squashed range from
`ftq_ptr`, so the status and shadow modules do not each repeat its generation
reconstruction. The rest are the RAS commit payload formed in `ftq_entry`,
where the snapshot lives; a second resolution read port on both arrays,
since two resolutions per cycle can name different entries; a read port for
the predecode writeback; and the RAS restore snapshot as its own port.

### The shadow

`ftq_decisions.md` 5.6 specifies a four-deep in-flight shadow, one stage per
cluster stage p0 to p3, which drops a predictor response for an entry a
redirect has squashed. It was first built as four registers. The p1 response
to a request issued in cycle T arrives in T+1, when a four-register shadow
holds that request in its first stage. Every response was checked against the
stage behind it and dropped, and the front end stopped after one block.

The p0 stage is the request being presented and is registered nowhere, in
the FTQ or the cluster. The shadow is four stages and three flops. This
passed every module test and was found only by `tb_ftq`, which runs the unit
against a modelled cluster. The shadow also carries full seven-bit pointers
rather than indices, because deciding which stages a p2 redirect clears is an
age comparison: the p3 stage holds an older request and must survive.

### The zero-bubble path

The p1 prediction must select the next p0 request in the same cycle. A
registered path passes every functional test and costs a cycle on every
prediction, so the task required the IA to state how it confirmed the path is
combinational. It gave three independent confirmations. One test reads the
next request one time unit after the p1 group arrives, with no clock edge
between, after first showing the prior value differs. A same-cycle property
fires when a register is injected into the path. The unit testbench counts 18
consecutive one-block cycles with the PC advancing by the block size each
cycle, which a registered path would halve.

### Fault injection

Every property was then proven live: 73 faults, one per property, each on a
scratch copy of the RTL, with the property's own error message confirmed in
the output. Verilator stops at the first assertion failure, so the runs raise
the error limit to keep an earlier property from hiding a later one.

On the first pass 46 of the 73 did not fire. A concurrent property samples at
a clock edge, and most of the testbenches drove inputs, checked the result
after a delta delay and moved on, so the state a property guards was never
present at an edge. A `settle()` task now holds each case's stimulus across
an edge. The zero-bubble test deliberately does not use it. Fourteen of the
fifteen `ftq_resolve` properties were defined and never asserted. Two
properties compared a register with `$past` of a signal in the same
combinational cone and reported mismatches the design does not have; both
were restated against an independent registered copy in the assertion
module.

All 73 fire now. Fault injection is required for every bound property, and
the clock-edge mechanism is recorded with the rule, so that a property that
does not fire is investigated as a testbench construction problem.

### The fall-through

At my instruction, after the run, the IA checked the RAS return address
against `ras_decisions.md`, which names the FTB's fall-through as the source
and says the RAS does not compute it. The entry's `pft_addr` is written once
at p1. On a uBTB miss that is the end of a full block, so a block the FTB ends
earlier at a call pushes an address past the call. No correction reaches the
field, because the p2 and p3 groups carry per-slot data and `pft_addr` is a
block value.[F1]

The IA reported the cost as return prediction accuracy. The PA traced the
field's other consumer. `ftq_entry_formats.md` 2 stores `pft_addr` so the
not-taken successor survives a redirect that rewrites a slot, which is the
case where the p1 value is stale. That makes it a fetch address error, not an
accuracy loss, and makes correcting the field at p2 the right fix rather than
adding a separate return address field. The fix is specified and was not built
in the range.

The report also records that the resolution generation test of
`ftq_backend_interfaces.md` 7 cannot be built, because the resolution index
carries no generation bit. Only the live-window half is built. The 73
properties are proven live in simulation, not proven by a formal tool.

## Moving the assertion files

BP-107 placed the ten assertion files in `rtl/`. The branch prediction unit
keeps them in `tb/`, so that `rtl/` holds only synthesizable RTL. BP-108
moved them and edited only the Makefile. All ten files are byte-identical to
their previous versions, and every target's counts matched before and after:
22 targets, 670 checks.

The check count cannot show that a moved file still elaborates, so the IA
counted, per target, the property failure messages Verilator generates, which
are present only for elaborated properties. The count was identical before
and after, and nonzero for every file. Lint builds kept the assertion files,
matching the branch prediction unit, which already lints a `tb/`
assertion file.

The PA noticed what the report did not state. Under lint the census matches
BP-107's 73 declared properties file for file. The module simulations sum to
71, two short in `ftq_ifu`, and the unit simulation to 69. If the lint count
is exact, two `ftq_ifu` properties are not in the simulated design and could
not have fired in BP-107. The census counts source lines, the lint and
simulation elaborations differ, and the figures come from two tasks, so the
discrepancy is recorded as an open question with a short task to settle
it.[F2]

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| BP-106 | ftq_ptr and ftq_commit; three pointers | PASS | 155/0; 10 properties, 2 fault injections; watermark alias found | 19m 48s | 16% |
| BP-107 | Remaining eight modules, ftq.sv, pointer retrofit | PASS | 22 targets; 670/0; 73 properties, 73 faults fired; baseline 4 of 6 targets broken | 1h 39m 55s | 67% |
| BP-108 | Assertion files moved from rtl/ to tb/ | PASS | 22 targets; 670/0 before and after; elaboration census | 9m 9s | 11% |

## Design Process Notes

### The IA contribution

The IA found the watermark alias by checking whether a stated property of the
interface, that a repeated watermark is harmless, held at full occupancy. It
reported the defect with a worked example and a reachability argument, and
implemented a safe workaround that a property guards rather than waiting for
a ruling.

It reported where the specification and the build diverged instead of
adjusting either silently: the two-way pointer crossing, the unspecified
`RC_UNSPEC` interaction, and the seven ports. It found the shadow error only
through a unit testbench it chose to add alongside the module tests, because
the module tests could place the corner cases and could not see the loop.

It ran fault injection on every property and reported the 46 that did not
fire on first pass, including its own `ftq_resolve` properties, with the
cause. It found the broken baseline by running every target before editing,
and proved the file move with a method that would detect the failure the move
risked.

### The PA contribution

The PA wrote the three task files and drafted every planning document
correction, applied in two rounds by exact-match replacement against the
original text so the unchanged text stayed byte-identical. In its review of
BP-106 it checked the watermark argument and recommended widening the port.
In BP-107 it traced `pft_addr` to its second consumer, which changed the
fix. In BP-108 it found the census discrepancy the report did not state.

Several of its errors changed artifacts. BP-106 was scoped to two modules
where the rest of the FTQ fit in one task. The package additions were handed
over without the sequencing that kept four targets building. BP-107 carried a
constraint to compact context after each logical unit, which the IA cannot
do; the project rule now is that the PA does not instruct the IA on session
operation. The PA filled the session field of BP-106 with 068 by inference,
and the number was carried into five more files before it was corrected to
067.

### My contribution

I ruled that commit and free are one pointer, that the commit watermark port
is widened, that package additions are permitted and scoped, and that fault
injection is required for every bound property. I retired "locked" as a
planning document marker, since permission is settled once for every file in
`planning/`. After BP-107 ran I had the IA check the RAS return address,
which confirmed the `pft_addr` defect, and I sorted the task's remaining
deferred items into those for the PA, those for a later task and those that
need no action. I identified the assertion file location as a departure from
the branch prediction unit's convention, which became BP-108.

### The generalization

Two of the range's defects were visible only one level up from where they
were built. The shadow passed every module test and dropped every response
in the unit. The four pointer targets passed when BP-106 reported and did not
build a day later, after a package change. A module result is evidence about
that module in that tree, and the unit test and the baseline run are
separate checks, not repetitions.

The range also found verification that did nothing at three layers. Some
properties were never asserted. Others were asserted and never sampled,
because no stimulus crossed a clock edge. The census suggests two may
elaborate under lint and not reach the simulation. In this project a property
counts after a fault makes it fire in the build that is run, and the census
is a check that the property is in that build at all.

## What comes next

At the close of the range the FTQ unit is complete: eleven modules, 22
targets, 670 checks and 73 properties. It is verified against modelled
neighbors. There is no front-end top, so the FTQ and the branch prediction
cluster have never been elaborated together, and the IFU and backend do not
exist.

The next range begins instruction cache planning. I decided in this range
that the ICache is an independent module within the front end rather than
part of the IFU, while keeping the earlier decision that there is no
FTQ-to-ICache interface.

## Technical Debt Referenced

The table below reports status as of the close of this range. Later
experiments outside the range have since changed the state of some items.

| # | Item | Resolution path |
|---|---|---|
| TD-FE-2 | bp_ftq_meta_t overload by branch type. | Open. ftq_meta is built unpacked; the p3 write suppression on the indirect arm belongs in its write block when the union lands. |
| 112 | Session-063 cluster decisions recorded only in handoffs. | Opened in this range. Promote the decisions into the planning documents.[F3] |
| pft_addr | Block fall-through has no correction path. | Open, specified and unbuilt: the p2 group carries the FTB fall-through and corrects the entry's block value.[F1] |
| census | Two ftq_ifu properties may not elaborate in simulation. | Open. A short task naming which of I1-I11 are absent from sim_ftq_ifu.[F2] |
| R3 | Resolution generation test cannot be built. | Open. The resolution index carries no generation bit; one bit per in-flight instruction. |

## References

- Specifying the Fetch Target Queue (BLOG_fetch_1), for the specification
  and module decomposition this range builds.

- Branch Prediction Cluster Simulation and Mutation-Based Verification
  (BLOG_bpu_20), for the earlier cases of checks that could not fail.

## Footnotes

<!-- ticfinder_off -->
[F1] Later numbered TD #113, open. Session 069 also revised the uBTB miss
value to the lookup PC plus 32 bytes, since prediction blocks are not
aligned.

[F2] Later numbered TD #114, open.

[F3] TD #112 was closed by ruling on 2026-09-17.
<!-- ticfinder_on -->

---
<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
