#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
"""
stamp.py -- THE BUILD STAMP of the performance harness (PERF-004, TD#210,
perf_decisions.md PF-9). Run by perf/Makefile, not by hand.

The stamp says what a harness build measures. Three values:
  sha     the git sha of SRC_ROOT (git -C SRC_ROOT rev-parse HEAD), or
          "unversioned" when SRC_ROOT is not a git work tree
  dirty   "clean"; or "dirty:" and the areas that differ from the sha,
          "rtl" when SRC_ROOT has tracked changes or untracked files
          under rtl/, "perf" when the harness tree (the perf Makefile's
          RVA_ROOT) has them under perf/, joined by "+" (git status
          --porcelain, so .gitignore applies); "unversioned" with the
          sha; "unknown" when git cannot answer
  digest  THE INPUT DIGEST: the SHA-256 of a manifest of every build
          input, in the order the Makefile gives them. One line per file:
          its path relative to its root and the SHA-256 of its contents
          (a file under the harness tree's perf/ is relative to the
          harness tree, any other to SRC_ROOT, else to the harness tree,
          else absolute). Then one line per make variable that reaches
          the build, NAME=VALUE, and one line per tool, its version line.
          The same inputs give the same digest wherever the trees are:
          paths are relative, and NAME, SRC_ROOT and JOBS, which do not
          change what is built, are not inputs.
The only git calls are the two read-only ones above (rev-parse, status).

Usage, from perf/Makefile:
  stamp.py --src-root R --perf-root P [--header H] [--manifest M]
           [--print] [--var NAME=VALUE ...] [--tool NAME=COMMAND ...]
           FILE ...
--header writes the C header perf_fe.cc includes (PERF_SRC_SHA,
PERF_SRC_DIRTY, PERF_INPUT_DIGEST), and --manifest the manifest, each only
when its text changes: the binary depends on the header, so it rebuilds
when the stamp changes and only then. --print writes the stamp to stdout.
A FILE that does not exist stops the stamp: every input is listed.
"""

import argparse
import hashlib
import os
import subprocess
import sys


def git(root, args):
    """The output of a read-only git call in root, None on failure."""
    try:
        p = subprocess.run(["git", "-C", root] + args, capture_output=True,
                           text=True)
    except OSError:
        return None
    return p.stdout if p.returncode == 0 else None


def file_sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(1 << 20)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def under(path, root):
    root = os.path.realpath(root)
    return path == root or path.startswith(root + os.sep)


def rel_path(path, src_root, perf_root):
    """The path a manifest line names: relative to its root (above)."""
    ap = os.path.realpath(path)
    for root, base in ((os.path.join(perf_root, "perf"), perf_root),
                       (src_root, src_root), (perf_root, perf_root)):
        if under(ap, root):
            return os.path.relpath(ap, os.path.realpath(base))
    return ap


def dirty_mark(src_root, perf_root, sha):
    if sha == "unversioned":
        return "unversioned"
    areas = []
    for root, area in ((src_root, "rtl"), (perf_root, "perf")):
        out = git(root, ["status", "--porcelain", "--untracked-files=all",
                         "--", area])
        if out is None:
            return "unknown"
        if out.strip():
            areas.append(area)
    return "dirty:" + "+".join(areas) if areas else "clean"


def write_if_changed(path, text):
    old = None
    if os.path.isfile(path):
        with open(path) as f:
            old = f.read()
    if old != text:
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, exist_ok=True)
        with open(path, "w") as f:
            f.write(text)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--src-root", required=True)
    ap.add_argument("--perf-root", required=True)
    ap.add_argument("--header")
    ap.add_argument("--manifest")
    ap.add_argument("--print", action="store_true")
    ap.add_argument("--var", action="append", default=[])
    ap.add_argument("--tool", action="append", default=[])
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()

    lines = []
    seen = set()
    for f in a.files:
        rp = rel_path(f, a.src_root, a.perf_root)
        if rp in seen:
            continue
        seen.add(rp)
        if not os.path.isfile(f):
            sys.exit("stamp.py: build input %s not found" % f)
        lines.append("file %s %s" % (rp, file_sha(f)))
    for v in a.var:
        # Whitespace inside a value is not significant to the build.
        name, _, val = v.partition("=")
        lines.append("var %s=%s" % (name, " ".join(val.split())))
    for t in a.tool:
        name, _, cmd = t.partition("=")
        try:
            p = subprocess.run(cmd, shell=True, capture_output=True,
                               text=True)
            out = p.stdout.strip().splitlines()
            ver = out[0] if (p.returncode == 0 and out) else "unknown"
        except OSError:
            ver = "unknown"
        lines.append("tool %s %s" % (name, ver))
    manifest = "\n".join(lines) + "\n"
    digest = hashlib.sha256(manifest.encode()).hexdigest()

    out = git(a.src_root, ["rev-parse", "HEAD"])
    sha = out.strip() if out else "unversioned"
    dirty = dirty_mark(a.src_root, a.perf_root, sha)

    if a.manifest:
        write_if_changed(a.manifest, manifest)
    if a.header:
        write_if_changed(a.header, (
            "// The build stamp, written by perf/src/stamp.py (PERF-004,\n"
            "// TD#210). Do not edit: the perf Makefile rewrites it when it\n"
            "// changes.\n"
            "#define PERF_SRC_SHA \"%s\"\n"
            "#define PERF_SRC_DIRTY \"%s\"\n"
            "#define PERF_INPUT_DIGEST \"%s\"\n" % (sha, dirty, digest)))
    if a.print:
        print("sha     %s" % sha)
        print("dirty   %s" % dirty)
        print("digest  %s" % digest)
        print("inputs  %d files, %d variables, %d tools" %
              (len(seen), len(a.var), len(a.tool)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
