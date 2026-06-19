<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 001

Written by Claude.ai at end of initial co-design session.
Date: 2026-03-24

This document captures reasoning, decisions, and context from the
initial co-design session that are not fully captured elsewhere in
the repo. The next claude.ai session should read this document and
the claude.code/CLAUDE.md before providing guidance.

---

## How to Use This Document

This is a handoff from one claude.ai session to the next.
claude.ai cannot read files directly -- the human (Jeff) pastes
the contents of this file into a new claude.ai chat to restore
context.

Claude Code is a separate tool running in a terminal. It reads
CLAUDE.md automatically from disk. It does not need this document.

The workflow:
- claude.ai (web): architectural guidance, writes experiment prompts
- Claude Code (terminal): implements RTL, runs Verilator
- Jeff: bridges the two, pastes results from Claude Code into
  claude.ai, pastes prompts from claude.ai into Claude Code

---

## Project Overview

AI-assisted co-design experiment for a RISC-V RVA23 8-issue
out-of-order processor. Jeff provides architectural decisions and
direction. claude.ai provides design guidance and writes experiment
prompts. Claude Code implements the RTL and testbenches.

Repo: https://github.com/jeffnye-gh/riscv-codesign
Local: ~/Development/jeffnye-gh/riscv-codesign

This project is also a research experiment in AI-assisted hardware
co-design methodology. The prompt framework, results capture, and
experiment discipline are themselves contributions worth documenting.
Jeff noted this may be worth writing up formally.

---

## Roles

claude.ai:
- Provides architectural guidance and design recommendations
- Writes experiment session prompts
- Evaluates results reported by Jeff
- Plans next experiments
- Makes recommendations but defers all decisions to Jeff

Claude Code:
- Reads CLAUDE.md baseline automatically at session start
- Implements RTL per session prompt pasted by Jeff
- Runs Verilator and iterates on errors autonomously
- Writes files directly to the repo
- One experiment = one fresh Claude Code session (never resume
  between experiments)

Jeff:
- Makes all architectural decisions
- Pastes session prompts from claude.ai into Claude Code
- Reports Claude Code results back to claude.ai
- Commits results to git
- Bridges claude.ai and Claude Code

---

## Decoder Track Status

All decoder experiments DECODE-001 through DECODE-011 are complete.
See STATUS.md for full details.

Key outcome: The decoder is functionally complete for RVA23 at the
opcode-dispatch level. 1043 tests passing across two testbenches
(tb_predecode.sv and tb_instr_decoder.sv).

### What is complete
- Full RVA23 scalar decode including Zcb (DECODE-001 to DECODE-003)
- Full RVA23 vector decode:
  - OPIVV/OPIVX/OPIVI integer ALU (DECODE-005)
  - OPFVV/OPFVF floating point ALU + Zvfhmin closure (DECODE-006)
  - OPMVV/OPMVX mask/reduce/permute (DECODE-007)
  - Vector memory + segment ops (DECODE-008, DECODE-009)
- Pre-decode stage predecode.sv with vtype hazard detection
  (DECODE-010)
- Extension enable/disable mechanism ext_enable_t (DECODE-011)
- Coverage tooling make coverage + check_rva23_coverage.py
  (TOOLS-001, DECODE-011)

### What is deferred
- DECODE-012: Frontend pre-decode restructuring. Deferred until
  fetch unit is designed -- needs fetch interface context.
- Instruction fusion: deliberate deferral, documented as debt.
- UOP expansion for RVV segment ops: policy TBD at vector
  execution unit design stage. nf field in decode packet provides
  the expansion count when needed.

---

## Key Architectural Decisions

These decisions are encoded in the RTL. The reasoning is here.

### Illegal instruction handling
Confirmed against BOOM and XiangShan conventions:
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
- Affected: vmv.s.x, vmv.x.s, vslide1up.vx, vslide1down.vx,
  and all other OPMVX instructions

### vfmv.f.s disambiguation
- VOP_VFMV_FS is a dedicated enum entry separate from VOP_VFMV
- Dispatch does not need funct3 to distinguish vfmv.f.s from
  vfmv.s.f -- v_op_class alone is sufficient
- Was technical debt from DECODE-006, resolved in DECODE-007

### Extension enable/disable
- misa is read-only in production
- ext_enable_t is a static input driven from misa fields by CSR unit
- Decoder assumes valid combinations -- no dependency enforcement
- Dependency enforcement is software/driver responsibility
- For RVA23 all bits are 1 at reset
- ext_enable_t is for bring-up, debug, and verification use

### Vector memory disambiguation
- vle*/vse* use opcodes 0x07/0x27 (same as scalar FP loads/stores)
- Disambiguation: width field [14:12] values:
    vector: 3'b000, 3'b101, 3'b110, 3'b111
    scalar FP: 3'b010, 3'b011, 3'b100 (no overlap)
