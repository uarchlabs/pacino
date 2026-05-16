# BP-003-FIX: Retire UBTB_BR_* Localparams

## Task Header

| Field        | Value                                      |
|--------------|--------------------------------------------|
| ID           | BP-003-FIX                                 |
| Date         | 2026-03-29                                 |
| Module       | bp_pkg.sv, ubtb.sv, tb_ubtb.sv             |
| Run time     | 4m.31s                                     |        
| Ctx%         | 34%                                        |
| Model        | Sonnet 4.6 normal                          |
| Session link | claude --resume 32493613-9d00-4d5e-b42f-9dd52998bc35 |
| Status       | READY                                      |

Task:   [x] experiment  [ ] implementation  [ ] debug       [ ] cleanup
Status: [ ] in-progress [x] complete        [ ] abandoned

---

## Results Discussion

_Populated after session by Jeff / Claude.ai._

  BP-003-FIX complete. Exit 0, zero warnings, TC1-TC10 all PASS.                
  
  What was done                                                                 
                                         
  bp_pkg.sv — Removed the 11-line UBTB_BR_* localparam block. Changed br_type in
   ubtb_entry_t, ubtb_pred_t, and ubtb_upd_t from logic [2:0] to bp_br_type_e.  
                                                                                
  ubtb.sv — No changes. The module contains no UBTB_BR_* references; it stores  
  and forwards br_type without interpreting encoding values.
                                                                                
  tb_ubtb.sv — Replaced all UBTB_BR_* references with bp_br_type_e enum values  
  across TC2, TC4, TC5, TC7, TC8, TC9, TC10. Changed write_entry task parameter
  from logic [2:0] to bp_br_type_e. Expanded TC6 from 6 to 7 entries covering   
  all enum values: NO_BRANCH, COND, DIRECT_UNC, DIRECT_CALL, INDIRECT_CALL,
  INDIRECT_NONRET, RETURN.

  BP-003.md — Results Capture appended, marked BP-003-FIX.                      
  
  One residual UBTB_BR_COND reference in TC10 was caught by the Verilator       
  compile step and fixed before declaring clean. RVA23 compliance gap item 2
  from BP-003 (encoding mismatch requiring translation at integration) is now   
  resolved.   

  The actual token usage % can sometimes be recovered by exit and then 
  using session link

---

## Claude Code Prompt

### Context Loaded

Load exactly these files before making any edits. Read each
file completely before proceeding to the next. Do not load
any other files.

  @frontend/branch_predictor/rtl/bp_pkg.sv
  @frontend/branch_predictor/rtl/ubtb.sv
  @frontend/branch_predictor/tb/tb_ubtb.sv
  @frontend/branch_predictor/Makefile
  @CLAUDE.md

---

### Background

BP-003 introduced UBTB_BR_* localparams in bp_pkg.sv as the
branch type encoding for ubtb_entry_t, ubtb_pred_t, and
ubtb_upd_t. A pre-existing enum bp_br_type_e already covers
the same semantic space with finer granularity. Two encodings
for the same concept is a latent integration bug.

Resolution: retire UBTB_BR_* entirely. All three uBTB structs
use bp_br_type_e directly. No translation is needed at
bp_cluster integration because the pre-decoder resolves full
branch type from instruction bits (opcode + rd/rs1 fields)
before the post-execute update channel fires. The stored
encoding in the uBTB will be correct by the time it is
written.

This is a fixup only. No new RTL logic is introduced.

---

### Hypothesis

Replacing UBTB_BR_* localparams with bp_br_type_e in the
three uBTB structs and updating all reference sites produces
a cleaner bp_pkg.sv with a single branch type encoding,
while preserving all TC1-TC10 pass results and maintaining
exit 0, zero warnings.

---

### Specific Requirements

Work through these steps in order. Read before write: read
each file completely before generating any edits to it.

#### Step 1 -- Edit bp_pkg.sv

Read bp_pkg.sv completely.

Remove the UBTB_BR_* localparam block. This includes:
  UBTB_BR_NONE, UBTB_BR_COND, UBTB_BR_DIRECT,
  UBTB_BR_INDIR, UBTB_BR_CALL, UBTB_BR_RET,
  and the associated comments and reserved encoding comment.

In ubtb_entry_t: change the br_type field from
  logic [2:0]  br_type;
to
  bp_br_type_e br_type;

Apply the same change in ubtb_pred_t and ubtb_upd_t.

Do not modify any other structs or localparams.

#### Step 2 -- Edit ubtb.sv

Read ubtb.sv completely.

Replace all UBTB_BR_* references with the corresponding
bp_br_type_e values per this mapping:

  UBTB_BR_NONE   -> NO_BRANCH
  UBTB_BR_COND   -> COND
  UBTB_BR_DIRECT -> DIRECT_UNC
  UBTB_BR_INDIR  -> INDIRECT_NONRET
  UBTB_BR_CALL   -> DIRECT_CALL
  UBTB_BR_RET    -> RETURN

This mapping applies to all uses: default assignments,
comparisons, and any case/if expressions referencing
branch type.

Do not change any logic, timing, or structural behavior.
This is a naming substitution only.

#### Step 3 -- Edit tb_ubtb.sv

Read tb_ubtb.sv completely.

Update TC6 to use bp_br_type_e values instead of UBTB_BR_*
values. Expand TC6 to cover all seven bp_br_type_e encodings:

  NO_BRANCH, COND, DIRECT_UNC, DIRECT_CALL,
  INDIRECT_CALL, INDIRECT_NONRET, RETURN

Write one entry per encoding value, verify each hit returns
the correct br_type. Update the TC6 pass/fail check to
confirm all seven values round-trip correctly.

Apply the same UBTB_BR_* -> bp_br_type_e substitution
everywhere else in the testbench (TC2, any other TC that
references branch type by name).

#### Step 4 -- Run make all and iterate

Run:

  make all

Fix all errors and warnings until exit 0, zero warnings.
Established suppressions from BP-003 remain valid:
  -Wno-IMPORTSTAR in VER_FLAGS
  -Wno-VARHIDDEN on sim_ubtb target only

Do not move to Results Capture until make all is clean.

---

### Constraints

- This is a naming substitution only. Do not change any
  logic, port names, timing behavior, or test stimulus
  values other than branch type encoding references.
- Do not add new Verilator suppressions. If a new warning
  appears, fix the root cause rather than suppressing.
- TC1-TC10 must all continue to pass. The only expected
  change in TC6 output is the encoding names and the
  addition of INDIRECT_CALL and DIRECT_CALL as separate
  test cases (previously collapsed into UBTB_BR_CALL).

---

### Deliverables

1. rtl/bp_pkg.sv  -- UBTB_BR_* removed, uBTB structs
                     updated to use bp_br_type_e
2. rtl/ubtb.sv    -- all UBTB_BR_* refs replaced
3. tb/tb_ubtb.sv  -- TC6 updated and expanded to 7 values
4. Results Capture appended to BP-003.md, clearly marked
   as BP-003-FIX. Include:
   - make all exit code and warning count
   - TC1-TC10 pass/fail (all expected to pass)
   - Any unexpected warnings or issues encountered
   - Confirmation that no logic changes were made

---

## Results Capture

_Written by Claude Code after session completion.
Append to BP-003.md Results Capture section,
marked as BP-003-FIX._

