<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd09_tage: TAGE Provider, Allocation and use_alt_on_na
```
 FILE:    fd09_tage.md
 SOURCE:  DOC-001, DOC-002, DOC-003, session-080
 STATUS:  WORKING
 UPDATED: 2026-10-15
 CONTACT: Jeff Nye
```

## 1. What the scenario shows

`fd09_tage` is the FD-9 scenario of the front-end demonstration. It
shows three behaviours of the pacino TAGE predictor: a prediction
supplied by a tagged table, the allocation of a new tagged entry after
a misprediction, and the use_alt_on_na mechanism handing a prediction
from a weak tagged entry to the base table T0. The scenario runs a
loop whose body contains a conditional branch with a random direction.
The predictors cannot learn that branch, so it mispredicts often, and
the mispredictions drive the allocations and the use_alt_on_na
counter. demo_explainer.md describes how a scenario is built and run,
and defines the terms used here.

When the scenario passes, it prints one line. This is the line from a
run on 2026-10-15, the run the cyc values below come from:

```
-I: fd09_tage: PASS, tagged-provider predictions 216, allocations 65,
    T0 by use_alt_on_na 37, cyc 1277
```

The testbench monitor, `tb/fe_demo_mon.svh` lines 409 to 433, samples
both prediction slots on every cycle and keeps the three counts in the
line:

- tagged-provider predictions, the monitor variable `n_tage_prov`: TAGE
  predictions at p2 whose provider is a tagged table;
- allocations, `n_tage_alc`: new tagged entries written to the TAGE
  tables;
- T0 by use_alt_on_na, `n_t0_uaon`: TAGE predictions at p2 that come
  from T0 because use_alt_on_na passed over a weak tagged provider.

The scenario passes when the allocation count and the T0 count are
both greater than zero (`tb/fe_demo_proofs.svh` line 89), and every
instruction the testbench expects retires without error. The count of
tagged-provider predictions is reported for information only. The run
took 1277 cycles.

---

## 2. The program

The program is written by the task `prog_fd09` in
`programs/fd09_tage.svh`. It has a short prologue, a loop that runs
256 times, and a short epilogue. The loop body holds two conditional
branches. The first, labelled B below, has a random direction. The
second is the loop's back edge. The program runs in machine mode with
translation off, so the addresses are physical; it starts at the
reset vector, `RESET_VECTOR` = 0x8000_0000 (`bp_defines_pkg.sv`), and
the loop's first instruction, top, is at 0x8000_0008.

```
Address      Label  Instruction              Purpose
0x8000_0000         c.addi a0, 1             prologue filler
0x8000_0002         addi t0, t0, 1           prologue filler
0x8000_0006         c.addi a0, 1             prologue filler
0x8000_0008  top:   c.addi a0, 1             loop body filler
0x8000_000A         addi t0, t0, 1           loop body filler
0x8000_000E  B:     bne x6, x0, 0x8000_0014  random direction, see below
0x8000_0012         c.addi a0, 1             executed only when B is
                                             not taken
0x8000_0014         c.addi a0, 1             loop body filler
0x8000_0016         bne x6, x0, 0x8000_0008  back edge to top
0x8000_001A         c.addi a0, 1             epilogue filler
0x8000_001C         addi t0, t0, 1           epilogue filler
0x8000_0020         c.addi a0, 1             epilogue filler
0x8000_0022         jal x0, 0                jump to itself; the run
                                             ends here
```

The filler instructions do no useful work. They make the code a mix of
16-bit and 32-bit instructions, so the branches are not at the start
of their fetch block: in the block that starts at top, B is at
halfword position 3 and the back edge at position 7.

The program writer writes the loop body into memory once for each
iteration, at the same addresses and with the same bytes, so the code
in memory is identical on every iteration. What changes from one
iteration to the next is the list of instructions the testbench
expects to retire. When B is taken, the `c.addi` at 0x8000_0012 is
still present in memory, and the program writer leaves it out of the
expected list, because it does not execute on that iteration
(`W.cskip` in `rtl/core/frontend/fe_top/tb/models/fe_tb_writer.svh`
writes it in dry mode).

The direction of each branch is decided by the program writer when it
writes the iteration, and is recorded in the expected list. The
backend model of the testbench resolves each branch with the recorded
direction (demo_explainer.md, the backend model). The value in
register x6 is never used. The branch instructions compare x6 with x0
only because a branch instruction needs two operands.

Branch B is taken on a given iteration when three bits drawn from the
program writer's pseudo-random generator are all 1. The generator is
a 16-bit Galois linear-feedback shift register with taps 0xB400 and
seed 0xACE1 (`W.lfsr` and `W.lfsr_bit` in `fe_tb_writer.svh`; the seed
is set in `prog_fd09`). The local variable `tk` in `prog_fd09` holds
the result. Each draw is close to an even chance, so B is taken on
about one iteration in eight. With this seed B is taken on 33 of the
256 iterations. Numbered from 0, the first taken iterations are 9, 16,
19, 22, 30 and 31.

