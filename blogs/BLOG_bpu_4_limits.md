<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
---
title: "When the Tools Fail: Hidden Limits in AI-Assisted Hardware Design"
author: Jeff Nye
date: 2026-03-31
copyright: "Copyright 2026 Jeff Nye"
---

*This is part 4 of a series on branch predictor co-design.
[Part 1: Cluster Architecture](BLOG_bpu_1_cluster_arch.md) |
[Part 2: History and uBTB](BLOG_bpu_2_history_ubtb.md) |
[Part 3: Loop Predictor](BLOG_bpu_3_loop_pred.md) |
[Part 4: When the Tools Fail](BLOG_bpu_4_limits.md)*

---

## A Session That Needs Its Own Post

The branch predictor (BP) co-design sessions through Part 9 followed a
recognizable arc: define the experiment, write the prompt, run Claude Code,
review results, adapt. The loop predictor required more adaptation than the
history module or micro Branch Target Buffer (uBTB) -- six experiment files
instead of one -- but each failure was understood, addressed, and resolved
within a session or two. The methodology bent under load but did not break.

Part 10 was different. The session that completed the loop predictor testbench
(BP-004f, TC8-TC13) produced the clearest evidence yet that the tooling has
hard limits that are not documented, not configurable, and not solvable by
any adjustment available to the user. The experience of hitting those limits
-- and of searching for a fix that does not exist -- is the subject of this
post.

This is not a design post. No new module is described here. The loop predictor
design, implementation, and verification are covered in
[Part 3](BLOG_bpu_3_loop_pred.md). This post is about what happens when the
tools reach their ceiling on a task that is not especially large by hardware
design standards.

---

## Two Distinct Failure Modes

Before Part 10, the BP-004 series had already produced two failure modes worth
distinguishing clearly, because they have different causes and different fixes.

The first is `context exhaustion`. The Claude Code implementation assistant (IA)
operates with a finite context window. When a session loads too many files --
the full experiment file including all template scaffolding, multiple large
RTL files, and the planning document simultaneously -- the context window fills
before generation begins. The session produces no output and exits. This is
what killed BP-004b: six files loaded, context exhausted, nothing generated
after 50 minutes.

The fix for context exhaustion is scope reduction on the input side.
validate_and_extract.py was written during session 9 to address exactly this.
The script validates the experiment file structure, then extracts only the
PROMPT section to a known path. Claude Code reads the focused prompt rather
than the full file. Context pressure drops substantially. BP-004e passed after
BP-004b failed. The fix worked.

The second failure mode is `generation timeout`. This is different in a way that
matters: it is a limit on the output side, not the input side. The model can
load context successfully and then fail to produce output because the
generation itself -- the act of writing a large block of code -- exceeds a
time limit enforced by the Anthropic application programming interface (API).
No input reduction fixes this. Reducing context may help indirectly by leaving
the model more working capacity, but the ceiling is on output length and
generation time, not on what was read.

BP-004f demonstrated both the distinction and its consequence.

---

## The BP-004f First Attempt

BP-004f was scoped to append TC8 through TC13 to the existing tb_loop_pred.sv
testbench. The testbench at that point was 357 lines covering TC1 through TC7.
Appending six more test cases would produce approximately 380 lines of new
code, bringing the file to roughly 735 lines total. This is not a large file
by any measure of hardware verification. A 735-line testbench for a 250-line
module is a normal ratio.

The full set of thirteen test cases, split across BP-004e and BP-004f, is:

| TC   | Experiment | Description                                                    |
|------|------------|----------------------------------------------------------------|
| TC1  | BP-004e    | Miss returns pred_is_loop=0                                    |
| TC2  | BP-004e    | Allocate on backward branch miss, verify index and way         |
| TC3  | BP-004e    | Forward branch miss does not allocate (backward branch filter) |
| TC4  | BP-004e    | Hit below LP_CONF_LEVEL returns pred_is_loop=0                 |
| TC5  | BP-004e    | Confidence builds to LP_CONF_LEVEL after correct exits         |
| TC6  | BP-004e    | Trusted prediction: curr_itr < past_itr predicts taken         |
| TC7  | BP-004e    | Trusted prediction: curr_itr == past_itr predicts exit         |
| TC8  | BP-004f    | Correct exit: conf increment, counter copy, age reset          |
| TC9  | BP-004f    | Wrong exit: conf reset, counter copy and reset                 |
| TC10 | BP-004f    | Mispredicted exit: conf and counter reset                      |
| TC11 | BP-004f    | Victim selection under a full set                              |
| TC12 | BP-004f    | Way conflict: two PCs mapping to same index                    |
| TC13 | BP-004f    | curr_itr saturation at LP_ITR_BITS maximum                     |

The first attempt ran for 1 hour and 6 minutes. Claude Code read all four
context files successfully. Then it produced nothing. The console reported:

