<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Technical Post-Mortem: RVA23 Decoder - Vector ALU Disambiguation

## Session Overview
- **Date**: March 22, 2026
- **Focus**: Complete vector ALU instruction disambiguation
- **Experiments**: DECODE-005, DECODE-006, DECODE-007
- **Results**: 453 tests passing, all non-memory vector ALU instructions
  fully decoded, v_op_class_t enum complete for computational instructions
- **Generated**: generated in doc's session labeled `RVA23 Co-Design PM 2`

## Premise

With the vector decode foundation established in DECODE-004, the decoder
entered its most technically dense phase: full funct6 disambiguation for
all three vector ALU instruction groups. DECODE-005 through DECODE-007
proceeded in strict dependency order — integer ALU first, floating point
second, mask/reduce/permute third — each experiment closing the previous
one's deferred scope and carrying forward any technical debt discovered
along the way.

The three experiments share a common pattern: read rv_v as ground truth,
expand the enum, add nested funct6 decode within decode_vec_one(), extend
the testbench, verify clean. The discipline held across all three sessions.
What varied was the spec complexity encountered and the quality of Claude's
independent judgment when that complexity exceeded what the prompt
anticipated.

## Implementation Phases

### Phase 1: Integer ALU Disambiguation (DECODE-005)
**Objective**: Replace VALU_INT placeholder with per-instruction VOP_*
entries for all OPIVV, OPIVX, and OPIVI instructions

**Approach**:
- Read rv_v as ground truth before writing any RTL
- Add 63 VOP_* enum entries (7'd8 through 7'd70) to v_op_class_t
- Implement nested funct6 decode: outer case on funct3, inner on funct6
- Retain VALU_FP and VALU_INT as coarse placeholders for later experiments
- Directed tests: per-funct3-group coverage plus regression on deferred groups

**Results**:
- 63 VOP_* entries added, v_op_class_t expanded from logic[3:0] to logic[6:0]
- 351 tests passing, 0 failures
- Run time: 9m 39s

**Key Technical Findings**:

1. **funct6=0x17 ambiguity (vmerge vs vmv.v.\*)**: The same funct6 value
   encodes both vmerge (vm=0) and vmv.v.\* (vm=1) across OPIVV, OPIVX,
   and OPIVI. Claude identified this from rv_v, resolved it by checking
   inst[25] inside the funct6 case, and classified it correctly. No prompt
   guidance was provided for this case.

2. **vmadc/vmsbc mask-bit variants**: funct6=0x11 and 0x13 each encode
   two instruction variants distinguished only by the vm bit. Claude
   correctly mapped both variants to the same VOP_VMADC/VOP_VMSBC class
   and deferred the distinction to rename. This is the right decision:
   the decoder should not make policy decisions about mask-bit handling.

3. **Cross-funct3 funct6 asymmetry**: funct6=0x0e encodes vrgatherei16
   in OPIVV but vslideup in OPIVX and OPIVI. No conflict due to the outer
   funct3 case, but this required careful reading of rv_v to catch.

**Style Non-Compliance**:
Claude did not follow the 80-column line width requirement specified in
CLAUDE.md. This was the first appearance of a recurring issue across the
vector decode experiments. The requirement was elevated from a style
suggestion to a strict rule and graduated to CLAUDE.md.

### Phase 2: Floating Point ALU + Zvfhmin Closure (DECODE-006)
**Objective**: Disambiguate OPFVV and OPFVF groups, close Zvfhmin
compliance automatically

**Approach**:
- 53 VOP_* entries (7'd71 through 7'd123) for full OPFVV/OPFVF coverage
- Nested funct6 decode following the DECODE-005 pattern
- cvt group (funct6=0x12) requires a second level of disambiguation on
  inst[19:15] for vfcvt/vfwcvt/vfncvt
- VALU_FP placeholder removed upon completion
- Dedicated VOP_VFWCVT_FF and VOP_VFNCVT_FF entries for Zvfhmin closure

