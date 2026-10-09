// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Unit testbench for ftq.sv, the structural top (BP-107).
//
// WHAT THIS FILE IS FOR, and what it is deliberately NOT for. The
// eight leaves each have their own testbench, where the acceptance
// criteria of Problems 1 to 6 are checked against stimulus placed
// exactly where each case needs it. This file cannot place that
// stimulus -- everything reaches a leaf through nine other modules
// -- and repeating those cases badly here would add coverage
// numbers and no coverage.
//
// What only this file can check is the WIRING and the LOOP:
//
//   A  the unit elaborates and comes out of reset requesting the
//      reset vector
//   B  THE STEADY-STATE LOOP CLOSES. One prediction block per
//      cycle, with no bubble, through ftq_npc's combinational
//      successor path and back into the p0 request. This is the
//      thing the FTQ exists for and the one behaviour that cannot
//      be seen in any single leaf.
//   C  an allocated entry becomes a fetch request with the right
//      PC, which is the path ftq_ptr -> ftq_entry -> ftq_ifu and
//      three modules' wiring
//   D  a backend redirect reaches every module that must act on it
//      -- the rewind, the status clear, the IFU flush, the restore
//      and the commit suppression -- which is ftq_npc's fan-out
//   E  the commit walk frees entries and drives the RAS group,
//      which is ftq_commit -> ftq_entry
//   J  BP-120, TD#157: a resolution held by a TAGE or SC ready low
//      trains the FTB once, counted at the FTB update port, through
//      ftq_resolve, ftq_upd_conv and ftq_ftb_sched together
//
// THE CLUSTER IS MODELLED, because it has to be: the loop closes
// through bp_cluster and ftq.sv does not instantiate it (7.1). The
// model is the minimum the contract requires -- one p1 response per
// accepted p0 request, one cycle later, carrying the index it was
// given -- and nothing more. It is not a predictor.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ---- BPU boundary -------------------------------------------------
  logic                     ftq_pred_val_p0;
  logic [VA_WIDTH-1:0]      ftq_pred_pc_p0;
  logic [FTQ_IDX_BITS-1:0]  ftq_pred_idx_p0;
  logic                     tage_pq_not_full;
  logic                     ittage_pq_not_full;
  logic                     sc_uq_not_full;
  logic                     bpu_pred_val_p1;
  logic [FTQ_IDX_BITS-1:0]  bpu_pred_idx_p1;
  bp_ftq_slot_t             bpu_pred_slot_p1 [0:NUM_PRED_SLOTS-1];
  bp_ras_snapshot_t         bpu_pred_ras_p1;
  logic [VA_WIDTH-1:0]      bpu_pred_pft_p1;
  logic [GHIST_PTR_BITS-1:0] ckpt_ghist_ptr;
  logic [PHIST_PTR_BITS-1:0] ckpt_phist_ptr;
  logic                     bpu_slot_val_p2;
  logic [FTQ_IDX_BITS-1:0]  bpu_slot_idx_p2;
  bp_ftq_slot_t             bpu_slot_p2 [0:NUM_PRED_SLOTS-1];
  logic                     bpu_slot_val_p3;
  logic [FTQ_IDX_BITS-1:0]  bpu_slot_idx_p3;
  bp_ftq_slot_t             bpu_slot_p3 [0:NUM_PRED_SLOTS-1];
  logic                     bpu_blk_val_p2;
  logic [FTQ_IDX_BITS-1:0]  bpu_blk_idx_p2;
  bp_ras_snapshot_t         bpu_blk_ras_p2;
  logic [VA_WIDTH-1:0]      bpu_blk_pft_p2;
  bp_redirect_t             bpu_redir_p2 [0:NUM_PRED_SLOTS-1];
  logic [FTQ_IDX_BITS-1:0]  bpu_redir_idx_p2;
  bp_redirect_t             bpu_redir_p3 [0:NUM_PRED_SLOTS-1];
  logic [FTQ_IDX_BITS-1:0]  bpu_redir_idx_p3;
  logic                     bpu_meta_val_p2;
  logic [FTQ_IDX_BITS-1:0]  bpu_meta_idx_p2;
  tage_pred_meta_t          bpu_meta_tage_p2   [0:NUM_PRED_SLOTS-1];
  ittage_pred_meta_t        bpu_meta_ittage_p2 [0:NUM_PRED_SLOTS-1];
  lp_pred_t                 bpu_meta_lp_p2     [0:NUM_PRED_SLOTS-1];
  ftb_pred_meta_t           bpu_meta_ftb_p2    [0:NUM_PRED_SLOTS-1];
  logic                     bpu_meta_val_p3;
  logic [FTQ_IDX_BITS-1:0]  bpu_meta_idx_p3;
  sc_pred_meta_t            bpu_meta_sc_p3     [0:NUM_PRED_SLOTS-1];
  logic                     ftq_rollback_val;
  logic [FTQ_IDX_BITS-1:0]  ftq_rollback_idx;
  logic                     ftq_rollback_corr;     // BP-121
  logic [1:0]               ftq_rollback_n;
  logic [1:0]               ftq_rollback_tkn;
  logic [1:0]               ftq_rollback_pbit;
  logic [NUM_PRED_SLOTS-1:0] ftq_rollback_slot_ex;   // BP-122
  logic [NUM_PRED_SLOTS-1:0] ftq_rollback_slot_tkn;  // BP-122
  logic                     ras_restore_val;
  bp_ras_snapshot_t         ras_restore_snapshot;
  logic                     ras_commit_val;
  bp_br_type_e              ras_commit_br_type;
  logic [VA_WIDTH-1:0]      ras_commit_ret_addr;
  bp_ras_snapshot_t         ras_commit_snapshot;
  // Section 8 per-predictor update ports (BP-119, TD#151). The
  // readies are the cluster's per-slot queue readies, held high here.
  logic                     sc_enable;
  ubtb_upd_t [NUM_PRED_SLOTS-1:0] ubtb_upd_u0;
  logic [NUM_PRED_SLOTS-1:0] lp_upd_valid_p0;
  lp_upd_t                  lp_upd_p0         [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] tage_upd_val_u0;
  tage_upd_inp_t            tage_upd_inp_u0   [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] ittage_upd_val_u0;
  ittage_upd_inp_t          ittage_upd_inp_u0 [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] sc_upd_val_u0;
  sc_upd_inp_t              sc_upd_inp_u0     [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] tage_upd_rdy;
  logic [NUM_PRED_SLOTS-1:0] ittage_upd_rdy;
  logic [NUM_PRED_SLOTS-1:0] sc_upd_rdy;
  logic                     ftb_upd_valid_u0;
  logic [VA_WIDTH-1:0]      ftb_upd_pc_u0;
  logic                     ftb_upd_hit_u0;
  logic [FTB_WAY_BITS-1:0]  ftb_upd_way_u0;
  logic                     ftb_upd_is_br_u0;
  logic                     ftb_upd_br_idx_u0;
  logic                     ftb_upd_taken_u0;
  logic [VA_WIDTH-1:0]      ftb_upd_target_u0;
  logic [FTB_BR_POS_BITS-1:0] ftb_upd_pos_u0;
  logic                     ftb_upd_is_jmp_u0;
  logic [VA_WIDTH-1:0]      ftb_upd_jmp_target_u0;
  logic                     ftb_upd_is_call_u0;
  logic                     ftb_upd_is_ret_u0;
  logic                     ftb_upd_is_jalr_u0;
  logic                     ftb_upd_jmp_rvc_u0;   // BP-121, TD#164
  logic [VA_WIDTH-1:0]      ftb_upd_pft_addr_u0;

  // ---- IFU boundary --------------------------------------------------
  logic                     ftq_ifu_xlate_val;
  logic                     ftq_ifu_xlate_rdy;
  logic [VA_WIDTH-1:0]      ftq_ifu_xlate_pc;
  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_xlate_idx;
  logic                     ftq_ifu_req_val;
  logic                     ftq_ifu_req_rdy;
  logic [VA_WIDTH-1:0]      ftq_ifu_start_pc;
  logic [VA_WIDTH-1:0]      ftq_ifu_next_pc;
  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_idx;
  logic                     ftq_ifu_taken_val;
  logic [FTB_BR_POS_BITS-1:0] ftq_ifu_taken_pos;
  logic                     ftq_ifu_gen;
  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_commit_ptr;
  logic                     ftq_ifu_flush_val;
  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_flush_idx;
  logic                     ifu_ftq_pdwb_val;
  logic [FTQ_IDX_BITS-1:0]  ifu_ftq_pdwb_idx;
  logic                     ifu_ftq_pdwb_gen;
  ftq_pd_info_t             ifu_ftq_pd [0:FTQ_PD_WIDTH-1];
  logic [FTQ_PD_WIDTH-1:0]  ifu_ftq_pd_range;
  logic                     ifu_ftq_cfi_val;
  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_cfi_pos;
  logic                     ifu_ftq_mis_val;
  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_mis_pos;
  logic [VA_WIDTH-1:0]      ifu_ftq_target;
  logic                     ifu_ftq_fault_val;
  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_fault_pos;

  // ---- backend boundary ----------------------------------------------
  logic [NUM_RESOLVE_PORTS-1:0] bkend_ftq_rsv_val;
  ftq_resolve_t             bkend_ftq_rsv [0:NUM_RESOLVE_PORTS-1];
  logic [NUM_RESOLVE_PORTS-1:0] ftq_bkend_rsv_rdy;
  logic                     bkend_ftq_redir_val;
  logic [FTQ_IDX_BITS-1:0]  bkend_ftq_redir_idx;
  logic [FTB_BR_POS_BITS-1:0] bkend_ftq_redir_pos;
  logic [VA_WIDTH-1:0]      bkend_ftq_redir_pc;
  logic                     bkend_ftq_redir_self;
  ftq_redir_cause_e         bkend_ftq_redir_cause;
  logic                     bkend_ftq_redir_taken; // BP-121
  logic                     bkend_ftq_commit_val;
  logic [FTQ_PTR_BITS-1:0]  bkend_ftq_commit_idx;

  logic                     ftq_full;
  logic                     ftq_empty;

  ftq dut (
    .clk                   (clk),
    .rstn                  (rstn),
    .ftq_pred_val_p0       (ftq_pred_val_p0),
    .ftq_pred_pc_p0        (ftq_pred_pc_p0),
    .ftq_pred_idx_p0       (ftq_pred_idx_p0),
    .tage_pq_not_full      (tage_pq_not_full),
    .ittage_pq_not_full    (ittage_pq_not_full),
    .sc_uq_not_full        (sc_uq_not_full),
    .bpu_pred_val_p1       (bpu_pred_val_p1),
    .bpu_pred_idx_p1       (bpu_pred_idx_p1),
    .bpu_pred_slot_p1      (bpu_pred_slot_p1),
    .bpu_pred_ras_p1       (bpu_pred_ras_p1),
    .bpu_pred_pft_p1       (bpu_pred_pft_p1),
    .ckpt_ghist_ptr        (ckpt_ghist_ptr),
    .ckpt_phist_ptr        (ckpt_phist_ptr),
    .bpu_slot_val_p2       (bpu_slot_val_p2),
    .bpu_slot_idx_p2       (bpu_slot_idx_p2),
    .bpu_slot_p2           (bpu_slot_p2),
    .bpu_slot_val_p3       (bpu_slot_val_p3),
    .bpu_slot_idx_p3       (bpu_slot_idx_p3),
    .bpu_slot_p3           (bpu_slot_p3),
    .bpu_blk_val_p2        (bpu_blk_val_p2),
    .bpu_blk_idx_p2        (bpu_blk_idx_p2),
    .bpu_blk_ras_p2        (bpu_blk_ras_p2),
    .bpu_blk_pft_p2        (bpu_blk_pft_p2),
    .bpu_redir_p2          (bpu_redir_p2),
    .bpu_redir_idx_p2      (bpu_redir_idx_p2),
    .bpu_redir_p3          (bpu_redir_p3),
    .bpu_redir_idx_p3      (bpu_redir_idx_p3),
    .bpu_meta_val_p2       (bpu_meta_val_p2),
    .bpu_meta_idx_p2       (bpu_meta_idx_p2),
    .bpu_meta_tage_p2      (bpu_meta_tage_p2),
    .bpu_meta_ittage_p2    (bpu_meta_ittage_p2),
    .bpu_meta_lp_p2        (bpu_meta_lp_p2),
    .bpu_meta_ftb_p2       (bpu_meta_ftb_p2),
    .bpu_meta_val_p3       (bpu_meta_val_p3),
    .bpu_meta_idx_p3       (bpu_meta_idx_p3),
    .bpu_meta_sc_p3        (bpu_meta_sc_p3),
    .ftq_rollback_val      (ftq_rollback_val),
    .ftq_rollback_idx      (ftq_rollback_idx),
    .ftq_rollback_corr     (ftq_rollback_corr),
    .ftq_rollback_n        (ftq_rollback_n),
    .ftq_rollback_tkn      (ftq_rollback_tkn),
    .ftq_rollback_pbit     (ftq_rollback_pbit),
    .ftq_rollback_slot_ex  (ftq_rollback_slot_ex),
    .ftq_rollback_slot_tkn (ftq_rollback_slot_tkn),
    .ras_restore_val       (ras_restore_val),
    .ras_restore_snapshot  (ras_restore_snapshot),
    .ras_commit_val        (ras_commit_val),
    .ras_commit_br_type    (ras_commit_br_type),
    .ras_commit_ret_addr   (ras_commit_ret_addr),
    .ras_commit_snapshot   (ras_commit_snapshot),
    .sc_enable             (sc_enable),
    .ubtb_upd_u0           (ubtb_upd_u0),
    .lp_upd_valid_p0       (lp_upd_valid_p0),
    .lp_upd_p0             (lp_upd_p0),
    .tage_upd_val_u0       (tage_upd_val_u0),
    .tage_upd_inp_u0       (tage_upd_inp_u0),
    .ittage_upd_val_u0     (ittage_upd_val_u0),
    .ittage_upd_inp_u0     (ittage_upd_inp_u0),
    .sc_upd_val_u0         (sc_upd_val_u0),
    .sc_upd_inp_u0         (sc_upd_inp_u0),
    .tage_upd_rdy          (tage_upd_rdy),
    .ittage_upd_rdy        (ittage_upd_rdy),
    .sc_upd_rdy            (sc_upd_rdy),
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
    .ftb_upd_jmp_rvc_u0    (ftb_upd_jmp_rvc_u0),
    .ftb_upd_pft_addr_u0   (ftb_upd_pft_addr_u0),
    .ftq_ifu_xlate_val     (ftq_ifu_xlate_val),
    .ftq_ifu_xlate_rdy     (ftq_ifu_xlate_rdy),
    .ftq_ifu_xlate_pc      (ftq_ifu_xlate_pc),
    .ftq_ifu_xlate_idx     (ftq_ifu_xlate_idx),
    .ftq_ifu_req_val       (ftq_ifu_req_val),
    .ftq_ifu_req_rdy       (ftq_ifu_req_rdy),
    .ftq_ifu_start_pc      (ftq_ifu_start_pc),
    .ftq_ifu_next_pc       (ftq_ifu_next_pc),
    .ftq_ifu_idx           (ftq_ifu_idx),
    .ftq_ifu_taken_val     (ftq_ifu_taken_val),
    .ftq_ifu_taken_pos     (ftq_ifu_taken_pos),
    .ftq_ifu_gen           (ftq_ifu_gen),
    .ftq_ifu_commit_ptr    (ftq_ifu_commit_ptr),
    .ftq_ifu_flush_val     (ftq_ifu_flush_val),
    .ftq_ifu_flush_idx     (ftq_ifu_flush_idx),
    .ifu_ftq_pdwb_val      (ifu_ftq_pdwb_val),
    .ifu_ftq_pdwb_idx      (ifu_ftq_pdwb_idx),
    .ifu_ftq_pdwb_gen      (ifu_ftq_pdwb_gen),
    .ifu_ftq_pd            (ifu_ftq_pd),
    .ifu_ftq_pd_range      (ifu_ftq_pd_range),
    .ifu_ftq_cfi_val       (ifu_ftq_cfi_val),
    .ifu_ftq_cfi_pos       (ifu_ftq_cfi_pos),
    .ifu_ftq_mis_val       (ifu_ftq_mis_val),
    .ifu_ftq_mis_pos       (ifu_ftq_mis_pos),
    .ifu_ftq_target        (ifu_ftq_target),
    .ifu_ftq_fault_val     (ifu_ftq_fault_val),
    .ifu_ftq_fault_pos     (ifu_ftq_fault_pos),
    .bkend_ftq_rsv_val     (bkend_ftq_rsv_val),
    .bkend_ftq_rsv         (bkend_ftq_rsv),
    .ftq_bkend_rsv_rdy     (ftq_bkend_rsv_rdy),
    .bkend_ftq_redir_val   (bkend_ftq_redir_val),
    .bkend_ftq_redir_idx   (bkend_ftq_redir_idx),
    .bkend_ftq_redir_pos   (bkend_ftq_redir_pos),
    .bkend_ftq_redir_pc    (bkend_ftq_redir_pc),
    .bkend_ftq_redir_self  (bkend_ftq_redir_self),
    .bkend_ftq_redir_cause (bkend_ftq_redir_cause),
    .bkend_ftq_redir_taken (bkend_ftq_redir_taken),
    .bkend_ftq_commit_val  (bkend_ftq_commit_val),
    .bkend_ftq_commit_idx  (bkend_ftq_commit_idx),
    .ftq_full              (ftq_full),
    .ftq_empty             (ftq_empty)
  );

  // -----------------------------------------------------------------
  // The cluster model.
  // -----------------------------------------------------------------
  // ONE p1 RESPONSE PER ACCEPTED p0 REQUEST, one cycle later,
  // carrying the index it was given. That is all the contract of
  // ftq_bpu_interfaces.md 3 and 4 requires and all this file needs.
  //
  // The p1 view it produces is a MISS: no slot valid, so the
  // successor is the fall-through. That is the ordinary steady-state
  // case for a straight-line stream, and it makes group B's
  // expectation an arithmetic progression that a wrong successor
  // cannot coincide with. Group B2 overrides it to exercise a taken
  // slot.
  logic                mdl_tkn_en;
  logic [VA_WIDTH-1:0] mdl_tkn_tgt;
  bp_br_type_e         mdl_tkn_type;

  // THE 4c GROUP (ftq_bpu_interfaces.md 4c, BP-118). Like the real
  // cluster, the model presents it for EVERY valid p2 block, one
  // cycle after p1, carrying the p1 fall-through forward. One index
  // may be given a corrected fall-through, mdl_blk_pft, standing in
  // for an FTB that ends the block earlier than the p1 view. The RAS
  // snapshot is the p1 value (zero) unless overridden the same way.
  logic                    mdl_blk_ovr;
  logic [FTQ_IDX_BITS-1:0] mdl_blk_idx;
  logic [VA_WIDTH-1:0]     mdl_blk_pft;
  bp_ras_snapshot_t        mdl_blk_ras;
  logic                    r_mdl_val_p2;
  logic [FTQ_IDX_BITS-1:0] r_mdl_idx_p2;
  logic [VA_WIDTH-1:0]     r_mdl_pft_p2;

  always_ff @(posedge clk or negedge rstn) begin : cluster_model_p2
    if (!rstn) begin
      r_mdl_val_p2 <= 1'b0;
      r_mdl_idx_p2 <= '0;
      r_mdl_pft_p2 <= '0;
    end else begin
      r_mdl_val_p2 <= bpu_pred_val_p1;
      r_mdl_idx_p2 <= bpu_pred_idx_p1;
      r_mdl_pft_p2 <= bpu_pred_pft_p1;
    end
  end

  always_comb begin : cluster_model_blk
    bpu_blk_val_p2 = r_mdl_val_p2;
    bpu_blk_idx_p2 = r_mdl_idx_p2;
    bpu_blk_pft_p2 = r_mdl_pft_p2;
    bpu_blk_ras_p2 = '0;
    if (mdl_blk_ovr && (r_mdl_idx_p2 == mdl_blk_idx)) begin
      bpu_blk_pft_p2 = mdl_blk_pft;
      bpu_blk_ras_p2 = mdl_blk_ras;
    end
  end

  always_ff @(posedge clk or negedge rstn) begin : cluster_model
    if (!rstn) begin
      bpu_pred_val_p1 <= 1'b0;
      bpu_pred_idx_p1 <= '0;
      bpu_pred_pft_p1 <= '0;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        bpu_pred_slot_p1[s] <= '0;
      end
    end else begin
      bpu_pred_val_p1 <= ftq_pred_val_p0;
      bpu_pred_idx_p1 <= ftq_pred_idx_p0;
      // The block fall-through: this block's start plus the block
      // size. FTB_BLOCK_BYTES, not a literal.
      bpu_pred_pft_p1 <= ftq_pred_pc_p0 + VA_WIDTH'(FTB_BLOCK_BYTES);
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        bpu_pred_slot_p1[s]            <= '0;
        bpu_pred_slot_p1[s].br_type    <= NO_BRANCH;
        bpu_pred_slot_p1[s].pred_src   <= PRED_NONE;
      end
      if (mdl_tkn_en) begin
        bpu_pred_slot_p1[0].slot_valid <= 1'b1;
        bpu_pred_slot_p1[0].taken      <= 1'b1;
        bpu_pred_slot_p1[0].br_type    <= mdl_tkn_type;
        bpu_pred_slot_p1[0].target     <= mdl_tkn_tgt;
        bpu_pred_slot_p1[0].pos        <= FTB_BR_POS_BITS'(2);
      end
    end
  end

  int pass_cnt;
  int fail_cnt;

  // K's presentations after a predecode redirect (BP-117, TD#146).
  // Counts every fetch and translation request presented for entry
  // k_mon_idx while k_mon_on is set. Armed the cycle AFTER the
  // redirect: the flush-cycle request comes from the pre-rewind
  // pointer and is discarded (ftq_ifu_interfaces.md 5). The counters
  // are written only here and cleared by reset; a test reads them
  // before and after. k_mon_on and k_mon_idx are cleared in do_reset.
  logic                    k_mon_on;
  logic [FTQ_IDX_BITS-1:0] k_mon_idx;
  int                      k_mon_fetch;
  int                      k_mon_xlate;

  always @(posedge clk) begin : k_monitor
    if (!rstn) begin
      k_mon_fetch <= 0;
      k_mon_xlate <= 0;
    end else if (k_mon_on && !ftq_ifu_flush_val) begin
      if (ftq_ifu_req_val && (ftq_ifu_idx == k_mon_idx))
        k_mon_fetch <= k_mon_fetch + 1;
      if (ftq_ifu_xlate_val && (ftq_ifu_xlate_idx == k_mon_idx))
        k_mon_xlate <= k_mon_xlate + 1;
    end
  end

  task automatic chk(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
      $display("PASS: %s", nm);
    end else begin
      fail_cnt++;
      $display("FAIL: %s", nm);
    end
  endtask

  task automatic chk_va(input string nm,
                        input logic [VA_WIDTH-1:0] got,
                        input logic [VA_WIDTH-1:0] exp);
    if (got === exp) begin
      pass_cnt++;
      $display("PASS: %s", nm);
    end else begin
      fail_cnt++;
      $display("FAIL: %s  got %010h exp %010h", nm, got, exp);
    end
  endtask

  task automatic tick();
    @(posedge clk);
    #1;
  endtask

  task automatic do_reset();
    rstn                  = 1'b0;
    tage_pq_not_full      = 1'b1;
    ittage_pq_not_full    = 1'b1;
    sc_uq_not_full        = 1'b1;
    ckpt_ghist_ptr        = '0;
    ckpt_phist_ptr        = '0;
    bpu_pred_ras_p1       = '0;
    bpu_slot_val_p2       = 1'b0;
    bpu_slot_idx_p2       = '0;
    bpu_slot_val_p3       = 1'b0;
    bpu_slot_idx_p3       = '0;
    bpu_redir_idx_p2      = '0;
    bpu_redir_idx_p3      = '0;
    bpu_meta_val_p2       = 1'b0;
    bpu_meta_idx_p2       = '0;
    bpu_meta_val_p3       = 1'b0;
    bpu_meta_idx_p3       = '0;
    sc_enable             = 1'b1;
    tage_upd_rdy          = '1;
    ittage_upd_rdy        = '1;
    sc_upd_rdy            = '1;
    ftq_ifu_xlate_rdy     = 1'b1;
    ftq_ifu_req_rdy       = 1'b1;
    k_mon_on              = 1'b0;
    k_mon_idx             = '0;
    ifu_ftq_pdwb_val      = 1'b0;
    ifu_ftq_pdwb_idx      = '0;
    ifu_ftq_pdwb_gen      = 1'b0;
    ifu_ftq_pd_range      = '0;
    ifu_ftq_cfi_val       = 1'b0;
    ifu_ftq_cfi_pos       = '0;
    ifu_ftq_mis_val       = 1'b0;
    ifu_ftq_mis_pos       = '0;
    ifu_ftq_target        = '0;
    ifu_ftq_fault_val     = 1'b0;
    ifu_ftq_fault_pos     = '0;
    bkend_ftq_rsv_val     = '0;
    bkend_ftq_redir_val   = 1'b0;
    bkend_ftq_redir_idx   = '0;
    bkend_ftq_redir_pos   = '0;
    bkend_ftq_redir_pc    = '0;
    bkend_ftq_redir_self  = 1'b0;
    bkend_ftq_redir_cause = RC_MISPREDICT;
    bkend_ftq_redir_taken = 1'b0;
    bkend_ftq_commit_val  = 1'b0;
    bkend_ftq_commit_idx  = '0;
    mdl_tkn_en            = 1'b0;
    mdl_tkn_tgt           = '0;
    mdl_tkn_type          = COND;
    mdl_blk_ovr           = 1'b0;
    mdl_blk_idx           = '0;
    mdl_blk_pft           = '0;
    mdl_blk_ras           = '0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      bpu_slot_p2[s]        = '0;
      bpu_slot_p3[s]        = '0;
      bpu_redir_p2[s]       = '0;
      bpu_redir_p3[s]       = '0;
      bpu_meta_tage_p2[s]   = '0;
      bpu_meta_ittage_p2[s] = '0;
      bpu_meta_lp_p2[s]     = '0;
      bpu_meta_ftb_p2[s]    = '0;
      bpu_meta_sc_p3[s]     = '0;
    end
    for (int p = 0; p < NUM_RESOLVE_PORTS; p++) bkend_ftq_rsv[p] = '0;
    for (int i = 0; i < FTQ_PD_WIDTH; i++)      ifu_ftq_pd[i]    = '0;
    repeat (4) tick();
    rstn = 1'b1;
    #1;
  endtask

  // -----------------------------------------------------------------
  // A. Elaboration and reset.
  // -----------------------------------------------------------------
  task automatic group_a();
    $display("-- A: elaboration and reset --");
    do_reset();

    chk   ("A1 the queue is empty at reset",  ftq_empty);
    chk   ("A2 and not full",                 !ftq_full);
    chk   ("A3 a prediction is requested",    ftq_pred_val_p0);
    chk_va("A4 for the reset vector",         ftq_pred_pc_p0,
           RESET_VECTOR);
    chk   ("A5 with index zero",              ftq_pred_idx_p0 == '0);
    chk   ("A6 no fetch is requested yet",    !ftq_ifu_req_val);
    chk   ("A7 no flush",                     !ftq_ifu_flush_val);
    chk   ("A8 no rollback",                  !ftq_rollback_val);
    chk   ("A9 no RAS commit",                !ras_commit_val);
    chk   ("A10 no FTB update",               !ftb_upd_valid_u0);
    chk   ("A11 resolution is ready",         &ftq_bkend_rsv_rdy);
  endtask

  // -----------------------------------------------------------------
  // B. THE STEADY-STATE LOOP.
  // -----------------------------------------------------------------
  // One block per cycle with NO BUBBLE. The p1 response for block N
  // arrives in the same cycle the request for block N+1 must be
  // presented, and ftq_npc's combinational successor path is what
  // makes that possible. A registered path would present the same
  // PC twice and the progression below would advance every other
  // cycle instead of every cycle.
  task automatic group_b();
    $display("-- B: the zero-bubble loop --");
    do_reset();

    // Cycle 0 requests the reset vector. Cycle 1 must request
    // RESET_VECTOR + 32, because the p1 response for the reset
    // block arrives in cycle 1 with its fall-through and the
    // successor selection is combinational.
    tick();
    chk_va("B1 the very next cycle requests the successor",
           ftq_pred_pc_p0,
           VA_WIDTH'(RESET_VECTOR + FTB_BLOCK_BYTES));
    chk   ("B2 and the index advanced",  ftq_pred_idx_p0 == 6'd1);
    chk   ("B3 the request is still valid", ftq_pred_val_p0);

    // Sixteen more, one per cycle. The PC is an arithmetic
    // progression in FTB_BLOCK_BYTES and the index counts by one; a
    // bubble anywhere shows as a repeated value.
    begin
      int bad_pc;
      int bad_idx;
      bad_pc  = 0;
      bad_idx = 0;
      for (int i = 2; i < 18; i++) begin
        tick();
        if (ftq_pred_pc_p0 !==
              VA_WIDTH'(RESET_VECTOR + i * FTB_BLOCK_BYTES)) bad_pc++;
        if (ftq_pred_idx_p0 !== FTQ_IDX_BITS'(i)) bad_idx++;
      end
      chk("B4 sixteen blocks, one PC per cycle, no bubble",
          bad_pc == 0);
      chk("B5 sixteen indices, one per cycle",  bad_idx == 0);
    end

    // A TAKEN SLOT resteers the loop in the same cycle, without a
    // redirect: this is arm 5 of 4.2, not arms 3 or 4.
    mdl_tkn_en  = 1'b1;
    mdl_tkn_tgt = VA_WIDTH'('h00_C000_0000);
    tick();
    tick();
    chk_va("B6 a taken slot supplies the successor",
           ftq_pred_pc_p0, VA_WIDTH'('h00_C000_0000));
    chk   ("B7 and no redirect was published", !ftq_ifu_flush_val);
    mdl_tkn_en = 1'b0;

    // H1 STOPS THE LOOP AND DOES NOT LOSE IT. The cluster has no
    // request-ready output, so this is the FTQ's obligation.
    tick();
    begin
      logic [VA_WIDTH-1:0] held;
      held             = ftq_pred_pc_p0;
      tage_pq_not_full = 1'b0;
      #1;
      chk("B8 H1 deasserts the request", !ftq_pred_val_p0);
      repeat (5) tick();
      chk_va("B9 and the PC is retained", ftq_pred_pc_p0, held);
      tage_pq_not_full = 1'b1;
      #1;
      chk   ("B10 the request resumes",   ftq_pred_val_p0);
      chk_va("B11 with the held PC",      ftq_pred_pc_p0, held);
    end
  endtask

  // -----------------------------------------------------------------
  // C. Allocation to fetch request.
  // -----------------------------------------------------------------
  // ftq_ptr -> ftq_entry -> ftq_ifu, and ftq_shadow qualifying the
  // p1 write. Four modules and the wiring between them.
  task automatic group_c();
    $display("-- C: allocation to fetch request --");
    do_reset();

    // Stop the IFU accepting, so the run-ahead builds and the
    // request stays on entry 0 while allocation moves on.
    ftq_ifu_req_rdy = 1'b0;

    // Cycle 0 allocates entry 0 for the reset vector. Its content
    // lands at p1 in cycle 1, and the fetch request may only appear
    // once it has -- the p0-to-p1 gap ftq_shadow reports.
    chk("C1 no fetch request in the allocation cycle",
        !ftq_ifu_req_val);
    tick();
    chk("C2 none while the p1 write is still in flight",
        !ftq_ifu_req_val);
    tick();

    // THE TRANSLATION COMES FIRST (BP-112, TD#127). The entry is
    // written, so xlate_ptr presents it on ftq_ifu_interfaces.md 4.1
    // in this cycle; FQ-1 holds fetch_ptr behind xlate_ptr, so the
    // fetch request follows one cycle later. L1I-3: a fetch cannot
    // issue in the cycle its translation begins.
    chk   ("C2a the translation is presented once the entry is written",
           ftq_ifu_xlate_val && (ftq_ifu_xlate_idx == '0));
    chk_va("C2b with the block start PC", ftq_ifu_xlate_pc,
           RESET_VECTOR);
    chk   ("C2c no fetch in the cycle its translation begins",
           !ftq_ifu_req_val);
    tick();
    chk   ("C3 a fetch is requested once the entry is written",
           ftq_ifu_req_val);
    chk   ("C4 for entry 0",       ftq_ifu_idx == '0);
    chk_va("C5 with the block start PC", ftq_ifu_start_pc,
           RESET_VECTOR);
    chk_va("C6 and the fall-through as the successor",
           ftq_ifu_next_pc,
           VA_WIDTH'(RESET_VECTOR + FTB_BLOCK_BYTES));
    chk   ("C7 no taken branch in the block",
           !ftq_ifu_taken_val);

    // The generation tag left with the request and the entry was
    // allocated once, so it is set.
    chk("C8 the generation tag is set", ftq_ifu_gen);

    // The IFU accepts, and the request moves to entry 1.
    ftq_ifu_req_rdy = 1'b1;
    tick();
    chk   ("C9 the request advances to entry 1",
           ftq_ifu_idx == 6'd1);
    chk_va("C10 with its own PC", ftq_ifu_start_pc,
           VA_WIDTH'(RESET_VECTOR + FTB_BLOCK_BYTES));

    // IFU BACKPRESSURE IS NOT A PREDICTION HOLD. That is the point
    // of a decoupled front end: only running out of entries couples
    // the two rates (4.5).
    ftq_ifu_req_rdy = 1'b0;
    repeat (8) tick();
    chk("C11 the FTQ keeps predicting while the IFU stalls",
        ftq_pred_val_p0);
    chk("C12 and the run-ahead built", !ftq_empty);
    ftq_ifu_req_rdy = 1'b1;
  endtask

  // -----------------------------------------------------------------
  // D. A backend redirect reaches every module.
  // -----------------------------------------------------------------
  task automatic group_d();
    $display("-- D: the redirect fan-out --");
    do_reset();

    // Build a run-ahead of twenty blocks.
    repeat (20) tick();
    chk("D1 the queue is not empty", !ftq_empty);

    // A backend mispredict naming entry 4, which survives.
    bkend_ftq_redir_val   = 1'b1;
    bkend_ftq_redir_idx   = 6'd4;
    bkend_ftq_redir_self  = 1'b0;
    bkend_ftq_redir_pc    = VA_WIDTH'('h00_D000_0000);
    bkend_ftq_redir_cause = RC_MISPREDICT;
    #1;
    // ftq_npc: the corrected PC is presented at p0 immediately.
    chk_va("D2 the corrected PC is requested", ftq_pred_pc_p0,
           VA_WIDTH'('h00_D000_0000));
    // ftq_ifu: the flush group is driven, starting one past the
    // naming entry because it survives.
    chk   ("D3 the IFU is flushed",  ftq_ifu_flush_val);
    chk   ("D4 from the entry after the named one",
           ftq_ifu_flush_idx == 6'd5);
    // ftq_npc again: the restore, D1 and D2 together.
    chk   ("D5 the history rollback is driven", ftq_rollback_val);
    chk   ("D6 naming the surviving entry",
           ftq_rollback_idx == 6'd4);
    chk   ("D7 and the RAS restore with it",    ras_restore_val);
    // ftq_commit: the walk is suppressed in a restore cycle.
    chk   ("D8 no RAS commit in a restore cycle", !ras_commit_val);

    tick();
    bkend_ftq_redir_val = 1'b0;
    #1;
    // ftq_ptr: the rewind. Allocation restarts at 5, and the request
    // presented WITH the redirect took 5 for the corrected PC, so the
    // next index issued is 6. CHANGED BY BP-113: this read 5, which
    // was TD#139 -- entry 5 then held the target's fall-through and
    // the target block itself was lost. Group G checks the PCs.
    chk("D9 allocation rewound to the entry after",
        ftq_pred_idx_p0 == 6'd6);
    chk("D10 the flush deasserted with the redirect",
        !ftq_ifu_flush_val);

    // _self SET squashes the naming entry too.
    repeat (6) tick();
    bkend_ftq_redir_val  = 1'b1;
    bkend_ftq_redir_idx  = 6'd7;
    bkend_ftq_redir_self = 1'b1;
    bkend_ftq_redir_pc   = VA_WIDTH'('h00_E000_0000);
    #1;
    chk("D11 _self set flushes from the named entry",
        ftq_ifu_flush_idx == 6'd7);
    chk("D12 and restores from the one before",
        ftq_rollback_idx == 6'd6);
    tick();
    bkend_ftq_redir_val = 1'b0;
    #1;
    // Rewound to 7, which the redirect-cycle request took (BP-113).
    chk("D13 allocation rewound to the named entry",
        ftq_pred_idx_p0 == 6'd8);

    // RC_UNSPEC squashes EVERY entry and performs NO restore.
    repeat (6) tick();
    bkend_ftq_redir_val   = 1'b1;
    bkend_ftq_redir_idx   = 6'd33;
    bkend_ftq_redir_self  = 1'b1;
    bkend_ftq_redir_pc    = VA_WIDTH'('h00_F000_0000);
    bkend_ftq_redir_cause = RC_UNSPEC;
    #1;
    chk   ("D14 RC_UNSPEC performs no restore", !ftq_rollback_val);
    chk   ("D15 and no RAS restore",            !ras_restore_val);
    chk   ("D16 but it does flush",             ftq_ifu_flush_val);
    chk_va("D17 and it requests its PC",        ftq_pred_pc_p0,
           VA_WIDTH'('h00_F000_0000));
    tick();
    bkend_ftq_redir_val   = 1'b0;
    bkend_ftq_redir_cause = RC_MISPREDICT;
    #1;
    // U3 empties the queue and the redirect-cycle request then takes
    // the first entry for the RC_UNSPEC PC, so exactly one entry is
    // live. CHANGED BY BP-113: this read ftq_empty, which held only
    // because that request was lost (TD#139).
    chk("D18 the queue is emptied, then holds only the target",
        !ftq_empty &&
        ((dut.w_alloc_ptr - dut.w_commit_ptr) == FTQ_PTR_BITS'(1)));
  endtask

  // -----------------------------------------------------------------
  // E. The commit walk and the RAS group.
  // -----------------------------------------------------------------
  task automatic group_e();
    $display("-- E: the commit walk --");
    do_reset();

    // Ten blocks, and the p2 slot correction gives entry 3 a taken
    // call so the walk has a RAS operation to issue when it reaches
    // it. The correction is presented two cycles after the request,
    // which is where p2 sits.
    repeat (12) tick();
    chk("E1 the queue holds the run-ahead", !ftq_empty);

    // Commit through entry 5. The watermark carries its generation,
    // so this is the pointer value and not an index.
    bkend_ftq_commit_val = 1'b1;
    bkend_ftq_commit_idx = FTQ_PTR_BITS'(5);
    tick();

    // ONE ENTRY PER CYCLE, because the ras_commit_* group is scalar
    // and FE-11 gives at most one RAS operation per entry.
    repeat (6) tick();
    bkend_ftq_commit_val = 1'b0;

    // The walk has freed six entries, so the queue shrank. It is
    // not empty -- allocation kept running ahead throughout.
    chk("E2 the queue is still not empty", !ftq_empty);

    // A REDIRECT SUPPRESSES THE WALK. ras_decisions.md 4.5 orders
    // BOS restore > commit > hold, so the FTQ suppresses the RAS
    // commit it would have issued in a restore cycle.
    bkend_ftq_commit_val  = 1'b1;
    bkend_ftq_commit_idx  = FTQ_PTR_BITS'(9);
    bkend_ftq_redir_val   = 1'b1;
    bkend_ftq_redir_idx   = 6'd15;
    bkend_ftq_redir_self  = 1'b0;
    bkend_ftq_redir_pc    = VA_WIDTH'('h00_A000_0000);
    bkend_ftq_redir_cause = RC_MISPREDICT;
    #1;
    chk("E3 the RAS commit is suppressed by the restore",
        !ras_commit_val);
    tick();
    bkend_ftq_redir_val = 1'b0;
    bkend_ftq_commit_val = 1'b0;
    repeat (6) tick();

    // The queue drains to empty when the watermark reaches the
    // head. commit_ptr never rewinds, so this is the whole live
    // window retiring.
    tage_pq_not_full = 1'b0;   // stop allocating so the walk can
                               // catch up with a fixed head
    #1;
    begin
      logic [FTQ_PTR_BITS-1:0] head;
      head = FTQ_PTR_BITS'(0);
      // Walk the watermark forward until the queue reports empty,
      // bounded so a stuck walk fails the check rather than hangs.
      bkend_ftq_commit_val = 1'b1;
      for (int i = 0; i < 2 * FTQ_DEPTH; i++) begin
        bkend_ftq_commit_idx = head;
        tick();
        if (ftq_empty) break;
        head = head + 1'b1;
      end
      bkend_ftq_commit_val = 1'b0;
      chk("E4 the walk drains the queue to empty", ftq_empty);
    end
    tage_pq_not_full = 1'b1;
  endtask

  // -----------------------------------------------------------------
  // F. A front-end redirect, end to end (BP-112, TD#126 and TD#127).
  // -----------------------------------------------------------------
  // A predecode redirect names entry K = 3, which was fetched against
  // a p1 miss. K SURVIVES, CORRECTED, and is NOT fetched again: its
  // positions up to mis_pos are already in the ibuf, which does not
  // clear on a predecode redirect (IB-12), so the IFU flush names K+1
  // (ftq_ifu_interfaces.md 7 W3), xlate_ptr and fetch_ptr come back
  // to K+1 (ftq_decisions.md 5.5 R1), and the first block translated
  // and fetched is K+1, the corrected successor. Ruled session-074,
  // TD#146. CHANGED BY BP-117: this group pinned F = K and the
  // refetch of K, the BP-112 build; each changed check carries its
  // old value. Group D holds the backend half.
  //
  // The waits below are BOUNDED and ordered rather than cycle exact:
  // what is checked is which entry each port names next, not how many
  // cycles the refill takes.
  localparam logic [VA_WIDTH-1:0] PD_TGT = VA_WIDTH'('h00_B000_0000);

  task automatic group_f();
    int n_x;
    int n_f;
    int k_f0;
    int k_x0;
    $display("-- F: a front-end redirect, end to end --");
    do_reset();
    repeat (12) tick();
    chk("F1 entry 3 was already fetched", ftq_ifu_idx > 6'd3);

    // The writeback for entry 3. Its generation is 1: one allocation
    // since reset. Predecode found a JAL at position 6 in a block the
    // p1 miss predicted to have none (M1).
    ifu_ftq_pdwb_val = 1'b1;
    ifu_ftq_pdwb_idx = 6'd3;
    ifu_ftq_pdwb_gen = 1'b1;
    ifu_ftq_pd[6]    = '{valid: 1'b1, is_rvc: 1'b0, br_type: 2'b10,
                         is_call: 1'b0, is_ret: 1'b0};
    ifu_ftq_mis_val  = 1'b1;
    ifu_ftq_mis_pos  = FTQ_PD_POS_BITS'(6);
    ifu_ftq_target   = PD_TGT;
    #1;
    chk("F2 the IFU is flushed",          ftq_ifu_flush_val);
    // was ftq_ifu_flush_idx == 3, "AT K, not K+1"
    chk("F3 AT K+1, not K",               ftq_ifu_flush_idx == 6'd4);
    chk_va("F4 fetch resumes at the corrected successor",
           ftq_pred_pc_p0, PD_TGT);
    tick();
    ifu_ftq_pdwb_val = 1'b0;
    ifu_ftq_mis_val  = 1'b0;
    ifu_ftq_pd[6]    = '0;
    k_mon_idx        = 6'd3;
    k_f0             = k_mon_fetch;
    k_x0             = k_mon_xlate;
    k_mon_on         = 1'b1;
    #1;
    // K+1 went out with the redirect, carrying PD_TGT (BP-113; this
    // read 4, TD#139).
    chk("F5 allocation restarts at K+1", ftq_pred_idx_p0 == 6'd5);
    // was ftq_ifu_xlate_idx == 3, "xlate_ptr is back on K"
    chk("F6 xlate_ptr is back on K+1",   ftq_ifu_xlate_idx == 6'd4);
    // was ftq_ifu_idx == 3, "fetch_ptr is back on K"
    chk("F7 fetch_ptr is back on K+1",   ftq_ifu_idx == 6'd4);

    // The next translation presented is K+1, and no fetch is
    // presented before it.
    n_x = 0;
    n_f = 0;
    for (int c = 0; c < 8; c++) begin
      if (ftq_ifu_xlate_val) break;
      if (ftq_ifu_req_val) n_f++;
      n_x++;
      tick();
    end
    // was ftq_ifu_xlate_idx == 3, "K is translated again"
    chk("F8 K+1 is the next translation, not K",
        ftq_ifu_xlate_val && (ftq_ifu_xlate_idx == 6'd4));
    chk("F9 with no fetch presented ahead of it", n_f == 0);
    // was RESET_VECTOR + 3 * FTB_BLOCK_BYTES, "K's own block start PC"
    chk_va("F10 with K+1's block start PC, the corrected successor",
           ftq_ifu_xlate_pc, PD_TGT);

    // Then K+1 is fetched: the first fetch after the redirect.
    for (int c = 0; c < 8; c++) begin
      if (ftq_ifu_req_val) break;
      tick();
    end
    // was ftq_ifu_idx == 3, "K is fetched again"
    chk("F11 K+1 is the first fetch, not K",
        ftq_ifu_req_val && (ftq_ifu_idx == 6'd4));
    // was ftq_ifu_taken_val && ftq_ifu_taken_pos == 6, "carrying the
    // corrected taken branch", which was K's refetch payload
    chk_va("F12 starting at the corrected successor",
           ftq_ifu_start_pc, PD_TGT);
    // was ftq_ifu_next_pc == PD_TGT, "and the corrected successor",
    // K's refetch; K+1 is a p1 miss and falls through
    chk_va("F13 and falling through from it", ftq_ifu_next_pc,
           VA_WIDTH'(PD_TGT + FTB_BLOCK_BYTES));
    repeat (16) tick();
    k_mon_on = 1'b0;
    // The ibuf already holds K's head (IB-2) and keeps it (IB-12), so
    // K must not be fetched again or its head is delivered twice.
    // Added by BP-117.
    chk($sformatf("F20 K is never fetched again (%0d) nor translated (%0d)",
                  k_mon_fetch - k_f0, k_mon_xlate - k_x0),
        (k_mon_fetch == k_f0) && (k_mon_xlate == k_x0));

    // A SECOND WRITEBACK FOR K (ftq_entry_formats.md 4.3 R3a, TD#140,
    // BP-114). R3a was written for the W3 refetch of K, which produced
    // it on every predecode redirect while the flush was at K. BP-117
    // moves the flush to K+1, F20 shows K is not refetched, and the
    // writeback below is INJECTED to keep R3's bound covered: it
    // arrives with wb_rcvd[K] set and gen[K] unchanged, is LEGAL,
    // accepted by 6.1 X3, and derives NO redirect, both when
    // predecode agrees with the corrected entry and when it reports a
    // mispredict again. ftq_ifu_assert I4 samples every cycle here.
    // The state R3a describes, read rather than assumed. F14 and F15
    // keep their values; the edge above no longer accepts a refetch.
    chk("F14 wb_rcvd[K] is still set from the first writeback",
        dut.w_wb_rcvd_vec[3]);
    chk("F15 and gen[K] is unchanged: K was not reallocated",
        dut.w_gen_vec[3] == 1'b1);
    ifu_ftq_pdwb_val = 1'b1;
    ifu_ftq_pdwb_idx = 6'd3;
    ifu_ftq_pdwb_gen = 1'b1;
    ifu_ftq_mis_val  = 1'b0;
    #1;
    chk("F16 the refetch writeback is accepted",
        dut.w_wb_accept && !dut.w_wb_drop_gen);
    chk("F17 and derives no redirect", !ftq_ifu_flush_val);
    tick();
    // The same writeback reporting a mispredict at the position the
    // correction already holds.
    ifu_ftq_pd[6]    = '{valid: 1'b1, is_rvc: 1'b0, br_type: 2'b10,
                         is_call: 1'b0, is_ret: 1'b0};
    ifu_ftq_mis_val  = 1'b1;
    ifu_ftq_mis_pos  = FTQ_PD_POS_BITS'(6);
    ifu_ftq_target   = PD_TGT;
    #1;
    chk("F18 a refetch writeback with mis_val is accepted too",
        dut.w_wb_accept);
    chk("F19 and still derives no redirect",
        !ftq_ifu_flush_val && !dut.w_pd_redir_val);
    tick();
    ifu_ftq_pdwb_val = 1'b0;
    ifu_ftq_mis_val  = 1'b0;
    ifu_ftq_pd[6]    = '0;
    tick();
  endtask

  // -----------------------------------------------------------------
  // G. The redirect target block is fetched (BP-113, TD#139).
  // -----------------------------------------------------------------
  // In a redirect cycle ftq_npc presents the redirect target at p0.
  // The index leaving with it must be the one 5.5 R1 allocates, so
  // the target block is written to an entry that survives and is the
  // first NEW block fetched. Group D checks only the index; this
  // group checks the PC each fetch carries, which is what the defect
  // loses.
  //
  // THE FETCH IS CAPTURED ON ITS HANDSHAKE. ftq_ifu_req_rdy is high
  // throughout, so a presented request is an issued one. The redirect
  // cycle itself is not sampled: its request comes from the
  // pre-rewind pointer and its handshake is dropped (TD#138).
  //
  // THE TRANSLATION LATENCY IS PINNED, not bounded: c counts the
  // cycles after the redirect cycle until the flush entry F is
  // presented for translation. When F is the redirect target block
  // itself, its p1 write lands at the end of the first cycle, so it
  // is two: the backend _self-clear row and, since BP-117, the
  // predecode row (F = K+1, TD#146). A p2 or p3 redirect has F = K,
  // already written, and 5.1 and IFU-27 give it one cycle; this
  // group does not drive p2 or p3. The predecode row read one cycle,
  // F = K, until BP-117.
  task automatic next_fetch(output logic [FTQ_IDX_BITS-1:0] idx,
                            output logic [VA_WIDTH-1:0]     pc);
    idx = '1;
    pc  = '1;
    for (int c = 0; c < 16; c++) begin
      if (ftq_ifu_req_val) begin
        idx = ftq_ifu_idx;
        pc  = ftq_ifu_start_pc;
        break;
      end
      tick();
    end
    $display("  fetch: idx %0d start_pc %010h", idx, pc);
    tick();
  endtask

  task automatic xlate_wait(input  logic [FTQ_IDX_BITS-1:0] f_idx,
                            output int                      lat);
    lat = -1;
    for (int c = 1; c < 16; c++) begin
      if (ftq_ifu_xlate_val && (ftq_ifu_xlate_idx == f_idx)) begin
        lat = c;
        break;
      end
      tick();
    end
    $display("  xlate of entry %0d presented %0d cycle(s) after the %s",
             f_idx, lat, "redirect cycle");
  endtask

  // One backend redirect cycle, then deasserted.
  task automatic bkend_redirect(input logic [FTQ_IDX_BITS-1:0] idx,
                                input logic                    self_sq,
                                input ftq_redir_cause_e        cause,
                                input logic [VA_WIDTH-1:0]     pc);
    bkend_ftq_redir_val   = 1'b1;
    bkend_ftq_redir_idx   = idx;
    bkend_ftq_redir_self  = self_sq;
    bkend_ftq_redir_pc    = pc;
    bkend_ftq_redir_cause = cause;
    #1;
    $display("  redirect cycle: p0 idx %0d pc %010h", ftq_pred_idx_p0,
             ftq_pred_pc_p0);
  endtask

  task automatic bkend_release();
    tick();
    bkend_ftq_redir_val   = 1'b0;
    bkend_ftq_redir_self  = 1'b0;
    bkend_ftq_redir_cause = RC_MISPREDICT;
    #1;
  endtask

  localparam logic [VA_WIDTH-1:0] G_PD_TGT = VA_WIDTH'('h00_B000_0000);
  localparam logic [VA_WIDTH-1:0] G_BC_TGT = VA_WIDTH'('h00_D000_0000);
  localparam logic [VA_WIDTH-1:0] G_BS_TGT = VA_WIDTH'('h00_E000_0000);
  localparam logic [VA_WIDTH-1:0] G_UN_TGT = VA_WIDTH'('h00_F000_0000);

  task automatic group_g();
    logic [FTQ_IDX_BITS-1:0] f_idx;
    logic [VA_WIDTH-1:0]     f_pc;
    int                      lat;
    $display("-- G: the redirect target block is fetched --");

    // ---- predecode redirect, K = 3, K survives: alloc_ptr -> K+1 ----
    // Same stimulus as group F. Entry 3 was fetched against a p1
    // miss; predecode finds a JAL at position 6.
    do_reset();
    repeat (12) tick();
    chk("G1 entry 3 was already fetched", ftq_ifu_idx > 6'd3);
    ifu_ftq_pdwb_val = 1'b1;
    ifu_ftq_pdwb_idx = 6'd3;
    ifu_ftq_pdwb_gen = 1'b1;
    ifu_ftq_pd[6]    = '{valid: 1'b1, is_rvc: 1'b0, br_type: 2'b10,
                         is_call: 1'b0, is_ret: 1'b0};
    ifu_ftq_mis_val  = 1'b1;
    ifu_ftq_mis_pos  = FTQ_PD_POS_BITS'(6);
    ifu_ftq_target   = G_PD_TGT;
    #1;
    $display("  redirect cycle: p0 idx %0d pc %010h", ftq_pred_idx_p0,
             ftq_pred_pc_p0);
    chk_va("G2 the target is requested in the redirect cycle",
           ftq_pred_pc_p0, G_PD_TGT);
    chk   ("G3 at the post-rewind index K+1", ftq_pred_idx_p0 == 6'd4);
    tick();
    ifu_ftq_pdwb_val = 1'b0;
    ifu_ftq_mis_val  = 1'b0;
    ifu_ftq_pd[6]    = '0;
    #1;
    chk   ("G4 the next index follows it", ftq_pred_idx_p0 == 6'd5);
    // was xlate_wait(3), lat == 1, "K is translated one cycle after
    // the redirect"
    xlate_wait(6'd4, lat);
    chk   ("G5 F = K+1 is translated two cycles after the redirect",
           lat == 2);
    next_fetch(f_idx, f_pc);
    // was f_idx == 3, "the first fetch is the refetch of K"
    chk   ("G6 the first fetch is entry K+1, not a refetch of K",
           f_idx == 6'd4);
    // was f_idx == 4 on the second fetch, "the next fetch is entry K+1"
    chk_va("G7 and carries the redirect target", f_pc, G_PD_TGT);
    next_fetch(f_idx, f_pc);
    // was f_pc == G_PD_TGT on the second fetch, "and carries the
    // redirect target"
    chk_va("G8 then the target's fall-through", f_pc,
           VA_WIDTH'(G_PD_TGT + FTB_BLOCK_BYTES));
    // was f_pc == G_PD_TGT + 32 on the third fetch, "then the target's
    // fall-through"
    chk   ("G9 at entry K+2", f_idx == 6'd5);

    // ---- backend, _self clear, K = 4: alloc_ptr -> K+1, F = K+1 -----
    do_reset();
    repeat (20) tick();
    bkend_redirect(6'd4, 1'b0, RC_MISPREDICT, G_BC_TGT);
    chk   ("G10 _self clear: the target is at index K+1",
           ftq_pred_idx_p0 == 6'd5);
    bkend_release();
    xlate_wait(6'd5, lat);
    chk   ("G11 F is translated two cycles after the redirect",
           lat == 2);
    next_fetch(f_idx, f_pc);
    chk   ("G12 the first fetch is entry K+1", f_idx == 6'd5);
    chk_va("G13 and carries the redirect target", f_pc, G_BC_TGT);
    next_fetch(f_idx, f_pc);
    chk_va("G14 then the target's fall-through", f_pc,
           VA_WIDTH'(G_BC_TGT + FTB_BLOCK_BYTES));

    // ---- backend, _self set, K = 7: alloc_ptr -> K, F = K -----------
    do_reset();
    repeat (20) tick();
    bkend_redirect(6'd7, 1'b1, RC_TRAP, G_BS_TGT);
    chk   ("G15 _self set: the target is at index K",
           ftq_pred_idx_p0 == 6'd7);
    bkend_release();
    xlate_wait(6'd7, lat);
    chk   ("G16 F is translated two cycles after the redirect",
           lat == 2);
    next_fetch(f_idx, f_pc);
    chk   ("G17 the first fetch is entry K", f_idx == 6'd7);
    chk_va("G18 and carries the redirect target", f_pc, G_BS_TGT);
    next_fetch(f_idx, f_pc);
    chk_va("G19 then the target's fall-through", f_pc,
           VA_WIDTH'(G_BS_TGT + FTB_BLOCK_BYTES));

    // ---- RC_UNSPEC: alloc_ptr -> commit_ptr, which is 0 here --------
    // _idx and _self are driven to values that would give a
    // different answer if read (U1, U2).
    do_reset();
    repeat (20) tick();
    bkend_redirect(6'd33, 1'b1, RC_UNSPEC, G_UN_TGT);
    chk   ("G20 RC_UNSPEC: the target is at commit_ptr",
           ftq_pred_idx_p0 == 6'd0);
    bkend_release();
    next_fetch(f_idx, f_pc);
    chk   ("G21 the first fetch is entry 0", f_idx == 6'd0);
    chk_va("G22 and carries the redirect target", f_pc, G_UN_TGT);
  endtask

  // -----------------------------------------------------------------
  // H. RC_UNSPEC with fetches in flight behind fetch_ptr (BP-114,
  //    TD#141).
  // -----------------------------------------------------------------
  // ftq_backend_interfaces.md 5.1 U3 squashes EVERY entry, and
  // ftq_ifu_interfaces.md 5 has the IFU drop every in-flight fetch AT
  // OR AFTER the flush index. The only index that drops the whole live
  // window is the OLDEST live entry, which is commit_ptr's. Group G's
  // RC_UNSPEC row has commit_ptr at 0; here it is moved off 0 first,
  // so a flush index of 0 or of fetch_idx cannot pass by coincidence.
  //
  // THE IFU IS MODELLED HERE as a record of issued fetches, h_ifl,
  // one bit per index. A fetch is issued on its handshake and the
  // model ignores a request presented in a flush cycle (section 5,
  // TD#138). Retiring an entry through commit clears its bit: its
  // writeback has returned. On the flush the model applies section 5
  // literally, measuring "after" from its own oldest in-flight entry,
  // h_base, which is what an IFU can see.
  localparam logic [VA_WIDTH-1:0] H_UN_TGT = VA_WIDTH'('h00_F100_0000);

  logic [FTQ_DEPTH-1:0]    h_ifl;
  logic [FTQ_IDX_BITS-1:0] h_base;
  int                      h_cyc;
  int                      h_cp_bad;

  // Tick n cycles, recording each fetch handshake the IFU would act
  // on. The request is sampled before the edge it is accepted at.
  //
  // ftq_ifu_commit_ptr (TD#142) is compared with ftq_commit's pointer
  // in EVERY cycle this task runs, whatever the request and redirect
  // are doing, which is what "driven continuously" means.
  task automatic h_run(input int n);
    for (int c = 0; c < n; c++) begin
      h_cyc++;
      if (ftq_ifu_commit_ptr !== dut.w_commit_ptr[FTQ_IDX_BITS-1:0]) begin
        h_cp_bad++;
      end
      if (ftq_ifu_req_val && ftq_ifu_req_rdy && !ftq_ifu_flush_val) begin
        h_ifl[ftq_ifu_idx] = 1'b1;
      end
      tick();
    end
  endtask

  function automatic int h_count();
    int n;
    n = 0;
    for (int i = 0; i < FTQ_DEPTH; i++) n += int'(h_ifl[i]);
    return n;
  endfunction

  task automatic group_h();
    logic [FTQ_IDX_BITS-1:0] f_idx;
    logic [VA_WIDTH-1:0]     f_pc;
    logic [FTQ_IDX_BITS-1:0] c_idx;
    logic [FTQ_IDX_BITS-1:0] fl_age;
    int                      n_live;
    int                      n_keep;
    $display("-- H: RC_UNSPEC with fetches in flight --");
    do_reset();
    h_ifl    = '0;
    h_base   = '0;
    h_cyc    = 0;
    h_cp_bad = 0;

    // A run-ahead with the IFU accepting every cycle. Nothing commits,
    // so the exported pointer stays on 0 while allocation and fetch
    // move past it.
    h_run(20);
    chk("H8 allocation moves, ftq_ifu_commit_ptr stays on entry 0",
        (ftq_pred_idx_p0 > 6'd10) && (ftq_ifu_idx > 6'd10) &&
        (ftq_ifu_commit_ptr == 6'd0));

    // Commit through entry 5. The watermark is inclusive, so the walk
    // leaves commit_ptr on 6; it runs one entry per cycle and is
    // bounded here so a stuck walk fails H1 rather than hangs.
    bkend_ftq_commit_val = 1'b1;
    bkend_ftq_commit_idx = FTQ_PTR_BITS'(5);
    for (int c = 0; c < 16; c++) begin
      if (dut.w_commit_ptr == FTQ_PTR_BITS'(6)) break;
      h_run(1);
    end
    bkend_ftq_commit_val = 1'b0;
    c_idx = dut.w_commit_ptr[FTQ_IDX_BITS-1:0];
    chk("H1 commit_ptr is off zero, on entry 6",
        dut.w_commit_ptr == FTQ_PTR_BITS'(6));
    chk("H9 ftq_ifu_commit_ptr follows the commit to entry 6",
        ftq_ifu_commit_ptr == 6'd6);

    // Entries 0 to 5 retired, so their writebacks have returned.
    for (int i = 0; i < 6; i++) h_ifl[i] = 1'b0;
    h_base = c_idx;

    // THE STIMULUS THE CASE RELIES ON, checked rather than assumed:
    // every entry from commit_ptr up to fetch_ptr has been issued and
    // is still in flight, and there is more than one of them.
    n_live = int'(FTQ_IDX_BITS'(ftq_ifu_idx - c_idx));
    $display("  commit_ptr %0d fetch_ptr %0d in flight %0d",
             c_idx, ftq_ifu_idx, h_count());
    chk("H2 fetches are in flight between commit_ptr and fetch_ptr",
        (n_live > 1) && (h_count() == n_live));

    // RC_UNSPEC. _idx and _self are driven to values that would give
    // a different answer if read (U1, U2).
    bkend_redirect(6'd33, 1'b1, RC_UNSPEC, H_UN_TGT);
    $display("  RC_UNSPEC flush_idx %0d, commit_ptr %0d, fetch_idx %0d",
             ftq_ifu_flush_idx, c_idx, ftq_ifu_idx);
    chk("H3 RC_UNSPEC flushes the IFU", ftq_ifu_flush_val);
    chk("H4 the flush index names the oldest live entry, commit_ptr",
        ftq_ifu_flush_idx == c_idx);
    // commit_ptr never rewinds (5.5 R2), and the export is driven in
    // the redirect cycle as in any other.
    chk("H10 ftq_ifu_commit_ptr holds through the redirect cycle",
        ftq_ifu_commit_ptr == c_idx);

    // Section 5 applied by the model: drop every in-flight fetch whose
    // index is at or after the flush index.
    fl_age = FTQ_IDX_BITS'(ftq_ifu_flush_idx - h_base);
    for (int i = 0; i < FTQ_DEPTH; i++) begin
      if (FTQ_IDX_BITS'(FTQ_IDX_BITS'(i) - h_base) >= fl_age) begin
        h_ifl[i] = 1'b0;
      end
    end
    n_keep = h_count();
    $display("  in-flight fetches surviving the flush: %0d", n_keep);
    chk("H5 no in-flight fetch survives an RC_UNSPEC flush",
        n_keep == 0);
    bkend_release();

    // Allocation restarted at commit_ptr (U3), so the first fetch of
    // the corrected stream is entry 6 carrying the RC_UNSPEC PC.
    next_fetch(f_idx, f_pc);
    chk   ("H6 the first fetch is the commit_ptr entry", f_idx == c_idx);
    chk_va("H7 and carries the RC_UNSPEC PC", f_pc, H_UN_TGT);

    // IFU-22 on the live unit. The first fetch of the corrected stream
    // is AT commit_ptr, so an uncached block there may issue its bus
    // read; the next one is ahead of it and must wait.
    chk("H11 the refetched entry is at ftq_ifu_commit_ptr: uncached may go",
        f_idx == ftq_ifu_commit_ptr);
    next_fetch(f_idx, f_pc);
    chk("H12 the next entry is ahead of it: uncached must wait",
        (f_idx == FTQ_IDX_BITS'(c_idx + 1'b1)) &&
        (f_idx != ftq_ifu_commit_ptr));
    h_run(8);
    $display("  ftq_ifu_commit_ptr compared in %0d cycles, %0d mismatches",
             h_cyc, h_cp_bad);
    chk("H13 ftq_ifu_commit_ptr equals commit_ptr in every cycle",
        (h_cyc > 30) && (h_cp_bad == 0));
  endtask


  // -----------------------------------------------------------------
  // I. TD#113, the corrected fall-through (BP-118).
  // -----------------------------------------------------------------
  // The cluster writes bp_ftq_entry_t.pft_addr at p1 from
  // bpu_pred_pft_p1 and, since BP-118, rewrites it at p2 from
  // bpu_blk_pft_p2. The model's p1 view is a uBTB MISS, so its p1
  // fall-through is the block start plus FTB_BLOCK_BYTES; the p2
  // value for the entry under test is the start plus 8, an FTB that
  // ends the block earlier. Every reader of pft_addr is checked to
  // see the p2 value: the fetch successor, the predecode W3
  // successor, the RAS commit return address and the FTB update
  // fall-through. Before BP-118 every one of them read start + 32.
  localparam logic [VA_WIDTH-1:0] I_PFT0 =
    VA_WIDTH'(RESET_VECTOR + 8);

  task automatic group_i();
    int                      n;
    logic [FTQ_IDX_BITS-1:0] sq_idx;
    $display("-- I: the corrected fall-through, TD#113 --");

    // I1. THE NOT-TAKEN SUCCESSOR. Entry 0 holds no taken slot, so
    // the fetch request's next_pc is the entry's pft_addr.
    do_reset();
    ftq_ifu_req_rdy = 1'b0;
    mdl_blk_ovr = 1'b1;
    mdl_blk_idx = 6'd0;
    mdl_blk_pft = I_PFT0;
    n = 0;
    while (!(ftq_ifu_req_val && (ftq_ifu_idx == 6'd0)) && (n < 8)) begin
      tick();
      n++;
    end
    chk   ("I1 entry 0 is presented for fetch",
           ftq_ifu_req_val && (ftq_ifu_idx == 6'd0));
    chk   ("I1 with no taken slot", !ftq_ifu_taken_val);
    chk_va("I1 next_pc is the p2 fall-through, not the p1 one",
           ftq_ifu_next_pc, I_PFT0);
    // Entry 1 got the p1 value forward and is unchanged.
    chk_va("I1 an entry with no correction keeps the p1 value",
           dut.u_entry.r_arr[1].pft_addr,
           VA_WIDTH'(RESET_VECTOR + 2 * FTB_BLOCK_BYTES));

    // I2. THE PREDECODE W3 SUCCESSOR. Entry 0 is rewritten with a
    // taken slot at position 2 and the writeback finds no control
    // transfer there (M2), so the corrected slot is not taken and
    // W3 re-derives the successor as the entry's pft_addr.
    ftq_ifu_req_rdy = 1'b1;
    repeat (6) tick();
    ifu_ftq_pdwb_val = 1'b1;
    ifu_ftq_pdwb_idx = 6'd0;
    ifu_ftq_pdwb_gen = 1'b1;
    ifu_ftq_pd[2]    = '{valid: 1'b1, is_rvc: 1'b0, br_type: 2'b00,
                         is_call: 1'b0, is_ret: 1'b0};
    ifu_ftq_pd_range = '1;
    ifu_ftq_mis_val  = 1'b1;
    ifu_ftq_mis_pos  = FTQ_PD_POS_BITS'(2);
    #1;
    chk   ("I2 a predecode redirect is derived", ftq_ifu_flush_val);
    chk_va("I2 W3 re-derives the successor from the p2 fall-through",
           ftq_pred_pc_p0, I_PFT0);
    tick();
    ifu_ftq_pdwb_val = 1'b0;
    ifu_ftq_mis_val  = 1'b0;
    ifu_ftq_pd[2]    = '0;
    ifu_ftq_pd_range = '0;
    tick();

    // I3. THE RAS COMMIT RETURN ADDRESS and I4 THE FTB UPDATE
    // FALL-THROUGH. Entry 0 is made a block ending in a taken direct
    // call at position 2, with the p2 fall-through as its return
    // address and a distinct p2 RAS snapshot.
    do_reset();
    mdl_tkn_en   = 1'b1;
    mdl_tkn_tgt  = VA_WIDTH'('h00_9100_0000);
    mdl_tkn_type = DIRECT_CALL;
    mdl_blk_ovr  = 1'b1;
    mdl_blk_idx  = 6'd0;
    mdl_blk_pft  = I_PFT0;
    mdl_blk_ras.tosr = RAS_PTR_BITS'(3);
    mdl_blk_ras.tosw = RAS_PTR_BITS'(4);
    tick();
    mdl_tkn_en = 1'b0;
    repeat (4) tick();
    chk("I3 entry 0 records the p2 RAS snapshot",
        dut.u_entry.r_arr[0].ras.tosw == RAS_PTR_BITS'(4));

    bkend_ftq_rsv_val                 = 2'b01;
    bkend_ftq_rsv[0]                  = '0;
    bkend_ftq_rsv[0].ftq_idx          = 6'd0;
    bkend_ftq_rsv[0].pos              = FTB_BR_POS_BITS'(2);
    bkend_ftq_rsv[0].taken            = 1'b1;
    bkend_ftq_rsv[0].target           = VA_WIDTH'('h00_9100_0000);
    bkend_ftq_rsv[0].br_type          = DIRECT_CALL;
    #1;
    chk_va("I4 the FTB update fall-through is the p2 value",
           dut.w_ftb_upd[0].pft_addr, I_PFT0);
    // BP-119, TD#151: the same resolution reaches the uBTB update port
    // through ftq_upd_conv, on the slot its position maps to, with the
    // same fall-through and the direct-call bits, and no queued
    // predictor is trained (fe_decisions.md 7.2).
    chk("I4a the uBTB update is presented for the direct call",
        ubtb_upd_u0[dut.w_rsv_slot[0]].valid
     && ubtb_upd_u0[dut.w_rsv_slot[0]].is_jmp
     && ubtb_upd_u0[dut.w_rsv_slot[0]].is_call
     && !ubtb_upd_u0[dut.w_rsv_slot[0]].is_ret
     && !ubtb_upd_u0[dut.w_rsv_slot[0]].is_jalr);
    chk_va("I4b with the p2 fall-through",
           ubtb_upd_u0[dut.w_rsv_slot[0]].pft_addr, I_PFT0);
    chk("I4c and no queued predictor is trained",
        (tage_upd_val_u0 == '0) && (ittage_upd_val_u0 == '0)
     && (sc_upd_val_u0 == '0) && (lp_upd_valid_p0 == '0));
    tick();
    bkend_ftq_rsv_val = '0;

    bkend_ftq_commit_val = 1'b1;
    bkend_ftq_commit_idx = FTQ_PTR_BITS'(1);
    n = 0;
    while (!ras_commit_val && (n < 8)) begin
      tick();
      n++;
    end
    chk   ("I3 the call block commits the RAS", ras_commit_val);
    chk_va("I3 with the p2 fall-through as the return address",
           ras_commit_ret_addr, I_PFT0);
    chk   ("I3 and the p2 snapshot",
           ras_commit_snapshot.tosw == RAS_PTR_BITS'(4));
    tick();
    bkend_ftq_commit_val = 1'b0;

    // I5. A p2 WRITE FOR A SQUASHED ENTRY DOES NOT LAND. A backend
    // redirect squashes the block at p1 in the redirect cycle; next
    // cycle that block's 4c group arrives at p2, carrying a value the
    // test marks. Allocation is then held so the index is not
    // reallocated over it before it can be read.
    do_reset();
    repeat (10) tick();
    sq_idx = bpu_pred_idx_p1;
    mdl_blk_ovr = 1'b1;
    mdl_blk_idx = sq_idx;
    mdl_blk_pft = VA_WIDTH'('h00_DEAD_0000);
    bkend_ftq_redir_val   = 1'b1;
    bkend_ftq_redir_idx   = sq_idx - 6'd3;
    bkend_ftq_redir_self  = 1'b0;
    bkend_ftq_redir_pc    = VA_WIDTH'('h00_A000_0000);
    bkend_ftq_redir_cause = RC_MISPREDICT;
    tick();
    bkend_ftq_redir_val = 1'b0;
    tage_pq_not_full    = 1'b0;
    #1;
    chk("I5 the squashed block's p2 group is presented",
        bpu_blk_val_p2 && (bpu_blk_idx_p2 == sq_idx));
    chk("I5 and the shadow drops it", !dut.w_ok_blk_p2);
    tick();
    chk("I5 so its value did not land in the entry",
        dut.u_entry.r_arr[sq_idx].pft_addr !=
          VA_WIDTH'('h00_DEAD_0000));
    tage_pq_not_full = 1'b1;
    mdl_blk_ovr      = 1'b0;
  endtask

  // -----------------------------------------------------------------
  // J. TD#157, BP-120. A resolution held for several cycles by a
  //    TAGE ready low (hold_tage) or an SC ready low (the SC grant
  //    withheld) is presented, then released. n_ftb counts the cycles
  //    the FTB update port is valid; n_acc the cycles the channel is
  //    accepted. Before BP-120 the scheduler took the FTB update every
  //    cycle the resolution was held, so n_ftb was the cycles held + 1.
  // -----------------------------------------------------------------
  task automatic j_held(input logic hold_tage, output int n_ftb,
                        output int n_acc);
    logic acc;
    do_reset();
    repeat (6) tick();                     // entries 0.. allocate
    bkend_ftq_rsv_val       = 2'b01;
    bkend_ftq_rsv[0]        = '0;
    bkend_ftq_rsv[0].ftq_idx = 6'd1;
    bkend_ftq_rsv[0].pos     = FTB_BR_POS_BITS'(3);
    bkend_ftq_rsv[0].taken   = 1'b1;
    bkend_ftq_rsv[0].target  = VA_WIDTH'('h00_9A00_0000);
    bkend_ftq_rsv[0].br_type = COND;
    if (hold_tage) tage_upd_rdy = '0;
    else           sc_upd_rdy   = '0;
    n_ftb = 0;
    n_acc = 0;
    for (int k = 0; k < 12; k++) begin
      if (k == 5) begin
        tage_upd_rdy = '1;
        sc_upd_rdy   = '1;
      end
      #1;
      if (ftb_upd_valid_u0) n_ftb++;
      acc = bkend_ftq_rsv_val[0] && ftq_bkend_rsv_rdy[0];
      if (acc) n_acc++;
      tick();
      if (acc) bkend_ftq_rsv_val = '0;     // the backend withdraws
    end
  endtask

  task automatic group_j();
    int n_ftb;
    int n_acc;
    $display("-- J: the FTB trained once per held resolution, TD#157 --");
    j_held(1'b1, n_ftb, n_acc);
    // OLD (until BP-120): n_ftb == 6, one per cycle presented.
    chk($sformatf("J1 held 5 cycles by TAGE: %0d FTB update(s), exp 1",
                  n_ftb), n_ftb == 1);
    chk($sformatf("J1 accepted once (%0d)", n_acc), n_acc == 1);
    j_held(1'b0, n_ftb, n_acc);
    chk($sformatf("J2 held 5 cycles by SC: %0d FTB update(s), exp 1",
                  n_ftb), n_ftb == 1);
    chk($sformatf("J2 accepted once (%0d)", n_acc), n_acc == 1);
  endtask

  // -----------------------------------------------------------------
  // Run
  // -----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    if (FTQ_DEPTH != 64 || NUM_PRED_SLOTS != 2) begin
      $fatal(1, "tb_ftq: written for FTQ_DEPTH 64, slots 2");
    end

    do_reset();
    group_a();
    group_b();
    group_c();
    group_d();
    group_e();
    group_f();
    group_g();
    group_h();
    group_i();
    group_j();

    $display("tb_ftq: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ftq: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #900000;
    $fatal(1, "tb_ftq: timeout");
  end

endmodule : tb
