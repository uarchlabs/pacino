// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// rvc_expander.sv
// Pre-decode RVC (16-bit compressed) to 32-bit instruction expander.
// RVA23 / RV64GC compliant.
//
// Accepts an 8-slot fetch bundle where each slot is 32 bits wide.
// 16-bit RVC instructions occupy the lower 16 bits of their slot.
// Expands all slots in parallel, fully combinational.
//
// Boundary mask encoding (2 bits per slot, MSB first within pair):
//   fetch_mask[2*i+1] = valid   - slot i holds a valid instruction start
//   fetch_mask[2*i+0] = is_rvc  - slot i is a 16-bit RVC instruction
//
// Downstream interface note:
//   exp_bundle and exp_valid are consumed by instr_decoder, which has
//   no knowledge of original instruction widths.
// ===================================================================

`default_nettype none

/* verilator lint_off IMPORTSTAR */
import decode_pkg::*;
/* verilator lint_on IMPORTSTAR */

module rvc_expander (
    // --- fetch bundle input ---
    input  logic [SLOTS-1:0][31:0] fetch_bundle,
    input  logic [SLOTS*MASK_BITS-1:0] fetch_mask,

    // --- expanded output ---
    output logic [SLOTS-1:0][31:0] exp_bundle,
    output logic [SLOTS-1:0]       exp_valid
);

// ---------------------------------------------------------------------------
// Internal signals
// ---------------------------------------------------------------------------

// Decoded mask fields per slot
logic [SLOTS-1:0] slot_valid;
logic [SLOTS-1:0] slot_is_rvc;

// Extract per-slot mask bits
genvar m;
generate
    for (m = 0; m < SLOTS; m++) begin : g_mask
        assign slot_valid[m]  = fetch_mask[m*MASK_BITS + 1];
        assign slot_is_rvc[m] = fetch_mask[m*MASK_BITS + 0];
    end
endgenerate

// ---------------------------------------------------------------------------
// RVC expansion function
// Expands a 16-bit compressed instruction to its 32-bit equivalent.
// Returns 32'h0 for illegal/reserved encodings (caller checks slot_valid).
// Targets RV64GC (C extension, RISC-V ISA spec v2.2+).
// ---------------------------------------------------------------------------
function automatic logic [31:0] expand_rvc(input logic [15:0] c);
    // Compressed register decoding (rs1'/rd'/rs2' -> x8..x15)
    logic [4:0] crs1, crs2, crd;
    // Full register fields (from CI/CR/CSS formats)
    logic [4:0] frs2, frd;
    logic [5:0] shamt6;
    logic [31:0] result;

    crs1 = {2'b01, c[9:7]};   // c.rs1' -> x8..x15
    crs2 = {2'b01, c[4:2]};   // c.rs2' -> x8..x15
    crd  = {2'b01, c[4:2]};   // c.rd'  -> x8..x15 (load/alu)
    frs2 = c[6:2];
    frd  = c[11:7];
    shamt6 = {c[12], c[6:2]};

    result = 32'h0;  // default: illegal

    unique casez (c[1:0])

        // ------------------------------------------------------------------
        // Quadrant 0
        // ------------------------------------------------------------------
        2'b00: begin
            unique casez (c[15:13])
                3'b000: begin
                    // C.ADDI4SPN -> ADDI rd', x2, nzuimm
                    // nzuimm = {c[10:7],c[12:11],c[5],c[6],2'b00}
                    logic [9:0] uimm;
                    uimm = {c[10:7], c[12:11], c[5], c[6], 2'b00};
                    if (uimm == 10'h0)
                        result = 32'h0; // reserved
                    else
                        result = {2'b00, uimm, 5'd2, 3'b000, crd,
                                  7'b0010011};
                end
                3'b001: begin
                    // C.FLD -> FLD rd', rs1', uimm  (RV64)
                    // uimm = {c[6:5],c[12:10],3'b000}
                    logic [7:0] uimm;
                    uimm = {c[6:5], c[12:10], 3'b000};
                    result = {4'b0000, uimm, crs1, 3'b011, crd,
                              7'b0000111};
                end
                3'b010: begin
                    // C.LW -> LW rd', rs1', uimm
                    // uimm = {c[5],c[12:10],c[6],2'b00}
                    logic [6:0] uimm;
                    uimm = {c[5], c[12:10], c[6], 2'b00};
                    result = {5'b00000, uimm, crs1, 3'b010, crd,
                              7'b0000011};
                end
                3'b011: begin
                    // C.LD -> LD rd', rs1', uimm  (RV64)
                    // uimm = {c[6:5],c[12:10],3'b000}
                    logic [7:0] uimm;
                    uimm = {c[6:5], c[12:10], 3'b000};
                    result = {4'b0000, uimm, crs1, 3'b011, crd,
                              7'b0000011};
                end
                3'b100: begin
                    // Zcb: byte/halfword loads and stores (Q0, funct3=4)
                    unique casez (c[12:10])
                        3'b000: begin
                            // c.lbu (12..10=0) -> LBU rd',rs1',uimm[1:0]
                            // uimm[1]=c[5], uimm[0]=c[6]
                            result = {10'b0, c[5], c[6], crs1,
                                      3'b100, crd, 7'b0000011};
                        end
                        3'b001: begin
                            if (c[6] == 1'b0) begin
                                // c.lhu (12..10=1,6=0) -> LHU rd',rs1',u
                                // uimm = {c[5], 1'b0} (halfword aligned)
                                result = {10'b0, c[5], 1'b0, crs1,
                                          3'b101, crd, 7'b0000011};
                            end else begin
                                // c.lh (12..10=1,6=1) -> LH rd',rs1',u
                                // uimm = {c[5], 1'b0} (halfword aligned)
                                result = {10'b0, c[5], 1'b0, crs1,
                                          3'b001, crd, 7'b0000011};
                            end
                        end
                        3'b010: begin
                            // c.sb (12..10=2) -> SB rs2',rs1',uimm[1:0]
                            // uimm[1]=c[5], uimm[0]=c[6]
                            // S-type:{imm[11:5],rs2,rs1,f3,imm[4:0],op}
                            result = {7'b0000000, crs2, crs1,
                                      3'b000, 3'b000, c[5], c[6],
                                      7'b0100011};
                        end
                        3'b011: begin
                            if (c[6] == 1'b0) begin
                                // c.sh (12..10=3,6=0) -> SH rs2',rs1',u
                                // uimm = {c[5], 1'b0} (halfword aligned)
                                result = {7'b0000000, crs2, crs1,
                                          3'b001, 3'b000, c[5], 1'b0,
                                          7'b0100011};
                            end else begin
                                result = 32'h0; // reserved (c.sh: c[6]=0)
                            end
                        end
                        default: result = 32'h0; // reserved
                    endcase
                end
                3'b101: begin
                    // C.FSD -> FSD rs2', rs1', uimm  (RV64)
                    // uimm = {c[6:5],c[12:10],3'b000}
                    logic [7:0] uimm;
                    uimm = {c[6:5], c[12:10], 3'b000};
                    result = {4'b0000, uimm[7:3], crs2, crs1, 3'b011,
                              uimm[2:0], 7'b0100111};
                end
                3'b110: begin
                    // C.SW -> SW rs2', rs1', uimm
                    // uimm[6:0] = {c[5],c[12:10],c[6],2'b00}
                    // S-type: {imm[11:5],rs2,rs1,f3,imm[4:0],opcode}
                    // imm[11:5]={5'b0,uimm[6:5]}, imm[4:0]=uimm[4:0]
                    logic [6:0] uimm;
                    uimm = {c[5], c[12:10], c[6], 2'b00};
                    result = {5'b00000, uimm[6:5], crs2, crs1,
                              3'b010, uimm[4:0], 7'b0100011};
                end
                3'b111: begin
                    // C.SD -> SD rs2', rs1', uimm  (RV64)
                    // uimm = {c[6:5],c[12:10],3'b000}
                    logic [7:0] uimm;
                    uimm = {c[6:5], c[12:10], 3'b000};
                    result = {4'b0000, uimm[7:3], crs2, crs1, 3'b011,
                              uimm[2:0], 7'b0100011};
                end
                default: result = 32'h0;
            endcase
        end

        // ------------------------------------------------------------------
        // Quadrant 1
        // ------------------------------------------------------------------
        2'b01: begin
            unique casez (c[15:13])
                3'b000: begin
                    // C.NOP / C.ADDI -> ADDI rd, rd, nzimm
                    // nzimm = sext({c[12],c[6:2]})
                    logic [11:0] imm;
                    imm = {{6{c[12]}}, c[12], c[6:2]};
                    result = {imm, frd, 3'b000, frd, 7'b0010011};
                end
                3'b001: begin
                    // C.ADDIW -> ADDIW rd, rd, imm  (RV64, rd!=0)
                    logic [11:0] imm;
                    imm = {{6{c[12]}}, c[12], c[6:2]};
                    if (frd == 5'h0)
                        result = 32'h0; // reserved
                    else
                        result = {imm, frd, 3'b000, frd, 7'b0011011};
                end
                3'b010: begin
                    // C.LI -> ADDI rd, x0, imm
                    logic [11:0] imm;
                    imm = {{6{c[12]}}, c[12], c[6:2]};
                    result = {imm, 5'h0, 3'b000, frd, 7'b0010011};
                end
                3'b011: begin
                    if (frd == 5'd2) begin
                        // C.ADDI16SP -> ADDI x2, x2, nzimm[9:4]
                        // nzimm={sext(c[12]),c[4:3],c[5],c[2],c[6],4'b0}
                        logic [11:0] imm;
                        imm = {{3{c[12]}}, c[4:3], c[5], c[2],
                               c[6], 4'b0000};
                        if (imm == 12'h0)
                            result = 32'h0; // reserved
                        else
                            result = {imm, 5'd2, 3'b000, 5'd2,
                                      7'b0010011};
                    end else begin
                        // C.LUI -> LUI rd, nzimm[31:12]
                        // nzimm[31:12] = sext({c[12],c[6:2]})
                        logic [19:0] imm;
                        imm = {{15{c[12]}}, c[6:2]};
                        if (imm == 20'h0 || imm == 20'hFFFFF)
                            result = 32'h0; // reserved
                        else
                            result = {imm, frd, 7'b0110111};
                    end
                end
                3'b100: begin
                    // Misc-ALU (SRLI, SRAI, ANDI, SUB, XOR, OR, AND,
                    //           SUBW, ADDW for RV64)
                    unique casez (c[11:10])
                        2'b00: begin
                            // C.SRLI -> SRLI rs1', rs1', shamt
                            // RV64 I-type shift: {funct6,shamt6,rs1,f3,rd,op}
                            result = {6'b000000, shamt6, crs1,
                                      3'b101, crs1, 7'b0010011};
                        end
                        2'b01: begin
                            // C.SRAI -> SRAI rs1', rs1', shamt
                            result = {6'b010000, shamt6, crs1,
                                      3'b101, crs1, 7'b0010011};
                        end
                        2'b10: begin
                            // C.ANDI -> ANDI rs1', rs1', imm
                            logic [11:0] imm;
                            imm = {{6{c[12]}}, c[12], c[6:2]};
                            result = {imm, crs1, 3'b111, crs1,
                                      7'b0010011};
                        end
                        2'b11: begin
                            if (c[12] == 1'b0) begin
                                unique casez (c[6:5])
                                    2'b00: // C.SUB
                                        result = {7'b0100000, crs2,
                                                  crs1, 3'b000, crs1,
                                                  7'b0110011};
                                    2'b01: // C.XOR
                                        result = {7'b0000000, crs2,
                                                  crs1, 3'b100, crs1,
                                                  7'b0110011};
                                    2'b10: // C.OR
                                        result = {7'b0000000, crs2,
                                                  crs1, 3'b110, crs1,
                                                  7'b0110011};
                                    2'b11: // C.AND
                                        result = {7'b0000000, crs2,
                                                  crs1, 3'b111, crs1,
                                                  7'b0110011};
                                    default: result = 32'h0;
                                endcase
                            end else begin
                                unique casez (c[6:5])
                                    2'b00: // C.SUBW  (RV64)
                                        result = {7'b0100000, crs2,
                                                  crs1, 3'b000, crs1,
                                                  7'b0111011};
                                    2'b01: // C.ADDW  (RV64)
                                        result = {7'b0000000, crs2,
                                                  crs1, 3'b000, crs1,
                                                  7'b0111011};
                                    2'b10: begin
                                        // c.mul (6..5=2) -> MULW rd',rd',rs2'
                                        // MULW: funct7=0000001,f3=000,op32
                                        result = {7'b0000001, crs2,
                                                  crs1, 3'b000, crs1,
                                                  7'b0111011};
                                    end
                                    2'b11: begin
                                        // Zcb single-reg ops: dispatch c[4:2]
                                        unique casez (c[4:2])
                                            3'b000: begin
                                                // c.zext.b (4..2=0)
                                                // -> ANDI rd',rd',0xFF
                                                result = {12'h0FF, crs1,
                                                          3'b111, crs1,
                                                          7'b0010011};
                                            end
                                            3'b001: begin
                                                // c.sext.b (4..2=1)
                                                // -> SEXT.B (Zbb)
                                                // funct7=0110000,r5=00100
                                                result = {7'b0110000,
                                                          5'b00100,
                                                          crs1, 3'b001,
                                                          crs1,
                                                          7'b0010011};
                                            end
                                            3'b010: begin
                                                // c.zext.h (4..2=2)
                                                // -> ZEXT.H (Zbb, RV64)
                                                // funct7=0000100,rs2=x0
                                                result = {7'b0000100,
                                                          5'b00000,
                                                          crs1, 3'b100,
                                                          crs1,
                                                          7'b0111011};
                                            end
                                            3'b011: begin
                                                // c.sext.h (4..2=3)
                                                // -> SEXT.H (Zbb)
                                                // funct7=0110000,r5=00101
                                                result = {7'b0110000,
                                                          5'b00101,
                                                          crs1, 3'b001,
                                                          crs1,
                                                          7'b0010011};
                                            end
                                            3'b100: begin
                                                // c.zext.w (4..2=4)
                                                // -> ADD.UW rd',rd',x0 (Zba)
                                                // NOTE: not in rv_zcb file
                                                // funct7=0000100,rs2=x0
                                                result = {7'b0000100,
                                                          5'b00000,
                                                          crs1, 3'b000,
                                                          crs1,
                                                          7'b0111011};
                                            end
                                            3'b101: begin
                                                // c.not (4..2=5)
                                                // -> XORI rd',rd',-1
                                                result = {12'hFFF, crs1,
                                                          3'b100, crs1,
                                                          7'b0010011};
                                            end
                                            default:
                                                result = 32'h0; // reserved
                                        endcase
                                    end
                                    default: result = 32'h0; // reserved
                                endcase
                            end
                        end
                        default: result = 32'h0;
                    endcase
                end
                3'b101: begin
                    // C.J -> JAL x0, jimm
                    // offset bits: j11=c[12],j4=c[11],j9=c[10],j8=c[9],
                    //   j10=c[8],j6=c[7],j7=c[6],j3=c[5],j2=c[4],
                    //   j1=c[3],j5=c[2]
                    // JAL:{imm[20],imm[10:1],imm[11],imm[19:12],rd,op}
                    // imm[20]=j11(sext), imm[19:12]={8{j11}}, imm[11]=j11
                    result = {c[12],
                              c[8], c[10], c[9], c[6], c[7],
                              c[2], c[11], c[5], c[4], c[3],
                              c[12],
                              {8{c[12]}},
                              5'h0, 7'b1101111};
                end
                3'b110: begin
                    // C.BEQZ -> BEQ rs1', x0, bimm
                    // offset: b8=c[12],b7=c[6],b6=c[5],b5=c[2],
                    //         b4=c[11],b3=c[10],b2=c[4],b1=c[3]
                    // B-type:{imm[12],imm[10:5],rs2,rs1,f3,imm[4:1],
                    //          imm[11],opcode}
                    // imm[12]=b8, imm[11]=0, imm[10:8]={0,0,b8},
                    // imm[7:5]={b7,b6,b5}
                    result = {c[12],
                              2'b00, c[12], c[6], c[5], c[2],
                              5'h0, crs1, 3'b000,
                              c[11], c[10], c[4], c[3],
                              1'b0, 7'b1100011};
                end
                3'b111: begin
                    // C.BNEZ -> BNE rs1', x0, bimm  (same as BEQZ)
                    result = {c[12],
                              2'b00, c[12], c[6], c[5], c[2],
                              5'h0, crs1, 3'b001,
                              c[11], c[10], c[4], c[3],
                              1'b0, 7'b1100011};
                end
                default: result = 32'h0;
            endcase
        end

        // ------------------------------------------------------------------
        // Quadrant 2
        // ------------------------------------------------------------------
        2'b10: begin
            unique casez (c[15:13])
                3'b000: begin
                    // C.SLLI -> SLLI rd, rd, shamt  (rd!=0, shamt!=0)
                    if (frd == 5'h0 || shamt6 == 6'h0)
                        result = 32'h0;
                    else
                        result = {6'b000000, shamt6, frd, 3'b001, frd,
                                  7'b0010011};
                end
                3'b001: begin
                    // C.FLDSP -> FLD rd, x2, uimm  (RV64)
                    // uimm = {c[4:2],c[12],c[6:5],3'b000}
                    logic [8:0] uimm;
                    uimm = {c[4:2], c[12], c[6:5], 3'b000};
                    result = {3'b000, uimm, 5'd2, 3'b011, frd,
                              7'b0000111};
                end
                3'b010: begin
                    // C.LWSP -> LW rd, x2, uimm  (rd!=0)
                    // uimm = {c[3:2],c[12],c[6:4],2'b00}
                    logic [7:0] uimm;
                    uimm = {c[3:2], c[12], c[6:4], 2'b00};
                    if (frd == 5'h0)
                        result = 32'h0;
                    else
                        result = {4'b0000, uimm, 5'd2, 3'b010, frd,
                                  7'b0000011};
                end
                3'b011: begin
                    // C.LDSP -> LD rd, x2, uimm  (RV64, rd!=0)
                    // uimm = {c[4:2],c[12],c[6:5],3'b000}
                    logic [8:0] uimm;
                    uimm = {c[4:2], c[12], c[6:5], 3'b000};
                    if (frd == 5'h0)
                        result = 32'h0;
                    else
                        result = {3'b000, uimm, 5'd2, 3'b011, frd,
                                  7'b0000011};
                end
                3'b100: begin
                    if (c[12] == 1'b0) begin
                        if (frs2 == 5'h0) begin
                            // C.JR -> JALR x0, rs1, 0  (rs1!=0)
                            if (frd == 5'h0)
                                result = 32'h0; // reserved
                            else
                                result = {12'h0, frd, 3'b000, 5'h0,
                                          7'b1100111};
                        end else begin
                            // C.MV -> ADD rd, x0, rs2
                            result = {7'b0000000, frs2, 5'h0,
                                      3'b000, frd, 7'b0110011};
                        end
                    end else begin
                        if (frd == 5'h0 && frs2 == 5'h0) begin
                            // C.EBREAK
                            result = 32'h00100073;
                        end else if (frs2 == 5'h0) begin
                            // C.JALR -> JALR x1, rs1, 0
                            result = {12'h0, frd, 3'b000, 5'd1,
                                      7'b1100111};
                        end else begin
                            // C.ADD -> ADD rd, rd, rs2
                            result = {7'b0000000, frs2, frd,
                                      3'b000, frd, 7'b0110011};
                        end
                    end
                end
                3'b101: begin
                    // C.FSDSP -> FSD rs2, x2, uimm
                    // uimm = {c[9:7],c[12:10],3'b000}
                    logic [8:0] uimm;
                    uimm = {c[9:7], c[12:10], 3'b000};
                    // FSD: {imm[11:5],rs2,rs1,3'b011,imm[4:0],opcode}
                    result = {3'b000, uimm[8:3], frs2, 5'd2, 3'b011,
                              uimm[2:0], 7'b0100111};
                end
                3'b110: begin
                    // C.SWSP -> SW rs2, x2, uimm
                    // uimm[7:0] = {c[8:7],c[12:9],2'b00}
                    // S-type: {imm[11:5],rs2,rs1,f3,imm[4:0],opcode}
                    // imm[11:5]={4'b0,uimm[7:5]}, imm[4:0]=uimm[4:0]
                    logic [7:0] uimm;
                    uimm = {c[8:7], c[12:9], 2'b00};
                    result = {4'b0000, uimm[7:5], frs2, 5'd2,
                              3'b010, uimm[4:0], 7'b0100011};
                end
                3'b111: begin
                    // C.SDSP -> SD rs2, x2, uimm  (RV64)
                    // uimm = {c[9:7],c[12:10],3'b000}
                    logic [8:0] uimm;
                    uimm = {c[9:7], c[12:10], 3'b000};
                    result = {3'b000, uimm[8:3], frs2, 5'd2, 3'b011,
                              uimm[2:0], 7'b0100011};
                end
                default: result = 32'h0;
            endcase
        end

        // Quadrant 3 = 32-bit instruction, should not reach this function
        default: result = 32'h0;
    endcase

    return result;
endfunction

// ---------------------------------------------------------------------------
// Per-slot parallel expansion
// ---------------------------------------------------------------------------

genvar i;
generate
    for (i = 0; i < SLOTS; i++) begin : g_expand
        always_comb begin
            exp_valid[i] = slot_valid[i];
            if (!slot_valid[i]) begin
                exp_bundle[i] = 32'h0;
            end else if (slot_is_rvc[i]) begin
                // Expand 16-bit RVC from lower half of slot
                exp_bundle[i] = expand_rvc(fetch_bundle[i][15:0]);
            end else begin
                // Already 32-bit, pass through unchanged
                exp_bundle[i] = fetch_bundle[i];
            end
        end
    end
endgenerate

endmodule

`default_nettype wire
