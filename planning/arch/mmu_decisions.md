<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# MMU Decisions
```
 FILE:    mmu_decisions.md
 SOURCE:  session-069
 STATUS:  DRAFT
 UPDATED: 2026-10-09
 CONTACT: Jeff Nye
```

Owns the MMU-N, TD-MMU-N and MMU-UN registries.

Scope is the page table walker and the PMP and PMA checkers. There
is no L2 TLB now (MMU-1, session-077); what this document says about
one is the plan for when it is added. The L1 instruction TLB is in
`itlb_decisions.md`. The L1 data TLB does not exist. Everything here
is shared I and D by construction, which is why it is not in the
ITLB document.

---

## 1. Origin

`icache_decisions.md` L1I-U3 and L1I-U4, both ruled session-069.
U4 was unrecommended and the recommendation was made and ruled in
the same session.

The walker is written from this document, the way the bpu and the
ftq were written from theirs. It is not a cachegen node. What L1I-U3
reaches into cachegen for is one thing only, and only once an L2
exists: the l2 must accept a third master, and the l2 is emitted.
That is MMU-U3.

MMU-1 WAS REVERSED session-077: there is no L2 TLB now, and the ITLB
is the walker's client directly.

---

## 2. Topology

MMU-1  THERE IS NO L2 TLB NOW. An ITLB miss goes directly to the
       page table walker. The walker is shared by the instruction
       and data sides; the DTLB, when it exists, is its second
       client. An L2 TLB is a later performance step, added with
       the DTLB and placed behind the same client port
       (itlb_l2tlb_interfaces.md). RULED session-077 (Jeff),
       REVERSING the session-069 rule, which read "One shared L2
       TLB serving the instruction and data sides. The page table
       walker is inside it."

MMU-1a THE WALKER IS OUTSIDE THE FRONT-END TOP, at rtl/mmu/ptw.
       It is shared I and D, and FE-U10 puts the front-end
       boundary between the ITLB and the shared translation level.
       tb_fe_top instantiates the front-end top and the walker
       beside it. Ruled session-077 (Jeff).

MMU-2  The walker reaches memory through its own port,
       `ptw_mem_interfaces.md`: an 8-byte read and an 8-byte
       compare-and-swap. A testbench memory model answers it,
       sharing one memory image with the model that answers the
       L1I's memory port (fe_decisions.md FE-21). THE L2 PLAN
       STANDS: when an L2 exists the walker's traffic goes on a
       master edge into it, alongside up_i and up_d, and
       icache_decisions.md L1I-25 rests on that. Ruled session-077
       (Jeff). This read "It drives a TileLink master port into
       l2, alongside up_i and up_d."

MMU-3  The L1 TLBs are clients of the walker, on the port of
       `itlb_l2tlb_interfaces.md`. A client miss is presented to
       the walker and starts a walk. This read "A client miss is
       presented to the L2 TLB; an L2 TLB miss starts a walk."

The D side has no client yet. The walker is built with one client
and the second arrives with the DTLB.

MMU-U1 CLOSED session-077 by MMU-1: there is no L2 TLB to size.
       Its geometry, and how a set-associative array holds a
       64 KiB NAPOT entry (MMU-U7), are decided when the L2 TLB is
       added. It read: "L2 TLB entry count, associativity and
       page-size handling. Comparable points: Neoverse N1 and N2
       at 1280 entries 5-way, Neoverse V2 and Cortex X2 at 2048
       8-way, Zen 2 with a split 512-entry 8-way L2 ITLB and
       2048-entry 12-way L2 DTLB."

---

## 3. Walker

MMU-4  The walker issues physical addresses directly. They do not
       pass through any L1 TLB.

MMU-5  Walk reads and the Svadu update of MMU-8 go out on the
       MMU-2 port. This read "Walk reads go out on the MMU-2
       master edge."

MMU-U2 CLOSED session-077 (Jeff). THE WALKER PERFORMS ONE WALK AT
       A TIME. A client request that arrives while a walk is in
       progress is answered retry (itlb_l2tlb_interfaces.md IL-6).
       This matches the ITLB's tracker depth of 1 (ITLB-15). More
       concurrent walks are a later performance step, measured
       with the TD#128 harness. It read: "How many walks may be
       outstanding. The l2 slave holds one transaction, TD#118, so
       concurrent walks serialise there until that is fixed."

---

## 3a. Two-stage translation

H is MANDATORY in RVA23 through Sha, so every translation this MMU
performs is potentially two-stage.

