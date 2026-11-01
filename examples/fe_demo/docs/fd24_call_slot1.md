<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd24_call_slot1: A Call in Slot 1
```
 FILE:    fd24_call_slot1.md
 SOURCE:  DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd24_call_slot1` is the FD-24 scenario of the front-end demonstration.
A fetch block holds a conditional branch followed by a call. With two
prediction slots the conditional is in slot 0 and the call in slot 1.
When the conditional is predicted not taken, the call in slot 1 is on
the predicted path, and the return address stack (RAS) pushes the
call's return address at p2 from slot 1. The function's return is then
predicted from the stack. The scenario runs on the two-slot model
(`SCEN_2S` in the `Makefile`). demo_explainer.md describes how a
scenario is built and run, and defines the terms used here.

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                          |
  |--------------------|-----------------------------------------------|
  | This file          | $DEMO/docs/fd24_call_slot1.md                 |
  | Program (stimulus) | $DEMO/programs/fd24_call_slot1.svh            |
  | Surfer sucl        | $DEMO/waves/fd24_call_slot1.sucl              |
  | Log                | $DEMO/out/fd24_call_slot1/fd24_call_slot1.log |
  | Waveform           | $DEMO/out/fd24_call_slot1/fd24_call_slot1.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd24_call_slot1.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd24_call_slot1.sucl) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd24_call_slot1
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd24_call_slot1
```

Console output:
```
-I: fd24_call_slot1 : PASS : cyc = 270
```

Log file output:
```
-I: fd24_call_slot1: PASS,
    RAS pushes from slot 1 behind a not-taken conditional 24,
    returns predicted by the RAS 21, events checked 9 of 9, cyc 270
```

The two counts are:

- RAS pushes from slot 1 behind a not-taken conditional, the monitor
  variable `n_push_s1` (`tb/fe_demo_mon.svh` lines 629 to 637): p2
  groups the FTQ accepted (`tb.dut.u_ftq.w_ok_slot_p2`) in which slot
  0 is a conditional predicted not taken and slot 1, a call, is
  presented to the RAS (`tb.dut.u_bpu.w_ras_pred_val_p2.[1]`);
- returns predicted by the RAS, `n_ras_ret_ok` (lines 306 to 310): a
  retired return whose block's final slot for it has `pred_src`
  PRED_RAS and the right target.

The scenario passes when both counts are greater than zero
(`tb/fe_demo_proofs.svh` line 186) and every instruction the testbench
expects retires without error. On the one-slot model the first count
is 0 and the scenario fails. The run took 270 cycles.

---

## 3. The program

The program is written by the task `prog_fd24` in
`programs/fd24_call_slot1.svh`. Between a short prologue and epilogue
it runs a loop of 24 passes. The loop's first block holds C, a
conditional that is never taken, followed by a call to the function f
at 0x8000_0400. f returns to the block that holds the back edge. The
program runs in machine mode with translation off, so the addresses
are physical. It starts at the reset vector, `RESET_VECTOR` =
0x8000_0000 (`bp_defines_pkg.sv`). The loop's first instruction, top,
is at 0x8000_0008.

```
Address      Label  Instruction              Purpose
0x8000_0000         c.addi a0, 1             prologue filler
0x8000_0002         addi t0, t0, 1           prologue filler
0x8000_0006         c.addi a0, 1             prologue filler
0x8000_0008  top:   c.addi a0, 1             loop body filler
0x8000_000A  C:     bne x6, x0, 0x8000_0010  never taken
0x8000_000E         c.addi a0, 1             always executed
0x8000_0010         jal x1, 0x8000_0400      the call; return address
                                             0x8000_0014
0x8000_0400  f:     c.addi a0, 1             function body
0x8000_0402         addi t0, t0, 1           function body
0x8000_0406         jalr x0, 0(x1)           return to 0x8000_0014
0x8000_0014         c.addi a0, 1             filler
0x8000_0016         addi t0, t0, 1           filler
0x8000_001A         bne x6, x0, 0x8000_0008  back edge to top
0x8000_001E         c.addi a0, 1             epilogue filler
0x8000_0020         addi t0, t0, 1           epilogue filler
0x8000_0024         c.addi a0, 1             epilogue filler
0x8000_0026         jal x0, 0                jump to itself; the run
                                             ends here
