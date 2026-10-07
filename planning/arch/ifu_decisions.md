<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Instruction Fetch Unit Decisions
```
 FILE:    ifu_decisions.md
 SOURCE:  session-069
 STATUS:  DRAFT
 UPDATED: 2026-10-06
 CONTACT: Jeff Nye
```

Owns the IFU-N, TD-IFU-N and IFU-UN registries. The numbers are
issue order and the sections are topical, so they do not run in
numeric order: IFU-5 follows IFU-1 in section 1, IFU-4 follows
TD-IFU-5 in section 3, and IFU-23 is in section 7 after IFU-23a to
IFU-27 in 5.1. Session-072.

Scope is the IFU. Its boundaries are held elsewhere:
`ftq_ifu_interfaces.md` upstream, `l1i_ifu_interfaces.md` for the
instruction side, `itlb_ifu_interfaces.md` for translation, and
`ifu_ibuf_interfaces.md` downstream. TD#116 closes on this
document as revised session-074; section 8 records the rulings.

---

## 1. Compressed instruction expansion

IFU-1  Compressed instructions are expanded to their 32-bit form
       in the IFU, before the instruction buffer.

Three consequences follow and are not separate rulings.

The ibuf holds uniform 32-bit slots. It does not pack halfwords,
its read and write ports are fixed width, and the only variability
on the write side is how many slots are valid in a cycle.

The IFU owns the straddle. A 32-bit instruction can begin in the
last halfword of a prediction block. The IFU fetches the 17th
halfword (IFU-8), so the instruction completes inside its own block,
and the next block, which begins on its tail, walks from position 1
(IFU-11). Nothing downstream sees a partial instruction. This read
that the IFU holds the leading halfword across the boundary.
Session-074.

The PC is carried per slot. Expansion breaks the correspondence
between slot position and address, because a compressed
instruction advances the PC by two and occupies a full slot.

IFU-1 matches XiangShan, where RVC expansion sits in the IFU ahead
of the IBuffer so the backend decoders see one instruction format.

IFU-5  The IFU presents the ibuf a fixed-width vector of 16 slots
       every cycle with one per-slot enable mask. It does not
       compact. The ibuf compacts on write.

A 32-byte block holds at most 16 instructions, so 16 slots covers
the widest case and the port never changes width. Compaction is a
shift by a variable amount, and doing it in the IFU puts that
shifter in series with expansion and predecode in the same cycle.
Moving it into the ibuf puts it against the write port instead.

One mask, not two. The start-within-range of DCD-12 and the
truncation by the prediction check of IFU-15 are both IFU-internal
and the ibuf needs only the result. `ifu_ibuf_interfaces.md` IB-2
and IB-3.
The port detail belongs to `ifu_ibuf_interfaces.md`.

---

## 2. Slot payload

IFU-2  Each slot delivered to the ibuf is an `ifu_pd_pkt_t`,
       whose fields are `dcd_decisions.md` DCD-16 and
       `ifu_ibuf_interfaces.md` 4: the expanded instruction, its
       start PC, its position within the prediction block, its
       FTQ index, its fault cause, faulting VA and faulting GPA,
       is_rvc, its control flow classification, is_vsetvl and
       needs_vtype. Declared in `bp_structs_pkg`, BP-115.

This read "its position within the buffer" and "its FTQ pointer",
and did not list the faulting VA that IFU-2a refers to. The
position is within the prediction block and the index is
FTQ_IDX_BITS, the value ftq_resolve_t returns. Session-074.

The start PC and the position are both needed and are not the same
thing. Expansion breaks the correspondence between the two,
because a compressed instruction advances the PC by two and
occupies a full slot.

The fault cause is per slot, not per prediction block. `itlb_decisions.md`
ITLB-11 returns one of three causes and the exception has to reach
the backend attached to the instruction it belongs to.

IFU-2a A slot whose cause is an instruction guest-page fault, cause
       20, also carries the faulting GUEST PHYSICAL address. It
       comes back on the translation port, IT-6a, because the IFU
       never had it. Shtvala requires `htval` to be written with
       it. The virtual address of IFU-2 is still carried for
       `stval` and `vstval` under Shvstvala.

