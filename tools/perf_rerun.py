#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
"""
perf_rerun.py -- THE REFERENCE RERUNS (PERF-002 Problem 3,
perf_decisions.md PF-1, PF-15).

Every CBP predictor of PF-1 (the nine CBP2025 entries, CBP2016 and
TAGE192) is run on the changed traces through tools/cbp2025's own
binaries (make -C tools/cbp2025 all) and its own runner,
scripts/trace_exec_training_list.py; the submodule is not changed. The
traces that need no change are run as they are and checked against the
golden results, tools/cbp2025/golden_results/<predictor>/<group>/
results.csv. Each trace is checked against its SHA-256 list before it is
run (PF-14).

PLANS:
  full      every predictor on every changed trace, and on every trace
            that needs no change
  fallback  (default) TAGE192 on every changed trace; every predictor on
            every trace that needs no change; the other ten on one
            changed trace per group, the group's shortest
  --only P  limit the predictors, comma separated

A trace needs no change when perf/cbp2025_rv_veneers.csv gives it no
stub and no reclassified record. The runner's logs go under
CBP_TRACES_RV/rerun/<predictor>/<set>/<group>/<trace>/; the table is
perf/cbp2025_rv_rerun.csv, one row per predictor and trace:
  predictor, set (rv: changed, orig: as it is), group, trace, Status,
  Instr, NumBr, MispBr, MPKI, 50PercInstr, 50PercNumBr, 50PercMPKI,
  ExecTime, the golden result's Instr, NumBr, MPKI and 50PercMPKI on the
  original trace, MPKI - golden MPKI, and for set orig whether every
  column equals the golden row (golden_equal).

Usage, from the repository root:
  python3 tools/perf_rerun.py [-j N] [--plan full|fallback] [--only P]
                              [--dry-run]
-j defaults to 75% of the hardware threads, at least 1 (PF-22).
Setup notes: README.md, section Performance analysis.
"""

import argparse
import csv
import hashlib
import multiprocessing
import os
import subprocess
import sys
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
README_REF = "see README.md, section Performance analysis"
CBP = os.path.join(REPO_ROOT, "tools", "cbp2025")
RUNNER = os.path.join(CBP, "scripts", "trace_exec_training_list.py")
PREDICTORS = ["tage192", "cbp2016", "behrendt", "cai", "fan", "jimenez",
              "koizumi", "man", "mose", "ros", "seznec"]
GROUPS = ["compress", "fp", "infra", "int", "media", "web"]
COLS = ["Instr", "NumBr", "MispBr", "MPKI", "50PercInstr", "50PercNumBr",
        "50PercMispBr", "50PercMPKI"]
OUT = os.path.join(REPO_ROOT, "perf", "cbp2025_rv_rerun.csv")


def fail(msg):
    sys.stderr.write("perf_rerun.py: %s\n  (%s)\n" % (msg, README_REF))
    sys.exit(1)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(4 << 20)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def read_list(path):
    out = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                sha, rel = line.split("  ", 1)
                out[rel] = sha
    return out


def run_one(job):
    """One predictor on one trace through the submodule's runner."""
    pred, tset, group, trace, path, outdir = job
    os.makedirs(outdir, exist_ok=True)
    lst = os.path.join(outdir, "trace_list.txt")
    with open(lst, "w") as f:
        f.write(path + "\n")
    t0 = time.time()
    p = subprocess.run([sys.executable, RUNNER, "--cbp_path",
                        os.path.join(CBP, "bin", "cbp." + pred),
                        "--trace_list", lst, "--results_dir", outdir,
                        "--jobs", "1"], capture_output=True, text=True,
                       cwd=CBP)
    row = None
    res = os.path.join(outdir, "results.csv")
    if os.path.isfile(res):
        with open(res, newline="") as f:
            for r in csv.DictReader(f):
                row = r
    return (pred, tset, group, trace, p.returncode, row, time.time() - t0)


def golden(pred, group):
    path = os.path.join(CBP, "golden_results", pred, group, "results.csv")
    out = {}
    if os.path.isfile(path):
        with open(path, newline="") as f:
            for r in csv.DictReader(f):
                out[r["Run"]] = r
    return out


