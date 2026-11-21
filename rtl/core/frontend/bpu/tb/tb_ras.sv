// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_ras.sv
// DATE:    2026-06-23
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking testbench for ras.sv (BP-063, BP-064).
//
// Directed cases TC-01 .. TC-71. TC-01 .. TC-20 from BP-063; TC-21
// (BP-064) pinned TD #78 (undo-pop did not reverse a recursion pop)
// until BP-133 fixed it.
// TC-22 .. TC-28 (BP-119, TD#152) are RETURN_CALL, the JALR that pops
// then pushes (ras_decisions.md 2, RAS-DS1): at p2, in the p3 repair,
// and at commit (IC-RAS-10). TC-29 .. TC-33 (BP-120, TD#159) are the
// next-on-stack link (ras_decisions.md 3.2, ruled session-075): the
// pop-then-push sequence, the p3 repair rows on the link, the restore
// after wrong-path pops and pushes, and the return-call pairings the
// repair table does not specify. TC-36 and TC-37 (BP-126, TD#121)
// are the full commit stack: 32 pushes read non-empty. BP-133 (TD
// #78) changed TC-21 from a pin of the non-reversing undo-pop to a
// check that the undo restores the recursion count, and added TC-38
// (the undo of a whole RETURN_CALL restores the counts it changed) and
// TC-39 (TD #79: the commit stack keeps recursion depth as repeated
// entries). BP-134 added TC-40 (the undo of a push that met a
// saturated recursion count leaves the count saturated). BP-138 added
// TC-41 (a commit moves BOS past an empty speculative stack: the next
// pop takes the commit-stack fallback), TC-42 (the same across a
// restore of a snapshot taken on either side of the BOS advance) and
// TC-43 (a p3 undo of an operation that began on an empty stack after
// a commit moved BOS). BP-140 added TC-44 (a RETURN commit whose
// snapshot is an empty stack leaves BOS on the entry the return popped,
// not on the reused slot its snapshot names). BP-141 added TC-45
// (TD#194: a recursion count changed on the wrong path, then a
// redirect); BP-142 built TD#194 option A and runs it by default.
// BP-142 (Problem 2) added a REFERENCE MODEL written from
// ras_decisions.md 12, compared with the DUT every cycle of every case
// (see REFERENCE MODEL below), and (Problem 3) TC-46 .. TC-65, directed
// cases for the rules of ras_decisions.md 12.1 to 12.13 with their
// boundaries; each check name carries the rule IDs it checks. BP-143
// changed the model's chain test to the session-084 ruling (TOSR below
// BOS is not a fault; see THE CHAIN below), runs TC-65 by default with
// the rule's values, and added TC-66 (fd07: CO6 keeps TOSR off the old
// BOS slot) and TC-67 (a chain entry below BOS reused before the
// sentinel skip: the wrap, counted). BP-144 added the converse of IV1
// to the model (THE CONVERSE below) and TC-68 .. TC-71, the rules
// ras_decisions.md 12 checked in part until then: TC-68 the boundary
// of the converse (TOSR == BOS on the entry BOS names), TC-69 the
// repair rules at each slot and the count's ends, and IV2 in a repair
// cycle, TC-70 SL2 on an empty stack whose BOS entry has a count,
// TC-71 KP1 and KP2 at slot S1.
// BP-152 (RAS-4) added the depth, the generation and the C1 group to the
// model (see the REFERENCE MODEL), changed TC-41, TC-42, TC-64, TC-66
// and TC-67 to the new rules (each case says what it read), and added
// TC-73 (A1, the fallback at the speculative depth), TC-74 (B1, the
// allocation onto TOSR and the stale restore), TC-75 (C1, the
// predecode operation on the restore) and TC-76 (the undo of the
// restored block's own push). Every one of them fails with its rule
// switched off (BP-152 Results Capture).
// No case uses a seed, an LFSR or random stimulus.
// Each case is self-contained: it resets, seeds any required state
// explicitly, and does not rely on state left by a prior case.
//
// Pointer model (post BP-063 fix): the BOS index is a sentinel. A
// push that would allocate on BOS (cold-start, or full wrap) skips to
// BOS+1, so a single live entry is distinguishable from empty
// (TOSR==BOS; BP-138 keeps that exact when a commit moves BOS, the
// case TC-41 builds). TOSW is monotonic across pops so popped
// entries survive for pointer-only mispredict restore. Since BP-120 a
// push writes TOSR into the new entry's nos and a pop sets TOSR to
// the popped entry's nos (it read TOSR-1).
//
// p3 protocol (IC-RAS-11): ras_pred_val_p3 / ras_br_type_p3 are the
// one-cycle-registered p2 inputs. drive() drives p3 from the previous
// cycle's p2 so the p3 repair pass is a no-op; force_p3() overrides p3
// to exercise a deliberate p2/p3 disagreement (TC-16, TC-17).
//
// Internal state (tosr/tosw/bos/csp, spec_ret_addr, spec_rctr,
// commit_ret_addr) is observed read-only via hierarchical references;
// rctr and csp are not exposed on the port list.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  // -----------------------------------------------------------------
  // Clock and reset
  // -----------------------------------------------------------------
  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // -----------------------------------------------------------------
  // DUT port signals (names match ras.sv exactly)
  // -----------------------------------------------------------------
  logic [VA_WIDTH-1:0] tos_addr_p0  [0:NUM_PRED_SLOTS-1];
  logic                tos_valid_p0 [0:NUM_PRED_SLOTS-1];

  logic                pred_val_p2  [0:NUM_PRED_SLOTS-1];
  bp_br_type_e         br_type_p2   [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] fall_p2      [0:NUM_PRED_SLOTS-1];

  logic [VA_WIDTH-1:0] pop_addr_p2  [0:NUM_PRED_SLOTS-1];
  logic                pop_valid_p2 [0:NUM_PRED_SLOTS-1];
  bp_ras_snapshot_t    snap_p2      [0:NUM_PRED_SLOTS-1];
  // BP-153: the pop each slot would make, popping or not.
  logic [VA_WIDTH-1:0] peek_addr_p2  [0:NUM_PRED_SLOTS-1];
  logic                peek_valid_p2 [0:NUM_PRED_SLOTS-1];
  // BP-153 (TD#149): the p3 block's snapshot after its repair.
  logic                rep_val;
  bp_ras_snapshot_t    rep_snap;

  logic                pred_val_p3  [0:NUM_PRED_SLOTS-1];
  bp_br_type_e         br_type_p3   [0:NUM_PRED_SLOTS-1];

  logic                restore_val;

  logic                p2_keep;     // BP-121: p2 pass kept unless dropped
  bp_ras_snapshot_t    restore_snap;

  logic                commit_val;
  bp_br_type_e         commit_br_type;
  logic [VA_WIDTH-1:0] commit_ret_addr;
  bp_ras_snapshot_t    commit_snap;

  logic                flush_val;
  bp_ras_snapshot_t    flush_snap;

  // BP-152, C1: the predecode operation on the restore, and the
  // snapshot after it.
  logic                pd_val;
  bp_br_type_e         pd_type;
  logic [VA_WIDTH-1:0] pd_ret;
  logic                rs_undo;   // BP-152: undo the block's own push
  logic                rs_undo_pop;   // BP-153: and its own pop
  bp_ras_snapshot_t    pd_snap;

  // -----------------------------------------------------------------
  // DUT
  // -----------------------------------------------------------------
  ras dut (
    .clk                  (clk),
    .rstn                 (rstn),
    .ras_tos_addr_p0      (tos_addr_p0),
    .ras_tos_valid_p0     (tos_valid_p0),
    .ras_pred_val_p2      (pred_val_p2),
    .ras_br_type_p2       (br_type_p2),
    .ras_fall_through_p2  (fall_p2),
    .ras_pop_addr_p2      (pop_addr_p2),
    .ras_pop_valid_p2     (pop_valid_p2),
    .ras_snapshot_p2      (snap_p2),
    .ras_peek_addr_p2     (peek_addr_p2),          // BP-153
    .ras_peek_valid_p2    (peek_valid_p2),
    .ras_rep_val          (rep_val),               // BP-153, TD#149
    .ras_rep_snapshot     (rep_snap),
    .ras_pred_val_p3      (pred_val_p3),
    .ras_br_type_p3       (br_type_p3),
    .ras_restore_val      (restore_val),
    .ras_p2_keep          (p2_keep),
    .ras_restore_snapshot (restore_snap),
    .ras_commit_val       (commit_val),
    .ras_commit_br_type   (commit_br_type),
    .ras_commit_ret_addr  (commit_ret_addr),
    .ras_commit_snapshot  (commit_snap),
    .ras_flush_val        (flush_val),
    .ras_flush_snapshot   (flush_snap),
    .ras_pd_val           (pd_val),
    .ras_pd_br_type       (pd_type),
    .ras_pd_ret_addr      (pd_ret),
    .ras_rs_undo          (rs_undo),
    .ras_rs_undo_pop      (rs_undo_pop),
    .ras_pd_snapshot      (pd_snap)
  );

  // -----------------------------------------------------------------
  // Scoreboard
  // -----------------------------------------------------------------
  int pass_cnt;
  int fail_cnt;
  int unsigned m_wpend;            // BP-143, see tc_of
  int unsigned m_wcase [string];

  // BP-143: the case a check belongs to, its name up to the first space
  // (TC-65, MODEL, ...). Wraps the model counted since the last check
  // are given to it (m_wpend, the REFERENCE MODEL below).
  function automatic string tc_of(input string nm);
    for (int i = 0; i < nm.len(); i++)
      if (nm.getc(i) == " ") return nm.substr(0, i - 1);
    return nm;
  endfunction

  task automatic check(input string nm, input logic cond);
    string tc;
    if (m_wpend != 0) begin
      tc          = tc_of(nm);
      m_wcase[tc] = m_wcase[tc] + m_wpend;
      m_wpend     = 0;
    end
    if (cond) begin
      pass_cnt++;
      $display("PASS: %s", nm);
    end else begin
      fail_cnt++;
      $display("FAIL: %s", nm);
    end
  endtask

  // -----------------------------------------------------------------
  // p2 -> p3 pipeline shadow
  // -----------------------------------------------------------------
  // S1: slot 1 in the dual-slot cases, which run only at two slots
  // (BP-128). It is NUM_PRED_SLOTS-1 so the one-slot build has no
  // constant out-of-range index.
  localparam int S1 = NUM_PRED_SLOTS - 1;

  logic        prev_val [0:NUM_PRED_SLOTS-1];
  bp_br_type_e prev_typ [0:NUM_PRED_SLOTS-1];

  // Drive p3 from previous cycle's p2 (no-op repair) and set p2.
  task automatic drive(
      input logic                v0, input bp_br_type_e t0,
      input logic [VA_WIDTH-1:0] f0,
      input logic                v1, input bp_br_type_e t1,
      input logic [VA_WIDTH-1:0] f1);
    // BP-128: the slot 1 operands apply only at two slots (a loop, so
    // the build at one slot has no constant out-of-range index).
    pred_val_p3[0] = prev_val[0]; br_type_p3[0] = prev_typ[0];
    pred_val_p2[0] = v0; br_type_p2[0] = t0; fall_p2[0] = f0;
    for (int s = 1; s < NUM_PRED_SLOTS; s++) begin
      pred_val_p3[s] = prev_val[s]; br_type_p3[s] = prev_typ[s];
      pred_val_p2[s] = v1; br_type_p2[s] = t1; fall_p2[s] = f1;
    end
  endtask

  // Override p3 explicitly (deliberate p2/p3 disagreement).
  task automatic force_p3(
      input logic v0, input bp_br_type_e t0,
      input logic v1, input bp_br_type_e t1);
    pred_val_p3[0] = v0; br_type_p3[0] = t0;
    for (int s = 1; s < NUM_PRED_SLOTS; s++) begin   // BP-128
      pred_val_p3[s] = v1; br_type_p3[s] = t1;
    end
  endtask

  // Advance one clock; remember this cycle's p2 for next cycle's p3.
  task automatic tick();
    @(posedge clk);
    #1;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin   // BP-128
      prev_val[s] = pred_val_p2[s]; prev_typ[s] = br_type_p2[s];
    end
  endtask

  // Drive a commit event for one cycle (p2 idle), then settle.
  task automatic commit_op(input bp_br_type_e bt,
                           input logic [VA_WIDTH-1:0] ra,
                           input logic [RAS_PTR_BITS-1:0] snap_tosr);
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    commit_val          = 1'b1;
    commit_br_type      = bt;
    commit_ret_addr     = ra;
    commit_snap.tosr    = snap_tosr;
    commit_snap.tosw    = '0;
    commit_snap.bos     = '0;
    // BP-152 A1: the committed block's depth, as its own snapshot would
    // carry it: the dep of the last kept p2 snapshot the model formed
    // with this TOSR (m_dep_at), else, for a block that operated nothing
    // (a commit with no p2 operation), the speculative depth now. The
    // model's record, not the DUT's. Before BP-152 dep and tag did not
    // exist.
    commit_snap.dep     = m_dep_at.exists(snap_tosr) ? m_dep_at[snap_tosr]
                                                     : m_s.dsp;
    commit_snap.tag     = '0;
    tick();
    commit_val          = 1'b0;
    commit_br_type      = NO_BRANCH;
    commit_ret_addr     = '0;
    commit_snap         = '0;
  endtask

  // Synchronous reset, plus one edge so ras_rst_done is set.
  task automatic do_reset();
    rstn = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      pred_val_p2[s] = 1'b0; br_type_p2[s] = NO_BRANCH; fall_p2[s] = '0;
      pred_val_p3[s] = 1'b0; br_type_p3[s] = NO_BRANCH;
      prev_val[s]    = 1'b0; prev_typ[s]   = NO_BRANCH;
    end
    restore_val = 1'b0; restore_snap = '0; p2_keep = 1'b1;
    commit_val  = 1'b0; commit_br_type = NO_BRANCH;
    commit_ret_addr = '0; commit_snap = '0;
    flush_val   = 1'b0; flush_snap = '0;
    pd_val      = 1'b0; pd_type = NO_BRANCH; pd_ret = '0;      // BP-152
    rs_undo     = 1'b0;
    rs_undo_pop = 1'b0;                                        // BP-153
    repeat (3) @(posedge clk);
    // BP-142: rstn rises after the edge, not at it, so the DUT and the
    // reference model see the same last reset edge (no race with the
    // always_ff at the third edge).
    #1;
    rstn = 1'b1;
    @(posedge clk);
    #1;
  endtask

  // BP-142: drive one slot, every other slot idle, p3 from the previous
  // cycle's p2 (no repair). sl may be 0 or S1.
  task automatic drv(input int sl, input logic v, input bp_br_type_e t,
                     input logic [VA_WIDTH-1:0] f);
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      pred_val_p3[s] = prev_val[s]; br_type_p3[s] = prev_typ[s];
      pred_val_p2[s] = 1'b0; br_type_p2[s] = NO_BRANCH; fall_p2[s] = '0;
    end
    pred_val_p2[sl] = v; br_type_p2[sl] = t; fall_p2[sl] = f;
  endtask

  // BP-142: an idle cycle (p2 idle, p3 agrees).
  task automatic idle();
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    tick();
  endtask

  // BP-142: a pop at slot sl, checked against an expected valid and
  // address (the address only when valid, PO6), then the edge.
  task automatic pop_chk(input string nm, input int sl, input logic ev,
                         input logic [VA_WIDTH-1:0] ea);
    drv(sl, 1'b1, RETURN, '0);
    #1;
    check(nm, (pop_valid_p2[sl] == ev) && (!ev || (pop_addr_p2[sl] == ea)));
    tick();
  endtask

  // BP-142: the DUT's speculative entry i against expected fields.
  function automatic logic ent_is(input int i,
                                  input logic [VA_WIDTH-1:0] a,
                                  input logic [RAS_RCTR_WIDTH-1:0] c,
                                  input logic [RAS_PTR_BITS-1:0] n,
                                  input logic b);
    return (dut.spec_ret_addr[i] == a) && (dut.spec_rctr[i] == c) &&
           (dut.spec_nos[i] == n) && (dut.spec_bot[i] == b);
  endfunction

  // BP-142: the DUT's pointers against expected values.
  function automatic logic ptr_is(input int r, input int w, input int b);
    return (int'(dut.tosr) == r) && (int'(dut.tosw) == w) &&
           (int'(dut.bos) == b);
  endfunction

  // Push one address on slot 0 (slot 1 idle), commit a cycle.
  task automatic push_one(input logic [VA_WIDTH-1:0] a);
    drive(1'b1, DIRECT_CALL, a, 1'b0, NO_BRANCH, '0);
    tick();
  endtask

  // TC-36 / TC-37 commit-stack test address: base plus 4 per push.
  function automatic logic [VA_WIDTH-1:0] cs_ad(input int base,
                                                input int i);
    return VA_WIDTH'(base + 4 * i);
  endfunction

  // =================================================================
  // REFERENCE MODEL (BP-142, Problem 2). Written from ras_decisions.md
  // 12 and the sections it cites, not from ras.sv. It keeps its own
  // state: the speculative stack (every entry's ret_addr, rctr, nos and
  // bot; TOSR, TOSW, BOS), the commit stack (every entry, CSP, the
  // count) and the p2 -> p3 registers the repair needs. It is stepped
  // from the DUT's inputs only. The DUT's state is read only to compare
  // with it (m_compare), never to step the model.
  //
  // Timing. The testbench drives inputs at posedge + 1 and + 2. At the
  // negedge the model forms this cycle's outputs and next state from
  // its state and the inputs (m_eval) and compares; at the posedge the
  // next state becomes the state (m_step). Reset (RT1) is applied at a
  // posedge with rstn low, as the DUT's synchronous reset is.
  //
  // THE CHAIN (IV1, PO7; BP-143, ruled session-084). Each speculative
  // index carries the sequence number of its last allocation (seq; PU1,
  // PU2, RP7 allocate, nothing else does). Beside the pointers the model
  // keeps which allocation they refer to: tref, the allocation TOSR
  // names, and per entry nref, the allocation its link names (0, none,
  // for a bottom entry, whose pop goes to BOS). A push sets tref to the
  // new allocation and records the old tref as the new entry's nref; a
  // pop that follows the link takes tref from nref; an undo takes the
  // tref registered with the operation; a restore takes the tref the
  // model recorded when it produced that snapshot (m_sref), or, for a
  // snapshot the model never produced, the allocation the index holds.
  // A chain entry is a TOSR with tref != 0, above or below BOS. With
  // TOSR != BOS and tref == 0 the state fails IV1 (every cycle) and PO7
  // (every pop of every slot, repair cycles included: IV2). A chain
  // entry whose index was reallocated since (seq[tosr] != tref) is the
  // wrap (PO7, PU3, RE7): counted, not failed. The model decides this
  // from its own state; it reads the DUT only to compare with it.
  // TOSR == BOS is the empty stack (IV1): tref is none there, and the
  // entry at BOS is the sentinel, never a chain entry (PO7).
  // Until BP-143 the model held TOSR only when TOSR was allocated after
  // BOS (seq[tosr] > seq[bos]), the meaning session-084 replaced.
  //
  // THE CONVERSE (IV1 "exactly when", PO7 "never the BOS sentinel";
  // BP-144). The model also keeps bref, the allocation BOS names: the
  // entry whose commit made it the boundary. A commit that moves BOS
  // (CO5) takes the allocation its snapshot's TOSR named (m_sref, or
  // for a snapshot the model never produced the allocation the index
  // holds; none for a snapshot of an empty stack); a restore takes the
  // bref the model recorded with that snapshot (m_sbref). TOSR == BOS
  // while tref names a live chain entry other than bref, one whose
  // index still holds it, fails: BOS moved onto a live entry, or TOSR
  // was left on one, and the stack reads empty over it (BP-143 Problem
  // 5, TC-44). Checked on the model's next state every cycle and at
  // every pop (m_iv); a chain entry at BOS reused since is the wrap,
  // counted in m_nbwrap. The DUT is checked against the same record:
  // DUT TOSR == DUT BOS where the model's TOSR names a live chain entry
  // at that index fails (m_dut_conv), so the fault shows as this rule,
  // not only as a BOS mismatch.
  //
  // BP-152 (RAS-4), the three rules for acceptance, written from the
  // BP-152 Results Capture's proposed text, not from ras.sv:
  //   A1  the model keeps the speculative depth (dsp, in its snapshots)
  //       and the committed depth (dcm): a push adds one and a pop takes
  //       one whatever the stack did, a repair reverses or applies its
  //       component, a restore loads the snapshot's; a RAS commit sets
  //       dcm to the committing snapshot's dep. The fallback reads
  //       the commit stack at CSP-1-n, n = dcm - dsp; CSP-1 for n below
  //       0; nothing (not valid) for n at or above the count (m_fb).
  //   B1  an allocation at index a makes bottom every other entry whose
  //       link names a, and an allocation onto the TOSR entry itself is
  //       bottom; every index has a generation (gt), advanced at each
  //       allocation, carried by a snapshot for its TOSR entry (tag) and
  //       by the p3 registers for the pre-op TOSR. A restore or an undo
  //       to an entry whose generation moved since reads empty.
  //   C1  with pd_val on a restore, the predecode operation is applied
  //       to the restored state by the p2 rules (pop, then push with
  //       recursion), and pd_snap is the state after it.
  // With B1 a pop never reads a reused entry: the wrap of PO7 that the
  // model counted (m_nwrap) is now a reuse the model fails, except for
  // a snapshot tag that aliased (2^RAS_TAG_BITS reallocations), which
  // no directed case builds.
  // =================================================================
  localparam int M_SEQ_W = 32;
  localparam logic [RAS_RCTR_WIDTH-1:0] M_RCTR_MAX =
    {RAS_RCTR_WIDTH{1'b1}};                              // PM1, PU6
  localparam int M_CCNT_W = RAS_COMMIT_PTR_BITS + 1;

  typedef struct packed {
    logic [VA_WIDTH-1:0]       ret;
    logic [RAS_RCTR_WIDTH-1:0] rctr;
    logic [RAS_PTR_BITS-1:0]   nos;
    logic                      bot;
    logic [RAS_RCTR_WIDTH-1:0] ncnt;   // BP-153: the count below
  } m_ent_t;

  typedef struct packed {
    m_ent_t [RAS_SPEC_ENTRIES-1:0]                e;
    logic   [RAS_SPEC_ENTRIES-1:0][M_SEQ_W-1:0]   seq;
    logic   [RAS_SPEC_ENTRIES-1:0][M_SEQ_W-1:0]   nref;  // BP-143
    logic   [RAS_SPEC_ENTRIES-1:0][RAS_TAG_BITS-1:0] gt; // BP-152 B1
    logic   [M_SEQ_W-1:0]                         tref;  // BP-143
    logic   [M_SEQ_W-1:0]                         bref;  // BP-144
    logic   [M_SEQ_W-1:0]                         gen;
    logic   [RAS_PTR_BITS-1:0]                    tosr;
    logic   [RAS_PTR_BITS-1:0]                    tosw;
    logic   [RAS_PTR_BITS-1:0]                    bos;
    logic   [RAS_DEPTH_BITS-1:0]                  dsp;   // BP-152 A1
  } m_spec_t;

  typedef struct packed {
    logic [RAS_COMMIT_ENTRIES-1:0][VA_WIDTH-1:0] a;
    logic [RAS_COMMIT_PTR_BITS-1:0]              csp;
    logic [M_CCNT_W-1:0]                         cnt;
    logic [RAS_DEPTH_BITS-1:0]                   dcm;     // BP-152 A1
  } m_cs_t;

  // What the push did (RP1 to RP3, RP8).
  localparam logic [1:0] M_PK_NONE  = 2'd0;
  localparam logic [1:0] M_PK_ALLOC = 2'd1;
  localparam logic [1:0] M_PK_INC   = 2'd2;
  localparam logic [1:0] M_PK_SAT   = 2'd3;

  typedef struct packed {
    logic                    pop;        // RP0: the registered p2 op
    logic                    push;
    logic [VA_WIDTH-1:0]     ft;         // RP7
    logic [RAS_PTR_BITS-1:0] pre_tosr;   // RP4, RP8
    logic [RAS_TAG_BITS-1:0] pre_tag;    // BP-152 B1: its generation
    logic [M_SEQ_W-1:0]      pre_tref;   // the allocation pre_tosr names
    logic                    pre_empty;  // RP5
    logic                    pop_dec;    // RP4, RP8
    logic [1:0]              push_kind;  // RP1 to RP3, RP8
    logic [RAS_PTR_BITS-1:0] push_ptr;   // the count a push raised
  } m_p3_t;

  m_spec_t m_s;     // speculative stack, as of this cycle
  m_cs_t   m_c;     // commit stack
  m_p3_t   m_q  [0:NUM_PRED_SLOTS-1];
  m_spec_t m_ns;    // next state, formed at the negedge
  m_cs_t   m_nc;
  m_p3_t   m_nq [0:NUM_PRED_SLOTS-1];
  logic    m_live;  // the model has seen a reset

  // This cycle's model outputs.
  logic                m_tos_valid;
  logic [VA_WIDTH-1:0] m_tos_addr;
  logic                m_pop_valid [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] m_pop_addr  [0:NUM_PRED_SLOTS-1];
  logic                m_peek_valid [0:NUM_PRED_SLOTS-1];  // BP-153
  logic [VA_WIDTH-1:0] m_peek_addr  [0:NUM_PRED_SLOTS-1];
  bp_ras_snapshot_t    m_snap      [0:NUM_PRED_SLOTS-1];
  bp_ras_snapshot_t    m_pd_snap;   // BP-152 C1, with restore_val
  // BP-152: pops that read a reused entry (B1 says none).
  int unsigned         m_nreuse;
  // BP-152: the dep of the last kept p2 snapshot by its TOSR, for
  // commit_op's stimulus (the committed block's own dep). Cleared at
  // reset.
  logic [RAS_DEPTH_BITS-1:0] m_dep_at [logic [RAS_PTR_BITS-1:0]];

  int unsigned m_ncmp;      // comparisons made
  int unsigned m_nmis;      // mismatches
  int unsigned m_niv;       // IV1 / IV2 (PO7) violations
  int unsigned m_cyc;       // cycles since the last reset
  // BP-143: pops of a reused chain entry (the wrap, PO7), in total, not
  // yet given to a case, and per case (the TC name of the next check).
  // m_wpend and m_wcase are declared with the scoreboard.
  int unsigned m_nwrap;
  // BP-143: the tref of each snapshot value the model produced (SL2),
  // read by a restore (RE1). Cleared at reset.
  logic [M_SEQ_W-1:0] m_sref [logic [$bits(bp_ras_snapshot_t)-1:0]];
  // BP-144: the bref of each snapshot value the model produced, read by
  // a restore; the converse failures (IV1) and wraps at BOS.
  logic [M_SEQ_W-1:0] m_sbref [logic [$bits(bp_ras_snapshot_t)-1:0]];
  int unsigned m_nconv;
  int unsigned m_nbwrap;

  // BP-144: the converse of IV1 at a working state. live 1: TOSR == BOS
  // over a chain entry other than the one BOS names, still held at its
  // index (a fault); live 0: the same over an index reused since (the
  // wrap).
  function automatic logic m_conv(input m_spec_t s, input logic live);
    return (s.tosr == s.bos) && (s.tref != '0) && (s.tref != s.bref) &&
           ((s.seq[s.tosr] == s.tref) == live);
  endfunction

  function automatic logic m_empty(input m_spec_t s);
    return s.tosr == s.bos;                              // IV1, 3.2
  endfunction

  // A chain entry at TOSR (IV1, PO7): the model's tref names one.
  function automatic logic m_chain(input m_spec_t s);
    return !m_empty(s) && (s.tref != '0);
  endfunction

  // A chain entry whose index was reallocated since: the wrap (PO7).
  function automatic logic m_reused(input m_spec_t s);
    return m_chain(s) && (s.seq[s.tosr] != s.tref);
  endfunction

  // Remove the top by its link (PO2, PO3, RP1): TOSR to nos, or to BOS
  // as it is then for a bottom entry; tref follows (BP-143).
  // BP-153: PO2 to a live entry gives it the count the popped entry
  // recorded at its allocation (ncnt).
  function automatic m_spec_t m_unlink(input m_spec_t s);
    m_spec_t                   r;
    logic [RAS_RCTR_WIDTH-1:0] nc;
    r = s;
    if (r.e[r.tosr].bot) begin                           // PO3
      r.tref = '0;
      r.tosr = r.bos;
    end else begin                                       // PO2
      nc     = r.e[r.tosr].ncnt;
      r.tref = r.nref[r.tosr];
      r.tosr = r.e[r.tosr].nos;
      if (!m_empty(r)) r.e[r.tosr].rctr = nc;
    end
    return r;
  endfunction

  // A pop of the speculative stack, PO1 to PO4. The caller has
  // checked the stack is not empty.
  function automatic m_spec_t m_pop_spec(input m_spec_t s,
                                         output logic dec);
    m_spec_t r;
    r   = s;
    dec = 1'b0;
    if (r.e[r.tosr].rctr != '0) begin                    // PO1
      r.e[r.tosr].rctr = r.e[r.tosr].rctr - 1'b1;
      dec = 1'b1;
    end else begin
      r = m_unlink(r);                                   // PO2, PO3
    end
    return r;
  endfunction

  // A push, PU1 to PU7. recur 0 is the missed push of RP7, which never
  // takes the recursion match.
  function automatic m_spec_t m_push(input m_spec_t             s,
                                     input logic [VA_WIDTH-1:0] ft,
                                     input logic                recur,
                                     output logic [1:0]         kind,
                                     output logic [RAS_PTR_BITS-1:0] ptr);
    m_spec_t                 r;
    logic                    skip;
    logic                    self;
    logic [RAS_PTR_BITS-1:0] al;
    r   = s;
    ptr = r.tosr;
    if (recur && !m_empty(r) && (ft == r.e[r.tosr].ret)) begin  // PU5, PU7
      if (r.e[r.tosr].rctr == M_RCTR_MAX) begin          // PU6
        kind = M_PK_SAT;
      end else begin
        kind = M_PK_INC;
        r.e[r.tosr].rctr = r.e[r.tosr].rctr + 1'b1;
      end
    end else begin
      kind = M_PK_ALLOC;
      skip = (r.tosw == r.bos);                          // PU2
      al   = skip ? (r.bos + 1'b1) : r.tosw;
      // BP-152 B1: the allocation lands on the TOSR entry itself (TOSR
      // below BOS, the allocator round to it): bottom, nothing below.
      self = !m_empty(r) && (al == r.tosr);
      // BP-152 B1: every other entry whose link names al names a reused
      // entry from now on: bottom.
      for (int j = 0; j < RAS_SPEC_ENTRIES; j++)
        if ((RAS_PTR_BITS'(j) != al) && (r.e[j].nos == al))
          r.e[j].bot = 1'b1;
      // BP-153: the count below, read before the entry is written (al
      // may be TOSR itself, the self case, which is bottom: 0).
      r.e[al].ncnt = (skip | self | m_empty(r)) ? '0 : r.e[r.tosr].rctr;
      r.e[al].ret  = ft;                                 // PU1, PU8
      r.e[al].rctr = '0;
      r.e[al].nos  = (skip | self) ? r.bos : r.tosr;
      r.e[al].bot  = skip | self | m_empty(r);
      // BP-143: the link names the allocation TOSR named; none for a
      // bottom entry.
      r.nref[al]   = (skip | self | m_empty(r)) ? '0 : r.tref;
      r.gt[al]     = r.gt[al] + 1'b1;                    // BP-152 B1
      r.gen        = r.gen + 1;
      r.seq[al]    = r.gen;
      r.tref       = r.gen;
      r.tosr       = al;
      r.tosw       = al + 1'b1;
    end
    return r;
  endfunction

  // BP-152 A1. The commit-stack fallback at the speculative depth d:
  // the frame at CSP-1-n, n = dcm - d. n below 0: CSP-1 (no committed
  // frame popped). n at or above the count: not valid (the frame is
  // gone).
  function automatic logic m_fb_v(input m_cs_t c,
                                  input logic [RAS_DEPTH_BITS-1:0] d);
    logic [RAS_DEPTH_BITS-1:0] n;
    n = c.dcm - d;
    if (n[RAS_DEPTH_BITS-1]) return c.cnt != '0;
    return int'(n) < int'(c.cnt);
  endfunction

  function automatic logic [VA_WIDTH-1:0] m_fb_a(
      input m_cs_t c, input logic [RAS_DEPTH_BITS-1:0] d);
    logic [RAS_DEPTH_BITS-1:0] n;
    n = c.dcm - d;
    if (n[RAS_DEPTH_BITS-1] || !(int'(n) < int'(c.cnt)))
      return c.a[c.csp - 1'b1];
    return c.a[c.csp - 1'b1 - RAS_COMMIT_PTR_BITS'(n)];
  endfunction

  // Step the count of entry p by one, not past 0 or the saturation
  // value (RP2, RP4, RP8: the count the p2 operation changed).
  function automatic m_spec_t m_adj(input m_spec_t s,
                                    input logic [RAS_PTR_BITS-1:0] p,
                                    input logic inc);
    m_spec_t r;
    r = s;
    if (inc && (r.e[p].rctr != M_RCTR_MAX))
      r.e[p].rctr = r.e[p].rctr + 1'b1;
    else if (!inc && (r.e[p].rctr != '0))
      r.e[p].rctr = r.e[p].rctr - 1'b1;
    return r;
  endfunction

  function automatic logic m_is_push(input logic v, input bp_br_type_e t);
    return v && ((t == DIRECT_CALL) || (t == INDIRECT_CALL) ||
                 (t == RETURN_CALL));                    // CL1
  endfunction

  function automatic logic m_is_pop(input logic v, input bp_br_type_e t);
    return v && ((t == RETURN) || (t == RETURN_CALL));   // CL2
  endfunction

  // The IV1 / PO7 check on a working state (BP-143): with TOSR != BOS,
  // TOSR names a chain entry. At a pop (wrap 1) a reused chain entry is
  // counted as the wrap; the pop then returns the reusing push's
  // address, which m_compare checks against the DUT.
  task automatic m_iv(input m_spec_t w, input int s, input string where,
                      input logic wrap);
    if (!m_empty(w) && !m_chain(w)) begin
      m_niv++;
      m_nmis++;
      $display("MODEL FAIL cyc %0d t %0t slot %0d %s: IV1/PO7", m_cyc, $time,
               s, where);
      $write("  tosr %0d != bos %0d names no chain entry: ", w.tosr, w.bos);
      $display("expected allocation none (empty); idx %0d holds alloc %0d",
               w.tosr, w.seq[w.tosr]);
    end else if (wrap && m_reused(w)) begin
      // BP-152 B1: a pop never reads a reused entry. Before BP-152 this
      // was the wrap of PO7, counted (m_nwrap) and not failed.
      m_nwrap++;
      m_wpend++;
      m_nreuse++;
      m_nmis++;
      $write("MODEL FAIL cyc %0d t %0t slot %0d %s: B1 reuse: ", m_cyc, $time,
             s, where);
      $display("tosr %0d (bos %0d) names alloc %0d, reused by alloc %0d",
               w.tosr, w.bos, w.tref, w.seq[w.tosr]);
    end
    m_ivc(w, s, where);
  endtask

  // BP-144: the converse of IV1 (THE CONVERSE above) on a working or
  // next state.
  task automatic m_ivc(input m_spec_t w, input int s, input string where);
    if (m_conv(w, 1'b1)) begin
      m_nconv++;
      m_nmis++;
      $display("MODEL FAIL cyc %0d t %0t slot %0d %s: IV1 converse", m_cyc,
               $time, s, where);
      $write("  tosr %0d == bos %0d reads empty over live alloc %0d; ",
             w.tosr, w.bos, w.tref);
      $display("bos names alloc %0d", w.bref);
    end else if (m_conv(w, 1'b0)) begin
      m_nbwrap++;
      $write("MODEL WRAP cyc %0d t %0t slot %0d %s: ", m_cyc, $time, s, where);
      $display("tosr %0d == bos names alloc %0d, reused by alloc %0d",
               w.tosr, w.tref, w.seq[w.tosr]);
    end
  endtask

  // -----------------------------------------------------------------
  // m_eval: this cycle's outputs and the next state.
  // -----------------------------------------------------------------
  task automatic m_eval();
    m_spec_t w;
    m_spec_t wr;          // after the repair alone (KP1)
    logic    vpop, vpush, d;
    logic [1:0] k;
    logic [RAS_PTR_BITS-1:0] p;
    logic    cpop, cpush, cmove;
    logic    ustale, rkeep;                                // BP-153 B1
    // BP-153: the pop record of this cycle's p2 block, and of the C1 pop.
    logic [RAS_PMODE_BITS-1:0] pp_mode;
    logic [RAS_PTR_BITS-1:0]   pp_tosr;
    logic [RAS_TAG_BITS-1:0]   pp_tag;
    logic                      pp_push;                    // BP-153

    // p0 (P01 to P05): from the state, combinationally; the fallback at
    // the speculative depth (BP-152 A1).
    m_tos_valid = !m_empty(m_s) || m_fb_v(m_c, m_s.dsp);
    m_tos_addr  = !m_empty(m_s) ? m_s.e[m_s.tosr].ret
                                : m_fb_a(m_c, m_s.dsp);

    // ---- p3 repair (RP0 to RP11), slot 0 first. ----
    w = m_s;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      vpop  = m_is_pop(pred_val_p3[s], br_type_p3[s]);     // RP0 view
      vpush = m_is_push(pred_val_p3[s], br_type_p3[s]);
      if ((vpop == m_q[s].pop) && (vpush == m_q[s].push)) continue;
      // BP-152 B1: an undo to a pre-op entry whose generation moved
      // since reads empty.
      ustale = !m_q[s].pre_empty &&
               (w.gt[m_q[s].pre_tosr] != m_q[s].pre_tag);
      if (m_q[s].pop && m_q[s].push && !vpop && !vpush) begin
        // RP8 the undo of a whole RETURN_CALL, RP5.
        w.tosr = (m_q[s].pre_empty || ustale) ? w.bos : m_q[s].pre_tosr;
        w.tref = (m_q[s].pre_empty || ustale) ? '0 : m_q[s].pre_tref;
        if (m_q[s].pop_dec && (m_q[s].push_kind == M_PK_INC)) begin
          // the pop and the push changed one count: they cancel
        end else if (m_q[s].pop_dec) begin
          w = m_adj(w, m_q[s].pre_tosr, 1'b1);
        end else if (m_q[s].push_kind == M_PK_INC) begin
          w = m_adj(w, m_q[s].push_ptr, 1'b0);
        end
      end else begin
        // RP1 to RP3: undo a push the p3 view does not have. The depth
        // is taken back in every case (BP-152 A1).
        if (m_q[s].push && !vpush) begin
          w.dsp = w.dsp - 1'b1;
          if (m_q[s].push_kind == M_PK_INC)                // RP2
            w = m_adj(w, w.tosr, 1'b0);
          else if ((m_q[s].push_kind == M_PK_ALLOC) && !m_empty(w))
            w = m_unlink(w);                               // RP1
          // RP3: a saturated push changed nothing; nor does its undo
        end
        if (m_q[s].pop && !vpop) begin                     // RP4, RP5
          w.dsp  = w.dsp + 1'b1;
          w.tosr = (m_q[s].pre_empty || ustale) ? w.bos : m_q[s].pre_tosr;
          w.tref = (m_q[s].pre_empty || ustale) ? '0 : m_q[s].pre_tref;
          if (m_q[s].pop_dec) w = m_adj(w, m_q[s].pre_tosr, 1'b1);
        end else if (!m_q[s].pop && vpop) begin            // RP6
          m_iv(w, s, "p3 missed pop", 1'b1);               // IV2, PO7
          w.dsp = w.dsp - 1'b1;
          if (!m_empty(w)) w = m_pop_spec(w, d);
        end
        if (!m_q[s].push && vpush) begin                   // RP7
          w.dsp = w.dsp + 1'b1;
          w = m_push(w, m_q[s].ft, 1'b0, k, p);
        end
      end
    end
    wr = w;

    // ---- p2 (CL1 to CL4, PO, PU, RC, SL), slot 0 first (SL1). ----
    pp_mode = RAS_POP_NONE;
    pp_tosr = '0;
    pp_tag  = '0;
    pp_push = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      m_pop_valid[s] = 1'b0;                               // PO9
      m_pop_addr[s]  = '0;
      // BP-153: the peek, the pop this slot would make, popping or not.
      m_peek_valid[s] = !m_empty(w) || m_fb_v(m_c, w.dsp);
      m_peek_addr[s]  = !m_empty(w) ? w.e[w.tosr].ret : m_fb_a(m_c, w.dsp);
      m_nq[s]           = '0;
      m_nq[s].pop       = m_is_pop(pred_val_p2[s], br_type_p2[s]);
      m_nq[s].push      = m_is_push(pred_val_p2[s], br_type_p2[s]);
      m_nq[s].ft        = fall_p2[s];
      m_nq[s].pre_tosr  = w.tosr;
      m_nq[s].pre_tag   = m_empty(w) ? '0 : w.gt[w.tosr];   // BP-152
      m_nq[s].pre_tref  = w.tref;
      m_nq[s].pre_empty = m_empty(w);
      if (m_nq[s].pop) begin                               // CL4: pop first
        // BP-153: the pop record, from the state the pop finds.
        pp_tosr = w.tosr;
        pp_tag  = m_empty(w) ? '0 : w.gt[w.tosr];
        pp_mode = m_empty(w)                 ? RAS_POP_EMPTY :
                  (w.e[w.tosr].rctr != '0)   ? RAS_POP_DEC   : RAS_POP_LINK;
        m_iv(w, s, "p2 pop", 1'b1);                        // IV2, PO7
        if (!m_empty(w)) begin
          m_pop_valid[s] = 1'b1;                           // PO1 to PO3
          m_pop_addr[s]  = w.e[w.tosr].ret;
          w = m_pop_spec(w, d);
          m_nq[s].pop_dec = d;
        end else begin                                     // PO5, PO6, A1
          m_pop_valid[s] = m_fb_v(m_c, w.dsp);
          m_pop_addr[s]  = m_fb_a(m_c, w.dsp);
        end
        w.dsp = w.dsp - 1'b1;                              // BP-152 A1
      end
      if (m_nq[s].push) begin                              // RC2
        pp_push = 1'b1;                                    // BP-153
        w = m_push(w, fall_p2[s], 1'b1, k, p);
        w.dsp = w.dsp + 1'b1;                              // BP-152 A1
        m_nq[s].push_kind = k;
        m_nq[s].push_ptr  = p;
      end
      m_snap[s].tosr = w.tosr;                             // SL2
      m_snap[s].tosw = w.tosw;
      m_snap[s].bos  = w.bos;
      m_snap[s].rctr = m_empty(w) ? '0 : w.e[w.tosr].rctr;
      m_snap[s].dep  = w.dsp;                              // BP-152
      m_snap[s].tag  = m_empty(w) ? '0 : w.gt[w.tosr];
      m_snap[s].push  = pp_push;                           // BP-153
      m_snap[s].pmode = pp_mode;
      m_snap[s].ptosr = pp_tosr;
      m_snap[s].ptag  = pp_tag;
      if (p2_keep && !restore_val && (m_nq[s].pop || m_nq[s].push))
        m_dep_at[w.tosr] = w.dsp;
      // BP-143: the allocation this snapshot's TOSR names.
      if (!m_empty(w)) m_sref[m_snap[s]] = w.tref;
      m_sbref[m_snap[s]] = w.bref;                         // BP-144
    end

    // ---- next state ----
    m_pd_snap = '0;
    if (restore_val) begin
      // RE1 to RE4, RE6: the pointers from the snapshot; the repair and
      // the p2 operation of this cycle are dropped; one count written.
      // BP-152: the depth from the snapshot; a TOSR entry whose
      // generation moved since the snapshot reads empty (B1).
      rkeep     = (restore_snap.tosr != restore_snap.bos) &&
                  (m_s.gt[restore_snap.tosr] == restore_snap.tag);
      m_ns      = m_s;
      m_ns.tosr = rkeep ? restore_snap.tosr : restore_snap.bos;
      m_ns.tosw = restore_snap.tosw;
      m_ns.bos  = restore_snap.bos;
      m_ns.dsp  = restore_snap.dep;
      // BP-143: the allocation the snapshot's TOSR named when the model
      // produced it; for a snapshot it never produced, the allocation
      // the index holds now.
      if (!rkeep)
        m_ns.tref = '0;
      else if (m_sref.exists(restore_snap))
        m_ns.tref = m_sref[restore_snap];
      else
        m_ns.tref = m_s.seq[restore_snap.tosr];
      // BP-144: the allocation the snapshot's BOS named; for a snapshot
      // the model never produced, the current one if BOS does not move,
      // else the allocation the index holds now.
      if (m_sbref.exists(restore_snap))
        m_ns.bref = m_sbref[restore_snap];
      else if (restore_snap.bos != m_s.bos)
        m_ns.bref = m_s.seq[restore_snap.bos];
      if (rkeep)
        m_ns.e[restore_snap.tosr].rctr = restore_snap.rctr;
      // BP-152: the undo of the restored block's own push (the top),
      // as the p3 undo-push (RP1, RP2), first.
      if (rs_undo) begin
        if (!m_empty(m_ns)) m_ns = m_pop_spec(m_ns, d);
        m_ns.dsp = m_ns.dsp - 1'b1;
      end
      // BP-153: the undo of the restored block's own pop, from the
      // snapshot's pop record, as the p3 undo-pop (RP4, RP5): LINK back
      // to ptosr (empty if its generation moved, B1) with the count 0 the
      // pop left; DEC the count at ptosr back up; the depth plus one.
      if (rs_undo_pop && (restore_snap.pmode != RAS_POP_NONE)) begin
        if (restore_snap.pmode == RAS_POP_LINK) begin
          ustale    = (m_ns.gt[restore_snap.ptosr] != restore_snap.ptag);
          m_ns.tosr = ustale ? m_ns.bos : restore_snap.ptosr;
          m_ns.tref = ustale ? '0 : m_ns.seq[restore_snap.ptosr];
          if (!m_empty(m_ns)) m_ns.e[m_ns.tosr].rctr = '0;
        end else if ((restore_snap.pmode == RAS_POP_DEC) && !m_empty(m_ns) &&
                     (m_ns.tosr == restore_snap.ptosr)) begin
          m_ns = m_adj(m_ns, restore_snap.ptosr, 1'b1);
        end
        m_ns.dsp = m_ns.dsp + 1'b1;
      end
      // BP-152 C1: the predecode operation on the restored state, by the
      // p2 rules: the pop first, then the push with recursion.
      pp_mode = RAS_POP_NONE;
      pp_tosr = '0;
      pp_tag  = '0;
      if (pd_val && m_is_pop(1'b1, pd_type)) begin
        pp_tosr = m_ns.tosr;                               // BP-153
        pp_tag  = m_empty(m_ns) ? '0 : m_ns.gt[m_ns.tosr];
        pp_mode = m_empty(m_ns)                    ? RAS_POP_EMPTY :
                  (m_ns.e[m_ns.tosr].rctr != '0)   ? RAS_POP_DEC   :
                                                     RAS_POP_LINK;
        if (!m_empty(m_ns)) m_ns = m_pop_spec(m_ns, d);
        m_ns.dsp = m_ns.dsp - 1'b1;
      end
      if (pd_val && m_is_push(1'b1, pd_type)) begin
        m_ns     = m_push(m_ns, pd_ret, 1'b1, k, p);
        m_ns.dsp = m_ns.dsp + 1'b1;
      end
      m_pd_snap.tosr = m_ns.tosr;
      m_pd_snap.tosw = m_ns.tosw;
      m_pd_snap.bos  = m_ns.bos;
      m_pd_snap.rctr = m_empty(m_ns) ? '0 : m_ns.e[m_ns.tosr].rctr;
      m_pd_snap.dep  = m_ns.dsp;
      m_pd_snap.tag  = m_empty(m_ns) ? '0 : m_ns.gt[m_ns.tosr];
      m_pd_snap.push  = pd_val && m_is_push(1'b1, pd_type); // BP-153
      m_pd_snap.pmode = pp_mode;
      m_pd_snap.ptosr = pp_tosr;
      m_pd_snap.ptag  = pp_tag;
      if (pd_val || rs_undo || rs_undo_pop) begin
        if (!m_empty(m_ns)) m_sref[m_pd_snap] = m_ns.tref;
        m_sbref[m_pd_snap] = m_ns.bref;
      end
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin       // RE3
        m_nq[s].pop  = 1'b0;
        m_nq[s].push = 1'b0;
      end
    end else if (!p2_keep) begin
      m_ns = wr;                                           // KP1
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        m_nq[s].pop  = 1'b0;
        m_nq[s].push = 1'b0;
      end
    end else begin
      m_ns = w;
    end

    // ---- commit (CO1 to CO11) ----
    m_nc  = m_c;
    cpop  = commit_val && ((commit_br_type == RETURN) ||
                           (commit_br_type == RETURN_CALL));
    cpush = commit_val && ((commit_br_type == DIRECT_CALL) ||
                           (commit_br_type == INDIRECT_CALL) ||
                           (commit_br_type == RETURN_CALL));
    if (cpop && (m_nc.cnt != '0)) begin                    // CO3, CO4
      m_nc.csp = m_nc.csp - 1'b1;
      m_nc.cnt = m_nc.cnt - 1'b1;
    end
    if (cpush) begin                                       // CO2, CO4
      m_nc.a[m_nc.csp] = commit_ret_addr;
      m_nc.csp         = m_nc.csp + 1'b1;
      if (m_nc.cnt != M_CCNT_W'(RAS_COMMIT_ENTRIES))
        m_nc.cnt = m_nc.cnt + 1'b1;
    end
    // BP-152 A1: the committed depth is the committing block's dep.
    if (cpop || cpush) m_nc.dcm = commit_snap.dep;
    // CO5: a push or a RETURN_CALL moves BOS; a RETURN unless its
    // snapshot is an empty stack.
    cmove = cpush || (cpop && (commit_snap.tosr != commit_snap.bos));
    if (cmove && !restore_val) begin                       // CO11
      if (m_ns.tosr == m_s.bos) begin                      // CO6
        m_ns.tosr = commit_snap.tosr;
        m_ns.tref = '0;                     // BP-144: empty, names none
      end
      m_ns.bos = commit_snap.tosr;
      // BP-144: BOS names the allocation the snapshot's TOSR named.
      if (commit_snap.tosr == commit_snap.bos)
        m_ns.bref = '0;
      else if (m_sref.exists(commit_snap))
        m_ns.bref = m_sref[commit_snap];
      else
        m_ns.bref = m_s.seq[commit_snap.tosr];
    end
    // BP-144: the converse of IV1 on the next state, before tref is
    // cleared below.
    m_ivc(m_ns, 0, "next state");
    // IV1: TOSR == BOS is the empty stack; the entry at BOS is the
    // sentinel, not a chain entry (BP-143).
    if (m_ns.tosr == m_ns.bos) m_ns.tref = '0;
  endtask

  // -----------------------------------------------------------------
  // m_compare: every pointer, every array entry, every output.
  // -----------------------------------------------------------------
  task automatic m_cmp(input string f, input logic [63:0] dv,
                       input logic [63:0] mv);
    m_ncmp++;
    if (dv !== mv) begin
      m_nmis++;
      $display("MODEL FAIL cyc %0d t %0t %s: dut %0h model %0h",
               m_cyc, $time, f, dv, mv);
    end
  endtask

  task automatic m_compare();
    m_cmp("tosr", 64'(dut.tosr), 64'(m_s.tosr));
    m_cmp("tosw", 64'(dut.tosw), 64'(m_s.tosw));
    m_cmp("bos",  64'(dut.bos),  64'(m_s.bos));
    m_cmp("csp",  64'(dut.csp),  64'(m_c.csp));
    m_cmp("c_cnt", 64'(dut.c_cnt), 64'(m_c.cnt));
    m_cmp("dsp",  64'(dut.dsp),  64'(m_s.dsp));            // BP-152 A1
    m_cmp("dcm",  64'(dut.dcm),  64'(m_c.dcm));
    for (int i = 0; i < RAS_SPEC_ENTRIES; i++)             // BP-152 B1
      m_cmp($sformatf("spec_gen[%0d]", i), 64'(dut.spec_gen[i]),
            64'(m_s.gt[i]));
    if (restore_val)                                       // BP-152 C1
      m_cmp("ras_pd_snapshot", 64'(pd_snap), 64'(m_pd_snap));
    for (int i = 0; i < RAS_SPEC_ENTRIES; i++) begin
      m_cmp($sformatf("spec_ret_addr[%0d]", i),
            64'(dut.spec_ret_addr[i]), 64'(m_s.e[i].ret));
      m_cmp($sformatf("spec_rctr[%0d]", i),
            64'(dut.spec_rctr[i]), 64'(m_s.e[i].rctr));
      m_cmp($sformatf("spec_ncnt[%0d]", i),                 // BP-153
            64'(dut.spec_ncnt[i]), 64'(m_s.e[i].ncnt));
      m_cmp($sformatf("spec_nos[%0d]", i),
            64'(dut.spec_nos[i]), 64'(m_s.e[i].nos));
      m_cmp($sformatf("spec_bot[%0d]", i),
            64'(dut.spec_bot[i]), 64'(m_s.e[i].bot));
    end
    for (int i = 0; i < RAS_COMMIT_ENTRIES; i++)
      m_cmp($sformatf("commit_ret_addr[%0d]", i),
            64'(dut.commit_ret_addr[i]), 64'(m_c.a[i]));
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      m_cmp($sformatf("ras_tos_valid_p0[%0d]", s),
            64'(tos_valid_p0[s]), 64'(m_tos_valid));
      if (m_tos_valid)
        m_cmp($sformatf("ras_tos_addr_p0[%0d]", s),
              64'(tos_addr_p0[s]), 64'(m_tos_addr));
      m_cmp($sformatf("ras_pop_valid_p2[%0d]", s),
            64'(pop_valid_p2[s]), 64'(m_pop_valid[s]));
      if (m_pop_valid[s])                                  // PO6
        m_cmp($sformatf("ras_pop_addr_p2[%0d]", s),
              64'(pop_addr_p2[s]), 64'(m_pop_addr[s]));
      m_cmp($sformatf("ras_snapshot_p2[%0d].tosr", s),
            64'(snap_p2[s].tosr), 64'(m_snap[s].tosr));
      m_cmp($sformatf("ras_snapshot_p2[%0d].tosw", s),
            64'(snap_p2[s].tosw), 64'(m_snap[s].tosw));
      m_cmp($sformatf("ras_snapshot_p2[%0d].bos", s),
            64'(snap_p2[s].bos), 64'(m_snap[s].bos));
      m_cmp($sformatf("ras_snapshot_p2[%0d].rctr", s),
            64'(snap_p2[s].rctr), 64'(m_snap[s].rctr));
      m_cmp($sformatf("ras_snapshot_p2[%0d].dep", s),      // BP-152
            64'(snap_p2[s].dep), 64'(m_snap[s].dep));
      m_cmp($sformatf("ras_snapshot_p2[%0d].tag", s),
            64'(snap_p2[s].tag), 64'(m_snap[s].tag));
      // BP-153: the pop record, and the peek (PO1 to PO6 for every slot).
      m_cmp($sformatf("ras_snapshot_p2[%0d].push", s),
            64'(snap_p2[s].push), 64'(m_snap[s].push));
      m_cmp($sformatf("ras_snapshot_p2[%0d].pmode", s),
            64'(snap_p2[s].pmode), 64'(m_snap[s].pmode));
      if (m_snap[s].pmode != RAS_POP_NONE) begin
        m_cmp($sformatf("ras_snapshot_p2[%0d].ptosr", s),
              64'(snap_p2[s].ptosr), 64'(m_snap[s].ptosr));
        m_cmp($sformatf("ras_snapshot_p2[%0d].ptag", s),
              64'(snap_p2[s].ptag), 64'(m_snap[s].ptag));
      end
      m_cmp($sformatf("ras_peek_valid_p2[%0d]", s),
            64'(peek_valid_p2[s]), 64'(m_peek_valid[s]));
      if (m_peek_valid[s])
        m_cmp($sformatf("ras_peek_addr_p2[%0d]", s),
              64'(peek_addr_p2[s]), 64'(m_peek_addr[s]));
    end
  endtask

  // BP-152: the four fields a snapshot had before BP-152, {tosr, tosw,
  // bos, rctr}, for the cases that check those values; the model
  // compares dep and tag (m_compare).
  localparam int P4_W = 3 * RAS_PTR_BITS + RAS_RCTR_WIDTH;
  function automatic logic [P4_W-1:0] p4(input bp_ras_snapshot_t x);
    return {x.tosr, x.tosw, x.bos, x.rctr};
  endfunction

  // BP-153: the expected {tosr, tosw, bos, rctr} at the parameters'
  // widths (RAS_PTR_BITS is 5 since BP-153; the cases wrote 4-bit
  // literal concatenations before).
  function automatic logic [P4_W-1:0] p4v(input int r, input int w,
                                          input int b, input int c);
    return {RAS_PTR_BITS'(r), RAS_PTR_BITS'(w), RAS_PTR_BITS'(b),
            RAS_RCTR_WIDTH'(c)};
  endfunction

  // BP-152: a hand-built snapshot {tosr, tosw, bos, rctr}. dep and tag
  // are the model's (THE REFERENCE MODEL's state, not the DUT's): the
  // speculative depth now, and the generation of the entry at tosr (0
  // when tosr == bos), so the snapshot restores the allocation the index
  // holds now, as a snapshot taken of it would. Before BP-152 the cases
  // wrote the four fields as a positional literal.
  function automatic bp_ras_snapshot_t snp(input int r, input int w,
                                           input int b, input int c);
    bp_ras_snapshot_t x;
    x.tosr = RAS_PTR_BITS'(r);
    x.tosw = RAS_PTR_BITS'(w);
    x.bos  = RAS_PTR_BITS'(b);
    x.rctr = RAS_RCTR_WIDTH'(c);
    x.dep  = m_s.dsp;
    x.tag  = (r == b) ? '0 : m_s.gt[r];
    // BP-153: a hand-built snapshot holds no operation record.
    x.push  = 1'b0;
    x.pmode = RAS_POP_NONE;
    x.ptosr = '0;
    x.ptag  = '0;
    return x;
  endfunction

  // BP-144: the converse of IV1 on the DUT, against the model's record.
  // The DUT reads empty (TOSR == BOS) at an index where the model's
  // TOSR names a live chain entry, one whose index still holds it.
  task automatic m_dut_conv();
    if ((dut.tosr == dut.bos) && (dut.tosr == m_s.tosr) && m_chain(m_s) &&
        !m_reused(m_s)) begin
      m_nconv++;
      m_nmis++;
      $display("MODEL FAIL cyc %0d t %0t dut state: IV1 converse", m_cyc,
               $time);
      $write("  dut tosr %0d == dut bos %0d reads empty over live alloc ",
             dut.tosr, dut.bos);
      $display("%0d (model bos %0d)", m_s.tref, m_s.bos);
    end
  endtask

  always @(negedge clk) begin
    if (rstn && m_live) begin
      m_eval();
      m_iv(m_s, 0, "state", 1'b0);                         // IV1
      m_dut_conv();                                        // BP-144
      m_compare();
    end
  end

  always @(posedge clk) begin
    if (!rstn) begin                                       // RT1
      m_s    <= '0;
      m_c    <= '0;
      m_live <= 1'b1;
      m_cyc  <= 0;
      m_sref.delete();                                     // BP-143
      m_sbref.delete();                                    // BP-144
      m_dep_at.delete();                                   // BP-152
      for (int s = 0; s < NUM_PRED_SLOTS; s++) m_q[s] <= '0;
    end else if (m_live) begin
      m_s   <= m_ns;
      m_c   <= m_nc;
      m_cyc <= m_cyc + 1;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) m_q[s] <= m_nq[s];
    end
  end

  // -----------------------------------------------------------------
  // Test addresses
  // -----------------------------------------------------------------
  localparam logic [VA_WIDTH-1:0] ADDR_A = VA_WIDTH'('h00_0000_1000);
  localparam logic [VA_WIDTH-1:0] ADDR_B = VA_WIDTH'('h00_0000_2000);
  localparam logic [VA_WIDTH-1:0] ADDR_C = VA_WIDTH'('h00_0000_3000);
  localparam logic [VA_WIDTH-1:0] ADDR_X = VA_WIDTH'('h00_0000_9000);
  localparam logic [VA_WIDTH-1:0] ADDR_R = VA_WIDTH'('h00_000A_0000);
  localparam logic [VA_WIDTH-1:0] ADDR_Y68 = VA_WIDTH'('h00_0000_6800);

  // TC-82's call-return pairs (BP-154): more than RAS_SPEC_ENTRIES - 2
  // at 16 entries, so the allocator laps the first call; fewer at 32.
  localparam int TC82_PAIRS = 20;
  // BP-153; BP-154 sizes it for TC-82, whose pairs outnumber the
  // entries at 16.
  localparam int FILL_N = RAS_SPEC_ENTRIES + TC82_PAIRS;
  logic [VA_WIDTH-1:0] fill_addr [0:FILL_N-1];

  // Saturated recursion count (TC-38d).
  localparam logic [RAS_RCTR_WIDTH-1:0] RCTR_MAX_TB =
    {RAS_RCTR_WIDTH{1'b1}};

  // -----------------------------------------------------------------
  // Stimulus
  // -----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    for (int i = 0; i < FILL_N; i++)
      fill_addr[i] = VA_WIDTH'('h0001_0000) + (i * VA_WIDTH'('h100));

    // =============================================================
    // TC-01: Reset state
    // =============================================================
    do_reset();
    check("TC-01 tosr==0", dut.tosr == '0);
    check("TC-01 tosw==0", dut.tosw == '0);
    check("TC-01 bos==0",  dut.bos  == '0);
    // Every slot (BP-128: literal [0] and [1] before).
    for (int s = 0; s < NUM_PRED_SLOTS; s++)
      check($sformatf("TC-01 pop_valid_p2[%0d]==0", s),
            pop_valid_p2[s] == 1'b0);
    for (int s = 0; s < NUM_PRED_SLOTS; s++)
      check($sformatf("TC-01 tos_valid_p0[%0d]==0", s),
            tos_valid_p0[s] == 1'b0);

    // =============================================================
    // TC-02: Single push slot 0
    // =============================================================
    do_reset();
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    #1;
    // Post-push snapshot: entry at idx1 (sentinel skip), tosr=1, tosw=2.
    check("TC-02 snap[0].tosr==1", snap_p2[0].tosr == 'd1);
    check("TC-02 snap[0].tosw==2", snap_p2[0].tosw == 'd2);
    check("TC-02 snap[0].bos==0",  snap_p2[0].bos  == 'd0);
    tick();
    check("TC-02 tos_valid_p0[0]==1 next cycle", tos_valid_p0[0] == 1'b1);
    check("TC-02 tos_addr_p0[0]==ADDR_A",        tos_addr_p0[0] == ADDR_A);

    // =============================================================
    // TC-03: Single pop slot 0
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // seed one entry
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-03 pop_valid_p2[0]==1", pop_valid_p2[0] == 1'b1);
    check("TC-03 pop_addr_p2[0]==ADDR_A", pop_addr_p2[0] == ADDR_A);
    // Post-pop snapshot: tosr back to 0, tosw monotonic at 2.
    check("TC-03 snap[0].tosr==0", snap_p2[0].tosr == 'd0);
    check("TC-03 snap[0].tosw==2", snap_p2[0].tosw == 'd2);
    tick();

    // TC-04 .. TC-07 drive both slots in one cycle: they need two slots
    // (BP-128). S1 is slot 1 whenever they run.
    if (NUM_PRED_SLOTS > 1) begin
      // =============================================================
      // TC-04: Dual push (call/call). Seed one entry first so the
      // cold-start sentinel skip does not perturb the +2 advance.
      // =============================================================
      do_reset();
      push_one(ADDR_X);                       // tosr=1, tosw=2
      begin
        logic [RAS_PTR_BITS-1:0] tosw_before;
        tosw_before = dut.tosw;
        drive(1'b1, DIRECT_CALL, ADDR_A, 1'b1, DIRECT_CALL, ADDR_B);
        tick();
        check("TC-04 TOSW advanced by 2",
              (dut.tosw - tosw_before) == 'd2);
        // Slot 0 -> idx2, slot 1 -> idx3 (in order).
        check("TC-04 spec[2]==ADDR_A", dut.spec_ret_addr[2] == ADDR_A);
        check("TC-04 spec[3]==ADDR_B", dut.spec_ret_addr[3] == ADDR_B);
        check("TC-04 tosr==3 (top is B)", dut.tosr == 'd3);
      end

      // =============================================================
      // TC-05: Dual pop (return/return). Seed two entries.
      // =============================================================
      do_reset();
      push_one(ADDR_A);                       // idx1
      push_one(ADDR_B);                       // idx2, tosr=2
      drive(1'b1, RETURN, '0, 1'b1, RETURN, '0);
      #1;
      // Slot 0 pops current top (B); slot 1 pops next (A).
      check("TC-05 pop_valid_p2[0]==1", pop_valid_p2[0] == 1'b1);
      check("TC-05 pop_addr_p2[0]==ADDR_B (top)", pop_addr_p2[0] == ADDR_B);
      check("TC-05 pop_valid_p2[1]==1", pop_valid_p2[S1] == 1'b1);
      check("TC-05 pop_addr_p2[1]==ADDR_A (next)", pop_addr_p2[S1] == ADDR_A);
      tick();

      // =============================================================
      // TC-06: Call then return (slot0=call, slot1=return). Bypass.
      // =============================================================
      do_reset();
      drive(1'b1, DIRECT_CALL, ADDR_A, 1'b1, RETURN, '0);
      #1;
      // slot1 pop must receive slot0's pushed address via bypass, not
      // from the array (array not yet written this cycle).
      check("TC-06 pop_valid_p2[1]==1", pop_valid_p2[S1] == 1'b1);
      check("TC-06 pop_addr_p2[1]==ADDR_A (bypass)",
            pop_addr_p2[S1] == ADDR_A);
      check("TC-06 array idx1 not yet written (pre-edge)",
            dut.spec_ret_addr[1] != ADDR_A);
      // slot1 snapshot: entry present (tosw=2) but TOSR back to pre-push.
      check("TC-06 snap[1].tosr==0 (pre-push)", snap_p2[S1].tosr == 'd0);
      check("TC-06 snap[1].tosw==2 (entry present)",
            snap_p2[S1].tosw == 'd2);
      tick();
      check("TC-06 spec[1]==ADDR_A after edge", dut.spec_ret_addr[1] == ADDR_A);

      // =============================================================
      // TC-07: Return then call (slot0=return, slot1=call). Seed one.
      // =============================================================
      do_reset();
      push_one(ADDR_X);                       // idx1, tosr=1, tosw=2
      drive(1'b1, RETURN, '0, 1'b1, DIRECT_CALL, ADDR_B);
      #1;
      check("TC-07 pop_valid_p2[0]==1", pop_valid_p2[0] == 1'b1);
      check("TC-07 pop_addr_p2[0]==ADDR_X", pop_addr_p2[0] == ADDR_X);
      // slot1 push lands at frontier (idx2); no bypass.
      check("TC-07 snap[1].tosr==2 (push at new TOSW)",
            snap_p2[S1].tosr == 'd2);
      check("TC-07 snap[1].tosw==3", snap_p2[S1].tosw == 'd3);
      tick();
      check("TC-07 spec[2]==ADDR_B", dut.spec_ret_addr[2] == ADDR_B);
    end else begin
      $display("SKIP TC-04 .. TC-07 dual-slot: needs NUM_PRED_SLOTS > 1");
    end

    // =============================================================
    // TC-08: Recursion counter increment
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // idx1, rctr=0, tosw=2
    begin
      logic [RAS_PTR_BITS-1:0] tosw_before;
      tosw_before = dut.tosw;
      drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0); // same addr
      tick();
      check("TC-08 TOSW did not advance (recursion)",
            dut.tosw == tosw_before);
      check("TC-08 rctr at idx1 incremented to 1",
            dut.spec_rctr[1] == 'd1);
      check("TC-08 tosr still 1", dut.tosr == 'd1);
    end

    // =============================================================
    // TC-09: Recursion counter decrement on pop
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // rctr=0
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0); tick(); // rctr=1
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0); tick(); // rctr=2
    check("TC-09 seeded rctr==2", dut.spec_rctr[1] == 'd2);
    // First RETURN: rctr 2->1, TOSR holds.
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); tick();
    check("TC-09 rctr==1 after pop1", dut.spec_rctr[1] == 'd1);
    check("TC-09 tosr holds at 1 (pop1)", dut.tosr == 'd1);
    // Second RETURN: rctr 1->0, TOSR holds.
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); tick();
    check("TC-09 rctr==0 after pop2", dut.spec_rctr[1] == 'd0);
    check("TC-09 tosr holds at 1 (pop2)", dut.tosr == 'd1);
    // Third RETURN: actual pop, TOSR moves.
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); tick();
    check("TC-09 tosr moves to 0 (pop3)", dut.tosr == 'd0);

    // =============================================================
    // TC-10: Recursion counter saturation (2^RAS_RCTR_WIDTH pushes)
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // first entry, rctr=0
    for (int i = 1; i < (1 << RAS_RCTR_WIDTH); i++) begin
      drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
      tick();
    end
    check("TC-10 rctr saturated at max",
          dut.spec_rctr[1] == {RAS_RCTR_WIDTH{1'b1}});
    check("TC-10 tosw not advanced past idx2", dut.tosw == 'd2);
    // One more push must not overflow rctr.
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0); tick();
    check("TC-10 rctr stays at max after extra push",
          dut.spec_rctr[1] == {RAS_RCTR_WIDTH{1'b1}});

    // TC-11 drive both slots in one cycle: they need two slots
    // (BP-128). S1 is slot 1 whenever they run.
    if (NUM_PRED_SLOTS > 1) begin
      // =============================================================
      // TC-11: Snapshot slot 0 vs slot 1 in a dual push.
      // Seed one entry to avoid cold-start sentinel skip.
      // =============================================================
      do_reset();
      push_one(ADDR_X);                       // tosr=1, tosw=2
      drive(1'b1, DIRECT_CALL, ADDR_A, 1'b1, DIRECT_CALL, ADDR_B);
      #1;
      check("TC-11 snap[0].tosr==2 (post slot0)", snap_p2[0].tosr == 'd2);
      check("TC-11 snap[0].tosw==3 (post slot0)", snap_p2[0].tosw == 'd3);
      check("TC-11 snap[1].tosr==3 (post both)",  snap_p2[S1].tosr == 'd3);
      check("TC-11 snap[1].tosw==4 (post both)",  snap_p2[S1].tosw == 'd4);
      tick();
    end else begin
      $display("SKIP TC-11 dual-slot snapshot: needs NUM_PRED_SLOTS > 1");
    end

    // =============================================================
    // TC-12: Mispredict restore (pointer-only, blocks p2).
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // idx1
    push_one(ADDR_B);                       // idx2
    push_one(ADDR_C);                       // idx3, tosr=3, tosw=4
    // Restore to the post-first-push state and simultaneously try a
    // push (must be blocked).
    drive(1'b1, DIRECT_CALL, ADDR_X, 1'b0, NO_BRANCH, '0);
    restore_val       = 1'b1;
    // BP-152: snp() gives the snapshot the generation idx1 holds (B1).
    restore_snap      = snp(1, 2, 0, 0);
    tick();
    restore_val       = 1'b0;
    restore_snap      = '0;
    check("TC-12 tosr restored to 1", dut.tosr == 'd1);
    check("TC-12 tosw restored to 2", dut.tosw == 'd2);
    check("TC-12 bos restored to 0",  dut.bos  == 'd0);
    check("TC-12 p2 push blocked (idx4 not written)",
          dut.spec_ret_addr[4] != ADDR_X);

    // =============================================================
    // TC-13: Commit stack push
    // =============================================================
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    check("TC-13 csp advanced to 1", int'(dut.csp) == 1);
    check("TC-13 commit_ret_addr[0]==ADDR_R",
          dut.commit_ret_addr[0] == ADDR_R);

    // =============================================================
    // TC-14: Commit stack pop
    // =============================================================
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);   // seed commit entry
    check("TC-14 csp==1 after seed", int'(dut.csp) == 1);
    commit_op(RETURN, '0, 'd0);
    check("TC-14 csp decremented to 0", int'(dut.csp) == 0);

    // =============================================================
    // TC-15: Empty fallback
    // =============================================================
    do_reset();
    // Both stacks empty -> pop invalid.
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-15 pop_valid_p2[0]==0 (both empty)",
          pop_valid_p2[0] == 1'b0);
    tick();
    // Seed commit stack only.
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-15 pop_valid_p2[0]==1 (commit fallback)",
          pop_valid_p2[0] == 1'b1);
    check("TC-15 pop_addr_p2[0]==ADDR_R (commit top)",
          pop_addr_p2[0] == ADDR_R);
    tick();
    check("TC-15 commit entry NOT consumed (csp==1)", int'(dut.csp) == 1);

    // =============================================================
    // TC-16: p3 repair -- undo push (p2=push, p3=no-op)
    // =============================================================
    do_reset();
    push_one(ADDR_X);                       // baseline, tosr=1, tosw=2
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0); // push A -> idx2
    tick();
    check("TC-16 pre-repair tosr==2", dut.tosr == 'd2);
    // Repair cycle: p2 idle, p3 disagrees (no-op vs the push).
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-16 tosr returned to pre-push (1)", dut.tosr == 'd1);
    check("TC-16 top is baseline X", dut.spec_ret_addr[dut.tosr] == ADDR_X);

    // =============================================================
    // TC-17: p3 repair -- undo pop (p2=pop, p3=no-op)
    // =============================================================
    do_reset();
    push_one(ADDR_X);                       // idx1, tosr=1, tosw=2
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); // pop -> tosr=0
    tick();
    check("TC-17 pre-repair tosr==0 (after pop)", dut.tosr == 'd0);
    // Repair cycle: p2 idle, p3 disagrees (no-op vs the pop).
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-17 tosr returned to pre-pop (1)", dut.tosr == 'd1);
    check("TC-17 top re-exposed as X", dut.spec_ret_addr[dut.tosr] == ADDR_X);

    // =============================================================
    // TC-18: Overflow graceful degradation
    // =============================================================
    do_reset();
    // Fill the speculative stack (idx1 .. RAS_SPEC_ENTRIES - 1 with the
    // sentinel model). BP-154: the counts are RAS_SPEC_ENTRIES'; they were
    // the literals 15 and 15, which at BP-153's 32 entries filled half.
    for (int i = 0; i < RAS_SPEC_ENTRIES - 1; i++) begin
      drive(1'b1, DIRECT_CALL, fill_addr[i], 1'b0, NO_BRANCH, '0);
      tick();
    end
    // One more push -> circular wrap, no fault.
    check("TC-18 the stack is full: TOSW back at BOS", dut.tosw == dut.bos);
    drive(1'b1, DIRECT_CALL, fill_addr[RAS_SPEC_ENTRIES - 1], 1'b0,
          NO_BRANCH, '0);
    tick();
    check("TC-18 pointers remain known (no X, graceful wrap)",
          (^{dut.tosr, dut.tosw, dut.bos} !== 1'bx));
    // Stack still functional: a pop yields a valid, non-X address.
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-18 pop_valid_p2[0]==1 (still functional)",
          pop_valid_p2[0] == 1'b1);
    check("TC-18 pop addr is known (not X)",
          pop_addr_p2[0] === pop_addr_p2[0]);
    tick();

    // =============================================================
    // TC-19: p0 TOS read reflects current TOS.
    // ras.sv p0 read is combinational off the registered pointers
    // (tosr/bos) and the array, so a pushed entry becomes visible the
    // cycle AFTER the push commits. Documented in Results Capture.
    // =============================================================
    do_reset();
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-19 same-cycle TOS still old (empty) before edge",
          tos_valid_p0[0] == 1'b0);
    tick();
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-19 next-cycle TOS reflects pushed addr",
          tos_addr_p0[0] == ADDR_A);
    check("TC-19 next-cycle TOS valid", tos_valid_p0[0] == 1'b1);
    tick();

    // =============================================================
    // TC-20: ras_tos_valid_p0 vs both-empty
    // =============================================================
    do_reset();
    check("TC-20 deasserted after reset", tos_valid_p0[0] == 1'b0);
    commit_op(DIRECT_CALL, ADDR_R, 'd0);   // seed commit only
    #1;
    check("TC-20 asserted with commit-only", tos_valid_p0[0] == 1'b1);
    check("TC-20 tos_addr from commit top", tos_addr_p0[0] == ADDR_R);
    commit_op(RETURN, '0, 'd0);            // clear commit
    #1;
    check("TC-20 deasserted when both empty", tos_valid_p0[0] == 1'b0);

    // =============================================================
    // TC-21: TD #78 -- undo-pop reverses a recursion pop (BP-133).
    // Seed a recursion entry so the p2 pop is a recursion-decrement
    // (TOSR held, rctr decremented) rather than a TOSR-moving pop. The
    // p3 undo-pop restores the pre-pop TOSR and increments the count
    // back. BP-064 to BP-132 pinned the non-reversing behavior: the
    // count stayed decremented (rctr[1] == 0 after the undo). Modeled
    // on TC-17 but with a recursion-decrement pop in p2.
    // See ras_decisions.md section 1 and PROJECT_STATUS TD #78.
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // idx1, rctr=0, tosw=2
    // Second push of ADDR_A -> recursion: rctr[1] 0->1, TOSR holds.
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-21 seeded recursion rctr[1]==1", dut.spec_rctr[1] == 'd1);
    check("TC-21 seeded tosr==1 (recursion holds top)", dut.tosr == 'd1);
    // p2 RETURN with p3 agreeing (drive) -> recursion-decrement pop:
    // rctr[1] 1->0, TOSR holds at 1 (TOSR not moved by this pop).
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-21 recursion pop decremented rctr[1] 1->0",
          dut.spec_rctr[1] == 'd0);
    check("TC-21 recursion pop held tosr at 1", dut.tosr == 'd1);
    // Repair cycle: p2 idle, p3 forced no-op so it disagrees with the
    // registered OP_POP -> undo-pop fires.
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    // OLD (BP-064 to BP-132): "TC-21 pins TD #78: rctr[1] NOT
    // restored, stays 0 (count lost)", dut.spec_rctr[1] == 'd0.
    check("TC-21 undo-pop restored the recursion count, rctr[1]==1",
          dut.spec_rctr[1] == 'd1);
    // OLD (BP-064 to BP-119): "TC-21 pins TD #78: undo-pop moved tosr
    // to 2, not restored to 1", dut.tosr == 'd2 (TOSR + 1).
    check("TC-21 undo-pop restored the pre-pop tosr (1)",
          dut.tosr == 'd1);
    check("TC-21 tosw held at 2 (no allocation on the undo)",
          dut.tosw == 'd2);
    // OLD (BP-064 to BP-119): "TC-21 pins TD #78: re-exposed top idx2
    // is empty (0), not ADDR_A", dut.spec_ret_addr[2] == '0 -- the
    // TOSR + 1 slot.
    check("TC-21 the top is A at idx1 again",
          dut.spec_ret_addr[dut.tosr] == ADDR_A);
    // Both recursion levels pop again: A, A, then empty.
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-21 first pop after the undo returns A",
          (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_A));
    tick();
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-21 second pop after the undo returns A",
          (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_A));
    tick();
    check("TC-21 two pops empty the stack", dut.tosr == dut.bos);

    // =============================================================
    // TC-22: RETURN_CALL at p2 -- pop, then push (RAS-DS1).
    // Seed A at idx1 (tosr 1, tosw 2). The pop returns A and leaves
    // TOSR at BOS (empty); the push then allocates at TOSW = 2.
    // =============================================================
    do_reset();
    push_one(ADDR_A);
    check("TC-22 seeded tosr==1 tosw==2",
          (dut.tosr == 'd1) && (dut.tosw == 'd2));
    drive(1'b1, RETURN_CALL, ADDR_B, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-22 the pop is valid", pop_valid_p2[0] == 1'b1);
    check("TC-22 the pop returns A", pop_addr_p2[0] == ADDR_A);
    check("TC-22 snap[0] is after the pop and the push (tosr 2)",
          snap_p2[0].tosr == 'd2);
    check("TC-22 snap[0].tosw==3", snap_p2[0].tosw == 'd3);
    tick();
    check("TC-22 tosr==2 after the edge", dut.tosr == 'd2);
    check("TC-22 spec[2]==B (the pushed return address)",
          dut.spec_ret_addr[2] == ADDR_B);
    check("TC-22 A still resident at idx1 (pop does not overwrite)",
          dut.spec_ret_addr[1] == ADDR_A);
    check("TC-22 p0 TOS reads B", tos_addr_p0[0] == ADDR_B);
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-22 p3 agrees with p2: no repair (tosr 2, tosw 3)",
          (dut.tosr == 'd2) && (dut.tosw == 'd3));

    // =============================================================
    // TC-23: RETURN_CALL with the speculative stack empty. The pop
    // falls back to the commit top and does not consume it; the push
    // allocates at BOS+1 (cold start).
    // =============================================================
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    check("TC-23 commit seeded csp==1", int'(dut.csp) == 1);
    drive(1'b1, RETURN_CALL, ADDR_B, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-23 pop valid from the commit stack", pop_valid_p2[0] == 1'b1);
    check("TC-23 pop addr is the commit top R", pop_addr_p2[0] == ADDR_R);
    tick();
    check("TC-23 push allocated at idx1: tosr 1, tosw 2",
          (dut.tosr == 'd1) && (dut.tosw == 'd2));
    check("TC-23 spec[1]==B", dut.spec_ret_addr[1] == ADDR_B);
    check("TC-23 commit entry NOT consumed (csp==1)", int'(dut.csp) == 1);

    // =============================================================
    // TC-24: RETURN_CALL over a recursion count -- TWO array writes in
    // one slot. Seed A twice (rctr[1] 1). The pop decrements rctr[1]
    // in place (TOSR holds at 1); the push of B != A allocates at
    // TOSW = 2. Both writes must land.
    // =============================================================
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_A);
    check("TC-24 seeded rctr[1]==1 tosr==1 tosw==2",
          (dut.spec_rctr[1] == 'd1) && (dut.tosr == 'd1)
          && (dut.tosw == 'd2));
    drive(1'b1, RETURN_CALL, ADDR_B, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-24 the pop returns A", pop_addr_p2[0] == ADDR_A);
    tick();
    check("TC-24 write 1: rctr[1] decremented 1->0",
          dut.spec_rctr[1] == 'd0);
    check("TC-24 write 1: spec[1] still A", dut.spec_ret_addr[1] == ADDR_A);
    check("TC-24 write 2: spec[2]==B", dut.spec_ret_addr[2] == ADDR_B);
    check("TC-24 tosr 2, tosw 3", (dut.tosr == 'd2) && (dut.tosw == 'd3));

    // =============================================================
    // TC-25: RETURN_CALL whose push equals the top the pop exposes:
    // the push is a recursion increment, not an allocation. Seed A at
    // idx1 and B at idx2. Pop B (tosr 2 -> 1, top A); push A matches
    // the top, so rctr[1] 0 -> 1 and TOSR holds at 1.
    // =============================================================
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_B);
    check("TC-25 seeded tosr==2 tosw==3",
          (dut.tosr == 'd2) && (dut.tosw == 'd3));
    drive(1'b1, RETURN_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-25 the pop returns B", pop_addr_p2[0] == ADDR_B);
    tick();
    check("TC-25 tosr==1 (recursion holds the exposed top)",
          dut.tosr == 'd1);
    check("TC-25 rctr[1]==1", dut.spec_rctr[1] == 'd1);
    check("TC-25 tosw unchanged at 3", dut.tosw == 'd3);

    // =============================================================
    // TC-26: p3 repair -- undo a whole RETURN_CALL (p2 pop+push, p3
    // no-op). Seed X at idx1. The RETURN_CALL leaves tosr 2 (B),
    // tosw 3. The undo restores the pre-op TOSR, 1 (X); TOSW stays
    // monotonic at 3. Retracting the push then re-exposing the pop
    // would land on 2, the slot the push wrote.
    // =============================================================
    do_reset();
    push_one(ADDR_X);
    drive(1'b1, RETURN_CALL, ADDR_B, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-26 pre-repair tosr==2 tosw==3",
          (dut.tosr == 'd2) && (dut.tosw == 'd3));
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-26 tosr restored to the pre-op value (1)", dut.tosr == 'd1);
    check("TC-26 top is X again", dut.spec_ret_addr[dut.tosr] == ADDR_X);
    check("TC-26 tosw held at 3", dut.tosw == 'd3);
    check("TC-26 p0 TOS reads X", tos_addr_p0[0] == ADDR_X);

    // =============================================================
    // TC-27: p3 repair -- a missed RETURN_CALL (p2 no-op, p3
    // RETURN_CALL): the missed pop, then the missed push of the
    // registered fall-through. Seed X at idx1 and idle one cycle so
    // the registered op is NONE; that idle cycle presents B on the
    // fall-through with no valid, which is what p3 registers.
    // =============================================================
    do_reset();
    push_one(ADDR_X);
    drive(1'b0, NO_BRANCH, ADDR_B, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-27 seeded tosr==1 tosw==2",
          (dut.tosr == 'd1) && (dut.tosw == 'd2));
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b1, RETURN_CALL, 1'b0, NO_BRANCH);
    tick();
    check("TC-27 missed pop then missed push: tosr 2, tosw 3",
          (dut.tosr == 'd2) && (dut.tosw == 'd3));
    check("TC-27 spec[2]==B (registered fall-through)",
          dut.spec_ret_addr[2] == ADDR_B);
    check("TC-27 p0 TOS reads B", tos_addr_p0[0] == ADDR_B);

    // =============================================================
    // TC-28: commit of RETURN_CALL (IC-RAS-10): the return arm, then
    // the call arm on the CSP the first leaves; BOS once, from the
    // commit snapshot.
    // =============================================================
    do_reset();
    commit_op(DIRECT_CALL, ADDR_A, 'd0);
    commit_op(DIRECT_CALL, ADDR_C, 'd0);
    check("TC-28 seeded csp==2", int'(dut.csp) == 2);
    commit_op(RETURN_CALL, ADDR_B, 'd5);
    check("TC-28 csp level at 2 (pop then push)", int'(dut.csp) == 2);
    check("TC-28 committed top replaced: commit[1]==B",
          dut.commit_ret_addr[1] == ADDR_B);
    check("TC-28 entry below untouched: commit[0]==A",
          dut.commit_ret_addr[0] == ADDR_A);
    check("TC-28 bos took the snapshot tosr (5)", dut.bos == 'd5);
    // Empty commit stack: the pop does nothing, the push writes at 0.
    do_reset();
    commit_op(RETURN_CALL, ADDR_B, 'd0);
    check("TC-28 from empty: csp 0 -> 1", int'(dut.csp) == 1);
    check("TC-28 from empty: commit[0]==B", dut.commit_ret_addr[0] == ADDR_B);

    // =============================================================
    // TC-29: TD#159. Push A, push B, pop, push C, pop, pop predicts
    // A, then the stack is empty and the pop falls back to the commit
    // stack (ras_decisions.md 3.2, ruled session-075). The commit
    // stack is seeded with R first so the fallback is visible. Before
    // BP-120 the pop after C returned to TOSR-1, the slot B was popped
    // from, and predicted B.
    // =============================================================
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    push_one(ADDR_A);                       // idx1, nos 0
    push_one(ADDR_B);                       // idx2, nos 1
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-29 pop 1 predicts B", pop_addr_p2[0] == ADDR_B);
    tick();
    push_one(ADDR_C);                       // idx3, nos 1 (A)
    check("TC-29 C allocated at idx3, links to A at idx1",
          (dut.tosr == 'd3) && (dut.spec_nos[3] == 'd1));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-29 pop 2 predicts C", pop_addr_p2[0] == ADDR_C);
    tick();
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-29 pop 3 predicts A (was B before BP-120)",
          pop_valid_p2[0] && (pop_addr_p2[0] == ADDR_A));
    tick();
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-29 the stack is empty (tosr == bos)", dut.tosr == dut.bos);
    check("TC-29 pop 4 falls back to the commit top R",
          pop_valid_p2[0] && (pop_addr_p2[0] == ADDR_R));
    tick();
    check("TC-29 the commit entry is not consumed", int'(dut.csp) == 1);

    // =============================================================
    // TC-30: TC-29 with a recursion count on A. A is pushed twice
    // (rctr 1). The pop after C pops A's count (TOSR holds at A), the
    // next pops A itself and follows the link to empty, and the last
    // falls back to R. Recursion counter rules (section 5) unchanged.
    // =============================================================
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    push_one(ADDR_A);
    push_one(ADDR_A);                       // rctr[1] 1
    push_one(ADDR_B);                       // idx2
    check("TC-30 seeded: A rctr 1 at idx1, B at idx2",
          (dut.spec_rctr[1] == 'd1) && (dut.tosr == 'd2));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();                                 // pop B
    push_one(ADDR_C);                       // idx3, nos 1
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-30 pop C", pop_addr_p2[0] == ADDR_C);
    tick();
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-30 pop predicts A (was B before BP-120)",
          pop_valid_p2[0] && (pop_addr_p2[0] == ADDR_A));
    tick();
    check("TC-30 the recursion pop decremented A's count, tosr holds",
          (dut.spec_rctr[1] == 'd0) && (dut.tosr == 'd1));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-30 pop predicts A again", pop_addr_p2[0] == ADDR_A);
    tick();
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-30 then empty: commit fallback R",
          (dut.tosr == dut.bos) && pop_valid_p2[0]
          && (pop_addr_p2[0] == ADDR_R));
    tick();

    // =============================================================
    // TC-31: the p3 repair rows of ras_decisions.md 1 on the link.
    // Each starts from A(1) B(2), pop B, then C pushed at idx3 with
    // nos 1, so the entry below C is NOT C's index minus one -- the
    // case where the TOSR+-1 rules and the link differ.
    // =============================================================
    // a. undo-pop (p2 pop, p3 none) restores the pre-op TOSR, 3.
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_B);
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();
    push_one(ADDR_C);
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);   // p2 pop C
    tick();
    check("TC-31a pop followed the link: tosr 1", dut.tosr == 'd1);
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-31a undo-pop restores the pre-op tosr 3 (C), not 2 (B)",
          (dut.tosr == 'd3) && (dut.spec_ret_addr[dut.tosr] == ADDR_C));
    check("TC-31a tosw held at 4", dut.tosw == 'd4);

    // b. missed pop (p2 none, p3 pop) follows the link to A.
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_B);
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();
    push_one(ADDR_C);
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    tick();                                 // registered op NONE
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b1, RETURN, 1'b0, NO_BRANCH);
    tick();
    check("TC-31b missed pop follows nos: tosr 1 (A), not 2 (B)",
          (dut.tosr == 'd1) && (dut.spec_ret_addr[dut.tosr] == ADDR_A));

    // c. undo-push (p2 push, p3 none) follows the pushed entry's nos.
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_B);
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();
    drive(1'b1, DIRECT_CALL, ADDR_C, 1'b0, NO_BRANCH, '0);  // p2 push C
    tick();
    check("TC-31c C pushed at idx3", dut.tosr == 'd3);
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-31c undo-push returns to the pre-push top, tosr 1 (A)",
          (dut.tosr == 'd1) && (dut.spec_ret_addr[dut.tosr] == ADDR_A));
    check("TC-31c tosw stays monotonic at 4", dut.tosw == 'd4);

    // d. missed push (p2 none, p3 call) allocates the registered
    //    fall-through at TOSW, linked to the current top.
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_B);
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();                                 // tosr 1, tosw 3
    drive(1'b0, NO_BRANCH, ADDR_C, 1'b0, NO_BRANCH, '0);
    tick();                                 // registers C, op NONE
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b1, DIRECT_CALL, 1'b0, NO_BRANCH);
    tick();
    check("TC-31d missed push: C at idx3, linked to A",
          (dut.tosr == 'd3) && (dut.spec_ret_addr[3] == ADDR_C)
          && (dut.spec_nos[3] == 'd1) && (dut.tosw == 'd4));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-31d the pop after C predicts A", pop_addr_p2[0] == ADDR_A);
    tick();

    // =============================================================
    // TC-32: a snapshot restore after wrong-path pops and pushes gives
    // the pre-mispredict top exactly, and the stack below it, while
    // the buffer has not wrapped (ras_decisions.md 3.2, 4.3). The
    // snapshot is the p2 post-op snapshot of the C push, whose top
    // links to A, not to the slot below it.
    // =============================================================
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    push_one(ADDR_A);                       // idx1
    push_one(ADDR_B);                       // idx2
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();
    drive(1'b1, DIRECT_CALL, ADDR_C, 1'b0, NO_BRANCH, '0);
    #1;
    restore_snap = snap_p2[0];              // {tosr 3, tosw 4, bos 0}
    tick();
    check("TC-32 snapshot taken: tosr 3 tosw 4 bos 0",
          (restore_snap.tosr == 'd3) && (restore_snap.tosw == 'd4)
          && (restore_snap.bos == 'd0));
    // Wrong path: pop C, pop A, push X, push Y, pop Y.
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();
    push_one(ADDR_X);
    push_one(ADDR_B + VA_WIDTH'('h10));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-32 wrong path left tosr off the snapshot top",
          dut.tosr != 'd3);
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    restore_val = 1'b1;
    tick();
    restore_val = 1'b0;
    check("TC-32 restore: pointers are the snapshot's",
          (dut.tosr == 'd3) && (dut.tosw == 'd4) && (dut.bos == 'd0));
    check("TC-32 restore: the p0 top is C exactly",
          tos_valid_p0[0] && (tos_addr_p0[0] == ADDR_C));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-32 pop after restore predicts C", pop_addr_p2[0] == ADDR_C);
    tick();
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-32 the next pop predicts A (was B before BP-120)",
          pop_addr_p2[0] == ADDR_A);
    tick();
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-32 then empty: commit fallback R",
          (dut.tosr == dut.bos) && (pop_addr_p2[0] == ADDR_R));
    tick();
    restore_snap = '0;

    // =============================================================
    // TC-33: a RETURN_CALL paired at the other stage with a plain push
    // or pop. ras_decisions.md 1 does not specify these rows; ras.sv
    // takes its per-component repair steps. Each case seeds X at idx1
    // and drives B as the fall-through of the p2 cycle, so the
    // registered fall-through is B. The result the p3 type implies is
    // stated beside each; two of the four are not it. In bp_cluster
    // the p3 type is the registered p2 type, so these rows are reached
    // only by force_p3 here. AS BUILT, BP-120.
    // =============================================================
    // a. p2 RETURN_CALL, p3 RETURN: the push is undone (the link
    //    returns TOSR to the post-pop top, empty). p3 result: X
    //    popped, stack empty. MATCHES.
    do_reset();
    push_one(ADDR_X);
    drive(1'b1, RETURN_CALL, ADDR_B, 1'b0, NO_BRANCH, '0);
    tick();
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b1, RETURN, 1'b0, NO_BRANCH);
    tick();
    check("TC-33a p2 RC / p3 RETURN: empty, as the pop alone",
          dut.tosr == dut.bos);
    // b. p2 RETURN, p3 RETURN_CALL: the missed push of B. p3 result:
    //    X popped, B pushed over empty. MATCHES.
    do_reset();
    push_one(ADDR_X);
    drive(1'b1, RETURN, ADDR_B, 1'b0, NO_BRANCH, '0);
    tick();
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b1, RETURN_CALL, 1'b0, NO_BRANCH);
    tick();
    check("TC-33b p2 RETURN / p3 RC: B on top, linked to empty",
          (dut.tosr != dut.bos) && (dut.spec_ret_addr[dut.tosr] == ADDR_B)
          && (dut.spec_nos[dut.tosr] == dut.bos));
    // c. p2 RETURN_CALL, p3 call: the undo-pop restores the pre-op
    //    TOSR, which drops the push as well. AS BUILT: X on top, B
    //    not pushed. p3 result would be X with B pushed above it.
    do_reset();
    push_one(ADDR_X);
    drive(1'b1, RETURN_CALL, ADDR_B, 1'b0, NO_BRANCH, '0);
    tick();
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b1, DIRECT_CALL, 1'b0, NO_BRANCH);
    tick();
    check("TC-33c AS BUILT p2 RC / p3 call: X on top, B dropped",
          (dut.tosr == 'd1) && (dut.spec_ret_addr[1] == ADDR_X));
    // d. p2 call, p3 RETURN_CALL: the missed pop removes the pushed
    //    B. AS BUILT: X on top. p3 result would be X popped and B
    //    pushed over empty.
    do_reset();
    push_one(ADDR_X);
    drive(1'b1, DIRECT_CALL, ADDR_B, 1'b0, NO_BRANCH, '0);
    tick();
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b1, RETURN_CALL, 1'b0, NO_BRANCH);
    tick();
    check("TC-33d AS BUILT p2 call / p3 RC: X on top, X not popped",
          (dut.tosr == 'd1) && (dut.spec_ret_addr[1] == ADDR_X));

    // =============================================================
    // TC-34 (BP-121, FE-14): ras_p2_keep low drops the p2 pass of a
    // block a redirect squashed, while the p3 repair of the older
    // block in the same cycle still applies (the cluster takes its own
    // p3 redirect without a restore), and the dropped operation is
    // registered as none, so the next cycle repairs nothing for it.
    // X on the stack, B pushed at p2; next cycle p3 says B's block had
    // no call (undo-push) while a squashed block pushes C at p2.
    // =============================================================
    do_reset();
    push_one(ADDR_X);
    drive(1'b1, DIRECT_CALL, ADDR_B, 1'b0, NO_BRANCH, '0);
    tick();
    drive(1'b1, DIRECT_CALL, ADDR_C, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    p2_keep = 1'b0;
    tick();
    p2_keep = 1'b1;
    check("TC-34a B's push undone by the repair, C's push dropped: X on top",
          (dut.tosr == 'd1) && (dut.spec_ret_addr[1] == ADDR_X));
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-34b the dropped push is not repaired a cycle later: X on top",
          (dut.tosr == 'd1) && (dut.spec_ret_addr[1] == ADDR_X));

    // =============================================================
    // TC-35 (BP-122, TD#170): ras_p2_keep low with no p3 repair in the
    // cycle. The squashed block's push is dropped and nothing else
    // moves the pointers: the empty stack stays empty. Exercises the
    // ras_assert RS1 property in the cycle it covers.
    // =============================================================
    do_reset();
    drive(1'b1, DIRECT_CALL, ADDR_C, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    p2_keep = 1'b0;
    tick();
    p2_keep = 1'b1;
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    check("TC-35 a dropped push with no repair leaves the pointers",
          (dut.tosr == '0) && (dut.tosw == '0));
    tick();  // the edge at which RS1 samples the dropped cycle

    // =============================================================
    // TC-36 (BP-126, TD#121): a FULL commit stack is not empty. 32
    // commit pushes with no pop fill the stack and wrap CSP to 0. The
    // stack must still read non-empty: the p0 read and the empty-pop
    // fallback take the last entry pushed, and a commit pop from the
    // full state exposes the entry below it (ras_decisions.md 3.3).
    // Before BP-126 the wrapped CSP == 0 read as EMPTY.
    // =============================================================
    do_reset();
    for (int i = 0; i < RAS_COMMIT_ENTRIES; i++)
      commit_op(DIRECT_CALL, cs_ad(32'h4_0000, i), 'd0);
    #1;
    check("TC-36a full commit stack: p0 TOS valid", tos_valid_p0[0] == 1'b1);
    check("TC-36b full commit stack: p0 TOS is the last push",
          tos_addr_p0[0] == cs_ad(32'h4_0000, RAS_COMMIT_ENTRIES-1));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);   // speculative empty
    #1;
    check("TC-36c empty-pop fallback valid from the full stack",
          pop_valid_p2[0] == 1'b1);
    check("TC-36d empty-pop fallback is the last push",
          pop_addr_p2[0] == cs_ad(32'h4_0000, RAS_COMMIT_ENTRIES-1));
    tick();
    commit_op(RETURN, '0, 'd0);                     // commit pop
    #1;
    check("TC-36e after one commit pop: still valid", tos_valid_p0[0] == 1'b1);
    check("TC-36f after one commit pop: the 31st push is on top",
          tos_addr_p0[0] == cs_ad(32'h4_0000, RAS_COMMIT_ENTRIES-2));

    // =============================================================
    // TC-37 (BP-126, TD#121): past full. A 33rd push overwrites the
    // oldest entry (conventional circular stack, no fault, 3.3) and
    // the stack stays non-empty; 32 pops then empty it, the last
    // valid top being the second push, since the first was lost.
    // =============================================================
    do_reset();
    for (int i = 0; i <= RAS_COMMIT_ENTRIES; i++)
      commit_op(DIRECT_CALL, cs_ad(32'h5_0000, i), 'd0);
    #1;
    check("TC-37a 33 pushes: TOS valid, the 33rd push",
          (tos_valid_p0[0] == 1'b1) &&
          (tos_addr_p0[0] == cs_ad(32'h5_0000, RAS_COMMIT_ENTRIES)));
    for (int i = 0; i < RAS_COMMIT_ENTRIES - 1; i++)
      commit_op(RETURN, '0, 'd0);
    #1;
    check("TC-37b 31 pops: one entry left, the second push",
          (tos_valid_p0[0] == 1'b1) &&
          (tos_addr_p0[0] == VA_WIDTH'('h5_0000 + 4)));
    commit_op(RETURN, '0, 'd0);
    #1;
    check("TC-37c 32 pops: empty", tos_valid_p0[0] == 1'b0);
    commit_op(RETURN, '0, 'd0);                     // pop on empty
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    #1;
    check("TC-37d a pop on empty is ignored: one push reads back",
          (tos_valid_p0[0] == 1'b1) && (tos_addr_p0[0] == ADDR_R));
    commit_op(RETURN, '0, 'd0);
    #1;
    check("TC-37e and one pop empties it again", tos_valid_p0[0] == 1'b0);

    // =============================================================
    // TC-38 (BP-133, TD #78): the undo of a whole RETURN_CALL (p2
    // pop+push, p3 no-op) restores the recursion counts its pop and
    // push changed, as well as the pre-op TOSR (TC-26).
    // a. The pop decremented a count, the push allocated: the count is
    //    incremented back. Seed A twice (idx1 rctr 1), RETURN_CALL with
    //    fall-through B: the pop takes rctr[1] 1->0 holding TOSR, the
    //    push allocates B at idx2.
    // =============================================================
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_A);
    check("TC-38a seeded rctr[1]==1 tosr==1",
          (dut.spec_rctr[1] == 'd1) && (dut.tosr == 'd1));
    drive(1'b1, RETURN_CALL, ADDR_B, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-38a pre-repair: rctr[1]==0, B on top at idx2",
          (dut.spec_rctr[1] == 'd0) && (dut.tosr == 'd2) &&
          (dut.spec_ret_addr[2] == ADDR_B));
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    // Before BP-133: tosr 1 and rctr[1] 0 (one recursion level lost).
    check("TC-38a undo: tosr 1, rctr[1] restored to 1",
          (dut.tosr == 'd1) && (dut.spec_rctr[1] == 'd1));
    // b. The pop moved TOSR, the push incremented the count of the
    //    entry below: the count is decremented back. Seed A (idx1),
    //    then X (idx2). RETURN_CALL with fall-through A pops X (TOSR to
    //    idx1, A) and the push matches A: rctr[1] 0->1.
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_X);
    drive(1'b1, RETURN_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-38b pre-repair: tosr 1, rctr[1]==1",
          (dut.tosr == 'd1) && (dut.spec_rctr[1] == 'd1));
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    // Before BP-133: tosr 2 and rctr[1] 1 (a level that never was).
    check("TC-38b undo: tosr 2 (X), rctr[1] restored to 0",
          (dut.tosr == 'd2) && (dut.spec_rctr[1] == 'd0) &&
          (dut.spec_ret_addr[2] == ADDR_X));
    // c. Both on one entry: seed A twice (rctr[1] 1), RETURN_CALL with
    //    fall-through A: the pop takes rctr[1] to 0 holding TOSR, the
    //    push matches A and takes it back to 1. The undo changes no
    //    count.
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_A);
    drive(1'b1, RETURN_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-38c pre-repair: tosr 1, rctr[1]==1, tosw 2",
          (dut.tosr == 'd1) && (dut.spec_rctr[1] == 'd1) &&
          (dut.tosw == 'd2));
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-38c undo: tosr 1, rctr[1] still 1",
          (dut.tosr == 'd1) && (dut.spec_rctr[1] == 'd1));
    // d. A saturated count the push could not move is not decremented
    //    by the undo. Seed A with rctr 15 through the push path (one
    //    allocation, 15 recursion pushes), X above it, then the b case.
    do_reset();
    for (int i = 0; i <= int'(RCTR_MAX_TB); i++)
      push_one(ADDR_A);
    check("TC-38d seeded rctr[1]==15", dut.spec_rctr[1] == RCTR_MAX_TB);
    push_one(ADDR_X);
    drive(1'b1, RETURN_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-38d pre-repair: tosr 1, rctr[1] held at 15",
          (dut.tosr == 'd1) && (dut.spec_rctr[1] == RCTR_MAX_TB));
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-38d undo: tosr 2, rctr[1] still 15",
          (dut.tosr == 'd2) && (dut.spec_rctr[1] == RCTR_MAX_TB));

    // =============================================================
    // TC-39 (BP-133, TD #79): the commit stack has no recursion
    // compression; each committed call is its own entry, so recursion
    // depth is kept as repeated entries and the fallback reads it at
    // depth. Commit A then B three times (B calling itself), then pop
    // with the speculative stack empty: B, B, B, A, empty. The commit
    // rctr field, written zero and read by nothing, was removed in
    // BP-134.
    // =============================================================
    do_reset();
    commit_op(DIRECT_CALL, ADDR_A, 'd0);
    for (int i = 0; i < 3; i++)
      commit_op(DIRECT_CALL, ADDR_B, 'd0);
    check("TC-39 four committed calls, four entries",
          int'(dut.c_cnt) == 4);
    for (int i = 0; i < 3; i++) begin
      #1;
      check($sformatf("TC-39 fallback at depth %0d is B", 4 - i),
            (tos_valid_p0[0] == 1'b1) && (tos_addr_p0[0] == ADDR_B));
      commit_op(RETURN, '0, 'd0);
    end
    #1;
    check("TC-39 fallback at depth 1 is A",
          (tos_valid_p0[0] == 1'b1) && (tos_addr_p0[0] == ADDR_A));
    commit_op(RETURN, '0, 'd0);
    #1;
    check("TC-39 then empty", tos_valid_p0[0] == 1'b0);

    // =============================================================
    // TC-40 (BP-134): an undo-push reverses only what the push did. A
    // push whose fall-through matches a top at the saturated count
    // (RCTR_MAX_TB) takes the recursion arm and changes nothing, so
    // its undo changes nothing. Before BP-134 the undo-push was
    // st_retract, which decremented the saturated count: one recursion
    // level lost.
    // a. Plain push undone: seed A with rctr 15 through the push path
    //    (one allocation, 15 recursion pushes). p2 pushes A again, p3
    //    says no branch.
    // =============================================================
    do_reset();
    for (int i = 0; i <= int'(RCTR_MAX_TB); i++)
      push_one(ADDR_A);
    check("TC-40a seeded rctr[1]==15 tosr 1 tosw 2",
          (dut.spec_rctr[1] == RCTR_MAX_TB) && (dut.tosr == 'd1) &&
          (dut.tosw == 'd2));
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-40a pre-repair: the saturated push moved nothing",
          (dut.spec_rctr[1] == RCTR_MAX_TB) && (dut.tosr == 'd1) &&
          (dut.tosw == 'd2));
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    // Before BP-134: rctr[1] 14.
    check("TC-40a undo-push: rctr[1] still 15, tosr 1, tosw 2",
          (dut.spec_rctr[1] == RCTR_MAX_TB) && (dut.tosr == 'd1) &&
          (dut.tosw == 'd2));
    // All 16 levels still pop as A, then the stack is empty.
    for (int i = 0; i <= int'(RCTR_MAX_TB); i++) begin
      drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
      #1;
      check($sformatf("TC-40a pop %0d returns A", i + 1),
            (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_A));
      tick();
    end
    check("TC-40a then the speculative stack is empty",
          dut.tosr == dut.bos);
    // b. The push half of a RETURN_CALL undone (p3 RETURN): seed A at
    //    rctr 15 and X above it. RETURN_CALL with fall-through A pops X
    //    (TOSR follows the link to A) and its push meets A at 15. p3
    //    keeps the pop and drops the push.
    do_reset();
    for (int i = 0; i <= int'(RCTR_MAX_TB); i++)
      push_one(ADDR_A);
    push_one(ADDR_X);
    drive(1'b1, RETURN_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-40b pre-repair: tosr 1, rctr[1] held at 15",
          (dut.tosr == 'd1) && (dut.spec_rctr[1] == RCTR_MAX_TB));
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b1, RETURN, 1'b0, NO_BRANCH);
    tick();
    // Before BP-134: rctr[1] 14.
    check("TC-40b undo of the push half: tosr 1, rctr[1] still 15",
          (dut.tosr == 'd1) && (dut.spec_rctr[1] == RCTR_MAX_TB));
    // c. Below saturation the undo-push still removes the level the
    //    push added: A twice (rctr 1), push A (rctr 2), undo -> 1.
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_A);
    drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-40c pre-repair: rctr[1]==2",
          (dut.spec_rctr[1] == 'd2) && (dut.tosr == 'd1));
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-40c undo-push: rctr[1] back to 1, tosr 1",
          (dut.spec_rctr[1] == 'd1) && (dut.tosr == 'd1));

    // =============================================================
    // TC-41 (BP-138, D2): a commit moves BOS while the speculative
    // stack is empty. A call pushes A, its return pops A (TOSR back to
    // BOS), then the call commits: BOS becomes A's slot. The stack is
    // still empty, so the next pop takes the commit-stack fallback, the
    // committed A. Before BP-138 TOSR stayed on the old BOS slot, the
    // stack read non-empty (TOSR != BOS) and the pop returned that slot:
    // a. the never-written sentinel (0, fd07's return to 0x0); b. a
    // committed entry (X). c. an entry pushed onto the empty stack
    // before the commit: its pop returns to BOS as the commit left it,
    // not to the slot its link names.
    // =============================================================
    // a. The old BOS slot is the reset sentinel, index 0.
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);   // commit stack R, bos 0
    push_one(ADDR_A);                       // idx1 (sentinel skip)
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-41a the return pops A from the speculative stack",
          (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_A));
    tick();
    check("TC-41a then the speculative stack is empty (tosr 0, bos 0)",
          (dut.tosr == 'd0) && (dut.bos == 'd0));
    commit_op(DIRECT_CALL, ADDR_A, 'd1);   // the call commits
    check("TC-41a the commit moved BOS to 1 and TOSR with it",
          (dut.bos == 'd1) && (dut.tosr == 'd1));
    check("TC-41a the commit-stack top is A",
          (int'(dut.c_cnt) == 2) && (dut.commit_ret_addr[1] == ADDR_A));
    check("TC-41a the sentinel slot 0 was never written",
          dut.spec_ret_addr[0] == '0);
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    // BP-152 A1: A's frame was popped by its return before the call
    // committed, so the frame the next return names is R, below it:
    // CSP-1-n, n 1 (A's dep 1 less the depth 0). Until BP-152 these two
    // checks expected A, the frame already consumed (fb_stale_top).
    check("TC-41a A1 p0 top of stack is the fallback below A's frame, R",
          (tos_valid_p0[0] == 1'b1) && (tos_addr_p0[0] == ADDR_R));
    check("TC-41a A1 the pop takes the fallback, R (not 0, not A)",
          (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_R));
    tick();
    check("TC-41a the fallback is not consumed: tosr 1, tosw 2, csp 2",
          (dut.tosr == 'd1) && (dut.tosw == 'd2) && (int'(dut.csp) == 2));

    // b. The old BOS slot is a committed entry, X (fd07's shape: BOS
    //    was a real slot, so the stale pop returned a real address and
    //    then followed X's link down the stack).
    do_reset();
    push_one(ADDR_X);                       // idx1
    commit_op(DIRECT_CALL, ADDR_X, 'd1);   // bos 1, commit top X
    push_one(ADDR_A);                       // idx2, bottom
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-41b the return pops A",
          (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_A));
    tick();
    check("TC-41b then tosr 1 == bos 1, empty",
          (dut.tosr == 'd1) && (dut.bos == 'd1));
    commit_op(DIRECT_CALL, ADDR_A, 'd2);   // bos 2, commit [X, A]
    check("TC-41b the commit moved BOS to 2 and TOSR with it",
          (dut.bos == 'd2) && (dut.tosr == 'd2));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    // BP-152 A1: as TC-41a, A's frame was popped first; the next frame
    // is X, now read from the commit stack below A (CSP-2), not from the
    // old BOS slot. Until BP-152 this expected A.
    check("TC-41b A1 the pop takes the fallback below A's frame, X",
          (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_X));
    tick();
    check("TC-41b the fallback moved nothing: tosr 2, tosw 3",
          (dut.tosr == 'd2) && (dut.tosw == 'd3));

    // c. A push onto the empty stack before the commit: B is pushed
    //    after A's pop, links to slot 1 (BOS then) and is a bottom
    //    entry. A's call then commits (BOS 2); TOSR is B, not BOS, so it
    //    stays. B's pop goes to BOS as it is now, 2, empty, and the next
    //    pop is the fallback A. Before BP-138 B's pop followed the link
    //    to slot 1, which read non-empty, and the next pop returned X.
    do_reset();
    push_one(ADDR_X);                       // idx1
    commit_op(DIRECT_CALL, ADDR_X, 'd1);   // bos 1, commit top X
    push_one(ADDR_A);                       // idx2
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();                                 // A popped, tosr 1
    push_one(ADDR_B);                       // idx3, links to 1
    check("TC-41c B is idx3, pushed onto the empty stack, linked to slot 1",
          (dut.tosr == 'd3) && (dut.spec_nos[3] == 'd1));
    commit_op(DIRECT_CALL, ADDR_A, 'd2);   // A's call commits
    check("TC-41c BOS 2, TOSR still B",
          (dut.bos == 'd2) && (dut.tosr == 'd3));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-41c the pop returns B from the speculative stack",
          (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_B));
    tick();
    check("TC-41c B's pop went to BOS as it is now (tosr 2), empty",
          (dut.tosr == 'd2) && (dut.bos == 'd2));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    // BP-152 A1: the first return popped A's frame, which then committed,
    // so the fallback is the frame below it, X: CSP-1-n, n 1 (A's dep 2
    // less the depth 1). Until BP-152 the fallback read the top, A, the
    // frame that return had consumed (fb_stale_top, BP-151), and this
    // check expected A.
    check("TC-41c A1 the next pop takes the fallback below A's popped frame, X",
          (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_X));
    tick();

    // =============================================================
    // TC-42 (BP-138, D2): TC-41b and TC-41c across a restore. For each,
    // one snapshot is taken before the commit moves BOS and one after.
    // A wrong path pushes two entries, the snapshot is restored, and
    // returns pop. TC-41b's snapshots are empty stacks (s1 tosr 1 bos
    // 1; s2 tosr 2 bos 2, the commit having moved TOSR with BOS): the
    // pop is the fallback A. TC-41c's hold B (s3 bos 1, s4 bos 2): the
    // pop returns B and the next is the fallback A. Before BP-138 s2
    // was tosr 1 bos 2 and its pop returned X, and after s4's B the pop
    // followed B's link to slot 1 and returned X.
    // =============================================================
    begin
      bp_ras_snapshot_t sn [0:3];
      for (int q = 0; q < 2; q++) begin
        // q 0: TC-41b's sequence, s1 and s2. q 1: TC-41c's, s3 and s4.
        // Each restores only its own snapshots: a restore of the other
        // sequence's TOSW would let the wrong path overwrite B.
        do_reset();
        push_one(ADDR_X);                   // idx1
        commit_op(DIRECT_CALL, ADDR_X, 'd1); // bos 1, commit top X
        push_one(ADDR_A);                   // idx2
        drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
        #1;
        if (q == 0) sn[0] = snap_p2[NUM_PRED_SLOTS-1]; // s1: A popped
        tick();
        if (q == 1) begin
          drive(1'b1, DIRECT_CALL, ADDR_B, 1'b0, NO_BRANCH, '0);
          #1;
          sn[2] = snap_p2[NUM_PRED_SLOTS-1]; // s3: after B's push
          tick();
        end
        commit_op(DIRECT_CALL, ADDR_A, 'd2); // bos 2, commit [X, A]
        drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
        #1;
        sn[2*q+1] = snap_p2[NUM_PRED_SLOTS-1]; // s2 / s4: after
        tick();
        // BP-142: the fourth field is the count of the TOSR entry, 0 for
        // the empty stacks s1 and s2 (SL2) and 0 for B, pushed once
        // with no recursion match (PU1), in s3 and s4.
        if (q == 0)
          check("TC-42 snapshots s1 (1,3,1,0) s2 (2,3,2,0)",
                (p4(sn[0]) == p4v(1, 3, 1, 0)) &&
                (p4(sn[1]) == p4v(2, 3, 2, 0)));
        else
          check("TC-42 snapshots s3 (3,4,1,0) s4 (3,4,2,0)",
                (p4(sn[2]) == p4v(3, 4, 1, 0)) &&
                (p4(sn[3]) == p4v(3, 4, 2, 0)));
        for (int k = 2 * q; k < 2 * q + 2; k++) begin
          // Wrong path: two pushes, then restore snapshot k.
          push_one(ADDR_C);
          push_one(ADDR_C + VA_WIDTH'(4));
          drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
          restore_val  = 1'b1;
          restore_snap = sn[k];
          tick();
          restore_val  = 1'b0;
          restore_snap = '0;
          if (q == 1) begin
            drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
            #1;
            check($sformatf("TC-42 restore s%0d, the pop returns B", k + 1),
                  (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_B));
            tick();
          end
          drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
          #1;
          // BP-152 A1: in both sequences A's frame was popped before its
          // call committed, so the fallback is X, the frame below it
          // (TC-41b, TC-41c). Until BP-152 every case expected A, the
          // popped frame.
          check($sformatf("TC-42 restore s%0d, A1 the pop is the fallback X",
                          k + 1),
                (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_X));
          tick();
          check($sformatf("TC-42 restore s%0d, then the stack is empty",
                          k + 1), dut.tosr == dut.bos);
        end
      end
    end

    // =============================================================
    // TC-43 (BP-138, D2): a p3 undo of an operation that began on an
    // empty stack, with a commit between p2 and p3 that moves BOS. The
    // undo restores TOSR to BOS as it is at the undo, not to the TOSR
    // registered at p2, which is the old BOS slot. a. undo-pop: a p2
    // return on the empty stack (the fallback, registered as a pop)
    // that p3 does not have. b. undo of a whole RETURN_CALL. In both,
    // A's call commits in the p2 cycle. Then a return pops: the stack
    // is empty, the pop is the fallback A. Without the rule the undo put
    // TOSR back on slot 1 with BOS 2 and the pop returned X.
    // =============================================================
    for (int v = 0; v < 2; v++) begin
      do_reset();
      push_one(ADDR_X);                     // idx1
      commit_op(DIRECT_CALL, ADDR_X, 'd1); // bos 1, commit top X
      push_one(ADDR_A);                     // idx2
      drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
      tick();                               // A popped: tosr 1 == bos
      // p2: the operation on the empty stack, and A's call commits.
      if (v == 0) drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
      else        drive(1'b1, RETURN_CALL, ADDR_B, 1'b0, NO_BRANCH, '0);
      commit_val       = 1'b1;
      commit_br_type   = DIRECT_CALL;
      commit_ret_addr  = ADDR_A;
      commit_snap.tosr = 'd2;
      #1;
      check($sformatf("TC-43%s p2 on the empty stack pops the fallback X",
                      (v == 0) ? "a" : "b"),
            (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_X));
      tick();
      commit_val       = 1'b0;
      commit_br_type   = NO_BRANCH;
      commit_ret_addr  = '0;
      commit_snap      = '0;
      check($sformatf("TC-43%s the commit moved BOS to 2",
                      (v == 0) ? "a" : "b"), dut.bos == 'd2);
      // p3: the operation is not there; the repair undoes it.
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
      tick();
      check($sformatf("TC-43%s the undo left the stack empty (tosr 2)",
                      (v == 0) ? "a" : "b"),
            (dut.tosr == 'd2) && (dut.bos == 'd2));
      drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
      #1;
      check($sformatf("TC-43%s a return then pops the fallback A, not X",
                      (v == 0) ? "a" : "b"),
            (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_A));
      tick();
    end

    // =============================================================
    // TC-44 (BP-140, Problem 4): a RETURN commit whose snapshot is an
    // empty stack leaves BOS where it is. A call pushes A (idx 1) and
    // its return pops it, emptying the stack: the return's snapshot is
    // tosr 0 bos 0, the BOS of that cycle. The call commits (BOS 1,
    // TOSR dragged to 1). Speculation then allocates every slot once
    // (push/pop pairs over idx 2..15) and B is pushed into idx 0, the
    // old BOS slot, which the sentinel skip no longer protects. Then
    // the return commits. Before BP-140 it moved BOS back to 0, B's
    // slot: TOSR == BOS read empty and the pop took the commit stack
    // (empty after the return committed) instead of B. Now BOS stays 1
    // and the pop returns B (CO5, final by Jeff's ruling, session-084).
    // BP-140 was prompted by a tb_fe_top region RS2 failure (TOSR 4
    // below BOS 5) judged by the old meaning of held; BP-143 found that
    // region does not fail without the exception, and this case is the
    // one that does. Since BP-144 the fault also fails the converse of
    // IV1 in the model and ras_assert RS4: TOSR == BOS over B, a live
    // chain entry BOS does not name.
    // =============================================================
    do_reset();
    push_one(ADDR_A);                       // idx1 (sentinel skip)
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-44 the return emptied the stack (tosr 0, bos 0)",
          (dut.tosr == 'd0) && (dut.bos == 'd0));
    commit_op(DIRECT_CALL, ADDR_A, 'd1);   // the call commits
    check("TC-44 the call commit moved BOS to 1, TOSR with it",
          (dut.bos == 'd1) && (dut.tosr == 'd1));
    for (int i = 2; i < RAS_SPEC_ENTRIES; i++) begin
      push_one(fill_addr[i]);
      drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
      tick();
    end
    check("TC-44 TOSW wrapped to the old BOS slot 0",
          (dut.tosw == 'd0) && (dut.tosr == 'd1));
    push_one(ADDR_B);
    check("TC-44 B is pushed into idx 0", (dut.tosr == 'd0)
          && (dut.spec_ret_addr[0] == ADDR_B));
    commit_op(RETURN, '0, 'd0);            // the return commits
    check("TC-44 the empty-snapshot return commit keeps BOS 1",
          (dut.bos == 'd1) && (dut.tosr == 'd0));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-44 the pop returns B from the speculative stack",
          (pop_valid_p2[0] == 1'b1) && (pop_addr_p2[0] == ADDR_B));
    tick();

    // =============================================================
    // TC-45 (BP-141, TD#194): a recursion count changed in place on the
    // wrong path, then a redirect. The restore takes TOSR, TOSW and BOS
    // from the snapshot (ras_decisions.md 4.3); the count is a field of
    // the entry, changed by a recursion push (st_push) or a recursion
    // pop (st_retract) without moving TOSR, so the pointers alone do
    // not put it back.
    //   a  the correct path pushes A (idx 1, count 0); snapshot S. The
    //      wrong path pushes A again: a recursion push, count 0 -> 1.
    //      Restore S. The count before the wrong path was 0.
    //   b  the correct path pushes A twice (count 1); snapshot S. The
    //      wrong path returns: a recursion pop, count 1 -> 0. Restore
    //      S. The count before the wrong path was 1.
    // Each checks the pointers (restored) and the count against its
    // value before the wrong path, then pops to show the stack the
    // correct path sees.
    // BP-142: TD#194 OPTION A (ruled session-084, ras_decisions.md 4.1,
    // 4.3, 12.9 RE6). The snapshot S is the DUT's own p2 snapshot of the
    // correct path's last operation (SL2), so it carries the count of
    // its TOSR entry; the restore writes it back. Run by default; until
    // BP-142 it ran only with +TD194 and failed 4 checks.
    // Expected values (RE5, RE6):
    //   a  S = {tosr 1, tosw 2, bos 0, rctr 0}: A pushed once (PU1, PU2
    //      cold-start skip to idx 1). After the restore rctr[1] = 0, so
    //      one pop returns A and leaves the stack empty (PO2/PO3), and
    //      the next pop has both stacks empty: valid 0 (PO6).
    //   b  S = {1, 2, 0, 1}: A pushed twice (PU5 raises rctr[1] to 1).
    //      After the restore rctr[1] = 1: two pops return A (PO1, then
    //      PO3).
    // =============================================================
    begin
      bp_ras_snapshot_t s45;
      logic [RAS_RCTR_WIDTH-1:0] c45;

      // -- a: a wrong-path recursion push.
      do_reset();
      drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
      #1;
      s45 = snap_p2[NUM_PRED_SLOTS-1];        // SL2: after A's push
      tick();                                 // idx1, count 0
      idle();                                 // p3 of the push agrees
      c45 = dut.spec_rctr[1];
      check("TC-45a the correct path: A at idx1, count 0, S {1,2,0,0}",
            (dut.tosr == 'd1) && (c45 == 'd0) &&
            (p4(s45) == p4v(1, 2, 0, 0)));
      push_one(ADDR_A);                       // wrong path: recursion
      idle();
      check("TC-45a the wrong path raised the count 0 -> 1, TOSR held",
            (dut.spec_rctr[1] == 'd1) && (dut.tosr == 'd1));
      restore_val  = 1'b1;
      restore_snap = s45;
      tick();
      restore_val  = 1'b0;
      restore_snap = '0;
      check("TC-45a the restore put the pointers back",
            (dut.tosr == s45.tosr) && (dut.tosw == s45.tosw)
            && (dut.bos == s45.bos));
      check({"TD#194 TC-45a the count is restored to its value before",
             " the wrong path (0)"}, dut.spec_rctr[1] == c45);
      pop_chk("TC-45a the first pop returns A", 0, 1'b1, ADDR_A);
      pop_chk({"TD#194 TC-45a the second pop finds both stacks empty (one",
               " A was pushed)"}, 0, 1'b0, '0);

      // -- b: a wrong-path recursion pop.
      do_reset();
      push_one(ADDR_A);                       // idx1, count 0
      drive(1'b1, DIRECT_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
      #1;
      s45 = snap_p2[NUM_PRED_SLOTS-1];        // after the recursion push
      tick();
      idle();
      c45 = dut.spec_rctr[1];
      check("TC-45b the correct path: A at idx1, count 1, S {1,2,0,1}",
            (dut.tosr == 'd1) && (c45 == 'd1) &&
            (p4(s45) == p4v(1, 2, 0, 1)));
      drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);  // wrong path
      tick();
      idle();
      check("TC-45b the wrong path lowered the count 1 -> 0, TOSR held",
            (dut.spec_rctr[1] == 'd0) && (dut.tosr == 'd1));
      restore_val  = 1'b1;
      restore_snap = s45;
      tick();
      restore_val  = 1'b0;
      restore_snap = '0;
      check("TC-45b the restore put the pointers back",
            (dut.tosr == s45.tosr) && (dut.tosw == s45.tosw)
            && (dut.bos == s45.bos));
      check({"TD#194 TC-45b the count is restored to its value before",
             " the wrong path (1)"}, dut.spec_rctr[1] == c45);
      for (int i = 0; i < 2; i++)
        pop_chk($sformatf("TD#194 TC-45b pop %0d returns A (two were pushed)",
                          i + 1), 0, 1'b1, ADDR_A);
    end

    // =============================================================
    // BP-142, Problem 3: one or more directed cases per rule of
    // ras_decisions.md 12, with the boundaries. Each case resets, seeds
    // its state through the ports, derives its expected values from the
    // rules named beside them, and runs beside the reference model,
    // which compares every pointer, entry and output every cycle.
    // Rule IDs are given in each check name. Cases that drive slot SL
    // run once at slot 0 and once at slot S1 (the same slot at one
    // slot).
    // =============================================================

    // =============================================================
    // TC-46 CL1, CL2, CL3: every type, valid and not valid, at each
    // slot. Seed: R committed (commit stack 1), A at idx1 (PU2 cold
    // skip: tosr 1, tosw 2, bos 0). The operand fall-through is B.
    // Expected after the edge:
    //   pred_val 0, or COND, INDIRECT_NONRET, DIRECT_UNC, NO_BRANCH
    //     -> nothing moves: tosr 1, tosw 2, entry 1 = {A,0,0,1} (CL3)
    //   DIRECT_CALL, INDIRECT_CALL -> push B: idx2 {B,0,1,0}, tosr 2,
    //     tosw 3 (CL1, PU1)
    //   RETURN -> pop A (bottom): tosr 0 == bos, entry 1 unchanged
    //     (CL2, PO3, PO4)
    //   RETURN_CALL -> pop A then push B on the empty stack: idx2
    //     {B,0,0,1} (PU1: bot 1 on an empty stack), tosr 2, tosw 3 (CL4)
    // =============================================================
    for (int sl = 0; sl < NUM_PRED_SLOTS; sl = sl + S1 + (S1 == 0 ? 1 : 0))
    for (int ti = 0; ti < 8; ti++)
    for (int v = 0; v < 2; v++) begin
      bp_br_type_e tt;
      logic        pu, po;
      tt = bp_br_type_e'(ti);
      pu = (v == 1) && ((tt == DIRECT_CALL) || (tt == INDIRECT_CALL) ||
                        (tt == RETURN_CALL));
      po = (v == 1) && ((tt == RETURN) || (tt == RETURN_CALL));
      do_reset();
      commit_op(DIRECT_CALL, ADDR_R, 'd0);
      push_one(ADDR_A);
      drv(sl, v[0], tt, ADDR_B);
      tick();
      if (pu && po)
        check($sformatf("TC-46 CL4 slot %0d %s v%0d: pop A then push B",
                        sl, tt.name(), v),
              ptr_is(2, 3, 0) && ent_is(2, ADDR_B, 0, 0, 1) &&
              ent_is(1, ADDR_A, 0, 0, 1));
      else if (pu)
        check($sformatf("TC-46 CL1 slot %0d %s v%0d: push B", sl,
                        tt.name(), v),
              ptr_is(2, 3, 0) && ent_is(2, ADDR_B, 0, 1, 0) &&
              ent_is(1, ADDR_A, 0, 0, 1));
      else if (po)
        check($sformatf("TC-46 CL2 slot %0d %s v%0d: pop A", sl,
                        tt.name(), v),
              ptr_is(0, 2, 0) && ent_is(1, ADDR_A, 0, 0, 1));
      else
        check($sformatf("TC-46 CL3 slot %0d %s v%0d: nothing moves", sl,
                        tt.name(), v),
              ptr_is(1, 2, 0) && ent_is(1, ADDR_A, 0, 0, 1) &&
              ent_is(2, '0, 0, 0, 0));
    end

    // =============================================================
    // TC-47 RT1, RT2. Dirty every kind of state (an entry with a count,
    // a link and a bottom bit, a commit entry, and a pending p2
    // operation for p3), hold rstn low for ONE edge, and read it all
    // back as zero (RT1, ras_interfaces.md 10). While rstn is low a
    // driven push changes nothing (RT1: reset acts while rstn is low).
    // In the first cycle after reset, a return finds both stacks empty:
    // ras_pop_valid_p2 and ras_tos_valid_p0 low (RT2, PO6, P03).
    // =============================================================
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    push_one(ADDR_A);
    push_one(ADDR_A);                           // rctr[1] 1
    push_one(ADDR_B);                           // idx2, nos 1
    drive(1'b1, DIRECT_CALL, ADDR_C, 1'b0, NO_BRANCH, '0);
    @(posedge clk);                             // C pushed, op registered
    #1;
    rstn = 1'b0;                                // one edge low, push held
    @(posedge clk);
    #1;
    rstn = 1'b1;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      pred_val_p2[s] = 1'b0; br_type_p2[s] = NO_BRANCH; fall_p2[s] = '0;
      pred_val_p3[s] = 1'b0; br_type_p3[s] = NO_BRANCH;
      prev_val[s] = 1'b0; prev_typ[s] = NO_BRANCH;
    end
    begin
      logic z;
      z = ptr_is(0, 0, 0) && (dut.csp == '0) && (dut.c_cnt == '0);
      for (int i = 0; i < RAS_SPEC_ENTRIES; i++)
        z = z && ent_is(i, '0, 0, 0, 0);
      for (int i = 0; i < RAS_COMMIT_ENTRIES; i++)
        z = z && (dut.commit_ret_addr[i] == '0);
      for (int s = 0; s < NUM_PRED_SLOTS; s++)
        z = z && (dut.p3_op_q[s] == 2'b00) && (dut.p3_fallthr_q[s] == '0)
              && (dut.p3_pre_tosr_q[s] == '0) && !dut.p3_pre_empty_q[s]
              && !dut.p3_pop_dec_q[s] && !dut.p3_push_inc_q[s]
              && !dut.p3_push_sat_q[s] && (dut.p3_inc_ptr_q[s] == '0);
      check("TC-47 RT1 one reset edge clears every pointer, entry and register",
            z);
    end
    drv(0, 1'b1, RETURN, '0);
    #1;
    check("TC-47 RT2 first cycle after reset: pop and p0 valid low",
          (pop_valid_p2[0] == 1'b0) && (tos_valid_p0[0] == 1'b0) &&
          (tos_valid_p0[S1] == 1'b0) && (pop_valid_p2[S1] == 1'b0));
    tick();
    // CL1 in the first cycle after reset: the push is made (the rule has
    // no exception for that cycle). A at idx1 by the cold skip (PU2).
    drv(0, 1'b1, DIRECT_CALL, ADDR_A);
    tick();
    check("TC-47 CL1 a push in the first cycles after reset is made",
          ptr_is(1, 2, 0) && ent_is(1, ADDR_A, 0, 0, 1));
    // rstn low with a push driven: nothing is pushed (RT1).
    rstn = 1'b0;
    drv(0, 1'b1, DIRECT_CALL, ADDR_B);
    @(posedge clk);
    #1;
    check("TC-47 RT1 a push while rstn is low is not made",
          ptr_is(0, 0, 0) && ent_is(1, '0, 0, 0, 0) && ent_is(2, '0, 0, 0, 0));
    do_reset();

    // TC-47c CL1 in the cycle rstn rises: the first cycle after reset.
    rstn = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    rstn = 1'b1;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      pred_val_p3[s] = 1'b0; br_type_p3[s] = NO_BRANCH;
      prev_val[s] = 1'b0; prev_typ[s] = NO_BRANCH;
    end
    drv(0, 1'b1, DIRECT_CALL, ADDR_A);
    tick();
    check("TC-47c CL1 a push in the very first cycle after reset is made",
          ptr_is(1, 2, 0) && ent_is(1, ADDR_A, 0, 0, 1));

    // =============================================================
    // TC-48 P01 to P05. Expected: P03 both empty -> valid 0; P02 commit
    // only -> the CSP-1 entry; P01 speculative non-empty -> ret[TOSR]
    // (over the commit top); P04 a push in the same cycle does not
    // change the read before the edge; P05 every slot the same value.
    // =============================================================
    do_reset();
    #1;
    check("TC-48 P03 both stacks empty: p0 valid 0",
          !tos_valid_p0[0] && !tos_valid_p0[S1]);
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    commit_op(DIRECT_CALL, ADDR_X, 'd0);
    #1;
    check("TC-48 P02 commit only: the CSP-1 entry X, valid",
          tos_valid_p0[0] && (tos_addr_p0[0] == ADDR_X));
    drv(S1, 1'b1, DIRECT_CALL, ADDR_A);
    #1;
    check("TC-48 P04 the same-cycle push is not seen before the edge",
          tos_valid_p0[0] && (tos_addr_p0[0] == ADDR_X));
    tick();
    check("TC-48 P01 speculative top A over the commit top",
          tos_valid_p0[0] && (tos_addr_p0[0] == ADDR_A));
    begin
      logic same;
      same = 1'b1;
      for (int s = 0; s < NUM_PRED_SLOTS; s++)
        same = same && (tos_valid_p0[s] == tos_valid_p0[0]) &&
               (tos_addr_p0[s] == tos_addr_p0[0]);
      check("TC-48 P05 every slot presents the same p0 value", same);
    end

    // =============================================================
    // TC-49 PU1, PU7, PU8 at each slot. (a) push onto a non-empty
    // stack: {ft, 0, nos = TOSR, bot 0}. (b) push onto a stack emptied
    // by a pop with TOSW != BOS: no skip, allocation at TOSW with
    // nos = TOSR = BOS and bot 1. (c) PU7: the empty stack's stale
    // ret_addr[TOSR] equals the push address, and the push allocates
    // (TC-41a's path puts BOS on A's slot). PU8: an address ending in 2
    // is written as given.
    // =============================================================
    for (int sl = 0; sl < NUM_PRED_SLOTS; sl = sl + S1 + (S1 == 0 ? 1 : 0))
    begin
      do_reset();
      push_one(ADDR_A);                       // idx1
      drv(sl, 1'b1, DIRECT_CALL, ADDR_B + VA_WIDTH'(2));
      tick();
      check($sformatf("TC-49a PU1 PU8 slot %0d: idx2 {B+2,0,1,0}", sl),
            ptr_is(2, 3, 0) && ent_is(2, ADDR_B + VA_WIDTH'(2), 0, 1, 0));
      pop_chk("TC-49b pop B+2", 0, 1'b1, ADDR_B + VA_WIDTH'(2));
      pop_chk("TC-49b pop A, empty", 0, 1'b1, ADDR_A);
      check("TC-49b the stack is empty with tosw 3 != bos 0", ptr_is(0, 3, 0));
      drv(sl, 1'b1, DIRECT_CALL, ADDR_C);
      tick();
      check($sformatf("TC-49b PU1 slot %0d: idx3 {C,0,0,1} (empty: bot 1)",
                      sl), ptr_is(3, 4, 0) && ent_is(3, ADDR_C, 0, 0, 1));
      // (c) PU7: TC-41a's path: A pushed, popped, its call commits.
      do_reset();
      commit_op(DIRECT_CALL, ADDR_R, 'd0);
      push_one(ADDR_A);                       // idx1
      pop_chk("TC-49c pop A", 0, 1'b1, ADDR_A);
      commit_op(DIRECT_CALL, ADDR_A, 'd1);   // bos 1, tosr dragged (CO6)
      check("TC-49c empty at bos 1, ret[1] == A", ptr_is(1, 2, 1) &&
            (dut.spec_ret_addr[1] == ADDR_A));
      drv(sl, 1'b1, DIRECT_CALL, ADDR_A);
      tick();
      check($sformatf("TC-49c PU7 slot %0d: no match on empty, A at idx2",
                      sl), ptr_is(2, 3, 1) && ent_is(2, ADDR_A, 0, 1, 1) &&
            (dut.spec_rctr[1] == 'd0));
    end

    // =============================================================
    // TC-50 PU2, PU3, PU4, PM1: one entry, 15 entries, full, the wrap.
    // From reset, RAS_SPEC_ENTRIES - 1 = 15 pushes of distinct
    // addresses fill idx1..15 (PU2 cold skip first): tosr 15, tosw 0 =
    // BOS. Full is TOSW + 1 == BOS (PU4): push k lands at idx k and
    // leaves TOSW = k + 1, so TOSW + 1 == BOS (0) after 14 pushes, with
    // one push remaining; the 15th leaves TOSW == BOS (PU4 reads "15
    // allocations", one more than the definition gives: reported).
    // The 16th push takes the skip: idx1 {X, 0, nos 0, bot 1}, tosr 1,
    // tosw 2 (PU2). Its pop leaves the stack empty (PU3, PO3); the next
    // pop is the commit fallback R (PO5); idx2..15 stay resident.
    // =============================================================
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    push_one(fill_addr[0]);
    check("TC-50 one entry: tosr 1, tosw 2", ptr_is(1, 2, 0));
    for (int i = 1; i < RAS_SPEC_ENTRIES - 2; i++) push_one(fill_addr[i]);
    // BP-153: the counts are RAS_SPEC_ENTRIES' (16; 32 in BP-153, RC11,
    // reverted by BP-154; the names keep the 16-entry numbers).
    check("TC-50 PU4 14 allocations: tosw + 1 == bos (full, one push left)",
          RAS_PTR_BITS'(dut.tosw + 1) == dut.bos);
    push_one(fill_addr[RAS_SPEC_ENTRIES - 2]);
    check("TC-50 15 entries: tosr 15, tosw 0 == bos",
          ptr_is(RAS_SPEC_ENTRIES - 1, 0, 0) &&
          ent_is(RAS_SPEC_ENTRIES - 1, fill_addr[RAS_SPEC_ENTRIES - 2], 0,
                 RAS_PTR_BITS'(RAS_SPEC_ENTRIES - 2), 0));
    push_one(ADDR_X);
    check("TC-50 PU2 the wrap: X at idx1 {X,0,0,1}, tosr 1, tosw 2",
          ptr_is(1, 2, 0) && ent_is(1, ADDR_X, 0, 0, 1));
    pop_chk("TC-50 PU3 the skip entry pops X", 0, 1'b1, ADDR_X);
    check("TC-50 PU3 then the stack is empty", ptr_is(0, 2, 0));
    pop_chk("TC-50 PU3 the next pop is the commit fallback R", 0, 1'b1, ADDR_R);
    begin
      logic res;
      res = 1'b1;
      for (int i = 2; i < RAS_SPEC_ENTRIES; i++)
        res = res && (dut.spec_ret_addr[i] == fill_addr[i - 1]);
      check("TC-50 PU3 the older entries stay resident", res);
    end
    // PU4 counts allocations, not live entries: 15 push/pop pairs leave
    // nothing live and TOSW == BOS, so the next push takes the skip.
    do_reset();
    for (int i = 0; i < RAS_SPEC_ENTRIES - 1; i++) begin
      push_one(fill_addr[i]);
      pop_chk($sformatf("TC-50 PU4 pair %0d", i), 0, 1'b1, fill_addr[i]);
    end
    check("TC-50 PU4 15 pairs: empty, tosw wrapped to bos", ptr_is(0, 0, 0));
    push_one(ADDR_C);
    check("TC-50 PU4 the next push skips to idx1", ptr_is(1, 2, 0) &&
          ent_is(1, ADDR_C, 0, 0, 1));

    // =============================================================
    // TC-51 PU5, PU6, PO1: rctr 0, 1, 14, 15. A pushed once (count 0),
    // then 15 recursion pushes take it to 15 one at a time; each moves
    // only rctr[1] (PU5); at 15 a further push changes nothing (PU6).
    // Then 15 pops decrement it to 0 holding TOSR (PO1), and the 16th
    // pops A (PO3). Checked at the boundaries 0, 1, 14, 15.
    // =============================================================
    do_reset();
    push_one(ADDR_A);
    check("TC-51 rctr 0", ent_is(1, ADDR_A, 0, 0, 1) && ptr_is(1, 2, 0));
    for (int c = 1; c <= int'(M_RCTR_MAX); c++) begin
      push_one(ADDR_A);
      if ((c == 1) || (c == int'(M_RCTR_MAX) - 1) || (c == int'(M_RCTR_MAX)))
        check($sformatf("TC-51 PU5 rctr %0d, only the count moved", c),
              ent_is(1, ADDR_A, RAS_RCTR_WIDTH'(c), 0, 1) && ptr_is(1, 2, 0));
    end
    push_one(ADDR_A);
    check("TC-51 PU6 a push at 15 changes nothing",
          ent_is(1, ADDR_A, M_RCTR_MAX, 0, 1) && ptr_is(1, 2, 0));
    for (int c = int'(M_RCTR_MAX); c > 0; c--) begin
      pop_chk($sformatf("TC-51 PO1 pop at rctr %0d returns A", c), 0, 1'b1,
              ADDR_A);
      if ((c == 1) || (c == 2) || (c == int'(M_RCTR_MAX)))
        check($sformatf("TC-51 PO1 rctr %0d -> %0d, tosr held", c, c - 1),
              ent_is(1, ADDR_A, RAS_RCTR_WIDTH'(c - 1), 0, 1) &&
              ptr_is(1, 2, 0));
    end
    pop_chk("TC-51 PO3 the last pop returns A", 0, 1'b1, ADDR_A);
    check("TC-51 PO3 then empty", ptr_is(0, 2, 0));

    // =============================================================
    // TC-52 PO2, PO3, PO4, PO6, PO9 at each slot. Stack A(1) B(2,
    // nos 1). (a) PO9: a non-pop type at the slot drives valid 0. (b)
    // PO2: pop B, TOSR = nos = 1; PO4: no ret/nos/bot written, TOSW
    // and BOS held. (c) PO3: pop A (bottom), TOSR = BOS. (d) PO6: both
    // stacks empty, valid 0.
    // =============================================================
    for (int sl = 0; sl < NUM_PRED_SLOTS; sl = sl + S1 + (S1 == 0 ? 1 : 0))
    begin
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_B);
      drv(sl, 1'b1, DIRECT_UNC, '0);
      #1;
      check($sformatf("TC-52 PO9 slot %0d: no pop, valid 0", sl),
            pop_valid_p2[sl] == 1'b0);
      tick();
      pop_chk($sformatf("TC-52 PO2 slot %0d pops B", sl), sl, 1'b1, ADDR_B);
      check("TC-52 PO2 PO4 tosr = nos 1, entries and tosw/bos unchanged",
            ptr_is(1, 3, 0) && ent_is(2, ADDR_B, 0, 1, 0) &&
            ent_is(1, ADDR_A, 0, 0, 1));
      pop_chk($sformatf("TC-52 PO3 slot %0d pops A", sl), sl, 1'b1, ADDR_A);
      check("TC-52 PO3 tosr = bos", ptr_is(0, 3, 0));
      pop_chk($sformatf("TC-52 PO6 slot %0d both empty", sl), sl, 1'b0, '0);
    end

    // =============================================================
    // TC-53 PO5 with a commit count of 0, 1, 31 and 32, and CO2, CO3,
    // CO10. Commit pushes cs_ad(6_0000, i); after k pushes the fallback
    // and the p0 read are cs_ad(k-1), valid iff k > 0. A pop on the
    // speculative-empty stack moves nothing (PO5).
    // =============================================================
    do_reset();
    pop_chk("TC-53 PO5 count 0: valid 0", 0, 1'b0, '0);
    for (int k = 1; k <= RAS_COMMIT_ENTRIES; k++) begin
      commit_op(DIRECT_CALL, cs_ad(32'h6_0000, k - 1), 'd0);
      if ((k == 1) || (k == RAS_COMMIT_ENTRIES - 1) ||
          (k == RAS_COMMIT_ENTRIES)) begin
        check($sformatf("TC-53 CO2 count %0d", k), int'(dut.c_cnt) == k);
        pop_chk($sformatf("TC-53 PO5 count %0d: the fallback is entry %0d", k,
                          k - 1), 0, 1'b1, cs_ad(32'h6_0000, k - 1));
        check($sformatf("TC-53 PO5 count %0d: nothing moved", k),
              ptr_is(0, 0, 0) && (int'(dut.c_cnt) == k));
      end
    end
    commit_op(DIRECT_CALL, ADDR_X, 'd0);
    check({"TC-53 CO2 a call on a full stack: count holds at ",
           "RAS_COMMIT_ENTRIES, X on top"},
          (int'(dut.c_cnt) == RAS_COMMIT_ENTRIES) && tos_valid_p0[0] &&
          (tos_addr_p0[0] == ADDR_X));
    for (int k = RAS_COMMIT_ENTRIES; k > 0; k--)
      commit_op(RETURN, '0, 'd0);
    #1;
    check("TC-53 CO10 RAS_COMMIT_ENTRIES returns empty it",
          !tos_valid_p0[0] &&
          (dut.c_cnt == '0));
    // 33 pushes and 32 returns leave CSP at 33 - 32 = 1 (mod 32).
    commit_op(RETURN, '0, 'd0);
    check("TC-53 CO3 a return on an empty commit stack does nothing",
          (dut.c_cnt == '0) && (int'(dut.csp) == 1));

    // =============================================================
    // TC-54 RC1, RC2: RETURN_CALL whose push meets the sentinel skip and
    // saturation. (a) A at idx1 then 14 more distinct pushes (tosw 0 =
    // bos): RETURN_CALL pops f14 at 15 (TOSR 14) and its push allocates
    // at TOSW 0 == BOS, so takes the skip: idx1 {B,0,0,1} (PU2), tosr
    // 1, tosw 2. (b) A at idx1 with rctr 15, X above: RETURN_CALL with
    // fall-through A pops X (TOSR 1) and its push meets A at 15:
    // nothing changes (PU6). (c) RC1: the fallback: empty speculative,
    // commit R: the pop returns R (TC-23).
    // =============================================================
    do_reset();
    for (int i = 0; i < RAS_SPEC_ENTRIES - 1; i++) push_one(fill_addr[i]);
    drv(0, 1'b1, RETURN_CALL, ADDR_B);
    #1;
    // BP-153: the last fill, fill_addr[RAS_SPEC_ENTRIES - 2] (f14 at 16).
    check("TC-54a RC1 the pop returns f14",
          pop_valid_p2[0] &&
          (pop_addr_p2[0] == fill_addr[RAS_SPEC_ENTRIES - 2]));
    tick();
    check("TC-54a RC2 the push takes the skip: idx1 {B,0,0,1}",
          ptr_is(1, 2, 0) && ent_is(1, ADDR_B, 0, 0, 1));
    do_reset();
    for (int i = 0; i <= int'(M_RCTR_MAX); i++) push_one(ADDR_A);
    push_one(ADDR_X);
    drv(S1, 1'b1, RETURN_CALL, ADDR_A);
    #1;
    check("TC-54b RC1 the pop returns X", pop_valid_p2[S1] &&
          (pop_addr_p2[S1] == ADDR_X));
    tick();
    check("TC-54b RC2 the push meets A at 15: nothing changes",
          ptr_is(1, 3, 0) && ent_is(1, ADDR_A, M_RCTR_MAX, 0, 1));
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    drv(S1, 1'b1, RETURN_CALL, ADDR_B);
    #1;
    check("TC-54c RC1 the fallback R", pop_valid_p2[S1] &&
          (pop_addr_p2[S1] == ADDR_R));
    tick();

    // =============================================================
    // TC-55 SL2: the snapshot's fourth field. (a) empty stack: rctr 0
    // even when ret[BOS] has a count (none here; the field is 0 by the
    // empty rule). (b) after a recursion push to count 3: rctr 3. (c)
    // after a pop that leaves count 2: rctr 2. (d) after a pop that
    // moves TOSR to an entry with count 0: 0. (e) present with
    // pred_val 0: the current state.
    // =============================================================
    do_reset();
    drv(0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-55a SL2 empty stack: snapshot {0,0,0,0}",
          (snap_p2[0] == '0) && (snap_p2[S1] == '0));
    tick();
    push_one(ADDR_A);                         // idx1
    push_one(ADDR_B);                         // idx2
    push_one(ADDR_B);
    push_one(ADDR_B);                         // rctr[2] 2
    drv(0, 1'b1, DIRECT_CALL, ADDR_B);
    #1;
    check("TC-55b SL2 after the recursion push: {2,3,0,3}",
          p4(snap_p2[0]) == p4v(2, 3, 0, 3));
    tick();
    drv(0, 1'b1, RETURN, '0);
    #1;
    check("TC-55c SL2 after a count pop: {2,3,0,2}",
          p4(snap_p2[0]) == p4v(2, 3, 0, 2));
    tick();
    drv(0, 1'b0, RETURN, '0);
    #1;
    check("TC-55e SL2 pred_val 0: the current state {2,3,0,2}",
          (p4(snap_p2[0]) == p4v(2, 3, 0, 2)) &&
          (p4(snap_p2[S1]) == p4v(2, 3, 0, 2)));
    tick();
    pop_chk("TC-55 pop", 0, 1'b1, ADDR_B);
    pop_chk("TC-55 pop", 0, 1'b1, ADDR_B);
    drv(0, 1'b1, RETURN, '0);
    #1;
    check("TC-55d SL2 after B is popped to A (count 0): {1,3,0,0}",
          p4(snap_p2[0]) == p4v(1, 3, 0, 0));
    tick();

    // =============================================================
    // TC-56 SL1, SL3 (two slots). SL3: one slot a RAS type, the other
    // valid with a non-RAS type: the other changes nothing, so slot 1's
    // snapshot equals slot 0's when slot 1 is not a RAS type, and slot
    // 0's equals the state when slot 0 is not. SL1: a slot 1 pop reads
    // the top a slot 0 push left (TC-06, and here with a count: A at
    // idx1, slot 0 pushes A (rctr 1), slot 1 pops: A, count back to 0).
    // =============================================================
    if (NUM_PRED_SLOTS > 1) begin
      do_reset();
      push_one(ADDR_A);
      drive(1'b1, DIRECT_CALL, ADDR_B, 1'b1, COND, ADDR_C);
      #1;
      check("TC-56 SL3 slot 0 push, slot 1 COND: snap[1] == snap[0]",
            (snap_p2[S1] == snap_p2[0]) &&
            (p4(snap_p2[0]) == p4v(2, 3, 0, 0)));
      tick();
      check("TC-56 SL3 only B was pushed", ptr_is(2, 3, 0));
      drive(1'b1, DIRECT_UNC, ADDR_C, 1'b1, RETURN, '0);
      #1;
      check("TC-56 SL3 slot 0 DIRECT_UNC: snap[0] is the state",
            p4(snap_p2[0]) == p4v(2, 3, 0, 0));
      check("TC-56 SL3 slot 1 pops B", pop_valid_p2[S1] &&
            (pop_addr_p2[S1] == ADDR_B));
      tick();
      do_reset();
      push_one(ADDR_A);
      drive(1'b1, DIRECT_CALL, ADDR_A, 1'b1, RETURN, '0);
      #1;
      check("TC-56 SL1 slot 1 pops the A slot 0's recursion push raised",
            pop_valid_p2[S1] && (pop_addr_p2[S1] == ADDR_A) &&
            (p4(snap_p2[0]) == p4v(1, 2, 0, 1)) &&
            (p4(snap_p2[S1]) == p4v(1, 2, 0, 0)));
      tick();
      check("TC-56 SL1 the count is back to 0, tosr 1",
            ptr_is(1, 2, 0) && ent_is(1, ADDR_A, 0, 0, 1));
    end else begin
      $display("SKIP TC-56 SL1/SL3: needs NUM_PRED_SLOTS > 1");
    end

    // =============================================================
    // TC-57 RE3, RE4. (a) RE3: a restore cycle's p2 push is not made
    // and is registered as none: the next cycle, with a p3 view of
    // "none", repairs nothing (an undo-push would move TOSR). (b) RE4:
    // the cycle after a p2 push, a restore and a p3 view of none (an
    // undo-push): the undo is dropped; the pointers are the snapshot's.
    // (c) RE4: the missed push of a restore cycle is not made.
    // =============================================================
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_B);                         // tosr 2, tosw 3
    drv(0, 1'b1, DIRECT_CALL, ADDR_C);
    restore_val = 1'b1; restore_snap = snp(1, 2, 0, 0);
    tick();
    restore_val = 1'b0; restore_snap = '0;
    check("TC-57a RE1 RE3 pointers are the snapshot's, C not pushed",
          ptr_is(1, 2, 0) && (dut.spec_ret_addr[2] == ADDR_B));
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-57a RE3 registered as none: no repair the next cycle",
          ptr_is(1, 2, 0));
    do_reset();
    push_one(ADDR_A);
    drv(0, 1'b1, DIRECT_CALL, ADDR_B);
    tick();                                   // B at idx2, op PUSH
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);    // undo-push wanted
    restore_val = 1'b1; restore_snap = snp(2, 3, 0, 0);
    tick();
    restore_val = 1'b0; restore_snap = '0;
    check("TC-57b RE4 the undo-push of the restore cycle is dropped",
          ptr_is(2, 3, 0));
    do_reset();
    push_one(ADDR_A);
    drive(1'b0, NO_BRANCH, ADDR_C, 1'b0, NO_BRANCH, '0);
    tick();                                   // op NONE, ft C
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b1, DIRECT_CALL, 1'b0, NO_BRANCH);  // a missed push
    restore_val = 1'b1; restore_snap = snp(1, 2, 0, 0);
    tick();
    restore_val = 1'b0; restore_snap = '0;
    check("TC-57c RE4 the missed push of the restore cycle is not made",
          ptr_is(1, 2, 0) && (dut.spec_ret_addr[2] == '0));

    // =============================================================
    // TC-58 RE6 (Problem 1). (a) A restore with an EMPTY snapshot
    // (tosr == bos) writes no count, even with a non-zero rctr field:
    // A at idx1 with count 2; restore {1, 2, 1, 7}: tosr == bos, so
    // rctr[1] stays 2. (b) No other entry's count changes: A(1) B(2);
    // snapshot S after B {2,3,0,0}; the wrong path pops B and pushes A
    // (recursion on A, count 0 -> 1); restore S: rctr[2] = 0 from S,
    // rctr[1] keeps the wrong path's 1 (3.2: a count below the top keeps
    // the wrong-path value). (c) a restore with a non-empty snapshot
    // writes the field even into a count the wrong path did not change.
    // =============================================================
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_A);
    push_one(ADDR_A);                         // rctr[1] 2
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    restore_val = 1'b1; restore_snap = snp(1, 2, 1, 7);
    tick();
    restore_val = 1'b0; restore_snap = '0;
    check("TC-58a RE6 empty snapshot: no count written, rctr[1] stays 2",
          ptr_is(1, 2, 1) && (dut.spec_rctr[1] == 'd2));
    do_reset();
    push_one(ADDR_A);
    drv(0, 1'b1, DIRECT_CALL, ADDR_B);
    #1;
    begin
      bp_ras_snapshot_t s58;
      s58 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      check("TC-58b S = {2,3,0,0}", p4(s58) == p4v(2, 3, 0, 0));
      pop_chk("TC-58b wrong path pops B", 0, 1'b1, ADDR_B);
      push_one(ADDR_A);                       // recursion on A: 0 -> 1
      check("TC-58b the wrong path raised rctr[1] to 1",
            dut.spec_rctr[1] == 'd1);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s58;
      tick();
      restore_val = 1'b0; restore_snap = '0;
      check("TC-58b RE6 rctr[2] from S (0), rctr[1] keeps the wrong path's 1",
            ptr_is(2, 3, 0) && (dut.spec_rctr[2] == 'd0) &&
            (dut.spec_rctr[1] == 'd1));
    end
    do_reset();
    push_one(ADDR_A);
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    restore_val = 1'b1; restore_snap = snp(1, 2, 0, 5);
    tick();
    restore_val = 1'b0; restore_snap = '0;
    check("TC-58c RE6 a non-empty snapshot writes its rctr (5) at tosr",
          ptr_is(1, 2, 0) && (dut.spec_rctr[1] == 'd5));

    // =============================================================
    // TC-59 RE7, RE8. RE7: snapshot S after A {1,2,0,0}; the wrong path
    // wraps (16 pushes overwrite idx1); restore S: not exact, only the
    // bound: the pops reach the empty stack within RAS_SPEC_ENTRIES
    // pops and then take the commit fallback R. RE8: ras_flush_val and
    // ras_flush_snapshot driven with values every cycle change nothing:
    // the model, which ignores them, still agrees everywhere.
    // =============================================================
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    drv(0, 1'b1, DIRECT_CALL, ADDR_A);
    #1;
    begin
      bp_ras_snapshot_t s59;
      int n59;
      s59 = snap_p2[0];
      tick();
      for (int i = 0; i < RAS_SPEC_ENTRIES; i++) push_one(fill_addr[i]);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s59;
      tick();
      restore_val = 1'b0; restore_snap = '0;
      n59 = 0;
      while ((dut.tosr != dut.bos) && (n59 <= RAS_SPEC_ENTRIES)) begin
        drv(0, 1'b1, RETURN, '0);
        tick();
        n59++;
      end
      check($sformatf("TC-59 RE7 empty after %0d pops (bound %0d)", n59,
                      RAS_SPEC_ENTRIES), n59 <= RAS_SPEC_ENTRIES);
      pop_chk("TC-59 RE7 then the commit fallback R", 0, 1'b1, ADDR_R);
    end
    do_reset();
    for (int i = 0; i < 6; i++) begin
      flush_val  = 1'b1;
      flush_snap = snp(7, 9, 3, 5);
      if (i < 3) push_one(fill_addr[i]);
      else pop_chk("TC-59 RE8 pop", 0, 1'b1, fill_addr[5 - i]);
    end
    flush_val = 1'b0; flush_snap = '0;
    check("TC-59 RE8 the flush port moved nothing: empty, tosw 4",
          ptr_is(0, 4, 0));

    // =============================================================
    // TC-60 RP1 for a bottom entry, RP6 by PO1 and PO3, RP7 with the
    // skip and no recursion match, at each slot.
    // (a) RP1: A pushed onto the empty stack (bottom) while a commit
    // moves BOS: R committed earlier at bos 0; A's push at idx1 in the
    // cycle a commit with snapshot tosr 1 moves BOS to 1 -- TOSR is A,
    // not BOS, so no drag. Then p3 says no call: TOSR follows the
    // pushed entry, which is bottom: BOS as it is at the undo (1).
    // (b) RP6 by PO1: A twice (count 1); missed pop decrements it. By
    // PO3: the missed pop of a bottom entry: TOSR = BOS.
    // (c) RP7: the registered fall-through equals ret[TOSR] (A): no
    // match, A allocated at idx2 (never the recursion match).
    // (d) RP7 with the skip: 15 pushes (tosw == bos), a missed push of
    // B allocates at bos+1 = 1 {B,0,0,1}.
    // =============================================================
    for (int sl = 0; sl < NUM_PRED_SLOTS; sl = sl + S1 + (S1 == 0 ? 1 : 0))
    begin
      // X at idx1, its call commits: BOS 1, TOSR 1 (empty). A is
      // pushed onto the empty stack: idx2 {A,0,nos 1,bot 1}. In A's p2
      // cycle a RETURN_CALL commit with snapshot tosr 0 moves BOS to 0
      // (CO5: a RETURN_CALL always moves it); the scan's TOSR 2 is not
      // BOS 1, so TOSR stays 2 (CO6). The undo of A: bottom, so TOSR
      // goes to BOS as it is at the undo, 0 -- not to its link, 1.
      do_reset();
      push_one(ADDR_X);
      commit_op(DIRECT_CALL, ADDR_X, 'd1);
      check("TC-60a X committed: tosr 1 == bos 1", ptr_is(1, 2, 1));
      drv(sl, 1'b1, DIRECT_CALL, ADDR_A);
      commit_val = 1'b1; commit_br_type = RETURN_CALL;
      commit_ret_addr = ADDR_C; commit_snap = snp(0, 2, 1, 0);
      tick();
      commit_val = 1'b0; commit_br_type = NO_BRANCH; commit_snap = '0;
      check($sformatf("TC-60a slot %0d A at idx2 (bottom, nos 1), bos 0",
                      sl), ptr_is(2, 3, 0) && ent_is(2, ADDR_A, 0, 1, 1));
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
      tick();
      check("TC-60a RP1 the undo of a bottom push: tosr = bos (0), not nos 1",
            ptr_is(0, 3, 0));
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_A);                       // count 1
      idle();
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(sl == 0, RETURN, sl != 0, RETURN);
      tick();
      check($sformatf("TC-60b RP6 by PO1 slot %0d: count 1 -> 0, tosr held",
                      sl), ptr_is(1, 2, 0) && (dut.spec_rctr[1] == 'd0));
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(sl == 0, RETURN, sl != 0, RETURN);
      tick();
      check($sformatf("TC-60b RP6 by PO3 slot %0d: bottom A, tosr = bos",
                      sl), ptr_is(0, 2, 0));
      do_reset();
      push_one(ADDR_A);
      drv(sl, 1'b0, NO_BRANCH, ADDR_A);
      tick();                                 // op none, ft A
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(sl == 0, DIRECT_CALL, sl != 0, DIRECT_CALL);
      tick();
      check($sformatf("TC-60c RP7 slot %0d: no recursion match, A at idx2",
                      sl), ptr_is(2, 3, 0) && ent_is(2, ADDR_A, 0, 1, 0) &&
            (dut.spec_rctr[1] == 'd0));
      do_reset();
      for (int i = 0; i < RAS_SPEC_ENTRIES - 1; i++) push_one(fill_addr[i]);
      drv(sl, 1'b0, NO_BRANCH, ADDR_B);
      tick();
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(sl == 0, INDIRECT_CALL, sl != 0, INDIRECT_CALL);
      tick();
      check($sformatf("TC-60d RP7 slot %0d: the skip, B at idx1 {B,0,0,1}",
                      sl), ptr_is(1, 2, 0) && ent_is(1, ADDR_B, 0, 0, 1));
    end

    // =============================================================
    // TC-61 RP0, RP10, RP11. (a) RP0: a p3 view equal to the registered
    // op repairs nothing, for a push, a pop and a RETURN_CALL. (b)
    // RP10: the repair acts on the speculative stack only (the commit
    // stack is unchanged) and the p2 snapshot taken before it is not
    // rewritten: restoring that snapshot after an undo-push brings the
    // pushed top back (TD#149, as built). (c) RP11: in one cycle the
    // undo-push of B and a p2 push of C: C links to the TOSR the
    // repair left (A, idx1), not to B.
    // =============================================================
    do_reset();
    push_one(ADDR_A);
    drive(1'b1, RETURN_CALL, ADDR_B, 1'b0, NO_BRANCH, '0);
    tick();
    idle();
    check("TC-61a RP0 RETURN_CALL view agrees: no repair", ptr_is(2, 3, 0));
    pop_chk("TC-61a RP0 pop agrees (next cycle drive)", 0, 1'b1, ADDR_B);
    idle();
    check("TC-61a RP0 no repair after the agreeing pop", ptr_is(0, 3, 0));
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    push_one(ADDR_A);
    drv(0, 1'b1, DIRECT_CALL, ADDR_B);
    #1;
    begin
      bp_ras_snapshot_t s61;
      s61 = snap_p2[0];
      tick();
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
      tick();
      check("TC-61b RP10 undo-push: tosr 1, commit stack unchanged",
            ptr_is(1, 3, 0) && (int'(dut.c_cnt) == 1) && (int'(dut.csp) == 1));
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s61;
      tick();
      restore_val = 1'b0; restore_snap = '0;
      check("TC-61b RP10 the p2 snapshot is as taken: B back on top",
            ptr_is(2, 3, 0) && tos_valid_p0[0] && (tos_addr_p0[0] == ADDR_B));
    end
    do_reset();
    push_one(ADDR_A);
    drv(0, 1'b1, DIRECT_CALL, ADDR_B);
    tick();
    drv(0, 1'b1, DIRECT_CALL, ADDR_C);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-61c RP11 C at idx3 links to A (idx1), the repair's TOSR",
          ptr_is(3, 4, 0) && ent_is(3, ADDR_C, 0, 1, 0));

    // =============================================================
    // TC-62 RP11 with a count the repair changed. TC-38b's shape: A
    // (1), X (2); RETURN_CALL with fall-through A pops X (TOSR 1) and
    // its push raises rctr[1] 0 -> 1. In the undo cycle a p2 pop runs
    // from the state the undo leaves: TOSR 2 (X), rctr[1] 0 (RP8). The
    // pop returns X and follows its link to A (PO2), whose count is 0:
    // the snapshot is {1,3,0,0}. A second pop (slot S1 at two slots)
    // then finds A at count 0: it pops A (bottom, PO3) to empty.
    // =============================================================
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_X);
    drive(1'b1, RETURN_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
    tick();
    check("TC-62 pre-repair: tosr 1, rctr[1] 1", ptr_is(1, 3, 0) &&
          (dut.spec_rctr[1] == 'd1));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    #1;
    check("TC-62 RP11 the p2 pop after the undo returns X",
          pop_valid_p2[0] && (pop_addr_p2[0] == ADDR_X));
    check("TC-62 RP11 RP8 snapshot {1,3,0,0}: A's count is back to 0",
          p4(snap_p2[0]) == p4v(1, 3, 0, 0));
    tick();
    check("TC-62 RP11 after the edge: tosr 1, rctr[1] 0",
          ptr_is(1, 3, 0) && (dut.spec_rctr[1] == 'd0));
    if (NUM_PRED_SLOTS > 1) begin
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_X);
      drive(1'b1, RETURN_CALL, ADDR_A, 1'b0, NO_BRANCH, '0);
      tick();
      drive(1'b1, RETURN, '0, 1'b1, RETURN, '0);
      force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
      #1;
      check("TC-62 RP11 slot 1 pops A from count 0 (bottom): {0,3,0,0}",
            pop_valid_p2[S1] && (pop_addr_p2[S1] == ADDR_A) &&
            (p4(snap_p2[S1]) == p4v(0, 3, 0, 0)));
      tick();
      check("TC-62 RP11 the stack is empty, rctr[1] 0",
            ptr_is(0, 3, 0) && (dut.spec_rctr[1] == 'd0));
    end

    // =============================================================
    // TC-63 CO1, CO5, CO6, CO7, CO8, CO11, and a commit in the same
    // cycle as each operation.
    // (a) CO1: before the edge the commit has not taken effect.
    // (b) CO5: a RETURN with a non-empty snapshot {3,_,1} moves BOS to
    // 3; a RETURN_CALL with an empty snapshot {2,_,2} moves BOS to 2.
    // (c) CO7: a commit writes no speculative entry and not TOSW.
    // (d) CO8: commit_val with every other type changes nothing.
    // (e) CO11: a restore and a commit in one cycle: the restore's
    // pointers, CO6 not applied, the commit stack updated.
    // (f) a commit with snapshot tosr 2 in the same cycle as: a push, a
    // pop, a RETURN_CALL, a recursion push, an undo-push, ras_p2_keep
    // low. CO6 compares the TOSR the scan leaves with BOS before the
    // commit: only when they are equal does TOSR move.
    // =============================================================
    do_reset();
    push_one(ADDR_A);
    drv(0, 1'b0, NO_BRANCH, '0);
    commit_val = 1'b1; commit_br_type = DIRECT_CALL; commit_ret_addr = ADDR_A;
    commit_snap = snp(1, 2, 0, 0);
    #1;
    check("TC-63a CO1 before the edge: csp 0, bos 0",
          (dut.csp == '0) && (dut.bos == '0));
    tick();
    commit_val = 1'b0; commit_br_type = NO_BRANCH; commit_snap = '0;
    check("TC-63a CO1 after the edge: csp 1, bos 1, A committed",
          (int'(dut.csp) == 1) && (dut.bos == 'd1) &&
          (dut.commit_ret_addr[0] == ADDR_A));
    check("TC-63c CO7 entry 1 and tosw untouched by the commit",
          ent_is(1, ADDR_A, 0, 0, 1) && (dut.tosw == 'd2));
    do_reset();
    push_one(ADDR_A);
    push_one(ADDR_B);
    push_one(ADDR_C);                         // tosr 3
    drv(0, 1'b0, NO_BRANCH, '0);
    commit_val = 1'b1; commit_br_type = RETURN; commit_snap = snp(3, 4,
                                                                1, 0);
    tick();
    check("TC-63b CO5 a RETURN with a non-empty snapshot moves BOS to 3",
          dut.bos == 'd3);
    commit_br_type = RETURN_CALL; commit_ret_addr = ADDR_X;
    commit_snap = snp(2, 4, 2, 0);
    tick();
    commit_val = 1'b0; commit_br_type = NO_BRANCH; commit_snap = '0;
    check("TC-63b CO5 a RETURN_CALL with an empty snapshot moves BOS to 2",
          dut.bos == 'd2);
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    push_one(ADDR_A);
    for (int ti = 0; ti < 8; ti++) begin
      bp_br_type_e tt;
      tt = bp_br_type_e'(ti);
      if ((tt == DIRECT_CALL) || (tt == INDIRECT_CALL) || (tt == RETURN) ||
          (tt == RETURN_CALL)) continue;
      drv(0, 1'b0, NO_BRANCH, '0);
      commit_val = 1'b1; commit_br_type = tt; commit_ret_addr = ADDR_X;
      commit_snap = snp(5, 6, 4, 0);
      tick();
      commit_val = 1'b0; commit_br_type = NO_BRANCH; commit_snap = '0;
      check($sformatf("TC-63d CO8 commit_val with %s changes nothing",
                      tt.name()),
            ptr_is(1, 2, 0) && (int'(dut.csp) == 1) && (int'(dut.c_cnt) == 1));
    end
    do_reset();
    push_one(ADDR_A);                         // tosr 1, bos 0
    pop_chk("TC-63e pop A, empty at 0", 0, 1'b1, ADDR_A);
    drv(0, 1'b0, NO_BRANCH, '0);
    restore_val = 1'b1; restore_snap = snp(1, 2, 0, 0);
    commit_val = 1'b1; commit_br_type = DIRECT_CALL; commit_ret_addr = ADDR_A;
    commit_snap = snp(1, 2, 0, 0);
    tick();
    restore_val = 1'b0; restore_snap = '0;
    commit_val = 1'b0; commit_br_type = NO_BRANCH; commit_snap = '0;
    check("TC-63e CO11 restore wins: tosr 1 tosw 2 bos 0, commit stack 1",
          ptr_is(1, 2, 0) && (int'(dut.c_cnt) == 1) &&
          (dut.commit_ret_addr[0] == ADDR_A));
    // (f) commits beside each operation. Seed: A(1) B(2), tosr 2, bos 0.
    for (int op = 0; op < 6; op++) begin
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_B);
      if (op == 4) begin
        drv(0, 1'b1, DIRECT_CALL, ADDR_C);    // C at 3, undone next
        tick();
      end
      case (op)
        0: drv(0, 1'b1, DIRECT_CALL, ADDR_C);
        1: drv(0, 1'b1, RETURN, '0);
        2: drv(0, 1'b1, RETURN_CALL, ADDR_C);
        3: drv(0, 1'b1, DIRECT_CALL, ADDR_B);
        4: begin
             drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
             force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
           end
        default: begin
             drv(0, 1'b1, DIRECT_CALL, ADDR_C);
             p2_keep = 1'b0;
           end
      endcase
      commit_val = 1'b1; commit_br_type = DIRECT_CALL;
      commit_ret_addr = ADDR_A; commit_snap = snp(1, 2, 0, 0);
      tick();
      p2_keep = 1'b1;
      commit_val = 1'b0; commit_br_type = NO_BRANCH; commit_snap = '0;
      // BOS 0 -> 1 in every case; the scan's TOSR is not BOS 0 in any
      // case (push C 3, pop B 1, RC 3, recursion 2, undo 2, keep 2), so
      // TOSR stays the scan's (CO6 does not apply).
      case (op)
        0: check("TC-63f push C beside a commit: tosr 3, bos 1",
                 ptr_is(3, 4, 1) && (int'(dut.c_cnt) == 1));
        1: check("TC-63f pop B beside a commit: tosr 1 == bos 1, empty",
                 ptr_is(1, 3, 1));
        2: check("TC-63f RETURN_CALL beside a commit: tosr 3, bos 1",
                 ptr_is(3, 4, 1) && ent_is(3, ADDR_C, 0, 1, 0));
        3: check("TC-63f recursion push beside a commit: rctr[2] 1, bos 1",
                 ptr_is(2, 3, 1) && (dut.spec_rctr[2] == 'd1));
        4: check("TC-63f undo-push beside a commit: tosr 2, bos 1",
                 ptr_is(2, 4, 1));
        default: check("TC-63f keep low beside a commit: tosr 2, bos 1",
                       ptr_is(2, 3, 1));
      endcase
    end
    // CO6 beside a pop that leaves the stack empty at the old BOS: A
    // pushed at 1 (bos 0); the pop of A goes to BOS 0 in the commit's
    // cycle; the commit moves BOS to 1 and TOSR with it.
    do_reset();
    push_one(ADDR_A);
    drv(0, 1'b1, RETURN, '0);
    commit_val = 1'b1; commit_br_type = DIRECT_CALL; commit_ret_addr = ADDR_A;
    commit_snap = snp(1, 2, 0, 0);
    tick();
    commit_val = 1'b0; commit_br_type = NO_BRANCH; commit_snap = '0;
    check("TC-63f CO6 the scan's TOSR 0 == BOS 0: TOSR moves to 1",
          ptr_is(1, 2, 1));

    // =============================================================
    // TC-64 PM1, PM2: the depths and widths are the parameters'.
    // =============================================================
    check("TC-64 PM1 speculative depth RAS_SPEC_ENTRIES",
          $size(dut.spec_ret_addr) == RAS_SPEC_ENTRIES);
    check("TC-64 PM1 commit depth RAS_COMMIT_ENTRIES",
          $size(dut.commit_ret_addr) == RAS_COMMIT_ENTRIES);
    check("TC-64 PM1 count width RAS_RCTR_WIDTH, saturation 2^w - 1",
          ($bits(dut.spec_rctr[0]) == RAS_RCTR_WIDTH) &&
          (int'(M_RCTR_MAX) == (1 << RAS_RCTR_WIDTH) - 1));
    check("TC-64 PM1 commit count to RAS_COMMIT_ENTRIES",
          $bits(dut.c_cnt) == RAS_COMMIT_PTR_BITS + 1);
    // BP-152: PM2 adds the depth (A1) and the tag (B1); 16 before.
    // BP-153: and the operation record, push, pmode, ptosr and ptag; 28
    // before. BP-154: every width is derived here from RAS_SPEC_ENTRIES
    // and FTQ_DEPTH, not restated as a literal (BP-153 checked 41 and 3,
    // its 32 entries): the pointer $clog2(RAS_SPEC_ENTRIES), the tag the
    // B1 bound $clog2(FTQ_DEPTH / (RAS_SPEC_ENTRIES - 1) + 1) + 1, the
    // depth $clog2(FTQ_DEPTH) + 2. At 16 entries 4, 4, 8: 39 bits; at 32
    // 5, 3, 8: 41.
    begin
      int e_ptr, e_tag, e_dep, e_snap;
      e_ptr  = $clog2(RAS_SPEC_ENTRIES);
      e_tag  = $clog2(FTQ_DEPTH / (RAS_SPEC_ENTRIES - 1) + 1) + 1;
      e_dep  = $clog2(FTQ_DEPTH) + 2;
      e_snap = 4 * e_ptr + RAS_RCTR_WIDTH + e_dep + 2 * e_tag +
               RAS_PMODE_BITS + 1;
      $display("TC-64 RAS_SPEC_ENTRIES %0d: pointer %0d, tag %0d, depth %0d,",
               RAS_SPEC_ENTRIES, RAS_PTR_BITS, RAS_TAG_BITS, RAS_DEPTH_BITS);
      $display("TC-64   snapshot $bits %0d (derived %0d)",
               $bits(bp_ras_snapshot_t), e_snap);
      check({"TC-64 PM2 snapshot 4 * ptr + RAS_RCTR_WIDTH + depth + ",
             "2 * tag + RAS_PMODE_BITS + 1, from RAS_SPEC_ENTRIES"},
            $bits(bp_ras_snapshot_t) == e_snap);
      check("TC-64 PM2 pointer $clog2(RAS_SPEC_ENTRIES)",
            (RAS_PTR_BITS == e_ptr) && ($bits(dut.tosr) == e_ptr) &&
            ($bits(dut.spec_nos[0]) == e_ptr));
      check({"TC-64 PM2 depth $clog2(FTQ_DEPTH) + 2, tag ",
             "$clog2(FTQ_DEPTH / (RAS_SPEC_ENTRIES - 1) + 1) + 1"},
            (RAS_DEPTH_BITS == e_dep) && (RAS_TAG_BITS == e_tag) &&
            ($bits(dut.spec_gen[0]) == e_tag));
    end

    // =============================================================
    // TC-65 IV1, IV2, PO7: TOSR below BOS names a chain entry (BP-142
    // Problem 4, the tb_fe_top RS2 failure at seeds 7777 and 1234 of
    // program rec_undo, which BP-143 removed; ruled session-084,
    // ras_decisions.md 3.2 TOSR BELOW BOS IS NOT A FAULT; BP-143 runs it
    // by default with the rule's values).
    //   A pushed (idx1, PU2: TOSW 0 == BOS 0, skip to 1, bottom), B
    //   pushed (idx2, PU1: nos 1), B again (PU5: rctr[2] 1). Block E
    //   (no RAS operation) takes snapshot S = {2,3,0,1} (SL2). The
    //   three calls commit: BOS 0 -> 1 -> 2 -> 2 (CO5); TOSR 2 is not
    //   BOS at the first two, and at the third TOSR 2 == BOS 2 already,
    //   so no drag (CO6): empty. E is redirected: the restore loads S
    //   (RE1): TOSR 2, TOSW 3, BOS 0, and rctr[2] 1 (RE6). TOSR names B,
    //   the allocation it named when S was taken. The correct path
    //   returns twice: R1 returns B and decrements rctr[2] (PO1), R2
    //   returns B and follows its link to A (PO2, TOSR 1, the
    //   allocation B's link names). R1 commits with its snapshot
    //   {2,3,0}: BOS 0 -> 2 (CO5); the scan's TOSR 1 is not BOS 0, so
    //   TOSR stays 1 (CO6). Now TOSR 1 is below BOS 2 and names A, a
    //   chain entry: the push of A wrote it, B's link reaches it, and no
    //   allocation has reused idx1 since (TOSW 3 has not come round).
    //   By PO7 the next pop returns A, valid (not the commit top B),
    //   and by PO3 (A is a bottom entry) TOSR then goes to BOS 2: empty.
    // Until BP-143 this case ran only with +OPEN_IV1 and expected the
    // commit top B, the old meaning of held (allocated after BOS).
    // =============================================================
    begin
      bp_ras_snapshot_t s65;
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_B);
      push_one(ADDR_B);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      s65 = snap_p2[NUM_PRED_SLOTS-1];        // block E
      tick();
      check("TC-65 S = {2,3,0,1}", p4(s65) == p4v(2, 3, 0, 1));
      commit_op(DIRECT_CALL, ADDR_A, 'd1);
      commit_op(DIRECT_CALL, ADDR_B, 'd2);
      commit_op(DIRECT_CALL, ADDR_B, 'd2);
      check("TC-65 IV1 three commits: tosr 2 == bos 2, empty",
            ptr_is(2, 3, 2));
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s65;
      tick();
      restore_val = 1'b0; restore_snap = '0;
      check("TC-65 RE1 the restore: tosr 2, tosw 3, bos 0", ptr_is(2, 3, 0));
      pop_chk("TC-65 R1 pops B (count 1 -> 0)", 0, 1'b1, ADDR_B);
      pop_chk("TC-65 R2 pops B to A", 0, 1'b1, ADDR_B);
      drv(0, 1'b0, NO_BRANCH, '0);
      commit_val = 1'b1; commit_br_type = RETURN;
      commit_snap = snp(2, 3, 0, 0);
      tick();
      commit_val = 1'b0; commit_br_type = NO_BRANCH; commit_snap = '0;
      check("TC-65 CO5 CO6 R1's commit: tosr 1 below bos 2", ptr_is(1, 3, 2));
      check("TC-65 IV1 tosr 1 names a chain entry, A's allocation, not reused",
            m_chain(m_s) && !m_reused(m_s) && (m_s.tref == m_s.seq[1]));
      drv(0, 1'b1, RETURN, '0);
      #1;
      check("TC-65 PO7 the pop returns the chain entry A, valid",
            pop_valid_p2[0] && (pop_addr_p2[0] == ADDR_A));
      tick();
      check("TC-65 PO3 A is a bottom entry: tosr to bos 2, empty",
            ptr_is(2, 3, 2));
    end

    // =============================================================
    // TC-66 IV1, PO7, CO6 (BP-143 Problem 3a, fd07 of BP-138): a commit
    // that moves BOS while TOSR == BOS moves TOSR with it, so TOSR never
    // names the old BOS slot, which no push on the chain wrote.
    //   X pushed: TOSW 0 == BOS 0, so the skip allocates idx1 with nos
    //   0, bottom (PU2). X's return pops it: bottom, TOSR = BOS 0, empty
    //   (PO3). X's call commits with its snapshot TOSR 1: BOS 0 -> 1
    //   (CO5), and the scan's TOSR 0 == BOS 0, so TOSR -> 1 (CO6).
    //   TOSR 1 == BOS 1: empty, and the next pop is the commit top X,
    //   valid (PO5). Without CO6 TOSR stays 0 != BOS 1, on idx0, the
    //   never-written sentinel: the model fails IV1 (no chain entry) and
    //   the pop returns 0x0 from the speculative stack, which RS2
    //   reports.
    // =============================================================
    do_reset();
    push_one(ADDR_X);
    pop_chk("TC-66 X's return pops X to empty", 0, 1'b1, ADDR_X);
    commit_op(DIRECT_CALL, ADDR_X, 'd1);
    check("TC-66 CO5 CO6 X's call commit: tosr 1 == bos 1, empty",
          ptr_is(1, 2, 1) && !m_chain(m_s));
    // BP-152 A1: X's only frame was popped before its call committed, so
    // the commit stack holds no frame for the next return (n 1, count 1):
    // not valid. Until BP-152 this expected the popped frame, X, valid.
    // The point of the case stands: no pop of the old BOS slot, 0x0.
    pop_chk("TC-66 A1 PO5 PO7 the next pop has no committed frame: not valid",
            0, 1'b0, '0);
    check("TC-66 PO5 the fallback moves nothing", ptr_is(1, 2, 1));

    // =============================================================
    // TC-67 PO7, PU2, PU4 (BP-143 Problem 4): a chain entry below BOS
    // reused before the sentinel skip, and the pop that reaches it.
    //   TC-65's state: TOSR 1 (A, a chain entry below BOS), TOSW 3, BOS
    //   2. Pushes P1..P15 (fill_addr[1..15]) follow. P1 allocates idx3
    //   (TOSW 3 != BOS 2, no skip; the stack is not empty, so bot 0, and
    //   its link names A at idx1, PU1). P2..P13 allocate idx4..idx15 and
    //   P14 idx0, each linked to the one before. TOSW is then 1 and TOSW
    //   + 1 == BOS 2: full (PU4, 14 allocations since BOS moved). P15
    //   finds TOSW 1 != BOS 2, so no skip (PU2 guards only BOS): it
    //   allocates idx1, A's index, and reuses A, linked to P14 (idx0);
    //   TOSW 2 == BOS. So the reusing push is P15, the 15th.
    //   The pops: P15 (idx1, the entry P15 wrote, not a wrap), then
    //   P14..P1 (idx0, idx15..idx3), each by its link (PO2).
    //   UNTIL BP-152: P1's pop followed its link to idx1, which names A's
    //   allocation; idx1 then held P15, and by PO7 the next pop returned
    //   the reusing push's address, P15, valid: the wrap, counted by the
    //   model and by RS2. That is stale_below_bos (BP-151), and this case
    //   checked it as allowed.
    //   SINCE BP-152 (B1): P15's allocation of idx1 kills P1's link, so P1
    //   is bottom and its pop leaves TOSR at BOS, empty. The pop reaching
    //   A falls back (A1): n = 1, the dep of the committed return (R1,
    //   2) less the speculative depth (1), so CSP-2, A. The RETURN commit
    //   carries R1's own snapshot (it read snp(2, 3, 0, 0), the same four
    //   fields with the depth of the cycle the commit was driven in).
    //   Run on the BP-151 RTL this case gives P15 at that pop: it fails.
    // =============================================================
    begin
      bp_ras_snapshot_t s67;
      bp_ras_snapshot_t s67r;
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_B);
      push_one(ADDR_B);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      s67 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      commit_op(DIRECT_CALL, ADDR_A, 'd1);
      commit_op(DIRECT_CALL, ADDR_B, 'd2);
      commit_op(DIRECT_CALL, ADDR_B, 'd2);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s67;
      tick();
      restore_val = 1'b0; restore_snap = '0;
      drv(0, 1'b1, RETURN, '0);
      #1;
      s67r = snap_p2[NUM_PRED_SLOTS-1];
      check("TC-67 R1 pops B (count 1 -> 0)",
            pop_valid_p2[0] && (pop_addr_p2[0] == ADDR_B));
      check("TC-67 R1's snapshot {2,3,0,0}, dep 2 (A1)",
            (p4(s67r) == p4v(2, 3, 0, 0)) && (s67r.dep == 8'd2));
      tick();
      pop_chk("TC-67 R2 pops B to A", 0, 1'b1, ADDR_B);
      drv(0, 1'b0, NO_BRANCH, '0);
      commit_val = 1'b1; commit_br_type = RETURN;
      commit_snap = s67r;
      tick();
      commit_val = 1'b0; commit_br_type = NO_BRANCH; commit_snap = '0;
      check("TC-67 TC-65's state: tosr 1 below bos 2, tosw 3, A at idx1",
            ptr_is(1, 3, 2) && m_chain(m_s) &&
            (dut.spec_ret_addr[1] == ADDR_A));
      // BP-153: RAS_SPEC_ENTRIES - 2 allocations (14 at 16 entries, the
      // names keep those numbers), then one more onto idx1.
      for (int k = 1; k <= RAS_SPEC_ENTRIES - 2; k++) push_one(fill_addr[k]);
      check("TC-67 PU4 14 allocations: tosw 1, tosw + 1 == bos 2, full",
            ptr_is(0, 1, 2) &&
            (dut.spec_ret_addr[0] == fill_addr[RAS_SPEC_ENTRIES - 2]) &&
            (dut.spec_nos[3] == 'd1) && !dut.spec_bot[3]);
      push_one(fill_addr[RAS_SPEC_ENTRIES - 1]);
      check("TC-67 PU2 P15 allocates idx1 (A's), no skip: tosw 2 == bos",
            ptr_is(1, 2, 2) &&
            ent_is(1, fill_addr[RAS_SPEC_ENTRIES - 1], 0, 0, 0));
      check("TC-67 B1 P15's allocation of idx1 kills P1's link: P1 bottom",
            (dut.spec_nos[3] == 'd1) && dut.spec_bot[3] &&
            (dut.spec_gen[1] == 'd2));
      pop_chk("TC-67 the pop of P15 at idx1 returns P15", 0, 1'b1,
              fill_addr[RAS_SPEC_ENTRIES - 1]);
      for (int k = RAS_SPEC_ENTRIES - 2; k >= 1; k--)
        pop_chk($sformatf("TC-67 the pop of P%0d returns P%0d", k, k), 0,
                1'b1, fill_addr[k]);
      check("TC-67 B1 P1's pop leaves TOSR at BOS 2: empty, no reuse",
            ptr_is(2, 2, 2) && !m_chain(m_s));
      pop_chk({"TC-67 A1 B1 the pop reaching A falls back: CSP-1-n, n 1, ",
               "A (BP-151 RTL: P15)"}, 0, 1'b1, ADDR_A);
      check("TC-67 B1 no pop read a reused entry (model, RS6 counter)",
            (m_nreuse == 0) && (dut.u_assert.r_nreuse == 0));
    end

    // =============================================================
    // TC-68 IV1 (both directions), PO5, PO7, CO5, IV2 (BP-144 Problem
    // 3): the boundary the converse of IV1 allows. TOSR == BOS on the
    // entry BOS names is the empty stack, not a stack read empty over a
    // live entry.
    //   X pushed (idx1, PU2 skip, bottom), Y pushed (idx2, nos 1, PU1).
    //   X's call commits with snapshot TOSR 1: BOS 0 -> 1 (CO5); the
    //   scan's TOSR 2 is not BOS 0, so TOSR stays 2 (CO6). BOS now names
    //   X's allocation. Y's return pops Y (PO2): TOSR = nos = 1 == BOS:
    //   empty (IV1), and the allocation TOSR names is the one BOS names,
    //   so the converse does not fail. The next pop is the commit top
    //   X, valid (PO5), and moves nothing.
    //   (b) two slots: the same, with both returns in one cycle: slot 0
    //   pops Y, slot 1 finds TOSR == BOS and takes the fallback X,
    //   valid (IV2: a fallback pop is valid while the commit stack holds
    //   an entry; SL1).
    // =============================================================
    for (int v = 0; v < 2; v++) begin
      int unsigned c0;
      if ((v == 1) && (NUM_PRED_SLOTS < 2)) begin
        $display("SKIP TC-68b two returns in one cycle: needs two slots");
        continue;
      end
      do_reset();
      push_one(ADDR_X);
      push_one(ADDR_Y68);
      commit_op(DIRECT_CALL, ADDR_X, 'd1);
      check("TC-68 CO5 CO6 X's call commit: tosr 2, tosw 3, bos 1",
            ptr_is(2, 3, 1) && m_chain(m_s));
      c0 = m_nconv;
      if (v == 0) begin
        pop_chk("TC-68a PO2 Y's return pops Y", 0, 1'b1, ADDR_Y68);
        check("TC-68a IV1 tosr 1 == bos 1, empty, BOS names the entry",
              ptr_is(1, 3, 1) && !m_chain(m_s) && (m_nconv == c0));
        pop_chk("TC-68a PO5 PO7 the next pop is the commit top X", 0, 1'b1,
                ADDR_X);
        check("TC-68a PO5 the fallback moves nothing", ptr_is(1, 3, 1));
      end else begin
        drive(1'b1, RETURN, '0, 1'b1, RETURN, '0);
        #1;
        check("TC-68b SL1 slot 0 pops Y",
              pop_valid_p2[0] && (pop_addr_p2[0] == ADDR_Y68));
        check("TC-68b IV2 PO5 slot 1 at tosr == bos: the commit top X, valid",
              pop_valid_p2[S1] && (pop_addr_p2[S1] == ADDR_X));
        tick();
        check("TC-68b IV1 tosr 1 == bos 1, no converse failure",
              ptr_is(1, 3, 1) && (m_nconv == c0));
      end
    end

    // =============================================================
    // TC-69 RP2, RP3, RP4, RP5, RP8, RP9 at each slot, RP2 at both ends
    // of the count, and IV2 in a repair cycle (BP-144 Problem 3). Each
    // makes the p2 operation at slot sl, then gives p3 a view that
    // differs at sl (force_p3; every other slot made no operation and is
    // given none, which agrees).
    //   a RP2 at count 0: A (idx1, count 0); a p2 push of A raises it to
    //     1 (PU5); the undo-push lowers it to 0, TOSR 1 (RP2).
    //   b RP2 at the top count: A pushed 15 times (count 14); the p2
    //     push raises it to 15 (PU5, below saturation); the undo lowers
    //     it to 14.
    //   c RP3: count 15; the p2 push meets saturation and changes
    //     nothing (PU6); its undo changes nothing: 15.
    //   d RP4: A twice (count 1); the p2 pop decrements it (PO1, TOSR
    //     held); the undo-pop puts the count back to 1 and TOSR to 1.
    //     Two pops then return A, A (PO1, PO3).
    //   e RP5: R committed; X (idx1) pushed and popped (empty at 0). A p2
    //     pop on the empty stack (fallback R) in the cycle X's call
    //     commits (BOS 0 -> 1, the scan's TOSR 0 == BOS 0, so TOSR -> 1,
    //     CO6). Its undo sets TOSR to BOS as it is at the undo, 1, not
    //     the registered 0 (RP5): empty, and the next pop is the commit
    //     top X (PO5).
    //   f RP8: A (1), X (2); a p2 RETURN_CALL with fall-through B pops X
    //     (TOSR 1) and pushes B at idx3 (nos 1). Its undo returns TOSR to
    //     2 (X), no count changed; B stays written (RP1: nothing is
    //     cleared), TOSW 4. The pops then return X, then A.
    //   g RP9: A (1); a p2 cycle with no RAS operation and fall-through
    //     B; p3 says RETURN_CALL: a missed pop of A (bottom: TOSR 0, PO3)
    //     then a missed push of B on the empty stack at TOSW 2 (no skip,
    //     TOSW != BOS): idx2 {B,0,0,1} (RP7, PU1), TOSR 2, TOSW 3.
    //   i RP6, IV2, PO7: TC-66's state (X pushed, popped, its call
    //     committed: TOSR 1 == BOS 1, empty, CO6). A missed pop at slot
    //     sl finds the stack empty: PO1 to PO3 do not apply, nothing
    //     moves. Without CO6 TOSR stays on idx0, which no push on the
    //     chain wrote, and the missed pop would pop it (RS2
    //     a_rep_pop_held).
    //   h IV2, RP11 in a repair cycle, two slots: R committed; A (idx1);
    //     a p2 push of B at slot 0 (idx2). Next cycle p3 undoes B (TOSR 1)
    //     while slot 0 pops A (bottom: empty) and slot 1 pops at TOSR ==
    //     BOS: the commit top R, valid.
    // =============================================================
    for (int sl = 0; sl < NUM_PRED_SLOTS; sl = sl + S1 + (S1 == 0 ? 1 : 0))
    begin
      // a, b, c
      for (int c = 0; c < 3; c++) begin
        int base;
        base = (c == 0) ? 0 : ((c == 1) ? int'(M_RCTR_MAX) - 1
                                        : int'(M_RCTR_MAX));
        do_reset();
        for (int i = 0; i <= base; i++) push_one(ADDR_A);
        drv(sl, 1'b1, DIRECT_CALL, ADDR_A);
        tick();
        check($sformatf("TC-69%s slot %0d PU5 PU6 the p2 push: count %0d",
                        (c == 0) ? "a" : ((c == 1) ? "b" : "c"), sl,
                        (c == 2) ? base : base + 1),
              ent_is(1, ADDR_A, RAS_RCTR_WIDTH'((c == 2) ? base : base + 1),
                     0, 1) && ptr_is(1, 2, 0));
        drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
        force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
        tick();
        check($sformatf("TC-69%s slot %0d %s the undo-push: count %0d",
                        (c == 0) ? "a" : ((c == 1) ? "b" : "c"), sl,
                        (c == 2) ? "RP3" : "RP2", base),
              ent_is(1, ADDR_A, RAS_RCTR_WIDTH'(base), 0, 1) &&
              ptr_is(1, 2, 0));
      end
      // d
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_A);
      drv(sl, 1'b1, RETURN, '0);
      tick();
      check($sformatf("TC-69d slot %0d PO1 the p2 pop: count 0, tosr 1", sl),
            ent_is(1, ADDR_A, 0, 0, 1) && ptr_is(1, 2, 0));
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
      tick();
      check($sformatf("TC-69d slot %0d RP4 the undo-pop: count 1, tosr 1", sl),
            ent_is(1, ADDR_A, 1, 0, 1) && ptr_is(1, 2, 0));
      pop_chk("TC-69d PO1 the first pop returns A", sl, 1'b1, ADDR_A);
      pop_chk("TC-69d PO3 the second pop returns A", sl, 1'b1, ADDR_A);
      check("TC-69d then empty", ptr_is(0, 2, 0));
      // e
      do_reset();
      commit_op(DIRECT_CALL, ADDR_R, 'd0);
      push_one(ADDR_X);
      pop_chk("TC-69e pop X, empty at 0", 0, 1'b1, ADDR_X);
      drv(sl, 1'b1, RETURN, '0);
      commit_val = 1'b1; commit_br_type = DIRECT_CALL; commit_ret_addr = ADDR_X;
      commit_snap = snp(1, 2, 0, 0);
      #1;
      check($sformatf("TC-69e slot %0d PO5 the p2 pop on empty: fallback R",
                      sl), pop_valid_p2[sl] && (pop_addr_p2[sl] == ADDR_R));
      tick();
      commit_val = 1'b0; commit_br_type = NO_BRANCH; commit_snap = '0;
      check($sformatf("TC-69e slot %0d CO5 CO6 bos 1, tosr dragged to 1", sl),
            ptr_is(1, 2, 1));
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
      tick();
      check($sformatf("TC-69e slot %0d RP5 the undo-pop: tosr = bos 1", sl),
            ptr_is(1, 2, 1));
      pop_chk("TC-69e PO5 the next pop is the commit top X", sl, 1'b1, ADDR_X);
      // f
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_X);
      drv(sl, 1'b1, RETURN_CALL, ADDR_B);
      #1;
      check($sformatf("TC-69f slot %0d RC1 the RETURN_CALL pops X", sl),
            pop_valid_p2[sl] && (pop_addr_p2[sl] == ADDR_X));
      tick();
      check($sformatf("TC-69f slot %0d RC2 B at idx3, nos 1", sl),
            ptr_is(3, 4, 0) && ent_is(3, ADDR_B, 0, 1, 0));
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
      tick();
      check($sformatf("TC-69f slot %0d RP8 the undo: tosr 2 (X), tosw 4, %s",
                      sl, "B kept"),
            ptr_is(2, 4, 0) && ent_is(3, ADDR_B, 0, 1, 0) &&
            ent_is(2, ADDR_X, 0, 1, 0));
      pop_chk("TC-69f PO2 the pop returns X", sl, 1'b1, ADDR_X);
      pop_chk("TC-69f PO3 the pop returns A", sl, 1'b1, ADDR_A);
      // g
      do_reset();
      push_one(ADDR_A);
      drv(sl, 1'b0, NO_BRANCH, ADDR_B);
      tick();
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(sl == 0, RETURN_CALL, sl != 0, RETURN_CALL);
      tick();
      check($sformatf("TC-69g slot %0d RP9 missed pop of A, missed push of B",
                      sl), ptr_is(2, 3, 0) && ent_is(2, ADDR_B, 0, 0, 1) &&
            ent_is(1, ADDR_A, 0, 0, 1));
      // i
      do_reset();
      push_one(ADDR_X);
      pop_chk("TC-69i X's return pops X to empty", 0, 1'b1, ADDR_X);
      commit_op(DIRECT_CALL, ADDR_X, 'd1);
      check("TC-69i CO5 CO6 X's call commit: tosr 1 == bos 1, empty",
            ptr_is(1, 2, 1));
      drv(sl, 1'b0, NO_BRANCH, '0);
      tick();
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(sl == 0, RETURN, sl != 0, RETURN);
      tick();
      check($sformatf("TC-69i slot %0d RP6 IV2 a missed pop on the empty %s",
                      sl, "stack moves nothing"), ptr_is(1, 2, 1));
    end
    // h
    do_reset();
    commit_op(DIRECT_CALL, ADDR_R, 'd0);
    push_one(ADDR_A);
    drv(0, 1'b1, DIRECT_CALL, ADDR_B);
    tick();
    drive(1'b1, RETURN, '0, 1'b1, RETURN, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    #1;
    check("TC-69h RP1 RP11 slot 0 pops A after the undo of B",
          pop_valid_p2[0] && (pop_addr_p2[0] == ADDR_A));
    if (NUM_PRED_SLOTS > 1)
      check("TC-69h IV2 slot 1 in the repair cycle: the commit top R, valid",
            pop_valid_p2[S1] && (pop_addr_p2[S1] == ADDR_R));
    tick();
    check("TC-69h the stack is empty, B kept at idx2",
          ptr_is(0, 3, 0) && ent_is(2, ADDR_B, 0, 1, 0));

    // =============================================================
    // TC-70 SL2, P02 (BP-144 Problem 3): the snapshot's count on an
    // empty stack whose BOS entry has a count. A pushed three times
    // (idx1, count 2). A's call commits with snapshot TOSR 1: BOS 0 -> 1
    // (CO5); the scan's TOSR 1 is not BOS 0, so no drag; TOSR 1 == BOS
    // 1: empty. The snapshot is {1, 2, 1, 0}: rctr 0 because TOSR ==
    // BOS (SL2, 4.1), though rctr[1] is 2. The p0 read is the commit
    // top A (P02), and a pop takes the fallback A (PO5).
    // =============================================================
    do_reset();
    for (int i = 0; i < 3; i++) push_one(ADDR_A);
    commit_op(DIRECT_CALL, ADDR_A, 'd1);
    drv(0, 1'b0, NO_BRANCH, '0);
    #1;
    check("TC-70 SL2 empty with rctr[BOS] 2: snapshot {1,2,1,0}",
          (p4(snap_p2[0]) == p4v(1, 2, 1, 0)) &&
          (p4(snap_p2[S1]) == p4v(1, 2, 1, 0)) &&
          (dut.spec_rctr[1] == 'd2));
    check("TC-70 P02 the p0 read is the commit top A",
          tos_valid_p0[0] && (tos_addr_p0[0] == ADDR_A));
    tick();
    pop_chk("TC-70 PO5 the pop is the fallback A", 0, 1'b1, ADDR_A);

    // =============================================================
    // TC-71 KP1, KP2 at slot S1 (BP-144 Problem 3). (a) KP2: X (idx1);
    // slot S1 pushes C with ras_p2_keep low and no repair: nothing moves,
    // and C is registered as none (the next cycle, p3 none, repairs
    // nothing). (b) KP1: X; slot 0 pushes B (idx2); next cycle p3 undoes
    // B while slot S1 pushes C with keep low: only the repair applies,
    // TOSR 1 (X), C not written (idx3 stays 0).
    // =============================================================
    do_reset();
    push_one(ADDR_X);
    drv(S1, 1'b1, DIRECT_CALL, ADDR_C);
    p2_keep = 1'b0;
    tick();
    p2_keep = 1'b1;
    check("TC-71a KP2 slot S1 push with keep low: nothing moves",
          ptr_is(1, 2, 0) && (dut.spec_ret_addr[2] == '0));
    drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    tick();
    check("TC-71a KP1 registered as none: no repair the next cycle",
          ptr_is(1, 2, 0));
    do_reset();
    push_one(ADDR_X);
    drv(0, 1'b1, DIRECT_CALL, ADDR_B);
    tick();
    drv(S1, 1'b1, DIRECT_CALL, ADDR_C);
    force_p3(1'b0, NO_BRANCH, 1'b0, NO_BRANCH);
    p2_keep = 1'b0;
    tick();
    p2_keep = 1'b1;
    check("TC-71b KP1 the repair applies, slot S1's push is dropped",
          ptr_is(1, 3, 0) && (dut.spec_ret_addr[3] == '0) &&
          ent_is(2, ADDR_B, 0, 1, 0));

    // =============================================================
    // TC-72 (BP-145, FE-19): return addresses above 2^41 are held
    // whole. The RAS holds VA_WIDTH bits in both stacks. (a) Two pushes
    // of addresses with bits 58, 56 and 41 set, popped in order; (b) a
    // committed call's address, the p0 read and the fallback pop of an
    // empty speculative stack (as TC-70). Each expected value is a 64-bit
    // constant, so a stack narrower than 59 bits cannot match it.
    // Skipped below VA_WIDTH 59.
    // =============================================================
    if (VA_WIDTH >= 59) begin
      do_reset();
      push_one(VA_WIDTH'(64'h500_0200_0000_1234));
      push_one(VA_WIDTH'(64'h500_0200_0000_5678));
      drv(0, 1'b1, RETURN, '0);
      #1;
      check("TC-72a the first pop is the second push, whole",
            pop_valid_p2[0] &&
            (64'(pop_addr_p2[0]) == 64'h500_0200_0000_5678));
      tick();
      drv(0, 1'b1, RETURN, '0);
      #1;
      check("TC-72a the second pop is the first push, whole",
            pop_valid_p2[0] &&
            (64'(pop_addr_p2[0]) == 64'h500_0200_0000_1234));
      tick();
      do_reset();
      push_one(VA_WIDTH'(64'h500_0200_0000_9ABC));
      commit_op(DIRECT_CALL, VA_WIDTH'(64'h500_0200_0000_9ABC), 'd1);
      drv(0, 1'b0, NO_BRANCH, '0);
      #1;
      check("TC-72b the p0 read is the commit top, whole",
            tos_valid_p0[0] &&
            (64'(tos_addr_p0[0]) == 64'h500_0200_0000_9ABC));
      tick();
      drv(0, 1'b1, RETURN, '0);
      #1;
      check("TC-72b the fallback pop is the commit top, whole",
            pop_valid_p2[0] &&
            (64'(pop_addr_p2[0]) == 64'h500_0200_0000_9ABC));
      tick();
    end else begin
      $display("SKIP TC-72: VA_WIDTH %0d", VA_WIDTH);
    end

    // =============================================================
    // TC-73 A1 (BP-152, RAS-4, TD#207): the fallback reads the committed
    // frame at the speculative depth, CSP-1-n, n = the committed block's
    // dep less the speculative depth.
    //   (a) fb_stale_top (BP-151): main calls a (A), a calls b (B), both
    //       calls commit; the stack is then empty (the commit of B moves
    //       BOS onto B). b returns: the fallback, n 0, B. a returns: n 1,
    //       A. The BP-151 RTL read the top, B, for both: a's return was
    //       mispredicted to B.
    //   (b) the depth is restored from the snapshot (RE1).
    //   (c) n at the count: the frame is gone, not valid (PO6).
    //   (d) n below 0 (a snapshot deeper than the committed depth): the
    //       top, CSP-1, as before BP-152.
    // =============================================================
    begin
      bp_ras_snapshot_t s73;
      do_reset();
      push_one(ADDR_A);                                    // a's call
      push_one(ADDR_B);                                    // b's call
      commit_op(DIRECT_CALL, ADDR_A, 'd1);
      commit_op(DIRECT_CALL, ADDR_B, 'd2);
      check("TC-73a both calls committed: tosr 2 == bos 2, dcm 2, dsp 2",
            ptr_is(2, 3, 2) && (dut.dcm == 8'd2) && (dut.dsp == 8'd2));
      drv(0, 1'b1, RETURN, '0);
      #1;
      s73 = snap_p2[NUM_PRED_SLOTS-1];
      check("TC-73a b's return: fallback n 0, B",
            pop_valid_p2[0] && (pop_addr_p2[0] == ADDR_B));
      tick();
      pop_chk("TC-73a a's return: fallback n 1, A (BP-151 RTL: B)", 0, 1'b1,
              ADDR_A);
      check("TC-73a two pops: dsp 0, nothing consumed (csp 2)",
            (dut.dsp == 8'd0) && (int'(dut.csp) == 2));
      // (b) back to the snapshot after b's return: the depth is its dep.
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s73;
      tick();
      restore_val = 1'b0; restore_snap = '0;
      check("TC-73b RE1 the restore loads the snapshot's dep 1",
            (s73.dep == 8'd1) && (dut.dsp == 8'd1));
      pop_chk("TC-73b after the restore a's return is A again", 0, 1'b1,
              ADDR_A);
      // (c) n 2 at a count of 2: no frame.
      pop_chk("TC-73c n 2 at count 2: not valid", 0, 1'b0, '0);
      // (d) a hand-built empty snapshot two deeper than the committed
      //     depth: n -2, the top.
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1;
      restore_snap = snp(2, 3, 2, 0);
      restore_snap.dep = 8'd4;
      tick();
      restore_val = 1'b0; restore_snap = '0;
      pop_chk("TC-73d n -2: the top, CSP-1, B", 0, 1'b1, ADDR_B);
    end

    // =============================================================
    // TC-74 B1 (BP-152, RAS-4): a link never names a reused entry.
    //   (a) an allocation onto the TOSR entry itself. From TC-65's state
    //       (TOSR 1, A below BOS 2, TOSW 3), 14 push-pop pairs move TOSW
    //       to 1 while TOSR returns to 1 each time. The 15th push
    //       allocates idx1, TOSR's entry: it is bottom (nos BOS), and its
    //       pop empties the stack. The BP-151 RTL linked it to itself
    //       (nos 1): its pop returned it again, for ever.
    //   (b) a restore of a snapshot whose TOSR entry was reallocated
    //       since (tag 1, generation 2): it reads empty, and the pop
    //       falls back to A. The BP-151 RTL restored TOSR 1 and popped
    //       the reusing push.
    //   (c) every entry whose link named idx1 was made bottom (kill).
    // =============================================================
    begin
      bp_ras_snapshot_t s74;
      bp_ras_snapshot_t s74r;
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_B);
      push_one(ADDR_B);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      s74 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      commit_op(DIRECT_CALL, ADDR_A, 'd1);
      commit_op(DIRECT_CALL, ADDR_B, 'd2);
      commit_op(DIRECT_CALL, ADDR_B, 'd2);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s74;
      tick();
      restore_val = 1'b0; restore_snap = '0;
      drv(0, 1'b1, RETURN, '0);
      #1;
      s74r = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      pop_chk("TC-74 R2 pops B to A", 0, 1'b1, ADDR_B);
      drv(0, 1'b0, NO_BRANCH, '0);
      commit_val = 1'b1; commit_br_type = RETURN; commit_snap = s74r;
      tick();
      commit_val = 1'b0; commit_br_type = NO_BRANCH; commit_snap = '0;
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      s74 = snap_p2[NUM_PRED_SLOTS-1];      // TOSR 1 (A), tag 1
      tick();
      check("TC-74 TC-65's state: tosr 1 below bos 2, tosw 3; snapshot tag 1",
            ptr_is(1, 3, 2) && (s74.tosr == 'd1) && (s74.tag == 'd1));
      // BP-153: RAS_SPEC_ENTRIES - 2 pairs (14 at 16 entries, the names
      // keep those numbers).
      for (int k = 1; k <= RAS_SPEC_ENTRIES - 2; k++) begin
        push_one(fill_addr[k]);
        pop_chk($sformatf("TC-74a pair %0d: P%0d pops back to A's idx1", k, k),
                0, 1'b1, fill_addr[k]);
      end
      check("TC-74a 14 pairs: tosr 1, tosw 1, bos 2",
            ptr_is(1, 1, 2));
      push_one(fill_addr[RAS_SPEC_ENTRIES - 1]);
      check("TC-74a B1 the push onto TOSR's own entry is bottom, nos BOS",
            ptr_is(1, 2, 2) &&
            ent_is(1, fill_addr[RAS_SPEC_ENTRIES - 1], 0, 2, 1));
      check("TC-74c B1 every link that named idx1 is killed (idx3..idx0)",
            dut.spec_bot[3] && dut.spec_bot[9] && dut.spec_bot[0]);
      pop_chk("TC-74a its pop returns it once", 0, 1'b1,
              fill_addr[RAS_SPEC_ENTRIES - 1]);
      check("TC-74a then TOSR is BOS: empty (BP-151 RTL: tosr 1 again)",
            ptr_is(2, 2, 2));
      pop_chk("TC-74a the next pop falls back to A (A1)", 0, 1'b1, ADDR_A);
      // (b) the snapshot of TC-65's state names idx1, generation 1; idx1
      //     now holds P15, generation 2.
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s74;
      tick();
      restore_val = 1'b0; restore_snap = '0;
      check("TC-74b B1 the restore of a reallocated TOSR entry reads empty",
            (dut.spec_gen[1] == 'd2) && ptr_is(2, 3, 2));
      pop_chk("TC-74b the pop falls back to A, not P15", 0, 1'b1, ADDR_A);
    end

    // =============================================================
    // TC-75 C1 (BP-152, ras_decisions.md 7): the predecode operation on
    // the restore of the predecode redirect, by the p2 rules, and the
    // post-op snapshot (ras_pd_snapshot).
    //   (a) a call: C pushed on the restored A, linked to it.
    //   (b) a return: the restored top B popped, to A.
    //   (c) a return-call: the pop, then the push on what it leaves.
    //   (d) a call matching the top: the recursion count.
    //   (e) ras_pd_val without a restore does nothing.
    // =============================================================
    begin
      bp_ras_snapshot_t s75;
      // (a)
      do_reset();
      push_one(ADDR_A);                                    // idx1
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      s75 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      push_one(ADDR_B);                                    // wrong path
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s75;
      pd_val = 1'b1; pd_type = DIRECT_CALL; pd_ret = ADDR_C;
      #1;
      check("TC-75a C1 pd snapshot: C at idx2, tosw 3, dep 2, its tag",
            (pd_snap.tosr == 'd2) && (pd_snap.tosw == 'd3) &&
            (pd_snap.bos == 'd0) && (pd_snap.dep == 8'd2) &&
            (pd_snap.tag == 'd2));
      tick();
      restore_val = 1'b0; restore_snap = '0; pd_val = 1'b0;
      check("TC-75a C1 C pushed on the restored A, linked to idx1",
            ptr_is(2, 3, 0) && ent_is(2, ADDR_C, 0, 1, 0) &&
            (dut.dsp == 8'd2));
      pop_chk("TC-75a pop C", 0, 1'b1, ADDR_C);
      pop_chk("TC-75a pop A", 0, 1'b1, ADDR_A);
      // (b)
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_B);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      s75 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      push_one(ADDR_C);                                    // wrong path
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s75;
      pd_val = 1'b1; pd_type = RETURN; pd_ret = '0;
      #1;
      check("TC-75b C1 pd snapshot after the pop: tosr 1, dep 1",
            (pd_snap.tosr == 'd1) && (pd_snap.dep == 8'd1));
      tick();
      restore_val = 1'b0; restore_snap = '0; pd_val = 1'b0;
      check("TC-75b C1 the restored top B popped: tosr 1",
            ptr_is(1, 3, 0) && (dut.dsp == 8'd1));
      pop_chk("TC-75b the next pop is A", 0, 1'b1, ADDR_A);
      // (c)
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_B);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      s75 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s75;
      pd_val = 1'b1; pd_type = RETURN_CALL; pd_ret = ADDR_C;
      tick();
      restore_val = 1'b0; restore_snap = '0; pd_val = 1'b0;
      check("TC-75c C1 RETURN_CALL: B popped, C pushed on A, dep 2",
            ptr_is(3, 4, 0) && ent_is(3, ADDR_C, 0, 1, 0) &&
            (dut.dsp == 8'd2));
      pop_chk("TC-75c pop C", 0, 1'b1, ADDR_C);
      pop_chk("TC-75c pop A", 0, 1'b1, ADDR_A);
      // (d)
      do_reset();
      push_one(ADDR_A);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      s75 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s75;
      pd_val = 1'b1; pd_type = DIRECT_CALL; pd_ret = ADDR_A;
      #1;
      check("TC-75d C1 pd snapshot carries the count 1",
            (pd_snap.tosr == 'd1) && (pd_snap.rctr == 'd1) &&
            (pd_snap.dep == 8'd2));
      tick();
      restore_val = 1'b0; restore_snap = '0; pd_val = 1'b0;
      check("TC-75d C1 a call matching the top: count 1, nothing allocated",
            ptr_is(1, 2, 0) && ent_is(1, ADDR_A, 1, 0, 1));
      // (e)
      drv(0, 1'b0, NO_BRANCH, '0);
      pd_val = 1'b1; pd_type = DIRECT_CALL; pd_ret = ADDR_C;
      tick();
      pd_val = 1'b0;
      check("TC-75e ras_pd_val without a restore: nothing moves",
            ptr_is(1, 2, 0) && ent_is(1, ADDR_A, 1, 0, 1) &&
            (dut.dsp == 8'd2));
    end

    // =============================================================
    // TC-76 (BP-152): the undo of the restored block's own push
    // (ras_rs_undo). The block's snapshot is post-op (4.2); a redirect
    // that leaves the block before its call restores a stack that holds
    // the call's push. (a) an allocating push: TOSR back to A by C's
    // link, dep 1. (b) with a C1 call after it: C undone, D pushed on A.
    // (c) a recursion increment: the count taken back. Before BP-152 the
    // restore kept C: the next return popped C.
    // =============================================================
    begin
      bp_ras_snapshot_t s76;
      // (a)
      do_reset();
      push_one(ADDR_A);
      drv(0, 1'b1, DIRECT_CALL, ADDR_C);
      #1;
      s76 = snap_p2[NUM_PRED_SLOTS-1];                    // after C
      tick();
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s76; rs_undo = 1'b1;
      #1;
      check("TC-76a undo pd snapshot: tosr 1 (A), dep 1",
            (pd_snap.tosr == 'd1) && (pd_snap.dep == 8'd1));
      tick();
      restore_val = 1'b0; restore_snap = '0; rs_undo = 1'b0;
      check("TC-76a undo: TOSR back to A, TOSW kept, dsp 1",
            ptr_is(1, 3, 0) && (dut.dsp == 8'd1));
      pop_chk("TC-76a the next pop is A, not C", 0, 1'b1, ADDR_A);
      // (b)
      do_reset();
      push_one(ADDR_A);
      drv(0, 1'b1, DIRECT_CALL, ADDR_C);
      #1;
      s76 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s76; rs_undo = 1'b1;
      pd_val = 1'b1; pd_type = DIRECT_CALL; pd_ret = ADDR_X;
      tick();
      restore_val = 1'b0; restore_snap = '0; rs_undo = 1'b0; pd_val = 1'b0;
      check("TC-76b undo then C1: X pushed on A at idx3, dsp 2",
            ptr_is(3, 4, 0) && ent_is(3, ADDR_X, 0, 1, 0) &&
            (dut.dsp == 8'd2));
      pop_chk("TC-76b pop X", 0, 1'b1, ADDR_X);
      pop_chk("TC-76b pop A", 0, 1'b1, ADDR_A);
      // (c)
      do_reset();
      push_one(ADDR_A);
      drv(0, 1'b1, DIRECT_CALL, ADDR_A);                   // count 1
      #1;
      s76 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s76; rs_undo = 1'b1;
      tick();
      restore_val = 1'b0; restore_snap = '0; rs_undo = 1'b0;
      check("TC-76c undo of a recursion increment: count 0, dsp 1",
            ptr_is(1, 2, 0) && ent_is(1, ADDR_A, 0, 0, 1) &&
            (dut.dsp == 8'd1));
    end

    // =============================================================
    // TC-77 (BP-153, RAS-4, TD#207): the restore operations the backend
    // redirect presents (ftq.sv bk_ras) on the C1 ports, which TC-75 did
    // not reach, since predecode raises a JAL only.
    //   (a) an indirect call: C pushed on the restored A, dep 2.
    //   (b) a return on an empty restored stack: no array change, the
    //       depth one less, so the next fallback reads the committed frame
    //       one deeper (A1). From TC-73a's state (A and B committed, the
    //       stack empty, dcm 2): after the backend's pop, b's return is
    //       accounted for, and a's return reads A, not B.
    //   (c) a return-call on an empty restored stack: the pop takes the
    //       depth, the push allocates C on the empty stack, bottom; the
    //       pop of C then leaves the stack empty at depth 1, whose
    //       fallback is A.
    // =============================================================
    begin
      bp_ras_snapshot_t s77;
      // (a)
      do_reset();
      push_one(ADDR_A);                                    // idx1
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      s77 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      push_one(ADDR_B);                                    // wrong path
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s77;
      pd_val = 1'b1; pd_type = INDIRECT_CALL; pd_ret = ADDR_C;
      #1;
      check("TC-77a backend indirect call: pd snapshot C at idx2, dep 2",
            (pd_snap.tosr == 'd2) && (pd_snap.tosw == 'd3) &&
            (pd_snap.dep == 8'd2));
      tick();
      restore_val = 1'b0; restore_snap = '0; pd_val = 1'b0;
      check("TC-77a C pushed on the restored A, linked to idx1",
            ptr_is(2, 3, 0) && ent_is(2, ADDR_C, 0, 1, 0) &&
            (dut.dsp == 8'd2));
      pop_chk("TC-77a pop C", 0, 1'b1, ADDR_C);
      pop_chk("TC-77a pop A", 0, 1'b1, ADDR_A);
      // (b)
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_B);
      commit_op(DIRECT_CALL, ADDR_A, 'd1);
      commit_op(DIRECT_CALL, ADDR_B, 'd2);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      s77 = snap_p2[NUM_PRED_SLOTS-1];                    // empty, dep 2
      check("TC-77b fixture: the snapshot is an empty stack at dep 2",
            (s77.tosr == s77.bos) && (s77.dep == 8'd2) && (dut.dcm == 8'd2));
      tick();
      restore_val = 1'b1; restore_snap = s77;
      pd_val = 1'b1; pd_type = RETURN; pd_ret = '0;
      #1;
      check("TC-77b backend return on an empty stack: pd snapshot dep 1",
            (pd_snap.tosr == pd_snap.bos) && (pd_snap.dep == 8'd1));
      tick();
      restore_val = 1'b0; restore_snap = '0; pd_val = 1'b0;
      check("TC-77b no pointer moves, dsp 1, csp 2",
            ptr_is(2, 3, 2) && (dut.dsp == 8'd1) && (int'(dut.csp) == 2));
      pop_chk("TC-77b a's return: fallback n 1, A (without the pop: B)", 0,
              1'b1, ADDR_A);
      // (c)
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_B);
      commit_op(DIRECT_CALL, ADDR_A, 'd1);
      commit_op(DIRECT_CALL, ADDR_B, 'd2);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      s77 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      restore_val = 1'b1; restore_snap = s77;
      pd_val = 1'b1; pd_type = RETURN_CALL; pd_ret = ADDR_C;
      #1;
      check("TC-77c backend return-call on an empty stack: C pushed, dep 2",
            (pd_snap.tosr == 'd3) && (pd_snap.dep == 8'd2));
      tick();
      restore_val = 1'b0; restore_snap = '0; pd_val = 1'b0;
      check("TC-77c C at idx3, bottom, linked to BOS",
            ptr_is(3, 4, 2) && ent_is(3, ADDR_C, 0, 2, 1) &&
            (dut.dsp == 8'd2));
      pop_chk("TC-77c pop C", 0, 1'b1, ADDR_C);
      pop_chk("TC-77c then the fallback at depth 1: A", 0, 1'b1, ADDR_A);
    end

    // =============================================================
    // TC-78 (BP-153, RAS-4, TD#207; BP-151 cause snap_offpath_op): the
    // undo of the restored block's own pop (ras_rs_undo_pop) from the
    // snapshot's pop record. The block's snapshot is post-op; a redirect
    // that leaves the block before its return restores a stack the
    // return has popped. Before BP-153 nothing undid it: the snapshot held
    // no pre-op TOSR, and with A1 the depth was one low.
    //   (a) THE DEPTH HALF: a pop on an empty stack (EMPTY). From TC-73a's
    //       state (A and B committed, empty, dcm 2) b's return pops, the
    //       fallback B. Its snapshot, restored with the undo, is at depth
    //       2 again, so the next return reads B (n 0), not A.
    //   (b) THE POINTER HALF: a pop that followed the link (LINK). A, B
    //       pushed; B's return pops to A. Restored with the undo, TOSR is
    //       back at B.
    //   (c) a pop that decremented a count (DEC): A pushed twice (count
    //       1); the pop takes the count to 0. Restored with the undo, the
    //       count is 1 again.
    //   (d) the pointer half to a reallocated entry: B's return pops to
    //       A; the wrong path pushes C, D, ... until B's index is
    //       allocated again. Restored with the undo, the generation at B's
    //       index moved: the stack reads empty (B1), the depth restored.
    //   (e) a snapshot with no pop record (pmode NONE): the undo changes
    //       nothing.
    // =============================================================
    begin
      bp_ras_snapshot_t s78;
      // (a)
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_B);
      commit_op(DIRECT_CALL, ADDR_A, 'd1);
      commit_op(DIRECT_CALL, ADDR_B, 'd2);
      drv(0, 1'b1, RETURN, '0);                            // b's return
      #1;
      s78 = snap_p2[NUM_PRED_SLOTS-1];
      check("TC-78a the snapshot's pop record: EMPTY, dep 1",
            (s78.pmode == RAS_POP_EMPTY) && (s78.dep == 8'd1));
      tick();
      pop_chk("TC-78a wrong path: a second pop reads A", 0, 1'b1, ADDR_A);
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s78; rs_undo_pop = 1'b1;
      #1;
      check("TC-78a undo pd snapshot: dep 2, no pop record",
            (pd_snap.dep == 8'd2) && (pd_snap.pmode == RAS_POP_NONE));
      tick();
      restore_val = 1'b0; restore_snap = '0; rs_undo_pop = 1'b0;
      check("TC-78a THE DEPTH HALF: dsp 2 after the undo (without it: 1)",
            ptr_is(2, 3, 2) && (dut.dsp == 8'd2));
      pop_chk("TC-78a the next return reads B (n 0; without the undo: A)", 0,
              1'b1, ADDR_B);
      // (b)
      do_reset();
      push_one(ADDR_A);                                    // idx1
      push_one(ADDR_B);                                    // idx2
      drv(0, 1'b1, RETURN, '0);                            // B's return
      #1;
      s78 = snap_p2[NUM_PRED_SLOTS-1];
      check("TC-78b the snapshot's pop record: LINK from idx2, its tag",
            (s78.pmode == RAS_POP_LINK) && (s78.ptosr == 'd2) &&
            (s78.ptag == dut.spec_gen[2]) && (s78.tosr == 'd1) &&
            (s78.dep == 8'd1));
      tick();
      pop_chk("TC-78b wrong path: A popped", 0, 1'b1, ADDR_A);
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s78; rs_undo_pop = 1'b1;
      tick();
      restore_val = 1'b0; restore_snap = '0; rs_undo_pop = 1'b0;
      check("TC-78b THE POINTER HALF: TOSR back at B (idx2), dsp 2",
            ptr_is(2, 3, 0) && (dut.dsp == 8'd2) &&
            ent_is(2, ADDR_B, 0, 1, 0));
      pop_chk("TC-78b pop B (without the undo: A)", 0, 1'b1, ADDR_B);
      pop_chk("TC-78b pop A", 0, 1'b1, ADDR_A);
      // (c)
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_A);                                    // count 1
      drv(0, 1'b1, RETURN, '0);
      #1;
      s78 = snap_p2[NUM_PRED_SLOTS-1];
      check("TC-78c the snapshot's pop record: DEC at idx1, count 0",
            (s78.pmode == RAS_POP_DEC) && (s78.ptosr == 'd1) &&
            (s78.tosr == 'd1) && (s78.rctr == 'd0));
      tick();
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s78; rs_undo_pop = 1'b1;
      tick();
      restore_val = 1'b0; restore_snap = '0; rs_undo_pop = 1'b0;
      check("TC-78c the count back to 1, dsp 2",
            ptr_is(1, 2, 0) && ent_is(1, ADDR_A, 1, 0, 1) &&
            (dut.dsp == 8'd2));
      // (d)
      do_reset();
      push_one(ADDR_A);                                    // idx1
      push_one(ADDR_B);                                    // idx2
      drv(0, 1'b1, RETURN, '0);
      #1;
      s78 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      // The wrong path: push and pop until the allocator is round to idx2
      // again (TOSW runs 3..15, 0 is BOS, skipped, then 1 and 2 are not
      // reached while the pushes pop again; push on A until TOSW is 2).
      for (int k = 0; k < RAS_SPEC_ENTRIES; k++) begin
        if (dut.tosw == 'd2) break;
        push_one(ADDR_X);
        pop_chk($sformatf("TC-78d wrong path %0d", k), 0, 1'b1, ADDR_X);
      end
      push_one(ADDR_X);                                    // reallocates idx2
      check("TC-78d fixture: idx2 reallocated (generation moved)",
            dut.spec_gen[2] != s78.ptag);
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s78; rs_undo_pop = 1'b1;
      tick();
      restore_val = 1'b0; restore_snap = '0; rs_undo_pop = 1'b0;
      check("TC-78d the undo to a reallocated entry reads empty, dsp 2",
            (dut.tosr == dut.bos) && (dut.dsp == 8'd2));
      // (e)
      do_reset();
      push_one(ADDR_A);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      s78 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s78; rs_undo_pop = 1'b1;
      tick();
      restore_val = 1'b0; restore_snap = '0; rs_undo_pop = 1'b0;
      check("TC-78e no pop record: the undo changes nothing",
            (s78.pmode == RAS_POP_NONE) && ptr_is(1, 2, 0) &&
            (dut.dsp == 8'd1));
    end

    // =============================================================
    // TC-79 (BP-153, BP-151 cause p3_reach): the peek. ras_peek_*_p2 is
    // the pop a slot would make, from the state the earlier slots leave,
    // whether or not the slot pops; nothing moves. bp_cluster takes a
    // return's target from it, so a return unreachable at p2 that SC
    // makes reachable at p3 has the RAS target. Before BP-153 there was
    // no peek, and the target of such a return was the FTB jump target.
    //   (a) a slot that does not pop: the top, and nothing moves.
    //   (b) a slot that pops: the peek equals the pop.
    //   (c) an empty stack: the fallback at the speculative depth.
    //   (d) two slots: slot 0 pushes C, slot 1 does not pop; slot 1's
    //       peek is C, the state slot 0 leaves.
    // =============================================================
    begin
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_B);
      // (a)
      drv(0, 1'b0, RETURN, '0);
      #1;
      check("TC-79a a slot that does not pop: peek B, no pop",
            peek_valid_p2[0] && (peek_addr_p2[0] == ADDR_B) &&
            !pop_valid_p2[0]);
      tick();
      check("TC-79a nothing moves", ptr_is(2, 3, 0) && (dut.dsp == 8'd2));
      // (b)
      drv(0, 1'b1, RETURN, '0);
      #1;
      check("TC-79b a slot that pops: peek == pop == B",
            peek_valid_p2[0] && pop_valid_p2[0] &&
            (peek_addr_p2[0] == ADDR_B) && (pop_addr_p2[0] == ADDR_B));
      tick();
      // (c)
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_B);
      commit_op(DIRECT_CALL, ADDR_A, 'd1);
      commit_op(DIRECT_CALL, ADDR_B, 'd2);
      drv(0, 1'b0, RETURN, '0);
      #1;
      check("TC-79c an empty stack: the fallback, B (n 0)",
            peek_valid_p2[0] && (peek_addr_p2[0] == ADDR_B));
      tick();
      // (d)
      if (NUM_PRED_SLOTS > 1) begin : tc79d
        do_reset();
        push_one(ADDR_A);
        drive(1'b1, DIRECT_CALL, ADDR_C, 1'b0, RETURN, '0);
        #1;
        check("TC-79d slot 1's peek is slot 0's push, C",
              peek_valid_p2[NUM_PRED_SLOTS-1] &&
              (peek_addr_p2[NUM_PRED_SLOTS-1] == ADDR_C) &&
              !pop_valid_p2[NUM_PRED_SLOTS-1]);
        tick();
      end
    end

    // =============================================================
    // TC-80 (BP-153, TD#149): the p3 block's snapshot after its repair
    // (ras_rep_val, ras_rep_snapshot). The block's p2 snapshot does not
    // hold a p3 repair; before BP-153 the entry kept it, so the block's
    // commit set the committed depth one off and its restores lost the
    // repair (fb_stale_top, web_11 (8, 8) k 51522).
    //   (a) a missed push (p2 none, p3 call): the snapshot holds C on top,
    //       dep + 1, push recorded.
    //   (b) a missed pop (p2 none, p3 return): B popped, dep - 1, the pop
    //       record LINK from B's index.
    //   (c) no repair: not valid.
    //   (d) a restore in the repair's cycle drops it: not valid.
    // =============================================================
    begin
      // (a)
      do_reset();
      push_one(ADDR_A);                                    // idx1
      drive(1'b0, NO_BRANCH, ADDR_C, 1'b0, NO_BRANCH, '0);
      tick();                                              // op NONE
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(1'b1, DIRECT_CALL, 1'b0, NO_BRANCH);
      #1;
      check("TC-80a missed push: the repaired snapshot is valid",
            rep_val);
      check("TC-80a C at idx2 on top, dep 2, push recorded",
            (rep_snap.tosr == 'd2) && (rep_snap.tosw == 'd3) &&
            (rep_snap.dep == 8'd2) && rep_snap.push &&
            (rep_snap.pmode == RAS_POP_NONE) &&
            (rep_snap.tag == RAS_TAG_BITS'(dut.spec_gen[2] + 1)));
      tick();
      check("TC-80a the state is the snapshot's", ptr_is(2, 3, 0) &&
            (dut.dsp == 8'd2) && (dut.spec_gen[2] == rep_snap.tag));
      // (b)
      do_reset();
      push_one(ADDR_A);                                    // idx1
      push_one(ADDR_B);                                    // idx2
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      tick();
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(1'b1, RETURN, 1'b0, NO_BRANCH);
      #1;
      check("TC-80b missed pop: B popped, dep 1, LINK record from idx2",
            rep_val && (rep_snap.tosr == 'd1) && (rep_snap.dep == 8'd1) &&
            !rep_snap.push && (rep_snap.pmode == RAS_POP_LINK) &&
            (rep_snap.ptosr == 'd2) && (rep_snap.ptag == dut.spec_gen[2]));
      tick();
      // (c)
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      check("TC-80c no repair: not valid", !rep_val);
      tick();
      // (d)
      do_reset();
      push_one(ADDR_A);
      drive(1'b0, NO_BRANCH, ADDR_C, 1'b0, NO_BRANCH, '0);
      tick();
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      force_p3(1'b1, DIRECT_CALL, 1'b0, NO_BRANCH);
      restore_val = 1'b1; restore_snap = snp(1, 2, 0, 0);
      #1;
      check("TC-80d a restore in the repair's cycle: not valid", !rep_val);
      tick();
      restore_val = 1'b0; restore_snap = '0;
    end

    // =============================================================
    // TC-81 (BP-153, BP-151 causes depth, pop_empty): a call depth of 40,
    // committed, read back by 40 returns through the fallback (A1).
    // Every frame is held: RAS_COMMIT_ENTRIES 64 since BP-153. With 32
    // entries the 9th return onward read nothing (frames 8 .. 1 were
    // overwritten by the full stack's wrap, 3.3).
    // =============================================================
    begin
      do_reset();
      // Committed only (no speculative push, as TC-36): the speculative
      // stack stays empty and every return reads the fallback, n = 0, 1,
      // 2 ... as its pop takes the depth down.
      for (int i = 0; i < 40; i++)
        commit_op(DIRECT_CALL, cs_ad(32'h7_0000, i), 'd0);
      for (int i = 39; i >= 0; i--)
        pop_chk($sformatf("TC-81 return %0d of 40 reads frame %0d", 40 - i, i),
                0, 1'b1, cs_ad(32'h7_0000, i));
    end

    // =============================================================
    // TC-82 (BP-153; a capacity case since BP-154; BP-151 causes wrap,
    // fb_uncommitted): an uncommitted call A, then TC82_PAIRS (20)
    // call-return pairs. The allocator only advances (TOSW, PU1), so each
    // pair allocates a new entry. From reset A is the sentinel skip's
    // idx1 (TOSW 0 == BOS 0) and pair k allocates idx k + 2, so pair
    // RAS_SPEC_ENTRIES - 2 finds TOSW back at BOS 0 and the skip lands on
    // idx1: the RAS_SPEC_ENTRIES-th allocation reuses A's entry. The
    // outcome follows from the parameter:
    //   - RAS_SPEC_ENTRIES - 2 < TC82_PAIRS (16 entries, pair 14): A's
    //     entry is reused, the allocation lands on the TOSR entry itself
    //     and is bottom (B1), and A's return reads the empty stack's
    //     fallback. Nothing is committed, so it is not valid: A's return
    //     is mispredicted. This is the wrap of RAS-2 (ras_decisions.md
    //     3.2), at 16 entries since RC11's revert (BP-154).
    //   - otherwise (32 entries, BP-153 RC11): A is still held and its
    //     return reads A.
    // =============================================================
    begin
      int idx_a, k_reuse, first_reuse;
      bit lapped;
      k_reuse     = RAS_SPEC_ENTRIES - 2;
      lapped      = (k_reuse < TC82_PAIRS);
      first_reuse = -1;
      $display("TC-82 RAS_SPEC_ENTRIES %0d, %0d pairs, lap at pair %0d:",
               RAS_SPEC_ENTRIES, TC82_PAIRS, k_reuse);
      if (lapped)
        $display("TC-82   checks the reuse of A's entry and A's return %s",
                 "mispredicted");
      else
        $display("TC-82   checks A's return read right");
      do_reset();
      push_one(ADDR_A);
      idx_a = int'(dut.tosr);
      check("TC-82 A is allocated at idx1 (the sentinel skip from reset)",
            (idx_a == 1) && (dut.spec_ret_addr[1] == ADDR_A));
      for (int k = 0; k < TC82_PAIRS; k++) begin
        push_one(fill_addr[k]);
        if ((first_reuse < 0) && (dut.spec_ret_addr[idx_a] != ADDR_A)) begin
          first_reuse = k;
          $display("TC-82   pair %0d allocates idx%0d: A's entry holds %h",
                   k, idx_a, dut.spec_ret_addr[idx_a]);
        end
        pop_chk($sformatf("TC-82 pair %0d", k), 0, 1'b1, fill_addr[k]);
      end
      if (lapped) begin
        check($sformatf("TC-82 A's entry reused by pair %0d (ENTRIES - 2)",
                        k_reuse), first_reuse == k_reuse);
        pop_chk("TC-82 A's return after the lap is not valid (mispredicted)",
                0, 1'b0, ADDR_A);
      end else begin
        check("TC-82 A's entry is not reused within the pairs",
              first_reuse == -1);
        pop_chk("TC-82 A's return after the pairs reads A", 0, 1'b1, ADDR_A);
      end
    end

    // =============================================================
    // TC-83 (BP-153, the count below, spec_ncnt; BP-151 cause
    // bos_rewind, infra_1 (0, 8) k 531556): a count the wrong path
    // changed in place on the entry BELOW the restored top. A at idx1,
    // B at idx2 (nos 1), the snapshot S after B. The wrong path pops B
    // (TOSR to idx1) and calls with fall-through A: the recursion match
    // raises idx1's count to 1. The restore of S puts back idx2's count
    // (RE6) and not idx1's. The pop of B then lands on idx1 with the
    // count B recorded at its allocation, 0: the pop of A follows the
    // link and the stack is empty, nothing committed: not valid. Before
    // BP-153 idx1 kept count 1 and the pop of A only decremented it:
    // TOSR stayed at idx1, and a third pop read A again.
    // =============================================================
    begin
      bp_ras_snapshot_t s83;
      do_reset();
      push_one(ADDR_A);
      push_one(ADDR_B);
      drive(1'b0, NO_BRANCH, '0, 1'b0, NO_BRANCH, '0);
      #1;
      s83 = snap_p2[NUM_PRED_SLOTS-1];
      tick();
      pop_chk("TC-83 wrong path: the pop of B", 0, 1'b1, ADDR_B);
      push_one(ADDR_A);
      check("TC-83 wrong path: the call matching A raises idx1's count to 1",
            ptr_is(1, 3, 0) && (dut.spec_rctr[1] == 'd1) &&
            (dut.spec_ncnt[2] == 'd0));
      drv(0, 1'b0, NO_BRANCH, '0);
      restore_val = 1'b1; restore_snap = s83;
      tick();
      restore_val = 1'b0; restore_snap = '0;
      check("TC-83 the restore of S: tosr 2 (B), idx1's count still 1",
            ptr_is(2, 3, 0) && (dut.spec_rctr[1] == 'd1));
      pop_chk("TC-83 the pop of B returns B", 0, 1'b1, ADDR_B);
      check("TC-83 it lands on idx1 with B's recorded count 0 (was 1)",
            ptr_is(1, 3, 0) && (dut.spec_rctr[1] == 'd0));
      pop_chk("TC-83 the pop of A returns A", 0, 1'b1, ADDR_A);
      pop_chk("TC-83 then the stack is empty: not valid (before: A again)",
              0, 1'b0, '0);
    end

    // -------------------------------------------------------------
    // The reference model (Problem 2): it ran in every case above,
    // from each case's reset. One check stands for all its comparisons.
    $display("tb_ras: MODEL comparisons %0d, mismatches %0d (IV1/PO7 %0d)",
             m_ncmp, m_nmis, m_niv);
    // BP-143: the wrap (PO7), per case and in total.
    if (m_wpend != 0) m_wcase["(after the last check)"] = m_wpend;
    foreach (m_wcase[c])
      $display("tb_ras: MODEL wraps %s %0d", c, m_wcase[c]);
    $display("tb_ras: MODEL wraps total %0d", m_nwrap);
    $display("tb_ras: MODEL IV1 converse failures %0d, wraps at BOS %0d",
             m_nconv, m_nbwrap);
    check($sformatf("MODEL %0d comparisons, no mismatch", m_ncmp),
          (m_nmis == 0) && (m_ncmp > 0));
    $display("=================================================");
    $display("tb_ras: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    $display("=================================================");
    if (fail_cnt != 0)
      $fatal(1, "tb_ras: %0d checks failed", fail_cnt);
    else
      $finish;
  end

  // Watchdog
  initial begin
    #500000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "tb_ras: timeout");
  end

endmodule
