// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ifu_rvc_exp (BP-116; reference removed BP-119).
//
// EVERY 16-BIT ENCODING, legal and reserved, is checked at all
// seventeen positions against tb/ifu_rvc_exp_oracle.hex. 32-bit
// encodings are checked to pass through unchanged, position 16 with
// its missing upper half zero.
//
// THE ORACLE (BP-117). tb/ifu_rvc_exp_oracle.hex holds an expected
// word for every 16-bit encoding produced by LLVM
// (gen_ifu_rvc_exp_oracle.py): its disassembler expands the encoding
// through its own compress-pattern table and its assembler re-encodes
// the expansion with C off. The file's class field says which
// encodings LLVM decides and which the spec decides; see the
// generator's header. The path is +oracle=<file>, default
// tb/ifu_rvc_exp_oracle.hex.
//
// THE DECODE REFERENCE IS GONE (BP-119, TD#143). Until BP-119 this
// file also instantiated decode's rvc_expander.sv, with six spec_*
// corrections for the places it was wrong, and checked the DUT
// against that at every encoding and position, and that reference
// against the oracle. The oracle has an entry for each of the same
// 49152 encodings and is checked at the same seventeen positions,
// and the last run with the reference (BP-119, pre-edit) had it
// agree with the oracle on all of them, so the comparison added no
// encoding the oracle does not cover. The rvc flag the old loop also
// checked is checked here at every position.
// rvc_expander.sv is deleted.
//
// THE RESERVED CONVENTION is the IFU's: {16'h0000, c}. The oracle
// carries it for every reserved code point (its class 2).
//
// GOLDEN VECTORS. A handful of encodings with their 32-bit forms
// worked by hand from the field tables, one per class the old
// reference got wrong and a few ordinary ones, checked against the
// DUT as a third source.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  localparam int NPOS  = FTQ_PD_WIDTH + 1;   // 17
  logic [15:0] hw   [0:FTQ_PD_WIDTH];
  logic [31:0] expv [0:FTQ_PD_WIDTH];
  logic        rvc  [0:FTQ_PD_WIDTH];

  ifu_rvc_exp dut (.hw(hw), .exp(expv), .rvc(rvc));

  int pass_cnt;
  int fail_cnt;

  // The oracle: {class[7:0], expected[31:0]} per encoding. Class
  // numbers are the generator's.
  localparam int OC_NA      = 0;
  localparam int OC_LLVM    = 1;
  localparam int OC_RSV     = 2;
  localparam int OC_ILL0    = 3;
  localparam int OC_HINT    = 4;
  localparam int OC_MOP     = 5;
  localparam int OC_RSVLLVM = 6;
  localparam int OC_MVALT   = 7;
  localparam int OC_N       = 8;

  logic [39:0] orc [0:65535];
  string       orc_file;
  int          o_match [0:OC_N-1];  // DUT equals the oracle word
  int          o_mis   [0:OC_N-1];  // DUT differs from it
  int          oc;
  logic [31:0] ow;
  logic        dut_ok;

  task automatic chk(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: %s", nm);
    end
  endtask

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
    gold[0]  = '{16'hDC7D, 32'hFE04_0FE3};  // c.beqz s0,-2
    gold[1]  = '{16'hFC7D, 32'hFE04_1FE3};  // c.bnez s0,-2
    gold[2]  = '{16'h757D, 32'hFFFF_F537};  // c.lui a0,0xfffff
    gold[3]  = '{16'h0006, 32'h0010_1013};  // c.slli x0,1 (HINT)
    gold[4]  = '{16'h9C45, 32'h0294_0433};  // c.mul s0,s1
    gold[5]  = '{16'h6081, 32'h0000_0013};  // c.mop.1
    gold[6]  = '{16'hBFFD, 32'hFFFF_F06F};  // c.j -2
    gold[7]  = '{16'hA001, 32'h0000_006F};  // c.j 0
    gold[8]  = '{16'h0001, 32'h0000_0013};  // c.nop
    gold[9]  = '{16'h0000, 32'h0000_0000};  // defined illegal
    gold[10] = '{16'h9002, 32'h0010_0073};  // c.ebreak
    gold[11] = '{16'h8082, 32'h0000_8067};  // c.jr ra (ret)
    gold[12] = '{16'h9082, 32'h0000_80E7};  // c.jalr ra
    gold[13] = '{16'h4501, 32'h0000_0513};  // c.li a0,0
    gold[14] = '{16'hE406, 32'h0011_3423};  // c.sdsp ra,8(sp)
    gold[15] = '{16'hE404, 32'h0094_3423};  // c.sd s1,8(s0)
    gold[16] = '{16'hA406, 32'h0011_3427};  // c.fsdsp f1,8(sp)
    gold[17] = '{16'h1141, 32'hFF01_0113};  // c.addi sp,-16
  end

  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    for (int i = 0; i < NPOS; i++) hw[i] = '0;
    for (int i = 0; i < OC_N; i++) begin
      o_match[i] = 0;
      o_mis[i]   = 0;
    end
    if (!$value$plusargs("oracle=%s", orc_file)) begin
      orc_file = "tb/ifu_rvc_exp_oracle.hex";
    end
    for (int v = 0; v < 65536; v++) orc[v] = 'x;
    $readmemh(orc_file, orc);
    #1;

    // ---- golden vectors -------------------------------------------
    for (int g = 0; g < NGOLD; g++) begin
      for (int i = 0; i < NPOS; i++) hw[i] = gold[g].c;
      #1;
      chk($sformatf("G%0d %04h -> %08h, got %08h", g, gold[g].c,
                    gold[g].e, expv[3]), expv[3] == gold[g].e);
    end

    // ---- every 16-bit encoding, all seventeen positions -----------
    for (int v = 0; v < 65536; v++) begin
      if (v[1:0] != 2'b11) begin
        for (int i = 0; i < NPOS; i++) hw[i] = v[15:0];
        #1;

        // The oracle. A missing or short file leaves X here, and an X
        // class is not a known class, so it fails rather than skips.
        oc = int'(orc[v][39:32]);
        ow = orc[v][31:0];
        chk($sformatf("O %04h: oracle entry present", v[15:0]),
            !$isunknown(orc[v]) && (oc > OC_NA) && (oc < OC_N));
        if (!$isunknown(orc[v]) && (oc > OC_NA) && (oc < OC_N)) begin
          dut_ok = 1'b1;
          for (int i = 0; i < NPOS; i++) begin
            if ((expv[i] !== ow) || !rvc[i]) dut_ok = 1'b0;
          end
          chk($sformatf("O %04h class %0d: DUT %08h oracle %08h",
                        v[15:0], oc, expv[0], ow), dut_ok);
          if (dut_ok) o_match[oc]++;
          else        o_mis[oc]++;
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

    // The oracle summary, by class. LLVM is the comparison against an
    // independent source; the rest are decided by the spec and named
    // in the generator's header.
    for (int i = OC_LLVM; i < OC_N; i++) begin
      $display("tb_ifu_rvc_exp: oracle class %0d match %0d mismatch %0d",
               i, o_match[i], o_mis[i]);
    end
    $display("tb_ifu_rvc_exp: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ifu_rvc_exp: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

endmodule : tb
