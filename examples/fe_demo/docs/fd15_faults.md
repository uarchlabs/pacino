<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd15_faults: Page, Access and Guest-Page Fetch Faults
```
 FILE:    fd15_faults.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-11-03
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd15_faults` (FD-15) demonstrates the three fault types reported by instruction
fetch, and their propagation to decode:

1. an instruction page fault, due to an unmapped page
2. an instruction access fault, due to a mapped page whose physical page
   physical memory protection (PMP) denies execute
3. an instruction guest-page fault, due to a guest physical page with no
   second-stage translation

The program makes three indirect jumps to targets that fault. The first two
execute in supervisor mode under single-stage translation. An ecall then
transfers execution to a guest under two-stage translation, for the third.

Each fault is recorded with its prediction block in the IFU, and is reported in
the fault fields of the per-instruction packet, `ifu_pd_pkt_t`, sent to decode
via the IBUF. The backend then redirects to the handler.

The result line in the log file reports the faults that reach decode with the
expected cause and virtual address.

This scenario runs in the 1-prediction slot Pacino configuration,
NUM_PRED_SLOTS=1.

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                  |
  |--------------------|---------------------------------------|
  | This file          | $DEMO/docs/fd15_faults.md             |
  | Program (stimulus) | $DEMO/programs/fd15_faults.svh        |
  | Surfer sucl        | $DEMO/waves/fd15_faults.sucl          |
  | Log                | $DEMO/out/fd15_faults/fd15_faults.log |
  | Waveform           | $DEMO/out/fd15_faults/fd15_faults.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd15_faults.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd15_faults.sucl) |
  | Block connectivity | [$DEMO/docs/fe_block.svg](fe_block.svg) |
  | Pipeline view      | [$DEMO/docs/fe_pipe.svg](fe_pipe.svg)   |
  | Common description | [$DEMO/docs/demo_explainer.md](demo_explainer.md) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd15_faults
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd15_faults
```

Console output:
```
-I: fd15_faults : PASS : cyc = 700
```

Log file output:
```
-I: fd15_faults: PASS, page faults at decode 1, guest-page faults at decode 1,
    access faults at decode 1, events checked 14 of 14, cyc 700
```

The testbench monitor, `tb/fe_demo_mon.svh`, supplies the counts in the log
line. It counts when the backend retires an expected fault entry whose
`fault_cause` and `fault_va` match the expected values.

| Item                     | Counter       | Expected fault       |
|--------------------------|---------------|----------------------|
| page faults at decode    | `n_flt_page`  | IFU_FAULT_PAGE       |
| guest-page faults at decode | `n_flt_guest` | IFU_FAULT_GUEST_PAGE |
| access faults at decode  | `n_flt_acc`   | IFU_FAULT_ACCESS     |

---

## 3. The program

The program is written by the task `prog_fd15` in `programs/fd15_faults.svh`.

The code consists of a short prologue at the reset vector, then three indirect
jumps to targets that fault. The handler of the first fault contains the second
jump. The handler of the second fault executes an ecall to page V, which
contains the third jump. The table gives each target and the listing gives the
code.

The program first executes in S-mode under satp Sv39. PMP entry 0 is a 4 KiB
NAPOT region at 0x8140_0000 with read and write permission and no execute, and
PMP entry 2 grants read, write and execute everywhere. Entry 0 matches first.

| Target      | Translation                                       | Fault      | Handler      |
|-------------|---------------------------------------------------|------------|--------------|
| 0x8040_0010 | nothing mapped                                    | page       | 0x8002_0000  |
| 0x8060_0010 | leaf to 0x8140_0000, denied execute by PMP entry 0 | access     | 0x8002_0040  |
| 0x8080_0010 | VS-stage leaf to GPA 0x2000_0000, no G-stage mapping | guest-page | 0x8005_1000  |

```
Address      Label  Instruction             Purpose
0x8000_0000         c.addi a0, 1            ; prologue
0x8000_0002         addi   t0, t0, 1        ; prologue
0x8000_0006         c.addi a0, 1            ; prologue
0x8000_0008         jal    x0, C            ; to page C

0x8001_0000  C:     c.addi a0, 1            ; filler
0x8001_0002         addi   t0, t0, 1        ; filler
0x8001_0006  J0:    jalr   x0, 0(x7)        ; to 0x8040_0010, page fault

0x8002_0000  H:     c.addi a0, 1            ; handler of the page fault
0x8002_0002         addi   t0, t0, 1        ; filler
0x8002_0006  J1:    jalr   x0, 0(x7)        ; to 0x8060_0010, access fault

