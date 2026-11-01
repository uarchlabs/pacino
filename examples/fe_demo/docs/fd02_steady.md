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

`fd02_steady` is the FD-2 demonstration scenario. It is a demo, not a
verification test. It runs 2 KiB of straight-line code. With no branch
to predict, every uBTB lookup misses, the p1 prediction is the lookup PC
plus one 32-byte block, and the FTQ allocates one entry per cycle on the
zero-bubble path. Once the IBUF is filled, decode delivers eight
instructions per cycle. The run passes if both happen for at least four
consecutive cycles.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).

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

### 2.1 What the monitor counts

The counts come from `tb/fe_demo_mon.svh:398-414`, taken only inside
the `meas` window (out of reset, the backend taking decode's output,
the stream not yet retired).

```
n_alloc         cycles with u_ftq.w_ok_pred_p1 (an FTQ allocation)
max_run_alloc   the longest run of consecutive such cycles
n_dec8          cycles with dec_ibuf_rdy and all SLOTS pd_out[i].valid
max_run_dec8    the longest run of consecutive such cycles
```

The proof (`tb/fe_demo_proofs.svh:49-54`) is
`max_run_alloc >= 4 && max_run_dec8 >= 4`. `tb_fe_demo.sv` also
requires the whole stream to retire with no errors before it accepts
the proof.

### 2.2 Reading the numbers

- `full decode bundles 64`: every instruction of the 64 code blocks was
  delivered in a full bundle. `longest bundle run 63`: the one break is
  cyc 19, after the first bundle (from the FST).
- `allocations 83, longest allocation run 83`: an allocation on every
  measured cycle but one. The program has 65 blocks: the 64 of code and
  the halt block. The other allocations are fall-through blocks past 0x80000800
  (0x80000820 onward), which the FTQ goes on predicting until the halt
  JAL is found; at cyc 84 `ftq_pred_pc_p0` returns to 0x80000800 (from
  the FST). Those entries are counted as allocations although they are
  not on the retired path.
- `cyc 84`: from the release of reset to the last retirement.
- Departure from `planning/showcase/fe_demo_scenarios.md` FD-2: its
  proof reads "consecutive allocations; 8 instructions decoded per cycle
  once the IBUF is filled". As built, the proof is a threshold, four
  consecutive cycles of each; the run reaches 83 and 63. The program
  ("straight-line code with no branches, longer than one line") is as
  specified.

---

## 3. The program

Source: `programs/fd02_steady.svh`, task `prog_fd02`.

```
RESET_VECTOR+0x000   addi t0 x 512      32-bit, 2048 bytes, 64 blocks
RESET_VECTOR+0x800   jal x0,0           halt (demo_go -> W.halt)
```

- `W.i32(ADDI_T0)` 512 times: 512 32-bit instructions, 2 KiB, 32 L1I
  lines of 64 bytes, 64 FTB blocks of 32 bytes (`FTB_BLOCK_BYTES = 32`,
  `bp_defines_pkg.sv:173`), 8 instructions per block.
- There is no branch until the halt JAL at `RESET_VECTOR + 0x800`
  (0x80000800).

---

## 4. Walkthrough

### 4.1 Why the program produces one block per cycle

1. p1 prediction on a uBTB miss. `rtl/core/frontend/bpu/rtl/
   bp_cluster.sv:876-878`: `w_pft_p1` is `r_ubtb_blk_p1.pft_addr` on a
   hit and `r_pc_p1 + FTB_BLOCK_BYTES` on a miss. With no branch in the
   code no lookup hits (`r_ubtb_blk_p1.hit` is low on cycles 1 to 84 in
   the FST), so each p1 prediction names the next 32-byte block and
   carries no slot.
2. FTQ acceptance. `rtl/core/frontend/ftq/rtl/ftq_shadow.sv:204-205`:
   `ok_pred_p1` (`w_ok_pred_p1` in `ftq.sv`) is the p1 group valid with
   the stage-1 shadow valid and its pointer matching `bpu_pred_idx_p1`.
3. Next request. `ftq_npc.sv:356-360`, arm 5, "the zero-bubble path":
   with no redirect and `p1_val`, the next p0 PC is the p1 successor,
   so a p0 request issues every cycle. `ftq_pred_val_p0 = ~w_hold`
   (line 377); `u_npc.w_hold` (lines 306-309) and `ftq_full` are low
   on every cycle from 1 to 84 (FST).
4. Decode width. `SLOTS = 8` (`rtl/core/frontend/decode/rtl/
   decode_pkg.sv:21`). A 32-byte block of 32-bit instructions is
   exactly eight instructions, one full `pd_out` bundle.

From the FST: `w_ok_pred_p1` is high from cycle 1 to cycle 84,
`ftq_pred_pc_p0` stepping by 0x20 each cycle. The first full bundle
(block 0x80000000) is at cycle 18; cycle 19 has none; cycles 20 to 82
deliver one full bundle each (blocks 0x80000020 to 0x800007E0). Cycle 83
delivers the halt block, one instruction.

### 4.2 Reading the waveform

The saved view is `waves/fd02_steady.sucl`, which `make view
S=fd02_steady` opens in Surfer. Look at:

- group `bp_cluster_p0`: `ftq_pred_val_p0` high and `ftq_pred_pc_p0`
  advancing by 0x20 per cycle; `ftq_pred_idx_p0` counting.
- group `bp_cluster_p1`: `bpu_pred_val_p1` every cycle,
  `r_ubtb_blk_p1.hit` low, `bpu_pred_pft_p1` the lookup PC + 0x20,
  the one slot, `bpu_pred_slot_p1.[0]`, with `slot_valid` low.
- group `ftq`: `w_ok_pred_p1` high cycle after cycle.
- groups `ftq_ifu`, `ifu_l1i`, `ifu_f3`, `ibuf`: the blocks moving
  through the IFU and the IBUF occupancy (`u_ibuf.w_n_pres`).
- group `decode`: all eight `pd_out.[i].valid` high together with
  `dec_ibuf_rdy` from cyc 20, and `pd_out.[0].start_pc` stepping by 0x20,
  one block per bundle. The group shows the first lane's PC only
  (DOC-006).

---

## 5. Events

| # | cyc | Event                                                                                            | Other                             |
|---|-----|--------------------------------------------------------------------------------------------------|-----------------------------------|
| 0 | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                          | fast init                         |
| 1 | 1   | first p1 prediction the FTQ accepts; one in every cycle from here to the end of the run          | uBTB miss, the next 32-byte block |
| 2 | 18  | first full decode bundle, the block at 0x8000_0000: all eight lanes of `pd_out` valid            |                                   |
| 3 | 20  | second full bundle, the block at 0x8000_0020; one full bundle in every cycle from here to cyc 82 |                                   |
| 4 | 83  | the halt block reaches decode, one instruction in lane 0                                         | 0x8000_0800                       |
| 5 | 84  | the run ends                                                                                     |                                   |

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
|               | `bpu_pred_pft_p1`                 | p1 fetch block end, the first halfword after it   |
|               | `bpu_pred_slot_p1.[0].slot_valid` | slot 0 holds a branch                             |
|               | `bpu_pred_slot_p1.[0].br_type`    | slot 0 branch type                                |
|               | `bpu_pred_slot_p1.[0].pos`        | slot 0 halfword position in the fetch block       |
|               | `bpu_pred_slot_p1.[0].taken`      | slot 0 predicted direction                        |
|               | `bpu_pred_slot_p1.[0].target`     | slot 0 predicted target                           |
|               | `bpu_pred_slot_p1.[0].pred_src`   | slot 0 predictor that supplied the direction      |
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
