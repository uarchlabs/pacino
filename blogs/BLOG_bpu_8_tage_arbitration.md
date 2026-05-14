---
title: "TAGE -- Arbitration and Integration"
author: Jeff Nye
date: 2026-04-22
copyright: "Copyright 2026 Jeff Nye"
---

*This is part 8 of a series on branch predictor co-design.
[Part 1: Cluster Architecture](BLOG_bpu_1_cluster_arch.md) |
[Part 2: History and uBTB](BLOG_bpu_2_history_ubtb.md) |
[Part 3: Loop Predictor](BLOG_bpu_3_loop_pred.md) |
[Part 4: When the Tools Fail](BLOG_bpu_4_limits.md) |
[Part 5: TAGE -- Architecture and the Decomposition Problem](BLOG_bpu_5_tage_arch.md) |
[Part 6: TAGE -- Implementation](BLOG_bpu_6_tage_impl.md) |
[Part 7: TAGE -- Validation](BLOG_bpu_7_tage_validation.md) |
[Part 8: TAGE -- Arbitration and Integration](BLOG_bpu_8_tage_arbitration.md)*

---

## Closing Out the TAGE Sessions

The previous post ended with 46 passing tests and a clean
codebase. Before TAGE could be handed off to the bp_cluster
integration work, two remaining tasks needed resolution: a
final cleanup of the parameter namespace, and the arbitration
infrastructure that will govern how TAGE accepts prediction
requests and update operations from the cluster.

This post covers the three sessions that completed that work:
the parameter normalization pass, the final struct migrations,
and the start of the arbitration implementation. It is a
shorter post than the implementation and validation posts --
the work here is largely structural preparation rather than
new functional design.

---

## Parameter Namespace Cleanup

Over the course of 28 design sessions, bp_defines_pkg.sv had
accumulated several categories of naming inconsistency. The
TAGE per-table parameters had been converted to TAGE_TBL_*
vectors earlier in the project, but the Statistical Corrector
(SC) and Indirect Target TAGE (ITTAGE) parameters remained as
individual scalar declarations. Six MAX_* localparams that
governed field widths had no predictor prefix, making their
origin ambiguous. And three TAGE scalar parameters flagged FIXME
in earlier cleanup passes had deferred consumers that blocked
their removal.

Three experiments resolved these items in sequence.

BP-022 renamed the six unprefixed MAX_* localparams to
TAGE_MAX_* and updated all consumer sites. It also added
SC_TBL_* and IT_TBL_* vector parameters, following the same
pattern as the TAGE_TBL_* vectors established earlier. A
stop-and-report event fired during the scalar removal step
when bp_history.sv was found to be a consumer outside the
loaded context. The session completed with all 12 build
targets green and the removal deferred.

BP-022a completed the deferred removals. The 16 remaining TAGE
per-table scalar parameters (T1-T4 folded history widths and
history lengths), all SC per-table scalars, and all ITTAGE
per-table scalars were removed. bp_folded_hist_t in
bp_structs_pkg.sv had all 27 field widths updated to use
the new MAX_* parameter names. bp_history.sv was updated to
use TBL vector indexing. Eight backward-compatibility aliases
were added temporarily to allow tb_tage_table.sv -- which was
out of context for that session -- to compile without changes.

BP-022b removed the temporary aliases and the SC_NUM_MAIN_TBLS
scalar that had been retained as a dependency. A follow-on
housekeeping pass (BP-022c) removed two remaining items:
SC_TBL_INDEX_BITS, which had no active consumers, and a
commented-out alias block that had been left as dead code.

The TAGE_TAG_BITS parameter, which had been retained through
multiple earlier passes because tage_hash.sv was an unexpected
consumer, was finally removed after the Makefile targets for
that abandoned module were cleaned up. That completed debt #24,
which had been open since the hash architecture change in
Part 19.

---

## Struct Migration: Closing TI7

