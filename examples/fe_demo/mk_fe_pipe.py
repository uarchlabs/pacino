#!/usr/bin/env python3
# Writes fe_pipe.svg, the pacino front end drawn against its pipeline
# stages. Sources: fe_decisions.md section 1 (p0 to p3, u0, u1),
# fe_top_connectivity.md 6.2 (predictor stages), ifu_decisions.md
# IFU-10, IFU-23a to IFU-27 (translation and fetch pipelines),
# icache_decisions.md L1I-5 (2-cycle hit), ibuf_decisions.md IBUF-3,
# IBUF-7, IBUF-9, IBUF-13.
import sys

W, H = 2050, 840
out = []
def add(s): out.append(s)

C = dict(
    bg='#ffffff', ink='#1f2328', mute='#59636e', edge='#8c959f',
    grid='#eaeef2', head='#f6f8fa',
    pred='#dbe9f7', predk='#3b6ea5',
    ftq='#f7ead2', ftqk='#a0702a',
    fetch='#dcefdc', fetchk='#3f7f45',
    xlat='#ebe0f5', xlatk='#6f4f99',
    tb='#f2f3f5', tbk='#8c959f', red='#b42318',
)

def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

def rect(x, y, w, h, fill, stroke, dash=False, rx=5, sw=1.3):
    d = ' stroke-dasharray="6 4"' if dash else ''
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" '
        f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')

def text(x, y, s, size=11, anchor='start', weight='normal', color=None,
         italic=False, mono=False):
    st = ' font-style="italic"' if italic else ''
    fam = 'mono' if mono else 'sans'
    add(f'<text x="{x}" y="{y}" class="{fam}" font-size="{size}" '
        f'text-anchor="{anchor}" font-weight="{weight}" '
        f'fill="{color or C["ink"]}"{st}>{esc(s)}</text>')

def lines(x, y, s, size=11, anchor='middle', color=None, lh=13):
    for i, ln in enumerate(s.split('\n')):
        text(x, y + i * lh, ln, size, anchor, color=color)

def path(pts, color=None, dash=False, sw=1.5, end=True, start=False):
    col = color or C['ink']
    d = 'M ' + ' L '.join(f'{a} {b}' for a, b in pts)
    da = ' stroke-dasharray="5 4"' if dash else ''
    me = ' marker-end="url(#ah)"' if end else ''
    ms = ' marker-start="url(#ah)"' if start else ''
    add(f'<path d="{d}" fill="none" stroke="{col}" stroke-width="{sw}"'
        f'{da}{me}{ms}/>')

add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
    f'viewBox="0 0 {W} {H}">')
add('<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" '
    'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
    f'<path d="M 0 0 L 10 5 L 0 10 z" fill="{C["ink"]}"/></marker>'
    '<style>.sans{font-family:Helvetica,Arial,sans-serif}'
    '.mono{font-family:Menlo,Consolas,monospace}</style></defs>')
add(f'<rect width="{W}" height="{H}" fill="{C["bg"]}"/>')

text(30, 40, 'pacino front end: pipeline view', 22, weight='bold')
text(30, 62, 'Each bar spans the stages its unit works in. Prediction '
     'runs ahead of fetch; the FTQ decouples them. One column is one '
     'cycle within a pipeline; the two pipelines are not aligned in '
     'time.', 12, color=C['mute'])

# ---------------------------------------------------------------- grid
TOP, ROWH, GAP = 150, 40, 8
HDR = 108

# prediction pipeline columns
PX0, PCW = 140, 120
pcols = ['p0', 'p1', 'p2', 'p3']
def pc(i): return PX0 + i * PCW

# FTQ column
FQX, FQW = PX0 + 4 * PCW + 30, 150

# translation and fetch columns
RX0, RCW = FQX + FQW + 80, 112
rcols = ['request', 'ITLB', 'queue', 'F0', 'F1', 'F2', 'F3', 'WB',
         'ibuf, decode']
def rc(i): return RX0 + i * RCW

NROWS = 10
BOT = TOP + NROWS * (ROWH + GAP)

# column backgrounds and headers
for i, n in enumerate(pcols):
    rect(pc(i) + 2, HDR, PCW - 4, BOT - HDR, C['head'], C['grid'], rx=4,
         sw=1)
    text(pc(i) + PCW / 2, HDR + 22, n, 15, 'middle', 'bold',
         color=C['predk'])
