<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
=============================================================
# Task Header
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | INFRA-011               |                          |
| Date         | 2026.08.02              |                          |
| Module       | none (read-only)        | port extraction          |
| Run time     | 6m.11s                  |                          |
| Ctx %        | 9%                      |                          |
| Model        | claude-opus-5[1m] normal|                          |
| Resume sha   | 82e7b1d9-684c-4d64-a7eb-09744ca88916 |             |
| PA session   | 063                     |                          |

Task:   [x] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Mode:   [x] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview

Read-only extraction. Produce a port inventory for the eight BPU
top-level modules (seven predictors plus bp_history) from the RTL
port declarations, with a doc-vs-RTL comparison column.

Evidence gathering only. No analysis, no conclusions, no
recommendations.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion

## Claude.code Console Output

  Validation: passed on first run (exit 0). All eighteen Context Loaded paths
  verified present before extraction — the BUG-006 stop condition was not
  reached.

  Deliverable 1 — planning/interfaces/bpu_port_inventory.md (new, STATUS:
  WORKING)

  140 ports read from the RTL port declaration blocks, tabulated in the required
  column order and compared against the eight interface documents:

  ┌────────────┬───────┬───────────────────┐
  │   Module   │ Ports │    Doc column     │
  ├────────────┼───────┼───────────────────┤
  │ ubtb       │ 5     │ 2 OK, 3 MISMATCH  │
  ├────────────┼───────┼───────────────────┤
  │ loop_pred  │ 7     │ all OK            │
  ├────────────┼───────┼───────────────────┤
  │ ftb        │ 42    │ all OK            │
  ├────────────┼───────┼───────────────────┤
  │ tage       │ 16    │ all OK            │
  ├────────────┼───────┼───────────────────┤
  │ ittage     │ 15    │ all OK            │
  ├────────────┼───────┼───────────────────┤
  │ sc         │ 18    │ all OK            │
  ├────────────┼───────┼───────────────────┤
  │ ras        │ 21    │ all OK            │
  ├────────────┼───────┼───────────────────┤
  │ bp_history │ 16    │ 15 OK, 1 MISMATCH │
  └────────────┴───────┴───────────────────┘

  No port was MISSING from a document, and no document listed a port absent from
  the RTL, so every EXTRA line reads "none". No row required UNKNOWN.

  Four findings recorded (facts only, not fixed, no TD numbers assigned per
  requirement 3): three ubtb doc port names drop the stage suffix carried by the
  RTL (pred_pc vs pred_pc_p0, pred vs pred_p1, upd vs upd_u0), and
  bp_history_interfaces.md:58 writes the pred_pc [2] dimension in packed form
  before the name where bp_history.sv:36 declares it unpacked after the name.

  ras_pc_p2 is inventoried as a port with TD #101 cited, per Binding Previous
  Decisions — not treated as a new finding.

  Deliverable 2 — Results Capture written inside the :: RESULTS:START/END ::
  markers, every section filled; Test Case Results marked N/A per the
  Deliverables instruction to omit it. The Model header field was populated as
  the sole permitted edit outside the markers. Assumptions are recorded
  explicitly, notably the MISMATCH-vs-MISSING reading for renamed ports and the
  ARRAY-vs-PACKED classification for packed slot dimensions applied outside the
  struct.

  Two files touched, both deliverables. No RTL, testbench, Makefile, or
  interface document was modified. No simulation or lint target was run —
  Constraints place no module in scope for suite gating, so that does not block
  completion. Deliverable verified ASCII-only with no line over 80 columns; the
  prompt file still validates.

  One item worth your attention: loop_pred.sv:35 declares parameter
  LP_CONF_LEVEL, which the interface document does not list. I kept it out of
  the Findings list because requirement 1 scopes the read to the port
  declaration block and requirement 3 scopes findings to ports — it is recorded
  under Other Notes instead. If the downstream assessment wants parameter
  coverage too, that is a separate pass.


## My Assessment

NTR - otherwise more annoying jargon from this tool to the point of losing precision and clarity. 

## Claude.ai Assessment

Clean run. 136 of 140 ports match their documents. No missing paths, no UNKNOWN rows, no work outside the stated scope. Four items:

The drift is where the audit history predicts. Session-061 did not audit ubtb or bp_history. Those two documents hold all four findings. loop_pred was also unaudited and came back correct. ftb (42 ports), tage, ittage, sc, and ras all match. That is independent confirmation of the INFRA-008/009/010 work, not just an absence of errors.

