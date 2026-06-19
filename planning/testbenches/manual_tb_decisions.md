<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Manual Testbench Planning Decisions
```
 FILE:    planning/manual_tb_decisions.md
 SOURCE:  manual edit
 STATUS:  DRAFT
 UPDATED: 2026-05-20
 CONTACT: Jeff Nye
```

## Purpose

The purpose of a manual testbench is to assist hand creation of
tests as a cross check against the PA/IA testbenches and tests.

Manual testbenches will be created for sub-units and for major
units. In current planning these include tage and ittage. The
frontend will be the first major unit with a manual testbench.

A common structure is desired to facilitate manual edits and
manual test development.

This document covers the general common structures and
organization of a manual testbench.

Specialization for each unit is supplied as an external
unit-specific document, e.g. tage_mtb_decisions.md,
ittage_mtb_decisions.md. These documents are parallel to
the existing PA/IA focused tb decision documents.

---

## File Names

Testbench top level:
  tb_<dut>_manual.sv
  rtl/core/frontend/bpu/tb/tb_<dut>_manual.sv

Unit-specific tasks include file:
  tb_<dut>_manual_tasks.svh
  rtl/core/frontend/bpu/tb/tb_<dut>_manual_tasks.svh

Shared utility include file:
  utils.svh
  rtl/core/frontend/bpu/tb/utils.svh

---

## Structure

The sections of the testbench file appear in this order:

```
<package imports>
<module declaration>
<include files>
<local parameters>
<test enable integers>
<dut port signal declarations>
<dut port expansion signal declarations>
<testbench variables>
<dut signal logic and tieoffs>
<master run_tests task>
<master initial statement>
<testbench logic>
<dut instantiation>
```

### Package Imports

Supplied by the prompt or determined from context.
Import order: bp_defines_pkg then bp_structs_pkg.

### Module Declaration

The top module is always named tb. The top module never
declares ports.

### Include Files

Two include files are listed in order:

  `include "utils.svh"
  `include "tb_<dut>_manual_tasks.svh"

utils.svh contains shared utility tasks common to all
manual testbenches. See the Utils section below.

tb_<dut>_manual_tasks.svh contains all unit-specific
tasks including RAM access tasks, prediction tasks,
update tasks, and check tasks for this DUT.

### Local Parameters

Parameters that set the module parameter values for the
DUT instantiation. Named to match the DUT parameter names.

### Test Enable Integers

One integer per test. A value of 1 enables the test.
A value of 0 disables it. All are set to 1 by default.
Naming convention: en_<test_name>.

```
int en_my_test = 1;
```

### DUT Port Signal Declarations

One signal per DUT port. Names are identical to the DUT
port names. All declared as logic so they can be driven
by tasks.

### DUT Port Expansion Signal Declarations

Waveform viewers have limited support for displaying
packed structs and multi-dimensional arrays. Expansion
signals provide individual named wires for each field
and slot so they are directly visible in the wave
viewer without manual decoding.

Expansion signals are continuous wire assigns derived
from DUT port signals. They are read-only debug
visibility aids and are never driven by tasks.

Two categories of port require expansion:

Category 1: Ports parameterized by NUM_PRED_SLOTS.
  Any port declared as [NUM_PRED_SLOTS-1:0] is
  expanded to one wire per slot.

Category 2: Struct array ports.
  Any port declared as a struct type with a slot
  dimension is expanded to one wire per field per
  slot. Field names and widths are derived from the
  struct definition in bp_structs_pkg.sv.

Naming convention:

  d_<port_name>_<slot_name>
  d_<port_name>_<field_name>_<slot_name>

  Prefix: d_ (debug visibility)
  Slot suffix: s0, s1, ... (matches slot index)

Examples:

```
  // Category 1: scalar array port
  logic [NUM_PRED_SLOTS-1:0] tage_pred_val_p0;
  wire d_tage_pred_val_p0_s0 = tage_pred_val_p0[0];
  wire d_tage_pred_val_p0_s1 = tage_pred_val_p0[1];

  // Category 2: struct array port
  tage_pred_inp_t tage_pred_inp_p0[0:NUM_PRED_SLOTS-1];
  wire [VA_WIDTH-1:0] d_tage_pred_inp_p0_pc_s0 =
    tage_pred_inp_p0[0].pc;
  wire [VA_WIDTH-1:0] d_tage_pred_inp_p0_pc_s1 =
    tage_pred_inp_p0[1].pc;
  wire [FTQ_IDX_BITS-1:0] d_tage_pred_inp_p0_branch_id_s0 =
    tage_pred_inp_p0[0].branch_id;
  wire [FTQ_IDX_BITS-1:0] d_tage_pred_inp_p0_branch_id_s1 =
    tage_pred_inp_p0[1].branch_id;
```

The unit-specific addendum identifies which ports are
expanded. Claude Code derives the full expansion from
the struct definitions in bp_structs_pkg.sv and the
parameter values in bp_defines_pkg.sv. No explicit
field enumeration is required in the addendum.

---

### Testbench Variables

The following variables are always present:

| Type   | Name       | Description                        |
|--------|------------|------------------------------------|
| int    | cycle_cnt  | clock cycle counter                |
| logic  | clk        | testbench clock                    |
| logic  | rstn       | active low reset                   |
| int    | tb_errs    | top-level error accumulator        |
| string | test_name  | current test name, visible in waves|

test_name is declared at module scope (not inside initial)
so it is visible to the wave dumper. start_test sets it.
stop_test clears it to "".

Per-test error counters follow the naming convention
err_<test_name> and are declared alongside the enable
integers.

Clock generation:

```
initial clk = 0;
/* verilator lint_off BLKSEQ */
always #5 clk = ~clk;
/* verilator lint_on BLKSEQ */
```

Cycle counter:

```
initial cycle_cnt = 0;
/* verilator lint_off BLKSEQ */
always @(posedge clk) cycle_cnt++;
/* verilator lint_on BLKSEQ */
```

### DUT Signal Logic and Tieoffs

Required tieoffs are placed in a dedicated initial block:

```
initial begin
  <signal> = <value>;
  ...
end
```

Any combinatorial logic required for DUT-related signals
is placed here as continuous assigns.

### Master run_tests Task

A single task named run_tests is defined at the top level.
It calls each test task gated by its enable integer.
run_tests accumulates errors into tb_errs.

```
task automatic run_tests();
  if (en_my_test1) my_test1(err_my_test1);
  if (en_my_test2) my_test2(err_my_test2);
  tb_errs = err_my_test1 + err_my_test2;
endtask
```

### Master Initial Statement

The master initial block executes in this order:

  1. Enable FST waveform dump if +EN_FST is present.
     This must be first so reset and initialization
     cycles are captured.
  2. Set default values for all DUT port signals.
  3. Call assert_reset(4).
  4. Wait for DUT ready signal if present.
  5. Call run_tests().
  6. Call terminate().

```
  // ----------------------------------------------------------------
  // Master initial statement
  // ----------------------------------------------------------------
  initial begin : tb_main
    int    en_fst;
    string fst_file;

    en_fst   = 0;
    fst_file = "waves.fst";

    void'($value$plusargs("EN_FST=%d",   en_fst));
    void'($value$plusargs("FST_FILE=%s", fst_file));

    if (en_fst) begin
      $dumpfile(fst_file);
      $dumpvars(0, tb);
    end

    // default signal values here

    assert_reset(4);

    // wait for ready
    while (!dut_rdy) @(posedge clk);
    @(posedge clk);

    run_tests();
    terminate();
  end
```

Note: replace dut_rdy with the actual ready signal name
for the unit under test. The unit-specific addendum
identifies the ready signal.

### Testbench Logic

Clock generation, cycle counter, and any always blocks
required for testbench operation are placed here.

### DUT Instantiation

The DUT instance is always named u_dut.

```
<dut_module> #(
  .PARAM (LOCAL_PARAM)
) u_dut (
  .port (signal)
);
```

---

## Utils

utils.svh contains shared utility tasks used by all manual
testbenches. All tasks are automatic.

---

### tb_msg