**Results**:
- 53 VOP_* entries added
- 396 tests passing, 0 failures
- Run time: 10m 43s
- Zvfhmin: coverage script confirmed all instructions covered under V
  (no dedicated reference file; both instructions fall within OPFVV)

**Key Technical Findings**:

1. **cvt group subfunct encoding**: funct6=0x12 covers vfcvt, vfwcvt, and
   vfncvt, further disambiguated by inst[19:15]. The two Zvfhmin
   instructions (vfwcvt.f.f.v subfunct=0x0C, vfncvt.f.f.w subfunct=0x14)
   required explicit case entries before the group-level fallback. Claude
   read rv_v and decoded this correctly on first pass.

2. **funct6=0x13 sqrt/class group**: vfsqrt, vfrsqrt7, vfrec7, and
   vfclass share one funct6, further distinguished by inst[19:15].
   Unassigned subfunct values map to VOTHER correctly.

3. **vfmv.f.s scalar destination (technical debt introduced)**:
   funct6=0x10 in OPFVV encodes vfmv.f.s, where the destination is a
   scalar GPR (rd), not a vector register (vd). Claude identified this
   downstream risk — dispatch cannot use v_op_class alone and must also
   inspect funct3 to distinguish vfmv.f.s from vfmv.s.f (OPFVF
   funct6=0x10). The clean solution is a dedicated VOP_VFMV_FS enum
   entry. This was noted as technical debt and scheduled for resolution
   in DECODE-007.

**Style Non-Compliance**:
Both the 80-column and 2-space indent requirements were ignored again.
The 2-space indent rule was graduated to CLAUDE.md at the close of this
experiment. The pattern of repeated non-compliance led to a recommendation
to add a format check script and require it to pass as a deliverable.

### Phase 3: Mask, Reduce, Permute, and Integer MAC (DECODE-007)
**Objective**: Complete OPMVV/OPMVX disambiguation, remove final coarse
placeholder, close vfmv.f.s technical debt from DECODE-006

**Approach**:
- Wire existing stubs VOP_VWADDU through VOP_VNMSUB (7'd52 through 7'd70)
  defined in DECODE-005
- Add new VOP_* entries: mask logical group, integer reductions, permute,
  misc OPMVV/OPMVX
- Resolve vfmv.f.s by adding VOP_VFMV_FS and updating OPFVV funct6=0x10
- OPMVX scalar GPR source contract: pkt.vs1=5'b0, GPR in scalar
  decode_pkt_t.rs1
- Remove VALU_INT placeholder

**Results**:
- 44 VOP_* entries added (7'd124 through 7'd167)
- Final total: 168 VOP_* entries across DECODE-004 through DECODE-007
- 453 tests passing, 0 failures
- Run time: 15m 40s

**Key Technical Findings**:

1. **Enum width overflow (proactive fix)**: 168 entries exceeded the
   7-bit logic[6:0] width. Claude identified this independently, widened
   v_op_class_t to logic[7:0], and noted it in the deliverables without
   prompting. This was not anticipated in the experiment design.

2. **OPMVV subfunct groups**: Three funct6 values (0x10, 0x12, 0x14)
   required a second disambiguation level on inst[19:15]:
   - 0x10: vmv.x.s, vcpop.m, vfirst.m
   - 0x12: vzext (x2/x4/x8) and vsext (x2/x4/x8)
   - 0x14: vmsbf, vmsof, vmsif, viota, vid

3. **vfmv.f.s technical debt closed**: VOP_VFMV_FS added as a dedicated
   enum entry. Dispatch can now route vfmv.f.s using v_op_class alone
   without inspecting funct3.

4. **vmvNr.v aliasing resolved**: funct6=0x27 in OPIVI with vm=1 was
   previously aliased to VOP_VMV. Dedicated VOP_VMVNR entry added,
   eliminating the aliasing.

