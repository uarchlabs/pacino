<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd22_sc_slot1: SC Reversing Slot 1
```
 FILE:    fd22_sc_slot1.md
 SOURCE:  DOC-006
 STATUS:  WORKING
 UPDATED: 2026-10-17
 CONTACT: Jeff Nye
```

## 1. What the scenario shows

`fd22_sc_slot1` is the FD-22 scenario of the front-end demonstration.
One fetch block holds two conditional branches. TAGE predicts both at
p2, one in each prediction slot. At p3 the statistical corrector (SC)
reverses the direction of the second, in slot 1, and the cluster
redirects the request stream from slot 1. FD-5 (`docs/fd05_p3_override.md`)
shows the same reversal in slot 0 on the one-slot model; this scenario
needs the second slot and runs on the two-slot model (`SCEN_2S` in the
`Makefile`). demo_explainer.md describes how a scenario is built and
run, and defines the terms used here.

When the scenario passes, it prints one line. This is the line from a
run on 2026-10-17, the run the cyc values below come from:

```
-I: fd22_sc_slot1: PASS,
    p3 redirects from slot 1 reversed by SC behind a TAGE slot 0 10,
    from slot 0 reversed by SC 2, cyc 386
```

The monitor, `tb/fe_demo_mon.svh` lines 579 to 597, counts a p3
redirect the FTQ accepted (`tb.dut.u_ftq.w_ok_redir_p3`) for the block
at p3 when one of the slots raised it:

- p3 redirects from slot 1 reversed by SC behind a TAGE slot 0, the
  monitor variable `n_sc_s1`: slot 1 raises the redirect, slot 1 is a
  conditional whose `pred_src` is PRED_SC, and slot 0 is a conditional
  whose `pred_src` is PRED_TAGE;
- from slot 0 reversed by SC, `n_sc_s0`: slot 0 raises the redirect and
  its `pred_src` is PRED_SC.

The scenario passes when the first count is greater than zero
(`tb/fe_demo_proofs.svh` line 173) and every instruction the testbench
expects retires without error. The second count is reported for
information only. On the one-slot model the first count is 0, because
there is no slot 1, and the scenario fails. The run took 386 cycles.

---

## 2. The program

The program is written by the task `prog_fd22` in
`programs/fd22_sc_slot1.svh`. Between a short prologue and epilogue it
runs a loop of 48 passes. The loop's first block holds two conditional
branches: A, never taken, and B, taken on the odd passes. The program
runs in machine mode with translation off, so the addresses are
physical. It starts at the reset vector, `RESET_VECTOR` = 0x8000_0000
(`bp_defines_pkg.sv`). The loop's first instruction, top, is at
0x8000_0008.

```
Address      Label  Instruction              Purpose
0x8000_0000         c.addi a0, 1             prologue filler
0x8000_0002         addi t0, t0, 1           prologue filler
0x8000_0006         c.addi a0, 1             prologue filler
0x8000_0008  top:   c.addi a0, 1             loop body filler
0x8000_000A         addi t0, t0, 1           loop body filler
0x8000_000E  A:     bne x6, x0, 0x8000_0014  never taken
0x8000_0012         c.addi a0, 1             always executed
0x8000_0014         c.addi a0, 1             loop body filler
0x8000_0016  B:     bne x6, x0, 0x8000_001C  taken on odd passes
0x8000_001A         c.addi a0, 1             executed when B is not
                                             taken
0x8000_001C         c.addi a0, 1             B's target; filler
0x8000_001E         addi t0, t0, 1           filler
0x8000_0022         c.addi a0, 1             filler
0x8000_0024         c.addi a0, 1             filler
0x8000_0026         addi t0, t0, 1           filler
0x8000_002A         c.addi a0, 1             filler
0x8000_002C         bne x6, x0, 0x8000_0008  back edge to top
0x8000_0030         c.addi a0, 1             epilogue filler
0x8000_0032         addi t0, t0, 1           epilogue filler
0x8000_0036         c.addi a0, 1             epilogue filler
0x8000_0038         jal x0, 0                jump to itself; the run
                                             ends here
```

In the block that starts at top, A is at halfword position 3 and B at
position 7. The filler after B moves the back edge into the next block,
so the block at top holds exactly the two conditionals. B skips one
instruction: its target, 0x8000_001C, lies inside the block, so the
block's successor differs between B taken and B not taken.

The program writer writes the loop body once per pass at the same
addresses, so the code in memory does not change; the passes differ
only in the expected list (demo_explainer.md sections 2 and 3). When
B is taken, `W.cskip` in `rtl/core/frontend/fe_top/tb/models/fe_tb_writer.svh`
writes the `c.addi` at 0x8000_001A in dry mode, and the expected list
leaves it out. The backend model resolves each branch with the
direction the program recorded; x6 is never read.

---

## 3. Walkthrough

### 3.1 Two conditionals in one prediction block

The FTB records, for a block start address, up to `NUM_PRED_SLOTS`
conditional branches and one jump, each with its position. On the
two-slot model the block at top has A in its first conditional field
and B in its second. At p2 the cluster presents them in slots 0 and 1.
For each conditional slot, TAGE's direction is used when TAGE
answered for the block (`w_taken_p2`, `rtl/core/frontend/bpu/rtl/bp_cluster.sv`
lines 1015 to 1029), and the slot's `pred_src` is PRED_TAGE.

