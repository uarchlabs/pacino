// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// ras_class.h -- THE RAS CLASSIFICATION (BP-151). Observation only: it
// reads perf_top's rc_* ports (the RAS state, its p2 and p3 operations,
// its array write ports, the restore and the commit) and the harness's
// committed path, and drives nothing.
//
//   THE LEDGER  a shadow of the RAS's provenance. Every speculative slot
//               carries the allocation that wrote it last (seq, the FTQ
//               instance that pushed it, the address); every commit slot
//               the instance whose commit wrote it. Each FTQ index has an
//               instance id, new at each allocation, and the instance's
//               RAS observation (IObs): its p2 operations, the pop's
//               state and source, the push and where it went, its p3
//               repair, and the restores that named it.
//   THE REFERENCE  a trace-driven return stack with no size limit, pushed
//               at each committed call (pc + 4) and popped at each
//               committed return, in trace order.
//   THE CAUSE   one per mispredicted slot-held return, by the rules in
//               classify() (BP-151 Results Capture, Problem 1).
//
// BP-152 (RAS-4), the RAS state the rules read changes, the rules are
// those of BP-151 except as below (BP-152 Results Capture, Problem 1):
//   - A1: a pop on an empty stack reads the commit stack at the index
//     the RAS forms (rc_p2_fbi, CSP-1-n), so its occupant is that
//     index's, not the top's.
//   - C1: a call predecode found is pushed on the restore of its
//     predecode redirect (rc_pd_*): the push is the call's, its
//     allocation is tracked as any other, and R5 counts it.
//   - R8 (C_T's entry reused) applies to a pop that read the speculative
//     stack, at C_T's own reused slot. With B1 a pop whose link was
//     killed reads empty and falls back, and R9 decides it; a pop of
//     another entry is decided by R10.
//   - R9, C_T committed, a closed frame at the fallback index: with A1
//     the index is the speculative depth's, so the frame's closer
//     decides, as in R10 (ret_pd, ret_nopop), else fb_stale_top.
//   - an off-path op of a restored block (snap_offpath_op) excludes a
//     push the restore undid (rc_rs_undo).
//   - a C1 push is also recorded by instance (pd_by_inst_), since the
//     call's take may precede the write-back's restore.
// ===================================================================
#ifndef PERF_RAS_CLASS_H
#define PERF_RAS_CLASS_H

#include <algorithm>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#ifndef PERF_SLOTS
#define PERF_SLOTS 2
#endif

