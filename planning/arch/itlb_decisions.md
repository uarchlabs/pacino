<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# L1 Instruction TLB Decisions
```
 FILE:    itlb_decisions.md
 SOURCE:  session-069
 STATUS:  DRAFT
 UPDATED: 2026-09-19
 CONTACT: Jeff Nye
```

Owns the ITLB-N, TD-ITLB-N and ITLB-UN registries.

Scope is the L1 instruction TLB only. The shared L2 TLB, the page
table walker, and the PMP and PMA checkers are in
`mmu_decisions.md`. This document names the ITLB side of each
boundary and does not restate the other side.

The ITLB is written from this document. cachegen currently does
not support TLB generation.

---

## 1. Origin

`icache_decisions.md` L1I-U2 asked for the ITLB parameters and
L1I-U3 for the walker topology. Both were ruled in session-069.
This document records the ITLB half. TD#115 closes on it.

L1I-3 makes the L1I physically indexed, so translation sits in the
fetch path ahead of the array. `l1i_ifu_interfaces.md` IF-8 has the
IFU issue only on a valid non-faulting translation.

---

## 2. Array

ITLB-1  64 entries.

ITLB-2  Fully associative.

ITLB-3  One array holds every page size: the three Sv39 sizes,
        4 KiB, 2 MiB and 1 GiB, and the 64 KiB Svnapot case. No
        separate large-page array. A NAPOT entry is HELD ONCE and
        matched across its range by masking VPN[3:0] out of the
        compare; on a hit the output PPN[3:0] is VPN[3:0], not the
        stored value, which is the size marker (mmu_decisions.md
        MMU-U7, ruled session-071). Svnapot is mandatory in
        RVA23S64. This read "all three Sv39 page sizes".

ITLB-3a Each entry also holds the page's PBMT, the more restrictive
        of the two stages' values as returned on
        itlb_l2tlb_interfaces.md IL-9. On a hit it is combined with
        the region attributes of the physical address to give the
        effective type (mmu_decisions.md MMU-U6). Session-071.

ITLB-4  ASID tagged. Entries carry an ASID field and a global bit
        taken from the PTE G bit. A global entry matches
        regardless of ASID.

ITLB-4a VMID tagged as well, and carry a V bit. H is mandatory in
        RVA23 through Sha, so an entry is either a `V=0`
        single-stage translation or a `V=1` two-stage one, and a
        `V=1` entry belongs to one guest. A hit requires the V bit
        to match, and for `V=1` the VMID to match. The global bit
        applies within a VMID, not across guests.

ITLB-5  Hit latency is one cycle. The PMP and PMA check is not in
        this path. See ITLB-12.

64 fully associative holding all page sizes in one array is the Zen
shape, which is the largest fully associative L1 ITLB found in the
survey. Neoverse N1 and V2 and XiangShan Kunminghu are at 48. The
only 128-entry L1 ITLB in the survey, Broadwell, is 4-way with a
separate 8-entry array for large pages, so it is not evidence that
64 fully associative can be exceeded.

---

## 3. Replacement and sizing

ITLB-6  Replacement is not-most-recently-used over the 64 entries.

ITLB-7  ASID width is 16 bits, the Sv39 maximum. VMID width is 14
        bits, the Sv39x4 maximum.

Neither of these was in the L1I-U2 recommendation. Both are
required to build the array and are recorded here rather than left
unstated.

---

## 4. Miss protocol

ITLB-8  The ITLB is non-blocking. On a miss it returns a miss
        response to the requester and remains available to serve
        hits from other requests while the walk is outstanding.

ITLB-9  The requester re-requests. The ITLB does not hold the
        faulting request and does not retry on the requester's
        behalf.

ITLB-10 The ITLB tracks outstanding walks and does not issue a
        second walk for a VA and ASID that already has one in
        flight. A re-request that matches an in-flight walk
        receives a miss response without generating walk traffic.

ITLB-10 is the consequence of ITLB-9. The requester re-requests the
same VA while the walk is outstanding, so without a match against
in-flight walks the ITLB issues duplicate walks for every retry.
This is the same shape as the L1I-14 MSHR target problem.

ITLB-U1 The depth of the in-flight walk tracker. One outstanding
        walk makes ITLB-8 mean only that hits continue during a
        miss. More than one requires the walker to accept more
        than one, which is an `mmu_decisions.md` question and is
        bounded by how many transactions the l2 slave accepts,
        TD#118. Unresolved.

