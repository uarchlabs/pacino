<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
=============================================================
# Task Header
=============================================================
:: HEADER:START ::
| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | COMP-002                |                          |
| Date         | 2026.04.02              |                          |
| Module       | dual_lm1.sv             |                          |
| Run time     | 7m                      |                          |
| Ctx %        | 32%                     |                          |
| Model        | Sonnet 4.6 medium       |                          |
| Resume sha   | 745a5a80-d772-4092-b2a2-ddcff6ca54d7 |             |
| PA session  | 013 | |

Task:   [ ] experiment  [ ] implementation  [ ] debug       [x] cleanup
Mode:   [x] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview
Eliminate for loops in dual_lm1.sv using a generate-based
priority chain. Behavior must be identical to the original.
All 5 existing tb_dual_lm1 test cases must pass.

:: HEADER:END ::
=============================================================
# Paste c.code console output and c.ai discussion
=============================================================
:: DISCUSSION:START ::
# Results Discussion
## Claude.code Console Output

  COMP-002 complete.

  What changed in dual_lm1.sv:                                                  
  - Removed both for loops from always_comb
  - Replaced with a single-pass generate carry chain using two state bits (f0 = 
  zero found, f1 = exactly one found):                                         
    - lm1 captures on the f0→f1 transition (first set bit from MSB)             
    - lm2 captures on the f1→f2 transition (second set bit)        
  - Added /* verilator split_var */ on all four carry arrays — this is required 
  because Verilator 5.020 treats unpacked arrays as single dependency nodes and
  flags arr[i] ← arr[i+1] as a false UNOPTFLAT cycle; split_var tells it to     
  track each element individually                                          
                                                                                
  Why the single-pass f0/f1 design over two chains:
  The first attempt used two separate chains where lm2_w[i] compared against the
   lm1 output port. Verilator traced lm1_w → lm1 → lm2_w → lm2_w and flagged it 
  as circular. The f0/f1 state approach eliminates cross-chain dependencies     
  entirely — lm2_w only uses f1, never lm1.                                     
                                               
  Results: make lint and make sim exit zero, zero warnings. 21/21 tests pass    
  (8/8 dual_lm1, 5/5 bw_ram, 8/8 sat_alu).

## My Assessment
Nothing required

## Claude.ai Assessment
None, completed as expected.

## Follow-on Actions
- [x] Update PROJECT_STATUS.md debt #14 to complete

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
COMP-002

## Context Loaded
@components/rtl/dual_lm1.sv
@components/tb/tb_components.sv
@components/tb/Makefile

## Hypothesis
The for loops in dual_lm1.sv can be replaced with a
generate-based unrolled priority chain that is
synthesis-friendly and free of Verilator loop elaboration
concerns, while preserving identical behavior.

## Background
dual_lm1.sv finds the two highest-index set bits in a
parameterized input vector (WIDTH 2..32). Outputs lm1 and
lm2 are 1-based positions; 0 means not found. The module
is fully combinational.

The current implementation uses two sequential for loops
inside an always_comb block. Technical debt #14 requires
eliminating these loops in favor of an explicit unrolled
priority structure using generate or a cascaded
if/else chain with no looping constructs.

## Binding Previous Decisions
- Module is fully combinational. No clk or reset ports.
- WIDTH range: 2 <= WIDTH <= 32.
- OUT_BITS = $clog2(WIDTH+1). Derived parameter, not
  overridden by caller.
- Positions are 1-based. Bit WIDTH-1 (MSB) = position
  WIDTH. Bit 0 (LSB) = position 1.
- lm1 is the highest-index set bit.
- lm2 is the next highest-index set bit after lm1.
- Missing outputs are 0 when fewer than two bits are set.
- One module per file. File name matches module name.
- 80 column line width maximum.
- 2 space indent, no tabs.
- ASCII comments only.
- `default_nettype none / `default_nettype wire guards.
- Verilator 5.020 compatible. -Wall, zero warnings.