namespace rcls {

constexpr int      NS   = PERF_SLOTS;     // NUM_PRED_SLOTS
constexpr int      RS   = 16;             // RAS_SPEC_ENTRIES
constexpr int      RC   = 32;             // RAS_COMMIT_ENTRIES
constexpr int      WP   = 4 * PERF_SLOTS; // ras.sv RAS_WR_PORTS
constexpr uint64_t VMASK = (uint64_t(1) << 59) - 1;
// bp_br_type_e
constexpr uint8_t T_DCALL = 1, T_ICALL = 2, T_RET = 3, T_RC = 7;
// ras.sv op encoding
constexpr uint8_t OP_PUSH = 1, OP_POP = 2;
// pred_src
constexpr uint8_t S_UBTB = 0, S_FTB = 2, S_RAS = 6, S_NONE = 7;

inline bool is_call_t(uint8_t t) {
  return t == T_DCALL || t == T_ICALL || t == T_RC;
}
inline bool is_ret_t(uint8_t t) { return t == T_RET || t == T_RC; }

// A speculative slot's occupant: the allocation that wrote it last.
struct Occ {
  uint64_t seq = 0;          // 0: never allocated since reset
  uint64_t inst = 0;         // the FTQ instance that pushed it
  uint64_t addr = 0;
  uint64_t cyc = 0;
  uint8_t  pos = 0;          // the pushing slot's position
  bool     repair = false;   // a p3 missed push
};
// A commit slot's occupant.
struct COcc {
  bool     v = false;
  uint64_t inst = 0, addr = 0, cyc = 0;
};
// The allocation that reused a slot (THE WRAP and the reuse below BOS).
struct Evict {
  uint64_t by_inst = 0, cyc = 0;
  bool     victim_cmt = false;   // the evicted push's block had committed
  bool     skip = false;         // the allocation was the sentinel skip
};

// One FTQ instance's RAS observation.
struct IObs {
  uint64_t inst = 0;
  bool     p2 = false;           // a p2 cycle was seen
  bool     ftb = false;          // the FTB answered at p2
  bool     applied = false;      // the p2 pass was kept (no restore, keep)
  uint64_t p2_cyc = 0;
  uint8_t  op[NS] = {}, type[NS] = {}, pos[NS] = {};
  bool     val[NS] = {};
  // the pop (the lowest popping slot)
  int      pop_s = -1;
  bool     pop_empty = false, popv = false;
  uint8_t  pre = 0, tosw = 0, bos = 0, csp = 0, cnt = 0, rctr = 0;
  uint64_t pop_addr = 0;
  Occ      pocc;                 // the speculative occupant popped
  COcc     cocc;                 // the commit-stack top, for a fallback
  uint64_t cmt_inst = 0;         // the last instance committed, at p2
  // the commit stack's top entries at the pop, newest first: instance
  // and address (THE OPTIONS, Problem 4)
  int      ncstk = 0;
  uint64_t cstk_inst[8] = {}, cstk_addr[8] = {};
  // the push (the lowest pushing slot)
  int      push_s = -1;
  uint8_t  kind = 0;             // 0 allocate, 1 recursion, 2 saturated
  uint8_t  aidx = 0;
  uint64_t aseq = 0, ft = 0;
  // the p3 repair of this instance
  uint8_t  rep = 0;              // REP_* bits
  bool     rep_applied = false;
  uint64_t rep_seq = 0;          // a missed push's allocation
  uint8_t  rep_aidx = 0;
  // BP-152, C1: the predecode operation on this instance's restore
  bool     pd_push = false, pd_pop = false;
  uint8_t  pd_pos = 0;
  uint64_t pd_seq = 0, pd_ft = 0;
  uint8_t  pd_aidx = 0;
  // BP-152, A1: the commit-stack index the empty pop read, and n, the
  // committed depth less the depth at the pop
  uint8_t  fbi = 0;
  int      fbn = 0;
  // restores that named this instance
  uint32_t n_named = 0;
};
constexpr uint8_t REP_UNDO_PUSH = 1, REP_UNDO_POP = 2, REP_MISS_POP = 4,
                  REP_MISS_PUSH = 8, REP_UNDO_RC = 16;

// One restore.
struct Rst {
  uint64_t cyc = 0, inst = 0;
  uint8_t  idx = 0, pos = 0;
  bool     pd = false;           // a predecode redirect, else the backend
  bool     cmt = false;          // a commit that moved BOS the same cycle
  uint8_t  tosr = 0, tosw = 0, bos = 0;
  // THE SNAPSHOT'S CONTENT against the redirect (BP-151, Problem 1):
  bool     op_after = false;     // a p2 op of the named block at a slot
                                 // after the redirecting position
  bool     rep = false;          // the named block had a p3 repair
  bool     rewind = false;       // the snapshot's BOS is not the BOS it
                                 // replaces (H2: commits since the snapshot)
};
// The pop that moved TOSR off an allocation (not a count decrement).
struct Popper {
  uint64_t inst = 0, cyc = 0;
};

// The reference stack's entry: one committed call.
struct RefEnt {
  uint64_t addr = 0, k = 0;
  uint8_t  pos = 0, src = S_NONE;
  bool     in_slot = false;
  bool     ind = false;          // BP-152: an indirect call (C_CALL_IND)
  uint64_t max_above = 0;        // the most entries above it while live
  IObs     obs;                  // the call's instance, at its take
};
// The return that closed a reference frame.
struct Closer {
  uint64_t k = 0;
  uint8_t  src = S_NONE;
  IObs     obs;
};

// The causes (BP-151 Results Capture, Problem 1, THE RULES).
enum Cause : int {
  C_TRAP = 0, C_REF_UNMATCHED, C_PD_RET, C_P3_REACH, C_P1_ONLY,
  C_CALL_PD, C_CALL_P1, C_CALL_DROP, C_CALL_UNDONE, C_CALL_ADDR,
  C_RCTR_SAT, C_DEPTH, C_POP_EMPTY, C_TGT_OK, C_WRAP, C_STALE,
  C_FB_RCTR_BOS, C_FB_UNCMT, C_FB_STALE, C_CMT_ADDR, C_CMT_LOST,
  C_CMT_NONCALL, C_SNAP_REP, C_RET_NOPOP, C_RET_PD, C_EXTRA_CLOSED,
  C_SNAP_AFTER, C_EXTRA_OFFPATH, C_EXTRA_DEEP, C_PROPAG, C_BOS_REWIND,
  C_CMT_TRAP, C_OTHER, C_N
};
inline const char* cause_name(int c) {
  static const char* n[C_N] = {
    "trap_after", "ref_unmatched", "pd_return", "p3_reach", "p1_only",
    "call_pd", "call_p1_only", "call_dropped", "call_undone_p3",
    "call_addr", "rctr_sat", "depth", "pop_empty", "target_ok", "wrap",
    "stale_below_bos", "fb_rctr_at_bos", "fb_uncommitted", "fb_stale_top",
    "commit_addr", "commit_lost", "commit_noncall", "snap_repair",
    "ret_nopop", "ret_pd", "extra_closed", "snap_offpath_op",
    "extra_offpath",
    "extra_deep", "propagated", "bos_rewind", "commit_unexecuted", "other"};
  return n[c];
}

class RasClass {
 public:
  uint64_t cnt[C_N] = {};
  uint64_t opt_ctop[C_N] = {}, opt_cskip[C_N] = {};
  uint64_t n_ret = 0, n_slot_mis = 0, max_spec = 0, max_cmt = 0;
  uint64_t max_ref = 0, n_restores = 0, n_wrap_skip = 0;
  uint64_t n_cmt_unexec_trap = 0;   // commit_unexecuted after an RC_TRAP
  uint64_t n_pd_push = 0, n_pd_pop = 0;  // BP-152, C1 operations
  uint64_t n_call_pd_ind = 0;   // BP-152: call_pd whose call is a JALR
  int      dump = 0;              // RC_DUMP: lines to print per cause
  int      dumped[C_N] = {};
  uint64_t tr_from = 0, tr_to = 0;  // RC_TRACE=from:to, the RAS events

  IObs& cur(uint8_t idx) { return cur_[idx & 63]; }

