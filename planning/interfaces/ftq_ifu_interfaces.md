<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTQ to IFU Interface
```
 FILE:    ftq_ifu_interfaces.md
 SOURCE:  ftq_decisions.md, ftq_entry_formats.md, ftb_decisions.md,
          bp_defines_pkg.sv, ia_context/background/xs_ifu_ftq.md
 STATUS:  DRAFT
 UPDATED: 2026-09-22
 CONTACT: Jeff Nye
```

The second of the FTQ's four interfaces. THE FTQ SIDE IS BUILT:
ftq_ifu.sv is Complete and its port list is the FTQ half of this
boundary (ifu_decisions.md, ftq_decisions.md 7.1), so the names
here are declared on that side. THE "NEW" TAG ON THE PORT ROWS
MEANS NOT YET DECLARED ON THE IFU SIDE; it does not mean the port
is undeclared on both. The IFU side does not exist --
`rtl/core/frontend/ifu/rtl` holds only a .gitkeep -- and those ports
are new. This read that no module on either side exists and that
nothing here names a declared port, which was true only until
BP-106/107; this file names ftq_ifu.sv twice itself, in sections 7
and 8. Session-072.

Where this file departs from the XiangShan Kunminghu contract
translated in `ia_context/background/xs_ifu_ftq.md`, section 9 says
why.

---

## 1. Scope

Covered:
- the fetch request, FTQ to IFU
- the flush and resteer path, FTQ to IFU
- the predecode writeback, IFU to FTQ
- the entry fields the writeback adds to `bp_ftq_entry_t`

Not covered:
- IFU internals, the ICache, the ITLB
- the IFU to IBuffer path, which does not return to the FTQ
- EXE to FTQ resolution -- ftq_backend_interfaces.md. This read
  "still unspecified"; that document exists. Session-070.
- whether the FTQ drives the ICache directly; see section 8

---

## 2. Naming

Predictor-facing ports carry a pipeline-stage suffix. This document
has no stage suffixes. That is a choice, not a gap: the IFU pipeline
IS defined, F0 to F3 plus WB (ifu_decisions.md IFU-9), and this text
read "The IFU pipeline is not defined". Session-070. Ports are named
by direction:

```
  ftq_ifu_<signal>    FTQ  -> IFU
  ifu_ftq_<signal>    IFU  -> FTQ
```

The IFU pipeline IS defined -- F0 to F3 plus WB, ifu_decisions.md
IFU-9 and IFU-10 -- so this is a naming choice, not a wait. If the
suffixes are ever added here, record the
rename here. This is a deliberate deviation, not an oversight.

---

## 3. Block sizes and granularity

Three sizes are in play and must not be collapsed.

```
  FTB_BLOCK_BYTES    32   the PREDICTION block. One FTQ entry
                          describes exactly one of these.
  FETCH_BLOCK_BYTES  64   the FETCH block: the unit the IFU reads
                          from the L1I, one cache line
                          (fe_decisions.md Conventions).
  FTB_BR_POS_BITS     4   in-block position, 2-byte granular, so
                          sixteen positions per prediction block.
```

`bp_defines_pkg.sv`, in the comment above FTB_BLOCK_BYTES, states
that the 32 and the 64 must not be collapsed. This interface names
the 32-byte prediction block: one request, one FTQ index, one entry,
at most one request per cycle. The IFU reads the 64-byte line holding
the block and extracts the block from it (ifu_decisions.md IFU-7,
TD-IFU-7). Serving two sequential requests from one held line is
IFU-internal and not visible here.

DELIVERING TWO PREDICTION BLOCKS PER CYCLE IS NOT IFU-INTERNAL. It
needs two requests per cycle from the FTQ and reopens this interface;
section 8, item 2. This paragraph called coalescing "an IFU-internal
optimization" without that distinction, cited item 1 for it, and
cited bp_defines_pkg.sv by a line number that had moved.
Session-071.

GRANULARITY. Predecode and the predictor now agree. Both resolve
2-byte positions, so a predecode position and a predictor position
are the same quantity and convert without loss. Until 2026-08-19 the
predictor was 4-byte granular and the two differed; the two widths
below are kept as separate names because they are derived from
different things, not because they hold different values.

