// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    ftb.sv
// DATE:    2026-06-25
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// FTB top (BP-067). STRUCTURAL ONLY.
//
// This module contains exactly three instances and the nets that wire
// them together:
//   - ftb_array : pure 1R1W DATA RAM (BP-065a, no reset)
//   - ftb_plru  : entry-valid + tree-PLRU flops (BP-065a, resettable)
//   - ftb_cntrl : the only logic (BP-066)
//
// There is NO logic in this module: no always blocks, no logic-bearing
// assigns. ftb_cntrl drives the two storage peers; the top simply
// connects its array_* port group to ftb_array and its plru_* port
// group to ftb_plru, and passes ftb_cntrl's functional ports through to
// the top boundary (ftb_interfaces.md 2, ftb_decisions.md 2.4).
//
// Substitution invariant (IC-FTB-12, ftb_decisions.md 2.4): the top is
// the only place wiring ftb_cntrl <-> ftb_array and ftb_cntrl <->
// ftb_plru. A 1R1W SRAM macro of the same port list may replace
// ftb_array without changing ftb_cntrl or its connections.
//
// Reset routing (IC-FTB-13): rstn goes to ftb_plru and ftb_cntrl only.
// ftb_array is pure RAM and has clk only -- it is NOT reset. clk goes
// to all three.
//
// ftb_fastpath_en (added to ftb_cntrl in BP-066) is threaded from the
// top boundary straight to ftb_cntrl. It is a top port beyond the
// current ftb_interfaces.md draft (source TBD, confidence doc 10).
// ===================================================================
`ifndef FTB_SV
`define FTB_SV

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftb (
  input  logic                          clk,
  input  logic                          rstn,

  // -- prediction request (ftb_interfaces.md 2.2; s0 in)
  input  logic                          pred_valid_p0,
  input  logic [VA_WIDTH-1:0]           pred_pc_p0,

  // -- prediction outputs (2.3; at s2)
  output logic                          ftb_valid_p2,
  output logic                          ftb_hit_p2,
  output logic [FTB_WAY_BITS-1:0]       ftb_way_p2,

  output logic                          ftb_br0_valid_p2,
  output logic [FTB_BR_POS_BITS-1:0]    ftb_br0_pos_p2,
  output logic                          ftb_br0_taken_p2,
  output logic [FTB_CONF_WIDTH-1:0]     ftb_br0_conf_p2,
  output logic [VA_WIDTH-1:0]           ftb_br0_target_p2,

  output logic                          ftb_br1_valid_p2,
  output logic [FTB_BR_POS_BITS-1:0]    ftb_br1_pos_p2,
  output logic                          ftb_br1_taken_p2,
  output logic [FTB_CONF_WIDTH-1:0]     ftb_br1_conf_p2,
  output logic [VA_WIDTH-1:0]           ftb_br1_target_p2,

  output logic                          ftb_jmp_valid_p2,
  output logic [FTB_BR_POS_BITS-1:0]    ftb_jmp_pos_p2,
  output logic [VA_WIDTH-1:0]           ftb_jmp_target_p2,
  output logic                          ftb_is_call_p2,
  output logic                          ftb_is_ret_p2,
  output logic                          ftb_is_jalr_p2,

  output logic [VA_WIDTH-1:0]           ftb_pft_addr_p2,

  // -- confidence fast-path (2.4); bit0 br0, bit1 br1
  output logic [1:0]                    ftb_fastpath_p2,

  // -- global fast-path enable (confidence section 5/10; 1 enables the
  //    bypass; top port beyond the current interface draft, source TBD)
  input  logic                          ftb_fastpath_en,

  // -- update port (2.5; post-execute, single port)
  input  logic                          ftb_upd_valid_u0,
  input  logic [VA_WIDTH-1:0]           ftb_upd_pc_u0,
  input  logic                          ftb_upd_hit_u0,
  input  logic [FTB_WAY_BITS-1:0]       ftb_upd_way_u0,
  input  logic                          ftb_upd_is_br_u0,
  input  logic                          ftb_upd_br_idx_u0,
  input  logic                          ftb_upd_taken_u0,
  input  logic [VA_WIDTH-1:0]           ftb_upd_target_u0,
  input  logic [FTB_BR_POS_BITS-1:0]    ftb_upd_pos_u0,
  input  logic                          ftb_upd_is_jmp_u0,
  input  logic [VA_WIDTH-1:0]           ftb_upd_jmp_target_u0,
  input  logic                          ftb_upd_is_call_u0,
  input  logic                          ftb_upd_is_ret_u0,
  input  logic                          ftb_upd_is_jalr_u0,
  input  logic [VA_WIDTH-1:0]           ftb_upd_pft_addr_u0,

  // -- flush (2.6; stub, IC-FTB-07)
  input  logic                          ftb_flush_px
);

  // ----------------------------------------------------------------
  // Internal nets: ftb_cntrl <-> ftb_array (array_* port group).
  // ----------------------------------------------------------------
  logic                          array_rd_en_n;
  logic [FTB_IDX_BITS-1:0]       array_rd_addr;
  logic [FTB_RAM_SET_WIDTH-1:0]  array_rd_data;
  logic                          array_wr_en_n;
  logic [FTB_IDX_BITS-1:0]       array_wr_addr;
  logic [FTB_WAYS-1:0]           array_wr_way;
  logic [FTB_RAM_ENTRY_WIDTH-1:0] array_wr_data;

  // ----------------------------------------------------------------
  // Internal nets: ftb_cntrl <-> ftb_plru (plru_* port group).
  // ----------------------------------------------------------------
  logic                          plru_rd_en_n;
  logic [FTB_IDX_BITS-1:0]       plru_rd_addr;
  logic [FTB_WAYS-1:0]           plru_rd_valid;
  logic [PLRU_BITS-1:0]          plru_rd_plru;
  logic                          plru_val_we_n;
  logic [FTB_IDX_BITS-1:0]       plru_val_addr;
  logic [FTB_WAYS-1:0]           plru_val_way;
  logic                          plru_val_set;
  logic                          plru_plru_we_n;
  logic [FTB_IDX_BITS-1:0]       plru_plru_addr;
  logic [PLRU_BITS-1:0]          plru_plru_wdata;

  // ----------------------------------------------------------------
  // ftb_array: pure 1R1W DATA RAM. clk only -- NO rstn (IC-FTB-13).
  // ----------------------------------------------------------------
  ftb_array u_ftb_array (
    .clk      (clk),
    .rd_en_n  (array_rd_en_n),
    .rd_addr  (array_rd_addr),
    .rd_data  (array_rd_data),
    .wr_en_n  (array_wr_en_n),
    .wr_addr  (array_wr_addr),
    .wr_way   (array_wr_way),
    .wr_data  (array_wr_data)
  );

  // ----------------------------------------------------------------
  // ftb_plru: entry-valid + tree-PLRU flops. clk and rstn.
  // ----------------------------------------------------------------
  ftb_plru u_ftb_plru (
    .clk        (clk),
    .rstn       (rstn),
    .rd_en_n    (plru_rd_en_n),
    .rd_addr    (plru_rd_addr),
    .rd_valid   (plru_rd_valid),
    .rd_plru    (plru_rd_plru),
    .val_we_n   (plru_val_we_n),
    .val_addr   (plru_val_addr),
    .val_way    (plru_val_way),
    .val_set    (plru_val_set),
    .plru_we_n  (plru_plru_we_n),
    .plru_addr  (plru_plru_addr),
    .plru_wdata (plru_plru_wdata)
  );

  // ----------------------------------------------------------------
  // ftb_cntrl: the only logic. Drives both storage peers; exposes the
  // functional FTB port list at the top boundary. clk and rstn.
  // ----------------------------------------------------------------
  ftb_cntrl u_ftb_cntrl (
    .clk                     (clk),
    .rstn                    (rstn),

    // prediction request
    .pred_valid_p0           (pred_valid_p0),
    .pred_pc_p0              (pred_pc_p0),

    // prediction outputs
    .ftb_valid_p2            (ftb_valid_p2),
    .ftb_hit_p2              (ftb_hit_p2),
    .ftb_way_p2              (ftb_way_p2),
    .ftb_br0_valid_p2        (ftb_br0_valid_p2),
    .ftb_br0_pos_p2          (ftb_br0_pos_p2),
    .ftb_br0_taken_p2        (ftb_br0_taken_p2),
    .ftb_br0_conf_p2         (ftb_br0_conf_p2),
    .ftb_br0_target_p2       (ftb_br0_target_p2),
    .ftb_br1_valid_p2        (ftb_br1_valid_p2),
    .ftb_br1_pos_p2          (ftb_br1_pos_p2),
    .ftb_br1_taken_p2        (ftb_br1_taken_p2),
    .ftb_br1_conf_p2         (ftb_br1_conf_p2),
    .ftb_br1_target_p2       (ftb_br1_target_p2),
    .ftb_jmp_valid_p2        (ftb_jmp_valid_p2),
    .ftb_jmp_pos_p2          (ftb_jmp_pos_p2),
    .ftb_jmp_target_p2       (ftb_jmp_target_p2),
    .ftb_is_call_p2          (ftb_is_call_p2),
    .ftb_is_ret_p2           (ftb_is_ret_p2),
    .ftb_is_jalr_p2          (ftb_is_jalr_p2),
    .ftb_pft_addr_p2         (ftb_pft_addr_p2),

    // fast-path output + enable
    .ftb_fastpath_p2         (ftb_fastpath_p2),
    .ftb_fastpath_en         (ftb_fastpath_en),

    // update port
    .ftb_upd_valid_u0        (ftb_upd_valid_u0),
    .ftb_upd_pc_u0           (ftb_upd_pc_u0),
    .ftb_upd_hit_u0          (ftb_upd_hit_u0),
    .ftb_upd_way_u0          (ftb_upd_way_u0),
    .ftb_upd_is_br_u0        (ftb_upd_is_br_u0),
    .ftb_upd_br_idx_u0       (ftb_upd_br_idx_u0),
    .ftb_upd_taken_u0        (ftb_upd_taken_u0),
    .ftb_upd_target_u0       (ftb_upd_target_u0),
    .ftb_upd_pos_u0          (ftb_upd_pos_u0),
    .ftb_upd_is_jmp_u0       (ftb_upd_is_jmp_u0),
    .ftb_upd_jmp_target_u0   (ftb_upd_jmp_target_u0),
    .ftb_upd_is_call_u0      (ftb_upd_is_call_u0),
    .ftb_upd_is_ret_u0       (ftb_upd_is_ret_u0),
    .ftb_upd_is_jalr_u0      (ftb_upd_is_jalr_u0),
    .ftb_upd_pft_addr_u0     (ftb_upd_pft_addr_u0),

    // flush
    .ftb_flush_px            (ftb_flush_px),

    // ftb_array-facing ports
    .array_rd_en_n           (array_rd_en_n),
    .array_rd_addr           (array_rd_addr),
    .array_rd_data           (array_rd_data),
    .array_wr_en_n           (array_wr_en_n),
    .array_wr_addr           (array_wr_addr),
    .array_wr_way            (array_wr_way),
    .array_wr_data           (array_wr_data),

    // ftb_plru-facing ports
    .plru_rd_en_n            (plru_rd_en_n),
    .plru_rd_addr            (plru_rd_addr),
    .plru_rd_valid           (plru_rd_valid),
    .plru_rd_plru            (plru_rd_plru),
    .plru_val_we_n           (plru_val_we_n),
    .plru_val_addr           (plru_val_addr),
    .plru_val_way            (plru_val_way),
    .plru_val_set            (plru_val_set),
    .plru_plru_we_n          (plru_plru_we_n),
    .plru_plru_addr          (plru_plru_addr),
    .plru_plru_wdata         (plru_plru_wdata)
  );

endmodule : ftb

`endif // FTB_SV
