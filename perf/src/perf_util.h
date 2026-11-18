// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// perf_util.h -- small helpers shared by the perf tools (PERF-002): a
// CSV reader, a parallel job loop, and string formatting.
// ===================================================================
#ifndef PERF_UTIL_H
#define PERF_UTIL_H

#include <atomic>
#include <cstdarg>
#include <cstdio>
#include <fstream>
#include <functional>
#include <map>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace perf {

// A CSV with a header row, no quoted fields; rows keyed by column.
struct Csv {
  std::vector<std::string>                        cols;
  std::vector<std::map<std::string, std::string>> rows;

  bool load(const std::string& path) {
    std::ifstream in(path);
    if (!in) return false;
    std::string line;
    if (!std::getline(in, line)) return false;
    cols = split(line);
    while (std::getline(in, line)) {
      if (line.empty()) continue;
      std::vector<std::string> v = split(line);
      std::map<std::string, std::string> r;
      for (size_t i = 0; i < cols.size() && i < v.size(); i++)
        r[cols[i]] = v[i];
      rows.push_back(r);
    }
    return true;
  }

  static std::vector<std::string> split(const std::string& s) {
    std::vector<std::string> v;
    std::string cur;
    for (char c : s) {
      if (c == ',') { v.push_back(cur); cur.clear(); }
      else if (c != '\r') cur.push_back(c);
    }
    v.push_back(cur);
    return v;
  }
};

// The default thread count of the perf tools (PF-22): 75% of the
// hardware threads, rounded down, at least 1.
inline unsigned default_jobs() {
  unsigned j = std::thread::hardware_concurrency() * 3 / 4;
  return j == 0 ? 1 : j;
}

// Run fn(i) for i in [0, n) on up to jobs threads (0: default_jobs()),
// largest-first order left to the caller.
inline void parallel_for(size_t n, unsigned jobs,
                         const std::function<void(size_t)>& fn) {
  if (jobs == 0) jobs = default_jobs();
  if (jobs > n) jobs = unsigned(n);
  std::atomic<size_t> next{0};
  std::vector<std::thread> th;
  for (unsigned t = 0; t < jobs; t++)
    th.emplace_back([&]() {
      for (size_t i = next++; i < n; i = next++) fn(i);
    });
  for (auto& t : th) t.join();
}

inline std::string fmt(const char* f, ...) {
  char b[1024];
  va_list ap;
  va_start(ap, f);
  std::vsnprintf(b, sizeof(b), f, ap);
  va_end(ap);
  return b;
}

}  // namespace perf

#endif  // PERF_UTIL_H
