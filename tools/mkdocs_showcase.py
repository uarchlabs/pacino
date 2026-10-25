#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# mkdocs_showcase.py -- MkDocs hook (mkdocs.yml hooks:) for the Showcase
# section (B6-1)
#
# Appends a footer to each frontend demo scenario page,
# showcase/fe_demo/fdNN_<name>.md, on the published site only; the
# source in examples/fe_demo/docs/ is not changed. The footer gives the
# run and view commands, the scenario's program (programs/) and Surfer
# command file (waves/), and a link to the page's source on GitHub.
# A file that does not exist gets no line.
#
# docs/showcase/fe_demo is a symlink to examples/fe_demo/docs, so the
# demo directory is the parent of the symlink's target.

import os
import re

SHOWCASE = "showcase/fe_demo/"
DEMO_REPO = "examples/fe_demo"
SCEN_RE = re.compile(r"^(fd\d\d_[a-z0-9_]+)\.md$")


def on_page_markdown(markdown, page, config, files):
    src = page.file.src_uri
    if not src.startswith(SHOWCASE):
        return markdown
    m = SCEN_RE.match(src[len(SHOWCASE):])
    if not m:
        return markdown
    scen = m.group(1)

    demo_dir = os.path.dirname(
        os.path.realpath(os.path.join(config["docs_dir"], SHOWCASE)))
    files_md = []
    for sub, ext in (("programs", ".svh"), ("waves", ".sucl")):
        rel = f"{sub}/{scen}{ext}"
        if os.path.isfile(os.path.join(demo_dir, rel)):
            files_md.append(f"`{rel}`")

    repo = config.get("repo_url", "").rstrip("/")
    src_url = f"{repo}/blob/main/{DEMO_REPO}/docs/{scen}.md"

    lines = [
        "",
        "---",
        "",
        f"**Run it** from `{DEMO_REPO}/`: `make {scen}` runs the scenario;"
        f" `make view S={scen}` opens its waveform in Surfer.",
    ]
    if files_md:
        lines += ["", "**Files:** " + ", ".join(files_md) + "."]
    lines += ["", f"[Source of this page on GitHub]({src_url})", ""]
    return markdown.rstrip("\n") + "\n" + "\n".join(lines)
