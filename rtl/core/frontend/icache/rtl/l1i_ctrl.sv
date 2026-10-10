// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      l1i_ctrl.sv
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// Control of one bank of node 'l1i', PIPELINED.
//
// It accepts one access a cycle and answers a hit 2 cycles
// after the acceptance. Both numbers come from the configuration:
//
//   read_latency_cycles  2
//   tag_compare_stage    next_cycle, so the compare is in stage 1
//   tag array read port  registered, its output is in stage 1
//   pad stages           0, carrying the answer and nothing else
//
//   read miss    allocate
//   replacement  tree_plru
//
// A MISS DOES NOT STALL THE PIPELINE. It reports its line and its
// victim way in the compare stage and leaves; the register the
// miss handling file allocated when the access was accepted is
// what remembers it, and the line comes back through the fill
// port rather than through this pipeline.
//
// The victim is the LOWEST NUMBERED INVALID WAY when there is
// one, and the replacement victim otherwise. That tie break is a
// generator convention, D-40, and it makes a cold set fill from
// way 0 upward, which is what a testbench can predict.
//
// PACINO CHANGES (BP-123, cachegen_decisions.md CG-D1):
//   - UNCACHED LOOKUPS (icache_decisions.md L1I-24). req_unc marks an
//     access that is a miss whatever the tags hold. It is reported as
//     a miss in the compare stage like any miss, and it does NOT move
//     the replacement state. Its way is the way the line already
//     occupies when it is resident, else the victim, so a cacheable
//     request merged onto its register later installs over the
//     resident copy rather than beside it. Whether the fill is
//     written is the miss handling file's decision (it may not be).
//   - INVALIDATE (L1I-18, l1i_ifu_interfaces.md IF-29, IF-42). inv_en
//     clears every way of one set, inv_all every set, in one cycle,
//     through the metadata array's clear port that the reset walk
//     uses. The maintenance control decides when.
//--------------------------------------------------------------------
// The import is at file scope and before the module, which is what
// the project verilog style asks for. Verilator's IMPORTSTAR objects
// to a wildcard in $unit scope, so it is turned off across these
// lines and nowhere else.
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
/* verilator lint_on IMPORTSTAR */

