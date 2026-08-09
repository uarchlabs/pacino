<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Loop Predictor Interface Specification

```
 FILE:    loop_pred_interfaces.md
 SOURCE:  various
 STATUS:  LOCKED
 UPDATED: 2026-08-08
 CONTACT: Jeff Nye
```

---

## Overview

The Loop Predictor is a 256-entry 4-way associative predictor per
prediction slot. It fires at p1 alongside uBTB and provides a
direction prediction for branches detected as constant-iteration
loops. It overrides uBTB at p1 when lp_pred_is_loop=1, which
requires confidence at maximum (cnf == LP_CONF_LEVEL). It does not
participate in the p2/p3 override chain.

Override control (not this module) makes the final p1 mux
decision. The loop predictor exposes lp_pred_is_loop and the
prediction; it does not directly suppress the uBTB output.

Stage naming is p0/p1/p2/p3, matching the port suffixes and
ftq_bpu_interfaces.md. Earlier revisions of this document used
s0/s1/s2/s3 for the same stages.

Types are defined in bp_structs_pkg.sv and the sizing parameters in
bp_defines_pkg.sv. This document describes port semantics, timing
contracts, and consumer/producer obligations. It does not restate
struct field layouts -- see bp_structs_pkg.sv.

---

## Module Parameters

  LP_TBL_ENTRIES : int -- default 256, per slot
  LP_TBL_WAYS    : int -- default 4
  LP_TAG_BITS    : int -- default 14
  LP_ITR_BITS    : int -- default 14
  LP_CNF_BITS    : int -- default 2
  LP_AGE_BITS    : int -- default 8
  LP_N_SETS      : int -- LP_TBL_ENTRIES / LP_TBL_WAYS
  LP_IDX_BITS    : int -- $clog2(LP_N_SETS)
  LP_CONF_LEVEL  : int -- (1 << LP_CNF_BITS) - 1
  NUM_PRED_SLOTS : int -- elaboration-time only. 1 or 2.
                         Value 3+ is undefined.

NUM_PRED_SLOTS defaults to 1 in the module and is overridden at
instantiation from bp_defines_pkg::NUM_PRED_SLOTS, the same way it
is for ubtb. The module elaborates at either value.

Every prediction and update port carries NUM_PRED_SLOTS elements and
the table is replicated as one bank per slot (TI6). Slot banks are
independent: a write to one bank cannot change another.

### Slot PC derivation

All slots index from the single p0 request PC presented on their own
pred_pc_p0 element. There is no per-slot PC at p0.

The index and tag hashes take no slot discriminator: two slots given
the same PC address the same set and the same tag in their own bank.
The banks diverge only because they are written by different slots'
updates.

An earlier revision of this document stated that slot 1 predicts the
fetch block following slot 0 at pred_pc + 32. That is superseded.
Session-063 retired the two-PC-range block model, G8 and G17 are
superseded, and BP-086 removed the pred_pc_p0 + 32 slot 1 lookup
from ubtb.sv.

---

## Port List

```
  clk           : input  logic                       -- rising edge
  rstn          : input  logic                       -- active low
  pred_pc_p0    : input  logic [VA_WIDTH-1:0]
                                [0:NUM_PRED_SLOTS-1] -- p0 input
  pred_valid_p0 : input  logic [NUM_PRED_SLOTS-1:0]  -- p0 input
  pred_p1       : output lp_pred_t
                                [0:NUM_PRED_SLOTS-1] -- p1 output
  upd_p0        : input  lp_upd_t
                                [0:NUM_PRED_SLOTS-1] -- post-execute
  upd_valid_p0  : input  logic [NUM_PRED_SLOTS-1:0]  -- post-execute
```

Slot dimension style follows the tage, ittage, sc and ras ports of
this unit: a packed vector for the per-slot valid bits and an
unpacked ascending array for the per-slot payload and address.

The prediction output was named pred_p0 before the TD#105 retrofit
while its value was already valid at p1. It is now named for the
stage at which it is valid. No other port stage suffix changed; the
update ports keep the p0 suffix, not u0 (ftq_bpu_interfaces.md
section 8).

---

## Reset State

Reset is asynchronous, active low, and clears every bank.

  - Every entry of every bank: v=0, tag=0, past_itr=0, curr_itr=0,
    age=0, cnf=0, curs=0, curs_v=0.
  - pred_p1 reads all-zero on every slot.

Consequences a consumer may rely on after reset, before any update:
every lookup reports lp_hit=0 and lp_pred_is_loop=0, and victim
selection reports way 0, because every way is invalid and priority 1
of victim selection is the lowest-indexed invalid way.

---

## Prediction Interface

### Producer: loop_pred
### Consumer: BP cluster (override control, p1 mux, FTQ write)

