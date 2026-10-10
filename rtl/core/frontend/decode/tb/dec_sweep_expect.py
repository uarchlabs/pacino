#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# dec_sweep_expect.py -- the expected decode of every swept encoding,
# from the spike-dasm oracle (BP-124 Problem 4, dcd_decisions.md DCD-34).
#
# usage: dec_sweep_expect.py <spike-dasm> <decode_pkg.sv> <oracle.txt>
#                            <out.hex> [--report <report.txt>]
#        dec_sweep_expect.py --table <decode_pkg.sv> <oracle.txt>
#
# For each line of the oracle (<word> <spike-dasm text>) this script
# writes the decode instr_decoder must produce with every extension
# enabled (RVA23_ENABLE), as one 64-bit hex line for tb_instr_decoder's
# sweep mode (+SWEEP):
#
#   [63:32] the word
#   [31:28] 1 illegal, 0 legal
#   [27:24] 1 a vector instruction (op is v_op_class), 0 scalar (alu_op)
#   [23:16] the operation, alu_op_t or v_op_class_t, 0 when illegal
#   [15:0]  the rule that decided it (RULES below), 0 spike-dasm's own
#
# THE TABLE (MNEMONIC -> OPERATION). spike-dasm's mnemonic names an
# encoding; the operation is the one DCD-22 (scalar), DCD-29 (fences;
# an alias such as pause maps to the operation of its encoding) and
# DCD-33 (Zvbb) assign to that encoding, and for the vector space the
# v_op_class decode_pkg.sv declares for it. The table is derived from
# those rules, not from instr_decoder. Operation names are resolved to
# values from decode_pkg.sv's enum declarations. --table prints it.
#
# A MNEMONIC OF AN EXTENSION THIS DESIGN DOES NOT IMPLEMENT (spike-dasm
# disassembles several regardless of --isa: Q, Zfh beyond Zfhmin, Zabha,
# Zacas, Zalasr, Zicfiss, Smrnmi, Sdext, Ssctr, Zfbfmin, Zvfbfmin,
# Zvfbfwma, Zvbc and unratified vector forms) is expected illegal: rule
# NI. RVA23 recommends illegal-instruction for unimplemented opcodes.
#
# RULES. Where the ratified specification or the dcd_decisions.md rule
# decides an encoding differently from spike-dasm's literal answer, the
# expectation follows the rule and the encoding is counted under it.
# Each rule names its source. These are the disagreements between
# spike-dasm and decode, each resolved; see the BP-124 Results Capture.
import os
import re
import subprocess
import sys

ISA_NOTE = "RVA23_ENABLE: every ext_enable_t bit set"

# ---------------------------------------------------------------------
# Rules: id -> (short name, source, outcome)
# ---------------------------------------------------------------------
RULES = {
    0:  ("SPIKE", "spike-dasm's decode", "agree"),
    1:  ("NI", "extension not implemented (RVA23 recommends illegal for "
         "unimplemented opcodes; rva23-profile.adoc Recommendations)",
         "decode illegal; spike-dasm decodes"),
    2:  ("RM", "static rm 101 or 110 is reserved (unprivileged F chapter, "
         "rounding modes; DCD-27)", "decode illegal; spike-dasm decodes"),
    3:  ("VRSV", "a reserved vector encoding decode classifies as the "
         "instruction it is with the reserved field at its defined value "
         "(V 1.0; riscv-opcodes rv_v fixes the field); DCD-32 reports it "
         "for a ruling and decode is not changed",
         "decode legal; spike-dasm unknown or a reserved form; listed for "
         "Jeff"),
}

