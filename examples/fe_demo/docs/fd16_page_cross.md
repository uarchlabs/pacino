<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd16_page_cross: A Fetch Block Crossing a Page
```
 FILE:    fd16_page_cross.md
 SOURCE:  DOC-002, DOC-006
 STATUS:  WORKING
 UPDATED: 2026-10-17
 CONTACT: Jeff Nye
```

`fd16_page_cross` is the FD-16 demonstration scenario. It is a demo,
not a verification test. A jump lands 16 bytes before the end of a
4 KiB page whose virtual successor is mapped to a non-adjacent physical
page. The fetch block starting there covers both pages, so the IFU
translates it twice and requests one line from each physical page; a
32-bit instruction straddles the boundary. The run passes if a
translation-queue entry is popped with two translations of different
PPNs.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).
A recorded run:

```
-I: fd16_page_cross: PASS, blocks translated twice 1, cyc 112
```

---

## 1. The program

Source: `programs/fd16_page_cross.svh`, task `prog_fd16`. S-mode under
satp Sv39 (begin_scen use_sv39 = 1).

```
mapping  RESET_VECTOR page to itself
         b      = 0x8001_0000 -> 0x8100_0000
         b+4K   = 0x8001_1000 -> 0x8120_5000   not adjacent
0x8000_0000  mixed(3)
0x8000_0008  jal x0, b+0xFF0
b+0xFF0      c.addi a0,1 (7 of them)        0xFF0 to 0xFFD
b+0xFFE      addi t0,t0,1                   32-bit, bytes 0xFFE-0x1001
b+0x1002     mixed(8), jal x0,0             halt
```

- `map4k` (`rtl/core/frontend/fe_top/tb/models/fe_tb_writer.svh:142`)
  writes each Sv39 leaf and records the VA page in `vmap`, which
  `put_hw` uses to place each halfword at its physical address, so the
  32-bit instruction's two halfwords land in different physical pages
  (0x8100_0FFE and 0x8120_5000).
- The jump target is 16 bytes before the page end; FD-16 asks for a
  block starting within 32 bytes of it.

---

## 2. Why the program produces the behaviour

1. The block crosses. `ifu_xlate` marks a block as crossing when its
   start PC's page offset is at least `CROSS_FROM` 0xFE0, 32 bytes
   from the end (`rtl/core/frontend/ifu/rtl/ifu_xlate.sv:144`,
   `:281`), and then needs two lookups (`r_need`, `:407`); the queue
   entry keeps both pages' results (`:306-308`); the page-1 fields
   are meaningful only for a crossing block (`:33-34`).
2. Two ITLB lookups and two walks. In the run (cyc is `tb.cyc`,
   `fe_tb_dut.svh:129`) the ITLB lookups (`ifu_itlb_vpn`) go from VPN
   0x80010 to 0x80011, and both miss: walks for VPN 0x80010 at cyc
   46 and VPN 0x80011 at cyc 70.
3. The queue entry. At cyc 94 the entry for the block at
   0x8001_0FF0 is popped with `xq_cross` 1, `xq_ppn0` 0x81000 and
   `xq_ppn1` 0x81205.
4. Two lines from two pages. A block starting in the upper half of a
   line needs a second line (IFU-7), and for a crossing block that line
   is the second page's first line (IFU-25,
   `rtl/core/frontend/ifu/rtl/ifu_fetch.sv:283-284`). The L1I requests
   are 0x8100_0FC0 (cyc 93) and 0x8120_5000 (cyc 94).

The backend compares every retired instruction with the expected
stream, so the 32-bit instruction at b+0xFFE retired with its expected
encoding.

---

## 3. What the monitor counts

The count comes from `tb/fe_demo_mon.svh:531-535`, sampled every cycle
while the stream is being measured (`meas`).

```
n_xq_cross   u_ifu.u_xlate.xq_val && xq_pop && xq_cross
             && xq_ppn0 != xq_ppn1
             a translation-queue entry popped with two translations
             of different physical pages
```

The proof (`tb/fe_demo_proofs.svh:133`) is `n_xq_cross > 0`.
`tb_fe_demo.sv` also requires the whole stream to retire with no errors
before it accepts the proof.

---

## 4. Reading the numbers

- The figure is 1: the program has one crossing block, and the run's
  translation queue shows no other entry popped with `xq_cross` set.
- The monitor also requires the two PPNs to differ, so the count shows
  two translations, not one page's result read twice. Here they are
  0x81000 and 0x81205.
- The program meets FD-16 of `planning/showcase/fe_demo_scenarios.md`
  (a block that starts within 32 bytes of a page end); the proof is
  FD-16's. No departure.

---

## 5. Waveform

The saved view is `waves/fd16_page_cross.sucl`, which `make view
S=fd16_page_cross` opens in Surfer. Groups: clock, ftq_ifu, ifu_xlate,
itlb, ifu_l1i, decode. Look at:

- `ftq_ifu_start_pc` 0x8001_0FF0: the crossing block.
- `ifu_itlb_req_val` with `ifu_itlb_vpn` 0x80010 then 0x80011: the two
  lookups.
- cyc 94: `xq_pop` with `xq_cross` 1, `xq_ppn0` 0x81000 and `xq_ppn1`
  0x81205.
- `ifu_l1i_req_paddr` 0x8100_0FC0 then 0x8120_5000.
- In the itlb group the encoded fields are shown as numbers (DOC-006):
  `itlb_ifu_status` (`planning/interfaces/itlb_ifu_interfaces.md`
  IT-4) is 0 hit, 1 miss (a walk has started), 2 fault, 3 reserved;
  `itlb_ifu_cause` (IT-6), valid with a fault, is 1 instruction access
  fault, 12 instruction page fault, 20 instruction guest-page fault.
