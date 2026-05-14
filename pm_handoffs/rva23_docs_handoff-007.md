# Session Handoff: RVA23 Co-Design Documentation Project

This is the documentation sub-project for the RVA23 Co-design project.

This is a handoff from PM 7. The new session will be PM 8.
This file is named rva23_docs_handoff-007.md.

We are continuing the postmortem and blog series for the BPU co-design
track. Read this document fully before proceeding. Raise any
inconsistencies immediately.

NOTE: the context isolation pattern is only for the IA (Claude Code)
sessions. This is a documentation session using the PA (Claude.ai) pattern.

---

## BPU Blog Series Structure (Unchanged)

Four posts planned:

  BLOG_bpu_1_cluster_arch.md   -- Part 3 sessions. BP-001. SIGNED OFF.
  BLOG_bpu_2_history_ubtb.md   -- Parts 4 and 5 combined. SIGNED OFF.
  BLOG_bpu_3_loop_pred.md      -- Parts 6-9. Written PM 7. Pending sign-off.
  BLOG_bpu_4_limits.md         -- Part 10 standalone. Not yet written.

---

## Work Completed This Session (PM 7)

### BLOG_bpu_2_history_ubtb.md -- Signed Off

Diagrams accepted at the start of PM 7. BPU-2 is complete and signed off.

### BLOG_bpu_3_loop_pred.md -- Written, Pending Sign-Off

The blog is written and pending user review. Current file is at:
  /mnt/user-data/outputs/BLOG_bpu_3_loop_pred.md

Final section list:
  - The Loop Predictor at s1
  - Loop Predictor Design
    - Entry Format
    - Index and Tag Derivation
    - Prediction Pipeline
    - Confidence Gating and Override
    - Victim Selection
    - The Update Path
    - The lp_hit Fix
  - Experiments BP-004 through BP-004f
  - Prompt Discipline
  - Experiment Summary
  - What Comes Next
  - Design Process Notes
    - Domain knowledge supplied by the user
    - What the PA contributed
    - What the prompt constrained versus what the IA filled in
    - The generalization
  - References ([1])

### Corrections Applied During PM 7

The following corrections were made during drafting and review:

Entry format presented as a proper markdown table. Original draft used
a code block with inline layout comment; replaced with a three-row
table (Bits, Field, Width).

Prediction/update interface model introduced at the top of the Loop
Predictor Design section, before the first subsection. Original draft
had no introduction to the two-interface structure.

False claim about XOR mixing distributing PC bits evenly removed.
Replaced with neutral description: mixing shifted copies of the PC
is a standard technique for producing a compact index or tag from a
wider address, reducing aliasing relative to a direct bit slice.

uBTB comparison removed from Index and Tag Derivation section. The
uBTB introduction was not relevant in that context.

Code blocks for hash functions changed to triple-backtick format for
correct rendering.

"Trusted" replaced throughout with precise signal names or descriptions.
The term was used before it was defined and was not the right framing.

Redundant clause removed from prediction pipeline paragraph (consumer
obligations restated after already being stated).

Five update conditions converted from prose to a markdown table.
Condition 5 annotated as added in BP-004d.

lp_hit fix section explicitly attributes identification to the IA
during implementation, not the PA during specification review.

BP-004 abandonment wording changed from "BP-004 was marked abandoned
and split" to "BP-004 was marked abandoned and the task was subdivided."

TC5 design choice reported as an IA discovery: the need for a wrong-exit
step to establish past_itr before the confidence sequence, and the
independent choice of past_itr=1 to minimize setup cycles. Both
documented in BP-004e results capture.

CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000 environment variable addition
reported. Set after the first BP-004 failure as a follow-on action.
The increased limit did not prevent the second failure (token limit
hit during generation) or the BP-004b failure (context exhaustion).

References section contains only one entry: Seznec 2011, cited in
text as [1] for the lp_hit fix design origin. No other citations added.

### Diagrams Required for BPU-3

Two diagrams are flagged for production, same pattern as BPU-2.
Both are placeholders in the current draft:

  loop_pred_structure.svg  -- structural diagram of loop_pred module.
    Should show: the four register ways (the table array), the
    prediction combinational block (s0), the output register (end of
    s0, valid at s1), and the update synchronous block. Analogous to
    history_module.svg from BPU-2.
    Referenced in blog as: ![Loop Predictor Structure](diagrams/loop_pred_structure.svg)
    STATUS: not yet produced.

  loop_pred_entry.svg  -- entry bit-field strip.
    Horizontal rectangle subdivided into eight named fields per the
    entry format table: v (1b), cnf (2b), age (8b), curr_itr (14b),
    past_itr (14b), tag (14b), curs (14b), curs_v (1b). Bit positions
    annotated at field boundaries. Total width 68b annotated.
    Referenced in blog as: ![Loop Predictor Entry Fields](diagrams/loop_pred_entry.svg)
    STATUS: not yet produced.

---

## Source Materials Used for BPU-3

