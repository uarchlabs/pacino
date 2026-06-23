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

---

## 1. Module Overview

Single module ras.sv owns:
- Speculative stack (16 entries, simple circular buffer)
- Commit stack (32 entries, conventional circular stack)
- Push/pop logic for both slots in a single cycle
- Same-cycle bypass for slot0=call, slot1=return case
- Recursion counter management
- Snapshot output per prediction for FTQ storage
- Restore input from FTQ on mispredict
- Commit stack update on FTQ commit

No PQ, UQ, or credit arbiter. No synchronous SRAMs.
Both stacks are register files.

RAS is outside the conditional branch override chain. It is
type-gated: push fires when br_type==DIRECT_CALL or
INDIRECT_CALL; pop fires when br_type==RETURN. All other
branch types produce no RAS action.

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

## 3. Port List

Module declaration:

  module ras (
    input  logic clk,
    input  logic rstn,
    ...
  );

### 3.1  Prediction inputs (s2, one per slot)

These arrive at s2 when FTB structural prediction is valid.
Branch type is provided by FTB; RAS does not classify
instructions independently.

  // Slot 0
  input  logic                     s2_pred_val_p0,
  input  bp_br_type_e              s2_br_type_p0,
  input  logic [VA_WIDTH-1:0]      s2_pc_p0,

  // Slot 1
  input  logic                     s2_pred_val_p1,
  input  bp_br_type_e              s2_br_type_p1,
  input  logic [VA_WIDTH-1:0]      s2_pc_p1,

s2_pred_val: asserted when the FTB result for this slot is
valid and should be acted on. RAS push/pop is gated on this.

s2_pc: PC of the call or return instruction. Used to compute
ret_addr = s2_pc + 2 (RVC) or s2_pc + 4 (RVI). The RAS
uses the FTB fallThroughAddr rather than computing this
independently; see section 5.1.

### 3.2  Return address inputs (s2, one per slot)

FTB provides the fallthrough address (PC+2 or PC+4) for
each slot. RAS pushes this value directly without
independent computation.

  input  logic [VA_WIDTH-1:0]      s2_fall_through_p0,
  input  logic [VA_WIDTH-1:0]      s2_fall_through_p1,

### 3.3  Prediction outputs (s2, one per slot)

  // Slot 0 pop result (return target prediction)
  output logic [VA_WIDTH-1:0]      s2_pop_addr_p0,
  output logic                     s2_pop_valid_p0,

  // Slot 1 pop result (return target prediction)
  output logic [VA_WIDTH-1:0]      s2_pop_addr_p1,
  output logic                     s2_pop_valid_p1,

s2_pop_addr: the predicted return target. Valid when
s2_pop_valid is asserted. Used by the s2_redirect logic
when br_type==RETURN and FTB/uBTB target disagrees.

s2_pop_valid: asserted when a valid return address is
available. Deasserted when the speculative stack is empty
and the commit stack fallback is also empty.

### 3.4  Snapshot output (s2, one per slot)

Written into the FTQ entry at prediction time. One snapshot
per slot per prediction cycle.

  output bp_ras_snapshot_t         s2_snapshot_p0,
  output bp_ras_snapshot_t         s2_snapshot_p1,

bp_ras_snapshot_t carries post-operation pointer state
(post-push for calls, post-pop for returns, unchanged for
neither). See ras_decisions.md section 4.2.

Snapshot fields (from bp_structs_pkg.sv):
  tosr : RAS_PTR_BITS  -- post-op speculative TOS read
  tosw : RAS_PTR_BITS  -- post-op speculative TOS write
  bos  : RAS_PTR_BITS  -- committed boundary (unchanged
                          until commit)

### 3.5  Mispredict restore input

Driven by the FTQ when a mispredict redirect is processed.
Restores the speculative stack to the state captured at the
mispredicted entry's prediction time.

  input  logic                     restore_val,
  input  bp_ras_snapshot_t         restore_snapshot,

restore_val: asserted for one cycle when a mispredict
restore is required. RAS latches the snapshot on this cycle.

restore_snapshot: the bp_ras_snapshot_t from the FTQ entry
of the mispredicted prediction. Provides tosr, tosw, bos.

Only pointer state is restored. Circular buffer data is not
cleared. See ras_decisions.md section 4.3.

### 3.6  Commit inputs

Driven by the FTQ when a prediction block commits.

  input  logic                     commit_val,
  input  bp_br_type_e              commit_br_type,
  input  logic [VA_WIDTH-1:0]      commit_ret_addr,
  input  bp_ras_snapshot_t         commit_snapshot,

commit_val: asserted when a committed FTQ entry contains
a call or return. Ignored for all other branch types.

