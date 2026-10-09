// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Front-end top (BP-118). fe_decisions.md section 15, FE-15 to FE-21.
//
// PURELY STRUCTURAL (FE-15): instances and wires. No state, no
// always block, and no expression on any path. The same rule
// ftq_decisions.md 7 applies to ftq.sv. Where wiring two units
// would have needed a gate, a width change or a conversion, the
// connection is NOT made here and the disagreement is recorded in
// the BP-118 Results Capture; see "NOT CONNECTED" below.
//
// INSTANCES (FE-15, FE-16, FE-21):
//   u_bpu    bp_cluster       the predictors
//   u_ftq    ftq              the fetch target queue
//   u_ifu    ifu              translation and fetch pipelines
//   u_l1i    l1i              the cachegen emission under
//                             tools/cachegen/output/l1i, used as
//                             emitted, a SIBLING of the IFU (L1I-2)
//   u_itlb   itlb             with its PMP/PMA checker inside
//                             (MMU-10a)
//   u_ibuf   ibuf             the instruction buffer
//   u_dec    instr_decoder    decode, on the ibuf read port
//
// THE BOUNDARY (FE-17, FE-20). Inward and outward groups:
//   instruction  the L1I's l2-side link, emitted as interface 'mem'
//                on link tl_l1i_l2 (FE-17 and FE-21 call it up_i).
//                Prefixed l1i_mem_ here; a testbench answers it.
//   translation  the ITLB to the shared L2 TLB, itlb_l2t_* and
//                l2t_itlb_*
//   uncached     IFU-21. NOT PRESENT: the IFU declares no uncached
//                port (TD#135), so there is nothing to bring out
//   backend      decode's output to rename, qualified by the ibuf
//                read ready dec_ibuf_rdy (FE-20), and the FTQ's
//                resolution, redirect and commit groups
//                (ftq_backend_interfaces.md). The backend redirect
//                valid also clears the ibuf (IBUF-13), the one net
//                with two consumers here
//   csr          V, privilege, satp / vsatp / hgatp fields, pmpcfg
//                and pmpaddr, into the ITLB (FE-20, ITLB-17)
//   config       the cluster's configuration inputs, and decode's
//                extension enables (FE-20; see Results Capture for
//                the ones FE-20 does not list)
//   maintenance  the ITLB invalidate port (FE-20, ITLB-14)
//
// THE UPDATE PATHS ARE ALL CONNECTED (BP-119, TD#151, TD#150). The
// FTQ forms the per-predictor payloads (ftq_upd_conv inside ftq.sv)
// and presents the section 8 ports name for name: ubtb_upd_u0,
// lp_upd_*, tage_upd_*, ittage_upd_*, sc_upd_*. The cluster's per-slot
// queue readies (tage_upd_rdy, ittage_upd_rdy, sc_upd_rdy) go to the
// FTQ unchanged; the FTQ ANDs them per predictor. sc_enable reaches
// both the cluster and the FTQ (the SC-disabled rule). The FTB update
// (14 flat ports) and the RAS commit group are wired as before. Until
// BP-119 only the FTB and the RAS trained here: the five inputs were
// held inactive, the FTQ's bp_update_t outputs ended on wires, and its
// three scalar readies were held high.
//
// NOT CONNECTED, AND WHY (each is a disagreement between units):
//   - the cluster's tage_upd_rdy_u1, ittage_upd_rdy_u1 and
//     sc_upd_rdy_u1 end on wires. Each is the registered update valid
//     ("update applied", tage_interfaces.md), not an accept ready.
//   - ras_flush_val and ras_flush_snapshot. Redundant with the
//     restore group and read by nothing (ras_decisions.md 4.4.2);
//     held inactive. ftb_flush_px is held inactive for the same
//     reason (FE-14).
// A constant is not a decision: no input above is derived from
// another signal.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;
import decode_pkg::*;

