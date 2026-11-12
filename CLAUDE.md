<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

```
 FILE:    CLAUDE.md
 SOURCE:  various
 STATUS:  WORKING
 UPDATED: n/a
 CONTACT: Jeff Nye
```

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
- Planning docs:     Planning documents are never modified by the IA.
                     Files under planning/, pa_handoffs/ and docs/ are
                     READ-ONLY in every task. The IA reports what a
                     planning document should say; the PA drafts it and
                     Jeff applies it.
                     This is NOT overridable by a task file. A planning
                     path in Deliverables, or in a "Files expected to
                     change" list, does not grant write permission.
                     WAIVER: only an explicit statement from Jeff in the
                     task file, naming the files and the task ID, permits
                     an IA write. A waiver covers that task only. It is
                     never precedent and never propagates to the next
                     task, even one continuing the same work.
- Packages:          A task may ADD, CHANGE or REMOVE declarations in
                     any package (bp_defines_pkg.sv, bp_structs_pkg.sv,
                     decode_pkg.sv) when its task file scopes the
                     change. Every change is listed in Results Capture
                     with its derivation.
                     A PACKAGE DECLARATION THAT SHADOWS A MODULE-LOCAL
                     DECLARATION IS A BUILD BREAK under -Wall, not a
                     tidy-up. Sequence the change WITH the modules that
                     stop declaring it locally, or state plainly that
                     the tree is broken in between.
                     Every package task ends by running
                     tools/regress.sh; its summary goes in Results
                     Capture. Any red result not in
                     tools/known_failures.txt blocks Status: complete.
                     The IA does not edit tools/known_failures.txt.
---

## Style Rules - enforced by style scripts, no exceptions

- Line width:   80 column maximum. Use all 80 columns when available
                do not format against 60 columns when you have room for
                the remainder.
- Table line width: The 80 column maximum does not apply for markdown tables.  
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
- Spelling:     American English in all prose, comments and identifiers.

## Commands
- Construct commands that minimize triggering a permissions request
- Read, search and list files with the Read, Grep and Glob tools, not
  with shell commands. A Bash command names its files by literal paths:
  no shell variables, $(...) or backticks, loops, or xargs.
- Run tools/regress.sh once, at the end, in the background, and wait
  for it to finish before writing Results Capture; no file changes
  while it runs. Its run is longer than the 600 s foreground limit.
  Take its summary whole from its output, sha line included, not cut
  by a pipe. Run tools/regress_demo.sh in the foreground.
- rtl/core/frontend/bpu/tb/tb_ras.sv is too large to Read whole (up to
  20k tokens per read). Search it, or Read only the line range you need
  with offset/limit.
- RTL rules (combinatorial style, package imports, Verilator work
  arounds, Makefile conventions) live in rtl/CLAUDE.md.

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
  The exceptions are the header fields Model, Run time, Ctx % and
  Resume sha, and the region between :: CONTEXT:START :: and
  :: CONTEXT:END ::, populated per "Model Reporting in Task Files"
  below.
- No default permission is allowed for git commands unless expressed
  in the task file. Unless permission has been granted the IA
  must ask for permission before proceeding.
- Run every command from the repo root. Do not prefix a command with
  cd to an absolute path; name files by paths relative to the root,
  and use make -C <dir> or a subshell ( cd <dir> && ... ) only where
  a tool must run in another directory. Scratch files go in the
  session's scratchpad directory.
  EXCEPTION: Firefox is installed as a snap and cannot read the
  scratchpad. A task that checks pages with headless Firefox may use
  ~/snap/firefox/common/<TASK-ID>_tmp for the browser profile and
  screenshots, and for nothing else. This folder needs no listing in
  Context Loaded or Deliverables. The IA removes it before writing
  Results Capture and reports there that it was created and removed.
- Create every file, scratch scripts included, with the Write tool,
  then run a script as python3 <file> or bash <file>. Do not create
  or change files with shell heredocs, redirects or python3 - <<EOF.
