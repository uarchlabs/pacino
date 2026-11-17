// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// trace_count.cc -- the gasket's trace reader over a trace set, checked
// against reference counts (PERF-002 Problem 1, perf_decisions.md
// PF-11, PF-14).
//
// For every trace of a sha256sum list: the file is checked against the
// list BEFORE it is read, then read with cbp::Reader, and its Instr,
// NumBr, 50PercInstr and 50PercNumBr are compared with a reference CSV
// (Workload, Run and those four columns).
//
// USE, from the repository root:
//   perf/build/trace_count [-j N] [--list <sha list>] [--root <dir>]
//                          [--ref <csv>] [--out <csv>]
// Defaults: the training set, perf/cbp2025_training.sha256 under
// CBP_TRACES, against tools/cbp2025/reference_results_training_set.csv.
// --rv selects the changed traces: perf/cbp2025_rv.sha256 under
// CBP_TRACES_RV, against perf/cbp2025_rv_counts.csv.
// --only <group>/<trace>[,...] selects traces. --limit N counts the
// first N records only (the 50Perc rule over those N), and then prints
// the counts without the reference comparison, which is of whole traces.
// Exit status 0 only when every trace was found, checked, read and
// equal to the reference.
// ===================================================================
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <sys/stat.h>

#include "cbp_trace.h"
#include "perf_util.h"

struct Job {
  cbp::ShaEntry e;
  std::string   path;
  off_t         size = 0;
  bool          ok = false;
  std::string   err;
  cbp::Counts   c;
  double        sec = 0;
};

static void die(const std::string& m) {
  std::fprintf(stderr, "trace_count: %s\n  (%s)\n", m.c_str(), cbp::README_REF);
  std::exit(1);
}

