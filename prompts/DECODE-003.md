=============================================================
# Task Header
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | DECODE-003              |                          |
| Date         | 2026.03.22              |                          |
| Module       | rvc_expander.sv         |                          |
| Run time     | ??????                  |                          |
| Run time     | 12m.56s                 |                          |
| Ctx %        | ??????                  |                          |
| Model        | Sonnet 4.6 medium       |                          |
| Resume sha   | 69f41938-8393-4172-920e-060d99af94d5 |             |
| PA session  | 001 | |

Task:   [ ] experiment  [x] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [x] verification
Mode:   [x] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview
DECODE-003 - Add Zcb

2026.05.30: Zcb support was missing from the rvc expander implementation.
This task rectifies the missing 13 instructions. This file was also 
retrofit for section markers.

:: HEADER:END ::
=============================================================
:: DISCUSSION:START ::

# Results Discussion

## Claude.code Console Output
Nothing captured
## My Assessment
Nothing required
## Claude.ai Assessment
Nothing required

### Follow-on actions
- [ ] Update check_rva23_coverage.py to handle shared encodings
      e.g. c.sext.w / C.ADDIW shared path reports as missing
      fix: add known-shared encoding exceptions table to script

- [ ] update README.md status table

## Other Planning File Updates
Nothing required
## CLAUDE.md Updates
Minor: no tabs

:: DISCUSSION:END ::
=============================================================
# Claude.code Prompt
=============================================================
:: PROMPT:START ::

## Task ID
DECODE-003

## Context Loaded
Nothing explicitly supplied

## Hypothesis
Module: Instruction Decoder

Experiment: DECODE-003 - Add Zcb compressed instructions to rvc_expander.sv

The 13 missing Zcb instructions identified in DECODE-002 can be added to
rvc_expander.sv without changes to any other RTL file. After this experiment
the scalar decoder should be 100% complete at the opcode-dispatch level.

## Background

DECODE-002 gap analysis identified the following as the only missing scalar
instructions. All 13 are Zcb extension encodings that belong in rvc_expander.sv.
All expand to instructions already handled by instr_decoder.sv.

Missing instructions:
  New load/store (CL/CS formats):
    c.lbu   -> LBU
    c.lh    -> LH
    c.lhu   -> LHU
    c.sb    -> SB
    c.sh    -> SH

  New integer ops (CB format):
    c.zext.b  -> ANDI rd, rd, 0xFF
    c.zext.h  -> zero-extend lower 16b (custom expand)
    c.sext.b  -> sign-extend byte
    c.sext.h  -> sign-extend halfword
    c.not     -> XORI rd, rd, -1
    c.mul     -> MULW
    c.zext.w  -> zero-extend lower 32b
    c.sext.w  -> ADDIW rd, rd, 0  (already in C, verify present)

Reference:
  Zcb encodings are in tools/riscv-opcodes/extensions/rv_zcb
  Verify each encoding against that file before implementing.

---
## Specific Requirements

1. Read tools/riscv-opcodes/extensions/rv_zcb before writing any RTL
   to confirm exact encodings. Do not rely on memory of the spec.

2. Modify frontend/decoder/rtl/rvc_expander.sv only.
   Do not modify any other RTL file.

3. For each new instruction:
   - Add the bit-pattern match for the 16b encoding
   - Expand to the correct 32b canonical form
   - Add a comment with the Zcb mnemonic and source encoding in ASCII

4. Update the testbench frontend/decoder/tb/tb_instr_decoder.sv or
   frontend/decoder/tb/tb_predecode_expand.sv to add at least one
   directed test per new Zcb instruction.

5. After RTL changes, re-run tools/check_rva23_coverage.py and confirm:
   - Zcb shows as fully covered
   - No regressions in any previously covered extension
   - Coverage moves from 99.7% to 100% excluding Vector

6. Run Verilator lint and simulation - must be clean before experiment
   is considered complete.

---
## Constraints
- ASCII only in all comments - no Unicode characters
- Changes confined to rvc_expander.sv and testbench files only
- decode_pkg.sv must not be modified
- instr_decoder.sv must not be modified
- All 8 expansion slots must handle new Zcb encodings in parallel -
  no special casing for Zcb vs base C

---
## Deliverables

Deliverables:
1. Updated rvc_expander.sv with all 13 Zcb instructions
2. Updated testbench with directed tests for each new instruction
3. Clean Verilator lint and simulation output
4. Re-run of tools/check_rva23_coverage.py showing Zcb fully covered
5. Note any encoding edge cases or ambiguities found in rv_zcb spec
6. Confirm scalar decoder is complete - state this explicitly in summary

---

Note on sext.w:
c.sext.w may already be present in rvc_expander.sv as part of the base
C extension. Verify before adding - do not duplicate.

:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::

