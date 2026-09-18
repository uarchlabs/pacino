<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# RAS Micro-Architectural Decisions
```
 FILE:    ras_decisions.md
 SOURCE:  session-050
 STATUS:  DRAFT
 UPDATED: 2026-06-23
 CONTACT: Jeff Nye
```

Canonical decision record for the Return Address Stack (RAS)
predictor. Companion to bp_cluster.md (architectural summary)
and bp_arb_spec.md (arbitration model). Those documents reference
this file for RAS-specific decisions. Claude Code loads this file
when working on ras.sv or related testbenches.

---

## 1. Role and Pipeline Position

RAS predicts the target of return-type indirect branches
(JALR/C.JR/C.JALR matching return register convention).

Pipeline stage: p2 push/pop, p3 registered.
Override: RAS supplies the TARGET for a return and takes no part in
the direction ranking (SC > TAGE > FTB on direction,
ftb_confidence_override_rules.md 4.3). It is type-gated -- active
only when FTB identifies the branch type as return. An earlier
revision placed it "outside the conditional branch override chain
(SC > TAGE > FTB > uBTB)", which compresses a direction ranking and
a target selection into one chain. fe_decisions.md 12, narrowed
session-070.

At p2: RAS overrides FTB target for return branches.
At p3: p3 repair applied if p3 structural prediction differs
from p2.

p2/p3 repair table:
  p2=push, p3=no-op  -> repair: pop
  p2=no-op, p3=pop   -> repair: pop
  p2=pop,  p3=no-op  -> repair: push
  p2=no-op, p3=push  -> repair: push
Note: push->pop and pop->push within one p2/p3 pair cannot occur.

Repair label semantics: the push/pop labels above denote
stack-height restoration of resident entries, not fresh
allocation or array clear.
  - p2=push, p3=no-op (undo-push): TOSR retract of the
    still-resident frontier slot. If that slot carried a
    recursion count the count is decremented in place;
    otherwise TOSR moves back one slot. The array entry is
    not cleared.
  - p2=pop, p3=no-op (undo-pop): TOSR re-expose. TOSR moves
    back up one slot to re-expose the still-resident entry the
    pop uncovered. No array write, TOSW held.
  - p2=no-op, p3=pop (missed pop): same TOSR retract as
    undo-push.
  - p2=no-op, p3=push (missed push): the only case that
    allocates and writes. The registered fallthrough is
    written at the frontier and TOSW advances.

