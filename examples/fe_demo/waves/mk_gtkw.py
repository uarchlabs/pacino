#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# mk_gtkw.py -- write waves/<scenario>.gtkw, the GTKWave save file of
# each scenario (DOC-001, fe_demo_tb_decisions.md FDT-12)
#
# Usage, from examples/fe_demo, after any scenario has run:
#   python3 waves/mk_gtkw.py out/fd02_steady/fd02_steady.fst
#
# Every scenario runs the same model, so one FST gives the signal names
# of all of them. The signal lists and the FST reader are in
# fe_demo_sigs.py, shared with mk_sucl.py (DOC-002). Each signal there
# is given without its range; a name not in the FST stops the script,
# so a save file never names a signal the waveform lacks.
#
# The groups of each file are named by unit and are in pipeline order
# (FDT-12): the scenario's waveform entry in fe_demo_scenarios.md, with
# clock and the scenario's own signals first.
import os
import sys

from fe_demo_sigs import S, fst_names, radix

if len(sys.argv) != 2:
    sys.exit('usage: mk_gtkw.py <fst>')
FST = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))

names = fst_names(FST)
missing = []

# The GTKWave trace flags of each format of fe_demo_sigs.radix().
FLAGS = {'bin': '@28', 'hex': '@22', 'dec': '@24'}

out = {}
for scen, groups in S:
    lines = ['[*] %s, examples/fe_demo (DOC-001); written by '
             'waves/mk_gtkw.py' % scen,
             '[dumpfile] "out/%s/%s.fst"' % (scen, scen),
             '[savefile] "waves/%s.gtkw"' % scen,
             '[timestart] 0',
             '[sst_expanded] 1',
             '[signals_width] 360',
             '[sst_width] 260']
    for g, sigs in groups:
        lines += ['@800200', '-' + g]
        for p in sigs:
            if p not in names:
                missing.append(p)
                continue
            full, width, _ = names[p]
            lines += [FLAGS[radix(width, p)], full]
        lines += ['@1000200', '-' + g]
    out[scen] = '\n'.join(lines) + '\n'

if missing:
    for m in sorted(set(missing)):
        print('not in the FST: ' + m, file=sys.stderr)
    sys.exit(1)
for scen, text in out.items():
    with open(os.path.join(HERE, scen + '.gtkw'), 'w') as f:
        f.write(text)
print('wrote %d save files' % len(out))
