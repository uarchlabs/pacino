<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd18_uncached: Uncached Fetch
```
 FILE:    fd18_uncached.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd18_uncached` is the FD-18 demonstration scenario. It is a demo, not
a verification test. Code runs from a page whose Sv39 leaf has PBMT NC,
then from one whose leaf has PBMT IO (DOC-003). The IFU fetches each one
instruction per FTQ entry, each block only after every older entry has
committed, with uncached L1I requests that are answered from memory and
never written into the array. The run passes if the L1I takes uncached
requests from each page and no line of either page is filled into the
L1I.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                      |
  |--------------------|-------------------------------------------|
  | This file          | $DEMO/docs/fd18_uncached.md               |
  | Program (stimulus) | $DEMO/programs/fd18_uncached.svh          |
  | Surfer sucl        | $DEMO/waves/fd18_uncached.sucl            |
  | Log                | $DEMO/out/fd18_uncached/fd18_uncached.log |
  | Waveform           | $DEMO/out/fd18_uncached/fd18_uncached.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd18_uncached.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd18_uncached.sucl) |

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
    from the IO page 10, uncached lines filled 0, events checked 8 of 8, cyc 797
```

### 2.1 What the monitor counts

The counts come from `tb/fe_demo_mon.svh:540-554`, sampled every cycle
while `meas` is set.

```
n_uc_req_nc  ifu_l1i_req_val && ifu_l1i_req_rdy && ifu_l1i_req_uncached,
             with the request's PA page not in io_ppn
             an uncached request the L1I took from the NC page (one per
             line requested)
n_uc_req_io  the same, with the PA page in io_ppn: from the IO page
n_uc_alloc   per bank b: u_l1i.u_mshr.b_fil_valid[b] and the filled
             line's PA page is in W.uc_ppn
             a line of an uncached page written into the array
```

`n_uc_alloc` sums the two banks of a cycle into `n_ucal` and adds the
sum once (DOC-002; it counted a cycle with both banks once before). It
is 0 in this run either way.

The proof (`tb/fe_demo_proofs.svh:144`) is
`n_uc_req_nc > 0 && n_uc_req_io > 0 && n_uc_alloc == 0`.
`tb_fe_demo.sv` also requires the whole stream to retire with no
errors.

### 2.2 Reading the numbers

- `uncached requests from the NC page 28` counts lines requested, not
  instructions. From the run (fst2vcd on
  `out/fd18_uncached/fd18_uncached.fst`, requests with
  `ifu_l1i_req_uncached` taken):
  - 14 for the 9 instructions at u+0x10..u+0x2E: the 4 in the lower
    half of the line request PA 0x8120_3000 alone; the 5 in the upper
    half (u+0x22 onward) request 0x8120_3000 and 0x8120_3040 in
    consecutive cycles (IFU-7);
  - 11 for the 12 instructions at u+0x200..u+0x210 (line
    0x8120_3200). Which instruction was served without a request of
    its own was not traced;
  - 3 for the 3 instructions at u+0x400 (line 0x8120_3400).
- `from the IO page 10`: the 7 instructions at io+0x10..io+0x28. The 4
  in the lower half of the line request PA 0x8120_4000 alone; the 3 in
  the upper half (io+0x22 onward) request 0x8120_4000 and 0x8120_4040
  (IFU-7). The first is at cyc 647.
- The requests are about 19 to 25 cycles apart (cycles 111, 130, 149,
  168, ... in the run): each waits at F0 for the previous entry to
  commit.
- `uncached lines filled 0` is the proof's last term: no fill of a line
  of PA page 0x81203 or 0x81204.
- FD-18 of `planning/showcase/fe_demo_scenarios.md` covers NC and IO
  (DOC-003); the program runs both. The commit gate FD-18's waveform
  names is `w_uc_gate`, in the `ifu_fetch` group with `xq_uc`.

---

## 3. The program

Source: `programs/fd18_uncached.svh`, task `prog_fd18`, ported from
tb_fe_top's `uc_nc`. S-mode under satp Sv39. The pages
(`map4k`, and `map4k_pbmt` at
`rtl/core/frontend/fe_top/tb/models/fe_tb_writer.svh:770`):

```
RESET_VECTOR 0x8000_0000 -> PA 0x8000_0000   cacheable
c            0x8001_0000 -> PA 0x8100_0000   cacheable
u            0x8001_1000 -> PA 0x8120_3000   PBMT 1 (NC)
io           0x8001_2000 -> PA 0x8120_4000   PBMT 2 (IO)
```

```
RESET  mixed(3); jal x0, c
c      mixed(4); jal x0, u+0x10
u+0x10 mixed(3)                   +0x10 +0x12 +0x16
u+0x18 bne (cskip, taken)         to +0x22; +0x1C..+0x21 written dry
u+0x22 mixed(2)                   +0x22 +0x24
u+0x28 bne (cskip, not taken)
u+0x2C c.addi
u+0x2E jal x0, u+0x200
u+0x200 mixed(2); bne x6 at +0x206 back to +0x200, 3 iterations
u+0x20A mixed(2); jal x0, c+0x200 at +0x210
c+0x200 mixed(3); jal x1, u+0x400 at c+0x208 (link c+0x20C)
u+0x400 mixed(2); ret at +0x406
c+0x20C mixed(2); jal x0, io+0x10 at c+0x212
io+0x10 mixed(3)                  +0x10 +0x12 +0x16
io+0x18 bne (cskip, taken)        to +0x22; +0x1C..+0x21 written dry
io+0x22 mixed(2); jal x0, c+0x300 at io+0x28
c+0x300 mixed(2), then jal x0,0 (halt)
```

- 24 instructions execute on page u (derived from the source): 9 at
  u+0x10..u+0x2E, 12 at u+0x200..u+0x210, 3 at u+0x400..u+0x406. 7
  execute on page io, at io+0x10..io+0x28.
- The program records the IO page's PPN in `io_ppn`
  (`tb/fe_demo_mon.svh` line 160), which the monitor uses to split the
  uncached requests between the two pages.
- `map4k_pbmt` with a non-zero PBMT also records the PA and VA pages in
  `uc_ppn` and `uc_vpn` (`fe_tb_writer.svh:774-776`), which the
  monitor reads.
- The program sets the backend's eager mode (`eager = 1'b1`,
  `programs/fd18_uncached.svh:31`). With nothing presented, the backend
  then resolves a branch that ended its block against the block the
  FTQ fetched after it, and commits the entry of the last retired
  instruction (`rtl/core/frontend/fe_top/tb/models/fe_tb_backend.svh:162-191`).

