<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Blog Article Generation Process — RVA23 Co-Design
```
 FILE:    BLOG_GENERATION_PROCESS.md
 STATUS:  DRAFT
 UPDATED: 2026-07-11
 CONTACT: Jeff Nye
```

This document describes a process for turning a specified range of PA session
chats into a published blog post in the BLOG_[series]_[number]_[short_description].md
series. This is a methodology document that describes the expected format of
a post and the analysis process.

---

## Definitions

IA — Implementation Assistant, nearly always Claude Code.
PA — Planning Assistant, nearly always Claude.ai.
Jeff — the user. Makes all architectural and editorial decisions;
       bridges PA, IA, and the blog generation process.

Design session naming convention: `RVA23 Co-Design Part N`
(unpadded — sessions are named with whatever integer is next,
e.g. Part 0, Part 1, Part 10, Part 33; not zero-padded).

The design sessions are under a single project, 'RISC-V RVA23 Design'.

The output file naming is BLOG_[series]_[number]_[short_description].md
    - series is typically a unit name, such as bpu or decoder
    - number identifies the sequence within that series
    - short_description is a brief identifier of content

BLOG generation session: a Claude.ai session named
    `RVA23 Blog-Gen Part N` (unpadded, matching the design
    session chat-naming convention above — chats are named
    with whatever integer is next, not zero-padded) which
    contains the interactive creation of one blog post. Scoped
    to a single post; producing a post that requires more
    context than one session holds is handled by the handoff
    below, not by cataloging across multiple posts in one
    session.

BLOG generation handoff: a file, `blog_handoff-NNN.md`
    (zero-padded three-digit — this is a separate convention
    from the chat session name above, matching the existing
    `session_handoff-NNN.md` file-naming convention already
    used for design sessions), written at the end of a BLOG
    generation session that has run out of context, allowing
    the next BLOG generation session to resume from a
    documented point on the same post.

---

## Purpose

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

## Process Summary

The user begins a BLOG generation session with the PA, using the
naming scheme above for back-referencing.

The user will:
  - Specify a range of PA session chats, `RVA23 Co-Design Part N`
    to `Part N+M` (or "Part N to Part N+M").
  - Ask the PA to examine that range for sufficient content —
    see Purpose above for what "sufficient" means in practice.
    The end of the range, N+M, may be adjusted to find a proper
    boundary.

The PA will identify the experiment files referenced in that
range. The user then pastes those files at the PA's request, and
the session_handoff-NNN.md files bounding the range, also at the
PA's request.

Confirming the range is a real, closeable arc happens once, in
Step 1 below — this section only covers how the range is
proposed, not how it's validated.

---

## Inputs Required

1. PA session chats in the target range — supplied by the user,
   extended at the PA's request.
2. Experiment files — supplied by the user at the PA's request.
3. session_handoff-NNN.md files — supplied by the user at the
   PA's request.
4. PROJECT_CORE.md — project planning file giving scope and
   terminology.
5. Prior post in the series — for context and continuity.
6. Series name, series number, and short description — usually
   self-evident from the range's subject matter; if not, the PA
   proposes one for the user's approval before drafting.

If any of 1-3 are unavailable for part of the range, that gap
should be stated in the post rather than papered over — gaps in
the record are reported, not silently smoothed.

---

## Step-by-Step Process

### 1. Determine the range and confirm it's a real arc
Identify the target Part range directly from the session chats
and their bounding session_handoff-NNN.md files. A post should
cover a range that closes something — a sub-feature complete, a
class of debt resolved, a component ready for handoff to the
next stage. If the requested range doesn't close anything (e.g.
it's mid-implementation), say so before drafting rather than
forcing an artificial "closing" narrative.

### 2. Build the experiment inventory
List every experiment ID touched in the range, in session order,
with: emitted / run / status (pass, fail, abandoned, split),
and one line on what it did. Pull this from Results Capture
sections in the experiment files and from the session chats
themselves — these are the authoritative record, not any
secondary index. This inventory becomes the raw material for
the Experiment Summary table and the narrative sections.

A source is not authoritative when it disputes its own
reliability. If a handoff or session chat states outright that
its own claims were not verified, were disputed by the user, or
were reverted — as opposed to ordinary self-correction across
sessions, which is normal and not this case — the post reflects
that disputed status rather than upgrading the claim to settled
fact. Report what the source claims and that the claim was
disputed or unverified; do not silently pick one side of the
dispute, and do not treat a later session's clean re-execution
as retroactively confirming what the disputed session claimed.
See BLOG_bpu_10 (Part 35's handoff explicitly stating its own
"successful" claims were not trusted by the user).

### 3. Identify thematic clusters, not a session-by-session log
Group the experiment inventory into 2-4 narrative threads by
what problem they solved, not by which session they ran in. A
post should read as "here's what got solved," with
session/experiment IDs as supporting detail, not as "session 26
did X, session 27 did Y."

### 4. Extract artifacts per cluster
For each thematic cluster, list concretely: files created or
renamed, parameters/structs added or removed, planning docs
written, debt numbers opened and closed. Specific names matter —
the audience is EDA/design engineers who will judge credibility
on this level of detail being present and accurate.

