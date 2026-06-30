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
Override chain: outside the conditional branch override chain
(SC > TAGE > FTB > uBTB). RAS is type-gated -- active only
when FTB identifies the branch type as return.

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
  JALR  rs1=x1 or rs1=x5  (and rd != x1, rd != x5, or rd==x0)
  C.JR  rs1=x1 or rs1=x5
  C.JALR with rs1=x5 is excluded from return classification.

Three-way JALR split with FTB and ITTAGE:
  FTB:    JALR with fixed stable target (most direct calls)
  RAS:    JALR/C.JR/C.JALR matching return register convention
  ITTAGE: remaining indirect JALR, history-dependent targets

These are mutually exclusive by branch type, resolved by FTB
structural prediction before p2.

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

Overflow condition: TOSW + 1 == BOS (mod 16). On overflow,
oldest speculative entry is silently dropped (circular wrap).
Prediction accuracy degrades gracefully; no fault is raised.

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

Overflow condition: CSP + 1 == CSP_base (mod 32). Oldest
committed entry silently dropped. Same graceful degradation
policy as speculative stack.

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

### 4.4  Restore on flush

Flush (_px signals) not yet defined. When flush is specified,
RAS restore on flush must follow the same pointer-restore
protocol as mispredict recovery. The FTQ snapshot of the
youngest valid entry before the flush point provides the
restore state.

OPEN ITEM RAS-3: revisit when flush protocol is defined.
See bp_arb_spec.md section 11 item G.

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

### 6.1  Bundle split

Fixed boundary split. Slot 0 covers pred_pc to pred_pc+31.
Slot 1 covers pred_pc+32 to pred_pc+63. Slot 1 PC is always
pred_pc+32. Static, not data-dependent on slot 0 prediction.

Both slots evaluated in parallel. No serial dependency between
slot 0 and slot 1 RAS evaluation.

### 6.2  Same-cycle combinations

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

### 6.3  Same-cycle bypass

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

The FTB fallThroughAddr field provides this value. A +2
correction applies for full-width RVI calls truncated at a
prediction block boundary. The RAS uses the FTB-provided value
directly; it does not independently compute PC+2 or PC+4.

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
  RAS_COMMIT_PTR_WIDTH = $clog2(RAS_COMMIT_ENTRIES) = 5b
  (local use only; not yet in bp_defines_pkg.sv)

---

## 10. Open Items

  RAS-1: Push timing. PARTIALLY RESOLVED. Push at p2 gated
         on FTB branch type. Predecode early hint deferred.
         Close when RTL confirms p2 timing is sufficient.

  RAS-2: Stack depth. RESOLVED session-050.
         16 speculative + 32 commit. See section 3.

  RAS-3: Recovery on flush. OPEN. Flush (_px signals) not
         yet defined. Revisit when flush protocol is specified.
         See section 4.4.

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
                          partially resolved. RAS-3 open.
                          Section 2 predictor inventory RAS
                          row: p0 is TOS read only; push/pop
                          and redirect participation is at p2.

  bp_defines_pkg.sv    -- RAS_PTR_BITS already present.
                          RAS_SPEC_ENTRIES, RAS_COMMIT_ENTRIES,
                          RAS_RCTR_WIDTH, RAS_ADDR_WIDTH,
                          RAS_COMMIT_PTR_WIDTH to be added at
                          RTL task time.

  bp_structs_pkg.sv    -- bp_ras_snapshot_t confirmed present
                          with tosr/tosw/bos fields at
                          RAS_PTR_BITS each, matching section
                          4.1. Comment updated session-050 to
                          remove linked-array reference.

  tage_interfaces.md   -- no RAS interaction.

  ittage_interfaces.md -- no direct RAS interaction. The
                          three-way JALR split (FTB/RAS/ITTAGE)
                          is defined in section 2 of this
                          document and in bp_cluster.md.

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

