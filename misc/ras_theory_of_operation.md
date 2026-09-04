<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

title: "RAS -- Theory of Operation"
author: Jeff Nye
date: 2026-06-28
copyright: "Copyright 2026 Jeff Nye"

<!--
```
 FILE:    ras_theory_of_operation.md
 SOURCE:  derived from session-050 / BP-062..BP-064
 STATUS:  DRAFT
 UPDATED: 2026-06-25
 CONTACT: Jeff Nye
```
-->

## RAS Theory of Operation

This is a theory of operation description of the return address stack,
a component in the BPU that assist call/return predictions. The tone
diverges from other blogs; this is less a postmortem of the co-design
of the RAS and more of a description of its operation with references
to the planning documents that were used in RAS creation and testing.

There will be a postmortem as well.  This is a descriptive companion 
to the canonical RAS records.  Where this document and the canonical 
records differ, the canonical records take precedence:

- `planning/arch/ras_decisions.md`   -- micro-architectural decisions
- `planning/interfaces/ras_interfaces.md` -- port and contract spec
- `rtl/core/frontend/bpu/rtl/ras.sv`  -- implementation
- `rtl/core/frontend/bpu/tb/tb_ras.sv` -- directed tests (TC-01..TC-21)

Stage notation: planning text uses `s0..s3`; RTL and port names use
`p0..p3`. They are equivalent (`s0=p0`, ... `s3=p3`). This document
uses `s`-notation in narrative and `p`-notation when naming ports,
consistent with existing practice.

---

## 1. What a RAS is for

A return is an indirect branch whose target is, in principle, always
determined: it is the address immediately following the matching call.
A general indirect predictor can learn return targets, but it does so
as one additional history-indexed pattern, and it mispredicts whenever
the same function is called from more than one site, which is the
common case. The information required to predict a return is structural
rather than statistical. Calls and returns nest in last-in-first-out
order, so a stack reconstructs the target exactly: the return address
is pushed when a call is predicted and popped when a return is
predicted, and the value at the top of the stack is the predicted
target.

On typical code, a return address stack predicts returns with an
accuracy approaching 100 percent. The design complexity arises in two
areas in which this abstraction does not hold:

1. **Speculation.** A modern front end pushes and pops on predicted
   call/return flow, many cycles before the prediction is confirmed. A
   mispredicted path corrupts the stack by pushing spurious entries or
   popping valid ones. The structure must therefore restore a
   known-good state at low cost on every pipeline redirect.

2. **Capacity and reuse.** The stack is finite. Layered software
   (runtime, framework, libraries, operating system) keeps tens of
   frames live at steady state in the absence of recursion, and
   recursion can push the same address repeatedly. The structure must
   degrade in a controlled manner on overflow and must avoid consuming
   one entry for each repetition of an address.

The pacino RAS is organized around these two requirements. The
remainder of this document describes the implemented design, the
alternatives that were evaluated, and the corresponding choices made in
industry and in the literature.

---

## 2. Role and context in pacino

The RAS is one of seven predictors in the BP cluster (uBTB, Loop, FTB,
TAGE, SC, ITTAGE, RAS). It predicts only the target of return-type
indirect branches and does not predict branch direction.

It is positioned outside the conditional-branch override chain
(`SC > TAGE > FTB > uBTB`) and is instead type-gated: it operates only
when the FTB structural prediction classifies a branch as a call (push)
or a return (pop). The RAS does not classify instructions; the branch
type is supplied on its ports by the FTB. Classification follows the
RISC-V register convention rather than the opcode alone:

- **Call (push):** `JAL`/`JALR` with `rd = x1` or `x5`; `C.JALR`.
- **Return (pop):** `JALR`/`C.JR` with `rs1 = x1` or `x5`, and
  for `JALR` only when `rd` is not itself a link register
  (`rd != x1`, `rd != x5`, or `rd == x0`). `C.JALR` with
  `rs1 = x5` is excluded from the return class. The `rd`
  qualifier is what keeps the classes disjoint: without it a
  `JALR rd=x1, rs1=x1` would satisfy both rules above.

