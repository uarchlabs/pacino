<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# uBTB Interface Specification
```
 FILE:    ubtb_interfaces.md
 SOURCE:  various; session-063 rewrite
 STATUS:  DRAFT
 UPDATED: 2026-08-02
 CONTACT: Jeff Nye
```

---

## Overview

The uBTB (micro Branch Target Buffer) is a 256-entry 4-way
associative predictor. It fires at p1 and provides the first next-PC
prediction to the BP cluster. It does not generate redirect signals.
It provides or withholds a prediction only.

One uBTB lookup returns ONE entry describing ONE 32-byte block. That
entry holds two conditional branch fields and one jump field, the
same shape as an FTB entry (ftb_decisions.md 4). The cluster's two
prediction slots are br0 and br1 of that one entry.

Types are defined in bp_structs_pkg.sv. This document describes port
semantics, timing contracts, and consumer/producer obligations. It
does not restate struct field layouts.

---

## Module Parameters

  NUM_PRED_SLOTS : int  -- elaboration-time only. 1 or 2.
                          Value 3+ is undefined.

NUM_PRED_SLOTS sizes the prediction output array and the update
input array. It does NOT change the number of lookups: one lookup
per cycle in either case. At NUM_PRED_SLOTS=1 only the br0 field is
reported.

---

## Port List

  clk         : input  logic                            -- rising edge
  rstn        : input  logic                            -- active low
  pred_pc_p0  : input  logic [VA_WIDTH-1:0]             -- p0 input
  pred_p1     : output ubtb_pred_t [NUM_PRED_SLOTS-1:0] -- p1 output
  blk_p1      : output ubtb_blk_t                       -- p1 output
  upd_u0      : input  ubtb_upd_t  [NUM_PRED_SLOTS-1:0] -- post-execute

---

## Prediction Interface

### Producer: uBTB
### Consumer: BP cluster (p1 selection mux, FTQ write)

### Timing

  pred_pc_p0 is presented at p0 (combinational input).
  pred_p1 and blk_p1 are combinational from pred_pc_p0. There is
  NO REGISTER IN THE PATH: ubtb.sv derives index and tag by
  continuous assign and produces every output field in one
  always_comb reading mem, which is a flop array but is read
  combinationally. Both outputs are therefore valid WITHIN THE p0
  CYCLE, and the BP cluster registers them; the _p1 suffix names
  where the consumer sees them, not where this module produces
  them. bp_arb_spec.md 7.1 and ftq_bpu_interfaces.md 4.
  Both are held stable until the next pred_pc_p0 is presented.

  AN EARLIER REVISION said the outputs were "combinational from
  registered mem" and "valid at the start of p1, one cycle after
  pred_pc_p0". That conflates mem being state with the read being
  registered, and claims a cycle of latency the module does not
  have. ubtb.sv's own header comment carries the same error and
  is a comment-only fix for the next task that touches the file.
  Corrected session-070 against the RTL.

### Lookup

One index and one tag are derived from pred_pc_p0. One way search
over UBTB_WAYS. The matched entry supplies every slot.

  index : pred_pc_p0[UBTB_IDX_BITS+UBTB_OFFSET_BITS-1
                        : UBTB_OFFSET_BITS]
  tag   : the upper VA bits above the index

Slot 0 is built from the entry's br0 field. Slot 1 from br1. A slot
carrying the block-terminating jump reports the jump field's type
and target.

### Semantics

  blk_p1.hit = 1   -- entry valid and tag matched. blk_p1.pft_addr
                      is valid. Each pred_p1[s] is valid or not per
                      its own valid bit.
  blk_p1.hit = 0   -- uBTB miss. Every pred_p1[s].valid is 0 and all
                      other fields are driven 0. No prediction for
                      this block.

  pred_p1[s].valid = 1  -- slot s of the matched entry carries a
                           branch. All other fields in pred_p1[s]
                           are valid and must be consumed.
  pred_p1[s].valid = 0  -- slot s carries no branch. All other
                           fields are driven 0 and must be ignored.

A hit with no valid slot is a legal state: the block is known and
contains no branch the uBTB has recorded. The successor is the
fallthrough.

On miss the BP cluster proceeds with fetch at the fallthrough. The
uBTB asserts no redirect and no stall.

