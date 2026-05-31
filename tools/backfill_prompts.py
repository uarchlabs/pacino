#!/usr/bin/env python3
"""
backfill_prompts.py -- insert missing Mode: and ## Files Modified
fields into existing prompt files.

Usage:
    # All prompts in default directory
    python3 tools/backfill_prompts.py

    # Explicit file list
    python3 tools/backfill_prompts.py prompts/BP-040.md prompts/BP-041.md

    # Dry run (print what would change, no writes)
    python3 tools/backfill_prompts.py --dry-run

Run from the repo root.

Changes made per file (only when the field is absent):
  1. Insert 'Mode:   [x] automated   [ ] manual' on the line
     immediately before the 'Status:' checkbox line in the
     header block.
  2. Insert '## Files Modified\nNo captured\n' immediately
     before the ':: RESULTS:END ::' marker.

Files that already contain the field are left untouched.
A summary is printed to stdout on completion.
"""

import re
import sys
from pathlib import Path

PROMPTS_DIR   = Path("prompts")
MODE_LINE     = "Mode:   [x] automated   [ ] manual"
FILES_SECTION = "## Files Modified\nNot captured\n"

# Matches the Status: checkbox line (with any checkbox states)
STATUS_RE = re.compile(r'^Status:\s+\[', re.MULTILINE)

# Matches the Mode: line (already present)
MODE_PRESENT_RE = re.compile(r'^Mode:\s+\[', re.MULTILINE)

RESULTS_END = ":: RESULTS:END ::"
FILES_PRESENT = "## Files Modified"


def backfill_file(path, dry_run=False):
    """
    Apply missing backfills to a single file.
    Returns (mode_added, files_added, skipped_reason).
    skipped_reason is None if the file was processed normally.
    """
    try:
        text = path.read_text(encoding='utf-8')
    except Exception as e:
        return False, False, f"read error: {e}"

    if ':: HEADER:START ::' not in text:
        return False, False, "no header markers -- skipping"

    original = text
    mode_added  = False
    files_added = False

    # -- Insert Mode: line before Status: --------------------------------
    if not MODE_PRESENT_RE.search(text):
        m = STATUS_RE.search(text)
        if m:
            insert_at = m.start()
            text = (text[:insert_at] +
                    MODE_LINE + "\n" +
                    text[insert_at:])
            mode_added = True
        else:
            # Status line absent -- append Mode after last Task: block
            pass

    # -- Insert ## Files Modified before :: RESULTS:END :: ---------------
    if FILES_PRESENT not in text:
        idx = text.find(RESULTS_END)
        if idx != -1:
            # Ensure a blank line before the section
            prefix = text[:idx]
            if not prefix.endswith('\n\n'):
                if prefix.endswith('\n'):
                    prefix += '\n'
                else:
                    prefix += '\n\n'
            text = prefix + FILES_SECTION + '\n' + text[idx:]
            files_added = True

    if text != original:
        if not dry_run:
            path.write_text(text, encoding='utf-8')

    return mode_added, files_added, None


def main():
    args     = sys.argv[1:]
    dry_run  = '--dry-run' in args
    args     = [a for a in args if a != '--dry-run']

    if args:
        paths = [Path(a) for a in args]
    else:
        if not PROMPTS_DIR.exists():
            print(f"ERROR: '{PROMPTS_DIR}' not found. "
                  f"Run from the repo root.")
            sys.exit(1)
        paths = sorted(PROMPTS_DIR.glob("*.md"))

    if not paths:
        print("No .md files found.")
        sys.exit(0)

    if dry_run:
        print("-- DRY RUN -- no files will be written\n")

    mode_count  = 0
    files_count = 0
    skip_count  = 0

    for path in paths:
        mode_added, files_added, reason = backfill_file(
            path, dry_run=dry_run)

        if reason:
            print(f"  SKIP  {path.name}: {reason}")
            skip_count += 1
            continue

        changes = []
        if mode_added:
            changes.append("Mode:")
            mode_count += 1
        if files_added:
            changes.append("## Files Modified")
            files_count += 1

        if changes:
            tag = "[dry]" if dry_run else "  OK "
            print(f"{tag}  {path.name}: added {', '.join(changes)}")
        else:
            print(f"  --   {path.name}: nothing to do")

    print(f"\n{'DRY RUN -- ' if dry_run else ''}"
          f"Mode: added to {mode_count} file(s), "
          f"## Files Modified added to {files_count} file(s), "
          f"{skip_count} skipped.")


if __name__ == "__main__":
    main()

