// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// dist.h -- the backend timing distributions of perf_decisions.md PF-18
// (PERF-002). A distribution is named with its range:
//   fixed:V                  V every time (minimum = maximum = V)
//   V                        the same
//   uniform:MIN:MAX          every value in [MIN, MAX] equally likely
//   geometric:MIN:MAX:MEAN   MIN plus a geometric count with mean
//                            MEAN - MIN, clipped to [MIN, MAX]
//   table:FILE               a file of "value weight" lines; MIN and
//                            MAX are its smallest and largest value
// Normal and triangular are not built (PF-18, built first: fixed,
// uniform, geometric and table). When MIN equals MAX the value is fixed
// and no random number is drawn.
// ===================================================================
#ifndef PERF_DIST_H
#define PERF_DIST_H

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <random>
#include <sstream>
#include <string>
#include <vector>

namespace perf {

class Dist {
 public:
  // Parse spec; false with err set on a bad spec.
  bool parse(const std::string& spec, std::string& err) {
    spec_ = spec;
    std::vector<std::string> f;
    std::stringstream ss(spec);
    std::string x;
    while (std::getline(ss, x, ':')) f.push_back(x);
    auto num = [&](const std::string& s, int64_t& v) {
      char* e = nullptr;
      v = std::strtoll(s.c_str(), &e, 10);
      return !s.empty() && *e == 0 && v >= 0;
    };
    int64_t a = 0, b = 0, c = 0;
    if (f.size() == 1 && num(f[0], a)) {
      kind_ = FIXED; lo_ = hi_ = a;
    } else if (f.size() == 2 && f[0] == "fixed" && num(f[1], a)) {
      kind_ = FIXED; lo_ = hi_ = a;
    } else if (f.size() == 3 && f[0] == "uniform" && num(f[1], a) &&
               num(f[2], b) && a <= b) {
      kind_ = UNIFORM; lo_ = a; hi_ = b;
    } else if (f.size() == 4 && f[0] == "geometric" && num(f[1], a) &&
               num(f[2], b) && num(f[3], c) && a <= b && c >= a) {
      kind_ = GEOMETRIC; lo_ = a; hi_ = b; mean_ = double(c);
    } else if (f.size() == 2 && f[0] == "table") {
      kind_ = TABLE;
      std::ifstream in(f[1]);
      if (!in) { err = "cannot read the table " + f[1]; return false; }
      std::string line;
      while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::stringstream ls(line);
        int64_t v;
        double w;
        if (!(ls >> v >> w) || v < 0 || w < 0) {
          err = "bad line in the table " + f[1] + ": " + line;
          return false;
        }
        vals_.push_back(v);
        wts_.push_back(w);
      }
      if (vals_.empty()) { err = "empty table " + f[1]; return false; }
      lo_ = hi_ = vals_[0];
      for (int64_t v : vals_) {
        lo_ = std::min(lo_, v);
        hi_ = std::max(hi_, v);
      }
      pick_ = std::discrete_distribution<size_t>(wts_.begin(), wts_.end());
    } else {
      err = "bad distribution '" + spec + "'";
      return false;
    }
    if (kind_ != FIXED && lo_ == hi_) kind_ = FIXED;
    return true;
  }

  int64_t draw(std::mt19937_64& g) {
    switch (kind_) {
      case FIXED:
        return lo_;
      case UNIFORM:
        return std::uniform_int_distribution<int64_t>(lo_, hi_)(g);
      case GEOMETRIC: {
        double m = mean_ - double(lo_);
        if (m <= 0) return lo_;
        // P(success) for a geometric count of mean m.
        std::geometric_distribution<int64_t> d(1.0 / (m + 1.0));
        int64_t v = lo_ + d(g);
        return v > hi_ ? hi_ : v;
      }
      case TABLE:
        return vals_[pick_(g)];
    }
    return lo_;
  }

  int64_t lo() const { return lo_; }
  int64_t hi() const { return hi_; }
  bool fixed() const { return kind_ == FIXED; }
  const std::string& spec() const { return spec_; }

 private:
  enum Kind { FIXED, UNIFORM, GEOMETRIC, TABLE };
  Kind                                 kind_ = FIXED;
  int64_t                              lo_ = 0, hi_ = 0;
  double                               mean_ = 0;
  std::vector<int64_t>                 vals_;
  std::vector<double>                  wts_;
  std::discrete_distribution<size_t>   pick_;
  std::string                          spec_;
};

}  // namespace perf

#endif  // PERF_DIST_H
