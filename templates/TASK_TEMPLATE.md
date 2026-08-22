<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
=============================================================
# Task Header 
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | BP-108                  |                          |
| Date         | 2026.08.22              |                          |
| Module       | ftq unit, file layout   | no RTL behaviour change  |
| Run time     |                         |                          |
| Ctx %        |                         |                          |
| Model        | <model> <effort>        |                          |
| Resume sha   | <sha>                   |                          |
| PA session   | 068                     |                          |

Task:   [ ] experiment  [ ] implementation  [ ] debug
        [X] cleanup     [ ] testbench       [ ] verification
Mode:   [X] automated   [ ] manual          [ ] interactive
Status: [ ] in-progress [ ] complete        [ ] abandoned

# Task Overview

Moves the ten FTQ assertion files from rtl/ to tb/, matching the
bpu convention that rtl/ holds only synthesisable RTL, and fixes
the Makefile targets that reference them.

A PURE RELOCATION. No RTL changes, no testbench changes, no
assertion changes. The unit's numbers must be identical before and
after: 22 targets, 670 checks, zero fail, zero warn, zero err.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion 

## Claude.code Console Output

## My Assessment

## Claude.ai Assessment

## Follow-on Actions
- [ ] As needed document here

## CLAUDE.md Updates
Nothing required

## Other Planning File Updates
Nothing required

:: DISCUSSION:END ::

=============================================================
:: PROMPT:START ::
=============================================================

## Task ID
BP-108

## Context Loaded
@rtl/core/frontend/ftq/Makefile
@rtl/core/frontend/bpu/Makefile
@rtl/core/frontend/ftq/rtl/ftq_commit_assert.sv
@rtl/core/frontend/ftq/rtl/ftq_entry_assert.sv
@rtl/core/frontend/ftq/rtl/ftq_ftb_sched_assert.sv
@rtl/core/frontend/ftq/rtl/ftq_ifu_assert.sv
@rtl/core/frontend/ftq/rtl/ftq_meta_assert.sv
@rtl/core/frontend/ftq/rtl/ftq_npc_assert.sv
@rtl/core/frontend/ftq/rtl/ftq_ptr_assert.sv
@rtl/core/frontend/ftq/rtl/ftq_resolve_assert.sv
@rtl/core/frontend/ftq/rtl/ftq_shadow_assert.sv
@rtl/core/frontend/ftq/rtl/ftq_status_assert.sv

## Context Comments
DIRECTORY LISTING OF THE ftq AND bpu UNITS IS PERMITTED, for
Requirement 0 and for Problem 2. Reading RTL or testbench sources is
not needed for this task and none is in the manifest.

THE bpu CONVENTION IS THAT rtl/ HOLDS ONLY SYNTHESISABLE RTL.
Assertion files are verification collateral and belong in tb/. The
FTQ unit does not follow this: BP-100 and BP-107 put ten assertion
files in rtl/. This task moves them.

THE bpu MAKEFILE IS LOADED AS THE CONVENTION REFERENCE. Match what
it does for its own assertion collateral -- source lists, search
paths, which targets see which directory. Do not invent an ftq
pattern that differs from it. If the bpu turns out NOT to follow
the convention this task assumes, STOP and report that; do not
build to an assumption the tree contradicts.

TEN FILES, NOT NINE. `ftq_ftb_sched_assert.sv` is from BP-100 and
was not in BP-107's Files Modified list, so it is easy to miss. It
is in scope. Moving nine of ten applies the convention halfway and
is worse than not moving any.

THIS IS A NO-OP REFACTOR. Every number must be identical before and
after. If any number changes, the move is wrong -- report it rather
than adjusting the expectation to match.

## Hypothesis

The ten assertion files can move from rtl/ to tb/ with no change to
their content, no change to any RTL or testbench source, and no
change to any reported number. The only edits are to the Makefile.

If a file needs its content changed to survive the move, that is a
finding: it means something in it depended on its own location, and
the dependency should be reported before it is edited away.

## Background

The FTQ unit is complete: eleven modules, 22 Makefile targets, 670
checks, 73 bound properties. BP-107 finished it.

