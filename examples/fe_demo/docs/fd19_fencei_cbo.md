<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd19_fencei_cbo: FENCE.I and cbo.inval
```
 FILE:    fd19_fencei_cbo.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-11-04
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd19_fencei_cbo` (FD-19) demonstrates the two instruction cache maintenance
operations. A FENCE.I invalidates every L1I line, and a cbo.inval invalidates
one line. For each operation, the backend, the IFU and the L1I complete a
handshake, fetch restarts at the next instruction, and the modified code then
runs.

The program calls a function, rewrites it with a store, and calls it again after
a FENCE.I. A second function repeats this with a cbo.inval of its line.

The result line in the log file reports the invalidates of each kind, the
completions, the acknowledgments and the restarts.

This scenario runs in the 1-prediction slot Pacino configuration,
NUM_PRED_SLOTS=1.

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                          |
  |--------------------|-----------------------------------------------|
  | This file          | $DEMO/docs/fd19_fencei_cbo.md                 |
  | Program (stimulus) | $DEMO/programs/fd19_fencei_cbo.svh            |
  | Surfer sucl        | $DEMO/waves/fd19_fencei_cbo.sucl              |
  | Log                | $DEMO/out/fd19_fencei_cbo/fd19_fencei_cbo.log |
  | Waveform           | $DEMO/out/fd19_fencei_cbo/fd19_fencei_cbo.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd19_fencei_cbo.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd19_fencei_cbo.sucl) |
  | Block connectivity | [$DEMO/docs/fe_block.svg](fe_block.svg)       |
  | Pipeline view      | [$DEMO/docs/fe_pipe.svg](fe_pipe.svg)         |
  | Common description | [$DEMO/docs/demo_explainer.md](demo_explainer.md) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd19_fencei_cbo
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd19_fencei_cbo
```

Console output:
```
-I: fd19_fencei_cbo : PASS : cyc = 235
```

Log file output:
```
-I: fd19_fencei_cbo: PASS, whole-cache invalidates 1, line invalidates 1,
    invalidates done 2, maintenance acknowledgments 2,
    restarts at the next instruction 2, events checked 17 of 17, cyc 235
```

The testbench monitor, `tb/fe_demo_mon.svh`, supplies the counts in the log
line.

| Item                              | Counter      | Counted                                                                                           |
|-----------------------------------|--------------|---------------------------------------------------------------------------------------------------|
| whole-cache invalidates           | `n_inv_all`  | `ifu_l1i_inv_val`, `ifu_l1i_inv_rdy` and `ifu_l1i_inv_all`                                        |
| line invalidates                  | `n_inv_line` | `ifu_l1i_inv_val` and `ifu_l1i_inv_rdy`, with `ifu_l1i_inv_all` clear                             |
| invalidates done                  | `n_inv_done` | `l1i_ifu_inv_done`                                                                                |
| maintenance acknowledgments       | `n_mt_ack`   | `ifu_cmt_maint_ack`                                                                               |
| restarts at the next instruction  | `n_restart`  | the first block after an acknowledgment starts at the address after the maintenance instruction   |

---

## 3. The program

The program is written by the task `prog_fd19` in
`programs/fd19_fencei_cbo.svh`.

The code consists of two calls of a function f, a store that rewrites f, a
FENCE.I, and a third call of f. The same sequence follows for a function g, with
a cbo.inval of its line, then a short epilogue.

The program runs in M-mode with bare addressing.

```
Address      Label  Instruction             Purpose
0x8000_0000         c.addi a0, 1            ; prologue
0x8000_0002         addi   t0, t0, 1        ; prologue
0x8000_0006         c.addi a0, 1            ; prologue
0x8000_0008         jal    x1, f            ; first call of f
0x8000_000C         jal    x1, f            ; second call of f
0x8000_0010         c.addi a0, 1            ; filler
0x8000_0012         addi   t0, t0, 1        ; filler
0x8000_0016         sw     x0, 0(a0)        ; rewrites f
0x8000_001A         c.addi a0, 1            ; filler
0x8000_001C         addi   t0, t0, 1        ; filler
0x8000_0020         fence.i                 ; invalidates every line
0x8000_0024         c.addi a0, 1            ; next instruction
0x8000_0026         addi   t0, t0, 1        ; filler
0x8000_002A         jal    x1, f            ; runs the new body of f

