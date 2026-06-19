<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 002

Written by Claude.ai at end of session-002.
Date: 2026-03-27

This is the delta from session-002. Read PROJECT_STATE.md first,
then this file, then CLAUDE.md to restore full context.

---

## What This Session Covered

Session-002 was a methodology and tooling session, not an RTL session.
No new RTL was written. The decoder track is complete as of session-001.

The session focused on:
1. Claude Code workflow analysis and optimization
2. Experiment file structure refinement
3. Context minimization strategy
4. Planning directory design
5. Interface specification approach for the BP cluster
6. Handoff process improvement (PROJECT_STATE.md split)
7. Research into AI-assisted hardware timing analysis

---

## Decisions Made This Session

### Experiment file is the single document of record
The REPORT_TEMPLATE.md was finalized. One file per experiment contains
the prompt, context manifest, results, and discussion. Claude Code
writes its Results Capture section directly into the file as a
deliverable -- Jeff does not copy-paste it manually.

Template location: prompts/TEMPLATE.md
Example: prompts/frontend/decoder/DECODE-004.md

### Context Loaded manifest replaces STATE.md
Rather than a separate STATE.md file that Claude Code reads at session
start, the context manifest lives directly in the prompt as a
Context Loaded section with explicit @file references. Claude Code
loads exactly those files and nothing else.

This gives Jeff explicit control over context cost per task and makes
each experiment fully reproducible from its file alone.

### planning/ directory added
Location: project root alongside CLAUDE.md.
Initial structure with placeholders is in place.
Interface-first: define all BP cluster interfaces as SV packages in
a dedicated session before any implementation RTL is written.

### Handoff process split into two files
- PROJECT_STATE.md: cumulative, always current, absorbs settled decisions
- session_handoff-NNN.md: delta only -- what changed this session

Paste order for new Claude.ai session:
1. PROJECT_STATE.md
2. session_handoff-NNN.md (latest)
3. CLAUDE.md

### TOOLS-002 explicitly deferred
The spike-dasm ISA string issue is not blocking BP cluster work.
TOOLS-002 is parked. Do not spend time on it until the oracle
is actually needed for BP verification.

---

## BP Cluster -- Context for Next Session

The next Claude.ai session should begin BP cluster planning.
Jeff has the micro-architecture in his head. The session should:

1. Extract the BP cluster hierarchy from Jeff -- which predictors,
   what roles, what the override/redirect architecture looks like.

2. Run an interface-first session: define all structs in bp_pkg.sv
   before any RTL is written. Key interfaces to define:
   - bp_pred_req_t   (fetch -> cluster, P0.comb)
   - bp_pred_resp_t  (cluster -> fetch, P1.clk)
   - bp_update_req_t (commit -> cluster, async to prediction path)
   - Per-predictor internal interfaces as needed

3. Write bp_cluster.md in planning/arch/ capturing:
   - Predictor hierarchy and roles
   - Pipeline depth and timing decisions
   - Override/redirect architecture
   - Simultaneous request handling rules

4. Then and only then write BP-001 -- the first implementation
   experiment. BP-001 scope TBD but likely bp_pkg.sv definition
   and cluster top-level shell.

### What Jeff dictates for BP (do not let Claude Code decide)
- Which predictors are in the cluster and their roles
- Prediction pipeline depth (when prediction is available relative
  to fetch request)
- Who can override whom and at what latency cost
- Training/update policy (speculative vs. retired updates)
- Flush/misprediction handling architecture

### What Claude Code can propose (subject to Jeff review)
- Internal signal naming within conventions
- Struct field decomposition
- Testbench structure
- Parameter names and widths within specified ranges

### Timing -- known gap
Timing intent must be expressed as constraints in the planning
document and verified by Jeff reviewing the RTL. Verilator does
not provide timing data. No open-source tool handles SystemVerilog
timing estimation reliably without full synthesis. This is a known
methodology gap -- document it honestly in the methodology writeup.

The pipe stage notation (P0.comb, P1.clk) in struct comments is
the mechanism for expressing timing intent to Claude Code.

---

## Status Line Setup (for reference)
Jeff's Claude Code status line is working. Script at
~/.claude/statusline.sh (global, not in repo). Displays:
  Total: <tokens> | Ctx: <k used> | Ctx: <%used>
  Reset: <Hh MMm>
Context field uses used_percentage (the accurate field per docs).
Reset countdown from rate_limits.five_hour.resets_at Unix timestamp.
jq is required and now installed.

---

## Methodology Document Note
Jeff intends to write up this methodology for an audience of
experienced hardware architects evaluating AI-assisted design flows.
The decoder track is documented. The BP cluster track will be the
second case study -- more complex because micro-architectural
decisions are open, interfaces are not predetermined by a spec,
and multi-module consistency becomes a real problem.

Capture methodology observations in docs/observations/ as they arise
during BP cluster work. These are raw material for the writeup.

