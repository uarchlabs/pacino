<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd02_steady: Steady-State Prediction and Fetch
```
 FILE:    fd02_steady.md
 SOURCE:  DOC-002
 STATUS:  WORKING
 UPDATED: 2026-10-15
 CONTACT: Jeff Nye
```

`fd02_steady` is the FD-2 demonstration scenario. It is a demo, not a
verification test. It runs 2 KiB of straight-line code. With no branch
to predict, every uBTB lookup misses, the p1 prediction is the lookup PC
plus one 32-byte block, and the FTQ allocates one entry per cycle on the
zero-bubble path. Once the IBUF is filled, decode delivers eight
instructions per cycle. The run passes if both happen for at least four
consecutive cycles.

A recorded run (DOC-002):

```
DEMO PASS fd02_steady: 83 allocations, longest run 83; 64 full decode
bundles, longest run 63 (cycles 84)
```

---

## 1. The program

Source: `programs/fd02_steady.svh`, task `prog_fd02`.

```
RESET_VECTOR+0x000   addi t0 x 512      32-bit, 2048 bytes, 64 blocks
RESET_VECTOR+0x800   jal x0,0           halt (demo_go -> W.halt)
```

- `W.i32(ADDI_T0)` 512 times: 512 32-bit instructions, 2 KiB, 32 L1I
  lines of 64 bytes, 64 FTB blocks of 32 bytes (`FTB_BLOCK_BYTES = 32`,
  `bp_defines_pkg.sv:171`), 8 instructions per block.
- There is no branch until the halt JAL at `RESET_VECTOR + 0x800`
  (0x80000800).

---

## 2. Why the program produces one block per cycle

1. p1 prediction on a uBTB miss. `rtl/core/frontend/bpu/rtl/
   bp_cluster.sv:862-864`: `w_pft_p1` is `r_ubtb_blk_p1.pft_addr` on a
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

---

## 3. What the monitor counts

The counts come from `tb/fe_demo_mon.svh:360-376`, taken only inside
the `meas` window (out of reset, the backend taking decode's output,
the stream not yet retired).

```
n_alloc         cycles with u_ftq.w_ok_pred_p1 (an FTQ allocation)
max_run_alloc   the longest run of consecutive such cycles
n_dec8          cycles with dec_ibuf_rdy and all SLOTS pd_out[i].valid
max_run_dec8    the longest run of consecutive such cycles
```

The proof (`tb/fe_demo_proofs.svh:38-43`) is
`max_run_alloc >= 4 && max_run_dec8 >= 4`. `tb_fe_demo.sv` also
requires the whole stream to retire with no errors before it accepts
the proof.

---

## 4. Reading the numbers

- `64 full decode bundles`: every instruction of the 64 code blocks was
  delivered in a full bundle. `longest run 63`: the one break is cycle
  19, after the first bundle (from the FST).
- `83 allocations, longest run 83`: an allocation on every measured
  cycle but one. 83 is more than the 65 blocks of the program (64 plus
  the halt block): the FTQ goes on predicting fall-through blocks past
  0x80000800 (0x80000820 onward) until the halt JAL is found, and at
  cycle 84 `ftq_pred_pc_p0` returns to 0x80000800 (from the FST). Those
  entries are counted as allocations although they are not on the
  retired path.
- `cycles 84`: from the release of reset to the last retirement.
- Departure from `planning/showcase/fe_demo_scenarios.md` FD-2: its
  proof reads "consecutive allocations; 8 instructions decoded per cycle
  once the IBUF is filled". As built, the proof is a threshold, four
  consecutive cycles of each; the run reaches 83 and 63. The program
  ("straight-line code with no branches, longer than one line") is as
  specified.

---

## 5. Waveform

The saved views are `waves/fd02_steady.gtkw` (GTKWave, `make view
S=fd02_steady`) and `waves/fd02_steady.sucl` (Surfer, `make sview
S=fd02_steady`). Look at:

- group `bp_cluster_p0`: `ftq_pred_val_p0` high and `ftq_pred_pc_p0`
  advancing by 0x20 per cycle; `ftq_pred_idx_p0` counting.
- group `bp_cluster_p1`: `bpu_pred_val_p1` every cycle,
  `r_ubtb_blk_p1.hit` low, `bpu_pred_pft_p1` the lookup PC + 0x20,
  both `bpu_pred_slot_p1` slots with `slot_valid` low.
- group `ftq`: `w_ok_pred_p1` high cycle after cycle.
- groups `ftq_ifu`, `ifu_l1i`, `ifu_f3`, `ibuf`: the blocks moving
  through the IFU and the IBUF occupancy (`u_ibuf.w_n_pres`).
- group `decode`: all eight `pd_out.[i].valid` high together with
  `dec_ibuf_rdy` from cycle 20.