---

## 5. Faults

ITLB-11 The ITLB returns a fault cause, not a single non-faulting
        bit. Three outcomes: hit, miss, fault.

The faulting virtual address is not returned on the port. The IFU
supplied it and holds it against the request tag, and pairs it
with the cause on the way into `predecode_pkt_t`.
`itlb_ifu_interfaces.md` IT-5. The pair still reaches the backend
as Sstvala requires; it is assembled one step later.

Three fault causes reach the IFU: instruction access fault, cause 1,
from the PMP or PMA check in `mmu_decisions.md`; instruction page
fault, cause 12, from a single-stage or VS-stage translation; and
instruction guest-page fault, cause 20, from the G-stage. The third
exists because H is mandatory in RVA23 through Sha. The IFU cannot
collapse them.

Sstvala is mandatory in RVA23S64 and requires stval to carry the
faulting virtual address for instruction page-fault and access-fault
exceptions, so the VA travels with the cause.

`l1i_ifu_interfaces.md` needs no amendment for this. IF-8 is a
gate condition, issue only on a valid non-faulting translation,
and section 8 already separates what lies behind it: IF-23 is the
fault case and IF-24 the miss case. Nothing there collapses two
causes into one bit.

---

## 6. Check placement

ITLB-12 The PMP permission check, the PMA executable check and the
        read of the EFFECTIVE cacheable and idempotent attributes
        (ITLB-3a, mmu_decisions.md MMU-14) all complete BEFORE any
        L1I request is issued. A request that fails them is never
        made. This read "the PMA idempotent read"; the effective
        type includes the PTE's PBMT. Session-071.

ITLB-12a None of these checks is in the ITLB-5 hit path. They run
         in the translation pipeline, `ifu_decisions.md` IFU-23a,
         which is a whole pipeline ahead of the fetch pipeline
         that issues to the L1I. The translation returns at the
         ITLB-5 latency and the checks complete before the result
         leaves the queue.

AN EARLIER REVISION OF ITLB-12 HAD THE CHECK GATE THE RESPONSE
RATHER THAN THE REQUEST, on the reasoning that a serial check after
a fully-associative hit would not fit in one cycle and that
L1iReadLatency of 2 left a cycle to hide it in. Two things were
wrong with it.

It contradicted `l1i_ifu_interfaces.md` IF-22, which states that a
faulting request never reaches the L1I and that this interface
carries no fault port in either direction. Letting a PMP failure
reach the array and blocking only the response is exactly the
traffic IF-22 forbids.

And its timing argument counted sixty-four PMP range compares.
MMU-11 sets sixteen entries.

The argument is moot in any case. The IFU now translates in a
pipeline ahead of fetch, so the checks have a pipeline to complete
in rather than a cycle, and gating the request costs nothing.
Session-069.

The idempotent read was separated from the other two in an earlier
revision because a check that gates a response cannot also decide
whether a request is made. With ITLB-12 gating the request, the
separation is unnecessary: all three are read before the request
and all three can stop it. MMU-14 and IT-11 are unchanged.

---

## 7. Maintenance

ITLB-13 SFENCE.VMA invalidates ITLB entries by VA, by ASID, by
        both, or all. GLOBAL ENTRIES ARE EXCLUDED BY THE TWO FORMS
        THAT NAME AN ASID, not by everything except the all form.
        The four forms, from RISC-V Privileged Architecture
        chapter 11, Supervisor-Level ISA version 1.13, section
        11.1.2.1 (library version v20260120):

```
  rs1=x0,  rs2=x0    all entries, all address spaces   global INCLUDED
  rs1=x0,  rs2!=x0   that ASID                         global EXCLUDED
  rs1!=x0, rs2=x0    that VA, all address spaces       global INCLUDED
  rs1!=x0, rs2!=x0   that VA and that ASID             global EXCLUDED
```

        The specification attaches "except for entries containing
        global mappings" to the two rs2!=x0 forms only. The
        address-only form invalidates entries for the address in
        rs1 "for all address spaces", with no exclusion stated.
        Corroborated from the other side by the G bit description
        in 11.1.3.1: global mappings need not be flushed when
        SFENCE.VMA is executed with rs2!=x0. The exclusion is tied
        to rs2!=x0 exactly.

        AN EARLIER REVISION SAID "global entries are invalidated
        only by the all form". That dropped the address-only form
        and would leave a stale global translation alive across
        `sfence.vma rs1, x0`. That is a correctness bug, not a
        prediction-quality one: the ITLB would answer a later fetch
        from an invalidated mapping. Corrected session-070.

        It affects `V=0` entries and, when executed in VS-mode, the
        current guest's VS-stage entries.

