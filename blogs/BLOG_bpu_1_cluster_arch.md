<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->

# BLOG_bpu_1_cluster_arch.md

```
 FILE:    BLOG_bpu_1_cluster_arch
 STATUS:  unpublished
 UPDATED: 2026-xx-xx
 CONTACT: uarchlabs@gmail.com
```

<!--
---
title: "Building a Seven-Predictor Branch Prediction Cluster for RVA23"
author: Jeff Nye
date: 2026-03-28
copyright: "Copyright 2026 Jeff Nye"

---

*This is part 1 of a series on branch predictor co-design.*
- [Part 1: Cluster Architecture](BLOG_bpu_1_cluster_arch.md)
- [Part 2: History and uBTB](BLOG_bpu_2_history_ubtb.md)
- [Part 3: Loop Predictor](BLOG_bpu_3_loop_pred.md)
- [Part 4: When the Tools Fail](BLOG_bpu_4_limits.md)

---
-->

## A New Aspect of Co-Design

This is the first of a set of posts on the design and execution of the branch prediction unit (BPU), beginning with task file BP-001. The design of the BPU exercises different aspects of the co-design methodology, with more research and more interaction with the user for the planning assistant (PA, Claude.ai).

The RVA23S64 decoder is, by definition, a specification-driven design, with clear implementation requirements. There are more tradeoffs and choices to be made in the BPU design. In developing the decoder the PA provided instructions for the implementation assistant (IA, Claude Code) on where to look for the definitions (riscv-opcodes [1]) and expectations on implementation. The PA's role in the decoder track was to segment the complete task into experiment files and load-balance each against the IA's context budget. In developing the BPU the PA role will expand with greater interaction in web research and user dialog.

Branch prediction is well-researched but with opportunities for innovation and customization not present in a strict specification driven implementation like RVA23.

The PA researched public information on BPU configurations for commercial and open source designs [2] [3] [4]. The PA was also instructed to assess the results of the branch prediction championships [5] [6] to mine for component configurations and parameters. Finally there is the extensive body of research literature covering predictor algorithms, table sizing, history management, and inter-component interactions. In the early BPU co-design sessions the user contributed known predictor configurations and domain knowledge of the redirect architecture. The PA researched alternative configurations, synthesized published documentation, and drove the RAS micro-architecture research from external sources. The BPU configuration emerged from that exchange.

This is the first exercise of the PA as a research partner on architecture questions, not just an orchestrator of implementation tasks, this shift in role surfaced methodology gaps -- in particular, error attribution and planning review discipline -- that subsequent sessions addressed directly.

The fabrication errors caught before BP-002 illustrate a hazard in this mode. Origins were mixed: ambiguous or incomplete direction from the user, PA extrapolation beyond what was specified, and IA (Claude Code assistant) assumptions for undefined elements. The early session record does not separate these cleanly. That gap is itself a methodology note -- error attribution in a multi-session AI-assisted flow requires more deliberate capture than was applied here. The errors were caught in a joint planning review before any RTL was generated, at low cost. Mid-implementation discovery would have been significantly more expensive. The methodology was modified to improve error assignment and its documentation.

The predictor hierarchy, table sizes, and staging decisions recorded here are working engineering choices subject to performance analysis as the design matures.

---

## Predictor Hierarchy

The BP cluster contains seven predictors: a micro Branch Target Buffer
(uBTB), a loop predictor (LP), a Fetch Target Buffer (FTB), a tagged geometric history length predictor (TAGE) [7], a Statistical Corrector (SC) [8], an indirect target TAGE predictor (ITTAGE) [9], and a Return Address Stack (RAS) [10].

![BPU Pipeline](diagrams/bpu_pipeline_staging.svg)

The diagram makes the distinction between the conditional predictors and the target predictors. The predictors in each group operate with the conventional separation of branch types, indirect and conditional. The RAS handles return instructions, the ITTAGE handles target predictor for indirect branches.

The override chain described below applies exclusively to conditional branches. For the conditional group, the SC may or may not override the TAGE prediction based on the confidence of either the TAGE or SC, as such the SC prediction process requires TAGE output to begin.

The cluster supports dual prediction: two independent next-PC predictions per fetch bundle, selected at elaboration time via the NUM_PRED_SLOTS parameter. Dual mode is the default. When dual mode is active, two independent update channels handle both conditional and indirect branch resolution concurrently. Single-channel mode exists for silicon debug and is not a production configuration.

