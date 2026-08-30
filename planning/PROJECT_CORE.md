<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Project Core — RISC-V RVA23 Processor Co-Design
```
 FILE:    PROJECT_CORE.md
 SOURCE:  various
 STATUS:  STABLE
 UPDATED: 2026-08-22
 CONTACT: Jeff Nye
```

Stable reference. Paste into Claude.ai only when methodology
is under discussion. Not required for routine sessions.

---

## Project Overview

AI-assisted co-design experiment for a RISC-V RVA23 8-issue
out-of-order processor. Jeff provides architectural decisions
and direction. Claude.ai provides design guidance and writes
experiment prompts. Claude Code implements the RTL and
testbenches.

This project is also a research experiment in AI-assisted
hardware co-design methodology. The prompt framework, results
capture, and experiment discipline are themselves contributions
worth documenting for an audience of experienced hardware
architects evaluating AI-assisted design flows.

Repo:  https://github.com/jeffnye-gh/riscv-codesign
Local: ~/Development/jeffnye-gh/riscv-codesign

---

## Terminology

The project record uses two abbreviations that appear in file
names, handoffs and postmortems. They are defined here and
nowhere else.

```
  PA    Planning Assistant. Claude.ai in the web interface.
        Writes prompts, drafts planning documents, evaluates
        results. Handoffs in pa_handoffs/.
  IA    Implementation Assistant. Claude Code in the terminal.
        Writes RTL and testbenches, runs Verilator. Handoffs in
        ia_context/ia_handoffs/.
```

Task IDs use three prefixes:

```
  BP-NNN     a BPU or front-end task, RTL or specification
  INFRA-NNN  a read-only IA audit or inventory task
  COMP-NNN   a shared-component task
```

A PA-direct edit -- a planning document the PA drafts and Jeff
pastes without an IA task -- takes NO task number. Cite it as
"PA-direct correction, session-NNN". Attaching an unissued task
ID to one is how INFRA-012 came to be cited three times before it
was ever generated.

---

## Roles

Claude.ai (PA):
- Provides architectural guidance and design recommendations
- Writes experiment session prompts
- Evaluates results reported by Jeff
- Drafts planning document changes for Jeff to apply
- Plans next experiments
- Makes recommendations but defers all decisions to Jeff
- Writes the session handoff, including its own postmortem

Claude Code (IA):
- Reads CLAUDE.md automatically at session start
- Implements RTL per session prompt pasted by Jeff
- Runs Verilator and iterates on errors autonomously
- Writes files directly to the repo
- Does NOT modify planning documents; see Planning document
  ownership below
- One experiment = one fresh Claude Code session

Jeff:
- Makes all architectural decisions
- Pastes session prompts from Claude.ai into Claude Code
- Reports Claude Code results back to Claude.ai
- Applies planning document changes drafted by the PA
- Commits results to git
- Bridges Claude.ai and Claude Code

---

## Workflow

- Claude.ai (web): architectural guidance, writes experiment
  prompts
- Claude Code (terminal): implements RTL, runs Verilator
- Jeff: bridges the two

To start a new Claude.ai session:
1. Paste latest pa_handoffs/session_handoff-NNN.md delta
2. Paste planning/PROJECT_STATUS.md
3. Paste CLAUDE.md

The new session has full context and can begin immediately.
Paste planning/PROJECT_CORE.md only when methodology is under
discussion.

---

## Methodology Conventions

### Experiment discipline
- One experiment = one fresh Claude Code session
- Never resume between experiments
- CLAUDE.md is re-read automatically by Claude Code each
  session
- ASCII only in all RTL comments
- 80 column line width enforced in prompts
- funct6 values must come from riscv-opcodes files, not
  training data
- Read before write: Claude Code reads relevant RTL before
  generating

### Planning document ownership
PLANNING DOCUMENTS ARE NEVER MODIFIED BY THE IA. Files under
planning/, pa_handoffs/ and docs/ are read-only in every task.
The IA reports what a document should say; the PA drafts it;
Jeff applies it.