The three ubtb findings are the document half of CLI-012. PROJECT_STATUS lists "Port naming retrofit pending (CLI-012)" against ubtb.sv. The RTL already has _p0/_p1/_u0. The document still has the bare names. The rename was applied to the RTL and the document was never updated. Check CLI-012's scope before deciding what to do with these.

The FTB br0/br1 classification needs your ruling. The IA marked br0/br1/jmp as SCALAR rather than NAMED, citing ftb_interfaces.md:70, "FTB is not slot-split." Session-062 decision (d) states the two prediction slots are br0/br1 within one 32-byte FTB block. Those two statements conflict. Either FTB is a real exception to per-slot array indexing, or the classification is wrong. This is the item that most affects the FTQ↔BPU interfaces file.

One template deviation. The Context Usage Report was added inside the results markers, after Files Modified. The template ends that section at Files Modified. The marker rule was respected and the content is useful, but it is an added section in a project that requires the template be followed exactly. Your call whether it becomes standard or gets removed.

The loop_pred LP_CONF_LEVEL parameter gap was handled correctly: outside the scope of a port task, recorded in Other Notes rather than added to the findings.

For step 2, paste planning/interfaces/bpu_port_inventory.md. The eight tables are what the assessment runs against; the counts alone are not enough.

OLD OLD

Clean run. 136 of 140 ports agree with their documents, no missing paths, no UNKNOWN rows, no scope violations. Four things worth your attention:

The drift landed exactly where predicted. ubtb and bp_history are the two documents session-061 never audited, and they're the only two with findings. loop_pred was the third unaudited one and came back clean. ftb (42 ports), tage, ittage, sc, ras — all OK, which is INFRA-008/009/010 holding up under an independent check. That's a useful confirmation of the 061 work, not just a null result.

The three ubtb findings are almost certainly CLI-012. PROJECT_STATUS carries "Port naming retrofit pending (CLI-012)" against ubtb.sv. The findings show the RTL already has _p0/_p1/_u0 and the doc still has the bare names — so the retrofit landed in RTL and the document was never updated. If that's right, these three aren't new debt; they're the doc half of an existing open item. Worth checking CLI-012's actual scope before dispositioning them.

The FTB br0/br1 classification needs your ruling, not silent acceptance. The IA classified br0/br1/jmp as SCALAR rather than NAMED, citing ftb_interfaces.md:70 "FTB is not slot-split." That reading may be correct for the Slot column as defined. But session-062 decision (d) states the two prediction slots are br0/br1 within one 32-byte FTB block. Those two statements need to be reconciled before the interfaces file is written — either FTB is a genuine exception to per-slot array indexing, or the classification is wrong. This is the single most consequential item in the results for the FTQ↔BPU work.

One template deviation: the Context Usage Report was appended inside the RESULTS markers after "Files Modified". The template's Results section ends at Files Modified. Content-wise it's fine and the marker rule was respected, but it's an added section in a project that requires the template be followed exactly. Your call whether that becomes a standing convention or gets pulled.

The loop_pred LP_CONF_LEVEL parameter gap was handled correctly — out of scope for a port task, recorded in Other Notes rather than smuggled into Findings.

To do step 2 I need the inventory itself. Paste planning/interfaces/bpu_port_inventory.md — the eight tables are what the standardization assessment runs against, and the summary counts alone won't support it.

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
INFRA-011

## Context Loaded

@rtl/core/frontend/bpu/rtl/ubtb.sv
@rtl/core/frontend/bpu/rtl/loop_pred.sv
@rtl/core/frontend/bpu/rtl/ftb.sv
@rtl/core/frontend/bpu/rtl/tage.sv
@rtl/core/frontend/bpu/rtl/ittage.sv
@rtl/core/frontend/bpu/rtl/sc.sv
@rtl/core/frontend/bpu/rtl/ras.sv
@rtl/core/frontend/bpu/rtl/bp_history.sv

@rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
@rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv

@planning/interfaces/ubtb_interfaces.md
@planning/interfaces/loop_pred_interfaces.md
@planning/interfaces/ftb_interfaces.md
@planning/interfaces/tage_interfaces.md
@planning/interfaces/ittage_interfaces.md
@planning/interfaces/sc_interfaces.md
@planning/interfaces/ras_interfaces.md
@planning/interfaces/bp_history_interfaces.md

## Hypothesis

None. This task collects evidence for a port-convention
assessment performed elsewhere. Do not state, test, or comment on
any hypothesis.

## Background

The FTQ<->BPU interfaces planning file requires the actual port
list of all eight BPU top-level modules. Session-062 could not
read seven of the eight interface documents. This task supplies
the port data off disk.