- Fixed in DECODE-008

### needs_vtype for whole-register ops
- VOP_VLWHOLE/VOP_VSWHOLE: needs_vtype=0 (fixed in DECODE-009)
- These do not consume vtype
- Segment ops retain needs_vtype=1

---

## Technical Debt Inventory

1. Instruction fusion: deferred to rename/dispatch design stage.

2. UOP expansion for RVV segment ops: policy TBD at vector
   execution unit design stage.

3. predecode.sv clk/rstn ports: unused, present for pipeline
   interface consistency. Will be connected or removed during
   pipeline stage assignment.

4. ENUM hole at 7'd2: VALU_FP was removed, left a reserved hole.
   Minor, acceptable for now.

5. vtype_hazard intra-bundle policy: TBD at rename/dispatch.
   Signal is available in predecode_out, policy not yet defined.

---

## Tools Status

### check_rva23_coverage.py
- Location: tools/check_rva23_coverage.py
- Uses submodule: tools/riscv-opcodes
- make coverage: exits non-zero if any MISSING instructions found
- ROUTED does not trigger failure (correct by design)
- --strict flag available: treats ROUTED as MISSING (off by default)

### Spike ISS (riscv-isa-sim)
- Submodule: tools/spike
- Built at: tools/spike/install/bin/spike-dasm
- setup.sh at project root builds spike for fresh clones
- Correct input format: DASM(hex) token -- NOT 0xhex
  Example: echo "DASM(00000013)" | tools/spike/install/bin/spike-dasm
- Vector disassembly works:
  echo "DASM(00000057)" | spike-dasm --isa rv64gcv
- Zba/Zbb/Zbs: return "unknown" with all ISA strings tried so far
- Hypervisor "h": not a valid spike-dasm ISA extension string
- The correct full RVA23 ISA string for spike-dasm is not yet
  determined -- this is the first task for TOOLS-002

### TOOLS-002
- Prompt written, location: prompts/tools/TOOLS-002.md
- NOT yet run -- blocked on spike ISA string issue
- First task: Jeff has spike expertise and will guide the new
  claude.ai session on determining the correct ISA string
- Once ISA string is confirmed the TOOLS-002 prompt needs to be
  updated with correct spike-dasm usage before running

---

## Methodology Conventions

### Experiment discipline
- One experiment = one fresh Claude Code session
- Never resume between experiments
- CLAUDE.md is re-read automatically by Claude Code each session
- ASCII only in all RTL comments
- 80 column line width enforced in prompts
- funct6 values must come from riscv-opcodes files not training data
- Read before write: Claude Code reads relevant RTL files before
  generating new RTL

### Prompt content
- Good detail: constraining Jeff's architectural decisions
- Bad detail: over-specifying implementation (reduces LLM leverage)
- See docs/observations/prompt_detail_and_leverage.md for the
  full discussion of this principle

### Results capture
- Fill in RESULTS CAPTURE section of experiment file after session
- Do not write results during the session -- after only
- Session link: claude.ai URL or "Claude Code local session"
- Graduated to CLAUDE.md: note when experiment confirms a decision

### CLAUDE.md vs session prompt
- CLAUDE.md: anything affecting correctness of design decisions
- Session prompt: hypothesis being tested, experiment-specific
  constraints, approach variations
- When experiment confirms a decision: graduate to CLAUDE.md

### make targets (frontend/decoder/)
- make lint: Verilator lint only
- make sim: build and run tb_instr_decoder
- make sim_predecode: run tb_predecode
- make sim_all: all testbenches + coverage
- make coverage: run check_rva23_coverage.py, exits non-zero on MISSING
- make oracle: spike oracle (TOOLS-002, not yet built)

---

## Next Steps (priority order)

1. Determine correct spike-dasm ISA string for RVA23 extensions
   beyond base RV64GCV. Jeff has spike expertise -- he leads this.

2. Update and run TOOLS-002 with correct spike-dasm usage and
   input format.

3. DECODE-012: Frontend pre-decode restructuring. Defer until
   fetch unit design starts.

4. Begin fetch unit (FETCH-001 etc.) when ready to move beyond
   decoder track.

5. Whisper ISS: plan for full pipeline lock-step validation when
   execution pipeline exists. Not needed yet.

---

## Handoff Process Notes

This is session_handoff-001.md -- the first in a numbered series.
Future handoffs are stored in handoffs/ and numbered sequentially:
  handoffs/session_handoff-001.md  (this file)
  handoffs/session_handoff-002.md  (next session end)
  etc.

To start a new claude.ai session:
1. Open a new claude.ai chat
2. Paste the contents of this file into the chat
3. Then paste the contents of CLAUDE.md
4. The new session has full context and can begin immediately

Claude Code does not need this file -- it reads CLAUDE.md from
disk automatically.

