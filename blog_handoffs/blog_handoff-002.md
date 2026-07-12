<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Blog Handoff 002
Written by the PA at end of session `RVA23 Blog-Gen Part 1`
(chat session name is unpadded; this handoff file's own NNN
numbering is a separate, zero-padded convention — see
BLOG_GENERATION_PROCESS.md Definitions).
Date: 2026-07-12

This session drafted BLOG_bpu_11_ittage_implementation.md
(Parts 37-42, complete, pending review), assessed Parts 43-48
and proposed a post sequence for that range, and drafted two
posts covering Parts 43-47 which Jeff abandoned. It also
identified and fixed a navigation-block defect affecting
BLOG_bpu_10.

Read this file, then the current draft (below or attached),
before continuing.

---
## Post Identity
- Series / number / short description: bpu / 11 / ittage_implementation
- Target filename: BLOG_bpu_11_ittage_implementation.md
- Source range: Part 37 to Part 42
- Range type: Standard (Experiment Summary table)

Note: BLOG_bpu_12 and BLOG_bpu_13 were drafted this session
covering Parts 43-46 and Part 47 respectively, and were
ABANDONED by Jeff. Both files were deleted, not retained.
The Parts 43-48 range remains unconsumed by any post. See
Suggested Sequence below.

---
## Inputs Status
Supplied this session:
  - session chats: none pasted directly; Parts 37-42 initially
    approximated via conversation_search, then superseded by
    the ho.md package below
  - experiment files: BP-031 through BP-039 (Parts 37-42, first
    ho.md upload); BP-041 through BP-060 plus INFRA-007 (Parts
    43-48+, second ho.md upload)
  - session_handoff files: 038-043 (first upload); 044-049
    (second upload)
  - prior post: BLOG_bpu_10_ittage_planning.md

Still needed / outstanding requests to user:
  - No session_handoff file exists in context for the session
    that ran BP-055 through BP-060 (the ITTAGE round-trip
    capstone and the TAGE mirror sequence). The task files are
    present in ho.md; the narrating handoff is not. This must be
    gathered before any post covering that range is confirmed as
    a real arc per Step 1.

Source reliability flags:
  - The second ho.md package contains two headers both labeled
    "# Session Handoff 046". The package's own file listing and
    the second file's content ("Session-045 was a PA session")
    confirm the first of these is session_handoff-045.md,
    mislabeled. Handoff numbering runs one ahead of the session
    it documents throughout (session_handoff-044 documents
    session-043, etc.).
  - No source in the Parts 37-48 range disputes its own claims
    in the manner of Part 35 (see BLOG_bpu_10). Ordinary
    self-correction across sessions is present and is not this.

---
## Process Progress
Per BLOG_GENERATION_PROCESS.md Step-by-Step Process:

For BLOG_bpu_11 (Parts 37-42) — all steps complete:
  [x] 1. Range confirmed as a real arc
  [x] 2. Experiment inventory built
  [x] 3. Thematic clusters identified
  [x] 4. Artifacts extracted per cluster
  [x] 5. Decisions and rationale extracted
  [x] 6. Friction / methodology events extracted
  [x] 7. PA/IA contribution separated
  [x] 8. Generalization drafted
  [x] 9. Assembled in template (Abstract drafted last)
  [x] 10. Series navigation updated

For the Parts 43-48 range — Step 1 partially complete (see
Suggested Sequence); no drafting to be carried forward, as both
attempts were abandoned.

---
## Suggested Sequence
Proposed post sequence for Parts 43-48, produced this session
from the handoff-044 through handoff-049 package. Session
numbering below is by the session that did the work, not by
handoff number. Not yet confirmed with Jeff; the two posts
drafted against the first two rows were abandoned, so this table
is a proposal only and its boundaries are open to revision.

