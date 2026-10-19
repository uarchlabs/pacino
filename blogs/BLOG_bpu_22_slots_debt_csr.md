<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

```
TITLE:     "One or Two Prediction Slots, the Last Front-End Debt and a CSR Definition"
FILE:      BLOG_bpu_22_slots_debt_csr.md
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

# One or Two Prediction Slots, the Last Front-End Debt and a CSR Definition

## Abstract

`NUM_PRED_SLOTS` sets how many branches the predictor reports per fetch
block. It was meant to take 1 or 2 and only 2 worked. BP-128 made both
values work from one macro in `bp_defines_pkg.sv` and added a one-slot twin
of every lint and simulation target, 106 in all. At two slots nothing
changed. At one slot every program retired exactly, and several took up to
80% more cycles, because a block's second branch has no slot.

Two tasks then sized the branch history path by the slot count. The first
found that at one slot the history correction after a mispredict sometimes
needs two bits, and that carrying one cost mispredicts. I ruled that the
correction carries up to two bits at either slot count, and the second task
restored every one-slot figure exactly.

A measurement task, BP-131, counted how often a block holds more branches
than slots, how often a region's shared block end is rewritten by another
start, and how long a branch waits between resolution and commit. The
counts showed that these directed programs cannot decide the slot
questions, and I deferred them to compiled benchmarks.

Five tasks closed the remaining front-end debt. This post reports what was
not expected: a T0 counter that was read as the wrong 3-bit value, a RAS
undo that lost recursion levels, test rows that seeded states no
prediction produces, slot-1 update paths whose removal passed the full
regression, and a decode speed-up that was a compiler cache.

Two system tasks replaced the configuration and control signals that
testbenches had driven individually with packages built from a new CSR
definition. One program changed by 40 cycles because it had set a CSR state
that no software write can produce.

## Where the range starts

The previous bpu post ended with every predictor in use and every open
predictor RTL and verification item closed. The fetch series had built the
rest of the front end, and the regression ran 155 targets, including 36
`tb_fe_top` programs that run instructions through the whole front end
against a testbench backend.

Session 078 began with a scrub of the technical debt table, led by me, item
by item. Several items closed by ruling with no task. Two decisions from
that scrub shaped the range: the one-slot build (TD#1) would be made real,
and the remaining front-end items would be closed before the CSR definition
(TD#178). The scrub also created a second table, Performance and
Verification Debt, for items that need benchmark data rather than a fix.

## One source for the slot count

The ruling for BP-128 had four parts: the values are 1 and 2, with 2 the
default; the value is set in one place, from a macro; every lint and
simulation target of the bpu, FTQ and `fe_top` units passes at both values;
and every new target joins the regression.

`bp_defines_pkg.sv` now takes `NUM_PRED_SLOTS` from `BP_NUM_PRED_SLOTS`,
defaulting to 2. A package-scope check stops elaboration at any other
value. Verilator rejects an elaboration `if` with `$error` at package scope,
so the check is a constant function that reaches `$fatal`. A second macro,
`BP_EXPECT_PRED_SLOTS`, makes the package stop unless the slot count equals
it. Each one-slot target, `<target>_1slot`, sets both. To show that each
was built at one slot, the IA rebuilt all 106 with the slot macro removed,
and all 106 stopped with "NUM_PRED_SLOTS 2, expected 1".

Ten modules lost their own slot parameter. Five of them had a literal
default of 2 and so ignored the package: `tage`, `tage_cntrl`, `tage_table`,
`tage_bim` and `ittage_table`. `ittage.sv` never overrode the last of these,
so `ittage_table` had been two-slot at any package value. `loop_pred` had a
literal 1 that `bp_cluster` overrode. `ubtb` kept a parameter, renamed
`N_SLOTS` with the package default, because `tb_ubtb` builds a uBTB at each
width in every build. The update queue write-port counts of TAGE, SC and
ITTAGE were literal 2 and now follow the slot count; `sc.sv` requires its
count to equal the slot count, so lint failed at one slot without this.

The IA swept the RTL of the three units for patterns that assume two slots
without naming the parameter, read all 239 hits, and changed 37 sites. The
largest were the copied slot-0 and slot-1 blocks in the TAGE, ITTAGE and SC
tables, each now one generate loop. No port was added, removed or
re-declared at either value.

At two slots, 150 of the 155 baseline logs were identical after removing
time and path lines. The other five were coverage targets whose line
totals fell because the copied blocks became loops; their check counts
were unchanged. At one slot every testbench passed. Each check that needs
two slots prints a SKIP line and is named with its count. Two checks in
`tb_loop_pred` had printed PASS at one slot without running anything, and
were fixed.

Every program retired exactly at one slot. The cost appeared where a block
holds two conditionals, or a conditional and a jump:

| Program | Cycles, 2 slots | Cycles, 1 slot | Mispredicts, 2 / 1 |
|---|---|---|---|
| `twocond` | 533 | 952 | 11 / 36 |
| `indir` | 1164 | 1668 | 24 / 71 |
| `hist` | 871 | 1057 | 22 / 42 |
| `multistart` | 412 | 647 | 7 / 19 |
| `recur` | 765 | 1139 | 28 / 24 |

The IA ran automated and took its design choices provisionally. Two
carried the rest of the range. The history bundle and FTQ rollback ports
stayed two wide at both values (D1). The FTB and uBTB entries kept two
conditional fields at one slot, so the second branch of a block is not
predicted and the backend corrects it (D2), which is where the one-slot
cycles come from. The planning assistant pointed out that a third, D4,
gated two loop predictor checks in `loops` that do not depend on having two
slots: at one slot the unslotted branch after the loop branch has its
resolution placed into the loop branch's slot, and the loop predictor never
becomes trusted there. The IA had stated that link as inferred, not traced.
I ruled D1 to be fixed, deferred D2 with the block split to TD#179, and
accepted D3 to D5.

## The history correction at one slot

BP-129 sized the history inputs and the FTQ rollback ports by
`NUM_PRED_SLOTS`, with a new package width `PRED_CNT_BITS` for the counts.
To make the second-branch logic exist only at two slots, the IA rewrote
`bp_history`'s two hand-written per-branch blocks as one loop over branches
with a new function, `fold_all_step`. That also did the cleanup recorded as
TD#82.

The task asked whether one case occurs: at one slot, a backend mispredict
of a branch that no slot held, so that `ftq_npc`'s correction is two bits,
a not-taken bit for slot 0 and then the mispredicted branch. It occurred 72
times in seven programs. A one-bit port cannot carry both, and the IA
listed four choices with their effect on the history. It built the only one
that fits the port and keeps the resolved direction as the newest history
bit: the mispredicted branch's bit alone. The cost against the old two-wide
port was more mispredicts at one slot in six programs, from `rvc` 18 to 26
and `indir` 71 to 86.

I ruled that this was not acceptable for performance, and that the
correction carries up to two bits at either slot count: at most one
not-taken bit before the mispredicted branch's bit. It is not one bit more
than the slot count; at two slots it stays two bits. BP-130 added
`RB_CORR_BITS` = 2 and `RB_CNT_BITS` = 2 to the package and widened the
correction path from `ftq_npc` through `ftq`, `fe_top` and `bp_cluster`
into `bp_history`, including the per-checkpoint bundle size `ckpt_nb`. The
prediction inputs stay sized by the slot count.

All 72 two-bit corrections then reached `bp_history`, and every one-slot
figure returned exactly to its value before BP-129. Nothing changed at two
slots. The history properties H1 and N11 now check every bit of the
correction; before BP-130 neither could see the older bit of a two-bit
correction at one slot, and each was shown firing on that bit by a fault on
a scratch copy. The IA also reported that `bp_history_decisions.md` 3.5
says the checkpoint needs no slot count, while the RTL has stored a
per-checkpoint bundle size since BP-121.

## What the programs can decide

Before building the block split of `ftb_decisions.md` section 3, in which a
block ends after as many branches as there are slots, I asked for
measurements. BP-131 changed nothing in the tree. It added read-only
monitors to a scratch copy of `tb_fe_top`, confirmed that every program
gave its baseline figures with them, and counted per program at both slot
counts.

- Blocks with more branches than slots: 9 at two slots, all in `twocond`,
  and 243 at one. No region in these programs holds three conditionals, so
  the FTB never had to replace a conditional field. At two slots the split
  would change almost nothing here.
- A backend mispredict costs 11.1 cycles on average at two slots and 11.3
  at one, with a maximum of 20, over the 21 programs without page walks or
  uncached fetch. The planning assistant had estimated 8 to 12.
- Block ends shared in a region: 73 of 260 FTB entries were hit by more
  than one block start, up to six. About 92% of the changes to an entry's
  block end were made by a start other than the previous writer. In every
  over-capacity block where another start's end was recorded, the end a
  split would write differs from it: 228 of 228 at one slot. With the
  current entry format, a split would add more rewriting of that shared
  value. This is the region sharing behind TD#168.
- Training from another branch's metadata, through the placement rule for
  a resolution that matches no slot: 27 times at two slots and 312 at one.
- Wrong-path training could not be measured. The testbench backend
  resolves only retired instructions, in program order.
- Resolution to commit: 6.4 cycles on average at two slots. Even in that
  window, 1,566 of 2,846 branches had their FTB region read again before
  commit, and for 876 of them the resolution had already changed the
  entry. Training at commit would have shown those reads older state. A
  core with a reorder buffer has a longer window.

The counts also showed two behaviours the questions had not asked about.
The uBTB stored one branch in both of its conditional fields 82 times at
two slots, because it fills the field the update's slot names without
checking the other. The placement rule displaced a later branch while a
slot was free 31 times at two slots.

I concluded that the `tb_fe_top` programs are directed tests, written to
reach particular cases, and not representative enough to decide the block
split, the entry format or the training point. Those decisions moved to
TD#179, in the new performance table, to be measured against compiled
benchmarks.[F1]

## The last front-end debt

Five tasks closed what remained: BP-132 to BP-136. Most items closed as
specified and are listed only in the technical debt table. The findings
below are the ones that were not expected.

### A decode speed-up that was a cache

TD#131 recorded that decode's wall time fell from 90 to 29 seconds when
the unit moved from Verilator 5.020 to the project's 5.048, with identical
check counts. The 5.048 installation sets `OBJCACHE ?= ccache` and the
5.020 installation leaves it empty. Without the cache, 5.048 was slower on
the same source: `rtl/lib` built in 13.6 seconds against 11.6. A decode
build takes about 42 seconds cold and 4 seconds warm. Decode times are now
compared only with the cache state stated.

The same task found two coverage tool problems outside its write access:
`tools/cov_table.py` measures TAGE coverage from `tage.sv` only, which
misses the arbitration that moved into `tage_arb.sv` in the same task, and
the bpu coverage targets run `verilator_coverage` 5.020 from the path on
data from the 5.048 build. It also removed GNU `objcopy` from the RVC
expander oracle; the regenerated oracle was byte-identical.

### Items that were not defects

TD#79 said the RAS commit stack did not preserve recursion depth because
its recursion field was never read. BP-133 found that the commit stack has
no recursion compression: every committed call gets its own entry, so
depth is kept by repetition, and the fallback is not degraded. The field
was dead storage and was later removed. The planning text describing the
limitation was wrong.

TD#89 and TD#90 asked for 22 bits per FTB entry to supply the SC update's
branch PC slice and backward-branch sign. Both values have been formed by
`ftq_upd_conv` since BP-119, from the FTQ entry's block PC, the slot
position and the resolved target, which the backend sends as the taken
target even for a not-taken branch. The rows predated the converter. No
FTB bits were added.

### The T0 counter

T0, the TAGE base table, has 2-bit counters; the tagged tables have 3-bit
counters. BP-133 found one T0 update case undefined: T0 as the provider
when the use-alt-on-new-allocation counter picks it over a weak tagged
primary. The RTL never wrote T0 in that case. The IA built rows 19.1 to
19.8, in which T0 steps toward the resolved direction, with a second write
path into `tage_bim`. I kept the fix.

The same task found a defect on the prediction side. When T0 provides the
prediction, its counter was zero-padded and then decoded as a 3-bit tagged
counter. A T0 at 2'b11, strongly taken, read as 3'b011, weak not taken, and
gave SC a negative TAGE term. Every T0-provided prediction was affected,
and no test covered it. I ruled the mapping {ctr[1], ctr[0], ctr[0]}, which
gives the exact 3-bit equivalents, and BP-134 built it as TD#182. One
cluster test, G3, had been written around the defect and was reseeded.

The fix changed ten programs at two slots. `hist` went from 22 to 31
mispredicts, while `ftbonly`, `indir` and `loops` improved. Each program
still retired exactly; SC now overrides T0 in different cases. That is
TD#183, for the benchmark analysis.

BP-135 then checked the rows 19.x tests themselves. All eight seeded the
tagged primary at 3'b010, and use-alt-on-new-allocation cannot fire on
that value; four also gave a predicted direction that 010 cannot produce.
The results were right because the update path acts on the metadata as
given, but the states were ones no prediction reaches. After reseeding to
reachable states, all eight rows fail with the T0 path removed; the
original seeding had caught six. A new program, `t0_uaon`, reaches the case
end to end, 17 times at two slots and 16 at one. In 13 of the 17 events at
two slots T0 was already saturated, so only four of them distinguish the
fix from its absence.

### The RAS recursion count

The RAS compresses a recursive call into a count on one entry. TD#78 had
recorded that an undo of a pop that decremented a count did not restore
it. BP-133 found the case reachable since BP-121: SC can make a return
reachable at p2 and unreachable at p3, and the undo then runs. The IA
registered what each p2 operation did to the counts and reversed it in the
undo.

BP-134 added a program for it, `rec_undo`, in which a function calls
itself six deep and a conditional before each return is taken one time in
four. At two slots the program reaches the case ten times, and each undo
restores the count. With the fix removed on a scratch copy, the program's
count check fails all ten, but its mispredicts do not rise. The counts were
already being lowered by wrong-path pops, because a mispredict restore
reloads the RAS pointers and not the counts held in the entries. That is
TD#184. At one slot the case cannot occur: a return never shares a block
with a branch before it, so the p3 view always matches p2.

BP-134 also found that an undo of a push that met a saturated count of 15
lowered a count the push had never raised. It was fixed with a registered
flag.

### A test-order dependence

102 of `tb_tage`'s 117 tasks changed their stimulus in the same time step
as the clock edge that sampled it, so the result depended on process order
within the time step. BP-134 moved every wait to the edge plus one time
unit. The results were unchanged except one count: a monitor's prediction
grants went from 163 to 162, because a test entered on the edge had staged
its probe request twice. The race had made one test's stimulus depend on
how the previous test ended.

### Slot-1 updates no check reached

TD#74 asked what covers the slot-1 update paths of TAGE and ITTAGE. BP-135
removed each path on a scratch copy and ran the full regression. Removing
every TAGE slot-1 table write failed 15 checks. Removing only the slot-1 T0
writes, or every ITTAGE slot-1 write, passed all 272 targets. Only the
program figures moved: with no ITTAGE slot-1 updates, `indir` went from 22
to 70 mispredicts, and no check failed. The programs exercised those paths;
nothing compared their result.

BP-135 was written to report, not to fix, so the gap stayed open and BP-136
was needed. It runs `tb_tage_manual`'s counter, useful and new
use-alt-on-new-allocation tests on each slot, reading back the RAM copy of
the slot it drove and checking that the other slot's copy keeps its seed.
It makes the epoch write visible by giving each slot a different epoch.
For ITTAGE, two new `tb_ittage` tests drive slot-1 updates through the
arbiter, the controller and the tables, one of them through the update
queue. Twenty-four mutations, one per path, each fail a check, and both
mutations that passed in BP-135 now fail. No RTL defect was found.

BP-136 found that `tage_cntrl` updates the use-alt-on-new-allocation
counter only when the alternate is a tagged table, while its rule document
also updates it with a T0 alternate. I ruled the RTL correct, and the
document was changed.

BP-135 also checked an ITTAGE interface note against the RTL and found four
of its seven statements false; the useful and epoch writes open on the
provider's counter strobe, not on the primary selector alone. No RTL was
wrong.

## The CSR definition

The front end has two groups of inputs that will come from control and
status registers. A configuration group holds the predictor enables and
aging intervals and decode's extension enables. A CSR group holds the
privilege level, the virtualization bit, the address translation registers
and the PMP registers. Until this range each testbench drove these as
individual ports, with its own values.

`csr_decisions.md`, written in session 079, defines both groups. Two custom
machine-level CSRs hold the configuration: 0x7C0 the four predictor enables
and 0x7C1 the two aging intervals. The extension enables are not a CSR. The
standard CSRs are the implemented subset of satp, vsatp, hgatp, menvcfg,
henvcfg, pmpcfg0, pmpcfg2 and pmpaddr0 to 15, with the write rules the
privileged specification gives for them [1]. Addresses and bit positions
were checked against Spike's `encoding.h` [2] and the riscv-opcodes CSR
table [3]. Three group structs, `fe_cfg_t`, `fe_csr_t` and `ptw_csr_t`,
carry the members to `fe_top`, the ITLB and the walker.

SYS-001 built `csr_pkg` with the layouts and the structs, the struct ports
on `fe_top`, the ITLB, the PMP checker and the walker, and `csr_tb_pkg`, a
testbench shadow of every CSR that applies the write rules and packs the
groups. All 15 testbenches that drove a group member now take it from
`csr_tb_pkg`. The shadow is a class with static members. Written as plain
package functions, it was inlined at every call site and the `tb_fe_top`
C++ compile ran past five minutes before it was stopped.

The inventory showed five testbenches resetting to values different from
`tb_fe_top`'s, including `tb_bp_cluster` with the SC disabled. Each now
resets through `csr_tb_pkg` and then writes its own value.

One program changed. Case 3 of `pt_ad_h` had given the walker
henvcfg.ADUE = 1 with menvcfg.ADUE = 0. No CSR write can produce that state,
because henvcfg.ADUE reads 0 while menvcfg.ADUE is 0. Through `csr_tb_pkg`
the case now sees ADUE 0 at both stages, takes a VS-stage page fault in
place of a G-stage guest-page fault, and skips one G-stage translation.
`pt_ad_h` went from 1,435 to 1,395 cycles at both slot counts. The task had
defined any figure change as a defect, and the IA reported it as one. I
accepted it.

The IA also reported three rules from the privileged specification that
`csr_decisions.md` lacked: henvcfg.PBMTE reads 0 while menvcfg.PBMTE is 0,
a pmpcfg entry with R = 0 and W = 1 is reserved, and an entry's pmpaddr is
not writable when the next entry is locked TOR. I added all three, and
SYS-002 built them. The planning assistant had predicted that the PBMTE
rule would change two tests, as ADUE had. Neither changed: the walker uses
henvcfg.PBMTE only for a VS-stage leaf's PBMT, and in both tests that leaf
is 0.

SYS-001 had also cost coverage. The PMP checker tests now received pmpaddr
as software reads it back, so they no longer exercised the checker's own
masking of the low address bits. SYS-002 restored it by writing and
packing at a granule of zero, so the checker at its real granule receives
the bits as written; removing the checker's masking fails six of the new
checks, while the old ones still pass. The NA4 half of the request could
not be checked at that granule, because NA4 and NAPOT use the same mask
there.

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| BP-128 | NUM_PRED_SLOTS 1 or 2 from one macro; one-slot targets | PASS | 261/261; 106 _1slot targets fail with the macro removed; 36 programs retire at 1 | 59m 13s | 54% |
| BP-129 | History and rollback ports sized by NUM_PRED_SLOTS | PASS | 261/261; 72 two-bit cases counted; H1, N11 fired at 1 | 68m, IA from timestamps | 54% header, 31% context report |
| BP-130 | Two-bit history correction at either slot count | PASS | 261/261; 72 of 72 reach bp_history; one-slot figures restored | 36m | 19% |
| BP-131 | Measurement: blocks over capacity, region sharing, resolve to commit | PASS | 261/261 at both ends; tree unchanged | 48m 27s | 32% |
| BP-132 | Clean-up: TD#49, 52, 77, 129, 130, 131, 147, 176, 177 | PASS | 265/265; t_fill_rpl 31 checks | 54m 34s | 36% |
| BP-133 | TD#18, 78, 79, 89, 90 | PASS | 265/265; rows 19.x fail 6 on the old RTL; tb_ras fails 4 on the old RTL | 46m 17s | 30% |
| BP-134 | TD#182 T0 mapping; RAS saturation; rec_undo; tb_tage race | PASS | 267/267; pred_t0_conf_tst fails 24 on the starting tree; rec_undo fails 10 of 10 without the TD#78 fix | 1h 46m 52s | 40% |
| SYS-001 | csr_pkg, csr_tb_pkg, struct ports, 15 testbenches | PASS | 270/270; tb_csr_tb_pkg 126; pt_ad_h 1435 to 1395 | 1h 24m 44s | 100%+5%, 1 compaction |
| SYS-002 | Three CSR-5 rules; PMP checker coverage | PASS | 270/270; tb_csr_tb_pkg 150; 6 new PMP checks fail under the masking mutation | 31m 14s | 25% |
| BP-135 | Clean-up batch; t0_uaon; TD#74 report | PASS | 272/272; sim_tage_manual 472; t0_uaon 17 and 16 events | 1h 23m 31s | 36% |
| BP-136 | Slot-1 TAGE and ITTAGE update checks | PASS | 272/272; 24 path mutations fail; both BP-135 passing mutations now fail | 50m 58s | 35% |

From BP-132 on, runtimes come from the task's start and end timestamps.
For BP-132 the IA corrected the tool's 26m 10s, which ended the run at the
first scheduled wakeup, to 54m 34s. BP-134 left the header status box
unticked; I accepted the task.

## Design Process Notes

### The IA contribution

The IA showed every new check failing before its fix, on a scratch copy of
the starting tree or by a mutation of the final one, and said which. It
showed that each one-slot target was really built at one slot by removing
the macro and watching all 106 stop. It attributed each figure change by
removing one item from the final tree. In BP-131 it confirmed that its
monitors left every program's figures unchanged before reporting a count,
and its before-and-after checksum of the repository found five files
changed outside the task during the run, which it reported and did not
revert.

It found defects while doing other work: the T0 decode while fixing the T0
update, the saturated undo-push while fixing the recursion undo, the
uBTB duplicate and the placement displacement while counting something
else, and three missing privileged-specification rules while building the
CSR package. It also corrected the premises it was given. It showed TD#79
and TD#89 and TD#90 were not defects, that the PBMTE rule changed no test,
and that four tests already reached the guest-page fault the task asked it
to add.

Two tasks, BP-133 and BP-134, edited RTL while their own baseline
regression was still running in the same tree. Each stopped the run,
restored the files and ran the baseline again, and each said so. From
SYS-002 on, every task required the baseline to finish before any edit.

### The PA contribution

The planning assistant wrote the eleven task files and drafted the
planning document changes after each task. Each task was written as
numbered problems with acceptance criteria, and left method and order to
the IA.

BP-135's TD#74 problem was written to report only, so the slot-1 gaps it
found could not be closed in that run, and BP-136 was needed. Every task
file now carries the rule that a defect found is fixed in the run, with a
check that fails first, and marked provisional where no planning document
sets the fix.

Several task statements rested on readings the planning assistant had not
checked. BP-133 was written from the debt table rows alone, and said so;
three of its five items turned out not to need RTL. BP-135's rows 19.x
claim came from reading BP-133's report and was confirmed by the IA.
SYS-002's prediction that the PBMTE rule would change two tests was taken
from SYS-001's report without reading how the walker uses PBMTE, and was
wrong. Its request to check NA4 handling at the checker's real granule
asked for a distinction that does not exist there.

`csr_decisions.md` was rewritten several times before I accepted it. The
final form states the organization, the implemented bits and the
connection to the RTL, with no narrative, no history, no provenance
identifiers and the references at the end. That is now the form for every
planning document written for the IA.

### My contribution

I ruled the slot count values, the one-source macro, and that every target
passes at both values. I ruled BP-128's D1 to be fixed, deferred D2 with
the block split, and accepted D3 to D5. I rejected the one-bit history
correction at one slot as costing too much and ruled the two-bit
correction at either slot count. After BP-131 I ruled that the directed
programs cannot decide the slot questions and moved them to compiled
benchmarks under TD#179. I created the Performance and Verification Debt
table.

I closed several items by ruling in the scrub, including TD#40, 43 and 97,
and accepted BP-132's provisional choices, including keeping the cluster's
boundary port names. I set BP-133's five items with freedom to find, fix
and measure; kept its T0 and RAS fixes; closed TD#79 and had the dead
field removed; and closed TD#89 and TD#90 without FTB storage. I ruled the
T0 mapping and opened TD#183 and TD#184.

For the CSR definition I ruled that it covers both groups, placed the
custom CSRs at 0x7C0 and 0x7C1, ruled that the extension enables are not a
CSR, that the ports become struct types and that the reset values come
from `tb_fe_top`. I accepted the `pt_ad_h` change and added the three
missing rules. I folded TD#74 into BP-135, kept it open after that task,
and ruled that the RTL is correct on the use-alt-on-new-allocation update.

### The generalization

Three kinds of result in this range were not what a passing regression
implies.

Tests exercised states the design cannot reach. The rows 19.x tests seeded
a primary counter that use-alt-on-new-allocation cannot fire on, and passed
because the update path does not re-check its inputs. `pt_ad_h` configured
a CSR state no software write can produce. Both gave correct results for
inputs that never occur.

Paths were exercised and not checked. With every ITTAGE slot-1 update
removed, a program's mispredicts nearly tripled and all 272 targets still
passed. With the RAS undo fix removed, `rec_undo`'s mispredicts did not
move; only a direct count check saw it. A figure that moves is not a
failure unless a check compares it.

A question was beyond the tests. The block split, the entry format and the
training point are performance decisions, and programs written to reach
particular cases do not weigh them as a workload would.

In this project a test's stimulus must be a state the design can produce,
a path counts as covered only when removing it fails a check, and a
measurement decides a design question only when its workload represents
the target.

## What comes next

At the close of the range the slot count works at 1 and 2, every
front-end technical debt item outside the performance table is closed, and
the regression runs 272 targets. The front end takes its configuration
and CSR state from packages built from one definition. The slot decisions,
the T0 mapping's effect on SC and the RAS recursion counts on wrong paths
wait on compiled benchmarks and a backend model (TD#179, TD#183, TD#184).
The rest of session 080 built a front-end demonstration, the subject of
the next post.

## Technical Debt Referenced

The table below reports status as of the close of session 080. Later
experiments outside the range have since changed the state of some items.

| # | Item | Resolution path |
|---|---|---|
| 1 | NUM_PRED_SLOTS = 1 reduction. | CLOSED BP-128. One macro; 106 _1slot targets. |
| 18 | T0 update side undefined. | CLOSED BP-133. Rows 19.1 to 19.8; tests reseeded by BP-135. |
| 49 | TAGE and ITTAGE queue-status pin names. | CLOSED BP-132. Cluster boundary names kept by ruling. |
| 52 | TAGE and ITTAGE arbitration in the top modules. | CLOSED BP-132. tage_arb.sv, ittage_arb.sv. |
| 74 | Slot-1 TAGE and ITTAGE update path coverage. | CLOSED BP-136. 24 path mutations fail. Not covered: ITTAGE uaon[1], slot-1 prediction-side effects. |
| 77 | Absolute paths in prompts. | CLOSED BP-132. Every path is a record of a past run. |
| 78 | RAS undo-pop does not reverse a recursion pop. | CLOSED BP-133. Exercised end to end by rec_undo (BP-134). |
| 79 | RAS commit-stack recursion depth. | CLOSED BP-133, not a defect. commit_rctr removed by BP-134. |
| 82 | bp_history per-branch blocks. | CLOSED BP-129. One loop, fold_all_step. |
| 89 | SC branch_range from the FTB. | CLOSED BP-133 without FTB storage. Formed by ftq_upd_conv. |
| 90 | SC backwards_branch from the FTB. | CLOSED BP-133 without FTB storage. |
| 129 | Top-level Makefile targets. | CLOSED BP-132. all and cov retired; clean reaches every unit. |
| 130 | Regression report gaps. | CLOSED BP-132. |
| 131 | Unexplained decode speed-up. | CLOSED BP-132. ccache in the 5.048 installation. |
| 147, 176 | Out-of-repository tool path. | CLOSED BP-132. RVA_EXT_TOOLS in rtl/Vars.mk. |
| 168 | FTB entry shares one jump field per region. | KEPT by ruling; measured again by BP-131.[F2] |
| 177 | L1I install-time replacement gate untested. | CLOSED BP-132. t_fill_rpl. |
| 178 | CSR definition. | CLOSED SYS-001. csr_decisions.md, csr_pkg, csr_tb_pkg. |
| 179 | One- and two-slot performance: block split, entry shape, region sharing, uBTB duplicate fill, placement, training point. | OPEN, DEFERRED to compiled benchmarks.[F1] |
| 182 | T0 counter decoded as a 3-bit tagged counter. | CLOSED BP-134. {ctr[1], ctr[0], ctr[0]}. |
| 183 | hist mispredicts after the T0 mapping. | OPEN, performance. |
| 184 | RAS recursion counts lowered on wrong paths. | OPEN, performance. Measure first. |

## References

[1] RISC-V Privileged Architecture, ISA manual v20260120,
https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html, for the
CSR fields and write rules csr_decisions.md implements.

[2] Spike RISC-V ISA simulator, `riscv/encoding.h` and `riscv/csrs.cc`,
https://github.com/riscv-software-src/riscv-isa-sim, against which the CSR
addresses and bit positions were checked, and whose pmpcfg write handling
the NA4 and R = 0, W = 1 rules follow.

[3] riscv-opcodes, `csrs.csv`, https://github.com/riscv/riscv-opcodes, for
the CSR addresses.

- Putting the Loop Predictor in Use and Closing the Predictor Debt
  (BLOG_bpu_21), for the predictor state this range starts from.

- Building the Fetch Unit and Running the Front End End to End
  (BLOG_fetch_4), for the `tb_fe_top` programs, the end-state task method
  and the L1I replacement reversion that TD#177 records.

## Footnotes

<!-- ticfinder_off -->
[F1] BP-138 (session 081) changed part of TD#179: a jump behind as many
conditionals as there are slots now ends the predicted block at the jump,
and the next block places it in slot 0. The other items remain open.

[F2] TD#168 was closed by BP-140 (session 081), which gives each block
start its own FTB entry.
<!-- ticfinder_on -->

---
<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
