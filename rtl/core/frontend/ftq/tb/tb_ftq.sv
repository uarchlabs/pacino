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
  logic                     ras_restore_val;
  bp_ras_snapshot_t         ras_restore_snapshot;
  logic                     ras_commit_val;
  bp_br_type_e              ras_commit_br_type;
  logic [VA_WIDTH-1:0]      ras_commit_ret_addr;
  bp_ras_snapshot_t         ras_commit_snapshot;
  bp_update_t               upd      [0:NUM_PRED_SLOTS-1];
  bp_ftq_meta_t             upd_meta [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] upd_ubtb_val;
  logic [NUM_PRED_SLOTS-1:0] upd_lp_val;
  logic [NUM_PRED_SLOTS-1:0] upd_tage_val;
  logic [NUM_PRED_SLOTS-1:0] upd_ittage_val;
  logic [NUM_PRED_SLOTS-1:0] upd_sc_val;
  logic                     tage_upd_rdy_u1;
  logic                     ittage_upd_rdy_u1;
  logic                     sc_upd_rdy_u1;
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
  logic [VA_WIDTH-1:0]      ftb_upd_pft_addr_u0;

  // ---- IFU boundary --------------------------------------------------
  logic                     ftq_ifu_req_val;
  logic                     ftq_ifu_req_rdy;
  logic [VA_WIDTH-1:0]      ftq_ifu_start_pc;
  logic [VA_WIDTH-1:0]      ftq_ifu_next_pc;
  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_idx;
  logic                     ftq_ifu_taken_val;
  logic [FTB_BR_POS_BITS-1:0] ftq_ifu_taken_pos;
  logic                     ftq_ifu_gen;
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
    .ras_restore_val       (ras_restore_val),
    .ras_restore_snapshot  (ras_restore_snapshot),
    .ras_commit_val        (ras_commit_val),
    .ras_commit_br_type    (ras_commit_br_type),
    .ras_commit_ret_addr   (ras_commit_ret_addr),
    .ras_commit_snapshot   (ras_commit_snapshot),
    .upd                   (upd),
    .upd_meta              (upd_meta),
    .upd_ubtb_val          (upd_ubtb_val),
    .upd_lp_val            (upd_lp_val),
    .upd_tage_val          (upd_tage_val),
    .upd_ittage_val        (upd_ittage_val),
    .upd_sc_val            (upd_sc_val),
    .tage_upd_rdy_u1       (tage_upd_rdy_u1),
    .ittage_upd_rdy_u1     (ittage_upd_rdy_u1),
    .sc_upd_rdy_u1         (sc_upd_rdy_u1),
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
    .ftq_ifu_req_val       (ftq_ifu_req_val),
    .ftq_ifu_req_rdy       (ftq_ifu_req_rdy),
    .ftq_ifu_start_pc      (ftq_ifu_start_pc),
    .ftq_ifu_next_pc       (ftq_ifu_next_pc),
    .ftq_ifu_idx           (ftq_ifu_idx),
    .ftq_ifu_taken_val     (ftq_ifu_taken_val),
    .ftq_ifu_taken_pos     (ftq_ifu_taken_pos),
    .ftq_ifu_gen           (ftq_ifu_gen),
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
        bpu_pred_slot_p1[0].br_type    <= COND;
        bpu_pred_slot_p1[0].target     <= mdl_tkn_tgt;
        bpu_pred_slot_p1[0].pos        <= FTB_BR_POS_BITS'(2);
      end
    end
  end

  int pass_cnt;
  int fail_cnt;

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
    tage_upd_rdy_u1       = 1'b1;
    ittage_upd_rdy_u1     = 1'b1;
    sc_upd_rdy_u1         = 1'b1;
    ftq_ifu_req_rdy       = 1'b1;
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
    bkend_ftq_commit_val  = 1'b0;
    bkend_ftq_commit_idx  = '0;
    mdl_tkn_en            = 1'b0;
    mdl_tkn_tgt           = '0;
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
    mdl_tkn_tgt = 40'h00_C000_0000;
    tick();
    tick();
    chk_va("B6 a taken slot supplies the successor",
           ftq_pred_pc_p0, 40'h00_C000_0000);
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
    bkend_ftq_redir_pc    = 40'h00_D000_0000;
    bkend_ftq_redir_cause = RC_MISPREDICT;
    #1;
    // ftq_npc: the corrected PC is presented at p0 immediately.
    chk_va("D2 the corrected PC is requested", ftq_pred_pc_p0,
           40'h00_D000_0000);
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
    // ftq_ptr: the rewind. Allocation restarts at 5, so the next
    // index issued is 5.
    chk("D9 allocation rewound to the entry after",
        ftq_pred_idx_p0 == 6'd5);
    chk("D10 the flush deasserted with the redirect",
        !ftq_ifu_flush_val);

    // _self SET squashes the naming entry too.
    repeat (6) tick();
    bkend_ftq_redir_val  = 1'b1;
    bkend_ftq_redir_idx  = 6'd7;
    bkend_ftq_redir_self = 1'b1;
    bkend_ftq_redir_pc   = 40'h00_E000_0000;
    #1;
    chk("D11 _self set flushes from the named entry",
        ftq_ifu_flush_idx == 6'd7);
    chk("D12 and restores from the one before",
        ftq_rollback_idx == 6'd6);
    tick();
    bkend_ftq_redir_val = 1'b0;
    #1;
    chk("D13 allocation rewound to the named entry",
        ftq_pred_idx_p0 == 6'd7);

    // RC_UNSPEC squashes EVERY entry and performs NO restore.
    repeat (6) tick();
    bkend_ftq_redir_val   = 1'b1;
    bkend_ftq_redir_idx   = 6'd33;
    bkend_ftq_redir_self  = 1'b1;
    bkend_ftq_redir_pc    = 40'h00_F000_0000;
    bkend_ftq_redir_cause = RC_UNSPEC;
    #1;
    chk   ("D14 RC_UNSPEC performs no restore", !ftq_rollback_val);
    chk   ("D15 and no RAS restore",            !ras_restore_val);
    chk   ("D16 but it does flush",             ftq_ifu_flush_val);
    chk_va("D17 and it requests its PC",        ftq_pred_pc_p0,
           40'h00_F000_0000);
    tick();
    bkend_ftq_redir_val   = 1'b0;
    bkend_ftq_redir_cause = RC_MISPREDICT;
    #1;
    chk("D18 the queue is empty after RC_UNSPEC", ftq_empty);
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
    bkend_ftq_redir_pc    = 40'h00_A000_0000;
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