ITLB-13a HFENCE.VVMA invalidates `V=1` VS-stage entries for the
         current VMID, by VA and by ASID. HFENCE.GVMA invalidates
         `V=1` entries by guest physical address and by VMID.
         Both arrive on the ITLB-14 port with an operation field.

         HFENCE.VVMA CARRIES THE SAME GLOBAL RULE AS ITLB-13. The
         privileged specification says its effect "is much the same
         as temporarily entering VS-mode and executing SFENCE.VMA",
         so it has the same four rs1/rs2 forms and global entries
         are excluded only by the two that name an ASID (rs2!=x0).
         The VA-only form invalidates global VS-stage mappings for
         that address. Global is per-VMID here, not across guests,
         ITLB-4a. Checked session-070 when ITLB-13 was corrected.

         HFENCE.GVMA HAS NO GLOBAL CASE. It selects by guest
         physical address and VMID and takes no ASID, so the
         exclusion has nothing to key on.

ITLB-14 The invalidate port is a distinct port, not carried on the
        translation request path. It is written with the module.

ITLB-13b Svinval, mandatory in RVA23S64, per mmu_decisions.md
         MMU-U8 (adopted session-071): SINVAL.VMA acts as
         SFENCE.VMA with ITLB-13's four forms and global rule,
         HINVAL.VVMA as HFENCE.VVMA and HINVAL.GVMA as HFENCE.GVMA
         (ITLB-13a), all on the ITLB-14 port. SFENCE.W.INVAL and
         SFENCE.INVAL.IR do nothing at the ITLB.

TD#119 does not reach this document. It is the cachegen schema
gap that stops the emitted L1I from carrying an invalidate port.
The ITLB is written from this document, so its port is written
with it.

---

## 8. Open

ITLB-U1  In-flight walk tracker depth. Section 4.

MMU-U6, MMU-U7 and MMU-U8, which bounded ITLB-3, ITLB-3a, ITLB-12
and section 7, were ruled session-071.

---

## 9. Bindings

L1I-3     PIPT, translation ahead of the array.
L1I-U2    Ruled session-069 at 64 entries, ITLB-1 to ITLB-5.
L1I-U3    Ruled session-069 as recommended, walker side in
          `mmu_decisions.md`, ITLB side in section 4.
IF-8      The gate condition. IF-23 and IF-24 behind it already
          separate fault from miss.
TD#115    Closed by this document.
IT-*      The IFU boundary is `itlb_ifu_interfaces.md`.
IL-*      The L2 TLB boundary is `itlb_l2tlb_interfaces.md`.
          IL-5 is deliberately the opposite of ITLB-8: a miss
          there holds the transaction open rather than ending it.
TD#118    Bounds ITLB-U1.

---

## 10. Document History

```
  2026-09-17  session-070 audit. ITLB-13 corrected. It read "Global
              entries are invalidated only by the all form", which
              is short by one form: the ratified privileged
              specification attaches the global exclusion to the
              two SFENCE.VMA forms with rs2!=x0, so the
              address-only form (rs1!=x0, rs2=x0) invalidates
              global mappings for that address. All four forms are
              now stated explicitly rather than summarised, since
              summarising them is what produced the error.

              Not a prediction-quality issue. A global mapping
              surviving sfence.vma rs1, x0 is a stale translation
              the ITLB will hit on.

              mmu_decisions.md MMU-17 needed no separate fix: it
              says the L2 TLB uses "the same forms as the L1 TLBs",
              which is a pointer to this rule. A cross-reference
              was added there.

  2026-09-19  session-071. ITLB-3 includes the Svnapot 64 KiB case
              and points to MMU-U7 for how it is held; section 7
              records that Svinval's five instructions are MMU-U8;
              section 8 names both. Both extensions are mandatory
              and the document stated a complete set without them.
  2026-09-19  session-071, rulings. ITLB-3: NAPOT held once with a
              masked match and PPN[3:0] substituted. ITLB-3a: the
              entry holds the page's PBMT. ITLB-12: the effective
              attributes gate the request. ITLB-13b: Svinval as
              its fence equivalents.
```
