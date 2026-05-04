# pacino

> *"I'm out of order? You're out of order!"*

Documentation, RTL, and verification for **Pacino** — a co-designed RISC-V RVA23
8-issue out-of-order processor. This project also explores AI-assisted hardware
co-design methodology alongside the processor design itself.

Pacino is the first project under [uarchlabs](https://uarchlabs.github.io), an open
source hardware design organization. The design flow is currently tightly coupled to
RVA23-based microarchitectures. As the uarchlabs portfolio grows, the flow will be
abstracted into a standalone tool.

RTL is in SystemVerilog, simulation with Verilator 5.020.

---

## Quick Start

```bash
# clone with submodules
git clone --recurse-submodules https://github.com/uarchlabs/pacino

# or if already cloned without submodules
cd pacino
git submodule update --init --recursive

# install system prerequisites
bash prereqs.sh

# one-time project setup (builds spike from submodule source)
./setup.sh
```

---

## Project Status

See `planning/PROJECT_CORE.md` and `planning/PROJECT_STATUS.md` for detailed status tables.

---

## Directory Structure

`$RVA_ROOT` is an environment variable pointing to the current top of the tree.

```
$RVA_ROOT/
|-- CLAUDE.md                  project baseline for Claude Code sessions
|-- docs/
|   |-- blogs/                 project discussion in blog form
|   |-- misc/
|   |   |-- ai_pairings        alternatives to c.ai+c.code
|   |   |-- observations.md    prompt detail risks
|   |   |-- pa_session_map.md  named PA sessions linked to task files
|   |-- pa_sessions/           downloaded Claude.ai sessions
|   |-- pm_handoffs/           postmortem session handoffs
|   |-- postmortem             analysis md files, deprecated for blogs
|   |-- README.md
|
|-- pa_handoffs                PA session handoffs
|-- planning                   development planning and methodology files
|   |-- arch                   architecture definitions in md
|   |   |-- <various>
|   |-- CORE.md                central planning, slow moving
|   |-- interfaces             interface contracts in md
|   |   |-- <various>
|   |-- testbenches            testbench rules in md
|       |-- <various>
|
|-- prereqs.sh                 dependencies needed by new repos
|
|-- prompts/                   experiment/task prompts
|   |-- bpu
|   |-- components
|   |-- decode
|   |-- tools
|
|-- README.md                  this file
|-- setup.sh                   one-time setup script (builds spike etc.)
|-- prereqs.sh                 install system prerequisites
|-- handoffs/                  claude.ai session handoff documents
|   |-- PROJECT_CORE.md        project principles
|   |-- PROJECT_STATUS.md      upcoming tasks and status
|   |-- session_handoff-001.md handoff documents, multiple
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
|   |   |-- ptw
|   |
|   |-- prot/                  phy mem protection/attributes
|   |   |-- tb
|   |   |-- pma
|   |   |-- pmp
|   |
|   |-- uncore
|   |   |-- tb                 subsystem tb
|       |-- tilelink
|
|-- templates/
|   |-- SESSION_HANDOFF.md     PA session handoff template
|   |-- TASK_TEMPLATE.md       IA prompt template
|
|-- tools/
|   |-- check_rva23_coverage.py  verify against riscv-opcodes and spike-dasm
|   |-- check_spike_decode.py
|   |-- gen_spike_oracle.py
|   |-- handoff.sh
|   |-- make_context.sh
|   |-- Makefile
|   |-- mk_pkg.sh
|   |-- riscv-opcodes/           git submodule
|   |-- rva23_ext_test.c
|   |-- rva23_insn_ref.c
|   |-- spike/                   git submodule (riscv-isa-sim)
|   |   |-- install/             spike build output (not committed)
|   |-- validate_and_extract.py
|   |-- spike_oracle/            oracle comparison scripts (TOOLS-002)
```

---

## Constants

| Property          | Value                                              |
|-------------------|----------------------------------------------------|
| Architecture      | RISC-V RVA23 profile                               |
| Microarchitecture | 8-issue out-of-order                               |
| RTL language      | SystemVerilog                                      |
| Simulator         | Verilator 5.020                                    |
| Compiler          | Embecosm riscv-embecosm-embedded-ubuntu2204-20250309 |

---

## Tools

| Name                    | Location             | Purpose                                 |
|-------------------------|----------------------|-----------------------------------------|
| check_rva23_coverage.py | tools/               | RVA23 instruction coverage gap analysis |
| riscv-opcodes           | tools/riscv-opcodes/ | Machine-readable RISC-V opcode database |
| spike (riscv-isa-sim)   | tools/spike/         | RISC-V ISA simulator and disassembler   |

### check_rva23_coverage.py

Parses `tools/riscv-opcodes/` extension files and checks coverage against the RTL in
`frontend/decoder/rtl/`. Produces a per-extension report with COVERED, ROUTED, and
MISSING categories.

```bash
cd frontend/decoder
make coverage    # exits non-zero if any MISSING instructions found
make sim_all     # runs all testbenches then coverage
```

Known limitations are documented in the script's `KNOWN_SHARED_ENCODINGS` and
`KNOWN_OPCODES_FILE_GAPS` tables.

### riscv-opcodes

Git submodule at `tools/riscv-opcodes/`. Enumerates standard RISC-V instruction
opcodes and CSRs. Used as ground truth for coverage checking and decoder validation.

### spike

Git submodule at `tools/spike/`. Built locally to `tools/spike/install/` by running
`./setup.sh` from the project root.

spike-dasm input format uses `DASM(hex)` tokens, not raw hex values.

```bash
# disassemble a NOP
echo "DASM(00000013)" | tools/spike/install/bin/spike-dasm

# disassemble a vector instruction
echo "DASM(00000057)" | tools/spike/install/bin/spike-dasm --isa rv64gcv
```

---

## Workflow

Two AI tools are used in parallel:

- **claude.ai** — web interface, provides architectural guidance and writes experiment prompts
- **Claude Code** — terminal interface, implements RTL and runs Verilator

Jeff bridges the two tools — pasting prompts from claude.ai into Claude Code, and
reporting Claude Code results back to claude.ai. Neither tool communicates directly
with the other.

### Terminology

| Term             | Meaning |
|------------------|---------|
| Experiment       | One focused design or verification task with a defined hypothesis |
| Experiment file  | The prompt and results document for one experiment e.g. DECODE-001.md |
| Session prompt   | The text section of an experiment file extracted by Claude Code |
| Baseline         | CLAUDE.md — constants applied to every Claude Code session |
| Handoff document | Notes written at end of a claude.ai session for the next claude.ai session |
| PROJECT_CORE     | Handoff document describing workflow, roles, structures, and files used in the methodology. Not supplied during handoff unless there has been a methodology change. |
| PROJECT_STATUS   | Handoff document supplied during handoff giving a task list (completed and planned), module status, technical debt, and open items. Used during task planning and next-experiment file generation. |

### Step by Step

1. In claude.ai: discuss the next experiment, agree on hypothesis and scope

2. In claude.ai: generate the session prompt following `prompts/REPORT_TEMPLATE.md`
   — reference existing experiment files in `prompts/frontend/decoder/` for examples

3. claude.ai creates a `<NAME>-<SEQID>.md` file from `REPORT_TEMPLATE.md`.
   Copy this file into `./prompts/<path>` — this is the *experiment file*

4. Validate the experiment file format:

   ```bash
   ./tools/validate_and_extract.py <path to experiment file>
   ```

   This checks the input format and writes to `.claude/tmp/current-prompt.md`.
   Fill in metadata (date, ID) in the experiment file.

5. Start a fresh Claude Code session:

   ```bash
   cd ~/pacino
   claude --dangerously-skip-permissions
   ```

   Note: `--dangerously-skip-permissions` can be downgraded to `--auto-accept-edits`
   or removed entirely depending on your preferred interaction/risk tradeoff.

6. Tell Claude Code to read and execute the file:

   ```
   Read .claude/tmp/current-prompt.md and execute it
   ```

7. Let Claude Code run. Approve file writes and shell commands as prompted.
   Report results back to claude.ai when complete.

8. Claude Code fills in the RESULTS CAPTURE section of the experiment file
   with the console output summary.

9. Add the console output to the Results Discussion section.

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

### Key Discipline Rules

- One experiment = one fresh Claude Code session. Never resume between experiments.
- Claude Code reads the prompt from the experiment file — this also verifies file format.
- Fill in RESULTS CAPTURE after the session.
- `CLAUDE.md` holds confirmed decisions. Experiment files hold hypotheses being tested.

---

## claude.ai Handoff Process

claude.ai sessions have a context limit. Over a long project, guidance quality
degrades as the context fills. When this happens, start a new claude.ai session
using the handoff process below.

Handoff documents are stored in `handoffs/` and numbered sequentially:

```
handoffs/session_handoff-001.md
handoffs/session_handoff-002.md
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
git add handoffs/session_handoff-NNN.md
git commit -m "docs: session handoff NNN"
git push
```

### Starting the new session

1. Open a new claude.ai chat

2. Update `handoffs/PROJECT_STATUS.md` and `CLAUDE.md` as needed

3. Run the handoff script against the latest session handoff file:

   ```bash
   ./tools/handoff.sh 017   # use the handoff number e.g. session_handoff-017.md
   ```

4. Paste the contents of the output file `ho` into claude.ai

5. Optionally paste `bp_cluster.md` (changes depending on planning cycle)

6. The new session now has full context and can begin

> **Note:** Paste `handoffs/PROJECT_CORE.md` when discussing methodology changes.
>
> **Note:** Claude Code does not need the handoff document — it reads `CLAUDE.md`
> from disk automatically at the start of each session.
>
> **Note:** When asking claude.ai to generate a prompt, supply `prompts/REPORT_TEMPLATE.md`
> to prevent format drift.

### What the handoff covers

The repo itself covers:
- Project constants and baseline (`CLAUDE.md`)
- Experiment history and results (`prompts/`)
- RTL decisions encoded in the code
- Status tables (`PROJECT_STATUS.md`)
- Methodology notes (`docs/observations/`)

The handoff document adds:
- Reasoning behind architectural decisions
- Why certain approaches were rejected
- Nuanced decisions not captured in code comments
- Current blockers and investigation status
- Anything discovered late in the session

---

## Naming Conventions

| Item             | Convention                  | Example                    |
|------------------|-----------------------------|----------------------------|
| Experiment IDs   | `MODULE-NNN`                | `DECODE-001`, `BP-001`     |
| RTL files        | `snake_case.sv`             | `instr_decoder.sv`         |
| Testbench files  | `tb_` prefix                | `tb_instr_decoder.sv`      |
| Parameters       | `ALL_CAPS`                  | `NUM_ISSUE_SLOTS`          |
| Signals          | `snake_case`                | `instr_valid`              |
| Experiment files | `<ID>.md`                   | `DECODE-001.md`            |
| Handoff files    | `session_handoff-NNN.md`    | `session_handoff-001.md`   |

---

## Further Reading

- `CLAUDE.md` — full project baseline and current scope
- `handoffs/PROJECT_*.md` — implementation status
- `handoffs/session_handoff-*.md` — claude.ai session handoff documents
- `prompts/README.md` — experiment naming and workflow details
- `prompts/REPORT_TEMPLATE.md` — experiment file format
- `docs/observations/` — methodology notes (dated)
- `docs/decision_guide.md` — next steps and design decision guide (dated)

---

*Part of the [uarchlabs](https://uarchlabs.github.io) open source hardware design organization.*

