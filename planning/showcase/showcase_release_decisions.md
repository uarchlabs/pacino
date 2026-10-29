<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Showcase Release Decisions
```
 FILE:    showcase_release_decisions.md
 SOURCE:  session-082
 STATUS:  DRAFT
 UPDATED: 2026-10-28
 CONTACT: Jeff Nye
```

Owns the SR-N and SR-UN registries.

How a showcase release is named and published: the frontend release
tags, the one RTL state the Showcase pages and the hosted waveforms
show, and the waveform staleness check. The showcase is
examples/fe_demo/ (planning/testbenches/fe_demo_tb_decisions.md,
planning/showcase/fe_demo_scenarios.md).

---

## 1. Tags

SR-1   A frontend release is an annotated git tag fe-<major>.<minor>.<patch>,
       each field a decimal number with no leading zero (Jeff,
       session-082):
         major  a new showcase scope
         minor  an RTL change that alters documented behavior, with the
                descriptions and their event checks (FDT-10c) brought to
                it
         patch  a change to the descriptions only, with no RTL change
                since the previous tag
       A change that alters neither documented behavior nor the
       descriptions takes no tag.
SR-2   Jeff applies every tag by hand. No script and no task creates,
       moves or deletes a tag.
SR-3   fe-1.0.0 marks the frontend-RTL-complete release. It is applied
       after the descriptions are re-edited (web plan B11) and after
       DOC-009.
SR-4   The latest tag is the fe-* tag with the highest version, compared
       field by field as numbers, not the most recent by date.

---

## 2. One state on the site

SR-5   The Showcase pages and the hosted waveforms show one RTL state,
       the commit of one fe-* tag.
SR-6   The docs build in CI takes the Showcase pages from
       examples/fe_demo/docs/ at the latest tag (SR-4), not from the
       branch. With no fe-* tag in the repository it takes them from
       the branch, and the Showcase landing page says that the pages are
       unreleased.
SR-6a  The CI build extracts the latest tag's examples/fe_demo/docs/,
       programs/ and waves/ with git archive into a directory outside
       the checkout, and tools/mkdocs_showcase.py takes the
       showcase/fe_demo pages from there. Nothing is written into a
       tracked path, and the symlink is unchanged (DOC-008).
SR-7   A local preview (mkdocs serve) shows the branch's pages through
       the docs/showcase/fe_demo symlink, unchanged. The landing page
       says it shows the branch.
SR-8   The Showcase landing page, docs/showcase/index.md, names the tag
       its pages come from.
SR-9   tools/publish_waves.py publishes only a commit at an fe-* tag.
       An explicit override publishes another commit and records the
       tag as untagged. The tag and the commit are recorded in the
       published manifest.json beside pacino_commit, as the keys tag
       (the fe-* tag, or untagged) and tag_commit; pacino_commit is the
       same commit (DOC-008).
SR-9a  A real publish is refused when a tracked file under rtl/ or
       examples/fe_demo/ differs from the commit published, or an
       untracked file that git does not ignore is present there (Jeff,
       session-082). A dry run warns instead.
SR-10  The tag and the commit can be given to publish_waves.py as
       arguments, and a dry run given both makes no git call. A real
       publish always checks with git that the tag is annotated and
       names HEAD, whether or not they are given, and refuses a given
       commit that is not HEAD (Jeff, session-082). Looking them up with
       git is the default when they are not given. A dry run builds and
       checks everything and pushes nothing.

---

## 3. Waveform staleness

SR-11  publish_waves.py computes, for each scenario, a digest of the
       decoded values over time of the signals listed in the scenario's
       .sucl file, read with tools/bin/fst2vcd (FST2VCD). The FST bytes
       are not digested: their header and compression vary between
       builds of the same values.
SR-12  The digests are recorded per scenario in manifest.json. Before a
       publish, the script compares each digest with the one in the
       published manifest.json, read from a file path given to it, and
       reports each scenario as unchanged, changed, new or without a
       published digest. A changed digest warns; it never stops a
       publish. The digests are the key digests, with digest_version;
       a published digest of another version is reported as without a
       published digest (DOC-008).

---

## 4. Open

SR-U1  A GitHub Release per tag with a short changelog. Optional; not
       tasked (Jeff, session-082).

---

## 5. Document History

```
  2026-10-28  session-082. Created (Jeff's rulings; DOC-008).
  2026-10-28  session-082, after DOC-008. SR-6a the mechanism; SR-9
              the manifest keys; SR-9a a dirty tree refuses a real
              publish; SR-10 a real publish always checks the tag with
              git (Jeff); SR-12 the digest version.
```
