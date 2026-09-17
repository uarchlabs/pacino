<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# IFU to Instruction TLB Interface
```
 FILE:    itlb_ifu_interfaces.md
 SOURCE:  session-069
 STATUS:  DRAFT
 UPDATED: 2026-09-15
 CONTACT: Jeff Nye
```

Owns the IT-N registry.

---

## 1. Scope

Two groups cross this boundary: the IFU asks the ITLB to
translate a virtual address, and the ITLB answers.

The requester is the IFU's TRANSLATION pipeline, `ifu_decisions.md`
IFU-24, which runs ahead of the fetch pipeline and queues its
results. It is not F0 of the fetch pipeline. Nothing in this
document depends on which of the two it is, but a reader placing
these ports in the fetch stages would put them in the wrong
pipeline. The ITLB's own
miss path into the shared L2 TLB is not here; it is
`itlb_l2tlb_interfaces.md`.

---

## 2. The groups

```
  ifu_itlb_req_val                        IFU  -> ITLB
  ifu_itlb_req_rdy                        ITLB -> IFU
  ifu_itlb_vpn   [VPN_WIDTH-1:0]          IFU  -> ITLB
  ifu_itlb_tag                            IFU  -> ITLB

  itlb_ifu_rsp_val                        ITLB -> IFU
  itlb_ifu_tag                            ITLB -> IFU
  itlb_ifu_status [1:0]                   ITLB -> IFU
  itlb_ifu_ppn   [PPN_WIDTH-1:0]          ITLB -> IFU
  itlb_ifu_cause [CAUSE_WIDTH-1:0]        ITLB -> IFU
  itlb_ifu_gpa   [GPA_WIDTH-1:0]          ITLB -> IFU
  itlb_ifu_pma   [PMA_WIDTH-1:0]          ITLB -> IFU
```

IT-1  One request port. A block that crosses a page needs two
      translations and they are issued on successive cycles, not
      on a second port.

IT-2  `ifu_itlb_tag` is one bit and names which half of the block
      the request covers. 0 is the block's own page, 1 is the
      page the straddle reaches into.

IT-3  The response carries the tag back. Responses may return out
      of order, so the tag is how the IFU attributes them.

IT-1 is the reason IT-3 exists. Two requests are in flight when a
block crosses a page, the first can miss while the second hits,
and the hit returns first. A second request port would avoid the
tag at the cost of a second set of 64 comparators against the
fully associative array of ITLB-2, spent on a case that occurs
only at a page boundary.

---

## 3. The result

IT-4  `itlb_ifu_status` is three-way, which is ITLB-11.

```
  2'b00   hit    ppn valid, cause and the block's PMA valid
  2'b01   miss   a walk has started. ppn and cause are invalid.
  2'b10   fault  cause valid. ppn invalid.
  2'b11   reserved
```

IT-5  The virtual address the fault applies to is not returned.
      The IFU supplied it and holds it. Returning it would give
      one fact two producers.

IT-6  `itlb_ifu_cause` distinguishes three causes: instruction
      access fault, cause 1, from the PMP or PMA check of MMU-10
      and MMU-12; instruction page fault, cause 12, from a
      single-stage or VS-stage translation; and instruction
      guest-page fault, cause 20, from the G-stage. H is
      mandatory in RVA23 through Sha, so the third is not
      optional.

IT-6a `itlb_ifu_gpa` carries the faulting GUEST PHYSICAL address
      and is valid only when the cause is 20. Shtvala requires
      `htval` to be written with it, and unlike the virtual
      address of IT-5 the IFU never had it: it is produced inside
      the walk. So it returns here and IT-5 does not apply to it.

IT-6b Nothing about the translation regime is on this port. The
      IFU presents a virtual address and no more.

      The ITLB reads what it needs directly: the V bit, the ASID
      and the VMID for the tag match of ITLB-4 and ITLB-4a, and
      the MODE fields to know whether translation is enabled or
      Bare.

      IT DOES NOT READ THE ROOT POINTERS. The ITLB does not walk,
      so `satp.PPN`, `vsatp.PPN` and `hgatp.PPN` are no use to it.
      They belong to the walker inside the L2 TLB,
      `itlb_l2tlb_interfaces.md` IL-3c. An earlier revision of
      this rule had the ITLB read all three.

IT-5 is a departure from how ITLB-11 is worded. That rule has the
ITLB return the fault cause and the faulting virtual address
together, because the pair is what must reach the backend under
Sstvala. The pair is assembled in the IFU: it already holds the
VA, it receives the cause here, and it carries both into
`predecode_pkt_t` at IB-9. Nothing is lost and the VA does not
make a round trip.

---

## 4. Miss

IT-7  A miss response ends the transaction. The ITLB does not
      hold the request and does not answer it later.

IT-8  The IFU re-requests. It may re-request in any cycle after
      the miss response and the ITLB does not require a minimum
      interval.

IT-9  A re-request for a virtual address with a walk already in
      flight receives a miss response and starts no second walk.
      The ITLB matches against its in-flight walks. This is
      ITLB-10 and it is stated here because the IFU's behaviour
      depends on it: the IFU may re-request freely and cannot
      cause duplicate walk traffic.

---

## 5. PMA

IT-10 `itlb_ifu_pma` returns the attributes of MMU-13 on a hit:
      cacheable, coherent, executable, idempotent.

IT-11 The IFU reads idempotent to decide whether the fetch may
      proceed speculatively. A non-idempotent region takes the
      uncached path of IFU-21 and does not reach the L1I.

IT-12 The checks do not gate THIS response. The translation
      returns at the ITLB-5 hit latency with `itlb_ifu_pma`
      valid, and the PMP and PMA results are consumed by the IFU
      before it issues an L1I request, not before the ITLB
      answers. ITLB-12 and ITLB-12a.

IT-12a No L1I request is issued for a block that fails PMP or
       PMA. `l1i_ifu_interfaces.md` IF-22: a faulting request
       never reaches the L1I and that interface has no fault port
       in either direction. The translation pipeline of IFU-23a
       is what makes this free; there is no cycle to save by
       letting the request go and killing the response.

---

## 6. Flow control

IT-13 `ifu_itlb_req_rdy` deasserts when the ITLB cannot accept a
      lookup. The IFU holds the request stable until it is taken.

IT-14 The response has no ready. The IFU accepts every response
      in the cycle it is presented. It has a slot for each of the
      two outstanding requests IT-1 permits and cannot run out.

---

## 7. Maintenance

IT-15 SFENCE.VMA does not cross this boundary. ITLB-14 gives the
      ITLB a distinct invalidate port and the IFU is not on that
      path.

---

## 8. Open

None here. Two items elsewhere bear on this port without changing
it: ITLB-U1, the in-flight walk tracker depth, bounded by TD#118,
since IT-9 holds at any depth; and IFU-U5, the translation queue
depth, which sets how far ahead of the fetch pipeline these
requests are issued.

---

## 9. Bindings

ITLB-2    The fully associative array IT-1 avoids duplicating.
ITLB-5    One cycle hit, preserved by IT-12.
ITLB-8    Non-blocking, IT-7.
ITLB-9    The requester re-requests, IT-8.
ITLB-10   In-flight walk match, IT-9.
ITLB-11   Three-way result, IT-4. The VA half is IT-5.
ITLB-12   Check placement, IT-12.
ITLB-14   Invalidate port, IT-15.
IFU-7     Two lookups per block, IT-1 and IT-2.
IFU-21    The uncached path IT-11 selects.
MMU-13    The attributes of IT-10.
IB-9      Where the cause and VA are paired.
