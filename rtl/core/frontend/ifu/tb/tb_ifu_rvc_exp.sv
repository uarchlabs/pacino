// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ifu_rvc_exp (BP-116).
//
// EVERY 16-BIT ENCODING, legal and reserved, is checked at all
// seventeen positions against a reference the RTL does not share:
// decode's rvc_expander.sv, instantiated here and nowhere in RTL
// (BP-116 Binding Decisions). 32-bit encodings are checked to pass
// through unchanged, position 16 with its missing upper half zero.
//
// THE REFERENCE IS WRONG IN SIX PLACES, each checked against the
// compressed-instruction chapter and listed in the BP-116 Results
// Capture. For those encoding classes this file computes the
// expected word itself from the specification's field tables (the
// spec_* functions below); everywhere else the reference decides.
// The classes are recognised from the encoding, not from the RTL's
// output, so a DUT error inside a class still fails:
//
//   R1 C.BEQZ / C.BNEZ: imm[11:9] driven 0, not the sign bit
//   R2 C.LUI nzimm = -1: called reserved, it is lui rd, 0xfffff
//   R3 C.SLLI rd = x0 or shamt = 0: HINTs, called reserved
//   R4 c.mul: expanded to MULW (OP-32), it is MUL (OP)
//   R5 C.MOP.n (Zcmop): called reserved, expanded to the NOP here
//   R6 C.FSD, C.SD, C.FSDSP, C.SDSP: the doubleword offset is split
//      across the S-type immediate fields at the wrong bit
//
// THE RESERVED CONVENTION is the IFU's: {16'h0000, c}. The reference
// returns 0 for a reserved code point; where it does and the class
// is not one of R1 to R5, the expected word is {16'h0000, c}.
//
// GOLDEN VECTORS. A handful of encodings with their 32-bit forms
// worked by hand from the field tables, one per correction class and
// a few ordinary ones, so the correction functions are themselves
// checked against a third source.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  localparam int NPOS  = FTQ_PD_WIDTH + 1;   // 17
  localparam int RSLOT = decode_pkg::SLOTS;
  localparam int RMASK = decode_pkg::MASK_BITS;

  logic [15:0] hw   [0:FTQ_PD_WIDTH];
  logic [31:0] expv [0:FTQ_PD_WIDTH];
  logic        rvc  [0:FTQ_PD_WIDTH];

  ifu_rvc_exp dut (.hw(hw), .exp(expv), .rvc(rvc));

  // The reference, slot 0 only.
  logic [RSLOT-1:0][31:0]    ref_in;
  logic [RSLOT*RMASK-1:0]    ref_mask;
  logic [RSLOT-1:0][31:0]    ref_out;
  logic [RSLOT-1:0]          ref_vld;

  rvc_expander u_ref (
    .fetch_bundle (ref_in),
    .fetch_mask   (ref_mask),
    .exp_bundle   (ref_out),
    .exp_valid    (ref_vld)
  );

  int pass_cnt;
  int fail_cnt;
  int n_ref;       // decided by the reference
  int n_rsv;       // reference reserved -> {16'h0, c}
  int n_fix [1:6]; // decided by spec_* correction class Rn

  task automatic chk(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: %s", nm);
    end
  endtask

  // -----------------------------------------------------------------
  // Specification field tables for the five correction classes.
  // -----------------------------------------------------------------
  function automatic logic [31:0] spec_b(input logic [15:0] c);
    // offset[8|4:3] = c[12|11:10], offset[7:6|2:1|5] = c[6:5|4:3|2]
    logic [12:0] o;
    o = {{5{c[12]}}, c[6], c[5], c[2], c[11], c[10], c[4], c[3], 1'b0};
    return {o[12], o[10:5], 5'd0, {2'b01, c[9:7]},
            (c[13] ? 3'b001 : 3'b000), o[4:1], o[11], 7'b1100011};
  endfunction

  function automatic logic [31:0] spec_lui(input logic [15:0] c);
    return {{15{c[12]}}, c[6:2], c[11:7], 7'b0110111};
  endfunction

  function automatic logic [31:0] spec_slli(input logic [15:0] c);
    return {6'b000000, c[12], c[6:2], c[11:7], 3'b001, c[11:7],
            7'b0010011};
  endfunction

  function automatic logic [31:0] spec_mul(input logic [15:0] c);
    return {7'b0000001, {2'b01, c[4:2]}, {2'b01, c[9:7]}, 3'b000,
            {2'b01, c[9:7]}, 7'b0110011};
  endfunction

  function automatic logic [31:0] spec_sd(input logic [15:0] c);
    // CS form, quadrant 0: offset[5:3|7:6] = c[12:10|6:5], rs2' rs1'.
    // CSS form, quadrant 2: offset[5:3|8:6] = c[12:10|9:7], rs2, x2.
    logic [11:0] im;
    logic [4:0]  r2;
    logic [4:0]  r1;
    if (c[1:0] == 2'b00) begin
      im = {4'b0000, c[6:5], c[12:10], 3'b000};
      r2 = {2'b01, c[4:2]};
      r1 = {2'b01, c[9:7]};
    end else begin
      im = {3'b000, c[9:7], c[12:10], 3'b000};
      r2 = c[6:2];
      r1 = 5'd2;
    end
    return {im[11:5], r2, r1, 3'b011, im[4:0],
            (c[14] ? 7'b0100011 : 7'b0100111)};
  endfunction

  // Which correction class an encoding is in, 0 for none.
  function automatic int fix_class(input logic [15:0] c);
    logic q1;
    logic q2;
    q1 = (c[1:0] == 2'b01);
    q2 = (c[1:0] == 2'b10);
    if (q1 && (c[15:14] == 2'b11))                       return 1;
    if (q1 && (c[15:13] == 3'b011) && (c[11:7] != 5'd2) &&
        ({c[12], c[6:2]} == 6'b111111))                  return 2;
    if (q2 && (c[15:13] == 3'b000) &&
        ((c[11:7] == 5'd0) || ({c[12], c[6:2]} == 6'd0))) return 3;
    if (q1 && (c[15:10] == 6'b100111) && (c[6:5] == 2'b10)) return 4;
    if (q1 && (c[15:13] == 3'b011) && (c[11:7] != 5'd2) &&
        ({c[12], c[6:2]} == 6'd0) && c[7] && !c[11])     return 5;
    if ((c[1:0] == 2'b00 || q2) && c[15] && c[13])      return 6;
    return 0;
  endfunction

  function automatic logic [31:0] spec_fix(input int k,
                                           input logic [15:0] c);
    case (k)
      1:       return spec_b(c);
      2:       return spec_lui(c);
      3:       return spec_slli(c);
      4:       return spec_mul(c);
      6:       return spec_sd(c);
      default: return 32'h0000_0013;   // 5, C.MOP.n
    endcase
  endfunction

  // -----------------------------------------------------------------
  // Golden vectors, worked by hand.
  // -----------------------------------------------------------------
  typedef struct packed {
    logic [15:0] c;
    logic [31:0] e;
  } gold_t;

  localparam int NGOLD = 18;
  gold_t gold [0:NGOLD-1];

  initial begin
    gold[0]  = '{16'hDC7D, 32'hFE04_0FE3};  // c.beqz s0,-2    R1
    gold[1]  = '{16'hFC7D, 32'hFE04_1FE3};  // c.bnez s0,-2    R1
    gold[2]  = '{16'h757D, 32'hFFFF_F537};  // c.lui a0,0xfffff R2
    gold[3]  = '{16'h0006, 32'h0010_1013};  // c.slli x0,1     R3
    gold[4]  = '{16'h9C45, 32'h0294_0433};  // c.mul s0,s1     R4
    gold[5]  = '{16'h6081, 32'h0000_0013};  // c.mop.1         R5
    gold[6]  = '{16'hBFFD, 32'hFFFF_F06F};  // c.j -2
    gold[7]  = '{16'hA001, 32'h0000_006F};  // c.j 0
    gold[8]  = '{16'h0001, 32'h0000_0013};  // c.nop
    gold[9]  = '{16'h0000, 32'h0000_0000};  // defined illegal
    gold[10] = '{16'h9002, 32'h0010_0073};  // c.ebreak
    gold[11] = '{16'h8082, 32'h0000_8067};  // c.jr ra (ret)
    gold[12] = '{16'h9082, 32'h0000_80E7};  // c.jalr ra
    gold[13] = '{16'h4501, 32'h0000_0513};  // c.li a0,0
    gold[14] = '{16'hE406, 32'h0011_3423};  // c.sdsp ra,8(sp) R6
    gold[15] = '{16'hE404, 32'h0094_3423};  // c.sd s1,8(s0)   R6
    gold[16] = '{16'hA406, 32'h0011_3427};  // c.fsdsp f1,8(sp) R6
    gold[17] = '{16'h1141, 32'hFF01_0113};  // c.addi sp,-16
  end

  logic [31:0] e;
  int          k;

  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    n_ref    = 0;
    n_rsv    = 0;
    for (int i = 1; i <= 6; i++) n_fix[i] = 0;
    ref_in   = '0;
    ref_mask = '0;
    ref_mask[1:0] = 2'b11;          // slot 0 valid, slot 0 is RVC
    for (int i = 0; i < NPOS; i++) hw[i] = '0;
    #1;

    // ---- golden vectors -------------------------------------------
    for (int g = 0; g < NGOLD; g++) begin
      for (int i = 0; i < NPOS; i++) hw[i] = gold[g].c;
      #1;
      chk($sformatf("G%0d %04h -> %08h, got %08h", g, gold[g].c,
                    gold[g].e, expv[3]), expv[3] == gold[g].e);
      k = fix_class(gold[g].c);
      if (k != 0) begin
        chk($sformatf("G%0d spec_fix agrees with the hand value", g),
            spec_fix(k, gold[g].c) == gold[g].e);
      end
    end

    // ---- every 16-bit encoding, all seventeen positions -----------
    for (int v = 0; v < 65536; v++) begin
      if (v[1:0] != 2'b11) begin
        for (int i = 0; i < NPOS; i++) hw[i] = v[15:0];
        ref_in[0] = {16'h0000, v[15:0]};
        #1;
        k = fix_class(v[15:0]);
        if (k != 0) begin
          e = spec_fix(k, v[15:0]);
          n_fix[k]++;
        end else if (ref_out[0] == 32'h0) begin
          e = {16'h0000, v[15:0]};
          n_rsv++;
        end else begin
          e = ref_out[0];
          n_ref++;
        end
        for (int i = 0; i < NPOS; i++) begin
          chk($sformatf("C %04h pos %0d: got %08h exp %08h", v[15:0], i,
                        expv[i], e), (expv[i] == e) && rvc[i]);
        end
      end
    end

    // ---- 32-bit encodings pass through ----------------------------
    // Every upper half against four low halves; position i reads
    // hw[i+1] as its upper half, so the array alternates low, high.
    for (int u = 0; u < 65536; u++) begin
      for (int lo = 0; lo < 4; lo++) begin
        for (int i = 0; i < NPOS; i++) begin
          hw[i] = (i % 2 == 0) ? (16'h0003 | 16'(lo * 16'h1554))
                               : u[15:0];
        end
        #1;
        for (int i = 0; i < NPOS; i += 2) begin
          if (i < NPOS - 1) begin
            chk($sformatf("P %04h_%04h pos %0d", u[15:0], hw[i], i),
                (expv[i] == {hw[i+1], hw[i]}) && !rvc[i]);
          end else begin
            chk($sformatf("P pos 16 upper zero, %04h", hw[i]),
                (expv[i] == {16'h0000, hw[i]}) && !rvc[i]);
          end
        end
      end
    end

    $display("tb_ifu_rvc_exp: decided by reference %0d, reserved %0d",
             n_ref, n_rsv);
    $display("tb_ifu_rvc_exp: corrections R1 %0d R2 %0d R3 %0d R4 %0d",
             n_fix[1], n_fix[2], n_fix[3], n_fix[4]);
    $display("tb_ifu_rvc_exp: corrections R5 %0d R6 %0d",
             n_fix[5], n_fix[6]);
    $display("tb_ifu_rvc_exp: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ifu_rvc_exp: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

endmodule : tb
