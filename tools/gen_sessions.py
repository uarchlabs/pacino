#!/usr/bin/env python3
"""
gen_sessions.py — parse prompts/*.md and emit docs/sessions.json

Run from the repo root:
    python3 tools/gen_sessions.py

Warnings are printed to stderr. sessions.json is written to docs/.
"""

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# ── Configuration ─────────────────────────────────────────────────────────────

PROMPTS_DIR = Path("prompts")
OUTPUT_FILE  = Path("docs/sessions.json")

KNOWN_CATEGORIES = {"BP", "COMP", "DECODE", "INFRA", "TB", "TOOLS"}

TASK_TYPES  = ["experiment", "implementation", "debug", "cleanup", "testbench", "verification"]
STATUS_OPTS = ["in-progress", "complete", "abandoned"]

# ── Warning codes ─────────────────────────────────────────────────────────────

class W:
    NO_MARKERS          = "W001"   # No :: HEADER:START :: found — markdown fallback
    DUPLICATE_PA        = "W002"   # Duplicate ## Claude.ai Assessment — blocks merged
    EMPTY_ASSESSMENT    = "W003"   # ## My Assessment is empty or TBD
    ABANDONED_WITH_PASS = "W004"   # status=abandoned but PASS counts found in results
    MISSING_DISCUSSION  = "W005"   # No :: DISCUSSION:START/END :: section
    MISSING_RESULTS     = "W006"   # No :: RESULTS:START/END :: section
    MISSING_PROMPT      = "W007"   # No :: PROMPT:START/END :: section
    ID_MISMATCH         = "W008"   # Task ID in header != filename stem
    ORPHAN_SUBSESSION   = "W009"   # Sub-session (BP-008a-1) with no parent in dir
    MISSING_FIELD       = "W010"   # Expected header field absent or empty
    VOICES_MERGED       = "W011"   # Discussion voices could not be cleanly separated
    UNKNOWN_CATEGORY    = "W012"   # Task ID prefix not in KNOWN_CATEGORIES
    BAD_TASK_ID         = "W013"   # Task ID doesn't match expected pattern

# ── Task ID parsing ───────────────────────────────────────────────────────────

# Matches: BP-040, BP-008a, BP-008a-1, DECODE-001
TASK_ID_RE = re.compile(r'^([A-Z]+)-(\d+)([a-z]?)(-\d+)?$')

def parse_task_id(task_id):
    """
    Return (category, number, suffix_letter, suffix_number, cluster_key) or None.
    cluster_key groups sub-sessions: BP-008a, BP-008a-1, BP-008b → BP-008
    """
    m = TASK_ID_RE.match(task_id.strip().upper())
    if not m:
        return None
    cat  = m.group(1)
    num  = m.group(2)
    sl   = m.group(3).lower() if m.group(3) else ""
    sn   = m.group(4) or ""
    return cat, num, sl, sn, f"{cat}-{num}"

# ── Text utilities ────────────────────────────────────────────────────────────

def extract_between(text, start_marker, end_marker):
    """Return text between markers, stripped. None if start not found."""
    s = text.find(start_marker)
    if s == -1:
        return None
    s += len(start_marker)
    e = text.find(end_marker, s)
    return (text[s:e] if e != -1 else text[s:]).strip()

def is_empty_or_tbd(text):
    if not text:
        return True
    t = re.sub(r'[-\s]', '', text.strip().upper())
    return t in ('', 'TBD', 'NA', 'NONE', 'ASNEEDEDDDOCUMENTHERE')

def has_pass_count(text):
    """True if text contains patterns like '76 PASS', 'PASS=24', 'ALL TESTS PASSED'."""
    return bool(re.search(
        r'\b\d+\s+PASS\b|\bPASS\s*=\s*\d+|\bALL\s+TESTS\s+PASSED\b',
        text, re.IGNORECASE
    ))

# ── Header parsing ────────────────────────────────────────────────────────────

# Normalize header field names to canonical keys
FIELD_ALIASES = {
    'task_id':    'task_id',
    'task id':    'task_id',
    'date':       'date',
    'module':     'module',
    'run_time':   'run_time',
    'run time':   'run_time',
    'ctx_%':      'ctx_pct',
    'ctx %':      'ctx_pct',
    'ctx':        'ctx_pct',
    'model':      'model',
    'resume_sha': 'resume_sha',
    'resume sha': 'resume_sha',
}