for i, n in enumerate(rcols):
    rect(rc(i) + 2, HDR, RCW - 4, BOT - HDR, C['head'], C['grid'], rx=4,
         sw=1)
    col = C['xlatk'] if i < 3 else C['fetchk']
    text(rc(i) + RCW / 2, HDR + 22, n, 14 if i < 8 else 12, 'middle',
         'bold', color=col)

text(PX0, HDR - 12, 'prediction pipeline (bp_cluster)', 13, weight='bold',
     color=C['predk'])
text(rc(0), HDR - 12, 'translation pipeline (IFU)', 13, weight='bold',
     color=C['xlatk'])
text(rc(3), HDR - 12, 'fetch pipeline (IFU), then ibuf and decode', 13,
     weight='bold', color=C['fetchk'])

def row_y(r): return TOP + r * (ROWH + GAP)

def pbar(r, c0, c1, label, sub=None, fill=None, stroke=None, name=None):
    x = pc(c0) + 6
    w = pc(c1 + 1) - pc(c0) - 12
    y = row_y(r)
    rect(x, y, w, ROWH, fill or C['pred'], stroke or C['predk'])
    lines(x + w / 2, y + (17 if sub else 25), label)
    if sub:
        text(x + w / 2, y + 32, sub, 10, 'middle', color=C['mute'])

def rbar(r, c0, c1, label, sub=None, fill=None, stroke=None):
    x = rc(c0) + 6
    w = rc(c1 + 1) - rc(c0) - 12
    y = row_y(r)
    rect(x, y, w, ROWH, fill or C['fetch'], stroke or C['fetchk'])
    lines(x + w / 2, y + (17 if sub else 25), label)
    if sub:
        text(x + w / 2, y + 32, sub, 10, 'middle', color=C['mute'])

def rowname(x, r, s, color):
    text(x, row_y(r) + 25, s, 12, 'end', 'bold', color=color)

# ------------------------------------------------- prediction pipeline
prow = [
    ('FTQ next PC', C['ftqk']),
    ('history', C['predk']),
    ('uBTB', C['predk']),
    ('loop_pred', C['predk']),
    ('FTB', C['predk']),
    ('TAGE', C['predk']),
    ('ITTAGE', C['predk']),
    ('SC', C['predk']),
    ('RAS', C['predk']),
    ('FTQ entry', C['ftqk']),
]
for r, (n, c) in enumerate(prow):
    rowname(PX0 - 8, r, n, c)

pbar(0, 0, 0, 'request', 'PC, FTQ index', C['ftq'], C['ftqk'])
pbar(1, 0, 1, 'folded history to the', 'tables; checkpoint at p1')
pbar(2, 0, 1, 'index, then prediction', 'initial prediction at p1')
pbar(3, 0, 2, 'p1 prediction, p2 re-read')
pbar(4, 0, 2, 'index, read, result', 'branch type known at p2')
pbar(5, 0, 2, 'index, read and tag match,', 'final at p2')
pbar(6, 0, 2, 'index, read and tag match,', 'target at p2')
pbar(7, 2, 3, 'index at p2,', 'final at p3')
# RAS: three separate actions
y = row_y(8)
for c, lab in [(0, 'top of stack'), (2, 'push or pop'), (3, 'repair')]:
    x = pc(c) + 6
    rect(x, y, PCW - 12, ROWH, C['pred'], C['predk'])
    text(x + (PCW - 12) / 2, y + 25, lab, 11, 'middle')
# FTQ entry: written at p1, corrected at p2 and p3
y = row_y(9)
for c, lab, sub in [(1, 'allocate,', 'write p1 prediction'),
                    (2, 'correct slots,', 'p2 redirect'),
                    (3, 'correct slots,', 'p3 redirect')]:
    x = pc(c) + 6
    rect(x, y, PCW - 12, ROWH, C['ftq'], C['ftqk'])
    text(x + (PCW - 12) / 2, y + 17, lab, 11, 'middle')
    text(x + (PCW - 12) / 2, y + 32, sub, 10, 'middle', color=C['mute'])