### Timing

  pred_pc_p0[s] is presented at p0 (combinational input).
  pred_p1[s] is registered at the end of p0, valid at the start of
  p1.
  pred_p1[s] is held stable until the next pred_pc_p0[s] is
  presented.
  pred_valid_p0[s] gates the lookup for slot s only. When
  pred_valid_p0[s]=0, pred_p1[s].lp_pred_is_loop=0 and
  pred_p1[s].lp_pred_taken=0. The remaining pred_p1[s] fields still
  report the addressed entry.

  Slots are independent in the same cycle: any subset of
  pred_valid_p0 may be asserted, each slot with its own PC.

### Semantics

  pred_p1[s].lp_pred_is_loop = 1 -- loop predictor hit in bank s
                               with confidence at maximum. All
                               lp_pred_t fields are valid and must
                               be consumed by the cluster override
                               control.
  pred_p1[s].lp_pred_is_loop = 0 -- miss, or hit with confidence
                               below LP_CONF_LEVEL, or that slot's
                               pred_valid_p0 bit low. Override
                               control must ignore lp_pred_taken
                               and defer to uBTB.

  On lp_pred_is_loop=0: the BP cluster uses the uBTB prediction
  for that slot at p1. The loop predictor does not assert any
  redirect or stall signal.

### pred_p1 field semantics

  lp_pred_is_loop : 1 when the loop predictor is trusted and
                    override control should select this output
                    over uBTB. 0 otherwise.

  lp_pred_taken   : predicted direction. Valid only when
                    lp_pred_is_loop=1. 1 = predict taken (still
                    inside loop body, curr_itr < past_itr).
                    0 = predict not-taken (loop exit).

  lp_idx          : set index derived from pred_pc_p0[s]. Used
                    by the update path to address the correct
                    set without re-deriving from PC.

  lp_tag          : tag derived from pred_pc_p0[s]. Used by the
                    update path for entry validation.

  lp_way          : way of the matching entry. Valid when
                    lp_hit=1. Used by the update path to write
                    back to the correct way directly.

  lp_hit       : 1 when bank s contains an entry matching
                 pred_pc_p0[s] (tag match, any confidence).
                 0 on cold miss. Valid regardless of
                 lp_pred_is_loop value, and not gated by
                 pred_valid_p0.

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

On a miss the entry-derived fields (lp_age, lp_conf, lp_past_itr,
lp_curr_itr, lp_curs, lp_curs_v) report way 0 of the addressed set,
which is the default the hit scan starts from.

### Victim selection

Evaluated on every lookup, in priority order:

  1. lowest-indexed invalid way
  2. lowest-indexed valid way with age == 0
  3. the lowest-numbered way among 1, 2, 3 whose age is less than
     way 0's age; way 0 if none qualifies

### Consumer obligations

  - Must not use pred_p1[s].lp_pred_taken when lp_pred_is_loop=0.
  - Must write all lp_pred_t fields into the FTQ meta path
    (bp_ftq_meta_t lp_* fields) per slot when pred_valid_p0[s]=1,
    regardless of lp_pred_is_loop value. The update path requires
    these fields unconditionally.
  - Must set pred_src in bp_ftq_slot_t to identify the loop
    predictor as provider when lp_pred_is_loop=1 and override
    control selects the loop predictor output.
  - Must compare pred_p1 against the p2 FTB/TAGE result and
    fire the p2 redirect if they disagree, same as uBTB.

---

## Update Interface

### Producer: post-execute resolution path (BP cluster)
### Consumer: loop_pred

### Timing

  upd_p0[s] is a synchronous input. Sampled on rising clk edge.
  upd_valid_p0[s] may be asserted in any cycle.
  No ordering constraint between update channels. Every channel is
  processed independently in the same cycle, into its own bank.
  upd_p0[s] is ignored entirely when upd_valid_p0[s]=0, including
  when another slot's valid is asserted in that cycle.

### Semantics

  upd_valid_p0[s] = 0  -- no update to bank s this cycle. All
                          upd_p0[s] fields are ignored.
  upd_valid_p0[s] = 1  -- resolved update. All upd_p0[s] fields
                          are valid and will be processed.

### upd_p0 field semantics

  pc           : fetch PC of the resolved branch. With target, it
                 forms the backward-branch filter on the
                 allocation path. It does NOT address the table:
                 lp_idx and lp_way do.

  target       : resolved target address. Allocation requires
                 target < pc.

  actual_taken : resolved branch direction.

  lp_hit          : value of lp_hit captured at predict time.

  lp_pred_is_loop : value of lp_pred_is_loop captured at predict
                    time.

  lp_pred_taken   : predicted direction captured at predict
                    time. Used to detect mispredicted exit.

  lp_idx, lp_tag, lp_way, lp_age, lp_conf, lp_past_itr,
  lp_curr_itr, lp_curs, lp_curs_v, lp_victim:
                 All captured from lp_pred_t at predict time.
                 The update path uses these directly. No
                 re-read of the table is performed.

### Write path selection

The write path is chosen by lp_pred_is_loop and lp_hit together,
not by lp_pred_is_loop alone:

  lp_pred_is_loop=1 OR lp_hit=1
      -- update in place at mem[lp_idx][lp_way]
  both 0, AND actual_taken=1, AND target < pc
      -- allocate at mem[lp_idx][lp_victim]
  otherwise
      -- no write