- Results Capture content must be ASCII only. No Unicode.
- Final console output should avoid non-ASCII if possible.
  This is a preference but not a hard requirement.

- EXCEPTION to the rule above: planning documents. A path
  under planning/, pa_handoffs/ or docs/ in Context Loaded
  is read-only, and the same path in Deliverables does not
  make it writable. Report the change you would have made
  in Results Capture instead. See Fixed Constants.

## Model Reporting in Task Files
- When the prompt context contains :: HEADER:START :: the
  session is running a project task file. In this case,
  before writing Results Capture, populate the Model
  header field with the running model name and effort
  level in this format:
    | Model | <model-name> <effort-level> |
  Example: claude-sonnet-4-6 normal
- Run time, Ctx % and Resume sha, and the region between
  :: CONTEXT:START :: and :: CONTEXT:END ::, are written only by the
  /cntx command, after the task has finished, as that command
  describes. The IA does not write them while working the task.
- Model reporting applies to both automated and manual
  task sessions.

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
- A testbench must exit non-zero on any failed check: $fatal(1) on the
  failure path, $finish only on the pass path, in exclusive branches.
- THE REGRESSION IS tools/regress.sh. Every task that ends in a
  status claim runs it from the repo root with no arguments:
    ./tools/regress.sh
  It finds every Makefile under rtl/ and runs every test target in
  each, one make call per target. This covers targets `all` omits
  and both units after a package edit. Do not enumerate targets by
  hand and do not scope the run to a subset.
- Report the summary block it prints: the git sha line, one line per
  target, and the totals. Counts written to Results Capture or
  PROJECT_STATUS come from a run in the current session. Do not carry
  a prior session's count.
- A non-zero exit blocks Status: complete. Mark the task in-progress
  or abandoned and report the failures.
- The only waived failures are those listed in tools/known_failures.txt.
  A task file cannot add a waiver. The IA never edits
  tools/known_failures.txt; it proposes entries in Results Capture and
  Jeff applies them.
- A new lint, sim or cov target must be added to REGRESS_TARGETS in
  its Makefile, or to REGRESS_EXCLUDE with a reason. regress.sh fails
  on any target in neither list.
- THE DEMONSTRATION REGRESSION IS tools/regress_demo.sh. It runs the
  examples/fe_demo scenarios and gates no push. A DOC task that
  changes examples/fe_demo/ runs it, and a failing scenario not in
  tools/known_failures_demo.txt blocks Status: complete. A task that
  changes rtl/ runs it and reports its failing scenarios; they do not
  block that task. The IA never edits tools/known_failures_demo.txt.

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

## Verification - assertions

- A property compares the checked signal against a source
  INDEPENDENT of the RTL that drives it: another module's state,
  a value the property derives itself, or an earlier cycle.
- A property that restates its driving assignment is not a check
  and is not written. It cannot fail without an edit to that line,
  and Verilator may fold it away entirely. INFRA-013 found 9 of 18
  ftq_ifu properties of this kind.
- A property whose antecedent or consequent is driven only by the
  testbench checks the stimulus, not the RTL. Say so or move it.

---

- Each chat is a fresh experiment. Do not assume anything from prior
  chats.
- If a requirement seems ambiguous, state your assumption explicitly
  before proceeding and record it in Results Capture.
- Flag any RVA23 compliance risks or gaps you notice.
- Write the Results Capture section of the experiment file as a
  required deliverable. Do not wait to be asked.

---

## Guidance during interactive sessions

- Before raising a topic the user did not ask about, check whether it is 
  already closed. If it is, do not raise it. If you think a closed item is 
  wrong, say so in one sentence and wait, do not re-argue it.

- Do not use unnecessary jargon, and picturesque phrasing, "That was an excuse
  wearing a diagnosis costume." That is one example of many, not the entire
  example set.

 
## Current Scope

Updated at the start of each experiment session. See the experiment
prompt (e.g. BP-001.md) for the current module and task description.