THE MISS FALLTHROUGH IS NOT FROM THIS MODULE. `blk_p1.pft_addr` is
driven 0 on a miss like every other field, so the cluster computes
the successor itself: lookup PC + FTB_BLOCK_BYTES, 32 bytes
(`bp_cluster.md`, Block width). The base is the lookup PC, not the
32-byte-aligned address containing it, so a miss does not resync
the stream to alignment.

### pred_p1[s] field semantics

  target   : predicted target for this slot, reconstructed to full
             width by ubtb.sv from the stored displacement. Valid
             when pred_p1[s].valid=1. Ignored by fetch when
             br_type==RETURN; RAS provides the target at p2.

  br_type  : bp_br_type_e. Valid when pred_p1[s].valid=1. The
             conditional fields always report COND. The slot
             carrying the jump field reports DIRECT_CALL,
             INDIRECT_CALL, RETURN, RETURN_CALL, INDIRECT_NONRET,
             or DIRECT_UNC per the stored is_call / is_ret /
             is_jalr bits.

             RETURN_CALL is is_call AND is_ret AND is_jalr, added
             session-069 for the JALR that pops then pushes
             (ras_decisions.md 2). The stored bits already express
             it; only the enum mapping was missing.

  br_taken : predicted direction, the conf MSB. Meaningful only when
             br_type==COND. Present in the struct for all types but
             the consumer must ignore it for non-COND.

  pos      : in-block instruction position, 0..15, of this branch.
             The cluster uses it to order br0 against br1 and to
             locate the taken branch in the fetch bundle.

  conf     : the bimodal direction counter value. MSB is the
             direction.

  carry    : 1 when THIS SLOT'S TARGET lies outside this block.
             Used by the cluster to decide whether the p1
             prediction requires a fetch block change.

             This is NOT the carry used to reconstruct
             blk_p1.pft_addr. That one is a block-scoped overflow
             bit meaning the block END crosses the
             FTB_BLOCK_BYTES boundary above the block start
             (ftb_decisions.md 5.5). One is per slot and about a
             branch target, the other is per block and about the
             fall-through. They are different facts and are not
             interchangeable. G18 / UI2.

