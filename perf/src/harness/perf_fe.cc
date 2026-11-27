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
//            verdict decides a waiting branch only when the ibuf stays
//            empty (decided_by_slot). The record's verdict
//            is compared with the stream's on every branch, by case
//            (fr_*). pred_src is the record's slot at the branch's
//            position under either rule (PF-6).
//            A TRAP AFTER A BRANCH (the trace's next record is not the
//            branch's own outcome, PERF-004, PF-18): under either rule the
//            branch is judged on its own outcome, its target when taken and
//            pc + 4 when not, from the record in its resolve cycle, and the
//            trap is a separate RC_TRAP redirect to the trace's next PC in
//            that cycle, as after a non-branch (trap_after_branch).
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
#include "ras_class.h"
#include "rv_encode.h"
#include "supply.h"
#include "tage_hash.h"

// THE BUILD STAMP (PERF-004, TD#210): the sha, the dirty mark and the
// input digest, written by perf/src/stamp.py into the build directory
// (perf/Makefile), and written to every result row.
#if __has_include("perf_stamp.h")
#include "perf_stamp.h"
#endif
#ifndef PERF_SRC_ROOT
#define PERF_SRC_ROOT "unknown"
#endif
#ifndef PERF_SRC_SHA
#define PERF_SRC_SHA "unknown"
#endif
#ifndef PERF_SRC_DIRTY
#define PERF_SRC_DIRTY "unknown"
#endif
#ifndef PERF_INPUT_DIGEST
#define PERF_INPUT_DIGEST "unknown"
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
"  --stamp                   print the build stamp (sha, dirty mark, input\n"
"                            digest, PERF-004) and exit\n"
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

// PERF-005 Phase 2: the fast-path cost histogram's bucket count (FH_NAME).
static const int FH_N = 12;

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
  // PERF-004: and the request's slot at its position was of the other
  // kind, conditional against unconditional (an alias: the predictor's
  // entry describes another branch). The request's type is the one the
  // predictors gave: a predecode correction may rewrite it (M3 keeps the
  // alias's taken). A slot's type is never forced (PF-11), so its
  // mispredict under the oracle is not a forcing failure
  // (orc_slot_kind_alias).
  bool     kind_alias = false;
  // A TRAP AFTER A BRANCH (PERF-004, PF-18, Jeff session-086): the trace's
  // next record is not the branch's own outcome (an exception entry). The
  // branch is judged on own_next, its target when taken and pc + 4 when
  // not; the trap is a separate RC_TRAP redirect, as for a non-branch.
  bool     trap_after = false;
  uint64_t own_next = 0;
  bool     orc_forced = false;   // its entry was allocated on the path
  uint8_t  src = SRC_NONE;
  uint8_t  rsn = 255;            // PERF-005: the reason (classify())
  int      xp = -1;              // and the SC partition
  // PERF-005 Phase 2: from the slot's decision (Dec): TAGE's response
  // for this entry and its direction, and the FTB field's shadow state.
  bool     dv = false, d_thit = false, d_ttk = false;
  bool     d_fsh = false, d_fleft = false;
  uint32_t d_fres = 0;
  int64_t  take_c, res_c, commit_c;
  bool     res_sent = false, res_done = false;
  Ent*     ent;
  // THE RAS CLASSIFICATION (BP-151): a call's or a return's FTQ instance
  // and its RAS observation, at the take.
  rcls::IObs rco;
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
  uint64_t conflict_unspec = 0;   // RC_UNSPEC after a class conflict
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
  uint64_t orc_kind_alias = 0;   // PERF-004: slot of the other kind, mis
  uint64_t orc_realign = 0;
  uint64_t br_traps = 0;        // RC_TRAP redirects after a branch (PERF-004)
  // PERF-004 Phase 4, the configuration probes: fast-path directions, SC
  // answers, epoch advances (summed over slots) and decayed lookups per
  // tagged table (TAGE T1-T4, ITTAGE T1-T5).
  uint64_t cf_fp = 0, cf_sc = 0, cf_tg_ep = 0, cf_it_ep = 0;
  uint64_t cf_tg_dec[4] = {}, cf_it_dec[5] = {};
  uint8_t  tg_ep_last[2] = {}, it_ep_last[2] = {};
  uint64_t miss[4] = {}, miss_mis[4] = {};
  // PERF-005 Phase 1: the committed branches and their mispredicts by
  // reason, and the SC partition (XP_NAME); sized in main (R_N).
  std::vector<uint64_t> rsn_n, rsn_m;
  uint64_t xp_n[4] = {}, xp_m[4] = {};
  // PERF-005 Phase 2, from cycle 0. The checks (0 expected): the p2 read
  // conf against the shadow (fp_chk_rd), a p2 field the shadow lacks
  // (fp_chk_nosh), ftb_fastpath_p2 against 4.1 (fp_chk_41), the
  // cluster's use against ftb_fastpath_p2 and the loop (fp_chk_use); at
  // the update: the read conf (fu_chk_rd), the trained or allocated conf
  // (fu_chk_wr), the fields it does not train (fu_chk_keep), a hit or an
  // in-place without a shadow (fu_chk_nosh). The flow: conditional
  // resolutions accepted, the scheduler's accepted and dropped ones, and
  // the issued updates by outcome.
  uint64_t fp_rd = 0, fp_fire = 0, fp_chk_rd = 0, fp_chk_nosh = 0;
  uint64_t fp_chk_41 = 0, fp_chk_use = 0;
  uint64_t fu_chk_rd = 0, fu_chk_wr = 0, fu_chk_keep = 0, fu_chk_nosh = 0;
  uint64_t res_cond = 0, fs_acc = 0, fs_drop = 0;
  uint64_t fu_br = 0, fu_inpl = 0, fu_alloc = 0, fu_past = 0, fu_split = 0;
  uint64_t fu_leave = 0, fu_resat = 0;
  // The cost, per committed fast-path mispredict: the histogram of res
  // (after leaving saturation, and since the allocation), TAGE's unused
  // response right, wrong or absent; and over the correct fast-path
  // decisions, TAGE's response wrong.
  uint64_t fh_left[FH_N] = {}, fh_alloc[FH_N] = {}, fh_nosh = 0;
  uint64_t fpm_tg_right = 0, fpm_tg_wrong = 0, fpm_tg_none = 0;
  uint64_t fpc_tg_wrong = 0, fpc_tg_none = 0;
  // PERF-005 Phase 3, THE TAGE CHECKS. The history: committed entries
  // checked, without a lookup, the PC, and per table (T0-T4) the index
  // and tag against the rule model (A) and the folds (T1-T4); lookups
  // with any mismatch by cause: queued, in a rollback cycle, matching
  // the observed bundles (B), other. Bundles A against B per entry.
  uint64_t th_n = 0, th_nolk = 0, th_pc = 0, th_idx[5] = {}, th_tag[5] = {};
  uint64_t th_fold[5] = {}, th_bad = 0, th_bad_q = 0, th_bad_rb = 0;
  uint64_t th_bad_b = 0, th_bad_other = 0, th_hb_ab = 0;
  uint64_t th_lag = 0;   // lookups that the block before them was not in
  uint64_t th_ab_p1only = 0;
  // A != B bundles that are not p1only: the RTL corrected the bundle by a
  // rollback and it still differs (corr), or neither (other)
  uint64_t th_ab_corr = 0, th_ab_other = 0;
  // obs_ok split: an uncorrected A != B bundle in the window (n), only
  // corrected ones (c), none (nowin: unexplained, 0 expected)
  uint64_t th_bad_b_n = 0, th_bad_b_c = 0, th_bad_b_nowin = 0;
  // rollback-cycle lookups whose window holds an uncorrected A != B bundle
  uint64_t th_bad_rb_n = 0;
  uint64_t th_idxB[5] = {}, th_tagB[5] = {};
  // The read (p1) against the RAM shadow, and reads that shared a cycle
  // with a write of their RAM.
  uint64_t tr_n = 0, tr_bad = 0, tr_coll = 0;
  // The update: updates, deviations from the rules (we, address, field)
  // and their kinds; the entry trained no longer the one read (tag or
  // valid), its counter moved since the read; allocations made, refused
  // (longest provider, useful), other, and duplicates.
  uint64_t tu_n = 0, tu_mis = 0, tu_chk = 0, tu_chk_we = 0, tu_chk_addr = 0;
  uint64_t tu_chk_ctr = 0, tu_chk_use = 0, tu_chk_alc = 0;
  uint64_t tu_chk_uaon = 0;   // use_alt_on_na counter != its re-derivation
  uint64_t tu_gone_p = 0, tu_gone_a = 0, tu_stale_p = 0, tu_stale_a = 0;
  uint64_t tu_alc = 0, tu_alc_long = 0, tu_alc_use = 0, tu_alc_other = 0;
  uint64_t tu_alc_dup = 0, tu_alc_ntk = 0;
  uint64_t tu_rows[4] = {};       // provider prm, alt tagged, alt T0, T0
  // THE SC, re-derived (sc_decisions.md 9, 10): answers, the sum, the
  // decision (local and final direction, override, corner); updates, the
  // counter write enable and data, the global next state; the corners
  // consulted by the choice made; the largest threshold seen.
  uint64_t sp_n = 0, sp_chk_sum = 0, sp_chk_dec = 0;
  uint64_t su_n = 0, su_chk_wr = 0, su_chk_wd = 0, su_chk_glob = 0;
  uint64_t sp_hi_sc = 0, sp_hi_tg = 0, sp_med_sc = 0, sp_med_tg = 0;
  uint64_t sc_thr_max = 0;
  std::vector<uint64_t> ep_instr, ep_numbr, ep_mis_cond, ep_mis;
};

// ---- THE DECISION (PERF-005 Phase 1) ---------------------------------
// Why a slot's direction or target came from its source: the p2 and p3
// decision probes (perf_top dp2_*, dp3_*) of the entry's last
// allocation, by FTQ index and slot, copied into the fetch record at the
// request (the p3 write of the request's own cycle included, as the
// fetch read port carries it).
struct Dec {
  bool    p2 = false;           // a p2 pass of this allocation was seen
  bool    ftb = false, p1ret = false;
  bool    cond = false, lp = false, fp = false, trdy = false, thit = false;
  bool    usep = false, irdy = false, ibid = false, ihit = false;
  bool    pkv = false;
  uint8_t prm = 0, alt = 0;
  bool    p3 = false;           // a p3 pass of this allocation was seen
  bool    p3cond = false, schit = false, hold = false, p2tk = false;
  bool    sctk = false, lcl = false;
  uint8_t chs = 0;
  // PERF-005 Phase 2: TAGE's p2 direction (dp2_ttk), and the FTB field
  // the slot read as the conf shadow (FShE) held it at p2: found, its
  // trains since conf last left saturation, and whether it left (false:
  // since the allocation).
  bool     ttk = false;
  bool     fsh = false, fleft = false;
  uint32_t fres = 0;
};

// ---- THE FTB CONF SHADOW (PERF-005 Phase 2) ---------------------------
// The conf of every FTB field as the update wrote it (ftb_cntrl upd_new,
// probes fu_*), by set, way and position. It is the harness's own
// account of the array: the p2 read (fq_conf) and the update's read
// (fu_oconf) are checked against it, and the write against conf section
// 3.2 / 3.4 / 7 applied to it. res counts the in-place trains since conf
// last left saturation (left) or since the allocation (!left).
struct FShF {
  bool     v = false, left = false;
  uint8_t  pos = 0, conf = 0;
  uint32_t res = 0;
};
struct FShE { bool w = false; FShF f[2]; };
// ---- THE TAGE CHECKS (PERF-005 Phase 3) -------------------------------
// The index and tag are tage_hash.h's, the twin's code (Phase 4).
// The lookup of an FTQ index as the tables saw it (tl_*), the last one.
struct TLk {
  bool     v = false, q = false, rb = false;
  int64_t  cyc = 0;
  uint64_t pc = 0;
  uint16_t idx[5][2] = {}, tag[5][2] = {}, fh[12] = {};
};
// A history bundle: n bits, bit 0 the older; wc the cycle the history
// took it (observed bundles only: the hw_ write or the rollback's).
struct THb { uint8_t n = 0, tkn = 0; int64_t wc = -1; bool corr = false; };
// A committed-path global history (tage_hash.h).
typedef tg::Gh TGh;

