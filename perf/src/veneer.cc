// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// veneer.cc -- THE CHANGED TRACES (PERF-002 Problem 2, perf_decisions.md
// PF-15): a direct branch beyond its RISC-V reach goes through a
// veneer, as Arm's linkers do.
//
// PER TRACE, from the training set (CBP_TRACES, checked against
// perf/cbp2025_training.sha256 before it is read):
//   pass 1   the executed PCs, every PC's class, every direct branch's
//            taken targets, and the far sites: a taken conditional
//            beyond -4096..+4094 or a direct jump or call beyond
//            -1 MiB..+1 MiB-2 (tools/scan_traces.py BR_MIN to JAL_MAX)
//   plan     the multi-target treatment, then one stub per far site
//            unless a stub for the same target is already in reach
//   pass 2   the changed trace, CBP's record format, to
//            CBP_TRACES_RV/training_traces/<group>/<trace>.gz
//   pass 3   READ BACK: the changed trace against the original, record
//            by record; its counts and its page list
//
// THE STUB (PROVISIONAL, PERF-002). A stub takes 8 free bytes within the
// branch's reach: two 4-byte words, neither an executed PC of the trace
// nor another stub's, and not at the branch's pc + 4. The branch keeps
// its PC and condition; its taken target becomes the stub. The stub
// jumps to the traced target:
//   JAL    the target within the stub's jal reach
//            S     jal x0, T              record: class 4, taken, T
//            S+4   (filler, never executed)
//   AUIPC  the target within auipc + jalr reach, +-2 GiB
//            S     auipc t1, hi           record: class 0, out x16
//            S+4   jalr x0, lo(t1)        record: class 5, taken, T,
//                                         in x16
//   LONG   beyond +-2 GiB (an Arm long veneer, ldr literal and br)
//            S     auipc t1, 0            record: class 0, out x16
//            S+4   ld t1, 16(t1)          record: class 1, ea S+16,
//                                         size 8, in x16, out x16 = T
//            S+8   jalr x0, 0(t1)         record: class 5, taken, T,
//                                         in x16
//            S+12  (filler)
//            S+16  the 8-byte literal T
//          24 free bytes, S 8-byte aligned.
// Register 16 is the trace's x16, the scratch register Arm's veneers
// use (IP0); the code image's register is t1 (x6). A stub serves every
// far branch in reach to its target. Conditional sites are placed
// first (the tighter reach), then jumps and calls, which reuse any stub
// in reach. A far conditional with no free 8 bytes within 4 KiB goes in
// two hops: a 4-byte jal within 4 KiB to a stub placed by the jump
// rule. Each stub's page joins the page list.
//
// MULTI-TARGET DIRECT BRANCHES (PROVISIONAL, PERF-002). A static
// instruction has one encoding, so a direct jump or call with more than
// one traced target is changed to its indirect class (4 -> 5, 9 -> 10),
// its one changed byte; it then needs no veneer.
//
// OUTPUT, under CBP_TRACES_RV (default ../cbp_traces_rv):
//   training_traces/<group>/<trace>.gz   the changed trace
//   pages/<group>/<trace>.pages          the page list, first touch
//   pages/<group>/<trace>.stubs          one line per stub
// and in perf/ (--set, the whole training set only):
//   cbp2025_rv_veneers.csv   the counts per trace
//   cbp2025_rv_counts.csv    Instr, NumBr, 50PercInstr, 50PercNumBr of
//                            each changed trace, the reference's columns
//
// USE, from the repository root:
//   perf/build/veneer [-j N] [--analyze] [--only <group>/<trace>] ...
// --analyze plans and counts without writing.
// ===================================================================
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <set>
#include <sys/stat.h>
#include <unordered_map>
#include <unordered_set>

#include "cbp_trace.h"
#include "perf_util.h"

using cbp::Rec;

