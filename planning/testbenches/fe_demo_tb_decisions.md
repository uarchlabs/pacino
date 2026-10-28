<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Front-End Demonstration Testbench Decisions
```
 FILE:    fe_demo_tb_decisions.md
 SOURCE:  session-080
 STATUS:  DRAFT
 UPDATED: 2026-10-28
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
         waves/       one Surfer command file per scenario;
                      fe_demo_sigs.py, the signal lists, built for
                      the slot count of the model that wrote each FST,
                      the format table FORMATS, and the FST reader;
                      mk_sucl.py, the generator, which writes each
                      command file from its own scenario's FST and
                      reads the descriptions' event tables (FDT-12c);
                      chk_sucl.py, which loads each command file in
                      Surfer and checks it against fe_demo_sigs.py,
                      FDT-12a and FDT-12c
         docs/        one description per scenario,
                      demo_explainer.md, and the fe_top connectivity
                      inventory
         README.md    the scenario list, how to run one, what to look
                      for
       tb/ holds tb_fe_demo.sv, fe_demo_mon.svh, fe_demo_lib.svh,
       fe_demo_proofs.svh and fe_demo_finish.cpp.
       Run output goes to examples/fe_demo/out/<scenario>/, which is
       not committed. The two models are built into
       examples/fe_demo/obj_fe_demo/ (one slot) and obj_fe_demo_2slot/
       (two slots), not committed.
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
FDT-5  Two builds (Jeff, session-081). The default model is built at
       NUM_PRED_SLOTS = 1 (+define+BP_NUM_PRED_SLOTS=1
       +define+BP_EXPECT_PRED_SLOTS=1), in obj_fe_demo/; a second at
       2, the package default, in obj_fe_demo_2slot/. Each scenario
       names the build it runs on (fe_demo_scenarios.md FD-0a); the
       Makefile lists the 2-slot scenarios in SCEN_2S.
FDT-6  CSR state comes from csr_tb_pkg (csr_decisions.md CSR-2).
FDT-7  Every scenario runs with the fast SRAM init except FD-1, which
       runs the full init walk.

---

## 3. Running

FDT-8  One make target per scenario, named by its FD number and a short
       name (for example fd04_p2_override). A target builds the model
       of its scenario's build if needed, runs the scenario and writes
       its waveform and log. Names are fdNN_<name>; output is
       out/<name>/<name>.fst and .log, for either build.
FDT-9  A make target, scenarios, runs every scenario in FD order. It
       stops at the first failing scenario; make -k scenarios runs all.
FDT-9a make view S=<scenario> opens the scenario in Surfer with its
       command file. <scenario> is the target name of FDT-8
       (fd02_steady). It brings the scenario's model up to date and
       runs the scenario first when its FST is missing or older than
       that model. A missing S prints the usage
       and fails; an S that is not a scenario lists the valid names
       and fails. The viewer is the variable SURFER, set in
       rtl/Vars.mk to $(RVA_ROOT)/tools/bin/surfer with ?=, so the
       command line or the environment may override it; the
       Makefile does not set it. A failing run still writes its FST,
       and the viewer opens on it.
       view runs Surfer with RUST_LOG set from the variable
       SURFER_LOG, default warn: Surfer's default level prints INFO
       lines on every start, and warn keeps its warnings, such as a
       .sucl command it does not understand. SURFER_LOG=info gives
       the full output.
FDT-10 Each run ends by checking the scenario's proof (FD-0b). It
       prints one result line and exits non-zero on a failure so make
       stops. A pass is -I: <scenario>: PASS, then the figures; a
       failure is -E: <scenario>: FAIL, then the figures.
FDT-10a Every line the testbench prints is at most 80 columns. A line
       begins with -I:, -W: or -E:, then the scenario name and a colon.
       Items are separated by commas and named in full words; the
       cycle count is cyc <n>. A line longer than 80 columns breaks
       after a comma, and each continuation line is indented four
       spaces with no prefix:
         -I: fd09_tage: PASS, tagged-provider predictions 216,
             allocations 65, T0 by use_alt_on_na 37, cyc 1277
       A passing run prints no other line: the simulator's $finish
       message is replaced (tb/fe_demo_finish.cpp, VL_USER_FINISH)
       and its end-of-run report is off (+verilator+quiet). After a
       failing result line the simulator prints the lines of $fatal,
       which are outside this format. The shared models'
       (rtl/core/frontend/fe_top/tb/models/) ERROR: and +TRACE lines
       keep tb_fe_top's format.
FDT-10b The monitor counts, from the cycle the three init readies are
       all high: the cycles the p0 request is withheld, in total and
       by cause as ftq_decisions.md 4.5 numbers them (H1 per
       predictor, split into queue full and starvation hold; H2; H3;
       H4); and the FTB updates in total, missed, and written back
       unchanged on a hit, each by conditional and jump. Each run
       prints them in the FDT-10a format after the result line.
       TD#188; not yet built.

---

## 4. Waveforms

FDT-11 Each run writes an FST waveform to its output directory.
FDT-12 Surfer is the one supported viewer. GTKWave is not supported:
       no save files, no rc file and no make target for it (Jeff,
       session-080). The FST opens in any viewer that reads FST.
       The scripts in waves/ read the FST with fst2vcd, from the
       GTKWave distribution; that tool, not the viewer, stays a
       dependency.
FDT-12a waves/<scenario>.sucl is a Surfer command file: the signals of
       the scenario's waveform entry (fe_demo_scenarios.md FD-0b), in
       pipeline order, in groups named by unit, the clock first. Names
       are shown with name type Unique, the shortest suffix of the
       path that identifies the signal. make view loads it with the
       FST. Formats:
         clk                 Clock
         rstn                Bit
         cyc                 Unsigned
         an enum-typed field Enum, the value names Verilator writes
                             into the FST
         every other signal  the format of the table FORMATS in
                             fe_demo_sigs.py (Jeff, session-081)
       The table's rules:
         a 1-bit signal                     Bit
         a per-slot or per-lane mask        Binary
         a count or iteration number        Unsigned, at any width
         the SRAM init write addresses      Unsigned
         an address, target, PC or data     Hexadecimal
         an encoded field                   Unsigned; its encoding is
                                            given in the description
                                            that shows it
       The encoded fields are itlb_ifu_status, itlb_ifu_cause,
       l2t_itlb_status, l2t_itlb_cause, itlb_l2t_priv and trx_type. At
       one slot a per-slot mask is 1 bit, so Bit. A signal the table
       does not match stops mk_sucl.py. The signals of a per-slot list
       are those of the slot count of the model that wrote the FST.
FDT-12b Every Surfer file shows the testbench cycle counter cyc, which
       counts cycles from the release of reset.
FDT-12c A Surfer file places one marker per event of the scenario's
       event table (FDT-13 section 4), at the first time in the
       scenario's FST at which cyc equals the event's value with rstn
       high (for cyc 0, the release of reset). It opens with the view
       from two cycles before the first marker to thirty after it;
       Surfer 0.7 cannot open at a marker with goto_marker in a command
       file, which it parses before it runs. The table in
       docs/<scenario>.md is the source: mk_sucl.py reads it, a row
       with a cyc value starts an event and a row with an empty cyc
       continues the one above. A marker is named c<cyc>_<label>, the
       label being the event text up to its first ';', ':', ',' or '(',
       at most six words, joined by '_'. A description is in the
       FDT-13 form when its level-2 headings are the five of FDT-13, in
       order, section 5 optional, after an optional leading
       "0. Introduction" (Jeff, session-081, DOC-007). A scenario with
       no description in that form has no markers. A description in
       that form whose table mk_sucl.py cannot read stops the generator
       with an error naming the file and row.

---

## 5. Descriptions

FDT-13 docs/<scenario>.md describes one scenario. Its reader is
       skilled in decoupled front ends and branch prediction and is
       working out how the pacino front end works. After the header
       block it has five sections, which may follow an introduction,
       section 0 (Jeff, session-081, DOC-007):
         1  What the scenario shows: the behaviour, the result line
            the run prints, and what must happen for it to pass.
         2  The program: the listing, every instruction written out
            with its address and purpose, and an explanation of it.
         3  Walkthrough: the theory of operation of each behaviour,
            and where to see it in the waveform, by the value of cyc;
            each point ends with the RTL file and signal that
            implement it.
         4  Events: a table, column 0 cyc, column 1 description,
            column 2 other details where needed. The first row is cyc
            0, the release of reset. Each row with a cyc value starts
            an event; a row with an empty cyc continues it. Each event
            is a marker in the Surfer file (FDT-12c).
         5  Notes: present only when there is something the reader
            must act on, and it says what to do.
FDT-13a The descriptions are written in full sentences, with no jargon
       and no abbreviation the text has not introduced. A testbench
       variable, task or file is named explicitly with where it is
       defined; a design term is explained at first use or in
       docs/demo_explainer.md. The words "lands" and "shape" are not
       used, nor the framing "X but not Y". Each description is
       checked with tools/ticfinder/tools/ticfinder.py before it is
       complete.
FDT-13b docs/demo_explainer.md explains, once, how a scenario is built
       and run: the program writer, the list of instructions the
       testbench expects to retire, the backend model, the result
       line and the proof, and cyc. It ends with a glossary of the
       front-end terms the descriptions use.
FDT-14 docs/fe_top_connectivity.md is the connectivity inventory of
       fe_top as built: the instances, the connections between them
       grouped by interface, the ports that cross the fe_top boundary
       grouped as fe_decisions.md FE-17 and FE-20 group them, and one
       level inside bp_cluster. Every entry cites file and line. The
       front-end block diagram, docs/fe_block.svg, is drawn from it.

---

## 6. Open

FDT-U1 The trace writer (planning/observ/fe_trace_decisions.md) is
       added by a later DOC task, not DOC-002 (Jeff, session-080).

---

## 7. Document History

```
  2026-10-14  session-080. Created.
  2026-10-14  session-080, after DOC-001. FDT-1, FDT-4, FDT-8, FDT-9,
              FDT-12 as built.
  2026-10-15  session-080. FDT-1 docs/ and the Surfer files; FDT-9a
              view and sview; FDT-12a; section 5, FDT-13 and FDT-14;
              FDT-U1 moved past DOC-002.
  2026-10-15  session-080, after DOC-002. FDT-1 waves/ as built;
              FDT-9a failing runs; FDT-10 and FDT-10a, the result line
              and message format (Jeff); FDT-12a, FDT-12b; FDT-13 the
              five-section form, FDT-13a, FDT-13b (Jeff).
  2026-10-15  session-080, after DOC-003. FDT-1 tb/ and docs/ as
              built; FDT-10a the lines outside the format.
  2026-10-16  session-080. FDT-10b, the p0 hold and FTB update
              counters (TD#188), drafted.
  2026-10-16  session-080. FDT-9a: Surfer's log level, SURFER_LOG
              (Jeff, Makefile edited by hand).
  2026-10-16  session-080. GTKWave dropped (Jeff): FDT-1 waves/,
              FDT-9a make view opens Surfer, FDT-12. FDT-12a name type
              Unique and the formats; FDT-12b; FDT-12c the event
              markers from the description's table; FDT-13 item 4.
  2026-10-16  session-080. FDT-12c: only FDT-13-form descriptions
              give markers; an unreadable table is an error.
  2026-10-16  session-080, after DOC-004. FDT-1 waves/, FDT-9a the
              environment's SURFER, FDT-12 fst2vcd, FDT-12c as built,
              FDT-13 item 4 events.
  2026-10-16  session-080. FDT-9a: SURFER's default is rtl/Vars.mk's
              (Jeff fixed Vars.mk); the Makefile workaround goes.
  2026-10-18  session-081, after DOC-006. FDT-1 waves/ and the model
              directories; FDT-5 two builds (Jeff); FDT-8, FDT-9a per
              build; FDT-12a the format table (Jeff).
  2026-10-19  session-081, after DOC-007. FDT-12c, FDT-13: a leading
              0. Introduction section is allowed (Jeff).
  2026-10-28  interactive session, branch install_scripts (IA, Jeff's
              authorization). FDT-9a: SURFER's default is
              $(RVA_ROOT)/tools/bin/surfer, built by
              tools/build_tools.sh at commit 010b840, the build these
              command files were checked with
              (new_user_decisions.md NU-17).
```
