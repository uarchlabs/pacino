<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# IFU RTL Readiness Notes
```
 FILE:    ifu_notes.md
 SOURCE:  session-072, PA assessment
 STATUS:  DRAFT
 UPDATED: 2026-09-20
 CONTACT: Jeff Nye
```

Not a decision record. A PA assessment written at the end of the
session-072 planning-document audit, for the session that scopes IFU
RTL generation, the IFU unit test, and front-end integration. Nothing
here issues a number or rules anything. Every item names the document
that owns it; that document decides.

---

## 1. What this is based on

Read COMPLETE during session-072: ifu_ibuf_interfaces.md,
itlb_ifu_interfaces.md, dcd_decisions.md, ibuf_decisions.md,
itlb_decisions.md, mmu_decisions.md, loop_pred_interfaces.md,
sram_init.md, tage_interfaces.md, tage_table_interfaces.md,
ittage_interfaces.md, ittage_table_interfaces.md, and the TAGE and
ITTAGE rule and entry-format documents.

Read only AT CITED SECTIONS: ifu_decisions.md, l1i_ifu_interfaces.md,
ftq_ifu_interfaces.md, ftq_decisions.md, ftb_decisions.md,
fe_decisions.md, PROJECT_STATUS.md, icache_decisions.md and the rest
of the tree.

SO: the IFU-internal gaps below are UNDER-SAMPLED. The three IFU
boundary documents were never read end to end. A complete read of
ifu_decisions.md, l1i_ifu_interfaces.md and ftq_ifu_interfaces.md
should precede the IFU prompt and may add items to section 2.

---

## 2. Hard blockers

Each of these stops correct RTL, not just clean RTL.

### 2.1 The package parameters the IFU ports need do not exist

`itlb_ifu_interfaces.md` declares ports sized by GPA_WIDTH,
VPN_WIDTH, PPN_WIDTH, ASID_WIDTH, VMID_WIDTH, PERM_WIDTH,
CAUSE_WIDTH and PMA_WIDTH. None is defined in the packages;
`mmu_decisions.md` MMU-23 says TD#122 adds them. VA_WIDTH is 41 in
every document and 40 in the package.

The IFU-to-ITLB port group cannot elaborate until this lands. It is
the first thing to do and it is a PACKAGE CHANGE, so it runs into
2.2 below.

### 2.2 The package-change waiver (parked session-071)

CLAUDE.md's Packages constant forbids a task changing or removing an
existing declaration. TD#122, TD#124 and TD#125 all do: VA_WIDTH,
PFTADDR_BITS, the FTB entry width, and removing `carry`. The
existing waiver covers planning-document writes only.

Either a package-change waiver form or a rule edit is required
before any of the three is prompted. This is a Jeff decision and it
gates 2.1.

### 2.3 TD#127, xlate_ptr specified but not built

IFU-24 puts translation in a pipeline AHEAD of the fetch pipeline.
`ftq_ifu_interfaces.md` 4.1 gates the translation request group on
FQ-1, fetch_ptr <= xlate_ptr. If xlate_ptr is not in ftq_ptr.sv, the
translation port has no producer and the IFU's two-pipeline
structure has nothing to sequence against.

### 2.4 TD#126, flush index K vs K+1

`ifu_ibuf_interfaces.md` IB-13 rules K for a predecode, p2 or p3
redirect and for a backend redirect with `_self` set, K+1 for a
backend redirect with `_self` clear. The built FTQ flushes K+1 for a
surviving entry on every cause. The IFU consumes this flush. It is a
correctness difference, not a preference, and one side has to give
before the IFU flush path is written.

---

## 3. Probable blockers, depending on scope

### 3.1 IFU-U5, translation queue depth

Unruled. It sets how far ahead of the fetch pipeline translation
runs, so it is structural rather than a tuning knob. Named in
`itlb_ifu_interfaces.md` section 8 as bearing on that port without
changing it.

### 3.2 TD-IFU-7 / L1I-U5, line buffer depth and redirect behaviour

Unruled, and IFU-23's uncached path depends on it.
`icache_decisions.md` L1I-U5 names ifu_decisions.md TD-IFU-7 as the
owner.

### 3.3 DCD-U1, where vtype_hazard is computed

TD-DCD-1 rules out the predecoder and does not choose between the
ibuf read port and decode. DEFERRABLE for the IFU task: IB-9 already
keeps the field off the IFU-to-ibuf port. It blocks decode, not the
IFU.

### 3.4 TD#125 open items O-1, O-2, O-3

Positions are stored region-relative and presented start-relative,
converted inside the FTB and the uBTB (ftb_decisions.md 4.6). The
IFU converts at predecode and at the FTQ writeback. O-1 to O-3 are
the boundary conditions of that conversion and are unruled.

---

## 4. Not blockers, but worth knowing before the prompt

- THE RVC EXPANDER HAS NO DESIGN DOCUMENT BY INTENT. dcd_decisions.md
  section 1 sends the IA to the compressed-instruction chapter of the
  unprivileged specification. IFU-1 places it in the IFU, IFU-4 runs
  it before predecode. Do not let the prompt ask for a specification
  that was deliberately not written.

- THE ITLB DOES NOT EXIST and cachegen cannot emit one
  (itlb_decisions.md: "The ITLB is written from this document.
  cachegen currently does not support TLB generation"). An IFU unit
  test needs a behavioural model behind itlb_ifu_interfaces.md.

- ftq_ifu.sv IS BUILT (BP-107, Complete). The IFU side must match its
  port list exactly. Diff the document's names against that port list
  BEFORE writing the prompt, not after. Session-072 corrected the
  scope note in ftq_ifu_interfaces.md that claimed neither side
  existed; the FTQ half is real and is the reference.

- The three-cause fault set is settled and consistent across
  itlb_decisions.md ITLB-11, itlb_ifu_interfaces.md IT-6,
  ifu_decisions.md IFU-2a, dcd_decisions.md DCD-15 and
  ifu_ibuf_interfaces.md IB-9a: cause 1 access fault, cause 12 page
  fault, cause 20 guest-page fault. The IFU pairs cause and VA; the
  GPA arrives on IT-6a. No work needed, but the IA should not
  collapse them.

- IB-1 fixed-width 16-slot port, IB-6 all-16-free ready rule, and
  IBUF-8/8a/8b clear sources are settled and internally consistent.

---

## 5. Suggested order

```
  1  TD#122 package edit        unblocks elaboration (2.1), needs
                                the waiver decision (2.2)
  2  TD#126                     flush index, one side gives
  3  TD#127                     xlate_ptr built
  4  TD#125 O-1, O-2, O-3       position conversion boundaries
  5  IFU-U5, TD-IFU-7           queue and buffer depths
  6  complete read of the three IFU boundary documents, then the
     IFU prompt
```

---

## 6. Session-072 document state

47 planning files differ from the session-071 tree. Most changes are
annotations, but three are structural and will move line numbers:
ftb_interfaces.md section 5 now points at ftb_decisions.md 8 instead
of carrying parameter values; ftq_bpu_interfaces.md has 4a before 4b;
ten Document History sections were sorted into date order. Anything
citing those files by line number is stale.
