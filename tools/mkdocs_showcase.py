#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# mkdocs_showcase.py -- MkDocs hook (mkdocs.yml hooks:) for the Showcase
# section (B6-1, B6-2, DOC-008)
#
# Changes the frontend demo pages, showcase/fe_demo/*.md, on the
# published site only; the source in examples/fe_demo/docs/ is not
# changed.
#
# Every demo page loses its working header: the first fenced block after
# the # title, when its first non-blank line starts with FILE: (B6-2).
#
# Each scenario page, showcase/fe_demo/fdNN_<name>.md, gets an Open
# waveform link after its title and a footer. The link opens the
# scenario's FST in Surfer's web build with its command file, both
# served from WAVES (published by tools/publish_waves.py). The footer
# gives the same link, the run and view commands, the scenario's program
# (programs/) and Surfer command file (waves/), and a link to the page's
# source on GitHub at the release tag, or main. A file that does not
# exist gets no line.
#
# docs/showcase/fe_demo is a symlink to examples/fe_demo/docs, so the
# demo directory is the parent of the symlink's target.
#
# THE RELEASE (planning/showcase/showcase_release_decisions.md SR-5 to
# SR-8). The CI docs build (.github/workflows/docs.yml) sets
#   SHOWCASE_CI=1         always
#   SHOWCASE_TAG          the latest fe-* tag (SR-4), when there is one
#   SHOWCASE_DEMO_DIR     with SHOWCASE_TAG: the tag's examples/fe_demo,
#                         its docs/, programs/ and waves/ extracted with
#                         git archive into a directory outside the
#                         checkout
# With SHOWCASE_DEMO_DIR set, every showcase/fe_demo/ file is taken from
# its docs/ instead of from the symlink (on_files); nothing is written
# into the checkout. In CI the landing page, showcase/index.md, has the
# text between its RELEASE_BEGIN and RELEASE_END comments replaced by a
# line naming the tag, or saying the pages are unreleased when there is
# no tag. A local build (mkdocs serve) sets none of these: the pages come
# through the symlink and the landing page keeps its own text, which says
# it shows the branch.
#
# THE SHOWN LIST. mkdocs.yml extra: showcase_shown names the scenarios
# the site shows, as fdNN_<name>; every other scenario is hidden. With
# no showcase_shown, every scenario is shown. A hidden scenario's page,
# and each file of docs/ whose name starts with its fdNN_ (a figure such
# as fd09_blocks.svg), is left out of the build: it has no page, no nav
# entry and no search entry. A list item or table row that links it, in
# the site or its source on GitHub, is dropped from every page: the
# landing page's scenario table and the architecture pages' "Frontend
# demo:" items. Any other link to it becomes plain text.
# Nothing in the source is changed or deleted. The list is read from
# the mkdocs.yml of the checkout, main in CI, so a scenario is hidden or
# shown without a new tag; tools/publish_waves.py reads the same list
# and publishes only the shown scenarios' waveforms. A name that is not
# a scenario page stops the build. SHOWCASE_SHOW_ALL=1 shows every
# scenario, for a local preview of the hidden pages; CI never sets it.

import os
import re
from urllib.parse import quote

from mkdocs.structure.files import File, InclusionLevel

WAVES = "https://uarchlabs.github.io/pacino-waves"
SURFER_APP = "https://app.surfer-project.org/"

SHOWCASE = "showcase/fe_demo/"
LANDING = "showcase/index.md"
DEMO_REPO = "examples/fe_demo"
SCEN_RE = re.compile(r"^(fd\d\d_[a-z0-9_]+)\.md$")
RELEASE_RE = re.compile(
    r"(<!-- RELEASE_BEGIN -->\n).*?(\n<!-- RELEASE_END -->)", re.S)
# A Markdown link to a scenario page: text, then the scenario's name.
SCEN_LINK_RE = re.compile(
    r"\[([^\]]*)\]\((?:[^)\s]*/)?(fd\d\d_[a-z0-9_]+)\.md(?:#[^)\s]*)?\)")
NUM_RE = re.compile(r"^(fd\d\d)_")

# The scenarios to show, from on_config: None shows every one.
SHOWN = None
# The hidden scenarios, from on_files.
HIDDEN = set()


