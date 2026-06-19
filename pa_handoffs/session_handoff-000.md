<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

DO NOT USE - THIS WAS 1st PROTOTYPE KEPT FOR REFERENCE


Written by Claude.ai

# Session Handoff Notes

This document captures reasoning, decisions, and context from the
initial co-design session that are not fully captured elsewhere in
the repo. A new claude.ai session should read this alongside
CLAUDE.md, README.md, prompts/README.md and the experiment logs
before providing guidance.

---

## Project Overview

This is an AI-assisted co-design experiment for a RISC-V RVA23
8-issue out-of-order processor. The human (jeff) provides
architectural decisions and direction. Claude.ai provides design
guidance and writes experiment prompts. Claude Code implements
the RTL and testbenches. The methodology is documented in
docs/observations/prompt_detail_and_leverage.md.

The project is at:
~/Development/jeffnye-gh/riscv-codesign

---

## Roles

Claude.ai (web session):
- Provides architectural guidance
- Writes experiment session prompts
- Evaluates results and identifies issues
- Plans next experiments
- Makes recommendations but defers to Jeff on decisions

Claude Code (terminal session):
- Reads CLAUDE.md baseline automatically
- Implements RTL per session prompt
- Runs Verilator and iterates on errors
- Writes files directly to the repo

One experiment = one fresh Claude Code session.
Claude.ai sessions are separate and provide continuity of guidance.

---

## Decoder Track Status

All decoder experiments DECODE-001 through DECODE-011 are complete.
See README.md status tables for full details.

Key outcome: The decoder is functionally complete for RVA23 at the
opcode-dispatch level. 1043 tests passing across two testbenches.

### What is complete
- Full RVA23 scalar decode including Zcb
- Full RVA23 vector decode (OPIVV/OPIVX/OPIVI, OPFVV/OPFVF,
  OPMVV/OPMVX, vector memory, segment ops)
- Pre-decode stage (predecode.sv) with vtype hazard detection
- Extension enable/disable mechanism (ext_enable_t)
- Coverage tooling (make coverage, check_rva23_coverage.py)

### What is deferred (documented in README.md and in STATUS.md)
- DECODE-012: Frontend pre-decode restructuring (fetch boundary,
  branch detection placement, RVC expansion placement). Deferred
  until fetch unit is designed -- needs fetch context.
- Instruction fusion: deliberate deferral, documented as debt
- UOP expansion for RVV segment ops: policy TBD at vector
  execution unit design stage. nf field in decode packet provides
  expansion count.

---

## Key Architectural Decisions Made

These decisions are encoded in the RTL but the reasoning is here.

### Illegal instruction handling
Convention confirmed against BOOM and XiangShan:
- Decoder sets ILLEGAL flag in decode packet
- Rename accepts ILLEGAL instruction, allocates ROB entry
- Dispatch does not issue ILLEGAL to execution units
- Commit: when ILLEGAL reaches ROB head, flush pipeline,
  write mepc = PC of illegal instruction, mcause = 2,
  redirect to mtvec
The decoder's job ends at setting the flag.

### vtype dependency model
- Decoder is stateless -- no vtype state stored in decoder
- vsetvl/vsetvli/vsetivli: set is_vsetvl=1, populate vsew/vlmul/
  vta/vma fields from instruction immediate
- All other vector instructions: set needs_vtype=1, leave vtype
  fields unpopulated
- Rename resolves vtype as a producer/consumer dependency
- Intra-bundle vtype hazard: predecode.sv detects and sets
  vtype_hazard flag. Policy (stall/forward/rename insertion)
  is TBD at rename/dispatch stage.
- vsetvl register form: vsew/vlmul/vta/vma left at zero in decode
  packet. Vector unit resolves vtype from rs2 at runtime.

### Dual decode packet interface
- decode_pkt_t[7:0] -- scalar decode packet (always present)
- vec_decode_pkt_t[7:0] -- vector decode packet (when is_vector=1)
- predecode_pkt_t[7:0] -- pre-decode annotations (pass-through)
- is_vector[7:0] -- steering flag for rename/dispatch
- Rename uses is_vector to steer to correct issue queue
- For OP_VECTOR scalar packet: uses_rd/rs1/rs2=1 conservatively.
  Rename must use vec_decode_pkt_t fields, not scalar fields.

### OPMVX scalar GPR source contract
- All OPMVX instructions: pkt.vs1=0, GPR in scalar pkt.rs1
- Dispatch must inspect funct3=OPMVX or v_op_class to route
  GPR operand to correct functional unit port
- Affected instructions: vmv.s.x, vmv.x.s, vslide1up.vx,
  vslide1down.vx, all other OPMVX

