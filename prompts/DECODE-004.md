=============================================================
# Task Header
=============================================================
:: HEADER:START ::
| Field       | Value                                        |   |
|-------------|----------------------------------------------|---|
| Task ID     | DECODE-004                                   |   |
| Date        | 2026-03-22                                   |   |
| Module      | decoder                                      |   |
| Run time    | 10m.56s    | |
| Ctx%        | not recorded                                 |   |
| Model       | Sonnet 4.6 normal                            |   |
| Resume sha  | 75e0b260-97fc-40e1-8dae-0347f8d06d08 | |

Task:   [x] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Status: [ ] in-progress [x] complete        [ ] abandoned

# Overview of task
Experiment: DECODE-004 - Vector decode foundation, decode_pkg.sv and
opcode handler

2026-05-30: This task file has been retro-fitted with the 
now standard section markers.
:: HEADER:END :
=============================================================
:: DISCUSSION:START ::

# Results Discussion

## Claude.code Console Output
  ---
  DECODE-004 Results

  Verilator lint: Clean (both modules, no warnings).
  Simulation: 284 PASS / 0 FAIL.
  Coverage: V extension now shows [ROUTED] — 375 instructions, 0 missing.

  ---
  What was delivered

  1. decode_pkg.sv — added v_op_class_t enum (8 classes, 4 bits) and
  vec_decode_pkt_t struct with all required fields: is_vector, is_vsetvl,
  needs_vtype, vsew/vlmul/vta/vma, vd/vs1/vs2/vs3/vm, nf/eew, v_op_class.

  2. instr_decoder.sv — OP_VECTOR = 7'b1010111 added; OP_VECTOR case in
  decode_one() returns a non-illegal scalar packet; new decode_vec_one()
  function decodes all OP_VECTOR (0x57) instructions into vec_decode_pkt_t; new
  outputs vec_decode_bundle[7:0] and is_vector[7:0] added to module interface;
  generate block drives all three outputs per slot.

  3. tb_instr_decoder.sv — added CHECK_VEC macro, vector opcode constant, 5
  encoding functions (enc_vsetvli, enc_vsetivli, enc_vsetvl, enc_vadd_vv,
  enc_vle32v), and tests T24–T30 covering: vsetvli e32m1ta, vsetvli e16m4,
  vsetivli e8m2, vsetvl (register form), vadd.vv, vle32.v misidentification
  (documented), 8-slot scalar/vector mix.

  4. check_rva23_coverage.py — added 0x15: 'OP_VECTOR' to HANDLED_OPGROUPS.

  ---
  Architectural assumptions made

  - decode_vec_one() only handles opcode 0x57. Vector memory ops (vle*/vse* via
  0x07/0x27) are not touched — they remain misrouted through
  OP_LOAD_FP/OP_STORE_FP.
  - v_op_class is coarse: funct3 001/101 → VALU_FP; all others → VALU_INT. Finer
   classification deferred to DECODE-005 through DECODE-007.
  - For vsetvl (register form): vsew/vlmul/vta/vma fields left at zero — vtype
  is in rs2 at runtime, resolved by the vector unit.
  - Scalar decode_pkt_t for OP_VECTOR sets uses_rd/rs1/rs2 = 1 conservatively;
  rename uses is_vector to steer to the vector unit and handles register fields
  from vec_decode_pkt_t.

  ---
  Deferred to DECODE-005 through DECODE-009

  ┌────────────┬─────────────────────────────────────────────────────────────┐
  │ Experiment │                            Scope                            │
  ├────────────┼─────────────────────────────────────────────────────────────┤
  │ DECODE-005 │ OPIVV/OPIVX/OPIVI integer ALU disambiguation (funct6        │
  │            │ decode)                                                     │
  ├────────────┼─────────────────────────────────────────────────────────────┤
  │ DECODE-006 │ OPFVV/OPFVF floating-point ALU disambiguation               │
  ├────────────┼─────────────────────────────────────────────────────────────┤
  │ DECODE-007 │ OPMVV/OPMVX mask/reduce/permute disambiguation              │
  ├────────────┼─────────────────────────────────────────────────────────────┤
  │ DECODE-008 │ Vector memory ops: reclassify opcodes 0x07/0x27 as vector   │
  │            │ loads/stores                                                │
  ├────────────┼─────────────────────────────────────────────────────────────┤
  │ DECODE-009 │ Segment loads/stores (nf > 0), whole-register moves         │
  └────────────┴─────────────────────────────────────────────────────────────┘

