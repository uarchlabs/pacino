<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd18_uncached: Uncached Fetch
```
 FILE:    fd18_uncached.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-11-04
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd18_uncached` (FD-18) demonstrates fetch from uncached pages:

1. the IFU fetches one instruction per FTQ entry
2. each entry is fetched only after every older entry has committed
3. the L1I answers uncached requests from memory and does not fill the lines

The program runs from a page with PBMT NC, then from a page with PBMT IO.

The result line in the log file reports the uncached requests from each page and
the number of uncached lines filled.

This scenario runs in the 1-prediction slot Pacino configuration,
NUM_PRED_SLOTS=1.

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                          |
  |--------------------|-----------------------------------------------|
  | This file          | $DEMO/docs/fd18_uncached.md                   |
  | Program (stimulus) | $DEMO/programs/fd18_uncached.svh              |
  | Surfer sucl        | $DEMO/waves/fd18_uncached.sucl                |
  | Log                | $DEMO/out/fd18_uncached/fd18_uncached.log     |
  | Waveform           | $DEMO/out/fd18_uncached/fd18_uncached.fst     |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd18_uncached.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd18_uncached.sucl) |
  | Block connectivity | [$DEMO/docs/fe_block.svg](fe_block.svg)       |
  | Pipeline view      | [$DEMO/docs/fe_pipe.svg](fe_pipe.svg)         |
  | Common description | [$DEMO/docs/demo_explainer.md](demo_explainer.md) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd18_uncached
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd18_uncached
```

Console output:
```
-I: fd18_uncached : PASS : cyc = 797
```

Log file output:
```
-I: fd18_uncached: PASS, uncached requests from the NC page 28,
    from the IO page 10, uncached lines filled 0, events checked 11 of 11,
    cyc 797
```

The testbench monitor, `tb/fe_demo_mon.svh`, supplies the counts in the log
line. A request is counted per line requested, not per instruction.

| Item                        | Counter       | Counted                                                                                     |
|-----------------------------|---------------|---------------------------------------------------------------------------------------------|
| requests from the NC page   | `n_uc_req_nc` | `ifu_l1i_req_val`, `ifu_l1i_req_rdy` and `ifu_l1i_req_uncached`, not on PA page 0x81204      |
| requests from the IO page   | `n_uc_req_io` | the same, on PA page 0x81204                                                                |
| uncached lines filled       | `n_uc_alloc`  | `u_l1i.u_mshr.b_fil_valid` for a line on PA page 0x81203 or 0x81204                         |

---

## 3. The program

The program is written by the task `prog_fd18` in `programs/fd18_uncached.svh`.

The code consists of a short prologue, a cacheable page that jumps to the NC
page, code on the NC page with branches, a loop and a function call, and code on
the IO page with a taken branch.

The program runs in S-mode under satp Sv39.

| Page   | Virtual address | Physical address | Type           |
|--------|-----------------|------------------|----------------|
| reset  | 0x8000_0000     | 0x8000_0000      | cacheable      |
| c      | 0x8001_0000     | 0x8100_0000      | cacheable      |
| u      | 0x8001_1000     | 0x8120_3000      | PBMT 1, NC     |
| io     | 0x8001_2000     | 0x8120_4000      | PBMT 2, IO     |

```
Address      Label  Instruction             Purpose
0x8000_0000         c.addi a0, 1            ; prologue
0x8000_0002         addi   t0, t0, 1        ; prologue
0x8000_0006         c.addi a0, 1            ; prologue
0x8000_0008         jal    x0, C            ; to page c

0x8001_0000  C:     c.addi a0, 1            ; filler
0x8001_0002         addi   t0, t0, 1        ; filler
0x8001_0006         c.addi a0, 1            ; filler
0x8001_0008         c.addi a0, 1            ; filler
0x8001_000A         jal    x0, U            ; to page u

0x8001_1010  U:     c.addi a0, 1            ; filler
0x8001_1012         addi   t0, t0, 1        ; filler
0x8001_1016         c.addi a0, 1            ; filler
0x8001_1018         bne    x6, x0, V        ; taken
0x8001_1022  V:     c.addi a0, 1            ; filler
0x8001_1024         addi   t0, t0, 1        ; filler
0x8001_1028         bne    x6, x0, W        ; not taken
0x8001_102C         c.addi a0, 1            ; filler
0x8001_102E  W:     jal    x0, L            ; to the loop

