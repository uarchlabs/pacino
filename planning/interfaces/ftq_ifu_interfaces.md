<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTQ to IFU Interface
```
 FILE:    ftq_ifu_interfaces.md
 SOURCE:  ftq_decisions.md, ftq_entry_formats.md, ftb_decisions.md,
          bp_defines_pkg.sv, ia_context/background/xs_ifu_ftq.md
 STATUS:  DRAFT -- closes TD-FE-1
 UPDATED: 2026-08-19
 CONTACT: Jeff Nye
```

The second of the FTQ's four interfaces. Every port here is NEW:
neither the FTQ nor the IFU exists in the tree, so nothing in this
file names a declared port. `rtl/core/frontend/ifu/rtl` holds only a
.gitkeep.

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
- EXE to FTQ resolution, still unspecified
- whether the FTQ drives the ICache directly; see section 8

---

## 2. Naming

Predictor-facing ports carry a pipeline-stage suffix. The IFU pipeline
is not defined, so there are no stage suffixes here yet. Ports are
named by direction:

```
  ftq_ifu_<signal>    FTQ  -> IFU
  ifu_ftq_<signal>    IFU  -> FTQ
```

When the IFU pipeline is defined, add the stage suffix and record the
rename here. This is a deliberate deviation, not an oversight.

---

## 3. Block sizes and granularity

Three sizes are in play and must not be collapsed.

```
  FTB_BLOCK_BYTES    32   the PREDICTION block. One FTQ entry
                          describes exactly one of these.
  FETCH_BLOCK_BYTES  64   the global fetch width in bp_defines_pkg.
  FTB_BR_POS_BITS     4   in-block position, 2-byte granular, so
                          sixteen positions per prediction block.
```

`bp_defines_pkg.sv` line 81 states that the 32 and the 64 must not be
collapsed. This interface names the 32-byte prediction block: one
request, one FTQ index, one entry. Whether the IFU coalesces two
consecutive requests into one 64-byte cache access is an IFU-internal
optimization and is not visible here. See section 8, item 1.

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

---

## 4. Fetch request: FTQ to IFU

Decoupled. The FTQ presents a request; the IFU accepts when its first
stage is free and the ICache can take the access.

```
  ftq_ifu_req_val                              NEW
  ftq_ifu_req_rdy                              NEW   IFU -> FTQ
  ftq_ifu_start_pc    [VA_WIDTH-1:0]           NEW
  ftq_ifu_next_pc     [VA_WIDTH-1:0]           NEW
  ftq_ifu_idx         [FTQ_IDX_BITS-1:0]       NEW
  ftq_ifu_taken_val                            NEW
  ftq_ifu_taken_pos   [FTB_BR_POS_BITS-1:0]    NEW
```

`ftq_ifu_start_pc` is `bp_ftq_entry_t.pc`, the block start.

`ftq_ifu_next_pc` is the block successor, selected across the slots
by `fe_decisions.md` 2.4: the first taken slot's target, or
`bp_ftq_entry_t.pft_addr` when no slot is taken. The IFU does not
recompute it. It exists so the IFU knows where the block ends without
reading the prediction, and so a prefetcher can walk ahead.

`ftq_ifu_taken_val` and `ftq_ifu_taken_pos` name the predicted taken
branch, so the IFU truncates the bundle there and does not present
instructions after it. Not valid means fetch the whole block.

`ftq_ifu_idx` accompanies every request and returns on the writeback.
It is the entry's own index, the same value carried in `branch_id`.

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
entries. The FTQ resumes requesting from the flush index.

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
  backend redirect     ftq_backend, UNSPECIFIED
```

A flush and a request may be presented in the same cycle. The flush
applies first: the request that accompanies it is the first fetch of
the corrected stream.

---

## 6. Predecode writeback: IFU to FTQ

One writeback per fetch block, after the IFU has predecoded the
fetched bytes.

```
  ifu_ftq_pdwb_val                                  NEW
  ifu_ftq_pdwb_idx     [FTQ_IDX_BITS-1:0]           NEW
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
    logic        is_rvc;   // 16-bit encoding
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
fault at that slot. The FAULT CODE IS NOT CARRIED HERE. The
architectural exception travels with the instruction stream to the
backend, which is where it is taken. The FTQ needs only to know that
the block ended early so it stops requesting and stops predicting
past it.

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
  W4  restores the history pointers and the RAS snapshot from this
      entry, the same restore a p2 or p3 redirect performs
      (ftq_decisions.md 3.2).
```

NO PREDICTOR UPDATE IS FORMED FROM PREDECODE. Updates remain
post-execute (FE-8, `fe_decisions.md` 7.1). A structural mispredict
here is corrected in the entry; the predictors learn it when the
branch resolves, and the section 4.2.1 R2 rule already handles a
classification that disagrees with the resolved type. Forming an
update here would give the predictors two producers in different
orders and break FE-6.

The FTQ does not need the writeback to free an entry. Deallocation is
FE-U7 and remains open.

---

## 8. Open items

```
  1. ICache path. DECIDED 2026-08-19: pacino defines NO logical
     ftq_icache interface. The ICache is encapsulated behind the
     IFU. If physical design later needs the FTQ address earlier, a
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

  3. Entry fields. bp_ftq_entry_t carries no fetch state: no
     request-issued bit, no writeback-received bit, no fault bit.
     All three become necessary once this interface is built. They
     are NOT added to ftq_entry_formats.md yet, because the FTQ
     allocation and deallocation policy that would read them is
     still FE-U7.

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
                     Here the prediction block is 8 positions and 16
                     is the PREDECODE width, RVC granularity over a
                     32-byte block. The two are different quantities
                     that happen to share a value.

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
```
