<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Decode Implementation Decisions
```
 FILE:    dcd_decisions.md
 SOURCE:  session-069
 STATUS:  DRAFT
 UPDATED: 2026-09-15
 CONTACT: Jeff Nye
```

Owns the DCD-N, TD-DCD-N and DCD-UN registries.

---

## 1. Scope and reference

The RISC-V unprivileged specification is the reference for every
instruction encoding, immediate format and register field named
here. This document does not restate them. It contains only what
the specification does not decide.

`instr_decoder.sv` is not in scope. It is Complete and decodes
what the predecoder hands it.

The RVC expander is not in scope either. Its encodings are the
compressed-instruction chapter of the specification, and the
project's decisions about it are placement and ordering, which
belong with the stage that holds it: `ifu_decisions.md` IFU-1 puts
it in the IFU ahead of the ibuf, and IFU-4 runs it before
predecode.

The predecoder replaces `predecode.sv`, and `predecode_pkt_t` is
redefined rather than extended. Neither the existing module nor
the existing struct constrains anything below.

---

## 2. One predecoder, two views

DCD-1  There is one predecoder. It produces two views of one
       classification.

       The block view is `ftq_pd_info_t` at each of the 16
       halfword positions of the fetch block. It goes to the FTQ
       writeback and its shape is fixed by `ftq_ifu.sv`.

       The bundle view is `predecode_pkt_t` at each of the 8
       decode slots. It goes through the ibuf to
       `instr_decoder`.

The two differ in width because their consumers do. The FTQ needs
an answer at every position in the block, including positions that
are not instruction starts. Decode needs `SLOTS` of 8. The
classification is computed once.

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
       not at position 0. The block is unaligned, IFU-6.

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

TD-DCD-2  The RAS is Complete and was built before DCD-11 existed.
          Whether it accepts both bits set on one instruction,
          and in which order it applies them, is unverified.
          A task against the RAS, not against the predecoder.

---

## 8. Validity and range

DCD-12 A position's `valid` is set when it is an instruction
       start under DCD-4 and it lies within the fetched range.

DCD-13 `pd_range` marks the positions actually fetched. The
       range ends at the predicted taken position when the FTQ
       supplied one, and at the block end otherwise.

DCD-14 The predecoder does not test the prediction. It reports
       what it found. The comparison against the prediction, and
       `cfi_val`, `cfi_pos`, `mis_val`, `mis_pos`, are the IFU's,
       IFU-15.

---

## 9. Faults

DCD-15 A faulting position is reported with `fault_val` and
       `fault_pos` in the block view, and with the cause and the
       faulting virtual address in the bundle view.

The two carry different things on purpose. The FTQ needs only to
know the block ended early. The architectural exception travels
with the instruction to the backend. This is IFU-2 and the note
under IFU-20.

---

## 10. The bundle view

DCD-16 `predecode_pkt_t` carries, per slot: valid, the expanded
       32-bit instruction, the start PC, the position within the
       fetch block, the FTQ index, the fault cause, the faulting
       virtual address, and the control flow classification of
       DCD-7.

The start PC and the position are both present and are not
redundant. Expansion breaks the correspondence between them,
because a compressed instruction advances the PC by two and fills
a whole slot.

TD-DCD-1  The vtype fields of the old `predecode_pkt_t` are
          `is_vsetvl`, `needs_vtype` and `vtype_hazard`. The
          first two are per-instruction and belong here. The
          third does not. `vtype_hazard` is defined as a vsetvl
          preceding a `needs_vtype` in the same bundle, and the
          bundle the predecoder sees is a fetch block while the
          bundle decode sees is 8 slots from the ibuf head. The
          ibuf regroups: one fetch block can split across two
          decode bundles and one decode bundle can draw from two
          fetch blocks. An intra-bundle property computed before
          the ibuf is wrong after it. `vtype_hazard` has to be
          computed at the ibuf read port or in decode.

---

## 11. Open

DCD-U1  Where `vtype_hazard` is computed. TD-DCD-1 establishes
        that it cannot be the predecoder and does not choose
        between the ibuf read port and decode.

DCD-U2  The order of the pop and the push in the DCD-11 case, if
        the RAS treats them as two operations. Belongs to the RAS
        and is carried here only because DCD-11 raises it.

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


