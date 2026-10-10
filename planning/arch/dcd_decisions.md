<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Decode Implementation Decisions
```
 FILE:    dcd_decisions.md
 SOURCE:  session-069
 STATUS:  DRAFT
 UPDATED: 2026-10-09
 CONTACT: Jeff Nye
```

Owns the DCD-N, TD-DCD-N and DCD-UN registries.

---

## 1. Scope and reference

The RISC-V unprivileged specification is the reference for every
instruction encoding, immediate format and register field named
here. This document does not restate them. It contains only what
the specification does not decide.

`instr_decoder.sv`'s instruction ENCODINGS are not in scope: they
are the specification's. What the specification does not decide IS
in scope: the boundary of section 10a, and since session-077 the
representation decode hands rename, and which encodings decode
treats as illegal, section 10b. This read "instr_decoder.sv is not
in scope for its instruction decode. It is Complete", which left
the representation undecided; BP-123 found the decoder rejecting
mandatory instructions and mapping others onto placeholders.

The RVC expander is not in scope either. Its encodings are the
compressed-instruction chapter of the specification, and the
project's decisions about it are placement and ordering, which
belong with the stage that holds it: `ifu_decisions.md` IFU-1 puts
it in the IFU ahead of the ibuf, and IFU-4 runs it before
predecode.

The predecoder replaces `predecode.sv`. Its bundle view is a NEW
struct, `ifu_pd_pkt_t`, not a redefinition of `predecode_pkt_t`
(Jeff, session-074). The old struct stays for the built decode
until decode moves to the new one, TD#143. Neither the existing
module nor the existing struct constrains anything below.

---

## 2. One predecoder, two views

DCD-1  There is one predecoder. It produces two views of one
       classification.

       The block view is `ftq_pd_info_t` at each of the 16
       halfword positions of the prediction block. It goes to the FTQ
       writeback and its shape is fixed by `ftq_ifu.sv`.

       The bundle view is `ifu_pd_pkt_t`, one per instruction
       slot. It goes through the ibuf to `instr_decoder`.

The two differ in width because their consumers do. The FTQ needs
an answer at every position in the block, including positions that
are not instruction starts. Decode needs `SLOTS` of 8. The
classification is computed once.

THE ARRAY WIDTH BELONGS TO THE PORT, NOT TO THE TYPE.
`ifu_pd_pkt_t` is a per-slot struct and both ibuf ports carry an
array of it: 16 wide on the write port, because the IFU does not
compact (ifu_ibuf_interfaces.md IB-1, IFU-5, IBUF-3), and 8 wide on
the read port into decode, where instr_decoder is `[SLOTS-1:0]`
(IBUF-9). The ibuf is the width converter. This read "at each of
the 8 decode slots", which attaches decode's width to the type and
puts it against the four documents that carry 16 on the write port.
Session-072.

DCD-2  Position 16, the 17th halfword of IFU-8, has no entry in
       either view. It can only be the tail of a straddling
       instruction, never a start.

---

## 3. Inputs

DCD-3  The predecoder takes both the raw halfwords and the
       expanded buffer.

IFU-4 expands before predecode, and expansion runs at every
halfword position independently, so a position that is not an
instruction start still produces an expanded value. That value is
meaningless. The raw halfwords are what determine which positions
are starts, so both are needed.

---

## 4. Instruction starts

DCD-4  A position is an instruction start if it is reached by the
       walk from the block start PC. At each start, the low two
       bits of that position's halfword give the length: not
       `2'b11` is a 16-bit instruction and the next start is one
       position later, `2'b11` is a 32-bit instruction and the
       next start is two positions later.

DCD-5  The walk begins at the block start PC supplied by the FTQ,
       which is position 0: positions count from the block start
       (ftq_ifu_interfaces.md 3) and the block is unaligned, IFU-6.
       When the block starts on the tail of a 32-bit instruction
       that began at position 15 of the previous block, the walk
       begins at position 1 (IFU-11).

       Session-074. This read "not at position 0", from before
       positions were counted from the block start, and did not
       cover a block that starts on a tail.

DCD-6  The start mask is a parallel prefix over the per-position
       lengths, not a sequential walk. Each position independently
       yields the length of an instruction starting there, and the
       mask is a scan over those lengths.

DCD-6 is stated because the obvious implementation is a loop and
the obvious loop does not close timing over 16 positions.

---

## 5. Control flow classification

DCD-7  Per position the predecoder emits a 2-bit type: `2'b00`
       not a control flow instruction, `2'b01` conditional
       branch, `2'b10` JAL, `2'b11` JALR. Plus `is_call` and
       `is_ret`.

The classification runs on the expanded encodings, so only the
base-ISA opcodes are recognised. The compressed forms have already
become their 32-bit equivalents and are not separately decoded.
That is the reason for IFU-4.

