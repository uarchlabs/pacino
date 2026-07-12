```
 FILE:    tmp_004.md
 SOURCE:  planning/arch/bp_cluster.md
          planning/arch/bp_arb_spec.md
          rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
 STATUS:  DRAFT
 UPDATED: 2026-07-09
 CONTACT: Jeff Nye
```

# Front End Theory of Operation: BPU and FTQ

This document describes the two paths that connect the branch
prediction cluster and the fetch target queue.

BPU to FTQ carries predictions. The FTQ allocates an entry on the
initial prediction and issues a fetch from it. Later predictors correct
that entry by redirect.

FTQ to BPU carries updates. On post-execute resolution the FTQ reads
the metadata captured at prediction time and forms an update for each
predictor named by the resolved branch type. Updates reach the
predictors through per-predictor update queues.

Predictor internals are out of scope, as is the RAM arbitration model.
This document states what each predictor contributes to the FTQ, when,
and the handshakes that carry it.

Stage labeling is p0 through p3 for prediction and u0/u1 for update.

---

## 1. Stages

```
  p0   Indices and addresses presented to the RAMs. PC hash and
       folded history available.
  p1   RAM outputs available. The initial prediction is formed. The
       FTQ allocates an entry and issues a fetch.
  p2   FTB result valid; branch type available. TAGE final. ITTAGE
       raw. RAS push or pop executes.
  p3   SC final. ITTAGE final.

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
stage after p1 is a correction path.

---

## 2. BPU to FTQ: The Initial Prediction

### 2.1 Selection at p1

The LP is a one-cycle RAM. Its index is driven at p0 and its output is
valid at p1. The uBTB output is valid at p1.

The two are selected by mux, in the same cycle. There is no bubble.

```
  LP output valid    ->  a loop was detected; the LP prediction is used
  otherwise          ->  the uBTB prediction is used
  neither valid      ->  next PC is PC + fetch_width
```

A uBTB miss produces no prediction. The uBTB output carries a valid,
and valid low is the miss. The uBTB asserts no redirect, because it is
the initial prediction and there is nothing earlier for it to correct.

The fetch of the block at the current PC is unconditional. The uBTB and
LP determine the successor PC written into the entry, not whether the
current block is fetched. On a miss, fetch proceeds sequentially at
PC + fetch_width until a later predictor redirects the entry.

### 2.2 Returns

For a block that ends in a return the RAS presents its top-of-stack
entry as the initial predicted target.

The RAS does not participate in the uBTB/LP selection. It supplies a
return target; the uBTB and LP supply a next PC for the fetch block.
They do not predict the same quantity.

The mechanism by which a return is identified before p1 is unresolved.
See section 14.

### 2.3 Allocation

The FTQ allocates an entry, writes the fast-path entry, and issues the
fetch. It does not wait for FTB, TAGE, SC, or ITTAGE.

The FTQ entry index is the 6-bit index into the 64-entry FTQ. It names
one fetch block and is the value carried in `branch_id`.

The interface by which the FTQ requests a fetch from the IFU, and by
which the IFU signals the fetch has returned, is unspecified. See
TD-FE-1.

The entry written at p1 records what was predicted and the
architectural state the prediction was made against. That second part
is what makes recovery possible; see section 6.

---

## 3. BPU to FTQ: Redirects

Every correction after p1 is a redirect. A redirect names one FTQ entry
index and carries a corrected target.

### 3.1 Interface

Each redirecting predictor exposes, at its own stage:

```
  <pred>_redir_val_<pN>       redirect asserted
  <pred>_redir_tgt_<pN>       corrected target PC, VA_WIDTH
  <pred>_redir_ftq_idx_<pN>   FTQ entry index being corrected
```

The comparison that raises a redirect is made at the bp_cluster
boundary, between a predictor's stage output and the entry the FTQ
currently holds for that index. No predictor is compared against
another predictor's output, and no predictor performs the comparison
itself. A predictor unit in isolation does not carry these signals.

### 3.2 Sources

```
  p2   FTB, TAGE, ITTAGE, RAS
  p3   SC, ITTAGE final
