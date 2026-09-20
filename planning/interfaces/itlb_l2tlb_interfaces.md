<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Instruction TLB to L2 TLB Interface
```
 FILE:    itlb_l2tlb_interfaces.md
 SOURCE:  session-069
 STATUS:  DRAFT
 UPDATED: 2026-09-19
 CONTACT: Jeff Nye
```

Owns the IL-N registry.

---

## 1. Scope

Two groups cross this boundary: the ITLB presents a miss to the
shared L2 TLB, and the L2 TLB answers with a translation or a
fault. The walk itself, the l2 port it uses, and the A and D bit
handling are inside the L2 TLB and are `mmu_decisions.md`.

The L1 data TLB will be a second client of this same port shape.
Nothing here is I-side specific and the port is written to be
instantiated twice.

---

## 2. The groups

```
  itlb_l2t_req_val                        ITLB  -> L2TLB
  itlb_l2t_req_rdy                        L2TLB -> ITLB
  itlb_l2t_vpn   [VPN_WIDTH-1:0]          ITLB  -> L2TLB
  itlb_l2t_asid  [ASID_WIDTH-1:0]         ITLB  -> L2TLB
  itlb_l2t_vmid  [VMID_WIDTH-1:0]         ITLB  -> L2TLB
  itlb_l2t_v                              ITLB  -> L2TLB
  itlb_l2t_tag   [1:0]                    ITLB  -> L2TLB

  l2t_itlb_rsp_val                        L2TLB -> ITLB
  l2t_itlb_tag   [1:0]                    L2TLB -> ITLB
  l2t_itlb_status [1:0]                   L2TLB -> ITLB
  l2t_itlb_ppn   [PPN_WIDTH-1:0]          L2TLB -> ITLB
  l2t_itlb_size  [1:0]                    L2TLB -> ITLB
  l2t_itlb_perm  [PERM_WIDTH-1:0]         L2TLB -> ITLB
  l2t_itlb_cause [CAUSE_WIDTH-1:0]        L2TLB -> ITLB
  l2t_itlb_gpa   [GPA_WIDTH-1:0]          L2TLB -> ITLB
```

IL-1  `itlb_l2t_tag` is two bits. Up to four requests may be
      outstanding from one client.

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
```

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

IL-3b A `V=1` request commits the L2 TLB to a NESTED walk,
      MMU-21, which is several times the work of a single-stage
      one. The port does not distinguish them beyond the V bit;
      the cost difference is the L2 TLB's to absorb and is why
      IL-6 exists.

---

## 3. The result

IL-4  `l2t_itlb_status` is three-way.

```
  2'b00   hit    ppn, size and perm valid
  2'b01   fault  cause valid, ppn invalid
  2'b10   retry  no walk was started, re-request
  2'b11   reserved
```

IL-5  There is no miss status. An L2 TLB miss starts a walk and
      the response is deferred until the walk completes. The
      transaction stays open. This is the opposite of ITLB-8,
      where a miss ends the transaction and the requester
      re-requests.

IL-6  `retry` is not a miss. It means the L2 TLB could not accept
      the request into its tracker, so nothing is in flight and
      the client must ask again. It exists because IL-5 makes the
      transaction long-lived and the tracker can fill.

IL-5 is why this port differs from the one above it. The ITLB
answers the IFU immediately because the IFU has other work and a
prediction block to abandon. The ITLB has nothing else to do with
a missed translation, so holding the transaction open costs it
nothing and saves a re-request path.

This read "a fetch block to abandon"; the fetch block is the 64-byte
L1I line (fe_decisions.md Conventions). Session-071.

---

## 4. Page size and permissions

IL-7  `l2t_itlb_size` names which of the three Sv39 page sizes
      the translation covers: 4 KiB, 2 MiB or 1 GiB. The ITLB
      installs the entry at that size, ITLB-3.

IL-8  `l2t_itlb_perm` carries the PTE permission and attribute
      bits the ITLB must hold to answer later hits without asking
      again. Included are the executable, user and global bits.
      The global bit sets the ITLB entry's global flag of
      ITLB-4.

IL-9  The PMA attributes of MMU-13 are not returned here. They
      come from the static region table and are a function of the
      physical address, so the ITLB derives them from the PPN it
      was given rather than being told.

IL-9 is a placement choice and it follows MMU-15. A PMA is a
property of an address range, not of a translation, so returning
it on this port would make the L2 TLB a second source for
something the region table already decides.

---

## 5. Faults

IL-10 A fault response ends the transaction. The cause
      distinguishes three: a page fault from a single-stage or
      VS-stage walk, a GUEST page fault from the G-stage, and an
      access fault from the PMP check the walker performs under
      MMU-10. MMU-16.

IL-11 The faulting virtual address is not returned. The client
      supplied it and holds it against the tag.

IL-11a The faulting GUEST PHYSICAL address IS returned on
       `l2t_itlb_gpa`, valid on a guest page fault only. The
       client never had it; it is
       produced inside the nested walk. Shtvala requires `htval`
       to carry it. This is the one address that travels back on
       this port, and it continues to the IFU as
       `itlb_ifu_gpa`, IT-6a.

---

## 6. Maintenance

IL-12 SFENCE.VMA does not cross this boundary, and neither do
      HFENCE.VVMA and HFENCE.GVMA. The L2 TLB has its own
      invalidate port, MMU-18, and the ITLB has its own,
      ITLB-14. Neither forwards to the other. MMU-17a.

IL-13 A walk in flight when an invalidate arrives completes, and
      its result is not installed in the L2 TLB. MMU-17. Whether
      the response is still returned to the client, or suppressed
      so the client's tracker entry must time out, is the one
      thing this port must state and IL-14 states it.

IL-14 The response is returned normally. The client installs
      nothing, because a client that received an invalidate in
      the same window discards its own tracker entry. A
      suppressed response would leave the client's tag allocated
      with nothing to release it.

---

## 7. Open

None.

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
MMU-18    The L2 TLB invalidate port, IL-12.