### Tool Text Output

  ---            
  DECODE-003 Results                                                            
                                                                                
  RTL changes — rvc_expander.sv only
                                                                                
  Quadrant 0 funct3=4 (previously reserved): Added full Zcb load/store dispatch:
  - c.lbu → LBU (I-type, funct3=100, uimm[1]=c[5], uimm[0]=c[6])                
  - c.lhu → LHU (c[6]=0, uimm={c[5],0})                                         
  - c.lh  → LH  (c[6]=1, uimm={c[5],0})                     
  - c.sb  → SB  (S-type, uimm[1]=c[5], uimm[0]=c[6])                            
  - c.sh  → SH  (c[6]=0, uimm={c[5],0})                                         
                                                                                
  Quadrant 1 Misc-ALU c[12:10]=111 (c[12]=1) branch extended:                   
  - c.mul    → MULW rd', rd', rs2' (M, funct7=0000001, op32)                    
  - c.zext.b → ANDI rd', rd', 0xFF                                              
  - c.sext.b → SEXT.B (Zbb, funct12=0x604)                                      
  - c.zext.h → ZEXT.H (Zbb/RV64, op32, funct7=0000100, rs2=x0, funct3=100)      
  - c.sext.h → SEXT.H (Zbb, funct12=0x605)                                      
  - c.zext.w → ADD.UW rd', rd', x0 (Zba, op32, funct7=0000100, funct3=000)      
  - c.not    → XORI rd', rd', -1                                                
                                                                                
  Encoding edge cases / discrepancies found in rv_zcb                           
                                                                                
  1. c.zext.w not in tools file. The tools/riscv-opcodes/extensions/rv_zcb file 
  contains only 11 entries (c.lbu through c.mul). c.zext.w (4..2=4, between     
  c.sext.h and c.not) is absent. It is present in the published RISC-V Zcb spec 
  and implemented here per spec (ADD.UW rd', rd', x0).      
  2. c.sext.w not in tools file and already handled. c.sext.w is not in rv_zcb
  because it is the same 16-bit encoding as C.ADDIW with rd≠0 and imm=0. The    
  existing base-C path in Q1/3'b001 already expands this to ADDIW rd, rd, 0. T29
   verifies this.                                                               
                                                            
  Coverage tool note                                                            
   
  check_rva23_coverage.py reports Zcb as 12/13 with c.sext.w listed as missing. 
  This is a tool limitation: it does string matching against the RTL source, and
   there is no sext.w label because the encoding is shared with C.ADDIW. The    
  instruction IS correctly handled.                         

  Simulation results                                                            
   
  ┌──────────────────────────┬───────┬──────┬──────┐                            
  │           Run            │ Tests │ Pass │ Fail │        
  ├──────────────────────────┼───────┼──────┼──────┤                            
  │ rvc_expander (T1–T29)    │ 43    │ 43   │ 0    │        
  ├──────────────────────────┼───────┼──────┼──────┤
  │ instr_decoder regression │ 229   │ 229  │ 0    │                            
  └──────────────────────────┴───────┴──────┴──────┘                            
                                                                                
  Verilator lint: clean. Verilator simulation: clean.                           
                                                            
  Scalar decoder status                                                         
                                                            
  The scalar (non-vector) decoder is complete at the opcode-dispatch level. All 
  mandatory RVA23 scalar instructions are either fully decoded or routed to
  their execution unit. The only remaining missing instructions are the 317     
  Vector (V) extension instructions, which are explicitly out of scope for this
  experiment.


### Experiment Header

| Field          | Value |
|----------------|-------|
| Experiment ID  | DECODE-003 |
| Date           | 2026.03.22 |
| Module         | decoder    |
| Run time       | 12m.56s    |
| Session Link   | claude --resume 69f41938-8393-4172-920e-060d99af94d5 |

---

### Output Quality

| Criteria                    | Rating (1-5) | Notes |
|-----------------------------|--------------|-------|
| RVA23 compliance            | 5   | incremental added ZCB |
| Interface correctness       | n/a | |
| RTL quality / readability   | 5   | CLAUDE.md should specify 2 spaces for indent not 4, will fix later |
| Testbench quality           | 5   | |
| Verilator compatibility     | 5   | |
| Assumptions stated clearly  | 5   | |

---

### What Claude got right

It correctly patched the missing opcodes, modified the RTL and testbench.
One caveat, see below

---

### What Claude got wrong or missed

These are not exactly 'wrong' 
  c.sext.w reports missing because there is no label in the RTL
  Instruction is correctly handled via shared C.ADDIW encoding
  c.zext.w absent from rv_zcb tools file but implemented per published spec

---

### RVA23 compliance flags raised by Claude

None.

---

### Interface decisions made - downstream impact

n/a

---

### Prompt effectiveness observations

Did the prompt produce the intended experiment?
 yes. The prompt was written by Claude.ai

Was anything ambiguous or missing?
 zcb coverage needs a follow on

---


## Files Modified
Not captured

:: RESULTS:END ::

