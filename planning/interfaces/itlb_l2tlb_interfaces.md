<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Instruction TLB to L2 TLB Interface
```
 FILE:    itlb_l2tlb_interfaces.md
 SOURCE:  session-069
 STATUS:  DRAFT
 UPDATED: 2026-10-09
 CONTACT: Jeff Nye
```

Owns the IL-N registry.

---

## 1. Scope

Two groups cross this boundary: the ITLB presents a miss, and the
server answers with a translation or a fault.

THE SERVER IS THE PAGE TABLE WALKER. There is no L2 TLB now
(`mmu_decisions.md` MMU-1, reversed session-077); an ITLB miss goes
to the walker directly. The port was written for an L2 TLB and its
shape is unchanged: a walker also holds the transaction open until
the walk completes (IL-5). An L2 TLB added later sits behind this
same port. THE PORT NAMES KEEP `l2t`, ruled session-077 (Jeff): they
are built, and renaming them buys nothing a reader of this
paragraph needs. Where the rules below say L2 TLB, read the walker
until an L2 TLB exists.

The walk itself, the walker's memory port, and the A and D bit
handling are `mmu_decisions.md` and `ptw_mem_interfaces.md`.

The L1 data TLB will be a second client of this same port shape.
Nothing here is I-side specific and the port is written to be
instantiated twice.

---

## 2. The groups

```
  itlb_l2t_req_val                        ITLB  -> L2TLB
  itlb_l2t_req_rdy                        L2TLB -> ITLB
  itlb_l2t_vpn   [VA_WIDTH-13:0]          ITLB  -> L2TLB
  itlb_l2t_asid  [ASID_WIDTH-1:0]         ITLB  -> L2TLB
  itlb_l2t_vmid  [VMID_WIDTH-1:0]         ITLB  -> L2TLB
  itlb_l2t_v                              ITLB  -> L2TLB
  itlb_l2t_tag   [1:0]                    ITLB  -> L2TLB

  l2t_itlb_rsp_val                        L2TLB -> ITLB
  l2t_itlb_tag   [1:0]                    L2TLB -> ITLB
  l2t_itlb_status [1:0]                   L2TLB -> ITLB
  l2t_itlb_ppn   [PPN_WIDTH-1:0]          L2TLB -> ITLB
  l2t_itlb_size  [2:0]                    L2TLB -> ITLB
  l2t_itlb_perm  [PERM_WIDTH-1:0]         L2TLB -> ITLB
  l2t_itlb_pbmt  [1:0]                    L2TLB -> ITLB
  l2t_itlb_cause [CAUSE_WIDTH-1:0]        L2TLB -> ITLB
  l2t_itlb_gpa   [GPA_WIDTH-1:0]          L2TLB -> ITLB
  l2t_itlb_gpa_imp [1:0]                  L2TLB -> ITLB
```

IL-1a `itlb_l2t_vpn` is VA_WIDTH - 12 = 29 bits, for the reason
      itlb_ifu_interfaces.md IT-16 gives for the IFU side: with V=1
      and vsatp.MODE=Bare the address is a 41-bit guest physical
      address, and a 27-bit field drops bits 40:39. BP-118 built
      it at 29. This read [VPN_WIDTH-1:0]. Session-075.

IL-1  `itlb_l2t_tag` is two bits. Up to four requests may be
      outstanding from one client. The walker accepts one at a
      time (MMU-U2, closed session-077) and answers others retry,
      IL-6; the tag width is unchanged.

IL-2  The response carries the tag back. Responses may return out
      of order.

Two bits covers the two translations IT-1 allows in flight on the
I side and leaves headroom. The tracker depth is a separate
decision, ITLB-U1, and can change without touching this port.
Sizing the tag to the tracker would couple them.

IL-3  The translation context IDENTITY travels with the request:
      the V bit, the ASID and the VMID. The L2 TLB does not hold a
      current ASID or VMID; the client already holds both for its
      own tag match, so sending them keeps one producer.

IL-3c THE MMU DOES READ CSRs. IL-3 is about identity, not about
      the whole CSR file. What the WALK needs is regime state and
      is read directly, not carried per request:

```
  satp.PPN                 single-stage root
  vsatp.PPN, hgatp.PPN     VS-stage and G-stage roots, MMU-19
  the MODE fields          whether translation is on, and Bare
  menvcfg.ADUE             Svade against Svadu, MMU-7
  henvcfg.ADUE             the same for the VS-stage, MMU-7a
  menvcfg/henvcfg.PBMTE    the PBMT walker checks, MMU-U6
```

These reach the walker on its own CSR input group, not through the
front-end top (mmu_decisions.md MMU-24a). The root pointers are
narrower than the architectural fields (MMU-24b).

