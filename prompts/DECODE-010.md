=============================================================
# Task Header
=============================================================
:: HEADER:START ::
| Field       | Value                                        |   |
|-------------|----------------------------------------------|---|
| Task ID     | DECODE-010                                   |   |
| Date        | 2026-03-23                                   |   |
| Module      | decoder                                      |   |
| Run time    | 39m.14s    | |
| Ctx%        | not recorded                                 |   |
| Model       | Sonnet 4.6 normal                            |   |
| Resume sha  | 102ea1cc-21d4-4d38-971f-bd5f4fd253fd | |
| PA session  | 001 | |

Task:   [x] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Mode:   [x] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview
Vector pre-decode module (vtype annotation)

2026-05-30: This task file has been retro-fitted with the 
now standard section markers.
:: HEADER:END :
=============================================================
:: DISCUSSION:START ::

# Results Discussion

## Claude.code Console Output

  Deliverables completed

  1. decode_pkg.sv — predecode_pkt_t struct added before vec_decode_pkt_t:
  - valid, instr[31:0], is_vsetvl, needs_vtype, vtype_hazard, may_be_branch

  2. predecode.sv — new purely combinational module:
  - 8 slots decoded in parallel via unrolled continuous assigns
  - Prefix-OR chain computes w_prior_vsetvl[i] for intra-bundle hazard detection
  - clk/rstn ports present for pipeline interface consistency, unused internally
  - UNOPTFLAT suppressed at declaration site with explanation

(continued in the RESULTS CAPTURE section)

## My Assessment
Nothing required
## Claude.ai Assessment

### What Claude got right

- Prefix-OR chain for vtype_hazard computed correctly in parallel
  across all 8 slots -- no loops, purely combinational.
- clk/rstn ports present for pipeline consistency even though
  unused -- correct forward-looking interface decision.
- UNOPTFLAT suppression documented at declaration site with
  explanation -- good practice.
- Verilator 5.020 variable-indexed array write quirk identified
  and worked around independently -- not in the prompt.
- 543 existing tests pass unchanged -- interface migration clean.
- may_be_branch false positive cases documented explicitly.

- isolated a quirk of Verilator, without additional prompts
  see docs/observations/verilator_5020_notes.md

---

### What Claude got wrong or missed

- Nothing significant. The Verilator quirk workaround was found
  and resolved without prompting. All deliverables complete.

## Follow-on Actions
- [ ] {e.g. retry with different constraint}
- [ ] {e.g. carry interface decision forward to next module}
- [ ] {e.g. update CLAUDE.md with confirmed decision}
- [ ] {e.g. update README.md status table}
## CLAUDE.md Updates
Nothing required
## Other Planning File Updates
Nothing required
:: DISCUSSION:END ::
=============================================================
# Claude.code Prompt
=============================================================
:: PROMPT:START ::

## Task ID
DECODE-010

## Hypothesis
A dedicated pre-decode module sitting between fetch and decode can
identify vsetvl/vsetvli/vsetivli instructions in the fetch bundle
and annotate each slot with vtype dependency information before the
main decoder runs. This keeps the main decoder stateless and provides
a clean interface for rename to track vtype as a producer/consumer
dependency.

## Background
The CLAUDE.md baseline states:
- vtype dependency policy for intra-bundle vsetvl is TBD
- Decoder marks is_vsetvl and needs_vtype in vec_decode_pkt_t
- Rename resolves the dependency

This experiment implements the pre-decode stage that makes that
policy concrete. The module is additive -- it does not restructure
the existing decoder or testbench. Frontend pre-decode restructuring
(branch detection, RVC expansion placement, fetch alignment) is
deferred to DECODE-011.

Design reference: XiangShan handles vtype tracking in a dedicated
unit alongside rename. BOOM pre-decode identifies branches early
for latency reduction. This module follows the same principle --
identify vtype-affecting instructions early, annotate the bundle,
keep downstream stages stateless.

---

## Specific Requirements

Step 1 - Read before writing (targeted):
- Read decode_pkg.sv: vec_decode_pkt_t struct and is_vsetvl,
  needs_vtype fields only
