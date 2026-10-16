#!/usr/bin/env python3
# Writes fe_block.svg, the pacino front-end block diagram, from the
# connectivity inventory examples/fe_demo/docs/fe_top_connectivity.md.
# Section numbers on the arrows are that file's.
import sys

W, H = 1820, 1060
out = []
def add(s): out.append(s)

C = dict(
    bg='#ffffff', ink='#1f2328', mute='#59636e', edge='#8c959f',
    pred='#dbe9f7', predk='#3b6ea5',
    ftq='#f7ead2', ftqk='#a0702a',
    fetch='#dcefdc', fetchk='#3f7f45',
    xlat='#ebe0f5', xlatk='#6f4f99',
    tb='#f2f3f5', tbk='#8c959f',
)

def rect(x, y, w, h, fill, stroke, dash=False, rx=6, sw=1.5):
    d = ' stroke-dasharray="6 4"' if dash else ''
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" '
        f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')

def text(x, y, s, size=12, anchor='start', weight='normal',
         color=None, mono=False, italic=False):
    fam = 'mono' if mono else 'sans'
    st = ' font-style="italic"' if italic else ''
    add(f'<text x="{x}" y="{y}" class="{fam}" font-size="{size}" '
        f'text-anchor="{anchor}" font-weight="{weight}" '
        f'fill="{color or C["ink"]}"{st}>{s}</text>')

def unit(x, y, w, h, title, inst, fill, stroke, dash=False):
    rect(x, y, w, h, fill, stroke, dash)
    text(x + w / 2, y + 20, title, 14, 'middle', 'bold')
    if inst:
        text(x + w / 2, y + 36, inst, 11, 'middle', color=C['mute'],
             mono=True)

def arrow(pts, label=None, lx=None, ly=None, anchor='middle',
          both=False, color=None, sw=1.6):
    col = color or C['ink']
    d = 'M ' + ' L '.join(f'{px} {py}' for px, py in pts)
    me = ' marker-start="url(#ah)"' if both else ''
    add(f'<path d="{d}" fill="none" stroke="{col}" stroke-width="{sw}" '
        f'marker-end="url(#ah)"{me}/>')
    if label:
        for i, line in enumerate(label.split('\n')):
            text(lx, ly + i * 13, line, 11, anchor)

add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
    f'viewBox="0 0 {W} {H}">')
add('<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" '
    'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
    f'<path d="M 0 0 L 10 5 L 0 10 z" fill="{C["ink"]}"/></marker>'
    '<style>.sans{font-family:Helvetica,Arial,sans-serif}'
    '.mono{font-family:Menlo,Consolas,monospace}</style></defs>')
add(f'<rect width="{W}" height="{H}" fill="{C["bg"]}"/>')

text(30, 40, 'pacino front end: fe_top', 22, weight='bold')
text(30, 62, 'Blocks and interfaces as built. Numbers are sections of '
     'examples/fe_demo/docs/fe_top_connectivity.md. NUM_PRED_SLOTS = 2.',
     12, color=C['mute'])

# fe_top boundary
rect(200, 110, 1310, 790, 'none', C['edge'], dash=True, rx=10, sw=2)
text(215, 132, 'fe_top', 15, weight='bold', color=C['mute'])
text(1495, 890, 'in: clk, rstn (4.1)', 11, 'end', color=C['mute'], italic=True)

# ---- bp_cluster ----
BX, BY, BW, BH = 230, 200, 240, 640
unit(BX, BY, BW, BH, 'bp_cluster', 'u_bpu', C['pred'], C['predk'])
def pbox(x, y, w, h, name):
    rect(x, y, w, h, '#ffffff', C['predk'], rx=4, sw=1)
    text(x + w / 2, y + h / 2 + 4, name, 12, 'middle')
rows = [('p1', 260, [('uBTB', 0), ('loop_pred', 1)]),
        ('p2', 320, [('FTB', 0), ('TAGE', 1)]),
        ('', 368, [('ITTAGE', 0), ('RAS', 1)]),
        ('p3', 428, [('SC', 0)])]
for st, y, boxes in rows:
    if st:
        text(BX + 14, y + 23, st, 12, weight='bold', color=C['predk'])
    for name, col in boxes:
        pbox(BX + 46 + col * 94, y, 86, 36, name)
pbox(BX + 46, 496, 180, 36, 'bp_history')
text(BX + 14, 519, 'hist', 11, color=C['predk'])
text(BX + 12, 572, 'p0 request in; p1 to p3', 11, color=C['mute'])
text(BX + 12, 586, 'predictions out; updates', 11, color=C['mute'])
text(BX + 12, 600, 'at u0, applied at u1', 11, color=C['mute'])
text(BX + 12, 630, 'RAS top of stack read at p0', 11, color=C['mute'])
text(BX + 12, 800, 'in: fe_cfg aging, sc_enable,', 11,
     color=C['mute'], italic=True)
