#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# gen_dec_dasm_oracle.py -- the decoder sweep oracle (BP-124 Problem 4,
# dcd_decisions.md DCD-34).
#
# usage: gen_dec_dasm_oracle.py <spike-dasm> <out.txt>
#
# THE ORACLE IS spike-dasm, the disassembler of tools/bin, run with
# --isa naming exactly the implemented extensions (ISA below). This
# script enumerates the swept encodings, hands every one to spike-dasm
# as DASM(<word>) and writes one line per encoding:
#
#   <word as 8 lower-case hex digits> <space> <spike-dasm's text>
#
# the text exactly as spike-dasm prints it, its unknown-instruction
# text included. Neither instr_decoder nor its testbench is read.
#
# THE SWEPT SPACES (DCD-34). Every value of every funct, fmt, rm,
# width and selector field of each space. A register field takes the
# values 0 and 1 in every combination with the other register fields;
# a register field that selects an operation for some instruction of
# its opcode also takes all 32 values with every other register field
# at 1:
#   OP-FP      funct5, fmt, rm; rd, rs1, rs2; rs1 and rs2 select
#              (FCVT, FLI, FROUND, FSQRT, FMV, FCLASS)
#   FMA x4     fmt, rm; rd, rs1, rs2, rs3
#   AMO        funct5, aq, rl, funct3; rd, rs1, rs2
#   MISC-MEM   the whole 12-bit immediate, funct3; rd, rs1
#   SYSTEM     the whole funct12 (rs2 included), funct3; rd, rs1
#   OP-V       funct6, vm, funct3; vd, vs2, vs1/rs1; vs1/rs1 selects
#              (VXUNARY0, VWXUNARY0, VFUNARY0/1, VMUNARY0, vmv<nr>r)
#   LOAD-FP    nf, mew, mop, vm, width (all eight values, the scalar
#   STORE-FP   widths included); vd/vs3, rs1, rs2; rs2 selects (lumop,
#              sumop)
# The encodings are written in ascending order of the word; a word in
# two spaces' enumerations is written once.
import os
import subprocess
import sys

ISA = ("rv64imafdcvh_zicbom_zicbop_zicboz_zicond_zihintntl_"
       "zihintpause_zimop_zawrs_zfa_zfhmin_zcb_zcmop_zba_zbb_zbs_zvbb_"
       "zvfhmin_svinval")

OP_FP, OP_AMO, OP_MISC_MEM, OP_SYSTEM = 0x53, 0x2F, 0x0F, 0x73
OP_VECTOR, OP_LOAD_FP, OP_STORE_FP = 0x57, 0x07, 0x27
OP_FMA = (0x43, 0x47, 0x4B, 0x4F)


def regs(n, sel=()):
    """Register field tuples: every {0,1} combination of n fields, plus,
    for each field index in sel, all 32 values with the others at 1."""
    out = []
    for b in range(1 << n):
        out.append(tuple((b >> i) & 1 for i in range(n)))
    for s in sel:
        for v in range(32):
            t = [1] * n
            t[s] = v
            out.append(tuple(t))
    return out


def sweep():
    words = set()
    # OP-FP: funct5 [31:27], fmt [26:25], rm [14:12]; rd, rs1, rs2.
    for f5 in range(32):
        for fmt in range(4):
            for rm in range(8):
                for rd, rs1, rs2 in regs(3, (1, 2)):
                    words.add((f5 << 27) | (fmt << 25) | (rs2 << 20) |
                              (rs1 << 15) | (rm << 12) | (rd << 7) | OP_FP)
    # FMA: rs3 [31:27], fmt [26:25], rm [14:12].
    for op in OP_FMA:
        for fmt in range(4):
            for rm in range(8):
                for rd, rs1, rs2, rs3 in regs(4):
                    words.add((rs3 << 27) | (fmt << 25) | (rs2 << 20) |
                              (rs1 << 15) | (rm << 12) | (rd << 7) | op)
    # AMO: funct5 [31:27], aq [26], rl [25], funct3 [14:12].
    for f5 in range(32):
        for aqrl in range(4):
            for f3 in range(8):
                for rd, rs1, rs2 in regs(3):
                    words.add((f5 << 27) | (aqrl << 25) | (rs2 << 20) |
                              (rs1 << 15) | (f3 << 12) | (rd << 7) | OP_AMO)
    # MISC-MEM and SYSTEM: imm/funct12 [31:20], funct3; rd, rs1.
    for op in (OP_MISC_MEM, OP_SYSTEM):
        for imm in range(4096):
            for f3 in range(8):
                for rd, rs1 in regs(2):
                    words.add((imm << 20) | (rs1 << 15) | (f3 << 12) |
                              (rd << 7) | op)
    # OP-V: funct6 [31:26], vm [25], funct3; vd, vs2, vs1/rs1.
    for f6 in range(64):
        for vm in range(2):
            for f3 in range(8):
                for vd, vs2, vs1 in regs(3, (2,)):
                    words.add((f6 << 26) | (vm << 25) | (vs2 << 20) |
                              (vs1 << 15) | (f3 << 12) | (vd << 7) |
                              OP_VECTOR)
    # LOAD-FP / STORE-FP: nf [31:29], mew [28], mop [27:26], vm [25],
    # width [14:12]; vd/vs3, rs1, rs2/lumop/sumop/vs2.
    for op in (OP_LOAD_FP, OP_STORE_FP):
        for nf in range(8):
            for mew in range(2):
                for mop in range(4):
                    for vm in range(2):
                        for w in range(8):
                            for vd, rs1, rs2 in regs(3, (2,)):
                                words.add((nf << 29) | (mew << 28) |
                                          (mop << 26) | (vm << 25) |
                                          (rs2 << 20) | (rs1 << 15) |
                                          (w << 12) | (vd << 7) | op)
    return sorted(words)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: gen_dec_dasm_oracle.py <spike-dasm> <out.txt>")
    dasm, out_path = sys.argv[1], sys.argv[2]
    if not os.access(dasm, os.X_OK):
        sys.exit("oracle: " + dasm + " is not executable")
    words = sweep()
    stdin = "".join("DASM(%08x)\n" % w for w in words)
    r = subprocess.run([dasm, "--isa=" + ISA], input=stdin,
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("oracle: spike-dasm failed: " + r.stderr)
    lines = r.stdout.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if len(lines) != len(words):
        sys.exit("oracle: %d words in, %d lines out" %
                 (len(words), len(lines)))
    with open(out_path, "w", encoding="ascii") as f:
        for w, t in zip(words, lines):
            f.write("%08x %s\n" % (w, t))
    print("oracle: %d encodings, isa %s" % (len(words), ISA))


if __name__ == "__main__":
    main()
