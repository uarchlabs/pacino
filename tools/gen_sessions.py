#!/usr/bin/env python3
"""
gen_sessions.py -- parse prompts/*.md and emit docs/sessions.json

Run from the repo root:
    python3 tools/gen_sessions.py [--show-waived] [--no-waivers]

    --show-waived   list warnings suppressed by the WAIVERS table
    --no-waivers    ignore the WAIVERS table, report every warning

Warnings are printed to stderr. sessions.json is written to docs/.
A small "summary" block (counts by status and category, first/last session
dates, latest sessions) is written near the top of the file for pages that
only need totals.
"""

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# -- Configuration -------------------------------------------------------------

PROMPTS_DIR = Path("prompts")
OUTPUT_FILE  = Path("docs/sessions.json")

KNOWN_CATEGORIES = {"BP", "COMP", "DECODE", "INFRA", "TB", "TOOLS"}

TASK_TYPES  = ["experiment", "implementation", "debug",
               "cleanup", "testbench", "verification"]
STATUS_OPTS = ["in-progress", "complete", "abandoned"]
# Mode checkboxes. "interactive" is optional -- older headers carry
# only automated/manual. A header with no interactive box is not a
# defect.
MODE_OPTS   = ["automated", "manual", "interactive"]

# -- Warning codes -------------------------------------------------------------

class W:
    NO_MARKERS          = "W001"   # No :: HEADER:START :: found --
                                   # markdown fallback
    DUPLICATE_PA        = "W002"   # Duplicate ## Claude.ai Assessment
                                   # blocks, merged
    EMPTY_ASSESSMENT    = "W003"   # ## My Assessment is empty or TBD
    ABANDONED_WITH_PASS = "W004"   # status=abandoned but PASS counts
                                   # found in results
    MISSING_DISCUSSION  = "W005"   # No :: DISCUSSION:START/END :: section
    MISSING_RESULTS     = "W006"   # No :: RESULTS:START/END :: section
    MISSING_PROMPT      = "W007"   # No :: PROMPT:START/END :: section
    ID_MISMATCH         = "W008"   # Task ID in header or
                                   # prompt != filename stem

# W009 is no longer used
#   ORPHAN_SUBSESSION   = "W009"   # Sub-session with no parent in dir

    MISSING_FIELD       = "W010"   # Expected header field absent or empty
    VOICES_MERGED       = "W011"   # Discussion voices could not be cleanly
                                   # separated
    UNKNOWN_CATEGORY    = "W012"   # Task ID prefix not in KNOWN_CATEGORIES
    BAD_TASK_ID         = "W013"   # Task ID doesn't match expected pattern
    FIELD_ALIAS_USED    = "W014"   # Non-canonical field name used (e.g.
                                   # 'ID' not 'Task ID')
    PROMPT_ID_MISMATCH  = "W015"   # Task ID in ## Task ID prompt block
                                   # != header/filename
    MISSING_END_MARKER  = "W016"   # Section START marker found but
                                   # END marker absent
    MISSING_MODE        = "W017"   # Mode: field absent or no box checked
    MISSING_OVERVIEW    = "W018"   # No '# Task Overview' heading found,
                                   # or overview section is empty/TBD
    MISSING_PA_SESSION  = "W019"   # No 'PA session' value in header table
                                   # (row absent, empty, or '???')
    BAD_PA_SESSION      = "W020"   # PA session value is not NNN[N] or
                                   # IA-NNN[N]
    MULTI_MODE          = "W021"   # More than one Mode box is checked;
                                   # the modes are mutually exclusive
    MISSING_TASK_TYPE   = "W022"   # Task: field absent or no box checked
    MISSING_STATUS      = "W023"   # Status: field absent or no box
                                   # checked; status falls back to
                                   # 'unknown'
    MULTI_STATUS        = "W024"   # More than one Status box is checked;
                                   # only the first is recorded

