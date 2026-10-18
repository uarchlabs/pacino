<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd23_jump_cut: A Jump Behind Two Conditionals
```
 FILE:    fd23_jump_cut.md
 SOURCE:  DOC-006
 STATUS:  WORKING
 UPDATED: 2026-10-17
 CONTACT: Jeff Nye
```

## 1. What the scenario shows

`fd23_jump_cut` is the FD-23 scenario of the front-end demonstration.
A fetch block holds two conditional branches followed by a jump. The
FTB entry for the block records all three. With two prediction slots,
both slots hold the conditionals and no slot is left for the jump.
When both conditionals are predicted not taken, the cluster ends the
block at the jump's address, and the next block, which starts at the
jump, predicts the jump in slot 0 (`planning/arch/fe_decisions.md`
section 10, BP-138). The scenario runs on the two-slot model (`SCEN_2S`
in the `Makefile`). demo_explainer.md describes how a scenario is built
and run, and defines the terms used here.

When the scenario passes, it prints one line. This is the line from a
run on 2026-10-17, the run the cyc values below come from:

```
-I: fd23_jump_cut: PASS, blocks cut at the jump 24,
    the jump predicted in slot 0 of the next block 24, cyc 253
```

The monitor, `tb/fe_demo_mon.svh` lines 598 to 619, counts in the p2
groups the FTQ accepted (`tb.dut.u_ftq.w_ok_slot_p2`):

- blocks cut at the jump, the monitor variable `n_jmp_cut`: a group
  whose two slots are conditionals predicted not taken while the
  cluster's cut, `tb.dut.u_bpu.w_jmp_cut_p2`, is set. The monitor keeps
  the block's end, `tb.dut.bpu_blk_pft_p2`, as the jump's address;
- the jump predicted in slot 0 of the next block, `n_jmp_next`: the
  next accepted group whose block starts at that address,
  `tb.dut.u_bpu.r_pc_p2`, with a jump in slot 0 at position 0,
  predicted taken.

The scenario passes when both counts are greater than zero
(`tb/fe_demo_proofs.svh` line 179) and every instruction the testbench
expects retires without error. On the one-slot model both counts are
0 and the scenario fails. The run took 253 cycles.

---

## 2. The program

The program is written by the task `prog_fd23` in
`programs/fd23_jump_cut.svh`. Between a short prologue and epilogue it
runs a loop of 24 passes. The loop's first block holds the conditionals
C1 and C2, never taken, followed by the jump J to a block at
0x8000_0400 that holds the back edge. The program runs in machine mode
with translation off, so the addresses are physical. It starts at the
reset vector, `RESET_VECTOR` = 0x8000_0000 (`bp_defines_pkg.sv`). The
loop's first instruction, top, is at 0x8000_0008.

```
Address      Label  Instruction              Purpose
0x8000_0000         c.addi a0, 1             prologue filler
0x8000_0002         addi t0, t0, 1           prologue filler
0x8000_0006         c.addi a0, 1             prologue filler
0x8000_0008  top:   c.addi a0, 1             loop body filler
0x8000_000A  C1:    bne x6, x0, 0x8000_0010  never taken
0x8000_000E         c.addi a0, 1             always executed
0x8000_0010  C2:    bne x6, x0, 0x8000_0016  never taken
0x8000_0014         c.addi a0, 1             always executed
0x8000_0016  J:     jal x0, 0x8000_0400      the jump
0x8000_0400         c.addi a0, 1             filler
0x8000_0402         addi t0, t0, 1           filler
0x8000_0406         bne x6, x0, 0x8000_0008  back edge to top
0x8000_040A         c.addi a0, 1             epilogue filler
0x8000_040C         addi t0, t0, 1           epilogue filler
0x8000_0410         c.addi a0, 1             epilogue filler
0x8000_0412         jal x0, 0                jump to itself; the run
                                             ends here
```

In the block that starts at top, C1 is at halfword position 1, C2 at
position 4 and J at position 7. The back edge is taken on passes 0 to
22 and falls through on pass 23. The program writer writes the loop
body once per pass at the same addresses, so the code in memory does
not change (demo_explainer.md, section 2); x6 is never read.

---

## 3. Walkthrough

### 3.1 No slot for the jump

