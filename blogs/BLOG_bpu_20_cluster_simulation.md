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

`bp_cluster` is the top level of the Pacino branch prediction unit. It
instantiates seven predictors and the history module, forms a prediction at
p1, derives redirects at p2 and p3, and writes each prediction's metadata to
the fetch target queue (FTQ). At the start of this range it had been built,
elaborated and linted, and not simulated.

Two tasks first settled the cluster's ports: the loop predictor gained a
second prediction slot, two duplicate loop predictor types became one, and the
p1 output gained the block fall-through address. A third corrected the branch
PC the cluster reports to the history module.

The first cluster testbench ran 530 checks. It found a defect in the TAGE
controller that no unit suite exposed, because none varied the input: the
`branch_id` carried in TAGE's metadata named the request one cycle later than
the rest of the metadata. At the cluster boundary this defeated the check that
matches a late prediction to its FTQ entry. The fix, a closed predict-then-update loop for all seven
predictors, and the statistical corrector's arbiter tests brought the
testbench to 973 checks and the cluster to 258 of 258 lines covered. All 20
injected RTL defects were caught.

The last three tasks applied the same method to the test infrastructure of
the whole unit. Each mechanism that decides whether a run passes was
deliberately broken to confirm the run then fails: the failure exit, assertion
binding, watchdogs and individual checks. Each class of defect found was swept
across all 18 unit testbenches and bounded. Across the range, six testbenches
reported exit 0 on a failed check, two assertion binds instantiated nothing, one watchdog
could not fire, and one counted check could not fail. All were repaired. No
check count changed, and all 47 unit targets pass.

## Where the range starts

