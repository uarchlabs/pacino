<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# BLOG_decoder_1_rva23_profile

```
 FILE:    BLOG_decoder_1_rva23_profile
 STATUS:  unpublished
 UPDATED: 2026.05.14
 CONTACT: uarchlabs@gmail.com
```

# What RVA23 Actually Asks of a Decoder

There is a version of RISC-V processor design that sounds straightforward:
pick the extensions you need, implement them, ship. The modular ISA 
(Instruction Set Architecture) is
one of RISC-V's genuine strengths — you are not dragged into supporting
instructions your workload will never use, and the base integer ISA is
clean enough that a minimal implementation is genuinely minimal.

The version of RISC-V processor design I am actually doing is different.
I am building a server-class out-of-order core targeting the RVA23
application processor profile. That changes the problem considerably.

## What a Profile Is and Why It Matters

RISC-V defines mandatory extension sets through profiles rather than
through the base ISA. A profile is a named, versioned set of extension
requirements — a processor claiming RVA23 compliance must implement a
specific list of extensions, all mandatory, no omissions. For the
application processor tier, RVA23 is the current generation target: it
is what Linux distributions and toolchains can assume is present on a
conformant system. To be precise, I am building the RVA23S64 profile [1].
This is a 64-bit profile with supervisor instructions targeting 
server-class machines. I will use RVA23 throughout as shorthand for RVA23S64.

The mandatory extension list for RVA23 is not short. At minimum it
includes the base integer and multiply-divide extensions (RV64IMA),
single and double precision floating point (FD), compressed instructions
(C) including the Zcb subset, bitmanipulation extensions (Zba, Zbb, Zbs),
the vector extension (V), vector half-precision float (Zvfhmin), and a
collection of smaller extensions covering CSR instructions, cache block
operations, and scalar half-precision float (Zfhmin, Zfa, Zicsr, Zicbom,
Zicbop, Zicboz). The hypervisor extension (H) is also required.

For a software developer, this is a feature list. For the processor
implementation team, each item on that list is a set of instructions the
decode stage must handle correctly, in parallel, at the target fetch width.

Because RVA23 mandates all of these extensions without exception, a
conformant processor does not actually need per-extension enable logic at
the decoder level — either the full profile is implemented or it is not.
I added an extension enable mechanism anyway, as a deliberate engineering
choice for validation and silicon bring-up. Being able to disable
individual extensions at the decoder level — flagging their instructions
as ILLEGAL — is useful during integration testing even when the final
product will always run with all extensions active. More on this when we
reach that experiment.

## Instruction Encoding Formats

RISC-V instructions follow a small number of fixed-width encoding formats.
Base ISA instructions are either 16 or 32 bits wide.

Within the 32-bit word, the lower 7 bits are always the opcode, and the remaining fields carry operand register indices, immediate values, and disambiguation fields. The fields that matter most for the decoder are:

- **funct3** (bits [14:12]): A 3-bit field that distinguishes instructions
  within the same opcode group
- **funct6** (bits [31:26]) and **funct7** (bits [31:25]): Higher-order
  disambiguation fields used extensively by the vector extension and
  arithmetic operations respectively

See [2] for funct3 and funct6 documentation.

The vector ALU decode work described in the next post depends almost
entirely on funct3 and funct6: funct3 selects the instruction group
(integer, floating-point, or mixed), and funct6 selects the specific
operation within that group. Getting those field values right from the
specification rather than from model training data was a central
discipline of the IA prompt implementation.

See [3] for the vector instruction documentation.

![RISC-V base and compressed instruction formats](diagrams/scalar_encoding_formats.svg)

![Vector V extension instruction encoding formats](diagrams/vector_encoding_formats.svg)


## The Decode Problem at 8 Instructions Per Cycle

A high-performance out-of-order core does not decode one instruction per
cycle. The Pacino target is a fetch bundle of eight 32-bit instructions decoded
simultaneously, producing results in a single cycle. Every instruction in
the bundle must be identified, its operands extracted, its type classified,
and its output routed to the correct downstream packet — all in parallel,
all in the same cycle.

At this width, the decoder is not a lookup table with some muxes around
it. It is eight parallel decoders operating on independent instructions,
sharing only the structural definitions they decode into. Any serial
dependency across slots — any logic that says "look at slot N before
deciding what to do with slot N+1" — is a potential speed path.

This constraint is not just a performance requirement. It shapes every
architectural decision made during decoder implementation.

## Why Compressed Instructions Complicate the Front End

The C extension allows 16-bit instruction encodings as compressed forms
of common 32-bit instructions. A fetch bundle from an RVA23 processor
can contain a mix of 16-bit and 32-bit instructions packed together
in memory without alignment between them.

The RISC-V RVC encodings were deliberately designed so that each compressed
instruction is a proper subset of a 32-bit instruction — same opcode
semantics, different encoding density. This design choice means hardware
can expand 16-bit instructions to their 32-bit equivalents early in the
pipeline, after which the backend sees only 32-bit instructions and
requires no knowledge of the compressed encoding. It simplifies
functional unit implementation at the cost of an expander in the front
end.

