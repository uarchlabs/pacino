<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
---

```
TITLE: "TAGE -- Coverage Methodology and Closure"
AUTHOR: Jeff Nye
DATE: 2026-05-01
STATUS: REVIEW BEFORE POSTING
COPYRIGHT: "Copyright 2026 Jeff Nye"
DESCRIPTION: "Building a Verilator coverage pipeline and applying it to close
TAGE's outstanding functional coverage gaps: sessions 29 through 32, covering
INFRA-001 through INFRA-006 and BP-023c through BP-030. Ends with the decision
to move on to ITTAGE." 
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

---

## Abstract

TAGE's arbitration testbench was incomplete, and no coverage
tooling existed to verify functional coverage before
bp_cluster integration. This post covers building a
Verilator coverage pipeline from nothing (INFRA-001 through
INFRA-006), closing the arbitration testbench (BP-023c), and
diagnosing and closing coverage gaps across seven sessions
(BP-024 through BP-030). Every outstanding coverage item
reached a passing test, a documented tool-artifact
conditional pass, or an explicitly deferred status. The post
ends with the decision to move on to ITTAGE.

---

## Closing the Arbitration Testbench and Opening Coverage

The previous post ended with BP-023c open: the arbitration
testbench work needed to validate the PQ/UQ credit arbiter
before TAGE could be considered ready for bp_cluster
integration. It also ended with [TD# 35](#td-35) superseded -- a
blunt test-count-comparison script rejected in favor of a
proper coverage matrix, coverage tracking, and RTL code
coverage from Verilator, none of which had been built yet.

This post covers four sessions that closed both threads.
BP-023c ran first, closing [TD# 37](#td-37) and exercising the
arbiter's FIFO storage path for the first time. The
remaining three sessions built a Verilator coverage
pipeline from nothing -- directory restructure, Makefile
targets, HTML reporting, gap-analysis tooling -- and used
it to drive TAGE's line coverage from roughly 70% to
complete or explicitly deferred on every outstanding item.
The post ends where the range ends: a decision to stop
refining TAGE coverage and start ITTAGE.

---

## Infrastructure: Building the Coverage Pipeline

Before Part 29, [TD# 35](#td-35)'s replacement had no tooling behind
it: no coverage matrix, no coverage tracking, and no RTL
code coverage from Verilator. INFRA-001 through INFRA-006
built that tooling, alongside a repository restructure
needed independently of the coverage work.

INFRA-001 verified the repository against three prior
directory renames and introduced the `RVA_ROOT` environment
variable. Four files carrying stale paths were corrected;
all 20 lint and sim targets passed with zero warnings. A
follow-on README update and a path fix in `handoff.sh`
(INFRA-002) were done manually rather than as a Claude Code
session.

INFRA-003 added per-module `cov_*` Makefile targets and a
`cov_bpu` merge target, working around a Verilator 5.020
limitation -- no runtime coverage file path argument -- with
a two-pass compile. This was tracked as [TD# 38](#td-38-part29) at the time
(reconstructed text in Technical Debt Referenced, below --
the live entry has since drifted to a different concern),
pinning the Verilator version until resolved. INFRA-004
fixed a `genhtml` misconfiguration that was writing
annotated HTML into the source tree instead of the
`coverage/` directory.

INFRA-005 and INFRA-006 established a gap-analysis format:
annotate existing coverage data, then map each uncovered
region to a row in the coverage plan. INFRA-005 found 13
gap regions and three direct conflicts against rows the
plan already marked covered. INFRA-006, scoped to
`tage_table.sv`, found the CU-11 conflict was wider than
first diagnosed: the `addr_mux` body containing
`norm_we_s1` showed zero executions, meaning the slot 1
write path had never been entered by any test, not merely
under-exercised.

---

## Closing the Arbitration Testbench

BP-023c completed the item BLOG_bpu_8 left open, adding the
eight-test arbitration suite defined in `bp_arb_spec.md`
section 10.1 and growing the test count from 46 to 54.
Before those tests could run, `consumer_ready` -- tied off
internally to `1'b1` since BP-023b, deferred pending SC
integration -- was promoted to an input port on `tage.sv`,
with `tb_tage.sv` wired to drive it high by default so the
existing 46 tests were unaffected.