# ---------------------------------------------------------------------
# VRSV. The vector fields V 1.0 fixes or reserves that decode does not
# check (DCD-32 keeps them, for a ruling). An encoding spike-dasm calls
# unknown, or a reserved form (EEW above 64, Zvfbfmin's VFUNARY0 slot),
# whose normalized word -- the reserved field at its defined value -- is
# an implemented instruction, is expected to decode as that instruction.
# Each entry: (opcode, funct3, funct6, condition) -> normalization.
#   vm1   vm set to 1 (the field must be 1)     vm0  vm set to 0
#   vs2   vs2 set to 0                          vs1  vs1 set to 0
#   cfg   vsetvl bits 30:25 set to 0
#   v1lo  VFUNARY0 vs1[2:0] set to 0 (decode classes by vs1[4:3])
#   nf    nf set to 0                           lum  lumop set to 0
#   w0    width set to 000 (whole-register stores and vlm / vsm fix it)
#   mew   mew set to 0 (V 1.0 reserves mew = 1)
# The class of an encoding outside these lists is decided by spike-dasm.
# ---------------------------------------------------------------------
def vrsv_norm(w):
    op  = w & 0x7F
    f3  = (w >> 12) & 7
    f6  = (w >> 26) & 0x3F
    vm  = (w >> 25) & 1
    vs1 = (w >> 15) & 0x1F
    steps = []
    if op == 0x57:
        if f3 == 7 and (w >> 30) == 2:
            steps = ["cfg"]                          # vsetvl
        elif f6 in (0x10, 0x12) and f3 in (0, 4, 3) and vm == 1 and \
                not (f6 == 0x12 and f3 == 3):
            steps = ["vm0"]                          # vadc, vsbc
        elif f6 == 0x17 and f3 in (0, 4, 3) and vm == 1:
            steps = ["vs2"]                          # vmv.v.*
        elif f6 == 0x17 and f3 == 5 and vm == 1:
            steps = ["vs2"]                          # vfmv.v.f
        elif f6 == 0x10 and f3 in (5, 6):
            steps = ["vs2", "vm1"]                   # vfmv.s.f, vmv.s.x
        elif f6 == 0x10 and f3 == 1:
            steps = ["vs1", "vm1"]                   # vfmv.f.s
        elif f6 == 0x10 and f3 == 2 and vs1 == 0:
            steps = ["vm1"]                          # vmv.x.s
        elif f6 == 0x27 and f3 == 3:
            steps = ["vs1", "vm1"]                   # vmv<nr>r.v
        elif f6 in range(0x17, 0x20) and f3 == 2:
            steps = ["vm1"]                          # vcompress, mask ops
        elif f6 == 0x14 and f3 == 2 and vs1 == 0x11:
            steps = ["vs2"]                          # vid.v
        elif f6 == 0x12 and f3 == 1 and (vs1 >> 3) in (0, 1, 2):
            steps = ["v1lo"]                         # VFUNARY0
    elif op in (0x07, 0x27):
        width = f3
        if width in (0, 5, 6, 7):
            nf    = w >> 29
            mop   = (w >> 26) & 3
            lum   = (w >> 20) & 0x1F
            store = (op == 0x27)
            if mop == 0 and lum == 0x08:
                steps = ["nf", "vm1", "mew"] + (["w0"] if store else [])
                                                     # whole register
            elif mop == 0 and lum == 0x0B and nf == 0:
                steps = ["vm1", "w0", "mew"]         # vlm.v, vsm.v
            elif mop == 0 and nf != 0 and lum not in (0x00, 0x10) and \
                    not (store and lum == 0x10):
                steps = ["lum"]                      # segment lumop
    return steps


def apply_norm(w, steps):
    for st in steps:
        if st == "vm1":  w |= (1 << 25)
        if st == "vm0":  w &= ~(1 << 25)
        if st == "vs2":  w &= ~(0x1F << 20)
        if st == "vs1":  w &= ~(0x1F << 15)
        if st == "cfg":  w &= ~(0x3F << 25)
        if st == "v1lo": w &= ~(0x7 << 15)
        if st == "nf":   w &= ~(0x7 << 29)
        if st == "lum":  w &= ~(0x1F << 20)
        if st == "w0":   w &= ~(0x7 << 12)
        if st == "mew":  w &= ~(1 << 28)
    return w & 0xFFFFFFFF

# ---------------------------------------------------------------------
# The enum values from decode_pkg.sv.
# ---------------------------------------------------------------------
def enum_values(pkg_path, enum_name):
    src = open(pkg_path, encoding="ascii").read()
    m = re.search(r"typedef enum logic \[\d+:0\] \{(.*?)\}\s*" + enum_name +
                  r"\s*;", src, re.S)
    if not m:
        sys.exit("expect: enum " + enum_name + " not found")
    vals = {}
    for nm, v in re.findall(r"\b([A-Z][A-Z0-9_]*)\s*=\s*\d+'d(\d+)",
                            m.group(1)):
        vals[nm] = int(v)
    return vals


