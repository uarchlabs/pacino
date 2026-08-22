// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Fetch target queue, structural top (BP-107),
// ftq_decisions.md 7.1 and 7.3.
//
// PURELY STRUCTURAL. Instantiation and wiring: no state, no always
// block, and no expression that reaches an output. Anything that
// needs a DECISION made in it belongs in a leaf instead, and where
// building this file wanted one, the leaf gained a port rather than
// this file gaining a gate. Every such case is listed in the BP-107
// Results Capture.
//
// THREE assign STATEMENTS, AND NONE OF THEM IS LOGIC:
//
//   ftq_pred_idx_p0 = w_alloc_idx      a rename
//   ras_restore_val = ftq_rollback_val an alias. D1 and D2 of
//                                      backend_interfaces 5 fire
//                                      together and from the same
//                                      derivation, so one net feeds
//                                      two consumers.
//   w_unused        = |{...}           a TERMINATION, reaching no
//                                      output. Every net in it is a
//                                      leaf observation port that
//                                      this file deliberately does
//                                      not export; see the block at
//                                      the end.
//
// IT DOES NOT INSTANTIATE bp_cluster. The BPU is a separate unit; a
// front-end top above both wires them together (7.1). The three
// boundaries this file presents are:
//
//   ftq_bpu       ftq_bpu_interfaces.md      BOTH
//   ftq_ifu       ftq_ifu_interfaces.md      BOTH
//   ftq_backend   ftq_backend_interfaces.md  IN
//
// A fourth, ftq_icache, is DELIBERATELY NOT DEFINED. The ICache is
// encapsulated behind the IFU (ftq_decisions.md 0).
//
// ELEVEN MODULES, one owner per piece of state (7.1):
//
//   ftq_ptr         alloc_ptr, fetch_ptr        5.1 5.2 5.5
//   ftq_commit      commit_ptr, the walk        5.3 5.4
//   ftq_npc         the next-PC register and
//                   the redirect arbitration    4
//   ftq_entry       the fast-path array         1 2
//   ftq_meta        the slow-path array         3
//   ftq_status      wb_rcvd, fault, gen         entry_formats 4
//   ftq_shadow      the response shadow         5.6
//   ftq_ifu         request, flush, writeback   ftq_ifu_ifs
//   ftq_resolve     resolution and fan-out      backend_ifs 4
//   ftq_ftb_sched   the FTB update scheduler    5.7  (BP-100)
//
// THE CROSSING BETWEEN ftq_ptr AND ftq_commit RUNS BOTH WAYS.
// commit_ptr goes to ftq_ptr for the full condition and for the
// generation reconstruction of the redirect index; alloc_ptr goes
// to ftq_commit to bound the walk end to the live window. One
// writer and one reader per pointer, so the partition rule holds;
// what does not hold is that the dependency runs one way (7.2,
// found by BP-106).
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq (
  input  logic                        clk,
  input  logic                        rstn,

  // =================================================================
  // BPU boundary, ftq_bpu_interfaces.md
  // =================================================================

  // ---- 3. prediction request, FTQ to BPU ---------------------------
  output logic                        ftq_pred_val_p0,
  output logic [VA_WIDTH-1:0]         ftq_pred_pc_p0,
  output logic [FTQ_IDX_BITS-1:0]     ftq_pred_idx_p0,

  // ---- 3. queue status, the H1 hold of 4.5 -------------------------
  // The cluster has NO request-ready output, so the FTQ must not
  // present a request while any of these is low.
  input  logic                        tage_pq_not_full,
  input  logic                        ittage_pq_not_full,
  input  logic                        sc_uq_not_full,

  // ---- 4. initial prediction, p1 -----------------------------------
  input  logic                        bpu_pred_val_p1,
  input  logic [FTQ_IDX_BITS-1:0]     bpu_pred_idx_p1,
  input  bp_ftq_slot_t                bpu_pred_slot_p1
                                        [0:NUM_PRED_SLOTS-1],
  input  bp_ras_snapshot_t            bpu_pred_ras_p1,
  input  logic [VA_WIDTH-1:0]         bpu_pred_pft_p1,

  // ---- 9. the checkpoint read, written into the entry --------------
  input  logic [GHIST_PTR_BITS-1:0]   ckpt_ghist_ptr,
  input  logic [PHIST_PTR_BITS-1:0]   ckpt_phist_ptr,

  // ---- 4a. slot correction, p2 and p3 ------------------------------
  input  logic                        bpu_slot_val_p2,
  input  logic [FTQ_IDX_BITS-1:0]     bpu_slot_idx_p2,
  input  bp_ftq_slot_t                bpu_slot_p2 [0:NUM_PRED_SLOTS-1],
  input  logic                        bpu_slot_val_p3,
  input  logic [FTQ_IDX_BITS-1:0]     bpu_slot_idx_p3,
  input  bp_ftq_slot_t                bpu_slot_p3 [0:NUM_PRED_SLOTS-1],

  // ---- 6. redirects, derived at the cluster boundary ---------------
  input  bp_redirect_t                bpu_redir_p2 [0:NUM_PRED_SLOTS-1],
  input  logic [FTQ_IDX_BITS-1:0]     bpu_redir_idx_p2,
  input  bp_redirect_t                bpu_redir_p3 [0:NUM_PRED_SLOTS-1],
  input  logic [FTQ_IDX_BITS-1:0]     bpu_redir_idx_p3,

  // ---- 7.1 and 7.2. prediction metadata ----------------------------
  input  logic                        bpu_meta_val_p2,
  input  logic [FTQ_IDX_BITS-1:0]     bpu_meta_idx_p2,
  input  tage_pred_meta_t             bpu_meta_tage_p2
                                        [0:NUM_PRED_SLOTS-1],
  input  ittage_pred_meta_t           bpu_meta_ittage_p2
                                        [0:NUM_PRED_SLOTS-1],
  input  lp_pred_t                    bpu_meta_lp_p2
                                        [0:NUM_PRED_SLOTS-1],
  input  ftb_pred_meta_t              bpu_meta_ftb_p2
                                        [0:NUM_PRED_SLOTS-1],
  input  logic                        bpu_meta_val_p3,
  input  logic [FTQ_IDX_BITS-1:0]     bpu_meta_idx_p3,
  input  sc_pred_meta_t               bpu_meta_sc_p3
                                        [0:NUM_PRED_SLOTS-1],

  // ---- 9. history rollback, TD-FE-7, BP-102 ------------------------
  output logic                        ftq_rollback_val,
  output logic [FTQ_IDX_BITS-1:0]     ftq_rollback_idx,

  // ---- 8. RAS restore and commit -----------------------------------
  // ras_flush_val / _snapshot are NOT driven. They are declared on
  // bp_cluster, read by nothing, and REDUNDANT with the restore
  // group -- not unfinished (ras_decisions.md 4.4.2, D3 of
  // ftq_backend_interfaces.md 5). Their absence here is the
  // decision, not an omission.
  output logic                        ras_restore_val,
  output bp_ras_snapshot_t            ras_restore_snapshot,
  output logic                        ras_commit_val,
  output bp_br_type_e                 ras_commit_br_type,
  output logic [VA_WIDTH-1:0]         ras_commit_ret_addr,
  output bp_ras_snapshot_t            ras_commit_snapshot,

  // ---- 8. updates, the per-slot channels ---------------------------
  output bp_update_t                  upd [0:NUM_PRED_SLOTS-1],
  output bp_ftq_meta_t                upd_meta [0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]   upd_ubtb_val,
  output logic [NUM_PRED_SLOTS-1:0]   upd_lp_val,
  output logic [NUM_PRED_SLOTS-1:0]   upd_tage_val,
  output logic [NUM_PRED_SLOTS-1:0]   upd_ittage_val,
  output logic [NUM_PRED_SLOTS-1:0]   upd_sc_val,
  input  logic                        tage_upd_rdy_u1,
  input  logic                        ittage_upd_rdy_u1,
  input  logic                        sc_upd_rdy_u1,

  // ---- 8. the FTB update, 14 flat ports, no slot dimension ---------
  output logic                        ftb_upd_valid_u0,
  output logic [VA_WIDTH-1:0]         ftb_upd_pc_u0,
  output logic                        ftb_upd_hit_u0,
  output logic [FTB_WAY_BITS-1:0]     ftb_upd_way_u0,
  output logic                        ftb_upd_is_br_u0,
  output logic                        ftb_upd_br_idx_u0,
  output logic                        ftb_upd_taken_u0,
  output logic [VA_WIDTH-1:0]         ftb_upd_target_u0,
  output logic [FTB_BR_POS_BITS-1:0]  ftb_upd_pos_u0,
  output logic                        ftb_upd_is_jmp_u0,
  output logic [VA_WIDTH-1:0]         ftb_upd_jmp_target_u0,
  output logic                        ftb_upd_is_call_u0,
  output logic                        ftb_upd_is_ret_u0,
  output logic                        ftb_upd_is_jalr_u0,
  output logic [VA_WIDTH-1:0]         ftb_upd_pft_addr_u0,

  // =================================================================
  // IFU boundary, ftq_ifu_interfaces.md
  // =================================================================
  output logic                        ftq_ifu_req_val,
  input  logic                        ftq_ifu_req_rdy,
  output logic [VA_WIDTH-1:0]         ftq_ifu_start_pc,
  output logic [VA_WIDTH-1:0]         ftq_ifu_next_pc,
  output logic [FTQ_IDX_BITS-1:0]     ftq_ifu_idx,
  output logic                        ftq_ifu_taken_val,
  output logic [FTB_BR_POS_BITS-1:0]  ftq_ifu_taken_pos,
  output logic                        ftq_ifu_gen,

  output logic                        ftq_ifu_flush_val,
  output logic [FTQ_IDX_BITS-1:0]     ftq_ifu_flush_idx,

  input  logic                        ifu_ftq_pdwb_val,
  input  logic [FTQ_IDX_BITS-1:0]     ifu_ftq_pdwb_idx,
  input  logic                        ifu_ftq_pdwb_gen,
  input  ftq_pd_info_t                ifu_ftq_pd [0:FTQ_PD_WIDTH-1],
  input  logic [FTQ_PD_WIDTH-1:0]     ifu_ftq_pd_range,
  input  logic                        ifu_ftq_cfi_val,
  input  logic [FTQ_PD_POS_BITS-1:0]  ifu_ftq_cfi_pos,
  input  logic                        ifu_ftq_mis_val,
  input  logic [FTQ_PD_POS_BITS-1:0]  ifu_ftq_mis_pos,
  input  logic [VA_WIDTH-1:0]         ifu_ftq_target,
  input  logic                        ifu_ftq_fault_val,
  input  logic [FTQ_PD_POS_BITS-1:0]  ifu_ftq_fault_pos,

  // =================================================================
  // Backend boundary, ftq_backend_interfaces.md
  // =================================================================
  input  logic [NUM_RESOLVE_PORTS-1:0] bkend_ftq_rsv_val,
  input  ftq_resolve_t                bkend_ftq_rsv
                                        [0:NUM_RESOLVE_PORTS-1],
  output logic [NUM_RESOLVE_PORTS-1:0] ftq_bkend_rsv_rdy,

  input  logic                        bkend_ftq_redir_val,
  input  logic [FTQ_IDX_BITS-1:0]     bkend_ftq_redir_idx,
  input  logic [FTB_BR_POS_BITS-1:0]  bkend_ftq_redir_pos,
  input  logic [VA_WIDTH-1:0]         bkend_ftq_redir_pc,
  input  logic                        bkend_ftq_redir_self,
  input  ftq_redir_cause_e            bkend_ftq_redir_cause,

  // FTQ_PTR_BITS wide: it carries the wrap generation
  // (ftq_backend_interfaces.md 6, widened after BP-106).
  input  logic                        bkend_ftq_commit_val,
  input  logic [FTQ_PTR_BITS-1:0]     bkend_ftq_commit_idx,

  // =================================================================
  // Observation. Not an interface -- the unit testbench and the
  // bound properties read these.
  // =================================================================
  output logic                        ftq_full,
  output logic                        ftq_empty
);

  // -----------------------------------------------------------------
  // Internal nets. Named for the port they carry, prefixed w_.
  // -----------------------------------------------------------------
  logic [FTQ_PTR_BITS-1:0]  w_alloc_ptr;
  logic [FTQ_PTR_BITS-1:0]  w_fetch_ptr;
  logic [FTQ_PTR_BITS-1:0]  w_commit_ptr;
  logic [FTQ_IDX_BITS-1:0]  w_alloc_idx;
  logic [FTQ_IDX_BITS-1:0]  w_fetch_idx;
  logic                     w_fetch_pending;
  logic                     w_ptr_alias_full;

  logic                     w_squash_val;
  logic [FTQ_PTR_BITS-1:0]  w_squash_start;
  logic [FTQ_PTR_BITS-1:0]  w_squash_end;

  logic                     w_commit_step_val;
  logic [FTQ_IDX_BITS-1:0]  w_commit_step_idx;
  logic                     w_walk_active;

  logic                     w_redir_val;
  logic [FTQ_IDX_BITS-1:0]  w_redir_idx;
  logic                     w_redir_self;
  ftq_redir_cause_e         w_redir_cause;
  logic [VA_WIDTH-1:0]      w_pred_pc_p1;
  logic [5:1]               w_arm_win;

  logic                     w_ok_pred_p1;
  logic                     w_ok_slot_p2;
  logic                     w_ok_meta_p2;
  logic                     w_ok_redir_p2;
  logic                     w_ok_slot_p3;
  logic                     w_ok_meta_p3;
  logic                     w_ok_redir_p3;
  logic                     w_alloc_inflight;
  logic [3:0]               w_shadow_val;
  logic [FTQ_PTR_BITS-1:0]  w_shadow_ptr [0:3];

  bp_ftq_entry_t            w_fetch_entry;
  bp_ftq_entry_t            w_redir_entry;
  bp_ftq_entry_t            w_pdwb_entry;
  bp_ftq_entry_t            w_commit_entry;
  logic [FTQ_IDX_BITS-1:0]  w_rsv_rd_idx [0:NUM_RESOLVE_PORTS-1];
  bp_ftq_entry_t            w_rsv_entry  [0:NUM_RESOLVE_PORTS-1];
  bp_ftq_meta_t             w_rsv_meta   [0:NUM_RESOLVE_PORTS-1]
                                         [0:NUM_PRED_SLOTS-1];

  logic                     w_gen_fetch;
  logic                     w_gen_pdwb;
  logic                     w_wb_rcvd_pdwb;
  logic                     w_fault_hold;
  logic [FTQ_DEPTH-1:0]     w_wb_rcvd_vec;
  logic [FTQ_DEPTH-1:0]     w_fault_vec;
  logic [FTQ_DEPTH-1:0]     w_gen_vec;

  logic                     w_wb_set_val;
  logic [FTQ_IDX_BITS-1:0]  w_wb_set_idx;
  logic                     w_fault_set_val;
  logic [FTQ_IDX_BITS-1:0]  w_fault_set_idx;

  logic                     w_pd_wr_val;
  logic [FTQ_IDX_BITS-1:0]  w_pd_wr_idx;
  logic [TRX_SLOT_BITS-1:0] w_pd_wr_sel;
  bp_ftq_slot_t             w_pd_wr_slot;
  logic                     w_pd_wr_kill;
  logic                     w_pd_redir_val;
  logic [FTQ_IDX_BITS-1:0]  w_pd_redir_idx;
  logic [VA_WIDTH-1:0]      w_pd_redir_pc;
  logic                     w_wb_accept;
  logic                     w_wb_drop_gen;

  logic [NUM_RESOLVE_PORTS-1:0] w_ftb_upd_val;
  ftb_upd_t                 w_ftb_upd [0:NUM_RESOLVE_PORTS-1];
  logic [NUM_RESOLVE_PORTS-1:0] w_ftb_upd_hit;
  logic [NUM_RESOLVE_PORTS-1:0] w_ftb_upd_mispred;
  logic [NUM_RESOLVE_PORTS-1:0] w_ftb_sched_rdy;
  logic [NUM_RESOLVE_PORTS-1:0] w_rsv_nomap;
  logic [NUM_RESOLVE_PORTS-1:0] w_rsv_drop_sq;
  logic [NUM_RESOLVE_PORTS-1:0] w_rsv_type_dis;
  logic [NUM_RESOLVE_PORTS-1:0] w_rsv_accept;
  logic [TRX_SLOT_BITS-1:0] w_rsv_slot [0:NUM_RESOLVE_PORTS-1];

  logic                     w_sched_from_skid;
  logic                     w_sched_skid_val;
  logic                     w_sched_skid_wr;
  logic                     w_sched_skid_issue;
  logic                     w_sched_drop_val;
  logic                     w_sched_drop_high;
  logic [$clog2(NUM_RESOLVE_PORTS+2)-1:0] w_sched_n_acc;
  logic [$clog2(NUM_RESOLVE_PORTS+2)-1:0] w_sched_n_pend;
  logic                     w_sched_any_high;

  // -----------------------------------------------------------------
  // ftq_ptr. alloc_ptr and fetch_ptr, 5.1 5.2 5.5.
  // -----------------------------------------------------------------
  // alloc_req_rdy is tied high. The acceptance of 5.2 is H1 clear,
  // and H1 is already inside ftq_pred_val_p0: ftq_npc forms the hold
  // from the three queue-status inputs and deasserts the request.
  // Presenting the request as both val and rdy here is the same
  // condition stated once, not twice.
  ftq_ptr u_ptr (
    .clk            (clk),
    .rstn           (rstn),
    .commit_ptr     (w_commit_ptr),
    .alloc_req_val  (ftq_pred_val_p0),
    .alloc_req_rdy  (1'b1),
    .ifu_req_val    (ftq_ifu_req_val),
    .ifu_req_rdy    (ftq_ifu_req_rdy),
    .alloc_inflight (w_alloc_inflight),
    .redir_val      (w_redir_val),
    .redir_idx      (w_redir_idx),
    .redir_self     (w_redir_self),
    .redir_cause    (w_redir_cause),
    .alloc_ptr      (w_alloc_ptr),
    .fetch_ptr      (w_fetch_ptr),
    .ftq_full       (ftq_full),
    .ftq_empty      (ftq_empty),
    .fetch_pending  (w_fetch_pending),
    .ptr_alias_full (w_ptr_alias_full),
    .squash_val     (w_squash_val),
    .squash_start   (w_squash_start),
    .squash_end     (w_squash_end),
    .alloc_idx      (w_alloc_idx),
    .fetch_idx      (w_fetch_idx)
  );

  assign ftq_pred_idx_p0 = w_alloc_idx;

  // -----------------------------------------------------------------
  // ftq_commit. commit_ptr and the walk, 5.3 5.4.
  // -----------------------------------------------------------------
  ftq_commit u_commit (
    .clk              (clk),
    .rstn             (rstn),
    .alloc_ptr        (w_alloc_ptr),
    .bkend_commit_val (bkend_ftq_commit_val),
    .bkend_commit_idx (bkend_ftq_commit_idx),
    .redir_val        (w_redir_val),
    .redir_cause      (w_redir_cause),
    .commit_ptr       (w_commit_ptr),
    .commit_step_val  (w_commit_step_val),
    .commit_step_idx  (w_commit_step_idx),
    .walk_active      (w_walk_active)
  );

  // -----------------------------------------------------------------
  // ftq_npc. The next-PC register and the redirect arbitration, 4.
  // -----------------------------------------------------------------
  ftq_npc u_npc (
    .clk                (clk),
    .rstn               (rstn),
    .bkend_redir_val    (bkend_ftq_redir_val),
    .bkend_redir_idx    (bkend_ftq_redir_idx),
    .bkend_redir_pc     (bkend_ftq_redir_pc),
    .bkend_redir_self   (bkend_ftq_redir_self),
    .bkend_redir_cause  (bkend_ftq_redir_cause),
    .pd_redir_val       (w_pd_redir_val),
    .pd_redir_idx       (w_pd_redir_idx),
    .pd_redir_pc        (w_pd_redir_pc),
    .p3_redir_val       (w_ok_redir_p3),
    .p3_redir_idx       (bpu_redir_idx_p3),
    .p3_redir           (bpu_redir_p3),
    .p2_redir_val       (w_ok_redir_p2),
    .p2_redir_idx       (bpu_redir_idx_p2),
    .p2_redir           (bpu_redir_p2),
    .p1_val             (w_ok_pred_p1),
    .p1_slot            (bpu_pred_slot_p1),
    .p1_pft_addr        (bpu_pred_pft_p1),
    .tage_pq_not_full   (tage_pq_not_full),
    .ittage_pq_not_full (ittage_pq_not_full),
    .sc_uq_not_full     (sc_uq_not_full),
    .h2_ftq_full        (ftq_full),
    .r1_fault_hold      (w_fault_hold),
    .ftq_pred_val_p0    (ftq_pred_val_p0),
    .ftq_pred_pc_p0     (ftq_pred_pc_p0),
    .pred_pc_p1         (w_pred_pc_p1),
    .redir_val          (w_redir_val),
    .redir_idx          (w_redir_idx),
    .redir_self         (w_redir_self),
    .redir_cause        (w_redir_cause),
    .rollback_val       (ftq_rollback_val),
    .rollback_idx       (ftq_rollback_idx),
    .arm_win            (w_arm_win)
  );

  // D1 and D2 fire together and from the same index: the history
  // rollback and the RAS restore both come from the entry being
  // corrected (backend_interfaces 5). One derivation, two consumers.
  assign ras_restore_val = ftq_rollback_val;

  // -----------------------------------------------------------------
  // ftq_shadow. The four-deep response shadow, 5.6.
  // -----------------------------------------------------------------
  ftq_shadow u_shadow (
    .clk            (clk),
    .rstn           (rstn),
    .req_val        (ftq_pred_val_p0),
    .req_ptr        (w_alloc_ptr),
    .squash_val     (w_squash_val),
    .squash_start   (w_squash_start),
    .squash_end     (w_squash_end),
    .gv_pred_p1     (bpu_pred_val_p1),
    .idx_pred_p1    (bpu_pred_idx_p1),
    .gv_slot_p2     (bpu_slot_val_p2),
    .idx_slot_p2    (bpu_slot_idx_p2),
    .gv_meta_p2     (bpu_meta_val_p2),
    .idx_meta_p2    (bpu_meta_idx_p2),
    .idx_redir_p2   (bpu_redir_idx_p2),
    .gv_slot_p3     (bpu_slot_val_p3),
    .idx_slot_p3    (bpu_slot_idx_p3),
    .gv_meta_p3     (bpu_meta_val_p3),
    .idx_meta_p3    (bpu_meta_idx_p3),
    .idx_redir_p3   (bpu_redir_idx_p3),
    .ok_pred_p1     (w_ok_pred_p1),
    .ok_slot_p2     (w_ok_slot_p2),
    .ok_meta_p2     (w_ok_meta_p2),
    .ok_redir_p2    (w_ok_redir_p2),
    .ok_slot_p3     (w_ok_slot_p3),
    .ok_meta_p3     (w_ok_meta_p3),
    .ok_redir_p3    (w_ok_redir_p3),
    .alloc_inflight (w_alloc_inflight),
    .shadow_val     (w_shadow_val),
    .shadow_ptr     (w_shadow_ptr)
  );

  // -----------------------------------------------------------------
  // ftq_entry. The fast-path array, 1 and 2.
  // -----------------------------------------------------------------
  // The redirect read index is the ROLLBACK index, not the raw
  // redirect index: 3.2 names the entry whose END-of-block pointer
  // state is restored, and on _self set that is the one before the
  // naming entry. ftq_npc makes that derivation and this port
  // consumes it, so the RAS snapshot and the history rollback come
  // from the same entry by construction.
  ftq_entry u_entry (
    .clk                 (clk),
    .rstn                (rstn),
    .alloc_wr_val        (w_ok_pred_p1),
    .alloc_wr_idx        (bpu_pred_idx_p1),
    .alloc_wr_pc         (w_pred_pc_p1),
    .alloc_wr_pft_addr   (bpu_pred_pft_p1),
    .alloc_wr_ras        (bpu_pred_ras_p1),
    .alloc_wr_ghist_ptr  (ckpt_ghist_ptr),
    .alloc_wr_phist_ptr  (ckpt_phist_ptr),
    .alloc_wr_slot       (bpu_pred_slot_p1),
    .p2_wr_val           (w_ok_slot_p2),
    .p2_wr_idx           (bpu_slot_idx_p2),
    .p2_wr_slot          (bpu_slot_p2),
    .p3_wr_val           (w_ok_slot_p3),
    .p3_wr_idx           (bpu_slot_idx_p3),
    .p3_wr_slot          (bpu_slot_p3),
    .pd_wr_val           (w_pd_wr_val),
    .pd_wr_idx           (w_pd_wr_idx),
    .pd_wr_sel           (w_pd_wr_sel),
    .pd_wr_slot          (w_pd_wr_slot),
    .pd_wr_kill          (w_pd_wr_kill),
    .fetch_rd_idx        (w_fetch_idx),
    .fetch_rd_entry      (w_fetch_entry),
    .redir_rd_idx        (ftq_rollback_idx),
    .redir_rd_entry      (w_redir_entry),
    .restore_snapshot    (ras_restore_snapshot),
    .pdwb_rd_idx         (ifu_ftq_pdwb_idx),
    .pdwb_rd_entry       (w_pdwb_entry),
    .commit_rd_idx       (w_commit_step_idx),
    .commit_rd_entry     (w_commit_entry),
    .commit_step_val     (w_commit_step_val),
    .ras_commit_val      (ras_commit_val),
    .ras_commit_br_type  (ras_commit_br_type),
    .ras_commit_ret_addr (ras_commit_ret_addr),
    .ras_commit_snapshot (ras_commit_snapshot),
    .rsv_rd_idx          (w_rsv_rd_idx),
    .rsv_rd_entry        (w_rsv_entry)
  );

  // -----------------------------------------------------------------
  // ftq_meta. The slow-path array, 3.
  // -----------------------------------------------------------------
  ftq_meta u_meta (
    .clk          (clk),
    .rstn         (rstn),
    .p2_wr_val    (w_ok_meta_p2),
    .p2_wr_idx    (bpu_meta_idx_p2),
    .p2_wr_tage   (bpu_meta_tage_p2),
    .p2_wr_ittage (bpu_meta_ittage_p2),
    .p2_wr_lp     (bpu_meta_lp_p2),
    .p2_wr_ftb    (bpu_meta_ftb_p2),
    .p3_wr_val    (w_ok_meta_p3),
    .p3_wr_idx    (bpu_meta_idx_p3),
    .p3_wr_sc     (bpu_meta_sc_p3),
    .rd_idx       (w_rsv_rd_idx),
    .rd_meta      (w_rsv_meta)
  );

  // -----------------------------------------------------------------
  // ftq_status. wb_rcvd, fault and gen, entry_formats 4.
  // -----------------------------------------------------------------
  // Allocation is the p1 write, not the p0 index: W1 says the bits
  // clear and gen toggles when the entry is ALLOCATED AT p1, which
  // is the same event that writes the entry content.
  ftq_status u_status (
    .clk           (clk),
    .rstn          (rstn),
    .commit_ptr    (w_commit_ptr),
    .alloc_ptr     (w_alloc_ptr),
    .alloc_val     (w_ok_pred_p1),
    .alloc_idx     (bpu_pred_idx_p1),
    .wb_set_val    (w_wb_set_val),
    .wb_set_idx    (w_wb_set_idx),
    .fault_set_val (w_fault_set_val),
    .fault_set_idx (w_fault_set_idx),
    .squash_val    (w_squash_val),
    .squash_start  (w_squash_start),
    .squash_end    (w_squash_end),
    .gen_rd_idx    (w_fetch_idx),
    .gen_rd_val    (w_gen_fetch),
    .gen_chk_idx   (ifu_ftq_pdwb_idx),
    .gen_chk_val   (w_gen_pdwb),
    .wb_rd_idx     (ifu_ftq_pdwb_idx),
    .wb_rd_val     (w_wb_rcvd_pdwb),
    .fault_hold    (w_fault_hold),
    .wb_rcvd       (w_wb_rcvd_vec),
    .fault         (w_fault_vec),
    .gen           (w_gen_vec)
  );

  // -----------------------------------------------------------------
  // ftq_ifu. The IFU boundary.
  // -----------------------------------------------------------------
  ftq_ifu u_ifu (
    .clk               (clk),
    .rstn              (rstn),
    .fetch_idx         (w_fetch_idx),
    .fetch_pending     (w_fetch_pending),
    .fetch_entry       (w_fetch_entry),
    .gen_fetch         (w_gen_fetch),
    .gen_pdwb          (w_gen_pdwb),
    .wb_rcvd_pdwb      (w_wb_rcvd_pdwb),
    .pdwb_entry        (w_pdwb_entry),
    .redir_val         (w_redir_val),
    .redir_idx         (w_redir_idx),
    .redir_self        (w_redir_self),
    .redir_cause       (w_redir_cause),
    .ftq_ifu_req_val   (ftq_ifu_req_val),
    .ftq_ifu_req_rdy   (ftq_ifu_req_rdy),
    .ftq_ifu_start_pc  (ftq_ifu_start_pc),
    .ftq_ifu_next_pc   (ftq_ifu_next_pc),
    .ftq_ifu_idx       (ftq_ifu_idx),
    .ftq_ifu_taken_val (ftq_ifu_taken_val),
    .ftq_ifu_taken_pos (ftq_ifu_taken_pos),
    .ftq_ifu_gen       (ftq_ifu_gen),
    .ftq_ifu_flush_val (ftq_ifu_flush_val),
    .ftq_ifu_flush_idx (ftq_ifu_flush_idx),
    .ifu_ftq_pdwb_val  (ifu_ftq_pdwb_val),
    .ifu_ftq_pdwb_idx  (ifu_ftq_pdwb_idx),
    .ifu_ftq_pdwb_gen  (ifu_ftq_pdwb_gen),
    .ifu_ftq_pd        (ifu_ftq_pd),
    .ifu_ftq_pd_range  (ifu_ftq_pd_range),
    .ifu_ftq_cfi_val   (ifu_ftq_cfi_val),
    .ifu_ftq_cfi_pos   (ifu_ftq_cfi_pos),
    .ifu_ftq_mis_val   (ifu_ftq_mis_val),
    .ifu_ftq_mis_pos   (ifu_ftq_mis_pos),
    .ifu_ftq_target    (ifu_ftq_target),
    .ifu_ftq_fault_val (ifu_ftq_fault_val),
    .ifu_ftq_fault_pos (ifu_ftq_fault_pos),
    .wb_set_val        (w_wb_set_val),
    .wb_set_idx        (w_wb_set_idx),
    .fault_set_val     (w_fault_set_val),
    .fault_set_idx     (w_fault_set_idx),
    .pd_wr_val         (w_pd_wr_val),
    .pd_wr_idx         (w_pd_wr_idx),
    .pd_wr_sel         (w_pd_wr_sel),
    .pd_wr_slot        (w_pd_wr_slot),
    .pd_wr_kill        (w_pd_wr_kill),
    .pd_redir_val      (w_pd_redir_val),
    .pd_redir_idx      (w_pd_redir_idx),
    .pd_redir_pc       (w_pd_redir_pc),
    .wb_accept         (w_wb_accept),
    .wb_drop_gen       (w_wb_drop_gen)
  );

  // -----------------------------------------------------------------
  // ftq_resolve. Resolution intake and update fan-out.
  // -----------------------------------------------------------------
  ftq_resolve u_resolve (
    .clk               (clk),
    .rstn              (rstn),
    .commit_ptr        (w_commit_ptr),
    .alloc_ptr         (w_alloc_ptr),
    .bkend_rsv_val     (bkend_ftq_rsv_val),
    .bkend_rsv         (bkend_ftq_rsv),
    .ftq_bkend_rsv_rdy (ftq_bkend_rsv_rdy),
    .rsv_rd_idx        (w_rsv_rd_idx),
    .rsv_entry         (w_rsv_entry),
    .rsv_meta          (w_rsv_meta),
    .ftb_sched_rdy     (w_ftb_sched_rdy),
    .tage_upd_rdy      (tage_upd_rdy_u1),
    .ittage_upd_rdy    (ittage_upd_rdy_u1),
    .sc_upd_rdy        (sc_upd_rdy_u1),
    .upd               (upd),
    .upd_ubtb_val      (upd_ubtb_val),
    .upd_lp_val        (upd_lp_val),
    .upd_tage_val      (upd_tage_val),
    .upd_ittage_val    (upd_ittage_val),
    .upd_sc_val        (upd_sc_val),
    .upd_meta          (upd_meta),
    .ftb_upd_val       (w_ftb_upd_val),
    .ftb_upd           (w_ftb_upd),
    .ftb_upd_hit       (w_ftb_upd_hit),
    .ftb_upd_mispred   (w_ftb_upd_mispred),
    .rsv_nomap         (w_rsv_nomap),
    .rsv_drop_sq       (w_rsv_drop_sq),
    .rsv_type_dis      (w_rsv_type_dis),
    .rsv_accept        (w_rsv_accept),
    .rsv_slot          (w_rsv_slot)
  );

  // -----------------------------------------------------------------
  // ftq_ftb_sched. The FTB update scheduler, 5.7. BUILT BY BP-100
  // and not modified by BP-107.
  // -----------------------------------------------------------------
  ftq_ftb_sched #(
    .NUM_UPD_CHAN (NUM_RESOLVE_PORTS)
  ) u_ftb_sched (
    .clk                   (clk),
    .rstn                  (rstn),
    .upd_val               (w_ftb_upd_val),
    .upd                   (w_ftb_upd),
    .upd_hit               (w_ftb_upd_hit),
    .upd_mispred           (w_ftb_upd_mispred),
    .upd_rdy               (w_ftb_sched_rdy),
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
    .ftb_upd_from_skid     (w_sched_from_skid),
    .skid_val              (w_sched_skid_val),
    .skid_wr               (w_sched_skid_wr),
    .skid_issue            (w_sched_skid_issue),
    .drop_val              (w_sched_drop_val),
    .drop_is_high          (w_sched_drop_high),
    .n_acc_ftb             (w_sched_n_acc),
    .n_pend_ftb            (w_sched_n_pend),
    .any_pend_high         (w_sched_any_high)
  );

  // -----------------------------------------------------------------
  // Nets read by no port of this module.
  // -----------------------------------------------------------------
  // Every one is a leaf OBSERVATION output, published so the
  // properties bound to that leaf read its port list and make no
  // hierarchical reference (TD#109). They are terminated here rather
  // than exported: the unit testbench reads them through the
  // instance, and exporting them would put diagnostic state on the
  // three specified interfaces.
  //
  // bkend_ftq_redir_pos is a BACKEND port with no FTQ consumer. It
  // locates the boundary within the entry, and every FTQ response to
  // a redirect -- rewind, status clear, restore, flush -- acts on
  // the ENTRY, not on a position inside it. Section 5 declares it;
  // nothing in D1 through D5 reads it.
  logic w_unused;
  assign w_unused = w_ptr_alias_full | w_walk_active | |w_arm_win |
                    |w_shadow_val    | w_wb_accept   | w_wb_drop_gen |
                    |w_wb_rcvd_vec   | |w_fault_vec  | |w_gen_vec |
                    |w_rsv_nomap     | |w_rsv_drop_sq |
                    |w_rsv_type_dis  | |w_rsv_accept |
                    w_sched_from_skid | w_sched_skid_val |
                    w_sched_skid_wr   | w_sched_skid_issue |
                    w_sched_drop_val  | w_sched_drop_high |
                    |w_sched_n_acc    | |w_sched_n_pend |
                    w_sched_any_high  | |w_redir_entry |
                    |w_commit_entry   | |bkend_ftq_redir_pos |
                    |w_shadow_ptr[0]  | |w_rsv_slot[0];

endmodule : ftq
