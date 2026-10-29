#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# publish_waves.py -- publish the frontend demo waveforms (B6-2, DOC-008)
#
# Runs every scenario in examples/fe_demo, then publishes each one's FST
# and Surfer command file to uarchlabs/pacino-waves, served by GitHub
# Pages at https://uarchlabs.github.io/pacino-waves/. The Showcase pages
# (tools/mkdocs_showcase.py) open them in Surfer's web build. The release
# rules are planning/showcase/showcase_release_decisions.md (SR-N).
#
# USAGE (from anywhere in this repo):
#
#   tools/publish_waves.py [--published FILE]
#       publish HEAD, which must be at an annotated fe-* tag (SR-9)
#   tools/publish_waves.py --tag fe-1.0.0 --commit <sha> [...]
#       the tag and its commit as arguments. A dry run takes them as
#       given, with no git lookup (SR-10); a publish checks them (below)
#   tools/publish_waves.py --tag fe-1.0.0 [...]
#       look up the tag's commit with git; HEAD must be that commit
#   tools/publish_waves.py --untagged [--commit <sha>] [...]
#       the override: record the tag as untagged (SR-9). A publish
#       publishes HEAD and refuses a <sha> that is not HEAD; a dry run
#       given <sha> records it with no git lookup
#   --dry-run [--out DIR]
#       build and check everything, write the files that would be pushed
#       into DIR (default examples/fe_demo/out/publish_dry_run/), push
#       nothing. With --tag and --commit, or --untagged and --commit, a
#       dry run runs no git command at all
#   --no-build
#       with --dry-run only: use the FSTs already in examples/fe_demo/out/
#       instead of running the scenarios (DOC-008 tests)
#   --published FILE
#       the published manifest.json, a local file, for the staleness
#       report (SR-12); without it the report is skipped
#
# A tag is fe-<major>.<minor>.<patch>, decimal fields, no leading zero
# (SR-1, tools/fe_release.py). Without --tag, --commit and --untagged the
# script looks up HEAD's tags with git and refuses, before building
# anything, unless HEAD is at an annotated fe-* tag; with more than one,
# the latest (SR-4) is recorded.
#
# A PUBLISH (no --dry-run) checks with git, whatever the arguments, and
# refuses before building anything when (SR-9a, SR-10):
#   - the tag is not annotated or does not name HEAD, or a given --commit
#     is not HEAD (the commit published is always HEAD)
#   - a tracked file under rtl/ or examples/fe_demo/ differs from HEAD, or
#     an untracked file there is not ignored; read from
#       git status --porcelain=v1 -z --no-renames --untracked-files=all
#     a change elsewhere in the tree only warns
# A dry run warns on any uncommitted change (git status --porcelain) and
# goes on.
#
# STEPS:
#   1. resolve the tag and the commit; refuse when there is no tag and no
#      override, and, for a publish, on a tag check or a dirty tree
#   2. refuse to run if RVA_ROOT is set and is not this repo's root
#   3. read --published, when given
#   4. make -C examples/fe_demo scenarios; stop on any failure
#   5. compute each scenario's digest and print the staleness report
#   6. write <scenario>.fst, <scenario>.sucl, .nojekyll, manifest.json and
#      README.md into the dry-run directory, or into a clone of
#      pacino-waves kept in examples/fe_demo/pub/ (gitignored), cloning it
#      on first use
#   7. publish only: commit the clone's files as one new orphan commit on
#      main and force-push it, so the repo never keeps old binaries in its
#      history
#
# The scenario list is the Makefile's SCENARIOS, read through make.
#
# MANIFEST.JSON, one JSON object:
#   scenarios       the scenario names, in FD order
#   files           each published file name (<scenario>.fst,
#                   <scenario>.sucl) -> its size in bytes
#   pacino_commit   the full sha of the pacino commit the files were
#                   built from; the same as tag_commit
#   build_date      UTC, ISO 8601 with a Z suffix
#   tag             the fe-* tag published (SR-9), or "untagged" when
#                   the override was used
#   tag_commit      the full sha of the commit the tag names; under the
#                   override, the commit published
#   digest_version  the digest method, DIGEST_VERSION below; digests of
#                   another version are not compared
#   digests         each scenario name -> the sha256 hex digest of its
#                   waveform (SR-11, see DIGEST)
# The first four keys predate DOC-008 and keep their names and meaning.
#
# DIGEST (SR-11). A scenario's digest is computed from the signals its
# .sucl file adds (variable_add lines), read from its FST with
# tools/bin/fst2vcd through examples/fe_demo/waves/fe_demo_sigs.py. Each
# signal's value changes are put in a canonical form: the last value at
# each time, a value equal to the one before dropped, x or z as x. The
# digest is sha256 over the signals in name order, each as its Surfer
# name, then one "<time> <value in hex>" line per change. It depends on
# those decoded values and names only, not on the FST bytes, the order
# of the .sucl or any signal it does not list.
#
# STALENESS REPORT (SR-12). Each scenario is reported as
#   unchanged            its digest equals the published one
#   changed              it differs; a warning, never a stop
#   new                  the published manifest does not list it
#   no published digest  listed, but with no digest of this version
# A scenario the published manifest lists and this build does not is
# reported as removed.

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