H is mandatory in RVA23 through Sha, so the guest case is not
optional and the GPA field is not conditional on a build option.

TD-IFU-1  CLOSED by `dcd_decisions.md` DCD-16 and BUILT by
          BP-115. The bundle view is a NEW struct, `ifu_pd_pkt_t`,
          in `bp_structs_pkg`; `predecode_pkt_t` in `decode_pkg.sv`
          is not changed and is retired with decode's move to the
          new struct, TD#143. This read that DCD-16 redefines
          `predecode_pkt_t` and that a `decode_pkg.sv` edit
          remained. Session-074.

          `predecode_pkt_t` in `decode_pkg.sv` carries valid, the
          32-bit instruction, three vtype annotations and a branch
          hint. It has no PC, no FTQ index, no fault cause and no
          faulting VA, and nothing else in the package carries
          them. IFU-2 requires all four and they are additions.

---

## 3. Predecode

The predecode correction is written back to the FTQ from the IFU
and `ftq_ifu.sv` is Complete including that writeback, so the
boundary this section specifies already exists in RTL.

IFU-3  Predecode is in the IFU and is specified in this document.

Decode has no planning document because it is close to a direct
translation of the RISC-V specification. Predecode is not in that
specification, so it has no home there and would otherwise have
none at all.

TD-IFU-5  CLOSED by `dcd_decisions.md`. The predecoder is written
          fresh from that document and neither `predecode.sv` nor
          the old `predecode_pkt_t` constrains it. Retained for
          the record.

          `predecode.sv` as built does not do what IFU-16
          requires. Its output struct carries `may_be_branch`,
          documented as a conservative hint set on the JAL, JALR
          and BRANCH opcodes with full resolution deferred to
          decode, and it is 8 slots wide. IFU-16 needs a 2-bit
          type separating conditional from JAL from JALR, plus
          is_call and is_ret, plus a computed target, across the
          16 positions of `ftq_pd_info_t`. The built module is a
          decode-side helper and the one specified here is a
          different module. Its location under
          `rtl/core/frontend/decode/` is a path and not the
          issue.

IFU-4  Expansion runs before predecode. Predecode operates on the
       expanded buffer and recognises base-ISA branch encodings
       only.

Expansion does not need to know where instructions start. At each
2-byte position the four bytes beginning there are taken, and the
low bits of that position alone decide whether a compressed
instruction is expanded or a 32-bit one passes through. Every
position expands independently, so the start mask and the
expanders run in parallel.

The gain is in predecode. On the expanded buffer it recognises
JAL, JALR, BEQ and BNE and not also C.J, C.JAL, C.JR, C.JALR,
C.BEQZ and C.BNEZ.

XiangShan orders these the other way, predecode at F2 and
expansion at F3, and its predecode therefore carries both the
instruction-start and RVC detection and the branch
classification. IFU-4 splits those: the start mask is computed
separately and predecode keeps only the classification.

---

## 4. Straddle

A 32-bit instruction can begin in the last halfword of one
prediction block and end in the next. Because RVC makes instructions 2-byte
aligned, this also happens at a line boundary and at a page
boundary, so the second half can miss, can translate differently,
and can fault on its own.

IFU-6  The prediction block is not aligned. It begins at the
       predicted target, which is any 2-byte address.

IFU-7  The IFU fetches two cache lines when the block start falls
       in the upper half of a line, and one otherwise.

IFU-8  The IFU covers 34 bytes, not 32: the 32-byte block plus
       the 2 bytes a straddling 32-bit instruction takes from the
       line after it. That is 17 halfword positions. Only the
       first 16 can be instruction starts, so IFU-5 stays at 16
       slots.

IFU-6 is the XiangShan arrangement and IFU-7 and IFU-8 follow from
it rather than being separate choices. An unaligned block starting
in the upper half of a line runs past the line end, so the second
line is needed for the ordinary case, not the edge case.

