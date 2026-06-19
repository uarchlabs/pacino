<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
---
title: "Iteration Counting at s1: The Loop Predictor"
author: Jeff Nye
date: 2026-03-31
copyright: "Copyright 2026 Jeff Nye"
---

*This is part 3 of a series on branch predictor co-design.
[Part 1: Cluster Architecture](BLOG_bpu_1_cluster_arch.md) |
[Part 2: History and uBTB](BLOG_bpu_2_history_ubtb.md) |
[Part 3: Loop Predictor](BLOG_bpu_3_loop_pred.md) |
[Part 4: When the Tools Fail](BLOG_bpu_4_limits.md)*

---

## The Loop Predictor at s1

The loop predictor is the second s1-stage predictor in the branch predictor
(BP) cluster, firing alongside the micro Branch Target Buffer (uBTB) with the
same one-cycle latency from fetch block PC to prediction output. Where the
uBTB provides a next-PC prediction for any branch type it recognizes, the loop
predictor is specialized: it detects backward branches with constant iteration
counts and predicts loop exit.

A loop predictor in this configuration -- at s1, overriding the uBTB -- is not
typical in published high-performance decoupled front-end designs. Most designs
that include a loop predictor place it later in the pipeline where more context
is available. The choice here is deliberate. Constant-iteration loops are
common in numerical and media workloads, the iteration count is often stable
across runs, and a one-cycle loop prediction that fires before the Fetch Target
Buffer (FTB) or TAgged GEometric history length predictor (TAGE) has produced a
result avoids a redirect penalty that would otherwise occur on every loop
iteration. Whether the area and power cost justifies inclusion is a performance
analysis question deferred to when a provably functional front-end exists.

When the loop predictor asserts its override signal, the BP cluster selects its
prediction over the uBTB at s1. Override control is external to the loop
predictor module. The module exposes a confidence-gated output; the cluster
makes the mux decision. The loop predictor does not participate in the s2/s3
override chain.

This post covers the design, implementation, and verification of the loop
predictor: experiments BP-004 through BP-004f across five PA sessions,
spanning a single module that required six experiment files to deliver.

---

## Loop Predictor Design

The loop predictor module presents two interfaces to the BP cluster. The
prediction interface accepts a fetch block PC and a valid signal each cycle and
produces a registered prediction output one cycle later. The update interface
accepts a resolved update bundle post-execute, carrying all metadata that was
captured at predict time. The no-read-modify-write policy that applies to all
predictors in the cluster connects these two interfaces: nothing about the
update path requires re-reading the table, because the prediction path captures
and forwards everything the update path needs.

### Entry Format

The loop predictor table is a 256-entry 4-way set-associative structure with
64 sets (LP_TBL_ENTRIES = 256, LP_TBL_WAYS = 4, LP_N_SETS = 64). Each entry
is 68 bits wide, packed in this layout:

| Bits  | 67     | 66:53 | 52:39 | 38:25    | 24:11    | 10:3 | 2:1 | 0 |
|-------|--------|-------|-------|----------|----------|------|-----|---|
| Field | curs_v | curs  | tag   | past_itr | curr_itr | age  | cnf | v |
| Width | 1      | 14    | 14    | 14       | 14       | 8    | 2   | 1 |

The valid bit occupies bit 0. The 2-bit confidence counter (cnf) occupies
bits 2:1. The 8-bit age counter occupies bits 10:3. The current iteration
counter (curr_itr, 14 bits) occupies bits 24:11. The known loop iteration
count (past_itr, 14 bits) occupies bits 38:25. The 14-bit tag occupies bits
52:39. The speculative iteration cursor (curs, 14 bits) occupies bits 66:53.
The cursor valid bit (curs_v) occupies bit 67.

The iteration counter width of 14 bits (LP_ITR_BITS = 14) accommodates loops
of up to 16,383 iterations before saturation. The 2-bit confidence counter
(LP_CNF_BITS = 2) provides four states; maximum confidence (LP_CONF_LEVEL = 3)
requires three consecutive correct exit predictions from a newly allocated
entry before the predictor asserts its override output. The 8-bit age counter
(LP_AGE_BITS = 8) supports the victim selection policy described below.

All fields needed for the update path are computed at predict time and bundled
into lp_pred_t, a flat struct that travels forward through the Fetch Target
Queue (FTQ) to the post-execute resolution path. The update path consumes
lp_pred_t fields directly, without re-reading the table.

