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

## 3a. Two-stage translation

H is MANDATORY in RVA23 through Sha, so every translation this MMU
performs is potentially two-stage.

MMU-19 The MMU supports both single-stage and two-stage
       translation. `V=0` accesses translate through `satp` only.
       `V=1` accesses translate through `vsatp` for the VS-stage
       and `hgatp` for the G-stage.

MMU-20 Shvsatpa: every translation mode supported in `satp` is
       supported in `vsatp`. Shgatpa: for each SvNN supported in
       `satp` the corresponding `hgatp` SvNNx4 mode is supported,
       and `hgatp` mode Bare is supported. Pacino is Sv39, so the
       G-stage is Sv39x4 and its root table is four times the
       normal size.

MMU-21 The walk is NESTED, not sequential. Every address the
       VS-stage walk produces is a guest physical address and
       needs its own G-stage walk before it can be used. A
       three-level VS-stage walk therefore costs up to four
       G-stage walks, one per VS-stage PTE fetch plus one for the
       final guest physical address.

MMU-21 is the reason MMU-U2, the outstanding walk count, matters
more than it did. A single two-stage walk occupies the walker for
far longer than a single-stage one, and TD#118 serialises the
memory accesses underneath it.

MMU-22 The MMU raises a GUEST page fault when the G-stage fails
       and an ordinary page fault when the VS-stage or a
       single-stage walk fails. They are distinct causes; see
       section 7.

MMU-23 Shtvala: `htval` is written with the faulting guest
       physical address on a guest page fault. The MMU produces
       that address; the trap path writes it.

MMU-24 The MMU reads the translation regime from the CSR file
       directly: `satp.PPN` for a single-stage root, `vsatp.PPN`
       and `hgatp.PPN` for the two stages, the MODE fields, and
       the ADUE bits of MMU-7 and MMU-7a.

MMU-25 It does NOT hold a current ASID or VMID. Those are
       identity, they belong to the request, and the client sends
       them. `itlb_l2tlb_interfaces.md` IL-3 and IL-3c.

The line between MMU-24 and MMU-25 is that identity is a property
of one request and the regime is not. A root pointer is not
something one request has and another does not.

---

## 4. A and D bits

MMU-6  Both Svade and Svadu are supported.

MMU-7  `menvcfg.ADUE` selects the behaviour at runtime. With ADUE
       clear the walker raises a page fault when A is clear on
       access or D is clear on write, which is Svade. With ADUE
       set the walker updates the bits in memory, which is Svadu.

MMU-7a For a `V=1` access, `henvcfg.ADUE` selects the behaviour of
       the VS-stage. `menvcfg.ADUE` continues to govern the
       G-stage. The two stages of one nested walk can therefore
       be under different rules at the same time.

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

MMU-10a ONE CHECKER, SPECIFIED HERE, INSTANTIATED TWICE. The PMP
        and PMA checker is one module. Site 1's instance sits with
        the ITLB, which has the translated physical address first;
        site 2's sits in the walker, whose addresses never reach
        an L1 TLB. This document owns the checker's behaviour; it
        does not own both instances.

MMU-10b Each instance produces cause 1 on its own response path.
        The ITLB-side instance drives `itlb_ifu_cause`
        (`itlb_ifu_interfaces.md` IT-6); the walker-side instance
        drives `l2t_itlb_cause` (`itlb_l2tlb_interfaces.md`
        IL-10). Neither the IFU nor the ITLB re-checks what the
        other produced.

MMU-10c THE IFU NEVER CHECKS. It CONSUMES a result that arrived
        with the translation. IT-12 says the results are consumed
        by the IFU before it issues an L1I request; that is
        consumption, not evaluation.

Two sites are forced, not chosen. MMU-4 has walk addresses bypass
the L1 TLBs, so a single checker at the L1 boundary would leave
walk traffic unchecked. CVA6 checks PMP on every access a walk
makes for the same reason.

MMU-11 16 PMP entries, with TOR and NAPOT address matching. The
       count is a parameter.

