<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd03_two_branch: Two Branches in One Block
```
 FILE:    fd03_two_branch.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd03_two_branch` is the FD-3 demonstration scenario. It is a demo, not a
verification test. It runs a loop through two blocks, X and Y, each
holding two conditional branches within its first 32 bytes. Once the
predictors are trained, the p1 prediction (uBTB) and the p2 slot group
(FTB) for each block carry both prediction slots. The run passes if the
FTQ accepts at least one p1 prediction or p2 slot group with both slots
valid.

The scenario needs two prediction slots and runs on the two-slot model
(Makefile `SCEN_2S`, DOC-006); on the one-slot model both counts are 0
and it fails.

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                          |
  |--------------------|-----------------------------------------------|
  | This file          | $DEMO/docs/fd03_two_branch.md                 |
  | Program (stimulus) | $DEMO/programs/fd03_two_branch.svh            |
  | Surfer sucl        | $DEMO/waves/fd03_two_branch.sucl              |
  | Log                | $DEMO/out/fd03_two_branch/fd03_two_branch.log |
  | Waveform           | $DEMO/out/fd03_two_branch/fd03_two_branch.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd03_two_branch.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd03_two_branch.sucl) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd03_two_branch
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd03_two_branch
```

Console output:
```
-I: fd03_two_branch : PASS : cyc = 539
```

Log file output:
```
-I: fd03_two_branch: PASS, blocks with both slots valid at p1 78, at p2 74,
    events checked 6 of 6, cyc 539
