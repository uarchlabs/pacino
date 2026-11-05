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
# rendered, at build time only, as its title, a status line, an advisory, and
# each listed planning document in a collapsed section; its placeholder block
# in docs/ is not changed. The CI build also sets
#   SHOWCASE_SPEC_DIR     with SHOWCASE_TAG: the directory holding the tag's
#                         planning/arch and planning/interfaces, extracted
#                         with the tag's examples/fe_demo
# and the documents are read from there; the lists themselves are the
# checkout's. A listed document that is not in the tag is a one-line note in
# place of its section, with a build warning (SR-18); the build goes on, as a
# list on main may name a document newer than the tag. A local build reads the
# working tree, where a listed path that does not exist is an error in the
# table and stops the build. The documents' text is unchanged. Two things
# differ from the source so that it reads as written:
# - headings are demoted by two levels and removed from the page's table of
#   contents (on_page_content)
# - a paragraph holding an indented line, which Markdown would join into one
#   run of text, is shown as a fenced block, and a rule directly under text
#   is kept a rule rather than read as a heading underline (keep_indented)
#
# THE UNIT PAGES (SR-17a, DOC-015). A frontend unit and the MMU are one page
# each, docs/<unit>/index.md, with a heading per block; the table has an
# entry per heading, keyed <page>#<heading text>. Each listed heading whose
# text is only its placeholder block is rendered, at build time, as its
# status line, its covers line as a sentence and its related links (the see:
# list, as the placeholder words them). The Overview heading then shows the
# advisory and each document named by any heading of the page once, in its
# own collapsed section: the Overview's own documents first, then each
# heading's in page order. Every other heading names its documents in a
# Specification line, each linked to its section in the Overview; a link
# to a section opens it. A heading with no document keeps the placeholder's
# status form and has no Specification line. A heading with written content
# and a spec: list stops the build; one without a list is left as written.
# The page's table of contents lists the page's own headings only.

import os
import re
from urllib.parse import quote

import yaml
from gen_doc_placeholders import (RTL_WORDS, TABLE_FILE, is_empty_body,
                                  see_line, spec_errors, split_key, split_page,
                                  split_sections, status_line)
from mkdocs.plugins import get_plugin_logger
from mkdocs.structure.files import File, InclusionLevel

log = get_plugin_logger("mkdocs_showcase")

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
# The unit pages' heading entries, {page: {heading text: entry}}, from
# on_config (SR-17a).
UNITS = {}
# The heading texts of each unit page, from on_page_markdown, for its table
# of contents.
UNIT_HEADINGS = {}
# The heading on a unit page that shows the documents.
OVERVIEW = "Overview"
# The Specification line of a heading on a unit page.
SPEC_LINE = "Specification: {} (in the Overview above)"

FENCE = "```"
HEADING_RE = re.compile(r"(#{1,6})(\s.*)")
RULE_RE = re.compile(r"-{3,}\s*")
COMMENT_RE = re.compile(r"<!--.*-->\s*")
# A list item: its indent, its marker and the space that follows.
ITEM_RE = re.compile(r"( *)([-*+]|\d+[.)])( +)\S")
# A name in angle brackets, which Markdown would pass through as an HTML tag.
NAME_TAG_RE = re.compile(r"<(/?[A-Za-z][\w-]*)>")
# Below the page title and the collapsed section's own title.
HEADING_DEMOTE = 2
# SR-18 fixes this text; the argument is what spec_source names.
ADVISORY = "This page shows the planning documents and specifications for {}."
# The status line of a page with a spec: list (SR-17).
SPEC_STATUS = "**Status:** {}, interim documentation"


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


def read_table():
    with open(os.path.join(ROOT, TABLE_FILE)) as f:
        return yaml.safe_load(f) or {}


def load_specs(table=None):
    """The doc_status.yaml page entries with a spec: list, by page. The list
    is the checkout's, main in CI (SR-18). A list of the wrong form stops the
    build; CI does not run gen_doc_placeholders.py."""
    table = read_table() if table is None else table
    for key, e in table.items():
        if "spec" in e:
            errors = spec_errors(e["spec"])
            if errors:
                raise ValueError(f"{TABLE_FILE}: {key}: " + "; ".join(errors))
    return {k: e for k, e in table.items()
            if "spec" in e and split_key(k)[1] is None}


