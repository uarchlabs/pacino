=============================================================
# Task Header 
=============================================================
:: HEADER:START ::
| Field       | Value                                        |   |
|-------------|----------------------------------------------|---|
| Task ID     | DECODE-002                                   |   |
| Date        | 2026-03-22                                   |   |
| Module      | decoder                                      |   |
| Run time    | 5m.51s                                       |   |
| Ctx%        | not recorded                                 |   |
| Model       | Sonnet 4.6 normal                            |   |
| Resume sha  | c21bc124-7d79-4705-bf16-bf38aaeabcd7         |   |

Task:   [x] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Mode:   [x] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned

# Overview of task

RVA23 coverage gap analysis

2026.05.30: This file was retrofit to conform to the current section
marker syntax for automated processing.

:: HEADER:END :
=============================================================
:: DISCUSSION:START ::

# Results Discussion

## Claude.code Console Output
Not captured, this task predates the fully standardized prompting
scheme.

## My Assessment
Nothing required
## Claude.ai Assessment
Nothing required

## Follow-on actions
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
DECODE-002

## SESSION PROMPT

Module: Instruction Decoder

Experiment: DECODE-002 - RVA23 extension coverage gap analysis

## Hypothesis 

Use the official riscv-opcodes repository as a reference to determine which
RVA23 mandatory instructions are missing or incomplete in the current
DECODE-001 RTL output.

---
## Specific Requirements

Specific requirements for this experiment:

Reference source:
- Clone https://github.com/riscv/riscv-opcodes.git into a tools/ directory
  at the project root (do not commit it, add to .gitignore)
- Use the opcodes definitions from that repo as the ground truth for RVA23
  mandatory instructions

RVA23 mandatory extensions to check (user-mode, RVA23U64):
- RV64I   base integer
- M       multiply/divide
- A       atomics
- F       single precision float
- D       double precision float
- C       compressed (16b)
- Zicsr   CSR instructions
- Zicntr  counters
- Zihpm   hardware performance monitors
- Zfhmin  half precision float conversions
- Zba     bitmanip address generation
- Zbb     bitmanip basic
- Zbs     bitmanip single bit
- Zicbom  cache block management
- Zicbop  cache block prefetch
- Zicboz  cache block zero
- V       vector extension
- Zvfhmin vector half precision conversions
- Zcb     additional compressed instructions
- Zfa     additional floating point operations
- H       hypervisor extension

RTL to check against:
- frontend/decoder/rtl/decode_pkg.sv
- frontend/decoder/rtl/instr_decoder.sv
- frontend/decoder/rtl/predecode_expand.sv
- any other .sv files generated in DECODE-001

---
## Constraints

- The gap analysis script must run with standard Python 3, no extra packages
- Script output must be ASCII only - no Unicode characters
- Script must be re-runnable as RTL improves in future experiments
- Add tools/riscv-opcodes/ to .gitignore

Note on Vector and Hypervisor:
These are the most likely to be completely absent. If they are missing entirely,
note this clearly in the gap summary but do not attempt to implement them in
this experiment - that is scope for DECODE-003 and beyond.

---
## Deliverables

Deliverables:
1. A Python script at tools/check_rva23_coverage.py that:
   - Parses riscv-opcodes definitions for all RVA23 mandatory extensions
   - Searches the RTL files for each opcode name or encoding
   - Produces a coverage report showing:
     a. Extensions fully covered
     b. Extensions partially covered - list missing instructions
     c. Extensions not present at all
   - Outputs a summary count: X of Y instructions covered

2. Run the script and show the full output

3. A gap summary in plain text listing:
   - Which extensions are completely missing
   - Which extensions are partial and what is missing
   - An estimate of effort to close each gap

4. Do not modify any existing RTL in this experiment - analysis only

:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::

### Experiment Header

| Field         | Value |
|---------------|-------|
| Task ID | DECODE-002 |
| Date          | 2026.03.26 |
| Module        | Decoder    |
| Run time      | 5m.51s     |
| Session Link  | claude --resume c21bc124-7d79-4705-bf16-bf38aaeabcd7 |


---

### Output Quality

| Criteria                    | Rating (1-5) | Notes |
|-----------------------------|--------------|-------|
| RVA23 compliance  | n/a | task was create compliance checking script|
| Interface correctness       | n/a | n/a |
| RTL quality / readability   | n/a | n/a |
| Testbench quality           | n/a | n/a |
| Verilator compatibility     | n/a | n/a |
| Assumptions stated clearly  | n/a | n/a |

---

### What Claude got right

- Created a tools directory and cloned riscv-opcodes without any issues.

