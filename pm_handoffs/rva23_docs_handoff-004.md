# Session Handoff: RVA23 Co-Design Documentation Project

This is the documentation sub-project for the RVA23 Co-design project.

This is a handoff from PM 4. The new session will be PM 5.
This file is named rva23_docs_handoff-004.md.

We are continuing the postmortem and blog series for the BPU co-design
track. Read this document fully before proceeding. Raise any
inconsistencies immediately.

NOTE: the context isolation pattern is only for the IA (Claude Code)
sessions. This is a documentation session using the PA (Claude.ai) pattern.

---

## Corrections Established This Session

- Copyright year in YAML front matter corrected to 2026.
  All blog files use: copyright: "Copyright 2026 Jeff Nye"
- The PM 3 handoff listed "Copyright 2025" -- this is wrong everywhere
  it appears and must be corrected in any existing blog files on disk.

---

## BPU Blog Series Structure (Decided PM 4)

Four posts planned:

  BLOG_bpu_1_cluster_arch.md   -- Part 3 sessions. BP-001. COMPLETE DRAFT.
  BLOG_bpu_2_history_ubtb.md   -- Parts 4 and 5 combined. Not yet written.
  BLOG_bpu_3_loop_pred.md      -- Parts 6-9. Not yet written.
  BLOG_bpu_4_limits.md         -- Part 10 standalone. Not yet written.

Series navigation block format (same as decoder series):

  *This is part N of a four-part series.
  [Part 1: title](BLOG_bpu_1_cluster_arch.md) |
  [Part 2: title](BLOG_bpu_2_history_ubtb.md) |
  [Part 3: title](BLOG_bpu_3_loop_pred.md) |
  [Part 4: title](BLOG_bpu_4_limits.md)*

---

## Work Completed This Session (PM 4)

### BLOG_bpu_1_cluster_arch.md -- Draft Complete, Open Items Remain

The blog has gone through multiple review and revision cycles this session.
The current draft exists at:
  /mnt/user-data/outputs/BLOG_bpu_1_cluster_arch.md

Sections in the current draft:
  - A New Aspect of Co-Design
  - Predictor Hierarchy (uses P2 base with P1 splice, see below)
  - Predictor Operation (merged from P1/P2, see below)
  - Redirect Architecture (PARTIALLY CORRECTED -- see open items)
  - Return Address Stack Design
  - FTQ Entry Split
  - Predictor Parameter Reference
  - Interface First: BP-001
  - Prompt Discipline and AI Leverage
  - Experiment Summary
  - What Comes Next
  - References (empty currently)

### P1/P2 Merge Completed

Two versions of the predictor hierarchy and operation section were
provided (p1.txt and p2.txt). These were merged. The merged version:
  - Uses P2 per-predictor operational descriptions as the base
    (uBTB single-cycle, LP single-cycle, FTB two-cycle, etc.)
  - Splices in P1's explicit override chain statement
    (SC overrides TAGE, which overrides FTB, which overrides uBTB)
  - Moves the RAS/ITTAGE type-gate distinction to before the per-
    predictor descriptions, as in P1
  - Retains all P2 bullet points on deliberate design choices

### Design Choice Bullet Points (New Content PM 4)

The following bullet points were drafted and approved for inclusion
in the "deliberate design choices" section:

1. Loop predictor -- atypical in high-performance decoupled front ends,
   included as deliberate choice, cost-benefit via performance analysis,
   exercise in PA/IA performance analysis methodology.

2. TAGE and SC configuration -- conventional. Publications [X] modify
   this to allow SC to use simplified TAGE output one cycle earlier.
   Structured experiment planned for PA/IA to find, implement, and measure.

3. ITTAGE -- extra cycle for full target via region pointer plus adder.
   Direct VA storage possible under some conditions, saving a cycle.
   Performance-analysis-driven decision, PA/IA methodology to research
   conditions and measure benefit.

4. Pre-decode branch detection -- early branch type hint to RAS ahead of
   FTB s2 result, reducing redirect penalty on return-heavy workloads.
   Secondary use: training assist, writing detected type back into FTB
   entry on first encounter. Both represent deliberate choices to be
   exercised in the performance analysis phase.

5. Broad experiment planned to assess PA's ability to mine prediction
   literature for alternative prediction state and predictor types
   (perceptron, etc). Deferred until provably functional frontend exists.

### Diagram Produced

  bpu_pipeline_staging.svg -- pipeline staging Gantt diagram.
  Stored at: /mnt/user-data/outputs/bpu_pipeline_staging.svg

  Description: vertical stack of predictors with horizontal bars spanning
  active pipeline stages s0-s3. Dashed vertical clock boundary lines.
  s2_redirect and s3_redirect annotated. Blue bars = conditional direction
  chain. Coral bars = type-gated (RAS and ITTAGE), separated below a
  dashed divider. Caption identifies color encoding.

  Placement in blog: after the Predictor Parameter Reference section,
  before or within the Redirect Architecture section. To be confirmed
  in PM 5.

  The diagram is a standalone SVG with hardcoded colors (no CSS variable
  dependencies) suitable for Inkscape editing and Jekyll rendering.

