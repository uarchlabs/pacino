// ===================================================================
// FILE:    tb_ittage_table.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking testbench for ittage_table.
// DUT parameters: IT1 (THIS_TABLE=1, IDX_BITS=8, TAG_BITS=8).
// folded_hist=0 throughout; +ITTAGE_FAST_INIT=1 required.
//
// This needs to be crossed checked against the manual testbench results
// ===================================================================

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  // DUT parameters
  localparam int THIS_TABLE      = 1;
  localparam int THIS_INDEX_BITS = 8;
  localparam int THIS_TAG_BITS   = 8;
  localparam int THIS_CTR_WIDTH  = IT_MAX_CTR_WIDTH;   // 3
  localparam int THIS_USE_WIDTH  = IT_MAX_USE_WIDTH;   // 2
  localparam int THIS_EPC_WIDTH  = IT_MAX_EPC_WIDTH;   // 2
  localparam int TBL_SEL_W       = IT_TBL_SEL_WIDTH;  // 3
  localparam int CBITS_W         = IT_MAX_VAL_WIDTH
                                 + IT_MAX_CTR_WIDTH
                                 + IT_MAX_USE_WIDTH
                                 + IT_MAX_EPC_WIDTH
                                 + IT_MAX_TGT_WIDTH;   // 46
  localparam int ALC_W           = CBITS_W + THIS_TAG_BITS; // 54

  // PC constants
  localparam logic [VA_WIDTH-1:0] PC_A = 40'h00_0000_1040;
  localparam logic [VA_WIDTH-1:0] PC_B = 40'h00_0000_2040;
  localparam logic [VA_WIDTH-1:0] PC_C = 40'h00_0000_0140;
  localparam logic [VA_WIDTH-1:0] PC_D = 40'h00_0000_00C0;
  localparam logic [VA_WIDTH-1:0] PC_E = 40'h00_0000_0080;

  logic clk, rstn;
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // DUT signals
  logic [1:0]                  hit_p1;
  logic [IT_MAX_TGT_WIDTH-1:0] pred_tgt_p1[0:1];
  logic [CBITS_W-1:0]          cntrl_bits_p1[0:1];
  logic [THIS_INDEX_BITS-1:0]  idx_hash_p0[0:1];
  logic [IT_MAX_TAG_WIDTH-1:0] tag_hash_p0[0:1];
  logic [1:0]                  ittage_pred_val_p0;
  ittage_pred_inp_t            ittage_pred_inp_p0[0:1];
  bp_folded_hist_t             folded_hist;
  logic [1:0]                  ittage_upd_val_u0;
  logic [THIS_CTR_WIDTH-1:0]   prm_ctr_wd_u0[0:1];
  logic [THIS_CTR_WIDTH-1:0]   alt_ctr_wd_u0[0:1];
  logic [THIS_USE_WIDTH-1:0]   use_wd_u0[0:1];
  logic [THIS_EPC_WIDTH-1:0]   epc_wd_u0[0:1];
  logic [IT_MAX_TGT_WIDTH-1:0] tgt_wd_u0[0:1];
  logic [ALC_W-1:0]            alc_wd_u0[0:1];
  logic [1:0]                  prm_ctr_wr_u0;
  logic [1:0]                  alt_ctr_wr_u0;
  logic [1:0]                  use_wr_u0;
  logic [1:0]                  epc_wr_u0;
  logic [1:0]                  tgt_wr_u0;
  logic [1:0]                  alc_wr_u0;
  logic [TBL_SEL_W-1:0]        prm_tbl_sel_u0[0:1];
  logic [TBL_SEL_W-1:0]        alt_tbl_sel_u0[0:1];
  logic [TBL_SEL_W-1:0]        alc_tbl_sel_u0[0:1];
  logic [THIS_INDEX_BITS-1:0]  upd_index_u0[0:1];
  logic [THIS_INDEX_BITS-1:0]  alc_index_u0[0:1];
  logic                        tbl_ri_active;
  logic                        tbl_ri_wr;
  logic [THIS_INDEX_BITS-1:0]  tbl_ri_wa;
  logic [ALC_W-1:0]            tbl_ri_wd;

  ittage_table #(
    .THIS_TABLE     (THIS_TABLE),
    .THIS_INDEX_BITS(THIS_INDEX_BITS),
    .THIS_TAG_BITS  (THIS_TAG_BITS)
  ) dut (
    .hit_p1             (hit_p1),
    .pred_tgt_p1        (pred_tgt_p1),
    .cntrl_bits_p1      (cntrl_bits_p1),
    .idx_hash_p0        (idx_hash_p0),
    .tag_hash_p0        (tag_hash_p0),
    .ittage_pred_val_p0 (ittage_pred_val_p0),
    .ittage_pred_inp_p0 (ittage_pred_inp_p0),
    .folded_hist        (folded_hist),
    .ittage_upd_val_u0  (ittage_upd_val_u0),
    .prm_ctr_wd_u0      (prm_ctr_wd_u0),
    .alt_ctr_wd_u0      (alt_ctr_wd_u0),
    .use_wd_u0          (use_wd_u0),
    .epc_wd_u0          (epc_wd_u0),
    .tgt_wd_u0          (tgt_wd_u0),
    .alc_wd_u0          (alc_wd_u0),
    .prm_ctr_wr_u0      (prm_ctr_wr_u0),
    .alt_ctr_wr_u0      (alt_ctr_wr_u0),
    .use_wr_u0          (use_wr_u0),
    .epc_wr_u0          (epc_wr_u0),
    .tgt_wr_u0          (tgt_wr_u0),
    .alc_wr_u0          (alc_wr_u0),
    .prm_tbl_sel_u0     (prm_tbl_sel_u0),
    .alt_tbl_sel_u0     (alt_tbl_sel_u0),
    .alc_tbl_sel_u0     (alc_tbl_sel_u0),
    .upd_index_u0       (upd_index_u0),
    .alc_index_u0       (alc_index_u0),
    .tbl_ri_active      (tbl_ri_active),
    .tbl_ri_wr          (tbl_ri_wr),
    .tbl_ri_wa          (tbl_ri_wa),
    .tbl_ri_wd          (tbl_ri_wd),
    .rstn               (rstn),
    .clk                (clk)
  );

  // Timeout watchdog
  initial begin
    #100000;
    $display("TIMEOUT: watchdog expired");
    $finish;
  end

  int pass_cnt, fail_cnt;

  task check;
    input string name;
    input logic  got;
    input logic  exp;
    if (got === exp) begin
      pass_cnt = pass_cnt + 1;
      $display("PASS %s", name);
    end else begin
      fail_cnt = fail_cnt + 1;
      $display("FAIL %s: got %b exp %b", name, got, exp);
    end
  endtask

  task check_w;
    input string       name;
    input logic [63:0] got;
    input logic [63:0] exp;
    if (got === exp) begin
      pass_cnt = pass_cnt + 1;
      $display("PASS %s", name);
    end else begin
      fail_cnt = fail_cnt + 1;
      $display("FAIL %s: got %h exp %h", name, got, exp);
    end
  endtask

  initial begin
    // Initialize all inputs
    rstn                        = 0;
    ittage_pred_val_p0          = 0;
    ittage_upd_val_u0           = 0;
    prm_ctr_wr_u0               = 0;
    alt_ctr_wr_u0               = 0;
    use_wr_u0                   = 0;
    epc_wr_u0                   = 0;
    tgt_wr_u0                   = 0;
    alc_wr_u0                   = 0;
    tbl_ri_active               = 0;
    tbl_ri_wr                   = 0;
    tbl_ri_wa                   = 0;
    tbl_ri_wd                   = 0;
    folded_hist                 = '0;
    ittage_pred_inp_p0[0].pc        = 0;
    ittage_pred_inp_p0[0].branch_id = 0;
    ittage_pred_inp_p0[1].pc        = 0;
    ittage_pred_inp_p0[1].branch_id = 0;
    prm_ctr_wd_u0[0]  = 0; prm_ctr_wd_u0[1]  = 0;
    alt_ctr_wd_u0[0]  = 0; alt_ctr_wd_u0[1]  = 0;
    use_wd_u0[0]      = 0; use_wd_u0[1]      = 0;
    epc_wd_u0[0]      = 0; epc_wd_u0[1]      = 0;
    tgt_wd_u0[0]      = 0; tgt_wd_u0[1]      = 0;
    alc_wd_u0[0]      = 0; alc_wd_u0[1]      = 0;
    prm_tbl_sel_u0[0] = 0; prm_tbl_sel_u0[1] = 0;
    alt_tbl_sel_u0[0] = 0; alt_tbl_sel_u0[1] = 0;
    alc_tbl_sel_u0[0] = 0; alc_tbl_sel_u0[1] = 0;
    upd_index_u0[0]   = 0; upd_index_u0[1]   = 0;
    alc_index_u0[0]   = 0; alc_index_u0[1]   = 0;
    pass_cnt = 0;
    fail_cnt = 0;

    // Reset sequence
    repeat(4) @(posedge clk);
    @(posedge clk); #1;
    rstn = 1;
    @(posedge clk); #1;

    // --------------------------------------------------------
    // TC-HASH: Combinatorial hash verification (no clock)
    // --------------------------------------------------------
    ittage_pred_inp_p0[0].pc = PC_A;
    ittage_pred_inp_p0[1].pc = PC_C;
    #1;
    check_w("TC-HASH idx_hash_p0[0]",
            64'(idx_hash_p0[0]), 64'h10);
    check_w("TC-HASH tag_hash_p0[0]",
            64'(tag_hash_p0[0]), 64'h010);
    check_w("TC-HASH idx_hash_p0[1]",
            64'(idx_hash_p0[1]), 64'h50);
    check_w("TC-HASH tag_hash_p0[1]",
            64'(tag_hash_p0[1]), 64'h001);

    // --------------------------------------------------------
    // TC-ALLOC-HIT: Allocate at idx=0x10 (PC_A), predict hit
    // Entry: tag=0x10, tgt=0x55, epc=2, use=1, ctr=4, val=1
    // --------------------------------------------------------
    ittage_upd_val_u0[0]  = 1;
    alc_wr_u0[0]          = 1;
    alc_tbl_sel_u0[0]     = TBL_SEL_W'(1);
    alc_index_u0[0]       = 8'h10;
    alc_wd_u0[0] = {8'h10, 38'h55, 2'b10, 2'b01, 3'b100, 1'b1};
    ittage_pred_inp_p0[0].pc = PC_A;
    @(posedge clk); #1;
    ittage_upd_val_u0[0] = 0;
    alc_wr_u0[0]         = 0;
    // Predict cycle
    @(posedge clk); #1;
    check("TC-ALLOC-HIT hit_p1[0]",
          hit_p1[0], 1'b1);
    check_w("TC-ALLOC-HIT pred_tgt_p1[0]",
            64'(pred_tgt_p1[0]), 64'h55);
    check("TC-ALLOC-HIT cntrl_bits[0][0]",
          cntrl_bits_p1[0][0], 1'b1);
    check_w("TC-ALLOC-HIT cntrl_bits[0][3:1]",
            64'(cntrl_bits_p1[0][3:1]), 64'h4);
    check_w("TC-ALLOC-HIT cntrl_bits[0][5:4]",
            64'(cntrl_bits_p1[0][5:4]), 64'h1);
    check_w("TC-ALLOC-HIT cntrl_bits[0][7:6]",
            64'(cntrl_bits_p1[0][7:6]), 64'h2);
    check_w("TC-ALLOC-HIT cntrl_bits[0][45:8]",
            64'(cntrl_bits_p1[0][45:8]), 64'h55);

    // --------------------------------------------------------
    // TC-PRED-VAL-ZERO: pred_val=0 does not suppress hit_p1
    // --------------------------------------------------------
    ittage_pred_val_p0[0]    = 0;
    ittage_pred_inp_p0[0].pc = PC_A;
    @(posedge clk); #1;
    check("TC-PRED-VAL-ZERO hit_p1[0]", hit_p1[0], 1'b1);

    // --------------------------------------------------------
    // TC-TAG-MISS: Tag miss same index (PC_B: idx=0x10 tag=0x20)
    // --------------------------------------------------------
    ittage_pred_inp_p0[0].pc = PC_B;
    @(posedge clk); #1;
    check("TC-TAG-MISS hit_p1[0]", hit_p1[0], 1'b0);

    // --------------------------------------------------------
    // TC-PRM-CTR: prm_ctr_wr update, read back
    // --------------------------------------------------------
    ittage_upd_val_u0[0] = 1;
    prm_ctr_wr_u0[0]     = 1;
    prm_tbl_sel_u0[0]    = TBL_SEL_W'(1);
    prm_ctr_wd_u0[0]     = 3'b111;
    upd_index_u0[0]      = 8'h10;
    ittage_pred_inp_p0[0].pc = PC_A;
    @(posedge clk); #1;
    ittage_upd_val_u0[0] = 0;
    prm_ctr_wr_u0[0]     = 0;
    @(posedge clk); #1;
    check("TC-PRM-CTR hit_p1[0]", hit_p1[0], 1'b1);
    check_w("TC-PRM-CTR cntrl_bits[0][3:1]",
            64'(cntrl_bits_p1[0][3:1]), 64'h7);

    // --------------------------------------------------------
    // TC-ALT-CTR: Alloc at idx=0x50 (PC_C), alt CTR update
    // Entry: tag=0x01, tgt=0xAA, epc=0, use=0, ctr=4, val=1
    // After update: ctr=2
    // --------------------------------------------------------
    ittage_upd_val_u0[0] = 1;
    alc_wr_u0[0]         = 1;
    alc_tbl_sel_u0[0]    = TBL_SEL_W'(1);
    alc_index_u0[0]      = 8'h50;
    alc_wd_u0[0] = {8'h01, 38'hAA, 2'b00, 2'b00, 3'b100, 1'b1};
    ittage_pred_inp_p0[0].pc = PC_C;
    @(posedge clk); #1;
    ittage_upd_val_u0[0] = 0;
    alc_wr_u0[0]         = 0;
    // Alt CTR update at idx=0x50
    ittage_upd_val_u0[0] = 1;
    alt_ctr_wr_u0[0]     = 1;
    alt_tbl_sel_u0[0]    = TBL_SEL_W'(1);
    alt_ctr_wd_u0[0]     = 3'b010;
    upd_index_u0[0]      = 8'h50;
    @(posedge clk); #1;
    ittage_upd_val_u0[0] = 0;
    alt_ctr_wr_u0[0]     = 0;
    // Predict
    @(posedge clk); #1;
    check("TC-ALT-CTR hit_p1[0]", hit_p1[0], 1'b1);
    check_w("TC-ALT-CTR cntrl_bits[0][3:1]",
            64'(cntrl_bits_p1[0][3:1]), 64'h2);

    // --------------------------------------------------------
    // TC-USE-EPC: use_wr and epc_wr via prm path, read back
    // --------------------------------------------------------
    ittage_upd_val_u0[0] = 1;
    use_wr_u0[0]         = 1;
    epc_wr_u0[0]         = 1;
    prm_tbl_sel_u0[0]    = TBL_SEL_W'(1);
    use_wd_u0[0]         = 2'b11;
    epc_wd_u0[0]         = 2'b01;
    upd_index_u0[0]      = 8'h10;
    ittage_pred_inp_p0[0].pc = PC_A;
    @(posedge clk); #1;
    ittage_upd_val_u0[0] = 0;
    use_wr_u0[0]         = 0;
    epc_wr_u0[0]         = 0;
    @(posedge clk); #1;
    check("TC-USE-EPC hit_p1[0]", hit_p1[0], 1'b1);
    check_w("TC-USE-EPC cntrl_bits[0][5:4]",
            64'(cntrl_bits_p1[0][5:4]), 64'h3);
    check_w("TC-USE-EPC cntrl_bits[0][7:6]",
            64'(cntrl_bits_p1[0][7:6]), 64'h1);

    // --------------------------------------------------------
    // TC-TGT-WR: tgt_wr target replacement, read back
    // --------------------------------------------------------
    ittage_upd_val_u0[0] = 1;
    tgt_wr_u0[0]         = 1;
    prm_tbl_sel_u0[0]    = TBL_SEL_W'(1);
    tgt_wd_u0[0]         = 38'h1234;
    upd_index_u0[0]      = 8'h10;
    ittage_pred_inp_p0[0].pc = PC_A;
    @(posedge clk); #1;
    ittage_upd_val_u0[0] = 0;
    tgt_wr_u0[0]         = 0;
    @(posedge clk); #1;
    check("TC-TGT-WR hit_p1[0]", hit_p1[0], 1'b1);
    check_w("TC-TGT-WR pred_tgt_p1[0]",
            64'(pred_tgt_p1[0]), 64'h1234);
    check_w("TC-TGT-WR cntrl_bits[0][45:8]",
            64'(cntrl_bits_p1[0][45:8]), 64'h1234);

    // --------------------------------------------------------
    // TC-ALC-GATE: Wrong alc_tbl_sel blocked (2 != 1)
    // Prior entry from TC-ALT-CTR at idx=0x50 must survive
    // --------------------------------------------------------
    ittage_upd_val_u0[0] = 1;
    alc_wr_u0[0]         = 1;
    alc_tbl_sel_u0[0]    = TBL_SEL_W'(2);
    alc_index_u0[0]      = 8'h50;
    alc_wd_u0[0] = {8'hFF, 38'hFF, 2'b11, 2'b11, 3'b111, 1'b1};
    ittage_pred_inp_p0[0].pc = PC_C;
    @(posedge clk); #1;
    ittage_upd_val_u0[0] = 0;
    alc_wr_u0[0]         = 0;
    @(posedge clk); #1;
    check("TC-ALC-GATE hit_p1[0]", hit_p1[0], 1'b1);

    // --------------------------------------------------------
    // TC-PRM-GATE: Wrong prm_tbl_sel blocked (3 != 1)
    // CTR at idx=0x10 must remain 3'b111 from TC-PRM-CTR
    // --------------------------------------------------------
    ittage_upd_val_u0[0] = 1;
    prm_ctr_wr_u0[0]     = 1;
    prm_tbl_sel_u0[0]    = TBL_SEL_W'(3);
    prm_ctr_wd_u0[0]     = 3'b000;
    upd_index_u0[0]      = 8'h10;
    ittage_pred_inp_p0[0].pc = PC_A;
    @(posedge clk); #1;
    ittage_upd_val_u0[0] = 0;
    prm_ctr_wr_u0[0]     = 0;
    @(posedge clk); #1;
    check_w("TC-PRM-GATE cntrl_bits[0][3:1]",
            64'(cntrl_bits_p1[0][3:1]), 64'h7);

    // --------------------------------------------------------
    // TC-TBL-RI: tbl_ri write path, predict hit
    // Write: tag=0x00, tgt=0xCC, epc=3, use=1, ctr=6, val=1
    // --------------------------------------------------------
    tbl_ri_active = 1;
    tbl_ri_wr     = 1;
    tbl_ri_wa     = 8'h30;
    tbl_ri_wd = {8'h00, 38'hCC, 2'b11, 2'b01, 3'b110, 1'b1};
    ittage_pred_inp_p0[0].pc = PC_A;  // idle during ri write
    @(posedge clk); #1;
    tbl_ri_active = 0;
    tbl_ri_wr     = 0;
    // Predict with PC_D (idx=0x30, tag=0x00)
    ittage_pred_inp_p0[0].pc = PC_D;
    @(posedge clk); #1;
    check("TC-TBL-RI hit_p1[0]", hit_p1[0], 1'b1);
    check_w("TC-TBL-RI pred_tgt_p1[0]",
            64'(pred_tgt_p1[0]), 64'hCC);
    check_w("TC-TBL-RI cntrl_bits[0][3:1]",
            64'(cntrl_bits_p1[0][3:1]), 64'h6);

    // --------------------------------------------------------
    // TC-DUAL: Slot 0 and slot 1 simultaneous, independent data
    // Slot 0: tag=0x00, tgt=0xAA, epc=1, use=1, ctr=5, val=1
    // Slot 1: tag=0x00, tgt=0xBB, epc=2, use=2, ctr=2, val=1
    // --------------------------------------------------------
    ittage_upd_val_u0    = 2'b11;
    alc_wr_u0            = 2'b11;
    alc_tbl_sel_u0[0]    = TBL_SEL_W'(1);
    alc_tbl_sel_u0[1]    = TBL_SEL_W'(1);
    alc_index_u0[0]      = 8'h20;
    alc_index_u0[1]      = 8'h20;
    alc_wd_u0[0] = {8'h00, 38'hAA, 2'b01, 2'b01, 3'b101, 1'b1};
    alc_wd_u0[1] = {8'h00, 38'hBB, 2'b10, 2'b10, 3'b010, 1'b1};
    ittage_pred_inp_p0[0].pc = PC_E;
    ittage_pred_inp_p0[1].pc = PC_E;
    @(posedge clk); #1;
    ittage_upd_val_u0 = 0;
    alc_wr_u0         = 0;
    // Predict both slots
    @(posedge clk); #1;
    check("TC-DUAL hit_p1[0]", hit_p1[0], 1'b1);
    check("TC-DUAL hit_p1[1]", hit_p1[1], 1'b1);
    check_w("TC-DUAL pred_tgt_p1[0]",
            64'(pred_tgt_p1[0]), 64'hAA);
    check_w("TC-DUAL pred_tgt_p1[1]",
            64'(pred_tgt_p1[1]), 64'hBB);

    $display("PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule : tb

`default_nettype wire
