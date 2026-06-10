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
  logic [NPS-1:0]              prm_tgt_wr_u0;
  logic [NPS-1:0]              alt_tgt_wr_u0;
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
    .t_alc_wr_u0          (alc_wr_u0),
    .t_prm_tbl_sel_u0     (prm_tbl_sel_u0),
    .t_alt_tbl_sel_u0     (alt_tbl_sel_u0),
    .t_alc_tbl_sel_u0     (alc_tbl_sel_u0),
    .t_prm_upd_index_u0   (upd_index_u0),
    .t_alt_upd_index_u0   (alt_upd_index_u0),
    .t_alc_index_u0       (alc_index_u0),
    .t_prm_tgt_wr_u0      (prm_tgt_wr_u0),
    .t_alt_tgt_wr_u0      (alt_tgt_wr_u0)
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

  task automatic chk4(
    input string nm, input logic [3:0] act, exp
  );
    if (act === exp) begin
      pass_cnt++;
      $display("  PASS %s", nm);
    end else begin
      fail_cnt++;
      $display("  FAIL %s: exp=%h act=%h", nm, exp, act);
    end
  endtask

  task automatic chk32(
    input string nm, input logic [31:0] act, exp
  );
    if (act === exp) begin
      pass_cnt++;
      $display("  PASS %s", nm);
    end else begin
      fail_cnt++;
      $display("  FAIL %s: exp=%0d(0x%08h) act=%0d(0x%08h)",
               nm, exp, exp, act, act);
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

  // ----------------------------------------------------------------
  // do_reset: local reset to establish clean UAON start state.
  // After return: all FFs at reset values, uaon[i]=IT_UAON_THRES.
  // ----------------------------------------------------------------
  task automatic do_reset();
    clr();
    rstn = 1'b0;
    repeat(2) @(posedge clk);
    @(negedge clk);
    rstn = 1'b1;
    repeat(2) @(posedge clk);
    #1;
  endtask

  // ----------------------------------------------------------------
  // uaon_upd: one update cycle targeting slot 0 for UAON testing.
  // ----------------------------------------------------------------
  task automatic uaon_upd(
    input logic                         hit,
    input logic                         pred_strong,
    input logic [TSW-1:0]               prm_c,
    input logic [TSW-1:0]               alt_c,
    input logic [IT_MAX_TGT_WIDTH-1:0]  prm_t,
    input logic [IT_MAX_TGT_WIDTH-1:0]  alt_t,
    input logic [IT_MAX_TGT_WIDTH-1:0]  res
  );
    ittage_upd_inp_t ui;
    ui = '0;
    ui.ittage_pred_meta.ittage_hit         = hit;
    ui.ittage_pred_meta.ittage_pred_strong = pred_strong;
    ui.ittage_pred_meta.ittage_prm_comp    = prm_c;
    ui.ittage_pred_meta.ittage_alt_comp    = alt_c;
    ui.ittage_pred_meta.ittage_prm_tgt     = prm_t;
    ui.ittage_pred_meta.ittage_alt_tgt     = alt_t;
    ui.resolved_target                     = res;
    clr();
    ittage_upd_val_u0[0] = 1'b1;
    ittage_upd_inp_u0[0] = ui;
    @(posedge clk); #1;
    clr();
  endtask

  // ----------------------------------------------------------------
  // obs_use_alt: observe use_alt[0] via hierarchical reference.
  // Drives null-CTR IT3 primary, non-null IT1 alt for slot 0.
  // After one posedge pred_val_p1[0]=1 and use_alt[0] is valid.
  // ----------------------------------------------------------------
  task automatic obs_use_alt(output logic ua);
    clr();
    ittage_pred_val_p0[0]   = 1'b1;
    tbl_hit_p1[3][0]        = 1'b1;
    tbl_cntrl_bits_p1[3][0] =
      mk_cb(1'b1, 3'b000, 2'b00, 2'b00, 38'hAAAA);
    tbl_pred_tgt_p1[3][0]   = 38'hAAAA;
    tbl_hit_p1[1][0]        = 1'b1;
    tbl_cntrl_bits_p1[1][0] =
      mk_cb(1'b1, 3'b011, 2'b00, 2'b00, 38'hBBBB);
    tbl_pred_tgt_p1[1][0]   = 38'hBBBB;
    @(posedge clk); #1;
    ua = dut.use_alt[0];
    ittage_pred_val_p0[0]   = 1'b0;
    tbl_hit_p1[3][0]        = 1'b0;
    tbl_cntrl_bits_p1[3][0] = '0;
    tbl_pred_tgt_p1[3][0]   = '0;
    tbl_hit_p1[1][0]        = 1'b0;
    tbl_cntrl_bits_p1[1][0] = '0;
    tbl_pred_tgt_p1[1][0]   = '0;
    @(posedge clk); #1;
    clr();
  endtask

  // ----------------------------------------------------------------
  // age_reset: reset with specific aging interval and enable.
  // Sets ittage_aging_interval before asserting reset so the
  // interval FF captures the correct value on the reset edges.
  // ----------------------------------------------------------------
  task automatic age_reset(
    input logic [31:0] interval,
    input logic        enable
  );
    clr();
    ittage_aging_interval = interval;
    ittage_enable_aging   = enable;
    rstn = 1'b0;
    repeat(2) @(posedge clk);
    @(negedge clk);
    rstn = 1'b1;
    repeat(2) @(posedge clk);
    #1;
  endtask

  // ----------------------------------------------------------------
  // age_tick_s0: drive one prediction through slot 0 to advance
  // the aging counter. Does NOT call clr(); preserves aging
  // settings. Requires 3 posedges: posedge 1 captures pred_val
  // into pred_val_p1; posedge 2 captures into rdy_p2_r; posedge 3
  // is when aging_reg reads rdy_p2_r=1 and updates the counters.
  // ----------------------------------------------------------------
  task automatic age_tick_s0();
    ittage_pred_val_p0[0] = 1'b1;
    @(posedge clk); #1;  // posedge 1: pred_val_p1[0] <- 1
    ittage_pred_val_p0[0] = 1'b0;
    @(posedge clk); #1;  // posedge 2: rdy_p2_r[0] <- 1
    @(posedge clk); #1;  // posedge 3: aging_reg reads rdy_p2_r=1
  endtask

  // ================================================================
  // TC-AGE-01: Reset values -- both slots
  // Verifies lcl_aging_interval loads from input and epoch resets
  // to 0 for both prediction slots.
  // ================================================================
  task automatic tc_age_01();
    $display("--- TC-AGE-01 ---");
    age_reset(32'd100, 1'b0);
    chk32("AGE01 interval[0] reset",
          dut.lcl_aging_interval[0], 32'd100);
    chk32("AGE01 interval[1] reset",
          dut.lcl_aging_interval[1], 32'd100);
    chk2("AGE01 epoch[0] reset",
         dut.lcl_epoch[0], 2'b00);
    chk2("AGE01 epoch[1] reset",
         dut.lcl_epoch[1], 2'b00);
  endtask

  // ================================================================
  // TC-AGE-02: Interval decrement on pred_rdy (slot 0)
  // One prediction with interval=50: interval must decrement to 49.
  // Epoch must not advance.
  // ================================================================
  task automatic tc_age_02();
    $display("--- TC-AGE-02 ---");
    age_reset(32'd50, 1'b1);
    age_tick_s0();
    chk32("AGE02 interval[0] dec",
          dut.lcl_aging_interval[0], 32'd49);
    chk2("AGE02 epoch[0] no-adv",
         dut.lcl_epoch[0], 2'b00);
  endtask

  // ================================================================
  // TC-AGE-03: Epoch advance and interval reload
  // interval=1: first tick decrements 1->0; second tick sees
  // interval==0, epoch fires (0->1) and interval reloads to 1.
  // RTL semantics: fires when interval IS 0, then reloads.
  // ================================================================
  task automatic tc_age_03();
    $display("--- TC-AGE-03 ---");
    age_reset(32'd1, 1'b1);
    // Tick 1: interval 1->0 (decrement only)
    age_tick_s0();
    chk32("AGE03 interval[0] at_0",
          dut.lcl_aging_interval[0], 32'd0);
    chk2("AGE03 epoch[0] no-adv-yet",
         dut.lcl_epoch[0], 2'b00);
    // Tick 2: interval==0, epoch fires and interval reloads
    age_tick_s0();
    chk2("AGE03 epoch[0] adv",
         dut.lcl_epoch[0], 2'b01);
    chk32("AGE03 interval[0] reload",
          dut.lcl_aging_interval[0], 32'd1);
  endtask

  // ================================================================
  // TC-AGE-04: Epoch wrap at 2b max (3->0)
  // interval=0: every tick fires epoch. 4 ticks: 0->1->2->3->0.
  // ================================================================
  task automatic tc_age_04();
    $display("--- TC-AGE-04 ---");
    age_reset(32'd0, 1'b1);
    age_tick_s0();  // epoch -> 1
    age_tick_s0();  // epoch -> 2
    age_tick_s0();  // epoch -> 3
    chk2("AGE04 epoch[0] at_3",
         dut.lcl_epoch[0], 2'b11);
    age_tick_s0();  // epoch -> 0 (2b wrap)
    chk2("AGE04 epoch[0] wrap_0",
         dut.lcl_epoch[0], 2'b00);
  endtask

  // ================================================================
  // TC-AGE-05: age==0 -- u_eff equals raw USEFUL (non-triggering)
  // epoch=0, EPC=0: age=(0-0) mod 4 = 0 -> u_eff = USEFUL.
  // Confirms USE holds when delta does not trigger decay.
  // ================================================================
  task automatic tc_age_05();
    ittage_pred_meta_t m; logic rdy;
    logic [CBW-1:0]              cb  [0:NTS-1];
    logic [IT_MAX_TGT_WIDTH-1:0] ptgt[0:NTS-1];
    logic [IT_MAX_IDX_WIDTH-1:0] idx [0:NTS-1];
    logic [IT_MAX_TAG_WIDTH-1:0] tag [0:NTS-1];
    $display("--- TC-AGE-05 ---");
    // epoch=0, aging disabled for stable measurement
    age_reset(32'd0, 1'b0);
    for (int t = 0; t < NTS; t++) begin
      cb[t] = '0; ptgt[t] = '0;
      idx[t] = '0; tag[t] = '0;
    end
    // IT3 hit, USE=2'b11, EPC=2'b00 (age = epoch-EPC = 0-0 = 0)
    cb[3]   = mk_cb(1'b1, 3'b101, 2'b11, 2'b00, 38'hAAAA);
    ptgt[3] = 38'hAAAA;
    pred_s0(40'h0, 6'b00_1000, cb, ptgt, idx, tag, m, rdy);
    // age=0: u_eff = USEFUL = 2'b11 (non-triggering, USE holds)
    chk2("AGE05 u_eff age0 hold",
         m.ittage_prm_useful, 2'b11);
  endtask

  // ================================================================
  // TC-AGE-06: age==1 -- USE decremented by right-shift
  // epoch=1, EPC=0: age=1 -> u_eff = USEFUL>>1.
  // Triggering delta. Discriminating power:
  //   pre-state USE=2'b10 (what a no-op would return).
  //   expected u_eff=2'b01 (PASS). Would FAIL if no decrement (2'b10).
  // ================================================================
  task automatic tc_age_06();
    ittage_pred_meta_t m; logic rdy;
    logic [CBW-1:0]              cb  [0:NTS-1];
    logic [IT_MAX_TGT_WIDTH-1:0] ptgt[0:NTS-1];
    logic [IT_MAX_IDX_WIDTH-1:0] idx [0:NTS-1];
    logic [IT_MAX_TAG_WIDTH-1:0] tag [0:NTS-1];
    $display("--- TC-AGE-06 ---");
    age_reset(32'd0, 1'b1);  // interval=0, aging enabled
    age_tick_s0();            // epoch[0] -> 1
    for (int t = 0; t < NTS; t++) begin
      cb[t] = '0; ptgt[t] = '0;
      idx[t] = '0; tag[t] = '0;
    end
    // IT3 hit, USE=2'b10, EPC=2'b00 (age=epoch-EPC=1-0=1)
    cb[3]   = mk_cb(1'b1, 3'b101, 2'b10, 2'b00, 38'hAAAA);
    ptgt[3] = 38'hAAAA;
    pred_s0(40'h0, 6'b00_1000, cb, ptgt, idx, tag, m, rdy);
    // Failing value (no-op): 2'b10  Passing value (decremented): 2'b01
    chk2("AGE06 u_eff age1 dec",
         m.ittage_prm_useful, 2'b01);
  endtask

  // ================================================================
  // TC-AGE-07: age>=2 -- u_eff zeroed completely
  // epoch=2, EPC=0: age=2 >= 2 -> u_eff = 0.
  // ================================================================
  task automatic tc_age_07();
    ittage_pred_meta_t m; logic rdy;
    logic [CBW-1:0]              cb  [0:NTS-1];
    logic [IT_MAX_TGT_WIDTH-1:0] ptgt[0:NTS-1];
    logic [IT_MAX_IDX_WIDTH-1:0] idx [0:NTS-1];
    logic [IT_MAX_TAG_WIDTH-1:0] tag [0:NTS-1];
    $display("--- TC-AGE-07 ---");
    age_reset(32'd0, 1'b1);
    age_tick_s0();  // epoch -> 1
    age_tick_s0();  // epoch -> 2
    for (int t = 0; t < NTS; t++) begin
      cb[t] = '0; ptgt[t] = '0;
      idx[t] = '0; tag[t] = '0;
    end
    // IT3 hit, USE=2'b11, EPC=2'b00 (age=2)
    cb[3]   = mk_cb(1'b1, 3'b101, 2'b11, 2'b00, 38'hAAAA);
    ptgt[3] = 38'hAAAA;
    pred_s0(40'h0, 6'b00_1000, cb, ptgt, idx, tag, m, rdy);
    // age=2 >= 2: u_eff = 0
    chk2("AGE07 u_eff age2 zero",
         m.ittage_prm_useful, 2'b00);
  endtask

  // ================================================================
  // TC-AGE-08: Discriminating power (step 6) -- triggering and
  // non-triggering cases use the same pre-state USE=2'b10.
  // Case A (age=1, triggering): u_eff=2'b01. A no-op returns 2'b10,
  //   which is observably distinct -- the test would FAIL.
  // Case B (age=0, non-triggering): u_eff=2'b10 (USE holds).
  // ================================================================
  task automatic tc_age_08();
    ittage_pred_meta_t m; logic rdy;
    logic [CBW-1:0]              cb  [0:NTS-1];
    logic [IT_MAX_TGT_WIDTH-1:0] ptgt[0:NTS-1];
    logic [IT_MAX_IDX_WIDTH-1:0] idx [0:NTS-1];
    logic [IT_MAX_TAG_WIDTH-1:0] tag [0:NTS-1];
    $display("--- TC-AGE-08 ---");
    // Case A: triggering (age=1, epoch=1, EPC=0, USE=2'b10)
    // failing=2'b10 (no-op), passing=2'b01 (decremented)
    age_reset(32'd0, 1'b1);
    age_tick_s0();  // epoch -> 1
    for (int t = 0; t < NTS; t++) begin
      cb[t] = '0; ptgt[t] = '0;
      idx[t] = '0; tag[t] = '0;
    end
    cb[3]   = mk_cb(1'b1, 3'b101, 2'b10, 2'b00, 38'hAAAA);
    ptgt[3] = 38'hAAAA;
    pred_s0(40'h0, 6'b00_1000, cb, ptgt, idx, tag, m, rdy);
    chk2("AGE08 trigger_pass 2b01",
         m.ittage_prm_useful, 2'b01);
    // Case B: non-triggering (age=0, epoch=0, EPC=0, USE=2'b10)
    age_reset(32'd0, 1'b0);
    for (int t = 0; t < NTS; t++) begin
      cb[t] = '0; ptgt[t] = '0;
      idx[t] = '0; tag[t] = '0;
    end
    cb[3]   = mk_cb(1'b1, 3'b101, 2'b10, 2'b00, 38'hAAAA);
    ptgt[3] = 38'hAAAA;
    pred_s0(40'h0, 6'b00_1000, cb, ptgt, idx, tag, m, rdy);
    chk2("AGE08 no_trigger_hold 2b10",
         m.ittage_prm_useful, 2'b10);
  endtask

  // ================================================================
  // TC-AGE-09: Enable gating -- no epoch advance, no USE decrement
  // interval=0 (trigger-ready), aging disabled: trigger condition
  // present but epoch must not advance and interval must not reload.
  // u_eff = USEFUL confirmed because age stays at 0 (epoch held).
  // ================================================================
  task automatic tc_age_09();
    ittage_pred_meta_t m; logic rdy;
    logic [CBW-1:0]              cb  [0:NTS-1];
    logic [IT_MAX_TGT_WIDTH-1:0] ptgt[0:NTS-1];
    logic [IT_MAX_IDX_WIDTH-1:0] idx [0:NTS-1];
    logic [IT_MAX_TAG_WIDTH-1:0] tag [0:NTS-1];
    $display("--- TC-AGE-09 ---");
    // Reset: interval=0 (would fire epoch if enabled), aging off
    age_reset(32'd0, 1'b0);
    // Drive prediction tick; enable_aging=0 so epoch must hold
    ittage_pred_val_p0[0] = 1'b1;
    @(posedge clk); #1;
    ittage_pred_val_p0[0] = 1'b0;
    @(posedge clk); #1;
    @(posedge clk); #1;
    // Epoch must NOT advance (aging disabled)
    chk2("AGE09 epoch[0] no_adv",
         dut.lcl_epoch[0], 2'b00);
    // Interval must NOT reload (no aging action)
    chk32("AGE09 interval[0] no_reload",
          dut.lcl_aging_interval[0], 32'd0);
    // u_eff = USEFUL: epoch=0, EPC=0 -> age=0 -> no decay
    for (int t = 0; t < NTS; t++) begin
      cb[t] = '0; ptgt[t] = '0;
      idx[t] = '0; tag[t] = '0;
    end
    cb[3]   = mk_cb(1'b1, 3'b101, 2'b11, 2'b00, 38'hAAAA);
    ptgt[3] = 38'hAAAA;
    pred_s0(40'h0, 6'b00_1000, cb, ptgt, idx, tag, m, rdy);
    chk2("AGE09 u_eff no_dec",
         m.ittage_prm_useful, 2'b11);
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
    chk1("UPD01 prm_tgt_wr", prm_tgt_wr_u0[0], 1'b0);
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
    chk1("UPD02 prm_tgt_wr", prm_tgt_wr_u0[0], 1'b0);
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
    chk1("UPD04 alt_tgt_wr", alt_tgt_wr_u0[0], 1'b0);
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
    chk1("UPD05 prm_tgt_wr", prm_tgt_wr_u0[0], 1'b1);
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
    chk1("UPD09 prm_tgt_wr", prm_tgt_wr_u0[0], 1'b0);
    chk1("UPD09 alc_wr",     alc_wr_u0[0],     1'b0);
  endtask

  // ================================================================
  // TC-UAON-01: Reset value -- both slots at IT_UAON_THRES
  // ================================================================
  task automatic tc_uaon_01();
    $display("--- TC-UAON-01 ---");
    do_reset();
    chk4("UAON01 uaon[0] reset",
         dut.uaon[0], 4'(IT_UAON_THRES));
    chk4("UAON01 uaon[1] reset",
         dut.uaon[1], 4'(IT_UAON_THRES));
  endtask

  // ================================================================
  // TC-UAON-02: Increment -- prm_wrong && alt_correct -> INC
  // ================================================================
  task automatic tc_uaon_02();
    $display("--- TC-UAON-02 ---");
    do_reset();
    // resolved==alt_tgt (alt_correct), resolved!=prm_tgt (prm_wrong)
    uaon_upd(1'b1, 1'b0, TSW'(3), TSW'(1),
             38'hAAAA, 38'hBBBB, 38'hBBBB);
    chk4("UAON02 uaon[0] inc", dut.uaon[0], 4'(9));
  endtask

  // ================================================================
  // TC-UAON-03: Decrement -- prm_correct && alt_wrong -> DEC
  // ================================================================
  task automatic tc_uaon_03();
    $display("--- TC-UAON-03 ---");
    do_reset();
    // resolved==prm_tgt (prm_correct), resolved!=alt_tgt (alt_wrong)
    uaon_upd(1'b1, 1'b0, TSW'(3), TSW'(1),
             38'hAAAA, 38'hBBBB, 38'hAAAA);
    chk4("UAON03 uaon[0] dec", dut.uaon[0], 4'(7));
  endtask

  // ================================================================
  // TC-UAON-04: Both-wrong hold -- neither correct -> no change
  // ================================================================
  task automatic tc_uaon_04();
    $display("--- TC-UAON-04 ---");
    do_reset();
    // resolved differs from both targets -> both wrong -> hold
    uaon_upd(1'b1, 1'b0, TSW'(3), TSW'(1),
             38'hAAAA, 38'hBBBB, 38'hCCCC);
    chk4("UAON04 uaon[0] both_wrong", dut.uaon[0], 4'(8));
  endtask

  // ================================================================
  // TC-UAON-05: Both-right hold -- both match -> no change
  // ================================================================
  task automatic tc_uaon_05();
    $display("--- TC-UAON-05 ---");
    do_reset();
    // resolved==prm_tgt==alt_tgt -> both correct -> hold
    uaon_upd(1'b1, 1'b0, TSW'(3), TSW'(1),
             38'hAAAA, 38'hAAAA, 38'hAAAA);
    chk4("UAON05 uaon[0] both_right", dut.uaon[0], 4'(8));
  endtask

  // ================================================================
  // TC-UAON-06: Pred_strong hold -- no change when pred_strong=1
  // ================================================================
  task automatic tc_uaon_06();
    $display("--- TC-UAON-06 ---");
    do_reset();
    // pred_strong=1 blocks update even if prm_wrong && alt_correct
    uaon_upd(1'b1, 1'b1, TSW'(3), TSW'(1),
             38'hAAAA, 38'hBBBB, 38'hBBBB);
    chk4("UAON06 uaon[0] pred_strong", dut.uaon[0], 4'(8));
  endtask

  // ================================================================
  // TC-UAON-07: Hit==0 hold -- no change when ittage_hit=0
  // ================================================================
  task automatic tc_uaon_07();
    $display("--- TC-UAON-07 ---");
    do_reset();
    // hit=0 blocks update even if prm_wrong && alt_correct
    uaon_upd(1'b0, 1'b0, TSW'(3), TSW'(1),
             38'hAAAA, 38'hBBBB, 38'hBBBB);
    chk4("UAON07 uaon[0] hit0", dut.uaon[0], 4'(8));
  endtask

  // ================================================================
  // TC-UAON-08: Single-hit guard -- alt_comp==0 (sentinel)
  // Stale alt_tgt=0xDEAD matches resolved: without the guard the
  // prm_wrong&&alt_correct condition would fire and increment.
  // With the guard (alt_comp==0 check) the counter must hold.
  // ================================================================
  task automatic tc_uaon_08();
    $display("--- TC-UAON-08 ---");
    do_reset();
    // alt_comp=0 (no alternate); stale alt_tgt==resolved -> blocked
    uaon_upd(1'b1, 1'b0, TSW'(3), TSW'(0),
             38'hBEEF, 38'hDEAD, 38'hDEAD);
    chk4("UAON08 uaon[0] sgl_hit_guard",
         dut.uaon[0], 4'(8));
  endtask

  // ================================================================
  // TC-UAON-09: Threshold boundary
  // Drive counter to THRES-1; confirm alt not selected (use_alt=0).
  // Advance to THRES; confirm alt selected (use_alt=1).
  // Step back; confirm alt not selected (use_alt=0).
  // ================================================================
  task automatic tc_uaon_09();
    logic ua;
    $display("--- TC-UAON-09 ---");
    do_reset();  // uaon[0] = 8
    // DEC to 7: prm_correct && alt_wrong
    uaon_upd(1'b1, 1'b0, TSW'(3), TSW'(1),
             38'hAAAA, 38'hBBBB, 38'hAAAA);
    chk4("UAON09 uaon[0] at_7", dut.uaon[0], 4'(7));
    // uaon=7 < THRES -> alt not selected
    obs_use_alt(ua);
    chk1("UAON09 use_alt=0 at_7", ua, 1'b0);
    // INC to 8: prm_wrong && alt_correct
    uaon_upd(1'b1, 1'b0, TSW'(3), TSW'(1),
             38'hAAAA, 38'hBBBB, 38'hBBBB);
    chk4("UAON09 uaon[0] at_8", dut.uaon[0], 4'(8));
    // uaon=8 >= THRES -> alt selected
    obs_use_alt(ua);
    chk1("UAON09 use_alt=1 at_8", ua, 1'b1);
    // DEC back to 7
    uaon_upd(1'b1, 1'b0, TSW'(3), TSW'(1),
             38'hAAAA, 38'hBBBB, 38'hAAAA);
    chk4("UAON09 uaon[0] back_7", dut.uaon[0], 4'(7));
    // uaon=7 < THRES -> alt not selected
    obs_use_alt(ua);
    chk1("UAON09 use_alt=0 back_7", ua, 1'b0);
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

    tc_uaon_01();
    tc_uaon_02();
    tc_uaon_03();
    tc_uaon_04();
    tc_uaon_05();
    tc_uaon_06();
    tc_uaon_07();
    tc_uaon_08();
    tc_uaon_09();

    tc_age_01();
    tc_age_02();
    tc_age_03();
    tc_age_04();
    tc_age_05();
    tc_age_06();
    tc_age_07();
    tc_age_08();
    tc_age_09();

    $display("RESULTS: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
    if (fail_cnt != 0) $finish(1);
    $finish(0);
  end

endmodule : tb

`default_nettype wire