  // ---- once per cycle, before the edge ----------------------------------
  // redir_now/rd_pos: the backend redirect the harness drives this cycle.
  template <class T>
  void observe(T* t, uint64_t cyc, bool redir_now, uint8_t rd_pos,
               uint8_t rd_type, uint8_t rd_cause) {
    // (1) the p3 repair of the block at p3 (os_p3_idx), then the p2 pass of
    // the block at p2 (os_p2_idx), as the scan orders them. The restore
    // drops every scan write; keep low drops the p2 pass.
    const bool rs = t->rc_rs_val;
    const bool keep = t->rc_keep;
    if (cyc >= tr_from && cyc < tr_to) {
      std::fprintf(stderr, "RTR %" PRIu64 " tosr %d tosw %d bos %d csp %d "
                   "cnt %d keep %d", cyc, int(t->rc_tosr), int(t->rc_tosw),
                   int(t->rc_bos), int(t->rc_csp), int(t->rc_ccnt), int(keep));
      if (t->os_p3_val)
        for (int s = 0; s < NS; s++)
          if (t->rc_p3_op[s] || ((t->rc_p3_val >> s) & 1))
            std::fprintf(stderr, " | p3 idx %d inst %" PRIu64 " s%d op %d "
                         "view %d/%d", int(t->os_p3_idx),
                         cur(t->os_p3_idx).inst, s, int(t->rc_p3_op[s]),
                         int((t->rc_p3_val >> s) & 1), int(t->rc_p3_type[s]));
      if (t->os_p2_val)
        for (int s = 0; s < NS; s++)
          if (t->rc_p2_op[s])
            std::fprintf(stderr, " | p2 idx %d inst %" PRIu64 " pc %" PRIx64
                         " s%d op %d type %d pos %d pre %d popv %d popa %"
                         PRIx64 " ft %" PRIx64, int(t->os_p2_idx),
                         cur(t->os_p2_idx).inst, uint64_t(t->os_p2_pc), s,
                         int(t->rc_p2_op[s]), int(t->rc_p2_type[s]),
                         int(t->os_p2_s_pos[s]), int(t->rc_p2_pre[s]),
                         int((t->rc_p2_popv >> s) & 1),
                         uint64_t(t->rc_p2_popa[s]) & VMASK,
                         uint64_t(t->rc_p2_ft[s]) & VMASK);
      if (rs)
        std::fprintf(stderr, " | RESTORE idx %d inst %" PRIu64 " snap %d/%d/%d"
                     " pd %d", int(t->rc_rs_idx), cur(t->rc_rs_idx).inst,
                     int(t->rc_rs_tosr), int(t->rc_rs_tosw), int(t->rc_rs_bos),
                     int(!redir_now));
      if (t->rc_cm_val)
        std::fprintf(stderr, " | COMMIT idx %d inst %" PRIu64 " type %d addr %"
                     PRIx64 " snap %d/%d", int(t->rc_cm_idx),
                     cur(t->rc_cm_idx).inst, int(t->rc_cm_type),
                     uint64_t(t->rc_cm_addr) & VMASK, int(t->rc_cm_tosr),
                     int(t->rc_cm_bos));
      std::fprintf(stderr, "\n");
    }
    // depth
    uint64_t d = (uint64_t(t->rc_tosw) - uint64_t(t->rc_bos)) & (RS - 1);
    if (d > max_spec) max_spec = d;
    if (uint64_t(t->rc_ccnt) > max_cmt) max_cmt = t->rc_ccnt;
    // pending allocations of this cycle: port, occupant
    struct Al { int port; Occ o; };
    std::vector<Al> al;
    if (t->os_p3_val) {
      uint8_t pidx = t->os_p3_idx;
      IObs& o = cur(pidx);
      for (int s = 0; s < NS; s++) {
        uint8_t ty = t->rc_p3_type[s];
        bool v = (t->rc_p3_val >> s) & 1;
        bool s3pop = v && is_ret_t(ty), s3push = v && is_call_t(ty);
        uint8_t q = t->rc_p3_op[s];
        bool qpop = q & OP_POP, qpush = q & OP_PUSH;
        uint8_t r = 0;
        if (qpop && qpush && !s3pop && !s3push) r |= REP_UNDO_RC;
        else {
          if (qpush && !s3push) r |= REP_UNDO_PUSH;
          if (qpop && !s3pop) r |= REP_UNDO_POP;
          else if (!qpop && s3pop) r |= REP_MISS_POP;
          if (!qpush && s3push) r |= REP_MISS_PUSH;
        }
        if (r) {
          o.rep |= r;
          o.rep_applied = !rs;
          if ((r & REP_MISS_PUSH) && !rs) {
            pushed_inst_.insert(o.inst);
            int port = -1;
            for (int n = 1; n >= 0; n--)
              if (port < 0 && ((t->rc_we >> (s * 2 + n)) & 1)) port = s * 2 + n;
            if (port >= 0) {
              Occ oc;
              oc.inst = o.inst; oc.addr = uint64_t(t->rc_p3_ft[s]) & VMASK;
              oc.cyc = cyc; oc.pos = o.pos[s]; oc.repair = true;
              al.push_back({port, oc});
            }
          }
        }
      }
    }
    if (t->os_p2_val) {
      uint8_t pidx = t->os_p2_idx;
      IObs& o = cur(pidx);
      o.p2 = true;
      o.ftb = t->rc_ftb_p2;
      o.applied = keep && !rs;
      o.p2_cyc = cyc;
      o.pop_s = -1;
      o.push_s = -1;
      for (int s = 0; s < NS; s++) {
        o.val[s] = (t->rc_p2_val >> s) & 1;
        o.type[s] = t->rc_p2_type[s];
        o.op[s] = t->rc_p2_op[s];
        o.pos[s] = t->os_p2_s_pos[s];
      }
      for (int s = 0; s < NS; s++) {
        if ((o.op[s] & OP_POP) && o.pop_s < 0) {
          o.pop_s = s;
          o.pop_empty = (t->rc_p2_pre_empty >> s) & 1;
          o.popv = (t->rc_p2_popv >> s) & 1;
          o.pre = t->rc_p2_pre[s];
          o.pop_addr = uint64_t(t->rc_p2_popa[s]) & VMASK;
          o.tosw = t->rc_tosw;
          o.bos = t->rc_bos;
          o.csp = t->rc_csp;
          o.cnt = t->rc_ccnt;
          o.rctr = t->rc_spec_rctr[o.pre];
          // the occupant: a repair allocation of this cycle at pre first
          o.pocc = spec_[o.pre];
          for (auto& a : al)
            if (int(t->rc_waddr[a.port]) == int(o.pre)) o.pocc = a.o;
          // BP-152 A1: the fallback reads the index the RAS formed
          o.fbi  = uint8_t(t->rc_p2_fbi[s]);
          // the depth before the pop is the slot's dep plus the pop, less
          // a push of the same slot (RETURN_CALL)
          o.fbn  = int8_t(uint8_t(t->rc_dcm) -
                          uint8_t(t->rc_p2_dep[s] + 1 -
                                  ((o.op[s] & OP_PUSH) ? 1 : 0)));
          o.cocc = o.pop_empty ? cmt_[o.fbi % RC]
                               : cmt_[(uint32_t(t->rc_csp) + RC - 1) % RC];
          o.cmt_inst = last_cmt_inst_;
          o.ncstk = 0;
          for (uint32_t j = 0; j < 8 && j < uint32_t(t->rc_ccnt); j++) {
            uint32_t ci = (uint32_t(t->rc_csp) + RC - 1 - j) % RC;
            o.cstk_inst[j] = cmt_[ci].inst;
            o.cstk_addr[j] = uint64_t(t->rc_cmt_addr[ci]) & VMASK;
            o.ncstk++;
          }
          // the pop that moves TOSR off this allocation
          if (!o.pop_empty && o.rctr == 0 && o.applied && o.pocc.seq != 0)
            popper_[o.pocc.seq] = Popper{o.inst, cyc};
        }
        if ((o.op[s] & OP_PUSH) && o.push_s < 0) {
          o.push_s = s;
          if (o.applied) pushed_inst_.insert(o.inst);
          o.kind = ((t->rc_p2_inc >> s) & 1) ? 1
                 : ((t->rc_p2_sat >> s) & 1) ? 2 : 0;
          o.ft = uint64_t(t->rc_p2_ft[s]) & VMASK;
          if (o.kind == 0 && o.applied) {
            int port = -1;
            for (int n = 1; n >= 0; n--)
              if (port < 0 && ((t->rc_we >> ((NS + s) * 2 + n)) & 1))
                port = (NS + s) * 2 + n;
            if (port >= 0) {
              Occ oc;
              oc.inst = o.inst; oc.addr = o.ft; oc.cyc = cyc;
              oc.pos = o.pos[s];
              al.push_back({port, oc});
            }
          } else if (o.kind == 1) {
            // the push matched the top: the entry the pop left, or the
            // entry at the slot's pre-op TOSR
            o.aidx = t->rc_p2_pre[s];
            o.aseq = spec_[o.aidx].seq;
          }
        }
      }
    }
    // (2) the allocations, at the edge, in port order
    if (!rs) {
      std::sort(al.begin(), al.end(),
                [](const Al& a, const Al& b) { return a.port < b.port; });
      for (auto& a : al) {
        uint8_t i = t->rc_waddr[a.port];
        // THE SENTINEL SKIP (PU2, the wrap): an allocation at BOS + 1
        // made with TOSW at BOS. The entries below it are left resident
        // and unreachable (PU3).
        if (uint8_t(t->rc_tosw) == uint8_t(t->rc_bos) &&
            i == uint8_t((uint32_t(t->rc_bos) + 1) % RS)) {
          n_wrap_skip++;
          skip_cyc_.push_back(cyc);
          if (skip_cyc_.size() > 256) skip_cyc_.erase(skip_cyc_.begin());
        }
        Occ& v = spec_[i];
        if (v.seq != 0) {
          Evict e;
          e.by_inst = a.o.inst;
          e.cyc = cyc;
          e.victim_cmt = v.inst <= last_cmt_inst_;
          e.skip = (uint8_t(t->rc_tosw) == uint8_t(t->rc_bos));
          evict_[v.seq] = e;
        }
        a.o.seq = ++seq_;
        v = a.o;
        IObs& o = inst_obs(a.o.inst);
        if (a.o.repair) { o.rep_seq = v.seq; o.rep_aidx = i; }
        else if (o.inst == a.o.inst) { o.aseq = v.seq; o.aidx = i; }
      }
    }
    // (3) the restore
    if (rs) {
      n_restores++;
      Rst r;
      r.cyc = cyc;
      r.idx = t->rc_rs_idx;
      IObs& o = cur(r.idx);
      r.inst = o.inst;
      o.n_named++;
      r.pd = !redir_now;
      r.pos = redir_now ? rd_pos : uint8_t(t->rc_pd_pos);
      r.tosr = t->rc_rs_tosr; r.tosw = t->rc_rs_tosw; r.bos = t->rc_rs_bos;
      // An operation of the named block that the redirect shows is off
      // the path: at a slot after the redirecting position, or at that
      // position with a RAS effect the corrected type does not have (the
      // backend's resolved type; predecode's corrected slot there).
      uint8_t cty = rd_type;
      if (r.pd) {
        cty = 6;                                  // NO_BRANCH
        for (int s = 0; s < NS; s++)
          if (((t->pc_s_val >> s) & 1) && t->pc_s_pos[s] == r.pos)
            cty = t->pc_s_type[s];
      }
      for (int s = 0; s < NS; s++) {
        if (!o.applied || !o.op[s]) continue;
        // BP-152: a push the restore undid (ras_rs_undo) is not in the
        // restored state; only a pop stays off the path.
        if (t->rc_rs_undo && !(o.op[s] & OP_POP)) continue;
        if (o.pos[s] > r.pos) r.op_after = true;
        if (o.pos[s] == r.pos &&
            (is_call_t(o.type[s]) != is_call_t(cty) ||
             is_ret_t(o.type[s]) != is_ret_t(cty)))
          r.op_after = true;
      }
      r.rep = o.rep != 0 && o.rep_applied;
      r.cmt = t->rc_cm_val;
      r.rewind = uint8_t(t->rc_rs_bos) != uint8_t(t->rc_bos);
      named_[r.inst]++;
      if (r.op_after) named_after_.insert(r.inst);
      // RC_TRAP (cause 1) names the trapping instruction's entry, which
      // survives (_self clear) with its slots after the trap uncleared.
      if (!r.pd && rd_cause == 1) trap_inst_.insert(r.inst);
      // BP-152, C1: the predecode operation on this restore. Its push
      // allocates as a p2 push does (THE SENTINEL SKIP against the
      // snapshot's TOSW and BOS, which the restore loads).
      if (t->rc_pd_val) {
        uint8_t pty = t->rc_pd_type;
        o.pd_pos = uint8_t(t->rc_pd_pos);
        if (is_ret_t(pty)) { o.pd_pop = true; n_pd_pop++; }
        if (is_call_t(pty)) {
          o.pd_push = true;
          o.pd_ft = uint64_t(t->rc_pd_ret) & VMASK;
          n_pd_push++;
          if (t->rc_pd_al) {
            uint8_t i = t->rc_pd_waddr;
            if (uint8_t(t->rc_rs_tosw) == uint8_t(t->rc_rs_bos) &&
                i == uint8_t((uint32_t(t->rc_rs_bos) + 1) % RS)) {
              n_wrap_skip++;
              skip_cyc_.push_back(cyc);
              if (skip_cyc_.size() > 256) skip_cyc_.erase(skip_cyc_.begin());
            }
            Occ& v = spec_[i];
            if (v.seq != 0) {
              Evict e;
              e.by_inst = o.inst;
              e.cyc = cyc;
              e.victim_cmt = v.inst <= last_cmt_inst_;
              e.skip = (uint8_t(t->rc_rs_tosw) == uint8_t(t->rc_rs_bos));
              evict_[v.seq] = e;
            }
            Occ oc;
            oc.inst = o.inst; oc.addr = o.pd_ft; oc.cyc = cyc;
            oc.pos = o.pd_pos;
            oc.seq = ++seq_;
            v = oc;
            o.pd_seq = oc.seq;
            o.pd_aidx = i;
          }
          // The call may have been taken, and its instance observation
          // copied, before this restore (the write-back trails the
          // delivery): the push is also kept by instance.
          PdRec pr;
          pr.pos = o.pd_pos; pr.seq = o.pd_seq; pr.aidx = o.pd_aidx;
          pr.ft = o.pd_ft;
          pd_by_inst_[o.inst] = pr;
          pushed_inst_.insert(o.inst);
        }
      }
      last_rst_ = r;
      rst_log_.push_back(r);
      if (rst_log_.size() > 256) rst_log_.erase(rst_log_.begin());
    }
    // (4) the commit stack and the committed instance
    if (t->rc_cm_val) {
      uint8_t ty = t->rc_cm_type;
      bool cpop = is_ret_t(ty), cpush = is_call_t(ty);
      uint32_t csp = t->rc_csp, cn = t->rc_ccnt;
      uint32_t mid = (cpop && cn != 0) ? (csp + RC - 1) % RC : csp;
      uint64_t ci = cur(t->rc_cm_idx).inst;
      if (cpush) {
        COcc c;
        c.v = true; c.inst = ci; c.cyc = cyc;
        c.addr = uint64_t(t->rc_cm_addr) & VMASK;
        cmt_[mid] = c;
      }
      last_cmt_inst_ = ci;
    }
    // (5) allocation of a new FTQ instance (p1), after the events above
    if (t->ew_alloc_val) {
      IObs& o = cur(t->ew_alloc_idx);
      o = IObs();
      o.inst = ++inst_ctr_;
      by_inst_[o.inst & (64 * 4 - 1)] = t->ew_alloc_idx;
    }
  }

