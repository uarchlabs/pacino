#!/usr/bin/env python3
"""
check_rva23_coverage.py
RVA23 mandatory instruction decoder coverage gap analysis.

Parses riscv-opcodes extension files as ground truth for RVA23U64 mandatory
instructions, then cross-references the RTL decoder source files to determine
which instructions are covered, partially covered, or absent.

Usage:
    python3 tools/check_rva23_coverage.py [--rtl-dir <dir>]

Output is ASCII only. No third-party packages required.

Re-runnable: as RTL improves, re-run this script to track coverage progress.
"""

import os
import re
import sys
import argparse

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
OPCODES_DIR  = os.path.join(SCRIPT_DIR, 'riscv-opcodes', 'extensions')
DEFAULT_RTL  = os.path.join(PROJECT_ROOT, 'rtl', 'core', 'frontend', 'decode', 'rtl')

# ---------------------------------------------------------------------------
# RVA23U64 mandatory extensions
#
# Each tuple: (display_name, [extension_files], instr_filter_fn_or_None)
#
# instr_filter_fn: callable(name) -> bool
#   When multiple extensions share a file (e.g. rv_zicbo), supply a filter
#   to select only the instructions that belong to this extension.
#   None means accept all non-pseudo instructions from those files.
# ---------------------------------------------------------------------------

def _cbo_om(name):
    return name in ('cbo.clean', 'cbo.flush', 'cbo.inval')

def _cbo_oz(name):
    return name == 'cbo.zero'

def _cbo_op(name):
    return name.startswith('prefetch.')

RVA23_EXTENSIONS = [
    # (display_name, [files], filter_fn, note)
    ('RV64I',   ['rv_i',    'rv64_i'],              None,      ''),
    ('M',        ['rv_m'],                           None,      ''),
    ('A',        ['rv_a',   'rv64_a'],               None,      ''),
    ('F',        ['rv_f'],                           None,      ''),
    ('D',        ['rv_d',   'rv64_d'],               None,      ''),
    ('C',        ['rv_c',   'rv64_c', 'rv_c_d'],     None,      ''),
    ('Zicsr',    ['rv_zicsr'],                       None,      ''),
    ('Zicntr',   ['rv_zicntr'],                      None,
     'pseudo-ops only; all map to CSRRS'),
    ('Zihpm',    [],                                 None,
     'no dedicated opcodes file; hpmcounterN CSRs are pseudo-ops via CSRRS'),
    ('Zfhmin',   ['rv_zfhmin', 'rv_d_zfhmin'],      None,      ''),
    ('Zba',      ['rv_zba',  'rv64_zba'],            None,      ''),
    ('Zbb',      ['rv_zbb',  'rv64_zbb'],            None,      ''),
    ('Zbs',      ['rv_zbs',  'rv64_zbs'],            None,      ''),
    ('Zicbom',   ['rv_zicbo'],                       _cbo_om,   ''),
    ('Zicbop',   ['rv_zicbo'],                       _cbo_op,
     'hint pseudo-ops; encodings are valid ORI instructions'),
    ('Zicboz',   ['rv_zicbo'],                       _cbo_oz,   ''),
    ('V',        ['rv_v'],                           None,      ''),
    ('Zvfhmin',  [],                                 None,
     'no dedicated file in riscv-opcodes; instructions are a subset of rv_v'),
    ('Zcb',      ['rv_zcb',  'rv64_zcb'],            None,      ''),
    ('Zfa',      ['rv_f_zfa', 'rv_d_zfa'],           None,      ''),
    ('H',        ['rv_h',   'rv64_h'],               None,      ''),
]

# ---------------------------------------------------------------------------
# Opcodes whose major opcode group (bits 6..2) is explicitly handled in
# instr_decoder.sv.  Value = handler name for reporting.
# ---------------------------------------------------------------------------

