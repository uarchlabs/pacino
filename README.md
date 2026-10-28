<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# pacino

> *"I'm out of order? You're out of order!"*

Documentation, RTL, and verification for Pacino — an open source 8-issue
out-of-order RISC-V RVA23S64 processor. The full co-design record — prompts,
iteration history, and architectural rationale — is committed alongside the
RTL.

Pacino is the first project under [uarchlabs](https://uarchlabs.com), an open
source hardware design organization. The design flow is currently tightly
coupled to RVA23-based microarchitectures. As the uarchlabs portfolio grows,
the flow will be abstracted into a standalone tool.

RTL is in SystemVerilog, simulation with Verilator 5.048

---
# TOC

1. [Quick start](#quick-start)
1. [Project Status](#project-status)
1. [Directory Structure](#directory-structure)
1. [Constants](#constants)
1. [Tools](#tools)
1. [Workflow](#workflow)
1. [Periodically](#periodically)
1. [Naming Conventions](#naming-conventions)
1. [Further Reading](#further-reading)
1. [License](#license)

---
# Quick start

- Clone pacino
- Install the Ubuntu prereqs
- Set the Pacino environment
- Build the tools
- Run the regression
- Run code coverage
- Push

Short path: the prerequisites step can be skipped. `build_tools.sh`
finds what is missing and prints the command to install it:

```bash
git clone --recurse-submodules https://github.com/uarchlabs/pacino
cd pacino
. tools/setup.sh
tools/build_tools.sh    # if an apt package is missing it stops in
                        # seconds and prints one apt command; run it,
                        # then run build_tools.sh again
./tools/regress.sh
```

The only question, about the Embecosm toolchain, comes in the first
seconds; the builds then run without input. Rust, for Surfer, is
installed by the script into `tools/rust`. The Python packages in `tools/requirements.txt`
are not checked by any script; they are needed only for the docs site,
`tools/gen_doc_placeholders.py` and ticfinder.

## Clone pacino
Clone with submodules
```bash
git clone --recurse-submodules https://github.com/uarchlabs/pacino
```
Or init submodules after clone
```bash
git clone https://github.com/uarchlabs/pacino
cd pacino
git submodule update --init --recursive
```

## Install system prerequisites

The Debian/Ubuntu packages are listed in `tools/apt-requirements.txt`,
grouped by the tool that needs them. No project script installs
packages; install them all with:

```bash
cd pacino
sudo apt install $(sed 's/#.*//' tools/apt-requirements.txt)
```

Rust is not a prerequisite. Surfer, the waveform viewer, is built with
Rust 1.95.0, which `tools/build_tools.sh` installs into `tools/rust`
with rustup. It edits no shell profile, and any Rust you have in
`~/.cargo` is neither used nor changed.

The Python packages for the scripts, the docs site and ticfinder are
listed in `tools/requirements.txt` (on Ubuntu 24.04 and later, install
them into a virtual environment instead of with `--user`):

```bash
python3 -m pip install --user -r tools/requirements.txt
```

## Set the environment

Run this from the repo root, in every new terminal:

```bash
cd pacino
. tools/setup.sh
```

It sets:

- `RVA_ROOT`, the repo root, taken from the current directory
- `CLAUDE_CODE_MAX_OUTPUT_TOKENS`
- `core.hooksPath tools/hooks`, git config for this clone: installs the
  pre-push hook that runs the regression (see Push)
- `core.sshCommand` with SSH keepalives, git config for this clone: GitHub
  does not drop the push connection while the hook runs the regression

A clone does not inherit git config, so these are set here rather than
committed. Setting them again is harmless.

## Build the tools

```bash
cd $RVA_ROOT
tools/build_tools.sh
```

This builds the project tools into `$RVA_ROOT/tools/bin`, the paths
`rtl/Vars.mk` expects (`VERILATOR`, `VERILATOR_COVERAGE`, `SPIKE`,
`SURFER`, `GENHTML`, `FST2VCD`). No Makefile or script finds a tool on
`PATH`:

| Tool      | Version    | Source                                         |
|-----------|------------|------------------------------------------------|
| Verilator | 5.048      | `tools/verilator` submodule                    |
| Spike     | 1.1.1-dev  | `tools/spike` submodule (commit 20feb9c2)      |
| Surfer    | v0.7.0     | gitlab.com/surfer-project/surfer, cloned into `tools/surfer` |
| lcov      | v1.15      | github.com/linux-test-project/lcov, cloned into `tools/lcov`; `genhtml` for the coverage reports |
| fst2vcd   | GTKWave v3.3.104 | github.com/gtkwave/gtkwave, cloned into `tools/gtkwave`; only `fst2vcd` is built |

It also checks the Embecosm RISC-V toolchain
(`riscv-embecosm-embedded-ubuntu2204-20250309`: GCC 15.0.1, Clang 21), a
prebuilt release, in `EMBECOSM_BIN` (`rtl/Vars.mk`). When it is not found
the script asks, before any build, for one of:

1. the bin directory of an existing install, e.g.
   `/usr/local/riscv-embecosm-embedded-ubuntu2204-20250309/bin`
2. a download (2.3 GB, 7.1 GB unpacked) and install into `tools/`, no
   sudo; it runs with the builds, after the questions. An interrupted
   download resumes by itself, up to 5 attempts; after that the next run
   resumes it
3. skip

> **Note: the `riscv32-unknown-elf-*` tools are RV64 tools too.** The
> Embecosm release names its GCC tools `riscv32-unknown-elf-gcc`,
> `riscv32-unknown-elf-objdump` and so on; there are no `riscv64-` names.
> The same GCC has RV64 multilibs and builds RV64 code when given
> `-march=rv64...` and `-mabi=lp64d`, as `tools/Makefile` does. The
> project uses the `riscv32-` names; do not add `riscv64-` links.

The answer is saved in `tools/local.mk` (not tracked), which
`rtl/Vars.mk` reads, so it is asked once. An `EMBECOSM_BIN` in the
environment overrides it. Without a terminal the script prints the
equivalent commands instead of asking.

The script runs in two phases, so that it can be started and left:

1. Check, a few seconds: every tool and its apt packages are checked,
   and the Embecosm question is asked. If any apt package is missing,
   the script stops here and builds nothing; the summary ends with one
   command that installs all of them. Run it, then run
   `tools/build_tools.sh` again; the Embecosm answer is kept.
2. Build, unattended: each tool that is missing or at the wrong version
   is built, and the Embecosm download, if chosen, is installed. A
   missing submodule is initialized. Each tool is attempted even if an
   earlier one fails.

A tool already installed at the right version is not rebuilt. The
summary lists each tool as OK, MISSING, NOT BUILT or FAIL, and the exit
status is non-zero unless all are OK. Each run is logged to
`logs/pacino_setup_YYYY-MM-DD_N.log`; the last line printed names it.
Send that file when reporting a setup problem.

```bash
tools/build_tools.sh --check         # phase 1 only, asks nothing
tools/build_tools.sh verilator spike # named tools only, e.g. no Surfer
JOBS=4 tools/build_tools.sh          # make parallelism; default nproc,
                                     # capped at one job per 2 GB
```

Each tool also has its own script, `tools/check_<tool>.sh [--build]`,
which `build_tools.sh` runs.

Spike installs `spike`, `spike-dasm`, `spike-log-parser`, `elf2hex`,
`xspike` and `termios-xspike`. `tools/check_spike_decode.py` also
expects them in `tools/bin`. Run the spike-dasm decode check (needs the
Embecosm toolchain in `EMBECOSM_BIN`, see above):

```bash
make -C $RVA_ROOT/tools            # builds rva23_insn_ref.disasm
make -C $RVA_ROOT/tools spike_all  # spike_oracle.csv, then check_spike_decode.py
```

## Run the regression

From the repo root:

```bash
./tools/regress.sh
```

It finds every Makefile under `rtl/` and runs every test target in each,
one make call per target, coverage targets included (about 15 minutes).
It prints a summary block (git sha, one line per target, totals) and
exits non-zero on any failure not listed in `tools/known_failures.txt`.
`make -C rtl all` and `make -C rtl cov` are retired; they print this
command and exit 1.

A passing run on a clean tree records the commit in `.git/regress_pass`
(see Push). The run prints `pass NOT recorded` when a tracked file
differs from HEAD, `rtl/` has untracked files, or HEAD moved during the
run.

## Run code coverage

The regression runs the BPU coverage targets. To run them alone:

```bash
make -C $RVA_ROOT/rtl/core/frontend/bpu cov_bpu
```

To view BPU coverage reports

```bash
firefox $RVA_ROOT/rtl/core/frontend/bpu/coverage/bpu/html/index.html
```

## Push

`git push` runs the regression through the pre-push hook
(`tools/hooks/pre-push`, installed by `tools/setup.sh`):

- a commit that already has a recorded pass is pushed at once;
- otherwise the hook runs `./tools/regress.sh` on HEAD, and pushes on
  PASS;
- the push is refused when the regression fails, when no pass could be
  recorded (see above), or when the commit pushed is not HEAD.

To skip the wait at push time, run `./tools/regress.sh` first; a clean
pass is recorded and the push then does not run it again.

# Project Status

Summary:

| Cluster       | Units                                         | Status   | Discussion |
|---------------|-----------------------------------------------|----------|------------|
| Front end     | BPU, FTQ, IFU, L1I, ITLB, PTW, ibuf, decode   | Complete | Available  |
| Midcore       | rename, dispatch, ROB                         | Planned  | n/a        |
| Backend       | execute, LSU                                  | Planned  | n/a        |
| Memory system | L2, L3, DTLB, L2 TLB                          | Planned  | n/a        |

See [PROJECT_STATUS.md](planning/PROJECT_STATUS.md) for detailed status tables.

Current discussions in article form are found in [BLOGS](https://uarchlabs.github.io/blog/)

Interactive status is this [diagram](https://uarchlabs.github.io/pacino/overview/).

See also uarchlabs [FAQ](https://uarchlabs.com/faq.html)

---
# Directory Structure

`$RVA_ROOT` is an environment variable pointing to the current top of the tree.

```
$RVA_ROOT/
|-- .claude
|   |-- commands
|   |   |-- run.md             execute prompt from task file
|   |-- statusline.sh          Custom status line, captures context usage, etc
|
|-- blog_handoffs/             blog session handoffs
|
|-- blogs/                     project discussion in blog form
|
|-- CLAUDE.md                  project baseline for Claude Code sessions
|
|-- docs/                      mkdocs source
|
|-- examples/
|   |-- fe_demo                front-end demo
|
|-- ia_context/                IA (Claude Code) background, handoffs, exports
|
|-- LICENSES/                  license files
|
|-- misc/                      notes, sometimes out of date
|
|-- NOTICE                     attribution notice
|
|-- overrides/                 mkdocs theme override
|
|-- pa_handoffs/               PA (c.ai) session handoffs
|
|-- planning                   development planning and methodology files
|   |-- ANTIPATTERNS.md
|   |-- PROJECT_CORE.md        project principles
|   |-- PROJECT_STATUS.md      upcoming tasks and status
|   |-- TAGE_DECOMP_LOG.md
|   |
|   |-- arch                   architecture definitions in md
|   |   |-- <various>
|   |-- interfaces             interface contracts in md
|   |   |-- <various>
|   |-- observ                 tracing rules in md
|   |   |-- <various>
|   |-- showcase               guidance for demo generation
|   |   |-- <various>
|   |-- testbenches            testbench rules in md
|   |   |-- <various>
|   |-- verification           verification rules in md
|       |-- <various>
|
|-- pm_handoffs/               postmortem session handoffs
|
|-- postmortem/                analysis md files, deprecated, see blogs
|
|-- prompts/                   experiment/task prompts
|
|-- README.md                  ...
|
|-- reports/                   temporary generated reports (not committed)
|
|-- rtl
|   |-- core
|   |   |-- csr/
|   |   |   |-- tb             csr unit tb
|   |   |
|   |   |-- dispatch/
|   |   |   |-- tb             disp unit tb
|   |   |   |-- rename         (rat armt freel)
|   |   |   |-- prf            (i/f/v/mm)
|   |   |   |-- rob
|   |   |   |-- rs             (i/f/v/ldst/mm)
|   |   |
|   |   |-- except/
|   |   |   |-- tb             except unit tb
|   |   |
|   |   |-- execute/
|   |   |   |-- tb             exe unit tb
|   |   |   |-- int
|   |   |   |-- float
|   |   |   |-- vector
|   |   |   |-- matrix         (tile reg file)
|   |   |   |-- atomics
|   |   |
|   |   |-- frontend/
|   |   |   |-- tb             fe unit tb
|   |   |   |-- icache
|   |   |   |   |-- rtl
|   |   |   |   |-- tb
|   |   |   |-- ftq
|   |   |   |-- ifu
|   |   |   |-- ibuf
|   |   |   |-- decode
|   |   |   |-- bpu
|   |   |
|   |   |-- lsu/
|   |   |   |-- tb             lsu unit tb
|   |   |   |-- agu
|   |   |   |-- lq             (vlq, rar lq, raw lq, raw)
|   |   |   |-- sq
|   |   |   |-- sb
|   |   |   |-- fwd
|   |   |   |-- excbuf         (except buffer)
|   |   |   |-- uncbuf         (uncached buffer)
|   |   |   |-- l1d            (+ dltb mshr write back queue)
|   |   |   |-- mmlsu          (matrix ld/st)
|   |   |   |-- vlsu           (rvv ld/st, vsplit/merge/seg/misalign/vfofbuf)
|   |   |
|   |   |-- pmu/
|   |   |   |-- tb             pmu unit tb
|   |   |
|   |   |-- trace/
|   |       |-- tb             trace unit tb
|   |
|   |-- lib/
|   |   |-- tb                 components tb
|   |   |-- <various>
|   |
|   |-- memory/
|   |   |-- tb                 memory subsystem tb
|   |   |-- l2
|   |   |-- l3
|   |   |-- prefetch
|   |
|   |-- mmu/
|   |   |-- tb                 mmu subsystem tb
|   |   |-- itlb
|   |   |-- dtlb
|   |   |-- l2tlb
|   |   |-- pmp                PMP and PMA checker
|   |   |-- ptw
|   |
|   |-- prot/                  phy mem protection/attributes
|       |-- tb
|
|-- templates/
|   |-- BLOG_HANDOFF.md        blog generation handoff template
|   |-- COPYRIGHT.md           copyright headers/boiler plate
|   |-- SESSION_HANDOFF.md     PA session handoff template
|   |-- TASK_TEMPLATE.md       IA prompt template
|
|-- tools/                     this changes frequently
|   |-- bin/                   installed verilator, spike, elf utils etc
|   |-- <submodules>           useful submodules
|   |-- cachegen               uarchlabs cache generation tool
|   |-- ticfinder              uarchlabs linguistic-based (spacy) text analysis
|   |-- <various>              includes scripts, 3rd party submodules, etc.
|
|-- waivers/                   ticfinder waivers for blogs

```

---

# Constants

| Property          | Value                                              |
|-------------------|----------------------------------------------------|
| Architecture      | RISC-V RVA23S64 profile                            |
| Microarchitecture | 8-issue out-of-order                               |
| RTL language      | SystemVerilog                                      |
| Simulator         | Verilator 5.048 (tools/bin/verilator)              |
| Compiler          | Embecosm riscv-embecosm-embedded-ubuntu2204-20250309 |

---

# Tools

Descriptions have moved to tools/README.md

---

# Workflow

Two AI tools are used in parallel:

- **claude.ai** — web interface, provides architectural guidance and writes experiment prompts
- **Claude Code** — terminal interface, implements RTL and runs Verilator

A domain expert directs both agents - the PA for architectural planning, the IA for implementation — with enforced context isolation between sessions.

## Terminology

| Term             | Meaning |
|------------------|---------|
| Experiment       | One focused design or verification task with a defined hypothesis |
| Experiment file  | The prompt and results document for one experiment e.g. DECODE-001.md |
| Session prompt   | The text section of an experiment file extracted by Claude Code |
| Baseline         | CLAUDE.md — constants applied to every Claude Code session |
| Handoff document | Notes written at end of a claude.ai session for the next claude.ai session |
| PROJECT_CORE     | Handoff document describing workflow, roles, structures, and files used in the methodology. Not supplied during handoff unless there has been a methodology change. |
| PROJECT_STATUS   | Handoff document supplied during handoff giving a task list (completed and planned), module status, technical debt, and open items. Used during task planning and next-experiment file generation. |

## Step by Step

1. In claude.ai: discuss the next experiment, agree on hypothesis and scope

2. In claude.ai: generate the session prompt following `templates/TASK_TEMPLATE.md`
   — reference existing experiment files in `prompts/` for examples

3. claude.ai creates a `<NAME>-<SEQID>.md` file from `TASK_TEMPLATE.md`.
   Copy this file into `./prompts/<path>` — this is the *experiment file*

4. Validate the experiment file format:

   ```bash
   ./tools/validate_and_extract.py <path to experiment file>
   ```

   This checks the input format and writes to `.claude/tmp/current-prompt.md`.
   Fill in metadata (date, ID) in the experiment file.

5. Start a fresh Claude Code session:

   ```bash
   cd $RVA_ROOT
   claude
   ```

   Assumes `RVA_ROOT` has been set to the top of the pacino repo. 

   Note: protections can be relaxed using `--dangerously-skip-permissions`. 
   This choice depends on your preferred interaction/risk tradeoff.

   **It has been shown that simply telling Claude not to do something is not sufficient to constrain its behavior.**

   **Security note:** Claude Code with relaxed permissions has broad filesystem
   and shell access. Regardless of permissions, consider running Claude Code in a
   restricted environment — a dedicated user account with limited sudo, a
   container, or a VM — particularly when using `--auto-accept-edits` or
   `--dangerously-skip-permissions`.


6. Tell Claude Code to read and execute the file:

   ```
   /run <task id>
   ```

   `/run` is a custom slash command defined in `.claude/commands/`. For
   the specified task id, the command locates the task file, validates the 
   format, extracts the prompt section, and executes the instructions 
   in the prompt.

   If task id is BP-001, the run command looks in ./prompts for a task file
   called BP-001.md.

7. Let Claude Code run. Approve file writes and shell commands as prompted.
   Report results back to claude.ai when complete.

8. Claude Code fills in the RESULTS CAPTURE section of the experiment file
   with the console output summary.

9. Add the console output to the Results Discussion section.

   1. Tell IA '/context'
   2. Tell IA 'how much context was used'
   3. Tell IA 'write context usage to new file context-report.md'
      copy the content of this file to Context Report section of task file.

10. Discuss results with claude.ai as needed. Record decisions in Results Discussion.

11. Ask claude.ai to suggest updates to `PROJECT_STATUS` and any planning files
    (e.g. `planning/arch/bp_cluster.md`).

12. Update `CLAUDE.md` Current Scope if moving to a new module. If the experiment
    confirmed a design decision, graduate it to `CLAUDE.md` and note this in the
    experiment file's "Graduated to CLAUDE.md" field.

13. Commit results:

    ```bash
    git add .
    git commit -m "<ID>: <short description>"
    git push
    ```

## Key Discipline Rules

- One experiment = one fresh Claude Code session. Never resume between experiments.
- Claude Code reads the prompt from the experiment file — this also verifies file format.
- Fill in RESULTS CAPTURE after the session.
- `CLAUDE.md` holds confirmed decisions. Experiment files hold hypotheses being tested.

---

## claude.ai Handoff Process

claude.ai sessions have a context limit. Over a long project, guidance quality
degrades as the context fills. When this happens, start a new claude.ai session
using the handoff process below.

Handoff documents are stored in `pa_handoffs/` and numbered sequentially:

```
pa_handoffs/session_handoff-001.md
pa_handoffs/session_handoff-002.md
```

### Signs that a handoff is needed

- Repeated factual errors on things established earlier
- Syntax or path errors in generated commands
- Responses that contradict earlier decisions
- Noticeably slower or less precise answers

### Before closing the old session

Ask the current claude.ai session to generate a handoff document. It will produce
a `session_handoff-NNN.md` capturing:

- Key architectural decisions and their reasoning
- Technical debt inventory
- Tools status and known issues
- Next steps in priority order
- Anything not captured elsewhere in the repo

Commit the handoff document:

```bash
git add pa_handoffs/session_handoff-NNN.md
git commit -m "docs: session handoff NNN"
git push
```

### Starting the new session

1. Open a new claude.ai chat

2. Update `planning/PROJECT_STATUS.md` and `CLAUDE.md` as needed

3. Run the handoff script against the latest session handoff file:

   ```bash
   ./tools/handoff.sh 017   # use the handoff number e.g. session_handoff-017.md
   ```

4. Paste the contents of the output file `ho` into claude.ai

5. Optionally paste the current module planning document, e.g. bp_cluster.md.

6. The new session now has full context and can begin

> **Note:** Paste `planning/PROJECT_CORE.md` when discussing methodology changes.
>
> **Note:** Claude Code does not need the handoff document — it reads `CLAUDE.md`
> from disk automatically at the start of each session.
>
> **Note:** When asking claude.ai to generate a prompt, supply `templates/TASK_TEMPLATE.md`
> to prevent format drift.

### What the handoff covers

The repo itself covers:
- Project constants and baseline (`CLAUDE.md`)
- Experiment history and results (`prompts/`)
- RTL decisions encoded in the code
- Status tables (`planning/PROJECT_STATUS.md`)
- Methodology notes (`misc/observations.md`)

The handoff document adds:
- Reasoning behind architectural decisions
- Why certain approaches were rejected
- Nuanced decisions not captured in code comments
- Current blockers and investigation status
- Anything discovered late in the session

---

# Periodically 

## Publish sessions

```
./tools/gen_sessions.py

correct any issues

commit docs/sessions.json
```

## Update news

```
edit docs/index.md RECENT section
```

---

# Naming Conventions

| Item             | Convention               | Example                    |
|:-----------------|:-------------------------|:---------------------------|
| Task File IDs    | `MODULE-NNN`             | `DECODE-001`, `BP-001`     |
| RTL files        | `snake_case.sv`          | `instr_decoder.sv`         |
| Testbench files  | `tb_` prefix             | `tb_instr_decoder.sv`      |
| Parameters       | `ALL_CAPS`               | `NUM_ISSUE_SLOTS`          |
| Signals          | `snake_case`             | `instr_valid`              |
| Experiment files | `<ID>.md`                | `DECODE-001.md`            |
| Handoff files    | `session_handoff-NNN.md` | `session_handoff-001.md`   |

---

# Further Reading

- [FAQ](https://uarchlabs.com/faq.html) - pacino focused uarchlabs FAQ
- `CLAUDE.md` - full project baseline and current scope
- `planning/PROJECT_CORE.md` - workflow, roles, structures and files
- `planning/PROJECT_STATUS.md` - implementation status
- `pa_handoffs/session_handoff-*.md` - claude.ai session handoff documents
- `templates/TASK_TEMPLATE.md` - experiment file format
- `misc/observations.md` - methodology notes

# Viewing a development version of the html

A reminder for me

```
mkdocs serve
http://127.0.0.1:8000
```

## License

Copyright (c) 2026 Jeff Nye, uarchlabs.com

Pacino is dual licensed:

- Documentation, blogs and articles, including the contents of `docs/`,
  `blogs/` and `examples/*/docs/`, are licensed under the Creative Commons
  Attribution 4.0 International License (CC BY 4.0). See
  [LICENSE-CC-BY-4.0](LICENSES/CC-BY-4.0.txt).
- All other material, including the RTL, tools, planning documents, task
  files, handoffs and READMEs, is licensed under the Apache License,
  Version 2.0. See [LICENSE](LICENSES/Apache-2.0.txt).

See [NOTICE](NOTICE) for attribution requirements.

---

*Part of the [uarchlabs](https://uarchlabs.com) open source hardware design organization.*



