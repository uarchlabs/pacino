// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// tb_instr_decoder.sv
// Self-checking testbench for instr_decoder.
// Drives ifu_pd_pkt_t bundles (wrapping raw instructions) and
// verifies decoded fields in decode_pkt_t bundles.
// Uses a free-running clock for Verilator 5.020 --timing compatibility.
// DECODE-010: input changed from raw bits to predecode_pkt_t.
// BP-118 (TD#143): input changed to ifu_pd_pkt_t, the ibuf read port
//   bundle. make_pd_pkt() wraps a raw 32-bit instruction into an
//   ifu_pd_pkt_t with valid set and no fault. The old predecode_pkt_t
//   is retired. T65 and T66 encoded the compressed-extension gating
//   that DCD-20 deletes and are restated; T73 to T75 cover DCD-17 to
//   DCD-19 and the DCD-18 pass-through.
// BP-120 (TD#155): en_c and en_zcb are removed from ext_enable_t. T66
//   and T65's en_c=0 case are removed with them (listed at T65).
// ---------------------------------------------------------------------------
// ===================================================================
`default_nettype none
`timescale 1ns/1ps

import bp_defines_pkg::*;
import bp_structs_pkg::*;
import decode_pkg::*;

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
ifu_pd_pkt_t                 pd_bundle [0:SLOTS-1];
decode_pkt_t     [SLOTS-1:0] decode_bundle;
/* verilator lint_off UNUSEDSIGNAL */
vec_decode_pkt_t [SLOTS-1:0] vec_decode_bundle;
logic            [SLOTS-1:0] is_vector;
/* verilator lint_on UNUSEDSIGNAL */
ifu_pd_pkt_t                 pd_out    [0:SLOTS-1];
logic            [SLOTS-1:0] vtype_hazard;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
instr_decoder dut (
    .ext_enable        (ext_enable),
    .pd_bundle         (pd_bundle),
    .decode_bundle     (decode_bundle),
    .vec_decode_bundle (vec_decode_bundle),
    .is_vector         (is_vector),
    .pd_out            (pd_out),
    .vtype_hazard      (vtype_hazard)
);

// ---------------------------------------------------------------------------
// Test infrastructure
// ---------------------------------------------------------------------------
int pass_count;
int fail_count;

// ---------------------------------------------------------------------------
// make_pd_pkt: wrap a raw 32-bit instruction into ifu_pd_pkt_t
// Sets valid=1 and fault_cause=IFU_FAULT_NONE. The remaining fields
// are zero; T75 drives them. ifu_pd_pkt_t carries no is_vsetvl or
// needs_vtype since BP-125 (TD#148): decode computes its own (DCD-17).
// ---------------------------------------------------------------------------
function automatic ifu_pd_pkt_t make_pd_pkt(
    input logic [31:0] instr
);
    ifu_pd_pkt_t pkt;
    pkt             = '0;
    pkt.valid       = 1'b1;
    pkt.instr       = instr;
    pkt.fault_cause = IFU_FAULT_NONE;
    return pkt;
endfunction

task automatic clear_all();
    int s;
    for (s = 0; s < SLOTS; s++) begin
        pd_bundle[s] = '0;
    end
endtask

task automatic drive(
    input int          slot,
    input logic [31:0] instr
);
    pd_bundle[slot] = make_pd_pkt(instr);
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

// check_hazard: compare all 8 vtype_hazard bits against an expected
// mask, one check per slot.
task automatic check_hazard(
    input logic [SLOTS-1:0] exp_mask,
    input string            tname
);
    for (int k = 0; k < SLOTS; k++) begin
        if (vtype_hazard[k] !== exp_mask[k]) begin
            $display("FAIL [%s] slot=%0d vtype_hazard got=%0b exp=%0b",
                     tname, k, vtype_hazard[k], exp_mask[k]);
            fail_count++;
        end else
            pass_count++;
    end
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

// ck78: one T78 layout check (BP-124).
task automatic ck78(input string nm, input int got, input int exp);
    if (got != exp) begin
        $display("FAIL [T78 %s] got %0d exp %0d", nm, got, exp);
        fail_count++;
    end else begin
        pass_count++;
    end
endtask

// ---------------------------------------------------------------------------
// The oracle sweep (BP-124 Problem 4, DCD-34). +SWEEP=<file> runs only
// this: the file is dec_sweep_expect.py's expectation of every encoding
// in tb/dec_dasm_oracle.txt (spike-dasm's text, with the table from each
// mnemonic to its operation and the named rules that resolve each
// disagreement with spike-dasm). Each line is {word, illegal, vector,
// op, rule}. Every word is decoded with RVA23_ENABLE, eight per bundle,
// and must match: illegal with no vector packet, or legal with the
// operation (alu_op, or ALU_VEC and v_op_class for a vector word).
// ---------------------------------------------------------------------------
localparam int SW_MAX   = 524288;
localparam int SW_RULES = 4;
logic [63:0] sw_mem [0:SW_MAX-1];

