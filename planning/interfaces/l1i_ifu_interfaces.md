<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# L1I to IFU Interface
```
 FILE:    l1i_ifu_interfaces.md
 SOURCE:  icache_decisions.md, ftq_ifu_interfaces.md, INFRA-012,
          TOOLS-003, tools/cachegen schema and testcases/pacino
 STATUS:  DRAFT
 UPDATED: 2026-09-01
 CONTACT: Jeff Nye
```

The L1I's core interface, and the maintenance path that reaches it.
`icache_decisions.md` section 4 states the SHAPE of the core boundary
and stops: one full 64-byte line per request, sixteen outstanding,
out-of-order response carrying an identifier. There is no port list,
no handshake, no backpressure rule and no maintenance path. This file
is those four.

DIVISION OF LABOUR. `icache_decisions.md` specifies BEHAVIOUR and
this file specifies PORTS. Where a behaviour is already decided there
it is cited by its L1I number and not restated.

Every port here is NEW. No module on either side exists:
`rtl/core/frontend/ifu/rtl` holds only a .gitkeep, and the L1I is a
generated module whose emitter cannot yet produce any of this
(TD-L1I-8).

---

## 1. Scope

Covered:
- the fetch request, IFU to L1I
- the line response, L1I to IFU
- backpressure, the outstanding limit and merging
- the maintenance request, IFU to L1I, and its completion
- the maintenance request that reaches the IFU from the backend
- what a cachegen link definition can and cannot express of the above

Not covered:
- L1I internals. Geometry, replacement, MSHR structure and the
  memory-side link are `icache_decisions.md` 1, 3, 5 and 6
- the IFU line buffer's depth and redirect behaviour, which is
  L1I-U5 and belongs to `ifu_decisions.md`
- the ITLB. Named in `icache_decisions.md` 2.3 as T1, T2 and T3;
  owned by `itlb_decisions.md`, which does not exist
- the FTQ to IFU boundary, which is `ftq_ifu_interfaces.md` and is
  neither contradicted nor duplicated here
- prefetch policy. L1I-19 puts the requester at the IFU, so the
  choice of what to prefetch is IFU-internal. The request itself
  DOES cross this boundary and carries one bit; section 4.4

REGISTRIES. This file owns IF-1 upward for its decisions and its
protocol rules, IF-U1 upward for open items, and TD-IF-1 upward for
technical debt. It does not use IC-, which is an interface-check
identifier in `ftb_interfaces.md` and `sc_interfaces.md`; it does not
use L1I-, which is `icache_decisions.md`; and it does not use FE-,
TD-FE- or FE-U, which are `fe_decisions.md`.

---

## 2. Naming

The IFU pipeline is not defined, so there are no stage suffixes, for
the same reason and with the same intent as `ftq_ifu_interfaces.md`
section 2. Ports are named by direction.

```
  ifu_l1i_<signal>    IFU -> L1I
  l1i_ifu_<signal>    L1I -> IFU
  cmt_ifu_<signal>    backend commit -> IFU, section 11
  ifu_cmt_<signal>    IFU -> backend commit
```

When the IFU pipeline is defined, add the stage suffix and record the
rename here.

---

## 3. Widths

```
  IF-1   The core interface carries a PHYSICAL BYTE address,
         PA_WIDTH bits wide. L1I-4. PA_WIDTH is 36, ruled
         session-068, and this file uses no other value.

  IF-2   The request identifier is REQ_ID_BITS wide, 4 bits, giving
         sixteen identifiers, one for each of the sixteen
         outstanding requests of L1I-10.

  IF-3   The response data path is one full cache line,
         L1I_LINE_BITS = 512. L1I-9. There is no narrower response
         and no partial line.
```

### 3.1 The parameters do not exist yet

`bp_defines_pkg.sv` carries `VA_WIDTH` (40) and `FETCH_BLOCK_BYTES`
(64) and carries NO PHYSICAL ADDRESS WIDTH AT ALL. The 36 of IF-1
lives today only in `tools/cachegen/testcases/pacino/
pacino_topology.json`, as `addressing.pa_bits`.

The IFU is hand written and reads `bp_defines_pkg`. The L1I is
generated and its constants are in `l1i_pkg`, under a different
naming convention. The two must agree and nothing makes them.

```
  this file        bp_defines_pkg     l1i_pkg         value
  ---------------- ------------------ --------------- -----
  PA_WIDTH         ABSENT, TD-IF-1    L1iPaBits          36
  L1I_LINE_BYTES   ABSENT, TD-IF-1    L1iLineBytes       64
  L1I_LINE_BITS    ABSENT, TD-IF-1    L1iLineBits       512
  L1I_OFFSET_BITS  ABSENT, TD-IF-1    L1iOffsetBits       6
  REQ_ID_BITS      ABSENT, TD-IF-1    (no counterpart)    4
  MAX_OUTSTANDING  ABSENT, TD-IF-1    (no counterpart)   16
```

`l1i_pkg` has no counterpart for the last two because the emitter
does not consume `outstanding_requests` or `id_width_bits` at all
(INFRA-012 E2 and E3, confirmed by TOOLS-003). Section 14 says which
of these a configuration change can supply and which cannot.

ADDING THESE PARAMETERS IS NOT THIS FILE'S ACT. This file is a
specification and writes no RTL. TD-IF-1 carries the addition.

---

## 4. The fetch request, IFU to L1I

### 4.1 Ports

```
  ifu_l1i_req_val                              NEW
  ifu_l1i_req_rdy                              NEW   L1I -> IFU
  ifu_l1i_req_id      [REQ_ID_BITS-1:0]        NEW
  ifu_l1i_req_paddr   [PA_WIDTH-1:0]           NEW
  ifu_l1i_req_prefetch                         NEW   L1I-21
```