[TD# 37](#td-37), open since BP-023b, was closed in this session. The
concern had been that `arb_grant_upd` -- used
combinationally to gate write enables in `tage_cntrl`
rather than through its registered pipeline copy -- could
glitch if the grant signal changed while `tage_cntrl` was
mid-pipeline. TB-ARB-03 (concurrent prediction and update
to different entries) and TB-ARB-04 (concurrent
prediction and update to the same entry) both passed
without a write-enable glitch, closing the debt with
evidence rather than closing it by inspection.

This session also exercised the arbiter's FIFO storage
path for the first time. All 46 prior tests had taken the
bypass path -- queue empty, request granted immediately --
leaving the head/tail pointer logic and credit registers
structurally present but untested since BP-023b. TB-ARB-06
through TB-ARB-08 filled that gap, and surfaced two spec
discrepancies rather than RTL defects: [TD# 39](#td-39), TB-ARB-08's
starvation-override rule untestable at the current parameter
values (`PRED_CREDITS=4` is below `STARVE_THRESH=8`, so the
credit-exhaustion rule becomes the effective ceiling before
starvation can occur), and [TD# 40](#td-40), a mismatch between the
arbitration spec's description of TB-ARB-05 backpressure
behavior and the RTL's actual `TAGE_UQ_DEPTH=8`.

---

## Diagnosing and Closing Coverage Gaps

BP-024 through BP-030 form one continuous diagnostic and
closure thread against the gaps INFRA-005 and INFRA-006
identified. The thread includes two findings worth stating
plainly: a session that hit the limit of static analysis
and left a contradiction unresolved, and a coverage-closure
session that missed its own target because the tests
landed in the wrong file.

BP-024 investigated why the TAGE allocation path had never
fired end-to-end despite every table entry being
initialized with `USEFUL=0`. The root cause was a compound
gate in `alc_upd_comb` (`tage_cntrl.sv` line 816) requiring
`u_alc_comp[s] != '0`. Every synthetic-metadata update test
written up to that point had left `tage_alc_comp` at its
structural default of zero, making the gate condition false
regardless of the USEFUL state the test intended to
exercise. TC-42 and TC-43, already present in the
testbench, were confirmed structurally correct against this
root cause; the session made no RTL changes and instead
identified that CU-07 had been marked covered at test-authoring
time without a confirming coverage run.

BP-025 diagnosed a related but distinct gap: `norm_we_s1`
in `tage_table.sv`, never asserted in any test according to
INFRA-006. Two candidate causes were investigated in
parallel -- incorrect testbench wiring of
`tage_upd_val_u0[1]`, or table-selector routing sending slot
1 updates to a `tage_table` instance that never matches.
Static trace confirmed the second cause for TB-ARB-05: that
test drives `tage_prm_comp = 0` for both slots, routing the
update to `tage_bim` (T0), and no `tage_table` instance has
`THIS_TABLE = 0`, so every write-enable term is
structurally zero for the duration of the test. For TC-23,
the same trace produced the opposite conclusion: every
signal condition required for `norm_we_s1` to assert traces
correctly, and static analysis predicts the signal fires.
That prediction directly contradicts INFRA-006's measured
zero-execution finding for the same test, and the session
stated this as an open contradiction rather than resolving
it -- closing with an explicit statement that the
discrepancy "cannot be fully resolved from static analysis
alone" and requires waveform capture, which was not run in
this range.

This session also surfaced a process deviation. The BP-025
prompt specified console output only, with no file writes
-- in conflict with the project's standing convention that
Claude Code writes its Results Capture section directly
into the experiment file. Neither the PA nor Jeff caught
this before the session ran; the console output was pasted
back into the file manually afterward. The session's own
assessment recorded the deviation directly rather than
omitting it.

BP-026 attempted closure of six gap clusters at once --
CU-11, CP-10, CE-09, CE-10, CE-11, and the slot 1 write
path -- adding TC-55 through TC-60 to `tb_tage.sv`. All 60
resulting tests passed, but the session's own stated 90%+
coverage target for `tage_table.sv` was not met: the added
tests were written against `tb_tage.sv`, while the
`cov_tage_table` Makefile target measures coverage through
`tb_tage_table.sv`. Coverage on the correct target moved
from roughly 76% to 78%, a one-testbench-file mismatch, not
a design defect. BP-027 corrected this in the next session
by adding equivalent tests -- TC-14 through TC-16 -- directly
to `tb_tage_table.sv`, reaching 154 of 171 lines, 90.1%,
against the stated target. Seventeen lines remained
uncovered: sixteen in the `fh_sel` arms for T2 and T3
(deferred to BP-028), and one flagged as a Verilator
instrumentation artifact on a fast-init conditional whose
body was otherwise fully covered.

BP-028 closed the `fh_sel` T2/T3 gap, but not by extending
`tb_tage_table.sv` as BP-027's own deferred-work note had
suggested. Verilator's `--coverage-line` does not sum
coverage across multiple parameterized specializations of
the same source file within a single run, so a unit-level
fix would have required a separate compile per table
instance. Instead, TC-61 and TC-62 were added to
`tb_tage.sv`, driving predictions through the T2 and T3
instances at the integration level via `cov_bpu`. Per-instance
raw coverage counts confirm both arms execute (`pi2=1`,
`pi3=1`), but `verilator_coverage --annotate` reports zero
for the same lines, because the annotation tool displays the
count from the highest-indexed instance sharing that source
line -- here, the T4 instance, which does not execute the T2
or T3 arms. The result is recorded as a conditional pass:
functionally covered, with the annotation tool's own
zero-count output documented as a known artifact rather than
a real gap.

BP-029 and BP-030 closed the remaining boundary-condition
items, CE-01 through CE-06, without further complication.
BP-029 added TC-63 through TC-66 for saturating arithmetic
at the CTR and USE field boundaries; in the process it
found that the prompt's background assumption -- that
saturation logic lived in a `sat_alu` instance inside
`bw_ram` or `tage_table` -- was wrong. The arithmetic is
inline in `tage_cntrl.sv` as ternary expressions, and the
session adapted to the actual RTL rather than writing
tests against the assumed structure. BP-030 added TC-67
and TC-68 for the no-allocation-candidate sentinel and the
no-RAM-write update path, bringing the test count to 68.
One residual gap remained after BP-030: four lines in the
allocation scan body, inside an `always_comb` block nested
in a `generate` loop, report a raw count of zero under
Verilator's line coverage. TC-60 already verifies the code
executes correctly through its functional result; the zero
count was documented as a pre-existing Verilator
instrumentation limitation on this specific RTL construct,
not introduced by BP-030 and not indicative of an
unexercised path.

---

## The Stop Decision

At the close of Part 32, every item opened by INFRA-005 and
INFRA-006 was either closed with a passing test, closed as
a conditional pass with a documented tool artifact, or
explicitly deferred with a stated reason: CU-08 and CU-09
(aging-path rows the coverage plan had marked covered
without a confirming test that ever drove
`tage_enable_aging` high), CE-07 and CE-08 (deferred at
Jeff's direction), CA-08 (starvation override, blocked by
the same parameter relationship as [TD# 39](#td-39)), and the
`-Wno-PINMISSING` suppression on `pq_not_full` and
`upd_rdy[1:0]`, which remains until those signals are
connected as testbench ports in a future session.

Against that state, the question was whether to continue
refining TAGE coverage or move to the three remaining BPU
predictors -- FTB, ITTAGE, and SC. The decision was to move
on. ITTAGE was chosen as the next component specifically
because it shares TAGE's table architecture, and BP-029 and
BP-030 were noted directly as reference material for
ITTAGE's own verification work.

---

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|------------|--------------------------------------------|--------|--------|-----------|------------------|
| INFRA-001  | Directory restructure, RVA_ROOT wired       | PASS   | 20/20  | 10m 0s    | 50%              |
| INFRA-002  | README/handoff.sh path fixes (manual)       | --     | --     | n/a       | n/a              |
| INFRA-003  | Coverage Makefile targets, HTML reporting   | PASS   | --     | 25m 44s   | 69%              |
| INFRA-004  | genhtml --prefix fix                        | PASS   | --     | 4m 26s    | 23%              |
| INFRA-005  | Coverage gap analysis, 13 regions           | --     | --     | 11m 44s   | 60%              |
| INFRA-006  | Targeted gap analysis, tage_table, 18 regions | --   | --     | 7m 2s     | 34%              |
| BP-023c    | Arbitration testbench TB-ARB-01--08         | PASS   | 54/54  | 52m 36s   | +14% compacted   |
| BP-024     | Allocation root cause (no RTL change)       | --     | --     | 25m 3s    | 21%              |
| BP-025     | norm_we_s1 root cause (partial, deferred)   | --     | --     | 14m 10s   | 72%              |
| BP-026     | Coverage closure, wrong testbench target    | PARTIAL| 60/60  | 1h 14m 7s | 54%+2 compactions+77% |
| BP-027     | Coverage closure, correct testbench, 90.1%  | PASS   | 15/15  | 38m 7s    | 47%              |
| BP-028     | fh_sel T2/T3, integration-level, conditional| COND. PASS | 62/62 | 22m 39s | 15%+compaction |
| BP-029     | CE-01--04 saturating arithmetic boundaries  | PASS   | 66/66  | 26m 42s   | 27%              |
| BP-030     | CE-05/CE-06 allocation and update boundaries| PASS   | 68/68  | 17m 31s   | 75%              |

---

## What Comes Next

TAGE is closed: implemented, arbitration-tested, and
covered to target or explicitly deferred on every remaining
item. The next work is a research session on ITTAGE,
followed by implementation using the same table
architecture and, where applicable, the same coverage
methodology built in this range.

---

## Technical Debt Referenced

[TD# 37](#td-37), [TD# 39](#td-39), and [TD# 40](#td-40) are copied from PROJECT_STATUS.md
as of session-061 and are unchanged in substance from Part 29.

[TD# 38](#td-38-current) has drifted: the number was retained across a later
Verilator version upgrade (5.020 to 5.048) but the text was
not preserved historically -- it now tracks a different,
unrelated concern. The row below is reconstructed from
INFRA-003's own description of why the debt was opened, not
copied from a session-029-era PROJECT_STATUS.md snapshot
(none was pasted into this project). It should be read as a
faithful reconstruction of the original entry, not a
verbatim historical copy.

| # | Item (as of Part 29, reconstructed) | Resolution path (as of Part 29, reconstructed) |
|---|------|------------------|
| <a id="td-38-part29"></a>38 | Verilator 5.020 does not accept a runtime coverage file path argument. Coverage requires a two-pass compile: a `--binary` build followed by a `sed` patch of the generated `Vtb__main.cpp` to append a `coveragep()->write()` call. | Pin Verilator at 5.020 until resolved. Re-evaluate on the next Verilator upgrade whether the runtime argument is supported and the two-pass workaround can be removed. |

| # | Item (current, session-061) | Resolution path (current, session-061) |
|---|------|------------------|
| <a id="td-37"></a>37 | trx_type forwarded combinationally from arb_grant_upd instead of from registered arb_trx_r.trx_type. Verify grant signal stability through tage_cntrl pipeline under concurrent pred+upd. | Investigate before closing. When concurrent pred+upd tests are added (arb item #73), verify grant stability through the pipeline. If unstable, promote arb_trx_r.trx_type and adjust write-enable timing. |
| <a id="td-38-current"></a>38 | Verilator 5.048 covergroup #7099 status not yet verified. | Re-check #7099 status in 5.048 release notes before closing. |
| <a id="td-39"></a>39 | TB-ARB-08 Rule 2 starvation override untestable at current params. PRED_CREDITS=4 < STARVE_THRESH=8 so starve_ctr never reaches threshold. Rule 4 is the effective ceiling. | Verify PRED_CREDITS < STARVE_THRESH is intentional. If Rule 2 must be testable, adjust params before bp_cluster integration. See arb item #73. |
| <a id="td-40"></a>40 | TB-ARB-05 spec discrepancy. Old "backpressure 2 cycles" note did not match TAGE_UQ_DEPTH=8. No RTL risk. | bp_arb_spec.md testbench section (was 10.1) removed session-057; tb requirements now live in the implementing task file. Verify UQ_DEPTH there before bp_cluster integration. No RTL change. |

<a id="td-35"></a>TD# 35 (the test-count-comparison script, superseded at the
start of this post's range) no longer has an active entry
in PROJECT_STATUS.md and is not reproduced here.

---

## Design Process Notes

### What the sessions exposed about the methodology

Three of the eight BP/INFRA sessions in this range did not
fail because the RTL was wrong. BP-026 missed its own
stated coverage target because its tests were written
against the wrong testbench file for the Makefile target
measuring them. BP-028's T2/T3 arms are functionally
exercised but read as uncovered because
`verilator_coverage --annotate` collapses per-instance
counts to the highest-indexed instance sharing a source
line. BP-025's TC-23 contradiction was never resolved
because static analysis and the coverage tool's own
zero-execution report disagreed, and no session in this
range ran the waveform capture needed to settle it. In each
case the obstacle was measurement fidelity -- whether the
right file was being measured, whether the tool could
represent what actually executed, whether static reasoning
about the RTL matched what the simulator reported -- not a
defect in TAGE's design.

The BP-025 process deviation is a separate finding. A
prompt specifying console-output-only ran against a project
convention requiring direct file writes, and the mismatch
was not caught by either the PA or Jeff before the session
executed. The session's own Results Discussion recorded
this rather than treating it as resolved by the manual
workaround applied afterward.

### What the PA contributed

The PA scoped the INFRA sequence, decided the gap-analysis
report format used across INFRA-005 and INFRA-006, wrote
all fourteen prompts in this range, and made the call to
route BP-028's T2/T3 closure through integration-level
testing once the parameterized-instance limitation in
Verilator's coverage tool was identified, rather than
pursuing the unit-level extension BP-027 had originally
proposed as the next step.

### What the IA contributed

The IA's diagnostic work in BP-024 and BP-025 produced
root-cause findings with specific line-number and signal-name
evidence rather than surface-level test additions. In
BP-029, the IA identified that the prompt's background
description of where saturating arithmetic lived was
incorrect and adapted the test placement to the actual RTL
structure rather than writing against the assumed one. The
BP-023c arbitration implementation and the BP-026/BP-027
sequence were executed to completion without design-level
error; where they fell short of their targets, the cause was
tooling and testbench targeting, not RTL correctness.

### The generalization

Across this range, every coverage-closure session that fell
short of its stated goal did so for a measurement reason,
not a design reason: the wrong testbench file (BP-026), a
coverage tool that cannot resolve per-instance execution
correctly (BP-028), and a coverage tool result that
contradicted static analysis with no session available to
adjudicate between them (BP-025's TC-23). Building the
coverage pipeline in INFRA-001 through INFRA-006 made these
problems visible for the first time -- prior to this range,
CU-11 and CU-08/CU-09 were marked covered in the coverage
plan on the basis of tests passing, not on the basis of a
coverage tool confirming what those tests actually executed.
The pattern across BLOG_bpu_5 through BLOG_bpu_8 was that
deferred problems became expensive later. This range adds a
related but distinct pattern: coverage claims made without
a coverage tool are not evidence, and building the tool
surfaced gaps the project had believed closed.

---

*No references required for this post.*

