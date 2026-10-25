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

Each scenario's waveform opens in Surfer in the browser, with nothing to
install.

| FD | Scenario | What it shows | Waveform |
|----|----------|---------------|----------|
| 1  | [Reset and SRAM Initialization](fe_demo/fd01_reset_init.md) | The TAGE, ITTAGE and SC init walks; no p0 request until all three are ready | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd01_reset_init.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd01_reset_init.sucl" target="_blank" rel="noopener">Open</a> |
| 2  | [Steady-State Prediction and Fetch](fe_demo/fd02_steady.md) | Straight-line code: one FTQ entry and eight decoded instructions per cycle | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd02_steady.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd02_steady.sucl" target="_blank" rel="noopener">Open</a> |
| 3  | [Two Branches in One Block](fe_demo/fd03_two_branch.md) | p1 and p2 predictions with both prediction slots valid | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd03_two_branch.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd03_two_branch.sucl" target="_blank" rel="noopener">Open</a> |
| 4  | [p2 Override](fe_demo/fd04_p2_override.md) | A uBTB miss corrected by the FTB at p2 | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd04_p2_override.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd04_p2_override.sucl" target="_blank" rel="noopener">Open</a> |
| 5  | [p3 Override](fe_demo/fd05_p3_override.md) | The statistical corrector reversing TAGE at p3 | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd05_p3_override.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd05_p3_override.sucl" target="_blank" rel="noopener">Open</a> |
| 6  | [Loop Predictor](fe_demo/fd06_loop_pred.md) | The loop predictor learning a trip count and predicting the exit | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd06_loop_pred.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd06_loop_pred.sucl" target="_blank" rel="noopener">Open</a> |
| 7  | [Calls and Returns](fe_demo/fd07_calls_returns.md) | RAS push and pop, recursion count and return-call | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd07_calls_returns.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd07_calls_returns.sucl" target="_blank" rel="noopener">Open</a> |
| 8  | [Indirect Jump](fe_demo/fd08_indirect.md) | ITTAGE supplying history-dependent indirect targets | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd08_indirect.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd08_indirect.sucl" target="_blank" rel="noopener">Open</a> |
| 9  | [TAGE Provider, Allocation and use_alt_on_na](fe_demo/fd09_tage.md) | A tagged-table provider, allocation after a mispredict, and use_alt_on_na | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd09_tage.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd09_tage.sucl" target="_blank" rel="noopener">Open</a> |
| 10 | [Predecode Redirect](fe_demo/fd10_pd_redirect.md) | Predecode at F3 finding an unpredicted JAL and redirecting fetch | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd10_pd_redirect.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd10_pd_redirect.sucl" target="_blank" rel="noopener">Open</a> |
| 11 | [Backend Mispredict](fe_demo/fd11_be_mispredict.md) | A backend redirect: FTQ squash, IFU flush, history and RAS recovery | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd11_be_mispredict.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd11_be_mispredict.sucl" target="_blank" rel="noopener">Open</a> |
| 12 | [Predictor Training and the FTB Update Bubble](fe_demo/fd12_training.md) | Updates to every predictor, and the p0 request each FTB update withholds | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd12_training.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd12_training.sucl" target="_blank" rel="noopener">Open</a> |
| 13 | [L1I Hit, Miss and MSHR Merge](fe_demo/fd13_l1i.md) | L1I hits, misses with fills, and a request merging onto an MSHR | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd13_l1i.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd13_l1i.sucl" target="_blank" rel="noopener">Open</a> |
| 14 | [Sv39 Walk, Sv39x4 Nested Walk and Svadu CAS](fe_demo/fd14_translation.md) | A single-stage walk, a two-stage walk at V=1, and an A-bit update by CAS | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd14_translation.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd14_translation.sucl" target="_blank" rel="noopener">Open</a> |
| 15 | [Page, Access and Guest-Page Fetch Faults](fe_demo/fd15_faults.md) | The three fetch faults carried with their blocks to decode | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd15_faults.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd15_faults.sucl" target="_blank" rel="noopener">Open</a> |
| 16 | [A Fetch Block Crossing a Page](fe_demo/fd16_page_cross.md) | One fetch block translated twice, with an instruction straddling the pages | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd16_page_cross.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd16_page_cross.sucl" target="_blank" rel="noopener">Open</a> |
| 17 | [Compressed and Unaligned Code](fe_demo/fd17_rvc.md) | A 32-bit instruction straddling two blocks, and 16-bit control transfers | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd17_rvc.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd17_rvc.sucl" target="_blank" rel="noopener">Open</a> |
| 18 | [Uncached Fetch](fe_demo/fd18_uncached.md) | Fetch from PBMT NC and IO pages, never filled into the L1I | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd18_uncached.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd18_uncached.sucl" target="_blank" rel="noopener">Open</a> |
| 19 | [FENCE.I and cbo.inval](fe_demo/fd19_fencei_cbo.md) | L1I invalidation and the fetch restart after each | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd19_fencei_cbo.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd19_fencei_cbo.sucl" target="_blank" rel="noopener">Open</a> |
| 20 | [Backpressure](fe_demo/fd20_backpressure.md) | A slow backend stalling decode, the IBUF, the IFU and the FTQ in turn | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd20_backpressure.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd20_backpressure.sucl" target="_blank" rel="noopener">Open</a> |
| 21 | [Commit](fe_demo/fd21_commit.md) | The FTQ commit pointer and the RAS commit stack | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd21_commit.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd21_commit.sucl" target="_blank" rel="noopener">Open</a> |
| 22 | [SC Reversing Slot 1](fe_demo/fd22_sc_slot1.md) | The statistical corrector reversing the branch in slot 1 at p3 | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd22_sc_slot1.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd22_sc_slot1.sucl" target="_blank" rel="noopener">Open</a> |
| 23 | [A Jump Behind Two Conditionals](fe_demo/fd23_jump_cut.md) | The FTB splitting a block that holds two conditionals and a jump | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd23_jump_cut.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd23_jump_cut.sucl" target="_blank" rel="noopener">Open</a> |
| 24 | [A Call in Slot 1](fe_demo/fd24_call_slot1.md) | A RAS push from slot 1 behind a not-taken conditional | <a href="https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd24_call_slot1.fst&amp;startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd24_call_slot1.sucl" target="_blank" rel="noopener">Open</a> |

FD-3 and FD-22 to FD-24 run on the two-slot build; the rest on the one-slot
build.