## My Assessment
Nothing required

## Claude.ai Assessment

What Claude got right

The dual packet output (decode_bundle + vec_decode_bundle + is_vector) is considered a good choice at this point in the design.

The conservative uses_rd/rs1/rs2=1 on the scalar packet for OP_VECTOR is a reasonable placeholder — rename can use is_vector to steer correctly.

The vsetvl register form decision is correct — leaving vsew/vlmul/vta/vma at zero when vtype comes from rs2 at runtime is the right stateless decoder behavior.  This matches the decision expressed in CLAUDE.md.

The vle32.v misidentification test being documented rather than fixed is good experiment discipline — scope of this experiment was honored.

Claude collapsed the config instructions (vsetvl/vsetvli/vsetivli) into DECODE-004 — they're already handled at the coarse level. That is reasonable since the config instructions are decoded correctly at the opcode level already.

What Claude got wrong or missed

Not wrong but a shift in focus by adding vsetvl to this experiment, 
and collapsing DECODE-005 into 004.

## Follow-on Actions
- [x] update README.md status table
- [x] Add support for disabling extensions
- [x] add this to DECODE-006
      Zvfhmin closure: vfwcvt.f.f.v and vfncvt.f.f.w are OPFVV instructions.
      When OPFVV disambiguation is complete these are covered. Confirm closure
      by re-running check_rva23_coverage.py and verifying Zvfhmin shows full
      coverage.

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
DECODE-004


Module: Instruction Decoder

Experiment: DECODE-004 - Vector decode foundation, decode_pkg.sv and
opcode handler

---
## Hypothesis 
Establish the vector decode foundation by adding OP_VECTOR opcode handler
(0x57) to instr_decoder.sv and a separate vec_decode_t struct to
decode_pkg.sv. After this experiment the decoder should recognize all
vector instructions at the opcode level and produce a correctly structured
vector decode packet. No instruction-level disambiguation is required in
this experiment - that is scope for DECODE-005 through DECODE-009.

## Background
DECODE-002 gap analysis confirmed opcode 0x57 (OP_VECTOR) is completely
absent from instr_decoder.sv. DECODE-003 closed the scalar gap (Zcb).
The scalar decoder is now complete. This experiment begins the vector
extension track.

Architectural decisions already made - do not deviate from these:

1. Separate vec_decode_t struct alongside existing decode_t.
   Do not add vector fields to the existing decode_t struct.
   The two packet types travel in parallel through the pipeline.

2. Decoder is stateless. vtype is handled as a producer/consumer
   dependency:
   - vsetvl/vsetvli/vsetivli set is_vsetvl=1 and populate vsew,
     vlmul, vta, vma fields from the instruction immediate/rs1/rs2.
   - All other vector instructions set needs_vtype=1 and leave
     vtype fields unpopulated. Rename resolves the dependency.

3. Intra-bundle vtype dependency policy is TBD - deferred to
   rename/dispatch. Decoder marks is_vsetvl and needs_vtype
   correctly and passes through. Add a comment in the RTL noting
   this is unresolved at the decode stage.

---
## Specific Requirements

Step 1 - Read existing RTL before writing anything:
- Read frontend/decoder/rtl/decode_pkg.sv
- Read frontend/decoder/rtl/instr_decoder.sv
- Read tools/riscv-opcodes/extensions/rv_v for opcode 0x57 encoding
- Read tools/riscv-opcodes/extensions/rv_zve32x and rv_zve64x
  for vector extension baseline encodings
