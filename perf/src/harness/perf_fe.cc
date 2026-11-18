// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// perf_fe.cc -- THE GASKET (PERF-002, perf_decisions.md PF-3 to PF-19):
// the C++ main that drives the Verilated wrapper perf_top (fe_top and
// the walker) with a CBP trace.
//
// It reads the changed trace (checked against perf/cbp2025_rv.sha256,
// and its image and stub list against perf/cbp2025_rv_aux.sha256,
// before either is read, PF-14), builds the code image (supply.h,
// rv_encode.h), loads the pt_gen page tables (PF-17), answers the L1I's
// TileLink link and the walker's memory port from one memory (THE
// MEMORY), and models the backend (THE BACKEND, PF-18). Counts are kept
// in memory and written as one CSV row at the end (PF-6, PF-9).
//
// THE BACKEND, per cycle:
//   TAKE     the ibuf read port takes every presented slot or none
//            (ibuf.sv). The take rate is a credit: each cycle adds a
//            drawn rate, capped at 8; dec_ibuf_rdy is raised when the
//            credit and the window cover the slots presented, and the
//            slots taken are spent. Not raised in a redirect cycle.
//   CHECK    each slot taken on the traced path must be the path's next
//            instruction: its PC (every committed PC equals the trace's
//            next PC, PF-11), its word (the image's), no fault, decode
//            legal. A mismatch is counted and repaired by a redirect.
//   RECORD   THE FETCH RECORD (PERF-003, PF-18): the prediction fetch
//            used, by FTQ index, written at each accepted fetch request
//            (start_pc, taken_val, taken_pos, next_pc and the fetch read
//            port's slots) and updated by each predecode correction as
//            the FTQ updates the entry (FRec, fr_verdict).
//   PREDICT  --mispredict-rule fetch (default): THE FETCH RULE. In its
//            resolve cycle a branch's predicted next PC is read from its
//            entry's record, and it mispredicts when that is not the
//            trace's next PC; the redirect is formed then, with no wait.
//            The fetched stream stays a check: fetch leaving the path
//            after a branch the record says correct is err_stream, and
//            fetch giving the trace's next PC after one it says
//            mispredicted is err_fetch_rule.
//            --mispredict-rule stream: THE STREAM RULE (PERF-002). A
//            branch mispredicts when the slot fetch delivers after it is
//            not the trace's next PC (as fe_tb_backend.svh): the next
//            slot of its bundle, or, when it ended its bundle, the next
//            slot taken, which it then waits for (decide()); the record's
//            verdict decides a waiting branch only when the FTQ is full or
//            the ibuf stays empty (decided_by_slot). The record's verdict
//            is compared with the stream's on every branch, by case
//            (fr_*). pred_src is the record's slot at the branch's
//            position under either rule (PF-6).
//   RESOLVE  every instruction resolves at its take cycle plus a resolve
//            latency, the sum of four drawn backend stages (decode,
//            rename, dispatch, execute, PF-18); a branch's resolution
//            goes to the FTQ
//            then, on up to NUM_RESOLVE_PORTS ports in resolve order,
//            held until ready. A conditional's resolution carries its
//            taken target, decoded from the image's B-type word, whatever
//            its direction (PERF-003). A mispredicted branch redirects in
//            its resolve cycle (RC_MISPREDICT, self clear); what was taken
//            after it is the wrong path and is dropped (PF-8).
//   COMMIT   in order, at the later of resolve plus a drawn resolve to
//            commit delay and the commit before; a branch after its
//            resolution is accepted. The FTQ watermark names the newest
//            entry whose instructions have all committed and whose
//            resolutions were all accepted (ftq_backend_interfaces.md
//            A7).
//   The take cycle is the first cycle the backend holds an instruction,
//   the cycle after the ibuf's handshake; a latency of 0 resolves in
//   it, and a resolve to commit of 0 commits in the resolve cycle.
//
// THE ORACLE (--oracle, PF-11, PERF-003). Each FTQ entry allocated at p1
// is aligned with the trace (OEnt): on the path at trace index k when its
// PC is where the trace goes after its predecessor's predicted block, or
// where a backend redirect sent fetch. For an entry on the path, each
// slot's direction and target at p1, p2 and p3 are set to the trace's
// (perf_top orc_*), and perf_top forces them into bp_cluster's predictor
// outputs; an entry off the path is not forced. Slot presence is the
// predictors' own: a branch with no slot in the record is a miss.
//
// See the usage text (--help) for the run parameters.
// ===================================================================
#include <chrono>
#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fstream>
#include <map>
#include <memory>
#include <random>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <unordered_map>
#include <vector>

#include "Vperf_top.h"
#include "verilated.h"

#include "../cbp_trace.h"
#include "../perf_util.h"
#include "dist.h"
#include "icache.h"
#include "rv_encode.h"
#include "supply.h"

#ifndef PERF_SRC_ROOT
#define PERF_SRC_ROOT "unknown"
#endif
#ifndef PERF_SRC_SHA
#define PERF_SRC_SHA "unknown"
#endif
#ifndef PERF_BUILD_NAME
#define PERF_BUILD_NAME "head"
#endif
#ifndef PERF_SLOTS
#define PERF_SLOTS 2
#endif

namespace {

constexpr int      SLOTS     = 8;          // decode_pkg SLOTS
constexpr int      NPS       = PERF_SLOTS;  // NUM_PRED_SLOTS
constexpr int      NRP       = PERF_SLOTS;  // NUM_RESOLVE_PORTS
constexpr int      VA_BITS   = 59;          // bp_defines_pkg VA_WIDTH
constexpr uint64_t VA_MASK   = (uint64_t(1) << VA_BITS) - 1;
constexpr uint64_t EPOCH     = 1000000;     // CBP epoch
constexpr int      SRC_NONE  = 7;           // PRED_NONE
const char* SRC_NAME[8] = {"ubtb", "loop", "ftb", "tage", "sc", "ittage",
                           "ras", "none"};

// PF-5 values of the predictor enables for a performance run.
struct Cfg {
  int      sc_enable = 1;
  int      ftb_fastpath_en = 1;
  int      tage_enable_aging = 1;
  int      ittage_enable_aging = 1;
  uint32_t tage_aging_interval = 262144;
  uint32_t ittage_aging_interval = 262144;
  bool is_pf5() const {
    return sc_enable == 1 && ftb_fastpath_en == 1 && tage_enable_aging == 1 &&
           ittage_enable_aging == 1 && tage_aging_interval == 262144 &&
           ittage_aging_interval == 262144;
  }
};

struct Opt {
  std::string trace;                 // <group>/<trace>
  std::string set = "rv";
  std::string config;
  std::string out;
  // THE BACKEND STAGES (PF-18, PERF-003): resolve latency is the sum of
  // decode, rename, dispatch and execute.
  std::string dlat = "fixed:0", nlat = "fixed:0", plat = "fixed:0";
  std::string xlat = "fixed:0";
  std::string r2c = "fixed:0", take = "fixed:8";
  uint64_t    window = 0;            // 0: no limit
  uint64_t    seed = 1;
  std::string icache = "real";
  uint64_t    max_instr = 0;
  int         mem_lat = 6;           // TileLink request to beat 0
  int         ptw_lat = 2;           // walker read to response
  uint64_t    log_cycles = 0;
  uint64_t    log_from = 0;
  uint64_t    max_cycles = 0;
  std::string mrule = "fetch";       // --mispredict-rule
  bool        oracle = false;        // --oracle
  Cfg         cfg;
};

void usage() {
  std::printf(
"perf_fe -- the front-end performance harness (PERF-002, PERF-003)\n"
"  --trace <group>/<trace>   the trace (required)\n"
"  --set rv|orig             changed traces (CBP_TRACES_RV, default) or\n"
"                            the training set as it is (CBP_TRACES; only\n"
"                            a trace that needs no change, PF-15)\n"
"  --config <name>           the configuration name (PF-5); default the\n"
"                            build's revision name; <tag>/<name> required\n"
"                            when a --cfg value differs from PF-5\n"
"  --cfg <key>=<value>       sc_enable, ftb_fastpath_en, tage_enable_aging,\n"
"                            ittage_enable_aging, tage_aging_interval,\n"
"                            ittage_aging_interval (PF-5 defaults)\n"
"  --decode-lat <dist>       the backend stages (PF-18): take to resolve\n"
"  --rename-lat <dist>       is their sum, each drawn from its own stream;\n"
"  --dispatch-lat <dist>     each default fixed:0 (--resolve-lat is\n"
"  --execute-lat <dist>      removed)\n"
"  --resolve-commit <dist>   resolve to commit, default fixed:0\n"
"  --take-rate <dist>        instructions taken per cycle, 1..8, default\n"
"                            fixed:8\n"
"  --window <n>              instructions held, 0 no limit (default)\n"
"  --mispredict-rule stream|fetch   how a mispredict is decided: the\n"
"                            fetched stream, or the fetch record in the\n"
"                            branch's resolve cycle (PF-18), default fetch\n"
"  --oracle                  the FTB-slot oracle (PF-11): each slot of an\n"
"                            entry on the path predicts the trace's\n"
"                            direction and target\n"
"  --seed <n>                the run's seed, default 1\n"
"  --icache real|preload|perfect   the I-cache switch (PF-19)\n"
"  --max-instr <n>           stop after n committed instructions\n"
"  --mem-lat <n>             L1I memory latency, default 6\n"
"  --ptw-lat <n>             walker memory latency, default 2\n"
"  --out <csv>               append the result row (header if new)\n"
"  --log <n>                 print the backend's events for n cycles\n"
"  <dist>: fixed:V | uniform:MIN:MAX | geometric:MIN:MAX:MEAN |\n"
"          table:FILE\n");
}

[[noreturn]] void die(const std::string& m, bool readme = false) {
  std::fprintf(stderr, "perf_fe: %s\n", m.c_str());
  if (readme) std::fprintf(stderr, "  (%s)\n", cbp::README_REF);
  std::exit(1);
}

// ---- the memory (THE MEMORY) ------------------------------------------
class Memory {
 public:
  uint8_t* page(uint64_t pa, bool make) {
    uint64_t pg = pa >> 12;
    auto it = pages_.find(pg);
    if (it != pages_.end()) return it->second.get();
    if (!make) return nullptr;
    auto p = std::make_unique<uint8_t[]>(4096);
    std::memset(p.get(), 0, 4096);
    uint8_t* r = p.get();
    pages_[pg] = std::move(p);
    return r;
  }
  uint8_t rd8(uint64_t pa) {
    uint8_t* p = page(pa, false);
    return p ? p[pa & 4095] : 0;
  }
  uint64_t rd64(uint64_t pa) {
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v |= uint64_t(rd8(pa + uint64_t(i))) << (8 * i);
    return v;
  }
  void wr32(uint64_t pa, uint32_t v) {
    uint8_t* p = page(pa, true);
    std::memcpy(p + (pa & 4095), &v, 4);
  }
  void wr64(uint64_t pa, uint64_t v) {
    uint8_t* p = page(pa, true);
    std::memcpy(p + (pa & 4095), &v, 8);
  }
  size_t pages() const { return pages_.size(); }

