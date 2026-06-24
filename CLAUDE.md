<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Project: RISC-V RVA23 Processor Design
You are assisting with the iterative RTL design and verification of a
RISC-V processor. Work through each module systematically, delivering
production-quality outputs.

---

## Fixed Constants - apply to every session without exception

- Architecture:      RISC-V, strictly RVA23 profile compliant
- Microarchitecture: 8-issue out-of-order processor. All design
                     decisions must be consistent with this target,
                     even when working on front-end stages.
- RTL:               SystemVerilog only. No VHDL, no Verilog-2001.
                     Fully compatible with Verilator v5.048.
                     One module per file. File name must match module
                     name. Exception: testbenches.
- Testbenches:       SystemVerilog, fully compatible with Verilator
                     v5.048. File name: tb_<name of dut>.sv.
                     The module name inside the testbench is always tb.
- Deliverables:      Always provide both the RTL file and the
                     testbench unless explicitly told otherwise.

---

## Style Rules - enforced by style scripts, no exceptions

- Line width:   80 column maximum. Use all 80 columns when available
                do not format against 60 columns when you have room for
                the remainder.
- Indent:       2 spaces. No tabs anywhere.
- Comments:     ASCII only. No Unicode, no special characters.
                Use -> instead of arrows or dashes with angle brackets.
                Use - for bullet points in comments.
- Naming:       Favor readability. Comment non-obvious logic.
                Use named parameters over magic numbers.
- Common ports: Active low reset is rstn.
                Rising edge clock is clk.
                Add clk/rstn only as needed. Combinatorial-only
                modules do not require these ports.
                Declare ports on one line when they fit within 80 cols

## Combinatorial Logic Style

- Prefer always_comb blocks over cascaded continuous
  assign statements when signals form a dependency
  chain (A depends on B depends on C). Verilator v5.048
  evaluates assign statements using an internal
  dependency DAG and may read stale values when a
  chain is evaluated out of order. always_comb blocks
  evaluate statements in textual order, eliminating
  the ambiguity.
- Single assign statements with no internal
  dependencies are acceptable.

## Experiment File Rules
- Only read or write files explicitly listed in the
  Context Loaded manifest or Deliverables section. Do
  not create, modify, or write to any file not in these
  lists. This includes comment blocks, headers, and any
  other content in listed files that is outside the
  explicit scope of the prompt. If a change outside
  scope appears necessary, stop and report it before
  making the change.
- Write Results Capture into ./prompts/<TASK-ID>.md
  Fill in every section completely.  Do not leave any
  section as TBD if information is available.
- When writing Results Capture, write only within the
  :: RESULTS:START :: :: RESULTS:END :: markers. Do not
  modify any content outside these markers.
  The sole exception is the Model header field, 
  which the IA populates per "Model Reporting in Task Files" below.

- Results Capture content must be ASCII only. No Unicode.
- Final console output should avoid non-ASCII if possible.
  This is a preference but not a hard requirement.

## Model Reporting in Task Files
- When the prompt context contains :: HEADER:START :: the
  session is running a project task file. In this case,
  before writing Results Capture, populate the Model
  header field with the running model name and effort
  level in this format:
    | Model | <model-name> <effort-level> |
  Example: claude-sonnet-4-6 normal
- Ctx % is captured manually by Jeff. Do not attempt to
  populate it programmatically.
- Model reporting applies to both automated and manual
  task sessions.

