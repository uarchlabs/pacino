// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      l1i_tb_mem.sv
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// A downstream responder for the unit testbench of node 'l1i'.
//
// NOT SYNTHESIZABLE and not part of the design. L1iBeats come back
// with the address baked into them, so a test can predict what a
// fill should contain without keeping its own model.
//
// IT HOLDS ONE FILL PER SOURCE, 16 of them, because the node
// under test may have that many in flight. A master holds at most
// one request per source, so the source IS the index and no
// search is needed.
//
// Four inputs let a test choose what the memory side does:
//
//   tb_hold   channel A is refused, so no fill can start
//   tb_dhold  channel D is held, so fills accumulate and
//             none of them completes
//   tb_ilv    beats go out round robin, so the beats of two
//             fills INTERLEAVE
//   tb_rev    the HIGHEST numbered pending source is served
//             first, so a fill issued later completes first
//
// With none of them set it serves the lowest numbered pending
// fill and keeps the link until that line is done.
//--------------------------------------------------------------------
// The import is at file scope and before the module, which is what
// the project verilog style asks for. Verilator's IMPORTSTAR objects
// to a wildcard in $unit scope, so it is turned off across these
// lines and nowhere else.
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
import cgen_tl_pkg::*;
/* verilator lint_on IMPORTSTAR */