The FTB entry for a block holds up to `NUM_PRED_SLOTS` conditional
fields and one jump field. At p2 the cluster places each conditional
field in its slot and the jump in the lowest slot that holds no
conditional (`p2_class_comb`, `rtl/core/frontend/bpu/rtl/bp_cluster.sv`
lines 1015 to 1038). The block at top fills both conditional fields,
so the jump is placed in no slot. The cluster marks this as the cut,
`w_jmp_cut_p2`: the FTB answered, it holds a jump, and every slot holds
a conditional (lines 1044 to 1047).

### 3.2 The block ends at the jump

When the cut is set, the block's fall-through, the address fetch
continues at when no slot is taken, is the jump's address,
`w_jmp_pc_p2`, the block's start plus the jump's position
(`p2_succ_comb`, lines 1107 and 1108; `w_jmp_pc_p2` at lines 1201 and
1202). It leaves the cluster as `bpu_blk_pft_p2`. Before BP-138 the
fall-through was the address after the jump, so a block whose
conditionals were not taken stepped over a jump it never predicted.

In the waveform, the first accepted p2 group of the block at top with both
conditionals predicted not taken is at cyc 89. In the `bp_cluster_p2_ftb` group,
`tb.dut.u_bpu.r_pc_p2` is 0x8000_0008. The FTB answer holds both conditional
fields (`w_ftb_br_valid_p2.[0]` and `.[1]`) and the jump (`w_ftb_jmp_valid_p2`).
`w_jmp_cut_p2` is 1, and `tb.dut.bpu_blk_pft_p2` is 0x8000_0016, J's address. In
the `bp_cluster_p2` group, `tb.dut.bpu_slot_p2.[0]` is C1 and `.[1]` is C2, both
COND, not taken.

### 3.3 The next block predicts the jump

The next block starts at 0x8000_0016. The FTB's window for that start
sees J first, so the cluster places it in slot 0 at position 0 (the
comment above `w_pft_p2`, `bp_cluster.sv` lines 1093 to 1103). At cyc
90, `r_pc_p2` is 0x8000_0016 and
`tb.dut.bpu_slot_p2.[0]` is DIRECT_UNC at `pos` 0, taken, with
`target` 0x8000_0400 and `pred_src` PRED_FTB.

The uBTB learns the shorter block too. From cyc 61 its p1 prediction
for top, `tb.dut.bpu_pred_pft_p1`, is 0x8000_0016, so p1 and p2 agree
and no p2 redirect is needed for the cut. Earlier, from cyc 44, the
cut is made at p2 while the conditionals are still predicted taken,
and those groups raise p2 redirects; the monitor does not count them.

RTL: the cut and the jump address are `w_jmp_cut_p2` and `w_jmp_pc_p2`
in `bp_cluster.sv`; the monitor is `tb/fe_demo_mon.svh` lines 598 to
619.

---

## 4. Events

| cyc | Event                                           | Other            |
|-----|-------------------------------------------------|------------------|
| 0   | reset released (`tb.rstn`); the FTQ requests    | fast init        |
|     | 0x8000_0000 the same cycle                      |                  |
| 19  | predecode redirect to 0x8000_0400: J found at   | pass 0           |
|     | F3, not yet known to the predictors             |                  |
| 40  | first backend misprediction, the back edge;     | pass 0           |
|     | redirect to 0x8000_0008                         |                  |
| 44  | first cut at p2, the block at top; C1 still     | p2 redirect      |
|     | predicted taken                                 |                  |
| 48  | first p2 group at 0x8000_0016: J in slot 0,     | PRED_FTB         |
|     | taken, to 0x8000_0400                           |                  |
| 55  | C1 mispredicted taken; redirect to 0x8000_000E  | backend          |
| 61  | first p1 prediction for top ending at           | uBTB             |
|     | 0x8000_0016                                     |                  |
| 89  | first cut with C1 and C2 predicted not taken;   | counted          |
|     | `bpu_blk_pft_p2` 0x8000_0016                    |                  |
| 90  | the next block, at 0x8000_0016, predicts J in   | counted          |
|     | slot 0                                          |                  |
| 243 | back edge falls through, a misprediction;       | pass 23          |
|     | redirect to 0x8000_040A                         |                  |
| 253 | the run ends                                    |                  |
