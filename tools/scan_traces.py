#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
"""
scan_traces.py -- characterize the CBP2025 training traces (PERF-001).

Reads every training trace through the CBP trace record format and
writes one CSV row per trace: instruction and branch counts, code
footprint, and the branches a RISC-V code image cannot encode directly
(PF-U1). The record format is the one documented in the CBP2025
repository, tools/cbp2025/lib/trace_reader.h; this reader is pacino's
own and no CBP code is used (PF-1).

Record, little endian:
  PC 8 bytes, class 1 byte
  load or store: effective address 8, size 1, base update 1,
                 and for a store, register offset 1
  branch:        taken 1, and when taken, target 8
  input register count 1, one byte per input register
  output register count 1, one byte per output register
  one value per output register: 8 bytes for an integer register
  (0-31, 64, 65), 16 bytes otherwise (SIMD, 32-63)

Counting follows the CBP2025 simulator, so the counts compare with
reference_results_training_set.csv:
  - instructions are trace records (Instr).
  - the simulator predicts once per record PIECE; a record with
    several output registers is several pieces. NumBr counts the
    conditional branch pieces. cond_br_pieces is that count.
  - the 50Perc columns cover the trailing 1M-record epochs whose sum
    first exceeds half the records (bp.cc output_periodic_info).
    half_instr and half_cond_br_pieces are computed the same way.

Branch reach, RISC-V (unprivileged ISA, B-type and J-type immediates):
  conditional branch  -4096 .. +4094 bytes
  jal                 -1048576 .. +1048574 bytes
A taken conditional branch or a direct jump or call whose traced
displacement is outside that range is counted as far.

The traces are found through the environment variable CBP_TRACES,
default ../cbp_traces relative to the repository root (PF-14). The
training set is CBP_TRACES/training_traces/<group>/<trace>.gz. Each
file is checked against perf/cbp2025_training.sha256 before it is
read. Setup notes: README.md, section Performance analysis.

Usage, from the repository root:
  python3 perf/scan_traces.py              training set -> perf CSV
  python3 perf/scan_traces.py -j 8         8 processes (default: all)
  python3 perf/scan_traces.py --dir tools/cbp2025/sample_traces
                                           any <dir>/<group>/*.gz, not
                                           checksum checked, printed
                                           only unless --out is given
Exit status: 0 when every trace was read and, for the training set,
every count equals the reference results; 1 otherwise.
"""

import argparse
import csv
import hashlib
import multiprocessing
import os
import struct
import sys
import time
import zlib

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
README_REF = "see README.md, section Performance analysis"
SHA_LIST = os.path.join(REPO_ROOT, "perf", "cbp2025_training.sha256")
REF_CSV = os.path.join(REPO_ROOT, "tools", "cbp2025",
                       "reference_results_training_set.csv")
OUT_CSV = os.path.join(REPO_ROOT, "perf", "cbp2025_training_scan.csv")
TRAINING_SUBDIR = "training_traces"

# Instruction classes, sim_common_structs.h InstClass.
C_LOAD = 1
C_STORE = 2
C_COND = 3
C_JMP_DIR = 4
C_JMP_IND = 5
C_UNDEF = 8
C_CALL_DIR = 9
C_CALL_IND = 10
C_RET = 11
BRANCH_CLASSES = frozenset((C_COND, C_JMP_DIR, C_JMP_IND, C_CALL_DIR,
                            C_CALL_IND, C_RET))

# RISC-V reach of a conditional branch and of jal, in bytes.
BR_MIN, BR_MAX = -4096, 4094
JAL_MIN, JAL_MAX = -(1 << 20), (1 << 20) - 2

EPOCH_RECORDS = 1000000         # CBP EPOCH_SIZE_INSTS default
CHUNK_BYTES = 4 << 20           # compressed bytes per read
MAX_RECORD = 8192               # more than any record can occupy
PAGE_SHIFT = 12                 # 4 KB code pages

# Bytes of value per output register: 8 for an integer register
# (0-31, the flag register 64, the zero register 65), 16 otherwise.
VALUE_BYTES = [8 if (r < 32 or r in (64, 65)) else 16
               for r in range(256)]