MMU-19 The MMU supports both single-stage and two-stage
       translation. `V=0` accesses translate through `satp` only.
       `V=1` accesses translate through `vsatp` for the VS-stage
       and `hgatp` for the G-stage.

MMU-19a M-MODE FETCH IS NOT TRANSLATED, whatever satp holds.
        mstatus.MPRV affects loads and stores only. Accepted
        session-075 (Jeff) as BP-118 built it.

MMU-20 Shvsatpa: every translation mode supported in `satp` is
       supported in `vsatp`. Shgatpa: for each SvNN supported in
       `satp` the corresponding `hgatp` SvNNx4 mode is supported,
       and `hgatp` mode Bare is supported. Pacino is Sv39, so the
       G-stage is Sv39x4 and its root table is four times the
       normal size.

       THE GUEST PHYSICAL ADDRESS IS 41 BITS, ZERO EXTENDED.
       Sv39x4 widens the incoming address by two bits and requires
       bits 63:41 to be zero or the access guest-page faults. With
       `V=1` and `vsatp.MODE=Bare` that address is the fetch PC
       itself, which is why VA_WIDTH is 41 and GPA_WIDTH = 41.
       fe_decisions.md FE-19, TD#122.

MMU-21 The walk is NESTED, not sequential. Every address the
       VS-stage walk produces is a guest physical address and
       needs its own G-stage walk before it can be used. A
       three-level VS-stage walk therefore costs up to four
       G-stage walks, one per VS-stage PTE fetch plus one for the
       final guest physical address.

MMU-21 is the reason the outstanding walk count matters more than
it did. A single two-stage walk occupies the walker for far longer
than a single-stage one. MMU-U2 is ruled at one walk for now.

MMU-22 The MMU raises a GUEST page fault when the G-stage fails
       and an ordinary page fault when the VS-stage or a
       single-stage walk fails. They are distinct causes; see
       section 7.

