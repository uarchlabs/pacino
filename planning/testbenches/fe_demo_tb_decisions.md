<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Front-End Demonstration Testbench Decisions
```
 FILE:    fe_demo_tb_decisions.md
 SOURCE:  session-080
 STATUS:  DRAFT
 UPDATED: 2026-10-14
 CONTACT: Jeff Nye
```

Owns the FDT-N and FDT-UN registries.

The testbench that runs the scenarios of
planning/showcase/fe_demo_scenarios.md. It is a demonstration, not a
verification testbench.

---

## 1. Location and structure

FDT-1  The testbench is examples/fe_demo/, a top-level directory beside
       rtl/:
         Makefile     includes rtl/Vars.mk
         tb/          the testbench top and its scenario code
         programs/    one program per scenario, or per group of
                      scenarios (fe_demo_scenarios.md FD-U1)
         waves/       one GTKWave save file per scenario
         README.md    the scenario list, how to run one, what to look
                      for
       tb/ holds tb_fe_demo.sv, fe_demo_mon.svh, fe_demo_lib.svh and
       fe_demo_proofs.svh. waves/mk_gtkw.py writes the save files from
       a run's FST.
       Run output goes to examples/fe_demo/out/<scenario>/, which is
       not committed.
FDT-2  examples/ is not scanned by tools/regress.sh and has no
       regression target.

---

## 2. What it instantiates

FDT-3  The top instantiates fe_top and the walker beside it, as
       tb_fe_top does, and drives the same ports.
FDT-4  The testbench models of tb_fe_top -- the memory model shared by
       the L1I and the walker, the in-order backend, the walker
       hookup, the program writer and the CSR setup through
       csr_tb_pkg -- are factored into a shared directory under
       rtl/core/frontend/fe_top/tb/. tb_fe_top and the demonstration
       both use them. tb_fe_top's figures and check counts are
       unchanged by the factoring.
       The shared directory is rtl/core/frontend/fe_top/tb/models/:
       fe_tb_dut, fe_tb_writer, fe_tb_mem, fe_tb_be_state,
       fe_tb_backend and fe_tb_csr (.svh), include fragments of module
       tb. The including testbench defines be_retire_hook and
       be_trap_hook. The backend's be_rdy_pat is 0 for tb_fe_top.
FDT-5  NUM_PRED_SLOTS = 2. No 1-slot build.
FDT-6  CSR state comes from csr_tb_pkg (csr_decisions.md CSR-2).
FDT-7  Every scenario runs with the fast SRAM init except FD-1, which
       runs the full init walk.

---

## 3. Running

FDT-8  One make target per scenario, named by its FD number and a short
       name (for example fd04_p2_override). A target builds if needed,
       runs the scenario and writes its waveform and log. Names are
       fdNN_<name>; output is out/<name>/<name>.fst and .log.
FDT-9  A make target, scenarios, runs every scenario in FD order. It
       stops at the first DEMO FAIL; make -k scenarios runs all.
FDT-10 Each run ends by checking the scenario's proof (FD-0b). It
       prints one line, DEMO PASS or DEMO FAIL with the scenario name,
       and exits non-zero on DEMO FAIL so make stops.

---

## 4. Waveforms

FDT-11 Each run writes an FST waveform to its output directory.
FDT-12 waves/<scenario>.gtkw opens it in GTKWave with the signal groups
       of the scenario's waveform entry, in pipeline order, the groups
       named by unit, the clock first.

---

## 5. Open

FDT-U1 The trace writer (planning/observ/fe_trace_decisions.md) is
       added by a later task, DOC-002.

---

## 6. Document History

```
  2026-10-14  session-080. Created.
  2026-10-14  session-080, after DOC-001. FDT-1, FDT-4, FDT-8, FDT-9,
              FDT-12 as built.
```
