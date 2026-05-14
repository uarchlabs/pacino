# BLOG_decoder_3_memory_to_closure.md

```
 FILE:    BLOG_decoder_3_memory_to_closure.md
 STATUS:  unpublished
 UPDATED: 2026.05.14
 CONTACT: uarchlabs@gmail.com
```

# The RVA23 Decoder Track: Memory Disambiguation, Pre-decode Infrastructure, and What Comes Next

The previous post described the systematic vector ALU disambiguation work
that took the decoder from a scalar foundation to 453 passing tests and
168 fully decoded v_op_class entries. This post covers the remaining four
experiments: the opcode overlap problem in vector memory, a new pre-decode
block, the extension enable mechanism, and what running a large decoder
project with an AI co-design methodology looks like when context limits
become a real operational constraint.

## The Opcode Overlap Problem (DECODE-008)

The first post mentioned this in passing. It deserves a more detailed
treatment because it is the kind of problem that does not appear in
extension documentation but absolutely appears in implementation.

Vector load instructions use opcode 0x07. Scalar FP load instructions
also use opcode 0x07. The disambiguation rule is well-defined in the spec,
but it means the decoder cannot route these instructions by opcode alone.
For any instruction with opcode 0x07 or 0x27, it must first inspect the
width field to determine whether this is a scalar FP operation or a vector
memory operation.

The width field split is clean. Values 3'b000, 3'b101, 3'b110, and 3'b111
are vector EEW encodings (8, 16, 32, and 64-bit element widths). Values
3'b010, 3'b011, and 3'b100 are scalar FP precisions (FLW, FLD, FLQ).
Width value 3'b001 is unused in both spaces. There is no overlap —
confirming this from rv_v was the first thing Claude Code did before
writing any disambiguation logic.

![Opcode 0x07 and 0x27 width-field disambiguation](diagrams/opcode_width_disambiguation.svg)

The implementation used an outer if guard within the OP_LOAD_FP and
OP_STORE_FP case branches: check the width field first; if it matches a
vector EEW, call decode_vec_mem_one(); otherwise fall through to the
existing scalar FP path unchanged. The scalar FP path was confirmed to be
byte-for-byte identical before and after — FLD and FSD regression tests
passed explicitly. This surgical approach kept risk bounded: the validated
scalar FP decoder was not touched.

DECODE-008 also established the addressing mode interface contracts for
the LSU. Five distinct addressing modes with different operand semantics:

- **Unit-stride**: rs1 as base address, element width from EEW field
- **Strided**: rs1 as base, rs2 as signed byte stride — not a data value
- **Indexed**: rs1 as base GPR, vs2 as index vector per element
- **Mask load/store**: always unmasked, EEW=8, no tail/mask policy
- **Fault-only-first**: LSU may shorten vl on mid-vector fault and must
  write back updated vl to the vtype CSR

Each of these requires different LSU behavior. Documenting them as
decode-stage contracts means the LSU design has a concrete specification
rather than needing to re-derive the memory access model from the vector
spec independently.

One technical debt was introduced: needs_vtype=1 was incorrectly set for
whole-register loads and stores. These operations transfer a fixed number
of register-sized chunks regardless of vtype — they do not consume the
current element width or mask policy. Setting needs_vtype=1 creates a
false rename dependency. Noted explicitly and scheduled for DECODE-009.