commit_br_type: branch type of the committing instruction.
RAS acts on DIRECT_CALL, INDIRECT_CALL (push commit stack),
and RETURN (pop commit stack).

commit_ret_addr: return address to push onto commit stack
on a call commit. Sourced from the FTQ entry's stored
fallthrough address.

commit_snapshot: the snapshot from the committing FTQ
entry. Used to advance BOS in the speculative stack to
reflect the new committed boundary.

### 3.7  Flush input

Not yet defined. Placeholder port reserved.

  input  logic                     flush_val,
  input  bp_ras_snapshot_t         flush_snapshot,

See ras_decisions.md section 4.4 (RAS-3 OPEN).

---

## 4. Interface Contracts

### IC-RAS-01: Push gating

Push fires if and only if:
  s2_pred_val_pN == 1
  AND s2_br_type_pN == DIRECT_CALL or INDIRECT_CALL

No push on any other branch type. RAS does not make its
own call/return classification.

### IC-RAS-02: Pop gating

Pop fires if and only if:
  s2_pred_val_pN == 1
  AND s2_br_type_pN == RETURN

No pop on any other branch type.

### IC-RAS-03: Slot priority

When both slots are active in the same cycle, slot 0
is processed before slot 1. The slot 1 operation sees
the post-slot-0 pointer state.

This applies to all five same-cycle combinations:
call/call, return/return, call/return, return/call,
neither/neither. See ras_decisions.md section 6.2.

### IC-RAS-04: Same-cycle bypass

When slot 0 is a call and slot 1 is a return in the
same cycle, slot 1's pop target is forwarded
combinationally from slot 0's push data without reading
back from the speculative stack array.

s2_pop_addr_p1 receives the forwarded value in this case.
The bypass is always present in the RTL; its activation
is combinationally determined from s2_br_type_p0 and
s2_br_type_p1. See ras_decisions.md section 6.3.

### IC-RAS-05: Recursion counter

On push: if s2_fall_through_pN equals ret_addr at TOSR
and the speculative stack is not empty (TOSR != BOS),
increment rctr at TOSR rather than allocating a new entry.
TOSW does not advance.

On pop: if rctr at TOSR > 0, decrement rctr without
moving TOSR. If rctr == 0, pop normally (TOSR decrements).

Saturation: rctr saturates at (2^RAS_RCTR_WIDTH - 1) = 15.
Additional pushes beyond saturation are suppressed without
corrupting the stack.

See ras_decisions.md section 5 and 6.4 for two-slot
simultaneous push behavior.

### IC-RAS-06: Speculative stack overflow

When TOSW + 1 == BOS (mod RAS_SPEC_ENTRIES), the oldest
speculative entry is silently dropped on the next push
(circular wrap). Prediction accuracy degrades gracefully.
No error signal is asserted.

### IC-RAS-07: Speculative stack empty fallback

When TOSR == BOS (speculative stack empty) and a pop is
requested, s2_pop_addr_pN is driven from the commit stack
top (CSP entry). s2_pop_valid_pN remains asserted.
The commit stack entry is NOT consumed.

If both speculative and commit stacks are empty,
s2_pop_valid_pN deasserts.

### IC-RAS-08: Snapshot timing

s2_snapshot_pN reflects post-operation pointer state
in the same cycle as the push or pop. It is combinational
from the push/pop logic output, not registered.

The FTQ captures s2_snapshot at the end of s2 (on the
rising edge that closes the s2 cycle). The snapshot
written for slot 0 reflects the state after slot 0's
operation. The snapshot written for slot 1 reflects the
state after both slot 0 and slot 1 operations.

### IC-RAS-09: Restore priority

restore_val takes priority over any s2 push or pop in
the same cycle. When restore_val is asserted, pointer
state is loaded from restore_snapshot and no s2
push/pop is applied.

Rationale: a mispredict redirect invalidates all
speculative state including the current s2 prediction.

### IC-RAS-10: Commit stack update

On commit_val with DIRECT_CALL or INDIRECT_CALL:
  - Push commit_ret_addr onto commit stack.
  - CSP advances.
  - BOS in speculative stack updated to reflect new
    committed boundary.

On commit_val with RETURN:
  - CSP decrements.
  - BOS updated accordingly.

Commit is registered (takes effect the cycle after
commit_val is asserted). Commit does not interact with
s2 push/pop combinationally.

### IC-RAS-11: s3 repair

At s3 (s2 registered), if the s3 structural prediction
from FTB disagrees with the s2 operation, an inverse
repair is applied:

  s2=push, s3=no-op  -> pop  (undo the push)
  s2=no-op, s3=pop   -> pop  (apply the missed pop)
  s2=pop,  s3=no-op  -> push (undo the pop)
  s2=no-op, s3=push  -> push (apply the missed push)

