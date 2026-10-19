<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd23_jump_cut: A Jump Behind Two Conditionals
```
 FILE:    fd23_jump_cut.md
 SOURCE:  DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. What the scenario shows

`fd23_jump_cut` is the FD-23 scenario of the front-end demonstration.
A fetch block holds two conditional branches followed by a jump. With
two prediction slots an FTB entry holds at most two branches, so when
the jump resolves in that block the FTB splits the entry: it keeps the
two conditionals and ends the block at the jump's address
(`planning/arch/ftb_decisions.md` section 3, BP-140). When both
conditionals are predicted not taken, the block ends at the jump by
the FTB's own stored end, and the next block, which starts at the
jump, predicts the jump in slot 0. The scenario runs on the two-slot
model (`SCEN_2S` in the `Makefile`). demo_explainer.md describes how a
scenario is built and run, and defines the terms used here.

DOC-006 wrote this scenario for the cluster's cut
(`planning/arch/fe_decisions.md` section 10, BP-138 and BP-139), which
ended such a block at the jump when the FTB entry held all three
branches. Since BP-140 no entry the FTB writes holds a branch that no
slot carries, the cut does not fire, and DOC-007 re-pointed the
scenario at the split.

When the scenario passes, it prints one line. This is the line from a
run on 2026-10-19, the run the cyc values below come from:

```
-I: fd23_jump_cut: PASS, blocks the FTB ends at the jump 23,
    the jump predicted in slot 0 of the next block 21,
    blocks cut by the cluster 0, cyc 244
