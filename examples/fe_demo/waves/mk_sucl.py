#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# mk_sucl.py -- write waves/<scenario>.sucl, the Surfer command file of
# each scenario (DOC-002, fe_demo_tb_decisions.md FDT-1, FDT-12a)
#
# Usage, from examples/fe_demo, after any scenario has run:
#   python3 waves/mk_sucl.py out/fd02_steady/fd02_steady.fst
#
# The signals and groups are those of the scenario's GTKWave save file:
# both generators read fe_demo_sigs.py. A name not in the FST stops the
# script, as mk_gtkw.py does. make sview S=<scenario> loads the file:
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
# What a GTKWave save file sets and this file does instead:
#   - groups      Surfer groups, named as the save file's
#   - radix       the same rule (fe_demo_sigs.radix): Binary, Hexadecimal
#                 or Unsigned (GTKWave's @28, @22, @24)
#   - full names  variable_force_name_type Global (FDT-12a)
#   - signal and SST widths, sst_expanded: no equivalent; not set
#   - colours: neither file sets any
import os
import sys

from fe_demo_sigs import S, fst_names, radix

if len(sys.argv) != 2:
    sys.exit('usage: mk_sucl.py <fst>')
FST = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))

names = fst_names(FST)
missing = []

# Surfer's translator of each format of fe_demo_sigs.radix().
FMT = {'bin': 'Binary', 'hex': 'Hexadecimal', 'dec': 'Unsigned'}


# Surfer's item index: hex digits mapped to a-p (libsurfer util.rs,
# alpha_idx_to_uint_idx).
def alpha(i):
    return ''.join(chr(ord('a') + int(c, 16)) for c in '%x' % i)


out = {}
for scen, groups in S:
    lines = ['# %s, examples/fe_demo (DOC-002); written by '
             'waves/mk_sucl.py' % scen,
             '# surfer out/%s/%s.fst -c waves/%s.sucl' % (scen, scen, scen),
             'variable_force_name_type Global']
    n = 0                                  # visible items so far
    for g, sigs in groups:
        rows = []
        for p in sigs:
            if p not in names:
                missing.append(p)
                continue
            _, width, snm = names[p]
            rows.append((snm, FMT[radix(width, p)]))
        if not rows:
            continue
        lines += ['# group ' + g,
                  'variable_add ' + rows[0][0],
                  'item_focus ' + alpha(n),
                  'group_marked ' + g,
                  'item_focus ' + alpha(n + 1),
                  'item_set_format ' + rows[0][1]]
        for snm, fmt in rows[1:]:
            lines += ['variable_add ' + snm, 'item_set_format ' + fmt]
        lines += ['item_unfocus']
        n += 1 + len(rows)
    lines += ['zoom_fit']
    out[scen] = '\n'.join(lines) + '\n'

if missing:
    for m in sorted(set(missing)):
        print('not in the FST: ' + m, file=sys.stderr)
    sys.exit(1)
for scen, text in out.items():
    with open(os.path.join(HERE, scen + '.sucl'), 'w') as f:
        f.write(text)
print('wrote %d command files' % len(out))
