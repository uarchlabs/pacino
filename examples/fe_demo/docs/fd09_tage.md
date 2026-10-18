<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd09_tage: TAGE Provider, Allocation and use_alt_on_na
```
 FILE:    fd09_tage.md
 SOURCE:  DOC-001, DOC-002, DOC-003, session-080, DOC-006
 STATUS:  WORKING
 UPDATED: 2026-10-17
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

The scenario runs on the one-slot model, built with one prediction
slot per fetch block (`SCEN_2S` in the `Makefile`). When the scenario
passes, it prints one line. This is the line from a run on 2026-10-17,
the run the cyc values below come from:

```
-I: fd09_tage: PASS, tagged-provider predictions 253, allocations 209,
    T0 by use_alt_on_na 75, cyc 3567
```

The testbench monitor, `tb/fe_demo_mon.svh` lines 435 to 459, samples
every prediction slot on every cycle and keeps the three counts in the
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
took 3567 cycles.

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

The front end predicts one branch in each prediction slot of a fetch
block, and TAGE keeps separate state for each slot. This model has one
slot. A prediction moves through four stages, p0 to p3. The FTQ
presents the request at p0, and TAGE delivers its prediction at p2.
In this program B is the first branch of the block that starts at top,
so B is always predicted and updated in slot 0.

The back edge is the second conditional of that block, and with one
slot the block has no place for it. When TAGE predicts B not taken and
B is not taken, fetch runs on past the back edge, and the backend
resolves the back edge as a misprediction (a redirect to 0x8000_0008).
The back edge has no slot of its own in that FTQ entry. The FTQ places
its resolution in slot 0, B's slot, and trains TAGE from B's metadata
(`place_slot`, `rtl/core/frontend/ftq/rtl/ftq_resolve.sv` lines 279 to
293). This happens on 101 of the 256 iterations. On those iterations
the back edge's update carries B's table index and tag, and its
direction, taken, is written into B's entries. On the other iterations
a redirect starts a new block before the back edge. The back edge is
then the first branch of its block and is updated with its own
metadata, still in slot 0.

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

Over the run TAGE mispredicted B on 144 of the 256 iterations: on 15
of the 33 iterations on which B was taken, and on 129 of the 223 on
which it was not. Each of the 144 wrote an allocation. The other 65
allocations of the result line come from the back edge's updates. TAGE
mispredicted the back edge 64 times when it was taken and once when it
fell through on iteration 255. Each of these 65 wrote an allocation.
The allocations by table:

```
             T1   T2   T3   T4   total
B            14   26   69   35     144
back edge    10   12   28   15      65
```

On the two-slot model, where the back edge
has a slot of its own in B's block, TAGE mispredicted B on 64
iterations and the back edge once, for 65 allocations (the figures
this description gave before DOC-006).

The first taken B is on iteration 9. In the waveform, the backend
resolves it at cyc 156: `tb.bkend_ftq_redir_val` is 1 and
`tb.bkend_ftq_redir_pc` is 0x8000_0014, B's target, because the front
end fetched the fall-through. The allocation write is in the same
cycle, in the `tage_update` group:

- `tb.dut.u_bpu.u_tage.u_tage_cntrl.trx_type` is 1 and
  `tb.dut.u_bpu.u_tage.u_tage_cntrl.tage_upd_val_u0` is 1: the TAGE
  tables take a slot 0 update this cycle. `trx_type` is an encoded
  field, 0 for a prediction cycle and 1 for an update cycle: it is the
  arbiter's grant (`tage_arb.sv` line 76), an input of `tage_cntrl.sv`
  (line 58), and the encoding is stated at
  `rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv` line 314;
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

TAGE keeps a 4-bit counter, `uaon`, for each prediction slot; on this
model there is one, `tb.dut.u_bpu.u_tage.u_tage_cntrl.uaon.[0]`. It
measures whether,
when the provider's CTR is weak, the alternate has been more accurate
than the provider. The rules are in
`planning/arch/tage_cntrl_uaon_update_rules.md`: on an update whose
prediction was weak, the counter increments when the provider was
wrong and the alternate right, and decrements when the provider was
right and the alternate wrong. It starts at 0.

`uaon` is updated only when both the provider and the alternate are
tagged tables. When the alternate is T0, `uaon` is unchanged. The
counter is therefore trained on predictions where two tagged tables
matched. B's updates and the back edge's are all slot 0 updates, so
both train `uaon.[0]`.

The history leading up to B is random, so the entries allocated for B
are later matched under histories they were not trained on. Those
entries are still weak, at CTR 3'b011 or 3'b100, and some predict
taken for a branch taken only one time in eight. The table counts the
updates that had a tagged provider, a tagged alternate and a weak
prediction, by the provider and alternate tables and by what the
update did to `uaon`. It increments when the provider was wrong and
the alternate right, decrements when the provider was right and the
alternate wrong, and is unchanged when the two predicted the same
direction.

```
             T2 over T1   T3 over T2   increment   decrement   unchanged
B                    45           20          32           5          28
back edge            20           10           1          18          11
```
The update inputs are in the `tage_update` group:
`tage_upd_inp_u0.[0].tage_pred_meta.tage_prm_comp`, `.tage_alt_comp`,
`.tage_pred_weak`, `.tage_prm_tkn` and `.tage_alt_tkn` under
`tb.dut.u_bpu.u_tage.u_tage_cntrl`.

In the waveform, `uaon.[0]` first increments at cyc 145, reading 1
after B's update of cyc 144. The back edge's update of cyc 145 is made
with B's metadata. Its provider, T2, predicts taken. Its alternate, T1,
predicts not taken. The back edge was taken, so the provider was
right, and `uaon` reads 0 again at cyc 146. It reaches 8 at cyc 1364.
Its highest value in the run is 12, first at cyc 3320, below the
counter's maximum of 15.

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
is at cyc 1392, in slot 0, for the block at top. In the `tage_p2`
group,
`tb.dut.u_bpu.u_tage.u_tage_cntrl.tage_pred_meta_p2.[0].tage_prm_comp`
is 1 (T1 matched B) and `.tage_prm_ctr` is 3'b100, weak;
`.tage_using_primary` is 0 and `.tage_alt_comp` is 0, so the
prediction is T0's. Of the 75 such predictions in the run, 70 have T1
as the provider. Of the other five, four have T3 and one T4. 63 are
for the block at top; the others are TAGE answers for blocks on a
wrong path, which the monitor counts as well.

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
| 23   | first FTB hit at p2, the block at 0x8000_0008: | slot 0 B; the    |
|      | TAGE's direction first used, B predicted taken | back edge in no  |
|      | (`pred_src` PRED_TAGE)                         | slot, iteration 1|
| 34   | that prediction wrong: B not taken; first      | iteration 1      |
|      | backend misprediction of B; redirect to        |                  |
|      | 0x8000_0012                                    |                  |
| 119  | first prediction from a tagged table           | table T1, slot 0 |
| 145  | `uaon` first increments, 0 to 1; the back      | slot 0           |
|      | edge's update, with B's metadata, takes it     |                  |
|      | back to 0 at cyc 146                           |                  |
| 156  | first taken B resolved, a misprediction;       | iteration 9      |
|      | redirect to 0x8000_0014; its allocation write  | table T1, slot 0 |
| 1364 | `uaon` reaches 8                               | slot 0           |
| 1392 | first prediction from T0, by use_alt_on_na     | provider T1,     |
|      |                                                | slot 0           |
| 3556 | back edge falls through, a misprediction;      | iteration 255    |
|      | redirect to 0x8000_001A                        |                  |
| 3567 | the run ends                                   |                  |
