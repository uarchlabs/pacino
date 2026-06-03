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
  2. Insert '## Files Modified\nNot captured\n' immediately
     before the ':: RESULTS:END ::' marker.
  3. Insert '| PA session  | NNN | |' immediately after the
     '| Resume sha | ... |' row, inside the header block. Files
     whose header has no 'Resume sha' row are FLAGGED (the PA row
     is not inserted, since there is no anchor) and listed at the
     end so they can be fixed manually.
  4. Rename any heading line beginning with '# Overview of task'
     to '# Task Overview'.

Files that already contain a given fix are left untouched for that
fix (all operations are idempotent).
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

HEADER_START = ":: HEADER:START ::"
HEADER_END   = ":: HEADER:END ::"

# Row inserted after the Resume sha row (placeholder value 'NNN').
PA_ROW = "| PA session  | NNN | |"

# Matches an existing PA session row (so we don't add a duplicate).
PA_PRESENT_RE = re.compile(
    r'^[ \t]*\|\s*pa[ _]session\s*\|', re.MULTILINE | re.IGNORECASE)

# Matches the Resume sha row; captures leading indentation. '[^\n]*'
# consumes the rest of the line so m.end() lands just before the
# newline -- the insertion point for the PA row.
RESUME_ROW_RE = re.compile(
    r'^(?P<indent>[ \t]*)\|\s*resume[ _]sha\s*\|[^\n]*',
    re.MULTILINE | re.IGNORECASE)

# Matches a heading line that begins with '# Overview of task'. The
# whole line is replaced with the canonical '# Task Overview'.
OVERVIEW_RE = re.compile(
    r'^#[ \t]+Overview of task[^\n]*$', re.MULTILINE | re.IGNORECASE)


def backfill_file(path, dry_run=False):
    """
    Apply missing backfills to a single file.
    Returns a result dict with keys:
        mode_added, files_added, pa_added, overview_renamed (bool),
        resume_missing (bool -- flagged, PA row not inserted),
        skip (str or None -- reason the file was skipped entirely).
    """
    def result(**kw):
        base = {"mode_added": False, "files_added": False,
                "pa_added": False, "overview_renamed": False,
                "resume_missing": False, "skip": None}
        base.update(kw)
        return base

    try:
        text = path.read_text(encoding='utf-8')
    except Exception as e:
        return result(skip=f"read error: {e}")

    if HEADER_START not in text:
        return result(skip="no header markers -- skipping")

    original = text
    res = result()

    # -- Insert Mode: line before Status: --------------------------------
    if not MODE_PRESENT_RE.search(text):
        m = STATUS_RE.search(text)
        if m:
            insert_at = m.start()
            text = (text[:insert_at] +
                    MODE_LINE + "\n" +
                    text[insert_at:])
            res["mode_added"] = True
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
            res["files_added"] = True

    # -- Rename '# Overview of task' -> '# Task Overview' (file-wide) -----
    text, n_overview = OVERVIEW_RE.subn('# Task Overview', text)
    if n_overview:
        res["overview_renamed"] = True

    # -- Insert PA session row after Resume sha (header block only) -------
    hs = text.find(HEADER_START)
    he = text.find(HEADER_END)
    if hs != -1 and he != -1 and he > hs:
        header_region = text[hs:he]
        if not PA_PRESENT_RE.search(header_region):
            m = RESUME_ROW_RE.search(header_region)
            if m:
                indent     = m.group('indent')
                abs_insert = hs + m.end()   # just before the line's \n
                text = (text[:abs_insert] +
                        "\n" + indent + PA_ROW +
                        text[abs_insert:])
                res["pa_added"] = True
            else:
                # No Resume sha row to anchor to -- flag for manual fix.
                res["resume_missing"] = True

    if text != original and not dry_run:
        path.write_text(text, encoding='utf-8')

    return res


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

    mode_count     = 0
    files_count    = 0
    pa_count       = 0
    overview_count = 0
    skip_count     = 0
    flagged        = []

    for path in paths:
        r = backfill_file(path, dry_run=dry_run)

        if r["skip"]:
            print(f"  SKIP  {path.name}: {r['skip']}")
            skip_count += 1
            continue

        changes = []
        if r["mode_added"]:
            changes.append("Mode:")
            mode_count += 1
        if r["files_added"]:
            changes.append("## Files Modified")
            files_count += 1
        if r["pa_added"]:
            changes.append("PA session row")
            pa_count += 1
        if r["overview_renamed"]:
            changes.append("# Task Overview rename")
            overview_count += 1

        if changes:
            tag = "[dry]" if dry_run else "  OK "
            print(f"{tag}  {path.name}: {', '.join(changes)}")

        if r["resume_missing"]:
            flagged.append(path.name)
            print(f"  FLAG  {path.name}: no 'Resume sha' row in header "
                  f"block -- PA session row NOT added (fix manually)")

        if not changes and not r["resume_missing"]:
            print(f"  --   {path.name}: nothing to do")

    print(f"\n{'DRY RUN -- ' if dry_run else ''}"
          f"Mode: {mode_count}, "
          f"## Files Modified: {files_count}, "
          f"PA session: {pa_count}, "
          f"# Task Overview renames: {overview_count}, "
          f"{skip_count} skipped, "
          f"{len(flagged)} flagged.")

    if flagged:
        print("\nFlagged -- no 'Resume sha' row in header, so the PA "
              "session row could not be anchored. Add it manually:")
        for name in flagged:
            print(f"  - {name}")


if __name__ == "__main__":
    main()

