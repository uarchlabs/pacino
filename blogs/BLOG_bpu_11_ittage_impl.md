<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Blog Article — RVA23 Co-Design

```
TITLE: "ITTAGE -- Table, Controller, Wrapper, and First Integrated Testbench"
AUTHOR: Jeff Nye
DATE: 2026-05-19
STATUS: DRAFT
COPYRIGHT: "Copyright 2026 Jeff Nye"
DESCRIPTION: "ITTAGE RTL implementation across RVA23 Co-Design sessions 37-42:
ittage_table.sv and ittage_cntrl.sv from a discarded first attempt to a clean
implementation, the ittage.sv wrapper and arbitration layer, a response
buffer built by pattern-copy and later traced and removed as dead logic, and
a first integrated testbench that found four DUT bugs neither module's
standalone testbench had caught."
```

---

*This is one of a series of articles on the branch predictor
co-design.*

[Part 1: Cluster Architecture](BLOG_bpu_1_cluster_arch.md)<br>
[Part 2: History and uBTB](BLOG_bpu_2_history_ubtb.md)<br>
[Part 3: Loop Predictor](BLOG_bpu_3_loop_pred.md)<br>
[Part 4: When the Tools Fail](BLOG_bpu_4_limits.md)<br>
[Part 5: TAGE -- Architecture and the Decomposition Problem](BLOG_bpu_5_tage_arch.md)<br>
[Part 6: TAGE -- Implementation](BLOG_bpu_6_tage_impl.md)<br>
[Part 7: TAGE -- Validation](BLOG_bpu_7_tage_validation.md)<br>
[Part 8: TAGE -- Arbitration and Integration](BLOG_bpu_8_tage_arbitration.md)<br>
[Part 9: TAGE -- Coverage Methodology and Closure](BLOG_bpu_9_tage_coverage.md)<br>
[Part 10: ITTAGE -- Design and Planning Documents](BLOG_bpu_10_ittage_planning.md)

---

## Abstract

The previous post closed with the ITTAGE planning document set
complete but not yet reconciled, and `ittage_table_interfaces.md`
still a hard blocker for RTL. This post covers six sessions that
closed that blocker, wrote `ittage_table.sv` and `ittage_cntrl.sv`,
assembled them into `ittage.sv` with a full arbitration layer, and
produced the first passing integrated testbench. A response buffer
added by copying the TAGE arbitration pattern was later traced and
confirmed dead logic, since ITTAGE and SC are mutually exclusive
consumers, and removed. The first integrated testbench found four
DUT bugs that neither module's standalone testbench had caught. The
post ends with ITTAGE unit-and-integration tested at 35/35 checks
and five new technical debt items opened for the next cleanup pass.

---

## Opening

