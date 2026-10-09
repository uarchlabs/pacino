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
// lp_pred_is_loop=1 only when cnf==LP_CONF_LEVEL (max confidence)
// and the speculative iteration count is valid (BP-122).
// Overriding uBTB at p1 is the cluster override control's job.
// See loop_pred_interfaces.md for interface semantics.
//
// Slot dimension (TD#105). Every prediction and update port carries
// NUM_PRED_SLOTS entries and the table is replicated as one bank per
// slot (TI6). Every port below is per bank except rst_val, rst_idx,
// inv_val, spec_ck_p2 and spec_idx_p2, which name one FTQ entry or
// act on every bank alike.
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
//
// BP-122, TD#169, LI4 (ruled by Jeff, loop_pred_interfaces.md Ruled
// Change; restore option A and LP priority at p2 / p3 ruled in the
// BP-122 session). The table is flops, so:
//
//   - pred_p2 RE-READS the entry of the p1 lookup one cycle later.
//     Every older block has advanced its count by then, so pred_p2 is
//     the count this instance of the branch really has. It is the
//     authoritative LP prediction and the one the FTQ carries.
//   - THE ITERATION NUMBER. curs is the speculative count: taken
//     iterations of the loop on the predicted path since its last
//     exit. A prediction carries curs / curs_v as lp_curs /
//     lp_curs_v, and the direction is curs < past_itr.
//   - THE ADVANCE. spec_val_p2[s] / spec_tkn_p2[s] give the p2
//     direction of the conditional the bank describes; the count
//     steps by one on taken and returns to zero, valid, on not
//     taken (an exit resynchronises an invalid count).
//   - THE CHECKPOINT. Each p2 block records, per bank, the entry it
//     read and the count before its advance, at its FTQ index.
//   - THE RESTORE. rst_val names an FTQ entry: each bank's entry is
//     re-advanced from the checkpointed count by the corrected
//     direction (rst_ex / rst_tkn), or put back to the checkpointed
//     count when the slot did not execute.
//   - inv_val clears every count's valid (an FTQ-raised redirect,
//     whose squashed blocks may have advanced any entry). An entry
//     with an invalid count is not trusted until its next exit.
//   - THE UPDATE reads the entry before it writes it: it looks the
//     tag up again in the set and trains from the carried iteration
//     number, so the order updates arrive in does not matter. The
//     snapshot fields of lp_upd_t other than lp_idx, lp_tag and
//     lp_curs / lp_curs_v are not read.
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
  // BP-122: the p2 re-read, the advance, the checkpoint, the restore.
  output lp_pred_t                  pred_p2    [0:NUM_PRED_SLOTS-1],
  input  logic                      spec_ck_p2,
  input  logic [FTQ_IDX_BITS-1:0]   spec_idx_p2,
  input  logic [NUM_PRED_SLOTS-1:0] spec_val_p2,
  input  logic [NUM_PRED_SLOTS-1:0] spec_tkn_p2,
  input  logic                      rst_val,
  input  logic [FTQ_IDX_BITS-1:0]   rst_idx,
  input  logic [NUM_PRED_SLOTS-1:0] rst_ex,
  input  logic [NUM_PRED_SLOTS-1:0] rst_tkn,
  input  logic                      inv_val,
  input  lp_upd_t                   upd_p0     [0:NUM_PRED_SLOTS-1],
  input  logic [NUM_PRED_SLOTS-1:0] upd_valid_p0
);

  // Checkpoint entry: what a p2 block read in one bank.
  typedef struct packed {
    logic                   hit;   // the block's p2 lookup hit
    logic                   adv;   // the block advanced the entry
    logic [LP_IDX_BITS-1:0] idx;
    logic [LP_WAY_BITS-1:0] way;
    logic [LP_TAG_BITS-1:0] tag;
    logic [LP_ITR_BITS-1:0] itr;   // count before the advance
    logic                   itr_v;
  } lp_ck_t;

  localparam logic [LP_ITR_BITS-1:0] ITR_MAX = {LP_ITR_BITS{1'b1}};

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

  // The count after one instance: taken steps it (saturating, and an
  // invalid count stays invalid); not taken is an exit, after which
  // the count is zero and known.
  function automatic logic [LP_ITR_BITS:0]
      adv_of(input logic [LP_ITR_BITS-1:0] itr, input logic itr_v,
             input logic tkn);
    if (!tkn)
      return {1'b1, {LP_ITR_BITS{1'b0}}};
    return {itr_v, (itr == ITR_MAX) ? itr : itr + LP_ITR_BITS'(1)};
  endfunction

  // ----------------------------------------------------------------
  // Per-slot bank and per-slot logic.
  // One generate for loop over the slot index, one level only. The
  // loop body holds the bank storage, the prediction datapath, the
  // update datapath and the sequential blocks for that slot. No
  // nested generate: the per-entry loops below are procedural for
  // loops inside always blocks, not generated logic.
  // ----------------------------------------------------------------
  genvar s;
  generate
    for (s = 0; s < NUM_PRED_SLOTS; s++) begin : g_slot

      // Storage: LP_N_SETS sets x LP_TBL_WAYS ways, one bank per
      // slot. Combinational read, synchronous write.
      lp_entry_t mem[LP_N_SETS][LP_TBL_WAYS];

      // Checkpoint per FTQ entry (BP-122).
      lp_ck_t    ck[FTQ_DEPTH];

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

      // p2 re-read (BP-122). r2_* is the p1 lookup one cycle on.
      logic                   r1_val;
      logic                   r2_val;
      logic [LP_IDX_BITS-1:0] r2_idx;
      logic [LP_TAG_BITS-1:0] r2_tag;
      logic                   p2_hit;
      logic [LP_WAY_BITS-1:0] p2_way;
      lp_entry_t              p2_entry;
      lp_pred_t               p2_comb;
      logic [LP_ITR_BITS:0]   p2_adv;

      // Restore (BP-122): the checkpoint the rollback names.
      lp_ck_t                 rck;
      logic                   rck_live;
      logic [LP_ITR_BITS:0]   rck_val;

      // Update (BP-122, read before write).
      logic                   u_hit;
      logic [LP_WAY_BITS-1:0] u_way;
      lp_entry_t              u_entry;
      logic [LP_WAY_BITS-1:0] u_victim;
      lp_entry_t              u_new;
      logic                   u_alloc;

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
        // BP-122: the direction is the speculative count against the
        // learned trip count, and an invalid count is not trusted.
        pred_comb.lp_idx          = req_idx;
        pred_comb.lp_tag          = req_tag;
        pred_comb.lp_way          = hit_way;
        pred_comb.lp_hit          = any_hit;
        pred_comb.lp_pred_is_loop = pred_valid_p0[s] && any_hit &&
                              hit_entry.curs_v &&
                              (hit_entry.cnf == {LP_CNF_BITS{1'b1}});
        pred_comb.lp_pred_taken   = pred_comb.lp_pred_is_loop &&
                              (hit_entry.curs < hit_entry.past_itr);
        pred_comb.lp_age          = hit_entry.age;
        pred_comb.lp_conf         = hit_entry.cnf;
        pred_comb.lp_past_itr     = hit_entry.past_itr;
        pred_comb.lp_curr_itr     = hit_entry.curr_itr;
        pred_comb.lp_curs         = hit_entry.curs;
        pred_comb.lp_curs_v       = hit_entry.curs_v;
        pred_comb.lp_victim       = victim_way;
      end

      // ------------------------------------------------------------
      // p2 re-read (BP-122). The set and tag of the p1 lookup, read
      // again: the entry may have been advanced by the blocks ahead,
      // or allocated, since p0. Gated by r2_val, a flop.
      // ------------------------------------------------------------
      always_comb begin
        p2_hit   = 1'b0;
        p2_way   = '0;
        p2_entry = mem[r2_idx][0];
        for (int w = LP_TBL_WAYS - 1; w >= 0; w--) begin
          if (mem[r2_idx][w].v && (mem[r2_idx][w].tag == r2_tag)) begin
            p2_hit   = 1'b1;
            p2_way   = w[LP_WAY_BITS-1:0];
            p2_entry = mem[r2_idx][w];
          end
        end

        p2_comb                 = '0;
        p2_comb.lp_idx          = r2_idx;
        p2_comb.lp_tag          = r2_tag;
        p2_comb.lp_way          = p2_way;
        p2_comb.lp_hit          = p2_hit;
        p2_comb.lp_pred_is_loop = r2_val && p2_hit && p2_entry.curs_v &&
                                  (p2_entry.cnf == {LP_CNF_BITS{1'b1}});
        p2_comb.lp_pred_taken   = p2_comb.lp_pred_is_loop &&
                                  (p2_entry.curs < p2_entry.past_itr);
        p2_comb.lp_age          = p2_entry.age;
        p2_comb.lp_conf         = p2_entry.cnf;
        p2_comb.lp_past_itr     = p2_entry.past_itr;
        p2_comb.lp_curr_itr     = p2_entry.curr_itr;
        p2_comb.lp_curs         = p2_entry.curs;
        p2_comb.lp_curs_v       = p2_entry.curs_v;
        p2_comb.lp_victim       = '0;
      end

      assign pred_p2[s] = p2_comb;

      // The advanced count. Kept out of the block above: the advance
      // direction is formed by the cluster from pred_p2, so reading it
      // there would close a loop at block granularity (UNOPTFLAT).
      assign p2_adv = adv_of(p2_entry.curs, p2_entry.curs_v,
                             spec_tkn_p2[s]);

      // ------------------------------------------------------------
      // Restore source (BP-122). The checkpoint of the named FTQ
      // entry; it applies only while the entry it read still holds
      // the same tag. Gated by rst_val through rck, a flop array read.
      // ------------------------------------------------------------
      always_comb begin
        rck      = ck[rst_idx];
        rck_live = rck.hit && (rck.adv || rst_ex[s]) &&
                   mem[rck.idx][rck.way].v &&
                   (mem[rck.idx][rck.way].tag == rck.tag);
        rck_val  = rst_ex[s] ? adv_of(rck.itr, rck.itr_v, rst_tkn[s])
                             : {rck.itr_v, rck.itr};
      end

      // ------------------------------------------------------------
      // Update, read before write (BP-122, TD#169). The tag is looked
      // up again in the set, so an entry allocated or replaced since
      // the prediction is found or missed as it is now. Training uses
      // the iteration number the prediction carried:
      //   taken     at a count at or beyond the learned trip count:
      //             the loop ran longer, confidence to zero
      //   not taken (the exit) at a known count: equal to the learned
      //             trip count, confidence up and age to max; else
      //             confidence to zero and the count is learned
      //   an unknown count trains nothing
      // curr_itr is the resolved count: taken steps it, the exit
      // clears it. It does not take part in prediction.
      // A miss allocates on a taken backward branch, at the victim
      // chosen from the set as it is now.
      // ------------------------------------------------------------
      always_comb begin
        u_hit   = 1'b0;
        u_way   = '0;
        u_entry = mem[upd_p0[s].lp_idx][0];
        for (int w = LP_TBL_WAYS - 1; w >= 0; w--) begin
          if (mem[upd_p0[s].lp_idx][w].v &&
              (mem[upd_p0[s].lp_idx][w].tag == upd_p0[s].lp_tag)) begin
            u_hit   = 1'b1;
            u_way   = w[LP_WAY_BITS-1:0];
            u_entry = mem[upd_p0[s].lp_idx][w];
          end
        end

        // Victim, priority as at prediction.
        u_victim = '0;
        if (!mem[upd_p0[s].lp_idx][0].v ||
            !mem[upd_p0[s].lp_idx][1].v ||
            !mem[upd_p0[s].lp_idx][2].v ||
            !mem[upd_p0[s].lp_idx][3].v) begin
          for (int w = LP_TBL_WAYS - 1; w >= 0; w--) begin
            if (!mem[upd_p0[s].lp_idx][w].v)
              u_victim = w[LP_WAY_BITS-1:0];
          end
        end else begin
          u_victim = '0;
          for (int w = LP_TBL_WAYS - 1; w >= 0; w--) begin
            if (mem[upd_p0[s].lp_idx][w].age == '0)
              u_victim = w[LP_WAY_BITS-1:0];
          end
          if (mem[upd_p0[s].lp_idx][u_victim].age != '0) begin
            if (mem[upd_p0[s].lp_idx][1].age <
                mem[upd_p0[s].lp_idx][0].age)
              u_victim = LP_WAY_BITS'(1);
            else if (mem[upd_p0[s].lp_idx][2].age <
                     mem[upd_p0[s].lp_idx][0].age)
              u_victim = LP_WAY_BITS'(2);
            else if (mem[upd_p0[s].lp_idx][3].age <
                     mem[upd_p0[s].lp_idx][0].age)
              u_victim = LP_WAY_BITS'(3);
            else
              u_victim = '0;
          end
        end

        u_alloc = !u_hit && upd_p0[s].actual_taken &&
                  (upd_p0[s].target < upd_p0[s].pc);

        u_new = u_entry;
        if (upd_p0[s].actual_taken) begin
          u_new.curr_itr = (u_entry.curr_itr == ITR_MAX)
                           ? u_entry.curr_itr
                           : u_entry.curr_itr + LP_ITR_BITS'(1);
          if (upd_p0[s].lp_curs_v &&
              (upd_p0[s].lp_curs >= u_entry.past_itr))
            u_new.cnf = '0;
        end else begin
          u_new.curr_itr = '0;
          if (upd_p0[s].lp_curs_v) begin
            if (upd_p0[s].lp_curs == u_entry.past_itr) begin
              u_new.cnf = (u_entry.cnf == LP_CNF_BITS'(LP_CONF_LEVEL))
                          ? u_entry.cnf
                          : u_entry.cnf + LP_CNF_BITS'(1);
              u_new.age = {LP_AGE_BITS{1'b1}};
            end else begin
              u_new.cnf      = '0;
              u_new.past_itr = upd_p0[s].lp_curs;
            end
          end
        end

        if (u_alloc) begin
          // curr_itr=1: the first iteration has been observed. The
          // speculative count is unknown: later instances are already
          // in flight. It becomes known at the entry's next exit.
          u_new          = '0;
          u_new.v        = 1'b1;
          u_new.tag      = upd_p0[s].lp_tag;
          u_new.curr_itr = LP_ITR_BITS'(1);
          u_new.age      = {LP_AGE_BITS{1'b1}};
        end
      end

      // ------------------------------------------------------------
      // Synchronous bank update. Slot s writes only bank s. Order of
      // the writes, later wins for the same entry and field:
      //   invalidate every count, the p2 advance, the restore, the
      //   resolution update (which writes the counts only when it
      //   allocates)
      // ------------------------------------------------------------
      always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
          for (int t = 0; t < LP_N_SETS; t++) begin
            for (int w = 0; w < LP_TBL_WAYS; w++) begin
              mem[t][w] <= '0;
            end
          end
        end else begin
          if (inv_val) begin
            for (int t = 0; t < LP_N_SETS; t++) begin
              for (int w = 0; w < LP_TBL_WAYS; w++) begin
                mem[t][w].curs_v <= 1'b0;
              end
            end
          end
          if (spec_val_p2[s] && p2_hit) begin
            mem[r2_idx][p2_way].curs   <= p2_adv[LP_ITR_BITS-1:0];
            mem[r2_idx][p2_way].curs_v <= p2_adv[LP_ITR_BITS];
          end
          if (rst_val && rck_live) begin
            mem[rck.idx][rck.way].curs   <= rck_val[LP_ITR_BITS-1:0];
            mem[rck.idx][rck.way].curs_v <= rck_val[LP_ITR_BITS];
          end
          if (upd_valid_p0[s] && u_alloc) begin
            mem[upd_p0[s].lp_idx][u_victim] <= u_new;
          end else if (upd_valid_p0[s] && u_hit) begin
            mem[upd_p0[s].lp_idx][u_way].cnf      <= u_new.cnf;
            mem[upd_p0[s].lp_idx][u_way].age      <= u_new.age;
            mem[upd_p0[s].lp_idx][u_way].past_itr <= u_new.past_itr;
            mem[upd_p0[s].lp_idx][u_way].curr_itr <= u_new.curr_itr;
          end
        end
      end

      // ------------------------------------------------------------
      // Checkpoint write (BP-122): the p2 block's read and the count
      // before its advance, at its FTQ index.
      // ------------------------------------------------------------
      always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
          for (int k = 0; k < FTQ_DEPTH; k++) ck[k] <= '0;
        end else if (spec_ck_p2) begin
          ck[spec_idx_p2].hit   <= p2_hit;
          ck[spec_idx_p2].adv   <= spec_val_p2[s] && p2_hit;
          ck[spec_idx_p2].idx   <= r2_idx;
          ck[spec_idx_p2].way   <= p2_way;
          ck[spec_idx_p2].tag   <= r2_tag;
          ck[spec_idx_p2].itr   <= p2_entry.curs;
          ck[spec_idx_p2].itr_v <= p2_entry.curs_v;
        end
      end

      // ------------------------------------------------------------
      // Prediction output register (p0 comb -> p1 registered output)
      // and the p1 -> p2 lookup register (BP-122).
      // ------------------------------------------------------------
      always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
          pred_p1[s] <= '0;
          r1_val     <= 1'b0;
          r2_val     <= 1'b0;
          r2_idx     <= '0;
          r2_tag     <= '0;
        end else begin
          pred_p1[s] <= pred_comb;
          r1_val     <= pred_valid_p0[s];
          r2_val     <= r1_val;
          r2_idx     <= pred_p1[s].lp_idx;
          r2_tag     <= pred_p1[s].lp_tag;
        end
      end

    end
  endgenerate

endmodule : loop_pred

`endif // LOOP_PRED_SV
