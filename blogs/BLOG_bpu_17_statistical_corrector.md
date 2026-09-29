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

In these sessions the statistical corrector (SC) direction predictor is
specified and implemented. At the end of these sessions the SC was verified at
the unit level.

PA sessions 56 and 57 created the SC planning documents, PA sessions 58 and 59
implemented the RTL and testing. Under 58/59, tasks BP-075 to BP-079 were
executed to create the RTL.

During SC implementation, the TAGE design elaboration was impacted. BP-080 was
executed to quantify the problems for repair in a follow on session. The main
problems were in TAGE confidence indicator flags, `tage_high/medium/weak_conf`.
BP-080 gathered data for the eventual fix in BP-081. Those repairs are complete
in the current repo RTL. Discussion of the repairs to TAGE will be in the next
article.

The SC design closed in this range as unit complete. Technical debt (TD#93) was
recorded for performance analysis of the SC.

This article is a departure from the normal subject matter. These sessions
followed the expected specification and execution sequence, and the SC work
itself required no change to the methodology. The one process finding concerns
package edits made during planning. They were not compiled, and one of them
broke TAGE elaboration. The break was found by the standard methods and
repaired in a later session.

Notwithstanding the large body of literature available describing statistical
correctors, I will use some of this space to describe the Pacino statistical
corrector in detail. There is also a non-exhaustive comparison of the Pacino
design choices to the limited number of public designs.

## The statistical corrector in Pacino

The statistical corrector (SC) is a tagless direction predictor used to assess
predictions from TAGE and determine the likely correctness of the TAGE
prediction.

The core mechanism in the Pacino SC is a GEHL-style [1] perceptron constructed
from 5 tables (ST0-ST4) containing signed 6 bit counters. Three of the tables
are indexed by varying length hashes of the direction history and PC, table 0
is unhashed. ST4 is a BrIMLI table indexed by a hash of the current loop's
iteration count.

The indexed counters read from the SC tables are combined to form a signed
value. The sign of this value is the SC prediction, positive equals taken. The
magnitude of this value is the SC confidence.

With two exceptions, the SC will override a TAGE prediction when SC and TAGE
directions differ. The exceptions are:

- **TAGE strong, SC weak**.
    - The TAGE provider counter is saturated (strong) and the SC magnitude is
      _below half the threshold_. The SC overrides only if the `choose_hi_vlo`
      counter is non-negative. Otherwise the TAGE prediction stands.

- **TAGE medium, SC very weak**.
    - The TAGE provider counter is one or two steps from saturation (medium)
      and the SC magnitude is _below one quarter of the threshold_. The SC
      overrides only if the `choose_med_vvlo` counter is non-negative.
      Otherwise the TAGE prediction stands.

## Simplified explanation of the Pacino SC operation

The SC services two kinds of requests. A prediction request reads the SC tables
and produces a prediction. An update request, issued when a branch resolves,
trains the tables and the threshold logic. Only an update request modifies SC
state.

There is one nuance in this process. During a prediction request the data
needed by a subsequent update is returned along with the prediction in the
_prediction meta data_. By doing this read/modify/writes of the SC state are
not required. This improves the throughput of updates.

### Prediction request

On a prediction request the SC reads one signed 6 bit counter from each of the
five tables. Each counter contributes `2*ctr+1` to the sum, a value between -63
and +63. The TAGE prediction meta data includes the provider counter (CTR) used
in the TAGE prediction. The 3 bit TAGE CTR is rescaled to a signed value
between -7 and +7, `tage_extd_ctr = 2*CTR - 7`, and added to the five table
contributions. This produces the sum `S`. The sign of `S` is the SC prediction,
`sc_lcl_pred_tkn`. The magnitude of `S`, `|S|`, is the SC's confidence in that
prediction.

The SC's confidence is used only when the SC prediction differs from the TAGE
prediction. If the TAGE and SC direction predictions are the same there is
nothing to override. When they differ, the result depends on the TAGE
confidence class, decoded from the TAGE CTR, and on `|S|` relative to the
`threshold` register.

- **TAGE strong** (`tage_pred_strong`, CTR 000 or 111) **and** `|S|` less than
  one half of `threshold`: the strong-TAGE chooser, `choose_hi_vlo`, decides.
  The SC prediction is used if `choose_hi_vlo` is non-negative, otherwise the
  TAGE prediction stands.
- **TAGE medium** (`tage_pred_medium`, CTR 001, 010, 101 or 110) **and** `|S|`
  less than one quarter of `threshold`: the medium-TAGE chooser,
  `choose_med_vvlo`, decides in the same way.
- **All other disagreements**, including every disagreement where TAGE is weak
  (CTR 011 or 100): the SC prediction overrides the TAGE prediction.

A strong TAGE prediction is therefore overridden whenever the SC disagrees with
`|S|` at or above one half of `threshold`.

The final prediction, `sc_pred_tkn`, is returned with the meta data needed for
the update: the five table indices, the five raw counter values, `S`, `|S|`,
the TAGE prediction, and which chooser, if any, was consulted.

There are four registers in the threshold logic.

| Common Name                  | RTL name          | Width           | Purpose     |
|------------------------------|-------------------|-----------------|-------------|
| threshold register           | `threshold`       | 10 bit unsigned | marks the boundary between high and low SC confidence |
| threshold adaptation counter | `tc_reg`          | 7 bit signed    | determines when to modify `threshold` |
| strong-TAGE chooser          | `choose_hi_vlo`   | 6 bit signed    | picks SC or TAGE when the TAGE prediction is strong and SC is weak |
| medium-TAGE chooser          | `choose_med_vvlo` | 6 bit signed    | picks SC or TAGE when the TAGE prediction is medium and SC is very weak |

In Pacino an SC prediction is considered weak when `|S|` is less than one half
of `threshold`. An SC prediction is considered very weak when `|S|` is less
than one quarter of `threshold`. The fractions are fixed in the comparison
logic. The band boundaries move with the value held in `threshold`.

The `choose_hi_vlo` register learns which of TAGE or SC is more often correct
when a strong TAGE prediction is contradicted by a weak SC prediction.

The `choose_med_vvlo` register learns which of TAGE or SC is more often correct
when a medium confidence TAGE prediction is contradicted by a very weak SC
prediction.

### Update request

An update request returns the prediction meta data with the resolved
direction, `resolved_taken`. Up to two update requests are accepted per cycle,
one per prediction slot.

**Table counters.** The counters are trained when the SC prediction was
incorrect (`sc_lcl_pred_tkn != resolved_taken`) or when `|S|` is less than
`threshold`. When training is enabled, each of the five captured counters
moves one step toward the resolved direction, saturating at -32 and +31, and is
written back at its captured index. The tables are not read during the update.
Each slot writes its own table RAMs.

**Threshold registers.** `threshold`, `tc_reg` and the two choosers are single
registers shared by both slots. When both slots present an update in the same
cycle, only the lowest-indexed valid slot changes them (TD #98).

`tc_reg` is updated on every update request.

- `tc_reg` is incremented if the SC prediction was incorrect
  (`sc_pred_meta.sc_lcl_pred_tkn != sc_upd_inp_u0.resolved_taken`).
- Otherwise `tc_reg` is decremented if `|S|` is less than `threshold`.
- Otherwise `tc_reg` is unchanged.

- If `tc_reg` reaches +63, `tc_reg` is cleared and `threshold` is incremented,
  up to 512.
- If `tc_reg` reaches -64, `tc_reg` is cleared and `threshold` is decremented,
  down to 1.

`threshold` resets to 10 and `tc_reg` resets to 0. A sustained excess of SC
mispredictions raises `threshold`, which widens the training margin and both
chooser bands. A sustained excess of correct, low-confidence SC predictions
lowers it.

A chooser is updated only when it was consulted for the prediction. It is
incremented if the final prediction was correct, and decremented if the final
prediction was incorrect and the TAGE prediction was correct. Both choosers
saturate at -32 and +31 and reset to 0.

Figure 1 shows the update of the four threshold registers for one update
request.

FIG: SC Threshold and Chooser Update - Claude
![SC Threshold and Chooser Update](sc_flow.svg)

## Effectiveness of statistical correctors

In general the literature agrees that statistical correctors improve prediction
accuracy. There is mixed data on the effectiveness, and there are few public
disclosures of commercial designs implementing an SC, although there are hints
in patent filings and whitepapers of unshipped RISC-V machines.

I mentioned that the utility of the SC will be analyzed in the future, TD #93
records this. As an aside, there are a number of configurations in the Pacino
BPU that will be assessed, such as combinations of SC, LP, `USE_ALT_ON_NA`, and
the numerous flavors of innermost loop iteration counters, SIC/HH/Ta/exact.

The table below provides a reference comparison for a limited number of SC
implementations.

| Parameter | Pacino | Seznec TAGE-SC (MICRO 2011) | XiangShan |
|---|---|---|---|
| SC tables | 5 | 4 | 4 |
| History inputs | Global (0, 4, 16, 64 bits) + BrIMLI | Global (0, 6, 10, 17 bits) | Global (0, 4, 10, 16 bits) |
| Local-history or loop-iteration input | BrIMLI table (ST4) | None | None |
| TAGE direction used in table index | No | Yes | Yes (two counters per entry, selected by TAGE direction) |
| Counter width | 6 bits | 6 bits | 6 bits |
| Entries per table | 512 (ST0-ST3), 1024 (ST4) | 1K | 512 across the two branch slots, each entry holding one counter per TAGE direction |
| Counter storage | 2.25 KiB per slot, 4.5 KiB for 2 slots | 24 Kbit (3 KiB) | 3 KiB for 2 branches |
| Sum | Centered counters (2*ctr+1) + TAGE term | Centered counters + TAGE term | Centered counters + TAGE term |
| TAGE counter weight | 1 (8 deferred, TD#86) | 8 | 8 |
| Override rule | SC wins on disagreement; choosers decide two low-confidence corners | Invert TAGE if SC disagrees and \|sum\| > threshold | Invert TAGE if a TAGE table hit provided the prediction and \|sum\| > threshold |
| Chooser counters | 2 (TAGE strong / medium corners) | None described | None |
| Dynamic threshold | 1 shared, range 1-512, adjusted by a 7-bit counter | 1, GEHL-style adaptation | 1 per branch slot, range 6-33 in steps of 2, adjusted by a 5-bit counter |
| Predictions per cycle | 2 | 1 | 2 |
| Latency after TAGE | 1 cycle (TAGE p2 in, result at p3) | Not specified | Read in parallel with TAGE; sum formed in the following stage |

## Specifying before building

Sessions 056 and 057 produced the planning document `sc_decisions.md` and no
RTL. I wrote the draft in session 056, and the planning assistant reviewed it
against the packages and against the published sources. Session 057 worked
through the defects that review found and rewrote the arbitration
specification. The operation described in the previous sections is the result.
This section records what changed between the draft and that result.

### The counter-update rule

The task text I had written gated SC training on the TAGE misprediction, on
whether the SC had overridden TAGE, and on the TAGE direction. None of those
terms appear in the published rule. The rule given under Update request is the
perceptron training rule [2], carried into the SC by [1]. It is also the rule
in the gem5 SC implementation [6] and in the TAGE cookbook simulator [5].
`sc_decisions.md` section 10 encodes it as `sc_wrong || sc_lo_upd`, with no
TAGE term.

### The threshold parameters

The threshold adaptation follows O-GEHL [3], but the draft parameters were not
taken from it. Session 057 checked them against the source and changed four.

| Parameter       | Draft | Final | Basis |
|-----------------|-------|-------|-------|
| `SC_THRSH_MID`  | 2048  | 10    | O-GEHL seeds the threshold at the table count; the `2*ctr+1` sum doubles it |
| `SC_THRSH_MAX`  | 4096  | 512   | the largest achievable `\|S\|` is about 322, bounded by `SC_LSUM_BITS = 10` |
| `SC_THRSH_BITS` | 12    | 10    | follows from `SC_THRSH_MAX` |
| `SC_TC_BITS`    | 10    | 7     | O-GEHL uses a 7-bit adaptation counter |

At the draft seed of 2048 the threshold was more than six times the largest
sum the hardware can form. The training gate would have been open on every
branch, and both chooser bands would have covered every achievable sum.

### The counter capture

A check of the draft against the struct widths found two defects in the
counter capture. The capture wrote the summed form of each counter, `2*ctr+1`,
into `sc_upd_ctr`, and the update stepped that value and wrote it back. Each
update would have written back roughly twice the stored counter until it
saturated. The reads were also unsigned, so negative counters summed as large
positive values.

Section 9 of `sc_decisions.md` was corrected. Counters are read signed over
-32 to 31, the `2*ctr+1` form is local to the sum, and the raw counter is
captured. The same pass added the capture of `sc_override`, which had been
computed and not stored.

### The TAGE term and the chooser bands

The SC sum includes `tage_extd_ctr` at weight 1. The published scheme weights
the TAGE term by 8. That variant is deferred for timing as TD #86.

The TAGE confidence classes follow [4]. The chooser band edges, `threshold`
shifted right by one and by two, are a local construction. O-GEHL uses a
single threshold. `sc_decisions.md` states this, and the tuning is part of
TD #93.

### BrIMLI

ST4 is indexed by the BrIMLI mechanism, taken from the TAGE cookbook simulator
source [5]. A register, `last_back_pc`, holds bits 15 to 6 of the PC of the
last taken backward branch, with a valid bit. `br_imli` counts consecutive
taken backward branches in the same 64-byte region and saturates at 1023. When
a taken backward branch arrives from a different region, `bb_hist` is shifted
left one bit and XORed with the previous and the new region, and `br_imli`
resets to zero. In the default mode the index value is `br_imli` when it is
non-zero and the path history otherwise, hashed as `pc ^ f ^ (pc >> 4)` over
PC bits 15 to 6.

Two variants were added for performance evaluation, one using path history
only and one using the iteration count only, selected by `br_imli_mode_e`.

The BrIMLI registers are updated at resolution, not at prediction. The FTB
must therefore supply each resolved branch's region and whether it is a
backward branch. Session 057 removed a PC field from the prediction metadata
and made two update-side fields, `branch_range` and `backwards_branch`, the
single source. The FTB storage they require is TD #89 and TD #90.

## Arbitration: SC as a standalone predictor

The arbitration specification had modeled TAGE and SC as one predictor, with
merged metadata and update structs, `cond_pred_meta_t` and
`cond_pred_upd_inp_t`, and a shared update queue. Session 057 rewrote
`bp_arb_spec.md` to a standalone SC.

The configurations were bounded to three:

- **Removed.** The SC is removed at compile time.
- **Present and fused.** The FTB sees only the final post-SC direction.
- **Present and separate.** TAGE drives the FTB at p2 and the SC applies a p3
  redirect.

In the last two a CSR, `sc_enable`, disables the SC at run time. Control stops
waiting for SC results and issuing SC updates, and the FTB continues to store
the SC-related fields.

Each SC table RAM has one port, shared by the prediction read and the update
write, and the existing credit arbiter governs that contention. The SC has no
prediction queue of its own. The TAGE response buffer holds the SC's pending
predictions, so the SC prediction rate is limited by TAGE's. The SC has its
own update queue, and a resolved conditional branch enqueues one entry in each
queue. When the arbiter grants an SC update over an SC prediction, the head of
the TAGE response buffer is held, which back-pressures TAGE.

The merged structs were retired in the package, and the SC uses
`sc_pred_meta_t` and `sc_upd_inp_t` directly. That change is where the TAGE
break described below began.

The update queue is not built at the unit level. `sc` drives `sc_uq_not_full`
and the update-ready outputs to constants, and the queue is deferred to cluster
integration.

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
together. BP-077 wrote `sc_cntrl`. No document defined the control-layer
boundary, so I authorized BP-077 to derive the port list from
`sc_decisions.md`. The IA gave `sc_cntrl` a table-facing port set so that it
can be tested without the tables, and its testbench runs 98 checks against
hand-computed values. All four tasks passed on the first run.

### Dual-slot scalar state

`sc_decisions.md` declares the threshold, TC, chooser counters and BrIMLI
registers as single copies, and does not say what happens when both prediction
slots deliver an update in the same cycle. BP-077 chose the lowest-indexed
valid slot rule given under Update request and stated it in the module header.
The review of BP-077's stated assumptions recorded it as TD #98. The rule is
temporary. Whether the shared state should be duplicated, shared or merged is
a performance question and does not affect unit correctness.

### The structural top

BP-078 wrote `sc`, which instantiates `sc_cntrl`, a generate loop of four
`sc_table` instances, one `sc_brimli`, and one `sram_init` sized to the
largest table. It gates prediction and update on `sc_ready` and bypasses the
initialization sequencer in the fast-init simulation mode, following the
`tage` pattern.

The task was written after the three lower modules existed, against their RTL
rather than their documents. That exposed four items the documents did not
cover:

- The ST0 to ST3 indices are 9 bits and the control-layer index buses are 10
  bits, so `sc` zero-extends the table indices up and slices the update index
  down.
- The update queue has no implementation at this level, so its status ports
  are stubbed.
- One `sram_init` serves all five tables.
- `sc_interfaces.md` omitted `br_imli_mode` from the top-level port list.

The integration testbench drives a prediction through the real tables into
`sc_cntrl` and an update back through them, across both initialization modes.
It runs 55 checks in the normal mode and 52 in the fast mode, which has no
not-ready window to test.

### The BrIMLI mode as a parameter

BP-078 added `br_imli_mode` as a run-time input to `sc`, routed through
`sc_cntrl` to `sc_brimli`. Its only consumer is the ST4 index, and the mode
selects a performance-evaluation variant, not a run-time behavior, so I made it
a compile-time parameter. BP-079 moved it to a `BR_IMLI_MODE` parameter on
`sc_brimli`, exposed as `SC_BR_IMLI_MODE` on `sc`, and removed it from
`sc_cntrl`. The `sc_brimli` testbench now covers the three modes with three
instances, one per parameter value. The default-mode results were unchanged.

## Package edits that were never compiled

The planning sessions edited `bp_structs_pkg.sv` and `bp_defines_pkg.sv`
directly, outside any implementation task. Nothing compiled those edits until
an implementation task used them. Three problems followed.

- **Two enum declarations.** Session 056 wrote a missing comma in
  `br_imli_mode_e` and a trailing comma in `bp_sc_chooser_e`. The review of
  the draft found both by reading, and session 057 fixed them.
- **A packed struct.** In session 058 Verilator rejected `sc_pred_meta_t` on
  first use. Its `sc_upd_idx` and `sc_upd_ctr` fields had an unpacked
  dimension inside a packed struct, and were converted to packed
  two-dimensional arrays.
- **TAGE elaboration.** Retiring the merged structs removed `cond_pred_meta_t`
  and `cond_pred_upd_inp_t`, and the confidence field `tage_high_conf` was
  removed from `tage_pred_meta_t`. `tage.sv` and `tage_cntrl.sv` still used
  all three, and from that point the six TAGE targets did not elaborate.

The TAGE break went unrepaired through four tasks. The session-058 tasks ran
only their own targets. BP-075 recorded that it had not run the full
regression. BP-078 ran every target in the unit, reported the six TAGE
failures as pre-existing and outside its scope, and showed with `git diff`
that it had not touched TAGE or the packages. BP-079 then waived those six
targets by name, so the task did not try to repair them.

### Investigating before fixing

BP-080 was written as a gated task. Phase 1 would locate every reference and
propose a fix, with no file edits. Phase 2 would apply the fix only on
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
Generating them is TD #87 and TD #88. The BP-080 manifest listed a file that
no longer exists and placed another under the wrong directory. I corrected
both by hand before the run.

## What the testbenches establish

The index checks in `tb_sc_table` and `tb_sc_brimli` compute the expected
index in the testbench with the same expression as the RTL, as both tasks
state. `tb_sc` transcribes the hash rules into its own reference functions.
These checks confirm that the index is wired and that the RTL matches its own
transcription of `sc_table_hash_rules.md`. They do not check the RTL against
that document independently, although the document defines the rule
completely enough to do so.

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
beyond its prompt. The task was written against the RTL of the lower modules,
and the IA reconciled every control-layer port in `sc_cntrl` to a port on
`sc_table` or `sc_brimli`. The IA found the mismatch between the 9-bit table
indices and the 10-bit control-layer index buses, and resolved it from the
package parameters rather than by assumption. The IA also confirmed from the
package that the counter widths needed no adapter. BP-078 added one lint
suppression beyond the one its constraints allowed, and the IA flagged that
suppression with its reason. The `tb_sc` testbench read the reset values of
`br_imli` and `threshold` by hierarchical reference, and checked those values
before any test relied on them.

BP-078 also ran the full unit regression, found the TAGE break, reported it
as pre-existing, and did not attempt to repair files outside its scope. BP-080
then corrected its own task's hypothesis in the Phase 1 report, which is the
result that changed the fix.

BP-077 wrote its dual-slot assumption into the module header without being
asked for a rule. Because it was written down, the review found it.

### The PA contribution

The planning assistant checked the SC's rules against the published sources
and the simulator code, and those checks set the update gate, the threshold
seed and maximum, and the TC width. It found the counter-capture defect by
reading the draft's widths against the struct. It rewrote the arbitration
specification to the standalone model, wrote the four session-058 planning
documents, and wrote the seven task files.

The assistant also made four errors:

- On the update gate, it first stated a different rule from recall, then
  accepted the task-text rule, before it pulled any source. The source matched
  neither.
- In session 059 it wrote a rationale into `sc_decisions.md` and into BP-079
  claiming that the mode parameter's default could not be placed in
  `bp_defines_pkg` because of package import order. That constraint does not
  exist, and the paragraph was removed from both files.
- It wrote BP-078 to add `br_imli_mode` as a port rather than raising the
  port-versus-parameter question, which is why BP-079 was needed.
- It built the BP-080 manifest without checking each path against the tree.

The assistant did not compile the package edits it made or reviewed during
planning, and nothing in the process required it to.

### My contribution

I wrote the first draft of `sc_decisions.md`, including the two-corner
chooser, the BrIMLI variants and the reset initialization. I bounded the SC
configurations to three and added the run-time enable. I removed the PC field
from the prediction metadata and moved the branch region and direction sign
into FTB storage, TD #89 and TD #90. I set the module decomposition,
authorized BP-077 to derive the control-layer port list, and made the BrIMLI
mode a compile-time parameter.

The task text that gated training on the TAGE misprediction was mine.

I stopped BP-080 after Phase 1 and set the tie-off policy for the TAGE
reconciliation. I corrected the BP-080 manifest before it ran.

### The generalization

The specification sessions checked the SC's rules and parameters against their
sources, and the unit built from them passed every task on its first run. The
same sessions edited two compiled package files without compiling them, and
all three problems in the package section came from those edits.

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
BP-080, which restores the TAGE targets. That task, BP-081, is the subject of
the next article.

The remaining SC dependencies are on other units and gate cluster
integration, not the SC unit: TAGE outputs (TD #87, TD #88), FTB storage
(TD #89, TD #90), PC and path history routing to p2 (TD #91, TD #92), the
update queue and arbiter, flush behavior (TD #96), and the end-to-end fold
check (TD #84).

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
| 94 | bp_arb_spec reconciliation to the standalone SC. | Section 6 rewritten session-057. The retired cond_pred_meta_t / cond_pred_upd_inp_t types are still the element types of two live tage.sv FIFOs; BP-080 scoped the fix as a retype to tage_upd_inp_t / tage_pred_meta_t. Open.[F3] |
| 95 | tage_pred_meta_t changed; TAGE references to reconcile. | tage_high_conf was removed from the struct and is dead in tage_cntrl.sv (BP-080). Delete it and tie the ungenerated SC-facing fields to zero. Open.[F3] |
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

[F3] TD #94 and TD #95 were later closed by BP-081, the TAGE struct
reconciliation covered in the next article.
<!-- ticfinder_on -->

---
<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry experience
spanning performance modeling, RTL implementation, and architecture for
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,
TI C6x and RISC-V designs, and recently served as sole architect and full-stack
implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue
RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He
holds +20 issued patents in processor design, architecture, and hardware
virtualization. He is the author of Pacino and the uarchlabs methodology
documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
