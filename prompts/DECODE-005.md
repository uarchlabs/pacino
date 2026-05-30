=============================================================
# Task Header
=============================================================
:: HEADER:START ::
| Field       | Value                                        |   |
|-------------|----------------------------------------------|---|
| Task ID     | DECODE-005                                   |   |
| Date        | 2026-03-22                                   |   |
| Module      | decoder                                      |   |
| Run time       | 9m.39s     | |
| Ctx%        | not recorded                                 |   |
| Model       | Sonnet 4.6 normal                            |   |
| Resume sha  | 21accb7f-7b47-47c7-8226-71417350a2e4 | |

Task:   [x] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Status: [ ] in-progress [x] complete        [ ] abandoned

# Overview of task
Vector integer ALU decode disambiguation (funct6 decode)

2026-05-30: This task file has been retro-fitted with the 
now standard section markers.
:: HEADER:END :
=============================================================
:: DISCUSSION:START ::

# Results Discussion

## Claude.code Console Output
  DECODE-005 complete. Here is the summary of deliverables:

  ---
  1. decode_pkg.sv — v_op_class_t expanded from logic[3:0] (8 entries) to
  logic[6:0] (71 entries). VALU_INT retained for OPMVV/OPMVX placeholder.

  2. instr_decoder.sv — decode_vec_one() now performs nested funct6 decode for
  OPIVV (funct3=3'b000), OPIVX (funct3=3'b100), and OPIVI (funct3=3'b011).
  OPFVV/OPFVF unchanged (VALU_FP). OPMVV/OPMVX unchanged (VALU_INT).

  3. Testbench — T28 updated to expect VOP_VADD. Tests T31–T40 added: 10 test
  groups covering OPIVV, OPIVX, OPIVI per-funct6, vmerge/vmv disambiguation,
  saturation, narrowing, widening reduction, VALU_FP regression, VALU_INT
  regression, VOTHER for unknown funct6, and the key asymmetry (OPIVV
  funct6=0x0e is vrgatherei16; OPIVX/OPIVI 0x0e is vslideup).

  4. Lint and simulation — clean. 351 tests, 0 failures.

  5. Coverage — V extension still ROUTED, 0 missing. No regressions.

  6. Ambiguous/overlapping encodings found:
  - funct6=0x17 in all three groups encodes both vmerge (vm=0) and vmv.v.*
  (vm=1) — resolved by checking inst[25] inside the funct6 case                 
  - funct6=0x11 encodes both vmadc.*.m (vm=0) and vmadc.* (vm=1) — both map to
  VOP_VMADC; distinction deferred to rename                                     
  - funct6=0x13: same pattern for vmsbc variants — both map to VOP_VMSBC        
  - funct6=0x27 in OPIVV/OPIVX is vsmul; in OPIVI it is vmv1r/2r/4r/8r — no
  conflict since outer case is on funct3                                        

  7. VOP_* enum entries added: 63 (7'd8 through 7'd70).

  8. Deferred:
  - DECODE-006: OPFVV/OPFVF funct6 decode (vfadd, vfsub, …). Currently VALU_FP
  coarse class.
  - DECODE-007: OPMVV/OPMVX funct6 decode (vmacc, vwaddu, vwmul, …). Currently
  VALU_INT coarse class. Enum stubs VOP_VWADDU..VOP_VNMSUB are defined and
  ready.

## My Assessment
Nothing required
## Claude.ai Assessment

### What Claude got right

The funct6=0x17 vmerge/vmv.v.* disambiguation via inst[25] is a spec subtlety.

Claude caught it, resolved it correctly, and deferred the vmadc/vmsbc
mask-bit distinction to rename appropriately. This shows good judgement
in segmentation. The decoder should not make architectural state decisions.
```

---

### What Claude got wrong or missed

minor: Claude did not maintain the 80 column style limit specified in CLAUDE.md
       re-wrote as a requirement not a suggestion


## Follow-on Actions
- [x] Update STATE.md table
## CLAUDE.md Updates
- Line width: 80 column maximum. No exceptions. This will be
  checked by style scripts.

- No tabs are permitted. No exceptions. This will be checked by
  style scripts

## Other Planning File Updates
Nothing required
:: DISCUSSION:END ::
=============================================================
# Claude.code Prompt
=============================================================
:: PROMPT:START ::

## Task ID
DECODE-005

## Hypothesis 
All vector integer ALU instructions (funct3 = OPIVV/OPIVX/OPIVI) can be
fully disambiguated using funct6 decoding within decode_vec_one() without
changes to any other part of the decoder. After this experiment v_op_class
for integer vector ALU instructions should be fully resolved and the
v_op_class field should carry a meaningful per-instruction opcode rather
than the coarse VALU_INT placeholder from DECODE-004.

---

## Background:
DECODE-004 established the vector decode foundation. All OP_VECTOR (0x57)
instructions are routed correctly. v_op_class is currently set at coarse
level only:
  - funct3 001/101 -> VALU_FP
  - all others     -> VALU_INT (placeholder)

This experiment fully disambiguates the VALU_INT group using funct6.
VALU_FP disambiguation is deferred to DECODE-006.
Mask/reduce/permute (OPMVV/OPMVX) disambiguation is deferred to DECODE-007.

---

# Specific requirements

Step 1 - Read before writing:
- Read frontend/decoder/rtl/decode_pkg.sv in full
- Read frontend/decoder/rtl/instr_decoder.sv in full
- Read tools/riscv-opcodes/extensions/rv_v carefully - focus on:
  - All instructions with funct3 = OPIVV (3'b000)
  - All instructions with funct3 = OPIVX (3'b100)
  - All instructions with funct3 = OPIVI (3'b011)
- Do not rely on training data for funct6 encodings - use rv_v as
  ground truth

Step 2 - Expand v_op_class_t enum in decode_pkg.sv:
- Replace the coarse VALU_INT placeholder with per-instruction entries
- Use a naming convention that is clear and consistent:
    VOP_VADD, VOP_VSUB, VOP_VRSUB, VOP_VMINU, VOP_VMIN,
    VOP_VMAXU, VOP_VMAX, VOP_VAND, VOP_VOR, VOP_VXOR,
    VOP_VRGATHER, VOP_VSLIDEUP, VOP_VRGATHEREI16,
    VOP_VSLIDEDOWN, VOP_VADC, VOP_VMADC, VOP_VSBC, VOP_VMSBC,
    VOP_VMERGE, VOP_VMV, VOP_VMSEQ, VOP_VMSNE, VOP_VMSLTU,
    VOP_VMSLT, VOP_VMSLEU, VOP_VMSLE, VOP_VMSGTU, VOP_VMSGT,
    VOP_VSADDU, VOP_VSADD, VOP_VSSUBU, VOP_VSSUB,
    VOP_VSLL, VOP_VSMUL, VOP_VSRL, VOP_VSRA, VOP_VSSRL,
    VOP_VSSRA, VOP_VNSRL, VOP_VNSRA, VOP_VNCLIPU, VOP_VNCLIP,
    VOP_VWREDSUMU, VOP_VWREDSUM,
    VOP_VWADDU, VOP_VWADD, VOP_VWSUBU, VOP_VWSUB,
    VOP_VWADDU_W, VOP_VWADD_W, VOP_VWSUBU_W, VOP_VWSUB_W,
    VOP_VWMULU, VOP_VWMULSU, VOP_VWMUL,
    VOP_VWMACCU, VOP_VWMACC, VOP_VWMACCUS, VOP_VWMACCSU,
    VOP_VMACC, VOP_VNMSAC, VOP_VMADD, VOP_VNMSUB
- Keep VALU_FP, VCFG, VMEM, VMASK, VPERM, VREDUCE, VOTHER as
  placeholders for later experiments
- ASCII only in all comments

Step 3 - Add funct6 decode to decode_vec_one() in instr_decoder.sv:
- Add funct6 disambiguation for OPIVV, OPIVX, OPIVI groups only
- Structure as a nested case: outer on funct3, inner on funct6
- For each instruction set v_op_class to the corresponding VOP_*
  enum value
- For unrecognized funct6 values within OPIVV/OPIVX/OPIVI set
  v_op_class = VOTHER and flag as potentially illegal
- Do not touch OPFVV/OPFVF or OPMVV/OPMVX cases - leave as
  VALU_FP and VALU_INT placeholders respectively
- Do not modify any other file except decode_pkg.sv and
  instr_decoder.sv

Step 4 - Update testbench:
- Add directed tests for at minimum one instruction per funct3 group
  per funct6 value - focus on:
  - One OPIVV test per major instruction class
  - One OPIVX test per major instruction class
  - One OPIVI test per immediate-form instruction
  - At least one widening instruction (VWADDU, VWMUL etc.)
  - At least one narrowing instruction (VNSRL, VNCLIP etc.)
  - At least one saturating instruction (VSADDU, VSADD etc.)
  - At least one multiply-accumulate (VMACC, VMADD etc.)
- All tests must be self-checking
- Verify VALU_FP and OPMVV groups still return correct coarse
  class (no regression)

Step 5 - Verilator lint and simulation must be clean.

Step 6 - Run tools/check_rva23_coverage.py:
- Coverage numbers should be unchanged (V was already ROUTED)
- Confirm no regressions

---

## Constraints
- ASCII only in all comments
- Changes confined to decode_pkg.sv and instr_decoder.sv only
- Do not modify rvc_expander.sv or any other RTL file
- Do not attempt VALU_FP or OPMVV/OPMVX disambiguation - deferred
- funct6 values must be taken from rv_v tools file - not from
  training data
- All 8 slots must decode in parallel - no sequential logic

---

## Deliverables
1. Updated decode_pkg.sv with expanded v_op_class_t enum
2. Updated instr_decoder.sv with funct6 decode for OPIVV/OPIVX/OPIVI
3. Updated testbench with directed tests per funct3/funct6 group
4. Clean Verilator lint and simulation
5. Coverage script output confirming no regressions
6. Explicit list of any funct6 encodings found in rv_v that were
   ambiguous or had overlapping encodings across funct3 groups
7. Count of VOP_* enum entries added
8. Explicit statement of what remains deferred to DECODE-006
   and DECODE-007

```
:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::

## RESULTS CAPTURE

### Claude Text Output

```
  ---                                                                           
  DECODE-005 complete. Here is the summary of deliverables:                     
                                                                                
  ---                                                                           
  1. decode_pkg.sv — v_op_class_t expanded from logic[3:0] (8 entries) to       
  logic[6:0] (71 entries). VALU_INT retained for OPMVV/OPMVX placeholder.       
                                                                         
  2. instr_decoder.sv — decode_vec_one() now performs nested funct6 decode for  
  OPIVV (funct3=3'b000), OPIVX (funct3=3'b100), and OPIVI (funct3=3'b011).      
  OPFVV/OPFVF unchanged (VALU_FP). OPMVV/OPMVX unchanged (VALU_INT).
                                                                                
  3. Testbench — T28 updated to expect VOP_VADD. Tests T31–T40 added: 10 test   
  groups covering OPIVV, OPIVX, OPIVI per-funct6, vmerge/vmv disambiguation,
  saturation, narrowing, widening reduction, VALU_FP regression, VALU_INT       
  regression, VOTHER for unknown funct6, and the key asymmetry (OPIVV
  funct6=0x0e is vrgatherei16; OPIVX/OPIVI 0x0e is vslideup).

  4. Lint and simulation — clean. 351 tests, 0 failures.                        
  
  5. Coverage — V extension still ROUTED, 0 missing. No regressions.            
                                                            
  6. Ambiguous/overlapping encodings found:                                     
  - funct6=0x17 in all three groups encodes both vmerge (vm=0) and vmv.v.*
  (vm=1) — resolved by checking inst[25] inside the funct6 case                 
  - funct6=0x11 encodes both vmadc.*.m (vm=0) and vmadc.* (vm=1) — both map to
  VOP_VMADC; distinction deferred to rename                                     
  - funct6=0x13: same pattern for vmsbc variants — both map to VOP_VMSBC        
  - funct6=0x27 in OPIVV/OPIVX is vsmul; in OPIVI it is vmv1r/2r/4r/8r — no
  conflict since outer case is on funct3                                        
                                                                                
  7. VOP_* enum entries added: 63 (7'd8 through 7'd70).                         
                                                                                
  8. Deferred:                                                                  
  - DECODE-006: OPFVV/OPFVF funct6 decode (vfadd, vfsub, …). Currently VALU_FP  
  coarse class.                                                                 
  - DECODE-007: OPMVV/OPMVX funct6 decode (vmacc, vwaddu, vwmul, …). Currently
  VALU_INT coarse class. Enum stubs VOP_VWADDU..VOP_VNMSUB are defined and      
  ready.   
```

### Experiment Header

| Field          | Value |
|----------------|-------|
| Task ID  | DECODE-005 |
| Date           | 2026.03.22 |
| Module         | decoder    |
| Run time       | 9m.39s     |
| Session Link   | claude --resume 21accb7f-7b47-47c7-8226-71417350a2e4 |

---

### Output Quality

| Criteria                    | Rating (1-5) | Notes |
|-----------------------------|--------------|-------|
| RVA23 compliance            | 5   | |
| Interface correctness       | n/a | |
| RTL quality / readability   | 5   | |
| Testbench quality           | 5   | |
| Verilator compatibility     | 5   | |
| Assumptions stated clearly  | n/a | |

---

### What Claude got right

The funct6=0x17 vmerge/vmv.v.* disambiguation via inst[25] is a spec subtlety. 

Claude caught it, resolved it correctly, and deferred the vmadc/vmsbc 
mask-bit distinction to rename appropriately. This shows good judgement
in segmentation. The decoder should not make architectural state decisions.
```

---

### What Claude got wrong or missed

minor: Claude did not maintain the 80 column style limit specified in CLAUDE.md
       re-wrote as a requirement not a suggestion

---

### RVA23 compliance flags raised by Claude

- funct6=0x17: vmerge vs vmv.v.* distinction requires inst[25] check.
  Resolved at decode stage correctly.
- funct6=0x11/0x13: vmadc/vmsbc mask-bit variants both map to same
  VOP_* class. Full distinction deferred to rename -- compliance risk
  if rename does not handle this correctly.

---

### Interface decisions made - downstream impact

```
- vmadc/vmsbc mask-bit distinction (vm field) passed through in
  vec_decode_pkt_t. Rename must inspect vm bit to distinguish
  vmadc.*.m from vmadc.* variants.
- vmerge/vmv resolved at decode -- no downstream ambiguity.
- 63 new VOP_* entries in v_op_class_t -- issue queue and
  execution unit must handle full enum width (7 bits).
```


---

### Prompt effectiveness observations

The prompt was written by Claude.ai

The prompt was highly detailed. It might be worth redoing this experiment
with less detail and comparing the results.


---

### Follow-on actions

- [x] Update STATE.md table

---

### Graduated to CLAUDE.md

- Line width: 80 column maximum. No exceptions. This will be
  checked by style scripts.

- No tabs are permitted. No exceptions. This will be checked by
  style scripts

:: RESULTS:END ::