5. **OPMVX scalar GPR contract established**: All OPMVX instructions set
   pkt.vs1=5'b0; the scalar source GPR is in scalar decode_pkt_t.rs1.
   Dispatch must inspect v_op_class or funct3=OPMVX to route the operand
   to the correct functional unit port. This is an interface contract
   with downstream stages.

6. **Context compaction during session**: DECODE-007 was the largest
   single decoder session to date. Claude Code entered a context
   compaction event mid-session, after which it updated the experiment
   results file autonomously — new behavior not observed in prior
   sessions. This signaled that the cumulative decoder RTL and package
   file sizes were approaching context limits. Noted as a factor to
   manage in future sessions.

**Style Non-Compliance**:
80-column limit still not consistently followed. RTL quality rated 4/5.
Formal style enforcement via a check script was identified as the
necessary next step.

## Overall Results

### Technical Achievements
- **Complete vector ALU decode**: All OPIVV, OPIVX, OPIVI, OPFVV, OPFVF,
  OPMVV, and OPMVX instructions fully disambiguated
- **Zvfhmin closed**: Coverage script confirmed 0 missing instructions
- **168-entry v_op_class_t**: Complete enum for all non-memory vector
  computational instructions
- **Clean test progression**: 351 → 396 → 453 tests with no failures
  across all three experiments
- **Technical debt managed**: vfmv.f.s debt identified in DECODE-006,
  scheduled explicitly, and closed in DECODE-007 within the same session
  day

### Key Metrics

| Experiment | Entries Added | Cumulative | Tests | Run Time |
|---|---|---|---|---|
| DECODE-005 | 63 | 71 | 351 | 9m 39s |
| DECODE-006 | 53 | 124 | 396 | 10m 43s |
| DECODE-007 | 44 | 168 | 453 | 15m 40s |

### Interface Specifications (Downstream Impact)
1. **v_op_class_t width**: logic[7:0] — all downstream consumers must
   handle 8-bit enum width
2. **vmadc/vmsbc variants**: vm bit passed through in vec_decode_pkt_t;
   rename must inspect to distinguish masked variants
3. **OPMVX scalar GPR contract**: pkt.vs1=5'b0 for all OPMVX; GPR in
   scalar decode_pkt_t.rs1. Dispatch must route accordingly.
4. **VOP_VFMV_FS vs VOP_VFMV**: dispatch can use v_op_class alone to
   distinguish vfmv.f.s (scalar destination) from vfmv.s.f
5. **VOP_VMVNR**: whole-register move — distinct from vmv.v.* for
   dispatch and execution unit routing

## Technical Decisions Made

### Read-Before-Write Discipline
- **Chosen**: Explicit requirement in each prompt to read rv_v as ground
  truth before writing any RTL
- **Rationale**: Vector funct6 encodings have known subtleties that
  diverge from what training data would produce. The cvt subfunct
  encoding (DECODE-006) and the OPMVV subfunct groups (DECODE-007) both
  required rv_v to decode correctly.
- **Result**: Zero encoding errors across 160 VOP_* entries added.
  Ambiguities were identified from the spec, not discovered through test
  failures.

### Technical Debt Carry-and-Close Pattern
- **Chosen**: Identify debt explicitly when discovered, schedule it for
  the next experiment, close it on schedule
- **Rationale**: Unresolved ambiguities compound. The vfmv.f.s issue
  left open past DECODE-007 would have required dispatch to carry the
  funct3 inspection workaround indefinitely.
- **Result**: vfmv.f.s and vmvNr.v both identified and resolved within
  the same three-experiment sequence without slipping to later work.

### Scope Isolation Per Experiment
- **Chosen**: Each experiment touches only decode_pkg.sv and
  instr_decoder.sv; each defers adjacent instruction groups explicitly
- **Rationale**: Prevents scope creep and maintains clean test baselines
  for regression detection
