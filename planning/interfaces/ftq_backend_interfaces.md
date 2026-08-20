<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Backend to FTQ Interface
```
 FILE:    ftq_backend_interfaces.md
 SOURCE:  ftq_decisions.md, ftq_entry_formats.md, fe_decisions.md 7,
          ras_decisions.md 3.3 and 4.5, bp_structs_pkg.sv
 STATUS:  DRAFT
 UPDATED: 2026-08-19
 CONTACT: Jeff Nye
```

The third of the FTQ's four interfaces, and the last carrying real
traffic. Every port here is NEW.

NOTHING IN THE BACKEND EXISTS. `docs/backend/` is four-line stubs,
`rtl/core/dispatch/*/rtl` holds no SystemVerilog, and no planning
document describes the ROB, the branch units or the commit path. Every
backend-side property this file relies on is therefore an ASSUMPTION,
collected in section 10 rather than scattered through the text. When
the backend is specified, check that list first.

---

## 1. Scope

Covered, all inbound:
- branch resolution, post-execute
- redirect and flush, from a mispredict or a trap
- commit, which frees entries and advances the RAS commit stack

Not covered:
- the ROB, the branch units, the trap path
- what the FTQ does with a resolution once it has it; that is
  `fe_decisions.md` 7.2 and `ftq_entry_formats.md` 3.1
- instruction delivery to the backend, which is IFU to IBuffer and
  never returns through the FTQ

---

## 2. Naming

```
  bkend_ftq_<signal>    backend -> FTQ
  ftq_bkend_<signal>    FTQ -> backend
```

No stage suffixes. The backend pipeline is not defined.

---

## 3. Three events, not one

The backend tells the FTQ three different things at three different
times, and they must not be collapsed:

```
  RESOLVE   a branch executed. Forms predictor updates. Does NOT
            free the entry and does NOT redirect by itself.
  REDIRECT  the fetch stream is wrong from some point on. Squashes
            entries, restores history and RAS, restarts fetch.
  COMMIT    an entry is architecturally retired. Frees it and
            advances the RAS commit stack.
```

`fe_decisions.md` 7.1 is explicit that updates trigger at post-execute
resolution and do NOT wait for retirement, so RESOLVE and COMMIT are
genuinely separate and can be many cycles apart. A mispredicting
branch RESOLVEs, REDIRECTs, and later COMMITs: three events, one
branch.

---

## 4. Resolution

```
  bkend_ftq_rsv_val   [NUM_RESOLVE_PORTS-1:0]              NEW
  bkend_ftq_rsv       ftq_resolve_t
                        [0:NUM_RESOLVE_PORTS-1]            NEW
  ftq_bkend_rsv_rdy   [NUM_RESOLVE_PORTS-1:0]              NEW
```

```
  typedef struct packed {
    logic [FTQ_IDX_BITS-1:0]    ftq_idx;   // entry that fetched it
    logic [FTB_BR_POS_BITS-1:0] pos;       // in-block position
    logic                       taken;     // resolved direction
    logic [VA_WIDTH-1:0]        target;    // resolved target
    bp_br_type_e                br_type;   // resolved type
    logic                       mispredict;
  } ftq_resolve_t;
```

THE BACKEND NAMES A POSITION, NOT A SLOT. Prediction slots are a
predictor concept: they are the two branch fields of one FTB block
(FE-10), and nothing outside the BPU and the FTQ has any reason to
know which field a branch landed in. The backend knows the FTQ index
and the in-block position because both travelled with the instruction
from the IFU (assumption A1, confirmed). The FTQ maps position to slot
by matching `pos` against the two `bp_ftq_slot_t.pos` fields of the
entry.

The slot array is program-ordered as of IC-FTB-16, so the mapping is
monotone: the lower position is slot 0. That is a property worth
having, but it does NOT let the backend carry a slot id instead. The
IFU tags each instruction from its own predecode, and predecode yields
a position; slot membership is FTB field bookkeeping the IFU does not
hold. Tagging with a slot would mean exporting the entry's
slot-to-position map into the IFU.

