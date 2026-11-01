<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd16_page_cross: A Fetch Block Crossing a Page
```
 FILE:    fd16_page_cross.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd16_page_cross` is the FD-16 demonstration scenario. It is a demo,
not a verification test. A jump lands 16 bytes before the end of a
4 KiB page whose virtual successor is mapped to a non-adjacent physical
page. The fetch block starting there covers both pages, so the IFU
translates it twice and requests one line from each physical page; a
32-bit instruction straddles the boundary. The run passes if a
translation-queue entry is popped with two translations of different
PPNs.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                          |
  |--------------------|-----------------------------------------------|
  | This file          | $DEMO/docs/fd16_page_cross.md                 |
  | Program (stimulus) | $DEMO/programs/fd16_page_cross.svh            |
  | Surfer sucl        | $DEMO/waves/fd16_page_cross.sucl              |
  | Log                | $DEMO/out/fd16_page_cross/fd16_page_cross.log |
  | Waveform           | $DEMO/out/fd16_page_cross/fd16_page_cross.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd16_page_cross.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd16_page_cross.sucl) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd16_page_cross
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd16_page_cross
```

Console output:
```
-I: fd16_page_cross : PASS : cyc = 112
```

Log file output:
```
-I: fd16_page_cross: PASS, blocks translated twice 1, events checked 7 of 7,
    cyc 112
```

### 2.1 What the monitor counts

The count comes from `tb/fe_demo_mon.svh:535-539`, sampled every cycle
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

### 2.2 Reading the numbers

- The figure is 1: the program has one crossing block, and the run's
  translation queue shows no other entry popped with `xq_cross` set.
- The monitor also requires the two PPNs to differ, so the count shows
  two translations, not one page's result read twice. Here they are
  0x81000 and 0x81205.
- The program meets FD-16 of `planning/showcase/fe_demo_scenarios.md`
  (a block that starts within 32 bytes of a page end); the proof is
  FD-16's. No departure.

---

## 3. The program

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
  32-bit instruction's two halfwords are written to different physical
  pages (0x8100_0FFE and 0x8120_5000).
- The jump target is 16 bytes before the page end; FD-16 asks for a
  block starting within 32 bytes of it.

---

## 4. Walkthrough

### 4.1 Why the program produces the behavior

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

### 4.2 Reading the waveform

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

---

## 5. Events

| # | cyc | Event                                                                                                                       | Other        |
|---|-----|-----------------------------------------------------------------------------------------------------------------------------|--------------|
| 0 | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                                                     | S-mode, Sv39 |
| 1 | 46  | walk for VPN 0x80010, the first page of the crossing block                                                                  |              |
| 2 | 70  | walk for VPN 0x80011, the second page                                                                                       |              |
| 3 | 93  | L1I request for 0x8100_0FC0, the line of the block's start                                                                  | first page   |
| 4 | 94  | the translation queue entry of the block at 0x8001_0FF0 popped with two translations: `xq_cross` 1, PPN 0x81000 and 0x81205 | counted      |
| 5 | 94  | L1I request for 0x8120_5000, the second page's first line                                                                   | second page  |
| 6 | 112 | the run ends                                                                                                                |              |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd16_page_cross` opens
`waves/fd16_page_cross.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group     | signal                      | description                                       |
|-----------|-----------------------------|---------------------------------------------------|
| clock     | `tb.clk`                    | clock                                             |
|           | `tb.rstn`                   | active low reset                                  |
|           | `tb.cyc`                    | cycle number                                      |
| ftq_ifu   | `ftq_ifu_req_val`           | FTQ presents a block to the IFU                   |
|           | `ftq_ifu_req_rdy`           | the IFU takes the block                           |
|           | `ftq_ifu_idx`               | FTQ index of the block                            |
|           | `ftq_ifu_start_pc`          | block start address                               |
|           | `ftq_ifu_next_pc`           | address after the block                           |
|           | `ftq_ifu_taken_val`         | the block holds a predicted-taken transfer        |
|           | `ftq_ifu_taken_pos`         | halfword position of the predicted-taken transfer |
|           | `ftq_ifu_flush_val`         | flush of the blocks younger than the named entry  |
|           | `ftq_ifu_flush_idx`         | FTQ index the flush names                         |
|           | `ftq_ifu_commit_ptr`        | FTQ commit pointer as the IFU sees it             |
| ifu_xlate | `u_ifu.u_xlate.xq_val`      | translation queue head valid                      |
|           | `u_ifu.u_xlate.xq_pop`      | translation queue pop                             |
|           | `u_ifu.u_xlate.xq_idx`      | FTQ index of the queue entry                      |
|           | `u_ifu.u_xlate.xq_pc`       | block start address of the queue entry            |
|           | `u_ifu.u_xlate.xq_cross`    | the block crosses a page                          |
|           | `u_ifu.u_xlate.xq_ppn0`     | physical page number of the first page            |
|           | `u_ifu.u_xlate.xq_ppn1`     | physical page number of the second page           |
|           | `u_ifu.u_xlate.xq_fault0`   | the first page faulted                            |
|           | `u_ifu.u_xlate.xq_fault1`   | the second page faulted                           |
|           | `u_ifu.u_xlate.xq_uc`       | the page is uncached                              |
| itlb      | `ifu_itlb_req_val`          | IFU lookup in the ITLB                            |
|           | `ifu_itlb_req_rdy`          | the ITLB takes the lookup                         |
|           | `ifu_itlb_vpn`              | virtual page number of the lookup                 |
|           | `itlb_ifu_rsp_val`          | ITLB response                                     |
|           | `itlb_ifu_status`           | ITLB status: 0 hit, 1 miss, 2 fault, 3 reserved   |
|           | `itlb_ifu_ppn`              | physical page number of the response              |
|           | `itlb_ifu_cause`            | fault cause: 1 access, 12 page, 20 guest-page     |
| ifu_l1i   | `ifu_l1i_req_val`           | IFU request to the L1I                            |
|           | `ifu_l1i_req_rdy`           | the L1I takes the request                         |
|           | `ifu_l1i_req_id`            | request id                                        |
|           | `ifu_l1i_req_paddr`         | physical address of the requested line            |
|           | `ifu_l1i_req_uncached`      | the request is uncached                           |
|           | `l1i_ifu_rsp_val`           | L1I response                                      |
|           | `l1i_ifu_rsp_id`            | id of the request answered                        |
| decode    | `tb.dec_ibuf_rdy`           | the backend model takes the bundle                |
|           | `tb.pd_out.[0].valid`       | lane 0 valid                                      |
|           | `tb.pd_out.[0].start_pc`    | lane 0 instruction address                        |
|           | `tb.pd_out.[0].ftq_idx`     | lane 0 FTQ index                                  |
|           | `tb.pd_out.[0].pos`         | lane 0 halfword position in the fetch block       |
|           | `tb.pd_out.[0].instr`       | lane 0 instruction, expanded if compressed        |
|           | `tb.pd_out.[0].is_rvc`      | lane 0 instruction is 16-bit                      |
|           | `tb.pd_out.[0].fault_cause` | lane 0 fetch fault cause                          |
|           | `tb.pd_out.[0].fault_va`    | lane 0 fetch fault virtual address                |