COLUMNS = [
    "group", "trace", "instructions",
    "cond_br", "cond_br_taken", "cond_br_pieces",
    "jump_direct", "jump_indirect", "call_direct", "call_indirect",
    "returns",
    "static_pcs", "static_cond_br", "static_direct_jmp_call",
    "code_pages_4k", "pc_min", "pc_max", "pc_unaligned_static",
    "multi_target_static",
    "far_cond_taken_dyn", "far_cond_static",
    "far_jal_dyn", "far_jal_static",
    "half_instr", "half_cond_br_pieces",
]


class TraceError(Exception):
    """A trace that cannot be found, checked or read."""


def fail(msg):
    """Stop with a message that names the README section."""
    sys.stderr.write("scan_traces.py: %s\n  (%s)\n" % (msg, README_REF))
    sys.exit(1)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(CHUNK_BYTES)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def branch_pieces(buf, regs_at, nout):
    """Pieces of a branch record: one per output register, at least
    one, plus one for each SIMD output whose upper 8 bytes are not 0
    (trace_reader.h readInstr)."""
    if nout == 0:
        return 1
    pieces = nout
    v = regs_at + nout
    for i in range(nout):
        r = buf[regs_at + i]
        if VALUE_BYTES[r] == 16:
            if buf[v + 8:v + 16] != b"\x00" * 8:
                pieces += 1
        v += VALUE_BYTES[r]
    return pieces


def scan_trace(job):
    """Scan one trace. job = (group, trace, path, sha or None).
    Returns (group, trace, row dict or None, error or None, seconds)."""
    group, trace, path, want_sha = job
    t0 = time.time()
    try:
        if want_sha is not None:
            got = sha256_of(path)
            if got != want_sha:
                raise TraceError("%s: SHA-256 %s does not match the "
                                 "list (%s)" % (path, got, want_sha))
        row = parse_trace(path)
    except (OSError, TraceError, zlib.error) as e:
        return (group, trace, None, str(e), time.time() - t0)
    row["group"] = group
    row["trace"] = trace
    return (group, trace, row, None, time.time() - t0)


