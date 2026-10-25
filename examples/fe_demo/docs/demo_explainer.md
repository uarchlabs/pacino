<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# How a Demonstration Scenario Is Built and Run
```
 FILE:    demo_explainer.md
 SOURCE:  DOC-003, session-080, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

This document explains, once, the parts every scenario description in
`docs/` relies on: the program writer, the list of instructions the
testbench expects to retire, the backend model, the result line and the
proof, and the cycle counter `cyc`. It ends with a glossary of the
front-end terms the descriptions use. A description refers here for
these subjects and does not repeat them.

Paths are relative to the repository root unless they begin with
`tb/`, `programs/`, `waves/` or `docs/`, which are relative to
`examples/fe_demo/`. The shared testbench models are in
`rtl/core/frontend/fe_top/tb/models/`, called `models/` below.

---

## 1. What a scenario is

A scenario is one short program run on the pacino front end, `fe_top`,
to make one behavior visible in a waveform. The scenarios are listed
in `planning/showcase/fe_demo_scenarios.md` as FD-1 to FD-24. Each has
a make target named `fdNN_<name>`, for example `fd09_tage`, and three
files of its own:

- `programs/fdNN_<name>.svh`, the task `prog_fdNN` that writes the
  program into the memory model and starts the run;
- `waves/fdNN_<name>.sucl`, the Surfer command file: the signals,
  their groups and formats, and the event markers;
- `docs/fdNN_<name>.md`, its description.

The testbench top is `tb/tb_fe_demo.sv`, module `tb`. It instantiates
`fe_top` as `tb.dut` and the page table walker beside it as
`tb.u_ptw`. The plusarg `+SCEN=<name>` selects the scenario;
`run_scen` in `tb/tb_fe_demo.sv` calls its `prog_fdNN` task.

The `Makefile` builds this top twice, as two simulation models that
differ only in the number of prediction slots per fetch block,
`NUM_PRED_SLOTS` (the glossary's prediction slot). The default model,
in `obj_fe_demo/`, has one slot, so each fetch block predicts one
branch. The second, in `obj_fe_demo_2slot/`, has two, the package
default. A scenario runs on one of them. FD-3 and FD-22 to FD-24 need
a second slot and run on the two-slot model (`SCEN_2S` in the
`Makefile`); every other scenario runs on the one-slot model.
Its description says which. `make fdNN_<name>` builds the scenario's
model if needed and runs it; the output is `out/fdNN_<name>/` for
either model.

A run has four steps, all in `tb/fe_demo_lib.svh` or the program task:

1. `begin_scen` prints the start line, resets every model and monitor
   (`models_reset` in `models/fe_tb_backend.svh`, `mon_reset` in
   `tb/fe_demo_mon.svh`) and holds `fe_top` in reset.
2. The program task writes the program and the expected list (sections
   2 and 3).
3. `demo_go` writes the final instruction, releases reset
   (`release_reset` in `models/fe_tb_backend.svh`) and runs until every
   expected instruction has retired, a stream error count reaches 20 or
   a cycle limit passes. It then stops taking instructions from decode
   and lets the front end run for 100 more cycles, which no monitor
   counts.
4. The top evaluates the scenario's proof and prints the result line
   (section 5).

---

## 2. The program writer

The program writer is the class `pw_c` in `models/fe_tb_writer.svh`;
its one object is `W`, declared at the end of that file. The writer
owns three things: the memory image, the address map and the expected
list.

The memory image is a byte array indexed by physical address,
`W.mem`. The memory model, `models/fe_tb_mem.svh`, answers the
instruction cache's line requests and the walker's page table reads
from it.

The address map is set by the program task. A scenario in machine
mode with translation off uses physical addresses directly. A scenario
under Sv39 translation maps each 4 KiB page with `W.map4k`, or with
`W.map4k_pbmt` when the page needs a memory type other than the
default, and the writer builds the page tables in the memory image.

The writer keeps a write cursor, `W.wp`, a virtual address. Each
emitter task writes one instruction at `W.wp`, appends it to the
expected list and advances `W.wp`:

| Task             | Writes                                              |
|------------------|-----------------------------------------------------|
| `W.i16()`        | `c.addi a0, 1`, a 16-bit filler instruction         |
| `W.i32(w)`       | the 32-bit instruction `w`                          |
| `W.mixed(n)`     | `n` fillers: `c.addi`, `addi t0, t0, 1`, `c.addi`,  |
|                  | repeating                                           |
| `W.bcc(tk, t)`   | `bne x6, x0, t`, taken when `tk` is 1               |
| `W.cskip(tk, n)` | a `bne` that, when taken, skips the `mixed(n)` after |
|                  | it                                                  |
| `W.jal(rd, t)`   | `jal rd, t`                                         |
| `W.halt()`       | `jal x0, 0`, a jump to itself; the program ends here |

The program decides each branch's direction when it writes the branch.
A program that repeats a loop body writes the body once per iteration,
setting `W.wp` back to the loop's first address each time. The bytes
written are the same on every iteration, so the code in memory does
not change. What differs between iterations is the expected list.

Code that the program places in memory but that does not execute on a
given iteration is written in dry mode (`W.dry` set): the emitters
write memory and append nothing to the expected list. `W.cskip` uses it
for the instructions a taken branch skips.

For a branch that the predictors cannot learn, the writer has a 16-bit
Galois linear-feedback shift register, `W.lfsr`, stepped by
`W.lfsr_bit()`. Each call returns the register's low bit and shifts
the register right by one. When the returned bit was 1, the shifted
value is combined with the tap mask `16'hB400` by exclusive OR. The
program sets the starting value.