The division is that identity is a property of the REQUEST and the
regime is not. A root pointer is not something one request has and
another does not, and putting it on the port would make every
client a producer of it.

AN EARLIER REVISION OF IL-3 said the L2 TLB does not read a CSR,
full stop. That contradicted MMU-7 and MMU-7a, which already have
the MMU read the ADUE bits, and it left the walker with no source
for the root it walks from. Session-069.

IL-3a The VMID and the V bit travel with it for the same reason.
      H is mandatory in RVA23 through Sha, so a request is either
      a `V=0` single-stage translation or a `V=1` two-stage one,
      and a two-stage request names its guest. ITLB-4a.

IL-3b A `V=1` request commits the walker to a NESTED walk,
      MMU-21, which is several times the work of a single-stage
      one. The port does not distinguish them beyond the V bit;
      the cost difference is the walker's to absorb and is why
      IL-6 exists. This read "the L2 TLB"; session-077.

---

## 3. The result

IL-4  `l2t_itlb_status` is three-way.

```
  2'b00   hit    ppn, size and perm valid
  2'b01   fault  cause valid, ppn invalid
  2'b10   retry  no walk was started, re-request
  2'b11   reserved
```

IL-5  There is no miss status. An accepted request starts a walk
      and the response is deferred until the walk completes. The
      transaction stays open. This is the opposite of ITLB-8,
      where a miss ends the transaction and the requester
      re-requests. This read "An L2 TLB miss starts a walk";
      session-077.

IL-6  `retry` is not a miss. It means the walker could not accept
      the request, because it is performing another walk
      (MMU-U2), so nothing is in flight and the client must ask
      again. It exists because IL-5 makes the transaction
      long-lived. This read "into its tracker" of an L2 TLB;
      session-077.

IL-5 is why this port differs from the one above it. The ITLB
answers the IFU immediately because the IFU has other work and a
prediction block to abandon. The ITLB has nothing else to do with
a missed translation, so holding the transaction open costs it
nothing and saves a re-request path.

This read "a fetch block to abandon"; the fetch block is the 64-byte
L1I line (fe_decisions.md Conventions). Session-071.

---

## 4. Page size and permissions

IL-7  `l2t_itlb_size` names which page size the translation
      covers: 4 KiB, 64 KiB (Svnapot), 2 MiB or 1 GiB. THREE bits,
      RULED session-075 (Jeff): 3'b000 4 KiB, 3'b001 64 KiB,
      3'b010 2 MiB, 3'b011 1 GiB, 3'b1xx reserved for a future
      size. Ascending, so a larger code always masks more VPN
      bits. BP-118 built two bits; BP-119 widened to three. A
      response that hits with a reserved size code is handled as a
      reserved status (IT-4, IL-4), built by BP-119. The ITLB
      installs the entry at that size, ITLB-3; a 64 KiB entry is
      held once with a masked match (mmu_decisions.md MMU-U7).
      The PPN returned for a 64 KiB page is the PTE's, with
      PPN[3:0] the size marker; the ITLB substitutes on its
      output. This read "which of the three Sv39 page sizes".
      Session-071.

IL-7a For a `V=1` translation the size is the SMALLER of the two
      stages' leaf sizes, and the PPN is the final supervisor
      physical page at that size (mmu_decisions.md MMU-27).
      Session-077.

IL-8  `l2t_itlb_perm` carries the PTE permission and attribute
      bits the ITLB must hold to answer later hits without asking
      again. Included are the executable, user and global bits.
      The global bit sets the ITLB entry's global flag of
      ITLB-4.

IL-9  The PMA attributes of MMU-13 are not returned here. They
      come from the static region table and are a function of the
      physical address, so the ITLB derives them from the PPN it
      was given rather than being told.

IL-9 is a placement choice and it follows MMU-15 for the
attributes the region table decides. Svpbmt is mandatory in
RVA23S64, so the PTE's PBMT field is a second memory type source,
per translation, that the region table cannot supply
(mmu_decisions.md MMU-U5). This paragraph said a PMA "is a property
of an address range, not of a translation" and that returning one
would make the L2 TLB "a second source for something the region
table already decides", which MMU-U5 contradicts. Session-071.

