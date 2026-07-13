<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Blog Article Generation Process — RVA23 Co-Design
```
 FILE:    BLOG_GENERATION_PROCESS.md
 STATUS:  DRAFT
 UPDATED: 2026-07-12
 CONTACT: Jeff Nye
```

This is a methodology document for generation of a blog style 
description of a portion of the RISC-V RVA23 Design developement
of the Pacino processor.

This document describes a process for turning a specified range of Claude AI
chat sessions into a published blog post, expected format and other guidelines.

---

# Files

There are a number of files referenced and a number of naming conventions.


1. Blog output file name format

    BLOG_[series]_[number]_[short_description].md 
    e.g. BLOG_bpu_10_ittage_planning.md

1. PA session handoff names

    'sessions' refer to interactive Claude AI chat sessions. Also known
    as PA sessions (PA=Planning Assistant=Claude AI).

    These sessions are captured in PA session handoff formatted documents.

    These are named session_handoff-NNN.md, N is an integer.

    These files contain a summary of the previous session tasks, completions
    findings and task files used.

1. PA sessions

    The PA session handoff files are derived during the PA sessions.
    These sessions are organized under the project RISC-V RVA23 Design
    and the sessions are number RVA23 Co-Design Part N.

1. BLOG session handoff names

    There is also a blog generation handoff file format, naming is
    blog_handoff-NNN.md.

    These sessions are also Claude AI but focus on generation, editing
    organizing blog articles.

1. BLOG sessions

    Blog sessions with the PA are also under the RISC-V RVA23 Design project
    and have a naming format: RVA23 Blog-Gen Part N.

1. Task or Experiment Files

    Claude.code (aka Implementation Assistant=IA) is used for 
    implementation of the design. The PA setups up the task and emits
    a formated task file. These are used as prompts for IA.

    The numbering format for this files is <unit>-NNN.md.
    e.g. BP-001.md


# Blog file format

The blog file output is somewhat free form and dictated by the tasks and
results covered in the blog. 

There are required sections however to support automation and general best
practices.

    - License Header
    - File meta data
    - Navigation section markers
    - Abstract
    - Body of the article
        - this is free form
    - Experiment Summary
    - Technical debt referenced
    - Literature and external documentation references
    - Attribution

## License Header

The code fences are not part of the text to insert in the blog, they are for
this document only. This is top of the file.

```
<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
```

## File meta data

Code fences ARE part of this text section. 

```
TITLE:     [title string in quotes]
FILE:      [the blog file name]
AUTHOR:    Jeff Nye
DATE:      [todays date YYYY-MM-DD]
STATUS:    REVIEW BEFORE POSTING
COPYRIGHT: "Copyright 2026 Jeff Nye"
```

## Navigation section markers

This contains boiler plate markers for a navigation section. This syntax
is strict, it is processed by scripts

The code fences are not part of the insert.

```
<!--
---

::SERIES DESCRIPTION::
::BEGIN LINKS::
::END LINKS::
-->
```

## Abstract

The abstract serves the same purpose here as it does in research literature and
other technical papers.  It is a concise stand-alone summary of the entire blog
with goal of 500 words or less, perferrably 300 or less.

The purpose of the abstract is to give the reader enough information to
determine if the topics covered are of interest. 

The abstract should contain a description or background of the problem,
describe methods used, report results and key findings. Provide a short
conclusion.

The abstract is stand alone. Only under the rarest cases should it back
reference previous blogs.

There should be no concern in subsequent sections in duplicating some of
the  abstract. This duplication is typical.

## Body of the article

This is covered in the next section Article Body Guide

## Experiment Summary

This is a table that captures statistics from the task file/experiment
runs. This is not always relevant.

Headers are:
```
| Experiment | Description | Status | Checks | Runtime | Context |
|------------|-------------|--------|--------|---------|---------|
```

Example
| Experiment | Description | Status | Checks | Runtime | Context |
|------------|-------------|--------|--------|---------|---------|
| INFRA-001  | Directory   | PASS   | 20/20  | 10m.0s  | 50%     |
| INFRA-002  | Path fixes  | --     | --     | --      | --      |
|            | manual      |        |        |         |         |

## Technical debt referenced

Technical debt is referenced in the artical as TD# N. This is not a link to the
technical debt table in the blog. This is a recently changed rule.