// The fast-path cost histogram buckets (res at the mispredicting
// prediction).
static const char* const FH_NAME[FH_N] = {
  "0", "1", "2", "3", "4", "5_8", "9_16", "17_32", "33_64", "65_256",
  "257_1024", "gt1024"};
static int fh_bucket(uint32_t r) {
  if (r <= 4) return int(r);
  if (r <= 8) return 5;
  if (r <= 16) return 6;
  if (r <= 32) return 7;
  if (r <= 64) return 8;
  if (r <= 256) return 9;
  if (r <= 1024) return 10;
  return 11;
}
// THE REASONS. Each committed branch gets exactly one, from its kind
// (conditional, direct jump, return, indirect), the source its record's
// slot carries (pred_src) and the decision above; every reason belongs
// to one source, so the reasons of a source sum to its pred_ and mis_
// columns (rs_sum_err, 0 expected). A *_other reason is a case no rule
// below names (0 expected).
enum Rsn : uint8_t {
  R_C_LOOP_P2, R_C_LOOP_P1, R_C_FP, R_C_FTB_NORDY, R_C_FTB_BID,
  R_C_TG_P1, R_C_TG_P2, R_C_TG_P3, R_C_TG_P4, R_C_TG_A0, R_C_TG_A1,
  R_C_TG_A2, R_C_TG_A3, R_C_TG_T0, R_C_SC_TG_GEN, R_C_SC_TG_HI,
  R_C_SC_TG_MED, R_C_SC_FTB, R_C_UBTB, R_C_NONE_MISS, R_C_NONE_PD,
  R_C_OTHER,
  R_J_FTB, R_J_UBTB, R_J_NONE_MISS, R_J_NONE_PD, R_J_OTHER,
  R_R_RAS_P2, R_R_RAS_P1, R_R_RAS_P1RET, R_R_FTB_NOPEEK, R_R_UBTB,
  R_R_NONE_MISS, R_R_NONE_PD, R_R_OTHER,
  R_I_ITTAGE, R_I_FTB_NORDY, R_I_FTB_BID, R_I_FTB_NOHIT, R_I_UBTB,
  R_I_NONE_MISS, R_I_NONE_PD, R_I_OTHER,
  R_N
};
const char* RSN_NAME[R_N] = {
  "c_loop_p2", "c_loop_p1", "c_fastpath", "c_ftb_tage_nordy",
  "c_ftb_tage_bid", "c_tage_prm_t1", "c_tage_prm_t2", "c_tage_prm_t3",
  "c_tage_prm_t4", "c_tage_alt_t0", "c_tage_alt_t1", "c_tage_alt_t2",
  "c_tage_alt_t3", "c_tage_t0", "c_sc_tage_gen", "c_sc_tage_hi",
  "c_sc_tage_med", "c_sc_ftb", "c_ubtb", "c_none_miss", "c_none_pd",
  "c_other",
  "j_ftb", "j_ubtb", "j_none_miss", "j_none_pd", "j_other",
  "r_ras_p2", "r_ras_p1", "r_ras_p1ret", "r_ftb_nopeek", "r_ubtb",
  "r_none_miss", "r_none_pd", "r_other",
  "i_ittage", "i_ftb_it_nordy", "i_ftb_it_bid", "i_ftb_it_nohit",
  "i_ubtb", "i_none_miss", "i_none_pd", "i_other"};
// The source each reason belongs to (bp_pred_src_e); *_other carries
// the source the branch had, counted apart (rsn_src_other).
constexpr uint8_t S_UB = 0, S_LP = 1, S_FT = 2, S_TG = 3, S_SC = 4,
                  S_IT = 5, S_RS = 6, S_NO = 7, S_ANY = 8;
