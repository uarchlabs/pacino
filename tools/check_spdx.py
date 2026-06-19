#!/usr/bin/env python3
"""
check_spdx.py - Report files missing SPDX-License-Identifier marker.

Usage:
    python3 check_spdx.py [root_dir] [options]

Examples:
    python3 check_spdx.py .
    python3 check_spdx.py ~/projects/pacino --exclude .git build _build
    python3 check_spdx.py . --ext .py .v .sv .cpp .h .md
"""

import os
import sys
import argparse

# Default file extensions to check
DEFAULT_EXTENSIONS = {
    # RTL / Hardware
    ".v", ".sv", ".svh", ".vh",
    # C / C++
    ".c", ".cpp", ".cc", ".cxx", ".h", ".hpp",
    # Python / Scripts
    ".py", ".sh",
    # Markdown / Docs (functional)
    ".md",
    # Other
    ".yaml", ".yml", ".json", ".toml",
}

# Directories to always skip
DEFAULT_SKIP_DIRS = {
    ".git", ".github", "__pycache__", "node_modules",
    "build", "_build", "dist", ".tox", ".venv", "venv",
    "tools", "versions"
}

SPDX_MARKER = "SPDX-License-Identifier"


def check_file(filepath: str, num_lines: int = 5) -> bool:
    """Return True if SPDX marker found in first num_lines of file."""
    try:
        with open(filepath, "r", errors="replace") as f:
            for i, line in enumerate(f):
                if i >= num_lines:
                    break
                if SPDX_MARKER in line:
                    return True
    except (OSError, PermissionError):
        pass
    return False


def scan(root: str, extensions: set, skip_dirs: set) -> list[str]:
    """Walk tree and return list of files missing SPDX marker."""
    missing = []
    for dirpath, dirnames, filenames in os.walk(root):
        # Prune skipped directories in-place
        dirnames[:] = [
            d for d in dirnames
            if d not in skip_dirs and not d.startswith(".")
        ]
        for fname in sorted(filenames):
            _, ext = os.path.splitext(fname)
            if ext.lower() not in extensions:
                continue
            full = os.path.join(dirpath, fname)
            rel  = os.path.relpath(full, root)
            if not check_file(full):
                missing.append(rel)
    return missing


def main():
    parser = argparse.ArgumentParser(
        description="Report files missing SPDX-License-Identifier."
    )
    parser.add_argument(
        "root",
        nargs="?",
        default=".",
        help="Root directory to scan (default: current directory)",
    )
    parser.add_argument(
        "--ext",
        nargs="+",
        metavar="EXT",
        help="Extensions to check (e.g. .py .v .sv .md). Overrides defaults.",
    )
    parser.add_argument(
        "--exclude",
        nargs="+",
        metavar="DIR",
        default=[],
        help="Additional directory names to skip.",
    )
    parser.add_argument(
        "--lines",
        type=int,
        default=5,
        metavar="N",
        help="Number of lines from top of file to search (default: 5)",
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="Print only the count, not individual file paths.",
    )
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print(f"Error: '{root}' is not a directory.", file=sys.stderr)
        sys.exit(1)

    extensions = set(args.ext) if args.ext else DEFAULT_EXTENSIONS
    skip_dirs  = DEFAULT_SKIP_DIRS | set(args.exclude)

    missing = scan(root, extensions, skip_dirs)

    if not missing:
        print("All checked files have an SPDX-License-Identifier marker.")
        sys.exit(0)

    if args.summary:
        print(f"{len(missing)} file(s) missing SPDX-License-Identifier")
    else:
        print(f"Files missing SPDX-License-Identifier ({len(missing)}):\n")
        for path in missing:
            print(f"  {path}")
        print(f"\nTotal: {len(missing)} file(s)")

    sys.exit(1)  # Non-zero exit useful for CI integration


if __name__ == "__main__":
    main()