Headers are:
```
| # | Item     | Resolution path    |
|---|----------|--------------------|
```

The text for the Technical debt table entry is copied from PROJECT_STATUS.md
or in CLOSED_TECH_DEBT.md.

This section is not always relevant for a given blog.

## Literature and external documentation references

References to external documents, in particular those in the research 
literature are indicated with the conventional [N]. This marker is not
a link to the reference section.

The reference section is labeled # References. It has a format similar to
this exmaple.

```
---

## References

[1] riscv-opcodes, https://github.com/riscv/riscv-opcodes, accessed 2026.05.01

[2] Wang, Kaifan, et al. "Lorem ipsum dolor sit amet" Research and Development 60.3 (2023): 476-493.

```

The code fences are not part of the format.

## Attribution

This is boiler plate that appears at the end of each blog.

```
---
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
```

The code fences are not part of the format.

---

# Article Body Guide


The article section has a few loose guidelines. It should start with
a introduction that includes very brief background of the problem or
topic.

The article generation process will include pasting context from 
session and experiment files.

The article should then provide a narrative of the process and progress 
represented in the context supplied. In particular highlighting findings.
The failures or difficulties encountered should not be hidden, but the
focus is what changes were made to the flow or understandings of the 
problems as a result of these difficulties, methods used to over come the
problems and a measure of the effectiveness of these new methods.

If there is a list of task files it is good information to provide a
discussion of the focus of that task file, its results, its problems, etc.


If there are future steps that emerge from the sessions that should be
discussed in a similarly named section.

There should be a Design Process Notes section with a decription of what
the user, the IA and the PA each contributed. In particular if the IA or
PA provided insight that was not explicit in the prompts, this is a useful
data point. If there are generalizations or lessons learned in the tasks this
final section should discuss this.

an assessment of the roles of each, user, IA, PA 

## Article Purpose

It is helpful to understand the purposes of these articles and the intended
audience when determining what to document.

The intended audience includes AI engineers, those skilled in the art of
micro-processor design, those with interest in learning out-of-order
concepts and those with skilled interest in design automation, in particular
automation and methods that utilize LLMs. 

There is more than one purpose for an article, one is to provide dialog on the 
effectiveness of the dual agent design flow, another is to document or 
discuss the Pacino design choices, and another is describe the results.

Each post in the series covers a contiguous block of PA sessions
and answers three questions:

1. What happened in these sessions (narrative of the work)
2. What artifacts were created (files, structs, decisions, debt
   opened/closed)
3. What the flow revealed — where the PA/IA/Jeff split worked,
   where it cost time, what would be done differently

The process below is the procedure for producing that from a session range.

  - The output format is defined (see Article Template) but not rigid.
  - The input session count is not fixed; it is set by where a
    coherent narrative arc closes, and adjusted against the
    Indexability section's length considerations. As a rough
    starting reference, prior posts in this series have each
    covered 2-8 experiments — use that as a sanity check when
    judging whether a candidate range is too thin or too broad,
    not as a hard rule.
  - The PA is consulted to determine the range of sessions
    necessary for a coherent and sizable article.

---

# Process Summary

The user begins a BLOG generation session with the PA.

The user will:
  - Specify a range of PA session chats, `RVA23 Co-Design Part N`
    to `Part N+M` (or "Part N to Part N+M").
  - Ask the PA to examine that range for sufficient content —
    see Purpose above for what "sufficient" means in practice.
    The end of the range, N+M, may be adjusted to find a proper
    boundary.
  - Agree with the PA on a focus, topic or angle for the article 
    including a working title.

The PA will:
  - Will identify the experiment files referenced in that
    range. The user then pastes those files at the PA's request, and
    the session_handoff-NNN.md files bounding the range, also at the
    PA's request.

Together the user and PA will decide if a particular focus, topic or
    angle for the article is the best fit for the information.

---

## Available context

There is a large amount of context available. The session handoffs
and experiement files will consume a larget amount of the available
context. But additional files are available. This is not a full list.

- PA session chats in the target range — supplied by the user,
  extended at the PA's request.
- Experiment files — supplied by the user at the PA's request.
- session_handoff-NNN.md files — supplied by the user at the PA's request.
- PROJECT_STATUS.md — project planning file tech debit list and current
  design status