### vfmv.f.s disambiguation
- VOP_VFMV_FS is a dedicated enum entry separate from VOP_VFMV
- Dispatch does not need funct3 to distinguish vfmv.f.s from
  vfmv.s.f -- v_op_class alone is sufficient
- This was technical debt from DECODE-006, resolved in DECODE-007

### Extension enable/disable
- misa is read-only in production
- ext_enable_t is a static input driven from misa fields by CSR unit
- Decoder assumes valid combinations -- no dependency enforcement
- Dependency enforcement is software/driver responsibility
- For RVA23 all bits are 1 at reset
- ext_enable_t is for bring-up, debug, and verification use

### Vector memory misidentification (resolved)
- vle*/vse* instructions use opcodes 0x07/0x27 (same as scalar FP)
- Disambiguation: width field [14:12] = 3'b000/101/110/111 = vector
- Scalar FP: width [14:12] = 3'b010/011/100 = no overlap
- Fixed in DECODE-008, T29 (previously documented failure) now passes

### needs_vtype for whole-register ops
- VOP_VLWHOLE/VOP_VSWHOLE: needs_vtype=0 (fixed in DECODE-009)
- These instructions do not consume vtype
- Segment ops retain needs_vtype=1

### vtype_hazard false dependency for whole-register ops
- needs_vtype=0 set correctly but rename should still tolerate
  the dependency being present as a safety margin
- Noted as minor technical debt

---

## Technical Debt Inventory

Items noted but not yet fixed. All documented in prompt results files.

1. Instruction fusion: deferred. To be designed when rename/dispatch
   is in scope.

2. UOP expansion for RVV segment ops: policy TBD at vector execution
   unit design stage.

3. predecode.sv clk/rstn ports: currently unused, present for
   pipeline interface consistency. Will be connected or removed
   during pipeline stage assignment process.

4. ENUM hole at 7'd2 (VALU_FP was removed, left a reserved hole).
   Minor -- acceptable for now.

5. vtype_hazard intra-bundle policy: TBD at rename/dispatch.
   Signal is available, policy not yet defined.

6. Vector memory false FP identification: T29 documents this was
   expected failure in DECODE-004, fixed in DECODE-008.

---

## Tools Status

### check_rva23_coverage.py
- Location: tools/check_rva23_coverage.py
- Submodule: tools/riscv-opcodes (git submodule)
- make coverage: exits non-zero if any MISSING instructions found
- ROUTED does not trigger failure (correct by design)
- --strict flag available for future use (treats ROUTED as MISSING)
- Known limitations documented in README.md tools section

### Spike ISS
- Submodule: tools/spike (git submodule)
- Built at: tools/spike/install/bin/spike-dasm
- Correct input format: DASM(hex) not 0xhex
- Example: echo "DASM(00000013)" | tools/spike/install/bin/spike-dasm
- Vector works: echo "DASM(00000057)" | spike-dasm --isa rv64gcv
- Zba/Zbb/Zbs: return "unknown" -- ISA string issue not yet resolved
- Hypervisor "h" extension: not supported by this spike build
- TOOLS-002 is the next experiment -- needs ISA string investigation

### TOOLS-001 status

- Prompt written and run
- Extended the coverage to include missing opcodes
- 

### TOOLS-002 status
- Prompt written but NOT yet run
- Blocked on: determining correct ISA string for spike-dasm that
  covers RVA23 extensions beyond base RV64GCV
- Key finding: spike-dasm does NOT use 0xhex input, uses DASM(hex)
- Key finding: hypervisor "h" is not a valid spike-dasm ISA extension
- First task in new session: determine what extensions spike-dasm
  actually supports by testing systematically, then rewrite prompt
- setup.sh at project root handles spike build for fresh clones

---

## Methodology Conventions

### Prompt discipline
- One experiment = one fresh Claude Code session
- Do not resume between experiments
- CLAUDE.md is re-read automatically each session
- ASCII only in all RTL comments (in CLAUDE.md)
- 80 column line width (enforced in prompts, sometimes violated)
- funct6 values must come from riscv-opcodes files not training data
- Read before write: Claude reads relevant files before generating RTL

### Prompt content convention
- Good detail: constraining YOUR architectural decisions
- Bad detail: over-specifying implementation (reduces leverage)
- Constraints section: contains YOUR decisions, not implementation steps
- Experiment scope: one variable at a time where possible
- Deliverables: explicit list, numbered, checkable

### Results capture discipline
- Fill in prompts/TEMPLATE.md results section after each session
- Session link field: claude.ai URL or "Claude Code local session"
- Do not write results capture during the session -- after only
- Graduated to CLAUDE.md: when experiment confirms a decision

