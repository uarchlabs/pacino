<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTQ Micro-Architectural Decisions
```
 FILE:    ftq_decisions.md
 SOURCE:  fe_decisions.md sections 4.3, 5 and 6
 STATUS:  DRAFT
 UPDATED: 2026-08-19
 CONTACT: Jeff Nye
```

FTQ-owned behaviour: how the entry is stored, how long it lives, and
what it holds for restore.

---

## 0. Scope and companion documents

```
  ftq_entry_formats.md      the two entry structures, field by field
  ftq_bpu_interfaces.md     the ports crossing the BPU boundary
  ftq_ifu_interfaces.md     the ports crossing the IFU boundary
  ftq_backend_interfaces.md the ports crossing the backend boundary
  fe_decisions.md           the BPU <-> FTQ paths: prediction,
                            redirect, slot correction, update
  bp_structs_pkg.sv         the reference declaration
```

Registries stay in `fe_decisions.md` and are NOT duplicated here.
Front-end invariants are FE-1 through FE-14, technical debt is
TD-FE-1 through TD-FE-8, and open items are FE-U1 through FE-U9, all
in `fe_decisions.md` sections 11, 13 and 14. This file cites them by
number.

The FTQ has three logical external interfaces, all specified:

```
  ftq_bpu       BOTH   specified, ftq_bpu_interfaces.md
  ftq_ifu       BOTH   specified, ftq_ifu_interfaces.md (TD-FE-1)
  ftq_backend   IN     specified, ftq_backend_interfaces.md:
                       resolution, redirect, commit
```

A fourth, ftq_icache, is DELIBERATELY NOT DEFINED. The ICache is
encapsulated behind the IFU. XiangShan drives it from its FTQ for
physical reasons -- critical path and register replication, with the
evidence cited in ftq_ifu_interfaces.md 8 item 1 -- and if pacino
meets the same pressure the answer is a pass-through or alternative
path created during physical design, not a logical interface carried
from the start.

---

## 1. Entry storage
`bp_ftq_entry_t` is read every cycle by fetch. The FTQ reads it again
on redirect, to rewrite the named slot, to re-derive the block
successor across the slots (fe_decisions.md 2.4), and to present
the checkpoint and the RAS snapshot of the entry being corrected
(section 3.2 and fe_decisions.md 9). It is read a third time at
resolution, for `pc` and the slot's `br_type` (fe_decisions.md 7.2).

NO PREDICTOR READS IT, and neither does bp_cluster. The redirect
comparison is made inside the cluster, against the prediction the
cluster formed at p1 and holds in its own stage registers (FE-4). A
prior revision of this section attributed a read to "every redirecting
predictor's cluster-boundary comparison". That read does not exist and
must not be counted when the fast-path read ports are sized.

`bp_ftq_meta_t` is read once, at resolution.

---

---

## 2. Entry Lifetime

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

---

## 3. Checkpoint and Restore

The BPU owns all branch history state. Only the FTQ-facing checkpoint 
and restore are specified here; internal history management is out of scope.

### 3.1 What is check-pointed

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
redirect (section 3.2):

```
  TOSR   top of stack read pointer
  TOSW   top of stack write pointer
  BOS    bottom of stack
```

### 3.2 Restore

On redirect the FTQ presents the INDEX of the entry being corrected,
on `ftq_rollback_val` / `ftq_rollback_idx`, and `bp_cluster` restores
`ghist_ptr` and `phist_ptr` from its own copy of that entry's
checkpoint.

THIS SECTION PREVIOUSLY SPECIFIED THE VALUE FORM -- the FTQ
presenting the two pointers themselves. BP-102 settled it as the
index form and this wording follows. The checkpoint array inside
bp_history and the checkpoint field of the FTQ entry are written from
the same p1 allocation and are one to one against an `FTQ_IDX_BITS`
index, so the index selects the same pointer pair at 7 bits rather
than 14, and bp_history needs no change. The entry still CARRIES the
pointer pair (section 2); nothing reads it across this interface.

The index names the entry whose END-of-block pointer state is to be
restored. On `RC_MISPREDICT` with `bkend_ftq_redir_self` clear that
is the redirecting entry itself; with `_self` set the naming entry is
squashed too and the index is the one before it. That derivation is
the FTQ's work -- `bp_cluster` applies the index it is given and does
not validate it.

The FTQ arm outranks both of the cluster's own redirect arms
unconditionally (`ftq_backend_interfaces.md` 8).

RAS restoration is `ras_decisions.md` 4.3 and 4.4, and
`fe_decisions.md` 9. It is the same pointer restore on every
redirect cause and needs nothing from this section.

---

---

## 4. Next fetch PC

