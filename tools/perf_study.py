#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
"""
perf_study.py -- a performance study: every trace of a list under every
parameter set of a list, run in parallel through the harness, gathered
into one CSV (PERF-002 Problem 5, perf_decisions.md PF-7, PF-9).

A parameter-set file holds one set per line: a name, then the harness's
arguments (perf/build/<NAME>_s<SLOTS>/perf_fe --help). Blank lines and
lines starting with # are skipped. A set may name its build with
bin=<path> as its first argument; otherwise --bin is used.
  base     --execute-lat fixed:0
  lat8     --execute-lat fixed:8 --resolve-commit uniform:0:4
A trace list holds one <group>/<trace> per line, or is given with
--traces as a comma-separated list.

Each run appends its row to its own CSV in the work directory; at the end
the rows are gathered into --out, with the set name as the first column
(study_set). Every row carries the trace, the configuration name, the
revision sha, the dirty mark, the input digest, the seed and every run
parameter (PF-9).

THE DIGEST RULE (PERF-004, TD#210). Each build's stamp (perf_fe --stamp)
is read before the runs. The rows are gathered only when every row's
input_digest is its build's, and, when the parameter-set file names one
build, when every row has the same digest. Otherwise nothing is written
to --out (the per-run CSVs stay in the work directory) and the exit is
non-zero: rows of different inputs are not one study unless the file
says so by naming more than one build.

Usage, from the repository root:
  python3 tools/perf_study.py --traces <list or file> --sets <file>
                              --out <csv> [-j N] [--bin <perf_fe>]
                              [--work <dir>]
-j defaults to 75% of the hardware threads, at least 1 (PF-22).
Setup notes: README.md, section Performance analysis.
"""

import argparse
import csv
import multiprocessing
import os
import shlex
import subprocess
import sys
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_BIN = os.path.join(REPO_ROOT, "perf", "build", "head_s2", "perf_fe")


def run(job):
    name, trace, binp, argv, out = job
    if os.path.exists(out):
        os.remove(out)
    t0 = time.time()
    p = subprocess.run([binp, "--trace", trace, "--out", out] + argv,
                       capture_output=True, text=True)
    return (name, trace, p.returncode, out, time.time() - t0,
            p.stderr.strip().splitlines()[-1:] if p.stderr else [])


def stamp(binp):
    """The build's stamp (PERF-004): sha, dirty, digest, build."""
    p = subprocess.run([binp, "--stamp"], capture_output=True, text=True)
    out = {}
    for ln in p.stdout.splitlines():
        f = ln.split(None, 1)
        if len(f) == 2:
            out[f[0]] = f[1].strip()
    if p.returncode != 0 or "digest" not in out:
        sys.exit("perf_study.py: %s gives no build stamp (built before "
                 "PERF-004?); rebuild it (make -C perf harness)" % binp)
    return out


def default_jobs():
    """PF-22: 75% of the hardware threads, rounded down, at least 1."""
    return max(1, (os.cpu_count() or 1) * 3 // 4)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--traces", required=True)
    ap.add_argument("--sets", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--bin", default=DEFAULT_BIN)
    ap.add_argument("--work", default=None)
    ap.add_argument("-j", "--jobs", type=int, default=default_jobs(),
                    help="worker processes (default %d: 75%%%% of the %d "
                    "hardware threads, PF-22)" % (default_jobs(),
                                                  os.cpu_count() or 1))
    args = ap.parse_args()

    if os.path.isfile(args.traces):
        traces = [ln.strip() for ln in open(args.traces)
                  if ln.strip() and not ln.startswith("#")]
    else:
        traces = [t for t in args.traces.split(",") if t]
    sets = []
    for ln in open(args.sets):
        ln = ln.strip()
        if not ln or ln.startswith("#"):
            continue
        f = shlex.split(ln)
        binp = args.bin
        if len(f) > 1 and f[1].startswith("bin="):
            binp = f[1][4:]
            f = [f[0]] + f[2:]
        sets.append((f[0], binp, f[1:]))
    work = args.work or os.path.splitext(args.out)[0] + "_work"
    os.makedirs(work, exist_ok=True)
    jobs = []
    for name, binp, argv in sets:
        if not os.access(binp, os.X_OK):
            sys.exit("perf_study.py: %s not built (make -C perf harness)"
                     % binp)
        for t in traces:
            out = os.path.join(work, "%s__%s.csv" % (name, t.replace("/", "_")))
            jobs.append((name, t, binp, argv, out))
    stamps = {}
    for name, binp, argv in sets:
        if binp not in stamps:
            stamps[binp] = stamp(binp)
            s = stamps[binp]
            print("perf_study.py: build %s: sha %s, %s, digest %s" %
                  (binp, s.get("sha"), s.get("dirty"), s["digest"]))
    nproc = min(args.jobs, len(jobs))
    print("perf_study.py: %d traces x %d sets = %d runs, %d processes "
          "(-j %d)" % (len(traces), len(sets), len(jobs), nproc, args.jobs))
    t0 = time.time()
    done = []
    with multiprocessing.Pool(nproc) as pool:
        for r in pool.imap_unordered(run, jobs):
            name, trace, rc, out, sec, err = r
            print("  %-12s %-24s exit %d  %.0f s %s" % (name, trace, rc, sec,
                                                        " ".join(err)))
            sys.stdout.flush()
            done.append(r)
    set_bin = {name: binp for name, binp, argv in sets}
    cols, rows = None, []
    for name, trace, rc, out, sec, err in sorted(done):
        if not os.path.isfile(out):
            continue
        with open(out, newline="") as f:
            for r in csv.DictReader(f):
                if cols is None:
                    cols = ["study_set"] + list(r.keys())
                r["study_set"] = name
                rows.append(r)
    if cols is None:
        sys.exit("perf_study.py: no run wrote a row")
    # THE DIGEST RULE (PERF-004): one set of inputs per build, and one in
    # all unless the parameter-set file names more than one build.
    bad = []
    for r in rows:
        want = stamps[set_bin[r["study_set"]]]["digest"]
        if r.get("input_digest", "") != want:
            bad.append("%s %s: input_digest %s, its build's %s" % (
                r["study_set"], r["trace"], r.get("input_digest", "none"),
                want))
    digests = sorted({r.get("input_digest", "") for r in rows})
    if len(digests) > 1 and len(stamps) < 2:
        bad.append("%d input digests (%s) from one build" %
                   (len(digests), ", ".join(digests)))
    if bad:
        for b in bad[:20]:
            print("perf_study.py: " + b)
        sys.exit("perf_study.py: rows of different inputs; %s not written "
                 "(the runs' rows are in %s)" % (args.out, work))
    with open(args.out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, lineterminator="\n",
                           extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)
    bad = sum(1 for r in done if r[2] != 0)
    print("wrote %s: %d rows, %d runs exited non-zero, wall %.0f s"
          % (args.out, len(rows), bad, time.time() - t0))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
