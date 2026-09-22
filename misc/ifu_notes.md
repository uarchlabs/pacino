<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# IFU RTL Readiness Notes, Revision 2
```
 FILE:    ifu_notes.md
 SOURCE:  previous ifu_notes.md (session-072, PA assessment), IA read of the
          IFU boundary documents and the front-end RTL, 2026-09-21
 STATUS:  DRAFT
 UPDATED: 2026-09-21
 CONTACT: Jeff Nye
```

Not a decision record. An assessment for the PA session that scopes
IFU RTL generation, the IFU unit test and front-end integration.
Nothing here issues a number or rules anything. Every item names the
document that owns it; that document decides.

---

## 1. What this is based on

Read COMPLETE for this revision:

```
  ifu_decisions.md          ifu_ibuf_interfaces.md
  ftq_ifu_interfaces.md     itlb_ifu_interfaces.md
  l1i_ifu_interfaces.md     icache_decisions.md
  ifu_notes.md              session_handoff-073.md
```

Read at cited sections: dcd_decisions.md (DCD-16, TD-DCD-1, DCD-U1),
ftb_decisions.md 4.6 (TD#125 O-1 to O-3), PROJECT_STATUS.md (the
ftq_ptr.sv row and the TD#125 row).

Carried from ifu_notes.md, read complete in session-072 by the PA:
dcd_decisions.md, ibuf_decisions.md, itlb_decisions.md,
mmu_decisions.md, loop_pred_interfaces.md, sram_init.md, and the
TAGE and ITTAGE interface, rule and entry-format documents.

RTL checked against the documents, by reading or grep:

```
  rtl/core/frontend/ftq/rtl/ftq_ifu.sv     port list, flush block
  rtl/core/frontend/ftq/rtl/ftq.sv         top-level IFU ports
  rtl/core/frontend/ftq/rtl/ftq_ptr.sv     xlate_ptr (absent)
  rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
  rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv  ftq_pd_info_t
  rtl/core/frontend/decode/rtl/decode_pkg.sv   predecode_pkt_t
  rtl/core/frontend/decode/rtl/rvc_expander.sv
  rtl/core/frontend/decode/rtl/instr_decoder.sv
  tools/cachegen/output/l1i/rtl/l1i.sv     emitted L1I ports
  import/l1i/rtl/l1i.sv, import/ifu/rtl/ifu.sv
```

NO TEST SUITE WAS RUN for this revision. Status of the BPU, FTQ and
decode suites is taken from PROJECT_STATUS.md, not from a run.

---

## 2. What exists

```
  BPU        rtl/core/frontend/bpu     built, 20 modules plus
                                       bp_defines_pkg and
                                       bp_structs_pkg
  FTQ        rtl/core/frontend/ftq     built, ftq_ifu.sv Complete
                                       (BP-107)
  Decode     rtl/core/frontend/decode  rvc_expander, predecode,
                                       instr_decoder built
  IFU        rtl/core/frontend/ifu     empty
  ibuf       rtl/core/frontend/ibuf    empty
  icache     rtl/core/frontend/icache  empty
  ITLB       rtl/mmu/itlb              empty (.gitkeep only)
  L1I        tools/cachegen/output/l1i/  emitted by cachegen
  FE top     not started (FE-16)
```

The emitted L1I at tools/cachegen/output/l1i/ matches the
documents: core_addr[35:0], core_id[3:0], core_rdata[511:0],
core_rid, core_rerr, core_prefetch, 16 outstanding, out-of-order
return by ID. Its package is l1i_pkg (L1iPaBits 36, L1iReqIdBits 4,
L1iMaxOutstanding 16).

import/l1i/ is an OLDER emission (32-bit pe_port, 32-bit address)
and must not be used. import/ifu/rtl/ifu.sv is a cgen protocol agent
marked NOT SYNTHESIZABLE, not an IFU.

---

## 3. Hard blockers

Each of these stops correct RTL, not just clean RTL. All four were
in ifu_notes.md; each is now confirmed in the RTL.

### 3.1 The package parameters the IFU ports need do not exist -- TD#122

bp_defines_pkg.sv line 21 is `VA_WIDTH = 40`. Every document uses
41 (fe_decisions.md FE-19).

itlb_ifu_interfaces.md sizes ports by GPA_WIDTH, VPN_WIDTH,
PPN_WIDTH, ASID_WIDTH, VMID_WIDTH, PERM_WIDTH, CAUSE_WIDTH and
PMA_WIDTH. None is in the packages; mmu_decisions.md MMU-23 says
TD#122 adds them. Five of these have no value yet.

NEW. l1i_ifu_interfaces.md sizes its ports by PA_WIDTH, REQ_ID_BITS
and L1I_LINE_BITS (sections 4.1, 5.1, 10.1, 11.2). It also uses
L1I_OFFSET_BITS and MAX_OUTSTANDING in rules IF-5 to IF-7, lists
L1I_LINE_BYTES in the 3.1 table, and section 11.2 defines
MAINT_FENCE_I = 0 and MAINT_CBO_INVAL = 1. None is in the packages.
Nothing ties l1i_pkg to bp_defines_pkg (TD-IF-1). The TD#122 row
names PA_WIDTH as "the same class" but does not carry it or the
other L1I names.

The IFU-to-ITLB and IFU-to-L1I port groups cannot elaborate until
these land. It is a PACKAGE CHANGE, so it runs into 3.2.

### 3.2 The package-change waiver (parked session-071)

CLAUDE.md's Packages constant forbids a task changing or removing an
existing declaration. TD#122, TD#124 and TD#125 all do: VA_WIDTH,
PFTADDR_BITS, the FTB entry width, and removing `carry`. The
existing waiver covers planning-document writes only.

Either a package-change waiver form or a rule edit is required
before any of the three is prompted. This is a Jeff decision and it
gates 3.1.

NEW. The DCD-16 redefinition of predecode_pkt_t is the same class of
change in decode_pkg.sv. See 5.1.

### 3.3 TD#127, the translation request group is not built

IFU-24 puts translation in a pipeline AHEAD of the fetch pipeline.
ftq_ifu_interfaces.md 4.1 drives the translation request from
xlate_ptr, and FQ-1 gates fetch on fetch_ptr <= xlate_ptr.

Confirmed: ftq_ptr.sv has no xlate_ptr, and neither ftq_ifu.sv nor
ftq.sv declares ftq_ifu_xlate_val, _rdy, _pc or _idx. The whole 4.1
group is absent on the FTQ side, not only the pointer. Without it
the IFU translation pipeline has no producer.

### 3.4 TD#126, flush index K vs K+1

ifu_ibuf_interfaces.md IB-13 and ftq_ifu_interfaces.md 7 W3 rule K
for a predecode, p2 or p3 redirect and for a backend redirect with
`_self` set, and K+1 for a backend redirect with `_self` clear.

Confirmed: ftq_ifu.sv line 238 drives `redir_idx + 1'b1` whenever
`_self` is clear, for every cause. The IFU consumes this flush. It
is a correctness difference, and one side has to give before the
IFU flush path is written.

---

## 4. FTQ-side items the IFU depends on

### 4.1 TD-IFU-4, commit pointer export is not built -- NEW here

ftq_ifu_interfaces.md 4 lists `ftq_ifu_commit_ptr` for IFU-22.
ftq_ifu.sv and ftq.sv have no such port. Only the uncached path of
IFU-21 to IFU-23 reads it. It can go in the same task as 3.3 and
3.4.

### 4.2 Port-name diff, ftq_ifu_interfaces.md against ftq_ifu.sv

ifu_notes.md asked for this diff before the IFU prompt. Done:

```
  section 4    req_val, req_rdy, start_pc, next_pc, idx,
               taken_val, taken_pos, gen             MATCH
               commit_ptr                            ABSENT, 4.1
  section 4.1  xlate_val, xlate_rdy, xlate_pc,
               xlate_idx                             ABSENT, 3.3
  section 5    flush_val, flush_idx                  MATCH
  section 6    all twelve ifu_ftq_* names            MATCH
```

One form difference. The document writes `ifu_ftq_pd` as
`ftq_pd_info_t [FTQ_PD_WIDTH-1:0]`, and so does the comment above
ftq_pd_info_t in bp_structs_pkg.sv. The port in ftq_ifu.sv and
ftq.sv is UNPACKED, `ftq_pd_info_t ifu_ftq_pd [0:FTQ_PD_WIDTH-1]`.
The IFU side must match the RTL form. The document or the comment
should say which is meant.

---

## 5. Decode-side items

### 5.1 The predecode_pkt_t redefinition breaks decode -- NEW

DCD-16 redefines predecode_pkt_t with the start PC, position, FTQ
index, three fault fields and the DCD-7 classification, and drops
`vtype_hazard` (TD-DCD-1). The built struct also carries
`may_be_branch`, which DCD-16 does not list.

The built struct is used by instr_decoder.sv (its input port and its
predecode_out output, which exist to pass vtype_hazard to rename),
predecode.sv, tb_instr_decoder.sv and tb_predecode.sv. Removing
fields breaks all four. The edit has to be sequenced with decode
rework, or the new struct given its own name while the old one is
retired separately. TD-IFU-1 records that this edit "remains to be
made"; it does not record the decode breakage.

### 5.2 The built rvc_expander.sv does not fit IFU-4 -- NEW

rvc_expander.sv takes an 8-slot bundle and a start mask. IFU-4
expands each of the 17 halfword positions of IFU-8 independently,
with no start mask. The existing module is not reusable as it is.

THE RVC EXPANDER HAS NO DESIGN DOCUMENT BY INTENT. dcd_decisions.md
section 1 sends the IA to the compressed-instruction chapter of the
unprivileged specification. IFU-1 places it in the IFU and IFU-4
runs it before predecode. The prompt must not ask for a
specification that was deliberately not written.

### 5.3 DCD-U1, where vtype_hazard is computed

TD-DCD-1 rules out the predecoder and does not choose between the
ibuf read port and decode. DEFERRABLE for the IFU task: IB-9 already
keeps the field off the IFU-to-ibuf port. It blocks decode, not the
IFU.

---

## 6. Structural gaps in the IFU specification

Each item changes IFU state or ports, not only a size. ifu_notes.md
listed IFU-U5 and TD-IFU-7 as probable blockers. The complete read
adds the rest.

### 6.1 One prediction block per cycle or two -- NEW

ftq_ifu_interfaces.md 8 item 2 leaves it open and says it "is
decided with the IFU design". One 32-byte block per cycle delivers
at most 8 full-width instructions, and fewer after a taken branch
truncates the block. CLAUDE.md requires the front end to sustain 8
instructions per cycle under ideal conditions. Two blocks per cycle
needs two FTQ requests and two writebacks per cycle and reopens
ftq_ifu_interfaces.md sections 4 and 6. This has to be ruled before
the IFU ports are fixed.

### 6.2 TD-IFU-9 / TD-IF-5, the reorder buffer

The L1I returns responses out of order (l1i_ifu_interfaces.md IF-12,
icache_decisions.md 4.3 R2). The IFU
writes back to the FTQ once per prediction block. Nothing bounds the
buffer that holds a block whose line returned early, and IFU-10 does
not say where it sits.

### 6.3 TD-IFU-7 / L1I-U5, the line buffer

Depth and redirect behaviour are unruled. IF-7 has the IFU reserve a
line-buffer slot when it allocates a request ID. Neither document
gives a depth. Reading IF-7 against the 16 IDs of IF-6, the range is
1 to 16; that range is this note's inference, not a stated rule.
IFU-23's uncached path also depends on it.
icache_decisions.md L1I-U5 names ifu_decisions.md TD-IFU-7 as the
owner.

### 6.4 Wrong-path requests after a redirect -- NEW

The L1I request port has no cancel. An ID is freed only when its
response arrives. How the IFU marks in-flight requests at or after
the flush index and drops their data is not written down. IFU-20
says what must be dropped, not how an ID that is still in flight is
handled.

IF-7 also lets one ID serve "FTQ index or indices". How one response
is mapped to more than one prediction block is not defined.

### 6.5 TD-IFU-8, the issue policy

Whether the IFU issues for a later block before an earlier response
lands is not stated. It decides what merges in the L1I MSHR and may
change the L1I-13 value of 4 targets. Policy and sizing, not ports.

### 6.6 Translation queue entry for a page-crossing block -- NEW

IFU-25 gives the queue entry one physical address, one PMA result,
one cause and status, and one GPA. IT-1 and IT-2 allow two
translations per block when the block crosses a page, and the second
can hit, miss or fault on its own (ifu_decisions.md 4). Either the
entry holds two of each, or IFU-25 needs a sentence saying where the
second result goes.

### 6.7 IFU-U5, translation queue depth

Unruled. It sets how far ahead of the fetch pipeline translation
runs, so it is structural rather than a tuning value. Named in
itlb_ifu_interfaces.md 8 as bearing on that port without changing
it.

NEW. IT-14 has the IFU hold "a slot for each of the two outstanding
requests IT-1 permits", and the tag of IT-2 is one bit naming the
half of one block. Read together, only one block can be at the ITLB
at a time and translation is in order. If that is intended it should
be stated, because it bounds what IFU-U5 can buy on an ITLB miss.

### 6.8 Uncached fetch -- IFU-U4

The uncached bus width is unruled (ifu_decisions.md 7), and the
uncached source of IFU-21 has no interface document. A split 32-bit
instruction on a narrow bus needs its own ITLB lookup and PMP check
for the second part. The first IFU task can either include this or
stub it under a TD number.

### 6.9 TD-IFU-10, fence.i and cbo.inval -- NEW detail

The producer on the commit side of l1i_ifu_interfaces.md 11 is
unspecified, and the section 12 assumptions A1 to A5 about the
commit stage cannot be checked because no backend commit document
exists.

The emitted L1I has NO invalidate port (TD-IF-4, TD#119, E7), so the
IFU side of l1i_ifu_interfaces.md 10 and 11 can be written but has
nothing to connect to. RVA23 COMPLIANCE GAP: Zifencei and Zicbom are
mandatory and have no hardware path yet. The maintenance state
machine linking cmt_ifu_maint to inv to the buffer clear to the ack
(IF-35, IF-36) is given as rules, not as a sequence, and whether
fetch stops accepting from the FTQ while an invalidate is in flight
is not stated.

### 6.10 Also unspecified on the L1I side of the IFU -- NEW

- Prefetch: what to prefetch and when (L1I-19, section 8.1, P1 and
  P3). Only the core_prefetch bit is defined.
- How an L1I rsp_err access fault and an ITLB fault combine onto
  ifu_ftq_fault_pos and the per-slot cause (l1i_ifu 8).
- TD#118, open. Sixteen fills can be in flight at the L1I boundary,
  but l2_up_i_slv holds one transaction, so misses serialise at the
  l2. PROJECT_STATUS: "The miss throughput the IFU would be built
  against is the l2 number, not the l1i number." ifu_decisions.md 10
  records that the IFU outstanding-request depth has no real target
  until this is settled, and that this is not yet a decision.

---

## 7. Document conflicts found -- NEW

- cbo.inval. icache_decisions.md 7 M2 and TD-L1I-2 say what drives
  it is undecided. l1i_ifu_interfaces.md IF-41 and 13.3 say it was
  ruled routed in session-068, and IF-U3 is closed on it.
  icache_decisions.md was not updated.
- TD-IF-1. l1i_ifu_interfaces.md 3.1 treats it as open and carrying
  PA_WIDTH and the rest. Section 17 says it was reopened as TD#122.
  The TD#122 row covers VA_WIDTH, GPA_WIDTH and the seven other ITLB
  widths, and not PA_WIDTH or the L1I parameters. So the L1I
  parameters have no TD that carries them.
- ifu_decisions.md TD-IFU-9 cites "IF-R2". No such ID exists. The
  rule is icache_decisions.md 4.3 R2, which l1i_ifu_interfaces.md
  IF-12 cites.
- Port prefix rule. l1i_ifu_interfaces.md 2 says the prefix names
  the driver. ifu_l1i_req_rdy and ifu_l1i_inv_rdy are driven by the
  L1I, and cmt_ifu_maint_rdy by the IFU.
- l1i_ifu_interfaces.md says every port in it is NEW, and two lines
  later says the emitted core port already exists.
- ftq_pd_info_t array form, 4.2 above.

---

## 8. Reassessed from ifu_notes.md

### 8.1 TD#125 O-1, O-2, O-3 are not IFU blockers

ifu_notes.md 3.4 listed them as probable blockers. O-1 (target
base), O-2 (fall-through upper bound) and O-3 (slot mapping and fill
order) are the boundary conditions of how the FTB and uBTB STORE
positions, ftb_decisions.md 4.6. Every port position the IFU sees is
measured from the block start and no port carries the stored form
(ftq_ifu_interfaces.md 3). They affect prediction accuracy, and so
how often M2 and M3 fire, not IFU correctness. They do not gate the
IFU prompt. They still gate the TD#125 RTL change.

---

## 9. Needed for an IFU unit test

- ITLB. It does not exist and cachegen cannot emit one
  (itlb_decisions.md: "The ITLB is written from this document.
  cachegen currently does not support TLB generation"). A
  behavioural model behind itlb_ifu_interfaces.md is required:
  hit, miss with re-request, the three causes, GPA on cause 20,
  PMA, and out-of-order tags (IT-3).
- L1I. The cachegen L1I is a smoke-test partner only. A hand-written
  responder is needed to force out-of-order return, merged duplicate
  responses, rsp_err, the IF-39 and IF-40 ready behaviour, and the
  invalidate drain, which the emitted L1I cannot do (no invalidate
  port).
- ibuf. A model with the IB-6 all-16-free ready rule.
- FTQ. The built ftq.sv, after 3.3, 3.4 and 4.1.
- Neither L1I document says an IFU test needs an L1I model, and none
  specifies one. The testbench document should.

---

## 10. Settled, no work needed

Carried from ifu_notes.md and consistent in the complete read.

- THE THREE-CAUSE FAULT SET is consistent across itlb_decisions.md
  ITLB-11, itlb_ifu_interfaces.md IT-6, ifu_decisions.md IFU-2a,
  dcd_decisions.md DCD-15 and ifu_ibuf_interfaces.md IB-9a: cause 1
  access fault, cause 12 page fault, cause 20 guest-page fault. The
  IFU pairs cause and VA (IT-5); the GPA arrives on IT-6a. The IA
  must not collapse them.
- IB-1 fixed-width 16-slot port, IB-6 all-16-free ready rule, and
  IBUF-8, 8a and 8b clear sources are settled and consistent.
- L1I boundary, checked and consistent: 64-byte line and 512-bit
  response, 16 outstanding, out-of-order response by ID, one
  response per cycle, drain then clear (IF-31, IF-42 with icache M1).
- The IFU does not redirect (IFU-13). The FTQ derives the redirect
  from the writeback.
- TD#128, opened 2026-09-21 after ifu_notes.md was written: history
  geometry sizing (GHR_WIDTH, PHR_WIDTH, fold depths, PHR bit
  selection) is deferred until the IFU is complete and can drive a
  performance harness. It waits on the IFU and does not block it.
  Next free TD is TD#129, not the TD#128 in handoff-073.

---

## 11. Suggested order

```
  1  waiver decision (3.2)       gates everything below that
                                 touches a package
  2  TD#122 + DCD-16 edit        packages, with the decode rework
                                 of 5.1; runs bpu, ftq and decode
  3  6.1 one or two blocks       fixes the FTQ-IFU port count
  4  TD#126, TD#127, TD-IFU-4    one FTQ task: flush index,
                                 xlate_ptr and group, commit_ptr
  5  6.2 to 6.7                  reorder buffer, line buffer,
                                 wrong-path IDs, issue policy,
                                 page-crossing queue entry, IFU-U5
  6  6.8, 6.9 scope              uncached and fence.i in the first
                                 IFU task, or stubbed under a TD
  7  test models (9)             ITLB, L1I responder, ibuf
  8  IFU prompt
```

The "complete read of the three IFU boundary documents" that
ifu_notes.md placed before the prompt is done by this revision.

---

## 12. Session-072 document state

Carried from ifu_notes.md and handoff-073. 47 planning files differ
from the session-071 tree. Most changes are annotations, but three
are structural and move line numbers: ftb_interfaces.md section 5
now points at ftb_decisions.md 8 instead of carrying parameter
values; ftq_bpu_interfaces.md has 4a before 4b; ten Document History
sections were sorted into date order. Anything citing those files by
line number is stale. The first two were checked against the current
files and hold; the history sort was not re-checked.

Since then, commit ad00766 (2026-09-21) changed PROJECT_STATUS.md
(TD#128 added) and bp_history_decisions.md. Neither touches the IFU
boundary documents. The planning tree has no uncommitted changes.
check_planning.sh is not in the tree, so the checksums were not
re-run.

---

## 13. Document History

```
  2026-09-21  Created from ifu_notes.md (session-072) and an IA
              complete read of the IFU boundary documents. All four
              hard blockers confirmed in RTL. Added TD-IFU-4,
              the port-name diff, the decode breakage of DCD-16,
              the rvc_expander fit, sections 6.1, 6.4, 6.6, 6.9
              and 6.10, the document conflicts of section 7, and
              the test-model list. TD#125 O-1 to O-3 reassessed as
              not gating the IFU prompt.

  2026-09-21  Checked against the current planning tree. Section 2:
              BPU is 20 modules plus two packages; rtl/mmu/itlb
              exists and is empty. 3.1: which L1I names size ports,
              and that TD#122 does not carry them. 6.2: IF-R2 is
              icache_decisions.md 4.3 R2. 6.3: the 1 to 16 range
              marked as inference. 6.10: TD#118 restated from its
              current row. Section 7: TD-IF-1 scope corrected, the
              IF-R2 citation added. Section 10: TD#128. Section 12:
              what was re-checked.
```