The mapping is EXACT. Positions are unique within an entry:
FTB_BR_POS_BITS is 4, giving one position per 2-byte slot, so no two
branches in a block can share one. It was ambiguous until 2026-08-19,
when the field was 3 bits and two RVC branches in one aligned word
collided onto a single slot.

`bp_update_t` is unchanged. It is arrayed `[NUM_PRED_SLOTS-1:0]` and
the slot IS the array index, so once the FTQ has resolved position to
slot it writes the matching element. `ftq_resolve_t` exists because
`bp_update_t` has no position field and cannot acquire one without
breaking FE-10.

NUM_RESOLVE_PORTS = NUM_PRED_SLOTS = 2. Not because two branches
resolve per cycle in the backend -- unknown, assumption A3 -- but
because the downstream capacity is two: `fe_decisions.md` 7.3 gives
each predictor's update queue two write ports serving the two update
channels. A third resolution in one cycle could not be forwarded, so
it would have to be queued in the FTQ. If the backend turns out to
have more than two branch units, add the queue and revisit; do not
widen this port and leave the queues behind it at two.

`ftq_bkend_rsv_rdy` is per port. The FTQ deasserts it when it cannot
accept, which is when the predictor update queues are full and FE-5
requires the update path to stall rather than drop. The backend holds
valid until accepted. A resolution is never dropped for capacity.

One qualification, FE-5a: a LOW-value FTB update -- predict-time hit,
correctly predicted -- may be dropped on collision rather than
stalling this port. Allocations and mispredict corrections are never
dropped and do stall it. ftq_decisions.md 5.7.

A resolution IS dropped, silently and correctly, when its entry has
been squashed; see section 7 rule R3.

---

## 5. Redirect

```
  bkend_ftq_redir_val                                      NEW
  bkend_ftq_redir_idx    [FTQ_IDX_BITS-1:0]                NEW
  bkend_ftq_redir_pos    [FTB_BR_POS_BITS-1:0]             NEW
  bkend_ftq_redir_pc     [VA_WIDTH-1:0]                    NEW
  bkend_ftq_redir_self                                     NEW
  bkend_ftq_redir_cause  ftq_redir_cause_e                 NEW
```

```
  typedef enum logic [1:0] {
    RC_MISPREDICT = 2'b00, // branch resolved against prediction
    RC_TRAP       = 2'b01, // exception or interrupt
    RC_REPLAY     = 2'b10, // pipeline replay, memory ordering
    RC_RESERVED   = 2'b11
  } ftq_redir_cause_e;
```

`bkend_ftq_redir_pc` IS THE NEXT FETCH ADDRESS, not a branch target.
For RC_MISPREDICT it is the resolved target or the fall-through. For
RC_TRAP it is the trap vector, which belongs to no FTQ entry and
cannot be derived from one. Carrying an address rather than a
"correct the entry and re-derive" instruction is what lets one group
serve all three causes.

`bkend_ftq_redir_self` distinguishes the two flush levels. Clear
means the naming instruction completed and everything after it is
squashed, which is the mispredict case. Set means the naming
instruction is squashed too, which is the trap case.

`bkend_ftq_redir_idx` and `_pos` locate the boundary. The FTQ
squashes every entry after that index, and the entry itself when
`_self` is set.

The FTQ's response:

```
  D1  restore the history pointers from the checkpoint held in the
      entry named by _idx (ftq_decisions.md 3.2), and drive the
      bp_cluster rollback input. THAT INPUT DOES NOT EXIST; see
      section 8, TD-FE-7.
  D2  restore the RAS from bp_ras_snapshot_t in that entry, on
      ras_restore_val / ras_restore_snapshot, which do exist.
  D3  on RC_TRAP, additionally drive the RAS flush group
      ras_flush_val / ras_flush_snapshot. Those ports exist,
      pass straight through bp_cluster, and have never been
      exercised. Behaviour is TD#96 / G24 and is NOT settled here.
  D4  free every squashed entry and restart allocation at the
      corrected stream.
  D5  drive the IFU flush group of ftq_ifu_interfaces.md 5.
```

