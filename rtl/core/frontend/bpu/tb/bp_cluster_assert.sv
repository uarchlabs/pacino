// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for bp_cluster (BP-139): the p2 block end against the
// branches the FTB reports (option A, the cut).
//
// BOUND BY MODULE NAME, never by instance name (TD#109). The bind
// connects the module's ports and its own p2 nets by name in its own
// scope; it makes no hierarchical reference.
//
// The source of CL1 is independent of the cut logic it checks: the
// FTB's own p2 outputs (the br0, br1 and jump fields as ftb.sv drives
// them) and the slot assignment the cluster publishes (bpu_slot_p2),
// not w_cut_p2, w_cut_pos_p2 or the w_pft_p2 selection.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module bp_cluster_assert (
  input logic                       clk,
  input logic                       rstn,
  input logic [VA_WIDTH-1:0]        r_pc_p2,
  input logic                       bpu_slot_val_p2,
  input bp_ftq_slot_t               bpu_slot_p2  [0:NUM_PRED_SLOTS-1],
  input bp_redirect_t               bpu_redir_p2 [0:NUM_PRED_SLOTS-1],
  input logic [VA_WIDTH-1:0]        bpu_blk_pft_p2,
  input logic                       w_ftb_br0_valid_p2,
  input logic [FTB_BR_POS_BITS-1:0] w_ftb_br0_pos_p2,
  input logic                       w_ftb_br1_valid_p2,
  input logic [FTB_BR_POS_BITS-1:0] w_ftb_br1_pos_p2,
  input logic                       w_ftb_jmp_valid_p2,
  input logic [FTB_BR_POS_BITS-1:0] w_ftb_jmp_pos_p2
);

  // The three FTB fields, in the order ftb.sv reports them.
  localparam int N_FLD = 3;

  // The PC of the first FTB-reported branch that no slot carries, and
  // whether there is one. A slot carries a field when it is valid at
  // the field's start-relative position.
  logic                       w_unslot;
  logic [VA_WIDTH-1:0]        w_unslot_pc;
  // Per slot: no slot at or after it is predicted taken, so its
  // successor is the block's not-taken end.
  logic                       w_nt_path [0:NUM_PRED_SLOTS-1];

  always_comb begin : unslot
    logic                       f_val [0:N_FLD-1];
    logic [FTB_BR_POS_BITS-1:0] f_pos [0:N_FLD-1];
    logic                       carried;
    logic                       later_tkn;
    f_val[0] = w_ftb_br0_valid_p2;
    f_pos[0] = w_ftb_br0_pos_p2;
    f_val[1] = w_ftb_br1_valid_p2;
    f_pos[1] = w_ftb_br1_pos_p2;
    f_val[2] = w_ftb_jmp_valid_p2;
    f_pos[2] = w_ftb_jmp_pos_p2;
    w_unslot    = 1'b0;
    w_unslot_pc = '0;
    for (int f = 0; f < N_FLD; f++) begin
      carried = 1'b0;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        if (bpu_slot_p2[s].slot_valid && (bpu_slot_p2[s].pos == f_pos[f]))
          carried = 1'b1;
      end
      if (f_val[f] && !carried &&
          (!w_unslot ||
           (r_pc_p2 + (VA_WIDTH'(f_pos[f]) << POS_OFFSET_BITS)
            < w_unslot_pc))) begin
        w_unslot    = 1'b1;
        w_unslot_pc = r_pc_p2 + (VA_WIDTH'(f_pos[f]) << POS_OFFSET_BITS);
      end
    end
    later_tkn = 1'b0;
    for (int s = NUM_PRED_SLOTS - 1; s >= 0; s--) begin
      later_tkn    = later_tkn |
                     (bpu_slot_p2[s].slot_valid & bpu_slot_p2[s].taken);
      w_nt_path[s] = !later_tkn;
    end
  end

  // CL1 BP-139, option A. No not-taken path of a p2 block runs past a
  // branch the FTB reports and no slot carries: the block end is no
  // later than that branch's PC, and so is the successor of every slot
  // with no taken slot at or after it. Before BP-139 the cut covered
  // the jump only, so at one slot a conditional in br1 was stepped over
  // (fd09: the back edge).
  property p_no_step_over;
    @(posedge clk) disable iff (!rstn)
      (bpu_slot_val_p2 && w_unslot) |->
        (bpu_blk_pft_p2 <= w_unslot_pc);
  endproperty
  a_no_step_over: assert property (p_no_step_over)
    else $error("CL1 the block end %h steps over an unslotted branch at %h",
                bpu_blk_pft_p2, w_unslot_pc);

  genvar gs;
  for (gs = 0; gs < NUM_PRED_SLOTS; gs++) begin : g_slot
    property p_nt_succ_bounded;
      @(posedge clk) disable iff (!rstn)
        (bpu_slot_val_p2 && w_unslot && w_nt_path[gs]) |->
          (bpu_redir_p2[gs].target_pc <= w_unslot_pc);
    endproperty
    a_nt_succ_bounded: assert property (p_nt_succ_bounded)
      else $error("CL1 slot %0d successor %h steps over an unslotted %h",
                  gs, bpu_redir_p2[gs].target_pc, w_unslot_pc);
  end

endmodule : bp_cluster_assert

// Bind BY MODULE NAME.
bind bp_cluster bp_cluster_assert u_assert (
  .clk                (clk),
  .rstn               (rstn),
  .r_pc_p2            (r_pc_p2),
  .bpu_slot_val_p2    (bpu_slot_val_p2),
  .bpu_slot_p2        (bpu_slot_p2),
  .bpu_redir_p2       (bpu_redir_p2),
  .bpu_blk_pft_p2     (bpu_blk_pft_p2),
  .w_ftb_br0_valid_p2 (w_ftb_br0_valid_p2),
  .w_ftb_br0_pos_p2   (w_ftb_br0_pos_p2),
  .w_ftb_br1_valid_p2 (w_ftb_br1_valid_p2),
  .w_ftb_br1_pos_p2   (w_ftb_br1_pos_p2),
  .w_ftb_jmp_valid_p2 (w_ftb_jmp_valid_p2),
  .w_ftb_jmp_pos_p2   (w_ftb_jmp_pos_p2)
);
