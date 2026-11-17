// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// supply.cc -- the trace-driven supplier and its code image (PERF-002,
// PF-4, PF-13). See supply.h and rv_encode.h.
// ===================================================================
#include "supply.h"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>

#include "rv_encode.h"

namespace perf {

bool TraceSupply::load(const std::string& trace, const std::string& stubs,
                       uint64_t limit, std::string& err) {
  // The class and first taken target of every PC on the path. A PC seen
  // in more than one class (rewritten code; web_11_trace has 9) holds
  // its most frequent class, the first seen on a tie (PROVISIONAL,
  // PERF-002); it joins conflict_.
  struct Pc {
    uint8_t  cls;
    bool     has_t;
    uint64_t t;
    uint32_t n[12];
  };
  std::unordered_map<uint64_t, Pc> pcs;
  {
    cbp::Reader r;
    cbp::Rec x;
    if (!r.open(trace)) { err = r.err(); return false; }
    while ((limit == 0 || r.records() < limit) && r.next(x)) {
      auto it = pcs.find(x.pc);
      if (it == pcs.end()) {
        Pc p{};
        p.cls = x.cls;
        it = pcs.emplace(x.pc, p).first;
      }
      Pc& p = it->second;
      p.n[x.cls]++;
      if (x.cls != p.cls) {
        conflict_.insert(x.pc);
        if (p.n[x.cls] > p.n[p.cls]) p.cls = x.cls;
      }
      if (x.taken && cbp::is_direct(x.cls) && !p.has_t) {
        p.has_t = true;
        p.t = x.target;
      }
    }
    if (!r.err().empty()) { err = r.err(); return false; }
    len_ = r.records();
  }
  static_ = pcs.size();
  image_.reserve(pcs.size() * 2);
  for (auto& kv : pcs) {
    uint64_t t = kv.second.has_t ? kv.second.t : kv.first + 8;
    image_[kv.first] = rv::class_word(kv.second.cls, kv.first, t);
  }
  // The stubs (veneer.cc), over the class words of their records.
  std::ifstream in(stubs);
  if (!in) { err = "cannot read the stub list " + stubs; return false; }
  std::string line;
  while (std::getline(in, line)) {
    if (line.empty() || line[0] == '#') continue;
    std::stringstream ss(line);
    std::string sa, form, sd;
    if (!(ss >> sa >> form >> sd)) {
      err = "bad stub line: " + line;
      return false;
    }
    uint64_t s = std::stoull(sa, nullptr, 16);
    uint64_t d = std::stoull(sd, nullptr, 16);
    int64_t off = int64_t(d - s);
    if (form == "jal" || form == "jal4") {
      image_[s] = rv::jal(rv::X0, int32_t(off));
    } else if (form == "auipc") {
      int64_t hi = (off + 0x800) >> 12;
      int64_t lo = off - (hi << 12);
      image_[s] = rv::auipc(rv::T1, int32_t(hi & 0xfffff));
      image_[s + 4] = rv::jalr(rv::X0, rv::T1, int32_t(lo));
    } else if (form == "long") {
      image_[s] = rv::auipc(rv::T1, 0);
      image_[s + 4] = rv::i_type(0x03, 3, rv::T1, rv::T1, 16);
      image_[s + 8] = rv::jalr(rv::X0, rv::T1, 0);
      image_[s + 16] = uint32_t(d);
      image_[s + 20] = uint32_t(d >> 32);
    } else {
      err = "bad stub form: " + line;
      return false;
    }
    nstubs_++;
  }
  if (!rd_.open(trace)) { err = rd_.err(); return false; }
  if (limit != 0 && limit < len_) len_ = limit;
  return true;
}

bool TraceSupply::at(uint64_t k, Inst& out) {
  if (k >= len_ || k < base_) return false;
  while (base_ + win_.size() <= k) {
    cbp::Rec x;
    if (!rd_.next(x)) {
      err_ = rd_.err();
      return false;
    }
    win_.push_back(Inst{x.pc, x.target, x.cls, x.taken, x.pieces});
  }
  out = win_[size_t(k - base_)];
  return true;
}

void TraceSupply::commit(uint64_t k) {
  while (base_ < k && !win_.empty()) {
    win_.pop_front();
    base_++;
  }
}

}  // namespace perf