task automatic run_sweep(input string fn);
    int n;
    int n_bad;
    int n_rule [0:SW_RULES-1];
    int n_ill;
    int n_leg;
    logic sw_all;    // +SWEEP_ALL: print every mismatch, not the first 40
    sw_all = $test$plusargs("SWEEP_ALL");
    for (int i = 0; i < SW_MAX; i++) sw_mem[i] = '1;
    $readmemh(fn, sw_mem);
    for (int r = 0; r < SW_RULES; r++) n_rule[r] = 0;
    n     = 0;
    n_bad = 0;
    n_ill = 0;
    n_leg = 0;
    ext_enable = RVA23_ENABLE;
    while ((n < SW_MAX) && (sw_mem[n] != '1)) begin
        int k;
        clear_all();
        k = 0;
        while ((k < SLOTS) && (n + k < SW_MAX) && (sw_mem[n + k] != '1)) begin
            drive(k, sw_mem[n + k][63:32]);
            k++;
        end
        #1;
        for (int s = 0; s < k; s++) begin
            logic [63:0] e;
            logic        ok;
            e = sw_mem[n + s];
            if (e[31:28] != 4'd0)
                ok = decode_bundle[s].is_illegal && !is_vector[s] &&
                     (decode_bundle[s].alu_op == ALU_ILL);
            else if (e[27:24] != 4'd0)
                ok = !decode_bundle[s].is_illegal && is_vector[s] &&
                     (decode_bundle[s].alu_op == ALU_VEC) &&
                     (8'(vec_decode_bundle[s].v_op_class) == e[23:16]);
            else
                ok = !decode_bundle[s].is_illegal && !is_vector[s] &&
                     (8'(decode_bundle[s].alu_op) == e[23:16]);
            if (int'(e[15:0]) < SW_RULES) n_rule[int'(e[15:0])]++;
            if (e[31:28] != 4'd0) n_ill++;
            else                  n_leg++;
            if (!ok) begin
                n_bad++;
                if ((n_bad <= 40) || sw_all)
                    $display("%s", $sformatf(
                        {"FAIL [sweep] %08h exp ill %0d vec %0d op %0d ",
                         "rule %0d; got ill %0d vec %0d alu %0d vop %0d"},
                        e[63:32], e[31:28], e[27:24], e[23:16], e[15:0],
                        decode_bundle[s].is_illegal, is_vector[s],
                        decode_bundle[s].alu_op,
                        vec_decode_bundle[s].v_op_class));
                fail_count++;
            end else begin
                pass_count++;
            end
        end
        n += k;
        @(posedge clk);
    end
    $display("sweep: %0d encodings, %0d expected legal, %0d illegal", n,
             n_leg, n_ill);
    for (int r = 0; r < SW_RULES; r++)
        $display("sweep: rule %0d decided %0d encodings", r, n_rule[r]);
    if (n == 0) begin
        $display("FAIL [sweep] no encodings read from %s", fn);
        fail_count++;
    end
endtask

// ---------------------------------------------------------------------------
// Test cases
// ---------------------------------------------------------------------------
initial begin
    string sw_file;
    pass_count   = 0;
    fail_count   = 0;
    ext_enable   = RVA23_ENABLE; // all extensions enabled by default
    pd_bundle    = '{default: '0};

    if ($value$plusargs("SWEEP=%s", sw_file)) begin
        run_sweep(sw_file);
        $display("instr_decoder sweep: PASS=%0d  FAIL=%0d", pass_count,
                 fail_count);
        if (fail_count != 0) begin
            $display("STATUS: FAIL");
            $fatal(1, "tb_instr_decoder: sweep, %0d mismatches", fail_count);
        end else begin
            $display("STATUS: PASS");
            $finish;
        end
    end

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
    // T39: OPIVV unrecognized funct6 -> VOTHER, which is illegal with a
    //   zero vector packet (DCD-32, BP-124)
    //   funct6=0x01 is vandn.vv (Zvbb, DCD-33, BP-124); it was unused
    //   funct6=0x08 is unused in OPIVV
    // -----------------------------------------------------------------------
    clear_all();
    drive(0, {6'h01, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    drive(1, {6'h08, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, OPVECTOR});
    @(posedge clk);
    `CHECK_VEC(0, v_op_class, VOP_VANDN, "T39_OPIVV_f6_0x01_vandn")
    `CHECK_FIELD(1, is_illegal, 1'b1, "T39_OPIVV_undef_f6_0x08")
    `CHECK_VEC(1, is_vector, 1'b0, "T39_OPIVV_undef_f6_0x08")

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
    `CHECK_FIELD(6, is_illegal, 1'b1, "T45_reg_OPMVX_undef_f6")
    `CHECK_VEC(6, is_vector, 1'b0, "T45_reg_OPMVX_undef_f6")
    `CHECK_FIELD(7, is_illegal, 1'b1, "T45_OPFVV_undef_f6_0x11")
    `CHECK_VEC(7, is_vector, 1'b0, "T45_OPFVV_undef_f6_0x11")

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
    `CHECK_FIELD(4, is_illegal, 1'b1, "T50_OPMVV_vwmaccus_undef")
    `CHECK_VEC(4, is_vector, 1'b0, "T50_OPMVV_vwmaccus_undef")

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
    `CHECK_FIELD(5, is_illegal, 1'b1, "T52_OPMVV_0x14_sub0_undef")
    `CHECK_VEC(5, is_vector, 1'b0, "T52_OPMVV_0x14_sub0_undef")
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
    `CHECK_FIELD(7, is_illegal, 1'b1, "T53_s7_OPMVV_undef_3e")
    `CHECK_VEC(7, is_vector, 1'b0, "T53_s7_OPMVV_undef_3e")
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
    `CHECK_FIELD(0, is_illegal, 1'b1, "T54_OPMVV_f6_3e_undef")
    `CHECK_VEC(0, is_vector, 1'b0, "T54_OPMVV_f6_3e_undef")
    `CHECK_FIELD(1, is_illegal, 1'b1, "T54_OPMVV_f6_28_undef")
    `CHECK_VEC(1, is_vector, 1'b0, "T54_OPMVV_f6_28_undef")
    `CHECK_FIELD(2, is_illegal, 1'b1, "T54_OPMVX_f6_00_undef")
    `CHECK_VEC(2, is_vector, 1'b0, "T54_OPMVX_f6_00_undef")
    `CHECK_FIELD(3, is_illegal, 1'b1, "T54_OPMVX_f6_15_undef")
    `CHECK_VEC(3, is_vector, 1'b0, "T54_OPMVX_f6_15_undef")

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
    // BP-124 (DCD-24): an FP load executes in the load unit, so is_fp
    // is clear; rd_is_fp names its FP destination. This read is_fp = 1.
    if ((decode_bundle[6].is_fp !== 1'b0) ||
        (decode_bundle[6].rd_is_fp !== 1'b1)) begin
        $display("FAIL [T56_fld_reg] FLD is_fp 0 and rd_is_fp 1");
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
    if ((decode_bundle[7].is_fp !== 1'b0) ||
        (decode_bundle[7].rs2_is_fp !== 1'b1)) begin
        $display("FAIL [T56_fsd_reg] FSD is_fp 0 and rs2_is_fp 1");
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
    // Scalar FP slots: is_vector=0, an FP load (ALU_FLOAD, rd_is_fp;
    // is_fp clear, DCD-24, BP-124), not illegal
    for (int s = 4; s < 8; s++) begin
        if (is_vector[s]) begin
            $display("FAIL [T57_mix] slot%0d: expected is_vector=0", s);
            fail_count++;
        end else
            pass_count++;
        if (decode_bundle[s].is_fp || !decode_bundle[s].rd_is_fp ||
            (decode_bundle[s].alu_op != ALU_FLOAD)) begin
            $display("FAIL [T57_mix] slot%0d: expected an FP load", s);
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
    // T65: DCD-20, C is always enabled. ext_enable has no C or Zcb enable
    //   since BP-120 (TD#155): en_c and en_zcb are removed from
    //   ext_enable_t. Removed with them: T65_c_en_c0_expanded (is_illegal
    //   and alu_op, en_c=0), T66_zcb_en_zcb0_expanded (is_illegal and
    //   alu_op, en_zcb=0 and en_c=0) and T66_zcb_base_reg (en_zcb=0). Each
    //   checked that a zero enable had no effect; there is no enable to
    //   zero. The RVA23_ENABLE regression stays.
    // -----------------------------------------------------------------------
    ext_enable = RVA23_ENABLE;
    clear_all();
    // ADDI x1, x1, 1 (expanded c.addi x1, 1)
    drive(0, enc_i(12'd1, 5'd1, 3'b000, 5'd1, OPIMM));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T65_c_reg")

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
    // T72: en_h=0 -- HFENCE.VVMA (f7=0010001, f3=000) -> ILLEGAL
    //   OP_SYSTEM, rd=0, any rs1/rs2. BP-123: this encoded funct7
    //   0100001, as the decoder did; the encoding (privileged spec, H
    //   chapter; LLVM assembles hfence.vvma a0, a1 as 0x22b50073) is
    //   0010001. 0100001 is not an instruction and is illegal.
    // -----------------------------------------------------------------------
    ext_enable        = RVA23_ENABLE;
    ext_enable.en_h   = 1'b0;
    clear_all();
    drive(0, enc_r(7'b0010001, 5'd1, 5'd2, 3'b000, 5'd0, OPSYSTEM));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T72_hfence_en_h0")
    ext_enable = RVA23_ENABLE;
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b0, "T72_hfence_reg")
    drive(0, enc_r(7'b0100001, 5'd1, 5'd2, 3'b000, 5'd0, OPSYSTEM));
    @(posedge clk);
    `CHECK_FIELD(0, is_illegal, 1'b1, "T72_not_hfence")

    // -----------------------------------------------------------------------
    // T73: DCD-17, vtype_hazard computed in decode, per 8-slot bundle.
    //   Each case starts from a cleared bundle; nothing carries over.
    // -----------------------------------------------------------------------
    ext_enable = RVA23_ENABLE;

    // T73a: vsetvli and a vtype user in ONE bundle. Slot 0 vsetvli,
    //   slot 1 vadd.vv, slot 2 ADDI, slot 5 vle32.v. Hazard on 1 and 5
    //   only: the vsetvl itself and the scalar slot raise none.
    clear_all();
    drive(0, enc_vsetvli(5'd1, 5'd2, 3'b010, 3'b000, 1'b1, 1'b0));
    drive(1, enc_vadd_vv(5'd3, 5'd4, 5'd5, 1'b1));
    drive(2, enc_i(12'd7, 5'd2, 3'b000, 5'd6, OPIMM));
    drive(5, enc_vle32v(5'd7, 5'd8, 1'b1));
    @(posedge clk);
    check_hazard(8'b0010_0010, "T73a_same_bundle");

    // T73b: the same two SPLIT across bundles. Bundle A ends with the
    //   vsetvli in slot 7; bundle B has the vadd.vv in slot 0. The flag
    //   is intra-bundle (DCD-17), so neither bundle raises it.
    clear_all();
    drive(7, enc_vsetvli(5'd1, 5'd2, 3'b010, 3'b000, 1'b1, 1'b0));
    @(posedge clk);
    check_hazard(8'b0000_0000, "T73b_split_bundle_A");
    clear_all();
    drive(0, enc_vadd_vv(5'd3, 5'd4, 5'd5, 1'b1));
    @(posedge clk);
    check_hazard(8'b0000_0000, "T73b_split_bundle_B");

    // T73c: the vsetvl AFTER the user. Slot 0 vadd.vv, slot 1 vsetvl,
    //   slot 2 vsetivli. A later vsetvl does not hazard an earlier
    //   user, and a vsetvl does not need vtype, so nothing is set.
    clear_all();
    drive(0, enc_vadd_vv(5'd3, 5'd4, 5'd5, 1'b1));
    drive(1, enc_vsetvl(5'd1, 5'd2, 5'd3));
    drive(2, enc_vsetivli(5'd1, 5'd4, 3'b010, 3'b000, 1'b0, 1'b0));
    @(posedge clk);
    check_hazard(8'b0000_0000, "T73c_vsetvl_after_user");

    // T73d: decode's OWN classification. Slot 0 vsetvli; slot 1
    //   vl1re8.v: decode clears needs_vtype on whole-register forms, so
    //   no hazard. Slot 2 vle32.v: decode marks it, hazard set. Until
    //   BP-125 the IFU's needs_vtype bits in ifu_pd_pkt_t were forced
    //   the other way here; BP-125 removed them (TD#148).
    clear_all();
    drive(0, enc_vsetvli(5'd1, 5'd2, 3'b010, 3'b000, 1'b1, 1'b0));
    drive(1, enc_vl1rev(5'd3, 5'd4));
    drive(2, enc_vle32v(5'd7, 5'd8, 1'b1));
    @(posedge clk);
    check_hazard(8'b0000_0100, "T73d_own_needs_vtype");

    // T73e: a scalar slot is not a vsetvl. Slot 0 ADDI, slot 1
    //   vadd.vv. Until BP-125 slot 0 also carried an IFU is_vsetvl bit
    //   forced 1; ifu_pd_pkt_t no longer has it (TD#148).
    clear_all();
    drive(0, enc_i(12'd7, 5'd2, 3'b000, 5'd6, OPIMM));
    drive(1, enc_vadd_vv(5'd3, 5'd4, 5'd5, 1'b1));
    @(posedge clk);
    check_hazard(8'b0000_0000, "T73e_own_is_vsetvl");

    // T73f: an INVALID slot holding a vsetvli encoding seeds nothing.
    clear_all();
    drive(0, enc_vsetvli(5'd1, 5'd2, 3'b010, 3'b000, 1'b1, 1'b0));
    pd_bundle[0].valid = 1'b0;
    drive(1, enc_vadd_vv(5'd3, 5'd4, 5'd5, 1'b1));
    @(posedge clk);
    check_hazard(8'b0000_0000, "T73f_invalid_vsetvl");

    // T73g: a FAULTING slot holding a vsetvli encoding seeds nothing
    //   (DCD-19: its bits are meaningless).
    clear_all();
    drive(0, enc_vsetvli(5'd1, 5'd2, 3'b010, 3'b000, 1'b1, 1'b0));
    pd_bundle[0].fault_cause = IFU_FAULT_PAGE;
    drive(1, enc_vadd_vv(5'd3, 5'd4, 5'd5, 1'b1));
    @(posedge clk);
    check_hazard(8'b0000_0000, "T73g_fault_vsetvl");

    // -----------------------------------------------------------------------
    // T74: DCD-19, a fetch-faulting slot is not decoded as illegal.
    //   Every slot carries the all-zero word, which is an illegal
    //   encoding. Slots 0, 1, 2 fault with each cause; slot 3 does
    //   not fault and is the control: it IS illegal. Slot 4 faults
    //   while carrying a legal vadd.vv: no vector decode.
    // -----------------------------------------------------------------------
    clear_all();
    for (int k = 0; k < 4; k++) drive(k, 32'h0000_0000);
    pd_bundle[0].fault_cause = IFU_FAULT_ACCESS;
    pd_bundle[0].fault_va    = VA_WIDTH'(64'h0_8000_1000);
    pd_bundle[1].fault_cause = IFU_FAULT_PAGE;
    pd_bundle[1].fault_va    = VA_WIDTH'(64'h1_2345_6782);
    pd_bundle[2].fault_cause = IFU_FAULT_GUEST_PAGE;
    pd_bundle[2].fault_va    = VA_WIDTH'(64'h0_4000_0ffe);
    pd_bundle[2].fault_gpa   = FAULT_GPA_WIDTH'(64'h80_0001_ffff_f000);
    drive(4, enc_vadd_vv(5'd3, 5'd4, 5'd5, 1'b1));
    pd_bundle[4].fault_cause = IFU_FAULT_PAGE;
    @(posedge clk);
    for (int k = 0; k < 3; k++) begin
        `CHECK_FIELD(k, valid,      1'b1, "T74_fault_valid")
        `CHECK_FIELD(k, is_illegal, 1'b0, "T74_fault_no_illegal")
        if (pd_out[k].fault_cause !== pd_bundle[k].fault_cause ||
            pd_out[k].fault_va    !== pd_bundle[k].fault_va    ||
            pd_out[k].fault_gpa   !== pd_bundle[k].fault_gpa) begin
            $display("FAIL [T74_fault_passthru] slot=%0d", k);
            fail_count++;
        end else
            pass_count++;
    end
    `CHECK_FIELD(3, is_illegal, 1'b1, "T74_nofault_control_illegal")
    `CHECK_FIELD(4, is_illegal, 1'b0, "T74_fault_vadd_no_illegal")
    if (is_vector[4] !== 1'b0 || vec_decode_bundle[4] !== '0) begin
        $display("FAIL [T74_fault_vadd_no_vec] is_vector=%0b",
                 is_vector[4]);
        fail_count++;
    end else
        pass_count++;
    // T74b: the same faulting slot with en_v cleared and a vector
    //   encoding: still not illegal (the fault outranks the gate).
    ext_enable      = RVA23_ENABLE;
    ext_enable.en_v = 1'b0;
    @(posedge clk);
    `CHECK_FIELD(4, is_illegal, 1'b0, "T74b_fault_vadd_en_v0")
    ext_enable = RVA23_ENABLE;

    // -----------------------------------------------------------------------
    // T75: DCD-18, every ifu_pd_pkt_t field reaches pd_out unchanged,
    //   on all 8 slots, valid or not, faulting or not. Each slot gets
    //   a distinct pattern in every field, derived from the slot
    //   number so a slot swap is caught too.
    // -----------------------------------------------------------------------
    clear_all();
    for (int k = 0; k < SLOTS; k++) begin
        pd_bundle[k].valid       = (k != 6);
        pd_bundle[k].instr       = 32'h1234_5000 | 32'(k * 32'h111);
        pd_bundle[k].start_pc    = VA_WIDTH'(64'h1_0000_0000)
                                 + VA_WIDTH'(k * 2 + 1);
        pd_bundle[k].pos         = FTQ_PD_POS_BITS'(15 - k);
        pd_bundle[k].ftq_idx     = FTQ_IDX_BITS'(7 * k + 3);
        pd_bundle[k].fault_cause = ifu_fault_e'(k % 4);
        pd_bundle[k].fault_va    = VA_WIDTH'(64'h0_abcd_0000)
                                 ^ VA_WIDTH'(k);
        pd_bundle[k].fault_gpa   = FAULT_GPA_WIDTH'(64'h40_0001_5555_0000)
                                 ^ FAULT_GPA_WIDTH'(k << 4);
        pd_bundle[k].fault_gpa_imp = 2'(k + 1);    // BP-123, DCD-16
        pd_bundle[k].is_rvc      = k[0];
        pd_bundle[k].br_type     = k[1:0];
        pd_bundle[k].is_call     = k[1];
        pd_bundle[k].is_ret      = k[2];
    end
    @(posedge clk);
    for (int k = 0; k < SLOTS; k++) begin
        if (pd_out[k] !== pd_bundle[k]) begin
            $display("FAIL [T75_passthru] slot=%0d got=%h exp=%h",
                     k, pd_out[k], pd_bundle[k]);
            fail_count++;
        end else
            pass_count++;
    end


    // -----------------------------------------------------------------------
    // T76 (BP-123, Problem 5): RVA23 instructions this decoder rejected.
    //   The words are LLVM's (clang -march=rv64...zba_zbb_zbs_zicond_
    //   zimop_zicbop_zawrs_svinval_h_zfhmin, then llvm-objdump), not
    //   derived from the decoder. Each must decode legal to its own
    //   operation; with its extension's enable clear, a gated one is
    //   illegal. a0 = x10, a1 = x11, a2 = x12.
    //   BP-124: the SYSTEM fences, Svinval, HFENCE/HINVAL and WRS have
    //   their own operations (DCD-22); FLH and FSH are ALU_FLOAD and
    //   ALU_FSTORE (renamed from ALU_FLD and ALU_FSD). T77 covers them
    //   with words from clang and spike-dasm.
    // -----------------------------------------------------------------------
    begin
        typedef struct {
            logic [31:0] w;
            alu_op_t     op;
            int          gate;   // 0 none, 1 zba, 2 zbb, 3 zbs, 4 h,
                                 // 5 zfhmin
            string       nm;
        } t76_t;
        t76_t t [$];
        t.push_back('{32'h60459513, ALU_SEXTB,    2, "sext.b"});
        t.push_back('{32'h60559513, ALU_SEXTH,    2, "sext.h"});
        t.push_back('{32'h0805c53b, ALU_ZEXTH,    2, "zext.h"});
        t.push_back('{32'h08c5853b, ALU_ADDUW,    1, "add.uw"});
        t.push_back('{32'h20c5a533, ALU_SH1ADD,   1, "sh1add"});
        t.push_back('{32'h20c5c533, ALU_SH2ADD,   1, "sh2add"});
        t.push_back('{32'h20c5e533, ALU_SH3ADD,   1, "sh3add"});
        t.push_back('{32'h20c5a53b, ALU_SH1ADDUW, 1, "sh1add.uw"});
        t.push_back('{32'h20c5c53b, ALU_SH2ADDUW, 1, "sh2add.uw"});
        t.push_back('{32'h20c5e53b, ALU_SH3ADDUW, 1, "sh3add.uw"});
        t.push_back('{32'h0835951b, ALU_SLLIUW,   1, "slli.uw"});
        t.push_back('{32'h40c5f533, ALU_ANDN,     2, "andn"});
        t.push_back('{32'h40c5e533, ALU_ORN,      2, "orn"});
        t.push_back('{32'h40c5c533, ALU_XNOR,     2, "xnor"});
        t.push_back('{32'h60059513, ALU_CLZ,      2, "clz"});
        t.push_back('{32'h6005951b, ALU_CLZW,     2, "clzw"});
        t.push_back('{32'h60159513, ALU_CTZ,      2, "ctz"});
        t.push_back('{32'h6015951b, ALU_CTZW,     2, "ctzw"});
        t.push_back('{32'h60259513, ALU_CPOP,     2, "cpop"});
        t.push_back('{32'h6025951b, ALU_CPOPW,    2, "cpopw"});
        t.push_back('{32'h0ac5e533, ALU_MAX,      2, "max"});
        t.push_back('{32'h0ac5f533, ALU_MAXU,     2, "maxu"});
        t.push_back('{32'h0ac5c533, ALU_MIN,      2, "min"});
        t.push_back('{32'h0ac5d533, ALU_MINU,     2, "minu"});
        t.push_back('{32'h60c59533, ALU_ROL,      2, "rol"});
        t.push_back('{32'h60c5953b, ALU_ROLW,     2, "rolw"});
        t.push_back('{32'h60c5d533, ALU_ROR,      2, "ror"});
        t.push_back('{32'h6035d513, ALU_RORI,     2, "rori"});
        t.push_back('{32'h6035d51b, ALU_RORIW,    2, "roriw"});
        t.push_back('{32'h60c5d53b, ALU_RORW,     2, "rorw"});
        t.push_back('{32'h2875d513, ALU_ORCB,     2, "orc.b"});
        t.push_back('{32'h6b85d513, ALU_REV8,     2, "rev8"});
        t.push_back('{32'h48c59533, ALU_BCLR,     3, "bclr"});
        t.push_back('{32'h48359513, ALU_BCLRI,    3, "bclri"});
        t.push_back('{32'h48c5d533, ALU_BEXT,     3, "bext"});
        t.push_back('{32'h4835d513, ALU_BEXTI,    3, "bexti"});
        t.push_back('{32'h68c59533, ALU_BINV,     3, "binv"});
        t.push_back('{32'h68359513, ALU_BINVI,    3, "binvi"});
        t.push_back('{32'h28c59533, ALU_BSET,     3, "bset"});
        t.push_back('{32'h28359513, ALU_BSETI,    3, "bseti"});
        t.push_back('{32'h0ec5d533, ALU_CZEROEQZ, 0, "czero.eqz"});
        t.push_back('{32'h0ec5f533, ALU_CZERONEZ, 0, "czero.nez"});
        t.push_back('{32'h81c5c573, ALU_MOP,      0, "mop.r.0"});
        t.push_back('{32'hcdf5c573, ALU_MOP,      0, "mop.r.31"});
        t.push_back('{32'h82c5c573, ALU_MOP,      0, "mop.rr.0"});
        t.push_back('{32'hcec5c573, ALU_MOP,      0, "mop.rr.7"});
        t.push_back('{32'h0405e013, ALU_OR,       0, "prefetch.i"});
        t.push_back('{32'h0415e013, ALU_OR,       0, "prefetch.r"});
        t.push_back('{32'h0435e013, ALU_OR,       0, "prefetch.w"});
        t.push_back('{32'h00d00073, ALU_WRS_NTO,  0, "wrs.nto"});
        t.push_back('{32'h01d00073, ALU_WRS_STO,  0, "wrs.sto"});
        t.push_back('{32'h12b50073, ALU_SFENCE_VMA, 0, "sfence.vma"});
        t.push_back('{32'h16b50073, ALU_SINVAL_VMA, 0, "sinval.vma"});
        t.push_back('{32'h18000073, ALU_SFENCE_W_INVAL, 0,
                     "sfence.w.inval"});
        t.push_back('{32'h18100073, ALU_SFENCE_INVAL_IR, 0,
                     "sfence.inval.ir"});
        t.push_back('{32'h22b50073, ALU_HFENCE_VVMA, 4, "hfence.vvma"});
        t.push_back('{32'h62b50073, ALU_HFENCE_GVMA, 4, "hfence.gvma"});
        t.push_back('{32'h26b50073, ALU_HINVAL_VVMA, 4, "hinval.vvma"});
        t.push_back('{32'h66b50073, ALU_HINVAL_GVMA, 4, "hinval.gvma"});
        t.push_back('{32'h6005c573, ALU_LB,       4, "hlv.b"});
        t.push_back('{32'h6015c573, ALU_LBU,      4, "hlv.bu"});
        t.push_back('{32'h6405c573, ALU_LH,       4, "hlv.h"});
        t.push_back('{32'h6415c573, ALU_LHU,      4, "hlv.hu"});
        t.push_back('{32'h6435c573, ALU_LHU,      4, "hlvx.hu"});
        t.push_back('{32'h6805c573, ALU_LW,       4, "hlv.w"});
        t.push_back('{32'h6835c573, ALU_LWU,      4, "hlvx.wu"});
        t.push_back('{32'h6815c573, ALU_LWU,      4, "hlv.wu"});
        t.push_back('{32'h6c05c573, ALU_LD,       4, "hlv.d"});
        t.push_back('{32'h62a5c073, ALU_SB,       4, "hsv.b"});
        t.push_back('{32'h66a5c073, ALU_SH,       4, "hsv.h"});
        t.push_back('{32'h6aa5c073, ALU_SW,       4, "hsv.w"});
        t.push_back('{32'h6ea5c073, ALU_SD,       4, "hsv.d"});
        t.push_back('{32'h00059507, ALU_FLOAD,      5, "flh"});
        t.push_back('{32'h00a59027, ALU_FSTORE,      5, "fsh"});
        foreach (t[k]) begin
            ext_enable = RVA23_ENABLE;
            clear_all();
            drive(0, t[k].w);
            @(posedge clk);
            `CHECK_FIELD(0, is_illegal, 1'b0, {"T76_legal_", t[k].nm})
            `CHECK_FIELD(0, alu_op, t[k].op, {"T76_op_", t[k].nm})
            if (t[k].gate != 0) begin
                case (t[k].gate)
                    1: ext_enable.en_zba    = 1'b0;
                    2: ext_enable.en_zbb    = 1'b0;
                    3: ext_enable.en_zbs    = 1'b0;
                    4: ext_enable.en_h      = 1'b0;
                    default: ext_enable.en_zfhmin = 1'b0;
                endcase
                @(posedge clk);
                `CHECK_FIELD(0, is_illegal, 1'b1, {"T76_gated_", t[k].nm})
            end
        end
        // Zimop writes rd and reads nothing; the unary bitmanip forms
        // read rs1 only.
        ext_enable = RVA23_ENABLE;
        clear_all();
        drive(0, 32'hcec5c573);                         // mop.rr.7 a0
        @(posedge clk);
        `CHECK_FIELD(0, uses_rd,  1'b1, "T76_mop_rd")
        `CHECK_FIELD(0, uses_rs1, 1'b0, "T76_mop_no_rs1")
        `CHECK_FIELD(0, uses_rs2, 1'b0, "T76_mop_no_rs2")
        `CHECK_FIELD(0, rd,       5'd10, "T76_mop_rd_field")
        drive(0, 32'h60459513);                         // sext.b a0, a1
        @(posedge clk);
        `CHECK_FIELD(0, uses_rs2, 1'b0, "T76_sextb_no_rs2")
        // Zicbop off: prefetch.i is still the ORI HINT, legal.
        ext_enable.en_zicbop = 1'b0;
        drive(0, 32'h0405e013);
        @(posedge clk);
        `CHECK_FIELD(0, is_illegal, 1'b0, "T76_prefetch_i_zicbop_off")
        ext_enable = RVA23_ENABLE;
    end

    // -----------------------------------------------------------------------
    // T77 (BP-124, dcd_decisions.md DCD-21 to DCD-33): the representation
    //   and legality. Each entry is a word, the source clang -c assembled
    //   it from (RISC-V target, -march the extension set of DCD-34,
    //   .option norvc), and spike-dasm's text for it; make asm_dec_words
    //   (tb/chk_dec_words.py) assembles every source and disassembles
    //   every word and fails on any difference. spike-dasm does not print
    //   a static rounding mode, prints FLI's FP destination with an
    //   integer register name, and prints fence.tso as fence rw,rw; the
    //   rm, the register and fm are clang's.
    //   Each word is decoded with RVA23_ENABLE and every field is checked:
    //   alu_op (ALU_ILL for an illegal word), v_op_class for a vector
    //   word, uses_rd/rs1/rs2/rs3, rd/rs1/rs2_is_fp, fp_fmt, fp_src_fmt,
    //   is_load, is_store, is_fp, is_csr, is_hlsv, is_hlvx, imm, the
    //   register fields (the word's when used, else zero), funct7,
    //   is_branch and is_jump clear, and is_vector. Each enable named in
    //   g (bit i is the i-th field of ext_enable_t, en_m first) is then
    //   cleared alone and the word must decode illegal.
    //   BP-125 adds, for each DCD-32 class, a reserved word after its
    //   nearest legal word, and checks that an illegal word's vector
    //   packet is zero (DCD-36).
    // -----------------------------------------------------------------------
    begin
        typedef struct {
            logic [31:0] w;
            string       a;      // the source clang assembled
            string       d;      // spike-dasm's text
            alu_op_t     op;     // ALU_ILL: illegal
            v_op_class_t vop;    // checked when op is ALU_VEC
            logic [3:0]  u;      // uses_rd, uses_rs1, uses_rs2, uses_rs3
            logic [2:0]  f;      // rd_is_fp, rs1_is_fp, rs2_is_fp
            logic [1:0]  fm;     // fp_fmt
            logic [1:0]  sf;     // fp_src_fmt
            logic [5:0]  k;      // is_load, is_store, is_fp, is_csr,
                                 // is_hlsv, is_hlvx
            logic [31:0] imm;
            logic [15:0] g;      // the enables that gate it
        } tw_t;
        tw_t tw [$];
    tw.push_back('{32'h00c5f553, "fadd.s fa0, fa1, fa2",
                  "fadd.s fa0, fa1, fa2",
                  ALU_FADD, VCFG, 4'b1110, 3'b111, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'h02c5f553, "fadd.d fa0, fa1, fa2, dyn",
                  "fadd.d fa0, fa1, fa2",
                  ALU_FADD, VCFG, 4'b1110, 3'b111, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'h0ac58553, "fsub.d fa0, fa1, fa2, rne",
                  "fsub.d fa0, fa1, fa2",
                  ALU_FSUB, VCFG, 4'b1110, 3'b111, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'h10c59553, "fmul.s fa0, fa1, fa2, rtz",
                  "fmul.s fa0, fa1, fa2",
                  ALU_FMUL, VCFG, 4'b1110, 3'b111, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'h1ac5a553, "fdiv.d fa0, fa1, fa2, rdn",
                  "fdiv.d fa0, fa1, fa2",
                  ALU_FDIV, VCFG, 4'b1110, 3'b111, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'h5805b553, "fsqrt.s fa0, fa1, rup",
                  "fsqrt.s fa0, fa1",
                  ALU_FSQRT, VCFG, 4'b1100, 3'b110, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'h5a05c553, "fsqrt.d fa0, fa1, rmm",
                  "fsqrt.d fa0, fa1",
                  ALU_FSQRT, VCFG, 4'b1100, 3'b110, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'h20c58553, "fsgnj.s fa0, fa1, fa2",
                  "fsgnj.s fa0, fa1, fa2",
                  ALU_FSGNJ, VCFG, 4'b1110, 3'b111, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'h22c59553, "fsgnjn.d fa0, fa1, fa2",
                  "fsgnjn.d fa0, fa1, fa2",
                  ALU_FSGNJN, VCFG, 4'b1110, 3'b111, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'h20c5a553, "fsgnjx.s fa0, fa1, fa2",
                  "fsgnjx.s fa0, fa1, fa2",
                  ALU_FSGNJX, VCFG, 4'b1110, 3'b111, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'h2ac58553, "fmin.d fa0, fa1, fa2",
                  "fmin.d fa0, fa1, fa2",
                  ALU_FMIN, VCFG, 4'b1110, 3'b111, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'h28c59553, "fmax.s fa0, fa1, fa2",
                  "fmax.s fa0, fa1, fa2",
                  ALU_FMAX, VCFG, 4'b1110, 3'b111, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'hc0059553, "fcvt.w.s a0, fa1, rtz",
                  "fcvt.w.s a0, fa1",
                  ALU_FCVT_W, VCFG, 4'b1100, 3'b010, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'hc215f553, "fcvt.wu.d a0, fa1",
                  "fcvt.wu.d a0, fa1",
                  ALU_FCVT_WU, VCFG, 4'b1100, 3'b010, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'hc025f553, "fcvt.l.s a0, fa1",
                  "fcvt.l.s a0, fa1",
                  ALU_FCVT_L, VCFG, 4'b1100, 3'b010, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'hc235f553, "fcvt.lu.d a0, fa1",
                  "fcvt.lu.d a0, fa1",
                  ALU_FCVT_LU, VCFG, 4'b1100, 3'b010, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'hd005f553, "fcvt.s.w fa0, a1",
                  "fcvt.s.w fa0, a1",
                  ALU_FCVT_FW, VCFG, 4'b1100, 3'b100, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'hd2158553, "fcvt.d.wu fa0, a1",
                  "fcvt.d.wu fa0, a1",
                  ALU_FCVT_FWU, VCFG, 4'b1100, 3'b100, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'hd025f553, "fcvt.s.l fa0, a1",
                  "fcvt.s.l fa0, a1",
                  ALU_FCVT_FL, VCFG, 4'b1100, 3'b100, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'hd235f553, "fcvt.d.lu fa0, a1",
                  "fcvt.d.lu fa0, a1",
                  ALU_FCVT_FLU, VCFG, 4'b1100, 3'b100, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'h4015f553, "fcvt.s.d fa0, fa1",
                  "fcvt.s.d fa0, fa1",
                  ALU_FCVT_FF, VCFG, 4'b1100, 3'b110, 2'd0, 2'd1,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'h42058553, "fcvt.d.s fa0, fa1",
                  "fcvt.d.s fa0, fa1",
                  ALU_FCVT_FF, VCFG, 4'b1100, 3'b110, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'he0058553, "fmv.x.w a0, fa1",
                  "fmv.x.w a0, fa1",
                  ALU_FMV_XF, VCFG, 4'b1100, 3'b010, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'he2058553, "fmv.x.d a0, fa1",
                  "fmv.x.d a0, fa1",
                  ALU_FMV_XF, VCFG, 4'b1100, 3'b010, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'hf0058553, "fmv.w.x fa0, a1",
                  "fmv.w.x fa0, a1",
                  ALU_FMV_FX, VCFG, 4'b1100, 3'b100, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'hf2058553, "fmv.d.x fa0, a1",
                  "fmv.d.x fa0, a1",
                  ALU_FMV_FX, VCFG, 4'b1100, 3'b100, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'ha0c5a553, "feq.s a0, fa1, fa2",
                  "feq.s a0, fa1, fa2",
                  ALU_FEQ, VCFG, 4'b1110, 3'b011, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'ha2c59553, "flt.d a0, fa1, fa2",
                  "flt.d a0, fa1, fa2",
                  ALU_FLT, VCFG, 4'b1110, 3'b011, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'ha0c58553, "fle.s a0, fa1, fa2",
                  "fle.s a0, fa1, fa2",
                  ALU_FLE, VCFG, 4'b1110, 3'b011, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'he2059553, "fclass.d a0, fa1",
                  "fclass.d a0, fa1",
                  ALU_FCLASS, VCFG, 4'b1100, 3'b010, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'h68c5f543, "fmadd.s fa0, fa1, fa2, fa3",
                  "fmadd.s fa0, fa1, fa2, fa3",
                  ALU_FMADD, VCFG, 4'b1111, 3'b111, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'h6ac58547, "fmsub.d fa0, fa1, fa2, fa3, rne",
                  "fmsub.d fa0, fa1, fa2, fa3",
                  ALU_FMSUB, VCFG, 4'b1111, 3'b111, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'h68c5f54b, "fnmsub.s fa0, fa1, fa2, fa3",
                  "fnmsub.s fa0, fa1, fa2, fa3",
                  ALU_FNMSUB, VCFG, 4'b1111, 3'b111, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0004});
    tw.push_back('{32'h6ac5f54f, "fnmadd.d fa0, fa1, fa2, fa3",
                  "fnmadd.d fa0, fa1, fa2, fa3",
                  ALU_FNMADD, VCFG, 4'b1111, 3'b111, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0008});
    tw.push_back('{32'h00c5a507, "flw fa0, 12(a1)",
                  "flw fa0, 12(a1)",
                  ALU_FLOAD, VCFG, 4'b1100, 3'b100, 2'd0, 2'd0,
                  6'b100000, 32'h0000000c, 16'h0004});
    tw.push_back('{32'hff85b507, "fld fa0, -8(a1)",
                  "fld fa0, -8(a1)",
                  ALU_FLOAD, VCFG, 4'b1100, 3'b100, 2'd1, 2'd0,
                  6'b100000, 32'hfffffff8, 16'h0008});
    tw.push_back('{32'h00c5aa27, "fsw fa2, 20(a1)",
                  "fsw fa2, 20(a1)",
                  ALU_FSTORE, VCFG, 4'b0110, 3'b001, 2'd0, 2'd0,
                  6'b010000, 32'h00000014, 16'h0004});
    tw.push_back('{32'hfec5b827, "fsd fa2, -16(a1)",
                  "fsd fa2, -16(a1)",
                  ALU_FSTORE, VCFG, 4'b0110, 3'b001, 2'd1, 2'd0,
                  6'b010000, 32'hfffffff0, 16'h0008});
    tw.push_back('{32'h00659507, "flh fa0, 6(a1)",
                  "flh fa0, 6(a1)",
                  ALU_FLOAD, VCFG, 4'b1100, 3'b100, 2'd2, 2'd0,
                  6'b100000, 32'h00000006, 16'h0080});
    tw.push_back('{32'hfec59f27, "fsh fa2, -2(a1)",
                  "fsh fa2, -2(a1)",
                  ALU_FSTORE, VCFG, 4'b0110, 3'b001, 2'd2, 2'd0,
                  6'b010000, 32'hfffffffe, 16'h0080});
    tw.push_back('{32'he4058553, "fmv.x.h a0, fa1",
                  "fmv.x.h a0, fa1",
                  ALU_FMV_XF, VCFG, 4'b1100, 3'b010, 2'd2, 2'd0,
                  6'b001000, 32'h00000000, 16'h0080});
    tw.push_back('{32'hf4058553, "fmv.h.x fa0, a1",
                  "fmv.h.x fa0, a1",
                  ALU_FMV_FX, VCFG, 4'b1100, 3'b100, 2'd2, 2'd0,
                  6'b001000, 32'h00000000, 16'h0080});
    tw.push_back('{32'h40258553, "fcvt.s.h fa0, fa1",
                  "fcvt.s.h fa0, fa1",
                  ALU_FCVT_FF, VCFG, 4'b1100, 3'b110, 2'd0, 2'd2,
                  6'b001000, 32'h00000000, 16'h0080});
    tw.push_back('{32'h4405f553, "fcvt.h.s fa0, fa1",
                  "fcvt.h.s fa0, fa1",
                  ALU_FCVT_FF, VCFG, 4'b1100, 3'b110, 2'd2, 2'd0,
                  6'b001000, 32'h00000000, 16'h0080});
    tw.push_back('{32'h42258553, "fcvt.d.h fa0, fa1",
                  "fcvt.d.h fa0, fa1",
                  ALU_FCVT_FF, VCFG, 4'b1100, 3'b110, 2'd1, 2'd2,
                  6'b001000, 32'h00000000, 16'h0088});
    tw.push_back('{32'h4415f553, "fcvt.h.d fa0, fa1",
                  "fcvt.h.d fa0, fa1",
                  ALU_FCVT_FF, VCFG, 4'b1100, 3'b110, 2'd2, 2'd1,
                  6'b001000, 32'h00000000, 16'h0088});
    tw.push_back('{32'hf01d0553, "fli.s fa0, 0x1p+7",
                  "fli.s a0, 128.0",
                  ALU_FLI, VCFG, 4'b1000, 3'b100, 2'd0, 2'd0,
                  6'b001000, 32'h0000001a, 16'h0100});
    tw.push_back('{32'hf21f05d3, "fli.d fa1, inf",
                  "fli.d a1, inf",
                  ALU_FLI, VCFG, 4'b1000, 3'b100, 2'd1, 2'd0,
                  6'b001000, 32'h0000001e, 16'h0108});
    tw.push_back('{32'h28c5a553, "fminm.s fa0, fa1, fa2",
                  "fminm.s fa0, fa1, fa2",
                  ALU_FMINM, VCFG, 4'b1110, 3'b111, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0100});
    tw.push_back('{32'h2ac5b553, "fmaxm.d fa0, fa1, fa2",
                  "fmaxm.d fa0, fa1, fa2",
                  ALU_FMAXM, VCFG, 4'b1110, 3'b111, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0108});
    tw.push_back('{32'h4045b553, "fround.s fa0, fa1, rup",
                  "fround.s fa0, fa1",
                  ALU_FROUND, VCFG, 4'b1100, 3'b110, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0100});
    tw.push_back('{32'h4255f553, "froundnx.d fa0, fa1",
                  "froundnx.d fa0, fa1",
                  ALU_FROUNDNX, VCFG, 4'b1100, 3'b110, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0108});
    tw.push_back('{32'hc2859553, "fcvtmod.w.d a0, fa1, rtz",
                  "fcvtmod.w.d a0, fa1, rtz",
                  ALU_FCVTMOD_W_D, VCFG, 4'b1100, 3'b010, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0108});
    tw.push_back('{32'ha0c5c553, "fleq.s a0, fa1, fa2",
                  "fleq.s a0, fa1, fa2",
                  ALU_FLEQ, VCFG, 4'b1110, 3'b011, 2'd0, 2'd0,
                  6'b001000, 32'h00000000, 16'h0100});
    tw.push_back('{32'ha2c5d553, "fltq.d a0, fa1, fa2",
                  "fltq.d a0, fa1, fa2",
                  ALU_FLTQ, VCFG, 4'b1110, 3'b011, 2'd1, 2'd0,
                  6'b001000, 32'h00000000, 16'h0108});
    tw.push_back('{32'h04c5f553, ".insn r 0x53, 7, 0x02, fa0, fa1, fa2",
                  "fadd.h fa0, fa1, fa2",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h24c58553, ".insn r 0x53, 0, 0x12, fa0, fa1, fa2",
                  "fsgnj.h fa0, fa1, fa2",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'hd405f553, ".insn r 0x53, 7, 0x6a, a0, fa1, x0",
                  "fcvt.h.w fa0, a1",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'he4059553, ".insn r 0x53, 1, 0x72, a0, fa1, x0",
                  "fclass.h a0, fa1",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'hf4108553, ".insn r 0x53, 0, 0x7a, fa0, x1, x1",
                  "fli.h a0, min",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h2cc5a553, ".insn r 0x53, 2, 0x16, fa0, fa1, fa2",
                  "fminm.h fa0, fa1, fa2",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'he2158553, ".insn r 0x53, 0, 0x71, a0, fa1, x1",
                  "fmvh.x.d a0, fa1",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'hb2c58553, ".insn r 0x53, 0, 0x59, fa0, a1, a2",
                  "fmvp.d.x fa0, a1, a2",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h06c5f553, ".insn r 0x53, 7, 0x03, fa0, fa1, fa2",
                  "fadd.q fa0, fa1, fa2",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h0005c507, ".insn i 0x07, 4, fa0, 0(a1)",
                  "flq fa0, 0(a1)",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h00c5c027, ".insn s 0x27, 4, fa2, 0(a1)",
                  "fsq fa2, 0(a1)",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h4035f553, ".insn r 0x53, 7, 0x20, fa0, fa1, x3",
                  "fcvt.s.q fa0, fa1",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'hc2858553, ".insn r 0x53, 0, 0x61, a0, fa1, x8",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'hc285f553, ".insn r 0x53, 7, 0x61, a0, fa1, x8",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h00c5d553, ".insn r 0x53, 5, 0x00, fa0, fa1, fa2",
                  "fadd.s fa0, fa1, fa2",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h02c5e553, ".insn r 0x53, 6, 0x01, fa0, fa1, fa2",
                  "fadd.d fa0, fa1, fa2",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h6ac5e543, ".insn r4 0x43, 6, 1, fa0, fa1, fa2, fa3",
                  "fmadd.d fa0, fa1, fa2, fa3",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'hc005d553, ".insn r 0x53, 5, 0x60, a0, fa1, x0",
                  "fcvt.w.s a0, fa1",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h4205e553, ".insn r 0x53, 6, 0x21, fa0, fa1, x0",
                  "fcvt.d.s fa0, fa1",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h4045d553, ".insn r 0x53, 5, 0x20, fa0, fa1, x4",
                  "fround.s fa0, fa1",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h58158553, ".insn r 0x53, 0, 0x2c, fa0, fa1, x1",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h20c5b553, ".insn r 0x53, 3, 0x10, fa0, fa1, fa2",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h1005a52f, "lr.w a0, (a1)",
                  "lr.w a0, (a1)",
                  ALU_LR_W, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b100000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h1005b52f, "lr.d a0, (a1)",
                  "lr.d a0, (a1)",
                  ALU_LR_D, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b100000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h18c5a52f, "sc.w a0, a2, (a1)",
                  "sc.w a0, a2, (a1)",
                  ALU_SC_W, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b010000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h1ec5b52f, "sc.d.aqrl a0, a2, (a1)",
                  "sc.d.aqrl a0, a2, (a1)",
                  ALU_SC_D, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b010000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h0ec5a52f, "amoswap.w.aqrl a0, a2, (a1)",
                  "amoswap.w.aqrl a0, a2, (a1)",
                  ALU_AMOSWAP_W, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h08c5b52f, "amoswap.d a0, a2, (a1)",
                  "amoswap.d a0, a2, (a1)",
                  ALU_AMOSWAP_D, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h00c5a52f, "amoadd.w a0, a2, (a1)",
                  "amoadd.w a0, a2, (a1)",
                  ALU_AMOADD_W, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h02c5b52f, "amoadd.d.rl a0, a2, (a1)",
                  "amoadd.d.rl a0, a2, (a1)",
                  ALU_AMOADD_D, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h20c5a52f, "amoxor.w a0, a2, (a1)",
                  "amoxor.w a0, a2, (a1)",
                  ALU_AMOXOR_W, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h20c5b52f, "amoxor.d a0, a2, (a1)",
                  "amoxor.d a0, a2, (a1)",
                  ALU_AMOXOR_D, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h60c5a52f, "amoand.w a0, a2, (a1)",
                  "amoand.w a0, a2, (a1)",
                  ALU_AMOAND_W, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h60c5b52f, "amoand.d a0, a2, (a1)",
                  "amoand.d a0, a2, (a1)",
                  ALU_AMOAND_D, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h40c5a52f, "amoor.w a0, a2, (a1)",
                  "amoor.w a0, a2, (a1)",
                  ALU_AMOOR_W, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h40c5b52f, "amoor.d a0, a2, (a1)",
                  "amoor.d a0, a2, (a1)",
                  ALU_AMOOR_D, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h80c5a52f, "amomin.w a0, a2, (a1)",
                  "amomin.w a0, a2, (a1)",
                  ALU_AMOMIN_W, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h80c5b52f, "amomin.d a0, a2, (a1)",
                  "amomin.d a0, a2, (a1)",
                  ALU_AMOMIN_D, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'ha0c5a52f, "amomax.w a0, a2, (a1)",
                  "amomax.w a0, a2, (a1)",
                  ALU_AMOMAX_W, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'ha0c5b52f, "amomax.d a0, a2, (a1)",
                  "amomax.d a0, a2, (a1)",
                  ALU_AMOMAX_D, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'hc0c5a52f, "amominu.w a0, a2, (a1)",
                  "amominu.w a0, a2, (a1)",
                  ALU_AMOMINU_W, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'hc0c5b52f, "amominu.d a0, a2, (a1)",
                  "amominu.d a0, a2, (a1)",
                  ALU_AMOMINU_D, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'he0c5a52f, "amomaxu.w a0, a2, (a1)",
                  "amomaxu.w a0, a2, (a1)",
                  ALU_AMOMAXU_W, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'he0c5b52f, "amomaxu.d a0, a2, (a1)",
                  "amomaxu.d a0, a2, (a1)",
                  ALU_AMOMAXU_D, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b110000, 32'h00000000, 16'h0002});
    tw.push_back('{32'h00c5852f, ".insn r 0x2f, 0, 0x00, a0, a1, a2",
                  "amoadd.b a0, a2, (a1)",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h08c5952f, ".insn r 0x2f, 1, 0x04, a0, a1, a2",
                  "amoswap.h a0, a2, (a1)",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h28c5a52f, ".insn r 0x2f, 2, 0x14, a0, a1, a2",
                  "amocas.w a0, a2, (a1)",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h1015a52f, ".insn r 0x2f, 2, 0x08, a0, a1, x1",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h00c5c52f, ".insn r 0x2f, 4, 0x00, a0, a1, a2",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h0310000f, "fence rw, w",
                  "fence rw,w",
                  ALU_FENCE, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000031, 16'h0000});
    tw.push_back('{32'h8330000f, "fence.tso",
                  "fence rw,rw",
                  ALU_FENCE, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000833, 16'h0000});
    tw.push_back('{32'h0100000f, "pause",
                  "pause",
                  ALU_FENCE, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000010, 16'h0000});
    tw.push_back('{32'h7ff5850f, ".insn i 0x0f, 0, a0, a1, 0x7ff",
                  "fence iorw,iorw",
                  ALU_FENCE, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h000007ff, 16'h0000});
    tw.push_back('{32'h0000100f, "fence.i",
                  "fence.i",
                  ALU_FENCE_I, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h0055950f, ".insn i 0x0f, 1, a0, a1, 5",
                  "fence.i",
                  ALU_FENCE_I, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h0005200f, "cbo.inval (a0)",
                  "cbo.inval (a0)",
                  ALU_CBO_INVAL, VCFG, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0400});
    tw.push_back('{32'h0015200f, "cbo.clean (a0)",
                  "cbo.clean (a0)",
                  ALU_CBO_CLEAN, VCFG, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0400});
    tw.push_back('{32'h0025200f, "cbo.flush (a0)",
                  "cbo.flush (a0)",
                  ALU_CBO_FLUSH, VCFG, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0400});
    tw.push_back('{32'h0045200f, "cbo.zero (a0)",
                  "cbo.zero (a0)",
                  ALU_CBO_ZERO, VCFG, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h1000});
    tw.push_back('{32'h0035200f, ".insn i 0x0f, 2, x0, a0, 3",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h0015258f, ".insn i 0x0f, 2, a1, a0, 1",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h0005300f, ".insn i 0x0f, 3, x0, a0, 0",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h0005700f, ".insn i 0x0f, 7, x0, a0, 0",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h00000073, "ecall",
                  "ecall",
                  ALU_ECALL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000100, 32'h00000000, 16'h0000});
    tw.push_back('{32'h00100073, "ebreak",
                  "ebreak",
                  ALU_EBREAK, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000100, 32'h00000000, 16'h0000});
    tw.push_back('{32'h10200073, "sret",
                  "sret",
                  ALU_SRET, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000100, 32'h00000000, 16'h0000});
    tw.push_back('{32'h30200073, "mret",
                  "mret",
                  ALU_MRET, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000100, 32'h00000000, 16'h0000});
    tw.push_back('{32'h10500073, "wfi",
                  "wfi",
                  ALU_WFI, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000100, 32'h00000000, 16'h0000});
    tw.push_back('{32'h00d00073, "wrs.nto",
                  "wrs.nto",
                  ALU_WRS_NTO, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h01d00073, "wrs.sto",
                  "wrs.sto",
                  ALU_WRS_STO, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h12b50073, "sfence.vma a0, a1",
                  "sfence.vma a0, a1",
                  ALU_SFENCE_VMA, VCFG, 4'b0110, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h16b50073, "sinval.vma a0, a1",
                  "sinval.vma a0, a1",
                  ALU_SINVAL_VMA, VCFG, 4'b0110, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h18000073, "sfence.w.inval",
                  "sfence.w.inval",
                  ALU_SFENCE_W_INVAL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h18100073, "sfence.inval.ir",
                  "sfence.inval.ir",
                  ALU_SFENCE_INVAL_IR, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h22b50073, "hfence.vvma a0, a1",
                  "hfence.vvma a0, a1",
                  ALU_HFENCE_VVMA, VCFG, 4'b0110, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h8000});
    tw.push_back('{32'h62b50073, "hfence.gvma a0, a1",
                  "hfence.gvma a0, a1",
                  ALU_HFENCE_GVMA, VCFG, 4'b0110, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h8000});
    tw.push_back('{32'h26b50073, "hinval.vvma a0, a1",
                  "hinval.vvma a0, a1",
                  ALU_HINVAL_VVMA, VCFG, 4'b0110, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h8000});
    tw.push_back('{32'h66b50073, "hinval.gvma a0, a1",
                  "hinval.gvma a0, a1",
                  ALU_HINVAL_GVMA, VCFG, 4'b0110, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h8000});
    tw.push_back('{32'h6005c573, "hlv.b a0, (a1)",
                  "hlv.b a0, (a1)",
                  ALU_LB, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b100010, 32'h00000000, 16'h8000});
    tw.push_back('{32'h6015c573, "hlv.bu a0, (a1)",
                  "hlv.bu a0, (a1)",
                  ALU_LBU, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b100010, 32'h00000000, 16'h8000});
    tw.push_back('{32'h6405c573, "hlv.h a0, (a1)",
                  "hlv.h a0, (a1)",
                  ALU_LH, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b100010, 32'h00000000, 16'h8000});
    tw.push_back('{32'h6415c573, "hlv.hu a0, (a1)",
                  "hlv.hu a0, (a1)",
                  ALU_LHU, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b100010, 32'h00000000, 16'h8000});
    tw.push_back('{32'h6435c573, "hlvx.hu a0, (a1)",
                  "hlvx.hu a0, (a1)",
                  ALU_LHU, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b100011, 32'h00000000, 16'h8000});
    tw.push_back('{32'h6805c573, "hlv.w a0, (a1)",
                  "hlv.w a0, (a1)",
                  ALU_LW, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b100010, 32'h00000000, 16'h8000});
    tw.push_back('{32'h6815c573, "hlv.wu a0, (a1)",
                  "hlv.wu a0, (a1)",
                  ALU_LWU, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b100010, 32'h00000000, 16'h8000});
    tw.push_back('{32'h6835c573, "hlvx.wu a0, (a1)",
                  "hlvx.wu a0, (a1)",
                  ALU_LWU, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b100011, 32'h00000000, 16'h8000});
    tw.push_back('{32'h6c05c573, "hlv.d a0, (a1)",
                  "hlv.d a0, (a1)",
                  ALU_LD, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b100010, 32'h00000000, 16'h8000});
    tw.push_back('{32'h62c5c073, "hsv.b a2, (a1)",
                  "hsv.b a2, (a1)",
                  ALU_SB, VCFG, 4'b0110, 3'b000, 2'd0, 2'd0,
                  6'b010010, 32'h00000000, 16'h8000});
    tw.push_back('{32'h66c5c073, "hsv.h a2, (a1)",
                  "hsv.h a2, (a1)",
                  ALU_SH, VCFG, 4'b0110, 3'b000, 2'd0, 2'd0,
                  6'b010010, 32'h00000000, 16'h8000});
    tw.push_back('{32'h6ac5c073, "hsv.w a2, (a1)",
                  "hsv.w a2, (a1)",
                  ALU_SW, VCFG, 4'b0110, 3'b000, 2'd0, 2'd0,
                  6'b010010, 32'h00000000, 16'h8000});
    tw.push_back('{32'h6ec5c073, "hsv.d a2, (a1)",
                  "hsv.d a2, (a1)",
                  ALU_SD, VCFG, 4'b0110, 3'b000, 2'd0, 2'd0,
                  6'b010010, 32'h00000000, 16'h8000});
    tw.push_back('{32'h7c059573, "csrrw a0, 0x7c0, a1",
                  "csrrw a0, unknown_7c0, a1",
                  ALU_CSRRW, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b000100, 32'h000007c0, 16'h0200});
    tw.push_back('{32'h8005a573, "csrrs a0, 0x800, a1",
                  "csrrs a0, unknown_800, a1",
                  ALU_CSRRS, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b000100, 32'h00000800, 16'h0200});
    tw.push_back('{32'hfff5b573, "csrrc a0, 0xfff, a1",
                  "csrrc a0, unknown_fff, a1",
                  ALU_CSRRC, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b000100, 32'h00000fff, 16'h0200});
    tw.push_back('{32'h8002d573, "csrrwi a0, 0x800, 5",
                  "csrrwi a0, unknown_800, 5",
                  ALU_CSRRWI, VCFG, 4'b1000, 3'b000, 2'd0, 2'd0,
                  6'b000100, 32'h00005800, 16'h0200});
    tw.push_back('{32'hc00fe573, "csrrsi a0, 0xc00, 31",
                  "csrrsi a0, cycle, 31",
                  ALU_CSRRSI, VCFG, 4'b1000, 3'b000, 2'd0, 2'd0,
                  6'b000100, 32'h0001fc00, 16'h0200});
    tw.push_back('{32'hfff0f573, "csrrci a0, 0xfff, 1",
                  "csrrci a0, unknown_fff, 1",
                  ALU_CSRRCI, VCFG, 4'b1000, 3'b000, 2'd0, 2'd0,
                  6'b000100, 32'h00001fff, 16'h0200});
    tw.push_back('{32'h00000573, ".insn i 0x73, 0, a0, x0, 0",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h00158073, ".insn i 0x73, 0, x0, a1, 1",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h30200573, ".insn i 0x73, 0, a0, x0, 0x302",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h10258073, ".insn i 0x73, 0, x0, a1, 0x102",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h10500573, ".insn i 0x73, 0, a0, x0, 0x105",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h00d58073, ".insn i 0x73, 0, x0, a1, 0x00d",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h12b50673, ".insn r 0x73, 0, 0x09, a2, a0, a1",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h16b50673, ".insn r 0x73, 0, 0x0b, a2, a0, a1",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h22b50673, ".insn r 0x73, 0, 0x11, a2, a0, a1",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h18050073, ".insn r 0x73, 0, 0x0c, x0, a0, x0",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h18100673, ".insn r 0x73, 0, 0x0c, a2, x0, x1",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h62c5c573, ".insn r 0x73, 4, 0x31, a0, a1, a2",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h7b200073, ".insn i 0x73, 0, x0, x0, 0x7b2",
                  "dret",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h70200073, ".insn i 0x73, 0, x0, x0, 0x702",
                  "mnret (args unknown)",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h022180d7, "vadd.vv v1, v2, v3",
                  "vadd.vv v1, v2, v3",
                  ALU_VEC, VOP_VADD, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h022540d7, "vadd.vx v1, v2, a0",
                  "vadd.vx v1, v2, a0",
                  ALU_VEC, VOP_VADD, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h962560d7, "vmul.vx v1, v2, a0",
                  "vmul.vx v1, v2, a0",
                  ALU_VEC, VOP_VMUL, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h022550d7, "vfadd.vf v1, v2, fa0",
                  "vfadd.vf v1, v2, fa0",
                  ALU_VEC, VOP_VFADD, 4'b0100, 3'b010, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h5e0540d7, "vmv.v.x v1, a0",
                  "vmv.v.x v1, a0",
                  ALU_VEC, VOP_VMV, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h42302557, "vmv.x.s a0, v3",
                  "vmv.x.s a0, v3",
                  ALU_VEC, VOP_VMV_XS, 4'b1000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h42282557, "vcpop.m a0, v2",
                  "vcpop.m a0, v2",
                  ALU_VEC, VOP_VCPOP, 4'b1000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h4028a557, "vfirst.m a0, v2, v0.t",
                  "vfirst.m a0, v2, v0.t",
                  ALU_VEC, VOP_VFIRST, 4'b1000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h42201557, "vfmv.f.s fa0, v2",
                  "vfmv.f.s fa0, v2",
                  ALU_VEC, VOP_VFMV_FS, 4'b1000, 3'b100, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h420550d7, "vfmv.s.f v1, fa0",
                  "vfmv.s.f v1, fa0",
                  ALU_VEC, VOP_VFMV, 4'b0100, 3'b010, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h80c5f557, "vsetvl a0, a1, a2",
                  "vsetvl a0, a1, a2",
                  ALU_VEC, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h0db5f557, "vsetvli a0, a1, e64, m8, ta, ma",
                  "vsetvli a0, a1, e64, m8, ta, ma",
                  ALU_VEC, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h000000db, 16'h0000});
    tw.push_back('{32'h7ff5f557, "vsetvli a0, a1, 0x7ff",
                  "vsetvli a0, a1, 0x7ff",
                  ALU_VEC, VCFG, 4'b1100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h000007ff, 16'h0000});
    tw.push_back('{32'hc00ff557, "vsetivli a0, 31, e8, m1, tu, mu",
                  "vsetivli a0, 31, e8, m1, tu, mu",
                  ALU_VEC, VCFG, 4'b1000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h001f0000, 16'h0000});
    tw.push_back('{32'hfff8f557, "vsetivli a0, 17, 0x3ff",
                  "vsetivli a0, 17, 0x3ff",
                  ALU_VEC, VCFG, 4'b1000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h001103ff, 16'h0000});
    tw.push_back('{32'h02056087, "vle32.v v1, (a0)",
                  "vle32.v v1, (a0)",
                  ALU_VEC, VOP_VLE, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b100000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h0ab56087, "vlse32.v v1, (a0), a1",
                  "vlse32.v v1, (a0), a1",
                  ALU_VEC, VOP_VLSE, 4'b0110, 3'b000, 2'd0, 2'd0,
                  6'b100000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h06256087, "vluxei32.v v1, (a0), v2",
                  "vluxei32.v v1, (a0), v2",
                  ALU_VEC, VOP_VLUXE, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b100000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h020501a7, "vse8.v v3, (a0)",
                  "vse8.v v3, (a0)",
                  ALU_VEC, VOP_VSE, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b010000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h0ab571a7, "vsse64.v v3, (a0), a1",
                  "vsse64.v v3, (a0), a1",
                  ALU_VEC, VOP_VSSE, 4'b0110, 3'b000, 2'd0, 2'd0,
                  6'b010000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h22850107, "vl2re8.v v2, (a0)",
                  "vl2re8.v v2, (a0)",
                  ALU_VEC, VOP_VLWHOLE, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b100000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h62850227, "vs4r.v v4, (a0)",
                  "vs4r.v v4, (a0)",
                  ALU_VEC, VOP_VSWHOLE, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b010000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h022830d7, "vadd.vi v1, v2, -16",
                  "vadd.vi v1, v2, -16",
                  ALU_VEC, VOP_VADD, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'hfffffff0, 16'h0000});
    tw.push_back('{32'h0e27b0d7, "vrsub.vi v1, v2, 15",
                  "vrsub.vi v1, v2, 15",
                  ALU_VEC, VOP_VRSUB, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h0000000f, 16'h0000});
    tw.push_back('{32'h8222b0d7, "vsaddu.vi v1, v2, 5",
                  "vsaddu.vi v1, v2, 5",
                  ALU_VEC, VOP_VSADDU, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000005, 16'h0000});
    tw.push_back('{32'h3a2fb0d7, "vslideup.vi v1, v2, 31",
                  "vslideup.vi v1, v2, 31",
                  ALU_VEC, VOP_VSLIDEUP, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h0000001f, 16'h0000});
    tw.push_back('{32'hb22a30d7, "vnsrl.wi v1, v2, 20",
                  "vnsrl.wi v1, v2, 20",
                  ALU_VEC, VOP_VNSRL, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000014, 16'h0000});
    tw.push_back('{32'h3228b0d7, "vrgather.vi v1, v2, 17",
                  "vrgather.vi v1, v2, 17",
                  ALU_VEC, VOP_VRGATHER, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000011, 16'h0000});
    tw.push_back('{32'h222180d7, ".insn r 0x57, 0, 0x11, v1, v3, v2",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h02150087, ".insn i 0x07, 0, v1, 0x021(a0)",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h030501a7, ".insn s 0x27, 0, a6, 0x023(a0)",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h230501a7, ".insn s 0x27, 0, a6, 0x223(a0)",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h062180d7, "vandn.vv v1, v2, v3",
                  "vandn.vv v1, v2, v3",
                  ALU_VEC, VOP_VANDN, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'h062540d7, "vandn.vx v1, v2, a0",
                  "vandn.vx v1, v2, a0",
                  ALU_VEC, VOP_VANDN, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'h4a2520d7, "vbrev.v v1, v2",
                  "vbrev.v v1, v2",
                  ALU_VEC, VOP_VBREV, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'h4a2420d7, "vbrev8.v v1, v2",
                  "vbrev8.v v1, v2",
                  ALU_VEC, VOP_VBREV8, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'h4824a0d7, "vrev8.v v1, v2, v0.t",
                  "vrev8.v v1, v2, v0.t",
                  ALU_VEC, VOP_VREV8, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'h4a2620d7, "vclz.v v1, v2",
                  "vclz.v v1, v2",
                  ALU_VEC, VOP_VCLZ, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'h4a26a0d7, "vctz.v v1, v2",
                  "vctz.v v1, v2",
                  ALU_VEC, VOP_VCTZ, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'h4a2720d7, "vcpop.v v1, v2",
                  "vcpop.v v1, v2",
                  ALU_VEC, VOP_VCPOP_V, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'h562180d7, "vrol.vv v1, v2, v3",
                  "vrol.vv v1, v2, v3",
                  ALU_VEC, VOP_VROL, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'h562540d7, "vrol.vx v1, v2, a0",
                  "vrol.vx v1, v2, a0",
                  ALU_VEC, VOP_VROL, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'h522180d7, "vror.vv v1, v2, v3",
                  "vror.vv v1, v2, v3",
                  ALU_VEC, VOP_VROR, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'h522540d7, "vror.vx v1, v2, a0",
                  "vror.vx v1, v2, a0",
                  ALU_VEC, VOP_VROR, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'h562fb0d7, "vror.vi v1, v2, 63",
                  "vror.vi v1, v2, 63",
                  ALU_VEC, VOP_VROR, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h0000003f, 16'h2000});
    tw.push_back('{32'h5620b0d7, "vror.vi v1, v2, 33",
                  "vror.vi v1, v2, 33",
                  ALU_VEC, VOP_VROR, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000021, 16'h2000});
    tw.push_back('{32'h5223b0d7, "vror.vi v1, v2, 7",
                  "vror.vi v1, v2, 7",
                  ALU_VEC, VOP_VROR, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000007, 16'h2000});
    tw.push_back('{32'hd6430157, "vwsll.vv v2, v4, v6",
                  "vwsll.vv v2, v4, v6",
                  ALU_VEC, VOP_VWSLL, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'hd6454157, "vwsll.vx v2, v4, a0",
                  "vwsll.vx v2, v4, a0",
                  ALU_VEC, VOP_VWSLL, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h2000});
    tw.push_back('{32'hd64fb157, "vwsll.vi v2, v4, 31",
                  "vwsll.vi v2, v4, 31",
                  ALU_VEC, VOP_VWSLL, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h0000001f, 16'h2000});
    // BP-125 (DCD-32, TD#175): one reserved encoding of each DCD-32
    // class, illegal with a zero vector packet (DCD-36), each after
    // its nearest legal encoding: the same instruction with the
    // field at its defined value.
    tw.push_back('{32'h02050087, "vle8.v v1, (a0)",
                  "vle8.v v1, (a0)",
                  ALU_VEC, VOP_VLE, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b100000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h12050087, ".insn i 0x07, 0, v1, 0x120(a0)",
                  "vle128.v v1, (a0)",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h22050087, "vlseg2e8.v v1, (a0)",
                  "vlseg2e8.v v1, (a0)",
                  ALU_VEC, VOP_VLSEG, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b100000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h22150087, ".insn i 0x07, 0, v1, 0x221(a0)",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h22850107, "vl2re8.v v2, (a0)",
                  "vl2re8.v v2, (a0)",
                  ALU_VEC, VOP_VLWHOLE, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b100000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h42850107, ".insn i 0x07, 0, v2, 0x428(a0)",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h62850227, "vs4r.v v4, (a0)",
                  "vs4r.v v4, (a0)",
                  ALU_VEC, VOP_VSWHOLE, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b010000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h62855227, ".insn s 0x27, 5, x8, 0x624(a0)",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h02b50087, "vlm.v v1, (a0)",
                  "vlm.v v1, (a0)",
                  ALU_VEC, VOP_VLM, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b100000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h00b50087, ".insn i 0x07, 0, v1, 0x00b(a0)",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h80c5f557, "vsetvl a0, a1, a2",
                  "vsetvl a0, a1, a2",
                  ALU_VEC, VCFG, 4'b1110, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h82c5f557, ".insn r 0x57, 7, 0x41, a0, a1, a2",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h402180d7, "vadc.vvm v1, v2, v3, v0",
                  "vadc.vvm v1, v2, v3, v0",
                  ALU_VEC, VOP_VADC, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h422180d7, ".insn r 0x57, 0, 0x21, v1, v3, v2",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h5e0180d7, "vmv.v.v v1, v3",
                  "vmv.v.v v1, v3",
                  ALU_VEC, VOP_VMV, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h5e2180d7, ".insn r 0x57, 0, 0x2f, v1, v3, v2",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h420560d7, "vmv.s.x v1, a0",
                  "vmv.s.x v1, a0",
                  ALU_VEC, VOP_VMV_SX, 4'b0100, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h422560d7, ".insn r 0x57, 6, 0x21, v1, a0, v2",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h42302557, "vmv.x.s a0, v3",
                  "vmv.x.s a0, v3",
                  ALU_VEC, VOP_VMV_XS, 4'b1000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h40302557, ".insn r 0x57, 2, 0x20, a0, x0, v3",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h9e40b157, "vmv2r.v v2, v4",
                  "vmv2r.v v2, v4",
                  ALU_VEC, VOP_VMVNR, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000001, 16'h0000});
    tw.push_back('{32'h9e413157, ".insn r 0x57, 3, 0x4f, v2, x2, v4",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h6621a0d7, "vmand.mm v1, v2, v3",
                  "vmand.mm v1, v2, v3",
                  ALU_VEC, VOP_VMAND, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h6421a0d7, ".insn r 0x57, 2, 0x32, v1, v3, v2",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h5208a0d7, "vid.v v1",
                  "vid.v v1",
                  ALU_VEC, VOP_VID, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h5228a0d7, ".insn r 0x57, 2, 0x29, v1, x17, v2",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h4a2010d7, "vfcvt.xu.f.v v1, v2",
                  "vfcvt.xu.f.v v1, v2",
                  ALU_VEC, VOP_VFCVT, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h4a2210d7, ".insn r 0x57, 1, 0x25, v1, x4, v2",
                  "unknown",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h4a2610d7, "vfwcvt.f.f.v v1, v2",
                  "vfwcvt.f.f.v v1, v2",
                  ALU_VEC, VOP_VFWCVT_FF, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
    tw.push_back('{32'h4a2690d7, ".insn r 0x57, 1, 0x25, v1, x13, v2",
                  "vfwcvtbf16.f.f.v v1, v2",
                  ALU_ILL, VCFG, 4'b0000, 3'b000, 2'd0, 2'd0,
                  6'b000000, 32'h00000000, 16'h0000});
        foreach (tw[k]) begin
            decode_pkt_t     d;
            vec_decode_pkt_t v;
            logic            ill;
            logic            ok;
            logic [31:0]     w;
            string           nm;
            w   = tw[k].w;
            nm  = $sformatf("T77 %08h %s", w, tw[k].a);
            ill = (tw[k].op == ALU_ILL);
            ext_enable = RVA23_ENABLE;
            clear_all();
            drive(0, w);
            #1;
            d  = decode_bundle[0];
            v  = vec_decode_bundle[0];
            ok = d.valid && (d.is_illegal == ill) && (d.alu_op == tw[k].op) &&
                 (d.opcode == w[6:0]) && (d.funct7 == w[31:25]) &&
                 ({d.uses_rd, d.uses_rs1, d.uses_rs2, d.uses_rs3} ==
                  tw[k].u) &&
                 ({d.rd_is_fp, d.rs1_is_fp, d.rs2_is_fp} == tw[k].f) &&
                 (d.fp_fmt == tw[k].fm) && (d.fp_src_fmt == tw[k].sf) &&
                 ({d.is_load, d.is_store, d.is_fp, d.is_csr, d.is_hlsv,
                   d.is_hlvx} == tw[k].k) &&
                 (d.imm == tw[k].imm) &&
                 (d.rd  == (tw[k].u[3] ? w[11:7]  : 5'd0)) &&
                 (d.rs1 == (tw[k].u[2] ? w[19:15] : 5'd0)) &&
                 (d.rs2 == (tw[k].u[1] ? w[24:20] : 5'd0)) &&
                 (d.rs3 == (tw[k].u[0] ? w[31:27] : 5'd0)) &&
                 !d.is_branch && !d.is_jump &&
                 (is_vector[0] == (tw[k].op == ALU_VEC)) &&
                 ((tw[k].op != ALU_VEC) || (v.v_op_class == tw[k].vop)) &&
                 // DCD-36 (BP-125): an illegal word's vector packet is
                 // zero
                 (!ill || (v == '0));
            if (!ok) begin
                $display("%s", $sformatf(
                    {"FAIL [%s] ill %0d alu %0d vop %0d u %b f %b fm %0d ",
                     "sf %0d k %b imm %h rd %0d rs1 %0d rs2 %0d rs3 %0d"},
                    nm, d.is_illegal, d.alu_op, v.v_op_class,
                    {d.uses_rd, d.uses_rs1, d.uses_rs2, d.uses_rs3},
                    {d.rd_is_fp, d.rs1_is_fp, d.rs2_is_fp}, d.fp_fmt,
                    d.fp_src_fmt, {d.is_load, d.is_store, d.is_fp,
                    d.is_csr, d.is_hlsv, d.is_hlvx}, d.imm, d.rd, d.rs1,
                    d.rs2, d.rs3));
                fail_count++;
            end else begin
                pass_count++;
            end
            // The gates: each enable cleared alone makes it illegal.
            for (int i = 0; i < 16; i++) begin
                if (tw[k].g[i]) begin
                    ext_enable = RVA23_ENABLE;
                    ext_enable[15 - i] = 1'b0;
                    #1;
                    if (!decode_bundle[0].is_illegal ||
                        (decode_bundle[0].alu_op != ALU_ILL) ||
                        is_vector[0]) begin
                        $display("FAIL [%s] legal with enable %0d clear", nm,
                                 i);
                        fail_count++;
                    end else begin
                        pass_count++;
                    end
                end
            end
        end
        ext_enable = RVA23_ENABLE;
        @(posedge clk);
    end

    // -----------------------------------------------------------------------
    // T78 (BP-124): the representation's layout. alu_op_t is 8 bits;
    //   values 0 to 106 keep theirs, ALU_ILL is 63, ALU_CSRRW, ALU_FLOAD
    //   and ALU_FSTORE (renamed) keep 49, 56 and 57, and the 79
    //   operations of DCD-22 are 107 to 185 in its order. The Zvbb
    //   classes are 189 to 198 in DCD-33's order. decode_pkt_t gains
    //   fp_fmt, fp_src_fmt, rd_is_fp, rs1_is_fp, rs2_is_fp, is_hlsv and
    //   is_hlvx, appended after is_illegal in that order, so is_hlvx is
    //   the packet's bit 0 and is_illegal bit 9. The expected values are
    //   DCD-22's list and DCD-33's, written here.
    //   BP-125 (TD#148, DCD-16): ifu_pd_pkt_t holds the DCD-16 fields and
    //   no is_vsetvl or needs_vtype: its width is the sum of those
    //   fields' widths, and is_ret, the last of them, is bit 0.
    // -----------------------------------------------------------------------
    begin
        decode_pkt_t lp;
        ifu_pd_pkt_t pp;
        ck78("$bits(ifu_pd_pkt_t)", $bits(ifu_pd_pkt_t),
             1 + 32 + VA_WIDTH + FTQ_PD_POS_BITS + FTQ_IDX_BITS +
             $bits(ifu_fault_e) + VA_WIDTH + FAULT_GPA_WIDTH + 2 + 1 + 2 +
             1 + 1);
        pp        = '0;
        pp.is_ret = 1'b1;
        ck78("ifu_pd_pkt_t is_ret is bit 0", int'(pp[7:0]), 1);
        ck78("$bits(alu_op_t)", $bits(alu_op_t), 8);
        ck78("ALU_ADD", int'(ALU_ADD), 0);
        ck78("ALU_CSRRW", int'(ALU_CSRRW), 49);
        ck78("ALU_FLOAD", int'(ALU_FLOAD), 56);
        ck78("ALU_FSTORE", int'(ALU_FSTORE), 57);
        ck78("ALU_FMADD", int'(ALU_FMADD), 58);
        ck78("ALU_ILL", int'(ALU_ILL), 63);
        ck78("ALU_MOP", int'(ALU_MOP), 106);
        ck78("ALU_VEC", int'(ALU_VEC), 107);
        ck78("ALU_FMSUB", int'(ALU_FMSUB), 108);
        ck78("ALU_FNMSUB", int'(ALU_FNMSUB), 109);
        ck78("ALU_FNMADD", int'(ALU_FNMADD), 110);
        ck78("ALU_FADD", int'(ALU_FADD), 111);
        ck78("ALU_FSUB", int'(ALU_FSUB), 112);
        ck78("ALU_FMUL", int'(ALU_FMUL), 113);
        ck78("ALU_FDIV", int'(ALU_FDIV), 114);
        ck78("ALU_FSQRT", int'(ALU_FSQRT), 115);
        ck78("ALU_FSGNJ", int'(ALU_FSGNJ), 116);
        ck78("ALU_FSGNJN", int'(ALU_FSGNJN), 117);
        ck78("ALU_FSGNJX", int'(ALU_FSGNJX), 118);
        ck78("ALU_FMIN", int'(ALU_FMIN), 119);
        ck78("ALU_FMAX", int'(ALU_FMAX), 120);
        ck78("ALU_FCVT_W", int'(ALU_FCVT_W), 121);
        ck78("ALU_FCVT_WU", int'(ALU_FCVT_WU), 122);
        ck78("ALU_FCVT_L", int'(ALU_FCVT_L), 123);
        ck78("ALU_FCVT_LU", int'(ALU_FCVT_LU), 124);
        ck78("ALU_FCVT_FW", int'(ALU_FCVT_FW), 125);
        ck78("ALU_FCVT_FWU", int'(ALU_FCVT_FWU), 126);
        ck78("ALU_FCVT_FL", int'(ALU_FCVT_FL), 127);
        ck78("ALU_FCVT_FLU", int'(ALU_FCVT_FLU), 128);
        ck78("ALU_FCVT_FF", int'(ALU_FCVT_FF), 129);
        ck78("ALU_FMV_XF", int'(ALU_FMV_XF), 130);
        ck78("ALU_FMV_FX", int'(ALU_FMV_FX), 131);
        ck78("ALU_FEQ", int'(ALU_FEQ), 132);
        ck78("ALU_FLT", int'(ALU_FLT), 133);
        ck78("ALU_FLE", int'(ALU_FLE), 134);
        ck78("ALU_FCLASS", int'(ALU_FCLASS), 135);
        ck78("ALU_FLI", int'(ALU_FLI), 136);
        ck78("ALU_FMINM", int'(ALU_FMINM), 137);
        ck78("ALU_FMAXM", int'(ALU_FMAXM), 138);
        ck78("ALU_FROUND", int'(ALU_FROUND), 139);
        ck78("ALU_FROUNDNX", int'(ALU_FROUNDNX), 140);
        ck78("ALU_FCVTMOD_W_D", int'(ALU_FCVTMOD_W_D), 141);
        ck78("ALU_FLEQ", int'(ALU_FLEQ), 142);
        ck78("ALU_FLTQ", int'(ALU_FLTQ), 143);
        ck78("ALU_LR_W", int'(ALU_LR_W), 144);
        ck78("ALU_LR_D", int'(ALU_LR_D), 145);
        ck78("ALU_SC_W", int'(ALU_SC_W), 146);
        ck78("ALU_SC_D", int'(ALU_SC_D), 147);
        ck78("ALU_AMOSWAP_W", int'(ALU_AMOSWAP_W), 148);
        ck78("ALU_AMOSWAP_D", int'(ALU_AMOSWAP_D), 149);
        ck78("ALU_AMOADD_W", int'(ALU_AMOADD_W), 150);
        ck78("ALU_AMOADD_D", int'(ALU_AMOADD_D), 151);
        ck78("ALU_AMOXOR_W", int'(ALU_AMOXOR_W), 152);
        ck78("ALU_AMOXOR_D", int'(ALU_AMOXOR_D), 153);
        ck78("ALU_AMOAND_W", int'(ALU_AMOAND_W), 154);
        ck78("ALU_AMOAND_D", int'(ALU_AMOAND_D), 155);
        ck78("ALU_AMOOR_W", int'(ALU_AMOOR_W), 156);
        ck78("ALU_AMOOR_D", int'(ALU_AMOOR_D), 157);
        ck78("ALU_AMOMIN_W", int'(ALU_AMOMIN_W), 158);
        ck78("ALU_AMOMIN_D", int'(ALU_AMOMIN_D), 159);
        ck78("ALU_AMOMAX_W", int'(ALU_AMOMAX_W), 160);
        ck78("ALU_AMOMAX_D", int'(ALU_AMOMAX_D), 161);
        ck78("ALU_AMOMINU_W", int'(ALU_AMOMINU_W), 162);
        ck78("ALU_AMOMINU_D", int'(ALU_AMOMINU_D), 163);
        ck78("ALU_AMOMAXU_W", int'(ALU_AMOMAXU_W), 164);
        ck78("ALU_AMOMAXU_D", int'(ALU_AMOMAXU_D), 165);
        ck78("ALU_FENCE_I", int'(ALU_FENCE_I), 166);
        ck78("ALU_CBO_INVAL", int'(ALU_CBO_INVAL), 167);
        ck78("ALU_CBO_CLEAN", int'(ALU_CBO_CLEAN), 168);
        ck78("ALU_CBO_FLUSH", int'(ALU_CBO_FLUSH), 169);
        ck78("ALU_CBO_ZERO", int'(ALU_CBO_ZERO), 170);
        ck78("ALU_SFENCE_VMA", int'(ALU_SFENCE_VMA), 171);
        ck78("ALU_SINVAL_VMA", int'(ALU_SINVAL_VMA), 172);
        ck78("ALU_SFENCE_W_INVAL", int'(ALU_SFENCE_W_INVAL), 173);
        ck78("ALU_SFENCE_INVAL_IR", int'(ALU_SFENCE_INVAL_IR), 174);
        ck78("ALU_HFENCE_VVMA", int'(ALU_HFENCE_VVMA), 175);
        ck78("ALU_HFENCE_GVMA", int'(ALU_HFENCE_GVMA), 176);
        ck78("ALU_HINVAL_VVMA", int'(ALU_HINVAL_VVMA), 177);
        ck78("ALU_HINVAL_GVMA", int'(ALU_HINVAL_GVMA), 178);
        ck78("ALU_WRS_NTO", int'(ALU_WRS_NTO), 179);
        ck78("ALU_WRS_STO", int'(ALU_WRS_STO), 180);
        ck78("ALU_CSRRS", int'(ALU_CSRRS), 181);
        ck78("ALU_CSRRC", int'(ALU_CSRRC), 182);
        ck78("ALU_CSRRWI", int'(ALU_CSRRWI), 183);
        ck78("ALU_CSRRSI", int'(ALU_CSRRSI), 184);
        ck78("ALU_CSRRCI", int'(ALU_CSRRCI), 185);
        ck78("VOP_VANDN", int'(VOP_VANDN), 189);
        ck78("VOP_VBREV", int'(VOP_VBREV), 190);
        ck78("VOP_VBREV8", int'(VOP_VBREV8), 191);
        ck78("VOP_VREV8", int'(VOP_VREV8), 192);
        ck78("VOP_VCLZ", int'(VOP_VCLZ), 193);
        ck78("VOP_VCTZ", int'(VOP_VCTZ), 194);
        ck78("VOP_VCPOP_V", int'(VOP_VCPOP_V), 195);
        ck78("VOP_VROL", int'(VOP_VROL), 196);
        ck78("VOP_VROR", int'(VOP_VROR), 197);
        ck78("VOP_VWSLL", int'(VOP_VWSLL), 198);
        // The appended fields, LSB up: is_hlvx 0, is_hlsv 1, rs2_is_fp 2,
        // rs1_is_fp 3, rd_is_fp 4, fp_src_fmt 6:5, fp_fmt 8:7, and
        // is_illegal 9 before them.
        lp = '0;
        lp.is_hlvx  = 1'b1;
        ck78("is_hlvx at 0", int'(lp[8:0]), 1);
        lp = '0;
        lp.is_hlsv  = 1'b1;
        ck78("is_hlsv at 1", int'(lp[8:0]), 2);
        lp = '0;
        lp.rs2_is_fp = 1'b1;
        ck78("rs2_is_fp at 2", int'(lp[8:0]), 4);
        lp = '0;
        lp.rs1_is_fp = 1'b1;
        ck78("rs1_is_fp at 3", int'(lp[8:0]), 8);
        lp = '0;
        lp.rd_is_fp  = 1'b1;
        ck78("rd_is_fp at 4", int'(lp[8:0]), 16);
        lp = '0;
        lp.fp_src_fmt = 2'b11;
        ck78("fp_src_fmt 6:5", int'(lp[8:0]), 96);
        lp = '0;
        lp.fp_fmt   = 2'b11;
        ck78("fp_fmt 8:7", int'(lp[8:0]), 384);
        lp = '0;
        lp.is_illegal = 1'b1;
        ck78("is_illegal at 9", int'(lp[9:0]), 512);
    end

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    $display("");
    $display("====================================================");
    $display("instr_decoder: PASS=%0d  FAIL=%0d", pass_count, fail_count);
    $display("====================================================");
    // TOOLS-006: a failing run must exit non-zero. $finish exits 0, so
    // the failure exit is $fatal(1), in a branch exclusive of $finish.
    if (fail_count != 0) begin
        $display("STATUS: FAIL");
        $fatal(1, "tb_instr_decoder: %0d checks failed", fail_count);
    end else begin
        $display("STATUS: PASS");
        $finish;
    end
end

endmodule

`default_nettype wire