The back edge is taken on iterations 0 to 254 and falls through on
iteration 255, so its pattern is regular and the predictors learn it.

---

## 3. Walkthrough

Pacino's TAGE has a base table, T0, and four tagged tables, T1 to T4,
with increasing history lengths (8, 13, 32 and 119 branch outcomes).
T0 holds a 2-bit counter per entry and always produces a prediction. A
tagged table produces a prediction only when its tag matches. Each
tagged entry holds a 3-bit direction counter, CTR. The provider is the
tagged table with the longest history that matches. The alternate is
the next longest matching table, or T0 when no other tagged table
matches.

The front end predicts up to two branches in each fetch block, one in
each of two prediction slots, and TAGE keeps separate state for each
slot. A prediction moves through four stages, p0 to p3. The FTQ
presents the request at p0, and TAGE delivers its prediction at p2.
In this program B is the first branch of the block that starts at top,
so B is always predicted and updated in slot 0.

### 3.1 Allocation

TAGE trains on its own prediction, whatever direction the front end
finally used. When a conditional branch resolves, the FTQ's update
conversion compares the TAGE direction carried with the branch with
the resolved direction, and marks a TAGE misprediction when they
differ. On a TAGE misprediction, when the provider is not T4, TAGE
writes a new entry for the branch in a table with a longer history
than the provider's. The table was chosen when the branch was
predicted: the first longer-history table whose entry at the branch's
index has an aged useful counter of 0. The new entry holds the
branch's tag and starts at CTR 3'b100, the weakest taken value.

T0's entries start at 2'b10, weakly taken, so until T0 has learned B,
TAGE predicts B taken. The first allocation is at cyc 19, for B on
iteration 0: B was not taken and T0 had predicted it taken. The front
end's final prediction for B was not taken, so the backend saw no
misprediction there; the allocation comes from TAGE's misprediction
alone.

Over the run TAGE mispredicted B on 64 of the 256 iterations: on 31 of
the 33 iterations on which B was taken, and on 33 of the 223 on which
it was not. Each of the 64 wrote an allocation: 16 into T1, 14 into
T2, 25 into T3 and 9 into T4. The 65th allocation of the result line
is for the back edge, which TAGE mispredicted once, when it fell
through on iteration 255.

The first taken B is on iteration 9. In the waveform, the backend
resolves it at cyc 52: `tb.bkend_ftq_redir_val` is 1 and
`tb.bkend_ftq_redir_pc` is 0x8000_0014, B's target, because the front
end fetched the fall-through. The allocation write follows at cyc 60,
in the `tage_update` group:

- `tb.dut.u_bpu.u_tage.u_tage_cntrl.trx_type` is 1 and bit 0 of
  `tb.dut.u_bpu.u_tage.u_tage_cntrl.tage_upd_val_u0` is 1: the TAGE
  tables take a slot 0 update this cycle;
