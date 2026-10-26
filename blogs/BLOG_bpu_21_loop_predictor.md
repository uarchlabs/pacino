<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

```
TITLE:     "Closing Predictor Technical Debt in LP, TAGE and SC"
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

# Closing Predictor Technical Debt in LP, TAGE and SC

## Abstract

During frontend testing the simulations showed the loop predictor was unable to
produce high confidence predictions and its predictions were ignored.  The
problem was lack of speculation in the iteration count, and repeated
overwriting of the count and confidence with stale updates.

The usefulness of the LP was improved by changing to a read-before-write
semantic in updates, addition of a speculative counter with checkpoint
based save and restore, and reducing the priority of TAGE/SC predictions when
there is a high confidence LP prediction.

The second half of this session was used for technical debt closure. There
were 16 items, most closed as specified.

BP-122 concerned the loop predictor and the addition of assertions. BP-126
addressed 16 known RTL/verification debt items, including the SC update queue
implementation. BP-127 modified the SC indexing scheme.

## The loop predictor

### Observed tight loop behavior

A loop prediction is used only when its entry's confidence is high. In the
initial design the iteration count advanced only when a branch resolved. In
a tight loop several iterations are predicted before the first resolves, so
the count lagged the loop. Each update also rewrote the entry's count and
confidence from the snapshot taken at its prediction.
Confidence never reached the threshold, so the loop
predictor trained but its predictions were never used (TD#169).

### The fix

A speculative iteration count now advances at prediction, at p2, after a p2
re-read of the entry. A checkpoint per FTQ entry is written at p2. After a
redirect, the redirecting block's count is restored from its checkpoint and
every other count is marked unknown until its next exit. This closed TD#7.

The update now reads the entry before writing it, in one cycle with no
bubble, and trains from the iteration number carried with the prediction.
No update overwrites a more recent one.

A change was also made to direction priority. Previously TAGE at p2 and SC
at p3 could override a high confidence LP prediction.

I ruled that a high confidence LP prediction should out rank both.
`fe_decisions.md` section 3.3 was modified and the RTL was built to that
ruling. The LP prediction also outranks an FTB fast-path direction. The
direction ranking is now LP, SC, TAGE, FTB.

### Loop predictor results

The predictor is trusted after five exits at the earliest. This was later than
BP-121's warm-up points. Programs `lp` and `loops` were lengthened and their
warm-up points moved. Both columns run the lengthened programs, and the before
column is the final RTL.

| Program | Cycles | Mispredicts | After warm-up | LP directions, p1 / p2 |
|---|---|---|---|---|
| `lp` | 550 to 513 | 19 to 13 | 7 to 1 | 0 / 0 to 94 / 86 |
| `loops` | 556 to 537 | 22 to 18 | 2 to 1 | 0 / 0 to 56 / 49 |

In each program, the one conditional that still mispredicts after warm-up is
the outer loop's final exit. The other 17 programs did not change.
`tb_loop_pred` grew to 9,408 checks, covering the read before write, the p2
re-read, restore and invalidation. `tb_bp_cluster` gained 20 checks of the
priority and both restore paths. Each new case was shown failing against the
received RTL, or, where it used the new ports, against a mutation of the final
RTL.

## Assertions for the previous task's fixes

The purpose of TD#170 was addition of a property (assertion) for each BP-121
fix in units with an existing property file.

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

The loop predictor's new behavior has properties LP1 and LP2, and the FTQ's
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

`sim_main_predecode.cpp` and its build directory were deleted, and the bpu
targets no longer leave `obj/` or `waves.fst` in the tree.

`tb_fe_top` had a mode that ran every program in one simulation, carrying
predictor tables between programs. It was removed. A reset between programs
would have had to be forced into every RAM by the testbench, since the FTB
has no reset and the other tables are filled once by fast-init plusargs.

TD#165 reported that `ras.sv` repairs the stack wrongly when a slot's branch
type at p3 differs from its type at p2. That cannot happen, because the p3
type is the p2 type registered, so I closed it as unreachable by
construction.

The regression passed all 123 targets.

## Closing the predictor debt

BP-126 took the sixteen open predictor RTL and verification items in the
technical debt table as one task. Most closed as specified and are listed
only in Technical Debt Referenced at the end of this post. The findings
below were not expected. The task ran in automated mode, so its three
design choices were taken provisionally, and I confirmed all three.

### The tagged counters stepped the wrong way

`tage_cntrl` stepped each tagged counter up when the prediction was correct
and down when it was wrong. The predicted direction is the counter's top
bit, so a correct not-taken prediction at 3'b011 became 3'b100, which
predicts taken. `tage_table_entry_formats.md` says the counter steps toward
the resolved direction. Taken entries step the same way under both rules,
so only not-taken entries were affected. No unit test had failed, because
the counter tests encoded the same rule as the controller. A new test
written from the entry format failed seven of nine cases on the unfixed
controller, all of them not-taken. ITTAGE was not changed: its counter is a
target confidence, not a direction.

### The folds through the hashes

`tb_bp_cluster` now keeps its own model of the global and path history,
written from `bp_history_decisions.md` and driven from the cluster nets that
feed `bp_history`, not from `bp_history`'s state. From it the monitor
computes the index and tag that every table using a history fold should
receive, and compares them on every prediction, including after rollbacks.
With the starting `bp_history.sv`, IT5's index fold read 0 where the model
expected 0x100.

### The SC index formula and its prose

Writing the SC part of that model, the IA found that
`sc_table_hash_rules.md` gave two rules. The formula shifts `inp_pc_p2`,
which is already PC[VA_WIDTH-1:1], right by `PC_HASH_SHIFT` of 2, so the
index starts at PC[3]. The prose says the shift drops only the instruction
offset, which with the C extension is PC[0]. The RTL followed the formula.
The IA reported the conflict as PD-17 for a ruling, covered in the next
section.

### Coverage and accuracy

TAGE's 73.8% line coverage (TD#100) was partly an accounting effect. The
`.info` file counts a line as covered only when it is hit in every
instance, so a line hit in T1 to T3 and not in T4 read as uncovered. The
rest were real gaps, now tested. The TAGE RTL reads 588 of 614 lines, and
each uncovered line is listed with the reason it cannot be reached.

All 36 programs retired exactly the same instructions before and after.
Three items moved the cycle and mispredict figures, attributed by removing
each from the final tree: T0's reset to weakly taken, the SC update queue,
which changed training timing, and the counter direction fix. The largest
changes were 81 fewer cycles in `loops` and 14 more mispredicts in
`region`.

BP-126 passed with 155 targets. Each of 27 reversions, run on scratch
copies of the final tree, failed the check for its rule.

## The SC index

I ruled for the prose, for the SC only. TAGE and ITTAGE keep
`PC_HASH_SHIFT`. Each SC table's 9-bit index moves from PC[11:3] to PC[9:1].

`inp_pc_p2` is the block start PC, the same on both slots, so the change
separates blocks, not branches. ST0, a PC slice with no fold, now separates
blocks whose starts differ only in bits 2:1, but aliases blocks 1 KiB apart
rather than 4 KiB apart. ST1 to ST3 XOR the same PC bits with their folds.
The trade was unmeasured when I ruled.

BP-127 changed one line of `sc_table.sv`, and no port changed. A new
`tb_sc_table` test checks ST0 and ST1 indices worked out by hand for two
block starts that differ only in bits 2:1. On the starting tree both give
the same ST0 index. The `tb_bp_cluster` monitor moved to the new rule and
now covers ST0.

| Program | Cycles | Mispredicts | After warm-up |
|---|---|---|---|
| `hist` | 889 to 871 (-18) | 27 to 22 (-5) | 5 to 1 |
| `lp` | 458 to 427 (-31) | 10 to 8 (-2) | 1 to 1 |
| `misp_call` | 509 to 492 (-17) | 23 to 22 (-1) | 16 to 15 |
| `multistart` | 440 to 412 (-28) | 6 to 7 (+1) | 1 to 2 |
| `ftbonly` | 525 to 525 (0) | 10 to 11 (+1) | 1 to 2 |
| `recur` | 763 to 765 (+2) | 28 to 28 (0) | 17 to 17 |

The other 30 programs did not change, and all 36 retired exactly. Restoring
only the old index line restored every baseline. A trace of ST0 sharing
shows both sides of the trade. In `hist` and `lp`, block starts that had
shared an entry no longer do. In `ftbonly`, whose code repeats at 2 KiB
intervals, every copy now lands on the 1 KiB alias, and up to 9 block
starts share an entry. No technical debt item was opened for the `ftbonly`
alias.

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| BP-122 | Loop predictor in use; properties for the BP-121 fixes; three cleanups; five declarations reported | PASS | 123/123 targets; tb_loop_pred 9,408; tb_bp_cluster 1,998; 20 property and loop predictor mutations caught, H2 not shown alone | 1h 59m 49s | 65% |
| BP-126 | Sixteen predictor RTL and verification items; D-1 counter direction | PASS | 155/155 targets; 27 reversions caught; 36 programs retire exactly | 1h 57m 4s | 68% |
| BP-127 | PD-17: SC index PC term PC[9:1] | PASS | 155/155 targets; 6 reversions caught; 2 starting-tree runs fail | 32m 0s | 18% |

## Design Process Notes

### The IA contribution

The IA used the mutation process from previous sessions [1]. After fixing
and testing the RTL, it reverted the fix in a scratch copy and confirmed
that the test failed.

Some fixes added new ports, and the checks for those fixes used the new
ports. A check like that cannot compile against RTL with the fix reverted.
For these checks, the IA changed the logic in a scratch copy of the final
RTL instead of reverting the fix. A reversion is preferred because it tests
the original defect. The IA reported which checks were tested this way.

Correctness in this project is checked against the planning documents.
Duplicate planning content without the full context will mislead the IA. In
BP-126 the IA read the copy of the TAGE counter update table in
`tb_tage_manual_tasks.svh`, which has no legend, and reported a conflict
between `tage_cntrl_ctr_update_rules.md` and `tage_table_entry_formats.md`.

### The PA contribution

In these sessions the IA was given more autonomy to propose and implement
provisional solutions to problems. The PA wrote the three task files and
recorded each result in the planning documents. BP-126 and BP-127 were written
as problems: each states what must be true at the end and leaves method and
order to the IA. A defect found while working a problem is in scope and fixed
in the run.

BP-121's task asked for package changes but not for port declarations, so
its new ports were reported by name only. Every task now requires each
port added, removed or changed to be reported with its declaration.

The PA made three errors. It suggested sharing the loop predictor table
between slots, which would create the write conflicts the per-slot banks
avoid. Its first argument for PD-17 said the PC bits separate branches in a
block. The SC's PC is the block start, and the two planning documents it
took the error from were corrected. While writing BP-127, it took an answer
I had given about a different item as approval, opened a technical debt
item, and wrote an SC fold change into six planning documents and the task.
All of it was reverted. I have no firm evidence for the cause; context load
is one possibility.

### My contribution

After BP-121 I ruled the loop predictor's read-before-write update, reversing
my earlier ruling to leave it as specified, and accepted the possible speedpath
cost.

In BP-122 I chose the restore scheme, ruled that a trusted loop prediction
outranks TAGE and SC, approved lengthening `lp` and `loops`, and closed TD#165.

I set BP-126's scope, confirmed its three provisional choices, ruled PD-17 for
the prose and for the SC only, and withdrew the SC fold change written without
my ruling.

### The generalization

In these sessions five implementations contributed to performance loss.
Every program still retired correctly, because a predictor that is idle or
wrong costs cycles, not results, so retirement checks could not find them.
Three were already known. Two were found by checks written from the
planning documents rather than from the RTL.

- Loop predictor: already known (TD#169), found by counting how many of its
  predictions were used.
- TAGE counter direction: found by a new unit test written from the entry
  format document.
- SC index: found while writing the monitor's model from
  `sc_table_hash_rules.md`.
- IT5 folds: already known (TD#102). The fold monitor confirmed it: the
  index fold read 0 where the model expected 0x100.
- SC queue: already known as a stub (TD#123).

In this project a predictor check takes its expected value from the
planning document, and a predictor that receives updates is reported with
how many of its predictions were used.

## What comes next

At the close of the tasks in this range every predictor is in use, every
predictor RTL and verification item in the technical debt table is closed, and
the regression passes all 155 targets. TD#168, the FTB's shared jump field, was
kept by ruling at the time and later closed by BP-140. The next session works
through the remaining open technical debt items.

## Technical Debt Referenced

The table below reports status as of the close of session 077. Later
experiments outside the range have since changed the state of some items.

| # | Item | Resolution path |
|---|---|---|
| 7 | Loop predictor speculative count rollback undefined. | CLOSED BP-122. Checkpoint per FTQ entry; the redirecting block's count is restored, other counts are marked unknown. |
| 37 | `trx_type` stability through `tage_cntrl`. | CLOSED BP-126, negative result: `trx_type` is read only at entry. |
| 38 | Verilator 5.048 covergroup support. | CLOSED BP-126: ignored with a warning, no coverage recorded. Revisit on a Verilator after the fix for issue 7099 [2]. |
| 67 | TAGE `sram_init` non-fast path. | CLOSED BP-126: `sim_tage` runs the walk with an init check. |
| 68 | ITTAGE `sram_init` non-fast path. | CLOSED BP-126: `sim_ittage` runs the walk; `sim_bp_cluster_init` added. |
| 69 | TAGE fold recompute after rollback. | CLOSED BP-126: fold monitor in `tb_bp_cluster`. |
| 70 | ITTAGE fold recompute after rollback. | CLOSED BP-126: fold monitor in `tb_bp_cluster`. |
| 75 | No fast ITTAGE target. | CLOSED BP-126: `sim_ittage_fast`. |
| 81 | `tb_ftb` coverage skews to br0. | CLOSED BP-126: 35 br1 checks. |
| 84 | Fold traced end to end, producer to consumer. | CLOSED BP-126: fold monitor in `tb_bp_cluster`, every prediction. |
| 100 | TAGE line coverage below the stated 90%. | CLOSED BP-126: per-file table, RTL 588/614, every uncovered line explained. |
| 101 | `ras.sv` declares `ras_pc_p2` and never reads it. | CLOSED BP-126: removed. |
| 102 | `bp_history` generates no IT5 folds. | CLOSED BP-126. |
| 103 | TAGE T0 resets strongly not taken. | CLOSED BP-126: T0 resets to 2'b10, `TAGE_T0_SRAM_INIT_VALUE`. |
| 104 | Stale FTB header comments. | CLOSED BP-126. |
| 121 | A full RAS commit stack reads as empty. | CLOSED BP-126: occupancy count beside CSP. |
| 123 | SC update queue not built at the unit level. | CLOSED BP-126: 8-entry queue in `sc.sv`. |
| 165 | RAS repair wrong when a slot's p2 and p3 branch types differ. | CLOSED by ruling, session 076: unreachable by construction. |
| 168 | FTB entry shares one jump field per region. | KEPT by ruling at session 077 (`ftb_decisions.md` 4.6). Later closed by BP-140, session 081. |
| 169 | Loop predictor trained, never used. | CLOSED BP-122. |
| 170 | No assertions for the BP-121 fixes. | CLOSED BP-122. H2 not shown firing alone; RS1 fires in `tb_ras` only. |

## References

[1] "Branch Prediction Cluster Simulation and Mutation-Based Verification"
[BLOG bpu/20](https://uarchlabs.github.io/blog/branch-prediction-cluster-simulation-and-mutation-based-verification/). Accessed 2026-10-26.

[2] Verilator issue 7099, "Support covergroup coverpoint bins with sample()
and get_inst_coverage()",
https://github.com/verilator/verilator/issues/7099.

---
<!-- ticfinder_off -->

*Jeff Nye is a microprocessor architect with 35 years of industry experience
spanning performance modeling, RTL implementation, and architecture for
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,
TI C6x and RISC-V designs, and recently served as sole architect and full-stack
implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue
RVA23 RISC-V processor - from research through timing closure at 2.75 GHz. He
holds +20 issued patents in processor design, architecture, and hardware
virtualization. He is the author of Pacino and the uarchlabs methodology
documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
