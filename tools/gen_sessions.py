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
    NO_MARKERS          = "W001"   # No :: HEADER:START :: found — 
                                   # markdown fallback
    DUPLICATE_PA        = "W002"   # Duplicate ## Claude.ai Assessment -
                                   # blocks, merged
    EMPTY_ASSESSMENT    = "W003"   # ## My Assessment is empty or TBD
    ABANDONED_WITH_PASS = "W004"   # status=abandoned but PASS counts found 
                                   # in results
    MISSING_DISCUSSION  = "W005"   # No :: DISCUSSION:START/END :: section
    MISSING_RESULTS     = "W006"   # No :: RESULTS:START/END :: section
    MISSING_PROMPT      = "W007"   # No :: PROMPT:START/END :: section
    ID_MISMATCH         = "W008"   # Task ID in header or 
                                   # prompt != filename stem

# W009 is not longer used
#    ORPHAN_SUBSESSION   = "W009"   # Sub-session with no parent in dir

    MISSING_FIELD       = "W010"   # Expected header field absent or empty
    VOICES_MERGED       = "W011"   # Discussion voices could not be cleanly
                                   # separated
    UNKNOWN_CATEGORY    = "W012"   # Task ID prefix not in KNOWN_CATEGORIES
    BAD_TASK_ID         = "W013"   # Task ID doesn't match expected pattern
    FIELD_ALIAS_USED    = "W014"   # Non-canonical field name used (e.g. 'ID'
                                   # not 'Task ID')
    PROMPT_ID_MISMATCH  = "W015"   # Task ID in ## Task ID
                                   # prompt block != header/filename
    MISSING_END_MARKER  = "W016"   # Section START marker found but
                                   # END marker absent

# ── Task ID parsing ───────────────────────────────────────────────────────────

# Matches: BP-040, BP-008a, BP-008a-1, BP-014d, BP-009a-1, DECODE-001
# Category is uppercase letters; optional lowercase letter suffix (a/b/c/d...);
# optional -N sub-session number.
# NOTE: do NOT call .upper() before matching — that converts 'BP-014d' to
# 'BP-014D' which fails the [a-z] group.
TASK_ID_RE = re.compile(r'^([A-Za-z]+)-(\d+)([a-z]?)(-\d+)?$')

def parse_task_id(task_id):
    """
    Return (category, number, suffix_letter, suffix_number, cluster_key) or None.
    cluster_key groups sub-sessions: BP-008a, BP-008a-1, BP-008b, BP-014d -> BP-008 / BP-014
    Category is normalised to uppercase in the return value.
    """
    m = TASK_ID_RE.match(task_id.strip())
    if not m:
        return None
    cat = m.group(1).upper()
    num = m.group(2)
    sl  = m.group(3).lower() if m.group(3) else ""
    sn  = m.group(4) or ""
    return cat, num, sl, sn, f"{cat}-{num}"

# ── Text utilities ────────────────────────────────────────────────────────────

def extract_between(text, start_marker, end_marker):
    """Return text between markers, stripped. None if start not found.
    If end marker is missing, returns everything after start (silent fallback).
    Use extract_section when a missing end marker should produce a warning."""
    s = text.find(start_marker)
    if s == -1:
        return None
    s += len(start_marker)
    e = text.find(end_marker, s)
    return (text[s:e] if e != -1 else text[s:]).strip()

def extract_section(text, start_marker, end_marker, warn_fn, warn_code, section_name):
    """
    Like extract_between but warns (W016) when the start marker is present
    without a matching end marker. Use this for all major document sections
    (DISCUSSION, PROMPT, RESULTS) where a missing end marker indicates a
    truncated or malformed file that will corrupt subsequent parsing.

    Returns None if start not found, content string otherwise.
    """
    s = text.find(start_marker)
    if s == -1:
        return None
    s += len(start_marker)
    e = text.find(end_marker, s)
    if e == -1:
        warn_fn(warn_code,
                f"'{start_marker.strip()}' found but '{end_marker.strip()}' is missing "
                f"in {section_name} section — file may be truncated or markers were "
                f"accidentally deleted. Content after start marker will be used as-is, "
                f"but subsequent sections may not parse correctly.")
        return text[s:].strip()
    return text[s:e].strip()

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

def normalise_id(task_id):
    """Uppercase for comparison purposes, stripping whitespace."""
    return task_id.strip().upper()

# ── Header parsing ────────────────────────────────────────────────────────────

# Canonical field name -> internal key.
# Also used to detect non-canonical aliases (e.g. 'id' instead of 'task id').
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
    # Non-canonical aliases — recognised but trigger W014
    'id':            'task_id',
    'task':          'task_id',
    'experiment id': 'task_id',
}

# Fields that are considered non-canonical (trigger W014 when used)
NON_CANONICAL = {
    'id':            'Task ID',
    'task':          'Task ID',
    'experiment id': 'Task ID',
}

