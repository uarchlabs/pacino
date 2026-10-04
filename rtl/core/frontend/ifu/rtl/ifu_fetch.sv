// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// IFU fetch side, F0 to F2 (BP-116). ifu_decisions.md IFU-6 to IFU-10,
// TD-IFU-8, TD-IFU-9, IFU-25, IFU-U5; ftq_ifu_interfaces.md 4;
// l1i_ifu_interfaces.md IF-4 to IF-8, IF-15, IF-23.
//
// OWNS the F0 register (the accepted FTQ request and its issue
// progress) and the in-order block queue that is F1. The identifier
// free list and the line buffer are ifu_lbuf's; this module asks for
// an allocation and reads the data back.
//
// F0 (IFU-10). Accept the FTQ request when F0 is free. Read the
// translation queue head, which is this block's translation: the FTQ
// issues fetch in entry order and only for an entry whose translation
// it presented earlier (ftq_ifu_interfaces.md 4, FQ-1), and the queue
// is in order. Then issue the L1I request for each line the block
// needs:
//   - one line, or two when the block starts in the upper half of a
//     line (IFU-7). The second line is the next line, or the second
//     page's first line for a block that crosses a page (IFU-25)
//   - a line on a faulting page is never requested (IF-8, IF-23)
//   - the block's FIRST line is compared with the PREVIOUS request
//     (ifu_lbuf) and reuses its slot on a match (TD-IFU-8). The
//     decision is taken once, on the first cycle the head is
//     available, and the reused slot is counted then, so the slot
//     cannot free while this block waits
//   - one request per cycle. The identifier, slot and address are
//     held from the cycle the request is first presented until the
//     L1I accepts it (IF-4)
// When every line is requested or reused the block enters F1 and the
// queue head is popped (IFU-U5: the entry frees when the block's L1I
// request issues).
//
// F1 is the block queue, BQ_DEPTH = 2 * LB_DEPTH: two blocks can share
// a line, so blocks in flight can outnumber slots (IFU-U5). F2 takes
// the oldest block once each line it uses has landed (TD-IFU-9: the
// line buffer is the reorder store, consumed in allocation order).
//
// F2 (IFU-10). Select the 17 halfwords of IFU-8 from the block's
// line(s) at the block's offset, compute each position's PC (F1's job
// in IFU-10, done here where the PCs are first needed and registered
// into F3), form each halfword's fault from its page's translation
// and its line's rsp_err (IF-15: a memory-side error is an access
// fault), and compute the base range:
//   predicted taken   positions 0 to taken_pos             DCD-13
//   not taken         positions whose address is below next_pc,
//                     the block end; all 16 when next_pc is not
//                     within 32 bytes after the start
// The fault cut of the range needs the start mask and is F3's.
//
// FLUSH. TD#134: everything is discarded and nothing is outstanding.
// A request presented in a flush cycle is ignored (ftq_ifu_interfaces
// .md 5, TD#138) and no L1I request is presented in a flush cycle.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ifu_fetch #(
  parameter int LB_DEPTH = 16
) (
  input  logic                     clk,
  input  logic                     rstn,
  input  logic                     flush,

  // ---- ftq_ifu_interfaces.md 4 -------------------------------------
  input  logic                     ftq_ifu_req_val,
  output logic                     ftq_ifu_req_rdy,
  input  logic [VA_WIDTH-1:0]      ftq_ifu_start_pc,
  input  logic [VA_WIDTH-1:0]      ftq_ifu_next_pc,
  input  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_idx,
  input  logic                     ftq_ifu_taken_val,
  input  logic [FTB_BR_POS_BITS-1:0] ftq_ifu_taken_pos,
  input  logic                     ftq_ifu_gen,

  // ---- the translation queue head, from ifu_xlate -------------------
  input  logic                     xq_val,
  input  logic [FTQ_IDX_BITS-1:0]  xq_idx,
  input  logic                     xq_cross,
  input  logic [PPN_WIDTH-1:0]     xq_ppn0,
  input  ifu_fault_e               xq_fault0,
  input  logic [GPA_WIDTH-1:0]     xq_gpa0,
  input  logic [PPN_WIDTH-1:0]     xq_ppn1,
  input  ifu_fault_e               xq_fault1,
  input  logic [GPA_WIDTH-1:0]     xq_gpa1,
  output logic                     xq_pop,

  // ---- ifu_lbuf --------------------------------------------------------
  output logic                     alloc_val,
  output logic [PA_WIDTH-1:L1I_OFFSET_BITS] alloc_line,
  input  logic                     alloc_ok,
  input  logic [REQ_ID_BITS-1:0]   alloc_id,
  input  logic [$clog2(LB_DEPTH)-1:0] alloc_slot,
  output logic                     att_val,
  output logic [$clog2(LB_DEPTH)-1:0] att_slot,
  input  logic                     prev_val,
  input  logic [PA_WIDTH-1:L1I_OFFSET_BITS] prev_line,
  input  logic [$clog2(LB_DEPTH)-1:0] prev_slot,
  output logic [$clog2(LB_DEPTH)-1:0] rd_slot0,
  output logic [$clog2(LB_DEPTH)-1:0] rd_slot1,
  input  logic                     rd_landed0,
  input  logic                     rd_landed1,
  input  logic [L1I_LINE_BITS-1:0] rd_data0,
  input  logic [L1I_LINE_BITS-1:0] rd_data1,
  input  logic                     rd_err0,
  input  logic                     rd_err1,
  output logic                     cons_val,
  output logic                     cons_use0,
  output logic                     cons_use1,

  // ---- l1i_ifu_interfaces.md 4 -------------------------------------
  output logic                     ifu_l1i_req_val,
  input  logic                     ifu_l1i_req_rdy,
  output logic [REQ_ID_BITS-1:0]   ifu_l1i_req_id,
  output logic [PA_WIDTH-1:0]      ifu_l1i_req_paddr,
  output logic                     ifu_l1i_req_prefetch,

  // ---- F2, to ifu_f3 -------------------------------------------------
  output logic                     f2_val,
  input  logic                     f2_rdy,
  output logic [FTQ_IDX_BITS-1:0]  f2_idx,
  output logic                     f2_gen,
  output logic [VA_WIDTH-1:0]      f2_start_pc,
  output logic [VA_WIDTH-1:0]      f2_next_pc,
  output logic                     f2_taken_val,
  output logic [FTB_BR_POS_BITS-1:0] f2_taken_pos,
  output logic [15:0]              f2_hw   [0:FTQ_PD_WIDTH],
  output ifu_fault_e               f2_hwf  [0:FTQ_PD_WIDTH],
  output logic [FTQ_PD_WIDTH:0]    f2_hwpg,
  output logic [VA_WIDTH-1:0]      f2_pc   [0:FTQ_PD_WIDTH],
  output logic [GPA_WIDTH-1:0]     f2_gpa0,
  output logic [GPA_WIDTH-1:0]     f2_gpa1,
  output logic [FTQ_PD_WIDTH-1:0]  f2_rng
);

  localparam int SB       = $clog2(LB_DEPTH);
  localparam int BQ_DEPTH = 2 * LB_DEPTH;
  localparam int BQ_PTR   = $clog2(BQ_DEPTH);
  localparam int BQ_CNT   = $clog2(BQ_DEPTH + 1);
  localparam int NPOS     = FTQ_PD_WIDTH + 1;               // 17
  localparam int LINE_W   = PA_WIDTH - L1I_OFFSET_BITS;     // 30

  // The block a not-taken range is measured against (DCD-13).
  localparam logic [VA_WIDTH-1:0] BLK_BYTES = VA_WIDTH'(FTB_BLOCK_BYTES);

  typedef struct packed {
    logic [FTQ_IDX_BITS-1:0]    idx;
    logic                       gen;
    logic [VA_WIDTH-1:0]        start_pc;
    logic [VA_WIDTH-1:0]        next_pc;
    logic                       taken_val;
    logic [FTB_BR_POS_BITS-1:0] taken_pos;
  } req_t;

  typedef struct packed {
    req_t                 rq;
    logic                 xpage;
    logic                 use0;
    logic [SB-1:0]        slot0;
    logic                 use1;
    logic [SB-1:0]        slot1;
    ifu_fault_e           fault0;
    logic [GPA_WIDTH-1:0] gpa0;
    ifu_fault_e           fault1;
    logic [GPA_WIDTH-1:0] gpa1;
  } blk_t;

  // ---- F0 ----------------------------------------------------------
  logic                r_f0_val;
  req_t                r_f0;
  logic                r_dec;          // reuse decision taken
  logic                r_reuse0;
  logic [SB-1:0]       r_reuse_slot;
  logic                r_done0;
  logic                r_done1;
  logic [SB-1:0]       r_slot0;
  logic [SB-1:0]       r_slot1;
  logic                r_pend;         // presented, not yet accepted
  logic                r_pend_which;
  logic [REQ_ID_BITS-1:0] r_pend_id;
  logic [SB-1:0]       r_pend_slot;
  logic [LINE_W-1:0]   r_pend_line;

  // ---- F1 ------------------------------------------------------------
  blk_t                r_bq [0:BQ_DEPTH-1];
  logic [BQ_PTR-1:0]   r_bq_rd;
  logic [BQ_PTR-1:0]   r_bq_wr;
  logic [BQ_CNT-1:0]   r_bq_cnt;

  // ---- F0 this cycle ----------------------------------------------
  logic                w_match;
  logic                w_two;
  logic [LINE_W-1:0]   w_line0;
  logic [LINE_W-1:0]   w_line1;
  logic                w_use0;
  logic                w_use1;
  logic                w_reuse0;
  logic [SB-1:0]       w_reuse_slot;
  logic                w_need0;
  logic                w_need1;
  logic                w_fresh;
  logic                w_fresh_which;
  logic                w_cur_which;
  logic [SB-1:0]       w_cur_slot;
  logic                w_fire;
  logic                w_fire0;
  logic                w_fire1;
  logic                w_push;
  logic                w_accept;
  logic                w_bq_full;
  blk_t                w_push_blk;

  always_comb begin : f0
    w_match = r_f0_val && xq_val && (xq_idx == r_f0.idx);
    w_two   = r_f0.start_pc[L1I_OFFSET_BITS-1];   // upper half, IFU-7
    w_line0 = {xq_ppn0, r_f0.start_pc[11:L1I_OFFSET_BITS]};
    w_line1 = xq_cross ? {xq_ppn1, (12-L1I_OFFSET_BITS)'(0)}
                       : w_line0 + LINE_W'(1);
    w_use0  = (xq_fault0 == IFU_FAULT_NONE);
    w_use1  = w_two && (xq_cross ? (xq_fault1 == IFU_FAULT_NONE)
                                 : w_use0);

    w_reuse0     = r_dec ? r_reuse0
                         : (w_use0 && prev_val && (prev_line == w_line0));
    w_reuse_slot = r_dec ? r_reuse_slot : prev_slot;
    w_need0      = w_use0 && !w_reuse0 && !r_done0;
    w_need1      = w_use1 && !r_done1;

    // The request presented this cycle: a held one, else a fresh
    // allocation for the first line still needed.
    w_fresh       = 1'b0;
    w_fresh_which = 1'b0;
    if (!r_pend && w_match && alloc_ok) begin
      if (w_need0) begin
        w_fresh = 1'b1;
      end else if (w_need1) begin
        w_fresh       = 1'b1;
        w_fresh_which = 1'b1;
      end
    end
    w_cur_which = r_pend ? r_pend_which : w_fresh_which;
    w_cur_slot  = r_pend ? r_pend_slot  : alloc_slot;

    ifu_l1i_req_val      = (r_pend || w_fresh) && !flush;
    ifu_l1i_req_id       = r_pend ? r_pend_id : alloc_id;
    ifu_l1i_req_paddr    = {(r_pend ? r_pend_line
                                    : (w_fresh_which ? w_line1 : w_line0)),
                            L1I_OFFSET_BITS'(0)};
    ifu_l1i_req_prefetch = 1'b0;          // prefetch is not in scope
    alloc_val  = w_fresh && !flush;
    alloc_line = w_fresh_which ? w_line1 : w_line0;

    w_fire  = ifu_l1i_req_val && ifu_l1i_req_rdy;
    w_fire0 = w_fire && !w_cur_which;
    w_fire1 = w_fire &&  w_cur_which;

    att_val  = w_match && !r_dec && w_reuse0 && !flush;
    att_slot = prev_slot;

    w_bq_full = (32'(r_bq_cnt) == BQ_DEPTH);
    w_push    = w_match && !flush && !w_bq_full &&
                (!w_use0 || w_reuse0 || r_done0 || w_fire0) &&
                (!w_use1 || r_done1 || w_fire1);
    xq_pop    = w_push;

    w_push_blk.rq     = r_f0;
    w_push_blk.xpage  = xq_cross;
    w_push_blk.use0   = w_use0;
    w_push_blk.slot0  = w_reuse0 ? w_reuse_slot
                                 : (w_fire0 ? w_cur_slot : r_slot0);
    w_push_blk.use1   = w_use1;
    w_push_blk.slot1  = w_fire1 ? w_cur_slot : r_slot1;
    w_push_blk.fault0 = xq_fault0;
    w_push_blk.gpa0   = xq_gpa0;
    w_push_blk.fault1 = xq_cross ? xq_fault1 : IFU_FAULT_NONE;
    w_push_blk.gpa1   = xq_gpa1;

    ftq_ifu_req_rdy = !r_f0_val || w_push;
    w_accept        = ftq_ifu_req_val && ftq_ifu_req_rdy && !flush;
  end

  // ---- F2 this cycle ------------------------------------------------
  blk_t                     w_hd;
  logic                     w_f2_pop;
  logic [5:0]               w_off;
  logic [2*L1I_LINE_BITS-1:0] w_win;
  logic [2*L1I_LINE_BITS-1:0] w_sh;
  logic [VA_WIDTH-1:0]      w_dist;
  logic [5:0]               w_lim;      // range limit in bytes, <= 32
  logic [6:0]               w_byte;
  logic                     w_in1;
  logic                     w_pg;
  ifu_fault_e               w_pf;
  logic                     w_lerr;

  // The line buffer read address, apart from the F2 block that reads
  // the result back: one block would be a combinational loop at block
  // granularity (UNOPTFLAT) though no bit depends on itself.
  assign rd_slot0 = r_bq[r_bq_rd].slot0;
  assign rd_slot1 = r_bq[r_bq_rd].slot1;

  always_comb begin : f2
    w_hd     = r_bq[r_bq_rd];
    f2_val   = (r_bq_cnt != '0) &&
               (!w_hd.use0 || rd_landed0) && (!w_hd.use1 || rd_landed1);
    w_f2_pop  = f2_val && f2_rdy && !flush;
    cons_val  = w_f2_pop;
    cons_use0 = w_hd.use0;
    cons_use1 = w_hd.use1;

    f2_idx       = w_hd.rq.idx;
    f2_gen       = w_hd.rq.gen;
    f2_start_pc  = w_hd.rq.start_pc;
    f2_next_pc   = w_hd.rq.next_pc;
    f2_taken_val = w_hd.rq.taken_val;
    f2_taken_pos = w_hd.rq.taken_pos;
    f2_gpa0      = w_hd.gpa0;
    f2_gpa1      = w_hd.gpa1;

    // IFU-8: seventeen halfwords from the block offset.
    w_off = w_hd.rq.start_pc[L1I_OFFSET_BITS-1:0];
    w_win = {rd_data1, rd_data0};
    w_sh  = w_win >> {w_off, 3'b000};

    // DCD-13 base range.
    w_dist = w_hd.rq.next_pc - w_hd.rq.start_pc;
    w_lim  = ((w_dist != '0) && (w_dist <= BLK_BYTES)) ? w_dist[5:0]
                                                       : 6'd32;

    for (int i = 0; i < NPOS; i++) begin
      f2_hw[i] = w_sh[16*i +: 16];
      f2_pc[i] = w_hd.rq.start_pc + VA_WIDTH'(2 * i);
      w_byte   = {1'b0, w_off} + 7'(2 * i);
      w_in1    = w_byte[6];
      w_pg     = w_in1 && w_hd.xpage;
      w_pf     = w_pg ? w_hd.fault1 : w_hd.fault0;
      w_lerr   = w_in1 ? (w_hd.use1 && rd_err1) : (w_hd.use0 && rd_err0);
      f2_hwpg[i] = w_pg;
      f2_hwf[i]  = (w_pf != IFU_FAULT_NONE) ? w_pf
                 : (w_lerr ? IFU_FAULT_ACCESS : IFU_FAULT_NONE);
    end
    for (int i = 0; i < FTQ_PD_WIDTH; i++) begin
      f2_rng[i] = w_hd.rq.taken_val
                ? (FTB_BR_POS_BITS'(i) <= w_hd.rq.taken_pos)
                : (7'(2 * i) < {1'b0, w_lim});
    end
  end

  // -----------------------------------------------------------------
  // State.
  // -----------------------------------------------------------------
  function automatic logic [BQ_PTR-1:0] bq_nxt(input logic [BQ_PTR-1:0] p);
    return (32'(p) == BQ_DEPTH - 1) ? '0 : p + BQ_PTR'(1);
  endfunction

  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      r_f0_val     <= 1'b0;
      r_f0         <= '0;
      r_dec        <= 1'b0;
      r_reuse0     <= 1'b0;
      r_reuse_slot <= '0;
      r_done0      <= 1'b0;
      r_done1      <= 1'b0;
      r_slot0      <= '0;
      r_slot1      <= '0;
      r_pend       <= 1'b0;
      r_pend_which <= 1'b0;
      r_pend_id    <= '0;
      r_pend_slot  <= '0;
      r_pend_line  <= '0;
      r_bq_rd      <= '0;
      r_bq_wr      <= '0;
      r_bq_cnt     <= '0;
    end else if (flush) begin
      r_f0_val <= 1'b0;
      r_dec    <= 1'b0;
      r_done0  <= 1'b0;
      r_done1  <= 1'b0;
      r_pend   <= 1'b0;
      r_bq_rd  <= '0;
      r_bq_wr  <= '0;
      r_bq_cnt <= '0;
    end else begin
      // ---- F1 queue --------------------------------------------------
      if (w_push) begin
        r_bq[r_bq_wr] <= w_push_blk;
        r_bq_wr       <= bq_nxt(r_bq_wr);
      end
      if (w_f2_pop) begin
        r_bq_rd <= bq_nxt(r_bq_rd);
      end
      r_bq_cnt <= r_bq_cnt + BQ_CNT'(w_push) - BQ_CNT'(w_f2_pop);

      // ---- F0 --------------------------------------------------------
      if (w_push || !r_f0_val) begin
        r_f0_val <= w_accept;
        if (w_accept) begin
          r_f0.idx       <= ftq_ifu_idx;
          r_f0.gen       <= ftq_ifu_gen;
          r_f0.start_pc  <= ftq_ifu_start_pc;
          r_f0.next_pc   <= ftq_ifu_next_pc;
          r_f0.taken_val <= ftq_ifu_taken_val;
          r_f0.taken_pos <= ftq_ifu_taken_pos;
        end
        r_dec   <= 1'b0;
        r_done0 <= 1'b0;
        r_done1 <= 1'b0;
        r_pend  <= 1'b0;
      end else begin
        if (w_match && !r_dec) begin
          r_dec        <= 1'b1;
          r_reuse0     <= w_reuse0;
          r_reuse_slot <= prev_slot;
        end
        if (w_fresh && !w_fire) begin
          r_pend       <= 1'b1;
          r_pend_which <= w_fresh_which;
          r_pend_id    <= alloc_id;
          r_pend_slot  <= alloc_slot;
          r_pend_line  <= w_fresh_which ? w_line1 : w_line0;
        end else if (w_fire) begin
          r_pend <= 1'b0;
        end
        if (w_fire0) begin
          r_done0 <= 1'b1;
          r_slot0 <= w_cur_slot;
        end
        if (w_fire1) begin
          r_done1 <= 1'b1;
          r_slot1 <= w_cur_slot;
        end
      end
    end
  end

endmodule : ifu_fetch