HANDLED_OPGROUPS = {
    0x00: 'OP_LOAD',
    0x01: 'OP_LOAD_FP (FLD/FSW only)',
    0x03: 'OP_MISC_MEM (FENCE)',
    0x04: 'OP_IMM',
    0x05: 'OP_AUIPC',
    0x06: 'OP_IMM_32',
    0x08: 'OP_STORE',
    0x09: 'OP_STORE_FP (FSD only)',
    0x0B: 'OP_AMO (routes to LSU)',
    0x0C: 'OP_REG',
    0x0D: 'OP_LUI',
    0x0E: 'OP_REG_32',
    0x10: 'OP_MADD',
    0x11: 'OP_MSUB',
    0x12: 'OP_NMSUB',
    0x13: 'OP_NMADD',
    0x14: 'OP_FP (routes to FPU)',
    0x15: 'OP_VECTOR (routes to VU, DECODE-004)',
    0x18: 'OP_BRANCH',
    0x19: 'OP_JALR',
    0x1B: 'OP_JAL',
    0x1C: 'OP_SYSTEM',
}

# ---------------------------------------------------------------------------
# Known shared encodings
#
# Some instructions reuse the encoding of another instruction (imm=0 or
# rd=0 special cases). The core string-match approach cannot find them by
# mnemonic alone. This table maps the missing mnemonic to the RTL label
# that handles the shared encoding so the script can confirm coverage
# without changing the matching strategy.
#
# Format:
#   'mnemonic': ('RTL_LABEL', 'short description', 'experiment ref')
#
# When a mnemonic is not found by string match, the script checks here.
# If RTL_LABEL is present in the RTL source, the instruction is reported
# as COVERED* (covered via shared encoding RTL_LABEL).
#
# How to add entries:
#   1. Identify the mnemonic shown as MISSING in script output.
#   2. Find the RTL label or comment that handles the shared encoding.
#   3. Add a new entry with the RTL label and a clear description.
#   4. Record the experiment reference that identified the case.
#
# Entries identified:
#   TOOLS-001: c.sext.w is a pseudo-op alias for c.addiw with imm=0.
#     rvc_expander.sv handles it via the C.ADDIW path (quadrant 1,
#     funct3=001, rd!=0, imm=0). No explicit c.sext.w label exists.
# ---------------------------------------------------------------------------

KNOWN_SHARED_ENCODINGS = {
    # c.sext.w is $pseudo_op for rv64_c::c.addiw with imm=0.
    # rvc_expander.sv handles the general C.ADDIW case; the imm=0
    # specialisation is the c.sext.w encoding. (TOOLS-001)
    'c.sext.w': (
        'C.ADDIW',
        'shared encoding, imm=0 case',
        'TOOLS-001',
    ),
}

# ---------------------------------------------------------------------------
# Known riscv-opcodes tools file gaps
#
# Some instructions are absent from the riscv-opcodes extension files that
# the script uses as ground truth, but are present in the ratified spec
# and are correctly implemented in the RTL. This table documents those gaps
# so the script can confirm coverage regardless of tools-file completeness.
#
# Format:
#   'mnemonic': ('expansion', 'source note', 'experiment ref')
#
# These entries are checked after the normal string-match and shared-
# encoding checks. If a mnemonic is in this table and still MISSING (not
# in any opcodes file for the extension), it is marked COVERED* with the
# note: covered per spec, absent from riscv-opcodes tools file.
#
# How to add entries:
#   1. Verify the instruction is in the ratified spec (not a draft).
#   2. Verify the RTL correctly implements it.
#   3. Confirm the instruction is absent from ALL riscv-opcodes files
#      listed for that extension in RVA23_EXTENSIONS.
#   4. Add an entry with the expansion and a clear source note.
#   5. Record the experiment reference that identified the case.
#
# Entries identified:
#   TOOLS-001: c.zext.w is absent from rv_zcb (the 32-bit Zcb file).
#     It IS present in rv64_zcb and in rvc_expander.sv, so it is already
#     found by normal matching. This entry documents the rv_zcb gap and
#     acts as a safety net if rv64_zcb is ever removed from the Zcb
#     extension file list in RVA23_EXTENSIONS above.
# ---------------------------------------------------------------------------

KNOWN_OPCODES_FILE_GAPS = {
    # c.zext.w absent from rv_zcb; found in rv64_zcb and RTL.
    # Entry is documentation and a safety net only. (TOOLS-001)
    'c.zext.w': (
        'ADD.UW rd,rd,x0',
        'absent from rv_zcb; present in rv64_zcb and rvc_expander.sv',
        'TOOLS-001',
    ),
}