```
  FTQ_PD_WIDTH     FTB_BLOCK_BYTES / 2      = 16  predecode slots
  FTQ_PD_POS_BITS  $clog2(FTQ_PD_WIDTH)     =  4  predecode position
  FTB_BR_POS_BITS                           =  4  predictor position
```

Both are 4 bits and the conversion is the identity. FTQ_PD_WIDTH is
derived from the block size and the RVC instruction granularity;
FTB_BR_POS_BITS is derived from the block size and the predictor's
position granularity. They coincide at the shipped geometry and a
change to either must be checked against the other. Section 7 states
where each is used.

Every position on this interface is measured from the BLOCK START:
position 0 is the first halfword of the block. The FTB and the uBTB
store positions relative to the 32-byte-aligned region, one bit wider,
and convert at their own boundary, so no port anywhere carries the
stored form (ftb_decisions.md 4.6). Session-071.

---

## 4. Fetch request: FTQ to IFU

Decoupled. The FTQ presents a request; the IFU accepts when its first
stage is free and the ICache can take the access.

THERE ARE TWO REQUEST GROUPS, NOT ONE. The IFU runs translation as a
pipeline ahead of fetch (ifu_decisions.md IFU-23a). Section 4.1 is
the translation request, driven by `xlate_ptr`. This section is the
fetch request, driven by `fetch_ptr`. The same entry is presented
twice, on the translation port first and the fetch port later, and
the two are independently flow controlled.

```
  ftq_ifu_req_val                              NEW
  ftq_ifu_req_rdy                              NEW   IFU -> FTQ
  ftq_ifu_start_pc    [VA_WIDTH-1:0]           NEW
  ftq_ifu_next_pc     [VA_WIDTH-1:0]           NEW
  ftq_ifu_idx         [FTQ_IDX_BITS-1:0]       NEW
  ftq_ifu_taken_val                            NEW
  ftq_ifu_taken_pos   [FTB_BR_POS_BITS-1:0]    NEW
  ftq_ifu_gen                                  NEW   TD-FE-8
  ftq_ifu_commit_ptr  [FTQ_IDX_BITS-1:0]       NEW   IFU-22
                                               NOT BUILT, TD#142
```

A request on this port is issued only for an entry whose translation
has already been presented on 4.1. The FTQ does not enforce that; it
follows from FQ-1, fetch_ptr <= xlate_ptr.

`ftq_ifu_start_pc` is `bp_ftq_entry_t.pc`, the block start.

`ftq_ifu_next_pc` is the block successor, selected across the slots
by `fe_decisions.md` 2.4: the first taken slot's target, or
`bp_ftq_entry_t.pft_addr` when no slot is taken. The IFU does not
recompute it. It exists so the IFU knows where the block ends without
reading the prediction, and so a prefetcher can walk ahead.

`ftq_ifu_taken_val` and `ftq_ifu_taken_pos` name the predicted taken
branch, so the IFU truncates the bundle there and does not present
instructions after it. Not valid means fetch the whole block.

`ftq_ifu_gen` is an OPAQUE TAG. The IFU stores it with the request
and returns it unchanged on the writeback; it has no meaning inside
the IFU and must not be decoded there. It closes TD-FE-8; the rule
is section 6.1.

`ftq_ifu_idx` accompanies every request and returns on the writeback.
It is the entry's own index, the same value carried in `branch_id`.

### 4.1 Translation request: FTQ to IFU

```
  ftq_ifu_xlate_val                            NEW   IFU-24
  ftq_ifu_xlate_rdy                            NEW   IFU -> FTQ
  ftq_ifu_xlate_pc    [VA_WIDTH-1:0]           NEW   IFU-24
  ftq_ifu_xlate_idx   [FTQ_IDX_BITS-1:0]       NEW   IFU-24
```

Driven from `xlate_ptr` (ftq_decisions.md 5.1), which sits between
`alloc_ptr` and `fetch_ptr`. The IFU's translation pipeline accepts
when its ITLB port and its translation queue can take another block.

