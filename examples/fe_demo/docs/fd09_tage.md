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

## 0. Introduction

To reduce the volume of text the discussion below assumes a grasp of the
concepts used in branch prediction and decoupled front ends. These are
well-researched topics; some of the seminal papers include [1] [2] [3] [4].

Pacino terminology labels the prediction operation stages as p0/p1/etc and the
branch predictor update operation stages u0/u1/etc.

`examples/fe_demo/docs/demo_explainer.md` describes how each scenario is built
and run. This includes:

- test program generation, known as "the program writer" below.
- the list of instructions the testbench expects to retire
- the modeled backend abstraction
- the result line
- the cycle counter `cyc`

The scenario is executed and the waveform viewer is opened with these commands:

```
cd examples/fe_demo
make fd09_tage
make view S=fd09_tage
```

Example console output is shown below listing the number of predictions,
allocations and cycle count:

```
-I: fd09_tage: PASS, tagged-provider predictions 253, allocations 209,
    T0 by use_alt_on_na 75, cyc 3567
```

The Pacino branch predictors supports up to two predictions per fetch block.
This is controlled by a compile time parameter, NUM_PRED_SLOTS=1 or 2. To
reduce the volume of signal data and improve clarity, this scenario uses
NUM_PRED_SLOTS=1.

For reference there are two views of frontend structures: 

```
examples/fe_demo/docs/fe_block.svg   block connectivity
examples/fe_demo/docs/fe_pipe.svg    pipeline view
```

## 1. What the scenario shows

`fd09_tage` (FD-9) shows three behaviors of the Pacino TAGE predictor in
response to FTQ prediction requests at p0 and FTQ updates at u0:

1. a prediction supplied by a tagged table
2. the allocation of a new tagged entry after a misprediction
3. the use_alt_on_na mechanism handing a prediction from a weak tagged
   entry to the base table T0.

FD-9 runs a loop whose body contains a conditional branch with a random
direction. The random direction is chosen by the program writer and resolved by
the modeled backend.  With the random direction the predictor cannot learn the
branch behavior and therefore mispredicts often. These mispredictions result in
allocations and eventual trigger of the use_alt_on_na (UAON) counter.
Eventually the UAON counter causes the prediction to use the base table T0 as
the prediction source.

The testbench monitor, `tb/fe_demo_mon.svh`, supplies statistical counts for
FD-9. These are reported in the console output, shown above:

- tagged-provider predictions 
    - `n_tage_prov` in `tb/fe_demo_mon.svh`
    - TAGE predictions at p2 whose provider is a tagged table
- allocations
    - `n_tage_alc` in `tb/fe_demo_mon.svh`
    - newly allocated tagged table entries written to the TAGE tables
- T0 by use_alt_on_na
    - `n_t0_uaon` in `tb/fe_demo_mon.svh`
    - TAGE predictions at p2 that come from T0 because use_alt_on_na
      replaced the weak tagged provider.

---

## 2. The program

The program is written by the task `prog_fd09` in `programs/fd09_tage.svh`. The
structure consists of a short prologue, a loop that runs 256 times, and a short
epilogue.

The loop body holds two conditional branches.  The bne branch at 0x8000_000E has a randomized direction.  The bne branch at 0x8000_0016 returns to label top. This is the loop's
back edge

The program runs in machine mode with translation off, the addresses are
physical. The program starts at the reset vector, `RESET_VECTOR` = 0x8000_0000
(`bp_defines_pkg.sv`), and the loop's first instruction, top, is at
0x8000_0008.

```
Address      Label  Instruction                Purpose
0x8000_0000         c.addi a0, 1               ; prologue, 16b instr
0x8000_0002         addi   t0, t0, 1           ; prologue
0x8000_0006         c.addi a0, 1               ; prologue, 16b

0x8000_0008  top:   c.addi a0, 1               ; loop body, 16b
0x8000_000A         addi   t0, t0, 1           ; loop body
0x8000_000E  B:     bne    x6, x0, 0x8000_0014 ; randomized taken/not taken

0x8000_0012         c.addi a0, 1               ; executed when B is not taken

0x8000_0014         c.addi a0, 1               ; loop body, 16b

0x8000_0016         bne    x6, x0, 0x8000_0008 ; back edge to top

0x8000_001A         c.addi a0, 1               ; epilogue
0x8000_001C         addi   t0, t0, 1           ; epilogue
0x8000_0020         c.addi a0, 1               ; epilogue

0x8000_0022         jal x0, 0                jump to itself, termination
```

The c.addi and addi instructions do no useful work. They mix 16-bit and
32-bit instructions so that neither branch is at the start of its fetch
block: in the block that starts at top, B is at halfword position 3 and the
back edge at position 7.

B's direction is random so that no predictor can learn it. B mispredicts
often, and those mispredictions drive the TAGE allocations and the
use_alt_on_na counter. The direction of each branch is chosen by the program
writer and resolved by the modeled backend; the register operands play no
part. B is taken on about one iteration in eight, 33 of the 256 in this run.
Numbered from 0, the first taken iterations are 9, 16, 19, 22, 30 and 31.
When B is taken, the c.addi at 0x8000_0012 is skipped.

