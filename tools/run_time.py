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
#          An interrupted /run (a rejected tool call or Esc writes a user
#          entry "[Request interrupted ...") is usually resumed by typed
#          follow-ups, so after an interrupt a typed prompt does not end the
#          task. It ends at the next slash command (/context, /cntx) or at
#          the end of the transcript, and the output says so. A task really
#          abandoned at the interrupt is over-counted by the turns after it.
#   active: the sum of the durationMs of the system turn_duration
#          entries Claude Code writes at the end of each turn, from start
#          to end. Claude Code leaves out of a turn's duration the time it
#          is blocked on a permission prompt, so time waiting on the user
#          is not counted. Nor is a background job (a regression run with
#          run_in_background) while no turn is running.
#          A turn with no such entry counts from its first entry to its last
#          assistant entry, and the output says active is partly estimated.
#          That span is never the task's wall time unless the task is one
#          turn: waits between turns stay out, though a permission prompt
#          inside that turn is counted.
#   wall:  end - start, as before. It never stands in for active.
# Prints: Run time: <active> active, <wall> wall (<start> -> <end>,
#         /run <ID>[, <note>])
# The first field is the header's Run time.
# Exits 1 when the file is unreadable, holds no /run, or the /run has no
# assistant reply: nothing was run to measure.
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
interrupted = False
estimated = False
# The turn being read: its first entry and last assistant entry. A span cut
# by a notification is held in pend_ms, since that notification can arrive
# inside a turn whose turn_duration, which covers the span, is still to come.
open_t = t0
last_a = None
pend_ms = 0


def cut():
    global open_t, last_a, pend_ms
    if open_t and last_a:
        pend_ms += int((ts(last_a) - ts(open_t)).total_seconds() * 1000)
    open_t = last_a = None


def settle():
    global active_ms, estimated, pend_ms
    cut()
    if pend_ms:
        active_ms += pend_ms
        estimated = True
    pend_ms = 0


for e in E[start + 1:]:
    if e.get('type') == 'user' and e.get('timestamp') != t0:
        t = text(e).lstrip()
        if e.get('turnOrigin') == 'scheduled' or 'scheduledTaskId' in e:
            t = '<task-notification>'
        if t.startswith('[Request interrupted'):
            interrupted = True
            continue
        if t.startswith(('<task-notification>', '<system-reminder>')):
            cut()
            open_t = e['timestamp']
        elif t:
            if not interrupted or t.startswith(('<command-',
                                                '<local-command-')):
                break
            settle()
            open_t = e['timestamp']
    if e.get('type') == 'assistant':
        t1 = last_a = e['timestamp']
        open_t = open_t or last_a
    if e.get('type') == 'system' and e.get('subtype') == 'turn_duration':
        active_ms += int(e.get('durationMs') or 0)
        open_t = last_a = None
        pend_ms = 0
settle()
if t1 is None:
    sys.exit('run_time: /run %s has no assistant reply' % task)


def hms(s):
    # The task-file format: 1h.10m.6s, 22m.39s, 11m.0s. No padding; the
    # hours field only when nonzero; minutes and seconds always.
    h, m, s = s // 3600, s // 60 % 60, s % 60
    return ('%dh.' % h if h else '') + '%dm.%ds' % (m, s)


def clock(s):
    # ISO timestamp to whole seconds: 2026-10-12T05:23:30Z.
    return ts(s).strftime('%Y-%m-%dT%H:%M:%SZ')


d = int((ts(t1) - ts(t0)).total_seconds())
notes = ''
if interrupted:
    notes += ', interrupted, counted to the next slash command'
if estimated:
    notes += ', active partly estimated, a turn has no turn_duration'
print('Run time: %s active, %s wall (%s -> %s, /run %s%s)'
      % (hms(active_ms // 1000), hms(d), clock(t0), clock(t1), task, notes))
