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

The master initial block:
  1. Sets default values for all DUT port signals.
  2. Calls assert_reset to hold reset for 4 cycles.
  3. Waits for DUT ready signal if present.
  4. Enables FST waveform dump if +EN_FST is present.
  5. Calls run_tests().
  6. Calls terminate().

FST waveform control:

```
initial begin
  int en_fst;
  en_fst = 0;
  void'($value$plusargs("EN_FST=%d", en_fst));
  if (en_fst) begin
    $dumpfile("tb_<dut>_manual.fst");
    $dumpvars(0, tb);
  end
end
```

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

Verilator 5.020 requires that always_comb blocks re-evaluate
after FF updates. Tasks that drive struct-array ports must
use staging always_ff blocks to satisfy the nba_sequent
requirement. Pure task-driven assigns to struct-array ports
may not propagate correctly without this pattern.

Declare staging signals alongside the DUT port signals:

  logic [1:0]        stg_pred_val;
  tage_pred_inp_t    stg_pred_inp[0:NUM_PRED_SLOTS-1];

Drive the staging signals from tasks. Connect staging
signals to DUT ports in the instantiation.

Staging always_ff blocks are placed in the Testbench Logic
section, not in DUT Signal Logic and Tieoffs, since they
are sequential blocks not combinatorial tieoffs.

---

## Simulation Controls

| Control         | Mechanism         | Default | Notes              |
|-----------------|-------------------|---------|--------------------|
| Reset length    | assert_reset(n)   | n=4     | cycles             |
| Waveform dump   | +EN_FST=1 plusarg | off     | FST format         |
| Dump scope      | $dumpvars(0,tb)   | full    | all signals in tb  |
| Clock period    | always #5         | 10ns    | 5ns half period    |

---

## Naming Conventions Summary

| Item               | Convention                          |
|--------------------|-------------------------------------|
| Testbench module   | tb                                  |
| DUT instance       | u_dut                               |
| Test enable        | en_<test_name>                      |
| Per-test errors    | err_<test_name>                     |
| Current test name  | test_name (module scope string)     |
| Tasks include      | tb_<dut>_manual_tasks.svh           |
| Utils include      | utils.svh                           |
| Waveform file      | tb_<dut>_manual.fst                 |