import fe_release

WAVES_REMOTE = "git@github.com:uarchlabs/pacino-waves.git"
WAVES_URL = "https://uarchlabs.github.io/pacino-waves/"
BRANCH = "main"
UNTAGGED = "untagged"
DIGEST_VERSION = 1

ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
DEMO = os.path.join(ROOT, "examples", "fe_demo")
PUB = os.path.join(DEMO, "pub")
DRY_OUT = os.path.join(DEMO, "out", "publish_dry_run")

SHA_RE = re.compile(r"[0-9a-f]{40}")


def die(msg):
    print(f"publish_waves: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd, cwd=None, capture=False, env=None, strip=True):
    r = subprocess.run(cmd, cwd=cwd, env=env, text=True,
                       stdout=subprocess.PIPE if capture else None)
    if r.returncode != 0:
        die(f"failed ({r.returncode}): {' '.join(cmd)}")
    if not capture:
        return None
    return r.stdout.strip() if strip else r.stdout


def git(*args, strip=True):
    """git in this repo, from PATH; its output, stripped unless strip is
    False (porcelain status starts with a significant space)."""
    return run(["git", "-C", ROOT, *args], capture=True, strip=strip)


def warn_dirty(commit):
    if git("status", "--porcelain"):
        print(f"[warning]    the pacino tree has uncommitted changes; the"
              f" manifest records {commit[:12]}")


# The directories a publish's waveforms are built from (SR-9a), and the
# status form read for them: one NUL-terminated "XY path" entry per
# changed or untracked file, paths from the repo root, unquoted; each
# untracked file listed (not its directory); ignored files left out.
GUARDED = ("rtl/", "examples/fe_demo/")
STATUS = ("status", "--porcelain=v1", "-z", "--no-renames",
          "--untracked-files=all")
WARN_LIST = 10


def status_entries(out):
    """[(XY, path)] of git status --porcelain=v1 -z output. A rename or
    copy entry (not produced under --no-renames) is followed by its source
    path, which is listed too."""
    fields = out.split("\0")
    entries = []
    i = 0
    while i < len(fields):
        f = fields[i]
        i += 1
        if len(f) < 4:
            continue
        xy = f[:2]
        entries.append((xy, f[3:]))
        if xy[0] in "RC" and i < len(fields):
            entries.append((xy, fields[i]))
            i += 1
    return entries


def refuse_dirty(commit):
    """A publish: refuses when a tracked file under rtl/ or
    examples/fe_demo/ differs from commit (HEAD), or an untracked file
    there is not ignored (SR-9a); warns on a change anywhere else."""
    entries = status_entries(git(*STATUS, strip=False))
    inside = [e for e in entries if e[1].startswith(GUARDED)]
    outside = [e for e in entries if not e[1].startswith(GUARDED)]
    if inside:
        die(f"{len(inside)} file(s) under rtl/ or examples/fe_demo/ differ"
            f" from HEAD {commit[:12]} or are untracked (SR-9a).\n"
            f"  Nothing was built or pushed. Commit, remove or ignore them,"
            f" or use --dry-run:\n"
            + "\n".join(f"    {xy} {path}" for xy, path in inside))
    if outside:
        print(f"[warning]    {len(outside)} uncommitted change(s) outside"
              f" rtl/ and examples/fe_demo/; the manifest records"
              f" {commit[:12]}")
        for xy, path in outside[:WARN_LIST]:
            print(f"    {xy} {path}")
        if len(outside) > WARN_LIST:
            print(f"    ... and {len(outside) - WARN_LIST} more")


def check_tree(commit, real):
    """A publish refuses a dirty rtl/ or examples/fe_demo/; a dry run
    warns on any uncommitted change."""
    if real:
        refuse_dirty(commit)
    else:
        warn_dirty(commit)


def check_given(given, head):
    """A publish publishes HEAD: a given --commit must be it (SR-10)."""
    if given is not None and given != head:
        die(f"--commit {given} is not HEAD {head} (SR-10).\n"
            f"  A publish builds and publishes HEAD. Nothing was built or"
            f" pushed. Check out\n  {given[:12]}, or give HEAD's sha.")


# ---------------------------------------------------------------------
# The tag gate (SR-9, SR-10)
# ---------------------------------------------------------------------
def lookup_head_tag(real):
    """HEAD and the latest annotated release tag at it; refuses when it
    has none. for-each-ref --points-at matches an annotated tag by the
    commit it names; objecttype is tag for an annotated tag and commit
    for a lightweight one. real: a publish, not a dry run."""
    head = git("rev-parse", "--verify", "HEAD^{commit}")
    refs = git("for-each-ref", "--points-at", head,
               "--format=%(objecttype) %(refname:strip=2)", "refs/tags/fe-*")
    annotated, other = [], []
    for line in refs.splitlines():
        typ, name = line.split()
        if typ == "tag" and fe_release.parse_tag(name):
            annotated.append(name)
        else:
            other.append(name)
    for name in other:
        print(f"[note]       {name} at HEAD is not an annotated"
              f" fe-<major>.<minor>.<patch> tag; ignored")
    if not annotated:
        die(f"HEAD {head[:12]} is at no annotated fe-<major>.<minor>.<patch>"
            f" tag (SR-9).\n  Nothing was built or pushed. Tag it, or pass"
            f" --untagged to publish it as\n  untagged; a dry run may give"
            f" --tag and --commit instead.")
    check_tree(head, real)
    return fe_release.latest_tag(annotated), head


def lookup_tag(tag, real, given=None):
    """The commit an annotated release tag names; HEAD must be it, and
    so must given, the --commit of a publish."""
    typ = git("cat-file", "-t", f"refs/tags/{tag}")
    if typ != "tag":
        die(f"{tag} is a lightweight tag; a release tag is annotated (SR-1)")
    commit = git("rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}")
    head = git("rev-parse", "--verify", "HEAD^{commit}")
    check_given(given, head)
    if head != commit:
        die(f"{tag} names {commit[:12]}, but HEAD is {head[:12]}; check out"
            f" the tag first")
    check_tree(commit, real)
    return commit


def resolve(args):
    """(tag, commit) from the arguments, or from git when they do not
    give both. Refuses, before anything is built, when there is no tag
    and no override. A publish always checks with git that the tag is
    annotated and names HEAD, and that the tree is clean (SR-9a, SR-10);
    only a dry run takes --commit without a git call."""
    if args.tag is not None and not fe_release.parse_tag(args.tag):
        die(f"{args.tag} is not a release tag: fe-<major>.<minor>.<patch>,"
            f" decimal fields, no leading zero (SR-1)")
    if args.commit is not None and not SHA_RE.fullmatch(args.commit):
        die(f"--commit {args.commit} is not a full 40-character sha")
    if args.untagged and args.tag is not None:
        die("--untagged and --tag together; give one")
    real = not args.dry_run
    if args.untagged:
        if args.commit is not None and not real:
            return UNTAGGED, args.commit
        head = git("rev-parse", "--verify", "HEAD^{commit}")
        check_given(args.commit, head)
        check_tree(head, real)
        return UNTAGGED, head
    if args.tag is not None and args.commit is not None and not real:
        return args.tag, args.commit
    if args.tag is None and args.commit is not None:
        die(f"--commit {args.commit[:12]} without --tag (SR-9). Nothing was"
            f" built or pushed.\n  Give --tag, or pass --untagged to"
            f" publish it as untagged.")
    if args.tag is not None:
        return args.tag, lookup_tag(args.tag, real, args.commit)
    return lookup_head_tag(real)


def check_rva_root():
    rva = os.environ.get("RVA_ROOT")
    if rva and os.path.realpath(rva) != ROOT:
        die(f"RVA_ROOT is {rva}, not this repo's root {ROOT}.\n"
            f"  The waveforms would be built from another tree. Unset it or"
            f" run\n  RVA_ROOT={ROOT} {sys.argv[0]} ...")


def scenarios(env):
    out = run(["make", "-C", DEMO, "-s", "--no-print-directory",
               "--eval", "print-scenarios: ; @echo $(SCENARIOS)",
               "print-scenarios"], capture=True, env=env)
    scen = out.split()
    if not scen:
        die("no SCENARIOS in examples/fe_demo/Makefile")
    return scen


# ---------------------------------------------------------------------
# The digest (SR-11)
# ---------------------------------------------------------------------
def sucl_signals(sucl):
    """The signals a .sucl file adds, as Surfer names, in file order."""
    with open(sucl) as f:
        return [l.split()[1] for l in f
                if l.startswith("variable_add ") and len(l.split()) == 2]


def canonical(changes):
    """A signal's value changes in canonical form: in time order, the last
    value at each time, a value equal to the one before dropped."""
    out = []
    for t, v in sorted(changes, key=lambda c: c[0]):
        if out and out[-1][0] == t:
            out.pop()
        if out and out[-1][1] == v:
            continue
        out.append((t, v))
    return out


def digest(values, names=None):
    """The digest of decoded waveform data: values maps each signal name
    to its value changes [(time, value)], the value an int or None for x
    or z. names, when given, are the signals digested (a .sucl's list);
    every other signal of values is left out."""
    if names is not None:
        values = {n: values[n] for n in names}
    h = hashlib.sha256()
    for name in sorted(values):
        h.update(f"S {name}\n".encode())
        for t, v in canonical(values[name]):
            h.update(f"{t} {'x' if v is None else format(v, 'x')}\n".encode())
    return h.hexdigest()


def scenario_digest(fst, sucl):
    """The digest of the signals sucl lists, read from fst."""
    sys.path.insert(0, os.path.join(DEMO, "waves"))
    import fe_demo_sigs
    by_surfer = {sname: path
                 for path, (_, sname, _) in fe_demo_sigs.fst_names(fst).items()}
    sigs = sucl_signals(sucl)
    missing = [s for s in sigs if s not in by_surfer]
    if missing:
        die(f"{os.path.basename(sucl)} lists signals {fst} lacks: "
            + ", ".join(missing))
    vals = fe_demo_sigs.fst_values(fst, [by_surfer[s] for s in sigs])
    return digest({s: vals[by_surfer[s]] for s in sigs}, sigs)


# ---------------------------------------------------------------------
# The staleness report (SR-12)
# ---------------------------------------------------------------------
def staleness(digests, published):
    """Each scenario of digests -> unchanged, changed, new or no published
    digest, against the published manifest (a dict)."""
    listed = set(published.get("scenarios", []))
    pub = {}
    if published.get("digest_version") == DIGEST_VERSION:
        pub = published.get("digests") or {}
    status = {}
    for s, d in digests.items():
        if s in pub:
            status[s] = "unchanged" if pub[s] == d else "changed"
        elif s in listed:
            status[s] = "no published digest"
        else:
            status[s] = "new"
    return status


def report(digests, published, source):
    print(f"[staleness]  against {source}")
    status = staleness(digests, published)
    for s in digests:
        print(f"  {status[s]:<20} {s}")
        if status[s] == "changed":
            print(f"[warning]    {s}: its waveform differs from the"
                  f" published one")
    for s in published.get("scenarios", []):
        if s not in digests:
            print(f"  {'removed':<20} {s}")
    counts = {}
    for v in status.values():
        counts[v] = counts.get(v, 0) + 1
    print("[staleness]  " + ", ".join(f"{n} {k}"
                                      for k, n in sorted(counts.items())))
    return status


def read_published(path):
    try:
        with open(path) as f:
            published = json.load(f)
    except (OSError, ValueError) as e:
        die(f"--published {path}: {e}")
    if not isinstance(published, dict):
        die(f"--published {path}: not a JSON object")
    return published


# ---------------------------------------------------------------------
# Staging and publishing
# ---------------------------------------------------------------------
def clone():
    if not os.path.isdir(PUB):
        print(f"[cloning]    {WAVES_REMOTE} -> {PUB}")
        run(["git", "clone", WAVES_REMOTE, PUB])
        return
    if not os.path.isdir(os.path.join(PUB, ".git")):
        die(f"{PUB} exists but is not a git clone; remove it")
    url = run(["git", "-C", PUB, "remote", "get-url", "origin"],
              capture=True)
    if url != WAVES_REMOTE:
        die(f"{PUB} has origin {url}, expected {WAVES_REMOTE}")


def readme(tag, commit, date):
    return f"""# pacino-waves

Waveforms for the Pacino frontend demonstration, served by GitHub Pages at
{WAVES_URL} and opened in Surfer's web build from the Showcase pages of
https://uarchlabs.github.io/pacino/.

- `<scenario>.fst`: the scenario's waveform, from `examples/fe_demo/out/`
- `<scenario>.sucl`: its Surfer command file, from `examples/fe_demo/waves/`
- `manifest.json`: the scenarios, each file's size, the pacino commit, the
  build date, the release tag and each scenario's waveform digest

These files are generated by `tools/publish_waves.py` in
https://github.com/uarchlabs/pacino. Do not edit them here.

Release `{tag}`, built from pacino commit `{commit}` on {date}.

The history of this repo is replaced on every publish: each publish is a
single new commit, force-pushed, so old waveforms are not kept.
"""


def manifest(scen, files, tag, commit, date, digests):
    return {
        "scenarios": scen,
        "files": files,
        "pacino_commit": commit,
        "build_date": date,
        "tag": tag,
        "tag_commit": commit,
        "digest_version": DIGEST_VERSION,
        "digests": digests,
    }


def stage(dest, scen, tag, commit, date, digests):
    # Empty dest except .git, then copy in the new files.
    os.makedirs(dest, exist_ok=True)
    for name in os.listdir(dest):
        if name == ".git":
            continue
        path = os.path.join(dest, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)

    files = {}
    for s in scen:
        for src in (os.path.join(DEMO, "out", s, f"{s}.fst"),
                    os.path.join(DEMO, "waves", f"{s}.sucl")):
            name = os.path.basename(src)
            shutil.copyfile(src, os.path.join(dest, name))
            files[name] = os.path.getsize(src)

    open(os.path.join(dest, ".nojekyll"), "w").close()
    with open(os.path.join(dest, "manifest.json"), "w") as f:
        json.dump(manifest(scen, files, tag, commit, date, digests), f,
                  indent=2)
        f.write("\n")
    with open(os.path.join(dest, "README.md"), "w") as f:
        f.write(readme(tag, commit, date))


def publish(tag, commit):
    # A new orphan branch holds the one commit; it replaces main.
    tmp = "publish-tmp"
    subprocess.run(["git", "-C", PUB, "branch", "-q", "-D", tmp],
                   stderr=subprocess.DEVNULL)
    run(["git", "-C", PUB, "checkout", "-q", "--orphan", tmp])
    run(["git", "-C", PUB, "add", "-A"])
    run(["git", "-C", PUB, "commit", "-q", "-m",
         f"Waveforms from pacino {tag} {commit[:12]}"])
    run(["git", "-C", PUB, "branch", "-M", tmp, BRANCH])
    run(["git", "-C", PUB, "push", "--force", "origin", BRANCH])
    # Drop the old commits from the local clone too.
    run(["git", "-C", PUB, "reflog", "expire", "--expire=now", "--all"])
    run(["git", "-C", PUB, "gc", "-q", "--prune=now"])


def main():
    ap = argparse.ArgumentParser(description="Publish the fe_demo waveforms"
                                 " to uarchlabs/pacino-waves.")
    ap.add_argument("--tag", help="the fe-<major>.<minor>.<patch> tag to"
                    " record")
    ap.add_argument("--commit", help="the full sha the tag names; with --tag"
                    " and --dry-run, no git lookup; a publish requires HEAD")
    ap.add_argument("--untagged", action="store_true",
                    help="override: publish a commit at no tag, recorded as"
                    " untagged")
    ap.add_argument("--dry-run", action="store_true",
                    help="build and stage only, into --out; push nothing")
    ap.add_argument("--out", default=DRY_OUT,
                    help="the dry run's directory (default %(default)s)")
    ap.add_argument("--no-build", action="store_true",
                    help="with --dry-run: use the FSTs already built")
    ap.add_argument("--published", metavar="FILE",
                    help="the published manifest.json, for the staleness"
                    " report")
    args = ap.parse_args()
    if args.no_build and not args.dry_run:
        die("--no-build is for a dry run only")
    # Keep this script's lines in order with make's when piped.
    sys.stdout.reconfigure(line_buffering=True)

    tag, commit = resolve(args)
    print(f"[release]    {tag} at {commit}")
    check_rva_root()
    env = dict(os.environ, RVA_ROOT=ROOT)
    published = read_published(args.published) if args.published else None

    scen = scenarios(env)
    if args.no_build:
        print(f"[not built]  {len(scen)} scenarios; using the FSTs in"
              f" {os.path.join(DEMO, 'out')}")
    else:
        print(f"[building]   {len(scen)} scenarios in {DEMO}")
        run(["make", "-C", DEMO, "scenarios"], env=env)
    for s in scen:
        for src in (os.path.join(DEMO, "out", s, f"{s}.fst"),
                    os.path.join(DEMO, "waves", f"{s}.sucl")):
            if not os.path.isfile(src):
                die(f"missing {os.path.relpath(src, ROOT)}")

    t0 = time.monotonic()
    digests = {s: scenario_digest(os.path.join(DEMO, "out", s, f"{s}.fst"),
                                  os.path.join(DEMO, "waves", f"{s}.sucl"))
               for s in scen}
    print(f"[digests]    {len(digests)} scenarios in"
          f" {time.monotonic() - t0:.1f} s")
    if published is None:
        print("[staleness]  skipped: no --published manifest.json given")
    else:
        report(digests, published, args.published)

    date = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ")
    if args.dry_run:
        dest = os.path.abspath(args.out)
    else:
        clone()
        dest = PUB
    stage(dest, scen, tag, commit, date, digests)

    names = sorted(n for n in os.listdir(dest) if n != ".git")
    total = 0
    print(f"[staged]     {dest}")
    for n in names:
        size = os.path.getsize(os.path.join(dest, n))
        total += size
        print(f"  {size:>10}  {n}")
    print(f"[total]      {len(names)} files, {total} bytes"
          f" ({total / 1e6:.1f} MB)")

    if args.dry_run:
        print(f"[dry run]    a publish would copy these files into {PUB},"
              f"\n             commit them as one orphan commit on {BRANCH},"
              f" 'Waveforms from pacino {tag} {commit[:12]}',\n"
              f"             and run git push --force origin {BRANCH}"
              f" ({WAVES_REMOTE})")
        return
    publish(tag, commit)
    print(f"[published]  {WAVES_URL} ({tag})")


if __name__ == "__main__":
    main()