```
Request timed out
Baked for 1h 6m 16s
```

The model had loaded the context, presumably begun generating, and then hit
the generation timeout before producing any output. No partial output was
written. No error message identified the root cause. The session simply
stopped.

---

## Searching for a Fix

The immediate question after the timeout was whether this was configurable.
Claude Code exposes environment variables and settings for various limits.
BASH_DEFAULT_TIMEOUT_MS controls how long bash commands are allowed to run.
settings.json accepts timeout configuration for some operations. The
CLAUDE_CODE_MAX_OUTPUT_TOKENS environment variable had already been set to
64000 earlier in the BP-004 series, after the first BP-004 attempt failed on
token limits. If there was a lever for generation timeout, it was not obvious
from the tooling surface.

A web search was run from within the planning assistant (PA) session:
first for "Claude Code generation timeout long output workaround," then
specifically for "generation timeout" to narrow to the relevant failure class.

The most direct result came from claudecodeguides.com, which addressed the
question without ambiguity:

*There is no --timeout flag for the claude command-line interface (CLI).
There is no skillDefaults configuration in settings.json. There is no
CLAUDE_SKILL_TIMEOUT environment variable. Generation timeout is governed
by the Anthropic API response limits, not by any configuration available
through skill files or CLI flags. The fix is always scoping the request
down. There is no other lever available.*

The BASH_DEFAULT_TIMEOUT_MS variable that appears in most search results
addresses bash command execution timeout, not generation timeout. These are
different limits at different layers of the system. Increasing bash timeout
does nothing for a model that times out during text generation.

GitHub issues confirmed the pattern. Issue #5804 in the Claude Code
repository is a bug report for API request timeout during long-running code
generation. Issue #1539 documents that Claude Code does not reliably respect
its own timeout extensions. Neither issue had a resolution that applied to
the generation timeout class, as of 2026.05.01.

---

## What This Means

The practical consequence is that generation timeout is a hard ceiling with
no configuration path available to the user. The ceiling is governed by
Anthropic API response limits that are not exposed as project settings. When
a generation task is large enough to approach or exceed that ceiling, the
available responses are:

Split the task into smaller units, each of which stays within the limit
individually. This is what was done for BP-004f and for the earlier BP-004
fracture from one experiment file into six. It works, but it adds experiment
files, session overhead, and prompt authoring time to every task that
exceeds the limit.

These are the decisions for the present:

* Accept that some tasks may exceed the limit on the first attempt and require
a second run with a reduced scope.
    * This is not predictable in advance.
    * Estimating output size from prompt scope is imprecise, and there is no
pre-flight check that identifies whether a given prompt will hit the limit
before it runs.

* Replace Claude Code with a different generation path for tasks that
consistently exceed the limit.
    * Driving generation directly through the
Anthropic API with streaming output and a client-controlled timeout would
bypass the Claude Code generation ceiling entirely.
    * This was noted as a
potential future replacement for the Claude Code role in the generation
pipeline, to be revisited after the Tagged GEometric history length
predictor (TAGE) feasibility assessment.

The user interaction in session 10 captured the core frustration directly:

* how are we supposed to know without running that it will exceed the limit?
    * The answer, in the current state of the tooling, is that you cannot know
with certainty.
    * You can estimate output size, apply heuristics from prior
sessions, and structure prompts conservatively. None of that guarantees a
clean first run when the task is near the ceiling.

---

## The Second Attempt

The second attempt at BP-004f used validate_and_extract.py to reduce the
context presented to Claude Code. The extracted prompt is smaller than the
full experiment file by design -- it omits the template scaffolding, results
placeholders, and discussion sections that serve the PA workflow but add
no value to the IA's generation task.

This did not directly fix the generation timeout. The timeout is on the
output side, not the input side. But reducing context load may have left
the model with more effective working capacity for generation. The second
attempt ran for 33 minutes and 4 seconds and completed successfully. TC8
through TC13 were appended to tb_loop_pred.sv. All 13 test cases passed
under Verilator 5.020 with zero warnings and exit 0.

Whether the reduced context was the determining factor or whether the first
attempt was close enough to the ceiling that normal run-to-run variation
accounted for the difference is not known. The data point is: same task,
reduced context input, successful completion in 33 minutes versus timeout
at 66 minutes.

---

## CLAUDE.md Updates

Three updates to CLAUDE.md followed the BP-004f session. Each addresses a
specific failure mode observed during the BP-004 series.

The first rule requires Claude Code to write Results Capture content only
within the designated marker region of the experiment file. Earlier sessions
had produced results written outside the markers, which broke the structured
format that subsequent tooling depends on.

The second rule requires ASCII-only content in Results Capture sections.
Unicode characters, checkmarks, non-ASCII arrows, and emoji had appeared in
results output from some sessions, causing downstream issues with tooling and
documentation.