# ---------------------------------------------------------------------
# Scalar mnemonics -> alu_op_t names (DCD-22, DCD-29, DCD-30).
# ---------------------------------------------------------------------
FP_ARITH = {
    "fadd": "ALU_FADD", "fsub": "ALU_FSUB", "fmul": "ALU_FMUL",
    "fdiv": "ALU_FDIV", "fsqrt": "ALU_FSQRT", "fsgnj": "ALU_FSGNJ",
    "fsgnjn": "ALU_FSGNJN", "fsgnjx": "ALU_FSGNJX", "fmin": "ALU_FMIN",
    "fmax": "ALU_FMAX", "feq": "ALU_FEQ", "flt": "ALU_FLT",
    "fle": "ALU_FLE", "fclass": "ALU_FCLASS", "fmadd": "ALU_FMADD",
    "fmsub": "ALU_FMSUB", "fnmsub": "ALU_FNMSUB", "fnmadd": "ALU_FNMADD",
    # Zfa
    "fli": "ALU_FLI", "fminm": "ALU_FMINM", "fmaxm": "ALU_FMAXM",
    "fround": "ALU_FROUND", "froundnx": "ALU_FROUNDNX",
    "fleq": "ALU_FLEQ", "fltq": "ALU_FLTQ",
}
ZFA = {"fli", "fminm", "fmaxm", "fround", "froundnx", "fleq", "fltq"}
FP_FMT = {"s", "d", "h", "q"}
INTS = {"w": "W", "wu": "WU", "l": "L", "lu": "LU"}
AMO = {
    "amoswap": "AMOSWAP", "amoadd": "AMOADD", "amoxor": "AMOXOR",
    "amoand": "AMOAND", "amoor": "AMOOR", "amomin": "AMOMIN",
    "amomax": "AMOMAX", "amominu": "AMOMINU", "amomaxu": "AMOMAXU",
    "lr": "LR", "sc": "SC",
}
SCALAR_FIXED = {
    "fence": "ALU_FENCE", "pause": "ALU_FENCE", "fence.tso": "ALU_FENCE",
    "fence.i": "ALU_FENCE_I",
    "cbo.inval": "ALU_CBO_INVAL", "cbo.clean": "ALU_CBO_CLEAN",
    "cbo.flush": "ALU_CBO_FLUSH", "cbo.zero": "ALU_CBO_ZERO",
    "ecall": "ALU_ECALL", "ebreak": "ALU_EBREAK", "sret": "ALU_SRET",
    "mret": "ALU_MRET", "wfi": "ALU_WFI",
    "wrs.nto": "ALU_WRS_NTO", "wrs.sto": "ALU_WRS_STO",
    "sfence.vma": "ALU_SFENCE_VMA", "sinval.vma": "ALU_SINVAL_VMA",
    "sfence.w.inval": "ALU_SFENCE_W_INVAL",
    "sfence.inval.ir": "ALU_SFENCE_INVAL_IR",
    "hfence.vvma": "ALU_HFENCE_VVMA", "hfence.gvma": "ALU_HFENCE_GVMA",
    "hinval.vvma": "ALU_HINVAL_VVMA", "hinval.gvma": "ALU_HINVAL_GVMA",
    # HLV / HLVX / HSV: the width-exact load and store (DCD-30)
    "hlv.b": "ALU_LB", "hlv.bu": "ALU_LBU", "hlv.h": "ALU_LH",
    "hlv.hu": "ALU_LHU", "hlvx.hu": "ALU_LHU", "hlv.w": "ALU_LW",
    "hlv.wu": "ALU_LWU", "hlvx.wu": "ALU_LWU", "hlv.d": "ALU_LD",
    "hsv.b": "ALU_SB", "hsv.h": "ALU_SH", "hsv.w": "ALU_SW",
    "hsv.d": "ALU_SD",
    # Zicsr and its aliases: the operation of the encoding
    "csrrw": "ALU_CSRRW", "csrw": "ALU_CSRRW", "unimp": "ALU_CSRRW",
    "csrrs": "ALU_CSRRS", "csrr": "ALU_CSRRS", "csrs": "ALU_CSRRS",
    "csrrc": "ALU_CSRRC", "csrc": "ALU_CSRRC",
    "csrrwi": "ALU_CSRRWI", "csrwi": "ALU_CSRRWI",
    "csrrsi": "ALU_CSRRSI", "csrsi": "ALU_CSRRSI",
    "csrrci": "ALU_CSRRCI", "csrci": "ALU_CSRRCI",
    # FP loads and stores of an implemented width
    "flw": "ALU_FLOAD", "fld": "ALU_FLOAD", "flh": "ALU_FLOAD",
    "fsw": "ALU_FSTORE", "fsd": "ALU_FSTORE", "fsh": "ALU_FSTORE",
    "fcvtmod.w.d": "ALU_FCVTMOD_W_D",
}
# Mnemonics of extensions not implemented (rule NI), by family.
NI_EXACT = {
    "flq": "Q", "fsq": "Q", "fmvh.x.d": "Zfa RV32", "fmvp.d.x": "Zfa RV32",
    "fmvh.x.q": "Q", "fmvp.q.x": "Q", "dret": "Sdext", "mnret": "Smrnmi",
    "sctrclr": "Ssctr", "fcvt.bf16.s": "Zfbfmin", "fcvt.s.bf16": "Zfbfmin",
}


