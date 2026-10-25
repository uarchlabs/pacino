<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# How a Demonstration Scenario Is Built and Run
```
 FILE:    demo_explainer.md
 SOURCE:  DOC-003, session-080, DOC-006, DOC-007
 STATUS:  COMPLETE
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

This document explains the operation of the functions used by the scenarios:
- the program writer
- the instruction list
- the backend model
- results console status

A glossary of frontend terms is included at the end.

`examples/fe_demo/` holds the collateral files used by the scenarios.

| Full path                  | Shorthand   | Explanation    |
|----------------------------|-------------|----------------|
| `examples/fe_demo/docs`    | `docs/`     | demo descriptions               |
| `examples/fe_demo/programs`| `programs/` | scenario drivers                |
| `examples/fe_demo/tb`      | `tb/`       | demo specific testbench support |
| `examples/fe_demo/waves`   | `waves/`    | Surfer signal files             |

The shared testbench models are found in `rtl/core/frontend/fe_top/tb/models/`,
shortened to `models/` below. 

---

## 1. The scenario

A scenario exercises isolated aspects of the Pacino frontend (FE). The full
scenario list is found in `planning/showcase/fe_demo_scenarios.md`, numbered
FD-1 to FD-24. Each scenario has an associated make target in
`examples/fe_demo/Makefile`. The targets are of the form `fdNN_<name>`.

A scenario has three files, the "program", the wave control file and the writeup:

- `programs/fdNN_<name>.svh`
    - contains the task `prog_fdNN` which populates the models memory
      and begins exectution.
    - In the demos there is no assembly step, the instructions are
      written to model memory directly as instruction words.
- `waves/fdNN_<name>.sucl`
    - this is Surfer command file: containing signals, groups and markers
    - Events in the waveforms are annotated using these markers. The
      markers are also described in the scenario description.
- `docs/fdNN_<name>.md`
    - the scenario description.

A run has four steps:

1. `begin_scen` prints the start line, resets all models and the monitors.
2. The program task writes the program and the expected instruction list 
   to the model memory.
3. `demo_go` releases reset and runs until every expected instruction 
   has retired. The pipeline runs for a number of cycles to allow the 
   pipeline to flush.
4. The top level evaluates the scenario's correctness and prints the results.

The scenario top level testbench is `tb/tb_fe_demo.sv`. This testbench
instantiates the FE as `fe_top`, and the page table walker. 

The plusarg `+SCEN=<name>` selects the scenario and `run_scen` in
`tb/tb_fe_demo.sv` calls its `prog_fdNN` task.

There are two simulation models, based on the number of prediction slots
selected. `NUM_PRED_SLOTS` selects 1 or 2 prediction slots. Pacino's FE
runs either.

`NUM_PRED_SLOTS`=1 is used for the simpler explanations to reduce amount of
data and the number of signals that much be recorded.

Full performance, `NUM_PRED_SLOTS`=2, scenarios are included to show dual
prediction operation. `NUM_PRED_SLOTS`=2 is configuration used for performance
analysis.

FD-3, FD-22, FD-23 and FD-24 run the dual prediction model.

---

## 2. The program writer

The program writer builds the memory image and the expected execution list.

The memory image is a byte array indexed by physical address. The expected
execution list is the sequence of instructions the program retires, in order.
The backend model checks each retired instruction against the list (section 3).

The memory model services instruction cache line requests from the memory
image. The page table walker reads from this image.

Scenarios run either in machine mode with physical addresses or in supervisor
mode under Sv39 translation. For the Sv39 scenarios, the writer also builds the
page tables in the memory image. FD-15 also uses two-stage (guest) translation.

The program writer includes tasks which emit either 16b or 32b instructions.
The writer emits either "filler" or "active" instructions.

The filler instructions serve to position an active instruction at a particular
PC. The PCs are varied to set up configurations which illustrate operation of
the frontend.

The active instructions are branches or jumps, plus `fence.i`, `cbo.inval` and
a store used in FD-13 and FD-19. Filler instructions are variations of addi.
The emitters write filler instructions and branches/etc; `demo_go` terminates
each program with an instruction which jumps to itself, a halt.

The memory image is written before reset is released.

The writer appends each instruction to the expected execution list only if it executes.
Instructions skipped by a taken branch are in the memory image but not in the
execution list, and a loop appears in the list once per iteration.

Each branch's direction is set by the program when it writes the branch.
Register values are never computed (section 3), so a branch's comparison has
no effect on its direction: the testbench controls the taken/not taken
decision of a branch.

In FD-09 and FD-11 some branch directions are randomized in order to illustrate
predictor behavior under those conditions; the testbench uses an LFSR to
randomize the taken/not taken state.

---

## 3. The expected execution list

The testbench does not model the instruction set. The expected execution list
is the reference instead. This list contains the instructions the program
retires, in order. The backend model retires an instruction when it matches
the next entry (section 4).

Each entry holds the instruction's address and encoding, its control-transfer
type, its direction and its target. A fetch fault or a trap the program expects
is also an entry. The entry type is `ex_t` in `models/fe_tb_writer.svh`.

---

## 4. The backend model

The backend is an abstract model. It does not execute instructions. The backend
model accepts up to 8 instructions from the frontend via decoder port
`tb.pd_out` and checks these instructions against the expected execution list
and retires them in order.  The backend model raises `tb.dec_ibuf_rdy` when it is ready to accept more instructions.

A prediction determines which instruction the frontend fetches after a branch
or jump. The model checks the prediction by comparing the next instruction
delivered with the next entry in the expected execution list.

If they match, the prediction was correct, and the model reports the branch's
outcome, its direction and target, to the FTQ on `tb.bkend_ftq_rsv`.

If they do not match, the frontend has fetched down the wrong path. The backend
model reports the outcome marked as a misprediction, discards the rest of the
delivered group, and raises a redirect, `tb.bkend_ftq_redir_val`, to the
expected address. The frontend flushes its younger work and fetches from that
address. This is the backend misprediction the scenario descriptions refer to;
its cycle is the cycle `bkend_ftq_redir_val` is high.

The backend model also commits FTQ entries whose instructions have all
retired (`tb.bkend_ftq_commit_val`, `tb.bkend_ftq_commit_idx`).

Any other mismatch, for example an instruction with the wrong encoding, is a
stream error: the model prints a line that begins `ERROR:` and the run fails
(section 5).

The plusarg `+TRACE` makes the backend print a line for each retired
instruction and each misprediction, with the cycle count first. These
lines are for debugging and do not follow the result-line format.

---

## 5. The result line

To maintain stability in the scenarios, they are developed against tagged
versions of the RTL. The Showcase landing page specifies the current tag. The
scenarios run internal checks to verify that the waveforms and scenario
descriptions match the current state of the design.

A run passes when every expected instruction retires with no stream error and
the scenario's checks pass. It prints a result line and exits with status 0.
Otherwise it prints a failing result line and exits non-zero, which stops
`make scenarios`.

A result line begins with `-I:` (information), `-W:` (warning) or `-E:`
(error), then the scenario name. A passing line gives PASS, the counts the
checks read, and `cyc`, the number of cycles from the release of reset to the
last retirement:

```
-I: fd09_tage: PASS, tagged-provider predictions 188, allocations 59,
    T0 by use_alt_on_na 22, cyc 1364