# -- Waivers -------------------------------------------------------------------
#
# Per-file suppression of a single warning. Edit this table to silence a
# warning that has been reviewed and accepted. A waived warning is dropped
# from stderr and from the per-session 'warnings' list in sessions.json,
# and recorded in a parallel 'waived' list instead, so the audit trail
# survives. Run with --show-waived to print them.
#
#   Key    the .md filename, with or without the extension -- both
#          'BP-042' and 'BP-042.md' work. The special key '*' applies
#          to every file.
#   Value  one of:
#            a bare code            W.BAD_TASK_ID
#            a list of codes        [W.BAD_TASK_ID, W.VOICES_MERGED]
#            a dict code -> reason  {W.BAD_TASK_ID: "why"}
#          The reason is optional. It is only documentation -- it is
#          echoed by --show-waived and carried into sessions.json.
#          The special code '*' waives every warning for that file.
#
# Stale entries -- a waiver whose warning no longer fires -- are reported
# at the end of the run so this table does not rot.
#
WAIVERS = {
  "BP-107" : [W.VOICES_MERGED],
  "BP-105" : [W.EMPTY_ASSESSMENT],
  "BP-104" : [W.EMPTY_ASSESSMENT],
  "BP-102" : [W.EMPTY_ASSESSMENT],
  "BP-101" : [W.EMPTY_ASSESSMENT],
  "BP-090" : [W.VOICES_MERGED],
  "BP-089" : [W.ABANDONED_WITH_PASS],
  "BP-088" : [W.ABANDONED_WITH_PASS],
  "BP-087" : [W.ABANDONED_WITH_PASS],
  "BP-086" : [W.EMPTY_ASSESSMENT],
  "BP-081" : [W.VOICES_MERGED],
  "BP-079" : [W.VOICES_MERGED],
  "BP-072" : [W.VOICES_MERGED],
  "BP-062" : [W.VOICES_MERGED],
  "BP-050" : [W.ABANDONED_WITH_PASS],
  "BP-045" : [W.VOICES_MERGED],
  "BP-042" : [W.VOICES_MERGED],
  "BP-033" : [W.ABANDONED_WITH_PASS],
  "BP-033-FIX-1" : [W.BAD_TASK_ID,W.VOICES_MERGED],
}

# All warning codes defined on W, used to reject typos in WAIVERS.
VALID_CODES = {v for k, v in vars(W).items() if k.isupper()}

# (waiver_key, code_key) pairs that actually suppressed a warning this run.
_WAIVERS_USED = set()

# Set by --no-waivers. When true the WAIVERS table is ignored entirely and
# every warning is reported, so a full audit can be run without editing
# the table.
_WAIVERS_DISABLED = False

def norm_waiver_key(key):
    """
    Normalise a WAIVERS key to a bare file stem. Both 'BP-090' and
    'BP-090.md' are accepted; the '*' key passes through unchanged.
    """
    key = key.strip()
    return key[:-3] if key.lower().endswith('.md') else key

def waiver_table():
    """WAIVERS with its keys normalised to bare file stems."""
    return {norm_waiver_key(k): v for k, v in WAIVERS.items()}

def normalise_waiver(entry):
    """
    Accept any of the three WAIVERS value forms and return a dict of
    code -> reason. Codes given without a reason map to ''. Returns None
    when the entry is malformed.
    """
    if isinstance(entry, str):
        return {entry: ''}
    if isinstance(entry, (list, tuple, set)):
        if not all(isinstance(c, str) for c in entry):
            return None
        return {c: '' for c in entry}
    if isinstance(entry, dict):
        return {c: (r or '') for c, r in entry.items()}
    return None

def waiver_reason(file_stem, code):
    """
    Return the waiver reason for (file_stem, code), or None when the
    warning is not waived. A waiver with no reason returns '' -- which
    is still a hit, so callers must test 'is not None', not truthiness.
    Exact file stem wins over the '*' key, exact code over the '*' code.
    Records the hit so stale waivers can be reported.
    """
    if _WAIVERS_DISABLED:
        return None
    table = waiver_table()
    for fkey in (file_stem, '*'):
        entry = normalise_waiver(table.get(fkey))
        if not entry:
            continue
        for ckey in (code, '*'):
            if ckey in entry:
                _WAIVERS_USED.add((fkey, ckey))
                return entry[ckey]
    return None