This is not overridable by a task file. A planning path in
Deliverables, or in a "Files expected to change" list, does not
grant write permission -- that list is a convenience and was
never scoped to act as one.

WAIVER. Only an explicit statement from Jeff in the task file,
naming the files and the task ID, permits an IA write. A waiver
covers that task only. It is never precedent and does not
propagate to the next task, even one continuing the same work.
BP-098 through BP-105 ran under such a waiver and it expired
with BP-105.

CLAUDE.md carries the enforcing copy of this rule, in Fixed
Constants. This section is the rationale; that one is the rule
the IA reads.

### Experiment file structure
An experiment file (e.g. BP-001.md) is the single document
for a task, created from templates/TASK_TEMPLATE.md. Sections
in order:
- Task header: ID, date, module, run time, ctx%, model,
  resume sha, PA session, task type checkboxes, mode
  checkboxes, status checkboxes
- Overview of task: brief narrative, filled by Jeff/Claude.ai
- Results Discussion: populated after, by Jeff/Claude.ai.
  Contains follow-on actions, CLAUDE.md updates, other
  planning file updates.
- Claude Code Prompt: generated by Claude.ai, pasted by Jeff
- Results Capture: written by Claude Code directly into this
  file, between the :: RESULTS:START :: and :: RESULTS:END ::
  markers and nowhere else

Prompt section structure:
- Task ID
- Context Loaded: explicit @file manifest -- Claude Code
  loads exactly these files and nothing else for this task.
  No prose in this section.
- Context Comments: all prose about the context files
- Hypothesis
- Background
- Binding Previous Decisions
- Specific Requirements (step-by-step, read-before-write
  enforced) OR Problems (see Prompt form below)
- Constraints
- Deliverables (includes instruction to write Results Capture
  section, names exact file path)

### Prompt form: problems, not procedure
Two forms are in use and the choice is deliberate.

- STEPWISE. Numbered requirements the IA executes in order.
  Correct when the work is mechanical and the sequence
  matters.
- PROBLEMS. A small number of stated problems, each with
  acceptance criteria, leaving method, ordering and
  decomposition to the IA. Introduced session-066 and it
  produced a better result than the stepwise form on the same
  class of work: the IA found a defect class no requirement
  had named, and bounded another by enumerating every site
  rather than fixing the one it was pointed at.

Prefer PROBLEMS for verification, audit, cleanup and debug
tasks. Prefer STEPWISE for a specified RTL build. The failure
mode of the problems form is a false premise in the problem
statement, not the freedom -- so every factual claim in a
problem statement must be checked against the tree before the
prompt is written.

### Context minimization
- Context Loaded manifest is the gating mechanism -- scope
  it tightly
- Planning files decomposed by domain so tasks load only
  what they need
- CLAUDE.md stays lean: rules only, no history, no examples
- Architectural reasoning lives in PROJECT_STATUS.md and
  planning/arch/
- However there should be no automated /compact commands 
  given or instructed. Context management is manual

### Prompt content
- Good detail: constraining Jeff's architectural decisions
- Bad detail: over-specifying implementation (reduces LLM
  leverage)
- Binding Previous Decisions: only items NOT in planning
  docs or genuinely easy to guess wrong. Everything else
  belongs in the planning document, which Claude Code reads
  via the manifest.
- Constraints section: experiment-specific items only.
  Global style rules live in CLAUDE.md and must not be
  repeated in prompts. Suite-gating waiver lists ARE
  experiment-specific (which tests, which TD numbers, this
  task) and belong here -- they are not the global-rule
  restatement this bans. See prompt generation rules below.
- A constraint that fences an area the requirements send the
  IA into will strand the session's best finding. Check the
  constraints against the requirements before issuing.

### Prompt generation rules
- Do not add CLAUDE.md to the context in generated prompts.
  Claude Code already loads that file. Reloading wastes
  context.
