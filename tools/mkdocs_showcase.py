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
#
# THE WORKING SPECIFICATIONS (showcase_release_decisions.md SR-17 to SR-19,
# DOC-013). A doc page whose tools/doc_status.yaml entry has a spec: list is
# rendered, at build time only, as its title, status and covers lines, an
# advisory, and each listed planning document in a collapsed section; its
# placeholder block in docs/ is not changed. The status and covers lines come
# from tools/gen_doc_placeholders.py. The CI build also sets
#   SHOWCASE_SPEC_DIR     with SHOWCASE_TAG: the directory holding the tag's
#                         planning/arch and planning/interfaces, extracted
#                         with the tag's examples/fe_demo
# and the documents are read from there; the lists themselves are the
# checkout's. A local build reads the working tree. The documents' text is
# unchanged. Two things differ from the source so that it reads as written:
# - headings are demoted by two levels and removed from the page's table of
#   contents (on_page_content)
# - a paragraph holding an indented line, which Markdown would join into one
#   run of text, is shown as a fenced block, and a rule directly under text
#   is kept a rule rather than read as a heading underline (keep_indented)

import os
import re
from urllib.parse import quote

import yaml
from gen_doc_placeholders import (TABLE_FILE, covers_line, is_empty_body,
                                  spec_errors, split_page, status_line)
from mkdocs.structure.files import File, InclusionLevel

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

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
# The doc_status.yaml entries with a spec: list, by page, from on_config.
SPECS = {}

FENCE = "```"
HEADING_RE = re.compile(r"(#{1,6})(\s.*)")
RULE_RE = re.compile(r"-{3,}\s*")
COMMENT_RE = re.compile(r"<!--.*-->\s*")
# A list item: its indent, its marker and the space that follows.
ITEM_RE = re.compile(r"( *)([-*+]|\d+[.)])( +)\S")
# Below the page title and the collapsed section's own title.
HEADING_DEMOTE = 2
ADVISORY = (
    "This page shows the planning documents this block was designed and"
    " implemented from, as of {}. They record decisions and their history,"
    " including superseded rulings, and will be replaced by a written"
    " description. Planning documents are licensed under Apache-2.0.")


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


def load_specs():
    """The doc_status.yaml entries with a spec: list, by page. The list is
    the checkout's, main in CI (SR-18). A list of the wrong form stops the
    build; CI does not run gen_doc_placeholders.py."""
    with open(os.path.join(ROOT, TABLE_FILE)) as f:
        table = yaml.safe_load(f) or {}
    specs = {k: e for k, e in table.items() if "spec" in e}
    for key, e in specs.items():
        errors = spec_errors(e["spec"])
        if errors:
            raise ValueError(f"{TABLE_FILE}: {key}: " + "; ".join(errors))
    return specs


def on_config(config):
    global SHOWN, HIDDEN, SPECS
    SHOWN = shown_list(config)
    HIDDEN = set()
    SPECS = load_specs()
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


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


def plain_list(block):
    """True when Markdown renders block as a list and loses nothing but the
    wrap of its items: each indented line is a nested item at four spaces or
    more, or a wrapped line under its item's text. A deeper line is aligned
    by hand, and a nested item at one to three spaces would be flattened."""
    m = ITEM_RE.match(block[0])
    if m is None or m.group(1):
        return False
    text_col = m.end(3)
    for line in block[1:]:
        ind = indent_of(line)
        m = ITEM_RE.match(line)
        if m:
            if 0 < ind < 4:
                return False
            text_col = m.end(3)
        elif ind not in (0, text_col):
            return False
    return True


def preformatted(block):
    """True when Markdown would lose the line breaks and indentation of this
    run of lines, so it is to be shown fenced."""
    if not any(indent_of(line) for line in block):
        return False
    if block[0].lstrip().startswith("|"):
        return False
    # Four or more: already an indented code block, or a list's continuation.
    if all(indent_of(line) >= 4 for line in block):
        return False
    return not plain_list(block)


def escape_wildcards(line):
    """line with the * of a name pattern such as tbl_ri_* escaped, outside
    inline code: two in one paragraph would be read as emphasis and lost."""
    parts = line.split("`")
    parts[::2] = [p.replace("_*", "_\\*") for p in parts[::2]]
    return "`".join(parts)


