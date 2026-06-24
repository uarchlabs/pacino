<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# RAS Interface Specification
```
 FILE:    ras_interfaces.md
 SOURCE:  session-050
 STATUS:  DRAFT
 UPDATED: 2026-06-23
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
- Push/pop logic for both prediction slots in a single cycle
- Same-cycle bypass for slot0=call, slot1=return case
- Recursion counter management
- p0/s0 TOS read for initial prediction
- Snapshot output per prediction for FTQ storage
- Restore input from FTQ on mispredict
- Commit stack update on FTQ commit
- p3/s3 repair logic

No PQ, UQ, or credit arbiter. No synchronous SRAMs.
Both stacks are register files.

RAS is outside the conditional branch override chain. It is
type-gated: push fires when br_type==DIRECT_CALL or
INDIRECT_CALL; pop fires when br_type==RETURN. All other
branch types produce no RAS action. Branch type classification
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
  RAS_ADDR_WIDTH      -- return address width = VA_WIDTH = 40b

---

## 3. Port Naming Convention

Signal names follow the pattern:
  <signal>_<pipestage>

  pipestage: p0, p1, p2 for prediction path.
             p3 for s3 repair.
             u0, u1 for update/commit path.
             px for flush signals (not yet defined).

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
  // p0/s0: TOS read -- initial prediction before FTB result.
  // Combinational read of current TOSR entry per slot.
  // Driven to the FTQ/uBTB path as the earliest available
  // return target. No push or pop at p0.
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
  // Flush (reserved, behavior TBD)
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
  All other values: no RAS action.

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
  AND ras_br_type_p2[s] == DIRECT_CALL or INDIRECT_CALL

No push on any other branch type. RAS does not make its
own call/return classification.

### IC-RAS-02: Pop gating

Pop fires if and only if:
  ras_pred_val_p2[s] == 1
  AND ras_br_type_p2[s] == RETURN

No pop on any other branch type.

### IC-RAS-03: Slot priority

When both slots are active in the same cycle, slot 0
is processed before slot 1. The slot 1 operation sees
the post-slot-0 pointer state. This applies to all five
same-cycle combinations. See ras_decisions.md section 6.2.

### IC-RAS-04: Same-cycle bypass

When slot 0 is DIRECT_CALL or INDIRECT_CALL and slot 1
is RETURN in the same cycle, slot 1's pop target is
forwarded combinationally from slot 0's push data without
reading back from the speculative stack array.

ras_pop_addr_p2[1] receives the forwarded value in this
case. The bypass is always present in the RTL; its
activation is combinationally determined from
ras_br_type_p2[0] and ras_br_type_p2[1].
See ras_decisions.md section 6.3.

### IC-RAS-05: Recursion counter

On push: if ras_fall_through_p2[s] equals ret_addr at
TOSR and the speculative stack is not empty (TOSR != BOS),
increment rctr at TOSR rather than allocating a new entry.
TOSW does not advance.

On pop: if rctr at TOSR > 0, decrement rctr without moving
TOSR. If rctr == 0, pop normally (TOSR decrements).

Saturation: rctr saturates at (2^RAS_RCTR_WIDTH - 1) = 15.
Additional pushes beyond saturation are suppressed.

See ras_decisions.md sections 5 and 6.4 for two-slot
simultaneous push behavior.

### IC-RAS-06: Speculative stack overflow

When TOSW + 1 == BOS (mod RAS_SPEC_ENTRIES), the oldest
speculative entry is silently dropped on the next push
(circular wrap). No error signal is asserted.

### IC-RAS-07: Speculative stack empty fallback

When TOSR == BOS (speculative stack empty) and a pop is
requested, ras_pop_addr_p2[s] is driven from the commit
stack top (CSP entry). ras_pop_valid_p2[s] remains
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

The FTQ captures ras_snapshot_p2 on the rising edge closing
p2. See ras_decisions.md section 4.2.

### IC-RAS-09: Restore priority

ras_restore_val takes priority over any p2 push or pop in
the same cycle. When ras_restore_val is asserted, pointer
state is loaded from ras_restore_snapshot and no p2
push/pop is applied.

Only pointer state is restored. Circular buffer data is
not cleared. See ras_decisions.md section 4.3.

### IC-RAS-10: Commit stack update

On ras_commit_val with DIRECT_CALL or INDIRECT_CALL:
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

### IC-RAS-12: Producer obligations (bp_cluster / FTQ)

- Must gate ras_pred_val_p2[s] on FTB result valid.
- Must present ras_br_type_p2[s] from FTB structural
  prediction, not from predecode or decode.
- Must present ras_br_type_p3[s] as the registered version
  of ras_br_type_p2[s] from the previous cycle.
- Must write ras_snapshot_p2[s] into bp_ftq_entry_t.ras
  when ras_pred_val_p2[s] was asserted.
- Must assert ras_restore_val for one cycle on mispredict
  and present the FTQ snapshot of the mispredicted entry.
- Must assert ras_commit_val when a call- or return-
  containing FTQ entry commits.
- Must set pred_src = PRED_RAS in bp_ftq_entry_t when RAS
  provides the return target at p2.
- Must gate RAS override on br_type==RETURN only.

---

## 8. Override Chain Position

RAS sits outside the conditional branch override chain:
  SC > TAGE > FTB > uBTB

RAS is type-gated alongside TAGE and ITTAGE at p2/s2:
  p1/s1: uBTB + Loop
  p2/s2: FTB + TAGE + ITTAGE + RAS
  p3/s3: SC

RAS provides the return target at p2 when FTB identifies
the branch type as RETURN. RAS overrides FTB target for
return branches only. It does not participate in direction
prediction.

The p0/s0 TOS read (ras_tos_addr_p0) provides an earlier
prediction before FTB is available. This is the initial
prediction the FTQ acts on; it may be corrected by the p2
result.

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
  post-slot-1 state  ->  ras_snapshot_p2[0], ras_snapshot_p2[1]

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
| RI-1   | Flush port behavior. ras_flush_val    | Tracks RAS-3 in    |
|        | and ras_flush_snapshot reserved.      | ras_decisions.md   |
|        | Behavior undefined until flush        | section 4.4.       |
|        | protocol specified.                   |                    |
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