def shown_list(config):
    """The showcase_shown names of mkdocs.yml extra, or None when every
    scenario is shown (no list, or SHOWCASE_SHOW_ALL=1)."""
    if os.environ.get("SHOWCASE_SHOW_ALL") == "1":
        return None
    names = (config.get("extra") or {}).get("showcase_shown")
    if names is None:
        return None
    if not isinstance(names, list) or not all(
            isinstance(n, str) and SCEN_RE.match(n + ".md") for n in names):
        raise ValueError("mkdocs.yml extra: showcase_shown must be a list"
                         " of scenario names, fdNN_<name>")
    return set(names)


def hidden_page(uri, shown):
    """True when uri is a scenario page of showcase/fe_demo/ not shown."""
    if shown is None or not uri.startswith(SHOWCASE):
        return False
    m = SCEN_RE.match(uri[len(SHOWCASE):])
    return bool(m) and m.group(1) not in shown


def drop_nav(nav, shown):
    """nav without the entries of hidden scenario pages; a section left
    empty is dropped too."""
    out = []
    for item in nav:
        if isinstance(item, str):
            if not hidden_page(item, shown):
                out.append(item)
            continue
        if not isinstance(item, dict):
            out.append(item)
            continue
        kept = {}
        for title, val in item.items():
            if isinstance(val, list):
                sub = drop_nav(val, shown)
                if sub:
                    kept[title] = sub
            elif not (isinstance(val, str) and hidden_page(val, shown)):
                kept[title] = val
        if kept:
            out.append(kept)
    return out


def on_config(config):
    global SHOWN, HIDDEN
    SHOWN = shown_list(config)
    HIDDEN = set()
    if SHOWN is not None and config.get("nav"):
        config["nav"] = drop_nav(config["nav"], SHOWN)
    return config


def drop_hidden(files):
    """files without the hidden scenarios' pages and fdNN_ files; sets
    HIDDEN. A shown name with no page stops the build."""
    global HIDDEN
    if SHOWN is None:
        HIDDEN = set()
        return files
    scen = {}
    for f in files:
        if f.src_uri.startswith(SHOWCASE):
            m = SCEN_RE.match(f.src_uri[len(SHOWCASE):])
            if m:
                scen[m.group(1)] = NUM_RE.match(m.group(1)).group(1)
    missing = sorted(SHOWN - set(scen))
    if missing:
        raise ValueError("mkdocs.yml extra: showcase_shown names no"
                         " scenario page: " + ", ".join(missing))
    HIDDEN = set(scen) - SHOWN
    shown_nums = {scen[s] for s in SHOWN}
    hidden_nums = {scen[s] for s in HIDDEN} - shown_nums
    for f in list(files):
        if not f.src_uri.startswith(SHOWCASE):
            continue
        rel = f.src_uri[len(SHOWCASE):]
        m = NUM_RE.match(rel)
        if "/" not in rel and m and m.group(1) in hidden_nums:
            files.remove(f)
    return files


def unlink_hidden(markdown):
    """A list item or table row that links a hidden scenario's page (in
    the site or its source on GitHub) is dropped: the landing page's
    scenario table, an architecture page's "Frontend demo:" item. Any
    other link to one becomes plain text."""
    if not HIDDEN:
        return markdown
    lines = []
    for line in markdown.split("\n"):
        hit = any(m.group(2) in HIDDEN for m in SCEN_LINK_RE.finditer(line))
        if hit and line.lstrip().startswith(("|", "- ", "* ")):
            continue
        lines.append(line)
    return SCEN_LINK_RE.sub(
        lambda m: m.group(1) if m.group(2) in HIDDEN else m.group(0),
        "\n".join(lines))


def release():
    """(in CI, tag or None, the tag's demo directory or None), from the
    environment the CI build sets."""
    tag = os.environ.get("SHOWCASE_TAG") or None
    return (os.environ.get("SHOWCASE_CI") == "1", tag,
            os.environ.get("SHOWCASE_DEMO_DIR") or None)


def release_text(ci, tag, repo):
    """The landing page's release line in CI, or None outside CI."""
    if not ci:
        return None
    if tag is None:
        return ("**Unreleased.** No fe-* release tag exists yet, so the"
                " Showcase pages are taken from the main branch.")
    return (f"**Release {tag}.** The Showcase pages are taken from the"
            f" release tag [{tag}]({repo}/tree/{tag}). The hosted waveforms"
            f" are published from the same tag; their manifest.json names"
            f" it.")