DCD-8  The classification is exact, not a hint. It distinguishes
       the three control flow classes and resolves call and
       return. There is no conservative case and nothing is
       deferred to decode.

---

## 6. Targets

DCD-9  The predecoder computes a target for conditional branches
       and for JAL, as the position's PC plus the sign-extended
       immediate of the relevant format.

DCD-10 No target is computed for JALR. The target depends on a
       register value the front end does not have. The target
       field carries no meaning for a JALR position and the FTQ
       does not read it, IFU-17.

---

## 7. Call and return

The specification's return-address-stack hints are the reference
for which JAL and JALR forms push, pop, or both. `x1` and `x5` are
the link registers and the behaviour is a function of `rd` and
`rs1`.

DCD-11 `is_call` and `is_ret` are independent bits, not a single
       encoded class. The specification has one case that both
       pops and pushes, a JALR whose `rd` and `rs1` are both link
       registers and are not equal. Both bits are set for it.

DCD-11a Downstream, that pair maps to `bp_br_type_e.RETURN_CALL`,
        added session-069 (`ras_decisions.md` 2). The predecoder
        emits the two bits; the enum is formed from them where a
        single classification is required, as on
        `ras_br_type_p2`.

TD-DCD-2  CLOSED by BP-119. It asked whether the RAS, built
          before DCD-11, accepts both bits set on one instruction
          and in which order. It did not: ras.sv treated 3'b111 as
          a no-op at p2, in the p3 repair and at commit, and
          nothing upstream presented 3'b111 anyway (the cluster
          and the uBTB presented RETURN, so the stack was one
          short after each switch). BP-119 built RAS-DS1: pop,
          then push, at p2, p3 and commit.

---

## 8. Validity and range

DCD-12 A position's `valid` is set when it is an instruction
       start under DCD-4 and it lies within the fetched range.

DCD-13 `pd_range` marks the positions actually fetched. The
       range ends at the predicted taken position when the FTQ
       supplied one, and at the block end otherwise, and is cut
       short at a fault (ftq_ifu_interfaces.md 6). The block end
       is `ftq_ifu_next_pc`, the fall-through: the not-taken range
       is the positions whose address is below it, all sixteen
       when it is not within 32 bytes above the start. Session-074,
       as BP-116 built it.

DCD-14 The predecoder does not test the prediction. It reports
       what it found. The comparison against the prediction, and
       `cfi_val`, `cfi_pos`, `mis_val`, `mis_pos`, are the IFU's,
       IFU-15.

---

## 9. Faults

DCD-15 A faulting position is reported with `fault_val` and
       `fault_pos` in the block view, and with the cause, the
       faulting virtual address, and on a guest page fault the
       faulting guest physical address and its implicit-access
       kind, in the bundle view. The kind was added session-077
       (mmu_decisions.md MMU-29).

The cause field carries three causes, not two, plus none:
instruction access fault, instruction page fault and instruction
guest-page fault. H is mandatory in RVA23 through Sha.
`mmu_decisions.md` MMU-16.

The two carry different things on purpose. The FTQ needs only to
know the block ended early. The architectural exception travels
with the instruction to the backend. This is IFU-2 and the note
under IFU-20.

---

## 10. The bundle view

