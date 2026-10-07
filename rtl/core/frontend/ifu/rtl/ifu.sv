// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Instruction fetch unit, structural top (BP-116). ifu_decisions.md.
//
// PURELY STRUCTURAL: no state and no logic. Each piece of state has
// one owner below, the rule ftq.sv follows (ftq_decisions.md 7.1):
//
//   ifu_xlate      the translation pipeline and the translation queue
//                  IFU-23a to IFU-27, IFU-U5
//   ifu_fetch      F0 (request, issue, coalescing) and the F1 block
//                  queue; forms F2. IFU-6 to IFU-10, TD-IFU-8/9
//   ifu_lbuf       the L1I identifier free list, the line buffer and
//                  the previous-request register. TD-IFU-7/8, IF-6/7
//   ifu_rvc_exp    the 17-position expander. IFU-1, IFU-4
//   ifu_predecode  the 16-position predecoder. IFU-3, IFU-16, DCD
//   ifu_f3         the F3 register, the straddle register, the
//                  prediction check and the ibuf vector. IFU-5,
//                  IFU-11, IFU-12, IFU-15
//   ifu_wb         the WB register. IFU-13, IFU-14, IFU-19, IFU-20
//
// THE FOUR BOUNDARIES carry the port names of ftq_ifu_interfaces.md
// (with ftq_ifu.sv's port list authoritative for names and widths),
// l1i_ifu_interfaces.md 4 and 5, itlb_ifu_interfaces.md 2 and
// ifu_ibuf_interfaces.md 2.
//
// THE FLUSH (IFU-28 to IFU-32, TD#134, BP-118) is applied by each
// owner from ftq_ifu_flush_idx and ftq_ifu_commit_ptr: a block older
// than the flush index survives in every structure, the rest are
// dropped in the flush cycle, L1I responses for dropped blocks are
// discarded as they land, and ITLB lookups of a dropped block are
// waited out before a new block is translated. ifu_wb needs no index:
// it is loaded only from an F3 transfer, which never happens in a
// flush cycle, and F3 keeps only survivors (IFU-32).
//
// NOT BUILT, by ruling (BP-116 Binding Decisions):
//   TD#135  the uncached path (IFU-21 to IFU-23). IFU-26 marking is
//           built; ifu_fetch_assert fires if a marked block reaches F0
//   TD#136  maintenance. The ports of l1i_ifu_interfaces.md 10 and 11
//           are not declared
//   prefetch  ifu_l1i_req_prefetch is driven 0
// ftq_ifu_commit_ptr is read for the flush ages; its IFU-22 use waits
// on TD#135.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ifu #(
  parameter int LB_DEPTH = 16,              // TD-IFU-7
  parameter int XQ_DEPTH = 4                // IFU-U5
) (
  input  logic                     clk,
  input  logic                     rstn,

  // ---- ftq_ifu_interfaces.md 4.1 -----------------------------------
  input  logic                     ftq_ifu_xlate_val,
  output logic                     ftq_ifu_xlate_rdy,
  input  logic [VA_WIDTH-1:0]      ftq_ifu_xlate_pc,
  input  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_xlate_idx,

  // ---- ftq_ifu_interfaces.md 4 -------------------------------------
  input  logic                     ftq_ifu_req_val,
  output logic                     ftq_ifu_req_rdy,
  input  logic [VA_WIDTH-1:0]      ftq_ifu_start_pc,
  input  logic [VA_WIDTH-1:0]      ftq_ifu_next_pc,
  input  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_idx,
  input  logic                     ftq_ifu_taken_val,
  input  logic [FTB_BR_POS_BITS-1:0] ftq_ifu_taken_pos,
  input  logic                     ftq_ifu_gen,
  input  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_commit_ptr,

  // ---- ftq_ifu_interfaces.md 5 -------------------------------------
  input  logic                     ftq_ifu_flush_val,
  input  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_flush_idx,

  // ---- ftq_ifu_interfaces.md 6 -------------------------------------
  output logic                     ifu_ftq_pdwb_val,
  output logic [FTQ_IDX_BITS-1:0]  ifu_ftq_pdwb_idx,
  output logic                     ifu_ftq_pdwb_gen,
  output ftq_pd_info_t             ifu_ftq_pd [0:FTQ_PD_WIDTH-1],
  output logic [FTQ_PD_WIDTH-1:0]  ifu_ftq_pd_range,
  output logic                     ifu_ftq_cfi_val,
  output logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_cfi_pos,
  output logic                     ifu_ftq_mis_val,
  output logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_mis_pos,
  output logic [VA_WIDTH-1:0]      ifu_ftq_target,
  output logic                     ifu_ftq_fault_val,
  output logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_fault_pos,

  // ---- l1i_ifu_interfaces.md 4 and 5 -------------------------------
  output logic                     ifu_l1i_req_val,
  input  logic                     ifu_l1i_req_rdy,
  output logic [REQ_ID_BITS-1:0]   ifu_l1i_req_id,
  output logic [PA_WIDTH-1:0]      ifu_l1i_req_paddr,
  output logic                     ifu_l1i_req_prefetch,
  input  logic                     l1i_ifu_rsp_val,
  input  logic [REQ_ID_BITS-1:0]   l1i_ifu_rsp_id,
  input  logic [L1I_LINE_BITS-1:0] l1i_ifu_rsp_data,
  input  logic                     l1i_ifu_rsp_err,

  // ---- itlb_ifu_interfaces.md 2 ------------------------------------
  output logic                     ifu_itlb_req_val,
  input  logic                     ifu_itlb_req_rdy,
  output logic [VA_WIDTH-13:0]     ifu_itlb_vpn,     // IT-16
  output logic                     ifu_itlb_tag,
  input  logic                     itlb_ifu_rsp_val,
  input  logic                     itlb_ifu_tag,
  input  logic [1:0]               itlb_ifu_status,
  input  logic [PPN_WIDTH-1:0]     itlb_ifu_ppn,
  input  logic [CAUSE_WIDTH-1:0]   itlb_ifu_cause,
  input  logic [GPA_WIDTH-1:0]     itlb_ifu_gpa,
  input  logic [PMA_WIDTH-1:0]     itlb_ifu_pma,

  // ---- ifu_ibuf_interfaces.md 2 ------------------------------------
  output logic                     ifu_ibuf_val,
  output logic [FTQ_PD_WIDTH-1:0]  ifu_ibuf_en,
  output ifu_pd_pkt_t              ifu_ibuf_slot [0:FTQ_PD_WIDTH-1],
  input  logic                     ibuf_ifu_rdy
);

  localparam int SB = $clog2(LB_DEPTH);

  // ---- translation queue head -----------------------------------------
  logic                     w_xq_val;
  logic [FTQ_IDX_BITS-1:0]  w_xq_idx;
  logic [VA_WIDTH-1:0]      w_xq_pc;
  logic                     w_xq_cross;
  logic [PPN_WIDTH-1:0]     w_xq_ppn0;
  ifu_fault_e               w_xq_fault0;
  logic [GPA_WIDTH-1:0]     w_xq_gpa0;
  logic [PPN_WIDTH-1:0]     w_xq_ppn1;
  ifu_fault_e               w_xq_fault1;
  logic [GPA_WIDTH-1:0]     w_xq_gpa1;
  logic                     w_xq_uc;
  logic                     w_xq_pop;

  // ---- line buffer -------------------------------------------------------
  logic                     w_alloc_val;
  logic [PA_WIDTH-1:L1I_OFFSET_BITS] w_alloc_line;
  logic                     w_alloc_ok;
  logic [REQ_ID_BITS-1:0]   w_alloc_id;
  logic [SB-1:0]            w_alloc_slot;
  logic                     w_att_val;
  logic [SB-1:0]            w_att_slot;
  logic                     w_prev_val;
  logic [PA_WIDTH-1:L1I_OFFSET_BITS] w_prev_line;
  logic [SB-1:0]            w_prev_slot;
  logic [SB-1:0]            w_rd_slot0;
  logic [SB-1:0]            w_rd_slot1;
  logic                     w_rd_landed0;
  logic                     w_rd_landed1;
  logic [L1I_LINE_BITS-1:0] w_rd_data0;
  logic [L1I_LINE_BITS-1:0] w_rd_data1;
  logic                     w_rd_err0;
  logic                     w_rd_err1;
  logic                     w_cons_val;
  logic                     w_cons_use0;
  logic                     w_cons_use1;
  logic [$clog2(2*LB_DEPTH+1)-1:0] w_kill_cnt [0:LB_DEPTH-1];

  // ---- F2 ----------------------------------------------------------------
  logic                     w_f2_val;
  logic                     w_f2_rdy;
  logic [FTQ_IDX_BITS-1:0]  w_f2_idx;
  logic                     w_f2_gen;
  logic [VA_WIDTH-1:0]      w_f2_start_pc;
  logic [VA_WIDTH-1:0]      w_f2_next_pc;
  logic                     w_f2_taken_val;
  logic [FTB_BR_POS_BITS-1:0] w_f2_taken_pos;
  logic [15:0]              w_f2_hw  [0:FTQ_PD_WIDTH];
  ifu_fault_e               w_f2_hwf [0:FTQ_PD_WIDTH];
  logic [FTQ_PD_WIDTH:0]    w_f2_hwpg;
  logic [VA_WIDTH-1:0]      w_f2_pc  [0:FTQ_PD_WIDTH];
  logic [GPA_WIDTH-1:0]     w_f2_gpa0;
  logic [GPA_WIDTH-1:0]     w_f2_gpa1;
  logic [FTQ_PD_WIDTH-1:0]  w_f2_rng;

  // ---- F3, expander and predecoder ------------------------------------
  logic [15:0]              w_f3_hw  [0:FTQ_PD_WIDTH];
  logic [VA_WIDTH-1:0]      w_f3_pc  [0:FTQ_PD_WIDTH-1];
  logic                     w_first_tail;
  logic [31:0]              w_exp    [0:FTQ_PD_WIDTH];
  logic                     w_exp_rvc [0:FTQ_PD_WIDTH];
  logic [FTQ_PD_WIDTH-1:0]  w_p_start;
  logic [FTQ_PD_WIDTH-1:0]  w_p_rvc;
  logic [1:0]               w_p_br   [0:FTQ_PD_WIDTH-1];
  logic [FTQ_PD_WIDTH-1:0]  w_p_call;
  logic [FTQ_PD_WIDTH-1:0]  w_p_ret;
  logic [VA_WIDTH-1:0]      w_p_tgt  [0:FTQ_PD_WIDTH-1];
  logic [FTQ_PD_WIDTH-1:0]  w_p_vset;
  logic [FTQ_PD_WIDTH-1:0]  w_p_vtype;

  // ---- WB --------------------------------------------------------------
  logic                     w_wb_load;
  logic [FTQ_IDX_BITS-1:0]  w_wb_idx;
  logic                     w_wb_gen;
  ftq_pd_info_t             w_wb_pd  [0:FTQ_PD_WIDTH-1];
  logic [FTQ_PD_WIDTH-1:0]  w_wb_range;
  logic                     w_wb_cfi_val;
  logic [FTQ_PD_POS_BITS-1:0] w_wb_cfi_pos;
  logic                     w_wb_mis_val;
  logic [FTQ_PD_POS_BITS-1:0] w_wb_mis_pos;
  logic [VA_WIDTH-1:0]      w_wb_target;
  logic                     w_wb_fault_val;
  logic [FTQ_PD_POS_BITS-1:0] w_wb_fault_pos;

  ifu_xlate #(.XQ_DEPTH(XQ_DEPTH)) u_xlate (
    .clk               (clk),
    .rstn              (rstn),
    .ftq_ifu_xlate_val (ftq_ifu_xlate_val),
    .ftq_ifu_xlate_rdy (ftq_ifu_xlate_rdy),
    .ftq_ifu_xlate_pc  (ftq_ifu_xlate_pc),
    .ftq_ifu_xlate_idx (ftq_ifu_xlate_idx),
    .ftq_ifu_flush_val (ftq_ifu_flush_val),
    .ftq_ifu_flush_idx (ftq_ifu_flush_idx),
    .ftq_ifu_commit_ptr (ftq_ifu_commit_ptr),
    .ifu_itlb_req_val  (ifu_itlb_req_val),
    .ifu_itlb_req_rdy  (ifu_itlb_req_rdy),
    .ifu_itlb_vpn      (ifu_itlb_vpn),
    .ifu_itlb_tag      (ifu_itlb_tag),
    .itlb_ifu_rsp_val  (itlb_ifu_rsp_val),
    .itlb_ifu_tag      (itlb_ifu_tag),
    .itlb_ifu_status   (itlb_ifu_status),
    .itlb_ifu_ppn      (itlb_ifu_ppn),
    .itlb_ifu_cause    (itlb_ifu_cause),
    .itlb_ifu_gpa      (itlb_ifu_gpa),
    .itlb_ifu_pma      (itlb_ifu_pma),
    .xq_val            (w_xq_val),
    .xq_idx            (w_xq_idx),
    .xq_pc             (w_xq_pc),
    .xq_cross          (w_xq_cross),
    .xq_ppn0           (w_xq_ppn0),
    .xq_fault0         (w_xq_fault0),
    .xq_gpa0           (w_xq_gpa0),
    .xq_ppn1           (w_xq_ppn1),
    .xq_fault1         (w_xq_fault1),
    .xq_gpa1           (w_xq_gpa1),
    .xq_uc             (w_xq_uc),
    .xq_pop            (w_xq_pop)
  );

  ifu_lbuf #(.LB_DEPTH(LB_DEPTH)) u_lbuf (
    .clk              (clk),
    .rstn             (rstn),
    .flush            (ftq_ifu_flush_val),
    .alloc_val        (w_alloc_val),
    .alloc_line       (w_alloc_line),
    .alloc_ok         (w_alloc_ok),
    .alloc_id         (w_alloc_id),
    .alloc_slot       (w_alloc_slot),
    .att_val          (w_att_val),
    .att_slot         (w_att_slot),
    .prev_val         (w_prev_val),
    .prev_line        (w_prev_line),
    .prev_slot        (w_prev_slot),
    .l1i_ifu_rsp_val  (l1i_ifu_rsp_val),
    .l1i_ifu_rsp_id   (l1i_ifu_rsp_id),
    .l1i_ifu_rsp_data (l1i_ifu_rsp_data),
    .l1i_ifu_rsp_err  (l1i_ifu_rsp_err),
    .rd_slot0         (w_rd_slot0),
    .rd_slot1         (w_rd_slot1),
    .rd_landed0       (w_rd_landed0),
    .rd_landed1       (w_rd_landed1),
    .rd_data0         (w_rd_data0),
    .rd_data1         (w_rd_data1),
    .rd_err0          (w_rd_err0),
    .rd_err1          (w_rd_err1),
    .cons_val         (w_cons_val),
    .cons_use0        (w_cons_use0),
    .cons_use1        (w_cons_use1),
    .kill_cnt         (w_kill_cnt)
  );

  ifu_fetch #(.LB_DEPTH(LB_DEPTH)) u_fetch (
    .clk                  (clk),
    .rstn                 (rstn),
    .flush                (ftq_ifu_flush_val),
    .flush_idx            (ftq_ifu_flush_idx),
    .commit_ptr           (ftq_ifu_commit_ptr),
    .ftq_ifu_req_val      (ftq_ifu_req_val),
    .ftq_ifu_req_rdy      (ftq_ifu_req_rdy),
    .ftq_ifu_start_pc     (ftq_ifu_start_pc),
    .ftq_ifu_next_pc      (ftq_ifu_next_pc),
    .ftq_ifu_idx          (ftq_ifu_idx),
    .ftq_ifu_taken_val    (ftq_ifu_taken_val),
    .ftq_ifu_taken_pos    (ftq_ifu_taken_pos),
    .ftq_ifu_gen          (ftq_ifu_gen),
    .xq_val               (w_xq_val),
    .xq_idx               (w_xq_idx),
    .xq_cross             (w_xq_cross),
    .xq_ppn0              (w_xq_ppn0),
    .xq_fault0            (w_xq_fault0),
    .xq_gpa0              (w_xq_gpa0),
    .xq_ppn1              (w_xq_ppn1),
    .xq_fault1            (w_xq_fault1),
    .xq_gpa1              (w_xq_gpa1),
    .xq_pop               (w_xq_pop),
    .alloc_val            (w_alloc_val),
    .alloc_line           (w_alloc_line),
    .alloc_ok             (w_alloc_ok),
    .alloc_id             (w_alloc_id),
    .alloc_slot           (w_alloc_slot),
    .att_val              (w_att_val),
    .att_slot             (w_att_slot),
    .prev_val             (w_prev_val),
    .prev_line            (w_prev_line),
    .prev_slot            (w_prev_slot),
    .rd_slot0             (w_rd_slot0),
    .rd_slot1             (w_rd_slot1),
    .rd_landed0           (w_rd_landed0),
    .rd_landed1           (w_rd_landed1),
    .rd_data0             (w_rd_data0),
    .rd_data1             (w_rd_data1),
    .rd_err0              (w_rd_err0),
    .rd_err1              (w_rd_err1),
    .cons_val             (w_cons_val),
    .cons_use0            (w_cons_use0),
    .cons_use1            (w_cons_use1),
    .kill_cnt             (w_kill_cnt),
    .ifu_l1i_req_val      (ifu_l1i_req_val),
    .ifu_l1i_req_rdy      (ifu_l1i_req_rdy),
    .ifu_l1i_req_id       (ifu_l1i_req_id),
    .ifu_l1i_req_paddr    (ifu_l1i_req_paddr),
    .ifu_l1i_req_prefetch (ifu_l1i_req_prefetch),
    .f2_val               (w_f2_val),
    .f2_rdy               (w_f2_rdy),
    .f2_idx               (w_f2_idx),
    .f2_gen               (w_f2_gen),
    .f2_start_pc          (w_f2_start_pc),
    .f2_next_pc           (w_f2_next_pc),
    .f2_taken_val         (w_f2_taken_val),
    .f2_taken_pos         (w_f2_taken_pos),
    .f2_hw                (w_f2_hw),
    .f2_hwf               (w_f2_hwf),
    .f2_hwpg              (w_f2_hwpg),
    .f2_pc                (w_f2_pc),
    .f2_gpa0              (w_f2_gpa0),
    .f2_gpa1              (w_f2_gpa1),
    .f2_rng               (w_f2_rng)
  );

  ifu_rvc_exp u_exp (
    .hw  (w_f3_hw),
    .exp (w_exp),
    .rvc (w_exp_rvc)
  );

  ifu_predecode u_pd (
    .hw          (w_f3_hw),
    .exp         (w_exp[0:FTQ_PD_WIDTH-1]),
    .pc          (w_f3_pc),
    .first_tail  (w_first_tail),
    .start       (w_p_start),
    .is_rvc      (w_p_rvc),
    .br_type     (w_p_br),
    .is_call     (w_p_call),
    .is_ret      (w_p_ret),
    .target      (w_p_tgt),
    .is_vsetvl   (w_p_vset),
    .needs_vtype (w_p_vtype)
  );

  ifu_f3 u_f3 (
    .clk           (clk),
    .rstn          (rstn),
    .flush         (ftq_ifu_flush_val),
    .flush_idx     (ftq_ifu_flush_idx),
    .commit_ptr    (ftq_ifu_commit_ptr),
    .f2_val        (w_f2_val),
    .f2_rdy        (w_f2_rdy),
    .f2_idx        (w_f2_idx),
    .f2_gen        (w_f2_gen),
    .f2_start_pc   (w_f2_start_pc),
    .f2_next_pc    (w_f2_next_pc),
    .f2_taken_val  (w_f2_taken_val),
    .f2_taken_pos  (w_f2_taken_pos),
    .f2_hw         (w_f2_hw),
    .f2_hwf        (w_f2_hwf),
    .f2_hwpg       (w_f2_hwpg),
    .f2_pc         (w_f2_pc),
    .f2_gpa0       (w_f2_gpa0),
    .f2_gpa1       (w_f2_gpa1),
    .f2_rng        (w_f2_rng),
    .f3_hw         (w_f3_hw),
    .f3_pc         (w_f3_pc),
    .first_tail    (w_first_tail),
    .x_exp         (w_exp),
    .p_start       (w_p_start),
    .p_rvc         (w_p_rvc),
    .p_br          (w_p_br),
    .p_call        (w_p_call),
    .p_ret         (w_p_ret),
    .p_tgt         (w_p_tgt),
    .p_vset        (w_p_vset),
    .p_vtype       (w_p_vtype),
    .ifu_ibuf_val  (ifu_ibuf_val),
    .ifu_ibuf_en   (ifu_ibuf_en),
    .ifu_ibuf_slot (ifu_ibuf_slot),
    .ibuf_ifu_rdy  (ibuf_ifu_rdy),
    .wb_load       (w_wb_load),
    .wb_idx        (w_wb_idx),
    .wb_gen        (w_wb_gen),
    .wb_pd         (w_wb_pd),
    .wb_range      (w_wb_range),
    .wb_cfi_val    (w_wb_cfi_val),
    .wb_cfi_pos    (w_wb_cfi_pos),
    .wb_mis_val    (w_wb_mis_val),
    .wb_mis_pos    (w_wb_mis_pos),
    .wb_target     (w_wb_target),
    .wb_fault_val  (w_wb_fault_val),
    .wb_fault_pos  (w_wb_fault_pos)
  );

  ifu_wb u_wb (
    .clk               (clk),
    .rstn              (rstn),
    .flush             (ftq_ifu_flush_val),
    .wb_load           (w_wb_load),
    .wb_idx            (w_wb_idx),
    .wb_gen            (w_wb_gen),
    .wb_pd             (w_wb_pd),
    .wb_range          (w_wb_range),
    .wb_cfi_val        (w_wb_cfi_val),
    .wb_cfi_pos        (w_wb_cfi_pos),
    .wb_mis_val        (w_wb_mis_val),
    .wb_mis_pos        (w_wb_mis_pos),
    .wb_target         (w_wb_target),
    .wb_fault_val      (w_wb_fault_val),
    .wb_fault_pos      (w_wb_fault_pos),
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
    .ifu_ftq_fault_pos (ifu_ftq_fault_pos)
  );

endmodule : ifu