The initial configuration of the BPU elements are parameter driven. The parameters are summarized in [Predictor Parameter Reference](#predictor-parameter-reference)

## Predictor Operation

The uBTB is a single-cycle predictor. The PC is presented in s0 and the
prediction result is available in s1. It is a 256-entry 4-way associative
table that provides the first next-PC prediction and starts speculative
fetch. It does not generate a redirect signal; it either supplies a
prediction or withholds one. On a miss, fetch proceeds sequentially until
a later stage corrects it.

The LP is also a single-cycle predictor, presenting its
result in s1. The LP prediction overrides the uBTB prediction if a loop
branch is detected and the LP has sufficient confidence. The override
control reads the LP confidence counter and determines whether the LP
prediction should be used.

The FTB is a two-cycle predictor. The PC is presented in s0 and the
hit/miss/prediction result is available in s2. The FTB is the
authoritative branch prediction selector, providing the redirect control
logic with branch type. Returns use the RAS target address; indirect
non-return branches use the ITTAGE target prediction; conditional branches
use the uBTB, LP, TAGE, or TAGE+SC predictions. In the conditional branch
chain, later predictors are by design more accurate. If a later predictor
does not contradict an earlier predictor there is no need for redirection.

TAGE is also a two-cycle predictor, presenting its result in s2. The SC
predictor uses the TAGE s2 result as input and supplies its prediction in
s3. This TAGE-then-SC arrangement is standard in the branch prediction
literature, and various latency optimizations exist to reduce the delay.

ITTAGE is a three cycle predictor. The PC is presented in s0 and the result is available in s3.

### Conscious Design Choices and Future Experiments

Several deliberate design choices in this micro-architecture are worth
pointing out as each represents a planned experiment in the PA/IA
co-design methodology.

The loop predictor is included as a deliberate architectural choice. Loop
predictors in high-performance decoupled front-end designs have become less
common. The cost-benefit trade-off will be evaluated during performance
analysis; inclusion or exclusion will follow from that result. This will
also serve as an exercise in the PA/IA methodology for performance
analysis.

The TAGE and SC configuration is conventional. There are publications [11]
that modify this arrangement, enabling the SC to use a simplified TAGE
output one cycle earlier. An experiment will be structured to determine
whether the PA/IA can identify these modifications from the literature,
implement them, and measure the performance benefit.

The ITTAGE design is structurally similar to TAGE but conventionally
requires an extra cycle to form the full target address, using a look-up
table and adder that accept a region pointer and offset from the TAGE-like
structures. Under some conditions it is possible to choose a virtual
address range that fits directly in the TAGE-like entry, saving that cycle.
This is a performance-analysis-driven decision; the PA/IA methodology will
be used to research the applicable conditions, provide the implementation,
and measure the benefit in a future performance analysis step.

A pre-decode branch detection stage can provide an early branch type hint
to the RAS ahead of the FTB s2 result, reducing the redirect penalty on
return-heavy workloads. This is also a opportunity to exercised the
performance analysis phase of the PA/IA methodology.

---

## Redirect Architecture

Two distinct concerns drive redirects in this cluster: conditional branch direction and branch target. This section covers each separately.

### Direction

Direction prediction for conditional branches proceeds in three stages. The uBTB and loop predictor supply the initial direction at s1; speculative fetch begins on that result. TAGE refines the conditional direction at s2. The SC may further override the TAGE s2 direction at s3. The FTB has no direction prediction role.

The s2_redirect direction trigger fires when TAGE produces a conditional direction that contradicts the s1 prediction. The s3_redirect direction trigger fires when the SC overrides the TAGE s2 direction.

### Target

Target selection is type-gated throughout. The FTB provides targets for direct branches. The RAS provides return addresses for returns. ITTAGE provides targets for indirect non-return branches.

The s2_redirect target triggers are: the FTB producing a target or branch type that contradicts the uBTB prediction, and the RAS producing a return address that differs from the uBTB prediction. When s2_redirect fires, type-gate priority determines the selected target: RAS for returns, raw ITTAGE for indirect non-return branches, FTB target for all direct branches. The FTB entry is held for use at s3.

At s3_redirect, the target comes from the FTB result held from s2. ITTAGE may refine an indirect target at s3 if the s2 redirect used a raw pre-final ITTAGE result.

### Pipeline Staging

The direction timeline is as follows. In s0, all predictors begin index calculations. In s1, the uBTB and loop predictor direction results are valid and speculative fetch begins. In s2, the TAGE direction result is valid; s2_redirect fires on direction if TAGE contradicts the s1 prediction. In s3, the SC direction result is valid; s3_redirect fires if SC overrides the TAGE s2 direction.

The target timeline proceeds in parallel. In s0, the FTB, TAGE, SC, and ITTAGE dispatch their SRAM addresses. In s2, the FTB and RAS results are valid; s2_redirect fires on target if either contradicts the uBTB prediction; the FTB entry is held for s3. In s3, ITTAGE finalizes; an indirect target may be refined if s2 used a pre-final ITTAGE result.

The design accepts up to two in-flight redirect operations as the cost of running the full predictor hierarchy. For a server-class, 8-issue, out-of-order processor, the accuracy benefit from the full hierarchy is expected to exceed the redirect penalty. That expectation will be confirmed through performance analysis.

---

## Return Address Stack Design

The RAS uses a dual-stack design [10]: a speculative stack implemented as a
persistent linked circular array, and a separate commit stack implemented
as a conventional circular structure. The speculative stack is the primary
prediction structure; the commit stack holds only confirmed, architecturally
committed return addresses and serves as a fallback.

![RAS Structure](diagrams/ras_structure.svg)

A naive circular stack corrupts entries under deep speculative execution in
an out-of-order machine. When a branch mispredict causes a rollback many
cycles deep, a series of speculative push and pop operations may have
overwritten entries below the stack top that are still needed. A
conventional stack cannot recover those entries without replaying every
individual operation from the rollback point, which is complex and costly.
The persistent linked array avoids this entirely.

The speculative stack never overwrites data. Push advances the write pointer
TOSW (Top Of Stack Write), allocates a new slot, and records the previous
TOSR (Top Of Stack Read) as the NOS (Next-On-Stack) pointer. Pop follows
the NOS of the current top without removing any data. Redirect recovery
reduces to restoring three pointer values -- TOSR, TOSW, and BOS (Bottom
Of Stack) -- from a snapshot stored per FTQ (Fetch Target Queue) slot.
The full history of speculative stack states is preserved in the linked
array with no replay required.

![RAS Push and Pop](diagrams/ras_push_pop.svg)

When the speculative stack is empty during a pop, the commit stack top is
used as the fallback prediction without consuming the entry. Committed state
must not be modified speculatively, so the entry is read but not popped.

The commit stack update policy is an intentional exception to the general
BP cluster update policy. All main predictor tables -- TAGE, SC, ITTAGE,
uBTB, and the loop predictor -- are updated post-execute, as soon as branch
resolution is known by the execution unit, without waiting for retirement.
The RAS commit stack is specifically tied to retirement because it records
the architecturally committed call and return state, not the speculative
state.

At s3, if the s3 structural prediction disagrees with the s2 stack
operation, an inverse repair is applied: a push at s2 that s3 considers
incorrect is repaired with a pop, and vice versa. Push-to-pop and
pop-to-push cannot occur within a single s2/s3 pair.

Call and return detection follows RISC-V register conventions. A call is a
JAL, JALR, or C.JALR where the destination register is x1 or x5. A return
is a JALR, C.JR, or C.JALR where the source register is x1 or x5, with
C.JALR using x5 excluded from return classification. JALR prediction is
split three ways: the FTB handles stable-target calls, the RAS handles
convention-matched returns, and ITTAGE handles history-dependent indirect
dispatches.

---

## FTQ Entry Split

The FTQ entry is split into two parallel SRAMs indexed by the same FTQ
slot. The fast-path entry is read every prediction cycle and carries the
prediction result, branch type, predicted target, source predictor, and the
history pointer checkpoints needed for redirect recovery. The slow-path
meta entry is read only on post-execute update and carries all
predictor-internal metadata needed to update each table correctly after
branch resolution.

The split is motivated by timing. A wide metadata entry that accumulates
TAGE provider and alternate-provider indices, saturating counter snapshots,
SC counter values, loop predictor iteration counts, and ITTAGE flags should
not sit on the timing-critical read path. Separating it to a wider, less
frequently accessed SRAM removes it from that path entirely.

The FTQ depth is 64 entries, giving 6-bit branch identifiers that serve as
the shared key across both SRAMs and as the rollback address for redirect
recovery. History checkpoints in the fast-path entry store only the GHR
(Global History Register) and PHR (Path History Register) circular buffer
pointers, not the folded histories. Folded histories are recomputed on
rollback from the circular buffer contents. The checkpoint cost per FTQ
slot is 13 bits (8b for the GHR pointer, 5b for the PHR pointer) rather
than the 288 bits a full snapshot of both buffers would require.

---

## Predictor Parameter Reference

The tables below consolidate all predictor parameters in one place for
reference. Parameters marked TBD are deferred to the relevant
implementation session.

### Global Parameters

| Parameter          | Value  | Notes                              |
|--------------------|--------|------------------------------------|
| VA_WIDTH           | 40b    | Virtual address width              |
| GHR_WIDTH          | 256b   | Global history register depth      |
| PHR_WIDTH          | 32b    | Path history register depth        |
| GHIST_PTR_BITS     | 8b     | GHR circular buffer pointer width  |
| PHIST_PTR_BITS     | 5b     | PHR circular buffer pointer width  |
| FTQ_DEPTH          | 64     | Fetch target queue entries         |
| FTQ_IDX_BITS       | 6b     | FTQ slot index width               |
| FETCH_BLOCK_BYTES  | 64     | Fetch block size in bytes          |
| NUM_PRED_SLOTS     | 1 or 2 | Elaboration-time dual predict mode |

### uBTB

| Parameter      | Value | Notes                                  |
|----------------|-------|----------------------------------------|
| UBTB_ENTRIES   | 256   | Total entries                          |
| UBTB_WAYS      | 4     | Associativity                          |
| UBTB_SETS      | 64    | Sets (ENTRIES / WAYS)                  |
| UBTB_IDX_BITS  | 6b    | PC[7:2]                                |
| UBTB_TAG_BITS  | 20b   | PC[26:7], accepted aliasing risk       |
| Entry width    | 66b   | valid+tag+br_type+target+taken+carry   |

### Loop Predictor

| Parameter      | Value | Notes                                  |
|----------------|-------|----------------------------------------|
| LP_TBL_ENTRIES | 256   | Total entries                          |
| LP_TBL_WAYS    | 4     | Associativity                          |
| LP_N_SETS      | 64    | Sets (ENTRIES / WAYS)                  |
| LP_IDX_BITS    | 6b    | Derived from LP_N_SETS                 |
| LP_TAG_BITS    | 14b   | Tag width                              |
| LP_ITR_BITS    | 14b   | Iteration counter width                |
| LP_CNF_BITS    | 2b    | Confidence counter width               |
| LP_AGE_BITS    | 8b    | Age/replacement counter width          |

### FTB

| Parameter   | Value | Notes               |
|-------------|-------|---------------------|
| FTB_ENTRIES | 2048  | Total entries       |
| FTB_WAYS    | 8     | Associativity       |

### TAGE

| Table | Banks | Entries | Tag | CTR | Useful | History |
|-------|-------|---------|-----|-----|--------|---------|
| T0    | 2     | 2048    | --  | 2b  | --     | --      |
| T1    | 2     | 2048    | 8b  | 3b  | 2b     | 8b      |
| T2    | 2     | 2048    | 8b  | 3b  | 2b     | 13b     |
| T3    | 2     | 2048    | 8b  | 3b  | 2b     | 32b     |
| T4    | 2     | 2048    | 8b  | 3b  | 2b     | 119b    |

T0 is the base table: 2b CTR only, no tag, no valid, no useful field.
T1-T4 are tagged tables: 1b valid, 8b tag, 3b CTR, 2b useful per entry.
Each tagged table maintains three folded histories (index, tag_fh1,
tag_fh2).

### SC (Statistical Corrector)

| Table | Entries | Width | History | Folds | Notes              |
|-------|---------|-------|---------|-------|--------------------|
| ST0   | 512     | 6b    | 0b      | none  | No history         |
| ST1   | 512     | 6b    | 4b      | 1     | Index fold only    |
| ST2   | 512     | 6b    | 16b     | 1     | Index fold only    |
| ST3   | 512     | 6b    | 64b     | 1     | Index fold only    |
| ST4   | 1024    | 6b    | none    | none  | Direct mapped      |

IT5 and ST4 were a source of an error in the specification and subsequent
implementation. The error was captured on review.

Initially IT5 was mistakenly specified as a BrIMLI table, obviously incorrect
for an indirect target predictor branch table. The tables that are shown 
here have been corrected to avoid confusion in the references.

ST4 is the BrIMLI table. The parameters in the tables have been corrected.
The ST4 implementation is for 64 byte regions.

Future work will explore the cost/benefit of the branch source (BrIMLI)
and branch target (TaIMLI) counters and the two sizes of each found in
Seznec[12], 64B and 4B regions.

### ITTAGE

| Table | Banks | Entries | FH  | FH1 | FH2 | History | Notes      |
|-------|-------|---------|-----|-----|-----|---------|------------|
| IT1   | 2     | 256     | 4b  | 4b  | 4b  | 4b      | 38b target |
| IT2   | 2     | 256     | 8b  | 8b  | 8b  | 8b      | 38b target |
| IT3   | 2     | 512     | 9b  | 9b  | 8b  | 13b     | 38b target |
| IT4   | 2     | 512     | 9b  | 9b  | 8b  | 16b     | 38b target |
| IT5   | 2     | 512     | 9b  | 9b  | 9b  | 32b     | 38b target |

Targets stored as Sv39-1 in width VA_WIDTH (40b) values.

### RAS

| Parameter             | Value | Notes                          |
|-----------------------|-------|--------------------------------|
| Speculative entries   | 48    | Persistent linked circular     |
| ret_addr width        | 41b   | FTB fallThroughAddr            |
| NOS pointer width     | 6b    | log2(48)                       |
| Recursion counter     | TBD   | Deferred to implementation     |
| TOSR / TOSW / BOS     | 6b ea | Snapshot stored per FTQ slot   |
| Commit stack entries  | TBD   | Smaller than speculative stack |

### History Module

| Parameter      | Value | Notes                                       |
|----------------|-------|---------------------------------------------|
| GHR_WIDTH      | 256b  | Circular buffer, pointer-addressed          |
| PHR_WIDTH      | 32b   | Circular buffer, pointer-addressed          |
| Total folds    | 27    | 12 TAGE + 12 ITTAGE + 3 SC                  |
| Checkpoint     | 13b   | ghist_ptr (8b) + phist_ptr (5b) per slot    |
| PHR folding    | TBD   | Deferred to TAGE/ITTAGE implementation      |

---

## Interface First: BP-001

The co-design discipline from the decoder track carries forward: define the
complete SystemVerilog type package before writing any implementation module.
For the BP cluster, this meant capturing every parameter, enumeration, and
struct definition in a single shared package file, bp_pkg.sv, before the
uBTB, loop predictor, history module, or any other module was started.
This package is the single source of truth for all types, widths, and
structural constants shared across the cluster. Having it locked and
verified before implementation begins ensures that every subsequent module
is built against a consistent, tested foundation. This was experiment
BP-001.

BP-001 produced bp_pkg.sv (397 lines containing all BP cluster parameters,
enumerations, and struct type definitions), a self-checking combinational
testbench tb_bp_pkg.sv (207 lines), and a Makefile with lint and simulation
targets (33 lines). All 15 checks passed on the first simulation run after
one Verilator flag addition for a naming convention conflict. Zero errors,
zero warnings.

The testbench verified that all structs instantiated correctly, all enum
values were distinct, key field widths matched their parameters, and struct
packing was consistent across assignment and copy. Catching field-width
errors at this stage costs almost nothing; catching them mid-module during
a later experiment costs a debugging session and a full context reload.

The session that followed BP-001, before BP-002 was run, caught five
errors during a critical review of the planning document and the BP-002
prompt draft. The errors had multiple plausible origins: ambiguous direction
from the user, the PA extrapolating beyond what was explicitly specified,
and the IA (Claude Code assistant) making assumptions for elements not yet
defined. The session record does not separate these causes cleanly, and that
is itself a methodology observation noted here. 

The most instructive error was a label applied to IT table IT5 that belonged to
SC ST4 -- a plausible-sounding association between two related but distinct
mechanisms that propagated silently into the draft prompt and was caught only
through deliberate review. All five errors were corrected before any RTL was
generated.

To simplify referencing the table parameters below have been corrected
with notation referring to the errors.

---

## Prompt Discipline and AI Leverage

During the architecture extraction sessions a question came up that is
worth recording for the methodology record: as experiment prompts become
more detailed, does that diminish the leverage the AI assistant provides?

The experience from the decoder experiments and BP-001 suggests the answer
is: not if the detail reflects architectural decisions you have already
made. The outcome depends on what kind of detail is being added.

Two kinds of prompt detail exist. The first is architectural constraint:
specifying that the FTQ entry uses a pointer-only history checkpoint rather
than a full GHR snapshot, that the SC index arrays must be split because
ST0 through ST3 and ST4 have different index widths and cannot form a
uniform packed array, that the RAS snapshot is a sub-struct bundled inside
the FTQ fast-path entry. This kind of detail does not diminish AI leverage.
It directs that leverage toward the intended architecture rather than
letting the assistant invent one. The implementation work -- writing correct
SystemVerilog, running Verilator, iterating on errors -- remains entirely
the assistant's job.

The second kind is implementation specification: dictating how to structure
a case statement, which signal names to use at the wire level, exactly which
lines of code to write. Prompts that reach this level of detail turn the
assistant into a syntax checker. That does diminish leverage.

The prompts in this project sit almost entirely in the first category. A
useful test for any given constraint: if you removed it, would the assistant
still produce something architecturally correct? If yes, the constraint is
probably over-specified. If no, it is earning its place.

A practical metric from the decoder experiments and BP-001: the ratio of
RTL lines written by the assistant to prompt lines written by the engineer
ran approximately 500 to 1. For BP-001 specifically, 397 lines of verified
SystemVerilog and 207 lines of testbench were produced from a prompt of
roughly one to two pages of architectural constraint and procedural
direction. Prompt length is not the right measure of leverage. That ratio
is.

---

## Experiment Summary

| Experiment | Description  | Status | Checks | RTL Lines | Runtime | Context |
|------------|--------------|--------|--------|-----------|---------|---------|
| BP-001     | bp_pkg.sv    | PASS   | 15/15  | 397       | 10m.49s | 50% est |
|            | type package |        |        |           |

---

## What Comes Next

BP-001 defined the shared parameter and type package that all subsequent
modules depend on. The next session begins implementation with the history
module: the GHR and PHR circular buffers, the 27 folded histories consumed
by TAGE, ITTAGE, and SC, and the checkpoint and rollback mechanism. After
that, the uBTB becomes the first prediction-path module with actual SRAM
structures and a testbench that exercises hit, miss, and replacement
behavior.

Those two modules, which together form the s1 prediction infrastructure,
are covered in [Part 2](BLOG_bpu_2_history_ubtb.md) of this series.

---

## Design Process Notes

The architecture described in this post was not derived from a
specification. Understanding who contributed which parts of it is
relevant to anyone trying to apply this methodology to their own domain.

### What the user contributed

The pipeline staging model came from the user: the s0-s3 stage
assignments for each predictor, the override chain (SC overrides TAGE
which overrides FTB which overrides uBTB), the speculative RAS update
policy at s2, and the redirect trigger conditions. The predictor
hierarchy itself primarily from domain knowledge, but someone with less
BPU experience could use the BOOM/Xiangshan Kunminghu architectures as
reference, with one deliberate addition: the loop predictor. 
Neither Xiangshan or BOOM include a loop predictor. Its inclusion here 
is a conscious design choice, noted as a future performance analysis 
experiment.

The user also provided initial parameter values for the TAGE and ITTAGE
tables, the FTQ depth and split rationale, and the SC index array layout
constraint that emerged during the BP-001 review. 

The parameter sets are again something supplied by user domain knowledge
but there are multiple sources of detailed parameters in the literature, 
in the BOOM and Xiangshan designs.

The user caught the five errors in the PA's first BP-002 draft 
during the planning review described in the Interface First section above.

### What the PA contributed

For the decoder track, the PA's job was decomposing a fixed external
specification into experiment files. For the BPU, the configuration space
was open. The PA researched predictor configurations from published
championship results, commercial processor disclosures, and open source
documentation. It synthesized that material into a coherent set of
architectural options, asked clarifying questions that surfaced implicit
decisions the user had not yet made explicit, and wrote the complete
bp_cluster.md planning document.

The RAS micro-architecture required specific research. The user indicated
the direction -- persistent linked array, dual stack -- and the PA traced
that design to its source, identified the pointer structure (TOSR, TOSW,
BOS, NOS), confirmed the commit stack update policy, and recommended
the speculative s2 update policy over post-execute after laying out the
trade-off. The user made the final call with a single response.

The PA also wrote the BP-001 experiment prompt, which is where the
interface between PA and IA becomes concrete.

### What the prompt constrained versus what the IA filled in

The BP-001 prompt specified struct names, field names, the dependency
ordering of struct definitions, naming conventions, file paths, and
Makefile targets. It included a Binding Previous Decisions section locking
five items that had been settled in prior planning sessions but were not
yet in bp_cluster.md -- among them the VA_WIDTH = 40 choice (direct VA
storage rather than region pointer plus offset) and the exact split
between the fast-path and slow-path FTQ SRAMs.

What the IA filled in without guidance: all SystemVerilog syntax, all
$clog2 derivations, the packed struct definitions, the testbench
self-check logic, and the Makefile. When the IA encountered four open
items -- the TAGE derived parameter widths, the SC index array split,
the RAS snapshot sub-struct bundling, and the FTQ confidence field width
-- it resolved each, flagged every one explicitly in the Results Capture
section, and left no silent assumptions. That behavior is what the
interface-first methodology is designed to produce: the IA executes
against architectural constraints and surfaces its own assumptions rather
than burying them.

The 500:1 line ratio cited in the Prompt Discipline section reflects this
division. The number is a measure of leverage, not a measure of how little
the engineer did. The constraints that generated that leverage took several
sessions of architecture extraction and planning review to arrive at.

### The generalization

A domain expert applying this methodology to a different subsystem -- a
cache hierarchy, a rename unit, a memory disambiguation block -- will find
the division of labor the same. The user contributes the architectural
intent that cannot/difficult to be researched: the tradeoffs that follow 
from knowing what the machine is supposed to do and how it is expected to 
be used. The PA contributes the research, the synthesis, and the prompt 
structure that makes the IA's output reliable.  The IA contributes the 
implementation work that is time-intensive at scale. Evidence from this 
session indicates the methodology works effectively with clear separation 
of roles.

---

## References

[1] riscv-opcodes, https://github.com/riscv/riscv-opcodes, accessed 2026.05.01

[2] Wang, Kaifan, et al. "XiangShan open-source high performance RISC-V processor design and implementation." Journal of Computer Research and Development 60.3 (2023): 476-493.

[3] Zhao, Jerry, et al. "Sonicboom: The 3rd generation berkeley out-of-order machine." Fourth Workshop on Computer Architecture Research with RISC-V. Vol. 5. International Symposium on Computer Architecture Valencia, 2020.

[4] Grayson, Brian, et al. "Evolution of the samsung exynos cpu microarchitecture. In 2020 ACM/IEEE 47th Annual International Symposium on Computer Architecture (ISCA)." IEEE, may. 2020.

[5] 6th Championship Branch Prediction (CBP2025), in conjunction with ISCA-52, Tokyo, Japan, June 21, 2025. Organizers: R. Sheikh and S. Jain (ARM), https://ericrotenberg.wordpress.ncsu.edu/cbp2025/ , accessed 2026.05.01

[6] 5th JILP Workshop on Computer Architecture Competitions (JWAC-5): Championship Branch Prediction (CBP-5), in conjunction with ISCA-43, Seoul, South Korea, June 2016. URL: https://jilp.org/cbp2016/ , accessed 2026.05.01

[7] A. Seznec and P. Michaud, "A Case for (Partially) TAgged GEometric History Length Branch Prediction," Journal of Instruction Level Parallelism, vol. 8, Feb. 2006.

[8] A. Seznec, "TAGE-SC-L Branch Predictors Again," in JWAC-5: Championship Branch Prediction (CBP-5), June 2016, Seoul.

[9] A. Seznec, "A 64-Kbytes ITTAGE Indirect Branch Predictor," in JWAC-2: Championship Branch Prediction, June 2011.

[10] Tan Hongze and Wang Jian, "A Return Address Predictor Based on Persistent Stack," Journal of Computer Research and Development, vol. 60, no. 6, pp. 1337–1345, 2023. DOI: 10.7544/issn1000-1239.202111274

[11] A. Seznec, "TAGE: an Engineering Cookbook," Inria Technical Report RR-9561, November 2024. Available: https://hal.science/hal-04804900

[12] André Seznec. 2025. TAGE-SC for CBP2025. In CBP 2025 (6th Championship Branch Prediction), June 21, 2025, Tokyo, Japan.

---
---
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*

