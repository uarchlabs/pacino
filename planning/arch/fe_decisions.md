```
 FILE:    fe_decisions.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-08-19
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
       folded history available. RAS top of stack read.
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
  p0   RAS top of stack read
  p1   uBTB, LP
  p2   FTB, TAGE, ITTAGE, RAS push/pop
  p3   SC
```

The FTQ never stalls waiting for a predictor later than p1. Every
stage after p1 is a redirect source.

---

## 2. BPU to FTQ: The Initial Prediction

### 2.1 Selection at p1

The LP and uBTB are one-cycle predictors, current implementations use two single port RAMs in each predictor. The indexes are driven at p0 and its outputs are valid at p1. 

Both LP and uBTB support dual prediction, they will present two predictions per cycle when requested. Dual prediction is implemented as two independent prediction `slots`. The slots share no resources and operate fully independently.

The loop predictor was retrofitted to NUM_PRED_SLOTS in BP-091: every
prediction and update port carries a slot dimension and the internal
tables are per-slot banks (TI6). Its prediction output is named
`pred_p1`.

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
top-of-stack entry as the predicted target. THE TOP OF STACK IS READ
AT p0: ras.sv declares `ras_tos_addr_p0` and `ras_tos_valid_p0`. The
cluster registers that value and applies it when the p1 selection mux
forms a RETURN slot.

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

The entry written at p1 records the prediction and the architectural state it was made against (ftq_entry_formats.md 2), so the block can be restored on a later redirect (ftq_decisions.md 3).

The IFU-FTQ interface carries fetch requests and a predecode
writeback. It is specified in ftq_ifu_interfaces.md.


### 2.4 Successor PC

The successor PC is the start PC of the next fetch block: the address
fetched after this block. It is selected across the block's slots,
priority-ordered top to bottom:

```
  slot 0 valid and taken   ->  slot 0 target
  slot 1 valid and taken   ->  slot 1 target
  otherwise                ->  fall-through address
```