namespace {

constexpr int64_t BR_MIN = -4096, BR_MAX = 4094;
constexpr int64_t JAL_MIN = -(int64_t(1) << 20);
constexpr int64_t JAL_MAX = (int64_t(1) << 20) - 2;
constexpr uint8_t VREG = 16;          // the trace's veneer register

enum Form { F_JAL = 0, F_AUIPC = 1, F_LONG = 2, F_JAL4 = 3 };
const char* FORM_NAME[] = {"jal", "auipc", "long", "jal4"};

struct Stub {
  uint64_t s;        // its address
  uint64_t t;        // where it jumps: the traced target, or a far stub
  Form     form;
  int      users = 0;
};

struct Site {
  uint64_t pc;
  uint8_t  cls;
  uint64_t t;        // the traced target
  uint64_t dyn = 0;  // taken passes
  int      stub = -1;
  bool     two_hop = false;
};

bool canonical57(uint64_t a) {
  uint64_t top = a >> 56;
  return top == 0 || top == 0xff;
}

bool in_reach(uint64_t from, uint64_t to, int64_t lo, int64_t hi) {
  int64_t d = int64_t(to - from);
  return d >= lo && d <= hi;
}

// auipc + jalr from S reaches T when hi fits 20 signed bits.
bool auipc_reach(uint64_t s, uint64_t t) {
  int64_t d = int64_t(t - s);
  int64_t hi = (d + 0x800) >> 12;
  return hi >= -(int64_t(1) << 19) && hi < (int64_t(1) << 19);
}

struct Result {
  std::string group, trace, err;
  bool        ok = false;
  uint64_t    orig_records = 0, new_records = 0, added = 0;
  uint64_t    far_cond_sites = 0, far_cond_dyn = 0;
  uint64_t    far_jal_sites = 0, far_jal_dyn = 0;
  uint64_t    stubs = 0, by_form[4] = {}, shared_sites = 0, two_hop = 0;
  uint64_t    unplaced = 0, multi_pcs = 0, multi_cond = 0, reclass_dyn = 0;
  uint64_t    conflict_pcs = 0, cond_t_pc4 = 0;
  uint64_t    patched = 0, check_bad = 0;
  uint64_t    pages = 0, stub_only_pages = 0;
  cbp::Counts c;
  double      sec = 0;
};

// The bytes of a record.
struct RecBuf {
  std::vector<uint8_t> b;
  void u8(uint8_t v) { b.push_back(v); }
  void u64(uint64_t v) {
    for (int i = 0; i < 8; i++) b.push_back(uint8_t(v >> (8 * i)));
  }
};

// The records of one pass through stub k, appended to out.
void stub_records(const std::vector<Stub>& stubs, int k,
                  std::vector<uint8_t>& out) {
  const Stub& st = stubs[size_t(k)];
  RecBuf r;
  switch (st.form) {
    case F_JAL:
    case F_JAL4:
      r.u64(st.s); r.u8(cbp::C_JMP_DIR); r.u8(1); r.u64(st.t);
      r.u8(0); r.u8(0);
      break;
    case F_AUIPC: {
      int64_t d = int64_t(st.t - st.s);
      int64_t hi = (d + 0x800) >> 12;
      uint64_t t1 = st.s + uint64_t(hi << 12);
      r.u64(st.s); r.u8(cbp::C_ALU); r.u8(0); r.u8(1); r.u8(VREG);
      r.u64(t1);
      r.u64(st.s + 4); r.u8(cbp::C_JMP_IND); r.u8(1); r.u64(st.t);
      r.u8(1); r.u8(VREG); r.u8(0);
      break;
    }
    case F_LONG:
      r.u64(st.s); r.u8(cbp::C_ALU); r.u8(0); r.u8(1); r.u8(VREG);
      r.u64(st.s);
      r.u64(st.s + 4); r.u8(cbp::C_LOAD); r.u64(st.s + 16); r.u8(8);
      r.u8(0); r.u8(1); r.u8(VREG); r.u8(1); r.u8(VREG); r.u64(st.t);
      r.u64(st.s + 8); r.u8(cbp::C_JMP_IND); r.u8(1); r.u64(st.t);
      r.u8(1); r.u8(VREG); r.u8(0);
      break;
  }
  out.insert(out.end(), r.b.begin(), r.b.end());
}

class Planner {
 public:
  Planner(const std::unordered_set<uint64_t>& exec) : exec_(exec) {}
  std::vector<Stub> stubs;

  bool free4(uint64_t a) const {
    return canonical57(a) && !exec_.count(a) && !used_.count(a);
  }
  bool free_n(uint64_t a, int words) const {
    for (int i = 0; i < words; i++)
      if (!free4(a + 4 * uint64_t(i))) return false;
    return true;
  }
  void take(uint64_t a, int words) {
    for (int i = 0; i < words; i++) used_.insert(a + 4 * uint64_t(i));
  }

