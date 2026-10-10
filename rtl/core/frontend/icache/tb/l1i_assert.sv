// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for the pacino L1I (BP-123): the maintenance port of
// l1i_ifu_interfaces.md 10 (IF-28 to IF-32) and the uncached request
// of IF-44 / icache_decisions.md L1I-24.
//
// BOUND BY MODULE NAME (TD#109) to l1i. Every input is a port of l1i.
// The miss handling file's property, C5, is tb/l1i_mshr_assert.sv.
//
// Each property compares a port against a model this file keeps from
// earlier port events: whether an invalidate has been taken and not
// yet completed, the line it names, and the requests taken and not
// yet answered with their lines and qualifiers. None restates the
// RTL that drives the checked signal.
//
//   C1  a_inv_hold      no request is accepted from the cycle an
//                       invalidate is taken until its done (IF-30)
//   C2  a_inv_one       no second invalidate is taken before the
//                       first's done (IF-28)
//   C3  a_done_pulse    done is one cycle wide and only for a taken
//                       invalidate (IF-32)
//   C4  a_done_drained  at done, no request taken before it is still
//                       unanswered for the whole cache (inv_all), or
//                       for the named line (inv_line) (IF-31)
// ===================================================================
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
/* verilator lint_on IMPORTSTAR */

module l1i_assert (
  input logic        clk,
  input logic        rstn,
  input logic        core_valid,
  input logic        core_ready,
  input logic [35:0] core_addr,
  input logic [3:0]  core_id,
  input logic        core_rvalid,
  input logic [3:0]  core_rid,
  input logic        core_inv_val,
  input logic        core_inv_rdy,
  input logic        core_inv_all,
  input logic [35:0] core_inv_addr,
  input logic        core_inv_done
);

  localparam int NID = 16;

  logic        r_pend;          // taken, done not yet seen
  logic        r_all;
  logic [29:0] r_line;
  logic        r_done_q;        // done last cycle
  logic        r_out  [NID];    // request outstanding, by id
  logic [29:0] r_oline [NID];

  wire w_take = core_inv_val && core_inv_rdy;
  wire w_acc  = core_valid && core_ready;

  logic w_left;                 // a request the done must have drained
  always_comb begin : drained
    w_left = 1'b0;
    for (int i = 0; i < NID; i++) begin
      if (r_out[i] && !(core_rvalid && (core_rid == 4'(i))) &&
          (r_all || (r_oline[i] == r_line)))
        w_left = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rstn) begin : track
    if (!rstn) begin
      r_pend   <= 1'b0;
      r_all    <= 1'b0;
      r_line   <= '0;
      r_done_q <= 1'b0;
      for (int i = 0; i < NID; i++) begin
        r_out[i]   <= 1'b0;
        r_oline[i] <= '0;
      end
    end else begin
      r_done_q <= core_inv_done;
      if (core_inv_done) r_pend <= 1'b0;
      if (w_take) begin
        r_pend <= 1'b1;
        r_all  <= core_inv_all;
        r_line <= core_inv_addr[35:6];
      end
      for (int i = 0; i < NID; i++) begin
        if (core_rvalid && (core_rid == 4'(i))) r_out[i] <= 1'b0;
        if (w_acc && (core_id == 4'(i))) begin
          r_out[i]   <= 1'b1;
          r_oline[i] <= core_addr[35:6];
        end
      end
    end
  end

  property p_inv_hold;
    @(posedge clk) disable iff (!rstn)
      (w_take || r_pend) |-> !w_acc;
  endproperty
  a_inv_hold: assert property (p_inv_hold)
    else $error("C1 L1I accepted a request during an invalidate");

  property p_inv_one;
    @(posedge clk) disable iff (!rstn)
      r_pend |-> !w_take;
  endproperty
  a_inv_one: assert property (p_inv_one)
    else $error("C2 L1I took a second invalidate before done");

  property p_done_pulse;
    @(posedge clk) disable iff (!rstn)
      core_inv_done |-> (r_pend && !r_done_q);
  endproperty
  a_done_pulse: assert property (p_done_pulse)
    else $error("C3 L1I done not a one-cycle answer to an invalidate");

  property p_done_drained;
    @(posedge clk) disable iff (!rstn)
      core_inv_done |-> !w_left;
  endproperty
  a_done_drained: assert property (p_done_drained)
    else $error("C4 L1I done with a request it must drain outstanding");

endmodule

bind l1i l1i_assert u_assert (
  .clk           (clk),
  .rstn          (rstn),
  .core_valid    (core_valid),
  .core_ready    (core_ready),
  .core_addr     (core_addr),
  .core_id       (core_id),
  .core_rvalid   (core_rvalid),
  .core_rid      (core_rid),
  .core_inv_val  (core_inv_val),
  .core_inv_rdy  (core_inv_rdy),
  .core_inv_all  (core_inv_all),
  .core_inv_addr (core_inv_addr),
  .core_inv_done (core_inv_done)
);

