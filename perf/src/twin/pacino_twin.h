// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//
// pacino_twin.h -- THE SOFTWARE TWIN OF PACINO'S TAGE (PERF-005 Phase 4).
//
// A CBP2025 conditional-branch predictor that is pacino's TAGE alone: T0
// and four tagged tables at bp_defines_pkg.sv's parameters, the index and
// tag of tage_hash.h (the harness's history check uses the same code),
// and the rules of tage_cntrl.sv as its planning files state them:
//   the prediction     provider the longest hitting table, alternate the
//                      next hitting one or T0; use_alt_on_na when the
//                      provider counter is weak (011 or 100) and
//                      uaon >= TAGE_UAON_THRES 8 (tage_cntrl_uaon_
//                      update_rules.md, Component Selection)
//   the counters       tage_cntrl_ctr_update_rules.md, rows 1-19
//   the useful bits    tage_cntrl_use_update_rules.md, Table 7, u_eff by
//                      epoch age; the epoch advances every 2^18
//                      predictions (PF-5 tage_aging_interval 262144)
//   the allocation     tage_cntrl_alloc_rules.md: on a TAGE mispredict
//                      with the provider below T4, the shortest table
//                      above it with u_eff 0, USE 00, EPC the epoch;
//                      CTR weak toward the resolved direction, 100 or
//                      011 (PERF-005 R4, in the tree for acceptance; the
//                      rule's 100 with PACINO_TWIN_ALLOC_100=1)
//   use_alt_on_na      uaon_update_rules.md: both providers tagged, the
//                      final provider counter weak; INC when the primary
//                      was wrong and the alternate right, DEC the reverse
// What it is not: no SC, no loop predictor, no FTB. The update is
// IMMEDIATE: each conditional updates right after its own prediction
// (spec_update), so no prediction reads a state older than the last
// branch's update. The PC is the branch's own PC, not a block's start.
// The global history takes one bit per branch, in program order: a
// conditional's outcome, 1 for any other branch (bp_history_decisions.md
// 3.2: a bit per branch on the path, its direction).
#ifndef PACINO_TWIN_H
#define PACINO_TWIN_H

#include <cstdint>
#include <cstdlib>
#include <cstring>

#include "tage_hash.h"

class PacinoTwin {
 public:
  static const int N = 2048;                 // TAGE_TBL_IDX 11
  static const int MAXT = 4;                 // TAGE_MAX_TBL, T4
  static const int UAON_THRES = 8;           // TAGE_UAON_THRES
  static const uint32_t AGING = 262144;      // PF-5, 2^18

  void setup() {
    for (int i = 0; i < N; i++) t0_[i] = 2;  // TAGE_T0_SRAM_INIT_VALUE
    std::memset(e_, 0, sizeof(e_));          // TAGE_SRAM_INIT_VALUE 0
    uaon_ = 0;
    epoch_ = 0;
    interval_ = AGING;
    const char* a = std::getenv("PACINO_TWIN_ALLOC_100");
    alloc100_ = a && a[0] == '1';
  }

  bool predict(uint64_t pc) {
    M& m = m_;
    m = M{};
    m.pc = pc;
    uint32_t f[tg::NT][3] = {};
    for (int t = 1; t < tg::NT; t++) tg::folds(t, gh_, f[t]);
    for (int t = 0; t < tg::NT; t++) {
      m.idx[t] = tg::index(t, pc, f[t]);
      if (t) m.tag[t] = tg::tag(t, pc, f[t]);
    }
    // u_eff by epoch age (use_update_rules.md, Effective USEFUL).
    int ueff[tg::NT] = {};
    bool hit[tg::NT] = {};
    for (int t = 1; t < tg::NT; t++) {
      const E& x = e_[t][m.idx[t]];
      int age = (epoch_ - x.epc) & 3;
      ueff[t] = age == 0 ? x.use : age == 1 ? (x.use >> 1) : 0;
      hit[t] = x.val && x.tag == m.tag[t];
    }
    for (int t = 1; t < tg::NT; t++)
      if (hit[t]) m.prm = t;
    for (int t = 1; t < m.prm; t++)
      if (hit[t]) m.alt = t;
    int t0c = t0_[m.idx[0]];
    int t0c3 = ((t0c & 3) << 1) | (t0c & 1);      // the 3b form (TD#182)
    m.pctr = m.prm ? e_[m.prm][m.idx[m.prm]].ctr : t0c;
    m.actr = m.alt ? e_[m.alt][m.idx[m.alt]].ctr : t0c;
    m.ptk = m.prm ? (m.pctr >> 2) & 1 : (t0c >> 1) & 1;
    m.atk = m.alt ? (m.actr >> 2) & 1 : (t0c >> 1) & 1;
    m.puse = m.prm ? ueff[m.prm] : 0;
    m.ause = m.alt ? ueff[m.alt] : 0;
    bool trig = m.prm && (m.pctr == 3 || m.pctr == 4);
    m.up = !(trig && uaon_ >= UAON_THRES);
    int post = m.up ? (m.prm ? m.pctr : t0c3) : (m.alt ? m.actr : t0c3);
    m.weak = post == 3 || post == 4;
    m.tk = m.up ? m.ptk : m.atk;
    for (int t = m.prm + 1; t < tg::NT; t++)
      if (!m.alc && ueff[t] == 0) m.alc = t;
    // The aging interval (tage_cntrl aging_ff): one step per prediction.
    if (interval_ == 0) { epoch_ = (epoch_ + 1) & 3; interval_ = AGING; }
    else interval_--;
    return m.tk;
  }