The previous range ended with `bp_cluster` structurally complete and
unsimulated, which is the order the flow follows: the top is built and linted
against its interface, then driven. The exit handoff listed nine items between
that state and a testbench. Three changed ports the testbench would bind by
name: the loop predictor's dual-slot retrofit (TD #105), which of two
identical loop predictor types to keep (TD #106), and whether the p1 output
carries the block fall-through (TD #108). Three were testbench decisions: how
to present a mismatched `branch_id`, which unknown-value settings the
simulation uses, and whether the statistical corrector (SC) arbiter's
starvation rule is reachable (TD #39).

## Settling the boundary

### The loop predictor retrofit

BP-091 retrofitted `loop_pred.sv` from one slot to `NUM_PRED_SLOTS`. Five
ports gained a slot dimension, `pred_p0` was renamed `pred_p1` to name the
stage at which the value is available, and the table became one bank per
slot. The per-slot algorithm is unchanged. The cluster was rewired in the same
task, removing two placeholders the single-slot module had forced: slot 1 no
longer takes the uBTB prediction unconditionally, and slot 1's p2 loop
metadata is a real snapshot rather than zero.

`tb_loop_pred.sv` now runs its directed set on each slot from a per-case reset
and adds slot independence, simultaneous prediction and update on both slots,
and a reset test over every bank. It reports 9,342 checks. The IA injected
eight defects into scratch copies of the RTL. Two survived the first pass. One
wrote every bank when any slot's update was valid, masked because the idle
slot's payload was all zero and matched no write path; a new test holds a
complete payload on a slot whose valid is low. The other was a confidence
counter that did not saturate, which no directed test had reached even before
the retrofit. Both were closed, and the second pass caught all eight.

### One loop type and the block fall-through

I ruled on TD #106 and TD #108 at the start of the session, and BP-092
implemented both. `lp_pred_t` and `bp_loop_meta_t` carried the same thirteen
fields, 80 bits each, in a different order and with two fields spelled
differently. A bit-level cast between them would have compiled and placed
every field in the wrong position. `bp_loop_meta_t` was deleted, and the
cluster's `lp_to_meta()` with it, since it did nothing but reorder and rename.

The p1 output group gained `bpu_pred_pft_p1`, one value per prediction,
qualified by `bpu_pred_val_p1`. It is the p1 view of the block end: the uBTB
entry's fall-through on a hit, and the block-aligned PC plus 32 bytes on a
miss.[F1] The FTQ needs it when no slot is taken, and it makes the p1 redirect
operand observable at the boundary. The value already existed as the not-taken
term of the cluster's successor expression, and the port is driven from it.

### The per-slot branch PC

While correcting a stale comment, BP-092 found that the code beneath it was
also stale. The cluster computed each slot's branch PC as the request PC plus
the slot number times 32 bytes, the retired model in which slot 1 was a lookup
of the next block. Since the uBTB rewrite, both slots describe branches in the
same block, so slot 1's PC was one block too high. Its only consumer is the PC
`bp_history` folds into the path history that feeds the TAGE, ITTAGE and SC
hashes. BP-092's constraints put the expression out of scope, and the IA
reported it.

BP-092a replaced the stride with the block base plus the slot's in-block
position, shifted by `BR_POS_SHIFT`, which is derived from the block size and
the position field width. The IA also reported that `bp_history_interfaces.md`
stated the opposite, that `pred_pc` is the fetch block PC. `bp_history` folds
`pred_pc[3:2]` into the path bit, and those bits are zero in a block-aligned
PC, so under the document's rule the path history would carry no information.
The planning assistant drafted the correction and I applied it. With no
cluster testbench, BP-092a could only lint its change. It wrote seven cases,
TC-A through TC-G, with exact expected values, as the specification for the
testbench to come.

## The first simulation

BP-093 built `tb_bp_cluster.sv` and covered six groups: bring-up, p1
prediction, p2 redirect, p3 and supersession, history, and metadata.
Bring-up came first, and the task stopped if it was not green. One request
must produce a prediction a cycle later with the requested index, followed by
p2 and p3 metadata on successive cycles. The harness must exit non-zero on a
failed check; the IA drove a deliberate failure from a plusarg so the
demonstration is repeatable, and the binary exited 1 and `make` exited 2. The
sim target sets neither `--x-assign` nor `--x-initial`, because every valid,
enable, count and select is reset-initialized. The IA stated that its
`$isunknown` bring-up check could not fail under Verilator's two-state model.

Tests need predictors that hold known entries. Training each one through its
update path makes every test long, and writing tables by hierarchical
reference ties cluster tests to each predictor's layout. The testbench writes
the uBTB and loop predictor tables directly and checks its index and tag
derivation against the DUT's own nets in the same cycle. It installs FTB and
RAS state only through the cluster's update ports. It writes the TAGE base
table and the SC counter tables uniformly, so no hash is assumed, and it reads
the one ITTAGE entry's index and tag from the DUT's hash nets.

A mismatched `branch_id` was presented at the boundary, not forced into
predictor metadata. Test D2 holds an SC update request so the arbiter
periodically withdraws TAGE's `consumer_ready`, then issues 40 back-to-back
requests, so delayed responses arrive after the stage register has advanced.

### What the run found

All 530 checks pass, and `bp_cluster.sv` needed no change. The run found one
defect, in `tage_cntrl.sv`. The controller builds its p1 metadata from values
staged at p0, except `branch_id`, which it read live from the p0 input. The
`branch_id` arriving at p2 named the request one cycle later than the one the
rest of the metadata described.

The cluster accepts a p2 or p3 result only when its `branch_id` equals the FTQ
index in the matching stage register. With the skew, in an unstalled stream
that check never matched, and neither the TAGE direction nor the SC correction
reached the FTQ. In a stalled stream it matched the wrong entry: D2 recorded
four accepted responses out of 32, each carrying another request's
`branch_id`. The SC copies its `branch_id` from TAGE and inherited the skew.
Every TAGE unit test presented one request at a time with a single
`branch_id`, so a live read and a staged read gave the same result.

The task barred changes to predictor RTL, so the IA reported the defect and
wrote test C0 to pin the observed value, so that correcting the controller
would fail C0 and force the testbench to be revisited. Tests needing a TAGE or
SC result repeated the FTQ index on the following cycle to work around it.

The IA found two testbench defects that produced passing checks without
testing anything. FTQ indices `6'h40` and `6'h41` truncate to 0 and 1 at six
bits, so two `branch_id` checks compared zero with zero. The ITTAGE tables use
a RAM with no reset, so an entry seeded for one case matched in a later one;
the reset task now clears them.

Coverage of `bp_cluster.sv` was 245 of 258 lines, the uncovered lines
belonging to the update decode and the SC arbiter, which were deferred. The
IA injected 13 defects into the cluster RTL. One survived the first pass,
inverting the rollback index select when p2 and p3 redirect together: with
the skew present, the two stage indices were always equal on those cycles, so
both selects agreed. A test under arbiter stalls reached four such cycles
with distinct indices and caught it.

## The fix and the closed loop

BP-094 registered `branch_id` from p0 to p1 alongside the index and tag
hashes. No port or struct changed, and SC needed no change of its own. The IA
read `ittage_cntrl.sv`, found it already staged correctly, and recorded the
requirement in the TAGE and ITTAGE interface documents, where it had not been
stated.

A new `tb_tage` test varies `branch_id` across consecutive requests and seeds
each PC with a different base-table counter, so each response identifies its
request two ways. Against the unfixed RTL it reported 22 failures, every
`branch_id` one request newer than expected, while the counter checks passed.
The first run of that demonstration printed failures and returned exit 0. The
`tb_tage` failure path was `$finish(1)`, which Verilator 5.048 reports as
success, the same defect BP-086 had found in the uBTB testbench. Both exits
became `$fatal(1)`.

In `tb_bp_cluster`, C0 failed on the fixed RTL as intended and was rewritten
to check the specified behavior. The index-repeat workaround was removed from
its nine uses. New test C4 issues 16 back-to-back requests with no repeated
index and no stall. Before the fix it delivered no TAGE or SC result; after
it, all 16 deliver both. D2 gained checks that every rejected response carries
an older `branch_id` than the p2 stage and that every accepted one is
published under its own index.

The seven `$isunknown` bring-up checks became 36 checks of the specific reset
value of each boundary valid, index, pointer and credit counter. Test E4
confirms that the RAS state published at p1 is the state that block starts
from at p2. The IA's first version compared the snapshot with a net driven
from the same source, which cannot fail; it rewrote the check against the RAS
pointer registers one cycle later.

Group G uses the metadata write path added in the previous range. The
testbench acts as the FTQ: it captures the p2 and p3 metadata by FTQ index and
returns it on the update ports at resolution. G0 drives all seven branch types
through the update fan-out and checks which predictors receive each. G1
through G7 close the loop for each predictor: a TAGE counter flips direction,
ITTAGE learns a target, the SC sum moves toward the resolved direction and its
override clears, and the uBTB, FTB, loop predictor and RAS each learn.

Group H covers the seven SC credit arbiter grant rules and TAGE's
`consumer_ready`. Two arms are not reachable from the ports in the shipped
configuration. `sc_ready` is held at 1 under the fast-initialization plusarg,
so one test clears the plusarg's register for its duration. The starvation
override is TD #39: with SC_PRED_CREDITS at 4, the run measured the starvation
counter reaching 4 and resetting, so it never reaches SC_STARVE_THRESH of 8.
Test H6 starts the counter at the threshold and confirms the implemented arm
follows the rule, and states that it does not show the arm is reachable.

Line coverage reached 258 of 258, and the testbench 973 checks. The 13
earlier mutants and seven new ones were run against the final sources, and all
20 were caught.

## Confirming the tests can fail

A passing target means the design met its checks only if the harness can
report a failure. The code mutations above test whether a check detects a
wrong design. The remaining three tasks tested whether a failed check, a
failed assertion or a hung run reaches the exit status `make` reads. Each
mechanism was broken on purpose, the run observed to fail, the break removed
and the run observed to pass. Each class of defect found was then swept across
the unit, so the result is a bounded count.

### Failure exits

BP-095 broke one check in each of five testbenches that had no `$fatal`. All
five printed the failure and returned exit 0. After conversion to `$fatal(1)`
the same breaks gave `make` exit 2, and with the breaks removed all five
passed. The 390 ITTAGE checks reproduced exactly, so those counts were
correct, and are now also enforced. Because `$finish` takes effect at the end
of the time step, the first fix printed both verdicts on a clean run; every
verdict is now an `if`/`else` with the exits in separate branches. The IA also
measured that a failing `assert ... else $error` produces a non-zero exit
under the project's flags.

### Assertion binds

`tb_tage_manual.sv` bound the TAGE assertion module to `u_dut`, the
testbench's instance name. Verilator 5.048 accepts this, instantiates
nothing, and reports nothing under `-Wall`. BP-095 changed the bind to the
module name, proved it live by forcing an assertion to fail, and reported the
same form in `tb_tage.sv`, which left the TAGE assertions unevaluated in
`sim_tage`, `sim_tage_fast`, `lint_tage` and `cov_tage`.

BP-096 enumerated every bind in the unit: five in 46 files, four correct, so
the class is bounded at the two found. The IA proved each bind live with a
temporary probe inside the assertion module that fails on the first clock
after reset. It fires only if the module is instantiated and clocked, which is
the property a bind to an instance name lacks, and it does not depend on
stimulus.

The task's background said a signal in the bind's port list,
`tage_assert_inhibit`, was not declared in `tb_tage.sv`. The IA reproduced the
compile failure and found the signal declared and driven. A bind that names a
module resolves its port expressions in that module's scope, where a
testbench signal does not exist, and the fix was the hierarchical reference
`tb.tage_assert_inhibit`. IEEE 1800 defines binding to an instance [1], so the
project rule that a bind names a module is a workaround for this Verilator
version, not a language rule.

Making the bind live exposed two further defects. `cov_tage` did not compile
`tage_assert.sv`, and the Makefile gained it; the line count moved from 6407
of 8689 to 6418 of 8700, a new baseline. With the assertions running,
`tb_tage` failed in one sub-test that hand-built an update in a state the TAGE
counter update rules record as invalid input. Sibling sub-tests that feed the
DUT's own metadata satisfy the assertion, so the defect was in the stimulus.
It was the only one of 13 such sites in the file missing an assignment.

### Watchdogs

BP-096 added watchdogs to four testbenches that had none, with limits set
from measured completion times. It proved each by stopping the clock
generator, which is how a hang presents, rather than by shortening the limit.
BP-097 swept all 18 testbenches. Three more had none, and the one in
`tb_bp_cluster` waited on `repeat (200000) @(posedge clk)`, counting the clock
a hang can stop. With the clock frozen, `make` did not return. All four were
given time-based limits and proven in both directions. The rule is now
recorded: a watchdog is a time delay, never a cycle count.

### Counted checks

`tb_bp_cluster` check D2 tested `!$isunknown` of three queue-status bits,
which is constant under two-state simulation, so it could not fail and was
counted among the 973. BP-094 had removed the same form from bring-up. BP-097
classified all 450 check sites in the file and found this the only remaining
instance; no other unit testbench uses `$isunknown`. The check now compares
each bit with its required value every cycle. Mutated, it reported one failure
and `make` exit 2. BP-097 also inventoried every exit path reachable from the
18 testbenches, including through included files, and found none that reports
a failed run as passing.

### Two numbers reconciled

BP-095's tables reported `sim_bp_cluster` at 407 checks, where BP-094 reported
973. BP-096 was required to distinguish between candidate causes. 407 is the
number of printed `PASS:` lines. The testbench also has quiet check tasks,
used for sweeps, that count a pass without printing, and the same run prints
`PASS=973 FAIL=0`. BP-095 had counted lines rather than reading the verdict. A
disabled group and a tree difference were each eliminated on the evidence.

The group subtotals then showed groups A through F at 808 checks against
BP-093's 530. BP-097 found that a table in BP-094's Results Capture accounts
for the full difference of 278. The testbench has one commit in version
control, so the growth was visible only in the task record.

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| BP-091 | loop_pred dual-slot retrofit, pred_p0 renamed pred_p1, cluster rewired | PASS | tb_loop_pred 9,342; 8 mutants, 2 survived pass 1, closed; 45/45 targets | 25m 8s | 23% |
| BP-092 | bp_loop_meta_t retired; bpu_pred_pft_p1 added; stale comments | PASS | tb_bp_pkg 28/28; 45/45 both runs; cluster lint only | 13m 10s | 17% |
| BP-092a | Per-slot branch PC derived from in-block position | PASS | 45/45 both runs; lint only; TC-A to TC-G specified | 10m 1s | 15% |
| BP-093 | tb_bp_cluster, groups A to F; first simulation | PASS | 530/0; 245/258 lines; 13 mutants caught; tage_cntrl defect reported; 47/47 | 1h 3m 27s | 44% |
| BP-094 | branch_id staging fix; groups G and H; tb_tage exit | PASS | 973/0; 258/258 lines; 20 mutants caught; tb_tage test 22 failures on unfixed RTL | 1h 8m 6s | 42% |
| BP-095 | Failure exits in five testbenches | PASS | 5 of 5 proven both directions; 390 ITTAGE checks enforced; 47/47 | 21m 18s | 20% |
| BP-096 | Bind sweep, watchdogs, 407 vs 973 | PASS | 5 binds in 46 files, 1 repaired; 4 watchdogs; 47/47 both runs | 26m 4s | 19% |
| BP-097 | Six problem statements: counts, exit paths, watchdogs, records | PASS | 450 check sites, 1 inert check replaced; 4 watchdogs; 47/47 both runs | 57m 0s | 33% |

## Design Process Notes

### The IA contribution

The IA mutation-tested its own work. BP-091, BP-093 and BP-094 injected 8,
13 and 20 RTL defects on scratch copies outside the tree, built with the
project's pinned Verilator after an unmutated control passed. When a mutant
survived, the IA added the test that caught it, and BP-094 reran every mutant
against its final sources.

The range's defects were found while doing other work: the stride under a
comment being corrected, the `branch_id` skew while building metadata tests,
the `tb_tage` exit because a run printing eleven failures returned zero, and
the dead bind while measuring how the assertion files exit. The IA also found
defects in its own tests: the truncated indices, the RAM residue, and the RAS
check that compared a net with itself.

It checked premises against the tree before acting on them. BP-096 replaced
the stated compile-failure cause with the scope rule after reproducing it.
BP-097 corrected four false premises with evidence and returned three of its
six problems as negative results. BP-096 chose a better liveness test than the
one specified.

### The PA contribution

The planning assistant wrote the eight task files and drafted corrections to
four planning documents in session 064, which I applied:
`bp_history_interfaces.md`, `ftq_bpu_interfaces.md`, `fe_decisions.md` and
`bp_arb_spec.md`.

Two tasks existed because constraints in earlier ones blocked fixes the IA had
found: BP-092a for the stride, and BP-094 for `branch_id`. The constraint form
changed as a result. A task now names only unnecessary change as out of scope
and instructs the IA to fix what it finds and report it. BP-094, BP-096 and
BP-097 used that form, and each repair happened in the run that found the
defect. Groups G and H were first scoped out of BP-094 and returned to it,
since it was already building their stimulus.

Several task files carried claims the tree contradicted: the undeclared-signal
diagnosis in BP-096, and four premises in BP-097, one of them answered by a
task file in BP-097's own manifest. For the 407 count, the planning assistant
first proposed that BP-094's work had been lost between sessions; BP-096's
requirement to discriminate between causes settled it.

BP-096 ordered the deletion of `ittage_assert_bind.sv`, which I had not
authorized. The file was dead and the deletion stands, recorded in TD #110 as
not a precedent, and BP-097 carried constraints against deletion. BP-097 in
turn listed planning documents as files expected to change. The IA edited
`PROJECT_STATUS.md` and `tage_coverage_plan.md` as instructed, and both edits
were reverted. The rule is that an IA task reports what a planning document
should say, the planning assistant drafts it, and I apply it.[F2]

Two task forms held. BP-095 required each exit to be broken, run and recorded
in both directions per suite. BP-097 stated six problems with acceptance
criteria and left method and order to the IA, which found the cycle-based
watchdog without being asked.

### My contribution

I ruled that `lp_pred_t` survives, that the p1 output carries the block
fall-through, and that the simulation takes no unknown-value settings because
every control bit is reset-initialized. I ruled that a separate uBTB decisions
document was unnecessary, since the uBTB entry mirrors the FTB entry and the
FTB decisions record the block model. I identified the constraints in BP-092
and BP-093 that blocked the IA's fixes, returned groups G and H to BP-094,
rejected the lost-work explanation for the 407 count, and reverted the
planning document edits from BP-097.

### The generalization

Each defect in the second half of the range produced a passing result
whether or not the design was correct: a failure exit returning 0, a bind
instantiating nothing, a watchdog counting a stopped clock, an `$isunknown`
check under two-state simulation, and a comparison of a net with itself. The
simulator reported none of them. Each was found by breaking the mechanism and
confirming the run failed.

The `branch_id` defect had the same property at the design level. The TAGE
suite passed because it never varied the input the defect affected. The
cluster test that found it presented back-to-back requests with distinct
indices, which is the traffic the check exists for.

In this project a check counts only after it has been shown to fail. A new
test is run against a design that violates it, a new harness demonstrates a
non-zero exit once, and when one instance of a silent-pass defect is found,
the unit is swept for the class and the count reported, including a count of
zero.

## What comes next

At the close of the range the cluster is verified at its boundary, and the
unit's pass results are enforced. The testbench acts as the FTQ. The next
range specifies and builds the FTQ itself.

Several items are open. TD #39 is answered by measurement and needs a
parameter decision. TD #100, whether TAGE is under-covered or its headline
figure is dominated by testbench lines, needs a decision; BP-097 measured
8,043 of `cov_tage`'s 8,700 lines in `tb_tage.sv`. Watchdog limits are not
uniform, and the completion times behind them need re-measuring before a ratio
rule is written. The session-063 cluster decisions are recorded only in
handoff-064 and `ftq_bpu_interfaces.md`.[F3]

## Technical Debt Referenced

The table below reports status as of the close of this range. Later
experiments outside the range have since changed the state of some items.

| # | Item | Resolution path |
|---|---|---|
| 1 | NUM_PRED_SLOTS=1 reduction. | New blocker from session 064: tb_bp_cluster indexes generate blocks by literal and stops at elaboration if NUM_PRED_SLOTS is not 2. |
| 39 | SC arbiter starvation override reachability. | Answered BP-094: with SC_PRED_CREDITS=4 the starvation counter reaches 4 and resets, so it never reaches SC_STARVE_THRESH=8. H6 proves the implemented arm, not reachability. Needs a parameter decision. |
| 67 | TAGE sram_init non-fast path. | Now extends to the cluster, whose targets use all three fast-init plusargs. A short init walk would also make the SC arbiter's sc_ready guard reachable from the ports. |
| 100 | TAGE line coverage below the stated 90%. | cov_tage 73.8% (6418/8700), a new baseline after tage_assert.sv entered the compile. 8043 of the 8700 lines are tb_tage.sv. Genuine under-coverage or accounting artifact is unresolved. |
| 102 | bp_history does not generate IT5 folds. | IT5 indexes on the PC alone. Add fold generation as for IT1 to IT4. |
| 105 | loop_pred dual-slot retrofit. | CLOSED BP-091. |
| 106 | Retire one of lp_pred_t / bp_loop_meta_t. | CLOSED BP-092. bp_loop_meta_t and lp_to_meta() deleted. |
| 107 | bp_cluster.sv stale comments. | CLOSED BP-092. BP-092a corrected four more of the same class. |
| 108 | p1 output group: block successor or fall-through. | CLOSED BP-092. bpu_pred_pft_p1 added. |
| 109 | tb_tage binds tage_assert to an instance name. | CLOSED BP-096. Repaired to the module name with tb.tage_assert_inhibit. Five binds in 46 files; class bounded at two. |
| 110 | ittage_assert_bind.sv compiled by no target. | CLOSED BP-096 by deletion, ordered by the task and not authorized; not a precedent. |
| 111 | Testbenches without a watchdog. | CLOSED BP-097. All 18 swept; four added in BP-096, four repaired in BP-097. A watchdog is a time delay, never a cycle count. |

## References

[1] IEEE Std 1800, IEEE Standard for SystemVerilog, clause 23.11, "Binding
auxiliary code to scopes or instances."

- The Branch Prediction Cluster: Built and Not Yet Run (BLOG_bpu_19), for the
  cluster this range simulates and the three abandoned tasks whose work BP-090
  carried.

- External Anchors: When a Proof and Its Reference Share the Same Error
  (BLOG_bpu_16), for an earlier check whose two sides came from the same
  source.

## Footnotes

<!-- ticfinder_off -->
[F1] Later sessions revised this value. Prediction blocks begin at any 2-byte
address, and the miss case now uses the lookup PC plus 32 bytes rather than
the block-aligned PC (session 069).

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