# ---------------------------------------------------------------------------
# Instruction record
# ---------------------------------------------------------------------------

class Instr:
    """Parsed instruction from riscv-opcodes."""
    def __init__(self, name, is_pseudo, bits10):
        self.name      = name       # mnemonic string
        self.is_pseudo = is_pseudo  # True if $pseudo_op
        self.bits10    = bits10     # bits [1:0] (3 = 32-bit, else RVC)

    @property
    def is_rvc(self):
        return self.bits10 != 3

    @property
    def opgroup(self):
        """bits[6:2] decoded from the original line; None if unavailable."""
        return self._opgroup

    @opgroup.setter
    def opgroup(self, v):
        self._opgroup = v

    def __repr__(self):
        return 'Instr({})'.format(self.name)

# ---------------------------------------------------------------------------
# Parse one extension file
# ---------------------------------------------------------------------------

def _parse_field(token):
    """
    Parse a single encoding field token such as '6..2=0x0C' or '1..0=3'.
    Returns (hi, lo, value) or None on parse failure.
    """
    m = re.match(r'^(\d+)\.\.(\d+)=(\S+)$', token)
    if m:
        hi  = int(m.group(1))
        lo  = int(m.group(2))
        val = int(m.group(3), 0)
        return (hi, lo, val)
    m2 = re.match(r'^(\d+)=(\S+)$', token)
    if m2:
        bit = int(m2.group(1))
        val = int(m2.group(2), 0)
        return (bit, bit, val)
    return None


def parse_extension_file(filepath, name_filter=None):
    """
    Parse one riscv-opcodes extension file.
    Returns list of Instr objects.
    name_filter: callable(mnemonic) -> bool, or None for all.
    """
    instrs = []
    if not os.path.isfile(filepath):
        return instrs

    with open(filepath, 'r') as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith('#'):
                continue

            is_pseudo = line.startswith('$pseudo_op')
            if is_pseudo:
                # Format: $pseudo_op <base_ext>::<base_op> <name> <args> ...
                parts = line.split()
                if len(parts) < 3:
                    continue
                mnemonic = parts[2]
                tokens   = parts[3:]
            else:
                parts = line.split()
                if not parts:
                    continue
                mnemonic = parts[0]
                tokens   = parts[1:]

            if name_filter and not name_filter(mnemonic):
                continue

            # Extract bits[1:0] and bits[6:2] from encoding fields.
            # Some instructions use '6..0=0xXX' (full opcode in one field)
            # rather than the split '6..2=X 1..0=3' form.
            bits10  = None
            bits62  = None
            for tok in tokens:
                parsed = _parse_field(tok)
                if parsed is None:
                    continue
                hi, lo, val = parsed
                if hi == 1 and lo == 0:
                    bits10 = val
                if hi == 6 and lo == 2:
                    bits62 = val
                if hi == 6 and lo == 0:
                    # full 7-bit opcode field: split into 6..2 and 1..0
                    bits10 = val & 0x3
                    bits62 = (val >> 2) & 0x1F

            # Default: if no 1..0 field, check last token for =3
            if bits10 is None:
                # Check for '1..0=3' style anywhere
                for tok in tokens:
                    if '1..0=3' in tok or tok == '3':
                        bits10 = 3
                        break
                if bits10 is None:
                    bits10 = 3  # assume 32-bit unless clearly RVC

            instr         = Instr(mnemonic, is_pseudo, bits10)
            instr.opgroup = bits62
            instrs.append(instr)

    return instrs

# ---------------------------------------------------------------------------
# Load all RTL file content
# ---------------------------------------------------------------------------

def load_rtl(rtl_dir):
    """
    Load all .sv files from rtl_dir.
    Returns (combined_text, {filename: text}).
    """
    files = {}
    for fname in os.listdir(rtl_dir):
        if fname.endswith('.sv'):
            fpath = os.path.join(rtl_dir, fname)
            with open(fpath, 'r') as fh:
                files[fname] = fh.read()
    combined = '\n'.join(files.values())
    return combined, files