Claude also flagged, without a prompt requirement, that indexed ordered
memory operations (mop=2'b11) impose a memory access ordering constraint
on the OOO LSU. Proactive identification of downstream implications not
in the experiment scope was a consistent behavior across the decoder track.

Result: 525 tests, 0 failures. The T_VLE32_MIS documented expected-failure
test from DECODE-004 converted to an expected pass.

## When the Right Result Is "Nothing to Change" (DECODE-009)

DECODE-008 placed eight segment instruction stubs in the enum and noted
that nf field routing was deferred. DECODE-009 was scoped to complete
that routing and close the needs_vtype debt.

When Claude Code ran the experiment, the segment routing from DECODE-008
was already functionally correct. DECODE-009 updated a comment to document
the nf encoding — nf is stored as nfields-1, so nf=0 means a non-segment
operation and nf=1 means two fields — applied the needs_vtype=0 fix for
VOP_VLWHOLE and VOP_VSWHOLE, and verified all four vmv*r.v whole-register
move variants return VOP_VMVNR correctly.

No new RTL. No new enum entries. The experiment completed in 5 minutes
and 26 seconds.

This outcome is worth stating directly: finding nothing to fix is a valid
and valuable result. It means the stub design in DECODE-008 was correct
and the scope split between the two experiments was well-calibrated. The
temptation in any experiment-driven process is to feel that a short session
means something was missed. DECODE-009 did not miss anything — it verified
that prior work was complete and closed scheduled debt on time.

Result: 543 tests, 0 failures. No new enum entries.

## A New Pre-decode Block (DECODE-010)

Up to this point every experiment modified existing files. DECODE-010
introduced a new module: predecode.sv.

The pre-decode block is a purely combinational block — not a registered
pipeline stage, though it is designed so that a register slice can be
inserted at any point without changing the surrounding interfaces. Clock
and reset ports are present but unused; they are there so that inserting
pipeline depth later requires no interface changes to predecode.sv or its
connected modules.

The block addresses the vtype dependency problem described in the first
post. When a bundle contains a vsetvl in slot 3 followed by a vadd.vv
in slot 4, the vadd.vv depends on the vtype that vsetvl produces. The
main decoder, being stateless, cannot resolve this. A pre-decode block
that scans the bundle before the main decoder runs can identify the hazard
and annotate it.

predecode.sv produces a predecode_pkt_t for each slot containing:

- **is_vsetvl**: this slot is a vsetvl/vsetvli/vsetivli
- **needs_vtype**: this slot consumes the current vtype
- **vtype_hazard**: a prior valid slot in this bundle has is_vsetvl=1
  and this slot has needs_vtype=1 — intra-bundle dependency detected
- **may_be_branch**: conservative hint that this slot may be a control
  flow instruction (JAL, JALR, or BRANCH opcode only)

The vtype_hazard signal is available to rename via a pass-through output
from instr_decoder. The actual scheduling policy — stall, rename
insertion, forwarding — remains TBD at the rename stage. The experiment
created the signal without encoding the policy. This is the correct
separation of concerns: the pre-decode block detects the structural hazard;
rename decides what to do about it.

The `may_be_branch` hint deserves a note. It is conservative by design —
set for JAL, JALR, and BRANCH opcodes regardless of whether the encoding
is valid. Illegal JALR encodings and reserved opcodes that share those
opcode values will produce false positives. No false negatives exist for
standard control flow instructions. This signal is a placeholder; a full
branch detection pre-decode stage with the resolution required by the BPU
is planned as part of the fetch unit design. That work depends on the
fetch unit interface being defined first.

The vtype_hazard computation requires a prefix-OR across slots: for slot
i, the hazard is set if needs_vtype[i] is true and any earlier valid slot
has is_vsetvl set. The implementation used unrolled continuous assigns —
no loops, fully parallel across all 8 slots.

An unexpected technical finding during DECODE-010: Claude Code
independently identified a Verilator 5.020 behavioral quirk where
variable-indexed array writes inside tasks do not trigger re-evaluation
of dependent assign statements. The testbench was updated to use explicit
case statements with compile-time-constant indices as a workaround. This
was identified from Verilator behavior during testing, not from the
experiment prompt.

This session also hit the API usage limit mid-session, requiring a 2.5-hour
pause before resuming with the experiment prompt re-pasted into a fresh
session. No work was lost. The context isolation pattern — fresh session,
complete prompt, no assumptions about prior session state — proved robust
under exactly the kind of operational interruption it was designed to handle.

Result: 348 predecode tests + 543 decoder tests = 891 total passing.

## Extension Enable and Coverage Closure (DECODE-011)

The final decoder experiment added the ext_enable_t mechanism and
formalized coverage as a gated build target.

As noted in the first post, RVA23 mandates all extensions — a conformant
processor does not need per-extension enable logic. The ext_enable_t struct
was added as a validation and bring-up tool: being able to disable
individual extensions at the decoder level and observe ILLEGAL flags
propagating through the pipeline is useful during integration testing
and early silicon debug. It is not a compliance requirement.

The struct has 18 bits, one per RVA23 mandatory extension, driven from
misa fields by the CSR unit. The decoder does not enforce extension
dependencies — that D requires F, or Zcb requires C, is a software and
system configuration responsibility. The decoder receives the current
enable state and acts on it.

What made this experiment technically interesting was that several
extensions required sub-opcode detection rather than simple opcode-level
gating:

**FLD vs FLW** share opcode OP_LOAD_FP and are distinguished by funct3.
They need separate enable bits (en_d and en_f respectively), which means
the enable check happens at the funct3 level within the opcode, not at
the opcode level.

**Prefetch instructions** are ORI pseudo-ops sharing opcode OP_IMM with
funct3=6. The hint pattern is detected by rd==0. Gating en_zicbop requires
identifying the hint encoding inside OP_IMM.

**CBO instructions** — cbo.inval, cbo.clean, cbo.flush (Zicbom), and
cbo.zero (Zicboz) — share OP_MISC_MEM with funct3=2 and are distinguished
by inst[24:20]. Two different enable bits apply within the same
opcode/funct3 cell.

**CSR vs privilege instructions**: CSRRW, CSRRS, and other CSR
instructions (funct3 != 0) are gated on en_zicsr. ECALL, EBREAK, MRET,
SRET, and WFI are not — they are base ISA privilege operations and are
never ILLEGAL via ext_enable.

A note on the PA/IA balance in this experiment: the decoder experiments
placed more research load on Claude Code (IA) than is typical for hardware
tasks. Because riscv-opcodes was installed in the file system Claude Code
could access directly, the instruction encoding ground truth was available
locally. For tasks with strict compliance requirements — like matching the
exact RVA23 extension list — this shifts research responsibility toward
the implementation agent rather than the planning agent, since the planning
agent (Claude.ai) cannot access the file system directly. The split worked
well: Claude Code's read-before-write access to riscv-opcodes produced
zero encoding errors across the full decoder track.

DECODE-011 required two sessions due to context limits. The first session
exhausted context during the research phase before writing any code. The
second session completed the full implementation in 8 minutes and 5
seconds. Research cost and implementation cost can be decoupled: a heavy
research phase in one session does not prevent a fast implementation in
the next.

The make coverage target added in this experiment formalizes coverage as
a gated build step: exit 0 when no MISSING instructions are found, exit 1
otherwise. ROUTED instructions — intentionally decoded at opcode level
rather than per-instruction — do not trigger failure. V extension ROUTED
is correct by design and the build passes.

Result: 476 predecode tests + 567 decoder tests = 1043 total passing.
make coverage: exit 0, no MISSING instructions.

## What the Methodology Taught Us

Running eleven decoder experiments over two days with a dual AI assistant
architecture produced some clear findings about what works and what needs
active management.

**Read-before-write is load-bearing**: The instruction to read riscv-opcodes
before writing RTL produced zero encoding errors across 160 vector ALU
entries. Errors that surface as test failures are expensive to diagnose.
Consistent clean first-pass test results across every experiment suggest
the discipline was doing real work.

**Technical debt scheduling works**: Every piece of debt identified in
this project was scheduled explicitly and closed within the same experiment
sequence that discovered it. The mechanism is simple: name the debt in the
results, put it in the background section of the next experiment prompt.
Nothing accumulated.

**Style enforcement requires automation**: Prose requirements in a context
document are not sufficient for consistent formatting compliance. The
pattern repeated across multiple experiments before automated check scripts
were identified as the necessary solution. This is a methodology lesson
worth carrying forward: correctness through prompt discipline, style
through automated scripts.

**Context limits are an operational reality**: Multiple experiments in
this group involved context limits or compaction events. All were handled
without loss of work. The context isolation pattern is resilient to
interruption by design. Targeted reads — read only the sections relevant
to this experiment — extended usable session length meaningfully.

**The methodology improves itself**: DECODE-011 produced three additions
to TEMPLATE.md — results reporting discipline, illegal instruction handling
specification, and RVV micro-op expansion policy. The process generated
enough concrete evidence to revise the methodology it was running under.

## What Comes Next

The decoder track is complete for now. 1043 tests pass. All RVA23
mandatory instructions are covered and all pipeline interfaces are defined.

Several decoder-adjacent topics remain for future sessions:

**Full branch pre-decode**: The `may_be_branch` hint in predecode_pkt_t
is a placeholder. A full branch detection pre-decode stage with the
resolution needed by the BPU — identifying branch types, target addresses,
and call/return patterns early enough to feed the prediction pipeline —
will be designed as part of the fetch unit work.

**Macro-op fusion**: Instruction pairs that can be fused into a single
micro-op (common patterns include lui+addi, auipc+load, and compare-
and-branch sequences) were deliberately not scoped for the decoder track.
This is future work alongside the uop cache design.

**NOP filtering**: Eliminating NOP instructions before they consume
rename and issue queue bandwidth is a natural complement to fusion.
Not yet scoped; will be considered together with fusion policy.

**Per-instruction enable gating for Zbb/Zbs/Zfhmin/Zfa**: These
extension enable bits are present in ext_enable_t but not yet wired
at per-instruction granularity. The instructions currently route to
functional units without fine-grained decode. Per-instruction gating
will be added when those instructions are decoded explicitly in later
pipeline stages.

---

### Session Statistics: DECODE-008 through DECODE-011

| Task ID    | Tests Passing | Runtime                             |
|------------|---------------|-------------------------------------|
| DECODE-008 | 525           | 10m 49s                             |
| DECODE-009 | 543           | 5m 26s                              |
| DECODE-010 | 891           | 39m 14s + 2.5hr pause (usage limit) |
| DECODE-011 | 1043          | 38m 55s + 8m 05s (2 sessions)       |

---
---
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*

