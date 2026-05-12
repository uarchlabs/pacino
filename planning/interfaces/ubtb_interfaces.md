# uBTB Interface Specification
```
 FILE:    ubtb_interfaces.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-03-28
 CONTACT: Jeff Nye
```
 
---

## Overview

The uBTB (micro Branch Target Buffer) is a 256-entry 4-way
associative predictor. It fires at s1 and provides the first
next-PC prediction to the BP cluster. It does not generate
redirect signals. It provides or withholds a prediction only.

All types defined in bp_pkg.sv. This document describes port
semantics, timing contracts, and consumer/producer obligations.
It does not restate struct field layouts -- see bp_pkg.sv for
those.

---

## Module Parameters

  NUM_PRED_SLOTS : int  -- elaboration-time only. 1 or 2.
                          Value 3+ is undefined.

When NUM_PRED_SLOTS=1: one prediction output, one update input.
When NUM_PRED_SLOTS=2: two independent prediction outputs,
two independent update inputs. Slot 1 predicts the fetch block
immediately following slot 0 (pred_pc + 32).

---

## Port List

  clk      : input  logic                            -- rising edge
  rstn     : input  logic                            -- active low
  pred_pc  : input  logic [VA_WIDTH-1:0]             -- s0 input
  pred     : output ubtb_pred_t [NUM_PRED_SLOTS-1:0] -- s1 output
  upd      : input  ubtb_upd_t  [NUM_PRED_SLOTS-1:0] -- post-execute

---

## Prediction Interface

### Producer: uBTB
### Consumer: BP cluster (override control, s1 mux, FTQ write)

### Timing

  pred_pc is presented at s0 (combinational input).
  pred is combinational from registered mem.
  pred is valid at the start of s1 (one cycle after pred_pc).
  pred is held stable until the next pred_pc is presented.

### Semantics

  pred[s].valid = 1  -- uBTB hit for slot s. All other fields
                        in pred[s] are valid and must be consumed.
  pred[s].valid = 0  -- uBTB miss for slot s. All other fields
                        are driven 0 and must be ignored by the
                        consumer. No prediction for this slot.

  On miss: the BP cluster proceeds with fetch at PC+fetch_width.
  The uBTB does not assert any redirect or stall signal.

### pred[s] field semantics

  target   : predicted next fetch PC. Valid when pred[s].valid=1.
             Ignored by fetch when br_type==UBTB_BR_RET (RAS
             provides the target in that case at s2).

  br_type  : branch type encoding. Valid when pred[s].valid=1.
             Consumer must gate downstream behavior on br_type:
               UBTB_BR_NONE   -- no branch. target is fall-through.
               UBTB_BR_COND   -- conditional. br_taken is valid.
               UBTB_BR_DIRECT -- unconditional JAL. br_taken=1
                                 implied; do not rely on br_taken
                                 field.
               UBTB_BR_INDIR  -- indirect non-return JALR.
               UBTB_BR_CALL   -- call (rd=x1 or x5).
               UBTB_BR_RET    -- return (rs1=x1 or x5).
               3'b110, 3'b111 -- reserved. Treat as miss.

  br_taken : predicted direction. Meaningful only when
             br_type==UBTB_BR_COND. Present in struct for all
             types but consumer must ignore for non-COND.

  carry    : 1 when target[VA_WIDTH-1:5] != pred_pc[VA_WIDTH-1:5].
             Indicates the predicted target crosses into a
             different 32B-aligned fetch block than the current
             fetch PC. Used by the cluster to decide whether
             s1 prediction requires a fetch block change.

### Consumer obligations

  - Must not use pred[s].target when pred[s].valid=0.
  - Must not use pred[s].br_taken when br_type != UBTB_BR_COND.
  - Must write pred[s] into FTQ fast path (bp_ftq_entry_t)
    with pred_src set to identify uBTB as the provider.
  - Must compare pred[s] against s2 FTB/TAGE result and fire
    s2_redirect if they disagree.

---

## Update Interface

### Producer: post-execute resolution path (BP cluster)
### Consumer: uBTB

### Timing

  upd is a synchronous input. Sampled on rising clk edge.
  upd[u].valid may be asserted in any cycle.
  There is no ordering constraint between upd channels when
  NUM_PRED_SLOTS=2. Both channels are processed independently
  in the same cycle.

### Semantics

  upd[u].valid = 0  -- channel u carries no update this cycle.
                       All other upd[u] fields are ignored.
  upd[u].valid = 1  -- channel u carries a resolved update.
                       All other fields are valid and will be
                       written to the uBTB array.

### upd[u] field semantics

  pc       : fetch block PC of the resolved prediction.
             Used to derive set index and tag for the write.

  br_type  : resolved branch type. Written to the entry.

  target   : resolved next fetch PC. Written to the entry.

  br_taken : resolved direction. Written to the entry.
             Meaningful at read time only for UBTB_BR_COND.

  carry    : resolved carry bit. Written to the entry.
             carry = target[VA_WIDTH-1:5] != pc[VA_WIDTH-1:5].

### Read-during-write contract

  If upd[u].pc and pred_pc index the same set in the same
  cycle, pred reflects the pre-update (registered) state.
  The new entry is visible on the following cycle.
  The producer must not depend on same-cycle readback.

### Producer obligations

  - Must provide resolved target and br_type, not speculative.
  - Must compute carry correctly before asserting valid.
  - Must not assert valid on the same pc via both channels
    in the same cycle (undefined update order).

---

## Miss Signaling Contract

The uBTB has no miss output port. Miss is implied by
pred[s].valid=0. The BP cluster is responsible for detecting
the miss condition and continuing fetch sequentially.

The uBTB does not stall, does not generate a redirect, and
does not communicate miss reason or miss type externally.

---

## Known Gaps and Deferred Items

| ID  | Item                                      | Status           |
|-----|-------------------------------------------|------------------|
| UI1 | Slot 1 PC derivation (pred_pc + 32)       | Assumed at BP-003|
|     | exact split point is G8 in bp_cluster.md  | revisit at fetch |
|     | (TBD at fetch interface)                  | interface        |
| UI2 | carry field consumer behavior in cluster  | TBD at           |
|     | top -- how cluster uses carry to decide   | bp_cluster impl  |
|     | fetch block change vs. continue           |                  |
| UI3 | Update channel arbitration when both      | G9 in            |
|     | channels write to the same set same cycle | bp_cluster.md    |
| UI4 | UBTB_BR_NONE target field value on hit    | TBD -- is target |
|     |                                           | fall-through PC  |
|     |                                           | or zero?         |

