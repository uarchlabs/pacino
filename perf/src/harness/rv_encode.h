// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// rv_encode.h -- the RISC-V words of the code image (PERF-002, PF-4,
// PF-13). One 32-bit instruction of the trace record's class at each
// traced PC; the veneer stubs; the filler (PF-8).
//
// PROVISIONAL, PERF-002. The class encodings:
//   ALU 0       addi  x7, x0, k        k = (pc >> 2) & 0x7ff
//   LOAD 1      ld    x7, k(x6)
//   STORE 2     sd    x7, k(x6)
//   COND 3      bne   x6, x7, T - pc   T the traced taken target, or
//                                      pc + 8 when never taken
//   JMP_DIR 4   jal   x0, T - pc       (DIRECT_UNC)
//   JMP_IND 5   jalr  x0, 0(x6)        (INDIRECT_NONRET)
//   FP 6        fadd.d f(k&31), f1, f2
//   SLOW 7      mul   x(k&31), x6, x7
//   CALL_DIR 9  jal   x1, T - pc       (DIRECT_CALL)
//   CALL_IND 10 jalr  x1, 0(x6)        (INDIRECT_CALL)
//   RET 11      jalr  x0, 0(x1)        (RETURN)
//   filler      addi  x0, x0, 0, the 4-byte nop
// k puts the PC's low bits in the word, so that a word fetched from the
// wrong physical page differs from the one the image holds there.
// ===================================================================
#ifndef PERF_RV_ENCODE_H
#define PERF_RV_ENCODE_H

#include <cstdint>

namespace rv {

constexpr uint32_t NOP = 0x00000013;   // addi x0, x0, 0, the filler
constexpr int X0 = 0, RA = 1, T1 = 6, T2 = 7;

inline uint32_t i_type(int op, int f3, int rd, int rs1, int32_t imm) {
  return (uint32_t(imm & 0xfff) << 20) | (uint32_t(rs1) << 15) |
         (uint32_t(f3) << 12) | (uint32_t(rd) << 7) | uint32_t(op);
}
inline uint32_t s_type(int op, int f3, int rs1, int rs2, int32_t imm) {
  return (uint32_t((imm >> 5) & 0x7f) << 25) | (uint32_t(rs2) << 20) |
         (uint32_t(rs1) << 15) | (uint32_t(f3) << 12) |
         (uint32_t(imm & 0x1f) << 7) | uint32_t(op);
}
inline uint32_t r_type(int op, int f3, int f7, int rd, int rs1, int rs2) {
  return (uint32_t(f7) << 25) | (uint32_t(rs2) << 20) |
         (uint32_t(rs1) << 15) | (uint32_t(f3) << 12) |
         (uint32_t(rd) << 7) | uint32_t(op);
}
// B-type, imm a signed even offset within -4096..4094.
inline uint32_t b_type(int f3, int rs1, int rs2, int32_t imm) {
  uint32_t u = uint32_t(imm);
  return (((u >> 12) & 1) << 31) | (((u >> 5) & 0x3f) << 25) |
         (uint32_t(rs2) << 20) | (uint32_t(rs1) << 15) |
         (uint32_t(f3) << 12) | (((u >> 1) & 0xf) << 8) |
         (((u >> 11) & 1) << 7) | 0x63u;
}
// J-type, imm a signed even offset within +-1 MiB.
inline uint32_t jal(int rd, int32_t imm) {
  uint32_t u = uint32_t(imm);
  return (((u >> 20) & 1) << 31) | (((u >> 1) & 0x3ff) << 21) |
         (((u >> 11) & 1) << 20) | (((u >> 12) & 0xff) << 12) |
         (uint32_t(rd) << 7) | 0x6fu;
}
inline uint32_t jalr(int rd, int rs1, int32_t imm) {
  return i_type(0x67, 0, rd, rs1, imm);
}
inline uint32_t auipc(int rd, int32_t hi20) {
  return (uint32_t(hi20) << 12) | (uint32_t(rd) << 7) | 0x17u;
}

// The word for a record of class cls at pc, taken target t (pc + 8 for
// a conditional never seen taken).
inline uint32_t class_word(uint8_t cls, uint64_t pc, uint64_t t) {
  int32_t k = int32_t((pc >> 2) & 0x7ff);
  int32_t off = int32_t(int64_t(t - pc));
  switch (cls) {
    case 0:  return i_type(0x13, 0, T2, X0, k);
    case 1:  return i_type(0x03, 3, T2, T1, k);
    case 2:  return s_type(0x23, 3, T1, T2, k);
    case 3:  return b_type(1, T1, T2, off);
    case 4:  return jal(X0, off);
    case 5:  return jalr(X0, T1, 0);
    case 6:  return r_type(0x53, 7, 0x01, k & 31, 1, 2);
    case 7:  return r_type(0x33, 0, 0x01, k & 31, T1, T2);
    case 9:  return jal(RA, off);
    case 10: return jalr(RA, T1, 0);
    case 11: return jalr(X0, RA, 0);
    default: return NOP;
  }
}

// bp_br_type_e of a record class, as the backend resolves it.
enum BrType : uint8_t {
  BT_COND = 0, BT_DIRECT_CALL = 1, BT_INDIRECT_CALL = 2, BT_RETURN = 3,
  BT_INDIRECT_NONRET = 4, BT_DIRECT_UNC = 5, BT_NO_BRANCH = 6,
  BT_RETURN_CALL = 7
};
inline uint8_t br_type_of(uint8_t cls) {
  switch (cls) {
    case 3:  return BT_COND;
    case 4:  return BT_DIRECT_UNC;
    case 5:  return BT_INDIRECT_NONRET;
    case 9:  return BT_DIRECT_CALL;
    case 10: return BT_INDIRECT_CALL;
    case 11: return BT_RETURN;
    default: return BT_NO_BRANCH;
  }
}

}  // namespace rv

#endif  // PERF_RV_ENCODE_H
