<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Performance Analysis Decisions
```
 FILE:    perf_decisions.md
 SOURCE:  session-084
 STATUS:  DRAFT
 UPDATED: 2026-11-09
 CONTACT: Jeff Nye
```

Owns the PF-N and PF-UN registries.

How the front end's performance is measured: the workload traces and
reference results taken from the Championship Branch Prediction (CBP),
the harness that runs them through the RTL, the configurations
measured, the metrics, and how a result is checked and recorded.

This is the first layer of performance analysis: a filter for
microarchitecture problems in the predictors and the fetch path,
before any full-core model exists. It answers whether the predictor
configuration shows performance compatible with the SPEC targets, by
extrapolation (PF-10). It does not measure the backend.

---

## 1. Sources

PF-1   Pacino takes the CBP workload traces and the CBP reference
       results, and nothing else from CBP. No CBP simulator code is
       copied into the tree (Jeff, session-084).
       The source is the CBP2025 training set: 105 traces in six
       groups (int 37, web 26, infra 16, fp 14, compress 8, media 4),
       4.34e9 instructions in all, and its reference results,
       reference_results_training_set.csv in the cbp2025 repository
       (https://github.com/ramisheikh/cbp2025). The reference
       predictor is the CBP2016 winner, a 64 KB TAGE-SC-L, which the
       CBP2025 simulator ships as its default (PF-U2 confirms that
       the reference results are from it).
       The trace format is generic at the predictor's view: a record
       carries the PC, an instruction class, the branch direction and
       target, and register values; it carries no instruction bytes.
       Every PC is 4-byte aligned.
       Licensing: the cbp2025 repository has no top-level license;
       its simulator sources carry an NCSU BSD-style notice. Pacino
       is Apache-2.0, which is one reason no CBP code is mixed in.

PF-2   The performance code lives in perf/. An external repository
       used by it is a git submodule under tools/. Pacino code and
       external code are not mixed in one directory (Jeff,
       session-084).
       The traces are not in git. They are fetched by a script that
       checks each file against a recorded checksum. Where they are
       stored is PF-U3.

## 2. Harness

PF-3   The harness is a hybrid (Jeff, session-084):
       - a SystemVerilog wrapper in perf/ instantiates fe_top and
         brings the internal signals the metrics need out as its own
         ports, by hierarchical reference. No RTL file is changed.
       - a C++ main drives the Verilated wrapper, reads the trace,
         builds the code image, models memory and the backend, and
         holds the counts in memory.
       Reasons: C++ is the fastest way to drive a Verilated model and
       the natural language for the gasket; the wrapper gives the
       internal signals that per-predictor attribution needs (PF-6)
       without --public-flat-rw.
       Cost: the memory and backend models are written in C++. The
       SystemVerilog models of tb_fe_top and examples/fe_demo
       (rtl/core/frontend/fe_top/tb/models/, FDT-4) are not reused.

PF-4   The gasket cuts in at fe_top, not at bp_cluster (Jeff,
       session-084). The gasket supplies the instruction memory and
       the backend; the FTQ, the IFU, predecode, the I-cache and the
       ITLB are the RTL's own.
       Reasons: a cut at bp_cluster makes the gasket a C++ model of
       the FTQ, a second copy that can diverge from the RTL; a cut at
       fe_top keeps the FTQ's management of predictions and updates,
       IFU predecode corrections, override flushes and run-ahead in
       the measurement.
       Cost: the trace carries no instruction bytes, so the gasket
       builds a code image, one RISC-V instruction of the trace
       record's class at each traced PC, with its traced target.
       Far conditional branches are PF-U1. The fe_top build is slower
       per simulated instruction than bp_cluster alone.

## 3. Configurations

PF-5   A measured configuration is named by a release tag, <tag>, for
       the RTL and parameters as tagged; a variant of it is named
       <tag>/<name> (Jeff, session-084). The first two:
         fe-1.0.0             A, the baseline: pacino as tagged
         fe-1.0.0/cbp16-64k   B, the matched: pacino's predictor
                              parameters set to match the reference
                              predictor's layout and total storage
       The RTL is tweaked between tags; a result on an untagged tree
       is keyed by the sha (PF-9) until the next tag.

## 4. Measurement

PF-6   The metrics are MPKI overall and MPKI per predictor (Jeff,
       session-084). A misprediction is attributed to the predictor
       that supplied the final prediction, bp_ftq_slot_t.pred_src
       (bp_pred_src_e: uBTB, Loop, FTB, TAGE, SC, ITTAGE, RAS, none),
       read through the wrapper (PF-3).
       No RTL change is made for measurement. Signals are observed at
       ports, the wrapper's included. Counts are kept in memory and a
       summary is written at the end of a run; there is no per-event
       file output.

PF-7   A run warms up and then measures, by the method CBP uses
       where it can be matched, so that results compare with the
       reference results like for like. The reference results report
       the full trace and its second half (the 50Perc columns); the
       second half is read as the measured part after a first-half
       warmup (PF-U2 confirms).
       Full traces are the goal. Whether they are practical here
       depends on the harness's speed, which PERF-001 measures; the
       aim is a sense of whether the front-end configuration performs
       well, within the limits of this environment. Runs are in
       parallel. Rented compute is a later step (Jeff, session-084).

PF-8   The first version measures the committed path only, as CBP
       scores its entries. Wrong-path fetch is a later version (Jeff,
       session-084). Fetches off the traced path land on bytes outside
       the code image and see filler.

PF-9   A result is keyed by its configuration name (PF-5) and the
       pacino sha it ran on, which is a tag's sha when the tree is
       tagged (Jeff, session-084). A performance run gates no push.

## 5. Comparison

PF-10  Three are compared, at equal predictor storage (Jeff,
       session-084):
         R  the reference: CBP's 64 KB TAGE-SC-L in software, the
            reference results
         A  pacino as built (fe-1.0.0)
         B  pacino matched to R's layout (fe-1.0.0/cbp16-64k)
       A against B is the effect of pacino's table sizing. B against
       R is the effect of pacino's microarchitecture: block
       prediction, the overrides, training at resolve or commit, the
       FTQ.
       The traces are not SPEC. The extrapolation to the SPEC targets
       runs pacino against R on these traces, then R's published SPEC
       CPU2017 MPKI, then pacino's expected SPEC MPKI. It holds if
       pacino's gap to R is steady across the trace groups; each
       result that uses it states that assumption. MPKI to IPC needs
       pacino's mispredict penalty and a backend model, a later step.

## 6. Checking the harness

PF-11  The harness is checked three ways, and a result is not used
       until all three pass (Jeff, session-084):
       - exact counts against the reference results: the instruction
         and branch counts of each trace, full and second half, equal
         the reference results' Instr and NumBr columns. This checks
         the trace reader and the committed stream.
       - an oracle mode, in which every prediction is correct: zero
         mispredictions, and the fetched committed stream equals the
         trace.
       - every committed PC equals the trace's next PC.
       The reference results are a yardstick for pacino's MPKI, not a
       check of it: one predictor's mispredictions are not checked
       against another's.

## 7. Process

PF-12  Performance tasks take the prefix PERF-NNN (Jeff,
       session-084). PERF-001 builds nothing for the gasket: it
       fetches and checks the traces, characterizes them, settles
       PF-U2, measures the speed of the Verilated fe_top, and totals
       pacino's predictor storage at fe-1.0.0.

---

## 8. Open

PF-U1  Far conditional branches. A RISC-V conditional branch reaches
       +-4 KB. In CBP2025's two sample traces (1e6 instructions
       each), 2776 of 128874 taken conditional branches (2.2 percent)
       of the int sample and none of the fp sample go further; no
       direct jump or call goes beyond +-1 MB, and no direct branch
       has more than one target. The choices are to relocate the
       code, which moves the PC bits the predictors hash, or to
       branch over a jump, which changes block contents and the
       branch count. PERF-001 counts them across the 105 traces.
PF-U2  What NumBr counts (all branches or conditional branches), and
       that the 50Perc columns are the second half after a first-half
       warmup, from running CBP's own simulator on one trace; and that
       the reference results come from the 64 KB TAGE-SC-L.
PF-U3  Where the traces are stored, outside the tree.
PF-U4  Memory: run bare with a sparse memory model, or build page
       tables so the ITLB and walker are in the measurement. The int
       sample's code spans 0x323048 to 0x80002b44.
PF-U5  The C++ backend: the resolve latency, and the order of resolve
       and commit returned to fe_top.
PF-U6  I-cache control: a switch for a real, preloaded or perfect
       I-cache, so that predictor effects separate from miss effects
       and scenarios can be set up from software.
PF-U7  Whether pacino's predictor parameters can express R's layout
       (table count, history lengths, tag widths, storage) for
       fe-1.0.0/cbp16-64k; pacino's total predictor storage at
       fe-1.0.0.
PF-U8  R stays the CBP2016 64 KB TAGE-SC-L, or becomes the CBP2025
       winner.

---

## 9. Document History

```
  2026-11-09  session-084. Created (Jeff's rulings): PF-1 to PF-12,
              PF-U1 to PF-U8.
```