def name_in_rtl(name, rtl_text):
    """
    Return True if the instruction mnemonic appears in the RTL source.
    Uses word-boundary matching on the uppercased name (for enum/comment hits).
    Also tries the raw mnemonic with common separators.
    """
    # Normalize: replace '.' and '-' for enum-style matching
    normalized = re.sub(r'[.\-]', '_', name).upper()
    # Check for enum/constant occurrence: e.g. ALU_FLD, ALU_ADDW, etc.
    # or a comment containing the mnemonic
    patterns = [
        r'\b' + re.escape(normalized) + r'\b',
        r'\b' + re.escape(name.upper())  + r'\b',
        r'\b' + re.escape(name.lower())  + r'\b',
        r'\b' + re.escape(name)          + r'\b',
    ]
    for pat in patterns:
        if re.search(pat, rtl_text, re.IGNORECASE):
            return True
    return False

# ---------------------------------------------------------------------------
# Exception table lookup
# ---------------------------------------------------------------------------

def _check_exceptions(name, rtl_text):
    """
    Check exception tables for instructions not found by string match.
    Returns a coverage note string if covered via exception, else None.

    Checks KNOWN_SHARED_ENCODINGS first: if the equivalent RTL label is
    present in the RTL source, the instruction is covered via shared
    encoding.

    Falls back to KNOWN_OPCODES_FILE_GAPS: if the mnemonic is listed as
    absent from the riscv-opcodes tools file but is ratified and correctly
    implemented, it is marked covered per spec.
    """
    entry = KNOWN_SHARED_ENCODINGS.get(name)
    if entry:
        rtl_label, desc, _ref = entry
        if name_in_rtl(rtl_label, rtl_text):
            return 'covered via shared encoding: {} ({})'.format(
                rtl_label, desc)

    entry = KNOWN_OPCODES_FILE_GAPS.get(name)
    if entry:
        _expansion, src_note, _ref = entry
        return ('covered per spec, absent from riscv-opcodes tools file'
                ' -- {}'.format(src_note))

    return None

# ---------------------------------------------------------------------------
# Coverage logic per instruction
# ---------------------------------------------------------------------------

COVERED      = 'covered'
COVERED_STAR = 'covered*'  # covered via exception table entry
ROUTED       = 'routed'    # opcode class handled; full decode in FU
PARTIAL_RVC  = 'rvc'       # RVC instruction; handled via rvc_expander
MISSING      = 'missing'


def classify_instr(instr, rtl_text):
    """
    Return one of COVERED, ROUTED, PARTIAL_RVC, MISSING.
    """
    # 16-bit instructions -> check rvc_expander presence
    if instr.is_rvc:
        # rvc_expander handles the full C extension expansion
        # Zcb instructions are 16-bit but not all are in expander yet
        if name_in_rtl(instr.name, rtl_text):
            return COVERED
        # C extension base - rvc_expander covers quadrant 0/1/2
        # Zcb is new (c.lbu, c.lhu etc.) - check by name
        return MISSING

    # 32-bit instructions
    if name_in_rtl(instr.name, rtl_text):
        return COVERED

    # Check if the instruction's opcode class is handled
    if instr.opgroup is not None and instr.opgroup in HANDLED_OPGROUPS:
        return ROUTED

    return MISSING

# ---------------------------------------------------------------------------
# Main analysis
# ---------------------------------------------------------------------------