`ftq_ifu_xlate_pc` is `bp_ftq_entry_t.pc`, the same field section 4
sends as `ftq_ifu_start_pc`. The entry is read twice because the two
pointers reach it at different times.

`ftq_ifu_xlate_idx` lets the IFU tag its queue entry so the fetch
request can be matched against the translation that was produced for
it.

NO RESULT RETURNS ON THIS PORT. The translation lands in the IFU's
own queue (IFU-25). The FTQ never sees a physical address, a PMA
attribute or a translation fault; those reach it, if at all, through
the predecode writeback fault fields of section 6.

WHY THE ENTRY IS PRESENTED TWICE. L1I-3 makes the L1I physically
indexed with translation complete before the array is indexed. A
single request group would force the IFU to translate and fetch in
one pass, which serialises the ITLB ahead of the array inside the
fetch pipeline. Splitting the pointer moves the translation out of
that path.

The two pointers reset to the same entry, and on a redirect each
moves back to the flush index if it was past it (ftq_decisions.md 5.5
R1), so the first fetch after either usually stalls one cycle waiting
for its translation. This read "are set equal on a redirect".
Session-071. That cost is stated in ftq_decisions.md 5.1 and
in IFU-27.

`ftq_ifu_commit_ptr` is DRIVEN CONTINUOUSLY, not requested. It is
not part of the request handshake and carries no valid. The FTQ
already holds this pointer; what is new is exporting it.

It exists for uncached fetch alone. A memory mapped device must not
see a read for an instruction that is not on the committed path, so
the IFU compares the index of an uncached block against this pointer
and issues the bus transaction only when everything earlier has
committed (`ifu_decisions.md` IFU-22). A cached fetch never reads
it: cacheable reads are speculative by design and have no side
effect. Stopping fetch is what lets the pipeline drain, but the
drain takes an unknown number of cycles and the IFU cannot otherwise
observe that it has finished. The FTQ cannot gate the request
instead, because whether a block is uncached is discovered in the
IFU from the PMA result at F2, after the request has been handed
over.

CROSS-LINE is DERIVED, not a port. The IFU computes it from
`ftq_ifu_start_pc` and its own line size. XiangShan carries
`nextlineStart` because its ICache takes two line addresses per
access; adding a port here would pin an ICache geometry this project
has not chosen (section 8, item 1).

The request is presented in FTQ entry order. The FTQ does not issue a
request for an entry it has already flushed.

---

## 5. Flush: FTQ to IFU

```
  ftq_ifu_flush_val                            NEW
  ftq_ifu_flush_idx   [FTQ_IDX_BITS-1:0]       NEW
```

Drop every in-flight fetch whose FTQ index is at or after
`ftq_ifu_flush_idx`, and discard whatever the IFU holds for those
entries. The FTQ resumes requesting from the flush index, or from
where it already was if it had not reached it (ftq_decisions.md 5.5
R1). The index is K or K+1 by cause, as 5.5 R1 tabulates.

IT DOES NOT CLEAR THE IBUF. Only a backend redirect does
(`ibuf_decisions.md` IBUF-8, `ifu_ibuf_interfaces.md` IB-12). A
predecode redirect is truncated by the IB-2 mask in the same stage
as the ibuf write, so nothing wrong arrives; a p2 or p3 redirect
fires before the named entry is fetched. Clearing on either would
discard valid work.

THIS FLUSHES BOTH IFU PIPELINES. The translation pipeline of 4.1 and
the fetch pipeline of section 4 are flushed by this one group, and
the translation queue between them (IFU-25) is emptied of every entry
at or after the flush index. The FTQ moves `xlate_ptr` and `fetch_ptr`
back to the flush index if they were past it and leaves them
otherwise (ftq_decisions.md 5.5 R1). When they were past it, the
first fetch after a flush waits for its own translation. Nothing at
or after the flush index is carried across a flush on the strength of
having been translated before it. This read that the FTQ "sets
`xlate_ptr` and `fetch_ptr` both to the flush index", which skips
unfetched entries older than it when the IFU is behind. Session-071.
Section 4.1 and xlate_ptr are BUILT, BP-112, TD#127 closed.

