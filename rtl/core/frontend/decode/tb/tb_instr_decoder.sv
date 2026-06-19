// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// tb_instr_decoder.sv
// Self-checking testbench for instr_decoder.
// Drives predecode_pkt_t bundles (wrapping raw instructions) and
// verifies decoded fields in decode_pkt_t bundles.
// Uses a free-running clock for Verilator 5.020 --timing compatibility.
// DECODE-010: input changed from raw bits to predecode_pkt_t.
//   make_predecode_pkt() wraps a raw 32-bit instruction into a
//   predecode_pkt_t with is_vsetvl/needs_vtype computed correctly.
//   All 543 existing tests pass unchanged via the updated drive() task.
// ---------------------------------------------------------------------------
// ===================================================================
`default_nettype none
`timescale 1ns/1ps

/* verilator lint_off IMPORTSTAR */
import decode_pkg::*;
/* verilator lint_on IMPORTSTAR */

module tb;

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------
logic clk;
initial clk = 0;
/* verilator lint_off BLKSEQ */
always #5 clk = ~clk;
/* verilator lint_on BLKSEQ */

// ---------------------------------------------------------------------------
// DUT ports
// ---------------------------------------------------------------------------
ext_enable_t     ext_enable;
predecode_pkt_t  [SLOTS-1:0] predecode_bundle;
decode_pkt_t     [SLOTS-1:0] decode_bundle;
/* verilator lint_off UNUSEDSIGNAL */
vec_decode_pkt_t [SLOTS-1:0] vec_decode_bundle;
logic            [SLOTS-1:0] is_vector;
predecode_pkt_t  [SLOTS-1:0] predecode_out;
/* verilator lint_on UNUSEDSIGNAL */

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
instr_decoder dut (
    .ext_enable        (ext_enable),
    .predecode_bundle  (predecode_bundle),
    .decode_bundle     (decode_bundle),
    .vec_decode_bundle (vec_decode_bundle),
    .is_vector         (is_vector),
    .predecode_out     (predecode_out)
);

// ---------------------------------------------------------------------------
// Test infrastructure
// ---------------------------------------------------------------------------
int pass_count;
int fail_count;

