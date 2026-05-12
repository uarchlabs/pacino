# BLOG_decoder_2_scalar_to_alu

```
 FILE:   BLOG_decoder_2_scalar_to_alu.md
 STATUS:  unpublished
 UPDATED: 2026-xx-xx
 CONTACT: uarchlabs@gmail.com
```

# Building the RVA23 Decoder: Scalar Foundation to Vector ALU

The previous post [1] described what an RVA23 decoder needs to do: eight
instructions per cycle, complete extension coverage, dual-packet output
for scalar and vector, single-cycle latency. This post describes how I
built it — from the first scalar instruction through 168 vector ALU
enum entries and 453 passing tests.

The implementation ran as a sequence of tightly scoped tasks/experiments,
labeled DECODE-001 through DECODE-011. Each experiment had an explicit
hypothesis, defined deliverables, and was verified against the riscv-opcodes
repository as ground truth. The riscv-opcodes project [2], maintained by the
RISC-V International technical group, provides machine-readable instruction
encoding definitions for all ratified extensions. I installed it in the
project file system and used it as the authoritative source for all instruction
encodings throughout the decoder work.

Claude Code handled RTL implementation and testbench execution.
Claude.ai designed the experiments and evaluated results. I made all
architectural decisions.

## Scalar First (DECODE-001 through DECODE-003)

The decoder architecture begins with the obvious foundation: get the scalar
instructions right before touching the vector extension. DECODE-001
established the parallel pipeline structure — eight decode units operating
on an 8x32b fetch bundle, with the RVC expander upstream handling 16-bit
to 32-bit expansion before the main decoder sees the bundle.

The parallel structure is non-negotiable. Eight combinational decode paths,
one per slot, no feedback between them. Every signal the decoder produces
for slot N is computed solely from the instruction bits in slot N. This
is what makes single-cycle latency achievable and what makes the decoder
straightforward to reason about: each slot is an independent problem.

DECODE-002 ran a coverage analysis against the full RVA23 mandatory
extension list. The result was 99.7% scalar coverage — substantially
complete but with Zcb compressed instructions remaining. DECODE-003 closed
that gap by implementing the 13 remaining Zcb instructions and, usefully,
exposing a false-negative in the coverage script itself. Zcb shares some
encodings with base C instructions; the coverage tooling was initially
counting them as missing when they were already handled. Fixing that was
as important as implementing the instructions — a coverage metric you
cannot trust is worse than no metric at all.

After DECODE-003: 100% scalar coverage, tooling accurate, 12m 56s of
implementation time to close the last 0.3%.

## The Dual-Packet Architecture (DECODE-004)

The vector foundation experiment was the first genuinely architectural
decision in the decoder track. The question was not just "how do we decode
vector instructions" but "what does the decoder's output look like when
it has to handle both scalar and vector instructions in the same bundle."

I chose a dual-packet approach. The decoder produces three parallel output
streams:

```
decode_pkt_t     decode_bundle[7:0]     // scalar decode, one per slot
vec_decode_pkt_t vec_decode_bundle[7:0] // vector decode, one per slot
logic            is_vector[7:0]         // per-slot steering signal
```

![Dual-packet decoder output architecture](diagrams/dual_packet_output.svg)

Every slot produces output in both bundles. For a scalar instruction, the
scalar packet is populated and the vector packet is a placeholder; for a
vector instruction, the reverse. The `is_vector` signal tells rename and
dispatch which packet to use for each slot. No conditional decoding, no
format probing at the consumer — the consumer receives both packets and
picks based on `is_vector`.

Two further decisions from DECODE-004 had lasting downstream impact.

The first is the stateless vtype approach. Instructions like vsetvl and
vsetvli change the current vector type — element width, grouping, mask
policy — and every subsequent vector instruction implicitly consumes that
type. A stateful decoder would track vtype internally and resolve the
dependency at decode time. I chose a stateless decoder instead: the
decoder identifies which instructions produce and consume vtype, annotates
those fields in the packet, and pushes dependency resolution to the rename
stage. This keeps the decoder simpler and leverages the dependency tracking
rename already does for general-purpose registers.

The second is conservative resource marking for vector instructions in
the scalar packet. During the transition period before rename fully
understands the vector packet, vector instructions mark their scalar
register fields as used. This is a deliberate interim trade-off — it
prevents rename from issuing false reads on registers that vector
instructions happen to reference, at some cost to instruction-level
parallelism. It is not technical debt so much as a known conservative
position to be relaxed as rename matures.

