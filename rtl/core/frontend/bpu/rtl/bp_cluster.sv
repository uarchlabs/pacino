// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    bp_cluster.sv
// DATE:    2026-08-03
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Branch predictor cluster top (BP-084). STRUCTURAL ONLY.
//
// Instantiates the eight predictor modules and wires them per
// planning/interfaces/ftq_bpu_interfaces.md sections 3 through 8:
//   ubtb, loop_pred, ftb, tage, ittage, sc, ras, bp_history
//
// There is NO behavioral logic in this module: no always_ff, no
// always_comb, no state. The only non-instance content is continuous
// assigns that build the per-slot predictor input structs, fan the
// request out to the predictors, and tie off inputs that have no
// producer at this stage.
//
// Deliberately NOT in this module (BP-084 constraints):
//   - the p1 uBTB / loop_pred selection mux (section 4)
//   - redirect derivation (section 6); the redirect output ports are
//     declared and left undriven
//   - successor-PC selection
//   - update fan-out by resolved branch type (fe_decisions.md 7.2)
//   - RAM arbitration (TD#73, TD#94)
//   - the FTQ entry itself
//
// Pipeline stage assignment (BP-084):
//   p0  indices and addresses to the RAMs; RAS top-of-stack read
//   p1  uBTB, loop_pred outputs; FTQ allocates
//   p2  FTB, TAGE, ITTAGE, RAS
//   p3  SC
//   u0  update address and write data to the RAMs
//   u1  RAM write completes
//
// Generate block style: one generate region, containing exactly one
// unconditional genvar for-loop over the prediction slots, named
// gen_slot. The loop body holds continuous assigns only -- no nested
// generate, no conditional generate, no instances, no always blocks.
// The loop exists solely to index the unpacked per-slot port arrays
// [0:NUM_PRED_SLOTS-1], which a scalar continuous assign cannot span.
// always_comb is deliberately avoided here: a block reading only
// module inputs is classified stl_sequent by Verilator v5.048 and
// would not re-evaluate after simulation start (CLAUDE.md).
//
// Naming: internal nets carry a w_ prefix. Cluster boundary signals
// use the NEW names of ftq_bpu_interfaces.md; predictor connections
// use each module's declared port names (interfaces section 2).
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
  // Undriven in BP-084: the p1 selection mux is not in this task.
  output logic                            bpu_pred_val_p1,
  output logic [FTQ_IDX_BITS-1:0]         bpu_pred_idx_p1,
  output bp_ftq_slot_t                    bpu_pred_slot_p1
                                            [0:NUM_PRED_SLOTS-1],
  output bp_ras_snapshot_t                bpu_pred_ras_p1,

  // ---- section 6: redirects, named by stage -----------------------
  // Declared and undriven: redirect derivation is a cluster-boundary
  // comparison against the FTQ entry and is not in this task.
  output bp_redirect_t                    bpu_redir_p2
                                            [0:NUM_PRED_SLOTS-1],
  output logic [FTQ_IDX_BITS-1:0]         bpu_redir_idx_p2,
  output bp_redirect_t                    bpu_redir_p3
                                            [0:NUM_PRED_SLOTS-1],
  output logic [FTQ_IDX_BITS-1:0]         bpu_redir_idx_p3,

  // ---- section 7: update channel, FTQ -> BPU (u0) -----------------
  // uBTB carries its valid inside ubtb_upd_t.valid; no valid port.
  input  ubtb_upd_t [NUM_PRED_SLOTS-1:0]  ubtb_upd_u0,

  // loop_pred update is single slot today; suffix is p0, not u0.
  input  logic                            lp_upd_valid_p0,
  input  lp_upd_t                         lp_upd_p0,

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
  // prefixes them so the two groups are distinguishable.
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
  // Internal nets: bp_history -> TAGE, ITTAGE, SC
  // ----------------------------------------------------------------
  bp_folded_hist_t            w_folded;

  // bp_history inputs with no producer at this stage. pred_taken,
  // pred_pc and num_branches come from the formed p1 prediction, so
  // they wait on the p1 selection mux. ckpt_wr_en waits on FTQ
  // allocation. rollback_* waits on redirect derivation.
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
  // Consumed by the p1 selection mux, which is not in this task.
  ubtb_pred_t [NUM_PRED_SLOTS-1:0] w_ubtb_pred_p1;
  lp_pred_t                        w_lp_pred_p0;

  // ----------------------------------------------------------------
  // Internal nets: FTB p2 results
  // ----------------------------------------------------------------
  // Consumed by redirect derivation and by the update fan-out, both
  // deferred. w_ftb_pft_addr_p2 is consumed here: it is the RAS
  // fall-through address (interfaces 5.1, 5.4).
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

  // ----------------------------------------------------------------
  // Internal nets: TAGE and ITTAGE prediction path
  // ----------------------------------------------------------------
  logic [NUM_PRED_SLOTS-1:0]  w_tage_pred_val_p0;
  tage_pred_inp_t             w_tage_pred_inp_p0 [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]  w_tage_pred_rdy_p2;
  tage_pred_meta_t            w_tage_pred_meta_p2[0:NUM_PRED_SLOTS-1];
  // SC drives tage.consumer_ready per the port comment, but sc.sv
  // declares no such output. Tied ready until the SC back-pressure
  // path exists (TD#73, TD#94).
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
  // sc does not take bp_folded_hist_t; the cluster slices the three
  // SC index folds and the low 10 bits of tage_phr out of the struct
  // (interfaces 5.3, TD#91, TD#92).
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
  // Request fan-out, scalar (interfaces section 3)
  // ----------------------------------------------------------------
  // Every table predictor sees the same request valid. The per-slot
  // bit vectors replicate it; the slot split is a property of the
  // FTB block, not of the request.
  assign w_tage_pred_val_p0   = {NUM_PRED_SLOTS{ftq_pred_val_p0}};
  assign w_ittage_pred_val_p0 = {NUM_PRED_SLOTS{ftq_pred_val_p0}};

  // ----------------------------------------------------------------
  // Tie-offs, scalar (see BP-084 Results Capture tie-off table)
  // ----------------------------------------------------------------
  assign w_tage_consumer_ready = 1'b1;

  // bp_history prediction update: waits on the p1 selection mux.
  assign w_hist_pred_taken   = 2'b00;
  assign w_hist_pred_pc[0]   = '0;
  assign w_hist_pred_pc[1]   = '0;
  assign w_hist_num_branches = 2'b00;

  // Checkpoint write: the strobe waits on FTQ allocation at p1. The
  // index is the request index, routed structurally so the write
  // port is addressed once the strobe has a producer.
  assign w_ckpt_wr_en  = 1'b0;
  assign w_ckpt_wr_idx = ftq_pred_idx_p0;

  // Rollback: waits on redirect derivation (interfaces section 6).
  assign w_rollback_valid    = 1'b0;
  assign w_rollback_ckpt_idx = '0;

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

      // -- SC staged PC, bit 0 not carried (interfaces 5.3, TD#91)
      assign w_sc_inp_pc_p2[gs] = ftq_pred_pc_p0[VA_WIDTH-1:1];

      // -- RAS p2 inputs. ras_pc_p2 is declared and unread (TD#101);
      //    it is driven from the request PC. The fall-through address
      //    is the FTB pftAddr (interfaces 5.1). The p2 push/pop
      //    qualifiers need the FTB branch classification, which is
      //    update fan-out logic and not in this task.
      assign w_ras_pc_p2[gs]           = ftq_pred_pc_p0;
      assign w_ras_fall_through_p2[gs] = w_ftb_pft_addr_p2;
      assign w_ras_pred_val_p2[gs]     = 1'b0;
      assign w_ras_br_type_p2[gs]      = NO_BRANCH;

      // -- RAS p3 repair inputs: the registered p2 FTB type. No
      //    pipeline register exists in this structural top.
      assign w_ras_pred_val_p3[gs]     = 1'b0;
      assign w_ras_br_type_p3[gs]      = NO_BRANCH;

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
  // ----------------------------------------------------------------
  ubtb #(
    .NUM_PRED_SLOTS (NUM_PRED_SLOTS)
  ) u_ubtb (
    .clk        (clk),
    .rstn       (rstn),
    .pred_pc_p0 (ftq_pred_pc_p0),
    .pred_p1    (w_ubtb_pred_p1),
    .upd_u0     (ubtb_upd_u0)
  );

  // ----------------------------------------------------------------
  // loop_pred (p1). Single slot in the shipped RTL; the dual-slot
  // retrofit and the pred_p0 -> pred_p1 rename are TD#105. Slot 1 has
  // no producer and no consumer at this level.
  // ----------------------------------------------------------------
  loop_pred u_loop_pred (
    .clk           (clk),
    .rstn          (rstn),
    .pred_pc_p0    (ftq_pred_pc_p0),
    .pred_valid_p0 (ftq_pred_val_p0),
    .pred_p0       (w_lp_pred_p0),
    .upd_p0        (lp_upd_p0),
    .upd_valid_p0  (lp_upd_valid_p0)
  );

  // ----------------------------------------------------------------
  // FTB (p2). Flat ports, no slot dimension. br0 maps to slot 0 and
  // br1 to slot 1 at the cluster boundary (interfaces 5.1).
  // ----------------------------------------------------------------
  ftb u_ftb (
    .clk                   (clk),
    .rstn                  (rstn),
    .pred_valid_p0         (ftq_pred_val_p0),
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
    .ftb_upd_valid_u0      (ftb_upd_valid_u0),
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
    .tage_upd_val_u0     (tage_upd_val_u0),
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
    .ittage_upd_val_u0     (ittage_upd_val_u0),
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
  // also fans out to the deferred FTQ boundary comparison. SC takes
  // sliced folds, not the bp_folded_hist_t struct (interfaces 5.3).
  // ----------------------------------------------------------------
  sc #(
    .NUM_PRED_SLOTS (NUM_PRED_SLOTS)
  ) u_sc (
    .clk               (clk),
    .rstn              (rstn),
    .tage_pred_rdy_p2  (w_tage_pred_rdy_p2),
    .tage_pred_meta_p2 (w_tage_pred_meta_p2),
    .inp_pc_p2         (w_sc_inp_pc_p2),
    .sc_phr_p2         (w_folded.tage_phr[9:0]),
    .sc_t1_idx_fh_p2   (w_folded.sc_t1_idx_fh),
    .sc_t2_idx_fh_p2   (w_folded.sc_t2_idx_fh),
    .sc_t3_idx_fh_p2   (w_folded.sc_t3_idx_fh),
    .sc_pred_rdy_p3    (w_sc_pred_rdy_p3),
    .sc_pred_meta_p3   (w_sc_pred_meta_p3),
    .sc_upd_val_u0     (sc_upd_val_u0),
    .sc_upd_inp_u0     (sc_upd_inp_u0),
    .sc_upd_rdy_u1     (sc_upd_rdy_u1),
    .sc_uq_not_full    (sc_uq_not_full),
    .sc_upd_rdy        (sc_upd_rdy),
    .sc_enable         (sc_enable),
    .sc_ready          (sc_ready)
  );

  // ----------------------------------------------------------------
  // RAS. Top of stack is presented at p0; the push or pop executes at
  // p2 once ras_br_type_p2 carries the FTB classification.
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
    .ras_commit_val       (ras_commit_val),
    .ras_commit_br_type   (ras_commit_br_type),
    .ras_commit_ret_addr  (ras_commit_ret_addr),
    .ras_commit_snapshot  (ras_commit_snapshot),
    .ras_flush_val        (ras_flush_val),
    .ras_flush_snapshot   (ras_flush_snapshot)
  );

endmodule : bp_cluster

`endif // BP_CLUSTER_SV