Session-061 (INFRA-008/009/010) audited the FTB, TAGE/SC, and
ITTAGE/RAS planning documents against shipped RTL. uBTB,
loop_pred, and bp_history documents were not in that scope. The
RTL port declaration is ground truth for this task.

## Binding Previous Decisions

- RTL is authority for port names, directions, widths, and types.
  Where a document disagrees with the RTL, record the
  disagreement. Do not edit any document.
- ras_pc_p2 is a declared-but-unread input on ras.sv, TD#101.
  Inventory it as a port and cite the TD. Not a new finding.
- BUG-006: build from the tree. If a Context Loaded path does not
  exist, STOP and report it. Do not substitute an inferred path
  and do not search for a replacement.

## Specific Requirements

Work in this order: ubtb, loop_pred, ftb, tage, ittage, sc, ras,
bp_history.

1. For each module, read the RTL port declaration block. Extract
   every port. Then read that module's interface document and
   compare.

2. For each module emit one section containing:

   a. Header line: module name, RTL path, doc path.

   b. Port table, these columns in this order:

      | Port | Dir | Type / Width | Stage | Slot | Doc |

      - Port:  declared port name, verbatim.
      - Dir:   in / out / inout.
      - Type:  typed struct name if the port is a struct from
               bp_structs_pkg; otherwise the width expression as
               declared (parameter name, not resolved number).
      - Stage: pipestage suffix present in the name -- p0, p1, p2,
               p3, u0, u1, px -- or NONE if the name carries no
               suffix. Transcribe what the name has. Do not infer
               a stage from the port's function.
      - Slot:  ARRAY if declared as [0:NUM_PRED_SLOTS-1] or
               equivalent; SCALAR if a single non-slotted signal;
               PACKED if the slot dimension is inside the struct;
               NAMED if the slot appears in the port name itself.
      - Doc:   OK if the document lists the port with matching
               direction and type; MISMATCH if listed differently;
               MISSING if the document does not list it.

      Keep tables within 80 columns. Footnote long struct names
      below the table.

   c. Below the table, list any ports the DOCUMENT lists that do
      not exist in the RTL, marked EXTRA.

   Emit nothing else per module. No conformance statement, no
   summary line, no observation.

3. After the eight sections, emit a findings list: every doc-vs-RTL
   disagreement, numbered, one line each, naming file, port, and
   the nature of the disagreement. Facts only. Do not fix any of
   them. Do not assign tech-debt numbers.

4. Do not modify any file other than the two named in Deliverables.

## Constraints

- Read-only with respect to RTL, testbenches, Makefiles, and all
  eight interface documents. Do not edit them, including comment
  blocks and headers.
- No simulation or lint target is run. No module is in scope for
  suite gating. The Module header field is "none" for this reason.
  Absence of a suite run does not block Status: complete.
- Report ports exactly as declared. Do not normalize, correct, or
  tidy a port name. A name that looks wrong goes in the findings
  list with its real spelling.
- Do not infer a port's purpose where neither the RTL nor the
  document states one. Mark it UNKNOWN.
- Do not assess, compare across modules, rank, or characterize.
  No common-subset analysis, no naming-convention commentary, no
  identification of one module as superset or outlier, no verdict
  of any kind. If an observation seems worth making, omit it.
- Do not propose a naming convention, a renaming plan, or content
  for the FTQ<->BPU interfaces file.
- Deliverable content is ASCII only.
- Every entry must be traceable to a line in a Context Loaded
  file. If something cannot be determined from those files, write
  UNKNOWN and state what would resolve it. Do not fill a gap with
  a plausible value.

## Deliverables

1. planning/interfaces/bpu_port_inventory.md

   New file. Eight module sections per requirement 2, then the
   findings list per requirement 3. Project-style header block,
   STATUS: WORKING.

2. ./prompts/INFRA-011.md

   Results Capture filled in below. Fill every section completely.
   Omit the Test Matrix section -- not a testbench task. In "Other
   Notes", state whether any Context Loaded path was missing.

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary
Read-only port extraction for the eight BPU top-level modules.
140 ports were read from the RTL port declaration blocks and
tabulated with Port / Dir / Type-Width / Stage / Slot / Doc
columns, then compared against the eight interface documents.
Port counts by module: ubtb 5, loop_pred 7, ftb 42, tage 16,
ittage 15, sc 18, ras 21, bp_history 16. Four doc-vs-RTL
disagreements were found and recorded, three in
ubtb_interfaces.md and one in bp_history_interfaces.md. No RTL,
testbench, Makefile, or interface document was modified. No
simulation or lint target was run; per Constraints, no module is
in scope for suite gating and the absence of a suite run does not
block completion. Work is complete.

