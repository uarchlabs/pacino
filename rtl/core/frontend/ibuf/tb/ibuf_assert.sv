// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ibuf (BP-118), ibuf_decisions.md.
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
//
// The properties do not read the ibuf's own occupancy. This module
// keeps its own count, built from the port handshakes alone: a write
// adds the popcount of the enable mask of an accepted block, a read
// subtracts the number of valid entries presented when the ready is
// high, and the backend redirect valid empties it. Every property
// checks the ibuf outputs against that count.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ibuf_assert #(
  parameter int DEPTH         = 64,
  parameter int IBUF_RD_WIDTH = 8
) (
  input logic                    clk,
  input logic                    rstn,
  input logic                    ifu_ibuf_val,
  input logic [FTQ_PD_WIDTH-1:0] ifu_ibuf_en,
  input logic                    ibuf_ifu_rdy,
  input logic                    bkend_ftq_redir_val,
  input ifu_pd_pkt_t             ibuf_dec_slot [0:IBUF_RD_WIDTH-1],
  input logic                    dec_ibuf_rdy
);

  int  r_occ;     // entries held, from the handshakes
  int  w_n_wr;    // entries written this cycle
  int  w_n_val;   // valid read slots this cycle
  int  w_n_exp;   // read slots that must be valid this cycle
  logic w_contig; // valid read slots are 0..n-1

  always_comb begin : ev
    int n;
    n = 0;
    for (int i = 0; i < FTQ_PD_WIDTH; i++) if (ifu_ibuf_en[i]) n++;
    w_n_wr = (ifu_ibuf_val && ibuf_ifu_rdy && !bkend_ftq_redir_val)
               ? n : 0;

    w_n_val  = 0;
    w_contig = 1'b1;
    for (int k = 0; k < IBUF_RD_WIDTH; k++) begin
      if (ibuf_dec_slot[k].valid) begin
        if (w_n_val != k) w_contig = 1'b0;
        w_n_val++;
      end
    end

    // IBUF-7: an empty buffer presents the write of the same cycle.
    w_n_exp = (r_occ == 0) ? w_n_wr : r_occ;
    if (w_n_exp > IBUF_RD_WIDTH) w_n_exp = IBUF_RD_WIDTH;
    if (bkend_ftq_redir_val)     w_n_exp = 0;
  end

  always_ff @(posedge clk or negedge rstn) begin : occ_ff
    if (!rstn)                    r_occ <= 0;
    else if (bkend_ftq_redir_val) r_occ <= 0;
    else r_occ <= r_occ + w_n_wr - (dec_ibuf_rdy ? w_n_val : 0);
  end

  // S1  IBUF-4, IB-6. Ready is high exactly when FTQ_PD_WIDTH entries
  //     are free, whatever the offered mask holds.
  property p_rdy_free16;
    @(posedge clk) disable iff (!rstn)
      ibuf_ifu_rdy == ((DEPTH - r_occ) >= FTQ_PD_WIDTH);
  endproperty

  // S2  IBUF-9. Valid read slots are presented from slot 0 with no
  //     hole, so slot order is FIFO order.
  property p_rd_contig;
    @(posedge clk) disable iff (!rstn)
      w_contig;
  endproperty

  // S3  IBUF-7, IBUF-9, IBUF-8. The read port presents min(8, held)
  //     entries, the same-cycle write when empty, and none in a clear
  //     cycle.
  property p_rd_count;
    @(posedge clk) disable iff (!rstn)
      w_n_val == w_n_exp;
  endproperty

  a_ibuf_rdy_free16: assert property (p_rdy_free16)
    else $error("S1 IBUF-4 ready does not match 16 free entries");
  a_ibuf_rd_contig:  assert property (p_rd_contig)
    else $error("S2 IBUF-9 valid read slots are not contiguous");
  a_ibuf_rd_count:   assert property (p_rd_count)
    else $error("S3 IBUF-7/9 read slot count is wrong");

endmodule : ibuf_assert

// Bind BY MODULE NAME.
bind ibuf ibuf_assert #(
  .DEPTH         (DEPTH),
  .IBUF_RD_WIDTH (IBUF_RD_WIDTH)
) u_assert (
  .clk                 (clk),
  .rstn                (rstn),
  .ifu_ibuf_val        (ifu_ibuf_val),
  .ifu_ibuf_en         (ifu_ibuf_en),
  .ibuf_ifu_rdy        (ibuf_ifu_rdy),
  .bkend_ftq_redir_val (bkend_ftq_redir_val),
  .ibuf_dec_slot       (ibuf_dec_slot),
  .dec_ibuf_rdy        (dec_ibuf_rdy)
);