- Do not restate rules already in CLAUDE.md: one module per
  file, line width, indent, reset/clock naming, style rules.
- -Wno-VARHIDDEN is already in CLAUDE.md. Do not duplicate
  in prompts.
- THE PA DOES NOT INSTRUCT THE IA ON SESSION OPERATION. Context,
  compaction, model selection, run length, status line, and
  anything else the operator controls are Jeff's, not the task
  file's. A task file specifies WORK. This is the same class of
  error as the two rules above -- writing about the IA's
  ENVIRONMENT rather than its task -- and it will not always be
  spelled /compact.
- Do not use results marker syntax in prompt guidance text.
  Using :: RESULTS:START :: / :: RESULTS:END :: markers in
  guidance causes validation script failures. Instead write:
  "Results Capture filled in below."
- Describe generate block style explicitly in prompts to
  prevent context explosion.
- Claude Code will violate explicit rules. Review all
  deliverables against the prompt Deliverables section
  before accepting a result as complete.
- Every factual claim in a Hypothesis or Background section
  must be verified against a file in the manifest before the
  prompt is issued. Half of BP-097 was spent correcting
  premises the PA had asserted about files it had loaded and
  not read.
- Package files bp_defines_pkg.sv and bp_structs_pkg.sv are
  located at:
    rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
    rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
  Do not use short paths -- these will fail the file
  existence check in validate_and_extract.py.
- For known prompt failure modes see ANTIPATTERNS.md.
- Suite-gating waivers: CLAUDE.md requires the IA to run each
  in-scope module's complete suite and blocks completion on any
  non-waived failure. When writing a verification, testbench,
  debug, or cleanup prompt for a unit that has known/open suite
  failures, the Constraints section MUST enumerate the waived
  tests and cite each one's tech-debt number. A failure not on
  that list will (correctly) block completion. Omitting the
  waiver list will strand legitimate work as in-progress.

### Results capture
- Claude Code writes its summary directly into the experiment
  file Results Capture section as a required deliverable.
  The Deliverables section must name the exact file path.
  Claude Code must fill in every section completely and must
  not read or write any file not listed in Context Loaded
  or Deliverables.
- Jeff pastes or copies that section into Claude.ai for
  discussion
- Results Discussion filled in after the session, not during.
  The PA does not pre-fill it.
- When experiment confirms a decision: graduate to CLAUDE.md

### Standing rules
Each of these was paid for by a session and is not re-argued.

- A NEGATIVE RESULT IS A DELIVERABLE. A problem that comes
  back "no defect, here is the enumeration that bounds it" is
  a completed problem, not a failed one.
- FIX WHAT YOU FIND. A defect found while working a problem is
  repaired in the run that found it, not deferred to a
  follow-on task.
- A TASK'S STATUS CHECKBOX IS NOT EVIDENCE THAT IT RAN. BP-100
  carried Status: complete while its own Summary read NOT RUN,
  its Date and Model fields were empty and no RTL existed.
  Requirement 0 of any task that could re-run prior work must
  check the TREE first and stop on a partial state rather than
  overwrite it.
- HISTORICAL RECORDS ARE NOT CORRECTED. docs/sessions.json,
  prior Results Capture sections, and CLOSED_TECH_DEBT closure
  entries record what was true when written. A stale type name
  or figure in one of those is not a defect. The exception is
  an entry that was wrong at the moment it was written.
- STATUS COUNTS COME FROM THE CURRENT SESSION. Never carry a
  prior session's pass/fail count into PROJECT_STATUS.
- A PROPERTY NEVER OBSERVED TO FIRE IS A COMMENT. Every bound
  concurrent property is proven live by FAULT INJECTION: break
  the thing it guards on a scratchpad copy outside the tree,
  confirm the property's own text appears, revert. BP-107 found
  46 of 73 inert on the first pass, and 14 of one file's 15
  defined but never asserted. A green suite carrying inert
  assertions is worse than one carrying none, because it
  reports coverage it does not have. Note that a concurrent
  property only samples state present at a clock edge, so a
  case that drives its inputs, checks at a delta and moves on
  will leave the property inert however well it is written.
