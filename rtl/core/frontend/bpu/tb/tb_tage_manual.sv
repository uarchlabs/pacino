// ===================================================================
// FILE:    tb_tage_manual.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// TAGE manual testbench. Top module is tb (no ports).
// DUT: tage #(.NUM_PRED_SLOTS(2)) u_dut.
// Task files: utils.svh, tb_tage_manual_tasks.svh.
// Run: +TAGE_FAST_INIT=1 +EN_FST=1 (optional waveform dump).
// TB-002: round-trip sanity test only.
// ===================================================================

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

`include "utils.svh"
`include "tb_tage_manual_tasks.svh"

  // ----------------------------------------------------------------
  // Local parameters
  // ----------------------------------------------------------------
  localparam int NUM_PRED_SLOTS = 2;

  // ----------------------------------------------------------------
  // Test enable integers (1 = enabled)
  // ----------------------------------------------------------------
  int en_round_trip = 1;

  // ----------------------------------------------------------------
  // Per-test error counters
  // ----------------------------------------------------------------
  int err_round_trip = 0;

  // ----------------------------------------------------------------
  // DUT port signal declarations
  // ----------------------------------------------------------------
  logic [NUM_PRED_SLOTS-1:0]        tage_pred_val_p0;
  tage_pred_inp_t                   tage_pred_inp_p0[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]        tage_pred_rdy_p2;
  tage_pred_meta_t                  tage_pred_meta_p2[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]        tage_upd_val_u0;
  tage_upd_inp_t                    tage_upd_inp_u0[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]        tage_upd_rdy_u1;
  logic                             pq_not_full;
  logic [NUM_PRED_SLOTS-1:0]        upd_rdy;
  logic                             tage_enable_aging;
  logic [31:0]                      tage_aging_interval;
  logic                             consumer_ready;
  bp_folded_hist_t                  folded_hist;
  logic                             tage_rdy;

  // ----------------------------------------------------------------
  // Testbench variables
  // ----------------------------------------------------------------
  int    cycle_cnt;
  logic  clk;
  logic  rstn;
  int    tb_errs;
  string test_name;

  // Staging registers: NBA propagation for struct-typed array ports.
  // Tasks write to staging; always_ff propagates to DUT ports so
  // tage.sv always_comb blocks see FF outputs (nba_sequent).
  tage_pred_inp_t            stg_pred_inp[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] stg_pred_val;
  tage_upd_inp_t             stg_upd_inp[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] stg_upd_val;

  // ----------------------------------------------------------------
  // DUT signal logic and tieoffs
  // ----------------------------------------------------------------
  initial begin
    tage_enable_aging   = 1'b0;
    tage_aging_interval = 32'b0;
    folded_hist         = '0;
    consumer_ready      = 1'b1;
    stg_pred_val        = '0;
    stg_pred_inp[0]     = '0;
    stg_pred_inp[1]     = '0;
    stg_upd_val         = '0;
    stg_upd_inp[0]      = '0;
    stg_upd_inp[1]      = '0;
  end

  // ----------------------------------------------------------------
  // Master run_tests task
  // ----------------------------------------------------------------
  task automatic run_tests();
    if (en_round_trip) tage_round_trip_sanity(err_round_trip);
    tb_errs = err_round_trip;
  endtask

  // ----------------------------------------------------------------
  // Master initial statement
  // ----------------------------------------------------------------
  initial begin : tb_main
    int en_fst;
    test_name = "";
    tb_errs   = 0;
    assert_reset(4);
    while (!tage_rdy) @(posedge clk);
    @(posedge clk);
    en_fst = 0;
    void'($value$plusargs("EN_FST=%d", en_fst));
    if (en_fst) begin
      $dumpfile("tb_tage_manual.fst");
      $dumpvars(0, tb);
    end
    run_tests();
    terminate();
  end

  // ----------------------------------------------------------------
  // Testbench logic: clock, cycle counter, staging FFs
  // ----------------------------------------------------------------
  initial clk = 0;
  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  initial cycle_cnt = 0;
  /* verilator lint_off BLKSEQ */
  always @(posedge clk) cycle_cnt++;
  /* verilator lint_on BLKSEQ */

  always_ff @(posedge clk) begin : pred_stg_ff
    tage_pred_val_p0[0] <= stg_pred_val[0];
    tage_pred_val_p0[1] <= stg_pred_val[1];
    tage_pred_inp_p0[0] <= stg_pred_inp[0];
    tage_pred_inp_p0[1] <= stg_pred_inp[1];
  end

  always_ff @(posedge clk) begin : upd_stg_ff
    tage_upd_val_u0[0] <= stg_upd_val[0];
    tage_upd_val_u0[1] <= stg_upd_val[1];
    tage_upd_inp_u0[0] <= stg_upd_inp[0];
    tage_upd_inp_u0[1] <= stg_upd_inp[1];
  end

  // ----------------------------------------------------------------
  // DUT instantiation
  // ----------------------------------------------------------------
  tage #(
    .NUM_PRED_SLOTS (NUM_PRED_SLOTS)
  ) u_dut (
    .clk                 (clk),
    .rstn                (rstn),
    .tage_pred_val_p0    (tage_pred_val_p0),
    .tage_pred_inp_p0    (tage_pred_inp_p0),
    .tage_pred_rdy_p2    (tage_pred_rdy_p2),
    .tage_pred_meta_p2   (tage_pred_meta_p2),
    .tage_upd_val_u0     (tage_upd_val_u0),
    .tage_upd_inp_u0     (tage_upd_inp_u0),
    .tage_upd_rdy_u1     (tage_upd_rdy_u1),
    .pq_not_full         (pq_not_full),
    .upd_rdy             (upd_rdy),
    .tage_enable_aging   (tage_enable_aging),
    .tage_aging_interval (tage_aging_interval),
    .consumer_ready      (consumer_ready),
    .folded_hist         (folded_hist),
    .tage_rdy            (tage_rdy)
  );

endmodule : tb

`default_nettype wire
