// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// IFU writeback stage, WB (BP-116). ifu_decisions.md IFU-9, IFU-10,
// IFU-13, IFU-14, IFU-19, IFU-20; ftq_ifu_interfaces.md 6, 6.1.
//
// OWNS the WB register. The block that transferred to the ibuf at F3
// presents its predecode writeback the next cycle, for one cycle.
// The FTQ accepts it in that cycle (ftq_ifu_interfaces.md 8 item 5:
// no ready).
//
// IFU-19. The generation bit is the one the request carried, captured
// at F0 and passed through unchanged. It is not decoded here.
//
// IFU-20. One bit of generation is enough only because a stale
// writeback cannot outlive the flush cycle. A writeback already in
// this register is presented in the flush cycle; nothing is loaded
// in a flush cycle (F3 does not transfer then), so none follows it.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ifu_wb (
  input  logic                     clk,
  input  logic                     rstn,
  input  logic                     flush,

  // ---- from ifu_f3 ---------------------------------------------------
  input  logic                     wb_load,
  input  logic [FTQ_IDX_BITS-1:0]  wb_idx,
  input  logic                     wb_gen,
  input  ftq_pd_info_t             wb_pd   [0:FTQ_PD_WIDTH-1],
  input  logic [FTQ_PD_WIDTH-1:0]  wb_range,
  input  logic                     wb_cfi_val,
  input  logic [FTQ_PD_POS_BITS-1:0] wb_cfi_pos,
  input  logic                     wb_mis_val,
  input  logic [FTQ_PD_POS_BITS-1:0] wb_mis_pos,
  input  logic [VA_WIDTH-1:0]      wb_target,
  input  logic                     wb_fault_val,
  input  logic [FTQ_PD_POS_BITS-1:0] wb_fault_pos,

  // ---- ftq_ifu_interfaces.md 6 -------------------------------------
  output logic                     ifu_ftq_pdwb_val,
  output logic [FTQ_IDX_BITS-1:0]  ifu_ftq_pdwb_idx,
  output logic                     ifu_ftq_pdwb_gen,
  output ftq_pd_info_t             ifu_ftq_pd [0:FTQ_PD_WIDTH-1],
  output logic [FTQ_PD_WIDTH-1:0]  ifu_ftq_pd_range,
  output logic                     ifu_ftq_cfi_val,
  output logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_cfi_pos,
  output logic                     ifu_ftq_mis_val,
  output logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_mis_pos,
  output logic [VA_WIDTH-1:0]      ifu_ftq_target,
  output logic                     ifu_ftq_fault_val,
  output logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_fault_pos
);

  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      ifu_ftq_pdwb_val  <= 1'b0;
      ifu_ftq_pdwb_idx  <= '0;
      ifu_ftq_pdwb_gen  <= 1'b0;
      ifu_ftq_pd_range  <= '0;
      ifu_ftq_cfi_val   <= 1'b0;
      ifu_ftq_cfi_pos   <= '0;
      ifu_ftq_mis_val   <= 1'b0;
      ifu_ftq_mis_pos   <= '0;
      ifu_ftq_target    <= '0;
      ifu_ftq_fault_val <= 1'b0;
      ifu_ftq_fault_pos <= '0;
      for (int i = 0; i < FTQ_PD_WIDTH; i++) ifu_ftq_pd[i] <= '0;
    end else begin
      ifu_ftq_pdwb_val <= wb_load && !flush;
      if (wb_load && !flush) begin
        ifu_ftq_pdwb_idx  <= wb_idx;
        ifu_ftq_pdwb_gen  <= wb_gen;
        ifu_ftq_pd_range  <= wb_range;
        ifu_ftq_cfi_val   <= wb_cfi_val;
        ifu_ftq_cfi_pos   <= wb_cfi_pos;
        ifu_ftq_mis_val   <= wb_mis_val;
        ifu_ftq_mis_pos   <= wb_mis_pos;
        ifu_ftq_target    <= wb_target;
        ifu_ftq_fault_val <= wb_fault_val;
        ifu_ftq_fault_pos <= wb_fault_pos;
        for (int i = 0; i < FTQ_PD_WIDTH; i++) ifu_ftq_pd[i] <= wb_pd[i];
      end
    end
  end

endmodule : ifu_wb