ONE flush group, not two. XiangShan carries `BpuFlushInfo` with
separate `s2` and `s3` valid-pointer pairs and leaves the consumer to
apply `shouldFlushByStage2` and `shouldFlushByStage3`. Pacino's FTQ
already resolves supersession by stage order before anything leaves
it (FE-3: a later stage wins for the entry and slot it names, and the
FTQ does not compare targets to settle it). Exporting both stages
would ask the IFU to redo a decision the FTQ has already made. The
FTQ presents the resolved flush point.

Sources of a flush, all resolved by the FTQ into this one group:

```
  p2 redirect          bpu_redir_p2 / bpu_redir_idx_p2
  p3 redirect          bpu_redir_p3 / bpu_redir_idx_p3
  predecode redirect   section 6, derived from the writeback
  backend redirect     ftq_backend_interfaces.md (this read
                       "ftq_backend, UNSPECIFIED"; session-070)
```

NO REQUEST ACCOMPANIES A FLUSH. A request may be PRESENTED in the
flush cycle, on section 4 or on 4.1, but it belongs to the old
stream: the FTQ drives it from the pre-rewind pointer and discards
the handshake, so the pointer does not advance and the entry is
presented again the next cycle from the rewound pointer. THE IFU
MUST IGNORE ANY REQUEST PRESENTED IN A CYCLE WHERE
ftq_ifu_flush_val IS SET, on both groups. Accepting one and acting
on it fetches the same entry twice under one generation tag when
the pre-rewind pointer was behind the flush index, and fetches a
squashed entry when it was not.

The first request of the corrected stream is the one presented the
CYCLE AFTER the flush.

RULED session-073 (Jeff), TD#138. This section said the opposite --
that the flush applies first and the request accompanying it is the
first fetch of the corrected stream -- which no request port has
ever done and which would need a same-cycle path from the winning
redirect through ftq_ptr's rewind to the entry read index and the
request outputs. The behaviour as built costs nothing, since the
handshake was already being discarded. tb_ftq_ptr H53-H56 pin it.
BP-112 recorded the full analysis.

---

## 6. Predecode writeback: IFU to FTQ

One writeback per prediction block, after the IFU has predecoded the
fetched bytes.

```
  ifu_ftq_pdwb_val                                  NEW
  ifu_ftq_pdwb_idx     [FTQ_IDX_BITS-1:0]           NEW
  ifu_ftq_pdwb_gen                                  NEW   TD-FE-8
  ifu_ftq_pd           ftq_pd_info_t
                         [FTQ_PD_WIDTH-1:0]         NEW
  ifu_ftq_pd_range     [FTQ_PD_WIDTH-1:0]           NEW
  ifu_ftq_cfi_val                                   NEW
  ifu_ftq_cfi_pos      [FTQ_PD_POS_BITS-1:0]        NEW
  ifu_ftq_mis_val                                   NEW
  ifu_ftq_mis_pos      [FTQ_PD_POS_BITS-1:0]        NEW
  ifu_ftq_target       [VA_WIDTH-1:0]               NEW
  ifu_ftq_fault_val                                 NEW
  ifu_ftq_fault_pos    [FTQ_PD_POS_BITS-1:0]        NEW
```

`ftq_pd_info_t` is per predecode slot, the shape of XiangShan's
`PreDecodeInfo`:

```
  typedef struct packed {
    logic        valid;    // slot holds an instruction start
    logic        is_rvc;   // 16-bit encoding. UNDRIVEN at the
                           // moment: no producer in DCD-7, no
                           // consumer in the FTQ. Session-072.
    logic [1:0]  br_type;  // 00 not CFI, 01 branch, 10 jal, 11 jalr
    logic        is_call;
    logic        is_ret;
  } ftq_pd_info_t;                                   // 6 bits
```

`ifu_ftq_pd_range` marks the slots inside the block that were
actually fetched: the tail is cut short by a taken branch, by the
block end, or by a fault.

