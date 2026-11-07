---
layout: post
title: "The Pacino Frontend RTL Is Complete"
author: Jeff Nye
date: 2026-11-05
excerpt: "the frontend RTL, demos and specs, released as fe-1.0.0"
copyright: "Copyright 2026 Jeff Nye"
---
<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

<!-- ``` -->
<!-- TITLE:     "The Pacino Frontend RTL Is Complete" -->
<!-- FILE:      BLOG_fe_rtl_complete.md -->
<!-- AUTHOR:    Jeff Nye -->
<!-- DATE:      [DATE] -->
<!-- STATUS:    DRAFT -->
<!-- COPYRIGHT: "Copyright 2026 Jeff Nye" -->
<!-- ``` -->

# The Pacino Frontend RTL Is Complete

## Abstract

The RTL for the Pacino frontend is complete and released as `fe-1.0.0`.
Pacino is an 8-issue out-of-order RISC-V core targeting the RVA23S64
profile. The frontend covers branch prediction, the fetch target queue,
instruction fetch, the L1 instruction cache, address translation and
protection for fetch, the instruction buffer and decode.

The release comes with 24 demonstrations of frontend behavior. Each has a
write-up, diagrams and a waveform that opens in Surfer in a browser, with
nothing to install.

The frontend was designed by one architect directing LLM agents. Every IA
task behind it is published with its prompt, results and assessment.

This post summarizes what is in the release, what has been verified and
what has not, and what comes next.

## What is in the release

The frontend RTL is about 29,000 lines of SystemVerilog, comments included,
with about 75,000 lines of testbench code.

- **Branch prediction unit.** Seven predictors in a four-stage pipeline. At
  p1 the uBTB and the loop predictor give the first prediction. At p2 the
  FTB, TAGE (a bimodal base and four tagged tables), ITTAGE and a 48-entry
  RAS refine or override it. At p3 the statistical corrector makes the
  final direction correction.
- **Fetch.** The fetch target queue, the instruction fetch unit, the L1
  instruction cache and the instruction buffer.
- **Translation and protection.** The ITLB, the page table walker and the
  PMP/PMA checker.
- **Decode.** 8-wide, covering RV64, RVC and RVV.
- **`fe_top`**, which integrates the above and is driven by a testbench
  backend.