const uint8_t RSN_SRC[R_N] = {
  S_LP, S_LP, S_FT, S_FT, S_FT, S_TG, S_TG, S_TG, S_TG, S_TG, S_TG,
  S_TG, S_TG, S_TG, S_SC, S_SC, S_SC, S_SC, S_UB, S_NO, S_NO, S_ANY,
  S_FT, S_UB, S_NO, S_NO, S_ANY,
  S_RS, S_RS, S_RS, S_FT, S_UB, S_NO, S_NO, S_ANY,
  S_IT, S_FT, S_FT, S_FT, S_UB, S_NO, S_NO, S_ANY};

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
  // PERF-004: the slot as the request carried it, which a correction
  // does not change: what the predictors gave (orc_slot_kind_alias).
  bool     rq_val = false;
  uint8_t  rq_pos = 0, rq_type = 0;
  // PERF-005: the decision behind the slot, as the request carried it;
  // dv is cleared when a predecode correction rewrites the slot.
  Dec      d;
  bool     dv = false;
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
  // PERF-004: a slot of the request was at pos, and its branch type
  bool     rq_at_pos;
  uint8_t  rq_type;
  int      slot;          // PERF-005: the record's slot at pos, or -1
};
FVerdict fr_verdict(const FRec& e, uint8_t pos, uint64_t pc) {
  FVerdict v{(pc + 4) & VA_MASK, SRC_NONE, false, false, false, 0, -1};
  for (int s = 0; s < NPS; s++)
    if (e.s[s].rq_val && e.s[s].rq_pos == pos) {
      v.rq_at_pos = true;
      v.rq_type = e.s[s].rq_type;
      break;
    }
  for (int s = 0; s < NPS; s++)
    if (e.s[s].val && e.s[s].pos == pos) {
      v.src = e.s[s].src;
      v.in_slot = true;
      v.slot = s;
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

// THE REASON of a branch of trace class cls, from its verdict (PERF-005
// Phase 1). The rules, by kind and the slot's source:
//   conditional  LOOP: at p2 when the FTB answered and w_lp_use_p2 (p2),
//                else the p1 loop slot (p1). FTB: the fast path
//                (w_fp_use_p2), else TAGE's response absent
//                (w_tage_pred_rdy_p2 low) or for another entry
//                (branch_id mismatch); bp_cluster.sv 1068-1098, 1238-1242.
//                TAGE: the table that supplied the direction, the
//                primary (tage_prm_comp, T0 when 0) or the alternate
//                (tage_alt_comp) by tage_using_primary. SC: an override
//                at p3 (sc_pred_tkn differs from the p2 direction,
//                1465-1470) of TAGE's direction by corner (sc_chooser),
//                or of the FTB direction. UBTB: the p1 slot, the FTB
//                not answering. NONE: no slot at the position (a miss),
//                or a slot predecode rewrote (ftq_ifu.sv W1).
//   jump         FTB at p2; UBTB at p1; NONE as above
//   return       RAS at p2 (the peek, 1251-1256), at p1 (the TOS, 878-
//                883) or by the p1 return redirect (1311-1324, 1363-
//                1368); FTB at p2 with no peek; UBTB at p1 with no TOS
//   indirect     ITTAGE at p2; FTB at p2 by ITTAGE's response absent,
//                for another entry or a miss (1227-1229, 1258-1261);
//                UBTB at p1; NONE as above
// extra: a second partition of the TAGE and FTB-direction conditionals,
// by SC agreeing (an SC answer equal to the p2 direction) or not
// answering; -1 for every other branch.
uint8_t classify(const FRec& e, const FVerdict& v, uint8_t cls, int& extra) {
  extra = -1;
  int kind = cls == cbp::C_COND ? 0
           : (cls == cbp::C_JMP_DIR || cls == cbp::C_CALL_DIR) ? 1
           : cls == cbp::C_RET ? 2 : 3;
  static const uint8_t MISS[4] = {R_C_NONE_MISS, R_J_NONE_MISS,
                                  R_R_NONE_MISS, R_I_NONE_MISS};
  static const uint8_t PD[4] = {R_C_NONE_PD, R_J_NONE_PD, R_R_NONE_PD,
                                R_I_NONE_PD};
  static const uint8_t OTH[4] = {R_C_OTHER, R_J_OTHER, R_R_OTHER,
                                 R_I_OTHER};
  if (v.slot < 0) return v.src == S_NO ? MISS[kind] : OTH[kind];
  const FSlot& fs = e.s[v.slot];
  if (!fs.dv) return v.src == S_NO ? PD[kind] : OTH[kind];
  const Dec& d = fs.d;
  bool f2 = d.p2 && d.ftb;           // the FTB answered at p2
  if (v.src == S_NO) return OTH[kind];
  if (kind == 0) {
    if (v.src == S_LP) return f2 ? (d.lp ? R_C_LOOP_P2 : R_C_OTHER)
                                 : R_C_LOOP_P1;
    if (v.src == S_UB) return f2 ? R_C_OTHER : R_C_UBTB;
    if (!f2 || !d.cond || d.lp) return R_C_OTHER;
    bool sc_ans = d.p3 && d.p3cond && d.schit && !d.hold;
    if (v.src == S_FT) {
      if (d.fp) return R_C_FP;
      if (d.thit) return R_C_OTHER;
      extra = sc_ans ? 2 : 3;
      return d.trdy ? R_C_FTB_BID : R_C_FTB_NORDY;
    }
    if (v.src == S_TG) {
      if (d.fp || !d.thit) return R_C_OTHER;
      extra = sc_ans ? 0 : 1;
      if (d.usep) {
        if (d.prm == 0) return R_C_TG_T0;
        return d.prm <= 4 ? uint8_t(R_C_TG_P1 + d.prm - 1) : R_C_OTHER;
      }
      return d.alt <= 3 ? uint8_t(R_C_TG_A0 + d.alt) : R_C_OTHER;
    }
    if (v.src == S_SC) {
      if (!sc_ans || d.fp || d.sctk == d.p2tk) return R_C_OTHER;
      if (!d.thit) return R_C_SC_FTB;
      return d.chs == 0 ? R_C_SC_TG_GEN : d.chs == 2 ? R_C_SC_TG_HI
           : d.chs == 1 ? R_C_SC_TG_MED : R_C_OTHER;
    }
    return R_C_OTHER;
  }
  if (kind == 1) {
    if (v.src == S_FT) return f2 ? R_J_FTB : R_J_OTHER;
    if (v.src == S_UB) return f2 ? R_J_OTHER : R_J_UBTB;
    return R_J_OTHER;
  }
  if (kind == 2) {
    if (v.src == S_RS) {
      if (f2) return d.pkv ? R_R_RAS_P2 : R_R_OTHER;
      return (d.p2 && d.p1ret) ? R_R_RAS_P1RET : R_R_RAS_P1;
    }
    if (v.src == S_FT) return (f2 && !d.pkv) ? R_R_FTB_NOPEEK : R_R_OTHER;
    if (v.src == S_UB) return f2 ? R_R_OTHER : R_R_UBTB;
    return R_R_OTHER;
  }
  if (v.src == S_IT) return f2 ? R_I_ITTAGE : R_I_OTHER;
  if (v.src == S_FT) {
    if (!f2) return R_I_OTHER;
    if (!d.irdy) return R_I_FTB_NORDY;
    if (!d.ibid) return R_I_FTB_BID;
    if (!d.ihit) return R_I_FTB_NOHIT;
    return R_I_OTHER;
  }
  if (v.src == S_UB) return f2 ? R_I_OTHER : R_I_UBTB;
  return R_I_OTHER;
}
const char* XP_NAME[4] = {"c_tage_sc_agree", "c_tage_sc_none",
                          "c_ftbdir_sc_agree", "c_ftbdir_sc_none"};

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
    else if (a == "--stamp") {
      std::printf("sha     %s\ndirty   %s\ndigest  %s\nbuild   %s_s%d\n",
                  PERF_SRC_SHA, PERF_SRC_DIRTY, PERF_INPUT_DIGEST,
                  PERF_BUILD_NAME, PERF_SLOTS);
      return 0;
    }
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
  c.rsn_n.assign(R_N, 0);
  c.rsn_m.assign(R_N, 0);
  std::vector<FRec> frec(64);          // THE RECORD, by FTQ index
  // PERF-005: THE DECISION of each index's last allocation, by slot.
  std::vector<std::vector<Dec>> dec(64, std::vector<Dec>(NPS));
  // PERF-005 Phase 2: THE FTB CONF SHADOW, by set * 4 + way (FTB_WAYS 4,
  // FTB_IDX_BITS up to 10; checked at the first probe).
  std::vector<FShE> fsh(4096);
  int n_fdev = 0;                      // deviations printed (20 at most)
  // PERF-005 Phase 3: THE TAGE CHECKS. The last lookup of each FTQ index;
  // the bundles, by the rule model (A: the request's slots, a backend
  // mispredict's correction) and as observed (B: hw_*, hr_*); the
  // committed-path histories; the RAM shadow [table][slot][index] (the
  // harness's +TAGE_FAST_INIT: T0 2'b10, T1-T4 0), the last cycle's
  // writes by RAM.
  std::vector<TLk> tlk(64);
  std::vector<THb> hbA(64), hbB(64);
  TGh ghA, ghB;
  int64_t th_last = -1;                // the FTQ pointer last committed
  uint8_t th_last_idx = 0;
  // The last committed entry's bundles, taken at each of its commits: its
  // FTQ slot can be allocated again before the next entry's first commit
  // (the FTQ wraps while that commit waits), and the new entry's p1 write
  // then replaces hbA/hbB at that index. An entry's bundle is final at its
  // last commit (no rollback names a committed entry).
  THb th_snapA, th_snapB;
  // The bits pushed into ghA / ghB since the last A != B bundle, kept
  // apart for the bundles a rollback corrected (C) and the rest (N): an
  // obs_ok lookup is explained only while such a bundle is inside the
  // longest history (tg::HIST[4]) of either model.
  uint64_t th_sNA = 1u << 30, th_sNB = 1u << 30;
  uint64_t th_sCA = 1u << 30, th_sCB = 1u << 30;
  uint64_t th_pnA = 0, th_pnB = 0;   // the previous bundle's bits
  std::vector<uint16_t> tsh(size_t(5) * 2 * 2048, 0);
  for (int s = 0; s < 2; s++)
    for (int i = 0; i < 2048; i++) tsh[size_t(s) * 2048 + size_t(i)] = 2;
  auto TS = [&](int t, int s, int i) -> uint16_t& {
    return tsh[(size_t(t) * 2 + size_t(s)) * 2048 + size_t(i & 2047)];
  };
  uint32_t tw_prev = 0;
  int uaon_m[4] = {};   // the use_alt_on_na model, per slot (reset 0)
  int n_tdev = 0;
  // The first 2 of each counted update outcome (gone, stale, alloc_dup),
  // to stderr as TGNOTE: an example per class (PERF-005 Block 2).
  int n_tnote[3] = {};
  int n_rsnote = 0;          // RSNOTE prints, the *_other reasons
  const char* lov = std::getenv("PERF_TH_LAG_OLD");
  const bool th_lag_old = lov && lov[0] == '1';
  // THE RAS CLASSIFICATION (BP-151): observation only. RC_DUMP=n prints
  // the first n returns of each cause to stderr.
  rcls::RasClass rcl;
  if (const char* dv = std::getenv("RC_DUMP")) rcl.dump = std::atoi(dv);
  // THE EVENT LOG (PERF-004, diagnostic only; nothing in a run reads it):
  // PERF_EVLOG=<file> writes one line per event, for finding the first
  // divergence of two runs (A MOVE FROM A TIMING CHANGE):
  //   C k cycle mis idx pos src cls
  //                       an instruction committed: its FTQ index and
  //                       position, pred_src and trace class
  //   W cycle ptr         the watermark presented to the FTQ changed
  //   E cycle ptr full    the eager close of the newest entry, and
  //                       whether the FTQ was full
  //   D cycle k full      a stream-rule branch decided by the record
  //   T cycle k           a trap after branch k, at its take
  //   S cycle idx slot pos p2tk p3tk hold final lcl ttkn thi tmed sum thr
  //     chi cmed          an SC answer at p3 for a conditional slot
  //                       (perf_top sd_*, PERF-004 Phase 5)
  FILE* evlog = nullptr;
  if (const char* ev = std::getenv("PERF_EVLOG")) {
    evlog = std::fopen(ev, "w");
    if (evlog == nullptr) die(std::string("cannot write ") + ev);
  }
  uint32_t ev_wm = 0xffffffffu;
  if (const char* tv = std::getenv("RC_TRACE")) {
    // RC_TRACE=from:to, the RAS events of those cycles on stderr
    rcl.tr_from = std::strtoull(tv, nullptr, 0);
    if (const char* co = std::strchr(tv, ':'))
      rcl.tr_to = std::strtoull(co + 1, nullptr, 0);
  }

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
      if (o + 1 < n && !seq) {
        // PERF-004: the trace leaves the block early by a taken branch to
        // pc itself, the block's predicted successor. A later stage sets
        // the block's end at that branch without changing its successor,
        // so with no redirect (BP-150), and the block at pc is on the
        // path after it. Refused, the block at pc was off the path at p1
        // and its p1 slots were not forced; the realign at p2 put it on
        // the path, with no FTB slot to force there (err_orc_slot_mispred
        // on 7 traces of the PERF-004 baseline). When no later stage moves
        // the end, fetch leaves the path inside the block and the redirect
        // squashes the block at pc.
        if (taken && (nx.pc & VA_MASK) == (pc & VA_MASK)) {
          k = e.k + o + 1;
          osucc_why = 0;
          return true;
        }
        osucc_why = 6;
        return false;
      }
      if (o + 1 == n && tk && !taken) { osucc_why = 7; return false; }
    }
    if ((nx.pc & VA_MASK) != (pc & VA_MASK)) { osucc_why = 8; return false; }
    k = e.k + n;
    osucc_why = 0;
    return true;
  };
  int64_t cyc = 0;
  int n_frdis_log = 0;                 // fetch-rule disagreements printed
  int n_diag_log = 0;                  // STREAMERR and UNSPEC lines printed
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
    uint8_t cls = 0;                  // BP-151: its class, for rd.ty
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
    // BP-151: the named instruction's type (its class by
    // rv::br_type_of), which THE RAS CLASSIFICATION reads. Since BP-153
    // it is also driven on the redirect (redir_type).
    uint8_t ty = rv::BT_NO_BRANCH;
    // PERF-004: the repair follows a PC of a class conflict (supply.h),
    // where fetch follows the image; its RC_UNSPEC form is counted with
    // the conflicts (conflict_unspec_repair), not as err_unspec_repair.
    bool conflict = false;
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
      rd.ty = rv::br_type_of(b->in.cls);
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
        // PERF-005: a slot predecode rewrote (ftq_ifu.sv W1, PRED_NONE)
        // or killed loses its decision; a slot kept as it was keeps it.
        if (!(((top->pc_s_val >> s) & 1) == e.s[s].val &&
              top->pc_s_pos[s] == e.s[s].pos &&
              top->pc_s_src[s] == e.s[s].src &&
              top->pc_s_type[s] == e.s[s].type))
          e.s[s].dv = false;
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
        // PERF-004: on an FTB miss the p1 view stands, and the RAS pops its
        // taken return at p2 and redirects to the pop (BP-154 R2,
        // bp_cluster w_p1ret_redir_p2). That pop is the forced
        // w_ras_pop_addr_p2; its enable came only from the FTB slots above,
        // so these returns were not forced (err_orc_slot_mispred on
        // compress_1, infra_1 and web_11 since BP-154).
        if (e.valid && e.on && (e.pc & VA_MASK) == (top->os_p2_pc & VA_MASK) &&
            !top->rc_ftb_p2)
          for (int s = 0; s < NPS; s++) {
            if (!((top->os_p2_p1_s_val >> s) & 1)) continue;
            uint8_t ty = top->os_p2_p1_s_type[s];
            if (ty != rv::BT_RETURN && ty != rv::BT_RETURN_CALL) continue;
            bool isbr = false, dir = false;
            uint64_t tgt = 0;
            uint8_t cls = 0;
            if (!o_slot(e.k, e.pc, top->os_p2_p1_s_pos[s], isbr, dir, tgt,
                        cls) || !dir)
              continue;
            p2_ten |= uint8_t(1u << s);
            top->orc_p2_tgt[s] = tgt;
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

    // THE STREAM RULE: a pending branch with nothing coming. When the ibuf
    // has been empty for EAGER_IDLE cycles, the fetch record's verdict
    // decides it (decided_by_slot; before PERF-003 the FTQ slot read at
    // the take did), so that the path's last branch, and one whose next
    // block is not yet fetched, do not wait for ever. PERF-004 (TD#206)
    // removed the term "the FTQ is full": with the FTQ full, fetch still
    // translates, fetches and delivers every allocated entry (tb_fe_top
    // ftq_full), so no commit waits on a fetch that waits on commit.
    if (pend != nullptr && top->pd_valid == 0 && idle >= EAGER_IDLE) {
      c.slot_decided++;
      pend->slot_dec = true;
      if (evlog)
        std::fprintf(evlog, "D %" PRId64 " %" PRIu64 " %d\n", cyc, pend->k,
                     int(top->ftq_full));
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
      // (C3): it is not judged, as the stream rule does not judge it. A
      // branch with a trap after it is judged on its own outcome (PERF-004).
      uint64_t judged = b->trap_after ? b->own_next : tnext;
      b->fr_mis = has_next && v.pnext != (judged & VA_MASK);
      b->fr_src = v.src;
      // pred_src comes from the record under either rule (PF-6).
      b->src = v.src;
      b->rsn = classify(fe, v, b->in.cls, b->xp);
      // the first 2 of each *_other reason, the cases no rule names
      if (RSN_SRC[b->rsn] == S_ANY && n_rsnote < 2) {
        n_rsnote++;
        const bool dv = v.slot >= 0 && fe.s[v.slot].dv;
        const Dec dd = dv ? fe.s[v.slot].d : Dec{};
        std::fprintf(stderr, "RSNOTE %s cyc %" PRId64 " k %" PRIu64
                     " pc %" PRIx64 " idx %d pos %d slot %d src %d dv %d"
                     " p2 %d ftb %d pkv %d p1ret %d\n", RSN_NAME[b->rsn],
                     cyc, b->k, b->in.pc, int(b->idx), int(b->pos),
                     v.slot, int(v.src), int(dv), int(dd.p2), int(dd.ftb),
                     int(dd.pkv), int(dd.p1ret));
      }
      if (v.slot >= 0 && fe.s[v.slot].dv) {
        const Dec& d = fe.s[v.slot].d;
        b->dv = true;
        b->d_thit = d.thit;
        b->d_ttk = d.ttk;
        b->d_fsh = d.fsh;
        b->d_fleft = d.fleft;
        b->d_fres = d.fres;
      }
      b->in_slot = v.in_slot;
      b->kind_alias = v.in_slot && v.rq_at_pos &&
                      ((v.rq_type == rv::BT_COND) !=
                       (b->in.cls == cbp::C_COND));
      if (v.beyond) c.fr_beyond++;
      if (b->trap_after) {
        // A TRAP AFTER A BRANCH, under either rule: the verdict on its own
        // outcome is the branch's; the RC_TRAP redirect formed at the take
        // stands, and what fetch gave after the branch is off the trace's
        // path (the handler's), so neither stream check applies.
        b->mis = b->fr_mis;
        logf("VERDICT k %" PRIu64 " mis %d trap after", b->k, int(b->mis));
      } else if (drive) {
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
          rd.unspec = false; rd.ty = rv::br_type_of(b->in.cls);
        } else if (b->nxt_seen && !b->nxt_ok) {
          // Fetch left the path after a branch the record says correct
          // (err_stream): repaired by RC_REPLAY naming the branch.
          if (sup.conflict(b->in.pc) || sup.conflict(tnext))
            c.class_conflict++;
          else
            c.stream_bad++;
          if (n_diag_log < 20) {
            n_diag_log++;
            std::fprintf(stderr, "STREAMERR verdict cyc %" PRId64 " k %"
                         PRIu64 " pc %" PRIx64 " cls %d idx %d pos %d next %"
                         PRIx64 " pnext %" PRIx64 "\n", cyc, b->k, b->in.pc,
                         int(b->in.cls), int(b->idx), int(b->pos), tnext,
                         v.pnext);
          }
          rd.v = true; rd.at = cyc; rd.idx = b->idx; rd.pos = b->pos;
          rd.pc = tnext; rd.self = false; rd.cause = 2; rd.taken = false;
          rd.next_k = b->k + 1; rd.ptr = b->ptr; rd.unspec = false;
          rd.ty = rv::br_type_of(b->in.cls);
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
      // BP-153: the named instruction's resolved type rides with the
      // redirect (ftq_backend_interfaces.md 5, _type), from its class.
      top->redir_type = rd.ty;
      // PERF-005 Phase 3: a backend mispredict's corrected bundle, the
      // rule model's (A): at most one not-taken bit, for the earliest
      // slot before the named position, then the resolved bit
      // (bp_history_decisions.md 3.5; RB_CORR_BITS 2).
      if (rd.cause == 0 && !rd.self) {
        const FRec& fe = frec[rd.idx];
        THb hb;
        for (int s = 0; s < NPS; s++)
          if (fe.s[s].val && fe.s[s].pos < rd.pos) { hb.n = 1; break; }
        if (rd.taken) hb.tkn |= uint8_t(1u << hb.n);
        hb.n++;
        hbA[rd.idx & 63] = hb;
      }
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
    // The eager close waits until the ibuf has been empty for EAGER_IDLE
    // cycles, so that an entry stays nameable by a repair redirect while
    // fetch may still show it was left early. PERF-004 (TD#206) removed
    // the term "or the FTQ is full", a workaround for a fetch stall the
    // RTL does not have (tb_fe_top ftq_full).
    idle = (top->pd_valid == 0) ? idle + 1 : 0;
    if (started && !wrong && !rd.v && top->pd_valid == 0 && !ents.empty() &&
        idle >= EAGER_IDLE) {
      if (evlog && !ents.back().closed)
        std::fprintf(evlog, "E %" PRId64 " %u %d\n", cyc, ents.back().ptr,
                     int(top->ftq_full));
      ents.back().closed = true;
    }
    // The watermark.
    while (!ents.empty() && ents.front().closed &&
           ents.front().n_commit == ents.front().n_taken &&
           ents.front().n_res == 0) {
      wm = ents.front().ptr;
      wm_val = true;
      ents.pop_front();
    }
    if (evlog && wm_val && wm != ev_wm) {
      std::fprintf(evlog, "W %" PRId64 " %u\n", cyc, wm);
      ev_wm = wm;
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
    // THE RAS CLASSIFICATION: this cycle's RAS events, before the edge.
    rcl.observe(top.get(), uint64_t(cyc), redir_now, uint8_t(top->redir_pos),
                rd.ty, rd.cause);

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
      // PERF-004 Phase 5: the SC decisions, to the event log only.
      for (int s = 0; evlog && s < NPS; s++) {
        if (!((top->sd_hit >> s) & 1)) continue;
        std::fprintf(evlog, "S %" PRId64 " %d %d %d %d %d %d %d %d %d %d %d "
                     "%d %d %d %d\n", cyc, int(top->sd_idx), s,
                     int(top->sd_pos[s]), int((top->sd_p2tk >> s) & 1),
                     int((top->sd_p3tk >> s) & 1), int((top->sd_hold >> s) & 1),
                     int((top->sd_final >> s) & 1), int((top->sd_lcl >> s) & 1),
                     int((top->sd_ttkn >> s) & 1), int((top->sd_thi >> s) & 1),
                     int((top->sd_tmed >> s) & 1), int(int16_t(top->sd_sum[s])),
                     int(top->sd_thr), int(int8_t(top->sd_chi)),
                     int(int8_t(top->sd_cmed)));
      }
      // PERF-004 Phase 4: the configuration probes (perf_top cf_*).
      for (int s = 0; s < NPS; s++) {
        if ((top->cf_fp_use >> s) & 1) c.cf_fp++;
        if ((top->cf_sc_hit >> s) & 1) c.cf_sc++;
        if (top->cf_tg_epoch[s] != c.tg_ep_last[s]) c.cf_tg_ep++;
        if (top->cf_it_epoch[s] != c.it_ep_last[s]) c.cf_it_ep++;
        c.tg_ep_last[s] = top->cf_tg_epoch[s];
        c.it_ep_last[s] = top->cf_it_epoch[s];
        for (int t = 0; t < 4; t++)
          if ((top->cf_tg_decay[s] >> t) & 1) c.cf_tg_dec[t]++;
        for (int t = 0; t < 5; t++)
          if ((top->cf_it_decay[s] >> t) & 1) c.cf_it_dec[t]++;
      }
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
      // PERF-005: THE DECISION, this allocation's, at p2 and p3.
      if (top->ew_alloc_val)
        for (int s = 0; s < NPS; s++) dec[top->ew_alloc_idx][s] = Dec{};
      if (top->dp2_val)
        for (int s = 0; s < NPS; s++) {
          Dec& d = dec[top->dp2_idx][s];
          d.p2 = true;
          d.ftb = top->dp2_ftb;
          d.p1ret = top->dp2_p1ret;
          d.cond = (top->dp2_cond >> s) & 1;
          d.lp = (top->dp2_lp >> s) & 1;
          d.fp = (top->dp2_fp >> s) & 1;
          d.trdy = (top->dp2_trdy >> s) & 1;
          d.thit = (top->dp2_thit >> s) & 1;
          d.prm = top->dp2_prm[s];
          d.alt = top->dp2_alt[s];
          d.usep = (top->dp2_usep >> s) & 1;
          d.irdy = (top->dp2_irdy >> s) & 1;
          d.ibid = (top->dp2_ibid >> s) & 1;
          d.ihit = (top->dp2_ihit >> s) & 1;
          d.pkv = (top->dp2_pkv >> s) & 1;
        }
      if (top->dp3_val)
        for (int s = 0; s < NPS; s++) {
          Dec& d = dec[top->dp3_idx][s];
          d.p3 = true;
          d.p3cond = (top->dp3_cond >> s) & 1;
          d.schit = (top->dp3_schit >> s) & 1;
          d.hold = (top->dp3_hold >> s) & 1;
          d.p2tk = (top->dp3_p2tk >> s) & 1;
          d.sctk = (top->dp3_sctk >> s) & 1;
          d.lcl = (top->dp3_lcl >> s) & 1;
          d.chs = top->dp3_chs[s];
        }
      // PERF-005 Phase 2: THE FAST PATH, every p2 read and every update,
      // from cycle 0. The p2 read is checked before this cycle's update
      // is applied: the update writes at this edge, and no p1 read
      // shares a cycle with an update (pred_grant_p1).
      auto fdev = [&](const char* what, uint32_t key, int i, int got,
                      int want) {
        if (n_fdev >= 20) return;
        n_fdev++;
        std::fprintf(stderr, "FPDEV %s cyc %" PRId64 " set %u way %u fld %d"
                     " got %d want %d\n", what, cyc, key >> 2, key & 3, i,
                     got, want);
      };
      auto sat = [](uint8_t cf) { return cf == 0 || cf == 7; };
      if (top->fq_val) {
        uint32_t key = (uint32_t(top->fq_set) << 2) | top->fq_way;
        if (key >= fsh.size()) die("FTB set index beyond the shadow");
        const FShE& E = fsh[key];
        for (int i = 0; i < 2; i++) {
          bool bv = (top->fq_bv >> i) & 1;
          bool fp = (top->fq_fp >> i) & 1;
          int sh = -1;
          if (bv) {
            c.fp_rd++;
            for (int j = 0; j < 2; j++)
              if (E.w && E.f[j].v && E.f[j].pos == top->fq_pos[i]) sh = j;
            if (sh < 0) {
              c.fp_chk_nosh++;
              fdev("p2_nosh", key, i, top->fq_pos[i], -1);
            } else if (E.f[sh].conf != top->fq_conf[i]) {
              c.fp_chk_rd++;
              fdev("p2_conf", key, i, top->fq_conf[i], E.f[sh].conf);
            }
          }
          // 4.1: valid, the field valid, the enable, saturated (the
          // shadow's conf, the RTL's when the shadow lacks the field).
          uint8_t cf = sh >= 0 ? E.f[sh].conf : uint8_t(top->fq_conf[i]);
          bool want = bv && top->fq_en && sat(cf);
          if (fp != want) {
            c.fp_chk_41++;
            fdev("p2_41", key, i, fp, want);
          }
          if (fp) c.fp_fire++;
          if (i < NPS && top->dp2_val) {
            Dec& d = dec[top->dp2_idx][i];
            d.ttk = (top->dp2_ttk >> i) & 1;
            d.fsh = bv && sh >= 0;
            if (d.fsh) { d.fres = E.f[sh].res; d.fleft = E.f[sh].left; }
            bool cnd = (top->dp2_cond >> i) & 1;
            bool lp = (top->dp2_lp >> i) & 1;
            bool use = (top->dp2_fp >> i) & 1;
            if (use != (cnd && fp && !lp)) {
              c.fp_chk_use++;
              fdev("p2_use", key, i, use, cnd && fp && !lp);
            }
          }
        }
      } else {
        if (top->fq_fp != 0) {
          c.fp_chk_41++;
          fdev("p2_41_noval", 0, -1, top->fq_fp, 0);
        }
        if (top->dp2_val)
          for (int s = 0; s < NPS; s++) {
            dec[top->dp2_idx][s].ttk = (top->dp2_ttk >> s) & 1;
            if ((top->dp2_fp >> s) & 1) {
              c.fp_chk_use++;
              fdev("p2_use_noval", 0, s, 1, 0);
            }
          }
      }
      if (top->fu_val) {
        uint32_t key = (uint32_t(top->fu_set) << 2) | top->fu_way;
        if (key >= fsh.size()) die("FTB set index beyond the shadow");
        FShE& E = fsh[key];
        FShE O = E;
        // The entry the update builds on: the old one on a hit, else
        // empty (ftb_cntrl upd_cur).
        if (top->fu_hit && !O.w) {
          c.fu_chk_nosh++;
          fdev("u_hit_nosh", key, -1, 1, 0);
        }
        if (!top->fu_hit) O = FShE{};
        bool isb = top->fu_isbr && !top->fu_past;
        int oj = -1;
        for (int j = 0; j < 2; j++)
          if (O.f[j].v && O.f[j].pos == top->fu_pos) oj = j;
        uint8_t want = 0;
        if (top->fu_isbr) c.fu_br++;
        if (top->fu_isbr && top->fu_past) c.fu_past++;
        if (isb) {
          if (bool(top->fu_inpl) != (oj >= 0)) {
            c.fu_chk_nosh++;
            fdev("u_inplace", key, -1, top->fu_inpl, oj >= 0);
          }
          if (oj >= 0) {
            c.fu_inpl++;
            if (top->fu_oconf != O.f[oj].conf) {
              c.fu_chk_rd++;
              fdev("u_rd", key, oj, top->fu_oconf, O.f[oj].conf);
            }
            uint8_t o = O.f[oj].conf;
            // 3.2: the saturating bimodal step toward the outcome.
            want = top->fu_tkn ? (o == 7 ? 7 : o + 1) : (o == 0 ? 0 : o - 1);
          } else {
            c.fu_alloc++;
            want = top->fu_tkn ? 4 : 3;      // 7: FTB_CONF_INIT_TKN / _NTK
          }
        }
        FShE N;
        N.w = true;
        bool wrote = false;
        for (int i = 0; i < 2; i++) {
          if (!((top->fu_nv >> i) & 1)) continue;
          FShF& f = N.f[i];
          f.v = true;
          f.pos = top->fu_npos[i];
          f.conf = top->fu_nconf[i];
          if (isb && f.pos == top->fu_pos) {
            wrote = true;
            if (f.conf != want) {
              c.fu_chk_wr++;
              fdev("u_wr", key, i, f.conf, want);
            }
            if (oj >= 0) {
              bool l = sat(O.f[oj].conf) && !sat(f.conf);
              if (l) c.fu_leave++;
              if (!sat(O.f[oj].conf) && sat(f.conf)) c.fu_resat++;
              f.res = l ? 0 : O.f[oj].res + 1;
              f.left = l ? true : O.f[oj].left;
            }
          } else {
            int k = -1;
            for (int j = 0; j < 2; j++)
              if (O.f[j].v && O.f[j].pos == f.pos) k = j;
            if (k < 0 || O.f[k].conf != f.conf) {
              c.fu_chk_keep++;
              fdev("u_keep", key, i, f.conf, k < 0 ? -1 : O.f[k].conf);
            }
            if (k >= 0) { f.res = O.f[k].res; f.left = O.f[k].left; }
          }
        }
        if (isb && !wrote) c.fu_split++;
        E = N;
      }
      for (int ch = 0; ch < NRP; ch++) {
        if ((top->fs_acc >> ch) & 1) c.fs_acc++;
        if ((top->fs_drop >> ch) & 1) c.fs_drop++;
      }
      // PERF-005 Phase 3: THE TAGE CHECKS, from cycle 0.
      auto tdev = [&](const char* what, int t, int s, uint64_t got,
                      uint64_t want, uint64_t a) {
        if (n_tdev >= 20) return;
        n_tdev++;
        std::fprintf(stderr, "TGDEV %s cyc %" PRId64 " t %d s %d got %" PRIx64
                     " want %" PRIx64 " at %" PRIx64 "\n", what, cyc, t, s,
                     got, want, a);
      };
      // The lookup.
      if (top->tl_val & 1) {
        TLk& L = tlk[top->tl_bid[0] & 63];
        L.v = true;
        L.q = top->tl_q;
        L.rb = top->tl_rb;
        L.cyc = cyc;
        L.pc = uint64_t(top->tl_pc[0]) & VA_MASK;
        for (int t = 0; t < 5; t++)
          for (int s = 0; s < NPS; s++) {
            L.idx[t][s] = top->tl_idx[t * NPS + s];
            L.tag[t][s] = top->tl_tag[t * NPS + s];
          }
        for (int k = 0; k < 12; k++) L.fh[k] = top->tl_fh[k];
      }
      // The observed bundles: a rollback outranks the p1 write
      // (bp_history_decisions.md 4); a corrected one rewrites the entry.
      if (top->hr_val)
        logf("HROLL idx %d corr %d n %d tkn %d", int(top->hr_idx),
             int(top->hr_corr), int(top->hr_n), int(top->hr_tkn));
      else if (top->hw_val)
        logf("HWRITE idx %d n %d tkn %d", int(top->hw_idx), int(top->hw_n),
             int(top->hw_tkn));
      if (top->hr_val || top->hw_val)
        logf("HPTR ptr %d win %04x (as registered, before this cycle's "
             "write)", int(top->hp_ptr), unsigned(top->hp_win));
      if (top->hr_val) {
        if (top->hr_corr)
          hbB[top->hr_idx & 63] =
              THb{top->hr_n, top->hr_tkn, int64_t(cyc), true};
      } else if (top->hw_val) {
        hbB[top->hw_idx & 63] =
            THb{top->hw_n, top->hw_tkn, int64_t(cyc), false};
      }
      // The p1 read against the shadow.
      for (int s = 0; s < NPS; s++) {
        if (!((top->tp_val >> s) & 1)) continue;
        for (int t = 0; t < 5; t++) {
          int k = t * NPS + s;
          c.tr_n++;
          if ((tw_prev >> k) & 1) { c.tr_coll++; continue; }
          uint16_t e = TS(t, s, top->tp_idx[k]);
          bool bad;
          if (t == 0) {
            // tage.sv 208-209: T0's cntrl bits are {5'b0, ctr[1:0], 1'b1}.
            bad = ((top->tp_cb[k] >> 1) & 3) != (e & 3) ||
                  !(top->tp_cb[k] & 1);
          } else {
            bool hit = (e & 1) && ((e >> 8) & 0xff) == (top->tp_tag[k] & 0xff);
            bad = hit != bool((top->tp_hit >> k) & 1) ||
                  (top->tp_cb[k] & 0xff) != (e & 0xff);
          }
          if (bad) {
            c.tr_bad++;
            tdev("p1_read", t, s, top->tp_cb[k], e, top->tp_idx[k]);
          }
        }
      }
      // The use_alt_on_na counter of each slot against its re-derivation
      // (tage_cntrl_uaon_update_rules.md 75-77, 138): with both providers
      // tagged and the final provider counter weak (011 or 100: the
      // primary's when it was used, else the alternate's), INC when the
      // primary was wrong and the alternate right, DEC the reverse, 4 bits
      // saturating. The registered value is compared before this cycle's
      // update is applied to the model.
      for (int s = 0; s < NPS; s++) {
        if (int(top->tu_uaon[s]) != uaon_m[s]) {
          c.tu_chk_uaon++;
          if (c.tu_chk_uaon <= 20)
            std::fprintf(stderr, "TUAON cyc %" PRIu64 " slot %d rtl %d "
                         "model %d\n", uint64_t(cyc), s,
                         int(top->tu_uaon[s]), uaon_m[s]);
          uaon_m[s] = int(top->tu_uaon[s]);   // resync: count each once
        }
        if (!((top->tu_val >> s) & 1)) continue;
        int pc_ = top->tu_pcmp[s], ac = top->tu_acmp[s];
        if (pc_ == 0 || ac == 0) continue;
        bool up = (top->tu_up >> s) & 1, res = (top->tu_res >> s) & 1;
        int post = up ? int(top->tu_pctr[s]) : int(top->tu_actr[s]);
        if (post != 3 && post != 4) continue;
        bool pok = (((top->tu_ptk >> s) & 1) != 0) == res;
        bool aok = (((top->tu_atk >> s) & 1) != 0) == res;
        if (!pok && aok && uaon_m[s] < 15) uaon_m[s]++;
        else if (pok && !aok && uaon_m[s] > 0) uaon_m[s]--;
      }
      // The update, re-derived from its probed state (the metadata) by
      // tage_cntrl_ctr_update_rules.md, _use_update_rules.md and
      // _alloc_rules.md, against the RAM writes of this cycle.
      for (int s = 0; s < NPS; s++) {
        if (!((top->tu_val >> s) & 1)) continue;
        c.tu_n++;
        int pc_ = top->tu_pcmp[s], ac = top->tu_acmp[s], cc = top->tu_ccmp[s];
        uint16_t pi = top->tu_pidx[s] & 2047, ai = top->tu_aidx[s] & 2047;
        uint16_t ci = top->tu_cidx[s] & 2047;
        int pct = top->tu_pctr[s], act = top->tu_actr[s];
        int pu = top->tu_puse[s], au = top->tu_ause[s];
        bool ptk = (top->tu_ptk >> s) & 1, atk = (top->tu_atk >> s) & 1;
        bool up = (top->tu_up >> s) & 1, res = (top->tu_res >> s) & 1;
        bool mis = (top->tu_mis >> s) & 1;
        int ep = top->tu_ep[s];
        if (mis) c.tu_mis++;
        bool both0 = pc_ == 0 && ac == 0, diff = ptk != atk;
        bool pok = ptk == res, aok = atk == res;
        auto st3 = [](int v, bool tk) {
          return tk ? (v == 7 ? 7 : v + 1) : (v == 0 ? 0 : v - 1);
        };
        auto st2 = [](int v, bool tk) {
          v &= 3;
          return tk ? (v == 3 ? 3 : v + 1) : (v == 0 ? 0 : v - 1);
        };
        // The expected write of each table: enable, address, the fields
        // written (mask) and their value.
        bool xw[5] = {};
        uint16_t xa[5] = {}, xm[5] = {}, xv[5] = {};
        auto put = [&](int t, uint16_t a, uint16_t m, uint16_t v) {
          if (xw[t] && xa[t] != a) a = 0xffff;        // two addresses
          xw[t] = true;
          xa[t] = a;
          xm[t] |= m;
          xv[t] = uint16_t((xv[t] & ~m) | (v & m));
        };
        const uint16_t MC = 0x000e, MU = 0x0030, ME = 0x00c0;
        if (both0) {
          c.tu_rows[3]++;
          put(0, pi, 0x3, uint16_t(st2(pct, res)));        // rows 13a-d
        } else {
          c.tu_rows[up ? 0 : (ac ? 1 : 2)]++;
          if (pc_ && (up || (diff && pok)))
            put(pc_, pi, MC, uint16_t(st3(pct, res) << 1));
          if (!ac && !up)
            put(0, ai, 0x3, uint16_t(st2(act, res)));      // rows 19.x
          if (ac && (!up || (diff && aok)))
            put(ac, ai, MC, uint16_t(st3(act, res) << 1));
          if (diff) {                                       // Table 7
            int uc = up ? pc_ : ac;
            uint16_t ui = up ? pi : ai;
            int u = up ? pu : au;
            int nu = !mis ? (u == 3 ? 3 : u + 1) : (u == 0 ? 0 : u - 1);
            if (uc)
              put(uc, ui, MU | ME, uint16_t((nu << 4) | (ep << 6)));
          }
        }
        if (mis) {
          if (pc_ >= 4) c.tu_alc_long++;
          else if (cc == 0) c.tu_alc_use++;
          else {
            // PERF-005 R4: the new entry's CTR is weak toward the
            // resolved direction, 100 taken, 011 not taken (it was 100
            // for both; tage_cntrl_alloc_rules.md).
            put(cc, ci, 0xffff, uint16_t(((top->tu_ctag[s] & 0xff) << 8) |
                                         (ep << 6) | ((res ? 4 : 3) << 1) |
                                         1));
          }
        }
        bool any = false;
        for (int t = 0; t < 5; t++) {
          int k = t * NPS + s;
          bool ow = (top->tw_we >> k) & 1;
          uint16_t om = uint16_t(~top->tw_bweb[k]);
          if (t == 0) om &= 3;
          if (ow != xw[t]) {
            c.tu_chk_we++; any = true;
            tdev("u_we", t, s, ow, xw[t], top->tw_addr[k]);
            continue;
          }
          if (!ow) continue;
          if ((top->tw_addr[k] & 2047) != xa[t]) {
            c.tu_chk_addr++; any = true;
            tdev("u_addr", t, s, top->tw_addr[k], xa[t], 0);
            continue;
          }
          if (om != xm[t] || (top->tw_din[k] & om) != (xv[t] & xm[t])) {
            any = true;
            if (xm[t] == 0xffff) c.tu_chk_alc++;
            else if (xm[t] & (MU | ME)) c.tu_chk_use++;
            else c.tu_chk_ctr++;
            tdev("u_field", t, s, (uint64_t(om) << 16) | top->tw_din[k],
                 (uint64_t(xm[t]) << 16) | xv[t], xa[t]);
          }
        }
        if (any) c.tu_chk++;
        // The entry trained is the one the prediction read: the lookup's
        // tag, still valid; and its counter as the metadata has it.
        const TLk& L = tlk[top->tu_bid[s] & 63];
        // An example of each class: the class, the update's cycle, table,
        // slot and index, the lookup's PC and cycle, the tag and CTR the
        // prediction read and the entry as it now stands.
        auto tnote = [&](int k, const char* what, int t, uint16_t i,
                         uint32_t rtag, int rctr, uint16_t e) {
          if (n_tnote[k] >= 2) return;
          n_tnote[k]++;
          std::fprintf(stderr, "TGNOTE %s cyc %" PRId64 " t %d s %d idx %x "
                       "lk_pc %" PRIx64 " lk_cyc %" PRId64 " read tag %x "
                       "ctr %d now %04x\n", what, cyc, t, s, i, L.pc, L.cyc,
                       rtag, rctr, e);
        };
        if (pc_ && xw[pc_] && (xm[pc_] & MC)) {
          uint16_t e = TS(pc_, s, pi);
          if (!(e & 1) || ((e >> 8) & 0xff) != (L.tag[pc_][s] & 0xff)) {
            c.tu_gone_p++;
            tnote(0, "gone_prm", pc_, pi, L.tag[pc_][s] & 0xff, pct, e);
          } else if (((e >> 1) & 7) != pct) {
            c.tu_stale_p++;
            tnote(1, "stale_prm", pc_, pi, L.tag[pc_][s] & 0xff, pct, e);
          }
        }
        if (ac && xw[ac] && (xm[ac] & MC)) {
          uint16_t e = TS(ac, s, ai);
          if (!(e & 1) || ((e >> 8) & 0xff) != (L.tag[ac][s] & 0xff))
            c.tu_gone_a++;
          else if (((e >> 1) & 7) != act)
            c.tu_stale_a++;
        }
        if (mis && pc_ < 4 && cc != 0) {
          bool ow = (top->tw_we >> (cc * NPS + s)) & 1;
          if (!ow) c.tu_alc_other++;
          else {
            c.tu_alc++;
            if (!res) c.tu_alc_ntk++;
            uint16_t e = TS(cc, s, ci);
            if ((e & 1) && ((e >> 8) & 0xff) == (top->tu_ctag[s] & 0xff)) {
              c.tu_alc_dup++;
              tnote(2, "alloc_dup", cc, ci, top->tu_ctag[s] & 0xff, -1, e);
            }
          }
        }
      }
      // THE SC, re-derived from the probed counters, TAGE's extended
      // counter and confidence, the threshold and the choosers (sc_cntrl
      // sc_decisions.md 9), and at the update from the metadata (10).
      if (top->sd_thr > c.sc_thr_max) c.sc_thr_max = top->sd_thr;
      for (int s = 0; s < NPS; s++) {
        if (!((top->sd_hit >> s) & 1)) continue;
        c.sp_n++;
        int sum = int(int8_t(top->sd_ext[s]));
        for (int t = 0; t < 5; t++)
          sum += 2 * int(int8_t(top->sd_ctr[t * NPS + s])) + 1;
        int s10 = ((sum + 512) & 1023) - 512;
        if (s10 != int(int16_t(top->sd_sum[s]))) {
          c.sp_chk_sum++;
          tdev("sc_sum", 0, s, uint64_t(int16_t(top->sd_sum[s])),
               uint64_t(s10), 0);
        }
        bool lcl = s10 >= 0;
        int ab = s10 < 0 ? -s10 : s10;
        int thr = top->sd_thr;
        bool vlo = ab < (thr >> 1), vvlo = ab < (thr >> 2);
        bool ttk = (top->sd_ttkn >> s) & 1, thi = (top->sd_thi >> s) & 1;
        bool tmed = (top->sd_tmed >> s) & 1;
        bool fin, ovr;
        int chs;
        if (lcl == ttk) { fin = lcl; ovr = false; chs = 0; }
        else if (thi && vlo) {
          bool sc = int8_t(top->sd_chi) >= 0;
          fin = sc ? lcl : ttk; ovr = sc; chs = 2;
          if (sc) c.sp_hi_sc++; else c.sp_hi_tg++;
        } else if (tmed && vvlo) {
          bool sc = int8_t(top->sd_cmed) >= 0;
          fin = sc ? lcl : ttk; ovr = sc; chs = 1;
          if (sc) c.sp_med_sc++; else c.sp_med_tg++;
        } else { fin = lcl; ovr = true; chs = 0; }
        if (fin != bool((top->sd_final >> s) & 1) ||
            lcl != bool((top->sd_lcl >> s) & 1) ||
            ovr != bool((top->sd_ovr >> s) & 1) || chs != top->sd_chs[s]) {
          c.sp_chk_dec++;
          tdev("sc_dec", 0, s, (top->sd_final >> s) & 1, fin, uint64_t(s10));
        }
      }
      {
        auto satc = [](int v, int d, int lo, int hi) {
          return (v == lo && d < 0) || (v == hi && d > 0) ? v : v + d;
        };
        int thr = top->su_thr, tc = int(int8_t(top->su_tc));
        int chi = int(int8_t(top->sd_chi)), cmed = int(int8_t(top->sd_cmed));
        int w = -1;
        for (int s = NPS - 1; s >= 0; s--)
          if ((top->su_val >> s) & 1) w = s;
        for (int s = 0; s < NPS; s++) {
          if (!((top->su_val >> s) & 1)) continue;
          c.su_n++;
          bool res = (top->su_res >> s) & 1;
          bool wrong = bool((top->su_lcl >> s) & 1) != res;
          bool lo = top->su_abs[s] < thr;
          bool du = wrong || lo;
          if (du != bool((top->su_wr >> s) & 1)) {
            c.su_chk_wr++;
            tdev("sc_upd_wr", 0, s, (top->su_wr >> s) & 1, du, 0);
          }
          for (int t = 0; t < 5; t++) {
            int o = int(int8_t(top->su_ctr[t * NPS + s]));
            int x = satc(o, res ? 1 : -1, -32, 31);
            if (x != int(int8_t(top->su_wd[t * NPS + s]))) {
              c.su_chk_wd++;
              tdev("sc_upd_wd", t, s, uint64_t(int8_t(top->su_wd[t * NPS + s])),
                   uint64_t(x), 0);
            }
          }
        }
        if (w >= 0) {
          bool res = (top->su_res >> w) & 1;
          bool wrong = bool((top->su_lcl >> w) & 1) != res;
          bool lo = top->su_abs[w] < thr;
          int ti = wrong ? satc(tc, 1, -64, 63) : lo ? satc(tc, -1, -64, 63)
                                                     : tc;
          int tcd = ti, thd = thr;
          if (ti == 63) { tcd = 0; thd = (thr == 0 /*THR_MAX_U*/) ? thr
                                                                  : thr + 1; }
          else if (ti == -64) { tcd = 0; thd = thr == 1 ? thr : thr - 1; }
          thd &= 1023;
          // PERF-005 R2: the chooser matches SC's own prediction (it was
          // the final one, su_fin; sc_decisions.md 10).
          bool scm = bool((top->su_lcl >> w) & 1) == res;
          bool tgm = bool((top->su_ttk >> w) & 1) == res;
          int nchi = chi, ncmed = cmed;
          if (top->su_chs[w] == 2) {
            if (scm) nchi = satc(chi, 1, -32, 31);
            else if (tgm) nchi = satc(chi, -1, -32, 31);
          } else if (top->su_chs[w] == 1) {
            if (scm) ncmed = satc(cmed, 1, -32, 31);
            else if (tgm) ncmed = satc(cmed, -1, -32, 31);
          }
          if (tcd != int(int8_t(top->su_tc_d)) || thd != top->su_thr_d ||
              nchi != int(int8_t(top->su_chi_d)) ||
              ncmed != int(int8_t(top->su_cmed_d)) || top->su_wsel != w) {
            c.su_chk_glob++;
            tdev("sc_upd_glob", 0, w, (uint64_t(top->su_thr_d) << 8) |
                 uint8_t(top->su_tc_d), (uint64_t(thd) << 8) | uint8_t(tcd), 0);
          }
        }
      }
      // The RAM writes, into the shadow, after the checks of this cycle.
      tw_prev = 0;
      for (int t = 0; t < 5; t++)
        for (int s = 0; s < NPS; s++) {
          int k = t * NPS + s;
          if (!((top->tw_we >> k) & 1)) continue;
          tw_prev |= 1u << k;
          uint16_t m = uint16_t(~top->tw_bweb[k]);
          if (t == 0) m &= 3;
          uint16_t& e = TS(t, s, top->tw_addr[k]);
          e = uint16_t((e & ~m) | (top->tw_din[k] & m));
        }
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
          e.s[s].rq_val = e.s[s].val;
          e.s[s].rq_pos = e.s[s].pos;
          e.s[s].rq_type = e.s[s].type;
          e.s[s].d = dec[top->fr_idx][s];
          e.s[s].dv = true;
        }
        // PERF-005 Phase 3: the rule model's bundle (A), the request's
        // slots in order up to and including the first taken one
        // (bp_history_decisions.md 3.2, 3.5 D16; bp_cluster.sv p1 write).
        {
          THb hb;
          for (int s = 0; s < NPS && hb.n < NPS; s++) {
            if (!e.s[s].val) continue;
            if (e.s[s].taken) hb.tkn |= uint8_t(1u << hb.n);
            hb.n++;
            if (e.s[s].taken) break;
          }
          hbA[top->fr_idx & 63] = hb;
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
        if (r->in.cls == cbp::C_COND) c.res_cond++;   // PERF-005 Phase 2
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
            rd.ty = rv::br_type_of(last->in.cls);
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
            if (n_diag_log < 20) {
              n_diag_log++;
              std::fprintf(stderr, "STREAMERR fetch cyc %" PRId64 " tp %"
                           PRIu64 " pc %" PRIx64 " exp %" PRIx64 " last pc %"
                           PRIx64 " cls %d v %d conflict %d freed %d idx %d "
                           "pos %d ptr %u wm %u\n", cyc, tp, pc, in.pc,
                           lc.pc, int(lc.cls), int(lc.v),
                           int(lc.v && sup.conflict(lc.pc)), int(freed),
                           int(lc.idx), int(lc.pos), lc.ptr, wm);
            }
            if (lc.v && !freed) {
              rd.v = true; rd.at = hold_c; rd.idx = lc.idx;
              rd.pos = lc.pos; rd.pc = in.pc; rd.self = false;
              rd.cause = 2; rd.taken = false; rd.next_k = tp;
              rd.ptr = lc.ptr; rd.unspec = false;
              rd.ty = rv::br_type_of(lc.cls);
            } else {
              rd.v = true; rd.at = hold_c; rd.pc = in.pc; rd.cause = 3;
              rd.unspec = true; rd.next_k = tp;
              rd.conflict = lc.v && sup.conflict(lc.pc);
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
        if (in.cls == cbp::C_CALL_DIR || in.cls == cbp::C_CALL_IND ||
            in.cls == cbp::C_RET) {
          r.rco = rcl.cur(idx);
          if (in.cls != cbp::C_RET) rcl.path_call(r.rco.inst, r.pos, tp);
          else rcl.path_ret(r.rco.inst, tp);
        }
        if (sup.conflict(in.pc)) rcl.path_conflict(rcl.cur(idx).inst);
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
          // A TRAP AFTER A BRANCH (PERF-004): the trace's next PC is not
          // the branch's own outcome.
          r.own_next = (in.taken ? in.target : in.pc + 4) & VA_MASK;
          r.trap_after = tp + 1 < path_len &&
                         (next_pc & VA_MASK) != r.own_next;
        }
        // A deque keeps references across push_back, and an entry leaves
        // only by commit, after its resolution: res_at's pointer stays
        // valid.
        rob.push_back(r);
        Ro* rp = &rob.back();
        bool pending = false;
        if (rp->is_br && (drive || rp->trap_after)) {
          // THE FETCH RULE: decided in the resolve cycle from the record,
          // with no wait for the next slot. A branch with a trap after it
          // is decided so under either rule: the slot fetch delivers after
          // it is not the trace's (PERF-004).
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
        lc.cls = in.cls;
        expect_next = next_pc;
        last_take_c = cyc;
        logf("TAKE k %" PRIu64 " pc %" PRIx64 " cls %d idx %d pos %d ptr %u "
             "br %d mis %d src %d next %" PRIx64 " res %" PRId64 " cmt %"
             PRId64, tp, in.pc, in.cls, idx, r.pos, ptr, r.is_br, r.mis,
             r.src, next_pc, r.res_c, r.commit_c);
        tp++;
        if (pending) {
          pend = rp;
        } else if (rp->is_br && rp->trap_after) {
          // A TRAP AFTER A BRANCH (PERF-004; PF-18, Jeff session-086): "the
          // branch is judged on its own outcome, and the trap is a separate
          // RC_TRAP redirect, as for a non-branch." The redirect names the
          // branch, in its resolve cycle, self clear, to the trace's next
          // PC; it carries the branch's type and direction, as every
          // redirect carries the named instruction's (BP-153). What fetch
          // takes after the branch is off the trace's path. Before PERF-004
          // the branch was judged against the trace's next PC, so its
          // prediction counted as mispredicted (mispred_trap_after) and the
          // RC_MISPREDICT redirect went to the handler.
          c.traps++;
          c.br_traps++;
          if (evlog)
            std::fprintf(evlog, "T %" PRId64 " %" PRIu64 "\n", cyc, rp->k);
          wrong = true;
          rd.v = true; rd.at = rp->res_c; rd.idx = idx; rd.pos = rp->pos;
          rd.pc = next_pc; rd.self = false; rd.cause = 1;
          rd.taken = in.taken; rd.next_k = tp; rd.ptr = ptr;
          rd.unspec = false; rd.ty = rv::br_type_of(in.cls);
        } else if (rp->is_br && rp->mis) {
          // The redirect, in its resolve cycle; what follows is wrong.
          wrong = true;
          pred_mis_last = true;
          rd.v = true; rd.at = rp->res_c; rd.idx = idx; rd.pos = rp->pos;
          rd.pc = next_pc; rd.self = false; rd.cause = 0;
          rd.taken = in.taken; rd.next_k = tp; rd.ptr = ptr;
          rd.unspec = false; rd.ty = rv::br_type_of(in.cls);
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
          rd.ty = rv::BT_NO_BRANCH;
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
        if (rd.conflict) c.conflict_unspec++;
        else c.unspec_repair++;
        rd.conflict = false;
        if (n_diag_log < 20) {
          n_diag_log++;
          std::fprintf(stderr, "UNSPEC cyc %" PRId64 " pc %" PRIx64 " k %"
                       PRIu64 " wm %u\n", cyc, rd.pc, rd.next_k, wm);
        }
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
      // PERF-005 Phase 3: THE HISTORY CHECK, at the first instruction of
      // each committed entry: the previous entry's bundle joins the
      // committed-path history, and this entry's lookup is recomputed
      // from it by tage_table_hash_rules.md.
      if (int64_t(r.ptr) != th_last) {
        // The stage model (bp_arb_spec.md 3.1-3.2, fe_decisions.md 1):
        // a block's p0 lookup reads the folds as registered, and a block
        // writes its bundle at p1 (bp_cluster.sv 954-978), so the block
        // just before it is in the lookup's history only when its bundle
        // was taken in an earlier cycle than the lookup. lagA/lagB are
        // the histories without it; ghA/ghB with it.
        bool have_prev = th_last >= 0;
        int64_t prev_wc = -1;
        TGh lagA = ghA, lagB = ghB;
        if (have_prev) {
          const THb& a = th_snapA;
          const THb& b = th_snapB;
          prev_wc = b.wc;
          for (int i = 0; i < a.n; i++) ghA.push((a.tkn >> i) & 1);
          for (int i = 0; i < b.n; i++) ghB.push((b.tkn >> i) & 1);
          th_sNA += a.n; th_sNB += b.n; th_sCA += a.n; th_sCB += b.n;
          th_pnA = a.n; th_pnB = b.n;
          if (a.n != b.n || (a.tkn & ((1u << a.n) - 1)) !=
                                (b.tkn & ((1u << b.n) - 1))) {
            c.th_hb_ab++;
            if (b.corr) th_sCA = th_sCB = 0;
            else th_sNA = th_sNB = 0;
            // p1only: the history holds the p1 write, never corrected,
            // and the request (A) has more branches: the p2/p3 view
            // added a branch without a redirect (bp_history_decisions.md
            // 3.5 corrects only on a redirect).
            bool p1only = !b.corr && b.n < a.n;
            if (p1only) c.th_ab_p1only++;
            else if (b.corr) c.th_ab_corr++;
            else c.th_ab_other++;
            // the first 20 that are not p1only (the p1only class is
            // defined above; these are the cases still to be defined)
            if (!p1only && !b.corr && c.th_ab_other <= 20) {
              const FRec& fe = frec[th_last_idx];
              std::fprintf(stderr, "THAB k %" PRIu64 " idx %d start %" PRIx64
                           " A %d/%x B %d/%x Bcorr %d wc %" PRId64
                           " s0 %d/%d/%d ty %d src %d s1 %d/%d/%d ty %d src %d"
                           " seq-req %d\n", r.k,
                           int(th_last_idx), fe.start_pc, int(a.n),
                           unsigned(a.tkn), int(b.n), unsigned(b.tkn),
                           int(b.corr), b.wc,
                           int(fe.s[0].val), int(fe.s[0].taken),
                           int(fe.s[0].pos), int(fe.s[0].type),
                           int(fe.s[0].src),
                           int(NPS > 1 && fe.s[1].val),
                           int(NPS > 1 && fe.s[1].taken),
                           int(NPS > 1 ? fe.s[1].pos : 0),
                           int(NPS > 1 ? fe.s[1].type : 0),
                           int(NPS > 1 ? fe.s[1].src : 0),
                           int(fe.seq - fe.req_seq));
            }
          }
        }
        th_last = int64_t(r.ptr);
        th_last_idx = r.idx & 63;
        c.th_n++;
        const TLk& L = tlk[th_last_idx];
        // PERF-005 R6: the p0 lookup reads the folds with the bundle
        // written in its own cycle (the bypass), so a block written in
        // the lookup's cycle is in it (it was prev_wc < L.cyc).
        // PERF_TH_LAG_OLD=1 keeps the model before R6 (prev_wc < L.cyc),
        // for a harness built on an RTL without the bypass.
        bool incl = !have_prev ||
                    (th_lag_old ? prev_wc < L.cyc : prev_wc <= L.cyc);
        if (L.v && !incl) c.th_lag++;
        const TGh& gA = incl ? ghA : lagA;
        const TGh& gB = incl ? ghB : lagB;
        if (!L.v) {
          c.th_nolk++;
        } else {
          uint64_t pc = frec[th_last_idx].start_pc & VA_MASK;
          bool bad = false, badB = false;
          unsigned mA = 0, mB = 0;   // the tables that deviate, A and B
          if (L.pc != pc) { c.th_pc++; bad = true; badB = true; }
          for (int t = 0; t < 5; t++) {
            uint32_t fa[3] = {}, fb[3] = {};
            uint32_t xt = 0, yt = 0;
            if (t != 0) {
              tg::folds(t, gA, fa);
              tg::folds(t, gB, fb);
              xt = tg::tag(t, pc, fa);
              yt = tg::tag(t, pc, fb);
              if (L.fh[(t - 1) * 3] != fa[0] ||
                  L.fh[(t - 1) * 3 + 1] != fa[1] ||
                  L.fh[(t - 1) * 3 + 2] != fa[2])
                c.th_fold[t]++;
            }
            uint32_t xi = tg::index(t, pc, fa), yi = tg::index(t, pc, fb);
            for (int s = 0; s < NPS; s++) {
              bool ia = L.idx[t][s] != xi, ta = t && L.tag[t][s] != xt;
              bool ib = L.idx[t][s] != yi, tb = t && L.tag[t][s] != yt;
              if (ia) c.th_idx[t]++;
              if (ta) c.th_tag[t]++;
              if (ib) c.th_idxB[t]++;
              if (tb) c.th_tagB[t]++;
              if (ia || ta) { bad = true; mA |= 1u << t; }
              if (ib || tb) { badB = true; mB |= 1u << t; }
            }
          }
          if (bad) {
            c.th_bad++;
            if (L.q) c.th_bad_q++;
            else if (L.rb) {
              c.th_bad_rb++;
              // the part with an uncorrected A != B bundle in its window
              // (it would mismatch outside a rollback cycle too)
              const uint64_t H = uint64_t(tg::HIST[4]);
              if (th_sNA < H + (incl ? 0 : th_pnA) ||
                  th_sNB < H + (incl ? 0 : th_pnB))
                c.th_bad_rb_n++;
            } else if (!badB) {
              c.th_bad_b++;
              // a lookup that lags reads the window without the previous
              // bundle, whose bits the counts already hold
              const uint64_t H = uint64_t(tg::HIST[4]);
              const uint64_t HA = H + (incl ? 0 : th_pnA);
              const uint64_t HB = H + (incl ? 0 : th_pnB);
              if (th_sNA < HA || th_sNB < HB) c.th_bad_b_n++;
              else if (th_sCA < HA || th_sCB < HB) c.th_bad_b_c++;
              else {
                c.th_bad_b_nowin++;
                if (c.th_bad_b_nowin <= 20)
                  std::fprintf(stderr, "THNW k %" PRIu64 " idx %d lkcyc %"
                               PRId64 " sNA %" PRIu64 " sNB %" PRIu64
                               " sCA %" PRIu64 " sCB %" PRIu64 " incl %d "
                               "tbl A %x B %x\n", r.k,
                               int(th_last_idx), L.cyc, th_sNA, th_sNB,
                               th_sCA, th_sCB, int(incl), mA, mB);
              }
            }
            else c.th_bad_other++;
            // the first 20 of the class still to be defined: neither the
            // request bundles (A) nor the observed bundles (B) give the
            // RTL's index or tag, and the lookup was not on a rollback
            if (!L.q && !L.rb && badB && c.th_bad_other <= 20) {
              uint32_t f1a[3] = {}, f1b[3] = {};
              tg::folds(1, gA, f1a);
              tg::folds(1, gB, f1b);
              unsigned ha = 0, hb = 0;
              for (int i = 0; i < 16; i++) {
                ha |= unsigned(gA.at(i)) << i;
                hb |= unsigned(gB.at(i)) << i;
              }
              std::fprintf(stderr, "THDEV k %" PRIu64 " idx %d pc %" PRIx64
                           " lkpc %" PRIx64 " lkcyc %" PRId64 " q %d rb %d "
                           "B %d t1fh rtl %x A %x B %x hist16 A %04x B %04x "
                           "prev_wc %" PRId64 " incl %d "
                           "bundle A %d/%x B %d/%x tbl A %x B %x\n", r.k,
                           int(th_last_idx),
                           pc, L.pc, L.cyc, int(L.q), int(L.rb), int(!badB),
                           unsigned(L.fh[0]), f1a[0], f1b[0], ha, hb,
                           prev_wc, int(incl), int(hbA[th_last_idx].n), unsigned(hbA[th_last_idx].tkn),
                           int(hbB[th_last_idx].n), unsigned(hbB[th_last_idx].tkn),
                           mA, mB);
            }
          }
        }
      }
      th_snapA = hbA[r.idx & 63];
      th_snapB = hbB[r.idx & 63];
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
      if (r.is_br && r.rsn < R_N) {
        c.rsn_n[r.rsn]++;
        if (r.mis) c.rsn_m[r.rsn]++;
        if (r.xp >= 0) {
          c.xp_n[r.xp]++;
          if (r.mis) c.xp_m[r.xp]++;
        }
      }
      // PERF-005 Phase 2: THE COST of the fast path. TAGE's response is
      // present when it is for this entry (w_tage_hit_p2); right when its
      // direction is the outcome.
      if (r.is_br && r.rsn == R_C_FP && r.dv) {
        bool tg = r.d_thit;
        bool tg_ok = tg && r.d_ttk == r.in.taken;
        if (r.mis) {
          if (!r.d_fsh) c.fh_nosh++;
          else if (r.d_fleft) c.fh_left[fh_bucket(r.d_fres)]++;
          else c.fh_alloc[fh_bucket(r.d_fres)]++;
          if (!tg) c.fpm_tg_none++;
          else if (tg_ok) c.fpm_tg_right++;
          else c.fpm_tg_wrong++;
        } else {
          if (!tg) c.fpc_tg_none++;
          else if (!tg_ok) c.fpc_tg_wrong++;
        }
      }
      if (r.is_br) {
        // The slot-held branches, and the misses by class (PF-11).
        int mc = r.in.cls == cbp::C_COND ? 0
               : (r.in.cls == cbp::C_JMP_DIR || r.in.cls == cbp::C_CALL_DIR)
                   ? 1
               : r.in.cls == cbp::C_RET ? 3 : 2;
        // A branch with a trap after it was judged on its own outcome
        // (PERF-004), so its mispredict, if any, is its own and counts with
        // the rest. PERF-003 counted it apart (orc_slot_trap,
        // mispred_trap_after); both are removed.
        if (r.in_slot && r.kind_alias) {
          // PERF-004: held by a slot of the other kind (an alias), counted
          // apart; under the oracle as under the predictors.
          if (r.mis) c.orc_kind_alias++;
        } else if (r.in_slot) {
          if (r.mis) c.orc_slot_mis++;
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
        // THE RAS CLASSIFICATION (BP-151): the reference stack, in trace
        // order, and the cause of each mispredicted slot-held return.
        if (r.in.cls == cbp::C_CALL_DIR || r.in.cls == cbp::C_CALL_IND)
          rcl.commit_call(r.in.pc, r.k, r.pos, r.src, r.in_slot, r.rco,
                          r.in.cls == cbp::C_CALL_IND);
        else if (r.in.cls == cbp::C_RET)
          rcl.commit_ret(r.k, r.in.pc, r.in.target, r.pos, r.src,
                         r.mis && r.in_slot, false, r.rco, 0);
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
      if (evlog)
        std::fprintf(evlog, "C %" PRIu64 " %" PRId64 " %d %d %d %d %d\n",
                     r.k, cyc + 1, int(r.mis), int(r.idx), int(r.pos),
                     int(r.src), int(r.in.cls));
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
  if (evlog) std::fclose(evlog);

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
    // PERF-004 (TD#210): what the build measured, beside its sha.
    {"dirty", PERF_SRC_DIRTY}, {"input_digest", PERF_INPUT_DIGEST},
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
    {"orc_slot_kind_alias", std::to_string(c.orc_kind_alias)},
    // PERF-004: the RC_TRAP redirects after a branch (of trap_redirects),
    // in the place of orc_slot_trap and mispred_trap_after.
    {"trap_after_branch", std::to_string(c.br_traps)},
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
    {"conflict_unspec_repair", std::to_string(c.conflict_unspec)},
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
  // THE RAS CLASSIFICATION (BP-151), after every PERF-003 column: the
  // returns, the slot-held mispredicted ones, one column per cause (each
  // such return has exactly one), and the depths seen.
  row.push_back({"rc_returns", std::to_string(rcl.n_ret)});
  row.push_back({"rc_slot_mispred_ret", std::to_string(rcl.n_slot_mis)});
  for (int k = 0; k < rcls::C_N; k++)
    row.push_back({std::string("rc_") + rcls::cause_name(k),
                   std::to_string(rcl.cnt[k])});
  row.push_back({"rc_max_spec_depth", std::to_string(rcl.max_spec)});
  row.push_back({"rc_max_commit_count", std::to_string(rcl.max_cmt)});
  row.push_back({"rc_max_ref_depth", std::to_string(rcl.max_ref)});
  row.push_back({"rc_restores", std::to_string(rcl.n_restores)});
  row.push_back({"rc_commit_unexecuted_trap",
                 std::to_string(rcl.n_cmt_unexec_trap)});
  row.push_back({"rc_sentinel_skips", std::to_string(rcl.n_wrap_skip)});
  // BP-152, C1: the predecode calls and returns applied to the RAS.
  row.push_back({"rc_pd_push", std::to_string(rcl.n_pd_push)});
  row.push_back({"rc_pd_pop", std::to_string(rcl.n_pd_pop)});
  row.push_back({"rc_call_pd_ind", std::to_string(rcl.n_call_pd_ind)});
  // THE OPTIONS (Problem 4): of the returns of a cause, those the commit
  // stack's top (ctop) or its first open frame (cskip) would predict.
  for (int k : {int(rcls::C_FB_STALE), int(rcls::C_STALE), int(rcls::C_WRAP)}) {
    row.push_back({std::string("rc_opt_ctop_") + rcls::cause_name(k),
                   std::to_string(rcl.opt_ctop[k])});
    row.push_back({std::string("rc_opt_cskip_") + rcls::cause_name(k),
                   std::to_string(rcl.opt_cskip[k])});
  }
  // BP-153: of rc_pd_push and rc_pd_pop, those on the restore of a
  // backend redirect (ftq.sv bk_ras). Last, so the columns before them
  // keep their order.
  row.push_back({"rc_bk_push", std::to_string(rcl.n_bk_push)});
  row.push_back({"rc_bk_pop", std::to_string(rcl.n_bk_pop)});
  // BP-153 phase 2: restores that undid the named block's pop.
  row.push_back({"rc_undo_pop", std::to_string(rcl.n_undo_pop)});
  // BP-153 phase 3: ref_unmatched, target below the reference top / absent.
  row.push_back({"rc_unm_deep", std::to_string(rcl.n_unm_deep)});
  row.push_back({"rc_unm_closed", std::to_string(rcl.n_unm_closed)});
  row.push_back({"rc_unm_none", std::to_string(rcl.n_unm_none)});
  // BP-153 phase 3: bos_rewind by the rule it stands for.
  {
    static const char* bn[5] = {"fbu", "clost", "eclosed", "eoff", "edeep"};
    for (int i = 0; i < 5; i++)
      row.push_back({std::string("rc_brew_") + bn[i],
                     std::to_string(rcl.n_brew[i])});
  }
  // BP-154: the speculative allocations in flight, unwrapped (ras_class.h
  // max_inflight), and the cycles they stood at RAS_SPEC_ENTRIES - 1 or
  // more. Last, so the columns before them keep their order.
  row.push_back({"rc_max_inflight", std::to_string(rcl.max_inflight)});
  row.push_back({"rc_cyc_lap", std::to_string(rcl.n_cyc_lap)});
  // PERF-004 Phase 4: the configuration probes, last, so the columns
  // before them keep their order.
  row.push_back({"cf_fastpath_dirs", std::to_string(c.cf_fp)});
  row.push_back({"cf_sc_answers", std::to_string(c.cf_sc)});
  row.push_back({"cf_tage_epoch_adv", std::to_string(c.cf_tg_ep)});
  row.push_back({"cf_ittage_epoch_adv", std::to_string(c.cf_it_ep)});
  for (int t = 0; t < 4; t++)
    row.push_back({"cf_tage_decay_t" + std::to_string(t + 1),
                   std::to_string(c.cf_tg_dec[t])});
  for (int t = 0; t < 5; t++)
    row.push_back({"cf_ittage_decay_t" + std::to_string(t + 1),
                   std::to_string(c.cf_it_dec[t])});
  // PERF-005 Phase 1: THE REASONS, last, so the columns before them keep
  // their order: rs_<reason> the committed branches, rm_<reason> their
  // mispredicts; then the SC partition; then rs_sum_err, the distance of
  // each source's reasons (the *_other ones apart) from its pred_ and
  // mis_ columns, summed over the sources (0 when every *_other is 0).
  for (int r = 0; r < R_N; r++) {
    row.push_back({std::string("rs_") + RSN_NAME[r],
                   std::to_string(c.rsn_n[r])});
    row.push_back({std::string("rm_") + RSN_NAME[r],
                   std::to_string(c.rsn_m[r])});
  }
  for (int x = 0; x < 4; x++) {
    row.push_back({std::string("rs_") + XP_NAME[x],
                   std::to_string(c.xp_n[x])});
    row.push_back({std::string("rm_") + XP_NAME[x],
                   std::to_string(c.xp_m[x])});
  }
  {
    uint64_t err = 0;
    for (int s = 0; s < 8; s++) {
      uint64_t n = 0, m = 0;
      for (int r = 0; r < R_N; r++)
        if (RSN_SRC[r] == s) { n += c.rsn_n[r]; m += c.rsn_m[r]; }
      err += (n > c.pred_src[s] ? n - c.pred_src[s] : c.pred_src[s] - n);
      err += (m > c.mis_src[s] ? m - c.mis_src[s] : c.mis_src[s] - m);
    }
    row.push_back({"rs_sum_err", std::to_string(err)});
  }
  // PERF-005 Phase 2: THE FAST PATH, last. fp_chk_* and fu_chk_* are
  // checks (0 expected); the rest are counts.
  {
    auto P = [&](const char* k, uint64_t v) {
      row.push_back({k, std::to_string(v)});
    };
    P("fp_reads", c.fp_rd);
    P("fp_fired", c.fp_fire);
    P("fp_chk_conf", c.fp_chk_rd);
    P("fp_chk_noshadow", c.fp_chk_nosh);
    P("fp_chk_41", c.fp_chk_41);
    P("fp_chk_use", c.fp_chk_use);
    P("fu_chk_rdconf", c.fu_chk_rd);
    P("fu_chk_wrconf", c.fu_chk_wr);
    P("fu_chk_keep", c.fu_chk_keep);
    P("fu_chk_noshadow", c.fu_chk_nosh);
    P("ftb_res_cond", c.res_cond);
    P("ftb_sched_acc_br", c.fs_acc);
    P("ftb_sched_drop_br", c.fs_drop);
    P("ftb_upd_br", c.fu_br);
    P("ftb_upd_inplace", c.fu_inpl);
    P("ftb_upd_alloc", c.fu_alloc);
    P("ftb_upd_past", c.fu_past);
    P("ftb_upd_split", c.fu_split);
    P("ftb_upd_leave_sat", c.fu_leave);
    P("ftb_upd_resat", c.fu_resat);
    for (int b = 0; b < FH_N; b++)
      row.push_back({std::string("fpm_left_") + FH_NAME[b],
                     std::to_string(c.fh_left[b])});
    for (int b = 0; b < FH_N; b++)
      row.push_back({std::string("fpm_alloc_") + FH_NAME[b],
                     std::to_string(c.fh_alloc[b])});
    P("fpm_noshadow", c.fh_nosh);
    P("fpm_tage_right", c.fpm_tg_right);
    P("fpm_tage_wrong", c.fpm_tg_wrong);
    P("fpm_tage_none", c.fpm_tg_none);
    P("fpc_tage_wrong", c.fpc_tg_wrong);
    P("fpc_tage_none", c.fpc_tg_none);
    // PERF-005 Phase 3: THE TAGE CHECKS, last. th_chk_* and the read and
    // update tu_chk_* are checks (0 expected); the rest are counts.
    P("th_entries", c.th_n);
    P("th_nolookup", c.th_nolk);
    P("th_lag", c.th_lag);
    P("th_chk_pc", c.th_pc);
    for (int t = 0; t < 5; t++) {
      std::string n = std::to_string(t);
      P(("th_chk_idx_t" + n).c_str(), c.th_idx[t]);
      if (t) P(("th_chk_tag_t" + n).c_str(), c.th_tag[t]);
      if (t) P(("th_fold_t" + n).c_str(), c.th_fold[t]);
    }
    for (int t = 0; t < 5; t++) {
      std::string n = std::to_string(t);
      P(("th_obs_idx_t" + n).c_str(), c.th_idxB[t]);
      if (t) P(("th_obs_tag_t" + n).c_str(), c.th_tagB[t]);
    }
    P("th_bad", c.th_bad);
    P("th_bad_queued", c.th_bad_q);
    P("th_bad_rollback", c.th_bad_rb);
    P("th_bad_rollback_nored", c.th_bad_rb_n);
    P("th_bad_obs_ok", c.th_bad_b);
    P("th_bad_obs_nored", c.th_bad_b_n);
    P("th_bad_obs_corr", c.th_bad_b_c);
    P("th_bad_obs_nowin", c.th_bad_b_nowin);
    P("th_bad_other", c.th_bad_other);
    P("th_bundle_a_ne_b", c.th_hb_ab);
    P("th_bundle_p1only", c.th_ab_p1only);
    P("th_bundle_corr", c.th_ab_corr);
    P("th_bundle_other", c.th_ab_other);
    P("tr_reads", c.tr_n);
    P("tr_chk_read", c.tr_bad);
    P("tr_collide", c.tr_coll);
    P("tu_updates", c.tu_n);
    P("tu_mispredicts", c.tu_mis);
    P("tu_chk", c.tu_chk);
    P("tu_chk_we", c.tu_chk_we);
    P("tu_chk_addr", c.tu_chk_addr);
    P("tu_chk_ctr", c.tu_chk_ctr);
    P("tu_chk_use", c.tu_chk_use);
    P("tu_chk_alc", c.tu_chk_alc);
    P("tu_chk_uaon", c.tu_chk_uaon);
    P("tu_gone_prm", c.tu_gone_p);
    P("tu_gone_alt", c.tu_gone_a);
    P("tu_stale_prm", c.tu_stale_p);
    P("tu_stale_alt", c.tu_stale_a);
    P("tu_alloc", c.tu_alc);
    P("tu_alloc_ntk", c.tu_alc_ntk);
    P("tu_alloc_dup", c.tu_alc_dup);
    P("tu_alloc_ref_longest", c.tu_alc_long);
    P("tu_alloc_ref_useful", c.tu_alc_use);
    P("tu_alloc_ref_other", c.tu_alc_other);
    P("tu_prov_prm", c.tu_rows[0]);
    P("tu_prov_alt", c.tu_rows[1]);
    P("tu_prov_alt_t0", c.tu_rows[2]);
    P("tu_prov_t0", c.tu_rows[3]);
    P("sp_answers", c.sp_n);
    P("sp_chk_sum", c.sp_chk_sum);
    P("sp_chk_dec", c.sp_chk_dec);
    P("su_updates", c.su_n);
    P("su_chk_wr", c.su_chk_wr);
    P("su_chk_wd", c.su_chk_wd);
    P("su_chk_glob", c.su_chk_glob);
    P("sp_hi_chose_sc", c.sp_hi_sc);
    P("sp_hi_chose_tage", c.sp_hi_tg);
    P("sp_med_chose_sc", c.sp_med_sc);
    P("sp_med_chose_tage", c.sp_med_tg);
    P("sc_thr_max", c.sc_thr_max);
  }
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