Limitation (TD #78): undo-pop re-expose does NOT reverse a
recursion-decrement pop. A pop that only decremented the
recursion counter (TOSR held) leaves no recoverable pre-pop
count; the re-expose moves TOSR by a slot instead. Pinned by
tb_ras TC-21. See PROJECT_STATUS TD #78.

RAS does not generate a redirect signal in the same sense as
TAGE or SC. It provides the initial p0 prediction (TOS read)
and participates in the p2 redirect when FTB disagrees with
the uBTB p0 result.

No PQ, UQ, or credit arbiter. RAS does not have synchronous
SRAMs. See bp_arb_spec.md section 7.2.

### 1.1  Stage and update notes

- Stage:  p2 push/pop + spec_pop_addr; p3 = p2 registered.
- Update: speculative at p2 (separate from main update channels).
          Commit stack updated at retire/commit, not post-execute.
- Outside the conditional branch override chain.

### 1.2  Role in redirect architecture

p2_redirect: fires when FTB/TAGE/RAS result disagrees with
  uBTB p1. For return branches, RAS spec_pop_addr is the
  redirect target.

p3_redirect: RAS p3 = p2 registered. Stack repair applied at
  p3 if p3 structural prediction disagrees with p2 (see repair
  table above). The repair restores stack height of resident
  entries; it does not allocate (except the missed-push case)
  or clear the array. Undo-pop does not reverse a recursion-
  decrement pop (TD #78). See the repair label semantics in
  section 1.

---

## 2. Call and Return Detection

Detection is by RISC-V register convention, not by opcode
alone. FTB structural prediction provides branch type to RAS.

Call instructions (push trigger):
  JAL   rd=x1 or rd=x5
  JALR  rd=x1 or rd=x5
  C.JALR          (implicit rd=x1)

Return instructions (pop trigger):
  JALR  rs1=x1 or rs1=x5, with rd not a link register or rd==x0
  C.JR  rs1=x1 or rs1=x5
  C.JALR with rs1=x5 is excluded from return classification.

Pop-then-push (RETURN_CALL):
  JALR  rd and rs1 BOTH link registers and rd != rs1

RETURN_CALL, session-069. The specification's return-address-stack
hints make a JALR whose rd and rs1 are both link registers and are
UNEQUAL a pop followed by a push. An earlier revision of the return
rule excluded every JALR with a link rd, which covers two different
cases:

```
  rd == rs1, both link   push only. The exclusion is CORRECT; the
                         specification agrees.
  rd != rs1, both link   pop THEN push. The exclusion dropped the
                         pop, so the stack grew by one on every
                         such instruction instead of staying level.
```

`bp_br_type_e` gains RETURN_CALL at 3'b111, the one free encoding
in the 3-bit enum. It is a package edit, so the verification run
widens to both units.

THE OWNERSHIP RULE BELOW SURVIVES IT. The package comment on the
enum worried that a JALR satisfying both the call and the return
rule would break the mutually exclusive RAS / ITTAGE split. It does
not, because RETURN_CALL is a SINGLE classification and it is
unambiguously the RAS's: ownership decides which predictor handles
an instruction, and this one is handled by the RAS performing two
operations rather than by two predictors performing one each.
An earlier revision called this a "three-way ... FTB / RAS /
ITTAGE split"; the FTB is not an arm of it, see below.

JALR ownership:
  RAS:    JALR/C.JR/C.JALR matching return register convention
  ITTAGE: every other indirect JALR

RAS and ITTAGE are mutually exclusive by branch type, resolved by FTB
structural prediction before p2. THE FTB IS NOT A THIRD ARM. An
earlier revision read "Three-way JALR split with FTB and ITTAGE" with
"FTB: JALR with fixed stable target (most direct calls)". The FTB
target is the ITTAGE-MISS FALLBACK (ftb_decisions.md 4.2), selected
by hit rather than by how stable the target is, so it is not a
type-based arm alongside the other two. ittage_interfaces.md and
bp_cluster.md carried the same error. fe_decisions.md 3.3. Corrected
session-070.

---

## 3. Dual-Stack Structure

### 3.1  Structure decision

DECIDED session-050: static partition, two independent physical
arrays. One speculative stack, one commit stack.

Rejected: unified pool (single 48-entry array shared between
speculative and commit). Rationale: static partition keeps
overflow detection at fixed limits, mispredict restore touches
only the speculative array, commit advancement touches only the
commit array. Pointer arithmetic and verification complexity
both minimized. 48-entry total budget is generous enough that
the flexibility of a unified pool is not needed.

Revisit trigger: SPEC benchmark performance analysis at
bp_cluster integration. If commit stack overflow is a measured
event under real workloads, rebalance the split before any
structural change.

### 3.2  Speculative stack

Entries:   16
Structure: simple circular buffer. No linked-list structure.
Purpose:   Covers in-flight call depth between fetch and commit.

Snapshot for mispredict recovery: three pointers (TOSR, TOSW,
BOS) saved per FTQ entry. On mispredict, restore all three from
the FTQ snapshot of the last known-good entry. Full speculative
history is preserved in the circular buffer -- no replay of
individual operations needed provided the buffer has not wrapped.

DECIDED session-050: simple circular buffer chosen over the
Xiangshan Kunminghu linked circular array. Academic literature
(Desmet et al., ACM TACO) shows no measurable IPC benefit from
linked speculative stacks over a simple circular buffer with a
BTB fallback for detected corruption. Commercial designs
(AMD Zen 1-5, Intel Golden Cove through Lion Cove) all use
pointer-only recovery. Complexity cost not justified.

Revisit trigger: RAS misprediction rate under SPEC benchmarks
shows wrong-path corruption as a significant contributor.
Candidate remedies at that point: linked structure or corruption
detector per Desmet et al.

Entry fields:
  ret_addr  : VA_WIDTH bits  -- PC+2 or PC+4 of instruction
                                after call (compressed vs full)
  rctr      : 4b             -- recursion counter (see section 5)

Pointers (all RAS_PTR_BITS wide, $clog2(RAS_SPEC_ENTRIES)=4b):
  TOSR  -- Top Of Stack Read: current top for predictions
  TOSW  -- Top Of Stack Write: next free allocation slot
  BOS   -- Bottom Of Stack: boundary of committed state

Push: write ret_addr and rctr to TOSW slot. TOSR = TOSW.
      TOSW advances to next slot. The BOS index is a permanent
      sentinel: a push that would land TOSW on BOS allocates at
      BOS+1 instead. This occurs at cold-start after reset, or on
      a full circular wrap. The sentinel keeps a single live
      entry distinguishable from empty.
Pop:  present TOSR entry as prediction. TOSR decrements.
      No data overwritten on pop.

Empty condition: TOSR == BOS. On pop when empty, fall through
to commit stack top as prediction result. Commit stack entry
is not consumed (read-only fallback).

Usable speculative depth: RAS_SPEC_ENTRIES - 1 = 15 entries
(16 physical). One slot is always reserved as the BOS sentinel
so that empty (TOSR == BOS) is never aliased by a full stack.

Full condition: TOSW + 1 == BOS (mod RAS_SPEC_ENTRIES). 15
entries live, one push remaining. Overflow (wrap) condition:
the next push finds TOSW == BOS and takes the sentinel skip.
No fault is raised and no error signal is asserted.

Overflow effect: the wrap is not the loss of one entry.
Allocation lands at BOS+1, so TOSR becomes BOS+1 and the
reachable depth (BOS to TOSR) collapses to one entry in a
single push. The older entries stay physically resident but
are unreachable -- the following pop hits TOSR == BOS and
takes the commit-stack fallback. Degradation is bounded by
that fallback, not gradual. Do not describe this as graceful
single-entry loss.

### 3.3  Commit stack

Entries:   32
Structure: conventional circular stack.
Purpose:   Covers steady-state live call nest depth for
           committed instruction stream.

Entry fields:
  ret_addr  : VA_WIDTH bits
  rctr      : 4b

Pointer:
  CSP  -- Commit Stack Pointer: points to current top

Update: when a call-containing prediction block commits from
the FTQ, the return address is pushed onto the commit stack
and CSP advances. BOS in the speculative stack advances to the
committing entry's post-op TOSR (ras_commit_snapshot.tosr),
marking the new committed boundary. A mispredict restore in the
same cycle wins over commit for BOS (restore > commit > hold).

On commit of a return: CSP decrements. The commit stack entry
is consumed. BOS likewise advances to the committing entry's
post-op TOSR (ras_commit_snapshot.tosr).

Overflow condition: CSP is a free pointer with no base
register. Empty is CSP == 0, the top is at CSP-1, and overflow
is the wrap of CSP to 0 on the 32nd consecutive commit push.
No fault is raised.

Overflow effect: the wrap makes a FULL commit stack read as
EMPTY -- commit_top_valid deasserts, so the p0 TOS read and
the speculative-empty pop fallback lose their source until CSP
advances again. Accepted, not guarded: a lost fallback yields
no prediction rather than a wrong one. Rebalance the 16/32
split per the 3.1 revisit trigger if this is measured. TD #121.

---

## 4. Snapshot and Restore Protocol

### 4.1  Snapshot contents

bp_ras_snapshot_t is a packed struct stored in bp_ftq_entry_t.
Fields (from bp_structs_pkg.sv):
  tosr  : RAS_PTR_BITS  -- speculative TOS read pointer
  tosw  : RAS_PTR_BITS  -- speculative TOS write pointer
  bos   : RAS_PTR_BITS  -- committed boundary pointer

RAS_PTR_BITS = $clog2(RAS_SPEC_ENTRIES) = $clog2(16) = 4b.
Total snapshot width = 3 * RAS_PTR_BITS = 12b per FTQ entry.

FTQ access pattern: entry.ras.tosr, entry.ras.tosw, entry.ras.bos

### 4.2  Snapshot write timing

Snapshot is written into the FTQ entry at the time the
prediction that consumed or produced the RAS state is issued.
One snapshot per FTQ entry.

On a push (call detected): snapshot the post-push pointer state.
On a pop (return detected): snapshot the post-pop pointer state.
On neither: snapshot current pointer state unchanged.

### 4.3  Restore on mispredict

On mispredict redirect from any predictor: restore TOSR, TOSW,
BOS from the FTQ snapshot of the mispredicted entry. The
circular buffer data is not cleared -- restoration is pointer-
only. Subsequent pushes and pops write into slots above the
restored TOSR, which may overwrite stale speculative data from
the wrong path. This is correct behavior.

### 4.4  Restore on flush -- DECIDED, RAS-3 CLOSED

THIS SECTION IS THE SINGLE SOURCE FOR THE RAS RESPONSE TO A FLUSH.
Every other document points here. Do not restate it elsewhere and do
not re-derive it.

THE DECISION. RAS restore on flush is the same pointer-restore
protocol as mispredict recovery, section 4.3: TOSR, TOSW and BOS are
restored from the FTQ snapshot of the youngest valid entry before the
flush point. The circular data is not cleared. There is NO
flush-specific RAS behaviour, no separate flush protocol, and nothing
for a flush to do to the RAS that a redirect does not already do.

THE MECHANISM IS BUILT AND TESTED. It is `ras_restore_val` /
`ras_restore_snapshot`, D2 of ftq_backend_interfaces.md 5, wired
through bp_cluster and implemented in ras.sv: the three pointers are
restored under `restore > commit > hold` priority, and tb_ras drives
it. This is not a plan. It is working RTL with coverage.

A backend redirect carries mispredict, trap and replay on ONE port
set (ftq_backend_interfaces.md 5), so the trap case reaches the RAS
through the same restore as any other redirect. That is why no
additional path is needed.

Even the residual case is bounded. Speculative RAS corruption is
self-correcting from both ends: TOSR unwinds toward BOS as the
program returns, and on a pop when TOSR == BOS the prediction falls
through to the commit stack (section 3.2), which is architectural
state; and BOS advances toward TOSR on every commit (section 3.3).
Corruption is squeezed, not merely drained.

### 4.4.1  What is still open, and what it is not

NOTHING. BP-105 closed the last piece: THERE IS NO FLUSH EVENT. A
flush is a redirect (fe_decisions.md FE-14), the front end has no
separate flush protocol, and a predictor is cleared by withholding
its stage valid rather than by being told anything.

This subsection previously said the `_px` signalling was an open
front-end-wide question tracked as G24 / IC-FTB-07. Both are now
closed by decision. The `_px` ports are redundant and retained.

So the RAS response to a flush is the pointer restore of 4.3,
because a flush IS a redirect and that is what a redirect does.

### 4.4.2  Do not reopen this -- read this first

RAS-3 was carried as OPEN from session-050 to 2026-08-20 while this
section already specified the answer. It was re-raised repeatedly.
Three artifacts caused that, and all three are still present by
design:

- `ras_flush_val` and `ras_flush_snapshot` are DECLARED ON ras.sv AND
  READ BY NOTHING. They are redundant with the restore group above.
  They are deliberately LEFT IN PLACE; removing them is not worth
  touching a green module for. A DECLARED PORT WITH NO BEHAVIOUR IS
  NOT EVIDENCE OF AN OPEN DESIGN QUESTION. Here it is evidence of a
  redundant port, and that is all.
- This section previously OPENED with "Flush (_px signals) not yet
  defined", so a reader met the gap before the decision and stopped
  there. The decision now comes first.
- The registry entry said "Recovery on flush. OPEN" while this
  section said what recovery on flush is. The registry contradicted
  the section it pointed to.

If you have arrived here because something looked unfinished: it is
not. The RAS half of flush is closed. If you are defining the flush
EVENT, see 4.4.1 -- that work does not touch this section.

### 4.5  Commit

On FTQ entry commit: the speculative entry is confirmed. BOS
advances to the committing entry's post-op TOSR
(ras_commit_snapshot.tosr). No speculative RAM write occurs.
A mispredict restore in the same cycle wins over commit for BOS
(restore > commit > hold). Commit stack is updated as described
in section 3.3.

---

## 5. Recursion Counter

DECIDED session-050: 4-bit counter per entry, in scope for
initial design.

Purpose: when the same return address is pushed multiple times
(self-recursive or mutually recursive calls), increment the
counter of the current TOS entry rather than allocating a new
entry. Suppresses duplicate pushes and preserves stack depth
budget for non-recursive call depth.

Counter width: 4b. Tracks up to 15 repeated pushes of the same
return address before saturating. Saturation behavior: counter
holds at 15, additional pushes are suppressed. On pop: if
rctr > 0, decrement rctr without moving TOSR. If rctr == 0,
pop normally (TOSR decrements).

Match condition: incoming push address equals ret_addr at TOSR
and the speculative stack is not empty (TOSR != BOS).

Recursion detection applies to the speculative stack only. The commit stack
rctr field is reserved and is currently written zero on every commit push; it
is not read by any output path. Commit-stack recursion depth is therefore not
preserved: a recursive call that commits reads back from the commit-stack
fallback as a single entry, not at its true depth. This is a documented
limitation, not a functional defect (the field is write-only). See TD #79.
Resolution deferred to bp_cluster/FTQ integration, when a recursion-count
source on the commit interface can be decided.

---

## 6. Dual-Slot Interaction

DECIDED session-050.

### 6.1  The two slots (REWRITTEN session-069)

Both slots are branch fields of ONE 32-byte prediction block.
Slot 0 is the block's first branch in program order and slot 1
the second, each located by its own `pos` inside the block's 16
two-byte positions (`fe_decisions.md` FE-10,
`ftq_entry_formats.md`, `ubtb_interfaces.md`). Neither slot has
a fixed PC.

THE PREVIOUS TEXT DESCRIBED A SUPERSEDED MODEL and is kept here
because the RTL may still implement it. It had slot 0 cover
pred_pc to pred_pc+31 and slot 1 cover pred_pc+32 to pred_pc+63,
with slot 1's PC always pred_pc+32:

```
  Fixed boundary split. Slot 0 covers pred_pc to pred_pc+31.
  Slot 1 covers pred_pc+32 to pred_pc+63. Slot 1 PC is always
  pred_pc+32. Static, not data-dependent on slot 0 prediction.
```

That is two 32-byte blocks inside a 64-byte region, which is
FETCH_BLOCK_BYTES standing in for FTB_BLOCK_BYTES. The two are
independent and must not be collapsed (`ftb_decisions.md` 2.3).
The text dates from session-050 and predates the single-lookup
32-byte block model of session-063.

Evaluation order is unchanged and still needed: slot 0 before
slot 1, slot 1 seeing the pointer state slot 0 left. That is
IC-RAS-03 slot priority.

### 6.2  Same-cycle combinations (SUPERSEDED session-069)

AT MOST ONE SLOT CAN CARRY A RAS OPERATION. `fe_decisions.md`
FE-11: a RAS operation is a call or a return, both taken
branches, so a RAS operation in slot 0 ends the block before
slot 1 is reached. With 6.1 corrected, both slots are in the
same block, so this applies to every combination below.

NONE OF THE FIVE COMBINATIONS CAN OCCUR. They are retained, not
deleted, because 6.3 and 6.4 describe logic that may exist in
the RTL and would now be dead. Confirming that is an RTL task,
not a documentation one.

THE ONE REAL TWO-OPERATION CASE IS NOT AMONG THEM. A JALR whose
`rd` and `rs1` are both link registers and are not equal is a
POP FOLLOWED BY A PUSH: one instruction, one slot, one position,
two RAS operations (`dcd_decisions.md` DCD-11, from the
specification's return-address-stack hints). FE-11's premise
excludes it wrongly; its conclusion, one snapshot per FTQ entry,
survives, because a pop-then-push at a single position needs no
second recovery point.

  RAS-DS1  The RAS accepts is_call and is_ret both set on one
           instruction and performs the pop first, then the
           push. On `ras_br_type_p2` that arrives as RETURN_CALL
           (section 2). Ordering is DCD-U2 and TD-DCD-2 verifies
           the built RAS against it.

The superseded five follow.

The five combinations the RAS must handle in a single cycle:

  slot0=call, slot1=call:
    Two pushes. If both addresses match current TOS and each
    other, increment rctr by 2 (or increment once per slot in
    priority order, clamped at 15). If addresses differ, push
    slot0 first, then slot1. TOSW advances by 2 (or 1 if
    recursion suppressed one push).

  slot0=return, slot1=return:
    Two pops. Pop slot0 first (TOSR decrements or rctr
    decrements). Pop slot1 from resulting state. Prediction
    for slot1 may require two levels of TOS traversal in the
    same cycle.

  slot0=call, slot1=return:
    Push slot0 return address. The address just pushed is
    immediately needed by slot1 pop. Same-cycle bypass
    required: slot1 pop target is forwarded from the slot0
    push data path without reading back from the array.

  slot0=return, slot1=call:
    Pop slot0 (TOSR decrements). Push slot1 return address
    to new TOSW. No bypass needed -- the push follows the pop
    with no dependency.

  neither slot is call or return:
    No RAS action.

### 6.3  Same-cycle bypass (SUPERSEDED session-069)

The case this serves, slot0=call with slot1=return, cannot occur
under 6.2. If the bypass exists in the RTL it is dead logic.

The slot0=call, slot1=return case requires a bypass path.
The return address pushed by slot0 is forwarded directly to
slot1's pop output in the same cycle. The bypass is detected
when slot0 is a call and slot1 is a return and the pushed
address would become the new TOS before slot1 pops.

This is a combinational forwarding path within the RAS push/pop
logic, not a RAM bypass. It is always present in the RTL;
the condition gating it is combinationally determined from the
slot0 and slot1 branch type inputs.

### 6.4  Recursion counter with two simultaneous pushes
###       (SUPERSEDED session-069)

Two simultaneous pushes require calls in both slots, which
cannot occur under 6.2. If this path exists in the RTL it is
dead logic. The single-push recursion counter of section 5 is
unaffected.

If slot0 and slot1 both push the same return address:
  - If that address matches the current TOS ret_addr:
      Increment rctr by 2 (saturating at 15).
      TOSW does not advance.
  - If that address does not match current TOS:
      Push once, set rctr to 1 (representing two occurrences).
      TOSW advances by 1.

If slot0 and slot1 push different addresses:
  - Push slot0 first (rctr check against current TOS).
  - Push slot1 second (rctr check against new TOS after slot0).
  - TOSW advances by 0, 1, or 2 depending on recursion matches.

---

## 7. Push Timing

OPEN ITEM RAS-1 from bp_arb_spec.md.

Push occurs at p2, when FTB structural prediction confirms the
branch type as call. Predecode provides an early hint that may
allow the push to be initiated before FTB confirms, but the
authoritative push is gated on FTB branch type at p2.

This is consistent with bp_cluster.md: RAS push/pop executes
at p2, spec_pop_addr valid at p2, p3 = p2 registered.

Implication: the return address is available one cycle after
the call instruction enters the prediction pipeline (p2). The
corresponding return will not appear until several cycles later
at minimum. No timing hazard from push latency under normal
conditions.

PARTIAL RESOLUTION: push occurs at p2 gated on FTB branch type.
Predecode early hint is an optimization deferred to RTL
implementation phase. RAS-1 may be closed when RTL confirms
the p2 push timing is sufficient for all call/return
interleavings.

---

## 8. Return Address Value

ret_addr stored in the stack is PC+2 or PC+4 of the instruction
after the call:
  - Full-width RVI call (4b): ret_addr = call_pc + 4
  - Compressed RVC call (2b): ret_addr = call_pc + 2

The FTB fallThroughAddr field provides this value. The RAS uses it
directly and does not independently compute PC+2 or PC+4.

NO STRADDLE CORRECTION EXISTS. An earlier revision of this section
said a +2 correction applies for full-width RVI calls truncated at
a prediction block boundary. That was the `last_may_be_rvi_call`
mechanism, which `ftb_decisions.md` 6 ELIMINATED; FTB-1 records
that no straddle correction exists. Corrected session-069.

It is eliminated rather than forgotten because `pft_addr` carries
the TRUE instruction end, not a value clamped at the block
boundary. A call is a taken branch and terminates the block, so
the fall-through IS the address after the call. The encoding
reaches past the block: `pftAddr` holds 0 to 16 at 2-byte
granularity, which is 0 to 32 bytes, and the carry bit adds a
further 32 (`ftb_decisions.md` 4.5, 5.5). A 32-bit call beginning
at the block's last halfword ends at block start plus 34, which is
`pftAddr` = 1 with carry set.

The straddle case is real, not hypothetical: `ifu_decisions.md`
IFU-8 covers 34 bytes and 17 halfword positions for exactly this
reason. It is handled by the fall-through arithmetic rather than
by a correction at the RAS.

VA_WIDTH = 40b covers the RVA23 implementation VA space.

---

## 9. Parameters

Defined in bp_defines_pkg.sv. Names and values to be added
when RAS RTL task is written.

  RAS_SPEC_ENTRIES   = 16        -- speculative stack depth
  RAS_COMMIT_ENTRIES = 32        -- commit stack depth
  RAS_RCTR_WIDTH     = 4         -- recursion counter bits
  RAS_ADDR_WIDTH     = VA_WIDTH  -- return address width

Pointer width (already present in bp_structs_pkg.sv as
RAS_PTR_BITS):
  RAS_PTR_BITS = $clog2(RAS_SPEC_ENTRIES) = 4b

bp_ras_snapshot_t uses RAS_PTR_BITS for tosr, tosw, bos.
Total snapshot width = 3 * RAS_PTR_BITS = 12b per FTQ entry.

Commit stack pointer width:
  RAS_COMMIT_PTR_BITS = $clog2(RAS_COMMIT_ENTRIES) = 5b
  Already present in bp_defines_pkg.sv.

---

## 10. Open Items

  RAS-1: Push timing. PARTIALLY RESOLVED. Push at p2 gated
         on FTB branch type. Predecode early hint deferred.
         Close when RTL confirms p2 timing is sufficient.

  RAS-2: Stack depth. RESOLVED session-050.
         16 speculative + 32 commit. See section 3.

  RAS-3: Recovery on flush. CLOSED 2026-08-20 -- and it was
         ALREADY ANSWERED by section 4.4 long before that date;
         only this label said otherwise. The RAS response to a
         flush is the pointer restore of 4.3, which is built and
         tested as ras_restore_val. BP-105 then closed the flush
         EVENT too: there is none, a flush is a redirect
         (fe_decisions.md FE-14). See 4.4.1.
         Do not re-raise from the unread ras_flush_* ports; see
         4.4.2.

---

## 11. Interactions With Other Planning Documents

  bp_cluster.md        -- architectural summary. RAS section
                          contains full detail by decision
                          (session-050). Duplication with this
                          document is intentional; to be
                          reconciled at a later session.
                          ras_decisions.md is canonical
                          authority where the two conflict.

  bp_arb_spec.md       -- arbitration model. Section 7.2
                          covers RAS non-RAM status. Open
                          item RAS-2 now closed. RAS-1
                          partially resolved. RAS-3 closed
                          2026-08-20 (section 4.4, section
                          10).
                          Section 2 predictor inventory RAS
                          row: p0 is TOS read only; push/pop
                          and redirect participation is at p2.

  bp_defines_pkg.sv    -- RAS_PTR_BITS, RAS_SPEC_ENTRIES,
                          RAS_COMMIT_ENTRIES, RAS_RCTR_WIDTH,
                          RAS_ADDR_WIDTH, RAS_COMMIT_PTR_BITS
                          all present.

  bp_structs_pkg.sv    -- bp_ras_snapshot_t confirmed present
                          with tosr/tosw/bos fields at
                          RAS_PTR_BITS each, matching section
                          4.1. Comment updated session-050 to
                          remove linked-array reference.

  tage_interfaces.md   -- no RAS interaction.

  ittage_interfaces.md -- no direct RAS interaction. JALR
                          ownership, RAS or ITTAGE, is defined in
                          section 2 of this document and in
                          bp_cluster.md. An earlier revision said
                          "three-way JALR split (FTB/RAS/ITTAGE)";
                          the FTB target is the ITTAGE-miss
                          fallback, not a third arm.
                          ftb_decisions.md 4.2.

---

## 12. Document History

  2026-06-23  session-050. Initial draft.
              Decisions recorded: static partition (G5),
              4b recursion counter (G6), fixed bundle split
              (G8), slot1 PC = pred_pc+32 (G17), simple
              circular buffer (internal structure).
              Full bp_cluster.md RAS content folded in:
              p2/p3 repair table, return address value
              (section 8), stage and update notes (section
              1.1), redirect architecture role (section 1.2).
              Dual-slot interaction cases enumerated.
              Same-cycle bypass documented.
              Open items RAS-1 partially resolved,
              RAS-2 closed, RAS-3 carried forward.
              Consistency pass session-050: parameter name
              aligned to RAS_PTR_BITS (matches bp_structs_
              pkg.sv). Section 11 corrected to reflect that
              bp_cluster.md duplication is intentional.

```
  2026-09-15  session-069. Section 6 reworked. 6.1 REWRITTEN: both
              slots are branch fields of one 32-byte block, each
              located by pos; the old fixed split at pred_pc+32
              was FETCH_BLOCK_BYTES standing in for
              FTB_BLOCK_BYTES and predates the session-063
              single-lookup model. 6.2, 6.3 and 6.4 SUPERSEDED:
              with 6.1 corrected, FE-11 makes all five cross-slot
              combinations unreachable, so the bypass and the
              two-push recursion path are dead logic if built.
              RAS-DS1 added: the one real two-operation case is
              DCD-11's pop-then-push within a single JALR.
              Superseded text retained, not deleted.

  2026-09-17  Section 11 bp_arb_spec.md entry read "RAS-3 open"
              while section 4.4's heading and section 10 both read
              CLOSED 2026-08-20. Corrected. This was the third
              artifact class of 4.4.2 -- a pointer entry
              contradicting the section it points at -- surviving
              one section below the warning against it. No
              protocol change; the label was the only thing wrong.
```