Five wires and two buses. There is no read/write strobe, no write
data and no byte enable: the L1I is read only (L1I-15, section 7 of
`icache_decisions.md`), so a request is always a read and a field
saying so would carry one constant value.

### 4.2 Rules

```
  IF-4   A request is presented when ifu_l1i_req_val is high, and is
         ACCEPTED in a cycle where ifu_l1i_req_val and
         ifu_l1i_req_rdy are both high. The IFU holds req_id and
         req_paddr stable from the cycle val rises until the cycle
         of acceptance.

  IF-5   ifu_l1i_req_paddr is LINE ALIGNED: paddr[L1I_OFFSET_BITS-1:0]
         is zero in every accepted request. 4.3 R1. The L1I does not
         mask the low bits and does not check them in synthesis; the
         L1I testbench asserts on them and the check is on the L1I
         side, not the IFU side, so an IFU defect is caught at the
         boundary it crosses.

  IF-6   ifu_l1i_req_id is allocated by the IFU from a free list of
         MAX_OUTSTANDING identifiers. An identifier is IN FLIGHT
         from the cycle its request is accepted until the cycle its
         response is presented. The IFU MUST NOT present an
         identifier that is in flight.

  IF-7   Until the response returns, the IFU holds, per in-flight
         identifier: the line buffer slot the response will land in,
         the FTQ index or indices the request serves
         (ftq_ifu_start_pc and ftq_ifu_idx of
         ftq_ifu_interfaces.md 4), and paddr[L1I_OFFSET_BITS-1:0]
         for the block extract of L1I-14. The RESPONSE DOES NOT
         RETURN THE ADDRESS, so the low offset bits exist only in
         the IFU and nowhere else.
```

WHY THE FULL BYTE ADDRESS AND NOT PA[35:6]. Six of the thirty-six
wires carry a constant zero by IF-5, and dropping them would save
them. Rejected. The ITLB delivers a byte physical address (2.3 T1)
and the IFU's own block extract is byte granular, so a line-granular
port would make the L1I's address a different quantity from every
other address in the front end and put a shift at the boundary. It
would also turn IF-5 from a checkable rule into a structural
property, and a rule a testbench can check is worth more than six
wires. The cachegen schema CAN express the rejected form
(`address_granularity` takes `line` beside `byte`), so this is a
choice and not a limitation; section 14 records it.

### 4.3 What the IFU must have before it issues

```
  IF-8   The IFU issues a request only when the ITLB has returned a
         VALID, NON-FAULTING physical translation for it (2.3 T1 and
         T2). An ITLB miss and an ITLB fault both mean NO REQUEST IS
         PRESENTED. Section 8 states what happens instead.
```

### 4.4 Prefetch uses this port

```
  IF-9   An IFU-originated prefetch (L1I-19) is presented on the
         ports of 4.1 with ifu_l1i_req_prefetch high. It consumes
         an identifier, it is answered with a line, and the IFU
         discards the line.

  IF-38  THE BIT AFFECTS ONLY ready. A prefetch is refused unless
         at least L1I-22's TWO MSHRs are free; see IF-39. Once
         accepted it is answered like any other request, on the
         same identifier space, with the same response and the
         same latency, and a miss remains invisible (IF-19).
```

`icache_decisions.md` 8.1 splits across the boundary. P1, demand
fetch always wins, is the IFU choosing which of its own requests to
present and this interface does not see it. P2 NAMES MSHR STATE,
AND ONLY THE L1I HOLDS MSHR STATE, so the bit exists to let the L1I
enforce it. P3, a dropped prefetch is not retried, is the IFU's
response to a refusal.

WITHOUT THE BIT the IFU would have to throttle on its own
outstanding count, which is a proxy for MSHR occupancy and a poor
one: merged requests occupy one MSHR and the IFU cannot tell.

---

## 5. The response, L1I to IFU

### 5.1 Ports

```
  l1i_ifu_rsp_val                              NEW
  l1i_ifu_rsp_id      [REQ_ID_BITS-1:0]        NEW
  l1i_ifu_rsp_data    [L1I_LINE_BITS-1:0]      NEW
  l1i_ifu_rsp_err                              NEW
```

There is no `l1i_ifu_rsp_rdy`.

### 5.2 Rules

```
  IF-10  A response is presented when l1i_ifu_rsp_val is high. THE
         IFU ACCEPTS IT IN THAT CYCLE UNCONDITIONALLY. There is no
         ready and no retry.

  IF-11  l1i_ifu_rsp_id names the request the response answers, and
         that identifier is retired by the presentation: it returns
         to the IFU's free list and may be reissued in the next
         cycle.

  IF-12  Responses MAY be presented IN ANY ORDER with respect to the
         requests that produced them. 4.3 R2. The identifier is the
         ONLY correlation; the IFU must not infer order from
         anything else.

  IF-13  At most ONE response is presented per cycle.

  IF-14  A response naming an identifier MUST NOT be presented in the
         cycle that identifier's request is accepted. The minimum
         request-to-response separation is one cycle.
```

WHY NO READY ON THE RESPONSE. The IFU reserved the line buffer slot
when it allocated the identifier (IF-7), so it always has somewhere
to put the data and a ready it could deassert would be a ready it
never deasserts. Adding one would need a second holding register in
the L1I for the response the IFU refused, and that register can fill
while an MSHR waits to retire into it, which is a deadlock the
identifier scheme otherwise cannot have. THE IDENTIFIER FREE LIST IS
THE FLOW CONTROL, and putting a second flow control beside it is what
makes the two able to disagree.

