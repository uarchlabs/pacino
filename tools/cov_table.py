#!/usr/bin/env python3
"""
cov_table.py -- BPU coverage summary table emitter.

Parses Verilator coverage .dat files and prints a per-target table.
Run from the repository root.

Usage:
    python3 cov_table.py [--dat-root <path>]
    python3 cov_table.py --diagnose

    --dat-root  Base directory containing per-target coverage.dat files.
                Default: rtl/core/frontend/bpu/coverage
                Expected layout: <dat-root>/<target>/coverage.dat

    --diagnose  Print the first 5 parsed lines from each dat file.
                Use when table shows 0/0 N/A.

File format note:
    Verilator .dat files use SOH (0x01) as field-name prefix and
    STX (0x02) as field-name/value separator.  A coverage line looks
    like (with control chars shown as <SOH> and <STX>):

        C '<SOH>f<STX>rtl/foo.sv<SOH>l<STX>42<SOH>n<STX>3...' <count>

    The source file path is the value of the 'f' field.
"""

import os
import sys

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEFAULT_DAT_ROOT = "rtl/core/frontend/bpu/coverage"

TARGETS = [
    ("history",    ["bp_history.sv"]),
    ("ubtb",       ["ubtb.sv"]),
    ("loop_pred",  ["loop_pred.sv"]),
    ("tage_table", ["tage_table.sv"]),
    ("tage",       ["tage.sv"]),
    ("bpu",        [
        "tage.sv",
        "tage_table.sv",
        "tage_bim.sv",
        "tage_cntrl.sv",
        "bp_history.sv",
        "ubtb.sv",
        "loop_pred.sv",
    ]),
]

THRESHOLD = 90.0

# Field delimiters used by Verilator in .dat files
SOH = "\x01"   # Start Of Header -- precedes field name
STX = "\x02"   # Start Of Text   -- separates field name from value
F_MARKER = SOH + "f" + STX   # prefix for the source-file field


# ---------------------------------------------------------------------------
# Line parser
# ---------------------------------------------------------------------------

def parse_line(raw):
    """
    Parse one stripped C-line from a Verilator .dat file.
    Returns (basename, count) or (None, None) if not a valid coverage point.

    The source file path is extracted from the 'f' field:
        <SOH>f<STX><path><SOH>...
    """
    if not raw.startswith("C "):
        return None, None

    # Count is the last whitespace-separated token
    parts = raw.rsplit(None, 1)
    if len(parts) < 2:
        return None, None
    try:
        count = int(parts[-1])
    except ValueError:
        return None, None

    # Find the 'f' field value
    f_start = raw.find(F_MARKER)
    if f_start < 0:
        return None, None

    path_start = f_start + len(F_MARKER)

    # Value ends at the next SOH or at the closing quote character
    path_end = raw.find(SOH, path_start)
    if path_end < 0:
        # No next field -- take everything up to the last quote before count
        path_end = raw.rfind("'", path_start)
    if path_end < 0 or path_end <= path_start:
        return None, None

    src_path = raw[path_start:path_end]
    basename = os.path.basename(src_path)
    return basename, count


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------

def parse_dat(dat_path, source_basenames):
    """
    Read one Verilator coverage .dat file.
    Returns (covered, total) or (None, None) if the file does not exist.
    """
    if not os.path.isfile(dat_path):
        return None, None

    want    = set(source_basenames)
    total   = 0
    covered = 0

    with open(dat_path, encoding="latin-1") as fh:
        for raw in fh:
            raw = raw.strip()
            basename, count = parse_line(raw)
            if basename is None or basename not in want:
                continue
            total += 1
            if count > 0:
                covered += 1

    return covered, total


# ---------------------------------------------------------------------------
# Diagnose mode
# ---------------------------------------------------------------------------

def diagnose(dat_root):
    for target, sources in TARGETS:
        dat_path = os.path.join(dat_root, target, "coverage.dat")
        print(f"\n=== {target} ===")
        print(f"    path : {dat_path}")
        print(f"    want : {sources}")

        if not os.path.isfile(dat_path):
            print("    FILE MISSING")
            continue

        shown = 0
        with open(dat_path, encoding="latin-1") as fh:
            for raw in fh:
                raw = raw.strip()
                basename, count = parse_line(raw)
                if basename is None:
                    continue
                match = "HIT " if basename in set(sources) else "skip"
                print(f"    [{match}] base={basename!r:30s} count={count}")
                shown += 1
                if shown >= 5:
                    break

        if shown == 0:
            print("    NO PARSEABLE C-LINES FOUND")


# ---------------------------------------------------------------------------
# Table formatter
# ---------------------------------------------------------------------------

def make_table(rows):
    cells = []
    for target, covered, total in rows:
        if covered is None:
            ratio   = "MISSING"
            pct_str = "--"
            flag    = " !"
        elif total == 0:
            ratio   = "0/0"
            pct_str = "N/A"
            flag    = " ?"
        else:
            pct     = 100.0 * covered / total
            ratio   = f"{covered}/{total}"
            pct_str = f"{pct:.1f}%"
            flag    = "" if pct >= THRESHOLD else " <"
        cells.append((target, ratio, pct_str, flag))

    w0 = max(max(len(c[0]) for c in cells), len("Target"))
    w1 = max(max(len(c[1]) for c in cells), len("Covered/Total"))
    w2 = max(max(len(c[2]) for c in cells), len("Coverage"))

    sep = f"+{'-'*(w0+2)}+{'-'*(w1+2)}+{'-'*(w2+2)}+"
    hdr = (f"| {'Target':<{w0}} "
           f"| {'Covered/Total':<{w1}} "
           f"| {'Coverage':<{w2}} |")

    lines = [sep, hdr, sep]
    for target, ratio, pct_str, flag in cells:
        lines.append(
            f"| {target:<{w0}} "
            f"| {ratio:<{w1}} "
            f"| {pct_str:<{w2}} |{flag}"
        )
    lines.append(sep)

    legend = []
    if any(c[3] == " <" for c in cells):
        legend.append("  < below 90% threshold")
    if any(c[3] == " !" for c in cells):
        legend.append("  ! dat file not found -- run the make target first")
    if any(c[3] == " ?" for c in cells):
        legend.append("  ? no matching points -- run --diagnose")
    lines.extend(legend)

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main(argv):
    dat_root      = DEFAULT_DAT_ROOT
    mode_diagnose = False

    i = 1
    while i < len(argv):
        if argv[i] == "--dat-root" and i + 1 < len(argv):
            dat_root = argv[i + 1]
            i += 2
        elif argv[i] == "--diagnose":
            mode_diagnose = True
            i += 1
        elif argv[i] in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            print(f"Unknown argument: {argv[i]}", file=sys.stderr)
            return 1

    if mode_diagnose:
        diagnose(dat_root)
        return 0

    rows = []
    for target, sources in TARGETS:
        dat_path = os.path.join(dat_root, target, "coverage.dat")
        covered, total = parse_dat(dat_path, sources)
        rows.append((target, covered, total))

    print(make_table(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