text(BX + 12, 814, 'ftb_fastpath_en (4.10)', 11, color=C['mute'],
     italic=True)

# ---- FTQ ----
FX, FY, FW, FH = 700, 200, 160, 640
unit(FX, FY, FW, FH, 'FTQ', 'u_ftq', C['ftq'], C['ftqk'])
text(FX + FW / 2, FY + FH - 26, 'in: fe_cfg.sc_enable', 11, 'middle',
     color=C['mute'], italic=True)

# BPU <-> FTQ: one arrow per interface group
L, R = BX + BW, FX
mid = (L + R) / 2
groups = [
    ('r', 250, 'p0 prediction request  3.1'),
    ('l', 300, 'p1 initial prediction  3.4'),
    ('l', 350, 'p2, p3 slot correction  3.5'),
    ('l', 400, 'p2 block correction  3.6'),
    ('l', 450, 'p2, p3 redirects  3.7'),
    ('l', 500, 'p2, p3 metadata  3.8'),
    ('l', 550, 'RAM init readies  3.2'),
    ('l', 600, 'queue status  3.3'),
    ('r', 650, 'updates u0, per predictor  3.9'),
    ('r', 700, 'FTB update u0  3.10'),
    ('r', 750, 'RAS commit, restore  3.11'),
    ('r', 800, 'history rollback  3.12'),
]
for d, y, lab in groups:
    pts = [(L, y), (R, y)] if d == 'r' else [(R, y), (L, y)]
    arrow(pts, lab, mid, y - 6)
# checkpoint pointers BPU -> FTQ, part of 3.12
arrow([(L, 818), (R, 818)])
text(mid, 834, 'checkpoint pointers (to FTQ)  3.12', 11, 'middle')

# ---- IFU, ITLB, L1I, ibuf, decode ----
IX, IY, IW, IH = 1010, 280, 160, 320
unit(IX, IY, IW, IH, 'IFU', 'u_ifu', C['fetch'], C['fetchk'])
text(IX + IW / 2, IY + 70, 'F0 to F3', 12, 'middle', color=C['mute'])
text(IX + IW / 2, IY + 86, 'predecode', 12, 'middle', color=C['mute'])

TX, TY, TW, TH = 900, 700, 160, 100
unit(TX, TY, TW, TH, 'ITLB', 'u_itlb, with PMP/PMA', C['xlat'], C['xlatk'])
text(TX + TW / 2, TY + 62, 'in: fe_csr (4.9),', 11, 'middle',
     color=C['mute'], italic=True)
text(TX + TW / 2, TY + 76, 'ITLB invalidate (4.11)', 11, 'middle',
     color=C['mute'], italic=True)

LX, LY, LW, LH = 1110, 700, 150, 100
unit(LX, LY, LW, LH, 'L1I', 'u_l1i', C['fetch'], C['fetchk'])

BUX, BUY, BUW, BUH = 1265, 360, 100, 160
unit(BUX, BUY, BUW, BUH, 'ibuf', 'u_ibuf', C['fetch'], C['fetchk'])
DX, DY, DW, DH = 1400, 360, 90, 160
unit(DX, DY, DW, DH, 'decode', 'u_dec', C['fetch'], C['fetchk'])
text(DX + DW / 2, DY + DH - 14, 'in: ext_enable', 10, 'middle',
     color=C['mute'], italic=True)

# FTQ <-> IFU
fl, fr = FX + FW, IX
fm = (fl + fr) / 2
arrow([(fl, 330), (fr, 330)], 'translation request\n3.13', fm, 312)
arrow([(fl, 400), (fr, 400)], 'fetch request  3.14', fm, 393)
arrow([(fl, 450), (fr, 450)], 'flush  3.15', fm, 443)
arrow([(fr, 540), (fl, 540)], 'predecode\nwriteback  3.16', fm, 515)

# IFU <-> ITLB
arrow([(1030, IY + IH), (1030, TY)])
arrow([(1050, TY), (1050, IY + IH)])
text(1020, 640, '↓ translate VPN', 11, 'end')
text(1020, 654, '↑ PPN or fault', 11, 'end')
text(1020, 668, '3.20', 11, 'end')

