<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

```
TITLE:     "Branch Prediction Cluster Simulation and Mutation-Based Verification"
FILE:      BLOG_bpu_20_cluster_simulation.md
AUTHOR:    Jeff Nye
DATE:      2026-09-23
STATUS:    REVIEW BEFORE POSTING
COPYRIGHT: "Copyright 2026 Jeff Nye"
```

<!--
---

::SERIES DESCRIPTION::
::BEGIN LINKS::
::END LINKS::
-->

# Branch Prediction Cluster Simulation and Mutation-Based Verification

## Abstract

The Pacino top level branch prediction unit or cluster (bp_cluster) 
instantiates seven predictors and the history module. At the end of
these sessions the bp_cluster was simulated, line coverage was measured and
mutation testing was completed.

Prior to final simulation the loop predictor was extended to support dual
prediction. The per-slot branch PC sent to the history module was corrected to
use the branch's position within the block.

During simulation a bug was discovered caused by reading an early version of
branch_id which defeated the FTQ entry comparison match. This was fixed by
adding the missing stage.

At the end the cluster testbench includes 973 checks, full line coverage
for the top level cluster and mutation defect injection was successfully 
tested on 20 faults.

The methodology was modified to require each check or test to prove it captures
failures. Each mechanism that determines run pass/fail was deliberately broken
to confirm the run then fails. Each class of defect found was swept across all
18 unit testbenches and bounded. Defects were discovered in exit codes,
unbound assertions and watchdogs that could not fire. These were repaired.

## Where the range starts

