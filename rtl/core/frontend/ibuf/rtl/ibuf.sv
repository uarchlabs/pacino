// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    ibuf.sv
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Instruction buffer (BP-118). ibuf_decisions.md, and
// ifu_ibuf_interfaces.md for the write port.
//
// A FIFO of ifu_pd_pkt_t between the IFU and decode (IBUF-1, IBUF-2).
// It is the width converter of the front end: one prediction block
// of FTQ_PD_WIDTH = 16 positions in, IBUF_RD_WIDTH = 8 out.
//
// WRITE SIDE. ifu_ibuf_slot is 16 positions every cycle with one
// enable mask (IB-1, IB-2). The IFU does not compact; this module
// does, on write (IFU-5, IBUF-3): enabled position i is stored at
// tail + (the number of enabled positions below i), so the order of
// the block is kept. A block is accepted whole or not at all, and
// ibuf_ifu_rdy is high only when 16 entries are free whatever the
// mask holds (IB-5, IB-6, IBUF-4). ready is formed from the
// registered occupancy alone, so it has no path from the read-side
// ready of the same cycle.
//
// READ SIDE. Up to 8 entries from the head, in order, in
// ibuf_dec_slot[0..7] (IBUF-6, IBUF-9). ifu_pd_pkt_t.valid is
// produced here and says whether a read slot holds an instruction
// (IB-3); presented entries are always slots 0..n-1. ONE ready,
// dec_ibuf_rdy, dequeues every valid entry presented in that cycle;
// there is no partial dequeue (IBUF-12).
//
// BYPASS (IBUF-7). When the buffer is empty, an accepted write is
// presented on the read port in the same cycle: the first up to 8
// compacted entries of the block. The write still lands in the array
// at the tail; when dec_ibuf_rdy takes the bypassed entries the head
// moves past them in the same cycle, so the array holds only the
// remainder. Bypass and storage are one mechanism: append at the
// tail, then pop from the head.
//
// CLEAR. bkend_ftq_redir_val, the backend redirect valid that also
// enters the FTQ (IBUF-8, IBUF-13, IB-12), empties the buffer on
// every cause. It is the ONLY clear: the FTQ's IFU flush group does
// not reach this module. In the clear cycle the write is discarded
// and nothing is presented on the read port: every entry held, and
// the block in F3, is younger than the redirecting instruction.
//
// NOT BANKED (IBUF-U1): each read output is a flat DEPTH-to-1 mux.
// DEPTH is a parameter, default 64 (IBUF-11). It must be at least
// FTQ_PD_WIDTH; the index wrap is a compare and subtract, so DEPTH
// need not be a power of two.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ibuf #(
  parameter int DEPTH         = 64,
  parameter int IBUF_RD_WIDTH = 8
) (
  input  logic        clk,
  input  logic        rstn,

  // ---- write port, ifu_ibuf_interfaces.md 2 ------------------------
  input  logic                    ifu_ibuf_val,
  input  logic [FTQ_PD_WIDTH-1:0] ifu_ibuf_en,
  input  ifu_pd_pkt_t             ifu_ibuf_slot [0:FTQ_PD_WIDTH-1],
  output logic                    ibuf_ifu_rdy,

  // ---- clear, IBUF-13 -----------------------------------------------
  input  logic                    bkend_ftq_redir_val,

  // ---- read port, IBUF-6, IBUF-9, IBUF-12 --------------------------
  output ifu_pd_pkt_t             ibuf_dec_slot [0:IBUF_RD_WIDTH-1],
  input  logic                    dec_ibuf_rdy
);

  localparam int IDX_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam int CNT_W = $clog2(DEPTH + 1);
  localparam int WR_W  = $clog2(FTQ_PD_WIDTH + 1);
  localparam int RD_W  = $clog2(IBUF_RD_WIDTH + 1);

  // Every enabled position of an accepted block must fit.
  if (DEPTH < FTQ_PD_WIDTH) begin : gen_depth_chk
    $error("ibuf: DEPTH must be at least FTQ_PD_WIDTH (IBUF-4)");
  end

  ifu_pd_pkt_t          r_arr [0:DEPTH-1];
  logic [IDX_W-1:0]     r_head;
  logic [IDX_W-1:0]     r_tail;
  logic [CNT_W-1:0]     r_count;

  // Compacted write block and its size.
  ifu_pd_pkt_t          w_wr_c [0:FTQ_PD_WIDTH-1];
  logic [WR_W-1:0]      w_n_wr;
  logic                 w_wr;
  // Entries presented on the read port and the number popped.
  logic [RD_W-1:0]      w_n_pres;
  logic [RD_W-1:0]      w_n_pop;
  logic                 w_bypass;

  // Index of the k-th entry past a base, wrapped at DEPTH.
  function automatic logic [IDX_W-1:0] wrap_add(
    input logic [IDX_W-1:0] b,
    input int               k);
    int s;
    s = int'(b) + k;
    if (s >= DEPTH) s = s - DEPTH;
    return IDX_W'(s);
  endfunction

  // -----------------------------------------------------------------
  // Ready (IBUF-4). Registered occupancy only.
  // -----------------------------------------------------------------
  assign ibuf_ifu_rdy = (r_count <= CNT_W'(DEPTH - FTQ_PD_WIDTH));

  // -----------------------------------------------------------------
  // Compaction, read mux and pop count. One block in textual order:
  // the read mux depends on the compacted block. It reads r_count and
  // r_head, so it is not input-only (CLAUDE.md stl_sequent rule).
  // -----------------------------------------------------------------
  always_comb begin : rd_wr_comb
    int r;
    int avail;

    w_wr = ifu_ibuf_val && ibuf_ifu_rdy && !bkend_ftq_redir_val;

    // Compaction (IBUF-3): enabled positions packed down, in order.
    for (int i = 0; i < FTQ_PD_WIDTH; i++) w_wr_c[i] = '0;
    r = 0;
    for (int i = 0; i < FTQ_PD_WIDTH; i++) begin
      if (ifu_ibuf_en[i]) begin
        w_wr_c[r]       = ifu_ibuf_slot[i];
        w_wr_c[r].valid = 1'b1;
        r = r + 1;
      end
    end
    w_n_wr = w_wr ? WR_W'(r) : '0;

    // Bypass (IBUF-7): empty buffer, write accepted this cycle.
    w_bypass = (r_count == '0) && w_wr;
    avail    = w_bypass ? int'(w_n_wr) : int'(r_count);
    if (bkend_ftq_redir_val) avail = 0;
    w_n_pres = (avail > IBUF_RD_WIDTH) ? RD_W'(IBUF_RD_WIDTH)
                                       : RD_W'(avail);

    for (int k = 0; k < IBUF_RD_WIDTH; k++) begin
      ibuf_dec_slot[k] = '0;
      if (k < int'(w_n_pres)) begin
        ibuf_dec_slot[k] = w_bypass ? w_wr_c[k]
                                    : r_arr[wrap_add(r_head, k)];
        ibuf_dec_slot[k].valid = 1'b1;
      end
    end

    // One ready takes every presented entry (IBUF-12).
    w_n_pop = dec_ibuf_rdy ? w_n_pres : '0;
  end

  // -----------------------------------------------------------------
  // State. Append the accepted block at the tail, then pop from the
  // head; a clear empties everything (IBUF-8).
  // -----------------------------------------------------------------
  always_ff @(posedge clk or negedge rstn) begin : state_ff
    if (!rstn) begin
      r_head  <= '0;
      r_tail  <= '0;
      r_count <= '0;
    end else if (bkend_ftq_redir_val) begin
      r_head  <= '0;
      r_tail  <= '0;
      r_count <= '0;
    end else begin
      r_head  <= wrap_add(r_head, int'(w_n_pop));
      r_tail  <= wrap_add(r_tail, int'(w_n_wr));
      r_count <= r_count + CNT_W'(w_n_wr) - CNT_W'(w_n_pop);
    end
  end

  // The array has no reset: an entry is read only below r_count.
  always_ff @(posedge clk) begin : arr_ff
    for (int i = 0; i < FTQ_PD_WIDTH; i++) begin
      if (i < int'(w_n_wr)) begin
        r_arr[wrap_add(r_tail, i)] <= w_wr_c[i];
      end
    end
  end

endmodule : ibuf
