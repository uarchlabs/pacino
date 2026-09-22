<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

```
TITLE:     "The Statistical Corrector: Design Choices at p3"
FILE:      BLOG_bpu_17_statistical_corrector.md
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

# The Statistical Corrector: Design Choices at p3

## Abstract

The statistical corrector (SC) is the last direction predictor in the Pacino
branch prediction cluster. It reads five tables of signed counters, sums them
with a counter from TAGE, and may reverse the TAGE direction at p3. It was the
last predictor unbuilt, and it had no planning documents at the start of these
four sessions.

Two sessions produced the specification and two built the unit. The
specification sessions checked the SC's rules against their published sources
rather than against recall. The counter-update rule in the task text was
wrong and was replaced by the rule from the source. The dynamic threshold
parameters were corrected against the O-GEHL paper: the seed from 2048 to 10,
the maximum from 4096 to 512, and the adaptation counter from 10 bits to 7.
A review of the draft against the package structs found that the counter
capture stored the doubled counter value, which would have inflated every
counter on update.

Six implementation tasks built `sc_table`, `sc_brimli`, `sc_cntrl` and the
structural top `sc`, and each passed on its first run. The top-level suite
runs 55 checks. The unit suites run 6, 7 and 98.

The same sessions also broke TAGE. Package struct edits made during planning
were never compiled against the modules that used them, and the TAGE targets
stopped elaborating. The break went unreported until the first task that ran
the full regression. A report-only investigation then showed that the planned
fix, deleting the references, would have removed live storage.

The SC closes the range complete at the unit level. Whether it earns its area
is an open question, recorded as debt.

## The statistical corrector in Pacino

TAGE predicts a conditional branch from the longest matching history. It does
not capture branches whose outcome is statistically biased but not correlated
with any history TAGE tracks. The statistical corrector addresses that case. It sums
a small set of counters indexed by the PC and short histories, and when the sum
disagrees with TAGE strongly enough, it reverses the TAGE direction. The
override order in Pacino is SC over TAGE over FTB over uBTB. The SC result
forms at p3, one stage after TAGE.

Earlier analysis I did outside this project, which cannot be reused here,
showed little or no benefit from a baseline SC. This design includes three
mechanisms from the later literature: a dynamic threshold, a two-corner
chooser, and an index driven by a loop-iteration count (BrIMLI). The purpose
is to test whether those mechanisms recover the gain. Whether the SC earns its
area is deferred to physical design and performance evaluation and is recorded
as TD #93.

The unit as built has five tables of 6-bit signed counters. There are no tags,
no useful bits, no valid bits and no allocation. ST0 through ST3 have 512
entries each. ST0 is indexed by the PC alone. ST1 to ST3 hash the PC with a
folded global history from `bp_history`, using the fold definition in section
6 of `bp_history_decisions.md`. ST3 is the 64-bit fold case that the fold
helpers were widened for in the previous range. ST4 has 1024 entries and is
indexed by the BrIMLI mechanism described below.

## Specifying before building

Sessions 056 and 057 produced no RTL. I wrote the draft of `sc_decisions.md`
in session 056, and the planning assistant reviewed it against the packages
and against the published sources. Session 057 worked through the list of
defects the first review found and rewrote the arbitration specification.

### The counter-update rule

The task text I had written gated SC training on the TAGE misprediction, on
whether SC had overridden TAGE, and on the TAGE direction. None of those terms
appear in the published rule. The SC trains its counters when its own
prediction was wrong, or when the magnitude of its sum is below the threshold.
Each consulted counter moves one step toward the resolved direction and
saturates. This is the perceptron training rule [2], carried into the SC by
[1], and it is the rule in the gem5 SC implementation [6] and in the TAGE
cookbook simulator [5].

`sc_decisions.md` section 10 encodes the gate as `sc_wrong || sc_lo_upd`. The
gate does not depend on TAGE. A branch the SC predicted correctly with a large
sum is not trained.

### The threshold parameters

The threshold adapts at run time, following O-GEHL [3]. A 7-bit counter, TC,
counts up when the SC is wrong and down when training fires on a correct
low-magnitude sum. When TC saturates in either direction, the threshold steps
by one and TC resets. The threshold sets the training gate and the two chooser
bands described below.

The draft parameters were not taken from the source, and were checked against
it in session 057. O-GEHL seeds the threshold at the number of tables. The SC
sum doubles each counter and adds one, so the seed scales to twice the table
count: `SC_THRSH_MID` changed from 2048 to 10. The largest achievable sum
magnitude is about 322, bounded by `SC_LSUM_BITS = 10`, so `SC_THRSH_MAX`
changed from 4096 to 512 and `SC_THRSH_BITS` from 12 to 10. The source uses a
7-bit TC, so `SC_TC_BITS` changed from 10 to 7.

At the draft seed of 2048 the threshold was more than six times the largest
sum the hardware can form. The training gate would have been open on every
branch, and both chooser bands would have covered every achievable sum.

### The counter capture

The SC does not read-modify-write its tables. The prediction reads the
counters and captures them into `sc_pred_meta`. The update steps the captured
values and writes them back at the captured indices, with no second read and
no re-hash.

A check of the draft against the struct widths found that the capture wrote
the summed form of each counter, `2*ctr+1`, into `sc_upd_ctr`, and the update
then stepped that value and wrote it back. Each update would have written back
roughly twice the stored counter, until it saturated. The reads were also unsigned, so
negative counters summed as large positive values. Section 9 was corrected:
counters are read signed over -32 to 31, the `2*ctr+1` form is local to the
sum, and the raw counter is captured. The same pass added the capture of
`sc_override`, which had been computed and not stored.

### The two-corner chooser

The SC sum includes the TAGE provider's extended counter, `tage_extd_ctr`, at
weight 1. The published scheme weights the TAGE term by 8. That variant is
deferred for timing as TD #86.

The final direction is the SC's except in two cases. When TAGE is high
confidence and the SC sum is very low, and when TAGE is medium confidence and
the SC sum is very-very low, a saturating counter for that case chooses
between them. The two counters, `choose_hi_vlo` and `choose_med_vvlo`, train
toward whichever of SC and TAGE matched the outcome. The TAGE confidence
classes follow [4]. The band edges are the threshold shifted right by one and
by two. That split is a local construction and does not come from O-GEHL,
which uses a single threshold; `sc_decisions.md` says so, and the tuning is part
of TD #93.

### BrIMLI

ST4 is indexed by the BrIMLI mechanism, taken from the TAGE cookbook simulator
source [5]. A register, `last_back_pc`, holds bits 15 to 6 of the PC of the
last taken backward branch, with a valid bit. `br_imli` counts consecutive
taken backward branches in the same 64-byte region and saturates at 1023. When
a taken backward branch arrives from a different region, `bb_hist` shifts in
the region being left and `br_imli` resets to zero. The index value is
`br_imli` when it is non-zero and the path history otherwise, hashed as
`pc ^ f ^ (pc >> 4)` over PC bits 15 to 6.

Two variants were added for performance evaluation, one using path history
only and one using the iteration count only, selected by `br_imli_mode_e`.

The BrIMLI registers are updated at resolution, not at prediction. The FTB
must therefore supply each resolved branch's region and whether it is a
backward branch. Session 057 removed a PC field from the prediction metadata
and made those two update-side fields, `branch_range` and `backwards_branch`,
the single source. The FTB storage they require is TD #89 and TD #90.

## Arbitration: SC as a standalone predictor

The arbitration specification had modeled TAGE and SC as one predictor, with
merged metadata and update structs, `cond_pred_meta_t` and
`cond_pred_upd_inp_t`, and a shared update queue. Session 057 rewrote
`bp_arb_spec.md` to a standalone SC.

The configurations were bounded to three. The SC can be removed at compile
time. It can be present and fused, where the FTB sees only the final post-SC
direction. Or it can be present and separate, where TAGE drives the FTB at p2
and the SC applies a p3 redirect. In the last two a CSR, `sc_enable`, disables
the SC at run time: control stops waiting for SC results and issuing SC
updates, and the FTB continues to store the SC-related fields.

Each SC table RAM has one port, shared by the prediction read and the update
write, and the existing credit arbiter governs that contention. The SC has no
prediction queue of its own. The TAGE response buffer holds the SC's pending
predictions, so SC prediction rate is limited by TAGE's. The SC has its own
update queue, and a resolved conditional branch enqueues one entry in each
queue. When the arbiter grants an SC update over an SC prediction, the head of
the TAGE response buffer is held, which back-pressures TAGE.

The merged structs were retired in the package, and the SC uses
`sc_pred_meta_t` and `sc_upd_inp_t` directly. That change is where the TAGE
break described below began.

The update queue is not built at the unit level. `sc` drives
`sc_uq_not_full` and the update-ready outputs to constants, and the queue is
deferred to cluster integration.

## Building the unit

Session 058 wrote the remaining planning documents: `sc_interfaces.md`,
`sc_table_interfaces.md`, `sc_table_hash_rules.md` and `sc_tb_decisions.md`.
Two planned documents were dropped. `sc_cntrl_decisions.md` would have had no
content independent of `sc_decisions.md`, and `sc_table_entry_formats.md` would
have described a single signed counter. The one open question in the interface
work, which PC bits feed ST4, was recorded as an interface gap rather than
assumed, and resolved to `inp_pc_p2[15:6]`.

The unit was split into two table modules and a control module. `sc_table`
implements ST0 to ST3 and `sc_brimli` implements ST4. They were kept separate
because ST4's index has different inputs, and may be merged later. Both are
pure RAM wrappers. Each prediction slot has its own RAM, and an update from a
slot writes only that slot's RAM. The tables compute their own index at p2,
expose it as `idx_hash_p2`, and return the counter at p3. All SC state other
than the counters, including the threshold, TC, the two chooser counters and
the BrIMLI registers, is in `sc_cntrl`.

BP-075 wrote `sc_table`. Its testbench was omitted from the task in error, and
BP-075a added it with six tests. BP-076 wrote `sc_brimli` and its testbench
together. BP-077 wrote `sc_cntrl`, deriving its port list from
`sc_decisions.md`, which I authorized, since no document defined the
control-layer boundary. The IA gave `sc_cntrl` a table-facing port set so that
it can be tested without the tables, and its testbench runs 98 checks against
hand-computed values. All four tasks passed on the first run.

### Dual-slot scalar state

`sc_decisions.md` declares the threshold, TC, chooser counters and BrIMLI
registers as single copies. It does not say what happens when both prediction
slots deliver an update in the same cycle. BP-077 resolved this in the module
header: the lowest-indexed valid slot drives the shared state, and each slot's
counter writes proceed independently. The review of BP-077's stated
assumptions took this up, and it was recorded as TD #98. It is a temporary
rule. Whether the shared state should be duplicated, shared or merged is a
performance question and does not affect unit correctness.

### The structural top

BP-078 wrote `sc`, which instantiates `sc_cntrl`, a generate loop of four
`sc_table` instances, one `sc_brimli`, and one `sram_init` sized to the
largest table. It gates prediction and update on `sc_ready` and bypasses the
initialization sequencer in the fast-init simulation mode, following the
`tage` pattern.

The task was written after the three lower modules existed, against their RTL
rather than their documents. That surfaced four items the documents did not.
The ST0 to ST3 indices are 9 bits and the control-layer index buses are 10
bits, so `sc` zero-extends the table indices up and slices the update index
down. The update queue has no implementation at this level, so its status
ports are stubbed. One `sram_init` serves all five tables. And
`sc_interfaces.md` omitted `br_imli_mode` from the top-level port list.

The integration testbench drives a prediction through the real tables into
`sc_cntrl` and an update back through them, across both initialization modes.
It runs 55 checks in the normal mode and 52 in the fast mode, which has no
not-ready window to test.

### The BrIMLI mode as a parameter

BP-078 added `br_imli_mode` as a run-time input to `sc`, routed through
`sc_cntrl` to `sc_brimli`. The only consumer is the ST4 index, and the mode
selects a performance-evaluation variant, not a run-time behavior. I made it a
compile-time parameter. BP-079 moved it to a `BR_IMLI_MODE` parameter on
`sc_brimli`, exposed as `SC_BR_IMLI_MODE` on `sc`, and removed it from
`sc_cntrl`. The `sc_brimli` testbench now covers the three modes with three
instances, one per parameter value. The default-mode results were unchanged.

## Package edits that were never compiled

The planning sessions edited `bp_structs_pkg.sv` and `bp_defines_pkg.sv`
directly, outside any implementation task. Nothing compiled those edits until
an implementation task used them, and three errors surfaced later.

Two enum declarations in session 056 would not compile as written: a missing
comma in `br_imli_mode_e` and a trailing comma in `bp_sc_chooser_e`. The
review of the draft found both in session 056, and they were fixed in session
057. In session 058
Verilator rejected `sc_pred_meta_t`, whose `sc_upd_idx` and `sc_upd_ctr`
fields had an unpacked dimension inside a packed struct; they were converted
to packed two-dimensional arrays.

The third was not in the SC. Retiring the merged structs removed
`cond_pred_meta_t` and `cond_pred_upd_inp_t`, and the confidence field
`tage_high_conf` was removed from `tage_pred_meta_t`. `tage.sv` and
`tage_cntrl.sv` still used all three, and from that point the six TAGE targets
did not elaborate. The four session-058 tasks ran only their own targets.
BP-075 recorded that it had not run the full regression. BP-078 ran every
target in the unit, reported the six TAGE failures as pre-existing and outside
its scope, and showed with `git diff` that it had not touched TAGE or the
packages. BP-079 then waived those six targets by name, so the task did not
try to repair them.

### Investigating before fixing

BP-080 was written as a gated task. Phase 1 would locate every reference and
propose a fix, with no file edits, and Phase 2 would apply the fix only on
explicit approval. The hypothesis in the task was that all three references
were vestigial and could be removed.

The Phase 1 report showed the hypothesis was half wrong. `tage_high_conf` was
dead: its only consumer was the write to the removed field. The two merged
types were not dead. They were the element types of two live FIFOs in
`tage.sv`, the update queue `uq_data_mem` and the response buffer
`rb_meta_mem`, whose outputs drive the `tage_cntrl` update port and the TAGE
prediction output. Only the SC-side subfields inside the merged wrappers were
dead, written and never read. The fix was to retype the two FIFOs to
`tage_upd_inp_t` and `tage_pred_meta_t` and collapse the per-field writes,
which is behavior-identical. Deleting the references, as the hypothesis
proposed, would have removed the storage.

I stopped the task after Phase 1. The change was a struct reconciliation, not
a lint repair, and it needed its own task. The policy for that task was set in
session 059: retype the FIFOs, delete the dead confidence logic, and tie the
SC-facing TAGE fields that TAGE does not yet generate, `tage_pred_medium`,
`tage_provider_ctr` and `tage_extd_ctr`, to zero and report each as owed.
Generating them is TD #87 and TD #88. The BP-080 manifest listed a file that no
longer exists and placed another under the wrong directory; I corrected both
by hand before the run.

## What the testbenches establish

The index checks in `tb_sc_table` and `tb_sc_brimli` compute the expected
index in the testbench using the same expression as the RTL, as both tasks
state. `tb_sc` transcribes the hash rules into its own reference functions.
These checks confirm that the index is wired and that the RTL matches its
transcription of `sc_table_hash_rules.md`. The rule itself is defined in that
document, so a check against it is possible. These tests do not make one.

BP-076 added two divergence checks to the mode test that the task did not ask
for, so that a module ignoring the mode selector would fail.

The sum, band, chooser, threshold and counter-update checks use hand-computed
values. For example, `tb_sc_cntrl` drives counters of 3, -2, 5, 0 and -1 with
a TAGE term of 2, and checks for a sum of 17. `tb_sc` seeds every consulted
entry with 3 and checks for 35.

Whether a fold from `bp_history` produces the intended index once it passes
through the SC hash is not tested at the unit level. That end-to-end check is
TD #84, which now covers SC ST1 to ST3 as well as TAGE and ITTAGE.

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| BP-075 | sc_table (ST0-ST3) RTL and lint target | PASS | lint 0/0 | 4m 49s | 11% |
| BP-075a | tb_sc_table, six directed tests, normal and fast init | PASS | 6/0, 6/0 | 8m 52s | 15% |
| BP-076 | sc_brimli (ST4) RTL and testbench | PASS | lint 0/0; 7/0, 7/0 | 8m 19s | 15% |
| BP-077 | sc_cntrl RTL and testbench; port list derived; dual-slot assumption recorded | PASS | lint 0/0; 98/0 | 25m 51s | 28% |
| BP-078 | sc structural top and integration testbench; TAGE break reported | PASS | lint 0/0; 55/0, 52/0 | 20m 23s | 27% |
| BP-079 | br_imli_mode converted from port to compile-time parameter | PASS | all SC targets green; 6 TAGE targets waived | 9m 51s | 17% |
| BP-080 | Gated investigation of the TAGE elaboration break; stopped after Phase 1 | STOPPED | report only, no files modified | 5m (est.) | 6% |

## Design Process Notes

### The IA contribution

The six build tasks each passed on their first run. BP-078 did the most work
beyond its prompt. It was written against the real
RTL of the lower modules and reconciled every control-layer port to a table
port. It found the index-width mismatch and resolved it from the package
parameters rather than assuming. It confirmed from the package that the counter
widths needed no adapter. It added one lint suppression beyond the one its
constraints allowed, and flagged it with the reason. Its testbench read the
reset values of `br_imli` and the threshold by hierarchical reference and
checked them before relying on them.

The same task ran the full unit regression, found the TAGE break, reported it
as pre-existing, and did not attempt to repair files outside its scope. BP-080
then corrected its own task's hypothesis in the Phase 1 report, which is the
result that changed the fix.

BP-077 recorded its dual-slot assumption in the module header. The task did
not ask for a rule. Because the assumption was written down, the review found
it and it became TD #98.

### The PA contribution

The planning assistant checked the SC's rules against the published sources
and the simulator code, and those checks set the update gate, the threshold
seed and maximum, and the TC width. It found the counter-capture defect by
reading the draft's widths against the struct. It rewrote the arbitration
specification to the standalone model, wrote the four session-058 planning
documents, and wrote the seven task files.

On the update gate, the assistant first stated a different rule from recall,
then accepted the task-text rule, before it pulled any source. The source
matched neither. In session 059 it wrote a rationale into `sc_decisions.md`
and into BP-079 claiming that the mode parameter's default could not be placed
in `bp_defines_pkg` because of package import order. That constraint does not
exist, and the paragraph was removed from both files. It wrote BP-078 to add
`br_imli_mode` as a port rather than raising the port-versus-parameter
question, which is why BP-079 was needed. And it built the BP-080 manifest
without checking each path against the tree.

The assistant did not compile the package edits it made or reviewed during
planning, and nothing in the process required it to.

### My contribution

I wrote the first draft of `sc_decisions.md`, including the two-corner
chooser, the BrIMLI variants and the reset initialization. I bounded the SC
configurations to three and added the run-time enable. I removed the PC field
from the prediction metadata and moved the branch region and direction sign
into FTB storage, TD #89 and TD #90. I set the module decomposition, authorized
BP-077 to derive the control-layer port list, and made the BrIMLI mode a
compile-time parameter.

The task text that gated training on the TAGE misprediction was mine.

I stopped BP-080 after Phase 1 and set the tie-off policy for the TAGE
reconciliation. I corrected the BP-080 manifest before it ran.

### The generalization

The specification sessions checked the SC's rules and parameters against their
sources, and the unit that was built from them passed every task on its first
run. The same sessions edited two compiled package files and did not compile
them. Three errors followed: two enum declarations that would not compile, a
struct Verilator rejected on first use, and a TAGE unit that stopped
elaborating.

The TAGE break persisted through four tasks because each task ran its own
targets. That scope is correct for a task that adds a new unit and touches
nothing shared. It is not correct for a change to a shared package, and the
package change was not made in a task.

An edit to a compiled file is an RTL change regardless of which session makes
it. In this project a planning session that edits a package needs the same
compile and full regression that an implementation task gets, and the first
task after it should run every target, not only its own.[F1]

## What comes next

The SC closes the range complete at the unit level: `sc_table`, `sc_brimli`,
`sc_cntrl` and `sc` are written, lint clean, and green across their unit and
integration suites. The coverage plan, `sc_coverage_plan.md`, is not written.
The counter-update rule table, `sc_cntrl_ctr_update_rules.md`, is optional and
deferred to coverage time.

The next task is not SC work. It is the TAGE struct reconciliation scoped by
BP-080, which restores the TAGE targets.

The remaining SC dependencies are on other units and gate cluster integration,
not the SC unit. TAGE must generate `tage_pred_medium` and `tage_extd_ctr`
(TD #87, TD #88). The FTB must store and supply each branch's region and
direction sign (TD #89, TD #90). The cluster must route the PC and path history
to p2 for the SC (TD #91, TD #92). The update queue and arbiter, the flush
behavior (TD #96), and the SC's share of the end-to-end fold check (TD #84)
are cluster work.

The question the SC was built to answer, whether its added mechanisms recover
a gain a baseline SC did not show, is TD #93, and it waits on performance
evaluation.

## Technical Debt Referenced

The table below reports status as of the close of this range. Later
experiments outside the range have since changed the state of some items.

| # | Item | Resolution path |
|---|---|---|
| 84 | Producer and consumer end-to-end fold check. | BP-073 proved the fold value against the canonical definition; it did not run that fold through a table index hash. SC ST1-ST3 are additional consumers of the bp_history folds. Needs cluster stimulus. |
| 85 | bp_structs_pkg.sv field sharing. | Review BPU structures for field sharing and storage/flop opportunities. |
| 86 | sc_cntrl 8x-weighted TAGE term. | The current sum includes tage_extd_ctr at weight 1. The 8x variant is deferred to PD / perf. Related: #93. |
| 87 | TAGE strong/medium/weak decode. | TAGE must emit tage_pred_medium, which the SC chooser consumes. The struct field is present; generation is not written. Interim: tie to zero in the TAGE reconciliation task (policy set session-059). |
| 88 | TAGE provider_ctr / extd_ctr generation. | TAGE must emit tage_provider_ctr and tage_extd_ctr; the SC sum consumes tage_extd_ctr. Struct fields present; generation not written. Same interim tie-off as #87. |
| 89 | FTB branch region storage. | Change the FTB definition to store 20 additional bits, PC bits [15:6] of each branch location, supplied to sc_upd_inp.branch_range. |
| 90 | FTB backward-branch sign storage. | Change the FTB to store 2 additional bits, the target signs for conditional branches 0 and 1, as backwards_branch0/1, supplied to sc_upd_inp.backwards_branch. One bit per prediction slot. |
| 91 | bpc PC routing to SC. | Route the PC from p0 to p2 as inp_pc_p2 per slot. |
| 92 | bpc path history capture for SC. | Capture phr[9:0] as sc_phr_p2 for the ST4 index. |
| 93 | SC efficacy and threshold/band tuning. | Deferred investigation. Open questions at PD/perf: does SC earn its area/power; the SC_THRSH_MID=10 / SC_THRSH_MAX=512 seeds vs achievable sum magnitude ~322; the vlo/vvlo band split (local, not O-GEHL); the 8x TAGE term (#86) interaction. Gate any SC die-area commitment on this. |
| 94 | bp_arb_spec reconciliation to the standalone SC. | Section 6 rewritten session-057. The retired cond_pred_meta_t / cond_pred_upd_inp_t types are still the element types of two live tage.sv FIFOs; BP-080 scoped the fix as a retype to tage_upd_inp_t / tage_pred_meta_t. Open. |
| 95 | tage_pred_meta_t changed; TAGE references to reconcile. | tage_high_conf was removed from the struct and is dead in tage_cntrl.sv (BP-080). Delete it and tie the ungenerated SC-facing fields to zero. Open. |
| 96 | Flush protocol. | The flush (_px) ports for the SC and the tables are not defined. Referenced by bp_arb_spec 7.2. Deferred to bp_cluster.[F2] |
| 97 | Shared upstream prediction queue. | To determine whether a shared upstream PQ broadcasting to all predictor PQs is implemented. Deferred. |
| 98 | sc_cntrl shared scalar state under dual-slot update. | TEMPORARY (BP-077): the lowest-indexed valid update slot drives the shared threshold/TC/chooser/BrIMLI adaptation. Evaluate at PD/perf. Related: #93, #86. |

## References
<!-- ticfinder_off -->

[1] A. Seznec, "A New Case for the TAGE Branch Predictor," in Proc. 44th
IEEE/ACM International Symposium on Microarchitecture (MICRO), 2011.

[2] D. A. Jiménez and C. Lin, "Neural Methods for Dynamic Branch
Prediction," ACM Transactions on Computer Systems, vol. 20, no. 4, 2002.

[3] A. Seznec, "Analysis of the O-GEometric History Length Branch
Predictor," ISCA-32, 2005, pp. 394-405.

[4] A. Seznec, "Storage Free Confidence Estimation for the TAGE Branch
Predictor," in Proc. 17th International Symposium on High-Performance
Computer Architecture (HPCA), 2011.

[5] A. Seznec, TAGE cookbook simulator source, predictor.h, Inria.
https://files.inria.fr/pacap/seznec/TageCookBook/predictor.h

[6] gem5 simulator, statistical corrector implementation,
src/cpu/pred/statistical_corrector.cc. https://github.com/gem5/gem5
<!-- ticfinder_on -->

## Footnotes

<!-- ticfinder_off -->
[F1] In later sessions TOOLS-006 added `tools/regress.sh`, which runs every
target of every `rtl/` Makefile, fails on an unclassified target, and is gated
at push.

[F2] TD #96 was later closed on the finding that there is no separate flush
event: a flush is a redirect, and a predictor is cleared by withholding its
stage valid. The `_px` ports are retained but redundant.
<!-- ticfinder_on -->

---
<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