THE FTQ IS THE REQUESTER. `bp_cluster` takes `ftq_pred_pc_p0` as an
INPUT and does not self-steer. `PROJECT_STATUS.md` said the opposite
until 2026-08-19; that describes the XiangShan model, where the BPU
holds its own PC and the FTQ supplies only ready and redirect
(`ia_context/background/fe_qaa.md`). Pacino inverted it. The port
direction settles it, and this section is the selection the
inversion makes the FTQ responsible for.

### 4.1 The register

One register and its valid, driving the section 3 request group of
`ftq_bpu_interfaces.md` directly:

```
  r_next_pc   [VA_WIDTH-1:0]  ->  ftq_pred_pc_p0
  r_next_val                  ->  ftq_pred_val_p0
```

`ftq_pred_idx_p0` is the index the FTQ allocates for the request, not
part of this selection.

### 4.2 Selection

Priority, highest first:

```
  0  reset               the reset vector (4.6)
  1  backend redirect    bkend_ftq_redir_pc
  2  predecode redirect  derived from the IFU writeback,
                         ftq_ifu_interfaces.md 7 W3
  3  p3 redirect         bpu_redir_p3[s].target_pc
  4  p2 redirect         bpu_redir_p2[s].target_pc
  5  p1 successor        selection across slots, fe_decisions.md 2.4
  6  hold                retain r_next_pc, deassert r_next_val (4.5)
```

### 4.3 The priority is age order, not an axiom

The rule that matters is that THE CORRECTION NAMING THE OLDEST FTQ
ENTRY WINS, because everything younger than it is squashed by it
anyway. The fixed priority of 4.2 IS that order in a correctly
operating pipeline, so no wrap-aware age comparator is needed on this
path:

- Backend resolution is many stages behind fetch, so the entry it
  names is always older than any entry still inside the BPU or the
  IFU.
- Predecode follows fetch, which follows p1, so its entry is always
  older than the entry at p2 or p3.
- p3 lags p2 by one cycle, so in a moving stream p3 names the older
  entry. When the stream is stalled the two hold the same entry and
  FE-3 decides: the later stage wins. bp_cluster.sv line 945 already
  resolves the history rollback index exactly this way.

Stated as a consequence rather than an assumption so that a future
source which does NOT fit the depth ordering is recognised as such.
The fallback is the age comparison itself, and that needs the wrap or
generation bit FE-U7 must define.

### 4.4 The p1 successor and the zero-bubble loop

The p1 successor is the `fe_decisions.md` 2.4 selection: the first
taken slot's target, or the block fall-through
`bp_ftq_entry_t.pft_addr`, delivered at p1 on `bpu_pred_pft_p1`.

TIMING. To sustain one block per cycle with no bubble, the path from
the p1 group through this selection into `ftq_pred_pc_p0` must be
COMBINATIONAL: the request for the next block is presented in the
same cycle this block's prediction is formed. This is the critical
loop of the front end and the reason the uBTB exists --
`ftb_decisions.md` 1 names it the zero-bubble predictor that supplies
the fast next-PC. The FTB, TAGE, ITTAGE and SC results all arrive
later and correct by redirect; none of them is in this loop.

Redirect targets do NOT need the same treatment. A redirect has
already cost the cycles between the mispredicted block and the
correcting stage, so one register stage on the redirect path is off
the critical loop. Registering the redirect sources and leaving only
the p1 successor combinational is the expected implementation.

### 4.5 Hold conditions

`r_next_val` deasserts and `r_next_pc` holds when either:

```
  H1  a queued predictor cannot accept a request: any of
      tage_pq_not_full, ittage_pq_not_full or sc_uq_not_full low.
      The cluster has NO request-ready output, so
      ftq_bpu_interfaces.md 3 makes this the FTQ's obligation.
  H2  the FTQ has no free entry. FE-U7.
```

NOT a hold condition: `ftq_ifu_req_rdy` low. The IFU being unable to
accept a fetch does not stop the FTQ predicting ahead. That is the
point of a decoupled front end and the FTQ's depth is the decoupling
buffer; prediction rate and fetch rate are deliberately separate.
Only running out of entries, H2, couples them.

### 4.6 In-flight responses after a redirect

A redirect does not reach into the cluster. `bp_cluster` has no flush
input, so requests already at p0, p1, p2 and p3 for entries the
redirect squashed still complete and still present their results.

THE FTQ DROPS THEM. Every cluster response carries the entry index it
belongs to -- `bpu_pred_idx_p1`, `bpu_slot_idx_p2`, `bpu_slot_idx_p3`,
`bpu_redir_idx_p2`, `bpu_redir_idx_p3`, `bpu_meta_idx_p2`,
`bpu_meta_idx_p3` -- and the FTQ ignores any naming an entry it has
squashed. This is the same rule as `ftq_backend_interfaces.md` R3 and
it has the same prerequisite: the FE-U7 generation bit, so a
reallocated index is not mistaken for the squashed one.

### 4.7 Reset vector