WHY IF-14, AND WHY IT COSTS NOTHING. L1I-5 puts hit latency at two
cycles, so a same-cycle response is already impossible at this
geometry. Forbidding it makes the rule survive a later latency
change and keeps the IFU from having to allocate and retire one
identifier in one cycle. The cachegen link schema names this choice
directly: `handshake.read_data_return` takes `same_cycle` beside
`valid_flag` and `valid_with_id`, and this link declares
`valid_with_id`.

### 5.3 rsp_err

```
  IF-15  l1i_ifu_rsp_err high with l1i_ifu_rsp_val means the refill
         that answered this request returned an ERROR FROM THE
         MEMORY SIDE. l1i_ifu_rsp_data is then undefined. It is NOT
         a translation fault and never can be: section 8.
```

The L1I has no exception behaviour of its own beyond what the L2
returns (`icache_decisions.md` 2.3). On the TL-UH link of L1I-16
that is `d_denied` or `d_corrupt`. The IFU turns it into an
instruction access fault at the fetch block that requested the line,
and reports it through `ifu_ftq_fault_val` and `ifu_ftq_fault_pos`
(`ftq_ifu_interfaces.md` 6), which is the same path a translation
fault takes. THE FAULT CODE DIFFERS AND IS NOT CARRIED HERE, for the
reason `ftq_ifu_interfaces.md` 6 already gives: the architectural
exception travels with the instruction stream to the backend.

---

## 6. Backpressure and the outstanding limit

```
  IF-16  ifu_l1i_req_rdy is the L1I's only backpressure. It may be
         deasserted for any internal reason: the array port is busy
         with a fill, the MSHR file cannot take the request (section
         7), or a maintenance operation is in flight (section 10).

  IF-17  ifu_l1i_req_rdy MUST NOT depend combinationally on
         ifu_l1i_req_val. IF-40 makes it independent of
         ifu_l1i_req_paddr as well.

  IF-18  A SEVENTEENTH OUTSTANDING REQUEST CANNOT BE PRESENTED. IF-6
         makes the identifier free list the limit, and sixteen
         identifiers cannot name a seventeenth request. The L1I
         carries an assertion that no accepted identifier is already
         in flight, and that assertion is the whole of its
         seventeenth-request handling. It has no counter and no
         recovery path.

  IF-39  THE PREFETCH RESERVE. ifu_l1i_req_rdy is low for a request
         with ifu_l1i_req_prefetch high whenever fewer than TWO of
         the sixteen MSHRs are free. L1I-22. A demand request is
         unaffected by the reserve and may take the last MSHR.
         This is the ONLY place the prefetch bit is read.
```

THE PORT COUNT AND THE MSHR COUNT ARE THE SAME NUMBER by L1I-10 and
L1I-12, so the identifier space and the miss-tracking capacity are
the same size and neither can exhaust before the other. That is why
IF-18 needs no arithmetic: a request can only miss if it is
outstanding, and there are exactly as many MSHRs as identifiers.

---

## 7. Misses and merging

```
  IF-19  A MISS IS NOT VISIBLE ON THIS INTERFACE. There is no hit
         indication, no miss indication and no way to distinguish
         the two other than by counting cycles. A miss is latency.

  IF-20  Two requests naming the same line while the first is in
         flight are MERGED BY THE L1I onto one MSHR (L1I-13, four
         targets). THE REQUESTER SEES NOTHING OF THIS: each request
         is answered separately, in its own cycle, carrying its own
         identifier, with the same 512 bits. Two merged requests
         return over two cycles because IF-13 allows one response
         per cycle.

  IF-21  A request that would need a FIFTH target on one MSHR IS NOT
         ACCEPTED. ifu_l1i_req_rdy is deasserted. The request is not
         queued, not rejected on a response channel, and not
         allocated a second MSHR for the same line.

  IF-40  READY IS COMPUTED CONSERVATIVELY. ifu_l1i_req_rdy is low
         whenever ANY MSHR holds four targets, whatever address the
         request names. Ruled session-068. It does not read
         ifu_l1i_req_paddr, so no address compare is in the ready
         path. Requests to unrelated lines are refused for as long
         as the full MSHR persists.
```

WHY NO HIT INDICATION. It would arrive after the request was issued
and after the identifier was allocated, so there is nothing the IFU
could do with it that it has not already done. The FTQ run-ahead
absorbs the latency (`ftq_decisions.md` 5.1) and the decoupled front
end is what makes that true. A PERFORMANCE COUNTER STROBE is a
different thing and is permitted: an `l1i_ifu_perf_miss` output that
no functional logic reads is outside this protocol and may be added
without changing it. It is named here so that adding it later is not
mistaken for a protocol change.

WHY A SECOND MSHR FOR ONE LINE IS WRONG. Two MSHRs on one line means
two fills of one line, two writes to one set, and a replacement
decision taken twice. The array would end with the line in two ways
or with one fill overwriting the other's way, and neither is a state
the tag compare of L1I-5 can be right about.

WHY REFUSE RATHER THAN REJECT. A reject needs a second response
channel and forces the IFU to re-present, which reorders the fetch
stream against the FTQ entry order `ftq_ifu_interfaces.md` 4 relies
on. Refusing costs cycles and reorders nothing.

IF-40 REFUSES MORE THAN IF-21 REQUIRES. `ifu_l1i_req_rdy` is one
wire and IF-40 does not qualify it by address, so a full MSHR
refuses requests to every other line as well. The cost is
throughput on a pattern the FTQ makes likely; the alternative put a
36-bit compare against sixteen MSHR line addresses in the ready
path and was rejected.