---

## 4. Walkthrough

### 4.1 Why the program produces the behavior

1. Uncached marking. On an ITLB hit the IFU translation queue marks
   the page uncached when its effective attributes are not both
   cacheable and idempotent (`rtl/core/frontend/ifu/rtl/ifu_xlate.sv:226`).
   The ITLB passes the leaf's PBMT to the PMA check
   (`rtl/mmu/itlb/rtl/itlb.sv:420`, `:435`); NC is not cacheable, and IO
   is neither cacheable nor idempotent.
   `xq_uc` carries the mark (`ifu_xlate.sv:324`).
2. The commit gate. F0 does not match an uncached block until
   `commit_ptr` equals its FTQ index (`w_uc_gate`,
   `rtl/core/frontend/ifu/rtl/ifu_fetch.sv:278`, IFU-22). Its requests
   carry `ifu_l1i_req_uncached` (`ifu_fetch.sv:316`).
3. One instruction per entry. F3 delivers only the block's first valid
   instruction; when more would follow (`w_uc_cut`), it ends the block
   there with `mis_val` and `ifu_ftq_uc_end`, so the FTQ redirects to
   the next sequential instruction, a new entry
   (`rtl/core/frontend/ifu/rtl/ifu_f3.sv:368-373`, the writeback at
   lines 421 to 431; the rule is described at `ifu_f3.sv:94-114`). A
   JALR is delivered alone with no redirect.
4. No allocation. An uncached lookup is a miss whatever the tags hold
   (`rtl/core/frontend/icache/rtl/l1i_ctrl.sv:229-230`, L1I-24). A free
   MSHR register taken by an uncached request is marked not to
   allocate (`e_alloc <= !req_uncached`,
   `rtl/core/frontend/icache/rtl/l1i_mshr.sv:486`), and a fill is
   installed only when `fil_alloc` is set (`l1i_mshr.sv:350-360`).

### 4.2 Reading the waveform

The saved view is `waves/fd18_uncached.sucl`, which `make view
S=fd18_uncached` opens in Surfer. Look at:

- `u_xlate.xq_uc` set for the blocks on the two uncached pages, and the
  commit gate `u_fetch.w_uc_gate` opening for each block.
- `ftq_ifu_commit_ptr` reaching each uncached block's `ftq_ifu_idx`
  before its `ifu_l1i_req_val` with `ifu_l1i_req_uncached`.
- each uncached block closing after one instruction, and the next block
  starting at the next instruction (`ftq_ifu_start_pc`). The writeback
  that closes it, `ifu_ftq_mis_val`, is not in this command file;
  `waves/fd10_pd_redirect.sucl` shows it.
- In the l1i group: `b_mis_valid` for each uncached request, an MSHR
  `e_val`, `l1i_mem_a_valid` and `l1i_mem_d_valid`, and no
  `b_fil_valid` for the 0x8120_3xxx or 0x8120_4xxx lines.

---

## 5. Events

| # | cyc | Event                                                                                                                               | Other        |
|---|-----|-------------------------------------------------------------------------------------------------------------------------------------|--------------|
| 0 | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                                                             | S-mode, Sv39 |
| 1 | 111 | first uncached request: the first block on page u asks the L1I for line 0x8120_3000 (`ifu_l1i_req_uncached`)                        | NC page      |
| 2 | 126 | first uncached block closed after one instruction: F3 ends it (`ifu_ftq_uc_end`), and the next entry starts at the next instruction |              |
| 3 | 306 | first request for 0x8120_3200, the loop at u+0x200                                                                                  | NC page      |
| 4 | 555 | first request for 0x8120_3400, the function at u+0x400                                                                              | NC page      |
| 5 | 647 | first uncached request from the IO page, line 0x8120_4000                                                                           | IO page      |
| 6 | 772 | last uncached request                                                                                                               | the 38th     |
| 7 | 797 | the run ends                                                                                                                        |              |

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
|           | `u_ifu.u_xlate.xq_fault0`      | the first page faulted                            |
|           | `u_ifu.u_xlate.xq_fault1`      | the second page faulted                           |
|           | `u_ifu.u_xlate.xq_uc`          | the page is uncached                              |
| ifu_fetch | `u_ifu.u_fetch.xq_uc`          | the block at fetch is uncached                    |
|           | `u_ifu.u_fetch.w_uc_gate`      | the commit gate on an uncached block              |
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
