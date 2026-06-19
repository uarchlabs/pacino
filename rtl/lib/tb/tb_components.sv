// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

// tb_components.sv
// Combined testbench for bw_ram, sat_alu, and dual_lm1.
// Module name is tb per project convention.
// Three named sub-blocks, one per DUT.
// Self-checking: PASS/FAIL printed per test case.

`default_nettype none

module tb;

  // ----------------------------------------------------------------
  // Shared clock (10 ns period, rising-edge active)
  // ----------------------------------------------------------------
  logic clk;
  initial clk = 1'b0;
  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  // ----------------------------------------------------------------
  // bw_ram DUT signals (ENTRIES=16, WIDTH=8, BANKS=2)
  // ----------------------------------------------------------------
  localparam int BWR_ENTRIES   = 16;
  localparam int BWR_WIDTH     = 8;
  localparam int BWR_BANKS     = 2;
  localparam int BWR_ADDR_BITS = $clog2(BWR_ENTRIES);  // 4
  localparam int BWR_BANK_BITS = $clog2(BWR_BANKS);    // 1

  logic [BWR_ADDR_BITS-1:0] bwram_addr;
  logic [BWR_BANK_BITS-1:0] bwram_bank_addr;
  logic                     bwram_wen_n;
  logic [BWR_WIDTH-1:0]     bwram_bweb_n;
  logic [BWR_WIDTH-1:0]     bwram_din;
  logic [BWR_WIDTH-1:0]     bwram_dout;

  bw_ram #(
    .ENTRIES (BWR_ENTRIES),
    .WIDTH   (BWR_WIDTH),
    .BANKS   (BWR_BANKS)
  ) u_bw_ram (
    .clk      (clk),
    .addr     (bwram_addr),
    .bank_addr(bwram_bank_addr),
    .wen_n    (bwram_wen_n),
    .bweb_n   (bwram_bweb_n),
    .din      (bwram_din),
    .dout     (bwram_dout)
  );

  // ----------------------------------------------------------------
  // sat_alu DUT signals (WIDTH=4)
  // ----------------------------------------------------------------
  localparam int ALU_WIDTH = 4;

  logic [ALU_WIDTH-1:0] alu_a;
  logic [ALU_WIDTH-1:0] alu_b;
  logic                 alu_sub;
  logic [ALU_WIDTH-1:0] alu_result;
  logic                 alu_sat;

  sat_alu #(.WIDTH(ALU_WIDTH)) u_sat_alu (
    .a     (alu_a),
    .b     (alu_b),
    .sub   (alu_sub),
    .result(alu_result),
    .sat   (alu_sat)
  );

  // ----------------------------------------------------------------
  // dual_lm1 DUT signals (WIDTH=8)
  // ----------------------------------------------------------------
  localparam int DLM_WIDTH    = 8;
  localparam int DLM_OUT_BITS = $clog2(DLM_WIDTH + 1);  // 4

  logic [DLM_WIDTH-1:0]    dlm_vec;
  logic [DLM_OUT_BITS-1:0] dlm_lm1;
  logic [DLM_OUT_BITS-1:0] dlm_lm2;

  dual_lm1 #(.WIDTH(DLM_WIDTH)) u_dual_lm1 (
    .vec(dlm_vec),
    .lm1(dlm_lm1),
    .lm2(dlm_lm2)
  );

  // ----------------------------------------------------------------
  // sram_init DUT A (4 entries, no delay, INIT_VAL=8'hA5)
  // ----------------------------------------------------------------
  localparam int   SI_A_ENTRIES = 4;
  localparam int   SI_A_ABITS   = 4;
  localparam int   SI_A_DWIDTH  = 8;
  localparam [7:0] SI_A_IVAL    = 8'hA5;
  localparam [7:0] SI_A_DELAY   = 8'h00;

  logic                      si_a_rstn;
  logic                      si_a_cs;
  logic                      si_a_wr;
  logic [SI_A_ABITS-1:0]     si_a_waddr;
  logic [SI_A_DWIDTH-1:0]    si_a_wdata;
  logic                      si_a_active;
  logic                      si_a_ready;

  sram_init #(
    .NUM_ENTRIES (SI_A_ENTRIES),
    .ADDR_BITS   (SI_A_ABITS),
    .DATA_WIDTH  (SI_A_DWIDTH),
    .INIT_VAL    (SI_A_IVAL),
    .START_DELAY (SI_A_DELAY)
  ) u_si_a (
    .clk    (clk),
    .rstn   (si_a_rstn),
    .cs     (si_a_cs),
    .wr     (si_a_wr),
    .waddr  (si_a_waddr),
    .wdata  (si_a_wdata),
    .active (si_a_active),
    .ready  (si_a_ready)
  );

  // ----------------------------------------------------------------
  // sram_init DUT B (4 entries, 3-cycle delay, INIT_VAL=8'hBB)
  // ----------------------------------------------------------------
  localparam int   SI_B_ENTRIES = 4;
  localparam int   SI_B_ABITS   = 4;
  localparam int   SI_B_DWIDTH  = 8;
  localparam [7:0] SI_B_IVAL    = 8'hBB;
  localparam [7:0] SI_B_DELAY   = 8'h03;

  logic                      si_b_rstn;
  logic                      si_b_cs;
  logic                      si_b_wr;
  logic [SI_B_ABITS-1:0]     si_b_waddr;
  logic [SI_B_DWIDTH-1:0]    si_b_wdata;
  logic                      si_b_active;
  logic                      si_b_ready;

  sram_init #(
    .NUM_ENTRIES (SI_B_ENTRIES),
    .ADDR_BITS   (SI_B_ABITS),
    .DATA_WIDTH  (SI_B_DWIDTH),
    .INIT_VAL    (SI_B_IVAL),
    .START_DELAY (SI_B_DELAY)
  ) u_si_b (
    .clk    (clk),
    .rstn   (si_b_rstn),
    .cs     (si_b_cs),
    .wr     (si_b_wr),
    .waddr  (si_b_waddr),
    .wdata  (si_b_wdata),
    .active (si_b_active),
    .ready  (si_b_ready)
  );

  // ----------------------------------------------------------------
  // Pass/fail counters
  // ----------------------------------------------------------------
  int bwr_pass,  bwr_total;
  int alu_pass,  alu_total;
  int dlm_pass,  dlm_total;
  int si_pass,   si_total;

  // Shared read buffers (module-level to avoid Verilator scoping)
  logic [BWR_WIDTH-1:0] bwr_rd;
  logic [BWR_WIDTH-1:0] bwr_rd_b0;
  logic [BWR_WIDTH-1:0] bwr_rd_b1;

  // ----------------------------------------------------------------
  // bw_ram helper tasks
  // ----------------------------------------------------------------

  // Write one cycle: sample inputs at posedge, then deassert wen_n.
  task automatic bwram_write(
    input logic [BWR_ADDR_BITS-1:0] w_addr,
    input logic [BWR_BANK_BITS-1:0] w_bank,
    input logic [BWR_WIDTH-1:0]     w_data,
    input logic [BWR_WIDTH-1:0]     w_bweb
  );
    bwram_addr      = w_addr;
    bwram_bank_addr = w_bank;
    bwram_wen_n     = 1'b0;
    bwram_bweb_n    = w_bweb;
    bwram_din       = w_data;
    @(posedge clk); #1;
    bwram_wen_n = 1'b1;
  endtask

  // Read one cycle: flop read address at posedge, capture dout after.
  task automatic bwram_read(
    input  logic [BWR_ADDR_BITS-1:0] r_addr,
    input  logic [BWR_BANK_BITS-1:0] r_bank,
    output logic [BWR_WIDTH-1:0]     r_data
  );
    bwram_addr      = r_addr;
    bwram_bank_addr = r_bank;
    bwram_wen_n     = 1'b1;
    @(posedge clk); #1;
    r_data = bwram_dout;
  endtask

  // ----------------------------------------------------------------
  // sat_alu helper task
  // ----------------------------------------------------------------
  task automatic alu_check(
    input logic [ALU_WIDTH-1:0] a_in,
    input logic [ALU_WIDTH-1:0] b_in,
    input logic                 sub_in,
    input logic [ALU_WIDTH-1:0] exp_res,
    input logic                 exp_sat,
    input string                tc_desc,
    input int                   tc_n
  );
    alu_a   = a_in;
    alu_b   = b_in;
    alu_sub = sub_in;
    #1;
    alu_total++;
    if (alu_result === exp_res && alu_sat === exp_sat) begin
      $display("PASS TC%0d sat_alu : %s", tc_n, tc_desc);
      alu_pass++;
    end else begin
      $display(
        "FAIL TC%0d sat_alu : expected r=%0h s=%0b got r=%0h s=%0b",
        tc_n, exp_res, exp_sat, alu_result, alu_sat);
    end
  endtask

  // ----------------------------------------------------------------
  // dual_lm1 helper task
  // ----------------------------------------------------------------
  task automatic dlm_check(
    input logic [DLM_WIDTH-1:0]    vec_in,
    input logic [DLM_OUT_BITS-1:0] exp_lm1,
    input logic [DLM_OUT_BITS-1:0] exp_lm2,
    input string                   tc_desc,
    input int                      tc_n
  );
    dlm_vec = vec_in;
    #1;
    dlm_total++;
    if (dlm_lm1 === exp_lm1 && dlm_lm2 === exp_lm2) begin
      $display("PASS TC%0d dual_lm1 : %s", tc_n, tc_desc);
      dlm_pass++;
    end else begin
      $display(
        "FAIL TC%0d dual_lm1 : expected %0d/%0d got %0d/%0d",
        tc_n, exp_lm1, exp_lm2, dlm_lm1, dlm_lm2);
    end
  endtask

  // ----------------------------------------------------------------
  // sram_init DUT A helper task
  // ----------------------------------------------------------------
  task automatic si_a_check(
    input logic                   exp_cs,
    input logic                   exp_wr,
    input logic [SI_A_ABITS-1:0]  exp_waddr,
    input logic [SI_A_DWIDTH-1:0] exp_wdata,
    input logic                   exp_active,
    input logic                   exp_ready,
    input string                  tc_desc,
    input int                     tc_n
  );
    si_total++;
    if (si_a_cs     === exp_cs     &&
        si_a_wr     === exp_wr     &&
        si_a_waddr  === exp_waddr  &&
        si_a_wdata  === exp_wdata  &&
        si_a_active === exp_active &&
        si_a_ready  === exp_ready) begin
      $display("PASS TC%0d sram_init : %s", tc_n, tc_desc);
      si_pass++;
    end else begin
      $display("FAIL TC%0d sram_init : %s", tc_n, tc_desc);
      $display(
        "  cs=%b wr=%b waddr=%h wdata=%h act=%b rdy=%b",
        si_a_cs, si_a_wr, si_a_waddr, si_a_wdata,
        si_a_active, si_a_ready);
    end
  endtask

  // ----------------------------------------------------------------
  // sram_init DUT B helper task
  // ----------------------------------------------------------------
  task automatic si_b_check(
    input logic                   exp_cs,
    input logic                   exp_wr,
    input logic [SI_B_ABITS-1:0]  exp_waddr,
    input logic [SI_B_DWIDTH-1:0] exp_wdata,
    input logic                   exp_active,
    input logic                   exp_ready,
    input string                  tc_desc,
    input int                     tc_n
  );
    si_total++;
    if (si_b_cs     === exp_cs     &&
        si_b_wr     === exp_wr     &&
        si_b_waddr  === exp_waddr  &&
        si_b_wdata  === exp_wdata  &&
        si_b_active === exp_active &&
        si_b_ready  === exp_ready) begin
      $display("PASS TC%0d sram_init : %s", tc_n, tc_desc);
      si_pass++;
    end else begin
      $display("FAIL TC%0d sram_init : %s", tc_n, tc_desc);
      $display(
        "  cs=%b wr=%b waddr=%h wdata=%h act=%b rdy=%b",
        si_b_cs, si_b_wr, si_b_waddr, si_b_wdata,
        si_b_active, si_b_ready);
    end
  endtask

  // ----------------------------------------------------------------
  // Main test sequence
  // ----------------------------------------------------------------
  initial begin
    // Initialize all DUT inputs to safe defaults
    bwram_addr      = '0;
    bwram_bank_addr = '0;
    bwram_wen_n     = 1'b1;
    bwram_bweb_n    = {BWR_WIDTH{1'b1}};
    bwram_din       = '0;
    alu_a   = '0;
    alu_b   = '0;
    alu_sub = 1'b0;
    dlm_vec = '0;
    si_a_rstn = 1'b0;
    si_b_rstn = 1'b0;
    bwr_pass = 0; bwr_total = 0;
    alu_pass = 0; alu_total = 0;
    dlm_pass = 0; dlm_total = 0;
    si_pass  = 0; si_total  = 0;

    // Wait two cycles before driving tests
    repeat (2) @(posedge clk); #1;

    // ==============================================================
    // tb_bw_ram
    // ==============================================================
    begin : tb_bw_ram

      // TC1: Write FF to bank0/row0, read back, expect FF
      bwram_write(4'd0, 1'b0, 8'hFF, 8'h00);
      bwram_read (4'd0, 1'b0, bwr_rd);
      bwr_total++;
      if (bwr_rd === 8'hFF) begin
        $display("PASS TC1 bw_ram : write FF bank0/row0 readback");
        bwr_pass++;
      end else
        $display("FAIL TC1 bw_ram : expected FF got %0h", bwr_rd);

      // TC2: Write AA to bank1/row5, read back, expect AA
      bwram_write(4'd5, 1'b1, 8'hAA, 8'h00);
      bwram_read (4'd5, 1'b1, bwr_rd);
      bwr_total++;
      if (bwr_rd === 8'hAA) begin
        $display("PASS TC2 bw_ram : write AA bank1/row5 readback");
        bwr_pass++;
      end else
        $display("FAIL TC2 bw_ram : expected AA got %0h", bwr_rd);

      // TC3: bweb mask -- write FF then partial 00 to bank0/row1.
      //   bweb_n=F0 = 1111_0000: bits[7:4] protected, bits[3:0]
      //   written. Result: upper nibble stays F, lower 0 -> F0.
      bwram_write(4'd1, 1'b0, 8'hFF, 8'h00);
      bwram_write(4'd1, 1'b0, 8'h00, 8'hF0);
      bwram_read (4'd1, 1'b0, bwr_rd);
      bwr_total++;
      if (bwr_rd === 8'hF0) begin
        $display("PASS TC3 bw_ram : bweb upper nibble protected");
        bwr_pass++;
      end else
        $display("FAIL TC3 bw_ram : expected F0 got %0h", bwr_rd);

      // TC4: bank isolation -- distinct values at same row, diff banks
      bwram_write(4'd2, 1'b0, 8'hA5, 8'h00);
      bwram_write(4'd2, 1'b1, 8'h5A, 8'h00);
      bwram_read (4'd2, 1'b0, bwr_rd_b0);
      bwram_read (4'd2, 1'b1, bwr_rd_b1);
      bwr_total++;
      if (bwr_rd_b0 === 8'hA5 && bwr_rd_b1 === 8'h5A) begin
        $display("PASS TC4 bw_ram : bank isolation confirmed");
        bwr_pass++;
      end else
        $display(
          "FAIL TC4 bw_ram : expected A5/5A got %0h/%0h",
          bwr_rd_b0, bwr_rd_b1);

      // TC5: address independence -- pre-set row1 sentinel,
      //   write distinct value to row0, read row1, expect sentinel.
      bwram_write(4'd1, 1'b0, 8'hBB, 8'h00);
      bwram_write(4'd0, 1'b0, 8'hCC, 8'h00);
      bwram_read (4'd1, 1'b0, bwr_rd);
      bwr_total++;
      if (bwr_rd === 8'hBB) begin
        $display("PASS TC5 bw_ram : address independence confirmed");
        bwr_pass++;
      end else
        $display("FAIL TC5 bw_ram : expected BB got %0h", bwr_rd);

      $display("bw_ram: %0d/%0d PASSED", bwr_pass, bwr_total);

    end  // tb_bw_ram

    // ==============================================================
    // tb_sat_alu
    // ==============================================================
    begin : tb_sat_alu

      alu_check(4'hE, 4'h1, 1'b0, 4'hF, 1'b0, "E+1=F",      1);
      alu_check(4'hF, 4'h1, 1'b0, 4'hF, 1'b1, "F+1->F sat", 2);
      alu_check(4'hF, 4'hF, 1'b0, 4'hF, 1'b1, "F+F->F sat", 3);
      alu_check(4'h1, 4'h1, 1'b1, 4'h0, 1'b0, "1-1=0",      4);
      alu_check(4'h0, 4'h1, 1'b1, 4'h0, 1'b1, "0-1->0 sat", 5);
      alu_check(4'h0, 4'hF, 1'b1, 4'h0, 1'b1, "0-F->0 sat", 6);
      alu_check(4'h8, 4'h7, 1'b0, 4'hF, 1'b0, "8+7=F",      7);
      alu_check(4'h8, 4'h8, 1'b0, 4'hF, 1'b1, "8+8->F sat", 8);

      $display("sat_alu: %0d/%0d PASSED", alu_pass, alu_total);

    end  // tb_sat_alu

    // ==============================================================
    // tb_dual_lm1
    // ==============================================================
    begin : tb_dual_lm1

      // Positions are 1-based. MSB (bit WIDTH-1) = position WIDTH.
      dlm_check(8'b1010_0000, 4'd8, 4'd6,
                "10100000 lm1=8 lm2=6", 1);
      dlm_check(8'b0000_0000, 4'd0, 4'd0,
                "00000000 lm1=0 lm2=0", 2);
      dlm_check(8'b0000_0001, 4'd1, 4'd0,
                "00000001 lm1=1 lm2=0", 3);
      dlm_check(8'b1111_1111, 4'd8, 4'd7,
                "11111111 lm1=8 lm2=7", 4);
      dlm_check(8'b0000_0011, 4'd2, 4'd1,
                "00000011 lm1=2 lm2=1", 5);
      dlm_check(8'b1000_0001, 4'd8, 4'd1,
                "10000001 lm1=8 lm2=1", 6);
      dlm_check(8'b0100_0000, 4'd7, 4'd0,
                "01000000 lm1=7 lm2=0", 7);
      dlm_check(8'b0110_0000, 4'd7, 4'd6,
                "01100000 lm1=7 lm2=6", 8);

      $display("dual_lm1: %0d/%0d PASSED", dlm_pass, dlm_total);

    end  // tb_dual_lm1

    // ==============================================================
    // tb_sram_init
    // ==============================================================
    begin : tb_sram_init

      // -- DUT A: NUM_ENTRIES=4, START_DELAY=0, INIT_VAL=8'hA5 --
      // Both rstrns already low from initialization.
      repeat (2) @(posedge clk); #1;
      si_a_rstn = 1'b1;
      // Posedge 1 after reset: PENDING->INIT (no delay).
      // waddr=0, cs/wr/active asserted.
      @(posedge clk); #1;
      si_a_check(1'b1, 1'b1, 4'h0, 8'hA5, 1'b1, 1'b0,
        "A no-dly c1 waddr=0", 1);
      @(posedge clk); #1;
      si_a_check(1'b1, 1'b1, 4'h1, 8'hA5, 1'b1, 1'b0,
        "A no-dly c2 waddr=1", 2);
      @(posedge clk); #1;
      si_a_check(1'b1, 1'b1, 4'h2, 8'hA5, 1'b1, 1'b0,
        "A no-dly c3 waddr=2", 3);
      @(posedge clk); #1;
      si_a_check(1'b1, 1'b1, 4'h3, 8'hA5, 1'b1, 1'b0,
        "A no-dly c4 waddr=3", 4);
      // Posedge 5: INIT->DONE. cs/wr/active deassert, ready=1.
      @(posedge clk); #1;
      si_a_check(1'b0, 1'b0, 4'h3, 8'hA5, 1'b0, 1'b1,
        "A done ready=1", 5);

      // -- DUT B: NUM_ENTRIES=4, START_DELAY=3, INIT_VAL=8'hBB --
      si_b_rstn = 1'b1;
      // Posedges 1-3: DELAY state, cs/wr/active deasserted.
      @(posedge clk); #1;
      si_b_check(1'b0, 1'b0, 4'h0, 8'hBB, 1'b0, 1'b0,
        "B delay c1", 6);
      @(posedge clk); #1;
      si_b_check(1'b0, 1'b0, 4'h0, 8'hBB, 1'b0, 1'b0,
        "B delay c2", 7);
      @(posedge clk); #1;
      si_b_check(1'b0, 1'b0, 4'h0, 8'hBB, 1'b0, 1'b0,
        "B delay c3", 8);
      // Posedge 4: DELAY->INIT. First write at waddr=0.
      @(posedge clk); #1;
      si_b_check(1'b1, 1'b1, 4'h0, 8'hBB, 1'b1, 1'b0,
        "B init c1 waddr=0", 9);
      @(posedge clk); #1;
      si_b_check(1'b1, 1'b1, 4'h1, 8'hBB, 1'b1, 1'b0,
        "B init c2 waddr=1", 10);
      @(posedge clk); #1;
      si_b_check(1'b1, 1'b1, 4'h2, 8'hBB, 1'b1, 1'b0,
        "B init c3 waddr=2", 11);
      @(posedge clk); #1;
      si_b_check(1'b1, 1'b1, 4'h3, 8'hBB, 1'b1, 1'b0,
        "B init c4 waddr=3", 12);
      // Posedge 8: INIT->DONE. ready=1.
      @(posedge clk); #1;
      si_b_check(1'b0, 1'b0, 4'h3, 8'hBB, 1'b0, 1'b1,
        "B done ready=1", 13);

      $display("sram_init: %0d/%0d PASSED", si_pass, si_total);

    end  // tb_sram_init

    // ==============================================================
    // Final summary
    // ==============================================================
    $display("tb_components: %0d/%0d PASSED",
      bwr_pass + alu_pass + dlm_pass + si_pass,
      bwr_total + alu_total + dlm_total + si_total);
    if ((bwr_pass + alu_pass + dlm_pass + si_pass) ==
        (bwr_total + alu_total + dlm_total + si_total))
      $display("ALL PASS");
    else
      $display("FAILURES: %0d",
        (bwr_total + alu_total + dlm_total + si_total) -
        (bwr_pass  + alu_pass  + dlm_pass  + si_pass));

    $finish;
  end  // initial

endmodule

`default_nettype wire