def check_waiver_table():
    """
    Validate the WAIVERS table itself -- unknown file stems, unknown
    warning codes, malformed entries. Returns a list of message strings
    (empty when the table is clean).
    """
    problems = []
    seen = {}
    for raw_key in WAIVERS:
        fkey = norm_waiver_key(raw_key)
        if fkey in seen:
            problems.append(
                f"'{raw_key}' and '{seen[fkey]}' are the same file -- "
                f"merge them into one entry")
        seen[fkey] = raw_key

    for fkey, raw in waiver_table().items():
        if fkey != '*' and not (PROMPTS_DIR / f"{fkey}.md").exists():
            problems.append(
                f"'{fkey}' -- no such file {PROMPTS_DIR}/{fkey}.md")
        entry = normalise_waiver(raw)
        if entry is None:
            problems.append(
                f"'{fkey}' -- value must be a code, a list of codes, "
                f"or a dict of code -> reason")
            continue
        for code in entry:
            if code != '*' and code not in VALID_CODES:
                problems.append(
                    f"'{fkey}' -- unknown warning code '{code}'")
    return problems

def stale_waivers():
    """Declared (file_stem, code) waivers that suppressed nothing."""
    declared = set()
    for fkey, raw in waiver_table().items():
        entry = normalise_waiver(raw)
        if entry:
            declared.update((fkey, c) for c in entry)
    return sorted(declared - _WAIVERS_USED)

# -- Task ID parsing -----------------------------------------------------------

# Matches: BP-040, BP-008a, BP-008a-1, BP-014d, BP-009a-1, DECODE-001
# Category is uppercase letters; optional lowercase letter suffix (a/b/c/d);
# optional -N sub-session number.
# NOTE: do NOT call .upper() before matching -- that converts 'BP-014d' to
# 'BP-014D' which fails the [a-z] group.
TASK_ID_RE = re.compile(r'^([A-Za-z]+)-(\d+)([a-z]?)(-\d+)?$')

def parse_task_id(task_id):
    """
    Return (category, number, suffix_letter, suffix_number, cluster_key)
    or None.
    cluster_key groups sub-sessions: BP-008a, BP-008a-1, BP-008b -> BP-008
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

# -- Text utilities ------------------------------------------------------------

def extract_between(text, start_marker, end_marker):
    """Return text between markers, stripped. None if start not found.
    If end marker is missing, returns everything after start (silent
    fallback). Use extract_section when a missing end marker should
    produce a warning."""
    s = text.find(start_marker)
    if s == -1:
        return None
    s += len(start_marker)
    e = text.find(end_marker, s)
    return (text[s:e] if e != -1 else text[s:]).strip()

def extract_section(text, start_marker, end_marker,
                    warn_fn, warn_code, section_name):
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
                f"'{start_marker.strip()}' found but "
                f"'{end_marker.strip()}' is missing "
                f"in {section_name} section -- file may be truncated "
                f"or markers were accidentally deleted. Content after "
                f"start marker will be used as-is, but subsequent "
                f"sections may not parse correctly.")
        return text[s:].strip()
    return text[s:e].strip()

def is_empty_or_tbd(text):
    if not text:
        return True
    t = re.sub(r'[-\s]', '', text.strip().upper())
    return t in ('', 'TBD', 'NA', 'NONE', 'ASNEEDEDDDOCUMENTHERE')

def has_pass_count(text):
    """True if text contains patterns like '76 PASS', 'PASS=24',
    'ALL TESTS PASSED'."""
    return bool(re.search(
        r'\b\d+\s+PASS\b|\bPASS\s*=\s*\d+|\bALL\s+TESTS\s+PASSED\b',
        text, re.IGNORECASE
    ))

def normalise_id(task_id):
    """Uppercase for comparison purposes, stripping whitespace."""
    return task_id.strip().upper()

# -- Header parsing ------------------------------------------------------------

# Canonical field name -> internal key.
# Also used to detect non-canonical aliases (e.g. 'id' instead of
# 'task id').
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
    'pa_session': 'pa_session',
    'pa session': 'pa_session',
    # Non-canonical aliases -- recognised but trigger W014
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
    Handles multi-row field values (continuation rows have empty first
    cell).
    Returns (fields_dict, alias_warnings_list).
    fields_dict: canonical_key -> value_string
    alias_warnings_list: list of (raw_key, canonical_name) for
    non-canonical fields found
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
            canonical = FIELD_ALIASES.get(
                raw_lower,
                FIELD_ALIASES.get(raw_key.lower(), raw_key.lower()))
            if raw_val:
                fields[canonical] = raw_val
                last_key = canonical
            if raw_lower in NON_CANONICAL:
                aliases.append((raw_key, NON_CANONICAL[raw_lower]))
        elif not raw_key and last_key and raw_val:
            # Continuation row
            fields[last_key] = (
                fields[last_key].rstrip(',').strip() + ', ' + raw_val)

    return fields, aliases

def parse_checkboxes(text, options):
    """Return list of option names where [x] is found before the option
    text."""
    checked = []
    for opt in options:
        if re.search(r'\[x\]\s+' + re.escape(opt), text, re.IGNORECASE):
            checked.append(opt)
    return checked

def parse_ctx_pct(raw):
    """Extract integer percentage from strings like '23%', '23',
    '75%'."""
    if not raw:
        return None
    m = re.search(r'(\d+)', raw)
    return int(m.group(1)) if m else None

# -- Prompt Task ID extraction -------------------------------------------------

def extract_prompt_task_id(prompt_text):
    """
    Extract the Task ID from the '## Task ID' block at the top of the
    prompt.
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

