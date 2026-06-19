<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->

# SVA Prompt Template — SymbiYosys-Compatible Assertion Generation

## How to Use

Copy the **System Prompt** into your LLM system/context field (or prepend it to your message).
Fill in the **User Prompt** template with your actual RTL and specification.
Run 2–3 refinement iterations using the **Refinement Prompt** with any errors fed back from SymbiYosys.

---

## System Prompt

```
You are an expert RTL verification engineer specialising in SystemVerilog Assertions (SVA)
for formal property verification (FPV).

Your task is to generate SVA assertions that are STRICTLY COMPATIBLE with the open-source
SymbiYosys formal verification flow (Yosys + SMTBMC / Boolector / Z3 backend).

RULES — follow these without exception:

1. SYNTHESIZABLE SVA ONLY
   - Use only: assert property, assume property, cover property
   - Allowed operators: ##N, [*N], [*N:M], |=>, |->, $past(), $stable(), $rose(), $fell()
   - Clocking: always use explicit @(posedge clk) or @(negedge clk)
   - Reset: use disable iff (rst) sparingly — confirm backend support if used

2. SIGNAL NAMES
   - Use ONLY signal names explicitly provided in the RTL snippet
   - Never invent or assume signal names
   - If a signal is ambiguous, flag it with a comment: // VERIFY: signal name assumed

3. CLOCK CYCLE DISCIPLINE
   - Be precise about cycle offsets — off-by-one errors are the most common mistake
   - If a value is sampled on cycle N, assert/assume it at the correct edge
   - Do NOT reference future cycle values in the present

4. ASSERTION CATEGORIES — generate at least one of each where applicable:
   - Safety:    things that must NEVER happen         (assert)
   - Liveness:  things that must EVENTUALLY happen    (assert ... ##[1:$])
   - Assumption: constraints on inputs                (assume)
   - Cover:     reachability / design intent          (cover)

5. OUTPUT FORMAT — for each assertion output:
   - A short comment explaining the design intent
   - The SVA property
   - A vacuity risk flag if the property could trivially pass on a constant signal

6. DO NOT generate:
   - covergroup / coverpoint (simulation only, not supported by SymbiYosys)
   - $monitor, $display, or any non-synthesizable system tasks
   - Assertions referencing unprovided signals
```

---

## User Prompt Template

```
## Design Under Test

Module name: <module_name>

### RTL (paste full module or relevant excerpt):

```systemverilog
<paste RTL here>
```

### Natural Language Specification:

<describe the intended behaviour in plain English, e.g.:
 - "The FIFO full flag must be asserted within one cycle of the write pointer
    catching the read pointer"
 - "An AXI transaction must not assert both RVALID and RREADY before ARVALID
    has been seen">

### Interface signals (list key signals and their roles):

| Signal     | Direction | Width | Description         |
|------------|-----------|-------|---------------------|
| clk        | input      | 1     | System clock        |
| rst_n      | input      | 1     | Active-low reset    |
| <sig_name> | input/output | N   | <description>       |

### Verification goals (optional — tick all that apply):

- [ ] Input constraint assumptions (assume)
- [ ] Safety / invariant properties (assert)
- [ ] Liveness / progress properties (assert ##[N:$])
- [ ] Reachability / cover points (cover)
- [ ] Reset behaviour
- [ ] Protocol compliance (specify protocol if relevant)

### Known corner cases or gotchas (optional):

<e.g. "The counter wraps at 255 — do not assert overflow beyond that">
```

---

## Refinement Prompt (Iteration 2+)

Use this after running SymbiYosys and collecting errors/vacuity warnings:

```
The following assertions from the previous response produced errors or unexpected
results when run through SymbiYosys. Please fix them.

### Failing / vacuous assertions:

<paste assertion code here>

### SymbiYosys / Yosys error output:

<paste error messages here>

### Observed issue (describe what you think is wrong, if known):

<e.g. "Assertion 3 is vacuously true because the assume on line X constrains
 the input to never trigger the antecedent">

Please:
1. Diagnose the root cause of each issue
2. Provide a corrected assertion
3. Explain what changed and why
```

---

## SymbiYosys .sby Config Template

Once assertions are generated, add them to your design and use this `.sby` skeleton:

```ini
[options]
mode prove          # or cover / bmc

[engines]
smtbmc boolector    # alternatives: smtbmc z3, abc pdr

[script]
read -formal <your_rtl_file>.sv
read -formal <assertions_file>.sv   # or inline in RTL
prep -top <module_name>

[files]
<your_rtl_file>.sv
<assertions_file>.sv
```

Run with:
```bash
symbiyosys -t prove <config>.sby
```

---

## Tips

- **Vacuity check**: after proving an assertion, also run `cover` mode on the same
  property's antecedent to confirm it is reachable at least once.
- **Iteration**: expect 2–3 LLM refinement rounds before assertions are production-ready.
- **Review checklist**: for each assertion verify — correct signal names, correct clock
  edge, correct cycle offset, non-trivial antecedent.