---

## 3. The expected list

The expected list is the array `W.ex`, with `W.ne` entries, in the
order the instructions execute. Each entry (type `ex_t` in
`models/fe_tb_writer.svh`) holds the instruction's address, its 32-bit
form (a 16-bit instruction is stored expanded), whether it is 16-bit,
its control-transfer type, its direction and its target. A fetch fault
or a trap the program expects is an entry too.

The testbench does not model the instruction set. The expected list is
the reference: an instruction retires correctly when it is the next
entry. The value in a register is never computed, which is why a
branch can compare `x6` with `x0` and still go either way: its
direction is the one recorded in its entry.

---

## 4. The backend model

The backend model is the process `backend` in
`models/fe_tb_backend.svh`. It stands in for an in-order processor
backend and drives the front end's backend ports.

Each cycle it may accept decode's output, `tb.pd_out`, up to eight
instructions, by raising `tb.dec_ibuf_rdy`. It compares each accepted
instruction's address with the next expected entry, `W.ex[ep]`, where
`ep` counts the entries retired so far. A match retires the entry.

A control transfer is checked by the instruction that follows it. When
the next instruction delivered is the expected one, the prediction was
right, and the backend sends a resolution for the branch on
`tb.bkend_ftq_rsv` with `bkend_ftq_rsv_val`. When it is not, the
front end fetched down the wrong path: the backend sends a resolution
marked as a misprediction, discards the rest of the delivered group,
and raises a redirect, `tb.bkend_ftq_redir_val`, with
`bkend_ftq_redir_pc` the expected address and `bkend_ftq_redir_cause`
0 (`RC_MISPREDICT`). The front end flushes the younger work and fetches
from that address. This is the backend misprediction a description
refers to; its cycle is the cycle `bkend_ftq_redir_val` is high.

The backend also commits fetch target queue entries whose instructions
have all retired (`tb.bkend_ftq_commit_val`, `bkend_ftq_commit_idx`).
Any other mismatch, for example an instruction with the wrong encoding,
is a stream error: it increments `n_err` and prints a line that begins
`ERROR:` (section 5).

The plusarg `+TRACE` makes the backend print a line for each retired
instruction and each misprediction, with the cycle count first. These
lines are for debugging and do not follow the result-line format.

---

## 5. The result line and the proof

Each scenario has a proof: a condition on counts taken from the design
during the run, which shows that the behavior occurred. The counts are
kept by the monitors in `tb/fe_demo_mon.svh`, which sample design
signals at every rising clock edge while the measurement window,
`tb.meas`, is open. The window opens at the release of reset and
closes when the last expected instruction retires. The proofs are the
function `proof` in `tb/fe_demo_proofs.svh`.

A run passes when every expected instruction retired with no stream
error and the proof holds. It prints one result line and exits with
status 0. Otherwise it prints a failing result line and exits non-zero,
which stops `make scenarios`.

Every line the testbench prints follows one format
(`planning/testbenches/fe_demo_tb_decisions.md` FDT-10 and FDT-10a). A
line begins with `-I:` (information), `-W:` (warning) or `-E:`
(error), then the scenario name and a colon. The items after it are
separated by commas. A line is at most 80 columns; a longer message
continues on lines indented four spaces. The result line gives PASS or
FAIL, then the counts the proof read, then the cycle count:

