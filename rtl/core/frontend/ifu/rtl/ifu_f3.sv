// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// IFU F3 (BP-116). ifu_decisions.md IFU-5, IFU-11, IFU-12, IFU-15,
// IFU-2, IFU-2a; dcd_decisions.md DCD-12 to DCD-16;
// ftq_ifu_interfaces.md 6 (M1 to M4); ifu_ibuf_interfaces.md IB-1 to
// IB-9a.
//
// OWNS the F3 register and the straddle register. Expansion and
// predecode (ifu_rvc_exp, ifu_predecode) run on the F3 register's
// halfwords in the same cycle and return their results here
// (IFU-12); this module forms the range, the fault, the prediction
// check, the ibuf vector and the writeback fields.
//
// FAULT. Each position's instruction faults with its first halfword's
// fault, or, for a 32-bit instruction whose first halfword is clean,
// with its second halfword's. fault_va is the address of the halfword
// that faulted (the portion of the instruction that caused the fault,
// privileged spec, Sstvala); fault_gpa is that halfword's page's GPA
// for a guest-page fault (IFU-2a). The block's fault position is the
// first start in the base range whose instruction faults; the range
// is cut after it (ftq_ifu_interfaces.md 6) and that instruction is
// delivered with its cause (IB-9). A faulting instruction's encoding
// is not known, so its classification is driven zero.
//
// THE CHECK, M1 to M4, ftq_ifu_interfaces.md 6.
//   M1  the first valid JAL, call or not, BEFORE the predicted taken
//       position tp, or anywhere when none is predicted. A JALR is
//       never M1: its target is unknown here. Ruled session-074,
//       TD#146, built BP-117; BP-116 raised M1 only when none was
//       predicted.
// With tp predicted and no M1:
//   M4  tp lies outside pd_range: a fault cut the range before it
//   M2  tp is not a valid start, or holds no control transfer
//   M3  tp holds a branch or JAL whose target differs from next_pc,
//       the taken slot's target (the one target the request carries)
//   no check when the instruction at tp itself faults
// M1 OUTRANKS M2 TO M4 BECAUSE IT IS EARLIER IN PROGRAM ORDER. A JAL
// before tp is taken unconditionally, so the path never reaches tp
// and whatever tp holds is off the path; mis_pos names the first
// position that fails, which is the JAL. M2 to M4 are all findings AT
// tp and are mutually exclusive by their conditions. The documents
// state no priority; this one follows from M1 naming the "first"
// JAL and from IB-2 truncating at mis_pos. See the BP-117 Results
// Capture.
// mis_pos is the M1 position, or tp. cfi is the first valid control
// transfer (IFU-15). ifu_ftq_target is the target at mis_pos when
// mis_val, else at cfi_pos: ftq_ifu.sv writes it into the slot at
// mis_pos (W1). See the BP-116 Results Capture.
//
// THE IBUF VECTOR (IFU-5, IB-1, IB-2). Sixteen slots, never
// compacted. ifu_ibuf_en is valid (start and in pd_range, DCD-12) and
// not after mis_pos (the truncation of IFU-15). The slot's valid
// field is not driven (IB-3). The block is offered whole (IB-5) and
// held, payload and all, while ibuf_ifu_rdy is low (IB-7). It is not
// offered in a flush cycle. A block at F3 that survives the flush
// (IFU-28) stays and is offered from the next cycle; one that does
// not is dropped. The ibuf clears only on a backend redirect (IB-12)
// and discards a write in that cycle, so holding the offer for one
// cycle loses nothing.
//
// THE STRADDLE REGISTER (IFU-11). The 17th halfword (IFU-8) lets a
// 32-bit instruction starting at the block's last position complete
// inside the block. When a block ends by falling through (no
// predicted taken, no mis, no fault) and its last delivered
// instruction is a 32-bit one starting 2 bytes before next_pc, the
// next block starts on that instruction's tail. The register holds
// that address; a block arriving at F3 with exactly that start PC
// begins its start walk at position 1 (first_tail). It is written on
// every transfer. A flush keeps it only when the block AFTER the one
// that set it survives (IFU-28): that block is the next to reach F3
// and is the sequential successor. Otherwise the next block is the
// corrected stream, whose start is a redirect target and begins on an
// instruction. IFU-11 reads that the
// register holds the leading halfword; under IFU-8 the instruction is
// already complete, so only the tail address is needed. See the
// Results Capture.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ifu_f3 (
  input  logic                     clk,
  input  logic                     rstn,
  input  logic                     flush,
  input  logic [FTQ_IDX_BITS-1:0]  flush_idx,
  input  logic [FTQ_IDX_BITS-1:0]  commit_ptr,

  // ---- F2, from ifu_fetch ------------------------------------------
  input  logic                     f2_val,
  output logic                     f2_rdy,
  input  logic [FTQ_IDX_BITS-1:0]  f2_idx,
  input  logic                     f2_gen,
  input  logic [VA_WIDTH-1:0]      f2_start_pc,
  input  logic [VA_WIDTH-1:0]      f2_next_pc,
  input  logic                     f2_taken_val,
  input  logic [FTB_BR_POS_BITS-1:0] f2_taken_pos,
  input  logic [15:0]              f2_hw   [0:FTQ_PD_WIDTH],
  input  ifu_fault_e               f2_hwf  [0:FTQ_PD_WIDTH],
  input  logic [FTQ_PD_WIDTH:0]    f2_hwpg,
  input  logic [VA_WIDTH-1:0]      f2_pc   [0:FTQ_PD_WIDTH],
  input  logic [GPA_WIDTH-1:0]     f2_gpa0,
  input  logic [GPA_WIDTH-1:0]     f2_gpa1,
  input  logic [FTQ_PD_WIDTH-1:0]  f2_rng,

  // ---- to and from the expander and predecoder ---------------------
  output logic [15:0]              f3_hw   [0:FTQ_PD_WIDTH],
  output logic [VA_WIDTH-1:0]      f3_pc   [0:FTQ_PD_WIDTH-1],
  output logic                     first_tail,
  input  logic [31:0]              x_exp   [0:FTQ_PD_WIDTH],
  input  logic [FTQ_PD_WIDTH-1:0]  p_start,
  input  logic [FTQ_PD_WIDTH-1:0]  p_rvc,
  input  logic [1:0]               p_br    [0:FTQ_PD_WIDTH-1],
  input  logic [FTQ_PD_WIDTH-1:0]  p_call,
  input  logic [FTQ_PD_WIDTH-1:0]  p_ret,
  input  logic [VA_WIDTH-1:0]      p_tgt   [0:FTQ_PD_WIDTH-1],
  input  logic [FTQ_PD_WIDTH-1:0]  p_vset,
  input  logic [FTQ_PD_WIDTH-1:0]  p_vtype,

  // ---- ifu_ibuf_interfaces.md 2 ------------------------------------
  output logic                     ifu_ibuf_val,
  output logic [FTQ_PD_WIDTH-1:0]  ifu_ibuf_en,
  output ifu_pd_pkt_t              ifu_ibuf_slot [0:FTQ_PD_WIDTH-1],
  input  logic                     ibuf_ifu_rdy,

  // ---- the writeback fields, to ifu_wb -----------------------------
  output logic                     wb_load,
  output logic [FTQ_IDX_BITS-1:0]  wb_idx,
  output logic                     wb_gen,
  output ftq_pd_info_t             wb_pd   [0:FTQ_PD_WIDTH-1],
  output logic [FTQ_PD_WIDTH-1:0]  wb_range,
  output logic                     wb_cfi_val,
  output logic [FTQ_PD_POS_BITS-1:0] wb_cfi_pos,
  output logic                     wb_mis_val,
  output logic [FTQ_PD_POS_BITS-1:0] wb_mis_pos,
  output logic [VA_WIDTH-1:0]      wb_target,
  output logic                     wb_fault_val,
  output logic [FTQ_PD_POS_BITS-1:0] wb_fault_pos
);

  localparam int NPD  = FTQ_PD_WIDTH;        // 16
  localparam int NPOS = FTQ_PD_WIDTH + 1;    // 17

  localparam logic [1:0] PD_NONE = 2'b00;
  localparam logic [1:0] PD_JAL  = 2'b10;
  localparam logic [1:0] PD_JALR = 2'b11;

  // ---- the F3 register ----------------------------------------------
  logic                       r_val;
  logic [FTQ_IDX_BITS-1:0]    r_idx;
  logic                       r_gen;
  logic [VA_WIDTH-1:0]        r_start_pc;
  logic [VA_WIDTH-1:0]        r_next_pc;
  logic                       r_taken_val;
  logic [FTB_BR_POS_BITS-1:0] r_taken_pos;
  logic [15:0]                r_hw  [0:NPOS-1];
  ifu_fault_e                 r_hwf [0:NPOS-1];
  logic [NPOS-1:0]            r_hwpg;
  logic [VA_WIDTH-1:0]        r_pc  [0:NPOS-1];
  logic [GPA_WIDTH-1:0]       r_gpa0;
  logic [GPA_WIDTH-1:0]       r_gpa1;
  logic [NPD-1:0]             r_rng;

  // ---- the straddle register -----------------------------------------
  logic                       r_strad_val;
  logic [VA_WIDTH-1:0]        r_strad_pc;
  logic [FTQ_IDX_BITS-1:0]    r_strad_idx;   // the block that set it

  // IFU-28. Older than the flush index, measured from commit_ptr.
  function automatic logic survives(input logic [FTQ_IDX_BITS-1:0] i,
                                    input logic [FTQ_IDX_BITS-1:0] f,
                                    input logic [FTQ_IDX_BITS-1:0] c);
    return FTQ_IDX_BITS'(i - c) < FTQ_IDX_BITS'(f - c);
  endfunction

  // ---- this cycle ----------------------------------------------------
  ifu_fault_e                 w_ifault [0:NPD-1];
  logic [VA_WIDTH-1:0]        w_fva    [0:NPD-1];
  logic [GPA_WIDTH-1:0]       w_fgpa   [0:NPD-1];
  logic [NPD-1:0]             w_has_f;
  logic [NPD-1:0]             w_range;
  logic [NPD-1:0]             w_valid;
  logic [1:0]                 w_br     [0:NPD-1];
  logic                       w_fault_val;
  logic [FTQ_PD_POS_BITS-1:0] w_fault_pos;
  logic                       w_cfi_val;
  logic [FTQ_PD_POS_BITS-1:0] w_cfi_pos;
  logic                       w_mis_val;
  logic [FTQ_PD_POS_BITS-1:0] w_mis_pos;
  logic                       w_last_val;
  logic [FTQ_PD_POS_BITS-1:0] w_last_pos;
  logic                       w_strad_set;
  logic                       w_xfer;
  logic                       w_tp_in;
  logic [FTQ_PD_POS_BITS-1:0] w_tp;
  logic                       w_m1_val;
  logic [FTQ_PD_POS_BITS-1:0] w_m1_pos;

  always_comb begin : f3
    for (int i = 0; i < NPOS; i++) f3_hw[i] = r_hw[i];
    for (int i = 0; i < NPD; i++)  f3_pc[i] = r_pc[i];
    first_tail = r_strad_val && (r_start_pc == r_strad_pc);

    // ---- per-position fault ------------------------------------------
    for (int i = 0; i < NPD; i++) begin
      if (r_hwf[i] != IFU_FAULT_NONE) begin
        w_ifault[i] = r_hwf[i];
        w_fva[i]    = r_pc[i];
        w_fgpa[i]   = r_hwpg[i] ? r_gpa1 : r_gpa0;
      end else if (!p_rvc[i] && (r_hwf[i+1] != IFU_FAULT_NONE)) begin
        w_ifault[i] = r_hwf[i+1];
        w_fva[i]    = r_pc[i] + VA_WIDTH'(2);
        w_fgpa[i]   = r_hwpg[i+1] ? r_gpa1 : r_gpa0;
      end else begin
        w_ifault[i] = IFU_FAULT_NONE;
        w_fva[i]    = '0;
        w_fgpa[i]   = '0;
      end
      if (w_ifault[i] != IFU_FAULT_GUEST_PAGE) w_fgpa[i] = '0;
      w_has_f[i] = (w_ifault[i] != IFU_FAULT_NONE);
    end

    // ---- the fault cut of the range ----------------------------------
    w_fault_val = 1'b0;
    w_fault_pos = '0;
    for (int i = NPD - 1; i >= 0; i--) begin
      if (p_start[i] && r_rng[i] && w_has_f[i]) begin
        w_fault_val = 1'b1;
        w_fault_pos = FTQ_PD_POS_BITS'(i);
      end
    end
    for (int i = 0; i < NPD; i++) begin
      w_range[i] = r_rng[i] &&
                   (!w_fault_val || (FTQ_PD_POS_BITS'(i) <= w_fault_pos));
      w_valid[i] = p_start[i] && w_range[i];
      w_br[i]    = w_has_f[i] ? PD_NONE : p_br[i];
    end

    // ---- cfi: the first valid control transfer -------------------------
    w_cfi_val = 1'b0;
    w_cfi_pos = '0;
    for (int i = NPD - 1; i >= 0; i--) begin
      if (w_valid[i] && (w_br[i] != PD_NONE)) begin
        w_cfi_val = 1'b1;
        w_cfi_pos = FTQ_PD_POS_BITS'(i);
      end
    end

    // ---- the prediction check, M1 to M4 --------------------------------
    w_tp      = FTQ_PD_POS_BITS'(r_taken_pos);
    w_tp_in   = w_range[w_tp];

    // M1: the first valid JAL, strictly before tp when tp is
    // predicted. Descending, so the lowest position is assigned last.
    // A faulting position has w_br driven to PD_NONE, and the range
    // is cut after the first fault, so a JAL is never found past one.
    w_m1_val = 1'b0;
    w_m1_pos = '0;
    for (int i = NPD - 1; i >= 0; i--) begin
      if (w_valid[i] && (w_br[i] == PD_JAL) &&
          (!r_taken_val || (FTQ_PD_POS_BITS'(i) < w_tp))) begin
        w_m1_val = 1'b1;
        w_m1_pos = FTQ_PD_POS_BITS'(i);
      end
    end

    w_mis_val = 1'b0;
    w_mis_pos = '0;
    if (w_m1_val) begin
      w_mis_val = 1'b1;                                     // M1
      w_mis_pos = w_m1_pos;
    end else if (r_taken_val) begin
      w_mis_pos = w_tp;
      if (!w_tp_in) begin
        w_mis_val = 1'b1;                                   // M4
      end else if (!w_valid[w_tp]) begin
        w_mis_val = 1'b1;                                   // M2
      end else if (w_has_f[w_tp]) begin
        w_mis_val = 1'b0;                                   // no check
      end else if (w_br[w_tp] == PD_NONE) begin
        w_mis_val = 1'b1;                                   // M2
      end else if ((w_br[w_tp] != PD_JALR) &&
                   (p_tgt[w_tp] != r_next_pc)) begin
        w_mis_val = 1'b1;                                   // M3
      end
    end

    // ---- the straddle into the next block -------------------------------
    w_last_val = 1'b0;
    w_last_pos = '0;
    for (int i = 0; i < NPD; i++) begin
      if (w_valid[i]) begin
        w_last_val = 1'b1;
        w_last_pos = FTQ_PD_POS_BITS'(i);
      end
    end
    w_strad_set = !r_taken_val && !w_mis_val && !w_fault_val &&
                  w_last_val && !p_rvc[w_last_pos] &&
                  ((r_pc[{1'b0, w_last_pos}] + VA_WIDTH'(2)) == r_next_pc);

    // ---- the ibuf vector -----------------------------------------------
    ifu_ibuf_val = r_val && !flush;
    w_xfer       = ifu_ibuf_val && ibuf_ifu_rdy;
    f2_rdy       = (!r_val || w_xfer) && !flush;
    for (int i = 0; i < NPD; i++) begin
      ifu_ibuf_en[i] = w_valid[i] &&
                       (!w_mis_val || (FTQ_PD_POS_BITS'(i) <= w_mis_pos));
      ifu_ibuf_slot[i].valid       = 1'b0;               // IB-3
      ifu_ibuf_slot[i].instr       = x_exp[i];
      ifu_ibuf_slot[i].start_pc    = r_pc[i];
      ifu_ibuf_slot[i].pos         = FTQ_PD_POS_BITS'(i);
      ifu_ibuf_slot[i].ftq_idx     = r_idx;
      ifu_ibuf_slot[i].fault_cause = w_ifault[i];
      ifu_ibuf_slot[i].fault_va    = w_fva[i];
      ifu_ibuf_slot[i].fault_gpa   = w_fgpa[i];
      ifu_ibuf_slot[i].is_rvc      = p_rvc[i];
      ifu_ibuf_slot[i].br_type     = w_br[i];
      ifu_ibuf_slot[i].is_call     = p_call[i] && !w_has_f[i];
      ifu_ibuf_slot[i].is_ret      = p_ret[i]  && !w_has_f[i];
      ifu_ibuf_slot[i].is_vsetvl   = p_vset[i] && !w_has_f[i];
      ifu_ibuf_slot[i].needs_vtype = p_vtype[i] && !w_has_f[i];
    end

    // ---- the writeback fields ------------------------------------------
    wb_load      = w_xfer;
    wb_idx       = r_idx;
    wb_gen       = r_gen;
    for (int i = 0; i < NPD; i++) begin
      wb_pd[i].valid   = w_valid[i];
      wb_pd[i].is_rvc  = p_rvc[i];
      wb_pd[i].br_type = w_br[i];
      wb_pd[i].is_call = p_call[i] && !w_has_f[i];
      wb_pd[i].is_ret  = p_ret[i]  && !w_has_f[i];
    end
    wb_range     = w_range;
    wb_cfi_val   = w_cfi_val;
    wb_cfi_pos   = w_cfi_pos;
    wb_mis_val   = w_mis_val;
    wb_mis_pos   = w_mis_pos;
    wb_target    = w_mis_val ? p_tgt[w_mis_pos]
                 : (w_cfi_val ? p_tgt[w_cfi_pos] : '0);
    wb_fault_val = w_fault_val;
    wb_fault_pos = w_fault_pos;
  end

  // -----------------------------------------------------------------
  // State.
  // -----------------------------------------------------------------
  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      r_val       <= 1'b0;
      r_idx       <= '0;
      r_gen       <= 1'b0;
      r_start_pc  <= '0;
      r_next_pc   <= '0;
      r_taken_val <= 1'b0;
      r_taken_pos <= '0;
      r_hwpg      <= '0;
      r_gpa0      <= '0;
      r_gpa1      <= '0;
      r_rng       <= '0;
      for (int i = 0; i < NPOS; i++) begin
        r_hw[i]  <= '0;
        r_hwf[i] <= IFU_FAULT_NONE;
        r_pc[i]  <= '0;
      end
      r_strad_val <= 1'b0;
      r_strad_pc  <= '0;
      r_strad_idx <= '0;
    end else if (flush) begin
      // Nothing transfers or loads in a flush cycle (f2_rdy and
      // ifu_ibuf_val are both low).
      r_val       <= r_val && survives(r_idx, flush_idx, commit_ptr);
      r_strad_val <= r_strad_val &&
                     survives(r_strad_idx + FTQ_IDX_BITS'(1), flush_idx,
                              commit_ptr);
    end else begin
      if (w_xfer) begin
        r_strad_val <= w_strad_set;
        r_strad_pc  <= r_next_pc;
        r_strad_idx <= r_idx;
      end
      if (f2_rdy) begin
        r_val <= f2_val;
        if (f2_val) begin
          r_idx       <= f2_idx;
          r_gen       <= f2_gen;
          r_start_pc  <= f2_start_pc;
          r_next_pc   <= f2_next_pc;
          r_taken_val <= f2_taken_val;
          r_taken_pos <= f2_taken_pos;
          r_hwpg      <= f2_hwpg;
          r_gpa0      <= f2_gpa0;
          r_gpa1      <= f2_gpa1;
          r_rng       <= f2_rng;
          for (int i = 0; i < NPOS; i++) begin
            r_hw[i]  <= f2_hw[i];
            r_hwf[i] <= f2_hwf[i];
            r_pc[i]  <= f2_pc[i];
          end
        end
      end
    end
  end

endmodule : ifu_f3