This is one branch of a three-way classification of all `JALR`-class
branches: the FTB handles indirect branches with a single stable
target, the RAS handles those that match the return convention, and
ITTAGE handles the remaining history-dependent indirect targets. The
three classes are mutually exclusive and are resolved by the FTB before
s2.

The RAS participates at three pipeline points (Figure 1). At **s0** it
presents a combinational read of its current top-of-stack as the
earliest available return target, before the FTB has resolved; this
read is the initial prediction used by the FTQ. At **s2**, once the FTB
confirms the branch type, the RAS executes the authoritative push or
pop and drives the return target into the s2 redirect when the FTB,
TAGE, or RAS result disagrees with the uBTB s1 result. At **s3** (s2
registered) the RAS performs a repair pass that reverses an s2
operation when the registered prediction no longer agrees with it.

![Figure 1. RAS position in the BP prediction pipeline](fig1_pipeline_position.svg)

*Figure 1. The RAS contributes at s0 (top-of-stack read), s2
(authoritative push/pop and redirect participation), and s3 (repair).
It is gated by the FTB branch type and is located outside the
conditional-branch override chain.*

The RAS contains no PQ, UQ, or credit arbiter, and no synchronous
SRAMs. Both stacks are register files. Its update mechanism is pointer
snapshot and retirement rather than a RAM write, as described in
Section 3.6.

---

## 3. Current design

### 3.1 Two physical stacks, statically partitioned

The RAS contains two independent register-file arrays (Figure 2):

- a **16-entry speculative stack**, a simple circular buffer that
  tracks in-flight call depth between fetch and commit; and
- a **32-entry commit stack**, a conventional circular stack that holds
  the architectural (committed) call nest.

The partition is static: 16 + 32 entries in two separate arrays rather
than a shared pool. The advantage is that each event affects exactly
one array. Each array wraps at its own fixed limit, with no shared
moving boundary to check; a mispredict restore reaches only the
speculative array; commit advancement reaches only the commit array.
Pointer arithmetic and the verification surface both remain small. The
48-entry total is sufficient that a shared pool would provide no
measurable benefit (Section 4).

Each entry, in both stacks, is a return address (`VA_WIDTH = 40b`) plus
a 4-bit recursion counter (`rctr`). The values are fixed in
`bp_defines_pkg.sv`; the two pointer widths are `localparam` derived by
`$clog2` from the depths above them, not independently set:

| Parameter | Value | Meaning |
|---|---|---|
| `RAS_SPEC_ENTRIES`   | 16 | speculative stack depth |
| `RAS_COMMIT_ENTRIES` | 32 | commit stack depth |
| `RAS_RCTR_WIDTH`     | 4  | recursion counter width (saturates at 15) |
| `RAS_PTR_BITS`       | 4  | `$clog2(16)` speculative pointer width |
| `RAS_COMMIT_PTR_BITS`| 5  | `$clog2(32)` commit pointer width |
| `RAS_ADDR_WIDTH`     | 40 | = `VA_WIDTH` |

![Figure 2. RAS dual-stack structure](fig2_dual_stack_structure.svg)

*Figure 2. Two register-file stacks. The speculative stack is a
circular buffer with TOSR/TOSW/BOS pointers and a reserved BOS sentinel
slot; the commit stack is a conventional stack with CSP. Three 4-bit
pointers per FTQ entry form the snapshot used for pointer-only
recovery.*

### 3.2 The speculative stack and its pointers

Three pointers, each `RAS_PTR_BITS` (4b) wide, define the speculative
stack:

- **TOSR** -- Top Of Stack Read: the current top, the entry a pop
  returns.
- **TOSW** -- Top Of Stack Write: the next free allocation slot.
- **BOS**  -- Bottom Of Stack: the committed boundary.