### Diagram Inputs Discussion (PM 4)

Predictor inputs established at high level:
  - All predictors receive PC
  - History-dependent predictors (TAGE, ITTAGE, SC) additionally receive
    folded GHR histories via bp_folded_hist_t
  - SC additionally receives TAGE provider counter value (TAGE-then-SC
    dependency)
  - RAS receives branch type from FTB and ret_addr from FTB fallThroughAddr
  - PHR contribution deferred (TBD at implementation)
  - History excluded from the high-level block diagram by user decision

---

## Open Items for PM 5

### Redirect Architecture Section -- Requires Rewrite

This section had a confirmed error and an incomplete correction. 

The error: the original draft stated "TAGE overrides the FTB direction
at s2" -- the FTB has no direction prediction. This was identified and
partially corrected.

The structure problem: the section establishes direction and target as
two distinct concerns up front, then mixes them in the redirect point
descriptions. The user flagged this twice. The correct structure is:

  Direction paragraph: covers s2_redirect (TAGE vs s1) and s3_redirect
  (SC vs TAGE) separately from target discussion.

  Target paragraph: covers s2_redirect (FTB target vs uBTB, RAS vs uBTB)
  and s3_redirect (ITTAGE refinement) separately from direction discussion.

  The redirect point descriptions must not mix direction and target
  sources in the same paragraph.

A corrected version was partially drafted at the end of PM 4 but the
session ended before the full section (including pipeline staging prose
and closing paragraph) was reintegrated. PM 5 should produce a complete
corrected Redirect Architecture section and integrate it into the blog.

The correct factual statements for the rewrite:
  - FTB provides branch targets and branch type. No direction prediction.
  - Direction chain: uBTB/LP at s1, TAGE at s2, SC at s3.
  - s2_redirect direction trigger: TAGE contradicts s1 conditional prediction.
  - s2_redirect target triggers: FTB target contradicts uBTB prediction;
    RAS return address contradicts uBTB prediction.
  - s3_redirect direction trigger: SC overrides TAGE s2 direction.
  - s3_redirect target: FTB result held from s2. ITTAGE may refine indirect
    target if s2 used raw pre-final ITTAGE result.

### Other Open Items

- The full merged P1/P2 text plus all new bullet points has not been
  integrated into the blog file on disk. PM 5 should produce a complete
  updated BLOG_bpu_1_cluster_arch.md with all changes applied.

- Blog diagram reference: bpu_pipeline_staging.svg needs to be referenced
  in the Markdown source as:
    ![BPU pipeline staging](bpu_pipeline_staging.svg)
  Placement to be confirmed.
  This is no longer open, placment is in Predictor Hierarchy.

- The opening section rewrite (co-design dynamic paragraph) was revised
  during PM 4 using the user's preferred version as base. The user provided
  alternative phrasings for four problem sentences. Final selections were
  not locked before session end. PM 5 should confirm and apply these.

  The four items needing final selection:
  1. Opening sentence alternatives (3 options provided, or cut entirely)
  2. Fragment fix for "With the PA's role segmenting..." (3 options)
  3. "With the PA's help research was done..." (3 options)
  4. "this exposed elements of the co-design flow..." (3 options, user
     preferred Option C or B)

- SVG editors discussion: user asked about open source WYSIWYG SVG editors.
  Summary provided: Inkscape (desktop, most capable), SVG-Edit (browser,
  open source), Method Draw (browser, simplest), GodSVG (pre-beta, code-
  centric). No action item -- informational only.

---

## Current Blog File Status

### Complete and on disk
  BLOG_bpu_1_cluster_arch.md -- draft, multiple open items listed above

### Not yet started
  BLOG_bpu_2_history_ubtb.md -- Parts 4 and 5 (history module + uBTB)
  BLOG_bpu_3_loop_pred.md    -- Parts 6-9 (loop predictor)
  BLOG_bpu_4_limits.md       -- Part 10 (PA limits and failures)

### Carried Forward from PM 3
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

## Deferred Items (Unchanged from PM 3)

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

## Suggested PM 5 Starting Point

1. Confirm and apply the four opening section sentence alternatives for
   the co-design dynamic paragraph.

2. Rewrite the Redirect Architecture section cleanly using the correct
   factual statements listed above. Keep direction and target concerns
   separated throughout. Do not mix them in any single paragraph.

3. Integrate the P1/P2 merged predictor section and all new bullet points
   into the blog file on disk.

4. Add the bpu_pipeline_staging.svg diagram reference at the confirmed
   placement location.

5. Produce a complete final BLOG_bpu_1_cluster_arch.md for user review
   and sign-off.

6. After BPU-1 sign-off, begin BPU-2 (history module plus uBTB,
   Parts 4 and 5). Source materials available from PM 4 conversation
   searches: session handoffs 003 and 004, bp_history interface spec,
   uBTB interface spec, BP-002 and BP-003 experiment files.