0x8000_002E         c.addi a0, 1            ; filler
0x8000_0030         addi   t0, t0, 1        ; filler
0x8000_0034         jal    x1, g            ; first call of g
0x8000_0038         jal    x1, g            ; second call of g
0x8000_003C         sw     x0, 0(a0)        ; rewrites g
0x8000_0040         bne    x6, x0, M        ; taken
0x8000_0046  M:     cbo.inval (a0)          ; invalidates the line of g
0x8000_004A         mixed code              ; next instruction, 60 instructions
0x8000_00EA         jal    x1, g            ; runs the new body of g

0x8000_00EE         c.addi a0, 1            ; epilogue
0x8000_00F0         addi   t0, t0, 1        ; epilogue
0x8000_00F4  hold:  jal    x0, hold         ; termination

0x8000_0800  f:     c.addi a0, 1            ; six in the old body, to 0x080A
0x8000_080C         ret                     ; return

0x8000_0C40  g:     c.addi a0, 1            ; six in the old body, to 0x0C4A
0x8000_0C4C         ret                     ; return
```

The new bodies of f and g are three `addi t1, t1, 1` and the same `ret`.

The cbo.inval names physical address 0x8000_0C64, in the line of g at
0x8000_0C40.

The `c.addi` and `addi` instructions do no useful work. Their purpose is to mix
16-bit and 32-bit instructions and to separate the operations.

A store's rewrite takes effect when the store retires, so memory holds the old
body until then. The directions and targets are chosen by the program writer and
resolved by the modeled backend, and the register operands play no part in them.

---

## 4. Walkthrough

The walkthrough follows the two maintenance operations. Section 4.1 describes
their handshake, section 4.2 the drain, and section 4.3 the effect of each
invalidate.

Cycle numbers below are events in [section 5](#5-events); each event is a marker
in the waveform.

The waveform group `maintenance` contains the handshake, `backend` the
redirects, `ftq_ifu` the blocks, `ifu_l1i` the line requests and memory
requests, and `decode` lane 0 at decode.

### 4.1 The maintenance handshake

When a maintenance instruction retires, the backend stops taking decode's output
and requests the operation.[^1] The IFU passes the invalidate to the L1I.[^2]
The L1I takes no new request, drains, clears the lines and signals done.[^3] The
IFU clears its line buffer and acknowledges, and the backend redirects to the
next instruction.

The FENCE.I clears every set. The cbo.inval clears every way of the set of the
named line.[^4]

| Step                                                                     | FENCE.I           | cbo.inval          |
|--------------------------------------------------------------------------|-------------------|--------------------|
| `tb.cmt_ifu_maint_val` asserted, `tb.cmt_ifu_maint_op`                   | cyc 71, op 0      | cyc 184, op 1      |
| the L1I takes the invalidate, `ifu_l1i_inv_val` and `ifu_l1i_inv_rdy`    | cyc 71 (event 1)  | cyc 184 (event 9)  |
| `u_l1i.u_maint.r_st` 1, M_DRAIN                                          | cyc 72            | cyc 185            |
| `u_l1i.u_maint.r_st` 2, M_CLEAR                                          | cyc 73            | cyc 186            |
| `l1i_ifu_inv_done`                                                       | cyc 74 (event 2)  | cyc 187 (event 10) |
| `tb.ifu_cmt_maint_ack`                                                   | cyc 75 (event 3)  | cyc 188 (event 11) |
| `tb.bkend_ftq_redir_val`, `tb.bkend_ftq_redir_cause` 2, RC_REPLAY        | cyc 77 (event 4)  | cyc 190 (event 12) |
| `tb.bkend_ftq_redir_pc`                                                  | 0x8000_0024       | 0x8000_004A        |
| `ftq_ifu_start_pc` at the next instruction                               | cyc 79 (event 5)  | cyc 192 (event 13) |

`ifu_l1i_inv_all` is 1 at cyc 71. At cyc 184 it is 0, and `ifu_l1i_inv_paddr` is
0x8000_0C64.

The `bne` before the cbo.inval is taken and not predicted.
`tb.bkend_ftq_redir_pc` is 0x8000_0046 at cyc 174 (event 8), with
`tb.bkend_ftq_redir_cause` 0.

### 4.2 The drain

The FENCE.I waits until no MSHR register is in use, and the cbo.inval waits
until no register holds the named line.[^5] Neither waits in this run, so
M_DRAIN lasts one cycle both times.

`u_l1i.mt_busy_any` is 0 at cyc 71. At cyc 184, `u_l1i.mt_busy_any` is 1 and
`u_l1i.mt_busy_line` is 0.

### 4.3 The effect of each invalidate

The FENCE.I clears every line, so later requests miss. `tb.l1i_mem_a_valid` is
asserted with `tb.l1i_mem_a_address` 0x8000_0800 at cyc 77 and 0x8000_0000 at
cyc 82 (event 6). The line at 0x8000_0000 had been requested from memory at
cyc 6.

At cyc 58, `tb.pd_out.[0].start_pc` is 0x8000_0800 with `tb.pd_out.[0].instr`
0x0015_0513, the old body of f. At cyc 106 (event 7), it is 0x8000_0800 with
`tb.pd_out.[0].instr` 0x0013_0313, the new body.

The cbo.inval clears only the set of its line. At cyc 208, `ifu_l1i_req_paddr`
is 0x8000_0C40, and at cyc 210 (event 14) `tb.l1i_mem_a_address` is 0x8000_0C40.
At cyc 209, `ifu_l1i_req_paddr` is 0x8000_0000 with no memory request.

At cyc 159, `tb.pd_out.[0].start_pc` is 0x8000_0C40 with `tb.pd_out.[0].instr`
0x0015_0513, the old body of g. At cyc 222 (event 15), it is 0x8000_0C40 with
`tb.pd_out.[0].instr` 0x0013_0313, the new body.

[^1]: `mt_pend`, `cmt_ifu_maint_val`:
    `rtl/core/frontend/fe_top/tb/models/fe_tb_backend.svh:357-365`, `:463-470`.
    The redirect: `:156-161`.
[^2]: `rtl/core/frontend/ifu/rtl/ifu_maint.sv:58-63`, `:71-75`, `:87-96`.
[^3]: `hold`, `inv_done`: `rtl/core/frontend/icache/rtl/l1i_maint.sv:73-75`.
    M_DRAIN, M_CLEAR: `:96-100`.
[^4]: `rtl/core/frontend/icache/rtl/l1i_maint.sv:25-27`.
[^5]: `busy_any`, `busy_line`:
    `rtl/core/frontend/icache/rtl/l1i_mshr.sv:499-508`.

---

## 5. Events

| #  | cyc | Event                                                                                  | Other                                        |
|----|-----|----------------------------------------------------------------------------------------|----------------------------------------------|
| 0  | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                | fast init                                    |
| 1  | 71  | the FENCE.I reaches the L1I: it takes the invalidate of every line (`ifu_l1i_inv_all`) | `mt_busy_any` 0                              |
| 2  | 74  | first invalidate done (`l1i_ifu_inv_done`)                                             | after M_DRAIN, M_CLEAR                       |
| 3  | 75  | first maintenance acknowledgment (`ifu_cmt_maint_ack`)                                 |                                              |
| 4  | 77  | the restart after the FENCE.I: a backend redirect to 0x8000_0024, cause RC_REPLAY      | backend                                      |
| 5  | 79  | fetch starts at 0x8000_0024, the next instruction                                      | `ftq_ifu_start_pc`                           |
| 6  | 82  | memory request for 0x8000_0000, a miss after the FENCE.I                               | first requested at cyc 6                     |
| 7  | 106 | the new body of f reaches decode: lane 0 at 0x8000_0800, `addi t1`                     | old body at cyc 58                           |
| 8  | 174 | the branch at 0x8000_0040 mispredicted; redirect to 0x8000_0046, the cbo.inval         | backend                                      |
| 9  | 184 | the cbo.inval reaches the L1I: it takes the invalidate of line 0x8000_0C40             | `mt_busy_line` 0                             |
| 10 | 187 | second invalidate done                                                                 |                                              |
| 11 | 188 | second maintenance acknowledgment                                                      |                                              |
| 12 | 190 | the restart after the cbo.inval: a backend redirect to 0x8000_004A, cause RC_REPLAY    | backend                                      |
| 13 | 192 | fetch starts at 0x8000_004A, the next instruction                                      |                                              |
| 14 | 210 | memory request for 0x8000_0C40, a miss after the cbo.inval                             | 0x8000_0000 at cyc 209 has no memory request |
| 15 | 222 | the new body of g reaches decode: lane 0 at 0x8000_0C40, `addi t1`                     | old body at cyc 159                          |
| 16 | 235 | the run ends                                                                           |                                              |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd19_fencei_cbo` opens
`waves/fd19_fencei_cbo.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group       | signal                     | description                                       |
|-------------|----------------------------|---------------------------------------------------|
| clock       | `tb.clk`                   | clock                                             |
|             | `tb.rstn`                  | active low reset                                  |
|             | `tb.cyc`                   | cycle number                                      |
| backend     | `tb.bkend_ftq_redir_val`   | backend redirect                                  |
|             | `tb.bkend_ftq_redir_idx`   | FTQ index of the backend redirect                 |
|             | `tb.bkend_ftq_redir_pc`    | backend redirect PC                               |
|             | `tb.bkend_ftq_redir_cause` | backend redirect cause                            |
|             | `tb.bkend_ftq_redir_self`  | self flag of the backend redirect                 |
|             | `tb.bkend_ftq_rsv_val`     | resolution from the backend, per slot             |
|             | `tb.bkend_ftq_commit_val`  | commit watermark valid                            |
|             | `tb.bkend_ftq_commit_idx`  | commit watermark FTQ index                        |
| maintenance | `tb.cmt_ifu_maint_val`     | maintenance request from the backend model        |
|             | `tb.cmt_ifu_maint_rdy`     | the IFU takes the request                         |
|             | `tb.cmt_ifu_maint_op`      | operation: 0 FENCE.I, 1 cbo.inval                 |
|             | `tb.cmt_ifu_maint_paddr`   | physical address of a cbo.inval                   |
|             | `u_ifu.u_maint.r_st`       | IFU maintenance state                             |
|             | `ifu_l1i_inv_val`          | IFU invalidate request to the L1I                 |
|             | `ifu_l1i_inv_rdy`          | the L1I takes the invalidate                      |
|             | `ifu_l1i_inv_all`          | invalidate every line                             |
|             | `ifu_l1i_inv_paddr`        | physical address of a line invalidate             |
|             | `u_l1i.u_maint.r_st`       | L1I maintenance state                             |
|             | `u_l1i.mt_busy_any`        | an MSHR register is in use                        |
|             | `u_l1i.mt_busy_line`       | an MSHR register holds the named line             |
|             | `l1i_ifu_inv_done`         | invalidate done                                   |
|             | `tb.ifu_cmt_maint_ack`     | maintenance acknowledgment                        |
| ftq_ifu     | `ftq_ifu_req_val`          | FTQ presents a block to the IFU                   |
|             | `ftq_ifu_req_rdy`          | the IFU takes the block                           |
|             | `ftq_ifu_idx`              | FTQ index of the block                            |
|             | `ftq_ifu_start_pc`         | block start address                               |
|             | `ftq_ifu_next_pc`          | address after the block                           |
|             | `ftq_ifu_taken_val`        | the block holds a predicted-taken transfer        |
|             | `ftq_ifu_taken_pos`        | halfword position of the predicted-taken transfer |
|             | `ftq_ifu_flush_val`        | flush of the blocks younger than the named entry  |
|             | `ftq_ifu_flush_idx`        | FTQ index the flush names                         |
|             | `ftq_ifu_commit_ptr`       | FTQ commit pointer as the IFU sees it             |
| ifu_l1i     | `ifu_l1i_req_val`          | IFU request to the L1I                            |
|             | `ifu_l1i_req_rdy`          | the L1I takes the request                         |
|             | `ifu_l1i_req_id`           | request id                                        |
|             | `ifu_l1i_req_paddr`        | physical address of the requested line            |
|             | `ifu_l1i_req_uncached`     | the request is uncached                           |
|             | `l1i_ifu_rsp_val`          | L1I response                                      |
|             | `l1i_ifu_rsp_id`           | id of the request answered                        |
|             | `tb.l1i_mem_a_valid`       | L1I request to memory                             |
|             | `tb.l1i_mem_a_address`     | address of the memory request                     |
| decode      | `tb.dec_ibuf_rdy`          | the backend model takes the bundle                |
|             | `tb.pd_out.[0].valid`      | lane 0 valid                                      |
|             | `tb.pd_out.[0].start_pc`   | lane 0 instruction address                        |
|             | `tb.pd_out.[0].instr`      | lane 0 instruction, expanded if compressed        |
