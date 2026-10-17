#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# mk_sucl.py -- write waves/<scenario>.sucl, the Surfer command file of
# each scenario (DOC-002, DOC-004, fe_demo_tb_decisions.md FDT-1,
# FDT-12a, FDT-12c)
#
# Usage, from examples/fe_demo, after the scenarios have run:
#   python3 waves/mk_sucl.py out/fd02_steady/fd02_steady.fst
#
# The signals and groups are fe_demo_sigs.S; every scenario runs the
# same model, so the FST given names them all. A name not in that FST
# stops the script. make view S=<scenario> loads the file:
#   surfer out/<scenario>/<scenario>.fst -c waves/<scenario>.sucl
#
# HOW A GROUP IS BUILT. A Surfer command file has no command that adds
# a variable to a named group, or that selects a range of items. Surfer
# 0.7 does this:
#   - variable_add with no item focused appends at the end, top level,
#     and leaves nothing focused
#   - item_focus <i> focuses visible item i (written as hex digits
#     mapped to the letters a-p: 0 -> a, 26 -> bk)
#   - group_marked <name> makes a group of the focused item, in its
#     place, so the item moves to i + 1 inside it
#   - variable_add with an item focused inserts after it at its level
#     and moves the focus to the new item
#   - item_set_format sets the focused item's format
# So each group is: add its first signal, focus it, group it, focus it
# inside the group, set its format, then add each further signal and
# set its format; then unfocus. The visible index counts each group
# row and each signal row (every group is open).
#
# NAMES AND FORMATS (FDT-12a). variable_force_name_type Unique shows
# each name as the shortest suffix of its path that identifies it.
# Formats: tb.clk Clock, tb.rstn Bit, tb.cyc Unsigned, an enum-typed
# signal Enum (the value names of its FST enum table), every other
# signal fe_demo_sigs.radix: Binary, Hexadecimal or Unsigned.
#
# MARKERS (FDT-12c). A scenario whose description docs/<scenario>.md is
# in the FDT-13 form gets one marker per event of its section 4 table.
# The description is in that form when its level-2 headings are, in
# order, 1. What the scenario shows, 2. The program, 3. Walkthrough,
# 4. Events, and optionally 5. Notes. The table's rows are | cyc |
# event | other |; a row with a cyc value starts an event and a row
# with an empty cyc continues the one above. Each event is a marker
#   marker_set c<cyc>_<label> <time>
# <label> is the event text up to its first ';', ':', ',' or '(',
# at most LABEL_WORDS words, joined by '_' (a marker name is one word,
# and '#' starts a comment in a command file). <time> is the first FST
# time at which tb.cyc equals <cyc> with tb.rstn high, read from that
# scenario's own FST, out/<scenario>/<scenario>.fst. A table this
# script cannot read, or a cyc the FST does not reach, stops it with
# the file and row.
#
# THE OPENING VIEW. With markers, zoom_to opens the view at the first
# marker: VIEW_BEFORE cycles before it to VIEW_AFTER cycles after it.
# goto_marker cannot do this: Surfer 0.7 parses the whole command file
# before it runs any of it, and goto_marker only accepts the name of a
# marker that exists when it is parsed. Without markers, zoom_fit.
import os
import re
import sys

from fe_demo_sigs import S, fst_names, fst_values, radix

if len(sys.argv) != 2:
    sys.exit('usage: mk_sucl.py <fst>')
FST = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(HERE, '..', 'docs')
OUT = os.path.join(HERE, '..', 'out')

LABEL_WORDS = 6
VIEW_BEFORE = 2
VIEW_AFTER = 30

# The level-2 headings of a description in the FDT-13 form.
FORM = ['1. What the scenario shows', '2. The program', '3. Walkthrough',
        '4. Events']
NOTES = '5. Notes'

names = fst_names(FST)
missing = []

# Surfer's translator of each format of fe_demo_sigs.radix().
FMT = {'bin': 'Binary', 'hex': 'Hexadecimal', 'dec': 'Unsigned'}
# The formats FDT-12a names for the clock group.
CLK_FMT = {'tb.clk': 'Clock', 'tb.rstn': 'Bit', 'tb.cyc': 'Unsigned'}


class TableError(Exception):
    pass


# Surfer's item index: hex digits mapped to a-p (libsurfer util.rs,
# alpha_idx_to_uint_idx).
def alpha(i):
    return ''.join(chr(ord('a') + int(c, 16)) for c in '%x' % i)


def fmt(path, width, enum):
    if path in CLK_FMT:
        return CLK_FMT[path]
    if enum:
        return 'Enum'
    return FMT[radix(width, path)]


