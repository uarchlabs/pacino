<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTQ Entry Formats
```
 FILE:    ftq_entry_formats.md
 SOURCE:  bp_structs_pkg.sv, fe_decisions.md sections 4.1 and 4.2
 STATUS:  DRAFT
 UPDATED: 2026-08-19
 CONTACT: Jeff Nye
```

The layout of the two FTQ entry structures. This file is the SOLE
prose home for them. `bp_cluster.md` and `fe_decisions.md` each
carried a copy until 2026-08-19; both now point here.

`bp_structs_pkg.sv` is the reference. Where this file and the package
disagree, the package wins and this file is wrong.

Behaviour -- lifetime, read rates, checkpoint, allocation -- is
`ftq_decisions.md`. The ports that carry these structures across the
BPU boundary are `ftq_bpu_interfaces.md`.

Both structures follow the package array-direction convention:
packed-struct dimensions descend, `[NUM_PRED_SLOTS-1:0]`; port
dimensions ascend, `[0:NUM_PRED_SLOTS-1]`.

---

## 1. Two paths

The FTQ entry is stored in two SRAMs, both indexed by the FTQ entry
index. The fast path (`bp_ftq_entry_t`, section 2) is read every
cycle. The slow path (`bp_ftq_meta_t`, section 3) is read only at
update. The two are separated so the every-cycle read does not carry
the width of the update-only metadata.

```
  fast path   bp_ftq_entry_t   224b   x 64 entries        14,336b
  slow path   bp_ftq_meta_t    421b   x 2 slots x 64      53,888b
                                                          -------
                                                          68,224b
```

The slow-path figure is the unpacked layout. Section 3.1 defines an
overload that takes it to 278b per slot and 35,584b, which is
defined and deferred.

---

## 2. Fast path: bp_ftq_entry_t
`bp_ftq_entry_t` is read every cycle. It is written at p1 and rewritten by redirect.

Block scalar fields, one per entry:

```
pc            40     fetch block start PC, VA_WIDTH
pft_addr      40     block fall-through address, VA_WIDTH
branch_id      6     FTQ entry index, FTQ_IDX_BITS
ras                  bp_ras_snapshot_t: TOSR, TOSW, BOS, 4 bits each
ghist_ptr      8     GHR circular buffer pointer snapshot
phist_ptr      5     PHR circular buffer pointer snapshot
valid          1     entry valid
```

Per-slot fields, `bp_ftq_slot_t[NUM_PRED_SLOTS-1:0]`:

```
slot_valid     1     this slot carries a predicted branch
target        40     predicted target for this slot, VA_WIDTH
br_type        3     bp_br_type_e
taken          1     predicted direction
pos            4     in-block branch position, FTB_BR_POS_BITS
pred_src       3     predictor that supplied this slot
                     not currently used, see TD-FE-4
confidence     4     saturating counter, FTQ_CONF_BITS
```

The per-slot array is declared inside `bp_ftq_entry_t`: one entry holds 
one fetch block and all its slots.

`br_type` is per slot and selects the predictor update set at
resolution (fe_decisions.md 7.2). It is written at p1 from the uBTB
view and CORRECTED at p2 by the slot correction group of
fe_decisions.md 2.5, which
carries the FTB classification. Before that group existed the field
kept the p1 value for the entry's whole life (TD-FE-6).

`pos` locates the branch inside the fetch bundle. It addresses
two-byte positions, so a 32-byte block has sixteen of them. RVA23
mandates the C extension and a branch may begin at any 2-byte
boundary, so a coarser position could not tell two RVC branches in one
aligned word apart. The cluster also uses it to form the branch PC reported to
bp_history: block base plus position times four (BP-092a).

The history pointers and RAS snapshot are block scalar
(ftq_decisions.md 3.1, fe_decisions.md 9).