```

The uBTB and the LP are not redirect sources. They form the initial
prediction, which is what every redirect corrects against.

### 3.3 Direction and target

A redirect corrects one of two quantities: a direction or a target.

TAGE and SC predict direction. They contribute a direction and nothing
else. The direction selects the redirect target:

```
  taken      ->  FTB branch target
  not taken  ->  fallthrough address
```

Both derive from the FTB result. How they are derived is FTB-internal
and out of scope here.

The FTB, RAS, and ITTAGE predict targets. The FTB also identifies the
branch type of the block, at p2. That type selects the target source:

```
  return        RAS spec_pop_addr
  indirect      ITTAGE
  conditional   direction from TAGE, then SC; target selected by that
                direction per the table above
  direct unc.   FTB branch target
```

Return and indirect are different branch types. The RAS and the ITTAGE
are never both consulted for one branch, so neither overrides the
other. TAGE overrides the FTB direction on conditional branches only.

At p3 the SC may override the TAGE direction. The FTB result remains
available at p3, so both target candidates are present when the SC
direction selects between them. The ITTAGE final result is also
available at p3 and may refine an indirect target taken from the raw
ITTAGE result at p2.

### 3.4 Supersession

A redirect from a later stage supersedes any earlier redirect for the
same FTQ entry index. The FTQ tracks which redirects are stale and
discards them.

A p2 redirect and a p3 redirect for one entry index can be in flight in
consecutive cycles, and the fetch stream started by the p2 redirect is
already speculative when the p3 redirect arrives. The FTQ does not
compare targets to settle this. The later stage wins for the entry
index it names.

---

## 4. The FTQ Entry

Two SRAMs, indexed by the same FTQ entry index. The split exists
because the two halves have different read rates.

Both structures are declared in `bp_structs_pkg.sv` as
`bp_ftq_entry_t` and `bp_ftq_meta_t`.

### 4.1 Fast path: bp_ftq_entry_t

Read every cycle. Written at p1 and rewritten by redirect.

```
  pc            40     fetch block start PC, VA_WIDTH
  target        40     predicted next PC
  br_type        3     conditional, indirect, return, direct-unc, none
  taken          1     predicted direction
  pred_src       3     predictor that supplied the prediction
                       not currently used, see TD-FE-4
  confidence     4     saturating counter, FTQ_CONF_BITS
  branch_id      6     FTQ entry index
  ras                  bp_ras_snapshot_t: TOSR, TOSW, BOS, 4 bits each
  ghist_ptr      8     GHR circular buffer pointer snapshot
  phist_ptr      5     PHR circular buffer pointer snapshot
  valid          1
```

`br_type` determines which predictors receive an update at resolution.
The set is a property of the branch class, not of which predictors
produced a result. See section 7.2.

### 4.2 Slow path: bp_ftq_meta_t

A separate, wider SRAM. Read only on post-execute update. Never read on
the prediction path.

It holds what each predictor needs to train itself and cannot recompute
at resolution. The field list is maintained in `bp_structs_pkg.sv` and
described in `bp_cluster.md`, FTQ Entry Split. In summary: TAGE
provider and alt-provider indices, components, counters, usefulness
bits, and allocation target; SC per-table indices and counter snapshots
for ST0 through ST4; LP index, tag, way, age, confidence, and iteration
counters; ITTAGE indirect-branch and indirect-call flags.

Fields are overloaded by branch type. The overloading scheme is not
settled; see TD-FE-2. Width is not a timing concern on this path.

`bp_ftq_meta_t` is captured at p2 for the predictors that finalize at
p2, and at p3 for the SC. It is written to the FTQ entry index the
prediction occupies.

### 4.3 Read rates

`bp_ftq_entry_t` is read every cycle, by fetch and by every redirecting
predictor's cluster-boundary comparison. `bp_ftq_meta_t` is read once,
at resolution. Storing them together would make every prediction-path
read carry the width of the metadata.

---

## 5. FTQ Entry Lifetime

```
  p1            allocate. Fast-path entry written.
  p2, p3        rewritten by redirect. The later stage wins.
  p2, p3        bp_ftq_meta_t written.
  post-execute  bp_ftq_meta_t read. Updates formed and enqueued.
