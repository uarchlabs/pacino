// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      l1i_bank.sv
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// One bank of node 'l1i'. 64 sets of 8 ways.
//
// There are 2 of these. R-6: the bank is chosen by address bits
// [6:6], taken out of the index rather than beside it.
//
// PACINO CHANGES (BP-123, CG-D1): req_unc, the uncached lookup, and
// inv_en / inv_all / inv_set, the invalidate, are passed to l1i_ctrl;
// the metadata array's inv_all is wired.
//--------------------------------------------------------------------
// The import is at file scope and before the module, which is what
// the project verilog style asks for. Verilator's IMPORTSTAR objects
// to a wildcard in $unit scope, so it is turned off across these
// lines and nowhere else.
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
/* verilator lint_on IMPORTSTAR */

module l1i_bank (
  input  logic  clk,
  input  logic  rstn,

  input  logic  req_valid,
  output logic  req_ready,
  input  l1i_addr_t req_addr,
  input  l1i_mshr_t req_src,
  input  logic  req_unc,        // L1I-24 (BP-123)

  // the invalidate, IF-29 and IF-42 (BP-123)
  input  logic  inv_en,
  input  logic  inv_all,
  input  l1i_set_t  inv_set,

  output logic  rsp_valid,
  output l1i_line_t rsp_data,
  output logic  rsp_err,
  output l1i_mshr_t rsp_src,

  output logic  mis_valid,
  output l1i_addr_t mis_line,
  output l1i_mshr_t mis_src,
  output l1i_way_t  mis_way,

  input  logic  fil_valid,
  input  l1i_addr_t fil_line,
  input  l1i_way_t  fil_way,
  input  l1i_line_t fil_data
);

  l1i_set_t        meta_rd_set;
  l1i_tag_t        meta_rd_tag   [L1iWays];
  logic        meta_rd_valid [L1iWays];
  l1i_repl_state_t meta_rd_repl;
  logic        meta_wr_en;
  l1i_set_t        meta_wr_set;
  l1i_way_t        meta_wr_way;
  l1i_tag_t        meta_wr_tag;
  logic        meta_wr_valid;
  logic        meta_rp_en;
  l1i_set_t        meta_rp_set;
  l1i_repl_state_t meta_rp_val;
  logic        meta_inv_en;
  logic        meta_inv_all;
  l1i_set_t        meta_inv_set;

  l1i_set_t        data_rd_set;
  l1i_line_t       data_rd_line [L1iWays];
  logic        data_wr_en;
  l1i_set_t        data_wr_set;
  l1i_way_t        data_wr_way;
  l1i_line_t       data_wr_line;

  l1i_meta_array u_meta (
    .clk           (clk),
    .rstn          (rstn),
    .rd_set        (meta_rd_set),
    .rd_tag        (meta_rd_tag),
    .rd_valid      (meta_rd_valid),
    .rd_repl       (meta_rd_repl),
    .wr_en         (meta_wr_en),
    .wr_set        (meta_wr_set),
    .wr_way        (meta_wr_way),
    .wr_tag        (meta_wr_tag),
    .wr_valid      (meta_wr_valid),
    .rp_en         (meta_rp_en),
    .rp_set        (meta_rp_set),
    .rp_val        (meta_rp_val),
    .inv_en        (meta_inv_en),
    .inv_all       (meta_inv_all),
    .inv_set       (meta_inv_set)
  );

  l1i_data_array u_data (
    .clk           (clk),
    .rd_set        (data_rd_set),
    .rd_line       (data_rd_line),
    .wr_en         (data_wr_en),
    .wr_set        (data_wr_set),
    .wr_way        (data_wr_way),
    .wr_line       (data_wr_line)
  );

  l1i_ctrl u_ctrl (
    .clk           (clk),
    .rstn          (rstn),
    .req_valid     (req_valid),
    .req_ready     (req_ready),
    .req_addr      (req_addr),
    .req_src       (req_src),
    .req_unc       (req_unc),
    .inv_en        (inv_en),
    .inv_all       (inv_all),
    .inv_set       (inv_set),
    .rsp_valid     (rsp_valid),
    .rsp_data      (rsp_data),
    .rsp_err       (rsp_err),
    .rsp_src       (rsp_src),
    .mis_valid     (mis_valid),
    .mis_line      (mis_line),
    .mis_src       (mis_src),
    .mis_way       (mis_way),
    .fil_valid     (fil_valid),
    .fil_line      (fil_line),
    .fil_way       (fil_way),
    .fil_data      (fil_data),
    .meta_rd_set   (meta_rd_set),
    .meta_rd_tag   (meta_rd_tag),
    .meta_rd_valid (meta_rd_valid),
    .meta_rd_repl  (meta_rd_repl),
    .meta_wr_en    (meta_wr_en),
    .meta_wr_set   (meta_wr_set),
    .meta_wr_way   (meta_wr_way),
    .meta_wr_tag   (meta_wr_tag),
    .meta_wr_valid (meta_wr_valid),
    .meta_rp_en    (meta_rp_en),
    .meta_rp_set   (meta_rp_set),
    .meta_rp_val   (meta_rp_val),
    .meta_inv_en   (meta_inv_en),
    .meta_inv_all  (meta_inv_all),
    .meta_inv_set  (meta_inv_set),
    .data_rd_set   (data_rd_set),
    .data_rd_line  (data_rd_line),
    .data_wr_en    (data_wr_en),
    .data_wr_set   (data_wr_set),
    .data_wr_way   (data_wr_way),
    .data_wr_line  (data_wr_line)
  );

endmodule
