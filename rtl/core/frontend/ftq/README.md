<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Fetch Target Queue (FTQ)

The FTQ sits between the branch predictor cluster and the fetch
unit. It holds one entry per prediction block, supplies the next
fetch address, and is the point where backend resolutions and
redirects re-enter the front end.

The unit is SPECIFIED but only partly BUILT. The specification is:

```
  planning/arch/ftq_decisions.md          behaviour, START HERE
  planning/arch/ftq_entry_formats.md      the two entry structures
  planning/interfaces/ftq_bpu_interfaces.md
  planning/interfaces/ftq_ifu_interfaces.md
  planning/interfaces/ftq_backend_interfaces.md
```

## Modules

```
  ftq_ftb_sched.sv         FTB update scheduler (BP-100)
  ftq_ftb_sched_assert.sv  its five concurrent properties
```

Everything else in the FTQ -- the entry arrays, the three pointers,
the next-PC mux, the commit walk -- is specified and not yet built.

### ftq_ftb_sched

Two FTQ update channels onto one FTB update port.

The FTB update is 14 flat ports with no slot dimension and NO ready
(`ftq_bpu_interfaces.md` 8), so presenting two updates in one cycle
silently loses one. The scheduler is a correctness requirement, not
an optimisation, and it belongs to the FTQ because the FTQ is what
has two channels.

The rule is `ftq_decisions.md` 5.7.3, S1 to S6: one skid register
one deep, a one-bit value function, issue one per cycle, retain one,
and drop only LOW-value updates. A LOW update is a routine
confidence step on a branch that hit at predict and predicted
correctly; dropping one delays a training step and never loses an
entry. HIGH updates -- allocations and mispredict corrections -- are
never dropped, and if accepting one would force a HIGH drop the
channel's ready deasserts instead (S6).

That deassertion is the only backpressure the FTB path can apply to
resolution, and it is why FE-5 was amended to FE-5a: the original
no-drop guarantee turned a predictor training limit into a machine
throughput limit.

The output is REGISTERED. A channel accepted in cycle T issues in
T+1.

## Verification

```
  make lint_ftq_ftb_sched
  make sim_ftq_ftb_sched
  make all          both of the above
  make clean
```

`sim_ftq_ftb_sched` runs 67 self-checking directed checks and, at
the same time, the five concurrent properties of
`ftq_decisions.md` 5.7.4, bound to the DUT BY MODULE NAME.

THE FIRST CONCURRENT SVA IN THIS PROJECT. The BPU assertion files
use procedural immediate assertions and are simulation only; these
are written in the form a formal tool consumes. Both targets pass
`--assert`, without which Verilator parses the properties and
generates nothing -- they would never fire, which is the defect
class this project has hit twice.

The properties read only the DUT's port list. `ftq_ftb_sched`
carries observation outputs -- `skid_val`, `skid_wr`, `skid_issue`,
`drop_val`, `drop_is_high`, the pending counts -- for exactly that
reason, so the bind makes no hierarchical reference into module
internals.

The directed checks cover the datapath: which update issues, in what
order, with what payload. The drop and stall rules are left to the
properties. That division is what `5.7.4` describes, and it is why
the testbench does not model the collision rule to predict FTB
contents.

## Structure

```
  rtl/        synthesisable RTL and the bound assertions
  tb/         testbenches, tb_<dut>.sv, module name tb
  Makefile    lint and sim targets
```