IL-9a `l2t_itlb_pbmt` returns the page's memory type on a hit: the
      more restrictive of the G-stage and VS-stage PBMT, ordered
      PMA < NC < IO, and PMA (2'b00) when neither stage sets one.
      The ITLB stores it (ITLB-3a) and combines it with the region
      attributes into the effective type, the most restrictive of
      the three (mmu_decisions.md MMU-U6, ruled session-071). A
      reserved PBMT, or a non-zero one with PBMTE clear, never
      reaches this port: the walker faults it.

---

## 5. Faults

IL-10 A fault response ends the transaction. The cause
      distinguishes three: a page fault from a single-stage or
      VS-stage walk, a GUEST page fault from the G-stage, and an
      access fault. MMU-16. The access fault has five sources: the
      PMP check the walker makes on every access (MMU-10, MMU-10d),
      the PMA check on every access (MMU-12), a page table outside
      cacheable coherent memory (MMU-12a), a PPN naming an address
      this implementation cannot form (MMU-28), and an error from
      the walker's memory port (ptw_mem_interfaces.md WM-7). This
      named the PMP check only; session-077.

IL-11 The faulting virtual address is not returned. The client
      supplied it and holds it against the tag.

IL-11a The faulting GUEST PHYSICAL address IS returned on
       `l2t_itlb_gpa`, valid on a guest page fault only. The
       client never had it; it is
       produced inside the nested walk. Shtvala requires `htval`
       to carry it. This is the one address that travels back on
       this port, and it continues to the IFU as
       `itlb_ifu_gpa`, IT-6a. It is 0 when the faulting guest
       physical address does not fit GPA_WIDTH (MMU-30).

IL-11b `l2t_itlb_gpa_imp` says what the GPA is, valid on a guest
       page fault only: 2'b00 the fetch's own guest physical
       address, 2'b01 an implicit read of a VS-stage page table,
       2'b10 an implicit write of one (the Svadu update), 2'b11
       reserved. The backend needs it to write htinst, which must
       be a pseudoinstruction for an implicit-access fault with a
       non-zero htval (mmu_decisions.md MMU-29). It continues to
       the IFU as `itlb_ifu_gpa_imp`, IT-6c. Added session-077
       (Jeff).

---

## 6. Maintenance

IL-12 SFENCE.VMA does not cross this boundary, and neither do
      HFENCE.VVMA and HFENCE.GVMA, nor the Svinval instructions,
      which act as those three (mmu_decisions.md MMU-U8). The ITLB
      has its own invalidate port, ITLB-14. The walker has none,
      because it holds no translation (MMU-17); an L2 TLB, when
      added, has its own (MMU-18). Neither forwards to the other.
      MMU-17a.

IL-13 A walk in flight when an invalidate arrives completes. The
      walker installs nothing in any case; an L2 TLB, when added,
      does not install the result. MMU-17. Whether the response is
      still returned to the client, or suppressed so the client's
      tracker entry must time out, is the one thing this port must
      state and IL-14 states it.

IL-14 The response is returned normally. The client installs
      nothing, because a client that received an invalidate in
      the same window discards its own tracker entry. A
      suppressed response would leave the client's tag allocated
      with nothing to release it.

---

## 7. Open

None. MMU-U6, MMU-U7 and MMU-U8, which reached IL-7, IL-9 and
IL-12, were ruled session-071; IL-9a adds l2t_itlb_pbmt. MMU-U9 was
ruled session-077; IL-10, IL-11a and IL-11b carry it.

---

## 8. Bindings

ITLB-3    Page sizes, IL-7.
ITLB-4    ASID and global, IL-3 and IL-8.
ITLB-8    Contrasted by IL-5.
ITLB-10   The in-flight match that keeps duplicate requests off
          this port.
ITLB-14   The ITLB invalidate port, IL-12.
ITLB-U1   Tracker depth, decoupled from IL-1 by design.
IT-1      Two outstanding I-side translations, the sizing input
          to IL-1.
MMU-3     The L1 TLBs are clients of this port.
MMU-10    The walker's PMP check, the access-fault cause of IL-10.
          This read "the second cause"; IL-10 lists it third.
          Session-071.
MMU-13    PMA attributes, deliberately absent by IL-9.
MMU-15    The static region table IL-9 defers to.
MMU-17    Invalidate during a walk, IL-13 and IL-14.
MMU-18    The L2 TLB invalidate port, when there is one, IL-12.
MMU-1     No L2 TLB now; the walker is the server, section 1.
MMU-27    The two-stage size, IL-7a.
MMU-29    The implicit-access kind, IL-11b.
MMU-30    The GPA that does not fit, IL-11a.

---

## 9. Document History

```
  2026-10-09  session-077, rulings (Jeff). The server is the walker,
              not an L2 TLB (MMU-1 reversed); the port names keep
              l2t. l2t_itlb_gpa_imp and IL-11b added. IL-7a, the
              two-stage size. IL-10 names every access-fault
              source. IL-1, IL-3b, IL-5, IL-6, IL-12 and IL-13
              restated for a walker. This document had no history
              section; its earlier changes are in PROJECT_STATUS.
```