`bp_defines_pkg::RESET_VECTOR`, a parameter, VA_WIDTH wide, default
`40'h00_8000_0000`. It initialises the next-PC register of 4.1 and is
selected by arm 0 of 4.2.

The privileged specification leaves the reset PC implementation
defined. 0x8000_0000 is the RISC-V convention for the base of main
memory and the target of the Spike boot ROM; the tree carries no
memory map of its own, so the convention stands. Override it at
elaboration for a different map.

It must be FTB_BLOCK_BYTES aligned. An unaligned value makes the
first fetch a partial block, and both the FTB and the uBTB index on
the block-aligned PC. 0x8000_0000 satisfies this and the parameter
comment records the requirement.

---

## 5. Queue management (FE-U7, resolved)

### 5.1 Three pointers

FTQ_DEPTH is 64 and FTQ_IDX_BITS is 6. Pointers are SEVEN bits: the
low six index the array, the top bit is the wrap generation.

```
  alloc_ptr    head.   Next entry to allocate. Advances when a
                       prediction request is accepted at p0.
  fetch_ptr    middle. Next entry to issue a fetch request for.
                       Advances on ftq_ifu_req_val & _rdy.
  commit_ptr   tail.   Next entry to commit and free. Advances at
                       most one entry per cycle; see 5.4.
```

INVARIANT FQ-1: commit_ptr <= fetch_ptr <= alloc_ptr, in wrap-aware
order. The gap between commit_ptr and fetch_ptr is the fetched but
unretired stream; the gap between fetch_ptr and alloc_ptr is the
PREDICTED BUT UNFETCHED run-ahead, and that gap is the decoupling the
FTQ exists to provide. At 64 entries of one 32-byte block it is at
most 2 KiB of instruction stream.

```
  empty   all three equal
  full    alloc_ptr[5:0] == commit_ptr[5:0]
          and alloc_ptr[6] != commit_ptr[6]
```

Full is hold condition H2 of section 4.5. It is the only condition
under which the FTQ stops predicting.

### 5.2 Allocation

The index is committed at p0, not at p1. `ftq_pred_idx_p0` leaves
with the request, so alloc_ptr must advance when the request is
accepted. The ENTRY CONTENT is written at p1 from the p1 group. One
p1 response is produced for every p0 request -- `bpu_pred_val_p1`
derives from the staged request valid -- so allocation cannot leak.

fe_decisions.md 2.3 says the FTQ allocates at p1. That describes the
entry write. The index is spoken for one cycle earlier.

Allocation is unconditional: an entry is allocated for every
prediction block, including one the p1 predictors miss, so a later
stage has an entry to correct (fe_decisions.md 2.3).

### 5.3 Deallocation

IN ORDER, tail first, one source only: commit. An entry is freed when
commit_ptr passes it.

A slot off the executed path never resolves (fe_decisions.md 7.2), so
resolution can never free an entry. Squashed entries are freed by the
REDIRECT that squashed them, by rewinding the head; see 5.5.

### 5.4 The commit walk

`bkend_ftq_commit_idx` is a watermark and may jump several entries at
once (ftq_backend_interfaces.md 6). commit_ptr advances toward it at
MOST ONE ENTRY PER CYCLE.

The limit is the RAS, not the FTQ. `ras_commit_val` and its payload
group are scalar on bp_cluster -- no slot dimension -- so one commit
operation per cycle is the port's capacity. FE-11 guarantees at most
one RAS operation per entry, so one entry per cycle is exactly one
RAS commit per cycle and the walk never falls behind what the port
can carry.

An entry cannot be freed before its RAS commit is issued: the commit
payload reads `bp_ras_snapshot_t` out of the entry. Commit and free
are therefore the same pointer, not two.

ras_decisions.md 4.5 rules restore > commit > hold for BOS, so the
FTQ SUPPRESSES the RAS commit it would have issued in a cycle where a
redirect restore fires. The walk does not advance that cycle.

### 5.5 Redirect rewind

On a redirect naming index K (ftq_backend_interfaces.md 5, or a BPU
or predecode redirect):

```
  R1  alloc_ptr rewinds to K, or K+1 when the naming entry itself
      survives. fetch_ptr rewinds with it, since FQ-1 forbids
      fetch_ptr running ahead of alloc_ptr.
  R2  commit_ptr NEVER rewinds. Committed is architectural. A
      redirect can only name an index at or after commit_ptr;
      ftq_backend_interfaces.md R2 makes that the backend's
      obligation and the FTQ does not arbitrate it.
  R3  the entries between the new alloc_ptr and the old one are
      free immediately. No walk, no commit.
```

### 5.6 Stale responses, and why the wrap bit is not carried