`ifu_ftq_cfi_val` and `ifu_ftq_cfi_pos` name the first control-flow
instruction predecode actually found. `ifu_ftq_target` is its target
when predecode can compute one, which is every direct branch and JAL.
For JALR it carries no meaning and is not read.

`ifu_ftq_mis_val` and `ifu_ftq_mis_pos` mark a STRUCTURAL
mispredict predecode can prove without executing anything:

```
  M1  the block was predicted to have no taken branch, and predecode
      found an unconditional direct branch, JAL, or a call
  M2  a taken slot named a position that holds no instruction start,
      or holds an instruction that is not a control transfer
  M3  the direct target computed by predecode differs from the
      target the entry holds for that slot
  M4  the predicted taken position lies outside ifu_ftq_pd_range
```

M1 through M4 need no execution and no register file. A CONDITIONAL
branch's direction is NOT a predecode mispredict: predecode cannot
know it, and TAGE and SC already own the direction.

`ifu_ftq_fault_val` and `ifu_ftq_fault_pos` report that fetch
terminated on an instruction access fault, page fault or guest page
fault at that slot. Guest page fault is a class here because H is
MANDATORY in RVA23 via Sha, so pacino has two-stage translation.

The FAULT CODE IS NOT CARRIED HERE. The
architectural exception travels with the instruction stream to the
backend, which is where it is taken. The FTQ needs only to know that
the block ended early so it stops requesting and stops predicting
past it.

### 6.1 Stale writeback rejection -- TD-FE-8, closed

A writeback in flight when its entry is squashed and its index
REALLOCATED would otherwise arrive after the new allocation cleared
the status bits and set them on the wrong use of that index
(`ftq_entry_formats.md` 4.4).

```
  X1  The FTQ holds one generation bit per entry, gen[FTQ_DEPTH-1:0],
      in flops beside wb_rcvd and fault (ftq_entry_formats.md 4).
  X2  Allocating entry i TOGGLES gen[i]. The fetch request for that
      entry carries the NEW value on ftq_ifu_gen.
  X3  A writeback is accepted only if ifu_ftq_pdwb_gen equals
      gen[ifu_ftq_pdwb_idx]. Otherwise it is DROPPED ENTIRELY: no
      status bit set, no predecode redirect derived, no field
      rewritten.
  X4  The IFU returns the tag unchanged and never decodes it.
```

A TOGGLE, not the pointer's wrap bit. A rewind can reallocate an
index WITHIN one wrap, so a wrap-derived generation would not
discriminate; toggling on every allocation discriminates on any
reallocation, rewind or wrap.

ONE BIT IS SUFFICIENT, AND THE REASON IS A BOUND, NOT ARITHMETIC. A
single bit fails if the same index is reallocated TWICE while one
writeback is still outstanding, because the second toggle restores
the original value. That cannot happen here: section 5 has the IFU
discard everything it holds for flushed entries, so the only stale
writeback that survives a redirect is one already presented in the
flush cycle, and it arrives immediately -- not after two further
reallocations of its index.

IF THE IFU FLUSH CONTRACT CHANGES so that a writeback can survive
arbitrarily long after a flush, this width must be revisited. The
bound is what makes one bit enough; the encoding does not.

The 5.6 rejection of carried wrap bits does not apply. That was
rejected for widening FTQ_IDX_BITS at every bp_cluster port and in
tage_pred_meta_t, sc_pred_meta_t and ittage_pred_meta_t. This bit is
on the IFU path and touches none of them.

There is NO separate IFU to FTQ redirect port. The FTQ derives the
redirect from the writeback, exactly as XiangShan does. A second path
would let the two disagree.

---

## 7. What the writeback does to the entry

The writeback is the THIRD correction of a slot, after the p2 and p3
slot correction groups of `ftq_bpu_interfaces.md` 4a. It is later
than both and supersedes both for the slot it names, by the same
stage-order rule as FE-3.

On `ifu_ftq_mis_val`, the FTQ:

```
  W1  rewrites the named slot: slot_valid, br_type and taken from
      the predecode info, target from ifu_ftq_target when predecode
      computed one. pred_src becomes PRED_NONE -- no predictor
      supplied this, and the field is diagnostic (TD-FE-4).
  W2  writes ifu_ftq_mis_pos straight into bp_ftq_slot_t.pos. The
      two widths are equal and the conversion is the identity
      (section 3). It was a lossy shift until the position field
      was widened on 2026-08-19.
  W3  re-derives the block successor across the slots
      (fe_decisions.md 2.4) and drives ftq_ifu_flush_val with this
      entry's index, so fetch restarts from the corrected successor.
      THE INDEX IS K, THE ENTRY ITSELF, NOT K+1. W1 and W2 correct
      the entry rather than discarding it, and section 5 then drops
      in-flight fetches at or after K. For a predecode redirect K
      is already fetched, so including it costs nothing. For a p2
      or p3 redirect K is not yet fetched and including it is
      required: the correction changes taken_val and taken_pos,
      which is what the IFU truncates the bundle on, so a fetch
      issued against the old prediction would truncate in the wrong
      place. Session-069. BUILT by BP-112, TD#126 closed, together
      with the fetch_ptr half: it had rewound to K+1 with the
      flush, so flushing at K alone would have left K flushed and
      never presented again.

      THIS RULE CANNOT BE KEYED ON THE REDIRECT CAUSE. ftq_npc
      drives RC_MISPREDICT with _self clear for p2, p3, predecode
      and the backend alike, so the distinction W3 needs is not on
      the bus. The FTQ resolves it internally from ftq_npc's
      arm_win, the arbitration arm that won: arms 2, 3 and 4 are
      predecode, p3 and p2. ftq_decisions.md 5.5 R1 carries the
      same note.
  W4  restores the history pointers and the RAS snapshot from this
      entry, the same restore a p2 or p3 redirect performs
      (ftq_decisions.md 3.2).
```

NO PREDICTOR UPDATE IS FORMED FROM PREDECODE. Updates remain
post-execute (FE-8, `fe_decisions.md` 7.1). A structural mispredict
here is corrected in the entry; the predictors learn it when the
branch resolves, and the `ftq_entry_formats.md` 3.1 R2 rule already
handles a classification that disagrees with the resolved type. Forming an
update here would give the predictors two producers in different
orders and break FE-6.

The FTQ does not need the writeback to free an entry. Deallocation is
FE-U7, which is RESOLVED by ftq_decisions.md 5: deallocation
follows bkend_ftq_commit_idx and the entry is freed at commit
(5.3). This said "remains open"; item 3 of section 8 in this same
file already says FE-U7 is decided. Corrected session-070.

---

## 8. Open items