### Index and Tag Derivation

Index and tag values are derived from the fetch block PC by XOR hash functions:

```
idx_of(pc):  x = pc ^ (pc >> 1) ^ (pc >> 4);  return x[LP_IDX_BITS-1:0]
tag_of(pc):  x = pc ^ (pc >> 6) ^ (pc >> 12); return x[LP_TAG_BITS-1:0]
```

Mixing shifted copies of the PC is a standard technique for producing a compact
index or tag from a wider address, reducing aliasing relative to a direct bit
slice. The testbench mirrors these exact functions to compute expected indices
and tags independently of the RTL implementation.

### Prediction Pipeline

The prediction pipeline is combinational in s0 and registered at the end of
s0, producing a valid output at the start of s1. The pipeline proceeds as
follows: compute req_idx and req_tag from pred_pc_p0; read all four ways at
req_idx; find the matching valid way by tag match; if a hit is found and the
confidence counter equals LP_CONF_LEVEL, assert lp_pred_is_loop=1; predict
taken if curr_itr is less than past_itr; predict not-taken (loop exit) if
curr_itr equals past_itr; on miss or confidence below maximum, output
lp_pred_is_loop=0 and lp_pred_taken=0.

All lp_pred_t fields are output regardless of lp_pred_is_loop value. The
cluster must write all fields into the FTQ metadata path unconditionally
whenever pred_valid_p0=1; the update path requires them whether or not
lp_pred_is_loop was asserted. The consumer must not act on lp_pred_taken when
lp_pred_is_loop=0.

Victim selection for allocation is computed at predict time and included in
lp_pred_t, so the update path does not need to determine it independently.

FIG: Loop Predictor Structure - Claude
![Loop Predictor Structure](diagrams/loop_pred_structure.svg)

FIG: Loop Predictor Entry Fields - Claude
![Loop Predictor Entry Fields](diagrams/loop_pred_entry.svg)

### Confidence Gating and Override

The loop predictor asserts lp_pred_is_loop only when the confidence counter
reaches LP_CONF_LEVEL (value 3 for LP_CNF_BITS=2). Below maximum confidence,
the module outputs lp_pred_is_loop=0 and the cluster falls back to the uBTB
prediction. A newly allocated entry requires a learning period before it can
influence fetch.

The separation between the loop predictor's confidence output and the cluster's
override control is deliberate. The loop predictor is a provider; the cluster
is the authority. This allows the cluster's override policy to evolve without
modifying the predictor module.

### Victim Selection

Victim selection is a three-priority scan computed combinationally over all
four ways at the prediction set index.

Priority 1 selects the lowest-indexed invalid way. A newly reset table has all
ways invalid, so the first four allocations into any set proceed in way order
0, 1, 2, 3.

Priority 2, when all ways are valid, selects the lowest-indexed way with age
equal to zero. An age of zero indicates the entry has not been refreshed
recently. Age is reset to its maximum value on a correct exit prediction,
giving recently verified entries protection from eviction.

Priority 3, when all ways are valid and no way has age zero, selects the way
whose age is less than way 0's age, checking way 1 first, then way 2, then
way 3. If no qualifying way is found, way 0 is selected by default.

### The Update Path

The update path is synchronous, sampled on the rising clock edge when
upd_valid_p0 is asserted. It consumes upd_p0 fields directly without
re-reading the table. The update behavior is organized into five conditions:

| Condition | Gate | Action |
|-----------|------|--------|
| 1 -- taken branch hit | lp_pred_is_loop=1, actual_taken=1 | Increment curr_itr, saturating at LP_ITR_BITS max. If lp_curs_v: increment lp_curs. |
| 2 -- correct exit | lp_pred_is_loop=1, actual_taken=0, curr_itr==past_itr | Increment conf, saturating at LP_CONF_LEVEL. Copy curr_itr to past_itr. Reset curr_itr to 0. Reset age to maximum. |
| 3 -- wrong exit | lp_pred_is_loop=1, actual_taken=0, curr_itr!=past_itr | Reset conf to 0. Copy curr_itr to past_itr. Reset curr_itr to 0. |
| 4 -- mispredicted exit | lp_pred_is_loop=1, lp_pred_taken=0, actual_taken=1 | Reset conf to 0. Reset curr_itr to 0. |
| 5 -- learning (added BP-004d) | lp_hit=1, lp_pred_is_loop=0, actual_taken=1 | Increment curr_itr only. No confidence change, no allocation. |