The back edge is taken on iterations 0 to 254 and falls through on iteration
255. Its pattern is regular, and the predictors learn it.

---

## 3. Walkthrough

Pacino's TAGE implementation uses 5 tables, T0-T4. T0 is the base predictor
which is untagged. T1 to T4 are tagged and use direction history in their
access address generation and entry matching. The tagged tables use
increasing number of history bits (length), 8, 13, 32 and 119, respectively.

T0 holds a 2-bit counter per entry and always produces a prediction.

A tagged table produces a prediction only when its tag matches. Each tagged
entry holds a 3-bit prediction counter, CTR, which encodes a predicted
direction in its MSB and a confidence value in the lower bits.

For the tagged table two predictions are possible, a 'primary' and an
'alternative' prediction. The table with the longest history that matches
the tag produces the primary prediction, the next longest matching table
is the alternative prediction or T0 when no other tagged table matches.

A prediction moves through four stages, p0 to p3. The FTQ presents the request
at p0, and TAGE delivers its prediction at p2. p3 is used when the statistical
corrector (SC) is enabled. In this scenario the SC is not enabled.

Each fetch block has NUM_PRED_SLOTS prediction slots. A slot holds one
conditional branch of the block, and TAGE predicts, updates and keeps its
use_alt_on_na counter separately for each slot. This scenario is built with
NUM_PRED_SLOTS = 1: every block has one slot, slot 0, and the per-slot TAGE
signals below are indexed [0].

The block that starts at top holds two conditional branches, B at halfword
position 3 and the back edge at position 7. B is the first, so it is always
in slot 0. The back edge has no slot in that block. What happens to it
depends on where the block at top ends:

- B predicted not taken and not taken, 101 of the 256 iterations. Nothing in
  the block predicts the back edge, so fetch continues past it and the
  backend resolves it as a misprediction, a redirect to 0x8000_0008. The FTQ
  entry has no slot for the back edge, so the FTQ places its resolution in
  slot 0 (`place_slot`, `rtl/core/frontend/ftq/rtl/ftq_resolve.sv` lines 279
  to 293). That slot holds B's metadata, so the update carries B's table
  index and tag, and the back edge's direction, taken, is trained into B's
  TAGE entries.
- Every other iteration. Fetch restarts after B, at 0x8000_0012 or
  0x8000_0014, either because B was predicted taken or because the backend
  redirected on B. The back edge is then the first branch of the new block,
  is placed in that block's slot 0, and is trained with its own metadata.

The updates of the first case are the "back edge" rows in the tables of 3.1
and 3.2. They train the same entries and the same use_alt_on_na counter as
B.

The first case is a known gap in the one-slot build. A branch that no slot
carries should end the block, so that it is predicted in the next block, as
an unslotted jump already does (BP-138). TD#179 records the fix. When it is
made, the back edge rows and the figures in this section and in section 4
change.

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

With NUM_PRED_SLOTS = 2 the back edge has its own slot in the block at top
and is always trained with its own metadata. The same program then gives 64
TAGE mispredictions of B and one of the back edge, 65 allocations in all.

The first taken B is on iteration 9. In the waveform, the backend
resolves it at cyc 156: `tb.bkend_ftq_redir_val` is 1 and
`tb.bkend_ftq_redir_pc` is 0x8000_0014, B's target, because the front
end fetched the fall-through. The allocation write is in the same
cycle, in the `tage_update` group:

- `tb.dut.u_bpu.u_tage.u_tage_cntrl.trx_type` is 1 and
  `tb.dut.u_bpu.u_tage.u_tage_cntrl.tage_upd_val_u0` is 1: the TAGE
  tables take an update this cycle. `trx_type` is an encoded
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

TAGE keeps a 4-bit counter, `uaon`, for each prediction slot. With one slot
there is one counter, `tb.dut.u_bpu.u_tage.u_tage_cntrl.uaon.[0]`. It
measures whether, when the provider's CTR is weak, the alternate has been
more accurate than the provider. The rules are in
`planning/arch/tage_cntrl_uaon_update_rules.md`: on an update whose
prediction was weak, the counter increments when the provider was wrong and
the alternate right, and decrements when the provider was right and the
alternate wrong. It starts at 0.

`uaon` is updated only when both the provider and the alternate are
tagged tables. When the alternate is T0, `uaon` is unchanged. The
counter is therefore trained on predictions where two tagged tables
matched. B and the back edge both update slot 0, so both train the one
counter.

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

# References

[1] Seznec, André, and Pierre Michaud. "A case for (partially) tagged geometric
history length branch prediction." The Journal of Instruction-Level Parallelism
8 (2006): 23.

[2] Seznec, André. "Tage-sc-l branch predictors." JILP-Championship Branch
Prediction. 2014.

[3] Reinman, Glenn, Todd Austin, and Brad Calder. "A scalable front-end
architecture for fast instruction delivery." ACM SIGARCH Computer Architecture
News 27.2 (1999): 234-245.

[4] Reinman, Glenn, Brad Calder, and Todd Austin. "Fetch directed instruction
prefetching." MICRO-32. Proceedings of the 32nd Annual ACM/IEEE International
Symposium on Microarchitecture. IEEE, 1999.