Two aspects of the pointer discipline warrant explicit description,
because the majority of corner cases derive from them.

**The BOS sentinel.** Empty is detected as `TOSR == BOS`. To prevent a
single live entry from aliasing the empty condition, the BOS index is
treated as a permanent sentinel: a push that would allocate onto BOS
allocates at `BOS+1` instead. This occurs at cold start after reset and
on a full circular wrap. The consequence is that usable depth is
`RAS_SPEC_ENTRIES - 1 = 15` rather than 16. (In `tb_ras`, this is why
the first push after reset is placed at index 1 with `tosr=1, tosw=2`;
TC-02.)

**TOSW is monotonic across pops.** A pop presents the TOSR entry and
moves TOSR back; it does not overwrite array data and does not retreat
TOSW. Popped entries therefore remain physically resident above TOSR.
This property is what makes pointer-only recovery correct (Section
3.6): a restore can re-expose a previously popped entry by moving a
pointer, because the data is not overwritten.

Push, pop, empty, and overflow then reduce to the following:

- **Push:** write `ret_addr`/`rctr` to the TOSW slot (skipping the BOS
  sentinel), set `TOSR = alloc`, advance `TOSW = alloc+1`.
- **Pop:** present TOSR; `TOSR--` (or decrement `rctr`, Section 3.5).
- **Empty (`TOSR == BOS`):** fall through to the commit-stack top as
  the prediction; the commit entry is not consumed.
- **Full (`TOSW+1 == BOS`):** 15 entries live, one push remaining.
- **Overflow (wrap):** the next push finds `TOSW == BOS` and takes
  the sentinel skip, allocating at `BOS+1`. This is not the loss of
  one entry. TOSR becomes `BOS+1`, so reachable depth collapses to a
  single entry in one push; the older entries stay physically
  resident but unreachable, and the following pop hits `TOSR == BOS`
  and falls through to the commit stack. No fault is raised, and the
  commit fallback bounds the damage, but the degradation is a cliff
  rather than a gradual slope. TC-18 checks only that the unit stays
  functional across the wrap, not the depth collapse.

### 3.3 The prediction path: s0 read and s2 push/pop

At **s0** the RAS presents a purely combinational read of its top: the
speculative top when the stack is non-empty, otherwise the commit-stack
top, otherwise invalid. Both prediction slots see the same s0 value.
Because the read is combinational off the registered pointers and
array, a freshly pushed entry becomes visible at s0 the cycle after the
push commits, not the same cycle (TC-19 verifies this).

At **s2**, gated on `ras_pred_val_p2`, FTB `br_type` and the
registered `ras_rst_done` (Section 3.9), the authoritative operation
runs combinationally and produces, per slot: the pop address
(`ras_pop_addr_p2`), its valid bit (`ras_pop_valid_p2`, asserted only
on a slot that actually pops, and within that case deasserted only
when both stacks are empty), and the post-operation pointer snapshot
(`ras_snapshot_p2`). The FTQ
latches the snapshot on the edge closing s2.

### 3.4 Dual-slot operation and the same-cycle bypass

The pacino front end issues two prediction slots per cycle
(`NUM_PRED_SLOTS = 2`) on a fixed bundle split: slot 0 covers
`pred_pc .. +31`, slot 1 covers `pred_pc+32 .. +63`. Both slots are
evaluated in the same cycle, slot 0 before slot 1, with slot 1 seeing
the pointer state left by slot 0. Snapshot[0] reflects the state after
slot 0 only; snapshot[1] reflects the state after both slots.

Four of the five slot combinations reduce to straightforward sequencing
of a push and/or a pop. The fifth requires additional handling: slot 0
= call, slot 1 = return in the same cycle. In this case slot 1 must
return the address that slot 0 has just pushed, but at the point slot 1
evaluates, that address has not yet been written to the array. The RTL
forwards it combinationally from the slot-0 push data path (the working
top-of-stack view) to the slot-1 pop output (Figure 3). This is a
forwarding path within the push/pop logic, not a RAM bypass; it is
always present and is gated combinationally on the two slots' branch
types (TC-06).