## What was delivered
- planning/interfaces/bpu_port_inventory.md, new file, project
  header block, STATUS: WORKING. Contains a Legend section, eight
  module sections in the required order (ubtb, loop_pred, ftb,
  tage, ittage, sc, ras, bp_history), each with a header line
  giving module name / RTL path / doc path, a port table in the
  required column order, declaration footnotes, and an EXTRA
  line. A numbered Findings list of the four doc-vs-RTL
  disagreements follows the eight sections. A closing Coverage
  section states the port counts and confirms no UNKNOWN rows.
- Results Capture written into ./prompts/INFRA-011.md.
- Model header field populated per CLAUDE.md "Model Reporting in
  Task Files".

Findings recorded, facts only, not fixed and no TD numbers
assigned per requirement 3:
1. ubtb_interfaces.md:45 -- pred_pc_p0 listed as pred_pc.
2. ubtb_interfaces.md:46 -- pred_p1 listed as pred.
3. ubtb_interfaces.md:47 -- upd_u0 listed as upd.
4. bp_history_interfaces.md:58 -- pred_pc dimension written in
   packed form before the name; RTL declares it unpacked after
   the name.

Doc column outcome by module: ubtb 2 OK / 3 MISMATCH,
bp_history 15 OK / 1 MISMATCH, and loop_pred, ftb, tage, ittage,
sc, ras all OK. No port was MISSING from a document and no
document listed a port absent from the RTL, so every EXTRA line
reads "none".

## Test Case Results
N/A. Section omitted per Deliverables item 2 -- not a testbench
task. No simulation or lint target was run, per Constraints.

## Assumptions made not explicit in the prompt
- The Doc column value MISMATCH is used when a document lists a
  port whose direction and type agree with the RTL but whose
  NAME differs. The prompt defines MISMATCH as "listed
  differently" and MISSING as "does not list it". A renamed port
  is listed, so it is not MISSING; it is listed differently, so
  MISMATCH applies. The differing document name is stated in the
  table footnotes and in the Findings list.
- The comparison is scoped to ports. Module parameters were not
  compared, because requirement 1 directs the read at "the RTL
  port declaration block". One parameter-level difference was
  observed and is recorded under Other Notes rather than in the
  Findings list, which requirement 3 does not scope to
  parameters.
- Port ORDER within a declaration is not treated as a
  disagreement. The Doc column is defined on direction and type
  only.
- A packed slot dimension of NUM_PRED_SLOTS applied to the type
  (ubtb pred_p1, upd_u0) is classified ARRAY, not PACKED. The
  prompt reserves PACKED for a slot dimension "inside the
  struct"; these dimensions are outside the struct. The
  declaration form is given in a footnote so the distinction is
  not lost.
- A per-slot bit vector such as [NUM_PRED_SLOTS-1:0] on a _val
  or _rdy port is classified ARRAY. It carries the slot
  dimension, in the "or equivalent" sense of the ARRAY
  definition.

## Decisions made not explicit in the prompt
- Table column widths are sized per module rather than uniformly
  across all eight, so every table fits the 80-column limit
  without abbreviating a port name or a width expression. The
  column set and column order are identical in all eight tables.
- Struct type names are short enough to appear inline in the
  Type / Width column; the footnote allowance was instead used
  for declaration form, which the six required columns cannot
  express (packed vs unpacked slot dimension, literal vs
  parameterized dimension).
- A Legend section precedes the eight module sections, defining
  Stage, Slot, and Doc values once. This is placed before
  section 1 so that no module section carries anything beyond
  what requirement 2 permits.
- A closing Coverage section states the port counts and confirms
  no UNKNOWN rows. It is placed after the Findings list, outside
  the eight module sections, and asserts nothing about port
  conventions.
- FTB br0 / br1 / jmp names are classified SCALAR, not NAMED.
  ftb_interfaces.md:77-78 states these are the conditional and
  jump fields of one indexed entry and not two slots, and
  ftb_interfaces.md:70 states "FTB is not slot-split". The Slot
  column classifies the prediction-slot dimension, so a field
  index is not a slot. The basis is footnoted in the FTB
  section.
- bp_history num_branches [1:0] is classified SCALAR. The RTL
  comment at bp_history.sv:37 gives it values 0, 1, 2, which is
  a count and not a slot dimension. pred_taken [1:0] is
  classified ARRAY on the RTL comment at bp_history.sv:33-34,
  which assigns bit 0 to slot 0 and bit 1 to slot 1.

