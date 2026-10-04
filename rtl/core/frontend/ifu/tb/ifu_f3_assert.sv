// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ifu_f3 (BP-116), ifu_ibuf_interfaces.md 3.
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
//
// The model here is built from F3's input handshake (a block loaded
// from F2) and its output handshake (a block transferred to the
// ibuf), so F3's own valid register is checked against events it
// does not drive.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ifu_f3_assert (
  input logic                    clk,
  input logic                    rstn,
  input logic                    flush,
  input logic                    f2_val,
  input logic                    f2_rdy,
  input logic                    ifu_ibuf_val,
  input logic [FTQ_PD_WIDTH-1:0] ifu_ibuf_en,
  input ifu_pd_pkt_t             ifu_ibuf_slot [0:FTQ_PD_WIDTH-1],
  input logic                    ibuf_ifu_rdy
);

  // Blocks loaded into F3 and not yet transferred: 0 or 1.
  logic                    r_held;
  // The block offered and refused last cycle.
  logic                    r_refused;
  logic [FTQ_PD_WIDTH-1:0] r_en;
  ifu_pd_pkt_t             r_slot [0:FTQ_PD_WIDTH-1];

  logic w_load;
  logic w_xfer;
  logic w_slot_same;

  always_comb begin : ev
    w_load      = f2_val && f2_rdy;
    w_xfer      = ifu_ibuf_val && ibuf_ifu_rdy;
    w_slot_same = 1'b1;
    for (int i = 0; i < FTQ_PD_WIDTH; i++) begin
      if (ifu_ibuf_slot[i] != r_slot[i]) w_slot_same = 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rstn) begin : hist
    if (!rstn) begin
      r_held    <= 1'b0;
      r_refused <= 1'b0;
      r_en      <= '0;
      for (int i = 0; i < FTQ_PD_WIDTH; i++) r_slot[i] <= '0;
    end else begin
      if (flush)       r_held <= 1'b0;
      else if (w_load) r_held <= 1'b1;
      else if (w_xfer) r_held <= 1'b0;
      r_refused <= ifu_ibuf_val && !ibuf_ifu_rdy;
      r_en      <= ifu_ibuf_en;
      for (int i = 0; i < FTQ_PD_WIDTH; i++) r_slot[i] <= ifu_ibuf_slot[i];
    end
  end

  // B1  IB-5. A block is offered only while one is held, so a block
  //     that transferred is not offered again: it went whole, in one
  //     cycle, and no remainder is left to present.
  property p_offer_needs_block;
    @(posedge clk) disable iff (!rstn)
      ifu_ibuf_val |-> r_held;
  endproperty

  // B2  IB-5, the other direction. A held block is offered every
  //     cycle (outside a flush cycle): F3 does not sit on a block.
  property p_block_is_offered;
    @(posedge clk) disable iff (!rstn)
      (r_held && !flush) |-> ifu_ibuf_val;
  endproperty

  // B3  IB-7. While the ibuf refuses, the block's valid and its whole
  //     payload -- enable mask and every slot -- are held unchanged.
  //     A flush discards the block (TD#134).
  property p_hold_while_refused;
    @(posedge clk) disable iff (!rstn)
      (r_refused && !flush) |->
        (ifu_ibuf_val && (ifu_ibuf_en == r_en) && w_slot_same);
  endproperty

  a_ib_offer_held:   assert property (p_offer_needs_block)
    else $error("B1 IB-5 a block was offered with none held");
  a_ib_held_offered: assert property (p_block_is_offered)
    else $error("B2 IB-5 a held block was not offered");
  a_ib_hold_stable:  assert property (p_hold_while_refused)
    else $error("B3 IB-7 the payload changed while ibuf_ifu_rdy was low");

endmodule : ifu_f3_assert

// Bind BY MODULE NAME.
bind ifu_f3 ifu_f3_assert u_assert (
  .clk           (clk),
  .rstn          (rstn),
  .flush         (flush),
  .f2_val        (f2_val),
  .f2_rdy        (f2_rdy),
  .ifu_ibuf_val  (ifu_ibuf_val),
  .ifu_ibuf_en   (ifu_ibuf_en),
  .ifu_ibuf_slot (ifu_ibuf_slot),
  .ibuf_ifu_rdy  (ibuf_ifu_rdy)
);
