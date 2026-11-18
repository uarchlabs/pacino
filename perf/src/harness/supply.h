// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// supply.h -- THE SUPPLY INTERFACE (PERF-002, perf_decisions.md PF-13).
//
// The timing model asks the supplier for the instruction at a PC, on
// the path it is on, not for the trace's next record:
//   word(va)        the instruction word at va: the code image, or the
//                   filler off the traced path (PF-8)
//   at(k)           the k-th instruction of the committed path, from the
//                   commit point on; the backend compares what fetch
//                   delivers against it
//   redirect(k, pc) a squash: the path continues at instruction k, at pc
//   commit(k)       the commit point: instructions before k are retired
// The trace-driven supplier (TraceSupply) reads the changed trace. An
// execution-driven supplier (a functional simulator rolled back on a
// redirect) implements the same four calls.
// ===================================================================
#ifndef PERF_SUPPLY_H
#define PERF_SUPPLY_H

#include <cstdint>
#include <deque>
#include <string>
#include <unordered_map>
#include <unordered_set>

#include "../cbp_trace.h"

namespace perf {

// One committed-path instruction, as the backend needs it.
struct Inst {
  uint64_t pc;
  uint64_t target;     // taken target; pc + 4 when not taken
  uint8_t  cls;
  bool     taken;
  uint32_t pieces;     // a conditional's NumBr pieces
};

class Supply {
 public:
  virtual ~Supply() = default;
  virtual uint32_t word(uint64_t va) const = 0;
  // false past the end of the path.
  virtual bool at(uint64_t k, Inst& out) = 0;
  virtual void redirect(uint64_t k, uint64_t pc) = 0;
  virtual void commit(uint64_t k) = 0;
};

class TraceSupply : public Supply {
 public:
  // The code image from the whole trace and the stub list; false with
  // err set on a problem. limit 0 is the whole trace.
  bool load(const std::string& trace, const std::string& stubs,
            uint64_t limit, std::string& err);

  uint32_t word(uint64_t va) const override {
    auto it = image_.find(va);
    return it == image_.end() ? 0x00000013u : it->second;
  }
  bool at(uint64_t k, Inst& out) override;
  void redirect(uint64_t, uint64_t) override {}  // the trace is the path
  void commit(uint64_t k) override;
  // Keep the last n retired records readable by at() (PERF-003: the
  // oracle aligns an entry allocated after its predecessor's block has
  // retired, so it reads records behind the commit point).
  void set_keep(uint64_t n) { keep_ = n; }

  uint64_t length() const { return len_; }       // records on the path
  size_t   static_pcs() const { return static_; }
  size_t   stub_count() const { return nstubs_; }
  const std::unordered_map<uint64_t, uint32_t>& image() const {
    return image_;
  }
  const std::string& err() const { return err_; }
  // PCs seen in more than one class; the image holds the most frequent.
  bool conflict(uint64_t pc) const { return conflict_.count(pc) != 0; }
  size_t conflicts() const { return conflict_.size(); }

 private:
  std::unordered_set<uint64_t>           conflict_;
  std::unordered_map<uint64_t, uint32_t> image_;
  cbp::Reader                            rd_;
  std::deque<Inst>                       win_;
  uint64_t                               base_ = 0;   // index of win_[0]
  uint64_t                               keep_ = 0;   // retired, kept
  uint64_t                               len_ = 0;
  size_t                                 static_ = 0;
  size_t                                 nstubs_ = 0;
  std::string                            err_;
};

}  // namespace perf

#endif  // PERF_SUPPLY_H
