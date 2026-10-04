// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// IFU RVC expander (BP-116), ifu_decisions.md IFU-1, IFU-4, IFU-8.
//
// SEVENTEEN POSITIONS, EACH EXPANDED INDEPENDENTLY (IFU-4). Position
// i takes the four bytes beginning at halfword i. The low two bits of
// halfword i alone decide the case: not 2'b11 is a 16-bit encoding
// and is expanded, 2'b11 is the low half of a 32-bit encoding and
// {hw[i+1], hw[i]} passes through unchanged. Expansion does not know
// where instructions start; every position produces a value and the
// predecoder's start mask says which are meaningful (DCD-3).
//
// Position 16 is the 17th halfword of IFU-8. It is never a start
// (DCD-2), there is no halfword after it, and its upper half is taken
// as zero. Its output exists because IFU-4 expands every position;
// nothing reads it.
//
// ENCODINGS are the RISC-V compressed-instruction chapter, RV64:
// C, Zcd (C.FLD/C.FSD/C.FLDSP/C.FSDSP), Zcb and Zcmop, which RVA23
// mandates. Zcf is RV32 only and absent. Zcmp and Zcmt are not in
// RVA23 and Zcmp overlaps Zcd.
//
// HINT code points EXPAND. They are legal instructions whose 32-bit
// form has no architectural effect (C.NOP with imm != 0, C.ADDI,
// C.LI, C.LUI, C.MV, C.ADD and C.SLLI with rd = x0, shamt = 0 shifts).
//
// RESERVED code points become {16'h0000, c}: the original 16 bits in
// the low half, zero above. Bits [1:0] are not 2'b11, so no 32-bit
// decoder accepts the word and the instruction raises illegal
// instruction, and stval/mtval can be written with the faulting
// encoding (Sstvala) because the encoding was not discarded. The
// all-zero 16-bit word, the defined illegal instruction, becomes 0.
//
// C.MOP.n (Zcmop) is the C.LUI xn, 0 space with n odd, 1 to 15. It is
// defined to write no register and is expanded to the canonical NOP,
// ADDI x0, x0, 0. See the BP-116 Results Capture.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ifu_rvc_exp (
  input  logic [15:0] hw  [0:FTQ_PD_WIDTH],
  output logic [31:0] exp [0:FTQ_PD_WIDTH],
  output logic        rvc [0:FTQ_PD_WIDTH]
);

  localparam int NUM_POS = FTQ_PD_WIDTH + 1;   // 17, IFU-8

  // Base opcodes of the 32-bit forms.
  localparam logic [6:0] OP_LOAD    = 7'b0000011;
  localparam logic [6:0] OP_LOADFP  = 7'b0000111;
  localparam logic [6:0] OP_IMM     = 7'b0010011;
  localparam logic [6:0] OP_IMM32   = 7'b0011011;
  localparam logic [6:0] OP_STORE   = 7'b0100011;
  localparam logic [6:0] OP_STOREFP = 7'b0100111;
  localparam logic [6:0] OP_OP      = 7'b0110011;
  localparam logic [6:0] OP_LUI     = 7'b0110111;
  localparam logic [6:0] OP_OP32    = 7'b0111011;
  localparam logic [6:0] OP_BRANCH  = 7'b1100011;
  localparam logic [6:0] OP_JALR    = 7'b1100111;
  localparam logic [6:0] OP_JAL     = 7'b1101111;

  localparam logic [31:0] INSN_EBREAK = 32'h0010_0073;
  localparam logic [31:0] INSN_NOP    = 32'h0000_0013;

  localparam logic [4:0] X0 = 5'd0;
  localparam logic [4:0] X1 = 5'd1;
  localparam logic [4:0] X2 = 5'd2;

  // -----------------------------------------------------------------
  // One 16-bit encoding to its 32-bit form.
  // -----------------------------------------------------------------
  function automatic logic [31:0] expand16(input logic [15:0] c);
    logic [4:0]  rdp;      // rd' / rs1' (bits 9:7), x8 to x15
    logic [4:0]  rs2p;     // rs2' / rd' (bits 4:2), x8 to x15
    logic [4:0]  rd;       // full rd / rs1 (bits 11:7)
    logic [4:0]  rs2;      // full rs2 (bits 6:2)
    logic [5:0]  imm6;     // {c[12], c[6:2]}
    logic [11:0] simm6;    // imm6 sign extended to 12
    logic [9:0]  nzuimm;   // C.ADDI4SPN
    logic [11:0] imm16sp;  // C.ADDI16SP, sign extended
    logic [7:0]  uimm_w;   // word offset, CL/CS
    logic [7:0]  uimm_d;   // doubleword offset, CL/CS
    logic [11:0] jimm;     // C.J offset[11:0], bit 0 zero
    logic [8:0]  bimm;     // C.BEQZ / C.BNEZ offset[8:0], bit 0 zero
    logic [7:0]  uimm_lwsp;
    logic [8:0]  uimm_ldsp;
    logic [7:0]  uimm_swsp;
    logic [8:0]  uimm_sdsp;
    logic [20:0] j21;      // jimm sign extended to the J-type field
    logic [12:0] b13;      // bimm sign extended to the B-type field
    logic [31:0] r;
    logic        ill;

    rdp       = {2'b01, c[9:7]};
    rs2p      = {2'b01, c[4:2]};
    rd        = c[11:7];
    rs2       = c[6:2];
    imm6      = {c[12], c[6:2]};
    simm6     = {{6{c[12]}}, imm6};
    nzuimm    = {c[10:7], c[12:11], c[5], c[6], 2'b00};
    imm16sp   = {{3{c[12]}}, c[4:3], c[5], c[2], c[6], 4'b0000};
    uimm_w    = {1'b0, c[5], c[12:10], c[6], 2'b00};
    uimm_d    = {c[6:5], c[12:10], 3'b000};
    jimm      = {c[12], c[8], c[10:9], c[6], c[7], c[2], c[11],
                 c[5:3], 1'b0};
    bimm      = {c[12], c[6:5], c[2], c[11:10], c[4:3], 1'b0};
    uimm_lwsp = {c[3:2], c[12], c[6:4], 2'b00};
    uimm_ldsp = {c[4:2], c[12], c[6:5], 3'b000};
    uimm_swsp = {c[8:7], c[12:9], 2'b00};
    uimm_sdsp = {c[9:7], c[12:10], 3'b000};
    j21       = {{9{jimm[11]}}, jimm};
    b13       = {{4{bimm[8]}}, bimm};

    r   = '0;
    ill = 1'b0;

    unique case (c[1:0])
      // -------------------------------------------------------------
      // Quadrant 0
      // -------------------------------------------------------------
      2'b00: begin
        unique case (c[15:13])
          3'b000: begin  // C.ADDI4SPN
            if (nzuimm == '0) ill = 1'b1;
            r = {2'b00, nzuimm, X2, 3'b000, rs2p, OP_IMM};
          end
          3'b001: r = {4'b0000, uimm_d, rdp, 3'b011, rs2p, OP_LOADFP};
          3'b010: r = {4'b0000, uimm_w, rdp, 3'b010, rs2p, OP_LOAD};
          3'b011: r = {4'b0000, uimm_d, rdp, 3'b011, rs2p, OP_LOAD};
          3'b100: begin  // Zcb loads and stores
            unique case (c[12:10])
              3'b000: r = {10'b0, c[5], c[6], rdp, 3'b100, rs2p,
                           OP_LOAD};                         // c.lbu
              3'b001: r = {10'b0, c[5], 1'b0, rdp,
                           (c[6] ? 3'b001 : 3'b101), rs2p,
                           OP_LOAD};                         // c.lh(u)
              3'b010: r = {7'b0, rs2p, rdp, 3'b000, 3'b000, c[5],
                           c[6], OP_STORE};                  // c.sb
              3'b011: begin                                  // c.sh
                if (c[6]) ill = 1'b1;
                r = {7'b0, rs2p, rdp, 3'b001, 3'b000, c[5], 1'b0,
                     OP_STORE};
              end
              default: ill = 1'b1;
            endcase
          end
          3'b101: r = {4'b0000, uimm_d[7:5], rs2p, rdp, 3'b011,
                       uimm_d[4:0], OP_STOREFP};             // C.FSD
          3'b110: r = {4'b0000, uimm_w[7:5], rs2p, rdp, 3'b010,
                       uimm_w[4:0], OP_STORE};               // C.SW
          3'b111: r = {4'b0000, uimm_d[7:5], rs2p, rdp, 3'b011,
                       uimm_d[4:0], OP_STORE};               // C.SD
          default: ill = 1'b1;
        endcase
      end

      // -------------------------------------------------------------
      // Quadrant 1
      // -------------------------------------------------------------
      2'b01: begin
        unique case (c[15:13])
          3'b000: r = {simm6, rd, 3'b000, rd, OP_IMM};       // C.ADDI
          3'b001: begin                                      // C.ADDIW
            if (rd == X0) ill = 1'b1;
            r = {simm6, rd, 3'b000, rd, OP_IMM32};
          end
          3'b010: r = {simm6, X0, 3'b000, rd, OP_IMM};       // C.LI
          3'b011: begin
            if (rd == X2) begin                              // ADDI16SP
              if (imm16sp == '0) ill = 1'b1;
              r = {imm16sp, X2, 3'b000, X2, OP_IMM};
            end else if (imm6 == '0) begin
              // nzimm = 0: C.MOP.n for odd rd up to x15, else reserved.
              if (rd[0] && !rd[4]) r = INSN_NOP;
              else                 ill = 1'b1;
            end else begin                                   // C.LUI
              r = {{14{c[12]}}, imm6, rd, OP_LUI};
            end
          end
          3'b100: begin
            unique case (c[11:10])
              2'b00: r = {6'b000000, imm6, rdp, 3'b101, rdp,
                          OP_IMM};                           // C.SRLI
              2'b01: r = {6'b010000, imm6, rdp, 3'b101, rdp,
                          OP_IMM};                           // C.SRAI
              2'b10: r = {simm6, rdp, 3'b111, rdp, OP_IMM};  // C.ANDI
              2'b11: begin
                if (!c[12]) begin
                  unique case (c[6:5])
                    2'b00: r = {7'b0100000, rs2p, rdp, 3'b000, rdp,
                                OP_OP};                      // C.SUB
                    2'b01: r = {7'b0000000, rs2p, rdp, 3'b100, rdp,
                                OP_OP};                      // C.XOR
                    2'b10: r = {7'b0000000, rs2p, rdp, 3'b110, rdp,
                                OP_OP};                      // C.OR
                    2'b11: r = {7'b0000000, rs2p, rdp, 3'b111, rdp,
                                OP_OP};                      // C.AND
                    default: ill = 1'b1;
                  endcase
                end else begin
                  unique case (c[6:5])
                    2'b00: r = {7'b0100000, rs2p, rdp, 3'b000, rdp,
                                OP_OP32};                    // C.SUBW
                    2'b01: r = {7'b0000000, rs2p, rdp, 3'b000, rdp,
                                OP_OP32};                    // C.ADDW
                    2'b10: r = {7'b0000001, rs2p, rdp, 3'b000, rdp,
                                OP_OP};                      // c.mul
                    2'b11: begin                             // Zcb unary
                      unique case (c[4:2])
                        3'b000: r = {12'h0FF, rdp, 3'b111, rdp,
                                     OP_IMM};                // c.zext.b
                        3'b001: r = {7'b0110000, 5'b00100, rdp,
                                     3'b001, rdp, OP_IMM};   // c.sext.b
                        3'b010: r = {7'b0000100, 5'b00000, rdp,
                                     3'b100, rdp, OP_OP32};  // c.zext.h
                        3'b011: r = {7'b0110000, 5'b00101, rdp,
                                     3'b001, rdp, OP_IMM};   // c.sext.h
                        3'b100: r = {7'b0000100, X0, rdp, 3'b000,
                                     rdp, OP_OP32};          // c.zext.w
                        3'b101: r = {12'hFFF, rdp, 3'b100, rdp,
                                     OP_IMM};                // c.not
                        default: ill = 1'b1;
                      endcase
                    end
                    default: ill = 1'b1;
                  endcase
                end
              end
              default: ill = 1'b1;
            endcase
          end
          3'b101: r = {j21[20], j21[10:1], j21[11], j21[19:12], X0,
                       OP_JAL};                              // C.J
          3'b110: r = {b13[12], b13[10:5], X0, rdp, 3'b000,
                       b13[4:1], b13[11], OP_BRANCH};        // C.BEQZ
          3'b111: r = {b13[12], b13[10:5], X0, rdp, 3'b001,
                       b13[4:1], b13[11], OP_BRANCH};        // C.BNEZ
          default: ill = 1'b1;
        endcase
      end

      // -------------------------------------------------------------
      // Quadrant 2
      // -------------------------------------------------------------
      2'b10: begin
        unique case (c[15:13])
          3'b000: r = {6'b000000, imm6, rd, 3'b001, rd,
                       OP_IMM};                              // C.SLLI
          3'b001: r = {3'b000, uimm_ldsp, X2, 3'b011, rd,
                       OP_LOADFP};                           // C.FLDSP
          3'b010: begin                                      // C.LWSP
            if (rd == X0) ill = 1'b1;
            r = {4'b0000, uimm_lwsp, X2, 3'b010, rd, OP_LOAD};
          end
          3'b011: begin                                      // C.LDSP
            if (rd == X0) ill = 1'b1;
            r = {3'b000, uimm_ldsp, X2, 3'b011, rd, OP_LOAD};
          end
          3'b100: begin
            if (!c[12]) begin
              if (rs2 == X0) begin                           // C.JR
                if (rd == X0) ill = 1'b1;
                r = {12'h000, rd, 3'b000, X0, OP_JALR};
              end else begin                                 // C.MV
                r = {7'b0000000, rs2, X0, 3'b000, rd, OP_OP};
              end
            end else begin
              if ((rd == X0) && (rs2 == X0)) begin           // C.EBREAK
                r = INSN_EBREAK;
              end else if (rs2 == X0) begin                  // C.JALR
                r = {12'h000, rd, 3'b000, X1, OP_JALR};
              end else begin                                 // C.ADD
                r = {7'b0000000, rs2, rd, 3'b000, rd, OP_OP};
              end
            end
          end
          3'b101: r = {3'b000, uimm_sdsp[8:5], rs2, X2, 3'b011,
                       uimm_sdsp[4:0], OP_STOREFP};          // C.FSDSP
          3'b110: r = {4'b0000, uimm_swsp[7:5], rs2, X2, 3'b010,
                       uimm_swsp[4:0], OP_STORE};            // C.SWSP
          3'b111: r = {3'b000, uimm_sdsp[8:5], rs2, X2, 3'b011,
                       uimm_sdsp[4:0], OP_STORE};            // C.SDSP
          default: ill = 1'b1;
        endcase
      end

      default: ill = 1'b1;   // 2'b11 is not a 16-bit encoding
    endcase

    return ill ? {16'h0000, c} : r;
  endfunction

  // -----------------------------------------------------------------
  // The seventeen positions.
  // -----------------------------------------------------------------
  genvar gi;
  generate
    for (gi = 0; gi < NUM_POS; gi++) begin : g_pos
      logic [15:0] w_hi;
      always_comb begin
        w_hi    = (gi < NUM_POS - 1) ? hw[(gi + 1) % NUM_POS] : 16'h0000;
        rvc[gi] = (hw[gi][1:0] != 2'b11);
        exp[gi] = rvc[gi] ? expand16(hw[gi]) : {w_hi, hw[gi]};
      end
    end
  endgenerate

endmodule : ifu_rvc_exp