Before ITTAGE RTL work resumed, two closeout items ran that are not
part of this post's main thread. A TAGE-side audit (BP-031, BP-032)
cross-checked the USE and UAON update-rules documents against the
actual `tage_cntrl.sv` RTL and found one real defect: the module was
storing the raw `USEFUL` field in prediction metadata instead of the
aged `u_eff` value. Two assignments were fixed; 68/68 regression
passed. The UAON audit found no discrepancies. Separately, a
redundancy-collapse pass across all eight ITTAGE planning documents
ran, and an unplanned second piece of work rode along with it: a
size reduction of `PROJECT_STATUS.md` that split it into three
files. Neither item is ITTAGE implementation work, and neither gets
its own section below. Both are noted here because the debt numbers
they opened and closed — [TD# 43](#td-43-part37),
[TD# 44](#td-44-part37), and [TD# 45](#td-45-part37) — get reused
for unrelated ITTAGE items later in this same range, which the
Technical Debt Referenced section addresses directly.

With the planning set collapsed and reconciled, RTL work began at
`ittage_table.sv` and closed, six sessions later, with a passing
integrated testbench for `ittage.sv`.

---

## ittage_table.sv and ittage_cntrl.sv: Discipline Learned the Hard Way

The first attempt at `ittage_table.sv` (BP-033) passed simulation
at 24/24 checks and lint-clean, and was abandoned anyway. Review
found that `ittage_pred_val_p0[s]`, a p0-stage signal, was gating
`hit_p1[s]`, a p1-stage output — a pipeline-stage violation. The
testbench had not caught it because the prompt did not specify
expected values; Claude Code wrote tests that matched the RTL it
had just written, not the specification the RTL was supposed to
implement.

BP-033-FIX-1 re-ran with two changes to the prompt: a binding
decision requiring `hit_p1[s]` to be derived solely from `ram_dout`
and `tag_hash_p1`, copied verbatim from `tage_table.sv`'s pattern,
and a Test Vector Table with every expected value computed from
spec before any code was written. A specific test, TC-PRED-VAL-ZERO
— valid entry loaded, predict with `pred_val=0`, expect `hit_p1=1`
— was added to target the exact defect BP-033 had shipped. The
result was 32/32 checks, lint-clean, in 41 minutes at 83% context
with compaction. Pre-computed expected values in the prompt, and
splitting implementation and testbench into separate prompts to
reduce context pressure and correlated-bug risk, became standing
requirements for every ITTAGE testbench prompt written afterward.

`ittage_cntrl.sv` took one abandoned attempt and three completed
ones. BP-034a was abandoned outright: the planning-document context
required to write the prompt ran close to 4,000 lines of markdown,
the PA session was repeatedly mishandling formatting and file
paths, and Jeff restarted with a fresh PA session rather than
continue debugging the one in progress. BP-034 then implemented the
prediction path — provider scan, alternate-provider scan, allocation
candidate selection, the UAON mux, `ittage_pred_meta_t` assembly —
with the update path fully stubbed to zero. BP-035 added the update
path: CTR, USE, EPC, and TGT updates, allocation write-data assembly,
UAON counter update, and the `u_eff` aging computation that replaces
raw USE in the prediction path.

BP-035 also introduced a defect that BP-036 later found and named
precisely: `prm_tbl_sel_u0` and `alt_tbl_sel_u0`, the update-path
table selectors, were driven from live prediction-scan intermediates
— placeholders left over from when the update path was still
stubbed — rather than from the predict-time metadata captured into
the FTQ and returned at update time. The project's own
meta-at-predict / consume-at-update pattern requires the latter;
BP-034's stub-era placeholder violated it and survived into BP-035
uncorrected. BP-036's testbench caught it, along with two Verilator
scheduling defects: a `prv_alt_scan always_comb` block that read
only module inputs and was therefore classified `stl_sequent` by
Verilator — evaluated once at simulation start and never again —
fixed by gating the block on a flopped input to force `nba_sequent`
classification; and a `meta_p1` intermediate wire that caused a
scheduling inversion, fixed by removing the wire and having
`meta_p2_reg` read the scan outputs directly. The `stl_sequent`
finding was written up as a standing CLAUDE.md rule: any
`always_comb` block that must re-evaluate after a flop update has to
read at least one flop output, not module inputs alone. BP-036
closed at 76 PASS, 0 FAIL.

---

## ittage.sv: Wrapper, Arbitration, and a Response Buffer That Didn't Need to Exist

`ittage.sv` instantiates `ittage_cntrl` and five `ittage_table`
instances (IT1-IT5) with per-table parameter assignments. The first
attempt, BP-037, got the module structurally correct and lint-clean
but instantiated `sram_init` once per table — five instances instead
of one shared instance at the module top level. BP-037a fixed the
instance count; the fix itself removed the `fast_init` strapping mux
that zeroed `tbl_ri_wr`, `tbl_ri_wa`, and `tbl_ri_wd` during
fast-init, which BP-037b then had to restore. Three fix-prompt
discipline rules came directly out of this two-pass cycle: a fix
prompt must state the required end state in full rather than a delta
("restore X" is not actionable to a tool with no memory of the prior
session), must state explicitly what must *not* change with the
exact working behavior reproduced rather than referenced, and any
prompt instantiating `sram_init` must state the required instance
count explicitly rather than deferring to a planning document.

BP-038 added the arbitration layer — PQ, UQ, credit arbiter,
competing-stage mux, and a prediction response buffer — by following
the `tage.sv` arbitration pattern with `ITTAGE_`-prefixed parameters.
The response buffer was included because `tage.sv`'s pattern has one,
built to support a downstream SC consumer that can apply backpressure.
`consumer_ready` was hardwired to `1'b1` internally rather than
exposed as a port, which put the buffer permanently in bypass mode
without anyone yet confirming it needed to exist at all. BP-038a
closed a related item, adding a `trx_type` input port to
`ittage_cntrl.sv` so write enables could be gated correctly by
transaction type.

The next session traced the response buffer's actual necessity and
found it had none. ITTAGE predicts targets for indirect branches
only; SC operates on conditional branches only. The two are mutually
exclusive branch classes, so there is no ITTAGE-to-SC chaining for a
response buffer to arbitrate. [TD# 48](#td-48) was closed by removing
it: BP-038b deleted the RB memories, its `always_ff` and
`always_comb` blocks, and replaced the buffered output path with
direct assigns from `ittage_cntrl`'s prediction-ready and metadata
outputs, simplifying the arbiter's Rules 3 and 5 by dropping their
`resp_buf_full_w` guards. Six active arbitration rules remained.
Lint passed clean on the first attempt.

---

## tb_ittage.sv: What Unit-Clean Modules Still Hid

BP-039 wrote the first testbench exercising `ittage.sv` with real
`ittage_table` instances wired in, using the FAST_INIT and
round-trip-hit methodology established in BP-033-FIX-1. Thirteen
test cases, 35 checks, all passing, zero warnings — and four DUT
bugs found and fixed along the way, none of which either module's
standalone testbench (32/32 for the table, 76/76 for the controller)
had surfaced.

Two of the four were specific to wiring real tables into the
controller and could not have been exercised by a controller-only
testbench: `ittage_table.sv`'s `addr_mux`/`din_mux` used
`tbl_ri_active` as their top-priority guard, and with `FAST_INIT=1`,
`sram_init`'s `active` signal stays high for the full 512-cycle init
sequence regardless of the fast-init flag — forcing the write
address and data muxes to zero and silently dropping every
allocation write during that window. The fix changed the guard from
`tbl_ri_active` to `ri_we` (`tbl_ri_active & tbl_ri_wr`), so with
fast-init active and `tbl_ri_wr=0`, the normal write path is used.
The same session opened [TD# 50](#td-50) to check whether
`tage_table.sv` has the same latent pattern. Separately,
`ittage_cntrl.sv`'s `alc_index_u0` was computed from the prediction's
provider index — zero for any no-hit prediction — instead of from
`ittage_pred_meta.ittage_alc_idx`, the actual allocation index
carried in the prediction metadata; a round-trip allocate-then-hit
test is the only kind of test that exposes this, since it requires
an entry that was actually allocated to actually be found again.

The other two were within a controller-only testbench's reach but
were not caught by BP-036's 76 checks. `branch_id` was read directly
from `pred_inp_p0` at the `meta_p2_reg` stage, one cycle after the
testbench had already deasserted the input — fixed by adding a
`branch_id_p1` register that captures the value at the correct
pipeline stage. And the `ctr_upd` block's `using_primary` branches
were inverted: `using_primary=1` was updating the alternate
provider's counter and `using_primary=0` was updating the primary's,
backward from the ITTAGE algorithm's requirement that the provider
actually used gets its own counter updated. The branches were
swapped. Because this defect sat in the same class of logic as three
other update rules (USE, TGT, and allocation write data) that
BP-036's suite had not independently exercised, [TD# 51](#td-51) was
opened: a systematic audit, one round-trip test per rule row in
`ittage_cntrl_ctr_update_rules.md` and
`ittage_cntrl_use_update_rules.md`, independent of the existing test
set.

One planned test, TC-ARB-07, is marked N/A rather than PASS or
FAIL — it tested response-buffer behavior that BP-038b had already
removed by the time BP-039 ran.

---

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| BP-031 | TAGE debt #44: USE update rules audited against RTL, one defect fixed | PASS | 68/68 | 5m 44s | 39% |
| BP-032 | TAGE debt #45: UAON update rules audited against RTL, no changes | PASS | 68/68 | 3m 53s | 37% |
| BP-033 | ittage_table.sv, first attempt -- p0/p1 gating defect | ABANDONED | 24/24 | 40m 23s | 24% |
| BP-033-FIX-1 | ittage_table.sv, corrected re-implementation | PASS | 32/32 | 41m 33s | 83% + compaction |
| BP-034a | ittage_cntrl.sv prediction path, first attempt | ABANDONED | -- | -- | -- |
| BP-034 | ittage_cntrl.sv prediction path | PASS | lint only | 18m 48s | 80% |
| BP-035 | ittage_cntrl.sv update path | PASS | lint only | 24m 52s | 75% |
| BP-036 | ittage_cntrl.sv testbench, three RTL defects found and fixed | PASS | 76/76 | 1h 35m 59s | 30% + compaction |
| BP-037 | ittage.sv structural wrapper | PASS | lint only | 27m 12s | 70% |
| BP-037a | sram_init instance-count fix | PASS | lint only | 5m 47s | 32% |
| BP-037b | fast_init strapping restore | PASS | lint only | 6m 18s | 26% |
| BP-038 | ittage.sv arbitration layer added, including response buffer | PASS | lint only | 10m 42s | 79% |
| BP-038a | trx_type gating added to ittage_cntrl.sv | PASS | lint only | 5m 11s | 37% |
| BP-038b | Response buffer removed, confirmed dead logic | PASS | lint only | 3m 1s | 25% |
| BP-039 | tb_ittage.sv, four DUT bugs found and fixed | PASS | 35/35 | 1h 43m | 42% + 2 compactions |

---

## What Comes Next

Five technical debt items are open at the close of this range:
[TD# 43](#td-43-current) and [TD# 44](#td-44-current) (both requiring
`ittage_cntrl_decisions.md` corrections), [TD# 45](#td-45-current)
(TAGE T0 index handling), [TD# 50](#td-50) (the FAST_INIT `sram_init`
pattern, and whether `tage_table.sv` shares it), and
[TD# 51](#td-51) (the systematic CTR/USE/TGT update-rule audit).
[TD# 46](#td-46) also needs attention: it was marked closed after
BP-038a and reopened when `tb_ittage_cntrl.sv` was found still
missing the `trx_type` port that closure depended on, so
`sim_ittage_cntrl` currently fails with a PINMISSING error. None of
these block further ITTAGE work, but the update-rule audit in
particular should run before the next module in the ITTAGE thread
begins, since it was opened specifically because one inverted
condition was found by accident rather than by systematic coverage.

---

## Technical Debt Referenced

[TD# 43](#td-43-part37), [TD# 44](#td-44-part37), and
[TD# 45](#td-45-part37) were opened in session-036 and closed in
session-037, over TAGE-side documentation and RTL-audit work
unrelated to this post's main thread (see Opening, above). All three
numbers were subsequently reused for unrelated ITTAGE items, opened
during session-040's `ittage_cntrl.sv` work and still open at the
close of this range. Both versions are quoted directly from
`session_handoff-038.md` (closing text) and `session_handoff-041.md`
/ `session_handoff-043.md` (current, reused text) — not
reconstructed.

<a id="td-43-part37"></a>

| # | Item (as of Part 37, closed) | Resolution path (as of Part 37) |
|---|---|---|
| 43 | tage_cntrl_use_update_rules.md needs a background paragraph explaining the USE field's purpose in tage table entries. | Add background section before the aging section: field width, eviction-protection role, epoch-decay interaction, update-trigger condition. Closed session-037. |
| 44 | Claude Code to verify USE update rules against current tage_cntrl.sv RTL. | Run BP-031. Closed session-037: one mismatch found (raw USEFUL vs u_eff in prediction metadata) and fixed. |
| 45 | Claude Code to verify UAON update rules against current tage_cntrl.sv RTL. | Run BP-032. Closed session-037: no discrepancies found. |

<a id="td-43-current"></a>

| # | Item (current, session-043) | Resolution path (current) |
|---|---|---|
| 43 | ittage_pred_strong definition in ittage_cntrl_decisions.md is incorrect. Needs update to CTR > 0 (not NULL). | Deferred. Correct ittage_cntrl_decisions.md when scheduled. |
| 44 | ittage_cntrl_decisions.md decoration flags section needs correction once TD #43 above is implemented. | Deferred, dependent on TD #43. |
| 45 | TAGE T0 index handling needs revisit. Recorded during upd_index_u0 discussion in session-040. | Deferred. |

<a id="td-46"></a>

| # | Item (current, session-043) | Resolution path (current) |
|---|---|---|
| 46 | tb_ittage_cntrl.sv is missing the trx_type port added to ittage_cntrl.sv in BP-038a. sim_ittage_cntrl fails with a PINMISSING error. Previously marked closed in error. | Reopened. Fix before the next integration session. |

<a id="td-48"></a>

| # | Item (current, session-043) | Resolution path (current) |
|---|---|---|
| 48 | ittage.sv response buffer bypass behavior with consumer_ready hardwired to 1'b1 needed verification against bp_cluster backpressure expectations. | Closed. RB confirmed dead logic -- ITTAGE and SC are mutually exclusive consumer classes (indirect vs. conditional branches) -- and removed in BP-038b. |

<a id="td-50"></a>

| # | Item (current, session-043) | Resolution path (current) |
|---|---|---|
| 50 | sram_init runs its full initialization sequence even when FAST_INIT=1; its active signal stays high for 512 cycles, overriding ittage_table.sv's write-mux paths during that window (BP-039 Bug 3). When FAST_INIT=1, sram_init should not run its init sequence and active should not assert. | Open. Scope: sram_init.sv, ittage_table.sv. Audit tage_table.sv for the same pattern. |

<a id="td-51"></a>

| # | Item (current, session-043) | Resolution path (current) |
|---|---|---|
| 51 | BP-039 found using_primary inverted in ittage_cntrl.sv's ctr_upd block. Systematic risk that other update-logic blocks (USE, TGT, allocation) may have similar errors not yet exercised by the existing test set. | Open. New round-trip test set required, one test per rule row in ittage_cntrl_ctr_update_rules.md and ittage_cntrl_use_update_rules.md, independent of TC-P01 through TC-UAON-01. |

---

## Design Process Notes

### What the sessions exposed about the methodology

Two distinct kinds of testbench failure appear in this range, and
they call for different fixes. The first is a testbench with no
independent power to catch a defect at all: BP-033's testbench wrote
its expected values from the RTL under test, so it could only ever
agree with whatever the RTL happened to do. The fix that followed —
pre-computed expected values fixed in the prompt before any code is
written — closed this failure mode completely for the rest of the
range; no later session repeats it.

The second kind is narrower and did not fully close. BP-039 found
four defects that BP-036's 76-check, unit-level `ittage_cntrl.sv`
testbench had not caught. Two of the four — the FAST_INIT/`sram_init`
write-mux override and the allocation-index source error — involve
real `ittage_table` instances wired into the controller and could
not have been exercised by a controller-only testbench regardless of
how thorough its test set was. The other two — the `branch_id`
pipeline-timing error and the inverted `using_primary` condition —
sit entirely within `ittage_cntrl.sv` and were, in principle,
reachable by a controller-only test. Whether extending BP-036's test
set would have caught them was not investigated in this range; TD#
51 opens that question as a systematic audit rather than assuming an
answer.

The BP-037/BP-037a/BP-037b sequence is a fix-prompt discipline
failure, not a design failure: the underlying wrapper structure was
correct from BP-037 onward, but two rounds of fix prompts were needed
because a fix prompt specifying a delta from an unstated prior state
does not tell a tool with no session memory what the required end
state actually is. The three rules recorded in that section were
written directly against this failure, not as anticipatory guidance.

### What the PA contributed

The PA identified the BP-033 p0/p1 gating defect on review before it
reached a second session, and designed the pre-computed
Test-Vector-Table fix that prevented the same class of defect from
recurring anywhere else in the range. It made the call to trace and
remove the response buffer once the ITTAGE/SC consumer relationship
was examined directly, rather than carrying it forward as
unverified. It also converted three fix-prompt failures into
standing prompt-writing rules, and scoped and split all fourteen
prompts in this range, including the decision to abandon BP-034a
outright rather than continue debugging a degraded PA session.

### What the IA contributed

The IA's BP-036 and BP-039 testbenches found and root-caused six RTL
defects between them autonomously, with file-and-line-level fixes
applied and verified against the regression suite in the same
session — the `stl_sequent`/`nba_sequent` scheduling diagnosis in
BP-036 in particular required tracing Verilator's block-classification
behavior, not just re-running a failing test. The BP-037a and
BP-037b fix passes were each single-attempt, lint-clean, no-iteration
results once the prompt stated the required end state explicitly.

### The generalization

Across this range, test discipline established early prevented one
entire class of defect from recurring — no session after BP-033-FIX-1
shipped a testbench that derived its own expected values from the RTL
it was testing. That discipline did not, on its own, guarantee
coverage at every module boundary: BP-039's four defects surfaced
only once `ittage_table.sv` and `ittage_cntrl.sv` were assembled into
`ittage.sv` and driven through arbitration, a configuration neither
module's standalone testbench exercised. This is consistent with
BLOG_bpu_9's finding that a testing method surfaces exactly the class
of problem it is built to catch and no other — a coverage tool found
gaps that passing tests had hidden; here, a controller-only testbench
could not have found defects that require a real table wired in,
regardless of how well-disciplined its own expected-value methodology
was. The response buffer follows the same shape from a different
angle: it was built by copying a working pattern from `tage.sv`
without first confirming the pattern's precondition — a downstream
consumer requiring backpressure — held for ITTAGE at all.

---

*No references required for this post.*

