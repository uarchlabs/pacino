// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ras (BP-122, TD#170): the BP-121 fix in this
// unit, ras_p2_keep (FE-14, BP-121 D8); and since BP-138 the p2 pop
// against the entries the speculative stack holds (RS2, RS3).
//
// BOUND BY MODULE NAME, never by instance name (TD#109). The bind
// connects the module's ports and its own state signals by name in
// its own scope (tosr, tosw, bos, p3_op_q, the arrays and the commit
// stack pointer and count); it makes no hierarchical reference.
//
// The source of RS1 is an earlier cycle: the pointers this module
// registered the cycle before, not the next-state expression of
// ras.sv. The source of RS2 and RS3 is an allocation order this module
// keeps itself from the TOSW and BOS history (see below), not the
// empty test of ras.sv (TOSR == BOS) or the rules that keep it exact.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ras_assert (
  input logic                    clk,
  input logic                    rstn,
  input logic                    ras_p2_keep,
  input logic                    ras_restore_val,
  input logic                    ras_pred_val_p3 [0:NUM_PRED_SLOTS-1],
  input bp_br_type_e             ras_br_type_p3  [0:NUM_PRED_SLOTS-1],
  input logic [RAS_PTR_BITS-1:0] tosr,
  input logic [RAS_PTR_BITS-1:0] tosw,
  input logic [1:0]              p3_op_q [0:NUM_PRED_SLOTS-1],
  // RS2, RS3 (BP-138).
  input logic                    ras_pred_val_p2  [0:NUM_PRED_SLOTS-1],
  input bp_br_type_e             ras_br_type_p2   [0:NUM_PRED_SLOTS-1],
  input logic                    ras_pop_valid_p2 [0:NUM_PRED_SLOTS-1],
  input logic [VA_WIDTH-1:0]     ras_pop_addr_p2  [0:NUM_PRED_SLOTS-1],
  input logic [RAS_PTR_BITS-1:0] bos,
  input logic [VA_WIDTH-1:0]     spec_ret_addr    [0:RAS_SPEC_ENTRIES-1],
  input logic [VA_WIDTH-1:0]     commit_ret_addr  [0:RAS_COMMIT_ENTRIES-1],
  input logic [RAS_COMMIT_PTR_BITS-1:0] csp,
  input logic [RAS_COMMIT_PTR_BITS:0]   c_cnt
);

  // The cycle before: the p2 pass was dropped and nothing else could
  // move the speculative pointers: no restore, and no p3 repair. The
  // repair acts only where the p3 view of a slot (push for a call,
  // pop for a return, both for a return-call, ras_decisions.md 1)
  // differs from the operation registered at p2, so the view is
  // derived here from the p3 inputs and compared.
  logic                    r_quiet;
  logic [RAS_PTR_BITS-1:0] r_tosr;
  logic [RAS_PTR_BITS-1:0] r_tosw;
  logic                    w_quiet;
  // No p3 repair this cycle: every slot's p3 view equals its
  // registered p2 operation (RS1, RS2, RS3).
  logic                    w_rep_idle;

  always_comb begin : quiet
    logic [1:0] view;
    w_rep_idle = 1'b1;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      view = 2'b00;
      if (ras_pred_val_p3[s]) begin
        case (ras_br_type_p3[s])
          DIRECT_CALL, INDIRECT_CALL: view = 2'b01;
          RETURN:                     view = 2'b10;
          RETURN_CALL:                view = 2'b11;
          default:                    view = 2'b00;
        endcase
      end
      if (view != p3_op_q[s]) w_rep_idle = 1'b0;
    end
    w_quiet = !ras_p2_keep && !ras_restore_val && w_rep_idle;
  end

  // -----------------------------------------------------------------
  // RS2 / RS3 model (BP-138): the order in which the speculative
  // entries were allocated, kept here from the TOSW and BOS history.
  // TOSW only moves forward except on a restore, and every index it
  // moves past is allocated in that order, except BOS: the sentinel
  // skip moves TOSW past BOS without writing it (ras_decisions.md 3.2).
  // Each index carries the sequence number of its last allocation;
  // reset gives every index 0. r_rst: the edge into this cycle applied
  // a restore, so the TOSW move it made allocated nothing. r_bos: BOS
  // in the cycle before, the one the skip compared against.
  //
  // The speculative stack holds TOSR when TOSR was allocated after
  // BOS: BOS is the committed boundary, so an entry allocated before
  // it is committed state or popped past. The sequence numbers do not
  // wrap. ras.sv answers the same question with TOSR != BOS and the
  // rules that keep that exact (THE BOTTOM in ras.sv); this model reads
  // neither.
  // -----------------------------------------------------------------
  localparam int SEQ_W = 32;
  logic [SEQ_W-1:0]        r_seq [0:RAS_SPEC_ENTRIES-1];
  logic [SEQ_W-1:0]        r_gen;
  logic                    r_rst;
  logic [RAS_PTR_BITS-1:0] r_bos;
  logic [SEQ_W-1:0]        w_seq [0:RAS_SPEC_ENTRIES-1];
  logic [SEQ_W-1:0]        w_gen;
  logic                    w_held;
  // A slot whose pop reads TOSR as the cycle starts: no repair, and no
  // RAS operation in a lower slot.
  logic                    w_first [0:NUM_PRED_SLOTS-1];
  logic [RAS_COMMIT_PTR_BITS-1:0] w_ctop;

  always_comb begin : alloc_order
    logic [RAS_PTR_BITS-1:0] n;
    logic [RAS_PTR_BITS-1:0] d;
    logic                    op;
    n     = r_rst ? '0 : (tosw - r_tosw);   // indices allocated
    w_gen = r_gen;
    for (int i = 0; i < RAS_SPEC_ENTRIES; i++) begin
      d = RAS_PTR_BITS'(i) - r_tosw;       // position past old TOSW
      w_seq[i] = ((d < n) && (RAS_PTR_BITS'(i) != r_bos))
                   ? (r_gen + SEQ_W'(d) + SEQ_W'(1)) : r_seq[i];
    end
    w_gen  = r_gen + SEQ_W'(n);
    w_held = w_seq[tosr] > w_seq[bos];
    op     = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      w_first[s] = w_rep_idle && !op;
      op = op || (ras_pred_val_p2[s] &&
                  (ras_br_type_p2[s] inside {DIRECT_CALL, INDIRECT_CALL,
                                             RETURN, RETURN_CALL}));
    end
    w_ctop = csp - RAS_COMMIT_PTR_BITS'(1);
  end

  always_ff @(posedge clk) begin : hist
    if (!rstn) begin
      r_quiet <= 1'b0;
      r_tosr  <= '0;
      r_tosw  <= '0;
      r_rst   <= 1'b0;
      r_bos   <= '0;
      r_gen   <= '0;
      for (int i = 0; i < RAS_SPEC_ENTRIES; i++) r_seq[i] <= '0;
    end else begin
      r_quiet <= w_quiet;
      r_tosr  <= tosr;
      r_tosw  <= tosw;
      r_rst   <= ras_restore_val;
      r_bos   <= bos;
      r_gen   <= w_gen;
      for (int i = 0; i < RAS_SPEC_ENTRIES; i++) r_seq[i] <= w_seq[i];
    end
  end

  // RS1 BP-121 D8 (m08), FE-14. A block a redirect squashes at p2
  //     makes no RAS operation: with ras_p2_keep low, and no restore
  //     and no p3 repair that cycle, the speculative pointers do not
  //     move, whatever the p2 inputs ask for. Before BP-121 the
  //     squashed block still pushed or popped on the restored stack.
  property p_dropped_p2_moves_nothing;
    @(posedge clk) disable iff (!rstn)
      r_quiet |-> (tosr == r_tosr) && (tosw == r_tosw);
  endproperty

  a_dropped_p2_moves_nothing: assert property (p_dropped_p2_moves_nothing)
    else $error("RS1 a squashed p2 block moved the RAS pointers");

  // RS2 BP-138 (D2), ras_decisions.md 3.2. A valid p2 pop never returns
  //     an entry the speculative stack does not hold: when the model
  //     above says TOSR is not allocated after BOS, the pop is the
  //     commit-stack fallback -- valid only with the commit stack
  //     non-empty, and its top. Before BP-138 a commit that moved BOS
  //     past an empty stack left TOSR != BOS on the old BOS slot and
  //     the pop returned it (fd07: a return to 0x0).
  // RS3 BP-138. The converse: when the model says the stack holds
  //     TOSR, the pop is valid and returns that entry, so the fix for
  //     RS2 does not empty a stack that holds entries.
  // Checked for a slot whose pop reads TOSR as the cycle starts.
  for (genvar gs = 0; gs < NUM_PRED_SLOTS; gs++) begin : g_rs
    a_pop_only_held: assert property (
      @(posedge clk) disable iff (!rstn)
        (w_first[gs] && ras_pop_valid_p2[gs] && !w_held)
          |-> (c_cnt != '0) &&
              (ras_pop_addr_p2[gs] == commit_ret_addr[w_ctop]))
      else $error("RS2 slot %0d popped tosr %0d, which bos %0d excludes",
                  gs, tosr, bos);

    a_held_pops_top: assert property (
      @(posedge clk) disable iff (!rstn)
        (w_first[gs] && ras_pred_val_p2[gs] && w_held &&
         (ras_br_type_p2[gs] inside {RETURN, RETURN_CALL}))
          |-> ras_pop_valid_p2[gs] &&
              (ras_pop_addr_p2[gs] == spec_ret_addr[tosr]))
      else $error("RS3 slot %0d did not pop held tosr %0d (bos %0d)",
                  gs, tosr, bos);
  end

endmodule : ras_assert

// Bind BY MODULE NAME.
bind ras ras_assert u_assert (
  .clk              (clk),
  .rstn             (rstn),
  .ras_p2_keep      (ras_p2_keep),
  .ras_restore_val  (ras_restore_val),
  .ras_pred_val_p3  (ras_pred_val_p3),
  .ras_br_type_p3   (ras_br_type_p3),
  .tosr             (tosr),
  .tosw             (tosw),
  .p3_op_q          (p3_op_q),
  .ras_pred_val_p2  (ras_pred_val_p2),
  .ras_br_type_p2   (ras_br_type_p2),
  .ras_pop_valid_p2 (ras_pop_valid_p2),
  .ras_pop_addr_p2  (ras_pop_addr_p2),
  .bos              (bos),
  .spec_ret_addr    (spec_ret_addr),
  .commit_ret_addr  (commit_ret_addr),
  .csp              (csp),
  .c_cnt            (c_cnt)
);
