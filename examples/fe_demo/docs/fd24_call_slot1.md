<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd24_call_slot1: A Call in Slot 1
```
 FILE:    fd24_call_slot1.md
 SOURCE:  DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. What the scenario shows

`fd24_call_slot1` is the FD-24 scenario of the front-end demonstration.
A fetch block holds a conditional branch followed by a call. With two
prediction slots the conditional is in slot 0 and the call in slot 1.
When the conditional is predicted not taken, the call in slot 1 is on
the predicted path, and the return address stack (RAS) pushes the
call's return address at p2 from slot 1. The function's return is then
predicted from the stack. The scenario runs on the two-slot model
(`SCEN_2S` in the `Makefile`). demo_explainer.md describes how a
scenario is built and run, and defines the terms used here.

When the scenario passes, it prints one line. This is the line from a
run on 2026-10-19, the run the cyc values below come from:

```
-I: fd24_call_slot1: PASS,
    RAS pushes from slot 1 behind a not-taken conditional 24,
    returns predicted by the RAS 21, cyc 270
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

## 2. The program

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

## 3. Walkthrough

### 3.1 The call reaches slot 1

The FTB entry for the block at top holds C in its first conditional field and
the call in its jump field. At p2 the cluster places C in slot 0. The call goes
to the lowest slot that holds no conditional, which is slot 1 (`p2_class_comb`
in `rtl/core/frontend/bpu/rtl/bp_cluster.sv` lines 1010 to 1046, the jump at
lines 1037 to 1045). A taken branch ends the block, so a slot is on the
predicted path only when no earlier slot is predicted taken (`w_reach_p2`,
lines 1076 to 1084).

### 3.2 The RAS operation of slot 1

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

### 3.3 The return predicted from the stack

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

## 4. Events

| cyc | Event                                           | Other            |
|-----|-------------------------------------------------|------------------|
| 0   | reset released (`tb.rstn`); the FTQ requests    | fast init        |
|     | 0x8000_0000 the same cycle                      |                  |
| 19  | predecode redirect to 0x8000_0400: the call     | pass 0           |
|     | found at F3, not yet known to the predictors    |                  |
| 40  | first return mispredicted, cold; redirect to    | backend          |
|     | 0x8000_0014                                     |                  |
| 51  | back edge mispredicted, cold; redirect to       | backend          |
|     | 0x8000_0008                                     |                  |
| 76  | C mispredicted taken; redirect to 0x8000_000E   | backend          |
| 90  | first RAS push from slot 1, behind C not taken; | counted          |
|     | the first p2 group for top with both slots      |                  |
| 91  | TOSR 1, TOSW 2; entry 1 holds 0x8000_0014;      | PRED_RAS         |
|     | first return predicted from the RAS             |                  |
| 261 | back edge falls through, a misprediction;       | pass 23          |
|     | redirect to 0x8000_001E                         |                  |
| 270 | the run ends                                    |                  |