- A GREEN REPORT IS NOT EVIDENCE THAT A TARGET STILL BUILDS.
  It records what was true when the session that wrote it ran,
  and the tree changes underneath. BP-106 reported 155 checks
  green; the packages then gained declarations those modules
  still held locally, and four targets stopped building with
  nothing anywhere to say so. Requirement 0 asks what EXISTS.
  Running the suite is what tells you what WORKS.

### Postmortem practice
Every PA handoff carries a postmortem of the PA's own
performance in that session, continuing a numbered trend log.
It is not optional and it is not softened. The log exists
because the same failure classes recur -- claims carried into
prompts unchecked, manifests inferred rather than read,
constraints that block real work -- and a named trend is
harder to repeat than an isolated apology.

### Dictate vs. propose
Jeff dictates (micro-architectural intent):
- Predictor hierarchy and component roles
- Prediction pipeline depth and timing availability
- Override and redirect architecture
- Training and update policy

Claude Code proposes (subject to Jeff review):
- Internal signal naming within stated conventions
- SV struct/package decomposition
- Testbench structure
- Parameterization within specified ranges

---

## Repository Layout

```
  planning/       specification and decision record. See below.
  prompts/        one file per task, BP-NNN.md / INFRA-NNN.md
  templates/      TASK_TEMPLATE.md
  pa_handoffs/    session_handoff-NNN.md, PA to next PA session
  ia_context/
    ia_handoffs/  ia_session_handoff-NNN.md, IA to next IA
    background/   reference translations, e.g. xs_ifu_ftq.md,
                  fe_qaa.md
  docs/           sessions.json, decomposition logs, backend
                  stubs
  rtl/            see Project Structure in CLAUDE.md
  tools/          tools/bin install dir, riscv-opcodes submodule
```

---

## Planning Directory (planning/)

### The directory contract
```
  planning/*.md         project-wide record and registries
  planning/arch/        decisions and rules: what the design
                        does and why. Owns the FE / TD-FE /
                        FE-U / G registries.
  planning/interfaces/  port specifications: what crosses a
                        module boundary. Names declared RTL
                        ports; the RTL is the reference.
  planning/testbenches/ testbench decisions
  planning/verification/coverage and validation plans
```

A decision goes in arch/. A port list goes in interfaces/. When
a document would carry both, split it -- the FTQ set is the
worked example: ftq_decisions.md holds behaviour, and three
ftq_*_interfaces.md files hold the boundaries.

ONE PROSE HOME PER SUBJECT. A structure or a rule is described
in exactly one document and cross-referenced from the others.
The FTQ entry was described in three places and edited in
lockstep until fe_decisions sections 4, 5 and 6 were moved out
whole to ftq_decisions.md and ftq_entry_formats.md; the vacated
sections are RETIRED, not reused, so old cross-references still
resolve rather than resolving to something else.

### Document status
A planning document's status is its MATURITY, and it is
recorded in exactly one place: the PROJECT_STATUS Module
Status table. The values in use are Draft, Working, Complete,
Not started and Deprecated.

Status is NOT permission. Who may write a document is settled
once, by Planning document ownership above, and the answer is
the same for every file under planning/: the IA does not, the
PA drafts, Jeff applies. A per-file permission marker would be
a second encoding of that one rule, free to disagree with it.

LOCKED IS RETIRED. It was never a Module Status value. It
appeared exactly twice, as an aside on two cross-references to
bp_cluster.md, and nothing maintained it. It read as
permission at a time when permission was not stated anywhere
else, and it made a necessary change to a document look like a
violation while the front end was still being designed.
bp_cluster.md is Working. Do not reintroduce a permission
marker on a planning file.

### Current inventory
Navigational only. PROJECT_STATUS.md Module Status is the
authoritative list and carries each document's status.