Section 4.6 requires the FTQ to drop cluster responses naming
squashed entries. The response indices -- `bpu_pred_idx_p1`,
`bpu_slot_idx_p2/p3`, `bpu_redir_idx_p2/p3`, `bpu_meta_idx_p2/p3` --
are FTQ_IDX_BITS wide and carry NO wrap bit. A rewind can therefore
re-allocate an index while a response for the squashed use of that
same index is still in flight, and the index alone cannot separate
them.

The FTQ keeps a four-deep IN-FLIGHT SHADOW of its own requests, one
stage per cluster stage:

```
  shadow[p0..p3]  { valid, idx[FTQ_IDX_BITS-1:0] }     4 x 7 bits
```

It shifts every cycle in lockstep with the cluster's own stage
registers, which advance unconditionally. A redirect clears the
shadow stages holding squashed entries. A response is accepted only
if its stage's shadow is valid AND its index matches; otherwise it is
dropped.

REJECTED ALTERNATIVE: widening the carried index to include the wrap
bit. It would change FTQ_IDX_BITS at every bp_cluster port and widen
`branch_id` in tage_pred_meta_t, sc_pred_meta_t, ittage_pred_meta_t
and bp_ftq_entry_t, for no functional gain over 28 bits of shadow in
the FTQ.

REJECTED ALTERNATIVE: draining the cluster before re-issuing after a
redirect. Correct, and free of the aliasing entirely, but it adds up
to three cycles to EVERY redirect. A p2 redirect costs two cycles
today; this would more than double it.

### 5.7 The FTB update scheduler (G9 / IC-FTB-09, resolved)

BUILT by BP-100 as `rtl/core/frontend/ftq/rtl/ftq_ftb_sched.sv`,
the first module of the FTQ unit. The rule below is implemented
as written; the properties of 5.7.4 are bound to it by module
name and run in its sim target.

The same class of problem as 5.4 and the reason it sits here: a
SCALAR predictor port fed by more than one source.

The FTQ has NUM_PRED_SLOTS update channels and
ftq_backend_interfaces.md 4 fixes the resolution input at two per
cycle. Every predictor takes two except the FTB, whose update is 14
FLAT ports with no slot dimension (ftq_bpu_interfaces.md 8) and which
declares NO ready. There is no handshake protecting it: presenting
two updates in one cycle silently loses one. The scheduler is
therefore a correctness requirement, not an optimisation, and it
belongs to the FTQ because the FTQ is what has two channels.

Scope: the FTB ONLY. tage, ittage, sc and ubtb are all per-slot. The
RAS is scalar too but is fed from the commit walk of 5.4.

#### 5.7.1 Why one per cycle is not enough

In steady state resolution rate equals prediction rate: every
predicted branch eventually resolves. At the 8-issue target of
CLAUDE.md, with 15 to 20 percent of dynamic instructions being
branches, that is 1.2 to 1.6 branch resolutions per cycle. Every one
writes the FTB -- fe_decisions.md 7.2 lists the FTB in all four
fan-out rows, and ftb_decisions.md 5.5 steps conf on every resolve.

One write per cycle is therefore below the stated target rate, not
below a rare peak. And under FE-5 as originally written the deficit
could not be absorbed: no update may be dropped, so the backlog
backpressures resolution, which stalls the backend. A PREDICTOR
TRAINING limit becomes a MACHINE THROUGHPUT limit. That is the defect
this section removes.

IC-FTB-09 was open, not decided. ftb_interfaces.md deferred
multi-branch update scheduling to bp_cluster integration and no
throughput analysis was ever done. There was no trade to reopen.

#### 5.7.2 Update value

An FTB-bound update is HIGH value when it allocates or corrects:

```
  HIGH   the FTB missed at predict (ftb_pred_meta_t.hit == 0), so
         this update ALLOCATES the entry. Without it the branch is
         never predicted at all.
  HIGH   the branch mispredicted (ftq_resolve_t.mispredict), so
         this update CORRECTS the thing that was wrong.
  LOW    hit at predict and predicted correctly: a routine conf
         step on a counter already in the right direction.
```

Both terms are available at update formation with no new state:
`mispredict` arrives on the resolution channel, `hit` is read from
the slow path with the rest of `bp_ftq_meta_t`.

A dropped LOW update is a DELAYED training step, not a lost entry.
The FTB entry still exists with its previous counter, and the next
resolve of that branch trains it.

#### 5.7.3 The rule

```
  S1  FTB-bound means the resolved br_type is anything other than
      NO_BRANCH.
  S2  Pending = the skid entry, if occupied, plus the FTB-bound
      channels accepted this cycle. The skid is ONE deep.
  S3  Issue exactly one: the skid entry when occupied, else the
      highest-value new one, slot 0 breaking a tie. Issuing the
      skid first preserves resolution order (FE-6).
  S4  Retain the highest-value remaining pending update in the
      skid.
  S5  Anything still remaining is DROPPED if LOW.
  S6  A HIGH update is NEVER dropped. If accepting one would force
      S5 to drop a HIGH, the FTQ instead deasserts
      ftq_bkend_rsv_rdy for that channel and the backend holds it.
```