# redirect loops: p2 and p3 back to the next PC at p0
ry = BOT + 14
for c, dy, lab in [(2, 0, 'p2 redirect'), (3, 16, 'p3 redirect')]:
    xs = pc(c) + PCW / 2
    path([(xs, row_y(9) + ROWH), (xs, ry + dy), (pc(0) + 20, ry + dy),
          (pc(0) + 20, row_y(0) + ROWH)], color=C['red'])
    text(xs + 6, ry + dy - 3, lab, 10, color=C['red'])
text(pc(0) + 28, ry + 34, 'Every stage after p1 is a redirect source; '
     'the FTQ never waits for a predictor later than p1.', 10,
     color=C['mute'])

# update path
UY = BOT + 92
text(PX0, UY - 8, 'update path', 13, weight='bold', color=C['predk'])
ux = [PX0, PX0 + 180, PX0 + 360, PX0 + 470]
rect(PX0, UY, 165, 44, C['ftq'], C['ftqk'])
lines(PX0 + 82, UY + 18, 'resolution from the\nbackend; FTQ forms update')
rect(PX0 + 190, UY, 120, 44, C['pred'], C['predk'])
lines(PX0 + 250, UY + 18, 'u0: address and\ndata to the RAMs')
rect(PX0 + 335, UY, 120, 44, C['pred'], C['predk'])
lines(PX0 + 395, UY + 18, 'u1: RAM write\ncompletes')
path([(PX0 + 165, UY + 22), (PX0 + 190, UY + 22)])
path([(PX0 + 310, UY + 22), (PX0 + 335, UY + 22)])

# ------------------------------------------------------------- the FTQ
rect(FQX, HDR, FQW, BOT - HDR, C['ftq'], C['ftqk'], sw=1.6)
text(FQX + FQW / 2, HDR + 22, 'FTQ', 15, 'middle', 'bold')
lines(FQX + FQW / 2, HDR + 44, '64 entries, one per\nprediction block',
      11)
text(FQX + FQW / 2, HDR + 92, 'pointers, oldest first', 11, 'middle',
     'bold')
for i, (p, d) in enumerate([
        ('commit_ptr', 'retired to here'),
        ('fetch_ptr', 'next to fetch, F0'),
        ('xlate_ptr', 'next to translate'),
        ('alloc_ptr', 'next to allocate, p1')]):
    yy = HDR + 116 + i * 40
    text(FQX + FQW / 2, yy, p, 11, 'middle', mono=True)
    text(FQX + FQW / 2, yy + 14, d, 10, 'middle', color=C['mute'])
lines(FQX + FQW / 2, HDR + 290, 'commit <= fetch\n<= xlate <= alloc', 11)
lines(FQX + FQW / 2, HDR + 350, 'Prediction fills it\nfrom alloc_ptr;\n'
      'translation and fetch\ndrain it in order.', 10, color=C['mute'])

# prediction to FTQ and FTQ to the right side
path([(pc(4) - 6, row_y(9) + ROWH / 2), (FQX, row_y(9) + ROWH / 2)])
path([(FQX, row_y(0) + ROWH / 2), (pc(1) - 6, row_y(0) + ROWH / 2)])
text((pc(4) + FQX) / 2, row_y(0) + ROWH / 2 - 5, 'next PC', 10, 'middle')

# --------------------------------------- translation and fetch pipelines
rrow = [
    ('FTQ', C['ftqk']), ('ITLB', C['xlatk']), ('queue', C['xlatk']),
    ('IFU', C['fetchk']), ('L1I', C['fetchk']), ('ibuf', C['fetchk']),
    ('decode', C['fetchk']),
]
rr = [0, 1, 2, 4, 6, 8, 9]
for (n, c), r in zip(rrow, rr):
    yy = row_y(r) + 25 + (40 if n == 'IFU' else 14 if n in ('L1I', 'decode') else 0)
    text(rc(0) - 8, yy, n, 12, 'end', 'bold', color=c)

