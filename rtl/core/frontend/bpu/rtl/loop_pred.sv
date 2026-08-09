// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    loop_pred.sv
// DATE:    2026-05-20
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Loop predictor: 256-entry 4-way set-associative per slot, p1 stage.
// Detects backward branches with constant iteration counts
// and predicts loop exit. Overrides uBTB at p1 when trusted.
// lp_pred_is_loop=1 only when cnf==LP_CONF_LEVEL (max confidence).
// Overriding uBTB at p1 is the cluster override control's job.
// See loop_pred_interfaces.md for interface semantics.
//
// Slot dimension (TD#105). Every prediction and update port carries
// NUM_PRED_SLOTS entries and the table is replicated as one bank per
// slot (TI6). The per-slot prediction algorithm is unchanged.
//
// All slots index from the single p0 request PC presented on their
// own pred_pc_p0 element. There is no per-slot PC derivation inside
// this module: the index and tag hashes take no slot discriminator,
// so two slots given the same PC read the same set and way of their
// own bank. The banks diverge only because they are written by
// different slots' updates.
//
// pred_p1 is a registered output. It is presented one cycle after
// the pred_pc_p0 that produced it, which is the p1 cycle for a p0
// request; the port is named for the stage at which it is valid.
// ===================================================================

`ifndef LOOP_PRED_SV
`define LOOP_PRED_SV

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module loop_pred #(
  parameter int LP_TBL_ENTRIES = 256,
  parameter int LP_TBL_WAYS    = 4,
  parameter int LP_TAG_BITS    = 14,
  parameter int LP_ITR_BITS    = 14,
  parameter int LP_CNF_BITS    = 2,
  parameter int LP_AGE_BITS    = 8,
  parameter int LP_N_SETS      = LP_TBL_ENTRIES / LP_TBL_WAYS,
  parameter int LP_IDX_BITS    = $clog2(LP_N_SETS),
  parameter int LP_CONF_LEVEL  = (1 << LP_CNF_BITS) - 1,
  parameter int NUM_PRED_SLOTS = 1
) (
  input  logic                      clk,
  input  logic                      rstn,
  input  logic [VA_WIDTH-1:0]       pred_pc_p0 [0:NUM_PRED_SLOTS-1],
  input  logic [NUM_PRED_SLOTS-1:0] pred_valid_p0,
  output lp_pred_t                  pred_p1    [0:NUM_PRED_SLOTS-1],
  input  lp_upd_t                   upd_p0     [0:NUM_PRED_SLOTS-1],
  input  logic [NUM_PRED_SLOTS-1:0] upd_valid_p0
);

  // ----------------------------------------------------------------
  // Index and tag derivation (exact hashes required by spec).
  // Module scope: the functions are automatic and are called once per
  // bank from inside the slot loop. They take no slot argument -- the
  // slot is not part of the hash (BP-091 decision 3).
  // ----------------------------------------------------------------
  function automatic logic [LP_IDX_BITS-1:0]
      idx_of(input logic [VA_WIDTH-1:0] pc);
    logic [VA_WIDTH-1:0] x;
    x = pc ^ (pc >> 1) ^ (pc >> 4);
    return x[LP_IDX_BITS-1:0];
  endfunction

  function automatic logic [LP_TAG_BITS-1:0]
      tag_of(input logic [VA_WIDTH-1:0] pc);
    logic [VA_WIDTH-1:0] x;
    x = pc ^ (pc >> 6) ^ (pc >> 12);
    return x[LP_TAG_BITS-1:0];
  endfunction

  // ----------------------------------------------------------------
  // Per-slot bank and per-slot logic.
  // One generate for loop over the slot index, one level only. The
  // loop body holds the bank storage, the prediction datapath, the
  // update datapath and the two sequential blocks for that slot. No
  // nested generate: the per-entry loops below are procedural for
  // loops inside always blocks, not generated logic.
  // ----------------------------------------------------------------
  genvar s;
  generate
    for (s = 0; s < NUM_PRED_SLOTS; s++) begin : g_slot

      // Storage: LP_N_SETS sets x LP_TBL_WAYS ways, one bank per
      // slot. Combinational read, synchronous write.
      lp_entry_t mem[LP_N_SETS][LP_TBL_WAYS];

      // Prediction pipeline signals (p0 comb -> p1 registered)
      logic [LP_IDX_BITS-1:0] req_idx;
      logic [LP_TAG_BITS-1:0] req_tag;
      logic [LP_TBL_WAYS-1:0] inv_mask;
      logic [LP_TBL_WAYS-1:0] z_age_mask;
      logic                   any_hit;
      logic [LP_WAY_BITS-1:0] hit_way;
      lp_entry_t              hit_entry;
      logic [LP_WAY_BITS-1:0] victim_way;
      lp_pred_t               pred_comb;

      // Update entry signals (computed comb, registered write)
      lp_entry_t upd_entry_hit;
      lp_entry_t upd_entry_alloc;

      // ------------------------------------------------------------
      // Combinational prediction logic
      // ------------------------------------------------------------
      always_comb begin
        req_idx = idx_of(pred_pc_p0[s]);
        req_tag = tag_of(pred_pc_p0[s]);

        // Compute invalid and zero-age masks for victim selection.
        for (int w = 0; w < LP_TBL_WAYS; w++) begin
          inv_mask[w]   = ~mem[req_idx][w].v;
          z_age_mask[w] = mem[req_idx][w].v &
                          (mem[req_idx][w].age == '0);
        end

        // Hit detection. Scan high->low so the lowest-indexed
        // matching way wins via last-write-wins assignment.
        any_hit   = 1'b0;
        hit_way   = '0;
        hit_entry = mem[req_idx][0];
        for (int w = LP_TBL_WAYS - 1; w >= 0; w--) begin
          if (mem[req_idx][w].v &&
              (mem[req_idx][w].tag == req_tag)) begin
            any_hit   = 1'b1;
            hit_way   = w[LP_WAY_BITS-1:0];
            hit_entry = mem[req_idx][w];
          end
        end

        // Victim selection
        if (|inv_mask) begin
          // Priority 1: lowest-indexed invalid way.
          victim_way = '0;
          for (int w = LP_TBL_WAYS - 1; w >= 0; w--) begin
            if (inv_mask[w]) victim_way = w[LP_WAY_BITS-1:0];
          end
        end else if (|z_age_mask) begin
          // Priority 2: lowest-indexed valid zero-age way.
          victim_way = '0;
          for (int w = LP_TBL_WAYS - 1; w >= 0; w--) begin
            if (z_age_mask[w]) victim_way = w[LP_WAY_BITS-1:0];
          end
        end else begin
          // Priority 3: way whose age < way[0].age.
          // Check way 1 first (highest priority), then 2, then 3.
          // Default to way 0 if no qualifying way found.
          if (mem[req_idx][1].age < mem[req_idx][0].age)
            victim_way = LP_WAY_BITS'(1);
          else if (mem[req_idx][2].age < mem[req_idx][0].age)
            victim_way = LP_WAY_BITS'(2);
          else if (mem[req_idx][3].age < mem[req_idx][0].age)
            victim_way = LP_WAY_BITS'(3);
          else
            victim_way = '0;
        end

        // Build combinational prediction output.
        // lp_pred_is_loop gated by pred_valid_p0[s]: when the slot
        // input is invalid, lp_pred_is_loop=0 and lp_pred_taken=0.
        pred_comb.lp_idx          = req_idx;
        pred_comb.lp_tag          = req_tag;
        pred_comb.lp_way          = hit_way;
        pred_comb.lp_hit          = any_hit;
        pred_comb.lp_pred_is_loop = pred_valid_p0[s] && any_hit &&
                              (hit_entry.cnf == {LP_CNF_BITS{1'b1}});
        pred_comb.lp_pred_taken   = pred_comb.lp_pred_is_loop &&
                              (hit_entry.curr_itr < hit_entry.past_itr);
        pred_comb.lp_age          = hit_entry.age;
        pred_comb.lp_conf         = hit_entry.cnf;
        pred_comb.lp_past_itr     = hit_entry.past_itr;
        pred_comb.lp_curr_itr     = hit_entry.curr_itr;
        pred_comb.lp_curs         = hit_entry.curs;
        pred_comb.lp_curs_v       = hit_entry.curs_v;
        pred_comb.lp_victim       = victim_way;
      end

      // ------------------------------------------------------------
      // Combinational update entry computation
      // upd_entry_hit:   used when upd_p0[s].lp_pred_is_loop=1
      //                  (trusted hit).
      // upd_entry_alloc: used on miss + backward branch allocation.
      // ------------------------------------------------------------
      always_comb begin
        // Default: propagate captured state unchanged.
        // Condition-specific overrides follow.
        upd_entry_hit.v        = 1'b1;
        upd_entry_hit.tag      = upd_p0[s].lp_tag;
        upd_entry_hit.past_itr = upd_p0[s].lp_past_itr;
        upd_entry_hit.curr_itr = upd_p0[s].lp_curr_itr;
        upd_entry_hit.age      = upd_p0[s].lp_age;
        upd_entry_hit.cnf      = upd_p0[s].lp_conf;
        upd_entry_hit.curs     = upd_p0[s].lp_curs;
        upd_entry_hit.curs_v   = upd_p0[s].lp_curs_v;

        // Condition 4 (mispredicted exit) checked before condition 1
        // (taken branch hit) because condition 4 is a subset of 1.
        if (upd_p0[s].lp_pred_is_loop &&
            !upd_p0[s].lp_pred_taken && upd_p0[s].actual_taken) begin
          // Mispredicted exit: predicted exit, actual=taken.
          // Reset conf and current iteration counter.
          upd_entry_hit.cnf      = '0;
          upd_entry_hit.curr_itr = '0;
        end else if (upd_p0[s].actual_taken &&
                     upd_p0[s].lp_pred_is_loop) begin
          // Taken branch hit: loop body iteration.
          // Increment curr_itr; if curs_v, increment curs.
          upd_entry_hit.curr_itr =
            (&upd_p0[s].lp_curr_itr) ? upd_p0[s].lp_curr_itr
                        : upd_p0[s].lp_curr_itr + LP_ITR_BITS'(1);
          upd_entry_hit.curs =
            (upd_p0[s].lp_curs_v && !(&upd_p0[s].lp_curs)) ?
            upd_p0[s].lp_curs + LP_ITR_BITS'(1) : upd_p0[s].lp_curs;
        end else if (upd_p0[s].lp_hit && !upd_p0[s].lp_pred_is_loop &&
                     upd_p0[s].actual_taken) begin
          // Condition 5 (learning): hit, not trusted, actual taken.
          // Increment curr_itr; no confidence change.
          upd_entry_hit.curr_itr =
            (&upd_p0[s].lp_curr_itr) ? upd_p0[s].lp_curr_itr
                        : upd_p0[s].lp_curr_itr + LP_ITR_BITS'(1);
        end else if (upd_p0[s].lp_curr_itr ==
                     upd_p0[s].lp_past_itr) begin
          // Correct not-taken exit: commit iteration count.
          // Increment conf (saturate); reset curr_itr; age=max.
          upd_entry_hit.cnf =
            (&upd_p0[s].lp_conf) ? upd_p0[s].lp_conf
                        : upd_p0[s].lp_conf + LP_CNF_BITS'(1);
          upd_entry_hit.past_itr = upd_p0[s].lp_curr_itr;
          upd_entry_hit.curr_itr = '0;
          upd_entry_hit.age      = {LP_AGE_BITS{1'b1}};
        end else begin
          // Wrong not-taken exit: iteration count mismatch.
          // Reset conf; copy curr_itr to past_itr; reset curr_itr.
          upd_entry_hit.cnf      = '0;
          upd_entry_hit.past_itr = upd_p0[s].lp_curr_itr;
          upd_entry_hit.curr_itr = '0;
        end

        // Allocation entry for miss + backward branch.
        // curr_itr=1: first iteration already observed.
        upd_entry_alloc.v        = 1'b1;
        upd_entry_alloc.tag      = upd_p0[s].lp_tag;
        upd_entry_alloc.past_itr = '0;
        upd_entry_alloc.curr_itr = LP_ITR_BITS'(1);
        upd_entry_alloc.cnf      = '0;
        upd_entry_alloc.age      = {LP_AGE_BITS{1'b1}};
        upd_entry_alloc.curs     = '0;
        upd_entry_alloc.curs_v   = 1'b0;
      end

      // ------------------------------------------------------------
      // Synchronous bank update. Slot s writes only bank s.
      // ------------------------------------------------------------
      always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
          for (int t = 0; t < LP_N_SETS; t++) begin
            for (int w = 0; w < LP_TBL_WAYS; w++) begin
              mem[t][w] <= '0;
            end
          end
        end else if (upd_valid_p0[s]) begin
          if (upd_p0[s].lp_pred_is_loop || upd_p0[s].lp_hit) begin
            // Hit: write updated entry to way identified at predict.
            mem[upd_p0[s].lp_idx][upd_p0[s].lp_way] <= upd_entry_hit;
          end else if (upd_p0[s].actual_taken &&
                       (upd_p0[s].target < upd_p0[s].pc)) begin
            // Miss + backward branch: allocate at victim way.
            mem[upd_p0[s].lp_idx][upd_p0[s].lp_victim] <=
              upd_entry_alloc;
          end
        end
      end

      // ------------------------------------------------------------
      // Prediction output register (p0 comb -> p1 registered output)
      // ------------------------------------------------------------
      always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
          pred_p1[s] <= '0;
        end else begin
          pred_p1[s] <= pred_comb;
        end
      end

    end
  endgenerate

endmodule : loop_pred

`endif // LOOP_PRED_SV
