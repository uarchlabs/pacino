<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Showcase Release Decisions
```
 FILE:    showcase_release_decisions.md
 SOURCE:  session-082, session-083
 STATUS:  DRAFT
 UPDATED: 2026-11-04
 CONTACT: Jeff Nye
```

Owns the SR-N and SR-UN registries.

How a showcase release is named and published: the frontend release
tags, the one RTL state the Showcase pages and the hosted waveforms
show, and the waveform staleness check. The showcase is
examples/fe_demo/ (planning/testbenches/fe_demo_tb_decisions.md,
planning/showcase/fe_demo_scenarios.md).

Which scenarios are shown on the site and published is section 4, the
shown list. The planning documents shown on unwritten doc pages are
section 5, the working specifications.

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
       tracked path, and the symlink is unchanged (DOC-008). The same
       extraction takes the tag's planning/arch/ and
       planning/interfaces/ for the working specifications (SR-18).
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
       session-082). A dry run warns instead. The check reads git status
       --porcelain=v1 -z --no-renames --untracked-files=all and names
       each file it refuses on; a change outside rtl/ and
       examples/fe_demo/ warns (DOC-010).
SR-10  The tag and the commit can be given to publish_waves.py as
       arguments, and a dry run given both makes no git call. A real
       publish always checks with git that the tag is annotated and
       names HEAD, whether or not they are given, and refuses a given
       commit that is not HEAD, under --tag or --untagged (Jeff,
       session-082; DOC-010). Looking them up with
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

## 4. The shown list

SR-13  The site shows, and tools/publish_waves.py publishes, only the
       scenarios named in the list extra: showcase_shown of the
       repository's mkdocs.yml, each as fdNN_<name>; the rest are
       hidden until they are reviewed. With no list, every scenario is
       shown (Jeff, session-082, recorded session-083).
SR-14  The list is read from the mkdocs.yml of main, also when the
       Showcase pages come from a tag (SR-6), so a scenario is shown or
       hidden without a new tag. This is the one exception to SR-5:
       the tag sets what the pages and waveforms show, and main's list
       sets which of them appear.
SR-15  A hidden scenario's page is left out of the site build, with its
       nav entry and its search entry, and so is each file of
       examples/fe_demo/docs/ named for its number, fdNN_*, unless a
       shown scenario has that number. A list item or table row that
       links a hidden page is dropped from every page: the landing
       page's scenario table and the architecture pages' "Frontend
       demo:" items. Any other link to it becomes plain text. Nothing
       under examples/fe_demo/ is changed. tools/mkdocs_showcase.py,
       THE SHOWN LIST.
SR-16  tools/publish_waves.py builds every scenario and digests,
       reports and publishes only the shown ones; manifest.json lists
       only them (SR-9, SR-12). A name in the list that is not a
       scenario, or a list that is not a list of names, stops both the
       build and the publish. SHOWCASE_SHOW_ALL=1 shows every scenario
       in a local build, for review; CI never sets it.

---

## 5. Working specifications

SR-17  A doc page whose tools/doc_status.yaml entry has a spec: list
       shows those planning documents, from planning/arch/ and
       planning/interfaces/, in the list's order, in place of its
       "Not written yet" placeholder (web plan B4), under an advisory
       naming the release they come from. The page keeps its title, and
       its status line reads "<the rtl field's words>, interim
       documentation", for example "RTL complete, interim
       documentation"; it has no "This page will cover" line (Jeff,
       session-083, before DOC-014). The documents are
       shown as they are, header, status line and history included;
       nothing under planning/ or docs/ is changed. A page without a
       spec: list is unchanged (Jeff, session-083). A document that
       covers a unit is listed on every page of that unit, its
       overview and each sub-page it covers (Jeff, session-083, after
       DOC-013). A page with written content and a spec: list, an
       empty spec: list, or a path listed twice stops the build
       (DOC-013).
SR-18  In CI the documents are the latest tag's (SR-4), extracted with
       the Showcase pages (SR-6a); the advisory reads, in full, "This
       page shows the planning documents and specifications for RTL tag
       <tag>." (Jeff, session-083, before DOC-014), and each
       document links to its file on GitHub at the tag. A local build
       (mkdocs serve) reads the working tree, the advisory names the
       working tree in place of the tag, and
       the links are to main. The spec: lists are read from the
       checkout's tools/doc_status.yaml, main in CI, as the shown list
       is (SR-14). The workflow passes the tag's extracted planning/
       to the hook as SHOWCASE_SPEC_DIR (DOC-013). A listed document
       that is not in the tag is shown as a one-line note naming it and
       the tag, in place of its section, and the build warns; it does
       not stop the build (Jeff, session-083, after DOC-013; DOC-013
       built a stop, to be changed in part 2).
SR-19  The documents keep their license, Apache-2.0, and their SPDX
       header. The advisory does not state the license (Jeff,
       session-083, before DOC-014; it did). The site footer's CC BY
       4.0 line is not changed for these pages, for the time being
       (Jeff, session-083).

---

## 6. Open

SR-U1  A GitHub Release per tag with a short changelog. Optional; not
       tasked (Jeff, session-082).

---

## 7. Document History

```
  2026-10-28  session-082. Created (Jeff's rulings; DOC-008).
  2026-10-28  session-082, after DOC-008. SR-6a the mechanism; SR-9
              the manifest keys; SR-9a a dirty tree refuses a real
              publish; SR-10 a real publish always checks the tag with
              git (Jeff); SR-12 the digest version.
  2026-10-29  session-082, after DOC-010. SR-9a the status form and
              the outside-change warning; SR-10 --untagged.
  2026-11-01  session-083. Section 4, the shown list, SR-13 to SR-16,
              from Jeff's change to mkdocs.yml, mkdocs_showcase.py and
              publish_waves.py; it replaces the paragraph under the
              registry line. Open and History renumbered 5 and 6.
  2026-11-04  session-083. Section 5, the working specifications,
              SR-17 to SR-19 (Jeff's spec pages prompt); SR-6a the tag's
              planning/arch/ and planning/interfaces/. Open and History
              renumbered 6 and 7.
  2026-11-04  session-083, after DOC-013 (Jeff). SR-17 a unit's
              document on every page of the unit, and the build stops
              DOC-013 added; SR-18 SHOWCASE_SPEC_DIR, and a document not
              in the tag shown as a note with a warning.
  2026-11-05  session-083, before DOC-014 (Jeff). SR-17 the status line
              "interim documentation" and no covers line; SR-18 the
              advisory's text; SR-19 the advisory no longer states the
              license.
```