# FTQ presents: translation request and fetch request
rbar(0, 0, 0, 'block start PC', 'at xlate_ptr', C['ftq'], C['ftqk'])
rbar(0, 3, 3, 'fetch request', 'at fetch_ptr', C['ftq'], C['ftqk'])
# ITLB
rbar(1, 1, 1, 'lookup,', '1-cycle hit', C['xlat'], C['xlatk'])
lines(rc(1) + RCW / 2, row_y(2) + ROWH + 18, 'second lookup the\n'
      'next cycle when the\nblock crosses a page;\na miss goes to the\n'
      'page table walker', 9, color=C['mute'], lh=11)
# translation queue
rbar(2, 2, 3, 'PA, PMA, fault; depth 4', 'head read at F0',
     C['xlat'], C['xlatk'])
text(rc(4) + 8, row_y(2) + 25, 'entry freed at F1', 10, color=C['mute'])
path([(rc(0) + RCW - 6, row_y(0) + ROWH / 2),
      (rc(1) + RCW / 2, row_y(0) + ROWH / 2),
      (rc(1) + RCW / 2, row_y(1))])
path([(rc(1) + RCW / 2, row_y(1) + ROWH),
      (rc(1) + RCW / 2, row_y(2) + ROWH / 2),
      (rc(2) + 6, row_y(2) + ROWH / 2)])
# IFU stage contents, two rows tall
y = row_y(3) + 10
ifu = [(3, 'accept request;\nread queue head;\nissue 0 to 2\nL1I requests'),
       (4, 'PC of every\n2-byte position;\ncache access\nin flight'),
       (5, 'line returns;\nfaults, ranges;\nselect 17\nhalfwords'),
       (6, 'expand, predecode,\ncheck prediction,\nmask; write\nthe ibuf'),
       (7, 'predecode\nwriteback\nto the FTQ')]
for c, s in ifu:
    rect(rc(c) + 6, y, RCW - 12, 2 * ROWH + GAP + 14, C['fetch'],
         C['fetchk'])
    lines(rc(c) + RCW / 2, y + 22, s, 10, lh=13)
for c in range(3, 7):
    path([(rc(c + 1) - 6, y + 50), (rc(c + 1) + 6, y + 50)])
# L1I: request at F0, array read F1, compare F2
y = row_y(6) + 14
rect(rc(4) + 6, y, 2 * RCW - 12, ROWH, C['fetch'], C['fetchk'])
text(rc(4) + RCW / 2, y + 17, 'array read', 11, 'middle')
text(rc(5) + RCW / 2, y + 17, 'tag compare,', 11, 'middle')
text(rc(5) + RCW / 2, y + 31, 'way select', 11, 'middle')
text(rc(4) + RCW / 2, y + 31, '2-cycle hit', 10, 'middle',
     color=C['mute'])
add(f'<line x1="{rc(5)}" y1="{y + 4}" x2="{rc(5)}" y2="{y + ROWH - 4}" '
    f'stroke="{C["fetchk"]}" stroke-width="1"/>')
path([(rc(3) + RCW / 2, row_y(3) + 10 + 2 * ROWH + GAP + 14),
      (rc(3) + RCW / 2, y + ROWH / 2), (rc(4) + 6, y + ROWH / 2)])
text(rc(3) + RCW / 2 + 4, y + ROWH / 2 - 5, 'request', 10)
path([(rc(5) + RCW / 2, y), (rc(5) + RCW / 2, row_y(3) + 10 + 2 * ROWH
                                                 + GAP + 14)])
text(rc(5) + RCW / 2 + 4, y - 6, 'line', 10)
# ibuf: written in F3, read with decode
y = row_y(8)
rect(rc(6) + 6, y, RCW - 12, ROWH, C['fetch'], C['fetchk'])
lines(rc(6) + RCW / 2, y + 17, 'write 16,\ncompact', 10)
rect(rc(8) + 6, y, RCW - 12, ROWH, C['fetch'], C['fetchk'])
lines(rc(8) + RCW / 2, y + 17, 'read 8 from\nthe head', 10)
path([(rc(7) - 6, y + ROWH / 2), (rc(8) + 6, y + ROWH / 2)])
text(rc(7) + RCW / 2, y + ROWH / 2 - 5, 'buffered', 10, 'middle',
     color=C['mute'])
text(rc(7) + RCW / 2, y + ROWH + 12, 'empty: F3 write bypasses', 9,
     'middle', color=C['mute'])
text(rc(7) + RCW / 2, y + ROWH + 23, 'to the read port', 9, 'middle',
     color=C['mute'])
