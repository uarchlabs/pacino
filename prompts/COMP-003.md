=============================================================
# Task Header
=============================================================
:: HEADER:START ::
| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | COMP-003                |                          |
| Date         | 2026.04.02              |                          |
| Module       | sram_init.sv            |                          |
| Run time     | 12m.9s                  |                          |
| Ctx %        | 40%                     |                          |
| Model        | Sonnet 4.6 medium       |                          |
| Resume sha   | 15d40762-3f61-4878-9f32-3bad4afe8c46 |             |
Task:   [ ] experiment  [x] implementation  [ ] debug       [ ] cleanup
Status: [ ] in-progress [x] complete        [ ] abandoned

# Overview of task  - manual/c.ai
Implement sram_init.sv, a parameterized SRAM initialization
component. On de-assertion of rstn it optionally waits a
start delay then walks all SRAM entries writing a fixed init
value, then asserts ready and holds until reset.
:: HEADER:END ::
=============================================================
# Paste c.code console output and c.ai discussion
=============================================================
:: DISCUSSION:START ::
# Results Discussion
## Claude.code Console Output

  components/rtl/sram_init.sv — new module
  - Four-state enum FSM: PENDING → (DELAY) → INIT → DONE
  - DELAY skipped when START_DELAY == 0; delay counter is 8-bit counting down
  from START_DELAY
  - cs, wr, active are combinatorial outputs of state (asserted only in INIT)
  - wdata tied to INIT_VAL at all times; ready registered, set on INIT→DONE
  transition
  - One lint fix needed: ADDR_BITS'(NUM_ENTRIES-1) cast on LAST_ADDR to avoid
  WIDTHTRUNC

  components/tb/tb_components.sv — updated
  - Two sram_init instantiations (DUT A: no delay; DUT B: 3-cycle delay)
  - si_a_check / si_b_check helper tasks
  - 13 directed test cases covering DELAY cycles, all INIT waddr values, and
  DONE state

  components/Makefile — sram_init.sv added to RTL_FILES

  Results: make lint and make sim both exit 0, zero warnings. 34/34 PASSED (21
  pre-existing + 13 new).

## Claude.ai Assessment
## Follow-on Actions
- [ ] Add sram_init row to MODULE_STATUS table in
      PROJECT_STATUS.md
## CLAUDE.md Updates
TBD
## Other Planning File Updates
TBD
:: DISCUSSION:END ::
=============================================================
# Claude.code Prompt
=============================================================
:: PROMPT:START ::
## Context Loaded
## Context Loaded
@components/tb/tb_components.sv
@components/Makefile

## Hypothesis
A parameterized state-machine-based SRAM initializer can be
implemented as a standalone combinational/sequential module
with no package dependencies, suitable for use as a library
primitive in components/rtl/.

## Background
The processor design contains multiple SRAMs that must be
initialized to a known value on reset before normal operation
begins. sram_init.sv provides a reusable primitive that walks
all entries of one or more SRAMs writing a fixed data value,
then signals completion via a ready output. Callers connect
cs, wr, waddr, and wdata to the target SRAMs.

## Binding Previous Decisions
- Active low reset port named rstn. Rising edge of rstn
  triggers state machine start.
- One module per file. File name matches module name.
- 80 column line width maximum.
- 2 space indent, no tabs.
- ASCII comments only.
- `default_nettype none / `default_nettype wire guards.
- Verilator 5.020 compatible. -Wall, zero warnings.
- --timing in VER_FLAGS (required by Verilator 5.020).
- Suppress BLKSEQ on clock generator with local
  lint_off/lint_on pragma.
- -Wno-DECLFILENAME in Makefile sim and lint targets.
- State machine encoding uses an enum defined inside
  the module. No external package dependency.

## Specific Requirements
1. Module name: sram_init. File: components/rtl/sram_init.sv.
2. Parameters:
     NUM_ENTRIES  - number of SRAM entries to initialize.
     ADDR_BITS    - address bus width. Caller specified,
                    independent of NUM_ENTRIES.
     DATA_WIDTH   - width of write data bus in bits.
     INIT_VAL     - DATA_WIDTH-wide value written to every
                    address. Supplied at instantiation.
     START_DELAY  - delay in clock cycles before the write
                    walk begins. 8-bit parameter. May be
                    zero, in which case the delay state is
                    skipped entirely.
3. Ports:
     clk          - rising edge clock.
     rstn         - active low reset.
     cs           - output, active high chip select,
                    asserted during write walk only.
     wr           - output, active high write enable,
                    asserted during write walk only.
     waddr        - output [ADDR_BITS-1:0], write address.
     wdata        - output [DATA_WIDTH-1:0], write data.
                    Holds INIT_VAL during write walk.
     active       - output, active high, asserted only
                    during the write walk state. Not
                    asserted during delay or done states.
     ready        - output, active high, asserted and held
                    after write walk completes. Deasserts
                    on reset.
4. State machine: four states encoded as an enum local
   to the module.
     PENDING  - held in reset (rstn asserted).
     DELAY    - counting down START_DELAY cycles.
                Skipped when START_DELAY == 0.
     INIT     - walking addresses 0..NUM_ENTRIES-1,
                asserting cs, wr, waddr, wdata each cycle.
     DONE     - ready asserted and held. cs, wr deasserted.
                Holds until reset.