| Post | Sessions | Experiments | What it closes |
|------|----------|-------------|----------------|
| 12 | 43-46 | ~14 (BP-040, TB-001, TB-002, BP-041, BP-042/a/b, INFRA-007, BP-043/043a, BP-044/044a/044b/044c) | Provider-gating defect class confirmed and closed; manual testbench and assertion infrastructure established; backdoor RAM-seeding adopted as the standard ITTAGE verification method; strategic pivot away from further manual test-writing |
| 13 | 47 | 6 (BP-045, BP-046, BP-047, BP-048, BP-049, BP-049a) | TD#66/#76 port-dimension rework (three-index update-bus form for TAGE and ITTAGE); TD#57 ITTAGE target-write gating; two standing verification rules (ALL TARGETS MUST RUN; governing document required in manifest) |
| 14 | 48 | 9 (BP-050, BP-050a, BP-050b, BP-051, BP-052, BP-053, BP-054, BP-054a) | ITTAGE directed validation complete: EPC, UAON, aging/epoch, allocation, prediction-side each proven by readback; one real RTL defect (missing UAON single-hit guard) |
| 15 | 49 | 6 (BP-055 through BP-060) | ITTAGE round-trip capstone (TD#72); the same directed-test template applied back to TAGE, finding the same missing-single-hit-guard defect class independently in TAGE UAON |

Boundary notes:
  - The original proposal split sessions 43-45 and 46 into
    separate posts. That split was rejected during this session:
    sessions 43-45 build two verification mitigations in
    response to an open question and close nothing, and session
    46 is where that question actually resolves. Splitting there
    produces a post whose own Abstract admits it closes nothing,
    which Step 1 prohibits. Rows 12 and 13 above reflect the
    merged form.
  - Post 15's range cannot be confirmed as a real arc until the
    missing handoff for the BP-055..060 session is supplied.

---
## Working Material Captured So Far
(Reference notes, not final prose.)

Not carried forward. Both abandoned drafts were deleted at
Jeff's direction. The session map in Suggested Sequence above,
and the raw ho.md package, are the material a resuming session
should work from. Re-derive clusters, artifacts, decisions, and
friction events from the task files directly rather than from
this handoff.

### Technical Debt Referenced (carry-forward, applies to any
### post covering Parts 37-48)
  - TD# 43, TD# 44, TD# 45: these three numbers have now drifted
    twice. They were closed in session-037 over TAGE-side
    documentation and audit work, reused in session-040/041 for
    unrelated ITTAGE items, and reassigned again by session-045.
    Any post citing them must state which version it means and
    when. BLOG_bpu_11 handles this by quoting both the Part 37
    (closed) and current (session-043) versions in separate
    anchored tables. A reconciliation pass against
    PROJECT_STATUS.md is warranted before any further post cites
    these numbers by content.
  - TD# 51 is the throughline of the Parts 39-46 material:
    opened by BP-039's inverted using_primary finding, confirmed
    as a defect class by BP-044b/BP-044c, closed with survivors
    folded into TD#57 (target write) and TD#62/#63 (allocation).

---
## Draft State
  - BLOG_bpu_11_ittage_implementation.md: complete, all sections
    present, pending Jeff's review. Attached / in outputs.
  - BLOG_bpu_12, BLOG_bpu_13: abandoned and deleted this
    session. Nothing to resume.

---
## Open Questions / Decisions Pending
  - Series navigation self-link: BLOG_bpu_10 links itself in its
    own navigation block; BLOG_bpu_9 does not. The self-link is
    the defect. BLOG_bpu_11 was corrected this session to omit
    it. BLOG_bpu_10 still needs the correction applied before it
    moves to COMPLETE. The following bullet was supplied to Jeff
    for addition to BLOG_GENERATION_PROCESS.md under Series
    navigation block, and has not yet been confirmed as added:

        - The list covers prior posts only. The post being
          written is never included as a link in its own
          navigation block — a post has no reason to link to
          itself. The list simply ends at the most recently
          published prior post; the new post is added to that
          list only when it is itself cited from a later post's
          navigation block.

  - A single shared navigation block referenced by all posts is
    not achievable in flat Markdown. Jeff confirmed the blog
    repo is separate from the GitHub Pages repo that publishes
    it, and that any Jekyll _includes transclusion would be done
    on the Pages side. No action needed in the blog repo;
    navigation blocks remain literal per post. To prevent drift,
    consider a canonical planning/BLOG_NAV.md that nav blocks
    are copied from verbatim, rather than copied from whichever
    prior post is nearest to hand.
  - Carried from blog_handoff-001, still undecided: whether to
    formalize the DRAFT / REVIEW BEFORE POSTING / COMPLETE
    pipeline into BLOG_GENERATION_PROCESS.md or BLOG_HANDOFF.md.
  - Carried from blog_handoff-001, still undecided: BLOG_bpu_10's
    quoted hand-annotated passage (Part 35) — keep as-is, tone
    down, or handle differently.
  - Title and filename length: flagged by Jeff this session as
    running too long. BLOG_bpu_11's title
    ("ITTAGE -- Table, Controller, Wrapper, and First Integrated
    Testbench") is a candidate for shortening before it moves to
    COMPLETE.

---
## Next Session (003)
1. Review BLOG_bpu_11_ittage_implementation.md; shorten title if
   desired; move to COMPLETE or return for edits.
2. Apply the navigation self-link correction to BLOG_bpu_10.
   Confirm whether the Series navigation bullet above was added
   to BLOG_GENERATION_PROCESS.md.
3. Complete the review of BLOG_bpu_9 and BLOG_bpu_10 carried
   over from blog_handoff-001 (both still REVIEW BEFORE
   POSTING).
4. Re-approach Parts 43-46 (Suggested Sequence row 12). Two
   prior attempts at this range were abandoned. Before drafting,
   establish with Jeff what the target reads like — the failures
   in that range are numerous and the useful content is in how
   each was fixed and what process changed as a result, not in
   the fact that failures occurred. Draft against the task files
   in ho.md directly; they carry the RTL-level detail (signal
   names, gating booleans, fail-before/pass-after values) that
   the posts require and that the handoffs alone do not supply.