module l1i_tb_mem (
  input  logic  clk,
  input  logic  rstn,
  input  logic  tb_hold,
  input  logic  tb_dhold,
  input  logic  tb_ilv,
  input  logic  tb_rev,

  input  logic                 mem_a_valid,         // ch A payload live
  output  logic                 mem_a_ready,         // ch A sink accepts
  input  logic [2:0]           mem_a_opcode,        // ch A operation
  input  logic [2:0]           mem_a_param,         // op qualifier
  input  logic [2:0]           mem_a_size,          // log2 beat bytes
  input  logic [3:0]           mem_a_source,        // master txn id
  input  logic [35:0]          mem_a_address,       // byte address, R-7
  input  logic [31:0]          mem_a_mask,          // one bit a data byte
  input  logic [255:0]         mem_a_data,          // the beat
  input  logic                 mem_a_corrupt,       // the beat is bad
  output  logic                 mem_d_valid,         // ch D payload live
  input  logic                 mem_d_ready,         // ch D sink accepts
  output  logic [2:0]           mem_d_opcode,        // ch D operation
  output  logic [2:0]           mem_d_param,         // op qualifier
  output  logic [2:0]           mem_d_size,          // log2 beat bytes
  output  logic [3:0]           mem_d_source,        // master txn id
  output  logic [1:0]           mem_d_sink,          // slave txn id
  output  logic                 mem_d_denied,        // the slave refused
  output  logic [255:0]         mem_d_data,          // the beat
  output  logic                 mem_d_corrupt        // the beat is bad
);

  localparam int unsigned BeatShift = 5;
  localparam int unsigned NSrc      = 16;

  typedef logic [3:0] src_t;

  // one pending fill per source
  logic        p_val  [NSrc];
  l1i_addr_t       p_addr [NSrc];
  logic [2:0]  p_size [NSrc];
  logic [15:0] p_beat [NSrc];
  logic [15:0] p_beats[NSrc];

  // where the round robin walk starts, so consecutive beats
  // go to different fills when tb_ilv is set
  src_t rr;

  function automatic logic [15:0] beats_of(input logic [2:0] s);
    beats_of = (int'(s) > int'(BeatShift))
             ? 16'(1 << (int'(s) - int'(BeatShift)))
             : 16'd1;
  endfunction

  function automatic longint unsigned key_of
      (input l1i_addr_t base, input logic [15:0] n);
    key_of = longint'({32'd0, base}) >> BeatShift;
    key_of = key_of + longint'({48'd0, n});
  endfunction

  // a beat carries its own key, so a test can predict a fill
  // without keeping a second model. The tests file carries
  // the same two functions, emitted from the same place.
  function automatic l1i_beat_t seed_of(input longint unsigned k);
    seed_of = l1i_beat_t'(k) ^ l1i_beat_t'(64'hcafe_0000_0000_0001);
  endfunction

  wire a_fire = mem_a_valid && mem_a_ready;
  wire d_fire = mem_d_valid && mem_d_ready;

  // ---------------------------------------------------------
  // CHANNEL A. A request is taken unless the source it names
  // already has a fill pending, so several may be in flight
  // and nothing here serialises them.
  // ---------------------------------------------------------
  assign mem_a_ready = rstn && !tb_hold &&
                            !p_val[mem_a_source];

  // ---------------------------------------------------------
  // CHANNEL D. Which pending fill gets this cycle's beat.
  // ---------------------------------------------------------
  logic d_any;
  src_t d_sel;

  always_comb begin
    d_any = 1'b0;
    d_sel = '0;
    if(tb_ilv) begin
      // start one past the source the last beat went to
      for(int unsigned k = 0; k < NSrc; k++) begin
        automatic src_t s = src_t'(
            (int'(rr) + int'(k) >= int'(NSrc))
            ? (int'(rr) + int'(k) - int'(NSrc))
            : (int'(rr) + int'(k)));
        if(!d_any && p_val[s]) begin
          d_any = 1'b1;
          d_sel = s;
        end
      end
    end else if(tb_rev) begin
      // counting up leaves the HIGHEST pending source
      for(int unsigned s = 0; s < NSrc; s++) begin
        if(p_val[s]) begin
          d_any = 1'b1;
          d_sel = src_t'(s);
        end
      end
    end else begin
      // counting down leaves the LOWEST pending source
      for(int unsigned s = NSrc; s > 0; s--) begin
        if(p_val[s-1]) begin
          d_any = 1'b1;
          d_sel = src_t'(s-1);
        end
      end
    end

    // unless a test asked for interleaving, a line that has
    // beats out already keeps the link until it is done
    if(!tb_ilv) begin
      for(int unsigned s = NSrc; s > 0; s--) begin
        if(p_val[s-1] && (p_beat[s-1] != 16'd0)) begin
          d_any = 1'b1;
          d_sel = src_t'(s-1);
        end
      end
    end
  end

  assign mem_d_valid   = d_any && !tb_dhold;
  assign mem_d_opcode  = TlDAccessAckData;
  assign mem_d_param   = TlParamZero;
  assign mem_d_size    = p_size[d_sel];
  assign mem_d_source  = 4'(d_sel);
  assign mem_d_sink    = '0;
  assign mem_d_denied  = 1'b0;
  assign mem_d_corrupt = 1'b0;
  assign mem_d_data    =
      seed_of(key_of(p_addr[d_sel], p_beat[d_sel]));

  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) begin
      for(int unsigned s = 0; s < NSrc; s++) begin
        p_val  [s] <= 1'b0;
        p_addr [s] <= '0;
        p_size [s] <= 3'd0;
        p_beat [s] <= 16'd0;
        p_beats[s] <= 16'd1;
      end
      rr <= '0;
    end else begin
      // a_fire needs the source free and d_fire needs it
      // taken, so the two cannot name one source in one
      // cycle and these writes cannot collide
      if(a_fire) begin
        p_val  [mem_a_source] <= 1'b1;
        p_addr [mem_a_source] <= mem_a_address;
        p_size [mem_a_source] <= mem_a_size;
        p_beat [mem_a_source] <= 16'd0;
        p_beats[mem_a_source] <= beats_of(mem_a_size);
      end

      if(d_fire) begin
        rr <= (d_sel == src_t'(NSrc-1))
              ? src_t'(0) : d_sel + src_t'(1);
        if(p_beat[d_sel] == p_beats[d_sel] - 16'd1) begin
          p_beat[d_sel] <= 16'd0;
          p_val [d_sel] <= 1'b0;
        end else begin
          p_beat[d_sel] <= p_beat[d_sel] + 16'd1;
        end
      end
    end
  end

  // THIS RESPONDER ANSWERS READS. The node under test is
  // read only on its core boundary and writes nothing back,
  // so anything but a Get is a defect in the master rather
  // than a case to carry.
  always_ff @(posedge clk) begin
    if(a_fire && (mem_a_opcode != TlAGet)) begin
      $error("l1i_tb_mem: opcode %0d is not a Get",
             mem_a_opcode);
    end
  end

  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_a = |{mem_a_param, mem_a_mask, mem_a_data, mem_a_corrupt};
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
