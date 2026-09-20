<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# RAS Interface Specification
```
 FILE:    ras_interfaces.md
 SOURCE:  session-050
 STATUS:  DRAFT
 UPDATED: 2026-09-19
 CONTACT: Jeff Nye
```

Interface contract for ras.sv. Companion to
planning/arch/ras_decisions.md (micro-architectural decisions)
and planning/arch/bp_arb_spec.md section 7.2 (arbitration role).
Claude Code loads this file when implementing or modifying ras.sv
or tb_ras.sv.

Note on stage notation: planning documents use s-stage notation
(s0/s1/s2/s3). RTL and port names use p-stage notation
(p0/p1/p2/p3). They are equivalent: s0=p0, s1=p1, s2=p2, s3=p3.
Port names in this document use p-stage notation to match RTL.
Narrative text uses s-stage notation to match planning documents.
Cleanup of this inconsistency is a future documentation task.

---

## 1. Module Overview

Single module ras.sv owns:
- Speculative stack (16 entries, simple circular buffer)
- Commit stack (32 entries, conventional circular stack)
- Push/pop logic per prediction slot. AT MOST ONE SLOT CARRIES A
  RAS OPERATION: a RAS operation is a taken branch and ends the
  block (FE-11, ras_decisions.md 6.2, SUPERSEDED session-069).
  This read "for both prediction slots in a single cycle".
- Same-cycle bypass for slot0=call, slot1=return. THAT CASE CANNOT
  OCCUR under FE-11; if the logic is in the RTL it is dead
  (ras_decisions.md 6.3, IC-RAS-04). Session-070.
- Recursion counter management
- p0/s0 TOS read, an input the cluster registers for the p1
  prediction (fe_decisions.md 2.2). Not itself a prediction
- Snapshot output per prediction for FTQ storage
- Restore input from FTQ on mispredict
- Commit stack update on FTQ commit
- p3/s3 repair logic

No PQ, UQ, or credit arbiter. No synchronous SRAMs.
Both stacks are register files.

RAS is outside the conditional branch override chain. It is
type-gated: push fires when br_type==DIRECT_CALL or
INDIRECT_CALL; pop fires when br_type==RETURN; RETURN_CALL pops
then pushes (IC-RAS-01, IC-RAS-02, ras_decisions.md 2). All
other branch types produce no RAS action. This list omitted
RETURN_CALL. Session-071. Branch type classification
is the responsibility of FTB; RAS does not classify
instructions independently.

---

## 2. Parameters

