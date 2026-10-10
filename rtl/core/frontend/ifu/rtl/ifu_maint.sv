// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// IFU maintenance path (BP-123, TD#136). l1i_ifu_interfaces.md 10
// (IFU to L1I) and 11 (commit to IFU): IF-28 to IF-37, IF-41, IF-43;
// icache_decisions.md L1I-18.
//
// The commit stage presents FENCE.I (MAINT_FENCE_I, the whole cache)
// or cbo.inval (MAINT_CBO_INVAL, the line at a physical address,
// IF-33, IF-41). One operation at a time on each side (IF-28, IF-34):
// cmt_ifu_maint_rdy is high only when idle.
//
//   IDLE   take the commit request
//   REQ    present it to the L1I, inv_all for FENCE.I, the address
//          for cbo.inval (the L1I masks the offset, IF-29), until the
//          L1I takes it
//   WAIT   until l1i_ifu_inv_done. In that cycle the IFU line buffer
//          is cleared (IF-36): on FENCE.I entirely, on cbo.inval when
//          it holds the named line. The clear follows done and not the
//          request, because the L1I drains rather than discards
//          (IF-31) and a draining response would refill a buffer
//          cleared earlier
//   ACK    ifu_cmt_maint_ack, one cycle, the cycle after the clear has
//          been applied (IF-35)
//
// The fetch path is independent at this boundary (IF-37): requests in
// flight are drained by the L1I, and fetch resumes after its done.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ifu_maint (
  input  logic                     clk,
  input  logic                     rstn,

  // ---- l1i_ifu_interfaces.md 11.2 ------------------------------------
  input  logic                     cmt_ifu_maint_val,
  output logic                     cmt_ifu_maint_rdy,
  input  logic                     cmt_ifu_maint_op,
  input  logic [PA_WIDTH-1:0]      cmt_ifu_maint_paddr,
  output logic                     ifu_cmt_maint_ack,

  // ---- l1i_ifu_interfaces.md 10.1 ------------------------------------
  output logic                     ifu_l1i_inv_val,
  input  logic                     ifu_l1i_inv_rdy,
  output logic                     ifu_l1i_inv_all,
  output logic [PA_WIDTH-1:0]      ifu_l1i_inv_paddr,
  input  logic                     l1i_ifu_inv_done,

  // ---- the IF-36 clear, to ifu_lbuf --------------------------------------
  output logic                     lb_clr_val,
  output logic                     lb_clr_all,
  output logic [PA_WIDTH-1:L1I_OFFSET_BITS] lb_clr_line
);

  typedef enum logic [1:0] {
    I_IDLE = 2'd0,
    I_REQ  = 2'd1,
    I_WAIT = 2'd2,
    I_ACK  = 2'd3
  } ist_e;

  ist_e                r_st;
  logic                r_all;
  logic [PA_WIDTH-1:0] r_pa;

  always_comb begin : outs
    cmt_ifu_maint_rdy = rstn && (r_st == I_IDLE);
    ifu_cmt_maint_ack = (r_st == I_ACK);
    ifu_l1i_inv_val   = (r_st == I_REQ);
    ifu_l1i_inv_all   = r_all;
    ifu_l1i_inv_paddr = r_pa;
    lb_clr_val        = (r_st == I_WAIT) && l1i_ifu_inv_done;
    lb_clr_all        = r_all;
    lb_clr_line       = r_pa[PA_WIDTH-1:L1I_OFFSET_BITS];
  end

  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      r_st  <= I_IDLE;
      r_all <= 1'b0;
      r_pa  <= '0;
    end else begin
      case (r_st)
        I_IDLE: begin
          if (cmt_ifu_maint_val && cmt_ifu_maint_rdy) begin
            r_all <= (cmt_ifu_maint_op == MAINT_FENCE_I);
            r_pa  <= cmt_ifu_maint_paddr;
            r_st  <= I_REQ;
          end
        end
        I_REQ:  if (ifu_l1i_inv_rdy)  r_st <= I_WAIT;
        I_WAIT: if (l1i_ifu_inv_done) r_st <= I_ACK;
        default: r_st <= I_IDLE;                    // I_ACK
      endcase
    end
  end

endmodule : ifu_maint