def scalar_op(m):
    """(name, None) for an implemented scalar operation, (None, ext) for a
    mnemonic of an unimplemented extension, (None, None) if unknown."""
    if m in SCALAR_FIXED:
        return SCALAR_FIXED[m], None
    if m in NI_EXACT:
        return None, NI_EXACT[m]
    if m.startswith("mop.r.") or m.startswith("mop.rr."):
        return "ALU_MOP", None
    if re.fullmatch(r"(lb|lh|lw|ld)\.aq|(sb|sh|sw|sd)\.rl", m):
        return None, "Zalasr"
    if m.startswith("ssamoswap"):
        return None, "Zicfiss"
    parts = m.split(".")
    base = parts[0]
    if base in AMO:
        if base == "amocas":
            return None, "Zacas"
        width = parts[1] if len(parts) > 1 else ""
        if width in ("b", "h"):
            return None, "Zabha"
        if width not in ("w", "d"):
            return None, "unknown AMO width"
        return "ALU_%s_%s" % (AMO[base], width.upper()), None
    if base == "amocas":
        return None, "Zacas"
    if base in FP_ARITH and len(parts) == 2 and parts[1] in FP_FMT:
        f = parts[1]
        if f == "q":
            return None, "Q"
        if f == "h":
            return None, "Zfh"            # Zfhmin has none of these
        return FP_ARITH[base], None
    if base == "fcvt" and len(parts) == 3:
        d, s = parts[1], parts[2]
        if "q" in (d, s):
            return None, "Q"
        if d in INTS and s in FP_FMT:
            if s == "h":
                return None, "Zfh"
            return "ALU_FCVT_" + INTS[d], None
        if s in INTS and d in FP_FMT:
            if d == "h":
                return None, "Zfh"
            return "ALU_FCVT_F" + INTS[s], None
        if d in FP_FMT and s in FP_FMT:
            return "ALU_FCVT_FF", None    # S/D/H pairs (Zfhmin)
    if base == "fmv" and len(parts) == 3:
        d, s = parts[1], parts[2]
        if "q" in (d, s):
            return None, "Q"
        if d == "x" and s in ("w", "d", "h"):
            return "ALU_FMV_XF", None
        if s == "x" and d in ("w", "d", "h"):
            return "ALU_FMV_FX", None
    return None, None


