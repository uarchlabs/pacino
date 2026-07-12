```
 FILE:    resume_20260708.md
 SOURCE:  session capture
 STATUS:  DRAFT
 UPDATED: 2026-07-08
 CONTACT: Jeff Nye
```

# Session capture: XiangShan FTB / BPU pipeline, and Pacino decisions

Scope: BPU->FTQ staged prediction response, the enq_ptr mechanism, FTB
read timing, the FTB update read-modify-write, predictor training timing
(resolution vs commit), and the Pacino decisions taken at the end of the
session.

Source references are XiangShan Kunminghu local copies under
./ia_xiangshan/. File:line citations are to the Scala/Chisel unless
noted.

---

## 1. Staged prediction response s1/s2/s3 is an override pipeline

branch_prediction_resp_t (BranchPredictionResp) is the BPU->FTQ payload.
It carries s1, s2, s3. These are three pipeline taps of the predictor,
each holding a different in-flight fetch block, not three views of one
block.

- s1 holds block A     (1-cycle predictors: uBTB, loop predictor)
- s2 holds block A-1   (2-cycle predictors: FTB, TAGE)
- s3 holds block A-2   (3-cycle predictors: SC)

s2_pc = s1_pc registered one cycle; s3_pc = s2_pc registered one cycle
(BPU.scala:296-297).

The BPU does not wait for all three stages. resp.valid asserts in three
independent cases (BPU.scala:444-447):

```
  resp.valid =
      s1_valid && s2_components_ready && s2_ready   // s1 enqueue
   || s2_fire  && s2_redirect                       // s2 override
   || s3_fire  && s3_redirect                       // s3 override
```

- s1 enqueue: the fast-path prediction is sent when the 1-cycle
  predictors produce it.
- s2 override: sent only when s2 disagrees with s1 (s2_redirect ->
  hasRedirect).
- s3 override: sent only when s3 disagrees with s2.

A later stage that agrees does not re-assert resp.valid for that block.
A correct fast-path prediction is enqueued at s1 and not re-sent. s2/s3
consume channel bandwidth only when they correct a younger prediction.

FTQ consumption. The FTQ selects the most-advanced stage that redirects,
priority s3 > s2 > s1 (FrontendBundle.scala:717-731):

```
  selectedRespIdxForFtq = PriorityMux(
    s3.valid && s3.hasRedirect -> BP_S3,
    s2.valid && s2.hasRedirect -> BP_S2,
    s1.valid                   -> BP_S1)
```

- On s1: allocate a new FTQ entry at bpuPtr, write it, increment bpuPtr
  (NewFtq.scala:569, 574, 695).
- On s2/s3 override: rewrite the already-allocated entry in place at the
  stage ftq_idx (NewFtq.scala:570, 574). The BPU flushes the younger
  in-flight stages (BPU.scala:383-387) and resteers s0_pc from
  s2_target / s3_target.

Training payload is a single s3 copy: last_stage_meta,
last_stage_ftb_entry, last_stage_spec_info are written when s3 is valid
(NewFtq.scala:588-604). The response has three prediction structs but one
meta / ftb_entry set.

---

## 2. How the BPU obtains the FTQ enqueue index

bpuPtr is owned by the FTQ (NewFtq.scala:524) and incremented on
enqueue (NewFtq.scala:695). It is driven to the BPU on a separate
FTQ->BPU port, enq_ptr, a member of FtqToBpuIO, not part of the resp
bundle:

```
  io.toBpu.enq_ptr := bpuPtr                         // NewFtq.scala:568
```

The BPU snapshots enq_ptr at s1_fire and pipelines it to tag its
later-stage overrides:

```
  s2_ftq_idx = RegEnable(io.ftq_to_bpu.enq_ptr, s1_fire)  // BPU.scala:747
  s3_ftq_idx = RegEnable(s2_ftq_idx,            s2_fire)  // BPU.scala:748
  s1.ftq_idx = DontCare                                    // BPU.scala:754
  s2.ftq_idx = s2_ftq_idx                                  // BPU.scala:759
  s3.ftq_idx = s3_ftq_idx                                  // BPU.scala:764
```

