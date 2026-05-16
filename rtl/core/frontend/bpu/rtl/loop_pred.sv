// ===================================================================
// FILE:    loop_pred.sv
// DATE:    2026-03-30
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Loop predictor: 256-entry 4-way set-associative, s1-stage.
// Detects backward branches with constant iteration counts
// and predicts loop exit. Overrides uBTB at s1 when trusted.
// pred_is_loop=1 only when conf==LP_CONF_LEVEL (max confidence).
// Overriding uBTB at s1 is the cluster override control's job.
// See loop_pred_interfaces.md for interface semantics.
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
  input  logic                clk,
  input  logic                rstn,
  input  logic [VA_WIDTH-1:0] pred_pc_p0,
  input  logic                pred_valid_p0,
  output lp_pred_t            pred_p0,
  input  lp_upd_t             upd_p0,
  input  logic                upd_valid_p0
);

  // ----------------------------------------------------------------
  // Storage: LP_N_SETS sets x LP_TBL_WAYS ways.
  // Combinational read, synchronous write.
  // ----------------------------------------------------------------
  lp_entry_t mem[LP_N_SETS][LP_TBL_WAYS];

  // ----------------------------------------------------------------
  // Prediction pipeline signals (s0 combinational -> s1 registered)
  // ----------------------------------------------------------------
  logic [LP_IDX_BITS-1:0] req_idx;
  logic [LP_TAG_BITS-1:0] req_tag;
  logic [LP_TBL_WAYS-1:0] inv_mask;
  logic [LP_TBL_WAYS-1:0] z_age_mask;
  logic                    any_hit;
  logic [LP_WAY_BITS-1:0]  hit_way;
  lp_entry_t               hit_entry;
  logic [LP_WAY_BITS-1:0]  victim_way;
  lp_pred_t                pred_comb;

  // ----------------------------------------------------------------
  // Update entry signals (computed combinationally, registered write)
  // ----------------------------------------------------------------
  lp_entry_t upd_entry_hit;
  lp_entry_t upd_entry_alloc;

  // ----------------------------------------------------------------
  // Index and tag derivation (exact hashes required by spec)
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
  // Combinational prediction logic
  // ----------------------------------------------------------------
  always_comb begin
    req_idx = idx_of(pred_pc_p0);
    req_tag = tag_of(pred_pc_p0);

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
    // pred_is_loop gated by pred_valid_p0: when input invalid,
    // output pred_is_loop=0, pred_taken=0.
    pred_comb.lp_idx          = req_idx;
    pred_comb.lp_tag          = req_tag;
    pred_comb.lp_way          = hit_way;
    pred_comb.lp_hit       = any_hit;
    pred_comb.lp_pred_is_loop = pred_valid_p0 && any_hit &&
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

  // ----------------------------------------------------------------
  // Combinational update entry computation
  // upd_entry_hit: used when upd_p0.lp_pred_is_loop=1 (trusted hit).
  // upd_entry_alloc: used on miss + backward branch allocation.
  // ----------------------------------------------------------------
  always_comb begin
    // Default: propagate captured state unchanged.
    // Condition-specific overrides follow.
    upd_entry_hit.v        = 1'b1;
    upd_entry_hit.tag      = upd_p0.lp_tag;
    upd_entry_hit.past_itr = upd_p0.lp_past_itr;
    upd_entry_hit.curr_itr = upd_p0.lp_curr_itr;
    upd_entry_hit.age      = upd_p0.lp_age;
    upd_entry_hit.cnf      = upd_p0.lp_conf;
    upd_entry_hit.curs     = upd_p0.lp_curs;
    upd_entry_hit.curs_v   = upd_p0.lp_curs_v;

    // Condition 4 (mispredicted exit) checked before condition 1
    // (taken branch hit) because condition 4 is a subset of 1.
    if (upd_p0.lp_pred_is_loop &&
        !upd_p0.lp_pred_taken && upd_p0.actual_taken) begin
      // Mispredicted exit: predicted exit, actual=taken.
      // Reset conf and current iteration counter.
      upd_entry_hit.cnf      = '0;
      upd_entry_hit.curr_itr = '0;
    end else if (upd_p0.actual_taken && upd_p0.lp_pred_is_loop) begin
      // Taken branch hit: loop body iteration.
      // Increment curr_itr; if curs_v, increment curs.
      upd_entry_hit.curr_itr =
        (&upd_p0.lp_curr_itr) ? upd_p0.lp_curr_itr
                           : upd_p0.lp_curr_itr + LP_ITR_BITS'(1);
      upd_entry_hit.curs =
        (upd_p0.lp_curs_v && !(&upd_p0.lp_curs)) ?
        upd_p0.lp_curs + LP_ITR_BITS'(1) : upd_p0.lp_curs;
    end else if (upd_p0.lp_hit && !upd_p0.lp_pred_is_loop &&
                 upd_p0.actual_taken) begin
      // Condition 5 (learning): hit, not trusted, actual taken.
      // Increment curr_itr; no confidence change.
      upd_entry_hit.curr_itr =
        (&upd_p0.lp_curr_itr) ? upd_p0.lp_curr_itr
                           : upd_p0.lp_curr_itr + LP_ITR_BITS'(1);
    end else if (upd_p0.lp_curr_itr == upd_p0.lp_past_itr) begin
      // Correct not-taken exit: commit iteration count.
      // Increment conf (saturate); reset curr_itr; age=max.
      upd_entry_hit.cnf =
        (&upd_p0.lp_conf) ? upd_p0.lp_conf
                       : upd_p0.lp_conf + LP_CNF_BITS'(1);
      upd_entry_hit.past_itr = upd_p0.lp_curr_itr;
      upd_entry_hit.curr_itr = '0;
      upd_entry_hit.age      = {LP_AGE_BITS{1'b1}};
    end else begin
      // Wrong not-taken exit: iteration count mismatch.
      // Reset conf; copy curr_itr to past_itr; reset curr_itr.
      upd_entry_hit.cnf      = '0;
      upd_entry_hit.past_itr = upd_p0.lp_curr_itr;
      upd_entry_hit.curr_itr = '0;
    end

    // Allocation entry for miss + backward branch.
    // curr_itr=1: first iteration already observed.
    upd_entry_alloc.v        = 1'b1;
    upd_entry_alloc.tag      = upd_p0.lp_tag;
    upd_entry_alloc.past_itr = '0;
    upd_entry_alloc.curr_itr = LP_ITR_BITS'(1);
    upd_entry_alloc.cnf      = '0;
    upd_entry_alloc.age      = {LP_AGE_BITS{1'b1}};
    upd_entry_alloc.curs     = '0;
    upd_entry_alloc.curs_v   = 1'b0;
  end

  // ----------------------------------------------------------------
  // Synchronous memory update
  // ----------------------------------------------------------------
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      for (int s = 0; s < LP_N_SETS; s++) begin
        for (int w = 0; w < LP_TBL_WAYS; w++) begin
          mem[s][w] <= '0;
        end
      end
    end else if (upd_valid_p0) begin
      if (upd_p0.lp_pred_is_loop || upd_p0.lp_hit) begin
        // Hit: write updated entry to way identified at predict.
        mem[upd_p0.lp_idx][upd_p0.lp_way] <= upd_entry_hit;
      end else if (upd_p0.actual_taken &&
                   (upd_p0.target < upd_p0.pc)) begin
        // Miss + backward branch: allocate at victim way.
        mem[upd_p0.lp_idx][upd_p0.lp_victim] <= upd_entry_alloc;
      end
    end
  end

  // ----------------------------------------------------------------
  // Prediction output register (s0 comb -> s1 registered output)
  // ----------------------------------------------------------------
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      pred_p0 <= '0;
    end else begin
      pred_p0 <= pred_comb;
    end
  end

endmodule : loop_pred

`endif // LOOP_PRED_SV
