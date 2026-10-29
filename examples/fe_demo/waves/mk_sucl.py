#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# mk_sucl.py -- write waves/<scenario>.sucl, the Surfer command file of
# each scenario (DOC-002, DOC-004, DOC-006, DOC-009,
# fe_demo_tb_decisions.md FDT-1, FDT-10c, FDT-12a, FDT-12c)
#
# Usage, from examples/fe_demo, after the scenarios have run:
#   python3 waves/mk_sucl.py [scenario ...]
# With no names, every scenario of fe_demo_sigs.NAMES. The Makefile
# runs the other form, --svh <file>, before each compile (below).
#
# THE FST OF EACH SCENARIO (DOC-006). The scenarios run on two models,
# at one and two prediction slots (Makefile SCEN_2S), whose FSTs name
# different signals. Each command file is written from its own
# scenario's FST, out/<scenario>/<scenario>.fst: its slot count
# (fe_demo_sigs.nslots) builds the scenario's signal list
# (fe_demo_sigs.scenarios), and its names give each signal's Surfer
# name, width and enum type. A missing FST, or a listed signal the FST
# does not have, stops the script before any file is written. make view
# S=<scenario> loads the file:
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
# Every format is fe_demo_sigs.fmt's, from the table FORMATS (DOC-006):
# among them tb.clk Clock, tb.rstn Bit, tb.cyc Unsigned and an
# enum-typed signal Enum (the value names of its FST enum table). A
# signal no row of the table matches stops the script.
#
# MARKERS (FDT-12c). A scenario gets one marker per event of the table
# of its description's level-2 section headed Events, with or without a
# section number ("## 4. Events", "## Events"), whether or not the
# description is in the FDT-13 form (Jeff, session-082, DOC-009). The
# section ends at the next level-1 or level-2 heading. The table's rows
# are | cyc | event | other |; a row with a cyc value starts an event and
# a row with an empty cyc continues the one above. Each event is a
# marker
#   marker_set c<cyc>_<label> <time>
# <label> is the event text up to its first ';', ':', ',' or '(',
# at most LABEL_WORDS words, joined by '_' (a marker name is one word,
# and '#' starts a comment in a command file). <time> is the first FST
# time at which tb.cyc equals <cyc> with tb.rstn high, read from that
# scenario's own FST, out/<scenario>/<scenario>.fst. A description with
# no Events section that cites no cycle as cyc <n> has no markers. One
# that cites a cycle and has no Events section, a table this script
# cannot read, or a cyc the FST does not reach, stops it with the file
# and line.
#
# THE TESTBENCH'S TABLE (FDT-10c, DOC-009). With --svh <file> the script
# reads only the descriptions and writes <file>, an include of module tb
# that gives each event of each table to tb/fe_demo_events.svh as
#   evt_row("<label>", <cyc>, <line>);
# so the expected cycle of every event check is the description's. The
# Makefile writes it into each model's directory before the compile; a
# description it cannot read stops the build. No FST is read and
# fe_demo_sigs.py is not loaded.
#   python3 waves/mk_sucl.py --svh obj_fe_demo/fe_demo_evt_tbl.svh
#
# THE OPENING VIEW. With markers, zoom_to opens the view at the first
# marker: VIEW_BEFORE cycles before it to VIEW_AFTER cycles after it.
# goto_marker cannot do this: Surfer 0.7 parses the whole command file
# before it runs any of it, and goto_marker only accepts the name of a
# marker that exists when it is parsed. Without markers, zoom_fit.
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(HERE, '..', 'docs')
OUT = os.path.join(HERE, '..', 'out')

LABEL_WORDS = 6
VIEW_BEFORE = 2
VIEW_AFTER = 30

# The Events heading, with or without a section number; a cycle cited
# as cyc <n> (FDT-12c).
EVENTS_HEAD = re.compile(r'## (?:(\d+)\. )?Events\s*$')
CYC_CITE = re.compile(r'\bcyc \d+')

missing = []
nofmt = []


class TableError(Exception):
    pass


# Surfer's item index: hex digits mapped to a-p (libsurfer util.rs,
# alpha_idx_to_uint_idx).
def alpha(i):
    return ''.join(chr(ord('a') + int(c, 16)) for c in '%x' % i)


# The events of a description: [(row, cyc, text)], row the line number
# of the event's first table row, and the section number of its Events
# heading ('' when it has none). (None, None) when the description is
# absent, or has no Events section and cites no cycle.
def events(path):
    if not os.path.exists(path):
        return None, None
    lines = open(path).read().split('\n')
    head = [(n, m) for n, m in ((n, EVENTS_HEAD.fullmatch(ln))
                                for n, ln in enumerate(lines, 1)) if m]
    if not head:
        cite = [n for n, ln in enumerate(lines, 1) if CYC_CITE.search(ln)]
        if cite:
            raise TableError('cites cyc <n> and has no Events section',
                             cite[0])
        return None, None
    if len(head) > 1:
        raise TableError('a second Events section', head[1][0])
    start, num = head[0][0], head[0][1].group(1) or ''
    end = next((n - 1 for n, ln in enumerate(lines, 1)
                if n > start and re.match(r'#{1,2} ', ln)), len(lines))
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
        raise TableError('no event table in the Events section', start)
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
    return [tuple(e) for e in ev], num


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


