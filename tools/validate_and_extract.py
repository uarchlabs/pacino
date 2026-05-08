#!/usr/bin/env python3
"""
validate_and_extract.py

Validates a structured experiment file against the project
report template format, then extracts the PROMPT section
to a known output file for Claude Code consumption.

Usage:
  python3 validate_and_extract.py <experiment_file>

Output:
  .claude/tmp/current-prompt.md  -- extracted prompt on success
  Non-zero exit code on validation failure.
"""

import sys
import os
import re

# ---------------------------------------------------------------------------
# Expected structure
# ---------------------------------------------------------------------------

BLOCK_MARKERS_ORDERED = [
    ":: HEADER:START ::",
    ":: HEADER:END ::",
    ":: DISCUSSION:START ::",
    ":: DISCUSSION:END ::",
    ":: PROMPT:START ::",
    ":: PROMPT:END ::",
    ":: RESULTS:START ::",
    ":: RESULTS:END ::",
]

HEADER_FIELDS = [
    "Task ID",
    "Date",
    "Module",
    "Run time",
    "Ctx %",
    "Model",
    "Resume sha",
    "Task:",
    "Status:",
]

PROMPT_SECTIONS_ORDERED = [
    "## Task ID",
    "## Context Loaded",
    "## Hypothesis",
    "## Background",
    "## Binding Previous Decisions",
    "## Specific Requirements",
    "## Constraints",
    "## Deliverables",
]

RESULTS_SECTIONS_ORDERED = [
    "## Summary",
    "## What was delivered",
    "## Test Case Results",
    "## Assumptions made not explicit in the prompt",
    "## Decisions made not explicit in the prompt",
    "## RVA23 compliance risks and gaps noticed",
    "## Deferred Work",
    "## Other Notes",
]

DISCUSSION_SECTIONS_ORDERED = [
    "# Results Discussion",
    "## Claude.code Console Output",
    "## Claude.ai Assessment",
    "## Follow-on Actions",
    "## CLAUDE.md Updates",
    "## Other Planning File Updates",
]

# Placeholder values that indicate an unfilled field.
TASK_ID_PLACEHOLDERS = {"<BLOCK-NUMBER>", "<block-number>"}
PROMPT_TASK_ID_PLACEHOLDERS = {
    "Replace this with the task ID",
    "replace this with the task id",
}

OUTPUT_PATH = ".claude/tmp/current-prompt.md"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def extract_between(lines, start_marker, end_marker):
    """Return lines between start and end markers, exclusive."""
    capturing = False
    result = []
    for line in lines:
        if line.strip() == start_marker:
            capturing = True
            continue
        if line.strip() == end_marker:
            capturing = False
            continue
        if capturing:
            result.append(line)
    return result


def extract_section(lines, section_header):
    """
    Return lines belonging to a ## section, stopping at the
    next ## or # heading or end of content.
    """
    capturing = False
    result = []
    for line in lines:
        stripped = line.strip()
        if stripped == section_header:
            capturing = True
            continue
        if capturing and re.match(r'^#{1,2} ', stripped):
            break
        if capturing:
            result.append(line)
    return result


def check_ordered_items(content_lines, items, section_name):
    """
    Check that all items appear in content_lines in the given
    order. Returns list of error strings (empty if all good).
    """
    errors = []
    last_pos = -1
    for item in items:
        found = -1
        for i, line in enumerate(content_lines):
            if item in line:
                found = i
                break
        if found == -1:
            errors.append(
                f"  [{section_name}] Missing: '{item}'"
            )
        elif found < last_pos:
            errors.append(
                f"  [{section_name}] Out of order: '{item}'"
            )
        else:
            last_pos = found
    return errors


def check_context_loaded(prompt_lines):
    """
    Check every non-blank line between ## Context Loaded
    and ## Hypothesis. Each line must start with @ and
    contain no spaces after the @. Any non-blank line
    that does not start with @ is a format violation.
    Returns list of error strings (empty if all good).
    """
    errors = []
    context_lines = extract_section(
        prompt_lines, "## Context Loaded"
    )
    for line in context_lines:
        stripped = line.strip()
        if not stripped:
            continue
        if not stripped.startswith('@'):
            errors.append(
                f"  [Context Loaded] Invalid entry "
                f"(must start with @): '{stripped}'"
            )
            continue
        token = stripped[1:]
        if not token:
            errors.append(
                f"  [Context Loaded] Empty filename "
                f"after @"
            )
        elif ' ' in token:
            errors.append(
                f"  [Context Loaded] Spaces not allowed "
                f"in filename: '{stripped}'"
            )
    return errors


def check_context_files_exist(prompt_lines):
    """
    Check that every file referenced in ## Context Loaded
    exists on disk relative to the current working directory
    (repo root). Skips entries that already failed format
    validation (no @, spaces in name, empty).
    Returns list of error strings (empty if all good).
    """
    errors = []
    context_lines = extract_section(
        prompt_lines, "## Context Loaded"
    )
    for line in context_lines:
        stripped = line.strip()
        if not stripped:
            continue
        if not stripped.startswith('@'):
            continue
        token = stripped[1:]
        if not token or ' ' in token:
            continue
        if not os.path.isfile(token):
            errors.append(
                f"  [Context Loaded] File not found: "
                f"'{token}'"
            )
    return errors


