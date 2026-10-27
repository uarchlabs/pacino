#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# gen_ifu_rvc_exp_oracle.py -- independent expected expansions for
# ifu_rvc_exp (BP-117 Problem 4).
#
# usage: gen_ifu_rvc_exp_oracle.py <toolchain bin dir> <out.hex>
#
# THE ORACLE IS LLVM, not a model written in this project. For every
# 16-bit encoding (bits [1:0] != 2'b11, 49152 of them):
#
#   0. clang's integrated assembler places it, as a raw .insn, in the
#      .text of an object file (BP-132; before it, GNU objcopy wrapped
#      the raw bytes, and the oracle is the same file either way).
#   1. llvm-objdump decodes it for riscv64 with C, Zcb and Zcmop on.
#      Its instruction printer UNCOMPRESSES an RVC instruction through
#      LLVM's own compress-pattern table before printing, so the text
#      it prints is LLVM's 32-bit expansion, not a 16-bit form.
#   2. clang's integrated assembler re-encodes that text with C OFF,
#      so every line becomes exactly one 32-bit word, read from the
#      object's .text by the ELF reader below.
#
# THE TOOLS ARE llvm-objdump AND clang, from the directory given as the
# first argument (the ifu Makefile passes $(EMBECOSM_BIN), rtl/Vars.mk,
# BP-132, TD#176). Nothing else outside the repository is run.
#
# Neither step reads ifu_rvc_exp, the module under test, or
# tb_ifu_rvc_exp. The expansion, the immediate scrambles and the
# 32-bit field placement all come from LLVM.
#
# WHERE LLVM IS NOT USED, the class says so and the expected value
# comes from the specification (the RVC chapter's HINT and reserved
# tables, and Zcmop), stated per class below. Those classes are
# small and named; they are the "not comparable" set of the BP-117
# Results Capture.
#
# Output: one line per 16-bit value 0x0000..0xFFFF, index = encoding,
# 40 bits as 10 hex digits: {class[7:0], expected[31:0]}. Lines for
# bits [1:0] == 2'b11 carry class 0 and are not read. Comment lines
# (//) at the top name the toolchain and the class counts.
#
# Classes:
#   0  NA       bits [1:0] == 2'b11, not a 16-bit encoding
#   1  LLVM     LLVM expanded it; expected is LLVM's word
#   2  RSV      reserved by the spec, and LLVM has no instruction
#               there either (<unknown>). Spec: raises illegal
#               instruction. Expected is the IFU's carrier
#               {16'h0000, c}; its bits [1:0] are not 2'b11, so no
#               32-bit decoder accepts it
#   3  ILL0     0x0000, the defined illegal instruction. Spec:
#               raises illegal instruction. Expected 32'h0
#   4  HINT     a spec HINT. LLVM decodes it and keeps it 16-bit
#               (no compress pattern), so the expected word is the
#               spec's expansion applied to LLVM's decoded operands
#   5  MOP      C.MOP.n (Zcmop). The spec defines no 32-bit form:
#               it writes no register. Expected is the canonical
#               NOP, the IFU's choice; NOT an oracle comparison
#   6  RSVLLVM  reserved by the spec, but LLVM decodes it: C.LUI with
#               nzimm = 0 and rd not x2 (rd = x0 as a HINT, any other
#               rd as lui rd, 0; the odd rd up to x15 are C.MOP.n and
#               class 5). The RVC chapter: "The code points with
#               nzimm=0 are reserved". The spec decides: as RSV
#   7  MVALT    C.MV. LLVM expands to addi rd, rs2, 0; the spec says
#               add rd, x0, rs2. Same architectural effect, different
#               word. Expected is the spec's word, built from LLVM's
#               decoded operands by the spec rule; NOT an oracle
#               comparison of the encoding
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

CLS_NA, CLS_LLVM, CLS_RSV, CLS_ILL0, CLS_HINT, CLS_MOP, CLS_RSVLLVM, \
    CLS_MVALT = range(8)
CLS_NAME = ["NA", "LLVM", "RSV", "ILL0", "HINT", "MOP", "RSVLLVM",
            "MVALT"]

# RV64 with every compressed extension RVA23 mandates: C (with Zcd
# for C.FLD/C.FSD/C.FLDSP/C.FSDSP), Zcb and Zcmop, and the base
# extensions their expansions land in (M for c.mul, Zba for
# c.zext.w, Zbb for c.sext.b/h and c.zext.h). Zcmp and Zcmt are not
# in RVA23 and overlap Zcd. Zicfiss is not enabled: its c.sspush and
# c.sspopchk are pseudo-ops on c.mop.1 and c.mop.5.
DIS_ATTR = "+c,+m,+f,+d,+zba,+zbb,+zcb,+zcmop"
ASM_ARCH = "rv64imafd_zba_zbb"
# Step 0's object: the same extension set as DIS_ATTR. The bytes are
# raw .insn words; the set only names the target.
RAW_ARCH = "rv64imfdc_zba_zbb_zcb_zcmop"

