# Technical Post-Mortem: RVA23 Decoder - Vector Memory, Pre-decode Infrastructure, and Closure

## Session Overview
- **Date**: March 23, 2026
- **Focus**: Vector memory decode, pre-decode pipeline stage, extension
  enable mechanism, and decoder track closure
- **Experiments**: DECODE-008, DECODE-009, DECODE-010, DECODE-011
- **Results**: 1043 tests passing across two testbenches, decoder track
  complete for RVA23, coverage tooling integrated as a gated build step

## Premise

The final four decoder experiments fall into two distinct phases. The
first, DECODE-008 and DECODE-009, completed the vector instruction space
by handling memory operations — the one area where vector and scalar
instruction encodings overlap and disambiguation requires structural
inspection rather than opcode routing. The second, DECODE-010 and
DECODE-011, shifted focus from instruction coverage to pipeline
architecture: a new pre-decode module, a new packet type, and an
extension enable mechanism that formalized how the decoder interacts
with the broader system.

The sessions also mark the point where context limits became a real
operational constraint. DECODE-010 hit API usage limits mid-session,
requiring a 2.5-hour pause. DECODE-011 required two separate sessions
to complete. Both were managed without loss of work. The methodology
adapted accordingly.

## Implementation Phases

### Phase 1: Vector Memory Disambiguation (DECODE-008)
**Objective**: Correctly route vector load and store instructions that
share opcodes 0x07 and 0x27 with scalar FP memory operations

**Approach**:
- Targeted read: only OP_LOAD_FP/OP_STORE_FP branches and rv_v
  memory definitions — not the full decoder
- Disambiguation rule: width field [14:12] values 3'b000, 3'b101,
  and 3'b111 are exclusively vector; scalar FP uses 3'b010, 3'b011,
  3'b100 with no overlap
- New decode_vec_mem_one() function for vector memory path;
  scalar FP path untouched via outer if guard
- 21 VOP_* entries added: 13 non-segment plus 8 segment stubs
  deferred to DECODE-009
- T_VLE32_MIS: the documented expected-failure test from DECODE-004
  converted to an expected pass

**Results**:
- 21 VOP_* entries added (VOP_VLE=168 through VOP_VSOXSEG=188)
- 525 tests passing, 0 failures
- Run time: 10m 49s

**Key Technical Findings**:

1. **Clean encoding partition**: The width field split between vector
   and scalar FP is unambiguous — no overlap exists. Width value
   3'b001 is unused in both spaces. Claude confirmed this from rv_v
   without ambiguity. Zero encoding conflicts to resolve.

2. **Surgical scalar FP preservation**: The outer if guard approach
   kept the scalar FP path byte-for-byte identical. FLD and FSD
   regression tests confirmed this explicitly.

3. **Addressing mode contracts established**: Five distinct LSU
   behaviors documented as decode-stage interface contracts:
   - Unit-stride: rs1 only
   - Strided: rs1 as base GPR, rs2 as signed byte stride
   - Indexed: rs1 as base GPR, vs2 as index vector
   - Mask load/store: always unmasked, EEW=8, no tail/mask policy
   - Fault-only-first: LSU may shorten vl on mid-vector fault,
     must write back updated vl to vtype CSR

4. **Indexed ordered distinction flagged proactively**: Claude
   identified the memory ordering constraint for mop=2'b11 without
   a prompt requirement, noting the constraint on OOO LSU scheduling.
   This was not in the experiment scope.

5. **Technical debt introduced**: needs_vtype=1 set for
   VOP_VLWHOLE/VOP_VSWHOLE, but whole-register operations do not
   actually consume vtype. This creates a false dependency in rename.
   Noted explicitly and scheduled for DECODE-009.

**RTL Quality Regression**:
Comment organization was noted as degrading at this point in the
decoder — dangling comments and comments in incorrect position
relative to RTL. Rated 3/5, down from prior experiments. The
accumulating size of the decoder was beginning to affect output
consistency.