def parse_trace(path):
    unpack_q = struct.Struct("<Q").unpack_from
    vb = VALUE_BYTES
    d = zlib.decompressobj(16 + zlib.MAX_WBITS)

    nrec = 0
    n_cond = n_taken = n_cond_pc = 0
    n_jd = n_ji = n_cd = n_ci = n_ret = 0
    far_c = far_j = 0
    pcs = set()
    cond_pcs = set()
    dir_pcs = set()
    far_c_pcs = set()
    far_j_pcs = set()
    first_tgt = {}
    multi = set()
    cond_ep = []                 # conditional pieces per epoch
    ep = -1
    bad_uncond = 0

    with open(path, "rb") as f:
        buf = b""
        pos = 0
        eof = False
        while True:
            # <= so that the parse loop below always has a record to
            # take: it parses while pos < n - MAX_RECORD.
            if not eof and len(buf) - pos <= MAX_RECORD:
                chunk = f.read(CHUNK_BYTES)
                if chunk:
                    buf = buf[pos:] + d.decompress(chunk)
                else:
                    buf = buf[pos:] + d.flush()
                    eof = True
                pos = 0
                continue
            n = len(buf)
            if pos >= n:
                break
            limit = n if eof else n - MAX_RECORD
            try:
                while pos < limit:
                    pc = unpack_q(buf, pos)[0]
                    t = buf[pos + 8]
                    p = pos + 9
                    if t == C_LOAD:
                        p += 10
                    elif t == C_STORE:
                        p += 11
                    elif t in BRANCH_CLASSES:
                        tk = buf[p]
                        p += 1
                        if tk:
                            tgt = unpack_q(buf, p)[0]
                            p += 8
                        ni = buf[p]
                        no = buf[p + 1 + ni]
                        regs_at = p + 2 + ni
                        if t == C_COND:
                            pieces = 1
                            if no:
                                pieces = branch_pieces(buf, regs_at, no)
                            n_cond += 1
                            n_cond_pc += pieces
                            e = nrec // EPOCH_RECORDS
                            while ep < e:
                                cond_ep.append(0)
                                ep += 1
                            cond_ep[e] += pieces
                            cond_pcs.add(pc)
                            if tk:
                                n_taken += 1
                                off = tgt - pc
                                if off < BR_MIN or off > BR_MAX:
                                    far_c += 1
                                    far_c_pcs.add(pc)
                                ft = first_tgt.get(pc)
                                if ft is None:
                                    first_tgt[pc] = tgt
                                elif ft != tgt:
                                    multi.add(pc)
                        else:
                            if not tk:
                                bad_uncond += 1
                                tgt = pc + 4
                            if t == C_JMP_DIR or t == C_CALL_DIR:
                                if t == C_JMP_DIR:
                                    n_jd += 1
                                else:
                                    n_cd += 1
                                dir_pcs.add(pc)
                                off = tgt - pc
                                if off < JAL_MIN or off > JAL_MAX:
                                    far_j += 1
                                    far_j_pcs.add(pc)
                                ft = first_tgt.get(pc)
                                if ft is None:
                                    first_tgt[pc] = tgt
                                elif ft != tgt:
                                    multi.add(pc)
                            elif t == C_JMP_IND:
                                n_ji += 1
                            elif t == C_CALL_IND:
                                n_ci += 1
                            else:
                                n_ret += 1
                    elif t == C_UNDEF or t > C_RET:
                        raise TraceError("%s: record %d has class %d"
                                         % (path, nrec, t))
                    ni = buf[p]
                    p += 1 + ni
                    no = buf[p]
                    p += 1
                    if no == 1:
                        p += 1 + vb[buf[p]]
                    elif no:
                        for r in buf[p:p + no]:
                            p += vb[r]
                        p += no
                    pcs.add(pc)
                    nrec += 1
                    pos = p
            except IndexError:
                raise TraceError("%s: truncated record %d" % (path, nrec))
            if eof and pos > n:
                raise TraceError("%s: truncated record %d" % (path, nrec))
            if eof and pos >= n:
                break
        if not d.eof:
            raise TraceError("%s: gzip stream ends early" % path)
    if bad_uncond:
        raise TraceError("%s: %d unconditional branches not taken"
                         % (path, bad_uncond))

    # 50Perc window: walk back from the last epoch until the summed
    # records exceed half the total (integer half, as bp.cc).
    n_ep = (nrec + EPOCH_RECORDS - 1) // EPOCH_RECORDS
    while len(cond_ep) < n_ep:
        cond_ep.append(0)
    half_target = nrec // 2
    h_instr = h_cond = 0
    for e in range(n_ep - 1, -1, -1):
        h_instr += min(EPOCH_RECORDS, nrec - e * EPOCH_RECORDS)
        h_cond += cond_ep[e]
        if h_instr > half_target:
            break

    return {
        "instructions": nrec,
        "cond_br": n_cond,
        "cond_br_taken": n_taken,
        "cond_br_pieces": n_cond_pc,
        "jump_direct": n_jd,
        "jump_indirect": n_ji,
        "call_direct": n_cd,
        "call_indirect": n_ci,
        "returns": n_ret,
        "static_pcs": len(pcs),
        "static_cond_br": len(cond_pcs),
        "static_direct_jmp_call": len(dir_pcs),
        "code_pages_4k": len({x >> PAGE_SHIFT for x in pcs}),
        "pc_min": "0x%x" % min(pcs) if pcs else "",
        "pc_max": "0x%x" % max(pcs) if pcs else "",
        "pc_unaligned_static": sum(1 for x in pcs if x & 3),
        "multi_target_static": len(multi),
        "far_cond_taken_dyn": far_c,
        "far_cond_static": len(far_c_pcs),
        "far_jal_dyn": far_j,
        "far_jal_static": len(far_j_pcs),
        "half_instr": h_instr,
        "half_cond_br_pieces": h_cond,
    }


def trace_key(path):
    """Sort key: group, then trace name in natural number order."""
    group = os.path.basename(os.path.dirname(path))
    name = os.path.basename(path)[:-3]
    parts = name.split("_")
    nums = tuple(int(x) if x.isdigit() else x for x in parts)
    return (group, nums)


def training_jobs():
    root = os.environ.get("CBP_TRACES",
                          os.path.join(REPO_ROOT, "..", "cbp_traces"))
    root = os.path.abspath(root)
    if not os.path.isdir(root):
        fail("trace directory %s not found; set CBP_TRACES" % root)
    if not os.path.isfile(SHA_LIST):
        fail("checksum list %s not found" % SHA_LIST)
    jobs = []
    with open(SHA_LIST) as f:
        for ln, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("  ", 1)
            if len(parts) != 2 or len(parts[0]) != 64:
                fail("%s line %d is not sha256sum format" % (SHA_LIST, ln))
            sha, rel = parts
            path = os.path.join(root, rel)
            if not os.path.isfile(path):
                fail("trace %s listed in %s not found under CBP_TRACES=%s"
                     % (rel, os.path.basename(SHA_LIST), root))
            group = os.path.basename(os.path.dirname(rel))
            trace = os.path.basename(rel)[:-3]
            jobs.append((group, trace, path, sha))
    if not jobs:
        fail("checksum list %s is empty" % SHA_LIST)
    return jobs


