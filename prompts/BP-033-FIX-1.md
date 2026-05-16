=============================================================
# Task Header
=============================================================
:: HEADER:START ::
| Field      | Value               | Notes              |
|------------|---------------------|--------------------|
| Task ID    | BP-033-FIX-1        |                    |
| Date       | 2026.04.29          |                    |
| Module     | ittage_table        |                    |
| Run time   | 41m.33s             |                    |
| Ctx %      | 83% w/ compaction   |                    |
| Model      | Sonnet 4.6 medium   |                    |
| Resume sha | cdc3901b-6ef5-4e72-84be-2d3b76bc87e6 |   |
Task:   [ ] experiment  [x] implementation  [ ] debug
        [ ] cleanup     [x] testbench       [ ] verification
Status: [ ] in-progress [x] complete        [ ] abandoned

# Overview of task

Re-implementation of BP-033. Prior attempt produced correlated
RTL and testbench errors: ittage_pred_val_p0[s] was used to
gate hit_p1[s], violating pipeline stage semantics. The
testbench did not catch this because expected values were not
specified in the prompt -- Claude Code wrote tests that
matched its own RTL rather than the spec.

This prompt pins all test case expected values to the spec
before any code is written.
:: HEADER:END ::

=============================================================
# Paste c.code console output and c.ai discussion
=============================================================
:: DISCUSSION:START ::
# Results Discussion
## Claude.code Console Output

 - rtl/core/frontend/bpu/rtl/ittage_table.sv — Parameterized ITTAGE table using
   tage_table.sv as structural template. Entry layout VAL CTR USE EPC TGT TAG   
  (LSB-first). USE/EPC gated by prm_match only; tgt_we gated by (prm|alt)_match 
  and included in norm_we. pred_tgt_p1 replaces taken_p1. ittage_pred_val_p0    
  absent from hit/read path. fh_sel cases 1–5 only. Fast init via               
  +ITTAGE_FAST_INIT=1.
  - rtl/core/frontend/bpu/tb/tb_ittage_table.sv — Self-checking testbench, IT1
  parameters, folded_hist=0. 12 test cases, 32 checks, 32/32 PASS, 0 FAIL.      
  - rtl/core/frontend/bpu/Makefile — lint_ittage_table and sim_ittage_table
  targets added; obj_ittage_table added to clean.                               
  - prompts/BP-033-FIX-1.md — Results Capture filled in.

※ recap: BP-033-FIX-1 implemented ittage_table.sv with its testbench, all 32    
  simulation checks passed with zero lint warnings. The Makefile and Results    
  Capture are complete; no further action needed unless the next experiment     
  prompt is ready. (disable recaps in /config)  

## My Assessment

There is some question as to whether c.code thought ram init can occur
at any time. 

This:
```
2. For TC-TBL-RI write cycle, slot 0 predict PC driven as PC_A
   (idle/don't-care). This avoids read-write conflict to 0x30
   since addr_mux selects tbl_ri_wa during that cycle.
```

This needs to be verified whether the design assumed tbl_ri_wa is
active at any time. 

ME: does your design assume tbl_ri_wa can assert after the first 
    ittage_pred_val_p0 ?

This question was poorly phrased by me, but the answer was:
```
  The design relies on a protocol assumption: sram_init completes before any    
  ittage_pred_val_p0 is asserted. This is consistent with the interface spec
  statement that "there is no case where tbl_ri_wr and the other write signals  
  are asserted." The testbench enforces this — TC-TBL-RI runs as a standalone
  operation with tbl_ri_active deasserted before any prediction cycle begins.
```

