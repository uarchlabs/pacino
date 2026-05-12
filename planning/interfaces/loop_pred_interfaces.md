# Loop Predictor Interface Specification

```
 FILE:    loop_pred_interfaces.md
 SOURCE:  various
 STATUS:  DRAFT, created session-006
 UPDATED: 2026-03-28
 CONTACT: Jeff Nye
```

---

## Overview

The Loop Predictor is a 256-entry 4-way associative predictor.
It fires at s1 alongside uBTB and provides a direction and
next-PC prediction for branches detected as constant-iteration
loops. It overrides uBTB at s1 when lp_pred_is_loop=1 and
confidence is at maximum (conf == LP_CONF_LEVEL). It does not
participate in the s2/s3 override chain.

Override control (not this module) makes the final s1 mux
decision. The loop predictor exposes pred_is_loop and the
prediction; it does not directly suppress the uBTB output.

All types defined in bp_pkg.sv. This document describes port
semantics, timing contracts, and consumer/producer obligations.
It does not restate struct field layouts -- see bp_pkg.sv.

---

## Module Parameters

  LP_TBL_ENTRIES : int -- default 256
  LP_TBL_WAYS    : int -- default 4
  LP_TAG_BITS    : int -- default 14
  LP_ITR_BITS    : int -- default 14
  LP_CNF_BITS    : int -- default 2
  LP_AGE_BITS    : int -- default 8
  LP_N_SETS      : int -- LP_TBL_ENTRIES / LP_TBL_WAYS
  LP_IDX_BITS    : int -- $clog2(LP_N_SETS)
  NUM_PRED_SLOTS : int -- elaboration-time only. 1 or 2.
                         Value 3+ is undefined.

When NUM_PRED_SLOTS=1: one prediction output, one update input.
When NUM_PRED_SLOTS=2: two independent prediction outputs,
two independent update inputs. Slot 1 predicts the fetch block
immediately following slot 0 (pred_pc + 32).

---

## Port List

  clk          : input  logic                             -- rising edge
  rstn         : input  logic                             -- active low
  pred_pc_p0   : input  logic [VA_WIDTH-1:0]              -- s0 input
  pred_valid_p0: input  logic                             -- s0 input
  pred_p0      : output lp_pred_t                         -- s1 output
  upd_p0       : input  lp_upd_t                          -- post-execute
  upd_valid_p0 : input  logic                             -- post-execute

---

## Prediction Interface

### Producer: loop_pred
### Consumer: BP cluster (override control, s1 mux, FTQ write)

### Timing

  pred_pc_p0 is presented at s0 (combinational input).
  pred_p0 is registered at end of s0, valid at start of s1.
  pred_p0 is held stable until the next pred_pc_p0 is
  presented.
  pred_valid_p0 gates the lookup. When pred_valid_p0=0,
  pred_p0.lp_pred_is_loop=0 and pred_p0.lp_pred_taken=0.

### Semantics

  pred_p0.lp_pred_is_loop = 1  -- loop predictor hit with
                               confidence at maximum. All
                               lp_pred_t fields are valid
                               and must be consumed by the
                               cluster override control.
  pred_p0.lp_pred_is_loop = 0  -- miss, or hit with confidence
                               below LP_CONF_LEVEL. Override
                               control must ignore lp_pred_taken
                               and defer to uBTB.

  On lp_pred_is_loop=0: the BP cluster uses the uBTB prediction
  for s1. The loop predictor does not assert any redirect or
  stall signal.

### pred_p0 field semantics

  lp_pred_is_loop : 1 when the loop predictor is trusted and
                    override control should select this output
                    over uBTB. 0 otherwise.

  lp_pred_taken   : predicted direction. Valid only when
                    lp_pred_is_loop=1. 1 = predict taken (still
                    inside loop body). 0 = predict not-taken
                    (loop exit).

  lp_idx          : set index derived from pred_pc_p0. Used
                    by the update path to address the correct
                    set without re-deriving from PC.

  lp_tag          : tag derived from pred_pc_p0. Used by the
                    update path for entry validation.

  lp_way          : way of the matching entry. Valid when
                    lp_pred_is_loop=1. Used by the update path
                    to write back to the correct way directly.

  lp_hit       : 1 when the table contains an entry matching
                 pred_pc_p0 (tag match, any confidence).
                 0 on cold miss. Valid regardless of
                 lp_pred_is_loop value.

  lp_age       : age counter value of the matching entry
                 at predict time. Captured for update.

  lp_conf      : confidence counter value at predict time.
                 Captured for update.

  lp_past_itr  : known loop iteration count at predict time.
                 Captured for update.

  lp_curr_itr  : current iteration counter at predict time.
                 Captured for update.

  lp_curs      : speculative iteration progress counter at
                 predict time. Captured for update.

  lp_curs_v    : 1 when lp_curs is valid. Captured for update.

  lp_victim    : way selected for replacement if the update
                 path needs to allocate a new entry. Computed
                 at predict time to avoid a re-read at update.

