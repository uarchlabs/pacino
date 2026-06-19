<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
---
title: "Branch History and the First Prediction: bp_history and uBTB"
author: Jeff Nye
date: 2026-03-28
copyright: "Copyright 2026 Jeff Nye"
---

*This is part 2 of a series on branch predictor co-design.
[Part 1: Cluster Architecture](BLOG_bpu_1_cluster_arch.md) |
[Part 2: History and uBTB](BLOG_bpu_2_history_ubtb.md) |
[Part 3: Loop Predictor](BLOG_bpu_3_loop_pred.md) |
[Part 4: When the Tools Fail](BLOG_bpu_4_limits.md)*

---

## The s1 Prediction Infrastructure

Part 1 of this series described the seven-predictor BP cluster architecture
and the BP-001 type package that defines all shared parameters, enumerations,
and structs. With that foundation in place, the next step was the first two
modules of the s1 prediction infrastructure: the history module and the micro
Branch Target Buffer (uBTB).

These two modules are logically independent but operationally coupled. The
uBTB fires at s1 and produces the first next-PC prediction seen by speculative
fetch. The history module maintains the Global History Register (GHR) and
Path History Register (PHR) that every table-based predictor in the cluster
consumes. Neither module depends on the other directly, but both must be
correct and well-specified before tagged geometric history length predictor
(TAGE), Statistical Corrector (SC), or indirect target TAGE predictor (ITTAGE)
can be implemented. They were the natural second target after BP-001.

This post covers the design, implementation, and verification of both modules:
BP-002 (bp_history.sv) and BP-003 (ubtb.sv), together with BP-003-FIX, a
follow-on cleanup that resolved a branch type encoding conflict introduced
during BP-003.

---

## History Module Design

The history module is the centralized owner of all branch history state in the
BP cluster. It contains no SRAM, only registered state: two circular buffers
for the GHR and PHR, a bank of 27 folded histories consumed by TAGE, SC, and
ITTAGE, and a checkpoint array of 64 pointer snapshots keyed by Fetch Target
Queue (FTQ) slot index.

### The Circular Buffer Model

The GHR is a 256-bit circular buffer (GHR_WIDTH = 256) with an 8-bit pointer
(GHIST_PTR_BITS = $clog2(256)). The PHR is a 32-bit circular buffer
(PHR_WIDTH = 32) with a 5-bit pointer (PHIST_PTR_BITS = $clog2(32)). Both
buffers are written speculatively: each accepted prediction advances the
pointer and writes the outcome bit into the buffer at the current position.

The key structural decision is that the pointers are external inputs. Buffer
storage lives inside bp_history, but pointer arithmetic lives outside it.
The module receives pred_pc -- the fetch block PC the cluster presents to the
history module each prediction cycle -- along with the predicted direction bits
and an active-branch count. It writes the bits into the buffers, updates the
folds, and on rollback recomputes the folds from the existing buffer contents
at the restored pointer. The module has no knowledge of pipeline staging,
fetch-block width, or redirect policy. Those concerns belong to the cluster
top, and this separation means bp_history does not change when prediction slot
count or pointer management policy changes.

The PHR update rule writes a path hash bit derived from the fetch PC:
PHR[phist_ptr] = pred_pc[2] ^ pred_pc[3]. The XOR of these two PC bits
provides a simple path distinguisher. The bit selection is subject to tuning;
the current choice is a working starting point.

### Dual Prediction and the GHR