This is acceptable. (note another compaction occur while answering this
question.

>  does the test bench execise both prediction slots ? 

No, not fully. Slot 1 is exercised in only two test cases:

This is acceptable now, we will improve testcases during line coverage.

You use the terms allocation and prediction

```
3. Separate alloc and predict cycles used throughout to avoid
   bw_ram read-write conflict at the same address.
```

do you exercise the update path, ittage_upd_val_u0 ? why did you specify 
allocation and prediction i would expect update and prediction.

Response was:

```
● You're right on both counts.

  ittage_upd_val_u0 is exercised — it gates every write in the testbench.       
  TC-PRM-CTR, TC-ALT-CTR, TC-USE-EPC, and TC-TGT-WR all assert it alongside the
  specific update enables (prm_ctr_wr_u0, alt_ctr_wr_u0, use_wr_u0/epc_wr_u0,   
  tgt_wr_u0). It's also asserted during alloc writes (alc_wr_u0) in
  TC-ALLOC-HIT, TC-ALC-GATE, TC-PRM-GATE, and TC-DUAL.

  The statement was imprecise. The addr_mux conflict applies to any write that  
  hits the same index as the prediction — both alc_we and norm_we override
  idx_hash when they assert. The pattern used throughout is: write cycle        
  (whether alloc or update), then a separate predict cycle. The statement should
   have read:

  ▎ "Separate write and predict cycles used throughout to avoid bw_ram
  ▎ read-write conflict at the same address."

  Using "alloc and predict" implied the separation only matters for allocation, 
  which is wrong — it applies equally to every norm_we update. I'll correct the
  Results Capture.                                                              
                                             
  Read 1 file (ctrl+o to expand)    
                            
● Correct on both counts. ittage_upd_val_u0 is exercised — it gates every write
  in the testbench, both alloc (alc_wr_u0) and update (prm_ctr_wr_u0,           
  alt_ctr_wr_u0, use_wr_u0, epc_wr_u0, tgt_wr_u0). The statement was imprecise. 
  Fixing it now.  
```

c.code modified the results portion I quoted to be this:

```
3. Separate write and predict cycles used throughout to avoid
   bw_ram read-write conflict at the same address. Applies to
   both alloc writes (alc_we) and update writes (norm_we).
   ittage_upd_val_u0 is asserted in every write cycle including
   pure update cycles (TC-PRM-CTR, TC-ALT-CTR, TC-USE-EPC,
   TC-TGT-WR, TC-ALC-GATE, TC-PRM-GATE).
```

Other comments:

- This prompt included too much work, we need to scope these to avoid
issues with compaction where possible. This could have been split
between design and testbench.

However preliminary inspection does not uncover any issues.
ittage_table seems to be implemented as intended.

- There is a nagging formatting problem that modifying CLAUDE.md did not help. 
"                Declare ports on one line when they fit within 80 cols"

- We need to find some pass/fail verilog formatting tool with sufficient
control to enforce otherwise legal SV.

## Claude.ai Assessment

Clean result. 32/32, lint clean, 41 minutes. The critical test TC-PRED-VAL-ZERO passed, confirming the p0/p1 gating bug is fixed.
Claude.ai Assessment
The prompt worked. Pre-computing expected values in the Test Vector Table is now a confirmed methodology requirement — it directly prevented the correlated bug from surviving.
Two things worth capturing from Jeff's assessment:
Prompt scope. 83% context with compaction on a single implementation+testbench task is too high. The prompt should have been split: one task for the RTL (no testbench), one task for the testbench (reads the completed RTL). This also has the benefit that the testbench author reads finished RTL rather than writing in parallel with it, which is a weaker form of the same correlated-bug risk. Add this to methodology conventions.
Terminology: allocation vs update. Claude Code used "alloc and predict" where "write and predict" was correct. The distinction matters because it implies separation only applies to allocation. The correct framing — write cycle (whether alc_we or norm_we) and predict cycle are kept separate — should be added to the testbench section of future prompts as a one-line constraint. It is too easy to get wrong.
Follow-on actions I'd add:

Methodology: split implementation and testbench into separate tasks when combined context risk exceeds ~50%

This was retracted in conversation: Add "write cycle and predict cycle must be separated" as a standard testbench constraint"
this already exists in the context supplied to c.code (IA)

Also retracted: "Research verible-verilog-format for SV formatting — artistic-style does not support SV"
unclear if AS supports verilog edit: it does but has trouble with systemverilog
recommendation is Verible: https://github.com/chipsalliance/verible

## Follow-on Actions
- [x] Research formatting tools, does `artistic-style` support verilog ? No
- [x] Research Verible consider integration
## CLAUDE.md Updates
None
## Other Planning File Updates
None

:: DISCUSSION:END ::

=============================================================
# Claude.code Prompt
=============================================================
:: PROMPT:START ::
## Task ID

BP-033-FIX-1

## Context Loaded

@planning/interfaces/ittage_table_interfaces.md
@planning/arch/ittage_table_hash_rules.md
@rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
@rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
@rtl/lib/rtl/bw_ram.sv
@rtl/lib/rtl/sram_init.sv
@rtl/core/frontend/bpu/rtl/tage_table.sv
@rtl/core/frontend/bpu/Makefile

## Hypothesis

Implementing ittage_table.sv using tage_table.sv as a
structural template, adapted for ITTAGE-specific differences
(TGT field, confidence CTR, no T0, prm-only USE/EPC gating,
tgt_wr path), will produce a lint-clean module that passes a
self-checking testbench whose expected outputs are fully
derived from the spec before any RTL is written.

## Background

ITTAGE is an indirect target predictor. It has five tagged
tables IT1-IT5. There is no base table (no IT0). Each table
instance is ittage_table, structurally similar to tage_table
with these differences:

- Entry adds a 38-bit TGT field between EPC and TAG.
- CTR is a confidence counter, not a direction predictor.
  hit_p1 is still produced; taken_p1 is not. The predicted
  target is output as pred_tgt_p1.
- All five tables use folded history (cases 1-5 in fh_sel).
  There is no direct PC index path.
- Folded history field names in bp_folded_hist_t are
  it_tN_idx_fh, it_tN_tag_fh1, it_tN_tag_fh2 (N = 1-5).
- USE and EPC writes are gated by prm_match only.
  In tage_table they were gated by (prm_match | alt_match).
- prm_ctr_wr_u0 and alt_ctr_wr_u0 are mutually exclusive
  per slot. ITTAGE never asserts both in the same cycle.
- tgt_wr_u0 is asserted on misprediction when provider CTR
  was null. The table gates it by (prm_match | alt_match)
  and uses upd_index_u0 as the write address.

The dual-slot RAM structure (u_ram_s0 / u_ram_s1, BANKS=2,
bank_addr from index MSB) is identical to tage_table.

## Binding Previous Decisions

1. Entry field order LSB to MSB: VALID CTR USE EPC TGT TAG.
   TGT sits between EPC and TAG. Only TAG width varies
   across IT1-IT5.

2. CNTRL_BITS_WIDTH = IT_MAX_VAL_WIDTH + IT_MAX_CTR_WIDTH
   + IT_MAX_USE_WIDTH + IT_MAX_EPC_WIDTH + IT_MAX_TGT_WIDTH
   = 1 + 3 + 2 + 2 + 38 = 46 bits.
   Uses IT_MAX_ widths to produce a fixed-width bus.

3. ALLOC_DATA_WIDTH = CNTRL_BITS_WIDTH + THIS_TAG_BITS.
   For IT1/IT2: 46 + 8 = 54 bits.

4. cntrl_bits_p1 layout (bit 0 = VAL):
     [0]      VAL
     [3:1]    CTR   (CB_CTR_H = IT_MAX_CTR_WIDTH = 3)
     [5:4]    USE   (CB_USE_H = 5)
     [7:6]    EPC   (CB_EPC_H = 7)
     [45:8]   TGT   (CB_TGT_H = 45)
   TGT is mirrored into cntrl_bits_p1 so ittage_cntrl can
   read both target and metadata from one bus.

5. pred_tgt_p1[IT_MAX_TGT_WIDTH-1:0] replaces taken_p1.
   Assign directly from ram_dout TGT field, zero-extended.

6. alc_tbl_sel == 0 is the no-alloc sentinel (same as TAGE).
   IT0 is never instantiated.

7. tgt_we participates in norm_we and uses upd_index_u0
   as the RAM write address (same index as CTR/USE/EPC).

8. Fast init: plusarg ITTAGE_FAST_INIT, constant
   IT_SRAM_INIT_VALUE. Pattern identical to tage_table.

9. Input struct is ittage_pred_inp_t, not tage_pred_inp_t.
   Port prefixes use ittage_ not tage_.

10. TBL_SEL_WIDTH defaults to IT_TBL_SEL_WIDTH
    = $clog2(IT_NUM_TABLES) = $clog2(6) = 3.

11. hit_p1[s] is derived solely from ram_dout and
    tag_hash_p1. It is not gated by ittage_pred_val_p0[s].
    ittage_pred_val_p0[s] gates write-enables only, via
    ittage_upd_val_u0 -- it does not appear on the read
    or hit path. Read tage_table.sv hit_p1 assign and
    replicate exactly, substituting the TGT-extended
    entry layout.

## Specific Requirements

1. Read all context files before writing any code.

2. Before writing any RTL or testbench, work through the
   test vector table in the Testbench section below and
   confirm each expected value is consistent with the
   spec. Do not proceed until this is done.

3. Implement rtl/core/frontend/bpu/rtl/ittage_table.sv.
   a. Use tage_table.sv as the structural template.
   b. Module and port names follow
      ittage_table_interfaces.md exactly.
   c. fh_sel always_comb covers cases 1 through 5 only.
      Default assigns all fh signals to zero. No case 0.
   d. idx_hash and tag_hash use the formulas in
      ittage_table_hash_rules.md. No ternary for T0.
   e. All write-enables for each slot in a single
      always_comb block (same HAND-FIX-001 pattern as
      tage_table) to avoid evaluation-order issues.
   f. USE and EPC gated by prm_match only.
   g. tgt_we gated by (prm_match | alt_match).
      tgt_we included in norm_we.
   h. addr_mux priority: tbl_ri_active > alc_we > norm_we
      > idx_hash. Identical to tage_table.
   i. din_mux: prm_ctr and alt_ctr are if/else-if.
      use, epc, tgt are independent if blocks within
      the norm update branch.
   j. bweb_mux: enable TGT bits when tgt_we asserted,
      same per-bit loop pattern used for CTR/USE/EPC.
   k. cntrl_out always_comb fills cntrl_bits_p1 at the
      CB_ positions in decision 4. Include TGT at
      [CB_TGT_H:CB_EPC_H+1].
   l. hit_p1[s] assign: copy tage_table.sv hit_p1 assign
      verbatim, adjusting only field positions for the
      ITTAGE entry layout. ittage_pred_val_p0 must not
      appear anywhere on the hit or read path.

4. Implement rtl/core/frontend/bpu/tb/tb_ittage_table.sv.
   a. Instantiate with IT1 parameters (THIS_TABLE=1,
      THIS_INDEX_BITS=8, THIS_TAG_BITS=8).
   b. Drive folded_hist=0 throughout.
   c. Use +ITTAGE_FAST_INIT=1 to pre-initialize RAMs.
   d. Include a timed reset sequence before test cases.
   e. Write check() and check_w() tasks for 1-bit and
      wide signal comparison with PASS/FAIL reporting.
   f. Implement the test cases from the Test Vector Table
      below exactly as specified. Expected values are
      fixed -- do not derive them from the RTL.
   g. Add #1 after each @(posedge clk) before sampling
      outputs (Verilator NBA scheduling requirement for
      always_ff non-blocking assignments).
   h. Print total PASS and FAIL counts. Call $finish.
   i. Include a timeout watchdog.

5. Run Verilator lint. Fix all errors and warnings.

6. Run simulation. All checks must pass. If a check
   fails, fix the RTL -- do not adjust the expected
   value in the testbench.

7. Add sim_ittage_table target to the Makefile consistent
   with existing sim_* target conventions.

## Test Vector Table

All vectors use folded_hist=0, IT1 parameters:
  IDX_BITS=8, TAG_BITS=8, INST_OFFSET=2.

Hash formulas:
  idx_hash = (pc >> 2)[7:0]
  tag_hash = (pc >> 8)[7:0], zero-extended to 11b

PC vectors and pre-computed hashes:
  PC_A = 40'h00_0000_1040 -> idx=8'h10  tag=8'h10
  PC_B = 40'h00_0000_2040 -> idx=8'h10  tag=8'h20
  PC_C = 40'h00_0000_0140 -> idx=8'h50  tag=8'h01
  PC_D = 40'h00_0000_00C0 -> idx=8'h30  tag=8'h00
  PC_E = 40'h00_0000_0080 -> idx=8'h20  tag=8'h00

Entry encoding (LSB first): {tag, tgt, epc, use, ctr, val}

Test cases and required expected values:

TC-HASH: Combinational hash verification (no clock)
  Drive PC_A on slot 0, PC_C on slot 1.
  Expected: idx_hash_p0[0]=8'h10, tag_hash_p0[0]=11'h010
            idx_hash_p0[1]=8'h50, tag_hash_p0[1]=11'h001

TC-ALLOC-HIT: Allocate at idx=8'h10 (PC_A), predict hit
  alc_wd = {8'h10, 38'h55, 2'b10, 2'b01, 3'b100, 1'b1}
  (tag=0x10, tgt=0x55, epc=2, use=1, ctr=4, val=1)
  Predict with PC_A, pred_val[0]=1.
  Expected: hit_p1[0]=1, pred_tgt_p1[0]=38'h55
            cntrl_bits_p1[0][0]=1 (val)
            cntrl_bits_p1[0][3:1]=3'b100 (ctr=4)
            cntrl_bits_p1[0][5:4]=2'b01  (use=1)
            cntrl_bits_p1[0][7:6]=2'b10  (epc=2)
            cntrl_bits_p1[0][45:8]=38'h55 (tgt)

TC-PRED-VAL-ZERO: pred_val=0 does not suppress hit_p1
  Entry from TC-ALLOC-HIT still loaded at idx=8'h10.
  Predict with PC_A, ittage_pred_val_p0[0]=0.
  Expected: hit_p1[0]=1
  Rationale: hit_p1 is a p1 output derived from ram_dout
  and tag_hash_p1 only. pred_val_p0 is a p0 signal and
  does not appear on the hit path.

TC-TAG-MISS: Tag miss same index
  Entry at idx=8'h10 has tag=8'h10.
  Predict with PC_B (idx=8'h10, tag=8'h20).
  Expected: hit_p1[0]=0

TC-PRM-CTR: prm_ctr_wr update, read back
  Update idx=8'h10 via prm path: prm_tbl_sel=1, ctr_wd=3'b111.
  Predict with PC_A.
  Expected: hit_p1[0]=1, cntrl_bits_p1[0][3:1]=3'b111

TC-ALT-CTR: alt_ctr_wr update, read back
  Allocate at idx=8'h50 (PC_C):
    alc_wd={8'h01, 38'hAA, 2'b00, 2'b00, 3'b100, 1'b1}
  Update via alt path: alt_tbl_sel=1, ctr_wd=3'b010.
  Predict with PC_C.
  Expected: hit_p1[0]=1, cntrl_bits_p1[0][3:1]=3'b010

TC-USE-EPC: use_wr and epc_wr via prm path, read back
  Update idx=8'h10: prm_tbl_sel=1, use_wd=2'b11, epc_wd=2'b01.
  Predict with PC_A.
  Expected: hit_p1[0]=1
            cntrl_bits_p1[0][5:4]=2'b11 (use)
            cntrl_bits_p1[0][7:6]=2'b01 (epc)

TC-TGT-WR: tgt_wr target replacement, read back
  Update idx=8'h10: prm_tbl_sel=1, tgt_wd=38'h1234.
  Predict with PC_A.
  Expected: hit_p1[0]=1, pred_tgt_p1[0]=38'h1234
            cntrl_bits_p1[0][45:8]=38'h1234

TC-ALC-GATE: Wrong alc_tbl_sel blocked
  Attempt alc at idx=8'h50 with alc_tbl_sel=2 (not 1).
  Predict with PC_C (would hit if write went through).
  Expected: hit_p1[0] reflects prior state (no new alloc)

TC-PRM-GATE: Wrong prm_tbl_sel blocked
  Attempt prm_ctr_wr at idx=8'h10 with prm_tbl_sel=3,
  ctr_wd=3'b000.
  Predict with PC_A.
  Expected: cntrl_bits_p1[0][3:1] unchanged from TC-PRM-CTR
            (still 3'b111)

TC-TBL-RI: tbl_ri write path, predict hit
  Write via tbl_ri to idx=8'h30:
    tbl_ri_wd={8'h00, 38'hCC, 2'b11, 2'b01, 3'b110, 1'b1}
    (tag=0x00, tgt=0xCC, epc=3, use=1, ctr=6, val=1)
  Predict with PC_D (idx=8'h30, tag=8'h00).
  Expected: hit_p1[0]=1, pred_tgt_p1[0]=38'hCC
            cntrl_bits_p1[0][3:1]=3'b110

TC-DUAL: Slot 0 and slot 1 simultaneous, independent data
  Alloc slot 0 at idx=8'h20 (PC_E):
    alc_wd={8'h00, 38'hAA, 2'b01, 2'b01, 3'b101, 1'b1}
  Alloc slot 1 at idx=8'h20 (PC_E):
    alc_wd={8'h00, 38'hBB, 2'b10, 2'b10, 3'b010, 1'b1}
  Predict both slots with PC_E, pred_val=2'b11.
  Expected: hit_p1[0]=1, pred_tgt_p1[0]=38'hAA
            hit_p1[1]=1, pred_tgt_p1[1]=38'hBB

## Constraints

- Default parameters must reflect IT1:
  THIS_TABLE=1, THIS_INDEX_BITS=8, THIS_TAG_BITS=8,
  THIS_CTR_WIDTH=IT_MAX_CTR_WIDTH,
  THIS_USE_WIDTH=IT_MAX_USE_WIDTH,
  THIS_EPC_WIDTH=IT_MAX_EPC_WIDTH,
  THIS_TGT_WIDTH=IT_MAX_TGT_WIDTH.
- Scope is ittage_table only. Do not implement any module
  above this level.
- tbl_ri signals are shared; do not create per-slot
  variants.
- Testbench module must be named tb.
- If a test fails, fix the RTL. Do not change expected
  values in the testbench.

## Deliverables

1. rtl/core/frontend/bpu/rtl/ittage_table.sv
2. rtl/core/frontend/bpu/tb/tb_ittage_table.sv
3. rtl/core/frontend/bpu/Makefile (updated)
4. prompts/BP-033-FIX-1.md with Results Capture filled
   in below.

Results Capture filled in below.

:: PROMPT:END ::

=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::
## Summary
ittage_table.sv implemented using tage_table.sv as structural
template with ITTAGE-specific adaptations: TGT field in entry
layout, confidence CTR semantics, fh_sel cases 1-5 only, USE/EPC
gated by prm_match only, tgt_we gated by (prm|alt)_match, and
pred_tgt_p1 output replacing taken_p1. Testbench validated all
12 test cases. 32/32 checks pass. Zero lint warnings.

## Test Matrix

TC-HASH
- Rule: ittage_table_hash_rules.md index/tag hash formulas
- Setup: folded_hist=0, IT1 parameters
- Stimulus: PC_A on slot 0, PC_C on slot 1
- Expected: idx=0x10,tag=11'h010 (slot 0); idx=0x50,tag=11'h001 (slot 1)
- Result: PASS (4 checks)

TC-ALLOC-HIT
- Rule: Entry layout decision 1/2; alc_tbl_sel gating decision 6
- Setup: RAM zeroed via ITTAGE_FAST_INIT
- Stimulus: alc_wr[0]=1, alc_tbl_sel=1, alc_index=0x10
  alc_wd={tag=0x10,tgt=0x55,epc=2,use=1,ctr=4,val=1}
- Expected: hit=1, pred_tgt=0x55, cntrl_bits fields match entry
- Result: PASS (7 checks)

TC-PRED-VAL-ZERO
- Rule: Decision 11 -- ittage_pred_val_p0 absent from hit/read path
- Setup: Entry from TC-ALLOC-HIT at idx=0x10
- Stimulus: PC_A, ittage_pred_val_p0[0]=0
- Expected: hit_p1[0]=1 (pred_val has no effect on hit path)
- Result: PASS (1 check)

TC-TAG-MISS
- Rule: hit_p1 tag compare logic requirement l
- Setup: Entry at idx=0x10 with tag=0x10
- Stimulus: PC_B (idx=0x10, tag=0x20)
- Expected: hit_p1[0]=0
- Result: PASS (1 check)

TC-PRM-CTR
- Rule: prm_ctr_wr gated by prm_match; CTR bweb pattern
- Setup: Entry at idx=0x10 from TC-ALLOC-HIT
- Stimulus: prm_ctr_wr[0]=1, prm_tbl_sel=1, ctr_wd=3'b111
- Expected: hit=1, cntrl_bits[3:1]=7
- Result: PASS (2 checks)

TC-ALT-CTR
- Rule: alt_ctr_wr gated by alt_match; mutual exclusion
- Setup: Alloc at idx=0x50 first; then alt CTR update
- Stimulus: alt_ctr_wr[0]=1, alt_tbl_sel=1, ctr_wd=3'b010
- Expected: hit=1, cntrl_bits[3:1]=2
- Result: PASS (2 checks)

TC-USE-EPC
- Rule: USE/EPC gated by prm_match only (not prm|alt)
- Setup: Entry at idx=0x10 (CTR=7 from TC-PRM-CTR)
- Stimulus: use_wr[0]=1, epc_wr[0]=1, prm_tbl_sel=1
  use_wd=3, epc_wd=1
- Expected: hit=1, cntrl_bits[5:4]=3, cntrl_bits[7:6]=1
- Result: PASS (3 checks)

TC-TGT-WR
- Rule: tgt_we gated by (prm|alt)_match; TGT bweb pattern
- Setup: Entry at idx=0x10 (USE=3,EPC=1 from TC-USE-EPC)
- Stimulus: tgt_wr[0]=1, prm_tbl_sel=1, tgt_wd=38'h1234
- Expected: hit=1, pred_tgt=0x1234, cntrl_bits[45:8]=0x1234
- Result: PASS (3 checks)

TC-ALC-GATE
- Rule: alc_match requires alc_tbl_sel==THIS_TABLE and !=0
- Setup: Entry at idx=0x50 from TC-ALT-CTR (tag=0x01)
- Stimulus: alc_wr[0]=1, alc_tbl_sel=2 (wrong), PC_C predict
- Expected: hit_p1[0]=1 (prior entry intact, blocked write)
- Result: PASS (1 check)

TC-PRM-GATE
- Rule: prm_match check gates CTR write
- Setup: Entry at idx=0x10 (CTR=7 from TC-PRM-CTR, unchanged)
- Stimulus: prm_ctr_wr[0]=1, prm_tbl_sel=3 (wrong), ctr_wd=0
- Expected: cntrl_bits[3:1]=7 (unchanged)
- Result: PASS (1 check)

TC-TBL-RI
- Rule: tbl_ri_active overrides all writes; shared to both RAMs
- Setup: Both slot RAMs targeted at idx=0x30
- Stimulus: tbl_ri_active=1, tbl_ri_wa=0x30
  tbl_ri_wd={tag=0x00,tgt=0xCC,epc=3,use=1,ctr=6,val=1}
- Expected: hit=1, pred_tgt=0xCC, cntrl_bits[3:1]=6
- Result: PASS (3 checks)

TC-DUAL
- Rule: u_ram_s0/u_ram_s1 are independent; simultaneous writes OK
- Setup: Both slots allocate at idx=0x20 in same cycle
- Stimulus: alc_wr=2'b11, alc_tbl_sel=1 both, PC_E both slots
  alc_wd[0]={tag=0x00,tgt=0xAA,...}, alc_wd[1]={tag=0x00,tgt=0xBB,...}
- Expected: hit[0]=1,pred_tgt[0]=0xAA; hit[1]=1,pred_tgt[1]=0xBB
- Result: PASS (4 checks)

## What was delivered

1. rtl/core/frontend/bpu/rtl/ittage_table.sv
   - Parameterized ITTAGE tagged table
   - Entry layout: VAL CTR USE EPC TGT TAG (LSB to MSB)
   - CNTRL_BITS_WIDTH=46 using IT_MAX_ widths
   - fh_sel cases 1-5; no case 0
   - USE/EPC gated by prm_match only
   - tgt_we gated by (prm_match | alt_match), in norm_we
   - pred_tgt_p1 assigned from TGT field of ram_dout
   - ittage_pred_val_p0 not on hit or read path
   - Fast init via +ITTAGE_FAST_INIT=1 plusarg

2. rtl/core/frontend/bpu/tb/tb_ittage_table.sv
   - IT1 parameters, folded_hist=0
   - check() and check_w() tasks (name, got, exp order)
   - Timeout watchdog at 100000 time units
   - 12 test cases, 32 checks, all PASS

3. rtl/core/frontend/bpu/Makefile
   - lint_ittage_table and sim_ittage_table targets added
   - sim_ittage_table runs with +ITTAGE_FAST_INIT=1
   - obj_ittage_table added to clean target

## Test Case Results

All 32 checks passed. FAIL: 0.

## Assumptions made not explicit in the prompt

1. For TC-ALC-GATE, "reflects prior state" means hit_p1[0]=1
   since the existing TC-ALT-CTR entry at idx=0x50 has tag=0x01
   which matches PC_C's tag. Test checks hit=1.

2. For TC-TBL-RI write cycle, slot 0 predict PC driven as PC_A
   (idle/don't-care). This avoids read-write conflict to 0x30
   since addr_mux selects tbl_ri_wa during that cycle.

3. Separate write and predict cycles used throughout to avoid
   bw_ram read-write conflict at the same address. Applies to
   both alloc writes (alc_we) and update writes (norm_we).
   ittage_upd_val_u0 is asserted in every write cycle including
   pure update cycles (TC-PRM-CTR, TC-ALT-CTR, TC-USE-EPC,
   TC-TGT-WR, TC-ALC-GATE, TC-PRM-GATE).

## Decisions made not explicit in the prompt

1. INST_OFFSET taken directly from bp_defines_pkg (no local
   redeclaration) to avoid -Wno-VARHIDDEN requirement for that
   constant specifically.

2. check/check_w tasks use (name, got, exp) argument order to
   match Verilator's behavior with string literals as first arg.

3. Clock generator uses initial/forever idiom rather than
   always block to avoid Verilator -Wall BLKSEQ warning.

## RVA23 compliance risks and gaps noticed

No new risks. ittage_table operates below the architectural
interface level. TGT is 38 bits (upper bits of Sv39 VA, bit 0
not stored), consistent with RVA23 Sv39 alignment requirement.

## Deferred Work

None within scope. Higher-level modules (ittage_cntrl, ittage)
not in scope for this experiment.

## Other Notes

CNTRL_BITS_WIDTH = 46 (1+3+2+2+38). For IT1-IT5 all tables
share the same CTR/USE/EPC/TGT widths (IT_MAX_ values), so
TAG_LSB = CNTRL_BITS_WIDTH = 46 is consistent across all instances.
:: RESULTS:END ::