def on_files(files, config):
    """In CI with a tag, every showcase/fe_demo/ file from the tag's
    docs/ (SHOWCASE_DEMO_DIR) instead of from the symlink. Either way,
    without the hidden scenarios (drop_hidden)."""
    _, _, demo = release()
    if demo is None:
        return drop_hidden(files)
    docs = os.path.join(demo, "docs")
    if not os.path.isdir(docs):
        raise OSError(f"SHOWCASE_DEMO_DIR has no docs/: {docs}")
    for f in [f for f in files if f.src_uri.startswith(SHOWCASE)]:
        files.remove(f)
    for top, dirs, names in os.walk(docs):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for name in sorted(names):
            if name.startswith("."):
                continue
            path = os.path.join(top, name)
            rel = os.path.relpath(path, docs).replace(os.sep, "/")
            files.append(File.generated(config, SHOWCASE + rel,
                                        abs_src_path=path,
                                        inclusion=InclusionLevel.INCLUDED))
    return drop_hidden(files)


def wave_url(scen):
    """The Surfer web URL that opens scen's FST and applies its .sucl."""
    load = f"{WAVES}/{scen}.fst"
    cmds = f"run_command_file_from_url {WAVES}/{scen}.sucl"
    return (f"{SURFER_APP}?load_url={quote(load, safe='')}"
            f"&startup_commands={quote(cmds, safe='')}")


def wave_link(scen):
    """The Open waveform link and its one-line note, as Markdown.

    Raw HTML so the link opens in a new tab; attr_list is not enabled.
    """
    href = wave_url(scen).replace("&", "&amp;")
    return [
        f'<a href="{href}" target="_blank" rel="noopener">'
        f"<strong>Open waveform</strong></a>",
        "",
        "Runs Surfer in the browser, with nothing to install. The signal"
        " setup takes a few seconds to apply.",
    ]


def drop_header(lines):
    """Drop the first fenced block after the # title if it is the
    FILE: header block."""
    title = next((i for i, l in enumerate(lines) if l.startswith("# ")), None)
    if title is None:
        return lines, None
    start = next((i for i in range(title + 1, len(lines))
                  if lines[i].startswith("```")), None)
    if start is None:
        return lines, title
    end = next((i for i in range(start + 1, len(lines))
                if lines[i].startswith("```")), None)
    if end is None:
        return lines, title
    body = [l for l in lines[start + 1:end] if l.strip()]
    if not body or not body[0].lstrip().startswith("FILE:"):
        return lines, title
    return lines[:start] + lines[end + 1:], title


def on_page_markdown(markdown, page, config, files):
    src = page.file.src_uri
    ci, tag, demo = release()
    repo = config.get("repo_url", "").rstrip("/")
    markdown = unlink_hidden(markdown)
    if src == LANDING:
        text = release_text(ci, tag, repo)
        if text is None:
            return markdown
        new, n = RELEASE_RE.subn(lambda m: m.group(1) + text + m.group(2),
                                 markdown)
        if n != 1:
            raise ValueError(f"{LANDING}: expected one RELEASE_BEGIN/"
                             f"RELEASE_END pair, found {n}")
        return new
    if not src.startswith(SHOWCASE):
        return markdown
    lines, title = drop_header(markdown.split("\n"))

    m = SCEN_RE.match(src[len(SHOWCASE):])
    if not m:
        return "\n".join(lines)
    scen = m.group(1)

    if title is not None:
        lines[title + 1:title + 1] = [""] + wave_link(scen) + [""]
    markdown = "\n".join(lines)

    demo_dir = demo or os.path.dirname(
        os.path.realpath(os.path.join(config["docs_dir"], SHOWCASE)))
    files_md = []
    for sub, ext in (("programs", ".svh"), ("waves", ".sucl")):
        rel = f"{sub}/{scen}{ext}"
        if os.path.isfile(os.path.join(demo_dir, rel)):
            files_md.append(f"`{rel}`")

    src_url = f"{repo}/blob/{tag or 'main'}/{DEMO_REPO}/docs/{scen}.md"

    lines = ["", "---", ""] + wave_link(scen) + [
        "",
        f"**Run it** from `{DEMO_REPO}/`: `make {scen}` runs the scenario;"
        f" `make view S={scen}` opens its waveform in Surfer.",
    ]
    if files_md:
        lines += ["", "**Files:** " + ", ".join(files_md) + "."]
    lines += ["", f"[Source of this page on GitHub]({src_url})", ""]
    return markdown.rstrip("\n") + "\n" + "\n".join(lines)