Base message formatter. All other print tasks call this.

```
task automatic tb_msg(
  input string prefix,
  input string msg,
  input int    t = 0
);
  if (t) $display("-%0s: %t : %s", prefix, $time, msg);
  else   $display("-%0s: %s", prefix, msg);
endtask
```

---

### tb_info, tb_warn, tb_error

Thin wrappers over tb_msg with fixed prefixes.
Optional time flag t defaults to 0.
tb_error does not increment any counter.
Error counting is the responsibility of the test task.

```
task automatic tb_info(
  input string msg, input int t = 0);
  tb_msg("I", msg, t);
endtask

task automatic tb_warn(
  input string msg, input int t = 0);
  tb_msg("W", msg, t);
endtask

task automatic tb_error(
  input string msg, input int t = 0);
  tb_msg("E", msg, t);
endtask
```

---

### tb_pf

Pass/fail reporter. Called at the end of each test task
with the test name and its error count. Prints PASS or
FAIL using tb_info or tb_error.

```
task automatic tb_pf(
  input string testname,
  input int    errs
);
  if (errs > 0)
    tb_error({testname, " : FAIL"});
  else
    tb_info({testname, " : PASS"});
endtask
```

---

### start_test

Sets test_name to the argument and emits a START message.
test_name must be declared at module scope.

```
task automatic start_test(input string name);
  test_name = name;
  tb_info({"START ", name});
endtask
```

Output format:
  -I: START <testname>

---

### stop_test

Emits a STOP message, calls tb_pf, then clears test_name.

```
task automatic stop_test(
  input string name,
  input int    errs
);
  tb_info({"STOP  ", name});
  tb_pf(name, errs);
  test_name = "";
endtask
```

Output format:
  -I: STOP  <testname>
  -I: <testname> : PASS  (or -E: <testname> : FAIL)

---

### assert_reset

Drives rstn low for n clock cycles then deasserts.

```
task automatic assert_reset(input int n);
  rstn = 1'b0;
  repeat (n) @(posedge clk);
  rstn = 1'b1;
endtask
```

---

### terminate

Called at the end of all tests. Placeholder for any
required shutdown sequence. Currently calls $finish.

```
task automatic terminate();
  $finish;
endtask
```

---

### Staging FF Pattern

Verilator 5.020 requires that always_comb blocks
re-evaluate after FF updates. Tasks that drive
struct-array ports must use staging always_ff blocks
to satisfy the nba_sequent requirement. Pure
task-driven assigns to struct-array ports may not
propagate correctly without this pattern.

Declare staging signals alongside the DUT port signals:

  logic [1:0]        stg_pred_val;
  tage_pred_inp_t    stg_pred_inp[0:NUM_PRED_SLOTS-1];

Drive the staging signals from tasks. Connect staging
signals to DUT ports in the instantiation.

Staging always_ff blocks are placed in the Testbench
Logic section, not in DUT Signal Logic and Tieoffs,
since they are sequential blocks not combinatorial
tieoffs.

---

## Simulation Controls

| Control          | Mechanism          | Default   | Notes             |
|------------------|--------------------|-----------|-------------------|
| Reset length     | assert_reset(n)    | n=4       | cycles            |
| Waveform dump    | +EN_FST=1 plusarg  | off       | FST format        |
| Dump file        | +FST_FILE=f plusarg| waves.fst | optional override |
| Dump scope       | $dumpvars(0,tb)    | full      | all signals in tb |
| Clock period     | always #5          | 10ns      | 5ns half period   |

---

## Naming Conventions Summary

| Item                  | Convention                          |
|-----------------------|-------------------------------------|
| Testbench module      | tb                                  |
| DUT instance          | u_dut                               |
| Test enable           | en_<test_name>                      |
| Per-test errors       | err_<test_name>                     |
| Current test name     | test_name (module scope string)     |
| Tasks include         | tb_<dut>_manual_tasks.svh           |
| Utils include         | utils.svh                           |
| Waveform file         | waves.fst (default)                 |
| Expansion wire prefix | d_                                  |
| Expansion slot suffix | _s0, _s1, ...                       |