MMU-23 Shtvala: `htval` is written with the faulting guest
       physical address on a guest page fault. The MMU produces
       that address; the trap path writes it. IT IS GPA_WIDTH = 41
       BITS (MMU-20), and it travels on `l2t_itlb_gpa` and
       `itlb_ifu_gpa`, both declared `[GPA_WIDTH-1:0]`. GPA_WIDTH
       and the other ITLB widths are in bp_defines_pkg since
       BP-109 (TD#122). This read that they were defined nowhere.
       Session-074.

MMU-24 The MMU reads the translation regime from the CSR file
       directly: `satp.PPN` for a single-stage root, `vsatp.PPN`
       and `hgatp.PPN` for the two stages, the MODE fields, and
       the ADUE bits of MMU-7 and MMU-7a.

MMU-25 It does NOT hold a current ASID or VMID. Those are
       identity, they belong to the request, and the client sends
       them. `itlb_l2tlb_interfaces.md` IL-3 and IL-3c.

MMU-26 THE WALKER CHECKS G-STAGE PERMISSIONS and returns cause 20
       on a failure. Every G-stage access is treated as a
       user-mode access, so the result does not depend on the
       current privilege and can be decided once, at walk time.
       VS-stage and single-stage permissions are checked by the L1
       TLB on every hit instead (itlb_decisions.md ITLB-16),
       because privilege changes without a fence. Ruled
       session-075 (Jeff).

MMU-24a THE WALKER'S CSR INPUTS ARE ITS OWN INPUT GROUP. The
        walker is outside the front-end top (MMU-1a), so the
        front-end csr group of fe_decisions.md FE-20 does not reach
        it. Its group carries satp, vsatp and hgatp PPN and MODE,
        menvcfg and henvcfg ADUE and PBMTE, and the PMP registers
        for its checker (MMU-11a). The CSR file does not exist; the
        testbench drives the group. Ruled session-077 (Jeff).

MMU-24b THE ROOT POINTERS ALWAYS FIT. The CSR file implements
        `satp.PPN` and `hgatp.PPN` at PPN_WIDTH bits and
        `vsatp.PPN` at GPA_WIDTH - 12 = 29 bits, the bits above
        read-only zero. The privileged specification lets satp.PPN
        hold fewer than all physical page numbers, and the hgatp
        fields are WARL; vsatp.PPN is narrowed on the same footing
        as satp.PPN, whose role it takes at V=1. A root can then
        never name an address this implementation cannot form, and
        MMU-28 applies to PTEs only. No CSR file exists, so this is
        an obligation on it, and the walker's root inputs are
        declared at those widths. Ruled session-077 (Jeff).

MMU-27 THE SIZE OF A TWO-STAGE TRANSLATION is the SMALLER of the
       VS-stage leaf size and the G-stage leaf size for the final
       guest physical address, and the PPN returned is the final
       supervisor physical page at that size
       (itlb_l2tlb_interfaces.md IL-7). This holds for the 64 KiB
       NAPOT size at either stage: if the smaller size is 64 KiB,
       PA[15:12] equals VA[15:12] through both stages, so the
       ITLB's PPN[3:0] substitution (MMU-U7) is right. Stated
       session-077; no document had said it.

The line between MMU-24 and MMU-25 is that identity is a property
of one request and the regime is not. A root pointer is not
something one request has and another does not.

---

## 4. A and D bits

MMU-6  Both Svade and Svadu are supported. CONFIRMED session-077
       (Jeff), after a session-076 recommendation to narrow to
       Svade alone. Svade is mandatory in RVA23S64 and Svadu is an
       expansion option (rva23-profile.adoc); with ADUE clear the
       hardware behaves exactly as Svade, so supporting both loses
       nothing.

MMU-7  `menvcfg.ADUE` selects the behaviour at runtime. With ADUE
       clear the walker raises a page fault when A is clear on
       access or D is clear on write, which is Svade. With ADUE
       set the walker updates the bits in memory, which is Svadu.

MMU-7a For a `V=1` access, `henvcfg.ADUE` selects the behaviour of
       the VS-stage. `menvcfg.ADUE` continues to govern the
       G-stage. The two stages of one nested walk can therefore
       be under different rules at the same time. `henvcfg.ADUE`
       is read-only zero when `menvcfg.ADUE` is zero (machine
       ISA, menvcfg); that is the CSR file's rule, and the walker
       reads both bits as given.

MMU-8  THE SVADU UPDATE IS A COMPARE AND STORE, the privileged
       translation algorithm's step 9. When ADUE selects Svadu for
       the stage and the leaf PTE has A clear (fetch never needs
       D), the walker:
         - checks that a STORE to the PTE passes PMP and PMA
           (MMU-10d, MMU-12a); otherwise access fault, cause 1;
         - compares the PTE it read against memory and, if they
           are equal, stores the PTE with A set, as ONE atomic
           operation on the MMU-2 port (ptw_mem_interfaces.md);
         - if they are not equal, restarts the walk from step 2.
       Every check of the leaf is made before the update. The
       translation is returned to the client only after the update
       has completed, so the update precedes the fetch that needed
       it in the global order, as the specification requires.
       The walker also holds the D update for the data-side client;
       until a DTLB exists it is checked at walker unit level only.
       This read "The Svadu update is atomic with respect to other
       harts. The walker performs it as a read-modify-write that
       cannot be split." A read-modify-write does not compare, and
       the compare is what stops the walker setting A on a PTE
       software changed after it was read. Corrected session-077.

MMU-8a UNDER H, a VS-stage PTE is in guest physical memory, so its
       update is a store through the G-stage. The G-stage leaf
       must grant write, checked as an implicit store at user
       level (MMU-26), and the update sets the G-stage leaf's A
       and D under `menvcfg.ADUE`, or raises a guest-page fault
       under Svade at the G-stage. A failure is cause 20, reported
       for the original access type, with implicit-access kind
       WRITE (MMU-29). Stated session-077 from the hypervisor
       chapter, two-stage address translation.

MMU-8b SPECULATION. A walk for a wrong-path fetch may set A: the
       specification permits A updates as a result of speculation,
       and permits a VS-stage A update only when the effective
       mode is VS or VU, which every `V=1` fetch is. The G-stage D
       set by a VS-stage update may be speculative only when the
       G-stage PTE grants write, which MMU-8a requires anyway. A
       walk killed by an invalidate (ITLB-14) may already have set
       A; that is permitted. Stated session-077.

MMU-9  The MMU-2 port is not read-only: it carries the
       compare-and-swap of MMU-8. Supporting Svadu fixes the port
       type, which is why MMU-6 is recorded here and not left
       implicit; Svade alone would have permitted a read-only
       port. This read that the edge's TileLink conformance level
       must include atomics; that is the L2 plan, MMU-U3.

MMU-U3 OPEN, MOVED TO THE L2 WORK (session-077). Two parts. How the
       compare-and-swap of MMU-8 is carried when the walker's port
       goes into an L2 (MMU-2): TileLink's atomic operations, as
       the PA recalls them, include no compare-and-swap, so either
       the L2 adds one or the walker builds it from another
       primitive; check the TileLink specification before the L2
       task. And whether the emitted l2 needs a schema or emitter
       change to accept a third master. Neither is needed while a
       testbench answers the port. This read "Whether the MMU-8
       atomic is a TileLink AMO on the MMU-2 port or a reservation
       pair."

---

## 5. PMP

MMU-10 PMP is checked at two sites. On the translated physical
       address before any L1 request is issued (itlb_decisions.md
       ITLB-12), and on every address the walker issues. This read
       "before an L1 access completes", the response-gating form
       ITLB-12 withdrew. Session-071.

MMU-10a ONE CHECKER, SPECIFIED HERE, INSTANTIATED TWICE. The PMP
        and PMA checker is one module. Site 1's instance sits with
        the ITLB, which has the translated physical address first;
        site 2's sits in the walker, whose addresses never reach
        an L1 TLB. This document owns the checker's behaviour; it
        does not own both instances. BUILT by BP-118 as
        rtl/mmu/pmp/rtl/pmp_pma_chk.sv, instantiated inside the
        ITLB. References for the PMP rules are in the BP-118
        record: tools/spike's csrs.cc and mmu.cc.

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

MMU-10d THE WALKER'S ACCESSES ARE CHECKED AT PRIVILEGE S, whatever
        the current privilege: the machine ISA, PMP and paging,
        gives the effective privilege of implicit page-table
        accesses as S. A PTE read is checked as a read and the
        Svadu update of MMU-8 as a write. The checker therefore
        takes an access type and a privilege; the walker's
        instance always presents S. The walker's instance sits in
        rtl/mmu/ptw. Ruled session-077 (Jeff), checked against
        machine.adoc.

Two sites are forced, not chosen. MMU-4 has walk addresses bypass
the L1 TLBs, so a single checker at the L1 boundary would leave
walk traffic unchecked. CVA6 checks PMP on every access a walk
makes for the same reason.

MMU-11 16 PMP entries, with TOR and NAPOT address matching. The
       count is a parameter. THE GRAIN IS 4 KiB, G = 10, accepted
       session-075 (Jeff) as BP-118 built it: the ITLB checks one
       page base per entry, which is exact only when no PMP
       boundary falls inside a page, and a 4 KiB grain guarantees
       that. The privileged specification leaves G to the
       platform.

MMU-11a THE CHECKER READS THE PMP REGISTERS AS INPUTS. The pmpcfg
        and pmpaddr values and the current privilege come in on a
        CSR input group; the checker holds no CSR. Each instance
        takes the group from its parent. For the ITLB-side
        instance that group crosses the front-end boundary
        (fe_decisions.md FE-20), because the CSR file does not
        exist. Ruled session-075 (Jeff).

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

MMU-12 PMA IS CHECKED ON EVERY PHYSICAL ACCESS: the final
       translated address of a fetch (ITLB-12), and every PTE read
       and every Svadu update the walker makes. The privileged
       translation algorithm raises an access fault of the
       original access type when a PTE access violates a PMA or
       PMP check (steps 2 and 9); for a fetch that is cause 1. Not
       on the virtual address. This read "PMA is checked on the
       final translated physical address only, not on the virtual
       address and not mid-walk", which the specification
       contradicts. Corrected session-077.

MMU-12a PAGE TABLES MUST BE IN A REGION THAT IS CACHEABLE AND
        COHERENT (MMU-13 bits [0] and [1]). A PTE read or update
        anywhere else is an access fault, cause 1. Legal: the
        machine ISA lets each region say which hardware page-table
        reads and writes it supports, Ssccptr requires them only in
        cacheable, coherent main memory, and Svadu requires page
        tables in memory with hardware page-table write access and
        RsrvEventual, which Ziccrse gives main memory. Ruled
        session-077 (Jeff).

MMU-13 The attributes carried per region are cacheable, coherent,
       executable and idempotent. Wherever they travel as a
       PMA_WIDTH vector the positions are [0] cacheable,
       [1] coherent, [2] executable, [3] idempotent. Session-074,
       as BP-116 built it (itlb_ifu_interfaces.md IT-10).

MMU-14 Non-idempotent regions are never fetched speculatively and
       never prefetched. This binds the L1I-21 prefetch bit: a
       prefetch to a non-idempotent region is dropped, not
       faulted. The attributes are the EFFECTIVE ones of MMU-U6,
       not the region table's alone: a fetch uses the L1I only
       when the effective type is cacheable and idempotent, and
       otherwise takes the uncached path of `ifu_decisions.md`
       IFU-21, which since session-076 goes through the L1I marked
       uncached and does not allocate (icache_decisions.md L1I-24).
       So a page marked NC or IO never allocates in the L1I. Session-071; this
       read "Non-idempotent regions" against the region table only.

MMU-15 PMA comes from a static region table fixed at
       configuration, one entry per address range.

MMU-15a THE REGION TABLE IS A PARAMETER OF THE CHECKER, and its
        default is one main-memory region and a default for the
        rest. Ruled session-075 (Jeff):

```
  0x0_8000_0000 .. 0xF_FFFF_FFFF   main memory, 62 GiB
                                   cacheable, coherent,
                                   executable, idempotent
  everything else                  none of the four
```

        Main memory starts at the reset vector (ftq_decisions.md
        4.7) and runs to the top of the 36-bit physical space
        (l1i_ifu_interfaces.md IF-1). 64 GiB is the whole space at
        PA_WIDTH 36, so 62 GiB is the most main memory there can
        be above 0x8000_0000; a larger memory needs a wider
        PA_WIDTH, which moves PPN_WIDTH, the ITLB entry, l1i_pkg
        and cachegen's pa_bits together. The shape is XiangShan's
        documented map: main memory from 0x8000_0000 to the top of
        the physical space, devices below it, which in pacino are
        not yet placed. The table classifies addresses and costs
        no storage, so a later device map changes the parameter
        and nothing else.

MMU-15b NON-IDEMPOTENT MEMORY IS NEVER EXECUTABLE. The region
        table of MMU-15a never marks a region executable unless it
        is also idempotent, and the checker rejects such a parameter
        at elaboration. An instruction fetch therefore never reads a
        device. The only uncached fetch is from main memory whose
        PTE makes it NC or IO (MMU-U6), and a whole-line read there
        has no side effect, so the uncached path needs no narrow
        read. RULED session-076 (Jeff). Closes ifu_decisions.md
        IFU-U4. A later device map that wants executable device
        memory, such as a boot ROM, places it in an idempotent
        region.

`itlb_decisions.md` ITLB-12 gates the REQUEST: the PMP permission
check, the PMA executable check and the PMA idempotent read all
complete in the IFU's translation pipeline before any L1I request is
issued, so the L1I array is never read for an access that fails
them. MMU-14 stands on its own: a non-idempotent region takes the
uncached path of `ifu_decisions.md` IFU-21 and is never fetched
speculatively or prefetched, because a read there can have a side
effect whether or not it is permitted.

The split is: PMA decides whether the access may be speculated,
PMP decides whether it may be issued.

AN EARLIER REVISION of this paragraph had MMU-14 make ITLB-12 safe,
on ITLB-12's withdrawn form: gating the response rather than the
request, so the L1I array was read before the check completed and
MMU-14 was the precondition for that timing decision. ITLB-12 was
revised in session-069 and this paragraph was not. Session-071.

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

MMU-U6 CLOSED session-071 (Jeff). THE EFFECTIVE MEMORY TYPE IS
       THE MOST RESTRICTIVE of the MMU-15 region table, the G-stage
       PBMT and the VS-stage PBMT. A PTE can make an access less
       cacheable, non-idempotent or strongly ordered, never the
       reverse; the region table still decides what the memory is.
       Ordered PMA < NC < IO, the walker returns the more
       restrictive of the two stages' PBMT as one 2-bit value
       (itlb_l2tlb_interfaces.md IL-9), the L1 TLB stores it per
       entry, and on a hit combines it with the region attributes
       of the physical address. The combination is order-free, so
       the specification's G-stage-then-VS-stage override sequence
       needs no separate handling.

       THIS IS A LEGAL STRICT IMPLEMENTATION OF SVPBMT'S OVERRIDE,
       not the override as the specification describes it. The
       specification lets NC on an I/O region make accesses
       idempotent and weakly ordered, and names write-combining and
       speculative access as the use. Those relaxations are
       permissions: forgoing speculation is always legal and
       stronger ordering always satisfies RVWMO. The cost is on the
       D side, where a driver mapping device memory NC gets
       strongly-ordered, non-speculative access. XiangShan gates its
       uncached path the same way, on the region's MMIO bit OR a
       non-PMA PBMT.

       WALKER OBLIGATIONS, beside the Svnapot ones of MMU-U7:
       PBMT = 3 is reserved and raises a page fault; with
       menvcfg.PBMTE clear, or henvcfg.PBMTE clear for the G-stage,
       bits 62-61 of a leaf PTE must be zero and a non-zero value
       raises a page fault; bits 62-61 of a non-leaf PTE are
       reserved. Cause 12 at a single or VS stage, 20 at the
       G-stage (MMU-16).

       It read: "Which wins, and what happens when the PTE names a
       type the region does not support, is not decided." 

---

## 6a. Svnapot

MMU-U7 SVNAPOT IS MANDATORY AND IS NOWHERE IN THIS TREE.
       `rva23-profile.adoc` lists Svnapot, NAPOT translation
       contiguity, among the new mandatory privileged extensions
       in RVA23S64. It was optional in RVA22 and is not.

       `itlb_decisions.md` ITLB-3 and `itlb_l2tlb_interfaces.md`
       IL-7 named three Sv39 page sizes, 4 KiB, 2 MiB and 1 GiB,
       until session-071; both now name four. Svnapot adds the
       64 KiB contiguous case through the
       PTE N bit, so there is a fourth. `l2t_itlb_size` is two
       bits, which encodes four, so the port width survived; IL-7's
       wording and the ITLB's install path, written for three, were
       updated session-071.

       THIS DOCUMENT HAS NO L2 TLB PAGE-SIZE DECISION TO CONTRADICT.
       There is no L2 TLB now (MMU-1, session-077); its entry count,
       associativity and page-size handling are decided when it is
       added (MMU-U1, closed). So Svnapot enlarges that later work
       rather than overturning anything decided here, and it is the
       L1 side, ITLB-3 and IL-7, that carries a stated three. This
       read "are MMU-U1, unresolved".

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

       RULED session-071 (Jeff):
         - a NAPOT entry is HELD ONCE in the L1 TLB, which is fully
           associative (ITLB-2), and matched across its range by
           masking VPN[3:0] out of the compare, the same mechanism
           the 2 MiB and 1 GiB sizes use
         - on every output, at BOTH stages, PPN[3:0] is REPLACED by
           VPN[3:0] (for the G-stage, by GPA[15:12]); the stored
           PPN[3:0] is the size marker, not an address
         - reserved N encodings page-fault IN THE WALKER, at each
           stage of the nested walk, cause 12 or 20 (MMU-16)
       The PBMT reserved-encoding and PBMTE checks of MMU-U6 are
       the same kind of walker obligation.

       The two output sites are the ones public implementations
       have got wrong: CVA6 issue 3569 substitutes on the
       first-stage output and not the G-stage one, and QEMU's IOMMU
       model did not check N at all and produced an address 32 KB
       off. The test plan must cover a 64 KiB mapping at each stage
       and every reserved N encoding.

       MOVED TO THE L2 TLB WORK (MMU-1, MMU-U1 closed session-077):
       how a set-associative L2 TLB holds a NAPOT entry. The
       published precedent (Rocket, arXiv 2406.17802) drops
       VPN[3:0] from the index. It read "Two decisions, then ...
       Unresolved."

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

MMU-U9  CLOSED session-077 by MMU-28 to MMU-30, after reading the
        ratified supervisor and hypervisor chapters. It read: "A PTE
        PPN WIDER THAN THE IMPLEMENTED PHYSICAL ADDRESS IS NOT
        CHECKED ANYWHERE. ... Both a page fault at the stage that
        read the PTE (cause 12 or 20) and an access fault from the
        MMU-10 PMP check (cause 1) are defensible." The roots are
        MMU-24b.

MMU-28  A PPN IS NEVER TRUNCATED. The supervisor chapter states that
        the translation algorithm does not admit ignoring
        high-order PPN bits on an implementation with fewer
        physical address bits. Bits 53:10 of a Sv39 PTE are all
        PPN, so a large PPN is not a reserved-bit page fault. The
        walker reads all 44 PPN bits of every PTE:
          - a PTE whose PPN is a SUPERVISOR physical page (single
            stage, or G-stage): a bit set above bit 23 names an
            address outside every PMA region, so the access made
            with it -- the next PTE read, or the fetch -- is an
            access fault, cause 1;
          - a PTE whose PPN is a GUEST physical page (VS-stage): a
            guest physical address with a bit set above bit 40 is a
            guest-page fault, cause 20 (Sv39x4, hypervisor
            chapter).
        The checks fall where the algorithm's steps put them, so a
        page fault found earlier in the walk is reported first. The
        ITLB is never filled with a truncated PPN. Ruled
        session-077 (Jeff).

MMU-29  THE IMPLICIT-ACCESS KIND. A guest-page fault the walker
        raises carries, beside its guest physical address
        (MMU-23), a two-bit kind:
          2'b00  the GPA is the fetch's own guest physical address
          2'b01  an implicit READ of a VS-stage page table
          2'b10  an implicit WRITE of one, the Svadu update (MMU-8a)
          2'b11  reserved
        Shtvala makes htval carry the faulting guest physical
        address, including for an implicit access, and the
        hypervisor chapter then forbids htinst zero: it must be the
        pseudoinstruction 0x00003000 (64-bit read) or 0x00003020
        (64-bit write). The backend chooses htinst from this kind;
        the front end carries it (itlb_l2tlb_interfaces.md IL-11b,
        itlb_ifu_interfaces.md IT-6c, dcd_decisions.md DCD-16).
        Ruled session-077 (Jeff).

MMU-30  A GUEST PHYSICAL ADDRESS THAT DOES NOT FIT. When the faulting
        guest physical address has a bit set above bit 40 (MMU-28),
        the GPA returned is 0 and the kind of MMU-29 is still
        given. The hypervisor chapter lets htval be written with
        zero, and with htval zero htinst may be zero, so the backend
        reads the kind only for a non-zero GPA. Whether this meets
        Shtvala's "in all circumstances permitted by the ISA" is an
        interpretation, recorded as one: htval is a WARL register
        that need hold only a subset of guest physical addresses,
        and this address is outside the 41-bit guest space. Ruled
        session-077 (Jeff).

Sstvala is mandatory in RVA23S64 and requires stval to carry the
faulting virtual address for page-fault, access-fault and
misaligned exceptions on load, store and instruction, and for
breakpoint exceptions that write an address (rva23-profile.adoc).
That covers causes 1 and 12. IT DOES NOT NAME CAUSE 20: for a
guest-page fault the profile mandates Shtvala, htval written with
the faulting guest physical address (MMU-23), and Shvstvala,
vstval written in all the cases described for stval. What stval
holds on cause 20 is the ISA's rule, not Sstvala's.

The VA travels with the cause on all three inside the front end
regardless, because the IFU pairs them (itlb_ifu_interfaces.md
IT-5, ifu_ibuf_interfaces.md IB-9); that is this design's doing,
not a profile requirement. This read "for both causes" until
session-072, then "for ALL THREE causes, cause 20 included,"
which attributed to Sstvala more than it says. Session-072.

---

## 8. Maintenance

MMU-17 THE WALKER HOLDS NO TRANSLATION, so it has no invalidate
       port while there is no L2 TLB. A walk in progress when the
       ITLB receives an invalidate completes, and the ITLB discards
       its result (ITLB-14, IL-13, IL-14). Ruled session-077 (Jeff)
       with MMU-1.

       WHEN AN L2 TLB IS ADDED: SFENCE.VMA invalidates its entries
       by the same forms as the L1 TLBs, and a walk in flight when
       an invalidate arrives is completed and its result is not
       installed. This read so of the L2 TLB as built.

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
        physical address and by VMID. Both reach the ITLB on its
        port, ITLB-14, with an operation field; when an L2 TLB is
        added they reach it the same way, MMU-18, distinguished by
        an operation field rather than by a separate port. This
        read as of a built L2 TLB; session-077.

MMU-18 The L2 TLB's invalidate port, when it is added, is a
       distinct port written with the module. This read as of a
       built L2 TLB; session-077.

MMU-17 and MMU-17a name three instructions; the five Svinval
instructions are handled by MMU-U8 below. Session-071.

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
       implementations do.

       ADOPTED session-071 (Jeff), the second:
         SINVAL.VMA      = SFENCE.VMA,  same four rs1/rs2 forms
         HINVAL.VVMA     = HFENCE.VVMA
         HINVAL.GVMA     = HFENCE.GVMA
         SFENCE.W.INVAL  no operation at the TLBs
         SFENCE.INVAL.IR no operation at the TLBs
       The invalidates arrive on the MMU-18 and ITLB-14 ports with
       the operation field of MMU-17a; no port changes. XiangShan
       Kunminghu does the same: its TLB treats Svinval.vma and
       Sfence.vma identically. Any ordering the two fences imply
       outside the TLBs belongs to the backend.

TD#119 does not reach this document. That gap stops the emitted
L1I from carrying an invalidate port.

---

## 9. Open

MMU-U1  CLOSED session-077 by MMU-1: no L2 TLB now. Section 2.
MMU-U2  CLOSED session-077: one walk at a time. Section 3.
MMU-U3  The L2 half of the Svadu atomic, and the l2 third-master
        change. Moved to the L2 work. Section 4.
MMU-U4  CLOSED session-070. Smepmp is not mandatory. Section 5.
MMU-U5  CLOSED session-070. Svpbmt is mandatory. Section 6.
MMU-U6  CLOSED session-071. Most restrictive of region and both
        PBMTs. Section 6.
MMU-U7  CLOSED session-071 for the L1 TLB and the walker; the L2
        TLB half moved to the L2 TLB work (MMU-1). Section 6a.
MMU-U8  CLOSED session-071. Svinval as the fence equivalents.
        Section 8.
MMU-U9  CLOSED session-077 by MMU-28 to MMU-30. Section 7.

---

## 10. Bindings

L1I-U3    Ruled session-069 as recommended. MMU-1 to MMU-3.
L1I-U4    Ruled session-069. MMU-10 to MMU-16.
L1I-21    Bound by MMU-14.
ITLB-U1   Closed by ITLB-15; MMU-U2 closed at one walk.
ITLB-12   Gates the request; MMU-10 site 1. It no longer depends
          on MMU-14, which read "Depends on MMU-14" until
          session-071.
IL-*      The client boundary is `itlb_l2tlb_interfaces.md`.
          Written to be instantiated twice; the DTLB is the
          second client.
TD#118    No longer bounds the walker, which has its own port
          (MMU-2). It bounds the L2 plan.

---

## 11. Document History

```
  2026-09-22  session-073. MMU-U9 raised from TD#122: with
              PPN_WIDTH ruled at 24 against a 44-bit PTE PPN
              field, nothing faults a PTE that names a physical
              address this implementation cannot form. The cause
              and the stage are not ruled, and the specification
              has not been checked.

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

  2026-09-19  session-071. MMU-10 and the MMU-14 paragraph restated
              against ITLB-12 as revised in session-069: the checks
              gate the L1I REQUEST, so the L1I array is never read
              before they complete and MMU-14 is no longer the
              precondition for a timing decision. The bindings
              entry for ITLB-12 corrected to match.
  2026-09-19  session-071. MMU-17 and MMU-17a marked incomplete
              against MMU-U8. ITLB-3, IL-7, IL-9 and IL-12 now
              point to MMU-U7, MMU-U6 and MMU-U8 instead of stating
              complete sets.
  2026-09-19  session-071, rulings (Jeff). MMU-U6 closed: the
              effective type is the most restrictive of region and
              both PBMTs, with the PBMT walker checks. MMU-U7 ruled:
              NAPOT held once, masked match, PPN[3:0] substituted on
              every output at both stages, reserved N faults in the
              walker; the L2 TLB half stays in MMU-U1. MMU-U8
              adopted: Svinval as its fence equivalents. MMU-14
              reads the effective attributes and sends
              non-cacheable fetch to the uncached path.

  2026-09-20  session-072. section 7: Sstvala named two causes
              beside a three-cause table; all three carry stval,
              and htval carries the GPA on cause 20.

  2026-09-20  session-072. E3: the history section renumbered 13 to 11;
              11 and 12 do not exist.

  2026-09-20  session-072. D30: Sstvala's requirement stated as the
              profile defines it; cause 20 is Shtvala and
              Shvstvala, not Sstvala.

  2026-10-01  session-074. MMU-13 fixes the PMA bit positions as
              BP-116 built them. MMU-23 no longer says the widths
              are undefined; BP-109 declared them.

  2026-10-07  session-075, rulings (Jeff). MMU-11a: the checker
              takes the PMP registers on an input group. MMU-15a:
              the region table is a parameter, default main memory
              0x8000_0000 to the top of the 36-bit space. MMU-26:
              G-stage permissions are checked by the walker.

  2026-10-07  session-075, after BP-118. MMU-10a built. MMU-11:
              the PMP grain is 4 KiB. MMU-19a: M-mode fetch is not
              translated.

  2026-10-09  session-076, rulings (Jeff). MMU-15b: non-idempotent
              memory is never executable, enforced on the region
              table parameter. MMU-14: the uncached path goes
              through the L1I without allocating (IFU-21 reversed).

  2026-10-09  session-077, rulings (Jeff), for BP-123. MMU-1
              REVERSED: no L2 TLB now; the walker serves the ITLB
              directly, outside the front-end top (MMU-1a), on its
              own memory port (MMU-2, ptw_mem_interfaces.md). MMU-6
              confirmed, full Svadu. MMU-U1 and MMU-U2 closed (one
              walk at a time). MMU-U9 closed by MMU-28 to MMU-30,
              checked against the ratified supervisor and
              hypervisor chapters. MMU-24a, MMU-24b, MMU-27,
              MMU-12a, MMU-10d added.

              Corrected against the specification: MMU-8 is a
              compare and store, not a read-modify-write; MMU-12
              checks PMA on every walker access, not on the final
              address only; MMU-8a and MMU-8b state the H and
              speculation rules. MMU-17 and MMU-18 restated for a
              walker with no translation cache. MMU-U3 moved to
              the L2 work.
```