def parse_header_table(header_text):
    """
    Parse the markdown table inside the header section.
    Handles multi-row field values (continuation rows have empty first cell).
    Returns dict of canonical_key -> value_string.
    """
    fields = {}
    last_key = None

    for line in header_text.splitlines():
        line = line.strip()
        if not line.startswith('|'):
            continue
        # Skip separator rows
        if re.match(r'\|[-| ]+\|', line):
            continue
        parts = [p.strip() for p in line.strip('|').split('|')]
        if len(parts) < 2:
            continue

        raw_key = parts[0].strip()
        raw_val = parts[1].strip()

        if raw_key.lower() == 'field':
            continue  # Table header row

        if raw_key:
            # New field row
            canonical = FIELD_ALIASES.get(raw_key.lower().replace('_', ' '),
                         FIELD_ALIASES.get(raw_key.lower(), raw_key.lower()))
            if raw_val:
                fields[canonical] = raw_val
                last_key = canonical
        elif not raw_key and last_key and raw_val:
            # Continuation row (empty first cell) — append to previous field
            fields[last_key] = fields[last_key].rstrip(',').strip() + ', ' + raw_val

    return fields

def parse_checkboxes(text, options):
    """Return list of option names where [x] is found before the option text."""
    checked = []
    for opt in options:
        if re.search(r'\[x\]\s+' + re.escape(opt), text, re.IGNORECASE):
            checked.append(opt)
    return checked

def parse_ctx_pct(raw):
    """Extract integer percentage from strings like '23%', '23', '75%'."""
    if not raw:
        return None
    m = re.search(r'(\d+)', raw)
    return int(m.group(1)) if m else None

# ── Discussion voice splitting ────────────────────────────────────────────────

# Headings we recognise as voice delimiters
IA_HEADINGS  = {"claude.code console output", "claude code console output"}
MY_HEADINGS  = {"my assessment"}
PA_HEADINGS  = {"claude.ai assessment", "claude ai assessment"}

# Headings that belong to the administrative tail — stop collecting voice content
TAIL_HEADINGS = {"follow-on actions", "follow on actions", "claude.md updates",
                 "other planning file updates", "other notes"}

def split_discussion_voices(discussion_text):
    """
    Split discussion section into three voice blocks.
    Returns (ia_output, my_assessment, pa_assessment, warnings_list).
    warnings_list items are (code, message) tuples.
    """
    warnings = []
    heading_re = re.compile(r'^##\s+(.+)$', re.MULTILINE)
    headings   = list(heading_re.finditer(discussion_text))

    if not headings:
        return None, None, None, []

    # Build ordered list of (heading_text, content)
    blocks = []
    for i, m in enumerate(headings):
        heading = m.group(1).strip()
        start   = m.end()
        end     = headings[i + 1].start() if i + 1 < len(headings) else len(discussion_text)
        content = discussion_text[start:end].strip()
        blocks.append((heading, content))

    ia_parts = []
    my_parts = []
    pa_parts = []
    pa_count = 0

    for heading, content in blocks:
        h = heading.lower()
        if h in IA_HEADINGS:
            ia_parts.append(content)
        elif h in MY_HEADINGS:
            my_parts.append(content)
        elif h in PA_HEADINGS:
            pa_count += 1
            if pa_count > 1:
                warnings.append((W.DUPLICATE_PA,
                    f"Duplicate '## {heading}' heading — blocks merged. "
                    f"Review and consolidate manually."))
            pa_parts.append(content)
        elif h in TAIL_HEADINGS:
            pass  # administrative tail, skip
        # Unknown headings are silently ignored

    # Merge multi-part blocks
    ia = "\n\n".join(ia_parts) if ia_parts else None
    my = "\n\n".join(my_parts) if my_parts else None
    pa = "\n\n---\n\n".join(pa_parts) if pa_parts else None

    # Heuristic: if My Assessment is very long, it may contain embedded PA text
    if my and len(my) > 2500:
        warnings.append((W.VOICES_MERGED,
            "## My Assessment is unusually long (>2500 chars) — may contain "
            "interleaved PA voice. Review and split manually."))

    return ia, my, pa, warnings

# ── Per-file parser ───────────────────────────────────────────────────────────