---

## 8. Faults

```
  IF-22  A FAULTING REQUEST NEVER REACHES THE L1I, and this
         interface carries NO FAULT PORT IN EITHER DIRECTION. 2.3 T2
         places the fault path between the ITLB and the IFU, so a
         translation fault is not a cache access.
```

The absence is the specification, so what the IFU does instead is
stated here rather than left to `ifu_decisions.md`:

```
  IF-23  On an ITLB FAULT for a fetch block, the IFU presents no
         request, allocates no identifier, terminates the fetch
         block at the faulting instruction position, and reports it
         with ifu_ftq_fault_val and ifu_ftq_fault_pos
         (ftq_ifu_interfaces.md 6). The L1I is not told.

  IF-24  On an ITLB MISS, the IFU presents no request and allocates
         no identifier. It retries the translation. The ITLB is
         non-blocking and returns miss to the requester;
         L1I-U3.
```

The three fault classes `ftq_ifu_interfaces.md` 6 names for
`ifu_ftq_fault_val` are instruction access fault, page fault and
guest page fault. Two of the three are ITLB-side and reach the FTQ
by IF-23. The third, instruction access fault, has TWO producers: the
ITLB, by IF-23, and the L1I's memory side, by IF-15. They arrive on
different paths and merge in the IFU. Nothing downstream can or needs
to tell them apart.

---

## 9. Reset

```
  IF-25  While rstn is low the IFU holds ifu_l1i_req_val and
         ifu_l1i_inv_val low, and the L1I holds l1i_ifu_rsp_val,
         l1i_ifu_inv_done and ifu_l1i_req_rdy low.

  IF-26  The IFU's identifier free list resets to ALL SIXTEEN FREE.
         No identifier is in flight across reset, and no response is
         presented for a request issued before it.

  IF-27  The L1I may assert ifu_l1i_req_rdy in the FIRST CYCLE after
         rstn deasserts. Its valid bits are a flop file cleared by
         reset (L1I-6), so the array is coherent immediately and
         there is no post-reset walk. The l2 node needs one; the L1I
         does not, and section 3 of icache_decisions.md says why.
```

---

## 10. Maintenance, IFU to L1I

L1I-18 puts the only invalidate path core side, through the IFU, and
supports `invalidate_line` and `invalidate_all` and neither flush.

### 10.1 Ports

```
  ifu_l1i_inv_val                              NEW
  ifu_l1i_inv_rdy                              NEW   L1I -> IFU
  ifu_l1i_inv_all                              NEW
  ifu_l1i_inv_paddr   [PA_WIDTH-1:0]           NEW
  l1i_ifu_inv_done                             NEW   L1I -> IFU
```

ONE GROUP, NOT TWO. `invalidate_line` and `invalidate_all` differ in
one bit of what to do and share every other wire, and IF-28 allows
only one of either in flight, so two port groups would be two ways to
drive one piece of hardware.

There is no flush port. There is nothing to flush: the L1I is read
only, holds no dirty state and has no write path to the L2.

### 10.2 Rules

```
  IF-28  AT MOST ONE MAINTENANCE OPERATION IS IN FLIGHT. The IFU
         presents the next one only after l1i_ifu_inv_done for the
         previous one. There is no maintenance identifier and no
         maintenance queue.

  IF-29  ifu_l1i_inv_all high means invalidate the WHOLE CACHE and
         ifu_l1i_inv_paddr is ignored. Low means invalidate the ONE
         LINE containing ifu_l1i_inv_paddr, in every way of its set.
         The address IS NOT REQUIRED TO BE LINE ALIGNED, unlike
         IF-5: cbo.inval names any address within the block and the
         architecture does not require the software to align it, so
         the L1I masks the offset bits.

  IF-30  FETCH DOES NOT PROCEED WHILE AN INVALIDATE IS IN FLIGHT.
         From the cycle a maintenance operation is accepted until
         the cycle l1i_ifu_inv_done is asserted, the L1I holds
         ifu_l1i_req_rdy low and accepts no new request.

  IF-31  l1i_ifu_inv_done IS NOT ASSERTED UNTIL EVERY FILL THE
         INVALIDATE MUST DEFEAT HAS LANDED OR BEEN DISCARDED, and
         until the clear itself has been applied. Specifically:
           - inv_all waits for EVERY outstanding request to have
             been answered, then clears
           - inv_line waits only for an MSHR whose line matches
             ifu_l1i_inv_paddr, if there is one, then clears
         The responses for those requests ARE STILL PRESENTED on the
         ports of section 5 and the IFU still accepts them by IF-10.
         A drain is not a discard at this boundary.

  IF-32  l1i_ifu_inv_done is one cycle wide.

  IF-42  THE CLEAR TAKES ONE CYCLE. After the drain of IF-31,
         inv_line clears its set in one cycle and inv_all clears
         the array in one cycle. l1i_ifu_inv_done asserts the
         cycle after the clear. Ruled session-068.
```

WHY IF-31 IS THE WHOLE POINT. `icache_decisions.md` 7 M1 says
FENCE.I is "implemented by the reset-branch clear of the flop valid
bits, so it is a single-cycle operation". THE CLEAR IS SINGLE CYCLE
AND THE OPERATION IS NOT. With sixteen requests outstanding, a fill
in flight when the clear happens lands in the array afterwards and
re-validates a line the fence was supposed to remove. FENCE.I is
drain then clear. See section 15, defect D1.

