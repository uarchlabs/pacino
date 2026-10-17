<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd17_rvc: Compressed and Unaligned Code
```
 FILE:    fd17_rvc.md
 SOURCE:  DOC-002
 STATUS:  WORKING
 UPDATED: 2026-10-15
 CONTACT: Jeff Nye
```

`fd17_rvc` is the FD-17 demonstration scenario. It is a demo, not a
verification test. Straight-line code of mixed 16- and 32-bit
instructions places a 32-bit instruction at the last halfword of a
32-byte block. The IFU delivers it whole from the block's 17th halfword,
and the next block starts on its tail. A loop of compressed control
transfers then runs from block starts that are not 32-byte aligned. The
run passes if the straddling instruction reaches retirement whole and
16-bit instructions retire.

A recorded run:

```
DEMO PASS fd17_rvc: 32-bit instructions at block position 15 delivered
whole 1; 16-bit instructions 98 (cycles 270)
```

---

## 1. The program

Source: `programs/fd17_rvc.svh`, task `prog_fd17`. M-mode, bare. The
addresses are offsets from RESET_VECTOR 0x8000_0000
(`rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv:40`). `mixed(n)` writes
c.addi, except addi for every k with k % 3 == 1
(`fe_tb_writer.svh:250`; the writer is
`rtl/core/frontend/fe_top/tb/models/fe_tb_writer.svh`).

```
+0x00  mixed(20)          13 c.addi, 7 addi              0x36 bytes
+0x36  4 x c.addi         to +0x3E
+0x3E  addi t0,t0,1       32-bit, halfwords +0x3E and +0x40: crosses
                          the 32-byte block end and the 64-byte line
+0x42  mixed(5)           top = +0x4E
loop, 8 passes (it = 0..7), from top = +0x4E:
+0x4E  c.addi
+0x50  c.bnez x8, +0x54   taken on odd passes (skips +0x52)
+0x52  c.addi             executed on even passes; written dry on odd
+0x54  addi
+0x58  c.jalr x1          to fn = +0x400 (INDIRECT_CALL), link +0x5A
+0x400 c.addi; addi; c.jr x1 at +0x406 (RETURN to +0x5A)
+0x5A  c.addi
+0x5C  c.j +0x64          +0x5E..+0x63 written dry (3 c.addi)
+0x64  c.addi
+0x66  c.beqz x8, top     taken on passes 0..6
+0x68  mixed(3), then jal x0,0 (halt)
```

- The writer appends each compressed control transfer with its 32-bit
  expansion (`fe_tb_writer.svh:435-492`, cj, cbz, cjr, cjalr), which is
  what decode delivers in `instr`. Outcomes are the writer's, as in
  every scenario; x8 is not read.
- The loop's blocks start at +0x4E, +0x54 and other non-aligned
  addresses: a taken transfer starts the next FTQ block at its target.

---

## 2. Why the program produces the behaviour

1. The 17-halfword window. F2 selects 17 halfwords from the block
   offset (`rtl/core/frontend/ifu/rtl/ifu_fetch.sv:445`), from the two
   lines `{rd_data1, rd_data0}`. A 32-bit instruction that starts at
   position 15 of a 32-byte block therefore completes inside the block.
   A block in the upper half of its line asks for the next line as
   well (`w_two`, `ifu_fetch.sv:281`, IFU-7).
2. The block at +0x20 ends by falling through, and its last delivered
   instruction is 32-bit and starts 2 bytes before next_pc (+0x40). F3
   then sets the straddle register (`w_strad_set`,
   `rtl/core/frontend/ifu/rtl/ifu_f3.sv:375`; the register is
   described at `ifu_f3.sv:64`) with `r_strad_pc` = +0x40.
3. The block at +0x40 arrives at F3 with that start PC, so `first_tail`
   (`ifu_f3.sv:250`) starts its walk at position 1: the halfword at
   +0x40 is the tail of the instruction already delivered.
4. Seen in the run (fst2vcd on `out/fd17_rvc/fd17_rvc.fst`): the FTQ
   blocks start at +0x00, +0x20, +0x40, ...; at cycle 21
   `r_strad_val` is 1 with `r_strad_pc` 0x8000_0040; in the same cycle
   decode slot 4 holds start_pc 0x8000_003E, pos 15 (f), is_rvc 0,
   instr 0x00128293, ftq_idx 1; the next bundle starts at 0x8000_0042,
   pos 1, ftq_idx 2.

---

## 3. What the monitor counts

Both counts are taken in `be_retire_hook` (`tb/fe_demo_mon.svh:286-291`)
as each expected instruction retires, while `meas` is set.

```
n_straddle   no fault, !is_rvc, pos == 15, and the packet's instr equals
             the expected (expanded) encoding: a 32-bit instruction in
             the last halfword of its block, delivered whole
n_rvc        no fault, is_rvc: a 16-bit instruction retired
```

The proof (`tb/fe_demo_proofs.svh:123`) is
`n_straddle > 0 && n_rvc > 0`. `tb_fe_demo.sv` also requires the whole
stream to retire with no errors.

---

## 4. Reading the numbers

- `delivered whole 1` is the instruction at +0x3E (seen at cycle 21,
  section 2).
- `16-bit instructions 98` matches the program (derived from the
  source): 13 c.addi in mixed(20), 4 c.addi to +0x3E, 3 in mixed(5);
  9 per odd pass and 10 per even pass (the c.addi at +0x52), 76 over
  the 8 passes; 2 in the final mixed(3). 20 + 76 + 2 = 98. The halt is
  32-bit.
- Departures from `planning/showcase/fe_demo_scenarios.md` FD-17:
  - FD-17's shows line names "a 34-byte block, and a 32-bit
    instruction straddling two blocks". These are one event here: the
    straddling instruction is delivered in the block before the
    boundary (the 34-byte window), and the next block starts on its
    tail. No instruction is split between two delivered blocks; the
    design does not do that (IFU-8, IFU-11).
  - The proof as built checks the instruction's encoding and position
    at retirement; FD-17's proof is "a straddling instruction
    delivered whole". It matches.

---

## 5. Waveform

The saved view is `waves/fd17_rvc.sucl`, which `make view S=fd17_rvc`
opens in Surfer. Look at:

- `ftq_ifu_start_pc` and `ftq_ifu_next_pc`: the blocks +0x20 to +0x40
  and +0x40 to +0x60 at the start of the run.
- `ifu_ibuf_val`, `ifu_ibuf_en` and `ibuf_ifu_rdy`: the blocks entering
  the ibuf.
- `pd_out.[4]` at cycle 21: start_pc 0x8000_003E, pos 15, is_rvc 0.
- In the loop, `pd_out.[i].is_rvc` set on the compressed transfers and
  `pd_out.[0].instr` holding their expansions (jal, beq/bne, jalr).
- The straddle register (`u_ifu.u_f3.r_strad_val`, `r_strad_pc`) is not
  in the save file; add it from the hierarchy if wanted.
