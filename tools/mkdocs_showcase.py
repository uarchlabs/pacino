#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# mkdocs_showcase.py -- MkDocs hook (mkdocs.yml hooks:) for the Showcase
# section (B6-1, B6-2)
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
# served from WAVES (published by tools/publish_waves.sh). The footer
# gives the same link, the run and view commands, the scenario's program
# (programs/) and Surfer command file (waves/), and a link to the page's
# source on GitHub. A file that does not exist gets no line.
#
# docs/showcase/fe_demo is a symlink to examples/fe_demo/docs, so the
# demo directory is the parent of the symlink's target.

import os
import re
from urllib.parse import quote

WAVES = "https://uarchlabs.github.io/pacino-waves"
SURFER_APP = "https://app.surfer-project.org/"

SHOWCASE = "showcase/fe_demo/"
DEMO_REPO = "examples/fe_demo"
SCEN_RE = re.compile(r"^(fd\d\d_[a-z0-9_]+)\.md$")


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

    demo_dir = os.path.dirname(
        os.path.realpath(os.path.join(config["docs_dir"], SHOWCASE)))
    files_md = []
    for sub, ext in (("programs", ".svh"), ("waves", ".sucl")):
        rel = f"{sub}/{scen}{ext}"
        if os.path.isfile(os.path.join(demo_dir, rel)):
            files_md.append(f"`{rel}`")

    repo = config.get("repo_url", "").rstrip("/")
    src_url = f"{repo}/blob/main/{DEMO_REPO}/docs/{scen}.md"

    lines = ["", "---", ""] + wave_link(scen) + [
        "",
        f"**Run it** from `{DEMO_REPO}/`: `make {scen}` runs the scenario;"
        f" `make view S={scen}` opens its waveform in Surfer.",
    ]
    if files_md:
        lines += ["", "**Files:** " + ", ".join(files_md) + "."]
    lines += ["", f"[Source of this page on GitHub]({src_url})", ""]
    return markdown.rstrip("\n") + "\n" + "\n".join(lines)