In the waveform, the first p2 group for the block at top with both slots valid
is at cyc 24, in the `bp_cluster_p2` group. `tb.dut.bpu_slot_p2.[0]` is A at
`pos` 3 and `tb.dut.bpu_slot_p2.[1]` is B at `pos` 7. Both are COND with
`pred_src` PRED_TAGE. TAGE's base table starts weakly taken, so both are
predicted taken here; A's misprediction is corrected by the backend at cyc 36 (a
redirect to 0x8000_0012).

RTL: the placement of the FTB's conditional fields into slots is in
`p2_class_comb`, `bp_cluster.sv` lines 1015 to 1029.

### 3.2 SC answers at p3 for each slot

SC answers one cycle after TAGE, at p3, separately for each slot. For
a conditional slot with an SC hit, and no loop predictor direction at
p2, the p3 direction is SC's (`w_taken_p3`, `bp_cluster.sv` lines 1277
to 1280). When it differs from the p2 direction, the p3 slot records
`pred_src` PRED_SC (`p3_slot_comb`, lines 1316 to 1329).

The successors at p3 are chained from the highest slot down, as at p2:
slot 1's successor is B's target when B is taken and the block's
fall-through when it is not, and slot 0's successor is A's target or
slot 1's successor. A slot redirects when it is reachable and its p3
successor differs from its p2 successor (lines 1284 to 1301). Because
A is not taken, slot 1 is reachable, and a reversal of B changes both
successors: slot 1 and slot 0 raise the redirect together, to the same
address. The FTQ accepts it (`ok_redir_p3`,
`rtl/core/frontend/ftq/rtl/ftq_shadow.sv` lines 220 and 221) and the
next request starts there (arm 3 of `ftq_npc.sv`, line 338).

In the waveform, the first redirect from slot 1 is at cyc 95. One cycle
earlier, at p2, the `tage_p2` group shows
`tb.dut.u_bpu.u_tage.u_tage_cntrl.tage_pred_meta_p2.[1].tage_prm_comp`
0 (T0 is the provider) with `.tage_pred_tkn` 0, so slot 1 is predicted
not taken. At cyc 95, in the `sc_p3` group,
`tb.dut.u_bpu.w_sc_hit_p3.[1]` is 1 and `tb.dut.u_bpu.w_taken_p3.[1]`
is 1: SC predicts B taken. In the `bp_cluster_p3` group
`tb.dut.bpu_slot_p3.[1].pred_src` is PRED_SC. Both
`tb.dut.bpu_redir_p3.[1].valid` and `.[0].valid` are 1, with
`target_pc` 0x8000_001C, B's target.

At cyc 136, TAGE's provider for slot 1 is T2 with CTR 3'b100, weakly
taken (`tage_prm_comp` 2, `tage_prm_ctr` 3'b100 at cyc 135); SC
predicts not taken, and the redirect is to 0x8000_0020, the block's
fall-through.

### 3.3 The reversals in the run

There are 12 p3 redirects in the run, all for the block at top:

```
cyc                         slot   p2 direction   p3 direction   target
44, 51                      0      not taken      taken          0x8000_0014
95, 104                     1      not taken      taken          0x8000_001C
100, 136, 144, 163, 171,    1      taken          not taken      0x8000_0020
214, 263, 312
```

The two reversals of slot 0 are early in the run, while SC is still
learning: they reverse A, which is never taken, and the backend
corrects them (a redirect to 0x8000_0012 at cyc 56). The backend's
last misprediction of B is at cyc 125 (a redirect to 0x8000_001A).
After it, each of SC's seven reversals of B replaces a wrong TAGE
direction with the right one, so none is followed by a backend
redirect.

RTL: the SC hit for slot s is `w_sc_hit_p3[s]`, `bp_cluster.sv` lines
1272 and 1273; the monitor counts are `n_sc_s1` and `n_sc_s0` in
`tb/fe_demo_mon.svh` lines 585 to 596.

---

## 4. Events

| cyc | Event                                           | Other            |
|-----|-------------------------------------------------|------------------|
| 0   | reset released (`tb.rstn`); the FTQ requests    | fast init        |
|     | 0x8000_0000 the same cycle                      |                  |
| 21  | first backend misprediction, the back edge;     | pass 0           |
|     | redirect to 0x8000_0008                         |                  |
| 24  | first p2 group for the block at top with both   | A slot 0, B      |
|     | slots: A and B, `pred_src` PRED_TAGE            | slot 1           |
| 36  | A mispredicted; redirect to 0x8000_0012         | backend          |
| 44  | first p3 redirect: SC reverses A in slot 0      | to 0x8000_0014   |
| 95  | first p3 redirect from slot 1: SC reverses B    | to 0x8000_001C   |
|     | from not taken to taken                         |                  |
| 100 | SC reverses B from taken to not taken           | to 0x8000_0020   |
| 125 | last backend misprediction of B; redirect to    | backend          |
|     | 0x8000_001A                                     |                  |
| 136 | SC corrects TAGE's taken for B, provider T2     | to 0x8000_0020   |
| 375 | back edge falls through, a misprediction;       | pass 47          |
|     | redirect to 0x8000_0030                         |                  |
| 386 | the run ends                                    |                  |
