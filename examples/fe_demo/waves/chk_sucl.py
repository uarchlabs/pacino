#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# chk_sucl.py -- check that each waves/<scenario>.sucl loads in Surfer
# and shows what fe_demo_sigs.py, FDT-12a and FDT-12c call for (DOC-002,
# DOC-004)
#
# Usage, from examples/fe_demo, after the scenarios have run:
#   python3 waves/chk_sucl.py [scenario ...]
# With no names, every scenario that has an FST in out/. Needs a display:
# Surfer opens a window for each file and closes it. The viewer is the
# environment's SURFER, else ~/.cargo/bin/surfer, the default rtl/Vars.mk
# gives make view (FDT-9a).
#
# For each scenario, Surfer loads out/<s>/<s>.fst with a copy of the
# command file that ends by saving Surfer's state and exiting. The check
# then reads:
#   - Surfer's log: any ERROR or WARN line (a command that does not
#     parse, a variable Surfer cannot find, a format it cannot apply)
#     fails the file
#   - the saved state: the displayed items in order, their tree level,
#     the group names, each variable's path, format and name type, the
#     markers with their times, and the view
# and compares them with what this script derives itself, without
# reading the command file or mk_sucl.py:
#   - signals, groups and order: fe_demo_sigs.S, each path as Surfer
#     names it in the FST (fe_demo_sigs.fst_names)
#   - name type: Unique on every variable (FDT-12a)
#   - formats: tb.clk Clock, tb.rstn Bit, tb.cyc Unsigned, a signal the
#     FST marks enum-typed Enum, every other signal fe_demo_sigs.radix
#     (FDT-12a); the enum marks are read here from the FST header
#   - markers: one per event of docs/<s>.md section 4 when the
#     description is in the FDT-13 form, none otherwise; in table order,
#     each named c<cyc>_<label>, at a time where the FST has tb.cyc equal
#     to <cyc> with tb.rstn high and did not have it just before
#     (FDT-12c)
#   - the view: zoomed in and holding the first marker; the whole run
#     when there are no markers
import os
import re
import shutil
import subprocess
import sys
import tempfile

from fe_demo_sigs import S, fst_header, fst_names, fst_values, radix

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(HERE, '..', 'docs')
SURFER = os.environ.get('SURFER',
                        os.path.expanduser('~/.cargo/bin/surfer'))
FMT = {'bin': 'Binary', 'hex': 'Hexadecimal', 'dec': 'Unsigned'}
CLK_FMT = {'tb.clk': 'Clock', 'tb.rstn': 'Bit', 'tb.cyc': 'Unsigned'}
FORM = ['1. What the scenario shows', '2. The program', '3. Walkthrough',
        '4. Events']
ANSI = re.compile(r'\x1b\[[0-9;]*m')


# The paths of the enum-typed signals: each $var that follows an enum
# table reference, '$attrbegin misc 07 "" <table> $end'.
def enum_paths(fst):
    paths = set()
    scope = []
    ref = False
    for line in fst_header(fst).split('\n'):
        w = line.split()
        if not w:
            continue
        if w[:4] == ['$attrbegin', 'misc', '07', '""']:
            ref = True
        elif w[0] == '$scope':
            scope.append(w[2])
        elif w[0] == '$upscope':
            scope.pop()
        elif w[0] == '$var':
            if ref:
                paths.add('.'.join(scope + [w[4]]))
            ref = False
    return paths


# The cyc values of the events in docs/<s>.md section 4, in table
# order; [] when the description is absent or not in the FDT-13 form.
def event_cycs(scen):
    path = os.path.join(DOCS, scen + '.md')
    if not os.path.exists(path):
        return []
    text = open(path).read()
    heads = re.findall(r'^## (.*?)\s*$', text, re.M)
    if heads not in (FORM, FORM + ['5. Notes']):
        return []
    sec = text.split('\n## 4. Events')[1].split('\n## ')[0]
    return [int(m) for m in re.findall(r'^\|\s*(\d+)\s*\|', sec, re.M)]


