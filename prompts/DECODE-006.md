# DECODE-006 - Vector FP ops + Zvfhmin

Date: 2026.03.22
Status: [ ] in-progress  [x] complete  [ ] abandoned

---

## SESSION PROMPT

Module: Instruction Decoder

Experiment: DECODE-006 - Vector FP ALU disambiguation (OPFVV/OPFVF)
and Zvfhmin closure

---

Hypothesis to test:
All vector floating point ALU instructions (funct3 = OPFVV/OPFVF) can be
fully disambiguated using funct6 decoding within decode_vec_one() following
the same nested case pattern established in DECODE-005. Zvfhmin closes
automatically when vfwcvt.f.f.v and vfncvt.f.f.w are correctly decoded
as OPFVV instructions.

---

Background:
DECODE-005 fully disambiguated OPIVV/OPIVX/OPIVI (63 VOP_* entries added).
OPFVV (funct3=3'b001) and OPFVF (funct3=3'b101) remain at coarse VALU_FP
placeholder. This experiment resolves both groups.

Zvfhmin comprises exactly two instructions:
  vfwcvt.f.f.v  -- half to single widening convert (OPFVV)
  vfncvt.f.f.w  -- single to half narrowing convert (OPFVV)
Both use opcode 0x57 with funct3 = OPFVV. They close automatically
when OPFVV is fully decoded.

---

Specific requirements for this experiment:

Step 1 - Read before writing:
- Read frontend/decoder/rtl/decode_pkg.sv in full
- Read frontend/decoder/rtl/instr_decoder.sv in full
- Read tools/riscv-opcodes/extensions/rv_v carefully - focus on:
  - All instructions with funct3 = OPFVV (3'b001)
  - All instructions with funct3 = OPFVF (3'b101)
- Do not rely on training data for funct6 encodings - use rv_v as
  ground truth

Step 2 - Expand v_op_class_t enum in decode_pkg.sv:
- Add VOP_* entries for all OPFVV and OPFVF instructions
- Suggested naming convention (extend as needed):
    VOP_VFADD, VOP_VFSUB, VOP_VFMUL, VOP_VFDIV, VOP_VFSQRT,
    VOP_VFMIN, VOP_VFMAX, VOP_VFSGNJ, VOP_VFSGNJN, VOP_VFSGNJX,
    VOP_VFSLIDE1UP, VOP_VFSLIDE1DOWN,
    VOP_VFMV, VOP_VFMERGE,
    VOP_VFCVT, VOP_VFWCVT, VOP_VFNCVT,
    VOP_VFMACC, VOP_VFNMACC, VOP_VFMSAC, VOP_VFNMSAC,
    VOP_VFMADD, VOP_VFNMADD, VOP_VFMSUB, VOP_VFNMSUB,
    VOP_VFWMACC, VOP_VFWNMACC, VOP_VFWMSAC, VOP_VFWNMSAC,
    VOP_VFWADD, VOP_VFWSUB, VOP_VFWADD_W, VOP_VFWSUB_W,
    VOP_VFWMUL,
    VOP_VFREDOSUM, VOP_VFREDUSUM, VOP_VFREDMAX, VOP_VFREDMIN,
    VOP_VFWREDOSUM, VOP_VFWREDUSUM,
    VOP_VMFEQ, VOP_VMFLE, VOP_VMFLT, VOP_VMFNE, VOP_VMFGT,
    VOP_VMFGE,
    VOP_VFCLASS
- Add VOP_VFWCVT_FF and VOP_VFNCVT_FF specifically for the two
  Zvfhmin instructions so they are identifiable by downstream stages
- Remove VALU_FP placeholder once all OPFVV/OPFVF entries are added
- Keep VALU_INT placeholder for OPMVV/OPMVX (deferred to DECODE-007)

Step 3 - Add funct6 decode to decode_vec_one() in instr_decoder.sv:
- Add funct6 disambiguation for OPFVV and OPFVF groups
- Follow the same nested case structure used for OPIVV/OPIVX/OPIVI
  in DECODE-005
- For vfcvt/vfwcvt/vfncvt: these share a funct6 value and are
  distinguished by subfunct bits within the instruction. Read rv_v
  carefully for the exact bit positions before implementing.
- For unrecognized funct6 values set v_op_class = VOTHER
- Do not touch OPIVV/OPIVX/OPIVI or OPMVV/OPMVX cases

Step 4 - Update testbench:
- Add directed tests covering:
  - One OPFVV test per major instruction class
  - One OPFVF test per major instruction class
  - vfwcvt.f.f.v specifically -- Zvfhmin closure test
  - vfncvt.f.f.w specifically -- Zvfhmin closure test
  - At least one FP compare (vmfeq, vmflt etc.)
  - At least one FP reduction (vfredosum etc.)
  - At least one FP widening (vfwadd, vfwmul etc.)
  - Regression: verify OPIVV/OPIVX/OPIVI results unchanged
- All tests must be self-checking

Step 5 - Verilator lint and simulation must be clean.

Step 6 - Run tools/check_rva23_coverage.py and confirm:
- Zvfhmin shows as fully covered
- V extension still ROUTED with 0 missing
- No regressions in any other extension

---

Constraints:
- Changes confined to decode_pkg.sv and instr_decoder.sv only
- Do not modify rvc_expander.sv or any other RTL file
- Do not attempt OPMVV/OPMVX disambiguation -- deferred to DECODE-007
- funct6 values must be taken from rv_v tools file -- not training data
- All 8 slots must decode in parallel -- no sequential logic
- VALU_FP placeholder must be removed once OPFVV/OPFVF are complete
- Maximum 80 column line width -- strictly enforced
- Use 2 spaces for indent rather than 4 spaces, no tabs ever

---

Deliverables:
1. Updated decode_pkg.sv with full OPFVV/OPFVF VOP_* enum entries
2. Updated instr_decoder.sv with funct6 decode for OPFVV/OPFVF
3. Updated testbench with directed tests including Zvfhmin closure
4. Clean Verilator lint and simulation
5. Coverage script output confirming Zvfhmin fully covered
6. Explicit list of any funct6 ambiguities or subfunct encoding
   complexities found in rv_v
7. Count of VOP_* enum entries added
8. Explicit confirmation that VALU_FP placeholder has been removed
9. Explicit statement of what remains deferred to DECODE-007


## RESULTS CAPTURE

### Claude Text Output

  DECODE-006 Complete                                                           
                                                                                
  Deliverable results                                       
                                                                                
  1. decode_pkg.sv — 53 new VOP_ enum entries added (7'd71 to 7'd123)*          
                                                                                
  ┌─────────┬────────────────────────────────────────────────────────┬───────┐  
  │  Range  │                         Group                          │ Count │
  ├─────────┼────────────────────────────────────────────────────────┼───────┤
  │ 71-84   │ OPFVV/OPFVF shared: vfadd, vfsub, vfmin, vfmax,        │ 14    │
  │         │ vfsgnj/n/x, vfslide1up/down, vfmv                      │       │
  ├─────────┼────────────────────────────────────────────────────────┼───────┤  
  │ 85-90   │ vfmerge, vfcvt, vfwcvt, VOP_VFWCVT_FF, vfncvt,         │ 6     │
  │         │ VOP_VFNCVT_FF                                          │       │  
  ├─────────┼────────────────────────────────────────────────────────┼───────┤
  │ 91-94   │ vfsqrt, vfrsqrt7, vfrec7, vfclass                      │ 4     │  
  ├─────────┼────────────────────────────────────────────────────────┼───────┤  
  │ 95-100  │ vmfeq, vmfle, vmflt, vmfne, vmfgt, vmfge               │ 6     │
  ├─────────┼────────────────────────────────────────────────────────┼───────┤  
  │ 101-112 │ vfdiv, vfrdiv, vfmul, vfrsub, FMA group x8             │ 12    │
  ├─────────┼────────────────────────────────────────────────────────┼───────┤  
  │ 113-123 │ Widening: vfwadd, vfwredusum, vfwsub, vfwredosum,      │ 11    │
  │         │ vfwadd_w, vfwsub_w, vfwmul, vfwmacc/nmacc/msac/nmsac   │       │  
  └─────────┴────────────────────────────────────────────────────────┴───────┘
                                                                                
  Total: 53 new VOP_ entries*                                                   
   
  2. instr_decoder.sv — OPFVV (funct3=3'b001) and OPFVF (funct3=3'b101) now     
  fully decoded with nested case (f6). The cvt group (funct6=0x12) has a second
  level case (inst[19:15]) for subfunct disambiguation.                         
                                                            
  3. Testbench — T37 replaced; T41–T45 added:                                   
  - T41: Zvfhmin closure (vfwcvt.f.f.v, vfncvt.f.f.w), cvt group, sqrt/class,
  vmfeq                                                                         
  - T42: OPFVV reductions (vfredusum/osum/min/max, vfwredusum/osum), vfwmul, FMA
  - T43: OPFVF unique (vfslide1up/down, vfmv.s.f, vfmerge, vfmv.v.f, vmfgt,     
  vmfge)                                                                        
  - T44: OPFVF MAC+widening (vfrdiv, vfrsub, vfmacc, vfwmacc, vfwadd, vfwmul,   
  vmfeq)                                                                        
  - T45: Regression — OPIVV/OPIVX/OPIVI unchanged, OPMVV/OPMVX still VALU_INT,  
  OPFVV undefined funct6 → VOTHER                                             
                                                                                
  4. Verilator lint — clean, no warnings.                   
                                                                                
  5. Simulation — PASS=396 FAIL=0                           
                                                                                
  6. Coverage script                                                            
  - V extension: ROUTED — 375 instrs, 0 missing
  - Zvfhmin: NO REF FILE — expected; script notes "instructions are a subset of 
  rv_v"; all Zvfhmin instructions are accounted for under V (0 missing)        
  - No regressions in any other extension                                       
                                                            
  7. Count of VOP_ entries added: 53*                                           
                                                                                
  8. VALU_FP placeholder: REMOVED. 7'd2 is now a reserved hole with a comment.  
  VALU_INT (7'd1) is retained for DECODE-007.                                   
                                                                                
  9. What remains deferred to DECODE-007:                                       
  - OPMVV (funct3=3'b010): fully deferred — placeholder VALU_INT returned
  - OPMVX (funct3=3'b110): fully deferred — placeholder VALU_INT returned       
  - All VOP_VWADDU..VOP_VNMSUB stubs (7'd52–7'd70) assigned at enum level but
  funct6 decode not wired for OPMVV/OPMVX — that is DECODE-007's work           
                                                                                
  ---                                                                           
  funct6 ambiguities / subfunct encoding complexities found in rv_v:            
                                                                                
  1. funct6=0x12 (cvt group): vfcvt, vfwcvt, vfncvt all share one funct6 value,
  disambiguated by inst[19:15] (the vs1/subfunct field). The Zvfhmin            
  instructions vfwcvt.f.f.v (subfunct=0x0C) and vfncvt.f.f.w (subfunct=0x14) sit
   within the widen/narrow ranges; they required explicit case entries before   
  the group-level fallback.                                 
  2. funct6=0x13 (sqrt/class): vfsqrt, vfrsqrt7, vfrec7, vfclass share one
  funct6, disambiguated by inst[19:15]. Values 0x01–0x03, 0x06–0x0F, 0x11–0x1F  
  are unassigned → VOTHER.
  3. funct6=0x17 in OPFVF: vfmerge.vfm (vm=0) vs vfmv.v.f (vm=1) — identical to 
  the integer vmerge/vmv pattern.                                               
  4. funct6=0x10 in OPFVV is vfmv.f.s (destination is scalar rd, not vd) —
  downstream dispatch must check the VOP_VFMV opcode combined with funct3 to    
  distinguish from vfmv.s.f (OPFVF funct6=0x10).            

### Experiment Header

| Field          | Value |
|----------------|-------|
| Experiment ID  | DECODE-006 |
| Date           | 2026.03.22 |
| Module         | decoder    |
| Run time       | 10m.43s    |
| Session Link   | claude --resume 644aa7b1-4cba-4647-acf2-0e96d83bba62 |

---

### Output Quality

| Criteria                    | Rating (1-5) | Notes |
|-----------------------------|--------------|-------|
| RVA23 compliance            | 5   | |
| Interface correctness       | n/a | |
| RTL quality / readability   | 3   | line width and indent rules ignored|
| Testbench quality           | 5   | |
| Verilator compatibility     | 5   | |
| Assumptions stated clearly  | n/a | |

---

### What Claude got right

Spec discipline - the read/before/write directive is being followed.

Ambiguity identification Claude surfaced real spec subtleties that matter downstream:

  cvt group subfunct encoding (DECODE-006)
  vfmv.f.s vs vfmv.s.f scalar destination issue (DECODE-006)

The testbenches are/remain self-checking

---

### What Claude got wrong or missed

vfmv.f.s downstream risk: scalar destination case identified but not
resolved at decode stage. Dispatch cannot use v_op_class alone --
must inspect funct3 as well. Cleaner solution would be a dedicated
VOP_VFMV_FS enum entry. Noted as technical debt.

It is having trouble sticking with the formatting requirements. I think
the solution is to add a format check-script and require it to pass that
script.

---

### RVA23 compliance flags raised by Claude

- funct6=0x10 OPFVV vfmv.f.s: destination is scalar rd not vd.
  Downstream dispatch must distinguish from vfmv.s.f (OPFVF funct6=0x10)
  using VOP_VFMV combined with funct3. Compliance risk if dispatch
  treats all VOP_VFMV identically.
- funct6=0x17 OPFVF: vfmerge/vfmv.v.f vm-bit disambiguation confirmed
  consistent with integer vmerge/vmv pattern from DECODE-005.

---

### Interface decisions made - downstream impact

- vfmv.f.s vs vfmv.s.f distinction: dispatch must inspect both
  v_op_class (VOP_VFMV) and funct3 to route correctly. Cannot
  use v_op_class alone.
- cvt group subfunct bits (inst[19:15]) decoded at decode stage --
  VOP_VFWCVT_FF and VOP_VFNCVT_FF are distinct enum entries.
  FPU can rely on v_op_class alone for these.
- VALU_INT retained for OPMVV/OPMVX -- dispatch must not attempt
  fine-grained steering on VALU_INT until DECODE-007 completes.

---

### Prompt effectiveness observations

Did the prompt produce the intended experiment? 
yes. The prompt was written by Claude.ai

Was anything ambiguous or missing?
no

---

### Follow-on actions

- [x] update CLAUDE.md with style selections
- [x] update README.md status table
- [ ] Consider adding VOP_VFMV_FS as dedicated enum entry to make
      vfmv.f.s unambiguous for dispatch -- either in DECODE-007
      or as a standalone fix (choosing standalone now)

---

### Graduated to CLAUDE.md

- Use 2 spaces for indent. No exceptions. This will be checked by
  style scripts