 private:
  std::unordered_map<uint64_t, std::unique_ptr<uint8_t[]>> pages_;
};

// ---- the backend's instruction -----------------------------------------
struct Ent;
struct Ro {
  uint64_t k;
  perf::Inst in;
  uint32_t ptr;          // FTQ pointer, FTQ_PTR_BITS
  uint8_t  idx, pos;
  bool     is_br, mis = false;
  uint64_t rsv_tgt = 0;          // the resolution's target (RESOLVE)
  bool     fr_mis = false;       // THE VERDICT of the fetch record
  uint8_t  fr_src = SRC_NONE;    // pred_src from the fetch record
  uint64_t fr_seq = 0;           // the record's write count at the take
  uint64_t fr_req_seq = 0;       // and its request count
  bool     slot_dec = false;     // decided without the stream (C1)
  // The next path slot fetch delivered after this branch: seen, and
  // equal to the trace's next PC (the fetched-stream check under fetch).
  bool     nxt_seen = false, nxt_ok = false;
  bool     in_slot = false;      // the record held it in a slot
  bool     orc_forced = false;   // its entry was allocated on the path
  uint8_t  src = SRC_NONE;
  int64_t  take_c, res_c, commit_c;
  bool     res_sent = false, res_done = false;
  Ent*     ent;
};
// One FTQ entry on the committed path.
struct Ent {
  uint32_t ptr;
  uint64_t n_taken = 0, n_commit = 0, n_res = 0;
  bool     closed = false;
};

struct Counts {
  uint64_t cycles = 0, instr = 0, numbr = 0, cond = 0;
  uint64_t mis = 0, mis_cond = 0, mis_dir = 0, mis_ind = 0, mis_ret = 0;
  uint64_t mis_src[8] = {}, pred_src[8] = {};
  uint64_t taken = 0, taken_wp = 0, ftq_full = 0, redirects = 0;
  uint64_t pd_redir = 0, p2_redir = 0, p3_redir = 0;
  uint64_t gets = 0, gets_mask0 = 0, walks = 0, ptw_rd = 0, ptw_cas = 0;
  uint64_t stream_bad = 0, instr_bad = 0, faults = 0;
  uint64_t illegal = 0, idx_bad = 0, opcode_bad = 0, class_conflict = 0;
  uint64_t reopen = 0, traps = 0, unspec_repair = 0, slot_decided = 0;
  uint64_t res_sched = 0, res_wait = 0, commit_dly = 0, commit_wait = 0;
  uint64_t ic_installs = 0, cond_target_bad = 0;
  // The fetch rule (PERF-003): its mispredicts, the agreement with the
  // stream verdict by case, and its checks.
  uint64_t fr_mis = 0, fr_c1_ag = 0, fr_c1_dis = 0, fr_c2_ag = 0;
  uint64_t fr_c2_dis = 0, fr_c3 = 0, fr_ag = 0, fr_dis = 0;
  uint64_t no_record = 0, late_write = 0, fetch_port = 0, fr_moved = 0;
  uint64_t fr_beyond = 0, fr_req = 0, fr_corr = 0, fr_corr_late = 0;
  uint64_t fetch_rule_bad = 0;
  // THE ORACLE (PF-11): entries allocated on the path (forced) and off it
  // (not forced); mispredicts on branches the record held in a slot; the
  // misses (no slot at the branch's position) by class, cond, direct,
  // indirect, return, and the mispredicts among them.
  uint64_t orc_on = 0, orc_off = 0, orc_slot_mis = 0, orc_path_unforced = 0;
  uint64_t orc_realign = 0, orc_slot_trap = 0, br_trap_after = 0;
  uint64_t miss[4] = {}, miss_mis[4] = {};
  std::vector<uint64_t> ep_instr, ep_numbr, ep_mis_cond, ep_mis;
};

// ---- THE RECORD (PERF-003, PF-18) ------------------------------------
// The prediction fetch used, by FTQ index: written at each accepted fetch
// request (ftq_ifu_req_val and _rdy, not in a flush cycle, which discards
// the handshake, ftq_ifu.sv 5) from the request and the fetch read port's
// slots, and updated by a predecode correction as the FTQ updates the
// entry (ftq_ifu.sv w_corr_slot, w_corr_succ).
struct FSlot {
  bool     val = false, taken = false;
  uint8_t  pos = 0, type = 0, src = SRC_NONE;
  uint64_t tgt = 0;
};
struct FRec {
  bool     valid = false;
  uint64_t start_pc = 0, next_pc = 0;
  bool     taken_val = false;
  uint8_t  taken_pos = 0;
  FSlot    s[NPS];
  uint64_t seq = 0;           // writes: requests and corrections
  uint64_t req_seq = 0;       // requests
};

// THE VERDICT: the next PC the record predicts for a branch at position
// pos and address pc of its entry: next_pc when it is the taken position;
// pc + 4 below it, or with none taken unless the branch is the block's
// last instruction, which predicts next_pc. pred_src is the slot's at
// pos, PRED_NONE when no slot is at pos. beyond: the position is after
// the taken one, which fetch does not deliver.
struct FVerdict {
  uint64_t pnext;
  uint8_t  src;
  bool     beyond;
  bool     in_slot;       // a slot of the record is at pos
};
FVerdict fr_verdict(const FRec& e, uint8_t pos, uint64_t pc) {
  FVerdict v{(pc + 4) & VA_MASK, SRC_NONE, false, false};
  for (int s = 0; s < NPS; s++)
    if (e.s[s].val && e.s[s].pos == pos) {
      v.src = e.s[s].src;
      v.in_slot = true;
      break;
    }
  if (e.taken_val && pos == e.taken_pos) {
    v.pnext = e.next_pc;
  } else if (e.taken_val && pos > e.taken_pos) {
    v.pnext = e.next_pc;
    v.beyond = true;
  } else if (!e.taken_val && ((pc + 4) & VA_MASK) >= e.next_pc) {
    v.pnext = e.next_pc;                       // the block's last
    v.beyond = ((pc + 4) & VA_MASK) > e.next_pc;
  }
  return v;
}

// The 50Perc rule (bp.cc), as cbp::Counts: the trailing epochs whose
// records first exceed half.
void half(const Counts& c, uint64_t& hi, uint64_t& hb, uint64_t& hmc,
          uint64_t& hm) {
  hi = hb = hmc = hm = 0;
  uint64_t n_ep = (c.instr + EPOCH - 1) / EPOCH;
  for (uint64_t e = n_ep; e-- > 0;) {
    hi += c.ep_instr[e];
    hb += c.ep_numbr[e];
    hmc += c.ep_mis_cond[e];
    hm += c.ep_mis[e];
    if (hi > c.instr / 2) break;
  }
}

bool file_exists(const std::string& p) {
  struct stat st;
  return stat(p.c_str(), &st) == 0;
}

// The digest recorded for rel in list, or "".
std::string listed_sha(const std::string& list, const std::string& rel) {
  std::vector<cbp::ShaEntry> v;
  std::string msg;
  if (!cbp::read_sha_list(list, v, msg)) die(msg, true);
  for (auto& e : v)
    if (e.rel == rel) return e.sha;
  return "";
}

void check_file(const std::string& root, const std::string& list,
                const std::string& rel) {
  std::string path = root + "/" + rel;
  if (!file_exists(path))
    die(path + " not found; set CBP_TRACES / CBP_TRACES_RV", true);
  std::string want = listed_sha(list, rel);
  if (want.empty()) die(rel + " is not listed in " + list, true);
  std::string got = cbp::sha256_file(path);
  if (got != want)
    die(path + ": SHA-256 " + got + " does not match " + list + " (" + want +
        ")", true);
}

}  // namespace