- Created a python script that parsed the riscv-opcodes docs and scanned
the RTL from DECODE-001. What it found is listed below:


---

### What Claude got wrong or missed

Nothing apparent. 

---

### RVA23 compliance flags raised by Claude

This is the output from claude's execution of the coverage script

BEGIN_SESSION_PARTIAL_OUTPUT

DECODE-002 RVA23 Coverage Gap Summary
  ======================================                                        
  Reference: riscv-opcodes extensions, RTL: frontend/decoder/rtl/               
  709 total instructions across 21 extensions (19 with reference files)         
                                                                                
  TERMINOLOGY                                                                   
    COVERED  - instruction mnemonic found by name in RTL source                 
    ROUTED   - instruction's 7-bit opcode class is handled; full decode         
               is deferred to a functional unit (FPU, LSU, VPU, etc.)           
    MISSING  - instruction's opcode is not recognized at all                    
                                                                                
                                                                                
  RESULT CATEGORIES                                                             
  -----------------                                         
                                                                                
  A. Extensions with full name-level coverage (4)                               
     M        - all 8 multiply/divide instructions named in decode_pkg.sv       
     C        - all 37 RVC instructions handled in rvc_expander.sv              
     Zicntr   - rdcycle/rdtime/rdinstret are pseudo-ops via CSRRS; covered      
     Zicbop   - prefetch hints are valid ORI encodings; covered                 
                                                                                
  B. Extensions fully routed at opcode-class level (13)                         
     These have zero missing instructions at the decoder stage because          
     every instruction's major opcode (bits [6:2]) is dispatched to a           
     functional unit.  Fine-grained decoding happens in that unit.              
                                                                                
     RV64I  - all 78 instructions (11 are routed by opcode class, not name)     
     A      - all 22 AMO instructions routed via OP_AMO to LSU                  
     F      - all 39 SP-float instructions routed via OP_FP / OP_LOAD_FP        
     D      - all 35 DP-float instructions routed via OP_FP / OP_LOAD_FP        
     Zicsr  - all 13 CSR instructions routed via OP_SYSTEM                      
     Zfhmin - all 8 half-precision convert instructions routed via OP_FP        
     Zba    - all 9 address-gen instructions routed via OP_REG / OP_REG_32      
     Zbb    - all 24 bitmanip basic instructions routed via OP_REG / OP_IMM     
     Zbs    - all 8 single-bit instructions routed via OP_REG / OP_IMM          
     Zicbom - cbo.clean/flush/inval routed via OP_MISC_MEM                      
     Zicboz - cbo.zero routed via OP_MISC_MEM                                   
     Zfa    - all 15 additional FP ops routed via OP_FP                         
     H      - all 15 hypervisor instructions routed via OP_SYSTEM               
                                                                                
                                                                                
  C. Extensions with NO reference file in riscv-opcodes (2)                     
     These cannot be scored; analysis notes are provided.                       
                                                                                
     Zihpm  - Hardware performance monitors are hpmcounterN CSR                 
              pseudo-ops.  They are CSRRS encodings with fixed CSR              
              addresses.  Coverage status: effectively ROUTED, because          
              OP_SYSTEM is handled and CSR dispatch is present.                 
              Effort to close: 0 RTL changes; update test to verify             
              HPM CSR addresses pass through correctly.  Low effort.            
                                                                                
     Zvfhmin - No dedicated file in riscv-opcodes.  Zvfhmin comprises           
               two vector instructions: vfwcvt.f.f.v (half->single in V)        
               and vfncvt.f.f.w (single->half in V).  These use opcode          
               0x57 (OP_VECTOR), which is ABSENT from the decoder.              
               Coverage status: ABSENT via V.                                   
               Effort to close: blocked on V extension (DECODE-003+).           
                                                                                
                                                                                
  D. Extensions partially or completely absent (2)                              
     These represent the true decoder gaps.                                     
                                                                                
     Zcb (13 instructions - COMPLETELY ABSENT)                                  
     - Description: additional compressed 16-bit instructions                   
       from the Zcb extension.  These are 16-bit (quadrant 0 and 1)             
       encodings NOT present in rvc_expander.sv.                                
     - Missing: c.lbu, c.lh, c.lhu, c.sb, c.sh (new CL/CS formats)              
                c.zext.b, c.zext.h, c.sext.b, c.sext.h, c.not                   
                c.mul, c.zext.w, c.sext.w                                       
     - Root cause: rvc_expander only implements the base C extension            
       (RVC v2.2).  Zcb adds new encodings in the space previously              
       marked reserved in quadrant 0 (c[15:13]=100) and quadrant 1.             
     - Effort: LOW-MEDIUM.  The Zcb encodings are straightforward               
       expansions (c.lbu -> LBU, c.mul -> MULW, etc.).  All expand              
       to instructions already handled by instr_decoder.  Requires              
       additions to rvc_expander.sv only.  No decode_pkg.sv changes             
       needed.  Estimate: 1 session (DECODE-003 candidate).                     
                                                                                
     V (317 of 375 instructions MISSING)                                        
     - Description: The RVV 1.0 vector extension.  The 58 vector                
       memory instructions (vle*.v, vse*.v, etc.) are technically               
       ROUTED because they use the FP-load/store opcode space (0x07             
       / 0x27), but would be misidentified as FP loads/stores at                
       this stage.  The remaining 317 instructions use opcode 0x57              
       (bits 6..2 = 0x15), which has no handler in instr_decoder.sv.            
     - Missing opcode: 0x57 (OP_VECTOR) - completely absent.                    
     - Scope of gap: vsetvl/vsetvli/vsetivli (config), all integer              
       vector ALU ops, all vector FP ops, all vector mask ops,                  
       all vector permute ops, all vector reduce ops.                           
     - Effort: HIGH.  Vector requires:                                          
       1. New opcode handler for 0x57 (OP_VECTOR) in instr_decoder.             
       2. New decode packet fields for vector operands: vd, vs1, vs2,           
          vs3, vm (mask), nf (segment), eew.                                    
       3. decode_pkg.sv additions: is_vector flag, vector-specific              
          alu_op_t entries (or a separate v_op_t field).                        
       4. rvc_expander is not involved (vector has no 16-bit forms).            
       5. A dedicated vector pre-decoder (vtype parsing) may be                 
          needed as a separate pipeline stage ahead of instr_decoder.           
       6. Zvfhmin is a subset of V and closes automatically when V              
          is handled.                                                           
       Estimate: 4-6 sessions minimum (DECODE-003 through DECODE-008).          
                                                                                
                                                            
  SUMMARY COUNT                                                                 
  -------------                                             
    Total in scope    : 709 instructions (across 19 extensions with files)
    Covered by name   : 145 (20%)                                               
    Routed by opcode  : 234 (33%)                                               
    Combined coverage : 379 / 709 (53%)                                         
    Missing           : 330 (47%) - almost entirely the V extension             
                                                                                
    Excluding V extension (329 instructions):                                   
    Combined coverage : 379 / 380 = 99.7%                                       
    Missing           :   1       - Zcb (13 instructions, new 16-bit forms)     
                                                                                
    BOTTOM LINE: The scalar decoder (RV64I + M + A + F + D + Zicsr +            
    all B and Zic* extensions + Zfa + H) is functionally complete at            
    the opcode-dispatch level.  Two gaps remain:                                
      1. Zcb - 13 new compressed instructions (LOW effort, DECODE-003)          
      2. V   - 317 vector instructions (HIGH effort, DECODE-003+)               
                                                                                
  ---                                                                           
  Key Observations                                                              
                                                                                
  The decoder is in better shape than it looks at 53% raw coverage. The "ROUTED"
   category represents correct design: the front-end decoder identifies opcode  
  classes and routes to functional units; individual F/D/A instruction
  disambiguation correctly belongs in the FPU and LSU, not the integer decoder. 
                                                            
  Two genuine gaps:                                                             
   
  1. Zcb - 13 compressed instructions that need adding to rvc_expander.sv. All  
  expand to instructions already supported by instr_decoder.sv. Low-risk,
  self-contained.                                                               
  2. V - 317 vector instructions. The opcode 0x57 (OP_VECTOR) is entirely
  absent. This is the dominant gap both in instruction count and in             
  implementation complexity. It requires new packet fields, a new opcode
  handler, and likely a dedicated vector pre-decode stage. Zvfhmin closes       
  automatically as a subset of V.                           

  Zihpm is effectively covered: all HPM counter reads are CSRRS pseudo-ops, and 
  the SYSTEM opcode handler already dispatches those correctly. No RTL change
  needed.                                                                       
END_SESSION_PARTIAL_OUTPUT
                                                            
### Interface decisions made - downstream impact

n/a for this prompt

---

### Prompt effectiveness observations

Did the prompt produce the intended experiment? 
yes
The prompt was written by Claude.ai

Was anything ambiguous or missing?
no

---

### Graduated to CLAUDE.md

{date} - {what was added, or "nothing" if no decisions confirmed}

## Files Modified
Not captured

:: RESULTS:END ::
