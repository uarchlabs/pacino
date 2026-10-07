// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// IFU translation pipeline and translation queue (BP-116).
// ifu_decisions.md IFU-23a, IFU-24, IFU-25, IFU-26, IFU-27, IFU-U5;
// itlb_ifu_interfaces.md IT-1 to IT-14; ftq_ifu_interfaces.md 4.1.
//
// THE TRANSLATION PIPELINE RUNS AHEAD OF FETCH (IFU-23a). It takes
// the FTQ's translation request (4.1), looks the block up in the ITLB
// and enqueues the result. The fetch side reads the queue head at F0
// and pops it when the block's L1I request issues (IFU-U5).
//
// ONE BLOCK IN THE ITLB AT A TIME, TWO LOOKUPS AT MOST. A block whose
// 34-byte window (IFU-8) runs into the next page needs two lookups,
// issued on successive cycles on the one port (IT-1) and tagged 0 for
// the block's own page and 1 for the next (IT-2). Responses return
// in either order (IT-3) and are attributed by the tag, which works
// only while one block is in flight: two blocks would put two
// requests on one tag. A new block's first lookup may be presented in
// the cycle the previous block's last response arrives, so a one-cycle
// ITLB hit sustains one block per cycle (IFU-U5).
//
// A MISS ENDS THE TRANSACTION (IT-7) and the lookup is presented
// again from the next cycle (IT-8). A hit or a fault is final. The
// result is enqueued when every lookup the block needs is final.
//
// THE QUEUE (IFU-25, IFU-U5) is XQ_DEPTH entries, default 4, in
// order. Per block: the index and pc, whether the block crosses a
// page, and per page the PPN, the fault (as ifu_fault_e), the GPA of
// a guest-page fault and the uncached mark of IFU-26. The page-1
// fields are meaningful only for a crossing block.
//
// IFU-26. A block is MARKED when a page it uses that hit is not both
// cacheable and idempotent (IT-11). The uncached path is TD#135 and
// is not built: an assertion fires if a marked block reaches F0.
//
// FLUSH (IFU-27, ftq_ifu_interfaces.md 5). The block in lookup and
// the whole queue are discarded. TD#134 is deferred: a flush with a
// lookup outstanding is an assertion failure, so a response can never
// return for a discarded block. A translation request presented in a
// flush cycle is ignored (ftq_ifu_interfaces.md 5, TD#138), and no
// lookup is presented in a flush cycle.
//
// THE LOOKUP VPN IS EVERY FETCH ADDRESS BIT ABOVE THE PAGE OFFSET,
// [VA_WIDTH-1:12], VA_WIDTH-12 = 29 bits (itlb_ifu_interfaces.md
// IT-16), on both lookups of a crossing block. It is not VPN_WIDTH
// (27, the Sv39 VPN): with V=1 and vsatp.MODE=Bare the fetch PC is a
// 41-bit guest physical address, and with V=0 and satp.MODE=Bare a
// fetch address above bit 35 must reach the PMA check to fault
// (FE-19). The ITLB, not the IFU, decides which bits a regime uses.
// Ruled session-074, TD#146, built BP-117; BP-116 drove VPN_WIDTH.
//
// PMA bit positions are not fixed by any document (IT-10 names the
// four attributes, MMU-13 their order). This module takes them in
// MMU-13's order from bit 0. See the BP-116 Results Capture.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ifu_xlate #(
  parameter int XQ_DEPTH = 4                 // IFU-U5
) (
  input  logic                     clk,
  input  logic                     rstn,

  // ---- ftq_ifu_interfaces.md 4.1 -----------------------------------
  input  logic                     ftq_ifu_xlate_val,
  output logic                     ftq_ifu_xlate_rdy,
  input  logic [VA_WIDTH-1:0]      ftq_ifu_xlate_pc,
  input  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_xlate_idx,

  // ---- ftq_ifu_interfaces.md 5 -------------------------------------
  input  logic                     ftq_ifu_flush_val,

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

  // ---- the queue head, to the fetch side ----------------------------
  output logic                     xq_val,
  output logic [FTQ_IDX_BITS-1:0]  xq_idx,
  output logic [VA_WIDTH-1:0]      xq_pc,
  output logic                     xq_cross,
  output logic [PPN_WIDTH-1:0]     xq_ppn0,
  output ifu_fault_e               xq_fault0,
  output logic [GPA_WIDTH-1:0]     xq_gpa0,
  output logic [PPN_WIDTH-1:0]     xq_ppn1,
  output ifu_fault_e               xq_fault1,
  output logic [GPA_WIDTH-1:0]     xq_gpa1,
  output logic                     xq_uc,
  input  logic                     xq_pop
);

  localparam int XQ_PTR = (XQ_DEPTH > 1) ? $clog2(XQ_DEPTH) : 1;
  localparam int XQ_CNT = $clog2(XQ_DEPTH + 1);

  // The lookup VPN width, IT-16: the fetch address above the offset.
  localparam int LK_VPN_W = VA_WIDTH - 12;

  // itlb_ifu_status, IT-4.
  localparam logic [1:0] ST_HIT  = 2'b00;
  localparam logic [1:0] ST_MISS = 2'b01;

  // Exception codes of IT-6.
  localparam logic [CAUSE_WIDTH-1:0] CAUSE_ACCESS = CAUSE_WIDTH'(1);
  localparam logic [CAUSE_WIDTH-1:0] CAUSE_PAGE   = CAUSE_WIDTH'(12);
  localparam logic [CAUSE_WIDTH-1:0] CAUSE_GUEST  = CAUSE_WIDTH'(20);

  // PMA bits, MMU-13 order (see the header).
  localparam int PMA_CACHEABLE  = 0;
  localparam int PMA_IDEMPOTENT = 3;

  // The last 32 bytes of a page: a window starting here reaches the
  // next page with its 17th halfword (IFU-8).
  localparam logic [11:0] CROSS_FROM = 12'hFE0;

  // -----------------------------------------------------------------
  // One page's result.
  // -----------------------------------------------------------------
  typedef struct packed {
    logic [PPN_WIDTH-1:0] ppn;
    ifu_fault_e           fault;
    logic [GPA_WIDTH-1:0] gpa;
    logic                 uc;      // hit, not cacheable and idempotent
  } pg_res_t;

  typedef struct packed {
    logic [FTQ_IDX_BITS-1:0] idx;
    logic [VA_WIDTH-1:0]     pc;
    logic                    xpage;
    pg_res_t                 pg0;
    pg_res_t                 pg1;
  } xq_ent_t;

  // ---- the block in lookup ----------------------------------------
  logic                    r_cur_val;
  logic [FTQ_IDX_BITS-1:0] r_cur_idx;
  logic [VA_WIDTH-1:0]     r_cur_pc;
  logic                    r_cur_cross;
  logic [1:0]              r_need;     // per tag: no final result yet
  logic [1:0]              r_out;      // per tag: lookup in flight
  pg_res_t                 r_res [0:1];

  // ---- the queue -----------------------------------------------------
  xq_ent_t                 r_q [0:XQ_DEPTH-1];
  logic [XQ_PTR-1:0]       r_rd;
  logic [XQ_PTR-1:0]       r_wr;
  logic [XQ_CNT-1:0]       r_cnt;

  // ---- this cycle ----------------------------------------------------
  logic [1:0]              w_need;
  logic [1:0]              w_out;
  logic                    w_rsp_final;
  pg_res_t                 w_rsp_res;
  pg_res_t                 w_res [0:1];
  logic                    w_done;
  logic                    w_accept;
  logic                    w_new_cross;
  logic [LK_VPN_W-1:0]     w_cur_vpn;
  logic                    w_req_new;
  logic                    w_req_fire;
  xq_ent_t                 w_enq;

  function automatic ifu_fault_e map_cause(
      input logic [CAUSE_WIDTH-1:0] c);
    if (c == CAUSE_PAGE)       return IFU_FAULT_PAGE;
    else if (c == CAUSE_GUEST) return IFU_FAULT_GUEST_PAGE;
    else                       return IFU_FAULT_ACCESS;  // 1, and any
  endfunction

  always_comb begin : step
    // ---- the response, IT-3 / IT-4 / IT-7 ---------------------------
    w_rsp_final   = itlb_ifu_rsp_val && (itlb_ifu_status != ST_MISS);
    w_rsp_res.gpa = '0;
    w_rsp_res.uc  = 1'b0;
    if (itlb_ifu_status == ST_HIT) begin
      w_rsp_res.fault = IFU_FAULT_NONE;
      w_rsp_res.uc    = !(itlb_ifu_pma[PMA_CACHEABLE] &&
                          itlb_ifu_pma[PMA_IDEMPOTENT]);
    end else begin
      // 2'b10 fault; 2'b11 is reserved and treated as a fault.
      w_rsp_res.fault = map_cause(itlb_ifu_cause);
      if (itlb_ifu_cause == CAUSE_GUEST) w_rsp_res.gpa = itlb_ifu_gpa;
    end
    w_rsp_res.ppn = (itlb_ifu_status == ST_HIT) ? itlb_ifu_ppn : '0;

    for (int t = 0; t < 2; t++) begin
      w_need[t] = r_need[t] &&
                  !(w_rsp_final && (itlb_ifu_tag == t[0]));
      w_out[t]  = r_out[t] &&
                  !(itlb_ifu_rsp_val && (itlb_ifu_tag == t[0]));
      w_res[t]  = (w_rsp_final && (itlb_ifu_tag == t[0])) ? w_rsp_res
                                                          : r_res[t];
    end
    w_done = r_cur_val && !w_need[0] && !w_need[1];

    // ---- accept the next block (4.1) ----------------------------------
    // Room is counted against the current count with the block in
    // lookup included, so an enqueue never meets a full queue.
    ftq_ifu_xlate_rdy = (!r_cur_val || w_done) &&
                        ((32'(r_cnt) + (r_cur_val ? 32'd1 : 32'd0)) <
                         XQ_DEPTH);
    w_accept    = ftq_ifu_xlate_val && ftq_ifu_xlate_rdy &&
                  !ftq_ifu_flush_val;
    w_new_cross = (ftq_ifu_xlate_pc[11:0] >= CROSS_FROM);

    // ---- the lookup presented this cycle (IT-1, IT-13) ----------------
    w_cur_vpn        = r_cur_pc[12 +: LK_VPN_W];
    ifu_itlb_req_val = 1'b0;
    ifu_itlb_tag     = 1'b0;
    ifu_itlb_vpn     = w_cur_vpn;
    w_req_new        = 1'b0;
    if (r_cur_val && w_need[0] && !w_out[0]) begin
      ifu_itlb_req_val = 1'b1;
    end else if (r_cur_val && w_need[1] && !w_out[1]) begin
      ifu_itlb_req_val = 1'b1;
      ifu_itlb_tag     = 1'b1;
      ifu_itlb_vpn     = w_cur_vpn + LK_VPN_W'(1);
    end else if (w_accept) begin
      ifu_itlb_req_val = 1'b1;
      ifu_itlb_vpn     = ftq_ifu_xlate_pc[12 +: LK_VPN_W];
      w_req_new        = 1'b1;
    end
    if (ftq_ifu_flush_val) ifu_itlb_req_val = 1'b0;
    w_req_fire = ifu_itlb_req_val && ifu_itlb_req_rdy;

    // ---- the entry enqueued when the block in lookup completes --------
    w_enq.idx   = r_cur_idx;
    w_enq.pc    = r_cur_pc;
    w_enq.xpage = r_cur_cross;
    w_enq.pg0   = w_res[0];
    w_enq.pg1   = r_cur_cross ? w_res[1] : '0;

    // ---- the queue head ----------------------------------------------
    xq_val    = (r_cnt != '0);
    xq_idx    = r_q[r_rd].idx;
    xq_pc     = r_q[r_rd].pc;
    xq_cross  = r_q[r_rd].xpage;
    xq_ppn0   = r_q[r_rd].pg0.ppn;
    xq_fault0 = r_q[r_rd].pg0.fault;
    xq_gpa0   = r_q[r_rd].pg0.gpa;
    xq_ppn1   = r_q[r_rd].pg1.ppn;
    xq_fault1 = r_q[r_rd].pg1.fault;
    xq_gpa1   = r_q[r_rd].pg1.gpa;
    // IFU-26. A faulting page is never fetched and does not mark.
    xq_uc     = (r_q[r_rd].pg0.uc &&
                 (r_q[r_rd].pg0.fault == IFU_FAULT_NONE)) ||
                (r_q[r_rd].xpage && r_q[r_rd].pg1.uc &&
                 (r_q[r_rd].pg1.fault == IFU_FAULT_NONE));
  end

  // -----------------------------------------------------------------
  // State.
  // -----------------------------------------------------------------
  function automatic logic [XQ_PTR-1:0] nxt(input logic [XQ_PTR-1:0] p);
    return (32'(p) == XQ_DEPTH - 1) ? '0 : p + XQ_PTR'(1);
  endfunction

  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      r_cur_val   <= 1'b0;
      r_cur_idx   <= '0;
      r_cur_pc    <= '0;
      r_cur_cross <= 1'b0;
      r_need      <= '0;
      r_out       <= '0;
      r_res[0]    <= '0;
      r_res[1]    <= '0;
      r_rd        <= '0;
      r_wr        <= '0;
      r_cnt       <= '0;
    end else if (ftq_ifu_flush_val) begin
      r_cur_val   <= 1'b0;
      r_need      <= '0;
      r_out       <= '0;
      r_rd        <= '0;
      r_wr        <= '0;
      r_cnt       <= '0;
    end else begin
      r_res[0] <= w_res[0];
      r_res[1] <= w_res[1];

      if (w_done) begin
        r_q[r_wr] <= w_enq;
        r_wr      <= nxt(r_wr);
      end
      if (xq_pop && xq_val) begin
        r_rd <= nxt(r_rd);
      end
      r_cnt <= r_cnt + XQ_CNT'(w_done) - XQ_CNT'(xq_pop && xq_val);

      if (w_accept) begin
        r_cur_val   <= 1'b1;
        r_cur_idx   <= ftq_ifu_xlate_idx;
        r_cur_pc    <= ftq_ifu_xlate_pc;
        r_cur_cross <= w_new_cross;
        r_need      <= {w_new_cross, 1'b1};
        r_out       <= {1'b0, w_req_new && w_req_fire};
        r_res[0]    <= '0;
        r_res[1]    <= '0;
      end else if (w_done) begin
        r_cur_val   <= 1'b0;
        r_need      <= '0;
        r_out       <= '0;
      end else begin
        r_need <= w_need;
        for (int t = 0; t < 2; t++) begin
          r_out[t] <= w_out[t] ||
                      (w_req_fire && !w_req_new && (ifu_itlb_tag == t[0]));
        end
      end
    end
  end

endmodule : ifu_xlate
