// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for the pacino L1I's miss handling file (BP-123):
// the uncached request of IF-44 / icache_decisions.md L1I-24. The
// core-port properties are in l1i_assert.sv.
//
// BOUND BY MODULE NAME (TD#109) to l1i_mshr. Every input is a port of
// l1i_mshr.
//
// The property compares the array writes against a model this file
// keeps from earlier port events: the requests taken and not yet
// answered, with their lines and their uncached qualifier. It does not
// restate the RTL that decides the install.
//
//   C5  a_fill_alloc    a fill is written into the array only for a
//                       line with a cacheable request outstanding,
//                       counting one taken in the fill's own cycle
//                       (L1I-24: an uncached request never allocates;
//                       a cacheable one merged onto it does)
// ===================================================================
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
/* verilator lint_on IMPORTSTAR */

module l1i_mshr_assert (
  input logic        clk,
  input logic        rstn,
  input logic        req_valid,
  input logic        req_ready,
  input l1i_addr_t   req_addr,
  input l1i_req_id_t req_id,
  input logic        req_uncached,
  input logic        rsp_valid,
  input l1i_req_id_t rsp_id,
  input logic        b_fil_valid [2],
  input l1i_addr_t   b_fil_line  [2]
);

  localparam int NID = 16;

  logic      r_out  [NID];
  logic      r_unc  [NID];
  l1i_addr_t r_line [NID];

  wire w_acc = req_valid && req_ready;

  // A fill being written for a line with no cacheable request on it,
  // counting one accepted in this cycle (it may merge as the fill
  // lands).
  logic w_bad;
  always_comb begin : fills
    logic ok;
    w_bad = 1'b0;
    for (int b = 0; b < 2; b++) begin
      ok = w_acc && !req_uncached &&
           (l1i_line_base(req_addr) == b_fil_line[b]);
      for (int i = 0; i < NID; i++) begin
        if (r_out[i] && !r_unc[i] && (r_line[i] == b_fil_line[b]))
          ok = 1'b1;
      end
      if (b_fil_valid[b] && !ok) w_bad = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rstn) begin : track
    if (!rstn) begin
      for (int i = 0; i < NID; i++) begin
        r_out[i]  <= 1'b0;
        r_unc[i]  <= 1'b0;
        r_line[i] <= '0;
      end
    end else begin
      for (int i = 0; i < NID; i++) begin
        if (rsp_valid && (rsp_id == l1i_req_id_t'(i))) r_out[i] <= 1'b0;
        if (w_acc && (req_id == l1i_req_id_t'(i))) begin
          r_out[i]  <= 1'b1;
          r_unc[i]  <= req_uncached;
          r_line[i] <= l1i_line_base(req_addr);
        end
      end
    end
  end

  property p_fill_alloc;
    @(posedge clk) disable iff (!rstn)
      !w_bad;
  endproperty
  a_fill_alloc: assert property (p_fill_alloc)
    else $error("C5 L1I installed a line no cacheable request asked for");

endmodule

bind l1i_mshr l1i_mshr_assert u_mshr_assert (
  .clk          (clk),
  .rstn         (rstn),
  .req_valid    (req_valid),
  .req_ready    (req_ready),
  .req_addr     (req_addr),
  .req_id       (req_id),
  .req_uncached (req_uncached),
  .rsp_valid    (rsp_valid),
  .rsp_id       (rsp_id),
  .b_fil_valid  (b_fil_valid),
  .b_fil_line   (b_fil_line)
);