int main(int argc, char** argv) {
  std::string repo = cbp::repo_root(argv[0]);
  std::string list = repo + "/perf/cbp2025_training.sha256";
  std::string root = cbp::traces_root(repo);
  std::string ref = repo + "/tools/cbp2025/reference_results_training_set.csv";
  std::string out;
  unsigned jobs = 0;
  uint64_t limit = 0;
  std::string only;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto val = [&]() {
      if (i + 1 >= argc) die("missing value after " + a);
      return std::string(argv[++i]);
    };
    if (a == "-j") jobs = unsigned(std::atoi(val().c_str()));
    else if (a == "--list") list = val();
    else if (a == "--root") root = val();
    else if (a == "--ref") ref = val();
    else if (a == "--out") out = val();
    else if (a == "--limit") limit = std::strtoull(val().c_str(), nullptr, 0);
    else if (a == "--only") only = val();
    else if (a == "--rv") {
      list = repo + "/perf/cbp2025_rv.sha256";
      root = cbp::traces_rv_root(repo);
      ref = repo + "/perf/cbp2025_rv_counts.csv";
    } else die("unknown argument " + a);
  }

  struct stat st;
  if (stat(root.c_str(), &st) != 0 || !S_ISDIR(st.st_mode))
    die("trace directory " + root + " not found; set CBP_TRACES (or "
        "CBP_TRACES_RV for --rv)");
  std::vector<cbp::ShaEntry> ents;
  std::string msg;
  if (!cbp::read_sha_list(list, ents, msg)) die(msg);
  if (!only.empty()) {
    // A comma-separated set of <group>/<trace>.
    std::vector<cbp::ShaEntry> sel;
    std::string s = "," + only + ",";
    for (auto& e : ents)
      if (s.find("," + e.group + "/" + e.trace + ",") != std::string::npos)
        sel.push_back(e);
    if (sel.empty()) die("--only selects no trace");
    ents = sel;
  }
  std::vector<Job> jv(ents.size());
  for (size_t i = 0; i < ents.size(); i++) {
    jv[i].e = ents[i];
    jv[i].path = root + "/" + ents[i].rel;
    if (stat(jv[i].path.c_str(), &st) != 0)
      die("trace " + ents[i].rel + " listed in " + list +
          " not found under " + root);
    jv[i].size = st.st_size;
  }
  // Largest first, so the longest trace does not start last.
  std::vector<size_t> order(jv.size());
  for (size_t i = 0; i < order.size(); i++) order[i] = i;
  std::sort(order.begin(), order.end(),
            [&](size_t a, size_t b) { return jv[a].size > jv[b].size; });

  auto t0 = std::chrono::steady_clock::now();
  std::mutex mx;
  perf::parallel_for(order.size(), jobs, [&](size_t k) {
    Job& j = jv[order[k]];
    auto s0 = std::chrono::steady_clock::now();
    std::string got = cbp::sha256_file(j.path);
    if (got != j.e.sha) {
      j.err = j.path + ": SHA-256 " + (got.empty() ? "unreadable" : got) +
              " does not match the list (" + j.e.sha + ")";
    } else {
      cbp::Reader r;
      cbp::Rec rec;
      if (!r.open(j.path)) j.err = r.err();
      else {
        while ((limit == 0 || j.c.instr < limit) && r.next(rec)) j.c.add(rec);
        if (!r.err().empty()) j.err = r.err();
        j.c.finish();
        j.ok = j.err.empty();
      }
    }
    j.sec = std::chrono::duration<double>(std::chrono::steady_clock::now() -
                                          s0).count();
    std::lock_guard<std::mutex> g(mx);
    if (j.ok)
      std::printf("  done %s/%s  %llu records  %.1f s\n", j.e.group.c_str(),
                  j.e.trace.c_str(), (unsigned long long)j.c.instr, j.sec);
    else
      std::printf("  FAIL %s/%s: %s\n", j.e.group.c_str(), j.e.trace.c_str(),
                  j.err.c_str());
    std::fflush(stdout);
  });
  double wall = std::chrono::duration<double>(std::chrono::steady_clock::now()
                                              - t0).count();

  if (limit != 0) {
    int nf = 0;
    for (auto& j : jv) {
      if (!j.ok) { nf++; continue; }
      std::printf("%s/%s first %llu: Instr %llu NumBr %llu 50PercInstr %llu "
                  "50PercNumBr %llu\n", j.e.group.c_str(), j.e.trace.c_str(),
                  (unsigned long long)limit, (unsigned long long)j.c.instr,
                  (unsigned long long)j.c.numbr,
                  (unsigned long long)j.c.half_instr,
                  (unsigned long long)j.c.half_numbr);
    }
    return nf ? 1 : 0;
  }
  // The comparison.
  perf::Csv rc;
  if (!rc.load(ref)) die("reference results " + ref + " not found");
  std::map<std::string, std::map<std::string, std::string>> rm;
  for (auto& r : rc.rows) rm[r["Workload"] + "/" + r["Run"]] = r;
  int bad = 0, nfail = 0;
  FILE* fo = out.empty() ? nullptr : std::fopen(out.c_str(), "w");
  if (!out.empty() && fo == nullptr) die("cannot write " + out);
  if (fo)
    std::fprintf(fo, "group,trace,Instr,NumBr,50PercInstr,50PercNumBr,"
                     "ref_Instr,ref_NumBr,ref_50PercInstr,ref_50PercNumBr,"
                     "equal\n");
  std::printf("%-8s %-18s %12s %10s %12s %10s  %s\n", "group", "trace",
              "Instr", "NumBr", "50PercInstr", "50PercNumBr", "vs reference");
  for (auto& j : jv) {
    std::string key = j.e.group + "/" + j.e.trace;
    if (!j.ok) { nfail++; continue; }
    auto it = rm.find(key);
    if (it == rm.end()) {
      std::printf("%s: not in the reference results\n", key.c_str());
      bad++;
      continue;
    }
    auto& r = it->second;
    unsigned long long ri = std::strtoull(r["Instr"].c_str(), nullptr, 10);
    unsigned long long rb = std::strtoull(r["NumBr"].c_str(), nullptr, 10);
    unsigned long long rhi =
        std::strtoull(r["50PercInstr"].c_str(), nullptr, 10);
    unsigned long long rhb =
        std::strtoull(r["50PercNumBr"].c_str(), nullptr, 10);
    bool eq = ri == j.c.instr && rb == j.c.numbr && rhi == j.c.half_instr &&
              rhb == j.c.half_numbr;
    if (!eq) bad++;
    std::printf("%-8s %-18s %12llu %10llu %12llu %10llu  %s\n",
                j.e.group.c_str(), j.e.trace.c_str(),
                (unsigned long long)j.c.instr, (unsigned long long)j.c.numbr,
                (unsigned long long)j.c.half_instr,
                (unsigned long long)j.c.half_numbr, eq ? "equal" : "DIFFER");
    if (fo)
      std::fprintf(fo, "%s,%s,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%d\n",
                   j.e.group.c_str(), j.e.trace.c_str(),
                   (unsigned long long)j.c.instr,
                   (unsigned long long)j.c.numbr,
                   (unsigned long long)j.c.half_instr,
                   (unsigned long long)j.c.half_numbr, ri, rb, rhi, rhb,
                   eq ? 1 : 0);
  }
  if (fo) std::fclose(fo);
  std::printf("trace_count: %zu traces, %d failed to read, %d differ from %s;"
              " %.1f s\n", jv.size(), nfail, bad, ref.c_str(), wall);
  if (nfail) std::fprintf(stderr, "trace_count: %d traces failed (%s)\n",
                          nfail, cbp::README_REF);
  return (nfail || bad) ? 1 : 0;
}