0x8001_1200  L:     c.addi a0, 1            ; loop body
0x8001_1202         addi   t0, t0, 1        ; loop body
0x8001_1206         bne    x6, x0, L        ; three passes
0x8001_120A         c.addi a0, 1            ; filler
0x8001_120C         addi   t0, t0, 1        ; filler
0x8001_1210         jal    x0, D            ; to page c

0x8001_0200  D:     c.addi a0, 1            ; filler
0x8001_0202         addi   t0, t0, 1        ; filler
0x8001_0206         c.addi a0, 1            ; filler
0x8001_0208         jal    x1, fn           ; call on page u
0x8001_020C         c.addi a0, 1            ; return address
0x8001_020E         addi   t0, t0, 1        ; filler
0x8001_0212         jal    x0, I            ; to page io

0x8001_2010  I:     c.addi a0, 1            ; filler
0x8001_2012         addi   t0, t0, 1        ; filler
0x8001_2016         c.addi a0, 1            ; filler
0x8001_2018         bne    x6, x0, J        ; taken
0x8001_2022  J:     c.addi a0, 1            ; filler
0x8001_2024         addi   t0, t0, 1        ; filler
0x8001_2028         jal    x0, E            ; to page c

0x8001_0300  E:     c.addi a0, 1            ; epilogue
0x8001_0302         addi   t0, t0, 1        ; epilogue
0x8001_0306  hold:  jal    x0, hold         ; termination