On a miss with a backward branch (lp_pred_is_loop=0, actual_taken=1, target <
pc), a new entry is allocated at the victim way computed at predict time. The
new entry is initialized with past_itr=0, curr_itr=1, conf=0, age=max, v=1,
curs=0, curs_v=0. Forward branches do not trigger allocation.

Condition 5 was added by BP-004d to correct a structural gap in the initial
specification. Its origin is described in the next section.

### The lp_hit Fix

The original specification had a structural gap that the IA identified and
documented in the BP-004c results capture during implementation.

All four update conditions in the initial spec gated on lp_pred_is_loop=1.
Reaching lp_pred_is_loop=1 requires conf==LP_CONF_LEVEL. Confidence can only
be incremented by condition 2, which also requires lp_pred_is_loop=1. From a
cold start with conf=0, the predictor could never reach LP_CONF_LEVEL: every
update would fire condition 4 (mispredicted exit) or condition 3 (wrong exit),
both of which reset confidence. The learning path that was supposed to advance
curr_itr toward past_itr was unreachable.

The fix is drawn from the Seznec TAGE-SC-L loop predictor design [1]. The
distinction required is between a true miss -- no entry in the table -- and a
low-confidence hit -- an entry exists but conf is below threshold. The original
lp_pred_t had no field for this: the absence of lp_pred_is_loop=1 covered both
cases.

The resolution added lp_hit to both lp_pred_t and lp_upd_t. lp_hit=1 indicates
a tag match at any confidence level. lp_pred_is_loop=1 continues to indicate a
tag match at full confidence. With this distinction, condition 5 becomes
possible: an allocated entry can advance curr_itr on every taken traversal
regardless of confidence. When curr_itr reaches past_itr and a correct
not-taken exit fires condition 2, confidence advances. After LP_CONF_LEVEL
correct exits, the predictor asserts lp_pred_is_loop.

The fix also required a change to the always_ff write condition in loop_pred.sv.
The original condition gated the table write on pred_is_loop alone. With the
lp_hit learning path, the write condition was extended to pred_is_loop ||
lp_hit, enabling conditions 2 and 3 to commit their results for entries below
the confidence threshold and allowing confidence to advance on correct exits.

The gap was not identified during the PA's authoring of loop_pred_interfaces.md
or any of the experiment prompts. The IA flagged it as Deferred Work #2 in the
BP-004c results capture with a precise description of the failure mode and the
required fix. The PA authored BP-004d in response.

---

## Experiments BP-004 through BP-004f

The loop predictor development covered five PA sessions and six experiment
files. The fracture from a single experiment into six was driven by tooling
constraints rather than design complexity, and understanding the arc is part
of understanding the methodology.

The original BP-004 combined three concerns in a single prompt: struct additions
to bp_pkg.sv, a 250-line RTL module, and a 12-case self-checking testbench.
The context load included six files. The first run exceeded usage limits before
generating any output. After this failure, CLAUDE_CODE_MAX_OUTPUT_TOKENS was
set to 64000 as a follow-on action. A second run then exceeded the 32000 output
token limit during generation. At this point, BP-004 was marked abandoned and
the task was subdivided.

BP-004a (structs only) passed in 3 minutes and 26 seconds at 24% context.
Three structs were added to bp_pkg.sv: lp_entry_t, lp_pred_t, and lp_upd_t.
The LP parameter block already existed from a prior session; LP_CONF_LEVEL was
the only new parameter. The existing tb_bp_pkg testbench verified the package
with 16 checks.

BP-004b (module and testbench together) was written during session 6 and
attempted during session 7. It consumed all available tokens over 50 minutes
without generating any output. The increased CLAUDE_CODE_MAX_OUTPUT_TOKENS
setting did not help because the context load itself -- six files including
the full bp_cluster.md planning document and both the module and testbench as
deliverables -- exhausted the session budget before generation began. BP-004b
was abandoned.

The failure of BP-004b also prompted a structural change that had been
discussed but deferred: bp_pkg.sv was manually split into bp_defines_pkg.sv
(parameters) and bp_structs_pkg.sv (structs, enums, typedefs), with a mandatory
import order rule added to CLAUDE.md. This was a structural improvement
independent of the BP-004 fracture, but the fracture provided the occasion.

