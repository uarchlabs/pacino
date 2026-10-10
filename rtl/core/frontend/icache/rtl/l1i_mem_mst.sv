// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      l1i_mem_mst.sv
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// Interface 'mem' of node 'l1i', the master end of
// link 'tl_l1i_l2', protocol tilelink TL-UH.
//
// One line is 64 bytes and the link carries 32
// bytes a beat, so a line is 2 beats. That number is derived
// from the two, never read from the configuration, D-37.
//
// UP TO 16 FILLS MAY BE IN FLIGHT. Nothing here limits them:
// channel A is straight through, so a fill leaves in any cycle
// the miss handling file offers one and the link takes it, and
// what bounds the count is the number of registers.
//
// A D BEAT IS PLACED BY ITS SOURCE AND BY NOTHING ELSE. The
// beats of two fills may interleave, and a fill issued later may
// complete first. A line is announced upstream when ITS last
// beat arrives.
//--------------------------------------------------------------------
// The import is at file scope and before the module, which is what
// the project verilog style asks for. Verilator's IMPORTSTAR objects
// to a wildcard in $unit scope, so it is turned off across these
// lines and nowhere else.
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
import cgen_tl_pkg::*;
/* verilator lint_on IMPORTSTAR */

module l1i_mem_mst (
  input  logic                 clk,
  input  logic                 rstn,

  // the internal line request
  input  logic                 mreq_valid,
  output logic                 mreq_ready,
  input  l1i_addr_t                mreq_addr,
  input  l1i_mshr_t                mreq_src,

  // the internal line response, naming the register it
  // belongs to
  output logic                 mrsp_valid,
  output l1i_mshr_t                mrsp_src,
  output l1i_line_t                mrsp_data,
  output logic                 mrsp_err,

  // the link
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

  localparam logic [2:0] LineSize = 3'd6;  // log2 of 64 bytes

  wire d_fire = mem_d_valid && mem_d_ready;

  // ---------------------------------------------------------
  // CHANNEL A. Straight through. There is no register
  // between the miss handling file and the link, so a fill
  // leaves in the cycle it is offered and the next may
  // leave in the cycle after it.
  // ---------------------------------------------------------
  assign mreq_ready = mem_a_ready;

  always_comb begin
    mem_a_valid   = mreq_valid;
    mem_a_opcode  = TlAGet;
    mem_a_param   = TlParamZero;
    mem_a_size    = LineSize;
    mem_a_source  = 4'(mreq_src);   // the register this fill belongs to
    mem_a_address = l1i_line_base(mreq_addr);
    mem_a_mask    = '0;
    mem_a_data    = '0;
    mem_a_corrupt = 1'b0;
  end

  // ---------------------------------------------------------
  // CHANNEL D. One partial line per register, indexed by the
  // source the beat carries. A register holds at most one
  // fill at a time, so the source IS the index and no
  // search is needed.
  //
  // D IS ALWAYS READY. A beat this adapter refused would
  // have to be refused for every source at once, which is a
  // second flow control beside the register count.
  // ---------------------------------------------------------
  assign mem_d_ready = 1'b1;

  l1i_line_t                  f_buf  [L1iMshrs];
  logic [L1iBeatIdxBits-1:0] f_beat [L1iMshrs];
  logic                   f_err  [L1iMshrs];

  wire l1i_mshr_t d_src  = l1i_mshr_t'(mem_d_source);
  wire        d_last = (f_beat[d_src] == L1iBeatIdxBits'(L1iBeats-1));
  wire        d_bad  = mem_d_denied || mem_d_corrupt;

  // the line as it stands WITH this beat already in it, so
  // the last beat does not have to wait a cycle to be part
  // of the answer
  l1i_line_t d_line;

  always_comb begin
    d_line = f_buf[d_src];
    d_line[int'(f_beat[d_src])*L1iBeatBits +: L1iBeatBits] =
        mem_d_data;
  end

  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) begin
      for(int unsigned m = 0; m < L1iMshrs; m++) begin
        f_buf [m] <= '0;
        f_beat[m] <= '0;
        f_err [m] <= 1'b0;
      end
      mrsp_valid <= 1'b0;
      mrsp_src   <= '0;
      mrsp_data  <= '0;
      mrsp_err   <= 1'b0;
    end else begin
      mrsp_valid <= 1'b0;

      if(d_fire) begin
        f_buf[d_src] <= d_line;
        if(d_last) begin
          // THIS line is complete. Whether any other fill
          // is still part way through says nothing about
          // it.
          f_beat[d_src] <= '0;
          f_err [d_src] <= 1'b0;
          mrsp_valid    <= 1'b1;
          mrsp_src      <= d_src;
          mrsp_data     <= d_line;
          mrsp_err      <= f_err[d_src] || d_bad;
        end else begin
          f_beat[d_src] <= f_beat[d_src] + L1iBeatIdxBits'(1);
          f_err [d_src] <= f_err[d_src] || d_bad;
        end
      end
    end
  end

  // channel D fields a whole line master does not consume
  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_d = |{
      mem_d_opcode,
      mem_d_param,
      mem_d_size,
      mem_d_sink
  };
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