  // ---- the committed path -----------------------------------------------
  void path_call(uint64_t inst, uint8_t pos, uint64_t k) {
    path_[(inst << 6) | pos] = k;
    path_inst_[inst] = k;
  }
  void path_ret(uint64_t inst, uint64_t k) { path_ret_[inst] = k; }
  // An instance with a path instruction at a class-conflict PC (supply.h:
  // the trace records the PC in more than one class).
  void path_conflict(uint64_t inst) { conflict_.insert(inst); }
  // A committed call, in trace order.
  void commit_call(uint64_t pc, uint64_t k, uint8_t pos, uint8_t src,
                   bool in_slot, const IObs& obs, bool ind = false) {
    RefEnt e;
    e.addr = (pc + 4) & VMASK;
    e.k = k; e.pos = pos; e.src = src; e.in_slot = in_slot; e.obs = obs;
    e.ind = ind;
    ref_.push_back(e);
    live_.insert(k);
    if (ref_.size() > max_ref) max_ref = ref_.size();
    for (size_t j = 0; j + 1 < ref_.size(); j++) {
      uint64_t above = ref_.size() - 1 - j;
      if (above > ref_[j].max_above) ref_[j].max_above = above;
    }
  }
  // A committed return, in trace order. mis_slot: a mispredicted slot-held
  // return; trap: a trace discontinuity after it. Returns the cause, or -1.
  int commit_ret(uint64_t k, uint64_t pc, uint64_t tgt, uint8_t pos,
                 uint8_t src, bool mis_slot, bool trap, const IObs& o,
                 uint64_t rec_tgt) {
    n_ret++;
    tgt &= VMASK;
    bool matched = !ref_.empty() && ref_.back().addr == tgt;
    RefEnt top;
    if (matched) top = ref_.back();
    int c = -1;
    if (mis_slot) {
      n_slot_mis++;
      c = classify(k, pc, tgt, pos, src, trap, matched, top, o, rec_tgt);
      cnt[c]++;
      // THE OPTIONS (Problem 4), measured without the change: the commit
      // stack's top at the pop (ctop), and its first entry whose frame
      // the reference holds open, skipping the frames whose returns came
      // before this one (cskip).
      if (matched && o.pop_s >= 0 && o.ncstk > 0) {
        if (o.cstk_addr[0] == tgt) opt_ctop[c]++;
        for (int j = 0; j < o.ncstk; j++) {
          auto it = path_inst_.find(o.cstk_inst[j]);
          if (it != path_inst_.end() && !live_.count(it->second)) continue;
          if (o.cstk_addr[j] == tgt) opt_cskip[c]++;
          break;
        }
      }
    }
    // the reference pop: to the matching entry when the target is on the
    // stack (an unwind), else one entry. Each frame popped records the
    // return that closed it.
    Closer cl;
    cl.k = k; cl.src = src; cl.obs = o;
    if (matched) {
      pop_ref(cl);
    } else {
      size_t j = ref_.size();
      while (j > 0 && ref_[j - 1].addr != tgt) j--;
      if (j > 0) {
        while (ref_.size() >= j) pop_ref(cl);
      } else if (!ref_.empty()) {
        pop_ref(cl);
      }
    }
    return c;
  }

