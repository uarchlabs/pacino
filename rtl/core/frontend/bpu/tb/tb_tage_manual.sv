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
  int en_ctr_test = 1;

  // ----------------------------------------------------------------
  // Per-test error counters
  // ----------------------------------------------------------------
  int err_round_trip = 0;
  int err_ctr_test   = 0;

  // ----------------------------------------------------------------
  // DUT port signal declarations
  // ----------------------------------------------------------------
  logic [NUM_PRED_SLOTS-1:0] tage_pred_val_p0;
  tage_pred_inp_t            tage_pred_inp_p0[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] tage_pred_rdy_p2;
  tage_pred_meta_t           tage_pred_meta_p2[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] tage_upd_val_u0;
  tage_upd_inp_t             tage_upd_inp_u0[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] tage_upd_rdy_u1;
  logic                      pq_not_full;
  logic [NUM_PRED_SLOTS-1:0] upd_rdy;
  logic                      tage_enable_aging;
  logic [31:0]               tage_aging_interval;
  logic                      consumer_ready;
  bp_folded_hist_t           folded_hist;
  logic                      tage_rdy;

  //break out
  wire d_tage_pred_val_p0_s0 = tage_pred_val_p0[0];
  wire d_tage_pred_val_p0_s1 = tage_pred_val_p0[1];

//  tage_pred_inp_t d_tage_pred_inp_p0_s0 = tage_pred_inp_p0[0];
//  tage_pred_inp_t d_tage_pred_inp_p0_s1 = tage_pred_inp_p0[1];

  wire d_tage_pred_rdy_p2_s0 = tage_pred_rdy_p2[0];
  wire d_tage_pred_rdy_p2_s1 = tage_pred_rdy_p2[1];

//  tage_pred_meta_t d_tage_pred_meta_p2_s0 = tage_pred_meta_p2[0];
//  tage_pred_meta_t d_tage_pred_meta_p2_s1 = tage_pred_meta_p2[1];

  wire d_tage_upd_val_u0_s0 = tage_upd_val_u0[0];
  wire d_tage_upd_val_u0_s1 = tage_upd_val_u0[1];