When NUM_PRED_SLOTS = 2, up to two prediction outcomes may arrive in the same
cycle. The module accepts two update bits via pred_taken[1:0] and a
num_branches[1:0] input that specifies how many are valid. Valid values for
num_branches are 0, 1, and 2; value 3 (2'b11) is undefined behavior and the
module makes no provision for it.

When num_branches = 2, both bits are written to the GHR in slot order:
ghr_mem[ghist_ptr] receives pred_taken[0] and ghr_mem[(ghist_ptr + 1) mod
GHR_WIDTH] receives pred_taken[1]. The fold update applies twice in sequence,
once for each slot. The first application uses pred_taken[0] and the current
pointer position; the second uses pred_taken[1] and the incremented pointer.
The same two-step structure applies to the PHR for path history.

### Folded Histories

The folded history approach is standard in TAGE-family predictor designs [1].
Rather than presenting the full 256-bit GHR to each predictor table for its
index and tag computation, the history module maintains a reduced-width folded
representation for each table and updates it incrementally on every prediction.

T0, the TAGE base table -- also called the bimodal or BIM table -- has no
history and no folds. It uses a 2-bit saturating counter per entry with no
tag, valid, or useful fields, and is not a consumer of bp_history folded
outputs. TAGE tables T1 through T4 each require three folds: an index fold and
two tag folds. ITTAGE tables IT1 through IT4 require the same. SC tables ST1
through ST3 require one index fold each. IT5 (the BrIMLI table) and SC tables
ST0 and ST4 have no history-derived folds. The total is 27 folds, exposed as
a single bp_folded_hist_t packed struct output port consumed directly by TAGE,
ITTAGE, and SC.

The incremental fold update rule for a fold of width W covering history
depth H is:

  bit_out  = ghr_mem[(ghist_ptr + H) % GHR_WIDTH]
  new_fold = (fold << 1) | new_bit ^ fold[W-1] ^ bit_out

where new_bit is the incoming prediction outcome. This advances the fold by
one bit per accepted prediction, shifting out the oldest contribution and
shifting in the newest, in a single registered operation per cycle. When
num_branches = 2, the rule applies twice in slot order as described in the
previous section.

PHR contribution to fold index and tag hashing is deferred. The implementation
maintains phr_mem and exposes phr_buf, but no fold uses PHR bits. That
decision is deferred to the TAGE and ITTAGE implementation sessions where the
mixing strategy can be resolved with the relevant predictor tables in context.

### Checkpoint and Rollback

The checkpoint design is the most consequential structural decision in this
module. The naive approach stores the full GHR content per FTQ slot: 256 bits
per checkpoint at 64 slots is 16,384 bits of storage, before folds. The chosen
approach stores only the two pointer values: ghist_ptr (8 bits) and phist_ptr
(5 bits), for 13 bits per slot and 832 bits total. Folds are not checkpointed.
On rollback, folds are recomputed from the circular buffer contents at the
restored pointer.

The reasoning is that the circular buffer itself is the history. Entries
written after a checkpoint remain in the buffer on rollback -- they are not
cleared -- but they become unreachable via the restored pointer. The fold
recompute traverses the buffer from the restored pointer position, reading H
consecutive bits per fold and XOR-folding to width W. This recomputation is
available one cycle after rollback_en asserts.

The timing concern is real: 27 folds recomputed in one cycle from a 256-bit
circular buffer is a non-trivial combinatorial path. This is logged as G15 in
the planning document and deferred until the critical path is characterized.
The architecture is correct and passes all directed tests; the timing risk is
accepted with open eyes.

TC8 in the BP-002 testbench confirmed a non-obvious semantic: because the
buffer is not cleared on rollback, GHR entries written after the checkpoint
remain in the buffer and can fall within the fold computation window when H
is large enough to reach them. The fold recomputed after rollback is computed
from the post-advance buffer state, not a frozen pre-checkpoint snapshot.
The TC8 reference model was corrected to reflect this, and the behavior is
architecturally correct for a pointer-based circular buffer design. This is
the accepted contamination model: the contaminating entries are unreachable
for future predictions but their bits remain in the buffer and contribute to
fold recomputation.

FIG: History Module - Claude
![History Module Structure](diagrams/history_module.svg)

FIG: GHR Circular Buffer, Checkpoint and Rollback - User
![GHR Checkpoint and Rollback](diagrams/ghr_checkpoint.svg)

---

## uBTB Design

The uBTB is the first predictor in the prediction pipeline. It takes the
fetch PC at s0 and produces a prediction at s1, one cycle later. Its role
is narrow: supply a next-PC prediction early enough to start speculative
fetch before any slower predictor has fired. It does not generate a redirect
signal. It supplies a prediction or withholds one. On a miss, fetch proceeds
sequentially at PC + fetch_width. The first cycle at which any predictor can
redirect fetch is s2.

### Structure and Lookup

The uBTB is 256 entries organized as 64 sets of 4 ways (UBTB_ENTRIES = 256,
UBTB_WAYS = 4, UBTB_SETS = 64). The set index is derived from PC[7:2], six
bits that address the 64 sets while dropping the two least-significant bits
that are always zero for aligned instructions. The tag is PC[26:7], 20 bits.
Each entry stores: a valid bit, the tag, the branch type, the predicted target,
the predicted direction for conditional branches, and a carry bit.

FIG: uBTB Entry Fields - Claude
![uBTB Entry Fields](diagrams/ubtb_entry.svg)

The carry bit indicates whether the predicted target falls in a different
32-byte-aligned fetch block from the current fetch PC:

  carry = target[VA_WIDTH-1:5] != pc[VA_WIDTH-1:5]

The cluster uses this to determine whether the s1 prediction requires
switching to a new fetch block or continuing within the current one.

The prediction path is combinational from registered memory. The set index
and tag are derived from pred_pc in s0. The registered array produces a hit
or miss output at the start of s1, one cycle later. The 20-bit tag is relied
upon to make aliasing acceptably rare for a 64-set table. No disambiguation
beyond valid-and-tag-match is performed.

FIG: uBTB Structure - Claude
![uBTB Structure](diagrams/ubtb_structure.svg)

### Read-During-Write

The update path is synchronous. When upd[u].valid asserts -- where upd[u] is
the resolved update bundle driven by the post-execute resolution path for
prediction slot u -- the target set is searched for an existing entry with
matching tag. A hit updates the entry in place. A miss writes to the way
pointed to by the per-set write pointer, which then advances. The replacement
policy is per-set write pointer only: no hit promotion, no LRU.

The read-during-write contract is that if an update and a lookup address the
same set in the same cycle, the prediction reflects pre-update (registered)
state. The new entry becomes visible on the following cycle. No bypass path
is implemented. TC10 in the BP-003 testbench confirmed this behavior by
checking the prediction between clock edges on the same cycle as the update,
then confirming visibility one cycle later.

### Dual Prediction

The uBTB is parameterized on NUM_PRED_SLOTS at elaboration time. When
NUM_PRED_SLOTS = 2, there are two independent prediction outputs and two
independent update channels. Slot 0 uses pred_pc directly. Slot 1 uses
pred_pc + 32, the next 32-byte fetch block. The reason for pred_pc + 32 is
that slot 1 must form its s0 address request before the slot 0 result is
available: the direction and target of any taken branch in slot 0 are not
resolved until s1 at the earliest. Using pred_pc + 32 as the slot 1 input is
a speculative stand-in for the sequential next block. If slot 0 produces a
taken branch, s2 will redirect to the actual target; if slot 0 is not taken
or has no branch, the prediction at pred_pc + 32 is already correct. The two
update channels are processed independently with no ordering constraint between
them. TC9 verified that a simultaneous hit on both slots produces correct
independent predictions in a single cycle.

When NUM_PRED_SLOTS = 1, one prediction output and one update channel are
active. Single-slot mode is for silicon debug only and is not a production
configuration.

### Branch Type Encoding

The UBTB_BR_* localparams that appeared in the initial BP-003 implementation
were introduced by the PA-authored experiment prompt, which specified them as
the branch type encoding for the three uBTB structs (ubtb_entry_t, ubtb_pred_t,
ubtb_upd_t). A pre-existing enum, bp_br_type_e, already covered the same
semantic space with finer granularity: seven values (NO_BRANCH, COND,
DIRECT_UNC, DIRECT_CALL, INDIRECT_CALL, INDIRECT_NONRET, RETURN) compared to
the six UBTB_BR_* values, which collapsed DIRECT_CALL and INDIRECT_CALL into
a single entry. The IA implemented the structs as specified and flagged the
conflict with bp_br_type_e in the results capture as an RVA23 compliance gap
requiring a translation step at integration. The PA identified the fix from
that results capture and authored BP-003-FIX.

BP-003-FIX retired UBTB_BR_* entirely and updated all three uBTB structs to
use bp_br_type_e directly. TC6 was expanded from 6 to 7 entries to cover all
enum values. The resolution path now stores exactly the encoding the FTQ and
update channel expect with no translation. ubtb.sv itself required no changes
because the module stores and forwards br_type without interpreting encoding
values.

The pre-decoder that produces the post-execute update distinguishes
DIRECT_CALL from INDIRECT_CALL from instruction bits (opcode plus rd and rs1
fields) before anything is written to the uBTB. The encoding that arrives at
the update input is already correct by the time the update fires.

---

## Experiments BP-002, BP-003, and BP-003-FIX

The BP-002 experiment covered the full history module implementation: the
circular buffers, 27 incremental fold computations, the checkpoint storage
array, and the rollback recompute path. The resulting module was 537 lines
of verified SystemVerilog. The 12-case testbench (TC1 through TC12) covered
reset state, single and dual branch writes to the GHR, PHR path bit updates
for both XOR values, checkpoint and rollback for GHR and PHR separately,
fold non-zero verification after alternating updates, fold recompute after
rollback with contamination, zero-branch no-op behavior, dual-slot writes
to consecutive GHR positions, checkpoint preservation across an unrelated
rollback, and GHR pointer wraparound.

TC8 required a reference model correction after the initial testbench draft
was written, as described in the previous section. Correcting the reference
to match the actual rollback semantics made TC8 a meaningful test of a
non-obvious property rather than a tautology. The corrected semantics are
now specified in the bp_history interface specification.

BP-002 also surfaced a Verilator include-path issue: RTL files that use
\`include directives fail if no -I path is given on the Verilator command
line, even when the included file is in the same directory. The fix --
passing all files explicitly on the Verilator command line rather than using
\`include in RTL -- was logged as a standing project rule.

BP-003 covered the full uBTB module and testbench. All ten test cases passed
on the first full run after one package import style correction carried over
from BP-002. BP-003-FIX, which retired UBTB_BR_* and expanded TC6, passed
with no new test failures.

Two Verilator suppression rules were established during BP-003 and graduated
to the project CLAUDE.md. The first, -Wno-IMPORTSTAR, is required project-wide
because the mandated file-scope wildcard import style (import bp_pkg::*; before
the module declaration) triggers a Verilator 5.020 warning about $unit
namespace pollution. The warning is structural. The second, -Wno-VARHIDDEN,
is scoped to individual sim targets when a module parameter intentionally
shadows a bp_pkg parameter of the same name. The NUM_PRED_SLOTS parameter in
ubtb.sv is the override point for instantiation; the package parameter is the
default. Renaming the module parameter would violate the interface
specification, so the suppression is the correct resolution, applied locally
rather than globally.

---

## Prompt Discipline

The BP-002 and BP-003 prompts followed the constraint-first pattern established
in BP-001. The BP-002 Binding Previous Decisions section specified eight items
that had been settled in prior planning sessions but were not yet in
bp_cluster.md or were easy to get wrong without explicit direction: the
pointer-external model, the no-fold-checkpoint decision, the SC history depths
(4, 10, 16 bits for ST1 through ST3), the specific folds required by each
ITTAGE table, and the bp_ftq_entry_t field change from a 256-bit raw snapshot
to a pair of pointer fields.

A practical consequence of that specificity appeared immediately. A planning
review before BP-002 ran caught five errors in the draft prompt and planning
document. The errors involved incorrect labels, wrong history depth values,
incorrect fold assignments, and a false assumption about checkpoint content.
The user identified all five errors during the pre-run review of the
PA-authored draft. All were caught before any RTL was generated. The session
record does not further separate which errors originated in the user's initial
direction and which in the PA's drafting; that attribution gap is a
methodology note already documented in Part 1.

The ratio metric from Part 1 extends to BP-002: 537 lines of verified RTL and
450 lines of testbench from a two-page experiment prompt represents
approximately the same leverage. BP-003 at 7 minutes of runtime and 10 passing
test cases from a comparably sized prompt extended the pattern. Both prompts
are primarily architectural constraint, not implementation dictation.

---

## Experiment Summary

| Experiment  | Description                    | Status | Checks | RTL Lines | Runtime | Context |
|-------------|--------------------------------|--------|--------|-----------|---------|---------|
| BP-002      | bp_history.sv, GHR/PHR/folds   | PASS   | 12/12  | 537       | 18m.22s | 30%+    |
| BP-003      | ubtb.sv, 4-way associative     | PASS   | 10/10  | --        | 7m.21s  | 38%     |
| BP-003-FIX  | Encoding unification, cleanup  | PASS   | 10/10  | 0 new     | 4m.31s  | 34%     |

---

## What Comes Next

With the history module and uBTB implemented and verified, the first two
modules of the s1 prediction infrastructure are in place. The history module
produces the 27 folded histories that every TAGE-family predictor depends on.
The uBTB produces the first prediction that speculative fetch acts on.

The next module is the loop predictor: a 256-entry 4-way associative predictor
that fires at s1 alongside the uBTB and can override the uBTB prediction when
a loop branch is detected and its confidence counter is sufficient. The loop
predictor is the only predictor in this cluster not derived from the Xiangshan
Kunminghu architecture. Its design, implementation, and verification are
covered in [Part 3](BLOG_bpu_3_loop_pred.md).

---

## Design Process Notes

### Domain knowledge supplied by the user

The circular buffer model for the GHR and PHR was user-directed. The key
structural decision -- that pointers are external inputs while buffer storage
is internal -- came from the user as an explicit architectural constraint. The
PHR update rule and the specific fold assignments per predictor table were also
user-supplied, as were the SC history depth values (4, 10, 16 bits for ST1
through ST3).

Those history depth values were initially transcribed incorrectly in the
planning document before BP-002 ran, appearing as 16 and 64 bits rather than
4, 10, and 16. This was one of five errors caught during a pre-run planning
review. The others were: an incorrect label applied to SC table ST4 (the BrIMLI
label belongs to ITTAGE IT5, not ST4), ITTAGE IT5 fold entries incorrectly
included in the draft bp_folded_hist_t definition (IT5 has no history and
therefore no folds), the checkpoint design incorrectly stated to store folded
histories rather than pointer values only, and IT1-IT5 listed as fold providers
where IT1-IT4 was correct. The user identified all five errors during the
pre-run review of the PA-authored draft.

### What the PA contributed

The PA authored the BP-003 experiment prompt, which introduced the UBTB_BR_*
localparams as the branch type encoding for the uBTB structs. The IA
implemented them as specified, flagged the conflict with bp_br_type_e as an
RVA23 compliance gap in the results capture, and the PA identified and authored
the fix as BP-003-FIX. The PA also wrote the bp_history and uBTB interface
specification documents (bp_history_interfaces.md and ubtb_interfaces.md),
which formalize port semantics, timing contracts, and consumer and producer
obligations for each module. These were written after BP-003 passed and are
outputs of the session, not inputs to it.

The rollback semantic clarification -- that fold recompute operates on
post-advance buffer state -- was first documented by the IA in the BP-002
results capture, discussed in the session that followed, and incorporated
into the interface specification by the PA.

### What the prompt constrained versus what the IA filled in

The BP-002 prompt specified the full port list, the circular buffer write
rules for both active slots, the incremental fold update formula, the fold
recompute trigger condition, and the exact checkpoint field list. It did not
specify how fold_step() should be structured, how many always_ff blocks the
module should use, or what the reset strategy for the checkpoint array should
be. Those were IA decisions.

The IA's results capture documented two assumptions not in the prompt: that
num_branches value 2'b11 is undefined and will not be presented, and that
ckpt_ghist_ptr and ckpt_phist_ptr track the most recently written checkpoint
values as combinational outputs rather than following the rollback pointer.
Both were raised explicitly, both were accepted without change, and both are
now specified in the bp_history interface specification.

For BP-003, the prompt specified the index derivation (PC[7:2]), tag
derivation (PC[26:7]), carry bit definition, read-during-write contract, and
replacement policy. The IA wrote all SystemVerilog syntax, structured the way
loops for lookup and update, and handled the dual-DUT instantiation required
for TC9 within a single testbench module. The VA_WIDTH = 40 bit gap against
Sv48 was noticed and flagged by the IA in the results capture; it is a known
accepted decision documented in bp_cluster.md and requires no action at this
stage.

### The generalization

The two modules in this session pair illustrate a structural property of the
methodology at the module level. Modules with purely registered state and
well-defined update semantics (bp_history) are fast to specify and fast to
verify: the interface is the design, and the testbench follows directly from
the interface. Modules with SRAM structures and multiple access patterns
(ubtb) require more test cases to cover the combinatorial space of hit, miss,
tag collision, replacement, and read-during-write behavior, but the same
interface-first approach applies. In both cases, prompt length was comparable,
runtime was short, and verification was complete before the session ended.

---

## References

[1] A. Seznec and P. Michaud, "A Case for (Partially) TAgged GEometric
History Length Branch Prediction," Journal of Instruction Level Parallelism,
vol. 8, Feb. 2006.

[2] Wang, Kaifan, et al. "XiangShan open-source high performance RISC-V
processor design and implementation." Journal of Computer Research and
Development 60.3 (2023): 476-493.