- CLOSED_TECH_DEBT.md - previously closed TD migrated to reduce PROJECT_STATUS
  size.
- PROJECT_CORE.md — project planning file giving scope and terminology.
- Prior post in the series — for context and continuity.
- Series name, series number, and short description — usually
  self-evident from the range's subject matter; if not, the PA
  proposes one for the user's approval before drafting.

---

## Step-by-Step Process

### 1. Determine the range and confirm it's a real arc

Identify the target Part range directly from the session chats and their
bounding session_handoff-NNN.md files. A post should cover a range that closes
something — a sub-feature complete, a class of debt resolved, a component ready
for handoff to the next stage. If the requested range doesn't close anything
(e.g.  it's mid-implementation), say so before drafting rather than forcing an
artificial "closing" narrative.

### 2. Build the experiment inventory

List every experiment ID touched in the range, in session order, with: emitted
/ run / status (pass, fail, abandoned, split), and one line on what it did.
Pull this from Results Capture sections in the experiment files and from the
session chats themselves — these are the authoritative record, not any
secondary index. This inventory becomes the raw material for the Experiment
Summary table and the narrative sections.

If a handoff or session chat states outright that its own claims were not
verified, were disputed by the user, or were reverted the article should
reflect that disputed status.
The PA should report what the source claims and that the claim was 
disputed or unverifie

### 3. Identify thematic clusters

Group the experiment inventory into narrative threads by what problem they
solved, not by which session they ran in. A post should read as "here's what
got solved," with session/experiment IDs as supporting detail, not as "session
26 did X, session 27 did Y."

### 4. Extract artifacts per cluster

For each thematic cluster, list concretely: files created or renamed,
parameters/structs added or removed, planning docs written, debt numbers opened
and closed. Specific names matter — the audience is EDA/design engineers who
will judge credibility on this level of detail being present and accurate.

### 5. Extract decisions and their rationale

For any nontrivial engineering call made mid-implementation, record: what the
naive/default approach would have been, why it was rejected, what was chosen
instead, and what it defers or risks. These are the highest-value paragraphs in
the post — they're the part a skeptical reader can't get from the repo alone.

### 6. Extract friction and methodology events

Pull anything that cost a session or forced a process change: stop-and-report
events, context/token limit hits, experiment splits (a/b/c, 1/2), PA context
degradation, off-by-one errors in handoff numbering, abandoned drafts. These
feed the "what the sessions exposed about the methodology" subsection. Report
them neutrally — cost and benefit both.

### 7. Separate PA contribution from IA contribution

Using PROJECT_CORE's dictate-vs-propose framing: what did the PA produce
(planning docs, prompt sequencing, decisions flagged as needing resolution)
versus what did the IA execute (RTL, testbenches, autonomous error resolution)?
Keep these as distinct paragraphs — collapsing them is the most common way
these posts drift into vague "AI helped with X" language.

### 8. Draft the generalization

Provide a summary or generalization of any impacts or results with the 
IA/PA/User methodology.

### 9. Assemble in the template (below)

Includes drafting the Abstract last, after the body sections exist — it's
easier to compress an already-written post accurately than to predict its shape
in advance.

---

# Indexability

Attributes that affect how these posts are found via web search,
separate from content or style. These are markdown/frontmatter
requirements, not writing-style guidance.

## Indexability section's length considerations

The desired length is 2500 words or greater. Maximum 5000 words.
These are guideline, if exceeded consult user.


## File metadata fields

The metadata block is a fenced code block at the top of the file (see File meta
data, above). That is the only metadata mechanism; do not add YAML frontmatter,
and do not add fields to the metadata block.

The block is closed: TITLE, FILE, AUTHOR, DATE, STATUS, COPYRIGHT.  The
publishing pipeline errors on unrecognized fields (DESCRIPTION was attempted
and rejected). TITLE, AUTHOR, DATE, and COPYRIGHT carry attribution and dating;
FILE is for local file management.

## Heading structure

- One H1 per post (the title only). Never reuse H1 inside the
  body.
- H2 for major sections, H3 for subsections, matching the
  existing Article Template. This is already followed; no
  change to current practice.

## Image alt text

- Every diagram requires descriptive alt text stating what the
  diagram shows, not a generic label. Example: "TAGE arbitration
  architecture: PQ/UQ credit-based queues feeding a
  competing-stage mux," not "arbitration diagram." Alt text is
  indexed separately by image search and read as context by
  search engines generally.

## Internal linking

- Series navigation anchor text must name the post ("Part 5:
  TAGE — Architecture and the Decomposition Problem"), not use
  generic anchor text ("here," "previous post"). Cross-links
  between posts are a search ranking signal; descriptive anchor
  text carries more weight than generic anchor text.

## Terminology consistency

- One canonical term per concept across the entire series (TAGE,
  ITTAGE, SC, consumer_ready, etc.) — this extends the existing
  rule of naming things exactly as they appear in the RTL, and
  applies for the same reason search indexing benefits from
  consistent terms across pages.

## Structured data

- If the publishing pipeline supports JSON-LD, mark each post as
  `TechArticle` or `Article` schema with author and publish date.
  This affects rich-result display (author/date shown directly
  in search results), not ranking. Confirm pipeline support
  before treating this as a requirement.

## Excluded practices

- Keyword density targeting or repetition for search purposes.
  Not a current ranking factor and conflicts with the plain
  engineering prose required elsewhere in this document.
- Meta keywords tag. Ignored by current search engines.

---

# Style

## Guidelines

- Prose, not bullet-heavy — the experiment summary table is the
  one place for tabular density; body sections are narrative.
- Name things exactly as they appear in the RTL/planning docs —
  no paraphrasing identifiers.
- Report failures, deferrals, and open risk plainly, in a direct
  sentence, not a subordinate clause.
- No marketing language about AI capability. The audience is
  explicitly skeptical and credibility comes from precision.
- Keep session/Part numbers as supporting citations inside prose
  ("BP-022 renamed...") rather than as section headers.
- Do not use intensifiers.
- Do not use asides.
- Do not use non-standard or invented jargon or slang.
- Do not use metaphors.
- Do not express subjective opinions.

### Quoting source material

The Guidelines above (no intensifiers, no asides, no subjective opinions)
govern the post's own authored prose. They do not apply to material quoted
directly from a source document — a session chat, a handoff, an experiment
file. Source material is data, not prose the post is writing, and is exempt
from the post's register.

Quote directly, rather than paraphrasing into the post's own register, only
when *how* something was communicated is itself the informative fact — not
merely *what* was communicated. A handoff document hand-annotated in block
capitals disputing its own AI-authored content is informative as a direct quote
in a way "the user strongly disagreed with the session's account" is not — the
annotation's register is the evidence that the review relationship broke down,
not just a fact to be reported about it. Ordinary source content (a design
decision, a test result, a debt description) gets paraphrased into the post's
register as normal; quoting is the exception, not the default, and is not a way
to bring charged or informal language into the post indirectly through
quotation marks. When quoting, mark it clearly as quoted material (quotation
marks, and named source) so a reader does not mistake it for the post's own
voice.

### Target audience

Stated previously but repeated for local reference:  

Engineers skilled in the art of hardware and software design,
specifically microprocessors, specifically RISC-V microprocessors.

### Examples

Jargon and aside:
- Avoid: "Flush behavior is a hole, not a risk."
- Use: "Flush behavior is unspecified."

Unnecessary aside:
- Avoid: "Yes — but it's a rewrite, not an extraction."
- Use: "Yes — but it's a rewrite."

Metaphor with no actionable content:
- Avoid: "The document is three documents wearing one trenchcoat."
- Use: state what the three things are and why they are combined
  in one file.

Unsupported subjective opinion:
- Avoid: "This is the largest single item in this proposal."
- Use: state the size and the comparison basis, e.g. "This item is
  40% of the total line count; the next largest is 12%."

Metaphor outside the engineering register:
- Avoid: "A theory of operation has to tell one story."
- Use: state the actual requirement, e.g. "A theory of operation
  must describe one consistent execution model; conflicting
  descriptions of the same signal in different sections are
  defects."

### Excluded phrases

These phrases and their variants are never to be used. The list
is maintained manually — added to as specific instances are
identified during review, not inferred or anticipated in advance
of being flagged:

- code smell
- bites harder
- papered over
- trench coat