def run_analysis(rtl_dir, opcodes_dir, strict=False):
    rtl_text, rtl_files = load_rtl(rtl_dir)

    print('=' * 72)
    print('RVA23U64 Instruction Decoder Coverage Analysis')
    print('RTL directory  : {}'.format(rtl_dir))
    print('Opcodes source : {}'.format(opcodes_dir))
    print('RTL files      : {}'.format(', '.join(sorted(rtl_files.keys()))))
    print('=' * 72)

    total_instrs       = 0
    total_covered      = 0    # direct name match + exception table
    total_covered_star = 0    # exception table subset of total_covered
    total_routed       = 0    # opcode class handled, detail in FU
    total_missing      = 0

    ext_results = []

    for ext_tuple in RVA23_EXTENSIONS:
        ext_name, ext_files, filt, note = ext_tuple

        # Collect instructions from all source files for this extension
        instrs = []
        missing_files = []
        for fname in ext_files:
            fpath = os.path.join(opcodes_dir, fname)
            if not os.path.isfile(fpath):
                missing_files.append(fname)
            else:
                instrs.extend(parse_extension_file(fpath, filt))

        # Deduplicate by mnemonic (multiple files may share aliases)
        seen  = set()
        dedup = []
        for ins in instrs:
            if ins.name not in seen:
                seen.add(ins.name)
                dedup.append(ins)
        instrs = dedup

        # Classify each instruction
        covered_list      = []
        covered_star_list = []  # covered via exception table
        routed_list       = []
        missing_list      = []
        pseudo_list       = []

        for ins in instrs:
            if ins.is_pseudo:
                # Pseudo-ops: covered if underlying op is handled
                status = classify_instr(ins, rtl_text)
                if status in (COVERED, ROUTED, PARTIAL_RVC):
                    pseudo_list.append((ins.name, status))
                else:
                    exc = _check_exceptions(ins.name, rtl_text)
                    if exc:
                        covered_star_list.append((ins.name, exc))
                    else:
                        missing_list.append(ins.name)
            else:
                status = classify_instr(ins, rtl_text)
                if status == COVERED:
                    covered_list.append(ins.name)
                elif status == ROUTED:
                    routed_list.append(ins.name)
                elif status == PARTIAL_RVC:
                    covered_list.append(ins.name)
                else:
                    exc = _check_exceptions(ins.name, rtl_text)
                    if exc:
                        covered_star_list.append((ins.name, exc))
                    else:
                        missing_list.append(ins.name)

        n_instrs       = len(instrs)
        n_covered_star = len(covered_star_list)
        n_covered      = (len(covered_list) + len(pseudo_list)
                          + n_covered_star)
        n_routed       = len(routed_list)
        n_missing      = len(missing_list)

        total_instrs       += n_instrs
        total_covered      += n_covered
        total_covered_star += n_covered_star
        total_routed       += n_routed
        total_missing      += n_missing

        ext_results.append({
            'name':      ext_name,
            'note':      note,
            'files':     ext_files,
            'missing_files':      missing_files,
            'instrs':    n_instrs,
            'covered':   n_covered,
            'covered_star': n_covered_star,
            'routed':    n_routed,
            'missing':   n_missing,
            'covered_list':      covered_list,
            'covered_star_list': covered_star_list,
            'routed_list':       routed_list,
            'missing_list':      missing_list,
            'pseudo_list':       pseudo_list,
        })

    # ------------------------------------------------------------------
    # Per-extension detail report
    # ------------------------------------------------------------------
    print()
    for r in ext_results:
        n     = r['instrs']
        nc    = r['covered']
        nr    = r['routed']
        nm    = r['missing']
        name  = r['name']

        if n == 0:
            status_tag = 'NO REF FILE'
        elif nm == 0 and nr == 0:
            status_tag = 'FULL'
        elif nm == 0:
            status_tag = 'ROUTED'   # all covered but some at FU level
        elif nc == 0 and nr == 0:
            status_tag = 'ABSENT'
        else:
            status_tag = 'PARTIAL'

        print('{:<10} [{:<8}] {:>3} instrs | covered {:>3} | routed {:>3}'
              ' | missing {:>3}'.format(
              name, status_tag, n, nc, nr, nm))

        if r['note']:
            print('           NOTE: {}'.format(r['note']))
        if r['missing_files']:
            print('           WARN: ref files not found: {}'.format(
                  ', '.join(r['missing_files'])))

        if r['missing_list']:
            # Group missing in lines of 6 for readability
            ml = sorted(r['missing_list'])
            for i in range(0, len(ml), 6):
                chunk = ml[i:i+6]
                print('           MISSING: {}'.format(
                      ', '.join(chunk)))

        if r['covered_star_list']:
            for cname, cnote in r['covered_star_list']:
                print('           COVERED*: {} -- {}'.format(
                      cname, cnote))

        if r['routed_list'] and nr > 0:
            rl = sorted(r['routed_list'])
            for i in range(0, len(rl), 6):
                chunk = rl[i:i+6]
                print('           ROUTED : {}'.format(
                      ', '.join(chunk)))
        print()

    # ------------------------------------------------------------------
    # Summary counts
    # ------------------------------------------------------------------
    grand_total  = total_covered + total_routed + total_missing
    total_direct = total_covered - total_covered_star
    print('=' * 72)
    print('SUMMARY')
    print('  Total instructions in scope : {}'.format(grand_total))
    print('  Covered (direct RTL match)  : {} ({:.0f}%)'.format(
          total_direct,
          100.0 * total_direct / grand_total if grand_total else 0))
    print('  Covered* (exception table)  : {} ({:.0f}%)'.format(
          total_covered_star,
          100.0 * total_covered_star / grand_total if grand_total else 0))
    print('  Opcode class routed (to FU) : {} ({:.0f}%)'.format(
          total_routed,
          100.0 * total_routed / grand_total if grand_total else 0))
    print('  Missing (opcode unhandled)  : {} ({:.0f}%)'.format(
          total_missing,
          100.0 * total_missing / grand_total if grand_total else 0))
    print()

    # ------------------------------------------------------------------
    # Extension-level classification
    # ------------------------------------------------------------------
    full_ext    = [r['name'] for r in ext_results
                   if r['instrs'] > 0
                   and r['missing'] == 0 and r['routed'] == 0]
    routed_ext  = [r['name'] for r in ext_results
                   if r['instrs'] > 0
                   and r['missing'] == 0 and r['routed'] > 0]
    partial_ext = [r['name'] for r in ext_results
                   if r['instrs'] > 0
                   and r['missing'] > 0
                   and (r['covered'] > 0 or r['routed'] > 0)]
    absent_ext  = [r['name'] for r in ext_results
                   if r['instrs'] > 0
                   and r['covered'] == 0 and r['routed'] == 0]
    noref_ext   = [r['name'] for r in ext_results if r['instrs'] == 0]

    print('Extensions fully name-matched in RTL ({}):'
          .format(len(full_ext)))
    for e in full_ext:
        print('  - {}'.format(e))
    print()

    print('Extensions fully routed at opcode level ({}):'
          .format(len(routed_ext)))
    for e in routed_ext:
        print('  - {}'.format(e))
    print()

    print('Extensions partially covered ({}):'
          .format(len(partial_ext)))
    for e in partial_ext:
        r = next(x for x in ext_results if x['name'] == e)
        print('  - {} : {} missing'.format(e, r['missing']))
    print()

    print('Extensions completely absent from RTL ({}):'
          .format(len(absent_ext)))
    for e in absent_ext:
        print('  - {}'.format(e))
    print()

    print('Extensions with no reference file in riscv-opcodes ({}):'
          .format(len(noref_ext)))
    for e in noref_ext:
        r = next(x for x in ext_results if x['name'] == e)
        print('  - {} : {}'.format(e, r['note'] if r['note'] else
              'no file found'))
    print()

    print('=' * 72)

    # Exit code:
    #   0 - no MISSING instructions found (ROUTED does not trigger failure)
    #   1 - one or more MISSING instructions found
    # With --strict: ROUTED also treated as failure (exit 1).
    if total_missing > 0:
        return 1
    if strict and total_routed > 0:
        return 1
    return 0

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description='RVA23 decoder coverage gap analysis')
    parser.add_argument(
        '--rtl-dir',
        default=DEFAULT_RTL,
        help='Path to RTL source directory '
             '(default: {})'.format(DEFAULT_RTL))
    parser.add_argument(
        '--opcodes-dir',
        default=OPCODES_DIR,
        help='Path to riscv-opcodes extensions dir')
    parser.add_argument(
        '--strict',
        action='store_true',
        default=False,
        help='Treat ROUTED instructions as MISSING (exit 1). '
             'Default: ROUTED is correct by design and does not '
             'trigger failure.')
    args = parser.parse_args()

    if not os.path.isdir(args.opcodes_dir):
        print('ERROR: riscv-opcodes extensions directory not found:')
        print('  {}'.format(args.opcodes_dir))
        print('  Clone riscv-opcodes into tools/riscv-opcodes/ first.')
        return 1

    if not os.path.isdir(args.rtl_dir):
        print('ERROR: RTL directory not found: '
              '{}'.format(args.rtl_dir))
        return 1

    return run_analysis(args.rtl_dir, args.opcodes_dir, args.strict)


if __name__ == '__main__':
    sys.exit(main())