WHY inv_line DRAINS ONLY ITS OWN MSHR. A fill for a different line
cannot re-validate the line being invalidated, so waiting for it buys
nothing. The comparison of `ifu_l1i_inv_paddr` against the MSHR
file's line addresses is the SAME COMPARISON THE MERGE OF IF-20
ALREADY PERFORMS, so this reuses a mechanism rather than adding one.
The alternative, draining everything for both forms, was rejected: a
range invalidation loop would then drain sixteen outstanding requests
per line, and that is a JIT's inner loop.

WHY inv_all DRAINS EVERYTHING. There is no line to compare against.

---

## 11. Maintenance, backend to IFU

FENCE.I and `cbo.inval` are EXECUTED INSTRUCTIONS. Something upstream
must tell the front end, and no document in this tree names that
boundary. This section names it. There is no producer built and no
producer specified, so section 12 lists every assumption this section
makes about it and marks each unverifiable.

### 11.1 The boundary

THE PRODUCER IS THE BACKEND COMMIT STAGE, not execute. Two reasons,
and only the second is decisive.

The weak reason: an invalidate on a wrong path is architecturally
harmless, because an empty instruction cache is always a legal
instruction cache. It costs refills and nothing else.

THE DECISIVE REASON: FENCE.I HAS COMPLETION SEMANTICS. The
instruction is not finished until every prior store is visible to
instruction fetch, and the pipeline restart that follows it must not
begin before that. Something must be able to say WHEN, and only a
stage that can hold the restart can use the answer. Execute cannot;
commit can.

### 11.2 Ports

```
  cmt_ifu_maint_val                            NEW
  cmt_ifu_maint_rdy                            NEW   IFU -> commit
  cmt_ifu_maint_op    [0:0]                    NEW
  cmt_ifu_maint_paddr [PA_WIDTH-1:0]           NEW
  ifu_cmt_maint_ack                            NEW   IFU -> commit
```

```
  cmt_ifu_maint_op    0   MAINT_FENCE_I     whole cache
                      1   MAINT_CBO_INVAL   one line at paddr
```

### 11.3 Rules

```
  IF-33  cmt_ifu_maint_paddr is a PHYSICAL address. cbo.inval names
         a virtual address in rs1; the backend translates it before
         it reaches this port. The IFU performs no translation and
         has no path to the DTLB. See assumption A2.

  IF-34  AT MOST ONE MAINTENANCE OPERATION IS IN FLIGHT ACROSS THIS
         BOUNDARY, for the same reason as IF-28 and with the same
         consequence: no identifier and no queue.

  IF-35  ifu_cmt_maint_ack IS REQUIRED. It is asserted for one cycle
         and only after everything the operation covers is complete:
           - l1i_ifu_inv_done for the operation has been received
           - the IFU's own line buffer (L1I-14) has been cleared,
             see IF-36
         WITHOUT THIS PORT FENCE.I HAS NO COMPLETION SEMANTICS. The
         commit stage would have to guess when to release the
         restart, and any guess is either wrong or a fixed delay
         that pins an L1I latency into the backend.

  IF-36  THE IFU CLEARS ITS OWN LINE BUFFER on MAINT_FENCE_I, and on
         MAINT_CBO_INVAL when the buffer holds the named line. L1I-14
         puts a 64-byte line in the IFU and L1I-18 puts the only
         invalidate path through the IFU, so a fence that clears the
         array and not the buffer leaves a stale instruction line
         the L1I cannot see and cannot be asked about. See section
         15, defect D2.

         THE CLEAR FOLLOWS l1i_ifu_inv_done, NOT THE REQUEST.
         IF-31 drains rather than discards, and IF-10 makes the
         IFU accept every draining response unconditionally. A
         buffer cleared on receipt of the maintenance request is
         therefore repopulated by the next response to land --
         which is D1's defect one layer up, on the structure D2
         exists to cover.

  IF-37  cmt_ifu_maint_val and the fetch request path are
         independent at this boundary. The IFU may still be holding
         in-flight requests when a maintenance request arrives; IF-30
         and IF-31 dispose of them.

  IF-41  cbo.inval REACHES THE I-SIDE. MAINT_CBO_INVAL is driven
         and the port group of 11.2 is live logic. Ruled
         session-068. Section 13 records that the architecture
         does not decide this and pacino must.

  IF-43  MAINT_FENCE_I IS ALSO ROUTED TO THE D-SIDE. The backend
         drives an equivalent operation to the LSU on the same
         instruction. Ruled session-068. ifu_cmt_maint_ack covers
         the I-side only, so the backend gates the post-fence
         restart on both acknowledgements.
```

---

## 12. What this file assumes about the producer

No backend commit document, no LSU document and no DTLB document
exists in this tree. Each assumption below is stated so that the
document that eventually specifies the producer can be checked
against it. EVERY ONE IS UNVERIFIABLE TODAY.

```
  A1  UNVERIFIABLE. The commit stage can hold the post-FENCE.I
      pipeline restart until ifu_cmt_maint_ack. If it cannot, IF-35
      buys nothing and the fence is not architecturally complete
      when the instruction retires. IF-43 makes this TWO
      acknowledgements, not one: the I-side and the D-side.

  A2  UNVERIFIABLE. The backend translates cbo.inval's rs1 through
      the DTLB and presents a PHYSICAL address on
      cmt_ifu_maint_paddr. If translation is left to the front end,
      the IFU needs an ITLB lookup on the maintenance path, which
      this interface does not have and section 10 does not carry.

  A3  UNVERIFIABLE. The backend raises the address-related faults of
      cbo.inval, and no faulting maintenance operation reaches
      cmt_ifu_maint_val. This is the same division as IF-22 on the
      fetch path.

  A4  UNVERIFIABLE. Only one hart drives this boundary. FENCE.I is
      per hart and is not broadcast; a multi-hart pacino would need
      software to run a fence on each hart, which is the
      architectural expectation and not a hardware path.

  A5  UNVERIFIABLE. The backend gates cbo.inval on menvcfg.CBIE
      before it reaches this port. Section 13 says what that gate
      is. If the gate is not in the backend, MAINT_CBO_INVAL must
      grow the trap and remap behaviour, which does not belong in
      the front end.
```