### Phase 2: Segment Operations and Debt Closure (DECODE-009)
**Objective**: Complete segment load/store routing, verify
whole-register moves, fix needs_vtype false dependency

**Approach**:
- Targeted read: decode_vec_mem_one() and segment stub entries only
- Segment routing: inspect nf field after base memory type is
  determined; nf=0 non-segment, nf>0 routes to VOP_*SEG
- needs_vtype=0 fix for VOP_VLWHOLE/VOP_VSWHOLE
- Verification-first: whole-register moves (VOP_VMVNR from DECODE-007)
  verified without RTL changes

**Results**:
- No new enum entries — DECODE-008 stubs were functionally correct
- 543 tests passing, 0 failures
- Run time: 5m 26s (shortest session in the decoder track)

**Key Technical Findings**:

1. **Routing already correct**: The segment stubs from DECODE-008 were
   functionally wired correctly. DECODE-009 updated a comment and fixed
   the needs_vtype debt. No additional RTL was required.

2. **nf encoding clarified**: nf is stored as nfields-1 in the
   instruction — nf=0 means non-segment (1 field), nf=1 means 2 fields.
   This was documented in the RTL comment as a contract for downstream
   LSU. The note that inst[28] is reserved was caught from rv_v.

3. **Debt closed on schedule**: needs_vtype=0 fix applied precisely for
   VOP_VLWHOLE/VOP_VSWHOLE only. Segment operations retain needs_vtype=1
   correctly.

4. **Verification discipline**: All four vmv\*r.v whole-register move
   variants confirmed as VOP_VMVNR with no regression. The experiment
   found nothing to fix — and documented that finding explicitly rather
   than manufacturing changes.

**Note on Session Length**: The 5m 26s runtime reflects both the
narrow scope and the payoff of incremental design. Correct stubs in
DECODE-008 meant DECODE-009 was primarily verification. This is the
intended outcome of the debt scheduling pattern.

### Phase 3: Pre-decode Module (DECODE-010)
**Objective**: Implement a dedicated combinational pre-decode stage
that annotates the fetch bundle with vtype dependency information
before the main decoder runs

**Approach**:
- New predecode_pkt_t struct in decode_pkg.sv carrying valid, instr,
  is_vsetvl, needs_vtype, vtype_hazard, and may_be_branch
- New purely combinational predecode.sv module with prefix-OR chain
  for intra-bundle vtype hazard detection across all 8 slots
- instr_decoder.sv interface updated: input changes from raw fetch
  bundle to predecode_pkt_t[7:0]
- Separate testbench tb_predecode.sv (13 test cases, 348 checks)
- Makefile extended with lint_predecode, sim_predecode, sim_all targets

**Results**:
- 348 predecode tests + 543 decoder tests = 891 total passing
- Run time: 39m 14s plus a 2.5-hour pause for API usage limit

**Key Technical Findings**:

1. **Parallel hazard detection**: The prefix-OR chain computing
   vtype_hazard[i] as needs_vtype[i] AND OR_REDUCE(is_vsetvl[i-1:0])
   was implemented correctly as unrolled continuous assigns — no loops,
   fully parallel across all 8 slots.

2. **Forward-looking interface**: clk/rstn ports included on predecode.sv
   even though the module is purely combinational. This allows a pipeline
   register slice to be inserted at any point without interface changes
   to connected modules. A small decision with meaningful downstream value.

3. **Verilator 5.020 quirk resolved independently**: Variable-indexed
   array writes inside tasks (fetch_valid[slot] where slot is an int)
   do not trigger re-evaluation of dependent assign statements in
   Verilator 5.020. Claude identified this and worked around it with
   an explicit case statement using compile-time-constant indices. This
   was not in the prompt. The finding was documented in a separate
   observations file.