# IFU <-> L1I
arrow([(1120, IY + IH), (1120, LY)])
arrow([(1140, IY + IH), (1140, LY)])
arrow([(1160, LY), (1160, IY + IH)])
text(1172, 628, '↓ fetch request  3.17', 11)
text(1172, 642, '↓ invalidate  3.19', 11)
text(1172, 656, '↑ 64-byte line  3.18', 11)

# IFU -> ibuf -> decode
arrow([(IX + IW, 410), (BUX, 410)], '16 slots', (IX + IW + BUX) / 2, 403)
text((IX + IW + BUX) / 2, 425, '3.21', 11, 'middle')
arrow([(BUX, 470), (IX + IW, 470)], 'ready', (IX + IW + BUX) / 2, 463)
arrow([(BUX + BUW, 440), (DX, 440)], '8', (BUX + BUW + DX) / 2, 433)
text((BUX + BUW + DX) / 2, 455, '3.22', 11, 'middle')

# ---- outside: backend ----
KX, KY, KW, KH = 1590, 160, 200, 700
unit(KX, KY, KW, KH, 'backend', 'testbench in-order model', C['tb'],
     C['tbk'], dash=True)
text(KX + KW / 2, KY + 64, 'rename and dispatch,', 11, 'middle',
     color=C['mute'])
text(KX + KW / 2, KY + 78, 'execute, commit', 11, 'middle',
     color=C['mute'])

# decode -> backend
arrow([(DX + DW, 420), (KX, 420)])
text(1540, 400, 'decoded bundle', 11, 'middle')
text(1540, 413, '4.2', 11, 'middle')
# backend -> ibuf ready
arrow([(KX, 545), (1315, 545), (1315, BUY + BUH)])
text(1450, 538, 'decode ready  4.2', 11, 'middle')
# commit stage -> IFU maintenance
arrow([(KX, 575), (IX + IW, 575)], both=True)
text(1380, 568, 'FENCE.I, cbo.inval  4.6', 11, 'middle')

# backend <-> FTQ along the top
arrow([(730, FY), (730, 132), (1575, 132), (1575, 210), (KX, 210)])
arrow([(KX, 230), (1560, 230), (1560, 150), (760, 150), (760, FY)])
arrow([(KX, 250), (1545, 250), (1545, 168), (790, 168), (790, FY)])
arrow([(KX, 270), (1530, 270), (1530, 186), (820, 186), (820, FY)])
text(1180, 128, 'resolution ready  4.3', 11, 'middle')
text(1180, 146, 'resolution  4.3', 11, 'middle')
text(1180, 164, 'redirect  4.4', 11, 'middle')
text(1180, 182, 'commit  4.5', 11, 'middle')
# redirect also clears the ibuf
arrow([(1300, 168), (1300, BUY)])
text(1306, 300, 'redirect', 11)
text(1306, 314, 'clears ibuf', 11)

# ---- outside, below: walker and memory model ----
PX, PY, PW, PH = 880, 950, 180, 80
unit(PX, PY, PW, PH, 'page table walker', 'u_ptw, testbench', C['tb'],
     C['tbk'], dash=True)
MX, MY, MW, MH = 1130, 950, 190, 80
unit(MX, MY, MW, MH, 'memory model', 'testbench, one image', C['tb'],
     C['tbk'], dash=True)
arrow([(940, TY + TH), (940, PY)])
arrow([(980, PY), (980, TY + TH)])
text(932, 866, '↓ walk request', 11, 'end')
text(932, 880, '↑ result  4.7', 11, 'end')
arrow([(1150, LY + LH), (1150, MY)])
arrow([(1200, MY), (1200, LY + LH)])
text(1210, 866, '↓ line request (A)', 11)
text(1210, 880, '↑ line data (D)  4.8', 11)
arrow([(PX + PW, 990), (MX, 990)], both=True)
text((PX + PW + MX) / 2, 984, 'PTE', 11, 'middle')

# observation outputs
arrow([(780, FY + FH), (780, 900)])
text(772, 892, 'ftq_full, ftq_empty  4.12', 11, 'end')

# legend
LGX, LGY = 230, 940
rect(LGX, LGY, 22, 14, C['pred'], C['predk'], rx=3, sw=1)
text(LGX + 30, LGY + 12, 'RTL instance inside fe_top', 12)
rect(LGX, LGY + 24, 22, 14, C['tb'], C['tbk'], dash=True, rx=3, sw=1)
text(LGX + 30, LGY + 36, 'testbench model outside fe_top', 12)
text(LGX, LGY + 62, 'in: ... marks a fe_top input wired to that '
     'block', 12, color=C['mute'], italic=True)

add('</svg>')
open(sys.argv[1] if len(sys.argv) > 1 else 'fe_block.svg', 'w').write(
    '\n'.join(out) + '\n')