The fall-through address for the not-taken case arrives on the p1
output group as `bpu_pred_pft_p1`, one value per prediction, qualified
by `bpu_pred_val_p1` (TD#108, BP-092). Before that port existed the
block end stayed inside the cluster and the FTQ had no source for it
on a not-taken block.

The FTQ writes that value into the allocated entry as
`bp_ftq_entry_t.pft_addr` (ftq_entry_formats.md 2). `bpu_pred_pft_p1`
only in the p1 cycle, and the selection above is re-evaluated on every
redirect, so the not-taken arm has to be read back from the entry
rather than resampled from the cluster.

Both slots are predicted at p1. The selection chooses which slot's
target is the successor; it does not gate whether a slot is predicted.

The selection is re-evaluated whenever a redirect rewrites a slot.

### 2.5 Slot correction at p2 and p3

The p1 prediction is the uBTB and loop-predictor view. The FTB
classifies the block at p2 and supplies the in-block position of each
branch field. Those are corrections to the RECORD, and they are
needed whether or not fetch has to be resteered.

The cluster therefore publishes its view of every slot again at p2,
and once more at p3 with the SC direction applied:

```
  bpu_slot_val_p2   bpu_slot_idx_p2   bpu_slot_p2 [0:NUM_PRED_SLOTS-1]
  bpu_slot_val_p3   bpu_slot_idx_p3   bpu_slot_p3 [0:NUM_PRED_SLOTS-1]
```

Each group carries one `bp_ftq_slot_t` per slot, the same type the p1
group delivers. The FTQ overwrites the slot description of the named
entry with the latest group it has received.

THE GROUP IS NOT GATED ON A REDIRECT (FE-13). A redirect fires only
when the p2 successor differs from the p1 successor, and the case
that matters most does not qualify: a conditional branch the uBTB
missed and the FTB found, predicted not taken. Both views end the
block at the same address, no redirect fires, and without this group
the entry would keep `br_type` NO_BRANCH and `pos` zero for its whole
life -- so section 7.2 would form no update for it and no predictor
would ever be trained on that branch. See TD-FE-6.

A slot holding the block's jump field takes the jump field's own
position, not a conditional field's, matching the lowest-free-slot
placement rule of section 10.

p3 changes only `taken`, and `pred_src` when SC actually moved the
direction. SC corrects direction, not branch type, so `br_type`,
`pos` and `target` are carried through the p2 to p3 register
unchanged.

The port specification is ftq_bpu_interfaces.md section 4a.

---

## 3. BPU to FTQ: Redirects

Correction and redirect are synonymous terms. A later-stage predictor may change -- correct -- the prediction currently held in the FTQ entry. Every correction after p1 is a redirect. A redirect identifies one FTQ entry index and carries a corrected target per slot.

### 3.1 Interface

NO PREDICTOR DECLARES A REDIRECT PORT. INFRA-011 confirmed this across
all 140 ports of the eight top-level BPU modules. A prior revision of
this section named `<pred>_redir_val_<pN>`, `<pred>_redir_tgt_<pN>` and
`<pred>_redir_ftq_idx_<pN>` as a per-predictor port group. No such
ports exist and none is planned.

The redirect is DERIVED at the bp_cluster boundary. The cluster
compares a predictor's stage output against the prediction it formed at
p1 and carried forward in its own stage registers (FE-4). bp_cluster
does not read the FTQ.

The groups are named by STAGE, not by predictor:

```
  bpu_redir_p2      bp_redirect_t [0:NUM_PRED_SLOTS-1]
  bpu_redir_idx_p2  [FTQ_IDX_BITS-1:0]
  bpu_redir_p3      bp_redirect_t [0:NUM_PRED_SLOTS-1]
  bpu_redir_idx_p3  [FTQ_IDX_BITS-1:0]
```

`bp_redirect_t` is the per-slot payload and carries `target_pc` and
`valid`. The array is per slot; the index is scalar alongside it,
because both slots occupy one fetch block, which is one FTQ entry.

p2 carries the FTB, TAGE, ITTAGE and RAS corrections. p3 carries the SC
correction.

The comparison reduces both views of a slot to ONE quantity, the
address fetched after that slot. Two not-taken views therefore compare
equal and raise no redirect. The p1 operand is formed at p1 from the p1
view only: the slot target when taken, the uBTB fall-through on a hit,
the block-aligned PC plus FTB_BLOCK_BYTES on a miss.

The p3 comparison is against the p2-corrected value, not the raw p1
prediction, so a p3 redirect fires only when SC changes what the cluster
published at p2.

Every p2 and p3 comparison is qualified by `branch_id` equal to the FTQ
index held in the matching stage register, so a queued or
back-pressured response cannot be compared against the wrong entry. The
redirect logic assumes no fixed predictor latency.

The port specification is ftq_bpu_interfaces.md section 6.

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

## 4, 5, 6. MOVED

The FTQ entry formats, the entry lifetime, and the checkpoint and
restore behaviour left this document on 2026-08-19. They are FTQ
internals; this document is the BPU <-> FTQ boundary.

```
  was 4.1  fast path bp_ftq_entry_t  ->  ftq_entry_formats.md 2
  was 4.2  slow path bp_ftq_meta_t   ->  ftq_entry_formats.md 3
  was 4.2.1 overload scheme          ->  ftq_entry_formats.md 3.1
  was 4.3  read rates                ->  ftq_decisions.md 1
  was 5    entry lifetime            ->  ftq_decisions.md 2
  was 6    checkpoint and restore    ->  ftq_decisions.md 3
```

Section numbers 4, 5 and 6 are retired rather than reused, so every
"section 7.2" and "section 2.4" reference in this document and in
ftq_bpu_interfaces.md still resolves.

The registries stay here: invariants in section 11, technical debt
in section 13, unresolved items in section 14. They cover the front
end as a whole and are not split.

---

## 7. FTQ to BPU: Updates

### 7.1 Trigger

Updates are triggered at post-execute resolution. Updates do not wait for retirement. 

There is one update channel per prediction slot, upd_ch[0] through upd_ch[NUM_PRED_SLOTS-1]. Each channel carries both conditional and indirect resolution.

### 7.2 Formation

On resolution of a branch at FTQ entry index `k`, slot `s`, the FTQ
reads slot `s` of `bp_ftq_meta_t[k]` from the slow-path SRAM, and reads
`pc` and slot `s` `br_type` from the fast-path entry.

The slot's `br_type` determines the set of predictors updated. It is
the FTB classification, placed in the entry by the p2 slot correction
group (section 2.5), not the p1 uBTB view (TD-FE-6):

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
  p0   top-of-stack read. ras.sv declares ras_tos_addr_p0 and
       ras_tos_valid_p0. The cluster registers the value and applies
       it at p1 as the predicted target for a return (section 2.2).
       This is spec_pop_addr in the section 3.3 target table.
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
it. The cluster enforces this by gating p2 RAS operations on
reachability across slots (FE-11).

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

The uBTB follows the same model. BP-086 rewrote ubtb.sv to a single
lookup returning one entry that describes one block and supplies both
slots; the `pred_pc_p0 + 32` slot-1 lookup is retired.

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
         between a predictor's stage output and the prediction the
         cluster formed at p1 and holds in its own stage registers.
         No predictor is compared against another predictor, and the
         cluster does not read the FTQ.

  FE-5   No prediction is dropped, and no update is dropped except
         as FE-5a permits. A full prediction path stalls fetch. A
         full update queue stalls the update path.

  FE-5a  AMENDMENT 2026-08-19. An FTB update may be dropped on
         collision, and ONLY when it is low value: the FTB hit at
         predict and the branch was predicted correctly, so the
         update is a routine conf step on a counter already in the
         right direction. An update that allocates an entry or
         corrects a mispredict is never dropped; where dropping one
         would otherwise be required the FTQ backpressures
         resolution instead. The FTB update port is scalar and the
         8-issue target resolves more than one branch per cycle, so
         without this the FTB training rate would stall the backend.
         Applies to the FTB path alone. Every other predictor takes
         one update per slot per cycle and keeps FE-5 unqualified.
         ftq_decisions.md 5.7, IC-FTB-09.

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
         field is carried. The index is ORDERED as of IC-FTB-16:
         slot 0 is the block's first branch in program order.

  FE-11  At most one RAS operation occurs per block. A RAS operation
         is a taken branch, so a RAS operation in slot 0 ends the
         block before slot 1. One RAS snapshot per FTQ entry is
         therefore sufficient.

  FE-12  No predictor declares a redirect port. Redirects exist only
         as cluster-derived, stage-named groups (section 3.1).

  FE-13  The cluster publishes its view of every slot on every
         prediction, at p2 and again at p3, not only when a redirect
         fires. A redirect says fetch must be resteered; the slot
         correction group says what the entry must record. The two
         are different questions and fire at different rates.
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
           exist. No predictor declares any redirect port (FE-12).

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
follows ftb_decisions.md, and BP-086 removed the retired model from
ubtb.sv.

---

## 13. Technical Debt

```
  TD-FE-1  CLOSED 2026-08-19. The IFU interface is specified in
           planning/interfaces/ftq_ifu_interfaces.md. Section 2.3 of
           this document referenced the gap and now names the file.
           The predecode writeback forms NO predictor update: FE-8
           keeps update formation post-execute, and a second
           producer in a different order would break FE-6. The
           writeback is the third correction of a slot, after the p2
           and p3 slot correction groups.

  TD-FE-2  CLOSED. bp_ftq_meta_t field overloading. Resolved in
           ftq_entry_formats.md 3.1: a two-arm packed union, u.cond
           holding
           tage, sc and lp, u.ind holding ittage, with ftb and a
           wr_br_type discriminant outside the union. 420b -> 280b
           per slot. The slot dimension is unaffected: the union is
           inside bp_ftq_meta_t and the array is still declared at
           instantiation.

  TD-FE-3  bp_ftq_entry_t.pc and per-slot target are 40 bits. RVA23
           mandates the C extension, so bit 0 of an instruction
           address is always zero and 39 bits suffice. If a fetch
           block always begins on an FTB_BLOCK_BYTES boundary, pc
           needs 35. Held at 40 until the design is working; revisit
           at the optimization step, together with the width of
           bp_redirect_t.target_pc, which carries the same quantity.
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
           ftq_entry_formats.md section 2 lists pred_src as the
           predictor that won, with no consumer; bp_structs_pkg.sv
           carries
           the field and its encoding. Remove the field and its enum
           when both are updated.

           To be merged into the project tech debt list.

  TD-FE-7  bp_cluster derives its bp_history rollback entirely from
           its own p2 and p3 redirects (bp_cluster.sv 944-945) and
           declares no input by which the FTQ can request one. The
RAS can be restored on a backend mispredict, because
           ras_restore_val is an input, but the history rollback
           cannot be triggered at all.

           THE STATE IS NOT MISSING. bp_history.sv holds the full
           checkpoint array, ckpt_gptr and ckpt_pptr of FTQ_DEPTH
           entries indexed by FTQ index, and rolls back by reading
           it. Every checkpoint the machine needs is already inside
           the cluster. What is missing is the TRIGGER: for a p2 or
           p3 redirect the cluster knows the index from its own
           stage registers, but for a backend redirect the index is
           known only to the FTQ and no port carries it in.

           The fix is two input ports, ftq_rollback_val and
           ftq_rollback_idx -- seven bits, a valid and an index, no
           history data -- ORed into the existing rollback with
           priority over the cluster's own, since an architectural
           correction outranks a speculative one. Whether the FTQ
           instead presents the pointer VALUES from its entry is an
           implementation choice to settle when this is built; the
           index form is cheaper and matches the cluster's internal
           path. Blocks
           ftq_backend_interfaces.md section 5 D1. Same class as
           TD-FE-6 and found the same way, by writing down what the
           FTQ would have to drive.

  TD-FE-6  CLOSED. bp_ftq_slot_t.br_type and .pos held the p1 uBTB
           values for the entry's whole life. bp_cluster formed the
           FTB classification in w_br_type_p2 and the FTB positions
           in w_ftb_br0_pos_p2 / w_ftb_br1_pos_p2, but no port
           carried any of them out: bp_redirect_t holds target_pc
           and valid only. Section 7.2 keys update fan-out off
           br_type, so a block the uBTB missed and the FTB hit read
           NO_BRANCH at resolution and formed NO update at all --
           the case where training matters most. Section 7.4 of
           ftq_bpu_interfaces.md claimed pos came from the FTB,
           which no port made possible.
           Carrying the type on bp_redirect_t does NOT fix it: a
           redirect fires only when the p1 and p2 successors differ,
           and the defining case is a not-taken conditional the uBTB
           missed, where both views end the block at the same
           address and no redirect fires. The classification is
           needed on every prediction, the redirect is an exception
           path.
           Fixed by the section 2.5 slot correction group, valid on
           every prediction the FTB answers. tb_bp_cluster group I,
           24 checks; sim_bp_cluster 973 -> 997. Proven by mutation:
           gating bpu_slot_val_p2 on w_any_redir_p2 reproduces the
           defect and I1 catches it.

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
         but the FTB branch type does not exist until p2. The uBTB
         entry's br_type is what identifies the return at p1
         (section 2.2); the residual question is what happens when
         the uBTB misses and the block contains a return.

  FE-U2  CLOSED for the FTQ side, 2026-08-19. A backend mispredict
         flush reaches the FTQ on the redirect group of
         ftq_backend_interfaces.md section 5, which serves
         mispredict, trap and replay from one port set. The RAS
         flush behaviour behind D3 there remains TD #96, and FTB
         flush remains G24.

  FE-U3  bp_ftq_slot_t.confidence, 4 bits. bp_cluster.md marks the
         purpose TBD and FTQ_CONF_BITS a placeholder. Nothing in
         either path reads it; the cluster drives it to zero.

  FE-U4  PHR contribution to index and tag hashing. bp_cluster.md
         defers it to the TAGE and ITTAGE implementation sessions.

  FE-U5  Indirect chain update and correction semantics.
         bp_arb_spec.md defers RAS and ITTAGE to a later spec.

  FE-U6  SC CSR enable. bp_arb_spec.md 0 states that when the SC is
         disabled the control logic issues no SC updates, does not
         process the SC response queue, and does not wait on it,
         while SC-related buffering and storage continue as normal.
         The phrasing is not yet placed in the specification.

  FE-U7  CLOSED 2026-08-19. FTQ allocation and deallocation policy
         is ftq_decisions.md 5. Three pointers with a wrap bit:
         alloc advances at p0 when the request is accepted, since
         ftq_pred_idx_p0 leaves with it; fetch advances on the IFU
         handshake; one commit pointer both issues the RAS commit
         and frees, walking at one entry per cycle because
         ras_commit_* is scalar. Full is alloc catching commit and
         is the only condition that stops the FTQ predicting.
         Redirect rewinds alloc and fetch, never commit.

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
         return address. NO_BRANCH forms no update. Independent of
         the slot count.
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

  2026-08-09  INFRA-012 / session-064. Three corrections carried from
              ftq_bpu_interfaces.md section 10.
              Section 2.2 and section 9: the RAS top of stack is read
              at p0, not p1. ras.sv declares ras_tos_addr_p0 and
              ras_tos_valid_p0; the cluster registers the value and
              applies it at p1. Section 1 stage list updated to match.
              Section 3.1: the per-predictor redirect port group was
              removed. No predictor declares a redirect port
              (INFRA-011, all 140 ports). Rewritten to the
              cluster-derived, stage-named groups bpu_redir_p2 and
              bpu_redir_p3, with the one-quantity comparison, the p1
              operand definition, the p3 comparison basis and the
              branch_id qualification. FE-4 restated and FE-12 added.
              Section 4.2: bp_loop_meta_t replaced by lp_pred_t
              (TD#106, BP-092); ftb_pred_meta_t added to the nested
              member list. TD-FE-3 reference to <pred>_redir_tgt_<pN>
              retargeted to bp_redirect_t.target_pc.
              Also updated: section 2.1 for the BP-091 loop_pred
              dual-slot retrofit; section 2.4 and 4.1 for
              bpu_pred_pft_p1 and bp_ftq_slot_t.pos; section 10 for
              the BP-086 uBTB block model; FE-U1, FE-U3 and FE-U9
              sharpened.

  2026-08-19  Section 4.3 corrected. It stated that the fast-path
              entry is read by "every redirecting predictor's
              cluster-boundary comparison", contradicting FE-4 and
              section 3.1 of this document and section 6 of
              ftq_bpu_interfaces.md, all three of which state that
              bp_cluster does not read the FTQ. The sentence
              predates the session-064 FE-4 rewrite and was the only
              statement bearing on fast-path read-port count.
              Rewritten to the three real readers, all of them the
              FTQ itself: fetch every cycle, the redirect apply
              path, and resolution.

  2026-08-19  bp_ftq_entry_t gains pft_addr, the block fall-through,
              VA_WIDTH and block scalar. Sections 2.4 and 4.1
              updated. The successor selection of 2.4 is re-evaluated
              on every redirect and its not-taken arm is
              bpu_pred_pft_p1, which is present only in the p1 cycle,
              so the value must be held in the entry. Applied to
              bp_structs_pkg.sv and checked in tb_bp_pkg.sv. Entry
              width 182b -> 222b. All 47 bpu targets green.

  2026-08-19  TD-FE-2 RESOLVED. Section 4.2.1 added: the
              bp_ftq_meta_t overload scheme. Two-arm packed union,
              u.cond {tage, sc, lp} against u.ind {ittage}, with ftb
              and a wr_br_type discriminant held outside it. Arm
              selection, four write rules and three read rules
              stated; the p3 SC write must be suppressed on the
              indirect arm or it corrupts ITTAGE state. 420b -> 280b
              per slot, slow path 53,760b -> 35,840b. Section 7.2
              fan-out re-keyed from bp_ftq_slot_t.br_type to
              bp_ftq_meta_t.wr_br_type, and the stale sentence in
              4.1 corrected. TD-FE-6 opened: the p2 FTB
              classification reaches no FTQ-facing port, which is
              both a prerequisite for this scheme and a pre-existing
              defect in the 7.2 fan-out. FE-13 added.

  2026-08-19  TD-FE-6 CLOSED, and the TD-FE-2 record restaged around
              it. Section 2.5 added: the p2 and p3 slot correction
              groups, delivered in bp_cluster.sv, which carry the FTB
              classification and the in-block positions into the
              fast-path entry on EVERY prediction rather than only on
              a redirect. Section 4.1 and section 7.2 returned to
              keying update fan-out on bp_ftq_slot_t.br_type, which
              is now correct. FE-13 restated to the slot correction
              group. Section 4.2.1 restaged: the union is DEFINED AND
              DEFERRED, a storage optimization with no other
              dependency, and its wr_br_type discriminant is dropped
              -- it was proposed while the fast-path br_type was
              stale and is redundant now. 280b -> 277b per slot,
              slow path 35,456b, FTQ 49,664b. tb_bp_cluster group I,
              24 checks, sim_bp_cluster 973 -> 997, all 47 targets
              green in this session.

  2026-08-19  ftq_backend_interfaces.md written: resolution,
              redirect and commit. FE-U2 closed for the FTQ side.
              TD-FE-7 opened -- bp_cluster has no history-rollback
              input, so a backend mispredict cannot restore the GHR
              and PHR pointers. Third of the four FTQ interfaces;
              only ftq_icache remains, and it is a decision rather
              than a specification.
```