4. **vtype_hazard policy boundary maintained**: The signal is available
   to rename via predecode_out. The actual scheduling policy (stall,
   rename insertion, forwarding) is explicitly deferred to the rename
   stage per CLAUDE.md. The experiment created the signal without
   encoding the policy — correct separation of concerns.

5. **may_be_branch as a conservative hint**: Set for JAL, JALR, and
   BRANCH opcodes. False positives documented: illegal JALR encodings
   and reserved opcodes that happen to share those opcode values. No
   false negatives for standard control flow. Downstream stages are not
   required to act on this signal without full decode confirmation.

**Context Management**:
DECODE-010 was the first experiment to hit API usage limits during
execution. Work was paused for 2.5 hours and resumed cleanly. No
state loss occurred due to the context isolation pattern — fresh session
at resume with the experiment prompt re-pasted. This validated the
robustness of the one-experiment-one-session methodology under real
operational constraints.

### Phase 4: Extension Enable/Disable and Decoder Closure (DECODE-011)
**Objective**: Add static ext_enable_t input to predecode.sv and
instr_decoder.sv; flag disabled-extension instructions as ILLEGAL;
integrate coverage as a gated build target

**Approach**:
- New ext_enable_t struct (18 RVA23 extension bits) with RVA23_ENABLE
  all-ones default parameter
- predecode.sv: vector annotation flags gated on en_v
- instr_decoder.sv: ILLEGAL gating at appropriate granularity per
  extension — opcode level for most, sub-opcode where required
- make coverage target: exit 0 on clean, exit 1 on MISSING
  instructions; ROUTED does not trigger failure
- check_rva23_coverage.py: --strict flag added for future enforcement

**Results**:
- 476 predecode tests + 567 decoder tests = 1043 total passing
- Run time: 38m 55s + 8m 05s (two sessions, context limit mid-session)
- make coverage: exit 0, no MISSING instructions, V extension ROUTED

**Key Technical Findings**:

1. **Sub-opcode extension gating required in several cases**:
   - FLD vs FLW share OP_LOAD_FP — gated separately on en_d and en_f
     by funct3, not by opcode alone
   - prefetch.\* instructions are ORI pseudo-ops (OP_IMM, funct3=6,
     rd=0) — en_zicbop gating requires detecting the hint pattern
     inside OP_IMM rather than at opcode level
   - CBO instructions share OP_MISC_MEM with funct3=2 — inst[24:20]
     distinguishes cbo.inval/clean/flush (Zicbom) from cbo.zero
     (Zicboz)
   - CSRRS/CSRRC and other CSR instructions gated on en_zicsr;
     ECALL/EBREAK/MRET/SRET/WFI explicitly excluded — base ISA
     privilege operations are never ILLEGAL via ext_enable

2. **Correct enum width for unused signals**: en_zbb, en_zbs,
   en_zfhmin, and en_zfa are struct members but not yet wired at
   per-instruction level since those instructions route to functional
   units without fine-grained decode. UNUSEDSIGNAL suppression
   applied with explanatory comments. The struct is complete; the
   gating will be added as per-instruction decode is implemented in
   later pipeline stages.

3. **Coverage tooling formalized**: The make coverage target closes
   the loop between implementation and verification. Exit code
   semantics correctly gate on MISSING (gaps in coverage) not ROUTED
   (intentional decode-level routing). V extension ROUTED is correct
   by design and does not indicate a deficiency.

4. **Context limit as operational data**: The initial DECODE-011
   session exhausted context during the research phase before writing
   any code. The second session completed the implementation in 8m 05s.
   The separation demonstrated that research cost and implementation
   cost can be decoupled — prompt design should account for this in
   complex experiments.

**Methodology Updates (Graduated to TEMPLATE.md)**:
Three additions to the experiment template as direct results of
DECODE-011:
- Claude Code must report results to console only, not write to
  .md files
- Illegal instruction handling: ILLEGAL flag at decode, pass through
  rename, handle at ROB commit head per RISC-V spec convention;
  ROB redirects to mtvec, writes mepc and mcause=2
