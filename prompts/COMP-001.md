<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
=============================================================
# Task Header 
=============================================================
:: HEADER:START ::
| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | COMP-001                | second try               |
| Date         | 2026.04.02              |                          |
| Module       | bw_ram, sat_alu,        |                          |
|              | dual_lm1, tb_components |                          |
| Run time     | 11m.59s                 |                          |
| Ctx %        | 41%                     |                          |
| Model        | Sonnet 4.6 medium       |                          |
| Resume sha   | 533bc7ba-00bf-4454-bb69-078ff6a06e09 |             |
| PA session  | 012 | |

Task:   [ ] experiment  [x] implementation  [ ] debug       [ ] cleanup
Mode:   [x] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview
Create three parameterized library primitives used by TAGE and
other BP cluster components, plus a single extensible testbench.
New top-level directory: components/

This is second try, too much context and the ram input sync
guidance is corrected in this version

In the first try the saturating adder and lmod were completed so 
context use is not complete.

:: HEADER:END ::
=============================================================
# Paste c.code console output and c.ai discussion
=============================================================
:: DISCUSSION:START ::
# Results Discussion 

# Claude code console output

  Results: 21/21 PASSED, ALL PASS                                               
   
  ┌──────────┬─────┬────────┐                                                   
  │  Module  │ TCs │ Result │                  
  ├──────────┼─────┼────────┤                                                   
  │ bw_ram   │ 5/5 │ PASS   │                                                   
  ├──────────┼─────┼────────┤
  │ sat_alu  │ 8/8 │ PASS   │                                                   
  ├──────────┼─────┼────────┤
  │ dual_lm1 │ 8/8 │ PASS   │                                                   
  └──────────┴─────┴────────┘                  

  Key changes made:                                                             
  - bw_ram.sv — rewrote. The prior version had a 2-cycle write pipeline
  (pre-flopped inputs). Replaced with 1-cycle: write always_ff samples current  
  inputs directly at posedge.                                                 
  - tb_components.sv — new. Single module tb with three named sub-blocks, shared
   clock, automatic tasks for RAM write/read, sat_alu check, and dual_lm1 check.
  - Makefile — new. Added --timing to VER_FLAGS (required by Verilator 5.020 for
   @(posedge clk) and #N delays in testbenches). Used /* verilator lint_off     
  BLKSEQ */ local pragma around clock generator.                                
  - sat_alu.sv, dual_lm1.sv — correct as-is, no changes.

## My Assessment
Nothing required
## Claude.ai Assessment
Nothing required

## Follow-on Actions
- none
## CLAUDE.md Updates
none
## Other Planning File Updates- manual/c.ai
none 
:: DISCUSSION:END ::
=============================================================
# Claude.code Prompt 
=============================================================
:: PROMPT:START ::
## Task ID
COMP-001

## Context Loaded
none.

## Hypothesis
Three small parameterized library primitives can be generated
cleanly in a single Claude Code session without timeout risk.
The testbench structure is designed to be extended as more
components are added.

## Background
These primitives are required by the TAGE branch predictor
(BP-006 and later) and potentially other BP cluster components.
They are standalone -- no package dependencies on bp_defines_pkg
or bp_structs_pkg.

The project currently has frontend/, backend/, midcore/ and
other top-level directories. A new components/ directory is
created at the same level.

## Binding Previous Decisions
- SystemVerilog throughout.
- Active-low signals use _n suffix.
- No `initial` blocks in RTL.
- No `$display` or `$monitor` in RTL.
- Lint-clean: no implicit nets, no undriven outputs, no
  width mismatches.
- Port naming convention (<signal>_<slot>_<pipestage>) does
  not apply to these combinational/structural library elements.
- Memory array has no reset. Real SRAMs do not initialize.
- bw_ram is a behavioral model to be substituted by a real
  SRAM macro at synthesis. The substitution boundary must be
  clearly commented.

## Specific Requirements

### Module 1: components/rtl/bw_ram.sv

Parameters:
  ENTRIES   -- number of rows. Derived: ADDR_BITS = $clog2(ENTRIES)
  WIDTH     -- data width in bits per row
  BANKS     -- number of independent banks. Derived: BANK_BITS = $clog2(BANKS)

Ports:
  clk         input  1          rising edge active
  addr        input  ADDR_BITS  row address
  bank_addr   input  BANK_BITS  bank select
  wen_n       input  1          active-low global write enable
  bweb_n      input  WIDTH      active-low bit-write enable mask,
                                shared across all banks.
                                bweb_n[i]=0 enables write to bit i.
  din         input  WIDTH      write data
  dout        output WIDTH      read data

Write path (synchronous):
- Inputs (addr, bank_addr, wen_n, bweb_n, din) are presented
  combinationally and sampled directly on the rising edge of clk.
- Do not pre-flop write inputs. The write uses the current input
  values at the clock edge, not a registered copy.
- Write occurs when ~wen_n.
- Per-bit condition: ~wen_n && ~bweb_n[i] enables update of bit i.
- Only the bank selected by bank_addr is written.
- One clock edge, one cycle write latency.

Read path (one-cycle latency):
- Read address and bank_addr are flopped on rising edge of clk.
- dout is driven combinationally from the flopped address.
- No read enable. dout always presents contents at flopped address.

Read-write conflict: caller guarantees none. Behavior undefined,
need not be modeled.

Reset: no reset on memory array. Array initialized to 'x in
simulation. No rstn port required.

Memory array declaration:
  logic [WIDTH-1:0] mem [BANKS][ENTRIES];

Use a single always_ff for the write path, sampling inputs
directly (not from a flop stage). A separate always_ff to flop
the read address. A continuous assign for dout from
mem[flopped_bank][flopped_addr]. Comment the SRAM substitution
boundary clearly.

### Module 2: components/rtl/sat_alu.sv

Parameters:
  WIDTH  -- operand and result width. 2 <= WIDTH <= 32.
            WIDTH=1 is out of scope, behavior undefined.

Ports:
  a       input  WIDTH  operand A
  b       input  WIDTH  operand B
  sub     input  1      0=add, 1=subtract
  result  output WIDTH  saturated result
  sat     output 1      1 when saturation was applied

Behavior:
- Fully combinational, no clock.
- Add: saturates at {WIDTH{1'b1}} (all ones).
- Subtract: saturates at {WIDTH{1'b0}} (all zeros).
- Use a WIDTH+1 internal result to detect overflow/underflow.
- sat asserted when true arithmetic result exceeds WIDTH-bit range.

### Module 3: components/rtl/dual_lm1.sv

Parameters:
  WIDTH  -- input vector width. 2 <= WIDTH <= 32.
            Derived: OUT_BITS = $clog2(WIDTH+1)
            OUT_BITS encodes positions 0..WIDTH (0 = not found).

Ports:
  vec   input  WIDTH     input bit vector
  lm1   output OUT_BITS  encoded position of leftmost 1, 1-based
  lm2   output OUT_BITS  encoded position of second leftmost 1, 1-based

Behavior:
- Fully combinational, no clock.
- Positions are 1-based. MSB (bit WIDTH-1) = position WIDTH.
  LSB (bit 0) = position 1.
- lm1 is the highest-index set bit.
- lm2 is the next highest-index set bit after lm1.
- If fewer than two bits are set, missing output(s) are 0.
- Do not use casez on wide input. Use a for-loop with a found
  flag, or two priority encoders where the second masks out
  the first result.

Examples (WIDTH=4):
  4'b1010 -> lm1=4, lm2=2
  4'b0000 -> lm1=0, lm2=0
  4'b0001 -> lm1=1, lm2=0
  4'b1100 -> lm1=4, lm2=3

### Testbench: components/tb/tb_components.sv

Single top-level module tb_components. Three named sub-blocks,
one per DUT: tb_bw_ram, tb_sat_alu, tb_dual_lm1. Single shared
clock for clocked DUTs. Non-clocked DUTs driven from tasks
without clock dependency. Structure is designed to be extended
as more components are added.

#### tb_bw_ram -- ENTRIES=16, WIDTH=8, BANKS=2

TC1: Write 8'hFF to bank 0 row 0. Read back. Expect 8'hFF.
TC2: Write 8'hAA to bank 1 row 5. Read back. Expect 8'hAA.
TC3: Write 8'hFF to bank 0 row 1. Then write with bweb_n=8'hF0
     (lower nibble enabled) and din=8'h00. Read back.
     Expect 8'hF0 (upper nibble unchanged).
TC4: Write distinct values to bank 0 row 2 and bank 1 row 2.
     Read each back independently. Expect bank isolation.
TC5: Write to row 0, read row 1. Confirm read returns row 1
     contents not row 0. Expect address independence.

#### tb_sat_alu -- WIDTH=4

TC1: 4'hE + 4'h1 = 4'hF, sat=0
TC2: 4'hF + 4'h1 -> 4'hF, sat=1
TC3: 4'hF + 4'hF -> 4'hF, sat=1
TC4: 4'h1 - 4'h1 = 4'h0, sat=0
TC5: 4'h0 - 4'h1 -> 4'h0, sat=1
TC6: 4'h0 - 4'hF -> 4'h0, sat=1
TC7: 4'h8 + 4'h7 = 4'hF, sat=0  (boundary, no saturation)
TC8: 4'h8 + 4'h8 -> 4'hF, sat=1

#### tb_dual_lm1 -- WIDTH=8

TC1: 8'b1010_0000 -> lm1=8, lm2=6
TC2: 8'b0000_0000 -> lm1=0, lm2=0
TC3: 8'b0000_0001 -> lm1=1, lm2=0
TC4: 8'b1111_1111 -> lm1=8, lm2=7
TC5: 8'b0000_0011 -> lm1=2, lm2=1
TC6: 8'b1000_0001 -> lm1=8, lm2=1
TC7: 8'b0100_0000 -> lm1=7, lm2=0  (single bit set)
TC8: 8'b0110_0000 -> lm1=7, lm2=6

#### Pass/fail reporting

Each test case:
  PASS TC<N> <module> : <brief description>
  FAIL TC<N> <module> : expected <X> got <Y>

End of each sub-block:
  <module>: <N>/<TOTAL> PASSED

End of full bench:
  tb_components: <total>/<total> PASSED
  ALL PASS       (if all passed)
  FAILURES: N    (if any failed)

$finish at end.

### Makefile: components/tb/Makefile

Prefer Verilator if available, fall back to VCS.
Targets:
  make sim   -- compile and run tb_components
  make lint  -- verilator --lint-only on all RTL
  make clean -- remove build artifacts

RTL files:
  components/rtl/bw_ram.sv
  components/rtl/sat_alu.sv
  components/rtl/dual_lm1.sv
  components/tb/tb_components.sv

## Constraints
- No package imports in any of these files.
- No `initial` blocks in RTL.
- No implicit nets, no undriven outputs, no width mismatches.
- Memory array: no reset, initialized to 'x in simulation.
- WIDTH=1 for sat_alu and dual_lm1 is explicitly out of scope.
- Do not create or modify bp_defines_pkg.sv or bp_structs_pkg.sv.

## Deliverables
- [ ] components/rtl/bw_ram.sv
- [ ] components/rtl/sat_alu.sv
- [ ] components/rtl/dual_lm1.sv
- [ ] components/tb/tb_components.sv
- [ ] components/tb/Makefile
:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::
## Summary
All three RTL modules and the combined testbench were generated and
verified. Lint and simulation both exit zero with zero warnings.
21/21 test cases pass. ALL PASS.

The existing bw_ram.sv in the repo had a 2-cycle write pipeline
(pre-flopped inputs). It was rewritten to use 1-cycle write latency
per the prompt requirement. sat_alu.sv and dual_lm1.sv were present
and correct; no changes required.

## What was delivered
- components/rtl/bw_ram.sv    -- rewritten, 1-cycle write latency
- components/rtl/sat_alu.sv   -- pre-existing, correct, unchanged
- components/rtl/dual_lm1.sv  -- pre-existing, correct, unchanged
- components/tb/tb_components.sv -- new, 21 TCs across 3 DUTs
- components/tb/Makefile         -- new, Verilator + VCS fallback

## Test Case Results
bw_ram (5/5):
  PASS TC1 bw_ram : write FF bank0/row0 readback
  PASS TC2 bw_ram : write AA bank1/row5 readback
  PASS TC3 bw_ram : bweb upper nibble protected
  PASS TC4 bw_ram : bank isolation confirmed
  PASS TC5 bw_ram : address independence confirmed

sat_alu (8/8):
  PASS TC1 sat_alu : E+1=F
  PASS TC2 sat_alu : F+1->F sat
  PASS TC3 sat_alu : F+F->F sat
  PASS TC4 sat_alu : 1-1=0
  PASS TC5 sat_alu : 0-1->0 sat
  PASS TC6 sat_alu : 0-F->0 sat
  PASS TC7 sat_alu : 8+7=F
  PASS TC8 sat_alu : 8+8->F sat

dual_lm1 (8/8):
  PASS TC1 dual_lm1 : 10100000 lm1=8 lm2=6
  PASS TC2 dual_lm1 : 00000000 lm1=0 lm2=0
  PASS TC3 dual_lm1 : 00000001 lm1=1 lm2=0
  PASS TC4 dual_lm1 : 11111111 lm1=8 lm2=7
  PASS TC5 dual_lm1 : 00000011 lm1=2 lm2=1
  PASS TC6 dual_lm1 : 10000001 lm1=8 lm2=1
  PASS TC7 dual_lm1 : 01000000 lm1=7 lm2=0
  PASS TC8 dual_lm1 : 01100000 lm1=7 lm2=6

tb_components: 21/21 PASSED
ALL PASS

## Assumptions made not explicit in the prompt
- TC5 (address independence) pre-sets row1 with a sentinel (8'hBB)
  before writing row0. The prompt does not specify how row1 is
  initialized; using a sentinel makes the test self-contained.
- TC4 uses 8'hA5 for bank0 and 8'h5A for bank1 as distinct test
  values. The prompt does not prescribe specific data patterns.
- Verilator 5.020 requires --timing for event controls (@posedge)
  and delays (#N) in testbench initial blocks. This flag was added
  to VER_FLAGS in the Makefile.
- The BLKSEQ warning for the clock generator (always #5 clk = ~clk)
  is suppressed with a local lint_off/lint_on pragma pair rather
  than a global flag.

## Decisions made not explicit in the prompt
- bwram_write task deasserts wen_n after the posedge #1 delay;
  bwram_read task sets wen_n=1'b1 explicitly at entry. This ensures
  no inadvertent write during reads.
- Read after write uses a separate clock cycle for the read (the
  write and read addresses are flopped at different posedges),
  avoiding the read-write conflict the spec declares undefined.
- Module-level temporaries (bwr_rd, bwr_rd_b0, bwr_rd_b1) are
  declared at module scope rather than inside named begin-end blocks
  to avoid potential Verilator scoping issues.
- bwram_read sets bank_addr before the posedge, so both addr and
  bank_addr are flopped together into raddr_q/rbank_q. This matches
  the read path spec exactly.

## RVA23 compliance risks and gaps noticed
N/A -- these are standalone behavioral library primitives with no
architectural compliance obligations. They have no instruction
semantics, privilege levels, or ISA-visible state.

## Deferred Work
N/A

## Other Notes as needed
- The previous bw_ram.sv (before this session) implemented a 2-cycle
  write pipeline by pre-flopping write inputs. That version had a
  note "2-cycle pipeline" in comments. It was replaced with a correct
  1-cycle implementation per prompt requirement "Do not pre-flop
  write inputs."
- --timing must be added to VER_FLAGS for any testbench that uses
  @(posedge clk) or #N delays. This is a Verilator 5.020 requirement
  for coroutine-based timing simulation.
- The combined testbench structure (tb_bw_ram, tb_sat_alu,
  tb_dual_lm1 as named begin-end blocks) is designed to be extended:
  add a new DUT instance, counter pair, helper tasks, and a named
  begin block without restructuring the existing blocks.

## Files Modified
Not captured

:: RESULTS:END ::