```
planning/
  PROJECT_CORE.md            this file
  PROJECT_STATUS.md          living record, updated every
                             session
  CLOSED_TECH_DEBT.md        closure entries, historical
  GLOSSARY.md                pipe stage notation, naming
  ANTIPATTERNS.md            known prompt failure modes
  arch/
    bp_cluster.md            BP cluster summary data
    bp_arb_spec.md
    bp_history_decisions.md
    fe_decisions.md          front-end theory of operation.
                             Owns FE-1..FE-14, TD-FE-1..8,
                             FE-U1..FE-U9.
    ftq_decisions.md         FTQ-owned behaviour
    ftq_entry_formats.md     sole prose home for
                             bp_ftq_entry_t / bp_ftq_meta_t
    ftb_decisions.md
    ftb_confidence_override_rules.md
    icache_decisions.md      L1I geometry, both interfaces,
                             miss handling, maintenance,
                             prefetch. Owns L1I-N, TD-L1I-N,
                             L1I-UN
    ras_decisions.md
    sc_decisions.md
    sc_table_hash_rules.md
    sram_init.md
    tage_cntrl_decisions.md
    tage_cntrl_ctr_update_rules.md
    tage_cntrl_uaon_update_rules.md
    tage_cntrl_use_update_rules.md
    ittage_cntrl_decisions.md
    ittage_cntrl_alloc_rules.md
    ittage_cntrl_ctr_update_rules.md
    ittage_cntrl_uaon_update_rules.md
    ittage_cntrl_use_update_rules.md
    ittage_table_entry_formats.md
    ittage_table_hash_rules.md
  interfaces/
    bpu_port_inventory.md    140 ports, eight modules
    ftq_bpu_interfaces.md
    ftq_ifu_interfaces.md
    ftq_backend_interfaces.md
    bp_history_interfaces.md
    ubtb_interfaces.md
    loop_pred_interfaces.md
    tage_interfaces.md
    tage_table_interfaces.md
    ittage_interfaces.md
    ittage_table_interfaces.md
    ras_interfaces.md
    ftb_interfaces.md
    sc_interfaces.md
    sc_table_interfaces.md
  testbenches/
    manual_tb_decisions.md
    sc_tb_decisions.md
  verification/
    tage_coverage_plan.md
    sc_coverage_plan.md      not yet written
```

There is no ftq_icache interface and there will not be one from
this phase. If physical design meets the fanout pressure
XiangShan solved with register replication, the answer is a
PD-phase path, not a logical interface carried from the start.
ftq_decisions.md 0.

THE ICACHE IS A SIBLING OF THE IFU, not inside it. Jeff's ruling,
session-068: it is its own module within the front-end boundary
and the IFU exposes the interface to it. An earlier revision of
this paragraph said the ICache was encapsulated behind the IFU
and that is no longer accurate. WHAT SURVIVES IS THE PARAGRAPH
ABOVE: independence changes the module hierarchy, not the absence
of an FTQ-to-ICache interface. icache_decisions.md L1I-2.

### Interface specification approach
Primary currency: SV structs in packages (not SV interfaces).
Rationale: better Verilator compatibility, simpler for Claude
Code.

BP cluster uses s-stage notation (s0/s1/s2/s3) to match the
prediction pipeline. P-stage notation used elsewhere.

Array direction convention, package-wide: packed-struct
dimensions descend, [NUM_PRED_SLOTS-1:0]; port dimensions
ascend, [0:NUM_PRED_SLOTS-1].

---

# Tools Status