// ---------------------------------------------------------------------------
// make_predecode_pkt: wrap a raw 32-bit instruction into predecode_pkt_t
// Sets valid=1, computes is_vsetvl and needs_vtype from opcode/funct3.
// vtype_hazard is left 0 -- intra-bundle policy resolved by rename.
// may_be_branch set for JAL/JALR/BRANCH opcodes (conservative hint).
// ---------------------------------------------------------------------------
function automatic predecode_pkt_t make_predecode_pkt(
    input logic [31:0] instr
);
    predecode_pkt_t pkt;
    logic [6:0]     opc;
    logic [2:0]     f3;
    logic           vec_w;
    pkt          = '0;
    pkt.valid    = 1'b1;
    pkt.instr    = instr;
    opc          = instr[6:0];
    f3           = instr[14:12];
    // vector memory width: funct3 in {000,101,110,111}
    vec_w = (f3 == 3'b000) | (f3 == 3'b101) |
            (f3 == 3'b110) | (f3 == 3'b111);
    pkt.is_vsetvl   = (opc == 7'b1010111) & (f3 == 3'b111);
    pkt.needs_vtype = ((opc == 7'b1010111) & (f3 != 3'b111)) |
                      ((opc == 7'b0000111) & vec_w)           |
                      ((opc == 7'b0100111) & vec_w);
    pkt.vtype_hazard  = 1'b0;
    pkt.may_be_branch = (opc == 7'b1101111) | (opc == 7'b1100111) |
                        (opc == 7'b1100011);
    return pkt;
endfunction

task automatic clear_all();
    int s;
    for (s = 0; s < SLOTS; s++) begin
        predecode_bundle[s] = '0;
    end
endtask

task automatic drive(
    input int          slot,
    input logic [31:0] instr
);
    predecode_bundle[slot] = make_predecode_pkt(instr);
endtask

`define CHECK_FIELD(slot, field, expected, tname) \
    if (decode_bundle[slot].field !== (expected)) begin \
        $display("FAIL [%s] slot=%0d .%s  got=%0h  exp=%0h", \
                 tname, slot, `"field`", \
                 decode_bundle[slot].field, expected); \
        fail_count++; \
    end else begin \
        pass_count++; \
    end

`define CHECK_VEC(slot, field, expected, tname) \
    if (vec_decode_bundle[slot].field !== (expected)) begin \
        $display("FAIL [%s] slot=%0d vec.%s  got=%0h  exp=%0h", \
                 tname, slot, `"field`", \
                 vec_decode_bundle[slot].field, expected); \
        fail_count++; \
    end else begin \
        pass_count++; \
    end

task automatic check_pkt(
    input int              slot,
    input logic [6:0]      exp_opcode,
    input logic [4:0]      exp_rd,
    input logic [4:0]      exp_rs1,
    input logic [4:0]      exp_rs2,
    input logic [31:0]     exp_imm,
    input instr_fmt_t      exp_fmt,
    input alu_op_t         exp_alu,
    input logic            exp_is_branch,
    input logic            exp_is_jump,
    input logic            exp_is_load,
    input logic            exp_is_store,
    input logic            exp_is_illegal,
    input string           tname
);
    if (!decode_bundle[slot].valid) begin
        $display("FAIL [%s] slot=%0d valid=0 expected=1", tname, slot);
        fail_count++;
        return;
    end
    `CHECK_FIELD(slot, opcode,     exp_opcode,     tname)
    `CHECK_FIELD(slot, rd,         exp_rd,         tname)
    `CHECK_FIELD(slot, rs1,        exp_rs1,        tname)
    `CHECK_FIELD(slot, rs2,        exp_rs2,        tname)
    `CHECK_FIELD(slot, imm,        exp_imm,        tname)
    `CHECK_FIELD(slot, fmt,        exp_fmt,        tname)
    `CHECK_FIELD(slot, alu_op,     exp_alu,        tname)
    `CHECK_FIELD(slot, is_branch,  exp_is_branch,  tname)
    `CHECK_FIELD(slot, is_jump,    exp_is_jump,    tname)
    `CHECK_FIELD(slot, is_load,    exp_is_load,    tname)
    `CHECK_FIELD(slot, is_store,   exp_is_store,   tname)
    `CHECK_FIELD(slot, is_illegal, exp_is_illegal, tname)
endtask

// ---------------------------------------------------------------------------
// Instruction encoding helpers
// ---------------------------------------------------------------------------
function automatic logic [31:0] enc_i(
    input logic [11:0] imm12,
    input logic [4:0]  rs1,
    input logic [2:0]  f3,
    input logic [4:0]  rd,
    input logic [6:0]  op
);
    return {imm12, rs1, f3, rd, op};
endfunction

function automatic logic [31:0] enc_r(
    input logic [6:0]  f7,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  f3,
    input logic [4:0]  rd,
    input logic [6:0]  op
);
    return {f7, rs2, rs1, f3, rd, op};
endfunction

function automatic logic [31:0] enc_s(
    input logic [11:0] imm12,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  f3,
    input logic [6:0]  op
);
    return {imm12[11:5], rs2, rs1, f3, imm12[4:0], op};
endfunction

/* verilator lint_off UNUSEDSIGNAL */
function automatic logic [31:0] enc_b(
    input logic [12:0] imm,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  f3,
    input logic [6:0]  op
);
    // imm is the full byte offset (bit 0 always 0); encode imm[12:1]
    return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], op};
endfunction
/* verilator lint_on UNUSEDSIGNAL */

function automatic logic [31:0] enc_u(
    input logic [31:12] imm,
    input logic [4:0]   rd,
    input logic [6:0]   op
);
    return {imm, rd, op};
endfunction

/* verilator lint_off UNUSEDSIGNAL */
function automatic logic [31:0] enc_j(
    input logic [20:0] imm,
    input logic [4:0]  rd,
    input logic [6:0]  op
);
    // imm is the full byte offset (bit 0 always 0); encode imm[20:1]
    return {imm[20], imm[10:1], imm[11], imm[19:12], rd, op};
endfunction
/* verilator lint_on UNUSEDSIGNAL */

// ---------------------------------------------------------------------------
// Opcode constants
// ---------------------------------------------------------------------------
localparam logic [6:0] OPLOAD   = 7'b0000011;
localparam logic [6:0] OPLOADFP  = 7'b0000111; // FP / vector loads  (0x07)
localparam logic [6:0] OPSTOREFP = 7'b0100111; // FP / vector stores (0x27)
localparam logic [6:0] OPIMM    = 7'b0010011;
localparam logic [6:0] OPAUIPC  = 7'b0010111;
localparam logic [6:0] OPIMM32  = 7'b0011011;
localparam logic [6:0] OPSTORE  = 7'b0100011;
localparam logic [6:0] OPREG    = 7'b0110011;
localparam logic [6:0] OPLUI    = 7'b0110111;
localparam logic [6:0] OPREG32  = 7'b0111011;
localparam logic [6:0] OPBRANCH = 7'b1100011;
localparam logic [6:0] OPJALR   = 7'b1100111;
localparam logic [6:0] OPJAL    = 7'b1101111;
localparam logic [6:0] OPSYSTEM = 7'b1110011;
localparam logic [6:0] OPVECTOR = 7'b1010111; // OP-V (0x57)

// ---------------------------------------------------------------------------
// Vector instruction encoding helpers
// ---------------------------------------------------------------------------

// vsetvli rd, rs1, vtype_imm
//   inst[31]=0, inst[30:20]=zimm11, inst[19:15]=rs1
//   inst[14:12]=3'b111, inst[11:7]=rd, inst[6:0]=0x57
//   zimm11: [10:8]=0 (reserved), [7]=vma, [6]=vta, [5:3]=vsew, [2:0]=vlmul
function automatic logic [31:0] enc_vsetvli(
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input logic [2:0] vsew,
    input logic [2:0] vlmul,
    input logic       vta,
    input logic       vma
);
    logic [10:0] zimm11;
    zimm11 = {3'b000, vma, vta, vsew, vlmul};
    return {1'b0, zimm11, rs1, 3'b111, rd, OPVECTOR};
endfunction

// vsetivli rd, uimm5, vtype_imm
//   inst[31:30]=2'b11, inst[29:20]=zimm10, inst[19:15]=uimm5 (AVL)
//   inst[14:12]=3'b111, inst[11:7]=rd, inst[6:0]=0x57
//   zimm10: [9:8]=0 (reserved), [7]=vma, [6]=vta, [5:3]=vsew, [2:0]=vlmul
function automatic logic [31:0] enc_vsetivli(
    input logic [4:0] rd,
    input logic [4:0] uimm5,
    input logic [2:0] vsew,
    input logic [2:0] vlmul,
    input logic       vta,
    input logic       vma
);
    logic [9:0] zimm10;
    zimm10 = {2'b00, vma, vta, vsew, vlmul};
    return {2'b11, zimm10, uimm5, 3'b111, rd, OPVECTOR};
endfunction

// vsetvl rd, rs1, rs2
//   inst[31:25]=7'b1000000, inst[24:20]=rs2, inst[19:15]=rs1
//   inst[14:12]=3'b111, inst[11:7]=rd, inst[6:0]=0x57
function automatic logic [31:0] enc_vsetvl(
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input logic [4:0] rs2
);
    return {7'b1000000, rs2, rs1, 3'b111, rd, OPVECTOR};
endfunction

// vadd.vv vd, vs1, vs2  (funct6=0x00, funct3=OPIVV=3'b000)
//   inst[31:26]=6'b000000, inst[25]=vm, inst[24:20]=vs2
//   inst[19:15]=vs1, inst[14:12]=3'b000, inst[11:7]=vd
function automatic logic [31:0] enc_vadd_vv(
    input logic [4:0] vd,
    input logic [4:0] vs1,
    input logic [4:0] vs2,
    input logic       vm    // 1=unmasked, 0=masked
);
    return {6'b000000, vm, vs2, vs1, 3'b000, vd, OPVECTOR};
endfunction

// vle32.v vd, (rs1): opcode=0x07, nf=0, mop=00, vm, [24:20]=0, funct3=110
// DECODE-008: previously misidentified as FP load; now correctly decoded.
function automatic logic [31:0] enc_vle32v(
    input logic [4:0] vd,
    input logic [4:0] rs1,
    input logic       vm
);
    return {3'b000, 1'b0, 2'b00, vm, 5'b00000, rs1, 3'b110, vd, OPLOADFP};
endfunction

// Generic unit-stride vector load: nf=0, mop=00, vm, [24:20]=0
// width: 3'b000=EEW8, 3'b101=EEW16, 3'b110=EEW32, 3'b111=EEW64
function automatic logic [31:0] enc_vlev(
    input logic [4:0] vd,
    input logic [4:0] rs1,
    input logic [2:0] width,
    input logic       vm
);
    return {3'b000, 1'b0, 2'b00, vm, 5'b00000, rs1, width, vd, OPLOADFP};
endfunction

// Generic unit-stride vector store: nf=0, mop=00, vm, [24:20]=0
function automatic logic [31:0] enc_vsev(
    input logic [4:0] vs3,
    input logic [4:0] rs1,
    input logic [2:0] width,
    input logic       vm
);
    return {3'b000, 1'b0, 2'b00, vm, 5'b00000, rs1, width, vs3, OPSTOREFP};
endfunction

// Strided vector load: nf=0, mop=10, vm, rs2=stride GPR
function automatic logic [31:0] enc_vlsev(
    input logic [4:0] vd,
    input logic [4:0] rs1,
    input logic [4:0] rs2,
    input logic [2:0] width,
    input logic       vm
);
    return {3'b000, 1'b0, 2'b10, vm, rs2, rs1, width, vd, OPLOADFP};
endfunction

// Unordered indexed vector load: nf=0, mop=01, vm, vs2=index
function automatic logic [31:0] enc_vluxev(
    input logic [4:0] vd,
    input logic [4:0] rs1,
    input logic [4:0] vs2,
    input logic [2:0] width,
    input logic       vm
);
    return {3'b000, 1'b0, 2'b01, vm, vs2, rs1, width, vd, OPLOADFP};
endfunction

// Mask load: nf=0, mop=00, vm=1, [24:20]=5'b01011, width=000
// vlm.v vd, (rs1)
function automatic logic [31:0] enc_vlmv(
    input logic [4:0] vd,
    input logic [4:0] rs1
);
    return {3'b000, 1'b0, 2'b00, 1'b1, 5'b01011, rs1, 3'b000, vd, OPLOADFP};
endfunction

// Whole-register load: nf=0, mop=00, vm=1, [24:20]=5'b01000
// vl1re8.v: nf=000 (1 reg), width=000 (EEW8)
function automatic logic [31:0] enc_vl1rev(
    input logic [4:0] vd,
    input logic [4:0] rs1
);
    return {3'b000, 1'b0, 2'b00, 1'b1, 5'b01000, rs1, 3'b000, vd, OPLOADFP};
endfunction

// Fault-only-first load: nf=0, mop=00, vm, [24:20]=5'b10000
// vle32ff.v: width=110 (EEW32)
function automatic logic [31:0] enc_vleffv(
    input logic [4:0] vd,
    input logic [4:0] rs1,
    input logic [2:0] width,
    input logic       vm
);
    return {3'b000, 1'b0, 2'b00, vm, 5'b10000, rs1, width, vd, OPLOADFP};
endfunction

// Scalar FP load FLD: opcode=0x07, funct3=011
// fld rd, imm(rs1)
function automatic logic [31:0] enc_fld(
    input logic [11:0] imm,
    input logic [4:0]  rs1,
    input logic [4:0]  rd
);
    return {imm, rs1, 3'b011, rd, OPLOADFP};
endfunction

// Scalar FP store FSD: opcode=0x27, funct3=011
// fsd rs2, imm(rs1)
function automatic logic [31:0] enc_fsd(
    input logic [11:0] imm,
    input logic [4:0]  rs1,
    input logic [4:0]  rs2
);
    return {imm[11:5], rs2, rs1, 3'b011, imm[4:0], OPSTOREFP};
endfunction

// Whole-register store: nf=0, mop=00, vm=1, [24:20]=5'b01000
// vs1re8.v: nf=000 (1 reg), width=000 (EEW8)
function automatic logic [31:0] enc_vs1rev(
    input logic [4:0] vs3,
    input logic [4:0] rs1
);
    return {3'b000, 1'b0, 2'b00, 1'b1, 5'b01000, rs1,
            3'b000, vs3, OPSTOREFP};
endfunction

// Unit-stride segment load: nf>0, mop=00, vm=1, [24:20]=0
// vlseg{nf+1}e{eew}.v
function automatic logic [31:0] enc_vlsegv(
    input logic [4:0] vd,
    input logic [4:0] rs1,
    input logic [2:0] nf,    // nf = nfields-1
    input logic [2:0] width, // EEW encoding
    input logic       vm
);
    return {nf, 1'b0, 2'b00, vm, 5'b00000, rs1, width, vd, OPLOADFP};
endfunction

// Unit-stride segment store: nf>0, mop=00, vm=1, [24:20]=0
// vsseg{nf+1}e{eew}.v
function automatic logic [31:0] enc_vssegv(
    input logic [4:0] vs3,
    input logic [4:0] rs1,
    input logic [2:0] nf,
    input logic [2:0] width,
    input logic       vm
);
    return {nf, 1'b0, 2'b00, vm, 5'b00000, rs1, width, vs3, OPSTOREFP};
endfunction

// Strided segment load: nf>0, mop=10, vm, rs2=stride GPR
// vlsseg{nf+1}e{eew}.v
function automatic logic [31:0] enc_vlssegv(
    input logic [4:0] vd,
    input logic [4:0] rs1,
    input logic [4:0] rs2,
    input logic [2:0] nf,
    input logic [2:0] width,
    input logic       vm
);
    return {nf, 1'b0, 2'b10, vm, rs2, rs1, width, vd, OPLOADFP};
endfunction

// Unordered indexed segment load: nf>0, mop=01, vm, vs2=index
// vluxseg{nf+1}e{eew}.v
function automatic logic [31:0] enc_vluxsegv(
    input logic [4:0] vd,
    input logic [4:0] rs1,
    input logic [4:0] vs2,
    input logic [2:0] nf,
    input logic [2:0] width,
    input logic       vm
);
    return {nf, 1'b0, 2'b01, vm, vs2, rs1, width, vd, OPLOADFP};
endfunction

// Ordered indexed segment load: nf>0, mop=11, vm, vs2=index
// vloxseg{nf+1}e{eew}.v
function automatic logic [31:0] enc_vloxsegv(
    input logic [4:0] vd,
    input logic [4:0] rs1,
    input logic [4:0] vs2,
    input logic [2:0] nf,
    input logic [2:0] width,
    input logic       vm
);
    return {nf, 1'b0, 2'b11, vm, vs2, rs1, width, vd, OPLOADFP};
endfunction

// ---------------------------------------------------------------------------
// Test cases
// ---------------------------------------------------------------------------
initial begin
    pass_count   = 0;
    fail_count   = 0;
    ext_enable   = RVA23_ENABLE; // all extensions enabled by default
    predecode_bundle = '0;

    // -----------------------------------------------------------------------
    // T1: All slots invalid - valid=0
    // -----------------------------------------------------------------------
    @(posedge clk);
    for (int s = 0; s < SLOTS; s++) begin
        if (decode_bundle[s].valid !== 1'b0) begin
            $display("FAIL [T1_invalid] slot=%0d valid!=0", s);
            fail_count++;
        end else
            pass_count++;
    end

    // -----------------------------------------------------------------------
    // T2: ADDI x1, x2, 42  (OP-IMM, I-type)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_i(12'd42, 5'd2, 3'b000, 5'd1, OPIMM));
    @(posedge clk);
    check_pkt(0, OPIMM, 5'd1, 5'd2, 5'd0, 32'd42,
              FMT_I, ALU_ADD, 0, 0, 0, 0, 0, "T2_ADDI_x1_x2_42");

    // -----------------------------------------------------------------------
    // T3: LW x5, -4(x2)
    // -----------------------------------------------------------------------
    clear_all();
    drive(1, enc_i(12'hFFC, 5'd2, 3'b010, 5'd5, OPLOAD));
    @(posedge clk);
    check_pkt(1, OPLOAD, 5'd5, 5'd2, 5'd0, 32'hFFFFFFFC,
              FMT_I, ALU_LW, 0, 0, 1, 0, 0, "T3_LW_x5_m4_x2");

    // -----------------------------------------------------------------------
    // T4: SW x5, 8(x2)
    // -----------------------------------------------------------------------
    clear_all();
    drive(2, enc_s(12'd8, 5'd5, 5'd2, 3'b010, OPSTORE));
    @(posedge clk);
    check_pkt(2, OPSTORE, 5'd0, 5'd2, 5'd5, 32'd8,
              FMT_S, ALU_SW, 0, 0, 0, 1, 0, "T4_SW_x5_8_x2");

    // -----------------------------------------------------------------------
    // T5: ADD x3, x1, x2
    // -----------------------------------------------------------------------
    clear_all();
    drive(3, enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, OPREG));
    @(posedge clk);
    check_pkt(3, OPREG, 5'd3, 5'd1, 5'd2, 32'd0,
              FMT_R, ALU_ADD, 0, 0, 0, 0, 0, "T5_ADD_x3_x1_x2");

    // -----------------------------------------------------------------------
    // T6: SUB x3, x1, x2
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_r(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd3, OPREG));
    @(posedge clk);
    check_pkt(0, OPREG, 5'd3, 5'd1, 5'd2, 32'd0,
              FMT_R, ALU_SUB, 0, 0, 0, 0, 0, "T6_SUB_x3_x1_x2");

    // -----------------------------------------------------------------------
    // T7: BEQ x1, x2, 16
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_b(13'd16, 5'd2, 5'd1, 3'b000, OPBRANCH));
    @(posedge clk);
    check_pkt(0, OPBRANCH, 5'd0, 5'd1, 5'd2, 32'd16,
              FMT_B, ALU_BEQ, 1, 0, 0, 0, 0, "T7_BEQ_x1_x2_16");

    // -----------------------------------------------------------------------
    // T8: JAL x1, 256
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_j(21'd256, 5'd1, OPJAL));
    @(posedge clk);
    check_pkt(0, OPJAL, 5'd1, 5'd0, 5'd0, 32'd256,
              FMT_J, ALU_JAL, 0, 1, 0, 0, 0, "T8_JAL_x1_256");

    // -----------------------------------------------------------------------
    // T9: JALR x1, x5, 0
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_i(12'd0, 5'd5, 3'b000, 5'd1, OPJALR));
    @(posedge clk);
    check_pkt(0, OPJALR, 5'd1, 5'd5, 5'd0, 32'd0,
              FMT_I, ALU_JALR, 0, 1, 0, 0, 0, "T9_JALR_x1_x5_0");

    // -----------------------------------------------------------------------
    // T10: LUI x5, 0xDEAD
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_u(20'hDEAD0, 5'd5, OPLUI));
    @(posedge clk);
    check_pkt(0, OPLUI, 5'd5, 5'd0, 5'd0, 32'hDEAD0000,
              FMT_U, ALU_LUI, 0, 0, 0, 0, 0, "T10_LUI_x5_DEAD");

    // -----------------------------------------------------------------------
    // T11: AUIPC x5, 1
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_u(20'h1, 5'd5, OPAUIPC));
    @(posedge clk);
    check_pkt(0, OPAUIPC, 5'd5, 5'd0, 5'd0, 32'h00001000,
              FMT_U, ALU_AUIPC, 0, 0, 0, 0, 0, "T11_AUIPC_x5_1");

    // -----------------------------------------------------------------------
    // T12: LD x1, 0(x2)  (RV64)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_i(12'd0, 5'd2, 3'b011, 5'd1, OPLOAD));
    @(posedge clk);
    check_pkt(0, OPLOAD, 5'd1, 5'd2, 5'd0, 32'd0,
              FMT_I, ALU_LD, 0, 0, 1, 0, 0, "T12_LD_x1_0_x2");

    // -----------------------------------------------------------------------
    // T13: SD x5, 0(x2)  (RV64)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_s(12'd0, 5'd5, 5'd2, 3'b011, OPSTORE));
    @(posedge clk);
    check_pkt(0, OPSTORE, 5'd0, 5'd2, 5'd5, 32'd0,
              FMT_S, ALU_SD, 0, 0, 0, 1, 0, "T13_SD_x5_0_x2");

    // -----------------------------------------------------------------------
    // T14: ADDIW x1, x2, 10  (OP-IMM-32, RV64)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_i(12'd10, 5'd2, 3'b000, 5'd1, OPIMM32));
    @(posedge clk);
    check_pkt(0, OPIMM32, 5'd1, 5'd2, 5'd0, 32'd10,
              FMT_I, ALU_ADDW, 0, 0, 0, 0, 0, "T14_ADDIW_x1_x2_10");

    // -----------------------------------------------------------------------
    // T15: ADDW x3, x1, x2  (OP-32, RV64)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, OPREG32));
    @(posedge clk);
    check_pkt(0, OPREG32, 5'd3, 5'd1, 5'd2, 32'd0,
              FMT_R, ALU_ADDW, 0, 0, 0, 0, 0, "T15_ADDW_x3_x1_x2");

    // -----------------------------------------------------------------------
    // T16: MUL x3, x1, x2  (M extension)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd3, OPREG));
    @(posedge clk);
    check_pkt(0, OPREG, 5'd3, 5'd1, 5'd2, 32'd0,
              FMT_R, ALU_MUL, 0, 0, 0, 0, 0, "T16_MUL_x3_x1_x2");

    // -----------------------------------------------------------------------
    // T17: ECALL
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, 32'h00000073);
    @(posedge clk);
    check_pkt(0, OPSYSTEM, 5'd0, 5'd0, 5'd0, 32'd0,
              FMT_I, ALU_ECALL, 0, 0, 0, 0, 0, "T17_ECALL");

    // -----------------------------------------------------------------------
    // T18: EBREAK
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, 32'h00100073);
    @(posedge clk);
    check_pkt(0, OPSYSTEM, 5'd0, 5'd0, 5'd0, 32'd0,
              FMT_I, ALU_EBREAK, 0, 0, 0, 0, 0, "T18_EBREAK");

    // -----------------------------------------------------------------------
    // T19: Illegal instruction
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, 32'h0000007F);  // reserved opcode
    @(posedge clk);
    if (!decode_bundle[0].is_illegal) begin
        $display("FAIL [T19_illegal] is_illegal should be 1");
        fail_count++;
    end else begin
        $display("PASS [T19_illegal] is_illegal=1");
        pass_count++;
    end

    // -----------------------------------------------------------------------
    // T20: 8-wide simultaneous decode
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_i(12'd1, 5'd0, 3'b000, 5'd1, OPIMM));    // ADDI
    drive(1, enc_i(12'd0, 5'd1, 3'b010, 5'd2, OPLOAD));   // LW
    drive(2, enc_s(12'd4, 5'd2, 5'd1, 3'b010, OPSTORE));  // SW
    drive(3, enc_r(7'b0, 5'd2, 5'd1, 3'b000, 5'd3, OPREG)); // ADD
    drive(4, enc_b(13'd8, 5'd2, 5'd1, 3'b001, OPBRANCH)); // BNE
    drive(5, enc_j(21'd4, 5'd0, OPJAL));                  // JAL
    drive(6, enc_u(20'h1, 5'd4, OPLUI));                  // LUI
    drive(7, enc_r(7'b0, 5'd2, 5'd1, 3'b000, 5'd5, OPREG32)); // ADDW
    @(posedge clk);

    if (decode_bundle[0].alu_op !== ALU_ADD || !decode_bundle[0].valid)
        begin $display("FAIL [T20] slot0 ADDI"); fail_count++; end
    else begin $display("PASS [T20] slot0 ADDI"); pass_count++; end

    if (decode_bundle[1].alu_op !== ALU_LW || !decode_bundle[1].is_load)
        begin $display("FAIL [T20] slot1 LW"); fail_count++; end
    else begin $display("PASS [T20] slot1 LW"); pass_count++; end

    if (decode_bundle[2].alu_op !== ALU_SW || !decode_bundle[2].is_store)
        begin $display("FAIL [T20] slot2 SW"); fail_count++; end
    else begin $display("PASS [T20] slot2 SW"); pass_count++; end

    if (decode_bundle[3].alu_op !== ALU_ADD)
        begin $display("FAIL [T20] slot3 ADD"); fail_count++; end
    else begin $display("PASS [T20] slot3 ADD"); pass_count++; end

    if (decode_bundle[4].alu_op !== ALU_BNE || !decode_bundle[4].is_branch)
        begin $display("FAIL [T20] slot4 BNE"); fail_count++; end
    else begin $display("PASS [T20] slot4 BNE"); pass_count++; end

    if (decode_bundle[5].alu_op !== ALU_JAL || !decode_bundle[5].is_jump)
        begin $display("FAIL [T20] slot5 JAL"); fail_count++; end
    else begin $display("PASS [T20] slot5 JAL"); pass_count++; end

    if (decode_bundle[6].alu_op !== ALU_LUI)
        begin $display("FAIL [T20] slot6 LUI"); fail_count++; end
    else begin $display("PASS [T20] slot6 LUI"); pass_count++; end

    if (decode_bundle[7].alu_op !== ALU_ADDW)
        begin $display("FAIL [T20] slot7 ADDW"); fail_count++; end
    else begin $display("PASS [T20] slot7 ADDW"); pass_count++; end

    // -----------------------------------------------------------------------
    // T21: uses_rd / uses_rs1 / uses_rs2 flags
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_j(21'd4, 5'd1, OPJAL));                  // JAL: rd only
    drive(1, enc_b(13'd8, 5'd2, 5'd1, 3'b000, OPBRANCH)); // BEQ: rs1+rs2
    drive(2, enc_r(7'b0, 5'd2, 5'd1, 3'b000, 5'd3, OPREG)); // ADD: all 3
    @(posedge clk);

    if (!decode_bundle[0].uses_rd || decode_bundle[0].uses_rs1 ||
        decode_bundle[0].uses_rs2)
        begin $display("FAIL [T21] JAL use flags"); fail_count++; end
    else begin $display("PASS [T21] JAL use flags"); pass_count++; end

    if (decode_bundle[1].uses_rd || !decode_bundle[1].uses_rs1 ||
        !decode_bundle[1].uses_rs2)
        begin $display("FAIL [T21] BEQ use flags"); fail_count++; end
    else begin $display("PASS [T21] BEQ use flags"); pass_count++; end

    if (!decode_bundle[2].uses_rd || !decode_bundle[2].uses_rs1 ||
        !decode_bundle[2].uses_rs2)
        begin $display("FAIL [T21] ADD use flags"); fail_count++; end
    else begin $display("PASS [T21] ADD use flags"); pass_count++; end

    // -----------------------------------------------------------------------
    // T22: Remaining branch types
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_b(13'd4, 5'd2, 5'd1, 3'b100, OPBRANCH)); // BLT
    drive(1, enc_b(13'd4, 5'd2, 5'd1, 3'b101, OPBRANCH)); // BGE
    drive(2, enc_b(13'd4, 5'd2, 5'd1, 3'b110, OPBRANCH)); // BLTU
    drive(3, enc_b(13'd4, 5'd2, 5'd1, 3'b111, OPBRANCH)); // BGEU
    @(posedge clk);

    if (decode_bundle[0].alu_op !== ALU_BLT)
        begin $display("FAIL [T22] BLT");  fail_count++; end
    else begin $display("PASS [T22] BLT");  pass_count++; end
    if (decode_bundle[1].alu_op !== ALU_BGE)
        begin $display("FAIL [T22] BGE");  fail_count++; end
    else begin $display("PASS [T22] BGE");  pass_count++; end
    if (decode_bundle[2].alu_op !== ALU_BLTU)
        begin $display("FAIL [T22] BLTU"); fail_count++; end
    else begin $display("PASS [T22] BLTU"); pass_count++; end
    if (decode_bundle[3].alu_op !== ALU_BGEU)
        begin $display("FAIL [T22] BGEU"); fail_count++; end
    else begin $display("PASS [T22] BGEU"); pass_count++; end

    // -----------------------------------------------------------------------
    // T23: SLLI x1, x1, 5  (OP-IMM, shift)
    // -----------------------------------------------------------------------
    clear_all();
    // SLLI: f7[6:1]=000000, shamt=5 in inst[25:20]
    drive(0, {6'b000000, 6'd5, 5'd1, 3'b001, 5'd1, OPIMM});
    @(posedge clk);
    if (decode_bundle[0].alu_op !== ALU_SLLI || decode_bundle[0].is_illegal)
        begin $display("FAIL [T23] SLLI"); fail_count++; end
    else begin $display("PASS [T23] SLLI"); pass_count++; end

    // -----------------------------------------------------------------------
    // T24: vsetvli x1, x2, e32m1ta
    //   vsew=e32 (3'b010), vlmul=m1 (3'b000), vta=1, vma=1
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_vsetvli(5'd1, 5'd2, 3'b010, 3'b000, 1'b1, 1'b1));
    @(posedge clk);
    if (!is_vector[0]) begin
        $display("FAIL [T24_vsetvli_e32m1ta] is_vector=0");
        fail_count++;
    end else
        pass_count++;
    `CHECK_VEC(0, is_vector,   1'b1,    "T24_vsetvli_e32m1ta")
    `CHECK_VEC(0, is_vsetvl,   1'b1,    "T24_vsetvli_e32m1ta")
    `CHECK_VEC(0, needs_vtype, 1'b0,    "T24_vsetvli_e32m1ta")
    `CHECK_VEC(0, vsew,        3'b010,  "T24_vsetvli_e32m1ta")
    `CHECK_VEC(0, vlmul,       3'b000,  "T24_vsetvli_e32m1ta")
    `CHECK_VEC(0, vta,         1'b1,    "T24_vsetvli_e32m1ta")
    `CHECK_VEC(0, vma,         1'b1,    "T24_vsetvli_e32m1ta")
    `CHECK_VEC(0, v_op_class,  VCFG,    "T24_vsetvli_e32m1ta")
    `CHECK_VEC(0, vd,          5'd1,    "T24_vsetvli_e32m1ta")
    `CHECK_VEC(0, vs1,         5'd2,    "T24_vsetvli_e32m1ta")
    // scalar packet must not be illegal
    if (decode_bundle[0].is_illegal) begin
        $display("FAIL [T24_vsetvli_e32m1ta] scalar is_illegal=1");
        fail_count++;
    end else
        pass_count++;

    // -----------------------------------------------------------------------
    // T25: vsetvli x3, x4, e16m4
    //   vsew=e16 (3'b001), vlmul=m4 (3'b010), vta=0, vma=0
    // -----------------------------------------------------------------------
    clear_all();
    drive(1, enc_vsetvli(5'd3, 5'd4, 3'b001, 3'b010, 1'b0, 1'b0));
    @(posedge clk);
    `CHECK_VEC(1, is_vsetvl, 1'b1,   "T25_vsetvli_e16m4")
    `CHECK_VEC(1, vsew,      3'b001, "T25_vsetvli_e16m4")
    `CHECK_VEC(1, vlmul,     3'b010, "T25_vsetvli_e16m4")
    `CHECK_VEC(1, vta,       1'b0,   "T25_vsetvli_e16m4")
    `CHECK_VEC(1, vma,       1'b0,   "T25_vsetvli_e16m4")

    // -----------------------------------------------------------------------
    // T26: vsetivli x5, 4, e8m2  (AVL=4 immediate)
    //   vsew=e8 (3'b000), vlmul=m2 (3'b001), vta=0, vma=0, uimm5=4
    // -----------------------------------------------------------------------
    clear_all();
    drive(2, enc_vsetivli(5'd5, 5'd4, 3'b000, 3'b001, 1'b0, 1'b0));
    @(posedge clk);
    `CHECK_VEC(2, is_vector,   1'b1,   "T26_vsetivli_e8m2")
    `CHECK_VEC(2, is_vsetvl,   1'b1,   "T26_vsetivli_e8m2")
    `CHECK_VEC(2, needs_vtype, 1'b0,   "T26_vsetivli_e8m2")
    `CHECK_VEC(2, vsew,        3'b000, "T26_vsetivli_e8m2")
    `CHECK_VEC(2, vlmul,       3'b001, "T26_vsetivli_e8m2")
    `CHECK_VEC(2, vta,         1'b0,   "T26_vsetivli_e8m2")
    `CHECK_VEC(2, vma,         1'b0,   "T26_vsetivli_e8m2")
    `CHECK_VEC(2, v_op_class,  VCFG,   "T26_vsetivli_e8m2")

    // -----------------------------------------------------------------------
    // T27: vsetvl x1, x2, x3  (vtype from register rs2=x3)
    //   vtype fields must be zero (decoded at runtime by vector unit)
    // -----------------------------------------------------------------------
    clear_all();
    drive(3, enc_vsetvl(5'd1, 5'd2, 5'd3));
    @(posedge clk);
    `CHECK_VEC(3, is_vector,   1'b1,   "T27_vsetvl_r")
    `CHECK_VEC(3, is_vsetvl,   1'b1,   "T27_vsetvl_r")
    `CHECK_VEC(3, needs_vtype, 1'b0,   "T27_vsetvl_r")
    `CHECK_VEC(3, vsew,        3'b000, "T27_vsetvl_r") // from rs2 at runtime
    `CHECK_VEC(3, vlmul,       3'b000, "T27_vsetvl_r") // from rs2 at runtime
    `CHECK_VEC(3, v_op_class,  VCFG,   "T27_vsetvl_r")
    `CHECK_VEC(3, vs2,         5'd3,   "T27_vsetvl_r") // rs2 captured in vs2

    // -----------------------------------------------------------------------
    // T28: vadd.vv v4, v2, v3  (unmasked, funct6=0x00, OPIVV)
    //   Expect: is_vector=1, needs_vtype=1, v_op_class=VOP_VADD
    //   (DECODE-005: v_op_class is now per-instruction, not VALU_INT)
    // -----------------------------------------------------------------------
    clear_all();
    drive(4, enc_vadd_vv(5'd4, 5'd2, 5'd3, 1'b1)); // vm=1 unmasked
    @(posedge clk);
    if (!is_vector[4]) begin
        $display("FAIL [T28_vadd_vv] is_vector=0");
        fail_count++;
    end else
        pass_count++;
    `CHECK_VEC(4, is_vector,   1'b1,     "T28_vadd_vv")
    `CHECK_VEC(4, is_vsetvl,   1'b0,     "T28_vadd_vv")
    `CHECK_VEC(4, needs_vtype, 1'b1,     "T28_vadd_vv")
    `CHECK_VEC(4, v_op_class,  VOP_VADD, "T28_vadd_vv")
    `CHECK_VEC(4, vd,          5'd4,     "T28_vadd_vv")
    `CHECK_VEC(4, vs1,         5'd2,     "T28_vadd_vv")
    `CHECK_VEC(4, vs2,         5'd3,     "T28_vadd_vv")
    `CHECK_VEC(4, vm,          1'b1,     "T28_vadd_vv")
    // scalar packet must not be illegal
    if (decode_bundle[4].is_illegal) begin
        $display("FAIL [T28_vadd_vv] scalar is_illegal=1");
        fail_count++;
    end else
        pass_count++;

    // -----------------------------------------------------------------------
    // T29: vle32.v v1, (x2)  - DECODE-008 fix: now correctly identified
    //   opcode=0x07, funct3=3'b110 (EEW32 vector width)
    //   Expected: is_vector=1, v_op_class=VOP_VLE, eew=3'b110, vd=1, vm=1
    // -----------------------------------------------------------------------
    clear_all();
    drive(5, enc_vle32v(5'd1, 5'd2, 1'b1));
    @(posedge clk);
    if (is_vector[5] !== 1'b1) begin
        $display("FAIL [T29_vle32v] is_vector should be 1");
        fail_count++;
    end else begin
        $display("PASS [T29_vle32v] is_vector=1");
        pass_count++;
    end
    `CHECK_VEC(5, is_vector,   1'b1,    "T29_vle32v")
    `CHECK_VEC(5, v_op_class,  VOP_VLE, "T29_vle32v")
    `CHECK_VEC(5, eew,         3'b110,  "T29_vle32v")
    `CHECK_VEC(5, vd,          5'd1,    "T29_vle32v")
    `CHECK_VEC(5, vm,          1'b1,    "T29_vle32v")
    if (decode_bundle[5].is_illegal) begin
        $display("FAIL [T29_vle32v] scalar is_illegal should be 0");
        fail_count++;
    end else
        pass_count++;
    if (decode_bundle[5].is_load !== 1'b1) begin
        $display("FAIL [T29_vle32v] scalar is_load should be 1");
        fail_count++;
    end else
        pass_count++;

    // -----------------------------------------------------------------------
    // T30: 8-slot mix - scalar instructions must be unaffected by OP_VECTOR
    //   Slots 0-5: scalars; slot 6: vadd.vv; slot 7: vsetvli
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_i(12'd1, 5'd0, 3'b000, 5'd1, OPIMM));     // ADDI
    drive(1, enc_r(7'b0,  5'd2, 5'd1,  3'b000, 5'd3, OPREG)); // ADD
    drive(2, enc_i(12'd0, 5'd2, 3'b010, 5'd4, OPLOAD));    // LW
    drive(3, enc_s(12'd4, 5'd2, 5'd1,  3'b010, OPSTORE));  // SW
    drive(4, enc_b(13'd8, 5'd2, 5'd1,  3'b000, OPBRANCH)); // BEQ
    drive(5, enc_j(21'd4, 5'd0, OPJAL));                   // JAL
    drive(6, enc_vadd_vv(5'd1, 5'd2, 5'd3, 1'b1));         // vadd.vv
    drive(7, enc_vsetvli(5'd1, 5'd2, 3'b010, 3'b000, 1'b1, 1'b1)); // vsetvli
    @(posedge clk);

    // Scalar slots must not be tagged as vector
    for (int s = 0; s < 6; s++) begin
        if (is_vector[s]) begin
            $display("FAIL [T30_mix] slot%0d scalar flagged as vector", s);
            fail_count++;
        end else
            pass_count++;
    end
    // Vector slots must be tagged correctly
    if (!is_vector[6]) begin
        $display("FAIL [T30_mix] slot6 vadd.vv not flagged as vector");
        fail_count++;
    end else begin
        $display("PASS [T30_mix] slot6 vadd.vv is_vector=1");
        pass_count++;
    end
    if (!is_vector[7]) begin
        $display("FAIL [T30_mix] slot7 vsetvli not flagged as vector");
        fail_count++;
    end else begin
        $display("PASS [T30_mix] slot7 vsetvli is_vector=1");
        pass_count++;
    end
    // Scalar instructions must still decode correctly
    if (decode_bundle[0].alu_op !== ALU_ADD || decode_bundle[0].is_illegal)
        begin $display("FAIL [T30_mix] slot0 ADDI"); fail_count++; end
    else begin $display("PASS [T30_mix] slot0 ADDI"); pass_count++; end
    if (decode_bundle[1].alu_op !== ALU_ADD || decode_bundle[1].is_illegal)
        begin $display("FAIL [T30_mix] slot1 ADD");  fail_count++; end
    else begin $display("PASS [T30_mix] slot1 ADD");  pass_count++; end

    // -----------------------------------------------------------------------
    // DECODE-005 Tests: funct6 disambiguation for OPIVV/OPIVX/OPIVI
    //
    // Helper: enc_vop(f6, vm, vs2, vs1, f3, vd)
    //   Encodes any OP-V arithmetic instruction (opcode=0x57).
    //
    // Macro shorthand used below:
    //   CV(s,f,e,n) = CHECK_VEC(s, f, e, n)
    // -----------------------------------------------------------------------

    // -----------------------------------------------------------------------
    // T31: OPIVV group - one test per representative funct6
    //   vsub.vv    funct6=0x02
    //   vxor.vv    funct6=0x0b
    //   vrgatherei16.vv funct6=0x0e  (note: OPIVX 0x0e is vslideup)
    //   vmseq.vv   funct6=0x18
    //   vmerge.vvm funct6=0x17 vm=0  -> VOP_VMERGE
    //   vmv.v.v    funct6=0x17 vm=1  -> VOP_VMV
    //   vsaddu.vv  funct6=0x20  (saturating, DECODE-005 req)
    //   vnsrl.wv   funct6=0x2c  (narrowing, DECODE-005 req)
    //   vwredsumu.vs funct6=0x30 (widening reduction, DECODE-005 req)
    // -----------------------------------------------------------------------
    clear_all();
    // slot 0: vsub.vv v1, v2, v3  funct6=0x02 vm=1
    drive(0, {6'h02, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    // slot 1: vxor.vv v4, v5, v6  funct6=0x0b vm=1
    drive(1, {6'h0b, 1'b1, 5'd6, 5'd5, 3'b000, 5'd4, OPVECTOR});
    // slot 2: vrgatherei16.vv v7,v8,v9  funct6=0x0e vm=1
    drive(2, {6'h0e, 1'b1, 5'd9, 5'd8, 3'b000, 5'd7, OPVECTOR});
    // slot 3: vmseq.vv v1,v2,v3  funct6=0x18 vm=1
    drive(3, {6'h18, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    // slot 4: vmerge.vvm v1,v2,v3,v0  funct6=0x17 vm=0 -> VOP_VMERGE
    drive(4, {6'h17, 1'b0, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    // slot 5: vmv.v.v v1,v2  funct6=0x17 vm=1 vs2=0 -> VOP_VMV
    drive(5, {6'h17, 1'b1, 5'd0, 5'd2, 3'b000, 5'd1, OPVECTOR});
    // slot 6: vsaddu.vv  funct6=0x20 vm=1
    drive(6, {6'h20, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    // slot 7: vnsrl.wv   funct6=0x2c vm=1
    drive(7, {6'h2c, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VSUB,        "T31_OPIVV_vsub")
    `CHECK_VEC(0, needs_vtype, 1'b1,            "T31_OPIVV_vsub")
    `CHECK_VEC(1, v_op_class, VOP_VXOR,        "T31_OPIVV_vxor")
    `CHECK_VEC(2, v_op_class, VOP_VRGATHEREI16,"T31_OPIVV_vrgatherei16")
    `CHECK_VEC(3, v_op_class, VOP_VMSEQ,       "T31_OPIVV_vmseq")
    `CHECK_VEC(4, v_op_class, VOP_VMERGE,      "T31_OPIVV_vmerge")
    `CHECK_VEC(5, v_op_class, VOP_VMV,         "T31_OPIVV_vmv")
    `CHECK_VEC(6, v_op_class, VOP_VSADDU,      "T31_OPIVV_vsaddu")
    `CHECK_VEC(7, v_op_class, VOP_VNSRL,       "T31_OPIVV_vnsrl")

    // -----------------------------------------------------------------------
    // T32: OPIVV widening reduction and additional funct6 coverage
    //   vwredsumu.vs funct6=0x30
    //   vwredsum.vs  funct6=0x31
    //   vsll.vv      funct6=0x25
    //   vsmul.vv     funct6=0x27
    //   vnclip.wv    funct6=0x2f
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h30, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    drive(1, {6'h31, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    drive(2, {6'h25, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    drive(3, {6'h27, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    drive(4, {6'h2f, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VWREDSUMU, "T32_OPIVV_vwredsumu")
    `CHECK_VEC(1, v_op_class, VOP_VWREDSUM,  "T32_OPIVV_vwredsum")
    `CHECK_VEC(2, v_op_class, VOP_VSLL,      "T32_OPIVV_vsll")
    `CHECK_VEC(3, v_op_class, VOP_VSMUL,     "T32_OPIVV_vsmul")
    `CHECK_VEC(4, v_op_class, VOP_VNCLIP,    "T32_OPIVV_vnclip")

    // -----------------------------------------------------------------------
    // T33: OPIVX group - funct3=3'b100
    //   vadd.vx    funct6=0x00
    //   vrsub.vx   funct6=0x03  (only in OPIVX/OPIVI, not OPIVV)
    //   vslideup.vx funct6=0x0e (OPIVX 0x0e is vslideup, OPIVV 0x0e is
    //                              vrgatherei16)
    //   vslidedown.vx funct6=0x0f
    //   vmsgtu.vx  funct6=0x1e  (only in OPIVX/OPIVI, not OPIVV)
    //   vmsgt.vx   funct6=0x1f  (only in OPIVX/OPIVI, not OPIVV)
    //   vsmul.vx   funct6=0x27
    //   vnclipu.wx funct6=0x2e  (narrowing)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h00, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(1, {6'h03, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(2, {6'h0e, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(3, {6'h0f, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(4, {6'h1e, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(5, {6'h1f, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(6, {6'h27, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(7, {6'h2e, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VADD,      "T33_OPIVX_vadd")
    `CHECK_VEC(1, v_op_class, VOP_VRSUB,     "T33_OPIVX_vrsub")
    `CHECK_VEC(2, v_op_class, VOP_VSLIDEUP,  "T33_OPIVX_vslideup")
    `CHECK_VEC(3, v_op_class, VOP_VSLIDEDOWN,"T33_OPIVX_vslidedown")
    `CHECK_VEC(4, v_op_class, VOP_VMSGTU,    "T33_OPIVX_vmsgtu")
    `CHECK_VEC(5, v_op_class, VOP_VMSGT,     "T33_OPIVX_vmsgt")
    `CHECK_VEC(6, v_op_class, VOP_VSMUL,     "T33_OPIVX_vsmul")
    `CHECK_VEC(7, v_op_class, VOP_VNCLIPU,   "T33_OPIVX_vnclipu")

    // -----------------------------------------------------------------------
    // T34: OPIVX carry/compare coverage
    //   vadc.vxm   funct6=0x10 vm=0
    //   vmadc.vxm  funct6=0x11 vm=0
    //   vmadc.vx   funct6=0x11 vm=1  (both map to VOP_VMADC)
    //   vsbc.vxm   funct6=0x12 vm=0
    //   vmsbc.vxm  funct6=0x13 vm=0
    //   vmsltu.vx  funct6=0x1a
    //   vmerge.vxm funct6=0x17 vm=0 -> VOP_VMERGE
    //   vmv.v.x    funct6=0x17 vm=1 -> VOP_VMV
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h10, 1'b0, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(1, {6'h11, 1'b0, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(2, {6'h11, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(3, {6'h12, 1'b0, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(4, {6'h13, 1'b0, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(5, {6'h1a, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(6, {6'h17, 1'b0, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR});
    drive(7, {6'h17, 1'b1, 5'd0, 5'd2, 3'b100, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VADC,   "T34_OPIVX_vadc")
    `CHECK_VEC(1, v_op_class, VOP_VMADC,  "T34_OPIVX_vmadc_vm0")
    `CHECK_VEC(2, v_op_class, VOP_VMADC,  "T34_OPIVX_vmadc_vm1")
    `CHECK_VEC(3, v_op_class, VOP_VSBC,   "T34_OPIVX_vsbc")
    `CHECK_VEC(4, v_op_class, VOP_VMSBC,  "T34_OPIVX_vmsbc")
    `CHECK_VEC(5, v_op_class, VOP_VMSLTU, "T34_OPIVX_vmsltu")
    `CHECK_VEC(6, v_op_class, VOP_VMERGE, "T34_OPIVX_vmerge")
    `CHECK_VEC(7, v_op_class, VOP_VMV,    "T34_OPIVX_vmvvx")

    // -----------------------------------------------------------------------
    // T35: OPIVI group - funct3=3'b011
    //   vadd.vi    funct6=0x00
    //   vrsub.vi   funct6=0x03
    //   vslideup.vi funct6=0x0e
    //   vslidedown.vi funct6=0x0f
    //   vadc.vim   funct6=0x10 vm=0
    //   vmseq.vi   funct6=0x18
    //   vsaddu.vi  funct6=0x20  (saturating)
    //   vsll.vi    funct6=0x25
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h00, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    drive(1, {6'h03, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    drive(2, {6'h0e, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    drive(3, {6'h0f, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    drive(4, {6'h10, 1'b0, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    drive(5, {6'h18, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    drive(6, {6'h20, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    drive(7, {6'h25, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VADD,      "T35_OPIVI_vadd")
    `CHECK_VEC(1, v_op_class, VOP_VRSUB,     "T35_OPIVI_vrsub")
    `CHECK_VEC(2, v_op_class, VOP_VSLIDEUP,  "T35_OPIVI_vslideup")
    `CHECK_VEC(3, v_op_class, VOP_VSLIDEDOWN,"T35_OPIVI_vslidedown")
    `CHECK_VEC(4, v_op_class, VOP_VADC,      "T35_OPIVI_vadc")
    `CHECK_VEC(5, v_op_class, VOP_VMSEQ,     "T35_OPIVI_vmseq")
    `CHECK_VEC(6, v_op_class, VOP_VSADDU,    "T35_OPIVI_vsaddu")
    `CHECK_VEC(7, v_op_class, VOP_VSLL,      "T35_OPIVI_vsll")

    // -----------------------------------------------------------------------
    // T36: OPIVI additional funct6 coverage
    //   vmerge.vim  funct6=0x17 vm=0  -> VOP_VMERGE
    //   vmv.v.i     funct6=0x17 vm=1  -> VOP_VMV
    //   vmv1r.v     funct6=0x27 vm=1 vs1=0 -> VOP_VMV  (not vsmul)
    //   vnclip.wi   funct6=0x2f  (narrowing)
    //   vmsgtu.vi   funct6=0x1e
    //   vmsgt.vi    funct6=0x1f
    //   vsadd.vi    funct6=0x21  (saturating)
    //   vnsra.wi    funct6=0x2d  (narrowing)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h17, 1'b0, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    drive(1, {6'h17, 1'b1, 5'd0, 5'd2, 3'b011, 5'd1, OPVECTOR});
    // vmv1r.v: funct6=0x27 vm=1 vs2=v1 vs1=0 (N-1=0 -> vmv1r)
    drive(2, {6'h27, 1'b1, 5'd1, 5'd0, 3'b011, 5'd1, OPVECTOR});
    drive(3, {6'h2f, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    drive(4, {6'h1e, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    drive(5, {6'h1f, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    drive(6, {6'h21, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    drive(7, {6'h2d, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VMERGE, "T36_OPIVI_vmerge")
    `CHECK_VEC(1, v_op_class, VOP_VMV,    "T36_OPIVI_vmv_vi")
    // vmv1r.v returns VOP_VMVNR (distinct from vmv.v.* VOP_VMV)
    `CHECK_VEC(2, v_op_class, VOP_VMVNR,  "T36_OPIVI_vmv1r")
    `CHECK_VEC(3, v_op_class, VOP_VNCLIP, "T36_OPIVI_vnclip")
    `CHECK_VEC(4, v_op_class, VOP_VMSGTU, "T36_OPIVI_vmsgtu")
    `CHECK_VEC(5, v_op_class, VOP_VMSGT,  "T36_OPIVI_vmsgt")
    `CHECK_VEC(6, v_op_class, VOP_VSADD,  "T36_OPIVI_vsadd")
    `CHECK_VEC(7, v_op_class, VOP_VNSRA,  "T36_OPIVI_vnsra")

    // -----------------------------------------------------------------------
    // T37: OPFVV basic funct6 coverage (DECODE-006)
    //   vfadd.vv    funct6=0x00 -> VOP_VFADD
    //   vfsub.vv    funct6=0x02 -> VOP_VFSUB
    //   vfmin.vv    funct6=0x04 -> VOP_VFMIN
    //   vfdiv.vv    funct6=0x20 -> VOP_VFDIV
    //   vfmul.vv    funct6=0x24 -> VOP_VFMUL
    //   vfmacc.vv   funct6=0x2c -> VOP_VFMACC
    //   vfwadd.vv   funct6=0x30 -> VOP_VFWADD  (widening)
    //   vfredusum.vs funct6=0x01 -> VOP_VFREDUSUM (reduction)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h00, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(1, {6'h02, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(2, {6'h04, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(3, {6'h20, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(4, {6'h24, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(5, {6'h2c, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(6, {6'h30, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(7, {6'h01, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VFADD,     "T37_OPFVV_vfadd")
    `CHECK_VEC(1, v_op_class, VOP_VFSUB,     "T37_OPFVV_vfsub")
    `CHECK_VEC(2, v_op_class, VOP_VFMIN,     "T37_OPFVV_vfmin")
    `CHECK_VEC(3, v_op_class, VOP_VFDIV,     "T37_OPFVV_vfdiv")
    `CHECK_VEC(4, v_op_class, VOP_VFMUL,     "T37_OPFVV_vfmul")
    `CHECK_VEC(5, v_op_class, VOP_VFMACC,    "T37_OPFVV_vfmacc")
    `CHECK_VEC(6, v_op_class, VOP_VFWADD,    "T37_OPFVV_vfwadd")
    `CHECK_VEC(7, v_op_class, VOP_VFREDUSUM, "T37_OPFVV_vfredusum")
    // Verify needs_vtype is set for FP ops
    if (!vec_decode_bundle[0].needs_vtype) begin
        $display("FAIL [T37_OPFVV] needs_vtype=0 for vfadd.vv");
        fail_count++;
    end else
        pass_count++;

    // -----------------------------------------------------------------------
    // T38: DECODE-007 OPMVV/OPMVX basic decode check.
    //   vredsum.vs  funct6=0x00 funct3=OPMVV=3'b010 -> VOP_VREDSUM
    //   vmacc.vv    funct6=0x2d funct3=OPMVV=3'b010 -> VOP_VMACC
    //   vmacc.vx    funct6=0x2d funct3=OPMVX=3'b110 -> VOP_VMACC
    //   OPMVX: vs1 must be zero (scalar GPR in scalar pkt.rs1)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h00, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(1, {6'h2d, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    // vmacc.vx: vs2=v3, rs1=x2 (in scalar pkt), vd=v1
    drive(2, {6'h2d, 1'b1, 5'd3, 5'd2, 3'b110, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VREDSUM, "T38_OPMVV_vredsum")
    `CHECK_VEC(1, v_op_class, VOP_VMACC,   "T38_OPMVV_vmacc")
    `CHECK_VEC(2, v_op_class, VOP_VMACC,   "T38_OPMVX_vmacc")
    // OPMVX: vs1 must be zero
    if (vec_decode_bundle[2].vs1 !== 5'b0) begin
        $display("FAIL [T38_OPMVX_vs1_zero] vs1=%0d expected 0",
                 vec_decode_bundle[2].vs1);
        fail_count++;
    end else begin
        $display("PASS [T38_OPMVX_vs1_zero] vs1=0 confirmed");
        pass_count++;
    end

    // -----------------------------------------------------------------------
    // T39: OPIVV unrecognized funct6 -> VOTHER
    //   funct6=0x01 is unused in OPIVV (and OPIVX/OPIVI)
    //   funct6=0x08 is unused in OPIVV
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h01, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    drive(1, {6'h08, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOTHER, "T39_OPIVV_undef_f6_0x01")
    `CHECK_VEC(1, v_op_class, VOTHER, "T39_OPIVV_undef_f6_0x08")

    // -----------------------------------------------------------------------
    // T40: 8-wide DECODE-005 bundle - verify all slots decode independently
    //   Mix of OPIVV/OPIVX/OPIVI in one bundle.
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h00, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR}); // vadd.vv
    drive(1, {6'h02, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR}); // vsub.vv
    drive(2, {6'h20, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR}); // vsaddu.vv
    drive(3, {6'h2c, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR}); // vnsrl.wv
    drive(4, {6'h03, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR}); // vrsub.vx
    drive(5, {6'h0e, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR}); // vslideup.vx
    drive(6, {6'h00, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR}); // vadd.vi
    drive(7, {6'h2f, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR}); // vnclip.wi
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VADD,      "T40_bundle_s0_vadd_vv")
    `CHECK_VEC(1, v_op_class, VOP_VSUB,      "T40_bundle_s1_vsub_vv")
    `CHECK_VEC(2, v_op_class, VOP_VSADDU,    "T40_bundle_s2_vsaddu_vv")
    `CHECK_VEC(3, v_op_class, VOP_VNSRL,     "T40_bundle_s3_vnsrl_wv")
    `CHECK_VEC(4, v_op_class, VOP_VRSUB,     "T40_bundle_s4_vrsub_vx")
    `CHECK_VEC(5, v_op_class, VOP_VSLIDEUP,  "T40_bundle_s5_vslideup_vx")
    `CHECK_VEC(6, v_op_class, VOP_VADD,      "T40_bundle_s6_vadd_vi")
    `CHECK_VEC(7, v_op_class, VOP_VNCLIP,    "T40_bundle_s7_vnclip_wi")
    // Verify funct3 difference: OPIVV 0x0e=vrgatherei16, OPIVX 0x0e=vslideup
    // Use a dedicated check to make this asymmetry explicit
    clear_all();
    drive(0, {6'h0e, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR}); // OPIVV 0x0e
    drive(1, {6'h0e, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR}); // OPIVX 0x0e
    drive(2, {6'h0e, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR}); // OPIVI 0x0e
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VRGATHEREI16,"T40_funct6_0x0e_OPIVV")
    `CHECK_VEC(1, v_op_class, VOP_VSLIDEUP,   "T40_funct6_0x0e_OPIVX")
    `CHECK_VEC(2, v_op_class, VOP_VSLIDEUP,   "T40_funct6_0x0e_OPIVI")

    // -----------------------------------------------------------------------
    // T41: OPFVV cvt group + Zvfhmin closure (DECODE-006)
    //   vfwcvt.f.f.v  funct6=0x12, inst[19:15]=0x0c -> VOP_VFWCVT_FF
    //   vfncvt.f.f.w  funct6=0x12, inst[19:15]=0x14 -> VOP_VFNCVT_FF
    //   vfcvt.xu.f.v  funct6=0x12, inst[19:15]=0x00 -> VOP_VFCVT
    //   vfwcvt.xu.f.v funct6=0x12, inst[19:15]=0x08 -> VOP_VFWCVT
    //   vfncvt.xu.f.w funct6=0x12, inst[19:15]=0x10 -> VOP_VFNCVT
    //   vfsqrt.v      funct6=0x13, inst[19:15]=0x00 -> VOP_VFSQRT
    //   vfclass.v     funct6=0x13, inst[19:15]=0x10 -> VOP_VFCLASS
    //   vmfeq.vv      funct6=0x18  (FP compare)    -> VOP_VMFEQ
    // -----------------------------------------------------------------------
    clear_all();
    // vfwcvt.f.f.v: f6=0x12 vm=1 vs2=v3 vs1=0x0c vd=v1 OPFVV
    drive(0, {6'h12, 1'b1, 5'd3, 5'h0c, 3'b001, 5'd1, OPVECTOR});
    // vfncvt.f.f.w: f6=0x12 vm=1 vs2=v3 vs1=0x14 vd=v1 OPFVV
    drive(1, {6'h12, 1'b1, 5'd3, 5'h14, 3'b001, 5'd1, OPVECTOR});
    // vfcvt.xu.f.v: f6=0x12 vs1=0x00
    drive(2, {6'h12, 1'b1, 5'd3, 5'h00, 3'b001, 5'd1, OPVECTOR});
    // vfwcvt.xu.f.v: f6=0x12 vs1=0x08
    drive(3, {6'h12, 1'b1, 5'd3, 5'h08, 3'b001, 5'd1, OPVECTOR});
    // vfncvt.xu.f.w: f6=0x12 vs1=0x10
    drive(4, {6'h12, 1'b1, 5'd3, 5'h10, 3'b001, 5'd1, OPVECTOR});
    // vfsqrt.v: f6=0x13 vs1=0x00
    drive(5, {6'h13, 1'b1, 5'd3, 5'h00, 3'b001, 5'd1, OPVECTOR});
    // vfclass.v: f6=0x13 vs1=0x10
    drive(6, {6'h13, 1'b1, 5'd3, 5'h10, 3'b001, 5'd1, OPVECTOR});
    // vmfeq.vv: f6=0x18
    drive(7, {6'h18, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VFWCVT_FF, "T41_vfwcvt_ff_v_Zvfhmin")
    `CHECK_VEC(1, v_op_class, VOP_VFNCVT_FF, "T41_vfncvt_ff_w_Zvfhmin")
    `CHECK_VEC(2, v_op_class, VOP_VFCVT,     "T41_vfcvt_xu")
    `CHECK_VEC(3, v_op_class, VOP_VFWCVT,    "T41_vfwcvt_xu")
    `CHECK_VEC(4, v_op_class, VOP_VFNCVT,    "T41_vfncvt_xu")
    `CHECK_VEC(5, v_op_class, VOP_VFSQRT,    "T41_vfsqrt")
    `CHECK_VEC(6, v_op_class, VOP_VFCLASS,   "T41_vfclass")
    `CHECK_VEC(7, v_op_class, VOP_VMFEQ,     "T41_vmfeq_vv")

    // -----------------------------------------------------------------------
    // T42: OPFVV reductions and FMA group
    //   vfredosum.vs  funct6=0x03 -> VOP_VFREDOSUM
    //   vfredmin.vs   funct6=0x05 -> VOP_VFREDMIN
    //   vfredmax.vs   funct6=0x07 -> VOP_VFREDMAX
    //   vfwredusum.vs funct6=0x31 -> VOP_VFWREDUSUM
    //   vfwredosum.vs funct6=0x33 -> VOP_VFWREDOSUM
    //   vfwmul.vv     funct6=0x38 -> VOP_VFWMUL     (FP widening mul)
    //   vmflt.vv      funct6=0x1b -> VOP_VMFLT       (FP compare)
    //   vfmadd.vv     funct6=0x28 -> VOP_VFMADD      (FMA)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h03, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(1, {6'h05, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(2, {6'h07, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(3, {6'h31, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(4, {6'h33, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(5, {6'h38, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(6, {6'h1b, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    drive(7, {6'h28, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VFREDOSUM,  "T42_vfredosum")
    `CHECK_VEC(1, v_op_class, VOP_VFREDMIN,   "T42_vfredmin")
    `CHECK_VEC(2, v_op_class, VOP_VFREDMAX,   "T42_vfredmax")
    `CHECK_VEC(3, v_op_class, VOP_VFWREDUSUM, "T42_vfwredusum")
    `CHECK_VEC(4, v_op_class, VOP_VFWREDOSUM, "T42_vfwredosum")
    `CHECK_VEC(5, v_op_class, VOP_VFWMUL,     "T42_vfwmul")
    `CHECK_VEC(6, v_op_class, VOP_VMFLT,      "T42_vmflt_vv")
    `CHECK_VEC(7, v_op_class, VOP_VFMADD,     "T42_vfmadd")

    // -----------------------------------------------------------------------
    // T43: OPFVF basic and OPFVF-unique instructions
    //   vfadd.vf      funct6=0x00 -> VOP_VFADD
    //   vfslide1up.vf funct6=0x0e -> VOP_VFSLIDE1UP
    //   vfslide1down.vf funct6=0x0f -> VOP_VFSLIDE1DOWN
    //   vfmv.s.f      funct6=0x10 -> VOP_VFMV
    //   vfmerge.vfm   funct6=0x17 vm=0 -> VOP_VFMERGE
    //   vfmv.v.f      funct6=0x17 vm=1 -> VOP_VFMV
    //   vmfgt.vf      funct6=0x1d -> VOP_VMFGT  (OPFVF only)
    //   vmfge.vf      funct6=0x1f -> VOP_VMFGE  (OPFVF only)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h00, 1'b1, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    drive(1, {6'h0e, 1'b1, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    drive(2, {6'h0f, 1'b1, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    // vfmv.s.f: f6=0x10 vm=1 vs2=0 rs1=f2 vd=v1
    drive(3, {6'h10, 1'b1, 5'd0, 5'd2, 3'b101, 5'd1, OPVECTOR});
    // vfmerge.vfm: f6=0x17 vm=0
    drive(4, {6'h17, 1'b0, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    // vfmv.v.f: f6=0x17 vm=1 vs2=0
    drive(5, {6'h17, 1'b1, 5'd0, 5'd2, 3'b101, 5'd1, OPVECTOR});
    drive(6, {6'h1d, 1'b1, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    drive(7, {6'h1f, 1'b1, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VFADD,       "T43_OPFVF_vfadd")
    `CHECK_VEC(1, v_op_class, VOP_VFSLIDE1UP,  "T43_OPFVF_vfslide1up")
    `CHECK_VEC(2, v_op_class, VOP_VFSLIDE1DOWN,"T43_OPFVF_vfslide1down")
    `CHECK_VEC(3, v_op_class, VOP_VFMV,        "T43_OPFVF_vfmv_sf")
    `CHECK_VEC(4, v_op_class, VOP_VFMERGE,     "T43_OPFVF_vfmerge")
    `CHECK_VEC(5, v_op_class, VOP_VFMV,        "T43_OPFVF_vfmv_vf")
    `CHECK_VEC(6, v_op_class, VOP_VMFGT,       "T43_OPFVF_vmfgt")
    `CHECK_VEC(7, v_op_class, VOP_VMFGE,       "T43_OPFVF_vmfge")

    // -----------------------------------------------------------------------
    // T44: OPFVF MAC, widening, and OPFVF-unique div ops
    //   vfmul.vf      funct6=0x24 -> VOP_VFMUL
    //   vfrdiv.vf     funct6=0x21 -> VOP_VFRDIV  (OPFVF only)
    //   vfrsub.vf     funct6=0x27 -> VOP_VFRSUB  (OPFVF only)
    //   vfmacc.vf     funct6=0x2c -> VOP_VFMACC
    //   vfwmacc.vf    funct6=0x3c -> VOP_VFWMACC (FP widening MAC)
    //   vfwadd.vf     funct6=0x30 -> VOP_VFWADD  (FP widening add)
    //   vfwmul.vf     funct6=0x38 -> VOP_VFWMUL  (FP widening mul)
    //   vmfeq.vf      funct6=0x18 -> VOP_VMFEQ
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h24, 1'b1, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    drive(1, {6'h21, 1'b1, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    drive(2, {6'h27, 1'b1, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    drive(3, {6'h2c, 1'b1, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    drive(4, {6'h3c, 1'b1, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    drive(5, {6'h30, 1'b1, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    drive(6, {6'h38, 1'b1, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    drive(7, {6'h18, 1'b1, 5'd3, 5'd2, 3'b101, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VFMUL,   "T44_OPFVF_vfmul")
    `CHECK_VEC(1, v_op_class, VOP_VFRDIV,  "T44_OPFVF_vfrdiv")
    `CHECK_VEC(2, v_op_class, VOP_VFRSUB,  "T44_OPFVF_vfrsub")
    `CHECK_VEC(3, v_op_class, VOP_VFMACC,  "T44_OPFVF_vfmacc")
    `CHECK_VEC(4, v_op_class, VOP_VFWMACC, "T44_OPFVF_vfwmacc")
    `CHECK_VEC(5, v_op_class, VOP_VFWADD,  "T44_OPFVF_vfwadd")
    `CHECK_VEC(6, v_op_class, VOP_VFWMUL,  "T44_OPFVF_vfwmul")
    `CHECK_VEC(7, v_op_class, VOP_VMFEQ,   "T44_OPFVF_vmfeq")

    // -----------------------------------------------------------------------
    // T45: DECODE-007 regression - OPIVV/OPIVX/OPIVI/OPFVV/OPFVF unchanged
    //   Verify that DECODE-007 did not disturb prior group decodes.
    //   vadd.vv  vadd.vx  vadd.vi  vrsub.vx  vrsub.vi
    //   OPMVV funct6=0x00 -> VOP_VREDSUM (vredsum.vs)
    //   OPMVX funct6=0x00 -> VOTHER (no OPMVX instruction at 0x00)
    //   OPFVV unrecognized funct6=0x11 -> VOTHER
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h00, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR}); // vadd.vv
    drive(1, {6'h00, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR}); // vadd.vx
    drive(2, {6'h00, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR}); // vadd.vi
    drive(3, {6'h03, 1'b1, 5'd3, 5'd2, 3'b100, 5'd1, OPVECTOR}); // vrsub.vx
    drive(4, {6'h03, 1'b1, 5'd3, 5'd2, 3'b011, 5'd1, OPVECTOR}); // vrsub.vi
    // OPMVV funct6=0x00 = vredsum.vs
    drive(5, {6'h00, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    // OPMVX funct6=0x00 = no instruction -> VOTHER
    drive(6, {6'h00, 1'b1, 5'd3, 5'd2, 3'b110, 5'd1, OPVECTOR});
    // unrecognized funct6 in OPFVV (0x11 not assigned)
    drive(7, {6'h11, 1'b1, 5'd3, 5'd2, 3'b001, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VADD,    "T45_reg_vadd_vv")
    `CHECK_VEC(1, v_op_class, VOP_VADD,    "T45_reg_vadd_vx")
    `CHECK_VEC(2, v_op_class, VOP_VADD,    "T45_reg_vadd_vi")
    `CHECK_VEC(3, v_op_class, VOP_VRSUB,   "T45_reg_vrsub_vx")
    `CHECK_VEC(4, v_op_class, VOP_VRSUB,   "T45_reg_vrsub_vi")
    `CHECK_VEC(5, v_op_class, VOP_VREDSUM, "T45_reg_OPMVV_vredsum")
    `CHECK_VEC(6, v_op_class, VOTHER,      "T45_reg_OPMVX_undef_f6")
    `CHECK_VEC(7, v_op_class, VOTHER,      "T45_OPFVV_undef_f6_0x11")

    // -----------------------------------------------------------------------
    // T46: VOP_VFMV_FS technical debt regression (DECODE-007)
    //   vfmv.f.s OPFVV funct6=0x10 must return VOP_VFMV_FS (not VOP_VFMV).
    //   vfmv.s.f OPFVF funct6=0x10 must still return VOP_VFMV.
    // -----------------------------------------------------------------------
    clear_all();
    // vfmv.f.s: f6=0x10 vm=1 vs2=v3 vs1=0 funct3=OPFVV vd=v1
    drive(0, {6'h10, 1'b1, 5'd3, 5'h00, 3'b001, 5'd1, OPVECTOR});
    // vfmv.s.f: f6=0x10 vm=1 vs2=0 rs1=f2 funct3=OPFVF vd=v1
    drive(1, {6'h10, 1'b1, 5'd0, 5'd2, 3'b101, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VFMV_FS, "T46_vfmv_f_s_OPFVV")
    `CHECK_VEC(1, v_op_class, VOP_VFMV,    "T46_vfmv_s_f_OPFVF_unchanged")

    // -----------------------------------------------------------------------
    // T47: OPMVV mask logical group
    //   vmand.mm  funct6=0x19 -> VOP_VMAND
    //   vmor.mm   funct6=0x1a -> VOP_VMOR
    //   vmxor.mm  funct6=0x1b -> VOP_VMXOR
    //   vmandn.mm funct6=0x18 -> VOP_VMANDN
    //   vmnand.mm funct6=0x1d -> VOP_VMNAND
    //   vmnor.mm  funct6=0x1e -> VOP_VMNOR
    //   vmorn.mm  funct6=0x1c -> VOP_VMORN
    //   vmxnor.mm funct6=0x1f -> VOP_VMXNOR
    //   All have vm=1 (mask registers, no tail/mask policy).
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h19, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(1, {6'h1a, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(2, {6'h1b, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(3, {6'h18, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(4, {6'h1d, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(5, {6'h1e, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(6, {6'h1c, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(7, {6'h1f, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VMAND,  "T47_OPMVV_vmand")
    `CHECK_VEC(1, v_op_class, VOP_VMOR,   "T47_OPMVV_vmor")
    `CHECK_VEC(2, v_op_class, VOP_VMXOR,  "T47_OPMVV_vmxor")
    `CHECK_VEC(3, v_op_class, VOP_VMANDN, "T47_OPMVV_vmandn")
    `CHECK_VEC(4, v_op_class, VOP_VMNAND, "T47_OPMVV_vmnand")
    `CHECK_VEC(5, v_op_class, VOP_VMNOR,  "T47_OPMVV_vmnor")
    `CHECK_VEC(6, v_op_class, VOP_VMORN,  "T47_OPMVV_vmorn")
    `CHECK_VEC(7, v_op_class, VOP_VMXNOR, "T47_OPMVV_vmxnor")

    // -----------------------------------------------------------------------
    // T48: OPMVV integer reduction group
    //   vredsum.vs funct6=0x00 -> VOP_VREDSUM
    //   vredand.vs funct6=0x01 -> VOP_VREDAND
    //   vredor.vs  funct6=0x02 -> VOP_VREDOR
    //   vredxor.vs funct6=0x03 -> VOP_VREDXOR
    //   vredminu.vs funct6=0x04 -> VOP_VREDMINU
    //   vredmin.vs funct6=0x05 -> VOP_VREDMIN
    //   vredmaxu.vs funct6=0x06 -> VOP_VREDMAXU
    //   vredmax.vs  funct6=0x07 -> VOP_VREDMAX
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h00, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(1, {6'h01, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(2, {6'h02, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(3, {6'h03, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(4, {6'h04, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(5, {6'h05, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(6, {6'h06, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(7, {6'h07, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VREDSUM,  "T48_OPMVV_vredsum")
    `CHECK_VEC(1, v_op_class, VOP_VREDAND,  "T48_OPMVV_vredand")
    `CHECK_VEC(2, v_op_class, VOP_VREDOR,   "T48_OPMVV_vredor")
    `CHECK_VEC(3, v_op_class, VOP_VREDXOR,  "T48_OPMVV_vredxor")
    `CHECK_VEC(4, v_op_class, VOP_VREDMINU, "T48_OPMVV_vredminu")
    `CHECK_VEC(5, v_op_class, VOP_VREDMIN,  "T48_OPMVV_vredmin")
    `CHECK_VEC(6, v_op_class, VOP_VREDMAXU, "T48_OPMVV_vredmaxu")
    `CHECK_VEC(7, v_op_class, VOP_VREDMAX,  "T48_OPMVV_vredmax")

    // -----------------------------------------------------------------------
    // T49: OPMVX vslide1up.vx / vslide1down.vx (permute, GPR src)
    //   vslide1up.vx   funct6=0x0e OPMVX -> VOP_VSLIDE1UP_X
    //   vslide1down.vx funct6=0x0f OPMVX -> VOP_VSLIDE1DOWN_X
    //   vs1 must be 0 (scalar source in scalar pkt.rs1)
    //   Also tests vaaddu.vx funct6=0x08 -> VOP_VAADDU
    // -----------------------------------------------------------------------
    clear_all();
    // vslide1up.vx: f6=0x0e vm=1 vs2=v3 rs1=x2 vd=v1
    drive(0, {6'h0e, 1'b1, 5'd3, 5'd2, 3'b110, 5'd1, OPVECTOR});
    // vslide1down.vx: f6=0x0f vm=1 vs2=v3 rs1=x2 vd=v1
    drive(1, {6'h0f, 1'b1, 5'd3, 5'd2, 3'b110, 5'd1, OPVECTOR});
    // vaaddu.vx: f6=0x08 OPMVX
    drive(2, {6'h08, 1'b1, 5'd3, 5'd2, 3'b110, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VSLIDE1UP_X,   "T49_OPMVX_vslide1up")
    `CHECK_VEC(1, v_op_class, VOP_VSLIDE1DOWN_X, "T49_OPMVX_vslide1down")
    `CHECK_VEC(2, v_op_class, VOP_VAADDU,         "T49_OPMVX_vaaddu")
    // vs1 must be zero for OPMVX (GPR in scalar pkt)
    if (vec_decode_bundle[0].vs1 !== 5'b0) begin
        $display("FAIL [T49_OPMVX_vs1_zero] vslide1up vs1=%0d exp 0",
                 vec_decode_bundle[0].vs1);
        fail_count++;
    end else begin
        $display("PASS [T49_OPMVX_vs1_zero] vslide1up vs1=0");
        pass_count++;
    end
    if (vec_decode_bundle[1].vs1 !== 5'b0) begin
        $display("FAIL [T49_OPMVX_vs1_zero] vslide1down vs1=%0d exp 0",
                 vec_decode_bundle[1].vs1);
        fail_count++;
    end else begin
        $display("PASS [T49_OPMVX_vs1_zero] vslide1down vs1=0");
        pass_count++;
    end
    // Scalar pkt.rs1 must hold the GPR register number (x2=5'd2)
    if (decode_bundle[0].rs1 !== 5'd2) begin
        $display("FAIL [T49_OPMVX_rs1] vslide1up rs1=%0d exp 2",
                 decode_bundle[0].rs1);
        fail_count++;
    end else begin
        $display("PASS [T49_OPMVX_rs1] vslide1up scalar rs1=2");
        pass_count++;
    end

    // -----------------------------------------------------------------------
    // T50: OPMVV widening integer MAC (DECODE-007 widening group wired)
    //   vwmacc.vv  funct6=0x3d OPMVV -> VOP_VWMACC
    //   vwmaccu.vv funct6=0x3c OPMVV -> VOP_VWMACCU
    //   vwmaccsu.vv funct6=0x3f OPMVV -> VOP_VWMACCSU
    //   vwmaccus.vx funct6=0x3e OPMVX -> VOP_VWMACCUS  (OPMVX only)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h3d, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(1, {6'h3c, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(2, {6'h3f, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    // vwmaccus.vx OPMVX only
    drive(3, {6'h3e, 1'b1, 5'd3, 5'd2, 3'b110, 5'd1, OPVECTOR});
    // vwmaccus funct6=0x3e in OPMVV -> VOTHER (not defined)
    drive(4, {6'h3e, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VWMACC,   "T50_OPMVV_vwmacc")
    `CHECK_VEC(1, v_op_class, VOP_VWMACCU,  "T50_OPMVV_vwmaccu")
    `CHECK_VEC(2, v_op_class, VOP_VWMACCSU, "T50_OPMVV_vwmaccsu")
    `CHECK_VEC(3, v_op_class, VOP_VWMACCUS, "T50_OPMVX_vwmaccus")
    `CHECK_VEC(4, v_op_class, VOTHER,        "T50_OPMVV_vwmaccus_undef")

    // -----------------------------------------------------------------------
    // T51: vmv.x.s / vmv.s.x scalar move forms
    //   vmv.x.s  OPMVV funct6=0x10 sub=0x00 -> VOP_VMV_XS (GPR dest)
    //   vmv.s.x  OPMVX funct6=0x10         -> VOP_VMV_SX  (GPR src)
    //   vcpop.m  OPMVV funct6=0x10 sub=0x10 -> VOP_VCPOP   (GPR dest)
    //   vfirst.m OPMVV funct6=0x10 sub=0x11 -> VOP_VFIRST  (GPR dest)
    // -----------------------------------------------------------------------
    clear_all();
    // vmv.x.s: f6=0x10 vm=1 vs2=v3 sub=0x00 OPMVV -> VOP_VMV_XS
    drive(0, {6'h10, 1'b1, 5'd3, 5'h00, 3'b010, 5'd1, OPVECTOR});
    // vmv.s.x: f6=0x10 vm=1 vs2=0 rs1=x2 OPMVX -> VOP_VMV_SX
    drive(1, {6'h10, 1'b1, 5'd0, 5'd2, 3'b110, 5'd1, OPVECTOR});
    // vcpop.m: f6=0x10 sub=0x10 OPMVV -> VOP_VCPOP
    drive(2, {6'h10, 1'b1, 5'd3, 5'h10, 3'b010, 5'd1, OPVECTOR});
    // vfirst.m: f6=0x10 sub=0x11 OPMVV -> VOP_VFIRST
    drive(3, {6'h10, 1'b1, 5'd3, 5'h11, 3'b010, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VMV_XS, "T51_OPMVV_vmv_xs")
    `CHECK_VEC(1, v_op_class, VOP_VMV_SX, "T51_OPMVX_vmv_sx")
    `CHECK_VEC(2, v_op_class, VOP_VCPOP,  "T51_OPMVV_vcpop")
    `CHECK_VEC(3, v_op_class, VOP_VFIRST, "T51_OPMVV_vfirst")
    // vmv.s.x OPMVX: vs1 must be 0
    if (vec_decode_bundle[1].vs1 !== 5'b0) begin
        $display("FAIL [T51_vmv_sx_vs1] vs1=%0d exp 0",
                 vec_decode_bundle[1].vs1);
        fail_count++;
    end else begin
        $display("PASS [T51_vmv_sx_vs1] vs1=0 for vmv.s.x");
        pass_count++;
    end

    // -----------------------------------------------------------------------
    // T52: OPMVV viota.m / vid.v (no vs2 for vid.v)
    //   viota.m funct6=0x14 sub=0x10 -> VOP_VIOTA
    //   vid.v   funct6=0x14 sub=0x11 -> VOP_VID
    //   Also vmsbf/vmsof/vmsif coverage
    // -----------------------------------------------------------------------
    clear_all();
    // viota.m: f6=0x14 vm=1 vs2=v3 sub=0x10 OPMVV
    drive(0, {6'h14, 1'b1, 5'd3, 5'h10, 3'b010, 5'd1, OPVECTOR});
    // vid.v:   f6=0x14 vm=1 vs2=0 sub=0x11 OPMVV
    drive(1, {6'h14, 1'b1, 5'd0, 5'h11, 3'b010, 5'd1, OPVECTOR});
    // vmsbf.m: f6=0x14 sub=0x01 OPMVV
    drive(2, {6'h14, 1'b1, 5'd3, 5'h01, 3'b010, 5'd1, OPVECTOR});
    // vmsof.m: f6=0x14 sub=0x02 OPMVV
    drive(3, {6'h14, 1'b1, 5'd3, 5'h02, 3'b010, 5'd1, OPVECTOR});
    // vmsif.m: f6=0x14 sub=0x03 OPMVV
    drive(4, {6'h14, 1'b1, 5'd3, 5'h03, 3'b010, 5'd1, OPVECTOR});
    // unknown sub -> VOTHER
    drive(5, {6'h14, 1'b1, 5'd3, 5'h00, 3'b010, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VIOTA, "T52_OPMVV_viota")
    `CHECK_VEC(1, v_op_class, VOP_VID,   "T52_OPMVV_vid")
    `CHECK_VEC(2, v_op_class, VOP_VMSBF, "T52_OPMVV_vmsbf")
    `CHECK_VEC(3, v_op_class, VOP_VMSOF, "T52_OPMVV_vmsof")
    `CHECK_VEC(4, v_op_class, VOP_VMSIF, "T52_OPMVV_vmsif")
    `CHECK_VEC(5, v_op_class, VOTHER,    "T52_OPMVV_0x14_sub0_undef")
    if (!vec_decode_bundle[0].needs_vtype) begin
        $display("FAIL [T52_viota_needs_vtype] needs_vtype=0");
        fail_count++;
    end else begin
        $display("PASS [T52_viota_needs_vtype] needs_vtype=1");
        pass_count++;
    end

    // -----------------------------------------------------------------------
    // T53: 8-wide DECODE-007 bundle - all 8 slots decode in parallel
    //   Mix of OPMVV and OPMVX; verify no cross-slot interference.
    // -----------------------------------------------------------------------
    clear_all();
    // s0: vredsum.vs OPMVV f6=0x00
    drive(0, {6'h00, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    // s1: vmand.mm OPMVV f6=0x19
    drive(1, {6'h19, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    // s2: vmacc.vv OPMVV f6=0x2d
    drive(2, {6'h2d, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    // s3: vwaddu.vv OPMVV f6=0x30
    drive(3, {6'h30, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    // s4: vaaddu.vx OPMVX f6=0x08 (GPR rs1=x5)
    drive(4, {6'h08, 1'b1, 5'd3, 5'd5, 3'b110, 5'd1, OPVECTOR});
    // s5: vslide1up.vx OPMVX f6=0x0e (GPR rs1=x5)
    drive(5, {6'h0e, 1'b1, 5'd3, 5'd5, 3'b110, 5'd1, OPVECTOR});
    // s6: vwmacc.vx OPMVX f6=0x3d (GPR rs1=x5)
    drive(6, {6'h3d, 1'b1, 5'd3, 5'd5, 3'b110, 5'd1, OPVECTOR});
    // s7: OPMVV f6=0x3e -> VOTHER (not defined in OPMVV)
    drive(7, {6'h3e, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VREDSUM,      "T53_s0_vredsum")
    `CHECK_VEC(1, v_op_class, VOP_VMAND,         "T53_s1_vmand")
    `CHECK_VEC(2, v_op_class, VOP_VMACC,         "T53_s2_vmacc_vv")
    `CHECK_VEC(3, v_op_class, VOP_VWADDU,        "T53_s3_vwaddu")
    `CHECK_VEC(4, v_op_class, VOP_VAADDU,        "T53_s4_vaaddu_vx")
    `CHECK_VEC(5, v_op_class, VOP_VSLIDE1UP_X,  "T53_s5_vslide1up_vx")
    `CHECK_VEC(6, v_op_class, VOP_VWMACC,        "T53_s6_vwmacc_vx")
    `CHECK_VEC(7, v_op_class, VOTHER,             "T53_s7_OPMVV_undef_3e")
    // OPMVX slots (4-6): vs1 must be zero
    for (int s = 4; s <= 6; s++) begin
        if (vec_decode_bundle[s].vs1 !== 5'b0) begin
            $display("FAIL [T53_OPMVX_vs1] slot%0d vs1=%0d exp 0",
                     s, vec_decode_bundle[s].vs1);
            fail_count++;
        end else begin
            $display("PASS [T53_OPMVX_vs1] slot%0d vs1=0", s);
            pass_count++;
        end
    end
    // OPMVV slots (0-3): vs1 must reflect instruction field
    if (vec_decode_bundle[0].vs1 !== 5'd2) begin
        $display("FAIL [T53_OPMVV_vs1] slot0 vs1=%0d exp 2",
                 vec_decode_bundle[0].vs1);
        fail_count++;
    end else begin
        $display("PASS [T53_OPMVV_vs1] slot0 vs1=2");
        pass_count++;
    end

    // -----------------------------------------------------------------------
    // T54: DECODE-007 OPMVV/OPMVX unrecognized funct6 -> VOTHER
    //   OPMVV funct6=0x3e (vwmaccus only in OPMVX) -> VOTHER in OPMVV
    //   OPMVV funct6=0x28 (no OPMVV instruction)    -> VOTHER
    //   OPMVX funct6=0x00 (no OPMVX instruction)    -> VOTHER
    //   OPMVX funct6=0x15 (unused)                  -> VOTHER
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h3e, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(1, {6'h28, 1'b1, 5'd3, 5'd2, 3'b010, 5'd1, OPVECTOR});
    drive(2, {6'h00, 1'b1, 5'd3, 5'd2, 3'b110, 5'd1, OPVECTOR});
    drive(3, {6'h15, 1'b1, 5'd3, 5'd2, 3'b110, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOTHER, "T54_OPMVV_f6_3e_undef")
    `CHECK_VEC(1, v_op_class, VOTHER, "T54_OPMVV_f6_28_undef")
    `CHECK_VEC(2, v_op_class, VOTHER, "T54_OPMVX_f6_00_undef")
    `CHECK_VEC(3, v_op_class, VOTHER, "T54_OPMVX_f6_15_undef")

    // -----------------------------------------------------------------------
    // T55: DECODE-008 vector unit-stride loads all EEW widths
    //   vle8.v  v2,(x3)  slot0  eew=000
    //   vle16.v v4,(x5)  slot1  eew=101
    //   vle32.v v6,(x7)  slot2  eew=110
    //   vle64.v v8,(x9)  slot3  eew=111
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_vlev(5'd2,  5'd3,  3'b000, 1'b1));
    drive(1, enc_vlev(5'd4,  5'd5,  3'b101, 1'b1));
    drive(2, enc_vlev(5'd6,  5'd7,  3'b110, 1'b1));
    drive(3, enc_vlev(5'd8,  5'd9,  3'b111, 1'b1));
    @(posedge clk);
    `CHECK_VEC(0, is_vector,  1'b1,    "T55_vle8v")
    `CHECK_VEC(0, v_op_class, VOP_VLE, "T55_vle8v")
    `CHECK_VEC(0, eew,        3'b000,  "T55_vle8v")
    `CHECK_VEC(0, vd,         5'd2,    "T55_vle8v")
    `CHECK_VEC(1, is_vector,  1'b1,    "T55_vle16v")
    `CHECK_VEC(1, v_op_class, VOP_VLE, "T55_vle16v")
    `CHECK_VEC(1, eew,        3'b101,  "T55_vle16v")
    `CHECK_VEC(1, vd,         5'd4,    "T55_vle16v")
    `CHECK_VEC(2, is_vector,  1'b1,    "T55_vle32v")
    `CHECK_VEC(2, v_op_class, VOP_VLE, "T55_vle32v")
    `CHECK_VEC(2, eew,        3'b110,  "T55_vle32v")
    `CHECK_VEC(2, vd,         5'd6,    "T55_vle32v")
    `CHECK_VEC(3, is_vector,  1'b1,    "T55_vle64v")
    `CHECK_VEC(3, v_op_class, VOP_VLE, "T55_vle64v")
    `CHECK_VEC(3, eew,        3'b111,  "T55_vle64v")
    `CHECK_VEC(3, vd,         5'd8,    "T55_vle64v")

    // -----------------------------------------------------------------------
    // T56: DECODE-008 vector memory addressing modes
    //   vse32.v  v2,(x3)       slot0  unit-stride store
    //   vlse32.v v4,(x5),x6   slot1  strided load (rs2=stride)
    //   vluxe32.v v8,(x1),v2  slot2  unord-indexed load (vs2=index)
    //   vlm.v v1,(x2)          slot3  mask load
    //   vl1re8.v v3,(x4)       slot4  whole-register load
    //   vle32ff.v v5,(x6)      slot5  fault-only-first load
    //   scalar FLD x1,0(x2)   slot6  FP scalar regression
    //   scalar FSD x2,0(x1)   slot7  FP scalar regression
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_vsev(5'd2, 5'd3, 3'b110, 1'b1));
    drive(1, enc_vlsev(5'd4, 5'd5, 5'd6, 3'b110, 1'b1));
    drive(2, enc_vluxev(5'd8, 5'd1, 5'd2, 3'b110, 1'b1));
    drive(3, enc_vlmv(5'd1, 5'd2));
    drive(4, enc_vl1rev(5'd3, 5'd4));
    drive(5, enc_vleffv(5'd5, 5'd6, 3'b110, 1'b1));
    drive(6, enc_fld(12'd0, 5'd2, 5'd1));
    drive(7, enc_fsd(12'd0, 5'd1, 5'd2));
    @(posedge clk);
    // slot0: vse32.v
    `CHECK_VEC(0, is_vector,  1'b1,    "T56_vse32v")
    `CHECK_VEC(0, v_op_class, VOP_VSE, "T56_vse32v")
    `CHECK_VEC(0, eew,        3'b110,  "T56_vse32v")
    `CHECK_VEC(0, vs3,        5'd2,    "T56_vse32v")
    // slot1: vlse32.v - verify uses_rs2 for stride GPR
    `CHECK_VEC(1, is_vector,  1'b1,     "T56_vlse32v")
    `CHECK_VEC(1, v_op_class, VOP_VLSE, "T56_vlse32v")
    `CHECK_VEC(1, eew,        3'b110,   "T56_vlse32v")
    `CHECK_VEC(1, vd,         5'd4,     "T56_vlse32v")
    if (decode_bundle[1].uses_rs2 !== 1'b1) begin
        $display("FAIL [T56_vlse32v] uses_rs2 should be 1 (stride GPR)");
        fail_count++;
    end else begin
        $display("PASS [T56_vlse32v] uses_rs2=1 stride GPR confirmed");
        pass_count++;
    end
    // slot2: vluxe32.v - vs2 = index vector register
    `CHECK_VEC(2, is_vector,   1'b1,     "T56_vluxe32v")
    `CHECK_VEC(2, v_op_class,  VOP_VLUXE,"T56_vluxe32v")
    `CHECK_VEC(2, eew,         3'b110,   "T56_vluxe32v")
    `CHECK_VEC(2, vd,          5'd8,     "T56_vluxe32v")
    `CHECK_VEC(2, vs2,         5'd2,     "T56_vluxe32v")
    // slot3: vlm.v
    `CHECK_VEC(3, is_vector,  1'b1,    "T56_vlmv")
    `CHECK_VEC(3, v_op_class, VOP_VLM, "T56_vlmv")
    `CHECK_VEC(3, eew,        3'b000,  "T56_vlmv")
    `CHECK_VEC(3, vd,         5'd1,    "T56_vlmv")
    // slot4: vl1re8.v
    `CHECK_VEC(4, is_vector,  1'b1,       "T56_vl1re8v")
    `CHECK_VEC(4, v_op_class, VOP_VLWHOLE,"T56_vl1re8v")
    `CHECK_VEC(4, vd,         5'd3,       "T56_vl1re8v")
    // slot5: vle32ff.v
    `CHECK_VEC(5, is_vector,  1'b1,    "T56_vle32ffv")
    `CHECK_VEC(5, v_op_class, VOP_VLFF,"T56_vle32ffv")
    `CHECK_VEC(5, eew,        3'b110,  "T56_vle32ffv")
    `CHECK_VEC(5, vd,         5'd5,    "T56_vle32ffv")
    // slot6: fld - scalar FP regression (must NOT be vector)
    if (is_vector[6] !== 1'b0) begin
        $display("FAIL [T56_fld_reg] is_vector should be 0 for FLD");
        fail_count++;
    end else begin
        $display("PASS [T56_fld_reg] is_vector=0 FLD scalar path intact");
        pass_count++;
    end
    if (decode_bundle[6].is_fp !== 1'b1) begin
        $display("FAIL [T56_fld_reg] is_fp should be 1 for FLD");
        fail_count++;
    end else
        pass_count++;
    if (decode_bundle[6].is_illegal) begin
        $display("FAIL [T56_fld_reg] FLD should not be illegal");
        fail_count++;
    end else
        pass_count++;
    // slot7: fsd - scalar FP regression (must NOT be vector)
    if (is_vector[7] !== 1'b0) begin
        $display("FAIL [T56_fsd_reg] is_vector should be 0 for FSD");
        fail_count++;
    end else begin
        $display("PASS [T56_fsd_reg] is_vector=0 FSD scalar path intact");
        pass_count++;
    end
    if (decode_bundle[7].is_fp !== 1'b1) begin
        $display("FAIL [T56_fsd_reg] is_fp should be 1 for FSD");
        fail_count++;
    end else
        pass_count++;
    if (decode_bundle[7].is_illegal) begin
        $display("FAIL [T56_fsd_reg] FSD should not be illegal");
        fail_count++;
    end else
        pass_count++;

    // -----------------------------------------------------------------------
    // T57: 8-slot mix of vector loads and scalar FP loads
    //   slots 0-3: vle8/16/32/64.v (vector)
    //   slots 4-7: fld 0(x1..x4)   (scalar FP)
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, enc_vlev(5'd1, 5'd2, 3'b000, 1'b1)); // vle8.v
    drive(1, enc_vlev(5'd3, 5'd4, 3'b101, 1'b1)); // vle16.v
    drive(2, enc_vlev(5'd5, 5'd6, 3'b110, 1'b1)); // vle32.v
    drive(3, enc_vlev(5'd7, 5'd8, 3'b111, 1'b1)); // vle64.v
    drive(4, enc_fld(12'd0, 5'd1, 5'd1));
    drive(5, enc_fld(12'd0, 5'd2, 5'd2));
    drive(6, enc_fld(12'd0, 5'd3, 5'd3));
    drive(7, enc_fld(12'd0, 5'd4, 5'd4));
    @(posedge clk);
    // Vector slots: is_vector=1
    for (int s = 0; s < 4; s++) begin
        if (!is_vector[s]) begin
            $display("FAIL [T57_mix] slot%0d: expected is_vector=1", s);
            fail_count++;
        end else
            pass_count++;
    end
    // Scalar FP slots: is_vector=0, is_fp=1, not illegal
    for (int s = 4; s < 8; s++) begin
        if (is_vector[s]) begin
            $display("FAIL [T57_mix] slot%0d: expected is_vector=0", s);
            fail_count++;
        end else
            pass_count++;
        if (!decode_bundle[s].is_fp) begin
            $display("FAIL [T57_mix] slot%0d: expected is_fp=1", s);
            fail_count++;
        end else
            pass_count++;
        if (decode_bundle[s].is_illegal) begin
            $display("FAIL [T57_mix] slot%0d: FLD should not be illegal",s);
            fail_count++;
        end else
            pass_count++;
    end
    // Verify v_op_class for each vector slot
    `CHECK_VEC(0, v_op_class, VOP_VLE, "T57_mix_vle8v")
    `CHECK_VEC(1, v_op_class, VOP_VLE, "T57_mix_vle16v")
    `CHECK_VEC(2, v_op_class, VOP_VLE, "T57_mix_vle32v")
    `CHECK_VEC(3, v_op_class, VOP_VLE, "T57_mix_vle64v")

    // -----------------------------------------------------------------------
    // T58: Whole-register move vmv1r/2r/4r/8r (DECODE-009 verification)
    //   vmvNr.v: funct6=0x27, vm=1, vs2=src, imm5=N-1, funct3=011
    //   vmv1r.v -> imm5=0, vmv2r.v -> imm5=1
    //   vmv4r.v -> imm5=3, vmv8r.v -> imm5=7
    //   All must return VOP_VMVNR (not VOP_VMV)
    // -----------------------------------------------------------------------
    clear_all();
    // vmv1r.v  vs2=v2 vd=v1  N-1=0
    drive(0, {6'h27, 1'b1, 5'd2, 5'd0, 3'b011, 5'd1, OPVECTOR});
    // vmv2r.v  vs2=v4 vd=v3  N-1=1
    drive(1, {6'h27, 1'b1, 5'd4, 5'd1, 3'b011, 5'd3, OPVECTOR});
    // vmv4r.v  vs2=v8 vd=v4  N-1=3
    drive(2, {6'h27, 1'b1, 5'd8, 5'd3, 3'b011, 5'd4, OPVECTOR});
    // vmv8r.v  vs2=v16 vd=v8  N-1=7
    drive(3, {6'h27, 1'b1, 5'd16, 5'd7, 3'b011, 5'd8, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VMVNR, "T58_vmv1r")
    `CHECK_VEC(1, v_op_class, VOP_VMVNR, "T58_vmv2r")
    `CHECK_VEC(2, v_op_class, VOP_VMVNR, "T58_vmv4r")
    `CHECK_VEC(3, v_op_class, VOP_VMVNR, "T58_vmv8r")

    // -----------------------------------------------------------------------
    // T59: Segment load/stores + nf field + needs_vtype checks
    //   vlseg2e32.v  nf=001 -> VOP_VLSEG  pkt.nf=3'b001
    //   vlseg8e8.v   nf=111 -> VOP_VLSEG  pkt.nf=3'b111
    //   vsseg2e32.v  nf=001 -> VOP_VSSEG
    //   vlsseg2e32.v nf=001 -> VOP_VLSSEG
    //   vluxseg2e32.v nf=001 -> VOP_VLUXSEG
    //   vloxseg2e32.v nf=001 -> VOP_VLOXSEG
    // -----------------------------------------------------------------------
    clear_all();
    // vlseg2e32.v v2,(x4)   nf=001 mop=00 vm=1 eew=110
    drive(0, enc_vlsegv(5'd2, 5'd4, 3'b001, 3'b110, 1'b1));
    // vlseg8e8.v v2,(x4)    nf=111 mop=00 vm=1 eew=000
    drive(1, enc_vlsegv(5'd2, 5'd4, 3'b111, 3'b000, 1'b1));
    // vsseg2e32.v v3,(x4)   nf=001 mop=00 vm=1 eew=110
    drive(2, enc_vssegv(5'd3, 5'd4, 3'b001, 3'b110, 1'b1));
    // vlsseg2e32.v v2,(x4),x5  nf=001 mop=10 vm=1 eew=110
    drive(3, enc_vlssegv(5'd2, 5'd4, 5'd5, 3'b001, 3'b110, 1'b1));
    // vluxseg2e32.v v2,(x4),v5 nf=001 mop=01 vm=1 eew=110
    drive(4, enc_vluxsegv(5'd2, 5'd4, 5'd5, 3'b001, 3'b110, 1'b1));
    // vloxseg2e32.v v2,(x4),v5 nf=001 mop=11 vm=1 eew=110
    drive(5, enc_vloxsegv(5'd2, 5'd4, 5'd5, 3'b001, 3'b110, 1'b1));
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VLSEG,   "T59_vlseg2e32")
    `CHECK_VEC(1, v_op_class, VOP_VLSEG,   "T59_vlseg8e8")
    `CHECK_VEC(2, v_op_class, VOP_VSSEG,   "T59_vsseg2e32")
    `CHECK_VEC(3, v_op_class, VOP_VLSSEG,  "T59_vlsseg2e32")
    `CHECK_VEC(4, v_op_class, VOP_VLUXSEG, "T59_vluxseg2e32")
    `CHECK_VEC(5, v_op_class, VOP_VLOXSEG, "T59_vloxseg2e32")
    // nf field preserved for vlseg2e32 (nf=001) and vlseg8e8 (nf=111)
    if (vec_decode_bundle[0].nf !== 3'b001) begin
        $display("FAIL [T59_nf_vlseg2] nf=%0b expected 001",
                 vec_decode_bundle[0].nf);
        fail_count++;
    end else
        pass_count++;
    if (vec_decode_bundle[1].nf !== 3'b111) begin
        $display("FAIL [T59_nf_vlseg8] nf=%0b expected 111",
                 vec_decode_bundle[1].nf);
        fail_count++;
    end else
        pass_count++;

    // -----------------------------------------------------------------------
    // T60: needs_vtype=0 for whole-register load/store (DECODE-009 debt fix)
    //   vl1re8.v -> VOP_VLWHOLE -> needs_vtype must be 0
    //   vs1re8.v -> VOP_VSWHOLE -> needs_vtype must be 0
    // Also regression: vle32.v nf=0 must still return VOP_VLE (not VOP_VLSEG)
    // -----------------------------------------------------------------------
    clear_all();
    // vl1re8.v v3,(x4)  nf=0 mop=00 vm=1 [24:20]=01000 width=000
    drive(0, enc_vl1rev(5'd3, 5'd4));
    // vs1re8.v v5,(x4)  nf=0 mop=00 vm=1 [24:20]=01000 width=000
    drive(1, enc_vs1rev(5'd5, 5'd4));
    // vle32.v v1,(x2) nf=0  -- regression: nf=0 must route to VOP_VLE
    drive(2, enc_vle32v(5'd1, 5'd2, 1'b1));
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VLWHOLE, "T60_vl1re8_class")
    `CHECK_VEC(1, v_op_class, VOP_VSWHOLE, "T60_vs1re8_class")
    `CHECK_VEC(2, v_op_class, VOP_VLE,     "T60_vle32_regression")
    if (vec_decode_bundle[0].needs_vtype !== 1'b0) begin
        $display("FAIL [T60_vl1re8_needs_vtype] expected 0 got %0b",
                 vec_decode_bundle[0].needs_vtype);
        fail_count++;
    end else
        pass_count++;
    if (vec_decode_bundle[1].needs_vtype !== 1'b0) begin
        $display("FAIL [T60_vs1re8_needs_vtype] expected 0 got %0b",
                 vec_decode_bundle[1].needs_vtype);
        fail_count++;
    end else
        pass_count++;
    if (vec_decode_bundle[2].needs_vtype !== 1'b1) begin
        $display("FAIL [T60_vle32_needs_vtype] expected 1 got %0b",
                 vec_decode_bundle[2].needs_vtype);
        fail_count++;
    end else
        pass_count++;

    // =======================================================================
    // DECODE-011 extension enable/disable tests
    // All tests with RVA23_ENABLE verify no regression.
    // =======================================================================

    // -----------------------------------------------------------------------
    // T61: en_m=0 -- MULW x1,x2,x3 (OP-32, f7=0000001) -> ILLEGAL
    // -----------------------------------------------------------------------
    ext_enable       = RVA23_ENABLE;
    ext_enable.en_m  = 1'b0;
    clear_all();
    drive(0, enc_r(7'b0000001, 5'd3, 5'd2, 3'b000, 5'd1, OPREG32));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T61_mulw_en_m0")
    // regression: en_m=1, MULW must not be ILLEGAL
    ext_enable = RVA23_ENABLE;
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T61_mulw_reg")

    // -----------------------------------------------------------------------
    // T62: en_a=0 -- LR.W (OP-AMO, f7=0001000) -> ILLEGAL
    // -----------------------------------------------------------------------
    ext_enable       = RVA23_ENABLE;
    ext_enable.en_a  = 1'b0;
    clear_all();
    // LR.W: f7=0001000, rs2=0, rs1=x2, f3=010, rd=x1, op=AMO
    drive(0, enc_r(7'b0001000, 5'd0, 5'd2, 3'b010, 5'd1,
                   7'b0101111));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T62_lrw_en_a0")
    ext_enable = RVA23_ENABLE;
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T62_lrw_reg")

    // -----------------------------------------------------------------------
    // T63: en_f=0 -- FLW x1,4(x2) (OP_LOAD_FP, f3=010) -> ILLEGAL
    // -----------------------------------------------------------------------
    ext_enable       = RVA23_ENABLE;
    ext_enable.en_f  = 1'b0;
    clear_all();
    drive(0, enc_i(12'd4, 5'd2, 3'b010, 5'd1, OPLOADFP));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T63_flw_en_f0")
    ext_enable = RVA23_ENABLE;
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T63_flw_reg")

    // -----------------------------------------------------------------------
    // T64: en_d=0, en_f=1 -- FLD x1,8(x2) (OP_LOAD_FP, f3=011) -> ILLEGAL
    // -----------------------------------------------------------------------
    ext_enable       = RVA23_ENABLE;
    ext_enable.en_d  = 1'b0;
    clear_all();
    drive(0, enc_i(12'd8, 5'd2, 3'b011, 5'd1, OPLOADFP));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T64_fld_en_d0")
    ext_enable = RVA23_ENABLE;
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T64_fld_reg")

    // -----------------------------------------------------------------------
    // T65: en_c=0 -- raw 16-bit instruction -> ILLEGAL
    //   c.addi x1, 1: Q1 funct3=000, rd=1, nzimm=1
    //   packed into 32-bit word {16'h0000, 16'h0085} where
    //   inst[1:0]=01 (Q1) and inst[15:13]=000 (not Zcb)
    // -----------------------------------------------------------------------
    ext_enable       = RVA23_ENABLE;
    ext_enable.en_c  = 1'b0;
    clear_all();
    // c.addi x1, 1: bits[15:13]=000, bit[12]=0, bits[11:7]=00001,
    //   bits[6:2]=00001, bits[1:0]=01 -> 0x0085
    drive(0, {16'h0000, 16'h0085});
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T65_c_en_c0")
    // regression: en_c=1, expanded 32-bit ADDI (not ILLEGAL)
    ext_enable = RVA23_ENABLE;
    clear_all();
    // ADDI x1, x1, 1 (expanded c.addi x1, 1)
    drive(0, enc_i(12'd1, 5'd1, 3'b000, 5'd1, OPIMM));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T65_c_reg")

    // -----------------------------------------------------------------------
    // T66: en_zcb=0, en_c=1 -- Zcb Q0 instruction -> ILLEGAL
    //   c.lbu: Q0 (inst[1:0]=00), inst[15:13]=100
    //   packed into {16'h0000, 16'h8000}
    // Regression: base C expansion (ADDI) with en_zcb=0 -> not ILLEGAL
    // -----------------------------------------------------------------------
    ext_enable          = RVA23_ENABLE;
    ext_enable.en_zcb   = 1'b0;
    clear_all();
    // c.lbu pattern: inst[15:13]=100, inst[1:0]=00 -> 0x8000 area
    // bits: 1000_0000_0000_0000 = 0x8000
    drive(0, {16'h0000, 16'h8000});
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T66_zcb_en_zcb0")
    // regression: expanded ADDI (not Zcb pattern) -> not ILLEGAL
    clear_all();
    drive(0, enc_i(12'd2, 5'd1, 3'b000, 5'd1, OPIMM));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T66_zcb_base_reg")

    // -----------------------------------------------------------------------
    // T67: en_v=0 -- vadd.vv (OP_VECTOR) -> ILLEGAL
    // -----------------------------------------------------------------------
    ext_enable       = RVA23_ENABLE;
    ext_enable.en_v  = 1'b0;
    clear_all();
    drive(0, enc_vadd_vv(5'd1, 5'd2, 5'd3, 1'b1));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T67_vadd_en_v0")
    ext_enable = RVA23_ENABLE;
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T67_vadd_reg")

    // -----------------------------------------------------------------------
    // T68: en_v=0 -- vle32.v (OP_LOAD_FP vector) -> ILLEGAL
    // -----------------------------------------------------------------------
    ext_enable       = RVA23_ENABLE;
    ext_enable.en_v  = 1'b0;
    clear_all();
    drive(0, enc_vle32v(5'd1, 5'd2, 1'b1));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T68_vle32_en_v0")
    ext_enable = RVA23_ENABLE;
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T68_vle32_reg")

    // -----------------------------------------------------------------------
    // T69: en_zicsr=0 -- CSRRW x1, mstatus, x2 -> ILLEGAL
    //   OP_SYSTEM, f3=001, csr=0x300 (mstatus)
    // -----------------------------------------------------------------------
    ext_enable           = RVA23_ENABLE;
    ext_enable.en_zicsr  = 1'b0;
    clear_all();
    drive(0, enc_i(12'h300, 5'd2, 3'b001, 5'd1, OPSYSTEM));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T69_csr_en_zicsr0")
    ext_enable = RVA23_ENABLE;
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T69_csr_reg")

    // -----------------------------------------------------------------------
    // T70: en_zicbom=0 -- cbo.clean (OP_MISC_MEM, f3=010, rs2=1) -> ILLEGAL
    //   inst = {7'b0, 5'b00001, rs1, 3'b010, 5'b0, 7'b0001111}
    // -----------------------------------------------------------------------
    ext_enable            = RVA23_ENABLE;
    ext_enable.en_zicbom  = 1'b0;
    clear_all();
    // cbo.clean: imm12={7'b0, 5'b00001}=12'h001, rs1=x2, f3=010, rd=0
    drive(0, enc_i(12'h001, 5'd2, 3'b010, 5'd0,
                   7'b0001111));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T70_cbo_clean_en_zicbom0")
    ext_enable = RVA23_ENABLE;
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T70_cbo_clean_reg")

    // -----------------------------------------------------------------------
    // T71: en_zba=0 -- sh1add x1,x2,x3 (f7=0010000, f3=010) -> ILLEGAL
    // -----------------------------------------------------------------------
    ext_enable           = RVA23_ENABLE;
    ext_enable.en_zba    = 1'b0;
    clear_all();
    drive(0, enc_r(7'b0010000, 5'd3, 5'd2, 3'b010, 5'd1, OPREG));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T71_sh1add_en_zba0")
    ext_enable = RVA23_ENABLE;
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T71_sh1add_reg")

    // -----------------------------------------------------------------------
    // T72: en_h=0 -- HFENCE.VVMA (f7=0100001, f3=000) -> ILLEGAL
    //   OP_SYSTEM, rd=0, any rs1/rs2
    // -----------------------------------------------------------------------
    ext_enable        = RVA23_ENABLE;
    ext_enable.en_h   = 1'b0;
    clear_all();
    drive(0, enc_r(7'b0100001, 5'd1, 5'd2, 3'b000, 5'd0, OPSYSTEM));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T72_hfence_en_h0")
    ext_enable = RVA23_ENABLE;
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T72_hfence_reg")

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    $display("");
    $display("====================================================");
    $display("instr_decoder: PASS=%0d  FAIL=%0d", pass_count, fail_count);
    $display("====================================================");
    if (fail_count != 0)
        $display("STATUS: FAIL");
    else
        $display("STATUS: PASS");

    $finish;
end

endmodule

`default_nettype wire
