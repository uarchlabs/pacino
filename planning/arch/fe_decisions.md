```
 FILE:    fe_decisions.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-08-01
 CONTACT: Jeff Nye
```

# Front End Theory of Operation: BPU and FTQ

This document describes the two paths that connect the branch
prediction cluster and the fetch target queue.

BPU to FTQ carries predictions. The FTQ allocates an entry on the
initial prediction and issues a fetch from it. Later predictors correct
that entry by redirect.

A redirect is the correction of an FTQ entry by a predictor at p2 or p3. A later predictor can override the initial p1 prediction held in the entry, replacing the corrected slot's target and redirecting fetch to the new address. Redirects supersede by stage order and carry a corrected target per slot; the mechanism is specified in section 3.

FTQ to BPU carries updates. On post-execute resolution the FTQ reads
the metadata captured at prediction time and forms an update for each
predictor named by the resolved branch type. Updates reach the
predictors through per-predictor update queues.

Predictor internals are out of scope, as is the RAM arbitration model.
This document states what each predictor contributes to the FTQ, when,
and the handshakes that carry it.

Stage labeling is p0 through p3 for prediction and u0/u1 for update.

One FTQ entry holds one fetch block. A fetch block carries
NUM_PRED_SLOTS predictions, one per prediction slot. The slots are the
branch fields of one FTB block; see section 10.

---

## 1. Stages

```
  p0   Indices and addresses presented to the RAMs. PC hash and
       folded history available.
  p1   RAM outputs available. The initial prediction is formed. The
       FTQ allocates an entry and issues a fetch.
  p2   FTB result valid; branch type available. TAGE final. ITTAGE.
       RAS push or pop executes.
  p3   SC final.

  u0   Update address and write data presented to the RAMs.
  u1   RAM write completes.
```

Predictor stage assignments:

```
  p1   uBTB, LP
  p2   FTB, TAGE, ITTAGE, RAS
  p3   SC
```

The FTQ never stalls waiting for a predictor later than p1. Every
stage after p1 is a redirect source.

---

## 2. BPU to FTQ: The Initial Prediction

### 2.1 Selection at p1

The LP and uBTB are one-cycle predictors, current implementations use two single port RAMs in each predictor. The indexes are driven at p0 and its outputs are valid at p1. 

Both LP and uBTB support dual prediction, they will present two predictions per cycle when requested. Dual prediction is implemented as two independent prediction `slots`. The slots share no resources and operate fully independently.

The remaining discussion focuses on a single slot for clarity, the decisions and operation of the 2nd slot are identical.

Both LP and uBTB outputs are valid at p1. There is a selection mux which choses the prediction to present. 

```
  LP output valid    ->  a loop was detected; the LP prediction is used
  otherwise          ->  the uBTB prediction is used
  neither valid      ->  this slot carries no prediction
```

Both LP and uBTB assert a valid when they have a prediction, valid will not be asserted in the case of LP or uBTB misses. 

The LP or uBTB predictions are not sources for redirects since they both are the 1st prediction in the pipeline. 

When neither the LP nor the uBTB hits, the slot carries no prediction.
The successor PC for that case is defined in section 2.4.

### 2.2 Returns

RAS is only active for return branch types. The RAS presents its
top-of-stack entry as the predicted target, at p1.

The RAS does not participate in the uBTB/LP selection. It supplies the
target for one branch type, the return, taken from its stack rather
than from a prediction table.

The return branch type is available at p1 from the uBTB entry
(ubtb_entry_t.br_type), so the RAS is engaged without waiting for the
FTB branch-type classification at p2.

### 2.3 Allocation

The FTQ allocates an entry at p1, when the initial prediction is
formed, and issues the fetch from it. Allocation is unconditional: an
entry is allocated for every prediction block, including a block the
p1 predictors miss. The p1 predictors are early in the pipeline;
FTB, TAGE, ITTAGE, and RAS can each find or correct a branch at p2 or
p3, and a redirect names an FTQ entry index, so the FTQ entry is allocated in p1
for a later stage to correct it. A p1 miss allocates an entry whose
slots carry no taken prediction and whose successor is the
fall-through address.

The FTQ entry index is the 6-bit index into the 64-entry FTQ. It
identifies one fetch block and is the value carried in `branch_id`. All
NUM_PRED_SLOTS predictions for that block occupy the one entry.

The entry written at p1 records the prediction and the architectural state it was made against (section 4.1), so the block can be restored on a later redirect (section 6).

