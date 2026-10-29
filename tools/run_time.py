#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/run_time.py <session transcript .jsonl>
#
# Run time of the LAST /run task in a Claude Code session, active and
# wall clock.
#   start: the user entry holding <command-name>/run</command-name>
#   end:   the last assistant entry before the next prompt the user
#          typed. Background-task notifications, system reminders,
#          scheduled-wakeup prompts (turnOrigin "scheduled", written by
#          the model's own ScheduleWakeup) and the /run expansion (same
#          timestamp as start) are not prompts, so time spent waiting on
#          a regression is counted.
#   active: the sum of the durationMs of the system turn_duration
#          entries Claude Code writes at the end of each turn, from start
#          to end. Claude Code leaves out of a turn's duration the time it
#          is blocked on a permission prompt, so time waiting on the user
#          is not counted. Nor is a background job (a regression run with
#          run_in_background) while no turn is running.
#   wall:  end - start, as before.
# Prints: Run time: <active> active, <wall> wall (<start> -> <end>,
#         /run <ID>)
# The first field is the header's Run time.
# Exits 1 when the file is unreadable or holds no /run.
import json, re, sys
from datetime import datetime


def text(e):
    c = e.get('message', {}).get('content')
    if isinstance(c, str):
        return c
    return ' '.join(x.get('text', '') for x in c or []
                    if isinstance(x, dict) and x.get('type') == 'text')


def ts(s):
    return datetime.fromisoformat(s.replace('Z', '+00:00'))


if len(sys.argv) != 2:
    sys.exit('usage: run_time.py <session transcript .jsonl>')

try:
    E = [json.loads(l) for l in open(sys.argv[1])]
except (OSError, ValueError) as err:
    sys.exit('run_time: cannot read transcript: %s' % err)

start = None
for i, e in enumerate(E):
    if e.get('type') == 'user' and \
       '<command-name>/run</command-name>' in text(e):
        start = i
if start is None:
    sys.exit('run_time: no /run command in this transcript')

m = re.search(r'<command-args>(.*?)</command-args>', text(E[start]))
task = m.group(1).strip() if m else '?'
t0 = E[start]['timestamp']
t1 = None
active_ms = 0
turns = 0
for e in E[start + 1:]:
    if e.get('type') == 'user' and e.get('timestamp') != t0:
        if e.get('turnOrigin') == 'scheduled' or 'scheduledTaskId' in e:
            continue
        t = text(e).lstrip()
        if t and not t.startswith(('<task-notification>',
                                   '<system-reminder>')):
            break
    if e.get('type') == 'assistant':
        t1 = e['timestamp']
    if e.get('type') == 'system' and e.get('subtype') == 'turn_duration':
        active_ms += int(e.get('durationMs') or 0)
        turns += 1
if t1 is None:
    sys.exit('run_time: /run %s has no assistant reply' % task)
if turns == 0:
    sys.exit('run_time: /run %s has no turn_duration entry; the turn may'
             ' still be running' % task)


def hms(s):
    # The task-file format: 1h.10m.6s, 22m.39s, 11m.0s. No padding; the
    # hours field only when nonzero; minutes and seconds always.
    h, m, s = s // 3600, s // 60 % 60, s % 60
    return ('%dh.' % h if h else '') + '%dm.%ds' % (m, s)


def clock(s):
    # ISO timestamp to whole seconds: 2026-10-12T05:23:30Z.
    return ts(s).strftime('%Y-%m-%dT%H:%M:%SZ')


d = int((ts(t1) - ts(t0)).total_seconds())
print('Run time: %s active, %s wall (%s -> %s, /run %s)'
      % (hms(active_ms // 1000), hms(d), clock(t0), clock(t1), task))