Defined in bp_defines_pkg.sv. All RAS RTL must use these
names. Do not use numeric literals for stack depths, pointer
widths, or counter widths.

  RAS_SPEC_ENTRIES    -- speculative stack depth (16)
  RAS_COMMIT_ENTRIES  -- commit stack depth (32)
  RAS_RCTR_WIDTH      -- recursion counter width (4)
  RAS_PTR_BITS        -- speculative pointer width
                         $clog2(RAS_SPEC_ENTRIES) = 4b
                         Already present in bp_defines_pkg.sv.
  RAS_COMMIT_PTR_BITS -- commit pointer width
                         $clog2(RAS_COMMIT_ENTRIES) = 5b
  RAS_ADDR_WIDTH      -- return address width = VA_WIDTH = 41b
                         (40b until TD#122 lands in the RTL)

---

## 3. Port Naming Convention

Signal names follow the pattern:
  <signal>_<pipestage>

  pipestage: p0, p1, p2 for prediction path.
             p3 for s3 repair.
             u0, u1 for update/commit path.
             px for flush signals. Reserved and unread. There
             is no flush event and no flush protocol; see
             RI-1 and ras_decisions.md 4.4.

Prediction slot dimension uses array index [0:NUM_PRED_SLOTS-1]
on the signal, not a suffix. Example:

  input  logic  ras_pred_val_p2[0:NUM_PRED_SLOTS-1]

clk and rstn carry no pipe stage suffix.

---

## 4. Port List

```systemverilog
module ras (
  input  logic clk,
  input  logic rstn,

  // ----------------------------------------------------------
  // p0/s0: TOS read, before the FTB result.
  // Combinational read of current TOSR entry per slot.
  // Registered by the cluster and applied by the p1 mux as
  // the target of a RETURN slot. Drives no FTQ port.
  // No push or pop at p0.
  // ----------------------------------------------------------
  output logic [VA_WIDTH-1:0] ras_tos_addr_p0[0:NUM_PRED_SLOTS-1],
  output logic                ras_tos_valid_p0[0:NUM_PRED_SLOTS-1],

  // ----------------------------------------------------------
  // p2/s2: Prediction inputs
  // FTB structural prediction valid. Push/pop gates on these.
  // ----------------------------------------------------------
  input  logic          ras_pred_val_p2[0:NUM_PRED_SLOTS-1],
  input  bp_br_type_e   ras_br_type_p2[0:NUM_PRED_SLOTS-1],

  // FTB fallthrough address per slot.
  // Pushed as ret_addr on call. RAS does not compute PC+2/+4.
  input  logic [VA_WIDTH-1:0] ras_fall_through_p2[0:NUM_PRED_SLOTS-1],

  // Branch PC per slot. Declared in ras.sv, not read. See TD #101.
  input  logic [VA_WIDTH-1:0] ras_pc_p2 [0:NUM_PRED_SLOTS-1],

  // ----------------------------------------------------------
  // p2/s2: Prediction outputs
  // ----------------------------------------------------------
  // Pop address (return target prediction) per slot.
  output logic [VA_WIDTH-1:0] ras_pop_addr_p2[0:NUM_PRED_SLOTS-1],
  // Asserted when a valid pop address is available.
  // Deasserted when both speculative and commit stacks empty.
  output logic                ras_pop_valid_p2[0:NUM_PRED_SLOTS-1],

  // RAS snapshot per slot for FTQ fast-path write.
  // Post-operation pointer state (see IC-RAS-08).
  output bp_ras_snapshot_t    ras_snapshot_p2[0:NUM_PRED_SLOTS-1],

  // ----------------------------------------------------------
  // p3/s3: Repair inputs
  // Registered FTB prediction, one cycle after p2.
  // Used to detect and undo incorrect p2 push/pop.
  // See IC-RAS-11 and ras_decisions.md section 1.
  // ----------------------------------------------------------
  input  logic          ras_pred_val_p3[0:NUM_PRED_SLOTS-1],
  input  bp_br_type_e   ras_br_type_p3[0:NUM_PRED_SLOTS-1],

  // ----------------------------------------------------------
  // Mispredict restore (driven by FTQ)
  // ----------------------------------------------------------
  input  logic             ras_restore_val,
  input  bp_ras_snapshot_t ras_restore_snapshot,

  // ----------------------------------------------------------
  // Commit inputs (driven by FTQ at retire)
  // One commit event per cycle. FTQ retires one entry per
  // cycle; dual-slot commit is not required.
  // ----------------------------------------------------------
  input  logic                ras_commit_val,
  input  bp_br_type_e         ras_commit_br_type,
  input  logic [VA_WIDTH-1:0] ras_commit_ret_addr,
  input  bp_ras_snapshot_t    ras_commit_snapshot,

  // ----------------------------------------------------------
  // Flush. RESERVED AND UNREAD -- not TBD. A flush is a
  // redirect (fe_decisions.md FE-14); the RAS response is the
  // pointer restore above. These two ports are redundant and
  // are intentionally left unread. Read ras_decisions.md 4.4
  // and 4.4.2 before reopening this.
  // ----------------------------------------------------------
  input  logic             ras_flush_val,
  input  bp_ras_snapshot_t ras_flush_snapshot
);
```

---

## 5. Struct Definitions

All structs defined in bp_structs_pkg.sv.

### bp_br_type_e

Branch type enum. RAS acts on:
  DIRECT_CALL, INDIRECT_CALL -- push trigger
  RETURN                     -- pop trigger
  RETURN_CALL                -- POP THEN PUSH, one instruction,
                                two operations (ras_decisions.md 2
                                and RAS-DS1, dcd_decisions.md
                                DCD-11a)
  All other values: no RAS action.

RETURN_CALL was added to bp_br_type_e at 3'b111 in session-069 and
was missing from this list and from IC-RAS-01, IC-RAS-02 and
IC-RAS-10. Session-070.

### bp_ras_snapshot_t

Packed struct, 3 * RAS_PTR_BITS wide:
  tosr : RAS_PTR_BITS  -- speculative TOS read pointer
  tosw : RAS_PTR_BITS  -- speculative TOS write pointer
  bos  : RAS_PTR_BITS  -- committed boundary pointer

With RAS_PTR_BITS=4: total 12b per snapshot.
Access pattern: entry.ras.tosr, entry.ras.tosw, entry.ras.bos

---

## 6. Prediction Interface

### Producer: FTB (branch type and fallthrough address)
### Consumer: RAS

### Timing

```
p0/s0: Combinational TOS read. ras_tos_addr_p0 and
       ras_tos_valid_p0 are valid combinationally from
       current TOSR. No push or pop at p0.

p2/s2: ras_pred_val_p2 and ras_br_type_p2 valid.
       Push or pop executes combinationally.
       ras_pop_addr_p2, ras_pop_valid_p2, ras_snapshot_p2
       all valid combinationally in p2.

p3/s3: ras_pred_val_p3 and ras_br_type_p3 are the
       registered p2 inputs. Repair logic compares p3
       FTB prediction against the p2 operation applied
       and executes the inverse if they disagree.
```

### Semantics

```
ras_pred_val_p2[s] = 1  -- valid FTB result for slot s.
                           RAS evaluates br_type and executes
                           push or pop as appropriate.
ras_pred_val_p2[s] = 0  -- no valid FTB result for slot s.
                           No push or pop for slot s.

ras_pop_valid_p2[s] = 1 -- ras_pop_addr_p2[s] is valid.
                           Used by s2_redirect logic when
                           br_type==RETURN.
ras_pop_valid_p2[s] = 0 -- both stacks empty; no valid
                           return address available.

ras_tos_valid_p0[s] = 1 -- ras_tos_addr_p0[s] holds the
                           current TOS return address.
                           Valid before FTB result at p2.
ras_tos_valid_p0[s] = 0 -- speculative and commit stacks
                           both empty.
```

Both slots may have ras_pred_val_p2 asserted in the same
cycle. Slot 0 is processed before slot 1. Slot 1 sees the
post-slot-0 pointer state.

---

## 7. Interface Contracts

### IC-RAS-01: Push gating

Push fires if and only if:
  ras_pred_val_p2[s] == 1
  AND ras_br_type_p2[s] == DIRECT_CALL, INDIRECT_CALL
      or RETURN_CALL

No push on any other branch type. On RETURN_CALL the push follows
the pop of IC-RAS-02 in the same operation. RAS does not make its
own call/return classification.

### IC-RAS-02: Pop gating

Pop fires if and only if:
  ras_pred_val_p2[s] == 1
  AND ras_br_type_p2[s] == RETURN or RETURN_CALL

No pop on any other branch type. On RETURN_CALL the pop comes
FIRST and supplies the predicted target; the push of IC-RAS-01
follows it (ras_decisions.md RAS-DS1).

### IC-RAS-03: Slot priority

AT MOST ONE SLOT CAN CARRY A RAS OPERATION. FE-11: a RAS operation
is a taken branch, so it ends the block before slot 1 is reached
(ras_decisions.md 6.2, SUPERSEDED session-069). The slot-priority
rule is retained because the RTL may implement it: when both slots
are active, slot 0 is processed before slot 1 and slot 1 sees the
post-slot-0 pointer state. This read "This applies to all five
same-cycle combinations"; none of the five can occur.
Session-070.

### IC-RAS-04: Same-cycle bypass

When slot 0 is DIRECT_CALL or INDIRECT_CALL and slot 1
is RETURN in the same cycle, slot 1's pop target is
forwarded combinationally from slot 0's push data without
reading back from the speculative stack array.

ras_pop_addr_p2[1] receives the forwarded value in this
case.

THE CASE CANNOT OCCUR. slot0=call with slot1=return needs two RAS
operations in one block, which FE-11 excludes (ras_decisions.md
6.2 and 6.3, SUPERSEDED session-069). If the bypass exists in the
RTL it is dead logic; confirming that is an RTL task. This read
"The bypass is always present in the RTL" as a live requirement.
Session-070.

### IC-RAS-05: Recursion counter

On push: if ras_fall_through_p2[s] equals ret_addr at
TOSR and the speculative stack is not empty (TOSR != BOS),
increment rctr at TOSR rather than allocating a new entry.
TOSW does not advance.

On pop: if rctr at TOSR > 0, decrement rctr without moving
TOSR. If rctr == 0, pop normally (TOSR decrements).

Saturation: rctr saturates at (2^RAS_RCTR_WIDTH - 1) = 15.
Additional pushes beyond saturation are suppressed.

See ras_decisions.md section 5 for the single-push recursion
counter. Section 6.4, two-slot simultaneous push, is SUPERSEDED:
two pushes need calls in both slots, which FE-11 excludes. The
single-push rule above is unaffected. Session-070.

### IC-RAS-06: Speculative stack overflow

TOSW + 1 == BOS (mod RAS_SPEC_ENTRIES) is the FULL condition:
15 entries live, one push remaining. The next push finds
TOSW == BOS, takes the sentinel skip, and wraps. No error
signal is asserted.

The wrap is not the loss of one entry. Allocation lands at
BOS+1, so TOSR becomes BOS+1 and reachable depth collapses to
one entry. The older entries remain physically resident but
unreachable: the following pop hits TOSR == BOS and takes the
IC-RAS-07 commit fallback. Consumers must not assume graceful
single-entry loss across a wrap.

### IC-RAS-07: Speculative stack empty fallback

When TOSR == BOS (speculative stack empty) and a pop is
requested, ras_pop_addr_p2[s] is driven from the commit
stack top, which is the CSP-1 entry, not the CSP entry
(ras_decisions.md 3.3). ras_pop_valid_p2[s] remains
asserted. The commit stack entry is NOT consumed.

The same fallback applies to ras_tos_addr_p0[s] at p0:
when the speculative stack is empty, the commit stack top
is presented as the TOS value.

If both speculative and commit stacks are empty,
ras_pop_valid_p2[s] and ras_tos_valid_p0[s] deassert.

### IC-RAS-08: Snapshot timing

ras_snapshot_p2[s] reflects post-operation pointer state
combinationally in p2. It is not registered before output.

Slot 0 snapshot reflects the state after slot 0's operation
only. Slot 1 snapshot reflects the state after both slot 0
and slot 1 operations have been applied.

The FTQ captures ras_snapshot_p2[NUM_PRED_SLOTS-1], the state
after both slots, on the rising edge closing p2, for every valid
block, through ftq_bpu_interfaces.md 4c. See ras_decisions.md
section 4.2.

### IC-RAS-09: Restore priority

ras_restore_val takes priority over any p2 push or pop in
the same cycle. When ras_restore_val is asserted, pointer
state is loaded from ras_restore_snapshot and no p2
push/pop is applied.

Only pointer state is restored. Circular buffer data is
not cleared. See ras_decisions.md section 4.3.

### IC-RAS-10: Commit stack update

On ras_commit_val with DIRECT_CALL, INDIRECT_CALL or RETURN_CALL
(RETURN_CALL commits as the net effect of its pop and push; see
ras_decisions.md RAS-DS1. Session-070):
  - Push ras_commit_ret_addr onto commit stack.
  - CSP advances.
  - BOS in speculative stack updated from ras_commit_snapshot.

On ras_commit_val with RETURN:
  - CSP decrements.
  - BOS updated accordingly.

Commit is registered (takes effect the cycle after
ras_commit_val is asserted). Commit does not interact with
p2 push/pop combinationally.

One commit event per cycle. The FTQ retires one entry per
cycle; dual-slot simultaneous commit does not occur.

### IC-RAS-11: p3/s3 repair

At p3 (p2 registered), if ras_br_type_p3[s] disagrees with
the p2 operation that was applied, an inverse repair is
applied to the speculative stack:

  p2=push, p3=no-op  -> repair: pop  (undo the push)
  p2=no-op, p3=pop   -> repair: pop  (apply missed pop)
  p2=pop,  p3=no-op  -> repair: push (undo the pop)
  p2=no-op, p3=push  -> repair: push (apply missed push)

push->pop and pop->push within one p2/p3 pair cannot occur.
Repair applies to the speculative stack only.
See ras_decisions.md section 1 (s2/s3 repair table).

Repair semantics: the push/pop labels denote stack-height
restoration of resident entries, not fresh allocation or array
clear. Undo-pop (p2=pop, p3=no-op) and undo-push (p2=push,
p3=no-op) move TOSR over still-resident entries with no array
write (undo-push decrements an in-place recursion count when
present). Only the missed-push case (p2=no-op, p3=push)
allocates and writes a new frontier entry. Undo-pop does NOT
reverse a recursion-decrement pop (TOSR held, rctr decremented):
the re-expose moves TOSR by a slot and the decremented count is
not recovered. See TD #78 and tb_ras TC-21.

### IC-RAS-12: Producer obligations (bp_cluster / FTQ)

- Must gate ras_pred_val_p2[s] on FTB result valid.
- Must present ras_br_type_p2[s] from FTB structural
  prediction, not from predecode or decode.
- Must present ras_br_type_p3[s] as the registered version
  of ras_br_type_p2[s] from the previous cycle.
- Must write ras_snapshot_p2[NUM_PRED_SLOTS-1] into
  bp_ftq_entry_t.ras for EVERY valid p2 block, through
  ftq_bpu_interfaces.md 4c, whether or not ras_pred_val_p2 was
  asserted for any slot. This read "ras_snapshot_p2[s] ... when
  ras_pred_val_p2[s] was asserted", which left the p1 initial
  value in a block with no FTB result. Session-071, ruled.
- Must assert ras_restore_val for one cycle on a redirect and
  present the FTQ snapshot of the entry the redirect names
  (ftq_backend_interfaces.md 5 D2). This read "the mispredicted
  entry". Session-071.
- Must assert ras_commit_val when a call- or return-
  containing FTQ entry commits.
- Must set pred_src = PRED_RAS in bp_ftq_entry_t when RAS
  provides the return target at p2.
- Must gate RAS override on br_type==RETURN or RETURN_CALL. This
  read "RETURN only"; RETURN_CALL's pop supplies the predicted
  target too (IC-RAS-02, ras_decisions.md RAS-DS1). Session-070.

---

## 8. Override Chain Position

RAS supplies the TARGET for a return. It takes no part in the
direction ranking, which is SC > TAGE > FTB on direction and is
suspended per branch when the FTB fast path fires
(ftb_confidence_override_rules.md 4.3, 4.2). Target is selected by
branch type, not ranked. An earlier revision read "RAS sits outside
the conditional branch override chain: SC > TAGE > FTB > uBTB",
which compresses the two. fe_decisions.md 12, narrowed session-070.

RAS is type-gated alongside TAGE and ITTAGE at p2:
  p1: uBTB + Loop
  p2: FTB + TAGE + ITTAGE + RAS
  p3: SC

RAS provides the return target at p2 when FTB identifies the branch
type as RETURN or RETURN_CALL -- for RETURN_CALL the pop supplies
the target and the push follows (ras_decisions.md RAS-DS1). RAS
supplies the target for those two types only. It does not
participate in direction prediction. This read "the branch type as
RETURN ... for return branches only". Session-070.

The p0/s0 TOS read (ras_tos_addr_p0) is available before the FTB.
The cluster registers it and the p1 selection mux applies it as the
target of a RETURN slot; the p1 prediction the FTQ acts on is the
cluster's, formed at p1 (fe_decisions.md FE-2, 2.2), and the p2
result may correct it. This read that the TOS read "is the initial
prediction the FTQ acts on". Session-071.

---

## 9. Timing Notes

### 9.1  Return address sourcing

ret_addr pushed to the speculative stack comes from
ras_fall_through_p2[s] (FTB-provided fallthrough address).
RAS does not independently compute PC+2 or PC+4.
See ras_decisions.md section 8.

### 9.2  Combinational paths in p2

The following signals are combinational in p2:

  ras_br_type_p2[0]  ->  push/pop decision slot 0
                     ->  TOSR/TOSW update (slot 0)
                     ->  bypass detect
  ras_br_type_p2[1]  ->  push/pop decision slot 1
                     ->  TOSR/TOSW update (slot 1, uses
                         post-slot-0 pointer state)
                     ->  ras_pop_addr_p2[1] (bypass or array)
  post-slot-0 state  ->  ras_snapshot_p2[0]
  post-slot-1 state  ->  ras_snapshot_p2[1]

Verilator stl_sequent note: always_comb blocks that must
re-evaluate after FF updates must read at least one FF
output. Gate the scan on a registered valid signal to
force nba_sequent classification. See CLAUDE.md.

---

## 10. Reset Behavior

On rstn deassert (active low, synchronous):
  - TOSR, TOSW, BOS all reset to 0.
  - CSP resets to 0.
  - All rctr fields reset to 0.
  - All ret_addr fields in both stacks reset to 0.
  - ras_pop_valid_p2 and ras_tos_valid_p0 deassert on
    the first cycle after reset.

---

## 11. Known Gaps and Deferred Items

| ID     | Item                                  | Status             |
|--------|---------------------------------------|--------------------|
| RI-1   | Flush port behavior. CLOSED. The RAS  | ras_decisions.md   |
|        | response to a flush is the pointer    | 4.4. Do not        |
|        | restore of 4.3, built as              | reopen from the    |
|        | ras_restore_val. ras_flush_val and    | unread ports;      |
|        | ras_flush_snapshot are redundant and  | see 4.4.2.         |
|        | intentionally left unread.            |                    |
| RI-2   | s/p stage notation inconsistency.     | Future doc         |
|        | Planning docs use s0-s3; RTL uses     | cleanup task.      |
|        | p0-p3. This document uses p-notation  | RTL is             |
|        | in port names and s-notation in       | authoritative.     |
|        | narrative to match existing practice. |                    |
| RI-3   | PHR/GHR contribution to RAS.          | N/A. RAS does      |
|        |                                       | not use folded     |
|        |                                       | history. No action.|

---

## 12. Interactions With Other Planning Documents

  ras_decisions.md     -- canonical decision record.
                          All micro-architectural decisions
                          cited by IC number above live there.

  bp_arb_spec.md       -- section 7.2: RAS non-RAM status,
                          snapshot/restore protocol overview.

  bp_cluster.md        -- pipeline staging, redirect
                          architecture, FTQ entry split
                          (bp_ras_snapshot_t in ftq_entry_t).

  bp_structs_pkg.sv    -- bp_ras_snapshot_t, bp_br_type_e,
                          bp_pred_src_e (PRED_RAS).

  bp_defines_pkg.sv    -- RAS_SPEC_ENTRIES, RAS_COMMIT_ENTRIES,
                          RAS_RCTR_WIDTH, RAS_PTR_BITS,
                          RAS_COMMIT_PTR_BITS, RAS_ADDR_WIDTH.

---

## 13. Document History

  2026-06-23  session-050. Initial draft.
              Port list corrected: slot dimension uses
              [0:NUM_PRED_SLOTS-1] array index, not _p0/_p1
              suffix. p-stage suffix denotes pipeline stage.
              s/p notation equivalence documented (RI-2).
              p0/s0 TOS read ports added (ras_tos_addr_p0,
              ras_tos_valid_p0). p3/s3 repair ports and
              IC-RAS-11 in scope for initial design.
              Dual-slot commit closed: one commit per cycle
              by FTQ design, no second channel needed.
              IC-RAS-07 extended to cover p0 TOS empty
              fallback. Open items reduced to RI-1 through
              RI-3.

  2026-09-19  session-071. The p0 TOS read is an input to the p1
              prediction, not the initial prediction the FTQ acts
              on (sections 1, 4 and 8). IC-RAS-08 and
              IC-RAS-12: the post-both-slots snapshot is written for
              every valid p2 block through ftq_bpu_interfaces.md
              4c; the restore presents the snapshot of the entry
              the redirect names.