# -- Files Modified parsing ----------------------------------------------------

def parse_files_modified(results_text):
    """
    Find the ## Files Modified section inside the results block.
    Parses bullet list lines (lines starting with '-' or '*').
    Returns a list of file path strings, stripped of leading bullet
    characters and whitespace.
    Returns [] if the section is absent or contains no bullet lines.
    """
    if not results_text:
        return []

    # Find ## Files Modified heading (case-insensitive)
    m = re.search(
        r'##\s+Files\s+Modified\s*\n(.*?)(?=\n##\s|\Z)',
        results_text,
        re.IGNORECASE | re.DOTALL
    )
    if not m:
        return []

    section_body = m.group(1)
    files = []
    for line in section_body.splitlines():
        line = line.strip()
        # Accept lines starting with - or *
        if line.startswith('-') or line.startswith('*'):
            entry = line.lstrip('-*').strip()
            # Skip blank entries and placeholder/instruction lines
            if not entry:
                continue
            lower = entry.lower()
            if lower.startswith('list every') or \
               lower.startswith('no prose') or \
               lower.startswith('file paths') or \
               lower.startswith('example'):
                continue
            files.append(entry)
    return files

# -- Discussion voice splitting ------------------------------------------------

IA_HEADINGS   = {"claude.code console output",
                 "claude code console output"}
MY_HEADINGS   = {"my assessment"}
PA_HEADINGS   = {"claude.ai assessment", "claude ai assessment"}
TAIL_HEADINGS = {"follow-on actions", "follow on actions",
                 "claude.md updates", "other planning file updates",
                 "other notes"}

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
        end     = (headings[i + 1].start()
                   if i + 1 < len(headings)
                   else len(discussion_text))
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
                    f"Duplicate '## {heading}' heading -- blocks merged."
                    f" Review and consolidate manually."))
            pa_parts.append(content)
        elif h in TAIL_HEADINGS:
            pass

    ia = "\n\n".join(ia_parts) if ia_parts else None
    my = "\n\n".join(my_parts) if my_parts else None
    pa = "\n\n---\n\n".join(pa_parts) if pa_parts else None

    if my and len(my) > 2500:
        warnings.append((W.VOICES_MERGED,
            "## My Assessment is unusually long (>2500 chars) -- may "
            "contain interleaved PA voice. Review and split manually."))

    return ia, my, pa, warnings

# -- Per-file parser -----------------------------------------------------------