MMU-U4 CLOSED session-070. Smepmp is NOT mandatory in RVA23S64.
       The full mandatory privileged list was read from the
       ratified `rva23-profile.adoc`: Ss1p13, then Svbare, Sv39,
       Svade, Ssccptr, Sstvecd, Sstvala, Sscounterenw, Svpbmt and
       Svinval carried from RVA22S64, then Svnapot, Sstc,
       Sscofpmf, Ssnpm, Ssu64xl and Sha as new. Smepmp is not in
       it, nor in the expansion options. MMU-11 is unchanged at 16
       entries with TOR and NAPOT. Session-069 saw a partial list;
       this is the whole one.

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

MMU-U5 CLOSED session-070 AS MANDATORY. `rva23-profile.adoc`
       lists Svpbmt, page-based memory types, among the privileged
       extensions mandatory in RVA23S64 and carried from RVA22S64.
       So the PTE supplies a memory type and IS a second PMA source
       alongside MMU-15. The precedence rule is required, not
       conditional, and is MMU-U6.

MMU-U6 The Svpbmt precedence rule. The PTE PBMT field and the
       MMU-15 static region table both describe the memory type of
       one access. Which wins, and what happens when the PTE names
       a type the region does not support, is not decided. Bears on
       MMU-14: if a PTE can make a region non-idempotent that the
       region table calls idempotent, the speculation gate reads
       the wrong source. Unresolved.

---

## 6a. Svnapot

MMU-U7 SVNAPOT IS MANDATORY AND IS NOWHERE IN THIS TREE.
       `rva23-profile.adoc` lists Svnapot, NAPOT translation
       contiguity, among the new mandatory privileged extensions
       in RVA23S64. It was optional in RVA22 and is not.

       `itlb_decisions.md` ITLB-3 and `itlb_l2tlb_interfaces.md`
       IL-7 both name three Sv39 page sizes, 4 KiB, 2 MiB and
       1 GiB. Svnapot adds the 64 KiB contiguous case through the
       PTE N bit, so there is a fourth. `l2t_itlb_size` is two
       bits, which encodes four, so the port width survives; what
       does not survive is IL-7's wording and the ITLB's install
       path, which are written for three.

       THIS DOCUMENT HAS NO L2 TLB PAGE-SIZE DECISION TO CONTRADICT.
       MMU-1 states the topology only. L2 TLB entry count,
       associativity and page-size handling are MMU-U1, unresolved.
       So Svnapot enlarges MMU-U1 rather than overturning anything
       decided here, and it is the L1 side, ITLB-3 and IL-7, that
       carries a stated three.

       IT REACHES THE G-STAGE, NOT ONLY THE TLB ARRAYS. Privileged
       11.1.7 states that when the hypervisor extension is
       implemented, Svnapot is also supported in G-stage
       translation. H is mandatory here, so the walker of MMU-4 and
       the nested walk of MMU-21 must honour the PTE N bit at both
       stages, and a NAPOT G-stage PTE can cover a range of the
       guest physical addresses a VS-stage walk produces.

       The encoding is one case: N=1 with ppn[0] = xxxx1000 is a
       64 KiB contiguous region. Every other N=1 encoding in
       Table 7 is reserved and MUST raise a page fault, which is a
       walker obligation, not a TLB one.

       Two decisions, then. Whether the L1 TLBs store a NAPOT entry
       once and match it across the range, or store it per 4 KiB
       page. And how the walker handles N at each stage of a nested
       walk. Unresolved.

---

## 7. Faults

MMU-16 Three fault causes reach the front end from translation and
       checking:

```
   1  instruction access fault        PMP or PMA, MMU-10, MMU-12
  12  instruction page fault          single-stage, or VS-stage
  20  instruction guest-page fault    G-stage, MMU-22
```

MMU-16a Guest page fault exists because H is mandatory. It is not
        an optional third case to be dropped when H is absent,
        because H is not absent.

Sstvala is mandatory in RVA23S64 and requires stval to carry the
faulting virtual address for both causes.

---

## 8. Maintenance

MMU-17 SFENCE.VMA invalidates L2 TLB entries by the same forms as
       the L1 TLBs. A walk in flight when an invalidate arrives is
       completed and its result is not installed.

       THE FORMS ARE `itlb_decisions.md` ITLB-13, WHICH STATES ALL
       FOUR EXPLICITLY. The one worth knowing before implementing
       this: global entries are excluded only by the two forms that
       name an ASID (rs2!=x0). The address-only form, rs1!=x0 with
       rs2=x0, DOES invalidate global mappings for that address.
       ITLB-13 read otherwise until session-070. Do not re-summarise
       the four forms here; point at ITLB-13. Source is RISC-V
       Privileged chapter 11 section 11.1.2.1, version 1.13.

