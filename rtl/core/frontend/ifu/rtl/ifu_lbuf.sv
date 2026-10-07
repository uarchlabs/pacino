// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// IFU line buffer and L1I request identifier free list (BP-116).
// ifu_decisions.md TD-IFU-7, TD-IFU-8, TD-IFU-9;
// l1i_ifu_interfaces.md IF-6, IF-7, IF-10, IF-11, IF-26;
// icache_decisions.md L1I-14.
//
// OWNS three pieces of state, each with one writer here:
//   the identifier free list    MAX_OUTSTANDING, IF-6
//   the line buffer slots       LB_DEPTH, TD-IFU-7, default 16
//   the previous request        TD-IFU-8's one comparator
//
// ALLOCATION. ifu_fetch allocates an identifier and a slot together
// in the cycle it first presents a request, and holds both stable
// until the L1I accepts (IF-4). Both are taken here at once: the
// identifier is in flight from then until its response is presented,
// and the slot is RESERVED for that response (IF-7), because the
// response has no ready (IF-10) and must always have somewhere to
// land. The identifier returns to the free list on the response
// (IF-11); the slot does not.
//
// A SLOT FREES WHEN ITS LAST BLOCK IS CONSUMED (TD-IFU-8). Each slot
// counts the blocks that will read it: one for the block whose
// request allocated it, plus one per later block that reuses it. F2
// consumes a block in order (TD-IFU-9) and the count falls. A slot
// frees when its count is zero, its line has landed, and it is not
// the previous request -- a later block may still reuse that one. It
// frees when a newer request replaces it.
//
// THE PREVIOUS REQUEST is the line address and slot of the most
// recent allocation. ifu_fetch compares a block's first line against
// it and reuses the slot on a match, so consecutive blocks in one line
// make one L1I request (TD-IFU-8).
//
// FLUSH (IFU-29, IFU-30; TD#134, BP-118). Nothing is cleared. The L1I
// has no cancel and every response is accepted (IF-10), so an
// identifier in flight stays in flight until its response, which
// frees it as any response does (IF-11). ifu_fetch reports, per slot,
// how many references the dropped blocks held (kill_cnt) and the
// count falls by that much. A slot left with no reader frees once its
// line has landed; its data is never read, which is the discard of
// IFU-29. A slot still read by a surviving block keeps it (IFU-30).
// No generation is needed: an identifier is not reissued while it is
// in flight (IF-6). The previous-request register is dropped when its
// slot is left with no reader, so no later block reuses a line whose
// only readers were dropped.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ifu_lbuf #(
  parameter int LB_DEPTH = 16                // TD-IFU-7
) (
  input  logic                     clk,
  input  logic                     rstn,
  input  logic                     flush,

  // ---- allocation, from ifu_fetch ------------------------------------
  input  logic                     alloc_val,
  input  logic [PA_WIDTH-1:L1I_OFFSET_BITS] alloc_line,
  output logic                     alloc_ok,
  output logic [REQ_ID_BITS-1:0]   alloc_id,
  output logic [$clog2(LB_DEPTH)-1:0] alloc_slot,

  // ---- reuse of the previous request's slot --------------------------
  input  logic                     att_val,
  input  logic [$clog2(LB_DEPTH)-1:0] att_slot,
  output logic                     prev_val,
  output logic [PA_WIDTH-1:L1I_OFFSET_BITS] prev_line,
  output logic [$clog2(LB_DEPTH)-1:0] prev_slot,

  // ---- the L1I response, l1i_ifu_interfaces.md 5 --------------------
  input  logic                     l1i_ifu_rsp_val,
  input  logic [REQ_ID_BITS-1:0]   l1i_ifu_rsp_id,
  input  logic [L1I_LINE_BITS-1:0] l1i_ifu_rsp_data,
  input  logic                     l1i_ifu_rsp_err,

  // ---- F2 reads and consumes ---------------------------------------
  input  logic [$clog2(LB_DEPTH)-1:0] rd_slot0,
  input  logic [$clog2(LB_DEPTH)-1:0] rd_slot1,
  output logic                     rd_landed0,
  output logic                     rd_landed1,
  output logic [L1I_LINE_BITS-1:0] rd_data0,
  output logic [L1I_LINE_BITS-1:0] rd_data1,
  output logic                     rd_err0,
  output logic                     rd_err1,
  input  logic                     cons_val,
  input  logic                     cons_use0,
  input  logic                     cons_use1,

  // ---- references dropped by a flush, from ifu_fetch ---------------
  input  logic [$clog2(2*LB_DEPTH+1)-1:0] kill_cnt [0:LB_DEPTH-1]
);

  localparam int SB = $clog2(LB_DEPTH);
  localparam int CB = $clog2(2 * LB_DEPTH + 1);   // refcount width

  logic [MAX_OUTSTANDING-1:0] r_id_busy;
  logic [SB-1:0]              r_id_slot [0:MAX_OUTSTANDING-1];

  logic [LB_DEPTH-1:0]        r_busy;
  logic [LB_DEPTH-1:0]        r_landed;
  logic [LB_DEPTH-1:0]        r_err;
  logic [CB-1:0]              r_rc   [0:LB_DEPTH-1];
  logic [L1I_LINE_BITS-1:0]   r_data [0:LB_DEPTH-1];

  logic                       r_prev_val;
  logic [PA_WIDTH-1:L1I_OFFSET_BITS] r_prev_line;
  logic [SB-1:0]              r_prev_slot;

  logic                       w_id_ok;
  logic                       w_slot_ok;
  logic [SB-1:0]              w_rsp_slot;
  logic                       w_alloc;
  logic [CB-1:0]              w_rc_nx  [0:LB_DEPTH-1];
  logic [LB_DEPTH-1:0]        w_landed_nx;
  logic [LB_DEPTH-1:0]        w_free;
  logic                       w_prev_val_nx;
  logic [SB-1:0]              w_prev_slot_nx;

  always_comb begin : alloc_pick
    // Lowest free identifier and lowest free slot. Descending so the
    // lowest is assigned last.
    w_id_ok  = 1'b0;
    alloc_id = '0;
    for (int i = MAX_OUTSTANDING - 1; i >= 0; i--) begin
      if (!r_id_busy[i]) begin
        w_id_ok  = 1'b1;
        alloc_id = REQ_ID_BITS'(i);
      end
    end
    w_slot_ok  = 1'b0;
    alloc_slot = '0;
    for (int s = LB_DEPTH - 1; s >= 0; s--) begin
      if (!r_busy[s]) begin
        w_slot_ok  = 1'b1;
        alloc_slot = SB'(s);
      end
    end
    alloc_ok = w_id_ok && w_slot_ok;

    prev_val  = r_prev_val;
    prev_line = r_prev_line;
    prev_slot = r_prev_slot;
  end

  // The F2 read port, its own block: rd_slot depends on nothing here
  // and the reads feed back into ifu_fetch's F2 valid.
  always_comb begin : rd_port
    rd_landed0 = r_landed[rd_slot0];
    rd_landed1 = r_landed[rd_slot1];
    rd_data0   = r_data[rd_slot0];
    rd_data1   = r_data[rd_slot1];
    rd_err0    = r_err[rd_slot0];
    rd_err1    = r_err[rd_slot1];
  end

  // -----------------------------------------------------------------
  // Reference counts and the free condition.
  // -----------------------------------------------------------------
  always_comb begin : counts
    w_alloc        = alloc_val && alloc_ok && !flush;
    w_rsp_slot     = r_id_slot[l1i_ifu_rsp_id];
    for (int s = 0; s < LB_DEPTH; s++) begin
      w_rc_nx[s] = r_rc[s];
      if (w_alloc && (alloc_slot == SB'(s))) begin
        w_rc_nx[s] = CB'(1);
      end
      if (att_val && (att_slot == SB'(s))) begin
        w_rc_nx[s] = w_rc_nx[s] + CB'(1);
      end
      if (cons_val && cons_use0 && (rd_slot0 == SB'(s))) begin
        w_rc_nx[s] = w_rc_nx[s] - CB'(1);
      end
      if (cons_val && cons_use1 && (rd_slot1 == SB'(s))) begin
        w_rc_nx[s] = w_rc_nx[s] - CB'(1);
      end
      w_rc_nx[s]     = w_rc_nx[s] - kill_cnt[s];
    end

    // The previous request: replaced by an allocation, or dropped by a
    // flush that leaves its slot with no reader.
    w_prev_val_nx  = w_alloc ? 1'b1
                   : ((flush && (w_rc_nx[r_prev_slot] == '0)) ? 1'b0
                                                              : r_prev_val);
    w_prev_slot_nx = w_alloc ? alloc_slot : r_prev_slot;

    for (int s = 0; s < LB_DEPTH; s++) begin
      w_landed_nx[s] = r_landed[s] ||
                       (l1i_ifu_rsp_val && (w_rsp_slot == SB'(s)));
      w_free[s] = r_busy[s] && (w_rc_nx[s] == '0) && w_landed_nx[s] &&
                  !(w_prev_val_nx && (w_prev_slot_nx == SB'(s)));
    end
  end

  // -----------------------------------------------------------------
  // State.
  // -----------------------------------------------------------------
  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      r_id_busy   <= '0;                 // IF-26: all sixteen free
      r_busy      <= '0;
      r_landed    <= '0;
      r_err       <= '0;
      r_prev_val  <= 1'b0;
      r_prev_line <= '0;
      r_prev_slot <= '0;
      for (int s = 0; s < LB_DEPTH; s++) r_rc[s] <= '0;
      for (int i = 0; i < MAX_OUTSTANDING; i++) r_id_slot[i] <= '0;
    end else begin
      // IF-10 / IF-11: land the response, free its identifier.
      if (l1i_ifu_rsp_val) begin
        r_data[w_rsp_slot]        <= l1i_ifu_rsp_data;
        r_err[w_rsp_slot]         <= l1i_ifu_rsp_err;
        r_id_busy[l1i_ifu_rsp_id] <= 1'b0;
      end
      for (int s = 0; s < LB_DEPTH; s++) begin
        r_rc[s] <= w_rc_nx[s];
        if (w_free[s]) begin
          r_busy[s]   <= 1'b0;
          r_landed[s] <= 1'b0;
        end else begin
          r_landed[s] <= w_landed_nx[s];
        end
      end
      r_prev_val <= w_prev_val_nx;
      if (w_alloc) begin
        r_id_busy[alloc_id]  <= 1'b1;
        r_id_slot[alloc_id]  <= alloc_slot;
        r_busy[alloc_slot]   <= 1'b1;
        r_landed[alloc_slot] <= 1'b0;
        r_prev_val           <= 1'b1;
        r_prev_line          <= alloc_line;
        r_prev_slot          <= alloc_slot;
      end
    end
  end

endmodule : ifu_lbuf