DCD-16 `ifu_pd_pkt_t` carries, per slot: valid, the expanded
       32-bit instruction, the start PC, the position within the
       prediction block, the FTQ index, the fault cause, the faulting
       virtual address, the faulting guest physical address, the
       implicit-access kind of that guest physical address,
       `is_rvc`, and the control flow classification of DCD-7.
       `is_vsetvl` and `needs_vtype` are REMOVED from it (TD#148):
       decode computes its own (DCD-17) and nothing read the IFU's.
       RULED session-077 (Jeff), after BP-124; REMOVED by BP-125,
       ifu_pd_pkt_t 192 -> 190 bits (T78 checks the width). The two
       paragraphs below record why they were carried.

       THE FAULTING GPA IS FAULT_GPA_WIDTH = 56 BITS, the widest
       guest physical address a walk can form (a 44-bit VS-stage
       PPN plus the page offset), so every faulting GPA is carried
       whole and none is replaced by a sentinel
       (mmu_decisions.md MMU-23, MMU-30 withdrawn). Ruled
       session-077 (Jeff); a package change, built by BP-124. For
       kind 00 the IFU fills the page offset from the faulting
       halfword's virtual address (ifu_decisions.md IFU-2a).

       THE IMPLICIT-ACCESS KIND is two bits, valid on a guest page
       fault: 2'b00 the fetch's own guest physical address, 2'b01
       an implicit read of a VS-stage page table, 2'b10 an
       implicit write of one, 2'b11 reserved
       (itlb_ifu_interfaces.md IT-6c). The backend needs it to
       write htinst (mmu_decisions.md MMU-29). Added session-077
       (Jeff); a package change, BUILT by BP-123 as
       `logic [1:0] fault_gpa_imp`.

       `is_vsetvl` and `needs_vtype` are per-instruction and belong
       here by TD-DCD-1; the enumeration did not carry them while
       ifu_ibuf_interfaces.md 4 listed them as coming from this
       rule. `vtype_hazard` is NOT here, TD-DCD-1. Session-072.

       `needs_vtype` is set for every OP-V instruction other than
       the vsetvl configuration forms, and for every vector load
       and store. It over-marks the whole-register forms, which is
       safe for rename. Session-074, as BP-116 built it; recheck
       against decode when decode moves to ifu_pd_pkt_t, TD#143.

DCD-16a A SLOT THAT FAULTED AT FETCH carries only `valid`, the
        start PC, the FTQ index, the position and the fault fields
        (cause, faulting VA, faulting GPA and its kind). Every
        other field on it -- the instruction, `is_rvc`, the DCD-7
        classification (and, until BP-125, `is_vsetvl` and
        `needs_vtype`) -- is
        meaningless, and neither decode nor the backend may read
        it. The faulting instruction never executes, so nothing
        needs its length or class: the trap is taken from the
        fault fields. Ruled session-075 (Jeff); the IFU drives
        `is_rvc` from the faulting halfword today, which this makes
        harmless rather than wrong. Found by BP-118.

The start PC and the position are both present and are not
redundant. Expansion breaks the correspondence between them,
because a compressed instruction advances the PC by two and fills
a whole slot.

`is_rvc` is present because expansion also erases the length. The
backend needs it for the link address of a compressed JAL or JALR
(rd = pc + 2) and for the fall-through PC of a not-taken
mispredict. Added session-074 (Jeff).

TD-DCD-1  The vtype fields of the old `predecode_pkt_t` are
          `is_vsetvl`, `needs_vtype` and `vtype_hazard`. The
          first two are per-instruction and belong here. The
          third does not. `vtype_hazard` is defined as a vsetvl
          preceding a `needs_vtype` in the same bundle, and the
          bundle the predecoder sees is a prediction block while
          the bundle decode sees is 8 slots from the ibuf head.
          The ibuf regroups: one prediction block can split across
          two decode bundles and one decode bundle can draw from
          two prediction blocks. An intra-bundle property computed before
          the ibuf is wrong after it. `vtype_hazard` is computed
          in decode, DCD-17.

---

## 10a. Decode on the bundle view -- TD#143

RULED session-075 (Jeff). BUILT by BP-118. What decode does once it
takes `ifu_pd_pkt_t` from the ibuf read port (IBUF-9) instead of
`predecode_pkt_t`. Section 1 keeps the instruction ENCODINGS out of
scope, since they are the specification's; these four rules are its
boundary, which the specification does not decide. This read that
section 1 keeps the instruction decode out of scope, true until
section 10b (session-077).

DCD-17 `vtype_hazard` IS COMPUTED IN DECODE. For each of the 8
       decode slots it is set when an earlier valid slot in the
       same decode bundle is a vsetvl form and this slot needs
       vtype. Decode computes it from its OWN classification of
       the instruction, not from the `is_vsetvl` and `needs_vtype`
       bits in `ifu_pd_pkt_t`: decode's is exact, and the IFU's
       `needs_vtype` over-marks the whole-register forms (DCD-16).
       Closes DCD-U1.

       The ibuf stays a buffer with no knowledge of instruction
       meaning, and the decode bundle is exactly the group the
       flag describes.

DCD-18 DECODE PASSES `ifu_pd_pkt_t` THROUGH to rename unchanged,
       beside its own decode packet, plus `vtype_hazard` per slot.
       The PC, FTQ index, position, fault fields and `is_rvc`
       reach the backend this way (ftq_backend_interfaces.md A1).
       `predecode_out` and `predecode_pkt_t` are retired.

DCD-19 A SLOT CARRYING A FETCH FAULT IS NOT DECODED AS ILLEGAL.
       Its instruction bits are meaningless, and an instruction
       fetch fault takes priority over an illegal instruction
       exception. Decode passes the fault through and raises no
       illegal on that slot.

DCD-20 C AND Zcb ARE ALWAYS ENABLED. After expansion in the IFU
       decode cannot tell which compressed extension an
       instruction came from: `is_rvc` survives, the Zcb
       distinction does not. RVA23 mandates both, so `misa.C` is
       read-only 1, and decode's per-extension gating of
       compressed encodings is deleted.

TD#148  `is_vsetvl` and `needs_vtype` in `ifu_pd_pkt_t` have no
        reader once DCD-17 is built. Left in place so BP-118 needs
        no change to `bp_structs_pkg`. Removal ruled session-077
        (Jeff). CLOSED by BP-125: removed from the struct,
        ifu_predecode, ifu_f3 and every reader.

TD#155  `en_c`, `en_zcb` and `MASK_BITS` in instr_decoder lose
        their readers with the gating DCD-20 deletes. They are
        declared in decode_pkg.sv (`ext_enable_t`), so removing
        them is a package change; it narrows fe_top's ext_enable
        input and removes tb_instr_decoder's en_c=0 and en_zcb=0
        cases. CLOSED BY BP-120: removed; ext_enable_t and
        fe_top's ext_enable are 16 bits; tb_instr_decoder 654 ->
        649 checks.

As built by BP-118, a faulting slot's decode packet is `valid` and
the instruction bits only, no illegal and no vector decode, and it
neither raises nor seeds `vtype_hazard`. DCD-16a makes the
instruction bits meaningless too; decode reads none of them.

---

## 10b. Decode representation and legality -- session-077

RULED session-077 (Jeff), from the PA's R1 to R14, after BP-123. The
decoder mapped FP, AMO and CSR instructions onto placeholder
operations before BP-123, and BP-123 (D4) mapped the SYSTEM fences,
HLV/HLVX/HSV, WRS and FLH/FSH onto the representation already used
for their class, so a backend could not tell those operations apart.
Reading the decoder in session-077 also found reserved encodings in
those spaces accepted, which RVA23 recommends raising illegal. BUILT
by BP-124 (session-077): alu_op_t 8 bits, values 107 to 185 as
DCD-22 lists them, the seven decode_pkt_t fields after is_illegal,
Zvbb at 189 to 198; tb_instr_decoder 1323 checks; sim_dec_sweep
458752 encodings.

PA ADDITIONS, drafted session-077 and built by BP-124 as written:
DCD-24's vector paragraph and its is_fp, is_load and is_store rule;
DCD-25's zero-extended CSR address, the vtype immediates and the
vsetivli AVL; DCD-33; the vector part of DCD-34; DCD-35; the
operation names and order of DCD-22. Jeff accepted BP-124's
decisions D1 to D9 (session-077), recorded in DCD-24, DCD-25,
DCD-32 and DCD-36.

The specification references, checked session-077: a reserved
encoding's behaviour is UNSPECIFIED and raising illegal-instruction
is valid behaviour (unprivileged, RV32I; F chapter); RVA23 strongly
recommends illegal-instruction for unimplemented opcodes
(rva23-profile.adoc, RVA23U64 and RVA23S64 Recommendations); a
reserved FENCE configuration SHALL be treated as FENCE (RV32I), and
the unused fields of FENCE.I shall be ignored (Zifencei); Zfhmin is
FLH, FSH, FMV.X.H, FMV.H.X, FCVT.S.H, FCVT.H.S, and with D FCVT.D.H
and FCVT.H.D (zfhmin.adoc); Zfa's .H forms need Zfh, FMVH.X.D and
FMVP.D.X are RV32 only, and Zfa depends on F (zfa.adoc).

DCD-21 THE PRINCIPLE (R1). `alu_op` and the decoded fields of
       `decode_pkt_t` fully identify every scalar operation, its
       operands' register files and its legality. No downstream
       unit re-decodes the instruction word for any of these.
       `instr` stays in the packet for traps (stval) and debug, not
       as a decode source. For a vector instruction `v_op_class`
       identifies the operation and `alu_op` is ALU_VEC.

DCD-22 `alu_op_t` IS 8 BITS (R2). Values 0 to 106 keep their values;
       ALU_ILL stays 63. Three are RENAMED to their exact meaning,
       values unchanged: ALU_FLD (56) -> ALU_FLOAD, ALU_FSD (57) ->
       ALU_FSTORE, ALU_CSR (49) -> ALU_CSRRW. ALU_FMADD (58) keeps
       its name and now means FMADD only. The new operations are
       appended from 107 in this order:

```
  ALU_VEC
  FP      ALU_FMSUB ALU_FNMSUB ALU_FNMADD
          ALU_FADD ALU_FSUB ALU_FMUL ALU_FDIV ALU_FSQRT
          ALU_FSGNJ ALU_FSGNJN ALU_FSGNJX ALU_FMIN ALU_FMAX
          ALU_FCVT_W ALU_FCVT_WU ALU_FCVT_L ALU_FCVT_LU
          ALU_FCVT_FW ALU_FCVT_FWU ALU_FCVT_FL ALU_FCVT_FLU
          ALU_FCVT_FF ALU_FMV_XF ALU_FMV_FX
          ALU_FEQ ALU_FLT ALU_FLE ALU_FCLASS
  Zfa     ALU_FLI ALU_FMINM ALU_FMAXM ALU_FROUND ALU_FROUNDNX
          ALU_FCVTMOD_W_D ALU_FLEQ ALU_FLTQ
  A       ALU_LR_W ALU_LR_D ALU_SC_W ALU_SC_D
          ALU_AMOSWAP_W ALU_AMOSWAP_D ALU_AMOADD_W ALU_AMOADD_D
          ALU_AMOXOR_W ALU_AMOXOR_D ALU_AMOAND_W ALU_AMOAND_D
          ALU_AMOOR_W ALU_AMOOR_D ALU_AMOMIN_W ALU_AMOMIN_D
          ALU_AMOMAX_W ALU_AMOMAX_D ALU_AMOMINU_W ALU_AMOMINU_D
          ALU_AMOMAXU_W ALU_AMOMAXU_D
  fences  ALU_FENCE_I ALU_CBO_INVAL ALU_CBO_CLEAN ALU_CBO_FLUSH
          ALU_CBO_ZERO ALU_SFENCE_VMA ALU_SINVAL_VMA
          ALU_SFENCE_W_INVAL ALU_SFENCE_INVAL_IR ALU_HFENCE_VVMA
          ALU_HFENCE_GVMA ALU_HINVAL_VVMA ALU_HINVAL_GVMA
  Zawrs   ALU_WRS_NTO ALU_WRS_STO
  Zicsr   ALU_CSRRS ALU_CSRRC ALU_CSRRWI ALU_CSRRSI ALU_CSRRCI
```

       79 operations, 107 to 185. ALU_FENCE (55) is FENCE, with
       FENCE.TSO and PAUSE, which are FENCE configurations.

DCD-23 FP PRECISION IS A FIELD (R3). `decode_pkt_t` gains
       `fp_fmt [1:0]` and `fp_src_fmt [1:0]`, encoded 2'b00 S,
       2'b01 D, 2'b10 H, 2'b11 unused. `fp_fmt` is the instruction's
       fmt field (bits 26:25) for OP-FP and the four FMA opcodes, so
       for a conversion to or from an integer, a move, a compare or
       a classify it is the precision of the FP operand, and for
       ALU_FCVT_FF the destination; for an FP load or store it is
       the width of the memory datum. `fp_src_fmt` is the source
       precision of ALU_FCVT_FF only, from instruction bits 21:20
       (rs2[1:0]). Both
       are zero for a non-FP operation. The rounding mode stays in
       `funct3`. This read "for a conversion, of the destination",
       which left FCVT.W.S and FCVT.W.D indistinguishable.

DCD-24 OPERAND REGISTER FILES (R4). `decode_pkt_t` gains `rd_is_fp`,
       `rs1_is_fp` and `rs2_is_fp`; rs3 is always an FP register.
       `uses_rd`, `uses_rs1`, `uses_rs2` and `uses_rs3` are exact
       per operation: a unary FP operation (FSQRT, FCVT_*, FMV_*,
       FCLASS, FROUND, FROUNDNX, FCVTMOD_W_D) does not use rs2, and
       FLI uses no source register; rs3 is zero for every operation
       but the four FMAs. `is_fp` means the operation executes in
       the FP unit, so an FP load or store has `is_fp` clear and
       names its FP register with `rd_is_fp` or `rs2_is_fp`
       (BP-124 D2). LR sets `is_load` only, SC `is_store` only, an
       AMO both, a CBO neither (D3). `is_csr` is set for the six
       CSR operations and for ECALL, EBREAK, SRET, MRET and WFI,
       and clear for the fences, WRS, HLV/HSV and MOP (D6).
       Accepted session-077 (Jeff).

       FOR A VECTOR INSTRUCTION these fields describe its SCALAR
       register operands only; its vector register operands are in
       `vec_decode_pkt_t`. OPIVX and OPMVX read GPR rs1; OPFVF reads
       FPR rs1; vmv.x.s, vcpop.m, vfirst.m and the vsetvl forms
       write GPR rd; vfmv.f.s writes FPR rd; vsetvl reads GPR rs1
       and rs2, vsetvli GPR rs1, vsetivli neither; a vector load or
       store reads GPR rs1, and GPR rs2 when strided. Every other
       vector instruction uses no scalar register. For every vector
       instruction `is_fp` is clear (it executes in the vector
       unit), `is_load` is set for a vector load and `is_store` for
       a vector store, and `is_branch`, `is_jump` and `is_csr` are
       clear. Added session-077 by the PA as R4's consequence for
       vector instructions, whose scalar packet set uses_rd,
       uses_rs1 and uses_rs2 for every instruction; flagged for
       Jeff.

DCD-25 IMMEDIATES THAT SIT IN A REGISTER FIELD go in `imm`, because
       decode zeroes an unused register field: the CSRRxI zimm in
       `imm[16:12]` beside the CSR address in `imm[11:0]`, for all
       six CSR operations the address ZERO-extended and `imm[31:17]`
       zero, `imm[16:12]` zero for the register forms (the decoder
       sign-extended the address as an I-type immediate); the FLI
       constant index in `imm[4:0]`; an OPIVI 5-bit immediate in
       `imm`, sign- or zero-extended as the specification defines
       for that instruction, and vror.vi's 6-bit immediate, whose
       bit 5 is instruction bit 26, in `imm[5:0]` zero-extended;
       vmv<nr>r.v's register-count field zero-extended (BP-124 D9,
       accepted); the
       vtype immediate of vsetvli (zimm[10:0]) and vsetivli
       (zimm[9:0]) in `imm[10:0]` zero-extended, reserved bits
       included, so vill can be formed downstream; and vsetivli's
       AVL, uimm[4:0], in `imm[20:16]`. The decoder zeroes rs1 for
       CSRRWI, CSRRSI and CSRRCI, losing the zimm, and would lose
       vsetivli's AVL once DCD-24 clears its uses_rs1; found
       session-077, PA additions.