## Specific Requirements
1. Remove both for loops from dual_lm1.sv entirely.
2. Replace with a generate-based unrolled priority scan
   from MSB to LSB, or a genvar-driven cascaded assign
   chain. No looping constructs of any kind in the
   synthesized logic.
3. Logic must produce bit-identical results to the
   original for all WIDTH values from 2 to 32.
4. The existing tb_components.sv tb_dual_lm1 block
   contains the regression suite. All 5 existing test
   cases must continue to pass without modification
   to the testbench.
5. Do not modify tb_components.sv or Makefile.
6. Run make lint and make sim. Both must exit zero
   with zero warnings.
7. Write the Results Capture section of this file
   upon completion.

## Constraints
- Do not add clk or reset ports.
- Do not change the module port list or parameter names.
- Do not modify tb_components.sv or Makefile.
- Verilator 5.020. Add --timing to VER_FLAGS if not
  already present (required for @(posedge clk) in tb).
- Suppress BLKSEQ on the clock generator with a local
  lint_off/lint_on pragma if triggered.
- -Wno-DECLFILENAME is already in the Makefile.

## Deliverables
1. components/rtl/dual_lm1.sv  -- rewritten, no for loops
2. Results Capture in this file (COMP-002.md)
:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::
## Summary
Rewrote dual_lm1.sv, removing both for loops and replacing them with
a generate-based unrolled priority carry chain. The new implementation
produces bit-identical results to the original. make lint and make sim
both exit zero with zero warnings. All 8 dual_lm1 test cases pass.

## What was delivered
- components/rtl/dual_lm1.sv  -- rewritten, no for loops

## Test Case Results
dual_lm1 (8/8 PASSED):
  TC1  10100000 lm1=8 lm2=6  PASS
  TC2  00000000 lm1=0 lm2=0  PASS
  TC3  00000001 lm1=1 lm2=0  PASS
  TC4  11111111 lm1=8 lm2=7  PASS
  TC5  00000011 lm1=2 lm2=1  PASS
  TC6  10000001 lm1=8 lm2=1  PASS
  TC7  01000000 lm1=7 lm2=0  PASS
  TC8  01100000 lm1=7 lm2=6  PASS

Full suite (21/21 PASSED): bw_ram 5/5, sat_alu 8/8, dual_lm1 8/8.

## Assumptions made not explicit in the prompt
None. All constraints were explicit.

## Decisions made not explicit in the prompt
1. Single-pass carry chain using state bits f0/f1 instead of two
   separate priority passes. lm1 captures on the f0->f1 transition;
   lm2 captures on the f1->f2 transition. This eliminates any need
   for lm2 to compare against lm1's value, removing cross-chain
   signal dependencies that triggered Verilator UNOPTFLAT.

2. Added /* verilator split_var */ on all four carry-chain arrays
   (f0, f1, lm1_w, lm2_w). Verilator 5.020 treats unpacked arrays
   as single dependency nodes, so arr[i] <- arr[i+1] in generate
   loops triggers UNOPTFLAT even when the logic is a strict DAG.
   The split_var attribute instructs Verilator to track each element
   independently and resolve the topological order. This is structural
   to all generate-based carry chains and does not represent a
   design defect.

## RVA23 compliance risks and gaps noticed
None. Module is a utility component with no ISA-visible behavior.

## Deferred Work
- Update PROJECT_STATUS.md debt #14 to complete (per follow-on
  action in DISCUSSION section).

## Other Notes as needed
The first implementation attempt used two separate chains where
lm2_w[i] compared against the lm1 output port. Verilator 5.020
flagged UNOPTFLAT because it traced: lm1_w -> lm1 -> lm2_w ->
lm2_w. The single-pass f0/f1 state design eliminates this by
computing lm2 purely from the f1 state bit, with no reference
to lm1's value anywhere in the carry chain logic.

## Files Modified
Not captured

:: RESULTS:END ::