The second line is a separate translation. It can be in another
page, so it can hit in the ITLB when the first missed, fault when
the first did not, and arrive at its own time.

The fault raised on the second half belongs to the instruction
that started in the first. XiangShan carries an exception mask on
its IFU-to-IBuffer boundary that can mark the first instruction of
either prediction block for this reason. XiangShan's "fetch block" is
its 32-byte prediction block, not pacino's 64-byte fetch block
(fe_decisions.md Conventions). Session-071.

---

## 5. Pipeline

IFU-9  Five stages: F0, F1, F2, F3 and WB. This is the XiangShan
       segmentation.

IFU-10 Stage contents.

       F0  Accept the FTQ request. Read the translation queue
           head, IFU-25. Issue the L1I request with the physical
           address it supplies, two requests under IFU-7, or none
           when the block's line matches the previous request
           (TD-IFU-8) or the translation faulted (IF-23).
       F1  Compute the PC of every 2-byte position in the block.
           The cache access is in flight.
       F2  L1I data returns. Check it against the request, form
           the per-instruction fault information from the line's
           fault information, compute the jump and fall-through
           ranges, and select the 17 halfword positions of
           IFU-8.
       F3  Expand, predecode, check the prediction, mask, and
           present the slot vector of IFU-5 to the ibuf.
       WB  Write the predecode correction back to the FTQ.

F0 does NOT start a translation. Translation happens in a separate
pipeline that runs ahead of this one, section 5.1. L1I-3 makes the
L1I physically indexed with translation complete before the array
is indexed, so a request issued in the same cycle the lookup began
would carry an address that does not exist yet. IF-8 says the same
from the other side. An earlier revision of IFU-10 did exactly
that.

IFU-11 A 32-bit instruction starting at position 15 completes in
       its own block from the 17th halfword (IFU-8, DCD-2). F3
       holds a register with the address of that tail. A block
       whose start equals it begins its walk at position 1
       (DCD-5). The tail's translation and fault are its own
       block's second result when the straddle crosses a page
       (IFU-25).

       RULED session-074 (Jeff), as BP-116 built it. This read
       that the register holds the leading halfword, its PC and
       its fault, and that the instruction completes in the next
       block. That contradicted IFU-8, and an instruction carried
       into the next block would sit at position -1, which
       ifu_pd_pkt_t.pos cannot express.

`L1iReadLatency` is 2, so F1 and F2 are mostly the wait for data.
That is why five stages carry what BOOM does in four: BOOM's
fetchWidth is 4 or 8 instructions and pacino is 16 positions over
a 32-byte block, so its F3 work does not compress the same way.

IFU-12 Expansion stays in F3. F3 holds expansion, predecode, the
       prediction check and the mask.

IFU-4 puts expansion ahead of predecode, the reverse of XiangShan,
so F2 and F3 do not hold what XiangShan's do. Expansion is a mux
per position and predecode on expanded encodings is a narrow
decode. The prediction check is a priority encode over the 16
positions to find the earliest control flow instruction, feeding
a 40-bit target compare, target[VA_WIDTH-1:1] at VA_WIDTH 41
(fe_decisions.md FE-19, TD-FE-3), and a 4-bit position compare.
This read "a 39-bit target compare", the floor computed against the
retired 40-bit address. Session-071. F2 keeps
the data return, the fault information and the position select.

### 5.1 The translation pipeline

IFU-23a The IFU has two decoupled pipelines. The TRANSLATION
        pipeline runs ahead and produces physical addresses. The
        FETCH pipeline of IFU-10 consumes them. A queue joins
        them.

IFU-24  The translation pipeline is driven by its own pointer
        into the FTQ, ahead of the pointer the fetch pipeline
        uses. It reads a block's start PC, performs the ITLB
        lookup of `itlb_ifu_interfaces.md`, and enqueues the
        result.

