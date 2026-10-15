#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# chk_sucl.py -- check that each waves/<scenario>.sucl loads in Surfer
# and shows the signals of waves/<scenario>.gtkw (DOC-002, FDT-12a)
#
# Usage, from examples/fe_demo, after the scenarios have run:
#   python3 waves/chk_sucl.py [scenario ...]
# With no names, every scenario that has an FST in out/. Needs a display:
# Surfer opens a window for each file and closes it.
#
# For each scenario, Surfer loads out/<s>/<s>.fst with a copy of the
# command file that ends by saving Surfer's state and exiting. The check
# then reads:
#   - Surfer's log: any ERROR line (a command that does not parse, a
#     variable Surfer cannot find) fails the file
#   - the saved state: the displayed items in order, their tree level,
#     the group names, each variable's path, format and name type
# and compares them with the save file: the same groups in the same
# order, each holding the same signals in the same order, each signal
# with the format of its GTKWave flags, and every name type Global.
import os
import re
import subprocess
import sys
import tempfile

from fe_demo_sigs import S, fst_names

HERE = os.path.dirname(os.path.abspath(__file__))
SURFER = os.environ.get('SURFER', 'surfer')
FMT = {'@28': 'Binary', '@22': 'Hexadecimal', '@24': 'Unsigned'}
ANSI = re.compile(r'\x1b\[[0-9;]*m')


# The save file: [(group, [(GTKWave name, format)])].
def gtkw_groups(path):
    groups = []
    flag = None
    for line in open(path):
        line = line.rstrip('\n')
        if line.startswith('@'):
            flag = line
        elif line.startswith('-'):
            if flag == '@800200':
                groups.append((line[1:], []))
        elif line and not line.startswith('['):
            groups[-1][1].append((line, FMT[flag]))
    return groups


# The saved state: [(level, kind, name, format, name type)] in tree
# order. kind is Group or Variable; a variable's name is its path.
def state_items(text):
    i = text.index('items_tree')
    j = text.index('displayed_items')
    order = re.findall(r'item_ref: \((\d+)\),\s*level: (\d+)', text[i:j])
    items = {}
    for m in re.finditer(r'\((\d+)\): (Group|Variable|Divider)\(\((.*?)'
                         r'\n            \)\),', text[j:], re.S):
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
        else:
            nm = re.search(r'name: "([^"]*)"', body)
            items[m.group(1)] = (m.group(2), nm.group(1) if nm else '',
                                 None, None)
    return [(int(lv),) + items[r] for r, lv in order]


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


def check(scen, tmpdir):
    fst = os.path.join('out', scen, scen + '.fst')
    if not os.path.exists(fst):
        return ['no FST %s' % fst]
    names = fst_names(fst)
    to_surfer = {full: snm for full, _, snm in names.values()}
    exp = gtkw_groups(os.path.join(HERE, scen + '.gtkw'))
    ron = os.path.join(tmpdir, scen + '.ron')
    log = run_surfer(fst, open(os.path.join(HERE, scen + '.sucl')).read(),
                     ron)
    if log is None:
        return ['Surfer did not save its state (3 tries)']
    errs = []
    for line in log.split('\n'):
        if 'ERROR' in line:
            errs.append('surfer: ' + line.strip())
    got = state_items(open(ron).read())
    want = []
    for g, sigs in exp:
        want.append((0, 'Group', g, None, None))
        for full, fmt in sigs:
            want.append((1, 'Variable', to_surfer.get(full, '?' + full),
                         'Some("%s")' % fmt, 'Global'))
    if got != want:
        for k in range(max(len(got), len(want))):
            a = got[k] if k < len(got) else None
            b = want[k] if k < len(want) else None
            if a != b:
                errs.append('item %d: Surfer %s, save file %s' % (k, a, b))
                break
        errs.append('items: Surfer %d, save file %d' % (len(got), len(want)))
    return errs, len(exp), sum(len(s) for _, s in exp)


scens = sys.argv[1:] or [s for s, _ in S
                         if os.path.exists(os.path.join('out', s, s + '.fst'))]
bad = 0
with tempfile.TemporaryDirectory() as tmpdir:
    for scen in scens:
        r = check(scen, tmpdir)
        if isinstance(r, list):
            errs, ng, nv = r, 0, 0
        else:
            errs, ng, nv = r
        if errs:
            bad += 1
            print('FAIL %s' % scen)
            for e in errs:
                print('  ' + e)
        else:
            print('ok   %-20s %2d groups, %3d signals, no Surfer error'
                  % (scen, ng, nv))
print('%d of %d command files checked clean' % (len(scens) - bad,
                                                  len(scens)))
sys.exit(1 if bad else 0)
