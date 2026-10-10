// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      cgen_tl_pkg.sv
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// The TileLink 1.9.3 constant set, shared by every link in the
// system. The opcode space is emitted whole so that a consumer
// decoding a channel has every name, not only the ones this
// design happens to drive.
//--------------------------------------------------------------------
package cgen_tl_pkg;

  // A generated package states the protocol, and one module
  // consumes a subset of it. The constants are the artifact,
  // not dead code, so UNUSEDPARAM is off across the package.
  /* verilator lint_off UNUSEDPARAM */

  // Channel A opcodes, Table 15
  localparam logic [2:0] TlAPutFullData = 3'd0;
  localparam logic [2:0] TlAPutPartialData = 3'd1;
  localparam logic [2:0] TlAArithmeticData = 3'd2;
  localparam logic [2:0] TlALogicalData = 3'd3;
  localparam logic [2:0] TlAGet         = 3'd4;
  localparam logic [2:0] TlAIntent      = 3'd5;
  localparam logic [2:0] TlAAcquireBlock = 3'd6;
  localparam logic [2:0] TlAAcquirePerm = 3'd7;

  // Channel B opcodes, Table 16
  localparam logic [2:0] TlBPutFullData = 3'd0;
  localparam logic [2:0] TlBPutPartialData = 3'd1;
  localparam logic [2:0] TlBArithmeticData = 3'd2;
  localparam logic [2:0] TlBLogicalData = 3'd3;
  localparam logic [2:0] TlBGet         = 3'd4;
  localparam logic [2:0] TlBIntent      = 3'd5;
  localparam logic [2:0] TlBProbeBlock  = 3'd6;
  localparam logic [2:0] TlBProbePerm   = 3'd7;

  // Channel C opcodes, Table 17
  localparam logic [2:0] TlCAccessAck   = 3'd0;
  localparam logic [2:0] TlCAccessAckData = 3'd1;
  localparam logic [2:0] TlCHintAck     = 3'd2;
  localparam logic [2:0] TlCProbeAck    = 3'd4;
  localparam logic [2:0] TlCProbeAckData = 3'd5;
  localparam logic [2:0] TlCRelease     = 3'd6;
  localparam logic [2:0] TlCReleaseData = 3'd7;

  // Channel D opcodes, Table 18
  localparam logic [2:0] TlDAccessAck   = 3'd0;
  localparam logic [2:0] TlDAccessAckData = 3'd1;
  localparam logic [2:0] TlDHintAck     = 3'd2;
  localparam logic [2:0] TlDGrant       = 3'd4;
  localparam logic [2:0] TlDGrantData   = 3'd5;
  localparam logic [2:0] TlDReleaseAck  = 3'd6;

  // Cap, grow, prune and report parameters, TL-C
  localparam logic [2:0] TlCapToT       = 3'd0;
  localparam logic [2:0] TlCapToB       = 3'd1;
  localparam logic [2:0] TlCapToN       = 3'd2;
  localparam logic [2:0] TlGrowNtoB     = 3'd0;
  localparam logic [2:0] TlGrowNtoT     = 3'd1;
  localparam logic [2:0] TlGrowBtoT     = 3'd2;
  localparam logic [2:0] TlPruneTtoB    = 3'd0;
  localparam logic [2:0] TlPruneTtoN    = 3'd1;
  localparam logic [2:0] TlPruneBtoN    = 3'd2;
  localparam logic [2:0] TlReportTtoT   = 3'd3;
  localparam logic [2:0] TlReportBtoB   = 3'd4;
  localparam logic [2:0] TlReportNtoN   = 3'd5;

  localparam logic [2:0] TlParamZero = 3'd0;

  /* verilator lint_on UNUSEDPARAM */

endpackage