The expansion introduces a bookkeeping obligation: a 16-bit instruction
at address 0x1000 that is expanded to 32 bits must retain its original
16-bit PC throughout the pipeline. The expanded instruction cannot be
treated as if it were a native 32-bit instruction at that address.
Precise exceptions, branch targets, and debug information all depend on
the original PC. The fetch bundle must carry both the expanded instruction
bits and the address of the 16-bit encoding that produced them.

The Zcb extension adds additional compressed instruction variants beyond
base C. Some Zcb encodings share bit patterns with base C instructions
and are distinguished only by specific field values — a subtlety that
affected both the expander logic and coverage validation tooling during the IA
implementation.

## Why the Vector Extension Changes the Architecture

The RVA23 vector extension (RVV) is not simply more instructions. It
introduces a separate register file (32 vector registers), a type system
for element width and grouping (vtype), and a length register (vl) that
affects how many elements each instruction processes. None of these exist
in the scalar ISA.

More concretely for the decoder: vector instructions need different
information extracted from the encoding than scalar instructions do, they
consume different register names, and they go to different execution
resources. A dual-packet output architecture — one packet stream for scalar
instructions, a separate one for vector — is the natural response. But it
means the decode stage produces two parallel output bundles instead of one,
and every downstream stage from rename to commit must consume both.

The vtype dependency is particularly interesting. Instructions like vsetvl
and vsetvli set the current vector type — element width, grouping, tail and
mask policy — and every subsequent vector instruction consumes that type.
This is a data dependency that flows through a special register rather than
a general-purpose register, and tracking it correctly matters for
performance. I implemented a dedicated combinational pre-decode block that
scans the fetch bundle before the main decoder runs, identifies vsetvl
instructions, and annotates each slot with vtype dependency information.
This keeps the main decoder stateless while giving the rename stage the
information it needs to track the dependency correctly.

A full branch detection pre-decode stage — capable of providing early
branch information to the branch predictor with the resolution needed by
the BPU and FTQ — is planned but deferred to the fetch unit design phase.
The pre-decode block implemented here carries a conservative
`may_be_branch` hint signal set by opcode alone as a placeholder. The
full branch pre-decode design requires the fetch unit interface to be
defined first, since its output format is tightly coupled to how the
BPU consumes early prediction targets.

## The Encoding Overlap Problem

Here is a problem that does not appear in extension feature lists but
absolutely appears in implementation: vector load and store instructions
share opcodes with scalar floating-point loads and stores.

In the RISC-V encoding, opcode 0x07 is OP_LOAD_FP — the scalar floating
point load opcode. It is also used by vector load instructions. Opcode
0x27 is OP_STORE_FP and is similarly shared. The disambiguation between
scalar FP and vector memory operations happens at the width field within
the instruction, not at the opcode level.

This means the decoder cannot route these instructions by opcode alone.
For 0x07 and 0x27, it must inspect the width field first, then decide
which decode path applies. The scalar FP path must be preserved exactly;
the vector memory path must extract entirely different information from
the same instruction bits.

This is not a theoretical edge case. vle32.v — load a vector of 32-bit
elements — uses opcode 0x07. Without explicit disambiguation logic, a
decoder would misidentify every vector load as a scalar FP load. Getting
this right while keeping the scalar path unchanged is one of the more
interesting problems in building an RVA23 decoder.

## What We Set Out to Build

Given all of this, Pacino's decoder implementation had four concrete
requirements.

First, eight-instruction parallel decode with single-cycle latency. No
serial dependencies between slots.

Second, complete RVA23S64 coverage. Every mandatory instruction from every
mandatory extension, plus correct handling of disabled extensions
producing an ILLEGAL decode packet for downstream exception handling. This last constraint was a self imposed forward looking feature intended to assist bring up.

Third, a dual-packet output architecture. Scalar instructions produce
decode_pkt_t; vector instructions produce vec_decode_pkt_t. A steering
signal tells downstream stages which packet to consume for each slot.

Fourth, a combinational pre-decode block that identifies vtype-producing
instructions before the main decoder runs, annotates the bundle with
dependency information, and provides a clean interface for the rename
stage to track vtype without the main decoder holding any state.

The implementation used a structured AI co-design methodology with a dual
assistant architecture: Claude.ai for architectural planning and experiment
design, Claude Code for RTL implementation and automated verification.
Experiments were isolated to single sessions with defined hypotheses,
explicit deliverables, and ground-truth verification against the
riscv-opcodes [4] repository rather than model training data.

The next post describes how I built the scalar foundation and worked
through the full vector ALU instruction space.

## References

```
[1] RVA23 Profiles
    https://github.com/riscv/riscv-profiles/blob/main/src/rva23-profile.adoc
    accessed 2026.05.01
[2] RISC-V Unprivileged ISA Specification 
    https://github.com/riscv/riscv-isa-manual
    accessed 2026.05.01
[3] RISC-V Vector Extension Specification (RVV 1.0)
    https://github.com/riscvarchive/riscv-v-spec/blob/master/v-spec.adoc
    accessed 2026.05.01
[4] riscv-opcodes 
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

