// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fe_tb_dut.svh -- the clock, reset, fe_top and the walker
//
// A SHARED FRONT-END TESTBENCH MODEL (DOC-001, fe_demo_tb_decisions.md
// FDT-4). Not a compilation unit: it is included inside the body of
// module tb, after the package imports, by tb_fe_top
// (rtl/core/frontend/fe_top/tb) and tb_fe_demo (examples/fe_demo/tb),
// in the order those files give. The text was moved here from
// tb_fe_top.sv unchanged except where this header says otherwise.
//
// Holds: clk and rstn; every fe_top port; the fe_top instance; the
// page table walker beside it on the itlb_l2t_* group, with its
// memory port and its CSR group (MMU-1a, MMU-24a); the cycle count;
// tname, the running program's name, which the models print.
// ===================================================================

  logic clk;
  logic rstn;
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ---- DUT ports ------------------------------------------------------
  decode_pkt_t     [SLOTS-1:0] decode_bundle;
  vec_decode_pkt_t [SLOTS-1:0] vec_decode_bundle;
  logic            [SLOTS-1:0] is_vector;
  ifu_pd_pkt_t                 pd_out [0:SLOTS-1];
  logic            [SLOTS-1:0] vtype_hazard;
  logic                        dec_ibuf_rdy;
  logic [NUM_RESOLVE_PORTS-1:0] bkend_ftq_rsv_val;
  ftq_resolve_t                bkend_ftq_rsv [0:NUM_RESOLVE_PORTS-1];
  logic [NUM_RESOLVE_PORTS-1:0] ftq_bkend_rsv_rdy;
  logic                        bkend_ftq_redir_val;
  logic [FTQ_IDX_BITS-1:0]     bkend_ftq_redir_idx;
  logic [FTB_BR_POS_BITS-1:0]  bkend_ftq_redir_pos;
  logic [VA_WIDTH-1:0]         bkend_ftq_redir_pc;
  logic                        bkend_ftq_redir_self;
  ftq_redir_cause_e            bkend_ftq_redir_cause;
  logic                        bkend_ftq_redir_taken;   // BP-121
  logic                        bkend_ftq_commit_val;
  logic [FTQ_PTR_BITS-1:0]     bkend_ftq_commit_idx;
  logic                        itlb_l2t_req_val;
  logic                        itlb_l2t_req_rdy;
  logic [VA_WIDTH-13:0]        itlb_l2t_vpn;
  logic [ASID_WIDTH-1:0]       itlb_l2t_asid;
  logic [VMID_WIDTH-1:0]       itlb_l2t_vmid;
  logic                        itlb_l2t_v;
  logic [1:0]                  itlb_l2t_tag;
  logic                        l2t_itlb_rsp_val;
  logic [1:0]                  l2t_itlb_tag;
  logic [1:0]                  l2t_itlb_status;
  logic [PPN_WIDTH-1:0]        l2t_itlb_ppn;
  logic [2:0]                  l2t_itlb_size;   // IL-7
  logic [PERM_WIDTH-1:0]       l2t_itlb_perm;
  logic [1:0]                  l2t_itlb_pbmt;
  logic [CAUSE_WIDTH-1:0]      l2t_itlb_cause;
  logic [FAULT_GPA_WIDTH-1:0]  l2t_itlb_gpa;     // MMU-23, BP-124
  logic [1:0]                  l2t_itlb_gpa_imp;      // BP-123
  logic                        cmt_ifu_maint_val;     // BP-123
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
  // The CSR groups (SYS-001, csr_decisions.md CSR-2), driven only by
  // csr_sync() from the csr_tb_pkg pack functions.
  fe_csr_t                     fe_csr;
  fe_cfg_t                     fe_cfg;
  logic                        bkend_itlb_inv_val;
  logic [1:0]                  bkend_itlb_inv_op;
  logic                        bkend_itlb_inv_rs1_nz;
  logic                        bkend_itlb_inv_rs2_nz;
  logic [VA_WIDTH-13:0]        bkend_itlb_inv_vpn;
  logic [ASID_WIDTH-1:0]       bkend_itlb_inv_asid;
  logic [VMID_WIDTH-1:0]       bkend_itlb_inv_vmid;
  logic                        ftq_full;
  logic                        ftq_empty;

  fe_top dut (.*);

  // ---- the page table walker, beside the top (MMU-1a, BP-123) -------
  // itlb_l2t_acc and itlb_l2t_priv are the ITLB's (IL-3d), carried by
  // fe_top (BP-124); BP-123 tied the access type here.
  logic [1:0]                  itlb_l2t_acc;
  logic [1:0]                  itlb_l2t_priv;
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

  // The walker reads the same PMP registers the ITLB does: one CSR
  // file, two inputs (MMU-11a, MMU-24a). Since SYS-001 both groups are
  // packed from the one csr_tb_pkg shadow.
  ptw u_ptw (.*);

  // The running program's name, printed by the models, and the cycle
  // count, zero in reset.
  string tname;
  int    cyc;

  always @(posedge clk) cyc <= rstn ? cyc + 1 : 0;
