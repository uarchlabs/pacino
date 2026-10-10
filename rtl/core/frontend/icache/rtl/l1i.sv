// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      l1i.sv
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// Node 'l1i', a icache.
//
// 1 slave interface, 2 banks, 1 master interface.
//
// THE CORE LINK IS NOT BLOCKING, so the miss handling file
// of l1i_mshr sits between the core adapter and the
// banks. It, and not an arbitration pointer, decides which
// bank sees what: a request whose line is already in flight
// never reaches a bank at all.
//
// The banks contend for the one downstream link, and that is
// round robin on the same reasoning.
//
// PACINO CHANGES (BP-123, cachegen_decisions.md CG-D1). Two port
// additions on the core side, under the emission's core_ naming;
// fe_top maps them to the l1i_ifu_interfaces.md names one to one:
//   core_uncached    ifu_l1i_req_uncached  IF-44, L1I-24
//   core_inv_val     ifu_l1i_inv_val       IF-28 to IF-32, IF-42,
//   core_inv_rdy     ifu_l1i_inv_rdy       L1I-18
//   core_inv_all     ifu_l1i_inv_all
//   core_inv_addr    ifu_l1i_inv_paddr
//   core_inv_done    l1i_ifu_inv_done
// The invalidate is l1i_maint's; the uncached qualifier is read by
// l1i_mshr and by the bank's compare stage.
//--------------------------------------------------------------------
// The import is at file scope and before the module, which is what
// the project verilog style asks for. Verilator's IMPORTSTAR objects
// to a wildcard in $unit scope, so it is turned off across these
// lines and nowhere else.
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
/* verilator lint_on IMPORTSTAR */