def extract_header_task_id(header_lines):
    """
    Extract the Task ID value from the header table.
    Returns the value string, or None if not found.
    Expects a markdown table row: | Task ID | <value> | ... |
    """
    for line in header_lines:
        stripped = line.strip()
        if not stripped.startswith('|'):
            continue
        cols = [c.strip() for c in stripped.split('|')]
        # cols[0] is empty (before first |), cols[1] is field
        if len(cols) >= 3 and cols[1] == "Task ID":
            return cols[2] if cols[2] else None
    return None


def extract_prompt_task_id(prompt_lines):
    """
    Extract the Task ID value from the ## Task ID section
    in the prompt block. Returns the first non-empty,
    non-heading content line, or None if not found.
    """
    section_lines = extract_section(prompt_lines, "## Task ID")
    for line in section_lines:
        stripped = line.strip()
        if stripped:
            return stripped
    return None


def check_task_id(header_lines, prompt_lines):
    """
    Validate Task ID in header and prompt block:
      1. Header Task ID must not be a placeholder or empty.
      2. Prompt ## Task ID must not be a placeholder or empty.
      3. Both values must match (case-sensitive).
    Returns list of error strings (empty if all good).
    """
    errors = []

    hdr_id = extract_header_task_id(header_lines)
    prm_id = extract_prompt_task_id(prompt_lines)

    # -- Header Task ID --
    if hdr_id is None:
        errors.append(
            "  [Task ID] Header Task ID field not found "
            "or empty."
        )
    elif hdr_id in TASK_ID_PLACEHOLDERS:
        errors.append(
            f"  [Task ID] Header Task ID is still a "
            f"placeholder: '{hdr_id}'"
        )

    # -- Prompt Task ID --
    if prm_id is None:
        errors.append(
            "  [Task ID] Prompt ## Task ID section is "
            "empty or missing."
        )
    elif prm_id.lower() in {p.lower()
                             for p in PROMPT_TASK_ID_PLACEHOLDERS}:
        errors.append(
            f"  [Task ID] Prompt ## Task ID is still a "
            f"placeholder: '{prm_id}'"
        )

    # -- Consistency --
    if (hdr_id and prm_id
            and hdr_id not in TASK_ID_PLACEHOLDERS
            and prm_id.lower() not in {
                p.lower() for p in PROMPT_TASK_ID_PLACEHOLDERS
            }):
        if hdr_id != prm_id:
            errors.append(
                f"  [Task ID] Header ('{hdr_id}') and "
                f"prompt ('{prm_id}') Task IDs do not match."
            )

    return errors


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def validate(lines):
    """
    Run all validation checks. Returns a list of error strings.
    Empty list means validation passed.
    """
    errors = []
    text = "".join(lines)

    # -- 1. Block markers present and in order --
    last_pos = -1
    for marker in BLOCK_MARKERS_ORDERED:
        pos = text.find(marker)
        if pos == -1:
            errors.append(
                f"  [Block markers] Missing: '{marker}'"
            )
        elif pos < last_pos:
            errors.append(
                f"  [Block markers] Out of order: '{marker}'"
            )
        else:
            last_pos = pos

    # Abort further checks if block markers are broken --
    # section extraction will be unreliable.
    if errors:
        return errors

    # -- 2. HEADER fields --
    header_lines = extract_between(
        lines, ":: HEADER:START ::", ":: HEADER:END ::"
    )
    errors += check_ordered_items(
        header_lines, HEADER_FIELDS, "Header"
    )

    # -- 3. PROMPT subsections --
    prompt_lines = extract_between(
        lines, ":: PROMPT:START ::", ":: PROMPT:END ::"
    )
    errors += check_ordered_items(
        prompt_lines, PROMPT_SECTIONS_ORDERED, "Prompt"
    )

    # -- 4. Context Loaded @ prefix and format --
    errors += check_context_loaded(prompt_lines)

    # -- 5. Context Loaded files exist on disk --
    errors += check_context_files_exist(prompt_lines)

    # -- 6. RESULTS subsections --
    results_lines = extract_between(
        lines, ":: RESULTS:START ::", ":: RESULTS:END ::"
    )
    errors += check_ordered_items(
        results_lines, RESULTS_SECTIONS_ORDERED, "Results"
    )

    # -- 7. DISCUSSION subsections --
    discussion_lines = extract_between(
        lines, ":: DISCUSSION:START ::", ":: DISCUSSION:END ::"
    )
    errors += check_ordered_items(
        discussion_lines,
        DISCUSSION_SECTIONS_ORDERED,
        "Discussion"
    )

    # -- 8. Task ID populated and consistent --
    errors += check_task_id(header_lines, prompt_lines)

    return errors


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) != 2:
        print(
            "Usage: python3 validate_and_extract.py "
            "<experiment_file>"
        )
        sys.exit(1)

    experiment_file = sys.argv[1]

    if not os.path.isfile(experiment_file):
        print(f"ERROR: File not found: {experiment_file}")
        sys.exit(1)

    with open(experiment_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    print(f"Validating: {experiment_file}")

    errors = validate(lines)

    if errors:
        print("\nVALIDATION FAILED:")
        for e in errors:
            print(e)
        sys.exit(1)

    print("Validation passed.")

    # Extract prompt section
    prompt_lines = extract_between(
        lines, ":: PROMPT:START ::", ":: PROMPT:END ::"
    )

    # Write output
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.writelines(prompt_lines)

    print(f"Prompt extracted to: {OUTPUT_PATH}")
    sys.exit(0)


if __name__ == "__main__":
    main()