| Tool       | Version                        | Location                          | Notes                         |
|------------|--------------------------------|-----------------------------------|-------------------------------|
| Verilator  | 5.048 2026-04-26 rev v5.048    | $(RVA_ROOT)/tools/bin/verilator   | Upgraded session-044.         |
|            |                                |                                   | inout optimizer bug fixed.    |
|            |                                |                                   | TD #38 partially addressed.   |
|            |                                |                                   | Covergroup #7099 re-check     |
|            |                                |                                   | still pending.                |
| Spike      | --                             | $(RVA_ROOT)/tools/bin/spike       | See TOOLS-002 for ISA string  |
|            |                                |                                   | issue.                        |
| Surfer     | --                             | $(USER)/.cargo/bin/surfer         |                               |
| Var.mk     | --                             | $(RVA_ROOT)/rtl/Var.mk            | Common Makefile variables.    |
|            |                                |                                   | VERILATOR, SPIKE, SURFER      |
|            |                                |                                   | paths. All RTL Makefiles      |
|            |                                |                                   | include this file.            |
|check_rva23_coverage.py | --    | ./tools                  | Uses submodule: tools/riscv-opcodes |
|                        |       |                          | make coverage: exits non-zero on MISSING |
|                        |       |                          | --strict flag: treats ROUTED as MISSING (off by default) |
| IA status line         | --    | ./claude/statusline.sh   | Two-line display:                             |
|                        |       |                          |  Total: <tokens> \| Ctx: <k used> \| Ctx: <%> |
|                        |       |                          |  Reset: <Hh MMm>                              |
|                        |       |                          |  Requires jq. Ctx% uses used_percentage (accurate field). |
|                        |       |                          |  Reset countdown derived from |
|                        |       |                          |  rate_limits.five_hour.resets_at. |
|                        |       |                          |  Note: display lost on terminal scroll. Run script directly |
|                        |       |                          |  to restore: ~/.claude/statusline.sh |

### Common
tools/bin: $(RVA_ROOT)/tools/bin is the common install directory for all submodule tools.
README.md updated to show build instructions for Verilator and Spike.

### make targets
Make targets are discoverable by analysis of the Makefile.
`make all` is NOT a complete run: it omits targets. Enumerate
the Makefile's targets and run each one. See CLAUDE.md,
Verification Expectations, and TD#99.

THE bpu GAP IS KNOWN AND IS RECORDED HERE so no session has to
rederive it. `all` names 38 of the 47. The NINE it omits:

```
  sim_ittage        sim_tage_manual
  cov_history       cov_ubtb          cov_loop_pred
  cov_tage_table    cov_tage          cov_bp_cluster
  cov_bpu
```

All 18 lint targets ARE in `all`; the gap is two sim targets and
every coverage target. Verified against the Makefile session-068.
If the Makefile changes, this list changes with it -- it is a
convenience, and the Makefile is still the reference.

The known RTL make files are:
```
./rtl/Makefile
./rtl/lib/Makefile
./rtl/core/frontend/decode/Makefile
./rtl/core/frontend/bpu/Makefile
./rtl/core/frontend/ftq/Makefile
```

A unit's target count is per-unit. The bpu unit is 47 targets
(18 lint, 22 sim, 7 cov). The ftq unit is 22 targets (11 lint,
11 sim) and 670 checks as of BP-107, which completed it. Count
them separately; do not fold the ftq figures into the bpu total
or read "47 of 47 green" as covering the tree.

### A package edit is a cross-unit change
EVERY TARGET IN BOTH UNITS COMPILES bp_defines_pkg.sv AND
bp_structs_pkg.sv, as its first two sources. All 47 in the bpu,
all 22 in the ftq. So a package addition made under a task scoped
to one unit reaches the other, and the task's own suite cannot
see it.

This is the mechanism behind the standing rule above: BP-106
reported green, an FTQ task then added FTQ_PTR_BITS and
ftq_redir_cause_e to the packages, and four targets stopped
building because those modules still declared them locally. A
package declaration that shadows a module-local one is a BUILD
BREAK under -Wall, not a tidy-up.

WHEN A TASK ADDS TO EITHER PACKAGE, both units are run afterwards,
whatever the task's own scope was. If they are not run in that
session, the handoff says plainly that the other unit is unbuilt
rather than carrying its last green figure forward.

