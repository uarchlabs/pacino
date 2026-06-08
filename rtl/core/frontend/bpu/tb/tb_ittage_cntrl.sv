// ===================================================================
// FILE:    tb_ittage_cntrl.sv
// DATE:    2026-05-17
// -------------------------------------------------------------------
// Testbench for ittage_cntrl. BP-036.
// Drives tbl_* ports directly; no ittage_table instantiated.
// ===================================================================
`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  // ----------------------------------------------------------------
  // Derived parameters
  // ----------------------------------------------------------------
  localparam int NTS  = IT_NUM_TABLES;
  localparam int NPS  = NUM_PRED_SLOTS;
  localparam int CBW  =
    IT_MAX_VAL_WIDTH + IT_MAX_CTR_WIDTH +
    IT_MAX_USE_WIDTH + IT_MAX_EPC_WIDTH +
    IT_MAX_TGT_WIDTH;
  localparam int MADW = CBW + IT_MAX_TAG_WIDTH;
  localparam int TSW  = IT_TBL_SEL_WIDTH;

  // ----------------------------------------------------------------
  // DUT ports
  // ----------------------------------------------------------------
  logic clk, rstn;
  logic [NPS-1:0]              ittage_pred_val_p0;
  ittage_pred_inp_t            ittage_pred_inp_p0[0:NPS-1];
  logic [NPS-1:0]              ittage_pred_rdy_p2;
  ittage_pred_meta_t           ittage_pred_meta_p2[0:NPS-1];
  logic [NPS-1:0]              ittage_upd_val_u0;
  ittage_upd_inp_t             ittage_upd_inp_u0[0:NPS-1];
  logic [NPS-1:0]              ittage_upd_rdy_u1;
  logic                        ittage_enable_aging;
  logic [31:0]                 ittage_aging_interval;
  logic                        trx_type_tb = 1'b0;
  logic [NPS-1:0]              tbl_hit_p1[0:NTS-1];
  logic [IT_MAX_TGT_WIDTH-1:0]
    tbl_pred_tgt_p1[0:NTS-1][0:NPS-1];
  logic [CBW-1:0]
    tbl_cntrl_bits_p1[0:NTS-1][0:NPS-1];
  logic [IT_MAX_IDX_WIDTH-1:0]
    tbl_idx_hash_p0[0:NTS-1][0:NPS-1];
  logic [IT_MAX_TAG_WIDTH-1:0]
    tbl_tag_hash_p0[0:NTS-1][0:NPS-1];
  logic [IT_MAX_CTR_WIDTH-1:0] prm_ctr_wd_u0[0:NPS-1];
  logic [IT_MAX_CTR_WIDTH-1:0] alt_ctr_wd_u0[0:NPS-1];
  logic [IT_MAX_USE_WIDTH-1:0] use_wd_u0[0:NPS-1];
  logic [IT_MAX_EPC_WIDTH-1:0] epc_wd_u0[0:NPS-1];
  logic [IT_MAX_TGT_WIDTH-1:0] tgt_wd_u0[0:NPS-1];
  logic [MADW-1:0]             alc_wd_u0[0:NPS-1];
  logic [NPS-1:0]              prm_ctr_wr_u0;
  logic [NPS-1:0]              alt_ctr_wr_u0;
  logic [NPS-1:0]              use_wr_u0;
  logic [NPS-1:0]              epc_wr_u0;
  logic [NPS-1:0]              tgt_wr_u0;
  logic [NPS-1:0]              alc_wr_u0;
  logic [TSW-1:0]              prm_tbl_sel_u0[0:NPS-1];
  logic [TSW-1:0]              alt_tbl_sel_u0[0:NPS-1];
  logic [TSW-1:0]              alc_tbl_sel_u0[0:NPS-1];
  logic [IT_MAX_IDX_WIDTH-1:0] upd_index_u0[0:NPS-1];
  logic [IT_MAX_IDX_WIDTH-1:0] alt_upd_index_u0[0:NPS-1];
  logic [IT_MAX_IDX_WIDTH-1:0] alc_index_u0[0:NPS-1];

  // ----------------------------------------------------------------
  // DUT
  // ----------------------------------------------------------------
  ittage_cntrl dut (
    .clk                  (clk),
    .rstn                 (rstn),
    .ittage_pred_val_p0   (ittage_pred_val_p0),
    .ittage_pred_inp_p0   (ittage_pred_inp_p0),
    .ittage_pred_rdy_p2   (ittage_pred_rdy_p2),
    .ittage_pred_meta_p2  (ittage_pred_meta_p2),
    .ittage_upd_val_u0    (ittage_upd_val_u0),
    .ittage_upd_inp_u0    (ittage_upd_inp_u0),
    .ittage_upd_rdy_u1    (ittage_upd_rdy_u1),
    .ittage_enable_aging  (ittage_enable_aging),
    .ittage_aging_interval(ittage_aging_interval),
    .trx_type             (trx_type_tb),
    .t_hit_p1             (tbl_hit_p1),
    .t_pred_tgt_p1        (tbl_pred_tgt_p1),
    .t_cntrl_bits_p1      (tbl_cntrl_bits_p1),
    .t_idx_hash_p0        (tbl_idx_hash_p0),
    .t_tag_hash_p0        (tbl_tag_hash_p0),
    .t_prm_ctr_wd_u0      (prm_ctr_wd_u0),
    .t_alt_ctr_wd_u0      (alt_ctr_wd_u0),
    .t_use_wd_u0          (use_wd_u0),
    .t_epc_wd_u0          (epc_wd_u0),
    .t_tgt_wd_u0          (tgt_wd_u0),
    .t_alc_wd_u0          (alc_wd_u0),
    .t_prm_ctr_wr_u0      (prm_ctr_wr_u0),
    .t_alt_ctr_wr_u0      (alt_ctr_wr_u0),
    .t_use_wr_u0          (use_wr_u0),
    .t_epc_wr_u0          (epc_wr_u0),
    .t_tgt_wr_u0          (tgt_wr_u0),
    .t_alc_wr_u0          (alc_wr_u0),
    .t_prm_tbl_sel_u0     (prm_tbl_sel_u0),
    .t_alt_tbl_sel_u0     (alt_tbl_sel_u0),
    .t_alc_tbl_sel_u0     (alc_tbl_sel_u0),
    .t_prm_upd_index_u0   (upd_index_u0),
    .t_alt_upd_index_u0   (alt_upd_index_u0),
    .t_alc_index_u0       (alc_index_u0)
  );

  // ----------------------------------------------------------------
  // Clock: 10 ns period
  // ----------------------------------------------------------------
  initial begin clk = 1'b0; forever #5 clk = ~clk; end

  int pass_cnt, fail_cnt;

  // ----------------------------------------------------------------
  // mk_cb: assemble cntrl_bits from fields
  // ----------------------------------------------------------------
  function automatic logic [CBW-1:0] mk_cb(
    input logic                        val,
    input logic [IT_MAX_CTR_WIDTH-1:0] ctr,
    input logic [IT_MAX_USE_WIDTH-1:0] ubits,
    input logic [IT_MAX_EPC_WIDTH-1:0] epc,
    input logic [IT_MAX_TGT_WIDTH-1:0] tgt
  );
    return {tgt, epc, ubits, ctr, val};
  endfunction

  // ----------------------------------------------------------------
  // clr: zero all driven ports
  // ----------------------------------------------------------------
  task automatic clr();
    ittage_pred_val_p0    = '0;
    ittage_upd_val_u0     = '0;
    ittage_enable_aging   = 1'b0;
    ittage_aging_interval = 32'hFFFF_FFFF;
    for (int s = 0; s < NPS; s++) begin
      ittage_pred_inp_p0[s] = '0;
      ittage_upd_inp_u0[s]  = '0;
    end
    for (int t = 0; t < NTS; t++) begin
      tbl_hit_p1[t] = '0;
      for (int s = 0; s < NPS; s++) begin
        tbl_cntrl_bits_p1[t][s] = '0;
        tbl_pred_tgt_p1[t][s]   = '0;
        tbl_idx_hash_p0[t][s]   = '0;
        tbl_tag_hash_p0[t][s]   = '0;
      end
    end
  endtask

  // ----------------------------------------------------------------
  // Check helpers
  // ----------------------------------------------------------------
  task automatic chk1(
    input string nm, input logic act, exp
  );
    if (act === exp) begin
      pass_cnt++;
      $display("  PASS %s", nm);
    end else begin
      fail_cnt++;
      $display("  FAIL %s: exp=%b act=%b", nm, exp, act);
    end
  endtask

  task automatic chk2(
    input string nm, input logic [1:0] act, exp
  );
    if (act === exp) begin
      pass_cnt++;
      $display("  PASS %s", nm);
    end else begin
      fail_cnt++;
      $display("  FAIL %s: exp=%h act=%h", nm, exp, act);
    end
  endtask

  task automatic chk3(
    input string nm, input logic [2:0] act, exp
  );
    if (act === exp) begin
      pass_cnt++;
      $display("  PASS %s", nm);
    end else begin
      fail_cnt++;
      $display("  FAIL %s: exp=%h act=%h", nm, exp, act);
    end
  endtask

  task automatic chk9(
    input string nm, input logic [8:0] act, exp
  );
    if (act === exp) begin
      pass_cnt++;
      $display("  PASS %s", nm);
    end else begin
      fail_cnt++;
      $display("  FAIL %s: exp=%h act=%h", nm, exp, act);
    end
  endtask

  task automatic chk38(
    input string nm, input logic [37:0] act, exp
  );
    if (act === exp) begin
      pass_cnt++;
      $display("  PASS %s", nm);
    end else begin
      fail_cnt++;
      $display("  FAIL %s: exp=%h act=%h", nm, exp, act);
    end
  endtask

  task automatic chk57(
    input string nm, input logic [56:0] act, exp
  );
    if (act === exp) begin
      pass_cnt++;
      $display("  PASS %s", nm);
    end else begin
      fail_cnt++;
      $display("  FAIL %s: exp=%h act=%h", nm, exp, act);
    end
  endtask

  // ----------------------------------------------------------------
  // mk_upd: build default update input bundle
  // ----------------------------------------------------------------
  task automatic mk_upd(output ittage_upd_inp_t ui);
    ui = '0;
    ui.indir_mispredict                      = 1'b0;
    ui.resolved_target                       = 38'hBEEF;
    ui.ittage_pred_meta.ittage_hit           = 1'b1;
    ui.ittage_pred_meta.ittage_using_primary = 1'b1;
    ui.ittage_pred_meta.ittage_pred_strong   = 1'b1;
    ui.ittage_pred_meta.ittage_prm_comp      = TSW'(3);
    ui.ittage_pred_meta.ittage_alt_comp      = TSW'(1);
    ui.ittage_pred_meta.ittage_prm_ctr       = 3'b101;
    ui.ittage_pred_meta.ittage_alt_ctr       = 3'b010;
    ui.ittage_pred_meta.ittage_prm_idx       = 9'h033;
    ui.ittage_pred_meta.ittage_alt_idx       = 9'h011;
    ui.ittage_pred_meta.ittage_prm_tgt       = 38'hAAAA;
    ui.ittage_pred_meta.ittage_alt_tgt       = 38'hBBBB;
    ui.ittage_pred_meta.ittage_alc_comp      = TSW'(4);
    ui.ittage_pred_meta.ittage_alc_idx       = 9'h044;
    ui.ittage_pred_meta.ittage_alc_tag       = 11'h555;
    ui.ittage_pred_meta.ittage_prm_useful    = 2'b01;
    ui.ittage_pred_meta.ittage_alt_useful    = 2'b10;
  endtask

  // ----------------------------------------------------------------
  // pred_s0: drive slot 0 through the 2-cycle prediction pipeline.
  // hit[t] = 1 means table t hit for slot 0.
  // ----------------------------------------------------------------
  // pred_s0: drive slot 0 through the 2-cycle prediction pipeline.
  // tbl_hit_p1/cntrl_bits/pred_tgt are driven BEFORE the p0->p1
  // posedge so Verilator's nba_sequent at that edge sees correct
  // table results. meta_p2_r captures the scan result at p1->p2.
  task automatic pred_s0(
    input  logic [VA_WIDTH-1:0]          pc,
    input  logic [NTS-1:0]               hit,
    input  logic [CBW-1:0]               cb  [0:NTS-1],
    input  logic [IT_MAX_TGT_WIDTH-1:0]  ptgt[0:NTS-1],
    input  logic [IT_MAX_IDX_WIDTH-1:0]  idx [0:NTS-1],
    input  logic [IT_MAX_TAG_WIDTH-1:0]  tag [0:NTS-1],
    output ittage_pred_meta_t            m,
    output logic                         rdy
  );
    clr();
    ittage_pred_val_p0[0]           = 1'b1;
    ittage_pred_inp_p0[0].pc        = pc;
    ittage_pred_inp_p0[0].branch_id = '0;
    for (int t = 0; t < NTS; t++) begin
      tbl_idx_hash_p0[t][0] = idx[t];
      tbl_tag_hash_p0[t][0] = tag[t];
      tbl_hit_p1[t][0]        = hit[t];
      tbl_cntrl_bits_p1[t][0] = cb[t];
      tbl_pred_tgt_p1[t][0]   = ptgt[t];
    end
    @(posedge clk); #1;
    ittage_pred_val_p0 = '0;
    // Hold tbl_hit_p1/cntrl_bits/pred_tgt stable through p1
    // period so prv_alt_scan sees correct inputs when
    // meta_p2_reg latches at the p1->p2 posedge.
    @(posedge clk); #1;
    for (int t = 0; t < NTS; t++) begin
      tbl_hit_p1[t][0]        = 1'b0;
      tbl_cntrl_bits_p1[t][0] = '0;
      tbl_pred_tgt_p1[t][0]   = '0;
    end
    m   = ittage_pred_meta_p2[0];
    rdy = ittage_pred_rdy_p2[0];
  endtask

  // ================================================================
  // TC-PRED-01: No hit
  // ================================================================
  task automatic tc_pred_01();
    ittage_pred_meta_t m; logic rdy;
    logic [CBW-1:0]              cb  [0:NTS-1];
    logic [IT_MAX_TGT_WIDTH-1:0] ptgt[0:NTS-1];
    logic [IT_MAX_IDX_WIDTH-1:0] idx [0:NTS-1];
    logic [IT_MAX_TAG_WIDTH-1:0] tag [0:NTS-1];
    $display("--- TC-PRED-01 ---");
    for (int t = 0; t < NTS; t++) begin
      cb[t] = '0; ptgt[t] = '0;
      idx[t] = '0; tag[t] = '0;
    end
    pred_s0(40'hAAA, 6'b0, cb, ptgt, idx, tag, m, rdy);
    chk1("PRED01 rdy",      rdy,                    1'b1);
    chk1("PRED01 hit",      m.ittage_hit,           1'b0);
    chk3("PRED01 prm_comp", m.ittage_prm_comp,      3'(0));
    chk3("PRED01 alt_comp", m.ittage_alt_comp,      3'(0));
    chk1("PRED01 strong",   m.ittage_pred_strong,   1'b0);
  endtask

  // ================================================================
  // TC-PRED-02: IT5 only hits, strong CTR
  // ================================================================
  task automatic tc_pred_02();
    ittage_pred_meta_t m; logic rdy;
    logic [CBW-1:0]              cb  [0:NTS-1];
    logic [IT_MAX_TGT_WIDTH-1:0] ptgt[0:NTS-1];
    logic [IT_MAX_IDX_WIDTH-1:0] idx [0:NTS-1];
    logic [IT_MAX_TAG_WIDTH-1:0] tag [0:NTS-1];
    $display("--- TC-PRED-02 ---");
    for (int t = 0; t < NTS; t++) begin
      cb[t] = '0; ptgt[t] = '0;
      idx[t] = '0; tag[t] = '0;
    end
    cb[5]   = mk_cb(1'b1, 3'b110, 2'b10, 2'b00,
                    38'h0000_0000_1234);
    ptgt[5] = 38'h0000_0000_1234;
    idx[5]  = 9'h055;
    tag[5]  = 11'h2AA;
    pred_s0(40'h0, 6'b10_0000, cb, ptgt, idx, tag, m, rdy);
    chk1("PRED02 hit",      m.ittage_hit,           1'b1);
    chk3("PRED02 prm_comp", m.ittage_prm_comp,      3'(5));
    chk3("PRED02 alt_comp", m.ittage_alt_comp,      3'(0));
    chk9("PRED02 prm_idx",  m.ittage_prm_idx,       9'h055);
    chk3("PRED02 prm_ctr",  m.ittage_prm_ctr,       3'b110);
    chk1("PRED02 strong",   m.ittage_pred_strong,   1'b1);
    chk1("PRED02 using_prm",m.ittage_using_primary, 1'b1);
    chk38("PRED02 prm_tgt", m.ittage_prm_tgt,
          38'h0000_0000_1234);
  endtask

  // ================================================================
  // TC-PRED-03: IT5 and IT3 hit; primary=IT5, alt=IT3
  // ================================================================
  task automatic tc_pred_03();
    ittage_pred_meta_t m; logic rdy;
    logic [CBW-1:0]              cb  [0:NTS-1];
    logic [IT_MAX_TGT_WIDTH-1:0] ptgt[0:NTS-1];
    logic [IT_MAX_IDX_WIDTH-1:0] idx [0:NTS-1];
    logic [IT_MAX_TAG_WIDTH-1:0] tag [0:NTS-1];
    $display("--- TC-PRED-03 ---");
    for (int t = 0; t < NTS; t++) begin
      cb[t] = '0; ptgt[t] = '0;
      idx[t] = '0; tag[t] = '0;
    end
    cb[5]   = mk_cb(1'b1, 3'b101, 2'b01, 2'b00,
                    38'h0000_0000_AAAA);
    ptgt[5] = 38'h0000_0000_AAAA;
    idx[5]  = 9'h011;
    cb[3]   = mk_cb(1'b1, 3'b010, 2'b00, 2'b00,
                    38'h0000_0000_BBBB);
    ptgt[3] = 38'h0000_0000_BBBB;
    idx[3]  = 9'h022;
    pred_s0(40'h0, 6'b10_1000, cb, ptgt, idx, tag, m, rdy);
    chk3("PRED03 prm_comp", m.ittage_prm_comp,      3'(5));
    chk3("PRED03 alt_comp", m.ittage_alt_comp,      3'(3));
    chk9("PRED03 prm_idx",  m.ittage_prm_idx,       9'h011);
    chk9("PRED03 alt_idx",  m.ittage_alt_idx,       9'h022);
    chk3("PRED03 prm_ctr",  m.ittage_prm_ctr,       3'b101);
    chk3("PRED03 alt_ctr",  m.ittage_alt_ctr,       3'b010);
    chk1("PRED03 using_prm",m.ittage_using_primary, 1'b1);
    chk38("PRED03 prm_tgt", m.ittage_prm_tgt,
          38'h0000_0000_AAAA);
    chk1("PRED03 strong",   m.ittage_pred_strong,   1'b1);
  endtask

  // ================================================================
  // TC-PRED-04: UAON fires (=8), alt selected
  // IT3=primary CTR=null, IT1=alt
  // ================================================================
  task automatic tc_pred_04();
    ittage_pred_meta_t m; logic rdy;
    logic [CBW-1:0]              cb  [0:NTS-1];
    logic [IT_MAX_TGT_WIDTH-1:0] ptgt[0:NTS-1];
    logic [IT_MAX_IDX_WIDTH-1:0] idx [0:NTS-1];
    logic [IT_MAX_TAG_WIDTH-1:0] tag [0:NTS-1];
    $display("--- TC-PRED-04 ---");
    for (int t = 0; t < NTS; t++) begin
      cb[t] = '0; ptgt[t] = '0;
      idx[t] = '0; tag[t] = '0;
    end
    cb[3]   = mk_cb(1'b1, 3'b000, 2'b00, 2'b00,
                    38'h0000_0000_1111);
    ptgt[3] = 38'h0000_0000_1111;
    cb[1]   = mk_cb(1'b1, 3'b011, 2'b01, 2'b00,
                    38'h0000_0000_2222);
    ptgt[1] = 38'h0000_0000_2222;
    pred_s0(40'h0, 6'b00_1010, cb, ptgt, idx, tag, m, rdy);
    chk1("PRED04 hit",      m.ittage_hit,            1'b1);
    chk3("PRED04 prm_comp", m.ittage_prm_comp,       3'(3));
    chk3("PRED04 alt_comp", m.ittage_alt_comp,       3'(1));
    chk1("PRED04 using_prm",m.ittage_using_primary,  1'b0);
    chk1("PRED04 uaon",     m.ittage_use_alt_on_na,  1'b1);
    chk38("PRED04 alt_tgt", m.ittage_alt_tgt,
          38'h0000_0000_2222);
    chk1("PRED04 strong",   m.ittage_pred_strong,    1'b1);
  endtask

  // ================================================================
  // TC-PRED-05: UAON fires but no alt, primary used
  // ================================================================
  task automatic tc_pred_05();
    ittage_pred_meta_t m; logic rdy;
    logic [CBW-1:0]              cb  [0:NTS-1];
    logic [IT_MAX_TGT_WIDTH-1:0] ptgt[0:NTS-1];
    logic [IT_MAX_IDX_WIDTH-1:0] idx [0:NTS-1];
    logic [IT_MAX_TAG_WIDTH-1:0] tag [0:NTS-1];
    $display("--- TC-PRED-05 ---");
    for (int t = 0; t < NTS; t++) begin
      cb[t] = '0; ptgt[t] = '0;
      idx[t] = '0; tag[t] = '0;
    end
    cb[3]   = mk_cb(1'b1, 3'b000, 2'b00, 2'b00,
                    38'h0000_0000_1111);
    ptgt[3] = 38'h0000_0000_1111;
    pred_s0(40'h0, 6'b00_1000, cb, ptgt, idx, tag, m, rdy);
    chk1("PRED05 using_prm", m.ittage_using_primary, 1'b1);
    chk38("PRED05 prm_tgt",  m.ittage_prm_tgt,
          38'h0000_0000_1111);
    chk1("PRED05 strong",    m.ittage_pred_strong,   1'b0);
  endtask

  // ================================================================
  // TC-PRED-06: Dual-slot independent operation
  // Slot 0: IT5 hits. Slot 1: IT2 hits. No cross-slot effect.
  // ================================================================
  task automatic tc_pred_06();
    ittage_pred_meta_t m0, m1;
    logic r0, r1;
    $display("--- TC-PRED-06 ---");
    clr();
    ittage_pred_val_p0            = 2'b11;
    ittage_pred_inp_p0[0].pc      = 40'h0;
    ittage_pred_inp_p0[0].branch_id = '0;
    ittage_pred_inp_p0[1].pc      = 40'h0;
    ittage_pred_inp_p0[1].branch_id = '0;
    // Drive tbl_hit_p1 BEFORE p0->p1 posedge so Verilator's
    // nba_sequent at that edge sees the correct table results.
    tbl_hit_p1[5][0]        = 1'b1;
    tbl_hit_p1[2][1]        = 1'b1;
    tbl_cntrl_bits_p1[5][0] = mk_cb(1'b1, 3'b111, 2'b11,
                                2'b00, 38'h0000_0000_CCCC);
    tbl_pred_tgt_p1[5][0]   = 38'h0000_0000_CCCC;
    tbl_cntrl_bits_p1[2][1] = mk_cb(1'b1, 3'b001, 2'b00,
                                2'b00, 38'h0000_0000_DDDD);
    tbl_pred_tgt_p1[2][1]   = 38'h0000_0000_DDDD;
    @(posedge clk); #1;
    ittage_pred_val_p0      = '0;
    // Hold hit/cntrl/tgt stable until meta_p2_reg latches.
    @(posedge clk); #1;
    m0 = ittage_pred_meta_p2[0];
    m1 = ittage_pred_meta_p2[1];
    r0 = ittage_pred_rdy_p2[0];
    r1 = ittage_pred_rdy_p2[1];
    tbl_hit_p1[5][0]        = 1'b0;
    tbl_hit_p1[2][1]        = 1'b0;
    tbl_cntrl_bits_p1[5][0] = '0;
    tbl_pred_tgt_p1[5][0]   = '0;
    tbl_cntrl_bits_p1[2][1] = '0;
    tbl_pred_tgt_p1[2][1]   = '0;
    clr();
    chk3("PRED06 s0 prm_comp", m0.ittage_prm_comp,   3'(5));
    chk1("PRED06 s0 hit",      m0.ittage_hit,         1'b1);
    chk38("PRED06 s0 prm_tgt", m0.ittage_prm_tgt,
          38'h0000_0000_CCCC);
    chk3("PRED06 s1 prm_comp", m1.ittage_prm_comp,   3'(2));
    chk1("PRED06 s1 hit",      m1.ittage_hit,         1'b1);
    chk38("PRED06 s1 prm_tgt", m1.ittage_prm_tgt,
          38'h0000_0000_DDDD);
  endtask

  // ================================================================
  // TC-UPD-01: CTR row 3: using_prm=1, no_mispredict, alt_comp>0
  // ================================================================
  task automatic tc_upd_01();
    ittage_upd_inp_t ui;
    $display("--- TC-UPD-01 ---");
    mk_upd(ui);
    clr();
    ittage_upd_val_u0[0] = 1'b1;
    ittage_upd_inp_u0[0] = ui;
    #1;
    // UP=1 -> provider is primary (rows 18-33 of CTR rules table).
    // prm_ctr_wr fires; alt_ctr_wr stays low.
    // prm_ctr=3'b101, no_mispredict: INC -> 3'b110.
    chk1("UPD01 prm_ctr_wr", prm_ctr_wr_u0[0], 1'b1);
    chk1("UPD01 alt_ctr_wr", alt_ctr_wr_u0[0], 1'b0);
    chk3("UPD01 prm_ctr_wd", prm_ctr_wd_u0[0], 3'b110);
    chk1("UPD01 use_wr",     use_wr_u0[0],     1'b1);
    chk2("UPD01 use_wd",     use_wd_u0[0],     2'b10);
    chk1("UPD01 epc_wr",     epc_wr_u0[0],     1'b1);
    chk1("UPD01 tgt_wr",     tgt_wr_u0[0],     1'b0);
    chk1("UPD01 alc_wr",     alc_wr_u0[0],     1'b0);
    @(posedge clk); #1;
    clr();
  endtask

  // ================================================================
  // TC-UPD-02: CTR row 5: using_prm=1, mispredict, alt_comp>0
  // ================================================================
  task automatic tc_upd_02();
    ittage_upd_inp_t ui;
    $display("--- TC-UPD-02 ---");
    mk_upd(ui);
    ui.indir_mispredict = 1'b1;
    clr();
    ittage_upd_val_u0[0] = 1'b1;
    ittage_upd_inp_u0[0] = ui;
    #1;
    // UP=1 -> prm_ctr_wr fires (rows 22-29 of CTR rules table).
    // prm_ctr=3'b101, mispredict: DEC -> 3'b100.
    chk1("UPD02 prm_ctr_wr", prm_ctr_wr_u0[0], 1'b1);
    chk3("UPD02 prm_ctr_wd", prm_ctr_wd_u0[0], 3'b100);
    chk1("UPD02 alt_ctr_wr", alt_ctr_wr_u0[0], 1'b0);
    chk1("UPD02 tgt_wr",     tgt_wr_u0[0],     1'b0);
    chk1("UPD02 alc_wr",     alc_wr_u0[0],     1'b1);
    @(posedge clk); #1;
    clr();
  endtask

  // ================================================================
  // TC-UPD-03: CTR row 7: using_prm=0, no_mispredict, prm_comp>0
  // ================================================================
  task automatic tc_upd_03();
    ittage_upd_inp_t ui;
    $display("--- TC-UPD-03 ---");
    mk_upd(ui);
    ui.ittage_pred_meta.ittage_using_primary = 1'b0;
    ui.ittage_pred_meta.ittage_prm_ctr       = 3'b011;
    clr();
    ittage_upd_val_u0[0] = 1'b1;
    ittage_upd_inp_u0[0] = ui;
    #1;
    // UP=0 -> provider is alternate (rows 2-17 of CTR rules table).
    // alt_ctr_wr fires; prm_ctr_wr stays low.
    // alt_ctr=3'b010, no_mispredict: INC -> 3'b011.
    chk1("UPD03 alt_ctr_wr", alt_ctr_wr_u0[0], 1'b1);
    chk3("UPD03 alt_ctr_wd", alt_ctr_wd_u0[0], 3'b011);
    chk1("UPD03 prm_ctr_wr", prm_ctr_wr_u0[0], 1'b0);
    @(posedge clk); #1;
    clr();
  endtask

  // ================================================================
  // TC-UPD-04: CTR row 9: using_prm=0, mispredict, prm_comp>0
  // Provider = alt; alt_ctr=010 not null -> no tgt_wr
  // ================================================================
  task automatic tc_upd_04();
    ittage_upd_inp_t ui;
    $display("--- TC-UPD-04 ---");
    mk_upd(ui);
    ui.ittage_pred_meta.ittage_using_primary = 1'b0;
    ui.indir_mispredict                      = 1'b1;
    ui.ittage_pred_meta.ittage_prm_ctr       = 3'b011;
    clr();
    ittage_upd_val_u0[0] = 1'b1;
    ittage_upd_inp_u0[0] = ui;
    #1;
    // UP=0 -> alt_ctr_wr fires (rows 6-13 of CTR rules table).
    // alt_ctr=3'b010, mispredict: DEC -> 3'b001.
    chk1("UPD04 alt_ctr_wr", alt_ctr_wr_u0[0], 1'b1);
    chk3("UPD04 alt_ctr_wd", alt_ctr_wd_u0[0], 3'b001);
    chk1("UPD04 prm_ctr_wr", prm_ctr_wr_u0[0], 1'b0);
    chk1("UPD04 tgt_wr",     tgt_wr_u0[0],     1'b0);
    chk1("UPD04 alc_wr",     alc_wr_u0[0],     1'b1);
    @(posedge clk); #1;
    clr();
  endtask

  // ================================================================
  // TC-UPD-05: TGT write fires (provider CTR null)
  // ================================================================
  task automatic tc_upd_05();
    ittage_upd_inp_t ui;
    $display("--- TC-UPD-05 ---");
    mk_upd(ui);
    ui.ittage_pred_meta.ittage_using_primary = 1'b1;
    ui.indir_mispredict                      = 1'b1;
    ui.ittage_pred_meta.ittage_prm_ctr       = 3'b000;
    clr();
    ittage_upd_val_u0[0] = 1'b1;
    ittage_upd_inp_u0[0] = ui;
    #1;
    // UP=1 -> prm_ctr_wr fires (rows 22-29 of CTR rules table).
    // prm_ctr=3'b000, mispredict: DEC saturates at 3'b000.
    // tgt_wr fires independently: mispredict + UP=1 + prm_ctr==0.
    chk1("UPD05 tgt_wr",     tgt_wr_u0[0],     1'b1);
    chk38("UPD05 tgt_wd",    tgt_wd_u0[0],     38'hBEEF);
    chk1("UPD05 prm_ctr_wr", prm_ctr_wr_u0[0], 1'b1);
    chk1("UPD05 alt_ctr_wr", alt_ctr_wr_u0[0], 1'b0);
    chk3("UPD05 prm_ctr_wd", prm_ctr_wd_u0[0], 3'b000);
    @(posedge clk); #1;
    clr();
  endtask

  // ================================================================
  // TC-UPD-06: Allocation write data
  // ================================================================
  task automatic tc_upd_06();
    ittage_upd_inp_t ui;
    logic [MADW-1:0] exp_alc;
    $display("--- TC-UPD-06 ---");
    mk_upd(ui);
    ui.indir_mispredict                      = 1'b1;
    ui.ittage_pred_meta.ittage_prm_comp      = TSW'(3);
    ui.ittage_pred_meta.ittage_alc_comp      = TSW'(4);
    ui.ittage_pred_meta.ittage_prm_ctr       = 3'b101;
    ui.ittage_pred_meta.ittage_alc_tag       = 11'h555;
    ui.resolved_target                       = 38'hBEEF;
    clr();
    ittage_upd_val_u0[0] = 1'b1;
    ittage_upd_inp_u0[0] = ui;
    #1;
    // lcl_epoch=0 (reset, aging disabled)
    exp_alc = {11'h555, 38'hBEEF,
               2'b00, 2'b00, 3'b000, 1'b1};
    // alc_index must come from ittage_alc_idx (9'h044), not
    // ittage_prm_idx (9'h033). ittage_alc_idx != ittage_prm_idx
    // here, so this check is discriminating: pre-fix RTL sources
    // t_prm_upd_index_u0 (9'h033) and FAILS; post-fix RTL
    // sources ittage_alc_idx (9'h044) and PASSES.
    chk1("UPD06 alc_wr",
         alc_wr_u0[0],      1'b1);
    chk3("UPD06 alc_tbl_sel",
         alc_tbl_sel_u0[0], 3'(4));
    chk9("UPD06 alc_index",
         alc_index_u0[0],   9'h044);
    chk57("UPD06 alc_wd",
          alc_wd_u0[0],     exp_alc);
    @(posedge clk); #1;
    clr();
  endtask

  // ================================================================
  // TC-UPD-07: ittage_upd_rdy_u1 timing
  // ================================================================
  task automatic tc_upd_07();
    ittage_upd_inp_t ui;
    $display("--- TC-UPD-07 ---");
    mk_upd(ui);
    clr();
    ittage_upd_val_u0[0] = 1'b1;
    ittage_upd_inp_u0[0] = ui;
    @(posedge clk); #1;
    chk1("UPD07 rdy_asserted",   ittage_upd_rdy_u1[0], 1'b1);
    ittage_upd_val_u0[0] = 1'b0;
    @(posedge clk); #1;
    chk1("UPD07 rdy_deasserted", ittage_upd_rdy_u1[0], 1'b0);
    clr();
  endtask

  // ================================================================
  // TC-UPD-08: UAON increment and verification via prediction
  // ================================================================
  task automatic tc_upd_08();
    ittage_upd_inp_t ui;
    ittage_pred_meta_t m; logic rdy;
    logic [CBW-1:0]              cb  [0:NTS-1];
    logic [IT_MAX_TGT_WIDTH-1:0] ptgt[0:NTS-1];
    logic [IT_MAX_IDX_WIDTH-1:0] idx [0:NTS-1];
    logic [IT_MAX_TAG_WIDTH-1:0] tag [0:NTS-1];
    $display("--- TC-UPD-08 ---");
    mk_upd(ui);
    // pred_strong=0, prm_wrong, alt_correct -> INC uaon
    ui.ittage_pred_meta.ittage_pred_strong = 1'b0;
    ui.ittage_pred_meta.ittage_prm_tgt     = 38'hAAAA;
    ui.ittage_pred_meta.ittage_alt_tgt     = 38'hBBBB;
    ui.resolved_target                     = 38'hBBBB;
    clr();
    ittage_upd_val_u0[0] = 1'b1;
    ittage_upd_inp_u0[0] = ui;
    @(posedge clk); #1; // uaon[0] increments to 9
    clr();
    // Confirm uaon=9: null prm_ctr + alt present -> use_alt fires
    for (int t = 0; t < NTS; t++) begin
      cb[t] = '0; ptgt[t] = '0;
      idx[t] = '0; tag[t] = '0;
    end
    cb[3]   = mk_cb(1'b1, 3'b000, 2'b00, 2'b00,
                    38'h0000_0000_1111);
    ptgt[3] = 38'h0000_0000_1111;
    cb[1]   = mk_cb(1'b1, 3'b011, 2'b01, 2'b00,
                    38'h0000_0000_2222);
    ptgt[1] = 38'h0000_0000_2222;
    pred_s0(40'h0, 6'b00_1010, cb, ptgt, idx, tag, m, rdy);
    chk1("UPD08 using_prm=0", m.ittage_using_primary, 1'b0);
    chk1("UPD08 uaon_fired",  m.ittage_use_alt_on_na, 1'b1);
  endtask

  // ================================================================
  // TC-UPD-09: No updates when upd_val=0
  // ================================================================
  task automatic tc_upd_09();
    $display("--- TC-UPD-09 ---");
    clr();
    #1;
    chk1("UPD09 prm_ctr_wr", prm_ctr_wr_u0[0], 1'b0);
    chk1("UPD09 alt_ctr_wr", alt_ctr_wr_u0[0], 1'b0);
    chk1("UPD09 use_wr",     use_wr_u0[0],     1'b0);
    chk1("UPD09 tgt_wr",     tgt_wr_u0[0],     1'b0);
    chk1("UPD09 alc_wr",     alc_wr_u0[0],     1'b0);
  endtask

  // ================================================================
  // Main test sequence
  // ================================================================
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    clr();
    rstn = 1'b0;
    repeat(4) @(posedge clk);
    @(negedge clk);
    rstn = 1'b1;
    repeat(2) @(posedge clk);
    #1;

    tc_pred_01();
    tc_pred_02();
    tc_pred_03();
    tc_pred_04();
    tc_pred_05();
    tc_pred_06();

    tc_upd_01();
    tc_upd_02();
    tc_upd_03();
    tc_upd_04();
    tc_upd_05();
    tc_upd_06();
    tc_upd_07();
    tc_upd_08();
    tc_upd_09();

    $display("RESULTS: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
    if (fail_cnt != 0) $finish(1);
    $finish(0);
  end

endmodule : tb

`default_nettype wire