`pft_addr` is block scalar as well: it is the address fetched after
this block when no slot in it is taken, one value per entry. It is
written at p1 from `bpu_pred_pft_p1` (TD#108) and is the not-taken arm
of the successor selection of fe_decisions.md 2.4. It is stored
rather than
re-derived because that selection is re-evaluated whenever a redirect
rewrites a slot, so the value is needed after p1 and cannot be
recovered from the rest of the entry.

---

## 3. Slow path: bp_ftq_meta_t

`bp_ftq_meta_t` is stored in a separate, wider SRAM, read only on post-execute update and never on the prediction path.

It holds the state each predictor needs to train and cannot recompute at resolution. The field list is maintained in `bp_structs_pkg.sv`. The struct nests one metadata block per predictor: `tage_pred_meta_t`, `sc_pred_meta_t`, `lp_pred_t`, `ittage_pred_meta_t`, and `ftb_pred_meta_t`.

The loop member is `lp_pred_t`, the same type loop_pred outputs. TD#106
retired `bp_loop_meta_t`, which carried the same thirteen fields in a
different declaration order with two spelled differently; the cluster's
field-by-field map went with it (BP-092).

The metadata is per slot, carried `[NUM_PRED_SLOTS-1:0]`. Each slot produces its own provider indices, counter snapshots, and allocation targets.

`bp_ftq_meta_t` is written at p2 for the predictors that finalize there, and at p3 for the SC, to the entry index and slot the prediction occupies.

### 3.1 Overload scheme (TD-FE-2, resolved)

DEFINED HERE, DEFERRED TO IMPLEMENTATION. The scheme below is settled
and is a STORAGE optimization only. Nothing else in the design
depends on it, so `bp_ftq_meta_t` may be built with its five members
unpacked and collapsed to the union later. Doing so preserves the
disjointness of the p2 and p3 write groups, which the union narrows
to a single arm.

The predictor metadata blocks are mutually exclusive by branch type.
TAGE, SC and the loop predictor train only on conditional branches;
ITTAGE trains only on indirect branches. No branch is both. Storing
all four unpacked therefore holds 143 bits per slot that no
resolution can ever read.

The four are overlaid in one union region with two arms. The FTB
block stays OUTSIDE the union: every branch type that forms an update
at all updates the FTB, so it is common to both arms.

```
  bp_ftq_meta_t                                       278b
    ftb          ftb_pred_meta_t         7b   [277:271]
    u            union                 271b   [270:0]

  u.cond                                271b
    tage         tage_pred_meta_t       79b   [270:192]
    sc           sc_pred_meta_t        112b   [191:80]
    lp           lp_pred_t              80b   [79:0]

  u.ind                                 271b
    rsvd                               128b   [270:143]
    ittage       ittage_pred_meta_t    143b   [142:0]
```

Per slot 278b against 421b unpacked. The slow-path array falls from
53,888b to 35,584b and the FTQ from 68,224b to 49,920b, a 27%
reduction.

DISCRIMINANT. `bp_ftq_slot_t.br_type` in the fast-path entry. It is
the FTB classification once the fe_decisions.md 2.5 slot correction
group has
written it, and the FTQ already reads the fast-path entry at
resolution for `pc` (fe_decisions.md 7.2), so the arm costs no field
and no extra access. An earlier draft of this section carried a
`wr_br_type` copy inside `bp_ftq_meta_t`; it was proposed while
`bp_ftq_slot_t.br_type` was still the stale p1 value and is redundant
now that TD-FE-6 is closed.

ARM SELECTION.

```
  COND                            ->  u.cond
  INDIRECT_NONRET, INDIRECT_CALL  ->  u.ind
  RETURN, DIRECT_CALL,
  DIRECT_UNC, NO_BRANCH           ->  no arm; u is not written
```

INDIRECT_CALL takes the indirect arm because it updates ITTAGE for
the target (FE-U9, session-061). Its RAS push reads the fast-path
snapshot, not the metadata.

WRITE RULES.

```
  W1  The p2 write always writes ftb. It writes tage and lp of
      u.cond, or ittage of u.ind, per the arm selection above.
  W2  The p3 write writes sc of u.cond and ONLY when the arm is
      u.cond. On any other arm the p3 write to the union region is
      SUPPRESSED. sc occupies [191:80] and ittage occupies [142:0],
      so an unsuppressed p3 write would corrupt ITTAGE training
      state. No placement of the two arms avoids the overlap:
      ittage is wider than lp and than tage.
  W3  Within u.cond the p2 fields (tage, lp) and the p3 field (sc)
      are disjoint bit ranges, so those two writes still require no
      merge. The disjointness that held across the whole struct
      before the union holds only within an arm after it.
  W4  The cluster continues to present all five metadata blocks on
      the flat ports of ftq_bpu_interfaces.md 7.1 and 7.2. The
      overlay is performed by the FTQ as it writes the SRAM. The
      cluster does not carry the union type.
```

READ RULES.

```
  R1  At resolution the FTQ reads br_type from the fast-path entry
      and decodes the union arm from it.
  R2  When that br_type disagrees with the resolved branch type in
      bp_update_t, the metadata describes a different predictor set
      than the branch that executed. Form the uBTB and FTB updates
      only: both derive from the resolved facts and from ftb, which
      lies outside the union. Suppress the TAGE, SC, LP and ITTAGE
      updates -- their payload types embed metadata that was never
      captured for this branch type. The FTB update corrects the
      stored classification, so the next occurrence selects the
      right arm.
```

R2 is reachable whenever an FTB entry is stale or aliased.

---

## 4. Per-entry fetch status

The two fields deferred by `ftq_ifu_interfaces.md` 8 item 3. They
were held back because the policy that reads them was FE-U7, which
`ftq_decisions.md` 5 resolved.

```
  wb_rcvd   1   the IFU has written this entry's block back
  fault     1   fetch of this block terminated on a fault
  gen       1   generation tag, toggled on allocation (4.4)
```

The third field named in that item, request-issued, IS NOT ADDED.
`fetch_ptr` already says which entries have been issued: every entry
behind it has, every entry at or ahead of it has not
(`ftq_decisions.md` 5.1). A per-entry bit would be a second encoding
of one pointer, free to disagree with it.

### 4.1 Not in either SRAM

THESE ARE FLOPS, three vectors FTQ_DEPTH deep, 192 bits total. They
are NOT members of `bp_ftq_entry_t` and not members of
`bp_ftq_meta_t`. Three reasons, and the third is decisive:

- The writeback arrives at an arbitrary time relative to the fetch
  read. Setting a bit inside the fast-path entry would be a
  read-modify-write of an SRAM that is already read every cycle.
- The commit walk and the next-PC hold test these ACROSS entries. A
  flop vector is readable whole; an SRAM is readable one index at a
  time.
- A redirect rewind squashes every entry after an index
  (`ftq_decisions.md` 5.5) and must clear their status in ONE
  cycle. In flops that is a masked clear. In SRAM it is a walk,
  and the walk would have to finish before those indices could be
  reallocated.

The entry totals of section 1 are therefore unchanged. Fast path
224b, slow path 421b per slot, 68,224b together; these 192 bits sit
outside both.

### 4.2 Write and clear

```
  W1  wb_rcvd and fault CLEAR when the entry is allocated at p1,
      and gen TOGGLES. Allocation is the only producer of a fresh
      entry, so this is the one place a stale bit could otherwise
      survive a wrap.
  W2  wb_rcvd SETS on ifu_ftq_pdwb_val naming this index AND
      carrying a matching gen. A writeback failing the gen test is
      dropped entirely (4.4).
  W3  fault SETS on ifu_ftq_fault_val naming this index. The
      writeback carries both, so W2 and W3 can fire together.
  W4  A redirect rewind clears both for every entry it squashes,
      in the same cycle it moves the pointer (5.5).
```

`ifu_ftq_fault_pos` is NOT stored. The fault code is not carried at
all -- the architectural exception travels with the instruction
stream to the backend, which is where it is taken
(`ftq_ifu_interfaces.md` 6). The FTQ needs only to know that the
block ended early.

### 4.3 Readers

```
  R1  fault holds the next-PC request. The FTQ stops requesting
      past a faulting block rather than predicting into a stream
      that will not be fetched (4.5 hold conditions).
  R2  fault does NOT hold commit. The entry frees normally; the
      trap is taken in the backend, which redirects the FTQ
      through the ordinary RC_TRAP path.
  R3  wb_rcvd qualifies the predecode redirect. An entry derives
      at most one, and only from its own writeback
      (ftq_ifu_interfaces.md 6). A second writeback naming an
      entry that already has the bit set is a protocol violation,
      not a second redirect.
```

R3 is the reason wb_rcvd exists at all. Deallocation does not need
it: 5.3 frees on commit only, and `ftq_ifu_interfaces.md` 7 already
states the FTQ does not need the writeback to free an entry.

### 4.4 The in-flight writeback -- TD-FE-8, CLOSED

W1 clears both bits at allocation, which handles a stale bit
surviving a wrap. It does NOT handle a writeback IN FLIGHT when the
entry is squashed and its index reallocated: that writeback arrives
after the new allocation cleared the bits, and sets them on the
WRONG use of the index.

`ftq_decisions.md` 5.6 solves the same problem for CLUSTER responses
with a four-deep in-flight shadow. That mechanism does not transfer:
it works because the cluster's stage registers advance
unconditionally, so the shadow shifts in lockstep. IFU latency is
neither fixed nor bounded -- an ICache miss makes it arbitrary --
so there is no stage count to shadow.

`ftq_ifu_interfaces.md` 5 says the IFU discards whatever it holds
for flushed entries, which covers everything except a writeback
already presented in the flush cycle. Whether that race is real
depends on the IFU's flush timing, which is not specified.

CLOSED by `ftq_ifu_interfaces.md` 6.1: one generation bit,
`ftq_ifu_gen` out with the request and `ifu_ftq_pdwb_gen` back on
the writeback, TOGGLED each time the entry is allocated. A
writeback whose tag does not match is dropped entirely.

The bit is held here, beside wb_rcvd and fault:

```
  gen       1   generation, toggled on allocation
```

so section 4 is three flop vectors, 192 bits, not two. Allocation
writes it and the IFU path reads it; nothing else does.

A TOGGLE rather than the pointer's wrap bit, because a rewind can
reallocate an index within one wrap and a wrap-derived value would
not discriminate there. One bit is sufficient because the flush of
`ftq_ifu_interfaces.md` 5 bounds the stale writebacks in flight to
one per flush; the reasoning, and what would invalidate it, is in
6.1.

The 5.6 rejection of carried wrap bits does not apply: it was
rejected because it would have widened FTQ_IDX_BITS at every
bp_cluster port and in three predictor metadata structs. The IFU
path touches none of those.

---

## 5. Document History

```
  2026-08-19  Created. Sections 4.1, 4.2 and 4.2.1 moved here whole
              from fe_decisions.md, and the duplicate layout deleted
              from bp_cluster.md. No content changed in the move.
              Section 1 added: the two-path summary and the storage
              totals. Numbering: fe_decisions 4.1 -> section 2,
              4.2 -> section 3, 4.2.1 -> section 3.1.

  2026-08-20  Section 4 added: the per-entry fetch status fields
              wb_rcvd and fault, closing the remainder of TD-FE-1.
              request-issued deliberately NOT added -- fetch_ptr
              already carries it. Both are FLOPS outside either
              SRAM; 4.1 gives the three reasons. TD-FE-8 opened in
              4.4 for the in-flight writeback race, which 5.6's
              shadow cannot cover because IFU latency is unbounded.
              Section 4 Document History renumbered to 5; nothing
              referenced it. TD-FE-8 CLOSED the same day: a third
              flop vector, gen, toggled on allocation and carried
              on the IFU path. Section 4 is 192 bits, not 128.

  2026-08-19  FTB_BR_POS_BITS 3 -> 4. bp_ftq_slot_t.pos widens, so
              the slot is 56b and the entry 224b; ftb_pred_meta_t
              gains a bit in jmp_pos, so bp_ftq_meta_t is 421b.
              Fast path 14,336b, slow path 53,888b, FTQ 68,224b.
              Section 3.1's overload figures restated: 278b per
              slot, 35,584b, FTQ 49,920b.
```