- Understand the existing decode_t struct fully before adding vec_decode_t

Step 2 - Add vec_decode_t to decode_pkg.sv:

   The struct must contain at minimum:

   // instruction class
   logic        is_vector;       // this is a vector instruction
   logic        is_vsetvl;       // this instruction sets vtype/vl
   logic        needs_vtype;     // this instruction consumes vtype

   // vtype fields - populated by vsetvl/vsetvli/vsetivli only
   logic [2:0]  vsew;            // selected element width
   logic [2:0]  vlmul;           // vector register grouping
   logic        vta;             // tail agnostic policy
   logic        vma;             // mask agnostic policy

   // vector register operands
   logic [4:0]  vd;              // destination vector register
   logic [4:0]  vs1;             // source vector register 1
   logic [4:0]  vs2;             // source vector register 2
   logic [4:0]  vs3;             // source vector register 3 (stores)
   logic        vm;              // mask enable (0=masked, 1=unmasked)

   // memory/segment fields
   logic [2:0]  nf;              // number of fields (segment ops)
   logic [2:0]  eew;             // effective element width (memory ops)

   // operation type - placeholder for DECODE-005 through DECODE-009
   // use a simple enum for now, to be expanded in later experiments
   logic [3:0]  v_op_class;      // VCFG, VALU_INT, VALU_FP, VMEM,
                                 // VMASK, VPERM, VREDUCE, VOTHER

   // intra-bundle vtype dependency - policy TBD at rename/dispatch
   // decoder sets these correctly, rename resolves dependency
   // see CLAUDE.md microarchitectural implications