```
-I: fd09_tage: PASS, tagged-provider predictions 188, allocations 59,
    T0 by use_alt_on_na 22, cyc 1364
```

When the expected instructions did not all retire, the failing line
says so first:

```
-E: fd09_tage: FAIL, stream not retired, retired 1200 of 1510,
    stream errors 1, ...
```

The final `cyc` is the number of cycles from the release of reset to
the last retirement.

Two kinds of line are outside this format. The shared models print
`ERROR:` lines for stream errors and the `+TRACE` lines; they are in
`models/`, shared with `tb_fe_top`, and keep that testbench's format.
On a failure, the simulator prints the lines of the SystemVerilog
`$fatal` call after the result line.

---

## 6. The cycle counter cyc

`tb.cyc` is an integer in `models/fe_tb_dut.svh`. It is 0 while reset
is asserted and increases by one at every rising clock edge after the
release of reset. Every save file and Surfer file shows it next to the
clock, so a waveform position can be given as a value of `cyc`.

A description says an event happens "at cyc N" when the signal it
names has that value during the clock period in which `tb.cyc` shows
N. That is also the value a register or a monitor samples at the end
of that period. A register written in that period shows its new value
from cyc N + 1.

---

## 7. Reading the waveforms

`make view S=<scenario>` opens the scenario's waveform in Surfer
with its command file (`README.md`, section 2). The signals are
grouped by unit in pipeline order, the clock group first. Surfer
shows each name with its name type Unique: the shortest end part
of the hierarchical path that tells the signal apart from the
others shown, after an ellipsis when the path is shortened. For
example `tb.dut.u_bpu.u_tage.u_tage_cntrl.uaon.[0]` is shown as
`...uaon.[0]` (the ellipsis is one character) and
`tb.dut.u_bpu.r_val_p2` as `r_val_p2`.

The descriptions give the full path in Surfer's form. Surfer
names an element of an unpacked array by its index under the
array, for example `tb.dut.u_bpu.u_tage.u_tage_cntrl.uaon.[0]`,
and a member of a structure in an array the same way, for example
`tb.dut.u_bpu.u_tage.u_tage_cntrl.tage_pred_meta_p2.[0].tage_prm_comp`.

Every signal's display format comes from one table, `FORMATS` in
`waves/fe_demo_sigs.py` (DOC-006):

- `tb.clk` is drawn as a clock; `tb.rstn` and every other 1-bit signal
  as a bit;
- a signal of an enumerated type is shown by its value names, for
  example PRED_TAGE or NO_BRANCH;
- a per-slot or per-lane mask, such as `w_tage_pred_rdy_p2` on the
  two-slot model or `ifu_ibuf_en`, in binary; on the one-slot model a
  per-slot mask is 1 bit and is shown as a bit;
- a count or an iteration number in decimal at any width, as is
  `tb.cyc`. Indices and pointers are shown in decimal as well, and so
  are positions and table numbers;
- an address or a data value in hexadecimal; a target or a PC is an
  address;
- an encoded field, such as `trx_type` or `itlb_ifu_status`, as its
  number. The descriptions that show one give its encoding.

The signal lists follow the slot count of the model: a one-slot
waveform shows slot 0 of each per-slot signal, a two-slot waveform
slots 0 and 1. A scenario whose description has an event table
(section 4) opens with one marker per event, named c<cyc>_<label>, and
the view at the first marker.

---

## 8. Glossary

Each term is given as a description uses it, with the file or signal
that implements it where there is one. Paths without a directory are in
`rtl/core/frontend/bpu/rtl/`.

**alternate (TAGE).** The table whose prediction TAGE uses in place of
the provider's when use_alt_on_na selects it: the tagged table with the
next shorter history that also matches, or T0 when no such table
matches. Its table number is `tage_alt_comp` in the prediction
metadata, 0 for T0.

**allocation (TAGE).** Writing a new entry into a tagged table after
TAGE mispredicts a conditional branch. The table is chosen at
prediction time: the first table with a longer history than the
provider's whose entry at the branch's index may be replaced, because
its useful counter, after aging, is 0. The new entry holds the branch's
tag and a CTR of 3'b100. `alc_upd_comb` in `tage_cntrl.sv`.