DCD-26 FP LEGALITY (R5). Legal, each gated by its enable: F (en_f),
       D (en_d), Zfhmin as quoted above (en_zfhmin; the D-dependent
       pair also en_d), Zfa's .S and .D forms and FCVTMOD.W.D
       (en_zfa; the .D forms also en_d). Illegal: every other .H
       operation (Zfh is not implemented), Zfa's .H forms,
       FMVH.X.D and FMVP.D.X (RV32 only), every Q form, and
       FCVTMOD.W.D with an rm other than 001 (RTZ), which zfa.adoc
       reserves.

DCD-27 STATIC ROUNDING MODE 101 OR 110 IS ILLEGAL (R6), in every
       instruction whose encoding has an rm field. Dynamic rm with
       an invalid frm is raised at execute, not here.

DCD-28 AMO LEGALITY (R7). Legal: funct3 010 (W) and 011 (D), with
       funct5 LR 00010 (rs2 must be x0), SC 00011, AMOSWAP 00001,
       AMOADD 00000, AMOXOR 00100, AMOAND 01100, AMOOR 01000,
       AMOMIN 10000, AMOMAX 10100, AMOMINU 11000, AMOMAXU 11100.
       Every other width (Zabha) and funct5 (AMOCAS, Zacas) is
       illegal. aq and rl travel in `funct7`.