def parse_header_table(header_text):
    """
    Parse the markdown table inside the header section.
    Handles multi-row field values (continuation rows have empty first cell).
    Returns (fields_dict, alias_warnings_list).
    fields_dict: canonical_key -> value_string
    alias_warnings_list: list of (raw_key, canonical_name) for non-canonical fields found
    """
    fields   = {}
    aliases  = []
    last_key = None

    for line in header_text.splitlines():
        line = line.strip()
        if not line.startswith('|'):
            continue
        if re.match(r'\|[-| ]+\|', line):
            continue
        parts = [p.strip() for p in line.strip('|').split('|')]
        if len(parts) < 2:
            continue

        raw_key = parts[0].strip()
        raw_val = parts[1].strip()

        if raw_key.lower() == 'field':
            continue

        if raw_key:
            raw_lower = raw_key.lower().replace('_', ' ')
            canonical = FIELD_ALIASES.get(raw_lower,
                         FIELD_ALIASES.get(raw_key.lower(), raw_key.lower()))
            if raw_val:
                fields[canonical] = raw_val
                last_key = canonical
            if raw_lower in NON_CANONICAL:
                aliases.append((raw_key, NON_CANONICAL[raw_lower]))
        elif not raw_key and last_key and raw_val:
            # Continuation row
            fields[last_key] = fields[last_key].rstrip(',').strip() + ', ' + raw_val

    return fields, aliases

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

# ── Prompt Task ID extraction ─────────────────────────────────────────────────

def extract_prompt_task_id(prompt_text):
    """
    Extract the Task ID from the '## Task ID' block at the top of the prompt.
    Looks for:
        ## Task ID
        BP-040
    Returns the ID string or None if not found.
    """
    if not prompt_text:
        return None
    m = re.search(
        r'##\s+Task\s+ID\s*\n+\s*([A-Za-z]+-\d+[A-Za-z0-9-]*)',
        prompt_text, re.IGNORECASE
    )
    return m.group(1).strip() if m else None

# ── Discussion voice splitting ────────────────────────────────────────────────

IA_HEADINGS   = {"claude.code console output", "claude code console output"}
MY_HEADINGS   = {"my assessment"}
PA_HEADINGS   = {"claude.ai assessment", "claude ai assessment"}
TAIL_HEADINGS = {"follow-on actions", "follow on actions", "claude.md updates",
                 "other planning file updates", "other notes"}