//  tage_upd_inp_t d_tage_upd_inp_u0_s0 = tage_upd_inp_u0[0];
//  tage_upd_inp_t d_tage_upd_inp_u0_s1 = tage_upd_inp_u0[1];

  wire d_tage_upd_rdy_u1_s0 = tage_upd_rdy_u1[0];
  wire d_tage_upd_rdy_u1_s1 = tage_upd_rdy_u1[1];


  `define FTQ_RNG FTQ_IDX_BITS-1:0
  `define VA_RNG  VA_WIDTH-1:0
  wire [`VA_RNG]  d_pred_inp_p0_pc_s0        = tage_pred_inp_p0[0].pc;
  wire [`VA_RNG]  d_pred_inp_p0_pc_s1        = tage_pred_inp_p0[1].pc;
  wire [`FTQ_RNG] d_pred_inp_p0_branch_id_s0 = tage_pred_inp_p0[0].branch_id;
  wire [`FTQ_RNG] d_pred_inp_p0_branch_id_s1 = tage_pred_inp_p0[0].branch_id;

  `define AW_RNG   TAGE_MAX_AWIDTH-1:0
  `define DW_RNG   TAGE_MAX_DWIDTH-1:0
  `define TSEL_RNG TAGE_TBL_SEL_WIDTH-1:0
  `define USE_RNG  TAGE_MAX_USE_WIDTH-1:0
  `define CTR_RNG  TAGE_MAX_CTR_WIDTH-1:0

  wire [`AW_RNG]   d_meta_p2_prm_idx_s0 = tage_pred_meta_p2[0].tage_prm_idx;
  wire [`AW_RNG]   d_pred_meta_p2_alt_idx_s0 = tage_pred_meta_p2[0].tage_alt_idx;
  wire [`TSEL_RNG] d_pred_meta_p2_prm_comp_s0 = tage_pred_meta_p2[0].tage_prm_comp;
  wire [`TSEL_RNG] d_pred_meta_p2_alt_comp_s0 = tage_pred_meta_p2[0].tage_alt_comp;

  wire [`USE_RNG]  d_pred_meta_p2_prm_useful_s0 = tage_pred_meta_p2[0].tage_prm_useful;
  wire [`USE_RNG]  d_pred_meta_p2_alt_useful_s0 = tage_pred_meta_p2[0].tage_alt_useful;
  wire [`CTR_RNG]  d_pred_meta_p2_prm_ctr_s0 = tage_pred_meta_p2[0].tage_prm_ctr;
  wire [`CTR_RNG]  d_pred_meta_p2_alt_ctr_s0 = tage_pred_meta_p2[0].tage_alt_ctr;

  wire [`TSEL_RNG] d_pred_meta_p2_alc_comp_s0 = tage_pred_meta_p2[0].tage_alc_comp;
  wire [`AW_RNG]   d_pred_meta_p2_alc_idx_s0 = tage_pred_meta_p2[0].tage_alc_idx;
  wire [`DW_RNG]   d_pred_meta_p2_alc_tag_s0 = tage_pred_meta_p2[0].tage_alc_tag;

  wire d_pred_meta_p2_prm_tkn_s0 = tage_pred_meta_p2[0].tage_prm_tkn;
  wire d_pred_meta_p2_alt_tkn_s0 = tage_pred_meta_p2[0].tage_alt_tkn;

  wire d_pred_meta_p2_pred_strong_s0 = tage_pred_meta_p2[0].tage_pred_strong;
  wire d_pred_meta_p2_use_alt_on_na_s0 = tage_pred_meta_p2[0].tage_use_alt_on_na;
  wire d_pred_meta_p2_using_primary_s0 = tage_pred_meta_p2[0].tage_using_primary;
  wire d_pred_meta_p2_high_conf_s0 = tage_pred_meta_p2[0].tage_high_conf;
  wire d_pred_meta_p2_pred_tkn_s0 = tage_pred_meta_p2[0].tage_pred_tkn;
  wire [`FTQ_RNG] d_pred_meta_p2_branch_id_s0 = tage_pred_meta_p2[0].branch_id;
  // --------------------------------------------------------------------------------
  wire [`AW_RNG]   d_meta_p2_prm_idx_s1 = tage_pred_meta_p2[1].tage_prm_idx;
  wire [`AW_RNG]   d_pred_meta_p2_alt_idx_s1 = tage_pred_meta_p2[1].tage_alt_idx;
  wire [`TSEL_RNG] d_pred_meta_p2_prm_comp_s1 = tage_pred_meta_p2[1].tage_prm_comp;
  wire [`TSEL_RNG] d_pred_meta_p2_alt_comp_s1 = tage_pred_meta_p2[1].tage_alt_comp;

  wire [`USE_RNG]  d_pred_meta_p2_prm_useful_s1 = tage_pred_meta_p2[1].tage_prm_useful;
  wire [`USE_RNG]  d_pred_meta_p2_alt_useful_s1 = tage_pred_meta_p2[1].tage_alt_useful;
  wire [`CTR_RNG]  d_pred_meta_p2_prm_ctr_s1    = tage_pred_meta_p2[1].tage_prm_ctr;
  wire [`CTR_RNG]  d_pred_meta_p2_alt_ctr_s1    = tage_pred_meta_p2[1].tage_alt_ctr;

  wire [`TSEL_RNG] d_pred_meta_p2_alc_comp_s1 = tage_pred_meta_p2[1].tage_alc_comp;
  wire [`AW_RNG]   d_pred_meta_p2_alc_idx_s1  = tage_pred_meta_p2[1].tage_alc_idx;
  wire [`DW_RNG]   d_pred_meta_p2_alc_tag_s1  = tage_pred_meta_p2[1].tage_alc_tag;

  wire d_pred_meta_p2_prm_tkn_s1 = tage_pred_meta_p2[1].tage_prm_tkn;
  wire d_pred_meta_p2_alt_tkn_s1 = tage_pred_meta_p2[1].tage_alt_tkn;

  wire d_pred_meta_p2_pred_strong_s1 = tage_pred_meta_p2[1].tage_pred_strong;
  wire d_pred_meta_p2_use_alt_on_na_s1 = tage_pred_meta_p2[1].tage_use_alt_on_na;
  wire d_pred_meta_p2_using_primary_s1 = tage_pred_meta_p2[1].tage_using_primary;
  wire d_pred_meta_p2_high_conf_s1 = tage_pred_meta_p2[1].tage_high_conf;
  wire d_pred_meta_p2_pred_tkn_s1 = tage_pred_meta_p2[1].tage_pred_tkn;
  wire [`FTQ_RNG] d_pred_meta_p2_branch_id_s1 = tage_pred_meta_p2[1].branch_id;
  // --------------------------------------------------------------------------------

  // tage_upd_inp_u0 -- top-level fields
  wire d_tage_upd_inp_u0_resolved_taken_s0  = tage_upd_inp_u0[0].resolved_taken;
  wire d_tage_upd_inp_u0_resolved_taken_s1  = tage_upd_inp_u0[1].resolved_taken;
  wire d_tage_upd_inp_u0_cond_mispredict_s0 = tage_upd_inp_u0[0].cond_mispredict;
  wire d_tage_upd_inp_u0_cond_mispredict_s1 = tage_upd_inp_u0[1].cond_mispredict;

  // tage_upd_inp_u0 -- tage_pred_meta fields (flattened)
  wire [`AW_RNG]   d_tage_upd_inp_u0_tage_prm_idx_s0       = tage_upd_inp_u0[0].tage_pred_meta.tage_prm_idx;
  wire [`AW_RNG]   d_tage_upd_inp_u0_tage_prm_idx_s1       = tage_upd_inp_u0[1].tage_pred_meta.tage_prm_idx;
  wire [`AW_RNG]   d_tage_upd_inp_u0_tage_alt_idx_s0       = tage_upd_inp_u0[0].tage_pred_meta.tage_alt_idx;
  wire [`AW_RNG]   d_tage_upd_inp_u0_tage_alt_idx_s1       = tage_upd_inp_u0[1].tage_pred_meta.tage_alt_idx;
  wire [`TSEL_RNG] d_tage_upd_inp_u0_tage_prm_comp_s0      = tage_upd_inp_u0[0].tage_pred_meta.tage_prm_comp;
  wire [`TSEL_RNG] d_tage_upd_inp_u0_tage_prm_comp_s1      = tage_upd_inp_u0[1].tage_pred_meta.tage_prm_comp;
  wire [`TSEL_RNG] d_tage_upd_inp_u0_tage_alt_comp_s0      = tage_upd_inp_u0[0].tage_pred_meta.tage_alt_comp;
  wire [`TSEL_RNG] d_tage_upd_inp_u0_tage_alt_comp_s1      = tage_upd_inp_u0[1].tage_pred_meta.tage_alt_comp;
  wire [`USE_RNG]  d_tage_upd_inp_u0_tage_prm_useful_s0    = tage_upd_inp_u0[0].tage_pred_meta.tage_prm_useful;
  wire [`USE_RNG]  d_tage_upd_inp_u0_tage_prm_useful_s1    = tage_upd_inp_u0[1].tage_pred_meta.tage_prm_useful;
  wire [`USE_RNG]  d_tage_upd_inp_u0_tage_alt_useful_s0    = tage_upd_inp_u0[0].tage_pred_meta.tage_alt_useful;
  wire [`USE_RNG]  d_tage_upd_inp_u0_tage_alt_useful_s1    = tage_upd_inp_u0[1].tage_pred_meta.tage_alt_useful;
  wire [`CTR_RNG]  d_tage_upd_inp_u0_tage_prm_ctr_s0       = tage_upd_inp_u0[0].tage_pred_meta.tage_prm_ctr;
  wire [`CTR_RNG]  d_tage_upd_inp_u0_tage_prm_ctr_s1       = tage_upd_inp_u0[1].tage_pred_meta.tage_prm_ctr;
  wire [`CTR_RNG]  d_tage_upd_inp_u0_tage_alt_ctr_s0       = tage_upd_inp_u0[0].tage_pred_meta.tage_alt_ctr;
  wire [`CTR_RNG]  d_tage_upd_inp_u0_tage_alt_ctr_s1       = tage_upd_inp_u0[1].tage_pred_meta.tage_alt_ctr;
  wire [`TSEL_RNG] d_tage_upd_inp_u0_tage_alc_comp_s0      = tage_upd_inp_u0[0].tage_pred_meta.tage_alc_comp;
  wire [`TSEL_RNG] d_tage_upd_inp_u0_tage_alc_comp_s1      = tage_upd_inp_u0[1].tage_pred_meta.tage_alc_comp;
  wire [`AW_RNG]   d_tage_upd_inp_u0_tage_alc_idx_s0       = tage_upd_inp_u0[0].tage_pred_meta.tage_alc_idx;
  wire [`AW_RNG]   d_tage_upd_inp_u0_tage_alc_idx_s1       = tage_upd_inp_u0[1].tage_pred_meta.tage_alc_idx;
  wire [`DW_RNG]   d_tage_upd_inp_u0_tage_alc_tag_s0       = tage_upd_inp_u0[0].tage_pred_meta.tage_alc_tag;
  wire [`DW_RNG]   d_tage_upd_inp_u0_tage_alc_tag_s1       = tage_upd_inp_u0[1].tage_pred_meta.tage_alc_tag;
  wire             d_tage_upd_inp_u0_tage_prm_tkn_s0       = tage_upd_inp_u0[0].tage_pred_meta.tage_prm_tkn;
  wire             d_tage_upd_inp_u0_tage_prm_tkn_s1       = tage_upd_inp_u0[1].tage_pred_meta.tage_prm_tkn;
  wire             d_tage_upd_inp_u0_tage_alt_tkn_s0       = tage_upd_inp_u0[0].tage_pred_meta.tage_alt_tkn;
  wire             d_tage_upd_inp_u0_tage_alt_tkn_s1       = tage_upd_inp_u0[1].tage_pred_meta.tage_alt_tkn;
  wire             d_tage_upd_inp_u0_tage_pred_strong_s0   = tage_upd_inp_u0[0].tage_pred_meta.tage_pred_strong;
  wire             d_tage_upd_inp_u0_tage_pred_strong_s1   = tage_upd_inp_u0[1].tage_pred_meta.tage_pred_strong;
  wire             d_tage_upd_inp_u0_tage_use_alt_on_na_s0 = tage_upd_inp_u0[0].tage_pred_meta.tage_use_alt_on_na;
  wire             d_tage_upd_inp_u0_tage_use_alt_on_na_s1 = tage_upd_inp_u0[1].tage_pred_meta.tage_use_alt_on_na;
  wire             d_tage_upd_inp_u0_tage_using_primary_s0 = tage_upd_inp_u0[0].tage_pred_meta.tage_using_primary;
  wire             d_tage_upd_inp_u0_tage_using_primary_s1 = tage_upd_inp_u0[1].tage_pred_meta.tage_using_primary;
  wire             d_tage_upd_inp_u0_tage_high_conf_s0     = tage_upd_inp_u0[0].tage_pred_meta.tage_high_conf;
  wire             d_tage_upd_inp_u0_tage_high_conf_s1     = tage_upd_inp_u0[1].tage_pred_meta.tage_high_conf;
  wire             d_tage_upd_inp_u0_tage_pred_tkn_s0      = tage_upd_inp_u0[0].tage_pred_meta.tage_pred_tkn;
  wire             d_tage_upd_inp_u0_tage_pred_tkn_s1      = tage_upd_inp_u0[1].tage_pred_meta.tage_pred_tkn;
  wire [`FTQ_RNG]  d_tage_upd_inp_u0_branch_id_s0          = tage_upd_inp_u0[0].tage_pred_meta.branch_id;
  wire [`FTQ_RNG]  d_tage_upd_inp_u0_branch_id_s1          = tage_upd_inp_u0[1].tage_pred_meta.branch_id;
  // ----------------------------------------------------------------
  // Testbench variables
  // ----------------------------------------------------------------
  int    cycle_cnt;
  logic  clk;
  logic  rstn;

  int    tb_errs = 0;
  string test_name = "";

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
  int VERB = 0; //verbose
  int TOE  = 0; //terminate on error, not typically used

  task automatic run_tests();
    if (en_ctr_test)   tage_ctr_test(.tb_errs(tb_errs),
                                     .verb(VERB),
                                     .toe(TOE));

    if (en_round_trip) tage_round_trip_sanity(.tb_errs(tb_errs),
                                     .verb(VERB),
                                     .toe(TOE));
  endtask

  // ----------------------------------------------------------------
  // Master initial statement
  // ----------------------------------------------------------------
  initial begin : tb_main
    int en_fst;
    string fst_file;

    en_fst = 0;
    fst_file = "waves.fst";

    void'($value$plusargs("EN_FST=%d",  en_fst));
    void'($value$plusargs("FST_FILE=%s",fst_file));

    if (en_fst) begin
      $dumpfile(fst_file);
      $dumpvars(0, tb);
    end

    // default signal values here

    assert_reset(4);

    // wait for ready
    while (!tage_rdy) @(posedge clk);
    @(posedge clk);

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