DCD-29 FENCES AND CBO (R8). MISC_MEM funct3 000 is ALU_FENCE for
       every fm, pred, succ, rs1 and rd: the specification requires
       reserved configurations to be treated as FENCE. fm, pred and
       succ travel in imm[11:0] zero-extended, a reserved
       configuration's raw fields included; the backend executes
       a reserved configuration as FENCE with fm 0000 (RV32I).
       BP-124 D4, accepted session-077 (Jeff). funct3 001
       is ALU_FENCE_I, its imm, rs1 and rd ignored as Zifencei
       requires. funct3 010 is the CBO operation of imm (0, 1, 2,
       4), any other imm illegal, and rd not x0 illegal (DCD-31).
       funct3 011 to 111 is illegal. The SYSTEM fence forms are the
       ALU_SFENCE/SINVAL/HFENCE/HINVAL operations of DCD-22.

DCD-30 WRS, HLV, CSR (R9, R10, R11). WRS.NTO and WRS.STO are their
       own operations. HLV, HLVX and HSV keep the width-exact load
       and store operations, with `is_load` or `is_store`, and set
       new packet bits `is_hlsv` (a virtual-machine access) and,
       for HLVX, `is_hlvx` (read with execute permission). The six
       CSR instructions are six operations.

DCD-31 SYSTEM RESERVED FIELDS ARE ILLEGAL (R12). rd not x0 in
       ECALL, EBREAK, MRET, SRET, WFI, WRS, the SFENCE, SINVAL,
       HFENCE and HINVAL forms and CBO; rs1 not x0 in ECALL,
       EBREAK, MRET, SRET, WFI, WRS, SFENCE.W.INVAL and
       SFENCE.INVAL.IR.

