#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# chk_dec_words.py -- the directed test words of tb_instr_decoder T77
# are the assembler's and the disassembler's (BP-124 Problem 3,
# dcd_decisions.md DCD-34).
#
# usage: chk_dec_words.py <clang> <spike-dasm> <tb_instr_decoder.sv> <dir>
#
# Every T77 entry in the testbench carries its word, the source it was
# assembled from and spike-dasm's text for the word:
#
#   tw.push_back('{32'h<word>, "<source>",
#                  "<spike-dasm text>", ...
#
# This script writes every source, in order, to <dir>/t77.s after
# ".option norvc" (so no instruction is compressed), assembles it with
# clang -c for the RISC-V target with -march the extension set of
# DCD-34 (ISA below, the oracle's --isa in clang's order), reads the
# words from the object file's .text section (an ELF64 reader using the
# standard library only), and disassembles each with spike-dasm. A word
# that differs from clang's, or whose spike-dasm text differs from the
# recorded one (spaces collapsed), is an error; the script exits 1.
import os
import re
import struct
import subprocess
import sys

ISA = ("rv64imafdcvh_zicbom_zicbop_zicboz_zicond_zihintntl_zihintpause_"
       "zimop_zawrs_zfa_zfhmin_zcb_zcmop_zba_zbb_zbs_zvbb_zvfhmin_svinval")

ENTRY = re.compile(r"tw\.push_back\('\{32'h([0-9a-f]{8}),\s*\"([^\"]*)\",\s*"
                   r"\"([^\"]*)\"", re.S)


def text_words(obj):
    """The 32-bit words of the .text section of an ELF64 LE object."""
    d = open(obj, "rb").read()
    if d[:4] != b"\x7fELF" or d[4] != 2 or d[5] != 1:
        sys.exit("words: not an ELF64 little-endian object")
    shoff = struct.unpack_from("<Q", d, 0x28)[0]
    esz, num, sx = struct.unpack_from("<HHH", d, 0x3A)
    secs = [struct.unpack_from("<IIQQQQIIQQ", d, shoff + i * esz)
            for i in range(num)]
    so = secs[sx][4]
    for s in secs:
        nm = d[so + s[0]:d.index(b"\0", so + s[0])].decode("ascii")
        if nm == ".text":
            t = d[s[4]:s[4] + s[5]]
            return list(struct.unpack("<%dI" % (len(t) // 4), t))
    sys.exit("words: no .text section")


def main():
    if len(sys.argv) != 5:
        sys.exit("usage: chk_dec_words.py <clang> <spike-dasm> <tb> <dir>")
    clang, dasm, tb, wd = sys.argv[1:]
    ents = ENTRY.findall(open(tb, encoding="ascii").read())
    if not ents:
        sys.exit("words: no T77 entries in " + tb)
    src = os.path.join(wd, "t77.s")
    obj = os.path.join(wd, "t77.o")
    with open(src, "w", encoding="ascii") as f:
        f.write(".option norvc\n.text\n")
        for _, a, _ in ents:
            f.write(a + "\n")
    r = subprocess.run([clang, "--target=riscv64-unknown-elf",
                        "-march=" + ISA, "-c", src, "-o", obj],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("words: clang failed\n" + r.stderr)
    ws = text_words(obj)
    if len(ws) != len(ents):
        sys.exit("words: %d sources, %d words" % (len(ents), len(ws)))
    r = subprocess.run([dasm, "--isa=" + ISA],
                       input="".join("DASM(%08x)\n" % w for w in ws),
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("words: spike-dasm failed")
    texts = r.stdout.split("\n")
    bad = 0
    for (hexw, a, d), w, t in zip(ents, ws, texts):
        if int(hexw, 16) != w:
            print("FAIL word %s for '%s': clang gives %08x" % (hexw, a, w))
            bad += 1
        if " ".join(t.split()) != " ".join(d.split()):
            print("FAIL text for %s '%s': spike-dasm prints '%s', "
                  "recorded '%s'" % (hexw, a, t.strip(), d))
            bad += 1
    print("asm_dec_words: %d words, PASS=%d FAIL=%d" %
          (len(ents), len(ents) * 2 - bad, bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
