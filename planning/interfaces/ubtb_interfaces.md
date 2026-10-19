<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# uBTB Interface Specification
```
 FILE:    ubtb_interfaces.md
 SOURCE:  various; session-063 rewrite
 STATUS:  DRAFT
 UPDATED: 2026-10-12
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
  have. ubtb.sv's header comment carried the same error; its
  timing paragraph was right before BP-134, and BP-134 corrected
  its opening lines.
  Corrected session-070 against the RTL.

### Lookup

One index and one tag are derived from pred_pc_p0. One way search
over UBTB_WAYS. The matched entry supplies every slot.

  index : pred_pc_p0[10:5] XOR (pred_pc_p0[4:1] << UBTB_SOFF_SHIFT)
  tag   : {pred_pc_p0[30:11], pred_pc_p0[4:1]}, UBTB_TAG_BITS = 24
ONE ENTRY PER START PC (BP-140, ruled by Jeff 2026-10-18; PROVISIONAL
index fold), within the partial tag: aliasing above pc[30] is
allowed, as before.

Slot 0 is built from the entry's br0 field. Slot 1 from br1. A slot
carrying the block-terminating jump reports the jump field's type
and target.

Since BP-140 the entry is one start's block, stored start-relative
and in ascending position (br0 below br1, the jump after both), so
there is no read window and nothing to compact or reorder; slot 0 is
br0 and the first branch. The divergences of session-073 (mask
without compaction, br_idx naming a storage field, a hidden field
refilled) are gone with the region entry. The bp_cluster p1 swap
(FE-10, BP-121 D12) stays and no longer fires for a uBTB entry.
REMAINING DIVERGENCES FROM THE FTB: targets are displacements from
the block start, not from the branch and jump PCs; the jump field
has no rvc bit (a jump's end comes from the update's pft_addr); the
fall-through is not bounds checked at the read (blk_p1 below); the
tag is partial; replacement is round-robin.

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
             counted from the BLOCK START, stored in the same form
             (UBTB_BR_POS_BITS; region-relative and windowed from
             session-071 to BP-140).
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
             stored partial pftAddr: five bits measured from the
             BLOCK START (BP-140; six from the aligned region base
             before it), no carry bit. ftb_decisions.md 5.5, 8.1.
             Authoritative for the cluster when no slot is taken.

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
  br_idx     : NOT READ since BP-140. A conditional's field is named
               by its position (Allocation and field writes); the
               member stays in ubtb_upd_t (ports unchanged).
               RESERVED (Jeff, session-081).
  br_taken   : resolved direction. Drives the bimodal conf step, and
               at fill the weak conf init direction.
  target     : resolved taken target, full width. ubtb.sv converts
               to the stored displacement form.
  pos        : in-block position of the resolving branch, 0..15,
               START-relative, stored as given (BP-140). Names the
               field: the same position is the same branch.
  is_jmp     : this resolve is a jump.
  jmp_target : resolved jump target, full width. Written on every
               jump resolve.
  is_call    : jump type.
  is_ret     : jump type.
  is_jalr    : jump type.
  pft_addr   : resolved block end, full width. Written only for a
               jump (the FTQ's resolved end of the taken jump,
               TD#164), reduced to five bits from the block start;
               for a conditional it is the block's predicted end and
               is not written (BP-140, PROVISIONAL, as the FTB).

### Allocation and field writes

The uBTB applies the FTB's update rule (ftb_decisions.md 3 and 5.5
as restated by BP-140; ubtb.sv apply_upd):
  same position, same kind      : a conditional trains conf toward
                                  the outcome and rewrites its target;
                                  a jump rewrites the jump field.
  same position, other kind     : replaces that field.
  at or after the end, or after
  the stored jump               : no change (a stale resolution).
  new branch                    : joins the held ones in position
                                  order, weak conf; a new jump removes
                                  the conditionals after it.
  more than N_SLOTS branches    : THE SPLIT. The lowest N_SLOTS kept;
                                  the end is the PC of the first not
                                  kept; a jump not kept is cleared.
  Tag miss                      : allocate, end start + 32. The
                                  evicted way is the round-robin
                                  write pointer.
A branch cannot fill both conditional fields (BP-131 measured 82 at
two slots before BP-140; the position now names the field). Two
channels landing on one entry in one cycle are applied in order and
give the same entry in either order (tb_ubtb TC21). The jump target
is rewritten on every resolve of that jump.

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
  2026-10-19  session-081, after BP-140. Per-start entries and the
              split at update, the rule the FTB uses; the region
              window, the masking and the field named by br_idx are
              gone. One branch can no longer fill both conditional
              fields. br_idx is no longer read and is kept reserved
              (Jeff).

  2026-10-12  session-079, after BP-134. Timing: the ubtb.sv header
              comment corrected.

  2026-10-12  session-078, after BP-131. Allocation and field writes:
              one branch can fill both conditional fields, measured
              82 times at two slots; the block split is not built.
              Both deferred to TD#179.

  2026-10-08  session-076, PA-direct correction recording BP-121.
              Lookup: the p1 slot-order inversion was not harmless;
              bp_cluster swaps the p1 slots (D12).

  2026-10-08  session-075, after BP-120. The position rule built;
              only the field br_idx names is compared.

  2026-10-07  session-075, after BP-119. Allocation and field
              writes: a filled field keeps pos only for the same
              position; otherwise the jump field is rewritten or
              the conditional filled as new (ruled, Jeff), TD#156.
              pft_addr text brought to the BP-110 build (no carry).
              The cluster now meets the obligation not to use
              br_taken when br_type is not COND (BP-119).

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

