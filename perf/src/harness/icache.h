// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// icache.h -- THE I-CACHE SWITCH (PERF-002, perf_decisions.md PF-19), a
// run parameter:
//   real      the L1I as built, filled over its TileLink link from the
//             gasket's memory
//   preload   the real L1I, its arrays first filled, before the path
//             starts, with the code lines of the trace's pages in the
//             pages' first-touch order (the .img map lines), each line
//             to the next way of its set until the set's 8 ways are full
//   perfect   every lookup hits: when the IFU presents a request on the
//             L1I core link (perf_top obs_l1i_*) for a line no way of its
//             set holds, the line is written into the set, round robin
//             over the ways, before the clock edge at which the arrays
//             are read
// PROVISIONAL (PERF-002). The writes go to the three arrays perf.vlt
// makes public (l1i_meta_array tag_mem, val_mem; l1i_data_array
// data_mem); no RTL file changes. The geometry is l1i_pkg.sv's: 2 banks
// on PA bit 6, 64 sets per bank on PA bits 12:7, 8 ways, the tag PA
// bits 47:13, a 64-byte line with byte b at line bits 8b+7:8b.
// ===================================================================
#ifndef PERF_ICACHE_H
#define PERF_ICACHE_H

#include <cstdint>
#include <functional>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "Vperf_top.h"
#include "Vperf_top___024root.h"
#include "supply.h"

namespace perf {

class ICache {
 public:
  ICache(Vperf_top* top, const std::string& mode) : top_(top), mode_(mode) {}
  bool ok(std::string& err) const {
    if (mode_ == "real" || mode_ == "preload" || mode_ == "perfect")
      return true;
    err = "--icache is real, preload or perfect";
    return false;
  }
  // Before the path starts: the preloaded lines.
  template <class M>
  void start(M& mem, const std::vector<std::pair<uint64_t, uint64_t>>& vmap,
             const TraceSupply& sup) {
    rd_ = [&mem](uint64_t pa) { return mem.rd8(pa); };
    if (mode_ != "preload") return;
    for (auto& m : vmap) {
      for (uint64_t off = 0; off < 4096; off += 64) {
        bool code = false;
        for (uint64_t w = 0; w < 64 && !code; w += 4)
          code = sup.image().count(m.first + off + w) != 0;
        if (!code) continue;
        uint64_t pa = m.second + off;
        int b = int((pa >> 6) & 1), s = int((pa >> 7) & 63);
        if (fill_[b][s] >= 8) continue;
        install(pa, fill_[b][s]++);
      }
    }
  }
  // After the inputs settle, before the rising edge.
  void before_edge(int64_t) {
    if (mode_ != "perfect" || !rd_) return;    // from start() on
    if (!top_->obs_l1i_req) return;
    uint64_t pa = top_->obs_l1i_paddr & ~63ull;
    int b = int((pa >> 6) & 1), s = int((pa >> 7) & 63);
    uint64_t tag = pa >> 13;
    for (int w = 0; w < 8; w++)
      if (val(b)[w][s] && tag_arr(b)[w][s] == tag) return;
    install(pa, rr_[b][s]);
    rr_[b][s] = (rr_[b][s] + 1) & 7;
  }
  void after_edge(int64_t) {}
  uint64_t installs() const { return installs_; }

 private:
// The arrays' Verilated names: bank B, unit U (meta or data), array A.
#define PERF_L1I(B, U, A)                                                  \
  perf_top__DOT__dut__DOT__u_l1i__DOT__g_bank__BRA__##B##__KET____DOT__## \
  u_bank__DOT__u_##U##__DOT__##A
  using TagArr  = VlUnpacked<VlUnpacked<QData, 64>, 8>;
  using ValArr  = VlUnpacked<VlUnpacked<CData, 64>, 8>;
  using DataArr = VlUnpacked<VlUnpacked<VlWide<16>, 64>, 8>;
  TagArr& tag_arr(int b) {
    auto* r = top_->rootp;
    return b ? r->PERF_L1I(1, meta, tag_mem) : r->PERF_L1I(0, meta, tag_mem);
  }
  ValArr& val(int b) {
    auto* r = top_->rootp;
    return b ? r->PERF_L1I(1, meta, val_mem) : r->PERF_L1I(0, meta, val_mem);
  }
  DataArr& data(int b) {
    auto* r = top_->rootp;
    return b ? r->PERF_L1I(1, data, data_mem)
             : r->PERF_L1I(0, data, data_mem);
  }
#undef PERF_L1I
  void install(uint64_t pa, int way) {
    int b = int((pa >> 6) & 1), s = int((pa >> 7) & 63);
    tag_arr(b)[way][s] = pa >> 13;
    val(b)[way][s] = 1;
    auto& line = data(b)[way][s];
    for (int w = 0; w < 16; w++) {
      uint32_t v = 0;
      for (int k = 0; k < 4; k++)
        v |= uint32_t(rd_(pa + uint64_t(4 * w + k))) << (8 * k);
      line[w] = v;
    }
    installs_++;
  }

  Vperf_top*  top_;
  std::string mode_;
  uint64_t    installs_ = 0;
  int         fill_[2][64] = {};
  int         rr_[2][64] = {};
  std::function<uint8_t(uint64_t)> rd_;
};

}  // namespace perf

#endif  // PERF_ICACHE_H