push->pop and pop->push within one s2/s3 pair cannot
occur. The repair applies to the speculative stack only.
See ras_decisions.md section 1.

Repair inputs (s3):
  input  logic          s3_pred_val_p0,
  input  bp_br_type_e   s3_br_type_p0,
  input  logic          s3_pred_val_p1,
  input  bp_br_type_e   s3_br_type_p1,

These are registered versions of the s2 FTB prediction
inputs, provided to the RAS at s3 for repair comparison.

---

## 5. Timing Notes

### 5.1  Return address sourcing

ret_addr pushed to the speculative stack comes from
s2_fall_through_pN (FTB-provided fallthrough address).
The RAS does not independently compute PC+2 or PC+4.

For full-width RVI calls truncated at a prediction block
boundary, FTB applies the +2 correction before presenting
fallThroughAddr. The RAS is not aware of this correction.

### 5.2  Pipeline position

  s0: TOS read. s2_pop_addr driven combinationally from
      current TOSR for use as initial uBTB-miss fallback.
      No push or pop at s0.

  s2: FTB structural prediction valid. Push/pop executes.
      s2_pop_addr_pN, s2_pop_valid_pN, s2_snapshot_pN
      all valid combinationally in s2.

  s3: s2 registered. Repair logic compares s3 FTB
      prediction against s2 operation and applies
      inverse if needed.

  commit: Registered. Commit stack updated one cycle
          after commit_val asserted.

### 5.3  Combinational paths in s2

The following signals are combinational in s2 and must
not create timing loops:

  s2_br_type_p0  ->  push/pop decision slot 0
                 ->  TOSR/TOSW update (slot 0)
                 ->  bypass detect
  s2_br_type_p1  ->  push/pop decision slot 1
                 ->  TOSR/TOSW update (slot 1, uses
                     post-slot-0 pointers)
                 ->  s2_pop_addr_p1 (bypass or array)
  post-slot-1 pointers -> s2_snapshot_p0, s2_snapshot_p1

Verilator stl_sequent note: always_comb blocks that
evaluate pointer state after FF updates must read at
least one FF output to be classified nba_sequent. Gate
the scan on a registered valid signal. See CLAUDE.md.

---

## 6. Reset Behavior

On rstn deassert (active low, synchronous):
  - TOSR, TOSW, BOS all reset to 0.
  - CSP resets to 0.
  - All rctr fields reset to 0.
  - All ret_addr fields in both stacks reset to 0.
  - s2_pop_valid_p0, s2_pop_valid_p1 deassert.

---

## 7. Struct Reference

Structs used at the RAS boundary. All defined in
bp_structs_pkg.sv.

  bp_br_type_e       -- branch type enum. RAS acts on:
                        DIRECT_CALL, INDIRECT_CALL (push)
                        RETURN (pop)
                        All others: no action.

  bp_ras_snapshot_t  -- packed struct, 3 * RAS_PTR_BITS:
                        tosr : RAS_PTR_BITS
                        tosw : RAS_PTR_BITS
                        bos  : RAS_PTR_BITS

---

## 8. Open Items

  RI-1: s0 TOS read port. The s0 prediction path needs
        a combinational TOS read output for the initial
        uBTB-miss fallback before s2 push/pop executes.
        Port name and connection to the uBTB/FTQ path
        TBD at bp_cluster integration. Not required for
        unit-level ras.sv RTL or testbench.

  RI-2: Flush port behavior. flush_val and flush_snapshot
        are reserved (section 3.7). Behavior undefined
        until flush protocol is specified.
        Tracks ras_decisions.md RAS-3.

  RI-3: Dual-slot commit. Current commit interface
        handles one commit event per cycle (commit_val
        single signal). If two call/return slots can
        commit simultaneously, the interface requires
        a second commit channel. Confirm at bp_cluster
        integration. Likely single-commit is sufficient
        given FTQ entry granularity.

  RI-4: s3 repair port inclusion. The s3 repair inputs
        listed in IC-RAS-11 are not yet in the port list
        (section 3). Add when s3 repair RTL is scoped.
        Listed here to avoid omission at RTL task time.

---

## 9. Interactions With Other Planning Documents

  ras_decisions.md     -- canonical decision record.
                          All micro-architectural decisions
                          cited by section number above
                          live there.

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

## 10. Document History

  2026-06-23  session-050. Initial draft.
              Port list, interface contracts, timing notes,
              reset behavior, struct reference, open items.
              Based on ras_decisions.md session-050 and
              bp_arb_spec.md section 7.2.

