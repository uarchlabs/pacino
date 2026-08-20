// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_sc.sv
// DATE:    2026-07-01
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking integration testbench for the SC structural top (sc).
// DUT instantiated directly as u_dut. NUM_PRED_SLOTS=2. This drives a
// full prediction through the REAL tables (ST0-ST3 sc_table, ST4
// sc_brimli) into sc_cntrl and back, drives an update, and exercises
// both init modes and the sc_ready gate.
//
// Table RAM contents are reached by hierarchical reference through the
// named bw_ram instances inside each table:
//   ST0-ST3: u_dut.gen_st[t].u_st.u_ram_s{0,1}.mem[bank][row]
//   ST4    : u_dut.u_st4.u_ram_s{0,1}.mem[bank][row]
// bank/row split (sc_table_interfaces.md): ST0-ST3 bank=idx[8],
// row=idx[7:0]; ST4 bank=idx[9], row=idx[8:0].
//
// Init modes (selected by +SC_FAST_INIT):
//   default (no plusarg): sram_init sequences all entries; sc_ready
//     follows. The gate test confirms no pred/upd accept before ready.
//   +SC_FAST_INIT=1: table initial blocks seed the RAMs at time zero;
//     sc_ready asserts immediately.
//
// TC1 init check   -- every entry, both banks, both slot RAMs, all
//                     five tables == SC_SRAM_INIT_VALUE after init.
// TC2 gate         -- (normal mode only) with sc_ready=0, a driven
//                     prediction and update are not accepted.
// TC3 prediction   -- derive each consulted index, seed a known
//                     counter, drive one prediction through the real
//                     tables, check sum / direction / override /
//                     captured index-counter meta at p3, both slots.
// TC4 update       -- drive one update, check sc_upd_rdy_u1 and that
//                     each addressed counter stepped (sat_sc) via
//                     mem[b][row], both slots.
// TC5 arb stubs    -- sc_uq_not_full / sc_upd_rdy safe constants.
// ===================================================================
`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  localparam int P_SLOTS = NUM_PRED_SLOTS;   // 2
  localparam int NT      = SC_NUM_TABLES;    // 5
  localparam int ST4     = SC_NUM_TABLES-1;  // 4

  // ----------------------------------------------------------------
  // Clock
  // ----------------------------------------------------------------
  logic clk;
  initial clk = 1'b0;
  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  // ----------------------------------------------------------------
  // DUT port signals
  // ----------------------------------------------------------------
  logic                        rstn;

  logic [P_SLOTS-1:0]          tage_pred_rdy_p2;
  tage_pred_meta_t             tage_pred_meta_p2[0:P_SLOTS-1];
  logic [VA_WIDTH-1:1]         inp_pc_p2[0:P_SLOTS-1];
  logic [9:0]                  sc_phr_p2;
  logic [SC_MAX_FH-1:0]        sc_t1_idx_fh_p2;
  logic [SC_MAX_FH-1:0]        sc_t2_idx_fh_p2;
  logic [SC_MAX_FH-1:0]        sc_t3_idx_fh_p2;

  logic [P_SLOTS-1:0]          sc_pred_rdy_p3;
  sc_pred_meta_t               sc_pred_meta_p3[0:P_SLOTS-1];

  logic [P_SLOTS-1:0]          sc_upd_val_u0;
  sc_upd_inp_t                 sc_upd_inp_u0[0:P_SLOTS-1];
  logic [P_SLOTS-1:0]          sc_upd_rdy_u1;

  logic                        sc_uq_not_full;
  logic [P_SLOTS-1:0]          sc_upd_rdy;

  logic                        sc_enable;
  logic                        sc_ready;

  // ----------------------------------------------------------------
  // DUT instantiation
  // ----------------------------------------------------------------
  sc #(
    .NUM_PRED_SLOTS(P_SLOTS)
  ) u_dut (
    .clk             (clk),
    .rstn            (rstn),
    .tage_pred_rdy_p2(tage_pred_rdy_p2),
    .tage_pred_meta_p2(tage_pred_meta_p2),
    .inp_pc_p2       (inp_pc_p2),
    .sc_phr_p2       (sc_phr_p2),
    .sc_t1_idx_fh_p2 (sc_t1_idx_fh_p2),
    .sc_t2_idx_fh_p2 (sc_t2_idx_fh_p2),
    .sc_t3_idx_fh_p2 (sc_t3_idx_fh_p2),
    .sc_pred_rdy_p3  (sc_pred_rdy_p3),
    .sc_pred_meta_p3 (sc_pred_meta_p3),
    .sc_upd_val_u0   (sc_upd_val_u0),
    .sc_upd_inp_u0   (sc_upd_inp_u0),
    .sc_upd_rdy_u1   (sc_upd_rdy_u1),
    .sc_uq_not_full  (sc_uq_not_full),
    .sc_upd_rdy      (sc_upd_rdy),
    .sc_enable       (sc_enable),
    .sc_ready        (sc_ready)
  );

  // ----------------------------------------------------------------
  // Pass / fail counters and per-test enables
  // ----------------------------------------------------------------
  int pass_cnt;
  int fail_cnt;

  int verbose      = 1;
  int _init_check  = 1;
  int _gate        = 1;
  int _prediction  = 1;
  int _update      = 1;
  int _arb_stub    = 1;

  // ----------------------------------------------------------------
  // Generic width-masked check (mirrors tb_sc_cntrl). 64-bit formals
  // so any DUT signal width flows through one helper.
  // ----------------------------------------------------------------
  /* verilator lint_off WIDTHEXPAND */
  task automatic chkw(input string nm, input int w,
                      input logic [63:0] got, input logic [63:0] exp);
    logic [63:0] m;
    m = (w >= 64) ? '1 : ((64'd1 << w) - 64'd1);
    if ((got & m) === (exp & m)) begin
      pass_cnt++;
      if (verbose != 0) $display("[PASS] %s", nm);
    end else begin
      fail_cnt++;
      $display("[FAIL] %s got=%0h exp=%0h", nm, got & m, exp & m);
    end
  endtask

  // ----------------------------------------------------------------
  // Reference saturating counter step (mirrors sc_cntrl sat_sc).
  // ----------------------------------------------------------------
  function automatic logic [SC_MAX_CTR_WIDTH-1:0] ref_sat_sc(
      input logic signed [SC_MAX_CTR_WIDTH-1:0] c, input int d);
    logic signed [SC_MAX_CTR_WIDTH-1:0] r;
    if (d == 0)                          r = c;
    else if ((c == SC_CTR_MIN) && d < 0) r = c;
    else if ((c == SC_CTR_MAX) && d > 0) r = c;
    else                                 r = c + SC_MAX_CTR_WIDTH'(d);
    return r;
  endfunction

  // ----------------------------------------------------------------
  // Reference index hashes. sc_idx_hash (ST0-ST3) and get_br_imli_idx
  // (ST4). Derived independently in the tb per the self-contained-test
  // rule; must match sc_table.sv / sc_brimli.sv exactly.
  // ----------------------------------------------------------------
  function automatic logic [SC_MAX_IDX_WIDTH-1:0] calc_sc_idx(
      input int                   t,
      input logic [VA_WIDTH-1:1]  pc,
      input logic [SC_MAX_FH-1:0] fh);
    logic [SC_MAX_FH-1:0] fh_ext;
    logic [SC_TBL_IDX[0]-1:0] idx9;   // ST0-ST3 are 9-bit
    fh_ext = (t == 0) ? '0 : fh;      // ST0 unhashed (SC_TBL_FH[0]=0)
    idx9   = SC_TBL_IDX[0]'(
               (SC_MAX_FH'(pc) >> PC_HASH_SHIFT) ^ fh_ext);
    calc_sc_idx = SC_MAX_IDX_WIDTH'(idx9);   // zero-extend to the bus
  endfunction

  function automatic logic [SC_MAX_IDX_WIDTH-1:0] calc_brimli_idx(
      input logic [VA_WIDTH-1:1] pc,
      input logic [9:0]          phr,
      input logic [9:0]          bri,
      input br_imli_mode_e       mode);
    logic [9:0] bpc, f_idx;
    bpc = pc[15:6];
    case (mode)
      IDX_IMLI_PHR:  f_idx = (bri == '0) ? phr : bri;
      IDX_PHR_ONLY:  f_idx = phr;
      IDX_IMLI_ONLY: f_idx = bri;
      default:       f_idx = (bri == '0) ? phr : bri;
    endcase
    calc_brimli_idx = SC_MAX_IDX_WIDTH'(bpc ^ f_idx ^ (bpc >> 4));
  endfunction

  // ----------------------------------------------------------------
  // Fold value routed to table t (matches sc_cntrl t_idx_fh_p2):
  //   ST0 -> 0, ST1 -> sc_t1, ST2 -> sc_t2, ST3 -> sc_t3.
  // ----------------------------------------------------------------
  function automatic logic [SC_MAX_FH-1:0] fold_for(input int t);
    case (t)
      1:       fold_for = sc_t1_idx_fh_p2;
      2:       fold_for = sc_t2_idx_fh_p2;
      3:       fold_for = sc_t3_idx_fh_p2;
      default: fold_for = '0;
    endcase
  endfunction

  // Derived consulted index for table t, slot s (br_imli held in
  // sc_cntrl; read it by hierarchical reference for ST4). The ST4 index
  // mode is now the sc SC_BR_IMLI_MODE parameter default (IDX_IMLI_PHR),
  // not a port; the reference passes that mode literal (BP-079).
  function automatic logic [SC_MAX_IDX_WIDTH-1:0] pred_idx(
      input int t, input int s);
    if (t == ST4)
      pred_idx = calc_brimli_idx(inp_pc_p2[s], sc_phr_p2,
                                 u_dut.u_sc_cntrl.br_imli, IDX_IMLI_PHR);
    else
      pred_idx = calc_sc_idx(t, inp_pc_p2[s], fold_for(t));
  endfunction

  // ----------------------------------------------------------------
  // Hierarchical table RAM read. bank/row per table geometry.
  // ----------------------------------------------------------------
  function automatic logic [SC_MAX_CTR_WIDTH-1:0] tbl_rd(
      input int t, input int s,
      input logic [SC_MAX_IDX_WIDTH-1:0] idx);
    logic b;
    int   row;
    logic [SC_MAX_CTR_WIDTH-1:0] v;
    if (t == ST4) begin b = idx[9]; row = int'(idx[8:0]); end
    else          begin b = idx[8]; row = int'(idx[7:0]); end
    v = '0;
    case (t)
      0: v = (s == 0) ? u_dut.gen_st[0].u_st.u_ram_s0.mem[b][row]
                      : u_dut.gen_st[0].u_st.u_ram_s1.mem[b][row];
      1: v = (s == 0) ? u_dut.gen_st[1].u_st.u_ram_s0.mem[b][row]
                      : u_dut.gen_st[1].u_st.u_ram_s1.mem[b][row];
      2: v = (s == 0) ? u_dut.gen_st[2].u_st.u_ram_s0.mem[b][row]
                      : u_dut.gen_st[2].u_st.u_ram_s1.mem[b][row];
      3: v = (s == 0) ? u_dut.gen_st[3].u_st.u_ram_s0.mem[b][row]
                      : u_dut.gen_st[3].u_st.u_ram_s1.mem[b][row];
      4: v = (s == 0) ? u_dut.u_st4.u_ram_s0.mem[b][row]
                      : u_dut.u_st4.u_ram_s1.mem[b][row];
    endcase
    tbl_rd = v;
  endfunction

  // Hierarchical table RAM seed (prediction setup only).
  task automatic tbl_seed(
      input int t, input int s,
      input logic [SC_MAX_IDX_WIDTH-1:0] idx,
      input logic [SC_MAX_CTR_WIDTH-1:0] data);
    logic b;
    int   row;
    if (t == ST4) begin b = idx[9]; row = int'(idx[8:0]); end
    else          begin b = idx[8]; row = int'(idx[7:0]); end
    case (t)
      0: if (s == 0) u_dut.gen_st[0].u_st.u_ram_s0.mem[b][row] = data;
         else        u_dut.gen_st[0].u_st.u_ram_s1.mem[b][row] = data;
      1: if (s == 0) u_dut.gen_st[1].u_st.u_ram_s0.mem[b][row] = data;
         else        u_dut.gen_st[1].u_st.u_ram_s1.mem[b][row] = data;
      2: if (s == 0) u_dut.gen_st[2].u_st.u_ram_s0.mem[b][row] = data;
         else        u_dut.gen_st[2].u_st.u_ram_s1.mem[b][row] = data;
      3: if (s == 0) u_dut.gen_st[3].u_st.u_ram_s0.mem[b][row] = data;
         else        u_dut.gen_st[3].u_st.u_ram_s1.mem[b][row] = data;
      4: if (s == 0) u_dut.u_st4.u_ram_s0.mem[b][row] = data;
         else        u_dut.u_st4.u_ram_s1.mem[b][row] = data;
    endcase
  endtask

  // ----------------------------------------------------------------
  // Clear all driven inputs
  // ----------------------------------------------------------------
  task automatic clr_inputs();
    tage_pred_rdy_p2 = '0;
    sc_upd_val_u0    = '0;
    for (int s = 0; s < P_SLOTS; s++) begin
      tage_pred_meta_p2[s] = '0;
      inp_pc_p2[s]         = '0;
      sc_upd_inp_u0[s]     = '0;
    end
    sc_phr_p2       = '0;
    sc_t1_idx_fh_p2 = '0;
    sc_t2_idx_fh_p2 = '0;
    sc_t3_idx_fh_p2 = '0;
    sc_enable       = 1'b1;
  endtask

  // ----------------------------------------------------------------
  // Wait for sc_ready (normal init). Bounded by the watchdog.
  // ----------------------------------------------------------------
  task automatic wait_ready();
    while (sc_ready !== 1'b1) begin
      @(posedge clk); #1;
    end
  endtask

  // ================================================================
  // TC1: init check. Every entry of every RAM holds the init value.
  // ================================================================
  task automatic test_init_check();
    int errs;
    int rows;
    logic [SC_MAX_IDX_WIDTH-1:0] idx;
    errs = 0;
    for (int t = 0; t < NT; t++) begin
      rows = (t == ST4) ? (SC_TBL_ENTRIES[ST4]/2)
                        : (SC_TBL_ENTRIES[0]/2);
      for (int s = 0; s < P_SLOTS; s++)
        for (int b = 0; b < 2; b++)
          for (int r = 0; r < rows; r++) begin
            idx = (t == ST4) ? SC_MAX_IDX_WIDTH'((b << 9) | r)
                             : SC_MAX_IDX_WIDTH'((b << 8) | r);
            if (tbl_rd(t, s, idx) !==
                SC_MAX_CTR_WIDTH'(SC_SRAM_INIT_VALUE))
              errs++;
          end
    end
    if (errs == 0) begin
      $display("[PASS] TC1: init check (all entries == %0d)",
               SC_SRAM_INIT_VALUE);
      pass_cnt++;
    end else begin
      $display("[FAIL] TC1: init check, %0d mismatched entries", errs);
      fail_cnt++;
    end
  endtask

  // ================================================================
  // TC2: sc_ready gate (normal init only). While sc_ready=0, a driven
  // prediction and update must not be accepted (sc_pred_rdy_p3=0,
  // sc_upd_rdy_u1=0).
  // ================================================================
  task automatic test_gate();
    // Precondition: sc_ready must still be low.
    chkw("TC2 ready low during seq", 1, sc_ready, 0);

    tage_pred_rdy_p2 = 2'b11;
    for (int s = 0; s < P_SLOTS; s++) begin
      tage_pred_meta_p2[s]              = '0;
      tage_pred_meta_p2[s].tage_pred_tkn = 1'b1;
      inp_pc_p2[s]                      = 39'h0000_0040;
    end
    sc_upd_val_u0 = 2'b11;
    for (int s = 0; s < P_SLOTS; s++) begin
      sc_upd_inp_u0[s]                = '0;
      sc_upd_inp_u0[s].resolved_taken = 1'b1;
    end
    @(posedge clk); #1;

    chkw("TC2 pred not accepted", P_SLOTS, sc_pred_rdy_p3, 0);
    chkw("TC2 upd  not accepted", P_SLOTS, sc_upd_rdy_u1, 0);

    tage_pred_rdy_p2 = '0;
    sc_upd_val_u0    = '0;
    for (int s = 0; s < P_SLOTS; s++) begin
      tage_pred_meta_p2[s] = '0;
      inp_pc_p2[s]         = '0;
      sc_upd_inp_u0[s]     = '0;
    end
    #1;
  endtask

  // ================================================================
  // TC3: full prediction through the real tables. Derive each
  // consulted index, seed a known counter (+3) at that index in the
  // per-slot RAM, drive one prediction at p2, and check the SC result
  // at p3 for both slots.
  //
  // With all five counters = +3 and tage_extd_ctr = 0:
  //   sc_sum = sum(2*3+1) = 35, abs = 35, lcl_tkn = 1.
  // threshold = SC_THRSH_MID (10) -> not vlo/vvlo (35 >= 5).
  //   slot 0: tage_tkn = 1  -> agree: final=1, override=0.
  //   slot 1: tage_tkn = 0  -> general differ: final=1, override=1.
  // ================================================================
  task automatic test_prediction();
    logic [SC_MAX_IDX_WIDTH-1:0] idx[0:NT-1][0:P_SLOTS-1];
    int exp_sum;

    // Confirm the sc_cntrl threshold and br_imli seeds the test relies
    // on (self-contained-test rule: verify, do not assume).
    chkw("TC3 pre threshold=MID", SC_THRSH_BITS,
         u_dut.u_sc_cntrl.threshold, SC_THRSH_MID);
    chkw("TC3 pre br_imli=0", 10, u_dut.u_sc_cntrl.br_imli, 0);

    // Prediction stimulus (distinct PCs per slot).
    clr_inputs();
    inp_pc_p2[0]    = 39'h0000_0044;   // pc>>2 = 0x11
    inp_pc_p2[1]    = 39'h0000_0088;   // pc>>2 = 0x22
    sc_t1_idx_fh_p2 = 64'd5;
    sc_t2_idx_fh_p2 = 64'd10;
    sc_t3_idx_fh_p2 = 64'd3;
    sc_phr_p2       = 10'h055;

    // Derive indices and seed +3 at each consulted entry.
    for (int t = 0; t < NT; t++)
      for (int s = 0; s < P_SLOTS; s++) begin
        idx[t][s] = pred_idx(t, s);
        tbl_seed(t, s, idx[t][s], 6'sd3);
      end

    // Present the prediction meta at p2.
    tage_pred_rdy_p2 = 2'b11;
    // slot 0: agree (tage_tkn = 1)
    tage_pred_meta_p2[0]                  = '0;
    tage_pred_meta_p2[0].tage_extd_ctr    = '0;
    tage_pred_meta_p2[0].tage_pred_strong = 1'b1;
    tage_pred_meta_p2[0].tage_pred_medium = 1'b0;
    tage_pred_meta_p2[0].tage_pred_tkn    = 1'b1;
    tage_pred_meta_p2[0].branch_id        = 6'd9;
    // slot 1: differ (tage_tkn = 0)
    tage_pred_meta_p2[1]                  = '0;
    tage_pred_meta_p2[1].tage_extd_ctr    = '0;
    tage_pred_meta_p2[1].tage_pred_strong = 1'b0;
    tage_pred_meta_p2[1].tage_pred_medium = 1'b0;
    tage_pred_meta_p2[1].tage_pred_tkn    = 1'b0;
    tage_pred_meta_p2[1].branch_id        = 6'd21;

    // p2 -> p3: clock once; the SC result forms combinationally at p3.
    @(posedge clk); #1;

    exp_sum = 5*(2*3+1);   // 35

    // -- slot 0 (agree)
    chkw("TC3 s0 rdy",      1, sc_pred_rdy_p3[0], 1);
    chkw("TC3 s0 sum",      SC_LSUM_BITS,
         sc_pred_meta_p3[0].sc_sum, exp_sum);
    chkw("TC3 s0 abs_sum",  SC_LSUM_BITS,
         sc_pred_meta_p3[0].sc_abs_sum, exp_sum);
    chkw("TC3 s0 lcl_tkn",  1, sc_pred_meta_p3[0].sc_lcl_pred_tkn, 1);
    chkw("TC3 s0 final",    1, sc_pred_meta_p3[0].sc_pred_tkn, 1);
    chkw("TC3 s0 override", 1, sc_pred_meta_p3[0].sc_override, 0);
    chkw("TC3 s0 chooser",  2,
         sc_pred_meta_p3[0].sc_chooser, CHOOSE_NONE);
    chkw("TC3 s0 branch_id", FTQ_IDX_BITS,
         sc_pred_meta_p3[0].branch_id, 9);

    // -- slot 1 (general differ -> override)
    chkw("TC3 s1 rdy",      1, sc_pred_rdy_p3[1], 1);
    chkw("TC3 s1 sum",      SC_LSUM_BITS,
         sc_pred_meta_p3[1].sc_sum, exp_sum);
    chkw("TC3 s1 lcl_tkn",  1, sc_pred_meta_p3[1].sc_lcl_pred_tkn, 1);
    chkw("TC3 s1 final",    1, sc_pred_meta_p3[1].sc_pred_tkn, 1);
    chkw("TC3 s1 override", 1, sc_pred_meta_p3[1].sc_override, 1);
    chkw("TC3 s1 chooser",  2,
         sc_pred_meta_p3[1].sc_chooser, CHOOSE_NONE);

    // -- captured per-table index / counter meta (both slots)
    for (int t = 0; t < NT; t++)
      for (int s = 0; s < P_SLOTS; s++) begin
        chkw($sformatf("TC3 s%0d cap idx[%0d]", s, t),
             SC_MAX_IDX_WIDTH,
             sc_pred_meta_p3[s].sc_upd_idx[t], idx[t][s]);
        chkw($sformatf("TC3 s%0d cap ctr[%0d]", s, t),
             SC_MAX_CTR_WIDTH,
             sc_pred_meta_p3[s].sc_upd_ctr[t], 6'sd3);
      end

    // Deassert and confirm sc_pred_rdy_p3 drops.
    tage_pred_rdy_p2 = '0;
    @(posedge clk); #1;
    chkw("TC3 rdy drops", P_SLOTS, sc_pred_rdy_p3, 0);
  endtask

  // ================================================================
  // TC4: update. Drive one update on both slots. Force do_update via
  // sc_wrong (sc_lcl_pred_tkn != resolved_taken). slot 0 resolves
  // taken (+1 step), slot 1 resolves not-taken (-1 step). Check
  // sc_upd_rdy_u1 and every addressed counter via mem[b][row].
  // ================================================================
  task automatic test_update();
    logic [SC_MAX_IDX_WIDTH-1:0] uidx[0:NT-1][0:P_SLOTS-1];
    logic signed [SC_MAX_CTR_WIDTH-1:0] uctr[0:NT-1][0:P_SLOTS-1];
    logic ures[0:P_SLOTS-1];
    logic [SC_MAX_CTR_WIDTH-1:0] exp;
    int   d;

    // slot 0: resolved taken -> +1; slot 1: resolved not-taken -> -1.
    ures[0] = 1'b1;
    ures[1] = 1'b0;

    // Per-table indices (distinct, covering both banks) and counters
    // (covering saturation at SC_CTR_MAX / SC_CTR_MIN).
    // slot 0
    uidx[0][0] = 10'h011; uctr[0][0] =  6'sd3;   // -> +4
    uidx[1][0] = 10'h114; uctr[1][0] =  6'sd31;  // sat -> +31
    uidx[2][0] = 10'h01B; uctr[2][0] = -6'sd5;   // -> -4
    uidx[3][0] = 10'h112; uctr[3][0] =  6'sd0;   // -> +1
    uidx[4][0] = 10'h254; uctr[4][0] = -6'sd32;  // -> -31 (ST4 bank1)
    // slot 1
    uidx[0][1] = 10'h022; uctr[0][1] = -6'sd3;   // -> -4
    uidx[1][1] = 10'h027; uctr[1][1] = -6'sd32;  // sat -> -32
    uidx[2][1] = 10'h128; uctr[2][1] =  6'sd5;   // -> +4
    uidx[3][1] = 10'h021; uctr[3][1] =  6'sd0;   // -> -1
    uidx[4][1] = 10'h157; uctr[4][1] =  6'sd31;  // -> +30 (ST4 bank0)

    // Land just after an edge with the request deasserted.
    clr_inputs();
    @(posedge clk); #1;

    // Build both slot update bundles. sc_wrong forced on each slot.
    sc_upd_val_u0 = 2'b11;
    for (int s = 0; s < P_SLOTS; s++) begin
      sc_upd_inp_u0[s]                                = '0;
      sc_upd_inp_u0[s].sc_pred_meta.sc_lcl_pred_tkn   = ~ures[s];
      sc_upd_inp_u0[s].resolved_taken                 = ures[s];
      sc_upd_inp_u0[s].sc_pred_meta.sc_abs_sum        = 10'd50;
      sc_upd_inp_u0[s].sc_pred_meta.sc_chooser        = CHOOSE_NONE;
      sc_upd_inp_u0[s].backwards_branch               = 1'b0;
      sc_upd_inp_u0[s].branch_range                   = '0;
      for (int t = 0; t < NT; t++) begin
        sc_upd_inp_u0[s].sc_pred_meta.sc_upd_idx[t] = uidx[t][s];
        sc_upd_inp_u0[s].sc_pred_meta.sc_upd_ctr[t] =
          SC_MAX_DATA_WIDTH'(uctr[t][s]);
      end
    end
    #1;

    // One posedge commits the RAM writes and loads sc_upd_rdy_u1.
    @(posedge clk); #1;
    chkw("TC4 upd_rdy_u1", P_SLOTS, sc_upd_rdy_u1, 2'b11);

    // Deassert the request before any further edge (single write).
    sc_upd_val_u0 = '0;
    #1;

    // Read back each addressed counter.
    for (int t = 0; t < NT; t++)
      for (int s = 0; s < P_SLOTS; s++) begin
        d   = ures[s] ? +1 : -1;
        exp = ref_sat_sc(uctr[t][s], d);
        chkw($sformatf("TC4 s%0d ctr[%0d] stepped", s, t),
             SC_MAX_CTR_WIDTH, tbl_rd(t, s, uidx[t][s]), exp);
      end
  endtask

  // ================================================================
  // TC5: arbitration stubs are safe constants.
  // ================================================================
  task automatic test_arb_stub();
    chkw("TC5 sc_uq_not_full", 1, sc_uq_not_full, 1);
    chkw("TC5 sc_upd_rdy",     P_SLOTS, sc_upd_rdy, 2'b11);
  endtask

  // ----------------------------------------------------------------
  // Main sequence
  // ----------------------------------------------------------------
  int fast_init;
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    clr_inputs();
    rstn = 1'b0;
    repeat (3) @(posedge clk);
    @(posedge clk); #1; rstn = 1'b1;
    @(posedge clk); #1;

    fast_init = 0;
    void'($value$plusargs("SC_FAST_INIT=%d", fast_init));
    if (fast_init != 0)
      $display("[info] SC_FAST_INIT=1 (fast init, sc_ready immediate)");
    else
      $display("[info] SC_FAST_INIT=0 (sram_init sequences)");

    if (fast_init != 0) begin
      // Fast init: sc_ready asserts immediately.
      chkw("INIT fast sc_ready immediate", 1, sc_ready, 1);
    end else begin
      // Normal init: sc_ready low while sram_init sequences. Prove the
      // gate first, then wait for ready.
      if (_gate != 0) test_gate();
      wait_ready();
      chkw("INIT normal sc_ready after seq", 1, sc_ready, 1);
    end

    if (_init_check != 0) test_init_check();
    if (_prediction != 0) test_prediction();
    if (_update     != 0) test_update();
    if (_arb_stub   != 0) test_arb_stub();

    @(posedge clk); #1;
    $display("--------------------------------------------");
    $display("Results: %0d PASS  %0d FAIL", pass_cnt, fail_cnt);
    if (fail_cnt != 0)
      $fatal(1, "TESTBENCH FAILED");
    else
      $display("TESTBENCH PASSED");
    $finish;
  end

  // ----------------------------------------------------------------
  // Timeout watchdog. Bounds the normal-init wait (~1024 cycles).
  // ----------------------------------------------------------------
  initial begin : watchdog
    #200000;
    $display("[TIMEOUT] simulation exceeded time limit");
    $fatal(1, "Timeout");
  end

  /* verilator lint_on WIDTHEXPAND */

endmodule : tb

`default_nettype wire