def load_units(table=None):
    """The heading entries of the unit pages, {page: {heading text: entry}},
    in table order (SR-17a)."""
    table = read_table() if table is None else table
    units = {}
    for key, e in table.items():
        page, heading = split_key(key)
        if heading is not None:
            units.setdefault(page, {})[heading] = e
    return units


def on_config(config):
    global SHOWN, HIDDEN, SPECS, UNITS
    SHOWN = shown_list(config)
    HIDDEN = set()
    table = read_table()
    SPECS = load_specs(table)
    UNITS = load_units(table)
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


def escape_names(line):
    """line with what Markdown would lose from a name escaped, outside inline
    code: the * of a pattern such as tbl_ri_*, as two in one paragraph would be
    read as emphasis, and a placeholder such as <PRED>_STARVE_THRESH, read as an
    HTML tag. An autolink, <https://...>, does not match NAME_TAG_RE."""
    parts = line.split("`")
    parts[::2] = [NAME_TAG_RE.sub(r"&lt;\1&gt;", p).replace("_*", "_\\*")
                  for p in parts[::2]]
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
            out.extend(escape_names(l) if indent_of(l) < 4 else l
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
        return spec_dir, f"RTL tag {tag}", tag
    name = "the main branch" if ci else "the working tree"
    return spec_dir or ROOT, name, "main"


def spec_anchor(path):
    """The id of a document's section on a unit page, from its file name."""
    return "spec-" + re.sub(r"[^a-z0-9]+", "-",
                            os.path.basename(path).lower()).strip("-")


def spec_section(path, base, name, ref, repo, page, anchor=False):
    """One document as a collapsed section, as Markdown lines. A document
    not in the tag is a one-line note and a warning (SR-18); with no tag the
    documents are the checkout's, and a missing one stops the build. With
    anchor, the section, or the note, holds the target of the document's
    Specification links (spec_anchor); Material opens a collapsed section
    holding the target of a link."""
    mark = f'<a id="{spec_anchor(path)}"></a>' if anchor else ""
    src = os.path.join(base, path)
    if not os.path.isfile(src):
        if release()[1] is None:
            raise OSError(f"{TABLE_FILE}: spec document {path} is not in"
                          f" {base}")
        log.warning(f"{page}: spec document {path} is not in {name}; shown"
                    f" as a note")
        return [f"{mark}`{path}` is not in {name}.", ""]
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
    head = [f"{mark}[{path} on GitHub]({repo}/blob/{ref}/{path})", ""]
    return (spdx + ["", f'??? abstract "{os.path.basename(path)}"', ""]
            + [f"    {l}" if l.strip() else "" for l in head + body] + [""])


def spec_page(markdown, src, entry, repo):
    """The page's title, status line, the advisory and its documents, in
    place of its placeholder block (SR-17)."""
    parts = split_page(markdown)
    if parts is None or not is_empty_body(parts[1]):
        raise ValueError(f"{src}: has a spec: list and written content")
    base, name, ref = spec_source()
    lines = [
        parts[0].rstrip("\n"), "",
        SPEC_STATUS.format(RTL_WORDS[entry["rtl"]]), "",
        '!!! note "Working specification"', "",
        "    " + ADVISORY.format(name), "",
    ]
    for path in entry["spec"]:
        lines += spec_section(path, base, name, ref, repo, src)
    return "\n".join(lines)


def covers_sentence(e):
    """The covers line as a sentence: its first letter capitalized, ending in
    a period."""
    covers = str(e["covers"]).strip()
    covers = covers[:1].upper() + covers[1:]
    return covers if covers.endswith(".") else covers + "."


def related_line(e):
    """The see: links as the placeholder words them, joined after
    "Related:", or None with no see: list. A hidden scenario's item is
    dropped, as from the placeholder's list (SR-15)."""
    items = [see_line(item) for item in e.get("see") or []
             if item.get("demo") not in HIDDEN]
    return "Related: " + "; ".join(items) if items else None


def heading_lines(e):
    """A heading's status line and covers sentence, as Markdown lines."""
    status = (SPEC_STATUS.format(RTL_WORDS[e["rtl"]]) if "spec" in e
              else status_line(e))
    return [status, "", covers_sentence(e), ""]


def unit_page(markdown, src, heads, repo):
    """The unit page with each listed, unwritten heading rendered, and the
    documents shown once, in the Overview heading (SR-17a)."""
    parts = split_page(markdown)
    if parts is None:
        raise ValueError(f"{src}: a unit page has no # title line")
    pre, sections = split_sections(parts[1])
    names = [s.name for s in sections]
    missing = [h for h in heads if h not in names]
    if missing:
        raise ValueError(f"{TABLE_FILE}: {src}: no such heading: "
                         + ", ".join(missing))
    docs = []
    order = ([OVERVIEW] if OVERVIEW in heads else []) + names
    for name in order:
        for path in (heads.get(name) or {}).get("spec", []):
            if path not in docs:
                docs.append(path)
    if docs and OVERVIEW not in names:
        raise ValueError(f"{src}: lists planning documents and has no"
                         f" {OVERVIEW} heading")
    UNIT_HEADINGS[src] = set(names)
    base, name, ref = spec_source()
    out = [parts[0].rstrip("\n"), ""]
    if pre.strip():
        out += [pre.strip("\n"), ""]
    for s in sections:
        e = heads.get(s.name)
        out += [s.line, ""]
        if e is None or not is_empty_body(s.text):
            if e is not None and "spec" in e:
                raise ValueError(f"{src}: heading '{s.name}' has a spec:"
                                 f" list and written content")
            if s.text.strip():
                out += [s.text.strip("\n"), ""]
            continue
        out += heading_lines(e)
        related = related_line(e)
        if s.name == OVERVIEW:
            if related:
                out += [related, ""]
            if docs:
                out += ['!!! note "Working specification"', "",
                        "    " + ADVISORY.format(name), ""]
                for path in docs:
                    out += spec_section(path, base, name, ref, repo, src,
                                        anchor=True)
            continue
        if "spec" in e:
            links = ", ".join(f"[{os.path.basename(p)}](#{spec_anchor(p)})"
                              for p in e["spec"])
            out += [SPEC_LINE.format(links), ""]
        if related:
            out += [related, ""]
    return "\n".join(out)


def keep_headings(items, names):
    """The table of contents items whose title is a heading of the page,
    each with its children so kept; nothing under the Overview, which holds
    the documents."""
    kept = []
    for item in items:
        if item.title not in names:
            continue
        item.children = ([] if item.title == OVERVIEW
                         else keep_headings(item.children, names))
        kept.append(item)
    return kept


def plain_ids(html, items):
    """html with each of the items' headings given its plain id, such as
    tage. A heading of a document in the Overview, earlier on the page, may
    have taken it, leaving the page's own heading tage_1; the two ids are
    exchanged, in the ids and in every link to them, so each link still
    opens what it opened."""
    for item in items:
        html = plain_ids(html, item.children)
        plain = re.sub(r"_\d+$", "", item.id)
        if plain == item.id or f'id="{plain}"' not in html:
            continue
        swap = {plain: item.id, item.id: plain}
        html = re.sub(r'(id="|href="#)(' + re.escape(plain) + "|"
                      + re.escape(item.id) + ')"',
                      lambda m: m.group(1) + swap[m.group(2)] + '"', html)
        item.id = plain
    return html


def on_page_content(html, page, config, files):
    """A page with a spec: list has no heading of its own under its title
    (spec_page), so every other entry of its table of contents is from a
    document, and is removed. A unit page's table of contents keeps its own
    headings only, each with its plain id (plain_ids)."""
    src = page.file.src_uri
    if src in SPECS:
        for item in page.toc:
            item.children = []
    if src in UNITS:
        names = UNIT_HEADINGS.get(src, set())
        for item in page.toc:
            item.children = keep_headings(item.children, names)
            html = plain_ids(html, item.children)
    return html


def on_page_markdown(markdown, page, config, files):
    src = page.file.src_uri
    ci, tag, demo = release()
    repo = config.get("repo_url", "").rstrip("/")
    if src in SPECS:
        markdown = spec_page(markdown, src, SPECS[src], repo)
    if src in UNITS:
        markdown = unit_page(markdown, src, UNITS[src], repo)
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