BP-004b was then split into three: BP-004c (loop_pred.sv RTL only), BP-004d
(lp_hit structural fix), and BP-004e (testbench TC1-TC7 plus Makefile). A
fourth, BP-004f, covered TC8-TC13.

BP-004c ran in 17 minutes and 35 seconds at 61% context and delivered 250
lines of loop_pred.sv, compiling cleanly under Verilator 5.020. The VARHIDDEN
suppression for the ten module parameters that shadow package-level names was
deferred to the Makefile update in BP-004d. The results capture flagged the
lp_hit structural gap as Deferred Work #2, a required fix before the predictor
could learn from a cold start.

BP-004d fixed the structural gap. 17 minutes and 50 seconds, 48% context.
lp_hit was added to lp_pred_t and lp_upd_t in bp_structs_pkg.sv. Condition 5
was added to the update path in loop_pred.sv. The always_ff write condition was
extended to pred_is_loop || lp_hit to enable confidence advancement for entries
below threshold.

BP-004e delivered TC1-TC7 and the Makefile sim and lint targets. 13 minutes
and 7 seconds, 50% context. TC1 through TC7 cover cold miss, backward branch
allocation, forward branch non-allocation (the backward branch filter), low-
confidence hit behavior, confidence build to LP_CONF_LEVEL, prediction with
curr_itr below past_itr, and prediction with curr_itr equal to past_itr. All
seven passed.

The TC5 confidence-build sequence required a design choice not specified in the
prompt. The IA identified that a wrong-exit update step was needed before the
confidence sequence to establish a non-zero past_itr in the table; without it,
the correct-exit condition (curr_itr == past_itr) would fire on the first
update after allocation, advancing confidence without the predictor having
learned a loop count. The IA also independently chose past_itr=1 as the
minimum value that satisfies the requirement, keeping the setup compact. Both
the need for the wrong-exit step and the choice of past_itr=1 are documented
in the BP-004e results capture assumptions and decisions sections.

Session 9, which produced BP-004e, also attempted to automate experiment
execution via a Claude Code slash command. The command registered incorrectly
due to missing YAML frontmatter in the command definition file and was
eventually abandoned. In its place, validate_and_extract.py was written. The
script validates the eight structural markers in an experiment file, then
extracts only the prompt section to a fixed output path for Claude Code to
read. This directly addresses the context pressure that killed BP-004b: Claude
Code reads a focused prompt rather than the full experiment file including
scaffolding, results templates, and discussion sections.

BP-004f appended TC8-TC13. The first attempt ran for 1 hour and 6 minutes.
Claude Code read all four context files successfully, then timed out during
generation before producing any output. TC8-TC13 appended to a 357-line
existing file would have produced approximately 380 lines of new code, enough
to exceed the generation timeout. The second attempt, using validate_and_extract
to reduce the context presented, ran in 33 minutes and 4 seconds and completed
successfully. All 13 test cases passed.

TC8 through TC13 cover correct exit (confidence increment, counter copy, age
reset), wrong exit (confidence reset, counter copy and reset), mispredicted
exit (confidence and counter reset), victim selection under a full set, way
conflict with two PCs mapping to the same index, and curr_itr saturation at
LP_ITR_BITS maximum.

TC11 (victim selection) required the testbench to fill all four ways of a
target set by injecting entries with direct upd_p0.tag assignments, rather
than through real PCs. Finding four real PCs that hash to the same index via
idx_of() would require a search; direct injection avoids this. Way 1's age
was then lowered to 0x01 via a condition 5 learning update passing
upd_p0.age=0x01. The IA confirmed by reading the RTL that condition 5 passes
the age field through from upd_p0 to the table write, making this approach
valid. The expected victim -- way 1, because its age (0x01) is less than way
0's age (maximum) -- was confirmed analytically before writing the assertion.

TC13 (saturation) drives curr_itr to LP_ITR_BITS maximum via two explicit
upd_p0 bundles with curr_itr set to itr_max-1 and itr_max respectively, rather
than 16,383 individual update cycles. The saturating behavior was confirmed by
reading loop_pred.sv before asserting.

The BP-004f generation timeout is a data point for a broader tooling problem
that is examined in Part 4 of this series.

Three CLAUDE.md updates followed the BP-004f session: a rule requiring Claude
Code to write Results Capture content only within the designated marker region
and nowhere else in the experiment file; a rule requiring ASCII-only content
in Results Capture; and removal of a redundant instruction that had told Claude
Code to narrate the context load manifest.