def dir_jobs(top):
    if not os.path.isdir(top):
        fail("directory %s not found" % top)
    jobs = []
    for group in sorted(os.listdir(top)):
        gdir = os.path.join(top, group)
        if not os.path.isdir(gdir):
            continue
        for name in sorted(os.listdir(gdir)):
            if name.endswith(".gz"):
                jobs.append((group, name[:-3], os.path.join(gdir, name),
                             None))
    if not jobs:
        fail("no <group>/*.gz files under %s" % top)
    return jobs


def compare_reference(rows):
    """Compare against the reference results. Returns mismatch lines."""
    ref = {}
    with open(REF_CSV, newline="") as f:
        for r in csv.DictReader(f):
            ref[(r["Workload"], r["Run"])] = r
    bad = []
    pairs = (("instructions", "Instr"),
             ("cond_br_pieces", "NumBr"),
             ("half_instr", "50PercInstr"),
             ("half_cond_br_pieces", "50PercNumBr"))
    for row in rows:
        r = ref.pop((row["group"], row["trace"]), None)
        if r is None:
            bad.append("%s/%s: not in the reference results"
                       % (row["group"], row["trace"]))
            continue
        for mine, theirs in pairs:
            if int(r[theirs]) != row[mine]:
                bad.append("%s/%s: %s %d, reference %s %s"
                           % (row["group"], row["trace"], mine, row[mine],
                              theirs, r[theirs]))
    for (g, t) in sorted(ref):
        bad.append("%s/%s: in the reference results, not scanned" % (g, t))
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count(),
                    help="processes (default: CPU count)")
    ap.add_argument("--dir", help="scan <dir>/<group>/*.gz instead of "
                    "the training set, unchecked, no reference compare")
    ap.add_argument("--out", help="CSV to write (default for the "
                    "training set: perf/cbp2025_training_scan.csv)")
    args = ap.parse_args()

    if args.dir:
        jobs = dir_jobs(args.dir)
        out = args.out
    else:
        jobs = training_jobs()
        out = args.out or OUT_CSV

    nproc = max(1, min(args.jobs, len(jobs)))
    # Largest first, so the longest trace does not start last.
    order = sorted(jobs, key=lambda j: -os.path.getsize(j[2]))
    print("scan_traces.py: %d traces, %d processes" % (len(jobs), nproc))
    t0 = time.time()
    rows, errors = [], []
    with multiprocessing.Pool(nproc) as pool:
        for g, t, row, err, sec in pool.imap_unordered(scan_trace, order):
            if err:
                errors.append(err)
                print("  FAIL %s/%s: %s" % (g, t, err))
            else:
                rows.append(row)
                print("  done %s/%s  %d records  %.1f s"
                      % (g, t, row["instructions"], sec))
            sys.stdout.flush()
    wall = time.time() - t0
    rows.sort(key=lambda r: trace_key(
        os.path.join(r["group"], r["trace"] + ".gz")))

    if args.dir and not out:
        w = csv.writer(sys.stdout, lineterminator="\n")
        w.writerow(COLUMNS)
        for r in rows:
            w.writerow([r[c] for c in COLUMNS])
    if out:
        with open(out, "w", newline="") as f:
            w = csv.writer(f, lineterminator="\n")
            w.writerow(COLUMNS)
            for r in rows:
                w.writerow([r[c] for c in COLUMNS])
        print("wrote %s, %d rows" % (out, len(rows)))

    status = 0
    if errors:
        sys.stderr.write("scan_traces.py: %d traces failed (%s)\n"
                         % (len(errors), README_REF))
        status = 1
    if not args.dir:
        bad = compare_reference(rows)
        if bad:
            print("reference check: %d mismatches" % len(bad))
            for b in bad:
                print("  " + b)
            status = 1
        else:
            print("reference check: %d traces, Instr, NumBr, 50PercInstr "
                  "and 50PercNumBr all equal" % len(rows))
    print("run time %.1f s, %d processes" % (wall, nproc))
    return status


if __name__ == "__main__":
    sys.exit(main())