def parse_session_file(path):
    """
    Parse a single session .md file.
    Returns (session_dict, warnings_list, waived_list).
    Warnings matched by the WAIVERS table go to waived_list instead of
    warnings_list.
    """
    text     = path.read_text(encoding='utf-8')
    filename = path.stem
    file_str = str(path)
    warnings = []
    waived   = []

    def warn(code, msg):
        reason = waiver_reason(filename, code)
        if reason is not None:
            waived.append({"code":   code,
                           "file":   file_str,
                           "msg":    msg,
                           "reason": reason})
            return
        warnings.append({"code": code, "file": file_str, "msg": msg})

    def wsection(text, start, end, section_name):
        """extract_section with warn pre-bound to this file."""
        return extract_section(
            text, start, end, warn, W.MISSING_END_MARKER, section_name)

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
        "pa_session":     "???",
        "task_types":     [],
        "modes":          [],
        "status":         None,
        "overview":       None,
        "ia_output":      None,
        "my_assessment":  None,
        "pa_assessment":  None,
        "discussion_raw": None,
        "prompt_raw":     None,
        "results_raw":    None,
        "files_modified": [],
        "warnings":       [],
        "waived":         [],
    }

    # -- Marker check ----------------------------------------------------------
    has_markers = ':: HEADER:START ::' in text
    session['has_markers'] = has_markers

    if not has_markers:
        warn(W.NO_MARKERS,
             "No ':: HEADER:START ::' marker found -- rendering as raw "
             "markdown. Add markers to enable structured parsing.")
        parsed = parse_task_id(filename)
        if parsed:
            cat, num, sl, sn, cluster = parsed
            session['category'] = cat
            session['cluster']  = cluster
            if cat not in KNOWN_CATEGORIES:
                warn(W.UNKNOWN_CATEGORY,
                     f"Category '{cat}' not in "
                     f"{sorted(KNOWN_CATEGORIES)}")
        else:
            warn(W.BAD_TASK_ID,
                 f"Filename '{filename}' doesn't match pattern "
                 f"e.g. BP-040")
        session['discussion_raw'] = text
        session['warnings'] = warnings
        session['waived']   = waived
        return session, warnings, waived

    # -- Header ----------------------------------------------------------------
    # Header uses extract_between (not wsection) -- a missing HEADER:END
    # is caught implicitly: overview and discussion extraction will both
    # fail, producing their own warnings.
    header_text = extract_between(
        text, ':: HEADER:START ::', ':: HEADER:END ::')
    if not header_text:
        warn(W.MISSING_FIELD,
             "Header markers found but header content is empty.")
    else:
        fields, field_aliases = parse_header_table(header_text)

        # Warn about non-canonical field names
        for raw_key, correct_name in field_aliases:
            warn(W.FIELD_ALIAS_USED,
                 f"Header field '{raw_key}' should be '{correct_name}'"
                 f" -- update the first column of the header table.")

        # Task ID
        task_id = fields.get('task_id', filename).strip()
        session['id'] = task_id

        if normalise_id(task_id) != normalise_id(filename):
            warn(W.ID_MISMATCH,
                 f"Task ID '{task_id}' in header table doesn't match "
                 f"filename '{filename}' -- update one to match.")

        parsed = parse_task_id(task_id)
        if parsed:
            cat, num, sl, sn, cluster = parsed
            session['category'] = cat
            session['cluster']  = cluster
            if cat not in KNOWN_CATEGORIES:
                warn(W.UNKNOWN_CATEGORY,
                     f"Category '{cat}' not in known set "
                     f"{sorted(KNOWN_CATEGORIES)}. Add it to "
                     f"KNOWN_CATEGORIES in gen_sessions.py if "
                     f"intentional.")
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

        # PA session -- expected to be a 3 or 4 digit number, or the
        # same number with an IA- prefix for an interactive IA
        # session (IA-004 is the session that emitted
        # ia_context/ia_handoffs/ia_session_handoff-004.md).
        # A missing row, an empty value, or the '???' placeholder all
        # map to the '???' sentinel and raise W019. Any other value
        # raises W020. The prefix is accepted in any case and stored
        # uppercase, so IA-004 and ia-004 land on one value.
        pa_raw = fields.get('pa_session')
        if (pa_raw is None
                or is_empty_or_tbd(pa_raw)
                or pa_raw.strip() == '???'):
            session['pa_session'] = '???'
            warn(W.MISSING_PA_SESSION,
                 "No 'PA session' value found in header table -- add a "
                 "'| PA session | NNNN |' row with the 3-4 digit "
                 "session number.")
        else:
            pa_val = pa_raw.strip()
            m = re.fullmatch(r'(?i:(ia-)?)(\d{3,4})', pa_val)
            if m:
                pa_val = ('IA-' if m.group(1) else '') + m.group(2)
            else:
                warn(W.BAD_PA_SESSION,
                     f"PA session '{pa_val}' is not 3 or 4 digits, "
                     f"with or without an IA- prefix -- expected "
                     f"something like '405', '1234' or 'IA-004'.")
            session['pa_session'] = pa_val

        for req in ['task_id', 'date', 'model']:
            if not fields.get(req):
                warn(W.MISSING_FIELD,
                     f"Required header field '{req}' is absent or "
                     f"empty.")

        session['task_types'] = parse_checkboxes(header_text, TASK_TYPES)
        if not session['task_types']:
            warn(W.MISSING_TASK_TYPE,
                 "Task: field absent or no box is checked -- check one "
                 "of " + ', '.join(TASK_TYPES) + " in the header block. "
                 "Backfill is acceptable; warn only, not fail.")

        # Mode checkboxes
        modes = parse_checkboxes(header_text, MODE_OPTS)
        session['modes'] = modes
        if len(modes) > 1:
            warn(W.MULTI_MODE,
                 f"Mode: more than one box is checked "
                 f"({', '.join(modes)}). The modes are mutually "
                 f"exclusive -- check exactly one.")
        if not modes:
            warn(W.MISSING_MODE,
                 "Mode: field absent or no box is checked -- add "
                 "'Mode: [x] automated', '[x] manual' or "
                 "'[x] interactive' to the header block. Backfill "
                 "is acceptable; warn only, not fail.")

        statuses = parse_checkboxes(header_text, STATUS_OPTS)
        session['status'] = statuses[0] if statuses else 'unknown'
        if len(statuses) > 1:
            warn(W.MULTI_STATUS,
                 f"Status: more than one box is checked "
                 f"({', '.join(statuses)}). The statuses are mutually "
                 f"exclusive -- only '{statuses[0]}' is recorded, the "
                 f"rest are dropped. Check exactly one.")
        if not statuses:
            warn(W.MISSING_STATUS,
                 "Status: field absent or no box is checked -- add "
                 "'[x] in-progress', '[x] complete' or '[x] abandoned' "
                 "to the header block. status is recorded as 'unknown', "
                 "which the sessions viewer cannot filter.")

        # Overview lives inside the header block, after the
        # '# Overview of task' heading and before :: HEADER:END ::
        ov_m = re.search(
#            r'#\s+Overview of task\s*\n(.*)',
            r'#\s+Task Overview\s*\n(.*)',
            header_text,
            re.IGNORECASE | re.DOTALL
        )
        if ov_m:
            ov = ov_m.group(1).strip()
            ov = re.sub(r'^=+$', '', ov, flags=re.MULTILINE)
            ov = re.sub(
                r'^#+\s+Paste c\.code console output.*$', '', ov,
                flags=re.MULTILINE | re.IGNORECASE)
            ov = re.sub(r'^#+\s+Paste\s+.*$', '', ov,
                        flags=re.MULTILINE | re.IGNORECASE)
            ov = ov.strip()
            session['overview'] = ov if ov else None
            if is_empty_or_tbd(session['overview']):
                warn(W.MISSING_OVERVIEW,
                     "'# Task Overview' heading found but the section "
                     "is empty or TBD -- add a short task overview.")
        else:
            warn(W.MISSING_OVERVIEW,
                 "No '# Task Overview' heading found in the header "
                 "block -- add a '# Task Overview' section with a short "
                 "description of the task.")

    # -- Discussion ------------------------------------------------------------
    discussion_text = wsection(
        text,
        ':: DISCUSSION:START ::', ':: DISCUSSION:END ::',
        'DISCUSSION')
    if discussion_text is None:
        warn(W.MISSING_DISCUSSION,
             "No ':: DISCUSSION:START ::' marker found.")
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
                 "## My Assessment is empty or TBD -- add assessment "
                 "before publishing.")
            session['my_assessment'] = None

    # -- Abandoned + PASS inconsistency ----------------------------------------
    if session.get('status') == 'abandoned':
        results_check = (
            extract_between(
                text, ':: RESULTS:START ::', ':: RESULTS:END ::') or '')
        disc_check = discussion_text or ''
        if has_pass_count(results_check) or has_pass_count(disc_check):
            warn(W.ABANDONED_WITH_PASS,
                 "Status is 'abandoned' but PASS counts detected in "
                 "results or discussion. Is the status correct? "
                 "Review and update.")

    # -- Prompt ----------------------------------------------------------------
    prompt_text = wsection(
        text,
        ':: PROMPT:START ::', ':: PROMPT:END ::',
        'PROMPT')
    if prompt_text is None:
        warn(W.MISSING_PROMPT,
             "No ':: PROMPT:START ::' marker found.")
    else:
        session['prompt_raw'] = prompt_text

        prompt_id = extract_prompt_task_id(prompt_text)
        if prompt_id:
            header_id = session.get('id', filename)
            if normalise_id(prompt_id) != normalise_id(header_id):
                warn(W.PROMPT_ID_MISMATCH,
                     f"Task ID '{prompt_id}' in '## Task ID' prompt "
                     f"block doesn't match header/filename "
                     f"'{header_id}' -- update to match.")
        else:
            warn(W.PROMPT_ID_MISMATCH,
                 "No '## Task ID' block found in prompt section -- "
                 "add one at the top.")

    # -- Results ---------------------------------------------------------------
    results_text = wsection(
        text,
        ':: RESULTS:START ::', ':: RESULTS:END ::',
        'RESULTS')
    if results_text is None:
        warn(W.MISSING_RESULTS,
             "No ':: RESULTS:START ::' marker found.")
    else:
        session['results_raw']    = results_text
        session['files_modified'] = parse_files_modified(results_text)

    session['warnings'] = warnings
    session['waived']   = waived
    return session, warnings, waived

