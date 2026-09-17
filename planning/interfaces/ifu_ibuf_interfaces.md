<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# IFU to Instruction Buffer Interface
```
 FILE:    ifu_ibuf_interfaces.md
 SOURCE:  session-069
 STATUS:  DRAFT
 UPDATED: 2026-09-15
 CONTACT: Jeff Nye
```

Owns the IB-N registry.

---

## 1. Scope

One group crosses this boundary: the IFU presents a fetch block's
instructions to the ibuf. There is no return path other than the
handshake.

The ibuf read side into decode is not here. It is
`ibuf_decisions.md` IBUF-6 and IBUF-9, because decode has no
planning document and an interface file into it would be the only
planning artifact in that unit.

---

## 2. The group

```
  ifu_ibuf_val                            IFU -> ibuf
  ifu_ibuf_en   [FTQ_PD_WIDTH-1:0]        IFU -> ibuf
  ifu_ibuf_slot [0:FTQ_PD_WIDTH-1]        IFU -> ibuf
                predecode_pkt_t
  ibuf_ifu_rdy                            ibuf -> IFU
```

`FTQ_PD_WIDTH` is 16.

IB-1  The port is fixed width. All 16 slot positions are
      presented every cycle a block is offered, whatever the block
      contains. The IFU does not compact and the width does not
      vary.

IB-2  `ifu_ibuf_en` is the per-slot write enable and is the only
      statement of which slots are real. A clear bit means the
      position is not an instruction start, or is outside the
      fetched range, or was truncated by the prediction check.
      The ibuf does not distinguish those cases and does not need
      to.

IB-3  `predecode_pkt_t.valid` is not driven on this port. It is
      produced by the ibuf on its read side, where it says whether
      a read slot holds an instruction. Driving it here would give
      one fact two producers.

IB-2 collapses three IFU-internal facts into one bit. DCD-12's
per-position valid is a start within the fetched range, and the
prediction check of IFU-15 may truncate the block further at
`mis_pos`. The ibuf sees only the result.

---

## 3. Handshake

IB-4  Decoupled valid and ready. `ifu_ibuf_val` asserts when the
      IFU has a block at F3. `ibuf_ifu_rdy` asserts when the ibuf
      can take it.

IB-5  A block transfers whole in one cycle or not at all. There
      is no partial acceptance and no multi-cycle block.

IB-6  `ibuf_ifu_rdy` asserts only when `FTQ_PD_WIDTH` entries are
      free, whatever `ifu_ibuf_en` actually contains. This is
      IBUF-4.

IB-6 is why IB-5 holds. The ibuf reserves for the widest case, so
an accepted block always fits and the IFU never holds a remainder.
IFU-5 moved compaction out of F3 and a partial transfer would put
it back.

IB-7  The IFU holds `ifu_ibuf_val` and the whole payload stable
      while ready is low. F3 does not advance.

---

## 4. Payload

Each slot carries `predecode_pkt_t` as defined in
`dcd_decisions.md` DCD-16:

```
  instr        the expanded 32-bit instruction
  start_pc     the address of this instruction
  pos          its halfword position in the fetch block
  ftq_idx      the FTQ entry this block came from
  fault_cause  access fault, page fault, guest-page fault, none
  fault_va     the faulting virtual address
  fault_gpa    the faulting guest physical address, valid only on
               a guest-page fault
  cfi          the control flow classification of DCD-7
  is_vsetvl    per-instruction, from DCD-16
  needs_vtype  per-instruction, from DCD-16
```

IB-8  `start_pc` and `pos` are both carried and neither derives
      from the other. Expansion breaks the correspondence: a
      compressed instruction advances the PC by two and fills a
      whole slot.

IB-9  The fault fields are per slot, not per block. The
      architectural exception travels with the instruction it
      belongs to. The block-level fault report is a different
      thing and goes to the FTQ, not here. IFU-2 and DCD-15.

IB-9a Three causes, not two. H is mandatory in RVA23 through Sha,
      so a guest-page fault is a normal outcome and its guest
      physical address rides here for Shtvala. MMU-16.

`vtype_hazard` is not on this port. It is an intra-bundle property
and the ibuf regroups instructions across bundle boundaries, so a
value computed before the ibuf is wrong after it. TD-DCD-1, open
as DCD-U1.

---

## 5. Uncached fetch

IB-10 An uncached fetch is an ordinary transfer with one bit set
      in `ifu_ibuf_en`. There is no separate port and no separate
      protocol. IFU-23 and IBUF-5.

The IFU's serialisation for uncached fetch happens before this
boundary. By the time a block is offered here the ordering
obligation is already met.

---

## 6. Redirect

IB-11 The redirect does not cross this boundary. The ibuf clears
      from its own connection, not through the IFU. FE-18 has
      each unit take the redirect by the path it declares, and
      forwarding it through the IFU would delay the ibuf clear by
      the IFU's own handling.

IB-U1 Which source clears the ibuf, and whether it is the same
      event that flushes the IFU. The FTQ drives
      `ftq_ifu_flush_val` to the IFU. XiangShan clears its
      IBuffer from the backend redirect instead. If the two
      sources differ, the IFU and the ibuf can disagree for some
      number of cycles about what has been discarded. Unresolved,
      and it belongs with the flush work that is deferred until
      the data path exists.

---

## 7. Open

IB-U1  The ibuf clear source. Section 6.

---

## 8. Bindings

IFU-5     Fixed-width vector, compaction in the ibuf. IB-1.
IFU-15    The prediction check truncation folded into IB-2.
IFU-23    Uncached, IB-10.
DCD-7     The classification carried in section 4.
DCD-12    Start and range, folded into IB-2.
DCD-16    Defines the payload.
IBUF-4    The ready rule, IB-6.
IBUF-5    Uncached as an ordinary write, IB-10.
IBUF-8    The clear, IB-11.
TD-DCD-1  Keeps `vtype_hazard` off this port.