The history restore is the same on all three causes. A trap does not
un-execute the branches that already resolved in the naming block, so
the checkpoint of the entry being corrected is the right state to
resume from, and the trap vector is then fetched against it.

A backend redirect OUTRANKS every BPU-derived redirect and the
predecode redirect, unconditionally and without comparison. Those are
speculative corrections; this is architectural fact. This is the one
place the stage-order rule of FE-3 does not decide the winner, and it
is why the backend group is separate rather than folded into
`bp_redirect_t`.

---

## 6. Commit

```
  bkend_ftq_commit_val                                     NEW
  bkend_ftq_commit_idx   [FTQ_IDX_BITS-1:0]                NEW
```

`bkend_ftq_commit_idx` is a WATERMARK: the newest FTQ entry all of
whose instructions have architecturally retired. The FTQ frees every
entry from its deallocation pointer through that index inclusive.

A watermark rather than a count or a per-entry pulse. The backend
retires up to eight instructions per cycle and those may span several
FTQ entries or none, so a count would need a width nobody has chosen
and a pulse would need a rate nobody has bounded. A watermark is
idempotent: repeating it is harmless, and a cycle in which it does
not advance costs nothing.

COMMIT IS RATE LIMITED BY THE RAS, not by the FTQ. `ras_decisions.md`
211 requires that when a call-containing block commits, the return
address is pushed onto the commit stack, and 4.5 requires BOS to
advance to that entry's post-op TOSR. The `ras_commit_*` group on
bp_cluster is SCALAR: one commit operation per cycle, no slot
dimension. So if the watermark jumps by more than one entry, the FTQ
must walk the intervening entries one per cycle to issue their RAS
commits.

That walk is bounded and safe. FE-11 guarantees at most one RAS
operation per entry, so one entry per cycle is one RAS commit per
cycle, exactly the port's capacity. Freeing an entry may run ahead of
its RAS commit; the RAS commit backlog is what the walk drains. The
FTQ needs a commit-walk pointer distinct from both the allocation and
the deallocation pointer.

`ras_decisions.md` 4.5 also rules that a mispredict restore in the
same cycle wins over commit for BOS: restore > commit > hold. The FTQ
must therefore suppress the RAS commit it would have issued in a
cycle where section 5 D2 fires.

---

## 7. Interaction rules

```
  R1  Priority in one cycle: REDIRECT first, then COMMIT, then
      RESOLVE. A redirect squashes entries a resolution in the same
      cycle may name; applying the resolution first would train a
      predictor on a squashed path.

  R2  A commit can never name an entry a redirect squashes. Commit
      is architectural and squashed entries are speculative. If both
      arrive naming overlapping entries, the backend is broken; the
      FTQ does not arbitrate it.

  R3  A resolution naming an entry that has been squashed, or an
      entry whose allocation generation does not match, is DROPPED
      silently. This is normal traffic, not an error: a branch in
      flight when an older branch redirects will resolve after the
      squash. The generation bit is FE-U7 work, section 9.

  R4  Resolutions are enqueued to the predictors in the order they
      arrive, not in program order. FE-6: this is an out-of-order
      machine, the update queue is a FIFO and is not reordered.

  R5  A resolution does not free its entry and does not redirect.
      Only COMMIT frees; only REDIRECT squashes.
```

---

## 8. What bp_cluster still lacks -- TD-FE-7

`bp_cluster.sv` lines 944-945 derive the bp_history rollback entirely
from its OWN p2 and p3 redirects:

```
  assign w_rollback_valid    = w_any_redir_p2 | w_any_redir_p3;
  assign w_rollback_ckpt_idx = w_any_redir_p3 ? r_idx_p3 : r_idx_p2;
```

There is no input port by which the FTQ can request a rollback. So
section 5 D1 cannot be built: a backend mispredict can restore the
RAS, because `ras_restore_val` is an input, but CANNOT restore the
GHR and PHR pointers. Every branch predicted after a backend
mispredict would index on history from the squashed path.

The fix is two input ports, `ftq_rollback_val` and
`ftq_rollback_idx`, ORed into the existing rollback with priority
over the cluster's own: an architectural correction outranks a
speculative one. Recorded as TD-FE-7 in `fe_decisions.md` 13.