The IFU-FTQ interface carries fetch requests and completion responses. It is currently unspecified. See TD-FE-1.


### 2.4 Successor PC

The successor PC is the start PC of the next fetch block: the address
fetched after this block. It is selected across the block's slots,
priority-ordered top to bottom:

```
  slot 0 valid and taken   ->  slot 0 target
  slot 1 valid and taken   ->  slot 1 target
  otherwise                ->  fall-through address
```

Both slots are predicted at p1. The selection chooses which slot's
target is the successor; it does not gate whether a slot is predicted.

The selection is re-evaluated whenever a redirect rewrites a slot.

---

## 3. BPU to FTQ: Redirects

Correction and redirect are synonymous terms. A later-stage predictor may change — correct — the prediction currently held in the FTQ entry. Every correction after p1 is a redirect. A redirect identifies one FTQ entry index and carries a corrected target per slot.

### 3.1 Interface

Each redirecting predictor exposes these signals at its stage (<pN> is p2 or p3, per section 3.2):

  \<pred\>\_redir_val_<pN>  [0:NUM_PRED_SLOTS-1]  redirect asserted, per slot
  \<pred\>\_redir_tgt_<pN>  [0:NUM_PRED_SLOTS-1]  corrected target, per slot
  \<pred\>\_redir_ftq_idx_<pN>                    FTQ entry index corrected

val and tgt are per-slot arrays; the slot is the array index. A predictor drives both slots in one cycle, so it can correct a branch in each slot of one block at once. ftq_idx is scalar: both slots are in one fetch block, which is one FTQ entry.

The comparison that raises a redirect is made at the bp_cluster boundary, between the predictor's stage output and the entry the FTQ holds for that index. A predictor in isolation does not carry these signals; they exist only at the cluster boundary.

### 3.2 Sources

```
  p2   FTB, TAGE, ITTAGE, RAS
  p3   SC
```

The uBTB and the LP are not redirect sources since they form the initial predictions.

### 3.3 Direction and target

A redirect's payload is always a target (section 3). The FTB, RAS, and ITTAGE produce a target directly; TAGE and SC produce a direction, which then selects a target.

The FTB identifies the branch type of each slot at p2. That type
selects the target source for the slot:

```
  return        RAS spec_pop_addr
  indirect      ITTAGE
  conditional   direction from TAGE, then SC (see below)
  direct unc.   FTB branch target
```

Return and indirect are different branch types. The RAS and ITTAGE are
never both consulted for the same branch.

For a conditional branch, TAGE (p2) then SC (p3) supplies the direction, which
selects the target:

```
  taken      ->  FTB branch target
  not taken  ->  fallthrough address
```

The branch target and the fallthrough address both derive from the FTB
result. The derivation is an FTB-internal operation with a description
found in the FTB documentation. The contents of this documentation is
not necessary to follow the remaining discussion.

TAGE overrides the FTB direction on conditional branches only. At p3 the SC may
override the TAGE direction; the FTB result is still available, so both
target candidates are present when the SC direction selects between
them. 

A redirect rewrites its slot. The block's successor PC is then re-derived 
across all slots per section 2.4.

### 3.4 Supersession

A redirect from a later stage supersedes any earlier redirect for the
same FTQ entry index and the same slot. The FTQ tracks which redirects
are stale and discards them.

Redirects do not cross slots. A p3 redirect on slot 1 does not
discard a p2 redirect on slot 0 of the same entry; the two correct
different branches.

A p2 redirect and a p3 redirect for one entry index and slot can be in
flight in consecutive cycles, and the fetch stream started by the p2
redirect is already speculative when the p3 redirect arrives. The FTQ
does not compare targets to settle this. The later stage wins for the
entry index and slot it names.

---

## 4. The FTQ Entry

The FTQ entry is stored in two SRAMs, both indexed by the FTQ entry index. The fast path (`bp_ftq_entry_t`, section 4.1) is read every cycle. The slow path (`bp_ftq_meta_t`, section 4.2) is read only at update. The two are separated so the every-cycle read does not carry the width of the update-only metadata. The two path structures are declared in `bp_structs_pkg.sv`.

Both structures follow the package array-direction convention: packed-struct dimensions descend, `[NUM_PRED_SLOTS-1:0]`, matching `sc_pred_meta_t.sc_upd_idx`; port dimensions ascend, `[0:NUM_PRED_SLOTS-1]`, matching TD#90 and TD#91.