```

### 2.1 What the monitor counts

The counts come from `tb/fe_demo_mon.svh:415-423`, taken inside the
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

### 2.2 Reading the numbers

- The counts are of groups the FTQ accepted. X is executed once per
  pass, 24 times, and shows 27 two-slot p2 groups; the count includes
  repeated predictions of the same block.
- The counters do not check the slot types. Of the 78 p1 groups (FST),
  27 are X, 27 are Y, 21 are Y+8 and 3 are Y+6. The block at `top`
  (0x80000008) holds only the JAL, and its entry, which is its own
  since each block start has one (BP-140), has one slot.
- Departure from `planning/showcase/fe_demo_scenarios.md` FD-3: the
  program is "two conditional branches within one 32-byte block, in a
  loop"; as built there are two such blocks, X (not taken, then taken)
  and Y (alternating, then not taken). The proof "a block predicted
  with both slots valid" is met by any two valid slots, including a
  JAL in one of them, as the Y+6 and Y+8 counts show.

---

## 3. The program

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
- Outcomes come from the writer (`bcc`, `fe_tb_writer.svh:412-419`), not
  from x6: the backend retires against the expected stream.
- `pos` is the halfword position from the lookup PC (X or Y, both
  32-byte aligned).

---

## 4. Walkthrough

### 4.1 Why the program fills both slots

1. Two branch fields per entry. On the two-slot model a prediction
   block has `NUM_PRED_SLOTS` = 2 slots (`bp_defines_pkg.sv:65`), each a
   `bp_ftq_slot_t` (`bp_structs_pkg.sv:405-418`). The FTB and the uBTB
   store a block's branches in position order, `br0` the lower: the
   update sorts the stored fields and the resolving branch by position
   (`rtl/core/frontend/bpu/rtl/ftb_cntrl.sv`, THE UPDATE, lines 464 to
   615; `ubtb.sv`, `apply_upd`, lines 291 to 376).
2. Both conditionals of X and of Y are on the path in every pass: X.c1
   is never taken, so X.c2 is reached; Y.c1 when not taken falls into
   Y.c2, and when taken jumps to Y+8, which is Y.c2. The FST shows
   both in the block's two slots (below).
3. Slot order. `bp_cluster.sv:861-867` swaps the two p1 slots when slot
   1's `pos` is below slot 0's, so slot 0 is always the earlier branch.
   Since the uBTB stores in position order the swap does not fire for
   its entries (the comment at lines 853 to 860).

From the FST, the accepted two-slot p2 groups, by block:

```
block        slot 0              slot 1              groups
X            pos 1 COND nt  TAGE pos 4 COND tk  TAGE  26
X            pos 1 COND tk  TAGE pos 4 COND tk  TAGE   1
Y            pos 1 COND nt  TAGE pos 4 COND nt  TAGE   5
Y            pos 1 COND nt  TAGE pos 4 COND tk  TAGE   1
Y            pos 1 COND tk  TAGE pos 4 COND nt  TAGE   7
Y            pos 1 COND tk  TAGE pos 4 COND tk  TAGE  13
Y+6          pos 1 COND nt  TAGE pos 5 JAL  tk  FTB    3
Y+8          pos 0 COND nt  TAGE pos 4 JAL  tk  FTB   15
Y+8          pos 0 COND tk  TAGE pos 4 JAL  tk  FTB    3
```

(COND is `br_type` COND, JAL `DIRECT_UNC`; TAGE and FTB are
`pred_src` PRED_TAGE and PRED_FTB, which the waveform shows by name;
nt and tk are `taken` 0 and 1.) Y+8 is the block fetched after Y.c1 is
taken: Y.c2 at its position 0 and the JAL to back at position 4. Y+6
is the block fetched after the backend corrects a Y.c1 predicted
taken: Y.c2 at its position 1 and the JAL at position 5.

### 4.2 Reading the waveform

The saved view is `waves/fd03_two_branch.sucl`, which `make view
S=fd03_two_branch` opens in Surfer. Look at:

- group `bp_cluster_p1_ubtb`: `r_ubtb_blk_p1.hit` with
  `bpu_pred_slot_p1.[0]` and `.[1]` both `slot_valid`, `pos` 1 and 4,
  at `bpu_pred_idx_p1` of the X and Y blocks.
- group `bp_cluster_p2_ftb`: `w_ftb_valid_p2`, `bpu_slot_val_p2` and
  `bpu_slot_p2.[0]` / `.[1]` both valid, each a conditional (`br_type`
  COND) at its own `pos`, `pred_src` PRED_TAGE.
- group `ftq`: `w_ok_pred_p1` and `w_ok_slot_p2` accepting them.

---

## 5. Events

| # | cyc | Event                                                                                              | Other                        |
|---|-----|----------------------------------------------------------------------------------------------------|------------------------------|
| 0 | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                            | fast init                    |
| 1 | 83  | first p1 prediction for X with both slots valid, accepted by the FTQ                               | uBTB, X 0x8000_0400          |
| 2 | 84  | first p2 group for X with both slots: X.c1 at position 1 and X.c2 at position 4, both conditionals | accepted, FTB                |
| 3 | 107 | first p2 group for Y with both slots: Y.c1 at position 1 and Y.c2 at position 4, both conditionals | accepted, FTB, Y 0x8000_0440 |
| 4 | 529 | back edge falls through, a misprediction; redirect to 0x8000_0014                                  | pass 23                      |
| 5 | 539 | the run ends                                                                                       |                              |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd03_two_branch` opens
`waves/fd03_two_branch.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group              | signal                            | description                                     |
|--------------------|-----------------------------------|-------------------------------------------------|
| clock              | `tb.clk`                          | clock                                           |
|                    | `tb.rstn`                         | active low reset                                |
|                    | `tb.cyc`                          | cycle number                                    |
| bp_cluster_p1_ubtb | `bpu_pred_val_p1`                 | p1 prediction valid                             |
|                    | `bpu_pred_idx_p1`                 | FTQ index of the p1 prediction                  |
|                    | `u_bpu.r_ubtb_blk_p1.hit`         | uBTB hit at p1                                  |
|                    | `bpu_pred_pft_p1`                 | p1 fetch block end, the first halfword after it |
|                    | `bpu_pred_slot_p1.[0].slot_valid` | slot 0 holds a branch                           |
|                    | `bpu_pred_slot_p1.[0].br_type`    | slot 0 branch type                              |
|                    | `bpu_pred_slot_p1.[0].pos`        | slot 0 halfword position in the fetch block     |
|                    | `bpu_pred_slot_p1.[0].taken`      | slot 0 predicted direction                      |
|                    | `bpu_pred_slot_p1.[0].target`     | slot 0 predicted target                         |
|                    | `bpu_pred_slot_p1.[0].pred_src`   | slot 0 predictor that supplied the direction    |
|                    | `bpu_pred_slot_p1.[1].slot_valid` | slot 1 holds a branch                           |
|                    | `bpu_pred_slot_p1.[1].br_type`    | slot 1 branch type                              |
|                    | `bpu_pred_slot_p1.[1].pos`        | slot 1 halfword position in the fetch block     |
|                    | `bpu_pred_slot_p1.[1].taken`      | slot 1 predicted direction                      |
|                    | `bpu_pred_slot_p1.[1].target`     | slot 1 predicted target                         |
|                    | `bpu_pred_slot_p1.[1].pred_src`   | slot 1 predictor that supplied the direction    |
| bp_cluster_p2_ftb  | `u_bpu.r_val_p2`                  | p2 valid                                        |
|                    | `bpu_slot_val_p2`                 | slot valid mask                                 |
|                    | `bpu_slot_idx_p2`                 | FTQ index of the p2 group                       |
|                    | `u_bpu.w_ftb_valid_p2`            | FTB hit at p2                                   |
|                    | `bpu_slot_p2.[0].slot_valid`      | slot 0 holds a branch                           |
|                    | `bpu_slot_p2.[0].br_type`         | slot 0 branch type                              |
|                    | `bpu_slot_p2.[0].pos`             | slot 0 halfword position in the fetch block     |
|                    | `bpu_slot_p2.[0].taken`           | slot 0 predicted direction                      |
|                    | `bpu_slot_p2.[0].target`          | slot 0 predicted target                         |
|                    | `bpu_slot_p2.[0].pred_src`        | slot 0 predictor that supplied the direction    |
|                    | `bpu_slot_p2.[1].slot_valid`      | slot 1 holds a branch                           |
|                    | `bpu_slot_p2.[1].br_type`         | slot 1 branch type                              |
|                    | `bpu_slot_p2.[1].pos`             | slot 1 halfword position in the fetch block     |
|                    | `bpu_slot_p2.[1].taken`           | slot 1 predicted direction                      |
|                    | `bpu_slot_p2.[1].target`          | slot 1 predicted target                         |
|                    | `bpu_slot_p2.[1].pred_src`        | slot 1 predictor that supplied the direction    |
|                    | `bpu_redir_p2.[0].valid`          | p2 redirect from slot 0                         |
|                    | `bpu_redir_p2.[0].target_pc`      | p2 redirect target from slot 0                  |
|                    | `bpu_redir_p2.[1].valid`          | p2 redirect from slot 1                         |
|                    | `bpu_redir_p2.[1].target_pc`      | p2 redirect target from slot 1                  |
|                    | `bpu_redir_idx_p2`                | FTQ index of the p2 redirect                    |
| ftq                | `u_ftq.w_ok_pred_p1`              | the FTQ accepts the p1 prediction               |
|                    | `u_ftq.w_ok_slot_p2`              | the FTQ accepts the p2 group                    |
|                    | `u_ftq.w_ok_slot_p3`              | the FTQ accepts the p3 group                    |
|                    | `u_ftq.w_ok_redir_p2`             | the FTQ accepts the p2 redirect                 |
|                    | `u_ftq.w_ok_redir_p3`             | the FTQ accepts the p3 redirect                 |
|                    | `u_ftq.w_redir_val`               | a redirect the FTQ takes                        |
|                    | `u_ftq.w_redir_idx`               | FTQ index of the redirect                       |
|                    | `u_ftq.w_commit_ptr`              | FTQ commit pointer                              |
|                    | `ftq_full`                        | FTQ full                                        |
|                    | `ftq_empty`                       | FTQ empty                                       |