- `tb.dut.u_ftq.u_upd_conv.lp_upd_p0.[0].pc` is 0x8000_000E, B's
  address (the TAGE update input has no address; the update
  conversion forms every predictor's update from one record, and the
  loop predictor's copy carries it);
- `tb.dut.u_bpu.u_tage.u_tage_cntrl.tage_upd_inp_u0.[0].cond_mispredict`
  is 1 and `.resolved_taken` is 1; `.tage_pred_meta.tage_prm_comp` is
  0, so T0 was the provider;
- `tb.dut.u_bpu.u_tage.u_tage_cntrl.u_alc_wr.[0]` is 1 and
  `tb.dut.u_bpu.u_tage.u_tage_cntrl.u_alc_comp.[0]` is 1:
  the new entry is written into T1.

RTL: the TAGE misprediction is `cond_mispredict`, set in
`rtl/core/frontend/ftq/rtl/ftq_upd_conv.sv` line 218. The candidate
table is chosen at p1 in `pred_logic`,
`rtl/core/frontend/bpu/rtl/tage_cntrl.sv` lines 574 to 585. The
allocation is formed by `alc_upd_comb` in `tage_cntrl.sv` line 853,
signal `u_alc_wr`. T0's starting value is `TAGE_T0_SRAM_INIT_VALUE`,
`rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv` line 400.

### 3.2 Training the use_alt_on_na counter

TAGE keeps a 4-bit counter, `uaon`, for each prediction slot,
`tb.dut.u_bpu.u_tage.u_tage_cntrl.uaon.[0]` and
`tb.dut.u_bpu.u_tage.u_tage_cntrl.uaon.[1]`. It measures whether,
when the provider's CTR is weak, the alternate has been more accurate
than the provider. The rules are in
`planning/arch/tage_cntrl_uaon_update_rules.md`: on an update whose
prediction was weak, the counter increments when the provider was
wrong and the alternate right, and decrements when the provider was
right and the alternate wrong. It starts at 0.

`uaon` is updated only when both the provider and the alternate are
tagged tables. When the alternate is T0, `uaon` is unchanged. The
counter is therefore trained on predictions where two tagged tables
matched B. Since B is always in slot 0, only `uaon.[0]` changes in
this run; `uaon.[1]` stays 0.

The history leading up to B is random, so the entries allocated for B
are later matched under histories they were not trained on. Those
entries are still weak, at CTR 3'b011 or 3'b100, and some predict
taken for a branch taken only one time in eight. In this run 34
updates of B had a tagged provider, a tagged alternate and a weak
prediction: 20 with T2 as the provider and T1 as the alternate, 14
with T3 and T2. On 21 of them the provider predicted taken, B was not
taken, and the alternate was right, so `uaon` incremented. On 3 the
provider was right and the alternate wrong, so it decremented. On the
other 10 the two predicted the same direction, and it was unchanged.
The update inputs are in the `tage_update` group:
`tage_upd_inp_u0.[0].tage_pred_meta.tage_prm_comp`, `.tage_alt_comp`,
`.tage_pred_weak`, `.tage_prm_tkn` and `.tage_alt_tkn` under
`tb.dut.u_bpu.u_tage.u_tage_cntrl`.

In the waveform, `uaon.[0]` first increments at cyc 221, reading
1 after the update of cyc 220; it falls back to 0 at cyc 238, and
reaches 8 at cyc 447. It reaches 15, its maximum, at cyc 620.

RTL: the update is `uaon_upd_ff` in `tage_cntrl.sv` line 380, and the
condition that both tables are tagged is at lines 383 and 384
(`u_prm_tagged` and `u_alt_tagged`, defined at lines 670 and 671).

### 3.3 T0 provides through use_alt_on_na

When `uaon` reaches 8, its top bit is set. From then on, a prediction
whose provider is a tagged table with a weak CTR uses the alternate
instead of the provider. When no second tagged table matched, the
alternate is T0, and the prediction comes from T0.

The counter that allows T0 to provide is trained only on predictions
where the alternate was a tagged table, as section 3.2 describes. It
then governs predictions where the alternate is T0. This follows the
update rule in tage_cntrl_uaon_update_rules.md.

In the waveform, the first prediction from T0 through use_alt_on_na
is at cyc 460, in slot 0. In the `tage_p2` group,
`tb.dut.u_bpu.u_tage.u_tage_cntrl.tage_pred_meta_p2.[0].tage_prm_comp`
is 1 (T1 matched B) and `.tage_prm_ctr` is 3'b100, weak;
`.tage_using_primary` is 0 and `.tage_alt_comp` is 0, so the
prediction is T0's. All 37 such predictions in the run are in slot 0
with T1 as the provider.

RTL: the selection is in `pred_logic` in `tage_cntrl.sv`: the trigger,
a tagged provider with a weak CTR, at lines 529 to 533, and the choice
of the alternate when the trigger is set and `uaon[s][3]` is 1 at line
539. The result is registered into `tage_pred_meta_p2` by
`meta_p2_ff` at line 364.

---

## 4. Events

| cyc  | Event                                          | Other            |
|------|------------------------------------------------|------------------|
| 0    | reset released (`tb.rstn`); the FTQ requests   | readies already  |
|      | 0x8000_0000 the same cycle                     | high, fast init  |
| 2    | first TAGE response at p2: `r_val_p2` and      | unused: FTB miss |
|      | `w_tage_pred_rdy_p2`                           |                  |
| 19   | first allocation write, B not taken, predicted | table T1, slot 0 |
|      | taken by T0                                    | iteration 0      |
| 20   | first backend misprediction, back edge;        | iteration 0      |
|      | redirect to 0x8000_0008                        |                  |
| 23   | first FTB hit at p2, the block at 0x8000_0008: | slot 0 B, slot 1 |
|      | TAGE's direction first used, B predicted taken | back edge        |
|      | (`pred_src` PRED_TAGE)                         | iteration 1      |
| 34   | that prediction wrong: B not taken; first      | iteration 1      |
|      | backend misprediction of B; redirect to        |                  |
|      | 0x8000_0012                                    |                  |
| 52   | first taken B resolved, a misprediction;       | iteration 9      |
|      | redirect to 0x8000_0014                        |                  |
| 60   | allocation for that B                          | table T1, slot 0 |
| 97   | first prediction from a tagged table           | table T1, slot 0 |
| 221  | `uaon` first increments, 0 to 1                | slot 0           |
| 447  | `uaon` reaches 8                               | slot 0           |
| 460  | first prediction from T0, by use_alt_on_na     | provider T1,     |
|      |                                                | slot 0           |
| 1266 | back edge falls through, a misprediction;      | iteration 255    |
|      | redirect to 0x8000_001A                        |                  |
| 1277 | the run ends                                   |                  |