0x8001_1400  fn:    c.addi a0, 1            ; function body
0x8001_1402         addi   t0, t0, 1        ; function body
0x8001_1406         ret                     ; return to 0x8001_020C
```

The `c.addi` and `addi` instructions do no useful work. Their purpose is to mix
16-bit and 32-bit instructions and to separate the control transfers.

The directions and targets are chosen by the program writer and resolved by the
modeled backend, and the register operands play no part in them. x6 is never
read.

The modeled backend runs in eager mode for this program. It commits the entry of
the last retired instruction without waiting for the next instruction, because
the next instruction waits for that commit.

---

## 4. Walkthrough

The walkthrough follows an uncached instruction through fetch. Section 4.1
describes how a page is marked uncached, section 4.2 the fetch of one
instruction, section 4.3 the requests by instruction, section 4.4 the control
transfers, and section 4.5 the absence of L1I fills.

Cycle numbers below are events in [section 5](#5-events); each event is a marker
in the waveform.

The waveform group `ifu_xlate` contains the translation queue and the page
attributes, `ifu_f3` the end of each block, `ifu_fetch` the commit gate,
`ifu_l1i` the requests, `l1i` the L1I and its memory requests, `backend` the
commits and the redirects, and `decode` lane 0 at decode.

### 4.1 Uncached marking

On an ITLB hit, the translation queue marks a block uncached when its page is
not both cacheable and idempotent.[^1] PBMT NC clears the cacheable attribute,
and PBMT IO clears both.[^2]

`itlb_ifu_pma` bit 0 is the cacheable attribute and bit 3 the idempotent
attribute. It is 1111 for the cacheable page c at cyc 68, 1110 for the NC page
at cyc 110, and 0110 for the IO page at cyc 646.

### 4.2 One instruction at a time

The IFU does not start an uncached block until `ftq_ifu_commit_ptr` equals its
FTQ index.[^3] F3 then delivers only the first instruction of the block and ends
the block there, so the FTQ redirects to the next instruction, which is a new
entry.[^4]

The table shows the instruction at 0x8001_1010, the first on the NC page.

| cyc | Event | Reading                                                                            |
|-----|-------|------------------------------------------------------------------------------------|
| 111 | 1     | `ifu_l1i_req_val` and `ifu_l1i_req_uncached` asserted, `ifu_l1i_req_paddr` 0x8120_3000 |
| 112 |       | `u_l1i.b_mis_valid.[0]` asserted                                                   |
| 113 |       | `tb.l1i_mem_a_valid` asserted, `tb.l1i_mem_a_address` 0x8120_3000                  |
| 121 |       | `tb.l1i_mem_d_valid` asserted, also at cyc 122                                     |
| 123 |       | `l1i_ifu_rsp_val` asserted                                                         |
| 125 |       | `tb.pd_out.[0].start_pc` 0x8001_1010                                               |
| 126 | 2     | `ifu_ftq_uc_end` and `ifu_ftq_mis_val` asserted, `u_ftq.w_pd_redir_pc` 0x8001_1012 |
| 128 |       | `tb.bkend_ftq_commit_idx` 2                                                        |
| 129 | 3     | `ftq_ifu_commit_ptr` 3, `u_ifu.u_fetch.w_uc_gate` asserted, `ftq_ifu_start_pc` 0x8001_1012 |
| 130 |       | the next request, `ifu_l1i_req_paddr` 0x8120_3000                                  |

The next instruction therefore starts 19 cycles after the previous one. The IO
page behaves the same way: requests at cyc 647 (event 8) and 666.

### 4.3 Requests by instruction

An instruction in the lower half of a line requests that line alone. An
instruction in the upper half also requests the next line.[^5] At cyc 193,
`ifu_l1i_req_paddr` is 0x8120_3000 with `ifu_l1i_req_id` 0, and at cyc 194 it is
0x8120_3040 with `ifu_l1i_req_id` 1, for the instruction at 0x8001_1022.

The 28 requests from the NC page are for 24 instructions:

| Addresses                  | Instructions | Requests | First                 |
|----------------------------|--------------|----------|-----------------------|
| 0x8001_1010 to 0x8001_102E | 9            | 14       | cyc 111 (event 1)     |
| 0x8001_1200 to 0x8001_1210 | 12           | 11       | cyc 306 (event 4)     |
| 0x8001_1400 to 0x8001_1406 | 3            | 3        | cyc 555 (event 6)     |

The 10 requests from the IO page are for 7 instructions, the last at cyc 772
(event 9).

The loop has one instruction with no request. On the third pass, the block at
0x8001_1200 follows the predicted-taken `bne` with no redirect, and the previous
request was for the same line. At cyc 427 (event 5), `u_ifu.u_fetch.w_reuse0` is
asserted with no `ifu_l1i_req_val`, and `tb.pd_out.[0].start_pc` is 0x8001_1200
at cyc 429.[^6]

### 4.4 Control transfers

A conditional branch ends its block like any other instruction, at the
sequential address. At cyc 183, `u_ftq.w_pd_redir_pc` is 0x8001_101C for the
`bne` at 0x8001_1018. The backend then corrects the path, with
`tb.bkend_ftq_redir_pc` 0x8001_1022 at cyc 189.

A `jal` redirects at predecode to its target. At cyc 298, `ifu_ftq_mis_val` is
asserted without `ifu_ftq_uc_end`, and `u_ftq.w_pd_redir_pc` is 0x8001_1200.

A `ret` is delivered alone with no predecode redirect, because only the backend
knows its target. At cyc 608 (event 7), `ifu_ftq_pdwb_val` is asserted with
`ifu_ftq_mis_val` and `ifu_ftq_uc_end` clear, and `tb.bkend_ftq_redir_pc` is
0x8001_020C at cyc 611.

### 4.5 No L1I fills

An uncached access is a miss whatever the tags hold, and the MSHR register it
takes is marked not to allocate.[^7] At cyc 316 and 317, `tb.l1i_mem_d_valid` is
asserted for the line at 0x8120_3200 with `u_l1i.u_mshr.b_fil_valid` clear.
Fills in this run are for the cacheable pages, for example from cyc 38 for the
reset page.

[^1]: `w_rsp_res.uc`: `rtl/core/frontend/ifu/rtl/ifu_xlate.sv:226`. `xq_uc`:
    `:324`.
[^2]: `rtl/mmu/pmp/rtl/pmp_pma_chk.sv:234-235`.
[^3]: `w_uc_gate`: `rtl/core/frontend/ifu/rtl/ifu_fetch.sv:278`.
[^4]: `w_uc_cut`, `w_uc_end`: `rtl/core/frontend/ifu/rtl/ifu_f3.sv:368-373`. The
    writeback: `:421-431`. The rule is described at `:94-114`.
[^5]: `w_two`: `rtl/core/frontend/ifu/rtl/ifu_fetch.sv:281`.
[^6]: `w_reuse0`: `rtl/core/frontend/ifu/rtl/ifu_fetch.sv:289`.
[^7]: `c_miss`: `rtl/core/frontend/icache/rtl/l1i_ctrl.sv:229-230`. `e_alloc`:
    `rtl/core/frontend/icache/rtl/l1i_mshr.sv:486`. `fil_alloc`: `:350-360`.

---

## 5. Events

| #  | cyc | Event                                                                                                                               | Other               |
|----|-----|-------------------------------------------------------------------------------------------------------------------------------------|---------------------|
| 0  | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                                                             | S-mode, Sv39        |
| 1  | 111 | first uncached request: the first block on page u asks the L1I for line 0x8120_3000 (`ifu_l1i_req_uncached`)                        | NC page             |
| 2  | 126 | first uncached block closed after one instruction: F3 ends it (`ifu_ftq_uc_end`), and the next entry starts at the next instruction |                     |
| 3  | 129 | the commit gate opens for the next block: `ftq_ifu_commit_ptr` 3                                                                    | commit at cyc 128   |
| 4  | 306 | first request for 0x8120_3200, the loop at 0x8001_1200                                                                              | NC page             |
| 5  | 427 | third pass of the loop: a block with no new request, reusing the line                                                               | decode at cyc 429   |
| 6  | 555 | first request for 0x8120_3400, the function at 0x8001_1400                                                                          | NC page             |
| 7  | 608 | the `ret` writes back with no predecode redirect                                                                                    | redirect at cyc 611 |
| 8  | 647 | first uncached request from the IO page, line 0x8120_4000                                                                           | IO page             |
| 9  | 772 | last uncached request                                                                                                               | the 38th            |
| 10 | 797 | the run ends                                                                                                                        |                     |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd18_uncached` opens
`waves/fd18_uncached.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group     | signal                         | description                                       |
|-----------|--------------------------------|---------------------------------------------------|
| clock     | `tb.clk`                       | clock                                             |
|           | `tb.rstn`                      | active low reset                                  |
|           | `tb.cyc`                       | cycle number                                      |
| ftq_ifu   | `ftq_ifu_req_val`              | FTQ presents a block to the IFU                   |
|           | `ftq_ifu_req_rdy`              | the IFU takes the block                           |
|           | `ftq_ifu_idx`                  | FTQ index of the block                            |
|           | `ftq_ifu_start_pc`             | block start address                               |
|           | `ftq_ifu_next_pc`              | address after the block                           |
|           | `ftq_ifu_taken_val`            | the block holds a predicted-taken transfer        |
|           | `ftq_ifu_taken_pos`            | halfword position of the predicted-taken transfer |
|           | `ftq_ifu_flush_val`            | flush of the blocks younger than the named entry  |
|           | `ftq_ifu_flush_idx`            | FTQ index the flush names                         |
|           | `ftq_ifu_commit_ptr`           | FTQ commit pointer as the IFU sees it             |
| ifu_xlate | `u_ifu.u_xlate.xq_val`         | translation queue head valid                      |
|           | `u_ifu.u_xlate.xq_pop`         | translation queue pop                             |
|           | `u_ifu.u_xlate.xq_idx`         | FTQ index of the queue entry                      |
|           | `u_ifu.u_xlate.xq_pc`          | block start address of the queue entry            |
|           | `u_ifu.u_xlate.xq_cross`       | the block crosses a page                          |
|           | `u_ifu.u_xlate.xq_ppn0`        | physical page number of the first page            |
|           | `u_ifu.u_xlate.xq_ppn1`        | physical page number of the second page           |
|           | `u_ifu.u_xlate.xq_fault0`      | fault of the first page                           |
|           | `u_ifu.u_xlate.xq_fault1`      | fault of the second page                          |
|           | `u_ifu.u_xlate.xq_uc`          | the page is uncached                              |
|           | `itlb_ifu_rsp_val`             | ITLB response                                     |
|           | `itlb_ifu_ppn`                 | physical page number of the response              |
|           | `itlb_ifu_pma`                 | page attributes of the response                   |
| ifu_f3    | `ifu_ftq_pdwb_val`             | predecode writeback to the FTQ                    |
|           | `ifu_ftq_pdwb_idx`             | FTQ index of the writeback                        |
|           | `ifu_ftq_mis_val`              | the writeback reports a mispredict position       |
|           | `ifu_ftq_mis_pos`              | the mispredict position                           |
|           | `ifu_ftq_uc_end`               | F3 ends the uncached block                        |
|           | `u_ftq.w_pd_redir_val`         | predecode redirect                                |
|           | `u_ftq.w_pd_redir_pc`          | predecode redirect PC                             |
| ifu_fetch | `u_ifu.u_fetch.xq_uc`          | the block at fetch is uncached                    |
|           | `u_ifu.u_fetch.w_uc_gate`      | the commit gate on an uncached block              |
|           | `u_ifu.u_fetch.w_reuse0`       | the block reuses the previous line                |
| ifu_l1i   | `ifu_l1i_req_val`              | IFU request to the L1I                            |
|           | `ifu_l1i_req_rdy`              | the L1I takes the request                         |
|           | `ifu_l1i_req_id`               | request id                                        |
|           | `ifu_l1i_req_paddr`            | physical address of the requested line            |
|           | `ifu_l1i_req_uncached`         | the request is uncached                           |
|           | `l1i_ifu_rsp_val`              | L1I response                                      |
|           | `l1i_ifu_rsp_id`               | id of the request answered                        |
| l1i       | `u_l1i.b_rsp_valid.[0]`        | L1I hit response, bank 0                          |
|           | `u_l1i.b_rsp_valid.[1]`        | L1I hit response, bank 1                          |
|           | `u_l1i.b_mis_valid.[0]`        | L1I miss, bank 0                                  |
|           | `u_l1i.b_mis_valid.[1]`        | L1I miss, bank 1                                  |
|           | `u_l1i.u_mshr.mrg_hit`         | the presented request matches a fill in flight    |
|           | `u_l1i.u_mshr.e_val.[0]`       | MSHR register 0 valid                             |
|           | `u_l1i.u_mshr.e_val.[1]`       | MSHR register 1 valid                             |
|           | `u_l1i.u_mshr.e_val.[2]`       | MSHR register 2 valid                             |
|           | `u_l1i.u_mshr.e_val.[3]`       | MSHR register 3 valid                             |
|           | `u_l1i.u_mshr.e_got.[0]`       | MSHR register 0 data arrived                      |
|           | `u_l1i.u_mshr.e_got.[1]`       | MSHR register 1 data arrived                      |
|           | `u_l1i.u_mshr.e_got.[2]`       | MSHR register 2 data arrived                      |
|           | `u_l1i.u_mshr.e_got.[3]`       | MSHR register 3 data arrived                      |
|           | `tb.l1i_mem_a_valid`           | L1I request to memory                             |
|           | `tb.l1i_mem_a_address`         | address of the memory request                     |
|           | `tb.l1i_mem_a_source`          | source id of the memory request                   |
|           | `tb.l1i_mem_d_valid`           | memory response beat                              |
|           | `tb.l1i_mem_d_source`          | source id of the memory response                  |
|           | `u_l1i.u_mshr.b_fil_valid.[0]` | fill written into the array, bank 0               |
|           | `u_l1i.u_mshr.b_fil_valid.[1]` | fill written into the array, bank 1               |
| backend   | `tb.bkend_ftq_redir_val`       | backend redirect                                  |
|           | `tb.bkend_ftq_redir_idx`       | FTQ index of the backend redirect                 |
|           | `tb.bkend_ftq_redir_pc`        | backend redirect PC                               |
|           | `tb.bkend_ftq_redir_cause`     | backend redirect cause                            |
|           | `tb.bkend_ftq_redir_self`      | self flag of the backend redirect                 |
|           | `tb.bkend_ftq_rsv_val`         | resolution from the backend, per slot             |
|           | `tb.bkend_ftq_commit_val`      | commit watermark valid                            |
|           | `tb.bkend_ftq_commit_idx`      | commit watermark FTQ index                        |
| decode    | `tb.dec_ibuf_rdy`              | the backend model takes the bundle                |
|           | `tb.pd_out.[0].valid`          | lane 0 valid                                      |
|           | `tb.pd_out.[0].start_pc`       | lane 0 instruction address                        |
|           | `tb.pd_out.[0].ftq_idx`        | lane 0 FTQ index                                  |
|           | `tb.pd_out.[0].pos`            | lane 0 halfword position in the fetch block       |
|           | `tb.pd_out.[0].instr`          | lane 0 instruction, expanded if compressed        |
|           | `tb.pd_out.[0].is_rvc`         | lane 0 instruction is 16-bit                      |
|           | `tb.pd_out.[0].fault_cause`    | lane 0 fetch fault cause                          |
|           | `tb.pd_out.[0].fault_va`       | lane 0 fetch fault virtual address                |