s1 needs no index. At s1 the FTQ enqueues the same cycle using its own
live bpuPtr: bpu_in_resp_ptr = Mux(stage===BP_S1, bpuPtr,
bpu_in_resp.ftq_idx) (NewFtq.scala:574). s2/s3 fire one and two cycles
later when bpuPtr has advanced, so they must carry the snapshot back.

On an s2/s3 override the FTQ rewinds its pointer past the corrected
block: bpuPtr := bpu_s2_resp.ftq_idx + 1 / + 1 for s3 (NewFtq.scala:718,
737), discarding younger wrong-path entries.

The FTB entry does not store an FTQ index. The index comes from bpuPtr
(s1) or the pipelined snapshot (s2/s3).

enq_ptr precise statement: enq_ptr is an input port to the BPU carrying
bpuPtr, the next available FTQ index. Its functional use is to supply the
slot id the BPU stamps onto its s2/s3 overrides.

---

## 3. s2_ftq_idx / s3_ftq_idx staging

s2_ftq_idx and s3_ftq_idx are enable-gated flops (RegEnable), not
free-running flops. The enable is the stage-advance fire signal. Capture
instant is s1_fire (enq_ptr sampled), then re-staged on s2_fire. See
BPU.scala:747-748.

---

## 4. Stage fire signals

Effective equations from BPU.scala:390-441.

- s0_fire (BPU.scala:394) = s1_components_ready && s1_ready. Launches the
  lookup at s0_pc.
- s1_fire (BPU.scala:401) = s1_valid && s2_components_ready && s2_ready
  && resp.ready. Advances s1->s2. This is the backpressure gate:
  FTQ resp.ready plus s2-stage readiness.
- s2_fire: assigned at :407 = s2_valid && s3_components_ready &&
  s3_ready, then reconnected at :417 to s2_fire := s2_valid. Chisel
  last-connect wins, so effectively s2_fire = s2_valid.
- s3_fire (BPU.scala:430) = s3_valid. Fed to predictors.io.s3_fire
  (:440).

predictors.io.s2_ready and s3_ready are tied true.B, so s2/s3 do not
stall on the predictors. The only backpressure point is s1_fire on
resp.ready. s2 and s3 run one and two cycles behind s1.

---

## 5. s1_components_ready

s1_components_ready = predictors.io.s1_ready = AND-reduce of every
component io.s1_ready (Composer.scala:68,70). It is a per-cycle read-port
/ flow ready, not a dedicated post-init strobe. It deasserts in two
situations:

- During SRAM reset-init. TAGE table has a reset FSM doing_reset
  (Tage.scala:169-172) driving io.req.ready := !doing_reset (:175), which
  feeds io.s1_ready (:849). While the RAMs clear, s1_ready is low and
  s0_fire cannot launch.
- On runtime read-port conflicts. FTB: io.s1_ready := ftbBank.io
  .req_pc.ready && !update_need_read && !RegNext(update_need_read)
  (FTB.scala:766). Deasserts when an update steals the read port.

Base predictor and predictors without such a stall tie it true.B
(BPU.scala:193; ITTAGE.scala:347; Tage.scala:540). It gates predictions
until the RAMs finish init, and also stalls s1 on read-port contention
during normal operation. It is a superset of an init-done signal.

---

## 6. FTB read timing

The FTB bank array read is single-cycle synchronous SRAM. Request issued
at s0 (ftbBank.io.req_pc.valid := io.s0_fire(0) && !s0_close_ftb_req,
FTB.scala:636), read data at s1.

The FTB predictor pipeline spans s1->s2 with an s3 fixup:

- s1: tag compare and hit computed off the s1 read data, qualified by
  io.s1_fire (FTB.scala:506, 659).
- s2: result registered on s1_fire and consumed here (FTB.scala:649,
  660, 669). The main FTB contributes its prediction / s2 override at s2.
- s3: multi-hit correction registered on s2_fire (FTB.scala:655, 666).

The main FTB is a 2-cycle predictor (request s0 -> read/hit s1 ->
prediction s2). The single-cycle predictor is the FauFTB (uFTB), which
produces the s1 prediction; the main FTB refines it at s2. The
s*_close_ftb_req logic (FTB.scala:628-630, 648) closes the main FTB read
and uses the s1 uFTB entry when the two have been consistent, to save
power.