### blk_p1 field semantics

  hit      : entry valid and tag matched.

  pft_addr : the block end, reconstructed to full width from the
             stored partial pftAddr. RULED session-070, NOT YET
             BUILT (TD#124): pftAddr becomes six bits measured
             from the 32-byte ALIGNED REGION BASE and THE CARRY
             BIT IS DELETED. As built it is a four-bit slice in a
             five-bit field plus a carry, which cannot represent
             an end more than 62 bytes above the region base;
             an unaligned block can reach 64. ftb_decisions.md
             5.5, 8.1. The text below describes the built form.
             Author-
             itative for the cluster when no slot is taken. The
             reconstruction is BOUNDS CHECKED: if the end is not
             above the looked-up block start, pft_addr is driven
             to start + FTB_BLOCK_BYTES instead. Same rule and
             same reason as ftb_decisions.md 4.5 FTB-G1 and
             FTB-G2. The uBTB index drops UBTB_OFFSET_BITS and
             blocks are unaligned, so two lookup PCs in one
             32-byte region share an entry.

### Consumer obligations

  - Must not use pred_p1[s] when blk_p1.hit=0.
  - Must not use pred_p1[s].target when pred_p1[s].valid=0.
  - Must not use pred_p1[s].br_taken when br_type != COND.
  - Must write the selected slot into the FTQ fast path
    (bp_ftq_slot_t) with pred_src set to PRED_UBTB.
  - Must compare pred_p1[s] against the p2 FTB result and derive a
    redirect if they disagree.

---

## Update Interface

### Producer: post-execute resolution path (BP cluster)
### Consumer: uBTB

### Timing

  upd_u0 is a synchronous input, sampled on the rising clk edge.
  upd_u0[u].valid may be asserted in any cycle.

Both channels are processed in the same cycle. Both may target the
same entry; they write different fields of it.

### Semantics

  upd_u0[u].valid = 0  -- channel u carries no update this cycle.
  upd_u0[u].valid = 1  -- channel u carries a resolved update. All
                          other fields are valid and are written to
                          the uBTB entry.

### upd_u0[u] field semantics

  pc         : block start PC of the entry being updated. Derives
               the set index and tag for the write.
  is_br      : this resolve is a conditional branch.
  br_idx     : which conditional field, 0 or 1.
  br_taken   : resolved direction. Drives the bimodal conf step, and
               at fill the weak conf init direction.
  target     : resolved taken target, full width. ubtb.sv converts
               to the stored displacement form.
  pos        : in-block position of the resolving branch, 0..15.
               Written at fill; static for the life of a filled
               field.
  is_jmp     : this resolve is a jump.
  jmp_target : resolved jump target, full width. Written on every
               jump resolve.
  is_call    : jump type.
  is_ret     : jump type.
  is_jalr    : jump type.
  pft_addr   : resolved block end, full width. ubtb.sv reduces it to
               the stored partial pftAddr plus carry.

### Allocation and field writes

  Tag hit, field already filled : train conf toward the resolved
                                  outcome; rewrite the target if it
                                  differs; keep pos.
  Tag hit, field free           : fill it. conf starts weak in the
                                  resolved direction
                                  (UBTB_CONF_INIT_TKN /
                                  UBTB_CONF_INIT_NTK). pos written.
  Tag miss                      : allocate. The evicted way is the
                                  round-robin write pointer.

The jump target is rewritten on every resolve of that jump, whether
or not ITTAGE or RAS supplies the runtime target.

pftAddr and carry are recomputed on any update that moves the block
boundary.

A block containing a third conditional branch ends at the second
conditional. The third branch becomes the first branch of the next
block and gets its own entry on a separate lookup. Branches are
never dropped; the block is split. The uBTB stores whatever boundary
the update path supplies in pft_addr.

### Read-during-write contract

If an update and pred_pc_p0 index the same set in the same cycle,
pred_p1 reflects the pre-update state. The new entry is visible on
the following cycle. The producer must not depend on same-cycle
readback.

### Producer obligations

  - Must provide resolved values, not speculative ones.
  - Must compute carry and pft_addr correctly before asserting
    valid.
  - Both channels may target one entry in the same cycle. They must
    not target the same FIELD of that entry.

---

## Miss Signaling Contract

The uBTB has no miss output port. Miss is blk_p1.hit=0. The BP
cluster detects the miss and continues fetch at the fallthrough it
computes itself, lookup PC + FTB_BLOCK_BYTES; see the Semantics
section above and `bp_cluster.md`.

The uBTB does not stall, does not generate a redirect, and does not
communicate miss reason or miss type externally.

---

## Known Gaps and Deferred Items

| ID  | Item                                      | Status           |
|-----|-------------------------------------------|------------------|
| UI2 | carry field consumer behavior in cluster  | TBD at           |
|     | top -- how the cluster uses the SLOT carry| bp_cluster       |
|     | to decide fetch block change vs continue. |                  |
|     | The name collision with the block-scoped  |                  |
|     | fall-through carry is resolved in the     |                  |
|     | pred_p1[s] field semantics, session-069.  |                  |
| UI3 | Both update channels targeting one entry  | Confirm at       |
|     | in the same cycle. Same-field collision   | bp_cluster       |
|     | is a producer error.                      |                  |

---

## Document History

```
  2026-09-15  session-069. The miss fallthrough is stated: the
              cluster computes lookup PC + FTB_BLOCK_BYTES, this
              module drives 0. Previously the fallthrough was
              named twice and defined nowhere.
  2026-09-15  session-069. pft_addr reconstruction is bounds
              checked, matching ftb_decisions.md 4.5 FTB-G1. The
              two meanings of "carry", per-slot target-outside-block
              and per-block fall-through overflow, are distinguished
              in the field semantics. G18 / UI2.
  2026-08-02  session-063. Single-lookup block descriptor model.
              One lookup returns one entry describing one 32-byte
              block; the two prediction slots are br0 and br1 of
              that entry. ubtb_entry_t reshaped to the FTB entry
              format. ubtb_pred_t gains pos and conf. ubtb_upd_t
              reshaped to mirror the FTB update port. ubtb_blk_t
              added for the entry-scoped hit and fallthrough.
              UI1 and UI4 closed.
```