def default_jobs():
    """PF-22: 75% of the hardware threads, rounded down, at least 1."""
    return max(1, (os.cpu_count() or 1) * 3 // 4)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("-j", "--jobs", type=int, default=default_jobs(),
                    help="worker processes (default %d: 75%%%% of the %d "
                    "hardware threads, PF-22)" % (default_jobs(),
                                                  os.cpu_count() or 1))
    ap.add_argument("--plan", choices=("full", "fallback"),
                    default="fallback")
    ap.add_argument("--only", help="predictors, comma separated")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    preds = PREDICTORS if not args.only else args.only.split(",")
    for p in preds:
        if p not in PREDICTORS:
            fail("unknown predictor %s" % p)
        if not os.access(os.path.join(CBP, "bin", "cbp." + p), os.X_OK):
            fail("tools/cbp2025/bin/cbp.%s not built; run make -C "
                 "tools/cbp2025 all" % p)
    rv_root = os.path.abspath(os.environ.get(
        "CBP_TRACES_RV", os.path.join(REPO_ROOT, "..", "cbp_traces_rv")))
    tr_root = os.path.abspath(os.environ.get(
        "CBP_TRACES", os.path.join(REPO_ROOT, "..", "cbp_traces")))
    rv_list = read_list(os.path.join(REPO_ROOT, "perf", "cbp2025_rv.sha256"))
    tr_list = read_list(os.path.join(REPO_ROOT, "perf",
                                     "cbp2025_training.sha256"))
    ven = {}
    with open(os.path.join(REPO_ROOT, "perf", "cbp2025_rv_veneers.csv"),
              newline="") as f:
        for r in csv.DictReader(f):
            ven[(r["group"], r["trace"])] = r
    changed = [k for k, r in sorted(ven.items())
               if int(r["stubs"]) or int(r["reclass_dyn"])]
    same = [k for k, r in sorted(ven.items())
            if not int(r["stubs"]) and not int(r["reclass_dyn"])]
    # The shortest changed trace of each group.
    short = {}
    for k in changed:
        n = int(ven[k]["new_records"])
        if k[0] not in short or n < int(ven[short[k[0]]]["new_records"]):
            short[k[0]] = k

    jobs = []

    def add(pred, tset, k):
        rel = "training_traces/%s/%s.gz" % k
        root, lst = (rv_root, rv_list) if tset == "rv" else (tr_root, tr_list)
        jobs.append((pred, tset, k[0], k[1], os.path.join(root, rel),
                     os.path.join(rv_root, "rerun", pred, tset, k[0], k[1]),
                     rel, lst.get(rel)))

    for pred in preds:
        for k in same:
            add(pred, "orig", k)
        if args.plan == "full" or pred == "tage192":
            for k in changed:
                add(pred, "rv", k)
        else:
            for g in GROUPS:
                add(pred, "rv", short[g])
    print("perf_rerun.py: plan %s, %d runs: %d changed traces, %d that "
          "need no change (%s)" % (args.plan, len(jobs), len(changed),
                                   len(same), " ".join("/".join(k)
                                                       for k in same)))
    print("perf_rerun.py: %d worker processes" % args.jobs)
    if args.dry_run:
        for j in jobs:
            print("  %s %s %s/%s" % (j[0], j[1], j[2], j[3]))
        return 0

    # Every input checked before any run (PF-14).
    seen = set()
    for j in jobs:
        if j[4] in seen:
            continue
        seen.add(j[4])
        if not os.path.isfile(j[4]):
            fail("trace %s not found" % j[4])
        if j[7] is None or sha256_of(j[4]) != j[7]:
            fail("trace %s does not match its SHA-256 list" % j[4])
    print("checked %d trace files" % len(seen))

    # Longest first: TAGE192 and the long traces start early.
    def size(j):
        return os.path.getsize(j[4])
    order = sorted(jobs, key=size, reverse=True)
    t0 = time.time()
    results = []
    with multiprocessing.Pool(args.jobs) as pool:
        for r in pool.imap_unordered(run_one, [j[:6] for j in order]):
            pred, tset, group, trace, rc, row, sec = r
            st = row["Status"] if row else "no result"
            print("  %s %s %s/%s %s MPKI %s %.0f s" % (
                pred, tset, group, trace, st, row["MPKI"] if row else "-",
                sec))
            sys.stdout.flush()
            results.append(r)
    wall = time.time() - t0

    gold = {}
    rows = []
    bad_equal = 0
    for pred, tset, group, trace, rc, row, sec in sorted(results):
        g = gold.setdefault((pred, group), golden(pred, group)).get(trace)
        out = {"predictor": pred, "set": tset, "group": group,
               "trace": trace, "Status": row["Status"] if row else "Fail"}
        for c in COLS:
            out[c] = row[c] if row else ""
        out["ExecTime"] = row["ExecTime"] if row else ""
        for c in ("Instr", "NumBr", "MPKI", "50PercMPKI"):
            out["golden_" + c] = g[c] if g else ""
        try:
            out["MPKI_minus_golden"] = "%.4f" % (float(out["MPKI"]) -
                                                 float(g["MPKI"]))
        except (TypeError, ValueError, KeyError):
            out["MPKI_minus_golden"] = ""
        if tset == "orig":
            eq = bool(row and g and g["Status"] == "Pass" and
                      all(row[c] == g[c] for c in COLS))
            out["golden_equal"] = "1" if eq else "0"
            if not eq:
                bad_equal += 1
        else:
            out["golden_equal"] = ""
        rows.append(out)
    cols = ["predictor", "set", "group", "trace", "Status"] + COLS + [
        "ExecTime", "golden_Instr", "golden_NumBr", "golden_MPKI",
        "golden_50PercMPKI", "MPKI_minus_golden", "golden_equal"]
    with open(OUT, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, lineterminator="\n")
        w.writeheader()
        for r in rows:
            w.writerow(r)
    core_s = sum(r[6] for r in results)
    print("wrote %s, %d rows; %d unchanged-trace rows differ from the "
          "golden results; wall %.0f s, %.1f core-hours" %
          (OUT, len(rows), bad_equal, wall, core_s / 3600))
    return 0


if __name__ == "__main__":
    sys.exit(main())