S6 is what keeps this narrow. Backpressure survives only for
allocations and mispredict corrections, and a sustained two-per-cycle
rate of those is self-limiting: a mispredict causes a redirect, which
flushes the pipeline. Steady state is dominated by correct
predictions, which are LOW, so in steady state the FTQ never stalls
resolution.

Capacity follows from S2 to S4: one issues and at most one is
retained, so at most two new FTB-bound updates can be accepted with
the skid empty, and at most one with it occupied.

#### 5.7.4 Properties

Written as concurrent SVA because that is what a formal tool
consumes; the BPU tree currently has none -- its three assertion
files use procedural immediate assertions and are simulation only.
Bind these when the scheduler RTL is written, and run them in the
existing sim targets first. TD#109 is the cautionary case: an
assertion file bound to an INSTANCE name rather than a module name,
instantiated by nothing, warned about by nothing.

Signal names below are the contract for the unbuilt scheduler.

```systemverilog
  // P1  A lone FTB-bound update is never dropped and never held.
  property p_ftb_lone_issues;
    @(posedge clk) disable iff (!rstn)
      (n_acc_ftb == 1 && !skid_val) |=> ftb_upd_valid_u0;
  endproperty

  // P2  A HIGH-value update is never dropped. This is the whole of
  //     the FE-5 relaxation: only LOW updates may be lost.
  property p_ftb_high_never_dropped;
    @(posedge clk) disable iff (!rstn)
      drop_val |-> !drop_is_high;
  endproperty

  // P3  The skid never overflows. It is one deep, so a write may
  //     only coincide with the entry leaving.
  property p_ftb_skid_bounded;
    @(posedge clk) disable iff (!rstn)
      (skid_val && skid_wr) |-> skid_issue;
  endproperty

  // P4  An occupied skid always issues NEXT, so the older update
  //     goes first and resolution order is preserved (FE-6).
  //
  //     CORRECTED BY BP-100, from |-> to |=>. As first written this
  //     property and P1 could not both hold in any implementation:
  //     P1 asserts ftb_upd_valid_u0 with |=>, which requires a
  //     REGISTERED output, and P4 asserted the same signal with
  //     |->, which requires a combinational one. The registered
  //     form was built. The intent is unchanged.
  property p_ftb_skid_first;
    @(posedge clk) disable iff (!rstn)
      skid_val |=> (ftb_upd_valid_u0 && ftb_upd_from_skid);
  endproperty

  // P5  Resolution is never stalled when every pending FTB update
  //     is LOW. This is the throughput claim of 5.7.1: training
  //     pressure must not reach the backend.
  property p_ftb_no_stall_on_low;
    @(posedge clk) disable iff (!rstn)
      (n_pend_ftb > 0 && !any_pend_high) |-> (&ftq_bkend_rsv_rdy);
  endproperty
```

