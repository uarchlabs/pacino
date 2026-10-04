// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ifu_predecode (BP-116), dcd_decisions.md.
//
// The predecoder is driven directly: this file lays instructions out
// as raw halfwords and as the expanded words the expander would give
// them, so a fault in the expander cannot hide or cause a predecode
// result. Every expected value is this file's: classes and call/ret
// from the test's own table, targets from the immediate the test
// encoded plus the position's PC, the start mask from a sequential
// walk (the RTL's is a parallel prefix).
//
//   A  every control-flow class of DCD-7, and the non-CFI cases next
//      to each (reserved BRANCH funct3, JALR funct3 != 0)
//   B  DCD-11: JAL with rd in {x0, x1, x5, x2}; JALR over rd x rs1 in
//      {x0, x1, x5, x6}^2, including the pop-then-push pair
//   C  DCD-9 targets: branch +2, -2, +4094, -4096; JAL +2, -2,
//      +1048574, -1048576; a target that wraps the VA_WIDTH space;
//      compressed forms through their expansions; JALR target zero
//   D  DCD-4 to DCD-6 starts: an unaligned block start, mixed
//      lengths, all 16-bit, all 32-bit, a 32-bit start at position
//      15 taking position 16, and first_tail
//   E  is_vsetvl and needs_vtype
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  localparam int NPD  = FTQ_PD_WIDTH;
  localparam int NPOS = FTQ_PD_WIDTH + 1;

  logic [15:0]         hw   [0:FTQ_PD_WIDTH];
  logic [31:0]         expw [0:FTQ_PD_WIDTH-1];
  logic [VA_WIDTH-1:0] pc   [0:FTQ_PD_WIDTH-1];
  logic                first_tail;
  logic [NPD-1:0]      start;
  logic [NPD-1:0]      is_rvc;
  logic [1:0]          br_type [0:FTQ_PD_WIDTH-1];
  logic [NPD-1:0]      is_call;
  logic [NPD-1:0]      is_ret;
  logic [VA_WIDTH-1:0] target  [0:FTQ_PD_WIDTH-1];
  logic [NPD-1:0]      is_vsetvl;
  logic [NPD-1:0]      needs_vtype;

  ifu_predecode dut (
    .hw (hw), .exp (expw), .pc (pc), .first_tail (first_tail),
    .start (start), .is_rvc (is_rvc), .br_type (br_type),
    .is_call (is_call), .is_ret (is_ret), .target (target),
    .is_vsetvl (is_vsetvl), .needs_vtype (needs_vtype)
  );

  int pass_cnt;
  int fail_cnt;

  task automatic chk(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: %s", nm);
    end
  endtask

  // -----------------------------------------------------------------
  // Encoders, from the base-ISA formats.
  // -----------------------------------------------------------------
  function automatic logic [31:0] enc_b(input logic [2:0] f3,
                                        input int imm);
    logic [12:0] o;
    o = 13'(imm);
    return {o[12], o[10:5], 5'd6, 5'd5, f3, o[4:1], o[11], 7'b1100011};
  endfunction

  function automatic logic [31:0] enc_jal(input logic [4:0] rd,
                                          input int imm);
    logic [20:0] o;
    o = 21'(imm);
    return {o[20], o[10:1], o[11], o[19:12], rd, 7'b1101111};
  endfunction

  function automatic logic [31:0] enc_jalr(input logic [4:0] rd,
                                           input logic [4:0] rs1,
                                           input logic [2:0] f3);
    return {12'h000, rs1, f3, rd, 7'b1100111};
  endfunction

  localparam logic [31:0] ADDI_X0 = 32'h0000_0013;
  localparam logic [31:0] LUI_A0  = 32'h1234_5537;

  // -----------------------------------------------------------------
  // Block layout. Positions are filled from 0; a 32-bit word takes
  // two halfwords. The expanded word at a 32-bit start is the word,
  // at a 16-bit start the expansion supplied, and at a tail position
  // an arbitrary value (it is not a start).
  // -----------------------------------------------------------------
  logic [VA_WIDTH-1:0] blk_pc;
  int                  fill;

  task automatic clear(input logic [VA_WIDTH-1:0] spc);
    blk_pc     = spc;
    fill       = 0;
    first_tail = 1'b0;
    for (int i = 0; i < NPOS; i++) hw[i] = 16'h0001;   // c.nop
    for (int i = 0; i < NPD; i++) begin
      expw[i] = ADDI_X0;
      pc[i]   = spc + VA_WIDTH'(2 * i);
    end
  endtask

  task automatic put32(input logic [31:0] w);
    hw[fill]   = w[15:0];
    hw[fill+1] = w[31:16];
    if (fill < NPD) expw[fill] = w;
    if (fill + 1 < NPD) expw[fill+1] = {w[15:0], w[31:16]};
    fill += 2;
  endtask

  task automatic put16(input logic [15:0] c, input logic [31:0] e);
    hw[fill] = c;
    if (fill < NPD) expw[fill] = e;
    fill += 1;
  endtask

  // The sequential walk the RTL must agree with (DCD-4, DCD-5).
  function automatic logic [NPD-1:0] walk(input logic ft);
    logic [NPD-1:0] m;
    int p;
    m = '0;
    p = ft ? 1 : 0;
    while (p < NPD) begin
      m[p] = 1'b1;
      p += (hw[p][1:0] == 2'b11) ? 2 : 1;
    end
    return m;
  endfunction

  task automatic settle();
    #1;
  endtask

  // -----------------------------------------------------------------
  // A. Classes.
  // -----------------------------------------------------------------
  task automatic group_a();
    logic [2:0] f3s [0:7];
    $display("-- A: classes --");
    for (int f = 0; f < 8; f++) f3s[f] = 3'(f);
    for (int f = 0; f < 8; f++) begin
      clear(VA_WIDTH'('h80001000));
      put32(enc_b(f3s[f], 8));
      settle();
      if ((f == 2) || (f == 3)) begin
        chk($sformatf("A BRANCH funct3 %0d is reserved: not a CFI", f),
            start[0] && (br_type[0] == 2'b00));
      end else begin
        chk($sformatf("A BRANCH funct3 %0d is a conditional", f),
            start[0] && (br_type[0] == 2'b01) && !is_rvc[0]);
      end
    end
    clear(VA_WIDTH'('h80001000));
    put32(enc_jal(5'd0, 16));
    put32(enc_jalr(5'd0, 5'd6, 3'b000));
    put32(enc_jalr(5'd0, 5'd6, 3'b001));
    put32(ADDI_X0);
    put32(LUI_A0);
    put16(16'hA001, 32'h0000_006F);              // c.j 0
    put16(16'hC011, enc_b(3'b000, 4) & 32'hFFF0_7FFF | 32'h0004_0000);
    put16(16'h8082, 32'h0000_8067);              // c.jr ra
    settle();
    chk("A JAL is 10",                start[0] && br_type[0] == 2'b10);
    chk("A JALR funct3 0 is 11",      start[2] && br_type[2] == 2'b11);
    chk("A JALR funct3 1 is not CFI", start[4] && br_type[4] == 2'b00);
    chk("A ADDI is not CFI",          start[6] && br_type[6] == 2'b00);
    chk("A LUI is not CFI",           start[8] && br_type[8] == 2'b00);
    chk("A C.J classifies by its expansion as JAL, is_rvc",
        start[10] && br_type[10] == 2'b10 && is_rvc[10]);
    chk("A C.BEQZ classifies as a conditional, is_rvc",
        start[11] && br_type[11] == 2'b01 && is_rvc[11]);
    chk("A C.JR ra classifies as JALR and is a return",
        start[12] && br_type[12] == 2'b11 && is_rvc[12] && is_ret[12]
        && !is_call[12]);
    chk("A no call/ret on a non-CFI",
        !is_call[6] && !is_ret[6] && !is_call[0] && !is_ret[0]);
  endtask

  // -----------------------------------------------------------------
  // B. DCD-11, call and return.
  // -----------------------------------------------------------------
  function automatic logic lnk(input logic [4:0] r);
    return (r == 5'd1) || (r == 5'd5);
  endfunction

  task automatic group_b();
    logic [4:0] regs [0:3];
    logic       ec;
    logic       er;
    $display("-- B: call and return --");
    regs[0] = 5'd0;
    regs[1] = 5'd1;
    regs[2] = 5'd5;
    regs[3] = 5'd6;
    // JAL: rd link pushes.
    for (int d = 0; d < 4; d++) begin
      clear(VA_WIDTH'('h80002000));
      put32(enc_jal(regs[d], 64));
      settle();
      chk($sformatf("B JAL rd x%0d: call %0d ret 0", regs[d], lnk(regs[d])),
          (is_call[0] == lnk(regs[d])) && !is_ret[0]);
    end
    // JAL rd = x2, not a link register.
    clear(VA_WIDTH'('h80002000));
    put32(enc_jal(5'd2, 64));
    settle();
    chk("B JAL rd x2 is not a call", !is_call[0] && !is_ret[0]);
    // JALR: the specification's table, written out.
    for (int d = 0; d < 4; d++) begin
      for (int s = 0; s < 4; s++) begin
        clear(VA_WIDTH'('h80002000));
        put32(enc_jalr(regs[d], regs[s], 3'b000));
        settle();
        if (!lnk(regs[d]) && !lnk(regs[s])) begin
          ec = 1'b0; er = 1'b0;
        end else if (!lnk(regs[d]) && lnk(regs[s])) begin
          ec = 1'b0; er = 1'b1;
        end else if (lnk(regs[d]) && !lnk(regs[s])) begin
          ec = 1'b1; er = 1'b0;
        end else if (regs[d] == regs[s]) begin
          ec = 1'b1; er = 1'b0;
        end else begin
          ec = 1'b1; er = 1'b1;                 // pop then push
        end
        chk($sformatf("B JALR rd x%0d rs1 x%0d: call %0d ret %0d",
                      regs[d], regs[s], ec, er),
            (is_call[0] == ec) && (is_ret[0] == er) &&
            (br_type[0] == 2'b11));
      end
    end
  endtask

  // -----------------------------------------------------------------
  // C. Targets.
  // -----------------------------------------------------------------
  task automatic tgt_case(input string nm, input logic [31:0] w,
                          input logic [VA_WIDTH-1:0] spc, input int at,
                          input logic [VA_WIDTH-1:0] exp_t);
    clear(spc);
    for (int i = 0; i < at; i++) put16(16'h0001, ADDI_X0);
    put32(w);
    settle();
    chk($sformatf("C %s: got %011h exp %011h", nm, target[at], exp_t),
        start[at] && (target[at] == exp_t));
  endtask

  task automatic group_c();
    logic [VA_WIDTH-1:0] b;
    logic [VA_WIDTH-1:0] top;
    $display("-- C: targets --");
    b   = VA_WIDTH'('h0_8000_4000);
    top = {VA_WIDTH{1'b1}} - VA_WIDTH'(1);      // last halfword
    tgt_case("BEQ +2",      enc_b(3'b000, 2),     b, 3,
             b + VA_WIDTH'(6) + VA_WIDTH'(2));
    tgt_case("BNE -2",      enc_b(3'b001, -2),    b, 3,
             b + VA_WIDTH'(6) - VA_WIDTH'(2));
    tgt_case("BLT +4094",   enc_b(3'b100, 4094),  b, 0,
             b + VA_WIDTH'(4094));
    tgt_case("BGE -4096",   enc_b(3'b101, -4096), b, 0,
             b - VA_WIDTH'(4096));
    tgt_case("JAL +2",      enc_jal(5'd0, 2),     b, 7,
             b + VA_WIDTH'(14) + VA_WIDTH'(2));
    tgt_case("JAL -2",      enc_jal(5'd1, -2),    b, 7,
             b + VA_WIDTH'(14) - VA_WIDTH'(2));
    tgt_case("JAL +1048574", enc_jal(5'd0, 1048574), b, 0,
             b + VA_WIDTH'(1048574));
    tgt_case("JAL -1048576", enc_jal(5'd0, -1048576), b, 0,
             b - VA_WIDTH'(1048576));
    tgt_case("BEQ wraps the VA space", enc_b(3'b000, 4), top, 0,
             VA_WIDTH'(2));
    tgt_case("JAL from position 14", enc_jal(5'd0, -1048576), b, 14,
             b + VA_WIDTH'(28) - VA_WIDTH'(1048576));

    // Compressed, through their expansions: C.J -2048 (offset all
    // ones in the sign) and C.BNEZ +254.
    clear(b);
    put16(16'hB001, enc_jal(5'd0, -2048));       // c.j -2048
    put16(16'hEC7D, enc_b(3'b001, 254) & 32'hFFF0_7FFF |
                    32'h0004_0000);              // c.bnez s0,254
    settle();
    chk("C C.J -2048 through its expansion",
        start[0] && is_rvc[0] && target[0] == b - VA_WIDTH'(2048));
    chk("C C.BNEZ +254 through its expansion",
        start[1] && is_rvc[1] && target[1] == b + VA_WIDTH'(2 + 254));

    clear(b);
    put32(enc_jalr(5'd1, 5'd6, 3'b000));
    settle();
    chk("C JALR target is driven zero", target[0] == '0);
  endtask

  // -----------------------------------------------------------------
  // D. Starts.
  // -----------------------------------------------------------------
  task automatic start_case(input string nm);
    logic [NPD-1:0] e;
    settle();
    e = walk(first_tail);
    chk($sformatf("D %s: got %04h exp %04h", nm, start, e), start == e);
  endtask

  task automatic group_d();
    logic [VA_WIDTH-1:0] ua;
    $display("-- D: starts --");
    ua = VA_WIDTH'('h0_8000_501A);   // unaligned: offset 26 in a line

    clear(ua);
    put32(ADDI_X0); put16(16'h0001, ADDI_X0); put32(LUI_A0);
    put16(16'h0001, ADDI_X0); put16(16'h0001, ADDI_X0);
    put32(ADDI_X0); put32(ADDI_X0); put16(16'h0001, ADDI_X0);
    put32(ADDI_X0); put16(16'h0001, ADDI_X0); put32(ADDI_X0);
    start_case("unaligned block, mixed lengths");
    chk("D the unaligned walk starts at position 0, not the line",
        start[0]);

    clear(ua);
    for (int i = 0; i < NPOS; i++) put16(16'h0001, ADDI_X0);
    start_case("all 16-bit");
    chk("D all 16-bit: every position is a start", start == '1);

    clear(ua);
    for (int i = 0; i < 8; i++) put32(ADDI_X0);
    put16(16'h0001, ADDI_X0);
    start_case("all 32-bit");
    chk("D all 32-bit: even positions only", start == 16'h5555);

    // A 32-bit start at position 15, its upper half in position 16.
    clear(ua);
    put16(16'h0001, ADDI_X0);
    for (int i = 0; i < 7; i++) put32(ADDI_X0);
    put32(enc_jal(5'd0, 32));
    start_case("32-bit start at position 15");
    chk("D position 15 is a 32-bit start taking position 16",
        start[15] && !is_rvc[15] && br_type[15] == 2'b10);

    // first_tail: position 0 is the tail of the previous block's last
    // instruction; the walk begins at position 1.
    clear(ua);
    first_tail = 1'b1;
    hw[0] = 16'hFFFF;                    // would read as a 32-bit start
    fill = 1;
    for (int i = 0; i < 5; i++) begin
      put32(ADDI_X0); put16(16'h0001, ADDI_X0);
    end
    start_case("first_tail");
    chk("D first_tail: position 0 is not a start", !start[0] && start[1]);

    // A tail that looks like a 32-bit start must not shift the walk.
    clear(ua);
    put32({16'hFFFF, 16'h0013});         // upper half low bits 11
    put16(16'h0001, ADDI_X0);
    start_case("tail with 11 in its low bits");
    chk("D a tail is never a start", start[0] && !start[1] && start[2]);
  endtask

  // -----------------------------------------------------------------
  // E. vtype marks.
  // -----------------------------------------------------------------
  task automatic group_e();
    $display("-- E: vtype marks --");
    clear(VA_WIDTH'('h80006000));
    put32(32'h0D00_7057);    // vsetvli x0, x0, e32
    put32(32'hC000_7057);    // vsetivli
    put32(32'h8000_7057);    // vsetvl
    put32(32'h0200_0057);    // vadd.vv v0, v0, v0
    put32(32'h0200_6007);    // vle32.v v0, (x0)
    put32(32'h0000_2007);    // flw f0, 0(x0)
    put32(32'h0000_3007);    // fld f0, 0(x0)
    put32(32'h0200_7027);    // vse64.v v0, (x0)
    settle();
    chk("E vsetvli is_vsetvl, not needs_vtype",
        is_vsetvl[0] && !needs_vtype[0]);
    chk("E vsetivli is_vsetvl",  is_vsetvl[2]);
    chk("E vsetvl is_vsetvl",    is_vsetvl[4]);
    chk("E vadd.vv needs_vtype", needs_vtype[6] && !is_vsetvl[6]);
    chk("E vle32.v needs_vtype", needs_vtype[8]);
    chk("E flw is neither",      !needs_vtype[10] && !is_vsetvl[10]);
    chk("E fld is neither",      !needs_vtype[12] && !is_vsetvl[12]);
    chk("E vse64.v needs_vtype", needs_vtype[14]);
  endtask

  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    group_a();
    group_b();
    group_c();
    group_d();
    group_e();
    $display("tb_ifu_predecode: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ifu_predecode: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

endmodule : tb