# A BigInt as the saved state writes it: (sign, [32-bit digits]).
def bigint(s):
    sign, digits = re.fullmatch(r'\((-?\d+),\s*\[([\d,\s]*)\]\)',
                                re.sub(r'\s+', ' ', s).strip()).groups()
    v = sum(int(d) << (32 * i) for i, d in
            enumerate(x for x in digits.replace(' ', '').split(',') if x))
    return -v if int(sign) < 0 else v


# The saved state: items [(level, kind, name, format, name type)] in
# tree order, a variable's name its path and a marker's name with its
# time; and the view (left, right) as fractions of the run.
def state(text):
    i = text.index('items_tree')
    j = text.index('displayed_items')
    order = re.findall(r'item_ref: \((\d+)\),\s*level: (\d+)', text[i:j])
    mk = {}
    m = re.search(r'\n        markers: \{(.*?)\n        \},', text, re.S)
    if m:
        for idx, val in re.findall(r'(\d+): (\(-?\d+, \[[\d,\s]*\]\))',
                                   m.group(1)):
            mk[idx] = bigint(val)
    items = {}
    for m in re.finditer(r'\((\d+)\): (Group|Variable|Divider|Marker)'
                         r'\(\((.*?)\n            \)\),', text[j:], re.S):
        body = m.group(3)
        if m.group(2) == 'Variable':
            p = re.search(r'variable_ref: \(\s*path: \(\s*strs: \['
                          r'((?:\s*"[^"]*",)*)\s*\].*?name: "([^"]*)"',
                          body, re.S)
            path = re.findall(r'"([^"]*)"', p.group(1)) + [p.group(2)]
            fmt = re.search(r'\n                format: ([^,]*),', body)
            nt = re.search(r'display_name_type: (\w+)', body)
            items[m.group(1)] = ('Variable', '.'.join(path),
                                 fmt.group(1) if fmt else None,
                                 nt.group(1) if nt else None)
        elif m.group(2) == 'Marker':
            nm = re.search(r'name: Some\("([^"]*)"\)', body)
            idx = re.search(r'idx: (\d+)', body).group(1)
            items[m.group(1)] = ('Marker', (nm.group(1) if nm else None,
                                            mk.get(idx)), None, None)
        else:
            nm = re.search(r'name: "([^"]*)"', body)
            items[m.group(1)] = (m.group(2), nm.group(1) if nm else '',
                                 None, None)
    vp = re.search(r'viewports: \[\s*\(\s*curr_left: \(([\d.e+-]+)\),'
                   r'\s*curr_right: \(([\d.e+-]+)\)', text)
    return ([(int(lv),) + items[r] for r, lv in order],
            (float(vp.group(1)), float(vp.group(2))))


def run_surfer(fst, cmds, ron):
    with tempfile.NamedTemporaryFile('w', suffix='.sucl', delete=False) as f:
        f.write(cmds + 'save_state_as %s\nexit\n' % ron)
        tmp = f.name
    try:
        for _ in range(3):
            if os.path.exists(ron):
                os.remove(ron)
            try:
                r = subprocess.run([SURFER, fst, '-c', tmp],
                                   capture_output=True, text=True,
                                   timeout=90,
                                   env=dict(os.environ, RUST_LOG='info'))
                log = ANSI.sub('', r.stdout + r.stderr)
            except subprocess.TimeoutExpired:
                continue
            if os.path.exists(ron):
                return log
        return None
    finally:
        os.remove(tmp)


# The value of a signal at time t from its changes.
def level(changes, t):
    v = [x for tx, x in changes if tx <= t]
    return v[-1] if v else None