 private:
  // BP-152: a C1 push, by the instance that made it.
  struct PdRec {
    uint8_t  pos = 0, aidx = 0;
    uint64_t seq = 0, ft = 0;
  };
  std::unordered_map<uint64_t, PdRec> pd_by_inst_;
  // BP-152, diagnostics: the instances whose call operated the
  // speculative stack (a kept p2 push of any kind, a p3 missed push, a
  // C1 push).
  std::unordered_set<uint64_t> pushed_inst_;
  IObs     cur_[64];
  Occ      spec_[RS];
  COcc     cmt_[RC];
  uint64_t seq_ = 0, inst_ctr_ = 0, last_cmt_inst_ = 0;
  uint8_t  by_inst_[256] = {};
  std::unordered_map<uint64_t, Evict>    evict_;
  std::unordered_map<uint64_t, uint64_t> path_;
  std::unordered_map<uint64_t, uint64_t> path_inst_;
  std::unordered_map<uint64_t, uint64_t> path_ret_;
  std::unordered_map<uint64_t, Popper>   popper_;
  std::unordered_set<uint64_t>           conflict_;
  std::unordered_set<uint64_t>           trap_inst_;
  std::unordered_set<uint64_t>           live_;
  std::unordered_map<uint64_t, Closer>   closer_;
  std::unordered_map<uint64_t, uint32_t> named_;
  std::unordered_set<uint64_t>           named_after_;
  std::vector<RefEnt>                    ref_;
  std::vector<Rst>                       rst_log_;
  std::vector<uint64_t>                  skip_cyc_;
  Rst                                    last_rst_;
  IObs                                   dummy_;

