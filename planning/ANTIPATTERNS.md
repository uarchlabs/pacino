<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Prompt Anti-Patterns
```
 FILE:    ANTIPATTERNS.md
 SOURCE:  various
 STATUS:  STABLE
 UPDATED: 2026-05-01
 CONTACT: Jeff Nye
```

Known failure modes when writing prompts for Claude Code.
Load this file only when writing or reviewing prompts.

---

### Anti-pattern: "Console output only" conflicts with
### Results Capture

**Failure ID:** PG-001

**Symptom:** A debug or experiment prompt contains both of the
following:
- Constraints section includes "Console output only. No file
  writes."
- Deliverables section includes "Results Capture filled in
  below."

These two instructions contradict each other. The Results
Capture write to `prompts/<ID>.md` is a required step in the
standard prompt lifecycle and is not a "file write" in the
sense the constraint intends.

**Root cause:** The constraint was written to protect RTL,
testbench, and Makefile files but was not scoped correctly.

**Correct form:** Use this instead in debug and experiment
prompts:
  - Do not modify any RTL, testbench, or Makefile files.

Never use "Console output only. No file writes." in any
prompt that contains a Results Capture section.

---

### Anti-pattern: Section order not validated against template

**Failure ID:** PG-002

**Symptom:** The validator rejects the prompt file with an
error of the form:

  Validation Error: [Prompt] Out of order: '## <Section>'

**Root cause:** The section sequence inside
`:: PROMPT:START ::` is fixed by the template and must be
followed exactly. In BP-026, `## Background` was written
before `## Hypothesis`, swapping those two sections.

**Required section order inside :: PROMPT:START ::**
  1. ## Task ID
  2. ## Context Loaded
  3. ## Hypothesis
  4. ## Background
  5. ## Binding Previous Decisions
  6. ## Specific Requirements
  7. ## Constraints
  8. ## Deliverables

**Correct form:** Before writing or outputting any prompt
file, verify the section order explicitly against this
sequence. Do not rely on what reads naturally -- the
validator is strict and the order is non-negotiable.

---

### Anti-pattern: Coverage target and testbench file
### not linked

**Failure ID:** PG-003

**Symptom:** A coverage target is stated in the prompt and a
make coverage target is specified in Step N, but the
testbench file where new tests are added is different from
the testbench compiled by that make target.

**Root cause:** BP-026 loaded tb_tage.sv in Context Loaded
and directed new tests there, but Step 8 specified
make cov_tage_table which compiles tb_tage_table.sv.

**Correct form:** Every prompt that states a coverage target
must explicitly link three things in the same section:

  1. The module under measurement
  2. The make target that measures it
  3. The testbench file that target compiles

Never leave the relationship between coverage make target
and testbench file implicit.

---

### Anti-pattern: Design decision stated without source
### citation

**Failure ID:** PG-004

**Symptom:** A design decision is written into a deliverable
based on Claude's assumption rather than a cited source. The
decision is later found to be incorrect, requiring rework.

**Root cause:** In the ITTAGE struct session, "no
alt-provider" was stated and written into
ittage_pred_meta_t without verifying against Seznec's paper.
The paper explicitly defines altpred and USE_ALT_ON_NA
for ITTAGE.

**Correct form:** Before stating any design decision, cite
the source. If the source cannot be cited, ask before
asserting. Never write an unverified design decision into
a deliverable.

---

### Anti-pattern: Uncertainty not flagged before writing
### deliverable

**Failure ID:** PG-005

**Symptom:** Claude is uncertain about a design detail but
proceeds to write it into a deliverable rather than flagging
the uncertainty and asking for confirmation first.

**Root cause:** Same ITTAGE session. The alt-provider
question was not verified but was written as fact into the
struct.

**Correct form:** When uncertain about a design detail,
state the uncertainty explicitly and ask before writing it
into any deliverable.


### Anti-pattern: PA Behavior Failure — Session-045 Step 1
**Failure ID:** PG-006

**Symptom:** During the Step 1 tooling task, the PA introduced 
a bug in the overview extraction logic of gen_sessions.py. The
parser looked for overview content between
:: HEADER:END :: and :: DISCUSSION:START ::, but the
template places # Overview of task and its content inside
the header block, before :: HEADER:END ::. This was
visible in the template provided at session start.

When Jeff reported overview: null in the JSON output, the
PA incorrectly diagnosed a template structure problem and
proposed moving the heading outside the header block — a
change to Jeff's input data — rather than reading the
template correctly and fixing the parser.

Jeff rejected the diagnosis. The PA then read the template
correctly and fixed the parser: overview is now extracted
from within header_text using a regex search for

\# Overview of task, taking all content following that
heading to the end of the header block.

**Failure mode to watch for:**
When a parser produces null or missing output, the PA must
verify its own extraction logic against the actual template
structure before suggesting changes to prompt files or
planning documents. Blaming input data is the wrong first
move.
**Resolution:** gen_sessions.py corrected and verified.
overview field now populates correctly from existing prompt
files without any template or backfill changes required.
