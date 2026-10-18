<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd03_two_branch: Two Branches in One Block
```
 FILE:    fd03_two_branch.md
 SOURCE:  DOC-002, DOC-006
 STATUS:  WORKING
 UPDATED: 2026-10-17
 CONTACT: Jeff Nye
```

`fd03_two_branch` is the FD-3 demonstration scenario. It is a demo, not a
verification test. It runs a loop through two blocks, X and Y, each
holding two conditional branches within its first 32 bytes. Once the
predictors are trained, the p1 prediction (uBTB) and the p2 slot group
(FTB) for each block carry both prediction slots. The run passes if the
FTQ accepts at least one p1 prediction or p2 slot group with both slots
valid.

The scenario needs two prediction slots and runs on the two-slot model
(Makefile `SCEN_2S`, DOC-006); on the one-slot model both counts are 0
and it fails. A recorded run:

```
-I: fd03_two_branch: PASS, blocks with both slots valid at p1 132, at p2 91,
    cyc 537
```

---

## 1. The program

Source: `programs/fd03_two_branch.svh`, task `prog_fd03` (tb_fe_top's
twocond). `X = RESET_VECTOR + 0x400`, `Y = RESET_VECTOR + 0x440`,
`top = RESET_VECTOR + 8`.

```
RESET_VECTOR+0   mixed(3)                                  8 bytes
top              c.addi
top+2            jal x0,X
top+6   (back)   c.addi
top+8            bne x6,x0,top        back edge: taken on passes 0..22
top+12           mixed(3)
top+20           jal x0,0             halt (demo_go -> W.halt)

X+0              c.addi
X+2     X.c1     bne x6,x0,X+8        never taken            pos 1
X+6              c.addi
X+8     X.c2     bne x6,x0,X+14       always taken           pos 4
X+12             c.addi               skipped (written dry)
X+14             c.addi
X+16             jal x0,Y                                    pos 8

Y+0              c.addi
Y+2     Y.c1     bne x6,x0,Y+8        taken on odd passes    pos 1
Y+6              c.addi               skipped when Y.c1 taken
Y+8     Y.c2     bne x6,x0,Y+14       never taken            pos 4
Y+12             c.addi
Y+14             c.addi
Y+16             jal x0,back                                 pos 8
```

- 24 passes. Each pass resets `W.wp = top` and writes the same bytes;
  `cskip(tk, 1)` writes the skipped `c.addi` in dry mode when taken, so
  the code is fixed and only the expected stream changes.
- Outcomes come from the writer (`bcc`, `fe_tb_writer.svh:412-421`), not
  from x6: the backend retires against the expected stream.
- `pos` is the halfword position from the lookup PC (X or Y, both
  32-byte aligned).

---

## 2. Why the program fills both slots

1. Two branch fields per entry. On the two-slot model a prediction
   block has `NUM_PRED_SLOTS` = 2 slots (`bp_defines_pkg.sv:65`), each a
   `bp_ftq_slot_t` (`bp_structs_pkg.sv:405-418`). The FTB update fills
   `br0` when it is free, else `br1` (`rtl/core/frontend/bpu/rtl/
   ftb_cntrl.sv:492-496`); the uBTB fills the field `br_idx` names
   (`ubtb.sv:305-318`).
2. Both conditionals of X and of Y are on the path in every pass: X.c1
   is never taken, so X.c2 is reached; Y.c1 when not taken falls into
   Y.c2, and when taken jumps to Y+8, which is Y.c2. The FST shows
   both in the block's two slots (below).
3. Slot order. `bp_cluster.sv:853-859` swaps the two p1 slots when slot
   1's `pos` is below slot 0's, so slot 0 is always the earlier branch.

From the FST, the accepted two-slot p2 groups, by block:

```
block        slot 0              slot 1              groups
X            pos 1 COND nt  TAGE pos 4 COND tk  TAGE  33
Y            pos 1 COND nt  TAGE pos 4 COND nt  TAGE  14
Y            pos 1 COND tk  TAGE pos 4 COND nt  TAGE  17
Y+8          pos 0 COND     TAGE pos 4 JAL  tk  FTB   22
Y+6, X+6/8   COND and JAL                              5
```

(COND is `br_type` COND, JAL `DIRECT_UNC`; TAGE and FTB are
`pred_src` PRED_TAGE and PRED_FTB, which the waveform shows by name.)
Y+8 is the block fetched after Y.c1 is taken: Y.c2 at its position 0
and the JAL to back at position 4.

---

## 3. What the monitor counts

The counts come from `tb/fe_demo_mon.svh:411-419`, taken inside the
`meas` window.

```
n_two_p1   u_ftq.w_ok_pred_p1 && bpu_pred_slot_p1[0].slot_valid
           && bpu_pred_slot_p1[1].slot_valid
           a p1 prediction the FTQ accepted, both slots valid
n_two_p2   u_ftq.w_ok_slot_p2 && bpu_slot_p2[0].slot_valid
           && bpu_slot_p2[1].slot_valid
           a p2 slot group the FTQ accepted, both slots valid
```

The proof (`tb/fe_demo_proofs.svh:55-59`) is
`n_two_p1 + n_two_p2 > 0`. `tb_fe_demo.sv` also requires the whole
stream to retire with no errors before it accepts the proof.

---

## 4. Reading the numbers

- The counts are of groups the FTQ accepted. X is executed once per
  pass, 24 times, and shows 33 two-slot p2 groups; the count includes
  repeated predictions of the same block.
- The counters do not check the slot types. Of the 132 p1 groups (FST),
  33 are X, 32 are Y and 24 are Y+8; 38 are the top block at
  `top` (0x80000008), whose uBTB answer holds the JAL at position 1 and
  a conditional at position 4; the other 5 are at Y+6, X+6 and X+8. No
  accepted p2 group for the top block has two slots; at p2 its FTB
  answer has one.
- Departure from `planning/showcase/fe_demo_scenarios.md` FD-3: the
  program is "two conditional branches within one 32-byte block, in a
  loop"; as built there are two such blocks, X (not taken, then taken)
  and Y (alternating, then not taken). The proof "a block predicted
  with both slots valid" is met by any two valid slots, including a
  JAL in one of them, as the top-block and Y+8 counts show.

---

## 5. Waveform

The saved view is `waves/fd03_two_branch.sucl`, which `make view
S=fd03_two_branch` opens in Surfer. Look at:

- group `bp_cluster_p1_ubtb`: `r_ubtb_blk_p1.hit` with
  `bpu_pred_slot_p1.[0]` and `.[1]` both `slot_valid`, `pos` 1 and 4,
  at `bpu_pred_idx_p1` of the X and Y blocks.
- group `bp_cluster_p2_ftb`: `w_ftb_valid_p2`, `bpu_slot_val_p2` and
  `bpu_slot_p2.[0]` / `.[1]` both valid, each a conditional (`br_type`
  COND) at its own `pos`, `pred_src` PRED_TAGE.
- group `ftq`: `w_ok_pred_p1` and `w_ok_slot_p2` accepting them.
