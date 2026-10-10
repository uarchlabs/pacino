// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      l1i_core_slv.sv
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// Interface 'core' of node 'l1i', the slave end of
// link 'pe_port_i', protocol custom.
//
// Turns a request on the link into internal requests and the
// internal answers back into a link response. The control
// behind it never sees which protocol this was.
//
// THIS LINK IS NOT BLOCKING. It declares 16 outstanding
// requests and a response keyed by an identifier, so the
// adapter holds no busy flag: every request is handed to
// the miss handling file with its identifier, and the
// response comes back carrying the identifier it answers.
// Ordering is the file's business and correlation is the
// identifier's, so nothing here has to remember either.
//
// PACINO CHANGES (BP-123, CG-D1): core_uncached (l1i_ifu_interfaces.md
// IF-44) passes to req_uncached like core_prefetch.
//--------------------------------------------------------------------
// The import is at file scope and before the module, which is what
// the project verilog style asks for. Verilator's IMPORTSTAR objects
// to a wildcard in $unit scope, so it is turned off across these
// lines and nowhere else.
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
/* verilator lint_on IMPORTSTAR */

module l1i_core_slv (
  input  logic                 clk,
  input  logic                 rstn,

  // the link
  input  logic                 core_valid,          // a request is live
  input  logic [35:0]          core_addr,           // byte address, R-7
  input  logic [3:0]           core_id,             // request id
  input  logic                 core_prefetch,
  input  logic                 core_uncached,       // L1I-24, BP-123
  output logic [511:0]         core_rdata,          // read data
  output logic                 core_ready,          // slave took it
  output logic                 core_rvalid,         // read data is live
  output logic [3:0]           core_rid,            // answers this request
  output logic                 core_rerr,

  // the internal request bundle
  output logic                 req_valid,
  input  logic                 req_ready,
  output l1i_addr_t                req_addr,
  output logic [3:0]          req_id,
  output logic                 req_prefetch,
  output logic                 req_uncached,

  // the internal response
  input  logic                 rsp_valid,
  input  logic [3:0]          rsp_id,
  input  logic [511:0]        rsp_data,
  input  logic                 rsp_err
);

  // NOTHING IS REGISTERED HERE. A holding register would
  // be a second place a request could sit, and the free
  // list of identifiers is already the flow control.
  assign req_valid             = core_valid;
  assign req_addr              = l1i_addr_t'(core_addr);
  assign req_id                = core_id;
  assign req_prefetch          = core_prefetch;
  assign req_uncached          = core_uncached;
  assign core_ready            = req_ready;

  assign core_rvalid           = rsp_valid;
  assign core_rid              = rsp_id;
  assign core_rdata            = rsp_data;
  assign core_rerr             = rsp_err;

  // this link declares no response ready, so the requester
  // takes every response in the cycle it is presented and
  // there is nothing to hold one in

  // the clock and reset reach the file behind this adapter
  // rather than any state of its own
  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_ck = |{clk, rstn};
  /* verilator lint_on UNUSEDSIGNAL */

endmodule
