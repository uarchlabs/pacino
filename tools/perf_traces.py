#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
"""
perf_traces.py -- make the changed traces and their page tables
(PERF-002, perf_decisions.md PF-15, PF-17).

Steps, from the repository root:
  1. make -C perf tools pt_gen
  2. perf/build/veneer: every training trace (CBP_TRACES, checked against
     perf/cbp2025_training.sha256) to its changed trace under
     CBP_TRACES_RV (default ../cbp_traces_rv), read back against the
     original; perf/cbp2025_rv_veneers.csv and perf/cbp2025_rv_counts.csv
  3. pt_gen on each trace's page list (CBP_TRACES_RV/pages/<group>/
     <trace>.pages) to its image (<trace>.img); any input pt_gen rejects
     is reported
  4. the SHA-256 lists: perf/cbp2025_rv.sha256 (the changed .gz files)
     and perf/cbp2025_rv_aux.sha256 (the page lists, images and stub
     lists), paths relative to CBP_TRACES_RV

Usage:
  python3 tools/perf_traces.py [-j N] [--skip-veneer]
--skip-veneer runs steps 3 and 4 on traces already written.
Setup notes: README.md, section Performance analysis.
"""

import argparse
import hashlib
import multiprocessing
import os
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
README_REF = "see README.md, section Performance analysis"
PT_GEN = os.path.join(REPO_ROOT, "perf", "build", "pt_gen", "Vpt_gen")


def fail(msg):
    sys.stderr.write("perf_traces.py: %s\n  (%s)\n" % (msg, README_REF))
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


def run_pt_gen(job):
    pages, img = job
    p = subprocess.run([PT_GEN, "+IN=" + pages, "+OUT=" + img],
                       capture_output=True, text=True)
    return (pages, img, p.returncode, (p.stdout + p.stderr).strip())


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count())
    ap.add_argument("--skip-veneer", action="store_true")
    args = ap.parse_args()

    rv_root = os.path.abspath(os.environ.get(
        "CBP_TRACES_RV", os.path.join(REPO_ROOT, "..", "cbp_traces_rv")))
    if subprocess.run(["make", "-C", os.path.join(REPO_ROOT, "perf"),
                       "tools", "pt_gen"]).returncode != 0:
        fail("the perf tools did not build")
    if not args.skip_veneer:
        if subprocess.run([os.path.join(REPO_ROOT, "perf", "build", "veneer"),
                           "-j", str(args.jobs)]).returncode != 0:
            fail("veneer failed")

    # The training list names the traces; each has its changed form.
    rels = []
    with open(os.path.join(REPO_ROOT, "perf",
                           "cbp2025_training.sha256")) as f:
        for line in f:
            line = line.strip()
            if line:
                rels.append(line.split("  ", 1)[1])
    jobs = []
    for rel in rels:
        group = os.path.basename(os.path.dirname(rel))
        trace = os.path.basename(rel)[:-3]
        base = os.path.join(rv_root, "pages", group, trace)
        if not os.path.isfile(os.path.join(rv_root, rel)):
            fail("changed trace %s not found under CBP_TRACES_RV=%s"
                 % (rel, rv_root))
        jobs.append((base + ".pages", base + ".img"))
    bad = 0
    with multiprocessing.Pool(args.jobs) as pool:
        for pages, img, rc, out in pool.imap_unordered(run_pt_gen, jobs):
            tag = os.path.relpath(pages, rv_root)
            last = [ln for ln in out.splitlines()
                    if ln.startswith("pt_gen:")]
            if rc != 0:
                bad += 1
                print("  REJECTED %s: %s" % (tag, out))
            else:
                print("  image %s: %s" % (tag, " | ".join(last)))
    print("pt_gen: %d inputs, %d rejected" % (len(jobs), bad))
    if bad:
        fail("pt_gen rejected %d inputs" % bad)

    # The checksum lists, in the training list's order.
    with open(os.path.join(REPO_ROOT, "perf", "cbp2025_rv.sha256"),
              "w") as f:
        for rel in rels:
            f.write("%s  %s\n" % (sha256_of(os.path.join(rv_root, rel)), rel))
    with open(os.path.join(REPO_ROOT, "perf", "cbp2025_rv_aux.sha256"),
              "w") as f:
        for rel in rels:
            group = os.path.basename(os.path.dirname(rel))
            trace = os.path.basename(rel)[:-3]
            for ext in (".pages", ".img", ".stubs"):
                r = "pages/%s/%s%s" % (group, trace, ext)
                f.write("%s  %s\n" % (sha256_of(os.path.join(rv_root, r)), r))
    print("wrote perf/cbp2025_rv.sha256 and perf/cbp2025_rv_aux.sha256, "
          "%d traces" % len(rels))
    return 0


if __name__ == "__main__":
    sys.exit(main())
