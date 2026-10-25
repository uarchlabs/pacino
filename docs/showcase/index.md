<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# <span style="color: var(--md-accent-fg-color)">Showcase</span>

A showcase release is documentation built around testcases and waveforms.
Each page follows one program through the RTL and explains what the
waveform shows. It is not a specification; the design is described in the
architecture pages and the planning documents.

## <span style="color: var(--md-accent-fg-color)">Release 01: Frontend Demo</span>

Twenty-four short programs run on the Pacino frontend, `fe_top`, with
testbench models of the backend, the page table walker and memory. Each
scenario shows one behavior: prediction and override, the predictors,
redirects, the L1I, translation and faults, compressed code, uncached
fetch, cache maintenance, backpressure and commit. Each run ends in a
PASS or FAIL line and writes an FST waveform. The
[Frontend Overview](../frontend/overview.md) describes the design.
[How a Scenario Is Built and Run](fe_demo/demo_explainer.md) covers the
testbench, the program writer and how to read the waveforms.

[![Block view of the Pacino frontend](fe_demo/fe_block.svg)](fe_demo/fe_block.svg)

[![Pipeline view of the Pacino frontend](fe_demo/fe_pipe.svg)](fe_demo/fe_pipe.svg)

Select either diagram to open it at full size. The signal annotations on the
block view refer to the
[fe_top connectivity inventory](fe_demo/fe_top_connectivity.md).

### Running it

From `examples/fe_demo/`:

```
make <scenario>          run one scenario; writes out/<scenario>/
make scenarios           run all 24 in order
make view S=<scenario>   open the scenario's waveform in Surfer
make help                list the scenarios
```

It needs Verilator 5.048 and, for `make view`, Surfer; the repository
[README](https://github.com/uarchlabs/pacino#readme) covers installing both.

### Scenarios

| FD | Scenario | What it shows |
|----|----------|---------------|
| 1  | [Reset and SRAM Initialization](fe_demo/fd01_reset_init.md) | The TAGE, ITTAGE and SC init walks; no p0 request until all three are ready |
| 2  | [Steady-State Prediction and Fetch](fe_demo/fd02_steady.md) | Straight-line code: one FTQ entry and eight decoded instructions per cycle |
| 3  | [Two Branches in One Block](fe_demo/fd03_two_branch.md) | p1 and p2 predictions with both prediction slots valid |
| 4  | [p2 Override](fe_demo/fd04_p2_override.md) | A uBTB miss corrected by the FTB at p2 |
| 5  | [p3 Override](fe_demo/fd05_p3_override.md) | The statistical corrector reversing TAGE at p3 |
| 6  | [Loop Predictor](fe_demo/fd06_loop_pred.md) | The loop predictor learning a trip count and predicting the exit |
| 7  | [Calls and Returns](fe_demo/fd07_calls_returns.md) | RAS push and pop, recursion count and return-call |
| 8  | [Indirect Jump](fe_demo/fd08_indirect.md) | ITTAGE supplying history-dependent indirect targets |
| 9  | [TAGE Provider, Allocation and use_alt_on_na](fe_demo/fd09_tage.md) | A tagged-table provider, allocation after a mispredict, and use_alt_on_na |
| 10 | [Predecode Redirect](fe_demo/fd10_pd_redirect.md) | Predecode at F3 finding an unpredicted JAL and redirecting fetch |
| 11 | [Backend Mispredict](fe_demo/fd11_be_mispredict.md) | A backend redirect: FTQ squash, IFU flush, history and RAS recovery |
| 12 | [Predictor Training and the FTB Update Bubble](fe_demo/fd12_training.md) | Updates to every predictor, and the p0 request each FTB update withholds |
| 13 | [L1I Hit, Miss and MSHR Merge](fe_demo/fd13_l1i.md) | L1I hits, misses with fills, and a request merging onto an MSHR |
| 14 | [Sv39 Walk, Sv39x4 Nested Walk and Svadu CAS](fe_demo/fd14_translation.md) | A single-stage walk, a two-stage walk at V=1, and an A-bit update by CAS |
| 15 | [Page, Access and Guest-Page Fetch Faults](fe_demo/fd15_faults.md) | The three fetch faults carried with their blocks to decode |
| 16 | [A Fetch Block Crossing a Page](fe_demo/fd16_page_cross.md) | One fetch block translated twice, with an instruction straddling the pages |
| 17 | [Compressed and Unaligned Code](fe_demo/fd17_rvc.md) | A 32-bit instruction straddling two blocks, and 16-bit control transfers |
| 18 | [Uncached Fetch](fe_demo/fd18_uncached.md) | Fetch from PBMT NC and IO pages, never filled into the L1I |
| 19 | [FENCE.I and cbo.inval](fe_demo/fd19_fencei_cbo.md) | L1I invalidation and the fetch restart after each |
| 20 | [Backpressure](fe_demo/fd20_backpressure.md) | A slow backend stalling decode, the IBUF, the IFU and the FTQ in turn |
| 21 | [Commit](fe_demo/fd21_commit.md) | The FTQ commit pointer and the RAS commit stack |
| 22 | [SC Reversing Slot 1](fe_demo/fd22_sc_slot1.md) | The statistical corrector reversing the branch in slot 1 at p3 |
| 23 | [A Jump Behind Two Conditionals](fe_demo/fd23_jump_cut.md) | The FTB splitting a block that holds two conditionals and a jump |
| 24 | [A Call in Slot 1](fe_demo/fd24_call_slot1.md) | A RAS push from slot 1 behind a not-taken conditional |

FD-3 and FD-22 to FD-24 run on the two-slot build; the rest on the one-slot
build.
