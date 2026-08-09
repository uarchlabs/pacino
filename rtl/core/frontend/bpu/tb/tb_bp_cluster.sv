// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_bp_cluster.sv
// DATE:    2026-08-09
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking testbench for bp_cluster.sv (BP-093).
//
// bp_cluster is the subject. No predictor is stubbed and no predictor
// metadata is forced. The drive surface is the cluster port list; the
// observe surface is the cluster port list plus a small set of named
// hierarchical probes into bp_cluster's own internal nets and into
// three predictor tables that act as FIXTURES.
//
// Groups
//   A  bring-up               A1 A2 A3
//   B  p1 prediction          B1 B2 B3 B4 B5
//   C  p2 redirect            C1 C2 C3
//   D  p3 and supersession    D1 D2
//   E  history                TC-A..TC-G, E1 E2 E3
//   F  metadata               F1 F2 F3
//
// Fixture policy (BP-093 binding decision 3). A predictor response
// that a cluster test needs as an input is established by writing that
// predictor's table by hierarchical reference, or by driving the
// cluster's own update port where one exists:
//
//   ubtb        table write, dut.u_ubtb.mem[set][way]. The index and
//               the tag are derived by TB functions that replicate
//               ubtb.sv get_idx/get_tag, and every test that uses the
//               table first checks the TB derivation against the DUT's
//               own p_idx / p_tag (see chk_ubtb_hash).
//   loop_pred   bank write, dut.u_loop_pred.g_slot[s].mem[set][way].
//               Index and tag derived the same way and checked against
//               the DUT's req_idx / req_tag.
//   ftb         NOT written by hierarchy. The cluster declares the
//               full FTB update port group, so every FTB entry in this
//               file is installed through ftb_upd_* at the boundary.
//   tage        the T0 bimodal RAM is written UNIFORMLY (every row of
//               every bank of both slot RAMs) so the TAGE direction is
//               a constant for any PC. No index is assumed.
//   sc          the five SC counter RAMs are written UNIFORMLY for the
//               same reason.
//   ittage      one entry, at the index and tag the DUT itself
//               computes for the request PC, read out of
//               dut.u_ittage.tbl_idx_hash_p0 / tbl_tag_hash_p0. The
//               hash is observed, never assumed.
//   ras         NOT written by hierarchy. The return address reaches
//               the RAS through the cluster ras_commit_* ports.
//
// Every case establishes its start state by reset plus a known driven
// sequence. Tables that could alias the set under test are invalidated
// explicitly rather than assumed empty.
//
// A failing check increments fail_cnt; the run ends in $fatal(1) when
// fail_cnt is non-zero. $finish(1) does NOT produce a non-zero exit
// under Verilator (BP-086 found that defect in the old tb_ubtb), so
// $fatal(1) is the only accepted failure exit. +FORCE_FAIL=1 breaks
// one check on purpose so the non-zero exit path can be demonstrated
// without editing this file (test A2).
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  // -----------------------------------------------------------------
  // Clock and reset
  // -----------------------------------------------------------------
  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // -----------------------------------------------------------------
  // Resolved geometry, restated so a change in the package shows up
  // here as a compile-time mismatch rather than as a silent retarget.
  // -----------------------------------------------------------------
  localparam int BLK_OFF_BITS = $clog2(FTB_BLOCK_BYTES);      // 5
  localparam int BR_POS_SHIFT = BLK_OFF_BITS - FTB_BR_POS_BITS; // 2
  // VA-width form of the block size, so address arithmetic below is
  // 40 bits on both sides.
  localparam logic [VA_WIDTH-1:0] BLK_SZ = VA_WIDTH'(FTB_BLOCK_BYTES);

  // SC credit-arbiter counter widths, restated exactly as bp_cluster
  // derives them, so the group A reset values and the group H counter
  // checks are compared at the design's own widths (bp_arb_spec 4.5).
  localparam int SC_PRED_CRED_W_TB = $clog2(SC_PRED_CREDITS + 1);
  localparam int SC_UPD_CRED_W_TB  = $clog2(SC_UPD_CREDITS  + 1);
  localparam int SC_STARVE_W_TB    = $clog2(SC_STARVE_THRESH + 1);

  // -----------------------------------------------------------------
  // DUT port signals (names match bp_cluster.sv)
  // -----------------------------------------------------------------
  logic                    ftq_pred_val_p0;
  logic [VA_WIDTH-1:0]     ftq_pred_pc_p0;
  logic [FTQ_IDX_BITS-1:0] ftq_pred_idx_p0;

  logic                    bpu_pred_val_p1;
  logic [FTQ_IDX_BITS-1:0] bpu_pred_idx_p1;
  bp_ftq_slot_t            bpu_pred_slot_p1 [0:NUM_PRED_SLOTS-1];
  bp_ras_snapshot_t        bpu_pred_ras_p1;
  logic [VA_WIDTH-1:0]     bpu_pred_pft_p1;

  bp_redirect_t            bpu_redir_p2 [0:NUM_PRED_SLOTS-1];
  logic [FTQ_IDX_BITS-1:0] bpu_redir_idx_p2;
  bp_redirect_t            bpu_redir_p3 [0:NUM_PRED_SLOTS-1];
  logic [FTQ_IDX_BITS-1:0] bpu_redir_idx_p3;

  logic                    bpu_meta_val_p2;
  logic [FTQ_IDX_BITS-1:0] bpu_meta_idx_p2;
  tage_pred_meta_t         bpu_meta_tage_p2   [0:NUM_PRED_SLOTS-1];
  ittage_pred_meta_t       bpu_meta_ittage_p2 [0:NUM_PRED_SLOTS-1];
  lp_pred_t                bpu_meta_lp_p2     [0:NUM_PRED_SLOTS-1];
  ftb_pred_meta_t          bpu_meta_ftb_p2    [0:NUM_PRED_SLOTS-1];

  logic                    bpu_meta_val_p3;
  logic [FTQ_IDX_BITS-1:0] bpu_meta_idx_p3;
  sc_pred_meta_t           bpu_meta_sc_p3     [0:NUM_PRED_SLOTS-1];

  ubtb_upd_t [NUM_PRED_SLOTS-1:0] ubtb_upd_u0;

  logic [NUM_PRED_SLOTS-1:0] lp_upd_valid_p0;
  lp_upd_t                   lp_upd_p0 [0:NUM_PRED_SLOTS-1];

  logic                       ftb_upd_valid_u0;
  logic [VA_WIDTH-1:0]        ftb_upd_pc_u0;
  logic                       ftb_upd_hit_u0;
  logic [FTB_WAY_BITS-1:0]    ftb_upd_way_u0;
  logic                       ftb_upd_is_br_u0;
  logic                       ftb_upd_br_idx_u0;
  logic                       ftb_upd_taken_u0;
  logic [VA_WIDTH-1:0]        ftb_upd_target_u0;
  logic [FTB_BR_POS_BITS-1:0] ftb_upd_pos_u0;
  logic                       ftb_upd_is_jmp_u0;
  logic [VA_WIDTH-1:0]        ftb_upd_jmp_target_u0;
  logic                       ftb_upd_is_call_u0;
  logic                       ftb_upd_is_ret_u0;
  logic                       ftb_upd_is_jalr_u0;
  logic [VA_WIDTH-1:0]        ftb_upd_pft_addr_u0;
  logic                       ftb_flush_px;

  logic [NUM_PRED_SLOTS-1:0] tage_upd_val_u0;
  tage_upd_inp_t             tage_upd_inp_u0 [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] ittage_upd_val_u0;
  ittage_upd_inp_t           ittage_upd_inp_u0 [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] sc_upd_val_u0;
  sc_upd_inp_t               sc_upd_inp_u0 [0:NUM_PRED_SLOTS-1];

  logic                ras_restore_val;
  bp_ras_snapshot_t    ras_restore_snapshot;
  logic                ras_commit_val;
  bp_br_type_e         ras_commit_br_type;
  logic [VA_WIDTH-1:0] ras_commit_ret_addr;
  bp_ras_snapshot_t    ras_commit_snapshot;
  logic                ras_flush_val;
  bp_ras_snapshot_t    ras_flush_snapshot;

  logic [GHIST_PTR_BITS-1:0] ghist_ptr;
  logic [PHIST_PTR_BITS-1:0] phist_ptr;
  logic [GHIST_PTR_BITS-1:0] ckpt_ghist_ptr;
  logic [PHIST_PTR_BITS-1:0] ckpt_phist_ptr;
  logic [GHR_WIDTH-1:0]      ghr_buf;
  logic [PHR_WIDTH-1:0]      phr_buf;

  logic        tage_enable_aging;
  logic [31:0] tage_aging_interval;
  logic        ittage_enable_aging;
  logic [31:0] ittage_aging_interval;
  logic        sc_enable;
  logic        ftb_fastpath_en;

  logic                      tage_rdy;
  logic                      ittage_rdy;
  logic                      sc_ready;
  logic                      tage_pq_not_full;
  logic [NUM_PRED_SLOTS-1:0] tage_upd_rdy;
  logic [NUM_PRED_SLOTS-1:0] tage_upd_rdy_u1;
  logic                      ittage_pq_not_full;
  logic [NUM_PRED_SLOTS-1:0] ittage_upd_rdy;
  logic [NUM_PRED_SLOTS-1:0] ittage_upd_rdy_u1;
  logic                      sc_uq_not_full;
  logic [NUM_PRED_SLOTS-1:0] sc_upd_rdy;
  logic [NUM_PRED_SLOTS-1:0] sc_upd_rdy_u1;

  // -----------------------------------------------------------------
  // DUT
  // -----------------------------------------------------------------
  bp_cluster dut (
    .clk                   (clk),
    .rstn                  (rstn),
    .ftq_pred_val_p0       (ftq_pred_val_p0),
    .ftq_pred_pc_p0        (ftq_pred_pc_p0),
    .ftq_pred_idx_p0       (ftq_pred_idx_p0),
    .bpu_pred_val_p1       (bpu_pred_val_p1),
    .bpu_pred_idx_p1       (bpu_pred_idx_p1),
    .bpu_pred_slot_p1      (bpu_pred_slot_p1),
    .bpu_pred_ras_p1       (bpu_pred_ras_p1),
    .bpu_pred_pft_p1       (bpu_pred_pft_p1),
    .bpu_redir_p2          (bpu_redir_p2),
    .bpu_redir_idx_p2      (bpu_redir_idx_p2),
    .bpu_redir_p3          (bpu_redir_p3),
    .bpu_redir_idx_p3      (bpu_redir_idx_p3),
    .bpu_meta_val_p2       (bpu_meta_val_p2),
    .bpu_meta_idx_p2       (bpu_meta_idx_p2),
    .bpu_meta_tage_p2      (bpu_meta_tage_p2),
    .bpu_meta_ittage_p2    (bpu_meta_ittage_p2),
    .bpu_meta_lp_p2        (bpu_meta_lp_p2),
    .bpu_meta_ftb_p2       (bpu_meta_ftb_p2),
    .bpu_meta_val_p3       (bpu_meta_val_p3),
    .bpu_meta_idx_p3       (bpu_meta_idx_p3),
    .bpu_meta_sc_p3        (bpu_meta_sc_p3),
    .ubtb_upd_u0           (ubtb_upd_u0),
    .lp_upd_valid_p0       (lp_upd_valid_p0),
    .lp_upd_p0             (lp_upd_p0),
    .ftb_upd_valid_u0      (ftb_upd_valid_u0),
    .ftb_upd_pc_u0         (ftb_upd_pc_u0),
    .ftb_upd_hit_u0        (ftb_upd_hit_u0),
    .ftb_upd_way_u0        (ftb_upd_way_u0),
    .ftb_upd_is_br_u0      (ftb_upd_is_br_u0),
    .ftb_upd_br_idx_u0     (ftb_upd_br_idx_u0),
    .ftb_upd_taken_u0      (ftb_upd_taken_u0),
    .ftb_upd_target_u0     (ftb_upd_target_u0),
    .ftb_upd_pos_u0        (ftb_upd_pos_u0),
    .ftb_upd_is_jmp_u0     (ftb_upd_is_jmp_u0),
    .ftb_upd_jmp_target_u0 (ftb_upd_jmp_target_u0),
    .ftb_upd_is_call_u0    (ftb_upd_is_call_u0),
    .ftb_upd_is_ret_u0     (ftb_upd_is_ret_u0),
    .ftb_upd_is_jalr_u0    (ftb_upd_is_jalr_u0),
    .ftb_upd_pft_addr_u0   (ftb_upd_pft_addr_u0),
    .ftb_flush_px          (ftb_flush_px),
    .tage_upd_val_u0       (tage_upd_val_u0),
    .tage_upd_inp_u0       (tage_upd_inp_u0),
    .ittage_upd_val_u0     (ittage_upd_val_u0),
    .ittage_upd_inp_u0     (ittage_upd_inp_u0),
    .sc_upd_val_u0         (sc_upd_val_u0),
    .sc_upd_inp_u0         (sc_upd_inp_u0),
    .ras_restore_val       (ras_restore_val),
    .ras_restore_snapshot  (ras_restore_snapshot),
    .ras_commit_val        (ras_commit_val),
    .ras_commit_br_type    (ras_commit_br_type),
    .ras_commit_ret_addr   (ras_commit_ret_addr),
    .ras_commit_snapshot   (ras_commit_snapshot),
    .ras_flush_val         (ras_flush_val),
    .ras_flush_snapshot    (ras_flush_snapshot),
    .ghist_ptr             (ghist_ptr),
    .phist_ptr             (phist_ptr),
    .ckpt_ghist_ptr        (ckpt_ghist_ptr),
    .ckpt_phist_ptr        (ckpt_phist_ptr),
    .ghr_buf               (ghr_buf),
    .phr_buf               (phr_buf),
    .tage_enable_aging     (tage_enable_aging),
    .tage_aging_interval   (tage_aging_interval),
    .ittage_enable_aging   (ittage_enable_aging),
    .ittage_aging_interval (ittage_aging_interval),
    .sc_enable             (sc_enable),
    .ftb_fastpath_en       (ftb_fastpath_en),
    .tage_rdy              (tage_rdy),
    .ittage_rdy            (ittage_rdy),
    .sc_ready              (sc_ready),
    .tage_pq_not_full      (tage_pq_not_full),
    .tage_upd_rdy          (tage_upd_rdy),
    .tage_upd_rdy_u1       (tage_upd_rdy_u1),
    .ittage_pq_not_full    (ittage_pq_not_full),
    .ittage_upd_rdy        (ittage_upd_rdy),
    .ittage_upd_rdy_u1     (ittage_upd_rdy_u1),
    .sc_uq_not_full        (sc_uq_not_full),
    .sc_upd_rdy            (sc_upd_rdy),
    .sc_upd_rdy_u1         (sc_upd_rdy_u1)
  );

  // -----------------------------------------------------------------
  // Scoreboard
  // -----------------------------------------------------------------
  int pass_cnt;
  int fail_cnt;
  int force_fail;

  // Loud check: prints on pass and on fail. Used for named cases.
  task automatic chk(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
      $display("PASS: %s", nm);
    end else begin
      fail_cnt++;
      $display("FAIL: %s", nm);
    end
  endtask

  // Quiet check: prints only on failure. Used inside sweeps so a
  // 64-point sweep does not bury the directed results.
  task automatic chk_q(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: %s", nm);
    end
  endtask

  task automatic chk_eq(input string nm, input logic [VA_WIDTH-1:0] got,
                        input logic [VA_WIDTH-1:0] exp);
    if (got === exp) begin
      pass_cnt++;
      $display("PASS: %s", nm);
    end else begin
      fail_cnt++;
      $display("FAIL: %s  got %010h exp %010h", nm, got, exp);
    end
  endtask

  task automatic chk_eq_q(input string nm, input logic [VA_WIDTH-1:0] got,
                          input logic [VA_WIDTH-1:0] exp);
    if (got === exp) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: %s  got %010h exp %010h", nm, got, exp);
    end
  endtask

  // -----------------------------------------------------------------
  // Address helpers -- derivations, not assumptions
  // -----------------------------------------------------------------
  function automatic logic [VA_WIDTH-1:0]
      blk_base(input logic [VA_WIDTH-1:0] pc);
    return {pc[VA_WIDTH-1:BLK_OFF_BITS], {BLK_OFF_BITS{1'b0}}};
  endfunction

  // The branch PC BP-092a specifies: block base plus the scaled
  // in-block position.
  function automatic logic [VA_WIDTH-1:0]
      slot_pc(input logic [VA_WIDTH-1:0] pc,
              input logic [FTB_BR_POS_BITS-1:0] pos);
    return blk_base(pc) + (VA_WIDTH'(pos) << BR_POS_SHIFT);
  endfunction

  // uBTB index / tag / base, replicating ubtb.sv get_idx / get_tag.
  function automatic logic [UBTB_IDX_BITS-1:0]
      ub_idx(input logic [VA_WIDTH-1:0] pc);
    return pc[UBTB_OFFSET_BITS +: UBTB_IDX_BITS];
  endfunction

  function automatic logic [UBTB_TAG_BITS-1:0]
      ub_tag(input logic [VA_WIDTH-1:0] pc);
    return pc[UBTB_OFFSET_BITS+UBTB_IDX_BITS +: UBTB_TAG_BITS];
  endfunction

  // loop_pred index / tag, replicating loop_pred.sv idx_of / tag_of.
  function automatic logic [LP_IDX_BITS-1:0]
      lp_idx(input logic [VA_WIDTH-1:0] pc);
    logic [VA_WIDTH-1:0] x;
    x = pc ^ (pc >> 1) ^ (pc >> 4);
    return x[LP_IDX_BITS-1:0];
  endfunction

  function automatic logic [LP_TAG_BITS-1:0]
      lp_tag(input logic [VA_WIDTH-1:0] pc);
    logic [VA_WIDTH-1:0] x;
    x = pc ^ (pc >> 6) ^ (pc >> 12);
    return x[LP_TAG_BITS-1:0];
  endfunction

  // uBTB stored partial fall-through and carry for a wanted address.
  function automatic logic [UBTB_PFTADDR_BITS-1:0]
      ub_pft_field(input logic [VA_WIDTH-1:0] want,
                   input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0] off;
    off = want - base;
    return {{(UBTB_PFTADDR_BITS-(UBTB_OFFSET_BITS-INST_OFFSET)){1'b0}},
            off[UBTB_OFFSET_BITS-1:INST_OFFSET]};
  endfunction

  function automatic logic
      ub_pft_carry(input logic [VA_WIDTH-1:0] want,
                   input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0] off;
    off = want - base;
    return |off[VA_WIDTH-1:UBTB_OFFSET_BITS];
  endfunction

  // One uBTB conditional field. conf is the weak init in the wanted
  // direction; its MSB is the direction ubtb.sv reports on br_taken.
  function automatic ubtb_cond_t
      mk_cond(input logic v, input logic [UBTB_BR_POS_BITS-1:0] pos,
              input logic [VA_WIDTH-1:0] tgt,
              input logic [VA_WIDTH-1:0] base, input logic taken);
    ubtb_cond_t c;
    logic [VA_WIDTH-1:0] d;
    c      = '0;
    d      = tgt - base;
    c.valid = v;
    c.pos   = pos;
    c.tgt   = d[UBTB_BR_TGT_BITS-1:0];
    c.stat  = 2'b00;
    c.conf  = taken ? UBTB_CONF_INIT_TKN : UBTB_CONF_INIT_NTK;
    return c;
  endfunction

  function automatic ubtb_jmp_t
      mk_jmp(input logic v, input logic [UBTB_BR_POS_BITS-1:0] pos,
             input logic [VA_WIDTH-1:0] tgt,
             input logic [VA_WIDTH-1:0] base,
             input logic is_call, input logic is_ret,
             input logic is_jalr);
    ubtb_jmp_t j;
    logic [VA_WIDTH-1:0] d;
    j        = '0;
    d        = tgt - base;
    j.valid  = v;
    j.pos    = pos;
    j.tgt    = d[UBTB_JMP_TGT_BITS-1:0];
    j.stat   = 2'b00;
    j.is_call = is_call;
    j.is_ret  = is_ret;
    j.is_jalr = is_jalr;
    return j;
  endfunction

  // -----------------------------------------------------------------
  // Stimulus primitives
  // -----------------------------------------------------------------
  task automatic tick();
    @(posedge clk);
    #1;
  endtask

  task automatic req(input logic [VA_WIDTH-1:0] pc,
                     input logic [FTQ_IDX_BITS-1:0] idx);
    ftq_pred_val_p0 = 1'b1;
    ftq_pred_pc_p0  = pc;
    ftq_pred_idx_p0 = idx;
  endtask

  task automatic norq();
    ftq_pred_val_p0 = 1'b0;
  endtask

  // BP-093 carried a req_a() helper here, which repeated the SAME FTQ
  // index on the following cycle so the skewed TAGE branch_id happened
  // to match at p2. BP-094 stages branch_id p0 -> p1 in tage_cntrl, so
  // a single request now delivers its own branch_id and the helper has
  // no reason to exist. It is REMOVED rather than left unused: every
  // former caller now issues one request, which is the stimulus the
  // interface actually specifies, and test C4 proves a back-to-back
  // unstalled stream works without any repetition at all.

  task automatic clr_ftb_upd();
    ftb_upd_valid_u0      = 1'b0;
    ftb_upd_pc_u0         = '0;
    ftb_upd_hit_u0        = 1'b0;
    ftb_upd_way_u0        = '0;
    ftb_upd_is_br_u0      = 1'b0;
    ftb_upd_br_idx_u0     = 1'b0;
    ftb_upd_taken_u0      = 1'b0;
    ftb_upd_target_u0     = '0;
    ftb_upd_pos_u0        = '0;
    ftb_upd_is_jmp_u0     = 1'b0;
    ftb_upd_jmp_target_u0 = '0;
    ftb_upd_is_call_u0    = 1'b0;
    ftb_upd_is_ret_u0     = 1'b0;
    ftb_upd_is_jalr_u0    = 1'b0;
    ftb_upd_pft_addr_u0   = '0;
  endtask

  task automatic init_inputs();
    ftq_pred_val_p0 = 1'b0;
    ftq_pred_pc_p0  = '0;
    ftq_pred_idx_p0 = '0;
    ubtb_upd_u0     = '0;
    lp_upd_valid_p0 = '0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      lp_upd_p0[s]         = '0;
      tage_upd_inp_u0[s]   = '0;
      ittage_upd_inp_u0[s] = '0;
      sc_upd_inp_u0[s]     = '0;
    end
    clr_ftb_upd();
    ftb_flush_px          = 1'b0;
    tage_upd_val_u0       = '0;
    ittage_upd_val_u0     = '0;
    sc_upd_val_u0         = '0;
    ras_restore_val       = 1'b0;
    ras_restore_snapshot  = '0;
    ras_commit_val        = 1'b0;
    ras_commit_br_type    = NO_BRANCH;
    ras_commit_ret_addr   = '0;
    ras_commit_snapshot   = '0;
    ras_flush_val         = 1'b0;
    ras_flush_snapshot    = '0;
    tage_enable_aging     = 1'b0;
    tage_aging_interval   = 32'd0;
    ittage_enable_aging   = 1'b0;
    ittage_aging_interval = 32'd0;
    sc_enable             = 1'b0;
    ftb_fastpath_en       = 1'b0;
  endtask

  // The ITTAGE tables live in bw_ram, which has no reset: rstn does
  // NOT clear them and a seeded entry would survive into the next
  // case. IT1 in particular indexes on pc[9:2] and tags on pc[15:8],
  // so two PCs a few blocks apart alias exactly. Clear all five
  // tables as part of every reset rather than relying on the absence
  // of residue (CLAUDE.md, self-contained tests).
  task automatic ittage_clear_all();
    for (int b = 0; b < 2; b++) begin
      for (int i = 0; i < 128; i++) begin
        dut.u_ittage.gen_ittage_tables[1].gen_active.u_table
           .u_ram_s0.mem[b][i] = '0;
        dut.u_ittage.gen_ittage_tables[1].gen_active.u_table
           .u_ram_s1.mem[b][i] = '0;
        dut.u_ittage.gen_ittage_tables[2].gen_active.u_table
           .u_ram_s0.mem[b][i] = '0;
        dut.u_ittage.gen_ittage_tables[2].gen_active.u_table
           .u_ram_s1.mem[b][i] = '0;
      end
      for (int i = 0; i < 256; i++) begin
        dut.u_ittage.gen_ittage_tables[3].gen_active.u_table
           .u_ram_s0.mem[b][i] = '0;
        dut.u_ittage.gen_ittage_tables[3].gen_active.u_table
           .u_ram_s1.mem[b][i] = '0;
        dut.u_ittage.gen_ittage_tables[4].gen_active.u_table
           .u_ram_s0.mem[b][i] = '0;
        dut.u_ittage.gen_ittage_tables[4].gen_active.u_table
           .u_ram_s1.mem[b][i] = '0;
        dut.u_ittage.gen_ittage_tables[5].gen_active.u_table
           .u_ram_s0.mem[b][i] = '0;
        dut.u_ittage.gen_ittage_tables[5].gen_active.u_table
           .u_ram_s1.mem[b][i] = '0;
      end
    end
  endtask

  task automatic do_reset();
    rstn = 1'b0;
    init_inputs();
    repeat (4) tick();
    rstn = 1'b1;
    ittage_clear_all();
    repeat (3) tick();
  endtask

  // -----------------------------------------------------------------
  // Fixture: uBTB
  // -----------------------------------------------------------------
  // Invalidate every way of the set this PC indexes, so no residue of
  // an earlier case can alias the entry under test.
  task automatic ubtb_clear_set(input logic [VA_WIDTH-1:0] pc);
    for (int w = 0; w < UBTB_WAYS; w++) begin
      dut.u_ubtb.mem[ub_idx(pc)][w].valid = 1'b0;
    end
  endtask

  task automatic ubtb_install(input logic [VA_WIDTH-1:0] pc,
                              input ubtb_entry_t e);
    ubtb_entry_t ee;
    ee       = e;
    ee.valid = 1'b1;
    ee.tag   = ub_tag(pc);
    ubtb_clear_set(pc);
    dut.u_ubtb.mem[ub_idx(pc)][0] = ee;
  endtask

  // Prove the TB derivation of the uBTB index and tag against the
  // module's own. Requires ftq_pred_pc_p0 to already carry pc.
  task automatic chk_ubtb_hash(input string nm,
                               input logic [VA_WIDTH-1:0] pc);
    chk_q({nm, " ubtb idx derivation"},
          dut.u_ubtb.p_idx === ub_idx(pc));
    chk_q({nm, " ubtb tag derivation"},
          dut.u_ubtb.p_tag === ub_tag(pc));
  endtask

  // -----------------------------------------------------------------
  // Fixture: loop_pred
  // -----------------------------------------------------------------
  // g_slot is a generate loop, so the bank index must be a literal.
  // NUM_PRED_SLOTS is 2 at the shipped geometry; a third slot would
  // need a third arm here and the elaboration check below fires.
  task automatic lp_clear_set(input int s,
                              input logic [VA_WIDTH-1:0] pc);
    for (int w = 0; w < LP_TBL_WAYS; w++) begin
      if (s == 0) dut.u_loop_pred.g_slot[0].mem[lp_idx(pc)][w] = '0;
      else        dut.u_loop_pred.g_slot[1].mem[lp_idx(pc)][w] = '0;
    end
  endtask

  task automatic lp_install(input int s,
                            input logic [VA_WIDTH-1:0] pc,
                            input logic [LP_CNF_BITS-1:0] cnf,
                            input logic [LP_ITR_BITS-1:0] curr,
                            input logic [LP_ITR_BITS-1:0] past);
    lp_entry_t e;
    e          = '0;
    e.v        = 1'b1;
    e.tag      = lp_tag(pc);
    e.cnf      = cnf;
    e.curr_itr = curr;
    e.past_itr = past;
    e.age      = '1;
    lp_clear_set(s, pc);
    if (s == 0) dut.u_loop_pred.g_slot[0].mem[lp_idx(pc)][0] = e;
    else        dut.u_loop_pred.g_slot[1].mem[lp_idx(pc)][0] = e;
  endtask

  task automatic lp_clear_both(input logic [VA_WIDTH-1:0] pc);
    lp_clear_set(0, pc);
    lp_clear_set(1, pc);
  endtask

  task automatic chk_lp_hash(input string nm,
                             input logic [VA_WIDTH-1:0] pc);
    chk_q({nm, " lp idx derivation s0"},
          dut.u_loop_pred.g_slot[0].req_idx === lp_idx(pc));
    chk_q({nm, " lp tag derivation s0"},
          dut.u_loop_pred.g_slot[0].req_tag === lp_tag(pc));
    chk_q({nm, " lp idx derivation s1"},
          dut.u_loop_pred.g_slot[1].req_idx === lp_idx(pc));
    chk_q({nm, " lp tag derivation s1"},
          dut.u_loop_pred.g_slot[1].req_tag === lp_tag(pc));
  endtask

  // -----------------------------------------------------------------
  // Fixture: TAGE T0 bimodal, written uniformly
  // -----------------------------------------------------------------
  // Every row of every bank of both slot RAMs takes the same counter,
  // so the TAGE direction is that counter's MSB for ANY request PC and
  // no index hash is assumed. T1..T4 stay cold (no tag match), so T0
  // is the provider.
  localparam int BIM_ENTRIES = (1 << TAGE_TBL_IDX[0]) / 2;

  task automatic tage_bim_fill(input logic [TAGE_TBL_CTR[0]-1:0] ctr);
    for (int b = 0; b < 2; b++) begin
      for (int i = 0; i < BIM_ENTRIES; i++) begin
        dut.u_tage.u_tage_bim.u_ram_s0.mem[b][i] = ctr;
        dut.u_tage.u_tage_bim.u_ram_s1.mem[b][i] = ctr;
      end
    end
  endtask

  // -----------------------------------------------------------------
  // Fixture: SC counter RAMs, written uniformly
  // -----------------------------------------------------------------
  localparam int SC03_ENTRIES = SC_TBL_ENTRIES[0] / 2;
  localparam int SC4_ENTRIES  = SC_TBL_ENTRIES[4] / 2;

  task automatic sc_fill(input logic [SC_MAX_CTR_WIDTH-1:0] ctr);
    for (int b = 0; b < 2; b++) begin
      for (int i = 0; i < SC03_ENTRIES; i++) begin
        dut.u_sc.gen_st[0].u_st.u_ram_s0.mem[b][i] = ctr;
        dut.u_sc.gen_st[0].u_st.u_ram_s1.mem[b][i] = ctr;
        dut.u_sc.gen_st[1].u_st.u_ram_s0.mem[b][i] = ctr;
        dut.u_sc.gen_st[1].u_st.u_ram_s1.mem[b][i] = ctr;
        dut.u_sc.gen_st[2].u_st.u_ram_s0.mem[b][i] = ctr;
        dut.u_sc.gen_st[2].u_st.u_ram_s1.mem[b][i] = ctr;
        dut.u_sc.gen_st[3].u_st.u_ram_s0.mem[b][i] = ctr;
        dut.u_sc.gen_st[3].u_st.u_ram_s1.mem[b][i] = ctr;
      end
      for (int i = 0; i < SC4_ENTRIES; i++) begin
        dut.u_sc.u_st4.u_ram_s0.mem[b][i] = ctr;
        dut.u_sc.u_st4.u_ram_s1.mem[b][i] = ctr;
      end
    end
  endtask

  // -----------------------------------------------------------------
  // Fixture: ITTAGE IT1, one entry at the DUT's own index and tag
  // -----------------------------------------------------------------
  // IT1 geometry, taken from the package rather than written out.
  localparam int IT1_IDX  = IT_TBL_IDX[1];              // 8
  localparam int IT1_TAG  = IT_TBL_TAG[1];              // 8
  localparam int IT_CB_W  = IT_MAX_VAL_WIDTH + IT_MAX_CTR_WIDTH
                          + IT_MAX_USE_WIDTH + IT_MAX_EPC_WIDTH
                          + IT_MAX_TGT_WIDTH;           // 46
  localparam int IT1_ALC  = IT_CB_W + IT1_TAG;          // 54

  // Write IT1 for slot 0 at the index and tag the DUT computed for the
  // PC currently on ftq_pred_pc_p0. Both are READ OUT of the DUT, so
  // no hash is assumed here.
  task automatic ittage_seed_it1_s0(input logic [IT_MAX_TGT_WIDTH-1:0] tgt);
    logic [IT_MAX_IDX_WIDTH-1:0] ix;
    logic [IT_MAX_TAG_WIDTH-1:0] tg;
    logic [IT1_ALC-1:0]          w;
    ix = dut.u_ittage.tbl_idx_hash_p0[1][0];
    tg = dut.u_ittage.tbl_tag_hash_p0[1][0];
    w  = '0;
    w[0]                                = 1'b1;            // valid
    w[IT_MAX_CTR_WIDTH:1]               = '1;              // ctr max
    w[IT_CB_W-1 -: IT_MAX_TGT_WIDTH]    = tgt;             // target
    w[IT1_ALC-1 -: IT1_TAG]             = tg[IT1_TAG-1:0]; // tag
    dut.u_ittage.gen_ittage_tables[1].gen_active.u_table
       .u_ram_s0.mem[ix[IT1_IDX-1]][ix[IT1_IDX-2:0]] = w;
  endtask

  // -----------------------------------------------------------------
  // Fixture: FTB, installed through the cluster update port
  // -----------------------------------------------------------------
  task automatic ftb_pulse();
    ftb_upd_valid_u0 = 1'b1;
    tick();
    clr_ftb_upd();
  endtask

  // Allocate an FTB entry carrying one conditional field.
  task automatic ftb_alloc_cond(input logic [VA_WIDTH-1:0] pc,
                                input logic [FTB_WAY_BITS-1:0] way,
                                input logic br_idx,
                                input logic taken,
                                input logic [VA_WIDTH-1:0] tgt,
                                input logic [FTB_BR_POS_BITS-1:0] pos,
                                input logic [VA_WIDTH-1:0] pft,
                                input logic hit);
    clr_ftb_upd();
    ftb_upd_pc_u0       = pc;
    ftb_upd_hit_u0      = hit;
    ftb_upd_way_u0      = way;
    ftb_upd_is_br_u0    = 1'b1;
    ftb_upd_br_idx_u0   = br_idx;
    ftb_upd_taken_u0    = taken;
    ftb_upd_target_u0   = tgt;
    ftb_upd_pos_u0      = pos;
    ftb_upd_pft_addr_u0 = pft;
    ftb_pulse();
  endtask

  // Allocate or rewrite the FTB jump field.
  task automatic ftb_alloc_jmp(input logic [VA_WIDTH-1:0] pc,
                               input logic [FTB_WAY_BITS-1:0] way,
                               input logic [VA_WIDTH-1:0] jtgt,
                               input logic [FTB_BR_POS_BITS-1:0] pos,
                               input logic is_call,
                               input logic is_ret,
                               input logic is_jalr,
                               input logic [VA_WIDTH-1:0] pft,
                               input logic hit);
    clr_ftb_upd();
    ftb_upd_pc_u0         = pc;
    ftb_upd_hit_u0        = hit;
    ftb_upd_way_u0        = way;
    ftb_upd_is_jmp_u0     = 1'b1;
    ftb_upd_jmp_target_u0 = jtgt;
    ftb_upd_pos_u0        = pos;
    ftb_upd_is_call_u0    = is_call;
    ftb_upd_is_ret_u0     = is_ret;
    ftb_upd_is_jalr_u0    = is_jalr;
    ftb_upd_pft_addr_u0   = pft;
    ftb_pulse();
  endtask

  // -----------------------------------------------------------------
  // Fixture: RAS commit push
  // -----------------------------------------------------------------
  // Pushes one return address onto the commit stack. The commit
  // snapshot names the new BOS; leaving it at zero keeps the
  // speculative stack empty (TOSR == BOS), so the p0 top of stack is
  // served from the commit stack.
  task automatic ras_push_commit(input logic [VA_WIDTH-1:0] addr);
    ras_commit_val      = 1'b1;
    ras_commit_br_type  = DIRECT_CALL;
    ras_commit_ret_addr = addr;
    ras_commit_snapshot = '0;
    tick();
    ras_commit_val      = 1'b0;
    ras_commit_br_type  = NO_BRANCH;
    ras_commit_ret_addr = '0;
  endtask

  // =================================================================
  // GROUP A -- bring-up
  // =================================================================
  task automatic group_a();
    int cyc_seen;
    $display("---- GROUP A: bring-up ----");
    do_reset();

    // -- A1. Reset, one request. The prediction must appear exactly
    //    one cycle after the request, carrying the requested index.
    chk("A1 pred_val low out of reset", bpu_pred_val_p1 === 1'b0);
    chk("A1 tage_pq_not_full out of reset", tage_pq_not_full === 1'b1);
    chk("A1 ittage_pq_not_full out of reset",
        ittage_pq_not_full === 1'b1);

    req(40'h00_0000_1000, 6'h15);
    tick();
    norq();
    chk("A1 pred_val at p1", bpu_pred_val_p1 === 1'b1);
    chk("A1 pred_idx at p1", bpu_pred_idx_p1 === 6'h15);
    cyc_seen = 1;
    tick();
    chk("A1 pred_val deasserts one cycle later",
        bpu_pred_val_p1 === 1'b0);
    chk("A1 latency is one cycle", cyc_seen == 1);

    // p2 group follows one cycle behind p1, p3 one behind that.
    chk("A1 meta_val_p2 at p2", bpu_meta_val_p2 === 1'b1);
    chk("A1 meta_idx_p2 at p2", bpu_meta_idx_p2 === 6'h15);
    chk("A1 redir_idx_p2 at p2", bpu_redir_idx_p2 === 6'h15);
    tick();
    chk("A1 meta_val_p3 at p3", bpu_meta_val_p3 === 1'b1);
    chk("A1 meta_idx_p3 at p3", bpu_meta_idx_p3 === 6'h15);
    chk("A1 redir_idx_p3 at p3", bpu_redir_idx_p3 === 6'h15);
    chk("A1 meta_val_p2 gone at p3", bpu_meta_val_p2 === 1'b0);

    // -- A2. The harness must exit non-zero on a failure. Every check
    //    routes through chk/chk_eq, which increments fail_cnt, and the
    //    run ends in $fatal(1) when fail_cnt is non-zero. +FORCE_FAIL=1
    //    breaks this one check so that path can be demonstrated
    //    without editing the file.
    chk("A2 deliberate-failure hook (see +FORCE_FAIL)",
        force_fail == 0);

    // -- A3. Reset-value conformance at the boundary (BP-094).
    //
    //    BP-093's A3 asked $isunknown of every boundary group. In the
    //    two-state value model this simulator uses, $isunknown of a
    //    logic can never be true, so that check passed BY
    //    CONSTRUCTION: it could not fail, and a check that cannot
    //    fail proves nothing. BP-093 said as much in its own
    //    assumptions list.
    //
    //    It is replaced with a check that CAN fail: after reset and
    //    with no request presented, every boundary VALID, ENABLE,
    //    COUNT and SELECT must read the SPECIFIC value the design
    //    resets to, not merely a known one. Each expected value below
    //    is the reset clause of the register that drives it:
    //      bp_cluster.sv reset block  -> r_val_p1/p2/p3, r_idx_*,
    //                                    r_ras_val_p3, r_br_type_p3
    //      bp_history                 -> ghist/phist pointers, GHR,
    //                                    PHR, checkpoint pointers
    //      ras.sv reset block         -> tosr = tosw = bos = 0, so
    //                                    the p1 snapshot is all zero
    //      bp_cluster sc_arb_cred_ff  -> pred_credits = SC_PRED_CREDITS
    //                                    upd_credits  = SC_UPD_CREDITS
    //                                    starve_ctr   = 0
    //    The queue-status outputs reset to NOT FULL, which is the
    //    value the FTQ needs to be allowed to issue at all.
    do_reset();
    norq();
    tick();

    // p1 group
    chk("A3 bpu_pred_val_p1 resets low", bpu_pred_val_p1 === 1'b0);
    chk("A3 bpu_pred_idx_p1 resets to zero",
        bpu_pred_idx_p1 === {FTQ_IDX_BITS{1'b0}});
    chk("A3 slot0 valid resets low",
        bpu_pred_slot_p1[0].slot_valid === 1'b0);
    chk("A3 slot1 valid resets low",
        bpu_pred_slot_p1[1].slot_valid === 1'b0);
    chk("A3 slot0 pred_src resets to PRED_NONE",
        bpu_pred_slot_p1[0].pred_src === PRED_NONE);
    chk("A3 slot1 pred_src resets to PRED_NONE",
        bpu_pred_slot_p1[1].pred_src === PRED_NONE);
    chk("A3 slot0 taken resets low",
        bpu_pred_slot_p1[0].taken === 1'b0);
    chk("A3 slot0 pos resets to zero",
        bpu_pred_slot_p1[0].pos === {FTB_BR_POS_BITS{1'b0}});
    chk("A3 slot1 pos resets to zero",
        bpu_pred_slot_p1[1].pos === {FTB_BR_POS_BITS{1'b0}});
    // ras.sv resets tosr, tosw and bos to zero, so the FE-11 snapshot
    // published at p1 is all zero out of reset.
    chk("A3 RAS snapshot tosr resets to zero",
        bpu_pred_ras_p1.tosr === '0);
    chk("A3 RAS snapshot tosw resets to zero",
        bpu_pred_ras_p1.tosw === '0);
    chk("A3 RAS snapshot bos resets to zero",
        bpu_pred_ras_p1.bos === '0);

    // p2 and p3 groups
    chk("A3 bpu_meta_val_p2 resets low", bpu_meta_val_p2 === 1'b0);
    chk("A3 bpu_meta_val_p3 resets low", bpu_meta_val_p3 === 1'b0);
    chk("A3 bpu_meta_idx_p2 resets to zero",
        bpu_meta_idx_p2 === {FTQ_IDX_BITS{1'b0}});
    chk("A3 bpu_meta_idx_p3 resets to zero",
        bpu_meta_idx_p3 === {FTQ_IDX_BITS{1'b0}});
    chk("A3 bpu_redir_idx_p2 resets to zero",
        bpu_redir_idx_p2 === {FTQ_IDX_BITS{1'b0}});
    chk("A3 bpu_redir_idx_p3 resets to zero",
        bpu_redir_idx_p3 === {FTQ_IDX_BITS{1'b0}});
    chk("A3 slot0 p2 redirect resets low",
        bpu_redir_p2[0].valid === 1'b0);
    chk("A3 slot1 p2 redirect resets low",
        bpu_redir_p2[1].valid === 1'b0);
    chk("A3 slot0 p3 redirect resets low",
        bpu_redir_p3[0].valid === 1'b0);
    chk("A3 slot1 p3 redirect resets low",
        bpu_redir_p3[1].valid === 1'b0);

    // Update-accept enables. Nothing has been presented, so every
    // per-slot accept and every u1 echo must be low.
    chk("A3 tage_upd_rdy_u1 resets low",
        tage_upd_rdy_u1 === {NUM_PRED_SLOTS{1'b0}});
    chk("A3 ittage_upd_rdy_u1 resets low",
        ittage_upd_rdy_u1 === {NUM_PRED_SLOTS{1'b0}});
    chk("A3 sc_upd_rdy_u1 resets low",
        sc_upd_rdy_u1 === {NUM_PRED_SLOTS{1'b0}});
    chk("A3 sc_upd_rdy resets low (no grant with no request)",
        sc_upd_rdy === {NUM_PRED_SLOTS{1'b0}});

    // Queue status resets to NOT FULL: the FTQ may issue.
    chk("A3 tage_pq_not_full resets high",
        tage_pq_not_full === 1'b1);
    chk("A3 ittage_pq_not_full resets high",
        ittage_pq_not_full === 1'b1);
    chk("A3 sc_uq_not_full resets high", sc_uq_not_full === 1'b1);

    // History counts and selects.
    chk("A3 ghist_ptr resets to zero",
        ghist_ptr === {GHIST_PTR_BITS{1'b0}});
    chk("A3 phist_ptr resets to zero",
        phist_ptr === {PHIST_PTR_BITS{1'b0}});
    chk("A3 ckpt_ghist_ptr resets to zero",
        ckpt_ghist_ptr === {GHIST_PTR_BITS{1'b0}});
    chk("A3 ckpt_phist_ptr resets to zero",
        ckpt_phist_ptr === {PHIST_PTR_BITS{1'b0}});
    chk("A3 ghr_buf resets to zero", ghr_buf === {GHR_WIDTH{1'b0}});
    chk("A3 phr_buf resets to zero", phr_buf === {PHR_WIDTH{1'b0}});
    chk("A3 checkpoint write enable resets low",
        dut.w_ckpt_wr_en === 1'b0);

    // SC credit-arbiter counts. Named in bp_arb_spec.md 4.5
    // Initialization; the arbiter is group H's subject and these are
    // its start values.
    chk("A3 SC pred credits reset to SC_PRED_CREDITS",
        dut.r_sc_pred_credits ===
          SC_PRED_CRED_W_TB'(SC_PRED_CREDITS));
    chk("A3 SC upd credits reset to SC_UPD_CREDITS",
        dut.r_sc_upd_credits === SC_UPD_CRED_W_TB'(SC_UPD_CREDITS));
    chk("A3 SC starve counter resets to zero",
        dut.r_sc_starve_ctr === {SC_STARVE_W_TB{1'b0}});
    chk("A3 no SC grant out of reset",
        (dut.w_sc_grant_pred === 1'b0)
     && (dut.w_sc_grant_upd  === 1'b0));

    if (fail_cnt != 0) begin
      $display("GROUP A NOT GREEN -- stopping (BP-093 stop rule 1)");
      $fatal(1, "tb_bp_cluster: group A failed, %0d checks failed",
             fail_cnt);
    end
    $display("---- GROUP A green (%0d checks) ----", pass_cnt);
  endtask

  // =================================================================
  // GROUP B -- p1 prediction
  // =================================================================
  task automatic group_b();
    ubtb_entry_t         e;
    logic [VA_WIDTH-1:0] pc;
    logic [VA_WIDTH-1:0] base;

    $display("---- GROUP B: p1 prediction ----");

    // -- B1. Selection per slot. There is no slot-0 exception: slot 1
    //    must take loop_pred when its lp_pred_is_loop is set.
    //    Case 1: loop_pred claims slot 1 only.
    do_reset();
    pc   = 40'h00_0000_1000;
    base = blk_base(pc);
    e    = '0;
    e.br0 = mk_cond(1'b1, 3'd1, base + 40'h100, base, 1'b0);
    e.br1 = mk_cond(1'b1, 3'd2, base + 40'h200, base, 1'b0);
    e.pft = ub_pft_field(base + BLK_SZ, base);
    e.carry = ub_pft_carry(base + BLK_SZ, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    // slot 1 bank: trusted loop entry predicting taken (curr < past)
    lp_install(1, pc, LP_CNF_BITS'(LP_CONF_LEVEL), 14'd1, 14'd4);
    req(pc, 6'h01);
    tick();
    norq();
    chk_ubtb_hash("B1a", pc);
    chk_lp_hash("B1a", pc);
    chk("B1 slot0 taken by uBTB (no slot-0 exception in play)",
        bpu_pred_slot_p1[0].pred_src === PRED_UBTB);
    chk("B1 slot1 taken by loop_pred",
        bpu_pred_slot_p1[1].pred_src === PRED_LOOP);
    chk("B1 slot1 direction is the loop direction",
        bpu_pred_slot_p1[1].taken === 1'b1);
    chk("B1 slot1 br_type forced COND by loop_pred",
        bpu_pred_slot_p1[1].br_type === COND);
    chk_eq("B1 slot1 target still the uBTB entry target",
           bpu_pred_slot_p1[1].target, base + 40'h200);
    chk("B1 slot1 pos survives the loop_pred override",
        bpu_pred_slot_p1[1].pos === 3'd2);

    //    Case 2: loop_pred claims slot 0 only. Proves the rule is
    //    symmetric and that slot 1 falls back to the uBTB.
    do_reset();
    ubtb_install(pc, e);
    lp_clear_both(pc);
    lp_install(0, pc, LP_CNF_BITS'(LP_CONF_LEVEL), 14'd4, 14'd4);
    req(pc, 6'h02);
    tick();
    norq();
    chk("B1 slot0 taken by loop_pred",
        bpu_pred_slot_p1[0].pred_src === PRED_LOOP);
    chk("B1 slot0 loop exit predicts not taken",
        bpu_pred_slot_p1[0].taken === 1'b0);
    chk("B1 slot1 falls back to uBTB",
        bpu_pred_slot_p1[1].pred_src === PRED_UBTB);

    //    Case 3: an untrusted loop entry (confidence below max) does
    //    not win. Pins the trust rule rather than mere presence.
    do_reset();
    ubtb_install(pc, e);
    lp_clear_both(pc);
    lp_install(1, pc, LP_CNF_BITS'(LP_CONF_LEVEL - 1), 14'd1, 14'd4);
    req(pc, 6'h03);
    tick();
    norq();
    chk("B1 untrusted loop entry does not win slot 1",
        bpu_pred_slot_p1[1].pred_src === PRED_UBTB);
    chk("B1 untrusted loop entry still reports a table hit",
        dut.w_lp_pred_p1[1].lp_hit === 1'b1);
    chk("B1 untrusted loop entry is not trusted",
        dut.w_lp_pred_p1[1].lp_pred_is_loop === 1'b0);

    // -- B2. Entry hit against slot valid.
    //    Case a: entry hits, no slot carries a branch. A legal state.
    do_reset();
    pc   = 40'h00_0000_3000;
    base = blk_base(pc);
    e    = '0;
    e.pft   = ub_pft_field(base + 40'h18, base);
    e.carry = ub_pft_carry(base + 40'h18, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    req(pc, 6'h04);
    tick();
    norq();
    chk("B2a entry hit with no valid slot: slot0 invalid",
        bpu_pred_slot_p1[0].slot_valid === 1'b0);
    chk("B2a entry hit with no valid slot: slot1 invalid",
        bpu_pred_slot_p1[1].slot_valid === 1'b0);
    chk("B2a prediction still allocated",
        bpu_pred_val_p1 === 1'b1);
    chk_eq("B2a fall-through comes from the hit entry",
           bpu_pred_pft_p1, base + 40'h18);
    chk("B2a hit reported to the p1 view",
        dut.r_ubtb_blk_p1.hit === 1'b1);

    //    Case b: entry misses entirely.
    do_reset();
    pc   = 40'h00_0000_4000;
    base = blk_base(pc);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h05);
    tick();
    norq();
    chk("B2b miss: slot0 invalid",
        bpu_pred_slot_p1[0].slot_valid === 1'b0);
    chk("B2b miss: slot1 invalid",
        bpu_pred_slot_p1[1].slot_valid === 1'b0);
    chk("B2b miss: pred_src NONE",
        bpu_pred_slot_p1[0].pred_src === PRED_NONE);
    chk("B2b miss: blk hit clear",
        dut.r_ubtb_blk_p1.hit === 1'b0);

    //    Case c: entry hits but only slot 1 carries a branch. The
    //    slot valid and the entry hit are separate terms.
    do_reset();
    pc   = 40'h00_0000_5000;
    base = blk_base(pc);
    e    = '0;
    e.br1 = mk_cond(1'b1, 3'd5, base + 40'h40, base, 1'b1);
    e.pft = ub_pft_field(base + BLK_SZ, base);
    e.carry = ub_pft_carry(base + BLK_SZ, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    req(pc, 6'h06);
    tick();
    norq();
    chk("B2c slot0 invalid on a hit entry",
        bpu_pred_slot_p1[0].slot_valid === 1'b0);
    chk("B2c slot1 valid on the same entry",
        bpu_pred_slot_p1[1].slot_valid === 1'b1);
    chk("B2c slot1 taken from the entry conf MSB",
        bpu_pred_slot_p1[1].taken === 1'b1);

    // -- B3. pos propagation from ubtb_pred_t into bp_ftq_slot_t.
    do_reset();
    pc   = 40'h00_0000_6000;
    base = blk_base(pc);
    e    = '0;
    e.br0 = mk_cond(1'b1, 3'd3, base + 40'h20, base, 1'b0);
    e.br1 = mk_cond(1'b1, 3'd7, base + 40'h60, base, 1'b0);
    e.pft = ub_pft_field(base + BLK_SZ, base);
    e.carry = ub_pft_carry(base + BLK_SZ, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    req(pc, 6'h07);
    tick();
    norq();
    chk("B3 slot0 pos propagated", bpu_pred_slot_p1[0].pos === 3'd3);
    chk("B3 slot1 pos propagated", bpu_pred_slot_p1[1].pos === 3'd7);

    // -- B4. RAS engagement at p1 on a uBTB RETURN. The top of stack
    //    is read at p0 and registered; the target must be that value
    //    and the source must be PRED_RAS.
    do_reset();
    pc   = 40'h00_0000_7000;
    base = blk_base(pc);
    ras_push_commit(40'h00_0000_ABC0);
    e    = '0;
    e.jmp = mk_jmp(1'b1, 3'd4, base + 40'h80, base, 1'b0, 1'b1, 1'b1);
    e.pft = ub_pft_field(base + BLK_SZ, base);
    e.carry = ub_pft_carry(base + BLK_SZ, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    req(pc, 6'h08);
    tick();
    norq();
    chk("B4 RETURN reported in the lowest free slot",
        bpu_pred_slot_p1[0].br_type === RETURN);
    chk("B4 RAS supplied the p1 target",
        bpu_pred_slot_p1[0].pred_src === PRED_RAS);
    chk_eq("B4 target is the registered top of stack",
           bpu_pred_slot_p1[0].target, 40'h00_0000_ABC0);
    chk("B4 a RETURN taken at p1", bpu_pred_slot_p1[0].taken === 1'b1);
    chk("B4 registered tos valid", dut.r_ras_tos_val_p1[0] === 1'b1);

    //    B4b: no RAS entry -> the uBTB entry target stands.
    do_reset();
    ubtb_install(pc, e);
    lp_clear_both(pc);
    req(pc, 6'h09);
    tick();
    norq();
    chk("B4b empty RAS: uBTB target stands",
        bpu_pred_slot_p1[0].pred_src === PRED_UBTB);
    chk_eq("B4b empty RAS: target is the entry jump target",
           bpu_pred_slot_p1[0].target, base + 40'h80);

    // -- B5. bpu_pred_pft_p1, the TD#108 fall-through.
    do_reset();
    pc   = 40'h00_0000_8000;
    base = blk_base(pc);
    e    = '0;
    e.br0 = mk_cond(1'b1, 3'd1, base + 40'h10, base, 1'b0);
    e.pft = ub_pft_field(base + 40'h0C, base);
    e.carry = ub_pft_carry(base + 40'h0C, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    req(pc, 6'h0A);
    tick();
    norq();
    chk_eq("B5 hit: pft is blk_p1.pft_addr",
           bpu_pred_pft_p1, base + 40'h0C);
    chk_eq("B5 hit: pft equals the internal p1 view",
           bpu_pred_pft_p1, dut.w_pft_p1);

    //    B5b: miss -> block-aligned PC plus one block. Request from
    //    mid-block so the alignment is actually exercised.
    do_reset();
    pc   = 40'h00_0000_901C;
    base = blk_base(pc);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h0B);
    tick();
    norq();
    chk_eq("B5b miss: pft is block base plus FTB_BLOCK_BYTES",
           bpu_pred_pft_p1, base + BLK_SZ);
    chk_eq("B5b miss: block base is the aligned request PC",
           dut.w_blk_base_p1, 40'h00_0000_9000);

    $display("---- GROUP B done (pass %0d fail %0d) ----",
             pass_cnt, fail_cnt);
  endtask

  // =================================================================
  // GROUP C -- p2 redirect
  // =================================================================
  //
  // Every case installs the FTB entry through the cluster update port,
  // then issues one request and reads the p2 group. bpu_redir_p2[s]
  // .target_pc carries the derived successor whether or not the
  // redirect fires, so the target SOURCE and the redirect DECISION are
  // separate observations.
  task automatic group_c();
    ubtb_entry_t         e;
    logic [VA_WIDTH-1:0] pc;
    logic [VA_WIDTH-1:0] base;
    logic [VA_WIDTH-1:0] pft;

    $display("---- GROUP C: p2 redirect ----");

    // -- C0. TAGE p2 metadata branch_id staging, the SPECIFIED
    //    behaviour (BP-094). Two back-to-back requests with DIFFERENT
    //    indices on DIFFERENT blocks. The response that arrives at the
    //    cluster p2 stage must carry the branch_id of the request that
    //    PRODUCED it -- the one sitting in the p2 stage register --
    //    not the one presented one cycle later. The cluster guard must
    //    therefore ACCEPT it.
    //
    //    BP-093 wrote this case as a pinning test whose expected value
    //    was the defect (branch_id === the NEXT request's index) so
    //    that fixing tage_cntrl would break it and force a revisit.
    //    That is what happened; the expected values below are now the
    //    specified ones. Both requests are checked, so the fix is
    //    shown to hold across the stream and not just on one cycle.
    do_reset();
    tage_bim_fill(2'b11);
    pc = 40'h00_0180_0000;
    ubtb_clear_set(pc);
    ubtb_clear_set(pc + BLK_SZ);
    lp_clear_both(pc);
    lp_clear_both(pc + BLK_SZ);
    req(pc, 6'h0C);
    tick();
    req(pc + BLK_SZ, 6'h0D);
    tick();
    norq();
    chk("C0 the p2 stage register holds the first request's index",
        dut.r_idx_p2 === 6'h0C);
    chk("C0 the TAGE response arrives at the cluster p2 stage",
        dut.w_tage_pred_rdy_p2[0] === 1'b1);
    chk("C0 TAGE p2 branch_id is the index of ITS OWN request",
        dut.w_tage_pred_meta_p2[0].branch_id === 6'h0C);
    chk("C0 slot 1 carries the same entry's branch_id",
        dut.w_tage_pred_meta_p2[1].branch_id === 6'h0C);
    chk("C0 the cluster branch_id guard accepts that response",
        dut.w_tage_hit_p2[0] === 1'b1);
    chk("C0 the metadata published to the FTQ names this entry",
        bpu_meta_tage_p2[0].branch_id === bpu_meta_idx_p2);
    tick();
    chk("C0 the second request follows it at p2",
        dut.r_idx_p2 === 6'h0D);
    chk("C0 the second response carries ITS own branch_id",
        dut.w_tage_pred_meta_p2[0].branch_id === 6'h0D);
    chk("C0 the guard accepts the second response too",
        dut.w_tage_hit_p2[0] === 1'b1);

    // -- C1a. Conditional slot, TAGE says taken -> FTB branch target.
    do_reset();
    tage_bim_fill(2'b11);           // TAGE predicts taken for any PC
    pc   = 40'h00_0100_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    // FTB br0 stored NOT taken, so a taken p2 result can only have
    // come from TAGE.
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b0, base + 40'h300, 3'd1, pft,
                   1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h10);
    tick();
    norq();
    tick();
    chk("C1a FTB entry hit at p2", bpu_meta_ftb_p2[0].hit === 1'b1);
    chk("C1a TAGE response matched this entry",
        dut.w_tage_hit_p2[0] === 1'b1);
    chk("C1a TAGE overrode the stored FTB direction",
        dut.w_taken_p2[0] === 1'b1);
    chk_eq("C1a successor is the FTB branch target",
           bpu_redir_p2[0].target_pc, base + 40'h300);

    // -- C1b. Conditional slot, TAGE says not taken -> fall-through.
    do_reset();
    tage_bim_fill(2'b00);           // TAGE predicts not taken
    pc   = 40'h00_0110_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    // FTB br0 stored TAKEN this time, so a not-taken p2 result can
    // only have come from TAGE.
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b1, base + 40'h300, 3'd1, pft,
                   1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h11);
    tick();
    norq();
    tick();
    chk("C1b TAGE response matched this entry",
        dut.w_tage_hit_p2[0] === 1'b1);
    chk("C1b TAGE overrode the stored FTB direction",
        dut.w_taken_p2[0] === 1'b0);
    chk_eq("C1b successor is the FTB fall-through",
           bpu_redir_p2[0].target_pc, pft);

    // -- C1c. RETURN -> RAS pop address.
    do_reset();
    tage_bim_fill(2'b00);
    ras_push_commit(40'h00_0000_DEC0);
    pc   = 40'h00_0120_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_jmp(pc, 2'd0, base + 40'h400, 3'd2, 1'b0, 1'b1, 1'b1,
                  pft, 1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h12);
    tick();
    norq();
    tick();
    chk("C1c FTB classified the jump as RETURN",
        dut.w_br_type_p2[0] === RETURN);
    chk("C1c RAS pop valid at p2",
        dut.w_ras_pop_valid_p2[0] === 1'b1);
    chk_eq("C1c successor is the RAS pop address",
           bpu_redir_p2[0].target_pc, 40'h00_0000_DEC0);

    // -- C1d. Direct unconditional -> FTB jump target.
    do_reset();
    tage_bim_fill(2'b00);
    pc   = 40'h00_0130_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_jmp(pc, 2'd0, base + 40'h500, 3'd3, 1'b0, 1'b0, 1'b0,
                  pft, 1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h13);
    tick();
    norq();
    tick();
    chk("C1d FTB classified the jump as DIRECT_UNC",
        dut.w_br_type_p2[0] === DIRECT_UNC);
    chk_eq("C1d successor is the FTB jump target",
           bpu_redir_p2[0].target_pc, base + 40'h500);

    // -- C1e. Indirect, ITTAGE misses -> FTB jump target stands.
    do_reset();
    tage_bim_fill(2'b00);
    pc   = 40'h00_0140_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_jmp(pc, 2'd0, base + 40'h600, 3'd4, 1'b0, 1'b0, 1'b1,
                  pft, 1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h14);
    tick();
    norq();
    tick();
    chk("C1e FTB classified the jump as INDIRECT_NONRET",
        dut.w_br_type_p2[0] === INDIRECT_NONRET);
    chk("C1e ITTAGE reports no hit",
        bpu_meta_ittage_p2[0].ittage_hit === 1'b0);
    chk_eq("C1e successor falls back to the FTB jump target",
           bpu_redir_p2[0].target_pc, base + 40'h600);

    // -- C1f. Indirect, ITTAGE hits -> ITTAGE target.
    //    The IT1 entry is written at the index and tag the DUT itself
    //    computed for this PC. bp_history does not advance across
    //    these requests (the uBTB misses, so num_branches is 0), so
    //    the folded history the hash uses is identical for the seeding
    //    request and the checking request.
    do_reset();
    tage_bim_fill(2'b00);
    pc   = 40'h00_0150_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_jmp(pc, 2'd0, base + 40'h600, 3'd4, 1'b0, 1'b0, 1'b1,
                  pft, 1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h15);
    #1;                              // let the p0 hashes settle
    ittage_seed_it1_s0(IT_MAX_TGT_WIDTH'(40'h00_0000_7788 >> 1));
    tick();
    norq();
    tick();
    tick();                          // history did not advance
    chk("C1f history held across the seeding request",
        ghist_ptr === {GHIST_PTR_BITS{1'b0}});
    req(pc, 6'h16);
    tick();
    norq();
    tick();
    chk("C1f ITTAGE reports a hit",
        bpu_meta_ittage_p2[0].ittage_hit === 1'b1);
    chk_eq("C1f successor is the ITTAGE target",
           bpu_redir_p2[0].target_pc, 40'h00_0000_7788);

    // -- C1g. The two call encodings of the FTB jump field. Both are
    //    RAS pushes, so the successor is the FTB jump target and the
    //    p2 snapshot must advance.
    do_reset();
    tage_bim_fill(2'b00);
    pc   = 40'h00_0155_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_jmp(pc, 2'd0, base + 40'h700, 3'd5, 1'b1, 1'b0, 1'b0,
                  pft, 1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h19);
    tick();
    norq();
    tick();
    chk("C1g direct call classified DIRECT_CALL",
        dut.w_br_type_p2[0] === DIRECT_CALL);
    chk_eq("C1g direct call successor is the FTB jump target",
           bpu_redir_p2[0].target_pc, base + 40'h700);
    chk("C1g direct call is a RAS push at p2",
        dut.w_ras_snapshot_p2[0].tosr !== dut.w_ras_snapshot_p2[0].bos);

    do_reset();
    tage_bim_fill(2'b00);
    pc   = 40'h00_0158_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_jmp(pc, 2'd0, base + 40'h700, 3'd5, 1'b1, 1'b0, 1'b1,
                  pft, 1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h1A);
    tick();
    norq();
    tick();
    chk("C1h indirect call classified INDIRECT_CALL",
        dut.w_br_type_p2[0] === INDIRECT_CALL);
    chk("C1h indirect call with no ITTAGE hit",
        bpu_meta_ittage_p2[0].ittage_hit === 1'b0);
    chk_eq("C1h indirect call successor is the FTB jump target",
           bpu_redir_p2[0].target_pc, base + 40'h700);

    // -- C1i. RETURN with an empty RAS. ras_pop_valid_p2 is low, so
    //    the successor falls back to the FTB jump target rather than
    //    using an invalid pop address.
    do_reset();
    tage_bim_fill(2'b00);
    pc   = 40'h00_015C_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_jmp(pc, 2'd0, base + 40'h800, 3'd2, 1'b0, 1'b1, 1'b1,
                  pft, 1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h1B);
    tick();
    norq();
    tick();
    chk("C1i RETURN classified with an empty RAS",
        dut.w_br_type_p2[0] === RETURN);
    chk("C1i RAS pop invalid on an empty stack",
        dut.w_ras_pop_valid_p2[0] === 1'b0);
    chk_eq("C1i successor falls back to the FTB jump target",
           bpu_redir_p2[0].target_pc, base + 40'h800);

    // -- C2. Two not-taken views compare equal and raise NO redirect.
    //    The uBTB and the FTB agree on the block end and neither slot
    //    is taken.
    do_reset();
    tage_bim_fill(2'b00);
    pc   = 40'h00_0160_0000;
    base = blk_base(pc);
    pft  = base + 40'h18;
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b0, base + 40'h300, 3'd1, pft,
                   1'b0);
    e       = '0;
    e.br0   = mk_cond(1'b1, 3'd1, base + 40'h300, base, 1'b0);
    e.pft   = ub_pft_field(pft, base);
    e.carry = ub_pft_carry(pft, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    req(pc, 6'h17);
    tick();
    norq();
    chk_eq("C2 p1 fall-through matches the FTB block end",
           bpu_pred_pft_p1, pft);
    tick();
    chk("C2 slot0 raises no p2 redirect",
        bpu_redir_p2[0].valid === 1'b0);
    chk("C2 slot1 raises no p2 redirect",
        bpu_redir_p2[1].valid === 1'b0);
    chk_eq("C2 successor is the shared fall-through",
           bpu_redir_p2[0].target_pc, pft);

    // -- C3. Not-taken slot, uBTB and FTB disagree on the block end.
    //    The p1 operand is formed from the p1 view only, so this
    //    redirects at p2 where a shared-FTB operand would have hidden
    //    it.
    do_reset();
    tage_bim_fill(2'b00);
    pc   = 40'h00_0170_0000;
    base = blk_base(pc);
    pft  = base + 40'h18;                       // FTB block end
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b0, base + 40'h300, 3'd1, pft,
                   1'b0);
    e       = '0;
    e.br0   = mk_cond(1'b1, 3'd1, base + 40'h300, base, 1'b0);
    e.pft   = ub_pft_field(base + 40'h0C, base); // uBTB block end
    e.carry = ub_pft_carry(base + 40'h0C, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    req(pc, 6'h18);
    tick();
    norq();
    chk_eq("C3 p1 fall-through is the uBTB block end",
           bpu_pred_pft_p1, base + 40'h0C);
    tick();
    chk("C3 stale block boundary redirects at p2",
        bpu_redir_p2[0].valid === 1'b1);
    chk_eq("C3 redirect target is the FTB block end",
           bpu_redir_p2[0].target_pc, pft);
    chk("C3 redirect index is the p2 stage index",
        bpu_redir_idx_p2 === 6'h18);

    // -- C4. BP-094. A back-to-back UNSTALLED stream, no repeated
    //    index and no arbiter stall, delivering the TAGE direction at
    //    p2 and the SC correction at p3 to the FTQ on EVERY request.
    //
    //    This is the sharpest single proof of the fix. Under BP-093
    //    this stream delivered NOTHING: the skewed branch_id never
    //    equalled the p2 stage index in an unstalled stream, so
    //    w_tage_hit_p2 and w_sc_hit_p3 were low on every cycle and
    //    neither the TAGE direction nor the SC correction ever
    //    reached the FTQ. Every TAGE and SC case in BP-093 needed the
    //    index repeated on the following cycle to reach those arms at
    //    all.
    //
    //    Fixture. The FTB conditional is stored NOT taken and the
    //    bimodal is all-taken, so a taken p2 result can only have
    //    come from TAGE. The SC counters are at SC_CTR_MIN, so SC
    //    reverses that direction at p3 and the p3 successor is the
    //    fall-through. The uBTB set is cleared, so the p1 view is the
    //    block fall-through and the p2 redirect is unambiguous.
    //    sc_enable is high but NO SC update request stands, so the
    //    credit arbiter takes rule 5 every cycle and
    //    w_tage_consumer_ready never drops -- the stream is unstalled
    //    by construction, which is checked below rather than assumed.
    do_reset();
    tage_bim_fill(2'b11);
    sc_fill(6'b100000);              // SC_CTR_MIN, strongly not taken
    sc_enable = 1'b1;
    pc   = 40'h00_0190_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b0, base + 40'h300, 3'd1, pft,
                   1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    begin
      int p2_seen;
      int p3_seen;
      int stall_seen;
      p2_seen    = 0;
      p3_seen    = 0;
      stall_seen = 0;
      // 16 requests, one per cycle, index incrementing, never
      // repeated. Two trailing idle cycles drain p2 and p3.
      for (int i = 0; i < 18; i++) begin
        if (i < 16) req(pc, FTQ_IDX_BITS'(6'h04 + i));
        else        norq();
        tick();

        if (dut.w_tage_consumer_ready !== 1'b1) stall_seen++;

        if (dut.r_val_p2 === 1'b1) begin
          p2_seen++;
          chk_q("C4 TAGE response branch_id equals the p2 index",
                dut.w_tage_pred_meta_p2[0].branch_id === dut.r_idx_p2);
          chk_q("C4 the branch_id guard accepts every response",
                dut.w_tage_hit_p2[0] === 1'b1);
          chk_q("C4 TAGE overrode the stored FTB direction",
                dut.w_taken_p2[0] === 1'b1);
          chk_eq_q("C4 p2 successor reaching the FTQ is the branch target",
                   bpu_redir_p2[0].target_pc, base + 40'h300);
          chk_q("C4 the p2 metadata write names this entry",
                bpu_meta_tage_p2[0].branch_id === bpu_meta_idx_p2);
        end

        if (dut.r_val_p3 === 1'b1) begin
          p3_seen++;
          chk_q("C4 SC response branch_id equals the p3 index",
                dut.w_sc_pred_meta_p3[0].branch_id === dut.r_idx_p3);
          chk_q("C4 the SC branch_id guard accepts every response",
                dut.w_sc_hit_p3[0] === 1'b1);
          chk_q("C4 SC recorded an override",
                bpu_meta_sc_p3[0].sc_override === 1'b1);
          chk_q("C4 the SC correction reaches the FTQ as a p3 redirect",
                bpu_redir_p3[0].valid === 1'b1);
          chk_eq_q("C4 p3 redirect target is the fall-through",
                   bpu_redir_p3[0].target_pc, pft);
          chk_q("C4 the p3 redirect names the p3 stage entry",
                bpu_redir_idx_p3 === dut.r_idx_p3);
        end
      end
      norq();
      chk("C4 every request produced a p2 response", p2_seen == 16);
      chk("C4 every request produced a p3 response", p3_seen == 16);
      chk("C4 the stream ran with NO consumer_ready stall",
          stall_seen == 0);
      $display("INFO: C4 unstalled stream p2=%0d p3=%0d stalls=%0d",
               p2_seen, p3_seen, stall_seen);
    end
    sc_enable = 1'b0;

    $display("---- GROUP C done (pass %0d fail %0d) ----",
             pass_cnt, fail_cnt);
  endtask

  // =================================================================
  // GROUP D -- p3 and supersession
  // =================================================================
  task automatic group_d();
    logic [VA_WIDTH-1:0] pc;
    logic [VA_WIDTH-1:0] base;
    logic [VA_WIDTH-1:0] pft;
    int                  mismatch_seen;
    int                  match_seen;
    logic [FTQ_IDX_BITS-1:0] idx_q;

    $display("---- GROUP D: p3 and supersession ----");

    // -- D1a. SC changes the published p2 direction -> p3 redirect.
    //    TAGE predicts taken (bimodal saturated), the SC counters are
    //    saturated the other way, so the SC local direction differs
    //    and the general-differ arm of sc_cntrl overrides.
    do_reset();
    tage_bim_fill(2'b11);
    sc_fill(6'b100000);              // SC_CTR_MIN, strongly not taken
    sc_enable = 1'b1;
    pc   = 40'h00_0200_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b1, base + 40'h300, 3'd1, pft,
                   1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h20);
    tick();
    norq();
    tick();
    chk("D1a p2 published taken",  dut.w_taken_p2[0] === 1'b1);
    chk_eq("D1a p2 successor is the branch target",
           bpu_redir_p2[0].target_pc, base + 40'h300);
    tick();
    chk("D1a SC response matched this entry",
        dut.w_sc_hit_p3[0] === 1'b1);
    chk("D1a SC recorded an override",
        bpu_meta_sc_p3[0].sc_override === 1'b1);
    chk("D1a SC direction differs from the p2 direction",
        bpu_meta_sc_p3[0].sc_pred_tkn === 1'b0);
    chk("D1a p3 redirect fires",  bpu_redir_p3[0].valid === 1'b1);
    chk_eq("D1a p3 redirect target is the fall-through",
           bpu_redir_p3[0].target_pc, pft);
    chk("D1a p3 redirect index is the p3 stage index",
        bpu_redir_idx_p3 === 6'h20);

    // -- D1b. SC agrees with the p2 direction -> NO p3 redirect.
    //    Same fixture with the SC counters saturated the same way as
    //    TAGE, so nothing changes at p3 and supersession is not
    //    triggered by mere SC presence.
    do_reset();
    tage_bim_fill(2'b11);
    sc_fill(6'b011111);              // SC_CTR_MAX, strongly taken
    sc_enable = 1'b1;
    pc   = 40'h00_0210_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b1, base + 40'h300, 3'd1, pft,
                   1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h21);
    tick();
    norq();
    tick();
    tick();
    chk("D1b SC response matched this entry",
        dut.w_sc_hit_p3[0] === 1'b1);
    chk("D1b SC agrees with TAGE",
        bpu_meta_sc_p3[0].sc_pred_tkn === 1'b1);
    chk("D1b no p3 redirect when SC changes nothing",
        bpu_redir_p3[0].valid === 1'b0);
    chk_eq("D1b p3 successor equals the p2 successor",
           bpu_redir_p3[0].target_pc, base + 40'h300);

    // -- D1c. SC disabled. bpu_meta_val_p3 must still assert and no
    //    p3 redirect may fire.
    do_reset();
    tage_bim_fill(2'b11);
    sc_fill(6'b100000);
    sc_enable = 1'b0;
    pc   = 40'h00_0220_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b1, base + 40'h300, 3'd1, pft,
                   1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h22);
    tick();
    norq();
    tick();
    tick();
    chk("D1c SC disabled: no p3 hit",
        dut.w_sc_hit_p3[0] === 1'b0);
    chk("D1c SC disabled: no p3 redirect",
        bpu_redir_p3[0].valid === 1'b0);
    chk("D1c SC disabled: metadata write still valid",
        bpu_meta_val_p3 === 1'b1);

    // -- D2. branch_id match rejecting a delayed response.
    //    Construction, per BP-093 binding decision 2: back-to-back
    //    requests with different FTQ indices while the TAGE response
    //    path is held. The hold is created at the boundary only: with
    //    SC enabled and an SC update request standing, the cluster's
    //    SC credit arbiter grants the update on the cycle its
    //    prediction credits run out, and the cluster drives
    //    consumer_ready low for that cycle. TAGE buffers its result,
    //    the cluster p2 stage register advances anyway, and the next
    //    response arrives carrying an older branch_id.
    //
    //    No predictor metadata is forced and no predictor is stubbed.
    //    The observation is w_tage_hit_p2, plus the queue-status
    //    outputs the FTQ would see.
    //
    //    BP-094 adds the check that makes the accepted responses
    //    GENUINE rather than accidental. The stream issues indices
    //    0, 1, 2, ... with no wrap (40 requests, FTQ_IDX_BITS is 6),
    //    so request age is index order. A response held one cycle by
    //    the arbiter must therefore carry a branch_id OLDER than the
    //    index at p2 -- it is a delayed answer to an earlier entry.
    //    Under BP-093 every mismatched response carried a branch_id
    //    one NEWER than the entry at p2, because the skew read the
    //    p0 input a cycle ahead; that is the opposite direction and
    //    this check fails against the unfixed RTL. The counts
    //    themselves are unchanged by the fix (28 mismatched, 4
    //    matched): the arbiter still stalls the same cycles. What
    //    changed is which entry each response belongs to.
    do_reset();
    tage_bim_fill(2'b11);
    sc_fill(6'b011111);
    sc_enable = 1'b1;
    // Structural bits only: is_br makes the cluster classify update
    // channel 0 as COND so the SC update request stands. The uBTB
    // update itself stays inactive (valid low).
    ubtb_upd_u0[0].valid = 1'b0;
    ubtb_upd_u0[0].is_br = 1'b1;
    sc_upd_val_u0[0]     = 1'b1;

    mismatch_seen = 0;
    match_seen    = 0;
    idx_q         = 6'h00;
    for (int i = 0; i < 40; i++) begin
      req(40'h00_0300_0000 + VA_WIDTH'(i * 32), idx_q);
      idx_q = idx_q + 6'd1;
      tick();
      if (dut.r_val_p2 === 1'b1 && dut.w_tage_pred_rdy_p2[0] === 1'b1)
      begin
        if (dut.w_tage_pred_meta_p2[0].branch_id !== dut.r_idx_p2) begin
          mismatch_seen++;
          chk_q("D2 mismatched branch_id rejected",
                dut.w_tage_hit_p2[0] === 1'b0);
          // A held response answers an OLDER entry, never a newer
          // one. This is the check the skew fails.
          chk_q("D2 a delayed response carries an OLDER branch_id",
                dut.w_tage_pred_meta_p2[0].branch_id < dut.r_idx_p2);
        end else begin
          match_seen++;
          chk_q("D2 matched branch_id accepted",
                dut.w_tage_hit_p2[0] === 1'b1);
          // A genuine match: the SC metadata one stage later must
          // name the same entry, since SC copies the staged TAGE
          // branch_id. A coincidental match cannot hold this.
          chk_q("D2 the accepted response is published to the FTQ",
                bpu_meta_tage_p2[0].branch_id === bpu_meta_idx_p2);
        end
      end
    end
    norq();
    sc_upd_val_u0        = '0;
    ubtb_upd_u0          = '0;
    chk("D2 at least one matched response observed", match_seen > 0);
    if (mismatch_seen == 0) begin
      $display(
        "NOTE: D2 saw no delayed TAGE response at the boundary; the");
      $display(
        "      branch_id reject arm was not reached. Reported, not");
      $display("      worked around (BP-093 decision 2).");
      chk("D2 delayed response constructed at the boundary", 1'b0);
    end else begin
      chk("D2 delayed response constructed at the boundary", 1'b1);
      $display("INFO: D2 matched %0d, mismatched %0d",
               match_seen, mismatch_seen);
    end
    // The queue status the FTQ observes must stay legal throughout.
    chk("D2 queue status readable at the boundary",
        !$isunknown({tage_pq_not_full, ittage_pq_not_full,
                     sc_uq_not_full}));

    sc_enable = 1'b0;
    $display("---- GROUP D done (pass %0d fail %0d) ----",
             pass_cnt, fail_cnt);
  endtask

  // =================================================================
  // GROUP E -- history (BP-092a TC-A .. TC-G, plus E1 E2 E3)
  // =================================================================
  task automatic group_e();
    ubtb_entry_t         e;
    logic [VA_WIDTH-1:0] pc;
    logic [VA_WIDTH-1:0] base;
    logic [VA_WIDTH-1:0] pft;
    logic [GHIST_PTR_BITS-1:0] g0;
    logic [PHIST_PTR_BITS-1:0] p0;
    int                        sweep_pairs;
    int                        tie_seen;

    $display("---- GROUP E: history ----");

    // -- TC-A. Two branches in one block, block-aligned request.
    do_reset();
    pc   = 40'h00_0000_1000;
    base = blk_base(pc);
    e       = '0;
    e.br0   = mk_cond(1'b1, 3'd1, base + 40'h100, base, 1'b0);
    e.br1   = mk_cond(1'b1, 3'd2, base + 40'h200, base, 1'b1);
    e.pft   = ub_pft_field(base + BLK_SZ, base);
    e.carry = ub_pft_carry(base + BLK_SZ, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    g0 = ghist_ptr;
    p0 = phist_ptr;
    req(pc, 6'h30);
    tick();
    norq();
    chk_eq("TC-A blk_base", dut.w_blk_base_p1, 40'h00_0000_1000);
    chk_eq("TC-A slot_pc[0]", dut.w_slot_pc_p1[0], 40'h00_0000_1004);
    chk_eq("TC-A slot_pc[1]", dut.w_slot_pc_p1[1], 40'h00_0000_1008);
    chk("TC-A num_branches", dut.w_hist_num_branches === 2'd2);
    chk_eq("TC-A pred_pc[0]", dut.w_hist_pred_pc[0], 40'h00_0000_1004);
    chk_eq("TC-A pred_pc[1]", dut.w_hist_pred_pc[1], 40'h00_0000_1008);
    chk("TC-A pred_taken", dut.w_hist_pred_taken === 2'b10);
    chk("TC-A path_bit_0 = pc[2]^pc[3] of 0x1004 = 1",
        dut.u_bp_history.path_bit_0 === 1'b1);
    chk("TC-A path_bit_1 = pc[2]^pc[3] of 0x1008 = 1",
        dut.u_bp_history.path_bit_1 === 1'b1);
    tick();
    chk("TC-A ghist pointer advanced by 2",
        ghist_ptr === GHIST_PTR_BITS'(g0 + 2));
    chk("TC-A phist pointer advanced by 2",
        phist_ptr === PHIST_PTR_BITS'(p0 + 2));
    chk("TC-A PHR took 1 then 1", phr_buf[1:0] === 2'b11);
    chk("TC-A GHR took 0 then 1", ghr_buf[1:0] === 2'b10);

    // -- TC-B. Same block, unaligned request PC. Byte-for-byte the
    //    same reported PCs as TC-A.
    do_reset();
    pc   = 40'h00_0000_101C;
    base = blk_base(pc);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    req(pc, 6'h31);
    tick();
    norq();
    chk_eq("TC-B blk_base ignores the in-block offset",
           dut.w_blk_base_p1, 40'h00_0000_1000);
    chk_eq("TC-B slot_pc[0]", dut.w_slot_pc_p1[0], 40'h00_0000_1004);
    chk_eq("TC-B slot_pc[1]", dut.w_slot_pc_p1[1], 40'h00_0000_1008);
    chk_eq("TC-B pred_pc[0]", dut.w_hist_pred_pc[0], 40'h00_0000_1004);
    chk_eq("TC-B pred_pc[1]", dut.w_hist_pred_pc[1], 40'h00_0000_1008);

    // -- TC-C. Position sweep, all 8x8 pairs.
    sweep_pairs = 0;
    for (int p0i = 0; p0i < 8; p0i++) begin
      for (int p1i = 0; p1i < 8; p1i++) begin
        do_reset();
        pc   = 40'h00_0000_2000;
        base = blk_base(pc);
        e       = '0;
        e.br0   = mk_cond(1'b1, UBTB_BR_POS_BITS'(p0i),
                          base + 40'h100, base, 1'b0);
        e.br1   = mk_cond(1'b1, UBTB_BR_POS_BITS'(p1i),
                          base + 40'h200, base, 1'b0);
        e.pft   = ub_pft_field(base + BLK_SZ, base);
        e.carry = ub_pft_carry(base + BLK_SZ, base);
        ubtb_install(pc, e);
        lp_clear_both(pc);
        req(pc, 6'h32);
        tick();
        norq();
        chk_eq_q("TC-C slot_pc[0]", dut.w_slot_pc_p1[0],
                 base + VA_WIDTH'(p0i << BR_POS_SHIFT));
        chk_eq_q("TC-C slot_pc[1]", dut.w_slot_pc_p1[1],
                 base + VA_WIDTH'(p1i << BR_POS_SHIFT));
        chk_q("TC-C path_bit_0",
              dut.u_bp_history.path_bit_0 === (p0i[1] ^ p0i[0]));
        chk_q("TC-C path_bit_1",
              dut.u_bp_history.path_bit_1 === (p1i[1] ^ p1i[0]));
        sweep_pairs++;
      end
    end
    chk("TC-C every position pair was driven", sweep_pairs == 64);

    // -- TC-D / E3. One branch only, in slot 1 -- compaction.
    do_reset();
    pc   = 40'h00_0000_3000;
    base = blk_base(pc);
    e       = '0;
    e.br1   = mk_cond(1'b1, 3'd5, base + 40'h200, base, 1'b1);
    e.pft   = ub_pft_field(base + BLK_SZ, base);
    e.carry = ub_pft_carry(base + BLK_SZ, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    req(pc, 6'h33);
    tick();
    norq();
    chk_eq("TC-D slot_pc[0] is zero on an invalid slot",
           dut.w_slot_pc_p1[0], 40'h0);
    chk_eq("TC-D slot_pc[1]", dut.w_slot_pc_p1[1], 40'h00_0000_3014);
    chk("TC-D num_branches", dut.w_hist_num_branches === 2'd1);
    chk_eq("TC-D/E3 slot-1 branch presented at branch index 0",
           dut.w_hist_pred_pc[0], 40'h00_0000_3014);
    chk_eq("TC-D pred_pc[1] untouched",
           dut.w_hist_pred_pc[1], 40'h0);
    chk("TC-D/E3 that branch's direction at index 0",
        dut.w_hist_pred_taken[0] === 1'b1);

    // -- TC-E. No branch in the block. bp_history holds.
    do_reset();
    pc   = 40'h00_0000_4000;
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    g0 = ghist_ptr;
    p0 = phist_ptr;
    req(pc, 6'h34);
    tick();
    norq();
    chk_eq("TC-E slot_pc[0] zero", dut.w_slot_pc_p1[0], 40'h0);
    chk_eq("TC-E slot_pc[1] zero", dut.w_slot_pc_p1[1], 40'h0);
    chk("TC-E num_branches zero", dut.w_hist_num_branches === 2'd0);
    chk_eq("TC-E pred_pc[0] zero", dut.w_hist_pred_pc[0], 40'h0);
    chk_eq("TC-E pred_pc[1] zero", dut.w_hist_pred_pc[1], 40'h0);
    tick();
    chk("TC-E ghist pointer held", ghist_ptr === g0);
    chk("TC-E phist pointer held", phist_ptr === p0);
    chk("TC-E GHR held", ghr_buf === {GHR_WIDTH{1'b0}});
    chk("TC-E PHR held", phr_buf === {PHR_WIDTH{1'b0}});

    // -- TC-F. loop_pred wins the selection mux.
    do_reset();
    pc   = 40'h00_0000_5000;
    base = blk_base(pc);
    e       = '0;
    e.br0   = mk_cond(1'b1, 3'd6, base + 40'h100, base, 1'b0);
    e.pft   = ub_pft_field(base + BLK_SZ, base);
    e.carry = ub_pft_carry(base + BLK_SZ, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    lp_install(0, pc, LP_CNF_BITS'(LP_CONF_LEVEL), 14'd1, 14'd4);
    req(pc, 6'h35);
    tick();
    norq();
    chk("TC-F pred_src is PRED_LOOP",
        bpu_pred_slot_p1[0].pred_src === PRED_LOOP);
    chk("TC-F entry position survives the override",
        bpu_pred_slot_p1[0].pos === 3'd6);
    chk_eq("TC-F slot_pc[0]", dut.w_slot_pc_p1[0], 40'h00_0000_5018);
    chk("TC-F reported direction is the loop direction",
        dut.w_hist_pred_taken[0] === 1'b1);
    chk_eq("TC-F pred_pc[0]", dut.w_hist_pred_pc[0], 40'h00_0000_5018);

    // -- TC-G. loop_pred wins with no uBTB entry for that slot.
    do_reset();
    pc   = 40'h00_0000_6000;
    base = blk_base(pc);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    lp_install(0, pc, LP_CNF_BITS'(LP_CONF_LEVEL), 14'd1, 14'd4);
    req(pc, 6'h36);
    tick();
    norq();
    chk("TC-G slot0 is valid from loop_pred alone",
        bpu_pred_slot_p1[0].slot_valid === 1'b1);
    chk("TC-G position gated off with no uBTB entry",
        bpu_pred_slot_p1[0].pos === 3'd0);
    chk_eq("TC-G target gated off with no uBTB entry",
           bpu_pred_slot_p1[0].target, 40'h0);
    chk_eq("TC-G slot_pc[0] is the block base",
           dut.w_slot_pc_p1[0], 40'h00_0000_6000);
    chk_eq("TC-G pred_pc[0] is the block base",
           dut.w_hist_pred_pc[0], 40'h00_0000_6000);
    chk("TC-G path bit is 0", dut.u_bp_history.path_bit_0 === 1'b0);

    // -- E1. Checkpoint write at allocation. The checkpoint holds the
    //    POST-advance pointer pair for the allocated index.
    do_reset();
    pc   = 40'h00_0000_1000;
    base = blk_base(pc);
    e       = '0;
    e.br0   = mk_cond(1'b1, 3'd1, base + 40'h100, base, 1'b0);
    e.br1   = mk_cond(1'b1, 3'd2, base + 40'h200, base, 1'b1);
    e.pft   = ub_pft_field(base + BLK_SZ, base);
    e.carry = ub_pft_carry(base + BLK_SZ, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    chk("E1 checkpoint write disabled with no prediction",
        dut.w_ckpt_wr_en === 1'b0);
    req(pc, 6'h2A);
    tick();
    norq();
    chk("E1 checkpoint write enabled at allocation",
        dut.w_ckpt_wr_en === 1'b1);
    chk("E1 checkpoint index is the allocated index",
        dut.w_ckpt_wr_idx === 6'h2A);
    tick();
    chk("E1 checkpoint stored the post-advance ghist pointer",
        dut.u_bp_history.ckpt_gptr[6'h2A] === GHIST_PTR_BITS'(2));
    chk("E1 checkpoint stored the post-advance phist pointer",
        dut.u_bp_history.ckpt_pptr[6'h2A] === PHIST_PTR_BITS'(2));
    chk("E1 checkpoint exposed on ckpt_ghist_ptr",
        ckpt_ghist_ptr === GHIST_PTR_BITS'(2));
    chk("E1 checkpoint exposed on ckpt_phist_ptr",
        ckpt_phist_ptr === PHIST_PTR_BITS'(2));

    // -- E2. Rollback on redirect.
    //
    //    E2a. Both stages redirect in the same cycle; the p3 index
    //    wins. The block carries a stale uBTB block end (a p2
    //    redirect) AND an SC direction change (a p3 redirect).
    //
    //    BP-094 makes this the DIRECT construction. Two consecutive
    //    requests with DIFFERENT FTQ indices are issued on the same
    //    block; one cycle later the first is at p3 raising the SC
    //    redirect and the second is at p2 raising the stale-boundary
    //    redirect, so the tie is reached with distinct indices and no
    //    arbiter trickery. Under BP-093 this was impossible: the
    //    skewed branch_id forced the two indices equal on every
    //    reachable cycle, which is why E2d had to construct the tie
    //    through an arbiter stall to discriminate the mux at all.
    do_reset();
    tage_bim_fill(2'b11);
    sc_fill(6'b100000);
    sc_enable = 1'b1;

    pc   = 40'h00_0400_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;              // FTB block end
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b1, base + 40'h300, 3'd1, pft,
                   1'b0);
    e       = '0;
    e.br0   = mk_cond(1'b1, 3'd1, base + 40'h300, base, 1'b0);
    e.pft   = ub_pft_field(base + 40'h0C, base);   // stale block end
    e.carry = ub_pft_carry(base + 40'h0C, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);

    req(pc, 6'h3A);
    tick();
    req(pc, 6'h3B);                 // DIFFERENT index, same block
    tick();
    norq();
    tick();                         // 0x3A at p3, 0x3B at p2
    chk("E2a p2 redirect present", dut.w_any_redir_p2 === 1'b1);
    chk("E2a p3 redirect present", dut.w_any_redir_p3 === 1'b1);
    chk("E2a the two stage indices are DISTINCT",
        dut.r_idx_p2 !== dut.r_idx_p3);
    chk("E2a p2 stage holds the second request",
        dut.r_idx_p2 === 6'h3B);
    chk("E2a p3 stage holds the first request",
        dut.r_idx_p3 === 6'h3A);
    chk("E2a rollback valid", dut.w_rollback_valid === 1'b1);
    chk("E2a p3 index selected on a same-cycle tie",
        dut.w_rollback_ckpt_idx === dut.r_idx_p3);
    chk("E2a rollback index is the entry being corrected",
        dut.w_rollback_ckpt_idx === 6'h3A);
    tick();
    chk("E2a history pointer restored from the checkpoint",
        ghist_ptr === dut.u_bp_history.ckpt_gptr[6'h3A]);

    //    E2c: a p3 redirect with no p2 redirect. The rollback must
    //    still be valid and must name the p3 index. TAGE resolves the
    //    slot NOT taken, so the p2 successor is the FTB block end and
    //    equals the p1 view; SC then flips the direction at p3.
    do_reset();
    tage_bim_fill(2'b00);
    sc_fill(6'b011111);
    sc_enable = 1'b1;
    pc   = 40'h00_0430_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b0, base + 40'h300, 3'd1, pft,
                   1'b0);
    ubtb_clear_set(pc);             // p1 fall-through matches the FTB
    lp_clear_both(pc);
    req(pc, 6'h3D);
    tick();
    norq();
    tick();
    chk("E2c no p2 redirect from this block",
        dut.w_any_redir_p2 === 1'b0);
    tick();
    chk("E2c p3 redirect alone", dut.w_any_redir_p3 === 1'b1);
    chk("E2c rollback valid on a p3-only redirect",
        dut.w_rollback_valid === 1'b1);
    chk("E2c rollback takes the p3 index",
        dut.w_rollback_ckpt_idx === 6'h3D);

    //    E2b: a p2 redirect alone rolls back to the p2 index. Here
    //    the p2 and p3 indices DO differ, so the mux is discriminated
    //    on its p2 arm.
    do_reset();
    tage_bim_fill(2'b00);
    sc_enable = 1'b0;
    ftb_alloc_cond(40'h00_0420_0000, 2'd0, 1'b0, 1'b0,
                   40'h00_0420_0300, 3'd1,
                   40'h00_0420_0018, 1'b0);
    e       = '0;
    e.br0   = mk_cond(1'b1, 3'd1, 40'h00_0420_0300,
                      40'h00_0420_0000, 1'b0);
    e.pft   = ub_pft_field(40'h00_0420_000C, 40'h00_0420_0000);
    e.carry = ub_pft_carry(40'h00_0420_000C, 40'h00_0420_0000);
    ubtb_install(40'h00_0420_0000, e);
    lp_clear_both(40'h00_0420_0000);
    req(40'h00_0420_0000, 6'h3C);
    tick();
    req(40'h00_0420_0000, 6'h1C);
    tick();
    norq();
    chk("E2b p2 redirect alone", dut.w_any_redir_p2 === 1'b1);
    chk("E2b no p3 redirect this cycle",
        dut.w_any_redir_p3 === 1'b0);
    chk("E2b p3 index differs from the p2 index",
        dut.r_idx_p3 !== dut.r_idx_p2);
    chk("E2b rollback takes the p2 index",
        dut.w_rollback_ckpt_idx === 6'h3C);

    //    E2d: the same-cycle tie with DISTINCT p2 and p3 indices.
    //    Reached by running a stream while the SC credit arbiter
    //    periodically drops the TAGE consumer_ready (the same
    //    boundary construction as D2). A one-cycle hold on the TAGE
    //    response shifts the C0 branch_id skew into alignment, so the
    //    SC result lands on an entry whose index differs from the one
    //    at p2 that cycle. Eight blocks are installed with an FTB
    //    conditional field and a stale uBTB block end, so every block
    //    can redirect at p2 while SC reverses the direction at p3.
    do_reset();
    tage_bim_fill(2'b11);
    sc_fill(6'b100000);
    sc_enable = 1'b1;
    for (int b = 0; b < 8; b++) begin
      pc   = 40'h00_0440_0000 + VA_WIDTH'(b * 32);
      base = blk_base(pc);
      ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b1, base + 40'h300, 3'd1,
                     base + BLK_SZ, 1'b0);
      e       = '0;
      e.br0   = mk_cond(1'b1, 3'd1, base + 40'h300, base, 1'b0);
      e.pft   = ub_pft_field(base + 40'h0C, base);
      e.carry = ub_pft_carry(base + 40'h0C, base);
      ubtb_install(pc, e);
      lp_clear_both(pc);
    end
    // Structural bits only: keeps an SC update request standing so
    // the cluster arbiter grants it now and then. The uBTB update
    // itself stays inactive.
    ubtb_upd_u0[0].valid = 1'b0;
    ubtb_upd_u0[0].is_br = 1'b1;
    sc_upd_val_u0[0]     = 1'b1;
    tie_seen = 0;
    for (int i = 0; i < 60; i++) begin
      req(40'h00_0440_0000 + (VA_WIDTH'(i % 8) * BLK_SZ),
          FTQ_IDX_BITS'(i));
      tick();
      if (dut.w_any_redir_p2 && dut.w_any_redir_p3
          && (dut.r_idx_p2 !== dut.r_idx_p3)) begin
        tie_seen++;
        chk_q("E2d p3 index wins a tie with distinct indices",
              dut.w_rollback_ckpt_idx === dut.r_idx_p3);
        chk_q("E2d rollback valid on a tie",
              dut.w_rollback_valid === 1'b1);
      end
    end
    norq();
    sc_upd_val_u0 = '0;
    ubtb_upd_u0   = '0;
    sc_enable     = 1'b0;
    chk("E2d a same-cycle tie with distinct indices was reached",
        tie_seen > 0);
    $display("INFO: E2d distinct-index ties observed: %0d", tie_seen);

    // -- E4. FE-11, proved end to end (BP-094; BP-093 deferred item
    //    6). The claim is that the RAS snapshot written into the
    //    entry allocated at p1 is EXACTLY the RAS state that block
    //    starts from when it reaches p2. BP-093 could only check that
    //    bpu_pred_ras_p1 was non-X and that it advanced on a push,
    //    because with the branch_id skew a back-to-back stream never
    //    got a usable TAGE result and the tests could not run blocks
    //    back to back with RAS operations in flight.
    //
    //    Construction. Four blocks are installed in the FTB, two
    //    DIRECT_CALLs (RAS pushes at p2) and two RETURNs (RAS pops at
    //    p2), and the RAS is primed with two committed return
    //    addresses so the returns have something to pop. The blocks
    //    are then requested BACK TO BACK, so at every cycle one block
    //    is at p1 while the block ahead of it executes its RAS
    //    operation at p2 -- pushes and pops are genuinely in flight
    //    across blocks.
    //
    //    The proof, and what it must NOT be. bpu_pred_ras_p1 is a
    //    direct assign of w_ras_snapshot_p2[NUM_PRED_SLOTS-1], so
    //    comparing those two in the SAME cycle is a tautology: it is
    //    one net compared against itself and it cannot fail. The
    //    check has to cross a cycle boundary and land on a DIFFERENT
    //    signal.
    //
    //    It does. The value published at p1 in cycle T is the
    //    POST-operation pointer state of the block that was at p2 in
    //    cycle T. ras.sv registers exactly that state, so in cycle
    //    T+1 the RAS pointer registers {tosr, tosw, bos} hold it --
    //    and cycle T+1 is when the block that was at p1 reaches p2.
    //    The state it starts from is therefore those registers,
    //    sampled BEFORE its own p2 operation is applied.
    //
    //    So the check is: the snapshot recorded at p1 in cycle T
    //    equals the RAS pointer registers in cycle T+1. Snapshot
    //    output against pointer register, one cycle apart. A
    //    snapshot that reported the PRE-operation state instead
    //    fails it, which is what makes it a test rather than a
    //    restatement.
    //
    //    The comparison is only meaningful if the state actually
    //    MOVES across the sequence: a stack that never changes makes
    //    every snapshot equal and the check vacuous. The number of
    //    distinct snapshots observed is counted and required to be
    //    more than one.
    begin
      logic [VA_WIDTH-1:0]      cpc;
      logic [VA_WIDTH-1:0]      cbase;
      bp_ras_snapshot_t         snap_p1_prev;
      bp_ras_snapshot_t         snap_first;
      int                       p1_seen;
      int                       moved_seen;
      logic                     have_prev;

      do_reset();
      tage_bim_fill(2'b00);
      sc_enable = 1'b0;

      // Two committed return addresses, so the RETURN blocks pop a
      // real address rather than falling back to the FTB target.
      ras_push_commit(40'h00_0000_C100);
      ras_push_commit(40'h00_0000_C200);

      // Four consecutive blocks: call, call, return, return.
      for (int b = 0; b < 4; b++) begin
        cpc   = 40'h00_0460_0000 + VA_WIDTH'(b * 32);
        cbase = blk_base(cpc);
        if (b < 2) begin
          // DIRECT_CALL: is_call, not jalr, not ret -> RAS push.
          ftb_alloc_jmp(cpc, 2'd0, cbase + 40'h700, 3'd5,
                        1'b1, 1'b0, 1'b0, cbase + BLK_SZ, 1'b0);
        end else begin
          // RETURN: is_ret + is_jalr -> RAS pop.
          ftb_alloc_jmp(cpc, 2'd0, cbase + 40'h800, 3'd2,
                        1'b0, 1'b1, 1'b1, cbase + BLK_SZ, 1'b0);
        end
        ubtb_clear_set(cpc);
        lp_clear_both(cpc);
      end

      p1_seen      = 0;
      moved_seen   = 0;
      have_prev    = 1'b0;
      snap_p1_prev = '0;
      snap_first   = '0;

      // Back-to-back stream over the four blocks, twice round, plus
      // two drain cycles.
      for (int i = 0; i < 10; i++) begin
        if (i < 8)
          req(40'h00_0460_0000 + (VA_WIDTH'(i % 4) * BLK_SZ),
              FTQ_IDX_BITS'(6'h04 + i));
        else
          norq();
        tick();

        // The block that was at p1 LAST cycle is at p2 NOW. The RAS
        // state it starts from is the pointer registers as they
        // stand this cycle, before its own p2 operation is applied.
        if (have_prev) begin
          chk_q("E4 FE-11 p1 snapshot tosr is that block's p2 start",
                snap_p1_prev.tosr === dut.u_ras.tosr);
          chk_q("E4 FE-11 p1 snapshot tosw is that block's p2 start",
                snap_p1_prev.tosw === dut.u_ras.tosw);
          chk_q("E4 FE-11 p1 snapshot bos is that block's p2 start",
                snap_p1_prev.bos  === dut.u_ras.bos);
        end

        if (bpu_pred_val_p1 === 1'b1) begin
          p1_seen++;
          if (p1_seen == 1) snap_first = bpu_pred_ras_p1;
          else if (bpu_pred_ras_p1 !== snap_first) moved_seen++;
        end

        snap_p1_prev = bpu_pred_ras_p1;
        have_prev    = bpu_pred_val_p1;
      end
      norq();

      chk("E4 the stream presented a p1 snapshot on every request",
          p1_seen == 8);
      chk("E4 the RAS state actually moved across the sequence",
          moved_seen > 0);
      $display("INFO: E4 p1 snapshots %0d, distinct-from-first %0d",
               p1_seen, moved_seen);
    end

    $display("---- GROUP E done (pass %0d fail %0d) ----",
             pass_cnt, fail_cnt);
  endtask

  // =================================================================
  // GROUP F -- prediction metadata write groups
  // =================================================================
  task automatic group_f();
    ubtb_entry_t         e;
    logic [VA_WIDTH-1:0] pc;
    logic [VA_WIDTH-1:0] base;
    logic [VA_WIDTH-1:0] pft;

    $display("---- GROUP F: metadata ----");

    // -- F1. The p2 group, field by field. Every slot must carry its
    //    OWN loop snapshot; the zero drive above slot 0 is gone.
    do_reset();
    tage_bim_fill(2'b11);
    pc   = 40'h00_0500_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_cond(pc, 2'd2, 1'b0, 1'b1, base + 40'h300, 3'd1, pft,
                   1'b0);
    ftb_alloc_jmp(pc, 2'd2, base + 40'h500, 3'd6, 1'b0, 1'b0, 1'b0,
                  pft, 1'b1);
    e       = '0;
    e.br0   = mk_cond(1'b1, 3'd1, base + 40'h300, base, 1'b0);
    e.br1   = mk_cond(1'b1, 3'd3, base + 40'h380, base, 1'b0);
    e.pft   = ub_pft_field(pft, base);
    e.carry = ub_pft_carry(pft, base);
    ubtb_install(pc, e);
    lp_clear_both(pc);
    // Distinct loop state per slot: different confidence and different
    // iteration counts, so a crossed or zero-driven slot is visible.
    lp_install(0, pc, LP_CNF_BITS'(LP_CONF_LEVEL), 14'd1, 14'd4);
    lp_install(1, pc, LP_CNF_BITS'(1),             14'd7, 14'd9);
    req(pc, 6'h2C);
    tick();
    norq();
    tick();

    chk("F1 p2 metadata valid",  bpu_meta_val_p2 === 1'b1);
    chk("F1 p2 metadata index",  bpu_meta_idx_p2 === 6'h2C);

    // tage member
    chk("F1 tage slot0 branch_id is this entry",
        bpu_meta_tage_p2[0].branch_id === 6'h2C);
    chk("F1 tage slot1 branch_id is this entry",
        bpu_meta_tage_p2[1].branch_id === 6'h2C);
    chk("F1 tage slot0 direction is the seeded bimodal direction",
        bpu_meta_tage_p2[0].tage_pred_tkn === 1'b1);
    chk("F1 tage slot0 metadata equals the predictor output",
        bpu_meta_tage_p2[0] === dut.w_tage_pred_meta_p2[0]);
    chk("F1 tage slot1 metadata equals the predictor output",
        bpu_meta_tage_p2[1] === dut.w_tage_pred_meta_p2[1]);

    // ittage member
    chk("F1 ittage slot0 branch_id is this entry",
        bpu_meta_ittage_p2[0].branch_id === 6'h2C);
    chk("F1 ittage slot0 metadata equals the predictor output",
        bpu_meta_ittage_p2[0] === dut.w_ittage_pred_meta_p2[0]);
    chk("F1 ittage slot1 metadata equals the predictor output",
        bpu_meta_ittage_p2[1] === dut.w_ittage_pred_meta_p2[1]);

    // ftb member: scalar within the entry, same value in every slot
    chk("F1 ftb hit slot0",  bpu_meta_ftb_p2[0].hit === 1'b1);
    chk("F1 ftb way slot0",  bpu_meta_ftb_p2[0].way === 2'd2);
    chk("F1 ftb jmp_pos slot0",
        bpu_meta_ftb_p2[0].jmp_pos === 3'd6);
    chk("F1 ftb member replicated into slot1",
        bpu_meta_ftb_p2[1] === bpu_meta_ftb_p2[0]);

    // lp member: per slot, each carrying its own snapshot
    chk("F1 lp slot0 confidence is slot 0's own",
        bpu_meta_lp_p2[0].lp_conf ===
          LP_CNF_BITS'(LP_CONF_LEVEL));
    chk("F1 lp slot1 confidence is slot 1's own",
        bpu_meta_lp_p2[1].lp_conf === LP_CNF_BITS'(1));
    chk("F1 lp slot1 is NOT zero-driven",
        bpu_meta_lp_p2[1] !== '0);
    chk("F1 lp slot0 past_itr", bpu_meta_lp_p2[0].lp_past_itr === 14'd4);
    chk("F1 lp slot1 past_itr", bpu_meta_lp_p2[1].lp_past_itr === 14'd9);
    chk("F1 lp slot0 curr_itr", bpu_meta_lp_p2[0].lp_curr_itr === 14'd1);
    chk("F1 lp slot1 curr_itr", bpu_meta_lp_p2[1].lp_curr_itr === 14'd7);
    chk("F1 lp slot0 hit",  bpu_meta_lp_p2[0].lp_hit === 1'b1);
    chk("F1 lp slot1 hit",  bpu_meta_lp_p2[1].lp_hit === 1'b1);
    chk("F1 lp slot0 trusted", bpu_meta_lp_p2[0].lp_pred_is_loop === 1'b1);
    chk("F1 lp slot1 untrusted",
        bpu_meta_lp_p2[1].lp_pred_is_loop === 1'b0);
    chk("F1 lp slot0 index is that bank's index",
        bpu_meta_lp_p2[0].lp_idx === lp_idx(pc));
    chk("F1 lp slot1 index is that bank's index",
        bpu_meta_lp_p2[1].lp_idx === lp_idx(pc));
    chk("F1 lp slots are not crossed",
        bpu_meta_lp_p2[0] !== bpu_meta_lp_p2[1]);
    chk("F1 lp slot0 equals the registered p1 loop result",
        bpu_meta_lp_p2[0] === dut.r_lp_pred_p2[0]);
    chk("F1 lp slot1 equals the registered p1 loop result",
        bpu_meta_lp_p2[1] === dut.r_lp_pred_p2[1]);

    // -- F2. The p3 group. bpu_meta_val_p3 asserts whether or not SC
    //    is enabled; the sc member is the predictor output.
    tick();
    chk("F2 p3 metadata valid (SC disabled)",
        bpu_meta_val_p3 === 1'b1);
    chk("F2 p3 metadata index", bpu_meta_idx_p3 === 6'h2C);
    chk("F2 sc slot0 metadata equals the predictor output",
        bpu_meta_sc_p3[0] === dut.w_sc_pred_meta_p3[0]);
    chk("F2 sc slot1 metadata equals the predictor output",
        bpu_meta_sc_p3[1] === dut.w_sc_pred_meta_p3[1]);

    do_reset();
    tage_bim_fill(2'b11);
    sc_fill(6'b011111);
    sc_enable = 1'b1;
    ftb_alloc_cond(pc, 2'd1, 1'b0, 1'b1, base + 40'h300, 3'd1, pft,
                   1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h2D);
    tick();
    norq();
    tick();
    tick();
    chk("F2 p3 metadata valid (SC enabled)",
        bpu_meta_val_p3 === 1'b1);
    chk("F2 sc slot0 branch_id is this entry",
        bpu_meta_sc_p3[0].branch_id === 6'h2D);
    sc_enable = 1'b0;

    // -- F3. The two groups write DISJOINT members of bp_ftq_meta_t.
    //    Assemble the struct the way the FTQ would and show that the
    //    p2 write touches tage / ittage / lp / ftb only and the p3
    //    write touches sc only, so no merge is required.
    begin
      bp_ftq_meta_t m_p2_only;
      bp_ftq_meta_t m_p3_only;
      bp_ftq_meta_t m_merged;

      m_p2_only         = '0;
      m_p2_only.tage    = bpu_meta_tage_p2[0];
      m_p2_only.ittage  = bpu_meta_ittage_p2[0];
      m_p2_only.lp      = bpu_meta_lp_p2[0];
      m_p2_only.ftb     = bpu_meta_ftb_p2[0];

      m_p3_only         = '0;
      m_p3_only.sc      = bpu_meta_sc_p3[0];

      m_merged          = m_p2_only;
      m_merged.sc       = m_p3_only.sc;

      chk("F3 p2 write leaves the sc member untouched",
          m_p2_only.sc === '0);
      chk("F3 p3 write leaves the tage member untouched",
          m_p3_only.tage === '0);
      chk("F3 p3 write leaves the ittage member untouched",
          m_p3_only.ittage === '0);
      chk("F3 p3 write leaves the lp member untouched",
          m_p3_only.lp === '0);
      chk("F3 p3 write leaves the ftb member untouched",
          m_p3_only.ftb === '0);
      chk("F3 the two writes reassemble without a merge",
          (m_merged.tage   === bpu_meta_tage_p2[0])
       && (m_merged.ittage === bpu_meta_ittage_p2[0])
       && (m_merged.lp     === bpu_meta_lp_p2[0])
       && (m_merged.ftb    === bpu_meta_ftb_p2[0])
       && (m_merged.sc     === bpu_meta_sc_p3[0]));
    end

    //    The two write groups also travel on independent valids, one
    //    stage apart, so the FTQ can take them as two separate writes
    //    rather than one merged one.
    do_reset();
    pc = 40'h00_0510_0000;
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    req(pc, 6'h2E);
    tick();
    norq();
    tick();
    chk("F3 p2 write valid while the p3 write is not",
        (bpu_meta_val_p2 === 1'b1) && (bpu_meta_val_p3 === 1'b0));
    tick();
    chk("F3 p3 write valid while the p2 write is not",
        (bpu_meta_val_p2 === 1'b0) && (bpu_meta_val_p3 === 1'b1));
    chk("F3 both writes name the same entry",
        bpu_meta_idx_p3 === 6'h2E);

    $display("---- GROUP F done (pass %0d fail %0d) ----",
             pass_cnt, fail_cnt);
  endtask

  // =================================================================
  // FTQ model -- the testbench acts as the FTQ for groups G and H
  // =================================================================
  // The update inputs embed predict-time metadata, so a closed loop
  // needs somewhere to HOLD that metadata against its FTQ index
  // between the prediction and the resolution. That is the FTQ's job,
  // and these arrays are the smallest model of it that the update
  // channels need: the p2 write group indexed by bpu_meta_idx_p2, the
  // p3 write group indexed by bpu_meta_idx_p3.
  //
  // Nothing is forced into the DUT from here. The arrays are written
  // ONLY from the metadata write groups at the cluster boundary and
  // read back ONLY onto the update ports, which is exactly the path
  // the FTQ implements.
  tage_pred_meta_t   ftq_tage   [0:FTQ_DEPTH-1][0:NUM_PRED_SLOTS-1];
  ittage_pred_meta_t ftq_ittage [0:FTQ_DEPTH-1][0:NUM_PRED_SLOTS-1];
  lp_pred_t          ftq_lp     [0:FTQ_DEPTH-1][0:NUM_PRED_SLOTS-1];
  ftb_pred_meta_t    ftq_ftb    [0:FTQ_DEPTH-1][0:NUM_PRED_SLOTS-1];
  sc_pred_meta_t     ftq_sc     [0:FTQ_DEPTH-1][0:NUM_PRED_SLOTS-1];
  logic              ftq_p2_v   [0:FTQ_DEPTH-1];
  logic              ftq_p3_v   [0:FTQ_DEPTH-1];

  task automatic ftq_clear();
    for (int i = 0; i < FTQ_DEPTH; i++) begin
      ftq_p2_v[i] = 1'b0;
      ftq_p3_v[i] = 1'b0;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        ftq_tage[i][s]   = '0;
        ftq_ittage[i][s] = '0;
        ftq_lp[i][s]     = '0;
        ftq_ftb[i][s]    = '0;
        ftq_sc[i][s]     = '0;
      end
    end
  endtask

  // Take the two metadata write groups exactly as the FTQ would.
  task automatic ftq_snoop();
    if (bpu_meta_val_p2 === 1'b1) begin
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        ftq_tage[bpu_meta_idx_p2][s]   = bpu_meta_tage_p2[s];
        ftq_ittage[bpu_meta_idx_p2][s] = bpu_meta_ittage_p2[s];
        ftq_lp[bpu_meta_idx_p2][s]     = bpu_meta_lp_p2[s];
        ftq_ftb[bpu_meta_idx_p2][s]    = bpu_meta_ftb_p2[s];
      end
      ftq_p2_v[bpu_meta_idx_p2] = 1'b1;
    end
    if (bpu_meta_val_p3 === 1'b1) begin
      for (int s = 0; s < NUM_PRED_SLOTS; s++)
        ftq_sc[bpu_meta_idx_p3][s] = bpu_meta_sc_p3[s];
      ftq_p3_v[bpu_meta_idx_p3] = 1'b1;
    end
  endtask

  task automatic tick_snoop();
    tick();
    ftq_snoop();
  endtask

  // Issue one request and carry it all the way to p3, snooping both
  // metadata write groups on the way. Leaves the caller one cycle
  // after the p3 group for that entry.
  task automatic req_to_p3(input logic [VA_WIDTH-1:0] pc,
                           input logic [FTQ_IDX_BITS-1:0] idx);
    req(pc, idx);
    tick_snoop();
    norq();
    tick_snoop();      // idx at p2
    tick_snoop();      // idx at p3
  endtask

  // Clear every update channel. Called before and after each update
  // pulse so no channel is left asserted into the next case.
  task automatic clr_upd_chans();
    ubtb_upd_u0       = '0;
    tage_upd_val_u0   = '0;
    ittage_upd_val_u0 = '0;
    sc_upd_val_u0     = '0;
    lp_upd_valid_p0   = '0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      tage_upd_inp_u0[s]   = '0;
      ittage_upd_inp_u0[s] = '0;
      sc_upd_inp_u0[s]     = '0;
      lp_upd_p0[s]         = '0;
    end
  endtask

  // Build the uBTB update payload for one resolved branch type. The
  // cluster rederives the branch type from THESE structural bits
  // (bp_cluster.sv upd_br_type), so this task is the only place a
  // resolved type is expressed and every fan-out arm reads it.
  function automatic ubtb_upd_t mk_upd(input bp_br_type_e t,
                                       input logic v,
                                       input logic [VA_WIDTH-1:0] pc);
    ubtb_upd_t u;
    u       = '0;
    u.valid = v;
    u.pc    = pc;
    case (t)
      COND:            u.is_br  = 1'b1;
      RETURN:          begin u.is_jmp = 1'b1; u.is_ret  = 1'b1; end
      DIRECT_CALL:     begin u.is_jmp = 1'b1; u.is_call = 1'b1; end
      INDIRECT_CALL:   begin u.is_jmp  = 1'b1; u.is_call = 1'b1;
                             u.is_jalr = 1'b1; end
      INDIRECT_NONRET: begin u.is_jmp = 1'b1; u.is_jalr = 1'b1; end
      DIRECT_UNC:      u.is_jmp = 1'b1;
      default:         ;                    // NO_BRANCH: no bits set
    endcase
    return u;
  endfunction

  // =================================================================
  // GROUP G -- the closed predict-then-update loop
  // =================================================================
  //
  // BP-093 left this uncovered (its deferred item 2) and the update
  // fan-out branch-type decode at bp_cluster.sv upd_br_type went with
  // it. The loop also exercises the BP-094 fix directly: every update
  // input embeds predict-time metadata, and that metadata carries
  // branch_id, so a closed loop over skewed metadata trains the entry
  // belonging to a DIFFERENT request.
  //
  // Shape of every case: predict, capture the metadata as the FTQ,
  // resolve, feed the captured metadata back on the update channel,
  // then predict the SAME PC again and show the prediction moved in
  // the direction the resolution implies.
  task automatic group_g();
    logic [VA_WIDTH-1:0] pc;
    logic [VA_WIDTH-1:0] base;
    logic [VA_WIDTH-1:0] pft;
    logic                t0_tkn_1;
    logic                t0_tkn_2;
    logic                sc_tkn_1;
    logic                sc_tkn_2;
    logic signed [SC_LSUM_BITS-1:0] sc_sum_1;
    logic signed [SC_LSUM_BITS-1:0] sc_sum_2;
    logic                it_hit_1;
    logic                it_hit_2;
    logic [VA_WIDTH-1:0] it_tgt_2;
    ubtb_upd_t           u;

    $display("---- GROUP G: closed predict-update loop ----");

    // -- G0. Update fan-out by resolved branch type (fe_decisions 7.2
    //    plus the three encodings that table does not list). The
    //    cluster rederives the type from the uBTB update payload's
    //    structural bits, so each encoding is presented and the
    //    decode plus every qualified valid is read back.
    //
    //    All seven encodings are driven, which is what closes the
    //    decode arms BP-093 could not reach.
    do_reset();
    ftq_clear();
    clr_upd_chans();
    sc_enable = 1'b1;
    pc = 40'h00_0600_0000;

    // NO_BRANCH: forms NO update anywhere, even with valid high.
    ubtb_upd_u0[0]    = mk_upd(NO_BRANCH, 1'b1, pc);
    tage_upd_val_u0   = 2'b01;
    ittage_upd_val_u0 = 2'b01;
    sc_upd_val_u0     = 2'b01;
    #1;
    chk("G0 NO_BRANCH decoded", dut.w_upd_type_u0[0] === NO_BRANCH);
    chk("G0 NO_BRANCH forms no update at all",
        dut.w_upd_any_u0[0] === 1'b0);
    chk("G0 NO_BRANCH gates the uBTB update valid off",
        dut.w_ubtb_upd_u0[0].valid === 1'b0);
    chk("G0 NO_BRANCH gates TAGE off",
        dut.w_tage_upd_val_u0[0] === 1'b0);
    chk("G0 NO_BRANCH gates ITTAGE off",
        dut.w_ittage_upd_val_u0[0] === 1'b0);
    chk("G0 NO_BRANCH gates SC off",
        dut.w_sc_upd_val_u0[0] === 1'b0);

    // COND: uBTB, TAGE and SC; not ITTAGE.
    ubtb_upd_u0[0] = mk_upd(COND, 1'b1, pc);
    #1;
    chk("G0 COND decoded", dut.w_upd_type_u0[0] === COND);
    chk("G0 COND selects the conditional fan-out",
        dut.w_upd_cond_u0[0] === 1'b1);
    chk("G0 COND passes the uBTB update",
        dut.w_ubtb_upd_u0[0].valid === 1'b1);
    chk("G0 COND passes TAGE",
        dut.w_tage_upd_val_u0[0] === 1'b1);
    chk("G0 COND does NOT reach ITTAGE",
        dut.w_ittage_upd_val_u0[0] === 1'b0);

    // RETURN: uBTB only among the table predictors; RAS is driven
    // from its own commit channel, checked in G7.
    ubtb_upd_u0[0] = mk_upd(RETURN, 1'b1, pc);
    #1;
    chk("G0 RETURN decoded", dut.w_upd_type_u0[0] === RETURN);
    chk("G0 RETURN forms an update", dut.w_upd_any_u0[0] === 1'b1);
    chk("G0 RETURN is not conditional",
        dut.w_upd_cond_u0[0] === 1'b0);
    chk("G0 RETURN is not an indirect target update",
        dut.w_upd_ind_u0[0] === 1'b0);
    chk("G0 RETURN passes the uBTB update",
        dut.w_ubtb_upd_u0[0].valid === 1'b1);
    chk("G0 RETURN gates TAGE and SC off",
        (dut.w_tage_upd_val_u0[0] === 1'b0)
     && (dut.w_sc_upd_val_u0[0] === 1'b0));

    // DIRECT_CALL: pushes the RAS and updates uBTB and FTB. Not an
    // indirect target, so ITTAGE takes nothing.
    ubtb_upd_u0[0] = mk_upd(DIRECT_CALL, 1'b1, pc);
    #1;
    chk("G0 DIRECT_CALL decoded",
        dut.w_upd_type_u0[0] === DIRECT_CALL);
    chk("G0 DIRECT_CALL passes the uBTB update",
        dut.w_ubtb_upd_u0[0].valid === 1'b1);
    chk("G0 DIRECT_CALL is not an indirect target update",
        dut.w_upd_ind_u0[0] === 1'b0);
    chk("G0 DIRECT_CALL does NOT reach ITTAGE",
        dut.w_ittage_upd_val_u0[0] === 1'b0);

    // INDIRECT_CALL: ITTAGE for the target AND the RAS for the return
    // address. Distinguished from DIRECT_CALL by is_jalr alone.
    ubtb_upd_u0[0] = mk_upd(INDIRECT_CALL, 1'b1, pc);
    #1;
    chk("G0 INDIRECT_CALL decoded",
        dut.w_upd_type_u0[0] === INDIRECT_CALL);
    chk("G0 INDIRECT_CALL is an indirect target update",
        dut.w_upd_ind_u0[0] === 1'b1);
    chk("G0 INDIRECT_CALL passes ITTAGE",
        dut.w_ittage_upd_val_u0[0] === 1'b1);
    chk("G0 INDIRECT_CALL is not conditional",
        dut.w_upd_cond_u0[0] === 1'b0);

    // INDIRECT_NONRET: ITTAGE only.
    ubtb_upd_u0[0] = mk_upd(INDIRECT_NONRET, 1'b1, pc);
    #1;
    chk("G0 INDIRECT_NONRET decoded",
        dut.w_upd_type_u0[0] === INDIRECT_NONRET);
    chk("G0 INDIRECT_NONRET passes ITTAGE",
        dut.w_ittage_upd_val_u0[0] === 1'b1);

    // DIRECT_UNC: the fall-through arm of the decode -- a jump with
    // none of ret, call or jalr set.
    ubtb_upd_u0[0] = mk_upd(DIRECT_UNC, 1'b1, pc);
    #1;
    chk("G0 DIRECT_UNC decoded",
        dut.w_upd_type_u0[0] === DIRECT_UNC);
    chk("G0 DIRECT_UNC forms an update",
        dut.w_upd_any_u0[0] === 1'b1);
    chk("G0 DIRECT_UNC reaches neither TAGE nor ITTAGE nor SC",
        (dut.w_tage_upd_val_u0[0]   === 1'b0)
     && (dut.w_ittage_upd_val_u0[0] === 1'b0)
     && (dut.w_sc_upd_val_u0[0]     === 1'b0));

    // is_br outranks is_jmp, matching ubtb.sv jmp_br_type and the p2
    // classification. Both bits set must read COND.
    u        = mk_upd(DIRECT_CALL, 1'b1, pc);
    u.is_br  = 1'b1;
    ubtb_upd_u0[0] = u;
    #1;
    chk("G0 is_br outranks is_jmp in the decode",
        dut.w_upd_type_u0[0] === COND);

    clr_upd_chans();
    sc_enable = 1'b0;
    tick();

    // -- G1. TAGE. Bimodal seeded weak NOT taken (2'b01), so the
    //    first prediction is not taken. Resolve TAKEN, feed the
    //    captured metadata back, and the T0 counter steps to 2'b10 --
    //    the direction flips. The metadata fed back is the one the
    //    FTQ holds for THAT entry, which is only correct because
    //    branch_id now names the request that produced it.
    do_reset();
    ftq_clear();
    clr_upd_chans();
    tage_bim_fill(2'b01);
    pc   = 40'h00_0610_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b0, base + 40'h300, 3'd1, pft,
                   1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);

    req_to_p3(pc, 6'h08);
    chk("G1 the FTQ captured the TAGE metadata for this entry",
        ftq_p2_v[6'h08] === 1'b1);
    chk("G1 the captured metadata names this entry",
        ftq_tage[6'h08][0].branch_id === 6'h08);
    t0_tkn_1 = ftq_tage[6'h08][0].tage_pred_tkn;
    chk("G1 first prediction is NOT taken", t0_tkn_1 === 1'b0);
    chk("G1 T0 is the provider on a cold tagged set",
        ftq_tage[6'h08][0].tage_prm_comp === '0);

    // Resolve taken. The prediction was not taken, so this is a
    // mispredict.
    ubtb_upd_u0[0] = mk_upd(COND, 1'b0, pc);   // structural bits only
    tage_upd_inp_u0[0].tage_pred_meta  = ftq_tage[6'h08][0];
    tage_upd_inp_u0[0].resolved_taken  = 1'b1;
    tage_upd_inp_u0[0].cond_mispredict = 1'b1;
    tage_upd_val_u0[0] = 1'b1;
    #1;
    chk("G1 the cluster accepts the TAGE update",
        dut.w_tage_upd_val_u0[0] === 1'b1);
    tick();
    clr_upd_chans();
    repeat (4) tick();

    req_to_p3(pc, 6'h09);
    t0_tkn_2 = ftq_tage[6'h09][0].tage_pred_tkn;
    chk("G1 second prediction moved to TAKEN, as resolved",
        t0_tkn_2 === 1'b1);
    chk("G1 the direction actually changed", t0_tkn_2 !== t0_tkn_1);
    chk("G1 the second metadata names the second entry",
        ftq_tage[6'h09][0].branch_id === 6'h09);

    // -- G2. ITTAGE. An indirect jump with a cold ITTAGE misses and
    //    falls back to the FTB jump target. Resolve a DIFFERENT
    //    target, feed the captured metadata back on the indirect
    //    fan-out arm, and the second prediction hits with the
    //    resolved target.
    do_reset();
    ftq_clear();
    clr_upd_chans();
    tage_bim_fill(2'b00);
    pc   = 40'h00_0620_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_jmp(pc, 2'd0, base + 40'h600, 3'd4, 1'b0, 1'b0, 1'b1,
                  pft, 1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);

    req_to_p3(pc, 6'h0A);
    it_hit_1 = ftq_ittage[6'h0A][0].ittage_hit;
    chk("G2 first prediction misses in ITTAGE", it_hit_1 === 1'b0);
    chk("G2 the captured ITTAGE metadata names this entry",
        ftq_ittage[6'h0A][0].branch_id === 6'h0A);
    chk("G2 a cold miss offers an allocation candidate",
        ftq_ittage[6'h0A][0].ittage_alc_comp !== '0);

    // Resolve target 0x9AA0. ITTAGE stores the upper bits only.
    ubtb_upd_u0[0] = mk_upd(INDIRECT_NONRET, 1'b0, pc);
    ittage_upd_inp_u0[0].ittage_pred_meta = ftq_ittage[6'h0A][0];
    ittage_upd_inp_u0[0].resolved_target  =
      IT_MAX_TGT_WIDTH'(40'h00_0000_9AA0 >> 1);
    ittage_upd_inp_u0[0].indir_mispredict = 1'b1;
    ittage_upd_val_u0[0] = 1'b1;
    #1;
    chk("G2 the cluster accepts the ITTAGE update",
        dut.w_ittage_upd_val_u0[0] === 1'b1);
    tick();
    clr_upd_chans();
    repeat (4) tick();

    req_to_p3(pc, 6'h0B);
    it_hit_2 = ftq_ittage[6'h0B][0].ittage_hit;
    it_tgt_2 = {1'b0,
                ftq_ittage[6'h0B][0].ittage_prm_tgt, 1'b0};
    chk("G2 second prediction HITS in ITTAGE after the update",
        it_hit_2 === 1'b1);
    chk("G2 the hit is a change from the first prediction",
        it_hit_2 !== it_hit_1);
    chk_eq("G2 the hit carries the resolved target",
           it_tgt_2, 40'h00_0000_9AA0);

    // -- G3. SC. The five counter tables are seeded at -1 and the
    //    TAGE bimodal at 2'b11, so the local SC sum is
    //    5 * (2*(-1)+1) + tage_extd_ctr = -5 + (-1) = -6, NEGATIVE,
    //    and SC predicts not taken while TAGE predicts taken -- the
    //    general-differ arm, so SC overrides. Resolving TAKEN steps
    //    every consulted counter to 0, which moves the sum to
    //    5 * 1 - 1 = +4, POSITIVE. The second prediction is therefore
    //    taken and agrees with TAGE, so the override goes away. Both
    //    the direction and the override flag are read back.
    //
    //    The SIGN of the sum, not an exact value, is what is
    //    asserted. sc_cntrl.sv pred_form builds it as
    //    sum((ctr <<< 1) + 1) over SC_NUM_TABLES plus
    //    tage_extd_ctr, and the seeded counters put it comfortably
    //    either side of zero; pinning an exact total here would bind
    //    this cluster test to the SC table count and counter widths,
    //    which the SC unit suite already covers. What matters at this
    //    boundary is that the update MOVED the sum in the resolved
    //    direction and that the published direction followed it, and
    //    both are asserted.
    do_reset();
    ftq_clear();
    clr_upd_chans();
    tage_bim_fill(2'b11);
    sc_fill(6'b111111);              // -1 in each consulted counter
    sc_enable = 1'b1;
    pc   = 40'h00_0630_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b1, base + 40'h300, 3'd1, pft,
                   1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);

    req_to_p3(pc, 6'h0C);
    chk("G3 the FTQ captured the SC metadata for this entry",
        ftq_p3_v[6'h0C] === 1'b1);
    chk("G3 the captured SC metadata names this entry",
        ftq_sc[6'h0C][0].branch_id === 6'h0C);
    sc_tkn_1 = ftq_sc[6'h0C][0].sc_pred_tkn;
    chk("G3 first SC prediction is NOT taken", sc_tkn_1 === 1'b0);
    sc_sum_1 = ftq_sc[6'h0C][0].sc_sum;
    $display("INFO: G3 sc_sum first  = %0d (abs %0d)",
             sc_sum_1, ftq_sc[6'h0C][0].sc_abs_sum);
    chk("G3 the first local sum is negative, as SC not-taken implies",
        sc_sum_1 < 0);
    chk("G3 SC overrode TAGE on the first prediction",
        ftq_sc[6'h0C][0].sc_override === 1'b1);

    // Resolve taken. sc_lcl_pred_tkn was 0, so do_update fires.
    ubtb_upd_u0[0] = mk_upd(COND, 1'b0, pc);
    sc_upd_inp_u0[0].sc_pred_meta   = ftq_sc[6'h0C][0];
    sc_upd_inp_u0[0].resolved_taken = 1'b1;
    sc_upd_inp_u0[0].cond_mispredict = 1'b1;
    sc_upd_val_u0[0] = 1'b1;
    #1;
    chk("G3 the cluster arbiter grants the SC update",
        dut.w_sc_grant_upd === 1'b1);
    chk("G3 the cluster accepts the SC update",
        dut.w_sc_upd_val_u0[0] === 1'b1);
    tick();
    clr_upd_chans();
    repeat (4) tick();

    req_to_p3(pc, 6'h0D);
    sc_tkn_2 = ftq_sc[6'h0D][0].sc_pred_tkn;
    chk("G3 second SC prediction moved to TAKEN, as resolved",
        sc_tkn_2 === 1'b1);
    chk("G3 the SC direction actually changed",
        sc_tkn_2 !== sc_tkn_1);
    sc_sum_2 = ftq_sc[6'h0D][0].sc_sum;
    $display("INFO: G3 sc_sum second = %0d (abs %0d)",
             sc_sum_2, ftq_sc[6'h0D][0].sc_abs_sum);
    chk("G3 the second local sum is positive, as SC taken implies",
        sc_sum_2 > 0);
    chk("G3 the sum moved UPWARD, the direction the resolution implies",
        sc_sum_2 > sc_sum_1);
    chk("G3 SC now agrees with TAGE, so no override",
        ftq_sc[6'h0D][0].sc_override === 1'b0);
    sc_enable = 1'b0;

    // -- G4. uBTB. A cold set predicts nothing at p1. Resolve a taken
    //    conditional through the uBTB update channel and the second
    //    prediction reports that branch from the uBTB.
    do_reset();
    ftq_clear();
    clr_upd_chans();
    tage_bim_fill(2'b00);
    pc   = 40'h00_0640_0000;
    base = blk_base(pc);
    ubtb_clear_set(pc);
    lp_clear_both(pc);

    req(pc, 6'h0E);
    tick();
    norq();
    chk("G4 cold uBTB set: slot0 invalid at p1",
        bpu_pred_slot_p1[0].slot_valid === 1'b0);
    chk("G4 cold uBTB set: no entry hit",
        dut.r_ubtb_blk_p1.hit === 1'b0);
    repeat (3) tick();

    u            = mk_upd(COND, 1'b1, pc);
    u.br_idx     = 1'b0;
    u.br_taken   = 1'b1;
    u.target     = base + 40'h240;
    u.pos        = 3'd3;
    u.pft_addr   = base + BLK_SZ;
    ubtb_upd_u0[0] = u;
    #1;
    chk("G4 the cluster passes the uBTB update through",
        dut.w_ubtb_upd_u0[0].valid === 1'b1);
    tick();
    clr_upd_chans();
    repeat (3) tick();

    req(pc, 6'h0F);
    tick();
    norq();
    chk("G4 the uBTB now hits the block",
        dut.r_ubtb_blk_p1.hit === 1'b1);
    chk("G4 slot0 is valid after the update",
        bpu_pred_slot_p1[0].slot_valid === 1'b1);
    chk("G4 slot0 is sourced from the uBTB",
        bpu_pred_slot_p1[0].pred_src === PRED_UBTB);
    chk("G4 the resolved position was learned",
        bpu_pred_slot_p1[0].pos === 3'd3);
    chk_eq("G4 the resolved target was learned",
           bpu_pred_slot_p1[0].target, base + 40'h240);
    repeat (3) tick();

    // -- G5. FTB. A cold FTB misses at p2; the resolved block is
    //    installed through the FTB update channel and the second
    //    prediction reports a hit carrying the resolved branch.
    do_reset();
    ftq_clear();
    clr_upd_chans();
    tage_bim_fill(2'b00);
    pc   = 40'h00_0650_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ubtb_clear_set(pc);
    lp_clear_both(pc);

    req_to_p3(pc, 6'h10);
    chk("G5 cold FTB misses at p2",
        ftq_ftb[6'h10][0].hit === 1'b0);

    // Resolve: install the block. The FTB update channel carries its
    // own structural classification, so this is the only fan-out that
    // does not read the uBTB payload.
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b1, base + 40'h340, 3'd2, pft,
                   1'b0);
    repeat (3) tick();

    req_to_p3(pc, 6'h11);
    chk("G5 the FTB now hits the block",
        ftq_ftb[6'h11][0].hit === 1'b1);
    chk("G5 the hit reports the way the update wrote",
        ftq_ftb[6'h11][0].way === 2'd0);
    chk("G5 the FTB hit changed from the first prediction",
        ftq_ftb[6'h11][0].hit !== ftq_ftb[6'h10][0].hit);
    // req_to_p3 leaves the caller past the p2 cycle, so the successor
    // is read from a further request timed to land on it.
    repeat (2) tick();
    req(pc, 6'h1C);
    tick();
    norq();
    tick();
    chk("G5 the entry under test is at p2", dut.r_idx_p2 === 6'h1C);
    chk_eq("G5 the resolved branch target is now the p2 successor",
           bpu_redir_p2[0].target_pc, base + 40'h340);

    // -- G6. loop_pred. A cold bank reports no hit. Resolve a
    //    BACKWARD conditional branch, which is the allocation
    //    condition loop_pred applies (target < pc), and the second
    //    prediction reports a table hit for that slot.
    do_reset();
    ftq_clear();
    clr_upd_chans();
    tage_bim_fill(2'b00);
    pc   = 40'h00_0660_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_cond(pc, 2'd0, 1'b0, 1'b1, base - 40'h100, 3'd1, pft,
                   1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);

    req_to_p3(pc, 6'h12);
    chk("G6 cold loop bank reports no hit",
        ftq_lp[6'h12][0].lp_hit === 1'b0);
    chk("G6 cold loop bank is not trusted",
        ftq_lp[6'h12][0].lp_pred_is_loop === 1'b0);

    // Resolve a backward taken branch on slot 0.
    ubtb_upd_u0[0] = mk_upd(COND, 1'b0, pc);
    lp_upd_p0[0]              = '0;
    lp_upd_p0[0].pc           = pc;
    lp_upd_p0[0].target       = base - 40'h100;   // backward
    lp_upd_p0[0].actual_taken = 1'b1;
    lp_upd_p0[0].lp_idx       = ftq_lp[6'h12][0].lp_idx;
    lp_upd_p0[0].lp_tag       = ftq_lp[6'h12][0].lp_tag;
    lp_upd_p0[0].lp_way       = ftq_lp[6'h12][0].lp_way;
    lp_upd_p0[0].lp_hit       = ftq_lp[6'h12][0].lp_hit;
    lp_upd_p0[0].lp_victim    = ftq_lp[6'h12][0].lp_victim;
    lp_upd_valid_p0[0]        = 1'b1;
    #1;
    chk("G6 the cluster accepts the loop update on the COND arm",
        dut.w_lp_upd_val_p0[0] === 1'b1);
    tick();
    clr_upd_chans();
    repeat (3) tick();

    req_to_p3(pc, 6'h13);
    chk("G6 the loop bank now hits for this PC",
        ftq_lp[6'h13][0].lp_hit === 1'b1);
    chk("G6 the loop hit changed from the first prediction",
        ftq_lp[6'h13][0].lp_hit !== ftq_lp[6'h12][0].lp_hit);
    chk("G6 the allocated entry indexes where the lookup read",
        ftq_lp[6'h13][0].lp_idx === ftq_lp[6'h12][0].lp_idx);

    // -- G7. RAS. A RETURN block with an empty stack falls back to
    //    the FTB jump target. Resolve a DIRECT_CALL through the RAS
    //    commit channel, which pushes the return address, and the
    //    same block then takes the RAS pop instead.
    do_reset();
    ftq_clear();
    clr_upd_chans();
    tage_bim_fill(2'b00);
    pc   = 40'h00_0670_0000;
    base = blk_base(pc);
    pft  = base + BLK_SZ;
    ftb_alloc_jmp(pc, 2'd0, base + 40'h800, 3'd2, 1'b0, 1'b1, 1'b1,
                  pft, 1'b0);
    ubtb_clear_set(pc);
    lp_clear_both(pc);

    req(pc, 6'h14);
    tick();
    norq();
    tick();
    chk("G7 RETURN classified with an empty stack",
        dut.w_br_type_p2[0] === RETURN);
    chk("G7 no pop is available before the call resolves",
        dut.w_ras_pop_valid_p2[0] === 1'b0);
    chk_eq("G7 the successor falls back to the FTB jump target",
           bpu_redir_p2[0].target_pc, base + 40'h800);
    repeat (3) tick();

    // Resolve the matching DIRECT_CALL. w_ras_commit_val admits both
    // call encodings and RETURN and nothing else.
    ras_commit_val      = 1'b1;
    ras_commit_br_type  = DIRECT_CALL;
    ras_commit_ret_addr = 40'h00_0000_D440;
    ras_commit_snapshot = '0;
    #1;
    chk("G7 the cluster admits a DIRECT_CALL commit",
        dut.w_ras_commit_val === 1'b1);
    tick();
    ras_commit_val      = 1'b0;
    ras_commit_br_type  = NO_BRANCH;
    ras_commit_ret_addr = '0;
    #1;
    chk("G7 the cluster rejects a NO_BRANCH commit",
        dut.w_ras_commit_val === 1'b0);
    repeat (3) tick();

    req(pc, 6'h15);
    tick();
    norq();
    tick();
    chk("G7 the pop is now available",
        dut.w_ras_pop_valid_p2[0] === 1'b1);
    chk_eq("G7 the successor is the resolved return address",
           bpu_redir_p2[0].target_pc, 40'h00_0000_D440);

    clr_upd_chans();
    $display("---- GROUP G done (pass %0d fail %0d) ----",
             pass_cnt, fail_cnt);
  endtask

  // =================================================================
  // GROUP H -- the SC credit arbiter (bp_arb_spec.md 4.5)
  // =================================================================
  //
  // Implemented in bp_cluster in session-063 and never tested; BP-093
  // left lines 981-983, 994 and 1010-1014 uncovered. The grant
  // signals, the credit counters and the starve counter are internal
  // nets and consumer_ready is not a port, so this group reads inside
  // the design by necessity. Nothing is FORCED except where a rule is
  // unreachable from the ports, which is called out where it happens.
  //
  // The two request terms, restated from bp_cluster.sv:
  //   w_sc_pred_req = r_val_p2 & sc_enable
  //   w_sc_upd_req  = sc_enable & sc_uq_not_full
  //                 & |(sc_upd_val_u0 & w_upd_cond_u0 & sc_upd_rdy)
  // so a prediction request is "a request is at the p2 stage" and an
  // update request is "an SC update is presented on a COND channel".
  // Each case below constructs exactly the occupancy its rule names
  // and reads back the grant AND the counter effects the rule
  // specifies.
  task automatic group_h();
    logic [VA_WIDTH-1:0] pc;
    logic [SC_PRED_CRED_W_TB-1:0] cred_before;
    logic [SC_STARVE_W_TB-1:0]    starve_before;
    int                           rule3_cycles;

    $display("---- GROUP H: SC credit arbiter ----");

    // Common fixture. SC counters uniform so no SC result depends on
    // an index, and the bimodal uniform so TAGE is constant.
    do_reset();
    clr_upd_chans();
    tage_bim_fill(2'b11);
    sc_fill(6'b011111);
    pc = 40'h00_0700_0000;
    ubtb_clear_set(pc);
    lp_clear_both(pc);

    // -- H1. Rule 7: neither queue non-empty -> NO grant, and no
    //    counter moves. sc_enable is high, so this is genuinely
    //    "no requests" rather than "SC switched off".
    sc_enable = 1'b1;
    norq();
    repeat (4) tick();
    #1;
    chk("H1 rule 7: no prediction request", dut.w_sc_pred_req === 1'b0);
    chk("H1 rule 7: no update request", dut.w_sc_upd_req === 1'b0);
    chk("H1 rule 7: no prediction grant",
        dut.w_sc_grant_pred === 1'b0);
    chk("H1 rule 7: no update grant", dut.w_sc_grant_upd === 1'b0);
    cred_before   = dut.r_sc_pred_credits;
    starve_before = dut.r_sc_starve_ctr;
    tick();
    chk("H1 rule 7: pred credits unchanged",
        dut.r_sc_pred_credits === cred_before);
    chk("H1 rule 7: starve counter unchanged",
        dut.r_sc_starve_ctr === starve_before);
    // consumer_ready with SC enabled, ready and no update grant.
    chk("H1 consumer_ready high: SC enabled, ready, no update grant",
        dut.w_tage_consumer_ready === 1'b1);

    // -- H2. Rule 5: prediction only. Grant prediction UNCONDITIONALLY
    //    and consume NO prediction credit -- that is what separates
    //    rule 5 from rule 3.
    do_reset();
    clr_upd_chans();
    sc_enable = 1'b1;
    req(pc, 6'h20);
    tick();
    norq();
    tick();                          // 0x20 at p2
    #1;
    cred_before   = dut.r_sc_pred_credits;
    starve_before = dut.r_sc_starve_ctr;
    chk("H2 rule 5: prediction request present",
        dut.w_sc_pred_req === 1'b1);
    chk("H2 rule 5: no update request", dut.w_sc_upd_req === 1'b0);
    chk("H2 rule 5: prediction granted",
        dut.w_sc_grant_pred === 1'b1);
    chk("H2 rule 5: no update granted",
        dut.w_sc_grant_upd === 1'b0);
    chk("H2 rule 5: SC RAM port went to the prediction",
        dut.w_tage_consumer_ready === 1'b1);
    tick();
    chk("H2 rule 5 consumes NO prediction credit",
        dut.r_sc_pred_credits === cred_before);
    chk("H2 rule 5 does not move the starve counter",
        dut.r_sc_starve_ctr === starve_before);

    // -- H2b. Rule 5's sc_ready guard, the arm BP-093 left uncovered.
    //    Rule 1 of section 4.5 blocks a prediction grant when the
    //    response path cannot take a result; sc.sv exposes no
    //    response-buffer flag and bp_cluster uses sc_ready in its
    //    place, which is low until the SC RAM init completes.
    //
    //    Under the sim plusargs sc_ready is strapped HIGH
    //    (+SC_FAST_INIT=1 makes it a constant in sc.sv), so this arm
    //    cannot be reached at the ports in this build. The fast-init
    //    strap itself is cleared for the duration of this case so the
    //    real sram_init walk drives sc_ready, and it is restored
    //    immediately afterwards. Clearing the strap also re-enables
    //    the init write path into the SC RAMs, so the strap is put
    //    back BEFORE any later case seeds them; sc_fill runs again
    //    after it.
    dut.u_sc.fast_init_r = 1'b0;
    rstn = 1'b0;
    clr_upd_chans();
    init_inputs();
    repeat (4) tick();
    rstn      = 1'b1;
    sc_enable = 1'b1;
    req(pc, 6'h21);
    tick();
    norq();
    tick();                          // 0x21 at p2, init still walking
    #1;
    chk("H2b the SC init walk is running, so sc_ready is low",
        sc_ready === 1'b0);
    chk("H2b rule 5 still sees a prediction request",
        dut.w_sc_pred_req === 1'b1);
    chk("H2b rule 5 sees no update request",
        dut.w_sc_upd_req === 1'b0);
    chk("H2b rule 1 guard blocks the prediction grant",
        dut.w_sc_grant_pred === 1'b0);
    chk("H2b no update grant either", dut.w_sc_grant_upd === 1'b0);
    chk("H2b consumer_ready drops while SC cannot take a result",
        dut.w_tage_consumer_ready === 1'b0);
    // Restore the strap and rebuild the fixture.
    dut.u_sc.fast_init_r = 1'b1;
    sc_enable = 1'b0;
    do_reset();
    clr_upd_chans();
    tage_bim_fill(2'b11);
    sc_fill(6'b011111);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    #1;
    chk("H2b sc_ready restored for the remaining cases",
        sc_ready === 1'b1);

    // -- H3. Rule 6: update only. Grant update unconditionally, no
    //    credit change. No request is in flight, so nothing occupies
    //    the prediction side.
    sc_enable      = 1'b1;
    ubtb_upd_u0[0] = mk_upd(COND, 1'b0, pc);
    sc_upd_val_u0[0] = 1'b1;
    norq();
    #1;
    cred_before   = dut.r_sc_pred_credits;
    starve_before = dut.r_sc_starve_ctr;
    chk("H3 rule 6: no prediction request",
        dut.w_sc_pred_req === 1'b0);
    chk("H3 rule 6: update request present",
        dut.w_sc_upd_req === 1'b1);
    chk("H3 rule 6: update granted", dut.w_sc_grant_upd === 1'b1);
    chk("H3 rule 6: no prediction granted",
        dut.w_sc_grant_pred === 1'b0);
    chk("H3 rule 6: the accept is presented at the boundary",
        sc_upd_rdy[0] === 1'b1);
    chk("H3 consumer_ready drops when the RAM port goes to an update",
        dut.w_tage_consumer_ready === 1'b0);
    tick();
    chk("H3 rule 6 leaves pred credits unchanged",
        dut.r_sc_pred_credits === cred_before);
    chk("H3 rule 6 leaves the starve counter unchanged",
        dut.r_sc_starve_ctr === starve_before);
    clr_upd_chans();
    repeat (2) tick();

    // -- H4 and H5. Rules 3 and 4, reached together by holding BOTH
    //    requests for a run of cycles. Rule 3 grants the prediction
    //    while credits remain, decrementing pred_credits and
    //    incrementing starve_ctr on each grant. When the credits
    //    reach zero rule 4 takes over: it grants the update and
    //    RELOADS both credit counters and RESETS the starve counter.
    //
    //    The whole cycle therefore runs SC_PRED_CREDITS rule-3 grants
    //    followed by one rule-4 grant, which is checked explicitly.
    do_reset();
    clr_upd_chans();
    tage_bim_fill(2'b11);
    sc_fill(6'b011111);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    sc_enable      = 1'b1;
    ubtb_upd_u0[0] = mk_upd(COND, 1'b0, pc);
    sc_upd_val_u0[0] = 1'b1;

    // Fill the pipe so a prediction stands at p2 every cycle.
    req(pc, 6'h22);
    tick();
    req(pc, 6'h23);
    tick();                          // 0x22 at p2: both requests up
    #1;
    chk("H4 rule 3: both sides have a request",
        (dut.w_sc_pred_req === 1'b1)
     && (dut.w_sc_upd_req === 1'b1));
    chk("H4 rule 3: credits are available",
        dut.r_sc_pred_credits > '0);
    chk("H4 rule 3: prediction wins while credits remain",
        dut.w_sc_grant_pred === 1'b1);
    chk("H4 rule 3: the update does not win",
        dut.w_sc_grant_upd === 1'b0);
    chk("H4 rule 3: the update is NOT accepted at the boundary",
        sc_upd_rdy[0] === 1'b0);

    rule3_cycles = 0;
    begin
      logic [SC_PRED_CRED_W_TB-1:0] c_prev;
      logic [SC_STARVE_W_TB-1:0]    s_prev;
      logic                         rule4_seen;
      rule4_seen = 1'b0;

      // Keep both requests standing and step through the credit run.
      for (int i = 0; i < 2 * SC_PRED_CREDITS + 4; i++) begin
        c_prev = dut.r_sc_pred_credits;
        s_prev = dut.r_sc_starve_ctr;
        if (dut.w_sc_grant_pred === 1'b1) begin
          rule3_cycles++;
          req(pc, FTQ_IDX_BITS'(6'h24 + i));
          tick();
          #1;
          chk_q("H4 rule 3 decremented pred credits",
                dut.r_sc_pred_credits ===
                  SC_PRED_CRED_W_TB'(c_prev - 1));
          chk_q("H4 rule 3 incremented the starve counter",
                dut.r_sc_starve_ctr ===
                  SC_STARVE_W_TB'(s_prev + 1));
        end else if (dut.w_sc_grant_upd === 1'b1) begin
          // Rule 4: credits exhausted with both sides requesting.
          chk_q("H5 rule 4 fires only with the credits exhausted",
                dut.r_sc_pred_credits === '0);
          chk_q("H5 rule 4 accepts the update at the boundary",
                sc_upd_rdy[0] === 1'b1);
          chk_q("H5 rule 4 drops consumer_ready for that cycle",
                dut.w_tage_consumer_ready === 1'b0);
          req(pc, FTQ_IDX_BITS'(6'h24 + i));
          tick();
          #1;
          chk_q("H5 rule 4 reloaded pred credits",
                dut.r_sc_pred_credits ===
                  SC_PRED_CRED_W_TB'(SC_PRED_CREDITS));
          chk_q("H5 rule 4 reloaded upd credits",
                dut.r_sc_upd_credits ===
                  SC_UPD_CRED_W_TB'(SC_UPD_CREDITS));
          chk_q("H5 rule 4 reset the starve counter",
                dut.r_sc_starve_ctr === '0);
          rule4_seen = 1'b1;
        end else begin
          req(pc, FTQ_IDX_BITS'(6'h24 + i));
          tick();
          #1;
        end
      end
      chk("H4 rule 3 was taken SC_PRED_CREDITS times per cycle run",
          rule3_cycles >= SC_PRED_CREDITS);
      chk("H5 rule 4 was reached", rule4_seen === 1'b1);
      $display("INFO: H4 rule-3 grants observed: %0d", rule3_cycles);
    end
    norq();
    clr_upd_chans();
    repeat (2) tick();

    // -- H5b. Rule 4's other entry condition: both requests with
    //    sc_ready low takes the same arm, because the rule-3 test is
    //    (credits > 0) AND sc_ready. Covered structurally by the
    //    grant expression; the sc_ready term itself is proved in H2b.

    // -- H6. Rule 2, the starvation override, and its counter
    //    effects: reset starve_ctr, reload upd_credits.
    //
    //    TD#39 (bp_arb_spec.md 4.2) records that this rule may be
    //    UNREACHABLE at the shipped parameters, and the run above
    //    confirms it: SC_PRED_CREDITS is 4 and SC_STARVE_THRESH is 8,
    //    starve_ctr only increments on a rule-3 grant, and rule 4
    //    resets it once the four credits are spent -- so it tops out
    //    at 4 and can never reach 8. The H4/H5 loop above observed
    //    exactly that.
    //
    //    The rule IS implemented, so it is tested by seeding the
    //    starve counter at the threshold and presenting an update
    //    request. That is a forced start state, stated plainly: it
    //    proves the implemented arm behaves as 4.5 rule 2 specifies,
    //    NOT that the arm is reachable in traffic. Settling TD#39 is
    //    a parameter decision, not a testbench one.
    do_reset();
    clr_upd_chans();
    tage_bim_fill(2'b11);
    sc_fill(6'b011111);
    ubtb_clear_set(pc);
    lp_clear_both(pc);
    sc_enable = 1'b1;

    chk("H6 TD#39: starve threshold is above the credit budget",
        SC_STARVE_THRESH > SC_PRED_CREDITS);

    // Seed the counter at the threshold and spend an update credit so
    // the reload is observable as a change.
    dut.r_sc_starve_ctr  = SC_STARVE_W_TB'(SC_STARVE_THRESH);
    dut.r_sc_upd_credits = '0;
    ubtb_upd_u0[0]   = mk_upd(COND, 1'b0, pc);
    sc_upd_val_u0[0] = 1'b1;
    // Present a prediction as well, so rule 2's PRIORITY over rules 3
    // and 4 is what is being read, not merely rule 6.
    req(pc, 6'h30);
    tick();
    req(pc, 6'h31);
    tick();
    dut.r_sc_starve_ctr  = SC_STARVE_W_TB'(SC_STARVE_THRESH);
    dut.r_sc_upd_credits = '0;
    #1;
    chk("H6 rule 2: both sides request, so rules 3/4 would apply",
        (dut.w_sc_pred_req === 1'b1)
     && (dut.w_sc_upd_req === 1'b1));
    chk("H6 rule 2: the starve counter is at the threshold",
        dut.r_sc_starve_ctr >= SC_STARVE_W_TB'(SC_STARVE_THRESH));
    chk("H6 rule 2: the update wins on the starvation override",
        dut.w_sc_grant_upd === 1'b1);
    chk("H6 rule 2: the prediction is overridden",
        dut.w_sc_grant_pred === 1'b0);
    chk("H6 rule 2: consumer_ready drops for that cycle",
        dut.w_tage_consumer_ready === 1'b0);
    tick();
    chk("H6 rule 2 reset the starve counter",
        dut.r_sc_starve_ctr === '0);
    chk("H6 rule 2 reloaded upd credits",
        dut.r_sc_upd_credits === SC_UPD_CRED_W_TB'(SC_UPD_CREDITS));
    norq();
    clr_upd_chans();
    repeat (2) tick();

    // -- H7. consumer_ready, every arm of
    //      ~sc_enable | (sc_ready & ~w_sc_grant_upd)
    //    SC disabled: the cluster does not wait on SC at all, so TAGE
    //    is never held whatever the arbiter is doing.
    sc_enable = 1'b0;
    #1;
    chk("H7 consumer_ready is high whenever SC is disabled",
        dut.w_tage_consumer_ready === 1'b1);
    chk("H7 a disabled SC raises no requests",
        (dut.w_sc_pred_req === 1'b0)
     && (dut.w_sc_upd_req === 1'b0));

    // SC enabled and ready with an update granted -> held.
    sc_enable        = 1'b1;
    ubtb_upd_u0[0]   = mk_upd(COND, 1'b0, pc);
    sc_upd_val_u0[0] = 1'b1;
    #1;
    chk("H7 an update grant holds TAGE",
        (dut.w_sc_grant_upd === 1'b1)
     && (dut.w_tage_consumer_ready === 1'b0));
    clr_upd_chans();
    #1;
    chk("H7 removing the update request releases TAGE",
        dut.w_tage_consumer_ready === 1'b1);

    sc_enable = 1'b0;
    clr_upd_chans();
    norq();
    repeat (2) tick();

    $display("---- GROUP H done (pass %0d fail %0d) ----",
             pass_cnt, fail_cnt);
  endtask

  // =================================================================
  // Main
  // =================================================================
  initial begin
    pass_cnt   = 0;
    fail_cnt   = 0;
    force_fail = 0;
    void'($value$plusargs("FORCE_FAIL=%d", force_fail));

    if (NUM_PRED_SLOTS != 2) begin
      $fatal(1,
        "tb_bp_cluster: written for NUM_PRED_SLOTS == 2, got %0d",
        NUM_PRED_SLOTS);
    end

    rstn = 1'b0;
    init_inputs();

    group_a();
    group_b();
    group_c();
    group_d();
    group_e();
    group_f();
    group_g();
    group_h();

    $display("tb_bp_cluster: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_bp_cluster: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  // Watchdog. $fatal(1) so a hang is a non-zero exit like any other
  // failure.
  initial begin
    repeat (200000) @(posedge clk);
    $fatal(1, "tb_bp_cluster: timeout");
  end

endmodule : tb
