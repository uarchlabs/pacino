<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd17_rvc: Compressed and Unaligned Code
```
 FILE:    fd17_rvc.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd17_rvc` is the FD-17 demonstration scenario. It is a demo, not a
verification test. Straight-line code of mixed 16- and 32-bit
instructions places a 32-bit instruction at the last halfword of a
32-byte block. The IFU delivers it whole from the block's 17th halfword,
and the next block starts on its tail. A loop of compressed control
transfers then runs from block starts that are not 32-byte aligned. The
run passes if the straddling instruction reaches retirement whole and
16-bit instructions retire.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                            |
  |--------------------|---------------------------------|
  | This file          | $DEMO/docs/fd17_rvc.md          |
  | Program (stimulus) | $DEMO/programs/fd17_rvc.svh     |
  | Surfer sucl        | $DEMO/waves/fd17_rvc.sucl       |
  | Log                | $DEMO/out/fd17_rvc/fd17_rvc.log |
  | Waveform           | $DEMO/out/fd17_rvc/fd17_rvc.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd17_rvc.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd17_rvc.sucl) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd17_rvc
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd17_rvc
```

Console output:
```
-I: fd17_rvc : PASS : cyc = 198
```

Log file output:
```
-I: fd17_rvc: PASS, straddling 32-bit instructions delivered whole 1,
    16-bit instructions 98, events checked 5 of 5, cyc 198
```

### 2.1 What the monitor counts

Both counts are taken in `be_retire_hook` (`tb/fe_demo_mon.svh:324-329`)
as each expected instruction retires, while `meas` is set.

```
n_straddle   no fault, !is_rvc, pos == 15, and the packet's instr equals
             the expected (expanded) encoding: a 32-bit instruction in
             the last halfword of its block, delivered whole