5. Delay counter is 8 bits wide. Counts down from
   START_DELAY to zero then transitions to INIT.
6. Address counter width is ADDR_BITS. Increments each
   cycle in INIT state. Transitions to DONE when
   NUM_ENTRIES addresses have been written.
7. cs and wr are deasserted in all states except INIT.
8. active is asserted only in INIT state.
9. ready is asserted in DONE state only. Deasserts
   synchronously on rstn assertion.
10. wdata is tied to INIT_VAL at all times.
11. Run make lint and make sim. Both must exit zero
    with zero warnings.
12. Write the Results Capture section of this file
    upon completion.

## Constraints
- No package dependencies. No import statements.
- Do not use for loops or while loops in RTL.
- Verilator 5.020. --timing in VER_FLAGS.
- -Wno-DECLFILENAME in sim and lint targets.
- -Wno-UNUSED in VER_FLAGS.

## Deliverables
1. components/rtl/sram_init.sv      -- new module
2. components/tb/tb_components.sv   -- add tb_sram_init block
3. components/tb/Makefile           -- add sram_init lint and
                                       sim targets
4. Results Capture in this file (COMP-003.md)
:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::
## Summary
sram_init.sv implemented as a four-state sequential module
(PENDING->DELAY->INIT->DONE) with no package dependencies.
Two DUT instantiations added to tb_components.sv: one with
START_DELAY=0 (tests direct PENDING->INIT path) and one with
START_DELAY=3 (tests DELAY countdown). All 13 sram_init test
cases pass. make lint and make sim both exit zero, zero
warnings. Total tb_components score: 34/34.

## What was delivered
- components/rtl/sram_init.sv (new module, 78 lines)
- components/tb/tb_components.sv (tb_sram_init block added,
  si_a_check / si_b_check tasks, two DUT instantiations)
- components/Makefile (sram_init.sv added to RTL_FILES)

## Test Case Results
DUT A: NUM_ENTRIES=4, ADDR_BITS=4, DATA_WIDTH=8,
       INIT_VAL=8'hA5, START_DELAY=0
  TC1  PASS  INIT cycle 1, waddr=0, cs=1 wr=1 active=1
  TC2  PASS  INIT cycle 2, waddr=1
  TC3  PASS  INIT cycle 3, waddr=2
  TC4  PASS  INIT cycle 4, waddr=3
  TC5  PASS  DONE: cs=0 wr=0 active=0 ready=1

DUT B: NUM_ENTRIES=4, ADDR_BITS=4, DATA_WIDTH=8,
       INIT_VAL=8'hBB, START_DELAY=3
  TC6  PASS  DELAY cycle 1, cs=0 wr=0 active=0 ready=0
  TC7  PASS  DELAY cycle 2
  TC8  PASS  DELAY cycle 3
  TC9  PASS  INIT cycle 1, waddr=0, cs=1 wr=1 active=1
  TC10 PASS  INIT cycle 2, waddr=1
  TC11 PASS  INIT cycle 3, waddr=2
  TC12 PASS  INIT cycle 4, waddr=3
  TC13 PASS  DONE: cs=0 wr=0 active=0 ready=1

All 13/13 sram_init cases pass.
Previously passing 21/21 cases unchanged.
Total: 34/34 PASSED.

## Assumptions made not explicit in the prompt
- waddr is not incremented on the last address (held at
  LAST_ADDR through DONE state). cs/wr deassert is the
  signal that the write walk ended.
- PENDING->INIT vs PENDING->DELAY branch is controlled by
  a runtime check on START_DELAY. Verilator elaborates
  both branches per instance; no CMPCONST warnings observed.
- LAST_ADDR uses ADDR_BITS'(NUM_ENTRIES-1) explicit cast to
  avoid WIDTHTRUNC warning (32->ADDR_BITS truncation).
- Makefile column header says "components/tb/Makefile" but
  the actual file lives at components/Makefile. Edited the
  file at components/Makefile per the paths in its body.

## Decisions made not explicit in the prompt
- INIT_VAL declared as parameter [DATA_WIDTH-1:0] so that
  the assign wdata = INIT_VAL is width-matched and
  width-warning-free.
- ready is registered inside the main always_ff block,
  set on the INIT->DONE transition, cleared on async
  reset. This matches "deasserts on reset" requirement
  and avoids a separate always block.
- cs, wr, active are combinatorial outputs of state
  (assign cs = (state == INIT)) to minimize registered
  outputs and avoid one-cycle lag on assertion.
- wdata is tied combinatorially to INIT_VAL at all
  times per requirement 10.
- Delay counter counts down: enters DELAY with delay_cnt
  = START_DELAY, transitions to INIT when delay_cnt==1
  (after decrement), giving exactly START_DELAY cycles
  in DELAY state before INIT begins.

## RVA23 compliance risks and gaps noticed
None. sram_init is a library primitive with no
architectural visibility. It has no ISA-level interface.

## Deferred Work
None identified for this module.

## Other Notes as needed
- Verilator 5.020 required ADDR_BITS'(NUM_ENTRIES-1) cast
  on the LAST_ADDR localparam. Plain NUM_ENTRIES-1 triggers
  WIDTHTRUNC (32-bit SUB result vs ADDR_BITS-wide target).
  No project-wide suppression added; the cast is the fix.
:: RESULTS:END ::
