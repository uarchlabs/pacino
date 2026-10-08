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
//     session-075, TD#159). Pointers TOSR/TOSW/BOS, snapshotted into
//     the FTQ for O(1) pointer-only mispredict recovery.
//   - Commit stack: RAS_COMMIT_ENTRIES, conventional circular stack.
//     Pointer CSP. Updated at retire. Empty fallback for pops.
//
// Pipeline (p-stage names; planning docs use equivalent s-stage):
//   p0: combinational TOS read (initial prediction fallback).
//   p2: FTB-confirmed push/pop, two slots, slot 0 before slot 1,
//       with slot0=call / slot1=return same-cycle bypass. RETURN_CALL
//       pops then pushes in one slot (RAS-DS1, TD#152).
//   p3: repair pass, inverse op when p3 FTB type disagrees with the
//       registered p2 op (speculative stack only).
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
  input  logic [VA_WIDTH-1:0] ras_pc_p2           [0:NUM_PRED_SLOTS-1],
  input  logic [VA_WIDTH-1:0] ras_fall_through_p2 [0:NUM_PRED_SLOTS-1],

  // ---- p2 prediction outputs (one per slot) -----------------------
  output logic [VA_WIDTH-1:0] ras_pop_addr_p2  [0:NUM_PRED_SLOTS-1],
  output logic                ras_pop_valid_p2 [0:NUM_PRED_SLOTS-1],
  output bp_ras_snapshot_t    ras_snapshot_p2  [0:NUM_PRED_SLOTS-1],

  // ---- p3 repair inputs (one per slot) ----------------------------
  // Registered (external) FTB structural type at p3 (IC-RAS-11).
  input  logic                ras_pred_val_p3 [0:NUM_PRED_SLOTS-1],
  input  bp_br_type_e         ras_br_type_p3  [0:NUM_PRED_SLOTS-1],

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

  // ---- flush (reserved, RAS-3 OPEN) -------------------------------
  input  logic                ras_flush_val,
  input  bp_ras_snapshot_t    ras_flush_snapshot
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

  // -----------------------------------------------------------------
  // Register-file storage and pointers
  // -----------------------------------------------------------------
  logic [VA_WIDTH-1:0]       spec_ret_addr [0:RAS_SPEC_ENTRIES-1];
  logic [RAS_RCTR_WIDTH-1:0] spec_rctr     [0:RAS_SPEC_ENTRIES-1];
  // Next on stack: the index of the entry below this one (3.2, ruled
  // session-075, BP-120). Written by the push that allocates the
  // entry, read by the pop that removes it. Internal; the snapshot
  // stays three pointers (4.1).
  logic [RAS_PTR_BITS-1:0]   spec_nos      [0:RAS_SPEC_ENTRIES-1];

  logic [VA_WIDTH-1:0]       commit_ret_addr [0:RAS_COMMIT_ENTRIES-1];
  logic [RAS_RCTR_WIDTH-1:0] commit_rctr     [0:RAS_COMMIT_ENTRIES-1];

  logic [RAS_PTR_BITS-1:0]        tosr; // top-of-stack read
  logic [RAS_PTR_BITS-1:0]        tosw; // top-of-stack write (free)
  logic [RAS_PTR_BITS-1:0]        bos;  // committed boundary
  logic [RAS_COMMIT_PTR_BITS-1:0] csp;  // commit free pointer

  // Registered "reset complete" valid. Reading this FF in the scan
  // always_comb forces nba_sequent classification (see CLAUDE.md
  // stl_sequent note) and gates spurious post-reset activity.
  logic ras_rst_done;

  // p2 -> p3 pipeline registers: actual p2 op and the fallthrough
  // address used, per slot. Consumed by the p3 repair pass.
  logic [1:0]          p3_op_q      [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] p3_fallthr_q [0:NUM_PRED_SLOTS-1];
  // TOSR before the slot's p2 operation. Read to undo a pop, alone or
  // as the first half of a whole RETURN_CALL (see the repair pass).
  logic [RAS_PTR_BITS-1:0] p3_pre_tosr_q [0:NUM_PRED_SLOTS-1];

  // -----------------------------------------------------------------
  // Commit-stack top (read-only fallback for empty speculative pops)
  // CSP is a free pointer: top entry is at CSP-1, empty when CSP==0.
  // Reads csp/commit_ret_addr (FF outputs) -> nba_sequent.
  // -----------------------------------------------------------------
  logic                           commit_top_valid;
  logic [RAS_COMMIT_PTR_BITS-1:0] commit_top_idx;
  logic [VA_WIDTH-1:0]            commit_top_addr;

  always_comb begin
    commit_top_valid = (csp != '0);
    commit_top_idx   = csp - {{(RAS_COMMIT_PTR_BITS-1){1'b0}}, 1'b1};
    commit_top_addr  = commit_ret_addr[commit_top_idx];
  end

  // -----------------------------------------------------------------
  // p0 TOS read. Both slots present the same combinational TOS value.
  // Source: speculative top when non-empty, else commit-stack top.
  // -----------------------------------------------------------------
  logic                spec_top_valid_p0;
  logic [VA_WIDTH-1:0] p0_tos_addr;
  logic                p0_tos_valid;

  always_comb begin
    spec_top_valid_p0 = (tosr != bos);
    p0_tos_addr  = spec_top_valid_p0 ? spec_ret_addr[tosr]
                                     : commit_top_addr;
    p0_tos_valid = spec_top_valid_p0 | commit_top_valid;
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
  // -----------------------------------------------------------------
  typedef struct packed {
    logic [RAS_PTR_BITS-1:0]   tosr;
    logic [RAS_PTR_BITS-1:0]   tosw;
    logic [VA_WIDTH-1:0]       top_addr;
    logic [RAS_RCTR_WIDTH-1:0] top_rctr;
    logic [RAS_PTR_BITS-1:0]   top_nos;
    logic                      valid;
    // The array write the last primitive made, if any.
    logic                      we;
    logic [RAS_PTR_BITS-1:0]   waddr;
    logic [VA_WIDTH-1:0]       wdata_a;
    logic [RAS_RCTR_WIDTH-1:0] wdata_r;
    logic [RAS_PTR_BITS-1:0]   wdata_n;
  } ras_ws_t;

  localparam logic [RAS_PTR_BITS-1:0]   PTR_ONE  = RAS_PTR_BITS'(1);
  localparam logic [RAS_RCTR_WIDTH-1:0] RCTR_ONE = RAS_RCTR_WIDTH'(1);

  // Reload the working top from the array at the working TOSR. TOSR
  // equal to BOS is empty.
  function automatic ras_ws_t st_load(input ras_ws_t w);
    ras_ws_t r;
    r = w;
    if (r.tosr != bos) begin
      r.top_addr = spec_ret_addr[r.tosr];
      r.top_rctr = spec_rctr[r.tosr];
      r.top_nos  = spec_nos[r.tosr];
      r.valid    = 1'b1;
    end else begin
      r.top_addr = '0;
      r.top_rctr = '0;
      r.top_nos  = '0;
      r.valid    = 1'b0;
    end
    return r;
  endfunction

  function automatic ras_ws_t st_retract(input ras_ws_t w);
    ras_ws_t r;
    r    = w;
    r.we = 1'b0;
    if (r.valid) begin
      if (r.top_rctr != '0) begin
        // Recursion outstanding: decrement the count, TOSR holds.
        r.we       = 1'b1;
        r.waddr    = r.tosr;
        r.wdata_a  = r.top_addr;
        r.wdata_r  = r.top_rctr - RCTR_ONE;
        r.wdata_n  = r.top_nos;
        r.top_rctr = r.wdata_r;
      end else begin
        // TOSR follows the link to the entry below, no data
        // overwritten. Before BP-120: TOSR - 1.
        r.tosr = r.top_nos;
        r      = st_load(r);
      end
    end
    return r;
  endfunction

  // The popped entry is still resident (a pop does not overwrite the
  // array), so it is re-exposed by restoring the TOSR the pop started
  // from. No array write, TOSW unchanged (stays monotonic). A pop that
  // only decremented a recursion count held TOSR, so this restores the
  // same TOSR and the count stays decremented (TD #78).
  function automatic ras_ws_t st_restore(
      input ras_ws_t w, input logic [RAS_PTR_BITS-1:0] pre_tosr);
    ras_ws_t r;
    r      = w;
    r.we   = 1'b0;
    r.tosr = pre_tosr;
    r      = st_load(r);
    return r;
  endfunction

  function automatic ras_ws_t st_push(input ras_ws_t             w,
                                      input logic [VA_WIDTH-1:0] ft,
                                      input logic                recur);
    ras_ws_t                 r;
    logic [RAS_PTR_BITS-1:0] alloc;
    r  = w;
    r.we = 1'b1;
    if (recur & r.valid & (ft == r.top_addr)) begin
      // Recursion: increment rctr at TOSR, saturate, no advance.
      r.waddr    = r.tosr;
      r.wdata_a  = r.top_addr;
      r.wdata_r  = (r.top_rctr == RCTR_MAX) ? RCTR_MAX
                                            : r.top_rctr + RCTR_ONE;
      r.wdata_n  = r.top_nos;
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
      alloc      = (r.tosw == bos) ? (r.tosw + PTR_ONE) : r.tosw;
      r.waddr    = alloc;
      r.wdata_a  = ft;
      r.wdata_r  = '0;
      r.wdata_n  = (r.tosw == bos) ? bos : r.tosr;
      r.tosr     = alloc;
      r.tosw     = alloc + PTR_ONE;
      r.top_addr = ft;
      r.top_rctr = '0;
      r.top_nos  = r.wdata_n;
      r.valid    = 1'b1;
    end
    return r;
  endfunction

  logic [RAS_PTR_BITS-1:0]   nxt_tosr;
  logic [RAS_PTR_BITS-1:0]   nxt_tosw;
  // The state after the repair pass alone, for a cycle whose p2 pass
  // is dropped (ras_p2_keep low).
  logic [RAS_PTR_BITS-1:0]   rep_tosr;
  logic [RAS_PTR_BITS-1:0]   rep_tosw;

  logic                      sp_we      [0:RAS_WR_PORTS-1];
  logic [RAS_PTR_BITS-1:0]   sp_waddr   [0:RAS_WR_PORTS-1];
  logic [VA_WIDTH-1:0]       sp_wdata_a [0:RAS_WR_PORTS-1];
  logic [RAS_RCTR_WIDTH-1:0] sp_wdata_r [0:RAS_WR_PORTS-1];
  logic [RAS_PTR_BITS-1:0]   sp_wdata_n [0:RAS_WR_PORTS-1];

  logic [1:0]                p2_op       [0:NUM_PRED_SLOTS-1];
  logic [RAS_PTR_BITS-1:0]   p2_pre_tosr [0:NUM_PRED_SLOTS-1];

  always_comb begin : scan
    ras_ws_t w;
    int      n;       // writes made so far by this slot in this pass
    int      pi;      // write port index
    logic    s3_pop;
    logic    s3_push;
    logic    q_pop;
    logic    q_push;
    logic    is_pop;
    logic    is_push;

    // Defaults for every variable the loops assign, so no control path
    // leaves one unassigned.
    n        = 0;
    pi       = 0;
    s3_pop   = 1'b0;
    s3_push  = 1'b0;
    q_pop    = 1'b0;
    q_push   = 1'b0;
    is_pop   = 1'b0;
    is_push  = 1'b0;
    nxt_tosr = tosr;
    nxt_tosw = tosw;
    rep_tosr = tosr;
    rep_tosw = tosw;

    // Working state from the FF pointers.
    w      = '0;
    w.tosr = tosr;
    w.tosw = tosw;
    w      = st_load(w);

    for (int p = 0; p < RAS_WR_PORTS; p++) begin
      sp_we[p]      = 1'b0;
      sp_waddr[p]   = '0;
      sp_wdata_a[p] = '0;
      sp_wdata_r[p] = '0;
      sp_wdata_n[p] = '0;
    end
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      ras_pop_addr_p2[s]  = '0;
      ras_pop_valid_p2[s] = 1'b0;
      ras_snapshot_p2[s]  = '0;
      p2_op[s]            = OP_NONE;
      p2_pre_tosr[s]      = '0;
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
    // decremented, or the push incremented, is not restored -- the
    // TD #78 limitation, as for an undo-pop. An undo-pop alone restores
    // the same registered TOSR (st_restore); a missed pop and an
    // undo-push follow the link (st_retract).
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

      if (ras_rst_done & q_pop & q_push & ~s3_pop & ~s3_push) begin
        w.tosr = p3_pre_tosr_q[s];
        w      = st_load(w);
      end else if (ras_rst_done) begin
        // Undo a push the p3 type does not have.
        if (q_push & ~s3_push) begin
          w = st_retract(w);
          if (w.we) begin
            pi             = (s * RAS_WR_PER_SLOT) + n;
            sp_we[pi]      = 1'b1;
            sp_waddr[pi]   = w.waddr;
            sp_wdata_a[pi] = w.wdata_a;
            sp_wdata_r[pi] = w.wdata_r;
            sp_wdata_n[pi] = w.wdata_n;
            n              = n + 1;
          end
        end
        // Undo a pop the p3 type does not have, or apply a missed one.
        if (q_pop & ~s3_pop) begin
          w = st_restore(w, p3_pre_tosr_q[s]);
        end else if (~q_pop & s3_pop) begin
          w = st_retract(w);
          if (w.we && (n < RAS_WR_PER_SLOT)) begin
            pi             = (s * RAS_WR_PER_SLOT) + n;
            sp_we[pi]      = 1'b1;
            sp_waddr[pi]   = w.waddr;
            sp_wdata_a[pi] = w.wdata_a;
            sp_wdata_r[pi] = w.wdata_r;
            sp_wdata_n[pi] = w.wdata_n;
            n              = n + 1;
          end
        end
        // Apply a missed push: allocate the registered fall-through.
        if (~q_push & s3_push) begin
          w = st_push(w, p3_fallthr_q[s], 1'b0);
          if (n < RAS_WR_PER_SLOT) begin
            pi             = (s * RAS_WR_PER_SLOT) + n;
            sp_we[pi]      = 1'b1;
            sp_waddr[pi]   = w.waddr;
            sp_wdata_a[pi] = w.wdata_a;
            sp_wdata_r[pi] = w.wdata_r;
            sp_wdata_n[pi] = w.wdata_n;
          end
        end
      end
    end

    rep_tosr = w.tosr;
    rep_tosw = w.tosw;

    // -------- p2 pass (this cycle's prediction) --------------------
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      is_pop  = ras_rst_done & ras_pred_val_p2[s] &
                ((ras_br_type_p2[s] == RETURN) |
                 (ras_br_type_p2[s] == RETURN_CALL));
      is_push = ras_rst_done & ras_pred_val_p2[s] &
                ((ras_br_type_p2[s] == DIRECT_CALL)   |
                 (ras_br_type_p2[s] == INDIRECT_CALL) |
                 (ras_br_type_p2[s] == RETURN_CALL));
      p2_op[s]       = is_pop ? (is_push ? OP_POPPUSH : OP_POP)
                              : (is_push ? OP_PUSH    : OP_NONE);
      p2_pre_tosr[s] = w.tosr;
      n              = 0;

      // The pop first (RAS-DS1). It supplies the predicted target.
      if (is_pop) begin
        if (~w.valid) begin
          // Empty speculative stack: commit-stack fallback, not
          // consumed. Valid only if the commit stack is non-empty.
          ras_pop_addr_p2[s]  = commit_top_addr;
          ras_pop_valid_p2[s] = commit_top_valid;
        end else begin
          ras_pop_addr_p2[s]  = w.top_addr;
          ras_pop_valid_p2[s] = 1'b1;
          w = st_retract(w);
          if (w.we) begin
            pi             = ((NUM_PRED_SLOTS + s) * RAS_WR_PER_SLOT) + n;
            sp_we[pi]      = 1'b1;
            sp_waddr[pi]   = w.waddr;
            sp_wdata_a[pi] = w.wdata_a;
            sp_wdata_r[pi] = w.wdata_r;
            sp_wdata_n[pi] = w.wdata_n;
            n              = n + 1;
          end
        end
      end

      // Then the push, applied to the state the pop left.
      if (is_push) begin
        w = st_push(w, ras_fall_through_p2[s], 1'b1);
        pi             = ((NUM_PRED_SLOTS + s) * RAS_WR_PER_SLOT) + n;
        sp_we[pi]      = 1'b1;
        sp_waddr[pi]   = w.waddr;
        sp_wdata_a[pi] = w.wdata_a;
        sp_wdata_r[pi] = w.wdata_r;
        sp_wdata_n[pi] = w.wdata_n;
      end

      // Post-op snapshot for this slot (BOS unchanged across p2).
      ras_snapshot_p2[s].tosr = w.tosr;
      ras_snapshot_p2[s].tosw = w.tosw;
      ras_snapshot_p2[s].bos  = bos;
    end

    nxt_tosr = w.tosr;
    nxt_tosw = w.tosw;
  end

  // -----------------------------------------------------------------
  // Commit stack (IC-RAS-10, ras_decisions.md 3.3). A return
  // decrements CSP; a call writes at CSP and advances it. RETURN_CALL
  // is the return arm then the call arm, the second applied to the
  // CSP the first leaves, so it overwrites the committed top in place
  // (RAS-DS1). Reads csp (a flop) -> nba_sequent.
  // -----------------------------------------------------------------
  logic                           c_pop;
  logic                           c_push;
  logic [RAS_COMMIT_PTR_BITS-1:0] c_mid;
  logic [RAS_COMMIT_PTR_BITS-1:0] c_nxt;

  always_comb begin : commit_arms
    c_pop  = ras_commit_val &
             ((ras_commit_br_type == RETURN) |
              (ras_commit_br_type == RETURN_CALL));
    c_push = ras_commit_val &
             ((ras_commit_br_type == DIRECT_CALL)   |
              (ras_commit_br_type == INDIRECT_CALL) |
              (ras_commit_br_type == RETURN_CALL));
    c_mid  = (c_pop && (csp != '0))
               ? (csp - RAS_COMMIT_PTR_BITS'(1)) : csp;
    c_nxt  = c_push ? (c_mid + RAS_COMMIT_PTR_BITS'(1)) : c_mid;
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
      ras_rst_done <= 1'b0;
      for (int i = 0; i < RAS_SPEC_ENTRIES; i++) begin
        spec_ret_addr[i] <= '0;
        spec_rctr[i]     <= '0;
        spec_nos[i]      <= '0;
      end
      for (int i = 0; i < RAS_COMMIT_ENTRIES; i++) begin
        commit_ret_addr[i] <= '0;
        commit_rctr[i]     <= '0;
      end
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        p3_op_q[s]       <= OP_NONE;
        p3_fallthr_q[s]  <= '0;
        p3_pre_tosr_q[s] <= '0;
      end
    end else begin
      ras_rst_done <= 1'b1;

      // ---- speculative pointers and array writes -----------------
      if (ras_restore_val) begin
        // Pointer-only restore; circular data is not cleared.
        tosr <= ras_restore_snapshot.tosr;
        tosw <= ras_restore_snapshot.tosw;
      end else begin
        tosr <= ras_p2_keep ? nxt_tosr : rep_tosr;
        tosw <= ras_p2_keep ? nxt_tosw : rep_tosw;
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
          end
        end
      end

      // ---- committed boundary (BOS): restore > commit > hold -----
      if (ras_restore_val) begin
        bos <= ras_restore_snapshot.bos;
      end else if (c_pop | c_push) begin
        // Committing entry's post-op TOSR is the new boundary. Once
        // for a RETURN_CALL (IC-RAS-10).
        bos <= ras_commit_snapshot.tosr;
      end

      // ---- commit stack (independent of restore / p2) ------------
      if (c_push) begin
        commit_ret_addr[c_mid] <= ras_commit_ret_addr;
        commit_rctr[c_mid]     <= '0;
      end
      csp <= c_nxt;

      // ---- register p2 op and fallthrough for the p3 repair pass -
      // An operation the restore or the squash dropped is registered
      // as none, so the p3 pass does not repair what never happened
      // (BP-121).
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        p3_op_q[s]       <= (ras_restore_val | ~ras_p2_keep) ? OP_NONE
                                                             : p2_op[s];
        p3_fallthr_q[s]  <= ras_fall_through_p2[s];
        p3_pre_tosr_q[s] <= p2_pre_tosr[s];
      end
    end
  end

endmodule : ras