This is the same class of defect as TD-FE-6 and was found the same
way, by writing down what the FTQ would have to drive.

---

## 9. What this makes decidable

Not decided here. Listed because this interface is the last input
they were waiting on.

```
  FE-U7  Allocation and deallocation policy. All three pointers now
         have a defined source: allocation advances on the p1
         prediction, deallocation follows bkend_ftq_commit_idx, and
         the commit walk of section 6 sits between them. Full is
         allocation catching deallocation. A generation or wrap bit
         is required by rule R3.
  G23    Checkpoint slot reclaim. The checkpoint lives in the entry,
         so it is reclaimed with the entry at commit.
  G9     FTB update arbitration. Two resolution ports feed one FTB
         update port with no slot dimension. The FTQ needs the
         scheduler; this interface fixes its input rate at two.
  FE-U2  Flush handling. Section 5 is the answer for the FTQ side.
         The RAS flush behaviour behind D3 remains TD#96.
```

---

## 10. Assumptions about the backend

Every one of these is unverifiable today. The backend does not exist.

```
  A1  CONFIRMED 2026-08-19. Instructions carry their FTQ index and
      in-block position from the IFU through to resolution and
      retirement: FTQ_IDX_BITS + FTB_BR_POS_BITS = 9 bits per
      in-flight instruction. Section 4 and section 6 both depend on
      it. XiangShan does the same (ftqPtr and ftqOffset in
      FetchToIBuffer).
  A2  Retirement is in order, so a commit watermark is meaningful.
  A3  At most two branches resolve per cycle. Section 4 sizes the
      port group to the downstream update capacity, not to a known
      backend width.
  A4  The backend can hold a resolution when ftq_bkend_rsv_rdy is
      low. If it cannot, the FTQ needs a resolution buffer and
      FE-5 has to be restated.
  A5  Exactly one redirect is presented per cycle, already
      prioritised by the backend across its own sources. The FTQ
      does not arbitrate between backend redirects.
  A6  The trap vector is supplied by the backend on
      bkend_ftq_redir_pc. The FTQ reads no CSR.
```

---

## 11. Departures from the XiangShan contract

```
  one redirect port   XiangShan carries redirect and
                      topdown_redirect, structurally identical, the
                      second only for performance accounting.
                      Dropped, as in ftq_ifu_interfaces.md 9.

  cause encoding      KEPT and narrowed. XiangShan's redirect
                      carries a large CfiUpdateInfo bundle. Here the
                      FTQ already holds the prediction, so the
                      redirect carries only what the FTQ cannot
                      know: where the stream went wrong, where it
                      resumes, and why.

  commit watermark    XiangShan advances a commit pointer from the
                      ROB. Same model, stated as an idempotent
                      index rather than a pointer increment.
```

---

## 12. Document History

```
  2026-08-19  Created. Resolution, redirect and commit defined as
              three separate events. Resolution names an in-block
              POSITION, not a prediction slot, so the backend needs
              no knowledge of the slot model; the FTQ maps position
              to slot. Port count set by the downstream update
              capacity of two, not by an unknown backend width.
              Commit is an idempotent watermark, rate limited by
              the scalar RAS commit port to one entry per cycle.
              TD-FE-7 opened: bp_cluster derives its history
              rollback only from its own p2/p3 redirects and has no
              input, so a backend mispredict cannot restore the GHR
              and PHR pointers. Six backend assumptions recorded in
              section 10; none is verifiable, the backend does not
              exist.

  2026-08-19  A1 CONFIRMED: 9 bits per in-flight instruction.
              Section 4 records that the position-to-slot mapping is
              monotone under IC-FTB-16, that a slot id still cannot
              replace the position because the IFU holds no slot
              map, and that the mapping is exact only while positions
              are unique -- which they are not at
              FTB_BR_POS_BITS = 3.

  2026-08-19  FTB_BR_POS_BITS widened to 4. The section 4
              position-to-slot mapping is now EXACT: one position
              per 2-byte slot, so no two branches in a block can
              share one. The caveat added earlier the same day is
              retired.
```