- RVV micro-op expansion policy: segment loads/stores and
  whole-register ops are candidates; policy TBD at vector execution
  unit design stage; nf field in decode packet provides expansion count

## Overall Results

### Technical Achievements
- **Decoder track complete**: 1043 tests passing across tb_predecode.sv
  and tb_instr_decoder.sv; all RVA23 instructions covered
- **Pre-decode infrastructure**: predecode.sv as a standalone
  combinational module with clean interface to both upstream fetch
  and downstream decoder
- **Extension enable mechanism**: 18-bit ext_enable_t struct, static
  from CSR unit, with per-instruction granularity where the spec
  requires it
- **Coverage tooling integrated**: make coverage as a first-class
  build target with exit code semantics

### Key Metrics

| Experiment | New VOP_* | Tests | Run Time | Notes |
|---|---|---|---|---|
| DECODE-008 | 21 | 525 | 10m 49s | T29 documented failure resolved |
| DECODE-009 | 0 | 543 | 5m 26s | Debt closed, routing verified |
| DECODE-010 | n/a | 891 | 39m 14s + pause | New module, 2 testbenches |
| DECODE-011 | n/a | 1043 | 38m 55s + 8m 05s | 2 sessions |

### Interface Specifications (Downstream Impact)
1. **predecode_pkt_t[7:0]**: Now the input to instr_decoder; all
   upstream stages (fetch, ICache) must produce this type
2. **predecode_out**: Pass-through from instr_decoder; provides
   vtype_hazard to rename without rename re-examining raw instructions
3. **ext_enable_t**: Input to both predecode.sv and instr_decoder.sv;
   CSR unit drives from misa fields; all instantiating modules must
   connect this port
4. **is_illegal in decode_pkt_t**: Dispatch must raise a precise
   illegal-instruction exception for slots with this flag set
5. **LSU memory contracts**: Five distinct addressing modes with
   documented operand semantics for strided, indexed, mask, fault-only-
   first, and whole-register variants

## Technical Decisions Made

### Surgical Scalar FP Preservation
- **Chosen**: Outer if guard for vector detection within
  OP_LOAD_FP/OP_STORE_FP; scalar path byte-for-byte unchanged
- **Rationale**: The scalar FP decoder was already validated; modifying
  it to accommodate vector introduces regression risk with no benefit
- **Result**: FLD/FSD regressions pass unchanged; zero scalar FP defects
  introduced

### Combinational Pre-decode with Forward-Looking Ports
- **Chosen**: Purely combinational predecode.sv with clk/rstn ports
  present but unused
- **Rationale**: The combinational behavior is required for latency;
  the ports allow a pipeline register slice without interface disruption
- **Impact**: Upstream fetch integration has a stable interface target
  regardless of future pipeline depth decisions

### Static Extension Enable from CSR
- **Chosen**: ext_enable_t driven from misa as a static signal; no
  dependency enforcement in the decoder
- **Rationale**: Dependency enforcement (D requires F, Zcb requires C)
  is a software and driver responsibility. The decoder sees the current
  enable state and flags violations; it does not validate combinations.
- **Impact**: CSR unit is the single source of truth for extension state

### Coverage as a Gated Build Target
- **Chosen**: make coverage exits non-zero on MISSING, passes on ROUTED
- **Rationale**: ROUTED is a correct decoder behavior, not a gap. Treating
  it as a failure would produce permanent build noise.
- **Impact**: CI can gate on make coverage without false failures from
  intentional decode-level routing

## Lessons Learned

### Technical Insights
1. **Verification-first discipline pays off**: DECODE-009's 5m 26s runtime
   was possible only because DECODE-008 had already implemented correct
   stubs. The experiment found nothing to fix. That is a valid and
   valuable result — it means the prior experiment's scope decisions
   were correct.