## Package imports
Import at file scope, before the module declaration. Do not place
import statements inside the module header between the module name
and the port list.

  Correct:
    import bp_defines_pkg::*;
    import bp_structs_pkg::*;
    module foo (

  Incorrect (Verilator accepts but project rejects):
    module foo
      import bp_defines_pkg::*;
      import bp_structs_pkg::*;
    (

For package imports the order of bp_defines_pkg and bp_structs_pkg are
important. It must be defines first then structs

    import bp_defines_pkg::*;
    import bp_structs_pkg::*;

---

## Microarchitectural Implications - keep in mind across all modules

- Front-end must sustain 8 instructions per cycle to the backend
  under ideal conditions.
- Interfaces between modules must be sized and structured to support
  8-wide dispatch.
- Design for out-of-order execution. Assume downstream stages include
  rename, reservation stations, and a reorder buffer.
- Avoid design choices that implicitly assume in-order execution.
- vtype dependency policy for intra-bundle vsetvl is TBD - to be
  decided at rename/dispatch stage. Decoder marks is_vsetvl and
  needs_vtype in the vec_decode_t packet. Rename resolves the
  dependency.

---

## Verification Expectations

- Testbenches must be self-checking. Do not rely on manual waveform
  inspection.
- Include directed tests for boundary conditions and known edge cases.
- Include a basic sanity check that runs in under 10 seconds with
  Verilator.
- A verification, testbench, debug, or cleanup task must run the
  COMPLETE existing test suite for every module named in the task
  header or Deliverables, not only the directed tests the task
  adds. Report the full pass/fail count for each suite run.
- A non-green suite for an in-scope module blocks Status: complete.
  Mark the task in-progress or abandoned and report the failures.
- Exception: failures explicitly listed in the task Constraints as
  known/waived, each citing a tech-debt number, do not block
  completion. Any failure NOT on that waiver list blocks.
- Status counts written to PROJECT_STATUS must come from a run in
  the current session. Do not carry a prior session's count.
- ALL TARGETS MUST RUN. Every generated prompt's run step
  invokes every sim and lint target defined in the unit's
  Makefile, whether or not that target is a dependency of
  `all`. `make all` is not sufficient -- a target omitted
  from `all` is still run. Enumerate the Makefile's targets
  and run each one. Report the pass count and fail count for
  every target, from a run in the current session. No prompt
  scopes the run to a subset. A port rename, a one-line fix,
  a comment change -- every target runs regardless. Any sim
  target with a non-zero fail count, or any lint target with
  a non-zero warning or error count, blocks Status: complete,
  unless that specific failure is listed in Constraints with
  a TD number.

## Verification - self-contained tests (no test debt)

- A test must not depend on unverified behavior or on test order.
- Within the run, before claiming a path proven:
  - Enumerate every mechanism the test stimulus relies on (e.g.
    reset values, sentinels, selection/threshold, allocation
    residue, index/tag hashes). Verify each, or seed it
    explicitly. Do not assume a hash/tag value -- derive it.
  - Invalidate unrelated table entries that could alias the
    index/bank under test. Do not rely on absence of residue.
  - Establish start state by reset plus a known driven sequence.
    Do not carry state across test cases.
- Report any dependency found unproven and prove it in this run.

---

## Project Structure

- clusters: frontend, midcore, backend, memory_system
- units:    each cluster contains units e.g. fetch, decoder,
            branch_predictor
- modules:  each unit contains one or more modules
- each module has: rtl/, tb/, verilator/, tests/, Makefile, README.md

---

## Verilator work arounds

- stl_sequent rule: always_comb blocks that must re-evaluate after FF
  updates must read at least one FF output. Pure module-input-only
  always_comb blocks are classified stl_sequent and will not see
  signal changes after simulation start. Gate prediction scan blocks
  on a registered valid signal to force nba_sequent.

## Verilator Makefile Conventions

- Always include -Wno-DECLFILENAME in sim targets. The project naming
  convention (module tb in file tb_<dut>.sv) triggers this warning by
  design. It is not a defect -- suppress it project-wide.
- Use -Wall for all other warnings. Sim and lint targets must both
  exit zero with zero warnings after -Wno-DECLFILENAME and any
  session-specific suppressions noted in the experiment constraints.
- Session-specific suppressions (e.g. -Wno-UNUSED for package-only
  sessions) are listed in the experiment Constraints section and
  must not be added to CLAUDE.md.
- Always include -Wno-IMPORTSTAR in VER_FLAGS. The project
  mandates file-scope wildcard import (import bp_pkg::*;
  before the module declaration). Verilator v5.048 warns on
  wildcard imports in $unit scope. This is structural and
  suppressed project-wide.
- -Wno-VARHIDDEN: add to individual sim or lint targets only when
  a module parameter intentionally shadows a bp_pkg parameter
  (e.g. NUM_PRED_SLOTS). Do not add to VER_FLAGS.
- Always include -Wno-UNUSED in VER_FLAGS. Package-only
  files and structs not yet consumed by any module will
  trigger unused warnings. This is structural and
  suppressed project-wide.
- add --timing to VER_FLAGS in Makefiles (required by Verilator
  v5.048 for @(posedge clk))

---

- Each chat is a fresh experiment. Do not assume anything from prior
  chats.
- If a requirement seems ambiguous, state your assumption explicitly
  before proceeding and record it in Results Capture.
- Flag any RVA23 compliance risks or gaps you notice.
- Write the Results Capture section of the experiment file as a
  required deliverable. Do not wait to be asked.

---

## Current Scope

Updated at the start of each experiment session. See the experiment
prompt (e.g. BP-001.md) for the current module and task description.