### 4.1 Fast path: bp_ftq_entry_t

`bp_ftq_entry_t` is read every cycle. It is written at p1 and rewritten by redirect.

Block scalar fields, one per entry:

```
pc            40     fetch block start PC, VA_WIDTH
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
pred_src       3     predictor that supplied this slot
                     not currently used, see TD-FE-4
confidence     4     saturating counter, FTQ_CONF_BITS
```

The per-slot array is declared inside `bp_ftq_entry_t`: one entry holds 
one fetch block and all its slots.

`br_type` is per slot and selects the predictor update set at resolution (section 7.2).

The history pointers and RAS snapshot are block scalar (sections 6.1, 9).

### 4.2 Slow path: bp_ftq_meta_t

`bp_ftq_meta_t` is stored in a separate, wider SRAM, read only on post-execute update and never on the prediction path.

It holds the state each predictor needs to train and cannot recompute at resolution. The field list is maintained in `bp_structs_pkg.sv` and described in `bp_cluster.md`, FTQ Entry Split. The struct nests one metadata block per predictor: `tage_pred_meta_t`, `sc_pred_meta_t`, `bp_loop_meta_t`, and `ittage_pred_meta_t`.

The metadata is per slot, carried `[NUM_PRED_SLOTS-1:0]`. Each slot produces its own provider indices, counter snapshots, and allocation targets.

Fields are overloaded by branch type. The overloading scheme is not settled (TD-FE-2).

`bp_ftq_meta_t` is written at p2 for the predictors that finalize there, and at p3 for the SC, to the entry index and slot the prediction occupies.

### 4.3 Read rates

`bp_ftq_entry_t` is read every cycle, by fetch and by every redirecting
predictor's cluster-boundary comparison. `bp_ftq_meta_t` is read once,
at resolution.

---

## 5. FTQ Entry Lifetime

```
  p1            allocate. Fast-path entry written, all slots.
  p2, p3        rewritten by redirect, per slot. The later stage wins
                for the slot it names.
  p2, p3        bp_ftq_meta_t written, per slot.
  post-execute  bp_ftq_meta_t read. Updates formed and enqueued.
```

The entry persists until its post-execute resolution, when its metadata is read. 
Allocation and deallocation policy is otherwise unspecified (FE-U7).

---

## 6. Checkpoint and Restore

The BPU owns all branch history state. Only the FTQ-facing checkpoint 
and restore are specified here; internal history management is out of scope.

### 6.1 What is check-pointed

A checkpoint consists of the GHR and PHR circular-buffer pointers, one pair per
FTQ entry, indexed by the FTQ entry index:

```
  ghist_ptr   8    GHR circular buffer pointer
  phist_ptr   5    PHR circular buffer pointer
```

A checkpoint is block granular: one pair per FTQ entry, covering the
bundle (G20). Checkpoints are written with post-update pointer values.

The RAS snapshot (`bp_ras_snapshot_t`) is a separate field of the
fast-path entry, not part of the checkpoint. It is restored on the same
redirect (section 6.2):

```
  TOSR   top of stack read pointer
  TOSW   top of stack write pointer
  BOS    bottom of stack
```

### 6.2 Restore

On redirect the FTQ presents the `ghist_ptr` and `phist_ptr` from the
checkpoint of the entry being corrected.

RAS restoration is discussed in Section 9.

---

## 7. FTQ to BPU: Updates

### 7.1 Trigger

Updates are triggered at post-execute resolution. Updates do not wait for retirement. 

There is one update channel per prediction slot, upd_ch[0] through upd_ch[NUM_PRED_SLOTS-1]. Each channel carries both conditional and indirect resolution.

### 7.2 Formation

On resolution of a branch at FTQ entry index `k`, slot `s`, the FTQ
reads slot `s` of `bp_ftq_meta_t[k]` from the slow-path SRAM, and reads
`pc` and slot `s` `br_type` from the fast-path entry.

The slot's `br_type` determines the set of predictors updated:

```
  conditional    uBTB, LP, FTB, TAGE, SC
  indirect       uBTB, FTB, ITTAGE
  return         uBTB, FTB, RAS
  direct unc.    uBTB, FTB
```

TAGE and SC predict direction and are updated only for conditional
branches. ITTAGE is updated only for indirect branches. RAS is updated
only for returns. The SC is excluded when disabled by its CSR bit
(FE-U6).