```

When the expected instructions did not all retire, the failing line says so
first:

```
-E: fd09_tage: FAIL, stream not retired, retired 1200 of 1510,
    stream errors 1, ...
```

The `ERROR:` lines for stream errors and the `+TRACE` debug lines (section 4)
use a different format.

---

## 6. The cycle counter cyc

`tb.cyc` counts clock cycles from the release of reset and is shown next to
the clock in every waveform.

Scenario descriptions give times as values of `cyc`. An event "at cyc N" occurs
in the clock period in which `tb.cyc` shows N; a register written in that
period shows its new value from cyc N + 1.

---

## 7. Reading the waveforms

Each scenario description has an "Open waveform" link that opens the
scenario in Surfer in the browser.

From the command line, `make view S=<scenario>` opens it in a
local Surfer session (`README.md`, section 2).

Surfer shortens signal names to the end of their hierarchical path. The
scenario descriptions give the full path in Surfer's form, which names an
array element by its index under the array, for example
`tb.dut.u_bpu.u_tage.u_tage_cntrl.uaon.[0]`.

A one-slot waveform shows slot 0 of each per-slot signal; a two-slot waveform
shows slots 0 and 1. Encoded fields, such as `trx_type`, are shown as numbers;
the descriptions that show one give its encoding.

A scenario whose description has an event table opens with one marker per
event, named `c<cyc>_<label>`, and the view at the first marker.

---

## 8. Glossary

Standard RISC-V terms (Sv39, Sv39x4, VS-stage and G-stage translation, PBMT,
PMP, Svadu, link registers) are used as the specifications define them. The
entries below give Pacino's parameters, conventions and signal names.

| Term | Description |
|------|-------------|
| allocation (TAGE) | On a TAGE misprediction of a conditional branch, a new entry is written in the first table with a longer history than the primary's whose entry at the branch's index has an aged useful value of 0. The candidate is chosen at prediction time; if no table qualifies, nothing is allocated. The new entry gets the branch's tag and a CTR of 3'b100. |
| alternate (TAGE) | The matching tagged table with the next shorter history below the primary, or T0 when no such table matches. Table number `tage_alt_comp` in the prediction metadata, 0 for T0. |
| back edge | The branch at the end of a loop body that jumps back to the loop's first instruction. It is taken on every iteration but the last, on which it falls through. |
| backend model | The testbench's stand-in for the backend (section 4). It retires in program order against the expected execution list, sends resolutions, redirects and commits, and does not execute instructions. |
| block | The prediction and fetch unit: at most 32 bytes from a start address, ending at the first predicted-taken control transfer. A 32-bit instruction starting in the last halfword is delivered with the block, which then spans 34 bytes. An FTB entry holds at most one branch per prediction slot; a block with more branches is split at update, ending the entry at the first branch it cannot hold (FD-23). One FTQ entry per block. |
| BPU | `tb.dut.u_bpu`: uBTB, loop predictor, FTB, TAGE, ITTAGE, SC and RAS, and the per-stage logic that combines their predictions. |
| branch type | `bp_br_type_e`, as shown in the waveforms: COND, DIRECT_UNC (`jal`, rd not a link register), DIRECT_CALL, INDIRECT_CALL (push only), RETURN, RETURN_CALL (`jalr` with rd and rs1 both link registers and unequal: pop then push), INDIRECT_NONRET and NO_BRANCH. Call and return classification follows the RISC-V link-register hints. |
| bundle | Decode's output per cycle, up to eight instructions on `tb.pd_out`, accepted when `tb.dec_ibuf_rdy` is high. |
| cbo.inval, fence.i | `cbo.inval` invalidates the cache line holding a given address; `fence.i` makes earlier stores visible to instruction fetch. At retirement of either, the backend model drives the frontend's commit-stage maintenance port and restarts fetch after the acknowledgment (FD-13, FD-19). |
| commit | The backend model raises `tb.bkend_ftq_commit_val` as its retirement watermark advances; the FTQ commit pointer follows one entry per cycle, freeing entries and committing RAS state for their calls and returns. |
| CTR | 3-bit saturating direction counter in tagged TAGE entries, its top bit the prediction: 3'b100 to 3'b111 taken, 3'b000 to 3'b011 not taken. 3'b011 and 3'b100 are weak, 3'b000 and 3'b111 strong. Updates step by one toward the resolved direction. |
| fall through | A branch falls through when it is not taken: execution continues at the next instruction. |
| frontend | `tb.dut`: BPU, FTQ, IFU, L1I, instruction buffer and decode. |
| FTB | Fetch target buffer: per block start, the block's end and its branches with positions, types and targets. Answers at p2. |
| FTQ | Fetch target queue, `tb.dut.u_ftq`, one entry per predicted block. Issues prediction requests, holds predictions and their metadata, feeds the IFU, and takes resolutions, redirects and commits from the backend. |
| G-stage, VS-stage, two-stage translation | Address translation for a guest running under a hypervisor. The VS-stage translates the guest's virtual address to a guest physical address (GPA) using the guest's page tables; the G-stage translates the GPA to a physical address using the hypervisor's Sv39x4 tables. A fault in the G-stage is a guest page fault (FD-15). |
| GPA | Guest physical address: an address a guest treats as physical, translated to a physical address by the G-stage. |
| history length | T1 to T4 use 8, 13, 32 and 119 branches of global history. |
| IFU | `tb.dut.u_ifu`: translation, L1I access, predecode, and delivery to the instruction buffer. |
| instruction buffer, IBUF | The queue between the IFU and decode. |
| ITLB | The instruction translation lookaside buffer: it holds recent translations from virtual to physical page numbers for fetch. A miss starts a page table walk. |
| ITTAGE | The indirect target predictor, built as TAGE is but storing targets, with its own primary and alternate (`ittage_using_primary`). Answers at p2. |
| L1I | `tb.dut.u_l1i`, 64-byte lines. Fetches from NC or IO pages are answered from memory as uncached requests (FD-18). |
| LFSR | Linear-feedback shift register: a shift register whose input is a combination of its own bits, used for a sequence of bits that looks random. Section 2 describes its use. |
| loop predictor, LP | Learns trip counts and predicts the back edge's exit. Answers at p1. |
| misprediction | A backend misprediction is a wrong-path fetch detected by the backend model, with a redirect (`tb.bkend_ftq_redir_val`, cause `RC_MISPREDICT`). A TAGE misprediction is TAGE's own direction differing from the resolved direction, whatever the final prediction was; TAGE trains and allocates on it. |
| MSHR | Miss status holding register: a register in the L1I that tracks one outstanding request to memory until it is answered. |
| override | A later prediction stage replacing an earlier one's prediction: FTB or TAGE at p2 (FD-04), SC at p3 (FD-05). It redirects the prediction request stream. |
| p0 to p3 | Prediction stages. p0: the FTQ presents a block start. p1: uBTB and loop predictor. p2: FTB, TAGE and ITTAGE. p3: SC. |
| page fault | An instruction page fault: translation of the fetch address fails, because a page table entry is invalid or does not permit execute. The fetch traps instead of delivering the instruction. |
| page table walk | Reading the page table entries for a virtual address from memory, after an ITLB miss, to find its translation. |
| PBMT | Page-based memory type (Svpbmt), a field of a leaf page table entry: normal memory, NC (non-cacheable) or IO. Code fetched from an NC or IO page is fetched uncached (FD-18). |
| position | The offset of an instruction from the start of its block, in halfwords: the instruction at the block's start is at position 0, one 6 bytes later at position 3. |
| PPN | Physical page number: a physical address without its offset within the page. |
| predecode | The IFU's step that finds the instruction boundaries and the control transfers in a block's bytes. |
| prediction metadata | Predictor state carried in the FTQ entry from prediction to update. For TAGE: the primary and alternate tables, their counters and directions, the allocation candidate, and whether the primary was the provider; returned as `tage_upd_inp_u0[s].tage_pred_meta`. |
| prediction slot | One branch field of an FTB entry; `NUM_PRED_SLOTS` (1 or 2) sets how many branches per block are predicted, slot 0 the earliest. TAGE keeps per-slot state, including use_alt_on_na. The demonstration builds a one-slot and a two-slot model (section 1). |
| primary (TAGE) | The matching tagged table with the longest history, or T0 when no tagged table matches. Table number `tage_prm_comp`, counter `tage_prm_ctr`, direction `tage_prm_tkn`. |
| provider (TAGE) | The table whose prediction TAGE uses: the primary, or the alternate when use_alt_on_na selects it. `tage_using_primary` is 1 when the primary is the provider. Which of the two provided determines how the update trains the tables. |
| PTE | Page table entry: a physical page number and permission bits, or a pointer to the next level of the table. |
| RAS | Return address stack with read and write pointers TOSR and TOSW. Each FTQ entry checkpoints them; a redirect restores the RAS from the named entry's checkpoint. |
| redirect | Sources: the BPU at p2 and p3, the IFU after predecode, and the backend on a misprediction or trap. |
| resolution | `tb.bkend_ftq_rsv`, one per resolved branch: FTQ index, position, direction, target, type, mispredict flag and instruction length. A conditional's target is its taken target whatever its direction. The FTQ converts resolutions into predictor updates. |
| retire | Complete an instruction in program order. In the demonstration the backend model retires an instruction when it matches the next entry of the expected execution list (section 4). |
| SC | Statistical corrector; may reverse TAGE's direction at p3. |
| stream error | A delivered instruction that does not match the expected execution list and is not explained by a misprediction. It fails the run. |
| Sv39, Sv39x4 | RISC-V page table formats. Sv39 translates 39-bit virtual addresses through three levels of tables to 4 KiB pages. Sv39x4 is the G-stage format, which translates 41-bit guest physical addresses. |
| T0, T1 to T4 | The TAGE tables: T0 the base table, T1 to T4 the tagged tables in order of increasing history length. |
| tag, tag match | A tagged table entry stores a short value formed from the branch address and the history. The entry matches a prediction request when its stored tag equals the request's. |
| TAGE | The direction predictor for conditional branches, instance `tb.dut.u_bpu.u_tage`. It has the base table T0 of 2-bit counters, initialized to 2'b10 (weakly taken), and four tagged tables T1 to T4, and answers at p2. |
| tagged table | A TAGE table whose entries carry a tag, so an entry answers only for the branch and history that wrote it, as far as the tag can tell them apart. |
| TOSR, TOSW | The RAS's top-of-stack read and write pointers. Each FTQ entry holds a copy of them, and a redirect restores the RAS from the copy in the entry it names. |
| trap | A transfer of control to a handler on an exception, such as a page fault or an access fault, or on an `ecall`. |
| trip count | The number of iterations a loop runs. |
| uBTB | Micro BTB; answers at p1. |
| update | A TAGE update arrives on `tage_upd_val_u0` with `tage_upd_inp_u0` and is written in the cycle `trx_type` is 1. Update conversion, `tb.dut.u_ftq.u_upd_conv`, builds each predictor's update input from a resolution and the FTQ entry's metadata. |
| use_alt_on_na | `uaon`, a 4-bit counter per prediction slot. When it is 8 or more and the primary is a tagged table with a weak CTR, the alternate is the provider. It is updated only when the primary and the alternate are both tagged tables. |
| useful counter | 2 bits per tagged entry, aged by period: full value in the current period, half in the next, 0 after that (`ueff_p1`). An entry whose aged value is 0 may be replaced by an allocation. |
| VPN | Virtual page number: a virtual address without its offset within the page. |
| weak | A CTR value of 3'b011 or 3'b100, the two values nearest the boundary between not taken and taken. |
