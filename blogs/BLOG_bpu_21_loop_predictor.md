<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

```
TITLE:     "Putting the Loop Predictor in Use and Closing the Predictor Debt"
FILE:      BLOG_bpu_21_loop_predictor.md
AUTHOR:    Jeff Nye
DATE:      2026-10-19
STATUS:    REVIEW BEFORE POSTING
COPYRIGHT: "Copyright 2026 Jeff Nye"
```

<!--
---

::SERIES DESCRIPTION::
::BEGIN LINKS::
::END LINKS::
-->

# Putting the Loop Predictor in Use and Closing the Predictor Debt

## Abstract

When the front end first ran programs end to end, the loop predictor
received 1,193 updates and none of its predictions was used. Each update
rewrote the entry from a snapshot taken at prediction, and many iterations
of a loop are predicted before the first update arrives, so the iteration
count never settled.

BP-122 built the update I ruled after that run. The update reads the entry
before writing it, and each prediction carries its iteration number. A
speculative iteration count advances at p2, is checkpointed per FTQ entry,
and is restored on a redirect. Two further rulings were needed in the run:
how the count is restored, and whether a trusted loop prediction outranks
TAGE and the statistical corrector (SC). In `lp`, mispredicts after warm-up
fell from 7 to 1, and in `loops` from 2 to 1. No other program changed. The
same task added a property for each fix of the previous end-state task, and
showed each property firing with its fix reverted.

BP-126 took every open predictor RTL and predictor verification item, sixteen
in all, as one task. Most closed as specified. This post reports what was
not expected. The tagged TAGE counters stepped by whether the prediction
was correct, not toward the resolved direction, and every unit test passed
because the tests encoded the same rule. The TAGE coverage shortfall carried
from the cluster simulation post was partly a counting rule and partly real
gaps. Verilator 5.048 ignores covergroups. The new SC update queue changed
training timing enough to move mispredicts by up to 14 in a program.

BP-126 also found that the SC index formula and its prose disagreed about
which PC bits the index takes. I ruled for the prose, and BP-127 moved the
SC index from PC[11:3] to PC[9:1]. Six of 36 programs changed, and putting
the old index line back restored every baseline.

## Where the range starts

The previous bpu post ended with the branch prediction cluster verified at
its boundary and its testbench standing in for the fetch target queue (FTQ).
The fetch series then built the FTQ, the instruction fetch unit and the rest
of the front end, and ran it as one design. BP-121, the first end-state task,
drove 19 programs through the front end, fixed 16 defects, and reported the
figures for each program and each predictor.

