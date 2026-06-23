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
//   - Speculative stack: RAS_SPEC_ENTRIES, simple circular buffer.
//     Pointers TOSR/TOSW/BOS, snapshotted into the FTQ for O(1)
//     pointer-only mispredict recovery.
//   - Commit stack: RAS_COMMIT_ENTRIES, conventional circular stack.
//     Pointer CSP. Updated at retire. Empty fallback for pops.
//
// Pipeline (p-stage names; planning docs use equivalent s-stage):
//   p0: combinational TOS read (initial prediction fallback).
//   p2: FTB-confirmed push/pop, two slots, slot 0 before slot 1,
//       with slot0=call / slot1=return same-cycle bypass.
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
  localparam logic [1:0] OP_NONE = 2'b00;
  localparam logic [1:0] OP_PUSH = 2'b01;
  localparam logic [1:0] OP_POP  = 2'b10;

  // Number of speculative-stack write requests produced per cycle:
  // one per slot for the p3 repair pass plus one per slot for the
  // p2 pass. Repair requests occupy [0 .. NUM_PRED_SLOTS-1], p2
  // requests occupy [NUM_PRED_SLOTS .. 2*NUM_PRED_SLOTS-1].
  localparam int RAS_WR_PORTS = 2 * NUM_PRED_SLOTS;

  // -----------------------------------------------------------------
  // Register-file storage and pointers
  // -----------------------------------------------------------------
  logic [VA_WIDTH-1:0]       spec_ret_addr [0:RAS_SPEC_ENTRIES-1];
  logic [RAS_RCTR_WIDTH-1:0] spec_rctr     [0:RAS_SPEC_ENTRIES-1];

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
  // by this cycle's p2 push/pop, processed slot 0 before slot 1.
  //
  // The scan walks working pointer state, reading FF outputs (tosr,
  // tosw, bos and the arrays) so it is classified nba_sequent. It
  // emits up to RAS_WR_PORTS speculative write requests, the next
  // pointer state, the p2 pop outputs, the post-op snapshots, and the
  // p2 op codes to be registered for the p3 pass.
  //
  // Same-cycle bypass (IC-RAS-04): the working top (w_top_addr) holds
  // the just-pushed value, so a later-slot pop forwards it without an
  // array read.
  // -----------------------------------------------------------------
  logic [RAS_PTR_BITS-1:0]   nxt_tosr;
  logic [RAS_PTR_BITS-1:0]   nxt_tosw;

  logic                      sp_we      [0:RAS_WR_PORTS-1];
  logic [RAS_PTR_BITS-1:0]   sp_waddr   [0:RAS_WR_PORTS-1];
  logic [VA_WIDTH-1:0]       sp_wdata_a [0:RAS_WR_PORTS-1];
  logic [RAS_RCTR_WIDTH-1:0] sp_wdata_r [0:RAS_WR_PORTS-1];

  logic [1:0]                p2_op [0:NUM_PRED_SLOTS-1];

  always_comb begin
    // Working pointer state and working top-of-stack view.
    logic [RAS_PTR_BITS-1:0]   w_tosr;
    logic [RAS_PTR_BITS-1:0]   w_tosw;
    logic [VA_WIDTH-1:0]       w_top_addr;
    logic [RAS_RCTR_WIDTH-1:0] w_top_rctr;
    logic                      w_valid;
    logic                      s3_call;
    logic                      s3_ret;
    logic                      s3_noop;
    logic                      rep_push;
    logic                      rep_pop;
    logic                      is_push;
    logic                      is_pop;

    // Defaults.
    w_tosr = tosr;
    w_tosw = tosw;
    if (tosr != bos) begin
      w_top_addr = spec_ret_addr[tosr];
      w_top_rctr = spec_rctr[tosr];
      w_valid    = 1'b1;
    end else begin
      w_top_addr = '0;
      w_top_rctr = '0;
      w_valid    = 1'b0;
    end

    for (int p = 0; p < RAS_WR_PORTS; p++) begin
      sp_we[p]      = 1'b0;
      sp_waddr[p]   = '0;
      sp_wdata_a[p] = '0;
      sp_wdata_r[p] = '0;
    end
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      ras_pop_addr_p2[s]  = '0;
      ras_pop_valid_p2[s] = 1'b0;
      ras_snapshot_p2[s]  = '0;
      p2_op[s]            = OP_NONE;
    end

    // -------- p3 repair pass (corrects the prior cycle's op) -------
    // Repair table (IC-RAS-11). push->pop and pop->push within one
    // p2/p3 pair cannot occur, so they are not handled here.
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      s3_call = ras_pred_val_p3[s] &
                ((ras_br_type_p3[s] == DIRECT_CALL) |
                 (ras_br_type_p3[s] == INDIRECT_CALL));
      s3_ret  = ras_pred_val_p3[s] & (ras_br_type_p3[s] == RETURN);
      s3_noop = ~s3_call & ~s3_ret;

      rep_pop  = ras_rst_done &
                 (((p3_op_q[s] == OP_PUSH) & s3_noop) |
                  ((p3_op_q[s] == OP_NONE) & s3_ret));
      rep_push = ras_rst_done &
                 (((p3_op_q[s] == OP_POP)  & s3_noop) |
                  ((p3_op_q[s] == OP_NONE) & s3_call));

      if (rep_pop) begin
        if (w_valid) begin
          if (w_top_rctr != '0) begin
            // Undo by decrementing the recursion counter.
            sp_we[s]      = 1'b1;
            sp_waddr[s]   = w_tosr;
            sp_wdata_a[s] = w_top_addr;
            sp_wdata_r[s] = w_top_rctr -
                            {{(RAS_RCTR_WIDTH-1){1'b0}}, 1'b1};
            w_top_rctr    = sp_wdata_r[s];
          end else begin
            w_tosr = w_tosr - {{(RAS_PTR_BITS-1){1'b0}}, 1'b1};
            if (w_tosr != bos) begin
              w_top_addr = spec_ret_addr[w_tosr];
              w_top_rctr = spec_rctr[w_tosr];
              w_valid    = 1'b1;
            end else begin
              w_top_addr = '0;
              w_top_rctr = '0;
              w_valid    = 1'b0;
            end
          end
        end
      end else if (rep_push) begin
        // Re-push the registered fallthrough address.
        sp_we[s]      = 1'b1;
        sp_waddr[s]   = w_tosw;
        sp_wdata_a[s] = p3_fallthr_q[s];
        sp_wdata_r[s] = '0;
        w_tosr        = w_tosw;
        w_tosw        = w_tosw + {{(RAS_PTR_BITS-1){1'b0}}, 1'b1};
        w_top_addr    = p3_fallthr_q[s];
        w_top_rctr    = '0;
        w_valid       = 1'b1;
      end
    end

    // -------- p2 push/pop pass (this cycle's prediction) -----------
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      is_push = ras_rst_done & ras_pred_val_p2[s] &
                ((ras_br_type_p2[s] == DIRECT_CALL) |
                 (ras_br_type_p2[s] == INDIRECT_CALL));
      is_pop  = ras_rst_done & ras_pred_val_p2[s] &
                (ras_br_type_p2[s] == RETURN);

      if (is_push) begin
        p2_op[s] = OP_PUSH;
        if (w_valid & (ras_fall_through_p2[s] == w_top_addr)) begin
          // Recursion: increment rctr at TOSR, saturate, no advance.
          sp_we[NUM_PRED_SLOTS + s]      = 1'b1;
          sp_waddr[NUM_PRED_SLOTS + s]   = w_tosr;
          sp_wdata_a[NUM_PRED_SLOTS + s] = w_top_addr;
          sp_wdata_r[NUM_PRED_SLOTS + s] = (w_top_rctr == RCTR_MAX)
              ? RCTR_MAX
              : w_top_rctr + {{(RAS_RCTR_WIDTH-1){1'b0}}, 1'b1};
          w_top_rctr = sp_wdata_r[NUM_PRED_SLOTS + s];
        end else begin
          // Normal push: write at TOSW, TOSR=TOSW, TOSW advances.
          sp_we[NUM_PRED_SLOTS + s]      = 1'b1;
          sp_waddr[NUM_PRED_SLOTS + s]   = w_tosw;
          sp_wdata_a[NUM_PRED_SLOTS + s] = ras_fall_through_p2[s];
          sp_wdata_r[NUM_PRED_SLOTS + s] = '0;
          w_tosr     = w_tosw;
          w_tosw     = w_tosw + {{(RAS_PTR_BITS-1){1'b0}}, 1'b1};
          w_top_addr = ras_fall_through_p2[s];
          w_top_rctr = '0;
          w_valid    = 1'b1;
        end
      end else if (is_pop) begin
        p2_op[s] = OP_POP;
        if (~w_valid) begin
          // Empty speculative stack: commit-stack fallback, not
          // consumed. Valid only if the commit stack is non-empty.
          ras_pop_addr_p2[s]  = commit_top_addr;
          ras_pop_valid_p2[s] = commit_top_valid;
        end else begin
          ras_pop_addr_p2[s]  = w_top_addr;
          ras_pop_valid_p2[s] = 1'b1;
          if (w_top_rctr != '0) begin
            // Recursion outstanding: decrement rctr, TOSR holds.
            sp_we[NUM_PRED_SLOTS + s]      = 1'b1;
            sp_waddr[NUM_PRED_SLOTS + s]   = w_tosr;
            sp_wdata_a[NUM_PRED_SLOTS + s] = w_top_addr;
            sp_wdata_r[NUM_PRED_SLOTS + s] = w_top_rctr -
                            {{(RAS_RCTR_WIDTH-1){1'b0}}, 1'b1};
            w_top_rctr = sp_wdata_r[NUM_PRED_SLOTS + s];
          end else begin
            // Normal pop: TOSR decrements, no data overwritten.
            w_tosr = w_tosr - {{(RAS_PTR_BITS-1){1'b0}}, 1'b1};
            if (w_tosr != bos) begin
              w_top_addr = spec_ret_addr[w_tosr];
              w_top_rctr = spec_rctr[w_tosr];
              w_valid    = 1'b1;
            end else begin
              w_top_addr = '0;
              w_top_rctr = '0;
              w_valid    = 1'b0;
            end
          end
        end
      end

      // Post-op snapshot for this slot (BOS unchanged across p2).
      ras_snapshot_p2[s].tosr = w_tosr;
      ras_snapshot_p2[s].tosw = w_tosw;
      ras_snapshot_p2[s].bos  = bos;
    end

    nxt_tosr = w_tosr;
    nxt_tosw = w_tosw;
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
      end
      for (int i = 0; i < RAS_COMMIT_ENTRIES; i++) begin
        commit_ret_addr[i] <= '0;
        commit_rctr[i]     <= '0;
      end
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        p3_op_q[s]      <= OP_NONE;
        p3_fallthr_q[s] <= '0;
      end
    end else begin
      ras_rst_done <= 1'b1;

      // ---- speculative pointers and array writes -----------------
      if (ras_restore_val) begin
        // Pointer-only restore; circular data is not cleared.
        tosr <= ras_restore_snapshot.tosr;
        tosw <= ras_restore_snapshot.tosw;
      end else begin
        tosr <= nxt_tosr;
        tosw <= nxt_tosw;
        // Apply repair writes [0..N-1] then p2 writes [N..2N-1] so
        // that a same-index p2 write supersedes the repair write.
        for (int p = 0; p < RAS_WR_PORTS; p++) begin
          if (sp_we[p]) begin
            spec_ret_addr[sp_waddr[p]] <= sp_wdata_a[p];
            spec_rctr[sp_waddr[p]]     <= sp_wdata_r[p];
          end
        end
      end

      // ---- committed boundary (BOS): restore > commit > hold -----
      if (ras_restore_val) begin
        bos <= ras_restore_snapshot.bos;
      end else if (ras_commit_val &
                   ((ras_commit_br_type == DIRECT_CALL) |
                    (ras_commit_br_type == INDIRECT_CALL) |
                    (ras_commit_br_type == RETURN))) begin
        // Committing entry's post-op TOSR is the new boundary.
        bos <= ras_commit_snapshot.tosr;
      end

      // ---- commit stack (independent of restore / p2) ------------
      if (ras_commit_val) begin
        if ((ras_commit_br_type == DIRECT_CALL) |
            (ras_commit_br_type == INDIRECT_CALL)) begin
          commit_ret_addr[csp] <= ras_commit_ret_addr;
          commit_rctr[csp]     <= '0;
          csp <= csp + {{(RAS_COMMIT_PTR_BITS-1){1'b0}}, 1'b1};
        end else if (ras_commit_br_type == RETURN) begin
          if (csp != '0)
            csp <= csp - {{(RAS_COMMIT_PTR_BITS-1){1'b0}}, 1'b1};
        end
      end

      // ---- register p2 op and fallthrough for the p3 repair pass -
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        p3_op_q[s]      <= p2_op[s];
        p3_fallthr_q[s] <= ras_fall_through_p2[s];
      end
    end
  end

endmodule : ras
