// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// IFU predecoder (BP-116), dcd_decisions.md, ifu_decisions.md IFU-3,
// IFU-4, IFU-16, IFU-17.
//
// ONE PREDECODER, ONE CLASSIFICATION (DCD-1). This module produces
// the per-position facts; ifu_f3 forms the two views from them -- the
// ftq_pd_info_t block view for the writeback and the ifu_pd_pkt_t
// bundle view for the ibuf -- because both views also need the range,
// the fault cut and the prediction check, which are F3's.
//
// INPUTS ARE BOTH BUFFERS (DCD-3). The raw halfwords decide which
// positions are starts; the expanded words are classified. A position
// that is not a start still has an expanded word, and it is
// meaningless.
//
// THE START MASK IS A PARALLEL PREFIX (DCD-4, DCD-5, DCD-6). Each
// position yields its own length from its low two bits. A position
// is a start or the tail of a 32-bit start, and position i maps that
// state to position i+1's as
//   start, 16-bit -> start      start, 32-bit -> tail
//   tail          -> start
// Each such map is two bits, maps compose, and the mask is a
// Kogge-Stone scan of the compositions applied to position 0's
// state: log2(16) = 4 levels, not a 16-step walk.
//
// POSITION 0 IS NOT ALWAYS A START. The walk begins at the block
// start PC (DCD-5), and the block start can land on the tail of a
// 32-bit instruction the previous block delivered from its 17th
// halfword (IFU-8). first_tail says so; ifu_f3 owns the straddle
// register that knows it. See the BP-116 Results Capture.
//
// CLASSIFICATION IS EXACT (DCD-7, DCD-8) and runs on the expanded
// encodings, so only base-ISA opcodes are recognised: BRANCH with a
// defined funct3, JAL, and JALR with funct3 000. Anything else,
// including a reserved RVC expanded to {16'h0, c}, is not a CFI.
//
// CALL AND RETURN (DCD-11) are independent bits from the
// specification's return-address-stack hint table, x1 and x5 the
// link registers:
//   JAL   rd link                          call
//   JALR  rd !link, rs1 !link              neither
//   JALR  rd !link, rs1 link               ret
//   JALR  rd link,  rs1 !link              call
//   JALR  rd link,  rs1 link, rd == rs1    call
//   JALR  rd link,  rs1 link, rd != rs1    call and ret
//
// TARGETS (DCD-9, DCD-10). pc + sext(imm) for a conditional branch
// (B-type) and JAL (J-type), modulo 2**VA_WIDTH. JALR's target field
// is driven zero and carries no meaning.
//
// is_vsetvl is OP-V with funct3 111 (vsetvli, vsetivli, vsetvl).
// needs_vtype is every other OP-V instruction and every vector load
// and store (LOAD-FP / STORE-FP with a vector width encoding). This
// over-marks the whole-register moves, loads and stores, which do not
// read vtype; over-marking is safe for a dependency the rename stage
// resolves (CLAUDE.md, vtype policy). See the Results Capture.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ifu_predecode (
  input  logic [15:0]          hw          [0:FTQ_PD_WIDTH],
  input  logic [31:0]          exp         [0:FTQ_PD_WIDTH-1],
  input  logic [VA_WIDTH-1:0]  pc          [0:FTQ_PD_WIDTH-1],
  input  logic                 first_tail,
  output logic [FTQ_PD_WIDTH-1:0] start,
  output logic [FTQ_PD_WIDTH-1:0] is_rvc,
  output logic [1:0]           br_type     [0:FTQ_PD_WIDTH-1],
  output logic [FTQ_PD_WIDTH-1:0] is_call,
  output logic [FTQ_PD_WIDTH-1:0] is_ret,
  output logic [VA_WIDTH-1:0]  target      [0:FTQ_PD_WIDTH-1],
  output logic [FTQ_PD_WIDTH-1:0] is_vsetvl,
  output logic [FTQ_PD_WIDTH-1:0] needs_vtype
);

  localparam int NPOS    = FTQ_PD_WIDTH;          // 16
  localparam int NLEVELS = $clog2(FTQ_PD_WIDTH);  // 4

  localparam logic [6:0] OP_LOADFP  = 7'b0000111;
  localparam logic [6:0] OP_STOREFP = 7'b0100111;
  localparam logic [6:0] OP_V       = 7'b1010111;
  localparam logic [6:0] OP_BRANCH  = 7'b1100011;
  localparam logic [6:0] OP_JALR    = 7'b1100111;
  localparam logic [6:0] OP_JAL     = 7'b1101111;

  localparam logic [1:0] PD_NONE = 2'b00;   // DCD-7 encoding
  localparam logic [1:0] PD_BR   = 2'b01;
  localparam logic [1:0] PD_JAL  = 2'b10;
  localparam logic [1:0] PD_JALR = 2'b11;

  // -----------------------------------------------------------------
  // The start mask. A map is {f(tail), f(start)}, state 1 = start.
  // g_f1[i] / g_f0[i] after the scan map position 0's state to
  // position i+1's.
  // -----------------------------------------------------------------
  logic [NPOS-1:0] w_len2;
  logic            w_f0 [0:NLEVELS][0:NPOS-1];   // image of tail
  logic            w_f1 [0:NLEVELS][0:NPOS-1];   // image of start
  logic            w_s0;

  always_comb begin : start_scan
    for (int i = 0; i < NPOS; i++) begin
      w_len2[i]   = (hw[i][1:0] == 2'b11);
      w_f0[0][i]  = 1'b1;           // a tail is followed by a start
      w_f1[0][i]  = !w_len2[i];     // a 32-bit start by a tail
    end
    for (int l = 0; l < NLEVELS; l++) begin
      for (int i = 0; i < NPOS; i++) begin
        if (i >= (1 << l)) begin
          // (this) o (earlier): apply the earlier map, then this one.
          w_f0[l+1][i] = w_f0[l][i - (1 << l)] ? w_f1[l][i]
                                               : w_f0[l][i];
          w_f1[l+1][i] = w_f1[l][i - (1 << l)] ? w_f1[l][i]
                                               : w_f0[l][i];
        end else begin
          w_f0[l+1][i] = w_f0[l][i];
          w_f1[l+1][i] = w_f1[l][i];
        end
      end
    end
    w_s0     = !first_tail;
    start[0] = w_s0;
    for (int i = 1; i < NPOS; i++) begin
      start[i] = w_s0 ? w_f1[NLEVELS][i-1] : w_f0[NLEVELS][i-1];
    end
  end

  // -----------------------------------------------------------------
  // Classification, target and vtype marks, per position.
  // -----------------------------------------------------------------
  function automatic logic is_link(input logic [4:0] r);
    return (r == 5'd1) || (r == 5'd5);
  endfunction

  genvar gp;
  generate
    for (gp = 0; gp < NPOS; gp++) begin : g_pos
      logic [6:0]  w_op;
      logic [2:0]  w_f3;
      logic [4:0]  w_rd;
      logic [4:0]  w_rs1;
      logic [12:0] w_bimm;
      logic [20:0] w_jimm;
      logic        w_br;
      logic        w_jal;
      logic        w_jalr;

      always_comb begin
        w_op   = exp[gp][6:0];
        w_f3   = exp[gp][14:12];
        w_rd   = exp[gp][11:7];
        w_rs1  = exp[gp][19:15];
        w_bimm = {exp[gp][31], exp[gp][7], exp[gp][30:25],
                  exp[gp][11:8], 1'b0};
        w_jimm = {exp[gp][31], exp[gp][19:12], exp[gp][20],
                  exp[gp][30:21], 1'b0};

        w_br   = (w_op == OP_BRANCH) && (w_f3 != 3'b010) &&
                 (w_f3 != 3'b011);
        w_jal  = (w_op == OP_JAL);
        w_jalr = (w_op == OP_JALR) && (w_f3 == 3'b000);

        is_rvc[gp]  = (hw[gp][1:0] != 2'b11);
        br_type[gp] = w_br  ? PD_BR  :
                      w_jal ? PD_JAL :
                      w_jalr ? PD_JALR : PD_NONE;
        is_call[gp] = (w_jal || w_jalr) && is_link(w_rd);
        is_ret[gp]  = w_jalr && is_link(w_rs1) &&
                      (!is_link(w_rd) || (w_rd != w_rs1));

        if (w_br) begin
          target[gp] = pc[gp] + {{(VA_WIDTH-13){w_bimm[12]}}, w_bimm};
        end else if (w_jal) begin
          target[gp] = pc[gp] + {{(VA_WIDTH-21){w_jimm[20]}}, w_jimm};
        end else begin
          target[gp] = '0;
        end

        is_vsetvl[gp]   = (w_op == OP_V) && (w_f3 == 3'b111);
        // Vector memory widths are 000, 101, 110 and 111; 001 to 100
        // are the scalar FLH/FLW/FLD/FLQ widths.
        needs_vtype[gp] = ((w_op == OP_V) && (w_f3 != 3'b111)) ||
                          (((w_op == OP_LOADFP) || (w_op == OP_STOREFP))
                           && ((w_f3 == 3'b000) || (w_f3 == 3'b101) ||
                               (w_f3[2:1] == 2'b11)));
      end
    end
  endgenerate

endmodule : ifu_predecode
