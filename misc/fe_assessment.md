<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Front-End Readiness Assessment
```
 FILE:    fe_assessment.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-10-14
 CONTACT: Jeff Nye
```

Question assessed: is the pacino front-end design ready for
- a) performance analysis
- b) physical design analysis
- c) formal and mutation testing
- d) parallel development of a cycle accurate performance model
- e) detailed design specifications

The assessment judges the design: its functional completeness, the
stability of its decisions, and how completely it is defined. It does not
judge whether the tooling for each phase exists; building that tooling is
part of each phase.

Baseline: commit 81d34d2, "FRONT-END PRINCIPAL DESIGN COMPLETE". BP-136
recorded regress.sh at 272 targets PASS. The regression was not re-run for
this assessment.

---
## 1. Summary

Agree on a) through d). Partly agree on e).

| Phase                    | Agree   | Basis                                   |
|--------------------------|---------|-----------------------------------------|
| a) Performance analysis  | Yes     | Functionally complete; open items are   |
|                          |         | performance questions                   |
| b) PD analysis           | Yes, as | Structurally complete; results are      |
|                          | analysis| provisional until TD#179 is ruled       |
| c) Formal / mutation     | Yes     | Control logic stable; interface rules   |
|                          |         | written as numbered rules               |
| d) Cycle accurate model  | Yes     | Parameters and timing documented and    |
|                          |         | consistent with the RTL                 |
| e) Detailed design specs | Partly  | Yes for FTQ, IFU, IBUF, decode, L1I,    |
|                          |         | ITLB; no for the FTB entry branch       |
|                          |         | fields, slot count and training point   |

The questions that remain open in the front end are deferred by ruling to
TD#179, to be decided by measurement against compiled benchmarks.

---
## 2. TD#179 -- the open front-end decisions

Source: planning/PROJECT_STATUS.md:5500-5524. The axis of measurement is
NUM_PRED_SLOTS = 1 or 2. Figures are from BP-131 (two slots / one slot).

1. FTB entry branch fields. Today: 2 conditional fields plus 1 jump field.
   Alternative: NUM_PRED_SLOTS fields with the last field shared between
   conditional and jump (XiangShan). Bundled with the fetch-block split of
   ftb_decisions.md section 3, which was never built. Blocks with more
   branches than slots: 9 / 243.
2. FTB region sharing (TD#168). 73 of 260 entries used by more than one
   block start; 92% of block-end changes made by a different start than
   the last writer; 608 jump updates replaced a different jump.
3. uBTB fill writes one branch into both conditional fields: 82 times at
   two slots.
4. The BP-119 rule that places a resolved branch in a prediction slot: 27
   (two slots) / 312 (one slot) trainings used another branch's slot
   metadata; 31 displacements with a slot free at two slots.
5. Predictor training at resolve or at commit (XiangShan: commit).

---
## 3. a) Performance analysis -- agree

Every structure is in place: uBTB, FTB, TAGE, SC, ITTAGE, RAS, loop
predictor, the 2-slot prediction path, the 64-entry FTQ, the 8-wide IBUF
read and decode, the L1I and the ITLB.

The open items are those that measurement decides:
- TD#179 items 1-5 (section 2)
- TD#183 TAGE/SC tuning
- TD#184 RAS recursion counts lost on wrong paths
- TD#80, 85, 86, 93, 98, 128, 133 (FTB, SC, history, two blocks per
  cycle)

