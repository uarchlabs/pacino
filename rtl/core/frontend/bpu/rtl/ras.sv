// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    ras.sv
// DATE:    2026-06-23
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Return Address Stack (RAS) predictor.
//
// Single self-contained module. No synchronous SRAMs, no PQ/UQ, no
// credit arbiter. Two register-file stacks:
//   - Speculative stack: RAS_SPEC_ENTRIES, circular buffer with a
//     next-on-stack link (nos) per entry (ras_decisions.md 3.2, ruled
//     session-075, TD#159). Pointers TOSR/TOSW/BOS and the top entry's
//     recursion count, snapshotted into the FTQ for O(1) mispredict
//     recovery (the count since BP-142, TD#194 option A).
//   - Commit stack: RAS_COMMIT_ENTRIES, conventional circular stack.
//     Pointer CSP and an occupancy count, so a full stack is not read
//     as empty (BP-126, TD#121). Updated at retire. Empty fallback for
//     pops.
//
// Pipeline (p-stage names, as the planning documents use since
// session-072; older history entries there keep the s-stage labels):
//   p0: combinational TOS read (initial prediction fallback).
//   p2: FTB-confirmed push/pop, two slots, slot 0 before slot 1,
//       with slot0=call / slot1=return same-cycle bypass. RETURN_CALL
//       pops then pushes in one slot (RAS-DS1, TD#152).
//   p3: repair pass, inverse op when p3 FTB type disagrees with the
//       registered p2 op (speculative stack only). An undo reverses the
//       recursion counts the p2 op changed (BP-133, TD #78), and only
//       those: a push at a saturated count is not undone (BP-134).
//
// Empty is TOSR == BOS, and BP-138 keeps it exact when a commit moves
// BOS: see THE BOTTOM below.
//
// BP-152 (RAS-4, TD#207), three rules, each for acceptance:
//   A1  THE FALLBACK READS THE COMMITTED FRAME AT THE SPECULATIVE DEPTH.
//       dsp is the speculative path's call depth: a push adds one, a pop
//       takes one, whatever the stack does with it; it is carried in the
//       snapshot as dep and restored. dcm is the dep of the last block
//       the RAS committed (ras_commit_snapshot.dep), the depth the
//       commit stack's top stands at in the same count. n = dcm - dsp is
//       the number of committed frames the blocks after it have popped
//       and not committed. The fallback reads CSP-1-n; before BP-152 it
//       read CSP-1, the frame such a pop had already consumed
//       (fb_stale_top, BP-151). With n below 0 (the speculative path
//       deeper than the committed one, which only the wrap leaves empty)
//       it reads CSP-1 as before; with n at or above the count the frame
//       is gone and the pop is not valid. dcm is taken from the snapshot
//       rather than counted at commit, so a call or return that commits
//       without having operated at p2 (one the FTB did not give) cannot
//       leave the two depths apart for good.
//   B1  A LINK NEVER NAMES A REUSED ENTRY. An allocation at index a
//       makes bottom every other entry whose link names a, so its pop
//       goes to BOS and falls back (A1); before BP-152 it followed the
//       link into the reusing push (stale_below_bos, BP-151). A push
//       whose allocation lands on the TOSR entry itself is bottom. Each
//       entry carries an allocation generation (spec_gen); the snapshot
//       carries the generation of its TOSR entry (tag), and a restore,
//       or a p3 undo, to a TOSR entry reallocated since reads empty.
//       So TOSR == BOS stays the whole empty test (IV1).
//   C1  ras_pd_*: the operation of a call or return only predecode
//       found, applied on top of the restore of the predecode redirect
//       that corrects its block (ras_decisions.md 7). The post-op
//       snapshot goes back to the FTQ on ras_pd_snapshot.
//   ras_rs_undo: a restore whose block's snapshot holds a push the
//       redirect shows off the path (it leaves the block before the
//       call) retracts that push first. With C1 every predecode call is
//       in its block's snapshot, so a conditional before it resolved
//       taken, or a trap before it, would otherwise keep it.
//
// BP-153 (RAS-4, TD#207), for acceptance:
//   The backend's operation. The C1 ports also carry the call or return
//       a backend redirect resolves and the entry did not hold (ftq.sv
//       bk_ras): the same operation on the restored state.
//   ras_rs_undo_pop: the restored block's own pop is off the path. The
//       snapshot is post-op and, before BP-153, held no pre-op TOSR, so
//       the pop stayed (snap_offpath_op, BP-151 E) and, with A1, the
//       depth was one low. Each snapshot now carries the block's pop
//       record (pmode, ptosr, ptag), and the restore undoes it as the
//       p3 undo-pop does: TOSR back to ptosr (unless its generation
//       moved, B1), a decremented count incremented, and the depth plus
//       one. The p1 snapshot carries no record (bp_cluster): its block
//       has not operated yet.
//
// See planning/arch/ras_decisions.md and
// planning/interfaces/ras_interfaces.md.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ras (
  input  logic                clk,
  input  logic                rstn,

  // ---- p0 TOS read outputs (one per slot) -------------------------
  output logic [VA_WIDTH-1:0] ras_tos_addr_p0  [0:NUM_PRED_SLOTS-1],
  output logic                ras_tos_valid_p0 [0:NUM_PRED_SLOTS-1],

  // ---- p2 prediction inputs (one per slot) ------------------------
  input  logic                ras_pred_val_p2     [0:NUM_PRED_SLOTS-1],
  input  bp_br_type_e         ras_br_type_p2      [0:NUM_PRED_SLOTS-1],
  input  logic [VA_WIDTH-1:0] ras_fall_through_p2 [0:NUM_PRED_SLOTS-1],

  // ---- p2 prediction outputs (one per slot) -----------------------
  output logic [VA_WIDTH-1:0] ras_pop_addr_p2  [0:NUM_PRED_SLOTS-1],
  output logic                ras_pop_valid_p2 [0:NUM_PRED_SLOTS-1],
  output bp_ras_snapshot_t    ras_snapshot_p2  [0:NUM_PRED_SLOTS-1],
  // BP-153 (p3_reach): the address the slot's pop would read, from the
  // state the earlier slots leave, whether or not the slot pops at p2.
  // Equal to ras_pop_addr_p2 / _valid for a slot that pops. A return
  // unreachable at p2 (an earlier conditional predicted taken) that SC
  // makes reachable at p3 takes its target from it (bp_cluster).
  output logic [VA_WIDTH-1:0] ras_peek_addr_p2  [0:NUM_PRED_SLOTS-1],
  output logic                ras_peek_valid_p2 [0:NUM_PRED_SLOTS-1],

  // ---- p3 repair inputs (one per slot) ----------------------------
  // Registered (external) FTB structural type at p3 (IC-RAS-11).
  input  logic                ras_pred_val_p3 [0:NUM_PRED_SLOTS-1],
  input  bp_br_type_e         ras_br_type_p3  [0:NUM_PRED_SLOTS-1],
  // BP-153 (TD#149): the p3 block's snapshot after this cycle's repair
  // pass, valid when the repair changed the stack for it and no restore
  // drops the repair. The block's p2 snapshot (bpu_blk_ras_p2) did not
  // hold the repair; the FTQ writes this one over it.
  output logic                ras_rep_val,
  output bp_ras_snapshot_t    ras_rep_snapshot,

  // ---- mispredict restore (IC-RAS-09) -----------------------------
  input  logic                ras_restore_val,
  // The p2 pass of this cycle is on the path (BP-121, FE-14). Low when
  // a redirect squashes the block at p2: the p2 operation is dropped
  // and the p3 repair still applies (a p3 redirect, which the cluster
  // takes without a restore).
  input  logic                ras_p2_keep,
  input  bp_ras_snapshot_t    ras_restore_snapshot,

  // ---- commit (IC-RAS-10) -----------------------------------------
  input  logic                ras_commit_val,
  input  bp_br_type_e         ras_commit_br_type,
  input  logic [VA_WIDTH-1:0] ras_commit_ret_addr,
  input  bp_ras_snapshot_t    ras_commit_snapshot,

  // ---- flush (redundant, read by nothing; RAS-3 CLOSED: a flush is a
  //      redirect and takes the pointer restore, ras_decisions.md 4.4)
  input  logic                ras_flush_val,
  input  bp_ras_snapshot_t    ras_flush_snapshot,

  // ---- C1, the predecode operation (BP-152) -------------------------
  // Read only with ras_restore_val: the restore is the predecode
  // redirect's, and its block holds a call or return that predecode
  // found and the RAS did not operate at p2. The type names the
  // operation (a call pushes ras_pd_ret_addr, the instruction's own pc
  // plus its length; a return pops; RETURN_CALL both), applied to the
  // restored state. ras_pd_snapshot is the state after it, for the FTQ
  // entry of the block. Driven every cycle from ras_restore_snapshot.
  input  logic                ras_pd_val,
  input  bp_br_type_e         ras_pd_br_type,
  input  logic [VA_WIDTH-1:0] ras_pd_ret_addr,
  // Read only with ras_restore_val (BP-152): the restored block's own
  // push is off the path (the redirect leaves the block before the call
  // its snapshot holds), so it is undone first, as the p3 undo-push
  // retracts the top. Then the C1 operation, if any. ras_pd_snapshot is
  // the state after both.
  input  logic                ras_rs_undo,
  // Read only with ras_restore_val (BP-153): the restored block's own
  // pop is off the path, so it is undone from the snapshot's pop record
  // (pmode, ptosr, ptag), after the push undo and before the C1
  // operation. A snapshot with pmode RAS_POP_NONE is left as it is.
  input  logic                ras_rs_undo_pop,
  output bp_ras_snapshot_t    ras_pd_snapshot
);

  // -----------------------------------------------------------------
  // Local constants
  // -----------------------------------------------------------------
  // Recursion counter saturation value (2^RAS_RCTR_WIDTH - 1).
  localparam logic [RAS_RCTR_WIDTH-1:0] RCTR_MAX =
                                          {RAS_RCTR_WIDTH{1'b1}};

  // p2 operation encoding, registered into the p3 pipeline so the
  // p3 repair can compare the actual p2 op against the p3 FTB type.
  // Bit 1 is the pop, bit 0 the push, so RETURN_CALL is both
  // (OP_POPPUSH, RAS-DS1: the pop first, then the push).
  localparam logic [1:0] OP_NONE    = 2'b00;
  localparam logic [1:0] OP_PUSH    = 2'b01;
  localparam logic [1:0] OP_POP     = 2'b10;
  localparam logic [1:0] OP_POPPUSH = 2'b11;

  // Speculative-stack write ports. Each pass (the p3 repair, then the
  // p2 operation) can write the array twice per slot: a RETURN_CALL
  // pop that only decrements a recursion count writes at TOSR, and the
  // push that follows writes at the frontier. Port index
  //   (pass * NUM_PRED_SLOTS + slot) * 2 + n
  // with pass 0 the repair and pass 1 the p2 operation, and n the
  // order of the write within the slot. Writes are applied in index
  // order, which is the order the scan makes them.
  localparam int RAS_WR_PER_SLOT = 2;
  localparam int RAS_WR_PORTS    = 2 * NUM_PRED_SLOTS * RAS_WR_PER_SLOT;
  // The restore cycle's writes (BP-152): port 0 the count of the
  // snapshot's top (RE6), port 1 the undo of the block's push, port 2
  // the count the undo of the block's pop puts back (BP-153), ports 3
  // and 4 the C1 pop and push, in that order.
  localparam int RS_WR_PORTS     = 5;
  localparam int RS_P_UNDO       = 1;
  localparam int RS_P_UPOP       = 2;
  localparam int RS_P_POP        = 3;
  localparam int RS_P_PUSH       = 4;

  localparam logic [RAS_PTR_BITS-1:0]   PTR_ONE  = RAS_PTR_BITS'(1);
  localparam logic [RAS_RCTR_WIDTH-1:0] RCTR_ONE = RAS_RCTR_WIDTH'(1);
  localparam logic [RAS_DEPTH_BITS-1:0] DEP_ONE  = RAS_DEPTH_BITS'(1);
  localparam logic [RAS_TAG_BITS-1:0]   TAG_ONE  = RAS_TAG_BITS'(1);
  localparam int RAS_COMMIT_CNT_BITS = RAS_COMMIT_PTR_BITS + 1;

  // -----------------------------------------------------------------
  // Register-file storage and pointers
  // -----------------------------------------------------------------
  logic [VA_WIDTH-1:0]       spec_ret_addr [0:RAS_SPEC_ENTRIES-1];
  logic [RAS_RCTR_WIDTH-1:0] spec_rctr     [0:RAS_SPEC_ENTRIES-1];
  // Next on stack: the index of the entry below this one (3.2, ruled
  // session-075, BP-120). Written by the push that allocates the
  // entry, read by the pop that removes it. Internal; the snapshot
  // carries the three pointers and the top entry's count (4.1).
  logic [RAS_PTR_BITS-1:0]   spec_nos      [0:RAS_SPEC_ENTRIES-1];
  // Bottom (BP-138): the entry was pushed onto an empty stack, or by
  // the sentinel skip, so nothing speculative lies below it. A pop
  // that removes it sets TOSR to BOS as it is then, not to nos. Since
  // BP-152 also set when the entry its link names is reallocated (B1).
  logic                      spec_bot      [0:RAS_SPEC_ENTRIES-1];
  // Allocation generation (BP-152, B1): advanced each time the index is
  // allocated, so a snapshot (tag) or a p3 undo that names the index
  // can tell whether the entry is still the one it named.
  logic [RAS_TAG_BITS-1:0]   spec_gen      [0:RAS_SPEC_ENTRIES-1];
  // The count below (BP-153, RAS-4): the recursion count the entry its
  // link names had when this entry was allocated. Written only by the
  // allocation. A pop that follows the link writes it back as the count
  // of the entry it lands on, so a count the wrong path changed in place
  // on an entry below the restored top is put back on the path. Before
  // BP-153 only the restored top's count was put back (RE6), and an
  // off-path recursion match one entry below kept its count.
  logic [RAS_RCTR_WIDTH-1:0] spec_ncnt     [0:RAS_SPEC_ENTRIES-1];

  // No recursion count on the commit stack: each committed call is its
  // own entry (BP-133, TD#79). The commit_rctr field, written zero and
  // read by nothing, is removed (BP-134).
  logic [VA_WIDTH-1:0]       commit_ret_addr [0:RAS_COMMIT_ENTRIES-1];

  logic [RAS_PTR_BITS-1:0]        tosr; // top-of-stack read
  logic [RAS_PTR_BITS-1:0]        tosw; // top-of-stack write (free)
  logic [RAS_PTR_BITS-1:0]        bos;  // committed boundary
  logic [RAS_COMMIT_PTR_BITS-1:0] csp;  // commit free pointer
  // Commit-stack occupancy, 0 to RAS_COMMIT_ENTRIES (BP-126, TD#121).
  // CSP alone wraps to 0 on the 32nd push and could not tell a full
  // stack from an empty one. Empty is c_cnt == 0.
  logic [RAS_COMMIT_CNT_BITS-1:0] c_cnt;
  // The call depths (BP-152, A1): the speculative path's, and the dep of
  // the last block the RAS committed. Free running; only dcm - dsp is
  // read.
  logic [RAS_DEPTH_BITS-1:0]      dsp;
  logic [RAS_DEPTH_BITS-1:0]      dcm;

  // Registered "reset complete": low in the first cycle after reset,
  // high after. Read by observers only (tb_fe_top, examples/fe_demo).
  // Until BP-142 it gated every p2 operation and repair, which dropped
  // a push or pop made in the first cycle after reset; CL1 and CL2
  // (ras_decisions.md 12.1) do not except that cycle (tb_ras TC-47c).
  // The scan reads flops (tosr, tosw, bos, the arrays), so it stays
  // nba_sequent without it (CLAUDE.md stl_sequent note).
  logic ras_rst_done;

  // p2 -> p3 pipeline registers: actual p2 op and the fallthrough
  // address used, per slot. Consumed by the p3 repair pass.
  logic [1:0]          p3_op_q      [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] p3_fallthr_q [0:NUM_PRED_SLOTS-1];
  // TOSR before the slot's p2 operation. Read to undo a pop, alone or
  // as the first half of a whole RETURN_CALL (see the repair pass).
  // With it the generation of the entry there (BP-152, B1): an undo to
  // an entry reallocated since reads empty.
  logic [RAS_PTR_BITS-1:0] p3_pre_tosr_q [0:NUM_PRED_SLOTS-1];
  logic [RAS_TAG_BITS-1:0] p3_pre_tag_q  [0:NUM_PRED_SLOTS-1];
  // The stack was empty before the slot's p2 operation (BP-138). An
  // undo then restores TOSR to BOS as it is at the undo, which a commit
  // may have moved since p2, rather than to the registered TOSR.
  logic                    p3_pre_empty_q [0:NUM_PRED_SLOTS-1];
  // The recursion counts the slot's p2 operation changed (BP-133, TD
  // #78), so an undo reverses them as well as the pointers:
  //   p3_pop_dec_q  the pop decremented the count at the pre-op TOSR
  //                 (TOSR held) instead of following the link.
  //   p3_push_inc_q the push incremented the count at p3_inc_ptr_q (the
  //                 TOSR the push found) instead of allocating. Not set
  //                 when the count was saturated and did not move.
  //   p3_push_sat_q the push matched the top at a saturated count and
  //                 changed nothing, so an undo of it changes nothing
  //                 (BP-134; before BP-134 the undo decremented the
  //                 count, losing one recursion level).
  logic                    p3_pop_dec_q  [0:NUM_PRED_SLOTS-1];
  logic                    p3_push_inc_q [0:NUM_PRED_SLOTS-1];
  logic                    p3_push_sat_q [0:NUM_PRED_SLOTS-1];
  logic [RAS_PTR_BITS-1:0] p3_inc_ptr_q  [0:NUM_PRED_SLOTS-1];

  // -----------------------------------------------------------------
  // THE COMMIT-STACK FALLBACK (A1, BP-152). The committed frame at the
  // speculative depth d: CSP-1-n with n = dcm - d. CSP is a free
  // pointer, so the top is at CSP-1. Empty is the count at zero, not
  // CSP == 0, which a full stack also reaches (TD#121). Reads csp,
  // c_cnt, dcm and commit_ret_addr (FF outputs) -> nba_sequent.
  // -----------------------------------------------------------------
  typedef struct packed {
    logic                           valid;
    logic [RAS_COMMIT_PTR_BITS-1:0] idx;
    logic [VA_WIDTH-1:0]            addr;
  } ras_fb_t;

  function automatic ras_fb_t f_fb(input logic [RAS_DEPTH_BITS-1:0] d);
    ras_fb_t                   r;
    logic [RAS_DEPTH_BITS-1:0] n;
    n = dcm - d;
    if (n[RAS_DEPTH_BITS-1]) begin
      // The speculative path is deeper than the committed one: no
      // committed frame has been popped. The top, as before BP-152.
      r.valid = (c_cnt != '0);
      r.idx   = csp - RAS_COMMIT_PTR_BITS'(1);
    end else if (n < RAS_DEPTH_BITS'(c_cnt)) begin
      r.valid = 1'b1;
      r.idx   = csp - RAS_COMMIT_PTR_BITS'(1) - RAS_COMMIT_PTR_BITS'(n);
    end else begin
      // Every committed frame the stack holds has been popped, or the
      // frame was lost to a full commit stack's overwrite.
      r.valid = 1'b0;
      r.idx   = csp - RAS_COMMIT_PTR_BITS'(1);
    end
    r.addr = commit_ret_addr[r.idx];
    return r;
  endfunction

  // -----------------------------------------------------------------
  // p0 TOS read. Both slots present the same combinational TOS value.
  // Source: speculative top when non-empty, else the commit-stack
  // fallback at the current speculative depth (A1).
  // -----------------------------------------------------------------
  logic                spec_top_valid_p0;
  logic [VA_WIDTH-1:0] p0_tos_addr;
  logic                p0_tos_valid;
  ras_fb_t             p0_fb;

  always_comb begin
    spec_top_valid_p0 = (tosr != bos);
    p0_fb        = f_fb(dsp);
    p0_tos_addr  = spec_top_valid_p0 ? spec_ret_addr[tosr] : p0_fb.addr;
    p0_tos_valid = spec_top_valid_p0 | p0_fb.valid;
  end

  // Per-slot fan-out of the shared p0 read (named generate block).
  genvar gs;
  generate
    for (gs = 0; gs < NUM_PRED_SLOTS; gs++) begin : g_p0_tos
      assign ras_tos_addr_p0[gs]  = p0_tos_addr;
      assign ras_tos_valid_p0[gs] = p0_tos_valid;
    end
  endgenerate

  // -----------------------------------------------------------------
  // Speculative scan: p3 repair (of the previous cycle's op) followed
  // by this cycle's p2 operation, processed slot 0 before slot 1.
  //
  // The scan walks working pointer state, reading FF outputs (tosr,
  // tosw, bos and the arrays) so it is classified nba_sequent. It
  // emits up to RAS_WR_PORTS speculative write requests, the next
  // pointer state, the p2 pop outputs, the post-op snapshots, and the
  // p2 op codes to be registered for the p3 pass.
  //
  // Same-cycle bypass (IC-RAS-04): the working top (w.top_addr) holds
  // the just-pushed value, so a later-slot pop forwards it without an
  // array read.
  //
  // THE LINK (ras_decisions.md 3.2, ruled session-075, TD#159). Each
  // entry carries nos, the entry below it. A push writes the current
  // TOSR into the new entry's nos; a pop that does not only decrement
  // a recursion count sets TOSR to the popped entry's nos. Before
  // BP-120 a pop moved TOSR to TOSR-1, which after a pop then a push
  // is the slot just popped (TOSW only advances), so the correct path
  // mispredicted: f calls g, g returns, f calls h, h returns, and f's
  // return was predicted to g's return address. The working top
  // carries its nos so a same-cycle pop after a push (IC-RAS-04)
  // follows the link before the array holds it.
  //
  // Three primitives act on the working state, each at most one array
  // write (ras_decisions.md 1, the repair label semantics):
  //   st_retract  remove the top: decrement its recursion count in
  //               place, or move TOSR to the top's nos and reload the
  //               top. The p2 pop, an undo-push and a missed pop.
  //   st_restore  set TOSR to the value it held before the slot's p2
  //               operation, no write. An undo-pop. Before BP-120 this
  //               was st_reexpose, TOSR + 1, which is the pre-pop TOSR
  //               only when the popped entry sat one slot above the
  //               entry below it.
  //   st_push     allocate the fall-through at the frontier with nos =
  //               TOSR, or, with recursion allowed and the top equal to
  //               it, increment the top's count. The p2 push and a
  //               missed push (no recursion, as before BP-119).
  // RETURN_CALL is st_retract then st_push in one slot (RAS-DS1, pop
  // first). Before BP-119 3'b111 was a no-op here and at commit
  // (TD-DCD-2).
  //
  // THE DEPTH (A1, BP-152). The working state carries dsp. Each
  // operation moves it by its logical effect, not by what the stack
  // did: a push adds one whether it allocated, matched a count or met
  // a saturated one; a pop takes one whether it read the stack or the
  // fallback, valid or not. A repair reverses or applies the same.
  //
  // THE KILL (B1, BP-152). st_push allocating index a sets kl for every
  // other entry whose link names a; the sequential block makes those
  // entries bottom. The scan records each allocation (al_v, al_n) so a
  // second allocation in the same scan reads the links as they stand.
  //
  // THE BOTTOM (BP-138, D2). Empty is TOSR == BOS, and a commit moves
  // BOS to the committing block's post-op TOSR. Before BP-138 nothing
  // moved TOSR with it, so a commit could leave TOSR != BOS on a slot no
  // push on the chain wrote (12.5 PO7). fd07: a call pushes X (link
  // to BOS), its return pops X back to BOS (empty), then the call
  // commits and BOS becomes X; TOSR, the old BOS, read non-empty, and
  // the next return popped that slot, the never-written sentinel, and
  // predicted 0x0. Four rules keep TOSR == BOS exactly when the stack
  // is empty:
  //   - a push onto an empty stack, or the sentinel skip, marks its
  //     entry bottom (spec_bot); the pop that removes a bottom entry
  //     sets TOSR to BOS as it is then. The link still names the BOS of
  //     the push (3.2), which is the same slot while BOS has not moved.
  //   - a commit that moves BOS while TOSR == BOS moves TOSR with it
  //     (the sequential block below).
  //   - a RETURN commit whose snapshot shows the stack empty after its
  //     block (snapshot TOSR == snapshot BOS) leaves BOS where it is
  //     (c_bos; ras_decisions.md 12.11 CO5). Built by BP-140; final by
  //     Jeff's ruling, session-084 (TD#189 closed). That snapshot TOSR
  //     is the BOS of the cycle the return popped a bottom entry, an
  //     index the commits of the older blocks have since moved BOS off,
  //     so the allocation may have reused it (the sentinel skip protects
  //     only the current BOS). Moving BOS back to it puts BOS on a slot
  //     a younger push holds, and TOSR == BOS then reads empty over that
  //     entry (tb_ras TC-44; BP-143 Problem 5). The current BOS is the
  //     entry that return popped, committed by its call, so the stack
  //     it leaves is empty there.
  //   - an undo of an operation that began on an empty stack restores
  //     TOSR to BOS as it is at the undo (p3_pre_empty_q).
  // A push onto a non-empty stack links to TOSR as before. The entries
  // below it are pushes of older blocks, which commit first: when the
  // last of them commits BOS is that entry, so the pop that reaches it
  // meets TOSR == BOS.
  // -----------------------------------------------------------------
  typedef struct packed {
    logic [RAS_PTR_BITS-1:0]   tosr;
    logic [RAS_PTR_BITS-1:0]   tosw;
    // The BOS the working state is judged against: the flop in the
    // scan, the snapshot's in the restore scan (BP-152).
    logic [RAS_PTR_BITS-1:0]   bos;
    logic [RAS_DEPTH_BITS-1:0] dsp;      // A1
    logic [RAS_TAG_BITS-1:0]   ttag;     // B1: generation at TOSR
    logic [VA_WIDTH-1:0]       top_addr;
    logic [RAS_RCTR_WIDTH-1:0] top_rctr;
    logic [RAS_RCTR_WIDTH-1:0] top_ncnt;   // BP-153: spec_ncnt at TOSR
    logic [RAS_PTR_BITS-1:0]   top_nos;
    logic                      top_bot;
    logic                      valid;
    // The array write the last primitive made, if any, and whether it
    // allocated (BP-152: an allocation advances the generation).
    logic                      we;
    logic                      wal;
    logic [RAS_PTR_BITS-1:0]   waddr;
    logic [VA_WIDTH-1:0]       wdata_a;
    logic [RAS_RCTR_WIDTH-1:0] wdata_r;
    logic [RAS_PTR_BITS-1:0]   wdata_n;
    logic                      wdata_b;
    logic [RAS_RCTR_WIDTH-1:0] wdata_c;    // BP-153: spec_ncnt, with wal
    // The recursion counts this scan has written so far, by index
    // (BP-142, RP11). The array holds them only after the edge, so a
    // later step of the same scan that reloads an entry reads them
    // here. Before BP-142 the undo of a whole RETURN_CALL decremented
    // the count of the entry below the restored top, and a p2 pop in
    // the same cycle that followed the link to that entry read the old
    // count from the array (tb_ras TC-62).
    logic [RAS_SPEC_ENTRIES-1:0]                     cw_v;
    logic [RAS_SPEC_ENTRIES-1:0][RAS_RCTR_WIDTH-1:0] cw_r;
    // B1 (BP-152): the indices this scan allocated, with the links it
    // wrote there, and the entries whose link it killed.
    logic [RAS_SPEC_ENTRIES-1:0]                     al_v;
    logic [RAS_SPEC_ENTRIES-1:0][RAS_PTR_BITS-1:0]   al_n;
    logic [RAS_SPEC_ENTRIES-1:0][RAS_RCTR_WIDTH-1:0] al_c;   // BP-153
    logic [RAS_SPEC_ENTRIES-1:0]                     kl;
  } ras_ws_t;

  // The generation of index i as this scan leaves it: one more than the
  // array's when the scan allocated it (at most one allocation per
  // index per scan: four allocations at most, fewer than a lap).
  function automatic logic [RAS_TAG_BITS-1:0] f_gen(
      input ras_ws_t w, input logic [RAS_PTR_BITS-1:0] i);
    return w.al_v[i] ? (spec_gen[i] + TAG_ONE) : spec_gen[i];
  endfunction

  // Reload the working top from the array at the working TOSR. TOSR
  // equal to BOS is empty.
  function automatic ras_ws_t st_load(input ras_ws_t w);
    ras_ws_t r;
    r = w;
    if (r.tosr != r.bos) begin
      r.top_addr = spec_ret_addr[r.tosr];
      r.top_rctr = r.cw_v[r.tosr] ? r.cw_r[r.tosr] : spec_rctr[r.tosr];
      r.top_ncnt = r.al_v[r.tosr] ? r.al_c[r.tosr] : spec_ncnt[r.tosr];
      r.top_nos  = spec_nos[r.tosr];
      r.top_bot  = spec_bot[r.tosr] | r.kl[r.tosr];
      r.ttag     = f_gen(r, r.tosr);
      r.valid    = 1'b1;
    end else begin
      r.top_addr = '0;
      r.top_rctr = '0;
      r.top_ncnt = '0;
      r.top_nos  = '0;
      r.top_bot  = 1'b0;
      r.ttag     = '0;
      r.valid    = 1'b0;
    end
    return r;
  endfunction

  // Note the count of the array write the last primitive made, so a
  // later reload in the same scan sees it (cw_v / cw_r, BP-142).
  function automatic ras_ws_t st_note(input ras_ws_t w);
    ras_ws_t r;
    r = w;
    if (r.we) begin
      r.cw_v[r.waddr] = 1'b1;
      r.cw_r[r.waddr] = r.wdata_r;
    end
    return r;
  endfunction

  // B1: index a is being allocated. Every other entry whose link names
  // a now names a reused entry: kill its link (it becomes bottom). The
  // link of an entry this scan allocated is the one it wrote. The new
  // entry's own link is wdata_n, recorded here.
  function automatic ras_ws_t st_kill(input ras_ws_t w,
                                      input logic [RAS_PTR_BITS-1:0] a);
    ras_ws_t                 r;
    logic [RAS_PTR_BITS-1:0] nj;
    r = w;
    for (int j = 0; j < RAS_SPEC_ENTRIES; j++) begin
      nj = r.al_v[j] ? r.al_n[j] : spec_nos[j];
      if ((RAS_PTR_BITS'(j) != a) && (nj == a)) r.kl[j] = 1'b1;
    end
    r.kl[a]   = 1'b0;
    r.al_v[a] = 1'b1;
    r.al_n[a] = r.wdata_n;
    r.al_c[a] = r.wdata_c;
    return r;
  endfunction

  function automatic ras_ws_t st_retract(input ras_ws_t w);
    ras_ws_t                   r;
    logic [RAS_RCTR_WIDTH-1:0] nc;
    logic                      fol;
    r     = w;
    r.we  = 1'b0;
    r.wal = 1'b0;
    if (r.valid) begin
      if (r.top_rctr != '0) begin
        // Recursion outstanding: decrement the count, TOSR holds.
        r.we       = 1'b1;
        r.waddr    = r.tosr;
        r.wdata_a  = r.top_addr;
        r.wdata_r  = r.top_rctr - RCTR_ONE;
        r.wdata_n  = r.top_nos;
        r.wdata_b  = r.top_bot;
        r.top_rctr = r.wdata_r;
      end else begin
        // TOSR follows the link to the entry below, no data
        // overwritten. Before BP-120: TOSR - 1. A bottom entry goes to
        // BOS as it is now, empty (BP-138), and so does one whose link
        // was killed (B1).
        nc     = r.top_ncnt;
        fol    = ~r.top_bot;
        r.tosr = r.top_bot ? r.bos : r.top_nos;
        r      = st_load(r);
        // BP-153: the link followed to a live entry: its count is the
        // one recorded at the popped entry's allocation (spec_ncnt),
        // written back when the array holds another (a wrong-path change
        // in place). One write, the port a decrement would use.
        if (fol && r.valid && (r.top_rctr != nc)) begin
          r.we       = 1'b1;
          r.waddr    = r.tosr;
          r.wdata_a  = r.top_addr;
          r.wdata_r  = nc;
          r.wdata_n  = r.top_nos;
          r.wdata_b  = r.top_bot;
          r.top_rctr = nc;
        end
      end
    end
    r = st_note(r);
    return r;
  endfunction

  // The popped entry is still resident (a pop does not overwrite the
  // array), so it is re-exposed by restoring the TOSR the pop started
  // from. No array write, TOSW unchanged (stays monotonic). A pop that
  // only decremented a recursion count held TOSR, so this restores the
  // same TOSR; the count is put back by st_rctr_adj (BP-133, TD #78;
  // before BP-133 it stayed decremented). A pop that began on an empty
  // stack restores BOS as it is now (BP-138), and so does one whose
  // pre-op entry has been reallocated since (B1, the generation).
  function automatic ras_ws_t st_restore(
      input ras_ws_t w, input logic [RAS_PTR_BITS-1:0] pre_tosr,
      input logic [RAS_TAG_BITS-1:0] pre_tag, input logic pre_empty);
    ras_ws_t r;
    r      = w;
    r.we   = 1'b0;
    r.wal  = 1'b0;
    r.tosr = (pre_empty || (f_gen(r, pre_tosr) != pre_tag)) ? r.bos
                                                            : pre_tosr;
    r      = st_load(r);
    return r;
  endfunction

  // Step the recursion count of the entry at ptr by one, up (inc) or
  // down, with one array write. The undo of a count the p2 operation
  // changed (BP-133, TD #78). The working top is used when ptr is the
  // working TOSR, so a count the same pass changed is seen; any other
  // entry is read from the array, or from cw_r when this scan already
  // wrote its count (BP-142). No step past 0 or RCTR_MAX.
  function automatic ras_ws_t st_rctr_adj(
      input ras_ws_t w, input logic [RAS_PTR_BITS-1:0] ptr,
      input logic inc);
    ras_ws_t                   r;
    logic [RAS_RCTR_WIDTH-1:0] c;
    r     = w;
    r.we  = 1'b0;
    r.wal = 1'b0;
    if (r.valid && (ptr == r.tosr)) begin
      c         = r.top_rctr;
      r.wdata_a = r.top_addr;
      r.wdata_n = r.top_nos;
      r.wdata_b = r.top_bot;
    end else begin
      c         = r.cw_v[ptr] ? r.cw_r[ptr] : spec_rctr[ptr];
      r.wdata_a = spec_ret_addr[ptr];
      r.wdata_n = spec_nos[ptr];
      r.wdata_b = spec_bot[ptr] | r.kl[ptr];
    end
    if (inc ? (c != RCTR_MAX) : (c != '0)) begin
      r.we      = 1'b1;
      r.waddr   = ptr;
      r.wdata_r = inc ? (c + RCTR_ONE) : (c - RCTR_ONE);
      if (r.valid && (ptr == r.tosr))
        r.top_rctr = r.wdata_r;
    end
    r = st_note(r);
    return r;
  endfunction

  function automatic ras_ws_t st_push(input ras_ws_t             w,
                                      input logic [VA_WIDTH-1:0] ft,
                                      input logic                recur);
    ras_ws_t                 r;
    logic [RAS_PTR_BITS-1:0] alloc;
    logic                    skip;
    logic                    self;
    r     = w;
    r.we  = 1'b1;
    r.wal = 1'b0;
    if (recur & r.valid & (ft == r.top_addr)) begin
      // Recursion: increment rctr at TOSR, saturate, no advance.
      r.waddr    = r.tosr;
      r.wdata_a  = r.top_addr;
      r.wdata_r  = (r.top_rctr == RCTR_MAX) ? RCTR_MAX
                                            : r.top_rctr + RCTR_ONE;
      r.wdata_n  = r.top_nos;
      r.wdata_b  = r.top_bot;
      r.top_rctr = r.wdata_r;
    end else begin
      // Allocate at TOSW, TOSR = alloc, TOSW advances. The BOS index is
      // a sentinel: when the write pointer would land on BOS (only at
      // cold start after reset, or on a full circular wrap), allocate
      // at BOS+1 instead, so a single live entry stays distinct from
      // empty (TOSR == BOS). TOSW stays monotonic so popped entries
      // remain intact for pointer-only mispredict restore.
      //
      // The new entry links to the current TOSR, BOS when the stack is
      // empty. On the sentinel skip it links to BOS instead: the skip
      // is the circular wrap, the slots it reuses may be named by the
      // links of older entries, and linking to BOS keeps the overflow
      // effect of 3.2 -- one reachable entry, then the commit-stack
      // fallback -- rather than a chain into overwritten slots.
      //
      // Both cases, the empty stack and the skip, link to BOS and mark
      // the entry bottom (BP-138): its pop returns to BOS as it is then.
      // So does an allocation that lands on the TOSR entry itself (B1,
      // BP-152): TOSR below BOS, the allocator round to it. The entry
      // being overwritten is the one the link would name, so the new
      // entry has nothing below it; before BP-152 it linked to itself.
      skip       = (r.tosw == r.bos);
      alloc      = skip ? (r.tosw + PTR_ONE) : r.tosw;
      self       = r.valid & (alloc == r.tosr);
      r.wal      = 1'b1;
      r.waddr    = alloc;
      r.wdata_a  = ft;
      r.wdata_r  = '0;
      r.wdata_n  = (skip | self) ? r.bos : r.tosr;
      r.wdata_b  = skip | self | ~r.valid;
      // BP-153: the count of the entry the link names, 0 for a bottom
      // entry (its pop goes to BOS and reads no count).
      r.wdata_c  = r.wdata_b ? '0 : r.top_rctr;
      r          = st_kill(r, alloc);
      r.tosr     = alloc;
      r.tosw     = alloc + PTR_ONE;
      r.top_addr = ft;
      r.top_rctr = '0;
      r.top_ncnt = r.wdata_c;
      r.top_nos  = r.wdata_n;
      r.top_bot  = r.wdata_b;
      r.ttag     = f_gen(r, alloc);
      r.valid    = 1'b1;
    end
    r = st_note(r);
    return r;
  endfunction

  logic [RAS_PTR_BITS-1:0]   nxt_tosr;
  logic [RAS_PTR_BITS-1:0]   nxt_tosw;
  logic [RAS_DEPTH_BITS-1:0] nxt_dsp;
  logic [RAS_SPEC_ENTRIES-1:0] nxt_kl;
  // The state after the repair pass alone, for a cycle whose p2 pass
  // is dropped (ras_p2_keep low).
  logic [RAS_PTR_BITS-1:0]   rep_tosr;
  logic [RAS_PTR_BITS-1:0]   rep_tosw;
  logic [RAS_DEPTH_BITS-1:0] rep_dsp;
  logic [RAS_SPEC_ENTRIES-1:0] rep_kl;

  logic                      sp_we      [0:RAS_WR_PORTS-1];
  logic                      sp_al      [0:RAS_WR_PORTS-1];
  logic [RAS_PTR_BITS-1:0]   sp_waddr   [0:RAS_WR_PORTS-1];
  logic [VA_WIDTH-1:0]       sp_wdata_a [0:RAS_WR_PORTS-1];
  logic [RAS_RCTR_WIDTH-1:0] sp_wdata_r [0:RAS_WR_PORTS-1];
  logic [RAS_PTR_BITS-1:0]   sp_wdata_n [0:RAS_WR_PORTS-1];
  logic                      sp_wdata_b [0:RAS_WR_PORTS-1];
  logic [RAS_RCTR_WIDTH-1:0] sp_wdata_c [0:RAS_WR_PORTS-1];   // BP-153

  logic [1:0]                p2_op       [0:NUM_PRED_SLOTS-1];
  logic [RAS_PTR_BITS-1:0]   p2_pre_tosr [0:NUM_PRED_SLOTS-1];
  logic [RAS_TAG_BITS-1:0]   p2_pre_tag  [0:NUM_PRED_SLOTS-1];
  logic                      p2_pre_empty[0:NUM_PRED_SLOTS-1];
  logic                      p2_pop_dec  [0:NUM_PRED_SLOTS-1];
  logic                      p2_push_inc [0:NUM_PRED_SLOTS-1];
  logic                      p2_push_sat [0:NUM_PRED_SLOTS-1];
  logic [RAS_PTR_BITS-1:0]   p2_inc_ptr  [0:NUM_PRED_SLOTS-1];
  // The fallback a p2 pop on an empty stack read (A1): the commit-stack
  // index and n. Observation only (perf ras_class.h).
  logic [RAS_COMMIT_PTR_BITS-1:0] p2_fb_idx [0:NUM_PRED_SLOTS-1];
  // BP-153 (TD#149): the repair pass changed the stack for the p3 block.
  logic                      rep_any;
  assign ras_rep_val = rep_any & ~ras_restore_val;

  always_comb begin : scan
    ras_ws_t w;
    ras_fb_t fb;
    int      n;       // writes made so far by this slot in this pass
    int      pi;      // write port index
    logic    s3_pop;
    logic    s3_push;
    logic    q_pop;
    logic    q_push;
    logic    is_pop;
    logic    is_push;
    // BP-153: the pop record of this cycle's p2 block (one pop per block,
    // FE-11), carried into the snapshot of the pop's slot and every slot
    // after it.
    logic [RAS_PMODE_BITS-1:0] pp_mode;
    logic [RAS_PTR_BITS-1:0]   pp_tosr;
    logic [RAS_TAG_BITS-1:0]   pp_tag;
    logic                      pp_push;   // BP-153: the block pushed
    // BP-153 (TD#149): the p3 block's record as the repair leaves it.
    logic                      rp_any;
    logic                      rp_push;
    logic [RAS_PMODE_BITS-1:0] rp_mode;
    logic [RAS_PTR_BITS-1:0]   rp_tosr;
    logic [RAS_TAG_BITS-1:0]   rp_tag;

    // Defaults for every variable the loops assign, so no control path
    // leaves one unassigned.
    rp_any   = 1'b0;
    rp_push  = 1'b0;
    rp_mode  = RAS_POP_NONE;
    rp_tosr  = '0;
    rp_tag   = '0;
    pp_push  = 1'b0;
    pp_mode  = RAS_POP_NONE;
    pp_tosr  = '0;
    pp_tag   = '0;
    n        = 0;
    pi       = 0;
    s3_pop   = 1'b0;
    s3_push  = 1'b0;
    q_pop    = 1'b0;
    q_push   = 1'b0;
    is_pop   = 1'b0;
    is_push  = 1'b0;
    fb       = '0;
    nxt_tosr = tosr;
    nxt_tosw = tosw;
    nxt_dsp  = dsp;
    nxt_kl   = '0;
    rep_tosr = tosr;
    rep_tosw = tosw;
    rep_dsp  = dsp;
    rep_kl   = '0;

    // Working state from the FF pointers.
    w      = '0;
    w.tosr = tosr;
    w.tosw = tosw;
    w.bos  = bos;
    w.dsp  = dsp;
    w      = st_load(w);

    for (int p = 0; p < RAS_WR_PORTS; p++) begin
      sp_we[p]      = 1'b0;
      sp_al[p]      = 1'b0;
      sp_waddr[p]   = '0;
      sp_wdata_a[p] = '0;
      sp_wdata_r[p] = '0;
      sp_wdata_n[p] = '0;
      sp_wdata_b[p] = 1'b0;
      sp_wdata_c[p] = '0;
    end
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      ras_pop_addr_p2[s]  = '0;
      ras_pop_valid_p2[s] = 1'b0;
      ras_peek_addr_p2[s]  = '0;
      ras_peek_valid_p2[s] = 1'b0;
      ras_snapshot_p2[s]  = '0;
      p2_op[s]            = OP_NONE;
      p2_pre_tosr[s]      = '0;
      p2_pre_tag[s]       = '0;
      p2_pre_empty[s]     = 1'b0;
      p2_pop_dec[s]       = 1'b0;
      p2_push_inc[s]      = 1'b0;
      p2_push_sat[s]      = 1'b0;
      p2_inc_ptr[s]       = '0;
      p2_fb_idx[s]        = '0;
    end

    // -------- p3 repair pass (corrects the prior cycle's op) -------
    // Repair table (IC-RAS-11), applied per component of the op: a
    // missed pop is applied before a missed push (RAS-DS1), each with
    // the primitive the table names. push->pop and pop->push within
    // one p2/p3 pair cannot occur (p3 is the registered p2 type), so
    // at most two of the steps below write.
    //
    // A WHOLE RETURN_CALL TO UNDO (p2 popped then pushed, p3 says
    // neither) restores TOSR to its value before the operation,
    // registered with the op. It is exact for the pointers because the
    // RETURN_CALL is the only RAS operation in its block (FE-11): a
    // taken branch ends the block. A recursion count the pop
    // decremented is incremented back, and a count the push
    // incremented is decremented back; when both are the same entry
    // (the pop held TOSR and the push matched it) they cancel (BP-133,
    // TD #78; before BP-133 neither count was restored). An undo-pop
    // alone restores the same registered TOSR (st_restore) and puts
    // back a count its pop decremented; a missed pop and an undo-push
    // follow the link or decrement a count (st_retract). An undo-push
    // of a push that met a saturated count does nothing, as the push
    // did nothing (BP-134).
    //
    // The depth (A1) is moved by each component: an undo-push takes
    // one, an undo-pop adds one, a missed pop takes one, a missed push
    // adds one, the undo of a whole RETURN_CALL none.
    //
    // A RETURN_CALL PAIRED AT THE OTHER STAGE WITH A PLAIN PUSH OR POP
    // is not specified (ras_decisions.md 1). It takes the per-component
    // steps below. p2 RETURN_CALL / p3 pop undoes the push (the link
    // returns TOSR to the post-pop top); p2 pop / p3 RETURN_CALL
    // applies the missed push. Both give the p3 result. p2 RETURN_CALL
    // / p3 push undoes the pop by restoring the pre-op TOSR, which also
    // drops the push, and p2 push / p3 RETURN_CALL applies the missed
    // pop to the pushed entry; neither gives the p3 result. Reported
    // in BP-120. In bp_cluster the p3 type is the registered p2 type,
    // so no pairing of differing ops reaches this pass there.
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      s3_pop  = ras_pred_val_p3[s] &
                ((ras_br_type_p3[s] == RETURN) |
                 (ras_br_type_p3[s] == RETURN_CALL));
      s3_push = ras_pred_val_p3[s] &
                ((ras_br_type_p3[s] == DIRECT_CALL)   |
                 (ras_br_type_p3[s] == INDIRECT_CALL) |
                 (ras_br_type_p3[s] == RETURN_CALL));
      q_pop   = (p3_op_q[s] == OP_POP)  | (p3_op_q[s] == OP_POPPUSH);
      q_push  = (p3_op_q[s] == OP_PUSH) | (p3_op_q[s] == OP_POPPUSH);
      n       = 0;
      // BP-153 (TD#149): the p3 block's operation record as the p3 view
      // leaves it. A pop kept from p2 keeps its registered record; a
      // missed pop's is taken below, from the state it finds.
      rp_any  = rp_any | (q_pop != s3_pop) | (q_push != s3_push);
      rp_push = rp_push | s3_push;
      if (q_pop & s3_pop) begin
        rp_tosr = p3_pre_tosr_q[s];
        rp_tag  = p3_pre_tag_q[s];
        rp_mode = p3_pre_empty_q[s] ? RAS_POP_EMPTY :
                  p3_pop_dec_q[s]   ? RAS_POP_DEC   : RAS_POP_LINK;
      end

      if (q_pop & q_push & ~s3_pop & ~s3_push) begin
        w = st_restore(w, p3_pre_tosr_q[s], p3_pre_tag_q[s],
                       p3_pre_empty_q[s]);
        if (p3_pop_dec_q[s] != p3_push_inc_q[s]) begin
          w = p3_pop_dec_q[s] ? st_rctr_adj(w, p3_pre_tosr_q[s], 1'b1)
                              : st_rctr_adj(w, p3_inc_ptr_q[s], 1'b0);
          if (w.we) begin
            pi             = (s * RAS_WR_PER_SLOT) + n;
            sp_we[pi]      = 1'b1;
            sp_waddr[pi]   = w.waddr;
            sp_wdata_a[pi] = w.wdata_a;
            sp_wdata_r[pi] = w.wdata_r;
            sp_wdata_n[pi] = w.wdata_n;
            sp_wdata_b[pi] = w.wdata_b;
          end
        end
      end else begin
        // Undo a push the p3 type does not have. Skipped when the push
        // met a saturated count and changed nothing: st_retract would
        // decrement a count the push did not raise (BP-134). The depth
        // is taken back either way.
        if (q_push & ~s3_push) begin
          w.dsp = w.dsp - DEP_ONE;
          if (~p3_push_sat_q[s]) begin
            w = st_retract(w);
            if (w.we) begin
              pi             = (s * RAS_WR_PER_SLOT) + n;
              sp_we[pi]      = 1'b1;
              sp_waddr[pi]   = w.waddr;
              sp_wdata_a[pi] = w.wdata_a;
              sp_wdata_r[pi] = w.wdata_r;
              sp_wdata_n[pi] = w.wdata_n;
              sp_wdata_b[pi] = w.wdata_b;
              n              = n + 1;
            end
          end
        end
        // Undo a pop the p3 type does not have, or apply a missed one.
        if (q_pop & ~s3_pop) begin
          w.dsp = w.dsp + DEP_ONE;
          w = st_restore(w, p3_pre_tosr_q[s], p3_pre_tag_q[s],
                         p3_pre_empty_q[s]);
          if (p3_pop_dec_q[s]) begin
            w = st_rctr_adj(w, p3_pre_tosr_q[s], 1'b1);
            if (w.we && (n < RAS_WR_PER_SLOT)) begin
              pi             = (s * RAS_WR_PER_SLOT) + n;
              sp_we[pi]      = 1'b1;
              sp_waddr[pi]   = w.waddr;
              sp_wdata_a[pi] = w.wdata_a;
              sp_wdata_r[pi] = w.wdata_r;
              sp_wdata_n[pi] = w.wdata_n;
              sp_wdata_b[pi] = w.wdata_b;
              n              = n + 1;
            end
          end
        end else if (~q_pop & s3_pop) begin
          rp_tosr = w.tosr;                            // BP-153
          rp_tag  = w.valid ? w.ttag : '0;
          rp_mode = ~w.valid             ? RAS_POP_EMPTY :
                    (w.top_rctr != '0)   ? RAS_POP_DEC   : RAS_POP_LINK;
          w.dsp = w.dsp - DEP_ONE;
          w = st_retract(w);
          if (w.we && (n < RAS_WR_PER_SLOT)) begin
            pi             = (s * RAS_WR_PER_SLOT) + n;
            sp_we[pi]      = 1'b1;
            sp_waddr[pi]   = w.waddr;
            sp_wdata_a[pi] = w.wdata_a;
            sp_wdata_r[pi] = w.wdata_r;
            sp_wdata_n[pi] = w.wdata_n;
            sp_wdata_b[pi] = w.wdata_b;
            n              = n + 1;
          end
        end
        // Apply a missed push: allocate the registered fall-through.
        if (~q_push & s3_push) begin
          w.dsp = w.dsp + DEP_ONE;
          w = st_push(w, p3_fallthr_q[s], 1'b0);
          if (n < RAS_WR_PER_SLOT) begin
            pi             = (s * RAS_WR_PER_SLOT) + n;
            sp_we[pi]      = 1'b1;
            sp_al[pi]      = w.wal;
            sp_waddr[pi]   = w.waddr;
            sp_wdata_a[pi] = w.wdata_a;
            sp_wdata_r[pi] = w.wdata_r;
            sp_wdata_n[pi] = w.wdata_n;
            sp_wdata_b[pi] = w.wdata_b;
            sp_wdata_c[pi] = w.wdata_c;
          end
        end
      end
    end

    rep_tosr = w.tosr;
    rep_tosw = w.tosw;
    rep_dsp  = w.dsp;
    rep_kl   = w.kl;

    // BP-153 (TD#149): the p3 block's corrected snapshot, the state the
    // repair pass leaves (before this cycle's p2 block operates). A
    // restore this cycle drops the repair, and so drops this: the gate is
    // outside this block (rep_any), so the scan reads no restore input
    // (bp_cluster forms its restore from its own redirects, which this
    // block's p2 outputs feed).
    rep_any                = rp_any;
    ras_rep_snapshot       = '0;
    ras_rep_snapshot.tosr  = w.tosr;
    ras_rep_snapshot.tosw  = w.tosw;
    ras_rep_snapshot.bos   = bos;
    ras_rep_snapshot.rctr  = w.valid ? w.top_rctr : '0;
    ras_rep_snapshot.dep   = w.dsp;
    ras_rep_snapshot.tag   = w.valid ? w.ttag : '0;
    ras_rep_snapshot.push  = rp_push;
    ras_rep_snapshot.pmode = rp_mode;
    ras_rep_snapshot.ptosr = rp_tosr;
    ras_rep_snapshot.ptag  = rp_tag;

    // -------- p2 pass (this cycle's prediction) --------------------
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      is_pop  = ras_pred_val_p2[s] &
                ((ras_br_type_p2[s] == RETURN) |
                 (ras_br_type_p2[s] == RETURN_CALL));
      is_push = ras_pred_val_p2[s] &
                ((ras_br_type_p2[s] == DIRECT_CALL)   |
                 (ras_br_type_p2[s] == INDIRECT_CALL) |
                 (ras_br_type_p2[s] == RETURN_CALL));
      p2_op[s]       = is_pop ? (is_push ? OP_POPPUSH : OP_POP)
                              : (is_push ? OP_PUSH    : OP_NONE);
      p2_pre_tosr[s] = w.tosr;
      p2_pre_tag[s]  = w.ttag;
      p2_pre_empty[s] = ~w.valid;
      n              = 0;
      // BP-153: the peek, the pop this slot would make (PO1 to PO6).
      if (w.valid) begin
        ras_peek_addr_p2[s]  = w.top_addr;
        ras_peek_valid_p2[s] = 1'b1;
      end else begin
        fb                   = f_fb(w.dsp);
        ras_peek_addr_p2[s]  = fb.addr;
        ras_peek_valid_p2[s] = fb.valid;
      end

      // The pop first (RAS-DS1). It supplies the predicted target.
      if (is_pop) begin
        // BP-153: the pop record, from the state the pop finds.
        pp_tosr = w.tosr;
        pp_tag  = w.valid ? w.ttag : '0;
        pp_mode = ~w.valid                ? RAS_POP_EMPTY :
                  (w.top_rctr != '0)      ? RAS_POP_DEC   : RAS_POP_LINK;
        if (~w.valid) begin
          // Empty speculative stack: the commit-stack frame at the
          // speculative depth (A1), not consumed. Valid only while the
          // commit stack still holds it.
          fb                  = f_fb(w.dsp);
          ras_pop_addr_p2[s]  = fb.addr;
          ras_pop_valid_p2[s] = fb.valid;
          p2_fb_idx[s]        = fb.idx;
        end else begin
          ras_pop_addr_p2[s]  = w.top_addr;
          ras_pop_valid_p2[s] = 1'b1;
          p2_pop_dec[s]       = (w.top_rctr != '0);
          w = st_retract(w);
          if (w.we) begin
            pi             = ((NUM_PRED_SLOTS + s) * RAS_WR_PER_SLOT) + n;
            sp_we[pi]      = 1'b1;
            sp_waddr[pi]   = w.waddr;
            sp_wdata_a[pi] = w.wdata_a;
            sp_wdata_r[pi] = w.wdata_r;
            sp_wdata_n[pi] = w.wdata_n;
            sp_wdata_b[pi] = w.wdata_b;
            n              = n + 1;
          end
        end
        w.dsp = w.dsp - DEP_ONE;
      end

      // Then the push, applied to the state the pop left.
      if (is_push) begin
        // The recursion arm of st_push, when it moves the count.
        p2_push_inc[s] = w.valid & (ras_fall_through_p2[s] == w.top_addr)
                       & (w.top_rctr != RCTR_MAX);
        // The recursion arm at a saturated count: nothing moves.
        p2_push_sat[s] = w.valid & (ras_fall_through_p2[s] == w.top_addr)
                       & (w.top_rctr == RCTR_MAX);
        p2_inc_ptr[s]  = w.tosr;
        pp_push        = 1'b1;                         // BP-153
        w = st_push(w, ras_fall_through_p2[s], 1'b1);
        w.dsp          = w.dsp + DEP_ONE;
        pi             = ((NUM_PRED_SLOTS + s) * RAS_WR_PER_SLOT) + n;
        sp_we[pi]      = 1'b1;
        sp_al[pi]      = w.wal;
        sp_waddr[pi]   = w.waddr;
        sp_wdata_a[pi] = w.wdata_a;
        sp_wdata_r[pi] = w.wdata_r;
        sp_wdata_n[pi] = w.wdata_n;
        sp_wdata_b[pi] = w.wdata_b;
        sp_wdata_c[pi] = w.wdata_c;
      end

      // Post-op snapshot for this slot (BOS unchanged across p2), with
      // the count of the entry at its TOSR, 0 when the stack is empty
      // (TD#194 option A, ras_decisions.md 4.1; BP-142), the depth and
      // the generation of the entry at TOSR (BP-152). A restore writes
      // the count back.
      ras_snapshot_p2[s].tosr = w.tosr;
      ras_snapshot_p2[s].tosw = w.tosw;
      ras_snapshot_p2[s].bos  = bos;
      ras_snapshot_p2[s].rctr = w.valid ? w.top_rctr : '0;
      ras_snapshot_p2[s].dep  = w.dsp;
      ras_snapshot_p2[s].tag  = w.valid ? w.ttag : '0;
      ras_snapshot_p2[s].push  = pp_push;               // BP-153
      ras_snapshot_p2[s].pmode = pp_mode;
      ras_snapshot_p2[s].ptosr = pp_tosr;
      ras_snapshot_p2[s].ptag  = pp_tag;
    end

    nxt_tosr = w.tosr;
    nxt_tosw = w.tosw;
    nxt_dsp  = w.dsp;
    nxt_kl   = w.kl;
  end

  // -----------------------------------------------------------------
  // THE RESTORE (IC-RAS-09, ras_decisions.md 4.3; BP-152). The state a
  // restore loads, and the C1 operation applied on top of it.
  //   - TOSR, TOSW, BOS and the depth from the snapshot, except that a
  //     snapshot whose TOSR entry has been reallocated since (its
  //     generation is not the snapshot's tag) loads an empty stack,
  //     TOSR = BOS (B1).
  //   - the count of the snapshot's top written back (RE6), only for a
  //     TOSR the restore keeps.
  //   - with ras_rs_undo, the restored block's own push retracted first
  //     (its snapshot is post-op, 4.2; the redirect leaves the block
  //     before the call).
  //   - with ras_pd_val, the predecode operation by the p2 rules: the
  //     pop (PO1 to PO6, the A1 fallback), then the push (PU1 to PU7,
  //     recursion allowed). A pop on an empty stack reads nothing: the
  //     predecode redirect's own target is predecode's (ftq_ifu W3).
  // Reads the snapshot input and the arrays (FF outputs).
  // -----------------------------------------------------------------
  logic                      rs_keep_top;
  logic [RAS_PTR_BITS-1:0]   rs_tosr;
  logic [RAS_PTR_BITS-1:0]   rs_tosw;
  logic [RAS_DEPTH_BITS-1:0] rs_dsp;
  logic [RAS_SPEC_ENTRIES-1:0] rs_kl;
  logic                      rs_we      [0:RS_WR_PORTS-1];
  logic                      rs_al      [0:RS_WR_PORTS-1];
  logic [RAS_PTR_BITS-1:0]   rs_waddr   [0:RS_WR_PORTS-1];
  logic [VA_WIDTH-1:0]       rs_wdata_a [0:RS_WR_PORTS-1];
  logic [RAS_RCTR_WIDTH-1:0] rs_wdata_r [0:RS_WR_PORTS-1];
  logic [RAS_PTR_BITS-1:0]   rs_wdata_n [0:RS_WR_PORTS-1];
  logic                      rs_wdata_b [0:RS_WR_PORTS-1];
  logic [RAS_RCTR_WIDTH-1:0] rs_wdata_c [0:RS_WR_PORTS-1];   // BP-153

  always_comb begin : restore_scan
    ras_ws_t w;
    logic    pd_pop;
    logic    pd_push;
    logic [RAS_PMODE_BITS-1:0] pd_pmode;
    logic [RAS_PTR_BITS-1:0]   pd_ptosr;
    logic [RAS_TAG_BITS-1:0]   pd_ptag;
    for (int p = 0; p < RS_WR_PORTS; p++) begin
      rs_we[p]      = 1'b0;
      rs_al[p]      = 1'b0;
      rs_waddr[p]   = '0;
      rs_wdata_a[p] = '0;
      rs_wdata_r[p] = '0;
      rs_wdata_n[p] = '0;
      rs_wdata_b[p] = 1'b0;
      rs_wdata_c[p] = '0;
    end
    pd_pop  = ras_pd_val &
              ((ras_pd_br_type == RETURN) | (ras_pd_br_type == RETURN_CALL));
    pd_push = ras_pd_val &
              ((ras_pd_br_type == DIRECT_CALL)   |
               (ras_pd_br_type == INDIRECT_CALL) |
               (ras_pd_br_type == RETURN_CALL));

    rs_keep_top = (ras_restore_snapshot.tosr != ras_restore_snapshot.bos) &&
                  (spec_gen[ras_restore_snapshot.tosr] ==
                   ras_restore_snapshot.tag);
    w      = '0;
    w.bos  = ras_restore_snapshot.bos;
    w.tosw = ras_restore_snapshot.tosw;
    w.dsp  = ras_restore_snapshot.dep;
    w.tosr = rs_keep_top ? ras_restore_snapshot.tosr
                         : ras_restore_snapshot.bos;
    if (rs_keep_top) begin
      // RE6, seen by the C1 pop below as the scan sees its own counts.
      w.cw_v[ras_restore_snapshot.tosr] = 1'b1;
      w.cw_r[ras_restore_snapshot.tosr] = ras_restore_snapshot.rctr;
      rs_we[0]      = 1'b1;
      rs_waddr[0]   = ras_restore_snapshot.tosr;
      rs_wdata_r[0] = ras_restore_snapshot.rctr;
    end
    w = st_load(w);

    // The undo of the restored block's own push (ras_rs_undo): the top
    // the snapshot holds is that push, so retract it, as the p3
    // undo-push does (RP1, RP2), and take the depth back.
    if (ras_rs_undo) begin
      if (w.valid) begin
        w = st_retract(w);
        if (w.we) begin
          rs_we[RS_P_UNDO]      = 1'b1;
          rs_waddr[RS_P_UNDO]   = w.waddr;
          rs_wdata_a[RS_P_UNDO] = w.wdata_a;
          rs_wdata_r[RS_P_UNDO] = w.wdata_r;
          rs_wdata_n[RS_P_UNDO] = w.wdata_n;
          rs_wdata_b[RS_P_UNDO] = w.wdata_b;
        end
      end
      w.dsp = w.dsp - DEP_ONE;
    end
    // BP-153: the undo of the restored block's own pop (ras_rs_undo_pop),
    // from the snapshot's pop record, as the p3 undo-pop does (RP3, RP4):
    //   LINK   TOSR back to ptosr, empty if its generation moved (B1). The
    //          pop followed the link only with the count at 0, so the
    //          count is written 0 (a count the wrong path changed in place
    //          is put back, as RE6 does for the top).
    //   DEC    the count at ptosr, the restored top, incremented back.
    //   EMPTY  nothing on the stack: the depth alone.
    // The depth plus one in every case (A1).
    if (ras_rs_undo_pop && (ras_restore_snapshot.pmode != RAS_POP_NONE)) begin
      if (ras_restore_snapshot.pmode == RAS_POP_LINK) begin
        w = st_restore(w, ras_restore_snapshot.ptosr,
                       ras_restore_snapshot.ptag, 1'b0);
        if (w.valid) begin
          rs_we[RS_P_UPOP]      = 1'b1;
          rs_waddr[RS_P_UPOP]   = w.tosr;
          rs_wdata_a[RS_P_UPOP] = w.top_addr;
          rs_wdata_r[RS_P_UPOP] = '0;
          rs_wdata_n[RS_P_UPOP] = w.top_nos;
          rs_wdata_b[RS_P_UPOP] = w.top_bot;
          w.top_rctr            = '0;
          w.cw_v[w.tosr]        = 1'b1;
          w.cw_r[w.tosr]        = '0;
        end
      end else if ((ras_restore_snapshot.pmode == RAS_POP_DEC) && w.valid &&
                   (w.tosr == ras_restore_snapshot.ptosr)) begin
        w = st_rctr_adj(w, ras_restore_snapshot.ptosr, 1'b1);
        if (w.we) begin
          rs_we[RS_P_UPOP]      = 1'b1;
          rs_waddr[RS_P_UPOP]   = w.waddr;
          rs_wdata_a[RS_P_UPOP] = w.wdata_a;
          rs_wdata_r[RS_P_UPOP] = w.wdata_r;
          rs_wdata_n[RS_P_UPOP] = w.wdata_n;
          rs_wdata_b[RS_P_UPOP] = w.wdata_b;
        end
      end
      w.dsp = w.dsp + DEP_ONE;
    end
    // The pop record of the C1 pop, for ras_pd_snapshot (BP-153).
    pd_pmode = RAS_POP_NONE;
    pd_ptosr = '0;
    pd_ptag  = '0;
    if (pd_pop) begin
      pd_ptosr = w.tosr;
      pd_ptag  = w.valid ? w.ttag : '0;
      pd_pmode = ~w.valid             ? RAS_POP_EMPTY :
                 (w.top_rctr != '0)   ? RAS_POP_DEC   : RAS_POP_LINK;
    end
    if (pd_pop) begin
      if (w.valid) begin
        w = st_retract(w);
        if (w.we) begin
          rs_we[RS_P_POP]      = 1'b1;
          rs_waddr[RS_P_POP]   = w.waddr;
          rs_wdata_a[RS_P_POP] = w.wdata_a;
          rs_wdata_r[RS_P_POP] = w.wdata_r;
          rs_wdata_n[RS_P_POP] = w.wdata_n;
          rs_wdata_b[RS_P_POP] = w.wdata_b;
        end
      end
      w.dsp = w.dsp - DEP_ONE;
    end
    if (pd_push) begin
      w = st_push(w, ras_pd_ret_addr, 1'b1);
      w.dsp                 = w.dsp + DEP_ONE;
      rs_we[RS_P_PUSH]      = 1'b1;
      rs_al[RS_P_PUSH]      = w.wal;
      rs_waddr[RS_P_PUSH]   = w.waddr;
      rs_wdata_a[RS_P_PUSH] = w.wdata_a;
      rs_wdata_r[RS_P_PUSH] = w.wdata_r;
      rs_wdata_n[RS_P_PUSH] = w.wdata_n;
      rs_wdata_b[RS_P_PUSH] = w.wdata_b;
      rs_wdata_c[RS_P_PUSH] = w.wdata_c;
    end

    rs_tosr = w.tosr;
    rs_tosw = w.tosw;
    rs_dsp  = w.dsp;
    rs_kl   = w.kl;

    ras_pd_snapshot.tosr = w.tosr;
    ras_pd_snapshot.tosw = w.tosw;
    ras_pd_snapshot.bos  = w.bos;
    ras_pd_snapshot.rctr = w.valid ? w.top_rctr : '0;
    ras_pd_snapshot.dep  = w.dsp;
    ras_pd_snapshot.tag  = w.valid ? w.ttag : '0;
    // BP-153: the block's operation record after the restore: the C1
    // operation's push and pop, else none (an undone operation is no
    // longer in the state, and an entry that takes a C1 operation held no
    // other on the path).
    ras_pd_snapshot.push  = pd_push;
    ras_pd_snapshot.pmode = pd_pmode;
    ras_pd_snapshot.ptosr = pd_ptosr;
    ras_pd_snapshot.ptag  = pd_ptag;
  end

  // -----------------------------------------------------------------
  // Commit stack (IC-RAS-10, ras_decisions.md 3.3). A return
  // decrements CSP; a call writes at CSP and advances it. RETURN_CALL
  // is the return arm then the call arm, the second applied to the
  // CSP the first leaves, so it overwrites the committed top in place
  // (RAS-DS1). Reads csp (a flop) -> nba_sequent.
  // A return on an empty stack (count 0) leaves it unchanged. A call
  // on a full stack overwrites the oldest entry, CSP wrapping past it,
  // and the count holds at RAS_COMMIT_ENTRIES (no fault, 3.3).
  // The committed depth (A1, BP-152) is the committing block's dep: the
  // speculative depth after the block, which the commit stack now
  // stands at.
  // -----------------------------------------------------------------
  logic                           c_pop;
  logic                           c_push;
  logic [RAS_COMMIT_PTR_BITS-1:0] c_mid;
  logic [RAS_COMMIT_PTR_BITS-1:0] c_nxt;
  logic [RAS_COMMIT_CNT_BITS-1:0] c_cnt_mid;
  logic [RAS_COMMIT_CNT_BITS-1:0] c_cnt_nxt;
  logic [RAS_DEPTH_BITS-1:0]      c_dcm_nxt;
  // TOSR after this cycle's scan, and the commit moving it with BOS
  // (BP-138): the stack is empty at the BOS the commit replaces.
  logic [RAS_PTR_BITS-1:0]        scan_tosr;
  logic                           c_drag;
  // The commit moves BOS (CO5, BP-140, final session-084): a push does;
  // a pop does unless its snapshot is an empty stack (THE BOTTOM).
  logic                           c_bos;

  always_comb begin : commit_arms
    c_pop  = ras_commit_val &
             ((ras_commit_br_type == RETURN) |
              (ras_commit_br_type == RETURN_CALL));
    c_push = ras_commit_val &
             ((ras_commit_br_type == DIRECT_CALL)   |
              (ras_commit_br_type == INDIRECT_CALL) |
              (ras_commit_br_type == RETURN_CALL));
    c_mid  = (c_pop && (c_cnt != '0))
               ? (csp - RAS_COMMIT_PTR_BITS'(1)) : csp;
    c_nxt  = c_push ? (c_mid + RAS_COMMIT_PTR_BITS'(1)) : c_mid;
    c_cnt_mid = (c_pop && (c_cnt != '0))
                  ? (c_cnt - RAS_COMMIT_CNT_BITS'(1)) : c_cnt;
    c_cnt_nxt = (c_push &&
                 (c_cnt_mid != RAS_COMMIT_CNT_BITS'(RAS_COMMIT_ENTRIES)))
                  ? (c_cnt_mid + RAS_COMMIT_CNT_BITS'(1)) : c_cnt_mid;
    c_dcm_nxt = (c_pop | c_push) ? ras_commit_snapshot.dep : dcm;
    scan_tosr = ras_p2_keep ? nxt_tosr : rep_tosr;
    c_bos     = c_push |
                (c_pop & (ras_commit_snapshot.tosr != ras_commit_snapshot.bos));
    c_drag    = c_bos & (scan_tosr == bos);
  end

  // -----------------------------------------------------------------
  // Sequential state update.
  // Priority: synchronous reset > restore (pointer-only) > scan.
  // Commit and the p2->p3 pipeline advance independently of restore,
  // except BOS where restore wins.
  // -----------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rstn) begin
      tosr <= '0;
      tosw <= '0;
      bos  <= '0;
      csp  <= '0;
      c_cnt <= '0;
      dsp  <= '0;
      dcm  <= '0;
      ras_rst_done <= 1'b0;
      for (int i = 0; i < RAS_SPEC_ENTRIES; i++) begin
        spec_ret_addr[i] <= '0;
        spec_rctr[i]     <= '0;
        spec_ncnt[i]     <= '0;
        spec_nos[i]      <= '0;
        spec_bot[i]      <= 1'b0;
        spec_gen[i]      <= '0;
      end
      for (int i = 0; i < RAS_COMMIT_ENTRIES; i++) begin
        commit_ret_addr[i] <= '0;
      end
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        p3_op_q[s]       <= OP_NONE;
        p3_fallthr_q[s]  <= '0;
        p3_pre_tosr_q[s] <= '0;
        p3_pre_tag_q[s]  <= '0;
        p3_pre_empty_q[s] <= 1'b0;
        p3_pop_dec_q[s]  <= 1'b0;
        p3_push_inc_q[s] <= 1'b0;
        p3_push_sat_q[s] <= 1'b0;
        p3_inc_ptr_q[s]  <= '0;
      end
    end else begin
      ras_rst_done <= 1'b1;

      // ---- speculative pointers and array writes -----------------
      if (ras_restore_val) begin
        // Pointer restore; circular data is not cleared. The array
        // writes are the count of the snapshot's top entry, when the
        // snapshot is not an empty stack (TD#194 option A, ruled
        // session-084, ras_decisions.md 4.3, 12.9 RE6; BP-142), and the
        // C1 operation's (BP-152). Before BP-142 a count changed in
        // place on the wrong path kept the wrong path's value (tb_ras
        // TC-45). No other count changes.
        tosr <= rs_tosr;
        tosw <= rs_tosw;
        dsp  <= rs_dsp;
        if (rs_we[0])
          spec_rctr[rs_waddr[0]] <= rs_wdata_r[0];
        for (int p = 1; p < RS_WR_PORTS; p++) begin
          if (rs_we[p]) begin
            spec_ret_addr[rs_waddr[p]] <= rs_wdata_a[p];
            spec_rctr[rs_waddr[p]]     <= rs_wdata_r[p];
            spec_nos[rs_waddr[p]]      <= rs_wdata_n[p];
            spec_bot[rs_waddr[p]]      <= rs_wdata_b[p];
            if (rs_al[p]) begin
              spec_gen[rs_waddr[p]]  <= spec_gen[rs_waddr[p]] + TAG_ONE;
              spec_ncnt[rs_waddr[p]] <= rs_wdata_c[p];       // BP-153
            end
          end
        end
        // B1: the links the C1 push's allocation killed, last.
        for (int j = 0; j < RAS_SPEC_ENTRIES; j++) begin
          if (rs_kl[j]) spec_bot[j] <= 1'b1;
        end
      end else begin
        // A commit that moves BOS while the stack is empty moves TOSR
        // with it, so the stack stays empty as TOSR == BOS (BP-138).
        tosr <= c_drag ? ras_commit_snapshot.tosr : scan_tosr;
        tosw <= ras_p2_keep ? nxt_tosw : rep_tosw;
        dsp  <= ras_p2_keep ? nxt_dsp  : rep_dsp;
        // Apply the repair writes, then the p2 writes, in port order
        // (the order the scan made them), so a later write to the
        // same index supersedes an earlier one. The p2 ports are the
        // upper half; dropped with the p2 pass.
        for (int p = 0; p < RAS_WR_PORTS; p++) begin
          if (sp_we[p] &&
              (ras_p2_keep ||
               (p < NUM_PRED_SLOTS * RAS_WR_PER_SLOT))) begin
            spec_ret_addr[sp_waddr[p]] <= sp_wdata_a[p];
            spec_rctr[sp_waddr[p]]     <= sp_wdata_r[p];
            spec_nos[sp_waddr[p]]      <= sp_wdata_n[p];
            spec_bot[sp_waddr[p]]      <= sp_wdata_b[p];
            if (sp_al[p]) begin
              spec_gen[sp_waddr[p]]  <= spec_gen[sp_waddr[p]] + TAG_ONE;
              spec_ncnt[sp_waddr[p]] <= sp_wdata_c[p];       // BP-153
            end
          end
        end
        // B1: the links this cycle's allocations killed, after the port
        // writes so a count write of a killed entry does not undo it.
        for (int j = 0; j < RAS_SPEC_ENTRIES; j++) begin
          if (ras_p2_keep ? nxt_kl[j] : rep_kl[j]) spec_bot[j] <= 1'b1;
        end
      end

      // ---- committed boundary (BOS): restore > commit > hold -----
      if (ras_restore_val) begin
        bos <= ras_restore_snapshot.bos;
      end else if (c_bos) begin
        // Committing entry's post-op TOSR is the new boundary. Once
        // for a RETURN_CALL (IC-RAS-10). Not for a RETURN whose
        // snapshot is an empty stack (BP-140, THE BOTTOM).
        bos <= ras_commit_snapshot.tosr;
      end

      // ---- commit stack (independent of restore / p2) ------------
      if (c_push) begin
        commit_ret_addr[c_mid] <= ras_commit_ret_addr;
      end
      csp   <= c_nxt;
      c_cnt <= c_cnt_nxt;
      dcm   <= c_dcm_nxt;

      // ---- register p2 op and fallthrough for the p3 repair pass -
      // An operation the restore or the squash dropped is registered
      // as none, so the p3 pass does not repair what never happened
      // (BP-121).
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        p3_op_q[s]       <= (ras_restore_val | ~ras_p2_keep) ? OP_NONE
                                                             : p2_op[s];
        p3_fallthr_q[s]  <= ras_fall_through_p2[s];
        p3_pre_tosr_q[s] <= p2_pre_tosr[s];
        p3_pre_tag_q[s]  <= p2_pre_tag[s];
        p3_pre_empty_q[s] <= p2_pre_empty[s];
        p3_pop_dec_q[s]  <= p2_pop_dec[s];
        p3_push_inc_q[s] <= p2_push_inc[s];
        p3_push_sat_q[s] <= p2_push_sat[s];
        p3_inc_ptr_q[s]  <= p2_inc_ptr[s];
      end
    end
  end

endmodule : ras