module l1i (
  input  logic                 clk,
  input  logic                 rstn,

  // interface 'core', link 'pe_port_i'
  input  logic                 core_valid,          // a request is live
  input  logic [35:0]          core_addr,           // byte address, R-7
  input  logic [3:0]           core_id,             // request id
  input  logic                 core_prefetch,
  input  logic                 core_uncached,       // L1I-24
  output logic [511:0]         core_rdata,          // read data
  output logic                 core_ready,          // slave took it
  output logic                 core_rvalid,         // read data is live
  output logic [3:0]           core_rid,            // answers this request
  output logic                 core_rerr,

  // maintenance, l1i_ifu_interfaces.md 10 (BP-123)
  input  logic                 core_inv_val,
  output logic                 core_inv_rdy,
  input  logic                 core_inv_all,
  input  logic [35:0]          core_inv_addr,       // any byte, IF-29
  output logic                 core_inv_done,

  // interface 'mem', link 'tl_l1i_l2'
  output logic                 mem_a_valid,         // ch A payload live
  input  logic                 mem_a_ready,         // ch A sink accepts
  output logic [2:0]           mem_a_opcode,        // ch A operation
  output logic [2:0]           mem_a_param,         // op qualifier
  output logic [2:0]           mem_a_size,          // log2 beat bytes
  output logic [3:0]           mem_a_source,        // master txn id
  output logic [35:0]          mem_a_address,       // byte address, R-7
  output logic [31:0]          mem_a_mask,          // one bit a data byte
  output logic [255:0]         mem_a_data,          // the beat
  output logic                 mem_a_corrupt,       // the beat is bad
  input  logic                 mem_d_valid,         // ch D payload live
  output logic                 mem_d_ready,         // ch D sink accepts
  input  logic [2:0]           mem_d_opcode,        // ch D operation
  input  logic [2:0]           mem_d_param,         // op qualifier
  input  logic [2:0]           mem_d_size,          // log2 beat bytes
  input  logic [3:0]           mem_d_source,        // master txn id
  input  logic [1:0]           mem_d_sink,          // slave txn id
  input  logic                 mem_d_denied,        // the slave refused
  input  logic [255:0]         mem_d_data,          // the beat
  input  logic                 mem_d_corrupt        // the beat is bad
);

  localparam int unsigned NSlv = 1;
  localparam int unsigned NBnk = 2;
  typedef logic [0:0] src_t;
  typedef logic [0:0] bsel_t;

  // the internal request bundle, one per slave adapter
  logic  s_req_valid [NSlv];
  logic  s_req_ready [NSlv];
  l1i_addr_t s_req_addr  [NSlv];
  l1i_req_id_t s_req_id  [NSlv];
  logic  s_req_prefetch [NSlv];
  logic  s_req_uncached [NSlv];
  logic  s_rsp_valid [NSlv];
  l1i_req_id_t s_rsp_id  [NSlv];
  l1i_word_t s_rsp_data  [NSlv];
  logic  s_rsp_err   [NSlv];

  // the same bundle on the bank side
  logic  b_req_valid [NBnk];
  logic  b_req_ready [NBnk];
  l1i_addr_t b_req_addr  [NBnk];
  logic  b_rsp_valid [NBnk];
  l1i_line_t b_rsp_data  [NBnk];
  logic  b_rsp_err   [NBnk];
  l1i_mshr_t b_req_src   [NBnk];
  logic  b_req_unc   [NBnk];
  l1i_mshr_t b_rsp_src   [NBnk];

  // the miss report out of each bank's compare stage, and
  // the fill write back into it
  logic  b_mis_valid [NBnk];
  l1i_addr_t b_mis_line  [NBnk];
  l1i_mshr_t b_mis_src   [NBnk];
  l1i_way_t  b_mis_way   [NBnk];
  logic  b_fil_valid [NBnk];
  l1i_addr_t b_fil_line  [NBnk];
  l1i_way_t  b_fil_way   [NBnk];
  l1i_line_t b_fil_data  [NBnk];
  logic  b_fil_rpl   [NBnk];      // BP-125

  // THE DOWNSTREAM SIDE IS THE MISS HANDLING FILE'S. No
  // bank presents to it, so there is no arbitration here
  // and no owner to remember: a return names its register.
  logic  m_req_valid;
  logic  m_req_ready;
  l1i_addr_t m_req_addr;
  l1i_mshr_t m_req_src;
  logic  m_rsp_valid;
  l1i_mshr_t m_rsp_src;
  l1i_line_t m_rsp_data;
  logic  m_rsp_err;

  // maintenance (BP-123)
  logic      mt_hold;
  l1i_addr_t mt_line;
  logic      mt_busy_any;
  logic      mt_busy_line;
  logic      mt_clr_en;
  logic      mt_clr_all;
  l1i_bank_t mt_clr_bank;
  l1i_set_t  mt_clr_set;

  l1i_core_slv u_core_slv (
    .clk       (clk),
    .rstn      (rstn),
    .core_valid        (core_valid),
    .core_addr         (core_addr),
    .core_id           (core_id),
    .core_prefetch     (core_prefetch),
    .core_uncached     (core_uncached),
    .core_rdata        (core_rdata),
    .core_ready        (core_ready),
    .core_rvalid       (core_rvalid),
    .core_rid          (core_rid),
    .core_rerr         (core_rerr),
    .req_valid (s_req_valid[0]),
    .req_ready (s_req_ready[0]),
    .req_addr  (s_req_addr[0]),
    .req_id    (s_req_id[0]),
    .req_prefetch(s_req_prefetch[0]),
    .req_uncached(s_req_uncached[0]),
    .rsp_valid (s_rsp_valid[0]),
    .rsp_id    (s_rsp_id[0]),
    .rsp_data  (s_rsp_data[0]),
    .rsp_err   (s_rsp_err[0])
  );

  l1i_mshr u_mshr (
    .clk         (clk),
    .rstn        (rstn),
    .req_valid   (s_req_valid[0]),
    .req_ready   (s_req_ready[0]),
    .req_addr    (s_req_addr[0]),
    .req_id      (s_req_id[0]),
    .req_prefetch(s_req_prefetch[0]),
    .req_uncached(s_req_uncached[0]),
    .rsp_valid   (s_rsp_valid[0]),
    .rsp_id      (s_rsp_id[0]),
    .rsp_data    (s_rsp_data[0]),
    .rsp_err     (s_rsp_err[0]),
    .b_req_valid (b_req_valid),
    .b_req_ready (b_req_ready),
    .b_req_addr  (b_req_addr),
    .b_req_src   (b_req_src),
    .b_req_unc   (b_req_unc),
    .b_rsp_valid (b_rsp_valid),
    .b_rsp_data  (b_rsp_data),
    .b_rsp_err   (b_rsp_err),
    .b_rsp_src   (b_rsp_src),
    .b_mis_valid (b_mis_valid),
    .b_mis_line  (b_mis_line),
    .b_mis_src   (b_mis_src),
    .b_mis_way   (b_mis_way),
    .b_fil_valid (b_fil_valid),
    .b_fil_line  (b_fil_line),
    .b_fil_way   (b_fil_way),
    .b_fil_data  (b_fil_data),
    .b_fil_rpl   (b_fil_rpl),
    .m_req_valid (m_req_valid),
    .m_req_ready (m_req_ready),
    .m_req_addr  (m_req_addr),
    .m_req_src   (m_req_src),
    .m_rsp_valid (m_rsp_valid),
    .m_rsp_src   (m_rsp_src),
    .m_rsp_data  (m_rsp_data),
    .m_rsp_err   (m_rsp_err),
    .hold        (mt_hold),
    .inv_line    (mt_line),
    .busy_any    (mt_busy_any),
    .busy_line   (mt_busy_line)
  );

  // ---------------------------------------------------------
  // Maintenance, drain then clear (BP-123).
  // ---------------------------------------------------------
  l1i_maint u_maint (
    .clk       (clk),
    .rstn      (rstn),
    .inv_val   (core_inv_val),
    .inv_rdy   (core_inv_rdy),
    .inv_all   (core_inv_all),
    .inv_addr  (l1i_addr_t'(core_inv_addr)),
    .inv_done  (core_inv_done),
    .hold      (mt_hold),
    .inv_line  (mt_line),
    .busy_any  (mt_busy_any),
    .busy_line (mt_busy_line),
    .clr_en    (mt_clr_en),
    .clr_all   (mt_clr_all),
    .clr_bank  (mt_clr_bank),
    .clr_set   (mt_clr_set)
  );

  // ---------------------------------------------------------
  // The banks. Identical by construction, which is the point
  // of generating them.
  // ---------------------------------------------------------
  for(genvar b = 0; b < int'(NBnk); b++) begin : g_bank
    l1i_bank u_bank (
      .clk        (clk),
      .rstn       (rstn),
      .req_valid  (b_req_valid[b]),
      .req_ready  (b_req_ready[b]),
      .req_addr   (b_req_addr[b]),
      .req_src    (b_req_src[b]),
      .req_unc    (b_req_unc[b]),
      .inv_en     (mt_clr_en && (mt_clr_bank == l1i_bank_t'(b))),
      .inv_all    (mt_clr_all),
      .inv_set    (mt_clr_set),
      .rsp_valid  (b_rsp_valid[b]),
      .rsp_data   (b_rsp_data[b]),
      .rsp_err    (b_rsp_err[b]),
      .rsp_src    (b_rsp_src[b]),
      .mis_valid  (b_mis_valid[b]),
      .mis_line   (b_mis_line[b]),
      .mis_src    (b_mis_src[b]),
      .mis_way    (b_mis_way[b]),
      .fil_valid  (b_fil_valid[b]),
      .fil_line   (b_fil_line[b]),
      .fil_way    (b_fil_way[b]),
      .fil_data   (b_fil_data[b]),
      .fil_rpl    (b_fil_rpl[b])
    );
  end : g_bank

  l1i_mem_mst u_mem_mst (
    .clk        (clk),
    .rstn       (rstn),
    .mreq_valid (m_req_valid),
    .mreq_ready (m_req_ready),
    .mreq_addr  (m_req_addr),
    .mreq_src   (m_req_src),
    .mrsp_valid (m_rsp_valid),
    .mrsp_src   (m_rsp_src),
    .mrsp_data  (m_rsp_data),
    .mrsp_err   (m_rsp_err),
    .mem_a_valid        (mem_a_valid),
    .mem_a_ready        (mem_a_ready),
    .mem_a_opcode       (mem_a_opcode),
    .mem_a_param        (mem_a_param),
    .mem_a_size         (mem_a_size),
    .mem_a_source       (mem_a_source),
    .mem_a_address      (mem_a_address),
    .mem_a_mask         (mem_a_mask),
    .mem_a_data         (mem_a_data),
    .mem_a_corrupt      (mem_a_corrupt),
    .mem_d_valid        (mem_d_valid),
    .mem_d_ready        (mem_d_ready),
    .mem_d_opcode       (mem_d_opcode),
    .mem_d_param        (mem_d_param),
    .mem_d_size         (mem_d_size),
    .mem_d_source       (mem_d_source),
    .mem_d_sink         (mem_d_sink),
    .mem_d_denied       (mem_d_denied),
    .mem_d_data         (mem_d_data),
    .mem_d_corrupt      (mem_d_corrupt)
  );

endmodule
