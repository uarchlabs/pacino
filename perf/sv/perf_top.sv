// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// perf_top.sv -- THE HARNESS WRAPPER (PERF-002, perf_decisions.md PF-3,
// PF-4, PF-6). A testbench module, not RTL: it is Verilated with the RTL
// and driven by the C++ gasket (perf/src/harness/).
//
// It instantiates fe_top (dut) and the page table walker beside it
// (u_ptw, on the itlb_l2t_* group), as tb_fe_top does (fe_tb_dut.svh),
// and gives the gasket plain ports in place of the packed groups:
//   - the decode output, 8 wide: each slot's ibuf packet fields and
//     decode's is_illegal
//   - the FTQ resolution, redirect and commit groups, field by field
//   - the L1I's TileLink link and the walker's memory port, as they are
//   - the CSR groups, set from csr_tb_pkg on csr_load (below)
// No RTL file is changed, and no signal is made public: the internal
// signals the counts need are read here by hierarchical reference and
// brought out as this module's ports (PF-3, PF-6):
//   fr_*         THE FETCH RECORD (PERF-003, PF-18): the FTQ's fetch
//                request (dut.ftq_ifu_req_val, _rdy, _idx, _start_pc,
//                _next_pc, _taken_val, _taken_pos), the flush that
//                discards a request presented with it, and the fetch
//                read port's slots in the request cycle
//                (dut.u_ftq.u_entry.fetch_rd_entry: slot_valid, taken,
//                pos, br_type, target, pred_src). pred_src is the
//                predictor that supplied the final prediction (PF-6)
//   pc_*         the predecode correction as the FTQ writes the entry:
//                dut.u_ftq.u_ifu pd_wr_val, pd_wr_idx, the corrected
//                slots w_corr_slot and the successor w_corr_succ
//   ew_*         the entry writes the record's checks read: allocation
//                and the p2 and p3 slot writes (dut.u_ftq.u_entry ports)
//   (PERF-002's pq_*, the slots of each decode slot's entry read at the
//   take, are removed by PERF-003: the record replaces them)
//   os_*, orc_*  THE ORACLE (PERF-003, PF-11): os_* the block at each BPU
//                stage, the slots its stage logic reads and its
//                predecessor's FTQ entry; orc_* the trace's direction
//                and target per slot, from the gasket, forced into
//                bp_cluster's predictor outputs (the oracle section)
//   obs_walk     a walk request accepted, itlb_l2t_req_val and _rdy
//   obs_pd_redir the predecode redirect, dut.ifu_ftq_mis_val
//   obs_p2_redir, obs_p3_redir
//                a BPU override at p2 or p3, any slot's valid of
//                dut.bpu_redir_p2 and dut.bpu_redir_p3
//   obs_l1i_req, obs_l1i_paddr, obs_l1i_rdy
//                the IFU's request on the L1I core link,
//                dut.ifu_l1i_req_val, _paddr, _rdy (the I-cache switch,
//                PF-19, reads them)
//   rc_*         THE RAS CLASSIFICATION (BP-151): the RAS state
//                (dut.u_bpu.u_ras tosr, tosw, bos, csp, c_cnt and both
//                arrays), its p2 inputs, pop outputs, op codes and pre-op
//                state (p2_op, p2_push_inc, p2_push_sat, p2_pre_tosr,
//                p2_pre_empty), its p3 view and registered op, its write
//                ports (sp_we, sp_waddr), the restore and the commit as
//                it receives them, the FTQ commit index, the rollback
//                index and the predecode redirect's position
//                (perf/src/harness/ras_class.h reads them)
//
// THE CSR GROUPS (PF-5). csr_load, sampled at a rising edge, resets the
// csr_tb_pkg shadow (csr_pkg reset values, CSR-7), sets U-mode (every
// PF-17 leaf has U set, so the trace runs as user code), writes
// satp (csr_satp, the image's satp line: Sv57, ASID 0, the root), and
// writes 0x7C0 and 0x7C1 from the cfg_* inputs; fe_cfg, fe_csr and
// ptw_csr are then packed from the shadow (csr_decisions.md CSR-2), as
// fe_tb_csr.svh's csr_sync does.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;
import decode_pkg::*;
import csr_pkg::*;