- Read instr_decoder.sv: module interface only (inputs/outputs)
- Do not read function bodies -- not needed for this experiment

Step 2 - Define pre-decode packet in decode_pkg.sv:
Add a new struct predecode_pkt_t alongside existing structs:

  typedef struct packed {
    // instruction validity
    logic        valid;          // slot contains a valid instruction

    // raw instruction (post RVC expansion if present, else raw)
    logic [31:0] instr;          // instruction bits passed to decoder

    // vtype annotation fields
    logic        is_vsetvl;      // slot is vsetvl/vsetvli/vsetivli
    logic        needs_vtype;    // slot consumes current vtype
    logic        vtype_hazard;   // vsetvl precedes a needs_vtype
                                 // in the same bundle -- intra-bundle
                                 // dependency detected

    // early branch hint (placeholder for DECODE-011)
    logic        may_be_branch;  // conservative early branch detect
                                 // set if opcode is JAL/JALR/BRANCH
                                 // full resolution deferred to decode

  } predecode_pkt_t;

Notes:
- vtype_hazard is set on any slot where a prior slot in the same
  bundle has is_vsetvl=1 AND this slot has needs_vtype=1
- vtype_hazard is informational for rename -- policy is still TBD
  but the signal is now available
- may_be_branch is a conservative hint only -- set for opcodes
  JAL (1101111), JALR (1100111), BRANCH (1100011)
  Full branch decode remains in instr_decoder.sv
- predecode_pkt_t carries the raw instruction through to the
  decoder -- decoder input changes from raw bits to
  predecode_pkt_t[7:0]

Step 3 - Create new module frontend/decoder/rtl/predecode.sv:

  Module interface:
    input  logic                clk
    input  logic                rst_n
    input  logic [7:0][31:0]    fetch_bundle    // raw instructions
    input  logic [7:0]          fetch_valid     // valid slots
    output predecode_pkt_t [7:0] predecode_bundle // annotated bundle

  Module behavior:
  - Purely combinational -- no registered state
  - For each slot i in parallel:
    1. Set valid from fetch_valid[i]
    2. Pass instr through from fetch_bundle[i]
    3. Detect is_vsetvl: opcode=1010111 AND funct3=3'b111
    4. Detect needs_vtype: opcode=1010111 AND funct3!=3'b111
       OR opcode=0000111 with vector width (eew check)
       OR opcode=0100111 with vector width (eew check)
    5. Set may_be_branch: opcode is JAL/JALR/BRANCH
    6. Compute vtype_hazard:
       vtype_hazard[i] = needs_vtype[i] AND
       OR_REDUCE(is_vsetvl[i-1:0] AND fetch_valid[i-1:0])
       -- any earlier valid slot in this bundle is a vsetvl

  All 8 slots must be processed in parallel -- no loops

Step 4 - Update instr_decoder.sv interface:
- Change input from logic [7:0][31:0] fetch_bundle to
  predecode_pkt_t [7:0] predecode_bundle
- Extract instr bits from predecode_bundle[i].instr internally
- All existing decode logic unchanged
- Add predecode_bundle as pass-through to output alongside
  decode_bundle and vec_decode_bundle
- Add a comment: predecode_pkt_t.vtype_hazard is available to
  rename via this output -- policy TBD per CLAUDE.md

Step 5 - Create new testbench
frontend/decoder/tb/tb_predecode.sv:
- Independent testbench for predecode.sv only
- Test cases must cover:
  - All 8 slots valid, no vector instructions -- all flags clear
  - Single vsetvli in slot 0 -- is_vsetvl[0]=1, all others clear
  - Single vadd.vv in slot 0 -- needs_vtype[0]=1
  - vsetvli in slot 0, vadd.vv in slot 1 -- vtype_hazard[1]=1
  - vsetvli in slot 3, vadd.vv in slot 4 -- vtype_hazard[4]=1,
    slots 0-3 no hazard
  - Two vsetvli in slots 0 and 2 -- is_vsetvl[0,2]=1
  - vsetvli in slot 7 (last slot) -- no hazard possible after it
  - Mixed scalar and vector instructions -- hazard only on vector
  - JAL in slot 2 -- may_be_branch[2]=1 only
  - BRANCH in slot 5 -- may_be_branch[5]=1 only
  - Vector load (vle32.v) -- needs_vtype[i]=1
  - Vector store after vsetvli -- vtype_hazard set correctly
  - All slots invalid -- all flags clear