After DECODE-004: 284 tests passing, dual-packet architecture operational,
vector instructions routed correctly at opcode level. The v_op_class field
in vec_decode_pkt_t carried only coarse classifications at this stage:

- **VALU_INT**: all integer vector ALU (placeholder for DECODE-005/007)
- **VALU_FP**: all FP vector ALU (placeholder for DECODE-006)
- **VCFG**: vsetvl/vsetvli/vsetivli configuration instructions
- **VMEM**: all vector memory (placeholder for DECODE-008/009)

Each coarse class would be replaced with per-instruction entries in
subsequent experiments, giving downstream issue queues and execution units
the fine-grained opcode information they need to schedule and execute
correctly.

## The Read-Before-Write Discipline

Before describing the vector ALU disambiguation work, it is worth
explaining the constraint that made it go well: every experiment prompt
included an explicit instruction to read the relevant riscv-opcodes
extension file before writing any RTL.

This sounds obvious but it matters more than it might appear. The vector
extension has hundreds of per-instruction encodings at the decode level,
many sharing funct6 values across different funct3 groups with context-
dependent disambiguation. Model training data can produce plausible-looking
encodings that are subtly wrong. The only reliable source is the spec
itself — specifically the rv_v file in riscv-opcodes, which defines every
vector instruction's encoding unambiguously.

The read-before-write directive was honored consistently across all vector
ALU experiments, with riscv-opcodes installed locally so Claude Code
could read it directly from the file system. Its most visible effect was
zero encoding errors across 160 new enum entries. None of the ambiguities
I found surfaced as test failures after the fact — they were all caught
during implementation by reading the spec carefully.

## Vector Integer ALU (DECODE-005)

The first disambiguation experiment replaced the coarse VALU_INT
placeholder with 63 per-instruction VOP_* enum entries for the three
integer ALU groups: OPIVV (vector-vector), OPIVX (vector-scalar), and
OPIVI (vector-immediate). The outer case branches on funct3; the inner
case branches on funct6 within each group. In a single Claude Code
session of under 10 minutes, 63 enum entries were added, the nested
decode was wired, and 351 tests ran clean.

The interesting cases were the encoding subtleties that training data
alone would likely have missed:

**funct6=0x17 across all three groups** encodes both vmerge (vm=0) and
vmv.v.* (vm=1). The same funct6 value, two instructions, distinguished
only by the vm bit in inst[25]. Claude caught this from rv_v and resolved
it with an inst[25] check inside the funct6 case — correct, and with the
right deference: the mask-bit policy interpretation is pushed to rename,
not resolved in the decoder.

**funct6=0x11 and 0x13** encode vmadc and vmsbc variants distinguished
by the vm bit. Both variants map to the same VOP_* class. The vm bit is
passed through in the decode packet; rename distinguishes the masked from
unmasked forms. The decoder classifies the instruction; the mask policy
is resolved where architectural state is available.

**Cross-group funct6 asymmetry**: funct6=0x0e encodes vrgatherei16 in
OPIVV but vslideup in OPIVX and OPIVI. No conflict because the outer
funct3 case separates the groups, but easy to miss when working from
memory rather than from the spec.

One thing went wrong in DECODE-005: Claude did not follow the 80-column
line width requirement from CLAUDE.md. This was the first appearance of
what became a recurring pattern across multiple experiments — technically
correct RTL that consistently violated formatting constraints despite
explicit entries in the project context document. The requirement was
escalated from a suggestion to a strict rule. It continued to be ignored.
By DECODE-007 it was clear that prose requirements in a context document
are not sufficient enforcement and that an automated style check script
added as a mandatory deliverable was the necessary mechanism. That script
was not yet in place for the ALU experiments.

## Vector FP and Zvfhmin (DECODE-006)

The floating-point ALU group added 53 entries for OPFVV and OPFVF,
removed the VALU_FP placeholder, and closed Zvfhmin compliance as a
side effect. Zvfhmin comprises exactly two instructions — vfwcvt.f.f.v
and vfncvt.f.f.w — which are OPFVV instructions. When OPFVV is fully
decoded, Zvfhmin closes automatically. The coverage script confirmed
zero missing Zvfhmin instructions.

The interesting encoding in this group is the cvt family. funct6=0x12
covers vfcvt, vfwcvt, and vfncvt, all sharing one funct6 value and
further disambiguated by inst[19:15] — a subfunct field that acts as a
second level of dispatch within the funct6 case. The two Zvfhmin
instructions sit inside the widening and narrowing ranges and required
explicit case entries before the group-level fallback. Claude read rv_v
and decoded this correctly on first pass — 396 tests clean without
iteration.