2. **Sub-opcode granularity is real**: DECODE-011 demonstrated that
   simple opcode-level extension gating is insufficient for several
   RVA23 extensions. FLD vs FLW, prefetch hints, and CBO all required
   reading within the instruction before the enable check could be
   applied. The spec must be read before assuming granularity.

3. **Context size affects quality**: RTL comment quality degraded in
   DECODE-008 compared to earlier experiments. By DECODE-011 the
   decoder had accumulated enough state that two sessions were required.
   Managing context size — through targeted reads, tighter scope, and
   reduced file sizes — is an active part of prompt engineering for
   large RTL projects.

4. **Independent problem identification scales**: Across all four
   experiments Claude independently identified the indexed ordered
   memory ordering constraint (DECODE-008), the Verilator 5.020
   array write quirk (DECODE-010), and the prefetch hint detection
   pattern (DECODE-011). None of these were in the prompts. The
   read-before-write directive appears to be the enabling condition
   for this behavior.

### AI Co-Design Insights
1. **Context limits require operational planning**: Two experiments in
   this group hit context limits. The recovery procedure — pause, restart
   with prompt re-pasted — worked cleanly both times. The context
   isolation pattern was not designed with this in mind but proved
   resilient to it.

2. **Results attribution evolved**: DECODE-011 results sections were
   explicitly tagged as written by Claude Code or Claude.ai depending
   on source. This reflects growing awareness that different parts of
   the results come from different agents in the dual assistant
   architecture. The attribution helps in post-mortem review.

3. **Template updates as first-class output**: The methodology itself
   improved as a result of DECODE-011. Three additions to TEMPLATE.md
   came directly from patterns observed during decoder implementation.
   Treating the methodology as a living artifact — updated when evidence
   warrants — is a distinguishing feature of the approach.

4. **Scope discipline holds under pressure**: Even with context limits,
   usage pauses, and multi-session runs, no experiment attempted to
   implement deferred scope. The constraint was maintained consistently.

## Deferred Work

### DECODE-012 (Pending Fetch Unit Context)
Frontend pre-decode restructuring — the placement of rvc_expander.sv,
branch detection hooks, and fetch/decode boundary — is deferred until
the fetch unit interface is defined. The predecode.sv module established
by DECODE-010 provides a stable integration point; DECODE-012 will
restructure around it when fetch context is available.

### Per-Instruction Zbb/Zbs/Zfhmin/Zfa Gating
These extension enable bits are present in ext_enable_t but not yet
wired at per-instruction granularity. The instructions route to
functional units without fine-grained decode in the current
implementation. Per-instruction gating will be added when those
instructions are decoded explicitly in later pipeline stages.

### Downstream Integration Requirements
- **Rename**: Dual packet consumption, vtype dependency tracking via
  vtype_hazard, and OPMVX scalar GPR source handling
- **Dispatch**: ILLEGAL instruction exception raising; ext_enable_t
  carry-forward in interface specifications
- **LSU**: Five addressing mode contracts, fault-only-first vl writeback,
  segment nf expansion policy (TBD at vector execution unit design)
- **CSR Unit**: ext_enable_t driver from misa fields

## Conclusion

DECODE-008 through DECODE-011 closed the decoder track with 1043 tests
passing and complete RVA23 coverage. The four experiments cover distinct
territory: a clean encoding partition resolved without ambiguity,
a verification experiment that correctly found nothing to fix, an
architectural addition that established the pre-decode pipeline stage,
and a system-level mechanism that formalized the decoder's relationship
with the CSR unit.

The recurring theme is that the hardest problems were not the instruction
encodings — those resolved cleanly from rv_v. The harder problems were
interface decisions: what signals to pass through, what state to defer,
where to draw the boundary between decode and rename. Each of those
decisions was made deliberately and documented explicitly as a contract
for downstream stages.

The methodology also evolved during this phase. Context limits, results
attribution, and template updates all surfaced as operational concerns
that were managed and incorporated. The decoder track is the most
complete artifact to date for that evolution.