ABI = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4, "t0": 5, "t1": 6,
    "t2": 7, "s0": 8, "fp": 8, "s1": 9, "a0": 10, "a1": 11, "a2": 12,
    "a3": 13, "a4": 14, "a5": 15, "a6": 16, "a7": 17, "s2": 18,
    "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23, "s8": 24,
    "s9": 25, "s10": 26, "s11": 27, "t3": 28, "t4": 29, "t5": 30,
    "t6": 31,
}

LINE_RE = re.compile(r"^\s*([0-9a-f]+):\s+([0-9a-f]{4})\s+(\S+)\s*(.*)$")
TGT_RE = re.compile(r"0x([0-9a-f]+) <[^>]*>")


def text_bytes(obj):
    """The .text section of an ELF64 little-endian object."""
    d = open(obj, "rb").read()
    if d[:4] != b"\x7fELF" or d[4] != 2 or d[5] != 1:
        sys.exit("oracle: " + obj + " is not an ELF64 LE object")
    shoff = struct.unpack_from("<Q", d, 0x28)[0]
    esz, num, sx = struct.unpack_from("<HHH", d, 0x3A)
    secs = [struct.unpack_from("<IIQQQQIIQQ", d, shoff + i * esz)
            for i in range(num)]
    so = secs[sx][4]
    for sh in secs:
        nm = d[so + sh[0]:d.index(b"\0", so + sh[0])].decode("ascii")
        if nm == ".text":
            return d[sh[4]:sh[4] + sh[5]]
    sys.exit("oracle: no .text section in " + obj)


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit("oracle: command failed: " + " ".join(cmd))
    return r.stdout


def disasm(tc, elf, aliases):
    cmd = [os.path.join(tc, "llvm-objdump"), "-d", "-z",
           "--mattr=" + DIS_ATTR]
    if not aliases:
        cmd += ["-M", "no-aliases"]
    out = {}
    for ln in run(cmd + [elf]).splitlines():
        m = LINE_RE.match(ln)
        if m:
            out[int(m.group(1), 16)] = (m.group(3), m.group(4).strip())
    return out


def i_type(op, f3, rd, rs1, imm):
    return ((imm & 0xfff) << 20) | (rs1 << 15) | (f3 << 12) | \
        (rd << 7) | op


def r_type(op, f3, f7, rd, rs1, rs2):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | \
        (rd << 7) | op


def num(s):
    return int(s, 0)


