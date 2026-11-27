// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//
// tage_hash.h -- PACINO'S TAGE INDEX AND TAG (PERF-005). One code for the
// harness's history check (perf_fe.cc, Phase 3) and the software twin
// (perf/src/twin, Phase 4).
//
//   the parameters   bp_defines_pkg.sv:395-403 (T0 and T1-T4: history
//                    lengths, fold widths, index and tag widths) and
//                    PC_HASH_SHIFT 2 (:54)
//   the history      a global history, newest bit at age 0
//                    (bp_history_decisions.md 6.1)
//   the fold         age i lands at (i + W - 1) mod W, XOR over the H
//                    bits of the window (6.2, the full recompute)
//   the hash         tage_table_hash_rules.md: index
//                    ((PC >> PC_HASH_SHIFT) ^ fh)[IDX-1:0]; tag
//                    ((PC >> IDX) ^ fh1 ^ (fh2 << 1))[TAG-1:0]; T0
//                    PC[12:2], no tag
#ifndef PERF_TAGE_HASH_H
#define PERF_TAGE_HASH_H

#include <cstdint>

namespace tg {

static const int NT = 5;
static const int PC_SHIFT = 2;
static const int HIST[NT] = {0, 8, 13, 32, 119};
static const int FH[NT] = {0, 8, 11, 11, 11};
static const int FH1[NT] = {0, 8, 8, 8, 8};
static const int FH2[NT] = {0, 7, 7, 7, 7};
static const int IDX[NT] = {11, 11, 11, 11, 11};
static const int TAG[NT] = {0, 8, 8, 8, 8};

// A global history, newest bit at head; 512 bits hold the longest window.
struct Gh {
  uint8_t  b[512] = {};
  uint32_t h = 0;
  void push(int x) { h = (h + 1) & 511u; b[h] = uint8_t(x & 1); }
  int at(int age) const { return b[(h - uint32_t(age)) & 511u]; }
  uint32_t fold(int H, int W) const {
    uint32_t f = 0;
    for (int i = 0; i < H; i++)
      if (at(i)) f ^= 1u << ((i + W - 1) % W);
    return f;
  }
};

// The three folds of table t (1-4): index, tag 1, tag 2.
inline void folds(int t, const Gh& g, uint32_t f[3]) {
  f[0] = g.fold(HIST[t], FH[t]);
  f[1] = g.fold(HIST[t], FH1[t]);
  f[2] = g.fold(HIST[t], FH2[t]);
}

// The index of table t from the PC and the folds (t 0: no history).
inline uint32_t index(int t, uint64_t pc, const uint32_t f[3]) {
  uint32_t m = (1u << IDX[t]) - 1;
  if (t == 0) return uint32_t(pc >> PC_SHIFT) & m;
  return uint32_t((pc >> PC_SHIFT) ^ f[0]) & m;
}

// The tag of table t (1-4).
inline uint32_t tag(int t, uint64_t pc, const uint32_t f[3]) {
  uint32_t m = (1u << TAG[t]) - 1;
  return uint32_t((pc >> IDX[t]) ^ f[1] ^ (f[2] << 1)) & m;
}

}  // namespace tg

#endif  // PERF_TAGE_HASH_H