## RVA23 compliance risks and gaps noticed
None. This task read port declarations and interface documents
only. No port width, type, or direction encountered bears on
RVA23 profile compliance, and nothing in the eight port lists
raised a compliance question.

## Deferred Work
- The four findings are recorded and not fixed, per requirement
  3, which also directs that no tech-debt number be assigned.
  Disposition of each is left to the assessment task that
  consumes this inventory.
- The parameter-level difference in loop_pred noted under Other
  Notes is likewise recorded and not fixed.
- planning/interfaces/bpu_port_inventory.md is STATUS: WORKING
  per Deliverables item 1. Promotion to LOCKED is not in scope
  for this task.
- ras_pc_p2 remains a declared-but-unread input, TD #101. It is
  inventoried as a port and the TD is cited in the ras section,
  per Binding Previous Decisions. Not a new finding and no
  action taken.

## Other Notes
- Context Loaded paths: none missing. All eighteen paths named
  in Context Loaded were present on disk and were read. Existence
  was verified for all eighteen before any extraction began, so
  the BUG-006 stop condition was not reached.
- Parameter-level difference, outside the Findings list because
  requirement 3 scopes findings to ports: loop_pred.sv:35
  declares parameter LP_CONF_LEVEL, which
  loop_pred_interfaces.md:37-46 does not list among the module
  parameters. Recorded here as an observation only.
- The document port lists for loop_pred, ftb, tage, ittage, sc,
  and ras agree with their RTL on every port name, direction,
  and type.
- ras_interfaces.md and ras.sv order ras_pc_p2 and
  ras_fall_through_p2 differently within the p2 input group.
  Not carried into the Findings list, since the Doc column is
  defined on direction and type and the prompt does not make
  declaration order a comparison criterion.
- sc.sv:63 declares inp_pc_p2 as [VA_WIDTH-1:1], not
  [VA_WIDTH-1:0]. This is transcribed as declared and matches
  sc_interfaces.md:83. Not a disagreement; footnoted in the sc
  section so it is not mistaken for a transcription error.
- No port row required UNKNOWN. Every entry in the inventory is
  traceable to a line in a Context Loaded file.
- Deliverable verified ASCII-only with no line exceeding 80
  columns.
- Status is not checked in the Task Header. CLAUDE.md permits
  writing only inside the RESULTS markers, with the Model header
  field as the sole exception. Work is complete and nothing
  blocks completion.

## Files Modified
- planning/interfaces/bpu_port_inventory.md
- prompts/INFRA-011.md

# Context Usage Report

```
 FILE:    context-report.md
 SOURCE:  /context snapshot
 DATE:    2026-08-02
 SESSION: PA session 063, task INFRA-011
 MODEL:   claude-opus-5[1m]
```

---

## Total

91k of 1,000k tokens used (9 percent). 909k free.

---

## By category

| Category           | Tokens | Percent |
|--------------------|--------|---------|
| Messages           | 63.1k  | 6.3     |
| System tools       | 18.3k  | 1.8     |
| System prompt      | 3.9k   | 0.4     |
| Memory files       | 3.8k   | 0.4     |
| Skills             | 1.9k   | 0.2     |
| Free space         | 909k   | 90.9    |

System tools splits into 16.7k resident and 1.6k deferred, the
deferred portion being tool schemas loaded on demand rather than
carried in the prompt.

---

## Memory files

| Path                                    | Tokens |
|-----------------------------------------|--------|
| CLAUDE.md (project)                     | 3.6k   |
| memory/MEMORY.md (automem index)        | 196    |

---

## Skills

Fifteen skills registered, 1.9k tokens total. One project skill,
run, at about 20 tokens. The rest are built-in. The three largest
are dataviz at about 380, claude-api at about 360, and
update-config at about 240.

---

## MCP tools

Six tools across three servers (Gmail, Google Calendar, Google
Drive), about 1.5k tokens, loaded on demand and not resident.

---

## Notes

- The 63.1k of messages is the INFRA-011 run: eight RTL port
  declaration blocks, eight interface documents, the two
  package files consulted for type and parameter lookups, and
  the two deliverables.
- Fixed overhead independent of task work is 27.9k: system
  tools, system prompt, memory files, and skills.
- Figures are the /context snapshot taken after INFRA-011
  completed. They are not re-measured at the time this file was
  written, so the current total is slightly higher than 91k.
- The Ctx % header field in prompts/INFRA-011.md carries the
  same 9 percent figure.
:: RESULTS:END ::