The previous range ended with `bp_cluster` built and linted but not yet
simulated [1]. The project flow builds a top level and lints it against its
interface before driving it. The exit handoff listed nine items to resolve
before a testbench could be written. Three would change ports the testbench
binds by name: the loop predictor's dual-slot retrofit (TD #105), which of
two identical loop predictor types to keep (TD #106), and whether the p1
output carries the block fall-through (TD #108). Two were testbench
decisions: how to present a mismatched `branch_id`, and which unknown-value
settings the simulation uses. One was an open question: whether the
statistical corrector (SC) arbiter's starvation rule is reachable (TD #39).

## Settling the boundary

### The loop predictor retrofit

BP-091 retrofitted `loop_pred.sv` from one fixed slot to a parameterized design
using `NUM_PRED_SLOTS`, with one table bank per slot and the per-slot algorithm
unchanged. The cluster was rewired in the same task, removing two placeholders
the single-slot module had forced: slot 1 no longer takes the uBTB prediction
unconditionally, and slot 1's p2 loop metadata is a real snapshot rather than
zero.

Of eight defects the IA injected, two were missed on the first pass. One
wrote every bank when any slot's update was valid. It went undetected because
the idle slot's payload was unfortunately all zero; a new test holds a
complete payload on a slot whose valid is low. The other was a confidence
counter that did not saturate, a case no directed test had reached. Both were
closed, and the second pass caught all eight.

### One loop type and the block fall-through

BP-092 closed TD #106 and TD #108, removing the original shared loop predictor
type `bp_loop_meta_t`, in favor of `lp_pred_t`.

BP-092 also added the p1 output `bpu_pred_pft_p1` (partial fall-through
address).[F1] The FTQ uses `bpu_pred_pft_p1` as a default next fetch PC.

The FTQ uses `bpu_pred_pft_p1` in two places:

1. Selecting the next fetch PC at p1. The order is slot 0's target if slot 0
   is valid and taken, then slot 1's target if slot 1 is valid and taken,
   and otherwise `bpu_pred_pft_p1`.

2. Storing it in the FTQ entry. It is written to `bp_ftq_entry_t.pft_addr`
   at allocation. The FTQ repeats the next-PC selection whenever a redirect
   rewrites a slot, and that selection still needs the not-taken address,
   which cannot be rebuilt from the rest of the entry.

Before this port, the cluster computed the value for its own successor
logic, but nothing outside the cluster could see it. The port also makes
the p1 redirect operand observable at the cluster boundary.


### Corrections to the per-slot branch PC

BP-092 found that the cluster computed each slot's branch PC as the request
PC plus the slot number times 32 bytes. This stride is left over from a
retired model in which slot 1 looked up the next block. Both slots now
describe branches in the same block, so slot 1's PC was one block too high.
The value feeds `bp_history`'s path history, and through it the TAGE, ITTAGE
and SC hashes.

BP-092a replaced the stride with the block base plus the slot's in-block
position. It also corrected `bp_history_interfaces.md`, which said `pred_pc`
is the block PC. `bp_history` folds `pred_pc[3:2]` into the path history,
and those bits are always zero in a block-aligned PC. With no cluster
testbench yet, the change was checked by lint only, and BP-092a specified
seven test cases, TC-A through TC-G, for the testbench to come.

## The first simulation

BP-093 built `tb_bp_cluster.sv` with six groups: bring-up, p1 prediction, p2
redirect, p3 and supersession, history, and metadata.

The testbench seeds predictor state directly or through the update ports,
and where an index or tag is needed it either writes every entry or takes
the value from the DUT's own hash nets, so no test depends on an unchecked
hash.

Test D2 holds an SC update request, which makes the arbiter periodically
withdraw TAGE's `consumer_ready`. It then issues 40 back-to-back requests,
so delayed responses arrive after the stage register has advanced and
carry a mismatched `branch_id`.

### What the run found

All 530 checks passed and `bp_cluster.sv` needed no change. The run found
one defect: `tage_cntrl.sv` was missing the p0 to p1 register on
`branch_id`.

The IA also found two testbench defects. Two FTQ indices were 7-bit values
assigned to a 6-bit field, so the checks using them compared zero with
zero. 

Line coverage of `bp_cluster.sv` was 245 of 258. The uncovered lines were
the update decode and the SC arbiter. This was resolved in BP-094.

The IA injected 13 defects into the cluster RTL, and the checks detected 12.
The missed one inverted the rollback index select when p2 and p3 redirect
together.

## The fix and the update path

BP-094 added the missing register. The IA confirmed that `ittage_cntrl.sv`
already staged `branch_id` correctly, and the requirement was added to the
TAGE and ITTAGE interface documents.

A new `tb_tage` test sends consecutive requests with different `branch_id`
values. Against the unfixed RTL it reported 22 failures, but the run
returned exit 0: the testbench's failure path used `$finish(1)`, which
Verilator 5.048 reports as success. It was changed to `$fatal(1)`. In the
cluster, a new test issues 16 back-to-back requests. Before the fix none
delivered a TAGE or SC result; after it, all 16 did.

The bring-up checks used `$isunknown`, which cannot fail under Verilator's
two-state simulation. They were replaced with 36 checks of each boundary
signal's reset value. A new RAS check first compared a net with another net
driven from the same source, so it could not fail. It was rewritten to
compare against the RAS pointer registers one cycle later.

BP-094 also added the update-path tests that BP-093 had deferred. The
testbench acts as the FTQ: it stores the p2 and p3 metadata and returns it
on the update ports at resolution, and each of the seven predictors is
checked to learn from it. The SC credit arbiter's grant rules are tested
individually. Its starvation override cannot be reached in the current
configuration (TD #39): the starvation counter resets at 4, before it
reaches the threshold of 8.

The testbench finished at 973 checks. The 13 earlier injected defects and
seven new ones were run against the final sources, and the checks detected
all 20.

## Confirming the tests can fail

Mutation is used at two levels. Injecting defects into the RTL shows
whether the checks detect an incorrect design. 

Breaking the testbench by forcing a check to fail, an assertion to fire or the
clock to stop, shows whether that failure reaches the exit status `make`
reports. 

Each break was run once to confirm the failure was reported and once with the
break removed to confirm the run passed. When a break exposed a defect, every
testbench in the unit was checked for the same kind of defect.

### Failure exits

Five testbenches did not use `$fatal`, so a failed check still returned
exit 0. All five were fixed.

### Assertion binds

Two TAGE testbenches bound the assertion module to an instance name.
Verilator 5.048 accepts this without a warning but instantiates nothing, so
the TAGE assertions never ran. IEEE 1800 allows binding to an instance [2];
this is a limitation of this Verilator version. Both binds were changed to
the module name, and the other three binds in the unit were already correct.
Once the assertions ran, they caught one test that drove an invalid update.

### Watchdogs

BP-096 and BP-097 checked every testbench for a watchdog. Seven had none,
and the one in `tb_bp_cluster` counted clock cycles, so it could not fire
if the clock stopped. All eight now use a time delay, which fires whether
or not the clock is running, and each was proved by stopping the clock
generator.

A project rule was added: a watchdog is implemented as a time delay.
Clock counts are no longer used.

### Check counts

| Unit | Checks |
|---|---|
| uBTB | 259 |
| FTB | 99 |
| RAS | 87 |
| Loop predictor | 126 directed (a) |
| TAGE | 121 |
| ITTAGE | 390 |
| SC | 166 |
| History | 19,224 (b) |
| Cluster | 973 |

The regression runs 47 targets across 18 testbenches, all passing at the
close of this range.

(a) The testbench reports 9,342 checks. 9,216 come from one reset test
that reads the table through 512 lookups per slot and counts each of 9
output fields as a check.

(b) The testbench reports 19,224 checks. After each update it compares
every folded history against a reference fold computed by the testbench,
27 folds per comparison. Two test cases of 400 and 300 updates account for
18,900 of the total.

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| BP-091 | loop_pred dual-slot retrofit, cluster rewired | PASS | tb_loop_pred 126 directed + reset sweep; 2 of 8 injected defects missed on first pass, closed; 45/45 targets | 25m 8s | 23% |
| BP-092 | bp_loop_meta_t removed; bpu_pred_pft_p1 added | PASS | tb_bp_pkg 28/28; cluster lint only; 45/45 targets | 13m 10s | 17% |
| BP-092a | Per-slot branch PC derived from in-block position | PASS | lint only; TC-A to TC-G specified; 45/45 targets | 10m 1s | 15% |
| BP-093 | tb_bp_cluster, first simulation | PASS | 530/0; 245/258 lines; 12 of 13 injected defects detected; tage_cntrl defect reported; 47/47 targets | 1h 3m 27s | 44% |
| BP-094 | branch_id register fix; update path and SC arbiter tests | PASS | 973/0; 258/258 lines; 20 of 20 injected defects detected; 47/47 targets | 1h 8m 6s | 42% |
| BP-095 | Failure exits in five testbenches | PASS | 5 of 5 proven both directions; 47/47 targets | 21m 18s | 20% |
| BP-096 | Assertion binds, watchdogs | PASS | 5 binds in 46 files, 1 repaired; 4 watchdogs added; 47/47 targets | 26m 4s | 19% |
| BP-097 | Watchdog repair, last $isunknown check, exit-path inventory | PASS | 1 always-passing check replaced; 3 watchdogs added, 1 repaired; 47/47 targets | 57m 0s | 33% |

## Design Process Notes

### The IA contribution

The IA tested its own tests by injecting defects into scratch copies of the
RTL, after confirming that an unmodified copy passed: 8 in BP-091, 13 in
BP-093, and 7 more in BP-094, which reran all 20 against its final sources.
Each defect the checks missed got a new test that caught it.

Most of the range's defects were found while doing other work: the stride
while correcting a comment, the missing `branch_id` register in the first
cluster simulation, the `tb_tage` exit when a run printing eleven failures
returned 0, and the dead bind while measuring how assertion failures exit.
The IA also found defects in its own tests: the truncated FTQ indices, 
and a RAS check that compared two nets driven from the same source.

It checked task premises against the tree before acting on them. BP-096
reproduced a reported compile failure and found a different cause than the
task stated. BP-097 corrected four false premises with evidence and
returned three of its six problems as negative results. BP-096 also used a
better bind liveness test than the one specified, a probe that fires only
if the assertion module is instantiated and clocked.


### The PA contribution

The planning assistant wrote the eight task files and drafted corrections to
four planning documents in session 064, which I applied:
`bp_history_interfaces.md`, `ftq_bpu_interfaces.md`, `fe_decisions.md` and
`bp_arb_spec.md`.

Two tasks existed because constraints in earlier ones blocked fixes the IA
had found: BP-092a for the stride, and BP-094 for `branch_id`. The
constraint form changed as a result. A task now marks only unnecessary
change as out of scope and tells the IA to fix what it finds and report it.
BP-094, BP-096 and BP-097 used that form, and each repair happened in the
run that found the defect. The update path and SC arbiter tests, scoped out
of BP-093 and at first out of BP-094, were returned to BP-094 since it was
already building their stimulus.

Several task files made claims the tree contradicted: BP-096 stated that a
bind signal was undeclared, which it was not, and BP-097 had four wrong
premises.

BP-096 ordered the deletion of `ittage_assert_bind.sv`, which I had not
authorized. The file was dead and the deletion stands, recorded in TD #110
as not a precedent, and BP-097 carried constraints against deletion.
BP-097 in turn listed planning documents as files expected to change. The
IA edited `PROJECT_STATUS.md` and `tage_coverage_plan.md` as instructed, and
both edits were reverted. The rule is that an IA task reports what a
planning document should say, the planning assistant drafts it, and I apply
it.[F2]

Two task forms worked. BP-095 required each exit to be broken, run and
recorded in both directions for every testbench. BP-097 stated six problems
with acceptance criteria and left method and order to the IA, which found
the cycle-based watchdog without being asked.

### My contribution

I ruled that `lp_pred_t` survives, that the p1 output carries the block
fall-through, and that the simulation takes no unknown-value settings because
every control bit is reset-initialized. I ruled that a separate uBTB decisions
document was unnecessary, since the uBTB entry mirrors the FTB entry and the
FTB decisions record the block model. I identified the constraints in BP-092
and BP-093 that blocked the IA's fixes, returned the update path and SC
arbiter tests to BP-094, and reverted the planning document edits from
BP-097.

### The generalization

Each testbench defect in this range let a run pass whether or not the
design was correct: a failure exit returning 0, a bind instantiating
nothing, a watchdog waiting on a stopped clock, an `$isunknown` check under
two-state simulation, and a check comparing two nets driven from the same
source [3]. The simulator reported none of them. Each fix was proven by
breaking the mechanism and confirming the run failed.

The `branch_id` defect is the same problem in the design. The TAGE unit
tests passed because they never sent consecutive requests with different
`branch_id` values. The cluster sends them on every cycle in normal
operation, and the first cluster simulation found the defect.

The project rule that follows is that a check counts only after it has
been shown to fail. When one instance of a defect that lets a run pass is
found, every testbench in the unit is checked for the same defect, and the
number found is reported, including zero.

## What comes next

At the close of the range the cluster is verified at its boundary, and the
unit's pass results are enforced. The testbench acts as the FTQ. The next
sessions will specify and build the FTQ.

Open items:

- TD #39: the SC starvation override is unreachable at the current
  parameters. Needs a parameter decision.
- TD #100: TAGE line coverage may be low, or the figure may be dominated by
  testbench lines. 8,043 of `cov_tage`'s 8,700 lines are in `tb_tage.sv`.
  Needs a decision.
- Watchdog limits are not uniform. The completion times behind them need
  re-measuring before a rule for setting limits is written.
- The session-063 cluster decisions are recorded only in handoff-064 and
  `ftq_bpu_interfaces.md`.[F3]

## Technical Debt Referenced

Status as of the close of this range. Later experiments have changed some
items.

| # | Item | Status |
|---|---|---|
| 1 | NUM_PRED_SLOTS=1 build. | Open. tb_bp_cluster fails to elaborate unless NUM_PRED_SLOTS is 2. |
| 39 | SC starvation override reachability. | Open. With SC_PRED_CREDITS=4 the starvation counter resets at 4 and never reaches SC_STARVE_THRESH=8. Needs a parameter decision. |
| 67 | TAGE sram_init slow path untested. | Open. Now includes the cluster, whose targets all use fast initialization. |
| 100 | TAGE line coverage below 90%. | Open. 73.8% (6418/8700), of which 8043 lines are tb_tage.sv. Whether TAGE is under-covered is unresolved. |
| 102 | bp_history does not generate IT5 folds. | Open. IT5 indexes on the PC alone. |
| 105 | loop_pred dual-slot retrofit. | Closed BP-091. |
| 106 | Duplicate loop predictor type. | Closed BP-092. bp_loop_meta_t removed. |
| 107 | Stale comments in bp_cluster.sv. | Closed BP-092 and BP-092a. |
| 108 | p1 block fall-through output. | Closed BP-092. bpu_pred_pft_p1 added. |
| 109 | tb_tage binds assertions to an instance name. | Closed BP-096. Bind changed to the module name. |
| 110 | ittage_assert_bind.sv compiled by no target. | Closed BP-096 by deletion, ordered by the task without authorization. |
| 111 | Testbenches without a working watchdog. | Closed BP-097. Four added in BP-096; three added and one repaired in BP-097. |

## References

<!-- ticfinder_off -->
[1] The Branch Prediction Cluster: Built and Not Yet Run (BLOG_bpu_19), for
the cluster this range simulates.

[2] IEEE Std 1800, IEEE Standard for SystemVerilog, clause 23.11, "Binding
auxiliary code to scopes or instances."

[3] External Anchors: When a Proof and Its Reference Share the Same Error
(BLOG_bpu_16), for an earlier check whose two sides came from the same
source.
<!-- ticfinder_on -->

## Footnotes

<!-- ticfinder_off -->
[F1] "pft" is from the partial fall-through stored in the uBTB entry, an
offset from the block start. The uBTB reconstructs the full address from
that offset and the lookup PC, and `bpu_pred_pft_p1` and the FTQ's
`pft_addr` carry the full address. The entry's carry bit was removed in
BP-110.

[F2] The rule was later added to CLAUDE.md's fixed constants, applying from
BP-106 (session 067).

[F3] TD #112, which tracked these decisions, was closed by ruling on
2026-09-17. Their promotion into bp_cluster.md is no longer tracked there.
<!-- ticfinder_on -->

---
<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