---

## Prompt Discipline

The BP-004 series illustrates what prompt scope limits look like in practice
and how the project adapted to them.

The original BP-004 combined three concerns in a single prompt: package struct
additions, a 250-line RTL module, and a 13-case testbench. Two attempts failed
before any output was produced -- the first at context load, the second at
generation even after CLAUDE_CODE_MAX_OUTPUT_TOKENS was increased to 64000.
The subsequent split into six experiments shows the practical scope limit for
this class of hardware design prompt at 2026 tooling levels: package additions
(BP-004a, 24% context, 3m), RTL module alone (BP-004c, 61% context, 17m),
testbench in two halves (BP-004e at 50%, BP-004f at 68%).

The BP-004c prompt specified the five update conditions as explicit boolean
guards on upd_valid_p0 and upd_p0 fields, the victim priority policy as prose
from which clean RTL was to be derived (explicitly instructing the IA not to
use a casez structure), and the exact XOR hash functions for index and tag
derivation. It did not specify always block structure, reset strategy for the
table array, how hit_entry should default on a true miss, or how curs and
curs_v should behave on update paths where the spec is silent. The IA
documented those choices as assumptions.

The lp_hit gap illustrates the asymmetry in specification review. The PA
authored loop_pred_interfaces.md and all experiment prompts. Neither document
identified the cold-start failure mode before the IA implemented the spec and
flagged it. The gap was not subtle: tracing the confidence advancement path
from conf=0 through the initial four conditions finds the failure immediately.
Pre-run review by the user caught five specification errors before BP-002 ran;
the lp_hit gap survived the same process. Detection came from implementation.

For BP-004d, the prompt stated the expected outcome but did not trace the
always_ff implication. The IA inferred the write condition change from the
stated outcome and documented it as a decision. This is the kind of design
reasoning the IA can supply when the expected outcome is clearly stated.

---

## Experiment Summary

| Experiment | Description                       | Status    | Checks | RTL Lines | Runtime        | Context |
|------------|-----------------------------------|-----------|--------|-----------|----------------|---------|
| BP-004     | Structs + module + testbench      | Abandoned | --     | 0         | 2 attempts     | >80%    |
| BP-004a    | lp_entry_t, lp_pred_t, lp_upd_t  | PASS      | 16/16  | ~30       | 3m 26s         | 24%     |
| BP-004b    | loop_pred.sv + testbench          | Abandoned | --     | 0         | 50m            | 100%    |
| BP-004c    | loop_pred.sv RTL                  | PASS      | lint   | 250       | 17m 35s        | 61%     |
| BP-004d    | lp_hit structural fix             | PASS      | lint   | ~20       | 17m 50s        | 48%     |
| BP-004e    | tb_loop_pred TC1-TC7, Makefile    | PASS      | 7/7    | ~200      | 13m 7s         | 50%     |
| BP-004f    | tb_loop_pred TC8-TC13             | PASS      | 13/13  | ~380      | 1h 6m + 33m 4s | 68%     |

---

## What Comes Next

With the loop predictor implemented and verified, the s1 prediction
infrastructure is complete. The uBTB and loop predictor together provide the
first predictions that speculative fetch acts on, before any slower predictor
has fired.

The original plan placed the FTB next. After the BP-004f session, the decision
was made to advance TAGE ahead of FTB. The generation timeout on BP-004f's
first attempt raised the question of whether the Claude Code generation flow
is feasible for substantially more complex modules before further tooling
investment. TAGE -- five tables, multiple index and tag hash inputs, a three-
stage prediction pipeline, and a complex update path -- provides an early
stress test on that question. FTB is deferred. The TAGE implementation and
the tooling failures that accompanied it are covered in subsequent posts.

---

## Design Process Notes

### Domain knowledge supplied by the user

The Seznec TAGE-SC-L loop predictor mechanism was the user-selected design
basis. The entry format -- all 68 bits with exact field widths and positions --
was user-specified as an explicit bit layout comment. The no-read-modify-write
policy was user-directed: all metadata for the update path is captured at
predict time. The backward branch filter -- allocating only when actual_taken=1
and target < pc -- was a user decision that required adding a target field to
lp_upd_t, expanding it from 15 to 16 fields.