![Figure 3. Same-cycle slot0-call / slot1-return bypass](fig3_same_cycle_bypass.svg)

*Figure 3. The slot0-call / slot1-return hazard. The pushed return
address is forwarded from the working top-of-stack view to the slot-1
pop output combinationally, before the array write that occurs at the
clock edge.*

### 3.5 Recursion counter

Recursive calls would otherwise consume one entry per repetition of the
same return address. Each entry carries a 4-bit `rctr` to accommodate
them:

- **Push** of an address equal to the current TOS `ret_addr` (with the
  stack non-empty) increments `rctr` in place rather than allocating;
  TOSW does not advance. The counter saturates at 15; further
  repetitions are suppressed (TC-08, TC-10).
- **Pop** when `rctr > 0` decrements `rctr` and holds TOSR; only when
  `rctr == 0` does the pop move TOSR (TC-09).

For two simultaneous same-address pushes, the two increments are
applied in slot order and clamped at 15; two pushes of a new address
allocate once with `rctr = 1`. Recursion detection is speculative only.
The commit stack's `rctr` field is reserved and is currently written
zero on every commit push, which is a known limitation (Section 3.10,
TD #79).

### 3.6 Snapshot and pointer-only restore

This mechanism is central to speculative recovery and is the rationale
for the speculative-stack organization.

Every prediction that affects the RAS writes one `bp_ras_snapshot_t` --
the post-operation `{tosr, tosw, bos}`, 12 bits -- into its FTQ entry.
On a mispredict redirect from any predictor, the FTQ drives
`ras_restore_val` with the snapshot of the mispredicted entry, and the
RAS reloads all three pointers from it. Only the pointers are restored;
the circular-buffer data is not cleared. Subsequent pushes overwrite
stale wrong-path slots above the restored TOSR, which is correct
because those slots are no longer reachable. The restore takes strict
priority over any same-cycle s2 push or pop (TC-12).

This provides constant-time (O(1)) recovery with no replay and no
per-operation undo log. It is correct precisely because TOSW is
monotonic (Section 3.2): the data that a restore must re-expose is not
overwritten. This checkpoint-and-restore approach corresponds to the
pointer-fixup mechanism described by Skadron et al. (1998), which saves
the top-of-stack pointer at each prediction for restoration after a
misprediction.

The committed boundary is updated under the priority
**restore > commit > hold**: a mispredict restore in the same cycle as
a commit takes precedence for BOS; otherwise a commit advances BOS to
the committing entry's post-operation TOSR; otherwise BOS holds.

### 3.7 Commit path and empty fallback

The FTQ retires one entry per cycle, so the RAS receives one commit
event per cycle (there is no dual-slot commit channel). On commit of a
call, the return address is pushed to the commit stack and CSP advances
(TC-13); on commit of a return, CSP decrements (TC-14); BOS advances as
described in Section 3.6. Commit is registered: it takes effect the
cycle after `ras_commit_val` and does not interact combinationally with
the s2 push/pop path.

CSP is a free pointer: the top entry is at `CSP-1` and empty is
`CSP == 0`. That encoding has a consequence at capacity. On the 32nd
consecutive commit push CSP wraps to 0, so a *full* commit stack
reads as empty, `commit_top_valid` deasserts, and both the s0 read
and the empty-pop fallback lose their commit source until CSP
advances again. Returns are a prediction and not a correctness
requirement, so this is accepted rather than guarded; it is a
candidate for rebalancing the 16/32 split if commit overflow is
measured at cluster integration.

When the speculative stack is empty and a pop is requested, the
commit-stack top is presented as the result and is not consumed
(read-only fallback, TC-15). The same fallback supplies the s0 read.
The valid bit is deasserted only when both stacks are empty (TC-20).

### 3.8 s3 repair

The s3 pass exists because the s2 operation is initiated on a
prediction that can change one cycle later. At s3 the RAS compares the
registered s2 operation against the registered FTB type and, when they
disagree, applies the inverse operation on the speculative stack:

| s2 did | s3 says | repair |
|---|---|---|
| push  | no-op | pop  (undo the push) |
| no-op | pop   | pop  (apply missed pop) |
| pop   | no-op | push (undo the pop) |
| no-op | push  | push (apply missed push) |

The `push->pop` and `pop->push` transitions within a single s2/s3 pair
cannot occur. The labels denote restoration of stack height over
resident entries rather than fresh allocation. Undo-push retracts TOSR
over the still-resident frontier slot (and decrements an in-place
recursion count if present); undo-pop re-exposes the still-resident
entry that the pop uncovered, with no array write. Only the missed-push
case allocates and writes a new frontier entry (TC-16, TC-17).

This realignment-on-misprediction approach corresponds to the
correction described by Desmet et al. (2008): after a call or return
misprediction, the recovered top-of-stack pointer is moved to the next
or previous slot relative to the checkpoint rather than rebuilding the
stack. pacino applies the same principle one stage earlier, between s2
and s3.

In the RTL, the repair and s2 passes share a single combinational scan
that emits up to `2 x NUM_PRED_SLOTS` speculative write requests;
repair writes occupy the low indices and s2 writes the high indices, so
an s2 write to a given index supersedes a repair write to the same
index in the same cycle.

### 3.9 Reset

On synchronous active-low reset, all pointers (TOSR, TOSW, BOS, CSP),
all `rctr` fields, and all `ret_addr` fields clear to zero, and both
valid outputs deassert on the first post-reset cycle (TC-01). A
registered `ras_rst_done` gates all push, pop, and repair activity off
until reset completes; reading it inside the combinational scan also
forces Verilator's `nba_sequent` scheduling so that the scan
re-evaluates after the flop updates.

### 3.10 Known limitations in the current design

Three items are documented and tracked; they are not latent defects:

- **TD #78 -- undo-pop does not reverse a recursion-decrement pop.** The
  s3 undo-pop re-exposes a TOSR-moving pop correctly, but a pop that
  only decremented `rctr` (TOSR held) leaves no recoverable pre-pop
  count, so the re-expose moves TOSR by one slot instead. `tb_ras`
  TC-21 verifies the current, non-reversing behavior. This will be
  re-evaluated only if an s2/s3 repair over a recursion pop is required.
- **TD #79 -- commit-stack recursion depth is not preserved.** The
  commit interface carries only a bare return address, so `commit_rctr`
  is written zero and never read. A recursive call that commits is read
  back from the commit fallback as a single entry rather than at its
  true depth. Because the field is write-only, an incorrect value
  cannot affect correctness; it can only degrade a fallback prediction.
  A complete fix requires a recursion-count source on the commit
  interface and is deferred to bp_cluster/FTQ integration.
- **TD #101 -- `ras_pc_p2` is declared and never read.** The branch PC
  is on the port list and `bp_cluster` drives it from the staged s2 PC,
  but nothing inside `ras.sv` consumes it: the pushed return address
  comes from `ras_fall_through_p2`, and the RAS does not compute PC+2
  or PC+4 itself (`ras_decisions.md` section 8). The port is either
  confirmed for a future use or removed from `ras.sv` and `tb_ras.sv`.

One interface item remains open: **RAS-1**, the predecode early-push
hint, which is an optimization over the s2 authoritative push that is
already in place.

**RAS-3 is closed**, and is worth stating explicitly because the
unread `ras_flush_*` ports invite the opposite conclusion. There is no
flush-specific RAS behavior and none is coming. A flush is a redirect
(`fe_decisions.md` FE-14), so the RAS response to a flush is the
pointer-only restore of Section 3.6, already built and tested as
`ras_restore_val`. `ras_flush_val` and `ras_flush_snapshot` are
redundant with that restore group and are deliberately left unread;
they are evidence of a redundant port, not of an open question. See
`ras_decisions.md` 4.4 and 4.4.2, which exist because this was
re-raised repeatedly from exactly that observation.

---

## 4. Other design choices

The pacino RAS represents a conservative point in a large design space.
This section describes the alternatives that were evaluated and
rejected for this design, followed by the corresponding choices made in
industry and in the literature.

### 4.1 Alternatives evaluated and rejected

**Linked circular array compared with simple circular buffer.** The
original direction (recorded in the early design sessions) followed the
Xiangshan Kunminghu RAS: a persistent linked circular array in which
each entry carries a next-on-stack (`nos`) pointer forming an explicit
chain, so that speculative history is not overwritten and pops traverse
the chain. This was rejected at session-050 in favor of the simple
circular buffer present in the RTL. The property that the linked
structure provides -- full speculative history retained for recovery --
is obtained at lower cost here through monotonic TOSW and pointer
snapshots, and the literature does not establish an IPC benefit that
would justify the chain maintenance and the larger verification
surface. A simple buffer combined with a fallback for detected
corruption is the prevailing commercial approach. This decision will be
re-evaluated: if SPEC trace analysis shows that wrong-path corruption
is an unexpectedly significant contributor to mispredictions, the
linked structure or a corruption-detection mechanism in the style of
Skadron et al. (1998) and Desmet et al. (2008) will be evaluated.

**Unified pool compared with static partition.** A single 48-entry
array shared between speculative and committed state was evaluated and
rejected in favor of the static 16 + 32 split. The only advantage of a
unified pool is flexible balancing between speculative and committed
depth; against this, every overflow check, every restore, and every
commit would have to account for a shared, moving boundary. Given a
48-entry total, this flexibility does not justify the additional
verification cost. This decision will be re-evaluated if commit-stack
overflow is observed as a measured event under representative
workloads, in which case the partition will be rebalanced before the
structure is changed.

**Recursion counter inclusion.** Folding recursive repeats into a
saturating counter, rather than consuming one entry per repetition, was
an optional feature. It was included in the initial design because its
cost is low (4 bits per entry) and it protects the limited 15-entry
usable speculative depth against pathological self-recursion. The
counter width is consistent with established practice: 15 repetitions
is well beyond the depth at which a realistic workload would already
have overflowed the stack.

**Push timing.** The choice between initiating the push on an early
predecode hint and waiting for the authoritative FTB type was resolved
in favor of the conservative option: the authoritative push is gated on
the FTB type at s2, and the predecode early-hint is deferred as a
subsequent RTL optimization (RAS-1).

### 4.2 Corresponding choices in industry and the literature

The pacino design choices are consistent with established practice. The
instances of divergence are intentional and are identified below.

**Recovery by checkpoint and pointer restoration.** Commercial
high-performance cores recover the RAS by checkpoint or pointer
restoration on redirect, which is the mechanism used by pacino. The
technique of saving the top-of-stack pointer at each prediction for
later restoration was established by Skadron et al. (1998), who reported
return-prediction accuracy approaching 100 percent with this repair.
Jourdan et al. (1997) characterized the recovery requirements of
branch-prediction storage structures under mispredicted-path execution.
Desmet et al. (2008) subsequently showed that most return mispredictions
arise from overflow and from wrong-path overwrites of the top entries,
and that the appropriate correction is to realign the recovered
top-of-stack pointer to the next or previous slot following a call or
return misprediction. The pacino s2/s3 repair table applies this
realignment; the monotonic-TOSW circular buffer addresses the
wrong-path overwrite source by retaining popped data until it is
reallocated.

**Stack depth.** Return-stack depth has increased as software has become
more layered. Sandy-Bridge-era x86 cores carried approximately 16
entries; AMD increased the RAS from 24 entries (Excavator) to 32 with
Zen, and the Zen 5 optimization guide documents a 52-entry RAS per
thread. The determining factor is not recursion depth but the number of
stack frames live at steady state in layered software (runtime,
framework, libraries, operating system), which commonly reaches several
tens of frames in the absence of recursion. The pacino configuration of
16 speculative and 32 commit entries is within the range of
contemporary commercial designs while keeping the speculative array,
which is timing- and recovery-critical, small.

**Per-thread duplication for SMT and security isolation.** The Zen 5
figure of 52 entries is per thread; commercial designs duplicate the
stack per SMT thread, in part for isolation against speculative-execution
attacks rather than for additional call depth. The pacino parameter
`NUM_PRED_SLOTS = 2` represents a different axis (two prediction slots
per cycle rather than two threads), but it imposes a comparable
structural requirement to dual-fetch commercial designs: the RAS must
process two call/return events in one cycle, which is the reason for
the slot-0/slot-1 ordering and the same-cycle bypass (Section 3.4).

**Call/return pair throughput.** The number of call/return pairs that a
front end can process per cycle is a recurring commercial design
parameter, and vendors allocate area and accept latency to increase it.
The pacino parallel dual-slot evaluation with a combinational bypass
addresses the same objective at the unit level: a call in slot 0 and
its matching return in slot 1 are resolved in one cycle.

### 4.3 Design-space summary

| Axis | pacino choice | Main alternative | Rationale |
|---|---|---|---|
| Speculative structure | simple circular buffer | linked circular array (Xiangshan-style) | no demonstrated IPC gain; recovery already O(1); smaller verification surface |
| Spec/commit storage | static 16 + 32 partition | unified 48-entry pool | fixed overflow limits; isolated restore/commit; flexibility not required at this capacity |
| Recovery | pointer-only snapshot restore + s2/s3 realign | per-op undo / replay; full-content checkpoint | consistent with Skadron/Desmet repair and commercial practice; low cost and exact |
| Wrong-path data | retained resident (monotonic TOSW) | clear-on-pop | enables pointer-only re-expose on restore |
| Recursion | 4-bit saturating counter per entry | one entry per repeat; no counter | protects limited speculative depth at low cost |
| Empty handling | commit-stack fallback, not consumed | invalid / no prediction | recovers a usable prediction past speculative empty |
| Overflow | circular wrap, commit fallback catches the miss | stall / fault | returns are a prediction, not a correctness requirement; the wrap collapses reachable depth rather than dropping one entry (Section 3.2) |

---

## 5. Open items and future work

- **RAS-1** -- predecode early-push hint as an optimization over the s2
  authoritative push. To be closed when RTL analysis confirms that s2
  timing is sufficient for all call/return interleavings.
- **TD #101** -- `ras_pc_p2` declared on `ras.sv` and read by nothing;
  confirm a use or remove it from the module and the testbench.
- **Commit-stack wrap** -- CSP encodes empty as `CSP == 0`, so a full
  commit stack reads as empty after the 32nd push (Section 3.7).
  Candidate for a tech-debt entry and for rebalancing the 16/32 split.
- **TD #78** -- s3 reversal of a recursion-decrement pop; to be
  re-evaluated if a repair over a recursion pop is required.
- **TD #79** -- commit-stack recursion depth; requires a recursion-count
  source on the commit interface; to be resolved at bp_cluster/FTQ
  integration.
- **Depth validation** -- confirm the 16/32 split against SPEC
  wrong-path corruption and commit-overflow measurements at cluster
  integration. The linked-structure and unified-pool decisions are both
  contingent on this data, as described in Section 4.1.

---

## Appendix A. Worked timing examples

These waveforms illustrate the four principal behaviors of Sections
3.3, 3.4, 3.5, and 3.6. They are schematic: pointer values are shown as
their registered state at the start of each cycle, so an operation
requested in cycle *n* updates the pointers visible from cycle *n+1*.
Addresses are symbolic (`A`, `B`); recursion and pointer arithmetic
follow the RTL and the directed tests cited.

**A.1 Basic call / return (TC-02..TC-05)**

![Basic push then pop](wf1_push_pop.svg)

*A push allocates at index 1 (skipping the BOS sentinel): `tosr` 0->1,
`tosw` 0->2. The pop presents the `tosr` entry and retreats `tosr`,
while `tosw` holds at 2 -- the monotonic-write property that retains
popped data for later restore.*

**A.2 Same-cycle dual-slot bypass (TC-06)**

![Same-cycle call+return bypass](wf2_same_cycle_bypass.svg)

*Slot 0 pushes call `A` and slot 1 pops a return in the same cycle.
`pop_addr_p2[1]` is forwarded combinationally from the slot-0 push
(`w_top_addr`, highlighted) with no array read. The net `tosr` is
unchanged because the push and pop offset each other; `tosw` still
advances to 2.*

**A.3 Recursion counter (TC-08 / TC-09)**

![Recursion counter increment and decrement](wf3_recursion.svg)

*The second push of the same address increments the top-of-stack `rctr`
in place (0->1) rather than allocating, so `tosw` holds. The first pop
finds `rctr > 0`, decrements it (1->0), and holds `tosr`; only the
second pop, with `rctr == 0`, moves `tosr` back. `rctr` saturates at
15.*

**A.4 Snapshot and pointer-only restore (TC-12)**

![Snapshot capture and mispredict restore](wf4_snapshot_restore.svg)

*Each prediction writes its post-operation `{tosr, tosw, bos}` snapshot
into the FTQ entry (`{1,2,0}` after pushing `A`, `{2,3,0}` after pushing
`B`). A redirect drives `restore_val` with `A`'s snapshot; the RAS
reloads all three pointers from it (`tosr` 2->1, `tosw` 3->2) while the
array data for `A` and `B` is not cleared. `bos` holds, per the
restore > commit > hold priority.*

---

## 6. Related documents

- `planning/arch/ras_decisions.md` -- canonical decisions (authoritative
  on any conflict).
- `planning/interfaces/ras_interfaces.md` -- ports and interface
  contracts IC-RAS-01..12.
- `planning/arch/bp_arb_spec.md` Section 7.2 -- RAS non-RAM status and
  snapshot/restore overview.
- `planning/arch/bp_cluster.md` -- pipeline staging, redirect
  architecture, FTQ entry layout.
- `rtl/core/frontend/bpu/rtl/ras.sv`, `.../tb/tb_ras.sv` -- RTL and
  directed tests.

### External references

- K. Skadron, P. S. Ahuja, M. Martonosi, and D. W. Clark, "Improving
  prediction for procedure returns with return-address-stack repair
  mechanisms," in Proceedings of the 31st Annual ACM/IEEE International
  Symposium on Microarchitecture (MICRO-31), 1998, pp. 259-271.
  DOI: 10.1109/MICRO.1998.742787.
- S. Jourdan, J. Stark, T.-H. Hsing, and Y. N. Patt, "Recovery
  requirements of branch prediction storage structures in the presence
  of mispredicted-path execution," International Journal of Parallel
  Programming, vol. 25, no. 5, 1997.
- V. Desmet, Y. Sazeides, C. Kourouyiannis, and K. De Bosschere,
  "Speculative return address stack management revisited," ACM
  Transactions on Architecture and Code Optimization, vol. 5, no. 3,
  2008. DOI: 10.1145/1455650.1455654.
- AMD, "Software Optimization Guide for the AMD Zen5 Microarchitecture,"
  publication 58455, rev. 1.00, August 2024 (52-entry return address
  stack per thread).