IFU-25  The translation queue holds, per block: the physical
        address, the PMA attributes of IT-10, the fault cause and
        status of IT-4, and the guest physical address of IT-6a
        when the cause is 20. F0 reads the head.

        A BLOCK THAT CROSSES A PAGE HOLDS TWO RESULTS in its one
        entry: the second page's physical address, PMA attributes,
        fault cause and GPA, valid only for a crossing block and
        filled by a second ITLB lookup in the next cycle. A fault
        on the second page belongs to the positions in it (DCD-15).
        Ruled session-074 (Jeff). Ending blocks at page boundaries
        instead would change built BPU and FTQ block semantics for
        an event on well under 1% of sequential blocks.

IFU-26  A block whose effective type is not both cacheable and
        idempotent is marked in the queue and is not issued to the
        L1I. It takes the uncached path of IFU-21. MMU-14 and IT-11;
        the effective type includes the PTE's PBMT
        (mmu_decisions.md MMU-U6). This read "translates to a
        non-idempotent region". Session-071.

IFU-27  On a redirect both pipelines are flushed of everything at
        or after the flush index (ftq_ifu_interfaces.md 5). The
        fetch pipeline then stalls until the translation pipeline
        refills the head. As built by BP-116 a flush clears ALL
        state and is legal only with nothing outstanding; that is
        the TD#134 stub. Clearing all is wrong once an entry older
        than F can be held. This read "the queue is emptied".
        Session-074. How the flush is applied with requests in
        flight is ruled as IFU-28 to IFU-32, section 6.1
        (session-075, TD#134), unbuilt.

        THE COST DEPENDS ON WHETHER F ALREADY HAS CONTENT. From the
        redirect cycle to the first cycle the FTQ presents the
        translation request for the flush index F:

```
          p2, p3          1 cycle     not measured
          predecode       2 cycles    BP-117, tb_ftq G5
          backend         2 cycles    BP-113, tb_ftq G11, G16
```

        For a backend redirect, and for a predecode redirect since
        BP-117 put F at K+1, F is the redirect target block and its
        p1 content write lands at the end of the redirect cycle, so
        there is nothing to translate until then. A p2 or p3
        redirect corrects K, which already has content; that row
        is inferred, since tb_ftq drives no p2 or p3 redirect.
        ftq_decisions.md 5.1 carries the same table.

        This read "front-end (p2, p3, predecode) 1 cycle" from
        BP-113, measured while predecode still flushed at K.
        Before that, "at least one cycle" for both. Session-075.

This is the XiangShan arrangement with one part left out.
XiangShan's IPrefetchPipe queries the MetaArray and the ITLB and
writes hit way, ECC and exception information into a WayLookup
queue for MainPipe to read, and it documents the same reset and
redirect cost: WayLookup is empty, the prefetch and fetch pointers
reset together, and MainPipe stalls one extra cycle.

WHAT IS LEFT OUT, AND THIS IS A CHOICE. XiangShan puts the
prefetch pipeline inside the ICache and queues the hit WAY along
with the translation, so its main pipe reads the data array with
the way already resolved. Pacino's L1I is EMITTED by cachegen.
Putting a second pipeline, an ITLB client and a lookup queue
inside it is a cachegen change of the class INFRA-012 sized for
one node: 4 configuration, 5 schema, 8 emitter items. So the
translation pipeline is placed in the IFU instead, the L1I is
unchanged and still receives a physical address on the
`l1i_ifu_interfaces.md` port, and the queue holds translation
only, not the hit way.

The cost of that choice is that the L1I tag compare stays in the
fetch path where L1I-5 puts it, so the way is resolved during
F1 and F2 rather than ahead of F0. The benefit is that nothing in
the emitted L1I changes.

IFU-U5 CLOSED session-074 (Jeff). The translation queue depth is
       a parameter, default 4. An entry frees when its block enters
       F1, whether it issued a request, reused the previous line or
       faulted; the translation result travels with the block.
       Freeing on data return would make the queue cover everything
       in flight, up to 32 blocks at a line buffer of 16. Four
       covers the one-cycle ITLB hit of ITLB-5 at one block per
       cycle. A longer hit would cut throughput whatever the
       depth: the one-bit tag of IT-2 allows one block at the ITLB
       at a time. Translation stays in order, IT-14. XiangShan
       exposes theirs as nWayLookupSize.

The FTQ side is `xlate_ptr`, ftq_decisions.md 5.1, and the port is
ftq_ifu_interfaces.md 4.1. Both were written session-069 with this
section. FQ-1 becomes commit_ptr <= fetch_ptr <= xlate_ptr <=
alloc_ptr.

---

## 6. Prediction check and writeback

`ftq_ifu.sv` is Complete and is the FTQ half of this boundary, so
this section records a contract rather than deciding one. The
port names are its port list.

IFU-13 The IFU reports, it does not redirect. There is no
       IFU-to-FTQ redirect port. The FTQ derives the redirect
       from the writeback, which keeps one producer for the fact.

IFU-14 The writeback carries, per block: `pdwb_val`, `pdwb_idx`,
       `pdwb_gen`, a `ftq_pd_info_t` for each of `FTQ_PD_WIDTH`
       positions, `pd_range`, `cfi_val` and `cfi_pos`, `mis_val`
       and `mis_pos`, `target`, `fault_val` and `fault_pos`.

IFU-15 `cfi_pos` and `mis_pos` are different facts. `cfi_pos`
       names the first control flow instruction predecode found.
       `mis_pos` names the position that failed the check. They
       coincide in one of the four mispredict cases and not in
       the others.

IFU-16 Predecode emits, per position: valid, a 2-bit type where
       00 is not a control flow instruction, 01 a conditional
       branch, 10 JAL and 11 JALR, plus is_call and is_ret.

IFU-17 Predecode computes a target for direct branches and JAL.
       For JALR the target field carries no meaning and the FTQ
       does not read it.

IFU-18 Predecode proves a direction only for an unconditional
       branch. It cannot know a conditional's direction, TAGE and
       SC own that, and the entry's prediction stands.

IFU-19 The generation bit issued with the request is carried
       through the IFU and returned with the writeback. A
       writeback whose bit does not match is dropped entirely.

IFU-20 On a flush the IFU drops every in-flight fetch whose index
       is at or after the flush index and discards everything it
       holds for those entries. A request presented in a flush
       cycle is ignored (ftq_ifu_interfaces.md 5, TD#138). Both
       pipelines of IFU-23a are flushed by the one group. This read
       that the flush applies first and that request is the first
       fetch of the corrected stream. Session-074.

IFU-20 is load-bearing beyond the IFU. The generation tag is one
bit, and one bit is only sufficient because a stale writeback
cannot outlive the flush cycle. If the IFU ever holds a writeback
longer than that, the tag width has to be revisited.

### 6.1 How the flush is applied -- TD#134

RULED session-075 (Jeff). UNBUILT; BP-118. IFU-28 to IFU-32 say how
IFU-20 is met with requests still in flight. Until they are built a
flush clears all IFU state and is legal only with nothing
outstanding (IFU-27, the BP-116 stub). Clearing all is wrong because
the FTQ does not rewind fetch_ptr or xlate_ptr past an entry older
than the flush index F (ftq_decisions.md 5.5 R1), so a block older
than F that the IFU drops is never presented again.

IFU-28 SURVIVAL. A block SURVIVES a flush when it is older than F,
       measured from the commit pointer: with
       age(i) = (i - ftq_ifu_commit_ptr) mod FTQ_DEPTH, a block with
       FTQ index i survives when age(i) < age(F). Every block the
       IFU holds is at or after commit_ptr, because an entry commits
       only after its instructions have left the IFU, so the age is
       well defined without a wrap bit. Surviving blocks continue in
       every structure: both pipelines, the translation queue and
       the line buffer. Non-surviving blocks are dropped from all of
       them in the flush cycle. RC_UNSPEC, where F is commit_ptr,
       drops everything with no special case.

IFU-29 L1I RESPONSES FOR DROPPED BLOCKS. The L1I has no cancel and
       the IFU accepts every response (l1i_ifu_interfaces.md IF-10).
       At the flush, every in-flight request identifier whose blocks
       all fail IFU-28 is marked KILLED. When a killed identifier's
       response arrives its data is discarded, and the identifier
       and its line buffer slot are freed as for any response
       (IF-11). No generation counter is needed: an identifier
       cannot be reissued while it is in flight (IF-6), so a killed
       identifier cannot be confused with a later request.

IFU-30 A SHARED LINE BUFFER SLOT. A slot that serves more than one
       block (TD-IFU-8, IF-7) survives when any block it serves
       survives; the blocks that fail IFU-28 are removed from it.
       Blocks are taken in order, so the removal is one cut at the
       first non-surviving block.

IFU-31 ITLB LOOKUPS IN FLIGHT. ITLB responses have no ready and may
       return out of order under a one-bit tag naming the half of a
       block (itlb_ifu_interfaces.md IT-2, IT-3, IT-14). When the
       block being translated fails IFU-28, its outstanding lookups
       are DEAD: their responses are dropped, and translation of a
       new block does not start until every dead lookup has
       answered, so a tag value is never shared between a dead and
       a live lookup. When the block being translated survives,
       translation continues. How long the wait lasts is the
       ITLB's miss latency, a property of the ITLB and not of the
       IFU; a testbench model of the ITLB answers when the
       stimulus says and so cannot measure it. What the IFU must
       guarantee is that translation of a new block starts the
       cycle after the last dead lookup answers, and not before.
       This read "BP-118 measures it". Session-075.

IFU-32 THE GENERATION BOUND. After the flush cycle the IFU presents
       no writeback (ftq_ifu_interfaces.md 6) for a block that
       failed IFU-28. This is what keeps one generation bit
       sufficient (IFU-20, ftq_ifu_interfaces.md 6.1), and an
       assertion checks it.

TD#135 (uncached) and TD#136 (maintenance) stay stubbed. A request
presented in a flush cycle is still ignored (IFU-20).

The fault takes two paths and they carry different things. The
architectural exception travels with the instruction to the
backend, which is the fault cause and faulting VA of IFU-2. The
FTQ is told only that the block ended early, which is why
`fault_pos` is declared on the port and not read.

`FTB_BLOCK_BYTES` is 32, so `FTQ_PD_WIDTH` is 16 and
`FTQ_PD_POS_BITS` is 4. The writeback array covers the 16
positions that can be instruction starts. The 17th position of
IFU-8 has no entry and needs none: it can only be the tail of a
straddling instruction, never a start, and it is consumed inside
the IFU.

---

## 7. Uncached fetch

Fetch from a page whose effective type is non-idempotent or
non-cacheable (MMU-14, MMU-U6) cannot use the normal path.
MMU-14 forbids speculating into it, and a memory mapped device
must not see a read for an instruction that is not on the
committed path.

IFU-21 The IFU has a second instruction source for uncached
       fetch, separate from the L1I. The L1I is not involved.

IFU-22 The FTQ drives its commit pointer to the IFU continuously.
       The IFU compares the index of the uncached block against
       it and issues the bus transaction only when every earlier
       instruction has committed.

The IFU cannot learn this any other way. Stopping fetch is what
allows the pipeline to drain, but the drain takes an unknown
number of cycles and the IFU has no way to observe that it has
finished. The FTQ already holds the commit pointer, so what is
added is its export, not the knowledge.

The FTQ cannot gate the request instead. Whether a block is
uncached is learned in the IFU's translation pipeline, from the PMA
result, and marked in the queue entry (IFU-25, IFU-26), after the
FTQ has handed the translation request over. This read "from the
PMA result at F2". Session-074.

IFU-23 Uncached fetch returns one instruction at a time. It is
       sent to the ibuf alone, and the IFU waits for it to commit
       before issuing the next.

TD-IFU-4  CLOSED. `ftq_ifu_commit_ptr` was added to the fetch
          request group by BP-114 (TD#142). It is a driven value,
          not a query with a response, so it adds no handshake.
          This read that ftq_ifu.sv has no commit pointer output.

IFU-U4 Bus width and the split it forces. XiangShan's MMIO bus is
       8 bytes and aligned, so a 32-bit instruction whose address
       ends in 3'b110 takes two transactions, and the second
       needs its own ITLB lookup and PMP check because it can
       cross a page. Pacino's uncached bus width is not set.
       Unresolved.

---

## 8. The line buffer, issue and reordering

Ruled session-074 (Jeff), closing TD#116. These were listed here
as unruled.

TD-IFU-7  CLOSED. The line buffer of `icache_decisions.md` L1I-14
          has a depth that is a parameter, default 16 =
          MAX_OUTSTANDING. One slot is reserved per L1I request
          identifier when it is allocated (`l1i_ifu_interfaces.md`
          IF-7), because the response carries no ready and must
          always have somewhere to land. Size it later with the
          TD#128 harness. What a redirect does to it is IFU-29
          and IFU-30 (TD#134).

TD-IFU-8  CLOSED. Issue is in order, oldest first, whenever a
          translated block, a free identifier and a free slot all
          exist. A block whose line matches the PREVIOUS request
          reuses that request's line-buffer slot and makes no
          request; it shares no identifier, which may already be
          retired. A slot frees when its last block is consumed.
          One comparator catches the common case, consecutive
          blocks in one line. So two
          sequential blocks make one L1I request, and what merges
          in the L1I MSHRs is a redirect back to a line in flight
          or a non-consecutive repeat.

TD-IFU-9  CLOSED. The reordering store of TD-IF-5 is the line
          buffer itself, consumed in allocation order. A response
          lands in the slot its identifier reserved; F2 takes slots
          in order. No separate structure, and the identifier free
          list bounds it.

TD-IFU-10 MOVED to TD#136. The maintenance path of
          `l1i_ifu_interfaces.md` 11; its producer is the backend
          commit stage, which has no document. Section 7 here
          covers uncached fetch, not this.

---

## 9. Open

IFU-U4  Uncached bus width. Section 7.
IFU-U6  Instruction prefetch. L1I-19 puts the requester in the IFU
        and ftq_decisions.md 6.1 defers prefetch. Nothing is built;
        ifu_l1i_req_prefetch is driven 0. DEFERRED, session-074.

---

## 10. Bindings

ITLB-11   Supplies the fault cause and VA of IFU-2.
M1 to M4  The four mispredict tests are the IFU's to make. M4,
          a predicted taken position outside the fetched range,
          is named explicitly in `ftq_ifu.sv` as the IFU's test.
DCD-*     The predecoder of IFU-3 and IFU-16 is specified in
          `dcd_decisions.md`. This document states where it sits
          and what it must produce; that one states how.
IB-*      The ibuf boundary is `ifu_ibuf_interfaces.md`.
IT-*      The translation boundary is `itlb_ifu_interfaces.md`.
          Its requester is the translation pipeline of IFU-24,
          not the fetch pipeline.
L1I-3     PIPT. The reason F0 cannot start a translation.
L1I-5     2-cycle hit, tag compare after the array read. Stays
          in the fetch path under the IFU-23a placement.
MMU-14    Requires the uncached path of section 7.
IFU-7     Two lines means up to two ITLB lookups per block.
          `itlb_ifu_interfaces.md` carries both.
IF-8      NOT amended. It is a gate condition -- issue only on a
          valid non-faulting translation -- and stands as written;
          the three causes and the VA are behind it at IF-23 and
          IF-24 (itlb_decisions.md 5). This read "Amended by
          TD-ITLB-1, single non-faulting condition becomes two
          causes plus the VA": no TD-ITLB-1 was ever issued in the
          registry itlb_decisions.md owns, and two causes is three.
          Session-072.
TD#116    Closed by section 8, session-074.
TD#136    Carries TD-IFU-10.
TD#118    The IFU outstanding-request depth has no real target
          until the l2 transaction limit is known. Not yet
          recorded as a decision.