Debt #14, tracked as TI7, had been open since session 11. It
recorded that bp_tage_meta_t -- the original TAGE metadata
struct -- had been superseded by tage_pred_meta_t but both
were retained in bp_structs_pkg.sv during the transition. The
two structs were not binary-compatible: tage_pred_meta_t had
renamed fields, added fields for primary and alternate
direction signals, and added branch_id.

The migration required two edits: retype bp_ftq_meta_t.tage
from bp_tage_meta_t to tage_pred_meta_t, then remove the
bp_tage_meta_t typedef. A consumer search confirmed no RTL
outside bp_structs_pkg.sv referenced bp_tage_meta_t -- the
field was present in bp_ftq_meta_t but bp_cluster, which
would consume it, had not yet been started. The migration
completed cleanly, lint green across all targets.

---

## The Arbitration Problem

TAGE is a three-stage pipeline. Prediction requests enter at
p0 and results emerge at p2. Update operations are
single-cycle. In bp_cluster, multiple predictors and two
prediction slots generate concurrent requests and updates.
The question of how a pipelined predictor manages this
concurrency without a dedicated arbitration layer is not
trivial: a naive implementation simply processes whatever
arrives, which works only when the cluster guarantees mutual
exclusion that TAGE has no way to enforce.

The arbitration design was documented first as a planning
artifact. bp_arb_spec.md defined a credit-based
Priority Queue and Update Queue (PQ/UQ) architecture. The
PQ accepts prediction requests up to a credit limit, issuing
them in order. The UQ accepts update operations, also credit-
limited. A competing-stage mux selects between PQ output and
UQ output each cycle, with a starvation threshold that
prevents either from being indefinitely blocked. A response
buffer holds prediction results until the consumer (SC in the
override chain) is ready to accept them.

The spec resolved debt #33 -- the simultaneous prediction and
update protocol -- as a design document rather than as a
testbench gap. The key decision: prediction goes first, reading
the pre-update state, with no address comparison at the
arbiter. Same-address conflicts are handled by the predictor's
existing read-during-write contract.

---

## Arbitration Implementation

NUM_PRED_SLOTS was set to 2 in bp_defines_pkg.sv before the
arbitration work began. This is the architectural default for
all TAGE design work. The reduction to 1 remains a deferred
cleanup task.

BP-023a added the arbitration parameters to bp_defines_pkg.sv
and the arbitration struct definitions to bp_structs_pkg.sv.
Seven TAGE arbitration parameters were added from the spec:
queue depths, credit limits, write port count, response buffer
depth, and starvation threshold. Stub parameter sections for
the remaining predictors (Loop, FTB, SC, ITTAGE) were added
with zero values and TBD comments. The bp_arb_trx_t struct,
which carries transaction type and slot index through the
pipeline, was added. Placeholder structs for SC prediction
metadata and SC update input were added to allow the
conditional prediction metadata union type to compile without
blocking SC implementation.

BP-023b added the arbitration logic to tage.sv and a
transaction type gate to tage_cntrl.sv. The PQ, UQ, credit
registers, competing-stage mux, transaction register, and
response buffer were implemented as structural logic in
tage.sv. tage_cntrl.sv received a trx_type input that gates
update write enables, ensuring the update path only fires when
the arbiter has granted an update operation.

Two decisions made during implementation are worth recording.

The first concerns consumer_ready. The response buffer design
requires a consumer_ready signal from SC to gate when
prediction results are released from the buffer. Adding this
as a port to tage.sv would have broken all 46 existing tests:
Verilator drives unconnected inputs to zero, which would stall
the response buffer on every prediction. The decision was to
tie consumer_ready internally to 1'b1, deferring backpressure
handling to the SC integration task. This blocks one of the
planned arbitration test cases (response buffer full behavior)
until consumer_ready becomes a real port.

The second concerns how the granted transaction type reaches
tage_cntrl. The arbitration logic produces arb_grant_upd as a
combinational output that is also registered into arb_trx_r
for pipeline tracking. Using the registered value to gate
write enables in tage_cntrl would cause writes to fire one
cycle late. The decision was to use the combinational
arb_grant_upd signal directly. This is correct for the current
test patterns, which never have concurrent prediction and
update activity, but carries a risk that a concurrent scenario
could see the grant signal change while tage_cntrl is mid-
pipeline. This was recorded as a new technical debt item.