The override control architecture -- the loop predictor exposes its confidence-
gated output, the cluster makes the mux decision -- was user-specified. The
iteration counter width (LP_ITR_BITS = 14), confidence counter width
(LP_CNF_BITS = 2), age counter width (LP_AGE_BITS = 8), and table sizing
parameters were all user-supplied. The curs and curs_v fields were specified
by the user as a speculative iteration cursor with rollback behavior deferred
as a known open item (LI4 in loop_pred_interfaces.md).

### What the PA contributed

The PA authored loop_pred_interfaces.md during session 6, formalizing port
semantics, timing contracts, consumer and producer obligations, the
read-during-write contract, and a deferred items table covering five open
items. The interface specification was written before any RTL existed and
served as the authoritative reference for BP-004c and subsequent experiments.

The PA authored BP-004 and its successor experiment files through BP-004f. The
initial BP-004 prompt combined too much scope and failed twice. The fracture
into six experiments was a consequence of those failures. The PA authored the
backward branch filter decision and the lp_upd_t target field addition during
the BP-004 design session.

The lp_hit structural gap was not identified during the PA's design of the
loop predictor, authoring of loop_pred_interfaces.md, or authoring of any
experiment prompt. It was identified by the IA during implementation of
BP-004c, flagged as Deferred Work #2 in the results capture, and fixed by
the PA in BP-004d.

The validate_and_extract.py script was designed and written during session 9
in response to the BP-004b context failure. Its adoption as standard workflow
is the most durable process change from this session series.

### What the prompt constrained versus what the IA filled in

The BP-004c prompt specified the exact port list, the exact XOR hash functions
for index and tag derivation, the prediction pipeline semantics (combinational
in s0, registered at end of s0), the victim selection priority policy as prose
description with explicit instruction to derive clean RTL rather than use a
casez structure, the five update conditions as explicit boolean guards, the
backward branch filter condition, and the Verilator suppression scope.

It did not specify always block count or structure, reset strategy for the
table array, the default behavior of hit_entry on a true miss, or how curs and
curs_v should be handled on update paths where the spec is silent. The IA's
documented assumptions: hit_entry defaults to mem[req_idx][0] on a true miss,
with fields propagating to pred_comb but ignored when lp_pred_is_loop=0; curs
and curs_v are not modified by mispredicted exit or wrong exit paths; condition
4 is evaluated before condition 1 because condition 4 is a subset of condition
1 and must take priority; the confidence comparison uses {LP_CNF_BITS{1'b1}}
rather than == LP_CONF_LEVEL to avoid comparing a packed field against an int
parameter where width mismatch is a risk.

For BP-004d, the prompt stated the expected outcome but did not trace the
always_ff implication. The IA inferred the write condition change from the
stated outcome. For the testbench sessions, the prompt specified TC names and
behavioral descriptions. The IA's notable decisions: the wrong-exit step to
establish past_itr before the confidence sequence in TC5; past_itr=1 to
minimize setup cycles; direct tag injection in TC11 rather than searching for
four aliasing PCs; the two-bundle saturation approach in TC13.

### The generalization

The loop predictor development adds a data point the earlier modules did not:
what happens when prompt scope hits the tooling ceiling before delivery. The
original BP-004 was not over-ambitious by the standards of the task -- a
package addition, a 250-line module, and a 13-case testbench is a coherent,
bounded unit of work. The tooling could not execute it as a unit. The
adaptation was correct: scope down until each prompt completes. The cost was
five additional experiment files, four additional Claude Code sessions, and one
session developing the validate_and_extract.py tooling. The output was the
same verified module.

The lp_hit gap illustrates a different property. Specification review -- by
the PA and by the user in the pre-run review step -- did not catch a
fundamental correctness property of the design. The IA implementation did.
This is not a reliable property of the methodology: whether the IA catches a
gap depends on what it encounters during implementation. In this case it caught
one; in the BP-002 session, the user caught five before the IA ran.
Specification errors can survive pre-run review, may be caught at
implementation, and some survive into testing.

The BP-004f generation timeout confirmed that the tooling ceiling applies to
generation as well as context. A focused context via validate_and_extract.py
solved the context side. The generation side required splitting the testbench
across two prompts. Both limits are real, both are managed by scoping, and
neither has a configuration lever. Part 4 examines these limits in more detail.

---

## References

[1] A. Seznec, "A new case for the TAGE branch predictor," Proceedings of the
44th Annual IEEE/ACM International Symposium on Microarchitecture, 2011.