**back edge.** The branch at the end of a loop body that jumps back to
the loop's first instruction. It is taken on every iteration but the
last, on which it falls through.

**backend.** The part of a processor after decode, which executes and
retires instructions. In the demonstration it is the backend model
(section 4).

**base table, T0.** The TAGE table without tags, indexed by address
bits of the prediction request only. Each entry is a 2-bit counter, so
T0 always has a prediction. Its entries start at 2'b10, weakly taken.
`tage_bim.sv`.

**block, fetch block.** The unit the predictors and the fetch unit
work on: consecutive code starting at one address and covering at most
32 bytes. A block ends at the first predicted-taken control transfer.
The FTB keeps one entry per block start, and an entry holds at most
one branch per prediction slot. When a block holds more branches, its
entry ends the block at the first branch it does not hold, and the
next block starts with that branch (the split at update,
`planning/arch/ftb_decisions.md` section 3; `fd23_jump_cut`). A 32-bit
instruction that starts in the last two bytes is delivered with the
block, which then spans 34 bytes. One FTQ entry describes one block.

**BPU, branch prediction unit.** `bp_cluster.sv`, instance
`tb.dut.u_bpu`: the uBTB, FTB, TAGE, SC, ITTAGE, loop predictor and RAS,
and the logic that combines their answers at each prediction stage.

**conditional branch.** A branch that is taken or not taken according
to a comparison; in RISC-V, `beq`, `bne` and the other B-type
instructions and their 16-bit forms.

**CTR.** The direction counter of a tagged TAGE entry, 3 bits. Values
3'b100 to 3'b111 predict taken, 3'b000 to 3'b011 not taken. The two
values nearest the boundary, 3'b011 and 3'b100, are weak; 3'b000 and
3'b111 are strong; the others are medium. When an update writes an
entry's counter, the counter steps one value toward the resolved
direction.

**direction.** Whether a conditional branch is taken.

**fall through.** A branch falls through when it is not taken:
execution continues at the next instruction.

**front end.** The part of the processor that predicts, fetches and
decodes instructions and delivers them to the backend: `fe_top`,
instance `tb.dut`.

**FTB, fetch target buffer.** The predictor that records, for a block
start address, the block's end and the branches in it, with their
positions, types and targets. It answers at p2. `ftb.sv`.

**FTQ, fetch target queue.** The queue between the BPU and the fetch
unit, `tb.dut.u_ftq`. Each entry holds one predicted block. The FTQ
issues the next prediction request, takes the predictions, sends
blocks to the fetch unit, and receives resolutions, redirects and
commits from the backend. `rtl/core/frontend/ftq/rtl/ftq.sv`.

**history, global history.** The record of the directions of recent
conditional branches, kept by `bp_history.sv`. TAGE's tagged tables
index and tag their entries with the branch address combined with a
length of this history.

**history length.** The number of recent branch outcomes a tagged
table combines with the address. Pacino's T1 to T4 use 8, 13, 32 and
119 (`TAGE_TBL_HIST` in `bp_defines_pkg.sv`).

**IFU, instruction fetch unit.** `tb.dut.u_ifu`: translates a block's
address, reads its bytes from the L1I, finds the instructions in them
(predecode) and passes them to the instruction buffer.

**ITTAGE.** The predictor of indirect jump targets, built as TAGE is
but storing targets. `ittage.sv`.

**L1I.** The level-one instruction cache, `tb.dut.u_l1i`.

**LFSR, linear-feedback shift register.** A shift register whose input
is a combination of its own bits, used for a sequence of bits that
looks random. The program writer's is in section 2.

**loop predictor.** The predictor that learns a loop's trip count and
predicts the exit of the loop's back edge. `loop_pred.sv`.

**misprediction.** A prediction that differs from what the branch
does. A backend misprediction is one the backend finds when the
front end has fetched down the wrong path (section 4). A TAGE
misprediction is TAGE's own direction differing from the resolved
direction, whatever the final prediction was; TAGE trains and
allocates on it (`cond_mispredict`, set in
`rtl/core/frontend/ftq/rtl/ftq_upd_conv.sv`).

**p0, p1, p2, p3.** The prediction stages. At p0 the FTQ presents a
block's start address. At p1 the uBTB and the loop predictor answer.
At p2 the FTB, TAGE and ITTAGE answer and may replace the p1
prediction. At p3 SC answers and may replace it again. A later stage
that disagrees with an earlier one redirects the request stream.