All 46 existing tests passed after BP-023b. The arbitration
bypass path -- where only one queue is active at a time -- is
what all existing tests exercise. The FIFO storage arrays,
head and tail pointer logic, and credit register decrement
paths are structurally present but untested at the close of
this session.

---

## Experiment Summary

| Experiment | Description                               | Status | Checks | RTL Lines | Runtime | Context |
|------------|-------------------------------------------|--------|--------|-----------|---------|---------|
| BP-022     | MAX_* rename, SC/IT vectorization         | PASS   | 46/46  | --        | --      | --      |
| BP-022a    | Scalar removal, bp_history update         | PASS   | 46/46  | --        | --      | --      |
| BP-022b    | Alias removal, SC_NUM_MAIN_TBLS removed   | PASS   | 46/46  | --        | --      | --      |
| BP-022c    | SC_TBL_INDEX_BITS, dead code removed      | PASS   | 46/46  | --        | --      | --      |
| BP-020     | sim_tage_table TC6 USE defect fixed       | PASS   | 12/12  | --        | --      | --      |
| BP-021     | TI7: bp_tage_meta_t removed               | PASS   | --     | --        | --      | --      |
| BP-023a    | Arbitration parameters and structs        | PASS   | 46/46  | --        | --      | --      |
| BP-023b    | PQ/UQ/credit arbiter, response buffer     | PASS   | 46/46  | --        | --      | --      |

---

## What Comes Next

BP-023c, which was open at the close of these sessions,
adds the arbitration testbench -- the test cases that exercise
queue depth, credit exhaustion, starvation threshold, and
the competing-stage mux. Once that completes, TAGE is
ready for bp_cluster integration.

The FTB predictor follows TAGE in the implementation sequence.

---

## Design Process Notes

### What the sessions exposed about the methodology

The parameter normalization work across BP-022 through BP-022c
took four experiments to complete what was originally scoped as
one. The stop-and-report pattern -- where Claude Code halts on
finding an unexpected consumer rather than proceeding with a
partial removal -- fired twice and was correct both times. The
cost was additional sessions; the benefit was that no consumer
was silently broken.

The bp_arb_spec.md approach to debt #33 is the most
methodologically interesting decision in this post. The
simultaneous prediction and update protocol had been an open
debt item for several sessions. Rather than writing a testbench
to characterize the undefined behavior, the decision was to
write a design document that defined the behavior, then
implement against the document. This is the same pattern used
for the tage_cntrl planning documents in Part 6 -- define
first, implement second. The arbitration complexity warranted
the same treatment.

### What the PA contributed

The PA produced bp_arb_spec.md, scoped and sequenced the
cleanup pass across BP-022 through BP-022c, wrote all prompts
for the struct migration and arbitration work, and identified
the consumer_ready and trx_type decisions as requiring
explicit resolution before BP-023b was authored.

### What the IA contributed

The IA executed all experiments cleanly, including the
consumer searches that triggered stop-and-report events. The
always_comb consolidation in BP-020 -- replacing cascaded
assign statements with always_comb blocks to resolve a
Verilator evaluation-order ambiguity -- was implemented
correctly on the first attempt. The BP-023b arbitration
implementation in tage.sv, which required adding a
structurally non-trivial queue-based arbiter to a module
that had previously been purely structural, was lint-clean
and all-passing on the first run.

### The generalization

The pattern across the TAGE sessions as a whole is that
the most expensive problems were the ones deferred past
their natural resolution point. The T0 geometry deferral
cost a module split in Part 6. The hash logic placement
cost a three-experiment migration in Part 6. The
simultaneous pred+update protocol deferral cost a design
document session before implementation could proceed. The
consumer_ready deferral left one test case blocked. None
of these were avoidable in the sense that the right answer
was not knowable earlier -- but the cost of deferral was
consistently higher than it appeared at the time of
deferral.

---

*No references required for this post.*

