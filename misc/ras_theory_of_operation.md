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
 SOURCE:  derived from session-050 / BP-062..BP-064; DOC-011
 STATUS:  DRAFT
 UPDATED: 2026-10-29
 CONTACT: Jeff Nye
```
-->

## RAS Theory of Operation

This is a theory of operation description of the return address stack,
a component in the BPU that assists call/return predictions. The tone
diverges from other blogs; this is less a postmortem of the co-design
of the RAS and more of a description of its operation with references
to the planning documents that were used in RAS creation and testing.

There will be a postmortem as well.  This is a descriptive companion 
to the canonical RAS records.  Where this document and the canonical 
records differ, the canonical records take precedence:

- `planning/arch/ras_decisions.md`   -- micro-architectural decisions
- `planning/interfaces/ras_interfaces.md` -- port and contract spec
- `rtl/core/frontend/bpu/rtl/ras.sv`  -- implementation
- `rtl/core/frontend/bpu/tb/tb_ras.sv` -- directed tests (TC-01..TC-44)

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

It supplies a target and takes no part in the direction ranking
(`fe_decisions.md` 3.3). It is type-gated: it acts only on the three
RAS types listed below. The RAS does not classify instructions; the
type is supplied on its ports by the cluster, from the FTB entry at
p2. Classification uses the RISC-V link-register convention (link
means `x1` or `x5`; `bp_structs_pkg.sv` `bp_br_type_e`):

- **Call (push):** `JAL` with `rd = x1` or `x5` (`DIRECT_CALL`);
  `JALR` with `rd` a link register and `rs1` either not a link
  register or equal to `rd` (`INDIRECT_CALL`); `C.JALR` with
  `rs1 != x5`.
- **Return (pop):** `JALR`/`C.JR` with `rs1 = x1` or `x5`, and
  for `JALR` only when `rd` is not a link register (`RETURN`).
- **Return-call (pop, then push):** `JALR` with `rd` and `rs1` both
  link registers and unequal, which includes `C.JALR` with
  `rs1 = x5` (`RETURN_CALL`). One instruction performs two RAS
  operations, the pop first (RAS-DS1). The `rd` qualifier of the
  return rule is what keeps the classes disjoint: `JALR rd=x1,
  rs1=x1` is a call, and `JALR rd=x1, rs1=x5` is a return-call.

This divides `JALR`-class branches between two predictors. The RAS
supplies the target of `RETURN` and `RETURN_CALL`; ITTAGE supplies the
target of every other indirect branch (`INDIRECT_CALL`,
`INDIRECT_NONRET`). The FTB jump target is the fallback for both,
taken when the RAS pop is not valid or ITTAGE misses
(`bp_cluster.sv:1164-1174`). It is chosen by hit, not by branch type,
so it is not a third class (`ras_decisions.md` 2). The type comes from
the uBTB entry at p1 and from the FTB entry at p2.

The RAS participates at three pipeline points (Figure 1). At **p0** it
presents a combinational read of its current top of stack. The cluster
registers it, and at p1 the selection mux uses it as the target of a
uBTB slot typed `RETURN` or `RETURN_CALL` (`bp_cluster.sv:706-707`,
`:839-845`); the read is an input to the p1 prediction
(`ras_decisions.md` 1). At **p2** the FTB entry gives the branch type.
The RAS then performs the push or the pop. A pop supplies the return
target. That target enters the p2 successor of the slot, and the p2
redirect fires when that successor differs from the one the cluster
formed at p1 (`fe_decisions.md` FE-4). At **p3** the RAS performs a repair pass
that reverses or completes a p2 operation when the p3 view of the
slot no longer agrees with it.

![Figure 1. RAS position in the BP prediction pipeline](fig1_pipeline_position.svg)

*Figure 1. The RAS contributes at p0 (top-of-stack read, registered
for the p1 prediction), p2 (push/pop and the return target), and p3
(repair). It is gated by the branch type and supplies a target only;
it is not part of the direction ranking.*

The RAS contains no PQ, UQ, or credit arbiter, and no synchronous
SRAMs. Both stacks are register files. Its update mechanism is pointer
snapshot and retirement rather than a RAM write, as described in
Section 3.6.

---

## 3. Current design

### 3.1 Two physical stacks, statically partitioned

The RAS contains two independent register-file arrays (Figure 2):

- a **16-entry speculative stack** that tracks in-flight call depth
  between fetch and commit. It is a circular buffer whose entries each
  carry a next-on-stack link and a bottom mark; and
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

The entry fields (`ras.sv:115-130`); the commit stack has no recursion
counter (Section 3.5):

| Field | Width | Speculative entry | Commit entry |
|---|---|---|---|
| `ret_addr` | `VA_WIDTH` = 41 | yes | yes |
| `rctr` | 4 | yes, recursion counter | no |
| `nos`  | 4 | yes, next-on-stack link | no |
| `bot`  | 1 | yes, bottom mark | no |

The values are fixed in
`bp_defines_pkg.sv`; the two pointer widths are `localparam` derived by
`$clog2` from the depths above them, not independently set:

| Parameter | Value | Meaning |
|---|---|---|
| `RAS_SPEC_ENTRIES`   | 16 | speculative stack depth |
| `RAS_COMMIT_ENTRIES` | 32 | commit stack depth |
| `RAS_RCTR_WIDTH`     | 4  | recursion counter width (saturates at 15) |
| `RAS_PTR_BITS`       | 4  | `$clog2(16)` speculative pointer width |
| `RAS_COMMIT_PTR_BITS`| 5  | `$clog2(32)` commit pointer width |
| `RAS_ADDR_WIDTH`     | 41 | = `VA_WIDTH` |

`ras.sv` declares its address ports and arrays with `VA_WIDTH`, which
`RAS_ADDR_WIDTH` equals. The commit-stack occupancy count is
`RAS_COMMIT_PTR_BITS + 1` = 6 bits, a `localparam` of `ras.sv`
(`ras.sv:139`).

![Figure 2. RAS dual-stack structure](fig2_dual_stack_structure.svg)

*Figure 2. Two register-file stacks. The speculative stack is a
circular buffer with a next-on-stack link and a bottom mark per entry,
TOSR/TOSW/BOS pointers and a reserved BOS sentinel slot; the commit
stack is a conventional stack with CSP and an occupancy count. Three
4-bit pointers per FTQ entry form the snapshot used for pointer-only
recovery.*

### 3.2 The speculative stack and its pointers

Three pointers, each `RAS_PTR_BITS` (4b) wide, define the speculative
stack:

- **TOSR** -- Top Of Stack Read: the current top, the entry a pop
  returns.
- **TOSW** -- Top Of Stack Write: the next free allocation slot.
- **BOS**  -- Bottom Of Stack: the committed boundary.

Three aspects of the pointer discipline warrant explicit description,
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
moves TOSR down; it does not overwrite array data and does not retreat
TOSW. Popped entries therefore remain physically resident. This
property is what makes pointer-only recovery correct (Section 3.6): a
restore can re-expose a previously popped entry by moving a pointer,
because the data is not overwritten.

**The next-on-stack link.** Because TOSW only advances, the entry below
the top is in general not the slot below it. In the sequence push A ->
push B -> pop -> push C, C is at index 3 and the entry below it is A at
index 1 (`tb_ras` TC-29). Each entry therefore records the index of
the entry below it in `nos`, written by the push that allocates the
entry and followed by the pop that removes it. Before BP-120 a pop moved TOSR to
TOSR-1, which there is B's slot, and the correct path mispredicted
(TD#159; Section 4.1). TC-29 to TC-33 check the link.

Push, pop, empty, and overflow then reduce to the following
(`ras.sv:330-454`):

- **Push:** write `ret_addr`/`rctr` and the next-on-stack link to
  the TOSW slot (skipping the BOS sentinel), set `TOSR = alloc`,
  advance `TOSW = alloc+1`. The link is the current TOSR, or BOS on
  the sentinel skip. The new entry is marked bottom when the stack was
  empty or the push took the sentinel skip (BP-138).
- **Pop:** present TOSR; TOSR follows the entry's link, or goes to
  BOS as it is then when the entry is bottom (BP-138); or decrement
  `rctr` (Section 3.5).
- **Empty (`TOSR == BOS`):** fall through to the commit-stack top as
  the prediction; the commit entry is not consumed. A commit moves
  BOS, and four rules keep the test exact across commits
  (`ras_decisions.md` 3.2; `ras.sv:257-287`):
  1. A push onto an empty stack, or by the sentinel skip, marks its
     entry bottom; the pop that removes a bottom entry sets TOSR to
     BOS as it is then, not to the link (BP-138, TC-41c).
  2. A commit that moves BOS while TOSR == BOS moves TOSR with it
     (BP-138, TC-41a, TC-41b, TC-42).
  3. A p3 undo of an operation that began on an empty stack restores
     TOSR to BOS as it is at the undo (BP-138, TC-43).
  4. A `RETURN` commit whose snapshot is an empty stack (snapshot
     TOSR == snapshot BOS) leaves BOS where it is (BP-140,
     provisional, TC-44). That snapshot TOSR is the BOS of the cycle
     in which the return popped a bottom entry. The commits of older
     blocks have since moved BOS off that slot, and the sentinel skip
     protects only the current BOS, so allocation may have reused the
     slot for a younger push. Moving BOS back to it would leave BOS on
     an entry the stack holds. The current BOS is the entry the
     return popped, committed by its call, so the stack the return
     leaves is empty there.
- **Full (`TOSW+1 == BOS`):** fifteen slots have been allocated
  beyond BOS and one push remains before the wrap. A pop does not
  retreat TOSW, so these are the allocations since BOS last moved,
  not necessarily fifteen live entries (TC-44 walks TOSW around the
  buffer with at most one entry live).
- **Overflow (wrap):** the next push finds `TOSW == BOS` and takes
  the sentinel skip; its entry links to BOS. This is not the loss of
  one entry. TOSR becomes `BOS+1`, so reachable depth collapses to a
  single entry in one push; the older entries stay physically
  resident but unreachable, and the following pop hits `TOSR == BOS`
  and falls through to the commit stack. No fault is raised, and the
  commit fallback bounds the damage, but the degradation is a cliff
  rather than a gradual slope. TC-18 checks only that the unit stays
  functional across the wrap, not the depth collapse.

### 3.3 The prediction path: p0 read and p2 push/pop

At **p0** the RAS presents a purely combinational read of its top: the
speculative top when the stack is non-empty, otherwise the commit-stack
top, otherwise invalid. Both prediction slots see the same p0 value
(`ras.sv:190-212`). Because the read is combinational off the
registered pointers and array, an entry pushed at p2 becomes visible
at p0 in the following cycle (TC-19). In the cluster the p0 read of a
block is taken while the two blocks ahead of it are at p1 and p2, so it
does not reflect their operations; the p2 operation of the block, two
cycles later, does.

At **p2** the operation runs combinationally. It is gated on
`ras_pred_val_p2` and the type on `ras_br_type_p2`, and is held off
by the registered `ras_rst_done` until reset completes (Section 3.9).
Per slot it produces:

- the pop address, `ras_pop_addr_p2`;
- its valid bit, `ras_pop_valid_p2`, asserted only on a slot that
  actually pops, and within that case deasserted only when both stacks
  are empty;
- the post-operation pointer snapshot, `ras_snapshot_p2`.

The cluster presents a slot when its block is valid, the FTB answered,
the slot holds a branch, and no earlier slot of the block is predicted
taken (`bp_cluster.sv:1089-1091`). The
return target is the pop address when the pop is valid, otherwise the
FTB jump target (`bp_cluster.sv:1164-1170`). The FTQ entry takes the
snapshot of the last slot, `ras_snapshot_p2[NUM_PRED_SLOTS-1]`, for
every valid p2 block, on the edge closing p2 (`bp_cluster.sv:1274`;
`ras_decisions.md` 4.2); the p1 value, `bpu_pred_ras_p1`, only
initializes the field (`bp_cluster.sv:955-961`).

### 3.4 Slot formation and same-cycle operations

The front end predicts up to `NUM_PRED_SLOTS = 2` branches per
prediction block (a one-slot build is supported, BP-128;
`bp_defines_pkg.sv:54-65`). Both slots are branch fields of the one
32-byte block (`FTB_BLOCK_BYTES`) that starts at the request PC, each
located by its own position in the block (`ras_decisions.md` 6.1,
`fe_decisions.md` FE-10). At p2 the cluster forms them from the FTB
entry for that start (`bp_cluster.sv:979-1046`): slot 0 carries the
entry's first conditional field, `br0`; slot 1 its second, `br1`; and
the entry's single jump field goes to the lowest slot that holds no
conditional. The fields are in position order, so
the slots are in program order. At p1 the same holds for the uBTB
entry, which since BP-140 stores its fields in position order
(`bp_cluster.sv:853-867`).

A branch the FTB reports that no slot carries is cut (BP-139): the
block ends at that branch's PC. The next block starts at that PC and
carries the branch in slot 0 (`bp_cluster.sv:1048-1074`,
`:1121-1141`). At one slot that branch is `br1`; at two slots it is
the jump when both slots hold conditionals. Since BP-140 the FTB ends
an entry at such a branch when it updates the entry. An entry then
holds at most `NUM_PRED_SLOTS` branches; the cut is a backstop that the
FTB's own entries do not reach (`bp_cluster.sv:1050-1053`,
`:1127-1130`).

Only the jump field carries a call, return or return-call type
(`bp_cluster.sv:993-1008`); a conditional slot is `COND`, on which the
RAS does nothing. An entry has one jump field, and a RAS-typed branch
is taken, so no later slot of the block is on the predicted path
(`w_reach_p2`, `bp_cluster.sv:1076-1084`). At most one slot of a block
therefore operates on the RAS (`fe_decisions.md` FE-11). That slot may
be slot 1, behind a not-taken conditional in slot 0, which is the case
`fd24_call_slot1` demonstrates.

Within `ras.sv`, every slot is evaluated in one cycle, slot 0 before
slot 1, slot 1 seeing the pointer state left by slot 0. Snapshot[0]
reflects the state after slot 0 only; snapshot[1] reflects the state
after both slots (TC-11). The module handles two operations in one
cycle: two pushes, two pops, return then call, and call then return.
For call then return, slot 1 must return the address that slot 0 has
just pushed, which the array does not hold until the clock edge. The
scan carries a working top of stack (the `ras_ws_t` state,
`ras.sv:289-304`) from step to step, and slot 1's pop reads the pushed
address from it with no array read (`ras.sv:224-226`, `:236-237`,
`:679`; TC-06, Figure 3). The forwarding has no gating of its own on
the two slots' types; every step of the scan reads the same working
state. `tb_ras` covers these combinations (TC-04 to TC-07, TC-11,
skipped at one slot). Because
`bp_cluster` never presents two RAS-typed slots in one block, the
integrated front end does not reach them (`ras_decisions.md` 6.2 to
6.4).

The two operations that do occur together are those of a
`RETURN_CALL`: one instruction in one slot, the pop first and then
the push applied to the state the pop left (RAS-DS1;
`ras.sv:671-713`; TC-22 to TC-25). The pop supplies the predicted
target. When the pop only decrements a recursion count, the slot makes
two array writes, which is why the scan has two write ports per slot
per pass (`ras.sv:101-110`; TC-24).

![Figure 3. Same-cycle slot0-call / slot1-return bypass](fig3_same_cycle_bypass.svg)

*Figure 3. Slot 0 call and slot 1 return in one cycle, at the module
level. The pushed return address reaches the slot-1 pop output from
the scan's working top of stack, before the array write that occurs at
the clock edge. `bp_cluster` does not present this combination.*

### 3.5 Recursion counter

Recursive calls would otherwise consume one entry per repetition of the
same return address. Each entry carries a 4-bit `rctr` to accommodate
them:

- **Push** of an address equal to the current TOS `ret_addr` (with the
  stack non-empty) increments `rctr` in place rather than allocating;
  TOSW does not advance. The counter saturates at 15; further
  repetitions are suppressed (TC-08, TC-10). The p2 push is made with
  this match enabled; a missed push applied by the p3 repair allocates
  without it (`ras.sv:639`, `:705`).
- **Pop** when `rctr > 0` decrements `rctr` and holds TOSR; only when
  `rctr == 0` does the pop move TOSR (TC-09).

When two slots push in one cycle (reached only in `tb_ras`, Section
3.4), the second push compares against the top the first left: two
pushes of the address on top increment the count twice, clamped at 15;
two pushes of a new address allocate once, and the second increments
that entry's count to 1. Recursion detection is speculative only.
The commit stack has no recursion count: every committed call is its
own entry, so depth is kept as repeated entries (TD #79 closed by
BP-133; the unused `rctr` field was removed by BP-134; TC-39).

### 3.6 Snapshot and pointer-only restore

This mechanism is central to speculative recovery and is the rationale
for the speculative-stack organization.

Every valid p2 block writes one `bp_ras_snapshot_t` -- the
`{tosr, tosw, bos}` after all of its slots, 12 bits -- into its FTQ
entry (Section 3.3). On a redirect the FTQ drives `ras_restore_val`
with the snapshot of the entry the redirect names by its index, and the
RAS reloads all three pointers from it (`ras.sv:808-811`, `:834-835`;
`ras_decisions.md` 4.3). Only the pointers are restored; the
circular-buffer data is not cleared. Pushes after the restore allocate
from the restored TOSW, over slots the wrong path wrote, which is
correct because those slots are no longer reachable. The restore takes
strict priority over the same cycle's scan. In a restore cycle the
scan neither writes the array nor moves a pointer (`ras.sv:808-831`).
The p2 operation of that cycle is registered as none for p3
(`ras.sv:855`; TC-12).

`bp_cluster` applies the restore with two exceptions (BP-121,
`fe_decisions.md` FE-14). For the cluster's own p2 or p3 redirect the
restore is masked: the redirecting block's own operation already
stands, or is repaired at p3 in that cycle, and the restore would
discard it (`bp_cluster.sv:1388-1402`). A block younger than a
redirect is squashed: `ras_p2_keep` low drops its p2 operation and
registers it as none, while the p3 repair of the older block in the
same cycle still applies (`bp_cluster.sv:2027`; `ras.sv:816-830`;
TC-34, TC-35).

This provides constant-time (O(1)) recovery with no replay and no
per-operation undo log. It is exact while the buffer has not wrapped.
Because TOSW only advances, a wrong-path push never overwrites an entry
the snapshot can reach (TC-32). A recursion count changed in place on
the wrong path is array data. The restore does not return it to its
earlier value (`ras.sv:335-343`, `:413-421`), and no `tb_ras` case
restores across such a change. This checkpoint-and-restore approach
corresponds to the pointer-fixup mechanism described by Skadron et al.
(1998), which saves the top-of-stack pointer at each prediction for
restoration after a misprediction.

The committed boundary is updated under the priority
**restore > commit > hold** (`ras.sv:833-841`): a restore in the same
cycle as a commit sets BOS from the snapshot; otherwise a commit
advances BOS to the committing entry's post-operation TOSR, except a
`RETURN` commit whose snapshot is an empty stack, which leaves BOS
(Section 3.2, rule 4); otherwise BOS holds. When a commit moves BOS
and the scan leaves `TOSR == BOS`, TOSR moves with it (rule 2,
`ras.sv:813-815`).

### 3.7 Commit path and empty fallback

The RAS has one commit port with no slot dimension
(`bp_cluster.sv:226-232`); the FTQ retires one entry per cycle, so the
RAS receives at most one commit event per cycle. `bp_cluster` passes a
commit only for a RAS-typed branch (`bp_cluster.sv:1646-1653`):

- a call writes the return address at CSP and advances CSP (TC-13);
- a return decrements CSP (TC-14);
- a return-call applies the return arm and then the call arm to the
  CSP the first leaves. It overwrites the committed top in place
  (TC-28).

BOS moves as described in Section 3.6. Commit is registered: it takes
effect the cycle after `ras_commit_val` and does not interact
combinationally with the p2 push/pop path, except that when the scan
leaves `TOSR == BOS`, a commit that moves BOS moves TOSR with it
(BP-138).

CSP is a free pointer: the top entry is at `CSP-1`. An occupancy
count beside it, 0 to 32, says whether the stack is empty (BP-126,
TD#121). A call committed on a full stack overwrites the oldest entry
and the count holds at 32, so a full stack still reads non-empty and
the p0 read and the empty-pop fallback keep their source. A return
committed on an empty stack does nothing (TC-36, TC-37).

When the speculative stack is empty and a pop is requested, the
commit-stack top is presented as the result and is not consumed
(read-only fallback, TC-15). The same fallback supplies the p0 read.
The valid bit is deasserted only when both stacks are empty (TC-20).

### 3.8 p3 repair

The p3 pass exists because the p2 operation is made on a view that can
change one cycle later. In `bp_cluster` the p3 type of a slot is its
registered p2 type, and its p3 valid is qualified by p3 reachability,
which uses the SC direction (`bp_cluster.sv:1721-1730`). When SC
reverses an earlier conditional so that a call or return becomes
reachable or unreachable, the p3 view differs from the p2 operation,
and the RAS applies the inverse on the speculative stack:

| p2 did | p3 says | repair |
|---|---|---|
| push  | no-op | pop  (undo the push) |
| no-op | pop   | pop  (apply missed pop) |
| pop   | no-op | push (undo the pop) |
| no-op | push  | push (apply missed push) |
| return-call | no-op | undo both: TOSR to its pre-op value |
| no-op | return-call | missed pop, then missed push |

The `push->pop` and `pop->push` transitions within a single p2/p3 pair
cannot occur. The labels denote restoration of stack height over
resident entries; only a missed push allocates (`ras.sv:239-252`,
`:531-651`):

- **Undo-push** removes the pushed entry as a pop does. When the push
  allocated, TOSR follows the entry's link (TC-16, TC-31c), or goes to
  BOS for a bottom entry. When the push incremented a count, the count
  is decremented. The undo of a push that met a saturated count
  changes nothing, as the push changed nothing (BP-134, TC-40).
- **Undo-pop** restores the TOSR the pop started from, registered at
  p2, with no array write of an address, and increments back a count
  the pop decremented (BP-120, BP-133; TC-17, TC-21, TC-31a).
- **Missed pop** is a pop: TOSR follows the link, or a count is
  decremented (TC-31b).
- **Missed push** is the only case that allocates: the registered
  fall-through is written at the frontier, linked to the current top
  (TC-31d).
- The undo of a whole return-call restores the pre-op TOSR and the
  counts its pop and push changed (TC-26, TC-38); a missed return-call
  is a missed pop and then a missed push (TC-27).

An undo of an operation that began on an empty stack restores TOSR to
BOS as it is at the undo (Section 3.2, rule 3; TC-43). A return-call
paired at the other stage with a plain push or pop is not specified;
two of the four pairings give a wrong result as built, and none is
reachable from `bp_cluster`, because the p3 type is the registered p2
type (`ras_decisions.md` 1, TD#165; TC-33).

This realignment-on-misprediction approach corresponds to the
correction described by Desmet et al. (2008): after a call or return
misprediction, the recovered top-of-stack pointer is moved to the next
or previous slot relative to the checkpoint rather than rebuilding the
stack. pacino applies the same principle one stage earlier, between p2
and p3. Its repair moves TOSR to the registered pre-operation TOSR or
along the link.

In the RTL, the repair and p2 passes share a single combinational scan,
the repair first and the p2 operation on the state the repair left. It
emits up to `2 x NUM_PRED_SLOTS x 2` speculative write requests, 8 at
two slots. Each slot has two per pass; repair writes take the low
indices and p2 writes the high. The writes are applied in index order,
so a later write to an index supersedes an earlier one in the same
cycle (`ras.sv:101-110`, `:817-830`). With `ras_p2_keep` low the p2
writes are dropped and the repair writes stay.

### 3.9 Reset

On synchronous active-low reset, all pointers (TOSR, TOSW, BOS, CSP),
the commit-stack occupancy count, every speculative entry's
`ret_addr`, `rctr`, `nos` and `bot`, every commit `ret_addr`, and the
p2-to-p3 registers clear to zero (`ras.sv:777-803`), and both valid
outputs deassert on the first post-reset cycle (TC-01). A registered
`ras_rst_done` holds the scan idle until reset completes; reading it
inside the combinational scan also forces Verilator's `nba_sequent`
scheduling so that the scan re-evaluates after the flop updates.

### 3.10 Known limitations in the current design

Three items were tracked here; all are closed:

- **TD #78 -- closed by BP-133.** An undo-pop over a pop that only
  decremented `rctr` restores the pre-op TOSR and increments the count
  back; the undo of a whole return-call restores the counts its pop and
  push changed. `tb_ras` TC-21 and TC-38 check it, and `tb_fe_top`
  `rec_undo` (BP-134) reaches it end to end.
- **TD #79 -- closed by BP-133, not a defect.** The commit stack has no
  recursion compression: every committed call is its own entry, so the
  commit fallback reads recursion at its true depth (`tb_ras` TC-39).
  `commit_rctr` was written zero and never read; BP-134 removed it.
- **TD #101 -- closed by BP-126.** `ras_pc_p2` was declared and never
  read; it was removed from `ras.sv`, `tb_ras` and `bp_cluster`. The
  pushed return address comes from `ras_fall_through_p2`, the call's
  own PC plus 2 or 4 (`bp_cluster.sv:1222-1226`; `ras_decisions.md`
  section 8).

One interface item remains open: **RAS-1**, the predecode early-push
hint, which is an optimization over the p2 authoritative push that is
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
re-raised repeatedly from exactly that observation. The port comment
in `ras.sv` still labels them "RAS-3 OPEN" (`ras.sv:80`); the decision
record is the authority.

---

## 4. Other design choices

The pacino RAS represents a conservative point in a large design space.
This section describes the alternatives that were evaluated,
followed by the corresponding choices made in industry and in the
literature.

### 4.1 Alternatives evaluated

**Linked circular array compared with simple circular buffer.**
Session-050 chose a simple circular buffer over the XiangShan
Kunminghu linked circular array, in which each entry carries a
next-on-stack (`nos`) pointer forming an explicit chain. The grounds
were that the literature did not establish an IPC benefit and that
pointer snapshots already gave O(1) recovery. BP-119 then found the
pointer rules built on that choice wrong on the correct path (TD#159).
With TOSW only advancing and a pop moving TOSR to TOSR-1, a pop that
follows a pop and a push lands on the slot just popped: f calls g, g
returns, f calls h, h returns, and f's return is predicted to g's
return address. Those rules were the linked array's pointers without
its link. Session-075 (Jeff) ruled to add the link. The ruling
reverses the session-050 choice. BP-120 built it in `ras.sv` with no
port or package change (`ras_decisions.md` 3.2). The ruling also
weighed a push at TOSR+1 with no TOSW and rejected it, because that
loses exact restore and rewrites the pointer rules of Section 3.2. The
link costs 16 x 4 = 64 bits; BP-138 added a bottom bit per entry (16
bits) to keep the empty test exact across commits. Recovery remains
the three-pointer snapshot.

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
the FTB type at p2, and the predecode early-hint is deferred as a
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
return misprediction. The pacino p2/p3 repair applies this realignment
by following the link or restoring the registered pre-operation TOSR;
the linked circular buffer with a monotonic TOSW addresses the
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
per cycle in one thread). The RAS module evaluates both slots in one
cycle in slot order, but in the integrated front end at most one slot
of a block operates on the RAS (Section 3.4). Two RAS operations in one
cycle come from a single return-call in one slot.

**Call/return pair throughput.** The number of call/return pairs that a
front end can process per cycle is a recurring commercial design
parameter, and vendors allocate area and accept latency to increase it.
pacino handles one RAS-operating instruction per prediction block
(`fe_decisions.md` FE-11). A call and its matching return are in
different blocks, since the call is taken and ends its block, and the
return's p2 pop sees the call's p2 push, made at least one cycle
earlier. The module-level same-cycle path of Section 3.4 is not used by
the cluster.

### 4.3 Design-space summary

| Axis | pacino choice | Main alternative | Rationale |
|---|---|---|---|
| Speculative structure | circular buffer with a next-on-stack link per entry (ruled session-075, built BP-120) | simple circular buffer (session-050 choice, reversed) | after a pop then a push, TOSR-1 is not the entry below (TD#159); the link costs 64 bits and keeps O(1) snapshot recovery |
| Spec/commit storage | static 16 + 32 partition | unified 48-entry pool | fixed overflow limits; isolated restore/commit; flexibility not required at this capacity |
| Recovery | pointer-only snapshot restore + p2/p3 repair | per-op undo / replay; full-content checkpoint | consistent with Skadron/Desmet repair and commercial practice; low cost and exact for pointers |
| Wrong-path data | retained resident (monotonic TOSW) | clear-on-pop | enables pointer-only re-expose on restore |
| Recursion | 4-bit saturating counter per entry | one entry per repeat; no counter | protects limited speculative depth at low cost |
| Empty handling | commit-stack fallback, not consumed | invalid / no prediction | recovers a usable prediction past speculative empty |
| Overflow | circular wrap, commit fallback catches the miss | stall / fault | returns are a prediction, not a correctness requirement; the wrap collapses reachable depth rather than dropping one entry (Section 3.2) |

---

## 5. Open items and future work

- **RAS-1** -- predecode early-push hint as an optimization over the p2
  authoritative push. To be closed when RTL analysis confirms that p2
  timing is sufficient for all call/return interleavings.
- **BP-140 BOS rule** -- the rule that a `RETURN` commit with an
  empty-stack snapshot leaves BOS (Section 3.2, rule 4) is recorded as
  provisional in `ras_decisions.md` 3.2.
- **Depth validation** -- confirm the 16/32 split against SPEC
  wrong-path corruption and commit-overflow measurements at cluster
  integration. The unified-pool decision is contingent on this data,
  as described in Section 4.1.

---

## Appendix A. Worked timing examples

These waveforms illustrate the four principal behaviors of Sections
3.3, 3.4, 3.5, and 3.6. They are schematic: pointer values are shown as
their registered state at the start of each cycle, so an operation
requested in cycle *n* updates the pointers visible from cycle *n+1*.
Addresses are symbolic (`A`, `B`); recursion and pointer arithmetic
follow the RTL and the directed tests cited.

**A.1 Basic call / return (TC-02, TC-03)**

![Basic push then pop](wf1_push_pop.svg)

*A push onto the empty stack allocates at index 1 (skipping the BOS
sentinel) and marks the entry bottom: `tosr` 0->1, `tosw` 0->2. The pop
presents the `tosr` entry; the entry is bottom, so `tosr` goes to BOS,
0, while `tosw` holds at 2 -- the monotonic-write property that retains
popped data for later restore.*

**A.2 Same-cycle dual-slot bypass (TC-06)**

![Same-cycle call+return bypass](wf2_same_cycle_bypass.svg)

*Module level; `bp_cluster` does not present this combination (Section
3.4). Slot 0 pushes call `A` and slot 1 pops a return in the same
cycle. `pop_addr_p2[1]` comes from the scan's working top of stack
(`w.top_addr`) with no array read. The pushed entry is bottom, so the
pop returns `tosr` to BOS: `tosr` is unchanged over the cycle. `tosw`
still advances to 2.*

**A.3 Recursion counter (TC-08 / TC-09)**

![Recursion counter increment and decrement](wf3_recursion.svg)

*The second push of the same address increments the top-of-stack `rctr`
in place (0->1) rather than allocating, so `tosw` holds. The first pop
finds `rctr > 0`, decrements it (1->0), and holds `tosr`; only the
second pop, with `rctr == 0`, moves `tosr` (to BOS, the entry being
bottom). `rctr` saturates at 15.*

**A.4 Snapshot and pointer-only restore (TC-12)**

![Snapshot capture and mispredict restore](wf4_snapshot_restore.svg)

*Each prediction block writes its post-operation `{tosr, tosw, bos}`
snapshot into its FTQ entry (`{1,2,0}` after pushing `A`, `{2,3,0}`
after pushing `B`). A redirect drives `restore_val` with `A`'s
snapshot; the RAS reloads all three pointers from it (`tosr` 2->1,
`tosw` 3->2, `bos` 0 from the snapshot, unchanged) while the array
data for `A` and `B` is not cleared.*

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

