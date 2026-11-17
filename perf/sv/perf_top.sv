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
//   pq_*         for each decode slot, the prediction slots of the FTQ
//                entry it names (pd_out[i].ftq_idx), from
//                dut.u_ftq.u_entry.r_arr: slot_valid, taken, pos,
//                br_type, target and pred_src (bp_ftq_slot_t,
//                bp_structs_pkg.sv). pred_src is the predictor that
//                supplied the final prediction; the gasket reads the
//                slot at the instruction's position as the backend
//                takes it, before its resolution rewrites the slot
//   obs_walk     a walk request accepted, itlb_l2t_req_val and _rdy
//   obs_pd_redir the predecode redirect, dut.ifu_ftq_mis_val
//   obs_p2_redir, obs_p3_redir
//                a BPU override at p2 or p3, any slot's valid of
//                dut.bpu_redir_p2 and dut.bpu_redir_p3
//   obs_l1i_req, obs_l1i_paddr, obs_l1i_rdy
//                the IFU's request on the L1I core link,
//                dut.ifu_l1i_req_val, _paddr, _rdy (the I-cache switch,
//                PF-19, reads them)
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
  // The prediction slots of the FTQ entry each decode slot names.
  output logic [NUM_PRED_SLOTS-1:0]   pq_val  [SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]   pq_taken [SLOTS],
  output logic [FTB_BR_POS_BITS-1:0]  pq_pos  [SLOTS][NUM_PRED_SLOTS],
  output logic [2:0]                  pq_type [SLOTS][NUM_PRED_SLOTS],
  output logic [2:0]                  pq_src  [SLOTS][NUM_PRED_SLOTS],
  output logic [VA_WIDTH-1:0]         pq_tgt  [SLOTS][NUM_PRED_SLOTS],
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
  output logic                        ftq_empty
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
    for (int i = 0; i < SLOTS; i++) begin
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        pq_val[i][s]   = dut.u_ftq.u_entry.r_arr[pd_out[i].ftq_idx].slot[s]
                           .slot_valid;
        pq_taken[i][s] = dut.u_ftq.u_entry.r_arr[pd_out[i].ftq_idx].slot[s]
                           .taken;
        pq_pos[i][s]   = dut.u_ftq.u_entry.r_arr[pd_out[i].ftq_idx].slot[s]
                           .pos;
        pq_type[i][s]  = 3'(dut.u_ftq.u_entry.r_arr[pd_out[i].ftq_idx]
                             .slot[s].br_type);
        pq_src[i][s]   = 3'(dut.u_ftq.u_entry.r_arr[pd_out[i].ftq_idx]
                             .slot[s].pred_src);
        pq_tgt[i][s]   = dut.u_ftq.u_entry.r_arr[pd_out[i].ftq_idx].slot[s]
                           .target;
      end
    end
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

endmodule : perf_top