# -- Cross-file validation -----------------------------------------------------

# def validate_clusters(sessions):
#     """Warn about sub-sessions whose parent doesn't exist in the
#     directory."""
#     all_ids  = {normalise_id(s['id']) for s in sessions}
#     warnings = []
#
#     for s in sessions:
#         parsed = parse_task_id(s['id'])
#         if not parsed:
#             continue
#         cat, num, sl, sn, cluster = parsed
#         is_sub = bool(sl) or bool(sn)
#         if is_sub:
#             parent_id = f"{cat}-{num}"
#             if normalise_id(parent_id) not in all_ids:
#                 warnings.append({
#                     "code": W.ORPHAN_SUBSESSION,
#                     "file": s['path'],
#                     "msg":  (f"Sub-session '{s['id']}' has no parent "
#                              f"'{parent_id}' in {PROMPTS_DIR}/. If "
#                              f"the parent was renamed, update the "
#                              f"Task ID or add the parent file."),
#                 })
#     return warnings

# -- Sort key ------------------------------------------------------------------

def sort_key(session):
    parsed = parse_task_id(session.get('id', ''))
    if not parsed:
        return ('ZZZ', 9999, '', '')
    cat, num, sl, sn, _ = parsed
    return (cat, int(num), sl, sn)

# -- Summary -------------------------------------------------------------------
#
# A small block written near the top of sessions.json so pages that only need
# totals (e.g. the uarchlabs.com status panel) can read the first few KB of the
# file instead of downloading all of it. Keep it small, and keep it before the
# large "warnings", "waived", and "sessions" arrays.