The pipestage view below shows the prediction pipeline (p0 to p3), the FTQ,
the translation and fetch pipelines and the decode output. Select it to
open it at full size. The block view is on the
[Frontend Overview](https://uarchlabs.github.io/pacino/frontend/overview/).

[![Pacino frontend pipestage view](/assets/diagrams/fe_pipe.svg)](/assets/diagrams/fe_pipe.svg)

## The demonstrations

The 24 scenarios, FD-01 to FD-24, run programs through `fe_top` and show
one behavior each. The [Showcase](https://uarchlabs.github.io/pacino/showcase/)
has the write-up for each, and the [workbench](https://uarchlabs.github.io/)
lists all 24 with a link that opens each waveform in the browser, with the
signals for that scenario already loaded.

| FD | Demonstration | What it shows |
|---|---|---|
| FD-01 | [Reset and init](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd01_reset_init/) | Reset and SRAM initialization |
| FD-02 | [Steady state](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd02_steady/) | Steady-state prediction and fetch |
| FD-03 | [Two branches](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd03_two_branch/) | Two branches in one prediction block |
| FD-04 | [p2 override](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd04_p2_override/) | An FTB hit at p2 corrects a uBTB miss |
| FD-05 | [p3 override](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd05_p3_override/) | The statistical corrector overrides at p3 |
| FD-06 | [Loop predictor](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd06_loop_pred/) | Loop trip count learned and the exit predicted |
| FD-07 | [Calls and returns](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd07_calls_returns/) | Return address stack push and pop |
| FD-08 | [Indirect jump](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd08_indirect/) | ITTAGE predicts an indirect target |
| FD-09 | [TAGE](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd09_tage/) | Provider, allocation and use_alt_on_na |
| FD-10 | [Predecode redirect](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd10_pd_redirect/) | Predecode corrects the prediction |
| FD-11 | [Backend mispredict](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd11_be_mispredict/) | Redirect from the backend after a mispredict |
| FD-12 | [Predictor training](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd12_training/) | Updates routed by branch type; the single-ported FTB |
| FD-13 | [L1I](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd13_l1i/) | Hit, miss and MSHR merge |
| FD-14 | [Translation](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd14_translation/) | Sv39 walk, Sv39x4 nested walk and Svadu CAS |
| FD-15 | [Fetch faults](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd15_faults/) | Page, access and guest-page fetch faults |
| FD-16 | [Page crossing](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd16_page_cross/) | A prediction block crossing a page |
| FD-17 | [Compressed code](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd17_rvc/) | Compressed and unaligned code |
| FD-18 | [Uncached fetch](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd18_uncached/) | Fetch from an uncached region |
| FD-19 | [FENCE.I and cbo.inval](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd19_fencei_cbo/) | Instruction cache maintenance |
| FD-20 | [Backpressure](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd20_backpressure/) | A decode stall propagating back to the p0 request |
| FD-21 | [Commit](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd21_commit/) | FTQ commit pointer and RAS commit stack |
| FD-22 | [SC on slot 1](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd22_sc_slot1/) | SC reversing slot 1 |
| FD-23 | [Jump cut](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd23_jump_cut/) | A jump behind two conditionals |
| FD-24 | [Call in slot 1](https://uarchlabs.github.io/pacino/showcase/fe_demo/fd24_call_slot1/) | A call in slot 1 |

FD-03 and FD-22 to FD-24 run in the two-slot configuration
(`NUM_PRED_SLOTS=2`), which predicts up to two branches per prediction
block.

The waveform for fd09_tage, as it opens in the browser:

![Surfer showing the FD09 waveform](/assets/diagrams/fd_fragment.png)

The Showcase pages, the waveforms and the release are tied to the same
tag. The waveforms are published only from a release tag and only when
every scenario passes, and a separate regression checks that each
scenario still produces the events its write-up describes.

## What has been verified, and what has not

Each block has its own unit testbench of directed tests. All of them pass
in the full regression at the release tag, 274 targets with no known
failures.

The branch prediction cluster has 973 checks, and mutation testing confirmed
that the testbench detects each of 20 injected faults. During that work the
method changed: every check must be shown to fail when the condition it guards
is broken. That sweep, across all 18 unit testbenches, found and repaired exit
codes, unbound assertions and watchdogs that could not fire. The details are in
[Branch Prediction Cluster Simulation and Mutation-based
Verification](https://uarchlabs.github.io/blog/branch-prediction-cluster-simulation-and-mutation-based-verification/).

Decode is checked against
[Spike](https://github.com/riscv-software-src/riscv-isa-sim), the RISC-V
ISA simulator, as an independent oracle.

Formal analysis is not part of this release. No performance figures exist
yet: prediction accuracy and frontend throughput on standard traces are
the next measurements. No synthesis or timing results are published, and
the physical design toolchain has not been chosen. Those three tracks are
in progress.

## The record

The project has run 250 IA tasks since the start of the development to
this release, most of them on the frontend: 234 complete, 12 abandoned and
kept, and 4 in progress.
Each IA task was issued from a numbered PA session. The
[IA task browser](https://uarchlabs.github.io/pacino/sessions/) holds each
one with its prompt, the results capture, the IA output, the assessment,
the files changed, the model, the runtime and the context use. The weekly
posts on this blog discuss the results range by range and name the tasks
they cover.

The planning documents the blocks were designed from are published as
working specifications on the
[docs pages](https://uarchlabs.github.io/pacino/) for the BPU, fetch, the
I-cache, the MMU, decode and the CSRs, until the written descriptions
replace them.

## Running it

The release is at
[github.com/uarchlabs/pacino/releases/tag/fe-1.0.0](https://github.com/uarchlabs/pacino/releases/tag/fe-1.0.0).
On Ubuntu 22.04, the quick start in the README builds the tools and runs a
demonstration:

```
git clone --recurse-submodules https://github.com/uarchlabs/pacino
cd pacino && . tools/setup.sh
tools/build_tools.sh
make -C examples/fe_demo view S=fd09_tage
./tools/regress.sh
```

## Where to go for more information

The demonstrations are the best place to start. The [demo
explainer](https://uarchlabs.github.io/pacino/showcase/fe_demo/demo_explainer/)
describes how the scenarios are built and how to read their waveforms Each demo
description page then walks through that one behavior, lists the events, lists
the signals in the waveforms and with a one-click link to the waveform for that
scenario.

For the design itself, start at the
[frontend specification](https://uarchlabs.github.io/pacino/frontend/overview/).
It walks through both diagrams, and the block pages under it hold the
working specifications: the decisions, rules and interfaces each block was
built from.

The weekly posts on this blog cover how each block was designed and
verified, and the IA task browser has every task they cite.

## What comes next

The frontend remains the current phase. The work now shifts from RTL to
four tracks:

- the documentation, released as further showcase sets
- LLM-augmented formal analysis
- performance analysis and modeling, starting with branch prediction on
  standard traces
- LLM-augmented physical design, on FPGA and open-source PDKs.

The mid-core and backend will follow the same methodology. Questions and
reports are welcome as
[issues](https://github.com/uarchlabs/pacino/issues).