Step 3 - Add OP_VECTOR handler to instr_decoder.sv:
- Add opcode 0x57 case to the main opcode decode block
- For this experiment all 0x57 instructions are decoded to:
  - is_vector = 1
  - vd, vs1, vs2, vm extracted from standard RVV bit positions
  - funct3 used to set v_op_class at coarse level only
  - is_vsetvl set for vsetvl/vsetvli/vsetivli (funct3 = 3'b111)
  - vsew, vlmul, vta, vma decoded from immediate for vsetvli/vsetivli
  - needs_vtype set for all non-vsetvl vector instructions
- Vector memory instructions currently misidentified as FP loads/stores
  (opcode 0x07/0x27) - add a comment flagging this, fix is DECODE-008
- Output both decode_t and vec_decode_t from the decoder top level
  for all 8 issue slots

Step 4 - Update decoder top level interface:
- Decoder must output both decode_t[7:0] and vec_decode_t[7:0]
- Add a is_vector[7:0] flag at the top level for easy steering
- Ensure existing scalar decode_t output is unchanged

Step 5 - Update testbench:
- Add directed tests for:
  - vsetvli with various vsew/vlmul combinations
  - vsetivli with immediate AVL
  - vsetvl with rs1/rs2 form
  - A simple vadd.vv to verify OP_VECTOR routing
  - A vle32.v to verify it is currently misidentified (expected
    failure - document this, fix is DECODE-008)
- All tests must be self-checking

Step 6 - Run tools/check_rva23_coverage.py:
- OP_VECTOR should now show as routed
- Report the new coverage numbers
- Confirm no scalar regressions

Step 7 - Verilator lint and simulation must be clean.

---
## Constraints
- ASCII only in all comments - no Unicode characters
- vec_decode_t must be in decode_pkg.sv - not a separate file
- Do not modify the existing decode_t struct
- Do not attempt full vector instruction disambiguation in this
  experiment - that is DECODE-005 through DECODE-009
- All 8 issue slots must produce vec_decode_t in parallel
- No sequential logic inside the decoder - purely combinational

---

## Deliverables

1. Updated decode_pkg.sv with vec_decode_t struct
2. Updated instr_decoder.sv with OP_VECTOR handler
3. Updated decoder top level with dual packet output
4. Updated testbench with vector directed tests
5. Clean Verilator lint and simulation
6. Coverage script output showing OP_VECTOR routed
7. Explicit statement of what is deferred to DECODE-005 through
   DECODE-009 and what architectural assumptions were made

:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::

## RESULTS CAPTURE

### Claude Text Output

```
  ---                                                                           
  DECODE-004 Results
                                                                                
  Verilator lint: Clean (both modules, no warnings).        
  Simulation: 284 PASS / 0 FAIL.                                                
  Coverage: V extension now shows [ROUTED] — 375 instructions, 0 missing.       
                                                                                
  ---                                                                           
  What was delivered                                                            
                                                            
  1. decode_pkg.sv — added v_op_class_t enum (8 classes, 4 bits) and
  vec_decode_pkt_t struct with all required fields: is_vector, is_vsetvl,       
  needs_vtype, vsew/vlmul/vta/vma, vd/vs1/vs2/vs3/vm, nf/eew, v_op_class.
                                                                                
  2. instr_decoder.sv — OP_VECTOR = 7'b1010111 added; OP_VECTOR case in         
  decode_one() returns a non-illegal scalar packet; new decode_vec_one()
  function decodes all OP_VECTOR (0x57) instructions into vec_decode_pkt_t; new 
  outputs vec_decode_bundle[7:0] and is_vector[7:0] added to module interface;
  generate block drives all three outputs per slot.

  3. tb_instr_decoder.sv — added CHECK_VEC macro, vector opcode constant, 5     
  encoding functions (enc_vsetvli, enc_vsetivli, enc_vsetvl, enc_vadd_vv,
  enc_vle32v), and tests T24–T30 covering: vsetvli e32m1ta, vsetvli e16m4,      
  vsetivli e8m2, vsetvl (register form), vadd.vv, vle32.v misidentification
  (documented), 8-slot scalar/vector mix.

  4. check_rva23_coverage.py — added 0x15: 'OP_VECTOR' to HANDLED_OPGROUPS.     
  
  ---                                                                           
  Architectural assumptions made                            
                                                                                
  - decode_vec_one() only handles opcode 0x57. Vector memory ops (vle*/vse* via
  0x07/0x27) are not touched — they remain misrouted through                    
  OP_LOAD_FP/OP_STORE_FP.                                   
  - v_op_class is coarse: funct3 001/101 → VALU_FP; all others → VALU_INT. Finer
   classification deferred to DECODE-005 through DECODE-007.                    
  - For vsetvl (register form): vsew/vlmul/vta/vma fields left at zero — vtype
  is in rs2 at runtime, resolved by the vector unit.                            
  - Scalar decode_pkt_t for OP_VECTOR sets uses_rd/rs1/rs2 = 1 conservatively;
  rename uses is_vector to steer to the vector unit and handles register fields 
  from vec_decode_pkt_t.                                    
                                                                                
  ---                                                       
  Deferred to DECODE-005 through DECODE-009
                                                                                
  ┌────────────┬─────────────────────────────────────────────────────────────┐
  │ Experiment │                            Scope                            │  
  ├────────────┼─────────────────────────────────────────────────────────────┤
  │ DECODE-005 │ OPIVV/OPIVX/OPIVI integer ALU disambiguation (funct6        │  
  │            │ decode)                                                     │
  ├────────────┼─────────────────────────────────────────────────────────────┤  
  │ DECODE-006 │ OPFVV/OPFVF floating-point ALU disambiguation               │
  ├────────────┼─────────────────────────────────────────────────────────────┤  
  │ DECODE-007 │ OPMVV/OPMVX mask/reduce/permute disambiguation              │
  ├────────────┼─────────────────────────────────────────────────────────────┤  
  │ DECODE-008 │ Vector memory ops: reclassify opcodes 0x07/0x27 as vector   │
  │            │ loads/stores                                                │  
  ├────────────┼─────────────────────────────────────────────────────────────┤
  │ DECODE-009 │ Segment loads/stores (nf > 0), whole-register moves         │  
  └────────────┴─────────────────────────────────────────────────────────────┘ 

```

### Experiment Header

| Field          | Value |
|----------------|-------|
| Task ID  | DECODE-004 |
| Date           | 2026.03.22 |
| Module         | decode     |
| Run time       | 10m.56s    |
| Session Link   | claude --resume 75e0b260-97fc-40e1-8dae-0347f8d06d08 |

---

### Output Quality

| Criteria                    | Rating (1-5) | Notes |
|-----------------------------|--------------|-------|
| RVA23 compliance            | 3 | see compliance flags below, for temp fix |
| Interface correctness       | 5   | this is interim further analysis will occur|
| RTL quality / readability   | 5   | |
| Testbench quality           | ?   | |
| Verilator compatibility     | 5   | |
| Assumptions stated clearly  | 5   | see below |

---

### What Claude got right

The dual packet output (decode_bundle + vec_decode_bundle + is_vector) is considered a good choice at this point in the design.

The conservative uses_rd/rs1/rs2=1 on the scalar packet for OP_VECTOR is a reasonable placeholder — rename can use is_vector to steer correctly.

The vsetvl register form decision is correct — leaving vsew/vlmul/vta/vma at zero when vtype comes from rs2 at runtime is the right stateless decoder behavior.  This matches the decision expressed in CLAUDE.md. 

The vle32.v misidentification test being documented rather than fixed is good experiment discipline — scope of this experiment was honored.

Claude collapsed the config instructions (vsetvl/vsetvli/vsetivli) into DECODE-004 — they're already handled at the coarse level. That is reasonable since the config instructions are decoded correctly at the opcode level already.

---

### What Claude got wrong or missed

Not wrong but a shift in focus by adding vsetvl to this experiment, and collapsing DECODE-005 into 004.

---

### RVA23 compliance flags raised by Claude

Vector memory instructions (vle*/vse* via opcodes 0x07/0x27) are currently
misrouted through OP_LOAD_FP/OP_STORE_FP. This is a compliance gap until
DECODE-008 resolves it. A vector memory instruction presented to the decoder
today would be incorrectly classified.

---

### Interface decisions made - downstream impact

1. Dual packet output: decode_bundle[7:0] (scalar) + vec_decode_bundle[7:0]
   (vector) + is_vector[7:0]. Rename/dispatch must consume both and use
   is_vector to steer to the correct issue queue.

2. Conservative scalar packet for OP_VECTOR: uses_rd/rs1/rs2=1. Rename
   must not use the scalar packet register fields for vector instructions -
   it must use vec_decode_pkt_t fields instead.

3. vsetvl register form: vsew/vlmul/vta/vma left at zero in decode packet.
   Vector unit resolves vtype from rs2 at runtime. Rename must track the
   rs2 dependency for vsetvl instructions.

4. is_vector steering flag: provided per slot at top level. Rename/dispatch
   should use this as the primary steering signal, not opcode inspection.

---

### Prompt effectiveness observations

Did the prompt produce the intended experiment? 
  yes . The prompt was written by Claude.ai

Was anything ambiguous or missing?
  no 

---

### Follow-on actions

- [x] update README.md status table
- [x] Add support for disabling extensions
- [ ] add this to DECODE-006
      Zvfhmin closure: vfwcvt.f.f.v and vfncvt.f.f.w are OPFVV instructions.
      When OPFVV disambiguation is complete these are covered. Confirm closure
      by re-running check_rva23_coverage.py and verifying Zvfhmin shows full
      coverage.

---

### Graduated to CLAUDE.md

nothing added to CLAUDE.md
:: RESULTS:END ::