module l1i_ctrl (
  input  logic  clk,
  input  logic  rstn,

  // the lookup, one access a cycle
  input  logic  req_valid,
  output logic  req_ready,
  input  l1i_addr_t req_addr,
  input  l1i_mshr_t req_src,
  input  logic  req_unc,        // L1I-24, a forced miss

  // the invalidate, from the maintenance control (IF-29, IF-42)
  input  logic  inv_en,
  input  logic  inv_all,
  input  l1i_set_t  inv_set,

  // The hit answer. It is the WHOLE LINE and it leaves
  // combinationally, because the last stage of the hit path
  // is the miss handling file's register and not this
  // pipeline's. The word inside it is selected there, where
  // the offset each target asked for is kept.
  output logic  rsp_valid,
  output l1i_line_t rsp_data,
  output logic  rsp_err,
  output l1i_mshr_t rsp_src,

  // the miss report, in the compare stage
  output logic  mis_valid,
  output l1i_addr_t mis_line,
  output l1i_mshr_t mis_src,
  output l1i_way_t  mis_way,

  // the fill write, from the miss handling file
  input  logic  fil_valid,
  input  l1i_addr_t fil_line,
  input  l1i_way_t  fil_way,
  input  l1i_line_t fil_data,

  // the metadata array
  output l1i_set_t  meta_rd_set,
  input  l1i_tag_t  meta_rd_tag   [L1iWays],
  input  logic  meta_rd_valid [L1iWays],
  input  l1i_repl_state_t meta_rd_repl,
  output logic  meta_wr_en,
  output l1i_set_t  meta_wr_set,
  output l1i_way_t  meta_wr_way,
  output l1i_tag_t  meta_wr_tag,
  output logic  meta_wr_valid,
  output logic  meta_rp_en,
  output l1i_set_t  meta_rp_set,
  output l1i_repl_state_t meta_rp_val,
  output logic  meta_inv_en,
  output logic  meta_inv_all,
  output l1i_set_t  meta_inv_set,

  // the data array
  output l1i_set_t  data_rd_set,
  input  l1i_line_t data_rd_line [L1iWays],
  output logic  data_wr_en,
  output l1i_set_t  data_wr_set,
  output l1i_way_t  data_wr_way,
  output l1i_line_t data_wr_line
);

  // The valid bits are CLEARED ON RESET, so there is no walk
  // to run and nothing takes the pipeline's ready down. It
  // takes an access in the first cycle after rstn rises.
  // The clear port carries the invalidate (BP-123).
  assign meta_inv_en  = inv_en;
  assign meta_inv_all = inv_all;
  assign meta_inv_set = inv_set;
  assign req_ready    = 1'b1;

  wire accept = req_valid && req_ready;

  // ---------------------------------------------------------
  // STAGE 0. The set of the access being accepted is presented
  // to both arrays. The read is issued every cycle whether or
  // not one was accepted; the stage below says whether its
  // result belongs to anything.
  // ---------------------------------------------------------
  wire l1i_set_t cur_set = l1i_set_of(req_addr);

  assign meta_rd_set = cur_set;
  assign data_rd_set = cur_set;

  // ---------------------------------------------------------
  // STAGE 1, THE COMPARE.
  // tag_compare_stage is next_cycle, so the access is
  // carried one cycle to meet the array output.
  // ---------------------------------------------------------
  logic  c_val;
  l1i_addr_t c_addr;
  l1i_mshr_t c_src;
  logic  c_unc;

  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) begin
      c_val  <= 1'b0;
      c_addr <= '0;
      c_src  <= '0;
      c_unc  <= 1'b0;
    end else begin
      c_val  <= accept;
      c_addr <= req_addr;
      c_src  <= req_src;
      c_unc  <= req_unc;
    end
  end

  // ---------------------------------------------------------
  // Hit, and which way hit. One comparator per way, which is
  // what way_access inferred_sram parallel lookup asks for.
  // ---------------------------------------------------------
  logic [L1iWays-1:0] hitv;
  logic            hit;
  l1i_way_t            hit_way;

  always_comb begin
    hitv = '0;
    for(int unsigned w = 0; w < L1iWays; w++) begin
      if(meta_rd_valid[w] &&
         (meta_rd_tag[w] == l1i_tag_of(c_addr))) begin
        hitv[w] = 1'b1;
      end
    end
  end

  always_comb begin
    hit     = |hitv;
    hit_way = '0;
    for(int unsigned w = 0; w < L1iWays; w++) begin
      if(hitv[w]) hit_way = l1i_way_t'(w);
    end
  end

  // ---------------------------------------------------------
  // The victim, chosen HERE and carried by the miss report.
  // The set's replacement state is in front of the compare
  // already, so the fill does not have to read the array a
  // second time when it comes back. An invalid way is always
  // taken first and the LOWEST numbered one wins the tie.
  // D-40.
  // ---------------------------------------------------------
  logic any_inv;
  l1i_way_t inv_way;
  l1i_way_t victim;

  always_comb begin
    any_inv = 1'b0;
    inv_way = '0;
    // counting down leaves the lowest numbered invalid way
    for(int unsigned w = L1iWays; w > 0; w--) begin
      if(!meta_rd_valid[w-1]) begin
        any_inv = 1'b1;
        inv_way = l1i_way_t'(w-1);
      end
    end
  end

  assign victim = any_inv ? inv_way : l1i_repl_victim(meta_rd_repl);

  // L1I-24: an uncached access is a miss whatever the tags hold.
  wire c_hit  = c_val &&  hit && !c_unc;
  wire c_miss = c_val && (!hit || c_unc);

  // ---------------------------------------------------------
  // THE MISS REPORT. One cycle, in the compare stage, and the
  // access is out of the pipeline. It carries no ready: the
  // register it names was allocated when the access was
  // accepted, so the file has room for it by construction.
  // ---------------------------------------------------------
  assign mis_valid = c_miss;
  assign mis_line  = l1i_line_base(c_addr);
  assign mis_src   = c_src;
  // An uncached access to a resident line names the line's own
  // way, so a cacheable request merged onto its register later
  // installs over the copy rather than beside it (BP-123).
  assign mis_way   = (c_unc && hit) ? hit_way : victim;

  // ---------------------------------------------------------
  // THE ANSWER. It leaves stage 1 COMBINATIONALLY, and the
  // miss handling file's own register is what turns it into
  // a response. THIS PIPELINE IS THEREFORE ONE STAGE
  // SHORTER THAN L1iReadLatency: the last stage of the hit path
  // belongs to the file, which is also where a returned fill
  // arrives, so hits and fills leave through one scan and
  // one response per cycle.
  // ---------------------------------------------------------
  assign rsp_valid = c_hit;
  assign rsp_data  = data_rd_line[hit_way];
  assign rsp_err   = 1'b0;
  assign rsp_src   = c_src;

  // ---------------------------------------------------------
  // The replacement state moves in the COMPARE stage, on a
  // hit and on a miss alike, and that is the only place it
  // is written. Doing it here rather than when the fill
  // lands leaves one writer of the port instead of two, and
  // the way it names is the way the fill will use.
  // ---------------------------------------------------------
  // L1I-24: an uncached access does not move it (BP-123).
  assign meta_rp_en  = c_val && !c_unc;
  assign meta_rp_set = l1i_set_of(c_addr);
  assign meta_rp_val =
      l1i_repl_update(meta_rd_repl, hit ? hit_way : victim);

  // ---------------------------------------------------------
  // INSTALLING A LINE. The miss handling file drives this
  // when the fill it asked for has come back, and it is the
  // only writer of the tag, the valid bit and the data.
  // ---------------------------------------------------------
  assign meta_wr_en    = fil_valid;
  assign meta_wr_set   = l1i_set_of(fil_line);
  assign meta_wr_way   = fil_way;
  assign meta_wr_tag   = l1i_tag_of(fil_line);
  assign meta_wr_valid = 1'b1;

  assign data_wr_en    = fil_valid;
  assign data_wr_set   = l1i_set_of(fil_line);
  assign data_wr_way   = fil_way;
  assign data_wr_line  = fil_data;

  // ---------------------------------------------------------
  // A FILL AND AN ACCESS IN THE SAME CYCLE. Both proceed:
  // the arrays carry a read port and a write port, the fill
  // lands on the edge that ends this cycle, and the access
  // reads the set as it was before it. NEITHER IS DROPPED
  // AND NEITHER IS DELAYED.
  //
  // The one outcome that would be wrong is an access to the
  // LINE being filled reporting a miss, because that is a
  // second register fetching a line already on its way in.
  // It cannot happen: the miss handling file merges such a
  // request onto the register that owns the line, and it
  // stops merging on the same edge that writes the array.
  // The check says so rather than leaving it resting on
  // that.
  // ---------------------------------------------------------
  always_ff @(posedge clk) begin
    if(fil_valid && c_miss && !c_unc &&
       (l1i_line_base(c_addr) == fil_line))
    begin
      $error("l1i_ctrl: an access missed on the line being filled");
    end
  end

endmodule