A predictor that missed at prediction time is still updated. Each
predictor derives allocate-versus-train from its own `bp_ftq_meta_t`
slice and the resolved outcome; that decision is predictor-internal.

The update path uses the metadata captured at predict. It does not
recompute predictor state from the PC or the history.

A slot off the executed path never resolves and forms no update.

### 7.3 Enqueue

Each RAM-based predictor has an update queue in front of it. The queue
is a FIFO with two write ports, so up to two updates may be enqueued
per cycle. Two write ports serve NUM_PRED_SLOTS = 2 update channels.

Updates reach a predictor in resolution order. This is an out-of-order
machine and resolution order is not program order. The FIFO is not
reordered.

The uBTB is combinational and has no queue; it updates immediately. The
RAS is register-file based and has no queue; its update is
snapshot-based, described in section 9.

---

## 8. Handshakes

The RAM arbitration model is specified in `bp_arb_spec.md` and is out
of scope here. Three handshakes cross the BPU/FTQ boundary.

**Prediction issue.** The FTQ can be back-pressured. A prediction
request is stalled. When the FTQ cannot accept the uBTB
output, the uBTB holds its output stable.

**Update enqueue.** The FTQ presents `upd_val` and `upd_inp` per
channel. The update queue asserts `upd_rdy` when it accepts. When the
queue is full, `upd_rdy` deasserts and the FTQ holds valid until
accepted.

**Prediction delivery.** The FTQ presents `consumer_ready`; the
predictor presents `pred_rdy` when its result is valid. The TAGE result
is consumed by both the FTQ and the SC.

A prediction may be granted ahead of a pending update to the same RAM
entry, and reads pre-update state. The potential accuracy loss from
the stale prediction state is accepted.

---

## 9. RAS

Only the FTQ-facing RAS behavior is stated here. RAS internals are in
`ras_decisions.md`.

The RAS is register-file based. It has no prediction queue, no update
queue, and no arbiter.

```
  p1   top-of-stack presented as the predicted target for a return
       (section 2.2). This is spec_pop_addr in the section 3.3 target
       table.
  p2   push or pop executes once the FTB branch type confirms a call
       or a return. Participates in the p2 redirect.
```

`bp_ras_snapshot_t` is checkpointed into the FTQ entry at the time of
the call or return that updated the RAS. On a misprediction or flush
the RAS is restored from the snapshot found in the entry being corrected.

One snapshot per FTQ entry is sufficient under dual slot. A RAS
operation is a call or a return, both taken branches, so a RAS
operation in slot 0 ends the block before slot 1 is reached. At most
one RAS operation therefore occurs per block, and one snapshot covers
it.

RAS flush behavior is open; see TD #96.

---

## 10. Prediction Slots

`NUM_PRED_SLOTS` parameterizes the number of prediction slots and the
number of update channels, `upd_ch[0]` through `upd_ch[NUM_PRED_SLOTS-1]`.

One FTQ entry holds all NUM_PRED_SLOTS predictions for one fetch block.

A fetch block is one 32-byte FTB block (FTB_BLOCK_BYTES). Both slots
are predicted from one FTB lookup: slot 0 is the block's first branch
field, slot 1 the second. The slots are not two PC ranges; they are
the two branch fields of one block (ftb_decisions.md 2.1, 2.3).

`dual_pred_en`, when clear, gates the second prediction slot off at
runtime. It does not change the structure: the slots and the channels
exist either way.

---

## 11. Invariants

Proposed numbering. Stated here for the first time; not carried from
`bp_cluster.md` or `bp_arb_spec.md`.