### What goes in CLAUDE.md vs session prompt
- CLAUDE.md: anything that affects correctness of design decisions
- Session prompt: the hypothesis being tested, experiment-specific
  constraints, approach variations
- When experiment confirms a decision: graduate to CLAUDE.md

### make targets
- make lint: Verilator lint only
- make sim: build and run simulation
- make sim_predecode: run predecode testbench
- make sim_all: run all testbenches + coverage
- make oracle: run spike oracle comparison (TOOLS-002, not yet built)
- make coverage: run check_rva23_coverage.py, exits non-zero on MISSING

---

## Next Steps (in priority order)

1. Resolve spike-dasm ISA string issue for Zba/Zbb/Zbs and other
   RVA23 extensions. Test systematically to find what is supported.

2. Rewrite and run TOOLS-002 with correct spike-dasm usage.

3. DECODE-012: Frontend pre-decode restructuring. Best deferred
   until fetch unit design is started -- needs fetch context.

4. Begin fetch unit experiments (FETCH-001 etc.) when ready to
   move beyond decoder track.

5. Whisper ISS: planned for full pipeline lock-step validation
   when execution pipeline exists. Not yet needed.

---

## Important Context: This Is a Research Project

This project is exploring AI-assisted co-design methodology as much
as it is designing the processor. The prompt framework, results
capture, and experiment discipline are themselves contributions.
Jeff noted this could be worth writing up -- keep this in mind
when making methodology decisions.

The decoder is one of many planned modules:
- clusters: frontend, midcore, backend, memory_system
- frontend units: fetch, branch_predictor, decoder (done)
- each unit has rtl/, tb/, verilator/, tests/, Makefile, README.md

The decoder experiments (DECODE-001 through DECODE-011) represent
only the first unit of the first cluster. There is substantial
work ahead.

=============================================================
Following instructions
=============================================================
**Then start the new session with:**
```
I am continuing the riscv-codesign project. Please start a Claude
Code session in ~/Development/jeffnye-gh/riscv-codesign and read
these files before we discuss anything:

  docs/observations/session_handoff.md  -- read this first
  CLAUDE.md
  README.md
  prompts/README.md
  prompts/tools/TOOLS-002.md

The handoff doc explains the project, methodology, all key
decisions, and where we are stuck on TOOLS-002.

=============================================================
OTHER VERSIONS
=============================================================
I am continuing a RISC-V RVA23 8-issue OOO processor co-design
project using Claude Code. The project repo is at
~/Development/jeffnye-gh/riscv-codesign.

The CLAUDE.md at the project root contains the full baseline.
The prompts/ directory contains all experiment history DECODE-001
through DECODE-011 plus TOOLS-001.

I need help with TOOLS-002 which adds spike-dasm as an oracle
for decoder validation. Spike is built and installed at
tools/spike/install/bin/spike-dasm.

Key facts established so far:
- spike-dasm input format is DASM(hex) not 0xhex
- Basic RV64I works: echo "DASM(00000013)" | spike-dasm
- Vector works with: echo "DASM(00000057)" | spike-dasm --isa rv64gcv
- Zba instructions return "unknown" regardless of ISA string tried
- Hypervisor extension "h" is not supported by this spike build
- The correct ISA string for all supported extensions needs to
  be determined before writing the TOOLS-002 session prompt

First task: determine the correct ISA string for spike-dasm that
covers as many RVA23 extensions as possible, then rewrite the
TOOLS-002 prompt accordingly.

=============================================================
=============================================================

cd ~/Development/jeffnye-gh/riscv-codesign
cat CLAUDE.md
cat README.md
cat docs/observations/prompt_detail_and_leverage.md
cat prompts/README.md
cat prompts/TEMPLATE.md
```

Make sure all of these are fully up to date and committed. They are the institutional memory of this project. A new Claude instance reading these files will understand:

- The machine target and constants
- The experiment methodology
- The directory structure
- The naming conventions
- The prompt/results discipline
- Current scope and status

---

**Then in the new chat, open with:**
```
I am continuing work on the riscv-codesign project. Please read
the following files before we discuss anything:

1. CLAUDE.md -- project baseline and constants
2. README.md -- project status and directory structure  
3. docs/observations/prompt_detail_and_leverage.md -- methodology
4. prompts/README.md -- experiment conventions
5. prompts/tools/TOOLS-002.md -- the current experiment we are
   working on

The project is at ~/Development/jeffnye-gh/riscv-codesign.
I will start a Claude Code session for you to read these files
directly. Please read them before proceeding.
=============================================================
=============================================================