```

The monitor, `tb/fe_demo_mon.svh` lines 602 to 628, counts in the p2
groups the FTQ accepted (`tb.dut.u_ftq.w_ok_slot_p2`):

- blocks the FTB ends at the jump, the monitor variable `n_jmp_end`: a
  group whose two slots are conditionals predicted not taken, whose
  block end, `tb.dut.bpu_blk_pft_p2`, is the jump's address, and in
  which the cluster's cut, `tb.dut.u_bpu.w_cut_p2`, is clear. The
  jump's address is the testbench variable `jmp_pc`
  (`tb/fe_demo_mon.svh` line 153). The program sets it when it writes
  the jump, so the end is checked against the program;
- the jump predicted in slot 0 of the next block, `n_jmp_next`: the
  next accepted group whose block starts at that address,
  `tb.dut.u_bpu.r_pc_p2`, with a jump in slot 0 at position 0,
  predicted taken;
- blocks cut by the cluster, `n_cut`: accepted groups with
  `w_cut_p2` set, reported for information.

The scenario passes when the first two counts are greater than zero
(`tb/fe_demo_proofs.svh` line 180) and every instruction the testbench
expects retires without error. On the one-slot model the counts are
0 and the scenario fails. The run took 244 cycles.

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
not change (demo_explainer.md, section 2); x6 is never read. Before it
writes J, the program sets `jmp_pc` to J's address, 0x8000_0016.

---

## 3. Walkthrough

### 3.1 The FTB entry for top

The FTB keeps one entry per block start. An update for a branch
resolved in a block from that start adds the branch to the entry. When
the entry already holds a branch at that position, the update changes
that branch in place. The entry stores its branches in position order.
An
entry holds at most `NUM_PRED_SLOTS` branches. When an update would
make it hold more, the lowest `NUM_PRED_SLOTS` positions are kept, the
block's end becomes the address of the lowest branch not kept, and a
jump not kept clears the jump field. This is the split
(`rtl/core/frontend/bpu/rtl/ftb_cntrl.sv`, THE UPDATE, lines 464 to
494; the split at lines 592 to 615). The uBTB applies the same rule
(`apply_upd`, `ubtb.sv` lines 291 to 376).

C1 and C2 resolve first: at cyc 52 and 53 the FTB allocates the entry
for top with C1, then adds C2. The entry ends one block above its
start, at 0x8000_0028. At cyc 56 the first p2 group for top predicts
both taken (TAGE's base table starts weakly taken), and the
statistical corrector reverses them at p3, at cyc 57, to the block's
end. J then resolves in a block from top and is the third branch: at
cyc 65, in the `ftb_update` group, `tb.dut.ftb_upd_pc_u0` is
0x8000_0008, `ftb_upd_pos_u0` 7, `ftb_upd_is_jmp_u0` 1, and
`tb.dut.u_bpu.u_ftb.u_ftb_cntrl.upd_split` is 1 with `upd_cut_pos` 7.
The entry keeps C1 and C2 and now ends at position 7, J's address.

### 3.2 The block ends at the jump

At p2 the cluster places each conditional field of the entry in its
slot and the jump field in the lowest slot that holds no conditional
(`p2_class_comb`, `rtl/core/frontend/bpu/rtl/bp_cluster.sv` lines 1010
to 1046). The entry for top has no jump field, so the two slots hold
C1 and C2. The block's fall-through, the address fetch continues at
when no slot is taken, is the FTB's stored end when the FTB answered,
no branch is cut and no jump is held (`w_pft_p2`, `p2_succ_comb`,
lines 1133 to 1141); it leaves the cluster as `bpu_blk_pft_p2` (line
1275). The cut, which would end the block at a branch the FTB reports
and no slot carries (`w_cut_p2`, lines 1064 to 1074), stays clear.

In the waveform, the first accepted p2 group of the block at top that
ends at J is at cyc 71. In the `bp_cluster_p2_ftb` group,
`tb.dut.u_bpu.r_pc_p2` is 0x8000_0008. The FTB answer holds both
conditional fields (`w_ftb_br_valid_p2.[0]` and `.[1]`) and no jump
(`w_ftb_jmp_valid_p2` 0), `w_cut_p2` is 0, and `tb.dut.bpu_blk_pft_p2`
is 0x8000_0016, J's address. In the `bp_cluster_p2` group,
`tb.dut.bpu_slot_p2.[0]` is C1 and `.[1]` is C2, both COND at `pos` 1
and 4, not taken, `pred_src` PRED_TAGE. The uBTB was split the same
way: its p1 prediction for top, `tb.dut.bpu_pred_pft_p1`, is
0x8000_0016 from cyc 70, so p1 and p2 agree.

### 3.3 The next block predicts the jump

The next block starts at 0x8000_0016. The predictors have not seen
this block start, so at first neither the uBTB nor the FTB answers for
it. Fetch runs past J, and predecode at F3 finds it (predecode
redirects to 0x8000_0400 at cyc 79 and 92). The update for
J from that start allocates its entry at cyc 91, with J at position 0.
From then on the FTB answers for 0x8000_0016 with J in its jump field,
and the cluster places J in slot 0.

The first counted pair is at cyc 97 and 98. At cyc 97 the block at top
ends at 0x8000_0016, as in 3.2; at cyc 98, `r_pc_p2` is 0x8000_0016
and `tb.dut.bpu_slot_p2.[0]` is DIRECT_UNC at `pos` 0, taken, with
`target` 0x8000_0400 and `pred_src` PRED_FTB. The two blocks counted
at cyc 71 and 84 ended at J before J's own entry existed; their next
groups had no FTB answer, so the count of blocks ended at J, 23,
exceeds the count of next blocks, 21.

RTL: the split is `upd_split` and `upd_cut_pos` in `ftb_cntrl.sv`; the
block end is `w_pft_p2` in `bp_cluster.sv`; the monitor is
`tb/fe_demo_mon.svh` lines 602 to 628.

---

## 4. Events

| cyc | Event                                           | Other            |
|-----|-------------------------------------------------|------------------|
| 0   | reset released (`tb.rstn`); the FTQ requests    | fast init        |
|     | 0x8000_0000 the same cycle                      |                  |
| 19  | predecode redirect to 0x8000_0400: J found at   | pass 0           |
|     | F3, not yet known to the predictors             |                  |
| 41  | first backend misprediction, the back edge;     | pass 0           |
|     | redirect to 0x8000_0008                         |                  |
| 52  | FTB entry for top allocated with C1; C2 added   | `ftb_update`     |
|     | at cyc 53                                       |                  |
| 56  | first p2 group for top: C1 and C2 in slots 0    | predicted taken  |
|     | and 1, end 0x8000_0028                          |                  |
| 57  | SC reverses both at p3; redirect to 0x8000_0028 | p3 redirect      |
| 65  | J resolved from top: the split, `upd_split` 1,  | `upd_cut_pos` 7  |
|     | the entry ends at 0x8000_0016                   |                  |
| 71  | first p2 group for top ending at 0x8000_0016,   | counted,         |
|     | C1 and C2 not taken, `w_cut_p2` 0               | `n_jmp_end`      |
| 91  | FTB entry for 0x8000_0016 allocated with J at   | `ftb_update`     |
|     | position 0                                      |                  |
| 98  | the block at 0x8000_0016 predicts J in slot 0,  | counted,         |
|     | taken, to 0x8000_0400                           | `n_jmp_next`     |
| 234 | back edge falls through, a misprediction;       | pass 23          |
|     | redirect to 0x8000_040A                         |                  |
| 244 | the run ends                                    |                  |