  IObs& inst_obs(uint64_t inst) {
    IObs& o = cur(by_inst_[inst & 255]);
    return o.inst == inst ? o : dummy_;
  }
  void pop_ref(const Closer& cl) {
    live_.erase(ref_.back().k);
    closer_[ref_.back().k] = cl;
    ref_.pop_back();
  }
  uint32_t named(uint64_t inst) const {
    auto it = named_.find(inst);
    return it == named_.end() ? 0 : it->second;
  }
  // The path index of the call an occupant pushed, or ~0 (not on the path).
  uint64_t occ_k(const Occ& oc) const {
    auto it = path_.find((oc.inst << 6) | oc.pos);
    return it == path_.end() ? ~uint64_t(0) : it->second;
  }

  int classify(uint64_t k, uint64_t pc, uint64_t tgt, uint8_t pos,
               uint8_t src, bool trap, bool matched, const RefEnt& top,
               const IObs& o, uint64_t rec_tgt) {
    // R1-R3: not a RAS prediction to judge.
    if (trap) return note(C_TRAP, k, pc, tgt, o, top, "");
    if (!matched) return note(C_REF_UNMATCHED, k, pc, tgt, o, top, "");
    if (src == S_NONE) return note(C_PD_RET, k, pc, tgt, o, top, "");
    // R4: the return made no p2 pop at its position.
    bool p2pop = o.p2 && o.ftb && o.applied && o.pop_s >= 0 &&
                 o.pos[o.pop_s] == pos;
    if (!p2pop) {
      if ((o.rep & REP_MISS_POP) && o.rep_applied)
        return note(C_P3_REACH, k, pc, tgt, o, top, "");
      return note(C_P1_ONLY, k, pc, tgt, o, top, "");
    }
    // R5: the call the reference names, C_T. A C1 push made after the
    // call's take is read from the record by instance (BP-152).
    IObs ct = top.obs;
    {
      auto pr = pd_by_inst_.find(ct.inst);
      if (!ct.pd_push && pr != pd_by_inst_.end()) {
        ct.pd_push = true;
        ct.pd_pos = pr->second.pos; ct.pd_seq = pr->second.seq;
        ct.pd_aidx = pr->second.aidx; ct.pd_ft = pr->second.ft;
      }
    }
    bool p2push = ct.p2 && ct.ftb && ct.push_s >= 0 &&
                  ct.pos[ct.push_s] == top.pos;
    bool p3push = (ct.rep & REP_MISS_PUSH) && ct.rep_applied &&
                  ct.rep_seq != 0;
    // BP-152, C1: the push on the restore of the call's predecode
    // redirect, at the call's position.
    bool pdpush = ct.pd_push && ct.pd_pos == top.pos;
    if (!p2push && !p3push && !pdpush) {
      if (top.src == S_NONE) {
        if (top.ind) n_call_pd_ind++;
        return note(C_CALL_PD, k, pc, tgt, o, top, top.ind ? "ind" : "dir");
      }
      return note(C_CALL_P1, k, pc, tgt, o, top, "");
    }
    if (p2push && !ct.applied && !p3push && !pdpush)
      return note(C_CALL_DROP, k, pc, tgt, o, top, "");
    if (p2push && (ct.rep & (REP_UNDO_PUSH | REP_UNDO_RC)) && ct.rep_applied)
      return note(C_CALL_UNDONE, k, pc, tgt, o, top, "");
    uint64_t cft = p2push ? ct.ft : pdpush ? ct.pd_ft : 0;
    if ((p2push || pdpush) && cft != top.addr)
      return note(C_CALL_ADDR, k, pc, tgt, o, top, "");
    if (p2push && ct.kind == 2) return note(C_RCTR_SAT, k, pc, tgt, o, top, "");
    // R6: true depth, the commit stack cannot hold T.
    if (top.max_above >= uint64_t(RC))
      return note(C_DEPTH, k, pc, tgt, o, top, "");
    // R7: the pop's result.
    if (!o.popv) return note(C_POP_EMPTY, k, pc, tgt, o, top, "");
    if (o.pop_addr == tgt) return note(C_TGT_OK, k, pc, tgt, o, top, "");
    // R8: C_T's entry reused by a later allocation before R's p2, and R's
    // pop read the speculative stack (BP-152: with B1 a pop whose link
    // was killed reads empty and R9 decides it).
    uint64_t cseq = p2push ? ct.aseq : p3push ? ct.rep_seq : ct.pd_seq;
    uint8_t  cidx = p2push ? ct.aidx : p3push ? ct.rep_aidx : ct.pd_aidx;
    // BP-152: and the pop read C_T's slot itself, the reused one: the
    // definition of stale_below_bos (BP-151, "a pop follows a link into
    // a slot below BOS that the allocator has reused"). A pop that read
    // another entry, with C_T's slot reused elsewhere, is decided by R10.
    if (!o.pop_empty && o.pre == cidx) {
      auto it = evict_.find(cseq);
      if (cseq != 0 && it != evict_.end() && it->second.cyc < o.p2_cyc)
        return note(it->second.victim_cmt ? C_STALE : C_WRAP, k, pc, tgt, o,
                    top, "");
    }
    // R8b: C_T's entry taken off the stack by an earlier on-path return's
    // pop (an error that return made, carried by its restore).
    {
      auto it = popper_.find(cseq);
      if (cseq != 0 && it != popper_.end() && it->second.cyc < o.p2_cyc) {
        auto rk = path_ret_.find(it->second.inst);
        if (rk != path_ret_.end() && rk->second < k)
          return note(C_PROPAG, k, pc, tgt, o, top, "");
      }
    }
    bool rewind = false, offp = false, skip = false;
    for (uint64_t sc : skip_cyc_)
      if (sc > ct.p2_cyc && sc < o.p2_cyc) skip = true;
    for (auto& r : rst_log_) {
      if (r.cyc <= ct.p2_cyc || r.cyc > o.p2_cyc) continue;
      if (r.rewind) rewind = true;
      // a restore to a block younger than C_T whose snapshot holds an
      // operation the redirect shows is off the path
      if (r.op_after && r.inst >= ct.inst) offp = true;
    }
    // R9: the speculative stack read empty with C_T's entry intact.
    if (o.pop_empty) {
      if (p2push && ct.kind == 1 && cidx == o.bos)
        return note(C_FB_RCTR_BOS, k, pc, tgt, o, top, "");
      // C_T not committed: a sentinel skip since its push left its entry
      // unreachable (the wrap, PU3), or (BP-152) its entry reallocated
      // and its link killed (B1: the allocator came round to an entry
      // not yet committed, the wrap), else a restore's snapshot.
      {
        auto ev = evict_.find(cseq);
        if (cseq != 0 && ev != evict_.end() && ev->second.cyc < o.p2_cyc &&
            ct.inst > o.cmt_inst)
          skip = true;
      }
      if (ct.inst > o.cmt_inst)
        return note(skip ? C_WRAP : offp ? C_SNAP_AFTER
                    : rewind ? C_BOS_REWIND : C_FB_UNCMT,
                    k, pc, tgt, o, top, "");
      // C_T had committed: the commit stack's top decides.
      auto it = path_inst_.find(o.cocc.inst);
      uint64_t ck = it == path_inst_.end() ? ~uint64_t(0) : it->second;
      if (!o.cocc.v || ck == ~uint64_t(0))
      {
        // The commit stack's top was pushed by an entry none of whose
        // path instructions is a call: a class conflict at one of its
        // PCs (the image's class is not the trace's), else a call slot
        // the walk committed though the path left the entry before it.
        if (conflict_.count(o.cocc.inst))
          return note(C_CMT_NONCALL, k, pc, tgt, o, top, "");
        if (trap_inst_.count(o.cocc.inst)) n_cmt_unexec_trap++;
        return note(C_CMT_TRAP, k, pc, tgt, o, top, "");
      }
      if (ck == top.k) return note(C_CMT_ADDR, k, pc, tgt, o, top, "");
      if (!live_.count(ck)) {
        // BP-152: with A1 the fallback reads the frame at the speculative
        // depth, so a closed frame there was closed by a return that took
        // nothing off the depth: decided by its closer, as in R10.
        auto cit = closer_.find(ck);
        if (cit != closer_.end()) {
          const Closer& c2 = cit->second;
          const IObs& ro = c2.obs;
          bool rpop = ro.p2 && ro.ftb && ro.applied && ro.pop_s >= 0;
          if (!rpop && !((ro.rep & REP_MISS_POP) && ro.rep_applied)) {
            if (c2.src == S_NONE)
              return note(C_RET_PD, k, pc, tgt, o, top, "fb");
            return note(C_RET_NOPOP, k, pc, tgt, o, top, "fb");
          }
        }
        return note(C_FB_STALE, k, pc, tgt, o, top, "");
      }
      return note(offp ? C_SNAP_AFTER : rewind ? C_BOS_REWIND : C_CMT_LOST,
                  k, pc, tgt, o, top, "");
    }
    // R10: TOSR at another entry, e, with C_T's entry intact.
    uint64_t ek = occ_k(o.pocc);
    if (ek != ~uint64_t(0) && !live_.count(ek)) {
      // e is a closed frame: the return that closed it, R'.
      auto it = closer_.find(ek);
      if (it != closer_.end()) {
        const Closer& c2 = it->second;
        const IObs& ro = c2.obs;
        bool rpop = ro.p2 && ro.ftb && ro.applied && ro.pop_s >= 0;
        if (ro.rep && ro.rep_applied && named(ro.inst) > 0)
          return note(C_SNAP_REP, k, pc, tgt, o, top, "");
        if (c2.src == S_NONE) return note(C_RET_PD, k, pc, tgt, o, top, "");
        if (!rpop && !((ro.rep & REP_MISS_POP) && ro.rep_applied))
          return note(C_RET_NOPOP, k, pc, tgt, o, top, "");
        // R' popped another entry than e: R' was itself wrong.
        if (rpop && !ro.pop_empty && ro.pocc.seq != o.pocc.seq)
          return note(C_PROPAG, k, pc, tgt, o, top, "");
      }
      return note(offp ? C_SNAP_AFTER
                  : rewind ? C_BOS_REWIND : C_EXTRA_CLOSED, k, pc, tgt, o,
                  top, "");
    }
    if (ek == ~uint64_t(0)) {
      if (named_after_.count(o.pocc.inst))
        return note(C_SNAP_AFTER, k, pc, tgt, o, top, "");
      return note(rewind ? C_BOS_REWIND : C_EXTRA_OFFPATH, k, pc, tgt, o,
                  top, "");
    }
    if (ek < top.k)
      return note(offp ? C_SNAP_AFTER : rewind ? C_BOS_REWIND : C_EXTRA_DEEP,
                  k, pc, tgt, o, top, "");
    return note(C_OTHER, k, pc, tgt, o, top, "");
  }