def check_markers(scen, fst, got, view):
    errs = []
    cycs = event_cycs(scen)
    mk = [it[2] for it in got if it[1] == 'Marker']
    if len(mk) != len(cycs):
        errs.append('markers: Surfer %d, docs/%s.md %d events'
                    % (len(mk), scen, len(cycs)))
    v = fst_values(fst, ['tb.rstn', 'tb.cyc'])
    end = v['tb.cyc'][-1][0]
    for (name, t), c in zip(mk, cycs):
        if not name or not re.fullmatch(r'c%d_\w+' % c, name):
            errs.append('marker %s: name is not c%d_<label>' % (name, c))
        if t is None:
            errs.append('marker %s: no time' % name)
            continue
        here = (level(v['tb.cyc'], t), level(v['tb.rstn'], t))
        before = (level(v['tb.cyc'], t - 1), level(v['tb.rstn'], t - 1))
        if here != (c, 1) or before == (c, 1):
            errs.append('marker %s at %d: FST has cyc %s rstn %s there, '
                        'cyc %s rstn %s just before'
                        % ((name, t) + here + before))
    left, right = view
    if mk and mk[0][1] is not None:
        t0 = mk[0][1] / end
        if not (left <= t0 <= right and right - left < 0.5):
            errs.append('view %.4f to %.4f of the run: not at the first '
                        'marker (%.4f)' % (left, right, t0))
    elif not mk and (left, right) != (0.0, 1.0):
        errs.append('view %.4f to %.4f of the run, no markers: not the '
                    'whole run' % (left, right))
    return errs, len(mk)


def check(scen, tmpdir):
    fst = os.path.join('out', scen, scen + '.fst')
    if not os.path.exists(fst):
        return ['no FST %s' % fst], 0, 0, 0
    names = fst_names(fst)
    enums = enum_paths(fst)
    exp = dict(S)[scen]
    ron = os.path.join(tmpdir, scen + '.ron')
    log = run_surfer(fst, open(os.path.join(HERE, scen + '.sucl')).read(),
                     ron)
    if log is None:
        return ['Surfer did not save its state (3 tries)'], 0, 0, 0
    errs = []
    for line in log.split('\n'):
        if 'ERROR' in line or 'WARN' in line:
            errs.append('surfer: ' + line.strip())
    got, view = state(open(ron).read())
    want = []
    for g, sigs in exp:
        want.append((0, 'Group', g, None, None))
        for p in sigs:
            width, snm, _ = names[p]
            f = CLK_FMT.get(p) or ('Enum' if p in enums else
                                   FMT[radix(width, p)])
            want.append((1, 'Variable', snm, 'Some("%s")' % f, 'Unique'))
    vars_got = [it for it in got if it[1] != 'Marker']
    if vars_got != want:
        for k in range(max(len(vars_got), len(want))):
            a = vars_got[k] if k < len(vars_got) else None
            b = want[k] if k < len(want) else None
            if a != b:
                errs.append('item %d: Surfer %s, expected %s' % (k, a, b))
                break
        errs.append('items: Surfer %d, expected %d' % (len(vars_got),
                                                       len(want)))
    tail = got[len(vars_got):]
    if any(it[1] != 'Marker' or it[0] != 0 for it in tail):
        errs.append('markers are not top-level items after the groups')
    e, nm = check_markers(scen, fst, got, view)
    return errs + e, len(exp), sum(len(s) for _, s in exp), nm


# The viewer must exist before any scenario is tried; otherwise every
# run_surfer call would raise FileNotFoundError.
if not shutil.which(SURFER):
    sys.exit('chk_sucl.py: Surfer not found: SURFER=%s; set SURFER to the '
             'surfer executable' % SURFER)

scens = sys.argv[1:] or [s for s, _ in S
                         if os.path.exists(os.path.join('out', s, s + '.fst'))]
bad = 0
with tempfile.TemporaryDirectory() as tmpdir:
    for scen in scens:
        errs, ng, nv, nm = check(scen, tmpdir)
        if errs:
            bad += 1
            print('FAIL %s' % scen)
            for e in errs:
                print('  ' + e)
        else:
            print('ok   %-20s %2d groups, %3d signals, %2d markers, '
                  'no Surfer error' % (scen, ng, nv, nm))
print('%d of %d command files checked clean' % (len(scens) - bad,
                                                  len(scens)))
sys.exit(1 if bad else 0)