# ---------------------------------------------------------------------
# Vector mnemonics -> v_op_class_t names (decode_pkg.sv, DCD-33).
# ---------------------------------------------------------------------
V_EXACT = {
    "vsetvl": "VCFG", "vsetvli": "VCFG", "vsetivli": "VCFG",
    "vmv.v.v": "VOP_VMV", "vmv.v.x": "VOP_VMV", "vmv.v.i": "VOP_VMV",
    "vmv.x.s": "VOP_VMV_XS", "vmv.s.x": "VOP_VMV_SX",
    "vfmv.f.s": "VOP_VFMV_FS", "vfmv.s.f": "VOP_VFMV",
    "vfmv.v.f": "VOP_VFMV",
    "vslide1up.vx": "VOP_VSLIDE1UP_X",
    "vslide1down.vx": "VOP_VSLIDE1DOWN_X",
    "vfwcvt.f.f.v": "VOP_VFWCVT_FF", "vfncvt.f.f.w": "VOP_VFNCVT_FF",
    "vcpop.m": "VOP_VCPOP", "vcpop.v": "VOP_VCPOP_V",
    "vlm.v": "VOP_VLM", "vsm.v": "VOP_VSM",
    "vrgatherei16.vv": "VOP_VRGATHEREI16",
}
# Unratified or unimplemented vector families (rule NI).
# Zvfbfmin's vfwcvtbf16.f.f.v sits in VFUNARY0's 01xxx group (vs1
# 01101), reserved in V 1.0; decode classes that group by vs1[4:3], so
# it is a VRSV encoding (see vrsv_norm), not NI.
V_NI = {
    "vclmul": "Zvbc", "vclmulh": "Zvbc", "vqdot": "unratified",
    "vqdotu": "unratified", "vqdotsu": "unratified",
    "vqdotus": "unratified", "vabd": "unratified", "vabdu": "unratified",
    "vwabda": "unratified", "vwabdau": "unratified", "vpaire": "unratified",
    "vpairo": "unratified", "vzip": "unratified", "vunzipe": "unratified",
    "vunzipo": "unratified", "vabs": "unratified", "vfext": "unratified",
    "vfwmaccbf16": "Zvfbfwma", "vfncvtbf16": "Zvfbfmin",
}
# A width-suffixed vector memory mnemonic: EEW 8..64 is V 1.0; 128 and
# above is the mew=1 space V 1.0 reserves (rule VRSV, see vec_op).
VMEM_RE = [
    (r"vl(\d)re(\d+)\.v", "VOP_VLWHOLE"),
    (r"vs(\d)r\.v", "VOP_VSWHOLE"),
    (r"vlseg\de(\d+)ff\.v", "VOP_VLSEG"),
    (r"vlseg\de(\d+)\.v", "VOP_VLSEG"),
    (r"vsseg\de(\d+)\.v", "VOP_VSSEG"),
    (r"vlsseg\de(\d+)\.v", "VOP_VLSSEG"),
    (r"vssseg\de(\d+)\.v", "VOP_VSSSEG"),
    (r"vluxseg\dei(\d+)\.v", "VOP_VLUXSEG"),
    (r"vloxseg\dei(\d+)\.v", "VOP_VLOXSEG"),
    (r"vsuxseg\dei(\d+)\.v", "VOP_VSUXSEG"),
    (r"vsoxseg\dei(\d+)\.v", "VOP_VSOXSEG"),
    (r"vle(\d+)ff\.v", "VOP_VLFF"),
    (r"vle(\d+)\.v", "VOP_VLE"),
    (r"vse(\d+)\.v", "VOP_VSE"),
    (r"vlse(\d+)\.v", "VOP_VLSE"),
    (r"vsse(\d+)\.v", "VOP_VSSE"),
    (r"vluxei(\d+)\.v", "VOP_VLUXE"),
    (r"vloxei(\d+)\.v", "VOP_VLOXE"),
    (r"vsuxei(\d+)\.v", "VOP_VSUXE"),
    (r"vsoxei(\d+)\.v", "VOP_VSOXE"),
]


def vec_op(m, vvals):
    """(name, None, wide) for a vector operation; (None, ext, False) for
    an unimplemented one; (None, None, False) unknown. wide is True for a
    memory mnemonic with EEW above 64 (mew=1, reserved in V 1.0), and for
    Zvfbfmin's VFUNARY0 slot (vfwcvtbf16.f.f.v, see V_NI)."""
    if m == "vfwcvtbf16.f.f.v":
        return "VOP_VFWCVT", None, True
    if m in V_EXACT:
        return V_EXACT[m], None, False
    base = m.split(".")[0]
    if base in V_NI:
        return None, V_NI[base], False
    if m in ("vfncvt.f.f.q", "vfncvt.sat.f.f.q"):
        return None, "unratified", False
    for rx, nm in VMEM_RE:
        mm = re.fullmatch(rx, m)
        if mm:
            eew = int(mm.groups()[-1])
            return nm, None, eew > 64
    if re.fullmatch(r"vmv[1248]r\.v", m):
        return "VOP_VMVNR", None, False
    if base == "vmerge":
        return "VOP_VMERGE", None, False
    if base == "vfmerge":
        return "VOP_VFMERGE", None, False
    if base in ("vzext", "vsext"):
        return "VOP_" + base.upper(), None, False
    if base == "vfcvt":
        return "VOP_VFCVT", None, False
    if base == "vfwcvt":
        return "VOP_VFWCVT", None, False
    if base == "vfncvt":
        return "VOP_VFNCVT", None, False
    # .wv/.wx/.wf/.wi forms of the widening add/sub are the _W classes;
    # the narrowing shifts and clips (.wv/.wx/.wi) are not.
    suf = m.split(".")[1] if "." in m else ""
    if suf in ("wv", "wx", "wf") and base in ("vwadd", "vwaddu", "vwsub",
                                               "vwsubu", "vfwadd", "vfwsub"):
        nm = "VOP_" + base.upper() + "_W"
        return nm, None, False
    nm = "VOP_" + base.upper()
    if nm in vvals:
        return nm, None, False
    return None, None, False


