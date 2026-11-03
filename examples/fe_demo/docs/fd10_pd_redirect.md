<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd10_pd_redirect: Predecode Redirect
```
 FILE:    fd10_pd_redirect.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd10_pd_redirect` (FD-10) runs a chain of 13 JALs to distinct prediction
blocks, in a loop of 3 passes.

On the first pass, neither the uBTB nor the FTB holds any of the JALs, so each
block is predicted to fall through. Predecode at F3 finds the JAL, the IFU
writes the block back with a mispredict position, and the FTQ redirects the p0
request to the JAL's target. Once the predictors hold a block's JAL, that block
needs no predecode redirect.

The FTQ takes 14 predecode redirects in the run. The result line in the log file
reports that count.

This scenario runs in the 1-prediction slot Pacino configuration,
NUM_PRED_SLOTS=1.

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                            |
  |--------------------|-------------------------------------------------|
  | This file          | $DEMO/docs/fd10_pd_redirect.md                  |
  | Program (stimulus) | $DEMO/programs/fd10_pd_redirect.svh             |
  | Surfer sucl        | $DEMO/waves/fd10_pd_redirect.sucl               |
  | Log                | $DEMO/out/fd10_pd_redirect/fd10_pd_redirect.log |
  | Waveform           | $DEMO/out/fd10_pd_redirect/fd10_pd_redirect.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd10_pd_redirect.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd10_pd_redirect.sucl) |
  | Block connectivity | [$DEMO/docs/fe_block.svg](fe_block.svg)         |
  | Pipeline view      | [$DEMO/docs/fe_pipe.svg](fe_pipe.svg)           |
  | Common description | [$DEMO/docs/demo_explainer.md](demo_explainer.md) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd10_pd_redirect
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd10_pd_redirect
```

Console output:
```
-I: fd10_pd_redirect : PASS : cyc = 255
```

Log file output:
```
-I: fd10_pd_redirect: PASS, predecode redirects 14, events checked 12 of 12,
    cyc 255
```

The testbench backend model supplies the count in the log line:

- predecode redirects
    - `n_pd_redir` in `rtl/core/frontend/fe_top/tb/models/fe_tb_be_state.svh`
    - cycles with `u_ftq.w_pd_redir_val` asserted and no backend redirect, while
      the expected instruction stream has not fully retired

---

## 3. The program

The program is written by the task `prog_fd10` in
`programs/fd10_pd_redirect.svh`. The code consists of a short prologue, then a
loop of 3 passes starting at `top`, and a short epilogue.

Each pass runs one `jal` at 0x8000_000A to `T0`, then 12 more through a chain of
blocks. The last of them, in `T11`, goes to 0x8000_0108, where the back edge at
0x8000_010A returns to `top`. The back edge is taken on passes 0 and 1.

The program runs in machine mode with translation off, the addresses are
physical. The program starts at the reset vector, `RESET_VECTOR` = 0x8000_0000
(`bp_defines_pkg.sv`).

```
                                                           Position from
Address      Label  Instruction        Purpose             0x000  0x008
0x8000_0000         c.addi a0, 1       ; prologue          0
0x8000_0002         addi   t0, t0, 1   ; prologue          1
0x8000_0006         c.addi a0, 1       ; prologue          3
0x8000_0008  top:   c.addi a0, 1       ; filler            4      0
0x8000_000A         jal    x0, T0      ; first JAL         5      1

                                                           Position from T(k)
0x8000_0200  T0:    c.addi a0, 1       ; filler            0
0x8000_0202         addi   t0, t0, 1   ; filler            1
0x8000_0206         jal    x0, T1      ; chain JAL         3
                    ...                ; T(k) = 0x8000_0200 + k * 0x60
0x8000_0620  T11:   c.addi a0, 1       ; filler            0
0x8000_0622         addi   t0, t0, 1   ; filler            1
0x8000_0626         jal    x0, 0x108   ; last chain JAL    3

                                                           Position from 0x108