# The events of a description in the FDT-13 form: [(row, cyc, text)],
# row the line number of the event's first table row. None when the
# description is absent or not in that form.
def events(path):
    if not os.path.exists(path):
        return None
    lines = open(path).read().split('\n')
    heads = [(n, ln[3:].strip()) for n, ln in enumerate(lines, 1)
             if ln.startswith('## ')]
    titles = [t for _, t in heads]
    if titles not in (FORM, FORM + [NOTES]):
        return None
    start = heads[3][0]
    end = heads[4][0] - 1 if len(heads) > 4 else len(lines)
    rows = [(n, ln.strip()) for n, ln in enumerate(lines[start:end],
                                                   start + 1)
            if ln.strip().startswith('|')]

    def cells(n, ln):
        if not ln.endswith('|'):
            raise TableError('row does not end in |', n)
        c = [x.strip() for x in ln[1:-1].split('|')]
        if len(c) != 3:
            raise TableError('%d columns, not 3' % len(c), n)
        return c

    if len(rows) < 3:
        raise TableError('no event table in section 4', start)
    head = cells(*rows[0])
    if head[0] != 'cyc':
        raise TableError('column 0 is "%s", not "cyc"' % head[0], rows[0][0])
    if not all(re.fullmatch(r':?-+:?', c) for c in cells(*rows[1])):
        raise TableError('no separator row under the header', rows[1][0])
    ev = []
    for n, ln in rows[2:]:
        cyc, text, _ = cells(n, ln)
        if cyc:
            if not re.fullmatch(r'\d+', cyc):
                raise TableError('cyc "%s" is not a number' % cyc, n)
            ev.append([n, int(cyc), text])
        elif not ev:
            raise TableError('a continuation row before any event', n)
        else:
            ev[-1][2] += ' ' + text
    return [tuple(e) for e in ev]


def label(text):
    text = re.split(r'[;:,(]', text.replace('`', ''))[0]
    words = [re.sub(r'[^A-Za-z0-9_]', '', w) for w in text.split()]
    return '_'.join([w for w in words if w][:LABEL_WORDS])


# The first time at which cyc holds each value with rstn high, and the
# clock period, from a scenario's own FST. cyc is 0 from the start of
# reset, so the time of cyc 0 is the release of reset.
def level(changes, t):
    return [x for tx, x in changes if tx <= t][-1]


def cyc_times(fst):
    v = fst_values(fst, ['tb.clk', 'tb.rstn', 'tb.cyc'])
    rise = [t for t, x in v['tb.clk'] if x == 1]
    rstn, cyc = v['tb.rstn'], v['tb.cyc']
    first = {}
    for k, (t, c) in enumerate(cyc):
        if c is None or c in first:
            continue
        if level(rstn, t) == 1:
            first[c] = t
            continue
        end = cyc[k + 1][0] if k + 1 < len(cyc) else None
        up = [tr for tr, x in rstn
              if x == 1 and tr > t and (end is None or tr < end)]
        if up:
            first[c] = up[0]
    return first, rise[1] - rise[0]


def markers(scen):
    doc = os.path.join(DOCS, scen + '.md')
    rel = os.path.join('docs', scen + '.md')
    try:
        ev = events(doc)
    except TableError as e:
        sys.exit('%s line %d: %s' % (rel, e.args[1], e.args[0]))
    if ev is None:
        return None, None
    fst = os.path.join(OUT, scen, scen + '.fst')
    if not os.path.exists(fst):
        sys.exit('%s has events; its FST %s is missing (make %s)'
                 % (rel, os.path.relpath(fst, os.path.join(HERE, '..')),
                    scen))
    first, period = cyc_times(fst)
    out = []
    for n, cyc, text in ev:
        lbl = label(text)
        if not lbl:
            sys.exit('%s line %d: no label in "%s"' % (rel, n, text))
        if cyc not in first:
            sys.exit('%s line %d: cyc %d is not in %s'
                     % (rel, n, cyc, os.path.basename(fst)))
        out.append(('c%d_%s' % (cyc, lbl), first[cyc]))
    return out, period


out = {}
nmark = {}
for scen, groups in S:
    lines = ['# %s, examples/fe_demo (DOC-002, DOC-004); written by '
             'waves/mk_sucl.py' % scen,
             '# surfer out/%s/%s.fst -c waves/%s.sucl' % (scen, scen, scen),
             'variable_force_name_type Unique']
    n = 0                                  # visible items so far
    for g, sigs in groups:
        rows = []
        for p in sigs:
            if p not in names:
                missing.append(p)
                continue
            width, snm, enum = names[p]
            rows.append((snm, fmt(p, width, enum)))
        if not rows:
            continue
        lines += ['# group ' + g,
                  'variable_add ' + rows[0][0],
                  'item_focus ' + alpha(n),
                  'group_marked ' + g,
                  'item_focus ' + alpha(n + 1),
                  'item_set_format ' + rows[0][1]]
        for snm, f in rows[1:]:
            lines += ['variable_add ' + snm, 'item_set_format ' + f]
        lines += ['item_unfocus']
        n += 1 + len(rows)
    if missing:
        continue
    mk, period = markers(scen)
    if mk:
        lines += ['# markers, from docs/%s.md section 4' % scen]
        lines += ['marker_set %s %d' % m for m in mk]
        t0 = mk[0][1]
        lines += ['item_unfocus',
                  'zoom_to %d %d' % (max(0, t0 - VIEW_BEFORE * period),
                                     t0 + VIEW_AFTER * period)]
        nmark[scen] = len(mk)
    else:
        lines += ['zoom_fit']
    out[scen] = '\n'.join(lines) + '\n'

if missing:
    for m in sorted(set(missing)):
        print('not in the FST: ' + m, file=sys.stderr)
    sys.exit(1)
for scen, text in out.items():
    with open(os.path.join(HERE, scen + '.sucl'), 'w') as f:
        f.write(text)
print('wrote %d command files; markers in %s' %
      (len(out), ', '.join('%s (%d)' % kv for kv in nmark.items()) or
       'none'))