- All tests must be self-checking

Step 6 - Update existing tb_instr_decoder.sv:
- Change input driving to use predecode_pkt_t instead of raw bits
- Add a helper function make_predecode_pkt() that wraps a raw
  instruction into a predecode_pkt_t with is_vsetvl/needs_vtype
  set correctly for that instruction
- All 543 existing tests must continue to pass unchanged
- Do not add new decoder tests in this experiment

Step 7 - Update Makefile:
- Add tb_predecode target alongside existing targets:
    make lint_predecode  -- lint predecode.sv only
    make sim_predecode   -- build and run tb_predecode
    make sim_all         -- run both tb_predecode and tb_instr_decoder
- Existing make lint and make sim targets must continue to work

Step 8 - Verilator lint and simulation must be clean for both
testbenches.
- Maximum 80 column line width strictly enforced.

Step 9 - Run tools/check_rva23_coverage.py and confirm:
- No regressions in any extension

---

## Constraints
- predecode.sv must be purely combinational -- no registered state
- All 8 slots processed in parallel -- no loops or sequential logic
- Do not restructure rvc_expander.sv or move RVC expansion --
  deferred to DECODE-011
- Do not add branch prediction logic -- may_be_branch is a hint
  only, full branch decode stays in instr_decoder.sv
- Do not modify any existing RTL except instr_decoder.sv interface
- 543 existing tests must pass unchanged
- Maximum 80 column line width strictly enforced

---

## Deliverables
1. Updated decode_pkg.sv with predecode_pkt_t struct
2. New frontend/decoder/rtl/predecode.sv module
3. Updated frontend/decoder/rtl/instr_decoder.sv interface
4. New frontend/decoder/tb/tb_predecode.sv testbench
5. Updated frontend/decoder/tb/tb_instr_decoder.sv with
   predecode_pkt_t input wrapper
6. Updated Makefile with new targets
7. Clean Verilator lint and simulation for both testbenches
8. Coverage script output confirming no regressions
9. Explicit statement of intra-bundle vtype hazard policy --
   confirm vtype_hazard signal is available but policy remains
   TBD at rename per CLAUDE.md
10. Note any cases where may_be_branch conservative detection
    produces false positives -- these are expected and acceptable

:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::

### Claude Text Output

  ---
  DECODE-010 Results

  Deliverables completed

  1. decode_pkg.sv — predecode_pkt_t struct added before vec_decode_pkt_t:
  - valid, instr[31:0], is_vsetvl, needs_vtype, vtype_hazard, may_be_branch

  2. predecode.sv — new purely combinational module:
  - 8 slots decoded in parallel via unrolled continuous assigns
  - Prefix-OR chain computes w_prior_vsetvl[i] for intra-bundle hazard detection
  - clk/rstn ports present for pipeline interface consistency, unused internally
  - UNOPTFLAT suppressed at declaration site with explanation

  3. instr_decoder.sv — interface updated:
  - exp_bundle/exp_valid replaced by predecode_pkt_t [SLOTS-1:0]
  predecode_bundle
  - predecode_out pass-through output added for rename
  - Comment states: predecode_pkt_t.vtype_hazard is available to rename via
  predecode_out -- policy TBD per CLAUDE.md
  - All existing decode logic unchanged

  4. tb_predecode.sv — 13 test cases + JALR variant, 348 checks, all PASS

  5. tb_instr_decoder.sv — updated with make_predecode_pkt() helper, drive()
  uses predecode_pkt_t; 543 tests PASS unchanged

  6. Makefile — lint_predecode, sim_predecode, sim_all targets added

  7. Verilator lint and simulation — clean for both testbenches

  8. Coverage script — no regressions, 0 missing instructions

  ---
  Implementation note (Verilator quirk)

  Variable-indexed array writes inside tasks (fetch_valid[slot] = 1'b1 where
  slot is an int) do not trigger re-evaluation of dependent assign statements in
   Verilator 5.020. The drive() task in tb_predecode.sv uses an explicit case
  statement to avoid this — all 8 slots are addressed with compile-time-constant
   indices.

  ---
  Intra-bundle vtype hazard policy statement (Deliverable 9)

  vtype_hazard is available but policy is TBD. The signal is set on any slot
  where a prior valid slot in the same bundle is a vsetvl/vsetvli/vsetivli AND
  this slot consumes vtype. It is passed through predecode_out from
  instr_decoder so rename can read it. The actual scheduling policy (stall,
  rename insertion, forwarding) is deferred to the rename/dispatch stage per
  CLAUDE.md.

  ---
  may_be_branch false positives (Deliverable 10)

  Expected false positives (benign, documented in predecode.sv comments):
  1. JALR with funct3 != 3'b000 — technically illegal per RVA23 but opcode check
   is conservative; instr_decoder will mark is_illegal=1
  2. Any reserved/custom encoding that happens to use opcode 1101111, 1100111,
  or 1100011 will set may_be_branch=1

  No false negatives exist for standard JAL/JALR/BRANCH instructions.


