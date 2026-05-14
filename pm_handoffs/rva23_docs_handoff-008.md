# Session Handoff: RVA23 Co-Design Documentation Project

This is the documentation sub-project for the RVA23 Co-design project.

This is a handoff from PM 8. The new session will be PM 9.
This file is named rva23_docs_handoff-008.md.

We are continuing the blog series for the BPU co-design track.
Read this document fully before proceeding. Raise any
inconsistencies immediately.

NOTE: the context isolation pattern is only for the IA (Claude Code)
sessions. This is a documentation session using the PA (Claude.ai) pattern.

---

## BPU Blog Series Structure (Updated)

The series is open-ended. Navigation blocks in all four existing posts
have been updated (manually by user) to read "a series on branch
predictor co-design" rather than "a four-part series." TAGE and FTB
posts will be added as the series grows.

Current posts:

  BLOG_bpu_1_cluster_arch.md   -- Part 3 sessions. BP-001. SIGNED OFF.
  BLOG_bpu_2_history_ubtb.md   -- Parts 4 and 5 combined. SIGNED OFF.
  BLOG_bpu_3_loop_pred.md      -- Parts 6-9. SIGNED OFF.
  BLOG_bpu_4_limits.md         -- Part 10 standalone. SIGNED OFF.

Planned posts:

  BLOG_bpu_5+  -- TAGE sessions. Parts 11-28. Not yet structured.
  BLOG_bpu_N   -- FTB. Deferred. Timing TBD.

---

## Work Completed This Session (PM 8)

### BLOG_bpu_3_loop_pred.md -- Signed Off

Signed off at start of PM 8. Both diagrams (loop_pred_structure.svg
and loop_pred_entry.svg) deferred. User will manually edit any
structural description as needed. BPU-3 is complete.

### BLOG_bpu_4_limits.md -- Written and Signed Off

Written and signed off during PM 8. File is at:
  /mnt/user-data/outputs/BLOG_bpu_4_limits.md

Final section list:
  - A Session That Needs Its Own Post
  - Two Distinct Failure Modes
  - The BP-004f First Attempt (includes TC1-TC13 table)
  - Searching for a Fix
  - What This Means
  - The Second Attempt
  - CLAUDE.md Updates
  - The TAGE Decision
  - Experiment Summary
  - What Comes Next
  - Design Process Notes
    - What the session exposed about the methodology
    - What the PA contributed
    - What the IA contributed
    - The generalization

Key content decisions made during PM 8:

TC1-TC13 table added to The BP-004f First Attempt section showing
test case descriptions and which experiment (BP-004e or BP-004f)
each belongs to.

Blog written from user's edited draft as base. User edits accepted
as authoritative over PM 8 initial draft.

No references section. claudecodeguides.com described in prose but
not formally cited -- it is a third-party site describing undocumented
behavior, not a stable reference.

The TAGE Decision section notes that TAGE was advanced ahead of FTB
to serve as a feasibility stress test on the generation ceiling.

---

## Decisions Made This Session (PM 8)

### Blog as primary record, postmortem deferred

The postmortem as a separate document class is deferred until a
publication target different from the blog emerges. The blogs carry
the technical narrative, design process notes, PA/IA attribution,
and experiment record. Microarchitecture specifications are the
companion artifacts. The postmortem function will be served by a
single methodology assessment written once the full project arc
is visible.

Bounding statements established for blog vs postmortem scope:

  Blog: Explains design decisions and challenges to a technically
  capable reader with processor design background but no project
  familiarity. Organized by concept. Adds explanatory context not
  written during implementation. Omits experiment scaffolding and
  session mechanics unless those are the topic. Methodology appears
  only where it shaped a design decision.

  Postmortem: Assesses what happened, what worked, what did not,
  and how the methodology evolved. Full experimental sequence with
  outcomes. Records failures, abandoned experiments, and adaptations
  explicitly. Methodology evolution assessment is the primary value.
  Assumes full project familiarity.

### Chat session export adopted

Claude Exporter (Firefox extension by agoramachina) adopted for
session preservation. Configuration: Markdown format, Nested
organization, Original format for artifacts, Chats and Metadata
checked, Thinking unchecked. Sessions to be exported to a sessions/
directory in the repo alongside existing handoff documents.

### TAGE blog scope

TAGE sessions run from RVA23 Co-Design Part 11 to Part 28 (18
sessions). PM 9 first task is to retrieve and catalog these sessions
to determine how many blog posts the TAGE material warrants and
where the natural split points are.

---

## Source Materials Used for BPU-4

  RVA23 Co-Design Part 10 -- primary source. BP-004f generation
    timeout event, web search for workaround, confirmation that
    generation timeout is not configurable, TAGE priority decision.
  session_handoff-011.md  -- pasted by user. BP-004e completion,
    validate_and_extract.py adoption, slash command migration.
    Provided context for the two distinct failure modes framing.

---

## Open Items for PM 9

### TAGE blog series planning

TAGE sessions run Parts 11-28. PM 9 should:

1. Retrieve session content for Parts 11-28 using conversation_search.
   Suggested search terms:
     - "TAGE implementation BP-005"
     - "TAGE feasibility assessment context limit"
     - "tage_table.sv BP-006"
     - "TAGE testbench TC"
     - "session handoff 012" through "session handoff 020" as needed

2. Build a session map showing what each Part covered, which
   experiments ran, pass/fail status, and any notable tooling events.

3. Determine natural split points for blog posts. The loop predictor
   took one blog (BPU-3) plus one limits blog (BPU-4). TAGE is
   substantially more complex and covers 18 sessions. Multiple posts
   likely warranted.

4. Propose a blog structure to the user for approval before writing.

### Navigation block update

All four existing blog posts need their navigation blocks updated
once the TAGE post titles and filenames are known. This is a
mechanical edit the user can apply manually once the structure
is settled.

---

## Current Blog File Status

### Signed off
  BLOG_bpu_1_cluster_arch.md -- complete
  BLOG_bpu_2_history_ubtb.md -- complete
  BLOG_bpu_3_loop_pred.md    -- complete, diagrams deferred
  BLOG_bpu_4_limits.md       -- complete

### Not yet started
  BLOG_bpu_5+.md  -- TAGE (Parts 11-28). Structure TBD in PM 9.
  BLOG_bpu_N.md   -- FTB. Deferred.

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
- Series index page (index.md) deferred until series count is stable.
- Methodology blog (BLOG1.md) is a copy of rva23_docs_methodology-pm-001.md.
  Revised narrative version deferred until more sessions documented.
- loop_pred_structure.svg and loop_pred_entry.svg not produced.
  User will manually edit structural description in BPU-3 if needed.

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

## Suggested PM 9 Starting Point

1. Read this handoff fully. Confirm no inconsistencies.

2. Retrieve TAGE session content Parts 11-28 from conversation_search.

3. Build session map for Parts 11-28.

4. Propose TAGE blog structure to user for approval.

5. Begin writing on user approval.