# ---------------------------------------------------------------------
# Field rules applied to an encoding spike-dasm decodes as implemented.
# ---------------------------------------------------------------------
def has_rm(w):
    """The encoding has an rm field: the FMA opcodes, and OP-FP funct5
    00000 to 00011, 01011, 01000 (FCVT.fmt.fmt, FROUND, FROUNDNX),
    11000 (FCVT int, except FCVTMOD's fixed 001), 11010."""
    op = w & 0x7F
    if op in (0x43, 0x47, 0x4B, 0x4F):
        return True
    if op != 0x53:
        return False
    f5 = (w >> 27) & 0x1F
    if f5 in (0, 1, 2, 3, 0x0B, 0x08, 0x1A):
        return True
    if f5 == 0x18:
        return ((w >> 20) & 0x1F) != 8
    return False


# The class an encoding is counted under in the report: the space, and
# for a rule, what decided it.
SPACES = {0x53: "OP-FP", 0x43: "FMA", 0x47: "FMA", 0x4B: "FMA",
          0x4F: "FMA", 0x2F: "AMO", 0x0F: "MISC-MEM", 0x73: "SYSTEM",
          0x57: "OP-V", 0x07: "LOAD-FP", 0x27: "STORE-FP"}
WHY = {}


def expect(word, text, avals, vvals, norm_text):
    """(illegal, is_vec, op, rule). norm_text maps a normalized word to
    spike-dasm's text for it (VRSV). WHY[word] records the detail."""
    m = text.split()[0] if text.split() else "unknown"
    if m == "unknown":
        steps = vrsv_norm(word)
        if steps:
            nw = apply_norm(word, steps)
            nm_t = norm_text.get(nw, "unknown")
            nm_m = nm_t.split()[0] if nm_t.split() else "unknown"
            if nm_m != "unknown" and nm_m.startswith("v"):
                nm, ni, wide = vec_op(nm_m, vvals)
                if nm is not None:
                    WHY[word] = "%s as %s (%s)" % (
                        "+".join(st for st in steps
                                 if apply_norm(word, [st]) != word),
                        re.sub(r"\d+", "N", nm_m), nm)
                    return 0, 1, vvals[nm], 3
        return 1, 0, 0, 0
    if m.startswith("v"):
        nm, ni, wide = vec_op(m, vvals)
        if ni is not None:
            WHY[word] = "%s %s" % (ni, re.sub(r"\d+", "N", m))
            return 1, 0, 0, 1
        if nm is None:
            sys.exit("expect: no table entry for %08x %s" % (word, text))
        if wide:
            # EEW above 64 (mew=1) is reserved in V 1.0; decode ignores
            # mew and classifies it as the EEW 8..64 form (rule VRSV).
            WHY[word] = "mew/bf16 slot %s (%s)" % (
                re.sub(r"\d+", "N", m), nm)
            return 0, 1, vvals[nm], 3
        return 0, 1, vvals[nm], 0
    nm, ni = scalar_op(m)
    if ni is not None:
        WHY[word] = "%s %s" % (ni, re.sub(r"\.(aq|rl|aqrl)$", "",
                                          re.sub(r"\d+", "N", m)))
        return 1, 0, 0, 1
    if nm is None:
        sys.exit("expect: no table entry for %08x %s" % (word, text))
    rm = (word >> 12) & 7
    if has_rm(word) and rm in (5, 6):
        WHY[word] = "rm %d" % rm
        return 1, 0, 0, 2
    return 0, 0, avals[nm], 0