module perf_top (
  input  logic                        clk,
  input  logic                        rstn,

  // ---- decode to the backend (FE-20) -------------------------------
  output logic [SLOTS-1:0]            pd_valid,
  output logic [VA_WIDTH-1:0]         pd_pc     [SLOTS],
  output logic [31:0]                 pd_instr  [SLOTS],
  output logic [FTQ_PD_POS_BITS-1:0]  pd_pos    [SLOTS],
  output logic [FTQ_IDX_BITS-1:0]     pd_idx    [SLOTS],
  output logic [1:0]                  pd_fault  [SLOTS],
  output logic [SLOTS-1:0]            pd_rvc,
  output logic [SLOTS-1:0]            pd_illegal,
  input  logic                        dec_ibuf_rdy,

  // ---- the FTQ resolution group, per port --------------------------
  input  logic [NUM_RESOLVE_PORTS-1:0] rsv_val,
  input  logic [FTQ_IDX_BITS-1:0]     rsv_idx    [NUM_RESOLVE_PORTS],
  input  logic [FTB_BR_POS_BITS-1:0]  rsv_pos    [NUM_RESOLVE_PORTS],
  input  logic [NUM_RESOLVE_PORTS-1:0] rsv_taken,
  input  logic [VA_WIDTH-1:0]         rsv_target [NUM_RESOLVE_PORTS],
  input  logic [2:0]                  rsv_type   [NUM_RESOLVE_PORTS],
  input  logic [NUM_RESOLVE_PORTS-1:0] rsv_mis,
  output logic [NUM_RESOLVE_PORTS-1:0] rsv_rdy,

  // ---- the FTQ redirect and commit groups --------------------------
  input  logic                        redir_val,
  input  logic [FTQ_IDX_BITS-1:0]     redir_idx,
  input  logic [FTB_BR_POS_BITS-1:0]  redir_pos,
  input  logic [VA_WIDTH-1:0]         redir_pc,
  input  logic                        redir_self,
  input  logic [1:0]                  redir_cause,
  input  logic                        redir_taken,
  input  logic                        commit_val,
  input  logic [FTQ_PTR_BITS-1:0]     commit_idx,

  // ---- the L1I's l2-side TileLink link -----------------------------
  output logic                        l1i_a_valid,
  input  logic                        l1i_a_ready,
  output logic [2:0]                  l1i_a_opcode,
  output logic [2:0]                  l1i_a_size,
  output logic [3:0]                  l1i_a_source,
  output logic [PA_WIDTH-1:0]         l1i_a_address,
  output logic [31:0]                 l1i_a_mask,
  input  logic                        l1i_d_valid,
  output logic                        l1i_d_ready,
  input  logic [2:0]                  l1i_d_opcode,
  input  logic [2:0]                  l1i_d_size,
  input  logic [3:0]                  l1i_d_source,
  input  logic                        l1i_d_denied,
  input  logic [255:0]                l1i_d_data,

  // ---- the walker's memory port (ptw_mem_interfaces.md) ------------
  output logic                        ptw_req_val,
  input  logic                        ptw_req_rdy,
  output logic                        ptw_req_op,
  output logic [PA_WIDTH-1:0]         ptw_req_paddr,
  output logic [63:0]                 ptw_req_cmp,
  output logic [63:0]                 ptw_req_swap,
  input  logic                        ptw_rsp_val,
  input  logic [63:0]                 ptw_rsp_data,
  input  logic                        ptw_rsp_err,

  // ---- the CSR groups (PF-5) ---------------------------------------
  input  logic                        csr_load,
  input  logic [63:0]                 csr_satp,
  input  logic                        cfg_sc_enable,
  input  logic                        cfg_ftb_fastpath_en,
  input  logic                        cfg_tage_enable_aging,
  input  logic                        cfg_ittage_enable_aging,
  input  logic [31:0]                 cfg_tage_aging_interval,
  input  logic [31:0]                 cfg_ittage_aging_interval,

  // ---- observation (PF-6), by hierarchical reference ---------------
  output logic                        obs_walk,
  // fe_cfg as fe_top receives it: sc, fast path, TAGE and ITTAGE aging
  // enables, then the two intervals.
  output logic [3:0]                  obs_cfg_en,
  output logic [31:0]                 obs_cfg_tage_int,
  output logic [31:0]                 obs_cfg_ittage_int,
  output logic                        obs_pd_redir,
  output logic                        obs_p2_redir,
  output logic                        obs_p3_redir,
  output logic                        obs_l1i_req,
  output logic [PA_WIDTH-1:0]         obs_l1i_paddr,
  output logic                        obs_l1i_rdy,
  output logic                        ftq_full,
  output logic                        ftq_empty,

  // ---- the fetch record (PERF-003, PF-18), by hierarchical reference
  // The fetch request (dut.ftq_ifu_*, ftq_ifu.sv request) and the
  // flush that discards a request presented with it (ftq_ifu.sv 5).
  output logic                        fr_req_val,
  output logic                        fr_req_rdy,
  output logic                        fr_flush_val,
  output logic [FTQ_IDX_BITS-1:0]     fr_idx,
  output logic [FTQ_IDX_BITS-1:0]     fr_rd_idx,
  output logic [VA_WIDTH-1:0]         fr_start_pc,
  output logic [VA_WIDTH-1:0]         fr_next_pc,
  output logic                        fr_taken_val,
  output logic [FTB_BR_POS_BITS-1:0]  fr_taken_pos,
  // The fetch read port's slots in the request cycle
  // (dut.u_ftq.u_entry.fetch_rd_entry, which writes through p3).
  output logic [NUM_PRED_SLOTS-1:0]   fr_s_val,
  output logic [NUM_PRED_SLOTS-1:0]   fr_s_taken,
  output logic [FTB_BR_POS_BITS-1:0]  fr_s_pos [NUM_PRED_SLOTS],
  output logic [2:0]                  fr_s_type [NUM_PRED_SLOTS],
  output logic [2:0]                  fr_s_src [NUM_PRED_SLOTS],
  output logic [VA_WIDTH-1:0]         fr_s_tgt [NUM_PRED_SLOTS],
  // The predecode correction as the FTQ writes it: pd_wr_val and _idx
  // (the gen-tested, R3-gated redirect), the corrected slots and the
  // successor re-derived over them (dut.u_ftq.u_ifu w_corr_slot,
  // w_corr_succ, ftq_ifu.sv 7).
  output logic                        pc_val,
  output logic [FTQ_IDX_BITS-1:0]     pc_idx,
  output logic [VA_WIDTH-1:0]         pc_succ,
  output logic [NUM_PRED_SLOTS-1:0]   pc_s_val,
  output logic [NUM_PRED_SLOTS-1:0]   pc_s_taken,
  output logic [FTB_BR_POS_BITS-1:0]  pc_s_pos [NUM_PRED_SLOTS],
  output logic [2:0]                  pc_s_type [NUM_PRED_SLOTS],
  output logic [2:0]                  pc_s_src [NUM_PRED_SLOTS],
  output logic [VA_WIDTH-1:0]         pc_s_tgt [NUM_PRED_SLOTS],
  // The entry writes the late-write check reads: allocation, and the
  // p2 and p3 slot writes (dut.u_ftq.u_entry ports).
  output logic                        ew_alloc_val,
  output logic [FTQ_IDX_BITS-1:0]     ew_alloc_idx,
  output logic                        ew_p2_val,
  output logic [FTQ_IDX_BITS-1:0]     ew_p2_idx,
  output logic                        ew_p3_val,
  output logic [FTQ_IDX_BITS-1:0]     ew_p3_idx,
  output logic [VA_WIDTH-1:0]         ew_alloc_pc,

  // ---- THE ORACLE (PERF-003, PF-11) ----------------------------------
  // The block at each BPU stage (bp_cluster r_val_pN, r_pc_pN,
  // r_idx_pN) and the slots its stage logic reads: p1 the registered
  // uBTB slots, p2 the FTB classification (w_br_val_p2, w_pos_p2,
  // w_br_type_p2), p3 the registered p2 slots (r_slot_p3).
  output logic                        os_p1_val,
  output logic [VA_WIDTH-1:0]         os_p1_pc,
  output logic [FTQ_IDX_BITS-1:0]     os_p1_idx,
  output logic [NUM_PRED_SLOTS-1:0]   os_p1_s_val,
  output logic [FTB_BR_POS_BITS-1:0]  os_p1_s_pos [NUM_PRED_SLOTS],
  output logic [2:0]                  os_p1_s_type [NUM_PRED_SLOTS],
  output logic                        os_p2_val,
  output logic [VA_WIDTH-1:0]         os_p2_pc,
  output logic [FTQ_IDX_BITS-1:0]     os_p2_idx,
  output logic [NUM_PRED_SLOTS-1:0]   os_p2_s_val,
  output logic [FTB_BR_POS_BITS-1:0]  os_p2_s_pos [NUM_PRED_SLOTS],
  output logic [2:0]                  os_p2_s_type [NUM_PRED_SLOTS],
  output logic                        os_p3_val,
  output logic [VA_WIDTH-1:0]         os_p3_pc,
  output logic [FTQ_IDX_BITS-1:0]     os_p3_idx,
  output logic [NUM_PRED_SLOTS-1:0]   os_p3_s_val,
  output logic [FTB_BR_POS_BITS-1:0]  os_p3_s_pos [NUM_PRED_SLOTS],
  output logic [2:0]                  os_p3_s_type [NUM_PRED_SLOTS],
  // The FTQ entry before each stage's block (its predecessor, whose
  // prediction gave the block's PC): start, fall-through and slots, from
  // dut.u_ftq.u_entry.r_arr; [0] p1, [1] p2, [2] p3.
  output logic [VA_WIDTH-1:0]         os_pr_pc [3],
  output logic [VA_WIDTH-1:0]         os_pr_pft [3],
  output logic [NUM_PRED_SLOTS-1:0]   os_pr_s_val [3],
  output logic [NUM_PRED_SLOTS-1:0]   os_pr_s_taken [3],
  output logic [FTB_BR_POS_BITS-1:0]  os_pr_s_pos [3][NUM_PRED_SLOTS],
  // The trace's value for each slot, from the gasket: _den forces the
  // direction to _dir, _ten the target to _tgt; p1 _ret forces the RAS
  // top of stack (a return slot) to _dir and _tgt; p2 _jten forces the
  // block's jump target to _jtgt. A slot with no enable keeps the
  // predictor's own value. orc_on is --oracle.
  input  logic                        orc_on,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p1_den,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p1_dir,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p1_ten,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p1_ret,
  input  logic [VA_WIDTH-1:0]         orc_p1_tgt [NUM_PRED_SLOTS],
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p2_den,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p2_dir,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p2_ten,
  input  logic [VA_WIDTH-1:0]         orc_p2_tgt [NUM_PRED_SLOTS],
  input  logic                        orc_p2_jten,
  input  logic [VA_WIDTH-1:0]         orc_p2_jtgt,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p3_den,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p3_dir,

  // ---- THE RAS CLASSIFICATION (BP-151), by hierarchical reference ----
  // Observation only: the RAS state (dut.u_bpu.u_ras), its p2 and p3
  // operations as the scan forms them, its array write ports, and the
  // restore and commit groups as the RAS receives them.
  output logic [RAS_PTR_BITS-1:0]        rc_tosr,
  output logic [RAS_PTR_BITS-1:0]        rc_tosw,
  output logic [RAS_PTR_BITS-1:0]        rc_bos,
  output logic [RAS_COMMIT_PTR_BITS-1:0] rc_csp,
  output logic [RAS_COMMIT_PTR_BITS:0]   rc_ccnt,
  output logic [VA_WIDTH-1:0]            rc_spec_addr [RAS_SPEC_ENTRIES],
  output logic [RAS_PTR_BITS-1:0]        rc_spec_nos  [RAS_SPEC_ENTRIES],
  output logic [RAS_RCTR_WIDTH-1:0]      rc_spec_rctr [RAS_SPEC_ENTRIES],
  output logic [RAS_SPEC_ENTRIES-1:0]    rc_spec_bot,
  output logic [VA_WIDTH-1:0]            rc_cmt_addr  [RAS_COMMIT_ENTRIES],
  // p2: the inputs, the pop outputs, the op and the pre-op state per slot
  output logic [NUM_PRED_SLOTS-1:0]      rc_p2_val,
  output logic [2:0]                     rc_p2_type   [NUM_PRED_SLOTS],
  output logic [VA_WIDTH-1:0]            rc_p2_ft     [NUM_PRED_SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]      rc_p2_popv,
  output logic [VA_WIDTH-1:0]            rc_p2_popa   [NUM_PRED_SLOTS],
  output logic [1:0]                     rc_p2_op     [NUM_PRED_SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]      rc_p2_inc,
  output logic [NUM_PRED_SLOTS-1:0]      rc_p2_sat,
  output logic [RAS_PTR_BITS-1:0]        rc_p2_pre    [NUM_PRED_SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]      rc_p2_pre_empty,
  output logic                           rc_keep,
  output logic                           rc_ftb_p2,
  // p3: the view and the registered p2 op per slot
  output logic [NUM_PRED_SLOTS-1:0]      rc_p3_val,
  output logic [2:0]                     rc_p3_type   [NUM_PRED_SLOTS],
  output logic [1:0]                     rc_p3_op     [NUM_PRED_SLOTS],
  output logic [VA_WIDTH-1:0]            rc_p3_ft     [NUM_PRED_SLOTS],
  // the speculative array write ports (ras.sv RAS_WR_PORTS)
  output logic [4*NUM_PRED_SLOTS-1:0]    rc_we,
  output logic [RAS_PTR_BITS-1:0]        rc_waddr     [4*NUM_PRED_SLOTS],
  // the restore and the commit, as the RAS receives them
  output logic                           rc_rs_val,
  output logic [RAS_PTR_BITS-1:0]        rc_rs_tosr,
  output logic [RAS_PTR_BITS-1:0]        rc_rs_tosw,
  output logic [RAS_PTR_BITS-1:0]        rc_rs_bos,
  output logic                           rc_cm_val,
  output logic [2:0]                     rc_cm_type,
  output logic [VA_WIDTH-1:0]            rc_cm_addr,
  output logic [RAS_PTR_BITS-1:0]        rc_cm_tosr,
  output logic [RAS_PTR_BITS-1:0]        rc_cm_bos,
  output logic [FTQ_IDX_BITS-1:0]        rc_cm_idx,
  // the entry a restore names, and the predecode redirect's position
  output logic [FTQ_IDX_BITS-1:0]        rc_rs_idx,
  output logic [FTQ_PD_POS_BITS-1:0]     rc_pd_pos
);

  // ---- every fe_top port, the names fe_tb_dut.svh gives them -------
  decode_pkt_t     [SLOTS-1:0] decode_bundle;
  vec_decode_pkt_t [SLOTS-1:0] vec_decode_bundle;
  logic            [SLOTS-1:0] is_vector;
  ifu_pd_pkt_t                 pd_out [0:SLOTS-1];
  logic            [SLOTS-1:0] vtype_hazard;
  logic [NUM_RESOLVE_PORTS-1:0] bkend_ftq_rsv_val;
  ftq_resolve_t                bkend_ftq_rsv [0:NUM_RESOLVE_PORTS-1];
  logic [NUM_RESOLVE_PORTS-1:0] ftq_bkend_rsv_rdy;
  logic                        bkend_ftq_redir_val;
  logic [FTQ_IDX_BITS-1:0]     bkend_ftq_redir_idx;
  logic [FTB_BR_POS_BITS-1:0]  bkend_ftq_redir_pos;
  logic [VA_WIDTH-1:0]         bkend_ftq_redir_pc;
  logic                        bkend_ftq_redir_self;
  ftq_redir_cause_e            bkend_ftq_redir_cause;
  logic                        bkend_ftq_redir_taken;
  logic                        bkend_ftq_commit_val;
  logic [FTQ_PTR_BITS-1:0]     bkend_ftq_commit_idx;
  logic                        itlb_l2t_req_val;
  logic                        itlb_l2t_req_rdy;
  logic [VA_WIDTH-13:0]        itlb_l2t_vpn;
  logic [ASID_WIDTH-1:0]       itlb_l2t_asid;
  logic [VMID_WIDTH-1:0]       itlb_l2t_vmid;
  logic                        itlb_l2t_v;
  logic [1:0]                  itlb_l2t_tag;
  logic [1:0]                  itlb_l2t_acc;
  logic [1:0]                  itlb_l2t_priv;
  logic                        l2t_itlb_rsp_val;
  logic [1:0]                  l2t_itlb_tag;
  logic [1:0]                  l2t_itlb_status;
  logic [PPN_WIDTH-1:0]        l2t_itlb_ppn;
  logic [2:0]                  l2t_itlb_size;
  logic [PERM_WIDTH-1:0]       l2t_itlb_perm;
  logic [1:0]                  l2t_itlb_pbmt;
  logic [CAUSE_WIDTH-1:0]      l2t_itlb_cause;
  logic [FAULT_GPA_WIDTH-1:0]  l2t_itlb_gpa;
  logic [1:0]                  l2t_itlb_gpa_imp;
  logic                        cmt_ifu_maint_val;
  logic                        cmt_ifu_maint_rdy;
  logic                        cmt_ifu_maint_op;
  logic [PA_WIDTH-1:0]         cmt_ifu_maint_paddr;
  logic                        ifu_cmt_maint_ack;
  logic                        l1i_mem_a_valid;
  logic                        l1i_mem_a_ready;
  logic [2:0]                  l1i_mem_a_opcode;
  logic [2:0]                  l1i_mem_a_param;
  logic [2:0]                  l1i_mem_a_size;
  logic [3:0]                  l1i_mem_a_source;
  logic [PA_WIDTH-1:0]         l1i_mem_a_address;
  logic [31:0]                 l1i_mem_a_mask;
  logic [255:0]                l1i_mem_a_data;
  logic                        l1i_mem_a_corrupt;
  logic                        l1i_mem_d_valid;
  logic                        l1i_mem_d_ready;
  logic [2:0]                  l1i_mem_d_opcode;
  logic [2:0]                  l1i_mem_d_param;
  logic [2:0]                  l1i_mem_d_size;
  logic [3:0]                  l1i_mem_d_source;
  logic [1:0]                  l1i_mem_d_sink;
  logic                        l1i_mem_d_denied;
  logic [255:0]                l1i_mem_d_data;
  logic                        l1i_mem_d_corrupt;
  fe_csr_t                     fe_csr;
  fe_cfg_t                     fe_cfg;
  logic                        bkend_itlb_inv_val;
  logic [1:0]                  bkend_itlb_inv_op;
  logic                        bkend_itlb_inv_rs1_nz;
  logic                        bkend_itlb_inv_rs2_nz;
  logic [VA_WIDTH-13:0]        bkend_itlb_inv_vpn;
  logic [ASID_WIDTH-1:0]       bkend_itlb_inv_asid;
  logic [VMID_WIDTH-1:0]       bkend_itlb_inv_vmid;

  fe_top dut (.*);

  // ---- the walker, beside the top (MMU-1a) -------------------------
  logic                        ptw_mem_req_val;
  logic                        ptw_mem_req_rdy;
  logic                        ptw_mem_req_op;
  logic [PA_WIDTH-1:0]         ptw_mem_req_paddr;
  logic [63:0]                 ptw_mem_req_cmp;
  logic [63:0]                 ptw_mem_req_swap;
  logic                        mem_ptw_rsp_val;
  logic [63:0]                 mem_ptw_rsp_data;
  logic                        mem_ptw_rsp_err;
  ptw_csr_t                    ptw_csr;

  ptw u_ptw (.*);

  // ---- the decode output, slot by slot -----------------------------
  always_comb begin : pd_ports
    for (int i = 0; i < SLOTS; i++) begin
      pd_valid[i]   = pd_out[i].valid;
      pd_pc[i]      = pd_out[i].start_pc;
      pd_instr[i]   = pd_out[i].instr;
      pd_pos[i]     = pd_out[i].pos;
      pd_idx[i]     = pd_out[i].ftq_idx;
      pd_fault[i]   = pd_out[i].fault_cause;
      pd_rvc[i]     = pd_out[i].is_rvc;
      pd_illegal[i] = decode_bundle[i].is_illegal;
    end
  end

  // ---- the backend groups ------------------------------------------
  always_comb begin : be_ports
    for (int p = 0; p < NUM_RESOLVE_PORTS; p++) begin
      bkend_ftq_rsv[p]            = '0;
      bkend_ftq_rsv[p].ftq_idx    = rsv_idx[p];
      bkend_ftq_rsv[p].pos        = rsv_pos[p];
      bkend_ftq_rsv[p].taken      = rsv_taken[p];
      bkend_ftq_rsv[p].target     = rsv_target[p];
      bkend_ftq_rsv[p].br_type    = bp_br_type_e'(rsv_type[p]);
      bkend_ftq_rsv[p].mispredict = rsv_mis[p];
      bkend_ftq_rsv[p].is_rvc     = 1'b0;     // every image word is 32 bits
    end
    bkend_ftq_rsv_val     = rsv_val;
    rsv_rdy               = ftq_bkend_rsv_rdy;
    bkend_ftq_redir_val   = redir_val;
    bkend_ftq_redir_idx   = redir_idx;
    bkend_ftq_redir_pos   = redir_pos;
    bkend_ftq_redir_pc    = redir_pc;
    bkend_ftq_redir_self  = redir_self;
    bkend_ftq_redir_cause = ftq_redir_cause_e'(redir_cause);
    bkend_ftq_redir_taken = redir_taken;
    bkend_ftq_commit_val  = commit_val;
    bkend_ftq_commit_idx  = commit_idx;
    // No FENCE.I, cbo.inval or ITLB invalidate in a trace.
    cmt_ifu_maint_val     = 1'b0;
    cmt_ifu_maint_op      = 1'b0;
    cmt_ifu_maint_paddr   = '0;
    bkend_itlb_inv_val    = 1'b0;
    bkend_itlb_inv_op     = '0;
    bkend_itlb_inv_rs1_nz = 1'b0;
    bkend_itlb_inv_rs2_nz = 1'b0;
    bkend_itlb_inv_vpn    = '0;
    bkend_itlb_inv_asid   = '0;
    bkend_itlb_inv_vmid   = '0;
  end

  // ---- the memory links --------------------------------------------
  always_comb begin : mem_ports
    l1i_a_valid       = l1i_mem_a_valid;
    l1i_mem_a_ready   = l1i_a_ready;
    l1i_a_opcode      = l1i_mem_a_opcode;
    l1i_a_size        = l1i_mem_a_size;
    l1i_a_source      = l1i_mem_a_source;
    l1i_a_address     = l1i_mem_a_address;
    l1i_a_mask        = l1i_mem_a_mask;
    l1i_mem_d_valid   = l1i_d_valid;
    l1i_d_ready       = l1i_mem_d_ready;
    l1i_mem_d_opcode  = l1i_d_opcode;
    l1i_mem_d_param   = '0;
    l1i_mem_d_size    = l1i_d_size;
    l1i_mem_d_source  = l1i_d_source;
    l1i_mem_d_sink    = '0;
    l1i_mem_d_denied  = l1i_d_denied;
    l1i_mem_d_data    = l1i_d_data;
    l1i_mem_d_corrupt = 1'b0;
    ptw_req_val       = ptw_mem_req_val;
    ptw_mem_req_rdy   = ptw_req_rdy;
    ptw_req_op        = ptw_mem_req_op;
    ptw_req_paddr     = ptw_mem_req_paddr;
    ptw_req_cmp       = ptw_mem_req_cmp;
    ptw_req_swap      = ptw_mem_req_swap;
    mem_ptw_rsp_val   = ptw_rsp_val;
    mem_ptw_rsp_data  = ptw_rsp_data;
    mem_ptw_rsp_err   = ptw_rsp_err;
  end

  // ---- the CSR groups (PF-5), from the csr_tb_pkg shadow -----------
  always_ff @(posedge clk) begin : csr_groups
    if (csr_load) begin
      csr_tb_pkg::csr_reset();
      csr_tb_pkg::set_priv(CSR_PRV_U);
      csr_tb_pkg::csr_write(CSR_SATP_ADDR, csr_satp);
      csr_tb_pkg::set_sc_enable(cfg_sc_enable);
      csr_tb_pkg::set_ftb_fastpath_en(cfg_ftb_fastpath_en);
      csr_tb_pkg::set_tage_enable_aging(cfg_tage_enable_aging);
      csr_tb_pkg::set_ittage_enable_aging(cfg_ittage_enable_aging);
      csr_tb_pkg::set_tage_aging_interval(cfg_tage_aging_interval);
      csr_tb_pkg::set_ittage_aging_interval(cfg_ittage_aging_interval);
      fe_cfg  <= csr_tb_pkg::pack_fe_cfg();
      fe_csr  <= csr_tb_pkg::pack_fe_csr();
      ptw_csr <= csr_tb_pkg::pack_ptw_csr();
    end
  end

  // ---- observation, by hierarchical reference (PF-6) ---------------
  always_comb begin : observe
    obs_walk     = itlb_l2t_req_val && itlb_l2t_req_rdy;
    obs_cfg_en   = {fe_cfg.ittage_enable_aging, fe_cfg.tage_enable_aging,
                    fe_cfg.ftb_fastpath_en, fe_cfg.sc_enable};
    obs_cfg_tage_int   = fe_cfg.tage_aging_interval;
    obs_cfg_ittage_int = fe_cfg.ittage_aging_interval;
    obs_pd_redir = dut.ifu_ftq_mis_val;
    obs_p2_redir = 1'b0;
    obs_p3_redir = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      obs_p2_redir = obs_p2_redir | dut.bpu_redir_p2[s].valid;
      obs_p3_redir = obs_p3_redir | dut.bpu_redir_p3[s].valid;
    end
    obs_l1i_req   = dut.ifu_l1i_req_val;
    obs_l1i_paddr = dut.ifu_l1i_req_paddr;
    obs_l1i_rdy   = dut.ifu_l1i_req_rdy;
  end

  // ---- the fetch record (PERF-003), by hierarchical reference ------
  always_comb begin : fetch_record
    fr_req_val   = dut.ftq_ifu_req_val;
    fr_req_rdy   = dut.ftq_ifu_req_rdy;
    fr_flush_val = dut.ftq_ifu_flush_val;
    fr_idx       = dut.ftq_ifu_idx;
    fr_rd_idx    = dut.u_ftq.u_entry.fetch_rd_idx;
    fr_start_pc  = dut.ftq_ifu_start_pc;
    fr_next_pc   = dut.ftq_ifu_next_pc;
    fr_taken_val = dut.ftq_ifu_taken_val;
    fr_taken_pos = dut.ftq_ifu_taken_pos;
    pc_val       = dut.u_ftq.u_ifu.pd_wr_val;
    pc_idx       = dut.u_ftq.u_ifu.pd_wr_idx;
    pc_succ      = dut.u_ftq.u_ifu.w_corr_succ;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      fr_s_val[s]   = dut.u_ftq.u_entry.fetch_rd_entry.slot[s].slot_valid;
      fr_s_taken[s] = dut.u_ftq.u_entry.fetch_rd_entry.slot[s].taken;
      fr_s_pos[s]   = dut.u_ftq.u_entry.fetch_rd_entry.slot[s].pos;
      fr_s_type[s]  = 3'(dut.u_ftq.u_entry.fetch_rd_entry.slot[s].br_type);
      fr_s_src[s]   = 3'(dut.u_ftq.u_entry.fetch_rd_entry.slot[s].pred_src);
      fr_s_tgt[s]   = dut.u_ftq.u_entry.fetch_rd_entry.slot[s].target;
      pc_s_val[s]   = dut.u_ftq.u_ifu.w_corr_slot[s].slot_valid;
      pc_s_taken[s] = dut.u_ftq.u_ifu.w_corr_slot[s].taken;
      pc_s_pos[s]   = dut.u_ftq.u_ifu.w_corr_slot[s].pos;
      pc_s_type[s]  = 3'(dut.u_ftq.u_ifu.w_corr_slot[s].br_type);
      pc_s_src[s]   = 3'(dut.u_ftq.u_ifu.w_corr_slot[s].pred_src);
      pc_s_tgt[s]   = dut.u_ftq.u_ifu.w_corr_slot[s].target;
    end
    ew_alloc_val = dut.u_ftq.u_entry.alloc_wr_val;
    ew_alloc_idx = dut.u_ftq.u_entry.alloc_wr_idx;
    ew_p2_val    = dut.u_ftq.u_entry.p2_wr_val;
    ew_p2_idx    = dut.u_ftq.u_entry.p2_wr_idx;
    ew_p3_val    = dut.u_ftq.u_entry.p3_wr_val;
    ew_p3_idx    = dut.u_ftq.u_entry.p3_wr_idx;
    ew_alloc_pc  = dut.u_ftq.u_entry.alloc_wr_pc;
  end

  // ---- THE ORACLE (PERF-003, PF-11), by SV force inside bp_cluster ---
  // Every force is continuous, from the start, to a mux: the trace's
  // value where the gasket enables it (an entry allocated on the path,
  // at a slot the trace decides), else the predictor's own value. The
  // predictor's own value is read where the force does not reach:
  //   - r_ubtb_pred_p1 and r_ras_tos_*_p1 are bp_cluster's p0 -> p1
  //     registers, loaded every clock from w_ubtb_pred_p1 and
  //     w_ras_tos_*_p0 with a synchronous reset (bp_cluster stage_ff).
  //     sh_* below are the same registers, loaded from the same nets,
  //     so they hold the value the forced register would hold.
  //   - the p2 and p3 predictor outputs are read at the predictor
  //     module's own output port, a variable of its own because perf.vlt
  //     keeps loop_pred, ftb, tage, ittage, sc and ras out of inlining.
  //   - w_ftb_br_taken_p2 and _target_p2 are bp_cluster's per-slot
  //     views of the FTB's br0 and br1 ports; those ports are read.
  // Slot presence, type and position are never forced: a branch the
  // predictors hold in no slot stays a miss (PF-11).
  ubtb_pred_t [NUM_PRED_SLOTS-1:0] sh_ubtb_pred;
  logic [VA_WIDTH-1:0]             sh_tos_addr [NUM_PRED_SLOTS];
  logic                            sh_tos_val  [NUM_PRED_SLOTS];
  always_ff @(posedge clk) begin : oracle_shadow
    if (!rstn) begin
      sh_ubtb_pred <= '0;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        sh_tos_addr[s] <= '0;
        sh_tos_val[s]  <= 1'b0;
      end
    end else begin
      sh_ubtb_pred <= dut.u_bpu.w_ubtb_pred_p1;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        sh_tos_addr[s] <= dut.u_bpu.w_ras_tos_addr_p0[s];
        sh_tos_val[s]  <= dut.u_bpu.w_ras_tos_valid_p0[s];
      end
    end
  end

  logic [FTQ_IDX_BITS-1:0] pr_idx [3];
  always_comb begin : oracle_state
    os_p1_val = dut.u_bpu.r_val_p1;
    os_p1_pc  = dut.u_bpu.r_pc_p1;
    os_p1_idx = dut.u_bpu.r_idx_p1;
    os_p2_val = dut.u_bpu.r_val_p2;
    os_p2_pc  = dut.u_bpu.r_pc_p2;
    os_p2_idx = dut.u_bpu.r_idx_p2;
    os_p3_val = dut.u_bpu.r_val_p3;
    os_p3_pc  = dut.u_bpu.r_pc_p3;
    os_p3_idx = dut.u_bpu.r_idx_p3;
    pr_idx[0] = dut.u_bpu.r_idx_p1 - 1'b1;
    pr_idx[1] = dut.u_bpu.r_idx_p2 - 1'b1;
    pr_idx[2] = dut.u_bpu.r_idx_p3 - 1'b1;
    for (int g = 0; g < 3; g++) begin
      os_pr_pc[g]  = dut.u_ftq.u_entry.r_arr[pr_idx[g]].pc;
      os_pr_pft[g] = dut.u_ftq.u_entry.r_arr[pr_idx[g]].pft_addr;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        os_pr_s_val[g][s]   = dut.u_ftq.u_entry.r_arr[pr_idx[g]].slot[s]
                                .slot_valid;
        os_pr_s_taken[g][s] = dut.u_ftq.u_entry.r_arr[pr_idx[g]].slot[s]
                                .taken;
        os_pr_s_pos[g][s]   = dut.u_ftq.u_entry.r_arr[pr_idx[g]].slot[s]
                                .pos;
      end
    end
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      os_p1_s_val[s]  = sh_ubtb_pred[s].valid;
      os_p1_s_pos[s]  = FTB_BR_POS_BITS'(sh_ubtb_pred[s].pos);
      os_p1_s_type[s] = 3'(sh_ubtb_pred[s].br_type);
      os_p2_s_val[s]  = dut.u_bpu.w_br_val_p2[s];
      os_p2_s_pos[s]  = dut.u_bpu.w_pos_p2[s];
      os_p2_s_type[s] = 3'(dut.u_bpu.w_br_type_p2[s]);
      os_p3_s_val[s]  = dut.u_bpu.r_slot_p3[s].slot_valid;
      os_p3_s_pos[s]  = dut.u_bpu.r_slot_p3[s].pos;
      os_p3_s_type[s] = 3'(dut.u_bpu.r_slot_p3[s].br_type);
    end
  end

  // The forced values. Each is a whole variable or array element, built
  // from the predictor's own value with the trace's fields put in: a
  // second force on another member of the same element is not applied
  // by this build (found here: of ITTAGE's prm_tgt and alt_tgt, only one
  // took), so no element is forced member by member.
  ubtb_pred_t [NUM_PRED_SLOTS-1:0] o_p1_ubtb;
  lp_pred_t             o_p1_lp   [NUM_PRED_SLOTS];
  logic                 o_p1_tosv [NUM_PRED_SLOTS];
  logic [VA_WIDTH-1:0]  o_p1_tosa [NUM_PRED_SLOTS];
  lp_pred_t             o_p2_lp   [NUM_PRED_SLOTS];
  tage_pred_meta_t      o_p2_tage [NUM_PRED_SLOTS];
  logic                 o_p2_ftk  [NUM_PRED_SLOTS];
  logic [VA_WIDTH-1:0]  o_p2_ftg  [NUM_PRED_SLOTS];
  logic [VA_WIDTH-1:0]  o_p2_ras  [NUM_PRED_SLOTS];
  ittage_pred_meta_t    o_p2_it   [NUM_PRED_SLOTS];
  logic [VA_WIDTH-1:0]  o_p2_jt;
  sc_pred_meta_t        o_p3_sc   [NUM_PRED_SLOTS];
  always_comb begin : oracle_values
    o_p1_ubtb = sh_ubtb_pred;
    o_p2_jt = (orc_on && orc_p2_jten) ? orc_p2_jtgt
                                      : dut.u_bpu.u_ftb.ftb_jmp_target_p2;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      if (orc_on && orc_p1_den[s]) o_p1_ubtb[s].br_taken = orc_p1_dir[s];
      if (orc_on && orc_p1_ten[s]) o_p1_ubtb[s].target   = orc_p1_tgt[s];
      o_p1_lp[s] = dut.u_bpu.u_loop_pred.pred_p1[s];
      if (orc_on && orc_p1_den[s]) o_p1_lp[s].lp_pred_taken = orc_p1_dir[s];
      o_p1_tosv[s] = (orc_on && orc_p1_ret[s]) ? orc_p1_dir[s]
                                               : sh_tos_val[s];
      o_p1_tosa[s] = (orc_on && orc_p1_ret[s]) ? orc_p1_tgt[s]
                                               : sh_tos_addr[s];
      o_p2_lp[s] = dut.u_bpu.u_loop_pred.pred_p2[s];
      if (orc_on && orc_p2_den[s]) o_p2_lp[s].lp_pred_taken = orc_p2_dir[s];
      o_p2_tage[s] = dut.u_bpu.u_tage.tage_pred_meta_p2[s];
      if (orc_on && orc_p2_den[s]) o_p2_tage[s].tage_pred_tkn = orc_p2_dir[s];
      o_p2_ftk[s]  = (orc_on && orc_p2_den[s])
                   ? orc_p2_dir[s]
                   : ((s == 0) ? dut.u_bpu.u_ftb.ftb_br0_taken_p2
                               : dut.u_bpu.u_ftb.ftb_br1_taken_p2);
      o_p2_ftg[s]  = (orc_on && orc_p2_ten[s])
                   ? orc_p2_tgt[s]
                   : ((s == 0) ? dut.u_bpu.u_ftb.ftb_br0_target_p2
                               : dut.u_bpu.u_ftb.ftb_br1_target_p2);
      o_p2_ras[s]  = (orc_on && orc_p2_ten[s])
                   ? orc_p2_tgt[s]
                   : dut.u_bpu.u_ras.ras_pop_addr_p2[s];
      o_p2_it[s] = dut.u_bpu.u_ittage.ittage_pred_meta_p2[s];
      if (orc_on && orc_p2_ten[s]) begin
        o_p2_it[s].ittage_prm_tgt = orc_p2_tgt[s][VA_WIDTH-1:1];
        o_p2_it[s].ittage_alt_tgt = orc_p2_tgt[s][VA_WIDTH-1:1];
      end
      o_p3_sc[s] = dut.u_bpu.u_sc.sc_pred_meta_p3[s];
      if (orc_on && orc_p3_den[s]) o_p3_sc[s].sc_pred_tkn = orc_p3_dir[s];
    end
  end

  // The forces: the predictor outputs the stage logic reads, by slot.
  //   p1 (p1_form_comb): r_ubtb_pred_p1 (.br_taken, .target), the loop
  //      predictor's pred_p1 (.lp_pred_taken), the RAS top of stack
  //      r_ras_tos_val_p1 and r_ras_tos_addr_p1
  //   p2 (p2_class_comb, p2_succ_comb): w_lp_pred_p2 (.lp_pred_taken),
  //      w_tage_pred_meta_p2 (.tage_pred_tkn), the FTB br direction and
  //      target w_ftb_br_taken_p2 and _target_p2, the FTB jump target
  //      w_ftb_jmp_target_p2, the RAS pop address w_ras_pop_addr_p2,
  //      w_ittage_pred_meta_p2 (.ittage_prm_tgt, .ittage_alt_tgt)
  //   p3 (p3_redir_comb, p3_slot_comb): w_sc_pred_meta_p3 (.sc_pred_tkn)
  initial begin : oracle_p1_ubtb
    force dut.u_bpu.r_ubtb_pred_p1 = o_p1_ubtb;
  end
  for (genvar gs = 0; gs < NUM_PRED_SLOTS; gs++) begin : g_oracle
    initial begin
      force dut.u_bpu.w_lp_pred_p1[gs]          = o_p1_lp[gs];
      force dut.u_bpu.r_ras_tos_val_p1[gs]      = o_p1_tosv[gs];
      force dut.u_bpu.r_ras_tos_addr_p1[gs]     = o_p1_tosa[gs];
      force dut.u_bpu.w_lp_pred_p2[gs]          = o_p2_lp[gs];
      force dut.u_bpu.w_tage_pred_meta_p2[gs]   = o_p2_tage[gs];
      force dut.u_bpu.w_ftb_br_taken_p2[gs]     = o_p2_ftk[gs];
      force dut.u_bpu.w_ftb_br_target_p2[gs]    = o_p2_ftg[gs];
      force dut.u_bpu.w_ras_pop_addr_p2[gs]     = o_p2_ras[gs];
      force dut.u_bpu.w_ittage_pred_meta_p2[gs] = o_p2_it[gs];
      force dut.u_bpu.w_sc_pred_meta_p3[gs]     = o_p3_sc[gs];
    end
  end
  initial begin : oracle_jump
    force dut.u_bpu.w_ftb_jmp_target_p2 = o_p2_jt;
  end

  // ---- THE RAS CLASSIFICATION (BP-151), by hierarchical reference ----
  // Read only: nothing here drives the design. The RAS is not inlined
  // (perf.vlt), so its ports and internal variables are its own.
  always_comb begin : ras_class
    rc_tosr   = dut.u_bpu.u_ras.tosr;
    rc_tosw   = dut.u_bpu.u_ras.tosw;
    rc_bos    = dut.u_bpu.u_ras.bos;
    rc_csp    = dut.u_bpu.u_ras.csp;
    rc_ccnt   = dut.u_bpu.u_ras.c_cnt;
    for (int i = 0; i < RAS_SPEC_ENTRIES; i++) begin
      rc_spec_addr[i] = dut.u_bpu.u_ras.spec_ret_addr[i];
      rc_spec_nos[i]  = dut.u_bpu.u_ras.spec_nos[i];
      rc_spec_rctr[i] = dut.u_bpu.u_ras.spec_rctr[i];
      rc_spec_bot[i]  = dut.u_bpu.u_ras.spec_bot[i];
    end
    for (int i = 0; i < RAS_COMMIT_ENTRIES; i++) begin
      rc_cmt_addr[i] = dut.u_bpu.u_ras.commit_ret_addr[i];
    end
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      rc_p2_val[s]       = dut.u_bpu.u_ras.ras_pred_val_p2[s];
      rc_p2_type[s]      = 3'(dut.u_bpu.u_ras.ras_br_type_p2[s]);
      rc_p2_ft[s]        = dut.u_bpu.u_ras.ras_fall_through_p2[s];
      rc_p2_popv[s]      = dut.u_bpu.u_ras.ras_pop_valid_p2[s];
      rc_p2_popa[s]      = dut.u_bpu.u_ras.ras_pop_addr_p2[s];
      rc_p2_op[s]        = dut.u_bpu.u_ras.p2_op[s];
      rc_p2_inc[s]       = dut.u_bpu.u_ras.p2_push_inc[s];
      rc_p2_sat[s]       = dut.u_bpu.u_ras.p2_push_sat[s];
      rc_p2_pre[s]       = dut.u_bpu.u_ras.p2_pre_tosr[s];
      rc_p2_pre_empty[s] = dut.u_bpu.u_ras.p2_pre_empty[s];
      rc_p3_val[s]       = dut.u_bpu.u_ras.ras_pred_val_p3[s];
      rc_p3_type[s]      = 3'(dut.u_bpu.u_ras.ras_br_type_p3[s]);
      rc_p3_op[s]        = dut.u_bpu.u_ras.p3_op_q[s];
      rc_p3_ft[s]        = dut.u_bpu.u_ras.p3_fallthr_q[s];
    end
    for (int p = 0; p < 4 * NUM_PRED_SLOTS; p++) begin
      rc_we[p]    = dut.u_bpu.u_ras.sp_we[p];
      rc_waddr[p] = dut.u_bpu.u_ras.sp_waddr[p];
    end
    rc_keep    = dut.u_bpu.u_ras.ras_p2_keep;
    rc_ftb_p2  = dut.u_bpu.w_ftb_valid_p2;
    rc_rs_val  = dut.u_bpu.u_ras.ras_restore_val;
    rc_rs_tosr = dut.u_bpu.u_ras.ras_restore_snapshot.tosr;
    rc_rs_tosw = dut.u_bpu.u_ras.ras_restore_snapshot.tosw;
    rc_rs_bos  = dut.u_bpu.u_ras.ras_restore_snapshot.bos;
    rc_cm_val  = dut.u_bpu.u_ras.ras_commit_val;
    rc_cm_type = 3'(dut.u_bpu.u_ras.ras_commit_br_type);
    rc_cm_addr = dut.u_bpu.u_ras.ras_commit_ret_addr;
    rc_cm_tosr = dut.u_bpu.u_ras.ras_commit_snapshot.tosr;
    rc_cm_bos  = dut.u_bpu.u_ras.ras_commit_snapshot.bos;
    rc_cm_idx  = dut.u_ftq.u_entry.commit_rd_idx;
    rc_rs_idx  = dut.u_ftq.ftq_rollback_idx;
    rc_pd_pos  = dut.u_ftq.u_ifu.ifu_ftq_mis_pos;
  end

endmodule : perf_top
