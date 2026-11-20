<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Performance Analysis Decisions
```
 FILE:    perf_decisions.md
 SOURCE:  session-084
 STATUS:  DRAFT
 UPDATED: 2026-11-20
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
       FOUND BY PERF-002: the submodule's work tree must be at
       6cc9952; at PERF-002's start it was at 6074966 (upstream main),
       and Jeff checked out 6cc9952 during the task. Mose fails on
       every training trace, in its golden results and in the reruns
       alike (an assertion in perceptron.h), so it cannot be compared.
       Cai and Jimenez give identical results, golden and rerun.

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
       A branch beyond its RISC-V reach goes through a veneer
       (PF-15). The fe_top build is slower per simulated
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

PF-18  THE C++ BACKEND'S TIMING IS SET BY PARAMETERS (Jeff,
       session-086), each given per run:
         resolve latency     cycles from the cycle the backend takes
                             an instruction from the ibuf to its
                             resolve
         resolve to commit   cycles from resolve to commit. Resolve is
                             before commit or in the same cycle, never
                             after it
         take rate           instructions the backend takes from the
                             ibuf per cycle, at most 8
         window              instructions the backend holds, taken
                             from the ibuf and not yet committed; at
                             the limit it takes nothing more. No limit
                             by default; FTQ_DEPTH bounds the blocks
                             in flight either way
       The first three have a minimum, a maximum and a distribution.
       When minimum equals maximum the value is fixed and not
       randomized; when both are 0 the event is immediate, resolve in
       the cycle the backend takes the instruction, or commit in the
       resolve cycle.
       Commit stays in order, and an FTQ entry commits only after
       every resolution naming it (ftq_backend_interfaces.md A7), so
       an instruction commits at its resolve plus the drawn delay or
       at the commit before it, whichever is later.
       PROPOSED (PA), the distributions, named with the range:
         fixed       one value; minimum equals maximum
         uniform     every value in [minimum, maximum] equally likely
         geometric   a mean; mostly short with a long tail, clipped to
                     [minimum, maximum]
         normal      a mean and a standard deviation, clipped
         triangular  a mode, clipped
         table       a file of value and weight lines, for a
                     distribution measured elsewhere
       for example --resolve-lat=uniform:4:20. One seed per run,
       recorded with the result (PF-9). Optionally a distribution per
       branch class (conditional, indirect, return). Built first:
       fixed, uniform, geometric and table.
       Replaces PF-U5.
       BUILT by PERF-002 (perf/src/harness/perf_fe.cc, dist.h):
       fixed, uniform, geometric and table, one seed per run; normal
       and triangular are not built. The ibuf read port takes every
       presented instruction or none (ibuf.sv), so the take rate is a
       credit: each cycle adds the drawn rate, capped at 8, and the
       backend takes when the credit and the window cover the
       instructions presented. The take cycle is the cycle after the
       ibuf handshake. As built, every event defaults to immediate,
       the take rate to fixed:8 and the window to none.
       RULED session-086 (Jeff), BUILT by PERF-003:
       - RESOLVE LATENCY IS A SUM OF STAGES: decode, rename, dispatch
         and execute, each a parameter with a range and distribution
         as above. Resolve to commit stays its own parameter.
       - THE DEFAULT WAS TO BE A NEAR-PERFECT BACKEND: the smallest
         stage and commit values beyond which return mispredicts stop
         changing (the commit race, TD#207), found by a sweep in
         PERF-003; the nearest pacino comes to CBP's scoring, which
         corrects branch history at once with the actual outcome and
         trains the tables later. NOT SET. In the sweep (execute 0..8
         by resolve to commit 0..8, six traces, 2e6;
         perf/studies/perf003_p6_sweep_table.csv) only (8, 8) meets
         the rule: return mispredicts do not settle on five traces
         (media_2 4,815 at (0, 0), 84 at (5, 5), about 600 at execute
         7 and 8; compress_1, infra_1 and int_6 rise with resolve to
         commit). RULED session-086 (Jeff): the default stays
         immediate, and TD#207 is investigated first.
         RETIRED session-086 (Jeff), after BP-153. With TD#207 fixed,
         return mispredicts no longer rise with resolve to commit
         (infra_1 2,791 to 2,848 over the grid, web_11 8,208 to 8,277),
         but the exact rule is still met only at (8, 8): the
         remaining variation is FTB replacement timing, not a race.
         THE IMMEDIATE BACKEND IS THE DEFAULT; the sweep
         (perf003_p6_sweep.sets) stays as a study.
       - THE MISPREDICT RULE. PERF-002 decides a mispredict by the
         fetched stream: a branch mispredicts when the next
         instruction fetch delivers is not the trace's next PC, and a
         branch that ends its fetch bundle waits for that instruction
         (PROVISIONAL). PERF-003 builds the FETCH RULE: the prediction
         fetch used is recorded per FTQ entry at the fetch request and
         at each correction, and a branch is compared with the trace
         in its resolve cycle, as hardware does. Per-predictor
         attribution (pred_src) comes from the same record.
       - THE FETCH RULE IS ACCEPTED IN TWO STEPS, WITH NO TOLERANCE.
         (1) Observe: the stream rule drives the redirects, and the
         fetch rule's verdict, computed beside it, agrees on every
         branch. A disagreement is a harness or RTL defect. Each case
         in which the two may legitimately differ has a written rule
         before the step runs. (2) Drive: the fetch rule drives the
         redirects, and its MPKI is the measurement. It is not
         compared with the stream rule's MPKI.
       - THE STAGES ARE BUILT: --decode-lat, --rename-lat,
         --dispatch-lat and --execute-lat, each its own random stream
         (execute keeps --resolve-lat's, so moved study sets reproduce
         their rows); --resolve-lat is removed and stops a run with a
         message.
       - THE FETCH RULE IS BUILT AND IS THE DEFAULT (--mispredict-rule
         fetch). The record is written at each accepted request (not in
         a flush cycle) and at each predecode correction (the corrected
         slots and w_corr_succ). The verdict is read in the branch's
         resolve cycle, with that cycle's correction applied. The
         fetched stream stays a check (err_stream, err_fetch_rule).
         Observed: 0 disagreements with the stream rule outside the
         written cases in 35 runs; no case was added. The path's last
         branch is not judged. pred_src comes from the record; a
         predecode-corrected slot carries PRED_NONE.
       - THE RESOLUTION TARGET: a conditional resolves with the taken
         target its B-type word encodes, whatever its direction
         (ftb_decisions.md 5.5); a veneered one with its stub. PERF-002
         sent pc + 8 when not taken, which trained false FTB targets
         that predecode repaired: predecode redirects fell by up to
         99.5% and cycles by up to 7.0% with the fix. err_predict was
         those repairs landing after the take; it and the take-time slot
         reading are removed.
       - A TRAP AFTER A BRANCH (the trace's next record an exception
         entry). PERF-003 counts it as the branch's mispredict under
         both rules (mispred_trap_after, 0 to 9 per 2e6 run). RULED
         session-086 (Jeff): the branch is judged on its own outcome,
         and the trap is a separate RC_TRAP redirect, as for a
         non-branch. To be built by PERF-004; orc_slot_trap goes with
         it.

PF-19  THE I-CACHE SWITCH (PF-U6 as written): a run parameter selects
       a real, a preloaded or a perfect I-cache, so that predictor
       effects separate from miss effects and scenarios can be set up
       from software. Built by PERF-002.
       BUILT (perf/src/harness/icache.h): preload fills the L1I with
       the trace's code lines in page first-touch order, to 8 ways
       per set, before the run; perfect writes the line the IFU asks
       for into its set before the arrays read it. Both write
       l1i_meta_array tag_mem and val_mem and l1i_data_array
       data_mem, public through perf/sv/perf.vlt; no RTL file
       changes.

PF-20  ONE PARAMETER SOURCE, IN ONE DIRECTION (Jeff, session-086).
       bp_defines_pkg.sv is the input: a utility reads it and writes
       the standalone model's parameter file (PF-U9). The model's
       file may then be edited directly for a study, without changing
       the RTL. Nothing generates bp_defines_pkg.sv. Applies when the
       standalone model is built. Replaces PF-U10.

PF-21  WHAT PERF-002 BUILT: the trace tools (perf/src); the changed
       traces under CBP_TRACES_RV (default ../cbp_traces_rv), with
       their SHA-256 lists in perf/ (PF-15); the reference reruns
       (tools/perf_rerun.py; the fallback plan run, the full plan
       outstanding); the harness (perf/sv/perf_top.sv,
       perf/src/harness); and the study runner (tools/perf_study.py).
       Build: make -C perf. The oracle check of PF-11 is not built.
       WHAT PERF-003 BUILT: the CPU cap (PF-22); the resolution target,
       the fetch record and the fetch rule, and the backend stages
       (PF-18); the oracle (PF-11); the backend sweep,
       perf/studies/perf003_p6_sweep_table.csv. The take-time slot
       reading (pq_*) and err_predict are removed.

PF-22  THE PERF TOOLS USE AT MOST 75% OF THE MACHINE'S HARDWARE THREADS
       BY DEFAULT, with -j to use fewer or more (Jeff, session-086:
       PERF-002's runs made the machine unusable). BUILT by PERF-003:
       tools/perf_study.py, perf_rerun.py and perf_traces.py, the
       veneer and trace_count tools (perf/src/perf_util.h) and the perf
       Makefile's JOBS default to max(1, floor(0.75 x hardware
       threads)); -j N (JOBS=N) sets N; each prints the count it uses.
       Spreading runs over several machines, the three on the local
       network, is wanted later, as an INFRA task of its own.

## 3. Configurations

PF-5   A measured configuration is named by a release tag, <tag>, for
       the RTL and parameters as tagged; a variant of it is named
       <tag>/<name> (Jeff, session-084). The revision a run measures
       is a parameter, a release tag or head (PF-10). The RTL is
       tweaked between tags; a result on head or on an untagged tree
       is keyed by the sha (PF-9) until the next tag.
       The harness runs a trace in U-mode: every PF-17 leaf has U set
       (PERF-002; S-mode faulted on every fetch).
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
       A STUDY is a set of harness runs: every trace of a trace list
       under every parameter set of a parameter-set list, each run
       with the seed and parameters its set gives, run in parallel
       and gathered into one CSV. Each row is a run's result row
       (the configuration name, the revision sha, the seed and every
       run parameter) with the parameter set's name in front
       (study_set). A parameter set is a name and the harness
       arguments it runs with. The runner is tools/perf_study.py;
       parameter-set files and study CSVs live in perf/studies/
       (PF-2). A study gates no push. Proposed by PERF-002; PF-20
       and PERF-002 used the term undefined.

## 5. Comparison

PF-10  Three are compared (Jeff, session-084):
         R  the reference: TAGE192, run from tools/cbp2025, with the
            other CBP predictors beside it (PF-1)
         A  pacino as built, at the revision a run parameter names:
            a release tag or head (Jeff, session-086)
         B  pacino matched to R's layout and storage, a <tag>/<name>
            configuration (PF-5)
       A against R is the question this work answers. B is built only
       if A's gap to R is large enough that its cause must be known:
       A against B is then the effect of pacino's table sizing, and B
       against R the effect of pacino's microarchitecture (block
       prediction, the overrides, training at resolve, the FTQ).
       fe-1.0.0 cannot be measured: it supports Sv39 only, with a
       36-bit physical address, and the traces need Sv57 (PF-15).
       Runs use head until the next tag (Jeff, session-086).
       B IS NOT BUILT. Whether pacino's predictor parameters can
       express TAGE192's layout has not been tested; TD#204 (Jeff,
       session-086).
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
       until all three pass. The count check answers Jeff's session-084
       request to sanity-check against CBP's results. The oracle and
       PC checks were proposed by the PA in session-084 and were
       recorded here as Jeff's; Jeff kept them in session-086.
       - exact counts against the reference results: the instruction
         and branch counts of each trace, full and second half, equal
         the reference results' Instr and NumBr columns, from the
         published results for an unchanged trace and from the reruns
         for a changed one (PF-15). This checks the trace reader and
         the committed stream.
       - an oracle mode, in which every prediction the FTB makes is
         correct (Jeff, session-086). The wrapper forces each slot's
         direction and target to the trace's, by an SV force by
         hierarchical reference after the predictors and before the
         FTQ; no file under rtl/ changes. It passes with zero
         mispredicts on every branch the FTB had in a slot. A branch
         the FTB did not have, a cold or capacity miss, is counted on
         its own and is expected to be non-zero. The same run's cycles
         are the front end's ceiling with direction and target
         perfect: the design's cycles minus the oracle's are what
         prediction costs. It read: "an oracle mode, in which every
         prediction is correct: zero mispredictions, and the fetched
         committed stream equals the trace."
         BUILT BY PERF-003 (--oracle). Each FTQ entry allocated at p1 is
         aligned with the trace: it is on the path when its PC is where
         a backend redirect sent fetch, or where the trace goes after
         its predecessor's predicted block (the predecessor's fetch
         record once fetched, its entry before that; realigned at p2 and
         p3). For an entry on the path, perf_top forces bp_cluster's
         predictor outputs to the trace's direction and target: at p1
         the uBTB prediction, the loop predictor and the RAS top of
         stack; at p2 the loop predictor, TAGE, the FTB direction, the
         conditional and jump targets, the RAS pop and ITTAGE's targets;
         at p3 SC. Each force is a mux of the trace's value with the
         predictor's own, of a whole variable or element.
         perf/sv/perf.vlt keeps loop_pred, ftb, tage, ittage, sc and ras
         out of inlining so that their ports read unforced; this applies
         to every harness run, and the counts are unchanged. No file
         under rtl/ changes.
         MEASURED (six traces, 2e6 instructions, 18 runs): 0 mispredicts
         on slot-held branches, apart from a branch whose next trace
         record is an exception entry (orc_slot_trap, 0 to 8 per run;
         PF-18). Misses are conditional, indirect and return; direct
         misses are 0, since predecode corrects every jal. THE CEILING
         IS DIRECTION AND TARGET PERFECT, NOT A PERFECT FRONT END: slot
         presence stays the predictors' own, so it still includes the
         FTB's misses (web_11: 67,057 conditional misses) and the p2
         overrides where p1 lacks a slot the FTB has (infra_1: 110,310).
         VERILATOR 5.048, AS FOUND BY PERF-003, for any change to the
         forces: a force through an inlined port is circular (UNOPTFLAT,
         VlForceVec unsupported); a released variable keeps its forced
         value until its driver re-evaluates; a force inside always_comb
         does nothing; of two member forces on one struct element only
         one applies, with no warning; a comment line in a .vlt file
         that starts with a pragma word is read as the pragma.
       - every committed PC equals the trace's next PC.
       The reference results are a yardstick for pacino's MPKI, not a
       check of it: one predictor's mispredictions are not checked
       against another's.

PF-15  Changing a trace invalidates the published reference results,
       which describe the original traces (Jeff, session-084). So, for
       every changed trace:
       - every CBP predictor of PF-1 is rerun on the changed traces,
         and pacino is compared with those runs, not with the
         published results;
       - the change's effect is measured by each predictor's MPKI on
         the changed traces against its golden results on the
         original ones;
       - the traces that need no change are also run as they are, and
         checked against the published results.
       THE TRACES ARE CHANGED: the RISC-V ISA cannot reach every
       traced target directly (Jeff, session-086). A conditional
       branch reaches +-4 KiB and a jal +-1 MiB (tools/scan_traces.py
       BR_MIN to JAL_MAX). PERF-001 counted 11.76e6 direct jumps and
       calls beyond a jal's reach, in 89 traces, and 0.99e6 taken
       conditional branches beyond a branch's reach.
       A BRANCH BEYOND ITS REACH GOES THROUGH A VENEER, as Arm's
       linkers do (Jeff, session-086): the branch keeps its PC and its
       condition and targets a stub within its reach; the stub jumps
       to the traced target with auipc and jalr. Every original PC and
       address is kept; a changed trace gains the stub's records on
       each taken pass through a stub. The code image and the changed
       trace carry the same stubs, so that pacino and the CBP
       predictors see one stream. Where a stub is placed and how its
       records are classed are proposed by PERF-002 and recorded as
       provisional until ruled.
       PROVISIONAL, AS BUILT BY PERF-002. A stub occupies free words
       within the branch's reach: not an executed PC of the trace, not
       another stub's, and not the branch's own pc + 4 (a taken branch
       to its fall-through cannot be told from a not-taken one, and
       CBP's uarchsim asserts against it). The nearest free place is
       taken. A stub serves every far branch in reach to its target;
       conditional sites are placed first. Forms: jal x0, T within
       the stub's jal reach; auipc t1 / jalr x0 within +-2 GiB; beyond
       that a long veneer (auipc t1, 0; ld t1, 16(t1); jalr x0,
       0(t1); an 8-byte literal), never needed by the training set.
       The far branch keeps its PC and condition, and its taken
       target becomes the stub. The stub's records are added on each
       taken pass: class 4 for jal; class 0 (out x16) then class 5
       (in x16) for auipc and jalr; x16 is the register Arm veneers
       use. The training set needs 47,912 stubs (6,668 jal, 41,244
       auipc and jalr) for 113,814 far sites; 0 two-hop, 0 unplaced;
       24,504,622 records added; 19 pages only stubs touch. A direct
       jump or call with more than one traced target (web_9_trace's
       three PCs, 21 records) changes to its indirect class and needs
       no veneer. A PC seen in more than one class (web_11_trace's 9
       PCs, rewritten code) holds its most frequent class in the code
       image; a pass through a minority record is repaired and
       counted (class_conflict_passes).
       Because the addresses are kept, every PC must be canonical under
       a mode pacino supports. Every PC of every trace
       (perf/cbp2025_training_scan.csv pc_mode_min, BP-145): 24 traces
       are canonical under Sv39, 18 more under Sv48, and the other 63
       only under Sv57; none needs more than Sv57
       (pc_noncanon_sv57_static is 0 in every trace). Pacino supports
       Sv57 (mmu_decisions.md MMU-20).

PF-16  REMOVED, session-086 (Jeff). It read "the traces run unchanged,
       under Sv57", which does not account for the reach of RISC-V
       branches. Its trace address counts are in PF-15. The number is
       not reused.

PF-17  THE TRACES RUN BEHIND PAGE TABLES (Jeff, session-085), so the
       ITLB and the walker are in the measurement. Each code page a
       trace touches is mapped by a 4 KiB leaf to a physical page
       allocated densely, in the order the trace first touches it,
       from the start of main memory (mmu_decisions.md MMU-15a). The
       mode is Sv57 (mmu_decisions.md MMU-20; PF-15). A generator
       built on pt_build_pkg writes the tables as a memory image file;
       the gasket (PF-4) loads it. Each leaf has V, R, X, A and U set,
       and W, D and G clear; the root is the first page after the
       last code page and the other table pages follow it; the image
       is text, every value hexadecimal with no prefix: header
       comments, a satp line
       (MODE Sv57, ASID 0, the root's PPN), one map line per page in
       first-touch order, and one word line per table word. RULED
       session-085 (Jeff). A non-canonical input address, or an input
       that does not fit main memory, stops the generator. BUILT by
       BP-149: rtl/mmu/ptw/tb/pt_gen.sv (+IN page list, +OUT image);
       rtl/mmu/ptw sim_ptw_img walks every page of a checked-in
       sample's image with the walker. The page list a trace touches
       is extracted by PERF-002, and the gasket is PERF-002's.

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
PF-U4  CLOSED session-085 (Jeff) by PF-17. It read: "Memory: run
       bare with a sparse memory model, or build page tables so the
       ITLB and walker are in the measurement."
PF-U5  CLOSED session-086 (Jeff) by PF-18. It read: "The C++
       backend: the resolve latency, and the order of resolve and
       commit returned to fe_top."
PF-U6  CLOSED session-086 by PF-19, which states it as written.
PF-U7  CLOSED session-086 (Jeff): B is not built; whether pacino's
       parameters can express TAGE192's layout is TD#204 (PF-10). It
       read: "Whether pacino's predictor parameters can express R's
       layout (table count, history lengths, tag widths, storage),
       needed only if B is built." Pacino's storage is settled: all
       predictors 102.48 KB as built (DOC-016; PERF-001's 67.29 KB
       counted one copy of the per-slot tables).
PF-U8  Closed: R is TAGE192 (PF-10).
PF-U9  A standalone performance model, leading the RTL and in time
       covering the whole core and parts of the system, correlated
       with the gasket on the same traces and counters. Discussed in
       session-084: built for pacino rather than adopted (an adopted
       model brings its own microarchitecture, which makes
       correlation harder), trace-driven first, front end first.
       Later (Jeff, session-086). Its language, Rust or C++, follows;
       the gasket stays C++, since Verilator generates C++. Its
       parameters: PF-20.
PF-U10 CLOSED session-086 (Jeff) by PF-20. It read: "One parameter
       source for the RTL and the model, from which bp_defines_pkg and
       the model's configuration are both generated."
PF-U11 CLOSED session-086 (Jeff) by PF-15, veneers. It read: "Far
       conditional branches, beyond +-4 KB: 0.99e6 in the training set
       (PERF-001). The linker form is an inverted branch over a
       jal."

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
  2026-11-12  session-085, after BP-145. PF-16: the counts from every
              PC; the entry above gave 53 and 28, from pc_min and
              pc_max alone.
  2026-11-13  session-085 (Jeff). PF-17: page tables, dense 4 KiB
              physical pages in first-touch order; PF-U4 closed.

  2026-11-14  session-085 (PA). PF-17: the generator's leaf, table
              placement and image format PROPOSED with BP-149.

  2026-11-15  session-085, after BP-149. PF-17: the generator's details
              RULED (Jeff) and BUILT.
  2026-11-16  session-086 (Jeff). PF-16 removed: the traces are
              changed, far branches through veneers (PF-15); PF-4,
              PF-11 and PF-17 follow. PF-10: A at a tag or head,
              fe-1.0.0 not measurable, B not built (TD#204). PF-18 the
              backend timing parameters, PF-19 the I-cache switch,
              PF-20 the parameter direction; the window limit a
              PF-18 parameter. PF-U5, PF-U6, PF-U7,
              PF-U10 and PF-U11 closed; PF-U9 later.
  2026-11-18  session-086, PERF-002 recorded. PF-1, PF-5, PF-9 (study),
              PF-15 and PF-19 record PERF-002 as built; PF-21 what it
              built. PF-11: the oracle as an FTB-slot oracle by SV
              force, kept (Jeff); its attribution corrected. PF-18:
              built as recorded; stage latencies, the near-perfect
              default, the fetch rule and its two-step acceptance
              ruled (Jeff), for PERF-003. PF-22 the CPU cap.
  2026-11-18  session-086, PERF-003 recorded. PF-11: the oracle as
              built, what its ceiling includes, the Verilator force
              findings. PF-18: the stages, the fetch rule and the
              resolution target built; the near-perfect default not
              set, the default immediate until TD#207 (Jeff); a trap
              after a branch judged apart (Jeff), for PERF-004. PF-21,
              PF-22: built.
  2026-11-20  session-086, after BP-153. PF-18: the near-perfect
              default retired; the immediate backend is the default
              (Jeff).
```
