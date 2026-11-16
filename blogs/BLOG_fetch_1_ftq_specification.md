<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

```
TITLE:     "Specifying the Fetch Target Queue"
FILE:      BLOG_fetch_1_ftq_specification.md
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

# Specifying the Fetch Target Queue

## Abstract

This article covers the development of specifications for the fetch target queue (FTQ) and RTL for the first FTQ module, the fetch target buffer (FTB) update scheduler.

At the close of these sessions the FTQ is specified in four documents, ftq_decisions.md, ftq_entry_formats.md, ftq_ifu_interfaces.md, and ftq_backend_interfaces.md. The FTQ is eleven modules.

Two outcomes worth mention, a flush is handled as a redirect avoiding a separate mechanism; verification of the FTB update scheduler introduces the project's first concurrent assertions.

The FTQ specification development helped identify issues in the BPU that had not been exposed by unit tests. These issues would have resulted in reduced prediction accuracy rather than functional failures.

## Background

The FTQ is a central feature in decoupled front ends. FTQ based decoupling is well published [4].

The FTQ provides a structure that allows the instruction fetch unit (IFU) to operate in parallel with the branch prediction unit (BPU).

The IFU and BPU index into the FTQ with independent pointers. As the BPU follows the predicted address path it writes or updates FTQ entries. IFU fetch traffic is triggered by the contents of the FTQ. The IFU updates entries in the FTQ as instruction traffic returns.

This separation allows the BPU to continue in the presence of fetch stalls and allows the IFU to continue during prediction stalls.

FTQ entries contain state that allows the predicted path to be corrected after the prediction is made, by the BPU's second and third prediction stages, by the IFU, and by the backend. Each correction is called a redirect. A redirect names an FTQ entry, and fetch resumes from the corrected target of that entry. On branch resolution the FTQ state is updated and predictor training is initiated.

The diagram shows the position of the FTQ in Pacino.

![FTQ boundaries](blogs/diagrams/blog_fe_1_ftq_boundary.svg)

*The FTQ's boundaries to the BPU, the IFU and the backend at the close of
the range. Edges and fields drawn in orange were added in this session.*


## Session overview

At the close of the work described in the previous article [1] the `bp_cluster` was completed, with unit tests passing.

As mentioned above, the work described in this article covers specifying the FTQ, in task files BP-098 through BP-105, referred to below as the range. The work in this series of tasks departed from the typical Pacino user/IA/PA interaction: I drove the IA interactively rather than driving the PA in the creation of IA tasks. These interactive sessions are recorded as IA-004 and IA-005.[F1]

As part of this work the IA was given a waiver allowing it to directly update planning documents. Use of the waiver is found in BP-098 through BP-105, at which time the waiver was rescinded.

Again atypically, the execution order of tasks was not numeric. BP-101 was completed before BP-098. The discussion below follows the order of work rather than task file numbering.

I made changes to the standard flow as an experiment to informally test a premise of the Pacino flow on a brand new module, the FTQ. The premise is the separation of implementation from research/planning/task creation. Claude Code is the implementation assistant (IA), and Claude.ai has been the planning assistant (PA).

This was not a formal experiment; it was more data gathering to see if a formal experiment is warranted. The findings were not cut and dried but the IA performed the task well enough that it could stand in for the PA when Claude.ai is exhibiting unreliable behavior, such as inventing obstacles, reducing task scope until the results were trivial, and failing to follow conventions used throughout the project. I'll discuss this in a future article.

## The specification documents

The IA interactive tasks produced four documents.

- `ftq_decisions.md`
    - covers the FTQ's behavior: its read ports, next-PC selection and redirect arbitration, pointers and deallocation, the stale-response shadow, the FTB update scheduler and the module decomposition.
- `ftq_entry_formats.md`
    - defines the two entry structures, the fast-path entry read on every fetch and the slow-path metadata read only at resolution.
- `ftq_ifu_interfaces.md` and `ftq_backend_interfaces.md`
    - specify the FTQ's boundaries to the IFU and the backend. The boundary to the BPU was already specified in `ftq_bpu_interfaces.md`.

Previously the FTQ had been described across other documents. These documents provide an explicit FTQ definition.

Two items were deferred. The instruction cache interface was defined after the work described in this article, in `l1i_ifu_interfaces.md`; it connects the instruction cache to the IFU, and there is no direct FTQ-to-instruction cache interface. Instruction prefetch support is planned but its definition is deferred until performance analysis.

## What the FTQ would have to drive

### BPU interface gaps found by the FTQ specification

Three gaps were discovered in the development of the FTQ specification. These were filled by BP-101.

- A fall-through address field in the FTQ entry
    - the BPU sends the fall-through address once; it is now captured in `pft_addr` of `bp_ftq_entry_t`.
    - the entry grew from 182 to 222 bits.[F2]
- Slot correction outputs from `bp_cluster`
    - ports were added to send p2 and p3 slot predictions to the FTQ on every prediction.
    - this allows the entry to be corrected whether or not a redirect occurs.
    - previously the entry kept the uBTB's p1 slot fields for its lifetime.
- A reset vector
    - the FTQ had no PC from which to issue its first prediction request.
    - `RESET_VECTOR`, 0x8000_0000, was added to `bp_defines_pkg`.

BP-101 added 24 slot correction checks to `tb_bp_cluster` and one entry width check.

The IA was instructed to verify in a side copy of the RTL that a deliberately broken design is detected by the tests.

### The history rollback input

Writing `ftq_backend_interfaces.md` identified the need to change the `bp_cluster` interface to allow the FTQ to restore the history pointers on a backend mispredict. This prevents the loss of prediction accuracy caused by predicting with history from the squashed path.

The signals added are `ftq_rollback_val`, a rollback request valid from the FTQ, and `ftq_rollback_idx`, the index of the FTQ entry whose history checkpoint is restored.

Notes:
- the FTQ request has priority over the cluster's p2 and p3 rollbacks.
- the definition of the rollback port on the cluster now specifies a 6-bit FTQ entry index, reduced from 13 bits.
    - The related planning documents were aligned, `fe_decisions.md` `ftq_backend_interfaces.md` `ftq_decisions.md`

BP-102 added 30 rollback checks to `tb_bp_cluster`, verified with the same scheme of mutations on temporary RTL.

## Position granularity and the C extension

Each FTB slot records the position of its branch within the 32-byte fetch block. `FTB_BR_POS_BITS` of 3 divides the block into eight 4-byte positions. RVA23 mandates the C extension [3], so two RVC branches can occupy the same aligned 4-byte word and receive the same position. The FTB and uBTB could record only one of them, and the position reported by the backend at resolution could not be mapped to a single slot.

![In-block branch positions](blogs/diagrams/blog_fe_1_rvc_positions.svg)

*Two RVC branches in one aligned 4-byte word. With 4-byte positions they share position 1; with 2-byte positions, after BP-099, each has its own.*

`INST_OFFSET` set both the position size in the FTB and uBTB and the PC hash shift in TAGE, ITTAGE and the SC. BP-098 split it so that the position size could change without rehashing the predictor tables:

- `POS_OFFSET_BITS`, the position size, derived from `FTB_BR_POS_BITS`.
- `PC_HASH_SHIFT`, the hash shift.
- the local copy in `tage_table.sv` was deleted.

Both resolve to 2, and every test count was unchanged.

BP-099 then set `FTB_BR_POS_BITS` to 4, dividing the block into sixteen 2-byte positions. `POS_OFFSET_BITS` became 1 by derivation, and no predictor hash changed. Storage grew by 9,472 bits, 3.0 percent across the FTB, uBTB and FTQ. The only test count that changed was the position sweep, which grew from 64 to 256 pairs.

`PC_HASH_SHIFT` remains 2, so two RVC instructions two bytes apart still share a TAGE, ITTAGE and SC index. The effect on accuracy has not been measured.

## The FTB update scheduler

The FTQ has two update channels, one for each of its two prediction slots. Every predictor accepts two updates per cycle except the FTB, whose update port has a single channel. At eight-wide issue and 15 to 20 percent branch density, 1.2 to 1.6 branches resolve per cycle, and each writes the FTB.

Rule FE-5 states that no update is dropped. Under that rule the FTB's one write per cycle would stall the backend in steady state. The FTB data array is a 1R1W RAM ~28KB. A second write port or a flip-flop array would remove the limit at a cost in area and power. Pacino keeps the single write port and amends the rule.

Amendment FE-5a, a change to FE-5 for the FTB only, permits dropping a low-value FTB update: a confidence step for a branch that hit and was predicted correctly. A dropped update delays a training step, and the next resolution of that branch trains it. Allocations and mispredict corrections are never dropped; on a conflict between them, the backend holds one. `ftq_decisions.md` 5.7 specifies the rule and five properties. Merging two updates to the same entry into one write, and banking the array, are recorded as escalations that need measurement first.

BP-100 built `ftq_ftb_sched.sv`, which has one skid register, a one-bit value function and a registered output. A new struct, `ftb_upd_t`, carries the fourteen payload fields. An occupied skid issues first, preserving resolution order; otherwise the higher-value update issues, and the channel index breaks ties.

The five properties are the project's first concurrent assertions. P1 required the output one cycle after acceptance, and P4 required it in the same cycle; no implementation satisfies both. The registered form was built, and P4 was corrected in the specification. Verilator requires `--assert` to evaluate concurrent properties; without it they are parsed and never evaluated, which is indistinguishable from passing.

The testbench runs 67 checks in five groups. Each property was broken by a separate mutation, and each failed the run. The scheduler has no consumer yet.

## Entry status and the module decomposition

BP-103 settled the last three items blocking FTQ RTL: the per-entry fetch status, stale IFU writebacks, and the module decomposition.

The status fields are flop vectors outside both entry arrays, so the entry sizes did not change. A writeback arrives at any time relative to the fetch read, so a status bit in the fast-path SRAM would require a read-modify-write of an array already read every cycle. The commit walk tests status across entries, and a redirect must clear the status of every squashed entry in one cycle. The request-issued field was dropped, since `fetch_ptr` already records which entries have been issued. Three bits per entry remain, writeback received, fault and generation, 192 bits in all.

A predecode writeback still in flight when its entry is squashed and the index reallocated would set status on the new use of that index. The FTQ handles the same problem for cluster responses with the stale-response shadow of `ftq_decisions.md` 5.6, which tracks the live request in each cluster pipeline stage. The shadow depends on the cluster's fixed latency, and IFU latency is unbounded. BP-103 added a generation bit per entry that toggles on each allocation, goes out with each request and returns with each writeback; a writeback with a mismatched generation is dropped. One bit is enough because the IFU flush bounds stale writebacks to those already presented in the flush cycle. The document records that condition, so that a change to the flush contract prompts a review of the width.

`ftq_decisions.md` 7 divides the FTQ into eleven modules by state ownership: logic that touches the same register is placed in one module, and unrelated registers are placed in separate modules. The top, `ftq.sv`, is purely structural.

| Module | Owns | Specified in |
|---|---|---|
| `ftq` | Structural top: instantiation and wiring only | ftq_decisions.md 7 |
| `ftq_ptr` | alloc_ptr, fetch_ptr | ftq_decisions.md 5.1, 5.2, 5.5 |
| `ftq_commit` | commit_ptr and the commit walk | ftq_decisions.md 5.3, 5.4 |
| `ftq_npc` | The next-PC register and the redirect arbitration that feeds it | ftq_decisions.md 4 |
| `ftq_entry` | The fast-path entry array | ftq_entry_formats.md 1, 2 |
| `ftq_meta` | The slow-path metadata array | ftq_entry_formats.md 3 |
| `ftq_status` | Per-entry status flops: writeback received, fault, generation | ftq_entry_formats.md 4 |
| `ftq_shadow` | The stale-response shadow | ftq_decisions.md 5.6 |
| `ftq_ifu` | IFU request, flush, writeback and predecode redirect ports | ftq_ifu_interfaces.md |
| `ftq_resolve` | Resolution intake and update fan-out | ftq_backend_interfaces.md 4 |
| `ftq_ftb_sched` | The FTB update scheduler; built in BP-100 | ftq_decisions.md 5.7 |

A later range added a twelfth, `ftq_upd_conv`, which forms the per-predictor update payloads (BP-119). Pointer state is split between `ftq_ptr` and `ftq_commit` because the commit pointer is the only one whose advance depends on the RAS commit port and on redirect restores.

## Flush

A flush now uses the redirect mechanism. BP-105 recorded this decision as FE-14 in `fe_decisions.md`, and six open items in other documents were closed citing it: TD #96, G24, IC-FTB-07, IC-SC-06, IC-SCT-03 and item E in `bp_arb_spec.md`.

The RAS behavior on flush, specified earlier in `ras_decisions.md` 4.4, is consistent with FE-14: a flush restores the RAS pointers from the FTQ snapshot, as a mispredict does. BP-104 closed RAS-3 as a label correction, rewrote 4.4 to state the decision first, and updated seven documents that described the RAS behavior as undefined to refer to it.

In the documents, the unused redirect cause `RC_RESERVED` became `RC_UNSPEC`, a redirect that names no instruction, for reset and debug entry. The rejected alternatives are recorded in the BP-105 task file.

The document update for FE-14 covered eleven sites, six in the first pass and five found by a subsequent search of the planning tree.

## Experiment Summary

Every task in this range was run interactively: I worked each one with the
IA in a live session, and no task was handed to an unattended run from a
PA-written task file. The Session overview gives the reason.
Status reads PASS for a task whose claim rests on simulation counts, and
COMPLETE for a specification or documentation task, which reran the bpu and
ftq units to show that no count moved. Rows are in the order the work was
done, as in the rest of the post.

| Experiment | Description | Status | Checks |
|---|---|---|---|
| BP-101 | pft_addr, TD-FE-6 slot groups, RESET_VECTOR | PASS | sim 28 to 29 (one pft_addr width check); sim_bp_cluster 973 to 997 (group I, 24); 2 mutations |
| BP-098 | INST_OFFSET split into PC_HASH_SHIFT and POS_OFFSET_BITS | PASS | 47/47, every count unchanged; 41 RTL and 9 planning sites |
| BP-099 | FTB_BR_POS_BITS 3 to 4 | PASS | 47/47; sim_bp_cluster 997 to 1765; 177 literals; +9,472 bits |
| BP-102 | TD-FE-7 history rollback input | PASS | sim_bp_cluster 1765 to 1795 (group J, 30); 4 mutations, 3 detected, 1 not detected (fixture not needed) |
| BP-100 | ftq_ftb_sched, first FTQ module and first concurrent assertions | PASS | sim_ftq_ftb_sched 67 checks, 0 failures; 5 properties, each mutated; bpu 47/47 unchanged |
| BP-103 | Entry status, TD-FE-8, eleven-module decomposition | COMPLETE | specification only; bpu and ftq rerun, unchanged |
| BP-104 | RAS-3 closed | COMPLETE | documentation only; bpu and ftq rerun, unchanged |
| BP-105 | FE-14, flush is a redirect; RC_UNSPEC | COMPLETE | documentation only; bpu and ftq rerun, unchanged |

## Design Process Notes

### The IA contribution

In the work described in this article, the IA wrote the four specification documents `ftq_decisions.md`, `ftq_entry_formats.md`, `ftq_ifu_interfaces.md` and `ftq_backend_interfaces.md`, in tasks BP-098 to BP-105.

In the process the IA identified BPU interface gaps: the fall-through address field, the p2 and p3 slot correction outputs, the reset vector and the history rollback input. These gaps were closed.

Every RTL change carries evidence matched to its claim.

- BP-098 left every test count unchanged.
- BP-099 changed one count: the position sweep test grew from 64 to 256 pairs, the square of the position count, as positions went from 8 to 16.
- BP-100, BP-101 and BP-102 each include mutations that reproduce the gap or break a property.
- BP-102 reported its undetected mutation as a result.

The IA also reported its own errors: the incomplete first pass of the flush document update, and a mutation run it initially reported as a hang, which was a command timeout during compilation.

### The PA contribution

The PA wrote no task file in this range. The IA's session handoffs are not among the files the PA reads at the start of a session, so each ended with a list of items for the PA to ratify: FE-5a, the two deferrals (the instruction cache interface and prefetch), the out-of-order task numbering, FE-14, the FTB flush gate, the `RC_UNSPEC` rename, the module decomposition and the per-entry status flops.

### My contribution

I granted the IA a waiver to update planning documents directly, limited to tasks BP-098 to BP-105.

In BP-104 I declined three IA proposals: removing the unused RAS flush ports, resolving the FTB flush in the same task, and opening a debt item for the lint suppression of unused ports.

The definition of `RC_UNSPEC` as a redirect that names no instruction is mine.

Since this was a modification to the Pacino IA/PA methodology I was careful to limit the amount of freedom given to the IA for file modification. Usually this is handled by interaction with me and the PA, and then explicitly listed as context in the task file. In these sessions that backstop was not in place.

As the work progressed I expanded the files the IA was permitted to edit. BP-102's task file limited changes to `bp_cluster.sv`, `tb_bp_cluster.sv` and the task file itself. After its RTL and run were complete I relaxed the limit, so the planning documents could be updated.

I added a section to CLAUDE.md on conduct in interactive sessions: a rule to check whether a topic is closed before raising it, and a directive to avoid unnecessary jargon and picturesque phrasing.

### The generalization

Six problems in this range were found by specification: the fall-through address field, the reset vector, the slot correction outputs, the history rollback input, the contradictory scheduler properties P1 and P4, and the stale IFU writeback. The four BPU interface gaps were in RTL that passed every test, because no test can check a port a module does not have. Specifying, port by port, what the next unit must drive and receive tested the cluster's boundary in a way its own testbench could not.

The range also showed that restated decisions drift. Seven documents restated the RAS flush decision and had diverged from it, and the first pass of the FE-14 document update missed five sites. In this project a decision has one home, other documents refer to it, and a sweep of the tree is done with a search whose output is recorded.

## What comes next

At the close of the range the FTQ is specified and one of its eleven modules is built. No open item blocks the remaining modules. Later tasks, starting with BP-106, return to PA-written task files under the standing rule that planning documents are read-only to the IA, and build the remaining modules.[F4]

Items that remain open:

- the effect on prediction accuracy of `PC_HASH_SHIFT` of 2 is unmeasured.
- G10, the TAGE and ITTAGE metadata overload, is undecided.
- G25, the source of `ftb_fastpath_en`, is undecided.
- `RC_UNSPEC` has no producer until there is a backend.
- instruction prefetch remains deferred.


## Technical Debt Referenced

The table reports status as of the close of this range. Later experiments
outside the range have since changed the state of some items. TD #96 is
tracked in the Technical Debt table of `planning/PROJECT_STATUS.md`. The
TD-FE items are owned by `planning/arch/fe_decisions.md`, are collected for
the FTQ in `planning/arch/ftq_decisions.md` 6, and are summarized in the
PROJECT_STATUS session log for this range.

| # | Item | Status at close of range | Source |
|---|---|---|---|
| TD #96 | Flush behavior: define it, implement it, update all references. | CLOSED BP-105. A flush is a redirect, FE-14. The flush ports are redundant and retained; read ras_decisions.md 4.4.2 before re-raising. | PROJECT_STATUS.md, Technical Debt |
| TD-FE-1 | IFU interface unspecified. | CLOSED in full: ftq_ifu_interfaces.md, and the entry status fields in BP-103. | fe_decisions.md; ftq_decisions.md 6 |
| TD-FE-3 | pc and per-slot target at 40 bits. | Open. 39 suffice under C, 35 with block alignment. A width optimization.[F5] | fe_decisions.md; ftq_decisions.md 6 |
| TD-FE-4 | pred_src has no functional consumer. | Open. Diagnostic; populated only where the information is already available. | fe_decisions.md; ftq_decisions.md 6 |
| TD-FE-6 | FTB classification and positions reach no FTQ port. | CLOSED BP-101. Slot correction groups at p2 and p3, valid on every FTB answer. | fe_decisions.md; ftq_bpu_interfaces.md |
| TD-FE-7 | No history rollback trigger input on bp_cluster. | CLOSED BP-102. ftq_rollback_val and ftq_rollback_idx, priority over the cluster's own arms. | fe_decisions.md; ftq_backend_interfaces.md 8 |
| TD-FE-8 | Stale IFU writeback sets status on a reallocated index. | Opened and CLOSED BP-103. One generation bit toggled per allocation. | fe_decisions.md; ftq_entry_formats.md 4.4; ftq_ifu_interfaces.md 6.1 |

## Identifiers

The project tracks open questions, decisions and debt in registries spread
across the planning documents. This table lists every identifier used in
the post, with the document that owns it. Paths are relative to the
repository root.

| Identifier | Kind | Description | Source document |
|---|---|---|---|
| BP-nnn | Task file | One file per task; this range is BP-098 to BP-105, and BP-106 and BP-119 are later tasks cited here | prompts/BP-nnn.md |
| IA-004, IA-005 | Interactive session | The two IA sessions of this range, recorded in each task file's header | prompts/BP-098.md to prompts/BP-105.md |
| TD #96 | Technical debt | Flush behavior. CLOSED BP-105 | planning/PROJECT_STATUS.md, Technical Debt |
| TD-FE-1 to TD-FE-8 | Front-end technical debt | See Technical Debt Referenced above | planning/arch/fe_decisions.md |
| FE-5 | Front-end decision | No prediction or update is dropped except as FE-5a permits | planning/arch/fe_decisions.md |
| FE-5a | Front-end decision | An FTB update may be dropped on collision, and only when it is low value | planning/arch/fe_decisions.md |
| FE-14 | Front-end decision | A flush is a redirect; the front end has no flush event | planning/arch/fe_decisions.md |
| G10 | BP cluster open TBD | TAGE and ITTAGE metadata overload scheme. Open | planning/PROJECT_STATUS.md, BP Cluster Open TBDs |
| G24 | BP cluster open TBD | FTB flush protocol, ftb_flush_px. CLOSED BP-105 | planning/PROJECT_STATUS.md, BP Cluster Open TBDs |
| G25 | BP cluster open TBD | Source of the FTB fast-path enable, ftb_fastpath_en. Open | planning/PROJECT_STATUS.md, BP Cluster Open TBDs |
| IC-FTB-07 | FTB interface item | Do not implement flush logic until specified. CLOSED BP-105 | planning/interfaces/ftb_interfaces.md |
| IC-SC-06 | SC interface item | SC flush port definitions (_px signals). CLOSED BP-105 | planning/interfaces/sc_interfaces.md |
| IC-SCT-03 | SC table interface item | SC table flush port definitions (_px signals). CLOSED BP-105 | planning/interfaces/sc_table_interfaces.md |
| bp_arb_spec.md item E | Arbiter open item | Prediction and update queue behavior on flush. CLOSED BP-105 | planning/arch/bp_arb_spec.md |
| RAS-3 | RAS open item | RAS recovery on flush. CLOSED BP-104 as a label correction | planning/arch/ras_decisions.md 4.4 |
| P1 to P5 | Scheduler property | The five FTB update scheduler properties; P4 corrected in BP-100 | planning/arch/ftq_decisions.md 5.7.4 |

## References

[1] Branch Prediction Cluster Simulation and Mutation-Based Verification
(BLOG_bpu_20), for the cluster boundary this range extends,
https://uarchlabs.github.io/blog/branch-prediction-cluster-simulation-and-mutation-based-verification/

[2] Pacino, https://github.com/uarchlabs/pacino. The planning documents and
task files cited in this post are in planning/ and prompts/.

[3] RISC-V Profiles, RVA23 Profile, https://github.com/riscv/riscv-profiles

[4] Reinman, Glenn, Brad Calder, and Todd Austin. "Optimizations enabled by a decoupled front-end architecture." IEEE Transactions on Computers 50.4 (2001): 338-355.

## Footnotes

<!-- ticfinder_off -->
[F1] Transcripts of the two interactive sessions are in the repository [2]
as `ia_context/ia_exports/ia_export_session-004.txt` and
`ia_context/ia_exports/ia_export_session-005.txt`.

[F2] The next range found that `pft_addr` is written once at p1 and that
nothing can correct it when the FTB ends the block earlier than the uBTB did.
The fix was specified and not built at the close of that range.

[F3] BP-102 recorded the index as seven bits. A later correction (session
072) records that the index is `FTQ_IDX_BITS`, six bits; seven is
`FTQ_PTR_BITS`.

[F4] The planning-document rule is in CLAUDE.md's fixed constants and
applies from BP-106.

[F5] The TD-FE-3 resolution path shown here was subsequently changed in
later sessions.
<!-- ticfinder_on -->

---
<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry experience
spanning performance modeling, RTL implementation, and architecture for
high-performance out-of-order processors. He has contributed RTL to Pentium 4,
ARMv7, TI C6x and RISC-V designs, and recently served as sole architect and
full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in
an 8-issue RVA23 RISC-V processor, from research through timing closure at
2.75 GHz. He holds more than 20 issued patents in processor design,
architecture, and hardware virtualization. He is the author of Pacino and the
uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
