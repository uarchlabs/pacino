// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      l1i_data_array.sv
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// Line storage of node 'l1i'. 8 ways of 64 sets,
// 64 bytes a line.
//
// Declared inferred_sram, registered read, byte enables off.
//
// With byte enables off the only write is a whole line, which
// is what a fill does. This node takes no partial write.
//--------------------------------------------------------------------
// The import is at file scope and before the module, which is what
// the project verilog style asks for. Verilator's IMPORTSTAR objects
// to a wildcard in $unit scope, so it is turned off across these
// lines and nowhere else.
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
/* verilator lint_on IMPORTSTAR */

module l1i_data_array (
  input  logic  clk,

  input  l1i_set_t  rd_set,
  output l1i_line_t rd_line [L1iWays],

  input  logic  wr_en,
  input  l1i_set_t  wr_set,
  input  l1i_way_t  wr_way,
  input  l1i_line_t wr_line
);

  l1i_line_t data_mem [L1iWays][L1iSetsPerBank];

  always_ff @(posedge clk) begin
    if(wr_en) begin
      data_mem[wr_way][wr_set] <= wr_line;
    end
  end

  always_ff @(posedge clk) begin
    for(int unsigned w = 0; w < L1iWays; w++) begin
      rd_line[w] <= data_mem[w][rd_set];
    end
  end

endmodule
