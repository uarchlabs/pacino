<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# MMU Decisions
```
 FILE:    mmu_decisions.md
 SOURCE:  session-069
 STATUS:  DRAFT
 UPDATED: 2026-09-15
 CONTACT: Jeff Nye
```

Owns the MMU-N, TD-MMU-N and MMU-UN registries.

Scope is the shared L2 TLB, the page table walker, and the PMP and
PMA checkers. The L1 instruction TLB is in `itlb_decisions.md`. The
L1 data TLB does not exist. Everything here is shared I and D by
construction, which is why it is not in the ITLB document.

---

## 1. Origin

`icache_decisions.md` L1I-U3 and L1I-U4, both ruled session-069.
U4 was unrecommended and the recommendation was made and ruled in
the same session.

The L2 TLB and the walker are written from this document, the way
the bpu and the ftq were written from theirs. They are not cachegen
nodes. What L1I-U3 reaches into cachegen for is one thing only: the
l2 must accept a third master, and the l2 is emitted. That is
MMU-U3.

---

## 2. Topology

MMU-1  One shared L2 TLB serving the instruction and data sides.
       The page table walker is inside it.

MMU-2  It drives a TileLink master port into l2, alongside up_i
       and up_d.

MMU-3  The L1 TLBs are clients. A client miss is presented to the
       L2 TLB; an L2 TLB miss starts a walk.

The D side has no client yet. MMU-1 is built with one client and
the second arrives with the DTLB.

MMU-U1 L2 TLB entry count, associativity and page-size handling.
       Not addressed by L1I-U3, which named the topology only.
       Comparable points: Neoverse N1 and N2 at 1280 entries
       5-way, Neoverse V2 and Cortex X2 at 2048 8-way, Zen 2 with
       a split 512-entry 8-way L2 ITLB and 2048-entry 12-way L2
       DTLB. Unresolved.

---

## 3. Walker

MMU-4  The walker issues physical addresses directly. They do not
       pass through any L1 TLB.

MMU-5  Walk reads go out on the MMU-2 master edge.

MMU-U2 How many walks may be outstanding. The l2 slave holds one
       transaction, TD#118, so concurrent walks serialise there
       until that is fixed. This bounds `itlb_decisions.md`
       ITLB-U1. Unresolved, and should be ruled after TD#118
       rather than before.

---

## 4. A and D bits

MMU-6  Both Svade and Svadu are supported.

MMU-7  `menvcfg.ADUE` selects the behaviour at runtime. With ADUE
       clear the walker raises a page fault when A is clear on
       access or D is clear on write, which is Svade. With ADUE
       set the walker updates the bits in memory, which is Svadu.

MMU-8  The Svadu update is atomic with respect to other harts. The
       walker performs it as a read-modify-write that cannot be
       split.

MMU-9  The MMU-2 master edge is not read-only. MMU-8 requires the
       edge to carry an atomic operation, so the edge's TileLink
       conformance level must include atomics and cannot be
       Get-only.

MMU-9 is the reason MMU-6 is recorded here and not left implicit.
Svade alone would have permitted a read-only edge. Supporting both
fixes the port type. Because the far end of that port is the
emitted l2, it is also the one place this module reaches into
cachegen. See MMU-U3.

MMU-U3 Two parts. Whether the MMU-8 atomic is a TileLink AMO on
       the MMU-2 port or a reservation pair. And whether the l2,
       which is emitted, needs a schema or emitter change to
       accept a third master and to carry that atomic on it.
       The second part is a cachegen question and is the only
       one in this document. Unresolved.

---

## 5. PMP

MMU-10 PMP is checked at two sites. On the translated physical
       address before an L1 access completes, and on every address
       the walker issues.

Two sites are forced, not chosen. MMU-4 has walk addresses bypass
the L1 TLBs, so a single checker at the L1 boundary would leave
walk traffic unchecked. CVA6 checks PMP on every access a walk
makes for the same reason.

MMU-11 16 PMP entries, with TOR and NAPOT address matching. The
       count is a parameter.

MMU-U4 Whether RVA23S64 mandates Smepmp, and whether that changes
       MMU-11. The RVA23S64 mandatory privileged list was checked
       in session-069 and Smepmp did not appear in what was
       retrieved, but the full list was not seen. Treat as
       unconfirmed rather than absent. Unresolved.

---

## 6. PMA

MMU-12 PMA is checked on the final translated physical address
       only, not on the virtual address and not mid-walk.

MMU-13 The attributes carried per region are cacheable, coherent,
       executable and idempotent.

MMU-14 Non-idempotent regions are never fetched speculatively and
       never prefetched. This binds the L1I-21 prefetch bit: a
       prefetch to a non-idempotent region is dropped, not
       faulted.

MMU-15 PMA comes from a static region table fixed at
       configuration, one entry per address range.

MMU-14 is what makes `itlb_decisions.md` ITLB-12 safe. Gating the
response rather than the request means the L1I array is read before
the check completes. That costs nothing for a cacheable main-memory
region, which has no side effect on read, and is unacceptable for
an I/O region. Excluding non-idempotent regions from speculation is
therefore a precondition for the timing decision, not an
independent policy.

The split is: PMA decides whether the access may be speculated,
PMP decides whether it may complete.

Ssccptr is mandatory in RVA23S64 and requires main memory regions
carrying the cacheability and coherence PMAs to support hardware
page-table reads. The walker sees the same attributes as the L1
clients.

MMU-U5 Whether Svpbmt is mandatory in RVA23S64. If it is, the PTE
       supplies a memory type and becomes a second PMA source
       alongside MMU-15, needing a precedence rule. Not confirmed
       in session-069. Unresolved.

---

## 7. Faults

MMU-16 A PMP or PMA violation on an instruction fetch raises an
       instruction access fault, cause 1. This is distinct from an
       instruction page fault, cause 12, which comes from the
       translation.

Sstvala is mandatory in RVA23S64 and requires stval to carry the
faulting virtual address for both causes.

---

## 8. Maintenance

MMU-17 SFENCE.VMA invalidates L2 TLB entries by the same forms as
       the L1 TLBs. A walk in flight when an invalidate arrives is
       completed and its result is not installed.

MMU-18 The invalidate port is a distinct port. It is written with
       the module.

TD#119 does not reach this document. That gap stops the emitted
L1I from carrying an invalidate port. The L2 TLB is written, so
its port is written with it.

---

## 9. Open

MMU-U1  L2 TLB geometry. Section 2.
MMU-U2  Outstanding walk count. Section 3.
MMU-U3  Atomic form, and the l2 third-master change. Section 4.
MMU-U4  Smepmp requirement in RVA23S64. Section 5.
MMU-U5  Svpbmt as a second PMA source. Section 6.

---

## 10. Bindings

L1I-U3    Ruled session-069 as recommended. MMU-1 to MMU-3.
L1I-U4    Ruled session-069. MMU-10 to MMU-16.
L1I-21    Bound by MMU-14.
ITLB-U1   Bounded by MMU-U2.
ITLB-12   Depends on MMU-14.
IL-*      The client boundary is `itlb_l2tlb_interfaces.md`.
          Written to be instantiated twice; the DTLB is the
          second client.
TD#118    Bounds MMU-U2.

