// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ras (BP-122, TD#170): the BP-121 fix in this
// unit, ras_p2_keep (FE-14, BP-121 D8).
//
// BOUND BY MODULE NAME, never by instance name (TD#109). The bind
// connects the module's ports and three of its own state signals by
// name in its own scope (tosr, tosw, p3_op_q); it makes no
// hierarchical reference.
//
// The source is an earlier cycle: the pointers this module registered
// the cycle before, not the next-state expression of ras.sv.
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
  input logic [1:0]              p3_op_q [0:NUM_PRED_SLOTS-1]
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

  always_comb begin : quiet
    logic [1:0] view;
    w_quiet = !ras_p2_keep && !ras_restore_val;
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
      if (view != p3_op_q[s]) w_quiet = 1'b0;
    end
  end

  always_ff @(posedge clk) begin : hist
    if (!rstn) begin
      r_quiet <= 1'b0;
      r_tosr  <= '0;
      r_tosw  <= '0;
    end else begin
      r_quiet <= w_quiet;
      r_tosr  <= tosr;
      r_tosw  <= tosw;
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

endmodule : ras_assert

// Bind BY MODULE NAME.
bind ras ras_assert u_assert (
  .clk             (clk),
  .rstn            (rstn),
  .ras_p2_keep     (ras_p2_keep),
  .ras_restore_val (ras_restore_val),
  .ras_pred_val_p3 (ras_pred_val_p3),
  .ras_br_type_p3  (ras_br_type_p3),
  .tosr            (tosr),
  .tosw            (tosw),
  .p3_op_q         (p3_op_q)
);