```
  FE-1   The FTQ allocates an entry and issues a fetch from the p1
         prediction. It never waits for a predictor later than p1.

  FE-2   The initial prediction is formed by selection at p1 between
         the LP and the uBTB, per slot. Every correction after p1 is
         a redirect naming an FTQ entry index and a slot.

  FE-3   A redirect from a later stage supersedes an earlier redirect
         for the same FTQ entry index and slot. The later stage wins
         by stage order. The FTQ does not compare targets to settle
         it. Supersession does not cross slots.

  FE-4   The redirect comparison is made at the cluster boundary,
         between a predictor's stage output and the entry the FTQ
         holds. No predictor is compared against another predictor.

  FE-5   No prediction and no update is dropped. A full prediction
         path stalls fetch. A full update queue stalls the update
         path.

  FE-6   Updates reach a predictor in resolution order. The update
         queue is a FIFO and is not reordered.

  FE-7   The FTQ history checkpoints are pointer-only and block
         granular, one per FTQ entry.

  FE-8   The update path uses metadata generated during predict. The
         set of predictors updated is determined by the slot's
         br_type.

  FE-9   A prediction granted ahead of a pending update to the same
         RAM entry reads pre-update state. The prediction accuracy
         loss from the stale read is accepted.

  FE-10  One FTQ entry holds one fetch block and all NUM_PRED_SLOTS
         predictions for it. The slots are the branch fields of one
         FTB block. The slot is the array index; no slot identifier
         field is carried.

  FE-11  At most one RAS operation occurs per block. A RAS operation
         is a taken branch, so a RAS operation in slot 0 ends the
         block before slot 1. One RAS snapshot per FTQ entry is
         therefore sufficient.
```

---

## 12. Source Document Conflicts

There is a known difference in pipe stage labeling.
RESOLUTION: all documents will transition to the p0/p1/p2/p3 labeling.
This document uses it.

`bp_arb_spec.md` contains errors. Where this document departs from it,
it does so deliberately:

```
  2, 7.1   uFTB output presented at p0.
           RESOLUTION: the initial prediction is formed at p1 and the
           FTQ allocates there. bp_arb_spec.md 7.2 itself refers to
           "the uBTB p1 prediction."

  2, 3.4   LP listed as a redirect source (lp_redir_val_p2).
           RESOLUTION: the LP is not a redirect source. It is selected
           against the uBTB by mux at p1. lp_redir_val_p2 does not
           exist.

  3.3      "SC > TAGE > FTB/LP > uFTB/RAS" presented as an override
           priority.
           RESOLUTION: there is no priority chain. These predictors do
           not produce the same quantity and do not contend. Redirects
           supersede by stage order (FE-3).

  3.3      "ITTAGE (p2) > RAS (p0)" presented as an override chain.
           RESOLUTION: there is no chain. br_type selects the RAS for
           a return and the ITTAGE for an indirect. The two are never
           both consulted for one branch.

  4.4      The update queue producer described as commit.
           RESOLUTION: the producer is post-execute resolution. The
           two write ports and the backpressure behavior are retained
           as written.

  4.4      Updates described as program-order.
           RESOLUTION: this is an out-of-order machine. Updates are
           enqueued and delivered in resolution order (FE-6).

  naming   uFTB.
           RESOLUTION: the predictor is the uBTB. This document uses
           uBTB throughout.
```

Prior revisions of this document assigned the two prediction slots to
fixed PC ranges (slot 0 pred_pc+0:31, slot 1 pred_pc+32:63), citing G8
and G17. That is the TAGE/ITTAGE bundle split and does not apply to the
FTB. The FTB prediction block is one 32-byte block and one FTB lookup
supplies both predictions (ftb_decisions.md 2.1, 2.3); the two slots
are the block's two branch fields, not two PC ranges. Section 10 now
follows ftb_decisions.md.

---

## 13. Technical Debt

```
  TD-FE-1  The IFU interface is unspecified. When the IFU
           specification is written, part of this debt is to update
           this document with the reference.

  TD-FE-2  bp_ftq_meta_t field overloading is not settled. Fields are
           overloaded by branch type; TAGE and ITTAGE share index
           fields. The metadata is also carried per slot, so the
           scheme has a slot dimension as well as a branch-type
           dimension. Deferred to implementation.

  TD-FE-3  bp_ftq_entry_t.pc and per-slot target are 40 bits. RVA23
           mandates the C extension, so bit 0 of an instruction
           address is always zero and 39 bits suffice. If a fetch
           block always begins on an FTB_BLOCK_BYTES boundary, pc
           needs 35. Held at 40 until the design is working; revisit
           at the optimization step, together with the width of
           <pred>_redir_tgt_<pN>, which carries the same quantity.
           The per-slot target is now replicated NUM_PRED_SLOTS
           times, so the saving scales with the slot count.
           To be merged into the project tech debt list.

  TD-FE-4  bp_ftq_slot_t.pred_src has no functional consumer. Update
           fan-out is determined by br_type (section 7.2); redirect
           supersession is by stage and slot (section 3.4); each
           predictor derives its own training decision from its
           bp_ftq_meta_t slice. The field is retained for diagnostic
           attribution of which predictor supplied the fetched
           prediction, and for performance counters. Nothing
           functional reads it. It is now replicated per slot.

           Removal requires cleanup outside this document:
           bp_cluster.md, FTQ Entry Split, lists pred_src as "which
           predictor won" with no consumer; bp_structs_pkg.sv carries
           the field and its encoding. Remove the field and its enum
           when both are updated.

           To be merged into the project tech debt list.

  TD-FE-5  bp_structs_pkg.sv comments branch_id as "FTQ slot index"
           in bp_ftq_entry_t, tage_pred_meta_t, sc_pred_meta_t, and
           ittage_pred_meta_t. The field is the FTQ entry index. With
           the prediction slot now a distinct concept, the comment
           reads as the slot index and should say "FTQ index".
           Comment-only, no behavior change.
```

