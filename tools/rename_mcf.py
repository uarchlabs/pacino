"""
Register Renaming on 429.mcf-like RISC-V inner loop
Using x0-x31 notation throughout for clarity.
"""
from collections import deque

NUM_ARCH = 32
NUM_PHYS = 64
GROUP    = 4

# ABI -> x-index (used only to parse the compiler output)
ABI = {
    'zero':0,'ra':1,'sp':2,'gp':3,'tp':4,
    't0':5,'t1':6,'t2':7,'s0':8,'s1':9,
    'a0':10,'a1':11,'a2':12,'a3':13,'a4':14,'a5':15,'a6':16,'a7':17,
    's2':18,'s3':19,'s4':20,'s5':21,'s6':22,'s7':23,'s8':24,'s9':25,'s10':26,'s11':27,
    't3':28,'t4':29,'t5':30,'t6':31,
}

def r(name): return ABI[name.strip()]
def xn(i):   return f"x{i}"
def pn(i):   return f"p{i}"

# (op, dst, src1, src2) — all in x-indices
INSTRS = [
    ("slli", 11, 11,  0),  #  0  x11 = x11 << 6
    ("add",  16, 10, 11),  #  1  x16 = x10 + x11
    ("bgeu",  0, 10, 16),  #  2  branch x10 >= x16
    ("ld",   15, 10,  0),  #  3  x15 = mem[x10+24]
    ("ld",   11, 10,  0),  #  4  x11 = mem[x10+0]
    ("beq",   0, 15,  0),  #  5  branch x15 == 0
    ("ld",   12, 15,  0),  #  6  x12 = mem[x15+40]
    ("ld",   14, 15,  0),  #  7  x14 = mem[x15+8]
    ("addi", 13,  0,  0),  #  8  x13 = 0
    ("ld",   12, 12,  0),  #  9  x12 = mem[x12+0]
    ("add",  14, 11, 14),  # 10  x14 = x11 + x14
    ("bge",   0, 14, 12),  # 11  branch x14 >= x12
    ("ld",   13, 15,  0),  # 12  x13 = mem[x15+16]
    ("sd",    0, 13, 15),  # 13  mem[x15+0] = x13
    ("ld",   15, 15,  0),  # 14  x15 = mem[x15+32]
    ("bne",   0, 15,  0),  # 15  branch x15 != 0
    ("addi", 10, 10,  0),  # 16  x10 = x10 + 64
    ("bltu",  0, 10, 16),  # 17  branch x10 < x16
    ("jalr",  0,  0,  0),  # 18  ret
    ("beq",   0, 11, 10),  # 19  branch x11 == x10
    ("ld",   14, 10,  0),  # 20  x14 = mem[x10+0]
    ("ld",   15, 10,  0),  # 21  x15 = mem[x10+48]
    ("add",  14, 14, 12),  # 22  x14 = x14 + x12
    ("addi", 15, 15,  0),  # 23  x15 = x15 + 1
    ("sd",    0, 14, 10),  # 24  mem[x10+0] = x14
]

# ── State ───────────────────────────────────────────────────────────────────
RAT      = list(range(NUM_ARCH))
freelist = deque(range(NUM_ARCH, NUM_PHYS))
ROB      = []
IQ       = []

def rename_group(group_instrs, group_id):
    rat_snap = RAT.copy()
    intra    = {}

    print(f"\n{'─'*108}")
    print(f"  GROUP {group_id}  ({len(group_instrs)} instructions)")
    print(f"{'─'*108}")
    print(f"  {'#':>2}  {'ARCH INSTRUCTION':<34}  {'RENAMED INSTRUCTION':<34}  ROB ENTRY")
    print(f"  {'─'*103}")

    for i, (op, dst, src1, src2) in enumerate(group_instrs):
        instr_num = group_id * GROUP + i

        p_src1 = intra.get(src1, rat_snap[src1])
        p_src2 = intra.get(src2, rat_snap[src2])

        arch_str    = f"{op} {xn(dst)},{xn(src1)},{xn(src2)}"

        if dst == 0:
            renamed_str = f"{op} {pn(0)},{pn(p_src1)},{pn(p_src2)}"
            print(f"  {instr_num:>2}  {arch_str:<34}  {renamed_str:<34}  (no dst — x0 hardwired)")
            continue

        if not freelist:
            raise RuntimeError("Freelist exhausted")

        new_p = freelist.popleft()
        old_p = intra.get(dst, rat_snap[dst])

        RAT[dst]   = new_p
        intra[dst] = new_p

        ROB.append({'logical': dst, 'old': old_p, 'new': new_p})
        rob_idx = len(ROB) - 1
        IQ.append({'op': op, 'ps1': p_src1, 'ps2': p_src2, 'pd': new_p, 'rob': rob_idx})

        renamed_str = f"{op} {pn(new_p)},{pn(p_src1)},{pn(p_src2)}"
        rob_str     = f"ROB[{rob_idx:>2}]: {xn(dst)} old={pn(old_p)} new={pn(new_p)}"
        print(f"  {instr_num:>2}  {arch_str:<34}  {renamed_str:<34}  {rob_str}")

print(f"\n429.mcf inner loop — RISC-V rename (x-notation)")
print(f"Arch regs: {NUM_ARCH}  Phys regs: {NUM_PHYS}  Rename width: {GROUP}")
print(f"Initial RAT: identity (xN -> pN)  Freelist: p{NUM_ARCH}..p{NUM_PHYS-1}")

groups = [INSTRS[i:i+GROUP] for i in range(0, len(INSTRS), GROUP)]
for g_id, grp in enumerate(groups):
    rename_group(grp, g_id)

print(f"\n{'─'*108}")
print(f"  Final RAT (changed entries):")
for i in range(NUM_ARCH):
    if RAT[i] != i:
        print(f"    {xn(i):<4} -> {pn(RAT[i])}")
print(f"  Freelist remaining: {len(freelist)}  ROB entries: {len(ROB)}")