int main(int argc, char** argv) {
  Opt o;
  std::string repo = cbp::repo_root(argv[0]);
  // ---- the run parameters ----------------------------------------------
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto val = [&]() -> std::string {
      if (i + 1 >= argc) die("missing value after " + a);
      return argv[++i];
    };
    auto u64 = [&]() { return std::strtoull(val().c_str(), nullptr, 0); };
    if (a == "--help" || a == "-h") { usage(); return 0; }
    else if (a == "--trace") o.trace = val();
    else if (a == "--set") o.set = val();
    else if (a == "--config") o.config = val();
    else if (a == "--out") o.out = val();
    else if (a == "--decode-lat") o.dlat = val();
    else if (a == "--rename-lat") o.nlat = val();
    else if (a == "--dispatch-lat") o.plat = val();
    else if (a == "--execute-lat") o.xlat = val();
    else if (a == "--resolve-lat")
      die("--resolve-lat is removed (PERF-003): resolve latency is the sum "
          "of --decode-lat, --rename-lat, --dispatch-lat and --execute-lat");
    else if (a == "--resolve-commit") o.r2c = val();
    else if (a == "--take-rate") o.take = val();
    else if (a == "--window") o.window = u64();
    else if (a == "--seed") o.seed = u64();
    else if (a == "--icache") o.icache = val();
    else if (a == "--max-instr") o.max_instr = u64();
    else if (a == "--mem-lat") o.mem_lat = int(u64());
    else if (a == "--ptw-lat") o.ptw_lat = int(u64());
    else if (a == "--log") o.log_cycles = u64();
    else if (a == "--log-from") o.log_from = u64();
    else if (a == "--max-cycles") o.max_cycles = u64();
    else if (a == "--mispredict-rule") o.mrule = val();
    else if (a == "--oracle") o.oracle = true;
    else if (a == "--cfg") {
      std::string kv = val();
      size_t eq = kv.find('=');
      if (eq == std::string::npos) die("--cfg wants key=value: " + kv);
      std::string k = kv.substr(0, eq);
      uint64_t v = std::strtoull(kv.c_str() + eq + 1, nullptr, 0);
      if (k == "sc_enable") o.cfg.sc_enable = int(v & 1);
      else if (k == "ftb_fastpath_en") o.cfg.ftb_fastpath_en = int(v & 1);
      else if (k == "tage_enable_aging") o.cfg.tage_enable_aging = int(v & 1);
      else if (k == "ittage_enable_aging")
        o.cfg.ittage_enable_aging = int(v & 1);
      else if (k == "tage_aging_interval")
        o.cfg.tage_aging_interval = uint32_t(v);
      else if (k == "ittage_aging_interval")
        o.cfg.ittage_aging_interval = uint32_t(v);
      else die("unknown --cfg key " + k);
    } else die("unknown argument " + a + " (--help)");
  }
  if (o.trace.empty()) { usage(); die("--trace is required"); }
  if (o.set != "rv" && o.set != "orig") die("--set is rv or orig");
  if (o.icache != "real" && o.icache != "preload" && o.icache != "perfect")
    die("--icache is real, preload or perfect");
  if (o.mrule != "stream" && o.mrule != "fetch")
    die("--mispredict-rule is stream or fetch");
  const bool drive = o.mrule == "fetch";
  if (o.config.empty()) {
    if (!o.cfg.is_pf5())
      die("a --cfg value differs from PF-5: name the configuration "
          "<tag>/<name> with --config (PF-5)");
    o.config = PERF_BUILD_NAME;
  } else if (!o.cfg.is_pf5() && o.config.find('/') == std::string::npos) {
    die("a --cfg value differs from PF-5: the configuration name must be "
        "<tag>/<name> (PF-5)");
  }
  perf::Dist d_dec, d_ren, d_dis, d_exe, d_r2c, d_take;
  std::string derr;
  if (!d_dec.parse(o.dlat, derr) || !d_ren.parse(o.nlat, derr) ||
      !d_dis.parse(o.plat, derr) || !d_exe.parse(o.xlat, derr) ||
      !d_r2c.parse(o.r2c, derr) || !d_take.parse(o.take, derr))
    die(derr);
  if (d_take.hi() > 8 || d_take.lo() < 1)
    die("--take-rate is within 1..8 (PF-18)");
  // One stream per parameter, so that one parameter's draws do not move
  // another's. Execute keeps the stream --resolve-lat had (PERF-002), so
  // that a set moved to --execute-lat gives the row it gave before; the
  // three new stages take streams no other parameter uses.
  const uint64_t STAGE_SEED = uint64_t(1) << 40;
  std::mt19937_64 g_exe(o.seed * 3 + 1), g_r2c(o.seed * 3 + 2),
      g_take(o.seed * 3 + 3), g_dec(o.seed * 3 + 1 + STAGE_SEED),
      g_ren(o.seed * 3 + 1 + 2 * STAGE_SEED),
      g_dis(o.seed * 3 + 1 + 3 * STAGE_SEED);

  // ---- the trace, its checksums, the image (PF-14, PF-17) --------------
  size_t sl = o.trace.find('/');
  if (sl == std::string::npos) die("--trace is <group>/<trace>");
  std::string group = o.trace.substr(0, sl), tname = o.trace.substr(sl + 1);
  std::string rv_root = cbp::traces_rv_root(repo);
  std::string rel = "training_traces/" + group + "/" + tname + ".gz";
  std::string trace_path, list;
  if (o.set == "rv") {
    list = repo + "/perf/cbp2025_rv.sha256";
    check_file(rv_root, list, rel);
    trace_path = rv_root + "/" + rel;
  } else {
    list = repo + "/perf/cbp2025_training.sha256";
    std::string root = cbp::traces_root(repo);
    check_file(root, list, rel);
    trace_path = root + "/" + rel;
  }
  // The image and stub list are the changed trace's; --set orig is for a
  // trace whose changed form is record for record the original.
  std::string aux = repo + "/perf/cbp2025_rv_aux.sha256";
  std::string img_rel = "pages/" + group + "/" + tname + ".img";
  std::string stub_rel = "pages/" + group + "/" + tname + ".stubs";
  check_file(rv_root, aux, img_rel);
  check_file(rv_root, aux, stub_rel);

  auto t_start = std::chrono::steady_clock::now();
  perf::TraceSupply sup;
  std::string err;
  if (!sup.load(trace_path, rv_root + "/" + stub_rel, o.max_instr, err))
    die(err, true);
  // The oracle reads records behind the commit point: an FTQ's worth of
  // blocks (64 entries of up to 8 instructions) and margin.
  sup.set_keep(4096);
  if (o.set == "orig" && sup.stub_count() != 0)
    die(o.trace + " has stubs: --set orig is only for a trace that needs "
        "no change");

  Memory mem;
  uint64_t satp = 0;
  std::vector<std::pair<uint64_t, uint64_t>> vmap;     // va page, pa page
  {
    std::ifstream in(rv_root + "/" + img_rel);
    std::string line;
    while (std::getline(in, line)) {
      if (line.empty() || line[0] == '#') continue;
      std::stringstream ss(line);
      std::string kw, a, b;
      ss >> kw >> a;
      if (kw == "satp") satp = std::stoull(a, nullptr, 16);
      else if (kw == "map") {
        ss >> b;
        vmap.emplace_back(std::stoull(a, nullptr, 16),
                          std::stoull(b, nullptr, 16));
      } else if (kw == "word") {
        ss >> b;
        mem.wr64(std::stoull(a, nullptr, 16), std::stoull(b, nullptr, 16));
      }
    }
    if (satp == 0 || vmap.empty()) die("bad image " + img_rel, true);
  }
  std::unordered_map<uint64_t, uint64_t> v2p;            // page numbers
  for (auto& m : vmap) {
    v2p[m.first >> 12] = m.second >> 12;
    for (uint64_t off = 0; off < 4096; off += 4)
      mem.wr32(m.second + off, sup.word(m.first + off));
  }
  // Every code word must have a page.
  for (auto& kv : sup.image())
    if (!v2p.count(kv.first >> 12))
      die(perf::fmt("pc %016" PRIx64 " is on no mapped page", kv.first), true);

  // ---- the model ---------------------------------------------------------
  std::vector<std::string> vargs = {"perf_fe", "+TAGE_FAST_INIT=1",
                                    "+ITTAGE_FAST_INIT=1", "+SC_FAST_INIT=1"};
  std::vector<const char*> vargv;
  for (auto& s : vargs) vargv.push_back(s.c_str());
  auto ctx = std::make_unique<VerilatedContext>();
  ctx->commandArgs(int(vargv.size()), vargv.data());
  auto top = std::make_unique<Vperf_top>(ctx.get());
  perf::ICache ic(top.get(), o.icache);
  std::string ic_err;
  if (!ic.ok(ic_err)) die(ic_err);

  Counts c;
  std::vector<FRec> frec(64);          // THE RECORD, by FTQ index

  // ---- THE ORACLE (PF-11): the predicted path, followed in the trace ----
  // Each entry allocated at p1 is aligned with the trace: on the path, at
  // trace index k (its first instruction), when its PC is where the trace
  // goes after its predecessor's block (the entry before it), or where a
  // backend redirect sent fetch; otherwise off the path. The slots of an
  // entry on the path are forced, at p1, p2 and p3, to the trace's
  // direction and target of the instruction at their position.
  struct OEnt {
    bool valid = false, on = false;
    uint64_t k = 0, pc = 0;
    bool fixed = false;           // aligned by a redirect, not a predecessor
  };
  std::vector<OEnt> oent(64);
  struct { bool v = false; uint64_t pc = 0, k = 0; } opend;  // a redirect
  // The trace's instruction at position pos of a block on the path that
  // starts at trace index k and address pc: false when the path leaves
  // the block before it (a taken branch, a trap) or the position is not
  // an instruction start the trace reaches. isbr: it is a branch; dir and
  // tgt its direction and taken target (a conditional's the image's
  // encoded target, as its resolution).
  auto o_slot = [&](uint64_t k, uint64_t pc, uint8_t pos, bool& isbr,
                    bool& dir, uint64_t& tgt, uint8_t& cls) -> bool {
    if (pos & 1) return false;
    uint32_t o = pos / 2;
    perf::Inst x;
    // Each instruction up to pos at its sequential PC: the path stays in
    // the block (a branch taken to its own pc + 4 included).
    for (uint32_t j = 0; j <= o; j++) {
      if (!sup.at(k + j, x)) return false;
      if ((x.pc & VA_MASK) != ((pc + 4 * uint64_t(j)) & VA_MASK)) return false;
    }
    cls = x.cls;
    isbr = cbp::is_branch(x.cls);
    dir = isbr && x.taken;
    tgt = x.target;
    if (x.cls == cbp::C_COND) {
      uint32_t w = sup.word(x.pc);
      if (rv::is_b_type(w)) tgt = rv::br_target(x.pc, w);
    }
    tgt &= VA_MASK;
    return true;
  };
  // The trace index of the block at pc after the block e on the path, or
  // false when pc is not where the trace goes from e. The block ends
  // where its FTQ entry predicts (top->os_pr_*, read in the cycle the
  // block at pc is at p1, when the entry holds the prediction that gave
  // pc): at its lowest taken slot, else at its fall-through. The trace
  // must run sequentially to that end with no taken branch before it,
  // take the slot's branch when the block ends at one, and continue at
  // pc. A PC the block reaches before its end is not its successor, even
  // when the trace passes it (a loop inside the block).
  int osucc_why = 0;            // why o_succ last refused (the --log)
  auto o_succ = [&](int g, uint8_t pidx, const OEnt& e, uint64_t pc,
                    uint64_t& k) -> bool {
    osucc_why = 1;
    bool tk = false;
    uint8_t tpos = 0;
    uint64_t pft = 0;
    const FRec& fr = frec[pidx];
    if (fr.valid && (fr.start_pc & VA_MASK) == (e.pc & VA_MASK)) {
      // Fetched: the record is the prediction fetch used. The entry's
      // slots may since have been rewritten by its resolutions.
      tk = fr.taken_val;
      tpos = fr.taken_pos;
      pft = fr.next_pc & VA_MASK;
    } else {
      // Not yet fetched: the entry holds the prediction (no resolution
      // names an entry before its instructions are delivered).
      if ((uint64_t(top->os_pr_pc[g]) & VA_MASK) != (e.pc & VA_MASK))
        return false;
      for (int s = NPS - 1; s >= 0; s--)
        if (((top->os_pr_s_val[g] >> s) & 1) &&
            ((top->os_pr_s_taken[g] >> s) & 1)) {
          tk = true;
          tpos = top->os_pr_s_pos[g][s];
        }
      pft = uint64_t(top->os_pr_pft[g]) & VA_MASK;
    }
    uint64_t n;                  // instructions in the block, end included
    if (tk) {
      if (tpos & 1) { osucc_why = 2; return false; }
      n = uint64_t(tpos / 2) + 1;
    } else {
      uint64_t st = e.pc & VA_MASK;
      if (pft <= st || ((pft - st) & 3) || pft - st > 64) {
        osucc_why = 3;
        return false;
      }
      n = (pft - st) / 4;
    }
    perf::Inst x, nx;
    for (uint64_t o = 0; o < n; o++) {
      if (!sup.at(e.k + o, x) || !sup.at(e.k + o + 1, nx)) {
        osucc_why = 4;
        return false;
      }
      if ((x.pc & VA_MASK) != ((e.pc + 4 * o) & VA_MASK)) {
        osucc_why = 5;
        return false;
      }
      // The path leaves the block early when the trace does not go on to
      // the next instruction (a taken branch elsewhere, a trap); a branch
      // taken to its own pc + 4 leaves it sequential and does not.
      bool taken = cbp::is_branch(x.cls) && x.taken;
      bool seq = (nx.pc & VA_MASK) == ((x.pc + 4) & VA_MASK);
      if (o + 1 < n && !seq) { osucc_why = 6; return false; }
      if (o + 1 == n && tk && !taken) { osucc_why = 7; return false; }
    }
    if ((nx.pc & VA_MASK) != (pc & VA_MASK)) { osucc_why = 8; return false; }
    k = e.k + n;
    osucc_why = 0;
    return true;
  };
  int64_t cyc = 0;
  int n_frdis_log = 0;                 // fetch-rule disagreements printed
  // Backend state.
  std::deque<Ro>  rob;
  std::deque<Ent> ents;
  std::deque<Ro*> rq;                 // resolutions to present, in order
  std::multimap<int64_t, Ro*> res_at; // branches by resolve cycle
  uint64_t tp = 0;                    // the path's next instruction
  uint64_t n_wp = 0;                  // wrong-path instructions held
  bool     wrong = false;
  bool     have_last = false;         // the last path instruction taken
  Ro*      last = nullptr;            // valid until it commits
  struct LastCopy {                   // the same, kept past its commit
    bool v = false; uint8_t idx = 0, pos = 0; uint32_t ptr = 0;
    uint64_t pc = 0;
  } lc;
  uint64_t expect_next = 0;           // the PC fetch should give next
  bool     pred_mis_last = false;     // the last branch was predicted bad
  int64_t  credit = 0;
  int64_t  last_commit_c = 0;
  bool     cur_val = false, after_redir = false;
  uint32_t cur_ptr = 0, redir_next = 0;
  bool     wm_val = false;
  uint32_t wm = 0;
  // The one pending redirect.
  struct Redir {
    bool v = false; int64_t at = 0; uint8_t idx = 0, pos = 0;
    uint64_t pc = 0; bool self = false; uint8_t cause = 0; bool taken = false;
    uint64_t next_k = 0; uint32_t ptr = 0; bool unspec = false;
  } rd;
  bool     redir_now = false;
  bool     started = false;           // the path's first redirect fired
  int64_t  idle = 0;                  // cycles the ibuf presented nothing
  const int64_t EAGER_IDLE = 32;
  // The memory links.
  struct Get { uint8_t src; uint64_t addr; int64_t due; };
  std::deque<Get> gets;
  bool d_busy = false;
  int  d_beat = 0;
  Get  d_cur{};
  bool pw_pend = false;
  int64_t pw_due = 0;
  bool pw_op = false;
  uint64_t pw_pa = 0, pw_cmp = 0, pw_swap = 0;
  int64_t last_take_c = 0;
  std::string status = "ok";

  auto logf = [&](const char* f, auto... args) {
    if (uint64_t(cyc) >= o.log_from &&
        uint64_t(cyc) < o.log_from + o.log_cycles) {
      std::printf("%8" PRId64 " ", cyc);
      std::printf(f, args...);
      std::printf("\n");
    }
  };

  // ---- reset, CSRs at once with fast init (PF-5) ----
  top->rstn = 0;
  top->csr_load = 1;
  top->csr_satp = satp;
  top->cfg_sc_enable = uint8_t(o.cfg.sc_enable);
  top->cfg_ftb_fastpath_en = uint8_t(o.cfg.ftb_fastpath_en);
  top->cfg_tage_enable_aging = uint8_t(o.cfg.tage_enable_aging);
  top->cfg_ittage_enable_aging = uint8_t(o.cfg.ittage_enable_aging);
  top->cfg_tage_aging_interval = o.cfg.tage_aging_interval;
  top->cfg_ittage_aging_interval = o.cfg.ittage_aging_interval;
  top->l1i_a_ready = 0;
  top->ptw_req_rdy = 0;
  for (int i = 0; i < 10; i++) {
    top->clk = 0; top->eval();
    top->clk = 1; top->eval();
    if (i == 2) top->csr_load = 0;
  }
  top->rstn = 1;
  // The path starts at its first PC: an RC_UNSPEC redirect, which names
  // no entry (ftq_backend_interfaces.md 5.1, reset).
  perf::Inst first;
  if (!sup.at(0, first)) die("the trace is empty");
  // It is issued at START_CYC, after the L1I's post-reset invalidate walk
  // (one set per cycle, l1i_meta_array), so that a preloaded line is not
  // invalidated; the counts start there.
  const int64_t START_CYC = 300;
  rd.v = true; rd.at = START_CYC; rd.pc = first.pc; rd.cause = 3;
  rd.unspec = true; rd.next_k = 0;
  last_take_c = START_CYC;

  // THE STREAM RULE (--mispredict-rule stream). A branch that ended its
  // bundle waits for the next slot fetch delivers, which decides it; it
  // then resolves at the later of its drawn resolve cycle and that slot's
  // take cycle, and a mispredict redirects there.
  Ro* pend = nullptr;
  auto decide = [&](Ro* b, bool mis, int64_t when) {
    b->mis = mis;
    if (when > b->res_c) {
      c.res_wait += uint64_t(when - b->res_c);
      b->res_c = when;
    }
    if (b->commit_c < b->res_c) b->commit_c = b->res_c;
    res_at.emplace(b->res_c, b);
    if (mis) {
      wrong = true;
      rd.v = true; rd.at = b->res_c; rd.idx = b->idx; rd.pos = b->pos;
      rd.pc = expect_next; rd.self = false; rd.cause = 0;
      rd.taken = b->in.taken; rd.next_k = b->k + 1; rd.ptr = b->ptr;
      rd.unspec = false;
    }
    logf("DECIDE k %" PRIu64 " mis %d res %" PRId64, b->k, int(mis),
         b->res_c);
  };

  auto t_sim = std::chrono::steady_clock::now();
  const uint64_t path_len = sup.length();
  uint64_t committed = 0;

  while (committed < path_len) {
    // =============== (A) this cycle's inputs ===============
    // THE PREDECODE CORRECTION of this cycle updates the record first.
    // The IFU presents its writeback the cycle after the F3 transfer
    // (ifu_wb.sv), and the ibuf may hand the block to the backend in the
    // transfer cycle itself, so the correction can land in a branch's
    // resolve cycle (a latency of 0). pd_wr_val and the corrected slots
    // are formed from registered state only (ifu_wb, ftq_status, the
    // entry), so they are read here, before this cycle's inputs, and the
    // verdict of a branch resolving in this cycle sees them.
    if (top->pc_val) {
      FRec& e = frec[top->pc_idx];
      if (!e.valid) c.no_record++;
      e.taken_val = false;
      e.taken_pos = 0;
      for (int s = NPS - 1; s >= 0; s--) {
        e.s[s].val = (top->pc_s_val >> s) & 1;
        e.s[s].taken = (top->pc_s_taken >> s) & 1;
        e.s[s].pos = top->pc_s_pos[s];
        e.s[s].type = top->pc_s_type[s];
        e.s[s].src = top->pc_s_src[s];
        e.s[s].tgt = top->pc_s_tgt[s];
        if (e.s[s].val && e.s[s].taken) {
          e.taken_val = true;
          e.taken_pos = e.s[s].pos;
        }
      }
      e.next_pc = top->pc_succ;
      e.seq++;
      c.fr_corr++;
      logf("FCORR idx %d next %" PRIx64 " tk %d/%d", int(top->pc_idx),
           e.next_pc, int(e.taken_val), int(e.taken_pos));
    }
    // ---- THE ORACLE: this cycle's forced values (PF-11) ----
    // The BPU stage registers and the slots the stage logic reads are
    // state, so they are read here and the values set before the edge.
    {
      uint8_t p1_den = 0, p1_dir = 0, p1_ten = 0, p1_ret = 0;
      uint8_t p2_den = 0, p2_dir = 0, p2_ten = 0, p3_den = 0, p3_dir = 0;
      bool p2_jten = false;
      uint64_t p2_jtgt = 0;
      top->orc_on = o.oracle;
      // The p3 and p2 blocks are aligned again, oldest first, from their
      // predecessors' entries as they now stand: a p2 or p3 slot write can
      // move where the predecessor's block ends without changing its
      // successor, and so without a redirect (BP-150).
      auto realign = [&](int g, uint8_t idx, uint64_t pc) {
        OEnt& e = oent[idx];
        if (!e.valid || e.fixed ||
            (e.pc & VA_MASK) != (pc & VA_MASK))
          return;
        const OEnt& pr = oent[(idx - 1) & 63];
        uint64_t k = 0;
        bool on = pr.valid && pr.on &&
                  o_succ(g, uint8_t((idx - 1) & 63), pr, e.pc, k);
        if (on != e.on || (on && k != e.k)) {
          c.orc_realign++;
          logf("OREALIGN p%d idx %d pc %" PRIx64 " on %d k %" PRIu64
               " was %d %" PRIu64, g + 1, int(idx), e.pc, int(on), k,
               int(e.on), e.k);
        }
        e.on = on;
        e.k = on ? k : 0;
      };
      if (o.oracle && top->os_p3_val)
        realign(2, top->os_p3_idx, top->os_p3_pc);
      if (o.oracle && top->os_p2_val)
        realign(1, top->os_p2_idx, top->os_p2_pc);
      if (o.oracle && top->os_p1_val) {
        // Align the p1 block, the entry allocated this cycle.
        OEnt e;
        e.valid = true;
        e.pc = top->os_p1_pc;
        uint64_t k = 0;
        if (opend.v && (e.pc & VA_MASK) == (opend.pc & VA_MASK)) {
          e.on = true;
          e.fixed = true;                 // where the redirect sent fetch
          e.k = opend.k;
        } else {
          const OEnt& pr = oent[(top->os_p1_idx - 1) & 63];
          if (pr.valid && pr.on &&
              o_succ(0, uint8_t((top->os_p1_idx - 1) & 63), pr, e.pc, k)) {
            e.on = true;
            e.k = k;
          }
        }
        oent[top->os_p1_idx] = e;
        {
          const OEnt& pr = oent[(top->os_p1_idx - 1) & 63];
          logf("OALIGN idx %d pc %" PRIx64 " on %d k %" PRIu64 " pred %d/%d "
               "pc %" PRIx64 " k %" PRIu64 " pend %d %" PRIx64 " why %d",
               int(top->os_p1_idx), e.pc, int(e.on), e.k, int(pr.valid),
               int(pr.on), pr.pc, pr.k, int(opend.v), opend.pc, osucc_why);
        }
        for (int s = 0; s < NPS && e.on; s++) {
          if (!((top->os_p1_s_val >> s) & 1)) continue;
          bool isbr = false, dir = false;
          uint64_t tgt = 0;
          uint8_t cls = 0;
          if (!o_slot(e.k, e.pc, top->os_p1_s_pos[s], isbr, dir, tgt, cls))
            continue;
          p1_den |= uint8_t(1u << s);
          if (dir) {
            p1_dir |= uint8_t(1u << s);
            p1_ten |= uint8_t(1u << s);
            top->orc_p1_tgt[s] = tgt;
          }
          uint8_t ty = top->os_p1_s_type[s];
          if (ty == rv::BT_RETURN || ty == rv::BT_RETURN_CALL) {
            p1_ret |= uint8_t(1u << s);
            top->orc_p1_tgt[s] = tgt;
          }
        }
      }
      if (o.oracle && top->os_p2_val) {
        const OEnt& e = oent[top->os_p2_idx];
        if (e.valid && e.on && (e.pc & VA_MASK) == (top->os_p2_pc & VA_MASK))
          for (int s = 0; s < NPS; s++) {
            if (!((top->os_p2_s_val >> s) & 1)) continue;
            bool isbr = false, dir = false;
            uint64_t tgt = 0;
            uint8_t cls = 0;
            if (!o_slot(e.k, e.pc, top->os_p2_s_pos[s], isbr, dir, tgt, cls))
              continue;
            logf("OFORCE p2 idx %d s %d pos %d type %d isbr %d dir %d tgt %"
                 PRIx64, int(top->os_p2_idx), s, int(top->os_p2_s_pos[s]),
                 int(top->os_p2_s_type[s]), int(isbr), int(dir), tgt);
            if (top->os_p2_s_type[s] == rv::BT_COND) {
              p2_den |= uint8_t(1u << s);
              if (dir) p2_dir |= uint8_t(1u << s);
            }
            if (dir) {
              p2_ten |= uint8_t(1u << s);
              top->orc_p2_tgt[s] = tgt;
              if (top->os_p2_s_type[s] != rv::BT_COND) {
                p2_jten = true;
                p2_jtgt = tgt;
              }
            }
          }
      }
      if (o.oracle && top->os_p3_val) {
        const OEnt& e = oent[top->os_p3_idx];
        if (e.valid && e.on && (e.pc & VA_MASK) == (top->os_p3_pc & VA_MASK))
          for (int s = 0; s < NPS; s++) {
            if (!((top->os_p3_s_val >> s) & 1)) continue;
            if (top->os_p3_s_type[s] != rv::BT_COND) continue;
            bool isbr = false, dir = false;
            uint64_t tgt = 0;
            uint8_t cls = 0;
            if (!o_slot(e.k, e.pc, top->os_p3_s_pos[s], isbr, dir, tgt, cls))
              continue;
            p3_den |= uint8_t(1u << s);
            if (dir) p3_dir |= uint8_t(1u << s);
          }
      }
      top->orc_p1_den = p1_den; top->orc_p1_dir = p1_dir;
      top->orc_p1_ten = p1_ten; top->orc_p1_ret = p1_ret;
      top->orc_p2_den = p2_den; top->orc_p2_dir = p2_dir;
      top->orc_p2_ten = p2_ten;
      top->orc_p2_jten = p2_jten; top->orc_p2_jtgt = p2_jtgt;
      top->orc_p3_den = p3_den; top->orc_p3_dir = p3_dir;
    }
    // TileLink channel D, one beat per cycle once due.
    if (!d_busy && !gets.empty() && gets.front().due <= cyc) {
      d_cur = gets.front();
      gets.pop_front();
      d_busy = true;
      d_beat = 0;
    }
    top->l1i_a_ready = 1;
    top->l1i_d_valid = d_busy;
    top->l1i_d_opcode = 1;                 // AccessAckData
    top->l1i_d_size = 6;                   // 64 bytes
    top->l1i_d_denied = 0;
    top->l1i_d_source = d_cur.src;
    if (d_busy) {
      uint64_t base = d_cur.addr + uint64_t(32 * d_beat);
      for (int w = 0; w < 8; w++) {
        uint32_t v = 0;
        for (int b = 0; b < 4; b++)
          v |= uint32_t(mem.rd8(base + uint64_t(4 * w + b))) << (8 * b);
        top->l1i_d_data[w] = v;
      }
    }
    // The walker's memory port: one access at a time (WM-3).
    top->ptw_req_rdy = !pw_pend;
    top->ptw_rsp_val = 0;
    top->ptw_rsp_err = 0;
    if (pw_pend && pw_due <= cyc) {
      uint64_t old = mem.rd64(pw_pa);
      top->ptw_rsp_val = 1;
      top->ptw_rsp_data = old;
      if (pw_op && old == pw_cmp) mem.wr64(pw_pa, pw_swap);
      pw_pend = false;
    }

    // THE STREAM RULE: a pending branch with nothing coming. When the FTQ
    // is full or the ibuf has been empty for EAGER_IDLE cycles, the fetch
    // record's verdict decides it (decided_by_slot; before PERF-003 the
    // FTQ slot read at the take did), so that no commit waits on a fetch
    // that waits on commit.
    if (pend != nullptr && top->pd_valid == 0 &&
        (top->ftq_full || idle >= EAGER_IDLE)) {
      c.slot_decided++;
      pend->slot_dec = true;
      FVerdict v = fr_verdict(frec[pend->idx], pend->pos, pend->in.pc);
      decide(pend, v.pnext != (expect_next & VA_MASK), cyc);
      pend = nullptr;
    }
    // Branches reaching their resolve cycle join the resolution queue,
    // before this cycle's redirect is formed, so that under the fetch
    // rule a mispredict redirects in its resolve cycle.
    while (!res_at.empty() && res_at.begin()->first <= cyc) {
      // THE VERDICT, in the resolve cycle, from the record. A request for
      // the index after the take means the record is not the one fetch
      // used for this branch (err_record_moved); a predecode correction
      // after the take is counted (fr_corr_after_take).
      Ro* b = res_at.begin()->second;
      res_at.erase(res_at.begin());
      const FRec& fe = frec[b->idx];
      if (fe.req_seq != b->fr_req_seq) c.fr_moved++;
      else if (fe.seq != b->fr_seq) c.fr_corr_late++;
      perf::Inst nx;
      bool has_next = sup.at(b->k + 1, nx);
      uint64_t tnext = has_next ? nx.pc : b->in.pc + 4;
      FVerdict v = fr_verdict(fe, b->pos, b->in.pc);
      // The path's last branch has no next instruction to compare with
      // (C3): it is not judged, as the stream rule does not judge it.
      b->fr_mis = has_next && v.pnext != (tnext & VA_MASK);
      b->fr_src = v.src;
      // pred_src comes from the record under either rule (PF-6).
      b->src = v.src;
      b->in_slot = v.in_slot;
      if (v.beyond) c.fr_beyond++;
      if (drive) {
        // THE FETCH RULE DRIVES: the verdict decides, here, with no wait.
        b->mis = b->fr_mis;
        if (b->mis && b->nxt_seen && b->nxt_ok) {
          // Fetch delivered the trace's next PC after a branch the record
          // says mispredicted (err_fetch_rule). The path went on; no
          // redirect is formed.
          c.fetch_rule_bad++;
        } else if (b->mis) {
          wrong = true;
          rd.v = true; rd.at = cyc; rd.idx = b->idx; rd.pos = b->pos;
          rd.pc = tnext; rd.self = false; rd.cause = 0;
          rd.taken = b->in.taken; rd.next_k = b->k + 1; rd.ptr = b->ptr;
          rd.unspec = false;
        } else if (b->nxt_seen && !b->nxt_ok) {
          // Fetch left the path after a branch the record says correct
          // (err_stream): repaired by RC_REPLAY naming the branch.
          if (sup.conflict(b->in.pc) || sup.conflict(tnext))
            c.class_conflict++;
          else
            c.stream_bad++;
          rd.v = true; rd.at = cyc; rd.idx = b->idx; rd.pos = b->pos;
          rd.pc = tnext; rd.self = false; rd.cause = 2; rd.taken = false;
          rd.next_k = b->k + 1; rd.ptr = b->ptr; rd.unspec = false;
        }
        logf("VERDICT k %" PRIu64 " mis %d nxt %d/%d", b->k, int(b->mis),
             int(b->nxt_seen), int(b->nxt_ok));
      }
      b->res_sent = true;
      rq.push_back(b);
    }
    // The redirect, in its cycle.
    redir_now = rd.v && rd.at <= cyc;
    top->redir_val = redir_now;
    if (redir_now) {
      top->redir_idx = rd.idx;
      top->redir_pos = rd.pos;
      top->redir_pc = rd.pc & VA_MASK;
      top->redir_self = rd.self;
      top->redir_cause = rd.cause;
      top->redir_taken = rd.taken;
      logf("REDIRECT cause %d idx %d pos %d pc %" PRIx64, rd.cause, rd.idx,
           rd.pos, rd.pc);
    }
    uint8_t rv = 0;
    for (int p = 0; p < NRP; p++) {
      if (size_t(p) >= rq.size()) break;
      Ro* r = rq[size_t(p)];
      rv |= uint8_t(1u << p);
      top->rsv_idx[p] = r->idx;
      top->rsv_pos[p] = r->pos;
      top->rsv_target[p] = r->rsv_tgt & VA_MASK;
      top->rsv_type[p] = rv::br_type_of(r->in.cls);
      if (r->in.taken) top->rsv_taken |= uint8_t(1u << p);
      else top->rsv_taken &= uint8_t(~(1u << p));
      if (r->mis) top->rsv_mis |= uint8_t(1u << p);
      else top->rsv_mis &= uint8_t(~(1u << p));
    }
    top->rsv_val = rv;
    // An entry ends when a later entry's instruction arrives, at a
    // redirect, or, as fe_tb_backend.svh's eager mode, when the ibuf
    // presents nothing: the IFU writes a block's slots to the ibuf
    // together, so every slot of the last entry has then been taken.
    // The eager close waits until the FTQ is full or the ibuf has been
    // empty for EAGER_IDLE cycles, so that an entry stays nameable by a
    // repair redirect while fetch may still show it was left early.
    idle = (top->pd_valid == 0) ? idle + 1 : 0;
    if (started && !wrong && !rd.v && top->pd_valid == 0 && !ents.empty() &&
        (top->ftq_full || idle >= EAGER_IDLE))
      ents.back().closed = true;
    // The watermark.
    while (!ents.empty() && ents.front().closed &&
           ents.front().n_commit == ents.front().n_taken &&
           ents.front().n_res == 0) {
      wm = ents.front().ptr;
      wm_val = true;
      ents.pop_front();
    }
    top->commit_val = wm_val;
    top->commit_idx = wm;
    // The take: every presented slot or none.
    int npres = 0;
    for (int i = 0; i < SLOTS; i++)
      if ((top->pd_valid >> i) & 1) npres = i + 1;
    credit = std::min<int64_t>(8, credit + d_take.draw(g_take));
    bool room = o.window == 0 || rob.size() + n_wp + uint64_t(npres) <=
                                     o.window;
    bool rdy = started && !redir_now && npres > 0 && credit >= npres &&
               room && tp < path_len;
    top->dec_ibuf_rdy = rdy;

    top->clk = 0;
    top->eval();
    ic.before_edge(cyc);

    // =============== (B) the handshakes of this cycle ===============
    if (top->l1i_a_valid && top->l1i_a_ready) {
      if (top->l1i_a_opcode != 4) c.opcode_bad++;
      if (top->l1i_a_mask == 0) c.gets_mask0++;   // TD#196: a full line
      c.gets++;
      gets.push_back(Get{top->l1i_a_source, top->l1i_a_address & ~63ull,
                         cyc + o.mem_lat});
    }
    if (d_busy && top->l1i_d_ready) {
      if (++d_beat == 2) d_busy = false;
    }
    if (top->ptw_req_val && top->ptw_req_rdy) {
      pw_pend = true;
      pw_due = cyc + std::max(1, o.ptw_lat);
      pw_op = top->ptw_req_op;
      pw_pa = top->ptw_req_paddr;
      pw_cmp = top->ptw_req_cmp;
      pw_swap = top->ptw_req_swap;
      if (pw_op) c.ptw_cas++;
      else c.ptw_rd++;
    }
    if (cyc >= START_CYC) {
      if (top->obs_walk) c.walks++;
      if (top->obs_pd_redir) c.pd_redir++;
      if (top->obs_p2_redir) c.p2_redir++;
      if (top->obs_p3_redir) c.p3_redir++;
    }
    // ---- THE RECORD (PERF-003), at this edge, before the take ----
    {
      // A p2 or p3 slot write to an entry whose request was accepted in
      // an earlier cycle is late (err_late_write): the fetch used the
      // slots before it. The p3 write of the request's own cycle is the
      // one the fetch read port carries (BP-150).
      if (top->ew_p2_val && frec[top->ew_p2_idx].valid) c.late_write++;
      if (top->ew_p3_val && frec[top->ew_p3_idx].valid) c.late_write++;
      // A new use of the index: its record is gone.
      if (top->ew_alloc_val) frec[top->ew_alloc_idx].valid = false;
      // THE ORACLE: the allocation, forced (on the path) or not.
      if (o.oracle && top->ew_alloc_val) {
        OEnt& e = oent[top->ew_alloc_idx];
        if (!e.valid ||
            (e.pc & VA_MASK) != (uint64_t(top->ew_alloc_pc) & VA_MASK))
          e = OEnt{true, false, 0, top->ew_alloc_pc};
        if (e.on) {
          c.orc_on++;
          if (opend.v && e.k == opend.k) opend.v = false;
        } else {
          c.orc_off++;
        }
      }
      if (top->fr_req_val && top->fr_req_rdy && !top->fr_flush_val) {
        if (top->fr_rd_idx != top->fr_idx) c.fetch_port++;
        // The p2 write is not carried by the fetch read port.
        if (top->ew_p2_val && top->ew_p2_idx == top->fr_idx) c.late_write++;
        FRec& e = frec[top->fr_idx];
        e.valid = true;
        e.start_pc = top->fr_start_pc;
        e.next_pc = top->fr_next_pc;
        e.taken_val = top->fr_taken_val;
        e.taken_pos = top->fr_taken_pos;
        for (int s = 0; s < NPS; s++) {
          e.s[s].val = (top->fr_s_val >> s) & 1;
          e.s[s].taken = (top->fr_s_taken >> s) & 1;
          e.s[s].pos = top->fr_s_pos[s];
          e.s[s].type = top->fr_s_type[s];
          e.s[s].src = top->fr_s_src[s];
          e.s[s].tgt = top->fr_s_tgt[s];
        }
        e.seq++;
        e.req_seq++;
        c.fr_req++;
        logf("FREQ idx %d start %" PRIx64 " next %" PRIx64 " tk %d/%d "
             "s0 %d/%d/%d/%d/%" PRIx64 " s1 %d/%d/%d/%d/%" PRIx64,
             int(top->fr_idx), e.start_pc, e.next_pc, int(e.taken_val),
             int(e.taken_pos), int(e.s[0].val), int(e.s[0].taken),
             int(e.s[0].pos), int(e.s[0].type), e.s[0].tgt,
             int(e.s[NPS - 1].val), int(e.s[NPS - 1].taken),
             int(e.s[NPS - 1].pos), int(e.s[NPS - 1].type),
             e.s[NPS - 1].tgt);
      }
    }
    // Resolutions accepted.
    {
      // Each port by itself: the FTQ may hold one port (a resolution
      // naming an older one's slot, ftq_backend_interfaces.md 4) and take
      // the other.
      std::vector<Ro*> keep;
      for (size_t p = 0; p < rq.size(); p++) {
        Ro* r = rq[p];
        bool acc = p < size_t(NRP) && ((top->rsv_val >> p) & 1) &&
                   ((top->rsv_rdy >> p) & 1);
        if (!acc) { keep.push_back(r); continue; }
        r->res_done = true;
        r->ent->n_res--;
        logf("RESOLVE k %" PRIu64 " idx %d pos %d mis %d", r->k, r->idx,
             r->pos, r->mis);
      }
      if (keep.size() != rq.size()) rq.assign(keep.begin(), keep.end());
    }
    // The slots taken.
    int64_t hold_c = cyc + 1;          // the take cycle
    if (top->dec_ibuf_rdy) {
      int ntake = 0;
      for (int i = 0; i < SLOTS; i++) {
        if (!((top->pd_valid >> i) & 1)) continue;
        ntake++;
        c.taken++;
        uint64_t pc = top->pd_pc[i];
        {
          // Every slot taken has a record whose block holds it
          // (err_no_record): the PC is the record's start plus two bytes
          // per position.
          const FRec& e = frec[top->pd_idx[i]];
          if (!e.valid ||
              pc != ((e.start_pc + 2 * uint64_t(top->pd_pos[i])) & VA_MASK)) {
            c.no_record++;
            logf("NORECORD pc %" PRIx64 " idx %d pos %d valid %d start %"
                 PRIx64, pc, int(top->pd_idx[i]), int(top->pd_pos[i]),
                 int(e.valid), e.start_pc);
          }
        }
        if (pend != nullptr) {
          // The slot after a branch that ended its bundle decides it.
          decide(pend, pc != (expect_next & VA_MASK), hold_c);
          pend = nullptr;
        }
        if (wrong || tp >= path_len) {
          // The wrong path (PF-8).
          c.taken_wp++;
          n_wp++;
          logf("WRONGPATH pc %" PRIx64, pc);
          continue;
        }
        perf::Inst in;
        sup.at(tp, in);
        if (pc != (in.pc & VA_MASK)) {
          // Fetch left the path where the prediction said it would not.
          c.taken_wp++;
          n_wp++;
          wrong = true;
          if (have_last && last->is_br && !last->nxt_seen) {
            last->nxt_seen = true;
            last->nxt_ok = false;
          }
          if (drive && have_last && last->is_br && !last->res_sent) {
            // Under the fetch rule the branch's verdict, in its resolve
            // cycle, redirects or finds the stream wrong (err_stream).
            logf("OFFPATH before verdict pc %" PRIx64 " exp %" PRIx64, pc,
                 in.pc);
            continue;
          }
          if (have_last && last->is_br && !last->res_sent) {
            // THE STREAM RULE: the stream shows the branch mispredicted.
            logf("FLIP predicted correct, fetch gave %" PRIx64, pc);
            last->mis = true;
            rd.v = true;
            rd.at = std::max(last->res_c, hold_c);
            rd.idx = last->idx; rd.pos = last->pos; rd.pc = in.pc;
            rd.self = false; rd.cause = 0; rd.taken = last->in.taken;
            rd.next_k = tp; rd.ptr = last->ptr; rd.unspec = false;
          } else {
            // After a PC whose record's class is not the image's
            // (rewritten code, supply.h conflict), fetch follows the
            // image: counted apart, not as an error.
            // The repair names the last path instruction taken, from a copy
            // kept past its commit (RC_REPLAY, self clear).
            if (lc.v && sup.conflict(lc.pc)) c.class_conflict++;
            else c.stream_bad++;
            // An entry already committed cannot be named (R2): then every
            // path instruction has retired, the window is empty, and the
            // repair is RC_UNSPEC, every entry squashed.
            bool freed = lc.v && wm_val && ((wm - lc.ptr) & 127u) < 64u;
            if (lc.v && !freed) {
              rd.v = true; rd.at = hold_c; rd.idx = lc.idx;
              rd.pos = lc.pos; rd.pc = in.pc; rd.self = false;
              rd.cause = 2; rd.taken = false; rd.next_k = tp;
              rd.ptr = lc.ptr; rd.unspec = false;
            } else {
              rd.v = true; rd.at = hold_c; rd.pc = in.pc; rd.cause = 3;
              rd.unspec = true; rd.next_k = tp;
            }
          }
          logf("OFFPATH pc %" PRIx64 " exp %" PRIx64, pc, in.pc);
          continue;
        }
        // The path's next instruction.
        if (have_last && last->is_br && !last->nxt_seen) {
          last->nxt_seen = true;
          last->nxt_ok = true;
        }
        pred_mis_last = false;
        if (top->pd_instr[i] != sup.word(in.pc)) c.instr_bad++;
        if (top->pd_fault[i] != 0) c.faults++;
        if ((top->pd_illegal >> i) & 1) c.illegal++;
        // Its FTQ pointer.
        uint8_t idx = top->pd_idx[i];
        uint32_t ptr;
        if (after_redir) {
          ptr = redir_next & 127u;
          if ((ptr & 63u) != idx) c.idx_bad++;
          ptr = (ptr & ~63u) | idx;
          after_redir = false;
        } else if (!cur_val) {
          ptr = idx;
        } else if (idx != (cur_ptr & 63u)) {
          ptr = (cur_ptr + ((uint32_t(idx) - (cur_ptr & 63u)) & 63u)) & 127u;
        } else {
          ptr = cur_ptr;
        }
        cur_ptr = ptr;
        cur_val = true;
        if (ents.empty() || ents.back().ptr != ptr) {
          if (!ents.empty()) ents.back().closed = true;
          if (ptr == wm && wm_val) c.reopen++;   // an entry already freed
          ents.push_back(Ent{ptr});
        } else if (ents.back().closed) {
          c.reopen++;                            // closed, then more came
        }
        Ent* en = &ents.back();
        en->n_taken++;
        Ro r;
        r.k = tp;
        r.in = in;
        r.ptr = ptr;
        r.idx = idx;
        r.pos = top->pd_pos[i];
        r.is_br = cbp::is_branch(in.cls);
        // THE RESOLUTION TARGET (ftb_decisions.md 5.5, fe_tb_backend.svh
        // br_target): a conditional resolves with its taken target whatever
        // its direction, the target the image's B-type word at its PC
        // encodes (the stub for a veneered branch, PF-15). Every other type
        // resolves with its traced target. At a class-conflict PC the
        // image may hold another class; the traced target is sent there.
        r.rsv_tgt = in.target;
        if (in.cls == cbp::C_COND) {
          uint32_t w = sup.word(in.pc);
          bool conf = sup.conflict(in.pc);
          if (rv::is_b_type(w)) r.rsv_tgt = rv::br_target(in.pc, w);
          // The hard check: a taken conditional's encoded target is its
          // traced target, except at a class-conflict PC.
          if (in.taken && !conf && ((r.rsv_tgt & VA_MASK) !=
                                    (in.target & VA_MASK)))
            c.cond_target_bad++;
          if (!rv::is_b_type(w) && !conf) c.cond_target_bad++;
        }
        r.take_c = hold_c;
        // THE BACKEND STAGES: take to resolve is decode + rename +
        // dispatch + execute, each drawn from its own stream (PF-18).
        int64_t rl = d_dec.draw(g_dec) + d_ren.draw(g_ren) +
                     d_dis.draw(g_dis) + d_exe.draw(g_exe);
        r.res_c = hold_c + rl;
        r.commit_c = std::max(r.res_c + d_r2c.draw(g_r2c), last_commit_c);
        c.res_sched += uint64_t(rl);
        c.commit_dly += uint64_t(r.commit_c - r.res_c);
        last_commit_c = r.commit_c;
        r.ent = en;
        // The next PC on the path.
        perf::Inst nx;
        uint64_t next_pc = sup.at(tp + 1, nx) ? nx.pc : in.pc + 4;
        if (r.is_br) {
          en->n_res++;
          // THE VERDICT is read from the record in the resolve cycle;
          // the record's counts at the take show what was written after.
          r.fr_seq = frec[idx].seq;
          r.orc_forced = oent[idx].valid && oent[idx].on;
          r.fr_req_seq = frec[idx].req_seq;
        }
        // A deque keeps references across push_back, and an entry leaves
        // only by commit, after its resolution: res_at's pointer stays
        // valid.
        rob.push_back(r);
        Ro* rp = &rob.back();
        bool pending = false;
        if (rp->is_br && drive) {
          // THE FETCH RULE: decided in the resolve cycle from the record,
          // with no wait for the next slot.
          res_at.emplace(rp->res_c, rp);
        } else if (rp->is_br) {
          // THE STREAM RULE: the next slot of this bundle decides, else the
          // next slot fetch delivers (decide()), as fe_tb_backend.svh.
          if (i + 1 < SLOTS && ((top->pd_valid >> (i + 1)) & 1)) {
            rp->mis = uint64_t(top->pd_pc[i + 1]) != (next_pc & VA_MASK);
          } else if (tp + 1 < path_len) {
            pending = true;
          }
          if (!pending) res_at.emplace(rp->res_c, rp);
        }
        last = rp;
        have_last = true;
        lc.v = true; lc.idx = idx; lc.pos = rp->pos; lc.ptr = ptr;
        lc.pc = in.pc;
        expect_next = next_pc;
        last_take_c = cyc;
        logf("TAKE k %" PRIu64 " pc %" PRIx64 " cls %d idx %d pos %d ptr %u "
             "br %d mis %d src %d next %" PRIx64 " res %" PRId64 " cmt %"
             PRId64, tp, in.pc, in.cls, idx, r.pos, ptr, r.is_br, r.mis,
             r.src, next_pc, r.res_c, r.commit_c);
        tp++;
        if (pending) {
          pend = rp;
        } else if (rp->is_br && rp->mis) {
          // The redirect, in its resolve cycle; what follows is wrong.
          wrong = true;
          pred_mis_last = true;
          rd.v = true; rd.at = rp->res_c; rd.idx = idx; rd.pos = rp->pos;
          rd.pc = next_pc; rd.self = false; rd.cause = 0;
          rd.taken = in.taken; rd.next_k = tp; rd.ptr = ptr;
          rd.unspec = false;
        } else if (!rp->is_br && tp < path_len &&
                   (next_pc & VA_MASK) != ((in.pc + 4) & VA_MASK)) {
          // A trace discontinuity after a non-branch: a trap or an
          // exception entry, which the trace records as the next PC. The
          // instruction completes and fetch restarts at the next PC, in
          // its resolve cycle (RC_TRAP, self clear).
          c.traps++;
          wrong = true;
          rd.v = true; rd.at = rp->res_c; rd.idx = idx; rd.pos = rp->pos;
          rd.pc = next_pc; rd.self = false; rd.cause = 1; rd.taken = false;
          rd.next_k = tp; rd.ptr = ptr; rd.unspec = false;
        }
      }
      credit -= ntake;
    }
    if (redir_now) {
      // The redirect fired at this edge: the wrong path is gone.
      c.redirects++;
      // THE ORACLE: fetch restarts on the path at the redirect.
      opend.v = true;
      opend.pc = rd.pc & VA_MASK;
      opend.k = rd.next_k;
      started = true;
      if (rd.unspec && wm_val) {
        // Mid-run: every entry squashed; allocation resumes after the
        // last committed entry.
        c.unspec_repair++;
        ents.clear();
        after_redir = true;
        redir_next = (wm + 1) & 127u;
      } else if (rd.unspec) {
        cur_val = false;
        after_redir = false;
      } else {
        ents.back().closed = true;
        after_redir = true;
        redir_next = (rd.ptr + 1) & 127u;
      }
      wrong = false;
      pred_mis_last = false;
      n_wp = 0;
      tp = rd.next_k;
      rd.v = false;
    }
    // Commit, in order.
    while (!rob.empty()) {
      Ro& r = rob.front();
      if (r.commit_c > cyc + 1) break;
      if (r.is_br && !r.res_done) break;
      // The counts (PF-6), by committed instruction.
      uint64_t e = r.k / EPOCH;
      if (c.ep_instr.size() <= e) {
        c.ep_instr.resize(e + 1, 0);
        c.ep_numbr.resize(e + 1, 0);
        c.ep_mis_cond.resize(e + 1, 0);
        c.ep_mis.resize(e + 1, 0);
      }
      c.instr++;
      c.ep_instr[e]++;
      if (r.in.cls == cbp::C_COND) {
        c.cond++;
        c.numbr += r.in.pieces;
        c.ep_numbr[e] += r.in.pieces;
      }
      if (r.mis) {
        c.mis++;
        c.ep_mis[e]++;
        c.mis_src[r.src]++;
        if (r.in.cls == cbp::C_COND) { c.mis_cond++; c.ep_mis_cond[e]++; }
        else if (r.in.cls == cbp::C_JMP_DIR || r.in.cls == cbp::C_CALL_DIR)
          c.mis_dir++;
        else if (r.in.cls == cbp::C_RET) c.mis_ret++;
        else c.mis_ind++;
      }
      if (r.is_br) c.pred_src[r.src]++;
      if (r.is_br) {
        // The slot-held branches, and the misses by class (PF-11).
        int mc = r.in.cls == cbp::C_COND ? 0
               : (r.in.cls == cbp::C_JMP_DIR || r.in.cls == cbp::C_CALL_DIR)
                   ? 1
               : r.in.cls == cbp::C_RET ? 3 : 2;
        // A mispredict whose trace next PC is not the branch's own outcome
        // (its target when taken, pc + 4 when not) is a trace discontinuity
        // after the branch, an exception entry the trace records as the
        // next PC: it counts as a mispredict (THE VERDICT compares with the
        // trace's next PC) and is counted apart here (orc_slot_trap).
        perf::Inst nxo;
        uint64_t own = ((r.in.taken ? r.in.target : r.in.pc + 4) & VA_MASK);
        bool trap_after = sup.at(r.k + 1, nxo) && (nxo.pc & VA_MASK) != own;
        if (r.is_br && r.mis && trap_after) c.br_trap_after++;
        if (r.in_slot) {
          if (r.mis && trap_after) c.orc_slot_trap++;
          else if (r.mis) c.orc_slot_mis++;
          if (o.oracle && r.mis && n_frdis_log < 20) {
            n_frdis_log++;
            const FRec& e = frec[r.idx];
            perf::Inst nx;
            uint64_t tn = sup.at(r.k + 1, nx) ? nx.pc : 0;
            std::fprintf(stderr, "ORCMIS k %" PRIu64 " pc %" PRIx64 " cls %d "
                         "tk %d tgt %" PRIx64 " idx %d pos %d forced %d next %"
                         PRIx64 " rec start %" PRIx64 " next %" PRIx64
                         " tk %d/%d take %" PRId64 "\n", r.k, r.in.pc,
                         int(r.in.cls), int(r.in.taken), r.in.target,
                         int(r.idx), int(r.pos), int(r.orc_forced), tn,
                         e.start_pc, e.next_pc, int(e.taken_val),
                         int(e.taken_pos), r.take_c);
          }
        } else {
          c.miss[mc]++;
          if (r.mis) c.miss_mis[mc]++;
        }
        if (o.oracle && !r.orc_forced) c.orc_path_unforced++;
      }
      if (r.is_br && drive && r.fr_mis) c.fr_mis++;
      if (r.is_br && !drive) {
        // The fetch verdict against the stream verdict, by case (THE
        // CASES): C3 the path's last branch, excluded; C2 a branch at a
        // class-conflict PC or before one; C1 decided by the slot
        // reading; every other disagreement is fr_disagree.
        if (r.fr_mis) c.fr_mis++;
        perf::Inst nx;
        bool has_next = sup.at(r.k + 1, nx);
        bool agree = r.fr_mis == r.mis;
        if (!has_next) {
          c.fr_c3++;
        } else if (sup.conflict(r.in.pc) || sup.conflict(nx.pc)) {
          if (agree) c.fr_c2_ag++; else c.fr_c2_dis++;
        } else if (r.slot_dec) {
          if (agree) c.fr_c1_ag++; else c.fr_c1_dis++;
        } else if (agree) {
          c.fr_ag++;
        } else {
          c.fr_dis++;
          if (n_frdis_log < 20) {
            n_frdis_log++;
            const FRec& e = frec[r.idx];
            std::fprintf(stderr, "FRDIS k %" PRIu64 " pc %" PRIx64 " cls %d "
                         "idx %d pos %d stream %d fetch %d next %" PRIx64
                         " rec start %" PRIx64 " next %" PRIx64 " tk %d/%d "
                         "take %" PRId64 "\n", r.k, r.in.pc, int(r.in.cls),
                         int(r.idx), int(r.pos), int(r.mis), int(r.fr_mis),
                         nx.pc, e.start_pc, e.next_pc, int(e.taken_val),
                         int(e.taken_pos), r.take_c);
          }
        }
      }
      r.ent->n_commit++;
      c.commit_wait += uint64_t(cyc + 1 - r.commit_c);
      logf("COMMIT k %" PRIu64 " in cycle %" PRId64 " (take %" PRId64
           " resolve %" PRId64 " drawn commit %" PRId64 ")", r.k, cyc + 1,
           r.take_c, r.res_c, r.commit_c);
      if (have_last && last == &r) { have_last = false; last = nullptr; }
      committed++;
      sup.commit(r.k + 1);
      rob.pop_front();
    }

    top->clk = 1;
    top->eval();
    ic.after_edge(cyc);
    if (cyc == START_CYC - 1) ic.start(mem, vmap, sup);
    cyc++;
    if (cyc > START_CYC && top->ftq_full) c.ftq_full++;
    if (cyc - last_take_c > 200000) {
      status = perf::fmt("stalled: no path instruction taken for 200000 "
                         "cycles at instruction %" PRIu64, tp);
      std::fprintf(stderr, "STALL cyc %" PRId64 " tp %" PRIu64 " rob %zu "
                   "rq %zu res_at %zu ents %zu wm %u/%d wrong %d rd.v %d "
                   "after_redir %d cur_ptr %u npres %d\n", cyc, tp,
                   rob.size(), rq.size(), res_at.size(), ents.size(), wm,
                   int(wm_val), int(wrong), int(rd.v), int(after_redir),
                   cur_ptr, int(top->pd_valid));
      std::fprintf(stderr, "  mem gets %zu d_busy %d d_beat %d pw_pend %d "
                   "l1i_req %d l1i_rdy %d paddr %" PRIx64 " a_valid %d "
                   "ptw_req %d ftq_full %d ftq_empty %d\n", gets.size(),
                   int(d_busy), d_beat, int(pw_pend), int(top->obs_l1i_req),
                   int(top->obs_l1i_rdy), uint64_t(top->obs_l1i_paddr),
                   int(top->l1i_a_valid), int(top->ptw_req_val),
                   int(top->ftq_full), int(top->ftq_empty));
      for (size_t i = 0; i < ents.size() && i < 4; i++)
        std::fprintf(stderr, "  ent ptr %u taken %" PRIu64 " commit %" PRIu64
                     " res %" PRIu64 " closed %d\n", ents[i].ptr,
                     ents[i].n_taken, ents[i].n_commit, ents[i].n_res,
                     int(ents[i].closed));
      if (!rob.empty())
        std::fprintf(stderr, "  rob front k %" PRIu64 " pc %" PRIx64 " br %d "
                     "res_sent %d res_done %d commit_c %" PRId64 "\n",
                     rob.front().k, rob.front().in.pc, int(rob.front().is_br),
                     int(rob.front().res_sent), int(rob.front().res_done),
                     rob.front().commit_c);
      if (!rq.empty())
        std::fprintf(stderr, "  rq front k %" PRIu64 " idx %d pos %d rdy %d\n",
                     rq.front()->k, rq.front()->idx, rq.front()->pos,
                     int(top->rsv_rdy));
      break;
    }
    if (o.max_cycles && uint64_t(cyc) >= o.max_cycles) {
      status = "stopped at --max-cycles";
      break;
    }
  }
  c.cycles = uint64_t(cyc > START_CYC ? cyc - START_CYC : 0);
  c.ic_installs = ic.installs();
  double sim_s = std::chrono::duration<double>(
                     std::chrono::steady_clock::now() - t_sim).count();
  double tot_s = std::chrono::duration<double>(
                     std::chrono::steady_clock::now() - t_start).count();
  top->final();

  // ---- the result row (PF-9) ---------------------------------------------
  uint64_t hi, hb, hmc, hm;
  half(c, hi, hb, hmc, hm);
  auto mpki = [](uint64_t m, uint64_t n) {
    return n ? 1000.0 * double(m) / double(n) : 0.0;
  };
  // The hard checks. err_stream (fetch left the path after a correctly
  // predicted instruction) is a hard check under the fetch rule; under the
  // stream rule it is RTL behavior the backend repairs, counted, and does
  // not fail the run. fr_disagree (the record against the stream) is hard
  // under the stream rule, where it is computed.
  uint64_t errs = c.instr_bad + c.faults + c.illegal + c.idx_bad +
                  c.opcode_bad + c.reopen + c.unspec_repair +
                  c.cond_target_bad + c.no_record + c.late_write +
                  c.fetch_port + c.fr_dis + c.fr_moved + c.fetch_rule_bad +
                  (drive ? c.stream_bad : 0) +
                  (o.oracle ? c.orc_slot_mis : 0);
  if (status == "ok" && errs) status = "check_errors";
  std::vector<std::pair<std::string, std::string>> row = {
    {"trace", o.trace}, {"set", o.set}, {"config", o.config},
    {"revision", PERF_BUILD_NAME}, {"sha", PERF_SRC_SHA},
    {"src_root", PERF_SRC_ROOT}, {"seed", std::to_string(o.seed)},
    {"num_pred_slots", std::to_string(NPS)},
    {"mispredict_rule", o.mrule},
    {"oracle", o.oracle ? "1" : "0"},
    {"decode_lat", o.dlat}, {"rename_lat", o.nlat},
    {"dispatch_lat", o.plat}, {"execute_lat", o.xlat},
    {"resolve_commit", o.r2c},
    {"take_rate", o.take}, {"window", std::to_string(o.window)},
    {"icache", o.icache}, {"mem_lat", std::to_string(o.mem_lat)},
    {"ptw_lat", std::to_string(o.ptw_lat)}, {"fast_init", "1"},
    {"sc_enable", std::to_string(o.cfg.sc_enable)},
    {"ftb_fastpath_en", std::to_string(o.cfg.ftb_fastpath_en)},
    {"tage_enable_aging", std::to_string(o.cfg.tage_enable_aging)},
    {"ittage_enable_aging", std::to_string(o.cfg.ittage_enable_aging)},
    {"tage_aging_interval", std::to_string(o.cfg.tage_aging_interval)},
    {"ittage_aging_interval", std::to_string(o.cfg.ittage_aging_interval)},
    {"max_instr", std::to_string(o.max_instr)},
    {"fe_cfg_seen", perf::fmt("en%x/%u/%u", unsigned(top->obs_cfg_en),
                              unsigned(top->obs_cfg_tage_int),
                              unsigned(top->obs_cfg_ittage_int))},
    {"status", status},
    {"cycles", std::to_string(c.cycles)}, {"instr", std::to_string(c.instr)},
    {"NumBr", std::to_string(c.numbr)}, {"cond", std::to_string(c.cond)},
    {"mispred", std::to_string(c.mis)},
    {"mpki", perf::fmt("%.4f", mpki(c.mis, c.instr))},
    {"mispred_cond", std::to_string(c.mis_cond)},
    {"mpki_cond", perf::fmt("%.4f", mpki(c.mis_cond, c.instr))},
    {"mispred_direct", std::to_string(c.mis_dir)},
    {"mispred_indirect", std::to_string(c.mis_ind)},
    {"mispred_return", std::to_string(c.mis_ret)},
  };
  for (int s = 0; s < 8; s++) {
    row.push_back({std::string("mis_") + SRC_NAME[s],
                   std::to_string(c.mis_src[s])});
    row.push_back({std::string("mpki_") + SRC_NAME[s],
                   perf::fmt("%.4f", mpki(c.mis_src[s], c.instr))});
    row.push_back({std::string("pred_") + SRC_NAME[s],
                   std::to_string(c.pred_src[s])});
  }
  std::vector<std::pair<std::string, std::string>> tail = {
    {"50PercInstr", std::to_string(hi)}, {"50PercNumBr", std::to_string(hb)},
    {"50PercMispCond", std::to_string(hmc)},
    {"50PercMpkiCond", perf::fmt("%.4f", mpki(hmc, hi))},
    {"50PercMisp", std::to_string(hm)},
    {"50PercMpki", perf::fmt("%.4f", mpki(hm, hi))},
    {"ipc", perf::fmt("%.4f", c.cycles ? double(c.instr) / double(c.cycles)
                                       : 0.0)},
    {"taken", std::to_string(c.taken)},
    {"taken_per_cycle", perf::fmt("%.4f", c.cycles ? double(c.taken) /
                                                      double(c.cycles) : 0)},
    {"taken_wrong_path", std::to_string(c.taken_wp)},
    {"ftq_full_cycles", std::to_string(c.ftq_full)},
    {"redirects", std::to_string(c.redirects)},
    {"trap_redirects", std::to_string(c.traps)},
    {"pd_redirects", std::to_string(c.pd_redir)},
    {"p2_overrides", std::to_string(c.p2_redir)},
    {"p3_overrides", std::to_string(c.p3_redir)},
    {"l1i_gets", std::to_string(c.gets)},
    {"l1i_gets_mask0", std::to_string(c.gets_mask0)},
    {"icache_installs", std::to_string(c.ic_installs)},
    {"walks", std::to_string(c.walks)},
    {"ptw_reads", std::to_string(c.ptw_rd)},
    {"ptw_cas", std::to_string(c.ptw_cas)},
    {"resolve_lat_sum", std::to_string(c.res_sched)},
    {"commit_delay_sum", std::to_string(c.commit_dly)},
    {"commit_wait_sum", std::to_string(c.commit_wait)},
    {"resolve_wait_sum", std::to_string(c.res_wait)},
    {"decided_by_slot", std::to_string(c.slot_decided)},
    {"err_stream", std::to_string(c.stream_bad)},
    {"err_word", std::to_string(c.instr_bad)},
    {"err_fault", std::to_string(c.faults)},
    {"err_illegal", std::to_string(c.illegal)},
    {"err_ftq_idx", std::to_string(c.idx_bad)},
    {"err_tl_opcode", std::to_string(c.opcode_bad)},
    {"err_entry_reopen", std::to_string(c.reopen)},
    {"err_unspec_repair", std::to_string(c.unspec_repair)},
    {"err_cond_target", std::to_string(c.cond_target_bad)},
    {"err_fetch_rule", std::to_string(c.fetch_rule_bad)},
    {"orc_forced_entries", std::to_string(c.orc_on)},
    {"orc_offpath_entries", std::to_string(c.orc_off)},
    {"orc_path_unforced", std::to_string(c.orc_path_unforced)},
    {"orc_realigned", std::to_string(c.orc_realign)},
    {"err_orc_slot_mispred", std::to_string(c.orc_slot_mis)},
    {"orc_slot_trap", std::to_string(c.orc_slot_trap)},
    {"mispred_trap_after", std::to_string(c.br_trap_after)},
    {"miss_cond", std::to_string(c.miss[0])},
    {"miss_cond_mis", std::to_string(c.miss_mis[0])},
    {"miss_direct", std::to_string(c.miss[1])},
    {"miss_direct_mis", std::to_string(c.miss_mis[1])},
    {"miss_indirect", std::to_string(c.miss[2])},
    {"miss_indirect_mis", std::to_string(c.miss_mis[2])},
    {"miss_return", std::to_string(c.miss[3])},
    {"miss_return_mis", std::to_string(c.miss_mis[3])},
    {"err_no_record", std::to_string(c.no_record)},
    {"err_late_write", std::to_string(c.late_write)},
    {"err_fetch_port", std::to_string(c.fetch_port)},
    {"fr_mispred", std::to_string(c.fr_mis)},
    {"fr_agree", std::to_string(c.fr_ag)},
    {"fr_disagree", std::to_string(c.fr_dis)},
    {"fr_c1_agree", std::to_string(c.fr_c1_ag)},
    {"fr_c1_disagree", std::to_string(c.fr_c1_dis)},
    {"fr_c2_agree", std::to_string(c.fr_c2_ag)},
    {"fr_c2_disagree", std::to_string(c.fr_c2_dis)},
    {"fr_c3_excluded", std::to_string(c.fr_c3)},
    {"err_record_moved", std::to_string(c.fr_moved)},
    {"fr_corr_after_take", std::to_string(c.fr_corr_late)},
    {"fr_beyond_taken", std::to_string(c.fr_beyond)},
    {"fr_requests", std::to_string(c.fr_req)},
    {"fr_corrections", std::to_string(c.fr_corr)},
    {"class_conflict_passes", std::to_string(c.class_conflict)},
    {"class_conflict_pcs", std::to_string(sup.conflicts())},
    {"static_pcs", std::to_string(sup.static_pcs())},
    {"stubs", std::to_string(sup.stub_count())},
    {"pages", std::to_string(vmap.size())},
    {"host_seconds", perf::fmt("%.1f", tot_s)},
    {"sim_seconds", perf::fmt("%.1f", sim_s)},
    {"instr_per_sec", perf::fmt("%.0f", sim_s > 0 ? double(c.instr) / sim_s
                                                   : 0)},
    {"cycles_per_sec", perf::fmt("%.0f", sim_s > 0 ? double(c.cycles) /
                                                      sim_s : 0)},
  };
  row.insert(row.end(), tail.begin(), tail.end());
  for (auto& kv : row)
    std::printf("%-22s %s\n", kv.first.c_str(), kv.second.c_str());
  if (!o.out.empty()) {
    bool is_new = !file_exists(o.out);
    FILE* f = std::fopen(o.out.c_str(), "a");
    if (f == nullptr) die("cannot write " + o.out);
    if (is_new) {
      for (size_t i = 0; i < row.size(); i++)
        std::fprintf(f, "%s%s", i ? "," : "", row[i].first.c_str());
      std::fprintf(f, "\n");
    }
    for (size_t i = 0; i < row.size(); i++)
      std::fprintf(f, "%s%s", i ? "," : "", row[i].second.c_str());
    std::fprintf(f, "\n");
    std::fclose(f);
  }
  return status == "ok" ? 0 : 2;
}