---

## 13. cbo.inval, menvcfg.CBIE and what is determinable

`icache_decisions.md` TD-L1I-2 carries this as unverified. It is
PARTLY DETERMINABLE, and the two halves are different in kind.

### 13.1 Determinable, and checked

`menvcfg.CBIE` is a two-bit field at bits [5:4], with
`senvcfg.CBIE` and `henvcfg.CBIE` at the same position. Checked in
this session against `tools/spike`, the reference implementation
carried in this tree:

```
  encoding.h:189    MENVCFG_CBIE == 0x30, so bits [5:4]
  csrs.cc:1057      the M, S and H field positions are asserted equal
  csrs.cc:1061-2    value 2 is RESERVED, and a write of it is
                    normalised to 0
  decode_macros.h:205  require_envcfg: below M with the field 0,
                    cbo.inval raises an ILLEGAL INSTRUCTION trap, or
                    a VIRTUAL INSTRUCTION trap when V is set
  insns/cbo_inval.h  the instruction executes as an invalidate or is
                    REMAPPED to a flush, depending on the field
```

So the three behaviours the architecture permits are real and the
gate is real: CBIE 0 traps below M, CBIE 1 invalidates, CBIE 2 is
reserved, CBIE 3 remaps the instruction to a flush.

ONE CAVEAT ON THE EVIDENCE. Spike's `cbo_inval.h` treats any non-zero
CBIE below M as the flush case and reaches the invalidate case only
at M-mode. That is a functional-model simplification and NOT evidence
about the 1-against-3 distinction: in a model with one coherent
memory, a flush and an invalidate of a clean block are the same act.
The field positions, the reserved value and the trap behaviour are
evidence; the 1-against-3 mapping above is from the privileged
specification and is not what spike demonstrates.

### 13.2 NOT determinable, and why

WHETHER cbo.inval REACHES AN INSTRUCTION CACHE AT ALL IS NOT FIXED BY
THE ARCHITECTURE. Zicbom is written against a coherent memory
hierarchy and names "the cache block"; it does not enumerate which
caches a hart has. The instruction cache is, in RISC-V,
architecturally NOT coherent with the data side: FENCE.I is the
mechanism and the burden is on software. It follows that software
CANNOT RELY on cbo.inval to make a store visible to instruction
fetch, whatever an implementation chooses to do, and an
implementation is therefore free to route it to the I-side or not.

That is a real answer, not a gap: the specification does not decide
it, so pacino must.

### 13.3 The port for both readings

The port list of sections 10 and 11 is UNCHANGED under either
reading. `cmt_ifu_maint_op` MAINT_CBO_INVAL either arrives or does
not, and the trap and remap of 13.1 are resolved in the backend
before this boundary (A5). The two readings differ only in the
backend:

```
  cbo.inval REACHES the I-side     the backend, having decided the
                                   instruction executes, drives
                                   MAINT_CBO_INVAL to the IFU and
                                   the equivalent to the LSU
  cbo.inval DOES NOT reach it      the backend drives only the LSU.
                                   MAINT_CBO_INVAL is never asserted
                                   and the IFU path is dead logic
```

ROUTED. IF-41, ruled session-068. MAINT_CBO_INVAL is live and
IF-29's line form is built.

---

## 14. What a cachegen configuration can and cannot say

INFRA-012 problem 4 assessed this and TOOLS-003 confirms it against
the schema and the tool. Confirmed means read this session, in
`tools/cachegen/planning/schema` and `cli/src`, and where a claim was
testable it was tested.

### 14.1 Expressible today, no tool change

For a `custom` link carrying the interface of sections 4 and 5:

```
  address_width_bits           36    yes. And AS OF TOOLS-003 the
                                     new T-10 checker rule makes a
                                     value that disagrees with
                                     addressing.pa_bits an error,
                                     which closes TD-L1I-6
  address_granularity          byte  yes. `line` is also available,
                                     which is the rejected form of
                                     section 4.2
  address_alignment_bytes      64    yes, the enum carries 64
  read_width_bits              512   yes, the maximum is 4096
  handshake.accept             ready yes, IF-16
  handshake.read_data_return
                       valid_with_id yes, IF-12 and IF-14
  id_width_bits                4     yes, IF-2
  outstanding_requests         16    yes, the schema accepts it. It
                                     is NOT CONSUMED, see 14.3 E2
  read_byte_enables            false yes
  write_response               false yes
```

### 14.2 Needs a schema change