# The events of docs/<scen>.md, each with a label; a description this
# script cannot read stops it with the file and line.
def read_events(scen):
    rel = os.path.join('docs', scen + '.md')
    try:
        ev, num = events(os.path.join(DOCS, scen + '.md'))
    except TableError as e:
        sys.exit('%s line %d: %s' % (rel, e.args[1], e.args[0]))
    for n, _, text in ev or []:
        if not label(text):
            sys.exit('%s line %d: no label in "%s"' % (rel, n, text))
    return ev, num


def markers(scen):
    rel = os.path.join('docs', scen + '.md')
    ev, num = read_events(scen)
    if ev is None:
        return None, None, None
    fst = os.path.join(OUT, scen, scen + '.fst')
    if not os.path.exists(fst):
        sys.exit('%s has events; its FST %s is missing (make %s)'
                 % (rel, os.path.relpath(fst, os.path.join(HERE, '..')),
                    scen))
    first, period = cyc_times(fst)
    out = []
    for n, cyc, text in ev:
        if cyc not in first:
            sys.exit('%s line %d: cyc %d is not in %s'
                     % (rel, n, cyc, os.path.basename(fst)))
        out.append(('c%d_%s' % (cyc, label(text)), first[cyc]))
    return out, period, num


# --svh: the testbench's table (FDT-10c). Every description
# docs/fdNN_<name>.md, in name order. tb/fe_demo_events.svh matches a
# row with its check by label, so a label must be unique in its table.
def write_svh(path):
    scens = sorted(f[:-3] for f in os.listdir(DOCS)
                   if re.fullmatch(r'fd\d\d_\w+\.md', f))
    lines = ['// %s -- written by examples/fe_demo/waves/mk_sucl.py --svh'
             % os.path.basename(path),
             '// from the Events tables of docs/fdNN_<name>.md (FDT-10c,',
             '// FDT-12c). Included inside module tb by tb_fe_demo.sv.',
             '// Do not edit: the descriptions are the source.',
             '  function automatic void evt_table(input string nm);',
             '    case (nm)']
    for scen in scens:
        ev, _ = read_events(scen)
        if not ev:
            continue
        seen = {}
        lines += ['      "%s": begin' % scen]
        for n, cyc, text in ev:
            lbl = label(text)
            if lbl in seen:
                sys.exit('docs/%s.md line %d: label %s is also the label '
                         'of line %d' % (scen, n, lbl, seen[lbl]))
            seen[lbl] = n
            lines += ['        evt_row("%s", %d, %d);' % (lbl, cyc, n)]
        lines += ['      end']
    lines += ['      default: ;', '    endcase', '  endfunction']
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')


args = sys.argv[1:]
if args[:1] == ['--svh']:
    if len(args) != 2:
        sys.exit('usage: mk_sucl.py --svh <file>')
    write_svh(args[1])
    sys.exit(0)

# The command files need the FST reader and the signal lists.
from fe_demo_sigs import NAMES, fmt, fst_names, fst_values, nslots, scenarios

scens = args or NAMES
bad = [s for s in scens if s not in NAMES]
if bad:
    sys.exit('mk_sucl.py: not a scenario: %s' % ' '.join(bad))

out = {}
nmark = {}
nslot = {}
absent = [s for s in scens
          if not os.path.exists(os.path.join(OUT, s, s + '.fst'))]
if absent:
    sys.exit('mk_sucl.py: no FST for %s (make -k scenarios)'
             % ', '.join(absent))
for scen in scens:
    fst = os.path.join(OUT, scen, scen + '.fst')
    names = fst_names(fst)
    nslot[scen] = nslots(names)
    groups = dict(scenarios(nslot[scen]))[scen]
    lines = ['# %s, examples/fe_demo (DOC-002, DOC-004, DOC-006); written '
             'by waves/mk_sucl.py' % scen,
             '# from out/%s/%s.fst, %d prediction slot(s)'
             % (scen, scen, nslot[scen]),
             '# surfer out/%s/%s.fst -c waves/%s.sucl' % (scen, scen, scen),
             'variable_force_name_type Unique']
    n = 0                                  # visible items so far
    for g, sigs in groups:
        rows = []
        for p in sigs:
            if p not in names:
                missing.append('%s: %s' % (scen, p))
                continue
            width, snm, enum = names[p]
            try:
                rows.append((snm, fmt(p, width, enum)))
            except KeyError as e:
                nofmt.append(str(e.args[0]))
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
    if missing or nofmt:
        continue
    mk, period, num = markers(scen)
    if mk:
        lines += ['# markers, from docs/%s.md section %s'
                  % (scen, num or 'Events')]
        lines += ['marker_set %s %d' % m for m in mk]
        t0 = mk[0][1]
        lines += ['item_unfocus',
                  'zoom_to %d %d' % (max(0, t0 - VIEW_BEFORE * period),
                                     t0 + VIEW_AFTER * period)]
        nmark[scen] = len(mk)
    else:
        lines += ['zoom_fit']
    out[scen] = '\n'.join(lines) + '\n'

if missing or nofmt:
    for m in sorted(set(missing)):
        print('not in the FST: ' + m, file=sys.stderr)
    for m in sorted(set(nofmt)):
        print(m, file=sys.stderr)
    sys.exit(1)
for scen, text in out.items():
    with open(os.path.join(HERE, scen + '.sucl'), 'w') as f:
        f.write(text)
print('wrote %d command files (%s at 2 slots); markers in %s' %
      (len(out), ', '.join(s for s in out if nslot[s] == 2) or 'none',
       ', '.join('%s (%d)' % kv for kv in nmark.items()) or 'none'))
