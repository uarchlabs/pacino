<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd02_steady: Steady-State Prediction and Fetch
```
 FILE:    fd02_steady.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd02_steady` (FD-2) runs 2 KB of straight-line code. There are no branches,
therefore every uBTB lookup will miss. Consequently the p1 prediction address
returned is the fall-through address, the lookup PC + 32 bytes returned in p1
on `bpu_pred_pft_p1`.

In this scenario the FTQ allocates one entry per cycle. The front end reaches
steady state at cyc 20, when decode begins delivering eight instructions per
cycle.

The simulation executes 513 instructions, 512 `addi` and the halt `jal`. Once
these instructions have retired the front end fetches for 100 more cycles, and
the simulation finishes.

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                  |
  |--------------------|---------------------------------------|
  | This file          | $DEMO/docs/fd02_steady.md             |
  | Program (stimulus) | $DEMO/programs/fd02_steady.svh        |
  | Surfer sucl        | $DEMO/waves/fd02_steady.sucl          |
  | Log                | $DEMO/out/fd02_steady/fd02_steady.log |
  | Waveform           | $DEMO/out/fd02_steady/fd02_steady.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd02_steady.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd02_steady.sucl) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd02_steady
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd02_steady
```

Console output:
```
-I: fd02_steady : PASS : cyc = 84
```

Log file output:
```
-I: fd02_steady: PASS, allocations 83, longest allocation run 83,
    full decode bundles 64, longest bundle run 63, events checked 6 of 6, cyc 84