### 5. Extract decisions and their rationale
For any nontrivial engineering call made mid-implementation,
record: what the naive/default approach would have been, why it
was rejected, what was chosen instead, and what it defers or
risks. These are the highest-value paragraphs in the post —
they're the part a skeptical reader can't get from the repo
alone.

### 6. Extract friction and methodology events
Pull anything that cost a session or forced a process change:
stop-and-report events, context/token limit hits, experiment
splits (a/b/c, 1/2), PA context degradation, off-by-one errors
in handoff numbering, abandoned drafts. These feed the "what the
sessions exposed about the methodology" subsection. Report them
neutrally — cost and benefit both.

### 7. Separate PA contribution from IA contribution
Using PROJECT_CORE's dictate-vs-propose framing: what did the PA
produce (planning docs, prompt sequencing, decisions flagged as
needing resolution) versus what did the IA execute (RTL,
testbenches, autonomous error resolution)? Keep these as
distinct paragraphs — collapsing them is the most common way
these posts drift into vague "AI helped with X" language.

### 8. Draft the generalization
One closing paragraph naming the pattern that recurs across the
clusters. This requires looking backward across the series, not
just at the current range, so re-read the prior post's own
generalization before writing this one — avoid repeating the
same claim in different words two posts running.

### 9. Assemble in the template (below)
Includes drafting the Abstract last, after the body sections
exist — it's easier to compress an already-written post
accurately than to predict its shape in advance.

---

## Article Template

Frontmatter: title, author, date, copyright (CC-BY-4.0 header,
matching existing posts), description (see Indexability).