SUMMARY_LATEST_N = 5

def norm_date(raw):
    """'2026.08.28', '2026/08/28', or '2026-08-28' -> '2026-08-28'; else None."""
    if not raw:
        return None
    d = re.sub(r'[./]', '-', str(raw).strip())
    return d if re.fullmatch(r'\d{4}-\d{2}-\d{2}', d) else None

def build_summary(sessions):
    by_status   = {}
    by_category = {}
    for s in sessions:
        status   = s.get('status') or 'unknown'
        category = s.get('category') or 'uncategorized'
        by_status[status]     = by_status.get(status, 0) + 1
        by_category[category] = by_category.get(category, 0) + 1

    dated = sorted(
        (s for s in sessions if norm_date(s.get('date'))),
        key=lambda s: (norm_date(s['date']), s.get('id') or ''))

    latest = [{
        "id":     s.get('id'),
        "date":   norm_date(s.get('date')),
        "status": s.get('status'),
        "model":  s.get('model'),
    } for s in reversed(dated[-SUMMARY_LATEST_N:])]

    def by_count(d):
        return dict(sorted(d.items(), key=lambda kv: (-kv[1], kv[0])))

    return {
        "by_status":   by_count(by_status),
        "by_category": by_count(by_category),
        "first_date":  norm_date(dated[0]['date'])  if dated else None,
        "last_date":   norm_date(dated[-1]['date']) if dated else None,
        "latest":      latest,
    }

# -- Main ----------------------------------------------------------------------