```
  1. ICache path. DECIDED 2026-08-19: pacino defines NO logical
     ftq_icache interface. The ICache is an INDEPENDENT MODULE
     inside the front-end top, a SIBLING of the IFU, and the IFU
     exposes the interface to it (icache_decisions.md L1I-2,
     fe_decisions.md FE-16). An earlier revision said the ICache
     is encapsulated behind the IFU; corrected session-069. The
     decision above is unaffected: independence changes the module
     hierarchy, not whether the FTQ reaches the cache directly.
     If physical design later needs the FTQ address earlier, a
     pass-through or alternative path is created in the PD phase,
     and this file does not change.

     XiangShan does drive the ICache and the prefetcher directly
     from its FTQ. The motive is PHYSICAL, and the evidence is in
     the Chisel rather than in any interface description:

       NewFtq.scala 637   // modify registers one cycle later to
                          // cut critical path
       NewFtq.scala 523   def copyNum = 5, with copied_ifu_ptr and
       NewFtq.scala 785   copied_bpu_ptr as Seq.fill(copyNum), and
                          toICachePcBundle a Vec(copyNum). Five
                          identical copies of one pointer and one PC
                          bundle: register replication against
                          fanout and wire delay, which has no
                          logical purpose.

     A secondary note in this tree, ia_context/background/
     xs_ifu_ftq.md 302-305, says the address fields feed the ICache
     the cycle before req.valid rises. That is a reading of the
     design, not a statement from it, and is cited as such.

     Pacino has no way to observe this pressure today:
     bp_cluster.md, Timing Methodology Gap, records that Verilator
     supplies no timing data and that stage intent in comments is
     verified by review alone. Deferring the question to PD is
     therefore deferring it to the first point at which it can be
     measured.

  2. FETCH_BLOCK_BYTES 64 against FTB_BLOCK_BYTES 32. Whether the
     IFU coalesces two consecutive FTQ entries into one 64-byte
     access, and what that does to ftq_ifu_req_rdy backpressure,
     is an IFU decision this file deliberately does not take.
     NARROWED session-071. Serving two requests from one held line
     is IFU-internal. Delivering two prediction blocks per cycle is
     not: the FTQ would issue two requests per cycle, fetch_ptr
     would advance by up to two, and there would be two predecode
     writebacks, so sections 4 and 6 reopen. As built the FTQ
     issues one request per cycle (ftq_ifu.sv, ftq_ptr.sv).
     Still open; it is decided with the IFU design.

  3. Entry fields. RESOLVED, ftq_entry_formats.md 4. FE-U7 is
     resolved (ftq_decisions.md 5), so the policy that reads them
     is settled and the fields are decidable.

     TWO of the three were added, not three. wb_rcvd and fault are
     per-entry status, held in FLOPS outside both SRAMs rather than
     as members of bp_ftq_entry_t; ftq_entry_formats.md 4.1 gives
     the reasons, of which the decisive one is that a redirect
     rewind must clear them for a RANGE of entries in one cycle.
     request-issued is NOT added: fetch_ptr already says which
     entries have been issued, and a per-entry bit would be a
     second encoding of one pointer.

     TD-FE-8 was opened against this interface and is CLOSED by
     section 6.1: one generation bit, ftq_ifu_gen out and
     ifu_ftq_pdwb_gen back, toggled per allocation.

  4. ifu_ftq_pd is 16 x 6 bits per writeback, 96 bits, plus the
     range vector. Whether the FTQ stores any of it or consumes it
     combinationally to form the correction of section 7 is an
     implementation choice. Nothing in section 7 requires storing
     it.

  5. Backpressure on the writeback. The group carries no ready. The
     FTQ must accept a writeback in the cycle it is presented,
     which is satisfiable because section 7 is a single entry
     rewrite. If the FTQ ever needs to stall it, a ready is added.
```

---

## 9. Departures from the XiangShan contract

```
  topdown_redirect   DROPPED. A structurally identical copy of the
                     redirect existing only to bucket top-down
                     performance counters. Add it with the counters
                     if they are built, not before.

  BpuFlushInfo       COLLAPSED to one group, section 5. The FTQ has
                     already resolved stage supersession (FE-3).

  nextlineStart      DROPPED from the request. Derived in the IFU;
                     carrying it pins an ICache geometry not chosen.

  PredictWidth 16    KEPT as FTQ_PD_WIDTH, but for a different
                     reason. XiangShan's 16 is its prediction width.
                     Here both are 16, and for different reasons:
                     the prediction block is 16 positions
                     (FTB_BR_POS_BITS 4, two bytes each) and 16 is
                     also the PREDECODE width, RVC granularity over
                     a 32-byte block. Two quantities that happen to
                     share a value.

  pdWb.pc vector     DROPPED. XiangShan returns the PC of every slot.
                     Every one of them is start_pc plus the slot
                     index times two; the FTQ can form any it needs.

  jalTarget          FOLDED into ifu_ftq_target. XiangShan carries a
                     separate directly-computed JAL target alongside
                     the general one. One target field plus
                     ifu_ftq_cfi_pos names the same thing.
```

---

## 10. RVA23 compliance note

RVA23 mandates the C extension, so a branch may begin at any 2-byte
boundary. FTB_BR_POS_BITS is 4, giving sixteen 2-byte positions per
32-byte block, so every branch in a block has its own position and
this interface converts a predecode position to a predictor position
without loss.