def parse_session_file(path):
    """
    Parse a single session .md file.
    Returns (session_dict, warnings_list).
    warnings_list items are dicts with keys: code, file, msg.
    """
    text     = path.read_text(encoding='utf-8')
    filename = path.stem  # e.g. "BP-040"
    file_str = str(path)
    warnings = []

    def warn(code, msg):
        warnings.append({"code": code, "file": file_str, "msg": msg})

    session = {
        "filename":       filename,
        "path":           file_str,
        "has_markers":    False,
        "id":             filename,
        "category":       None,
        "cluster":        None,
        "date":           None,
        "modules":        [],
        "run_time":       None,
        "ctx_pct":        None,
        "model":          None,
        "resume_sha":     None,
        "task_types":     [],
        "status":         None,
        "overview":       None,
        "ia_output":      None,
        "my_assessment":  None,
        "pa_assessment":  None,
        "discussion_raw": None,
        "prompt_raw":     None,
        "results_raw":    None,
        "warnings":       [],
    }

    # ── Marker check ─────────────────────────────────────────────────────────
    has_markers = ':: HEADER:START ::' in text
    session['has_markers'] = has_markers

    if not has_markers:
        warn(W.NO_MARKERS,
             "No ':: HEADER:START ::' marker found — rendering as raw markdown. "
             "Add markers to enable structured parsing.")
        # Best-effort: derive category from filename
        parsed = parse_task_id(filename)
        if parsed:
            cat, num, sl, sn, cluster = parsed
            session['category'] = cat
            session['cluster']  = cluster
            if cat not in KNOWN_CATEGORIES:
                warn(W.UNKNOWN_CATEGORY, f"Category '{cat}' not in {sorted(KNOWN_CATEGORIES)}")
        else:
            warn(W.BAD_TASK_ID, f"Filename '{filename}' doesn't match pattern e.g. BP-040")
        session['discussion_raw'] = text
        session['warnings'] = warnings
        return session, warnings

    # ── Header ───────────────────────────────────────────────────────────────
    header_text = extract_between(text, ':: HEADER:START ::', ':: HEADER:END ::')
    if not header_text:
        warn(W.MISSING_FIELD, "Header markers found but header content is empty")
    else:
        fields = parse_header_table(header_text)

        # Task ID
        task_id = fields.get('task_id', filename).strip()
        session['id'] = task_id

        if task_id.upper() != filename.upper():
            warn(W.ID_MISMATCH,
                 f"Task ID '{task_id}' in header doesn't match filename '{filename}' — "
                 f"update one to match the other.")

        parsed = parse_task_id(task_id)
        if parsed:
            cat, num, sl, sn, cluster = parsed
            session['category'] = cat
            session['cluster']  = cluster
            if cat not in KNOWN_CATEGORIES:
                warn(W.UNKNOWN_CATEGORY,
                     f"Category '{cat}' not in known set {sorted(KNOWN_CATEGORIES)}. "
                     f"Add it to KNOWN_CATEGORIES in gen_sessions.py if intentional.")
        else:
            warn(W.BAD_TASK_ID,
                 f"Task ID '{task_id}' doesn't match expected pattern (e.g. BP-040, BP-008a-1).")

        # Date
        session['date'] = fields.get('date')

        # Modules — multi-row already merged by parse_header_table
        modules_raw = fields.get('module', '')
        session['modules'] = [
            m.strip() for m in re.split(r',\s*', modules_raw)
            if m.strip() and not re.match(r'^[\|\s]+$', m)
        ]

        # Numeric / string fields
        session['run_time']   = fields.get('run_time')
        session['ctx_pct']    = parse_ctx_pct(fields.get('ctx_pct'))
        session['model']      = fields.get('model')
        session['resume_sha'] = fields.get('resume_sha')

        # Required field warnings
        for req in ['task_id', 'date', 'model']:
            if not fields.get(req):
                warn(W.MISSING_FIELD, f"Required header field '{req}' is absent or empty.")

        # Checkboxes
        session['task_types'] = parse_checkboxes(header_text, TASK_TYPES)
        statuses = parse_checkboxes(header_text, STATUS_OPTS)
        session['status'] = statuses[0] if statuses else 'unknown'

        # Overview — content between HEADER:END and DISCUSSION:START
        overview_raw = extract_between(text, ':: HEADER:END ::', ':: DISCUSSION:START ::')
        if overview_raw:
            # Strip section dividers and the "# Overview of task" heading
            ov = re.sub(r'^=+$', '', overview_raw, flags=re.MULTILINE)
            ov = re.sub(r'^#+\s+Overview of task\s*$', '', ov, flags=re.MULTILINE)
            ov = ov.strip()
            session['overview'] = ov if ov else None

    # ── Discussion ────────────────────────────────────────────────────────────
    discussion_text = extract_between(text, ':: DISCUSSION:START ::', ':: DISCUSSION:END ::')
    if discussion_text is None:
        warn(W.MISSING_DISCUSSION, "No ':: DISCUSSION:START/END ::' section found.")
    else:
        session['discussion_raw'] = discussion_text
        ia, my, pa, voice_warns = split_discussion_voices(discussion_text)
        session['ia_output']     = ia
        session['my_assessment'] = my
        session['pa_assessment'] = pa

        for wcode, wmsg in voice_warns:
            warn(wcode, wmsg)

        if is_empty_or_tbd(my):
            warn(W.EMPTY_ASSESSMENT,
                 "## My Assessment is empty or TBD — add assessment before publishing.")
            session['my_assessment'] = None

    # ── Abandoned + PASS inconsistency ────────────────────────────────────────
    if session.get('status') == 'abandoned':
        results_text = extract_between(text, ':: RESULTS:START ::', ':: RESULTS:END ::') or ''
        disc_text    = discussion_text or ''
        if has_pass_count(results_text) or has_pass_count(disc_text):
            warn(W.ABANDONED_WITH_PASS,
                 "Status is 'abandoned' but PASS counts detected in results or discussion. "
                 "Is the status correct? Review and update.")

    # ── Prompt ────────────────────────────────────────────────────────────────
    prompt_text = extract_between(text, ':: PROMPT:START ::', ':: PROMPT:END ::')
    if prompt_text is None:
        warn(W.MISSING_PROMPT, "No ':: PROMPT:START/END ::' section found.")
    else:
        session['prompt_raw'] = prompt_text

    # ── Results ───────────────────────────────────────────────────────────────
    results_text = extract_between(text, ':: RESULTS:START ::', ':: RESULTS:END ::')
    if results_text is None:
        warn(W.MISSING_RESULTS, "No ':: RESULTS:START/END ::' section found.")
    else:
        session['results_raw'] = results_text

    session['warnings'] = warnings
    return session, warnings