```

---

## 3. The program

Source: `programs/fd02_steady.svh`, task `prog_fd02`.

The `RESET_VECTOR` parameter is 0x8000_0000.

```
0x8000_0000   addi t0 x 512      32-bit instruction
...           (addi)             2048 bytes in 32B prediction blocks
0x8000_0800   jal x0,0           halt, loop to self
```

---

## 4. Operation

Signal paths are as given in section 6. Event numbers refer to section 5.

### 4.1 Prediction and FTQ allocation

Reset is deasserted at cyc 0 (event 0). No hold condition is active, so
`ftq_pred_val_p0` is asserted and the FTQ issues its first prediction request,
with `ftq_pred_pc_p0` = 0x8000_0000 and `ftq_pred_idx_p0` = 0.[^1]

The BPU returns the p1 prediction at cyc 1 (event 1), with `bpu_pred_val_p1`
asserted. The uBTB lookup misses: `u_bpu.r_ubtb_blk_p1.hit` and
`bpu_pred_slot_p1.[0].slot_valid` are deasserted, and `bpu_pred_pft_p1` is the
lookup PC + 0x20. `u_ftq.w_ok_pred_p1` asserts when `bpu_pred_idx_p1` matches
the outstanding request, and this writes the prediction into the FTQ entry.[^2]

In the same cycle, `bpu_pred_pft_p1` drives `ftq_pred_pc_p0` combinationally.
This is the zero-bubble path: the next request is presented in the cycle in
which the current prediction is formed, so no idle cycle separates consecutive
prediction blocks.[^3] As a result, `ftq_pred_pc_p0` increments by 0x20 per
cycle and `u_ftq.w_ok_pred_p1` remains asserted from cyc 1.
`u_ftq.u_npc.w_hold`, `ftq_full`, `u_ftq.w_ok_slot_p2` and `u_ftq.w_ok_slot_p3`
remain deasserted throughout.

### 4.2 Instruction fetch

The FTQ presents entries to the IFU from cyc 3. `ftq_ifu_req_val` and
`ftq_ifu_req_rdy` are asserted, so one block transfers per cycle, with
`ftq_ifu_next_pc` equal to `ftq_ifu_start_pc` + 0x20.

Each block fetch covers 34 bytes: the 32-byte block plus one halfword, for a
32-bit instruction that crosses the block end. A block that starts in the upper
half of a 64-byte L1I line therefore requires two lines, and it reuses the first
if the previous block requested it. Block 0x8000_0000 requests line 0x8000_0000
at cyc 4 and block 0x8000_0020 requests line 0x8000_0040 at cyc 5. Thereafter,
only the upper-half blocks issue requests, so `ifu_l1i_req_val` asserts on odd
cycles from cyc 7. `l1i_ifu_rsp_val` first asserts at cyc 16 and then asserts
every second cycle.[^5]

### 4.3 Delivery to decode

The block at 0x8000_0000 reaches the IBUF at cyc 18 (event 2). `ifu_ibuf_val` is
asserted and `u_ibuf.w_n_pres` is 8, so all eight `tb.pd_out.[i].valid` lanes
are asserted. `tb.dec_ibuf_rdy` is asserted, so `u_ibuf.w_n_pop` is also 8. Each
block passes through the IBUF without accumulating, and `u_ibuf.r_count` remains
0.

No block is delivered at cyc 19, because block 0x8000_0020 also requires line
0x8000_0040, which is returned at cyc 18 and is readable from cyc 19. From
cyc 20 (event 3) through cyc 82, one full bundle is delivered every cycle, with
`tb.pd_out.[0].start_pc` incrementing by 0x20. This is the steady state: one
line every two cycles, at two blocks per line and eight instructions per block,
delivers eight instructions per cycle.

Predecode writes back to the FTQ one cycle after each bundle, with
`ifu_ftq_pdwb_val` asserted and `ifu_ftq_cfi_val` deasserted until the halt.
`u_ftq.w_commit_ptr` advances one entry per cycle from cyc 23.

### 4.4 Halt

Prediction continues past the halt JAL, which has not been trained into the BPU.
`ftq_pred_pc_p0` reaches 0x8000_0800 at cyc 64 and continues along the
fall-through path to 0x8000_0a60.

The halt block reaches decode at cyc 83 (event 4). `u_ibuf.w_n_pres` is 1, so
only lane 0 is valid. At cyc 84 the predecode writeback identifies the JAL:
`ifu_ftq_cfi_val` and `ifu_ftq_mis_val` are asserted, `ifu_ftq_mis_pos` is 0 and
`ifu_ftq_target` is 0x8000_0800. This asserts `u_ftq.w_pd_redir_val`,
`u_ftq.w_redir_val` and `ftq_ifu_flush_val`, and redirects `ftq_pred_pc_p0` to
0x8000_0800.

The last instruction has retired by cyc 84 (event 5), so `tb.dec_ibuf_rdy`
deasserts.[^4]

[^1]: `rtl/core/frontend/ftq/rtl/ftq_npc.sv:306-309`, `:377`
[^2]: `rtl/core/frontend/ftq/rtl/ftq_shadow.sv:204-205`,
      `rtl/core/frontend/ftq/rtl/ftq.sv:576`
[^3]: `rtl/core/frontend/bpu/rtl/bp_cluster.sv:876-878`, `:953`,
      `rtl/core/frontend/ftq/rtl/ftq_npc.sv:356-360`
[^4]: `examples/fe_demo/tb/fe_demo_lib.svh:92-98`,
      `rtl/core/frontend/fe_top/tb/models/fe_tb_backend.svh:463`
[^5]: `rtl/core/frontend/ifu/rtl/ifu_fetch.sv:281`, `:289-293`

---

## 5. Events

| # | cyc | Event                                                                                            | Other                             |
|---|-----|--------------------------------------------------------------------------------------------------|-----------------------------------|
| 0 | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                          | fast init                         |
| 1 | 1   | first p1 prediction the FTQ accepts; one in every cycle from here to the end of the simulation   | uBTB miss, the next 32-byte block |
| 2 | 18  | first full decode bundle, the block at 0x8000_0000: all eight lanes of `pd_out` valid            |                                   |
| 3 | 20  | second full bundle, the block at 0x8000_0020; one full bundle in every cycle from here to cyc 82 |                                   |
| 4 | 83  | the halt block reaches decode, one instruction in lane 0                                         | 0x8000_0800                       |
| 5 | 84  | the last instruction retires                                                                     |                                   |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd02_steady` opens
`waves/fd02_steady.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group         | signal                            | description                                       |
|---------------|-----------------------------------|---------------------------------------------------|
| clock         | `tb.clk`                          | clock                                             |
|               | `tb.rstn`                         | active low reset                                  |
|               | `tb.cyc`                          | cycle number                                      |
| bp_cluster_p0 | `ftq_pred_val_p0`                 | p0 request valid                                  |
|               | `ftq_pred_pc_p0`                  | p0 request PC                                     |
|               | `ftq_pred_idx_p0`                 | p0 request FTQ index                              |
|               | `u_ftq.u_npc.w_hold`              | holds the p0 request                              |
| bp_cluster_p1 | `bpu_pred_val_p1`                 | p1 prediction valid                               |
|               | `bpu_pred_idx_p1`                 | FTQ index of the p1 prediction                    |
|               | `u_bpu.r_ubtb_blk_p1.hit`         | uBTB hit at p1                                    |
|               | `bpu_pred_pft_p1`                 | p1 prediction block end, next halfword after it   |
|               | `bpu_pred_slot_p1.[0].slot_valid` | slot 0 holds a branch                             |
|               | `bpu_pred_slot_p1.[0].br_type`    | slot 0 branch type                                |
|               | `bpu_pred_slot_p1.[0].pos`        | slot 0 halfword position in the prediction block  |
|               | `bpu_pred_slot_p1.[0].taken`      | slot 0 predicted direction                        |
|               | `bpu_pred_slot_p1.[0].target`     | slot 0 predicted target                           |
|               | `bpu_pred_slot_p1.[0].pred_src`   | slot 0 predictor that supplied the direction      |
| ftq           | `u_ftq.w_ok_pred_p1`              | the FTQ accepts the p1 prediction                 |
|               | `u_ftq.w_ok_slot_p2`              | the FTQ accepts the p2 group                      |
|               | `u_ftq.w_ok_slot_p3`              | the FTQ accepts the p3 group                      |
|               | `u_ftq.w_ok_redir_p2`             | a live p2 request matches the redirect index      |
|               | `u_ftq.w_ok_redir_p3`             | a live p3 request matches the redirect index      |
|               | `u_ftq.w_redir_val`               | a redirect the FTQ takes                          |
|               | `u_ftq.w_redir_idx`               | FTQ index of the redirect                         |
|               | `u_ftq.w_commit_ptr`              | FTQ commit pointer                                |
|               | `ftq_full`                        | FTQ full                                          |
|               | `ftq_empty`                       | FTQ empty                                         |
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
| ifu_l1i       | `ifu_l1i_req_val`                 | IFU request to the L1I                            |
|               | `ifu_l1i_req_rdy`                 | the L1I takes the request                         |
|               | `ifu_l1i_req_id`                  | request id                                        |
|               | `ifu_l1i_req_paddr`               | physical address of the requested line            |
|               | `ifu_l1i_req_uncached`            | the request is uncached                           |
|               | `l1i_ifu_rsp_val`                 | L1I response                                      |
|               | `l1i_ifu_rsp_id`                  | id of the request answered                        |
| ifu_f3        | `ifu_ftq_pdwb_val`                | predecode writeback to the FTQ                    |
|               | `ifu_ftq_pdwb_idx`                | FTQ index of the writeback                        |
|               | `ifu_ftq_cfi_val`                 | the writeback reports a control transfer          |
|               | `ifu_ftq_cfi_pos`                 | halfword position of the control transfer         |
|               | `ifu_ftq_mis_val`                 | the writeback reports a mispredict position       |
|               | `ifu_ftq_mis_pos`                 | the mispredict position                           |
|               | `ifu_ftq_target`                  | the corrected target                              |
|               | `u_ftq.w_pd_redir_val`            | predecode redirect                                |
| ibuf          | `ifu_ibuf_val`                    | the IFU offers a block to the instruction buffer  |
|               | `ifu_ibuf_en`                     | per-lane mask of the slots offered                |
|               | `ibuf_ifu_rdy`                    | the instruction buffer takes the block            |
|               | `u_ibuf.r_count`                  | instruction buffer occupancy                      |
|               | `u_ibuf.w_n_pres`                 | slots presented to decode                         |
|               | `u_ibuf.w_n_pop`                  | slots taken by decode                             |
| decode        | `tb.dec_ibuf_rdy`                 | the backend model takes the bundle                |
|               | `tb.pd_out.[0].start_pc`          | lane 0 instruction address                        |
|               | `tb.pd_out.[0].valid`             | lane 0 valid                                      |
|               | `tb.pd_out.[1].valid`             | lane 1 valid                                      |
|               | `tb.pd_out.[2].valid`             | lane 2 valid                                      |
|               | `tb.pd_out.[3].valid`             | lane 3 valid                                      |
|               | `tb.pd_out.[4].valid`             | lane 4 valid                                      |
|               | `tb.pd_out.[5].valid`             | lane 5 valid                                      |
|               | `tb.pd_out.[6].valid`             | lane 6 valid                                      |
|               | `tb.pd_out.[7].valid`             | lane 7 valid                                      |