  // The nearest address from pc within [lo, hi] with `words` free
  // words, aligned to `align` bytes; 0 if none.
  uint64_t find(uint64_t pc, int64_t lo, int64_t hi, int words,
                uint64_t align) const {
    for (int64_t k = 4; k <= std::max(-lo, hi); k += 4) {
      for (int sgn = 0; sgn < 2; sgn++) {
        int64_t d = sgn ? -k : k;
        if (d < lo || d > hi) continue;
        // Never the branch's own fall-through: a taken conditional to
        // pc + 4 cannot be told from a not-taken one (CBP uarchsim.cc
        // asserts against it, and its direction would not show in the
        // fetched stream).
        if (d == 4) continue;
        uint64_t a = pc + uint64_t(d);
        if ((a & (align - 1)) != 0) continue;
        if (free_n(a, words)) return a;
      }
    }
    return 0;
  }

  // An existing stub to t within [lo, hi] of pc.
  int reuse(uint64_t pc, uint64_t t, int64_t lo, int64_t hi) const {
    auto it = by_t_.find(t);
    if (it == by_t_.end()) return -1;
    int best = -1;
    int64_t bd = 0;
    for (int k : it->second) {
      int64_t d = int64_t(stubs[size_t(k)].s - pc);
      if (d < lo || d > hi) continue;
      if (d == 4) continue;   // not the branch's fall-through (find())
      int64_t ad = d < 0 ? -d : d;
      if (best < 0 || ad < bd) { best = k; bd = ad; }
    }
    return best;
  }

  // A new stub to t at the nearest free place within [lo, hi] of pc.
  int place(uint64_t pc, uint64_t t, int64_t lo, int64_t hi) {
    // The jal form needs 8 bytes (PA proposal), the auipc form 8, the
    // long form 24, 8-byte aligned.
    uint64_t a = find(pc, lo, hi, 2, 4);
    if (a == 0) return -1;
    Form f;
    if (in_reach(a, t, JAL_MIN, JAL_MAX)) f = F_JAL;
    else if (auipc_reach(a, t)) f = F_AUIPC;
    else {
      a = find(pc, lo, hi, 6, 8);
      if (a == 0) return -1;
      f = F_LONG;
    }
    take(a, f == F_LONG ? 6 : 2);
    Stub st;
    st.s = a;
    st.t = t;
    st.form = f;
    stubs.push_back(st);
    int k = int(stubs.size() - 1);
    by_t_[t].push_back(k);
    return k;
  }

  // A 4-byte jal hop within [lo, hi] of pc to dest.
  int hop(uint64_t pc, uint64_t dest, int64_t lo, int64_t hi) {
    uint64_t a = find(pc, lo, hi, 1, 4);
    if (a == 0 || !in_reach(a, dest, JAL_MIN, JAL_MAX)) return -1;
    take(a, 1);
    Stub st;
    st.s = a;
    st.t = dest;
    st.form = F_JAL4;
    stubs.push_back(st);
    return int(stubs.size() - 1);
  }