```

The entry must survive to its own post-execute resolution, because that
is when its metadata is read. Nothing in this document requires it
beyond that point.

The FTQ allocation and deallocation policy is unspecified. See FE-U7.

---

## 6. Checkpoint and Restore

The BPU owns all branch history state.

### 6.1 What is checkpointed

One checkpoint per FTQ entry, 64 entries, held as register arrays
indexed by the FTQ entry index:

```
  ghist_ptr   8    GHR circular buffer pointer
  phist_ptr   5    PHR circular buffer pointer
```

plus the RAS snapshot carried in the fast-path entry:

```
  TOSR   top of stack read pointer
  TOSW   top of stack write pointer
  BOS    bottom of stack
```

Checkpoints are written with post-update pointer values.

### 6.2 Restore

On redirect the FTQ presents the `ghist_ptr` and `phist_ptr` from the
checkpoint of the entry being corrected.

The RAS restores by pointer. TOSR, TOSW, and BOS are written back from
the snapshot in the entry.

---

## 7. FTQ to BPU: Updates

### 7.1 Trigger

Post-execute resolution. Updates do not wait for retire.

One update channel per prediction slot, `upd_ch[0]` through
`upd_ch[NUM_PRED_SLOTS-1]`. Each channel carries both conditional and
indirect resolution. They are not split by branch type.

### 7.2 Formation

On resolution of the branch at FTQ entry index k, the FTQ reads
`bp_ftq_meta_t[k]` from the slow-path SRAM and reads the fast-path
entry for `pc` and `br_type`.

The set of predictors updated is determined by `br_type`:

```
  conditional    uBTB, LP, FTB, TAGE, SC
  indirect       uBTB, FTB, ITTAGE
  return         uBTB, FTB, RAS
  direct unc.    uBTB, FTB
```

TAGE and SC predict direction and never see an indirect or a return.
ITTAGE never sees a conditional. RAS sees only returns.

The SC is excluded when disabled by its CSR bit. See FE-U6.

A predictor that missed at prediction time is still updated. The miss
is the allocation case: the FTB allocates its entry, TAGE allocates on
a misprediction with no provider, the LP allocates a way, the uBTB
allocates. Each predictor derives allocate-or-train from its own
`bp_ftq_meta_t` slice and the resolved outcome. Nothing in the FTQ
records which predictors produced a result.

The update path uses metadata generated during predict. It does not
recompute predictor state from the PC or the history.

### 7.3 Enqueue

Each RAM-based predictor has an update queue in front of it. The queue
is a FIFO with two write ports, so up to two updates may be enqueued
per cycle.

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

**Prediction issue.** The FTQ can be backpressured. A prediction
request is stalled, never dropped. When the FTQ cannot accept the uBTB
output, the uBTB holds its output stable.

**Update enqueue.** The FTQ presents `upd_val` and `upd_inp` per
channel. The update queue asserts `upd_rdy` when it accepts. When the
queue is full, `upd_rdy` deasserts and the FTQ holds valid until
accepted. An update is stalled, never dropped.

**Prediction delivery.** The FTQ presents `consumer_ready`; the
predictor presents `pred_rdy` when its result is valid. The TAGE result
is consumed by both the FTQ and the SC.

A prediction may be granted ahead of a pending update to the same RAM
entry, and reads pre-update state. The prediction accuracy loss from
the stale read is accepted.

---

## 9. RAS

Only the FTQ-facing behavior is stated here. RAS internals are in
`ras_decisions.md`.

The RAS is register-file based. It has no prediction queue, no update
queue, and no arbiter.

```
  p1   top-of-stack presented as the predicted target for a return
       (section 2.2)
  p2   push or pop executes once the FTB branch type confirms call or
       return. Participates in the p2 redirect.