Series navigation block:
  - Lead sentence, italic: "*This is one of a series of
    articles on [series topic].*" Not "This is part N of..."
    — the lead sentence does not number this post; the list
    below it does that implicitly by position and by each
    link's own "Part N:" text.
  - One link per post, each on its own line, separated by
    `<br>` — not `|`. Pipe-separated single-line nav blocks
    wrap unpredictably and are hard to scan; one link per
    line is not.
  - Each link's visible text includes the part number and
    title ("Part 5: TAGE — Architecture and the Decomposition
    Problem"), per the Indexability section's internal-linking
    rule — never generic anchor text.
- The list covers prior posts only. The post being written
    is never included as a link in its own navigation block —
    a post has no reason to link to itself. The list simply
    ends at the most recently published prior post; the new
    post is added to that list only when it is itself cited
    from a later post's navigation block.

**Abstract** (`##`, immediately after the navigation block):
3-5 sentences, plain prose, no subsection structure. States
the problem the range addressed, a very brief description of
what was done, and the outcome, in that order. Written to let
a reader decide in a few seconds whether the full post is
relevant to them — this is a triage function, not a summary
of every section. Some overlap with the Opening section is
expected and is not a defect; the two serve different reader
commitment levels, the same way an abstract and introduction
coexist in a technical paper. The Abstract does not replace
the Opening section.

**Opening section** (unnumbered, 1-2 short paragraphs): what the
prior post left open, what this post closes, and an honest note
if this is a "shorter/thinner" post because the work was
structural rather than new design — don't inflate scope.

**Thematic body sections** (2-4, each with a `##` header naming
the problem solved, not the session number): narrative prose,
specific names/parameters/debt numbers, per PROJECT_CORE's
"good detail" standard — architecturally meaningful, not
implementation trivia.

**Experiment Summary table** (`##`): columns Experiment,
Description, Status, Checks, Runtime, Context. Use
`--` for unavailable fields rather than omitting the column.

If the range has no experiment files at all — a pure planning
range, no Claude Code session run — rename the section
**Session Summary** and use columns Session, Deliverable,
Outcome instead, one row per Part. State explicitly, in prose
above the table, that no experiment files exist for the range
and why (e.g. "every session was Claude.ai planning-document
work; no Claude Code session ran"). Do not force planning
sessions into the Experiment/Checks/Runtime/Context shape —
those columns describe RTL experiments and have no meaningful
value for a document-drafting session. See BLOG_bpu_10 for the
pattern.

**What Comes Next** (`##`): what's open at the close of the
range, feeding the next post's opening.

**Technical Debt Referenced** (`##`, optional — include only
if the post cites specific numbered debt items from
PROJECT_STATUS.md): reproduces the cited rows verbatim from
PROJECT_STATUS.md as of the drafting date, stated explicitly.
If a cited debt's text has drifted since the post's own time
period (number reused, item redefined, resolution superseded),
reconstruct the period-accurate version from the experiment
files' own description of why the debt was opened, and say
plainly that it's a reconstruction, not a verbatim historical
copy, alongside the current text for contrast — see BLOG_bpu_9
for the pattern (TD# 38, Verilator version drift). Every
inline `TD# NN` mention in the post's prose must link to its
row here via an HTML anchor (`<a id="td-NN">` before the row's
first cell, `[TD# NN](#td-NN)` at each mention) rather than
staying as flat text — this lets a reader jump straight to the
full item instead of re-reading the surrounding paragraph for
context. Use a distinct anchor per version when the same debt
number is reproduced more than once for drift comparison (e.g.
`#td-38-part29` vs `#td-38-current`).

**Design Process Notes** (`##`), four fixed subsections:
- `###` What the sessions exposed about the methodology
- `###` What the PA contributed
- `###` What the IA contributed
- `###` The generalization

**References footer**: citation list if external sources were
used in the post, or the explicit "*No references required for
this post.*" line if not.

---

## Indexability

Attributes that affect how these posts are found via web search,
separate from content or style. These are markdown/frontmatter
requirements, not writing-style guidance.

### Frontmatter additions

- `description:` — a 1-2 sentence summary distinct from the post
  body, written as if it is the only text a searcher will see.
  Most publishing pipelines map this directly to the HTML meta
  description shown under the title in search results. State
  what the post covers in concrete terms (component name,
  session range, what was resolved) rather than assuming series
  context the searcher does not have.
- Existing `title`, `author`, `date`, `copyright` fields are
  already sufficient for attribution and dating; no change
  needed there.

### Heading structure

- One H1 per post (the title only). Never reuse H1 inside the
  body.
- H2 for major sections, H3 for subsections, matching the
  existing Article Template. This is already followed; no
  change to current practice.

### Image alt text

- Every diagram requires descriptive alt text stating what the
  diagram shows, not a generic label. Example: "TAGE arbitration
  architecture: PQ/UQ credit-based queues feeding a
  competing-stage mux," not "arbitration diagram." Alt text is
  indexed separately by image search and read as context by
  search engines generally.

### Internal linking

- Series navigation anchor text must name the post ("Part 5:
  TAGE — Architecture and the Decomposition Problem"), not use
  generic anchor text ("here," "previous post"). Cross-links
  between posts are a search ranking signal; descriptive anchor
  text carries more weight than generic anchor text.
- Within a post, every inline `TD# NN` mention links to its row
  in the Technical Debt Referenced section via an in-page anchor
  — see Article Template. Same rationale as cross-post linking:
  a reader (or a search engine's page-structure parsing) gets a
  direct path to the full context instead of flat, unlinked text.

### Terminology consistency

- One canonical term per concept across the entire series (TAGE,
  ITTAGE, SC, consumer_ready, etc.) — this extends the existing
  rule of naming things exactly as they appear in the RTL, and
  applies for the same reason search indexing benefits from
  consistent terms across pages.

### Structured data

- If the publishing pipeline supports JSON-LD, mark each post as
  `TechArticle` or `Article` schema with author and publish date.
  This affects rich-result display (author/date shown directly
  in search results), not ranking. Confirm pipeline support
  before treating this as a requirement.

### Excluded practices

- Keyword density targeting or repetition for search purposes.
  Not a current ranking factor and conflicts with the plain
  engineering prose required elsewhere in this document.
- Meta keywords tag. Ignored by current search engines.

---

## Style

### Guidelines

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

### Interpretive claims vs. opinions

Step 5 (decision rationale) and Step 8 (the generalization) call
for interpretive claims — statements that go beyond reporting
what happened to say what it means. "Do not express subjective
opinions" does not bar these sections; it sets the bar for what
makes a claim admissible. A claim is evidenced, not opinion, when
it is stated as a direct sentence and immediately backed by
specific, named instances the reader can check against the
Experiment Summary or the artifact list. A claim is opinion when
it asserts a judgment without attaching the instances that
support it.

Example: "the most expensive problems were the ones deferred
past their natural resolution point" is evidenced when followed
by named instances a reader can verify independently. "This is
the most methodologically interesting decision in this post" is
opinion — it asserts a ranking with no supporting comparison.

### Quoting source material

The Guidelines above (no intensifiers, no asides, no subjective
opinions) govern the post's own authored prose. They do not
apply to material quoted directly from a source document —
a session chat, a handoff, an experiment file. Source material
is data, not prose the post is writing, and is exempt from the
post's register.

Quote directly, rather than paraphrasing into the post's own
register, only when *how* something was communicated is itself
the informative fact — not merely *what* was communicated. A
handoff document hand-annotated in block capitals disputing its
own AI-authored content is informative as a direct quote in a
way "the user strongly disagreed with the session's account"
is not — the annotation's register is the evidence that the
review relationship broke down, not just a fact to be reported
about it. Ordinary source content (a design decision, a test
result, a debt description) gets paraphrased into the post's
register as normal; quoting is the exception, not the default,
and is not a way to bring charged or informal language into the
post indirectly through quotation marks. When quoting, mark it
clearly as quoted material (quotation marks, and named source)
so a reader does not mistake it for the post's own voice.

### Prior posts predate this style section

BLOG_bpu_1 through BLOG_bpu_8 were written before the Guidelines
above were adopted and are cited elsewhere in this document (the
Article Template and several numbered steps) as structural
models — for section layout, table format, and the shape of the
Design Process Notes. They are not style models. A structural
reference to an existing post elsewhere in this document does
not carry an endorsement of its sentence-level phrasing.

### Target audience

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