### Experiment Header

| Field          | Value |
|----------------|-------|
| Task ID  | DECODE-010 |
| Date           | 2026.03.23 |
| Module         | decoder    |
| Run time       | 39m.14s    |
| Session Link   | claude --resume 102ea1cc-21d4-4d38-971f-bd5f4fd253fd |

---

### Output Quality

| Criteria                    | Rating (1-5) | Notes |
|-----------------------------|--------------|-------|
| RVA23 compliance            | 5   | |
| Interface correctness       | n/a | |
| RTL quality / readability   | 4   | same formatting thing |
| Testbench quality           | 5   | |
| Verilator compatibility     | 5   | excellent self prompted fixes for verilator behavior |
| Assumptions stated clearly  | 5   | |

---

### What Claude got right

- Prefix-OR chain for vtype_hazard computed correctly in parallel
  across all 8 slots -- no loops, purely combinational.
- clk/rstn ports present for pipeline consistency even though
  unused -- correct forward-looking interface decision.
- UNOPTFLAT suppression documented at declaration site with
  explanation -- good practice.
- Verilator 5.020 variable-indexed array write quirk identified
  and worked around independently -- not in the prompt.
- 543 existing tests pass unchanged -- interface migration clean.
- may_be_branch false positive cases documented explicitly.

- isolated a quirk of Verilator, without additional prompts
  see docs/observations/verilator_5020_notes.md

---

### What Claude got wrong or missed

- Nothing significant. The Verilator quirk workaround was found
  and resolved without prompting. All deliverables complete.

---

### RVA23 compliance flags raised by Claude

- vtype_hazard signal available to rename via predecode_out.
  Intra-bundle vtype dependency policy remains TBD per CLAUDE.md.
  To be resolved at rename/dispatch stage.
- may_be_branch conservative detection produces expected false
  positives for illegal JALR encodings and reserved opcodes.
  No false negatives for standard control flow instructions.

---

### Interface decisions made - downstream impact

- predecode_pkt_t [7:0] is now the input to instr_decoder.
  All upstream stages (fetch, ICache) must produce this type.
- predecode_out pass-through from instr_decoder provides
  vtype_hazard to rename without rename needing to re-examine
  raw instructions.
- clk/rstn on predecode.sv: unused now but pipeline register
  slice can be inserted without interface change.

---

### Prompt effectiveness observations

Did the prompt produce the intended experiment? 
yes. Prompt written by Claude.ai

Was anything ambiguous or missing?
not

Hit usage limits. wait 2.5hr. Exited, restarted after timeout.

---

### Follow-on actions

- [ ] {e.g. retry with different constraint}
- [ ] {e.g. carry interface decision forward to next module}
- [ ] {e.g. update CLAUDE.md with confirmed decision}
- [ ] {e.g. update README.md status table}

---

### Graduated to CLAUDE.md

{date} - {what was added, or "nothing" if no decisions confirmed}

## Files Modified
Not captured

:: RESULTS:END ::