def main():
    args = sys.argv[1:]
    if "--table" in args:
        args.remove("--table")
        avals = enum_values(args[0], "alu_op_t")
        vvals = enum_values(args[0], "v_op_class_t")
        mn = sorted(set(l.split(" ", 1)[1].split()[0]
                        for l in open(args[1], encoding="ascii")
                        if len(l.split(" ", 1)) > 1 and
                        l.split(" ", 1)[1].split()))
        for m in mn:
            if m == "unknown":
                continue
            if m.startswith("v"):
                nm, ni, wide = vec_op(m, vvals)
                print("%-24s %s" % (m, ("NI " + ni) if ni else
                                    nm + (" (mew=1, VRSV)" if wide else "")))
            else:
                nm, ni = scalar_op(m)
                print("%-24s %s" % (m, ("NI " + ni) if ni else nm))
        return
    if len(args) < 4:
        sys.exit("usage: dec_sweep_expect.py <spike-dasm> <decode_pkg.sv> "
                 "<oracle.txt> <out.hex> [--report <file>]")
    dasm, pkg, oracle, out = args[0], args[1], args[2], args[3]
    rpt = args[args.index("--report") + 1] if "--report" in args else None
    avals = enum_values(pkg, "alu_op_t")
    vvals = enum_values(pkg, "v_op_class_t")
    lines_in = [l.rstrip("\n") for l in open(oracle, encoding="ascii")]
    text_of = {int(l[:8], 16): l[9:] for l in lines_in}
    # The normalized words VRSV needs: from the oracle where it holds
    # them, else from spike-dasm, run with the oracle's --isa.
    need = set()
    for l in lines_in:
        w = int(l[:8], 16)
        if l[9:].split()[0:1] == ["unknown"]:
            st = vrsv_norm(w)
            if st:
                nw = apply_norm(w, st)
                if nw not in text_of:
                    need.add(nw)
    norm_text = dict(text_of)
    if need:
        # The same --isa as the oracle (gen_dec_dasm_oracle.py, beside
        # this file).
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from gen_dec_dasm_oracle import ISA
        ws = sorted(need)
        r = subprocess.run([dasm, "--isa=" + ISA],
                           input="".join("DASM(%08x)\n" % w for w in ws),
                           capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit("expect: spike-dasm failed")
        outl = r.stdout.split("\n")
        for w, t in zip(ws, outl):
            norm_text[w] = t
    counts = {}
    sp_n = {}
    sp_leg = {}
    detail = {}
    n = 0
    with open(out, "w", encoding="ascii") as fo:
        for line in lines_in:
            word = int(line[:8], 16)
            text = line[9:]
            ill, vec, op, rule = expect(word, text, avals, vvals, norm_text)
            counts[rule] = counts.get(rule, 0) + 1
            sp = SPACES[word & 0x7F]
            sp_n[sp] = sp_n.get(sp, 0) + 1
            sp_leg[sp] = sp_leg.get(sp, 0) + (0 if ill else 1)
            if rule:
                k = (rule, sp, WHY.get(word, ""))
                if k not in detail:
                    detail[k] = [0, word]
                detail[k][0] += 1
            fo.write("%08x%01x%01x%02x%04x\n" % (word, ill, vec, op, rule))
            n += 1
    lines = ["sweep expectation: %d encodings (%s)" % (n, ISA_NOTE)]
    for r in sorted(counts):
        lines.append("  rule %d %-6s %7d  %s" % (r, RULES[r][0], counts[r],
                                                  RULES[r][2]))
    lines.append("by space: encodings, expected legal, expected illegal")
    for sp in sorted(sp_n):
        lines.append("  %-9s %7d %7d %7d" % (sp, sp_n[sp], sp_leg[sp],
                                             sp_n[sp] - sp_leg[sp]))
    lines.append("disagreements with spike-dasm, by rule, space and class "
                 "(count, first encoding):")
    for k in sorted(detail):
        lines.append("  %-5s %-9s %-44s %6d  %08x" % (
            RULES[k[0]][0], k[1], k[2], detail[k][0], detail[k][1]))
    print("\n".join(lines[:5 + len(sp_n) + 1]))
    if rpt:
        open(rpt, "w", encoding="ascii").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