The third change removed a redundant instruction that told Claude Code to
narrate the context load manifest. The @ reference syntax in the experiment
prompt handles file loading directly. The narration step added no value and
had occasionally produced false validation output -- Claude Code reporting
that context was loaded when the file had not been read correctly.

Each rule addresses something observed rather than anticipated. The CLAUDE.md
document is a record of what the tooling actually does under pressure, not
what the documentation suggests it should do.

---

## The TAGE Decision

The session ended with a decision to advance TAGE ahead of the Fetch Target
Buffer (FTB) in the implementation sequence to further explore the limit issues found in the loop predictor implementation.

TAGE is substantially more complex than the loop predictor. Five tables,
multiple index and tag hash inputs, a three-stage prediction pipeline,
a complex provider and alternate-provider update path, and a Statistical
Corrector (SC) dependency. If the Claude Code generation flow has a practical
ceiling near 380 lines of new output per session, TAGE is the right module
to test that ceiling on before investing further in the tooling.

FTB is deferred. If TAGE exposes further generation limit problems, the
Python API streaming approach or some other alternative can be evaluated
with evidence from a genuinely complex module, not from a 735-line
testbench that would be considered modest by any reasonable standard.

The decision to use TAGE as a feasibility stress test is methodologically
sound. It surfaces the tooling ceiling problem at a controlled point in the
development sequence rather than discovering it mid-implementation of a
module that cannot be easily split.

---

## Experiment Summary

| Experiment | Description                | Status    | Checks | RTL Lines | Runtime              | Context |
|------------|----------------------------|-----------|--------|-----------|----------------------|---------|
| BP-004f    | tb_loop_pred TC8-TC13      | Abandoned | --     | 0         | 1h 6m 16s (timeout)  | --      |
| BP-004f    | tb_loop_pred TC8-TC13      | PASS      | 13/13  | ~380      | 33m 4s               | 68%     |

---

## What Comes Next

With the loop predictor complete and the tooling ceiling documented, the next
sessions begin TAGE implementation. The first step is a feasibility assessment:
can the Claude Code generation flow handle a module of TAGE's complexity, or
does the ceiling make it impractical without a different generation path?

That question is examined in subsequent posts as the TAGE implementation
proceeds.

---

## Design Process Notes

### What the session exposed about the methodology

The BP-004 series produced a clean taxonomy of failure modes in the Claude
Code generation flow. Context exhaustion and generation timeout are distinct
problems at different layers of the system, with different symptoms and
different available responses.

Context exhaustion is solvable. validate_and_extract.py addresses the input
side of the problem by ensuring Claude Code reads a focused prompt rather than
a full experiment file with all its scaffolding. The fix is stable and has been
adopted as standard tooling.

Generation timeout is not solvable within the current Claude Code surface.
The limit is a hard API ceiling with no configuration path. The only available
response is scope reduction on the output side, which means splitting tasks
that exceed the limit into smaller units. This adds overhead but does not
prevent completion.

The more significant finding is that neither limit is documented in a way that
allows pre-flight estimation. Output size can be approximated from prompt scope
and prior session data, but the estimate is imprecise and the limit is not
published. The user hit a 66-minute timeout on a task that produced 380 lines
of output -- a task that would be considered small in any conventional
verification workflow. The ceiling is lower than the task profile of this
project.

### What the PA contributed

The PA ran the web search for generation timeout workarounds when the first
BP-004f attempt failed. That search produced the claudecodeguides.com
confirmation that the limit is a hard API ceiling with no configuration lever.
The PA documented this as a known project risk in the session handoff and
authored the three CLAUDE.md updates that followed.

The decision to advance TAGE ahead of FTB was reached in the PA session at
the close of Part 10, with the user's agreement. The reasoning -- use TAGE
as a feasibility stress test before investing further in tooling -- was the
PA's framing.

### What the IA contributed

The IA completed BP-004f on the second attempt without modification to the
prompt. Given the same task with reduced context input, it produced 380 lines
of new testbench code covering six test cases, all passing. The IA also
identified the structural assumptions that made TC11 (victim selection under
a full set) and TC13 (saturation) non-trivial to write, and documented its
approach in the results capture.

### The generalization

A domain expert applying this methodology to any subsystem of comparable
or greater complexity should expect to encounter both failure modes. Context
exhaustion is manageable with disciplined prompt scoping and extraction
tooling. Generation timeout requires task decomposition at the experiment
file level. Neither has a configuration fix. Both require the engineer to
maintain an intuition for output size that the tooling does not provide
directly.

The 380-line data point from BP-004f is the most concrete evidence available
from this project for where the generation ceiling sits. Tasks that produce
significantly more output than this in a single session are at risk. Tasks
that can be decomposed to stay well below this threshold are not. Planning
should account for this.

---

*No references required for this post.*

