<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Performance Analysis Decisions
```
 FILE:    perf_decisions.md
 SOURCE:  session-084
 STATUS:  DRAFT
 UPDATED: 2026-11-12
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
       (https://github.com/ramisheikh/cbp2025). The published
       reference results are from the CBP2016 64 KB TAGE-SC-L, the
       simulator's default, with indirect prediction perfect; NumBr
       counts conditional branches only, so their MPKI counts
       conditional mispredictions only (PERF-001, Problem 3).
       The trace format is generic at the predictor's view: a record
       carries the PC, an instruction class, the branch direction and
       target, and register values; it carries no instruction bytes.
       Every PC is 4-byte aligned.
       Licensing: the cbp2025 repository has no top-level license;
       its simulator sources carry an NCSU BSD-style notice. Pacino
       is Apache-2.0, which is one reason no CBP code is mixed in.
       The traces are Arm's. The readme.txt beside them says they are
       "provided for the sole purpose of the competition as an aid to
       learning and academic advancement", without warranty. Whether
       publishing results from them fits that use is Jeff's to decide
       before results are published.
       The repository is used through Jeff's public fork,
       https://github.com/jeffnye-gh/cbp2025.git, as the submodule
       tools/cbp2025 (PF-2), by its HTTPS URL so that an anonymous
       clone with --recurse-submodules works. The submodule pins
       commit 6cc9952 on the branch jeff/baseline (Jeff, session-084),
       which adds the nine CBP2025 entries (Behrendt, Cai, Fan,
       Jimenez, Koizumi, Man, Mose, Ros, Seznec), CBP2016 and TAGE192
       as separate binaries, make targets to run and summarize them,
       and golden results of every one on the original traces.
       CBP is temporary scaffolding for this work. The entries'
       licenses are set aside (Jeff, session-084): eight of the nine
       carry no license notice of their own; the CBP2025 rules say
       only that source code, papers and results are made public.

PF-2   Perf scripts live in tools/ with pacino's other scripts, the
       first being tools/scan_traces.py. Perf data, the trace
       checksum list and the scan results, and the harness itself
       (the SystemVerilog wrapper and the C++ gasket) live in perf/
       (Jeff, session-084). A script finds perf/ from the repository
       root, not from its own directory.
       An external repository used by the work is a git submodule
       under tools/. Pacino code and external code are not mixed in
       one directory (Jeff, session-084).
       Moved after PERF-001, which wrote perf/scan_traces.py: Jeff
       moved it to tools/ and reran it from the repository root; the
       new perf/cbp2025_training_scan.csv equals the reference
       results' instruction count for all 105 traces.
       The traces are not in git. Where they are and how they are
       checked is PF-14.

PF-14  The traces live outside the repository, unpacked from CBP's
       .tar.xz archives into one .gz file per trace, one directory
       per group (Jeff, session-084). A perf script finds them through
       the environment variable CBP_TRACES, default ../cbp_traces
       relative to the repository root; no machine path is written in
       code. Each .gz file is checked against a recorded SHA-256 list,
       perf/cbp2025_training.sha256, before it is read.
       All the perf setup notes, for every user, are in the main
       README.md, not a README under perf/. A perf script that cannot
       find or check its traces stops with a message naming the
       problem and that README section (Jeff, session-084).
       A Claude Code user who restricts reads outside the repository
       adds the trace directory with --add-dir or in their own
       settings; Jeff's is in his untracked .claude/settings.local.json
       (additionalDirectories), tested in session-084: reads there do
       not prompt. A symlink inside the repository does not serve: the
       read check covers the path the link resolves to.
       The archives are not read in place: a .tar.xz is one stream, so
       reaching one trace decompresses all before it.

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
       Far conditional branches are PF-U11 (PF-U1 until
       session-085). The fe_top build is slower per simulated
       instruction than bp_cluster alone.

PF-13  Instructions reach a timing model through one interface,
       designed for trace-driven and execution-driven supply alike,
       even while only the trace-driven side exists (Jeff,
       session-084):
       - the timing model asks for the instruction at a PC, on the
         path it is on, not for the trace's next record.
       - the interface carries a redirect (a squash and the new PC)
         and a commit point.
       Its suppliers, the first now and the others later: the CBP
       trace reader, which returns filler off the traced path (PF-8);
       traces with the wrong path added; a functional simulator, such
       as spike, rolled back on a redirect.
       The gasket (PF-4) and a standalone model (PF-U9) use the same
       interface: fe_top already fetches by PC from the gasket's
       memory and takes redirects and commits from its backend.
       Moving from trace-driven to execution-driven then changes the
       supplier, not the timing model.
       References: FAST, Chiou et al., MICRO 2007 (a functional model
       running ahead, forced back onto the correct path by the timing
       model); Mauer, Hill and Wood, "Full-system timing-first
       simulation", SIGMETRICS 2002 (the reverse arrangement); Pepi et
       al., "Correct Wrong Path", arXiv 2408.05912 (the wrong path
       added to ChampSim after the fact: a new trace format, traces
       1.53x to 3.25x larger, and changes to the simulator core).

## 3. Configurations

PF-5   A measured configuration is named by a release tag, <tag>, for
       the RTL and parameters as tagged; a variant of it is named
       <tag>/<name> (Jeff, session-084). The first, and the one B
       would be named for if built (PF-10):
         fe-1.0.0             A, the baseline: pacino as tagged
         fe-1.0.0/tage192     B, the matched: pacino's predictor
                              parameters set to match R's layout and
                              total storage; built only if needed
       The RTL is tweaked between tags; a result on an untagged tree
       is keyed by the sha (PF-9) until the next tag.
       The predictor enables are custom CSRs 0x7C0 and 0x7C1
       (csr_pkg.sv:121-133, 204-205). Their reset values are
       unchanged: SC enabled; the FTB fast path, TAGE aging and ITTAGE
       aging disabled; both aging intervals 0. For a performance run
       the harness writes them once reset has finished, or at once
       when fast init is used (Jeff, session-084):
         sc_enable              1
         ftb_fastpath_en        1
         tage_enable_aging      1
         ittage_enable_aging    1
         tage_aging_interval    262144 (2^18)
         ittage_aging_interval  262144 (2^18)
       The interval is TAGE's usual useful-counter reset period: gem5's
       TAGE model resets every 2^18 conditional-branch updates
       (logUResetPeriod 18; L-TAGE 19), halving each useful counter.
       Pacino's interval counts p2 predictions per slot
       (tage_cntrl.sv:397-410), so it is not exactly a branch count.
       A configuration that sets them otherwise says so in its name.
       2^18 holds until TD#197, the investigation of the aging and
       epoch design, closes; the intervals are to become parameters
       (Jeff, session-084).

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
       the full trace and, in the 50Perc columns, the trailing
       1e6-instruction epochs from the trace's midpoint, with the
       predictor trained from the start of the trace (PERF-001,
       Problem 3). The harness reproduces that epoch rule exactly.
       The Verilated fe_top's SystemVerilog testbench runs 4.4e3 to
       8.3e3 instructions per second: 146 to 272 hours for the
       training set on one process, a bound the C++ harness only
       improves on (PERF-001, Problem 4).
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

PF-10  Three are compared (Jeff, session-084):
         R  the reference: TAGE192, run from tools/cbp2025, with the
            other CBP predictors beside it (PF-1)
         A  pacino as built (fe-1.0.0)
         B  pacino matched to R's layout and storage, a <tag>/<name>
            configuration (PF-5)
       A against R is the question this work answers. B is built only
       if A's gap to R is large enough that its cause must be known:
       A against B is then the effect of pacino's table sizing, and B
       against R the effect of pacino's microarchitecture (block
       prediction, the overrides, training at resolve, the FTQ).
       The CBP predictors' MPKI counts conditional branches only
       (PF-1); pacino's ITTAGE and RAS are measured but have no
       counterpart in R.
       Pacino's direction storage, as built: TAGE + SC + loop 41.75
       KB, two copies of 20.88 KB, one per prediction slot (DOC-016;
       pacino_features.md 2.9).
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

PF-15  Changing the traces' addresses invalidates the published
       reference results, which describe the original traces (Jeff,
       session-084). So, if any trace is changed:
       - every CBP predictor of PF-1 is rerun on the changed traces,
         and pacino is compared with those runs, not with the
         published results;
       - the change's effect is measured by each predictor's MPKI on
         the changed traces against its golden results on the
         original ones;
       - the traces whose addresses fit pacino unchanged are also run
         as they are, and checked against the published results.
       A direct jump or call whose target is beyond the +-1 MB of a
       RISC-V jal becomes an auipc and jalr pair, as a RISC-V linker
       emits it, in the code image and in the changed trace alike, so
       that pacino and the CBP predictors see one stream (Jeff,
       session-084). PERF-001 counted 11.76e6 of them, in 89 traces.
       Which addresses are changed, and how, was PF-U1; PF-16
       changes none.

PF-16  THE TRACES RUN UNCHANGED, UNDER SV57 (Jeff, session-085).
       Pacino supports Sv57 (mmu_decisions.md MMU-20), so every trace
       address is used as recorded and PF-15 does not apply. From
       perf/cbp2025_training_scan.csv pc_min and pc_max (PA,
       session-085): both extremes are canonical under Sv39 in 24
       traces, under Sv48 in 53 more, and only under Sv57 in the
       other 28; none needs more than Sv57. Every PC, not only the
       extremes, is checked by BP-145.

## 7. Process

PF-12  Performance tasks take the prefix PERF-NNN (Jeff,
       session-084). PERF-001 builds nothing for the gasket: it
       checks the traces, characterizes them, settles
       PF-U2, measures the speed of the Verilated fe_top, and totals
       pacino's predictor storage at fe-1.0.0.

---

## 8. Open

PF-U1  CLOSED session-085 (Jeff) by PF-16. It read: "The address
       scheme. 81 of the 105 traces have PCs at or above 2^41 ... a
       Sv57 variant of pacino, under which every trace address is
       canonical and the traces run unchanged ...; Sv39 page tables
       built by the gasket, each PC keeping its low 38 bits ... (PF-15
       then applies)." Its far conditional branch sentence is PF-U11.
PF-U2  Closed by PERF-001, into PF-1 and PF-7.
PF-U3  Closed by PF-14.
PF-U4  Memory: run bare with a sparse memory model, or build page
       tables so the ITLB and walker are in the measurement. The int
       sample's code spans 0x323048 to 0x80002b44.
PF-U5  The C++ backend: the resolve latency, and the order of resolve
       and commit returned to fe_top.
PF-U6  I-cache control: a switch for a real, preloaded or perfect
       I-cache, so that predictor effects separate from miss effects
       and scenarios can be set up from software.
PF-U7  Whether pacino's predictor parameters can express R's layout
       (table count, history lengths, tag widths, storage), needed
       only if B is built (PF-10). Pacino's storage is settled: all
       predictors 102.48 KB as built (DOC-016; PERF-001's 67.29 KB
       counted one copy of the per-slot tables).
PF-U8  Closed: R is TAGE192 (PF-10).
PF-U9  A standalone performance model, leading the RTL and in time
       covering the whole core and parts of the system, correlated
       with the gasket on the same traces and counters. Discussed in
       session-084: built for pacino rather than adopted (an adopted
       model brings its own microarchitecture, which makes
       correlation harder), trace-driven first, front end first. Not
       yet ruled. Its language, Rust or C++, follows; the gasket
       stays C++, since Verilator generates C++.
PF-U10 One parameter source for the RTL and the model, from which
       bp_defines_pkg and the model's configuration are both
       generated, so that a configuration name (PF-5) names one
       parameter set. Not yet ruled.
PF-U11 Far conditional branches, beyond +-4 KB: 0.99e6 in the
       training set (PERF-001). The linker form is an inverted branch
       over a jal. Moved from PF-U1, session-085.

---

## 9. Document History

```
  2026-11-09  session-084. Created (Jeff's rulings): PF-1 to PF-13,
              PF-U1 to PF-U10.
  2026-11-09  session-084, before PERF-001 (Jeff). PF-1 the Arm notice
              and the fork; PF-14 the trace location, CBP_TRACES, the
              checksum list and the README; PF-U3 closed.
  2026-11-10  session-084, after PERF-001 and DOC-016 (Jeff). PF-1 the
              reference results, the jeff/baseline pin and the
              entries; PF-7 the epoch rule and the speed; PF-10 R is
              TAGE192, B optional, the storage; PF-15 new; PF-U1
              rewritten as the address scheme; PF-U2, PF-U8 closed;
              PF-U7 narrowed.
  2026-11-10  session-084 (Jeff). PF-2: perf scripts in tools/, perf
              data and the harness in perf/; PF-14 names the checksum
              list.
  2026-11-10  session-084 (Jeff). PF-5: the CSR reset values are kept;
              a performance run enables SC, the FTB fast path and
              TAGE and ITTAGE aging after reset, intervals 2^18.
  2026-11-12  session-085 (Jeff). PF-16: the traces run unchanged
              under Sv57; PF-U1 closed; its far conditional branch
              part moved to PF-U11, and PF-4 points there.
```
