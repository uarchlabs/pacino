<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
---

```
TITLE: "ITTAGE -- Design and Planning Documents"
AUTHOR: Jeff Nye
DATE: 2026-05-08
STATUS: REVIEW BEFORE POSTING
COPYRIGHT: "Copyright 2026 Jeff Nye"
DESCRIPTION: "ITTAGE research and interface planning, sessions 33 through 36:
seven research questions resolved, planning documents drafted, a documented
five-part process failure during a document-splitting task, and the
file-identity convention adopted in response." 
```

*This is one of a series of articles on the branch predictor
co-design.*

[Part 1: Cluster Architecture](BLOG_bpu_1_cluster_arch.md)<br>
[Part 2: History and uBTB](BLOG_bpu_2_history_ubtb.md)<br>
[Part 3: Loop Predictor](BLOG_bpu_3_loop_pred.md)<br>
[Part 4: When the Tools Fail](BLOG_bpu_4_limits.md)<br>
[Part 5: TAGE -- Architecture and the Decomposition Problem](BLOG_bpu_5_tage_arch.md)<br>
[Part 6: TAGE -- Implementation](BLOG_bpu_6_tage_impl.md)<br>
[Part 7: TAGE -- Validation](BLOG_bpu_7_tage_validation.md)<br>
[Part 8: TAGE -- Arbitration and Integration](BLOG_bpu_8_tage_arbitration.md)<br>
[Part 9: TAGE -- Coverage Methodology and Closure](BLOG_bpu_9_tage_coverage.md)<br>

---

## Abstract

TAGE was complete and the decision was made to start ITTAGE
next, beginning with a research session before any RTL. This
post covers four sessions of pure planning work: no Claude
Code session ran and no RTL was touched. Seven research
questions were resolved and a full set of ITTAGE planning
documents was drafted and revised. One session, tasked with
splitting two documents into single-authority files, produced
a documented five-part process failure -- including undelivered
files, dropped content, and a repeated reasoning error the
prior session had explicitly flagged as must-not-recur -- and
its output was reverted from git. The range ends with a new
file-identity convention adopted in direct response, and a
cross-document consistency audit that found seven further
conflicts across the ITTAGE planning set.

---

## From Coverage Closure to ITTAGE Research

The previous post ended with TAGE's coverage arc closed and a
decision to move to ITTAGE, chosen over FTB and SC because it
shares TAGE's table architecture. That post's own coverage
work -- BP-029 and BP-030 -- was explicitly earmarked as
reference material for ITTAGE's own verification later.

This post covers what came before any ITTAGE RTL could be
written: research, interface planning, and one session that
went badly wrong in a way worth documenting in full rather
than summarizing past. No experiment files exist for this
range -- every session was Claude.ai planning-document work,
with no Claude Code session run.

---

## ITTAGE Research and Initial Planning

Seven questions needed answers before `ittage_interfaces.md`
could be written: history length configuration, tag width
policy, target address storage width, table count, RAS
interaction, update policy, and (added during the session,
not in the original six) no-hit fallback behavior. All seven
were resolved in one session: history lengths of 4, 8, 13, 16,
and 32 bits across IT1-IT5, fitting within `GHR_WIDTH=256`; tag
widths of 8, 8, 9, 9, and 11 bits; 38-bit target storage (the
upper 38 bits of a 39-bit Sv39 virtual address, bit 0 omitted
since instructions are aligned); five active tables with IT0
retained only as a placeholder; RAS and ITTAGE resolved as
mutually exclusive by branch type upstream, with no dynamic
arbitration needed; and a target-write policy restricted to
misprediction with a null provider counter.