0x8002_0040  H1:    c.addi a0, 1            ; handler of the access fault
0x8002_0042         addi   t0, t0, 1        ; filler
0x8002_0046         ecall                   ; to VS-mode at V

0x8005_0000  V:     c.addi a0, 1            ; filler
0x8005_0002         addi   t0, t0, 1        ; filler
0x8005_0006  J2:    jalr   x0, 0(x7)        ; to 0x8080_0010, guest-page fault

0x8005_1000  V1:    c.addi a0, 1            ; handler of the guest-page fault
0x8005_1002         addi   t0, t0, 1        ; epilogue
0x8005_1006         c.addi a0, 1            ; epilogue
0x8005_1008         c.addi a0, 1            ; epilogue
0x8005_100A  hold:  jal    x0, hold         ; termination
```

The three targets contain no code, because their fetches fault. The testbench
compares the fault reported at decode with the expected cause and address. It
also applies the change to guest execution when the ecall retires, in place of
the trap to machine mode and the return that software would execute.

The `c.addi` and `addi` instructions do no useful work. Their purpose is to mix
16-bit and 32-bit instructions and to separate the control transfers.

The directions and targets are chosen by the program writer and resolved by the
modeled backend, and the register operands play no part in them. x7 is never
read.

The run has no accepted p2 slot groups, because no block repeats and the FTB
therefore never hits.

---

## 4. Walkthrough

The walkthrough follows each faulting fetch. Sections 4.1, 4.2 and 4.3 describe
how each fault arises, and section 4.4 describes the path that all three take to
decode. [fd14_translation](fd14_translation.md#4-walkthrough) section 4 defines
the RISC-V translation terms.

Each `jalr` is mispredicted at its first execution, because no target is known,
so the backend redirects to the target, and the fetch of the target then faults.

Cycle numbers below are events in [section 5](#5-events); each event is a marker
in the waveform. A signal the testbench drives, such as
`tb.bkend_ftq_redir_val`, changes one time unit after the clock edge, so the
waveform first shows the new value at the marker of the next cycle.

The waveform group `itlb` contains the IFU lookups, `walker` the walks,
`ifu_xlate` the translation queue, `ifu_fault` the fault report to the FTQ,
`decode` lane 0 at decode, and `backend` the redirects.

### 4.1 Instruction page fault

The walk for page 0x8040_0000 starts at cyc 90 (event 1) and answers a fault at
cyc 104 (event 2), because nothing is mapped. The ITLB does not install a fault.
It holds the fault in its tracker and answers the re-request with it.[^1] A
later lookup of the page therefore walks again, which it does at cyc 107.

At cyc 90 (event 1), `tb.itlb_l2t_req_val` and `tb.itlb_l2t_req_rdy` are
asserted with `tb.itlb_l2t_vpn` 0x80400 and `tb.itlb_l2t_v` 0. At cyc 104
(event 2),
`tb.l2t_itlb_rsp_val` is asserted with `tb.l2t_itlb_status` 1 and
`tb.l2t_itlb_cause` 12.

### 4.2 Instruction access fault

The walk for page 0x8060_0000 starts at cyc 166 (event 5) and answers a hit at
cyc 187 (event 6), because the page has a valid leaf. The ITLB checks every
translation against PMP and PMA for execute access at the effective privilege,
and answers a hit that fails as a fault with the access cause, at cyc 188
(event 7).[^2] PMP entry 0 matches the physical page and has execute clear.

At cyc 187 (event 6), `tb.l2t_itlb_rsp_val` is asserted with
`tb.l2t_itlb_status` 0 and `tb.l2t_itlb_ppn` 0x81400. At cyc 188 (event 7),
`itlb_ifu_rsp_val` is asserted with `itlb_ifu_status` 2 and `itlb_ifu_cause` 1.

### 4.3 Instruction guest-page fault

The ecall's trap redirect to V is at cyc 202 (event 9). As in fd14, a younger
fetch on the wrong path is translated with V=1 first: the walk for page H starts
at cyc 201 and answers a fault at cyc 278 that nothing delivers. The walk for
page V then runs from cyc 280 to 377.

The walk for page 0x8080_0000 starts at cyc 399 (event 10). The VS-stage leaf
gives the guest physical address 0x2000_0000, which the G-stage does not map. A
G-stage page fault is a guest-page fault, so the walker answers cause 20 at cyc
490 (event 11).[^3] The ITLB handles it as in section 4.1, and the page is
walked again at cyc 493.

At cyc 399 (event 10), `tb.itlb_l2t_req_val` and `tb.itlb_l2t_req_rdy` are
asserted with `tb.itlb_l2t_vpn` 0x80800 and `tb.itlb_l2t_v` 1. At cyc 490
(event 11), `tb.l2t_itlb_rsp_val` is asserted with `tb.l2t_itlb_status` 1 and
`tb.l2t_itlb_cause` 20.

### 4.4 Fault propagation to decode

All three faults take the same path, with the same timing from the walker's
answer. The translation queue records the page's fault, `ifu_fetch` requests no
line on a faulting page, and F3 assigns each position its fault, cause and
virtual address and writes them into the packet.[^4]

| Fault      | Walker answers | ITLB answers | Queue entry faulted | Decode | Trap redirect |
|------------|----------------|--------------|---------------------|--------|---------------|
| page       | 104            | 105          | 106                 | 108    | 110           |
| access     | 187            | 188          | 189                 | 191    | 193           |
| guest-page | 490            | 491          | 492                 | 494    | 496           |

At cyc 108 (event 3), `tb.pd_out.[0].valid` is asserted with
`tb.pd_out.[0].start_pc` and `tb.pd_out.[0].fault_va` 0x8040_0010 and
`tb.pd_out.[0].fault_cause` IFU_FAULT_PAGE. At cyc 110 (event 4),
`tb.bkend_ftq_redir_val` is asserted with `tb.bkend_ftq_redir_cause` RC_TRAP and
`tb.bkend_ftq_redir_pc` 0x8002_0000.

At cyc 191 (event 8), `tb.pd_out.[0].start_pc` and `tb.pd_out.[0].fault_va` are
0x8060_0010, with `tb.pd_out.[0].fault_cause` IFU_FAULT_ACCESS.

At cyc 494 (event 12), `tb.pd_out.[0].start_pc` and `tb.pd_out.[0].fault_va` are
0x8080_0010, with `tb.pd_out.[0].fault_cause` IFU_FAULT_GUEST_PAGE and
`tb.pd_out.[0].fault_gpa` 0x2000_0010.

[^1]: The tracker: `rtl/mmu/itlb/rtl/itlb.sv:105-110`. The answer on the
    re-request: `:525-528`.
[^2]: `pmp_pma_chk`: `rtl/mmu/itlb/rtl/itlb.sv:423-441`. The access cause:
    `:517-519`.
[^3]: `rtl/mmu/ptw/rtl/ptw.sv:79`, MMU-22.
[^4]: `xq_fault0`: `rtl/core/frontend/ifu/rtl/ifu_xlate.sv:316`. The requests:
    `rtl/core/frontend/ifu/rtl/ifu_fetch.sv:24`. The per-position fault:
    `rtl/core/frontend/ifu/rtl/ifu_f3.sv:252-279`. The packet: `:391-392`.
    `ifu_fault_e`: `rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv:563-566`.

---

## 5. Events

| #  | cyc | Event                                                                                     | Other                |
|----|-----|-------------------------------------------------------------------------------------------|----------------------|
| 0  | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                   | S-mode, Sv39         |
| 1  | 90  | walk for VPN 0x80400, the first target's page, single-stage                               | nothing mapped       |
| 2  | 104 | the walker answers a page fault, cause 12                                                 | status 1             |
| 3  | 108 | the page fault reaches decode: lane 0 at 0x8040_0010, `fault_cause` IFU_FAULT_PAGE        | `tb.pd_out.[0]`      |
| 4  | 110 | the trap redirect for the page fault, to 0x8002_0000                                      | RC_TRAP, backend     |
| 5  | 166 | walk for VPN 0x80600, the second target's page                                            | a valid leaf         |
| 6  | 187 | the walker answers a hit, PPN 0x81400                                                     | status 0             |
| 7  | 188 | the ITLB answers the access fault: its PMP check refuses the hit                          | status 2, cause 1    |
| 8  | 191 | the access fault reaches decode: lane 0 at 0x8060_0010, IFU_FAULT_ACCESS                  | `tb.pd_out.[0]`      |
| 9  | 202 | the ecall's trap redirect to V, 0x8005_0000                                               | backend              |
| 10 | 399 | walk for VPN 0x80800, the third target's page, with `itlb_l2t_v` 1                        | nested               |
| 11 | 490 | the walker answers cause 20, a guest-page fault: the G-stage does not map GPA 0x2000_0000 | status 1             |
| 12 | 494 | the third fault reaches decode: lane 0 at 0x8080_0010, IFU_FAULT_GUEST_PAGE               | GPA 0x2000_0010      |
| 13 | 700 | the run ends                                                                              |                      |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd15_faults` opens
`waves/fd15_faults.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group     | signal                      | description                                           |
|-----------|-----------------------------|-------------------------------------------------------|
| clock     | `tb.clk`                    | clock                                                 |
|           | `tb.rstn`                   | active low reset                                      |
|           | `tb.cyc`                    | cycle number                                          |
| itlb      | `ifu_itlb_req_val`          | IFU lookup in the ITLB                                |
|           | `ifu_itlb_req_rdy`          | the ITLB takes the lookup                             |
|           | `ifu_itlb_vpn`              | virtual page number of the lookup                     |
|           | `itlb_ifu_rsp_val`          | ITLB response                                         |
|           | `itlb_ifu_status`           | ITLB status: 0 hit, 1 miss, 2 fault, 3 reserved       |
|           | `itlb_ifu_ppn`              | physical page number of the response                  |
|           | `itlb_ifu_cause`            | fault cause: 1 access, 12 page, 20 guest-page         |
| walker    | `tb.itlb_l2t_req_val`       | ITLB request to the walker                            |
|           | `tb.itlb_l2t_req_rdy`       | the walker takes the request                          |
|           | `tb.itlb_l2t_vpn`           | virtual page number of the walk                       |
|           | `tb.itlb_l2t_v`             | the walk is for V=1, two-stage when hgatp is not Bare |
|           | `tb.itlb_l2t_priv`          | privilege of the walk: 0 U, 1 S                       |
|           | `tb.u_ptw.r_st`             | walker state                                          |
|           | `tb.u_ptw.r_g_on`           | G-stage enabled for the walk                          |
|           | `tb.l2t_itlb_rsp_val`       | walker response                                       |
|           | `tb.l2t_itlb_status`        | walker status: 0 hit, 1 fault, 2 retry, 3 reserved    |
|           | `tb.l2t_itlb_ppn`           | physical page number of the walk                      |
|           | `tb.l2t_itlb_cause`         | fault cause: 1 access, 12 page, 20 guest-page         |
| ifu_xlate | `u_ifu.u_xlate.xq_val`      | translation queue head valid                          |
|           | `u_ifu.u_xlate.xq_pop`      | translation queue pop                                 |
|           | `u_ifu.u_xlate.xq_idx`      | FTQ index of the queue entry                          |
|           | `u_ifu.u_xlate.xq_pc`       | block start address of the queue entry                |
|           | `u_ifu.u_xlate.xq_cross`    | the block crosses a page                              |
|           | `u_ifu.u_xlate.xq_ppn0`     | physical page number of the first page                |
|           | `u_ifu.u_xlate.xq_ppn1`     | physical page number of the second page               |
|           | `u_ifu.u_xlate.xq_fault0`   | fault of the first page                               |
|           | `u_ifu.u_xlate.xq_fault1`   | fault of the second page                              |
|           | `u_ifu.u_xlate.xq_uc`       | the page is uncached                                  |
| ifu_fault | `ifu_ftq_fault_val`         | the IFU reports a fetch fault to the FTQ              |
|           | `ifu_ftq_fault_pos`         | halfword position of the fault                        |
| decode    | `tb.dec_ibuf_rdy`           | the backend model takes the bundle                    |
|           | `tb.pd_out.[0].valid`       | lane 0 valid                                          |
|           | `tb.pd_out.[0].start_pc`    | lane 0 instruction address                            |
|           | `tb.pd_out.[0].ftq_idx`     | lane 0 FTQ index                                      |
|           | `tb.pd_out.[0].pos`         | lane 0 halfword position in the fetch block           |
|           | `tb.pd_out.[0].instr`       | lane 0 instruction, expanded if compressed            |
|           | `tb.pd_out.[0].is_rvc`      | lane 0 instruction is 16-bit                          |
|           | `tb.pd_out.[0].fault_cause` | lane 0 fetch fault cause                              |
|           | `tb.pd_out.[0].fault_va`    | lane 0 fetch fault virtual address                    |
|           | `tb.pd_out.[0].fault_gpa`   | lane 0 faulting guest physical address                |
| backend   | `tb.bkend_ftq_redir_val`    | backend redirect                                      |
|           | `tb.bkend_ftq_redir_idx`    | FTQ index of the backend redirect                     |
|           | `tb.bkend_ftq_redir_pc`     | backend redirect PC                                   |
|           | `tb.bkend_ftq_redir_cause`  | backend redirect cause                                |
|           | `tb.bkend_ftq_redir_self`   | self flag of the backend redirect                     |
|           | `tb.bkend_ftq_rsv_val`      | resolution from the backend, per slot                 |
|           | `tb.bkend_ftq_commit_val`   | commit watermark valid                                |
|           | `tb.bkend_ftq_commit_idx`   | commit watermark FTQ index                            |