---

## 7. FTB update read-modify-write

FTB bank is a single-port SRAM: SRAMTemplate(..., singlePort = true)
(FTB.scala:486). One shared address port serves read and write; they
cannot both occur in a cycle. Prediction read (io.req_pc) and update read
(io.u_req_pc) drive the same ftb.io.r.req (FTB.scala:490-491) and are
asserted mutually exclusive (:493).

An update writes: ftb.io.w driven by io.update_write_data, gated by
u_valid, at u_idx / u_way (FTB.scala:602-620).

An update also reads, because the write is read-modify-write for way
selection. The update read (update_access, io.u_req_pc) produces:

- u_hit / u_hit_way from re-comparing current tags (FTB.scala:538-541,
  out on io.update_hits): presence and location re-check.
- allocWriteWay from current valids / replacer (FTB.scala:582):
  allocation victim.

What XiangShan pre-calculates at prediction time and carries in meta:

- writeWay and hit in FTBMeta (FTB.scala:669), carried in
  last_stage_meta.
- The old entry (last_stage_ftb_entry), used by FTBEntryGen for the data
  merge.
- On a hit-update the write uses the captured way directly: u_way =
  Mux(update_write_alloc, allocWriteWay, io.update_write_way)
  (FTB.scala:606). The read does not supply the hit-update write way.

What XiangShan does NOT pre-calculate, which is why the update read
remains:

- The allocation victim way (allocWriteWay). Chosen at update time from
  current set state. Needed when the update allocates a new entry.
- A current presence / staleness verdict (u_hit / u_hit_way). The set can
  change between predict and commit, so the entry location is re-checked.

Port impact: eliminating the update read removes the update_need_read
term that deasserts io.s1_ready (FTB.scala:766). The update write still
contends for the single port, so the read removal reduces update
occupancy from read+write to write, it does not free the port.

---

## 8. Predictor training timing: resolution vs commit

Two distinct feedback events at different times:

- Redirect at resolution (execute). The branch functional unit computes
  taken/target, flushes wrong path, resteers s0_pc.
- Update (training of FTB, TAGE/SC counters) at commit/retire in
  XiangShan.

Definitions. Commit = in-order architectural retirement from the ROB,
non-speculative. Resolved = outcome known at execute, still speculative.

XiangShan reasons for deferring table training to commit:
- A branch resolved at execute can be squashed by an older mispredict,
  exception, or interrupt and never retire. Training on a non-retiring
  outcome pollutes the tables.
- History and counter updates want in-program-order final outcomes.

State needed at prediction time (folded global history, RAS speculative
pointers) is updated speculatively and repaired on redirect via
spec_info / cfiUpdate. Only the persistent SRAM tables (FTB, TAGE/SC) are
trained at commit.

Discussion outcome:
- The wrong-path-squash argument is the minor factor.
- Deferring to commit avoids adding recovery hardware for speculative
  table writes. That recovery does not require full array rollback; it
  requires undoing only wrong-path writes to the predictor counter SRAM
  entries (TAGE/SC counter and useful-bit fields at the {table, set
  index, way} locations touched by wrong-path branches). The mechanism is
  a walk-back log sized O(in-flight branch count), plus old-value capture
  (a read-before-write) and coalescing for multiple in-flight updates to
  the same entry.
- An alternative avoids the walk-back log entirely: checkpoint and
  restore only the history, allow the counter tables to absorb wrong-path
  writes, and accept bounded divergence. Multi-bit hysteretic counters
  dilute and overwrite stray wrong-path updates; wrong-path writes are a
  minority of updates. No evidence was presented that this approach is
  ineffective. General branch-prediction literature direction is that
  wrong-path effects on table state are small to neutral (stated as
  direction, not a specific citation).

---

## 9. Precompute victim way: analysis

Precomputing the allocation victim at prediction time is feasible: the
prediction already reads the set, so valids and replacer state are
available that cycle. Compute allocWriteWay there, carry it in meta with
writeWay/hit. The update then becomes write-only for the common path.

Impacts, ordered:

1. Inter-block set aliasing. Multiple in-flight fetch blocks can map to
   the same FTB set and each captures a victim from the state it saw. Two
   can pick the same way and collide at update, one clobbering the other.
   This scales with same-set blocks concurrently in flight (FTQ depth,
   fetch width), not with predict->update latency. Shortening the window
   does not reduce it.
2. Stale victim quality. Replacer state read at prediction is older than
   at update; the victim may not be current LRU. Quality loss, not a
   correctness bug, provided a valid way is written.
3. Stale hit/way. Captured hit/writeWay can be wrong if the entry was
   evicted or reallocated in the window. Affects hit-update target and
   alloc-vs-hit decision. Short window reduces frequency.

Resolution-time update shrinks impacts 2 and 3 (shorter window than
commit drain). Impact 1 is structural and remains.

Unmitigated behavior is self-healing: a wrong-way or clobbered
allocation is re-allocated and re-trained on the next miss. No
correctness violation while every write targets a valid way.

Complexity accounting. Two separate savings:
- Area/complexity: removing the update-read logic (way-select/hit
  compare, read-port arbitration, s1_ready gating). Retaining any re-read
  fallback keeps this hardware; the precompute + meta carry + collision
  detector then add area.
- Throughput/port: not exercising the update read on the common path.
  Survives a rarely-firing fallback.

To realize the area saving the update path must be fully read-free: no
fallback, accept unmitigated aliasing and stale-way writes as
self-healing. If a re-read fallback is retained, the RMW logic still
exists and the area saving is lost.

Single-port constraint caps the benefit: a write-only update still needs
the one port, so it contends with the prediction read regardless of
update timing. The lever that removes contention is the memory structure
(dual-port, or bank/partition so writes and reads hit different banks),
not update timing.

---

## 10. Pacino decisions taken this session

- Pacino updates predictor tables at resolution, not at commit. The
  predict->update window is therefore shorter than a commit-drain window,
  which reduces victim-way and hit/way staleness (impacts 2 and 3 in
  section 9).

- Pacino precalculates the FTB update information during the FTB access
  (prediction read) to eliminate the FTB read-modify-write. The
  allocation victim way and the way/hit information are captured at
  access time and carried to the update, so the update path does not
  re-read the FTB. This commits to the fully read-free update path in
  section 9: no re-read fallback, accept unmitigated inter-block set
  aliasing and stale-way writes as self-healing.

- Pacino schedules access to the single-port RAMs using the existing BPU
  arbitration specification. Prediction reads and update writes to the
  single-port FTB (and other single-port predictor RAMs) are ordered by
  the BPU arb rather than by an update-read RMW mechanism.

Consequences to carry forward:
- Inter-block set aliasing (section 9, impact 1) is structural and is not
  removed by resolution-time update. It must be handled by the BPU arb
  schedule or accepted as self-healing divergence.
- With the update read eliminated, the update_need_read term no longer
  gates s1_ready (section 5). The single-port write still contends with
  the prediction read; the BPU arb resolves that contention.

---

## Task items

- Define the BPU arb specification behavior for FTB write vs prediction
  read scheduling on the single-port RAM.

    - This does not need to be defined in this document, it is covered 
      in planning/arch bp_arb_spec.md

- Decide whether inter-block set aliasing is left self-healing or
  detected/serialized by the arb.

    - This was already decided. Not detected. Create the wording for a
      technical debit item for later analysis

- Widen the XiangShan numBr=2 structures to the Pacino 8-wide target
  (carried from resume.md).

    - CLOSED. this is a nonsense issue that got promoted unknowingly
      from a previous session. 

- Fold the cold-start writeups (fe.md section, cold_start.md, c.md) into
  one canonical document (carried from resume.md).

    - Task for this session

- Update references to use Pacino structs and defines. This information
  is in the supplied context

## Context to load

Load this context and review in detail. Each file has an intro section
which summarizes the contents and/or purpose

@ia_context/c.md
@ia_context/cold_start.md
@ia_context/fe.md
@ia_context/fe_qaa.md
@ia_context/ifu_ftq.md
@planning/arch/bp_arb_spec.md
@rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
@rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