The following documents were retrieved and used as source material
during PM 7. These do not need to be re-retrieved for BPU-4.

  BP-004.md          -- abandoned, token limit. Overview and prompt.
  BP-004a.md         -- PASS. Structs added to bp_pkg.sv.
  BP-004b.md         -- abandoned, context exhaustion.
  BP-004c.md         -- PASS. loop_pred.sv RTL, 250 lines. Full results
                        capture including lp_hit structural gap as
                        Deferred Work #2.
  BP-004d.md         -- PASS. lp_hit fix. Full results capture.
  BP-004e.md         -- PASS. TC1-TC7 testbench and Makefile.
  BP-004f.md         -- PASS. TC8-TC13 appended. 13/13 PASS.
                        Generation timeout on first attempt (1h 6m).
                        Second attempt completed (33m 4s).
  loop_pred_interfaces.md  -- authoritative interface specification.
  session_handoff-007.md   -- BP-004 split decisions, backward branch
                              filter, lp_upd_t target field.
  session_handoff-008.md   -- bp_pkg.sv split, BP-004b abandonment,
                              BP-004c/d/e scope decisions.
  session_handoff-009.md   -- lp_hit fix adopted, BP-004d/e/f renumber.

  RVA23 Co-Design Part 10 was identified as the session containing
  the BP-004f generation timeout event and the decision to advance
  TAGE ahead of FTB. Part 10 material is primary source for BPU-4.

---

## Open Items for PM 8

### BLOG_bpu_3_loop_pred.md -- Sign-Off

PM 8 should confirm BPU-3 status with the user at the start of the
session. If accepted, BPU-3 is signed off and diagrams can be
produced or deferred per BPU-2 precedent.

### Diagrams for BPU-3

loop_pred_structure.svg and loop_pred_entry.svg are not yet produced.
If BPU-3 is signed off, produce diagrams following the same approach
as BPU-2: standalone SVGs, hardcoded colors, Inkscape and Jekyll
compatible, no inline SVG in Markdown source.

### Begin BLOG_bpu_4_limits.md

BPU-4 covers Part 10 standalone: PA limits and failures during the
BP-004f session and the TAGE feasibility assessment sessions.

Source materials for BPU-4:
  - RVA23 Co-Design Part 10 (primary: BP-004f timeout, web search
    for workaround, confirmation generation timeout is not configurable,
    decision to advance TAGE)
  - Session handoff-011 (written at end of Part 10)
  - Any subsequent TAGE sessions where generation limits recurred

Search terms for PM 8 session history retrieval:
  - "generation timeout BP-004f validate_and_extract"
  - "TAGE feasibility Claude Code limits session 10 11"
  - "session handoff 011"

The handoff from PM 6 notes that session 10 "probably needs its own
blog." BPU-4 is that blog.

---

## Current Blog File Status

### Signed off
  BLOG_bpu_1_cluster_arch.md -- complete
  BLOG_bpu_2_history_ubtb.md -- complete

### Written, pending sign-off
  BLOG_bpu_3_loop_pred.md -- text complete, diagrams not yet produced

### Not yet started
  BLOG_bpu_4_limits.md       -- Part 10 (PA limits and failures)

### Carried Forward (unchanged from PM 3)
  rva23_docs_decoder_part2-pm-002.md
  rva23_docs_decoder_part3-pm-002.md
  BLOG_decoder_1_rva23_profile.md
  BLOG_decoder_2_scalar_to_alu.md
  BLOG_decoder_3_memory_to_closure.md
  rva23_docs_methodology-pm-001.md
  rva23_docs_tools-pm-001.md
  rva23_docs_decoder_part1-pm-001.md
  BLOG1.md

---

## Deferred Items (Unchanged from PM 3/4)

- BLOG_tools.md not yet written. Source: rva23_docs_tools-pm-001.md.
  Deferred until after TAGE/BPU work.
- PROJECT_STATUS.md and PROJECT_CORE.md not yet introduced in blog
  narrative.
- Series index page (index.md) deferred until series grows beyond
  three posts.
- Methodology blog (BLOG1.md) is a copy of rva23_docs_methodology-pm-001.md.
  Revised narrative version deferred until more sessions documented.

---

## Documentation Rules (Unchanged)

- No non-ASCII characters in any output except diagrams.
- Diagrams are SVG, stored as separate files, referenced in Markdown as
  ![alt](diagram.svg). No inline SVG in Markdown source.
- Acronyms expanded on first use in each document.
- Blog posts use YAML front matter with title, author, date, copyright.
- Copyright year: 2026.
- Series navigation block immediately after title, before first paragraph.
- Stats table header: "Experiment" not "Task ID".
- References minimal, only where genuinely needed.

---

## Suggested PM 8 Starting Point

1. Confirm BLOG_bpu_3_loop_pred.md status with user.
   If accepted, sign off BPU-3.

2. Decide on BPU-3 diagram approach: produce now or defer as with BPU-2.

3. Retrieve BPU-4 source materials by searching PA session history
   for Part 10 content and session_handoff-011.

4. Write BLOG_bpu_4_limits.md covering the tooling limits experience.
   Follow the same structure conventions as BPU-1 through BPU-3.