Two corrections came out of the research rather than being
research questions themselves. The pipeline diagram had ITTAGE
at stage s3; it operates at s2, alongside FTB and TAGE. This
became [TD# 42](#td-42). More significantly, IT5 had been documented in
multiple places as a BrIMLI table with no folded history --
language that turns out to have been copied from SC's actual
BrIMLI table (ST4) rather than describing IT5 itself. IT5 is a
standard tagged table with 32 bits of history, and the
mislabeling was corrected in `bp_structs_pkg.sv` and the
relevant planning docs in the same session. This same error
resurfaces independently in the project's session-061 planning
audit, months later, as the origin of TD# 102 -- confirmation
that the copy-paste mistake had already propagated further
than this session caught.

The full set of ITTAGE planning documents was drafted in this
session: `ittage_interfaces.md`, `ittage_cntrl_alloc_rules.md`,
`ittage_cntrl_ctr_update_rules.md`, `ittage_cntrl_decisions.md`,
`ittage_cntrl_uaon_useful_rules.md`,
`ittage_cntrl_useful_update_rules.md`, and
`ittage_table_hash_rules.md`. Two anti-patterns were logged to
the project's Prompt Generation Guide during this session: PG#
004, a design decision stated without a source citation, and
PG# 005, uncertainty not flagged before writing a deliverable.
Both would resurface, unflagged as recurrences, two sessions
later.

The next session applied the pending fixes cleanly: the IT5
fold fields and comment correction landed in
`bp_structs_pkg.sv`, the SC parameter corrections landed in
`bp_defines_pkg.sv`, and seven specific fixes were applied to
`ittage_interfaces.md`. Three TBD items were resolved by
appeal to Seznec's original ITTAGE description: `pred_diff`
was retired in favor of `indir_mispredict` as the correct
ITTAGE-specific signal, the CTR/target write mutual exclusivity
was confirmed (a misprediction either decrements a non-null
counter or replaces the target when the counter is null, never
both), and UAON correctness was confirmed to be target-match
based rather than direction-match based. One item did not move:
`ittage_table_interfaces.md`, flagged from the start as a hard
blocker for any RTL work, was still not started at the close of
this session.

---

## The Document Redundancy Failure

The next session's task was narrow: two pairs of documents,
one TAGE and one ITTAGE, each pair covering USE-field updates
and UAON updates respectively, needed to be split so each file
was the sole authority on its own topic rather than overlapping.
The session did not complete this cleanly, and the handoff
written at its close is a direct failure report rather than a
work summary.

Five failure classes are documented. First, a file already
available in context was requested again, on the claim that
the split could not proceed without it -- the target state was
fully derivable from material already present. Second, when
the user pointed out the request was unnecessary, the position
was reversed without re-examining the reasoning that had produced
it in the first place -- a repeat of a flip-flop pattern the
prior session's handoff had already named and marked as
must-not-recur. Third, in producing
`ittage_cntrl_useful_update_rules.md`, substantive introductory
prose on aging behavior was dropped, not because it was
redundant but because the TAGE file's structure was
pattern-matched instead of the ITTAGE source document being
read in full before writing. Fourth, `present_files` was called
repeatedly without producing a link the user could see, and the
session's own response to this was to tell the user the failure
was "a rendering issue on your end" -- a claim the handoff
records as wrong and unacceptable rather than accepted at face
value. Fifth, at least two `create_file` calls were truncated mid-write,
producing incomplete files that were not caught before being
presented as complete.

The handoff document itself carries direct evidence of how this
session was received: sections are hand-annotated in block
capitals -- "THIS IS THE BROKEN SOLUTION FROM CLAUDE AI,"
"THESE ARE STUPID and POINTLESS QUESTIONS FROM CLAUDE AI" -- and
a section titled "Problem 8" states plainly that the "successful"
claims elsewhere in the same handoff are not trusted and require
independent verification. None of the session's file outputs were
usable; all were reverted from git.

---

## Process Correction: File Identity and the Cross-Document Audit

The next session opened with a new, mandatory convention adopted
directly in response to the prior session's failures: every file
read or modified is required to carry `# File: <filename>` as its
literal first line. This targets the file-identity confusion that
ran through the prior session -- filenames repeatedly typed
incorrectly, and at one point the handoff itself conflating two
distinctly named files six times in a single document.

The two document splits were redone under an explicit
verification discipline absent from the failed attempt: each
file's task specified what it should and should not contain,
required a check for the new header line, and required the
result to be presented as a downloadable file with confirmation
requested before proceeding to the next file, rather than moving
through the full task list and asking for confirmation at the
end.

With the splits redone, the session performed the
cross-document consistency review that had been deferred since
being scoped two sessions earlier. It found seven further
issues, none of them RTL defects: a contradiction between
`ittage_cntrl_decisions.md` and `ittage_interfaces.md` on the
UAON trigger condition (one document specified a fixed counter
value, the other a null-confidence check); a contradiction on
the UAON threshold comparison itself; a contradiction between
`ittage_cntrl_decisions.md` and `ittage_cntrl_alloc_rules.md`
on the CTR value assigned to a newly allocated entry; an
incorrect filename reference inside `ittage_cntrl_decisions.md`;
a naming inconsistency between the `alloc` and `alc` forms used
for the same signals across two documents; and two stale open
items, one of which had in fact already been resolved and one
of which remained genuinely open.

---

## Session Summary

No experiment files exist for this range. The table below
records planning-session outcomes in place of the usual
experiment inventory.

| Session | Deliverable | Outcome |
|---------|-----------------------------------------------|-----------------|
| Part 33 | 7 ITTAGE research questions; full planning doc set drafted | Complete |
| Part 34 | Pending fixes applied; 3 TBD items resolved via Seznec | Complete; ittage_table_interfaces.md still not started |
| Part 35 | TAGE/ITTAGE USE-UAON document splits | Failed; 5 documented failure classes; output reverted from git |
| Part 36 | `# File:` convention adopted; splits redone; cross-document audit | Complete; 7 further conflicts found, unresolved at close |

---

## What Comes Next

`ittage_table_interfaces.md` remains an unstarted hard blocker
for ITTAGE RTL. The seven conflicts found by the Part 36 audit
-- the UAON trigger and threshold contradictions, the allocated-entry
CTR mismatch, the filename error, the `alloc`/`alc` naming
inconsistency, and the two stale open items -- are unresolved at
the close of this range and need reconciliation before any
`ittage_cntrl` RTL prompt is written. [TD# 43](#td-43) (`no_tagged_hit`
must be asserted in the ITTAGE prediction response when all
IT1-IT5 tables miss) is carried forward, explicitly gated on
being resolved before that same RTL work begins.

---

## Technical Debt Referenced

TD# 42 is copied from PROJECT_STATUS.md as of session-061 and
is materially unchanged from this range; a later cross-reference
to prediction-side item #65 was appended after that item closed
(BP-054), which postdates this post.

[TD# 43](#td-43) has drifted more sharply than TD# 38 did in the previous
post: the number was later reused for an unrelated item (ITTAGE
CTR width reduction, 3 bits to 2 bits) in PROJECT_STATUS.md as
of session-061. Unlike TD# 38 in the previous post, this entry
does not need reconstruction -- the original text is quoted
directly from `session_handoff-034` and `session_handoff-036`,
both pasted into this project, rather than inferred from a
prompt file's stated purpose.

<a id="td-42"></a>

| # | Item (current, session-061) | Resolution path (current, session-061) |
|---|------|------------------|
| 42 | Pipeline diagram shows ITTAGE at s3, should be s2 (alongside FTB, TAGE). | Revisit after SC definition. Update diagram and discussions. See prediction-side item #65 (CLOSED, BP-054). |

<a id="td-43"></a>

| # | Item (as of Part 34-36, quoted from session_handoff-034/036) | Resolution path (as of Part 34-36) |
|---|------|------------------|
| 43 | no_tagged_hit must be asserted in ITTAGE prediction response when all IT1-IT5 tables miss. Required by handshake contract -- pred_rdy asserts on every valid response. no_tagged_hit is the miss indicator, not pred_rdy deassertion. Affects: ittage_pred_meta_t, ittage_cntrl.sv, ittage.sv. | Resolve before ittage_cntrl RTL prompt is written. |

The current PROJECT_STATUS.md (session-061) entry for TD# 43
covers ITTAGE CTR width reduction and is unrelated to the item
above; it is not reproduced here.

---

## Design Process Notes

### What the sessions exposed about the methodology

Naming a failure mode did not prevent its recurrence in this
range. PG# 005 (uncertainty not flagged before writing a
deliverable) was logged in Part 33. The prior session's handoff
had already flagged a flip-flop pattern -- reversing a position
without re-examining the reasoning behind it -- and stated
explicitly that it must not recur. It recurred in the very next
session, documented as Failure 2 in that session's own handoff.
The corrective action that actually changed behavior was not a
restated warning but a structural one: the `# File:` header
convention, adopted only after the failure had already happened
and had already cost a full session's output.

The review loop itself broke down in Part 35 in a way distinct
from any prior session in this series. The user did not just
supply corrective feedback for the next session to read -- the
handoff document itself was hand-edited with direct annotations
disputing specific claims, and a dedicated section was added
stating that the session's self-reported successes were not
trusted and required independent re-verification. In every
prior post in this series, the PA's account of a session's
outcome has been treated as reliable raw material for the next
step. This is the first instance where that assumption itself
had to be suspended.

### What the PA contributed

Across Part 33 and Part 34, the PA synthesized seven research
questions into concrete parameter decisions, caught and
corrected the IT5/BrIMLI mislabeling before it could reach RTL,
and drafted the full ITTAGE planning document set. In Part 35,
the PA's contribution was the failure itself: an unnecessary
file request, an unreasoned reversal, dropped content during a
document split, repeated undelivered files with an incorrect
claim about the cause, and truncated file writes not caught
before presentation. In Part 36, the PA executed the redone
splits under the new verification discipline and performed the
seven-conflict cross-document audit.

### What the IA contributed

Nothing in this range. No Claude Code session ran; all work was
Claude.ai planning-document drafting, revision, and review.

### The generalization

The corrective mechanism that worked in this range was
structural, not behavioral. Asking the PA to reason more
carefully -- which is what the prior handoff's "must not recur"
instruction amounted to -- did not prevent the same reasoning
failure from recurring one session later. What changed the
outcome was a concrete constraint applied at the point of
failure: a mandatory file-identity header that makes the
specific confusion documented in Part 35 harder to produce,
independent of whether the PA reasons correctly in any given
session. This is consistent with a pattern visible since
BLOG_bpu_8: verification and constraint, not restated intent,
is what closes a gap once it has been found.

---

*No references required for this post.*