0x8000_0108         c.addi a0, 1       ; filler            0
0x8000_010A         bne    x6, x0, top ; back edge         1
0x8000_010E         c.addi a0, 1       ; epilogue          3
0x8000_0110         addi   t0, t0, 1   ; epilogue          4
0x8000_0114         c.addi a0, 1       ; epilogue          6
0x8000_0116  hold:  jal    x0, hold    ; termination       7
```

A position is the halfword offset of an instruction from the start of its
prediction block. The 32-bit instructions take two positions. Each `T(k)` is
0x60 bytes from the last, so each JAL of the chain is in a different prediction
block.

The `c.addi` and `addi` instructions do no useful work. Their purpose is to mix
16-bit and 32-bit instructions and to separate the branches.

The direction of the back edge is chosen by the program writer and resolved by
the modeled backend, and the register operands play no part in it. The code is
the same on every pass, and only the expected instruction stream changes.

---

## 4. Walkthrough

Cycle numbers below are events in [section 5](#5-events); each event is a
marker in the waveform.

### 4.1 Finding the JALs at F3

A block with no taken slot is predicted to fall through, so `ftq_ifu_taken_val`
is deasserted and the next request is the next sequential block. At F3,
predecode marks each position's control transfer type. The first valid JAL in
the block, before the predicted taken position if there is one, sets the
mispredict position and is written back to the FTQ.[^1]

The FTQ takes a writeback's mispredict position as a predecode redirect, with
the corrected successor as the target.[^2] In the p0 arbiter, a predecode
redirect ranks below a backend redirect and above the p3 and p2 redirects.[^3]
Any redirect flushes the younger blocks in the IFU and rolls back the
history.[^4]

The first pass has the 13 redirects that the JALs give.

```
FTQ index   block   position   target   cyc
0           0x000   5          0x200    19
1           0x200   3          0x260    38
2           0x260   3          0x2C0    50
3           0x2C0   3          0x320    60
4           0x320   3          0x380    71
5           0x380   3          0x3E0    81
6           0x3E0   3          0x440    95
7           0x440   3          0x4A0    105
8           0x4A0   3          0x500    116
9           0x500   3          0x560    129
10          0x560   3          0x5C0    141
11          0x5C0   3          0x620    151
12          0x620   3          0x108    165
```

The first redirect is at cyc 19 (event 1), and the last of the pass at cyc 165
(event 2). In the meantime, the p0 request has run ahead sequentially. At cyc 19
the FTQ is presenting FTQ index 16 to the IFU, and the flush names index 1.

The block at 0x8000_0108 holds the back edge at position 1 and the `hold` JAL at
position 7. The back edge is not known yet, so predecode finds the JAL. Its
redirect to 0x8000_0116 is at cyc 175 (event 3), the same cycle as the backend's
redirect for the back edge to `top` (event 4). The backend redirect wins, so the
monitor does not count this one.

The backend redirect starts the p0 request at `top`, a block start that has not
been seen before, because the first pass started its block at 0x8000_0000. An
FTB entry belongs to one block start, so the `jal` at 0x8000_000A is unknown in
this block. Predecode finds it at position 1, and the 14th counted redirect is
at cyc 186 (event 5). It is the last in the run.

From there on, the JALs are predicted. The uBTB supplies the block at
0x8000_0200 at p1 at cyc 187 (event 6), and the FTB confirms it at p2 at cyc 188
(event 7). The rest of the chain follows in order, to the block at 0x8000_0620
at cyc 203 (event 8). In these blocks the p2 slot agrees with the p1 slot, so
there is no p2 redirect. Pass 2 starts with the block at `top`, predicted at p1
for the first time at cyc 209 (event 9).

The back edge is predicted taken in passes 1 and 2. In pass 2 it falls through,
and the backend redirects to 0x8000_010E at cyc 245 (event 10).

[^1]: `w_m1_val`: `rtl/core/frontend/ifu/rtl/ifu_f3.sv:315-329`. The writeback:
    `rtl/core/frontend/ifu/rtl/ifu_wb.sv:86`.
[^2]: `pd_redir_val`: `rtl/core/frontend/ftq/rtl/ftq_ifu.sv:548-550`.
[^3]: `rtl/core/frontend/ftq/rtl/ftq_npc.sv:316-337`.
[^4]: `ftq_ifu_flush_val`: `rtl/core/frontend/ftq/rtl/ftq_ifu.sv:352`.
    `rollback_val`: `rtl/core/frontend/ftq/rtl/ftq_npc.sv:399`.

### 4.2 The redirect in the waveform

The waveform group `ifu_f3` shows the writeback and the redirect, and `ftq_ifu`
shows the flush and the requests that follow.

At cyc 19 (event 1), `ifu_ftq_pdwb_val` is asserted with `ifu_ftq_pdwb_idx` 0.
`ifu_ftq_mis_val` is asserted with `ifu_ftq_mis_pos` 5, and `ifu_ftq_target` is
0x8000_0200. `u_ftq.w_pd_redir_val` is asserted in the same cycle, with
`u_ftq.w_pd_redir_pc` 0x8000_0200. `ftq_pred_pc_p0` is 0x8000_0200, and
`ftq_ifu_flush_val` is asserted with `ftq_ifu_flush_idx` 1. At cyc 22,
`ftq_ifu_req_val` is asserted with `ftq_ifu_idx` 1 and `ftq_ifu_start_pc`
0x8000_0200.

At cyc 175 (events 3 and 4), `w_pd_redir_val` and `tb.bkend_ftq_redir_val` are
both asserted. `w_pd_redir_pc` is 0x8000_0116 and `tb.bkend_ftq_redir_pc` is
0x8000_0008, and `ftq_pred_pc_p0` follows the backend's redirect.

At cyc 187 (event 6), `u_bpu.r_pc_p1` is 0x8000_0200 and
`u_bpu.r_ubtb_blk_p1.hit` is asserted. `bpu_pred_slot_p1.[0]` is a DIRECT_UNC
with `target` 0x8000_0260 and `pred_src` PRED_UBTB.

At cyc 188 (event 7), `u_bpu.r_pc_p2` is 0x8000_0200 and `bpu_slot_p2.[0]` holds
the JAL at `pos` 3 with `pred_src` PRED_FTB. `ftq_ifu_taken_val` is asserted and
`ftq_ifu_next_pc` is 0x8000_0260. No writeback for this block carries
`ifu_ftq_mis_val`.

During the drain after cyc 255, `w_pd_redir_val` asserts about every 9 cycles
for the `hold` JAL. The monitor does not count these.

---

## 5. Events

| #  | cyc | Event                                                                                                                                                                | Other                            |
|----|-----|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------|
| 0  | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                                                                                              | fast init                        |
| 1  | 19  | first predecode redirect: the jal at top + 2, found at F3, to T(0), 0x8000_0200                                                                                      | pass 0                           |
| 2  | 165 | the 13th predecode redirect: the jal of T(11), to 0x8000_0108                                                                                                        | pass 0                           |
| 3  | 175 | a predecode redirect to 0x8000_0116, the halt's jal fetched past the cold back edge; the backend's redirect takes the next request, so the monitor does not count it | not counted                      |
| 4  | 175 | the back edge mispredicted, cold; redirect to 0x8000_0008                                                                                                            | backend                          |
| 5  | 186 | last predecode redirect: the jal at top + 2 again, to 0x8000_0200, in the block that starts at top                                                                   | pass 1, the 14th counted         |
| 6  | 187 | first chain JAL predicted at p1: the block at 0x8000_0200, from the uBTB                                                                                             | `pred_src` PRED_UBTB             |
| 7  | 188 | first chain JAL predicted at p2: the block at 0x8000_0200, from the FTB                                                                                              | `pred_src` PRED_FTB              |
| 8  | 203 | last chain JAL of pass 1 predicted at p1: the block at 0x8000_0620                                                                                                   | 16 cycles from event 6           |
| 9  | 209 | top's jal first predicted at p1: the block at 0x8000_0008                                                                                                            | pass 2                           |
| 10 | 245 | back edge falls through, a misprediction; redirect to 0x8000_010E                                                                                                    | pass 2, backend                  |
| 11 | 255 | the run ends                                                                                                                                                         | a 100 cycle drain follows, to 355 |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd10_pd_redirect` opens
`waves/fd10_pd_redirect.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group         | signal                            | description                                       |
|---------------|-----------------------------------|---------------------------------------------------|
| clock         | `tb.clk`                          | clock                                             |
|               | `tb.rstn`                         | active low reset                                  |
|               | `tb.cyc`                          | cycle number                                      |
| ftq_ifu       | `ftq_ifu_req_val`                 | FTQ presents a block to the IFU                   |
|               | `ftq_ifu_req_rdy`                 | the IFU takes the block                           |
|               | `ftq_ifu_idx`                     | FTQ index of the block                            |
|               | `ftq_ifu_start_pc`                | block start address                               |
|               | `ftq_ifu_next_pc`                 | address after the block                           |
|               | `ftq_ifu_taken_val`               | the block holds a predicted-taken transfer        |
|               | `ftq_ifu_taken_pos`               | halfword position of the predicted-taken transfer |
|               | `ftq_ifu_flush_val`               | flush of the blocks younger than the named entry  |
|               | `ftq_ifu_flush_idx`               | FTQ index the flush names                         |
|               | `ftq_ifu_commit_ptr`              | FTQ commit pointer as the IFU sees it             |
| ifu_f3        | `ifu_ftq_pdwb_val`                | predecode writeback to the FTQ                    |
|               | `ifu_ftq_pdwb_idx`                | FTQ index of the writeback                        |
|               | `ifu_ftq_cfi_val`                 | the writeback reports a control transfer          |
|               | `ifu_ftq_cfi_pos`                 | halfword position of the control transfer         |
|               | `ifu_ftq_mis_val`                 | the writeback reports a mispredict position       |
|               | `ifu_ftq_mis_pos`                 | the mispredict position                           |
|               | `ifu_ftq_target`                  | the corrected target                              |
|               | `u_ftq.w_pd_redir_val`            | predecode redirect                                |
|               | `u_ftq.w_pd_redir_pc`             | predecode redirect target                         |
| ftq           | `u_ftq.w_ok_pred_p1`              | the FTQ accepts the p1 prediction                 |
|               | `u_ftq.w_ok_slot_p2`              | the FTQ accepts the p2 group                      |
|               | `u_ftq.w_ok_slot_p3`              | the FTQ accepts the p3 group                      |
|               | `u_ftq.w_ok_redir_p2`             | the FTQ accepts the p2 redirect                   |
|               | `u_ftq.w_ok_redir_p3`             | the FTQ accepts the p3 redirect                   |
|               | `u_ftq.w_redir_val`               | a redirect the FTQ takes                          |
|               | `u_ftq.w_redir_idx`               | FTQ index of the redirect                         |
|               | `u_ftq.w_commit_ptr`              | FTQ commit pointer                                |
|               | `ftq_full`                        | FTQ full                                          |
|               | `ftq_empty`                       | FTQ empty                                         |
| bp_cluster_p0 | `ftq_pred_val_p0`                 | p0 request valid                                  |
|               | `ftq_pred_pc_p0`                  | p0 request PC                                     |
|               | `ftq_pred_idx_p0`                 | p0 request FTQ index                              |
|               | `u_ftq.u_npc.w_hold`              | holds the p0 request                              |
| bp_cluster_p1 | `u_bpu.r_pc_p1`                   | p1 prediction block start address                 |
|               | `bpu_pred_val_p1`                 | p1 prediction valid                               |
|               | `bpu_pred_idx_p1`                 | FTQ index of the p1 prediction                    |
|               | `u_bpu.r_ubtb_blk_p1.hit`         | uBTB hit at p1                                    |
|               | `bpu_pred_pft_p1`                 | p1 prediction block end, next halfword after it   |
|               | `bpu_pred_slot_p1.[0].slot_valid` | slot 0 holds a branch                             |
|               | `bpu_pred_slot_p1.[0].br_type`    | slot 0 branch type                                |
|               | `bpu_pred_slot_p1.[0].pos`        | slot 0 halfword position in the prediction block  |
|               | `bpu_pred_slot_p1.[0].taken`      | slot 0 predicted direction                        |
|               | `bpu_pred_slot_p1.[0].target`     | slot 0 predicted target                           |
|               | `bpu_pred_slot_p1.[0].pred_src`   | slot 0 predictor that supplied the prediction     |
| bp_cluster_p2 | `u_bpu.r_pc_p2`                   | p2 prediction block start address                 |
|               | `u_bpu.r_val_p2`                  | p2 valid                                          |
|               | `bpu_slot_val_p2`                 | p2 group valid: p2 valid and an FTB hit           |
|               | `bpu_slot_idx_p2`                 | FTQ index of the p2 group                         |
|               | `u_bpu.w_ftb_valid_p2`            | FTB hit at p2                                     |
|               | `bpu_slot_p2.[0].slot_valid`      | slot 0 holds a branch                             |
|               | `bpu_slot_p2.[0].br_type`         | slot 0 branch type                                |
|               | `bpu_slot_p2.[0].pos`             | slot 0 halfword position in the prediction block  |
|               | `bpu_slot_p2.[0].taken`           | slot 0 predicted direction                        |
|               | `bpu_slot_p2.[0].target`          | slot 0 predicted target                           |
|               | `bpu_slot_p2.[0].pred_src`        | slot 0 predictor that supplied the prediction     |
|               | `bpu_redir_p2.[0].valid`          | p2 redirect from slot 0                           |
|               | `bpu_redir_p2.[0].target_pc`      | p2 redirect target from slot 0                    |
|               | `bpu_redir_idx_p2`                | FTQ index of the p2 redirect                      |
| backend       | `tb.bkend_ftq_redir_val`          | backend redirect valid                            |
|               | `tb.bkend_ftq_redir_pc`           | backend redirect PC                               |
|               | `tb.bkend_ftq_redir_cause`        | backend redirect cause                            |