```
  S2  A READ-ONLY LINK. custom.write_width_bits has minimum 8 and is
      in the required list, so `0` cannot be declared. Section 4.1
      has no write channel at all. TD-L1I-7, unchanged by TOOLS-003
      and CONFIRMED against links.schema.json this session.

  S6  AN ERROR RETURN ON A CUSTOM LINK. NEW, and not in INFRA-012's
      list. IF-15's l1i_ifu_rsp_err CANNOT BE DECLARED. There is no
      field for it, and the consequence is already visible in the
      emitted tree: l1i_core_slv.sv carries
        // the link declares no error return, so a slave error is
        // dropped here
      and ties rsp_err into an unused net. The node knows it can
      return an error and the link has no way to say so. TD-IF-2.

  S7  A RESPONSE-SIDE HANDSHAKE. NEW. `handshake.accept` governs the
      REQUEST side only. IF-10's deliberate ABSENCE of a response
      ready cannot be declared, and neither could its presence. The
      emitted adapter's response behaviour is a tool policy, not a
      configured one. TD-IF-3.

  S8  THE MAINTENANCE PORTS. The four booleans of the node's
      `maintenance` group say WHETHER the capability exists. Nothing
      anywhere says what its PORTS are, and the group is on the NODE
      rather than on a LINK, so there is no object for section 10's
      port list to attach to. This is a larger gap than E7 below: E7
      is an emitter that does not emit a port, S8 is a schema with
      nowhere to describe one. TD-IF-4.

  S1  prefetch_arbitration. TD-L1I-3, unchanged. IF-9 and 4.4
      narrow what the field means: P1 is IFU-internal and this
      interface cannot see it, so the field describes P2 and P3
      only.

  S9  THE PREFETCH REQUEST BIT. NEW. ifu_l1i_req_prefetch cannot
      be declared: a custom link's bundle is derived from its
      shape and carries no requester-supplied qualifier. Schema
      and emitter, in that order. TD-L1I-9.

  S3  A CONSTRAINT TYING read_data_return `valid_with_id` TO A
      NON-ZERO id_width_bits. Unchanged from INFRA-012. IF-2 and
      IF-11 are exactly the pair that would disagree without it.
```

### 14.3 Needs an emitter change

INFRA-012 E1 through E8 stand. Two of them were TESTED this session
rather than read, and one grew:

```
  E1  THE 512-BIT CORE PORT BREAKS THE PACKAGE. CONFIRMED BY
      EXPERIMENT, not by reading. A scratch copy of pacino with a
      second core link at read_width_bits 512 emits cleanly, and
      Verilator then reports on l1i_pkg.sv:
        %Error: Size-changing cast to zero or negative size: 0
        %Warning-ASCRANGE: Ascending bit range vector: [-1:0]
      at l1i_word_of, exactly as INFRA-012 derived. It is a hard
      ERROR and not a warning.

      AND IT IS WORSE THAN INFRA-012 REPORTED. The same experiment
      also produces, in the emitted TESTBENCH:
        %Warning-WIDTHTRUNC: core_wdata = d;   512 into 32
        %Warning-WIDTHTRUNC: core_wstrb = be;  64 into 4
      The testbench driver task sizes its write path from
      write_width_bits and its data argument from the read width, so
      an asymmetric link breaks the testbench as well as the
      package. That is a second site and it is not in E1's fix.

  E2  outstanding_requests reaches nothing. CONFIRMED: the string
      appears in no consumer, and IF-6, IF-18 and the whole of
      section 6 have no emitted counterpart.

  E3  The request and response identifiers are emitted as wires by
      link_sig and consumed by nothing. IF-11 and IF-12 have no
      emitted counterpart.

  E4  No MSHR file. IF-20 and IF-21 have no emitted counterpart, and
      section 7 is the largest single gap between this file and the
      tool.

  E5  read_latency_cycles and tag_compare_stage are dead for a cache
      node. IF-14's one-cycle minimum is not enforced by anything.

  E7  NO NODE EMITS AN INVALIDATE PORT OF ANY KIND. The whole of
      section 10 is unemittable. With S8, the maintenance path needs
      a schema change AND an emitter change, in that order.
```

### 14.4 The one thing that got better

TOOLS-003 closed TD-L1I-6. `addressing.pa_bits` and every link's
address width are now checked against each other, on any edge
touching a cache or memory node, as `T-10.addr_width`. The silent
zero-extend into `l1i_addr_t` and the silent truncation out of
`mem_a_address` that INFRA-012 found are now build errors.

---

## 15. Defects found in icache_decisions.md

Reported, not worked around. This file was read-only in TOOLS-003
and the PA drafted the amendment.

ALL SIX ARE APPLIED as of icache_decisions.md 2026-08-29, plus a
seventh the PA found in the same pass. Kept here as the record of
what was found and why; do not re-report them.

```
  D1  APPLIED. 7 M1 is drain then clear
  D2  APPLIED. L1I-18 covers the IFU buffer; ordering in IF-36
  D3  APPLIED. Section 9 reads 36; TD-L1I-6 closed
  D4  APPLIED, by adding the port. L1I-21 and L1I-22; IF-38 and
      IF-39 in this file
  D5  APPLIED. L1I-20; L1I-U1 closed; 23 and 24 disambiguated
  D6  APPLIED. 0.1 carries a maint row
  D7  APPLIED, PA-found. Section 6's targets-per-MSHR derivation
      was void under L1I-14 -- the second prediction block never
      becomes a request -- so 4 is now an unmeasured choice
```

---

## 16. Open items

EVERY IF-U IS CLOSED. None is reused.

```
  IF-U1  CLOSED. Conservative, IF-40.

  IF-U2  CLOSED. It asked whether the ITLB assumed by IF-24 holds.
         IF-24 was written on that assumption, so the item asked
         about its own premise. The ITLB is non-blocking; L1I-U3.

  IF-U3  CLOSED. Routed. IF-41.

  IF-U4  CLOSED. One cycle. IF-42.

  IF-U5  CLOSED. FENCE.I is routed to the D-side as well. IF-43.
```

NO OPEN ITEMS REMAIN IN THIS FILE.

---

## 17. Technical debt