DECODE-006 introduced the first explicit technical debt. The instruction
vfmv.f.s — move a vector element to a scalar FP register — uses
funct6=0x10 in OPFVV with the destination in scalar rd rather than
vector vd. Without a dedicated enum entry, dispatch cannot use v_op_class
alone to distinguish this from vfmv.s.f (OPFVF, same funct6) without
also inspecting funct3. The clean fix is a dedicated VOP_VFMV_FS entry
that makes the instruction unambiguous. I noted it explicitly and
scheduled it for DECODE-007 — close enough that it would not accumulate.

## Mask, Reduce, Permute, and Integer MAC (DECODE-007)

The final ALU disambiguation experiment covered OPMVV and OPMVX — the
most structurally complex of the vector instruction groups — and closed
the vfmv.f.s debt from DECODE-006.

Several things happened that were not anticipated in the experiment design:

**Enum width overflow**: 168 entries exceeded 7-bit representation.
Claude identified this independently, widened v_op_class_t from
logic[6:0] to logic[7:0], and noted it in the deliverables without
prompting. All downstream consumers of v_op_class must handle the 8-bit
width.

**vfmv.f.s debt closed**: VOP_VFMV_FS added as a dedicated enum entry.
Dispatch can now route vfmv.f.s by v_op_class alone without inspecting
funct3.

**vmvNr.v aliasing resolved**: Whole-register move instructions
(vmv1r.v through vmv8r.v) were previously aliased to VOP_VMV. A
dedicated VOP_VMVNR entry was added, distinguishing whole-register moves
from the vmv.v.* family for dispatch and execution unit routing.

**OPMVX scalar GPR contract**: Unlike OPIVX and OPFVF, the scalar source
in OPMVX is an integer register rather than a vector or float register.
vs1 is unused; rs1 carries the scalar source. The decode packet contract:
pkt.vs1=5'b0 for all OPMVX, GPR in the scalar decode_pkt_t.rs1.
Dispatch must inspect v_op_class to route the operand correctly.

Three OPMVV funct6 values also required a second disambiguation level
on inst[19:15], handled correctly from rv_v without encoding errors.

A context compaction event occurred mid-session — Claude Code's internal
summarization mechanism that triggers when the active context approaches its
limit (roughly 85%), automatically compressing earlier conversation history to
free space for continued execution. 

This was the first such event in the decoder track, signaling that the
cumulative decoder RTL and package file sizes were approaching context limits.
Claude Code subsequently updated the experiment results file autonomously. Both
were new behaviors not seen in prior experiments and served as advance notice
that context management would need active attention in the sessions that
followed.

These events motivated changes to the task file template to add explicit
labeled regions for the IA to place its results and also explicit instructions
in future prompts that report results in the labeled regions was required.

Result: 453 tests, 0 failures. v_op_class_t: 168 entries, 8-bit width.
VALU_INT and VALU_FP placeholders both removed. All non-memory vector
computational instructions fully decoded.

## What the First Seven Experiments Established

After DECODE-001 through DECODE-007 the decoder had:

- 100% RVA23 scalar coverage including Zcb
- Complete vector ALU decode across all seven funct3 groups
- A 168-entry v_op_class_t enum with per-instruction granularity
- 453 tests passing, zero failures, zero encoding errors against the spec
- Documented interface contracts for rename and dispatch
- All technical debt identified, scheduled, and closed within the
  same experiment sequence

---

### Session Statistics: DECODE-001 through DECODE-007

| Task ID    | New Entries | Tests Passing | Runtime   |
|------------|-------------|---------------|-----------|
| DECODE-001 | —           | (baseline)    | 51m 14s   |
| DECODE-002 | —           | (coverage)    | 5m 51s    |
| DECODE-003 | —           | (scalar)      | 12m 56s   |
| DECODE-004 | 8 coarse    | 284           | 10m 56s   |
| DECODE-005 | 63          | 351           | 9m 39s    |
| DECODE-006 | 53          | 396           | 10m 43s   |
| DECODE-007 | 44          | 453           | 15m 40s   |

Note: this track pre-dates the context usage percentage tracking that occured 
in later sessions.

The next post covers the remainder of the decoder track: vector memory
disambiguation, the pre-decode pipeline block, the extension enable
mechanism, and what I learned working at the scale where context limits
become an operational constraint.

# References

```
[1] INSERT LINK TO PREVIOUS POST WHEN HOSTED

[2] riscv-opcodes
    https://github.com/riscv/riscv-opcodes
    accessed 2026.05.01

```
---
---
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*