### Update behavior

The in-place cases are evaluated in this order. The first match
wins; the ordering matters because the mispredicted-exit case is a
subset of the taken-branch case.

  1. Mispredicted exit -- lp_pred_is_loop=1, lp_pred_taken=0,
     actual_taken=1:
       - Reset cnf to 0. Reset curr_itr to 0.

  2. Taken branch hit -- lp_pred_is_loop=1, actual_taken=1:
       - Increment curr_itr, saturating at the LP_ITR_BITS max.
       - If curs_v: increment curs, saturating.

  3. Learning hit -- lp_hit=1, lp_pred_is_loop=0, actual_taken=1:
       - Increment curr_itr, saturating. No confidence change.

  4. Correct not-taken exit -- none of the above matched and
     curr_itr == past_itr:
       - Increment cnf, saturating at LP_CONF_LEVEL.
       - Copy curr_itr to past_itr. Reset curr_itr to 0.
       - Reset age to maximum.

  5. Wrong not-taken exit -- none of the above matched and
     curr_itr != past_itr:
       - Reset cnf to 0.
       - Copy curr_itr to past_itr. Reset curr_itr to 0.

  Cases 4 and 5 are the fall-through of the chain. They do not test
  lp_pred_is_loop: an entry reached through lp_hit alone takes them
  as well.

  Every field not named by the matched case is written back from
  the captured upd_p0[s] value unchanged, and v is set to 1 and tag
  to upd_p0[s].lp_tag.

  On allocation (miss, actual_taken=1, target < pc):
    - Allocate at way upd_p0[s].lp_victim of set upd_p0[s].lp_idx.
    - Initialize: past_itr=0, curr_itr=1, cnf=0, age=max, v=1,
      curs=0, curs_v=0.
    - Write tag from upd_p0[s].lp_tag.
    curr_itr=1 because the first iteration has already been
    observed.

### Read-during-write contract

  If an update and a lookup address the same set of the same bank
  in the same cycle, pred_p1 reflects the pre-update (registered)
  state. The new entry is visible on the following cycle.
  The producer must not depend on same-cycle readback.

### Producer obligations

  - Must provide resolved actual_taken, not speculative.
  - Must pass all lp_pred_t fields captured at predict time
    unmodified into lp_upd_t. No recomputation at update.
  - Must not present two updates for the same branch on two
    channels in the same cycle. Two channels resolving the same PC
    address the same set and way of two different banks and would
    diverge that PC's state between the banks.

---

## Miss Signaling Contract

The loop predictor has no miss output port. Miss is implied
by pred_p1[s].lp_pred_is_loop=0. The BP cluster override control
is responsible for detecting this condition and falling back
to the uBTB prediction for that slot.

The loop predictor does not stall, does not generate a
redirect, and does not communicate miss reason externally.

---

## Known Gaps and Deferred Items

| ID  | Item                                      | Status           |
|-----|-------------------------------------------|------------------|
| LI1 | Slot 1 PC derivation (pred_pc + 32)       | CLOSED. Model    |
|     |                                           | retired in       |
|     |                                           | session-063. All |
|     |                                           | slots index from |
|     |                                           | the p0 request   |
|     |                                           | PC. G8 and G17   |
|     |                                           | superseded.      |
| LI2 | Override control threshold -- loop pred   | CLOSED at        |
|     | trusted when cnf==LP_CONF_LEVEL           | bp_cluster: the  |
|     |                                           | p1 mux takes the |
|     |                                           | loop direction   |
|     |                                           | per slot when    |
|     |                                           | lp_pred_is_loop. |
| LI3 | Update channel arbitration when two       | CLOSED by TI6.   |
|     | channels write the same set in the same   | Banks are per    |
|     | cycle                                     | slot; there is   |
|     |                                           | no shared write  |
|     |                                           | port to arbitrate|
| LI4 | curs/curs_v speculative iteration         | Technical debt #7.|
|     | tracking -- rollback policy not           | Resolve at bp_cluster impl.|
|     | defined. Seznec uses external SLIM        |                  |
|     | structure for this purpose.               |                  |
| LI5 | Allocation policy -- allocates    | DECIDED: backward branch filter  |
|     | on backward branches only.        | required. Only upd_valid with    |
|     | Forward branches do not trigger   | actual_taken=1 and target <      |
|     | allocation.                       | pc qualify for allocation.       |
| LI6 | lp_pred_t and bp_loop_meta_t carry the    | CLOSED by TD#106,|
|     | same thirteen fields in a different order | BP-092. lp_pred_t|
|     | with two spelled differently. Retiring    | survives;        |
|     | one of the two is an open decision.       | bp_loop_meta_t   |
|     |                                           | deleted, and the |
|     |                                           | bp_ftq_meta_t lp |
|     |                                           | member is now    |
|     |                                           | lp_pred_t.       |