---

## 14. Unresolved

```
  FE-U1  Return identification before p1. The RAS presents its
         top-of-stack as the initial predicted target for a return,
         but the FTB branch type does not exist until p2. What
         identifies the return at p1 is stated nowhere.

  FE-U2  Flush handling. How a backend mispredict flush reaches the
         FTQ is open. RAS flush behavior is TD #96.

  FE-U3  bp_ftq_slot_t.confidence, 4 bits. bp_cluster.md marks the
         purpose TBD and FTQ_CONF_BITS a placeholder. Nothing in
         either path reads it.

  FE-U4  PHR contribution to index and tag hashing. bp_cluster.md
         defers it to the TAGE and ITTAGE implementation sessions.

  FE-U5  Indirect chain update and correction semantics.
         bp_arb_spec.md defers RAS and ITTAGE to a later spec.

  FE-U6  SC CSR enable. bp_arb_spec.md 0 states that when the SC is
         disabled the control logic issues no SC updates, does not
         process the SC response queue, and does not wait on it,
         while SC-related buffering and storage continue as normal.
         The phrasing is not yet placed in the specification.

  FE-U7  FTQ allocation and deallocation policy. Neither source
         document specifies when an entry is freed, in what order, or
         what backpressures allocation when the FTQ is full.

  FE-U8  CLOSED. Fetch block to FTQ entry mapping. bp_ftq_entry_t now
         carries a per-slot array of target, taken, and br_type, so
         one entry represents one fetch block with NUM_PRED_SLOTS
         predicted branches. See sections 4.1 and 10, FE-10.

  FE-U9  br_type update fan-out covers four of the seven
         bp_br_type_e encodings. The section 7.2 table has rows for
         conditional, indirect, return, and direct unconditional.
         DIRECT_CALL, INDIRECT_CALL, and NO_BRANCH have no row. Both
         call encodings push the RAS, and per the session-061 ruling
         INDIRECT_CALL updates ITTAGE for the target and RAS for the
         return address. Independent of the slot count.
```

---

## 15. Document History

```
  2026-07-09  tmp_004. Written from bp_cluster.md rev 1.0,
              bp_arb_spec.md rev 1.0, and bp_structs_pkg.sv. Covers
              the BPU to FTQ prediction and redirect path and the FTQ
              to BPU update path. Predictor internals and the RAM
              arbitration model are out of scope. Departures from
              bp_arb_spec.md are recorded in section 12.

  2026-07-23  fe_decisions.md. Renamed from tmp_004.md. Dual-slot FTQ
              entry applied, closing FE-U8. bp_ftq_entry_t split into
              block-scalar fields and a per-slot bp_ftq_slot_t array;
              bp_ftq_meta_t carried per slot. Redirect val and tgt
              became per-slot arrays with a scalar ftq_idx; the slot
              is the array index. Supersession restated per entry and
              slot. Section 2.4 successor PC selection added. History
              checkpoint and RAS snapshot confirmed block granular,
              with the one-RAS-operation-per-block argument recorded
              in section 9. FE-10, FE-11, TD-FE-5, and FE-U9 added.
              ITTAGE raw/final split removed (single-stage target at
              p2; the p2/p3 split was a conventional LUT-plus-offset
              artifact not present in Pacino). Section 10 slot model
              corrected: the two slots are the branch fields of one
              32-byte FTB block, not two fixed PC ranges; G8/G17 is
              the TAGE/ITTAGE bundle split and does not govern the
              FTB (ftb_decisions.md 2.1, 2.3). Intro line, FE-10, and
              FE-11 propagated to the branch-field model; FE-11
              restated to the RAS-operation basis.
```
