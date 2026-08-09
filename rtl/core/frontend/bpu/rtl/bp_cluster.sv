// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    bp_cluster.sv
// DATE:    2026-08-04
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Branch predictor cluster top.
//
// The cluster instantiates every branch predictor, drives one shared
// request down a four-stage pipeline, forms the FTQ-facing prediction
// from the results as they arrive, and fans the FTQ update channels
// back out to the predictors that own each branch type.
//
// Instances:
//   ubtb, loop_pred, ftb, tage, ittage, sc, ras, bp_history
//
// What the module produces at its boundary:
//   1. the p1 prediction group -- one bp_ftq_slot_t per slot, formed
//      by the uBTB / loop_pred selection mux, plus the RAS snapshot
//   2. the p2 and p3 redirect groups, each derived by reducing the
//      earlier and the later view of a slot to one quantity, the
//      address fetched after that slot, and comparing them
//   3. the two prediction-metadata write groups that fill the FTQ
//      slow path (bp_ftq_meta_t). The p2 group writes the tage,
//      ittage, lp and ftb members; the p3 group writes the sc member.
//      The sets are disjoint, so the FTQ never merges. Without this
//      group the update path cannot work at all: tage_upd_inp_t,
//      ittage_upd_inp_t and sc_upd_inp_t each embed the matching
//      predict-time metadata, and those values exist only at predict
//      time. The loop predictor finalizes at p1; its result is
//      registered and presented in the p2 group unchanged -- the lp
//      member of bp_ftq_meta_t is lp_pred_t itself, so no field map
//      stands between the two (TD#106). The FTB metadata is scalar
//      within the entry and the same values are written into every
//      slot's copy.
//   4. the update fan-out. The resolved branch type of a channel is
//      rederived from the structural bits of that channel's uBTB
//      update payload (is_br, is_jmp, is_ret, is_call, is_jalr) --
//      the same facts the FTB update fan-out reads, so the two
//      cannot diverge. ubtb_upd_t carries no branch-type field.
//   5. the SC credit arbiter and the queue-status consumption
//
// uBTB interface. ubtb.sv reports one entry per lookup: pred_p1 is
// the per-slot view and blk_p1 is the entry-scoped sideband carrying
// the hit and the reconstructed block fall-through. A pred_p1 slot
// valid bit says only that the slot carries a branch; the entry hit
// is blk_p1.hit. blk_p1.pft_addr is authoritative for the cluster
// when no slot is taken and is the p1 operand of the p2 redirect
// comparison; on a miss it reads zero and the block-aligned start PC
// plus one block stands in.
//
// Pipeline stage assignment:
//   p0  indices and addresses to the RAMs; RAS top-of-stack read
//   p1  uBTB and loop_pred outputs; prediction formed; FTQ allocates
//   p2  FTB, TAGE, ITTAGE, RAS
//   p3  SC
//   u0  update address and write data to the RAMs
//   u1  RAM write completes
//
// Producer alignment. ubtb.pred_p1 and ubtb.blk_p1 are both
// combinational from pred_pc_p0 and are therefore valid in the p0
// cycle; loop_pred.pred_p1 is a registered output and is valid in the
// p1 cycle. The cluster registers the two uBTB results together
// (r_ubtb_pred_p1, r_ubtb_blk_p1) so all three describe the same
// request when the p1 selection mux reads them. ftb, tage and ittage
// are two cycles from p0 and align with the r_*_p2 stage registers;
// sc is one further and aligns with r_*_p3. SC indexes at p2 the
// block requested at p0, so its PC, its phr slice and its three index
// folds are all staged p0 -> p2 rather than connected live.
//
// Late-result matching. tage, ittage and sc carry branch_id in their
// metadata. Every p2/p3 comparison is qualified by branch_id equal to
// the FTQ index held in the matching stage register, so a queued or
// back-pressured response cannot be compared against the wrong entry.
// bp_cluster does not read the FTQ (FE-4 comparison is against the
// prediction the cluster formed at p1 and carried forward here).
//
// Generate block style: one generate region, containing exactly one
// unconditional genvar for-loop over the prediction slots, named
// gen_slot. The loop body holds continuous assigns only -- no nested
// generate, no conditional generate, no instances, no always blocks.
// The loop exists solely to index the unpacked per-slot port arrays
// [0:NUM_PRED_SLOTS-1], which a scalar continuous assign cannot span.
// The update fan-out lives in this loop rather than in an always_comb
// block: a block reading only module inputs is classified stl_sequent
// by Verilator v5.048 and would not re-evaluate after simulation
// start (CLAUDE.md). Every always_comb block in this file reads at
// least one flop output; the gating signal is named in the header
// comment of each block.
//
// Naming: internal nets carry a w_ prefix, stage registers an r_
// prefix with the stage in the suffix. Cluster boundary signals use
// the NEW names of ftq_bpu_interfaces.md; predictor connections use
// each module's declared port names (interfaces section 2).
// ===================================================================
`ifndef BP_CLUSTER_SV
`define BP_CLUSTER_SV

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module bp_cluster (
  input  logic                            clk,
  input  logic                            rstn,

  // ---- section 3: prediction request, FTQ -> BPU (p0) -------------
  input  logic                            ftq_pred_val_p0,
  input  logic [VA_WIDTH-1:0]             ftq_pred_pc_p0,
  input  logic [FTQ_IDX_BITS-1:0]         ftq_pred_idx_p0,

  // ---- section 4: initial prediction, BPU -> FTQ (p1) -------------
  output logic                            bpu_pred_val_p1,
  output logic [FTQ_IDX_BITS-1:0]         bpu_pred_idx_p1,
  output bp_ftq_slot_t                    bpu_pred_slot_p1
                                            [0:NUM_PRED_SLOTS-1],
  output bp_ras_snapshot_t                bpu_pred_ras_p1,
  // Block fall-through: the address fetched after this block when no
  // slot in it is taken. One value per prediction, not per slot.
  // Qualified by bpu_pred_val_p1; it carries no valid of its own.
  output logic [VA_WIDTH-1:0]             bpu_pred_pft_p1,

  // ---- section 6: redirects, named by stage -----------------------
  output bp_redirect_t                    bpu_redir_p2
                                            [0:NUM_PRED_SLOTS-1],
  output logic [FTQ_IDX_BITS-1:0]         bpu_redir_idx_p2,
  output bp_redirect_t                    bpu_redir_p3
                                            [0:NUM_PRED_SLOTS-1],
  output logic [FTQ_IDX_BITS-1:0]         bpu_redir_idx_p3,

  // ---- metadata write, BPU -> FTQ slow path (interfaces 7.1) ------
  // bp_ftq_meta_t is carried per slot; the array is declared here, at
  // the port, not inside the struct. This group writes its tage,
  // ittage, lp and ftb members.
  output logic                            bpu_meta_val_p2,
  output logic [FTQ_IDX_BITS-1:0]         bpu_meta_idx_p2,
  output tage_pred_meta_t                 bpu_meta_tage_p2
                                            [0:NUM_PRED_SLOTS-1],
  output ittage_pred_meta_t               bpu_meta_ittage_p2
                                            [0:NUM_PRED_SLOTS-1],
  output lp_pred_t                        bpu_meta_lp_p2
                                            [0:NUM_PRED_SLOTS-1],
  output ftb_pred_meta_t                  bpu_meta_ftb_p2
                                            [0:NUM_PRED_SLOTS-1],

  // ---- metadata write, BPU -> FTQ slow path (interfaces 7.2) ------
  // Writes the sc member. Disjoint from the p2 group above.
  output logic                            bpu_meta_val_p3,
  output logic [FTQ_IDX_BITS-1:0]         bpu_meta_idx_p3,
  output sc_pred_meta_t                   bpu_meta_sc_p3
                                            [0:NUM_PRED_SLOTS-1],

  // ---- section 8: update channel, FTQ -> BPU (u0) -----------------
  // uBTB carries its valid inside ubtb_upd_t.valid; no valid port.
  input  ubtb_upd_t [NUM_PRED_SLOTS-1:0]  ubtb_upd_u0,

  // loop_pred update is per slot after the TD#105 retrofit. The
  // suffix stays p0, not u0 (interfaces section 8).
  input  logic [NUM_PRED_SLOTS-1:0]       lp_upd_valid_p0,
  input  lp_upd_t                         lp_upd_p0
                                            [0:NUM_PRED_SLOTS-1],

  // FTB update: 14 flat payload ports plus the valid.
  input  logic                            ftb_upd_valid_u0,
  input  logic [VA_WIDTH-1:0]             ftb_upd_pc_u0,
  input  logic                            ftb_upd_hit_u0,
  input  logic [FTB_WAY_BITS-1:0]         ftb_upd_way_u0,
  input  logic                            ftb_upd_is_br_u0,
  input  logic                            ftb_upd_br_idx_u0,
  input  logic                            ftb_upd_taken_u0,
  input  logic [VA_WIDTH-1:0]             ftb_upd_target_u0,
  input  logic [FTB_BR_POS_BITS-1:0]      ftb_upd_pos_u0,
  input  logic                            ftb_upd_is_jmp_u0,
  input  logic [VA_WIDTH-1:0]             ftb_upd_jmp_target_u0,
  input  logic                            ftb_upd_is_call_u0,
  input  logic                            ftb_upd_is_ret_u0,
  input  logic                            ftb_upd_is_jalr_u0,
  input  logic [VA_WIDTH-1:0]             ftb_upd_pft_addr_u0,
  input  logic                            ftb_flush_px,

  input  logic [NUM_PRED_SLOTS-1:0]       tage_upd_val_u0,
  input  tage_upd_inp_t                   tage_upd_inp_u0
                                            [0:NUM_PRED_SLOTS-1],

  input  logic [NUM_PRED_SLOTS-1:0]       ittage_upd_val_u0,
  input  ittage_upd_inp_t                 ittage_upd_inp_u0
                                            [0:NUM_PRED_SLOTS-1],

  input  logic [NUM_PRED_SLOTS-1:0]       sc_upd_val_u0,
  input  sc_upd_inp_t                     sc_upd_inp_u0
                                            [0:NUM_PRED_SLOTS-1],

  // RAS restore, commit, and flush groups. No slot dimension.
  input  logic                            ras_restore_val,
  input  bp_ras_snapshot_t                ras_restore_snapshot,
  input  logic                            ras_commit_val,
  input  bp_br_type_e                     ras_commit_br_type,
  input  logic [VA_WIDTH-1:0]             ras_commit_ret_addr,
  input  bp_ras_snapshot_t                ras_commit_snapshot,
  input  logic                            ras_flush_val,
  input  bp_ras_snapshot_t                ras_flush_snapshot,

  // ---- section 8: history pointer and buffer outputs --------------
  output logic [GHIST_PTR_BITS-1:0]       ghist_ptr,
  output logic [PHIST_PTR_BITS-1:0]       phist_ptr,
  output logic [GHIST_PTR_BITS-1:0]       ckpt_ghist_ptr,
  output logic [PHIST_PTR_BITS-1:0]       ckpt_phist_ptr,
  output logic [GHR_WIDTH-1:0]            ghr_buf,
  output logic [PHR_WIDTH-1:0]            phr_buf,

  // ---- configuration sidebands (inputs) ---------------------------
  input  logic                            tage_enable_aging,
  input  logic [31:0]                     tage_aging_interval,
  input  logic                            ittage_enable_aging,
  input  logic [31:0]                     ittage_aging_interval,
  input  logic                            sc_enable,
  input  logic                            ftb_fastpath_en,

  // ---- status sidebands (outputs) ---------------------------------
  // RAM init ready.
  output logic                            tage_rdy,
  output logic                            ittage_rdy,
  output logic                            sc_ready,
  // Queue status, presented at the boundary. tage and ittage declare
  // pq_not_full / upd_rdy unprefixed (TD#49); the cluster boundary
  // prefixes them so the two groups are distinguishable. These are
  // the back-pressure the FTQ observes: the cluster has no request
  // ready output, so the FTQ must not present a request while a
  // pq_not_full is low (bp_arb_spec.md 8.1).
  output logic                            tage_pq_not_full,
  output logic [NUM_PRED_SLOTS-1:0]       tage_upd_rdy,
  output logic [NUM_PRED_SLOTS-1:0]       tage_upd_rdy_u1,
  output logic                            ittage_pq_not_full,
  output logic [NUM_PRED_SLOTS-1:0]       ittage_upd_rdy,
  output logic [NUM_PRED_SLOTS-1:0]       ittage_upd_rdy_u1,
  output logic                            sc_uq_not_full,
  output logic [NUM_PRED_SLOTS-1:0]       sc_upd_rdy,
  output logic [NUM_PRED_SLOTS-1:0]       sc_upd_rdy_u1
);

  // ----------------------------------------------------------------
  // Local constants
  // ----------------------------------------------------------------
  // SC credit arbiter counter widths (bp_arb_spec.md 4.2, 5.5).
  localparam int SC_PRED_CRED_W = $clog2(SC_PRED_CREDITS + 1);
  localparam int SC_UPD_CRED_W  = $clog2(SC_UPD_CREDITS  + 1);
  localparam int SC_STARVE_W    = $clog2(SC_STARVE_THRESH + 1);

  // Prediction-block alignment. The uBTB and the FTB describe the
  // same FTB_BLOCK_BYTES block, so one offset width serves both. Used
  // only by the p1 fall-through default on a uBTB miss.
  localparam int BLK_OFF_BITS   = $clog2(FTB_BLOCK_BYTES);

  // ----------------------------------------------------------------
  // Internal nets: bp_history -> TAGE, ITTAGE, SC
  // ----------------------------------------------------------------
  bp_folded_hist_t            w_folded;

  logic [1:0]                 w_hist_pred_taken;
  logic [VA_WIDTH-1:0]        w_hist_pred_pc [2];
  logic [1:0]                 w_hist_num_branches;
  logic                       w_ckpt_wr_en;
  logic [FTQ_IDX_BITS-1:0]    w_ckpt_wr_idx;
  logic                       w_rollback_valid;
  logic [FTQ_IDX_BITS-1:0]    w_rollback_ckpt_idx;

  // ----------------------------------------------------------------
  // Internal nets: uBTB and loop_pred p1 results
  // ----------------------------------------------------------------
  ubtb_pred_t [NUM_PRED_SLOTS-1:0] w_ubtb_pred_p1;
  // Entry-scoped uBTB sideband: the lookup hit and the reconstructed
  // block fall-through. One set per lookup, not per slot.
  ubtb_blk_t                       w_ubtb_blk_p1;
  // loop_pred is per slot (TD#105). Its request PC is the single p0
  // request PC replicated: there is no per-slot PC at p0, and the
  // loop index and tag hashes take no slot discriminator.
  logic [VA_WIDTH-1:0]             w_lp_pred_pc_p0 [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]       w_lp_pred_val_p0;
  lp_pred_t                        w_lp_pred_p1    [0:NUM_PRED_SLOTS-1];

  // ----------------------------------------------------------------
  // Internal nets: FTB p2 results
  // ----------------------------------------------------------------
  logic                       w_ftb_valid_p2;
  logic                       w_ftb_hit_p2;
  logic [FTB_WAY_BITS-1:0]    w_ftb_way_p2;
  logic                       w_ftb_br0_valid_p2;
  logic [FTB_BR_POS_BITS-1:0] w_ftb_br0_pos_p2;
  logic                       w_ftb_br0_taken_p2;
  logic [FTB_CONF_WIDTH-1:0]  w_ftb_br0_conf_p2;
  logic [VA_WIDTH-1:0]        w_ftb_br0_target_p2;
  logic                       w_ftb_br1_valid_p2;
  logic [FTB_BR_POS_BITS-1:0] w_ftb_br1_pos_p2;
  logic                       w_ftb_br1_taken_p2;
  logic [FTB_CONF_WIDTH-1:0]  w_ftb_br1_conf_p2;
  logic [VA_WIDTH-1:0]        w_ftb_br1_target_p2;
  logic                       w_ftb_jmp_valid_p2;
  logic [FTB_BR_POS_BITS-1:0] w_ftb_jmp_pos_p2;
  logic [VA_WIDTH-1:0]        w_ftb_jmp_target_p2;
  logic                       w_ftb_is_call_p2;
  logic                       w_ftb_is_ret_p2;
  logic                       w_ftb_is_jalr_p2;
  logic [VA_WIDTH-1:0]        w_ftb_pft_addr_p2;
  logic [1:0]                 w_ftb_fastpath_p2;

  // Per-slot view of the FTB conditional branch fields. ftb.sv
  // declares br0 and br1; slot 0 takes br0 and every higher slot
  // takes br1 (interfaces 5.1). NUM_PRED_SLOTS == 2 is the intended
  // configuration; the select is a constant per generate iteration.
  logic                w_ftb_br_valid_p2  [0:NUM_PRED_SLOTS-1];
  logic                w_ftb_br_taken_p2  [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] w_ftb_br_target_p2 [0:NUM_PRED_SLOTS-1];

  // ----------------------------------------------------------------
  // Internal nets: TAGE and ITTAGE prediction path
  // ----------------------------------------------------------------
  logic [NUM_PRED_SLOTS-1:0]  w_tage_pred_val_p0;
  tage_pred_inp_t             w_tage_pred_inp_p0 [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]  w_tage_pred_rdy_p2;
  tage_pred_meta_t            w_tage_pred_meta_p2[0:NUM_PRED_SLOTS-1];
  logic                       w_tage_consumer_ready;

  logic [NUM_PRED_SLOTS-1:0]  w_ittage_pred_val_p0;
  ittage_pred_inp_t           w_ittage_pred_inp_p0
                                [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]  w_ittage_pred_rdy_p2;
  ittage_pred_meta_t          w_ittage_pred_meta_p2
                                [0:NUM_PRED_SLOTS-1];

  // ----------------------------------------------------------------
  // Internal nets: SC prediction path
  // ----------------------------------------------------------------
  logic [VA_WIDTH-1:1]        w_sc_inp_pc_p2 [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]  w_sc_pred_rdy_p3;
  sc_pred_meta_t              w_sc_pred_meta_p3 [0:NUM_PRED_SLOTS-1];

  // ----------------------------------------------------------------
  // Internal nets: RAS
  // ----------------------------------------------------------------
  logic [VA_WIDTH-1:0] w_ras_tos_addr_p0     [0:NUM_PRED_SLOTS-1];
  logic                w_ras_tos_valid_p0    [0:NUM_PRED_SLOTS-1];
  logic                w_ras_pred_val_p2     [0:NUM_PRED_SLOTS-1];
  bp_br_type_e         w_ras_br_type_p2      [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] w_ras_pc_p2           [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] w_ras_fall_through_p2 [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] w_ras_pop_addr_p2     [0:NUM_PRED_SLOTS-1];
  logic                w_ras_pop_valid_p2    [0:NUM_PRED_SLOTS-1];
  bp_ras_snapshot_t    w_ras_snapshot_p2     [0:NUM_PRED_SLOTS-1];
  logic                w_ras_pred_val_p3     [0:NUM_PRED_SLOTS-1];
  bp_br_type_e         w_ras_br_type_p3      [0:NUM_PRED_SLOTS-1];

  // ----------------------------------------------------------------
  // Stage registers
  // ----------------------------------------------------------------
  // p0 -> p1
  logic                            r_val_p1;
  logic [VA_WIDTH-1:0]             r_pc_p1;
  logic [FTQ_IDX_BITS-1:0]         r_idx_p1;
  logic [9:0]                      r_phr_p1;
  ubtb_pred_t [NUM_PRED_SLOTS-1:0] r_ubtb_pred_p1;
  ubtb_blk_t                       r_ubtb_blk_p1;
  logic [VA_WIDTH-1:0]             r_ras_tos_addr_p1 [0:NUM_PRED_SLOTS-1];
  logic                            r_ras_tos_val_p1  [0:NUM_PRED_SLOTS-1];
  // SC index folds, staged p0 -> p1 -> p2 with the phr slice. SC
  // indexes at p2 the block requested at p0, and bp_history advances
  // whenever a branch is predicted, so the live folds would describe
  // newer history than the block SC is indexing (TD#91, TD#92).
  logic [SC_MAX_FH-1:0]            r_sc_t1_fh_p1;
  logic [SC_MAX_FH-1:0]            r_sc_t2_fh_p1;
  logic [SC_MAX_FH-1:0]            r_sc_t3_fh_p1;

  // p1 -> p2
  logic                    r_val_p2;
  logic [VA_WIDTH-1:0]     r_pc_p2;
  logic [FTQ_IDX_BITS-1:0] r_idx_p2;
  logic [9:0]              r_phr_p2;
  bp_ftq_slot_t            r_slot_p2 [0:NUM_PRED_SLOTS-1];
  logic [SC_MAX_FH-1:0]    r_sc_t1_fh_p2;
  logic [SC_MAX_FH-1:0]    r_sc_t2_fh_p2;
  logic [SC_MAX_FH-1:0]    r_sc_t3_fh_p2;
  // The p1 view of the address fetched after each slot, carried
  // forward as the p1 operand of the p2 redirect comparison.
  logic [VA_WIDTH-1:0]     r_succ_p1_p2 [0:NUM_PRED_SLOTS-1];
  // The loop predictor finalizes at p1. Its result is registered here
  // and presented in the p2 metadata group so the FTQ performs one
  // slow-path write per entry rather than two.
  lp_pred_t                r_lp_pred_p2 [0:NUM_PRED_SLOTS-1];

  // p2 -> p3
  logic                    r_val_p3;
  logic [FTQ_IDX_BITS-1:0] r_idx_p3;
  bp_br_type_e             r_br_type_p3 [0:NUM_PRED_SLOTS-1];
  logic                    r_ras_val_p3 [0:NUM_PRED_SLOTS-1];
  logic                    r_taken_p3   [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0]     r_tkn_tgt_p3 [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0]     r_pft_p3;

  // ----------------------------------------------------------------
  // Derived per-stage nets
  // ----------------------------------------------------------------
  logic                w_pq_rdy_p0;
  logic                w_req_val_p0;

  bp_ftq_slot_t        w_slot_p1    [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] w_slot_pc_p1 [0:NUM_PRED_SLOTS-1];
  // p1 block fall-through, and the per-slot p1 successor built from
  // it. Both are the p1 view only; nothing here reads an FTB result.
  logic [VA_WIDTH-1:0] w_pft_p1;
  logic [VA_WIDTH-1:0] w_succ_p1    [0:NUM_PRED_SLOTS-1];

  bp_br_type_e         w_br_type_p2 [0:NUM_PRED_SLOTS-1];
  logic                w_br_val_p2  [0:NUM_PRED_SLOTS-1];
  logic                w_taken_p2   [0:NUM_PRED_SLOTS-1];
  logic                w_reach_p2   [0:NUM_PRED_SLOTS-1];
  logic                w_tage_hit_p2[0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] w_tkn_tgt_p2 [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] w_succ_p2    [0:NUM_PRED_SLOTS-1];
  bp_redirect_t        w_redir_p2   [0:NUM_PRED_SLOTS-1];

  logic                w_sc_hit_p3  [0:NUM_PRED_SLOTS-1];
  logic                w_taken_p3   [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0] w_succ_p3    [0:NUM_PRED_SLOTS-1];
  bp_redirect_t        w_redir_p3   [0:NUM_PRED_SLOTS-1];

  logic                w_any_redir_p2;
  logic                w_any_redir_p3;

  // ----------------------------------------------------------------
  // Update fan-out nets
  // ----------------------------------------------------------------
  bp_br_type_e                    w_upd_type_u0 [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]      w_upd_any_u0;
  logic [NUM_PRED_SLOTS-1:0]      w_upd_cond_u0;
  logic [NUM_PRED_SLOTS-1:0]      w_upd_ind_u0;
  ubtb_upd_t [NUM_PRED_SLOTS-1:0] w_ubtb_upd_u0;
  logic [NUM_PRED_SLOTS-1:0]      w_tage_upd_val_u0;
  logic [NUM_PRED_SLOTS-1:0]      w_ittage_upd_val_u0;
  logic [NUM_PRED_SLOTS-1:0]      w_sc_upd_val_u0;
  logic [NUM_PRED_SLOTS-1:0]      w_lp_upd_val_p0;
  logic                           w_ftb_upd_val_u0;
  logic                           w_ras_commit_val;

  // ----------------------------------------------------------------
  // SC credit arbiter nets
  // ----------------------------------------------------------------
  logic                      w_sc_uq_not_full_int;
  logic [NUM_PRED_SLOTS-1:0] w_sc_upd_rdy_int;
  logic                      w_sc_pred_req;
  logic                      w_sc_upd_req;
  logic                      w_sc_grant_pred;
  logic                      w_sc_grant_upd;
  logic [SC_PRED_CRED_W-1:0] r_sc_pred_credits;
  logic [SC_UPD_CRED_W-1:0]  r_sc_upd_credits;
  logic [SC_STARVE_W-1:0]    r_sc_starve_ctr;

  // ================================================================
  // p0: request qualification (bp_arb_spec.md 8.1, FE-5)
  // ================================================================
  // The RAM-based predictors with a prediction queue are tage and
  // ittage; both export pq_not_full. A request is presented to the
  // whole cluster only when every such queue can accept it, so no
  // prediction is dropped and the predictors stay in lockstep. The
  // queue-status ports are also presented at the boundary: the FTQ
  // sees them and must not issue while one is low.
  assign w_pq_rdy_p0  = tage_pq_not_full & ittage_pq_not_full;
  assign w_req_val_p0 = ftq_pred_val_p0 & w_pq_rdy_p0;

  // Every table predictor sees the same request valid. The per-slot
  // bit vectors replicate it; the slot split is a property of the
  // FTB block, not of the request.
  assign w_tage_pred_val_p0   = {NUM_PRED_SLOTS{w_req_val_p0}};
  assign w_ittage_pred_val_p0 = {NUM_PRED_SLOTS{w_req_val_p0}};
  assign w_lp_pred_val_p0     = {NUM_PRED_SLOTS{w_req_val_p0}};

  // ================================================================
  // Stage registers p0 -> p1 -> p2 -> p3
  // ================================================================
  always_ff @(posedge clk) begin : stage_ff
    if (!rstn) begin
      r_val_p1  <= 1'b0;
      r_pc_p1   <= '0;
      r_idx_p1  <= '0;
      r_phr_p1  <= '0;
      r_ubtb_pred_p1 <= '0;
      r_ubtb_blk_p1  <= '0;
      r_sc_t1_fh_p1  <= '0;
      r_sc_t2_fh_p1  <= '0;
      r_sc_t3_fh_p1  <= '0;
      r_val_p2  <= 1'b0;
      r_pc_p2   <= '0;
      r_idx_p2  <= '0;
      r_phr_p2  <= '0;
      r_sc_t1_fh_p2  <= '0;
      r_sc_t2_fh_p2  <= '0;
      r_sc_t3_fh_p2  <= '0;
      r_val_p3  <= 1'b0;
      r_idx_p3  <= '0;
      r_pft_p3  <= '0;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        r_ras_tos_addr_p1[s] <= '0;
        r_ras_tos_val_p1[s]  <= 1'b0;
        r_slot_p2[s]         <= '0;
        r_succ_p1_p2[s]      <= '0;
        r_lp_pred_p2[s]      <= '0;
        r_br_type_p3[s]      <= NO_BRANCH;
        r_ras_val_p3[s]      <= 1'b0;
        r_taken_p3[s]        <= 1'b0;
        r_tkn_tgt_p3[s]      <= '0;
      end
    end else begin
      // -- p0 -> p1. The uBTB results are combinational from the p0 PC
      //    and are registered here so they align with the registered
      //    loop_pred output. pred_p1 and blk_p1 cross the boundary
      //    together so both describe the same request when the p1
      //    selection mux reads them. The RAS top of stack is a p0 read
      //    and is registered for the same reason. The SC index folds
      //    are sampled in the cycle the request is presented.
      r_val_p1       <= w_req_val_p0;
      r_pc_p1        <= ftq_pred_pc_p0;
      r_idx_p1       <= ftq_pred_idx_p0;
      r_phr_p1       <= w_folded.tage_phr[9:0];
      r_ubtb_pred_p1 <= w_ubtb_pred_p1;
      r_ubtb_blk_p1  <= w_ubtb_blk_p1;
      r_sc_t1_fh_p1  <= w_folded.sc_t1_idx_fh;
      r_sc_t2_fh_p1  <= w_folded.sc_t2_idx_fh;
      r_sc_t3_fh_p1  <= w_folded.sc_t3_idx_fh;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        r_ras_tos_addr_p1[s] <= w_ras_tos_addr_p0[s];
        r_ras_tos_val_p1[s]  <= w_ras_tos_valid_p0[s];
      end

      // -- p1 -> p2. Carries the formed p1 prediction forward; it is
      //    the value every p2 redirect compares against (FE-4). The
      //    per-slot p1 successor travels with it: it is the reduced
      //    form of that prediction and must describe the same block.
      //    The loop result is registered here for the p2 metadata
      //    group; loop_pred.pred_p1 is valid in the p1 cycle. It is
      //    carried per slot: every slot has a loop producer.
      r_val_p2 <= r_val_p1;
      r_pc_p2  <= r_pc_p1;
      r_idx_p2 <= r_idx_p1;
      r_phr_p2 <= r_phr_p1;
      r_sc_t1_fh_p2 <= r_sc_t1_fh_p1;
      r_sc_t2_fh_p2 <= r_sc_t2_fh_p1;
      r_sc_t3_fh_p2 <= r_sc_t3_fh_p1;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        r_slot_p2[s]    <= w_slot_p1[s];
        r_succ_p1_p2[s] <= w_succ_p1[s];
        r_lp_pred_p2[s] <= w_lp_pred_p1[s];
      end

      // -- p2 -> p3. ras_pred_val_p3 and ras_br_type_p3 are the
      //    registered p2 FTB classification (IC-RAS-11). The taken
      //    target and the fall-through address are carried so the SC
      //    direction can select between them at p3 without a second
      //    FTB read.
      r_val_p3 <= r_val_p2;
      r_idx_p3 <= r_idx_p2;
      r_pft_p3 <= w_ftb_pft_addr_p2;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        r_br_type_p3[s] <= w_br_type_p2[s];
        r_ras_val_p3[s] <= w_ras_pred_val_p2[s];
        r_taken_p3[s]   <= w_taken_p2[s];
        r_tkn_tgt_p3[s] <= w_tkn_tgt_p2[s];
      end
    end
  end

  // ================================================================
  // p1: selection mux and prediction formation
  // ================================================================
  // Gating signal: r_val_p1. The block reads the p1 stage registers
  // (r_val_p1, r_pc_p1, r_ubtb_pred_p1, r_ubtb_blk_p1,
  // r_ras_tos_*_p1), so it is classified nba_sequent (CLAUDE.md
  // stl_sequent rule).
  //
  // Selection per slot, fe_decisions.md 2.1:
  //   lp_pred_is_loop set -> loop_pred supplies the direction
  //   else uBTB valid     -> uBTB supplies the slot
  //   else                -> the slot carries no prediction
  //
  // lp_pred_t carries no target: the loop predictor supplies a
  // direction only. When it wins, the target is still the uBTB entry
  // target. Every slot has its own loop_pred producer after the
  // TD#105 retrofit, so the same trust rule applies to every slot.
  //
  // A uBTB RETURN uses the RAS top of stack as the target
  // (fe_decisions.md 2.2); the uBTB entry supplies the branch type at
  // p1 so the RAS is engaged without waiting for the FTB.
  //
  // The uBTB hit is r_ubtb_blk_p1.hit, reported once per lookup. A
  // pred_p1 slot valid bit says only whether that slot carries a
  // branch, so the two terms are ANDed where the entry must have hit
  // AND the slot must describe a branch.
  always_comb begin : p1_form_comb
    int  nb;
    logic ubtb_slot_hit;

    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      w_slot_p1[s]            = '0;
      w_slot_p1[s].br_type    = NO_BRANCH;
      w_slot_p1[s].pred_src   = PRED_NONE;
      w_slot_p1[s].confidence = '0; // FE-U3: no consumer

      // The uBTB describes slot s only when the entry hit and that
      // slot of the entry carries a branch.
      ubtb_slot_hit = r_ubtb_blk_p1.hit & r_ubtb_pred_p1[s].valid;

      if (r_val_p1) begin
        // Every slot has its own loop_pred producer and its own
        // trust bit; the rule below is the one slot 0 has always
        // used, applied per slot (TD#105).
        if (w_lp_pred_p1[s].lp_pred_is_loop) begin
          w_slot_p1[s].slot_valid = 1'b1;
          w_slot_p1[s].taken      = w_lp_pred_p1[s].lp_pred_taken;
          w_slot_p1[s].br_type    = COND;
          w_slot_p1[s].pred_src   = PRED_LOOP;
          // Target only matters when taken; it comes from the uBTB.
          // The position is gated identically: a slot the uBTB does
          // not describe has no position to report.
          w_slot_p1[s].target     = ubtb_slot_hit
                                      ? r_ubtb_pred_p1[s].target : '0;
          w_slot_p1[s].pos        = ubtb_slot_hit
                                      ? r_ubtb_pred_p1[s].pos : '0;
        end else if (r_ubtb_pred_p1[s].valid) begin
          w_slot_p1[s].slot_valid = 1'b1;
          w_slot_p1[s].taken      = r_ubtb_pred_p1[s].br_taken;
          w_slot_p1[s].br_type    = r_ubtb_pred_p1[s].br_type;
          w_slot_p1[s].pos        = r_ubtb_pred_p1[s].pos;
          if ((r_ubtb_pred_p1[s].br_type == RETURN)
              && r_ras_tos_val_p1[s]) begin
            w_slot_p1[s].target   = r_ras_tos_addr_p1[s];
            w_slot_p1[s].taken    = 1'b1;
            w_slot_p1[s].pred_src = PRED_RAS;
          end else begin
            w_slot_p1[s].target   = r_ubtb_pred_p1[s].target;
            w_slot_p1[s].pred_src = PRED_UBTB;
          end
        end
      end
    end

    // -- p1 successor of each slot: the address fetched after that
    //    slot, formed from the p1 view only. blk_p1.pft_addr is the
    //    uBTB block fall-through and is authoritative for the cluster
    //    when no slot is taken (ubtb_interfaces.md, blk_p1 field
    //    semantics). It reads zero on a miss, so the block-aligned
    //    start PC plus one block stands in.
    w_pft_p1 = r_ubtb_blk_p1.hit
                 ? r_ubtb_blk_p1.pft_addr
                 : ({r_pc_p1[VA_WIDTH-1:BLK_OFF_BITS],
                     {BLK_OFF_BITS{1'b0}}} + VA_WIDTH'(FTB_BLOCK_BYTES));

    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      w_succ_p1[s] = w_slot_p1[s].taken ? w_slot_p1[s].target
                                        : w_pft_p1;
    end

    // -- bp_history prediction update, from the formed prediction.
    //    bp_history indexes pred_taken and pred_pc by branch number,
    //    not by slot number, so the valid slots are compacted down.
    //    Its ports are literal [1:0] and [2] (INFRA-011 item 10), so
    //    at most two branches are reported.
    w_hist_pred_taken   = 2'b00;
    w_hist_pred_pc[0]   = '0;
    w_hist_pred_pc[1]   = '0;
    w_hist_num_branches = 2'b00;
    nb                  = 0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      if (w_slot_p1[s].slot_valid && (nb < 2)) begin
        w_hist_pred_taken[nb] = w_slot_p1[s].taken;
        w_hist_pred_pc[nb]    = w_slot_pc_p1[s];
        nb                    = nb + 1;
      end
    end
    w_hist_num_branches = 2'(nb);
  end

  // -- p1 cluster outputs. Allocation is unconditional: an entry is
  //    written for every prediction block, including one the p1
  //    predictors miss (interfaces section 4).
  assign bpu_pred_val_p1 = r_val_p1;
  assign bpu_pred_idx_p1 = r_idx_p1;

  // -- Block fall-through, exposed for the FTQ (TD#108). This is the
  //    same w_pft_p1 the per-slot p1 successor above uses as its
  //    not-taken term, driven out unchanged: one value per
  //    prediction, qualified by bpu_pred_val_p1. Exposing it does not
  //    change how it is computed.
  assign bpu_pred_pft_p1 = w_pft_p1;

  // -- The RAS snapshot written into the entry allocated at p1 is the
  //    pointer state that block will start from at p2. In the cycle
  //    this block is at p1 the block ahead of it is at p2, and
  //    ras_snapshot_p2 of the highest slot is that block's post-op
  //    state -- which is exactly the state of the p1 block on entry
  //    to p2. One snapshot per entry is sufficient (FE-11).
  assign bpu_pred_ras_p1 = w_ras_snapshot_p2[NUM_PRED_SLOTS-1];

  // -- Checkpoint write at allocation (interfaces section 8).
  assign w_ckpt_wr_en  = r_val_p1;
  assign w_ckpt_wr_idx = r_idx_p1;

  // ================================================================
  // p2: FTB classification, RAS qualification
  // ================================================================
  // Gating signal: r_val_p2. Reads the p2 stage registers, so the
  // block is nba_sequent.
  //
  // This block deliberately reads NO ras output. It drives the RAS p2
  // inputs, and ras.sv produces ras_pop_addr_p2 combinationally from
  // them; computing the successor target here as well would make the
  // block circular at block granularity (Verilator UNOPTFLAT). The
  // successor and the redirect are formed in p2_succ_comb below.
  //
  // Branch type per slot: the slot's FTB conditional field when it is
  // valid, else the block's single jump field, which is placed in the
  // lowest slot that carries no conditional branch. The jump field is
  // the block-terminating branch, so lowest-free-slot placement is
  // program order.
  always_comb begin : p2_class_comb
    bp_br_type_e jmp_type;
    logic        jmp_placed;
    logic        blk_val;

    blk_val = r_val_p2 & w_ftb_valid_p2;

    // FTB jump-field structural classification.
    if (w_ftb_is_ret_p2)
      jmp_type = RETURN;
    else if (w_ftb_is_call_p2 & w_ftb_is_jalr_p2)
      jmp_type = INDIRECT_CALL;
    else if (w_ftb_is_call_p2)
      jmp_type = DIRECT_CALL;
    else if (w_ftb_is_jalr_p2)
      jmp_type = INDIRECT_NONRET;
    else
      jmp_type = DIRECT_UNC;

    jmp_placed = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      w_br_type_p2[s]  = NO_BRANCH;
      w_br_val_p2[s]   = 1'b0;
      w_taken_p2[s]    = 1'b0;
      w_tage_hit_p2[s] = w_tage_pred_rdy_p2[s]
                       & (w_tage_pred_meta_p2[s].branch_id == r_idx_p2);

      if (blk_val && w_ftb_br_valid_p2[s]) begin
        // Conditional branch. TAGE supplies the direction at p2 when
        // its response matches this entry; the FTB direction stands
        // otherwise (fe_decisions.md 3.3).
        w_br_type_p2[s] = COND;
        w_br_val_p2[s]  = 1'b1;
        w_taken_p2[s]   = w_tage_hit_p2[s]
                            ? w_tage_pred_meta_p2[s].tage_pred_tkn
                            : w_ftb_br_taken_p2[s];
      end else if (blk_val && w_ftb_jmp_valid_p2 && !jmp_placed) begin
        jmp_placed      = 1'b1;
        w_br_type_p2[s] = jmp_type;
        w_br_val_p2[s]  = 1'b1;
        w_taken_p2[s]   = 1'b1; // unconditional
      end
    end

    // Reachability: a taken branch ends the block, so a later slot is
    // not on the predicted path and must not change RAS state
    // (FE-11).
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      if (s == 0)
        w_reach_p2[s] = 1'b1;
      else
        w_reach_p2[s] = w_reach_p2[s-1] & ~w_taken_p2[s-1];
    end

    // RAS p2 qualification. ras.sv acts on DIRECT_CALL, INDIRECT_CALL
    // and RETURN only; every other type is a no-op inside the module.
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      w_ras_pred_val_p2[s] = blk_val & w_br_val_p2[s] & w_reach_p2[s];
    end
  end

  // ================================================================
  // p2: successor selection and redirect derivation
  // ================================================================
  // Gating signal: r_val_p2. Reads the p2 stage registers and the p2
  // predictor outputs, so the block is nba_sequent.
  //
  // Target source by branch type (fe_decisions.md 3.3):
  //   return       RAS pop address
  //   indirect     ITTAGE target
  //   conditional  direction from TAGE selects branch target or the
  //                fall-through address
  //   direct unc.  FTB jump target
  always_comb begin : p2_succ_comb
    logic [VA_WIDTH-1:0] it_tgt;
    logic                it_hit;
    logic [VA_WIDTH-1:0] p1_succ;

    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      // ITTAGE target. The metadata holds the upper 38 bits of an
      // Sv39 VA with bit 0 not stored; bit 39 is the Sv39 sign
      // extension of bit 38.
      it_hit = w_ittage_pred_rdy_p2[s]
             & (w_ittage_pred_meta_p2[s].branch_id == r_idx_p2)
             & w_ittage_pred_meta_p2[s].ittage_hit;
      it_tgt = w_ittage_pred_meta_p2[s].ittage_using_primary
                 ? {w_ittage_pred_meta_p2[s]
                      .ittage_prm_tgt[IT_MAX_TGT_WIDTH-1],
                    w_ittage_pred_meta_p2[s].ittage_prm_tgt, 1'b0}
                 : {w_ittage_pred_meta_p2[s]
                      .ittage_alt_tgt[IT_MAX_TGT_WIDTH-1],
                    w_ittage_pred_meta_p2[s].ittage_alt_tgt, 1'b0};

      case (w_br_type_p2[s])
        COND: begin
          w_tkn_tgt_p2[s] = w_ftb_br_target_p2[s];
        end
        RETURN: begin
          w_tkn_tgt_p2[s] = w_ras_pop_valid_p2[s]
                              ? w_ras_pop_addr_p2[s]
                              : w_ftb_jmp_target_p2;
        end
        INDIRECT_NONRET, INDIRECT_CALL: begin
          w_tkn_tgt_p2[s] = it_hit ? it_tgt : w_ftb_jmp_target_p2;
        end
        DIRECT_CALL, DIRECT_UNC: begin
          w_tkn_tgt_p2[s] = w_ftb_jmp_target_p2;
        end
        default: begin // NO_BRANCH
          w_tkn_tgt_p2[s] = w_ftb_pft_addr_p2;
        end
      endcase

      // Successor of this slot: the taken target, or the block
      // fall-through when the slot resolves not taken.
      w_succ_p2[s] = w_taken_p2[s] ? w_tkn_tgt_p2[s]
                                   : w_ftb_pft_addr_p2;

      // The p1 prediction carried in the stage register, expressed as
      // the same quantity so the comparison is target against target.
      // The p1 side uses the p1 fall-through, not the FTB one: taking
      // the FTB value on both sides would mask the case this
      // comparison exists to catch, a block whose boundary the FTB
      // places somewhere the uBTB did not.
      p1_succ = r_succ_p1_p2[s];

      w_redir_p2[s].valid     = r_val_p2 & w_ftb_valid_p2
                              & (w_succ_p2[s] != p1_succ);
      w_redir_p2[s].target_pc = w_succ_p2[s];
    end
  end

  assign bpu_redir_idx_p2 = r_idx_p2;

  // ================================================================
  // p3: SC redirect derivation
  // ================================================================
  // Gating signal: r_val_p3. Reads the p3 stage registers, so the
  // block is nba_sequent.
  //
  // SC corrects the direction of a conditional slot only. The
  // comparison is against the value the cluster published at p2 and
  // carried forward in r_taken_p3 / r_tkn_tgt_p3 / r_pft_p3, so a p3
  // redirect fires only when SC changes that value. Supersession is
  // preserved: the FTQ takes the later stage for the same entry index
  // and slot (FE-3).
  always_comb begin : p3_redir_comb
    logic [VA_WIDTH-1:0] p2_succ;

    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      w_sc_hit_p3[s] = w_sc_pred_rdy_p3[s] & sc_enable
                     & (w_sc_pred_meta_p3[s].branch_id == r_idx_p3);

      w_taken_p3[s]  = ((r_br_type_p3[s] == COND) & w_sc_hit_p3[s])
                         ? w_sc_pred_meta_p3[s].sc_pred_tkn
                         : r_taken_p3[s];

      w_succ_p3[s]   = w_taken_p3[s] ? r_tkn_tgt_p3[s] : r_pft_p3;
      p2_succ        = r_taken_p3[s] ? r_tkn_tgt_p3[s] : r_pft_p3;

      w_redir_p3[s].valid     = r_val_p3 & (w_succ_p3[s] != p2_succ);
      w_redir_p3[s].target_pc = w_succ_p3[s];
    end
  end

  assign bpu_redir_idx_p3 = r_idx_p3;

  // ================================================================
  // History rollback, driven from the redirect (interfaces 8)
  // ================================================================
  // A redirect discards the fetch stream started from the entry, so
  // the history pointers are restored from that entry's checkpoint.
  // p3 wins the index when both stages redirect in the same cycle,
  // matching the supersession rule.
  always_comb begin : rollback_comb
    w_any_redir_p2 = 1'b0;
    w_any_redir_p3 = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      w_any_redir_p2 = w_any_redir_p2 | w_redir_p2[s].valid;
      w_any_redir_p3 = w_any_redir_p3 | w_redir_p3[s].valid;
    end
  end

  assign w_rollback_valid    = w_any_redir_p2 | w_any_redir_p3;
  assign w_rollback_ckpt_idx = w_any_redir_p3 ? r_idx_p3 : r_idx_p2;

  // ================================================================
  // SC credit arbiter (bp_arb_spec.md 4.5, 5.5, 6.1)
  // ================================================================
  // sc.sv stubs its arbitration layer; the real arbiter lands here
  // (TD#73, TD#94). The SC tables are single port: an SC prediction
  // (p2 -> p3 read) and an SC update (u0 write) contend for that one
  // port and the section 4.5 credit rules pick one per cycle.
  //
  // Queue depth. SC has no prediction FIFO of its own -- the TAGE
  // response buffer is its PQ (section 6.1) -- and the cluster does
  // not add an update FIFO: the producer holds valid until accepted
  // (section 4.4 handshake, FE-5), so the FTQ is the holding element
  // and a bypass-only queue is the degenerate legal case of section
  // 4.3/4.4. "Queue non-empty" is therefore "a request is presented".
  //
  // The prediction request is the cluster p2 stage valid, not
  // tage_pred_rdy_p2: tage.sv already qualifies that output with
  // consumer_ready, and consumer_ready is an output of this arbiter,
  // so using it as an input would close a combinational loop.
  assign w_sc_pred_req = r_val_p2 & sc_enable;
  assign w_sc_upd_req  = sc_enable & w_sc_uq_not_full_int
                       & (|(sc_upd_val_u0 & w_upd_cond_u0
                            & w_sc_upd_rdy_int));

  // Rule 1 of section 4.5 blocks prediction grants when the response
  // path cannot take a result. sc.sv exposes no response-buffer full
  // flag; the equivalent condition available here is sc_ready, which
  // is low until the SC RAM init completes.
  always_comb begin : sc_arb_comb
    w_sc_grant_pred = 1'b0;
    w_sc_grant_upd  = 1'b0;

    // Rule 2: starvation override (highest priority)
    if (w_sc_upd_req
        && (r_sc_starve_ctr >= SC_STARVE_W'(SC_STARVE_THRESH))) begin
      w_sc_grant_upd = 1'b1;
    end
    // Rules 3/4: both sides have a request
    else if (w_sc_pred_req && w_sc_upd_req) begin
      if ((r_sc_pred_credits > '0) && sc_ready)
        w_sc_grant_pred = 1'b1;  // rule 3
      else
        w_sc_grant_upd  = 1'b1;  // rule 4
    end
    // Rule 5: prediction only
    else if (w_sc_pred_req && !w_sc_upd_req) begin
      if (sc_ready)
        w_sc_grant_pred = 1'b1;
    end
    // Rule 6: update only
    else if (!w_sc_pred_req && w_sc_upd_req) begin
      w_sc_grant_upd = 1'b1;
    end
    // Rule 7: neither -- no grant (implicit)
  end

  always_ff @(posedge clk) begin : sc_arb_cred_ff
    if (!rstn) begin
      r_sc_pred_credits <= SC_PRED_CRED_W'(SC_PRED_CREDITS);
      r_sc_upd_credits  <= SC_UPD_CRED_W'(SC_UPD_CREDITS);
      r_sc_starve_ctr   <= '0;
    end else begin
      if (w_sc_upd_req
          && (r_sc_starve_ctr >= SC_STARVE_W'(SC_STARVE_THRESH))) begin
        // Rule 2 fired: reset starve, reload upd_credits
        r_sc_starve_ctr  <= '0;
        r_sc_upd_credits <= SC_UPD_CRED_W'(SC_UPD_CREDITS);
      end else if (w_sc_pred_req && w_sc_upd_req) begin
        if ((r_sc_pred_credits > '0) && sc_ready) begin
          // Rule 3 fired: dec pred_credits, inc starve
          r_sc_pred_credits <= r_sc_pred_credits
                             - SC_PRED_CRED_W'(1);
          r_sc_starve_ctr   <= r_sc_starve_ctr + SC_STARVE_W'(1);
        end else begin
          // Rule 4 fired: reload all credits, reset starve
          r_sc_pred_credits <= SC_PRED_CRED_W'(SC_PRED_CREDITS);
          r_sc_upd_credits  <= SC_UPD_CRED_W'(SC_UPD_CREDITS);
          r_sc_starve_ctr   <= '0;
        end
      end
      // Rules 5, 6, 7: no credit changes
    end
  end

  // consumer_ready, driven from the real condition. SC is the
  // consumer of the TAGE p2 result (bp_arb_spec.md 4.7, 11 item C).
  // It can take the result unless the SC RAM port went to an update
  // this cycle, or the SC RAMs are still initialising. When the SC is
  // disabled the cluster does not wait on it at all (section 0), so
  // TAGE is never held.
  assign w_tage_consumer_ready = ~sc_enable
                               | (sc_ready & ~w_sc_grant_upd);

  // Queue-status presented at the boundary. sc_uq_not_full is the
  // sc.sv value, also consumed above by the arbiter. sc_upd_rdy is
  // the section 4.4 accept: the update is taken only when granted.
  assign sc_uq_not_full = w_sc_uq_not_full_int;
  assign sc_upd_rdy     = w_sc_upd_rdy_int
                        & {NUM_PRED_SLOTS{w_sc_grant_upd}};

  // ================================================================
  // Helper functions
  // ================================================================
  // Resolved branch type of one update channel, rederived from the
  // structural bits of its own uBTB update payload. ubtb_upd_t
  // carries no branch-type field: the type is a function of the
  // resolved facts, and rederiving it here keeps the uBTB fan-out and
  // the FTB fan-out reading the SAME facts, so the two cannot
  // diverge. Arm order matches ubtb.sv jmp_br_type and the p2 FTB
  // classification above, with is_br outranking is_jmp.
  function automatic bp_br_type_e upd_br_type(input ubtb_upd_t u);
    if      (u.is_br)    upd_br_type = COND;
    else if (!u.is_jmp)  upd_br_type = NO_BRANCH;
    else if (u.is_ret)   upd_br_type = RETURN;
    else if (u.is_call)  upd_br_type = u.is_jalr ? INDIRECT_CALL
                                                 : DIRECT_CALL;
    else if (u.is_jalr)  upd_br_type = INDIRECT_NONRET;
    else                 upd_br_type = DIRECT_UNC;
  endfunction

  // lp_to_meta() lived here. TD#106 retired bp_loop_meta_t in favour
  // of lp_pred_t, so the p2 metadata member and the loop predictor
  // output are now the same type and the field-by-field map has no
  // work left to do. The p1 loop result is carried through unchanged.

  // ================================================================
  // Prediction metadata write groups (interfaces 7.1, 7.2)
  // ================================================================
  // The p2 group follows the p2 stage valid and index; the p3 group
  // follows the p3 pair. bpu_meta_val_p3 asserts whether or not SC is
  // enabled, so the entry's slow path is always complete; when SC is
  // disabled the written value simply carries no prediction.
  assign bpu_meta_val_p2 = r_val_p2;
  assign bpu_meta_idx_p2 = r_idx_p2;
  assign bpu_meta_val_p3 = r_val_p3;
  assign bpu_meta_idx_p3 = r_idx_p3;

  // ================================================================
  // Update fan-out, scalar channels (fe_decisions.md 7.2)
  // ================================================================
  // The FTB update channel carries its own structural classification,
  // so it is decoded from its own payload rather than from a
  // prediction slot. NO_BRANCH forms no update.
  assign w_ftb_upd_val_u0 = ftb_upd_valid_u0
                          & (ftb_upd_is_br_u0 | ftb_upd_is_jmp_u0);

  // RAS commit carries its own resolved branch type. Both call
  // encodings push and RETURN pops; every other type is a no-op.
  assign w_ras_commit_val = ras_commit_val
                          & ((ras_commit_br_type == DIRECT_CALL)
                           | (ras_commit_br_type == INDIRECT_CALL)
                           | (ras_commit_br_type == RETURN));

  // ----------------------------------------------------------------
  // Per-slot wiring (generate style described in the file header)
  // ----------------------------------------------------------------
  generate
    genvar gs;
    for (gs = 0; gs < NUM_PRED_SLOTS; gs++) begin : gen_slot

      // -- TAGE / ITTAGE input structs, built from the request PC and
      //    the allocated FTQ index (interfaces section 3). The FTB is
      //    not internally slot split: one lookup describes the whole
      //    block, so both slots carry the block start PC.
      assign w_tage_pred_inp_p0[gs].pc          = ftq_pred_pc_p0;
      assign w_tage_pred_inp_p0[gs].branch_id   = ftq_pred_idx_p0;
      assign w_ittage_pred_inp_p0[gs].pc        = ftq_pred_pc_p0;
      assign w_ittage_pred_inp_p0[gs].branch_id = ftq_pred_idx_p0;

      // -- loop_pred request PC. Every slot indexes from the single
      //    p0 request PC: there is no per-slot PC at p0 and the loop
      //    index and tag hashes carry no slot discriminator, so the
      //    banks diverge only through their own updates (TD#105).
      assign w_lp_pred_pc_p0[gs] = ftq_pred_pc_p0;

      // -- loop_pred update, conditional branches only, per slot.
      assign w_lp_upd_val_p0[gs] = lp_upd_valid_p0[gs]
                                 & w_upd_cond_u0[gs];

      // -- Per-slot view of the FTB conditional fields (5.1).
      assign w_ftb_br_valid_p2[gs]  = (gs == 0) ? w_ftb_br0_valid_p2
                                                : w_ftb_br1_valid_p2;
      assign w_ftb_br_taken_p2[gs]  = (gs == 0) ? w_ftb_br0_taken_p2
                                                : w_ftb_br1_taken_p2;
      assign w_ftb_br_target_p2[gs] = (gs == 0) ? w_ftb_br0_target_p2
                                                : w_ftb_br1_target_p2;

      // -- Branch PC of each p1 slot, reported to bp_history as that
      //    branch's pred_pc. Its only consumer.
      //    BP-086 retired the model this expression was written for.
      //    ubtb.sv no longer derives a slot 1 lookup from pred_pc_p0
      //    plus FTB_BLOCK_BYTES: one lookup returns one entry and
      //    both slots describe branches inside that same block, with
      //    the entry hit reported once in blk_p1. The per-slot block
      //    stride below therefore outlives its rationale. Correcting
      //    it changes what bp_history is told and is out of scope
      //    here (BP-092 constraint 4); see the Results Capture.
      assign w_slot_pc_p1[gs] = r_pc_p1
                              + (VA_WIDTH'(gs)
                                 * VA_WIDTH'(FTB_BLOCK_BYTES));

      // -- p1 prediction output array.
      assign bpu_pred_slot_p1[gs] = w_slot_p1[gs];

      // -- Redirect output arrays (interfaces section 6).
      assign bpu_redir_p2[gs] = w_redir_p2[gs];
      assign bpu_redir_p3[gs] = w_redir_p3[gs];

      // -- SC staged PC, bit 0 not carried (interfaces 5.3, TD#91).
      //    Staged p0 -> p2 by the cluster stage registers.
      assign w_sc_inp_pc_p2[gs] = r_pc_p2[VA_WIDTH-1:1];

      // -- RAS p2 inputs. ras_pc_p2 is declared and unread (TD#101);
      //    it is driven from the staged request PC. The fall-through
      //    address is the FTB pftAddr (interfaces 5.1).
      assign w_ras_pc_p2[gs]           = r_pc_p2;
      assign w_ras_fall_through_p2[gs] = w_ftb_pft_addr_p2;
      assign w_ras_br_type_p2[gs]      = w_br_type_p2[gs];

      // -- RAS p3 repair inputs: the registered p2 classification.
      assign w_ras_pred_val_p3[gs]     = r_ras_val_p3[gs];
      assign w_ras_br_type_p3[gs]      = r_br_type_p3[gs];

      // -- Update fan-out by resolved branch type (7.2, FE-U9).
      //    The resolved type of update channel gs is rederived from
      //    the structural bits of that channel's uBTB payload, which
      //    is the only per-slot update payload carrying them, and
      //    uBTB appears in every row of the 7.2 table. The bits are
      //    read independently of ubtb_upd_u0[gs].valid so a channel
      //    that updates only the table predictors still classifies.
      assign w_upd_type_u0[gs]  = upd_br_type(ubtb_upd_u0[gs]);
      assign w_upd_any_u0[gs]   = (w_upd_type_u0[gs] != NO_BRANCH);
      assign w_upd_cond_u0[gs]  = (w_upd_type_u0[gs] == COND);
      assign w_upd_ind_u0[gs]   =
                     (w_upd_type_u0[gs] == INDIRECT_NONRET)
                   | (w_upd_type_u0[gs] == INDIRECT_CALL);

      // uBTB: every row of 7.2 except NO_BRANCH. The uBTB update
      // carries no valid port of its own, so the NO_BRANCH
      // qualification lands on the struct's valid field. Every other
      // member is forwarded unchanged.
      assign w_ubtb_upd_u0[gs].valid      = ubtb_upd_u0[gs].valid
                                          & w_upd_any_u0[gs];
      assign w_ubtb_upd_u0[gs].pc         = ubtb_upd_u0[gs].pc;
      assign w_ubtb_upd_u0[gs].is_br      = ubtb_upd_u0[gs].is_br;
      assign w_ubtb_upd_u0[gs].br_idx     = ubtb_upd_u0[gs].br_idx;
      assign w_ubtb_upd_u0[gs].br_taken   = ubtb_upd_u0[gs].br_taken;
      assign w_ubtb_upd_u0[gs].target     = ubtb_upd_u0[gs].target;
      assign w_ubtb_upd_u0[gs].pos        = ubtb_upd_u0[gs].pos;
      assign w_ubtb_upd_u0[gs].is_jmp     = ubtb_upd_u0[gs].is_jmp;
      assign w_ubtb_upd_u0[gs].jmp_target = ubtb_upd_u0[gs].jmp_target;
      assign w_ubtb_upd_u0[gs].is_call    = ubtb_upd_u0[gs].is_call;
      assign w_ubtb_upd_u0[gs].is_ret     = ubtb_upd_u0[gs].is_ret;
      assign w_ubtb_upd_u0[gs].is_jalr    = ubtb_upd_u0[gs].is_jalr;
      assign w_ubtb_upd_u0[gs].pft_addr   = ubtb_upd_u0[gs].pft_addr;

      // -- Prediction metadata, p2 group (interfaces 7.1). TAGE and
      //    ITTAGE are the predictor outputs passed through. The FTB
      //    values are scalar within the entry, so the same three go
      //    into every slot's copy (7.3). The loop metadata is that
      //    slot's own registered p1 loop result: after the TD#105
      //    retrofit every slot has a loop producer and a bank of its
      //    own, so each slot carries its own table coordinates.
      assign bpu_meta_tage_p2[gs]        = w_tage_pred_meta_p2[gs];
      assign bpu_meta_ittage_p2[gs]      = w_ittage_pred_meta_p2[gs];
      assign bpu_meta_ftb_p2[gs].hit     = w_ftb_hit_p2;
      assign bpu_meta_ftb_p2[gs].way     = w_ftb_way_p2;
      assign bpu_meta_ftb_p2[gs].jmp_pos = w_ftb_jmp_pos_p2;
      assign bpu_meta_lp_p2[gs]          = r_lp_pred_p2[gs];

      // -- Prediction metadata, p3 group (interfaces 7.2). The SC
      //    predictor output passed through.
      assign bpu_meta_sc_p3[gs]          = w_sc_pred_meta_p3[gs];

      // TAGE and SC: conditional branches only. ITTAGE: indirect
      // only, which per the session-061 ruling includes the indirect
      // call, whose target ITTAGE predicts. Each is additionally
      // qualified by its own queue ready, so no update is presented
      // to a full queue (bp_arb_spec.md 4.4; the FTQ holds it).
      assign w_tage_upd_val_u0[gs]   = tage_upd_val_u0[gs]
                                     & w_upd_cond_u0[gs]
                                     & tage_upd_rdy[gs];
      assign w_ittage_upd_val_u0[gs] = ittage_upd_val_u0[gs]
                                     & w_upd_ind_u0[gs]
                                     & ittage_upd_rdy[gs];
      assign w_sc_upd_val_u0[gs]     = sc_upd_val_u0[gs]
                                     & w_upd_cond_u0[gs]
                                     & w_sc_upd_rdy_int[gs]
                                     & sc_enable
                                     & w_sc_grant_upd;

    end
  endgenerate

  // ----------------------------------------------------------------
  // bp_history (interfaces section 8)
  // ----------------------------------------------------------------
  bp_history u_bp_history (
    .clk               (clk),
    .rstn              (rstn),
    .pred_taken        (w_hist_pred_taken),
    .pred_pc           (w_hist_pred_pc),
    .num_branches      (w_hist_num_branches),
    .ckpt_wr_en        (w_ckpt_wr_en),
    .ckpt_wr_idx       (w_ckpt_wr_idx),
    .rollback_valid    (w_rollback_valid),
    .rollback_ckpt_idx (w_rollback_ckpt_idx),
    .ghist_ptr         (ghist_ptr),
    .phist_ptr         (phist_ptr),
    .ckpt_ghist_ptr    (ckpt_ghist_ptr),
    .ckpt_phist_ptr    (ckpt_phist_ptr),
    .ghr_buf           (ghr_buf),
    .phr_buf           (phr_buf),
    .folded            (w_folded)
  );

  // ----------------------------------------------------------------
  // uBTB (p1). No request-valid port: it predicts every cycle.
  // NUM_PRED_SLOTS defaults to 1 in ubtb.sv and is overridden here.
  // pred_p1 is the per-slot view of the matched entry; blk_p1 is the
  // entry-scoped sideband. Both are registered p0 -> p1 together.
  // ----------------------------------------------------------------
  ubtb #(
    .NUM_PRED_SLOTS (NUM_PRED_SLOTS)
  ) u_ubtb (
    .clk        (clk),
    .rstn       (rstn),
    .pred_pc_p0 (ftq_pred_pc_p0),
    .pred_p1    (w_ubtb_pred_p1),
    .blk_p1     (w_ubtb_blk_p1),
    .upd_u0     (w_ubtb_upd_u0)
  );

  // ----------------------------------------------------------------
  // loop_pred (p1). Per slot after the TD#105 retrofit: one table
  // bank per slot, one prediction and one update channel per slot,
  // and the output renamed pred_p1 for the stage at which it is
  // valid. NUM_PRED_SLOTS defaults to 1 in loop_pred.sv and is
  // overridden here, the same way it is for ubtb.
  // ----------------------------------------------------------------
  loop_pred #(
    .NUM_PRED_SLOTS (NUM_PRED_SLOTS)
  ) u_loop_pred (
    .clk           (clk),
    .rstn          (rstn),
    .pred_pc_p0    (w_lp_pred_pc_p0),
    .pred_valid_p0 (w_lp_pred_val_p0),
    .pred_p1       (w_lp_pred_p1),
    .upd_p0        (lp_upd_p0),
    .upd_valid_p0  (w_lp_upd_val_p0)
  );

  // ----------------------------------------------------------------
  // FTB (p2). Flat ports, no slot dimension. br0 maps to slot 0 and
  // br1 to slot 1 at the cluster boundary (interfaces 5.1).
  // ----------------------------------------------------------------
  ftb u_ftb (
    .clk                   (clk),
    .rstn                  (rstn),
    .pred_valid_p0         (w_req_val_p0),
    .pred_pc_p0            (ftq_pred_pc_p0),
    .ftb_valid_p2          (w_ftb_valid_p2),
    .ftb_hit_p2            (w_ftb_hit_p2),
    .ftb_way_p2            (w_ftb_way_p2),
    .ftb_br0_valid_p2      (w_ftb_br0_valid_p2),
    .ftb_br0_pos_p2        (w_ftb_br0_pos_p2),
    .ftb_br0_taken_p2      (w_ftb_br0_taken_p2),
    .ftb_br0_conf_p2       (w_ftb_br0_conf_p2),
    .ftb_br0_target_p2     (w_ftb_br0_target_p2),
    .ftb_br1_valid_p2      (w_ftb_br1_valid_p2),
    .ftb_br1_pos_p2        (w_ftb_br1_pos_p2),
    .ftb_br1_taken_p2      (w_ftb_br1_taken_p2),
    .ftb_br1_conf_p2       (w_ftb_br1_conf_p2),
    .ftb_br1_target_p2     (w_ftb_br1_target_p2),
    .ftb_jmp_valid_p2      (w_ftb_jmp_valid_p2),
    .ftb_jmp_pos_p2        (w_ftb_jmp_pos_p2),
    .ftb_jmp_target_p2     (w_ftb_jmp_target_p2),
    .ftb_is_call_p2        (w_ftb_is_call_p2),
    .ftb_is_ret_p2         (w_ftb_is_ret_p2),
    .ftb_is_jalr_p2        (w_ftb_is_jalr_p2),
    .ftb_pft_addr_p2       (w_ftb_pft_addr_p2),
    .ftb_fastpath_p2       (w_ftb_fastpath_p2),
    .ftb_fastpath_en       (ftb_fastpath_en),
    .ftb_upd_valid_u0      (w_ftb_upd_val_u0),
    .ftb_upd_pc_u0         (ftb_upd_pc_u0),
    .ftb_upd_hit_u0        (ftb_upd_hit_u0),
    .ftb_upd_way_u0        (ftb_upd_way_u0),
    .ftb_upd_is_br_u0      (ftb_upd_is_br_u0),
    .ftb_upd_br_idx_u0     (ftb_upd_br_idx_u0),
    .ftb_upd_taken_u0      (ftb_upd_taken_u0),
    .ftb_upd_target_u0     (ftb_upd_target_u0),
    .ftb_upd_pos_u0        (ftb_upd_pos_u0),
    .ftb_upd_is_jmp_u0     (ftb_upd_is_jmp_u0),
    .ftb_upd_jmp_target_u0 (ftb_upd_jmp_target_u0),
    .ftb_upd_is_call_u0    (ftb_upd_is_call_u0),
    .ftb_upd_is_ret_u0     (ftb_upd_is_ret_u0),
    .ftb_upd_is_jalr_u0    (ftb_upd_is_jalr_u0),
    .ftb_upd_pft_addr_u0   (ftb_upd_pft_addr_u0),
    .ftb_flush_px          (ftb_flush_px)
  );

  // ----------------------------------------------------------------
  // TAGE (p2). folded_hist takes bp_folded_hist_t whole.
  // ----------------------------------------------------------------
  tage #(
    .NUM_PRED_SLOTS (NUM_PRED_SLOTS)
  ) u_tage (
    .clk                 (clk),
    .rstn                (rstn),
    .tage_pred_val_p0    (w_tage_pred_val_p0),
    .tage_pred_inp_p0    (w_tage_pred_inp_p0),
    .tage_pred_rdy_p2    (w_tage_pred_rdy_p2),
    .tage_pred_meta_p2   (w_tage_pred_meta_p2),
    .tage_upd_val_u0     (w_tage_upd_val_u0),
    .tage_upd_inp_u0     (tage_upd_inp_u0),
    .tage_upd_rdy_u1     (tage_upd_rdy_u1),
    .pq_not_full         (tage_pq_not_full),
    .upd_rdy             (tage_upd_rdy),
    .tage_enable_aging   (tage_enable_aging),
    .tage_aging_interval (tage_aging_interval),
    .consumer_ready      (w_tage_consumer_ready),
    .folded_hist         (w_folded),
    .tage_rdy            (tage_rdy)
  );

  // ----------------------------------------------------------------
  // ITTAGE (p2). folded_hist takes bp_folded_hist_t whole. bp_history
  // does not generate the IT5 folds ittage.sv consumes; those fields
  // read zero (TD#102, not in scope).
  // ----------------------------------------------------------------
  ittage u_ittage (
    .clk                   (clk),
    .rstn                  (rstn),
    .ittage_pred_val_p0    (w_ittage_pred_val_p0),
    .ittage_pred_inp_p0    (w_ittage_pred_inp_p0),
    .ittage_pred_rdy_p2    (w_ittage_pred_rdy_p2),
    .ittage_pred_meta_p2   (w_ittage_pred_meta_p2),
    .ittage_upd_val_u0     (w_ittage_upd_val_u0),
    .ittage_upd_inp_u0     (ittage_upd_inp_u0),
    .ittage_upd_rdy_u1     (ittage_upd_rdy_u1),
    .pq_not_full           (ittage_pq_not_full),
    .upd_rdy               (ittage_upd_rdy),
    .ittage_enable_aging   (ittage_enable_aging),
    .ittage_aging_interval (ittage_aging_interval),
    .folded_hist           (w_folded),
    .ittage_rdy            (ittage_rdy)
  );

  // ----------------------------------------------------------------
  // SC (p3). Consumes the TAGE p2 result directly; the same result
  // also feeds the cluster p2 redirect derivation. SC takes sliced
  // folds, not the bp_folded_hist_t struct (interfaces 5.3). inp_pc,
  // sc_phr and the three index folds are all staged p0 -> p2 by this
  // module (TD#91, TD#92): SC indexes at p2 the block requested at
  // p0, and bp_history advances whenever a branch is predicted, so
  // the live folds would describe newer history than that block.
  // ----------------------------------------------------------------
  sc #(
    .NUM_PRED_SLOTS (NUM_PRED_SLOTS)
  ) u_sc (
    .clk               (clk),
    .rstn              (rstn),
    .tage_pred_rdy_p2  (w_tage_pred_rdy_p2),
    .tage_pred_meta_p2 (w_tage_pred_meta_p2),
    .inp_pc_p2         (w_sc_inp_pc_p2),
    .sc_phr_p2         (r_phr_p2),
    .sc_t1_idx_fh_p2   (r_sc_t1_fh_p2),
    .sc_t2_idx_fh_p2   (r_sc_t2_fh_p2),
    .sc_t3_idx_fh_p2   (r_sc_t3_fh_p2),
    .sc_pred_rdy_p3    (w_sc_pred_rdy_p3),
    .sc_pred_meta_p3   (w_sc_pred_meta_p3),
    .sc_upd_val_u0     (w_sc_upd_val_u0),
    .sc_upd_inp_u0     (sc_upd_inp_u0),
    .sc_upd_rdy_u1     (sc_upd_rdy_u1),
    .sc_uq_not_full    (w_sc_uq_not_full_int),
    .sc_upd_rdy        (w_sc_upd_rdy_int),
    .sc_enable         (sc_enable),
    .sc_ready          (sc_ready)
  );

  // ----------------------------------------------------------------
  // RAS. Top of stack is presented at p0; the push or pop executes at
  // p2 from the FTB branch-type classification, and the p3 repair
  // pass takes the registered p2 values.
  // ----------------------------------------------------------------
  ras u_ras (
    .clk                  (clk),
    .rstn                 (rstn),
    .ras_tos_addr_p0      (w_ras_tos_addr_p0),
    .ras_tos_valid_p0     (w_ras_tos_valid_p0),
    .ras_pred_val_p2      (w_ras_pred_val_p2),
    .ras_br_type_p2       (w_ras_br_type_p2),
    .ras_pc_p2            (w_ras_pc_p2),
    .ras_fall_through_p2  (w_ras_fall_through_p2),
    .ras_pop_addr_p2      (w_ras_pop_addr_p2),
    .ras_pop_valid_p2     (w_ras_pop_valid_p2),
    .ras_snapshot_p2      (w_ras_snapshot_p2),
    .ras_pred_val_p3      (w_ras_pred_val_p3),
    .ras_br_type_p3       (w_ras_br_type_p3),
    .ras_restore_val      (ras_restore_val),
    .ras_restore_snapshot (ras_restore_snapshot),
    .ras_commit_val       (w_ras_commit_val),
    .ras_commit_br_type   (ras_commit_br_type),
    .ras_commit_ret_addr  (ras_commit_ret_addr),
    .ras_commit_snapshot  (ras_commit_snapshot),
    .ras_flush_val        (ras_flush_val),
    .ras_flush_snapshot   (ras_flush_snapshot)
  );

endmodule : bp_cluster

`endif // BP_CLUSTER_SV