  // The immediate update of the last prediction, then its history bit.
  void update(uint64_t pc, bool res) {
    M& m = m_;
    if (pc != m.pc) return;                    // not the predicted branch
    bool mis = m.tk != res;
    bool both0 = !m.prm && !m.alt, diff = m.ptk != m.atk;
    bool pok = m.ptk == res, aok = m.atk == res;
    if (both0) {
      uint8_t& c = t0_[m.idx[0]];
      c = step2(c, res);                       // rows 13a-d
    } else {
      if (m.prm && (m.up || (diff && pok))) {  // rows 1-12, 14-17, 19
        E& x = e_[m.prm][m.idx[m.prm]];
        x.ctr = step3(m.pctr, res);
      }
      if (!m.alt && !m.up) {                   // rows 19.1-19.8
        uint8_t& c = t0_[m.idx[0]];
        c = step2(m.actr, res);
      }
      if (m.alt && (!m.up || (diff && aok))) {
        E& x = e_[m.alt][m.idx[m.alt]];
        x.ctr = step3(m.actr, res);
      }
      if (diff) {                              // Table 7, rows 3-6
        int uc = m.up ? m.prm : m.alt;
        int u = m.up ? m.puse : m.ause;
        if (uc) {
          E& x = e_[uc][m.idx[uc]];
          x.use = uint8_t(!mis ? (u == 3 ? 3 : u + 1) : (u == 0 ? 0 : u - 1));
          x.epc = uint8_t(epoch_);
        }
      }
      if (m.prm && m.alt && m.weak) {          // uaon_update_rules.md
        if (!pok && aok && uaon_ < 15) uaon_++;
        else if (pok && !aok && uaon_ > 0) uaon_--;
      }
    }
    if (mis && m.prm < MAXT && m.alc) {        // alloc_rules.md
      E& x = e_[m.alc][m.idx[m.alc]];
      // PERF-005 R4: CTR weak toward the resolved direction (100 / 011);
      // PACINO_TWIN_ALLOC_100=1 keeps the planning rule's 100 for both.
      x.val = 1; x.ctr = uint8_t(alloc100_ || res ? 4 : 3);
      x.use = 0; x.epc = uint8_t(epoch_);
      x.tag = uint8_t(m.tag[m.alc]);
    }
    m.pc = ~0ull;
  }

  void history(bool bit) { gh_.push(bit); }

 private:
  struct E { uint8_t val, ctr, use, epc, tag; };
  struct M {
    uint64_t pc = ~0ull;
    uint32_t idx[tg::NT] = {}, tag[tg::NT] = {};
    int prm = 0, alt = 0, alc = 0, pctr = 0, actr = 0, puse = 0, ause = 0;
    bool ptk = false, atk = false, up = true, tk = false, weak = false;
  };
  static uint8_t step3(int c, bool tk) {
    return uint8_t(tk ? (c == 7 ? 7 : c + 1) : (c == 0 ? 0 : c - 1));
  }
  static uint8_t step2(int c, bool tk) {
    c &= 3;
    return uint8_t(tk ? (c == 3 ? 3 : c + 1) : (c == 0 ? 0 : c - 1));
  }
  uint8_t t0_[N];
  E e_[tg::NT][N];
  tg::Gh gh_;
  int uaon_ = 0, epoch_ = 0;
  bool alloc100_ = false;
  uint32_t interval_ = AGING;
  M m_;
};

#endif  // PACINO_TWIN_H