```

In the block that starts at top, C is at halfword position 1 and the
call at position 4. The `jal` with rd x1 is a call (`DIRECT_CALL`) and
the `jalr x0, 0(x1)` a return (`RETURN`), by the program writer's
types (`W.jal` and `W.ret` in
`rtl/core/frontend/fe_top/tb/models/fe_tb_writer.svh`). The back edge
is taken on passes 0 to 22 and falls through on pass 23.

---

## 4. Walkthrough

### 4.1 The call reaches slot 1

The FTB entry for the block at top holds C in its first conditional field and
the call in its jump field. At p2 the cluster places C in slot 0. The call goes
to the lowest slot that holds no conditional, which is slot 1 (`p2_class_comb`
in `rtl/core/frontend/bpu/rtl/bp_cluster.sv` lines 1010 to 1046, the jump at
lines 1037 to 1045). A taken branch ends the block, so a slot is on the
predicted path only when no earlier slot is predicted taken (`w_reach_p2`,
lines 1076 to 1084).

### 4.2 The RAS operation of slot 1

At p2 a slot of a valid block is presented to the RAS when it holds a
branch on the predicted path (`w_ras_pred_val_p2`, lines 1086 to 1091).
The RAS performs the slots' operations in order, slot 0 first, so a
call in slot 1 pushes its return address after slot 0's operation
(`rtl/core/frontend/bpu/rtl/ras.sv` lines 24 to 27). A push allocates
an entry at the write pointer TOSW, and the read pointer TOSR moves to
it (`st_push` at `ras.sv` lines 406 to 454; the p2 push at lines 696
to 705).

In the waveform, the first counted push is at cyc 90. It is also the
first p2 group for top with both slots valid. In the `bp_cluster_p2`
group, `tb.dut.bpu_slot_p2.[0]` is C, a COND at `pos` 1, not taken,
`pred_src` PRED_TAGE. `tb.dut.bpu_slot_p2.[1]` is the call,
DIRECT_CALL at `pos` 4, taken, with `target` 0x8000_0400 and
`pred_src` PRED_FTB. In the `ras` group
`tb.dut.u_bpu.w_ras_pred_val_p2.[1]` is 1 with `w_br_type_p2.[1]`
DIRECT_CALL, and `w_ras_pred_val_p2.[0]` is 1 for C, a conditional,
which the RAS does not act on. At cyc 91 `tb.dut.u_bpu.u_ras.tosr` has
moved from 0 to 1 and `tosw` from 0 to 2. `spec_ret_addr.[1]` holds
0x8000_0014, the call's return address.

### 4.3 The return predicted from the stack

The block at f holds the return. At p2 a return slot takes the RAS's
pop address as its target when the pop is valid, with `pred_src`
PRED_RAS (`bp_cluster.sv` lines 1164 to 1170). Of the 25 accepted p2
groups for the block at 0x8000_0400, 23 predict the return from the
RAS with target 0x8000_0014. The first is at cyc 91, the cycle after
the first counted push.

Before cyc 90 the call is found four times by predecode, each time in a
block whose start has no FTB entry holding it yet; each block start
has its own entry (BP-140). Predecode redirects to 0x8000_0400 at cyc
19 (the block at 0x8000_0000, pass 0), 60 (top, after the back edge's
first backend redirect), 75 (0x8000_0010, C's target, while C is
predicted taken) and 85 (0x8000_000E, C's fall-through, after the
backend corrects C).

When the call and the return retire, the commit stack follows them
(`tb.dut.ras_commit_val` with `u_ras.csp`). The run has 48 commits: a
push and a pop for each of the 24 passes.

RTL: the slot-1 presentation is `w_ras_pred_val_p2[1]` in
`bp_cluster.sv`; the monitor is `tb/fe_demo_mon.svh` lines 629 to 637.

---

## 5. Events

| # | cyc | Event                                                                                      | Other     |
|---|-----|--------------------------------------------------------------------------------------------|-----------|
| 0 | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                    | fast init |
| 1 | 19  | predecode redirect to 0x8000_0400: the call found at F3, not yet known to the predictors   | pass 0    |
| 2 | 40  | first return mispredicted, cold; redirect to 0x8000_0014                                   | backend   |
| 3 | 51  | back edge mispredicted, cold; redirect to 0x8000_0008                                      | backend   |
| 4 | 76  | C mispredicted taken; redirect to 0x8000_000E                                              | backend   |
| 5 | 90  | first RAS push from slot 1, behind C not taken; the first p2 group for top with both slots | counted   |
| 6 | 91  | TOSR 1, TOSW 2; entry 1 holds 0x8000_0014; first return predicted from the RAS             | PRED_RAS  |
| 7 | 261 | back edge falls through, a misprediction; redirect to 0x8000_001E                          | pass 23   |
| 8 | 270 | the run ends                                                                               |           |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd24_call_slot1` opens
`waves/fd24_call_slot1.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group         | signal                          | description                                  |
|---------------|---------------------------------|----------------------------------------------|
| clock         | `tb.clk`                        | clock                                        |
|               | `tb.rstn`                       | active low reset                             |
|               | `tb.cyc`                        | cycle number                                 |
| bp_cluster_p2 | `u_bpu.r_val_p2`                | p2 valid                                     |
|               | `bpu_slot_val_p2`               | slot valid mask                              |
|               | `bpu_slot_idx_p2`               | FTQ index of the p2 group                    |
|               | `u_bpu.w_ftb_valid_p2`          | FTB hit at p2                                |
|               | `bpu_slot_p2.[0].slot_valid`    | slot 0 holds a branch                        |
|               | `bpu_slot_p2.[0].br_type`       | slot 0 branch type                           |
|               | `bpu_slot_p2.[0].pos`           | slot 0 halfword position in the fetch block  |
|               | `bpu_slot_p2.[0].taken`         | slot 0 predicted direction                   |
|               | `bpu_slot_p2.[0].target`        | slot 0 predicted target                      |
|               | `bpu_slot_p2.[0].pred_src`      | slot 0 predictor that supplied the direction |
|               | `bpu_slot_p2.[1].slot_valid`    | slot 1 holds a branch                        |
|               | `bpu_slot_p2.[1].br_type`       | slot 1 branch type                           |
|               | `bpu_slot_p2.[1].pos`           | slot 1 halfword position in the fetch block  |
|               | `bpu_slot_p2.[1].taken`         | slot 1 predicted direction                   |
|               | `bpu_slot_p2.[1].target`        | slot 1 predicted target                      |
|               | `bpu_slot_p2.[1].pred_src`      | slot 1 predictor that supplied the direction |
|               | `bpu_redir_p2.[0].valid`        | p2 redirect from slot 0                      |
|               | `bpu_redir_p2.[0].target_pc`    | p2 redirect target from slot 0               |
|               | `bpu_redir_p2.[1].valid`        | p2 redirect from slot 1                      |
|               | `bpu_redir_p2.[1].target_pc`    | p2 redirect target from slot 1               |
|               | `bpu_redir_idx_p2`              | FTQ index of the p2 redirect                 |
| ras           | `u_bpu.u_ras.tosr`              | RAS read pointer                             |
|               | `u_bpu.u_ras.tosw`              | RAS write pointer                            |
|               | `u_bpu.u_ras.bos`               | RAS bottom of stack                          |
|               | `u_bpu.u_ras.ras_rst_done`      | RAS reset done                               |
|               | `u_bpu.w_ras_pred_val_p2.[0]`   | slot 0 presented to the RAS at p2            |
|               | `u_bpu.w_ras_pred_val_p2.[1]`   | slot 1 presented to the RAS at p2            |
|               | `u_bpu.w_br_type_p2.[0]`        | slot 0 branch type at p2                     |
|               | `u_bpu.w_br_type_p2.[1]`        | slot 1 branch type at p2                     |
|               | `u_bpu.u_ras.spec_ret_addr.[0]` | RAS entry 0 return address                   |
|               | `u_bpu.u_ras.spec_ret_addr.[1]` | RAS entry 1 return address                   |
|               | `u_bpu.u_ras.spec_ret_addr.[2]` | RAS entry 2 return address                   |
|               | `u_bpu.u_ras.spec_ret_addr.[3]` | RAS entry 3 return address                   |
|               | `u_bpu.u_ras.spec_rctr.[0]`     | RAS entry 0 recursion count                  |
|               | `u_bpu.u_ras.spec_rctr.[1]`     | RAS entry 1 recursion count                  |
|               | `u_bpu.u_ras.spec_rctr.[2]`     | RAS entry 2 recursion count                  |
|               | `u_bpu.u_ras.spec_rctr.[3]`     | RAS entry 3 recursion count                  |
| ftq           | `u_ftq.w_ok_pred_p1`            | the FTQ accepts the p1 prediction            |
|               | `u_ftq.w_ok_slot_p2`            | the FTQ accepts the p2 group                 |
|               | `u_ftq.w_ok_slot_p3`            | the FTQ accepts the p3 group                 |
|               | `u_ftq.w_ok_redir_p2`           | the FTQ accepts the p2 redirect              |
|               | `u_ftq.w_ok_redir_p3`           | the FTQ accepts the p3 redirect              |
|               | `u_ftq.w_redir_val`             | a redirect the FTQ takes                     |
|               | `u_ftq.w_redir_idx`             | FTQ index of the redirect                    |
|               | `u_ftq.w_commit_ptr`            | FTQ commit pointer                           |
|               | `ftq_full`                      | FTQ full                                     |
|               | `ftq_empty`                     | FTQ empty                                    |
| ras_commit    | `ras_commit_val`                | RAS commit valid                             |
|               | `ras_commit_br_type`            | branch type of the RAS commit                |
|               | `ras_commit_ret_addr`           | return address of the RAS commit             |
|               | `u_bpu.u_ras.csp`               | commit stack pointer                         |
|               | `u_bpu.u_ras.commit_top_valid`  | commit stack top valid                       |
|               | `u_bpu.u_ras.commit_top_addr`   | commit stack top address                     |
