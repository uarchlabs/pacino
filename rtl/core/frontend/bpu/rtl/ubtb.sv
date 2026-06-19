// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    ubtb.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Micro Branch Target Buffer: 256-entry, 4-way set-associative.
// First predictor in the BP cluster pipeline (s1 output).
// Combinational prediction from registered SRAM contents.
// Synchronous update on clk posedge when upd.valid.
//
// uBTB pipeline timing:
// s0: pred_pc_p0 presented. Index and tag derived comb.
// s1: mem is registered. pred output is comb from mem.
//     pred valid at start of s1 (one cycle after pred_pc_p0).
// Update: synchronous write on clk posedge when upd.valid.
//
// This has not been validated
//
// ===================================================================

`ifndef UBTB_SV
`define UBTB_SV

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ubtb #(
  parameter int NUM_PRED_SLOTS = 1
)(
  input  logic                             clk,
  input  logic                             rstn,
  input  logic [VA_WIDTH-1:0]              pred_pc_p0,
  output ubtb_pred_t [NUM_PRED_SLOTS-1:0]  pred_p1,
  input  ubtb_upd_t  [NUM_PRED_SLOTS-1:0]  upd_u0
);

  // ----------------------------------------------------------------
  // Storage
  // ----------------------------------------------------------------
  // mem[set][way]: UBTB_SETS=64, UBTB_WAYS=4
  ubtb_entry_t mem[UBTB_SETS][UBTB_WAYS];

  // Per-set write pointer for round-robin replacement on miss.
  // Width: $clog2(UBTB_WAYS) = 2
  localparam int WR_PTR_BITS = $clog2(UBTB_WAYS);
  logic [WR_PTR_BITS-1:0] wr_ptr[UBTB_SETS];

  // ----------------------------------------------------------------
  // Index and tag extraction functions
  // ----------------------------------------------------------------
  // Index: PC[UBTB_IDX_BITS+1:2] = PC[7:2], 6 bits
  // Tag:   PC[UBTB_TAG_BITS+UBTB_IDX_BITS+1:UBTB_IDX_BITS+2]
  //        = PC[26:7], 20 bits

  function automatic logic [UBTB_IDX_BITS-1:0] get_idx(
    input logic [VA_WIDTH-1:0] pc
  );
    return pc[UBTB_IDX_BITS+1:2];
  endfunction

  function automatic logic [UBTB_TAG_BITS-1:0] get_tag(
    input logic [VA_WIDTH-1:0] pc
  );
    return pc[UBTB_TAG_BITS+UBTB_IDX_BITS+1:UBTB_IDX_BITS+2];
  endfunction

  // carry: target is in a different 32B block than pc
  function automatic logic get_carry(
    input logic [VA_WIDTH-1:0] pc,
    input logic [VA_WIDTH-1:0] target
  );
    return (target[VA_WIDTH-1:5] != pc[VA_WIDTH-1:5]);
  endfunction

  // ----------------------------------------------------------------
  // Reset and update path (synchronous)
  // ----------------------------------------------------------------
  integer s, w;
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      // Clear valid bits only (power saving -- other fields untouched)
      for (s = 0; s < UBTB_SETS; s++) begin
        for (w = 0; w < UBTB_WAYS; w++) begin
          mem[s][w].valid <= 1'b0;
        end
        wr_ptr[s] <= '0;
      end
    end else begin
      // Update channels: process each slot independently
      for (int u = 0; u < NUM_PRED_SLOTS; u++) begin
        if (upd_u0[u].valid) begin
          automatic logic [UBTB_IDX_BITS-1:0] uidx;
          automatic logic [UBTB_TAG_BITS-1:0] utag;
          automatic logic                     hit_found;
          automatic int                       hit_way;
          uidx      = get_idx(upd_u0[u].pc);
          utag      = get_tag(upd_u0[u].pc);
          hit_found = 1'b0;
          hit_way   = 0;
          // Search for existing entry (hit: update in place)
          for (int hw = 0; hw < UBTB_WAYS; hw++) begin
            if (mem[uidx][hw].valid && mem[uidx][hw].tag == utag) begin
              hit_found = 1'b1;
              hit_way   = hw;
            end
          end
          if (hit_found) begin
            mem[uidx][hit_way].br_type  <= upd_u0[u].br_type;
            mem[uidx][hit_way].target   <= upd_u0[u].target;
            mem[uidx][hit_way].br_taken <= upd_u0[u].br_taken;
            mem[uidx][hit_way].carry    <= upd_u0[u].carry;
          end else begin
            // Miss: write to current write pointer way
            mem[uidx][wr_ptr[uidx]].valid    <= 1'b1;
            mem[uidx][wr_ptr[uidx]].tag      <= utag;
            mem[uidx][wr_ptr[uidx]].br_type  <= upd_u0[u].br_type;
            mem[uidx][wr_ptr[uidx]].target   <= upd_u0[u].target;
            mem[uidx][wr_ptr[uidx]].br_taken <= upd_u0[u].br_taken;
            mem[uidx][wr_ptr[uidx]].carry    <= upd_u0[u].carry;
            wr_ptr[uidx] <= wr_ptr[uidx] + 1'b1;
          end
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // Prediction path (combinational from registered mem)
  // ----------------------------------------------------------------
  // Slot 0: uses pred_pc_p0 directly.
  // Slot 1: uses pred_pc_p0 + 32 (next 32B-aligned block).
  // Read-during-write: reflects pre-update state (no bypass).
  generate
    genvar gs;
    for (gs = 0; gs < NUM_PRED_SLOTS; gs++) begin : gen_pred
      logic [VA_WIDTH-1:0]      slot_pc;
      logic [UBTB_IDX_BITS-1:0] slot_idx;
      logic [UBTB_TAG_BITS-1:0] slot_tag;

      // Slot 1 looks ahead by one 32B block
      assign slot_pc  = pred_pc_p0 + (VA_WIDTH'(gs) * VA_WIDTH'(32));
      assign slot_idx = get_idx(slot_pc);
      assign slot_tag = get_tag(slot_pc);

      // Combinational way search
      always_comb begin
        pred_p1[gs] = '0; // default: miss
        for (int pw = 0; pw < UBTB_WAYS; pw++) begin
          if (mem[slot_idx][pw].valid &&
              mem[slot_idx][pw].tag == slot_tag) begin
            pred_p1[gs].valid    = 1'b1;
            pred_p1[gs].target   = mem[slot_idx][pw].target;
            pred_p1[gs].br_type  = mem[slot_idx][pw].br_type;
            pred_p1[gs].br_taken = mem[slot_idx][pw].br_taken;
            pred_p1[gs].carry    = mem[slot_idx][pw].carry;
          end
        end
      end
    end
  endgenerate

endmodule : ubtb

`endif // UBTB_SV