Two of BP-121's results concern this post. The loop predictor trained in
every program and was never used. The 16 fixes were covered by testbench
checks, and none had a property (TD#170). I had ruled during BP-121 to leave
the loop predictor as specified, so that end-state item was reported as
blocked by my ruling. After the run I reversed that ruling, and BP-122 was
written to build the new one.

The range covers sessions 076 and 077. The fetch tasks of session 077,
BP-123 to BP-125, ran between BP-122 and BP-126 and are covered in the
fetch series. By BP-126 the regression ran 36 programs, not 19, and the
figures below for BP-126 and BP-127 use the 36.

## The loop predictor

### Why it was never used

A loop predictor records, for a loop-closing branch, how many times it is
taken before it falls through, and predicts the exit when the current
iteration reaches that count. The current iteration count is the state that
matters. In the version BP-121 tested, each update rewrote the entry from
the snapshot captured at prediction, and the prediction read `curr_itr`, a
count maintained at resolution.

In a loop of a few instructions, several iterations are predicted before the
first of them resolves. Each resolution then wrote back an entry built from
a snapshot older than the entry's current state, and the prediction read a
count several iterations behind the fetch stream. The count never settled,
the confidence never reached the trust threshold, and the predictor's
direction was never chosen. This was TD#169. TD#7, the rollback of the
speculative count, had been open since the predictor was specified, because
the inline count fields had no defined checkpoint or restore path.

### The ruled update

I ruled the update after BP-121. It reads the entry before writing it, in a
single cycle with no bubble. A prediction in the same cycle as an update to
its entry sees the old value. Each prediction carries its iteration number,
and a speculative iteration count is built with it. The table is flops.
Physical design bounds the number of entries, and the cost in maximum
frequency is accepted.

The ruling as first recorded also said that slot 1 wins when both slots
update one entry. The loop predictor table is one bank per slot (TI6), and
each slot predicts from and updates only its own bank, so no shared entry
exists for the rule to apply to. BP-122's task file states the bank rule and
that the table is not to be shared between slots.

BP-122 built the update in `loop_pred.sv`. The update looks the tag up again
rather than trusting the way carried from prediction, recomputes the victim,
and trains from the iteration number the prediction carried in
`lp_pred_t.lp_curs` and `lp_curs_v`. An exit at a known count equal to the
learned trip count raises confidence. A taken branch at or past the learned
count clears it. An update whose carried count is unknown trains nothing.
No package changed: the iteration number rides in fields `lp_pred_t` already
had. The IA proposed retiring the snapshot fields the update no longer
reads, which would shrink the FTQ metadata. I left them.

### The speculative count and its restore

The count advances at p2 by the p2 direction, after a new p2 re-read of the
entry, `pred_p2`. The p1 direction is an early guess from the p0 read, which
in a one-block loop can be up to two iterations stale; p2 corrects it, at the
cost of a p2 redirect at a loop exit rather than a backend mispredict. The
checkpoint lives in `loop_pred`, one per bank and `FTQ_DEPTH` deep, written
at p2, in the same way `bp_history` keeps its own checkpoint per FTQ index.

How the count is restored after a redirect was the first design choice the
task put to me in session. The IA gave three options:

- A: restore the redirecting block's own entry exactly from its
  checkpoint, and mark every other count unknown on an FTQ-raised rollback,
  so each resynchronizes at its next exit. Two new FTQ-to-cluster ports.
- B: as A, but mark unknown only the entries a squashed block advanced. A
  pointer per entry, about 4 kbit, and 512 range compares.
- C: walk the squashed blocks and undo each advance exactly, over several
  cycles.

I chose A. Before my answer to the third question, the IA prototyped B on a
scratch copy. It gave the same `lp` and `loops` figures as A, with the
predictor trusted from the sixth outer iteration in both. The stated cost of
A is that a loop whose run contains an unrelated backend or predecode
redirect loses one exit to resynchronize.

The two new ports are `ftq_rollback_slot_ex` and `ftq_rollback_slot_tkn` at
the `bp_cluster` boundary, one bit per slot. They mark which slots of the
rollback entry are conditionals the backend mispredict executed, and their
resolved directions. `ftq_npc` drives them, qualified by `rollback_corr`. On
`loop_pred`, `rst_val`, `rst_idx`, `rst_ex` and `rst_tkn` restore from the
checkpoint, and `inv_val` marks every count unknown.

### Which direction wins

The second choice was priority. Under `fe_decisions.md` 3.3, TAGE at p2 and
SC at p3 overrode the loop predictor's p1 direction, so a correct loop exit
could never remove the mispredict. The options were: the loop predictor wins
at p2 and p3; it wins over TAGE but SC may override it; or the rule stays and
the end state is reported unreachable. I ruled that a trusted loop
prediction wins at p2 and p3. The direction ranking is now loop predictor,
SC, TAGE, FTB.

### Warm-up

The third choice came from the programs. The predictor is trusted after five
exits at the earliest: one with no count, one to learn, and three to confirm.
BP-121's warm-up points, outer iteration 4 of 12 in `lp` and 2 of 8 in
`loops`, came before that. I approved lengthening both programs and moving
the warm-up: `lp` runs 16 outer iterations of a 10-iteration inner loop, with
warm-up at 8, and `loops` runs 14, with warm-up after 8.

The before column below is the received RTL with the final testbench, so
both columns run the lengthened programs. On the lengthened `loops`, TAGE
learns the 5-iteration exit by the eighth outer iteration on the received
tree, so BP-121's repeating `loops` exit mispredict at 0x18 does not occur
on either side. In `lp` the exit at 0x16 mispredicts six times after warm-up
on the received tree and at most once after the change.

### Results

| Program | Cycles | Mispredicts | After warm-up | LP directions, p1 / p2 |
|---|---|---|---|---|
| `lp` | 550 to 513 | 19 to 13 | 7 to 1 | 0 / 0 to 94 / 86 |
| `loops` | 556 to 537 | 22 to 18 | 2 to 1 | 0 / 0 to 56 / 49 |

The one conditional left after warm-up in each is the outer loop's final
exit. The other 17 programs gave identical figures before and after. In
both changed programs p2 redirects rose and p3 redirects fell (`loops` 64 to
68 and 32 to 27, `lp` 43 to 51 and 44 to 37), which is the early p1 guess
corrected at p2.

`tb_loop_pred` was reworked for the new update, from 9,342 to 9,408 checks.
Its new cases cover the read before write (TC19), order independence of
resolutions (TC20), the update looking the tag up again (TC21), the p2
re-read on back-to-back blocks (TC22), an unknown count not trusted (TC23),
restore from the checkpoint (TC24), invalidation (TC25 and TC26), and a
same-cycle prediction seeing the old value (TC27). The cases that use only
the old ports failed against the received `loop_pred.sv`. The cases that use
the new ports cannot be built against it, so each was shown failing by a
mutation of the final RTL instead. `tb_bp_cluster` gained group O, 20 checks
of the priority, the advance and both restore paths.

## Properties for the previous task's fixes

TD#170 required a property for each BP-121 fix in a unit with a property
file, compared against a source independent of the RTL that drives it, and
each shown firing on a scratch copy with its fix reverted. BP-121 had named
its fixes m01 to m15, and BP-122 reverted them by those names.

| Property | Unit | Fix reverted | Where it fired |
|---|---|---|---|
| R20 `a_every_rsv_written` | `ftq_resolve` | a mapped resolution does not write its slot | unit test, all 19 programs |
| E11 `a_rsv_end_kills_above` | `ftq_entry` | no clear above a resolved end | 10 programs |
| R21 `a_jump_ft_is_jump_end` | `ftq_resolve` | taken jump keeps the predicted fall-through | unit test, 17 programs |
| E13 `a_rsv_jump_ft_lands` | `ftq_entry` | resolved fall-through not written | unit test, 17 programs |
| F1 `a_no_update_after_request` | `ftq` | the hold before an FTB update removed | unit test, all 19 programs |
| N11 `a_mispredict_bundle` | `ftq_npc` | no corrected history bundle | unit test, all 19 programs |
| H1 `a_corrected_newest` | `bp_history` | corrected rollback ignored | unit test, all 19 programs |
| RS1 `a_dropped_p2_moves_nothing` | `ras` | `ras_p2_keep` ignored | `tb_ras` only |

The loop predictor's new behaviour has properties LP1 and LP2, and the FTQ's
new slot bits N12, each fired by its own mutation. Twelve mutations of the
new loop predictor logic, L1 to L12, each failed at least one check.

Two results are partial, and the IA reported both. H2, the `bp_history`
checkpoint rewrite, was never shown firing on its own: the mutation that
removes the rewrite also removes the corrected rollback, H1 fires first and
stops the simulation, and no mutation of the rewrite alone was run. H2 holds
in every run. RS1 fires only in `tb_ras`, in a new case TC-35, because the
cycle it covers, a p2 RAS operation dropped with no p3 repair, does not occur
in the 19 programs. The program-level check of that fix remains `tb_fe_top`'s
check that no squashed block performs a RAS operation.

## The rest of BP-122

The task carried three cleanups and a report.

`sim_main_predecode.cpp` and the build directory that named it were deleted.
The bpu targets no longer leave `obj/` or `waves.fst` in the tree; waves are
written only with `make sim_tage_manual FST=1`.

`tb_fe_top` had a mode that ran every program in one simulation, carrying
predictor tables from one program into the next. The task let the IA choose
between resetting predictor state between programs and removing the mode. It
removed the mode. The FTB array has no reset and the TAGE, ITTAGE and SC
tables are filled once at time zero by the fast-init plusargs, so a reset
between programs would have had to be forced into every RAM by the
testbench, modelling nothing the RTL does. Without `+PROG` the testbench now
fails and lists the programs.

BP-121 had named five interface details without declarations. BP-122 gave
each from the RTL as built: the rollback history-correction ports
`ftq_rollback_corr`, `ftq_rollback_n`, `ftq_rollback_tkn` and
`ftq_rollback_pbit` at the cluster boundary and their `bp_history`
counterparts, `bkend_ftq_redir_taken`, `ras_p2_keep`, how `w_jmp_ft_p2`
enters `w_pft_p2`, and whether `ftq_npc` holds the prediction request when
`sc_uq_not_full` is low. It does: `sc_uq_not_full` is a term of `ftq_npc`'s
hold, so the SC starvation hold withholds that p0 request, no block is at p2
two cycles later, and the SC arbiter grants the waiting update. No defect
was found.

TD#165, two wrong return-call repair pairings in `ras.sv`, was closed by
ruling as unreachable by construction. Both pairings need the p2 and p3
types of one slot to differ, and the p3 type is the type registered at p2.
BP-122 confirmed this from the RTL. `ras_decisions.md` 1 records the one
change that would reopen it: taking the p3 type from anywhere else.

The regression passed all 123 targets.

## Closing the predictor debt

BP-126 took every open predictor RTL item and every open predictor
verification item in the technical debt table, sixteen in all, as one task:
the IT5 history folds, TAGE T0's reset value, a full RAS commit stack, the SC
update queue, an unread RAS port, two FTB header comments, the TAGE and
ITTAGE `sram_init` path without fast-init plusargs, the history folds traced
through every index and tag hash, grant stability in `tage_cntrl`,
covergroups, `sim_ittage_fast`, slot-1 cases in `tb_ftb`, and TAGE line
coverage. It ran in automated mode, so the three design choices it met were
taken provisionally and recorded for me to confirm. I confirmed all three.

Most items closed as specified, and I list them only in the technical debt
table. The findings below are the ones that were not expected, with the two
items they came from.

### The tagged counters stepped the wrong way

`tage_cntrl` stepped each tagged counter up when the prediction was correct
and down when it was wrong. The predicted direction is the counter's top
bit, so a not-taken entry moved away from a not-taken outcome: a correct
prediction at 3'b011 became 3'b100, which predicts taken.
`tage_table_entry_formats.md` says the counter steps toward the resolved
direction. The taken cases give the same result under both rules, which is
why the defect showed only on not-taken entries.

No unit test had failed. The tests that covered counter updates encoded the
same rule as the controller, so the controller and its tests agreed with
each other and not with the document. A new test, `ctr_dir_tst`, drives
update-only cases for the provider, the alternate provider and the
non-provider step, taken and not taken. On the unfixed controller seven of
nine cases failed, all of them not-taken. The fix changed which way each
step goes and not which counter steps. Sixteen `tb_tage` tests and sixteen
`tb_tage_manual` rows had their expected values re-derived from their own
stimulus. ITTAGE was not changed: its counter is a target confidence, not a
direction.

The IA also reported that `tage_cntrl_ctr_update_rules.md` contradicted the
entry format document for the not-taken rows. It had read the copy of the
row table in `tb_tage_manual_tasks.svh`, which has no legend. Read with its
legend, INC strengthens and DEC weakens the entry in its current direction,
so every row steps toward the resolved direction and the documents agree. A
note was added to both documents and no row changed.

### What the coverage figure was measuring

The cluster simulation post left TD#100 open: `cov_tage` reported 73.8% of
lines, and whether TAGE was under-covered or the figure was an accounting
effect was unresolved. BP-126 found both.

The `.info` file counts a line as covered only when every coverage point on
it is hit, line and branch points alike and in every instance. One line of
`tage_table.sv` was hit 40, 30 and 10 times in the T1, T2 and T3 instances,
0 times in T4, and read as uncovered. That is why `tage_table.sv` read
125 of 172 lines in `cov_tage`, which has four instances, and 155 of 172 in
`cov_tage_table`, which has one.

There were also real gaps. The aging-interval decrement had never run,
although the coverage plan marked it covered, because every aging test
forced the interval to zero. Slot-1 allocation, slot-1 counter updates and
several T3 and T4 cases had no test. One more gap was a tool effect:
`ctr_step` written as `if`/`else` left two counters that Verilator never
increments once the function is inlined, and as one expression it does not.
After new tests and a second `cov_tage` run on the walk path, the TAGE RTL
reads 588 of 614 lines. Each of the 26 uncovered lines is listed with the
reason it cannot be reached: a `sram_init` delay state that TAGE's
`START_DELAY` of zero skips, the case arms of an elaboration constant that
each instance enters only once, a default arm for a table number never
instantiated, and alternate-provider write data in T4, which as the longest
table is never the alternate provider.

### Verilator and covergroups

TD#38 asked whether Verilator 5.048 supports covergroups. A minimal
covergroup compiled in the scratch directory reported every covergroup,
coverpoint and bin as ignored, which fails a `-Wall` build. With
`-Wno-fatal` it built and ran, and reported 0.00 coverage after the
coverpoint had taken all four values. Issue 7099 describes this behaviour
[1]. It was closed on 2026-06-06, after 5.048's release on 2026-04-26, and
5.048's change list has no covergroup entry. Covergroup coverage waits for
a later Verilator.

### Accuracy moved by items that do not change correctness

Every one of the 36 programs retired exactly the same instructions before and
after. Three items moved the figures, attributed by removing each from the
final tree in turn:

- T0 weakly taken. A cold T0 entry now predicts taken. Programs whose
  first-seen branches are taken gained: `loops` 81 fewer cycles, `lp` 58,
  `multistart` 21. Programs whose first-seen branches are not taken lost:
  `hist` 5 more mispredicts, `twocond` 4. Five `tb_tage` tests had relied
  on T0's old reset value and now seed the rows they read.
- The SC update queue. Updates are now accepted into an 8-entry queue at
  once and applied when the SC RAM port is free, rather than held at the
  producer until the arbiter grants them. Training timing changed: `hist`
  12 fewer mispredicts and `recur` 7 fewer, `region` 14 more and
  `misp_call` 6 more.
- The counter direction fix: between 3 fewer and 1 more mispredict per
  program.

The IT5 folds and the RAS occupancy count changed no figure in any program.
Why IT5 changes nothing in these programs was not investigated; the folds
themselves are checked.

The queue was built at the unit level, as the arbitration specification
describes and `sc.sv` had stubbed. Each entry holds one update cycle of both
slots, and two new ports, `sc_uq_has_data` and `sc_uq_rd_en`, connect it to
the cluster arbiter, whose rules did not change. Before `sc_ready` an update
is refused and held by its producer rather than ignored.

### The folds through the hashes

TD#69, TD#70 and TD#84 asked for the history folds to be traced through
every index and tag hash, end to end and after a rollback. `tb_bp_cluster`
now keeps its own model of the global and path history, written from
`bp_history_decisions.md` and driven from the cluster nets that feed
`bp_history`, never from `bp_history`'s state. From it the monitor computes
the index and tag every TAGE table, every ITTAGE table from IT1 to IT5 and
SC tables ST1 to ST3 should receive, and compares on every prediction. The
final run compared 589 TAGE and 589 ITTAGE predictions and 277 SC
predictions, including 3 first predictions after a rollback and 171 after a
corrected rollback. With the starting `bp_history.sv`, IT5's index fold read
0 where the model expected 0x100.

### The SC index formula and its prose

Writing the monitor's SC model, the IA found that `sc_table_hash_rules.md`
gave two rules. The formula shifts `inp_pc_p2`, which is already
PC[VA_WIDTH-1:1], right by `PC_HASH_SHIFT` of 2, so the index starts at
PC[3]. The prose says the shift drops the instruction offset, which with the
C extension is PC[0] alone. The RTL and the new monitor followed the formula.
The IA reported it as PD-17 for a ruling.

BP-126 passed with 155 targets, two more than at the start, and 27
reversions, each on a scratch copy of the final tree, each failing the check
for its rule.

## The SC index

I ruled for the prose, for the SC only. TAGE and ITTAGE keep
`PC_HASH_SHIFT`. The nine index bits of each 9-bit SC table move from
PC[11:3] to PC[9:1].

`inp_pc_p2` is the prediction block's start PC, the same value on both
slots. The two branches of a block are separated by the per-slot RAMs, not
by PC bits. The change is therefore about blocks. ST0, which is a PC slice
with no fold, now separates blocks whose starts differ only in bits 2:1,
which happens because blocks start at any halfword. It also aliases blocks
1 KiB apart rather than 4 KiB apart. ST1 to ST3 XOR the same PC bits with
their folds. The trade was unmeasured when I ruled.

BP-127 changed one line of `sc_table.sv` and a comment in
`bp_defines_pkg.sv`; no port changed. `tb_sc_table` gained a second table
instance with ST0's parameters and a test, TC7, that drives two block starts
differing only in bits 2:1, 0x8000_0A40 and 0x8000_0A46, and checks literal
indices: 0x120 and 0x123 for ST0, 0x125 and 0x126 for ST1. On the starting
tree both PCs give 0x148 in ST0. The `tb_bp_cluster` monitor moved to the
new rule and now covers ST0 as well. Six reversions on copies of the final
tree each failed their check, and the starting tree with only the new
testbenches copied in failed both times.

| Program | Cycles | Mispredicts | After warm-up |
|---|---|---|---|
| `hist` | 889 to 871 | 27 to 22 | 5 to 1 |
| `lp` | 458 to 427 | 10 to 8 | 1 to 1 |
| `misp_call` | 509 to 492 | 23 to 22 | 16 to 15 |
| `multistart` | 440 to 412 | 6 to 7 | 1 to 2 |
| `ftbonly` | 525 to 525 | 10 to 11 | 1 to 2 |
| `recur` | 763 to 765 | 28 to 28 | 17 to 17 |

The other 30 programs did not change, and all 36 retired exactly. With only
the index line put back on the final tree, all 36 gave their baselines
exactly, so every change comes from the index.

A trace on a scratch copy counted, for each program, the block starts that
share an ST0 entry under each rule. Both effects of the trade appear. In
`hist` and `lp`, two pairs of block starts differing only in bits 2:1 had
shared an entry, and now none share. In `ftbonly`, whose code is copied at
2 KiB intervals, every copy now falls on the 1 KiB alias, and block starts
share ST0 entries in groups of up to 9. `twocond` and `loops` show the SC's
behaviour moving with no change in their figures. The ruled paragraph in
`sc_table_hash_rules.md` now cites these figures. No technical debt item
was opened for the `ftbonly` alias.

BP-127 ran in 32 minutes at low effort. It found no other defect and put no
decision to me.

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| BP-122 | Loop predictor in use; properties for the BP-121 fixes; three cleanups; five declarations reported | PASS | 123/123 targets; tb_loop_pred 9,408; tb_bp_cluster 1,998; 20 property and loop predictor mutations caught, H2 not shown alone | 1h 59m 49s | 65% |
| BP-126 | Sixteen predictor RTL and verification items; D-1 counter direction | PASS | 155/155 targets; 27 reversions caught; 36 programs retire exactly | 1h 57m 4s | 68% |
| BP-127 | PD-17: SC index PC term PC[9:1] | PASS | 155/155 targets; 6 reversions caught; 2 starting-tree runs fail | 32m 0s | 18% |

## Design Process Notes

### The IA contribution

Each fix came with a check shown to fail before it. Where a new check could
not be built against the starting tree because it used new ports, the IA
said so and showed it failing by mutating the final RTL instead. BP-122 ran
20 mutations across the property files and the loop predictor, BP-126 27
reversions and BP-127 6, each on a scratch copy.

It reported what it could not show. H2 was never fired on its own, and the
IA said so with the reason rather than counting it with the rest. RS1 fires
in one testbench and not in the programs, and the report says why. The IT5
folds changed no figure, and the report says that was not investigated.

It measured before a ruling rather than after. It prototyped restore option
B on a scratch copy before I answered the third question, so the choice
between A and B was made knowing the figures were the same. Every change in
a program's figures was attributed by removing one item from the final tree
and rerunning, not by inference.

The IA made one reporting error. In BP-126 it read a
copy of a rules table without its legend and reported a conflict between
two documents that do not conflict. The defect it found, D-1, was real; the
document conflict was not.

At the end of BP-122 two wait loops were still running. Each polled with
`pgrep -f` for the mutation script, and the pattern also matched the loop's
own command line, so neither could exit. The IA stopped them and, when I
asked, saved the case to its memory. BP-126 and BP-127 state the rule: a
wait waits on a job's exit status or a file the job writes, not on
`pgrep -f`.

### The PA contribution

The planning assistant wrote the three task files and recorded each result
in the planning documents named by the IA's proposals: fifteen documents
after BP-122, and the PD-1 to PD-16 and PD-1 to PD-4 changes after BP-126
and BP-127.

BP-121's task had asked for package changes with reasons but not for ports
with declarations, so five interface details came back as names. BP-122
asked for those five, and every task since requires every port added,
removed or changed with its declaration as built.

The planning assistant had listed TD#168 as open when I had ruled to keep
it, and had left TD#165 out of BP-122's scope. TD#168 was relabelled as kept
by ruling and not open work, and TD#165 was closed by ruling. The planning
assistant also offered sharing the loop predictor table between slots as an
option, which would create the write conflict the per-slot banks exist to
avoid. BP-122 states that the banks stay one per slot.

BP-126 and BP-127 were written as problems: each states what must be true at
the end, and leaves method and order to the IA. A defect found while working
any problem is in scope and fixed in the run. A rule examined and found
already met is a completed item, which is how TD#37 closed as a negative
result.

The planning assistant's first argument for PD-17 was wrong: it said the PC
bits separate branches in a block. The SC's PC is the block start, the same
on both slots. Two planning documents called `inp_pc_p2` the staged branch
PC, and the planning assistant had taken the error from them. Both were
corrected, and the corrected reasoning is the one above.

While writing BP-127, the planning assistant opened a new technical debt
item and wrote a change to the SC folds into six planning documents and the
task, taking an answer I had given about a different item as approval. I had
not ruled it, and the SC worked as built. All of it was reverted, the item
number was freed, and BP-127 carries PD-17 alone.

### My contribution

I ruled the loop predictor's update after BP-121, reversing my in-run ruling
to leave it as specified, and accepted the frequency cost and a bounded entry
count. I kept the table one bank per slot. In BP-122 I chose restore option
A, ruled that a trusted loop prediction wins at p2 and p3, and approved
lengthening `lp` and `loops`. I closed TD#165 as unreachable by construction
and left `lp_pred_t`'s unread fields in place.

I set BP-126's scope as every open predictor RTL and verification item,
confirmed its counter direction fix and its two other provisional choices,
and accepted its sixteen document changes. I ruled PD-17 for the prose and
for the SC only. I withdrew the SC fold change written without my ruling.

### The generalization

Every item in this range, known or found, left the programs correct. The
loop predictor trained for a whole run and contributed nothing. The IT5 folds
were never driven. The SC queue was a stub. The tagged counters stepped away
from not-taken outcomes. The SC index used different PC bits from the ones
its document described. In each case every program retired exactly, because
a predictor that is idle or wrong costs cycles, not results.

Retirement checks therefore could not find any of them. The unit tests did
not find the two defects found in the range, because each test encoded the
implementation it tested: the counter tests stepped the counters the way the
controller did, and the SC index models shifted the PC the way the RTL
did.

What found them was a check written from the document and not from the RTL:
literal expected indices worked out by hand from the PCs, a history model
fed from the cluster's nets rather than from `bp_history`, a counter test
derived from the entry format's stated rule, and per-predictor counts of
predictions used. In this project a predictor check takes its expected value
from the planning document, and a predictor that receives updates is
reported with how many of its predictions were used.

## What comes next

At the close of the range every predictor is in use, every predictor RTL
and verification item in the technical debt table is closed, and the
regression runs 155 targets green. The largest remaining source of
mispredicts is the FTB's shared jump field, kept by ruling (TD#168).[F1] The
next session scrubs the remaining open technical debt item by item.

## Technical Debt Referenced

The table below reports status as of the close of session 077. Later
experiments outside the range have since changed the state of some items.

| # | Item | Resolution path |
|---|---|---|
| 7 | Loop predictor speculative count rollback undefined. | CLOSED BP-122. Checkpoint per FTQ entry, restore option A. |
| 37 | trx_type stability through tage_cntrl. | CLOSED BP-126, negative result: trx_type is read only at entry. |
| 38 | Verilator 5.048 covergroup support. | CLOSED BP-126: ignored with a warning, no coverage recorded. Revisit on a Verilator after the fix for issue 7099. |
| 39 | SC arbiter starvation override reachability. | CLOSED, moot, session 076: BP-121 replaced the credit rules, and the parameter relationship no longer exists. |
| 67 | TAGE sram_init non-fast path. | CLOSED BP-126: sim_tage runs the walk with an init check. |
| 68 | ITTAGE sram_init non-fast path. | CLOSED BP-126: sim_ittage runs the walk; sim_bp_cluster_init added. |
| 69 | TAGE fold recompute after rollback. | CLOSED BP-126: FOLD monitor in tb_bp_cluster. |
| 70 | ITTAGE fold recompute after rollback. | CLOSED BP-126: FOLD monitor. |
| 75 | No fast ITTAGE target. | CLOSED BP-126: sim_ittage_fast. |
| 81 | tb_ftb coverage skews to br0. | CLOSED BP-126: 35 br1 checks. |
| 84 | Fold traced end to end, producer to consumer. | CLOSED BP-126: FOLD monitor, every prediction. |
| 100 | TAGE line coverage below the stated 90%. | CLOSED BP-126: per-file table, RTL 588/614, every uncovered line explained. |
| 101 | ras.sv declares ras_pc_p2 and never reads it. | CLOSED BP-126: removed. |
| 102 | bp_history generates no IT5 folds. | CLOSED BP-126. |
| 103 | TAGE T0 resets strongly not taken. | CLOSED BP-126: T0 resets to 2'b10, TAGE_T0_SRAM_INIT_VALUE. |
| 104 | Stale FTB header comments. | CLOSED BP-126. |
| 121 | A full RAS commit stack reads as empty. | CLOSED BP-126: occupancy count beside CSP. |
| 123 | SC update queue not built at the unit level. | CLOSED BP-126: 8-entry queue in sc.sv. |
| 165 | Two RAS return-call repair pairings wrong. | CLOSED by ruling, session 076: unreachable by construction. |
| 168 | FTB entry shares one jump field per region. | KEPT by ruling (ftb_decisions.md 4.6); not open work.[F1] |
| 169 | Loop predictor trained, never used. | CLOSED BP-122. |
| 170 | No properties for the BP-121 fixes. | CLOSED BP-122. H2 not shown firing alone; RS1 fires in tb_ras only. |

## References

[1] Verilator issue 7099, "Support covergroup coverpoint bins with sample()
and get_inst_coverage()",
https://github.com/verilator/verilator/issues/7099.

- Branch Prediction Cluster Simulation and Mutation-Based Verification
  (BLOG_bpu_20), for the cluster testbench this range extends and the TAGE
  coverage question TD#100 answered here.

- Building the Fetch Unit and Running the Front End End to End
  (BLOG_fetch_4), for BP-121, whose loop predictor result and fixes this
  range takes up, and for BP-123 to BP-125, which ran between BP-122 and
  BP-126.

## Footnotes

<!-- ticfinder_off -->
[F1] TD#168 was closed by BP-140 (session 081).
<!-- ticfinder_on -->

---
<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