# ── Cross-file validation ─────────────────────────────────────────────────────

def validate_clusters(sessions):
    """
    Warn about sub-sessions (BP-008a-1) whose parent (BP-008) doesn't exist.
    """
    all_ids   = {s['id'].upper() for s in sessions}
    warnings  = []

    for s in sessions:
        parsed = parse_task_id(s['id'])
        if not parsed:
            continue
        cat, num, sl, sn, cluster = parsed
        is_sub = bool(sl) or bool(sn)
        if is_sub:
            parent_id = f"{cat}-{num}"
            if parent_id.upper() not in all_ids:
                warnings.append({
                    "code": W.ORPHAN_SUBSESSION,
                    "file": s['path'],
                    "msg":  (f"Sub-session '{s['id']}' has no parent '{parent_id}' "
                             f"in {PROMPTS_DIR}/. If the parent file was renamed, "
                             f"update the Task ID or add the parent file."),
                })
    return warnings

# ── Sort key ──────────────────────────────────────────────────────────────────

def sort_key(session):
    parsed = parse_task_id(session.get('id', ''))
    if not parsed:
        return ('ZZZ', 9999, '', '')
    cat, num, sl, sn, _ = parsed
    return (cat, int(num), sl, sn)

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    if not PROMPTS_DIR.exists():
        print(f"ERROR: '{PROMPTS_DIR}' not found. Run from the repo root.", file=sys.stderr)
        sys.exit(1)

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)

    md_files = sorted(PROMPTS_DIR.glob("*.md"))
    if not md_files:
        print(f"WARNING: No .md files found in '{PROMPTS_DIR}'.", file=sys.stderr)

    sessions     = []
    all_warnings = []

    for path in md_files:
        session, file_warns = parse_session_file(path)
        sessions.append(session)
        all_warnings.extend(file_warns)

    all_warnings.extend(validate_clusters(sessions))
    sessions.sort(key=sort_key)

    # ── Print warnings ────────────────────────────────────────────────────────
    if all_warnings:
        print(f"\n{'='*64}", file=sys.stderr)
        print(f"  gen_sessions.py — {len(all_warnings)} warning(s)", file=sys.stderr)
        print(f"{'='*64}", file=sys.stderr)
        by_file = {}
        for w in all_warnings:
            by_file.setdefault(Path(w['file']).name, []).append(w)
        for fname in sorted(by_file):
            print(f"\n  {fname}", file=sys.stderr)
            for w in by_file[fname]:
                print(f"    [{w['code']}] {w['msg']}", file=sys.stderr)
        print(f"\n{'='*64}\n", file=sys.stderr)

    # ── Write JSON ────────────────────────────────────────────────────────────
    output = {
        "generated":     datetime.now(timezone.utc).isoformat(),
        "session_count": len(sessions),
        "warning_count": len(all_warnings),
        "warnings":      all_warnings,
        "sessions":      sessions,
    }

    OUTPUT_FILE.write_text(
        json.dumps(output, indent=2, ensure_ascii=False),
        encoding='utf-8'
    )

    print(f"gen_sessions.py: {len(sessions)} sessions → {OUTPUT_FILE}")
    if all_warnings:
        print(f"  {len(all_warnings)} warning(s) printed above — fix then re-run.")

if __name__ == "__main__":
    main()