The signal names above are the scheduler's PORT LIST, not internal
nets. ftq_ftb_sched carries skid_val, skid_wr, skid_issue, drop_val,
drop_is_high and the two pending counts as outputs so the bind reads
only ports and makes no hierarchical reference into the module
(TD#109). ftq_bkend_rsv_rdy appears on the scheduler as upd_rdy: the
scheduler owns only the FTB reason for deasserting it, and the FTQ
ANDs that with its others.

P2 and P5 are the two that carry the design intent. P2 bounds the
accuracy cost; P5 bounds the throughput cost. P1, P3 and P4 are the
structural checks that make the other two meaningful.

Proving P1 to P5 also retires a verification cost. Without them a
testbench must model the collision and the priority rule to predict
FTB contents at all. With them, simulation can restrict stimulus to
non-colliding sequences and check the datapath normally, leaving the
drop behaviour to proof. This is a two-input arbiter with a one-bit
priority function and one skid register: bounded state, no sequential
depth, entirely control.

#### 5.7.5 Not mergeable, and what is left on the table

Two updates naming the same entry hit the same set AND the same way
-- the carried hit and way come from ftb_pred_meta_t, which is scalar
within the entry -- so their fields are different bit ranges inside
one FTB_RAM_ENTRY_WIDTH slice of ftb_array. One RAM write could carry
both. That is a real optimisation and it needs NO second write port:
ftb_array.sv is a single 512-set array with one write port, and this
would widen the write data rather than duplicate the port.

It is NOT taken here. It covers only the same-block case, it requires
widening the update payload and reworking ftb_cntrl's write logic in
a verified module, and the drop rule above already removes the
throughput problem. Recorded as the first escalation if measurement
ever shows the LOW drop rate matters.

The second escalation is banking ftb_array by index so two updates to
different sets proceed in parallel. Two banks give roughly 1.5
effective writes per cycle for random addresses, not 2.

Neither can be chosen without measurement, and the repository has no
simulator to measure with.

### 5.8 What this settles

```
  FE-U7  RESOLVED by this section.
  G23    Checkpoint slot reclaim. The checkpoint is a field of the
         entry, so it is reclaimed with the entry at 5.3. No
         separate protocol.
  4.5 H2 Full is defined: 5.1.
  4.6    The drop rule has a mechanism: 5.6.
  G9     Update channel arbitration. The SC half was already done
         and tested (BP-094 group H); the FTB half is 5.7.
```

The three IFU-facing entry fields deferred by
ftq_ifu_interfaces.md 8 item 3 -- request-issued,
writeback-received, fault -- are now decidable, and were decided.
request-issued is redundant: fetch_ptr already says which entries
have been issued. The other two are per-entry status and are
ftq_entry_formats.md 4, held in flops outside both SRAMs.

---

## 6. Open policy

Collected for navigation. Each is recorded in `fe_decisions.md` or
`PROJECT_STATUS.md`; none is decided here.

```
  FE-U7    RESOLVED. Section 5.
  FE-U2    Flush handling. The FTQ side is answered by
           ftq_backend_interfaces.md 5. The RAS behaviour behind D3
           is CLOSED -- it is D2 and nothing more,
           ras_decisions.md 4.4. The flush EVENT and the FTB half
           are CLOSED too, BP-105: there is no flush event, a
           flush is a redirect (fe_decisions.md FE-14). TD#96,
           G24 and IC-FTB-07 all closed.
  FE-U3    bp_ftq_slot_t.confidence has no consumer.
  TD-FE-1  CLOSED, in full. The IFU interface is
           ftq_ifu_interfaces.md; the entry fields it needs are
           ftq_entry_formats.md 4. Two were added, wb_rcvd and
           fault; request-issued was rejected as a second encoding
           of fetch_ptr.
  TD-FE-8  CLOSED. A predecode writeback in flight when its entry
           was squashed and its index reallocated set the status
           bits on the wrong use of that index. One generation bit
           on the IFU path, toggled per allocation.
           ftq_entry_formats.md 4.4, ftq_ifu_interfaces.md 6.1.
  TD-FE-2  The slow-path overload is defined and DEFERRED. See
           ftq_entry_formats.md 3.1.
  TD-FE-3  bp_ftq_entry_t.pc and the per-slot target are 40 bits;
           39 suffice under the C extension, 35 if a block always
           starts on an FTB_BLOCK_BYTES boundary.
  TD-FE-4  bp_ftq_slot_t.pred_src is diagnostic only.
  G9       RESOLVED. Section 5.7.
  G23      RESOLVED. The checkpoint is a field of the entry and is
           reclaimed with it. Section 5.7.
  RESETVEC RESOLVED. bp_defines_pkg::RESET_VECTOR. Section 4.7.
  PREFETCH Instruction prefetch is DEFERRED and the deferral has a
           structural cost. Section 6.1.
  TD-FE-7  CLOSED by BP-102. bp_cluster gained ftq_rollback_val
           and ftq_rollback_idx, with priority over its own p2/p3
           arms. ftq_backend_interfaces.md 8, section 3.2.
```

Next-PC selection was on this list and is now section 4. What
remains open from it is the RESET VECTOR, which has no source
anywhere in the tree; see 4.7.

### 6.1 Instruction prefetch -- DEFERRED, with impact

DECIDED 2026-08-19, alongside the decision not to define an
ftq_icache interface. Pacino specifies no instruction prefetcher and
no FTQ-sourced prefetch path.

WHAT THIS FORECLOSES, and it is not the same thing the ftq_icache
decision defers. That one is PHYSICAL and PD can undo it. This one is
FUNCTIONAL and PD cannot.

An instruction prefetcher wants the FTQ's RUN-AHEAD: the entries
between fetch_ptr and alloc_ptr (section 5.1), which the BPU has
predicted and the IFU has not yet fetched. That stream exists ONLY in
the FTQ. The IFU is by construction behind fetch_ptr, so an
IFU-encapsulated memory path has no access to it, and no amount of
physical-design work creates the access.

XiangShan carries this as a separate consumer, not as part of its
ICache path: FtqToPrefetchIO, toPrefetchPcBundle, and a dedicated
pfPtr read port in ftq_pc_mem. The pointer sits between its ifuPtr
and its bpuPtr, exactly in the run-ahead gap.

IMPACTED IF PREFETCH IS LATER WANTED:

```
  ftq_decisions.md 5.1   a fourth pointer, prefetch_ptr, between
                         fetch_ptr and alloc_ptr, with FQ-1
                         extended to order it
  ftq_decisions.md 5.5   the rewind rule gains a pointer
  fast-path read ports   a further reader of bp_ftq_entry_t,
                         against the two-read-port decision of
                         section 1
  a new interface        FTQ to prefetcher, or an extension of
                         ftq_ifu_interfaces.md
  redirect fan-out       the prefetcher must be told to drop stale
                         requests, as XiangShan does with
                         BpuFlushInfo on FtqToPrefetchIO
```

The pointer model of section 5 was written so the run-ahead is
explicit rather than implicit, so adding prefetch_ptr later is an
extension rather than a restructure. That is the whole of the
insurance taken here.

---

## 7. Module decomposition

The FTQ is SEVERAL MODULES. `ftq.sv` is the top and is PURELY
STRUCTURAL: instantiation and wiring, no logic of its own, no
always block, no state. Anything that needs a decision made in it
belongs in a leaf instead.

### 7.1 The partition rule

EVERY PIECE OF STATE HAS EXACTLY ONE OWNER MODULE. Everything else
reads it through a port. The partition below is derived from that
rule and from nothing else, which is why it does not follow the
section order of this document: two sections that touch the same
register belong in one module, and one section that owns two
unrelated registers splits.

```
  ftq.sv             structural top, no state, no logic
  ftq_ptr.sv         alloc_ptr, fetch_ptr           5.1 5.2 5.5
  ftq_commit.sv      commit_ptr, the commit walk    5.3 5.4
  ftq_npc.sv         the next-PC register, and the
                     redirect arbitration that
                     feeds it                       4
  ftq_entry.sv       the fast-path array            1 2
  ftq_meta.sv        the slow-path array            3
  ftq_status.sv      wb_rcvd, fault, gen            entry_formats 4
  ftq_shadow.sv      the four-deep response shadow  5.6
  ftq_ifu.sv         request, flush, writeback,
                     predecode redirect             ftq_ifu_ifs
  ftq_resolve.sv     resolution intake and update
                     fan-out                        backend_ifs 4
  ftq_ftb_sched.sv   BUILT, BP-100                  5.7
```

`ftq.sv` does NOT instantiate `bp_cluster`. The BPU is a separate
unit; a front-end top above both wires them together.

### 7.2 Why the pointers split

`ftq_ptr` owns alloc_ptr and fetch_ptr. `ftq_commit` owns
commit_ptr. Section 5.1 presents all three together and the
partition rule splits them anyway, because commit_ptr is the only
one whose advance is not a local decision: 5.4 rate-limits it to one
entry per cycle against the scalar RAS commit port, reads
`bp_ras_snapshot_t` out of the entry to form the commit payload, and
SUPPRESSES the advance in any cycle a redirect restore fires. That
is a different job from allocating and issuing.

`ftq_ptr` reads commit_ptr as an input to compute full. One writer,
one reader, no shared state.

### 7.3 Why redirect arbitration is in ftq_npc

Four redirect sources reach the FTQ -- backend, p2, p3, and
predecode -- and 4.3 orders them by AGE, not by an axiom. That
ordering exists to answer one question: what does fetch do next.
The winner is therefore the next-PC source, and putting the arbiter
anywhere else would mean exporting the priority result to the module
that already has to consume it.

`ftq_npc` publishes the winning redirect to `ftq_ptr` for the rewind
of 5.5 and to `ftq_status` for the masked clear of
`ftq_entry_formats.md` 4.2 W4. Those two act on it; neither decides
it.

### 7.4 Why status is not inside ftq_entry

Different storage class. `ftq_entry` is an SRAM read every cycle;
`ftq_status` is 192 flops with a masked range clear. Keeping them
apart makes the storage class STRUCTURAL rather than a comment, and
`ftq_entry_formats.md` 4.1 is the argument for why they cannot share
one.

---

## 8. Document History

```
  2026-08-20  TD-FE-8 CLOSED by one generation bit on the IFU
              path. Section 6 registry updated.

  2026-08-20  Section 7 added: module decomposition. The FTQ is
              several modules with a purely structural ftq.sv top,
              partitioned by ONE rule -- every piece of state has
              exactly one owner. Document History renumbered 7 to
              8; nothing referenced 7.

  2026-08-20  The last two open entry fields decided and placed
              in ftq_entry_formats.md 4, closing TD-FE-1 in full.
              Section 6 registry updated; TD-FE-8 opened for the
              in-flight writeback race.

  2026-08-20  Section 5.7.4 P4 CORRECTED, |-> to |=>. P1 and P4
              as written could not both hold in any implementation:
              one required a registered output and the other a
              combinational one, on the same signal. Found by
              building the scheduler (BP-100). 5.7.4 also gains a
              note that the property signal names are the module's
              port list, which is what BP-100 delivered.

  2026-08-20  Section 3.2 CORRECTED. It specified the value form,
              the FTQ presenting ghist_ptr and phist_ptr; BP-102
              built the index form and closed TD-FE-7, so the FTQ
              presents ftq_rollback_idx and the cluster reads its own
              checkpoint copy. The conflict was between this document
              and fe_decisions.md 13, which had recorded the choice
              as open; building it settled the choice.

  2026-08-19  Created. Sections 4.3, 5 and 6 moved here whole from
              fe_decisions.md; no content changed in the move.
              Numbering: fe_decisions 4.3 -> section 1, 5 ->
              section 2, 6 -> section 3. Section 0 added, naming the
              companion documents, stating that the FE / TD-FE / FE-U
              registries are NOT duplicated here, and listing the
              four FTQ interfaces. Section 4 added: a navigation list
              of open policy items, by reference only, plus the
              next-PC ownership gap.

  2026-08-19  ftq_ifu_interfaces.md added and TD-FE-1 closed. The
              interface table in section 0 and the open policy list
              in section 4 updated to match.

  2026-08-19  ftq_backend_interfaces.md added: resolution, redirect
              and commit as three separate events. Section 0 and
              section 4 updated. FE-U2's FTQ side is answered
              there; FE-U7 and G23 are unblocked but not decided.
              TD-FE-7 opened against bp_cluster. Also repaired the
              FE-U7 entry, which had lost the words "flush is" to a
              cross-reference edit earlier the same day.

  2026-08-19  Section 4 added: the next fetch PC. The FTQ is the
              requester and owns the selection. Priority is stated
              as a CONSEQUENCE of entry age rather than an axiom,
              with the argument for why the depth ordering
              reproduces it. The p1 successor path is identified as
              the zero-bubble critical loop and the only source that
              must be combinational. IFU backpressure is explicitly
              NOT a hold condition. Cluster responses for squashed
              entries are dropped by index, needing the same FE-U7
              generation bit as ftq_backend R3. 4.7 opens the reset
              vector, which has no source anywhere in the tree.
              Open policy renumbered 4 -> 5, history 5 -> 6.

  2026-08-19  FE-U7 RESOLVED as section 5, queue management. Three
              pointers with a wrap bit: alloc at p0 (the index
              leaves with the request, one cycle before the entry
              write), fetch, and a single commit pointer that both
              issues the RAS commit and frees, walking at one entry
              per cycle because ras_commit_* is scalar. Redirect
              rewinds head and fetch, never commit. Stale responses
              are caught by a four-deep in-flight shadow rather
              than by carrying a wrap bit through bp_cluster; both
              rejected alternatives are recorded with their cost.
              G23 falls out. Section 6.1 records the instruction
              prefetch deferral and what it forecloses. Open policy
              renumbered 5 -> 6, history 6 -> 7.

  2026-08-19  G9 RESOLVED as section 5.7, the FTB update scheduler.
              The FTB update is 14 flat ports with NO slot dimension
              and NO ready, so presenting two in a cycle loses one
              silently: the scheduler is a correctness requirement,
              not an optimisation, and it is the FTQ's because the
              FTQ is what has two channels. Slot 0 first into a
              one-deep skid, with resolution backpressure bounding
              it. Scope is the FTB alone; every other predictor
              takes two per cycle and the scalar RAS port is fed
              from the 5.4 commit walk. The one-per-cycle FTB
              ceiling is recorded as a known limit rather than
              reopening the single-port choice of FTB-3 /
              IC-FTB-09.

  2026-08-19  RESETVEC resolved. bp_defines_pkg::RESET_VECTOR,
              parameter, 40'h00_8000_0000, block aligned. Section
              4.7 rewritten from an open item to the decision. It
              was never a hard choice -- it was on the list because
              nothing in the tree named a reset PC at all.

  2026-08-19  5.7 REWRITTEN, superseding the G9 entry above. That
              entry said the one-per-cycle ceiling was recorded as a
              known limit "rather than reopening the single-port
              choice of FTB-3 / IC-FTB-09". There was no choice to
              reopen: ftb_interfaces.md had IC-FTB-09 marked OPEN
              and deferred to bp_cluster integration, and no
              throughput analysis had been done.
              5.7.1 does it: at the 8-issue target 1.2 to 1.6
              branches resolve per cycle and every one writes the
              FTB, so one write per cycle was below target, and
              FE-5's no-drop rule turned the deficit into
              backpressure on resolution -- a training limit
              stalling the backend.
              5.7.2 defines update value, 5.7.3 the drop rule: LOW
              may be dropped, HIGH never, backpressure only to
              protect a HIGH. 5.7.4 specifies five concurrent SVA
              properties for the unbuilt scheduler; P2 bounds the
              accuracy cost, P5 the throughput cost. 5.7.5 records
              the two escalations not taken. FE-5 amended narrowly
              as FE-5a; IC-FTB-09 resolved. The FTB is unchanged.
```