# decode
y = row_y(9) + 14
rect(rc(8) + 6, y, RCW - 12, ROWH, C['fetch'], C['fetchk'])
lines(rc(8) + RCW / 2, y + 17, '8-wide,\ncombinational', 10)
path([(rc(8) + RCW / 2, row_y(8) + ROWH), (rc(8) + RCW / 2, y)])

# --------------------------------------------------- feedback to the FTQ
FB = BOT + 22
# predecode writeback
wx = rc(7) + RCW / 2
path([(wx, row_y(3) + 10 + 2 * ROWH + GAP + 14), (wx, row_y(6) + 4)],
     end=False)
path([(wx, row_y(6) + 4), (wx, FB), (FQX + FQW / 2 + 20, FB),
      (FQX + FQW / 2 + 20, BOT)], color=C['red'])
text(rc(3), FB - 4, 'predecode writeback; the FTQ derives the redirect '
     'and flushes from K+1', 10, color=C['red'])
# flush to the IFU
path([(FQX + FQW / 2 - 20, BOT), (FQX + FQW / 2 - 20, FB + 26),
      (rc(3) + RCW / 2 - 10, FB + 26), (rc(3) + RCW / 2 - 10,
                                        row_y(6) + 4)],
     color=C['ink'], dash=True)
text(rc(0), FB + 22, 'flush: both IFU pipelines drop every block at or '
     'after the flush index', 10)

# backend, outside, at the right
BKX = rc(9) + 10
rect(BKX, HDR, W - BKX - 14, BOT - HDR, C['tb'], C['tbk'], dash=True)
lines(BKX + (W - BKX - 14) / 2, HDR + 22, 'backend\n(testbench)', 12)
path([(rc(9) - 6, row_y(9) + 14 + ROWH / 2),
      (BKX, row_y(9) + 14 + ROWH / 2)])
text(rc(9) - 2, row_y(9) + 14 + ROWH / 2 - 5, '', 10)
# backend redirect, resolution, commit to the FTQ; redirect clears ibuf
bx = BKX + (W - BKX - 14) / 2
path([(bx, BOT), (bx, FB + 52), (FQX + FQW / 2, FB + 52),
      (FQX + FQW / 2, BOT)], color=C['red'])
text(rc(3), FB + 48, 'backend redirect, resolution and commit to the '
     'FTQ; the redirect also clears the ibuf', 10, color=C['red'])

path([(BKX, row_y(8) + ROWH / 2), (rc(9) - 6, row_y(8) + ROWH / 2)],
     color=C['red'])
text(BKX + 8, row_y(8) + ROWH / 2 + 4, 'redirect clears ibuf', 10, color=C['red'])
text(BKX + 8, row_y(9) + 14 + ROWH / 2 + 4, 'decoded bundle', 10)

# latency note
NX, NY = rc(0), FB + 80
rect(NX, NY, 470, 86, '#ffffff', C['edge'], rx=6, sw=1)
text(NX + 12, NY + 20, 'Redirect to the first translation request '
     'for the flush index', 11, weight='bold')
for i, (a, b) in enumerate([('p2 or p3 redirect', '1 cycle'),
                            ('predecode redirect', '2 cycles'),
                            ('backend redirect', '2 cycles')]):
    text(NX + 24, NY + 40 + i * 15, a, 11)
    text(NX + 230, NY + 40 + i * 15, b, 11)
text(NX + 470 + 16, NY + 20, 'Sources: fe_decisions.md 1; '
     'ifu_decisions.md IFU-10,', 10, color=C['mute'])
text(NX + 470 + 16, NY + 34, 'IFU-23a to IFU-27; icache_decisions.md '
     'L1I-5;', 10, color=C['mute'])
text(NX + 470 + 16, NY + 48, 'ibuf_decisions.md IBUF-3, IBUF-7, '
     'IBUF-9, IBUF-13;', 10, color=C['mute'])
text(NX + 470 + 16, NY + 62, 'fe_top_connectivity.md 6.2.', 10,
     color=C['mute'])

add('</svg>')
open(sys.argv[1] if len(sys.argv) > 1 else 'fe_pipe.svg', 'w').write(
    '\n'.join(out) + '\n')