 private:
  const std::unordered_set<uint64_t>&         exec_;
  std::unordered_set<uint64_t>                used_;
  std::unordered_map<uint64_t, std::vector<int>> by_t_;
};

struct Ctx {
  std::string repo, in_root, out_root;
  bool        analyze = false;
};

bool mkdirs(const std::string& p) {
  std::string cur;
  for (size_t i = 0; i < p.size(); i++) {
    cur.push_back(p[i]);
    if (p[i] == '/' || i + 1 == p.size()) {
      if (cur.size() > 1) ::mkdir(cur.c_str(), 0775);
    }
  }
  struct stat st;
  return stat(p.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

void run_trace(const Ctx& cx, const cbp::ShaEntry& e, Result& res) {
  res.group = e.group;
  res.trace = e.trace;
  std::string in = cx.in_root + "/" + e.rel;
  std::string got = cbp::sha256_file(in);
  if (got != e.sha) {
    res.err = in + ": SHA-256 " + (got.empty() ? "unreadable" : got) +
              " does not match perf/cbp2025_training.sha256";
    return;
  }

  // ---- pass 1 --------------------------------------------------------
  std::unordered_set<uint64_t>           exec;
  std::unordered_map<uint64_t, uint8_t>  cls_of;
  std::unordered_set<uint64_t>           conflict;
  std::unordered_map<uint64_t, uint64_t> first_t;
  std::unordered_set<uint64_t>           multi;
  std::map<uint64_t, Site>               far;     // by pc
  {
    cbp::Reader r;
    Rec x;
    if (!r.open(in)) { res.err = r.err(); return; }
    while (r.next(x)) {
      exec.insert(x.pc);
      auto ci = cls_of.find(x.pc);
      if (ci == cls_of.end()) cls_of.emplace(x.pc, x.cls);
      else if (ci->second != x.cls) conflict.insert(x.pc);
      if (cbp::is_direct(x.cls) && x.taken) {
        auto fi = first_t.find(x.pc);
        if (fi == first_t.end()) first_t.emplace(x.pc, x.target);
        else if (fi->second != x.target) multi.insert(x.pc);
        bool is_c = x.cls == cbp::C_COND;
        if (is_c && x.target == x.pc + 4) res.cond_t_pc4++;
        bool farb = is_c ? !in_reach(x.pc, x.target, BR_MIN, BR_MAX)
                         : !in_reach(x.pc, x.target, JAL_MIN, JAL_MAX);
        if (farb) {
          auto& s = far[x.pc];
          s.pc = x.pc;
          s.cls = x.cls;
          s.t = x.target;
          s.dyn++;
        }
      }
    }
    if (!r.err().empty()) { res.err = r.err(); return; }
    res.orig_records = r.records();
  }
  res.conflict_pcs = conflict.size();
  res.multi_pcs = multi.size();
  if (!conflict.empty() || !multi.empty()) {
    // The classes and records of each such PC, for the report.
    std::map<uint64_t, std::map<int, uint64_t>> seen;
    cbp::Reader r;
    Rec x;
    if (r.open(in)) {
      while (r.next(x))
        if (conflict.count(x.pc) || multi.count(x.pc))
          seen[x.pc][x.cls]++;
    }
    for (auto& kv : seen) {
      std::string s;
      for (auto& cv : kv.second)
        s += perf::fmt(" class %d x %llu", cv.first,
                       (unsigned long long)cv.second);
      std::printf("  %s/%s %s pc %016llx:%s\n", e.group.c_str(),
                  e.trace.c_str(), conflict.count(kv.first) ? "conflict"
                                                            : "multi",
                  (unsigned long long)kv.first, s.c_str());
    }
  }

  // ---- plan ----------------------------------------------------------
  std::unordered_set<uint64_t> reclass;     // multi-target, made indirect
  for (uint64_t pc : multi) {
    if (cls_of[pc] == cbp::C_COND) res.multi_cond++;
    else reclass.insert(pc);
  }
  Planner pl(exec);
  std::vector<Site*> conds, jals;
  for (auto& kv : far) {
    if (reclass.count(kv.first)) continue;
    if (multi.count(kv.first)) continue;    // a multi-target conditional
    if (kv.second.cls == cbp::C_COND) conds.push_back(&kv.second);
    else jals.push_back(&kv.second);
  }
  // Grouped by target, then pc, so that sharing is found in order.
  auto by_t = [](const Site* a, const Site* b) {
    return a->t != b->t ? a->t < b->t : a->pc < b->pc;
  };
  std::sort(conds.begin(), conds.end(), by_t);
  std::sort(jals.begin(), jals.end(), by_t);
  for (Site* s : conds) {
    res.far_cond_sites++;
    res.far_cond_dyn += s->dyn;
    int k = pl.reuse(s->pc, s->t, BR_MIN, BR_MAX);
    if (k < 0) k = pl.place(s->pc, s->t, BR_MIN, BR_MAX);
    if (k < 0) {
      // Two hops: a jal within 4 KiB to a stub by the jump rule. The
      // hop's place is found first, the far stub from it.
      uint64_t h = pl.find(s->pc, BR_MIN, BR_MAX, 1, 4);
      if (h != 0) {
        int f = pl.reuse(h, s->t, JAL_MIN, JAL_MAX);
        if (f < 0) f = pl.place(h, s->t, JAL_MIN, JAL_MAX);
        if (f >= 0) k = pl.hop(s->pc, pl.stubs[size_t(f)].s, BR_MIN, BR_MAX);
        if (k >= 0) {
          s->two_hop = true;
          pl.stubs[size_t(f)].users++;
          res.two_hop++;
        }
      }
    }
    if (k < 0) { res.unplaced++; continue; }
    s->stub = k;
    pl.stubs[size_t(k)].users++;
  }
  for (Site* s : jals) {
    res.far_jal_sites++;
    res.far_jal_dyn += s->dyn;
    int k = pl.reuse(s->pc, s->t, JAL_MIN, JAL_MAX);
    if (k < 0) k = pl.place(s->pc, s->t, JAL_MIN, JAL_MAX);
    if (k < 0) { res.unplaced++; continue; }
    s->stub = k;
    pl.stubs[size_t(k)].users++;
  }
  res.stubs = pl.stubs.size();
  for (auto& st : pl.stubs) res.by_form[st.form]++;
  for (auto& kv : far)
    if (kv.second.stub >= 0 && pl.stubs[size_t(kv.second.stub)].users > 1)
      res.shared_sites++;
  // The far stub of a two-hop chain, by the hop's address.
  std::unordered_map<uint64_t, int> stub_at;
  for (size_t k = 0; k < pl.stubs.size(); k++)
    stub_at[pl.stubs[k].s] = int(k);
  if (res.unplaced != 0 || res.multi_cond != 0) {
    res.err = perf::fmt("%llu far branches without a stub, %llu "
                        "multi-target conditionals",
                        (unsigned long long)res.unplaced,
                        (unsigned long long)res.multi_cond);
    return;
  }
  if (cx.analyze) {
    for (auto& kv : far)
      if (reclass.count(kv.first)) res.reclass_dyn += kv.second.dyn;
    res.ok = true;
    return;
  }

  // The records a taken pass through site pc adds.
  auto pass_records = [&](const Site& s, std::vector<uint8_t>& out) {
    int k = s.stub;
    stub_records(pl.stubs, k, out);
    if (pl.stubs[size_t(k)].form == F_JAL4)
      stub_records(pl.stubs, stub_at.at(pl.stubs[size_t(k)].t), out);
  };

  // ---- pass 2: the changed trace -------------------------------------
  std::string odir = cx.out_root + "/training_traces/" + e.group;
  std::string pdir = cx.out_root + "/pages/" + e.group;
  if (!mkdirs(odir) || !mkdirs(pdir)) {
    res.err = "cannot create " + odir + " or " + pdir;
    return;
  }
  std::string outp = odir + "/" + e.trace + ".gz";
  {
    cbp::Reader r;
    cbp::Writer w;
    Rec x;
    std::vector<uint8_t> tmp;
    if (!r.open(in)) { res.err = r.err(); return; }
    if (!w.open(outp, 6)) { res.err = w.err(); return; }
    while (r.next(x)) {
      auto fi = (x.taken && cbp::is_direct(x.cls)) ? far.find(x.pc)
                                                   : far.end();
      if (fi != far.end() && fi->second.stub >= 0) {
        tmp.assign(x.raw, x.raw + x.len);
        uint64_t s = pl.stubs[size_t(fi->second.stub)].s;
        std::memcpy(tmp.data() + x.target_off, &s, 8);
        pass_records(fi->second, tmp);
        w.write(tmp.data(), tmp.size());
      } else if (reclass.count(x.pc)) {
        tmp.assign(x.raw, x.raw + x.len);
        tmp[8] = (x.cls == cbp::C_JMP_DIR) ? cbp::C_JMP_IND
                                           : cbp::C_CALL_IND;
        w.write(tmp.data(), tmp.size());
        res.reclass_dyn++;
      } else {
        w.write(x.raw, x.len);
      }
    }
    if (!r.err().empty()) { res.err = r.err(); return; }
    if (!w.close()) { res.err = outp + ": " + w.err(); return; }
  }

  // ---- pass 3: read back ---------------------------------------------
  // Every original record in order, equal byte for byte but for a far
  // branch's target (the stub) and a multi-target class byte; after
  // each taken far branch, exactly its stub's records; nothing else.
  std::vector<uint64_t> page_order;
  std::unordered_set<uint64_t> page_seen, orig_pages;
  for (uint64_t pc : exec) orig_pages.insert(pc >> 12);
  {
    cbp::Reader ro, rc;
    Rec a, b;
    std::vector<uint8_t> want, stubb;
    if (!ro.open(in) || !rc.open(outp)) {
      res.err = "read back: cannot open";
      return;
    }
    auto see = [&](const Rec& y) {
      // A taken conditional to its own fall-through fails the check.
      if (y.cls == cbp::C_COND && y.taken && y.target == y.pc + 4)
        res.check_bad++;
      res.c.add(y);
      uint64_t pg = y.pc >> 12;
      if (page_seen.insert(pg).second) page_order.push_back(pg);
    };
    while (ro.next(a)) {
      want.assign(a.raw, a.raw + a.len);
      auto fi = (a.taken && cbp::is_direct(a.cls)) ? far.find(a.pc)
                                                   : far.end();
      bool veneered = fi != far.end() && fi->second.stub >= 0;
      if (veneered) {
        uint64_t s = pl.stubs[size_t(fi->second.stub)].s;
        std::memcpy(want.data() + a.target_off, &s, 8);
      } else if (reclass.count(a.pc)) {
        want[8] = (a.cls == cbp::C_JMP_DIR) ? cbp::C_JMP_IND
                                            : cbp::C_CALL_IND;
      }
      if (!rc.next(b) || b.len != want.size() ||
          std::memcmp(b.raw, want.data(), b.len) != 0) {
        res.check_bad++;
        break;
      }
      see(b);
      if (veneered) {
        res.patched++;
        stubb.clear();
        pass_records(fi->second, stubb);
        size_t off = 0;
        while (off < stubb.size()) {
          if (!rc.next(b) || off + b.len > stubb.size() ||
              std::memcmp(b.raw, stubb.data() + off, b.len) != 0) {
            res.check_bad++;
            break;
          }
          see(b);
          off += b.len;
          res.added++;
        }
        if (res.check_bad) break;
      }
    }
    if (res.check_bad == 0 && rc.next(b)) res.check_bad++;   // extra
    if (!ro.err().empty() || !rc.err().empty()) {
      res.err = "read back: " + ro.err() + rc.err();
      return;
    }
    res.new_records = rc.records();
  }
  res.c.finish();
  if (res.check_bad != 0) {
    res.err = "read back: the changed trace differs from the plan";
    return;
  }
  res.pages = page_order.size();
  for (uint64_t pg : page_order)
    if (!orig_pages.count(pg)) res.stub_only_pages++;

  // The page list and the stub list.
  std::string pp = pdir + "/" + e.trace + ".pages";
  FILE* f = std::fopen(pp.c_str(), "w");
  if (f == nullptr) { res.err = "cannot write " + pp; return; }
  std::fprintf(f, "# %s/%s: the code pages of the changed trace, first "
               "touch (PERF-002, PF-17)\n", e.group.c_str(), e.trace.c_str());
  for (uint64_t pg : page_order)
    std::fprintf(f, "%016llx\n", (unsigned long long)(pg << 12));
  std::fclose(f);
  std::string sp = pdir + "/" + e.trace + ".stubs";
  f = std::fopen(sp.c_str(), "w");
  if (f == nullptr) { res.err = "cannot write " + sp; return; }
  std::fprintf(f, "# %s/%s: <address> <form> <destination> <users>\n",
               e.group.c_str(), e.trace.c_str());
  for (auto& st : pl.stubs)
    std::fprintf(f, "%016llx %s %016llx %d\n", (unsigned long long)st.s,
                 FORM_NAME[st.form], (unsigned long long)st.t, st.users);
  std::fclose(f);
  res.ok = true;
}

void die(const std::string& m) {
  std::fprintf(stderr, "veneer: %s\n  (%s)\n", m.c_str(), cbp::README_REF);
  std::exit(1);
}

}  // namespace

int main(int argc, char** argv) {
  Ctx cx;
  cx.repo = cbp::repo_root(argv[0]);
  cx.in_root = cbp::traces_root(cx.repo);
  cx.out_root = cbp::traces_rv_root(cx.repo);
  unsigned jobs = 0;
  std::set<std::string> only;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    if (a == "-j" && i + 1 < argc) jobs = unsigned(std::atoi(argv[++i]));
    else if (a == "--analyze") cx.analyze = true;
    else if (a == "--only" && i + 1 < argc) only.insert(argv[++i]);
    else die("unknown argument " + a);
  }
  struct stat st;
  if (stat(cx.in_root.c_str(), &st) != 0 || !S_ISDIR(st.st_mode))
    die("trace directory " + cx.in_root + " not found; set CBP_TRACES");
  std::vector<cbp::ShaEntry> ents, sel;
  std::string msg;
  if (!cbp::read_sha_list(cx.repo + "/perf/cbp2025_training.sha256", ents,
                          msg))
    die(msg);
  for (auto& e : ents)
    if (only.empty() || only.count(e.group + "/" + e.trace)) sel.push_back(e);
  if (sel.empty()) die("no trace selected");
  for (auto& e : sel)
    if (stat((cx.in_root + "/" + e.rel).c_str(), &st) != 0)
      die("trace " + e.rel + " not found under CBP_TRACES=" + cx.in_root);
  if (!cx.analyze && !mkdirs(cx.out_root))
    die("cannot create CBP_TRACES_RV=" + cx.out_root);

  std::vector<size_t> order(sel.size());
  std::vector<off_t> size(sel.size());
  for (size_t i = 0; i < sel.size(); i++) {
    order[i] = i;
    stat((cx.in_root + "/" + sel[i].rel).c_str(), &st);
    size[i] = st.st_size;
  }
  std::sort(order.begin(), order.end(),
            [&](size_t a, size_t b) { return size[a] > size[b]; });
  std::vector<Result> res(sel.size());
  std::mutex mx;
  auto t0 = std::chrono::steady_clock::now();
  perf::parallel_for(order.size(), jobs, [&](size_t k) {
    size_t i = order[k];
    auto s0 = std::chrono::steady_clock::now();
    run_trace(cx, sel[i], res[i]);
    res[i].sec = std::chrono::duration<double>(
                     std::chrono::steady_clock::now() - s0).count();
    std::lock_guard<std::mutex> g(mx);
    Result& r = res[i];
    if (r.ok)
      std::printf("  done %s/%s  far %llu+%llu stubs %llu  %.1f s\n",
                  r.group.c_str(), r.trace.c_str(),
                  (unsigned long long)r.far_cond_sites,
                  (unsigned long long)r.far_jal_sites,
                  (unsigned long long)r.stubs, r.sec);
    else
      std::printf("  FAIL %s/%s: %s\n", r.group.c_str(), r.trace.c_str(),
                  r.err.c_str());
    std::fflush(stdout);
  });
  double wall = std::chrono::duration<double>(
                    std::chrono::steady_clock::now() - t0).count();

  // The table, and with the whole set, the CSVs.
  const char* hdr =
      "group,trace,far_cond_sites,far_cond_dyn,far_jal_sites,far_jal_dyn,"
      "stubs,stubs_jal,stubs_auipc,stubs_long,stubs_jal4,shared_sites,"
      "two_hop,unplaced,multi_target_pcs,reclass_dyn,conflict_pcs,"
      "cond_target_pc4,orig_records,added_records,new_records,"
      "patched_targets,pages,stub_only_pages,NumBr,50PercInstr,"
      "50PercNumBr";
  bool whole = only.empty() && !cx.analyze;
  FILE* fv = nullptr;
  FILE* fc = nullptr;
  if (whole) {
    fv = std::fopen((cx.repo + "/perf/cbp2025_rv_veneers.csv").c_str(), "w");
    fc = std::fopen((cx.repo + "/perf/cbp2025_rv_counts.csv").c_str(), "w");
    if (!fv || !fc) die("cannot write the perf/ CSVs");
    std::fprintf(fv, "%s\n", hdr);
    std::fprintf(fc, "Workload,Run,Instr,NumBr,50PercInstr,50PercNumBr\n");
  }
  std::printf("%s\n", hdr);
  Result tot;
  int nfail = 0;
  for (auto& r : res) {
    if (!r.ok) { nfail++; continue; }
    std::string line = perf::fmt(
        "%s,%s,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,"
        "%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu",
        r.group.c_str(), r.trace.c_str(),
        (unsigned long long)r.far_cond_sites,
        (unsigned long long)r.far_cond_dyn,
        (unsigned long long)r.far_jal_sites, (unsigned long long)r.far_jal_dyn,
        (unsigned long long)r.stubs, (unsigned long long)r.by_form[F_JAL],
        (unsigned long long)r.by_form[F_AUIPC],
        (unsigned long long)r.by_form[F_LONG],
        (unsigned long long)r.by_form[F_JAL4],
        (unsigned long long)r.shared_sites, (unsigned long long)r.two_hop,
        (unsigned long long)r.unplaced, (unsigned long long)r.multi_pcs,
        (unsigned long long)r.reclass_dyn, (unsigned long long)r.conflict_pcs,
        (unsigned long long)r.cond_t_pc4,
        (unsigned long long)r.orig_records, (unsigned long long)r.added,
        (unsigned long long)r.new_records,
        (unsigned long long)r.patched, (unsigned long long)r.pages,
        (unsigned long long)r.stub_only_pages,
        (unsigned long long)r.c.numbr, (unsigned long long)r.c.half_instr,
        (unsigned long long)r.c.half_numbr);
    std::printf("%s\n", line.c_str());
    if (fv) std::fprintf(fv, "%s\n", line.c_str());
    if (fc)
      std::fprintf(fc, "%s,%s,%llu,%llu,%llu,%llu\n", r.group.c_str(),
                   r.trace.c_str(), (unsigned long long)r.c.instr,
                   (unsigned long long)r.c.numbr,
                   (unsigned long long)r.c.half_instr,
                   (unsigned long long)r.c.half_numbr);
    tot.far_cond_sites += r.far_cond_sites;
    tot.far_cond_dyn += r.far_cond_dyn;
    tot.far_jal_sites += r.far_jal_sites;
    tot.far_jal_dyn += r.far_jal_dyn;
    tot.stubs += r.stubs;
    for (int f = 0; f < 4; f++) tot.by_form[f] += r.by_form[f];
    tot.shared_sites += r.shared_sites;
    tot.two_hop += r.two_hop;
    tot.unplaced += r.unplaced;
    tot.multi_pcs += r.multi_pcs;
    tot.reclass_dyn += r.reclass_dyn;
    tot.conflict_pcs += r.conflict_pcs;
    tot.cond_t_pc4 += r.cond_t_pc4;
    tot.orig_records += r.orig_records;
    tot.added += r.added;
    tot.new_records += r.new_records;
    tot.patched += r.patched;
    tot.pages += r.pages;
    tot.stub_only_pages += r.stub_only_pages;
  }
  if (fv) std::fclose(fv);
  if (fc) std::fclose(fc);
  std::printf(
      "TOTAL far_cond_sites %llu far_cond_dyn %llu far_jal_sites %llu "
      "far_jal_dyn %llu stubs %llu (jal %llu auipc %llu long %llu jal4 "
      "%llu) shared_sites %llu two_hop %llu unplaced %llu multi_pcs %llu "
      "reclass_dyn %llu conflict_pcs %llu cond_target_pc4 %llu "
      "orig_records %llu added %llu new_records %llu patched %llu "
      "pages %llu stub_only_pages %llu\n",
      (unsigned long long)tot.far_cond_sites,
      (unsigned long long)tot.far_cond_dyn,
      (unsigned long long)tot.far_jal_sites,
      (unsigned long long)tot.far_jal_dyn, (unsigned long long)tot.stubs,
      (unsigned long long)tot.by_form[0], (unsigned long long)tot.by_form[1],
      (unsigned long long)tot.by_form[2], (unsigned long long)tot.by_form[3],
      (unsigned long long)tot.shared_sites, (unsigned long long)tot.two_hop,
      (unsigned long long)tot.unplaced, (unsigned long long)tot.multi_pcs,
      (unsigned long long)tot.reclass_dyn,
      (unsigned long long)tot.conflict_pcs,
      (unsigned long long)tot.cond_t_pc4,
      (unsigned long long)tot.orig_records, (unsigned long long)tot.added,
      (unsigned long long)tot.new_records, (unsigned long long)tot.patched,
      (unsigned long long)tot.pages,
      (unsigned long long)tot.stub_only_pages);
  std::printf("veneer: %zu traces, %d failed, %.1f s\n", res.size(), nfail,
              wall);
  return nfail ? 1 : 0;
}