```

`bp_ras_snapshot_t` is checkpointed into the FTQ entry at the time of
the prediction that consumed or produced the RAS state. On mispredict
or flush the RAS is restored from the snapshot of the last known-good
entry. The RAS update mechanism is snapshot-based.

RAS flush behavior is open; see TD #96.

---

## 10. Prediction Slots

`NUM_PRED_SLOTS` parameterizes the number of prediction slots and the
number of update channels, `upd_ch[0]` through
`upd_ch[NUM_PRED_SLOTS-1]`.

Two prediction slots per fetch bundle allow a taken branch in the
middle of a bundle to also predict the branch at its predicted target.

Each prediction slot consumes one FTQ entry.

`dual_pred_en` is a signal. When clear it gates the second prediction
slot off at runtime. Its only purpose is debug. It does not change the
structure: the slots and the channels exist either way.

Speculative history writes are one per active prediction slot, in
priority order.

---

## 11. Invariants

Proposed numbering. Stated here for the first time; not carried from
`bp_cluster.md` or `bp_arb_spec.md`.

```
  FE-1   The FTQ allocates an entry and issues a fetch from the p1
         prediction. It never waits for a predictor later than p1.

  FE-2   The initial prediction is formed by selection at p1 between
         the LP and the uBTB. Every correction after p1 is a redirect
         naming an FTQ entry index.

  FE-3   A redirect from a later stage supersedes an earlier redirect
         for the same FTQ entry index. The later stage wins by stage
         order. The FTQ does not compare targets to settle it.

  FE-4   The redirect comparison is made at the cluster boundary,
         between a predictor's stage output and the entry the FTQ
         holds. No predictor is compared against another predictor.

  FE-5   No prediction and no update is dropped. A full prediction
         path stalls fetch. A full update queue stalls the update
         path.

  FE-6   Updates reach a predictor in resolution order. The update
         queue is a FIFO and is not reordered.

  FE-7   The FTQ history checkpoints are pointer-only.

  FE-8   The update path uses metadata generated during predict. The
         set of predictors updated is determined by br_type.

  FE-9   A prediction granted ahead of a pending update to the same
         RAM entry reads pre-update state. The prediction accuracy
         loss from the stale read is accepted.
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

---

## 13. Technical Debt

```
  TD-FE-1  The IFU interface is unspecified. When the IFU
           specification is written, part of this debt is to update
           this document with the reference.

  TD-FE-2  bp_ftq_meta_t field overloading by branch type is not
           settled. TAGE and ITTAGE share index fields. The scheme is
           deferred to implementation.

  TD-FE-3  bp_ftq_entry_t.pc and .target are 40 bits. RVA23 mandates
           the C extension, so bit 0 of an instruction address is
           always zero and 39 bits suffice. If a fetch block always
           begins on an FTB_BLOCK_BYTES boundary, pc needs 35. Held
           at 40 until the design is working; revisit at the
           optimization step, together with the width of
           <pred>_redir_tgt_<pN>, which carries the same quantity.
           To be merged into the project tech debt list.

  TD-FE-4  bp_ftq_entry_t.pred_src has no functional consumer. Update
           fan-out is determined by br_type (section 7.2); redirect
           supersession is by stage (section 3.4); each predictor
           derives its own training decision from its bp_ftq_meta_t
           slice. The field is retained for diagnostic attribution of
           which predictor supplied the fetched prediction, and for
           performance counters. Nothing functional reads it.

           Removal requires cleanup outside this document:
           bp_cluster.md, FTQ Entry Split, lists pred_src as "which
           predictor won" with no consumer; bp_structs_pkg.sv carries
           the field and its encoding in bp_ftq_entry_t. Remove the
           field and its enum when both are updated.

           To be merged into the project tech debt list.
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

  FE-U3  bp_ftq_entry_t.confidence, 4 bits. bp_cluster.md marks the
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

  FE-U8  Fetch block to FTQ entry mapping. bp_ftq_entry_t carries one
         target, one taken, and one br_type, so it represents exactly
         one predicted branch. The FTB entry carries br0, br1, and jmp
         for one fetch block. A fetch block containing two conditional
         branches has no representation in the FTQ entry as specified.
         This is independent of the prediction slot count: it is a
         property of one block, not of two.
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
```