DCD-32 VECTOR RESERVED ENCODINGS ARE ILLEGAL (R13): every encoding
       that decodes to VOTHER or to the VMEM default, and any store,
       segment or not, with sumop 10000 (built by BP-124).

       EVERY OTHER RESERVED VECTOR ENCODING IS ILLEGAL TOO. RULED
       session-077 (Jeff), after BP-124, which found 24742 in its
       sweep (rule VRSV) and reported them as this rule then said.
       The classes, from the V 1.0 text BP-124 cites:
       - mew = 1 (EEW 128 and above), every load and store form
       - a unit-stride segment load or store whose lumop/sumop is
         neither 00000 nor 10000
       - a whole-register load or store with vm 0, NFIELDS other
         than 1, 2, 4 or 8, mew 1, or (store) width not 000
       - vlm.v or vsm.v with vm 0, width not 000, or mew 1
       - vsetvl with bits 29:25 not zero (bit 31 set and bit 30
         clear is vsetvl; bit 30 set is vsetivli)
       - vadc and vsbc with vm 1
       - vmv.v.v/x/i and vfmv.v.f with vs2 not v0
       - vmv.s.x and vfmv.s.f with vs2 not v0 or vm 0
       - vfmv.f.s with vs1 not 0 or vm 0; vmv.x.s with vm 0
       - vmv<nr>r.v with vm 0 or a register count other than 1, 2,
         4 or 8
       - vcompress.vm and the eight mask-logical operations with
         vm 0
       - vid.v with vs2 not v0
       - VFUNARY0 selectors 00100, 00101 and 01101 (the last is
         Zvfbfmin's vfwcvtbf16.f.f.v, not implemented)
       This read: "Other reserved vector encodings found are
       reported for a ruling, not changed." BP-124 D7 classed every
       lumop 01000 encoding as whole-register, reserved NFIELDS
       included; those fall under the third class. An illegal
       vector word carries a zero vector packet (DCD-36).

       BUILT by BP-125, TD#175 closed: a reserved memory form
       decodes as VMEM and a reserved OP-V form as VOTHER, so the
       existing illegal path applies (D3). Counts by class, each
       encoding counted under the class of its form (D2; the
       classes overlap on mew): mew 15168, segment lumop/sumop 7168,
       whole-register 236, vlm/vsm 30, vsetvl 1178, vadc/vsbc 190,
       vmv.v/vfmv.v.f 136, vmv.s.x/vfmv.s.f 144, vfmv.f.s/vmv.x.s 76,
       vmv<nr>r 66, vcompress and mask-logical 342, vid.v 2,
       VFUNARY0 6; total 24742. CORRECTED session-077: the vsetvl
       class read "bits 30:25", copied by the PA from BP-124's report
       without checking the encoding; bit 30 set is vsetivli, so
       that text would have made half the vsetivli encodings
       illegal. BP-125 built bits 29:25. Checked against
       riscv-opcodes rv_v, every other class matches its fixed
       fields.

DCD-33 ZVBB IS DECODED, one v_op_class per instruction, appended
       after VOP_VSOXSEG in this order with the values 189 to 198:
       VOP_VANDN, VOP_VBREV, VOP_VBREV8, VOP_VREV8, VOP_VCLZ,
       VOP_VCTZ, VOP_VCPOP_V (VOP_VCPOP is vcpop.m), VOP_VROL,
       VOP_VROR and VOP_VWSLL, gated by en_v, each with is_vector and
       needs_vtype set. Zvbb is mandatory in RVA23U64
       and the decoder had no entry for it, so DCD-32 would have
       made it illegal. Added session-077 by the PA; flagged for
       Jeff.

DCD-36 AN ILLEGAL PACKET carries ALU_ILL and nothing else: no
       register (uses_* clear, the fields zero), no immediate, no
       is_* flag, no FP field, and a zero vector packet, so rename
       and dispatch see only the trap. BP-124 D5, accepted
       session-077 (Jeff).

DCD-34 VERIFICATION (R14). Legality and classification are checked
       against a disassembler oracle, spike-dasm, the disassembler the
       decoder work has used, with --isa naming exactly the implemented
       extensions (every RVA23U64 and RVA23S64 mandatory extension that
       has instructions, H and Svinval among them, and no optional one).
       Directed decoder tests take each word from clang -c (RISC-V
       target, the same extension set) and confirm it with spike-dasm.
       This read "an LLVM disassembler oracle, as BP-117 checked the
       expander, with --mattr". spike-dasm and clang replaced it
       session-077 (Jeff). BP-124 found LLVM installed off PATH, in the
       embecosm toolchain under /usr/local, which the expander oracle
       uses (TD#147); this note said the system had no LLVM. BUILT by
       BP-124: sim_dec_sweep compares the decoder against
       tb/dec_dasm_oracle.txt (458752 encodings, including all eight
       LOAD-FP and STORE-FP widths), oracle_dec_sweep regenerates it
       with tb/gen_dec_dasm_oracle.py, and asm_dec_words re-checks the
       216 directed words with clang and spike-dasm (246 since BP-125).
       The out-of-repo tool path is TD#176. Since DCD-32's classes
       became illegal (BP-125) the sweep expects 208902 legal and 249850
       illegal. BP-124's Results Capture gave its totals as 233504 and
       225248; its per-space figures sum to 233644 and 225108. The sweep
       covers every funct and selector field of OP_FP, the four FMA
       opcodes, AMO, MISC_MEM, SYSTEM, and, because of DCD-32 and
       DCD-33, OP_VECTOR and the vector forms of LOAD-FP and STORE-FP.
       Each disagreement is resolved against the ratified specification
       and listed. The sweep over the vector space was added by the PA
       with DCD-33.

DCD-35 THE Zimop COMMENTS are corrected: Zicfiss, an RVA23
       expansion option this design does not implement, redefines
       some MOP encodings. decode_pkg.sv reads "(no extension
       redefines them in RVA23)" and instr_decoder.sv "no RVA23
       extension redefines them" (BP-123); both become "no
       extension this design implements redefines them; Zicfiss, an
       RVA23 option not implemented, redefines some".

---

## 11. Open

DCD-U1  CLOSED session-075 by DCD-17: decode. It asked where
        `vtype_hazard` is computed; TD-DCD-1 had excluded the
        predecoder and left the ibuf read port and decode.

DCD-U2  CLOSED session-070 by ras_decisions.md RAS-DS1: the RAS
        treats them as two operations and performs the POP FIRST,
        then the push. bp_cluster.md and ftq_bpu_interfaces.md 5.4
        agree. This asked for the order "if the RAS treats them as
        two operations"; it does, and RAS-DS1 says so. What is
        then open was TD-DCD-2, whether the BUILT RAS implemented
        it; it did not, and BP-119 built it.

---

## 12. Bindings

IFU-1     Expansion in the IFU. The RVC expander is specified
          there, not here.
IFU-3     Puts predecode in the IFU.
IFU-4     Expansion before predecode, the premise of DCD-7.
IFU-6     Unaligned block, the premise of DCD-5.
IFU-8     17 positions, the premise of DCD-2.
IFU-15    The IFU owns the prediction test, not DCD-14.
IFU-16    Satisfied by DCD-7.
IFU-17    Satisfied by DCD-10.
IFU-18    Direction is proven only for an unconditional, which
          follows from DCD-7 and is the FTQ's rule.
IBUF-2    Consumes the bundle view of DCD-16.
TD-IFU-1  Closed by DCD-16.
TD-IFU-5  Closed by this document.
IBUF-9    The 8-wide read port that sets the decode bundle of
          DCD-17.
TD#143    DCD-17 to DCD-20 built by BP-118; rvc_expander.sv
          retires in BP-119.
MMU-29    The implicit-access kind of DCD-16.
MMU-23    FAULT_GPA_WIDTH, DCD-16.

---

## 13. Document History

```
  2026-10-09  session-077, ruling (Jeff). DCD-15, DCD-16 and DCD-16a
              carry the implicit-access kind of a guest physical
              address. This document had no history section; its
              earlier changes are in PROJECT_STATUS.

  2026-10-09  session-077, after BP-123, rulings (Jeff). Section 1:
              the representation and legality are in scope. DCD-16:
              the GPA is FAULT_GPA_WIDTH = 56; the kind is built.
              Section 10b, DCD-21 to DCD-35, from R1 to R14. DCD-24's
              vector paragraph, DCD-33 (Zvbb) and the vector part
              of DCD-34 were added by the PA and flagged.

  2026-10-09  session-077, after review of the BP-124 draft. DCD-23:
              fp_fmt is the encoding's fmt field. DCD-24: is_fp,
              is_load and is_store for vector instructions. DCD-25:
              the vtype immediates and the vsetivli AVL. DCD-26:
              FCVTMOD.W.D needs rm 001. DCD-35: the exact comment
              text. 10b lists the PA additions pending Jeff. 10a's
              scope sentence; DCD-16's "last two".

  2026-10-10  session-077, ruling (Jeff). DCD-34: the oracle is
              spike-dasm and directed words come from clang -c; the
              LLVM oracle is withdrawn, there being no LLVM on the
              system.

  2026-10-10  session-077, after BP-124, rulings (Jeff). 10b built;
              the PA additions accepted as built. BP-124's D2 to D7
              and D9 accepted: DCD-24 (FP load/store is_fp, LR/SC/AMO
              marking, is_csr, rs3), DCD-29 (the FENCE immediate),
              DCD-36 (the illegal packet). DCD-32: every reserved
              vector encoding is illegal, the VRSV classes listed;
              built by BP-125. DCD-34: built; LLVM is installed off
              PATH, so the "no LLVM" note is corrected.

  2026-10-10  session-077, ruling (Jeff). DCD-16 and TD#148:
              is_vsetvl and needs_vtype leave ifu_pd_pkt_t; removed
              by BP-125.

  2026-10-10  session-077, after BP-125. DCD-32 built, TD#175
              closed, with the per-class counts; its vsetvl class
              corrected from bits 30:25 to 29:25 (PA error). DCD-34:
              the sweep's totals. DCD-16 and TD#148: the removal
              built, 192 -> 190 bits.
```