**position.** The offset of an instruction from the start of its block,
in halfwords (2-byte units): the instruction at the block's start is
at position 0, one 6 bytes later at position 3.

**prediction metadata.** The state a predictor records with a
prediction so that the later update can use it, for TAGE
`tage_pred_meta_t` in `bp_structs_pkg.sv`: the provider and alternate
tables, their counters and directions, the allocation candidate and
whether use_alt_on_na was used. It travels with the FTQ entry and comes
back with the update as `tage_upd_inp_u0[s].tage_pred_meta`.

**prediction slot.** One of the positions in a block's prediction that each
describe one branch (`bp_ftq_slot_t` in `bp_structs_pkg.sv`). `NUM_PRED_SLOTS`
sets how many a block has, and so how many of its branches are predicted; the
slots are the branch fields of one FTB entry, slot 0 the earliest branch
(`planning/arch/fe_decisions.md` section 10). The demonstration builds one model
with one slot and one with two (section 1). TAGE keeps separate state for each
slot, such as the use_alt_on_na counter. Every branch the FTB holds is in a
slot: a branch beyond the slots starts a block of its own (block, above).

**provider (TAGE).** The tagged table with the longest history whose
entry matches the branch, or T0 when no tagged table matches. Its
table number is `tage_prm_comp` in the prediction metadata, 0 for T0;
its CTR is `tage_prm_ctr`.

**RAS, return address stack.** The predictor of return addresses.
`ras.sv`.

**redirect.** A message that restarts fetch at a new address and
discards the younger work in flight. The BPU redirects at p2 and p3,
the fetch unit after predecode, and the backend on a misprediction.

**resolution.** The backend's report of what a branch did: its
direction and target, and whether it was mispredicted
(`tb.bkend_ftq_rsv`). The FTQ turns resolutions into updates.

**retire.** Complete an instruction in program order. In the
demonstration the backend model retires an instruction when it
matches the next expected entry (section 4).

**RTL.** Register-transfer level: the SystemVerilog design source of
the processor, under `rtl/`, as distinct from the testbench.

**SC, statistical corrector.** A predictor that may reverse TAGE's
direction at p3 when its own counters disagree strongly. `sc.sv`.

**T0, T1 to T4.** The TAGE tables: T0 the base table, T1 to T4 the
tagged tables in order of increasing history length.

**tag, tag match.** A tagged table entry stores a short value formed
from the branch address and the history. The entry matches a
prediction request when its stored tag equals the request's.

**TAGE.** The direction predictor for conditional branches,
`tage.sv` with its control logic in `tage_cntrl.sv`, instance
`tb.dut.u_bpu.u_tage`. It has the base table T0 and four tagged tables
T1 to T4, and answers at p2.

**tagged table.** A TAGE table whose entries carry a tag, so an entry
answers only for the branch and history that wrote it, as far as the
tag can tell them apart.

**taken.** A branch is taken when execution continues at its target.

**uBTB, micro branch target buffer.** The small predictor that answers
at p1, `ubtb.sv`.

**update.** A write to a predictor's tables from a resolution. A TAGE
update arrives at `tage_upd_val_u0` with the prediction's metadata,
`tage_upd_inp_u0`, and is written in the cycle `trx_type` is 1.

**update conversion.** `ftq_upd_conv.sv`, instance
`tb.dut.u_ftq.u_upd_conv`: turns each resolved branch, with the
metadata stored in its FTQ entry, into the update input of each
predictor.

**use_alt_on_na.** "Use the alternate on a newly allocated entry." A
4-bit counter per prediction slot, `uaon` in `tage_cntrl.sv`, that
learns whether a weak provider or the alternate is more often right.
When its top bit is set (the value is 8 or more) and the provider is a
tagged table with a weak CTR, TAGE predicts with the alternate. It is
updated only when the provider and the alternate are both tagged
tables (`planning/arch/tage_cntrl_uaon_update_rules.md`).

**useful counter.** A 2-bit field of a tagged entry that records
whether the entry has been needed to predict correctly. It is aged: an
entry written one aging period ago counts half its value, and one
written two or more periods ago counts 0 (`ueff_p1` in
`tage_cntrl.sv`). An entry whose aged value is 0 may be replaced by an
allocation.

**weak.** A CTR value of 3'b011 or 3'b100, the two values nearest the
boundary between not taken and taken.