n_rvc        no fault, is_rvc: a 16-bit instruction retired
```

The proof (`tb/fe_demo_proofs.svh:138`) is
`n_straddle > 0 && n_rvc > 0`. `tb_fe_demo.sv` also requires the whole
stream to retire with no errors.

### 2.2 Reading the numbers

- `straddling 32-bit instructions delivered whole 1` is the
  instruction at +0x3E (seen at cycle 21, section 4.1).
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

## 3. The program

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

## 4. Walkthrough

### 4.1 Why the program produces the behavior

1. The 17-halfword window. F2 selects 17 halfwords from the block
   offset (`rtl/core/frontend/ifu/rtl/ifu_fetch.sv:445-448`), from the two
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

### 4.2 Reading the waveform

The saved view is `waves/fd17_rvc.sucl`, which `make view S=fd17_rvc`
opens in Surfer. Look at:

- `ftq_ifu_start_pc` and `ftq_ifu_next_pc`: the blocks +0x20 to +0x40
  and +0x40 to +0x60 at the start of the run.
- `ifu_ibuf_val`, `ifu_ibuf_en` and `ibuf_ifu_rdy`: the blocks entering
  the ibuf.
- `pd_out.[4]` at cycle 21: start_pc 0x8000_003E, pos 15, is_rvc 0.
- In the loop, `pd_out.[i].is_rvc` set on the compressed transfers and
  `pd_out.[0].instr` holding their expansions (jal, beq/bne, jalr). The
  decode group shows the first lane in full and the `is_rvc` of every
  lane; of lane 4 it also shows the PC and position (DOC-006).
- The straddle register, group `ifu_f3_straddle`
  (`u_ifu.u_f3.r_strad_val`, `r_strad_pc`, `r_strad_idx`): set at
  cycle 21 with `r_strad_pc` 0x8000_0040.

---

## 5. Events

| # | cyc | Event                                                                                                                                   | Other              |
|---|-----|-----------------------------------------------------------------------------------------------------------------------------------------|--------------------|
| 0 | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                                                                 | fast init          |
| 1 | 21  | the straddling instruction reaches decode: lane 4, the 32-bit addi at 0x8000_003E, position 15; the straddle register holds 0x8000_0040 | `r_strad_val`      |
| 2 | 22  | the next bundle starts on its tail: lane 0 at 0x8000_0042, position 1                                                                   |                    |
| 3 | 28  | first fetch of fn, 0x8000_0400, after the c.jalr                                                                                        | `ftq_ifu_start_pc` |
| 4 | 198 | the run ends                                                                                                                            |                    |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd17_rvc` opens
`waves/fd17_rvc.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group           | signal                      | description                                       |
|-----------------|-----------------------------|---------------------------------------------------|
| clock           | `tb.clk`                    | clock                                             |
|                 | `tb.rstn`                   | active low reset                                  |
|                 | `tb.cyc`                    | cycle number                                      |
| ftq_ifu         | `ftq_ifu_req_val`           | FTQ presents a block to the IFU                   |
|                 | `ftq_ifu_req_rdy`           | the IFU takes the block                           |
|                 | `ftq_ifu_idx`               | FTQ index of the block                            |
|                 | `ftq_ifu_start_pc`          | block start address                               |
|                 | `ftq_ifu_next_pc`           | address after the block                           |
|                 | `ftq_ifu_taken_val`         | the block holds a predicted-taken transfer        |
|                 | `ftq_ifu_taken_pos`         | halfword position of the predicted-taken transfer |
|                 | `ftq_ifu_flush_val`         | flush of the blocks younger than the named entry  |
|                 | `ftq_ifu_flush_idx`         | FTQ index the flush names                         |
|                 | `ftq_ifu_commit_ptr`        | FTQ commit pointer as the IFU sees it             |
| ifu_f3          | `ifu_ftq_pdwb_val`          | predecode writeback to the FTQ                    |
|                 | `ifu_ftq_pdwb_idx`          | FTQ index of the writeback                        |
|                 | `ifu_ftq_cfi_val`           | the writeback reports a control transfer          |
|                 | `ifu_ftq_cfi_pos`           | halfword position of the control transfer         |
|                 | `ifu_ftq_mis_val`           | the writeback reports a mispredict position       |
|                 | `ifu_ftq_mis_pos`           | the mispredict position                           |
|                 | `ifu_ftq_target`            | the corrected target                              |
|                 | `u_ftq.w_pd_redir_val`      | predecode redirect                                |
| ifu_f3_straddle | `u_ifu.u_f3.r_strad_val`    | straddle register valid                           |
|                 | `u_ifu.u_f3.r_strad_pc`     | address of the held tail                          |
|                 | `u_ifu.u_f3.r_strad_idx`    | FTQ index of the straddle register                |
| ibuf            | `ifu_ibuf_val`              | the IFU offers a block to the instruction buffer  |
|                 | `ifu_ibuf_en`               | per-lane mask of the slots offered                |
|                 | `ibuf_ifu_rdy`              | the instruction buffer takes the block            |
| decode          | `tb.dec_ibuf_rdy`           | the backend model takes the bundle                |
|                 | `tb.pd_out.[0].valid`       | lane 0 valid                                      |
|                 | `tb.pd_out.[0].start_pc`    | lane 0 instruction address                        |
|                 | `tb.pd_out.[0].ftq_idx`     | lane 0 FTQ index                                  |
|                 | `tb.pd_out.[0].pos`         | lane 0 halfword position in the fetch block       |
|                 | `tb.pd_out.[0].instr`       | lane 0 instruction, expanded if compressed        |
|                 | `tb.pd_out.[0].is_rvc`      | lane 0 instruction is 16-bit                      |
|                 | `tb.pd_out.[0].fault_cause` | lane 0 fetch fault cause                          |
|                 | `tb.pd_out.[0].fault_va`    | lane 0 fetch fault virtual address                |
|                 | `tb.pd_out.[4].valid`       | lane 4 valid                                      |
|                 | `tb.pd_out.[4].start_pc`    | lane 4 instruction address                        |
|                 | `tb.pd_out.[4].pos`         | lane 4 halfword position in the fetch block       |
|                 | `tb.pd_out.[4].is_rvc`      | lane 4 instruction is 16-bit                      |
|                 | `tb.pd_out.[1].is_rvc`      | lane 1 instruction is 16-bit                      |
|                 | `tb.pd_out.[2].is_rvc`      | lane 2 instruction is 16-bit                      |
|                 | `tb.pd_out.[3].is_rvc`      | lane 3 instruction is 16-bit                      |
|                 | `tb.pd_out.[5].is_rvc`      | lane 5 instruction is 16-bit                      |
|                 | `tb.pd_out.[6].is_rvc`      | lane 6 instruction is 16-bit                      |
|                 | `tb.pd_out.[7].is_rvc`      | lane 7 instruction is 16-bit                      |