Documented design behaviors that will appear in the measurements. These
are recorded choices, not defects:
- Instruction prefetch is not built; the request is driven 0 (IFU-U6).
- L1I fills serialize at L2 (TD#118).
- One slot's ready stalls both slots (TD#150).
- The p3 RAS repair leaves the pre-repair snapshot in the FTQ entry
  (TD#149).
- The confidence field has no consumer and is driven 0 (FE-U3).

---
## 4. b) Physical design analysis -- agree, as analysis

The design is structurally complete:
- one clock, clk
- no latches, no generated or gated clocks
- fe_top has no testbench-only ports

The analysis will raise decisions the design has not yet made.

Memories:
- FTB (ftb_array.sv:86), uBTB and the loop predictor are flop arrays with
  combinational read. The uBTB and loop predictor also reset the whole
  array (ubtb.sv:515-518, loop_pred.sv:445-448).
- The FTB array is 512 sets x 452 bits, about 230 Kbit.
- No SRAM macro mapping is decided for any of them.
- TAGE, ITTAGE and SC already go through bw_ram (rtl/lib/rtl/bw_ram.sv),
  a 1RW substitution point with bit write enables.

Per-slot table copies:
- Every TAGE, ITTAGE and SC table is instantiated once per prediction
  slot (e.g. tage_table.sv:203).
- Two copies versus one 2-read macro depends on the TD#179 slot count.

Single-cycle paths to examine:
- ITLB: a 64-entry fully associative compare with a serial first-hit
  chain, then PMP/PMA, in one cycle (itlb.sv:397-440).
- IBUF compaction (ibuf.sv:126-135) feeding the combinational
  instr_decoder, which drives the unregistered fe_top outputs
  decode_bundle and vec_decode_bundle.
- FTB: a 512:1 read of 452 bits from a muxed address
  (ftb_cntrl.sv:581-582), then the 4-way tag compare, in p1.
- FTQ entry array: about 9 read and 6 write ports on 64 x 228 bits
  (ftq_entry.sv:206-334). Plus 64-entry age and squash scans in
  ftq_status.sv:139.

Simulation-only code in rtl/ to remove:
- fast_init_r (tage.sv:162-167) is assigned only in an initial block
  from a plusarg, and drives the sram_init bypass muxes.
- $value$plusargs initial blocks in eight predictor files (tage, ittage,
  sc, tage_table, tage_bim, ittage_table, sc_table, sc_brimli).
- $error inside always_ff in l1i_mshr.sv:513-602 and l1i_ctrl.sv:316-320.

Reset style is mixed: 29 always_ff blocks use async reset and 51 use sync
or no reset.

Area and timing results stay provisional until TD#179 is ruled:
- the slot count sets the number of table copies
- the FTB branch fields set the FTB entry width

---
## 5. c) Formal and mutation testing -- agree

The design supports this now:
- The control logic in the FTQ, IFU, IBUF, L1I MSHR and RAS is settled.
- The interface rules are written as numbered rules in
  planning/interfaces/*.md. These are the source of the formal
  constraints.
- 133 concurrent properties are already bound by module. All are safety
  properties: no liveness, no ## delays.
- Hand-written reversions have consistently failed: 91 in BP-123, 24 in
  BP-136. The tests detect real faults.

Small, self-contained first targets: ftq_ptr, ibuf, ftb_plru,
ftq_status, ftq_commit, ifu_predecode.

Design properties that affect the work:
- Most module sizes come from package constants, not module parameters.
  ftq_ptr, ras, ftb_plru and l1i_mshr have no module parameters, so
  shrinking for a proof means overriding the package.
- A fe_top-level proof depends on the backend-side assumptions A1-A7 in
  ftq_backend_interfaces.md:507-546, which no built logic produces yet.
  Unit-level proofs do not depend on them.
- The large predictor and cache arrays need abstraction: TAGE, ITTAGE,
  SC, FTB, uBTB, the L1I data and tag arrays, and ftq_entry/ftq_meta.
- instr_decoder (2100 lines, combinational) fits an equivalence check
  against a decoder model better than property checking.
- ifu_rvc_exp is already checked exhaustively in simulation: all 49152
  16-bit encodings against an LLVM oracle.

Changes from TD#179 invalidate properties on the FTB, uBTB, bp_cluster
and FTQ metadata.

---
## 6. d) Cycle accurate performance model -- agree

This is the strongest case of the five.

Pipeline timing is documented:
- prediction stages: fe_decisions.md:100-127 (uBTB and LP at p1; FTB,
  TAGE, ITTAGE and RAS at p2; SC at p3)
- redirect to translate: ftq_decisions.md:472-483 (p2/p3 1 cycle,
  predecode 2, backend 2)
- one p0 bubble per FTB update
- IFU stages F0-F3 plus WB: ifu_decisions.md:233-276
- L1I 2-cycle hit, one line per cycle: icache_decisions.md:247-268
- decode is combinational behind a registered IBUF output

Parameter spot-check, planning documents against the RTL. No mismatch:

| Parameter      | Value                                  |
|----------------|----------------------------------------|
| FTQ depth      | 64                                     |
| FTB            | 2048 entries, 4-way, 32-byte block     |
| uBTB           | 256 entries, 4-way                     |
| TAGE           | 5 tables x 2048, history 0/8/13/32/119 |
| SC             | 512x4 + 1024, history 0/4/16/64        |
| ITTAGE         | 256/256/512/512/512, hist 4/8/13/16/32 |
| RAS            | 16 speculative + 32 commit             |
| IBUF           | depth 64, read width 8                 |
| L1I            | 64 KiB, 8-way, 64-byte line, 128 sets  |
| NUM_PRED_SLOTS | 2 default, 1 or 2 allowed              |

Behavior the model must take from the RTL, because no document gives it:
- the loop predictor and the uBTB (no decisions document for either)
- the decode-to-rename handoff (no interface document; DCD-18 only)
- the arbitration parameters still 0 "TBD"
  (bp_defines_pkg.sv:148-156, 275-283)

L1I miss latency is not defined while TD#118 is open
(ibuf_decisions.md:154-155).

The model can measure TD#179 items 1-5 directly, including training at
resolve versus commit with wrong-path fetch.

---
## 7. e) Detailed design specifications -- partly agree

Ready to specify now:
- FTQ, IFU, IBUF, decoder, L1I and the ITLB interaction
- RAS mechanics
- the TAGE and ITTAGE allocation, counter, use and use_alt_on_na rule
  sets

Would be rewritten after TD#179 is ruled:
- the FTB entry format and its branch fields (item 1)
- the uBTB fill (item 3)
- slot placement of resolutions (item 4)
- the training point (item 5)
- the FTQ metadata fields that carry each slot's predictor state

Undecided or unwritten rules:
- FE-U4 (fe_decisions.md:1252, bp_history_decisions.md:684): whether
  path history feeds the hashes. All folds use global history today.
- FE-U5 (fe_decisions.md:1260): the RAS/ITTAGE update and correction
  rules were deferred and never written.
- FE-U6 (fe_decisions.md:1263): the SC-disable rule text is not placed.
- FE-U11 (fe_decisions.md:1310): signalling of a backend redirect PC with
  bits 63:41 set.
- FTB-2 (ftb_decisions.md): confidence override interaction with the
  TAGE update path, not yet analyzed.
- RAS-1 (ras_decisions.md:875): push timing only partly resolved.
- IFU-U6 (ifu_decisions.md:692): instruction prefetch.
- L1I-U7 (icache_decisions.md:835): where the L1I-22 reserve is
  declared.
- CSR-U1, CSR-U2 (csr_decisions.md:206-207): custom CSR names; ordering
  of CSR writes against fetch and the fences.

Document conflicts a spec would have to settle:
- uFTB prediction stage: bp_arb_spec.md:22,88-94 says p0;
  fe_decisions.md:121 says p1. bp_arb_spec defers to fe_decisions.
- dual_pred_en: fe_decisions.md:666-668 describes a runtime gate; FE-20
  in the same document says no module has it.
- HI6 / TD#102 reads OPEN at bp_history_decisions.md:700; the IT5 folds
  are built (PROJECT_STATUS.md:663).
- ia_context/planning/arch/fe_theory_of_operation.md is an older copy of
  fe_decisions.md.

---
## 8. Interaction between the phases

- a) and d) produce the measurements that decide TD#179.
- b) and c) can run alongside a) and d).
- A TD#179 ruling changes three things:
  - the FTB entry width
  - the number of per-slot TAGE, ITTAGE and SC table copies
  - the FTQ metadata width

  That invalidates the b) area and timing results, and the c) properties,
  for those modules.
- e) can start with the units in section 7 marked ready now. The FTB,
  uBTB, bp_cluster and FTQ metadata chapters wait for the TD#179 ruling.

---
## 9. Method and evidence

Read-only survey of rtl/core/frontend, planning/arch, planning/interfaces
and planning/PROJECT_STATUS.md. Four survey agents covered:
- physical design
- formal and mutation
- performance analysis
- specification and performance-model definition

Checked directly against source for this report:
- ftb_array.sv:86 combinational read
- tage.sv:162-167 fast_init_r
- the TD#179 text

Other file:line references are from the survey agents and were not
re-read individually.

Not used: versions/ (old files). misc/ treated as possibly stale.
