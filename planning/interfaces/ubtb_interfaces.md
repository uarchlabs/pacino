<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# uBTB Interface Specification
```
 FILE:    ubtb_interfaces.md
 SOURCE:  various; session-063 rewrite
 STATUS:  DRAFT
 UPDATED: 2026-09-22
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

THE uBTB DIVERGES FROM THE FTB AND THE DIVERGENCE IS RULED
(session-073, Jeff; ftb_decisions.md 4.6). Under the read window the
uBTB MASKS ONLY: a field whose stored position lies outside this
block's window reports invalid, and the surviving fields are NOT
compacted onto the slots and NOT reordered in storage. Slot 0 stays
br0. The FTB does compact (4.6 O-3b); the uBTB does not.

Three consequences, all accepted:
  - with br0 hidden and br1 visible, slot 0 is EMPTY and slot 1
    carries the block's first branch.
  - a visible jump takes slot 0 ahead of br1, so the p1 slot order
    can invert. The FTB corrects the order at p2, and FE-3 already
    has a later stage supersede the whole p1 prediction.
  - br_idx on the update port names the STORAGE field, not a port
    slot as ftb_upd_br_idx_u0 does. A field hidden from the update's
    start is refilled with that start's branch rather than kept.

The uBTB is a p1 guess that p2 replaces, so slot-order inversion
costs accuracy for one cycle and nothing else. Compaction would have
bought consistency with the FTB at the price of a second set of
window rules in a module whose output is always superseded.

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

  pos      : in-block instruction position, 0..15, of this branch,
             counted from the BLOCK START. The entry stores it
             region-relative, UBTB_BR_POS_BITS + 1 wide, and ubtb.sv
             converts at the read, reporting a slot whose stored
             position lies outside this block's window as invalid
             (ftb_decisions.md 4.6, session-071, TD#125).
             The cluster uses it to locate the branch in the fetch
             bundle. NOT to order br0 against br1: br0 is always
             the earlier branch by fill order
             (ftb_decisions.md 4, IC-FTB-16). This read "to order
             br0 against br1". Session-070. It is used to
             locate the taken branch in the fetch bundle.

  conf     : the bimodal direction counter value. MSB is the
             direction.

  carry    : DELETED by BP-110 (session-073). It was the ENTRY
             fall-through carry, the block-scoped overflow bit of
             the stored pftAddr, and it had no consumer anywhere in
             rtl/. Nothing replaces it: at six bits pftAddr reaches
             past the block boundary on its own, so a consumer
             derives the crossing from blk_p1.pft_addr itself.
             G18 and UI2 close as "field removed".

             It read at one point as "1 when THIS SLOT'S TARGET
             lies outside this block" and "NOT the carry used to
             reconstruct blk_p1.pft_addr" (session-069), which
             session-070's package-comment correction reversed.
             Session-071.

### blk_p1 field semantics

  hit      : entry valid and tag matched.

  pft_addr : the block end, reconstructed to full width from the
             stored partial pftAddr. BUILT by BP-110: six bits
             measured from the 32-byte ALIGNED REGION BASE, NO
             CARRY BIT. Before that it was a four-bit slice in a
             five-bit field plus a carry, which could not represent
             an end more than 62 bytes above the region base while
             an unaligned block reaches 64. ftb_decisions.md 5.5,
             8.1. Authoritative for the cluster when no slot is
             taken.

             IT IS NOT BOUNDS CHECKED. Ruled session-073 (Jeff).
             This entry previously required the FTB-G1 rule of
             ftb_decisions.md 4.5, and the RTL has never had it.
             The uBTB index drops UBTB_OFFSET_BITS and blocks are
             unaligned, so two lookup PCs in one 32-byte region do
             share an entry and an aliased end can be reported.
             That is accepted for the same reason as the slot
             divergence above: the p1 prediction is superseded at
             p2, where the FTB result IS bounds checked (FTB-G1 and
             FTB-G3).

### Consumer obligations

  - Must not use pred_p1[s] when blk_p1.hit=0.
  - Must not use pred_p1[s].target when pred_p1[s].valid=0.
  - Must not use pred_p1[s].br_taken when br_type != COND.
  - Must write the selected slot into the FTQ fast path
    (bp_ftq_slot_t) with pred_src set to PRED_UBTB.

The uBTB takes no part in the redirect comparison. The cluster
compares the successor it would publish at p2 against its own p1
stage registers (fe_decisions.md FE-4); no predictor is compared
against another, and the uBTB is not a redirect source. This list
carried "Must compare pred_p1[s] against the p2 FTB result and derive
a redirect if they disagree". Session-071.

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
  br_idx     : which conditional STORAGE field, 0 or 1. Unlike
               ftb_upd_br_idx_u0, which names a port slot
               (ftb_interfaces.md 2.5), this names the field
               directly, because the uBTB does not compact. A field
               hidden from this update's start is REFILLED with
               this start's branch and a fresh conf. Ruled
               session-073.
  br_taken   : resolved direction. Drives the bimodal conf step, and
               at fill the weak conf init direction.
  target     : resolved taken target, full width. ubtb.sv converts
               to the stored displacement form.
  pos        : in-block position of the resolving branch, 0..15,
               START-relative. ubtb.sv adds the update PC's region
               offset before storing it (ftb_decisions.md 4.6 R-2).
               Written at fill; static for the life of a filled
               field.
  is_jmp     : this resolve is a jump.
  jmp_target : resolved jump target, full width. Written on every
               jump resolve.
  is_call    : jump type.
  is_ret     : jump type.
  is_jalr    : jump type.
  pft_addr   : resolved block end, full width. ubtb.sv reduces it to
               the stored partial pftAddr plus carry. THAT IS THE
               BUILT FORM. Ruled session-070, not built (TD#124):
               six bits from the aligned region base, no carry
               (blk_p1 field semantics above, ftb_decisions.md 5.5).

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
boundary. Built form; after TD#124 there is no carry and only
pftAddr is recomputed. This paragraph and the pft_addr field above
carried the built form unannotated. Session-072.

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
  - Must compute pft_addr correctly before asserting valid (and,
    in the built form, carry; TD#124 deletes it).
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
| UI2 | CLOSED session-073, BP-110. The carry     | Field removed.   |
|     | field is deleted; it never had a          |                  |
|     | consumer. G18 closes with it.             |                  |
| UI3 | Both update channels targeting one entry  | Confirm at       |
|     | in the same cycle. Same-field collision   | bp_cluster       |
|     | is a producer error.                      |                  |

---

## Document History

```
  2026-09-22  session-073, after BP-110. The uBTB divergence from
              the FTB is ruled and stated at the head of the
              prediction section: mask only, no compaction, no
              reorder, br_idx names a storage field, and a hidden
              field is refilled. pft_addr is six bits with no carry
              and is ruled NOT bounds checked. carry deleted; G18
              and UI2 closed.

  2026-09-20  session-072. The Update Interface pft_addr field, the
              pftAddr/carry recompute and the producer obligation
              annotated as the built form against the TD#124
              ruling.
  2026-09-19  session-071. pos is start-relative at both ports and
              stored region-relative, one bit wider, with a read
              window, as the FTB (ftb_decisions.md 4.6, TD#125). The
              consumer obligation to compare pred_p1 against the p2
              FTB result is removed: FE-4. carry is the entry
              fall-through carry, as G18 and the package say, not
              a slot-target bit; TD#124 removes its source. "Fetch
              block" replaced by
              "prediction block" where the 32-byte unit was meant.
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