def main():
    global _WAIVERS_DISABLED

    show_waived = '--show-waived' in sys.argv[1:]
    _WAIVERS_DISABLED = '--no-waivers' in sys.argv[1:]
    for arg in sys.argv[1:]:
        if arg not in ('--show-waived', '--no-waivers'):
            print(f"ERROR: unknown option '{arg}'. Usage: "
                  f"gen_sessions.py [--show-waived] [--no-waivers]",
                  file=sys.stderr)
            sys.exit(2)

    if not PROMPTS_DIR.exists():
        print(
            f"ERROR: '{PROMPTS_DIR}' not found. "
            f"Run from the repo root.",
            file=sys.stderr)
        sys.exit(1)

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)

    md_files = sorted(PROMPTS_DIR.glob("*.md"))
    if not md_files:
        print(
            f"WARNING: No .md files found in '{PROMPTS_DIR}'.",
            file=sys.stderr)

    # Validate the waiver table before it is used, so a typo in a code
    # or a stem does not silently fail to waive anything.
    table_problems = [] if _WAIVERS_DISABLED else check_waiver_table()
    if table_problems:
        print("\nWAIVER TABLE PROBLEMS (WAIVERS in gen_sessions.py):",
              file=sys.stderr)
        for msg in table_problems:
            print(f"    {msg}", file=sys.stderr)

    sessions     = []
    all_warnings = []
    all_waived   = []

    for path in md_files:
        session, file_warns, file_waived = parse_session_file(path)
        sessions.append(session)
        all_warnings.extend(file_warns)
        all_waived.extend(file_waived)

    # all_warnings.extend(validate_clusters(sessions))
    sessions.sort(key=sort_key)

    # -- Print warnings --------------------------------------------------------
    if all_warnings:
        print(f"\n{'='*64}", file=sys.stderr)
        print(
            f"  gen_sessions.py -- {len(all_warnings)} warning(s)",
            file=sys.stderr)
        print(f"{'='*64}", file=sys.stderr)
        by_file = {}
        for w in all_warnings:
            by_file.setdefault(
                Path(w['file']).name, []).append(w)
        for fname in sorted(by_file):
            print(f"\n  {fname}", file=sys.stderr)
            for w in by_file[fname]:
                print(
                    f"    [{w['code']}] {w['msg']}",
                    file=sys.stderr)
        print(f"\n{'='*64}\n", file=sys.stderr)

    # -- Waived warnings -------------------------------------------------------
    if all_waived and show_waived:
        print(f"\n{'='*64}", file=sys.stderr)
        print(f"  gen_sessions.py -- {len(all_waived)} waived warning(s)",
              file=sys.stderr)
        print(f"{'='*64}", file=sys.stderr)
        by_file = {}
        for w in all_waived:
            by_file.setdefault(Path(w['file']).name, []).append(w)
        for fname in sorted(by_file):
            print(f"\n  {fname}", file=sys.stderr)
            for w in by_file[fname]:
                reason = w['reason'] or '(no reason given)'
                print(f"    [{w['code']}] WAIVED: {reason}",
                      file=sys.stderr)
        print(f"\n{'='*64}\n", file=sys.stderr)

    stale = [] if _WAIVERS_DISABLED else stale_waivers()
    if stale:
        print("\nSTALE WAIVERS (nothing to suppress -- delete these "
              "from WAIVERS in gen_sessions.py):", file=sys.stderr)
        for fkey, code in stale:
            print(f"    {fkey} / {code}", file=sys.stderr)
        print("", file=sys.stderr)

    # -- Write JSON ------------------------------------------------------------
    output = {
        "generated":     datetime.now(timezone.utc).isoformat(),
        "session_count": len(sessions),
        "summary":       build_summary(sessions),   # keep before the big arrays
        "warning_count": len(all_warnings),
        "warnings":      all_warnings,
        "waived_count":  len(all_waived),
        "waived":        all_waived,
        "sessions":      sessions,
    }

    OUTPUT_FILE.write_text(
        json.dumps(output, indent=2, ensure_ascii=False),
        encoding='utf-8'
    )

    print(
        f"gen_sessions.py: {len(sessions)} sessions -> {OUTPUT_FILE}")
    if all_warnings:
        print(
            f"  {len(all_warnings)} warning(s) printed above "
            f"-- fix then re-run.")
    if _WAIVERS_DISABLED and WAIVERS:
        print(f"  --no-waivers: {len(WAIVERS)} waiver entr(y/ies) "
              f"ignored, all warnings reported.")
    if all_waived:
        suffix = "" if show_waived else " (--show-waived to list)"
        print(f"  {len(all_waived)} warning(s) waived{suffix}.")

if __name__ == "__main__":
    main()