module fe_top (
  input  logic                        clk,
  input  logic                        rstn,

  // =================================================================
  // backend: decode to rename (FE-17, FE-20)
  // =================================================================
  output decode_pkt_t     [SLOTS-1:0] decode_bundle,
  output vec_decode_pkt_t [SLOTS-1:0] vec_decode_bundle,
  output logic            [SLOTS-1:0] is_vector,
  output ifu_pd_pkt_t                 pd_out [0:SLOTS-1],
  output logic            [SLOTS-1:0] vtype_hazard,
  input  logic                        dec_ibuf_rdy,

  // =================================================================
  // backend: the FTQ groups, ftq_backend_interfaces.md 4 to 6
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
  // The resolved direction of the redirecting branch (BP-121, the
  // corrected history rollback).
  input  logic                        bkend_ftq_redir_taken,
  input  logic                        bkend_ftq_commit_val,
  input  logic [FTQ_PTR_BITS-1:0]     bkend_ftq_commit_idx,

  // =================================================================
  // translation: ITLB to the shared L2 TLB, itlb_l2tlb_interfaces.md
  // =================================================================
  output logic                        itlb_l2t_req_val,
  input  logic                        itlb_l2t_req_rdy,
  output logic [VA_WIDTH-13:0]        itlb_l2t_vpn,
  output logic [ASID_WIDTH-1:0]       itlb_l2t_asid,
  output logic [VMID_WIDTH-1:0]       itlb_l2t_vmid,
  output logic                        itlb_l2t_v,
  output logic [1:0]                  itlb_l2t_tag,
  input  logic                        l2t_itlb_rsp_val,
  input  logic [1:0]                  l2t_itlb_tag,
  input  logic [1:0]                  l2t_itlb_status,
  input  logic [PPN_WIDTH-1:0]        l2t_itlb_ppn,
  input  logic [2:0]                  l2t_itlb_size,   // IL-7
  input  logic [PERM_WIDTH-1:0]       l2t_itlb_perm,
  input  logic [1:0]                  l2t_itlb_pbmt,
  input  logic [CAUSE_WIDTH-1:0]      l2t_itlb_cause,
  input  logic [GPA_WIDTH-1:0]        l2t_itlb_gpa,

  // =================================================================
  // instruction: the L1I's l2-side link, as emitted (FE-21)
  // =================================================================
  output logic                        l1i_mem_a_valid,
  input  logic                        l1i_mem_a_ready,
  output logic [2:0]                  l1i_mem_a_opcode,
  output logic [2:0]                  l1i_mem_a_param,
  output logic [2:0]                  l1i_mem_a_size,
  output logic [3:0]                  l1i_mem_a_source,
  output logic [PA_WIDTH-1:0]         l1i_mem_a_address,
  output logic [31:0]                 l1i_mem_a_mask,
  output logic [255:0]                l1i_mem_a_data,
  output logic                        l1i_mem_a_corrupt,
  input  logic                        l1i_mem_d_valid,
  output logic                        l1i_mem_d_ready,
  input  logic [2:0]                  l1i_mem_d_opcode,
  input  logic [2:0]                  l1i_mem_d_param,
  input  logic [2:0]                  l1i_mem_d_size,
  input  logic [3:0]                  l1i_mem_d_source,
  input  logic [1:0]                  l1i_mem_d_sink,
  input  logic                        l1i_mem_d_denied,
  input  logic [255:0]                l1i_mem_d_data,
  input  logic                        l1i_mem_d_corrupt,

  // =================================================================
  // csr (FE-20, ITLB-17, MMU-11a)
  // =================================================================
  input  logic                        csr_itlb_v,
  input  logic [1:0]                  csr_itlb_priv,
  input  logic [3:0]                  csr_itlb_satp_mode,
  input  logic [ASID_WIDTH-1:0]       csr_itlb_satp_asid,
  input  logic [3:0]                  csr_itlb_vsatp_mode,
  input  logic [ASID_WIDTH-1:0]       csr_itlb_vsatp_asid,
  input  logic [3:0]                  csr_itlb_hgatp_mode,
  input  logic [VMID_WIDTH-1:0]       csr_itlb_hgatp_vmid,
  input  logic [15:0][7:0]            csr_itlb_pmpcfg,
  input  logic [15:0][PA_WIDTH-3:0]   csr_itlb_pmpaddr,

  // =================================================================
  // config (FE-20)
  // =================================================================
  input  logic                        sc_enable,
  input  logic                        ftb_fastpath_en,
  input  logic                        tage_enable_aging,
  input  logic [31:0]                 tage_aging_interval,
  input  logic                        ittage_enable_aging,
  input  logic [31:0]                 ittage_aging_interval,
  // decode_pkg ext_enable_t. No C or Zcb enable since BP-120 (TD#155,
  // DCD-20): two bits narrower.
  input  ext_enable_t                 ext_enable,

  // =================================================================
  // maintenance: the ITLB invalidate port (FE-20, ITLB-14)
  // =================================================================
  input  logic                        bkend_itlb_inv_val,
  input  logic [1:0]                  bkend_itlb_inv_op,
  input  logic                        bkend_itlb_inv_rs1_nz,
  input  logic                        bkend_itlb_inv_rs2_nz,
  input  logic [VA_WIDTH-13:0]        bkend_itlb_inv_vpn,
  input  logic [ASID_WIDTH-1:0]       bkend_itlb_inv_asid,
  input  logic [VMID_WIDTH-1:0]       bkend_itlb_inv_vmid,

  // =================================================================
  // observation: the FTQ's own, passed through
  // =================================================================
  output logic                        ftq_full,
  output logic                        ftq_empty
);

  // -----------------------------------------------------------------
  // BPU <-> FTQ, ftq_bpu_interfaces.md 3 to 9
  // -----------------------------------------------------------------
  logic                       ftq_pred_val_p0;
  logic [VA_WIDTH-1:0]        ftq_pred_pc_p0;
  logic [FTQ_IDX_BITS-1:0]    ftq_pred_idx_p0;
  logic                       bpu_pred_val_p1;
  logic [FTQ_IDX_BITS-1:0]    bpu_pred_idx_p1;
  bp_ftq_slot_t               bpu_pred_slot_p1 [0:NUM_PRED_SLOTS-1];
  bp_ras_snapshot_t           bpu_pred_ras_p1;
  logic [VA_WIDTH-1:0]        bpu_pred_pft_p1;
  bp_redirect_t               bpu_redir_p2 [0:NUM_PRED_SLOTS-1];
  logic [FTQ_IDX_BITS-1:0]    bpu_redir_idx_p2;
  bp_redirect_t               bpu_redir_p3 [0:NUM_PRED_SLOTS-1];
  logic [FTQ_IDX_BITS-1:0]    bpu_redir_idx_p3;
  logic                       bpu_slot_val_p2;
  logic [FTQ_IDX_BITS-1:0]    bpu_slot_idx_p2;
  bp_ftq_slot_t               bpu_slot_p2 [0:NUM_PRED_SLOTS-1];
  logic                       bpu_slot_val_p3;
  logic [FTQ_IDX_BITS-1:0]    bpu_slot_idx_p3;
  bp_ftq_slot_t               bpu_slot_p3 [0:NUM_PRED_SLOTS-1];
  logic                       bpu_blk_val_p2;
  logic [FTQ_IDX_BITS-1:0]    bpu_blk_idx_p2;
  bp_ras_snapshot_t           bpu_blk_ras_p2;
  logic [VA_WIDTH-1:0]        bpu_blk_pft_p2;
  logic                       bpu_meta_val_p2;
  logic [FTQ_IDX_BITS-1:0]    bpu_meta_idx_p2;
  tage_pred_meta_t            bpu_meta_tage_p2   [0:NUM_PRED_SLOTS-1];
  ittage_pred_meta_t          bpu_meta_ittage_p2 [0:NUM_PRED_SLOTS-1];
  lp_pred_t                   bpu_meta_lp_p2     [0:NUM_PRED_SLOTS-1];
  ftb_pred_meta_t             bpu_meta_ftb_p2    [0:NUM_PRED_SLOTS-1];
  logic                       bpu_meta_val_p3;
  logic [FTQ_IDX_BITS-1:0]    bpu_meta_idx_p3;
  sc_pred_meta_t              bpu_meta_sc_p3     [0:NUM_PRED_SLOTS-1];
  logic                       ftq_rollback_val;
  logic [FTQ_IDX_BITS-1:0]    ftq_rollback_idx;
  logic                       ftq_rollback_corr;
  logic [1:0]                 ftq_rollback_n;
  logic [1:0]                 ftq_rollback_tkn;
  logic [1:0]                 ftq_rollback_pbit;
  logic [NUM_PRED_SLOTS-1:0]  ftq_rollback_slot_ex;   // BP-122
  logic [NUM_PRED_SLOTS-1:0]  ftq_rollback_slot_tkn;  // BP-122
  logic [GHIST_PTR_BITS-1:0]  ckpt_ghist_ptr;
  logic [PHIST_PTR_BITS-1:0]  ckpt_phist_ptr;
  logic                       ras_restore_val;
  bp_ras_snapshot_t           ras_restore_snapshot;
  logic                       ras_commit_val;
  bp_br_type_e                ras_commit_br_type;
  logic [VA_WIDTH-1:0]        ras_commit_ret_addr;
  bp_ras_snapshot_t           ras_commit_snapshot;
  logic                       tage_pq_not_full;
  logic                       ittage_pq_not_full;
  logic                       sc_uq_not_full;

  // The FTB update, 14 flat ports plus the valid, name for name.
  logic                       ftb_upd_valid_u0;
  logic [VA_WIDTH-1:0]        ftb_upd_pc_u0;
  logic                       ftb_upd_hit_u0;
  logic [FTB_WAY_BITS-1:0]    ftb_upd_way_u0;
  logic                       ftb_upd_is_br_u0;
  logic                       ftb_upd_br_idx_u0;
  logic                       ftb_upd_taken_u0;
  logic [VA_WIDTH-1:0]        ftb_upd_target_u0;
  logic [FTB_BR_POS_BITS-1:0] ftb_upd_pos_u0;
  logic                       ftb_upd_is_jmp_u0;
  logic [VA_WIDTH-1:0]        ftb_upd_jmp_target_u0;
  logic                       ftb_upd_is_call_u0;
  logic                       ftb_upd_is_ret_u0;
  logic                       ftb_upd_is_jalr_u0;
  logic                       ftb_upd_jmp_rvc_u0;
  logic [VA_WIDTH-1:0]        ftb_upd_pft_addr_u0;

  // The per-predictor update channels, FTQ -> BPU, section 8.
  ubtb_upd_t [NUM_PRED_SLOTS-1:0] ubtb_upd_u0;
  logic [NUM_PRED_SLOTS-1:0]  lp_upd_valid_p0;
  lp_upd_t                    lp_upd_p0         [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]  tage_upd_val_u0;
  tage_upd_inp_t              tage_upd_inp_u0   [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]  ittage_upd_val_u0;
  ittage_upd_inp_t            ittage_upd_inp_u0 [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]  sc_upd_val_u0;
  sc_upd_inp_t                sc_upd_inp_u0     [0:NUM_PRED_SLOTS-1];

  // The cluster's unread outputs, and its per-slot queue readies.
  logic [GHIST_PTR_BITS-1:0]  bpu_ghist_ptr;
  logic [PHIST_PTR_BITS-1:0]  bpu_phist_ptr;
  logic [GHR_WIDTH-1:0]       bpu_ghr_buf;
  logic [PHR_WIDTH-1:0]       bpu_phr_buf;
  logic                       bpu_tage_rdy;
  logic                       bpu_ittage_rdy;
  logic                       bpu_sc_ready;
  logic [NUM_PRED_SLOTS-1:0]  bpu_tage_upd_rdy;
  logic [NUM_PRED_SLOTS-1:0]  bpu_tage_upd_rdy_u1;
  logic [NUM_PRED_SLOTS-1:0]  bpu_ittage_upd_rdy;
  logic [NUM_PRED_SLOTS-1:0]  bpu_ittage_upd_rdy_u1;
  logic [NUM_PRED_SLOTS-1:0]  bpu_sc_upd_rdy;
  logic [NUM_PRED_SLOTS-1:0]  bpu_sc_upd_rdy_u1;

  // -----------------------------------------------------------------
  // FTQ <-> IFU, ftq_ifu_interfaces.md
  // -----------------------------------------------------------------
  logic                       ftq_ifu_xlate_val;
  logic                       ftq_ifu_xlate_rdy;
  logic [VA_WIDTH-1:0]        ftq_ifu_xlate_pc;
  logic [FTQ_IDX_BITS-1:0]    ftq_ifu_xlate_idx;
  logic                       ftq_ifu_req_val;
  logic                       ftq_ifu_req_rdy;
  logic [VA_WIDTH-1:0]        ftq_ifu_start_pc;
  logic [VA_WIDTH-1:0]        ftq_ifu_next_pc;
  logic [FTQ_IDX_BITS-1:0]    ftq_ifu_idx;
  logic                       ftq_ifu_taken_val;
  logic [FTB_BR_POS_BITS-1:0] ftq_ifu_taken_pos;
  logic                       ftq_ifu_gen;
  logic [FTQ_IDX_BITS-1:0]    ftq_ifu_commit_ptr;
  logic                       ftq_ifu_flush_val;
  logic [FTQ_IDX_BITS-1:0]    ftq_ifu_flush_idx;
  logic                       ifu_ftq_pdwb_val;
  logic [FTQ_IDX_BITS-1:0]    ifu_ftq_pdwb_idx;
  logic                       ifu_ftq_pdwb_gen;
  ftq_pd_info_t               ifu_ftq_pd [0:FTQ_PD_WIDTH-1];
  logic [FTQ_PD_WIDTH-1:0]    ifu_ftq_pd_range;
  logic                       ifu_ftq_cfi_val;
  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_cfi_pos;
  logic                       ifu_ftq_mis_val;
  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_mis_pos;
  logic [VA_WIDTH-1:0]        ifu_ftq_target;
  logic                       ifu_ftq_fault_val;
  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_fault_pos;

  // -----------------------------------------------------------------
  // IFU <-> L1I, l1i_ifu_interfaces.md 4 and 5. The emitted L1I
  // names its core link core_*; the IFU's names are kept here.
  // -----------------------------------------------------------------
  logic                       ifu_l1i_req_val;
  logic                       ifu_l1i_req_rdy;
  logic [REQ_ID_BITS-1:0]     ifu_l1i_req_id;
  logic [PA_WIDTH-1:0]        ifu_l1i_req_paddr;
  logic                       ifu_l1i_req_prefetch;
  logic                       l1i_ifu_rsp_val;
  logic [REQ_ID_BITS-1:0]     l1i_ifu_rsp_id;
  logic [L1I_LINE_BITS-1:0]   l1i_ifu_rsp_data;
  logic                       l1i_ifu_rsp_err;

  // -----------------------------------------------------------------
  // IFU <-> ITLB, itlb_ifu_interfaces.md 2
  // -----------------------------------------------------------------
  logic                       ifu_itlb_req_val;
  logic                       ifu_itlb_req_rdy;
  logic [VA_WIDTH-13:0]       ifu_itlb_vpn;
  logic                       ifu_itlb_tag;
  logic                       itlb_ifu_rsp_val;
  logic                       itlb_ifu_tag;
  logic [1:0]                 itlb_ifu_status;
  logic [PPN_WIDTH-1:0]       itlb_ifu_ppn;
  logic [CAUSE_WIDTH-1:0]     itlb_ifu_cause;
  logic [GPA_WIDTH-1:0]       itlb_ifu_gpa;
  logic [PMA_WIDTH-1:0]       itlb_ifu_pma;

  // -----------------------------------------------------------------
  // IFU -> ibuf -> decode, ifu_ibuf_interfaces.md
  // -----------------------------------------------------------------
  logic                       ifu_ibuf_val;
  logic [FTQ_PD_WIDTH-1:0]    ifu_ibuf_en;
  ifu_pd_pkt_t                ifu_ibuf_slot [0:FTQ_PD_WIDTH-1];
  logic                       ibuf_ifu_rdy;
  ifu_pd_pkt_t                ibuf_dec_slot [0:SLOTS-1];

  // -----------------------------------------------------------------
  // The branch predictor cluster
  // -----------------------------------------------------------------
  bp_cluster u_bpu (
    .clk                   (clk),
    .rstn                  (rstn),
    .ftq_pred_val_p0       (ftq_pred_val_p0),
    .ftq_pred_pc_p0        (ftq_pred_pc_p0),
    .ftq_pred_idx_p0       (ftq_pred_idx_p0),
    .bpu_pred_val_p1       (bpu_pred_val_p1),
    .bpu_pred_idx_p1       (bpu_pred_idx_p1),
    .bpu_pred_slot_p1      (bpu_pred_slot_p1),
    .bpu_pred_ras_p1       (bpu_pred_ras_p1),
    .bpu_pred_pft_p1       (bpu_pred_pft_p1),
    .bpu_redir_p2          (bpu_redir_p2),
    .bpu_redir_idx_p2      (bpu_redir_idx_p2),
    .bpu_redir_p3          (bpu_redir_p3),
    .bpu_redir_idx_p3      (bpu_redir_idx_p3),
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
    .bpu_meta_val_p2       (bpu_meta_val_p2),
    .bpu_meta_idx_p2       (bpu_meta_idx_p2),
    .bpu_meta_tage_p2      (bpu_meta_tage_p2),
    .bpu_meta_ittage_p2    (bpu_meta_ittage_p2),
    .bpu_meta_lp_p2        (bpu_meta_lp_p2),
    .bpu_meta_ftb_p2       (bpu_meta_ftb_p2),
    .bpu_meta_val_p3       (bpu_meta_val_p3),
    .bpu_meta_idx_p3       (bpu_meta_idx_p3),
    .bpu_meta_sc_p3        (bpu_meta_sc_p3),
    .ubtb_upd_u0           (ubtb_upd_u0),
    .lp_upd_valid_p0       (lp_upd_valid_p0),
    .lp_upd_p0             (lp_upd_p0),
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
    .ftb_flush_px          (1'b0),
    .tage_upd_val_u0       (tage_upd_val_u0),
    .tage_upd_inp_u0       (tage_upd_inp_u0),
    .ittage_upd_val_u0     (ittage_upd_val_u0),
    .ittage_upd_inp_u0     (ittage_upd_inp_u0),
    .sc_upd_val_u0         (sc_upd_val_u0),
    .sc_upd_inp_u0         (sc_upd_inp_u0),
    .ras_restore_val       (ras_restore_val),
    .ras_restore_snapshot  (ras_restore_snapshot),
    .ras_commit_val        (ras_commit_val),
    .ras_commit_br_type    (ras_commit_br_type),
    .ras_commit_ret_addr   (ras_commit_ret_addr),
    .ras_commit_snapshot   (ras_commit_snapshot),
    .ras_flush_val         (1'b0),
    .ras_flush_snapshot    ('0),
    .ftq_rollback_val      (ftq_rollback_val),
    .ftq_rollback_idx      (ftq_rollback_idx),
    .ftq_rollback_corr     (ftq_rollback_corr),
    .ftq_rollback_n        (ftq_rollback_n),
    .ftq_rollback_tkn      (ftq_rollback_tkn),
    .ftq_rollback_pbit     (ftq_rollback_pbit),
    .ftq_rollback_slot_ex  (ftq_rollback_slot_ex),
    .ftq_rollback_slot_tkn (ftq_rollback_slot_tkn),
    .ghist_ptr             (bpu_ghist_ptr),
    .phist_ptr             (bpu_phist_ptr),
    .ckpt_ghist_ptr        (ckpt_ghist_ptr),
    .ckpt_phist_ptr        (ckpt_phist_ptr),
    .ghr_buf               (bpu_ghr_buf),
    .phr_buf               (bpu_phr_buf),
    .tage_enable_aging     (tage_enable_aging),
    .tage_aging_interval   (tage_aging_interval),
    .ittage_enable_aging   (ittage_enable_aging),
    .ittage_aging_interval (ittage_aging_interval),
    .sc_enable             (sc_enable),
    .ftb_fastpath_en       (ftb_fastpath_en),
    .tage_rdy              (bpu_tage_rdy),
    .ittage_rdy            (bpu_ittage_rdy),
    .sc_ready              (bpu_sc_ready),
    .tage_pq_not_full      (tage_pq_not_full),
    .tage_upd_rdy          (bpu_tage_upd_rdy),
    .tage_upd_rdy_u1       (bpu_tage_upd_rdy_u1),
    .ittage_pq_not_full    (ittage_pq_not_full),
    .ittage_upd_rdy        (bpu_ittage_upd_rdy),
    .ittage_upd_rdy_u1     (bpu_ittage_upd_rdy_u1),
    .sc_uq_not_full        (sc_uq_not_full),
    .sc_upd_rdy            (bpu_sc_upd_rdy),
    .sc_upd_rdy_u1         (bpu_sc_upd_rdy_u1)
  );

  // -----------------------------------------------------------------
  // The fetch target queue
  // -----------------------------------------------------------------
  ftq u_ftq (
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
    .tage_upd_rdy          (bpu_tage_upd_rdy),
    .ittage_upd_rdy        (bpu_ittage_upd_rdy),
    .sc_upd_rdy            (bpu_sc_upd_rdy),
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
  // The instruction fetch unit
  // -----------------------------------------------------------------
  ifu u_ifu (
    .clk                   (clk),
    .rstn                  (rstn),
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
    .ifu_l1i_req_val       (ifu_l1i_req_val),
    .ifu_l1i_req_rdy       (ifu_l1i_req_rdy),
    .ifu_l1i_req_id        (ifu_l1i_req_id),
    .ifu_l1i_req_paddr     (ifu_l1i_req_paddr),
    .ifu_l1i_req_prefetch  (ifu_l1i_req_prefetch),
    .l1i_ifu_rsp_val       (l1i_ifu_rsp_val),
    .l1i_ifu_rsp_id        (l1i_ifu_rsp_id),
    .l1i_ifu_rsp_data      (l1i_ifu_rsp_data),
    .l1i_ifu_rsp_err       (l1i_ifu_rsp_err),
    .ifu_itlb_req_val      (ifu_itlb_req_val),
    .ifu_itlb_req_rdy      (ifu_itlb_req_rdy),
    .ifu_itlb_vpn          (ifu_itlb_vpn),
    .ifu_itlb_tag          (ifu_itlb_tag),
    .itlb_ifu_rsp_val      (itlb_ifu_rsp_val),
    .itlb_ifu_tag          (itlb_ifu_tag),
    .itlb_ifu_status       (itlb_ifu_status),
    .itlb_ifu_ppn          (itlb_ifu_ppn),
    .itlb_ifu_cause        (itlb_ifu_cause),
    .itlb_ifu_gpa          (itlb_ifu_gpa),
    .itlb_ifu_pma          (itlb_ifu_pma),
    .ifu_ibuf_val          (ifu_ibuf_val),
    .ifu_ibuf_en           (ifu_ibuf_en),
    .ifu_ibuf_slot         (ifu_ibuf_slot),
    .ibuf_ifu_rdy          (ibuf_ifu_rdy)
  );

  // -----------------------------------------------------------------
  // The L1I, as emitted (FE-16, FE-21). Its core link is the IFU's
  // l1i_ifu_interfaces.md 4 and 5 port under the emitted names.
  // -----------------------------------------------------------------
  l1i u_l1i (
    .clk           (clk),
    .rstn          (rstn),
    .core_valid    (ifu_l1i_req_val),
    .core_addr     (ifu_l1i_req_paddr),
    .core_id       (ifu_l1i_req_id),
    .core_prefetch (ifu_l1i_req_prefetch),
    .core_rdata    (l1i_ifu_rsp_data),
    .core_ready    (ifu_l1i_req_rdy),
    .core_rvalid   (l1i_ifu_rsp_val),
    .core_rid      (l1i_ifu_rsp_id),
    .core_rerr     (l1i_ifu_rsp_err),
    .mem_a_valid   (l1i_mem_a_valid),
    .mem_a_ready   (l1i_mem_a_ready),
    .mem_a_opcode  (l1i_mem_a_opcode),
    .mem_a_param   (l1i_mem_a_param),
    .mem_a_size    (l1i_mem_a_size),
    .mem_a_source  (l1i_mem_a_source),
    .mem_a_address (l1i_mem_a_address),
    .mem_a_mask    (l1i_mem_a_mask),
    .mem_a_data    (l1i_mem_a_data),
    .mem_a_corrupt (l1i_mem_a_corrupt),
    .mem_d_valid   (l1i_mem_d_valid),
    .mem_d_ready   (l1i_mem_d_ready),
    .mem_d_opcode  (l1i_mem_d_opcode),
    .mem_d_param   (l1i_mem_d_param),
    .mem_d_size    (l1i_mem_d_size),
    .mem_d_source  (l1i_mem_d_source),
    .mem_d_sink    (l1i_mem_d_sink),
    .mem_d_denied  (l1i_mem_d_denied),
    .mem_d_data    (l1i_mem_d_data),
    .mem_d_corrupt (l1i_mem_d_corrupt)
  );

  // -----------------------------------------------------------------
  // The ITLB, with its PMP/PMA checker inside (MMU-10a)
  // -----------------------------------------------------------------
  itlb u_itlb (
    .clk                   (clk),
    .rstn                  (rstn),
    .ifu_itlb_req_val      (ifu_itlb_req_val),
    .ifu_itlb_req_rdy      (ifu_itlb_req_rdy),
    .ifu_itlb_vpn          (ifu_itlb_vpn),
    .ifu_itlb_tag          (ifu_itlb_tag),
    .itlb_ifu_rsp_val      (itlb_ifu_rsp_val),
    .itlb_ifu_tag          (itlb_ifu_tag),
    .itlb_ifu_status       (itlb_ifu_status),
    .itlb_ifu_ppn          (itlb_ifu_ppn),
    .itlb_ifu_cause        (itlb_ifu_cause),
    .itlb_ifu_gpa          (itlb_ifu_gpa),
    .itlb_ifu_pma          (itlb_ifu_pma),
    .itlb_l2t_req_val      (itlb_l2t_req_val),
    .itlb_l2t_req_rdy      (itlb_l2t_req_rdy),
    .itlb_l2t_vpn          (itlb_l2t_vpn),
    .itlb_l2t_asid         (itlb_l2t_asid),
    .itlb_l2t_vmid         (itlb_l2t_vmid),
    .itlb_l2t_v            (itlb_l2t_v),
    .itlb_l2t_tag          (itlb_l2t_tag),
    .l2t_itlb_rsp_val      (l2t_itlb_rsp_val),
    .l2t_itlb_tag          (l2t_itlb_tag),
    .l2t_itlb_status       (l2t_itlb_status),
    .l2t_itlb_ppn          (l2t_itlb_ppn),
    .l2t_itlb_size         (l2t_itlb_size),
    .l2t_itlb_perm         (l2t_itlb_perm),
    .l2t_itlb_pbmt         (l2t_itlb_pbmt),
    .l2t_itlb_cause        (l2t_itlb_cause),
    .l2t_itlb_gpa          (l2t_itlb_gpa),
    .csr_itlb_v            (csr_itlb_v),
    .csr_itlb_priv         (csr_itlb_priv),
    .csr_itlb_satp_mode    (csr_itlb_satp_mode),
    .csr_itlb_satp_asid    (csr_itlb_satp_asid),
    .csr_itlb_vsatp_mode   (csr_itlb_vsatp_mode),
    .csr_itlb_vsatp_asid   (csr_itlb_vsatp_asid),
    .csr_itlb_hgatp_mode   (csr_itlb_hgatp_mode),
    .csr_itlb_hgatp_vmid   (csr_itlb_hgatp_vmid),
    .csr_itlb_pmpcfg       (csr_itlb_pmpcfg),
    .csr_itlb_pmpaddr      (csr_itlb_pmpaddr),
    .bkend_itlb_inv_val    (bkend_itlb_inv_val),
    .bkend_itlb_inv_op     (bkend_itlb_inv_op),
    .bkend_itlb_inv_rs1_nz (bkend_itlb_inv_rs1_nz),
    .bkend_itlb_inv_rs2_nz (bkend_itlb_inv_rs2_nz),
    .bkend_itlb_inv_vpn    (bkend_itlb_inv_vpn),
    .bkend_itlb_inv_asid   (bkend_itlb_inv_asid),
    .bkend_itlb_inv_vmid   (bkend_itlb_inv_vmid)
  );

  // -----------------------------------------------------------------
  // The instruction buffer. Cleared by the backend redirect valid
  // alone (IBUF-13, IB-12).
  // -----------------------------------------------------------------
  ibuf u_ibuf (
    .clk                 (clk),
    .rstn                (rstn),
    .ifu_ibuf_val        (ifu_ibuf_val),
    .ifu_ibuf_en         (ifu_ibuf_en),
    .ifu_ibuf_slot       (ifu_ibuf_slot),
    .ibuf_ifu_rdy        (ibuf_ifu_rdy),
    .bkend_ftq_redir_val (bkend_ftq_redir_val),
    .ibuf_dec_slot       (ibuf_dec_slot),
    .dec_ibuf_rdy        (dec_ibuf_rdy)
  );

  // -----------------------------------------------------------------
  // Decode, on the ibuf read port
  // -----------------------------------------------------------------
  instr_decoder u_dec (
    .ext_enable        (ext_enable),
    .pd_bundle         (ibuf_dec_slot),
    .decode_bundle     (decode_bundle),
    .vec_decode_bundle (vec_decode_bundle),
    .is_vector         (is_vector),
    .pd_out            (pd_out),
    .vtype_hazard      (vtype_hazard)
  );

endmodule : fe_top