MMU-17a H adds two more. HFENCE.VVMA invalidates VS-stage
        translations for the current VMID, by VA and by ASID.
        HFENCE.GVMA invalidates G-stage translations, by guest
        physical address and by VMID. Both reach the L2 TLB on the
        same port as SFENCE.VMA, MMU-18, distinguished by an
        operation field rather than by a separate port.

MMU-18 The invalidate port is a distinct port. It is written with
       the module.

MMU-U8 SVINVAL IS MANDATORY AND IS NOT IN MMU-17 OR MMU-17a.
       `rva23-profile.adoc` lists Svinval, fine-grained
       address-translation cache invalidation, among the privileged
       extensions mandatory in RVA23S64 and carried from RVA22S64.

       MMU-17 and MMU-17a name three instructions: SFENCE.VMA,
       HFENCE.VVMA and HFENCE.GVMA. Svinval adds SINVAL.VMA,
       SFENCE.W.INVAL and SFENCE.INVAL.IR, and with H also
       HINVAL.VVMA and HINVAL.GVMA. Five more, and the last two are
       mandatory here because H is.

       MMU-17a already distinguishes its operations by an operation
       field rather than a separate port, so the port shape is
       likely to hold. What is not decided is whether the invalidate
       and the fence are separable inside the L2 TLB, which is the
       whole point of Svinval, or whether SINVAL.VMA is implemented
       as SFENCE.VMA and the ordering instructions as no-ops.
       The second is architecturally legal and is what most
       implementations do. Unresolved.

TD#119 does not reach this document. That gap stops the emitted
L1I from carrying an invalidate port. The L2 TLB is written, so
its port is written with it.

---

## 9. Open

MMU-U1  L2 TLB geometry. Section 2. Two-stage translation makes
        this larger than it looked: entries are tagged by VMID as
        well as ASID, and G-stage and VS-stage entries may share
        the array or be split.
MMU-U2  Outstanding walk count. Section 3.
MMU-U3  Atomic form, and the l2 third-master change. Section 4.
MMU-U4  CLOSED session-070. Smepmp is not mandatory. Section 5.
MMU-U5  CLOSED session-070. Svpbmt is mandatory. Section 6.
MMU-U6  Svpbmt precedence against MMU-15. Section 6.
MMU-U7  Svnapot. Section 6a.
MMU-U8  Svinval. Section 8.

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

---

## 13. Document History

```
  2026-09-17  session-070 audit. MMU-U4 and MMU-U5 both turned on
              the same unread list. The ratified
              rva23-profile.adoc was fetched and the RVA23S64
              mandatory privileged set read in full.

              MMU-U5 CLOSED as mandatory. Svpbmt is in the set, so
              the PTE is a second PMA source and the precedence
              rule is required. Raised as MMU-U6.

              MMU-U4 CLOSED the other way. Smepmp is absent from
              the mandatory set and from the expansion options.
              MMU-11 unchanged.

              Three mandatory extensions were found to be absent
              from every document in the tree. MMU-U7 Svnapot,
              which makes a fourth page size against the three of
              ITLB-3 and IL-7. MMU-U8 Svinval, which adds five
              instructions to the three of MMU-17 and MMU-17a.
              Ssnpm, pointer masking, was also found absent and
              was WRONGLY reported as reaching the front end. The
              ratified Pointer Masking specification v1.0 applies
              the ignore transformation to explicit memory accesses
              only and states it does not apply to implicit
              accesses such as page-table walks or instruction
              fetches. The claim came from the J extension WORKING
              DRAFT and concerns data accesses. Ssnpm has no
              front-end or fetch-path consequence. It may still
              reach the D side when the DTLB exists.

              MMU-U7 extended: privileged 11.1.7 has Svnapot
              supported in G-stage translation when H is
              implemented, so it reaches the walker and the nested
              walk, not only the TLB arrays. The reserved N=1
              encodings of Table 7 must page fault.

              MMU-U7's first draft attributed a three-page-size
              statement to MMU-1. MMU-1 states the topology only;
              page-size handling in the L2 TLB is MMU-U1 and is
              unresolved. Corrected.
```
