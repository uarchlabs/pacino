<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Instruction Buffer Decisions
```
 FILE:    ibuf_decisions.md
 SOURCE:  session-069
 STATUS:  DRAFT
 UPDATED: 2026-09-15
 CONTACT: Jeff Nye
```

Owns the IBUF-N, TD-IBUF-N and IBUF-UN registries.

Scope is the instruction buffer between the IFU and decode. The
write side is fixed by `ifu_decisions.md` and recorded here rather
than decided. The port itself is `ifu_ibuf_interfaces.md`.

---

## 1. Why the document is short

The ibuf holds instructions the RISC-V specification already
defines, so it decides nothing about them. IFU-1 puts compressed
expansion in the IFU, so every entry is a 32-bit instruction and
the buffer has no variable-length packing. What is left is depth,
port widths, and behaviour on a redirect.

---

## 2. Structure

IBUF-1  A FIFO. In order in, in order out. No reordering, no
        out-of-order read.

IBUF-2  Entries are uniform. Each holds what IFU-2 delivers: the
        expanded 32-bit instruction, its start PC, its position
        within the fetch block, its predecode result, its FTQ
        index, and its fault cause.

The start PC is stored per entry rather than derived. Expansion
breaks the correspondence between position and address, because a
compressed instruction advances the PC by two and fills a whole
entry.

---

## 3. Write side

IBUF-3  The write port is 16 entries wide with one per-entry
        enable mask. The IFU does not compact. The ibuf compacts
        on write, which is IFU-5. The port is
        `ifu_ibuf_interfaces.md`.

IBUF-4  A block is accepted whole or not at all. The ibuf asserts
        ready only when 16 entries are free, whatever the block
        actually contains.

IBUF-4 is the simplifying choice and it costs capacity. Accepting
a partial block means the write logic handles a block split across
two cycles and the IFU holds the remainder, which puts state back
in F3 that IFU-5 moved out. Requiring 16 free entries wastes up to
15 at the tail and needs no such state.

IBUF-5  Uncached fetch is an ordinary write with one entry valid.
        IFU-23 sends one instruction at a time and the ibuf needs
        no separate path for it.

---

## 4. Read side

IBUF-6  The read port is the decode width, in order, from the
        head.

IBUF-7  When the buffer is empty a write bypasses to the read
        port in the same cycle.

IBUF-7 exists because without it every redirect pays an extra
cycle refilling an empty buffer, and a redirect is when that cycle
is least affordable. The cost is that the write data feeds the
read mux combinationally.

IBUF-9  The read port is 8 wide. `instr_decoder.sv` is an 8-wide
        parallel decoder and every port is `[SLOTS-1:0]`.

The ibuf is therefore the width converter of the front end: 16
positions in from one fetch block, 8 out to decode.

IBUF-10 The entry delivers a `predecode_pkt_t` to decode.
        `instr_decoder` reads only `.instr` and `.valid` from it
        and passes the rest through to rename untouched, so
        whatever the ibuf stores in that field survives to
        rename.

TD-IBUF-1  `predecode_pkt_t` has no PC, no FTQ index, no fault
           cause and no faulting VA. IBUF-2 requires all four.
           Same item as TD-IFU-1; the field is added once and
           both documents depend on it.

`ftq_pd_info_t`, the 16-position predecode array of IFU-14, and
`predecode_pkt_t`, the 8-slot bundle here, are different views of
the same predecode. The first is sized to the fetch block and goes
to the FTQ. The second is sized to decode and goes through the
ibuf.

IBUF-U1 Whether the buffer is banked. A flat depth-to-1 mux per
        read output may be too expensive at 8 outputs, and
        banking replaces it with a per-bank mux followed by a
        select across banks. If banked, the bank count is at
        least the 8 of IBUF-9, since the bank count caps dequeue.
        XiangShan banks for exactly this reason, requires the
        count to be at least its decode width, and sits at 6 and
        6 with no margin. Banking changes nothing about enqueue:
        every entry keeps its own write mux. Unresolved.

---

## 5. Depth

IBUF-11 The depth is a parameter. 64 to start.

IBUF-4 requires 16 free entries to accept a block, so 32 is the
floor: below it the buffer stalls the IFU with entries still free.
XiangShan uses the same rule, gating enqueue on IBufSize minus
PredictWidth, and sits at 48 against a PredictWidth of 16, which
is the floor plus one more bundle. Their decode width is 6, so 48
is eight times it. Pacino decodes 8 wide, and the same ratio gives
64.

The number that would settle it rather than reason toward it is
how long a fetch bubble the buffer has to cover at 8 instructions
per cycle, and the bubble that matters is an L1I miss, whose real
latency is unknown until TD#118 closes.

---

## 6. Redirect

IBUF-8  A redirect clears the buffer entirely. Nothing in it is
        on the corrected path, because everything it holds was
        fetched after the redirecting instruction.

---

## 7. Open

IBUF-U1  Whether the buffer is banked. Section 4.

---

## 8. Bindings

IFU-2     Sets the entry contents of IBUF-2.
IFU-5     Gives the compaction to IBUF-3.
IFU-23    Uncached fetch, IBUF-5.
ITLB-11   The fault cause and VA carried in IBUF-2 originate
          here.
IB-*      The write port is `ifu_ibuf_interfaces.md`.
TD#118    Bounds IBUF-11.

