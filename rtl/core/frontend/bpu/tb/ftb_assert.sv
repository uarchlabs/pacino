// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for the ftb top (BP-140): the split at update.
//
// BOUND BY MODULE NAME, never by instance name (TD#109). The bind
// connects the ftb top's ports and its own storage-facing nets
// (array_wr_en_n, array_wr_addr, array_rd_addr) by name in its own
// scope; it makes no hierarchical reference.
//
// FA1 is checked against a model INDEPENDENT OF THE UPDATE LOGIC that
// drives the entry: the positions the update port presented to each
// stored entry since that entry was allocated, kept here per (set,
// way). An entry's set and way are where the array write landed; its
// allocation is a write to a (set, way) whose last writer was another
// start PC. The model does not read ftb_cntrl's field mapping, its
// split, its end or its hit decision. The checked values are the
// prediction ports of a later lookup of that entry.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftb_assert (
  input logic                       clk,
  input logic                       rstn,
  // -- prediction request and the ports a hit reports
  input logic                       pred_valid_p0,
  input logic [VA_WIDTH-1:0]        pred_pc_p0,
  input logic                       ftb_valid_p2,
  input logic [FTB_WAY_BITS-1:0]    ftb_way_p2,
  input logic                       ftb_br0_valid_p2,
  input logic [FTB_BR_POS_BITS-1:0] ftb_br0_pos_p2,
  input logic                       ftb_br1_valid_p2,
  input logic [FTB_BR_POS_BITS-1:0] ftb_br1_pos_p2,
  input logic                       ftb_jmp_valid_p2,
  input logic [FTB_BR_POS_BITS-1:0] ftb_jmp_pos_p2,
  input logic [VA_WIDTH-1:0]        ftb_pft_addr_p2,
  // -- the update port
  input logic                       ftb_upd_valid_u0,
  input logic [VA_WIDTH-1:0]        ftb_upd_pc_u0,
  input logic [FTB_WAY_BITS-1:0]    ftb_upd_way_u0,
  input logic                       ftb_upd_is_br_u0,
  input logic                       ftb_upd_is_jmp_u0,
  input logic [FTB_BR_POS_BITS-1:0] ftb_upd_pos_u0,
  // -- the storage the ftb top wires (array_* group)
  input logic                       array_wr_en_n,
  input logic [FTB_IDX_BITS-1:0]    array_wr_addr,
  input logic [FTB_IDX_BITS-1:0]    array_rd_addr
);

  localparam int N_POS = 1 << FTB_BR_POS_BITS;

  // The model, per (set, way): the start PC that last wrote it, and the
  // positions the update port presented to it since its allocation.
  logic                m_v   [FTB_SETS][FTB_WAYS];
  logic [VA_WIDTH-1:0] m_pc  [FTB_SETS][FTB_WAYS];
  logic [N_POS-1:0]    m_pos [FTB_SETS][FTB_WAYS];

  // The lookup PC and the set the prediction read, staged to p2. The
  // read address is the prediction's in the cycle after p0 (ftb_cntrl
  // drives array_rd_addr from the p1 PC unless an update borrows the
  // port, and then ftb_valid_p2 is 0).
  logic [VA_WIDTH-1:0]     r_pc_p1;
  logic [VA_WIDTH-1:0]     r_pc_p2;
  logic [FTB_IDX_BITS-1:0] r_set_p2;

  always_ff @(posedge clk) begin
    if (!rstn) begin
      r_pc_p1  <= '0;
      r_pc_p2  <= '0;
      r_set_p2 <= '0;
      for (int i = 0; i < FTB_SETS; i++)
        for (int w = 0; w < FTB_WAYS; w++) begin
          m_v[i][w]   <= 1'b0;
          m_pc[i][w]  <= '0;
          m_pos[i][w] <= '0;
        end
    end else begin
      r_pc_p1  <= pred_pc_p0;
      r_pc_p2  <= r_pc_p1;
      r_set_p2 <= array_rd_addr;
      if (!array_wr_en_n && ftb_upd_valid_u0) begin
        m_v [array_wr_addr][ftb_upd_way_u0] <= 1'b1;
        m_pc[array_wr_addr][ftb_upd_way_u0] <= ftb_upd_pc_u0;
        if (m_v[array_wr_addr][ftb_upd_way_u0] &&
            (m_pc[array_wr_addr][ftb_upd_way_u0] == ftb_upd_pc_u0))
          m_pos[array_wr_addr][ftb_upd_way_u0]
            <= m_pos[array_wr_addr][ftb_upd_way_u0]
             | ((ftb_upd_is_br_u0 | ftb_upd_is_jmp_u0)
                ? (N_POS'(1) << ftb_upd_pos_u0) : '0);
        else
          m_pos[array_wr_addr][ftb_upd_way_u0]
            <= (ftb_upd_is_br_u0 | ftb_upd_is_jmp_u0)
             ? (N_POS'(1) << ftb_upd_pos_u0) : '0;
      end
    end
  end

  // The lookup's entry as the model holds it, the branches the ports
  // report, and the checks.
  logic                w_ent;
  logic [N_POS-1:0]    w_res;
  logic [N_POS-1:0]    w_held;
  int                  w_nheld;
  logic                w_end_bad;
  logic [VA_WIDTH-1:0] w_bad_pc;

  always_comb begin : model_read
    w_ent  = m_v[r_set_p2][ftb_way_p2] && (m_pc[r_set_p2][ftb_way_p2]
                                           == r_pc_p2);
    w_res  = m_pos[r_set_p2][ftb_way_p2];
    w_held = '0;
    if (ftb_br0_valid_p2) w_held[ftb_br0_pos_p2] = 1'b1;
    if (ftb_br1_valid_p2) w_held[ftb_br1_pos_p2] = 1'b1;
    if (ftb_jmp_valid_p2) w_held[ftb_jmp_pos_p2] = 1'b1;
    w_nheld = int'(ftb_br0_valid_p2) + int'(ftb_br1_valid_p2)
            + int'(ftb_jmp_valid_p2);
    // A position presented to this entry and not reported must lie at
    // or above the end: the end is not beyond its PC.
    w_end_bad = 1'b0;
    w_bad_pc  = '0;
    for (int p = 0; p < N_POS; p++) begin
      if (w_res[p] && !w_held[p] &&
          (ftb_pft_addr_p2 > r_pc_p2 + (VA_WIDTH'(p) << POS_OFFSET_BITS))
          && !w_end_bad) begin
        w_end_bad = 1'b1;
        w_bad_pc  = r_pc_p2 + (VA_WIDTH'(p) << POS_OFFSET_BITS);
      end
    end
  end

  // FA1 BP-140, the split at update (ruled by Jeff 2026-10-18). A valid
  // FTB entry holds at most NUM_PRED_SLOTS branches, and its end is not
  // beyond the PC of any branch that resolved into it (from its start)
  // and that it does not hold. Before BP-140 an entry held up to two
  // conditionals and a jump at both slot counts, and its end was the
  // last update's.
  property p_fa1_count;
    @(posedge clk) disable iff (!rstn)
      ftb_valid_p2 |-> (w_nheld <= NUM_PRED_SLOTS);
  endproperty
  a_fa1_count: assert property (p_fa1_count)
    else $error("FA1 entry for %h holds %0d branches", r_pc_p2, w_nheld);

  property p_fa1_end;
    @(posedge clk) disable iff (!rstn)
      (ftb_valid_p2 && w_ent) |-> !w_end_bad;
  endproperty
  a_fa1_end: assert property (p_fa1_end)
    else $error("FA1 entry for %h ends at %h past the unheld branch at %h",
                r_pc_p2, ftb_pft_addr_p2, w_bad_pc);

  // pred_valid_p0 is staged by ftb_cntrl; the model reads the PC alone.
  logic w_unused;
  assign w_unused = pred_valid_p0;

endmodule : ftb_assert

// Bind BY MODULE NAME.
bind ftb ftb_assert u_ftb_assert (
  .clk               (clk),
  .rstn              (rstn),
  .pred_valid_p0     (pred_valid_p0),
  .pred_pc_p0        (pred_pc_p0),
  .ftb_valid_p2      (ftb_valid_p2),
  .ftb_way_p2        (ftb_way_p2),
  .ftb_br0_valid_p2  (ftb_br0_valid_p2),
  .ftb_br0_pos_p2    (ftb_br0_pos_p2),
  .ftb_br1_valid_p2  (ftb_br1_valid_p2),
  .ftb_br1_pos_p2    (ftb_br1_pos_p2),
  .ftb_jmp_valid_p2  (ftb_jmp_valid_p2),
  .ftb_jmp_pos_p2    (ftb_jmp_pos_p2),
  .ftb_pft_addr_p2   (ftb_pft_addr_p2),
  .ftb_upd_valid_u0  (ftb_upd_valid_u0),
  .ftb_upd_pc_u0     (ftb_upd_pc_u0),
  .ftb_upd_way_u0    (ftb_upd_way_u0),
  .ftb_upd_is_br_u0  (ftb_upd_is_br_u0),
  .ftb_upd_is_jmp_u0 (ftb_upd_is_jmp_u0),
  .ftb_upd_pos_u0    (ftb_upd_pos_u0),
  .array_wr_en_n     (array_wr_en_n),
  .array_wr_addr     (array_wr_addr),
  .array_rd_addr     (array_rd_addr)
);