Assertions are bound BY MODULE NAME, not by instance (TD#109), so a
bind does not depend on where the assertion file sits in the tree.
What does depend on it is the Makefile: which source lists name the
file, and which search paths the lint and sim targets use.

## Binding Previous Decisions

1. BIND BY MODULE NAME. TD#109. The binds are already correct and
   this task does not touch them. It also must not silently break
   them; see Problem 3.

2. THE ftq UNIT IS 22 TARGETS AND 670 CHECKS. 11 lint, 11 sim.
   That is the number to reproduce, and BP-107's Results Capture
   has the per-target breakdown if you need it. Do not take the
   figure from this prompt as the baseline -- measure it.

3. planning/ IS READ-ONLY, as always.

## Specific Requirements

Problems, not procedure.

REQUIREMENT 0 -- BASELINE FIRST, BEFORE ANY CHANGE.
Enumerate the Makefile's targets from the Makefile, not from `all`.
Run every one from a clean tree. Record rc, pass, fail, warn and err
per target. THIS TABLE IS THE ACCEPTANCE CRITERION for everything
below, so capture it before touching anything.
Also inventory rtl/core/frontend/ftq/rtl/ and tb/ and report what is
there. If the ten files are not all where this task says they are,
STOP and report.

PROBLEM 1 -- THE MOVE.
Move the ten assertion files to rtl/core/frontend/ftq/tb/. Use `git
mv` so the history follows. Do not edit their contents. If one will
not work after the move without a content change, report what the
dependency was before changing anything.

PROBLEM 2 -- THE MAKEFILE.
Fix every target that referenced the old paths, following the bpu
Makefile's pattern for the same collateral.
ONE QUESTION TO ANSWER EXPLICITLY: the 11 lint targets currently
compile the assertion files, since they sit in rtl/. After the move,
do they still? Report whether lint coverage of the assertion files
is retained, dropped, or moved to the sim targets, and whether that
matches what the bpu does. A silent loss of lint coverage on ten
files is the kind of thing this task could cause and not notice.

PROBLEM 3 -- PROVE THE BINDS SURVIVED.
THE CHECK COUNT CANNOT DETECT THIS FAILURE. The 670 checks are
testbench $error counts, not property firings. If a moved assertion
file silently drops out of a build, every target still reports 670
passing and zero warnings, and the task looks like a success.

So prove separately that each of the ten files is still compiled and
its properties still bound. Method is yours -- an elaboration or
hierarchy report naming the bind instances is cheaper than injection
and is sufficient if it is conclusive. If nothing conclusive is
available, fall back to ONE fault injection per moved file, which is
ten, not the full 73: this task changes no behaviour, so re-proving
every property is not proportionate.
Report the method and the evidence for all ten.

PROBLEM 4 -- RE-RUN AND COMPARE.
Run every target individually from a clean tree again. Present the
before and after tables together. Every cell must match. Call out
any difference rather than explaining it away.

## Constraints

- DO NOT EDIT ANY .sv FILE. Not the RTL, not the testbenches, not
  the assertion files. The only file this task edits is the
  Makefile. If that turns out to be impossible, stop and report why
  rather than making the edit.
- Do not add, remove or renumber a property.
- Do not add or remove a Makefile target. The count stays at 22.
- planning/ is read-only.
- The bpu unit's suite is not in scope and must not be run.

## Deliverables

- The ten assertion files relocated to
  rtl/core/frontend/ftq/tb/
- rtl/core/frontend/ftq/Makefile, updated
- Results Capture filled in below, in this file:
  prompts/BP-108.md

Fill in every section. Test Matrix may be omitted: this task adds no
test cases. Report the BEFORE and AFTER target tables in full, and
the Problem 3 evidence for all ten files.

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary
RESULTS NOT YET WRITTEN -- replace this line when filling in.

## Test Matrix (testbench sessions only, omit otherwise)

## What was delivered

## Test Case Results

## Assumptions made not explicit in the prompt

## Decisions made not explicit in the prompt

## RVA23 compliance risks and gaps noticed

## Deferred Work

## Other Notes

## Files Modified
- List every file changed, one file per line, as a bullet.
- No prose. File paths only. Example:
- rtl/core/frontend/bpu/rtl/tage_cntrl.sv

:: RESULTS:END ::

:: CONTEXT:START ::

:: CONTEXT:END ::