### Consumer obligations

  - Must not use pred_p0.lp_pred_taken when lp_pred_is_loop=0.
  - Must write all lp_pred_t fields into FTQ meta path
    (bp_ftq_meta_t lp_* fields) when pred_valid_p0=1,
    regardless of lp_pred_is_loop value. The update path
    requires these fields unconditionally.
  - Must set pred_src in bp_ftq_entry_t to identify loop
    predictor as provider when lp_pred_is_loop=1 and override
    control selects loop predictor output.
  - Must compare pred_p0 against s2 FTB/TAGE result and
    fire s2_redirect if they disagree, same as uBTB.

---

## Update Interface

### Producer: post-execute resolution path (BP cluster)
### Consumer: loop_pred

### Timing

  upd_p0 is a synchronous input. Sampled on rising clk edge.
  upd_valid_p0 may be asserted in any cycle.
  No ordering constraint between update channels when
  NUM_PRED_SLOTS=2. Both channels processed independently
  in the same cycle.

### Semantics

  upd_valid_p0 = 0  -- no update this cycle. All upd_p0
                       fields are ignored.
  upd_valid_p0 = 1  -- resolved update. All upd_p0 fields
                       are valid and will be processed.

### upd_p0 field semantics

  pc           : fetch block PC of the resolved prediction.
                 Source of truth for the branch identity.

  actual_taken : resolved branch direction.

  lp_pred_is_loop : value of lp_pred_is_loop captured at
                    predict time. Gates update behavior:
                      1 -- entry exists; update counters in
                           the way identified by upd_p0.lp_way.
                      0 -- no entry existed at predict time;
                           allocate a new entry at victim way.

  lp_pred_taken   : predicted direction captured at predict
                    time. Used to detect mispredicted exit.

  lp_idx, lp_tag, lp_way, lp_hit, lp_age, lp_conf,
  lp_past_itr, lp_curr_itr, lp_curs, lp_curs_v, lp_victim:
                 All captured from lp_pred_t at predict time.
                 The update path uses these directly. No
                 re-read of the table is performed.

### Update behavior

  On taken branch, lp_pred_is_loop=1 (hit, inside loop):
    - Increment lp_curr_itr (saturate at LP_ITR_BITS max).
    - If lp_curs_v: increment lp_curs (saturate).

  On not-taken exit, lp_pred_is_loop=1,
  lp_curr_itr==lp_past_itr (correct exit prediction):
    - Increment lp_conf (saturate at LP_CONF_LEVEL).
    - Copy lp_curr_itr to lp_past_itr. Reset lp_curr_itr to 0.
    - Reset lp_age to maximum.

  On not-taken exit, lp_pred_is_loop=1,
  lp_curr_itr!=lp_past_itr (wrong exit prediction):
    - Reset lp_conf to 0.
    - Copy lp_curr_itr to lp_past_itr. Reset lp_curr_itr to 0.

  On mispredicted exit (lp_pred_taken=0, actual_taken=1,
  lp_pred_is_loop=1):
    - Reset lp_conf to 0. Reset lp_curr_itr to 0.

  On miss (lp_pred_is_loop=0, upd_valid_p0=1,
           actual_taken=1, upd_p0.target < upd_p0.pc):
    - Allocate entry at lp_victim way from upd_p0.lp_victim.
    - Initialize: lp_past_itr=0, lp_curr_itr=1, lp_conf=0,
                  lp_age=max, v=1, lp_curs=0, lp_curs_v=0.
    - Write lp_tag from upd_p0.lp_tag.

### Read-during-write contract

  If upd_p0.pc and pred_pc_p0 index the same set in the
  same cycle, pred_p0 reflects the pre-update (registered)
  state. The new entry is visible on the following cycle.
  The producer must not depend on same-cycle readback.

### Producer obligations

  - Must provide resolved actual_taken, not speculative.
  - Must pass all lp_pred_t fields captured at predict time
    unmodified into lp_upd_t. No recomputation at update.
  - Must not assert upd_valid_p0 on the same pc via both
    channels in the same cycle (undefined update order).

---

## Miss Signaling Contract

The loop predictor has no miss output port. Miss is implied
by pred_p0.lp_pred_is_loop=0. The BP cluster override control
is responsible for detecting this condition and falling back
to the uBTB prediction.

The loop predictor does not stall, does not generate a
redirect, and does not communicate miss reason externally.

---

## Known Gaps and Deferred Items

| ID  | Item                                      | Status           |
|-----|-------------------------------------------|------------------|
| LI1 | Slot 1 PC derivation (pred_pc + 32)       | TBD at fetch     |
|     | exact split point ties to G8 in           | interface        |
|     | bp_cluster.md                             |                  |
| LI2 | Override control threshold -- loop pred   | TBD at           |
|     | trusted when conf==LP_CONF_LEVEL but      | bp_cluster impl  |
|     | override control policy not yet specified |                  |
| LI3 | Update channel arbitration when both      | G9 in            |
|     | channels write to same set same cycle     | bp_cluster.md    |
| LI4 | curs/curs_v speculative iteration         | Technical debt #7.|
|     | tracking -- rollback policy not           | Resolve at bp_cluster impl.|
|     | defined. Seznec uses external SLIM        |                  |
|     | structure for this purpose.               |                  |
| LI5 | Allocation policy -- allocates    | DECIDED: backward branch filter  |
|     | on backward branches only.        | required. Only upd_valid with    |
|     | Forward branches do not trigger   | actual_taken=1 and target <      |
|     | allocation.                       | pc qualify for allocation.       |
