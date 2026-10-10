// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// L1I maintenance control (BP-123). Not in the cachegen emission: it
// is the pacino addition of cachegen_decisions.md CG-D1, building
// icache_decisions.md L1I-18 and the port of l1i_ifu_interfaces.md 10.
//
// ONE OPERATION AT A TIME (IF-28). inv_rdy is high only when idle.
//
// DRAIN THEN CLEAR (L1I-18 M1, IF-31). From the cycle an operation is
// accepted the core port takes nothing new (hold, IF-30). The control
// then waits until no fill the clear must defeat is in flight:
//   inv_all    every register free: every outstanding request has been
//              answered
//   inv_line   no register holds the named line
// Responses of the drained requests are still presented on the core
// port; a drain is not a discard. Then the clear is applied, in ONE
// cycle (IF-42): every set of both banks for inv_all, or every way of
// the line's set in its bank for inv_line. The offset bits of the
// address are not used (IF-29). inv_done is high for one cycle (IF-32),
// the cycle after the clear (IF-42), and hold falls after it.
//
// inv_line clears the whole set, every way, which IF-42 states ("clears
// its set in one cycle"); invalidating more than the one line is always
// legal for an instruction cache with no dirty state.
// ===================================================================
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
/* verilator lint_on IMPORTSTAR */

module l1i_maint (
  input  logic      clk,
  input  logic      rstn,

  // ---- l1i_ifu_interfaces.md 10.1 -------------------------------------
  input  logic      inv_val,
  output logic      inv_rdy,
  input  logic      inv_all,
  input  l1i_addr_t inv_addr,
  output logic      inv_done,

  // ---- to the miss handling file ----------------------------------------
  output logic      hold,
  output l1i_addr_t inv_line,     // the line being drained
  input  logic      busy_any,
  input  logic      busy_line,

  // ---- to the banks -------------------------------------------------------
  output logic      clr_en,       // one set, in one bank
  output logic      clr_all,      // every set, both banks
  output l1i_bank_t clr_bank,
  output l1i_set_t  clr_set
);

  typedef enum logic [1:0] {
    M_IDLE  = 2'd0,
    M_DRAIN = 2'd1,
    M_CLEAR = 2'd2,
    M_DONE  = 2'd3
  } mst_e;

  mst_e      r_st;
  logic      r_all;
  l1i_addr_t r_line;

  wire w_take = inv_val && inv_rdy;

  always_comb begin : outs
    inv_rdy  = rstn && (r_st == M_IDLE);
    // IF-30: from the acceptance cycle itself to the done cycle.
    hold     = w_take || (r_st != M_IDLE);
    inv_line = r_line;
    inv_done = (r_st == M_DONE);
    clr_en   = (r_st == M_CLEAR) && !r_all;
    clr_all  = (r_st == M_CLEAR) &&  r_all;
    clr_bank = l1i_bank_of(r_line);
    clr_set  = l1i_set_of(r_line);
  end

  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      r_st   <= M_IDLE;
      r_all  <= 1'b0;
      r_line <= '0;
    end else begin
      case (r_st)
        M_IDLE: begin
          if (w_take) begin
            r_all  <= inv_all;
            r_line <= l1i_line_base(inv_addr);     // IF-29
            r_st   <= M_DRAIN;
          end
        end
        M_DRAIN: begin
          if (r_all ? !busy_any : !busy_line) r_st <= M_CLEAR;
        end
        M_CLEAR: r_st <= M_DONE;
        default: r_st <= M_IDLE;                   // M_DONE
      endcase
    end
  end

endmodule