def split_discussion_voices(discussion_text):
    """
    Split discussion section into three voice blocks.
    Returns (ia_output, my_assessment, pa_assessment, warnings_list).
    warnings_list items are (code, message) tuples.
    """
    warnings   = []
    heading_re = re.compile(r'^##\s+(.+)$', re.MULTILINE)
    headings   = list(heading_re.finditer(discussion_text))

    if not headings:
        return None, None, None, []

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
            pass

    ia = "\n\n".join(ia_parts) if ia_parts else None
    my = "\n\n".join(my_parts) if my_parts else None
    pa = "\n\n---\n\n".join(pa_parts) if pa_parts else None

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
    """
    text     = path.read_text(encoding='utf-8')
    filename = path.stem
    file_str = str(path)
    warnings = []

    def warn(code, msg):
        warnings.append({"code": code, "file": file_str, "msg": msg})

    def wsection(text, start, end, section_name):
        """extract_section with warn pre-bound to this file."""
        return extract_section(text, start, end, warn, W.MISSING_END_MARKER, section_name)

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
    # Header uses extract_between (not wsection) — a missing HEADER:END is
    # caught implicitly: the overview extraction and discussion extraction will
    # both fail, producing their own warnings.
    header_text = extract_between(text, ':: HEADER:START ::', ':: HEADER:END ::')
    if not header_text:
        warn(W.MISSING_FIELD, "Header markers found but header content is empty.")
    else:
        fields, field_aliases = parse_header_table(header_text)

        # Warn about non-canonical field names
        for raw_key, correct_name in field_aliases:
            warn(W.FIELD_ALIAS_USED,
                 f"Header field '{raw_key}' should be '{correct_name}' — "
                 f"update the first column of the header table.")

        # Task ID
        task_id = fields.get('task_id', filename).strip()
        session['id'] = task_id

        if normalise_id(task_id) != normalise_id(filename):
            warn(W.ID_MISMATCH,
                 f"Task ID '{task_id}' in header table doesn't match "
                 f"filename '{filename}' — update one to match the other.")

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
                 f"Task ID '{task_id}' doesn't match expected pattern "
                 f"(e.g. BP-040, BP-008a, BP-008a-1, BP-014d).")

        session['date'] = fields.get('date')

        modules_raw = fields.get('module', '')
        session['modules'] = [
            m.strip() for m in re.split(r',\s*', modules_raw)
            if m.strip() and not re.match(r'^[\|\s]+$', m)
        ]

        session['run_time']   = fields.get('run_time')
        session['ctx_pct']    = parse_ctx_pct(fields.get('ctx_pct'))
        session['model']      = fields.get('model')
        session['resume_sha'] = fields.get('resume_sha')

        for req in ['task_id', 'date', 'model']:
            if not fields.get(req):
                warn(W.MISSING_FIELD, f"Required header field '{req}' is absent or empty.")

        session['task_types'] = parse_checkboxes(header_text, TASK_TYPES)
        statuses = parse_checkboxes(header_text, STATUS_OPTS)
        session['status'] = statuses[0] if statuses else 'unknown'

        overview_raw = extract_between(text, ':: HEADER:END ::', ':: DISCUSSION:START ::')
        if overview_raw:
            ov = re.sub(r'^=+$', '', overview_raw, flags=re.MULTILINE)
            ov = re.sub(r'^#+\s+Overview of task\s*$', '', ov, flags=re.MULTILINE)
            ov = re.sub(r'^#+\s+Paste c\.code console output.*$', '', ov,
                        flags=re.MULTILINE | re.IGNORECASE)
            ov = re.sub(r'^#+\s+Paste\s+.*$', '', ov,
                        flags=re.MULTILINE | re.IGNORECASE)
            ov = ov.strip()
            session['overview'] = ov if ov else None

    # ── Discussion ────────────────────────────────────────────────────────────
    discussion_text = wsection(text,
                               ':: DISCUSSION:START ::', ':: DISCUSSION:END ::',
                               'DISCUSSION')
    if discussion_text is None:
        warn(W.MISSING_DISCUSSION, "No ':: DISCUSSION:START ::' marker found.")
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
        results_check = extract_between(text, ':: RESULTS:START ::', ':: RESULTS:END ::') or ''
        disc_check    = discussion_text or ''
        if has_pass_count(results_check) or has_pass_count(disc_check):
            warn(W.ABANDONED_WITH_PASS,
                 "Status is 'abandoned' but PASS counts detected in results or discussion. "
                 "Is the status correct? Review and update.")

    # ── Prompt ────────────────────────────────────────────────────────────────
    prompt_text = wsection(text,
                           ':: PROMPT:START ::', ':: PROMPT:END ::',
                           'PROMPT')
    if prompt_text is None:
        warn(W.MISSING_PROMPT, "No ':: PROMPT:START ::' marker found.")
    else:
        session['prompt_raw'] = prompt_text

        prompt_id = extract_prompt_task_id(prompt_text)
        if prompt_id:
            header_id = session.get('id', filename)
            if normalise_id(prompt_id) != normalise_id(header_id):
                warn(W.PROMPT_ID_MISMATCH,
                     f"Task ID '{prompt_id}' in '## Task ID' prompt block doesn't match "
                     f"header/filename '{header_id}' — update to match.")
        else:
            warn(W.PROMPT_ID_MISMATCH,
                 "No '## Task ID' block found in prompt section — add one at the top.")

    # ── Results ───────────────────────────────────────────────────────────────
    results_text = wsection(text,
                            ':: RESULTS:START ::', ':: RESULTS:END ::',
                            'RESULTS')
    if results_text is None:
        warn(W.MISSING_RESULTS, "No ':: RESULTS:START ::' marker found.")
    else:
        session['results_raw'] = results_text

    session['warnings'] = warnings
    return session, warnings

# ── Cross-file validation ─────────────────────────────────────────────────────

#def validate_clusters(sessions):
#    """Warn about sub-sessions whose parent doesn't exist in the directory."""
#    all_ids  = {normalise_id(s['id']) for s in sessions}
#    warnings = []
#
#    for s in sessions:
#        parsed = parse_task_id(s['id'])
#        if not parsed:
#            continue
#        cat, num, sl, sn, cluster = parsed
#        is_sub = bool(sl) or bool(sn)
#        if is_sub:
#            parent_id = f"{cat}-{num}"
#            if normalise_id(parent_id) not in all_ids:
#                warnings.append({
#                    "code": W.ORPHAN_SUBSESSION,
#                    "file": s['path'],
#                    "msg":  (f"Sub-session '{s['id']}' has no parent '{parent_id}' "
#                             f"in {PROMPTS_DIR}/. If the parent was renamed, "
#                             f"update the Task ID or add the parent file."),
#                })
#    return warnings

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

    #all_warnings.extend(validate_clusters(sessions))
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

    print(f"gen_sessions.py: {len(sessions)} sessions -> {OUTPUT_FILE}")
    if all_warnings:
        print(f"  {len(all_warnings)} warning(s) printed above — fix then re-run.")

if __name__ == "__main__":
    main()