def keep_indented(lines):
    """lines with each paragraph holding an indented line fenced, whole, so
    its line breaks and indentation stay and its text is shown as written.
    A heading or a rule is not part of a paragraph, and a rule gets blank
    lines so that the line above it is not read as a heading."""
    out, block, fenced = [], [], False

    def flush():
        if block and preformatted(block):
            out.extend(["", FENCE, *block, FENCE, ""])
        else:
            # Four or more spaces may be an indented code block.
            out.extend(escape_wildcards(l) if indent_of(l) < 4 else l
                       for l in block)
        block.clear()

    for line in lines:
        if line.lstrip().startswith(FENCE):
            flush()
            fenced = not fenced
            out.append(line)
        elif fenced:
            out.append(line)
        elif not line.strip():
            flush()
            out.append(line)
        elif HEADING_RE.fullmatch(line):
            flush()
            out.extend([line, ""])
        elif RULE_RE.fullmatch(line):
            flush()
            out.extend(["", line, ""])
        else:
            block.append(line)
    flush()
    return out


def demote_headings(lines):
    """lines with each heading outside a fenced block HEADING_DEMOTE levels
    lower, no lower than level 6."""
    out, fenced = [], False
    for line in lines:
        if line.lstrip().startswith(FENCE):
            fenced = not fenced
        m = None if fenced else HEADING_RE.fullmatch(line)
        if m:
            level = min(6, len(m.group(1)) + HEADING_DEMOTE)
            line = "#" * level + m.group(2)
        out.append(line)
    return out


def spec_source():
    """(the directory holding planning/, the name the advisory gives, the
    ref the GitHub links use) of this build (SR-18)."""
    ci, tag, _ = release()
    spec_dir = os.environ.get("SHOWCASE_SPEC_DIR") or None
    if tag is not None and spec_dir is None:
        raise OSError("SHOWCASE_TAG is set without SHOWCASE_SPEC_DIR: the"
                      " working specifications must come from the tag")
    if tag is not None:
        return spec_dir, tag, tag
    name = "the main branch" if ci else "the working tree"
    return spec_dir or ROOT, name, "main"


def spec_section(path, base, ref, repo):
    """One document as a collapsed section, as Markdown lines."""
    src = os.path.join(base, path)
    if not os.path.isfile(src):
        raise OSError(f"{TABLE_FILE}: spec document {path} is not in {base}")
    with open(src, encoding="utf-8") as f:
        lines = f.read().split("\n")
    # The SPDX comments go directly before the section, unindented. Indented
    # they are read as inline text, and the address in the last one becomes
    # a mail link inside the comment.
    n = 0
    while n < len(lines) and COMMENT_RE.fullmatch(lines[n]):
        n += 1
    spdx, lines = lines[:n], lines[n:]
    body = demote_headings(keep_indented(lines))
    name = os.path.basename(path)
    head = [f"[{path} on GitHub]({repo}/blob/{ref}/{path})", ""]
    return (spdx + ["", f'??? abstract "{name}"', ""]
            + [f"    {l}" if l.strip() else "" for l in head + body] + [""])


def spec_page(markdown, src, entry, repo):
    """The page's title, status and covers lines, the advisory and its
    documents, in place of its placeholder block (SR-17)."""
    parts = split_page(markdown)
    if parts is None or not is_empty_body(parts[1]):
        raise ValueError(f"{src}: has a spec: list and written content")
    base, name, ref = spec_source()
    lines = [
        parts[0].rstrip("\n"), "",
        status_line(entry), "",
        covers_line(entry), "",
        '!!! note "Working specification"', "",
        "    " + ADVISORY.format(name), "",
    ]
    for path in entry["spec"]:
        lines += spec_section(path, base, ref, repo)
    return "\n".join(lines)


def on_page_content(html, page, config, files):
    """A page with a spec: list has no heading of its own under its title
    (spec_page), so every other entry of its table of contents is from a
    document, and is removed."""
    if page.file.src_uri in SPECS:
        for item in page.toc:
            item.children = []
    return html


def on_page_markdown(markdown, page, config, files):
    src = page.file.src_uri
    ci, tag, demo = release()
    repo = config.get("repo_url", "").rstrip("/")
    if src in SPECS:
        markdown = spec_page(markdown, src, SPECS[src], repo)
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
