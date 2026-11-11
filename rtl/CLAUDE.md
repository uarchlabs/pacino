<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

```
 FILE:    rtl/CLAUDE.md
 SOURCE:  moved from CLAUDE.md
 STATUS:  WORKING
 UPDATED: 2026-11-11
 CONTACT: Jeff Nye
```

RTL rules. Loaded when working under rtl/. The root CLAUDE.md still
applies.

## Combinatorial Logic Style

- Prefer always_comb blocks over cascaded continuous
  assign statements when signals form a dependency
  chain (A depends on B depends on C). Verilator v5.048
  evaluates assign statements using an internal
  dependency DAG and may read stale values when a
  chain is evaluated out of order. always_comb blocks
  evaluate statements in textual order, eliminating
  the ambiguity.
- Single assign statements with no internal
  dependencies are acceptable.

## Package imports
Import at file scope, before the module declaration. Do not place
import statements inside the module header between the module name
and the port list.

  Correct:
    import bp_defines_pkg::*;
    import bp_structs_pkg::*;
    module foo (

  Incorrect (Verilator accepts but project rejects):
    module foo
      import bp_defines_pkg::*;
      import bp_structs_pkg::*;
    (

For package imports the order of bp_defines_pkg and bp_structs_pkg are
important. It must be defines first then structs

    import bp_defines_pkg::*;
    import bp_structs_pkg::*;

## Verilator work arounds

- stl_sequent rule: always_comb blocks that must re-evaluate after FF
  updates must read at least one FF output. Pure module-input-only
  always_comb blocks are classified stl_sequent and will not see
  signal changes after simulation start. Gate prediction scan blocks
  on a registered valid signal to force nba_sequent.

## Verilator Makefile Conventions

- Always include -Wno-DECLFILENAME in sim targets. The project naming
  convention (module tb in file tb_<dut>.sv) triggers this warning by
  design. It is not a defect -- suppress it project-wide.
- Use -Wall for all other warnings. Sim and lint targets must both
  exit zero with zero warnings after -Wno-DECLFILENAME and any
  session-specific suppressions noted in the experiment constraints.
- Session-specific suppressions (e.g. -Wno-UNUSED for package-only
  sessions) are listed in the experiment Constraints section and
  must not be added to CLAUDE.md.
- Always include -Wno-IMPORTSTAR in VER_FLAGS. The project
  mandates file-scope wildcard import (import bp_defines_pkg::*;
  then import bp_structs_pkg::*; before the module declaration).
  Verilator v5.048 warns on wildcard imports in $unit scope. This
  is structural and suppressed project-wide.
- -Wno-VARHIDDEN: add to individual sim or lint targets only when
  a module parameter intentionally shadows a package parameter
  (e.g. NUM_PRED_SLOTS). Do not add to VER_FLAGS.
- Always include -Wno-UNUSED in VER_FLAGS. Package-only
  files and structs not yet consumed by any module will
  trigger unused warnings. This is structural and
  suppressed project-wide.
- add --timing to VER_FLAGS in Makefiles (required by Verilator
  v5.048 for @(posedge clk))