```
  TD-IF-1  closed
           VA_WIDTH is 40 and addressing.va_bits is 39. These are different
           quantities: 40 is the Sv39 address plus its sign bit, the
           vaddrBitsExtended convention. No action.

  TD-IF-2  A CUSTOM LINK CANNOT DECLARE AN ERROR RETURN. Section
           14.2 S6. IF-15 is unemittable and the emitted adapter
           already ties the signal off with a comment saying so.

  TD-IF-3  A CUSTOM LINK CANNOT DECLARE ITS RESPONSE-SIDE
           HANDSHAKE. Section 14.2 S7. IF-10's absence of a response
           ready is a tool policy today, not a configured property.

  TD-IF-4  THE SCHEMA HAS NOWHERE TO DESCRIBE A MAINTENANCE PORT.
           Section 14.2 S8. The `maintenance` group is four booleans
           on the node saying whether a capability exists. Section
           10's port list has no object to attach to, so E7's
           emitter work has nothing to read.

  TD-IF-5  THE PREDECODE WRITEBACK AND THE LINE RESPONSE ARE NOT
           ORDERED AGAINST EACH OTHER. ftq_ifu_interfaces.md 6 has
           the IFU return one writeback per fetch block; IF-12 lets
           the line responses that feed those blocks return out of
           order. The IFU therefore reorders between its two
           boundaries, and nothing in either file says what bounds
           the reordering buffer that implies. It belongs in
           ifu_decisions.md and is named here because this file is
           the half that introduces the out-of-order return.
```

---

## 18. RVA23 compliance note

```
  Zicbom     MANDATORY in RVA23U64. cbo.inval is section 11's
             MAINT_CBO_INVAL and section 13 is its gate.
  Zifencei   MANDATORY in RVA23S64, which pacino is: it implements
             Sv39 and supervisor mode. FENCE.I is section 11's
             MAINT_FENCE_I.
```

Both were checked this session against the profile listing in
`tools/cachegen/tools/jnutils/ncurses/rva23.md`, which carries
Zicbom in the RVA23U64 mandatory string and Zifencei in the RVA23S64
additions.

THE GAP IS UNCHANGED BY THIS FILE. TD-L1I-8 records that L1I-18 has
no hardware, and section 14.3 E7 confirms it: no generated node emits
an invalidate port of any kind. This file specifies the ports; it
does not build them, and RVA23 conformance for both extensions
remains blocked on the emitter work.

There is no C-extension consequence here. A fetch may begin on any
2-byte boundary, but IF-5 makes every request line aligned and the
block extract is the IFU's (4.3 R3), so nothing in this interface
sees a 2-byte boundary.

---

## 19. Document History

```
  2026-09-01  IF-U3, IF-U4 and IF-U5 closed, session-068.
              cbo.inval is routed to the I-side, IF-41. The
              invalidate clear takes one cycle, IF-42. FENCE.I is
              routed to the D-side as well, IF-43, so the backend
              gates the post-fence restart on two
              acknowledgements. 13.3 and A1 follow. No open item
              remains in this file.

  2026-08-31  IF-U1 closed as IF-40, conservative ready. IF-U2
              deleted, circular. IF-17, IF-24 and section 7
              updated. Section 15's duplicated defect text
              removed; the status block stands.

  2026-08-30  THE PREFETCH BIT ADDED, session-068. 4.4 said P2 was
              not enforceable and left it; Jeff ruled the port in.
              ifu_l1i_req_prefetch is one bit, read in exactly one
              place: IF-39 refuses a prefetch unless two MSHRs are
              free, L1I-22. Everything else about a prefetch is
              identical to a demand fetch, so IF-19's invisible
              miss and the shared identifier space both stand.
              S9 and TD-L1I-9: no link field can express the bit.

              IF-36 GAINED ITS ORDERING. The rule said the IFU
              clears its buffer and did not say when. IF-31 drains
              rather than discards and IF-10 makes the IFU accept
              every draining response, so a clear on receipt is
              repopulated by the next response -- D1's defect one
              layer up. The clear follows l1i_ifu_inv_done.

              All six reported defects are applied in
              icache_decisions.md, with a seventh the PA found.
              Section 15 records their status.

  2026-08-29  Created, TOOLS-003. Closes the port-list half of
              icache_decisions.md section 4, which stated the shape
              and stopped. Sixteen identifiers with an IFU-owned
              free list are the flow control, and the response
              carries no ready because of it. A miss is not visible;
              merging is not visible; a fifth target on one MSHR is
              refused by ready rather than rejected on a channel. A
              translation fault reaches the L1I never and adds no
              port, so section 8 specifies an absence. Maintenance
              is specified at both ends: a drain-then-clear
              invalidate from the IFU, and a commit-stage boundary
              with a required acknowledgement, because without one
              FENCE.I has no completion semantics.

              SIX DEFECTS REPORTED against icache_decisions.md, of
              which two are correctness rather than tidiness: 7 M1's
              single-cycle FENCE.I is wrong once sixteen requests
              can be outstanding (D1), and L1I-14's IFU line buffer
              is not covered by L1I-18's invalidate path (D2).

              menvcfg.CBIE checked against tools/spike rather than
              asserted. The gate is real and the field is two bits
              at [5:4] with value 2 reserved; whether cbo.inval
              reaches an instruction cache at all is NOT fixed by
              the architecture, so the port is specified for both
              readings and the choice is recorded as IF-U3.

              Three NEW schema gaps beyond INFRA-012's list, all
              found by writing the port list down: no error return
              on a custom link, no response-side handshake, and
              nowhere at all to describe a maintenance port.
```