  int note(int c, uint64_t k, uint64_t pc, uint64_t tgt, const IObs& o,
           const RefEnt& top, const char* why) {
    if (dump && dumped[c] < dump) {
      dumped[c]++;
      std::fprintf(stderr,
          "RCLS %s k %" PRIu64 " pc %" PRIx64 " tgt %" PRIx64 " %s | ret "
          "p2 %d ftb %d ap %d pop_s %d empty %d v %d pre %d tosw %d bos %d "
          "csp %d cnt %d addr %" PRIx64 " occ seq %" PRIu64 " inst %" PRIu64
          " k %" PRId64 " addr %" PRIx64 " rep %d | call k %" PRIu64
          " src %d p2 %d ftb %d ap %d push_s %d kind %d aidx %d aseq %" PRIu64
          " ft %" PRIx64 " rep %d/%d n_named %u | last rst cyc %" PRIu64
          " pd %d after %d rep %d | ref %zu | cocc %d inst %" PRIu64
          " addr %" PRIx64 " cmt_inst %" PRIu64 " call inst %" PRIu64 "\n",
          cause_name(c), k, pc, tgt, why, int(o.p2), int(o.ftb),
          int(o.applied), o.pop_s, int(o.pop_empty), int(o.popv),
          int(o.pre), int(o.tosw), int(o.bos), int(o.csp), int(o.cnt),
          o.pop_addr, o.pocc.seq, o.pocc.inst, int64_t(occ_k(o.pocc)),
          o.pocc.addr, int(o.rep), top.k, int(top.src), int(top.obs.p2),
          int(top.obs.ftb), int(top.obs.applied), top.obs.push_s,
          int(top.obs.kind), int(top.obs.aidx), top.obs.aseq, top.obs.ft,
          int(top.obs.rep), int(top.obs.rep_applied), top.obs.n_named,
          last_rst_.cyc, int(last_rst_.pd), int(last_rst_.op_after),
          int(last_rst_.rep), ref_.size(), int(o.cocc.v), o.cocc.inst,
          o.cocc.addr, o.cmt_inst, top.obs.inst);
      // BP-152: for a fallback, the index read and the commit stack's
      // top entries, newest first, each with its reference state (L live,
      // C closed, - not on the path).
      if (o.pop_empty) {
        std::fprintf(stderr, "   FB fbi %d n %d csp %d:", int(o.fbi), o.fbn,
                     int(o.csp));
        for (int j = 0; j < o.ncstk; j++) {
          auto it = path_inst_.find(o.cstk_inst[j]);
          char st = it == path_inst_.end() ? '-'
                  : live_.count(it->second) ? 'L' : 'C';
          char pu = pushed_inst_.count(o.cstk_inst[j]) ? 'p' : 'n';
          std::fprintf(stderr, " %c%c%" PRIx64, st, pu, o.cstk_addr[j]);
        }
        std::fprintf(stderr, "\n");
      }
      if (c == C_EXTRA_DEEP || c == C_EXTRA_OFFPATH || c == C_EXTRA_CLOSED ||
          c == C_OTHER || c == C_POP_EMPTY || c == C_CMT_LOST ||
          c == C_CMT_NONCALL || c == C_FB_UNCMT || c == C_FB_STALE ||
          c == C_BOS_REWIND || c == C_SNAP_AFTER)
        for (auto& r : rst_log_)
          if (r.cyc > top.obs.p2_cyc && r.cyc <= o.p2_cyc)
            std::fprintf(stderr, "   RST cyc %" PRIu64 " inst %" PRIu64
                         " idx %d pos %d pd %d after %d rep %d cmt %d snap "
                         "%d/%d/%d\n", r.cyc, r.inst, int(r.idx), int(r.pos),
                         int(r.pd), int(r.op_after), int(r.rep), int(r.cmt),
                         int(r.tosr), int(r.tosw), int(r.bos));
    }
    return c;
  }
};

}  // namespace rcls

#endif  // PERF_RAS_CLASS_H