CLOSED 2026-08-19. The field was 3 bits until then, 4-byte granular,
and two RVC branches in one aligned word shared a position. The
consequences recorded here were: the entry could describe only one of
the two, section 7 W2 could not recover which, the FTB and uBTB
trained them as one branch with interfering directions, and the
position-to-slot mapping of ftq_backend_interfaces.md 4 was ambiguous.
All of that is gone.

The cost, measured: FTB entry 106 -> 110 bits per way (+8,192 bits of
array), uBTB entry 100 -> 104 (+1,024), FTQ fast path 222 -> 224 bits
per entry (+128) and slow path 420 -> 421 per slot (+128). 9,472 bits
in all, about 3 percent of the three structures. No logic was
restructured: every affected width is derived from
$clog2(FTB_BLOCK_BYTES / N), and the granularity shift had already
been separated from the predictor hash shift by BP-098, so
POS_OFFSET_BITS rescaled from 2 to 1 on its own.

## 11. Document History

```
  2026-09-22  session-073, after BP-112. Section 4.1 and section 5's
              pointer rules are BUILT, TD#127 closed. 7 W3 is
              BUILT, TD#126 closed, with the note that the rule
              cannot be keyed on the redirect cause and is
              resolved from ftq_npc's arm_win. Section 5's
              same-cycle flush-and-request sentence RULED: no
              request accompanies a flush, and the IFU must ignore
              any request presented in a flush cycle. TD#138. ftq_ifu_commit_ptr
              marked not built, TD#142.
  2026-08-19  Created. Closes TD-FE-1. Fetch request, flush and
              predecode writeback defined against the 32-byte
              prediction block. Departures from the XiangShan
              contract recorded in section 9: topdown_redirect and
              the pdWb pc vector dropped, BpuFlushInfo collapsed to
              one resolved group, nextlineStart derived rather than
              carried, jalTarget folded. Predecode writeback forms
              no predictor update; FE-8 keeps updates post-execute.
              Section 10 records the 4-byte position granularity
              against RVA23 C.

  2026-08-19  FTB_BR_POS_BITS widened to 4, closing the section 10
              gap the same day it was written. Predecode and the
              predictor now share 2-byte position granularity, so
              section 3's mismatch text and section 7 W2's lossy
              shift are both retired: the conversion is the
              identity.

  2026-08-20  Section 8 item 3 CLOSED: the entry fields are
              ftq_entry_formats.md 4, two added and one rejected.
              Section 6.1 added, closing TD-FE-8 with one
              generation bit -- ftq_ifu_gen out, ifu_ftq_pdwb_gen
              back, toggled per allocation. One bit is sufficient
              because the flush of section 5 BOUNDS the number of
              stale writebacks in flight to one per flush; if that
              contract changes the width must be revisited.

  2026-08-21  Section 9 said the prediction block is 8 positions.
              FTB_BR_POS_BITS is 4, so it is 16, as sections 3 and
              10 of this file already said. Stale by BP-099.

  2026-08-21  Cross-reference repair. No content change. Section 7
              cited "the section 4.2.1 R2 rule", the fe_decisions.md
              numbering that was retired when that content moved
              out. It is ftq_entry_formats.md 3.1 R2.

  2026-09-19  session-071. Section 3: FETCH_BLOCK_BYTES is the
              fetch block, the L1I line the IFU reads, not a fetch
              width; delivering two prediction blocks per cycle is
              not IFU-internal; ports carry block-start positions.
              Section 5: xlate_ptr and fetch_ptr move back to the
              flush index only if past it; the index is K or K+1 by
              cause. W3 recorded as unbuilt, TD#126. Section 8 item
              2 narrowed. "Fetch block" replaced by "prediction
              block" where the 32-byte unit was meant.

  2026-09-20  session-072. ftq_pd_info_t.is_rvc marked undriven:
              no producer in DCD-7, no consumer in the FTQ.

  2026-09-20  session-072. E7: an empty code fence in section 4
              removed.

  2026-09-20  session-072. G1: the scope note records that the FTQ
              side is built (ftq_ifu.sv) and only the IFU side is
              new.

  2026-09-20  session-072. E22: Document History sorted into date order;
              newer entries had been appended at the wrong end.
```