def hint_word(mn, ops):
    # The spec's expansion of an RVC HINT, applied to the operands LLVM
    # decoded. The RVC chapter's HINT table: each HINT is the ordinary
    # instruction with rd = x0 or a zero immediate or shift amount, and
    # expands exactly as the non-HINT form does.
    a = [o.strip() for o in ops.split(",")] if ops else []
    OP_IMM, OP, LUI = 0x13, 0x33, 0x37
    if mn == "c.nop":                       # addi x0, x0, nzimm
        return i_type(OP_IMM, 0, 0, 0, num(a[0]))
    if mn == "c.addi":                      # addi rd, rd, 0
        r = ABI[a[0]]
        return i_type(OP_IMM, 0, r, r, num(a[1]))
    if mn == "c.li":                        # addi x0, x0, imm
        return i_type(OP_IMM, 0, ABI[a[0]], 0, num(a[1]))
    if mn == "c.lui":                       # lui x0, nzimm
        return ((num(a[1]) & 0xfffff) << 12) | (ABI[a[0]] << 7) | LUI
    if mn == "c.mv":                        # add x0, x0, rs2
        return r_type(OP, 0, 0, ABI[a[0]], 0, ABI[a[1]])
    if mn == "c.add":                       # add x0, x0, rs2
        r = ABI[a[0]]
        return r_type(OP, 0, 0, r, r, ABI[a[1]])
    if mn == "c.slli":                      # slli rd, rd, shamt
        r = ABI[a[0]]
        return i_type(OP_IMM, 1, r, r, num(a[1]) & 0x3f)
    if mn in ("c.slli64", "c.srli64", "c.srai64"):   # shamt = 0
        r = ABI[a[0]]
        f3 = 1 if mn == "c.slli64" else 5
        f7 = 0x20 if mn == "c.srai64" else 0
        return i_type(OP_IMM, f3, r, r, f7 << 5)
    return None


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: gen_ifu_rvc_exp_oracle.py <tc bin> <out.hex>")
    tc, out_path = sys.argv[1], sys.argv[2]
    for t in ("llvm-objdump", "clang"):
        if not os.access(os.path.join(tc, t), os.X_OK):
            sys.exit("oracle: " + t + " not found in " + tc +
                     " (EMBECOSM_BIN, rtl/Vars.mk)")

    encs = [c for c in range(65536) if (c & 3) != 3]
    work = tempfile.mkdtemp(prefix="rvc_oracle.")
    rawf = os.path.join(work, "c.s")
    elf = os.path.join(work, "c.o")
    with open(rawf, "w") as f:
        f.write("\t.option rvc\n\t.text\n_start:\n")
        for c in encs:
            f.write("\t.insn 0x%04x\n" % c)
    run([os.path.join(tc, "clang"), "--target=riscv64-unknown-elf",
         "-march=" + RAW_ARCH, "-mno-relax", "-c", rawf, "-o", elf])
    if text_bytes(elf) != b"".join(struct.pack("<H", c) for c in encs):
        sys.exit("oracle: the object's .text is not the 16-bit encodings")

    dis_a = disasm(tc, elf, True)
    dis_n = disasm(tc, elf, False)

    cls = [CLS_NA] * 65536
    exp = [0] * 65536
    asm = []            # (encoding, text) re-encoded by clang
    for i, c in enumerate(encs):
        addr = 2 * i
        if addr not in dis_a or addr not in dis_n:
            sys.exit("oracle: no disassembly at 0x%x (%04x)" % (addr, c))
        mn, ops = dis_a[addr]
        nmn, nops = dis_n[addr]
        if c == 0:
            cls[c], exp[c] = CLS_ILL0, 0
        elif mn == "<unknown>":
            cls[c], exp[c] = CLS_RSV, c
        elif nmn.startswith("c.mop."):
            cls[c], exp[c] = CLS_MOP, 0x00000013
        elif nmn == "c.lui" and num(nops.split(",")[1]) == 0:
            cls[c], exp[c] = CLS_RSVLLVM, c
        elif nmn == "c.mv":
            # Operands from LLVM's decode, word from the spec's rule.
            a = [o.strip() for o in nops.split(",")]
            cls[c] = CLS_MVALT
            exp[c] = r_type(0x33, 0, 0, ABI[a[0]], 0, ABI[a[1]])
        elif mn.startswith("c."):
            # Kept 16-bit by LLVM: a HINT.
            w = hint_word(mn, ops)
            if w is None:
                sys.exit("oracle: unhandled 16-bit form %04x: %s %s"
                         % (c, mn, ops))
            cls[c], exp[c] = CLS_HINT, w
        else:
            # LLVM's 32-bit expansion. A pc-relative target is printed
            # as an address; give the assembler the offset instead.
            m = TGT_RE.search(ops)
            if m:
                ops = TGT_RE.sub(str(int(m.group(1), 16) - addr), ops)
            cls[c] = CLS_LLVM
            asm.append((c, mn + " " + ops))

    src = os.path.join(work, "x.s")
    obj = os.path.join(work, "x.o")
    with open(src, "w") as f:
        f.write("\t.option norvc\n\t.text\n")
        for _, t in asm:
            f.write("\t" + t + "\n")
    run([os.path.join(tc, "clang"), "--target=riscv64-unknown-elf",
         "-march=" + ASM_ARCH, "-mno-relax", "-c", src, "-o", obj])
    data = text_bytes(obj)
    if len(data) != 4 * len(asm):
        sys.exit("oracle: %d bytes for %d lines; a line did not encode "
                 "to one 32-bit word" % (len(data), len(asm)))
    for k, (c, _) in enumerate(asm):
        exp[c] = struct.unpack_from("<I", data, 4 * k)[0]
        if (exp[c] & 3) != 3:
            sys.exit("oracle: %04x re-encoded as a 16-bit word" % c)

    ver = run([os.path.join(tc, "llvm-objdump"), "--version"])
    ver = [v.strip() for v in ver.splitlines() if "version" in v][0]
    counts = [cls[c] for c in range(65536)]
    with open(out_path, "w") as f:
        f.write("// ifu_rvc_exp oracle, gen_ifu_rvc_exp_oracle.py. "
                "Do not edit.\n")
        f.write("// " + ver + "\n")
        f.write("// disassembly --mattr=" + DIS_ATTR + "\n")
        f.write("// re-encode -march=" + ASM_ARCH + "\n")
        f.write("// {class[7:0], expected[31:0]}, index = encoding\n")
        for k, n in enumerate(CLS_NAME):
            f.write("// class %d %-7s %5d\n" % (k, n, counts.count(k)))
        for c in range(65536):
            f.write("%02x%08x\n" % (cls[c], exp[c]))

    shutil.rmtree(work)
    print("oracle: %s" % ver)
    for k, n in enumerate(CLS_NAME):
        if k != CLS_NA:
            print("oracle: class %d %-7s %5d" % (k, n, counts.count(k)))
    print("oracle: %d encodings, %d by LLVM" %
          (len(encs), counts.count(CLS_LLVM)))


if __name__ == "__main__":
    main()
