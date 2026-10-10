// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      l1i_meta_array.sv
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// Metadata of node 'l1i': tag, valid and the
// replacement state, all addressed by the set index.
//
// Declared storage:
//   tag    inferred_sram, registered
//   valid  flop_file, combinational, cleared on reset
//   repl   flop_file, combinational
//
// The read port presented is REGISTERED, the slowest of the four.
//
// The valid bits ARE cleared on reset, which is the non
// synthesizable reset clear loop of D-40. It is emitted as
// the configuration asks and is correct for a flop file.
//
// PACINO CHANGES (BP-123, CG-D1): inv_all clears every valid bit and
// every replacement state in one cycle (l1i_ifu_interfaces.md IF-42),
// beside inv_en's one set, which now carries invalidate_line.
//
// PACINO CHANGES (BP-125, TD#172): fp_en / fp_set / fp_way, the
// replacement update of an install whose lookup did not move it (a
// cacheable request merged onto an uncached register, L1I-24).
//--------------------------------------------------------------------
// The import is at file scope and before the module, which is what
// the project verilog style asks for. Verilator's IMPORTSTAR objects
// to a wildcard in $unit scope, so it is turned off across these
// lines and nowhere else.
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
/* verilator lint_on IMPORTSTAR */

module l1i_meta_array (
  input  logic  clk,
  input  logic  rstn,

  // read port, one set, every way
  input  l1i_set_t  rd_set,
  output l1i_tag_t  rd_tag   [L1iWays],
  output logic  rd_valid [L1iWays],
  output l1i_repl_state_t rd_repl,

  // allocate one way of one set
  input  logic  wr_en,
  input  l1i_set_t  wr_set,
  input  l1i_way_t  wr_way,
  input  l1i_tag_t  wr_tag,
  input  logic  wr_valid,

  // replacement state write back
  input  logic  rp_en,
  input  l1i_set_t  rp_set,
  input  l1i_repl_state_t rp_val,

  // the replacement update of an install (BP-125): the way is made
  // most recently used in its set
  input  logic  fp_en,
  input  l1i_set_t  fp_set,
  input  l1i_way_t  fp_way,

  // invalidate every way of one set, the post reset walk; and
  // every set at once, the invalidate_all of L1I-18 (BP-123)
  input  logic  inv_en,
  input  logic  inv_all,
  input  l1i_set_t  inv_set
);

  l1i_tag_t        tag_mem  [L1iWays][L1iSetsPerBank];
  logic        val_mem  [L1iWays][L1iSetsPerBank];
  l1i_repl_state_t repl_mem [L1iSetsPerBank];

  always_ff @(posedge clk) begin
    if(wr_en) tag_mem[wr_way][wr_set] <= wr_tag;
  end

  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) begin
      // D-40, the reset clear loop. Correct for a flop
      // file and not synthesizable for a memory macro.
      for(int unsigned w = 0; w < L1iWays; w++) begin
        for(int unsigned s = 0; s < L1iSetsPerBank; s++) begin
          val_mem[w][s] <= 1'b0;
        end
      end
    end else begin
      if(inv_all) begin
        for(int unsigned w = 0; w < L1iWays; w++) begin
          for(int unsigned s = 0; s < L1iSetsPerBank; s++) begin
            val_mem[w][s] <= 1'b0;
          end
        end
      end else if(inv_en) begin
        for(int unsigned w = 0; w < L1iWays; w++) begin
          val_mem[w][inv_set] <= 1'b0;
        end
      end
      if(wr_en) val_mem[wr_way][wr_set] <= wr_valid;
    end
  end

  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) begin
      for(int unsigned s = 0; s < L1iSetsPerBank; s++) begin
        repl_mem[s] <= L1iReplReset;
      end
    end else begin
      if(inv_all) begin
        for(int unsigned s = 0; s < L1iSetsPerBank; s++) begin
          repl_mem[s] <= L1iReplReset;
        end
      end else if(inv_en) begin
        repl_mem[inv_set] <= L1iReplReset;
      end
      if(rp_en)  repl_mem[rp_set]  <= rp_val;
      // BP-125. After the compare stage's write, so that when both name
      // one set in one cycle the install's way is moved on top of the
      // compare stage's value and neither update is lost.
      if(fp_en)
        repl_mem[fp_set] <= l1i_repl_update(
            (rp_en && (rp_set == fp_set)) ? rp_val : repl_mem[fp_set],
            fp_way);
    end
  end

  always_ff @(posedge clk) begin
    for(int unsigned w = 0; w < L1iWays; w++) begin
      rd_tag[w]   <= tag_mem[w][rd_set];
      rd_valid[w] <= val_mem[w][rd_set];
    end
    rd_repl <= repl_mem[rd_set];
  end

endmodule