- **Result**: No regressions across any experiment. Each test suite
  addition is additive.

### Style Enforcement Evolution
- **Problem**: 80-column and indent requirements specified in CLAUDE.md
  were consistently ignored across all three experiments
- **Decision path**: DECODE-005 elevated 80-column to strict; DECODE-006
  added 2-space indent; DECODE-007 identified that a check script with
  pass requirement was the necessary enforcement mechanism
- **Lesson**: Prose requirements in CLAUDE.md are insufficient for
  consistent compliance. Automated enforcement is required.

## Lessons Learned

### Technical Insights
1. **Spec subtlety detection**: Claude consistently caught encoding
   ambiguities that required real spec knowledge — the vmerge/vmv
   inst[25] check, the cvt subfunct decode, and the OPMVV subfunct
   groups. None of these were anticipated in the prompts. The
   read-before-write directive was the enabling condition.

2. **Proactive scope management**: In DECODE-007 Claude identified and
   resolved the enum width overflow without prompting, and updated the
   experiment file autonomously after context compaction. Both are
   examples of correct judgment under constraint.

3. **Context size as a design factor**: The compaction event in
   DECODE-007 signals that cumulative decoder complexity is real. Future
   sessions touching the same files need to account for this, either
   through tighter scope or reduced read requirements.

4. **Debt scheduling works**: Carrying vfmv.f.s forward explicitly and
   closing it in the next experiment prevented it from becoming
   indefinitely deferred. The mechanism is simple — note it in the
   results, include it in the next prompt's background section.

### AI Co-Design Insights
1. **Prompt detail level**: DECODE-005's prompt was highly detailed by
   design. It produced correct results but the question was noted:
   would a less detailed prompt have produced equivalent output? This
   was identified as a candidate for a controlled comparison experiment.

2. **Self-assessment reliability**: In DECODE-007, Claude reported its
   own "got right / got wrong" sections after context compaction. The
   self-assessments were accurate and complete. This is a useful
   property — the model can produce honest self-evaluation when the
   results are available.

3. **Style compliance gap**: Technical correctness was consistently high
   (5/5 RVA23 compliance across all three experiments). Formatting
   compliance was consistently low. These are separable concerns and
   should be enforced through separate mechanisms — correctness through
   prompt discipline, style through automated scripts.

4. **Scope deference**: In no case did Claude attempt to implement
   deferred scope (e.g., attempting OPMVV decode during DECODE-005).
   The explicit deferral statements in each prompt were respected.

## Follow-up Work

### Immediate (DECODE-008, DECODE-009)
- Vector memory disambiguation: opcodes 0x07/0x27, width/addressing
  mode decode, unit-stride/strided/indexed routing
- Segment loads/stores: nf encoding, whole-register moves, VOP_*SEG
  routing

### Infrastructure (DECODE-010, DECODE-011)
- Pre-decode module: vtype hazard detection, vsetvl/vsetvli/vsetivli
  identification before main decode
- Extension enable/disable: ext_enable_t mechanism, ILLEGAL flag for
  disabled extensions

### Process Improvement
- Format check script: automated enforcement of 80-column and indent
  requirements as a mandatory deliverable
- Prompt detail experiment: controlled comparison of high-detail vs.
  reduced-detail prompts for equivalent experiments

## Conclusion

DECODE-005 through DECODE-007 completed the vector ALU decode in three
disciplined sessions across a single day. The 168-entry v_op_class_t enum
and 453 passing tests represent the densest technical phase of the decoder
track. The read-before-write discipline prevented encoding errors across
160 new entries. Technical debt identified mid-sequence was closed
on schedule within the same sequence.

The recurring style compliance gap — correct RTL that consistently
violated formatting requirements — identified a process gap that prose
rules in CLAUDE.md cannot close alone. Automated enforcement was
scheduled as a direct result. This is an example of the methodology
improving itself through observation of its own failure modes.

