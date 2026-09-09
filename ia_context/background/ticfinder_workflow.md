```
 FILE:    ticfinder_workflow.md
 SOURCE:  session 2026-09-08, BLOG_bpu_14 prose cleanup
 STATUS:  WORKING
 UPDATED: 2026-09-08
 CONTACT: Jeff Nye
```

# Intro

How to run a ticfinder cleanup pass over a blog document, from the
first pass, BLOG_bpu_14, 2026-09-08. Claims below are marked as
tested or as observed-but-unexplained. Do not promote an observation
to a rule without reproducing it.

A copy of this note is carried in the IA session memory as
feedback-ticfinder-workflow. This file is the version in git.

# Mechanics not in the README

Rewrites introduce new findings. Splitting a participial tail
promoted a three-case list into a visible TRICOLON, and two rewritten
abstract sentences tripped EMPHATIC_REFLEXIVE. A falling total hides
this, so compare the finding set between runs, not the count.

Markdown masking blanks inline code while preserving offsets, so the
displayed finding text is often mangled, e.g. "reverted a TAGE epoch
gate to alone" for a line whose source reads `prm_match`. Read the
source line, never the finding text.

Waiver hashing works as the README documents: the id covers the
sentence containing the match, so editing a DIFFERENT sentence does
not stale it. Tested 2026-09-08 by rewording the sentence before a
waived tricolon; the waiver held, 22 waived and 0 stale. Every
rehash seen on the first pass was a case of editing the containing
sentence, which the README already predicts.

One finding (7d0225) did appear between two runs without its own
sentence being edited. The cause was not established and a later
attempt to reproduce it was inconclusive. Treat it as unexplained,
not as a rule.

# Why it matters

The waiver file is the record that a document was reviewed. Waivers
written per-round go stale as later rounds reword the sentences they
were written against, and a clean count sitting on stale entries is a
false green. That is the same class of error as a carried-forward
test count, which is the subject of the post this workflow was built
on.

# How to run a pass

- Work one construction at a time, highest count first.
- Re-run after each batch and compare the FINDING SET, not the total.
- Waive nothing until every round is done. Then generate the id list
  from one clean run and waive in a single batch.
- Triage on the tool's own test. A construction stays if it is
  load-bearing: real enumerations, real choices where the rejected
  option was on the table, precise technical terms. Recast it if it
  is cadence.
- Expect ALTERNATIVE_FRAMING to be mostly legitimate in technical
  prose. Six of eight were on the first pass.
- Wrap reused boilerplate such as the author bio in
  <!-- ticfinder_off --> so it leaves the per-1000-word denominator.
- When the source file is renamed or moved, edit the source field in
  the waiver JSON or every run prints a mismatch warning.
- Never let a prose pass move a number, task id or filename. Read
  each rewrite back against the source record.

# Result of the first pass

BLOG_bpu_14_directed_validation.md went from 45 findings at 8.8 per
1k words to 0 unreviewed: 29 rewrites and 22 waivers.
PARTICIPIAL_TAIL and EMPHATIC_REFLEXIVE went to zero outright rather
than being waived.
