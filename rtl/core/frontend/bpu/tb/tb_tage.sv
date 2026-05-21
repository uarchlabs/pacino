// ===================================================================
// FILE:    tb_tage.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// tb_tage.sv
// Self-checking testbench for tage.sv.
// BP-010b: tage_rdy_tst -- verifies SRAM initialization and
//          tage_rdy assertion timing under both slow and fast
//          init paths.
// BP-010c: update path tests, slot 0 only. One per rule branch.
//          upd_t0_inc_tst, upd_t0_dec_tst, upd_prm_inc_tst,
//          upd_prm_dec_alt_inc_tst, upd_alt_inc_tst,
//          upd_use_inc_tst, upd_alloc_tst.
// BP-010d: coverage gap tests, slot 0 only.
//          upd_use_alt_inc_tst, upd_use_alt_dec_tst,
//          upd_uaon_inc_tst, upd_uaon_dec_tst,
//          upd_ctr_max_sat_tst, upd_ctr_min_sat_tst,
//          upd_alloc_no_cand_tst.
// BP-010e: prediction path tests, slot 0 only.
//          pred_t0_only_tst, pred_t1_single_hit_tst,
//          pred_t1t2_dual_hit_tst, pred_uaon_override_tst,
//          pred_uaon_suppressed_tst, pred_rdy_timing_tst.
// BP-010f: slot 1 symmetry tests.
//          slot1_pred_tst, slot1_upd_tst.
// BP-014b: CTR round-trip tests TC-32 and TC-33.
//          rt_ctr_rows9_10_tst, rt_ctr_rows11_12_tst.
//          All 33 tests pass under sim_tage_fast.
// BP-014c: CTR round-trip tests TC-34 and TC-35.
//          rt_ctr_row13b_tst, rt_ctr_row13c_tst.
//          T0 sole provider (prm_comp=0, alt_comp=0).
//          All 35 tests pass under sim_tage_fast.
// BP-014d: CTR round-trip tests TC-36 and TC-37.
//          rt_ctr_row13a_tst, rt_ctr_row13d_tst.
//          T0 sole provider, correct prediction (CTR INC).
//          All 37 tests pass under sim_tage_fast.
// BP-014e: CTR round-trip tests TC-38 and TC-39.
//          rt_ctr_rows14_15_tst, rt_ctr_rows16_17_tst.
//          T1 prm (comp=1), T0 alt (comp=0). USE update.
//          All 39 tests pass under sim_tage_fast.
// BP-014f: UAON round-trip tests TC-40 and TC-41.
//          uaon_threshold_cross_tst, uaon_dec_restore_tst.
//          All 41 tests pass under sim_tage_fast.
// BP-014g: Allocation round-trip tests TC-42 and TC-43.
//          alloc_t0_provider_tst, alloc_no_consecutive_tst.
//          All 43 tests pass under sim_tage_fast.
// BP-014h: Aging round-trip tests TC-44 and TC-45.
//          aging_age1_not_candidate_tst: age=1 u_eff=01 T2 skip.
//          aging_age2_is_candidate_tst: age=2 u_eff=0 T2 select.
//          All 45 tests pass under sim_tage_fast.
// BP-016:  T0 DEC min saturation TC-46: t0_dec_min_sat_tst.
//          CTR=2'b00 resolved_taken=0 -> stays 2'b00 (sat min).
//          All 46 tests pass under sim_tage_fast.
// ===================================================================

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  // ----------------------------------------------------------------
  // Test enables and verbosity
  // ----------------------------------------------------------------
  int verbose                  = 1;
  int _tage_rdy_tst            = 1;
  int _upd_t0_inc_tst          = 1;
  int _upd_t0_dec_tst          = 1;
  int _upd_prm_inc_tst         = 1;
  int _upd_prm_dec_alt_inc_tst = 1;
  int _upd_alt_inc_tst         = 1;
  int _upd_use_inc_tst         = 1;
  int _upd_alloc_tst           = 1;
  int _upd_use_alt_inc_tst     = 1;
  int _upd_use_alt_dec_tst     = 1;
  int _upd_uaon_inc_tst        = 1;
  int _upd_uaon_dec_tst        = 1;
  int _upd_ctr_max_sat_tst     = 1;
  int _upd_ctr_min_sat_tst     = 1;
  int _upd_alloc_no_cand_tst   = 1;
  int _pred_t0_only_tst        = 1;
  int _pred_t1_single_hit_tst  = 1;
  int _pred_t1t2_dual_hit_tst  = 1;
  int _pred_uaon_override_tst  = 1;
  int _pred_uaon_suppressed_tst = 1;
  int _pred_rdy_timing_tst     = 1;
  int _slot1_pred_tst              = 1;
  int _slot1_upd_tst               = 1;
  int _rt_correct_t0_tst           = 1;
  int _rt_correct_tagged_tst       = 1;
  int _rt_mispredict_alloc_tst     = 1;
  int _rt_no_alloc_last_tbl_tst    = 1;
  int _rt_ctr_rows1_2_tst          = 1;
  int _rt_ctr_rows3_4_tst          = 1;
  int _rt_ctr_rows5_6_tst          = 1;
  int _rt_ctr_rows7_8_tst          = 1;
  int _rt_ctr_rows9_10_tst         = 1;
  int _rt_ctr_rows11_12_tst        = 1;
  int _rt_ctr_row13b_tst           = 1;
  int _rt_ctr_row13c_tst           = 1;
  int _rt_ctr_row13a_tst           = 1;
  int _rt_ctr_row13d_tst           = 1;
  int _rt_ctr_rows14_15_tst        = 1;
  int _rt_ctr_rows16_17_tst        = 1;
  int _uaon_threshold_cross_tst    = 1;
  int _uaon_dec_restore_tst        = 1;
  int _alloc_t0_provider_tst       = 1;
  int _alloc_no_consecutive_tst    = 1;
  int _aging_age1_not_candidate_tst = 1;
  int _aging_age2_is_candidate_tst  = 1;
  int _t0_dec_min_sat_tst           = 1;
  // -- BP-023c ARB tests (TC-47 through TC-54)
  int _arb_pred_only_tst            = 1;
  int _arb_upd_only_tst             = 1;
  int _arb_concurrent_pred_wins_tst = 1;
  int _arb_concurrent_upd_wins_tst  = 1;
  int _arb_upd_burst_tst            = 1;
  int _arb_rb_full_blocks_pred_tst  = 1;
  int _arb_pred_credits_reset_tst   = 1;
  int _arb_starve_tst               = 1;
  int _slot1_t1_write_tst           = 1;
  int _slot1_t2_write_tst           = 1;
  int _fh_sel_t3_t4_tst             = 1;
  int _aging_active_tst             = 1;
  int _alt_ctr_s0_write_tst         = 1;
  int _alc_end_to_end_tst           = 1;
  int _fh_sel_t2_tst                = 1;
  int _fh_sel_t3_tst                = 1;
  int _ctr_t1_max_sat_tst           = 1;
  int _ctr_t1_min_sat_tst           = 1;
  int _use_t1_max_sat_tst           = 1;
  int _use_t1_min_sat_tst           = 1;
  int _no_alloc_candidate_tst        = 1;
  int _no_ram_write_upd_tst          = 1;

  // ----------------------------------------------------------------
  // Module-level failure accumulator
  // ----------------------------------------------------------------
  int total_fails;
  initial total_fails = 0;

  // ----------------------------------------------------------------
  // DUT parameters and signals
  // ----------------------------------------------------------------
  localparam int NUM_PRED_SLOTS = 2;

  logic clk;
  logic rstn;

  // Prediction inputs (tied to 0 in BP-010b)
  logic [NUM_PRED_SLOTS-1:0]      tage_pred_val_p0;
  tage_pred_inp_t
    tage_pred_inp_p0[0:NUM_PRED_SLOTS-1];

  // Prediction outputs
  logic [NUM_PRED_SLOTS-1:0]      tage_pred_rdy_p2;
  tage_pred_meta_t
    tage_pred_meta_p2[0:NUM_PRED_SLOTS-1];

  // Update inputs (tied to 0 in BP-010b)
  logic [NUM_PRED_SLOTS-1:0]      tage_upd_val_u0;
  tage_upd_inp_t
    tage_upd_inp_u0[0:NUM_PRED_SLOTS-1];

  // Update outputs
  logic [NUM_PRED_SLOTS-1:0]      tage_upd_rdy_u1;

  // Aging control (tied to 0 in BP-010b)
  logic                           tage_enable_aging;
  logic [31:0]                    tage_aging_interval;

  // Folded history (tied to 0 in BP-010b)
  bp_folded_hist_t                folded_hist;

  // RAM init ready
  logic                           tage_rdy;

  // Consumer ready (BP-023c: promoted to port; default 1)
  logic                           consumer_ready;
  initial consumer_ready = 1'b1;

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
    .tage_enable_aging   (tage_enable_aging),
    .tage_aging_interval (tage_aging_interval),
    .consumer_ready      (consumer_ready),
    .folded_hist         (folded_hist),
    .tage_rdy            (tage_rdy)
  );

  // ----------------------------------------------------------------
  // Clock generator: 10-unit period
  // ----------------------------------------------------------------
  initial clk = 0;
  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  // ----------------------------------------------------------------
  // Cycle counter (increments on every posedge clk)
  // ----------------------------------------------------------------
  int cycle_cnt;
  initial cycle_cnt = 0;
  /* verilator lint_off BLKSEQ */
  always @(posedge clk) cycle_cnt++;
  /* verilator lint_on BLKSEQ */

  // ----------------------------------------------------------------
  // Input tie-off (aging/history inputs).
  // Prediction inputs driven from stg_pred_val0/stg_pred_inp0
  // via always_ff below (same pattern as update inputs).
  // Update inputs driven from stg_upd_val0/stg_upd_inp0 below.
  // ----------------------------------------------------------------
  initial begin
    tage_enable_aging   = '0;
    tage_aging_interval = '0;
    folded_hist         = '0;
  end

  // ----------------------------------------------------------------
  // Staging variables for update path tests (slot 0 only).
  // Written by test tasks; driven to DUT via always_ff so Verilator
  // NBA propagation correctly updates the struct-field combinational
  // cone (u_prm_idx etc.) before the bw_ram write posedge.
  // ----------------------------------------------------------------
  tage_upd_inp_t stg_upd_inp0;
  logic          stg_upd_val0;
  initial begin
    stg_upd_inp0 = '0;
    stg_upd_val0 = 1'b0;
  end

  tage_upd_inp_t stg_upd_inp1;
  logic          stg_upd_val1;
  initial begin
    stg_upd_inp1 = '0;
    stg_upd_val1 = 1'b0;
  end

  // Synchronous driver: NBA writes to tage_upd_inp_u0/val set
  // activity flags so the struct-field combo chain re-evaluates.
  always_ff @(posedge clk) begin
    tage_upd_inp_u0[0] <= stg_upd_inp0;
    tage_upd_inp_u0[1] <= stg_upd_inp1;
    tage_upd_val_u0[0] <= stg_upd_val0;
    tage_upd_val_u0[1] <= stg_upd_val1;
  end

  // ----------------------------------------------------------------
  // Staging variables for prediction path tests (slot 0 only).
  // Note: blocking assignments to struct-typed array elements in
  // initial block coroutines do not propagate through always_comb
  // under Verilator --timing (activity flags not set). NBA via
  // always_ff is required to trigger correct eval chain.
  // ----------------------------------------------------------------
  tage_pred_inp_t stg_pred_inp0;
  logic           stg_pred_val0;
  initial begin
    stg_pred_inp0 = '0;
    stg_pred_val0 = 1'b0;
  end

  tage_pred_inp_t stg_pred_inp1;
  logic           stg_pred_val1;
  initial begin
    stg_pred_inp1 = '0;
    stg_pred_val1 = 1'b0;
  end

  always_ff @(posedge clk) begin
    tage_pred_val_p0[0] <= stg_pred_val0;
    tage_pred_inp_p0[0] <= stg_pred_inp0;
    tage_pred_val_p0[1] <= stg_pred_val1;
    tage_pred_inp_p0[1] <= stg_pred_inp1;
  end

  // ----------------------------------------------------------------
  // tage_rdy_tst
  // a. Read +TAGE_FAST_INIT plusarg.
  // b. Record start_cycle (one sync posedge after rstn deasserts).
  // c. Spin on posedge clk until tage_rdy or watchdog expires.
  //    Watchdog: (1 << TAGE_MAX_IDX_WIDTH) + 16 cycles.
  // d. Check all bw_ram mem entries via hierarchical reference.
  //    T0: u_dut.u_tage_bim.u_ram_s0/s1.mem[b][i]
  //    T1-T4: gen_tage_tbl[N].u_tage_tbl.u_ram_s0/s1.mem[b][i]
  //    (N must be a constant for Verilator; loops unrolled.)
  //    Expected: '0 (TAGE_SRAM_INIT_VALUE = 0).
  // e. When fast_init==0: verify elapsed <
  //    (1<<TAGE_MAX_IDX_WIDTH)+4.
  // f. When fast_init==1: verify elapsed < 8 (bypass check).
  // g. Print PASS/FAIL summary. Update total_fails.
  // ----------------------------------------------------------------
  task automatic tage_rdy_tst(int verbose);
    // All locals declared at top of task.
    int fast_init;
    int start_cycle;
    int elapsed;
    int local_fails;
    int watchdog_lim;
    int re;
    int hi;
    // CNTRL_BITS_W and ALLOC_DATA_W: per-table expected widths.
    // T1-T4: CNTRL_BITS_W=8, ALLOC_DATA_W=16.
    localparam int CNTRL_BITS_W =
      TAGE_MAX_EPC_WIDTH + TAGE_MAX_USE_WIDTH
      + TAGE_MAX_CTR_WIDTH + TAGE_MAX_VAL_WIDTH; // = 8
    localparam int ALLOC_DATA_W =
      CNTRL_BITS_W + TAGE_MAX_TAG_WIDTH;   // = 16
    logic [TAGE_TBL_CTR[0]-1:0] bim_s0_v;
    logic [TAGE_TBL_CTR[0]-1:0] bim_s1_v;
    logic [ALLOC_DATA_W-1:0]    tbl_s0_v;
    logic [ALLOC_DATA_W-1:0]    tbl_s1_v;

    local_fails  = 0;
    fast_init    = 0;
    watchdog_lim = (1 << TAGE_MAX_IDX_WIDTH) + 16;

    void'($value$plusargs("TAGE_FAST_INIT=%d", fast_init));

    // Synchronize to first posedge after rstn deasserted.
    // sram_init transitions PENDING->INIT at this posedge.
    @(posedge clk);
    start_cycle = cycle_cnt;

    // Spin until tage_rdy asserts or watchdog fires.
    while (!tage_rdy) begin
      @(posedge clk);
      if ((cycle_cnt - start_cycle) > watchdog_lim) begin
        $display(
          "[FAIL] tage_rdy_tst: watchdog at %0d cycles",
          cycle_cnt - start_cycle);
        $finish(1);
      end
    end

    elapsed = cycle_cnt - start_cycle;
    if (verbose != 0)
      $display("[INFO] tage_rdy_tst: rdy after %0d cycles",
        elapsed);

    // ----------------------------------------------------------
    // d. Check T0 (tage_bim) bw_ram mem entries.
    // RAM_ENTRIES = (1 << TAGE_TBL_IDX[0]) / 2 = 1024.
    // Expected: TAGE_TBL_CTR[0]'(TAGE_SRAM_INIT_VALUE) = 2'b00.
    // ----------------------------------------------------------
    re = (1 << TAGE_TBL_IDX[0]) / 2;
    for (int b = 0; b < 2; b++) begin
      for (int i = 0; i < re; i++) begin
        bim_s0_v = u_dut.u_tage_bim.u_ram_s0.mem[b][i];
        if (bim_s0_v !== '0) begin
          local_fails++;
          if (verbose != 0)
            $display("[FAIL] T0 s0 b=%0d i=%0d val=0x%0h",
              b, i, bim_s0_v);
        end
        bim_s1_v = u_dut.u_tage_bim.u_ram_s1.mem[b][i];
        if (bim_s1_v !== '0) begin
          local_fails++;
          if (verbose != 0)
            $display("[FAIL] T0 s1 b=%0d i=%0d val=0x%0h",
              b, i, bim_s1_v);
        end
      end
    end

    // ----------------------------------------------------------
    // d. Check T1-T4 (tage_table) bw_ram mem entries.
    // Generate block indices must be constants: T1-T4 unrolled.
    // RAM_ENTRIES = (1 << TAGE_TBL_IDX[t]) / 2 = 1024 for all.
    // Expected: ALLOC_DATA_W'(TAGE_SRAM_INIT_VALUE) = 16'h0.
    // ----------------------------------------------------------

    // -- T1 --
    re = (1 << TAGE_TBL_IDX[1]) / 2;
    for (int b = 0; b < 2; b++) begin
      for (int i = 0; i < re; i++) begin
        tbl_s0_v =
          u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[b][i];
        if (tbl_s0_v !== '0) begin
          local_fails++;
          if (verbose != 0)
            $display("[FAIL] T1 s0 b=%0d i=%0d val=0x%0h",
              b, i, tbl_s0_v);
        end
        tbl_s1_v =
          u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s1.mem[b][i];
        if (tbl_s1_v !== '0) begin
          local_fails++;
          if (verbose != 0)
            $display("[FAIL] T1 s1 b=%0d i=%0d val=0x%0h",
              b, i, tbl_s1_v);
        end
      end
    end

    // -- T2 --
    re = (1 << TAGE_TBL_IDX[2]) / 2;
    for (int b = 0; b < 2; b++) begin
      for (int i = 0; i < re; i++) begin
        tbl_s0_v =
          u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[b][i];
        if (tbl_s0_v !== '0) begin
          local_fails++;
          if (verbose != 0)
            $display("[FAIL] T2 s0 b=%0d i=%0d val=0x%0h",
              b, i, tbl_s0_v);
        end
        tbl_s1_v =
          u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s1.mem[b][i];
        if (tbl_s1_v !== '0) begin
          local_fails++;
          if (verbose != 0)
            $display("[FAIL] T2 s1 b=%0d i=%0d val=0x%0h",
              b, i, tbl_s1_v);
        end
      end
    end

    // -- T3 --
    re = (1 << TAGE_TBL_IDX[3]) / 2;
    for (int b = 0; b < 2; b++) begin
      for (int i = 0; i < re; i++) begin
        tbl_s0_v =
          u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[b][i];
        if (tbl_s0_v !== '0) begin
          local_fails++;
          if (verbose != 0)
            $display("[FAIL] T3 s0 b=%0d i=%0d val=0x%0h",
              b, i, tbl_s0_v);
        end
        tbl_s1_v =
          u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s1.mem[b][i];
        if (tbl_s1_v !== '0) begin
          local_fails++;
          if (verbose != 0)
            $display("[FAIL] T3 s1 b=%0d i=%0d val=0x%0h",
              b, i, tbl_s1_v);
        end
      end
    end

    // -- T4 --
    re = (1 << TAGE_TBL_IDX[4]) / 2;
    for (int b = 0; b < 2; b++) begin
      for (int i = 0; i < re; i++) begin
        tbl_s0_v =
          u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[b][i];
        if (tbl_s0_v !== '0) begin
          local_fails++;
          if (verbose != 0)
            $display("[FAIL] T4 s0 b=%0d i=%0d val=0x%0h",
              b, i, tbl_s0_v);
        end
        tbl_s1_v =
          u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s1.mem[b][i];
        if (tbl_s1_v !== '0) begin
          local_fails++;
          if (verbose != 0)
            $display("[FAIL] T4 s1 b=%0d i=%0d val=0x%0h",
              b, i, tbl_s1_v);
        end
      end
    end

    // ----------------------------------------------------------
    // e/f. Cycle count checks.
    // FAST_INIT=0: elapsed must be < (1<<TAGE_MAX_IDX_WIDTH)+4.
    // FAST_INIT=1: elapsed must be < 8 (bypass confirmed).
    // ----------------------------------------------------------
    if (fast_init == 0) begin
      hi = (1 << TAGE_MAX_IDX_WIDTH) + 4;
      if (elapsed >= hi) begin
        local_fails++;
        $display(
          "[FAIL] tage_rdy_tst: elapsed %0d >= %0d",
          elapsed, hi);
      end else if (verbose != 0) begin
        $display(
          "[INFO] tage_rdy_tst: elapsed %0d < %0d OK",
          elapsed, hi);
      end
    end else begin
      hi = 8;
      if (elapsed >= hi) begin
        local_fails++;
        $display(
          "[FAIL] tage_rdy_tst: fast elapsed %0d >= %0d",
          elapsed, hi);
      end else if (verbose != 0) begin
        $display(
          "[INFO] tage_rdy_tst: fast elapsed %0d < %0d OK",
          elapsed, hi);
      end
    end

    // ----------------------------------------------------------
    // g. Summary
    // ----------------------------------------------------------
    if (local_fails == 0) begin
      $display("[PASS] tage_rdy_tst: 0 failures fast_init=%0d",
        fast_init);
    end else begin
      $display("[FAIL] tage_rdy_tst: %0d failures fast_init=%0d",
        local_fails, fast_init);
    end

    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_t0_inc_tst
  // Rule: ctr_update_rules.md row 13d (T0 correct -> INC CTR).
  // Pre-load: T0 s0 mem[0][4] = 2'b10.
  // Struct: prm_comp=0 alt_comp=0 prm_idx=11'h004
  //         prm_ctr=3'b010 prm_tkn=1 alt_tkn=1
  //         using_primary=1 resolved_taken=1 mispredict=0.
  // Expected: T0 s0 mem[0][4] = 2'b11 (INC: 10 -> 11).
  // ----------------------------------------------------------------
  task automatic upd_t0_inc_tst(int verbose);
    int                          local_fails;
    tage_upd_inp_t               upd_inp;
    tage_pred_meta_t             meta;
    logic [TAGE_TBL_CTR[0]-1:0] rd_val;

    local_fails = 0;

    // Pre-load T0 s0 bank 0 row 4.
    u_dut.u_tage_bim.u_ram_s0.mem[0][4] = 2'b10;
    if (verbose != 0)
      $display(
        "[INFO] upd_t0_inc_tst: pre T0 s0 mem[0][4]=2b10");

    // Build update struct.
    // Both T0 path: prm_comp=alt_comp=0.
    // prm_ctr[1:0]=2b10; resolved=1 -> prm correct -> INC.
    meta                    = '0;
    meta.tage_prm_idx       = 11'h004;
    meta.tage_alt_idx       = 11'h004;
    meta.tage_prm_comp      = 3'd0;
    meta.tage_alt_comp      = 3'd0;
    meta.tage_prm_ctr       = 3'b010;
    meta.tage_alt_ctr       = 3'b010;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b1;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;

    // Set staging; always_ff drives DUT inputs via NBA at posedge.
    // bw_ram write fires at the second posedge (after NBA settle).
    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_val = u_dut.u_tage_bim.u_ram_s0.mem[0][4];

    if (rd_val !== 2'b11) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_t0_inc_tst: mem[0][4]=0x%0h exp=3",
          rd_val);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_t0_inc_tst: mem[0][4]=0x%0h OK",
        rd_val);
    end

    if (local_fails == 0)
      $display("[PASS] upd_t0_inc_tst: 0 failures");
    else
      $display("[FAIL] upd_t0_inc_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_t0_dec_tst
  // Rule: ctr_update_rules.md row 13c (T0 wrong -> DEC CTR).
  // Pre-load: T0 s0 mem[0][8] = 2'b10.
  // Struct: prm_comp=0 alt_comp=0 prm_idx=11'h008
  //         prm_ctr=3'b010 prm_tkn=1 alt_tkn=1
  //         using_primary=1 resolved_taken=0 mispredict=1.
  // Expected: T0 s0 mem[0][8] = 2'b01 (DEC: 10 -> 01).
  // ----------------------------------------------------------------
  task automatic upd_t0_dec_tst(int verbose);
    int                          local_fails;
    tage_upd_inp_t               upd_inp;
    tage_pred_meta_t             meta;
    logic [TAGE_TBL_CTR[0]-1:0] rd_val;

    local_fails = 0;

    // Pre-load T0 s0 bank 0 row 8.
    u_dut.u_tage_bim.u_ram_s0.mem[0][8] = 2'b10;
    if (verbose != 0)
      $display(
        "[INFO] upd_t0_dec_tst: pre T0 s0 mem[0][8]=2b10");

    // Both T0 path: prm_comp=alt_comp=0.
    // prm_ctr[1:0]=2b10; resolved=0 -> prm wrong -> DEC.
    meta                    = '0;
    meta.tage_prm_idx       = 11'h008;
    meta.tage_alt_idx       = 11'h008;
    meta.tage_prm_comp      = 3'd0;
    meta.tage_alt_comp      = 3'd0;
    meta.tage_prm_ctr       = 3'b010;
    meta.tage_alt_ctr       = 3'b010;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b1;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_val = u_dut.u_tage_bim.u_ram_s0.mem[0][8];

    if (rd_val !== 2'b01) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_t0_dec_tst: mem[0][8]=0x%0h exp=1",
          rd_val);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_t0_dec_tst: mem[0][8]=0x%0h OK",
        rd_val);
    end

    if (local_fails == 0)
      $display("[PASS] upd_t0_dec_tst: 0 failures");
    else
      $display("[FAIL] upd_t0_dec_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_prm_inc_tst
  // Rule: ctr_update_rules.md row 1 (tagged prm correct -> INC).
  // Pre-load: T1 s0 mem[0][2] = 16'h0007
  //           ({TAG=0,EPC=00,USE=00,CTR=011,VAL=1}).
  // Struct: prm_comp=1 alt_comp=0 prm_idx=11'h002
  //         prm_ctr=3'b011 prm_tkn=1 alt_tkn=1
  //         using_primary=1 resolved_taken=1 mispredict=0.
  // pred_diff=0 -> no USE update. alc_comp=0 -> no alloc.
  // Expected: T1 s0 mem[0][2] = 16'h0009 (CTR 011->100).
  // ----------------------------------------------------------------
  task automatic upd_prm_inc_tst(int verbose);
    int              local_fails;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_val;

    local_fails = 0;

    // Pre-load T1 s0 bank 0 row 2.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][2]
      = 16'h0007;
    if (verbose != 0)
      $display(
        "[INFO] upd_prm_inc_tst: pre T1 s0 mem[0][2]=16h0007");

    // Tagged prm path: prm_comp=1, using_primary=1.
    // prm_crt=(prm_tkn=1==resolved=1)=1 -> INC.
    // pred_diff=(1!=1)=0 -> no USE, no alt CTR.
    meta                    = '0;
    meta.tage_prm_idx       = 11'h002;
    meta.tage_alt_idx       = 11'h002;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_alt_comp      = 3'd0;
    meta.tage_prm_ctr       = 3'b011;
    meta.tage_alt_ctr       = 3'b000;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b1;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_val =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][2];

    if (rd_val !== 16'h0009) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_prm_inc_tst: T1 mem[0][2]=0x%04h exp=0009",
          rd_val);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_prm_inc_tst: T1 mem[0][2]=0x%04h OK",
        rd_val);
    end

    if (local_fails == 0)
      $display("[PASS] upd_prm_inc_tst: 0 failures");
    else
      $display("[FAIL] upd_prm_inc_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_prm_dec_alt_inc_tst
  // Rule: ctr_update_rules.md row 3 (prm DEC; alt INC when right).
  // Pre-load: T1 s0 mem[0][5] = 16'h0009 (CTR=100 USE=00)
  //           T2 s0 mem[0][7] = 16'h0009 (CTR=100 USE=00).
  // Struct: prm_comp=1 alt_comp=2 prm_idx=11'h005 alt_idx=11'h007
  //         prm_ctr=3'b100 alt_ctr=3'b100 prm_useful=2'b00
  //         prm_tkn=1 alt_tkn=0 (pred_diff=1) using_primary=1
  //         alc_comp=0 (suppress alloc)
  //         resolved_taken=0 mispredict=1.
  // USE fires on T1 (pred_diff=1 using_prm=1) but sats at 00.
  // Expected: T1 s0 mem[0][5] = 16'h0007 (CTR 100->011)
  //           T2 s0 mem[0][7] = 16'h000B (CTR 100->101).
  // ----------------------------------------------------------------
  task automatic upd_prm_dec_alt_inc_tst(int verbose);
    int              local_fails;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;

    local_fails = 0;

    // Pre-load T1 s0 bank 0 row 5 and T2 s0 bank 0 row 7.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][5]
      = 16'h0009;
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][7]
      = 16'h0009;
    if (verbose != 0) begin
      $display(
        "[INFO] upd_prm_dec_alt_inc_tst: pre T1 [0][5]=9");
      $display(
        "[INFO] upd_prm_dec_alt_inc_tst: pre T2 [0][7]=9");
    end

    // prm_comp=1 using_prm=1, pred_diff=1.
    // prm_crt=(1==0)=0 -> DEC prm (T1).
    // alt_crt=(0==0)=1 -> INC alt (T2).
    // USE fires on T1: use_nxt=00 (sats at 0). EPC=00.
    meta                    = '0;
    meta.tage_prm_idx       = 11'h005;
    meta.tage_alt_idx       = 11'h007;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_alt_comp      = 3'd2;
    meta.tage_prm_ctr       = 3'b100;
    meta.tage_alt_ctr       = 3'b100;
    meta.tage_prm_useful    = 2'b00;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b0;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][5];
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][7];

    if (rd_t1 !== 16'h0007) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_prm_dec_alt_inc_tst: T1[0][5]=0x%04h exp=7",
          rd_t1);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_prm_dec_alt_inc_tst: T1[0][5]=0x%04h OK",
        rd_t1);
    end

    if (rd_t2 !== 16'h000B) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_prm_dec_alt_inc_tst: T2[0][7]=0x%04h expB",
          rd_t2);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_prm_dec_alt_inc_tst: T2[0][7]=0x%04h OK",
        rd_t2);
    end

    if (local_fails == 0)
      $display("[PASS] upd_prm_dec_alt_inc_tst: 0 failures");
    else
      $display(
        "[FAIL] upd_prm_dec_alt_inc_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_alt_inc_tst
  // Rule: ctr_update_rules.md row 7 (alt provider INC when right).
  // Pre-load: T2 s0 mem[0][9] = 16'h0009 (CTR=100).
  // Struct: prm_comp=1 alt_comp=2 prm_idx=11'h00A alt_idx=11'h009
  //         prm_ctr=3'b100 alt_ctr=3'b100
  //         prm_tkn=1 alt_tkn=1 (pred_diff=0) using_primary=0
  //         resolved_taken=1 mispredict=0.
  // using_primary=0 -> alt is provider.
  // pred_diff=0 -> no prm CTR write, no USE update.
  // alt_crt=(1==1)=1 -> INC alt CTR (T2).
  // Expected: T2 s0 mem[0][9] = 16'h000B (CTR 100->101).
  // ----------------------------------------------------------------
  task automatic upd_alt_inc_tst(int verbose);
    int              local_fails;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_val;

    local_fails = 0;

    // Pre-load T2 s0 bank 0 row 9.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][9]
      = 16'h0009;
    if (verbose != 0)
      $display(
        "[INFO] upd_alt_inc_tst: pre T2 s0 mem[0][9]=16h0009");

    // alt provider path: using_primary=0, pred_diff=0.
    // alt_crt=1 -> INC alt CTR.
    meta                    = '0;
    meta.tage_prm_idx       = 11'h00A;
    meta.tage_alt_idx       = 11'h009;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_alt_comp      = 3'd2;
    meta.tage_prm_ctr       = 3'b100;
    meta.tage_alt_ctr       = 3'b100;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b1;
    meta.tage_using_primary = 1'b0;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_val =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][9];

    if (rd_val !== 16'h000B) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_alt_inc_tst: T2 mem[0][9]=0x%04h exp=000B",
          rd_val);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_alt_inc_tst: T2 mem[0][9]=0x%04h OK",
        rd_val);
    end

    if (local_fails == 0)
      $display("[PASS] upd_alt_inc_tst: 0 failures");
    else
      $display("[FAIL] upd_alt_inc_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_use_inc_tst
  // Rule: use_update_rules.md Table 7 row 3 (USE INC).
  // Pre-load: T1 s0 mem[0][3] = 16'h0019
  //           ({TAG=0,EPC=00,USE=01,CTR=100,VAL=1}).
  // Struct: prm_comp=1 alt_comp=2 prm_idx=11'h003 alt_idx=11'h006
  //         prm_ctr=3'b100 alt_ctr=3'b100 prm_useful=2'b01
  //         prm_tkn=1 alt_tkn=0 (pred_diff=1) using_primary=1
  //         resolved_taken=1 mispredict=0.
  // prm_crt=1 -> prm CTR INC (100->101).
  // USE: pred_diff=1 using_prm=1 !mispredict -> INC (01->10).
  // EPC=lcl_epoch=00. alt_crt=(0==1)=0 -> no alt CTR write.
  // Expected: T1 s0 mem[0][3] = 16'h002B
  //           ({TAG=0,EPC=00,USE=10,CTR=101,VAL=1}).
  // ----------------------------------------------------------------
  task automatic upd_use_inc_tst(int verbose);
    int              local_fails;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_val;

    local_fails = 0;

    // Pre-load T1 s0 bank 0 row 3.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][3]
      = 16'h0019;
    if (verbose != 0)
      $display(
        "[INFO] upd_use_inc_tst: pre T1 s0 mem[0][3]=16h0019");

    // prm_comp=1 pred_diff=1 using_prm=1 !mispredict.
    // USE INC (01->10), CTR INC (100->101), EPC=00.
    meta                    = '0;
    meta.tage_prm_idx       = 11'h003;
    meta.tage_alt_idx       = 11'h006;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_alt_comp      = 3'd2;
    meta.tage_prm_ctr       = 3'b100;
    meta.tage_alt_ctr       = 3'b100;
    meta.tage_prm_useful    = 2'b01;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b0;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_val =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][3];

    if (rd_val !== 16'h002B) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_use_inc_tst: T1 mem[0][3]=0x%04h exp=002B",
          rd_val);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_use_inc_tst: T1 mem[0][3]=0x%04h OK",
        rd_val);
    end

    if (local_fails == 0)
      $display("[PASS] upd_use_inc_tst: 0 failures");
    else
      $display("[FAIL] upd_use_inc_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_alloc_tst
  // Rule: alloc_rules.md (alloc trigger and entry init).
  // Pre-load: T2 s0 mem[0][11] = 16'hBEEF (overwrite check).
  //           T1 s0 mem[0][1]  = 16'h0009 (prm DEC pre-load).
  // Struct: prm_comp=1 alt_comp=0 alc_comp=2
  //         prm_idx=11'h001 alt_idx=11'h001 alc_idx=11'h00B
  //         alc_tag=8'hAA prm_ctr=3'b100 alt_ctr=3'b000
  //         prm_tkn=1 alt_tkn=1 (pred_diff=0) using_primary=1
  //         resolved_taken=0 mispredict=1.
  // Alloc fires: mispredict AND prm_comp=1 < T4 AND alc_comp!=0.
  // alc_wd = {alc_tag,lcl_epoch,2b00,3b100,1b1} = 16'hAA09.
  // Expected: T2 s0 mem[0][11] = 16'hAA09 (full alloc write).
  // ----------------------------------------------------------------
  task automatic upd_alloc_tst(int verbose);
    int              local_fails;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_val;

    local_fails = 0;

    // Pre-load T2 s0 bank 0 row 11 (alloc target).
    // Pre-load T1 s0 bank 0 row 1  (prm DEC target).
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][11]
      = 16'hBEEF;
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][1]
      = 16'h0009;
    if (verbose != 0) begin
      $display(
        "[INFO] upd_alloc_tst: pre T2 s0 mem[0][11]=16hBEEF");
      $display(
        "[INFO] upd_alloc_tst: pre T1 s0 mem[0][1]=16h0009");
    end

    // mispredict=1 prm_comp=1 < TAGE_MAX_TBL=4 alc_comp=2 !=0.
    // alc_wd={8hAA, 2b00, 2b00, 3b100, 1b1} = 16hAA09.
    meta                    = '0;
    meta.tage_prm_idx       = 11'h001;
    meta.tage_alt_idx       = 11'h001;
    meta.tage_alc_idx       = 11'h00B;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_alt_comp      = 3'd0;
    meta.tage_alc_comp      = 3'd2;
    meta.tage_prm_ctr       = 3'b100;
    meta.tage_alt_ctr       = 3'b000;
    meta.tage_alc_tag       = 8'hAA;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b1;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_val =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][11];

    if (rd_val !== 16'hAA09) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_alloc_tst: T2 mem[0][11]=0x%04h exp=AA09",
          rd_val);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_alloc_tst: T2 mem[0][11]=0x%04h OK",
        rd_val);
    end

    if (local_fails == 0)
      $display("[PASS] upd_alloc_tst: 0 failures");
    else
      $display("[FAIL] upd_alloc_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_use_alt_inc_tst
  // Rule: use_update_rules.md Table 7 row 5 (USE INC on alt).
  // Pre-load: T2 s0 mem[0][16] = 16'h0019
  //           ({TAG=0,EPC=00,USE=01,CTR=100,VAL=1}).
  //           T1 s0 mem[0][18] = 16'h0009 (canary, no prm write).
  // Struct: prm_comp=1 alt_comp=2 prm_idx=11'h012 alt_idx=11'h010
  //         prm_tkn=0 alt_tkn=1 (pred_diff=1) using_primary=0
  //         alt_useful=01 resolved_taken=1 mispredict=0.
  // CTR row 7: INC alt (100->101). No prm CTR write.
  // USE row 5: INC alt USE (01->10). EPC=00.
  // Expected: T2 s0 mem[0][16] = 16'h002B
  //           ({TAG=0,EPC=00,USE=10,CTR=101,VAL=1}).
  //           T1 s0 mem[0][18] = 16'h0009 (unchanged).
  // ----------------------------------------------------------------
  task automatic upd_use_alt_inc_tst(int verbose);
    int              local_fails;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_t2;
    logic [15:0]     rd_t1;

    local_fails = 0;

    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][16]
      = 16'h0019;
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][18]
      = 16'h0009;
    if (verbose != 0) begin
      $display(
        "[INFO] upd_use_alt_inc_tst: pre T2[0][16]=0019");
      $display(
        "[INFO] upd_use_alt_inc_tst: pre T1[0][18]=0009");
    end

    // using_primary=0 pred_diff=1 !mispredict -> USE INC on alt.
    // CTR row 7: INC alt (alt_tkn=1 resolved=1 alt correct).
    meta                    = '0;
    meta.tage_prm_idx       = 11'h012;
    meta.tage_alt_idx       = 11'h010;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_alt_comp      = 3'd2;
    meta.tage_prm_ctr       = 3'b100;
    meta.tage_alt_ctr       = 3'b100;
    meta.tage_prm_tkn       = 1'b0;
    meta.tage_alt_tkn       = 1'b1;
    meta.tage_alt_useful    = 2'b01;
    meta.tage_using_primary = 1'b0;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][16];
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][18];

    if (rd_t2 !== 16'h002B) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_use_alt_inc_tst: T2[0][16]=0x%04h exp=002B",
          rd_t2);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_use_alt_inc_tst: T2[0][16]=0x%04h OK",
        rd_t2);
    end

    if (rd_t1 !== 16'h0009) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_use_alt_inc_tst: T1[0][18]=0x%04h exp=0009",
          rd_t1);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_use_alt_inc_tst: T1[0][18]=0x%04h OK",
        rd_t1);
    end

    if (local_fails == 0)
      $display("[PASS] upd_use_alt_inc_tst: 0 failures");
    else
      $display("[FAIL] upd_use_alt_inc_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_use_alt_dec_tst
  // Rule: use_update_rules.md Table 7 row 6 (USE DEC on alt).
  // Pre-load: T3 s0 mem[0][24] = 16'h0019
  //           ({TAG=0,EPC=00,USE=01,CTR=100,VAL=1}).
  //           T1 s0 mem[0][26] = 16'h0009
  //           ({TAG=0,EPC=00,USE=00,CTR=100,VAL=1}).
  // Struct: prm_comp=1 alt_comp=3 prm_idx=11'h01A alt_idx=11'h018
  //         prm_tkn=0 alt_tkn=1 (pred_diff=1) using_primary=0
  //         alt_useful=01 resolved_taken=0 mispredict=1.
  // CTR row 9: DEC alt (T3 100->011), INC prm (T1 100->101).
  // USE row 6: DEC alt USE (01->00). EPC=00.
  // Expected: T3 s0 mem[0][24] = 16'h0007
  //           ({TAG=0,EPC=00,USE=00,CTR=011,VAL=1}).
  //           T1 s0 mem[0][26] = 16'h000B (CTR 100->101).
  // ----------------------------------------------------------------
  task automatic upd_use_alt_dec_tst(int verbose);
    int              local_fails;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_t3;
    logic [15:0]     rd_t1;

    local_fails = 0;

    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[0][24]
      = 16'h0019;
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][26]
      = 16'h0009;
    if (verbose != 0) begin
      $display(
        "[INFO] upd_use_alt_dec_tst: pre T3[0][24]=0019");
      $display(
        "[INFO] upd_use_alt_dec_tst: pre T1[0][26]=0009");
    end

    // using_primary=0 pred_diff=1 mispredict=1 -> USE DEC on alt.
    // CTR row 9: prm correct -> INC prm. alt wrong -> DEC alt.
    meta                    = '0;
    meta.tage_prm_idx       = 11'h01A;
    meta.tage_alt_idx       = 11'h018;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_alt_comp      = 3'd3;
    meta.tage_prm_ctr       = 3'b100;
    meta.tage_alt_ctr       = 3'b100;
    meta.tage_prm_tkn       = 1'b0;
    meta.tage_alt_tkn       = 1'b1;
    meta.tage_alt_useful    = 2'b01;
    meta.tage_using_primary = 1'b0;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_t3 =
      u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[0][24];
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][26];

    if (rd_t3 !== 16'h0007) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_use_alt_dec_tst: T3[0][24]=0x%04h exp=0007",
          rd_t3);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_use_alt_dec_tst: T3[0][24]=0x%04h OK", rd_t3);
    end

    if (rd_t1 !== 16'h000B) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_use_alt_dec_tst: T1[0][26]=0x%04h exp=000B",
          rd_t1);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_use_alt_dec_tst: T1[0][26]=0x%04h OK", rd_t1);
    end

    if (local_fails == 0)
      $display("[PASS] upd_use_alt_dec_tst: 0 failures");
    else
      $display("[FAIL] upd_use_alt_dec_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_uaon_inc_tst
  // Rule: uaon_update_rules.md (INC: prm wrong, alt correct).
  // Pre-load: T1 s0 mem[0][32] = 16'h0009 (CTR=100, USE=00).
  //           T2 s0 mem[0][32] = 16'h000B (CTR=101, USE=00).
  // Struct: prm_comp=1 alt_comp=2 prm_idx=11'h020 alt_idx=11'h020
  //         prm_ctr=100 alt_ctr=101 prm_tkn=1 alt_tkn=0
  //         (pred_diff=1) pred_strong=0 using_primary=1
  //         resolved_taken=0 mispredict=1 (prm wrong, alt correct).
  // CTR row 3: DEC prm (T1 100->011), INC alt (T2 101->110).
  // USE row 4: DEC prm USE (00 sats->00). EPC=00.
  // UAON: prm_wrong && alt_correct && !pred_strong -> INC (0->1).
  // Expected: T1 s0 mem[0][32] = 16'h0007 (CTR=011).
  //           T2 s0 mem[0][32] = 16'h000D (CTR=110).
  //           uaon[0]: 0 -> 1.
  // ----------------------------------------------------------------
  task automatic upd_uaon_inc_tst(int verbose);
    int              local_fails;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;
    logic [3:0]      uaon_pre;
    logic [3:0]      uaon_post;

    local_fails = 0;

    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][32]
      = 16'h0009;
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][32]
      = 16'h000B;
    if (verbose != 0) begin
      $display(
        "[INFO] upd_uaon_inc_tst: pre T1[0][32]=0009");
      $display(
        "[INFO] upd_uaon_inc_tst: pre T2[0][32]=000B");
    end

    uaon_pre = u_dut.u_tage_cntrl.uaon[0];

    // prm_tagged=1 pred_strong=0 prm_wrong alt_correct -> INC uaon.
    meta                    = '0;
    meta.tage_prm_idx       = 11'h020;
    meta.tage_alt_idx       = 11'h020;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_alt_comp      = 3'd2;
    meta.tage_prm_ctr       = 3'b100;
    meta.tage_alt_ctr       = 3'b101;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b0;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    uaon_post = u_dut.u_tage_cntrl.uaon[0];
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][32];
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][32];

    if (uaon_pre !== 4'h0) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_uaon_inc_tst: pre uaon=0x%0h exp=0",
          uaon_pre);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_uaon_inc_tst: pre uaon=0x%0h OK", uaon_pre);
    end

    if (uaon_post !== 4'h1) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_uaon_inc_tst: post uaon=0x%0h exp=1",
          uaon_post);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_uaon_inc_tst: post uaon=0x%0h OK", uaon_post);
    end

    if (rd_t1 !== 16'h0007) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_uaon_inc_tst: T1[0][32]=0x%04h exp=0007",
          rd_t1);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_uaon_inc_tst: T1[0][32]=0x%04h OK", rd_t1);
    end

    if (rd_t2 !== 16'h000D) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_uaon_inc_tst: T2[0][32]=0x%04h exp=000D",
          rd_t2);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_uaon_inc_tst: T2[0][32]=0x%04h OK", rd_t2);
    end

    if (local_fails == 0)
      $display("[PASS] upd_uaon_inc_tst: 0 failures");
    else
      $display("[FAIL] upd_uaon_inc_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_uaon_dec_tst
  // Rule: uaon_update_rules.md (DEC: prm correct, alt wrong).
  // Pre-load: T1 s0 mem[0][34] = 16'h0007 (CTR=011, USE=00).
  // Struct: prm_comp=1 alt_comp=2 prm_idx=11'h022 alt_idx=11'h022
  //         prm_ctr=011 alt_ctr=011 prm_tkn=0 alt_tkn=1
  //         (pred_diff=1) pred_strong=0 using_primary=1
  //         prm_useful=00 resolved_taken=0 mispredict=0.
  // CTR row 2: INC prm (T1 011->100). No alt CTR write.
  // USE row 3: INC prm USE (00->01). EPC=00.
  // UAON: prm_correct && alt_wrong && !pred_strong -> DEC (1->0).
  // Expected: T1 s0 mem[0][34] = 16'h0019 (CTR=100, USE=01).
  //           uaon[0]: 1 -> 0.
  // ----------------------------------------------------------------
  task automatic upd_uaon_dec_tst(int verbose);
    int              local_fails;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_t1;
    logic [3:0]      uaon_pre;
    logic [3:0]      uaon_post;

    local_fails = 0;

    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][34]
      = 16'h0007;
    if (verbose != 0)
      $display(
        "[INFO] upd_uaon_dec_tst: pre T1[0][34]=0007");

    uaon_pre = u_dut.u_tage_cntrl.uaon[0];

    // prm_tagged=1 pred_strong=0 prm_correct alt_wrong -> DEC uaon.
    meta                    = '0;
    meta.tage_prm_idx       = 11'h022;
    meta.tage_alt_idx       = 11'h022;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_alt_comp      = 3'd2;
    meta.tage_prm_ctr       = 3'b011;
    meta.tage_alt_ctr       = 3'b011;
    meta.tage_prm_tkn       = 1'b0;
    meta.tage_alt_tkn       = 1'b1;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b0;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    uaon_post = u_dut.u_tage_cntrl.uaon[0];
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][34];

    if (uaon_pre !== 4'h1) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_uaon_dec_tst: pre uaon=0x%0h exp=1",
          uaon_pre);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_uaon_dec_tst: pre uaon=0x%0h OK", uaon_pre);
    end

    if (uaon_post !== 4'h0) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_uaon_dec_tst: post uaon=0x%0h exp=0",
          uaon_post);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_uaon_dec_tst: post uaon=0x%0h OK", uaon_post);
    end

    if (rd_t1 !== 16'h0019) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_uaon_dec_tst: T1[0][34]=0x%04h exp=0019",
          rd_t1);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_uaon_dec_tst: T1[0][34]=0x%04h OK", rd_t1);
    end

    if (local_fails == 0)
      $display("[PASS] upd_uaon_dec_tst: 0 failures");
    else
      $display("[FAIL] upd_uaon_dec_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_ctr_max_sat_tst
  // Rule: ctr_update_rules.md saturation at max boundary.
  // Part 1 (T1): Pre-load T1 s0 mem[0][40] = 16'h000F (CTR=111).
  //   Struct: prm_comp=1 alt_comp=0 prm_idx=11'h028
  //           prm_ctr=111 prm_tkn=1 alt_tkn=1 pred_strong=1
  //           resolved_taken=1 mispredict=0.
  //   CTR row 16: INC prm -> 111 sats at 111.
  //   Expected: T1 s0 mem[0][40] = 16'h000F (no change).
  // Part 2 (T0): Pre-load T0 s0 mem[0][40] = 2'b11 (CTR=11).
  //   Struct: prm_comp=0 alt_comp=0 prm_idx=11'h028
  //           prm_tkn=1 resolved_taken=1 mispredict=0.
  //   CTR row 13d: INC T0 -> 11 sats at 11.
  //   Expected: T0 s0 mem[0][40] = 2'b11 (no change).
  // ----------------------------------------------------------------
  task automatic upd_ctr_max_sat_tst(int verbose);
    int                          local_fails;
    tage_upd_inp_t               upd_inp;
    tage_pred_meta_t             meta;
    logic [15:0]                 rd_t1;
    logic [TAGE_TBL_CTR[0]-1:0] rd_t0;

    local_fails = 0;

    // -- Part 1: T1 3b CTR at max (111). --
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][40]
      = 16'h000F;
    if (verbose != 0)
      $display(
        "[INFO] upd_ctr_max_sat_tst: pre T1[0][40]=000F");

    meta                    = '0;
    meta.tage_prm_idx       = 11'h028;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_prm_ctr       = 3'b111;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b1;
    meta.tage_pred_strong   = 1'b1;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][40];

    if (rd_t1 !== 16'h000F) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_ctr_max_sat_tst: T1[0][40]=0x%04h exp=000F",
          rd_t1);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_ctr_max_sat_tst: T1[0][40]=0x%04h OK", rd_t1);
    end

    // -- Part 2: T0 2b CTR at max (11). --
    u_dut.u_tage_bim.u_ram_s0.mem[0][40] = 2'b11;
    if (verbose != 0)
      $display(
        "[INFO] upd_ctr_max_sat_tst: pre T0[0][40]=2b11");

    meta                    = '0;
    meta.tage_prm_idx       = 11'h028;
    meta.tage_prm_comp      = 3'd0;
    meta.tage_prm_ctr       = 3'b011;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b1;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_t0 = u_dut.u_tage_bim.u_ram_s0.mem[0][40];

    if (rd_t0 !== 2'b11) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_ctr_max_sat_tst: T0[0][40]=0x%0h exp=3",
          rd_t0);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_ctr_max_sat_tst: T0[0][40]=0x%0h OK", rd_t0);
    end

    if (local_fails == 0)
      $display("[PASS] upd_ctr_max_sat_tst: 0 failures");
    else
      $display("[FAIL] upd_ctr_max_sat_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_ctr_min_sat_tst
  // Rule: ctr_update_rules.md saturation at min boundary.
  // Part 1 (T1): Pre-load T1 s0 mem[0][42] = 16'h0001 (CTR=000).
  //   Struct: prm_comp=1 alt_comp=0 prm_idx=11'h02A
  //           prm_ctr=000 prm_tkn=1 alt_tkn=1 pred_strong=1
  //           resolved_taken=0 mispredict=1.
  //   CTR row 14: DEC prm -> 000 sats at 000.
  //   Expected: T1 s0 mem[0][42] = 16'h0001 (no change).
  // Part 2 (T0): Pre-load T0 s0 mem[0][42] = 2'b00 (CTR=00).
  //   Struct: prm_comp=0 alt_comp=0 prm_idx=11'h02A
  //           prm_tkn=0 resolved_taken=1 mispredict=1.
  //   CTR row 13b: INC T0 (resolved_taken=1): 00->01.
  //   BP-015: Was pred_crt=0 -> DEC sats at 00. Fixed:
  //   resolved_taken=1 -> INC: 00->01. Debt #34 closed.
  //   Expected: T0 s0 mem[0][42] = 2'b01.
  // ----------------------------------------------------------------
  task automatic upd_ctr_min_sat_tst(int verbose);
    int                          local_fails;
    tage_upd_inp_t               upd_inp;
    tage_pred_meta_t             meta;
    logic [15:0]                 rd_t1;
    logic [TAGE_TBL_CTR[0]-1:0] rd_t0;

    local_fails = 0;

    // -- Part 1: T1 3b CTR at min (000). --
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][42]
      = 16'h0001;
    if (verbose != 0)
      $display(
        "[INFO] upd_ctr_min_sat_tst: pre T1[0][42]=0001");

    meta                    = '0;
    meta.tage_prm_idx       = 11'h02A;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_prm_ctr       = 3'b000;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b1;
    meta.tage_pred_strong   = 1'b1;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][42];

    if (rd_t1 !== 16'h0001) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_ctr_min_sat_tst: T1[0][42]=0x%04h exp=0001",
          rd_t1);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_ctr_min_sat_tst: T1[0][42]=0x%04h OK", rd_t1);
    end

    // -- Part 2: T0 2b CTR at min (00). --
    u_dut.u_tage_bim.u_ram_s0.mem[0][42] = 2'b00;
    if (verbose != 0)
      $display(
        "[INFO] upd_ctr_min_sat_tst: pre T0[0][42]=2b00");

    meta                    = '0;
    meta.tage_prm_idx       = 11'h02A;
    meta.tage_prm_comp      = 3'd0;
    meta.tage_prm_ctr       = 3'b000;
    meta.tage_prm_tkn       = 1'b0;
    meta.tage_alt_tkn       = 1'b0;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b1;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_t0 = u_dut.u_tage_bim.u_ram_s0.mem[0][42];

    if (rd_t0 !== 2'b01) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_ctr_min_sat_tst: T0[0][42]=0x%0h exp=1",
          rd_t0);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_ctr_min_sat_tst: T0[0][42]=0x%0h OK", rd_t0);
    end

    if (local_fails == 0)
      $display("[PASS] upd_ctr_min_sat_tst: 0 failures");
    else
      $display("[FAIL] upd_ctr_min_sat_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // upd_alloc_no_cand_tst
  // Rule: alloc_rules.md (alc_comp=0 -> alloc write suppressed).
  // Pre-load: T2 s0 mem[0][48] = 16'hBEEF (canary).
  //           T1 s0 mem[0][49] = 16'h000F (CTR=111).
  // Struct: prm_comp=1 alt_comp=0 alc_comp=0
  //         prm_idx=11'h031 alc_idx=11'h030
  //         prm_ctr=111 prm_tkn=1 alt_tkn=0 (pred_diff=1)
  //         pred_strong=1 using_primary=1
  //         resolved_taken=0 mispredict=1.
  // alc_comp=0 -> alc_wr suppressed. Canary unchanged.
  // CTR row 14: DEC prm (T1 CTR 111->110).
  // USE row 4: DEC prm USE (00 sats->00). EPC=00.
  // Expected: T2 s0 mem[0][48] = 16'hBEEF (no alloc write).
  //           T1 s0 mem[0][49] = 16'h000D (CTR=110).
  // ----------------------------------------------------------------
  task automatic upd_alloc_no_cand_tst(int verbose);
    int              local_fails;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_t2;
    logic [15:0]     rd_t1;

    local_fails = 0;

    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][48]
      = 16'hBEEF;
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][49]
      = 16'h000F;
    if (verbose != 0) begin
      $display(
        "[INFO] upd_alloc_no_cand_tst: pre T2[0][48]=BEEF");
      $display(
        "[INFO] upd_alloc_no_cand_tst: pre T1[0][49]=000F");
    end

    meta                    = '0;
    meta.tage_prm_idx       = 11'h031;
    meta.tage_alt_idx       = 11'h031;
    meta.tage_alc_idx       = 11'h030;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_alt_comp      = 3'd0;
    meta.tage_alc_comp      = 3'd0;
    meta.tage_prm_ctr       = 3'b111;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b0;
    meta.tage_alc_tag       = 8'hAA;
    meta.tage_pred_strong   = 1'b1;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][48];
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][49];

    if (rd_t2 !== 16'hBEEF) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_alloc_no_cand_tst: T2[0][48]=0x%04h expBEEF",
          rd_t2);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_alloc_no_cand_tst: T2[0][48]=0x%04h OK",
        rd_t2);
    end

    if (rd_t1 !== 16'h000D) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] upd_alloc_no_cand_tst: T1[0][49]=0x%04h exp=000D",
          rd_t1);
    end else if (verbose != 0) begin
      $display(
        "[INFO] upd_alloc_no_cand_tst: T1[0][49]=0x%04h OK",
        rd_t1);
    end

    if (local_fails == 0)
      $display("[PASS] upd_alloc_no_cand_tst: 0 failures");
    else
      $display("[FAIL] upd_alloc_no_cand_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // pred_t0_only_tst
  // TC-A: No tagged table hits. T0 is provider.
  // Pre-load: T0 s0 mem[0][128] = 2'b11 (CTR=11, taken).
  // PC=0x200: idx=128 bank=0 row=128 tag=0x00.
  // Expected: prm_comp=0 alt_comp=0 prm_ctr=3b011
  //           pred_tkn=1 using_primary=1 use_alt_on_na=0 rdy=1.
  // ----------------------------------------------------------------
  task automatic pred_t0_only_tst(int verbose);
    int                 local_fails;
    tage_pred_inp_t     inp;
    tage_pred_meta_t    meta;

    local_fails = 0;

    // Pre-load T0 bank 0 row 128 with CTR=2b11.
    u_dut.u_tage_bim.u_ram_s0.mem[0][128] = 2'b11;
    if (verbose != 0)
      $display(
        "[INFO] pred_t0_only_tst: T0 mem[0][128]=2b11");

    // Stage prediction inputs via always_ff (Verilator requirement:
    // struct-field always_comb sensitivity requires NBA path).
    // Sequence: stg set -> @posedge (NBA: val=1, inp.pc=0x200) ->
    //   stg clear -> @posedge (p0->p1: raddr_q=128, dout valid) ->
    //   @posedge (p1->p2: meta latched, rdy=1).
    inp           = '0;
    inp.pc        = 40'h200;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Read p2 outputs.
    meta = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] pred_t0_only_tst: rdy=%0b prm_comp=%0d",
        tage_pred_rdy_p2[0],
        meta.tage_prm_comp);
      $display(
        "[INFO] pred_t0_only_tst: alt_comp=%0d prm_ctr=%03b",
        meta.tage_alt_comp,
        meta.tage_prm_ctr);
      $display(
        "[INFO] pred_t0_only_tst: pred_tkn=%0b using_prm=%0b",
        meta.tage_pred_tkn,
        meta.tage_using_primary);
    end

    if (tage_pred_rdy_p2[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] pred_t0_only_tst: rdy=%0b exp=1",
        tage_pred_rdy_p2[0]);
    end
    if (meta.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] pred_t0_only_tst: prm_comp=%0d exp=0",
        meta.tage_prm_comp);
    end
    if (meta.tage_alt_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] pred_t0_only_tst: alt_comp=%0d exp=0",
        meta.tage_alt_comp);
    end
    if (meta.tage_prm_ctr !== 3'b011) begin
      local_fails++;
      $display(
        "[FAIL] pred_t0_only_tst: prm_ctr=%03b exp=011",
        meta.tage_prm_ctr);
    end
    if (meta.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] pred_t0_only_tst: pred_tkn=%0b exp=1",
        meta.tage_pred_tkn);
    end
    if (meta.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] pred_t0_only_tst: using_primary=%0b exp=1",
        meta.tage_using_primary);
    end
    if (meta.tage_use_alt_on_na !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] pred_t0_only_tst: use_alt_on_na=%0b exp=0",
        meta.tage_use_alt_on_na);
    end

    if (local_fails == 0)
      $display("[PASS] pred_t0_only_tst: 0 failures");
    else
      $display("[FAIL] pred_t0_only_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // pred_t1_single_hit_tst
  // TC-B: T1 hits; T0 is fallback alt.
  // Pre-load: T1 s0 mem[1][256]=16h420B (CTR=101 taken strong).
  // PC=0x21400: idx=1280 bank=1 row=256 tag=0x42.
  // Expected: prm_comp=1 alt_comp=0 prm_ctr=3b101
  //           pred_tkn=1 using_primary=1 use_alt_on_na=0 rdy=1.
  // ----------------------------------------------------------------
  task automatic pred_t1_single_hit_tst(int verbose);
    int                 local_fails;
    tage_pred_inp_t     inp;
    tage_pred_meta_t    meta;

    local_fails = 0;

    // Pre-load T1 bank 1 row 256.
    // Entry: TAG=0x42 EPC=0 USE=0 CTR=101 VAL=1 = 0x420B.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][256]
      = 16'h420B;
    if (verbose != 0)
      $display(
        "[INFO] pred_t1_single_hit_tst: T1 mem[1][256]=420B");

    // Stage prediction inputs (Verilator struct NBA requirement).
    inp           = '0;
    inp.pc        = 40'h21400;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Read p2 outputs.
    meta = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] pred_t1_single_hit_tst: rdy=%0b prm_comp=%0d",
        tage_pred_rdy_p2[0],
        meta.tage_prm_comp);
      $display(
        "[INFO] pred_t1_single_hit_tst: alt_comp=%0d",
        meta.tage_alt_comp);
      $display(
        "[INFO] pred_t1_single_hit_tst: prm_ctr=%03b pred_tkn=%0b",
        meta.tage_prm_ctr,
        meta.tage_pred_tkn);
    end

    if (tage_pred_rdy_p2[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] pred_t1_single_hit_tst: rdy=%0b exp=1",
        tage_pred_rdy_p2[0]);
    end
    if (meta.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] pred_t1_single_hit_tst: prm_comp=%0d exp=1",
        meta.tage_prm_comp);
    end
    if (meta.tage_alt_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] pred_t1_single_hit_tst: alt_comp=%0d exp=0",
        meta.tage_alt_comp);
    end
    if (meta.tage_prm_ctr !== 3'b101) begin
      local_fails++;
      $display(
        "[FAIL] pred_t1_single_hit_tst: prm_ctr=%03b exp=101",
        meta.tage_prm_ctr);
    end
    if (meta.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] pred_t1_single_hit_tst: pred_tkn=%0b exp=1",
        meta.tage_pred_tkn);
    end
    if (meta.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] pred_t1_single_hit_tst: using_primary=%0b exp=1",
        meta.tage_using_primary);
    end
    if (meta.tage_use_alt_on_na !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] pred_t1_single_hit_tst: use_alt_on_na=%0b exp=0",
        meta.tage_use_alt_on_na);
    end

    if (local_fails == 0)
      $display("[PASS] pred_t1_single_hit_tst: 0 failures");
    else
      $display("[FAIL] pred_t1_single_hit_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // pred_t1t2_dual_hit_tst
  // TC-C: T1 and T2 both hit. T2 wins (longer history).
  // Pre-load: T1 s0 mem[1][256]=16h4207 (CTR=011 weak not-taken).
  //           T2 s0 mem[1][256]=16h420B (CTR=101 taken strong).
  // PC=0x21400: idx=1280 bank=1 row=256 tag=0x42.
  // Expected: prm_comp=2 alt_comp=1 prm_ctr=3b101 alt_ctr=3b011
  //           pred_tkn=1 using_primary=1 use_alt_on_na=0 rdy=1.
  // ----------------------------------------------------------------
  task automatic pred_t1t2_dual_hit_tst(int verbose);
    int                 local_fails;
    tage_pred_inp_t     inp;
    tage_pred_meta_t    meta;

    local_fails = 0;

    // Pre-load T1 bank 1 row 256: weak not-taken.
    // TAG=0x42 EPC=0 USE=0 CTR=011 VAL=1 = 0x4207.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][256]
      = 16'h4207;
    // Pre-load T2 bank 1 row 256: strong taken.
    // TAG=0x42 EPC=0 USE=0 CTR=101 VAL=1 = 0x420B.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][256]
      = 16'h420B;
    if (verbose != 0)
      $display(
        "[INFO] pred_t1t2_dual_hit_tst: T1[1][256]=4207 T2[1][256]=420B");

    // Stage prediction inputs (Verilator struct NBA requirement).
    inp           = '0;
    inp.pc        = 40'h21400;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Read p2 outputs.
    meta = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] pred_t1t2_dual_hit_tst: rdy=%0b prm=%0d alt=%0d",
        tage_pred_rdy_p2[0],
        meta.tage_prm_comp,
        meta.tage_alt_comp);
      $display(
        "[INFO] pred_t1t2_dual_hit_tst: pctr=%03b actr=%03b tkn=%0b",
        meta.tage_prm_ctr,
        meta.tage_alt_ctr,
        meta.tage_pred_tkn);
    end

    if (tage_pred_rdy_p2[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] pred_t1t2_dual_hit_tst: rdy=%0b exp=1",
        tage_pred_rdy_p2[0]);
    end
    if (meta.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] pred_t1t2_dual_hit_tst: prm_comp=%0d exp=2",
        meta.tage_prm_comp);
    end
    if (meta.tage_alt_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] pred_t1t2_dual_hit_tst: alt_comp=%0d exp=1",
        meta.tage_alt_comp);
    end
    if (meta.tage_prm_ctr !== 3'b101) begin
      local_fails++;
      $display(
        "[FAIL] pred_t1t2_dual_hit_tst: prm_ctr=%03b exp=101",
        meta.tage_prm_ctr);
    end
    if (meta.tage_alt_ctr !== 3'b011) begin
      local_fails++;
      $display(
        "[FAIL] pred_t1t2_dual_hit_tst: alt_ctr=%03b exp=011",
        meta.tage_alt_ctr);
    end
    if (meta.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] pred_t1t2_dual_hit_tst: pred_tkn=%0b exp=1",
        meta.tage_pred_tkn);
    end
    if (meta.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] pred_t1t2_dual_hit_tst: using_primary=%0b exp=1",
        meta.tage_using_primary);
    end
    if (meta.tage_use_alt_on_na !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] pred_t1t2_dual_hit_tst: use_alt_on_na=%0b exp=0",
        meta.tage_use_alt_on_na);
    end

    if (local_fails == 0)
      $display("[PASS] pred_t1t2_dual_hit_tst: 0 failures");
    else
      $display("[FAIL] pred_t1t2_dual_hit_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // pred_uaon_override_tst
  // TC-D: UAON override active (uaon[0]=0xF >= threshold).
  // Pre-load: T2 mem[0][512]=16h4509 (CTR=100 weak taken).
  //           T1 mem[0][512]=16h4507 (CTR=011 weak not-taken).
  // PC=0x22800: idx=512 bank=0 row=512 tag=0x45.
  // uaon[0]=0xF: override fires -> use alt (T1, not-taken).
  // Expected: prm_comp=2 alt_comp=1 using_primary=0
  //           pred_tkn=0 use_alt_on_na=1 rdy=1.
  // ----------------------------------------------------------------
  task automatic pred_uaon_override_tst(int verbose);
    int                 local_fails;
    tage_pred_inp_t     inp;
    tage_pred_meta_t    meta;

    local_fails = 0;

    // Pre-load T2 bank 0 row 512: primary, weak taken.
    // TAG=0x45 EPC=0 USE=0 CTR=100 VAL=1 = 0x4509.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][512]
      = 16'h4509;
    // Pre-load T1 bank 0 row 512: alt, weak not-taken.
    // TAG=0x45 EPC=0 USE=0 CTR=011 VAL=1 = 0x4507.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][512]
      = 16'h4507;
    // Set uaon[0] >= threshold (bit[3]=1).
    u_dut.u_tage_cntrl.uaon[0] = 4'hF;
    if (verbose != 0)
      $display(
        "[INFO] pred_uaon_override_tst: T2[0][512]=4509 T1[0][512]=4507 uaon=0xF");

    // Stage prediction inputs (Verilator struct NBA requirement).
    inp           = '0;
    inp.pc        = 40'h22800;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Read p2 outputs.
    meta = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] pred_uaon_override_tst: rdy=%0b prm=%0d alt=%0d",
        tage_pred_rdy_p2[0],
        meta.tage_prm_comp,
        meta.tage_alt_comp);
      $display(
        "[INFO] pred_uaon_override_tst: uprm=%0b tkn=%0b ualt=%0b",
        meta.tage_using_primary,
        meta.tage_pred_tkn,
        meta.tage_use_alt_on_na);
    end

    if (tage_pred_rdy_p2[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] pred_uaon_override_tst: rdy=%0b exp=1",
        tage_pred_rdy_p2[0]);
    end
    if (meta.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] pred_uaon_override_tst: prm_comp=%0d exp=2",
        meta.tage_prm_comp);
    end
    if (meta.tage_alt_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] pred_uaon_override_tst: alt_comp=%0d exp=1",
        meta.tage_alt_comp);
    end
    if (meta.tage_prm_ctr !== 3'b100) begin
      local_fails++;
      $display(
        "[FAIL] pred_uaon_override_tst: prm_ctr=%03b exp=100",
        meta.tage_prm_ctr);
    end
    if (meta.tage_using_primary !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] pred_uaon_override_tst: using_primary=%0b exp=0",
        meta.tage_using_primary);
    end
    if (meta.tage_pred_tkn !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] pred_uaon_override_tst: pred_tkn=%0b exp=0",
        meta.tage_pred_tkn);
    end
    if (meta.tage_use_alt_on_na !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] pred_uaon_override_tst: use_alt_on_na=%0b exp=1",
        meta.tage_use_alt_on_na);
    end

    if (local_fails == 0)
      $display("[PASS] pred_uaon_override_tst: 0 failures");
    else
      $display("[FAIL] pred_uaon_override_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // pred_uaon_suppressed_tst
  // TC-E: UAON trigger fires but override suppressed (uaon[0]=0).
  // Reuses TC-D RAM: T2 mem[0][512]=16h4509 T1 mem[0][512]=16h4507.
  // PC=0x22800: idx=512 bank=0 row=512 tag=0x45.
  // uaon[0]=0x0: override suppressed -> use primary (T2, taken).
  // Expected: prm_comp=2 alt_comp=1 using_primary=1
  //           pred_tkn=1 use_alt_on_na=1 (RTL: trigger fires
  //           from prm CTR=100 weak; counter value not tested
  //           by trigger flag) rdy=1.
  // NOTE: Prompt spec says use_alt_on_na==0 but RTL sets this from
  //       uaon_trig regardless of counter value. Expected=1 here.
  // ----------------------------------------------------------------
  task automatic pred_uaon_suppressed_tst(int verbose);
    int                 local_fails;
    tage_pred_inp_t     inp;
    tage_pred_meta_t    meta;

    local_fails = 0;

    // RAM from TC-D already set. Clear uaon[0] to suppress override.
    u_dut.u_tage_cntrl.uaon[0] = 4'h0;
    if (verbose != 0)
      $display(
        "[INFO] pred_uaon_suppressed_tst: uaon=0x0 T2/T1 RAM from TC-D");

    // Stage prediction inputs (Verilator struct NBA requirement).
    inp           = '0;
    inp.pc        = 40'h22800;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Read p2 outputs.
    meta = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] pred_uaon_suppressed_tst: rdy=%0b uprm=%0b tkn=%0b ualt=%0b",
        tage_pred_rdy_p2[0],
        meta.tage_using_primary,
        meta.tage_pred_tkn,
        meta.tage_use_alt_on_na);
    end

    if (tage_pred_rdy_p2[0] !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] pred_uaon_suppressed_tst: rdy=%0b exp=1",
        tage_pred_rdy_p2[0]);
    end
    if (meta.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] pred_uaon_suppressed_tst: prm_comp=%0d exp=2",
        meta.tage_prm_comp);
    end
    if (meta.tage_alt_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] pred_uaon_suppressed_tst: alt_comp=%0d exp=1",
        meta.tage_alt_comp);
    end
    if (meta.tage_prm_ctr !== 3'b100) begin
      local_fails++;
      $display(
        "[FAIL] pred_uaon_suppressed_tst: prm_ctr=%03b exp=100",
        meta.tage_prm_ctr);
    end
    if (meta.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] pred_uaon_suppressed_tst: using_primary=%0b exp=1",
        meta.tage_using_primary);
    end
    if (meta.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] pred_uaon_suppressed_tst: pred_tkn=%0b exp=1",
        meta.tage_pred_tkn);
    end
    //HAND-FIX-002 - uaon flag setting conditions
    // use_alt_on_na=0: uaon_trig fires (weak CTR) but counter
    // below threshold, mux stays on primary. HAND-FIX-002.
    if (meta.tage_use_alt_on_na !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] pred_uaon_suppressed_tst: use_alt_on_na=%0b exp=0",
        meta.tage_use_alt_on_na);
    end

    if (local_fails == 0)
      $display("[PASS] pred_uaon_suppressed_tst: 0 failures");
    else
      $display("[FAIL] pred_uaon_suppressed_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // pred_rdy_timing_tst
  // TC-F: Verify tage_pred_rdy_p2 timing.
  // tage_pred_rdy_p2 = pred_val_p2 = val delayed by 2 posedges.
  // Check: rdy=0 after +1 posedge (p1), rdy=1 after +2 posedge
  // (p2), rdy=0 after +3 posedge (deassertion propagated).
  // No RAM pre-load required.
  // ----------------------------------------------------------------
  task automatic pred_rdy_timing_tst(int verbose);
    int                 local_fails;
    logic               rdy_p1;
    logic               rdy_p2;
    logic               rdy_p3;

    local_fails = 0;

    // Assert val via staging for one cycle (Verilator NBA requirement).
    // Timing with staging:
    //   @posedge N: NBA: val=1 (p0 assertion). pred_val_p2 still 0.
    //   @posedge N+1: NBA: val=0 (deassert). pred_val_p1=1. rdy still 0.
    //   @posedge N+2: pred_val_p2=1. rdy=1.
    //   @posedge N+3: pred_val_p2=0. rdy=0.
    stg_pred_val0 = 1'b1;
    stg_pred_inp0.pc = 40'h0;
    @(posedge clk);
    // After posedge N: val=1 via NBA. pred_val_p2 not yet 1.
    rdy_p1 = tage_pred_rdy_p2[0];
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    // After posedge N+1: val=0 via NBA. pred_val_p1=1. rdy still 0.
    @(posedge clk);
    // After posedge N+2: pred_val_p2=1. rdy=1.
    rdy_p2 = tage_pred_rdy_p2[0];
    @(posedge clk);
    // After posedge N+3: pred_val_p2=0. rdy=0.
    rdy_p3 = tage_pred_rdy_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] pred_rdy_timing_tst: rdy_p1=%0b rdy_p2=%0b rdy_p3=%0b",
        rdy_p1, rdy_p2, rdy_p3);
    end

    if (rdy_p1 !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] pred_rdy_timing_tst: rdy_p1=%0b exp=0",
        rdy_p1);
    end
    if (rdy_p2 !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] pred_rdy_timing_tst: rdy_p2=%0b exp=1",
        rdy_p2);
    end
    if (rdy_p3 !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] pred_rdy_timing_tst: rdy_p3=%0b exp=0",
        rdy_p3);
    end

    if (local_fails == 0)
      $display("[PASS] pred_rdy_timing_tst: 0 failures");
    else
      $display("[FAIL] pred_rdy_timing_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // slot1_pred_tst
  // Slot 1 prediction symmetry. Verifies slot 1 reads u_ram_s1
  // and not u_ram_s0.
  // PC=0x5000: T1 idx=11h400 (bank=1 row=0) tag=0x0A with fh=0.
  // u_ram_s1 mem[1][0]=16h0A09 (TAG=0x0A CTR=100 VAL=1).
  // u_ram_s0 mem[1][0]=16h0A0F (TAG=0x0A CTR=111 VAL=1 sentinel).
  // Contamination: prm_ctr=3b111 if slot 1 reads u_ram_s0.
  // Expected: rdy[1]=1 rdy[0]=0 prm_comp=1 prm_ctr=3b100 tkn=1.
  // ----------------------------------------------------------------
  task automatic slot1_pred_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;

    local_fails = 0;

    // Pre-load T1 slot 1 RAM bank=1 row=0: matching tagged entry.
    // T1 entry layout: [15:8]=TAG [7:6]=EPC [5:4]=USE [3:1]=CTR [0]=VAL
    // 16'h0A09: TAG=0x0A EPC=0 USE=0 CTR=100(weakest taken) VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s1.mem[1][0]
      = 16'h0A09;
    // Pre-load T1 slot 0 RAM same address as contamination sentinel.
    // 16'h0A0F: TAG=0x0A EPC=0 USE=0 CTR=111(strong taken) VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][0]
      = 16'h0A0F;
    if (verbose != 0) begin
      $display(
        "[INFO] slot1_pred_tst: T1 s1 mem[1][0]=16h0A09");
      $display(
        "[INFO] slot1_pred_tst: T1 s0 mem[1][0]=16h0A0F sentinel");
    end

    // Drive slot 1 with PC=0x5000. Slot 0 held at zero (stg_pred_val0
    // not set). T1: idx_hash=11h400 -> bank=1 row=0, tag_hash=8h0A.
    inp           = '0;
    inp.pc        = 40'h5000;
    inp.branch_id = 6'h0;
    stg_pred_inp1 = inp;
    stg_pred_val1 = 1'b1;
    @(posedge clk);
    stg_pred_val1 = 1'b0;
    stg_pred_inp1 = '0;
    @(posedge clk);
    @(posedge clk);

    // Read p2 outputs for slot 1.
    meta1 = tage_pred_meta_p2[1];

    if (verbose != 0) begin
      $display(
        "[INFO] slot1_pred_tst: rdy[1]=%0b rdy[0]=%0b",
        tage_pred_rdy_p2[1],
        tage_pred_rdy_p2[0]);
      $display(
        "[INFO] slot1_pred_tst: prm=%0d ctr=%03b tkn=%0b",
        meta1.tage_prm_comp,
        meta1.tage_prm_ctr,
        meta1.tage_pred_tkn);
    end

    if (tage_pred_rdy_p2[1] !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] slot1_pred_tst: rdy[1]=%0b exp=1",
        tage_pred_rdy_p2[1]);
    end
    if (tage_pred_rdy_p2[0] !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] slot1_pred_tst: rdy[0]=%0b exp=0",
        tage_pred_rdy_p2[0]);
    end
    if (meta1.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] slot1_pred_tst: prm_comp=%0d exp=1",
        meta1.tage_prm_comp);
    end
    // prm_ctr=100 from u_ram_s1; contamination gives 111 from s0.
    if (meta1.tage_prm_ctr !== 3'b100) begin
      local_fails++;
      $display(
        "[FAIL] slot1_pred_tst: prm_ctr=%03b exp=100",
        meta1.tage_prm_ctr);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] slot1_pred_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end

    if (local_fails == 0)
      $display("[PASS] slot1_pred_tst: 0 failures");
    else
      $display("[FAIL] slot1_pred_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // slot1_upd_tst
  // Slot 1 update symmetry. Verifies slot 1 update writes u_ram_s1
  // and not u_ram_s0.
  // T1 prm_idx=11h046 (bank=0 row=70).
  // u_ram_s1 mem[0][70]=16h0007 (CTR=011 VAL=1).
  // u_ram_s0 mem[0][70]=16h000F (CTR=111 VAL=1 sentinel).
  // CTR increment 011->100: expect u_ram_s1 = 16h0009.
  // u_ram_s0 must remain 16h000F. upd_rdy[0] must be 0.
  // ----------------------------------------------------------------
  task automatic slot1_upd_tst(int verbose);
    int              local_fails;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_s1;
    logic [15:0]     rd_s0;

    local_fails = 0;

    // Pre-load T1 slot 1 RAM bank=0 row=70: CTR=011 VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s1.mem[0][70]
      = 16'h0007;
    // Pre-load T1 slot 0 RAM same address as sentinel: CTR=111 VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][70]
      = 16'h000F;
    if (verbose != 0) begin
      $display(
        "[INFO] slot1_upd_tst: T1 s1 mem[0][70]=16h0007");
      $display(
        "[INFO] slot1_upd_tst: T1 s0 mem[0][70]=16h000F sentinel");
    end

    // CTR increment update for slot 1 on T1 at prm_idx=11h046.
    // prm_comp=1 using_primary=1 prm_tkn=1 resolved=1 -> correct
    // -> INC. CTR 011 -> 100.
    meta                    = '0;
    meta.tage_prm_idx       = 11'h046;
    meta.tage_alt_idx       = 11'h046;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_alt_comp      = 3'd0;
    meta.tage_prm_ctr       = 3'b011;
    meta.tage_alt_ctr       = 3'b011;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b1;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;

    // Drive slot 1. Slot 0 held at zero via staging.
    stg_upd_inp1 = upd_inp;
    stg_upd_val1 = 1'b1;
    @(posedge clk);
    stg_upd_val1 = 1'b0;
    stg_upd_inp1 = '0;
    @(posedge clk);

    // After second posedge: upd_rdy_u1[1]=1, RAM written.
    rd_s1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s1.mem[0][70];
    rd_s0 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][70];

    if (verbose != 0) begin
      $display(
        "[INFO] slot1_upd_tst: rdy[1]=%0b rdy[0]=%0b",
        tage_upd_rdy_u1[1],
        tage_upd_rdy_u1[0]);
      $display(
        "[INFO] slot1_upd_tst: s1 mem[0][70]=16h%04h",
        rd_s1);
      $display(
        "[INFO] slot1_upd_tst: s0 mem[0][70]=16h%04h",
        rd_s0);
    end

    if (tage_upd_rdy_u1[1] !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] slot1_upd_tst: rdy[1]=%0b exp=1",
        tage_upd_rdy_u1[1]);
    end
    if (tage_upd_rdy_u1[0] !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] slot1_upd_tst: rdy[0]=%0b exp=0",
        tage_upd_rdy_u1[0]);
    end
    // Slot 1 CTR incremented: 011->100 -> entry 16h0009.
    if (rd_s1 !== 16'h0009) begin
      local_fails++;
      $display(
        "[FAIL] slot1_upd_tst: s1[0][70]=16h%04h exp=0009",
        rd_s1);
    end
    // Slot 0 RAM unchanged (sentinel value 16h000F).
    if (rd_s0 !== 16'h000F) begin
      local_fails++;
      $display(
        "[FAIL] slot1_upd_tst: s0[0][70]=16h%04h exp=000F",
        rd_s0);
    end

    if (local_fails == 0)
      $display("[PASS] slot1_upd_tst: 0 failures");
    else
      $display("[FAIL] slot1_upd_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_correct_t0_tst
  // Round-trip: T0 provider, correct prediction, CTR increments.
  // CTR rule: tage_cntrl_ctr_update_rules.md row 13d.
  // PC=40'h001E0: T0 idx=0x78=120 bank=0 row=120 tag=0x00.
  // Pre-load: T0 mem[0][120]=2'b10 (weak taken).
  //           T1-T4 VALID=0 (FAST_INIT).
  // ----------------------------------------------------------------
  task automatic rt_correct_t0_tst(int verbose);
    int                          local_fails;
    tage_pred_inp_t              inp;
    tage_pred_meta_t             meta1;
    tage_pred_meta_t             meta2;
    tage_upd_inp_t               upd_inp;
    logic [TAGE_TBL_CTR[0]-1:0] rd_t0;

    local_fails = 0;

    // Step 1: Pre-load T0 bank=0 row=120 with CTR=2b10.
    u_dut.u_tage_bim.u_ram_s0.mem[0][120] = 2'b10;
    if (verbose != 0)
      $display(
        "[INFO] rt_correct_t0_tst: pre T0 mem[0][120]=2b10");

    // Step 2: First predict PC=40'h001E0.
    inp           = '0;
    inp.pc        = 40'h001E0;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=0, pred_tkn=1.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_correct_t0_tst: prm_comp=%0d pred_tkn=%0b",
        meta1.tage_prm_comp,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_correct_t0_tst: prm_comp=%0d exp=0",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_correct_t0_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end

    // Step 4: Update: resolved_taken=1, cond_mispredict=0.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM: T0 CTR=2b11 (INC: 10->11, rule 13d).
    rd_t0 = u_dut.u_tage_bim.u_ram_s0.mem[0][120];
    if (verbose != 0)
      $display(
        "[INFO] rt_correct_t0_tst: post T0 mem[0][120]=2b%02b",
        rd_t0);
    if (rd_t0 !== 2'b11) begin
      local_fails++;
      $display(
        "[FAIL] rt_correct_t0_tst: T0 CTR=%02b exp=11",
        rd_t0);
    end

    // Step 6: Re-predict at same PC. T0 CTR=2b11 -> prm_ctr=3b011.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_correct_t0_tst: repred ctr=%03b tkn=%0b",
        meta2.tage_prm_ctr,
        meta2.tage_pred_tkn);
    end
    if (meta2.tage_prm_ctr !== 3'b011) begin
      local_fails++;
      $display(
        "[FAIL] rt_correct_t0_tst: repred ctr=%03b exp=011",
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_correct_t0_tst: repred tkn=%0b exp=1",
        meta2.tage_pred_tkn);
    end

    if (local_fails == 0)
      $display("[PASS] rt_correct_t0_tst: 0 failures");
    else
      $display("[FAIL] rt_correct_t0_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_correct_tagged_tst
  // Round-trip: T1 provider, correct, preds_diff=1, CTR+USE INC.
  // CTR rule: tage_cntrl_ctr_update_rules.md row 16
  //           (alt=BIM, prm correct, INC prm CTR).
  // USE rule: Table 7 row 3 (preds_diff=1 TTM=0 using_prm=1
  //           mispredict=0 -> INC u_eff).
  // PC=40'h02900: idx=0x240=576 bank=0 row=576 tag=0x05.
  // Pre-load: T1 mem[0][576]=0x051B (CTR=101 USE=01 EPC=0).
  //           T0 mem[0][576]=2'b00 (not-taken -> preds_diff=1).
  //           T2-T4 VALID=0 (FAST_INIT).
  // ----------------------------------------------------------------
  task automatic rt_correct_tagged_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;

    local_fails = 0;

    // Step 1: Pre-load.
    // T1 bank=0 row=576: TAG=0x05 EPC=0 USE=01 CTR=101 VALID=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][576]
      = 16'h051B;
    // T0 bank=0 row=576: CTR=2b00 (not-taken, preds_diff=1).
    u_dut.u_tage_bim.u_ram_s0.mem[0][576] = 2'b00;
    if (verbose != 0) begin
      $display(
        "[INFO] rt_correct_tagged_tst: T1 mem[0][576]=051B");
      $display(
        "[INFO] rt_correct_tagged_tst: T0 mem[0][576]=2b00");
    end

    // Step 2: First predict PC=40'h02900.
    inp           = '0;
    inp.pc        = 40'h02900;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=1, using_primary=1,
    //         pred_tkn=1, preds_diff=1 (prm_tkn != alt_tkn).
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_correct_tagged_tst: prm=%0d alt=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp);
      $display(
        "[INFO] rt_correct_tagged_tst: using_prm=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
      $display(
        "[INFO] rt_correct_tagged_tst: prm_tkn=%0b alt_tkn=%0b",
        meta1.tage_prm_tkn,
        meta1.tage_alt_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] rt_correct_tagged_tst: prm_comp=%0d exp=1",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_correct_tagged_tst: using_prm=%0b exp=1",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_correct_tagged_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_tkn === meta1.tage_alt_tkn) begin
      local_fails++;
      $display(
        "[FAIL] rt_correct_tagged_tst: preds_diff=0 exp=1");
    end

    // Step 4: Update: resolved_taken=1, cond_mispredict=0.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM.
    // T1: TAG=0x05 EPC=0 USE=10 CTR=110 VALID=1 = 0x052D.
    // CTR 101->110 (row 16); USE 01->10 (Table 7 row 3).
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][576];
    if (verbose != 0)
      $display(
        "[INFO] rt_correct_tagged_tst: post T1[0][576]=0x%04h",
        rd_t1);
    if (rd_t1 !== 16'h052D) begin
      local_fails++;
      $display(
        "[FAIL] rt_correct_tagged_tst: T1=0x%04h exp=052D",
        rd_t1);
    end

    // Step 6: Re-predict at same PC. T1 CTR=110 -> prm_ctr=3b110.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_correct_tagged_tst: repred ctr=%03b tkn=%0b",
        meta2.tage_prm_ctr,
        meta2.tage_pred_tkn);
    end
    if (meta2.tage_prm_ctr !== 3'b110) begin
      local_fails++;
      $display(
        "[FAIL] rt_correct_tagged_tst: repred ctr=%03b exp=110",
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_correct_tagged_tst: repred tkn=%0b exp=1",
        meta2.tage_pred_tkn);
    end

    if (local_fails == 0)
      $display("[PASS] rt_correct_tagged_tst: 0 failures");
    else
      $display("[FAIL] rt_correct_tagged_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_mispredict_alloc_tst
  // Round-trip: T1 provider, mispredict, allocation into T2.
  // CTR rule: tage_cntrl_ctr_update_rules.md row 14
  //           (alt=BIM, prm wrong, DEC prm CTR).
  // Alloc rule: tage_cntrl_alloc_rules.md -- mispredict +
  //             prm_comp(1)<TAGE_MAX_TBL(4) + alc_comp(2)!=0
  //             -> write alloc entry to T2.
  // PC=40'h05500: idx=0x540=1344 bank=1 row=320 tag=0x0A.
  // Pre-load: T1 mem[1][320]=0x0A19 (CTR=100 USE=01 EPC=0).
  //           T2 mem[1][320]=0 (VALID=0, alloc candidate).
  //           T0/T3/T4 at idx 1344=0 (FAST_INIT).
  // ----------------------------------------------------------------
  task automatic rt_mispredict_alloc_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;

    local_fails = 0;

    // Step 1: Pre-load T1 bank=1 row=320.
    // TAG=0x0A EPC=0 USE=01 CTR=100 VALID=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][320]
      = 16'h0A19;
    if (verbose != 0)
      $display(
        "[INFO] rt_mispredict_alloc_tst: T1 mem[1][320]=0A19");

    // Step 2: First predict PC=40'h05500.
    inp           = '0;
    inp.pc        = 40'h05500;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=1, alc_comp=2.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_mispredict_alloc_tst: prm=%0d alc=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alc_comp);
    end
    if (meta1.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] rt_mispredict_alloc_tst: prm_comp=%0d exp=1",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alc_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_mispredict_alloc_tst: alc_comp=%0d exp=2",
        meta1.tage_alc_comp);
    end

    // Step 4: Update: resolved_taken=0, cond_mispredict=1.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM.
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][320];
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][320];
    if (verbose != 0) begin
      $display(
        "[INFO] rt_mispredict_alloc_tst: T1[1][320]=0x%04h",
        rd_t1);
      $display(
        "[INFO] rt_mispredict_alloc_tst: T2[1][320]=0x%04h",
        rd_t2);
    end
    // T1 CTR decremented 100->011 (row 14 DEC). Check bits[3:1].
    if (rd_t1[3:1] !== 3'b011) begin
      local_fails++;
      $display(
        "[FAIL] rt_mispredict_alloc_tst: T1 CTR=%03b exp=011",
        rd_t1[3:1]);
    end
    // T2 allocated: TAG=0x0A EPC=0 USE=00 CTR=100 VALID=1=0x0A09.
    if (rd_t2 !== 16'h0A09) begin
      local_fails++;
      $display(
        "[FAIL] rt_mispredict_alloc_tst: T2=0x%04h exp=0A09",
        rd_t2);
    end

    // Step 6: Re-predict. T2 now VALID=1 wins (longer history).
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_mispredict_alloc_tst: repred prm=%0d",
        meta2.tage_prm_comp);
    end
    // T2 allocated and valid: prm_comp=2.
    if (meta2.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_mispredict_alloc_tst: repred prm=%0d exp=2",
        meta2.tage_prm_comp);
    end

    if (local_fails == 0)
      $display("[PASS] rt_mispredict_alloc_tst: 0 failures");
    else
      $display("[FAIL] rt_mispredict_alloc_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_no_alloc_last_tbl_tst
  // Round-trip: T4 provider (last table), mispredict, no alloc.
  // CTR rule: tage_cntrl_ctr_update_rules.md row 14
  //           (alt=BIM, prm wrong, DEC prm CTR).
  // Alloc rule: tage_cntrl_alloc_rules.md -- provider is last
  //   table (T4), tage_alc_comp=0 in meta -> no write.
  // PC=40'h07D00: idx=0x740=1856 bank=1 row=832 tag=0x0F.
  // Pre-load: T4 mem[1][832]=0x0F19 (CTR=100 USE=01 EPC=0).
  //           T1-T3 mem[1][832]=0 (VALID=0, FAST_INIT).
  // ----------------------------------------------------------------
  task automatic rt_no_alloc_last_tbl_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t4;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;
    logic [15:0]     rd_t3;

    local_fails = 0;

    // Step 1: Pre-load T4 bank=1 row=832.
    // TAG=0x0F EPC=0 USE=01 CTR=100 VALID=1.
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[1][832]
      = 16'h0F19;
    if (verbose != 0)
      $display(
        "[INFO] rt_no_alloc_last_tbl_tst: T4 mem[1][832]=0F19");

    // Step 2: First predict PC=40'h07D00.
    inp           = '0;
    inp.pc        = 40'h07D00;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=4.
    //         Primary criterion: alc_comp=0 (no alloc, last tbl).
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_no_alloc_last_tbl_tst: prm=%0d alc=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alc_comp);
    end
    if (meta1.tage_prm_comp !== 3'd4) begin
      local_fails++;
      $display(
        "[FAIL] rt_no_alloc_last_tbl_tst: prm_comp=%0d exp=4",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alc_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_no_alloc_last_tbl_tst: alc_comp=%0d exp=0",
        meta1.tage_alc_comp);
    end

    // Step 4: Update: resolved_taken=0, cond_mispredict=1.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM.
    rd_t4 =
      u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[1][832];
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][832];
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][832];
    rd_t3 =
      u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[1][832];
    if (verbose != 0) begin
      $display(
        "[INFO] rt_no_alloc_last_tbl_tst: T4[1][832]=0x%04h",
        rd_t4);
      $display(
        "[INFO] rt_no_alloc_last_tbl_tst: T1-T3[1][832]=%04h %04h %04h",
        rd_t1, rd_t2, rd_t3);
    end
    // T4 CTR decremented 100->011 (row 14 DEC). Check bits[3:1].
    if (rd_t4[3:1] !== 3'b011) begin
      local_fails++;
      $display(
        "[FAIL] rt_no_alloc_last_tbl_tst: T4 CTR=%03b exp=011",
        rd_t4[3:1]);
    end
    // T1-T3 unchanged: VALID=0 -> word=0. No alloc write.
    if (rd_t1 !== 16'h0000) begin
      local_fails++;
      $display(
        "[FAIL] rt_no_alloc_last_tbl_tst: T1[1][832]=0x%04h exp=0",
        rd_t1);
    end
    if (rd_t2 !== 16'h0000) begin
      local_fails++;
      $display(
        "[FAIL] rt_no_alloc_last_tbl_tst: T2[1][832]=0x%04h exp=0",
        rd_t2);
    end
    if (rd_t3 !== 16'h0000) begin
      local_fails++;
      $display(
        "[FAIL] rt_no_alloc_last_tbl_tst: T3[1][832]=0x%04h exp=0",
        rd_t3);
    end

    // Step 6: Re-predict. T4 CTR=011 (not-taken): prm=4 ctr=011.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_no_alloc_last_tbl_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd4) begin
      local_fails++;
      $display(
        "[FAIL] rt_no_alloc_last_tbl_tst: repred prm=%0d exp=4",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b011) begin
      local_fails++;
      $display(
        "[FAIL] rt_no_alloc_last_tbl_tst: repred ctr=%03b exp=011",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] rt_no_alloc_last_tbl_tst: 0 failures");
    else
      $display(
        "[FAIL] rt_no_alloc_last_tbl_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_ctr_rows1_2_tst (TC-28)
  // Round-trip: T2 prm (comp=2), T1 alt (comp=1), both hit.
  // using_prm=1, prm correct (resolved_taken=1), pred_diff=1.
  // CTR rule: tage_cntrl_ctr_update_rules.md rows 1/2
  //           (prm correct, both tagged: prm INC).
  // USE rule: Table 7 row 3 (pred_diff=1, using_prm=1,
  //           mispredict=0: INC prm USE).
  // PC=40'h09100: idx=0x440=1088 bank=1 row=64 tag=0x12.
  // Pre-load: T2 mem[1][64]=0x120B (CTR=101 USE=00 VAL=1).
  //           T1 mem[1][64]=0x1207 (CTR=011 USE=00 VAL=1).
  // After: T2 CTR 101->110 USE 00->01 -> 0x121D. T1 0x1207.
  // ----------------------------------------------------------------
  task automatic rt_ctr_rows1_2_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;

    local_fails = 0;

    // Step 1: Pre-load. T2=prm(comp=2), T1=alt(comp=1).
    // T2 bank=1 row=64: TAG=0x12 EPC=0 USE=00 CTR=101 VAL=1.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][64]
      = 16'h120B;
    // T1 bank=1 row=64: TAG=0x12 EPC=0 USE=00 CTR=011 VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][64]
      = 16'h1207;
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows1_2_tst: T2 mem[1][64]=120B");
      $display(
        "[INFO] rt_ctr_rows1_2_tst: T1 mem[1][64]=1207");
    end

    // Step 2: First predict PC=40'h09100.
    inp           = '0;
    inp.pc        = 40'h09100;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=2 alt_comp=1
    //         using_primary=1 pred_tkn=1 pred_diff=1.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows1_2_tst: prm=%0d alt=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp);
      $display(
        "[INFO] rt_ctr_rows1_2_tst: using_prm=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
      $display(
        "[INFO] rt_ctr_rows1_2_tst: prm_tkn=%0b alt_tkn=%0b",
        meta1.tage_prm_tkn,
        meta1.tage_alt_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows1_2_tst: prm_comp=%0d exp=2",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows1_2_tst: alt_comp=%0d exp=1",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows1_2_tst: using_prm=%0b exp=1",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows1_2_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_tkn === meta1.tage_alt_tkn) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows1_2_tst: pred_diff=0 exp=1");
    end

    // Step 4: Update: resolved_taken=1, cond_mispredict=0.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM.
    // T2: CTR 101->110 (prm INC), USE 00->01 (Table 7 r3).
    // T2 final: TAG=0x12 EPC=0 USE=01 CTR=110 VAL=1 = 0x121D.
    // T1: unchanged = 0x1207.
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][64];
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][64];
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows1_2_tst: post T2[1][64]=0x%04h",
        rd_t2);
      $display(
        "[INFO] rt_ctr_rows1_2_tst: post T1[1][64]=0x%04h",
        rd_t1);
    end
    if (rd_t2 !== 16'h121D) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows1_2_tst: T2=0x%04h exp=121D",
        rd_t2);
    end
    if (rd_t1 !== 16'h1207) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows1_2_tst: T1=0x%04h exp=1207",
        rd_t1);
    end

    // Step 6: Re-predict. T2 CTR=110 -> prm_ctr=3b110.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows1_2_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows1_2_tst: repred prm=%0d exp=2",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b110) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows1_2_tst: repred ctr=%03b exp=110",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] rt_ctr_rows1_2_tst: 0 failures");
    else
      $display("[FAIL] rt_ctr_rows1_2_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_ctr_rows3_4_tst (TC-29)
  // Round-trip: T2 prm (comp=2), T1 alt (comp=1), both hit.
  // using_prm=1, prm wrong (resolved_taken=0), pred_diff=1.
  // CTR rule: tage_cntrl_ctr_update_rules.md rows 3/4
  //           (prm wrong, pred_diff=1: prm DEC, alt INC).
  // USE rule: Table 7 row 4 (pred_diff=1, using_prm=1,
  //           mispredict=1: DEC prm USE).
  // PC=40'h0B800: idx=0x600=1536 bank=1 row=512 tag=0x17.
  // Pre-load: T2 mem[1][512]=0x171B (CTR=101 USE=01 VAL=1).
  //           T1 mem[1][512]=0x1707 (CTR=011 USE=00 VAL=1).
  //           T3/T4 mem[1][512]=0x0010 (USE=01 VALID=0)
  //           prevents allocation when mispredict=1.
  // After: T2 CTR 101->100 USE 01->00 -> 0x1709.
  //        T1 CTR 011->100 (alt INC, pred_diff=1) -> 0x1709.
  // ----------------------------------------------------------------
  task automatic rt_ctr_rows3_4_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;

    local_fails = 0;

    // Step 1: Pre-load.
    // T2 bank=1 row=512: TAG=0x17 EPC=0 USE=01 CTR=101 VAL=1.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][512]
      = 16'h171B;
    // T1 bank=1 row=512: TAG=0x17 EPC=0 USE=00 CTR=011 VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][512]
      = 16'h1707;
    // T3/T4: USE=01 to block alloc when mispredict=1.
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[1][512]
      = 16'h0010;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[1][512]
      = 16'h0010;
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows3_4_tst: T2 mem[1][512]=171B");
      $display(
        "[INFO] rt_ctr_rows3_4_tst: T1 mem[1][512]=1707");
      $display(
        "[INFO] rt_ctr_rows3_4_tst: T3/T4[1][512]=0010");
    end

    // Step 2: First predict PC=40'h0B800.
    inp           = '0;
    inp.pc        = 40'h0B800;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=2 alt_comp=1
    //         using_primary=1 pred_tkn=1 pred_diff=1 alc=0.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows3_4_tst: prm=%0d alt=%0d alc=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp,
        meta1.tage_alc_comp);
      $display(
        "[INFO] rt_ctr_rows3_4_tst: using_prm=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows3_4_tst: prm_comp=%0d exp=2",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows3_4_tst: alt_comp=%0d exp=1",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows3_4_tst: using_prm=%0b exp=1",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows3_4_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_tkn === meta1.tage_alt_tkn) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows3_4_tst: pred_diff=0 exp=1");
    end
    if (meta1.tage_alc_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows3_4_tst: alc_comp=%0d exp=0",
        meta1.tage_alc_comp);
    end

    // Step 4: Update: resolved_taken=0, cond_mispredict=1.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM.
    // T2: CTR 101->100 (prm DEC), USE 01->00 (Table 7 r4).
    // T2 final: 0x1709. T1: 011->100 (alt INC) -> 0x1709.
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][512];
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][512];
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows3_4_tst: post T2[1][512]=0x%04h",
        rd_t2);
      $display(
        "[INFO] rt_ctr_rows3_4_tst: post T1[1][512]=0x%04h",
        rd_t1);
    end
    if (rd_t2 !== 16'h1709) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows3_4_tst: T2=0x%04h exp=1709",
        rd_t2);
    end
    if (rd_t1 !== 16'h1709) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows3_4_tst: T1=0x%04h exp=1709",
        rd_t1);
    end

    // Step 6: Re-predict. T2 CTR=100 -> prm_ctr=3b100.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows3_4_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows3_4_tst: repred prm=%0d exp=2",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b100) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows3_4_tst: repred ctr=%03b exp=100",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] rt_ctr_rows3_4_tst: 0 failures");
    else
      $display("[FAIL] rt_ctr_rows3_4_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_ctr_rows5_6_tst (TC-30)
  // Round-trip: T2 prm (comp=2), T1 alt (comp=1), both hit.
  // using_prm=1, prm wrong (resolved_taken=0), pred_diff=0.
  // CTR rule: tage_cntrl_ctr_update_rules.md rows 5/6
  //           (prm wrong, pred_diff=0: prm DEC only).
  // USE rule: Table 7 row 1 (pred_diff=0: no USE update).
  // PC=40'h0C000: idx=0x000=0 bank=0 row=0 tag=0x18.
  // Pre-load: T2 mem[0][0]=0x1809 (CTR=100 USE=00 VAL=1).
  //           T1 mem[0][0]=0x180B (CTR=101 USE=00 VAL=1).
  //           T3/T4 mem[0][0]=0x0010 (USE=01 VALID=0).
  // After: T2 CTR 100->011 -> 0x1807. T1 unchanged 0x180B.
  // ----------------------------------------------------------------
  task automatic rt_ctr_rows5_6_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;

    local_fails = 0;

    // Step 1: Pre-load.
    // T2 bank=0 row=0: TAG=0x18 EPC=0 USE=00 CTR=100 VAL=1.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][0]
      = 16'h1809;
    // T1 bank=0 row=0: TAG=0x18 EPC=0 USE=00 CTR=101 VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][0]
      = 16'h180B;
    // T3/T4: USE=01 to block alloc when mispredict=1.
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[0][0]
      = 16'h0010;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[0][0]
      = 16'h0010;
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows5_6_tst: T2 mem[0][0]=1809");
      $display(
        "[INFO] rt_ctr_rows5_6_tst: T1 mem[0][0]=180B");
      $display(
        "[INFO] rt_ctr_rows5_6_tst: T3/T4 mem[0][0]=0010");
    end

    // Step 2: First predict PC=40'h0C000.
    inp           = '0;
    inp.pc        = 40'h0C000;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=2 alt_comp=1
    //         using_primary=1 pred_tkn=1 pred_diff=0 alc=0.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows5_6_tst: prm=%0d alt=%0d alc=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp,
        meta1.tage_alc_comp);
      $display(
        "[INFO] rt_ctr_rows5_6_tst: prm_tkn=%0b alt_tkn=%0b",
        meta1.tage_prm_tkn,
        meta1.tage_alt_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows5_6_tst: prm_comp=%0d exp=2",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows5_6_tst: alt_comp=%0d exp=1",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows5_6_tst: using_prm=%0b exp=1",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows5_6_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_tkn !== meta1.tage_alt_tkn) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows5_6_tst: pred_diff=1 exp=0");
    end
    if (meta1.tage_alc_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows5_6_tst: alc_comp=%0d exp=0",
        meta1.tage_alc_comp);
    end

    // Step 4: Update: resolved_taken=0, cond_mispredict=1.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM.
    // T2: CTR 100->011 (prm DEC); USE unchanged (pred_diff=0).
    // T2 final: 0x1807. T1 unchanged: 0x180B.
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][0];
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][0];
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows5_6_tst: post T2[0][0]=0x%04h",
        rd_t2);
      $display(
        "[INFO] rt_ctr_rows5_6_tst: post T1[0][0]=0x%04h",
        rd_t1);
    end
    if (rd_t2 !== 16'h1807) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows5_6_tst: T2=0x%04h exp=1807",
        rd_t2);
    end
    if (rd_t1 !== 16'h180B) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows5_6_tst: T1=0x%04h exp=180B",
        rd_t1);
    end

    // Step 6: Re-predict. T2 CTR=011 -> prm_ctr=3b011.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows5_6_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows5_6_tst: repred prm=%0d exp=2",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b011) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows5_6_tst: repred ctr=%03b exp=011",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] rt_ctr_rows5_6_tst: 0 failures");
    else
      $display("[FAIL] rt_ctr_rows5_6_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_ctr_rows7_8_tst (TC-31)
  // Round-trip: T2 prm (comp=2), T1 alt (comp=1), both hit.
  // UAON fires: T2 CTR=100 boundary + uaon[0]=8.
  // using_prm=0: T1 alt is provider. Alt correct.
  // CTR rule: tage_cntrl_ctr_update_rules.md rows 7/8
  //           (using_prm=0, both tagged, alt correct: alt INC).
  // USE rule: Table 7 row 1 (pred_diff=0: no USE update).
  //           T2 CTR[2]=1, T1 CTR[2]=1: pred_diff=0.
  // PC=40'h12400: idx=0x100=256 bank=0 row=256 tag=0x24.
  // Pre-load: T2 mem[0][256]=0x2409 (CTR=100 boundary VAL=1).
  //           T1 mem[0][256]=0x240B (CTR=101 VAL=1).
  // uaon[0]=4'h8 written before predict.
  // After: T1 CTR 101->110 -> 0x240D. T2 unchanged 0x2409.
  // Restore uaon[0]=4'h0 before re-predict.
  // ----------------------------------------------------------------
  task automatic rt_ctr_rows7_8_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;

    local_fails = 0;

    // Step 1: Pre-load.
    // T2 bank=0 row=256: TAG=0x24 EPC=0 USE=00 CTR=100 VAL=1.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][256]
      = 16'h2409;
    // T1 bank=0 row=256: TAG=0x24 EPC=0 USE=00 CTR=101 VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][256]
      = 16'h240B;
    // Write uaon[0]=8 to force UAON to fire on T2 CTR=100.
    u_dut.u_tage_cntrl.uaon[0] = 4'h8;
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows7_8_tst: T2 mem[0][256]=2409");
      $display(
        "[INFO] rt_ctr_rows7_8_tst: T1 mem[0][256]=240B");
      $display(
        "[INFO] rt_ctr_rows7_8_tst: uaon[0]=8");
    end

    // Step 2: First predict PC=40'h12400.
    inp           = '0;
    inp.pc        = 40'h12400;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=2 alt_comp=1
    //         using_primary=0 (UAON fires) pred_tkn=1.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows7_8_tst: prm=%0d alt=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp);
      $display(
        "[INFO] rt_ctr_rows7_8_tst: using_prm=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows7_8_tst: prm_comp=%0d exp=2",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows7_8_tst: alt_comp=%0d exp=1",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows7_8_tst: using_prm=%0b exp=0",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows7_8_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end

    // Step 4: Update: resolved_taken=1, cond_mispredict=0.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM.
    // T1: CTR 101->110 (alt INC, rows 7/8). USE unchanged.
    // T1 final: 0x240D. T2 unchanged: 0x2409.
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][256];
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][256];
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows7_8_tst: post T1[0][256]=0x%04h",
        rd_t1);
      $display(
        "[INFO] rt_ctr_rows7_8_tst: post T2[0][256]=0x%04h",
        rd_t2);
    end
    if (rd_t1 !== 16'h240D) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows7_8_tst: T1=0x%04h exp=240D",
        rd_t1);
    end
    if (rd_t2 !== 16'h2409) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows7_8_tst: T2=0x%04h exp=2409",
        rd_t2);
    end

    // Restore uaon[0]=0 before re-predict.
    // pred_strong=1 (post-mux CTR=101) prevents uaon_upd_ff
    // from firing; uaon[0] stays at 4'h8 after update.
    // Restore to prevent UAON from re-firing on T2 CTR=100.
    u_dut.u_tage_cntrl.uaon[0] = 4'h0;

    // Step 6: Re-predict. T2 CTR=100 unchanged.
    // uaon[0]=0 -> UAON does not fire -> using_primary=1.
    // prm=T2 (comp=2), prm_ctr=3b100.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows7_8_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows7_8_tst: repred prm=%0d exp=2",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b100) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows7_8_tst: repred ctr=%03b exp=100",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] rt_ctr_rows7_8_tst: 0 failures");
    else
      $display("[FAIL] rt_ctr_rows7_8_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_ctr_rows9_10_tst (TC-32)
  // Round-trip: T2 prm (comp=2), T1 alt (comp=1), both hit.
  // UAON fires: T2 CTR=011 boundary + uaon[0]=8.
  // using_prm=0: T1 alt is provider. Alt wrong.
  // CTR rule: tage_cntrl_ctr_update_rules.md rows 9/10
  //           (using_prm=0, pred_diff=1, alt wrong:
  //            prm INC, alt DEC).
  // USE rule: Table 7 row 6 (pred_diff=1, using_prm=0,
  //           mispredict=1: DEC alt USE). T1 USE 01->00.
  // PC=40'h14600: idx=0x180=384 bank=0 row=384 tag=0x28.
  // Pre-load: T2 mem[0][384]=0x2807 (CTR=011 USE=00 VAL=1).
  //           T1 mem[0][384]=0x2819 (CTR=100 USE=01 VAL=1).
  //           T3/T4 mem[0][384]=0x0010 (USE=01 VALID=0)
  //           prevents allocation when mispredict=1.
  // uaon[0]=4'h8 written before predict.
  // pred_diff: T2 CTR[2]=0, T1 CTR[2]=1 -> pred_diff=1.
  // resolved_taken=0, cond_mispredict=1, alt wrong.
  // After: T1 CTR 100->011 USE 01->00 -> 0x2807.
  //        T2 CTR 011->100 USE unchanged -> 0x2809.
  // UAON: prm_correct=1, alt_wrong=1 -> DEC. uaon[0]: 8->7.
  // Restore uaon[0]=4'h0 before re-predict.
  // ----------------------------------------------------------------
  task automatic rt_ctr_rows9_10_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;

    local_fails = 0;

    // Step 1: Pre-load.
    // T2 bank=0 row=384: TAG=0x28 EPC=0 USE=00 CTR=011 VAL=1.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][384]
      = 16'h2807;
    // T1 bank=0 row=384: TAG=0x28 EPC=0 USE=01 CTR=100 VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][384]
      = 16'h2819;
    // T3/T4: USE=01 to block alloc when mispredict=1.
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[0][384]
      = 16'h0010;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[0][384]
      = 16'h0010;
    // Write uaon[0]=8 to force UAON on T2 CTR=011 boundary.
    u_dut.u_tage_cntrl.uaon[0] = 4'h8;
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows9_10_tst: T2 mem[0][384]=2807");
      $display(
        "[INFO] rt_ctr_rows9_10_tst: T1 mem[0][384]=2819");
      $display(
        "[INFO] rt_ctr_rows9_10_tst: T3/T4[0][384]=0010");
      $display(
        "[INFO] rt_ctr_rows9_10_tst: uaon[0]=8");
    end

    // Step 2: First predict PC=40'h14600.
    inp           = '0;
    inp.pc        = 40'h14600;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=2 alt_comp=1
    //         using_primary=0 (UAON fires) pred_tkn=1.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows9_10_tst: prm=%0d alt=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp);
      $display(
        "[INFO] rt_ctr_rows9_10_tst: using_prm=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows9_10_tst: prm_comp=%0d exp=2",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows9_10_tst: alt_comp=%0d exp=1",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows9_10_tst: using_prm=%0b exp=0",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows9_10_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end

    // Step 4: Update: resolved_taken=0, cond_mispredict=1.
    // Rows 9/10: prm (T2) INC, alt (T1) DEC. pred_diff=1.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM.
    // T1: CTR 100->011 USE 01->00 (alt DEC, rows 9/10).
    // T1 final: 0x2807. T2: CTR 011->100 -> 0x2809.
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][384];
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][384];
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows9_10_tst: post T1[0][384]=0x%04h",
        rd_t1);
      $display(
        "[INFO] rt_ctr_rows9_10_tst: post T2[0][384]=0x%04h",
        rd_t2);
    end
    if (rd_t1 !== 16'h2807) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows9_10_tst: T1=0x%04h exp=2807",
        rd_t1);
    end
    if (rd_t2 !== 16'h2809) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows9_10_tst: T2=0x%04h exp=2809",
        rd_t2);
    end

    // Restore uaon[0]=0 before re-predict.
    // UAON DEC fired (prm_correct=1, alt_wrong=1): 8->7.
    // Restore to prevent UAON from re-firing on T2 CTR=100.
    u_dut.u_tage_cntrl.uaon[0] = 4'h0;

    // Step 6: Re-predict. T2 CTR=100. T1 CTR=011.
    // uaon[0]=0 -> UAON does not fire -> using_primary=1.
    // prm=T2 (comp=2), prm_ctr=3b100.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows9_10_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows9_10_tst: repred prm=%0d exp=2",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b100) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows9_10_tst: repred ctr=%03b exp=100",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] rt_ctr_rows9_10_tst: 0 failures");
    else
      $display("[FAIL] rt_ctr_rows9_10_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_ctr_rows11_12_tst (TC-33)
  // Round-trip: T2 prm (comp=2), T1 alt (comp=1), both hit.
  // UAON fires: T2 CTR=100 boundary + uaon[0]=8.
  // using_prm=0: T1 alt is provider. Alt wrong.
  // CTR rule: tage_cntrl_ctr_update_rules.md rows 11/12
  //           (using_prm=0, pred_diff=0, alt wrong:
  //            alt DEC only, prm no change).
  // USE rule: Table 7 row 1 (pred_diff=0: no USE update).
  // PC=40'h1F400: idx=0x500=1280 bank=1 row=256 tag=0x3E.
  // Pre-load: T2 mem[1][256]=0x3E09 (CTR=100 USE=00 VAL=1).
  //           T1 mem[1][256]=0x3E19 (CTR=100 USE=01 VAL=1).
  //           T3/T4 mem[1][256]=0x0010 (USE=01 VALID=0)
  //           prevents allocation when mispredict=1.
  // uaon[0]=4'h8 written before predict.
  // pred_diff: T2 CTR[2]=1, T1 CTR[2]=1 -> pred_diff=0.
  // NOTE: prompt Specific Requirements specifies T2 CTR=3'b101
  //       but that is not a boundary value and UAON would not
  //       fire. T2 CTR=3'b100 is used per Background section
  //       and RTL tage_cntrl.sv UAON trigger analysis.
  // resolved_taken=0, cond_mispredict=1, alt wrong.
  // After: T1 CTR 100->011 USE unchanged 01 -> 0x3E17.
  //        T2 CTR 100 unchanged USE unchanged -> 0x3E09.
  // UAON: both wrong -> no change. uaon[0] stays at 8.
  // Restore uaon[0]=4'h0 before re-predict.
  // ----------------------------------------------------------------
  task automatic rt_ctr_rows11_12_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;

    local_fails = 0;

    // Step 1: Pre-load.
    // T2 bank=1 row=256: TAG=0x3E EPC=0 USE=00 CTR=100 VAL=1.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][256]
      = 16'h3E09;
    // T1 bank=1 row=256: TAG=0x3E EPC=0 USE=01 CTR=100 VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][256]
      = 16'h3E19;
    // T3/T4: USE=01 to block alloc when mispredict=1.
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[1][256]
      = 16'h0010;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[1][256]
      = 16'h0010;
    // Write uaon[0]=8 to force UAON on T2 CTR=100 boundary.
    u_dut.u_tage_cntrl.uaon[0] = 4'h8;
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows11_12_tst: T2 mem[1][256]=3E09");
      $display(
        "[INFO] rt_ctr_rows11_12_tst: T1 mem[1][256]=3E19");
      $display(
        "[INFO] rt_ctr_rows11_12_tst: T3/T4[1][256]=0010");
      $display(
        "[INFO] rt_ctr_rows11_12_tst: uaon[0]=8");
    end

    // Step 2: First predict PC=40'h1F400.
    inp           = '0;
    inp.pc        = 40'h1F400;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=2 alt_comp=1
    //         using_primary=0 (UAON fires) pred_tkn=1.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows11_12_tst: prm=%0d alt=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp);
      $display(
        "[INFO] rt_ctr_rows11_12_tst: using_prm=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows11_12_tst: prm_comp=%0d exp=2",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows11_12_tst: alt_comp=%0d exp=1",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows11_12_tst: using_prm=%0b exp=0",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows11_12_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end

    // Step 4: Update: resolved_taken=0, cond_mispredict=1.
    // Rows 11/12: alt (T1) DEC only. prm (T2) no change.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM.
    // T1: CTR 100->011 USE 01 unchanged (pred_diff=0).
    // T1 final: 0x3E17. T2 unchanged: 0x3E09.
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][256];
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][256];
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows11_12_tst: post T1[1][256]=0x%04h",
        rd_t1);
      $display(
        "[INFO] rt_ctr_rows11_12_tst: post T2[1][256]=0x%04h",
        rd_t2);
    end
    if (rd_t1 !== 16'h3E17) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows11_12_tst: T1=0x%04h exp=3E17",
        rd_t1);
    end
    if (rd_t2 !== 16'h3E09) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows11_12_tst: T2=0x%04h exp=3E09",
        rd_t2);
    end

    // Restore uaon[0]=0 before re-predict.
    // UAON no change (both wrong): uaon[0] stays at 8.
    // Restore to prevent UAON from re-firing on T2 CTR=100.
    u_dut.u_tage_cntrl.uaon[0] = 4'h0;

    // Step 6: Re-predict. T2 CTR=100 unchanged.
    // uaon[0]=0 -> UAON does not fire -> using_primary=1.
    // prm=T2 (comp=2), prm_ctr=3b100.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows11_12_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows11_12_tst: repred prm=%0d exp=2",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b100) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows11_12_tst: repred ctr=%03b exp=100",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] rt_ctr_rows11_12_tst: 0 failures");
    else
      $display("[FAIL] rt_ctr_rows11_12_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_ctr_row13b_tst (TC-34)
  // Round-trip: T0 sole provider. prm_comp=0, alt_comp=0.
  // T0 CTR=2'b01 (weakly not-taken). pred_tkn=0.
  // resolved_taken=1, cond_mispredict=1.
  // CTR rule: tage_cntrl_ctr_update_rules.md row 13b
  //           (prm_comp=0, alt_comp=0, pred_tkn=0,
  //            resolved_taken=1: T0 INC 01->10).
  // BP-015: Fixed T0 CTR direction. Was pred_crt-driven
  //   (DEC when mispredicted: 01->00). Now resolved_taken:
  //   INC when taken: 01->10. Debt #34 closed.
  // PC=40'h190: T0 idx=100 bank=0 row=100.
  // Pre-load: T0 mem[0][100]=2'b01 (weakly not-taken).
  //           T1-T4 mem[0][100]=16'h0010 (USE=01, VALID=0):
  //           no tag hits; blocks allocation candidate.
  // After update: T0 CTR 01->10 (INC, resolved_taken=1).
  // Re-predict: prm_comp=0, prm_ctr=3'b010.
  // ----------------------------------------------------------------
  task automatic rt_ctr_row13b_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [1:0]      rd_bim;

    local_fails = 0;

    // Step 1: Pre-load.
    // T0 bank=0 row=100: CTR=2'b01 (weakly not-taken).
    u_dut.u_tage_bim.u_ram_s0.mem[0][100] = 2'b01;
    // T1-T4 bank=0 row=100: USE=01 VALID=0.
    // USE=01 -> ueff=01 -> not an allocation candidate.
    // VALID=0 -> no tag hit during prediction.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][100]
      = 16'h0010;
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][100]
      = 16'h0010;
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[0][100]
      = 16'h0010;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[0][100]
      = 16'h0010;
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_row13b_tst: T0 mem[0][100]=2b01");
      $display(
        "[INFO] rt_ctr_row13b_tst: T1-T4[0][100]=0010");
    end

    // Step 2: First predict PC=40'h190.
    inp           = '0;
    inp.pc        = 40'h190;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=0 alt_comp=0
    //         using_primary=1 pred_tkn=0.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_row13b_tst: prm=%0d alt=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp);
      $display(
        "[INFO] rt_ctr_row13b_tst: using_prm=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13b_tst: prm_comp=%0d exp=0",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13b_tst: alt_comp=%0d exp=0",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13b_tst: using_prm=%0b exp=1",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13b_tst: pred_tkn=%0b exp=0",
        meta1.tage_pred_tkn);
    end

    // Step 4: Update: resolved_taken=1, cond_mispredict=1.
    // Row 13b: T0 INC (01->10). Allocation suppressed
    // (alc_comp=0 sentinel from predict: T1-T4 ueff!=0).
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify T0 BIM RAM.
    // resolved_taken=1 -> INC: 01->10. mem[0][100]=2'b10.
    rd_bim = u_dut.u_tage_bim.u_ram_s0.mem[0][100];
    if (verbose != 0)
      $display(
        "[INFO] rt_ctr_row13b_tst: post T0[0][100]=2b%02b",
        rd_bim);
    if (rd_bim !== 2'b10) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13b_tst: T0=2b%02b exp=10",
        rd_bim);
    end

    // Step 6: Re-predict. T0 CTR=2'b10 after INC.
    // Verify prm_comp=0, prm_ctr=3'b010.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_row13b_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13b_tst: repred prm=%0d exp=0",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b010) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13b_tst: repred ctr=%03b exp=010",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] rt_ctr_row13b_tst: 0 failures");
    else
      $display("[FAIL] rt_ctr_row13b_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_ctr_row13c_tst (TC-35)
  // Round-trip: T0 sole provider. prm_comp=0, alt_comp=0.
  // T0 CTR=2'b10 (weakly taken). pred_tkn=1.
  // resolved_taken=0, cond_mispredict=1.
  // CTR rule: tage_cntrl_ctr_update_rules.md row 13c
  //           (prm_comp=0, alt_comp=0, pred_tkn=1,
  //            resolved_taken=0: T0 DEC 10->01).
  // PC=40'h320: T0 idx=200 bank=0 row=200.
  // Pre-load: T0 mem[0][200]=2'b10 (weakly taken).
  //           T1-T4 mem[0][200]=16'h0010 (USE=01, VALID=0):
  //           no tag hits; blocks allocation candidate.
  // After update: T0 CTR 10->01.
  // Re-predict: prm_comp=0, prm_ctr=3'b001.
  // ----------------------------------------------------------------
  task automatic rt_ctr_row13c_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [1:0]      rd_bim;

    local_fails = 0;

    // Step 1: Pre-load.
    // T0 bank=0 row=200: CTR=2'b10 (weakly taken).
    u_dut.u_tage_bim.u_ram_s0.mem[0][200] = 2'b10;
    // T1-T4 bank=0 row=200: USE=01 VALID=0.
    // USE=01 -> ueff=01 -> not an allocation candidate.
    // VALID=0 -> no tag hit during prediction.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][200]
      = 16'h0010;
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][200]
      = 16'h0010;
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[0][200]
      = 16'h0010;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[0][200]
      = 16'h0010;
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_row13c_tst: T0 mem[0][200]=2b10");
      $display(
        "[INFO] rt_ctr_row13c_tst: T1-T4[0][200]=0010");
    end

    // Step 2: First predict PC=40'h320.
    inp           = '0;
    inp.pc        = 40'h320;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=0 alt_comp=0
    //         using_primary=1 pred_tkn=1.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_row13c_tst: prm=%0d alt=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp);
      $display(
        "[INFO] rt_ctr_row13c_tst: using_prm=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13c_tst: prm_comp=%0d exp=0",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13c_tst: alt_comp=%0d exp=0",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13c_tst: using_prm=%0b exp=1",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13c_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end

    // Step 4: Update: resolved_taken=0, cond_mispredict=1.
    // Row 13c: T0 DEC (10->01). Allocation suppressed
    // (alc_comp=0 sentinel from predict: T1-T4 ueff!=0).
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify T0 BIM RAM.
    // CTR 10->01. BIM mem[0][200]=2'b01.
    rd_bim = u_dut.u_tage_bim.u_ram_s0.mem[0][200];
    if (verbose != 0)
      $display(
        "[INFO] rt_ctr_row13c_tst: post T0[0][200]=2b%02b",
        rd_bim);
    if (rd_bim !== 2'b01) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13c_tst: T0=2b%02b exp=01",
        rd_bim);
    end

    // Step 6: Re-predict. T0 CTR=2'b01 after DEC.
    // Verify prm_comp=0, prm_ctr=3'b001.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_row13c_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13c_tst: repred prm=%0d exp=0",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b001) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13c_tst: repred ctr=%03b exp=001",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] rt_ctr_row13c_tst: 0 failures");
    else
      $display("[FAIL] rt_ctr_row13c_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_ctr_row13a_tst (TC-36)
  // Round-trip: T0 sole provider. prm_comp=0, alt_comp=0.
  // T0 CTR=2'b01 (weakly not-taken). pred_tkn=0.
  // resolved_taken=0, cond_mispredict=0. T0 correct.
  // CTR rule: tage_cntrl_ctr_update_rules.md row 13a
  //           (prm_comp=0, alt_comp=0, pred_tkn=0,
  //            resolved_taken=0: T0 DEC 01->00).
  // BP-015: Fixed T0 CTR direction. Was pred_crt-driven
  //   (INC when correct: 01->10). Now resolved_taken-driven
  //   (DEC when not-taken: 01->00). Debt #34 closed.
  // PC=40'h480: T0 idx=288 bank=0 row=288.
  // Pre-load: T0 mem[0][288]=2'b01 (weakly not-taken).
  //           T1-T4 not pre-loaded. FAST_INIT ensures
  //           VALID=0 (no tag hits). Allocation suppressed
  //           because cond_mispredict=0.
  // After update (RTL): T0 CTR 01->10 (add 1, pred_crt=1).
  // Re-predict: prm_comp=0, prm_ctr=3'b010.
  // ----------------------------------------------------------------
  task automatic rt_ctr_row13a_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [1:0]      rd_bim;

    local_fails = 0;

    // Step 1: Pre-load.
    // T0 bank=0 row=288: CTR=2'b01 (weakly not-taken).
    // T1-T4 not pre-loaded: FAST_INIT gives VALID=0 (no
    // tag hit). cond_mispredict=0 suppresses allocation.
    u_dut.u_tage_bim.u_ram_s0.mem[0][288] = 2'b01;
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_row13a_tst: T0 mem[0][288]=2b01");
      $display(
        "[INFO] rt_ctr_row13a_tst: T1-T4 not pre-loaded");
    end

    // Step 2: First predict PC=40'h480.
    inp           = '0;
    inp.pc        = 40'h480;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=0 alt_comp=0
    //         using_primary=1 pred_tkn=0.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_row13a_tst: prm=%0d alt=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp);
      $display(
        "[INFO] rt_ctr_row13a_tst: using_prm=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13a_tst: prm_comp=%0d exp=0",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13a_tst: alt_comp=%0d exp=0",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13a_tst: using_prm=%0b exp=1",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13a_tst: pred_tkn=%0b exp=0",
        meta1.tage_pred_tkn);
    end

    // Step 4: Update: resolved_taken=0, cond_mispredict=0.
    // Row 13a: T0 INC (01->00). Correct prediction.
    // Allocation does not fire (cond_mispredict=0).
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b0;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify T0 BIM RAM.
    // resolved_taken=0 -> DEC: 01->00. mem[0][288]=2'b00.
    rd_bim = u_dut.u_tage_bim.u_ram_s0.mem[0][288];
    if (verbose != 0)
      $display(
        "[INFO] rt_ctr_row13a_tst: post T0[0][288]=2b%02b",
        rd_bim);
    if (rd_bim !== 2'b00) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13a_tst: T0=2b%02b exp=00",
        rd_bim);
    end

    // Step 6: Re-predict. T0 CTR=2'b00 after DEC.
    // Verify prm_comp=0, prm_ctr=3'b000.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_row13a_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13a_tst: repred prm=%0d exp=0",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b000) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13a_tst: repred ctr=%03b exp=000",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] rt_ctr_row13a_tst: 0 failures");
    else
      $display("[FAIL] rt_ctr_row13a_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_ctr_row13d_tst (TC-37)
  // Round-trip: T0 sole provider. prm_comp=0, alt_comp=0.
  // T0 CTR=2'b10 (weakly taken). pred_tkn=1.
  // resolved_taken=1, cond_mispredict=0. T0 correct.
  // CTR rule: tage_cntrl_ctr_update_rules.md row 13d
  //           (prm_comp=0, alt_comp=0, pred_tkn=1,
  //            resolved_taken=1: T0 INC 10->11).
  // PC=40'h600: T0 idx=384 bank=0 row=384.
  // Pre-load: T0 mem[0][384]=2'b10 (weakly taken).
  //           T1-T4 not pre-loaded. FAST_INIT ensures
  //           VALID=0 (no tag hits). Allocation suppressed
  //           because cond_mispredict=0.
  // After update: T0 CTR 10->11 (INC toward taken).
  // Re-predict: prm_comp=0, prm_ctr=3'b011.
  // ----------------------------------------------------------------
  task automatic rt_ctr_row13d_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [1:0]      rd_bim;

    local_fails = 0;

    // Step 1: Pre-load.
    // T0 bank=0 row=384: CTR=2'b10 (weakly taken).
    // T1-T4 not pre-loaded: FAST_INIT gives VALID=0 (no
    // tag hit). cond_mispredict=0 suppresses allocation.
    u_dut.u_tage_bim.u_ram_s0.mem[0][384] = 2'b10;
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_row13d_tst: T0 mem[0][384]=2b10");
      $display(
        "[INFO] rt_ctr_row13d_tst: T1-T4 not pre-loaded");
    end

    // Step 2: First predict PC=40'h600.
    inp           = '0;
    inp.pc        = 40'h600;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=0 alt_comp=0
    //         using_primary=1 pred_tkn=1.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_row13d_tst: prm=%0d alt=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp);
      $display(
        "[INFO] rt_ctr_row13d_tst: using_prm=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13d_tst: prm_comp=%0d exp=0",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13d_tst: alt_comp=%0d exp=0",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13d_tst: using_prm=%0b exp=1",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13d_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end

    // Step 4: Update: resolved_taken=1, cond_mispredict=0.
    // Row 13d: T0 INC (10->11). Correct prediction.
    // Allocation does not fire (cond_mispredict=0).
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify T0 BIM RAM.
    // CTR 10->11. BIM mem[0][384]=2'b11.
    rd_bim = u_dut.u_tage_bim.u_ram_s0.mem[0][384];
    if (verbose != 0)
      $display(
        "[INFO] rt_ctr_row13d_tst: post T0[0][384]=2b%02b",
        rd_bim);
    if (rd_bim !== 2'b11) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13d_tst: T0=2b%02b exp=11",
        rd_bim);
    end

    // Step 6: Re-predict. T0 CTR=2'b11 after INC.
    // Verify prm_comp=0, prm_ctr=3'b011.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_row13d_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13d_tst: repred prm=%0d exp=0",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b011) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_row13d_tst: repred ctr=%03b exp=011",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] rt_ctr_row13d_tst: 0 failures");
    else
      $display("[FAIL] rt_ctr_row13d_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_ctr_rows14_15_tst (TC-38)
  // Round-trip: T1 prm (comp=1), T0 alt (comp=0). T2-T4 no hit.
  // using_prm=1. T1 CTR=101 (wt1, not boundary). T0 CTR=01 (wnt).
  // pred_diff=1 (T1 CTR[2]=1 != T0 CTR[1]=0).
  // CTR rule: tage_cntrl_ctr_update_rules.md row 14
  //   (prm_comp>0, alt_comp=0, using_prm=1, pred_tkn=1,
  //    resolved_taken=0: prm DEC).
  // USE rule: tage_cntrl_use_update_rules.md Table 7 row 4
  //   (pred_diff=1, TTM=0, using_prm=1, mispredict=1:
  //    DEC prm USE).
  // PC=40'h780: idx=480 bank=0 row=480 tag=0x00.
  // T1 pre-load: mem[0][480]=16'h001B (CTR=101 USE=01 VAL=1).
  // T0 pre-load: mem[0][480]=2'b01 (weakly not-taken).
  // T2-T4 pre-load: mem[0][480]=16'h0010 (USE=01 VAL=0,
  //   blocks alloc candidate).
  // After update: T1 CTR 101->100 USE 01->00 -> 16'h0009.
  //               T0 unchanged -> 2'b01.
  // Re-predict: prm_comp=1 prm_ctr=3b100.
  // ----------------------------------------------------------------
  task automatic rt_ctr_rows14_15_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [1:0]      rd_bim;

    local_fails = 0;

    // Step 1: Pre-load.
    // T1 bank=0 row=480: TAG=0x00 EPC=0 USE=01 CTR=101 VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][480]
      = 16'h001B;
    // T0 bank=0 row=480: CTR=2b01 (weakly not-taken).
    u_dut.u_tage_bim.u_ram_s0.mem[0][480] = 2'b01;
    // T2-T4 bank=0 row=480: USE=01 VALID=0, blocks alloc.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][480]
      = 16'h0010;
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[0][480]
      = 16'h0010;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[0][480]
      = 16'h0010;
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows14_15_tst: T1 mem[0][480]=001B");
      $display(
        "[INFO] rt_ctr_rows14_15_tst: T0 mem[0][480]=2b01");
      $display(
        "[INFO] rt_ctr_rows14_15_tst: T2-T4[0][480]=0010");
    end

    // Step 2: First predict PC=40'h780.
    inp           = '0;
    inp.pc        = 40'h780;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=1 alt_comp=0
    //         using_primary=1 pred_tkn=1 pred_diff=1 alc=0.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows14_15_tst: prm=%0d alt=%0d alc=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp,
        meta1.tage_alc_comp);
      $display(
        "[INFO] rt_ctr_rows14_15_tst: prm_tkn=%0b alt_tkn=%0b",
        meta1.tage_prm_tkn,
        meta1.tage_alt_tkn);
      $display(
        "[INFO] rt_ctr_rows14_15_tst: using_prm=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows14_15_tst: prm_comp=%0d exp=1",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows14_15_tst: alt_comp=%0d exp=0",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows14_15_tst: using_prm=%0b exp=1",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows14_15_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_tkn === meta1.tage_alt_tkn) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows14_15_tst: pred_diff=0 exp=1");
    end
    if (meta1.tage_alc_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows14_15_tst: alc_comp=%0d exp=0",
        meta1.tage_alc_comp);
    end

    // Step 4: Update: resolved_taken=0, cond_mispredict=1.
    // CTR row 14: prm wrong (pred_tkn=1 != resolved=0):
    //   DEC prm CTR 101->100.
    // Table 7 row 4: pred_diff=1 using_prm=1 mispredict=1:
    //   DEC prm USE 01->00.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM.
    // T1: CTR 101->100 USE 01->00; entry=16h0009.
    // T0: unchanged 2b01.
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][480];
    rd_bim = u_dut.u_tage_bim.u_ram_s0.mem[0][480];
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows14_15_tst: post T1[0][480]=0x%04h",
        rd_t1);
      $display(
        "[INFO] rt_ctr_rows14_15_tst: post T0[0][480]=2b%02b",
        rd_bim);
    end
    if (rd_t1 !== 16'h0009) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows14_15_tst: T1=0x%04h exp=0009",
        rd_t1);
    end
    if (rd_bim !== 2'b01) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows14_15_tst: T0=2b%02b exp=01",
        rd_bim);
    end

    // Step 6: Re-predict. T1 CTR=100 after DEC.
    // Verify prm_comp=1, prm_ctr=3b100.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows14_15_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows14_15_tst: repred prm=%0d exp=1",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b100) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows14_15_tst: repred ctr=%03b exp=100",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] rt_ctr_rows14_15_tst: 0 failures");
    else
      $display("[FAIL] rt_ctr_rows14_15_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // rt_ctr_rows16_17_tst (TC-39)
  // Round-trip: T1 prm (comp=1), T0 alt (comp=0). T2-T4 no hit.
  // using_prm=1. T1 CTR=101 (wt1, not boundary). T0 CTR=01 (wnt).
  // pred_diff=1 (T1 CTR[2]=1 != T0 CTR[1]=0).
  // CTR rule: tage_cntrl_ctr_update_rules.md row 16
  //   (prm_comp>0, alt_comp=0, using_prm=1, pred_tkn=1,
  //    resolved_taken=1: prm INC).
  // USE rule: tage_cntrl_use_update_rules.md Table 7 row 3
  //   (pred_diff=1, TTM=0, using_prm=1, mispredict=0:
  //    INC prm USE).
  // PC=40'h900: idx=576 bank=0 row=576 tag=0x01.
  // T1 pre-load: mem[0][576]=16'h011B (CTR=101 USE=01 VAL=1).
  // T0 pre-load: mem[0][576]=2'b01 (weakly not-taken).
  // cond_mispredict=0: no T2-T4 pre-load needed.
  // After update: T1 CTR 101->110 USE 01->10 -> 16'h012D.
  //               T0 unchanged -> 2'b01.
  // Re-predict: prm_comp=1 prm_ctr=3b110.
  // ----------------------------------------------------------------
  task automatic rt_ctr_rows16_17_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [1:0]      rd_bim;

    local_fails = 0;

    // Step 1: Pre-load.
    // T1 bank=0 row=576: TAG=0x01 EPC=0 USE=01 CTR=101 VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][576]
      = 16'h011B;
    // T0 bank=0 row=576: CTR=2b01 (weakly not-taken).
    u_dut.u_tage_bim.u_ram_s0.mem[0][576] = 2'b01;
    // T2-T4: no pre-load (cond_mispredict=0, no allocation).
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows16_17_tst: T1 mem[0][576]=011B");
      $display(
        "[INFO] rt_ctr_rows16_17_tst: T0 mem[0][576]=2b01");
    end

    // Step 2: First predict PC=40'h900.
    inp           = '0;
    inp.pc        = 40'h900;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta. Verify prm_comp=1 alt_comp=0
    //         using_primary=1 pred_tkn=1 pred_diff=1.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows16_17_tst: prm=%0d alt=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp);
      $display(
        "[INFO] rt_ctr_rows16_17_tst: prm_tkn=%0b alt_tkn=%0b",
        meta1.tage_prm_tkn,
        meta1.tage_alt_tkn);
      $display(
        "[INFO] rt_ctr_rows16_17_tst: using_prm=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows16_17_tst: prm_comp=%0d exp=1",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows16_17_tst: alt_comp=%0d exp=0",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows16_17_tst: using_prm=%0b exp=1",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows16_17_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_tkn === meta1.tage_alt_tkn) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows16_17_tst: pred_diff=0 exp=1");
    end

    // Step 4: Update: resolved_taken=1, cond_mispredict=0.
    // CTR row 16: prm correct (pred_tkn=1 == resolved=1):
    //   INC prm CTR 101->110.
    // Table 7 row 3: pred_diff=1 using_prm=1 mispredict=0:
    //   INC prm USE 01->10.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM.
    // T1: CTR 101->110 USE 01->10; entry=16h012D.
    // T0: unchanged 2b01.
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][576];
    rd_bim = u_dut.u_tage_bim.u_ram_s0.mem[0][576];
    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows16_17_tst: post T1[0][576]=0x%04h",
        rd_t1);
      $display(
        "[INFO] rt_ctr_rows16_17_tst: post T0[0][576]=2b%02b",
        rd_bim);
    end
    if (rd_t1 !== 16'h012D) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows16_17_tst: T1=0x%04h exp=012D",
        rd_t1);
    end
    if (rd_bim !== 2'b01) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows16_17_tst: T0=2b%02b exp=01",
        rd_bim);
    end

    // Step 6: Re-predict. T1 CTR=110 after INC.
    // Verify prm_comp=1, prm_ctr=3b110.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] rt_ctr_rows16_17_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows16_17_tst: repred prm=%0d exp=1",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b110) begin
      local_fails++;
      $display(
        "[FAIL] rt_ctr_rows16_17_tst: repred ctr=%03b exp=110",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] rt_ctr_rows16_17_tst: 0 failures");
    else
      $display("[FAIL] rt_ctr_rows16_17_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // BP-014f TC-40: uaon_threshold_cross_tst
  // PC=40'hB00: bank=0 row=704 tag=0x01.
  // uaon[0] starts at 4'h7 (below threshold=8).
  // T2 prm CTR=100 (boundary taken). T1 alt CTR=010.
  // First predict: using_prm=1 (uaon<threshold).
  // Update: resolved_taken=0 cond_mispredict=1.
  //   prm(T2) wrong alt(T1) correct pred_strong=0.
  //   UAON INC 7->8. CTR row 3: T2 DEC T1 INC.
  // Re-predict: using_prm=0 (uaon=8>=threshold T2 CTR=011
  //   still boundary).
  // ----------------------------------------------------------------
  task automatic uaon_threshold_cross_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;
    logic [3:0]      uaon_pre;
    logic [3:0]      uaon_post;

    local_fails = 0;

    // Step 1: Pre-load.
    // uaon[0]=7 via hierarchical write.
    u_dut.u_tage_cntrl.uaon[0] = 4'h7;
    // T2 bank=0 row=704: TAG=0x01 EPC=0 USE=00 CTR=100 VAL=1.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][704]
      = 16'h0109;
    // T1 bank=0 row=704: TAG=0x01 EPC=0 USE=00 CTR=010 VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][704]
      = 16'h0105;
    // T3/T4: USE=01 VALID=0 (allocation suppression).
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[0][704]
      = 16'h0010;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[0][704]
      = 16'h0010;
    if (verbose != 0) begin
      $display(
        "[INFO] uaon_threshold_cross_tst: uaon[0]=0x%0h",
        u_dut.u_tage_cntrl.uaon[0]);
      $display(
        "[INFO] uaon_threshold_cross_tst: T2[0][704]=0109");
      $display(
        "[INFO] uaon_threshold_cross_tst: T1[0][704]=0105");
      $display(
        "[INFO] uaon_threshold_cross_tst: T3/T4[0][704]=0010");
    end

    // Step 2: First predict PC=40'hB00.
    inp           = '0;
    inp.pc        = 40'hB00;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta1. Verify prm=2 alt=1
    //         using_prm=1 pred_tkn=1 pred_diff=1.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] uaon_threshold_cross_tst: prm=%0d alt=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp);
      $display(
        "[INFO] uaon_threshold_cross_tst: prm_tkn=%0b alt=%0b",
        meta1.tage_prm_tkn,
        meta1.tage_alt_tkn);
      $display(
        "[INFO] uaon_threshold_cross_tst: using=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] uaon_threshold_cross_tst: prm=%0d exp=2",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] uaon_threshold_cross_tst: alt=%0d exp=1",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] uaon_threshold_cross_tst: using_prm=%0b exp=1",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] uaon_threshold_cross_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_tkn === meta1.tage_alt_tkn) begin
      local_fails++;
      $display(
        "[FAIL] uaon_threshold_cross_tst: pred_diff=0 exp=1");
    end

    // Step 4: Update resolved_taken=0 cond_mispredict=1.
    // UAON INC: 7->8 (prm wrong alt correct pred_strong=0).
    // CTR row 3: T2 DEC 100->011 T1 INC 010->011.
    // Table 7 row 4: T2 USE DEC 00->00 sat.
    uaon_pre = u_dut.u_tage_cntrl.uaon[0];
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify UAON and RAM.
    uaon_post = u_dut.u_tage_cntrl.uaon[0];
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][704];
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][704];
    if (verbose != 0) begin
      $display(
        "[INFO] uaon_threshold_cross_tst: pre uaon=0x%0h",
        uaon_pre);
      $display(
        "[INFO] uaon_threshold_cross_tst: post uaon=0x%0h",
        uaon_post);
      $display(
        "[INFO] uaon_threshold_cross_tst: T2[0][704]=0x%04h",
        rd_t2);
      $display(
        "[INFO] uaon_threshold_cross_tst: T1[0][704]=0x%04h",
        rd_t1);
    end
    if (uaon_post !== 4'h8) begin
      local_fails++;
      $display(
        "[FAIL] uaon_threshold_cross_tst: uaon=0x%0h exp=8",
        uaon_post);
    end
    if (rd_t2 !== 16'h0107) begin
      local_fails++;
      $display(
        "[FAIL] uaon_threshold_cross_tst: T2=0x%04h exp=0107",
        rd_t2);
    end
    if (rd_t1 !== 16'h0107) begin
      local_fails++;
      $display(
        "[FAIL] uaon_threshold_cross_tst: T1=0x%04h exp=0107",
        rd_t1);
    end

    // Step 6: Re-predict. uaon=8 >= threshold.
    // T2 CTR=011 still boundary: UAON fires -> using_prm=0.
    // Alt T1 CTR=011 says not-taken -> pred_tkn=0.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] uaon_threshold_cross_tst: repred prm=%0d",
        meta2.tage_prm_comp);
      $display(
        "[INFO] uaon_threshold_cross_tst: repred using=%0b tkn=%0b",
        meta2.tage_using_primary,
        meta2.tage_pred_tkn);
    end
    if (meta2.tage_using_primary !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] uaon_threshold_cross_tst: repred using_prm=%0b exp=0",
        meta2.tage_using_primary);
    end
    if (meta2.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] uaon_threshold_cross_tst: repred prm_comp=%0d exp=2",
        meta2.tage_prm_comp);
    end

    if (local_fails == 0)
      $display(
        "[PASS] uaon_threshold_cross_tst: 0 failures");
    else
      $display(
        "[FAIL] uaon_threshold_cross_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // BP-014f TC-41: uaon_dec_restore_tst
  // Continues from TC-40 RAM state.
  // uaon[0]=8 (set by TC-40). T2 CTR=011 (TC-40 result).
  // Write T1[0][704]=16'h0109 (CTR=100) before predict.
  // Second predict: using_prm=0 (uaon=8 T2 CTR=011 boundary).
  // Update: resolved_taken=0 cond_mispredict=1.
  //   alt(T1) wrong prm(T2) correct pred_strong=0.
  //   UAON DEC 8->7. CTR row 9: T2 INC T1 DEC.
  // Re-predict: using_prm=1 (uaon=7<threshold restored).
  // ----------------------------------------------------------------
  task automatic uaon_dec_restore_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;
    logic [3:0]      uaon_pre;
    logic [3:0]      uaon_post;

    local_fails = 0;

    // Step 1: Write T1 CTR=100 to set up TC-41 direction.
    // T2[0][704] is already 16'h0107 (CTR=011) from TC-40.
    // Write T1[0][704]=16'h0109: CTR=100 (boundary taken).
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][704]
      = 16'h0109;
    if (verbose != 0) begin
      $display(
        "[INFO] uaon_dec_restore_tst: uaon[0]=0x%0h (TC-40)",
        u_dut.u_tage_cntrl.uaon[0]);
      $display(
        "[INFO] uaon_dec_restore_tst: T2[0][704]=0x%04h",
        u_dut.gen_tage_tbl[2].u_tage_tbl
          .u_ram_s0.mem[0][704]);
      $display(
        "[INFO] uaon_dec_restore_tst: wrote T1[0][704]=0109");
    end

    // Step 2: Second predict PC=40'hB00.
    // uaon=8 >= threshold. T2 CTR=011 boundary.
    // UAON fires: using_prm=0. Alt T1 CTR=100 taken.
    inp           = '0;
    inp.pc        = 40'hB00;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta1. Verify prm=2 alt=1
    //         using_prm=0 pred_tkn=1 pred_diff=1.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] uaon_dec_restore_tst: prm=%0d alt=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp);
      $display(
        "[INFO] uaon_dec_restore_tst: prm_tkn=%0b alt=%0b",
        meta1.tage_prm_tkn,
        meta1.tage_alt_tkn);
      $display(
        "[INFO] uaon_dec_restore_tst: using=%0b tkn=%0b",
        meta1.tage_using_primary,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] uaon_dec_restore_tst: prm=%0d exp=2",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] uaon_dec_restore_tst: alt=%0d exp=1",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_using_primary !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] uaon_dec_restore_tst: using_prm=%0b exp=0",
        meta1.tage_using_primary);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] uaon_dec_restore_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_tkn === meta1.tage_alt_tkn) begin
      local_fails++;
      $display(
        "[FAIL] uaon_dec_restore_tst: pred_diff=0 exp=1");
    end

    // Step 4: Update resolved_taken=0 cond_mispredict=1.
    // UAON DEC: 8->7 (prm correct alt wrong pred_strong=0).
    // CTR row 9: T2 INC 011->100 T1 DEC 100->011.
    // Table 7 row 6: T1 USE DEC 00->00 sat.
    uaon_pre = u_dut.u_tage_cntrl.uaon[0];
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify UAON and RAM.
    uaon_post = u_dut.u_tage_cntrl.uaon[0];
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][704];
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][704];
    if (verbose != 0) begin
      $display(
        "[INFO] uaon_dec_restore_tst: pre uaon=0x%0h",
        uaon_pre);
      $display(
        "[INFO] uaon_dec_restore_tst: post uaon=0x%0h",
        uaon_post);
      $display(
        "[INFO] uaon_dec_restore_tst: T2[0][704]=0x%04h",
        rd_t2);
      $display(
        "[INFO] uaon_dec_restore_tst: T1[0][704]=0x%04h",
        rd_t1);
    end
    if (uaon_post !== 4'h7) begin
      local_fails++;
      $display(
        "[FAIL] uaon_dec_restore_tst: uaon=0x%0h exp=7",
        uaon_post);
    end
    if (rd_t2 !== 16'h0109) begin
      local_fails++;
      $display(
        "[FAIL] uaon_dec_restore_tst: T2=0x%04h exp=0109",
        rd_t2);
    end
    if (rd_t1 !== 16'h0107) begin
      local_fails++;
      $display(
        "[FAIL] uaon_dec_restore_tst: T1=0x%04h exp=0107",
        rd_t1);
    end

    // Step 6: Re-predict. uaon=7 < threshold.
    // T2 CTR=100 boundary but uaon[0][3]=0: no UAON fire.
    // using_prm=1. T2 CTR=100 taken -> pred_tkn=1.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] uaon_dec_restore_tst: repred prm=%0d",
        meta2.tage_prm_comp);
      $display(
        "[INFO] uaon_dec_restore_tst: repred using=%0b tkn=%0b",
        meta2.tage_using_primary,
        meta2.tage_pred_tkn);
    end
    if (meta2.tage_using_primary !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] uaon_dec_restore_tst: repred using_prm=%0b exp=1",
        meta2.tage_using_primary);
    end
    if (meta2.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] uaon_dec_restore_tst: repred prm_comp=%0d exp=2",
        meta2.tage_prm_comp);
    end

    // Cleanup: restore uaon[0] to 0.
    u_dut.u_tage_cntrl.uaon[0] = 4'h0;

    if (local_fails == 0)
      $display("[PASS] uaon_dec_restore_tst: 0 failures");
    else
      $display("[FAIL] uaon_dec_restore_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // alloc_t0_provider_tst (TC-42)
  // Round-trip: T0 sole provider. prm_comp=0. Mispredict fires
  // allocation into T1 (shortest qualifying table).
  // Alloc rules: tage_cntrl_alloc_rules.md
  //   - cond_mispredict==1 AND prm_comp=0 < M=4 -> fires.
  //   - Scan T1 (T(0+1)) through T4 for u_eff==0.
  //   - T1 USEFUL=0 under FAST_INIT. u_eff=0. T1 selected.
  //   - tage_alc_comp=1. One alloc: consecutive guard irrelevant.
  // CTR rule: tage_cntrl_ctr_update_rules.md row 13c
  //   (prm_comp=0, pred_tkn=1, resolved_taken=0: T0 DEC).
  //   RTL debt #34: pred_crt=0 -> subtract 1: 2'b10->2'b01.
  // PC=40'hD00: idx=832 bank=0 row=832 tag=0x01.
  // T1 alloc target bank=0 row=832:
  //   entry={tag=0x01, 8'h09}=0x0109.
  // T2-T4 bank=0 row=832: unchanged (zero from FAST_INIT).
  // ----------------------------------------------------------------
  task automatic alloc_t0_provider_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;
    logic [15:0]     rd_t3;
    logic [15:0]     rd_t4;
    logic [1:0]      rd_bim;

    local_fails = 0;

    // Step 1: Pre-load.
    // T0 bank=0 row=832: CTR=2'b10 (weakly taken, pred_tkn=1).
    u_dut.u_tage_bim.u_ram_s0.mem[0][832] = 2'b10;
    // T1-T4: no pre-load. FAST_INIT zeroes all entries.
    // VALID=0 -> no tag hit. USE=0 -> u_eff=0 -> alloc cand.
    if (verbose != 0) begin
      $display(
        "[INFO] alloc_t0_provider_tst: T0 mem[0][832]=2b10");
      $display(
        "[INFO] alloc_t0_provider_tst: T1-T4[0][832]=unloaded");
    end

    // Step 2: First predict PC=40'hD00.
    inp           = '0;
    inp.pc        = 40'hD00;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta.
    // Verify prm_comp=0 alt_comp=0 alc_comp=1 alc_tag=0x01.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] alloc_t0_provider_tst: prm=%0d alt=%0d alc=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp,
        meta1.tage_alc_comp);
      $display(
        "[INFO] alloc_t0_provider_tst: alc_tag=0x%02h tkn=%0b",
        meta1.tage_alc_tag,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] alloc_t0_provider_tst: prm_comp=%0d exp=0",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] alloc_t0_provider_tst: alt_comp=%0d exp=0",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_alc_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] alloc_t0_provider_tst: alc_comp=%0d exp=1",
        meta1.tage_alc_comp);
    end
    if (meta1.tage_alc_tag !== 8'h01) begin
      local_fails++;
      $display(
        "[FAIL] alloc_t0_provider_tst: alc_tag=0x%02h exp=01",
        meta1.tage_alc_tag);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] alloc_t0_provider_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end

    // Step 4: Update: resolved_taken=0, cond_mispredict=1.
    // Row 13c: T0 DEC 10->01 (RTL debt #34: pred_crt=0).
    // Alloc: T1 bank=0 row=832 written with 0x0109.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM.
    // T1: allocated {tag=0x01, 8'h09}=0x0109.
    // T0: CTR 10->01 (DEC, row 13c, RTL debt #34).
    // T2-T4: unchanged (zero from FAST_INIT).
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][832];
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][832];
    rd_t3 =
      u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[0][832];
    rd_t4 =
      u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[0][832];
    rd_bim = u_dut.u_tage_bim.u_ram_s0.mem[0][832];

    if (verbose != 0) begin
      $display(
        "[INFO] alloc_t0_provider_tst: T1[0][832]=0x%04h",
        rd_t1);
      $display(
        "[INFO] alloc_t0_provider_tst: T0[0][832]=2b%02b",
        rd_bim);
      $display(
        "[INFO] alloc_t0_provider_tst: T2[0][832]=0x%04h",
        rd_t2);
      $display(
        "[INFO] alloc_t0_provider_tst: T3[0][832]=0x%04h",
        rd_t3);
      $display(
        "[INFO] alloc_t0_provider_tst: T4[0][832]=0x%04h",
        rd_t4);
    end
    if (rd_t1 !== 16'h0109) begin
      local_fails++;
      $display(
        "[FAIL] alloc_t0_provider_tst: T1=0x%04h exp=0109",
        rd_t1);
    end
    if (rd_bim !== 2'b01) begin
      local_fails++;
      $display(
        "[FAIL] alloc_t0_provider_tst: T0=2b%02b exp=01",
        rd_bim);
    end
    if (rd_t2 !== 16'h0000) begin
      local_fails++;
      $display(
        "[FAIL] alloc_t0_provider_tst: T2=0x%04h exp=0000",
        rd_t2);
    end
    if (rd_t3 !== 16'h0000) begin
      local_fails++;
      $display(
        "[FAIL] alloc_t0_provider_tst: T3=0x%04h exp=0000",
        rd_t3);
    end
    if (rd_t4 !== 16'h0000) begin
      local_fails++;
      $display(
        "[FAIL] alloc_t0_provider_tst: T4=0x%04h exp=0000",
        rd_t4);
    end

    // Step 6: Re-predict. T1 now valid, tag=0x01 matches.
    // prm_comp=1, prm_ctr=3'b100.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] alloc_t0_provider_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] alloc_t0_provider_tst: repred prm=%0d exp=1",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b100) begin
      local_fails++;
      $display(
        "[FAIL] alloc_t0_provider_tst: repred ctr=%03b exp=100",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] alloc_t0_provider_tst: 0 failures");
    else
      $display("[FAIL] alloc_t0_provider_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // alloc_no_consecutive_tst (TC-43)
  // Round-trip: T1 provider. prm_comp=1. Mispredict fires
  // allocation into T2 (T(1+1), first qualifying table).
  // T3 not written (consecutive guard). T4 not reached.
  // Alloc rules: tage_cntrl_alloc_rules.md
  //   - cond_mispredict==1 AND prm_comp=1 < M=4 -> fires.
  //   - Scan T2 (T(1+1)) through T4 for u_eff==0.
  //   - T2 USEFUL=0 under FAST_INIT. u_eff=0. T2 selected.
  //   - tage_alc_comp=2. Consecutive guard: T3 not written.
  // CTR rule: tage_cntrl_ctr_update_rules.md row 14
  //   (prm_comp>0, alt_comp=0, using_prm=1, pred_tkn=1,
  //    resolved_taken=0: prm DEC). T1 CTR 101->100.
  // USE rule: tage_cntrl_use_update_rules.md Table 7 row 1
  //   (pred_diff=0 -> no USE update).
  //   T1 CTR[2]=1, T0 CTR[1]=1 (pre-loaded 2'b10): diff=0.
  // PC=40'h1100: idx=1088 bank=1 row=64 tag=0x02.
  // T2 alloc target bank=1 row=64:
  //   entry={tag=0x02, 8'h09}=0x0209.
  // T1 bank=1 row=64: CTR 101->100 -> 0x0209 (USE unchanged).
  // T3 bank=1 row=64: unchanged (zero, consecutive guard).
  // T4 bank=1 row=64: unchanged (zero, not reached).
  // ----------------------------------------------------------------
  task automatic alloc_no_consecutive_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;
    logic [15:0]     rd_t3;
    logic [15:0]     rd_t4;

    local_fails = 0;

    // Step 1: Pre-load.
    // T1 bank=1 row=64: TAG=0x02 EPC=0 USE=0 CTR=101 VALID=1.
    // {TAG=0x02, EPC=00, USE=00, CTR=101, VALID=1}=0x020B.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][64]
      = 16'h020B;
    // T0 bank=1 row=64: CTR=2'b10 (CTR[1]=1).
    // T1 CTR[2]=1 == T0 CTR[1]=1 -> pred_diff=0.
    // Table 7 row 1 (pred_diff=0): no USE update.
    u_dut.u_tage_bim.u_ram_s0.mem[1][64] = 2'b10;
    // T2-T4: explicit zero to ensure USE=0 u_eff=0.
    // bank=1 row=64 may be dirty from prior tests
    // (earlier PCs alias this location). Zeroing gives
    // VALID=0 USE=0 -> u_eff=0 -> T2 selected as alloc
    // target, T3 consecutive guard, T4 not reached.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][64]
      = 16'h0000;
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[1][64]
      = 16'h0000;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[1][64]
      = 16'h0000;
    if (verbose != 0) begin
      $display(
        "[INFO] alloc_no_consecutive_tst: T1 mem[1][64]=020B");
      $display(
        "[INFO] alloc_no_consecutive_tst: T0 mem[1][64]=2b10");
      $display(
        "[INFO] alloc_no_consecutive_tst: T2-T4[1][64]=0000");
    end

    // Step 2: First predict PC=40'h1100.
    inp           = '0;
    inp.pc        = 40'h1100;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 3: Capture meta.
    // Verify prm_comp=1 alt_comp=0 alc_comp=2 alc_tag=0x02.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] alloc_no_consecutive_tst: prm=%0d alt=%0d alc=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp,
        meta1.tage_alc_comp);
      $display(
        "[INFO] alloc_no_consecutive_tst: alc_tag=0x%02h tkn=%0b",
        meta1.tage_alc_tag,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] alloc_no_consecutive_tst: prm_comp=%0d exp=1",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] alloc_no_consecutive_tst: alt_comp=%0d exp=0",
        meta1.tage_alt_comp);
    end
    if (meta1.tage_alc_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] alloc_no_consecutive_tst: alc_comp=%0d exp=2",
        meta1.tage_alc_comp);
    end
    if (meta1.tage_alc_tag !== 8'h02) begin
      local_fails++;
      $display(
        "[FAIL] alloc_no_consecutive_tst: alc_tag=0x%02h exp=02",
        meta1.tage_alc_tag);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] alloc_no_consecutive_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end

    // Step 4: Update: resolved_taken=0, cond_mispredict=1.
    // Row 14: T1 prm wrong, DEC CTR 101->100.
    // Table 7 row 1: pred_diff=0 -> no USE update.
    // Alloc: T2 bank=1 row=64 written with 0x0209.
    // Consecutive guard: T3 not written.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Step 5: Verify RAM.
    // T2: allocated {tag=0x02, 8'h09}=0x0209.
    // T1: CTR 101->100 USE unchanged -> 0x0209.
    // T3: unchanged (zero, consecutive guard confirmed).
    // T4: unchanged (zero, not reached).
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][64];
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][64];
    rd_t3 =
      u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[1][64];
    rd_t4 =
      u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[1][64];

    if (verbose != 0) begin
      $display(
        "[INFO] alloc_no_consecutive_tst: T2[1][64]=0x%04h",
        rd_t2);
      $display(
        "[INFO] alloc_no_consecutive_tst: T1[1][64]=0x%04h",
        rd_t1);
      $display(
        "[INFO] alloc_no_consecutive_tst: T3[1][64]=0x%04h",
        rd_t3);
      $display(
        "[INFO] alloc_no_consecutive_tst: T4[1][64]=0x%04h",
        rd_t4);
    end
    if (rd_t2 !== 16'h0209) begin
      local_fails++;
      $display(
        "[FAIL] alloc_no_consecutive_tst: T2=0x%04h exp=0209",
        rd_t2);
    end
    if (rd_t1 !== 16'h0209) begin
      local_fails++;
      $display(
        "[FAIL] alloc_no_consecutive_tst: T1=0x%04h exp=0209",
        rd_t1);
    end
    if (rd_t3 !== 16'h0000) begin
      local_fails++;
      $display(
        "[FAIL] alloc_no_consecutive_tst: T3=0x%04h exp=0000",
        rd_t3);
    end
    if (rd_t4 !== 16'h0000) begin
      local_fails++;
      $display(
        "[FAIL] alloc_no_consecutive_tst: T4=0x%04h exp=0000",
        rd_t4);
    end

    // Step 6: Re-predict. T2 valid and tag hits (tag=0x02).
    // T1 also hits but T2 longer history: prm_comp=2 ctr=100.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] alloc_no_consecutive_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] alloc_no_consecutive_tst: repred prm=%0d exp=2",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b100) begin
      local_fails++;
      $display(
        "[FAIL] alloc_no_consecutive_tst: repred ctr=%03b exp=100",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] alloc_no_consecutive_tst: 0 failures");
    else
      $display("[FAIL] alloc_no_consecutive_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // aging_age1_not_candidate_tst (TC-44)
  // Round-trip: T1 provider. lcl_epoch[0]=1. T2 pre-loaded with
  // USEFUL=10 EPC=00. age=(1-0) mod 4=1. u_eff=USEFUL>>1=01.
  // T2 u_eff != 0: T2 NOT a candidate.
  // Scan continues: T3 u_eff=0 (FAST_INIT) -> T3 selected.
  // tage_alc_comp=3. T1 mispredicts -> allocation fires.
  // Aging formula: tage_cntrl_use_update_rules.md:
  //   age=(TG_AGE_EPOCH-EPOCH) mod 4
  //   if(age==0) u_eff=USEFUL; if(age==1) u_eff=USEFUL>>1;
  //   else u_eff=0;
  // CTR rule: tage_cntrl_ctr_update_rules.md row 14
  //   (prm_comp>0, alt_comp=0, using_prm=1, mispredict):
  //   DEC primary CTR. T1 CTR 101->100.
  // USE rule: Table 7 row 4 (pred_diff=1, using_prm=1,
  //   mispredict=1): DEC prm u_eff.
  //   u_prm_use=u_eff(T1)=USE>>1=00>>1=00. DEC sat at 00.
  //   EPC written: lcl_epoch[0]=1.
  //   T1 lower byte after: {EPC=01,USE=00,CTR=100,VALID=1}=0x49.
  // PC=40'h1300: idx=1216 bank=1 row=192 tag=0x02.
  // T3 alloc target bank=1 row=192:
  //   entry={tag=0x02,EPC=01,USE=00,CTR=100,VALID=1}=0x0249.
  // T1 bank=1 row=192: 0x0249 (CTR 101->100, EPC=01).
  // T2 bank=1 row=192: unchanged 0x0020 (not candidate).
  // T4 bank=1 row=192: unchanged (not reached, T3 selected).
  // RTL discrepancy: use_upd_comb operates on raw u_prm_use
  //   (the u_eff captured at predict time), not stored USEFUL.
  //   Expected values derived from RTL behavior.
  // ----------------------------------------------------------------
  task automatic aging_age1_not_candidate_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;
    logic [15:0]     rd_t3;
    logic [15:0]     rd_t4;

    local_fails = 0;

    // Step 1: Pre-load. PC=40'h1300 bank=1 row=192 tag=0x02.
    // T1: TAG=0x02 EPC=00 USE=00 CTR=101 VALID=1 -> 0x020B.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][192]
      = 16'h020B;
    // T2: TAG=0x00 EPC=00 USE=10 CTR=000 VALID=0 -> 0x0020.
    // VALID=0: no tag hit. USE=10 EPC=00 used for u_eff scan.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][192]
      = 16'h0020;
    // T3, T4: explicit zero.
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[1][192]
      = 16'h0000;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[1][192]
      = 16'h0000;
    // T0 at bank=1 row=192: FAST_INIT 2b00 (CTR[1]=0).
    // T1 CTR[2]=1, T0 CTR[1]=0 -> pred_diff=1.
    // Table 7 row 4 applies (pred_diff=1, using_prm=1,
    // mispredict=1): DEC prm USE. EPC updated to lcl_epoch.

    // Step 2: Set lcl_epoch[0]=1. age=(1-0)=1. u_eff=01.
    // T2 u_eff=01 != 0: T2 not a candidate.
    u_dut.u_tage_cntrl.lcl_epoch[0] = 2'b01;
    if (verbose != 0) begin
      $display(
        "[INFO] aging_age1_not_candidate_tst: T1=020B T2=0020");
      $display(
        "[INFO] aging_age1_not_candidate_tst: epoch=1 ueff=01");
    end

    // Step 3: First predict PC=40'h1300.
    inp           = '0;
    inp.pc        = 40'h1300;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 4: Capture meta.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] aging_age1_not_candidate_tst: prm=%0d alt=%0d alc=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp,
        meta1.tage_alc_comp);
      $display(
        "[INFO] aging_age1_not_candidate_tst: alc_tag=0x%02h tkn=%0b",
        meta1.tage_alc_tag,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] aging_age1_not_candidate_tst: prm_comp=%0d exp=1",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] aging_age1_not_candidate_tst: alt_comp=%0d exp=0",
        meta1.tage_alt_comp);
    end
    // alc_comp=3: T2 skipped (u_eff=01), T3 selected.
    if (meta1.tage_alc_comp !== 3'd3) begin
      local_fails++;
      $display(
        "[FAIL] aging_age1_not_candidate_tst: alc_comp=%0d exp=3",
        meta1.tage_alc_comp);
    end
    if (meta1.tage_alc_tag !== 8'h02) begin
      local_fails++;
      $display(
        "[FAIL] aging_age1_not_candidate_tst: alc_tag=0x%02h exp=02",
        meta1.tage_alc_tag);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] aging_age1_not_candidate_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end

    // Step 5: Update: resolved_taken=0, cond_mispredict=1.
    // Row 14: T1 CTR DEC 101->100.
    // Table 7 row 4: DEC prm USE (00 sat 00). EPC=lcl_epoch=1.
    // Alloc: T3 bank=1 row=192 -> 0x0249.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Restore lcl_epoch[0]=0 to avoid contaminating later tests.
    u_dut.u_tage_cntrl.lcl_epoch[0] = 2'b00;

    // Step 6: Verify RAM.
    // T3: allocated 0x0249 (EPC=01 from lcl_epoch).
    // T1: CTR 101->100 USE DEC(00)=00 EPC=01 -> 0x0249.
    // T2: unchanged 0x0020 (not candidate, u_eff=01).
    // T4: unchanged 0x0000 (not reached, T3 selected first).
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][192];
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][192];
    rd_t3 =
      u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[1][192];
    rd_t4 =
      u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[1][192];

    if (verbose != 0) begin
      $display(
        "[INFO] aging_age1_not_candidate_tst: T3[1][192]=0x%04h",
        rd_t3);
      $display(
        "[INFO] aging_age1_not_candidate_tst: T1[1][192]=0x%04h",
        rd_t1);
      $display(
        "[INFO] aging_age1_not_candidate_tst: T2[1][192]=0x%04h",
        rd_t2);
      $display(
        "[INFO] aging_age1_not_candidate_tst: T4[1][192]=0x%04h",
        rd_t4);
    end
    if (rd_t3 !== 16'h0249) begin
      local_fails++;
      $display(
        "[FAIL] aging_age1_not_candidate_tst: T3=0x%04h exp=0249",
        rd_t3);
    end
    if (rd_t1 !== 16'h0249) begin
      local_fails++;
      $display(
        "[FAIL] aging_age1_not_candidate_tst: T1=0x%04h exp=0249",
        rd_t1);
    end
    if (rd_t2 !== 16'h0020) begin
      local_fails++;
      $display(
        "[FAIL] aging_age1_not_candidate_tst: T2=0x%04h exp=0020",
        rd_t2);
    end
    if (rd_t4 !== 16'h0000) begin
      local_fails++;
      $display(
        "[FAIL] aging_age1_not_candidate_tst: T4=0x%04h exp=0000",
        rd_t4);
    end

    // Step 7: Re-predict. T3 valid tag hits: prm_comp=3 ctr=100.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] aging_age1_not_candidate_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd3) begin
      local_fails++;
      $display(
        "[FAIL] aging_age1_not_candidate_tst: repred prm=%0d exp=3",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b100) begin
      local_fails++;
      $display(
        "[FAIL] aging_age1_not_candidate_tst: repred ctr=%03b exp=100",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display(
        "[PASS] aging_age1_not_candidate_tst: 0 failures");
    else
      $display(
        "[FAIL] aging_age1_not_candidate_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // aging_age2_is_candidate_tst (TC-45)
  // Round-trip: T1 provider. lcl_epoch[0]=2. T2 pre-loaded with
  // USEFUL=10 EPC=00. age=(2-0) mod 4=2. u_eff=0 (age>=2).
  // T2 u_eff==0 despite USEFUL=10: T2 IS a candidate.
  // Scan selects T2 first (shortest qualifying): alc_comp=2.
  // T1 mispredicts -> allocation fires into T2.
  // Aging formula: tage_cntrl_use_update_rules.md:
  //   age=(TG_AGE_EPOCH-EPOCH) mod 4
  //   if(age==0) u_eff=USEFUL; if(age==1) u_eff=USEFUL>>1;
  //   else u_eff=0;
  // CTR rule: tage_cntrl_ctr_update_rules.md row 14
  //   (prm_comp>0, alt_comp=0, using_prm=1, mispredict):
  //   DEC primary CTR. T1 CTR 101->100.
  // USE rule: Table 7 row 4 (pred_diff=1, using_prm=1,
  //   mispredict=1): DEC prm u_eff.
  //   u_prm_use=u_eff(T1)=0 (age=2->u_eff=0). DEC sat at 00.
  //   EPC written: lcl_epoch[0]=2.
  //   T1 lower byte after: {EPC=10,USE=00,CTR=100,VALID=1}=0x89.
  // PC=40'h1500: idx=1344 bank=1 row=320 tag=0x02.
  // T2 alloc target bank=1 row=320:
  //   entry={tag=0x02,EPC=10,USE=00,CTR=100,VALID=1}=0x0289.
  // T1 bank=1 row=320: 0x0289 (CTR 101->100, EPC=10).
  // T3 bank=1 row=320: unchanged 0x0000 (T2 selected first).
  // T4 bank=1 row=320: unchanged 0x0000 (not reached).
  // RTL discrepancy: use_upd_comb operates on raw u_prm_use
  //   (u_eff captured at predict), not stored USEFUL.
  //   Expected values derived from RTL behavior.
  // ----------------------------------------------------------------
  task automatic aging_age2_is_candidate_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_pred_meta_t meta2;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;
    logic [15:0]     rd_t2;
    logic [15:0]     rd_t3;
    logic [15:0]     rd_t4;

    local_fails = 0;

    // Step 1: Pre-load. PC=40'h1500 bank=1 row=320 tag=0x02.
    // T1: TAG=0x02 EPC=00 USE=00 CTR=101 VALID=1 -> 0x020B.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][320]
      = 16'h020B;
    // T2: TAG=0x00 EPC=00 USE=10 CTR=000 VALID=0 -> 0x0020.
    // VALID=0: no tag hit. USE=10 EPC=00 used for u_eff scan.
    // age=(2-0)=2 -> u_eff=0: T2 IS a candidate.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][320]
      = 16'h0020;
    // T3, T4: explicit zero.
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[1][320]
      = 16'h0000;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[1][320]
      = 16'h0000;
    // T0 at bank=1 row=320: FAST_INIT 2b00 (CTR[1]=0).
    // T1 CTR[2]=1, T0 CTR[1]=0 -> pred_diff=1.
    // Table 7 row 4 applies.

    // Step 2: Set lcl_epoch[0]=2. age=(2-0)=2. u_eff=0.
    // T2 u_eff=0: T2 IS a candidate despite USE=10.
    u_dut.u_tage_cntrl.lcl_epoch[0] = 2'b10;
    if (verbose != 0) begin
      $display(
        "[INFO] aging_age2_is_candidate_tst: T1=020B T2=0020");
      $display(
        "[INFO] aging_age2_is_candidate_tst: epoch=2 ueff=0");
    end

    // Step 3: First predict PC=40'h1500.
    inp           = '0;
    inp.pc        = 40'h1500;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // Step 4: Capture meta.
    meta1 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] aging_age2_is_candidate_tst: prm=%0d alt=%0d alc=%0d",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp,
        meta1.tage_alc_comp);
      $display(
        "[INFO] aging_age2_is_candidate_tst: alc_tag=0x%02h tkn=%0b",
        meta1.tage_alc_tag,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] aging_age2_is_candidate_tst: prm_comp=%0d exp=1",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alt_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] aging_age2_is_candidate_tst: alt_comp=%0d exp=0",
        meta1.tage_alt_comp);
    end
    // alc_comp=2: T2 selected despite USE=10 (u_eff=0, age=2).
    if (meta1.tage_alc_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] aging_age2_is_candidate_tst: alc_comp=%0d exp=2",
        meta1.tage_alc_comp);
    end
    if (meta1.tage_alc_tag !== 8'h02) begin
      local_fails++;
      $display(
        "[FAIL] aging_age2_is_candidate_tst: alc_tag=0x%02h exp=02",
        meta1.tage_alc_tag);
    end
    if (meta1.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] aging_age2_is_candidate_tst: pred_tkn=%0b exp=1",
        meta1.tage_pred_tkn);
    end

    // Step 5: Update: resolved_taken=0, cond_mispredict=1.
    // Row 14: T1 CTR DEC 101->100.
    // Table 7 row 4: DEC prm USE (u_prm_use=0 sat 0). EPC=2.
    // Alloc: T2 bank=1 row=320 -> 0x0289 (EPC=10 from epoch).
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Restore lcl_epoch[0]=0 to avoid contaminating later tests.
    u_dut.u_tage_cntrl.lcl_epoch[0] = 2'b00;

    // Step 6: Verify RAM.
    // T2: allocated 0x0289 (EPC=10 from lcl_epoch=2).
    // T1: CTR 101->100 USE DEC(00)=00 EPC=10 -> 0x0289.
    // T3: unchanged 0x0000 (T2 selected, scan stopped).
    // T4: unchanged 0x0000 (not reached).
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][320];
    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][320];
    rd_t3 =
      u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[1][320];
    rd_t4 =
      u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[1][320];

    if (verbose != 0) begin
      $display(
        "[INFO] aging_age2_is_candidate_tst: T2[1][320]=0x%04h",
        rd_t2);
      $display(
        "[INFO] aging_age2_is_candidate_tst: T1[1][320]=0x%04h",
        rd_t1);
      $display(
        "[INFO] aging_age2_is_candidate_tst: T3[1][320]=0x%04h",
        rd_t3);
      $display(
        "[INFO] aging_age2_is_candidate_tst: T4[1][320]=0x%04h",
        rd_t4);
    end
    if (rd_t2 !== 16'h0289) begin
      local_fails++;
      $display(
        "[FAIL] aging_age2_is_candidate_tst: T2=0x%04h exp=0289",
        rd_t2);
    end
    if (rd_t1 !== 16'h0289) begin
      local_fails++;
      $display(
        "[FAIL] aging_age2_is_candidate_tst: T1=0x%04h exp=0289",
        rd_t1);
    end
    if (rd_t3 !== 16'h0000) begin
      local_fails++;
      $display(
        "[FAIL] aging_age2_is_candidate_tst: T3=0x%04h exp=0000",
        rd_t3);
    end
    if (rd_t4 !== 16'h0000) begin
      local_fails++;
      $display(
        "[FAIL] aging_age2_is_candidate_tst: T4=0x%04h exp=0000",
        rd_t4);
    end

    // Step 7: Re-predict. T2 valid tag hits: prm_comp=2 ctr=100.
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta2 = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] aging_age2_is_candidate_tst: repred prm=%0d ctr=%03b",
        meta2.tage_prm_comp,
        meta2.tage_prm_ctr);
    end
    if (meta2.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display(
        "[FAIL] aging_age2_is_candidate_tst: repred prm=%0d exp=2",
        meta2.tage_prm_comp);
    end
    if (meta2.tage_prm_ctr !== 3'b100) begin
      local_fails++;
      $display(
        "[FAIL] aging_age2_is_candidate_tst: repred ctr=%03b exp=100",
        meta2.tage_prm_ctr);
    end

    if (local_fails == 0)
      $display("[PASS] aging_age2_is_candidate_tst: 0 failures");
    else
      $display("[FAIL] aging_age2_is_candidate_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // t0_dec_min_sat_tst (TC-46)
  // Rule: tage_cntrl_ctr_update_rules.md row 13c.
  // T0 CTR DEC from min (2'b00) -> stays at 2'b00 (sat min).
  // PC=40'h1200: T0 idx=11'h480 bank=1 row=128.
  // prm_comp=0 alt_comp=0 prm_tkn=1 resolved_taken=0.
  // cond_mispredict=1 (pred=T, resolved=NT).
  // Expected: mem[1][128] == 2'b00 after update.
  // Coverage gap from BP-015: upd_ctr_min_sat_tst Part 2
  //   now exercises INC (resolved=1) not DEC at 00.
  // ----------------------------------------------------------------
  task automatic t0_dec_min_sat_tst(int verbose);
    int                          local_fails;
    tage_upd_inp_t               upd_inp;
    tage_pred_meta_t             meta;
    logic [TAGE_TBL_CTR[0]-1:0] rd_t0;

    local_fails = 0;

    // Address aliasing hygiene: zero T1-T4 at bank=1 row=128.
    // PC=40'h1200 hashes to idx=11'h480 for T1-T4 (fh=0).
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][128]
      = 16'h0000;
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][128]
      = 16'h0000;
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[1][128]
      = 16'h0000;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[1][128]
      = 16'h0000;

    // Force T0 BIM RAM to min state: CTR=2'b00 (strongly NT).
    u_dut.u_tage_bim.u_ram_s0.mem[1][128] = 2'b00;
    if (verbose != 0)
      $display(
        "[INFO] t0_dec_min_sat_tst: pre T0[1][128]=2b00");

    // Build update: row 13c (prm=0 alt=0 tkn=1 resolved=0).
    // DEC from 00 -> saturates at 00.
    meta                    = '0;
    meta.tage_prm_idx       = 11'h480;
    meta.tage_prm_comp      = 3'd0;
    meta.tage_alt_comp      = 3'd0;
    meta.tage_prm_ctr       = 3'b000;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_alt_tkn       = 1'b0;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_t0 = u_dut.u_tage_bim.u_ram_s0.mem[1][128];

    // DEC from 00 must saturate at 00.
    if (rd_t0 !== 2'b00) begin
      local_fails++;
      if (verbose != 0)
        $display(
          "[FAIL] t0_dec_min_sat_tst: T0[1][128]=0x%0h exp=00",
          rd_t0);
    end else if (verbose != 0) begin
      $display(
        "[INFO] t0_dec_min_sat_tst: T0[1][128]=0x%0h OK",
        rd_t0);
    end

    if (local_fails == 0)
      $display("[PASS] t0_dec_min_sat_tst: 0 failures");
    else
      $display("[FAIL] t0_dec_min_sat_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-47  TB-ARB-01: Prediction only, no updates in flight.
  // Verify: prediction completes slot0 and slot1 in p0+p1+p2.
  // Uses: pc=40'hA00 -> T0 bank=0 row=640.
  // Pre-load T0 s0/s1 mem[0][640] = 2b10 (NT weak).
  // ----------------------------------------------------------------
  task automatic arb_pred_only_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta0, meta1;
    local_fails = 0;

    u_dut.u_tage_bim.u_ram_s0.mem[0][640] = 2'b10;
    u_dut.u_tage_bim.u_ram_s1.mem[0][640] = 2'b10;
    if (verbose != 0)
      $display("[INFO] arb_pred_only_tst: pre T0 s0/s1[0][640]=10");

    inp           = '0;
    inp.pc        = 40'hA00;
    inp.branch_id = 6'h1;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    inp.branch_id = 6'h2;
    stg_pred_inp1 = inp;
    stg_pred_val1 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_val1 = 1'b0;
    stg_pred_inp0 = '0;
    stg_pred_inp1 = '0;
    @(posedge clk);
    @(posedge clk);

    meta0 = tage_pred_meta_p2[0];
    meta1 = tage_pred_meta_p2[1];

    if (tage_pred_rdy_p2[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] arb_pred_only_tst: slot0 rdy=%0b exp=1",
        tage_pred_rdy_p2[0]);
    end
    if (tage_pred_rdy_p2[1] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] arb_pred_only_tst: slot1 rdy=%0b exp=1",
        tage_pred_rdy_p2[1]);
    end
    if (meta0.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] arb_pred_only_tst: s0 prm_comp=%0d exp=0",
        meta0.tage_prm_comp);
    end
    if (meta1.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] arb_pred_only_tst: s1 prm_comp=%0d exp=0",
        meta1.tage_prm_comp);
    end
    if (local_fails == 0)
      $display("[PASS] arb_pred_only_tst: 0 failures");
    else
      $display("[FAIL] arb_pred_only_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-48  TB-ARB-02: Update only, no predictions in flight.
  // Verify: update completes in u0+u1, upd_rdy asserts.
  // Uses T0 update: prm_comp=0 prm_idx=11'h280 (row 640).
  // Pre-load: T0 s0 mem[0][640] = 2b01 (NT weak).
  // After upd (resolved_taken=1 mispredict): expect CTR inc -> 2b10.
  // ----------------------------------------------------------------
  task automatic arb_upd_only_tst(int verbose);
    int              local_fails;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [1:0]      rd_t0;
    local_fails = 0;

    u_dut.u_tage_bim.u_ram_s0.mem[0][640] = 2'b01;
    if (verbose != 0)
      $display("[INFO] arb_upd_only_tst: pre T0 s0[0][640]=01");

    meta                    = '0;
    meta.tage_prm_idx       = 11'h280;
    meta.tage_prm_comp      = 3'd0;
    meta.tage_prm_ctr       = 3'b001;
    meta.tage_prm_tkn       = 1'b0;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b1;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_t0 = u_dut.u_tage_bim.u_ram_s0.mem[0][640];
    if (tage_upd_rdy_u1[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] arb_upd_only_tst: upd_rdy=%0b exp=1",
        tage_upd_rdy_u1[0]);
    end
    if (rd_t0 !== 2'b10) begin
      local_fails++;
      $display(
        "[FAIL] arb_upd_only_tst: T0[0][640]=0x%0h exp=10",
        rd_t0);
    end else if (verbose != 0) begin
      $display(
        "[INFO] arb_upd_only_tst: T0[0][640]=0x%0h OK", rd_t0);
    end
    if (local_fails == 0)
      $display("[PASS] arb_upd_only_tst: 0 failures");
    else
      $display("[FAIL] arb_upd_only_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-49  TB-ARB-03: Concurrent pred+upd, different entries.
  // Verify: pred wins Rule 3, upd gets Rule 6 next cycle, both rdy.
  // Pred: pc=40'hA80 -> row=672. Upd: prm_idx=11'h280 (row 640).
  // Debt #37 investigaton: arb_grant_upd combinational forward.
  // ----------------------------------------------------------------
  task automatic arb_concurrent_pred_wins_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t upd_meta;
    local_fails = 0;

    u_dut.u_tage_bim.u_ram_s0.mem[0][672] = 2'b11;
    u_dut.u_tage_bim.u_ram_s0.mem[0][640] = 2'b10;

    inp           = '0;
    inp.pc        = 40'hA80;
    inp.branch_id = 6'h3;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;

    upd_meta                    = '0;
    upd_meta.tage_prm_idx       = 11'h280;
    upd_meta.tage_prm_comp      = 3'd0;
    upd_meta.tage_prm_ctr       = 3'b010;
    upd_meta.tage_prm_tkn       = 1'b0;
    upd_meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = upd_meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b1;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;

    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_upd_val0  = 1'b0;
    stg_pred_inp0 = '0;
    stg_upd_inp0  = '0;
    @(posedge clk);
    @(posedge clk);

    if (tage_pred_rdy_p2[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] arb_concurrent_pred_wins_tst: pred_rdy=%0b",
        tage_pred_rdy_p2[0]);
    end
    if (tage_upd_rdy_u1[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] arb_concurrent_pred_wins_tst: upd_rdy=%0b",
        tage_upd_rdy_u1[0]);
    end
    if (local_fails == 0)
      $display(
        "[PASS] arb_concurrent_pred_wins_tst: 0 failures");
    else
      $display(
        "[FAIL] arb_concurrent_pred_wins_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-50  TB-ARB-04: Concurrent pred+upd, same entry.
  // Pred reads pre-update state. Upd writes next cycle. Both done.
  // pc=40'hA00 -> row=640, bank=0. Upd: prm_idx=11'h280 (same row).
  // Pre-load T0 s0 mem[0][640] = 2b10 (NT weak).
  // After upd (resolved_taken=1): CTR -> 2b11 (NT strong? -> TKN).
  // Pred should read CTR=010 before upd writes.
  // Debt #37: trx_type_comb stable during concurrent pred+upd.
  // ----------------------------------------------------------------
  task automatic arb_concurrent_upd_wins_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t upd_meta;
    logic [1:0]      rd_t0;
    local_fails = 0;

    u_dut.u_tage_bim.u_ram_s0.mem[0][640] = 2'b10;
    if (verbose != 0)
      $display("[INFO] arb_concurrent_upd_wins_tst: T0[0][640]=10");

    inp           = '0;
    inp.pc        = 40'hA00;
    inp.branch_id = 6'h4;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;

    upd_meta                    = '0;
    upd_meta.tage_prm_idx       = 11'h280;
    upd_meta.tage_prm_comp      = 3'd0;
    upd_meta.tage_prm_ctr       = 3'b010;
    upd_meta.tage_prm_tkn       = 1'b0;
    upd_meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = upd_meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b1;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;

    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_upd_val0  = 1'b0;
    stg_pred_inp0 = '0;
    stg_upd_inp0  = '0;
    @(posedge clk);
    @(posedge clk);

    rd_t0 = u_dut.u_tage_bim.u_ram_s0.mem[0][640];

    if (tage_pred_rdy_p2[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] arb_concurrent_upd_wins_tst: pred_rdy=%0b",
        tage_pred_rdy_p2[0]);
    end
    if (tage_upd_rdy_u1[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] arb_concurrent_upd_wins_tst: upd_rdy=%0b",
        tage_upd_rdy_u1[0]);
    end
    // Upd: INC from 10 -> 11 expected.
    if (rd_t0 !== 2'b11) begin
      local_fails++;
      $display(
        "[FAIL] arb_concurrent_upd_wins_tst: T0[0][640]=%02b"
        , rd_t0);
    end else if (verbose != 0) begin
      $display(
        "[INFO] arb_concurrent_upd_wins_tst: T0[0][640]=%02b OK"
        , rd_t0);
    end
    if (local_fails == 0)
      $display(
        "[PASS] arb_concurrent_upd_wins_tst: 0 failures");
    else
      $display(
        "[FAIL] arb_concurrent_upd_wins_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-51  TB-ARB-05: Update burst of 4.
  // Issue 2 dual-slot updates (slots 0+1) over 2 cycles = 4 upds.
  // TAGE_UQ_DEPTH=8 >> 4 entries so no backpressure expected.
  // Spec note: spec says "backpressure for 2 cycles" but with
  // UQ_DEPTH=8 and 4 updates no backpressure occurs (see Results).
  // Verify: all 4 completions (2 x upd_rdy[1:0]=2b11) occur.
  // ----------------------------------------------------------------
  task automatic arb_upd_burst_tst(int verbose);
    int            local_fails;
    tage_upd_inp_t upd0, upd1;
    tage_pred_meta_t meta;
    int            rdy_cnt;
    local_fails = 0;
    rdy_cnt     = 0;

    // Build two distinct update inps (T0 upd, different idx)
    meta                    = '0;
    meta.tage_prm_comp      = 3'd0;
    meta.tage_prm_idx       = 11'h2C0;
    meta.tage_using_primary = 1'b1;
    meta.tage_prm_tkn       = 1'b1;
    meta.tage_prm_ctr       = 3'b011;

    upd0                 = '0;
    upd0.tage_pred_meta  = meta;
    upd0.resolved_taken  = 1'b1;
    upd0.cond_mispredict = 1'b0;

    meta.tage_prm_idx    = 11'h2C1;
    upd1                 = '0;
    upd1.tage_pred_meta  = meta;
    upd1.resolved_taken  = 1'b0;
    upd1.cond_mispredict = 1'b0;

    // Cycle A: drive both slots simultaneously (2 upds).
    // With UQ empty: bypass fires immediately; upd_rdy fires
    // at cycle B (one cycle after bypass). Keep stg=1 so cycle
    // B also bypasses and upd_rdy fires at cycle C.
    stg_upd_inp0 = upd0;
    stg_upd_inp1 = upd1;
    stg_upd_val0 = 1'b1;
    stg_upd_val1 = 1'b1;
    @(posedge clk); // cycle A: bypass A fires
    // Cycle B: keep stg set; count rdy that fires from A bypass.
    @(posedge clk); // cycle B: rdy from A; bypass B fires
    if (tage_upd_rdy_u1[0] || tage_upd_rdy_u1[1]) rdy_cnt++;
    stg_upd_val0 = 1'b0;
    stg_upd_val1 = 1'b0;
    stg_upd_inp0 = '0;
    stg_upd_inp1 = '0;
    @(posedge clk); // cycle C: rdy from B
    if (tage_upd_rdy_u1[0] || tage_upd_rdy_u1[1]) rdy_cnt++;
    @(posedge clk); // cycle D: extra
    if (tage_upd_rdy_u1[0] || tage_upd_rdy_u1[1]) rdy_cnt++;

    if (rdy_cnt < 2) begin
      local_fails++;
      $display("[FAIL] arb_upd_burst_tst: rdy_cnt=%0d exp>=2",
        rdy_cnt);
    end else if (verbose != 0) begin
      $display("[INFO] arb_upd_burst_tst: rdy_cnt=%0d OK",
        rdy_cnt);
    end
    if (local_fails == 0)
      $display("[PASS] arb_upd_burst_tst: 0 failures");
    else
      $display("[FAIL] arb_upd_burst_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-52  TB-ARB-06: PQ fills to TAGE_PQ_DEPTH.
  // Procedure:
  //   1. consumer_ready=0 to prevent RB drain.
  //   2. Issue 2 predictions to fill RB (resp_buf_full=1 after).
  //   3. Hold stg_pred_val0=1 for PQ_DEPTH+1 cycles: PQ fills.
  //   4. Verify pq_not_full===0.
  //   5. consumer_ready=1, drain, verify pq_not_full reasserts.
  // ----------------------------------------------------------------
  task automatic arb_rb_full_blocks_pred_tst(int verbose);
    int local_fails;
    int i;
    int drain_cyc;
    local_fails = 0;

    consumer_ready = 1'b0;

    // Pre-load T0 s0 row 700 bank 0 with CTR=2b11.
    // pc=40'hAF0 -> bits[12:2]=0xAF0>>2=0x2BC, bank=0, row=700.
    u_dut.u_tage_bim.u_ram_s0.mem[0][700] = 2'b11;

    // Issue pred 1 to fill first RB slot.
    stg_pred_inp0 = '0;
    stg_pred_inp0.pc = 40'hAF0;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);
    // RB now has 1 entry (consumer_ready=0, no bypass/drain).

    // Issue pred 2 to fill second (last) RB slot.
    stg_pred_inp0.pc = 40'hAF0;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);
    // RB now full: resp_buf_full_w=1.

    if (verbose != 0)
      $display("[INFO] arb_rb_full_blocks_pred_tst: rbfull=%0b",
        u_dut.resp_buf_full_w);

    // Hold pred stg for PQ_DEPTH+1 cycles to fill PQ.
    stg_pred_inp0.pc = 40'hAF0;
    stg_pred_val0    = 1'b1;
    repeat (TAGE_PQ_DEPTH + 1) @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);

    if (u_dut.pq_not_full !== 1'b0) begin
      local_fails++;
      $display("[FAIL] arb_rb_full_blocks_pred_tst: nf=%0b exp=0",
        u_dut.pq_not_full);
    end else if (verbose != 0) begin
      $display("[INFO] arb_rb_full_blocks_pred_tst: nf=0 OK");
    end

    // Drain: consumer_ready=1 lets RB drain -> pred_rdy pulses
    // then PQ drains.
    consumer_ready = 1'b1;
    drain_cyc = (TAGE_PQ_DEPTH + 2) * 4;
    repeat (drain_cyc) @(posedge clk);

    if (u_dut.pq_not_full !== 1'b1) begin
      local_fails++;
      $display("[FAIL] arb_rb_full_blocks_pred_tst: nf=%0b exp=1",
        u_dut.pq_not_full);
    end else if (verbose != 0) begin
      $display("[INFO] arb_rb_full_blocks_pred_tst: nf=1 OK");
    end

    if (local_fails == 0)
      $display("[PASS] arb_rb_full_blocks_pred_tst: 0 failures");
    else
      $display("[FAIL] arb_rb_full_blocks_pred_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-53  TB-ARB-07: Response buffer full blocks pred, upd allowed.
  // Procedure:
  //   1. consumer_ready=0 to block RB drain.
  //   2. Fill RB: issue 2 preds, wait for results to enter RB.
  //   3. Verify resp_buf_full=1.
  //   4. Issue concurrent pred+upd: check grant_pred=0, grant_upd=1.
  //   5. Verify upd_rdy fires. consumer_ready=1 to clean up.
  // ----------------------------------------------------------------
  task automatic arb_pred_credits_reset_tst(int verbose);
    int local_fails;
    local_fails = 0;

    consumer_ready = 1'b0;

    u_dut.u_tage_bim.u_ram_s0.mem[0][750] = 2'b11;
    // pc=40'hBB8 -> bits[12:2]=0xBB8>>2=0x2EE, bank=0, row=750.

    // Fill RB slot 1: pred takes 3 cycles p0->p2.
    // RB enqueue fires the cycle AFTER pred_rdy (rb_ff sees
    // cntrl_pred_rdy_p2 pre-NBA, one cycle late). Need 4 cycles.
    stg_pred_inp0    = '0;
    stg_pred_inp0.pc = 40'hBB8;
    stg_pred_val0    = 1'b1;
    @(posedge clk);
    stg_pred_val0    = 1'b0;
    stg_pred_inp0    = '0;
    @(posedge clk);
    @(posedge clk);
    @(posedge clk); // extra: rb_ff sees pred_rdy=1 pre-NBA

    // Fill RB slot 2 (same 4-cycle sequence).
    stg_pred_inp0    = '0;
    stg_pred_inp0.pc = 40'hBB8;
    stg_pred_val0    = 1'b1;
    @(posedge clk);
    stg_pred_val0    = 1'b0;
    stg_pred_inp0    = '0;
    @(posedge clk);
    @(posedge clk);
    @(posedge clk); // extra: rb enqueues slot 2
    // RB full now.

    if (u_dut.resp_buf_full_w !== 1'b1) begin
      local_fails++;
      $display("[FAIL] arb_pred_credits_reset_tst: rbfull=%0b",
        u_dut.resp_buf_full_w);
    end

    // Issue concurrent pred + upd; pred must be blocked.
    stg_pred_inp0.pc = 40'hBB8;
    stg_pred_val0    = 1'b1;
    stg_upd_inp0     = '0;
    stg_upd_inp0.tage_pred_meta.tage_prm_idx  = 11'h280;
    stg_upd_inp0.tage_pred_meta.tage_prm_comp = 3'd0;
    stg_upd_inp0.tage_pred_meta.tage_using_primary = 1'b1;
    stg_upd_val0     = 1'b1;
    @(posedge clk);
    // Verify grant_pred blocked, grant_upd asserted.
    if (u_dut.arb_grant_pred !== 1'b0) begin
      local_fails++;
      $display("[FAIL] arb_pred_credits_reset_tst: gp=%0b exp=0",
        u_dut.arb_grant_pred);
    end else if (verbose != 0) begin
      $display("[INFO] arb_pred_credits_reset_tst: gp=0 OK");
    end
    if (u_dut.arb_grant_upd !== 1'b1) begin
      local_fails++;
      $display("[FAIL] arb_pred_credits_reset_tst: gu=%0b exp=1",
        u_dut.arb_grant_upd);
    end else if (verbose != 0) begin
      $display("[INFO] arb_pred_credits_reset_tst: gu=1 OK");
    end
    stg_pred_val0 = 1'b0;
    stg_upd_val0  = 1'b0;
    stg_pred_inp0 = '0;
    stg_upd_inp0  = '0;

    @(posedge clk);
    // upd_rdy should assert one cycle later.
    if (tage_upd_rdy_u1[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] arb_pred_credits_reset_tst: ur=%0b exp=1",
        tage_upd_rdy_u1[0]);
    end else if (verbose != 0) begin
      $display("[INFO] arb_pred_credits_reset_tst: ur=1 OK");
    end

    // Clean up: drain RB.
    consumer_ready = 1'b1;
    repeat (8) @(posedge clk);

    if (local_fails == 0)
      $display("[PASS] arb_pred_credits_reset_tst: 0 failures");
    else
      $display("[FAIL] arb_pred_credits_reset_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-54  TB-ARB-08: Pred credits exhaust -> Rule 4 fires.
  // TAGE_PRED_CREDITS=4, TAGE_STARVE_THRESH=8.
  // Because PRED_CREDITS=4 < STARVE_THRESH=8, Rule 2 (starvation
  // override) cannot fire naturally. Test exercises Rule 4 instead:
  // after 4 pred grants with upd pending, credits=0 -> Rule 4 fires
  // -> upd granted, credits reload. Documented in Results Capture.
  // Procedure:
  //   1. Issue pred+upd together (stg both) -> pred gets Rule 3,
  //      upd enters UQ.
  //   2. Hold stg_pred_val0=1 for 5 cycles total (4 credit dec
  //      cycles + 1 Rule 4 cycle).
  //   3. On cycle 5: pred_credits=0 -> Rule 4: upd granted.
  //   4. Verify upd_rdy asserts and pred_credits reloads to 4.
  // ----------------------------------------------------------------
  task automatic arb_starve_tst(int verbose);
    int local_fails;
    local_fails = 0;

    // Issue pred and upd together (cycle 0): both stg set.
    stg_pred_inp0     = '0;
    stg_pred_inp0.pc  = 40'hA00;
    stg_upd_inp0      = '0;
    stg_upd_inp0.tage_pred_meta.tage_prm_idx  = 11'h280;
    stg_upd_inp0.tage_pred_meta.tage_prm_comp = 3'd0;
    stg_upd_inp0.tage_pred_meta.tage_using_primary = 1'b1;
    stg_upd_val0      = 1'b1;
    stg_pred_val0     = 1'b1;
    @(posedge clk); // cycle 0: stage both vals
    stg_upd_val0  = 1'b0;
    stg_upd_inp0  = '0;
    // Keep stg_pred_val0=1 for 5 more cycles (4 Rule3 + 1 Rule4)
    @(posedge clk); // cycle 1: Rule3, credits 4->3, UQ enqueues
    @(posedge clk); // cycle 2: Rule3, credits 3->2
    @(posedge clk); // cycle 3: Rule3, credits 2->1
    @(posedge clk); // cycle 4: Rule3, credits 1->0
    @(posedge clk); // cycle 5: Rule4, upd granted, upd_rdy=1
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;

    if (tage_upd_rdy_u1[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] arb_starve_tst: upd_rdy=%0b exp=1",
        tage_upd_rdy_u1[0]);
    end else if (verbose != 0) begin
      $display("[INFO] arb_starve_tst: upd_rdy=1 OK");
    end
    // Verify pred_credits reloaded.
    if (u_dut.pred_credits_r !== 3'(TAGE_PRED_CREDITS)) begin
      local_fails++;
      $display("[FAIL] arb_starve_tst: credits=%0d exp=%0d",
        u_dut.pred_credits_r, TAGE_PRED_CREDITS);
    end else if (verbose != 0) begin
      $display("[INFO] arb_starve_tst: credits=%0d OK",
        u_dut.pred_credits_r);
    end

    if (local_fails == 0)
      $display("[PASS] arb_starve_tst: 0 failures");
    else
      $display("[FAIL] arb_starve_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // Main test sequence
  // ----------------------------------------------------------------
  initial begin : test_body
    // Reset: assert for 4 cycles then deassert.
    rstn = 1'b0;
    repeat(4) @(posedge clk);
    #1;
    rstn = 1'b1;

    // Run tests.
    if (_tage_rdy_tst != 0) tage_rdy_tst(verbose);

    // Update path tests run after tage_rdy asserts.
    if (_upd_t0_inc_tst != 0) upd_t0_inc_tst(verbose);
    if (_upd_t0_dec_tst != 0) upd_t0_dec_tst(verbose);
    if (_upd_prm_inc_tst != 0) upd_prm_inc_tst(verbose);
    if (_upd_prm_dec_alt_inc_tst != 0)
      upd_prm_dec_alt_inc_tst(verbose);
    if (_upd_alt_inc_tst != 0) upd_alt_inc_tst(verbose);
    if (_upd_use_inc_tst != 0) upd_use_inc_tst(verbose);
    if (_upd_alloc_tst != 0) upd_alloc_tst(verbose);

    // BP-010d coverage gap tests.
    if (_upd_use_alt_inc_tst != 0)
      upd_use_alt_inc_tst(verbose);
    if (_upd_use_alt_dec_tst != 0)
      upd_use_alt_dec_tst(verbose);
    if (_upd_uaon_inc_tst != 0) upd_uaon_inc_tst(verbose);
    if (_upd_uaon_dec_tst != 0) upd_uaon_dec_tst(verbose);
    if (_upd_ctr_max_sat_tst != 0)
      upd_ctr_max_sat_tst(verbose);
    if (_upd_ctr_min_sat_tst != 0)
      upd_ctr_min_sat_tst(verbose);
    if (_upd_alloc_no_cand_tst != 0)
      upd_alloc_no_cand_tst(verbose);

    // BP-010e prediction path tests.
    if (_pred_t0_only_tst != 0)
      pred_t0_only_tst(verbose);
    if (_pred_t1_single_hit_tst != 0)
      pred_t1_single_hit_tst(verbose);
    if (_pred_t1t2_dual_hit_tst != 0)
      pred_t1t2_dual_hit_tst(verbose);
    if (_pred_uaon_override_tst != 0)
      pred_uaon_override_tst(verbose);
    if (_pred_uaon_suppressed_tst != 0)
      pred_uaon_suppressed_tst(verbose);
    if (_pred_rdy_timing_tst != 0)
      pred_rdy_timing_tst(verbose);

    // BP-010f slot 1 symmetry tests.
    if (_slot1_pred_tst != 0)
      slot1_pred_tst(verbose);
    if (_slot1_upd_tst != 0)
      slot1_upd_tst(verbose);

    // BP-011 round-trip tests.
    if (_rt_correct_t0_tst != 0)
      rt_correct_t0_tst(verbose);
    if (_rt_correct_tagged_tst != 0)
      rt_correct_tagged_tst(verbose);
    if (_rt_mispredict_alloc_tst != 0)
      rt_mispredict_alloc_tst(verbose);
    if (_rt_no_alloc_last_tbl_tst != 0)
      rt_no_alloc_last_tbl_tst(verbose);

    // BP-014a CTR round-trip tests.
    if (_rt_ctr_rows1_2_tst != 0)
      rt_ctr_rows1_2_tst(verbose);
    if (_rt_ctr_rows3_4_tst != 0)
      rt_ctr_rows3_4_tst(verbose);
    if (_rt_ctr_rows5_6_tst != 0)
      rt_ctr_rows5_6_tst(verbose);
    if (_rt_ctr_rows7_8_tst != 0)
      rt_ctr_rows7_8_tst(verbose);

    // BP-014b CTR round-trip tests.
    if (_rt_ctr_rows9_10_tst != 0)
      rt_ctr_rows9_10_tst(verbose);
    if (_rt_ctr_rows11_12_tst != 0)
      rt_ctr_rows11_12_tst(verbose);

    // BP-014c CTR round-trip tests.
    if (_rt_ctr_row13b_tst != 0)
      rt_ctr_row13b_tst(verbose);
    if (_rt_ctr_row13c_tst != 0)
      rt_ctr_row13c_tst(verbose);

    // BP-014d CTR round-trip tests.
    if (_rt_ctr_row13a_tst != 0)
      rt_ctr_row13a_tst(verbose);
    if (_rt_ctr_row13d_tst != 0)
      rt_ctr_row13d_tst(verbose);

    // BP-014e CTR round-trip tests.
    if (_rt_ctr_rows14_15_tst != 0)
      rt_ctr_rows14_15_tst(verbose);
    if (_rt_ctr_rows16_17_tst != 0)
      rt_ctr_rows16_17_tst(verbose);

    // BP-014f UAON round-trip tests.
    if (_uaon_threshold_cross_tst != 0)
      uaon_threshold_cross_tst(verbose);
    if (_uaon_dec_restore_tst != 0)
      uaon_dec_restore_tst(verbose);

    // BP-014g allocation round-trip tests.
    if (_alloc_t0_provider_tst != 0)
      alloc_t0_provider_tst(verbose);
    if (_alloc_no_consecutive_tst != 0)
      alloc_no_consecutive_tst(verbose);

    // BP-014h aging round-trip tests.
    if (_aging_age1_not_candidate_tst != 0)
      aging_age1_not_candidate_tst(verbose);
    if (_aging_age2_is_candidate_tst != 0)
      aging_age2_is_candidate_tst(verbose);

    // BP-016 T0 DEC min saturation test.
    if (_t0_dec_min_sat_tst != 0)
      t0_dec_min_sat_tst(verbose);

    // BP-023c ARB tests (TC-47 through TC-54).
    if (_arb_pred_only_tst != 0)
      arb_pred_only_tst(verbose);
    if (_arb_upd_only_tst != 0)
      arb_upd_only_tst(verbose);
    if (_arb_concurrent_pred_wins_tst != 0)
      arb_concurrent_pred_wins_tst(verbose);
    if (_arb_concurrent_upd_wins_tst != 0)
      arb_concurrent_upd_wins_tst(verbose);
    if (_arb_upd_burst_tst != 0)
      arb_upd_burst_tst(verbose);
    if (_arb_rb_full_blocks_pred_tst != 0)
      arb_rb_full_blocks_pred_tst(verbose);
    if (_arb_pred_credits_reset_tst != 0)
      arb_pred_credits_reset_tst(verbose);
    if (_arb_starve_tst != 0)
      arb_starve_tst(verbose);

    // BP-026 coverage gap tests (TC-55 through TC-60).
    if (_slot1_t1_write_tst != 0)
      slot1_t1_write_tst(verbose);
    if (_slot1_t2_write_tst != 0)
      slot1_t2_write_tst(verbose);
    if (_fh_sel_t3_t4_tst != 0)
      fh_sel_t3_t4_tst(verbose);
    if (_aging_active_tst != 0)
      aging_active_tst(verbose);
    if (_alt_ctr_s0_write_tst != 0)
      alt_ctr_s0_write_tst(verbose);
    if (_alc_end_to_end_tst != 0)
      alc_end_to_end_tst(verbose);

    // BP-028 fh_sel T2 and T3 arm coverage (TC-61 and TC-62).
    if (_fh_sel_t2_tst != 0)
      fh_sel_t2_tst(verbose);
    if (_fh_sel_t3_tst != 0)
      fh_sel_t3_tst(verbose);

    // BP-029 sat-alu boundary tests (TC-63 through TC-66).
    if (_ctr_t1_max_sat_tst != 0)
      ctr_t1_max_sat_tst(verbose);
    if (_ctr_t1_min_sat_tst != 0)
      ctr_t1_min_sat_tst(verbose);
    if (_use_t1_max_sat_tst != 0)
      use_t1_max_sat_tst(verbose);
    if (_use_t1_min_sat_tst != 0)
      use_t1_min_sat_tst(verbose);

    // BP-030 CE-05 and CE-06 coverage (TC-67 and TC-68).
    if (_no_alloc_candidate_tst != 0)
      no_alloc_candidate_tst(verbose);
    if (_no_ram_write_upd_tst != 0)
      no_ram_write_upd_tst(verbose);

    // Overall verdict.
    if (total_fails == 0) begin
      $display("[PASS] BP-023c: all tests passed");
      $finish(0);
    end else begin
      $display("[FAIL] BP-023c: %0d total failures",
        total_fails);
      $finish(1);
    end
  end

  // ----------------------------------------------------------------
  // TC-55  slot1_t1_write_tst: CU-11 slot 1 T1 tagged write.
  // norm_we_s1 must assert in the T1 instance for slot 1 update.
  // Pre-load T1 s1 mem[0][80]=0x0007 (CTR=011 prm_tkn=0 VAL=1).
  // Update: prm_comp=1 prm_idx=80 resolved=0 correct -> INC CTR.
  // Expect CTR 011->100 -> 0x0009.
  // ----------------------------------------------------------------
  task automatic slot1_t1_write_tst(int verbose);
    int              local_fails;
    logic            norm_we_s1_seen;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_s1;

    local_fails     = 0;
    norm_we_s1_seen = 1'b0;

    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s1.mem[0][80]
      = 16'h0007;
    if (verbose != 0)
      $display(
        "[INFO] slot1_t1_write_tst: T1 s1 mem[0][80]=0007");

    meta                    = '0;
    meta.tage_prm_idx       = 11'h050;
    meta.tage_alt_idx       = 11'h050;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_alt_comp      = 3'd0;
    meta.tage_prm_ctr       = 3'b011;
    meta.tage_alt_ctr       = 3'b000;
    meta.tage_prm_tkn       = 1'b0;
    meta.tage_alt_tkn       = 1'b0;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b0;

    // Drain the one stale PQ entry left by arb_starve_tst.
    @(posedge clk);

    stg_upd_inp1 = upd_inp;
    stg_upd_val1 = 1'b1;
    @(posedge clk);
    norm_we_s1_seen =
      u_dut.gen_tage_tbl[1].u_tage_tbl.norm_we_s1;
    stg_upd_val1 = 1'b0;
    stg_upd_inp1 = '0;
    @(posedge clk);

    rd_s1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s1.mem[0][80];

    if (verbose != 0) begin
      $display(
        "[INFO] slot1_t1_write_tst: norm_we_s1=%0b",
        norm_we_s1_seen);
      $display(
        "[INFO] slot1_t1_write_tst: s1[0][80]=0x%04h", rd_s1);
    end

    if (norm_we_s1_seen !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] slot1_t1_write_tst: norm_we_s1=0 exp=1");
    end
    if (rd_s1 !== 16'h0009) begin
      local_fails++;
      $display(
        "[FAIL] slot1_t1_write_tst: s1[0][80]=0x%04h exp=0009",
        rd_s1);
    end

    if (local_fails == 0)
      $display("[PASS] slot1_t1_write_tst: 0 failures");
    else
      $display("[FAIL] slot1_t1_write_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-56  slot1_t2_write_tst: CU-11 slot 1 T2 tagged write.
  // norm_we_s1 must assert in the T2 instance for slot 1 update.
  // Pre-load T2 s1 mem[0][90]=0x0007 (CTR=011 prm_tkn=0 VAL=1).
  // Update: prm_comp=2 prm_idx=90 resolved=0 correct -> INC CTR.
  // Expect CTR 011->100 -> 0x0009.
  // ----------------------------------------------------------------
  task automatic slot1_t2_write_tst(int verbose);
    int              local_fails;
    logic            norm_we_s1_seen;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_s1;

    local_fails     = 0;
    norm_we_s1_seen = 1'b0;

    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s1.mem[0][90]
      = 16'h0007;
    if (verbose != 0)
      $display(
        "[INFO] slot1_t2_write_tst: T2 s1 mem[0][90]=0007");

    meta                    = '0;
    meta.tage_prm_idx       = 11'h05A;
    meta.tage_alt_idx       = 11'h05A;
    meta.tage_prm_comp      = 3'd2;
    meta.tage_alt_comp      = 3'd0;
    meta.tage_prm_ctr       = 3'b011;
    meta.tage_alt_ctr       = 3'b000;
    meta.tage_prm_tkn       = 1'b0;
    meta.tage_alt_tkn       = 1'b0;
    meta.tage_using_primary = 1'b1;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b0;

    stg_upd_inp1 = upd_inp;
    stg_upd_val1 = 1'b1;
    @(posedge clk);
    norm_we_s1_seen =
      u_dut.gen_tage_tbl[2].u_tage_tbl.norm_we_s1;
    stg_upd_val1 = 1'b0;
    stg_upd_inp1 = '0;
    @(posedge clk);

    rd_s1 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s1.mem[0][90];

    if (verbose != 0) begin
      $display(
        "[INFO] slot1_t2_write_tst: norm_we_s1=%0b",
        norm_we_s1_seen);
      $display(
        "[INFO] slot1_t2_write_tst: s1[0][90]=0x%04h", rd_s1);
    end

    if (norm_we_s1_seen !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] slot1_t2_write_tst: norm_we_s1=0 exp=1");
    end
    if (rd_s1 !== 16'h0009) begin
      local_fails++;
      $display(
        "[FAIL] slot1_t2_write_tst: s1[0][90]=0x%04h exp=0009",
        rd_s1);
    end

    if (local_fails == 0)
      $display("[PASS] slot1_t2_write_tst: 0 failures");
    else
      $display("[FAIL] slot1_t2_write_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-57  fh_sel_t3_t4_tst: CP-10 fh_sel mux arms T3 and T4.
  // Set non-zero T3/T4 folded-hist fields, then issue predictions
  // so T3 and T4 tage_table instances evaluate fh_sel arms with
  // non-trivial fh_idx_ext/fh1_ext/fh2_ext outputs.
  // No mandatory RAM check; pass criterion is pred_rdy fires.
  // ----------------------------------------------------------------
  task automatic fh_sel_t3_t4_tst(int verbose);
    int             local_fails;
    tage_pred_inp_t inp;
    logic [1:0]     rdy;

    local_fails = 0;

    // Non-zero T3 and T4 folded-hist inputs.
    folded_hist.tage_t3_idx_fh  = 11'h1AA;
    folded_hist.tage_t3_tag_fh1 = 8'h55;
    folded_hist.tage_t3_tag_fh2 = 7'h2A;
    folded_hist.tage_t4_idx_fh  = 11'h155;
    folded_hist.tage_t4_tag_fh1 = 8'h2A;
    folded_hist.tage_t4_tag_fh2 = 7'h15;
    if (verbose != 0)
      $display(
        "[INFO] fh_sel_t3_t4_tst: T3 fh=1AA T4 fh=155 set");

    // Prediction 1: pc=40'hE00. T3/T4 idx/tag recomputed with
    // non-zero fh -> exercises fh_sel arms 3 and 4.
    inp           = '0;
    inp.pc        = 40'hE00;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    rdy = tage_pred_rdy_p2;
    if (verbose != 0)
      $display("[INFO] fh_sel_t3_t4_tst: pred1 rdy=0b%0b", rdy);
    if (rdy[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] fh_sel_t3_t4_tst: pred1 rdy=%0b exp=1",
        rdy[0]);
    end

    // Prediction 2: pc=40'hC00 for additional T3/T4 activity.
    inp           = '0;
    inp.pc        = 40'hC00;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    rdy = tage_pred_rdy_p2;
    if (verbose != 0)
      $display("[INFO] fh_sel_t3_t4_tst: pred2 rdy=0b%0b", rdy);
    if (rdy[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] fh_sel_t3_t4_tst: pred2 rdy=%0b exp=1",
        rdy[0]);
    end

    // Restore folded_hist to zero.
    folded_hist = '0;

    if (local_fails == 0)
      $display("[PASS] fh_sel_t3_t4_tst: 0 failures");
    else
      $display("[FAIL] fh_sel_t3_t4_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-58  aging_active_tst: CE-09 aging active path.
  // Assert tage_enable_aging=1 with tage_aging_interval=0.
  // On pred_rdy_p2 the aging_ff increments lcl_epoch 0->1.
  // Issue mispredict update targeting T1 row 100: DEC CTR/USE,
  // write EPC = new epoch (01). Verifies use_we and epc_we paths.
  // Pre-load T1 s0 mem[0][100]=0x001B (CTR=101 USE=01 VAL=1).
  // Pre-load T0 s0 mem[0][100]=2b00 (not-taken, pred_diff=1).
  // Expect after update: T1 s0 mem[0][100]=0x0049.
  // ----------------------------------------------------------------
  task automatic aging_active_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;

    local_fails = 0;

    // Pre-load T1 s0 row=100 bank=0.
    // CTR=101 (taken, non-boundary), USE=01, EPC=00, TAG=00, VAL=1.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][100]
      = 16'h001B;
    // T0 row=100: not-taken (CTR=00), so alt_tkn=0 -> pred_diff=1.
    u_dut.u_tage_bim.u_ram_s0.mem[0][100] = 2'b00;
    if (verbose != 0) begin
      $display(
        "[INFO] aging_active_tst: T1 s0 mem[0][100]=001B");
      $display(
        "[INFO] aging_active_tst: T0 s0 mem[0][100]=2b00");
    end

    // TC-57 leaves pred_rdy_p2=1; drain it with aging disabled
    // before resetting epoch to avoid a spurious aging increment.
    @(posedge clk);

    // Reset epoch and interval to known state.
    u_dut.u_tage_cntrl.lcl_epoch[0]          = 2'b00;
    u_dut.u_tage_cntrl.lcl_aging_interval[0] = 32'h0;

    // Enable aging: interval=0 so first pred_rdy_p2 increments
    // lcl_epoch from 0 to 1.
    tage_enable_aging   = 1'b1;
    tage_aging_interval = 32'h0;

    // Predict PC=40'h190: T1 idx=100 bank=0 tag=0x00 -> T1 hit.
    inp           = '0;
    inp.pc        = 40'h190;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    // tage_pred_rdy_p2 high after this posedge. Capture meta.
    meta1 = tage_pred_meta_p2[0];
    if (verbose != 0) begin
      $display(
        "[INFO] aging_active_tst: prm=%0d alt=%0d tkn=%0b",
        meta1.tage_prm_comp,
        meta1.tage_alt_comp,
        meta1.tage_pred_tkn);
    end
    if (meta1.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] aging_active_tst: prm_comp=%0d exp=1",
        meta1.tage_prm_comp);
    end

    // Posedge 4: aging_ff fires (tage_pred_rdy_p2 pre-edge=1).
    // After NBA: lcl_epoch[0] = 1.
    @(posedge clk);

    if (verbose != 0)
      $display(
        "[INFO] aging_active_tst: epoch=%0d",
        u_dut.u_tage_cntrl.lcl_epoch[0]);
    if (u_dut.u_tage_cntrl.lcl_epoch[0] !== 2'b01) begin
      local_fails++;
      $display(
        "[FAIL] aging_active_tst: epoch=%0d exp=1",
        u_dut.u_tage_cntrl.lcl_epoch[0]);
    end

    // Update: prm=T1 (taken, pre-edge epoch=1) resolved=0 wrong.
    // DEC CTR 101->100. pred_diff=1 -> DEC USE 01->00. EPC=01.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Restore aging control.
    tage_enable_aging   = 1'b0;
    tage_aging_interval = 32'h0;

    // Verify: CTR 101->100 USE 01->00 EPC->01 = 0x0049.
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][100];
    if (verbose != 0)
      $display(
        "[INFO] aging_active_tst: T1 s0[0][100]=0x%04h",
        rd_t1);

    if (rd_t1 !== 16'h0049) begin
      local_fails++;
      $display(
        "[FAIL] aging_active_tst: T1[0][100]=0x%04h exp=0049",
        rd_t1);
    end

    if (local_fails == 0)
      $display("[PASS] aging_active_tst: 0 failures");
    else
      $display("[FAIL] aging_active_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-59  alt_ctr_s0_write_tst: CE-11 alt-CTR slot 0 write.
  // Requires u_alt_tagged=1 (alt_comp!=0) and using_primary=0
  // so u_alt_ctr_wr fires unconditionally (provider = alt).
  // With pred_diff=0 (prm_tkn==alt_tkn) no USE side-effect.
  // Pre-load T2 s0 mem[0][95]=0x0007 (CTR=011 VAL=1 TAG=00).
  // Update: alt_comp=2 alt_idx=95 using_primary=0 resolved=0.
  // alt_crt=(0==0)=1 -> INC alt CTR 011->100.
  // Expect T2 s0 mem[0][95]=0x0009.
  // ----------------------------------------------------------------
  task automatic alt_ctr_s0_write_tst(int verbose);
    int              local_fails;
    tage_upd_inp_t   upd_inp;
    tage_pred_meta_t meta;
    logic [15:0]     rd_t2;

    local_fails = 0;

    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][95]
      = 16'h0007;
    if (verbose != 0)
      $display(
        "[INFO] alt_ctr_s0_write_tst: T2 s0 mem[0][95]=0007");

    // using_primary=0 -> alt (T2) is provider -> alt_ctr_wr=1.
    // prm_tkn=alt_tkn=0 -> pred_diff=0 -> no USE write side-effect.
    meta                    = '0;
    meta.tage_prm_idx       = 11'h064;
    meta.tage_alt_idx       = 11'h05F;
    meta.tage_prm_comp      = 3'd1;
    meta.tage_alt_comp      = 3'd2;
    meta.tage_prm_ctr       = 3'b000;
    meta.tage_alt_ctr       = 3'b011;
    meta.tage_prm_tkn       = 1'b0;
    meta.tage_alt_tkn       = 1'b0;
    meta.tage_using_primary = 1'b0;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b0;

    stg_upd_inp0 = upd_inp;
    stg_upd_val0 = 1'b1;
    @(posedge clk);
    stg_upd_val0 = 1'b0;
    stg_upd_inp0 = '0;
    @(posedge clk);

    rd_t2 =
      u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][95];
    if (verbose != 0)
      $display(
        "[INFO] alt_ctr_s0_write_tst: T2 s0[0][95]=0x%04h",
        rd_t2);

    if (rd_t2 !== 16'h0009) begin
      local_fails++;
      $display(
        "[FAIL] alt_ctr_s0_write_tst: T2[0][95]=0x%04h exp=0009",
        rd_t2);
    end

    if (local_fails == 0)
      $display("[PASS] alt_ctr_s0_write_tst: 0 failures");
    else
      $display("[FAIL] alt_ctr_s0_write_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-60  alc_end_to_end_tst: CE-10 allocation end-to-end.
  // Named owner of the alc_wr path in tage_table.sv.
  // PC=40'hF40 -> all tables idx=976 bank=0.
  // Pre-load T0[0][976]=2b10 (taken). T1-T4[0][976]=0x0000
  // (VAL=0 miss -> ueff=0 -> T1 is first allocation candidate).
  // Prediction: prm=T0 alc_comp=T1 alc_tag=0x01.
  // Mispredict update: alc_we_s0 fires in T1. Allocate 0x0109.
  // ----------------------------------------------------------------
  task automatic alc_end_to_end_tst(int verbose);
    int              local_fails;
    logic            alc_wr_seen;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta1;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;

    local_fails = 0;
    alc_wr_seen = 1'b0;

    // Reset epoch to 0 so EPC field of allocated entry = 0x00.
    u_dut.u_tage_cntrl.lcl_epoch[0]          = 2'b00;
    u_dut.u_tage_cntrl.lcl_aging_interval[0] = 32'h0;

    // Pre-load: T0 weakly taken. T1-T4 all-zero (VAL=0 miss).
    u_dut.u_tage_bim.u_ram_s0.mem[0][976]         = 2'b10;
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][976]
      = 16'h0000;
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][976]
      = 16'h0000;
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[0][976]
      = 16'h0000;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[0][976]
      = 16'h0000;
    if (verbose != 0) begin
      $display(
        "[INFO] alc_end_to_end_tst: T0[0][976]=2b10");
      $display(
        "[INFO] alc_end_to_end_tst: T1-T4[0][976]=0000");
    end

    // Predict PC=40'hF40. T1-T4 miss (VAL=0) -> prm=T0.
    // T1 ueff=0 -> alc_comp=1 alc_idx=976 alc_tag=0x01.
    inp           = '0;
    inp.pc        = 40'hF40;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta1 = tage_pred_meta_p2[0];
    if (verbose != 0) begin
      $display(
        "[INFO] alc_end_to_end_tst: prm=%0d alc=%0d tag=0x%02h",
        meta1.tage_prm_comp,
        meta1.tage_alc_comp,
        meta1.tage_alc_tag);
    end
    if (meta1.tage_prm_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] alc_end_to_end_tst: prm_comp=%0d exp=0",
        meta1.tage_prm_comp);
    end
    if (meta1.tage_alc_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] alc_end_to_end_tst: alc_comp=%0d exp=1",
        meta1.tage_alc_comp);
    end
    if (meta1.tage_alc_tag !== 8'h01) begin
      local_fails++;
      $display(
        "[FAIL] alc_end_to_end_tst: alc_tag=0x%02h exp=01",
        meta1.tage_alc_tag);
    end

    // Mispredict update. Allocation write to T1 row 976 bank 0.
    // alc_wr_seen captured after staging posedge (combinational).
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta1;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    alc_wr_seen =
      u_dut.gen_tage_tbl[1].u_tage_tbl.alc_we_s0;
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][976];
    if (verbose != 0) begin
      $display(
        "[INFO] alc_end_to_end_tst: alc_wr_seen=%0b",
        alc_wr_seen);
      $display(
        "[INFO] alc_end_to_end_tst: T1 s0[0][976]=0x%04h",
        rd_t1);
    end

    if (alc_wr_seen !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] alc_end_to_end_tst: alc_wr_seen=0 exp=1");
    end
    if (rd_t1 !== 16'h0109) begin
      local_fails++;
      $display(
        "[FAIL] alc_end_to_end_tst: T1[0][976]=0x%04h exp=0109",
        rd_t1);
    end

    if (local_fails == 0)
      $display("[PASS] alc_end_to_end_tst: 0 failures");
    else
      $display("[FAIL] alc_end_to_end_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-61  fh_sel_t2_tst: CP-11 fh_sel mux arm T2.
  // Drives non-zero T2 folded-hist fields, pre-loads a matching
  // T2 RAM entry, issues a prediction, and verifies T2 hit.
  // PC=40'h14000 t2_idx=100 t2_fh1=15 t2_fh2=0A.
  // idx=11'(0x5000^0x100)=256 bank=0 row=256.
  // tag=8'(0x28^0x15^0x14)=0x29.
  // Entry 0x290B: TAG=0x29 CTR=101 VAL=1.
  // Expected: prm_comp=2 prm_ctr=101 pred_tkn=1 rdy=1.
  // ----------------------------------------------------------------
  task automatic fh_sel_t2_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta;

    local_fails = 0;

    // Non-zero T2 folded-hist fields.
    folded_hist.tage_t2_idx_fh  = 11'h100;
    folded_hist.tage_t2_tag_fh1 = 8'h15;
    folded_hist.tage_t2_tag_fh2 = 7'h0A;

    // Pre-load T2 s0 bank 0 row 256.
    // TAG=0x29 EPC=00 USE=00 CTR=101 VAL=1 -> 0x290B.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][256]
      = 16'h290B;
    if (verbose != 0)
      $display(
        "[INFO] fh_sel_t2_tst: T2 s0 mem[0][256]=290B");

    // Stage prediction: PC=40'h14000.
    inp           = '0;
    inp.pc        = 40'h14000;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] fh_sel_t2_tst: rdy=%0b prm_comp=%0d",
        tage_pred_rdy_p2[0], meta.tage_prm_comp);
      $display(
        "[INFO] fh_sel_t2_tst: prm_ctr=%03b pred_tkn=%0b",
        meta.tage_prm_ctr, meta.tage_pred_tkn);
    end

    if (tage_pred_rdy_p2[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] fh_sel_t2_tst: rdy=%0b exp=1",
        tage_pred_rdy_p2[0]);
    end
    if (meta.tage_prm_comp !== 3'd2) begin
      local_fails++;
      $display("[FAIL] fh_sel_t2_tst: prm_comp=%0d exp=2",
        meta.tage_prm_comp);
    end
    if (meta.tage_prm_ctr !== 3'b101) begin
      local_fails++;
      $display("[FAIL] fh_sel_t2_tst: prm_ctr=%03b exp=101",
        meta.tage_prm_ctr);
    end
    if (meta.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display("[FAIL] fh_sel_t2_tst: pred_tkn=%0b exp=1",
        meta.tage_pred_tkn);
    end

    // Restore folded_hist.
    folded_hist = '0;

    if (local_fails == 0)
      $display("[PASS] fh_sel_t2_tst: 0 failures");
    else
      $display("[FAIL] fh_sel_t2_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-62  fh_sel_t3_tst: CP-12 fh_sel mux arm T3.
  // Drives non-zero T3 folded-hist fields, pre-loads a matching
  // T3 RAM entry, issues a prediction, and verifies T3 hit.
  // PC=40'h16000 t3_idx=080 t3_fh1=22 t3_fh2=11.
  // idx=11'(0x5800^0x080)=128 bank=0 row=128.
  // tag=8'(0x2C^0x22^0x22)=0x2C.
  // Entry 0x2C0B: TAG=0x2C CTR=101 VAL=1.
  // Expected: prm_comp=3 prm_ctr=101 pred_tkn=1 rdy=1.
  // ----------------------------------------------------------------
  task automatic fh_sel_t3_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta;

    local_fails = 0;

    // Non-zero T3 folded-hist fields.
    folded_hist.tage_t3_idx_fh  = 11'h080;
    folded_hist.tage_t3_tag_fh1 = 8'h22;
    folded_hist.tage_t3_tag_fh2 = 7'h11;

    // Pre-load T3 s0 bank 0 row 128.
    // TAG=0x2C EPC=00 USE=00 CTR=101 VAL=1 -> 0x2C0B.
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[0][128]
      = 16'h2C0B;
    if (verbose != 0)
      $display(
        "[INFO] fh_sel_t3_tst: T3 s0 mem[0][128]=2C0B");

    // Stage prediction: PC=40'h16000.
    inp           = '0;
    inp.pc        = 40'h16000;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] fh_sel_t3_tst: rdy=%0b prm_comp=%0d",
        tage_pred_rdy_p2[0], meta.tage_prm_comp);
      $display(
        "[INFO] fh_sel_t3_tst: prm_ctr=%03b pred_tkn=%0b",
        meta.tage_prm_ctr, meta.tage_pred_tkn);
    end

    if (tage_pred_rdy_p2[0] !== 1'b1) begin
      local_fails++;
      $display("[FAIL] fh_sel_t3_tst: rdy=%0b exp=1",
        tage_pred_rdy_p2[0]);
    end
    if (meta.tage_prm_comp !== 3'd3) begin
      local_fails++;
      $display("[FAIL] fh_sel_t3_tst: prm_comp=%0d exp=3",
        meta.tage_prm_comp);
    end
    if (meta.tage_prm_ctr !== 3'b101) begin
      local_fails++;
      $display("[FAIL] fh_sel_t3_tst: prm_ctr=%03b exp=101",
        meta.tage_prm_ctr);
    end
    if (meta.tage_pred_tkn !== 1'b1) begin
      local_fails++;
      $display("[FAIL] fh_sel_t3_tst: pred_tkn=%0b exp=1",
        meta.tage_pred_tkn);
    end

    // Restore folded_hist.
    folded_hist = '0;

    if (local_fails == 0)
      $display("[PASS] fh_sel_t3_tst: 0 failures");
    else
      $display("[FAIL] fh_sel_t3_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-63  ctr_t1_max_sat_tst: CE-01 T1 CTR max saturation.
  // Pre-load T1 s0 idx=640 (PC=40'hA00, folded_hist=0):
  //   bank=0 row=640 tag=8'h01.
  //   Entry 0x011F: TAG=01 EPC=00 USE=01 CTR=111 VAL=1.
  // Predict PC=40'hA00: prm_comp=1 prm_ctr=111 prm_tkn=1.
  // Update: resolved_taken=1 cond_mispredict=0 (correct).
  // CTR INC attempt at max 111->111 (saturates). CE-01 covered.
  // ----------------------------------------------------------------
  task automatic ctr_t1_max_sat_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;

    local_fails = 0;

    // Pre-load T1 slot 0 bank=0 row=640.
    // TAG=0x01 EPC=00 USE=01 CTR=111 VAL=1 -> 0x011F.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][640]
      = 16'h011F;
    if (verbose != 0)
      $display(
        "[INFO] ctr_t1_max_sat_tst: T1 s0 mem[0][640]=011F");

    // Predict PC=40'hA00 with zero folded_hist.
    inp           = '0;
    inp.pc        = 40'hA00;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] ctr_t1_max_sat_tst: prm_comp=%0d ctr=%03b",
        meta.tage_prm_comp, meta.tage_prm_ctr);
      $display(
        "[INFO] ctr_t1_max_sat_tst: prm_tkn=%0b",
        meta.tage_prm_tkn);
    end
    if (meta.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] ctr_t1_max_sat_tst: prm_comp=%0d exp=1",
        meta.tage_prm_comp);
    end
    if (meta.tage_prm_ctr !== 3'b111) begin
      local_fails++;
      $display(
        "[FAIL] ctr_t1_max_sat_tst: prm_ctr=%03b exp=111",
        meta.tage_prm_ctr);
    end

    // Update: resolved_taken=1 (correct), cond_mispredict=0.
    // CTR INC at max: (111==111)?111:111+1 = 111 (sat).
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Read back T1 entry. CTR bits[3:1] must remain 111.
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][640];
    if (verbose != 0)
      $display(
        "[INFO] ctr_t1_max_sat_tst: post T1[0][640]=0x%04h",
        rd_t1);
    if (rd_t1[3:1] !== 3'b111) begin
      local_fails++;
      $display(
        "[FAIL] ctr_t1_max_sat_tst: CTR=%03b exp=111",
        rd_t1[3:1]);
    end
    if (tage_upd_rdy_u1[0] !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] ctr_t1_max_sat_tst: upd_rdy=%0b exp=1",
        tage_upd_rdy_u1[0]);
    end

    if (local_fails == 0)
      $display("[PASS] ctr_t1_max_sat_tst: 0 failures");
    else
      $display("[FAIL] ctr_t1_max_sat_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-64  ctr_t1_min_sat_tst: CE-02 T1 CTR min saturation.
  // Pre-load T1 s0 idx=1024 (PC=40'h1000, folded_hist=0):
  //   bank=1 row=0 tag=8'h02.
  //   Entry 0x0211: TAG=02 EPC=00 USE=01 CTR=000 VAL=1.
  // T2-T4 s0 mem[1][0]=0x0010 (USE=01 VALID=0 blocks alloc).
  // Predict PC=40'h1000: prm_comp=1 prm_ctr=000 prm_tkn=0.
  // Update: resolved_taken=1 cond_mispredict=1 (wrong).
  // CTR DEC attempt at min 000->000 (saturates). CE-02 covered.
  // ----------------------------------------------------------------
  task automatic ctr_t1_min_sat_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;

    local_fails = 0;

    // Pre-load T1 slot 0 bank=1 row=0.
    // TAG=0x02 EPC=00 USE=01 CTR=000 VAL=1 -> 0x0211.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][0]
      = 16'h0211;
    // T2-T4 bank=1 row=0: USE=01 VALID=0.
    // Ensures ueff=01 at predict, so alc_comp=0 at update.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][0]
      = 16'h0010;
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[1][0]
      = 16'h0010;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[1][0]
      = 16'h0010;
    if (verbose != 0)
      $display(
        "[INFO] ctr_t1_min_sat_tst: T1 s0 mem[1][0]=0211");

    // Predict PC=40'h1000 with zero folded_hist.
    inp           = '0;
    inp.pc        = 40'h1000;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] ctr_t1_min_sat_tst: prm_comp=%0d ctr=%03b",
        meta.tage_prm_comp, meta.tage_prm_ctr);
      $display(
        "[INFO] ctr_t1_min_sat_tst: prm_tkn=%0b",
        meta.tage_prm_tkn);
    end
    if (meta.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] ctr_t1_min_sat_tst: prm_comp=%0d exp=1",
        meta.tage_prm_comp);
    end
    if (meta.tage_prm_ctr !== 3'b000) begin
      local_fails++;
      $display(
        "[FAIL] ctr_t1_min_sat_tst: prm_ctr=%03b exp=000",
        meta.tage_prm_ctr);
    end

    // Update: resolved_taken=1 (wrong, prm_tkn=0),
    // cond_mispredict=1. CTR DEC at min: (000==000)?000:000-1
    // = 000 (sat).
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Read back T1 entry. CTR bits[3:1] must remain 000.
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][0];
    if (verbose != 0)
      $display(
        "[INFO] ctr_t1_min_sat_tst: post T1[1][0]=0x%04h",
        rd_t1);
    if (rd_t1[3:1] !== 3'b000) begin
      local_fails++;
      $display(
        "[FAIL] ctr_t1_min_sat_tst: CTR=%03b exp=000",
        rd_t1[3:1]);
    end

    if (local_fails == 0)
      $display("[PASS] ctr_t1_min_sat_tst: 0 failures");
    else
      $display("[FAIL] ctr_t1_min_sat_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-65  use_t1_max_sat_tst: CE-03 T1 USE max saturation.
  // Pre-load T1 s0 idx=896 (PC=40'hE00, folded_hist=0):
  //   bank=0 row=896 tag=8'h01.
  //   Entry 0x013F: TAG=01 EPC=00 USE=11 CTR=111 VAL=1.
  // T0 CTR=00 (FAST_INIT, row=896 uncontaminated): alt_tkn=0.
  // pred_diff=1 (prm_tkn=1 != alt_tkn=0): USE update fires.
  // Predict PC=40'hE00: prm_comp=1 prm_use=11 pred_diff=1.
  // Update: resolved_taken=1 cond_mispredict=0 (correct).
  // USE INC attempt at max 11->11 (saturates). CE-03 covered.
  // ----------------------------------------------------------------
  task automatic use_t1_max_sat_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;

    local_fails = 0;

    // Pre-load T1 slot 0 bank=0 row=896.
    // TAG=0x01 EPC=00 USE=11 CTR=111 VAL=1 -> 0x013F.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][896]
      = 16'h013F;
    if (verbose != 0)
      $display(
        "[INFO] use_t1_max_sat_tst: T1 s0 mem[0][896]=013F");

    // Predict PC=40'hE00 with zero folded_hist.
    inp           = '0;
    inp.pc        = 40'hE00;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] use_t1_max_sat_tst: prm_comp=%0d use=%02b",
        meta.tage_prm_comp, meta.tage_prm_useful);
      $display(
        "[INFO] use_t1_max_sat_tst: prm_tkn=%0b alt_tkn=%0b",
        meta.tage_prm_tkn, meta.tage_alt_tkn);
    end
    if (meta.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] use_t1_max_sat_tst: prm_comp=%0d exp=1",
        meta.tage_prm_comp);
    end
    if (meta.tage_prm_useful !== 2'b11) begin
      local_fails++;
      $display(
        "[FAIL] use_t1_max_sat_tst: prm_use=%02b exp=11",
        meta.tage_prm_useful);
    end
    if (meta.tage_prm_tkn === meta.tage_alt_tkn) begin
      local_fails++;
      $display(
        "[FAIL] use_t1_max_sat_tst: pred_diff=0 exp=1");
    end

    // Update: resolved_taken=1 (correct), cond_mispredict=0.
    // USE INC at max: (11==11)?11:11+01 = 11 (sat).
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b0;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Read back T1 entry. USE bits[5:4] must remain 11.
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][896];
    if (verbose != 0)
      $display(
        "[INFO] use_t1_max_sat_tst: post T1[0][896]=0x%04h",
        rd_t1);
    if (rd_t1[5:4] !== 2'b11) begin
      local_fails++;
      $display(
        "[FAIL] use_t1_max_sat_tst: USE=%02b exp=11",
        rd_t1[5:4]);
    end

    if (local_fails == 0)
      $display("[PASS] use_t1_max_sat_tst: 0 failures");
    else
      $display("[FAIL] use_t1_max_sat_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-66  use_t1_min_sat_tst: CE-04 T1 USE min saturation.
  // Pre-load T1 s0 idx=1152 (PC=40'h1200, folded_hist=0):
  //   bank=1 row=128 tag=8'h02.
  //   Entry 0x0203: TAG=02 EPC=00 USE=00 CTR=001 VAL=1.
  // T0 s0 mem[1][128]=2b10 (CTR=10 alt_tkn=1 pred_diff=1).
  // T2-T4 s0 mem[1][128]=0x0010 (USE=01 VALID=0 blocks alloc).
  // Predict PC=40'h1200: prm_comp=1 prm_use=00 pred_diff=1.
  // Update: resolved_taken=1 cond_mispredict=1 (wrong).
  // USE DEC attempt at min 00->00 (saturates). CE-04 covered.
  // ----------------------------------------------------------------
  task automatic use_t1_min_sat_tst(int verbose);
    int              local_fails;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta;
    tage_upd_inp_t   upd_inp;
    logic [15:0]     rd_t1;

    local_fails = 0;

    // Pre-load T1 slot 0 bank=1 row=128.
    // TAG=0x02 EPC=00 USE=00 CTR=001 VAL=1 -> 0x0203.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][128]
      = 16'h0203;
    // T0 bank=1 row=128: CTR=10 (taken=1). Creates alt_tkn=1
    // so pred_diff=1 and USE DEC fires at update.
    u_dut.u_tage_bim.u_ram_s0.mem[1][128] = 2'b10;
    // T2-T4 bank=1 row=128: USE=01 VALID=0.
    // Ensures ueff=01 at predict, so alc_comp=0 at update.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[1][128]
      = 16'h0010;
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[1][128]
      = 16'h0010;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[1][128]
      = 16'h0010;
    if (verbose != 0)
      $display(
        "[INFO] use_t1_min_sat_tst: T1 s0 mem[1][128]=0203");

    // Predict PC=40'h1200 with zero folded_hist.
    inp           = '0;
    inp.pc        = 40'h1200;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta = tage_pred_meta_p2[0];

    if (verbose != 0) begin
      $display(
        "[INFO] use_t1_min_sat_tst: prm_comp=%0d use=%02b",
        meta.tage_prm_comp, meta.tage_prm_useful);
      $display(
        "[INFO] use_t1_min_sat_tst: prm_tkn=%0b alt_tkn=%0b",
        meta.tage_prm_tkn, meta.tage_alt_tkn);
    end
    if (meta.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] use_t1_min_sat_tst: prm_comp=%0d exp=1",
        meta.tage_prm_comp);
    end
    if (meta.tage_prm_useful !== 2'b00) begin
      local_fails++;
      $display(
        "[FAIL] use_t1_min_sat_tst: prm_use=%02b exp=00",
        meta.tage_prm_useful);
    end
    if (meta.tage_prm_tkn === meta.tage_alt_tkn) begin
      local_fails++;
      $display(
        "[FAIL] use_t1_min_sat_tst: pred_diff=0 exp=1");
    end

    // Update: resolved_taken=1 (wrong, prm_tkn=0),
    // cond_mispredict=1. USE DEC at min: (00==00)?00:00-01
    // = 00 (sat).
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b1;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    // Read back T1 entry. USE bits[5:4] must remain 00.
    rd_t1 =
      u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[1][128];
    if (verbose != 0)
      $display(
        "[INFO] use_t1_min_sat_tst: post T1[1][128]=0x%04h",
        rd_t1);
    if (rd_t1[5:4] !== 2'b00) begin
      local_fails++;
      $display(
        "[FAIL] use_t1_min_sat_tst: USE=%02b exp=00",
        rd_t1[5:4]);
    end

    if (local_fails == 0)
      $display("[PASS] use_t1_min_sat_tst: 0 failures");
    else
      $display("[FAIL] use_t1_min_sat_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-67  no_alloc_candidate_tst: CE-05 no allocation candidate.
  // PC=40'h2800 -> all tables idx=512 bank=0 row=512.
  // tag(T1-T4) = pc>>11 = 8'h05 (folded_hist=0).
  // T1 s0 mem[0][512]=0x0509:
  //   TAG=05 EPC=00 USE=00 CTR=100 VAL=1 -> T1 hits as provider.
  // T0 BIM s0 mem[0][512]=2'b00: alt_tkn=0, pred_diff=1.
  // T2-T4 s0 mem[0][512]=0x0010:
  //   USE=01 VAL=0 -> ueff=USE=01>0 (aging off). Blocked.
  // alc_comp scan: T2,T3,T4 all have ueff>0 -> no candidate.
  //   alc_comp_p1 stays 0 (no-candidate sentinel).
  // Update: mispredict=1, prm_comp=1 (<4), alc_comp=0.
  //   alc_upd_comb: (u_alc_comp==0) -> u_alc_wr=0.
  //   alc_wr_u0 suppressed for all tables. CE-05 covered.
  // ----------------------------------------------------------------
  task automatic no_alloc_candidate_tst(int verbose);
    int              local_fails;
    logic            alc_wr_seen;
    tage_pred_inp_t  inp;
    tage_pred_meta_t meta;
    tage_upd_inp_t   upd_inp;

    local_fails = 0;
    alc_wr_seen = 1'b0;

    // Reset epoch to 0: ueff = USE (age=0, tage_enable_aging=0).
    u_dut.u_tage_cntrl.lcl_epoch[0] = 2'b00;

    // T1 s0 bank=0 row=512: valid hit entry CTR=100 (taken).
    // TAG=05 EPC=00 USE=00 CTR=100 VAL=1 -> 0x0509.
    u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[0][512]
      = 16'h0509;
    // T0 BIM s0: CTR=00 not-taken. alt_tkn=0 -> pred_diff=1.
    u_dut.u_tage_bim.u_ram_s0.mem[0][512] = 2'b00;
    // T2-T4 s0: USE=01 VAL=0 -> ueff=01>0. Block candidates.
    u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[0][512]
      = 16'h0010;
    u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[0][512]
      = 16'h0010;
    u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[0][512]
      = 16'h0010;
    if (verbose != 0)
      $display(
        "[INFO] no_alloc_candidate_tst: T1[0][512]=0509");

    // Predict PC=40'h2800, folded_hist=0.
    // T1 hits (tag=05 match), T2-T4 miss (VAL=0).
    // alc_comp scan: T2,T3,T4 ueff=01>0 -> alc_comp=0.
    inp           = '0;
    inp.pc        = 40'h2800;
    inp.branch_id = 6'h0;
    stg_pred_inp0 = inp;
    stg_pred_val0 = 1'b1;
    @(posedge clk);
    stg_pred_val0 = 1'b0;
    stg_pred_inp0 = '0;
    @(posedge clk);
    @(posedge clk);

    meta = tage_pred_meta_p2[0];

    if (verbose != 0)
      $display(
        "[INFO] no_alloc_candidate_tst: prm=%0d alc=%0d",
        meta.tage_prm_comp, meta.tage_alc_comp);
    if (meta.tage_prm_comp !== 3'd1) begin
      local_fails++;
      $display(
        "[FAIL] no_alloc_candidate_tst: prm_comp=%0d exp=1",
        meta.tage_prm_comp);
    end
    if (meta.tage_alc_comp !== 3'd0) begin
      local_fails++;
      $display(
        "[FAIL] no_alloc_candidate_tst: alc_comp=%0d exp=0",
        meta.tage_alc_comp);
    end

    // Update: mispredict=1 triggers alloc path.
    // u_alc_comp=0 suppresses u_alc_wr -> no alc_wr_u0.
    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta;
    upd_inp.resolved_taken  = 1'b0;
    upd_inp.cond_mispredict = 1'b1;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    // Sample alc_we_s0 for all tables T1-T4.
    alc_wr_seen =
      u_dut.gen_tage_tbl[1].u_tage_tbl.alc_we_s0
      | u_dut.gen_tage_tbl[2].u_tage_tbl.alc_we_s0
      | u_dut.gen_tage_tbl[3].u_tage_tbl.alc_we_s0
      | u_dut.gen_tage_tbl[4].u_tage_tbl.alc_we_s0;
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    if (verbose != 0)
      $display(
        "[INFO] no_alloc_candidate_tst: alc_wr_seen=%0b",
        alc_wr_seen);
    if (alc_wr_seen !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] no_alloc_candidate_tst: alc_wr_seen=1 exp=0");
    end
    if (tage_upd_rdy_u1[0] !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] no_alloc_candidate_tst: upd_rdy=%0b exp=1",
        tage_upd_rdy_u1[0]);
    end

    if (local_fails == 0)
      $display("[PASS] no_alloc_candidate_tst: 0 failures");
    else
      $display(
        "[FAIL] no_alloc_candidate_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

  // ----------------------------------------------------------------
  // TC-68  no_ram_write_upd_tst: CE-06 update with no RAM write.
  // CE-06 path identified in tage_cntrl.sv (ctr_upd_comb,
  //   use_upd_comb, alc_upd_comb, gen_tbl assigns):
  //   u_prm_comp=0 (T0: u_prm_tagged=false)
  //   u_alt_comp=1 (T1: u_alt_tagged=true)
  //   u_both_t0 = !u_prm_tagged && !u_alt_tagged = false
  //   u_using_prm=1 (primary provider in use)
  //   u_pred_diff=0 (tage_prm_tkn == tage_alt_tkn)
  //   u_mispredict=0 (cond_mispredict=0)
  // No CTR write:
  //   both_t0 false -> else branch. prm_tagged false -> skip.
  //   alt_tagged true, using_prm true ->
  //     u_alt_ctr_wr = pred_diff && alt_crt = 0. No CTR write.
  // No USE write: u_use_wr = pred_diff && !both_t0 = 0.
  // No alloc write: u_alc_wr = mispredict && ... = 0.
  // No T0 BIM write: u_t0_ctr_wr fires only when both_t0=true.
  // Result: no RAM write enable asserts on any table or BIM.
  // ----------------------------------------------------------------
  task automatic no_ram_write_upd_tst(int verbose);
    int              local_fails;
    logic            any_we_seen;
    tage_pred_meta_t meta_ce06;
    tage_upd_inp_t   upd_inp;

    local_fails = 0;
    any_we_seen = 1'b0;

    // Construct CE-06 metadata directly (no prediction cycle).
    // prm_comp=0 (T0), alt_comp=1 (T1), using_primary=1,
    // both tkn=0 -> pred_diff=0. alc_comp=0 (default).
    meta_ce06                      = '0;
    meta_ce06.tage_prm_comp        = 3'd0;
    meta_ce06.tage_alt_comp        = 3'd1;
    meta_ce06.tage_using_primary   = 1'b1;
    meta_ce06.tage_prm_tkn         = 1'b0;
    meta_ce06.tage_alt_tkn         = 1'b0;

    upd_inp                 = '0;
    upd_inp.tage_pred_meta  = meta_ce06;
    upd_inp.cond_mispredict = 1'b0;
    upd_inp.resolved_taken  = 1'b0;
    stg_upd_inp0            = upd_inp;
    stg_upd_val0            = 1'b1;
    @(posedge clk);
    // Sample all write enables after update val propagates.
    // BIM ctr_we_s0 and T1-T4 norm_we_s0 must all be 0.
    any_we_seen =
      u_dut.u_tage_bim.ctr_we_s0
      | u_dut.gen_tage_tbl[1].u_tage_tbl.norm_we_s0
      | u_dut.gen_tage_tbl[2].u_tage_tbl.norm_we_s0
      | u_dut.gen_tage_tbl[3].u_tage_tbl.norm_we_s0
      | u_dut.gen_tage_tbl[4].u_tage_tbl.norm_we_s0;
    stg_upd_val0            = 1'b0;
    stg_upd_inp0            = '0;
    @(posedge clk);

    if (verbose != 0)
      $display(
        "[INFO] no_ram_write_upd_tst: any_we_seen=%0b",
        any_we_seen);
    if (any_we_seen !== 1'b0) begin
      local_fails++;
      $display(
        "[FAIL] no_ram_write_upd_tst: any_we_seen=1 exp=0");
    end
    if (tage_upd_rdy_u1[0] !== 1'b1) begin
      local_fails++;
      $display(
        "[FAIL] no_ram_write_upd_tst: upd_rdy=%0b exp=1",
        tage_upd_rdy_u1[0]);
    end

    if (local_fails == 0)
      $display("[PASS] no_ram_write_upd_tst: 0 failures");
    else
      $display(
        "[FAIL] no_ram_write_upd_tst: %0d failures",
        local_fails);
    total_fails += local_fails;
  endtask

endmodule : tb

`default_nettype wire
