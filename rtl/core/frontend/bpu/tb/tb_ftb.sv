// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_ftb.sv
// DATE:    2026-06-25
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking directed testbench for the ftb top (BP-068).
//
// DUT is the structural ftb top (ftb_array + ftb_plru + ftb_cntrl).
// The testbench drives ONLY the ftb top ports and reads ONLY the top
// outputs -- no bind into or hierarchical peek of the storage / cntrl
// internals (keeps the array-substitution invariant honest, IC-FTB-12).
//
// Timing model (BP-066, IC-FTB-09): prediction is two cycles. Drive
// pred_valid_p0 / pred_pc_p0 at cycle N; the p2 outputs are valid at
// cycle N+2. The single read port is shared: an active update borrows
// it, so prediction and update are driven in SEPARATE cycles here. The
// predict() task asserts the request for one cycle and samples two
// posedges later; the upd_*() tasks drive the update port for one cycle
// with the carried hit/way supplied explicitly (no FTB modeled).
//
// conf is a 3-bit bimodal DIRECTION counter
// (ftb_confidence_override_rules.md): ftb_brI_taken_p2 = valid &
// conf[MSB]. Fast-path (ftb_fastpath_p2) fires only at a saturated conf
// (111 / 000) with ftb_fastpath_en=1.
//
// Test groups: D (direction/conf), FP (fast-path), S (structural),
// P (position), I (invariant), R (per-start entries and the bounded
// fall-through; TD#124 / TD#125 / BP-110 until BP-140 made the entry
// per start), SP (the split at update, BP-140). The groups run at the
// package NUM_PRED_SLOTS, so the 1-slot target runs the 1-slot split;
// a case whose stimulus would split at one slot names its slot count.
// WAIVED here
// (BP-068 Constraints): flush (IC-FTB-07), FTQ round-trip /
// carried-way timing (IC-FTB-10), concurrent same-cycle
// predict+update arbitration (IC-FTB-09).
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;
import csr_pkg::*;

module tb;

  // -----------------------------------------------------------------
  // Clock and reset
  // -----------------------------------------------------------------
  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // -----------------------------------------------------------------
  // DUT port signals (names match ftb.sv exactly)
  // -----------------------------------------------------------------
  logic                       pred_valid_p0;
  logic [VA_WIDTH-1:0]        pred_pc_p0;

  logic                       ftb_valid_p2;
  logic                       ftb_hit_p2;
  logic [FTB_WAY_BITS-1:0]    ftb_way_p2;

  logic                       ftb_br0_valid_p2;
  logic [FTB_BR_POS_BITS-1:0] ftb_br0_pos_p2;
  logic                       ftb_br0_taken_p2;
  logic [FTB_CONF_WIDTH-1:0]  ftb_br0_conf_p2;
  logic [VA_WIDTH-1:0]        ftb_br0_target_p2;

  logic                       ftb_br1_valid_p2;
  logic [FTB_BR_POS_BITS-1:0] ftb_br1_pos_p2;
  logic                       ftb_br1_taken_p2;
  logic [FTB_CONF_WIDTH-1:0]  ftb_br1_conf_p2;
  logic [VA_WIDTH-1:0]        ftb_br1_target_p2;

  logic                       ftb_jmp_valid_p2;
  logic [FTB_BR_POS_BITS-1:0] ftb_jmp_pos_p2;
  logic [VA_WIDTH-1:0]        ftb_jmp_target_p2;
  logic                       ftb_is_call_p2;
  logic                       ftb_is_ret_p2;
  logic                       ftb_is_jalr_p2;
  logic                       ftb_jmp_rvc_p2;       // BP-121, TD#164

  logic [VA_WIDTH-1:0]        ftb_pft_addr_p2;

  logic [1:0]                 ftb_fastpath_p2;
  // The config group (SYS-001, csr_decisions.md CSR-2): the
  // DUT's config ports are driven from the members of fe_cfg,
  // which only the cfg_* tasks below write, from csr_tb_pkg
  // pack_fe_cfg after a csr_tb_pkg setter.
  fe_cfg_t fe_cfg;

  task automatic cfg_ftb_fastpath_en(input logic v);
    csr_tb_pkg::set_ftb_fastpath_en(v);
    fe_cfg = csr_tb_pkg::pack_fe_cfg();
  endtask


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
  logic                       ftb_upd_jmp_rvc_u0;   // BP-121, TD#164
  // The rvc bit the next upd_jmp carries (BP-121); 0 unless a test sets
  // it.
  logic                       jrvc_next;
  logic [VA_WIDTH-1:0]        ftb_upd_pft_addr_u0;

  logic                       ftb_flush_px;

  // -----------------------------------------------------------------
  // DUT
  // -----------------------------------------------------------------
  ftb dut (
    .clk                   (clk),
    .rstn                  (rstn),
    .pred_valid_p0         (pred_valid_p0),
    .pred_pc_p0            (pred_pc_p0),
    .ftb_valid_p2          (ftb_valid_p2),
    .ftb_hit_p2            (ftb_hit_p2),
    .ftb_way_p2            (ftb_way_p2),
    .ftb_br0_valid_p2      (ftb_br0_valid_p2),
    .ftb_br0_pos_p2        (ftb_br0_pos_p2),
    .ftb_br0_taken_p2      (ftb_br0_taken_p2),
    .ftb_br0_conf_p2       (ftb_br0_conf_p2),
    .ftb_br0_target_p2     (ftb_br0_target_p2),
    .ftb_br1_valid_p2      (ftb_br1_valid_p2),
    .ftb_br1_pos_p2        (ftb_br1_pos_p2),
    .ftb_br1_taken_p2      (ftb_br1_taken_p2),
    .ftb_br1_conf_p2       (ftb_br1_conf_p2),
    .ftb_br1_target_p2     (ftb_br1_target_p2),
    .ftb_jmp_valid_p2      (ftb_jmp_valid_p2),
    .ftb_jmp_pos_p2        (ftb_jmp_pos_p2),
    .ftb_jmp_target_p2     (ftb_jmp_target_p2),
    .ftb_is_call_p2        (ftb_is_call_p2),
    .ftb_is_ret_p2         (ftb_is_ret_p2),
    .ftb_is_jalr_p2        (ftb_is_jalr_p2),
    .ftb_jmp_rvc_p2        (ftb_jmp_rvc_p2),
    .ftb_pft_addr_p2       (ftb_pft_addr_p2),
    .ftb_fastpath_p2       (ftb_fastpath_p2),
    .ftb_fastpath_en       (fe_cfg.ftb_fastpath_en),
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
    .ftb_upd_jmp_rvc_u0    (ftb_upd_jmp_rvc_u0),
    .ftb_upd_pft_addr_u0   (ftb_upd_pft_addr_u0),
    .ftb_flush_px          (ftb_flush_px)
  );

  // -----------------------------------------------------------------
  // Scoreboard
  // -----------------------------------------------------------------
  int pass_cnt;
  int fail_cnt;

  task automatic check(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
      $display("PASS: %s", nm);
    end else begin
      fail_cnt++;
      $display("FAIL: %s", nm);
    end
  endtask

  // -----------------------------------------------------------------
  // Address / field helpers. All quantities are DERIVED from the
  // package parameters and the RTL encode/reconstruct, not assumed.
  // -----------------------------------------------------------------
  localparam logic [FTB_CONF_WIDTH-1:0] CONF_SAT_T = {FTB_CONF_WIDTH{1'b1}};
  localparam logic [FTB_CONF_WIDTH-1:0] CONF_SAT_N = '0;

  // The region tag width: FTB_RTAG_BITS since BP-140, FTB_TAG_BITS
  // before it (PRE_BP140 runs this file against the starting tree).
`ifdef PRE_BP140
  localparam int RTAG_BITS = FTB_TAG_BITS;
`else
  localparam int RTAG_BITS = FTB_RTAG_BITS;
`endif
  localparam int NS        = NUM_PRED_SLOTS;

  // Build a block-aligned PC from a region tag and a set index. tag
  // occupies the RTAG_BITS above the index, PC[39:14]; idx PC[13:5];
  // block offset PC[4:0] = 0. VA bits above the tag are zero: the
  // region tag is pinned at 26 (TD#122), so PC bit 40 is not
  // tag-covered. An aligned start's set is idx under both the starting
  // and the BP-140 index (the start offset it folds in is 0).
  function automatic logic [VA_WIDTH-1:0] make_pc(
      input logic [RTAG_BITS-1:0]    tag,
      input logic [FTB_IDX_BITS-1:0] idx);
    make_pc = VA_WIDTH'({tag, idx, {FTB_OFFSET_BITS{1'b0}}});
  endfunction

  // Independent restatement of the BP-140 index (bp_defines_pkg
  // FTB_SOFF_SHIFT): VA[13:5] XOR (VA[4:1] << 5), and of the region
  // index of the starting tree, VA[13:5].
  function automatic logic [FTB_IDX_BITS-1:0] new_idx(
      input logic [VA_WIDTH-1:0] pc);
    logic [FTB_IDX_BITS-1:0] off;
    off     = FTB_IDX_BITS'(pc[FTB_OFFSET_BITS-1:1]);
    new_idx = pc[FTB_OFFSET_BITS +: FTB_IDX_BITS]
            ^ (off << (FTB_IDX_BITS - FTB_BR_POS_BITS));
  endfunction

  function automatic logic [FTB_IDX_BITS-1:0] old_idx(
      input logic [VA_WIDTH-1:0] pc);
    old_idx = pc[FTB_OFFSET_BITS +: FTB_IDX_BITS];
  endfunction

  // The PC of in-block position pos of the block starting at start.
  function automatic logic [VA_WIDTH-1:0] pos_pc(
      input logic [VA_WIDTH-1:0]        start,
      input logic [FTB_BR_POS_BITS-1:0] pos);
    pos_pc = start + (VA_WIDTH'(pos) << POS_OFFSET_BITS);
  endfunction

  // Expected conditional target read-back: base + sign-extended low
  // FTB_BR_TGT_BITS of (tgt - base). Mirrors enc_br_disp + recon_br.
  function automatic logic [VA_WIDTH-1:0] exp_br_tgt(
      input logic [VA_WIDTH-1:0] tgt, input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0]        d;
    logic [FTB_BR_TGT_BITS-1:0] disp;
    d    = tgt - base;
    disp = d[FTB_BR_TGT_BITS-1:0];
    exp_br_tgt = base
      + {{(VA_WIDTH-FTB_BR_TGT_BITS){disp[FTB_BR_TGT_BITS-1]}}, disp};
  endfunction

  // Expected jump target read-back (FTB_JMP_TGT_BITS displacement).
  // base is the JUMP PC (ftb_decisions.md 4.2, TD#137).
  function automatic logic [VA_WIDTH-1:0] exp_jmp_tgt(
      input logic [VA_WIDTH-1:0] tgt, input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0]         d;
    logic [FTB_JMP_TGT_BITS-1:0] disp;
    d    = tgt - base;
    disp = d[FTB_JMP_TGT_BITS-1:0];
    exp_jmp_tgt = base
      + {{(VA_WIDTH-FTB_JMP_TGT_BITS){disp[FTB_JMP_TGT_BITS-1]}}, disp};
  endfunction

  // Expected fallthrough read-back from a full-VA block end written by
  // a jump update, for a lookup at start. Mirrors the ftb_cntrl reduce
  // (pftAddr from the block start since BP-140, no carry;
  // ftb_decisions.md 5.5) and the bounded reconstruct (FTB-G1, FTB-G3,
  // FTB-G2 fallback; 4.5, 4.6).
  function automatic logic [VA_WIDTH-1:0] exp_pft(
      input logic [VA_WIDTH-1:0] pft_in, input logic [VA_WIDTH-1:0] start);
    logic [VA_WIDTH-1:0]     off;
    logic [PFTADDR_BITS-1:0] pidx;
    logic [VA_WIDTH-1:0]     full;
    off   = pft_in - start;
    pidx  = off[POS_OFFSET_BITS +: PFTADDR_BITS];
    full  = start + (VA_WIDTH'(pidx) << POS_OFFSET_BITS);
    if ((full <= start)
        || (full > start + VA_WIDTH'(FTB_BLOCK_BYTES + (1 << POS_OFFSET_BITS))))
      exp_pft = start + VA_WIDTH'(FTB_BLOCK_BYTES);
    else
      exp_pft = full;
  endfunction

  // Every prediction port of one lookup, for comparing the entry two
  // resolution orders leave (group SP).
  typedef struct packed {
    logic                       hit;
    logic                       b0v;
    logic [FTB_BR_POS_BITS-1:0] b0p;
    logic [FTB_CONF_WIDTH-1:0]  b0c;
    logic [VA_WIDTH-1:0]        b0t;
    logic                       b1v;
    logic [FTB_BR_POS_BITS-1:0] b1p;
    logic [FTB_CONF_WIDTH-1:0]  b1c;
    logic [VA_WIDTH-1:0]        b1t;
    logic                       jv;
    logic [FTB_BR_POS_BITS-1:0] jp;
    logic [VA_WIDTH-1:0]        jt;
    logic [2:0]                 jty;
    logic [VA_WIDTH-1:0]        pft;
  } ftb_view_t;

  function automatic ftb_view_t view();
    ftb_view_t v;
    v.hit = ftb_hit_p2;
    v.b0v = ftb_br0_valid_p2;
    v.b0p = ftb_br0_pos_p2;
    v.b0c = ftb_br0_conf_p2;
    v.b0t = ftb_br0_target_p2;
    v.b1v = ftb_br1_valid_p2;
    v.b1p = ftb_br1_valid_p2 ? ftb_br1_pos_p2 : '0;
    v.b1c = ftb_br1_valid_p2 ? ftb_br1_conf_p2 : '0;
    v.b1t = ftb_br1_valid_p2 ? ftb_br1_target_p2 : '0;
    v.jv  = ftb_jmp_valid_p2;
    v.jp  = ftb_jmp_valid_p2 ? ftb_jmp_pos_p2 : '0;
    v.jt  = ftb_jmp_valid_p2 ? ftb_jmp_target_p2 : '0;
    v.jty = {ftb_is_call_p2, ftb_is_ret_p2, ftb_is_jalr_p2};
    v.pft = ftb_pft_addr_p2;
    return v;
  endfunction

  // -----------------------------------------------------------------
  // Drive helpers
  // -----------------------------------------------------------------
  // Park the update port idle (no clock).
  task automatic upd_idle();
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
    ftb_upd_jmp_rvc_u0    = 1'b0;
    ftb_upd_pft_addr_u0   = '0;
  endtask

  // Issue a prediction and sample two posedges later (p0 -> p2). The
  // update port is idle, so the prediction owns the read port. Driven
  // signals change #1 AFTER each posedge so the DUT flops capture the
  // intended value (avoids the stimulus/clock race).
  task automatic predict(input logic [VA_WIDTH-1:0] pc);
    pred_valid_p0 = 1'b1;
    pred_pc_p0    = pc;
    @(posedge clk); #1;      // p0 -> p1 (valid captured high)
    pred_valid_p0 = 1'b0;
    pred_pc_p0    = '0;
    @(posedge clk); #1;      // p1 -> p2 (sample now)
  endtask

  // One conditional-branch update (resolve). Carried hit/way supplied
  // explicitly. pft is the resolved block end (full VA).
  task automatic upd_br(input logic [VA_WIDTH-1:0]        pc,
                        input logic                       hit,
                        input logic [FTB_WAY_BITS-1:0]    way,
                        input logic                       br_idx,
                        input logic                       taken,
                        input logic [VA_WIDTH-1:0]        tgt,
                        input logic [FTB_BR_POS_BITS-1:0] pos,
                        input logic [VA_WIDTH-1:0]        pft);
    upd_idle();
    ftb_upd_valid_u0    = 1'b1;
    ftb_upd_pc_u0       = pc;
    ftb_upd_hit_u0      = hit;
    ftb_upd_way_u0      = way;
    ftb_upd_is_br_u0    = 1'b1;
    ftb_upd_br_idx_u0   = br_idx;
    ftb_upd_taken_u0    = taken;
    ftb_upd_target_u0   = tgt;
    ftb_upd_pos_u0      = pos;
    ftb_upd_pft_addr_u0 = pft;
    @(posedge clk); #1;      // write commits with valid still high
    upd_idle();
  endtask

  // One jump update (resolve). Type bits from the resolved jump.
  task automatic upd_jmp(input logic [VA_WIDTH-1:0]        pc,
                         input logic                       hit,
                         input logic [FTB_WAY_BITS-1:0]    way,
                         input logic [VA_WIDTH-1:0]        jtgt,
                         input logic                       is_call,
                         input logic                       is_ret,
                         input logic                       is_jalr,
                         input logic [FTB_BR_POS_BITS-1:0] pos,
                         input logic [VA_WIDTH-1:0]        pft);
    upd_idle();
    ftb_upd_valid_u0      = 1'b1;
    ftb_upd_pc_u0         = pc;
    ftb_upd_hit_u0        = hit;
    ftb_upd_way_u0        = way;
    ftb_upd_is_jmp_u0     = 1'b1;
    ftb_upd_jmp_target_u0 = jtgt;
    ftb_upd_is_call_u0    = is_call;
    ftb_upd_is_ret_u0     = is_ret;
    ftb_upd_is_jalr_u0    = is_jalr;
    ftb_upd_jmp_rvc_u0    = jrvc_next;
    ftb_upd_pos_u0        = pos;
    ftb_upd_pft_addr_u0   = pft;
    @(posedge clk); #1;      // write commits with valid still high
    upd_idle();
  endtask

  // n in-place conditional resolves (training the bimodal conf).
  task automatic train_br(input logic [VA_WIDTH-1:0]        pc,
                          input logic [FTB_WAY_BITS-1:0]    way,
                          input logic                       br_idx,
                          input logic                       taken,
                          input int                         n,
                          input logic [VA_WIDTH-1:0]        tgt,
                          input logic [FTB_BR_POS_BITS-1:0] pos,
                          input logic [VA_WIDTH-1:0]        pft);
    for (int i = 0; i < n; i++)
      upd_br(pc, 1'b1, way, br_idx, taken, tgt, pos, pft);
  endtask

  // Synchronous reset: clears ftb_plru valid + PLRU (FTB cold init).
  task automatic do_reset();
    rstn            = 1'b0;
    pred_valid_p0   = 1'b0;
    pred_pc_p0      = '0;
    csr_tb_pkg::csr_reset();
    cfg_ftb_fastpath_en(1'b0);
    ftb_flush_px    = 1'b0;
    jrvc_next       = 1'b0;
    upd_idle();
    repeat (3) @(posedge clk);
    rstn = 1'b1;
    @(posedge clk);
    #1;
  endtask

  // -----------------------------------------------------------------
  // Working variables
  // -----------------------------------------------------------------
  logic [VA_WIDTH-1:0] pc;
  logic [VA_WIDTH-1:0] pcA, pcB;
  logic [VA_WIDTH-1:0] base;
  logic [VA_WIDTH-1:0] tgt;
  logic [VA_WIDTH-1:0] j1, j2;
  logic [VA_WIDTH-1:0] jpc;
  logic [VA_WIDTH-1:0] s6_pc [0:4];
  logic [VA_WIDTH-1:0] st_pc [0:7];   // R2b, SP: starts and PCs
  logic [VA_WIDTH-1:0] b1pc;   // B1 cases: the br1 branch PC

  // -----------------------------------------------------------------
  // B1 set-up (BP-126, TD#81): an entry with br0 at pos 0 (taken) and
  // the branch under test in br1 at pos B1_POS, written as a free
  // field (S4's mechanism) with direction d. Its PC, the base of its
  // target, is the block start plus B1_POS halfwords.
  // -----------------------------------------------------------------
  localparam logic [FTB_BR_POS_BITS-1:0] B1_POS = 4'd4;
  task automatic b1_setup(input logic [VA_WIDTH-1:0]     p,
                          input logic [FTB_WAY_BITS-1:0] way,
                          input logic                    d,
                          input logic [VA_WIDTH-1:0]     t1);
    upd_br(p, 1'b0, way, 1'b0, 1'b1, p + VA_WIDTH'('h40), 4'd0, p);
    upd_br(p, 1'b1, way, 1'b1, d, t1, B1_POS, p);
  endtask

  // -----------------------------------------------------------------
  // Stimulus
  // -----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    // =============================================================
    // I1: conf allocate-init invariant (IC-FTB-06, conf 7). Asserted
    // here at sim start; ftb_cntrl carries the same elaboration check.
    // =============================================================
    check("I1 FTB_CONF_INIT_TKN unsaturated",
          FTB_CONF_INIT_TKN != CONF_SAT_T);
    check("I1 FTB_CONF_INIT_TKN MSB=1",
          FTB_CONF_INIT_TKN[FTB_CONF_WIDTH-1] == 1'b1);
    check("I1 FTB_CONF_INIT_NTK unsaturated",
          FTB_CONF_INIT_NTK != CONF_SAT_N);
    check("I1 FTB_CONF_INIT_NTK MSB=0",
          FTB_CONF_INIT_NTK[FTB_CONF_WIDTH-1] == 1'b0);

    // =============================================================
    // S1: cold miss -- unallocated block reads invalid (5.1).
    // =============================================================
    do_reset();
    predict(make_pc(26'h000001, 9'd7));
    check("S1 ftb_valid_p2==0 on cold miss", ftb_valid_p2 == 1'b0);
    check("S1 ftb_hit_p2==0 on cold miss",   ftb_hit_p2  == 1'b0);
    check("S1 fastpath clear on miss",       ftb_fastpath_p2 == 2'b00);

    // =============================================================
    // S2: allocate-then-hit -- miss-allocate the carried victim way,
    // later lookup hits with the correct way (5.1).
    // =============================================================
    do_reset();
    pc  = make_pc(26'h0000A1, 9'd5);
    tgt = pc + VA_WIDTH'('h100);
    upd_br(pc, 1'b0, 2'd2, 1'b0, 1'b1, tgt, 4'd1, pc); // alloc way2 br0 tkn
    predict(pc);
    check("S2 valid on hit",        ftb_valid_p2 == 1'b1);
    check("S2 hit asserted",        ftb_hit_p2  == 1'b1);
    check("S2 way == carried 2",    ftb_way_p2  == 2'd2);
    check("S2 br0 valid",           ftb_br0_valid_p2 == 1'b1);
    check("S2 br0 target round-trip",
          ftb_br0_target_p2 == exp_br_tgt(tgt, pc));

    // =============================================================
    // S3: update-in-place -- hit, resolve the same branch; the field
    // updates (conf steps) without reallocation (5.1).
    // =============================================================
    do_reset();
    pc  = make_pc(26'h0000B2, 9'd9);
    tgt = pc + VA_WIDTH'('h80);
    upd_br(pc, 1'b0, 2'd1, 1'b0, 1'b1, tgt, 4'd0, pc); // alloc way1 conf=4
    predict(pc);
    check("S3 alloc conf==INIT_TKN", ftb_br0_conf_p2 == FTB_CONF_INIT_TKN);
    upd_br(pc, 1'b1, 2'd1, 1'b0, 1'b1, tgt, 4'd0, pc); // in-place tkn ->5
    predict(pc);
    check("S3 in-place hit way unchanged", ftb_way_p2 == 2'd1);
    check("S3 still valid (no realloc)",   ftb_valid_p2 == 1'b1);
    check("S3 conf stepped 4->5",          ftb_br0_conf_p2 == 3'd5);

    // =============================================================
    // S4: free-field write -- tag hit, second conditional free, gets
    // written with weak init for its direction (5.1).
    // =============================================================
    do_reset();
    pc  = make_pc(26'h0000C3, 9'd11);
    tgt = pc + VA_WIDTH'('h40);
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd2, pc); // alloc br0 tkn
    upd_br(pc, 1'b1, 2'd0, 1'b1, 1'b0, tgt, 4'd4, pc); // free br1 ntkn
    predict(pc);
    check("S4 br0 still valid",  ftb_br0_valid_p2 == 1'b1);
    // BP-140: at one slot the second conditional splits the block
    // (group SP); the free-field fill is a two-slot case.
    if (NS > 1) begin
      check("S4 br1 now valid",    ftb_br1_valid_p2 == 1'b1);
      check("S4 br1 conf==INIT_NTK", ftb_br1_conf_p2 == FTB_CONF_INIT_NTK);
      check("S4 br1 not-taken (MSB=0)", ftb_br1_taken_p2 == 1'b0);
    end else begin
      check("S4 one slot: br1 not stored", ftb_br1_valid_p2 == 1'b0);
      check("S4 one slot: the end is the pos 4 branch PC",
            ftb_pft_addr_p2 == pos_pc(pc, 4'd4));
    end

    // =============================================================
    // S5: track-every-branch -- a not-taken conditional is allocated
    // and tracked, not dropped (5.2).
    // =============================================================
    do_reset();
    pc  = make_pc(26'h0000D4, 9'd13);
    tgt = pc + VA_WIDTH'('h60);
    upd_br(pc, 1'b0, 2'd3, 1'b0, 1'b0, tgt, 4'd1, pc); // alloc ntkn
    predict(pc);
    check("S5 not-taken branch tracked (valid)",
          ftb_br0_valid_p2 == 1'b1);
    check("S5 direction not-taken", ftb_br0_taken_p2 == 1'b0);
    check("S5 conf==INIT_NTK",      ftb_br0_conf_p2 == FTB_CONF_INIT_NTK);

    // =============================================================
    // S6: tree-PLRU eviction -- fill all four ways of one set from a
    // known reset+allocate sequence, then a miss prediction exposes
    // the tree-PLRU victim (5.3, IC-FTB-10). Touch order 0,1,2,3
    // leaves PLRU state 000 -> victim way0 (derived, not assumed).
    // =============================================================
    do_reset();
    for (int w = 0; w < 5; w++)
      s6_pc[w] = make_pc(26'h000100 + RTAG_BITS'(w), 9'd21);
    for (int w = 0; w < 4; w++)
      upd_br(s6_pc[w], 1'b0, w[FTB_WAY_BITS-1:0], 1'b0, 1'b1,
             s6_pc[w] + VA_WIDTH'('h20), 4'd0, s6_pc[w]); // alloc way w
    // Read the victim off the clean allocate sequence first (a miss
    // prediction does not touch PLRU, so this does not perturb state).
    // Touch order 0,1,2,3 leaves PLRU state 000 -> victim way0.
    predict(s6_pc[4]);
    check("S6 fifth tag misses", ftb_valid_p2 == 1'b0);
    check("S6 victim == tree-PLRU choice way0", ftb_way_p2 == 2'd0);
    // Confirm the four ways are populated (each tag hits its own way).
    for (int w = 0; w < 4; w++) begin
      predict(s6_pc[w]);
      check($sformatf("S6 way%0d populated", w),
            ftb_valid_p2 && (ftb_way_p2 == w[FTB_WAY_BITS-1:0]));
    end
    // Allocate the carried victim; way0's old tag (s6_pc[0]) is evicted.
    upd_br(s6_pc[4], 1'b0, 2'd0, 1'b0, 1'b1, s6_pc[4] + VA_WIDTH'('h20), 4'd0,
           s6_pc[4]);
    predict(s6_pc[4]);
    check("S6 new tag now hits way0",
          ftb_valid_p2 && (ftb_way_p2 == 2'd0));
    predict(s6_pc[0]);
    check("S6 evicted tag now misses", ftb_valid_p2 == 1'b0);

    // =============================================================
    // S7: jump-target unconditional rewrite -- resolve the same jump
    // twice with different targets; stored target = latest, no
    // ITTAGE-miss gating (5.5, IC-FTB-01).
    // =============================================================
    do_reset();
    pc = make_pc(26'h0000E5, 9'd33);
    j1 = pc + VA_WIDTH'('h200);
    j2 = pc + VA_WIDTH'('h2C0);
    upd_jmp(pc, 1'b0, 2'd0, j1, 1'b0, 1'b0, 1'b1, 4'd6, pc); // alloc jalr
    predict(pc);
    check("S7 jmp valid",            ftb_jmp_valid_p2 == 1'b1);
    jpc = pc + VA_WIDTH'(6 << POS_OFFSET_BITS);            // jump PC
    check("S7 jmp target == first",  ftb_jmp_target_p2 == exp_jmp_tgt(j1, jpc));
    upd_jmp(pc, 1'b1, 2'd0, j2, 1'b0, 1'b0, 1'b1, 4'd6, pc); // rewrite
    predict(pc);
    check("S7 jmp target == latest", ftb_jmp_target_p2 == exp_jmp_tgt(j2, jpc));

    // =============================================================
    // S8: conditional target round-trip -- in-range lossless; beyond
    // the FTB_BR_TGT_BITS reach the read-back wraps (overflow). conf
    // does not gate the target (4.2). Rewritten in place each resolve.
    // =============================================================
    do_reset();
    pc   = make_pc(26'h000040, 9'd1);   // base 0x100020, room below
    base = pc;
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, base + VA_WIDTH'('h400), 4'd0, pc);
    predict(pc);
    check("S8 in-range +0x400 lossless",
          ftb_br0_target_p2 == base + VA_WIDTH'('h400));
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, base + VA_WIDTH'('h0FFF), 4'd0, pc);
    predict(pc);
    check("S8 max in-range +0xFFF lossless (fit boundary)",
          ftb_br0_target_p2 == base + VA_WIDTH'('h0FFF));
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, base - VA_WIDTH'('h400), 4'd0, pc);
    predict(pc);
    check("S8 negative in-range -0x400 lossless",
          ftb_br0_target_p2 == base - VA_WIDTH'('h400));
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, base + VA_WIDTH'('h1000), 4'd0, pc);
    predict(pc);
    check("S8 overflow +0x1000 wraps per encode (status=overflow)",
          ftb_br0_target_p2 == exp_br_tgt(base + VA_WIDTH'('h1000), base));
    check("S8 overflow read-back != true target (lossy past reach)",
          ftb_br0_target_p2 != (base + VA_WIDTH'('h1000)));

    // =============================================================
    // S9: jump target round-trip -- same for FTB_JMP_TGT_BITS. The
    // jump is at pos 0 of a region-aligned start, so its jump PC is
    // base.
    // =============================================================
    do_reset();
    pc   = make_pc(26'h000080, 9'd2);   // base 0x200040
    base = pc;
    upd_jmp(pc, 1'b0, 2'd0, base + VA_WIDTH'('h1000), 1'b1, 1'b0, 1'b0, 4'd0,
            pc);
    predict(pc);
    check("S9 jmp in-range +0x1000 lossless",
          ftb_jmp_target_p2 == base + VA_WIDTH'('h1000));
    upd_jmp(pc, 1'b1, 2'd0, base + VA_WIDTH'('hF_FFFF), 1'b1, 1'b0, 1'b0, 4'd0,
            pc);
    predict(pc);
    check("S9 jmp max in-range +0xFFFFF lossless (fit boundary)",
          ftb_jmp_target_p2 == base + VA_WIDTH'('hF_FFFF));
    upd_jmp(pc, 1'b1, 2'd0, base + VA_WIDTH'('h10_0000), 1'b1, 1'b0, 1'b0,
            4'd0, pc);
    predict(pc);
    check("S9 jmp overflow +0x100000 wraps per encode",
          ftb_jmp_target_p2 == exp_jmp_tgt(base + VA_WIDTH'('h10_0000), base));

    // =============================================================
    // S10: fallthrough reduce/reconstruct -- in-block ends are
    // lossless, and so is an end at the next block start (4.5, 5.5,
    // 8.1). Since BP-140 an end is written by a jump (its resolved end)
    // or by the split; the pftAddr a conditional's update carries is
    // its block's predicted end and is not written, so the ends here
    // come from jumps, one start each (a second jump after the first is
    // past the block, group F).
    // OLD (until BP-140): one start, three conditional updates carrying
    // ends +12, +28 and +32, each read back as written.
    // =============================================================
    do_reset();
    pc   = make_pc(26'h0000F6, 9'd44);
    base = pc;
    tgt  = base + VA_WIDTH'('h10);
    // a conditional allocate: the end is one block above the start, not
    // the +12 its update carries.
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd0, base + VA_WIDTH'('d12));
    predict(pc);
    check("S10 a conditional's update end is not written (start + 32)",
          ftb_pft_addr_p2 == base + VA_WIDTH'(FTB_BLOCK_BYTES));
    // in-block end +12: a 32-bit jump at pos 4 (offset 8).
    do_reset();
    upd_jmp(pc, 1'b0, 2'd0, tgt, 1'b0, 1'b0, 1'b0, 4'd4,
            base + VA_WIDTH'('d12));
    predict(pc);
    check("S10 in-block end +12 lossless",
          ftb_pft_addr_p2 == base + VA_WIDTH'('d12));
    check("S10 in-block end +12 == model",
          ftb_pft_addr_p2 == exp_pft(base + VA_WIDTH'('d12), base));
    // in-block end +28: a 32-bit jump at pos 12 (offset 24).
    do_reset();
    upd_jmp(pc, 1'b0, 2'd0, tgt, 1'b0, 1'b0, 1'b0, 4'd12,
            base + VA_WIDTH'('d28));
    predict(pc);
    check("S10 in-block end +28 lossless",
          ftb_pft_addr_p2 == base + VA_WIDTH'('d28));
    // cross-block end at next block start (offset 32): a 32-bit jump at
    // pos 14.
    do_reset();
    upd_jmp(pc, 1'b0, 2'd0, tgt, 1'b0, 1'b0, 1'b0, 4'd14,
            base + VA_WIDTH'('d32));
    predict(pc);
    check("S10 cross-block end +32 lossless",
          ftb_pft_addr_p2 == base + VA_WIDTH'('d32));
    check("S10 cross-block end +32 == model",
          ftb_pft_addr_p2 == exp_pft(base + VA_WIDTH'('d32), base));

    // =============================================================
    // S11: branch-type classification -- jump type bits drive
    // ftb_is_call / ftb_is_ret / ftb_is_jalr (section 1).
    // =============================================================
    do_reset();
    pc = make_pc(26'h000111, 9'd55);
    j1 = pc + VA_WIDTH'('h100);
    upd_jmp(pc, 1'b0, 2'd0, j1, 1'b1, 1'b0, 1'b0, 4'd0, pc); // call
    predict(pc);
    check("S11 call: is_call",  ftb_is_call_p2 == 1'b1);
    check("S11 call: !is_ret",  ftb_is_ret_p2  == 1'b0);
    check("S11 call: !is_jalr", ftb_is_jalr_p2 == 1'b0);
    upd_jmp(pc, 1'b1, 2'd0, j1, 1'b0, 1'b1, 1'b0, 4'd0, pc); // ret
    predict(pc);
    check("S11 ret: is_ret",   ftb_is_ret_p2  == 1'b1);
    check("S11 ret: !is_call", ftb_is_call_p2 == 1'b0);
    check("S11 ret: !is_jalr", ftb_is_jalr_p2 == 1'b0);
    upd_jmp(pc, 1'b1, 2'd0, j1, 1'b0, 1'b0, 1'b1, 4'd0, pc); // jalr
    predict(pc);
    check("S11 jalr: is_jalr",  ftb_is_jalr_p2 == 1'b1);
    check("S11 jalr: !is_call", ftb_is_call_p2 == 1'b0);
    check("S11 jalr: !is_ret",  ftb_is_ret_p2  == 1'b0);

    // =============================================================
    // D1: FTB direction is the conf MSB, both polarities (override
    // doc 3.1). Allocate taken (MSB=1); one not-taken resolve flips
    // the MSB to 0.
    // =============================================================
    do_reset();
    pc  = make_pc(26'h000221, 9'd64);
    tgt = pc + VA_WIDTH'('h40);
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd0, pc); // conf=4, MSB=1
    predict(pc);
    check("D1 MSB=1 -> taken", ftb_br0_taken_p2 == 1'b1);
    check("D1 taken == valid & conf MSB",
          ftb_br0_taken_p2 ==
            (ftb_br0_valid_p2 & ftb_br0_conf_p2[FTB_CONF_WIDTH-1]));
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b0, tgt, 4'd0, pc); // 4->3, MSB=0
    predict(pc);
    check("D1 MSB=0 -> not-taken", ftb_br0_taken_p2 == 1'b0);
    check("D1 not-taken == valid & conf MSB",
          ftb_br0_taken_p2 ==
            (ftb_br0_valid_p2 & ftb_br0_conf_p2[FTB_CONF_WIDTH-1]));

    // =============================================================
    // D2: bimodal train -- taken saturates at 111 (no wrap),
    // not-taken saturates at 000 (no wrap) (override doc 3.2).
    // =============================================================
    do_reset();
    pc  = make_pc(26'h000222, 9'd65);
    tgt = pc + VA_WIDTH'('h40);
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd0, pc); // conf=4
    train_br(pc, 2'd0, 1'b0, 1'b1, 3, tgt, 4'd0, pc);  // ->7
    predict(pc);
    check("D2 taken saturates at 111", ftb_br0_conf_p2 == CONF_SAT_T);
    train_br(pc, 2'd0, 1'b0, 1'b1, 1, tgt, 4'd0, pc);  // extra taken
    predict(pc);
    check("D2 taken no wrap (stays 111)", ftb_br0_conf_p2 == CONF_SAT_T);
    do_reset();
    pc  = make_pc(26'h000223, 9'd66);
    tgt = pc + VA_WIDTH'('h40);
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b0, tgt, 4'd0, pc); // conf=3
    train_br(pc, 2'd0, 1'b0, 1'b0, 3, tgt, 4'd0, pc);  // ->0
    predict(pc);
    check("D2 not-taken saturates at 000", ftb_br0_conf_p2 == CONF_SAT_N);
    train_br(pc, 2'd0, 1'b0, 1'b0, 1, tgt, 4'd0, pc);  // extra not-taken
    predict(pc);
    check("D2 not-taken no wrap (stays 000)", ftb_br0_conf_p2 == CONF_SAT_N);

    // =============================================================
    // D3: weak init -- taken alloc -> INIT_TKN (3'b100), not-taken
    // alloc -> INIT_NTK (3'b011); a fresh entry does NOT fast-path
    // (override doc 7). en=1 to prove the unsaturated entry holds.
    // =============================================================
    do_reset();
    cfg_ftb_fastpath_en(1'b1);
    pc  = make_pc(26'h000224, 9'd70);
    tgt = pc + VA_WIDTH'('h40);
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd0, pc); // taken alloc
    predict(pc);
    check("D3 taken init conf==3'b100", ftb_br0_conf_p2 == FTB_CONF_INIT_TKN);
    check("D3 taken init MSB=1",
          ftb_br0_conf_p2[FTB_CONF_WIDTH-1] == 1'b1);
    check("D3 fresh taken does NOT fast-path", ftb_fastpath_p2[0] == 1'b0);
    pc  = make_pc(26'h000225, 9'd71);
    tgt = pc + VA_WIDTH'('h40);
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b0, tgt, 4'd0, pc); // not-taken alloc
    predict(pc);
    check("D3 ntkn init conf==3'b011", ftb_br0_conf_p2 == FTB_CONF_INIT_NTK);
    check("D3 ntkn init MSB=0",
          ftb_br0_conf_p2[FTB_CONF_WIDTH-1] == 1'b0);
    check("D3 fresh ntkn does NOT fast-path", ftb_fastpath_p2[0] == 1'b0);
    cfg_ftb_fastpath_en(1'b0);

    // =============================================================
    // D4: self-correction -- saturate to 111 (fast-path eligible);
    // one opposite resolve steps to 110 and the fast-path stops until
    // re-saturation (override doc 3.4).
    // =============================================================
    do_reset();
    pc  = make_pc(26'h000226, 9'd80);
    tgt = pc + VA_WIDTH'('h40);
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd0, pc);
    train_br(pc, 2'd0, 1'b0, 1'b1, 3, tgt, 4'd0, pc);  // ->7
    cfg_ftb_fastpath_en(1'b1);
    predict(pc);
    check("D4 saturated conf==111", ftb_br0_conf_p2 == CONF_SAT_T);
    check("D4 fast-path fires at 111", ftb_fastpath_p2[0] == 1'b1);
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b0, tgt, 4'd0, pc); // 7->6
    predict(pc);
    check("D4 mispredict steps 111->110", ftb_br0_conf_p2 == 3'd6);
    check("D4 fast-path stops at 110", ftb_fastpath_p2[0] == 1'b0);
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, tgt, 4'd0, pc); // 6->7
    predict(pc);
    check("D4 re-saturates to 111", ftb_br0_conf_p2 == CONF_SAT_T);
    check("D4 fast-path fires again", ftb_fastpath_p2[0] == 1'b1);
    cfg_ftb_fastpath_en(1'b0);

    // =============================================================
    // D5: reallocation resets conf -- saturate a field, then evict
    // and reallocate the same way to a branch of the opposite
    // direction; conf = new weak init, not the old value (5.4 / 7).
    // =============================================================
    do_reset();
    pcA = make_pc(26'h00030A, 9'd90);
    pcB = make_pc(26'h00030B, 9'd90);   // same set, different tag
    tgt = pcA + VA_WIDTH'('h40);
    upd_br(pcA, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd0, pcA); // alloc tkn
    train_br(pcA, 2'd0, 1'b0, 1'b1, 3, tgt, 4'd0, pcA);  // ->7
    predict(pcA);
    check("D5 A saturated 111 before realloc", ftb_br0_conf_p2 == CONF_SAT_T);
    // realloc
    upd_br(pcB, 1'b0, 2'd0, 1'b0, 1'b0, pcB + VA_WIDTH'('h40), 4'd0, pcB);
    predict(pcB);
    check("D5 B hits after realloc",   ftb_valid_p2 == 1'b1);
    check("D5 B conf == new weak init (011)",
          ftb_br0_conf_p2 == FTB_CONF_INIT_NTK);
    check("D5 B direction not-taken",  ftb_br0_taken_p2 == 1'b0);
    predict(pcA);
    check("D5 A evicted by realloc",   ftb_valid_p2 == 1'b0);

    // =============================================================
    // FP1: fast-path fires only with en=1 AND conf saturated AND
    // ftb_valid_p2 AND ftb_brI_valid_p2 (override doc 4).
    // =============================================================
    do_reset();
    pc  = make_pc(26'h000401, 9'd100);
    tgt = pc + VA_WIDTH'('h40);
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd0, pc);
    train_br(pc, 2'd0, 1'b0, 1'b1, 3, tgt, 4'd0, pc);  // ->7
    cfg_ftb_fastpath_en(1'b1);
    predict(pc);
    check("FP1 valid+br0_valid+sat+en", ftb_valid_p2 && ftb_br0_valid_p2 &&
          (ftb_br0_conf_p2 == CONF_SAT_T) && fe_cfg.ftb_fastpath_en);
    check("FP1 fast-path[0] fires", ftb_fastpath_p2[0] == 1'b1);

    // =============================================================
    // FP2: does NOT fire at en=0, even at saturated conf.
    // =============================================================
    cfg_ftb_fastpath_en(1'b0);
    predict(pc);
    check("FP2 conf still saturated",  ftb_br0_conf_p2 == CONF_SAT_T);
    check("FP2 no fire at en=0",       ftb_fastpath_p2[0] == 1'b0);

    // =============================================================
    // FP3: does NOT fire at an unsaturated conf, even with en=1.
    // =============================================================
    do_reset();
    pc  = make_pc(26'h000402, 9'd101);
    tgt = pc + VA_WIDTH'('h40);
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd0, pc); // conf=4 (unsat)
    cfg_ftb_fastpath_en(1'b1);
    predict(pc);
    check("FP3 conf unsaturated (==4)", ftb_br0_conf_p2 == FTB_CONF_INIT_TKN);
    check("FP3 no fire when unsaturated", ftb_fastpath_p2[0] == 1'b0);
    cfg_ftb_fastpath_en(1'b0);

    // =============================================================
    // FP4: does NOT fire on an FTB miss or an empty conditional field.
    // =============================================================
    do_reset();
    cfg_ftb_fastpath_en(1'b1);
    predict(make_pc(26'h0009FF, 9'd102));            // unallocated -> miss
    check("FP4 miss: not valid",       ftb_valid_p2 == 1'b0);
    check("FP4 miss: no fast-path",    ftb_fastpath_p2 == 2'b00);
    pc = make_pc(26'h000403, 9'd103);
    upd_jmp(pc, 1'b0, 2'd0, pc + VA_WIDTH'('h80), 1'b1, 1'b0, 1'b0, 4'd0, pc);
    predict(pc);                                     // jmp only, no br0
    check("FP4 empty br0 field invalid", ftb_br0_valid_p2 == 1'b0);
    check("FP4 empty field: br0 no fast-path", ftb_fastpath_p2[0] == 1'b0);
    cfg_ftb_fastpath_en(1'b0);

    // =============================================================
    // FP5: fast-path is direction-only -- at a saturated conf the
    // branch target is unchanged; there is no target suppression
    // (override doc 4.2). Train to 111 with a known target.
    // =============================================================
    do_reset();
    pc   = make_pc(26'h000404, 9'd104);
    base = pc;
    tgt  = base + VA_WIDTH'('h300);
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd0, pc);
    train_br(pc, 2'd0, 1'b0, 1'b1, 3, tgt, 4'd0, pc);  // ->7
    cfg_ftb_fastpath_en(1'b1);
    predict(pc);
    check("FP5 fast-path fires", ftb_fastpath_p2[0] == 1'b1);
    check("FP5 target intact under fast-path",
          ftb_br0_target_p2 == exp_br_tgt(tgt, base));
    check("FP5 target == true (in-range, direction-only)",
          ftb_br0_target_p2 == tgt);
    cfg_ftb_fastpath_en(1'b0);

    // =============================================================
    // P1: position round-trip -- drive ftb_upd_pos_u0 on fills for
    // br0, br1, and the jump; read back the three pos outputs
    // (BP-066b, IC-FTB-15). Since BP-140 an entry holds at most
    // NUM_PRED_SLOTS branches, so the three fields are read in entries
    // that fit: {br0 3, jmp 7} and, at two slots, {br0 3, br1 5}.
    // OLD (until BP-140): one entry {br0 3, br1 5, jmp 7}; at two slots
    // the jump is now the third branch and is split off (SP4).
    // =============================================================
    do_reset();
    pc  = make_pc(26'h000501, 9'd120);
    tgt = pc + VA_WIDTH'('h40);
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd3, pc);            // br0 pos3
    if (NS > 1) begin
      upd_br(pc, 1'b1, 2'd0, 1'b1, 1'b1, tgt, 4'd5, pc);          // br1 pos5
      predict(pc);
      check("P1 br0 pos round-trip ==3", ftb_br0_pos_p2 == 4'd3);
      check("P1 br1 pos round-trip ==5", ftb_br1_pos_p2 == 4'd5);
      do_reset();
      upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd3, pc);          // br0 pos3
    end
    // jmp7: at one slot a separate entry (the conditional at 3 would
    // split it off).
    if (NS == 1) do_reset();
    upd_jmp(pc, (NS > 1), 2'd0, pc + VA_WIDTH'('h80), 1'b1, 1'b0, 1'b0, 4'd7,
            pc + VA_WIDTH'('d18));
    predict(pc);
    if (NS > 1)
      check("P1 br0 pos round-trip ==3 (beside the jump)",
            ftb_br0_pos_p2 == 4'd3);
    check("P1 jmp pos round-trip ==7", ftb_jmp_pos_p2 == 4'd7);

    // =============================================================
    // P2: a DIFFERENT position is a different branch (5.5, ruled
    // session-075, TD#156). Since BP-140 a new branch below every held
    // one in a full entry is KEPT and the highest held branch falls out
    // (the split, SP5); the end moves to the PC of the one that fell
    // out. Full entry: {3, 5} at two slots, {3} at one; new branch 2.
    // The same-position case is group F, F3.
    // OLD (BP-066b, until BP-120): "P2 br0 pos static on in-place
    // (still 3)". OLD (BP-120 to BP-140): br0, the field slot 0 names,
    // refilled with pos 2 and br1 kept pos 5.
    // =============================================================
    do_reset();
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd3, pc);
    if (NS > 1) upd_br(pc, 1'b1, 2'd0, 1'b1, 1'b1, tgt, 4'd5, pc);
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, tgt, 4'd2, pc); // new branch pos2
    predict(pc);
    check("P2 the new lower branch is kept in br0 (pos 2)",
          ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd2));
    if (NS > 1) begin
      check("P2 br1 is the pos 3 branch", ftb_br1_valid_p2
            && (ftb_br1_pos_p2 == 4'd3));
      check("P2 the pos 5 branch fell out: end = its PC",
            ftb_pft_addr_p2 == pos_pc(pc, 4'd5));
    end else begin
      check("P2 the pos 3 branch fell out: end = its PC",
            ftb_pft_addr_p2 == pos_pc(pc, 4'd3));
    end

    // =============================================================
    // P3: reallocation overwrites position -- reallocate the field to
    // a new branch with a new position; the new position is stored.
    // =============================================================
    pcB = make_pc(26'h000502, 9'd120);  // same set, different tag
    // realloc
    upd_br(pcB, 1'b0, 2'd0, 1'b0, 1'b1, pcB + VA_WIDTH'('h40), 4'd4, pcB);
    predict(pcB);
    check("P3 realloc stores new pos ==4", ftb_br0_pos_p2 == 4'd4);

    // =============================================================
    // R1: TD#124. A block starting at region offset 30 whose 32-bit
    // jump at pos 15 straddles the next block ends 34 bytes above the
    // start, 64 above the region base (ftb_decisions.md 5.5). The end
    // must reconstruct exactly. As built before TD#124, pftAddr + carry
    // reconstructed base+32, and FTB-G1 passed it because base+32 is
    // above the start.
    // OLD (until BP-140): a conditional at pos 3 whose update carried
    // the end base+64; a conditional's update end is no longer written
    // (S10), so the straddling end now comes from the jump.
    // =============================================================
    do_reset();
    base = make_pc(26'h000611, 9'd130);
    pc   = base + VA_WIDTH'('d30);
    tgt  = pc + VA_WIDTH'('h100);
    upd_jmp(pc, 1'b0, 2'd0, tgt, 1'b0, 1'b0, 1'b0, 4'd15,
            base + VA_WIDTH'('d64));
    predict(pc);
    $display("R1 pft got %h exp %h", ftb_pft_addr_p2,
             base + VA_WIDTH'('d64));
    check("R1 start at region offset 30 hits", ftb_valid_p2 == 1'b1);
    check("R1 end at region offset 64 reconstructs exactly",
          ftb_pft_addr_p2 == base + VA_WIDTH'('d64));
    check("R1 end is start + FTB_BLOCK_BYTES + 2 (straddle)",
          ftb_pft_addr_p2
            == pc + VA_WIDTH'(FTB_BLOCK_BYTES + (1 << POS_OFFSET_BITS)));
    check("R1 jmp pos is start-relative ==15", ftb_jmp_valid_p2
          && (ftb_jmp_pos_p2 == 4'd15));
    check("R1 jmp target round-trip", ftb_jmp_target_p2 == tgt);

    // =============================================================
    // R2: BP-140, Problem 1. TWO STARTS IN ONE 32-BYTE REGION KEEP
    // SEPARATE ENTRIES (one entry per start PC, ruled by Jeff
    // 2026-10-18; it reverses ftb_decisions.md 4.6). A starts at region
    // offset 0, B at offset 10. Each start's updates leave the other's
    // fields, end and hit unchanged. Fails on the starting tree, where
    // the two share one entry (B hits A's entry before B ever writes,
    // and A then reads B's branch and B's jump end).
    // OLD (TD#125, BP-110 to BP-140): the shared entry, B not seeing A's
    // branch below B's start, and A seeing B's branch at pos 8.
    // =============================================================
    do_reset();
    base = make_pc(26'h000612, 9'd131);
    pcA  = base;
    pcB  = base + VA_WIDTH'('d10);
    j1   = base + VA_WIDTH'('h100);          // A's branch target
    j2   = base + VA_WIDTH'('h300);          // B's jump target
    // A: a conditional at pos 2 (branch PC base+4). Carried way 1.
    upd_br(pcA, 1'b0, 2'd1, 1'b0, 1'b1, j1, 4'd2, pcA);
    predict(pcB);
    check("R2 B misses before B writes (no shared entry)",
          !ftb_hit_p2 && !ftb_valid_p2);
    // B: a 32-bit jump at its pos 3 (jump PC base+16), end base+20.
    // Carried way 1 again: B's set differs from A's, so it does not
    // overwrite A.
    upd_jmp(pcB, 1'b0, 2'd1, j2, 1'b1, 1'b0, 1'b0, 4'd3,
            base + VA_WIDTH'('d20));
    predict(pcB);
    check("R2 B hits its own entry", ftb_hit_p2 && ftb_valid_p2);
    check("R2 B holds only its jump: no conditional",
          !ftb_br0_valid_p2 && !ftb_br1_valid_p2);
    check("R2 B jmp at its pos 3, its target, a call",
          ftb_jmp_valid_p2 && (ftb_jmp_pos_p2 == 4'd3)
          && (ftb_jmp_target_p2 == j2) && ftb_is_call_p2);
    check("R2 B end is its jump's end", ftb_pft_addr_p2
          == base + VA_WIDTH'('d20));
    predict(pcA);
    check("R2 A still hits", ftb_hit_p2 && ftb_valid_p2);
    check("R2 A br0 is A's branch: pos 2, A's target, weak taken",
          ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd2)
          && (ftb_br0_target_p2 == j1)
          && (ftb_br0_conf_p2 == FTB_CONF_INIT_TKN));
    check("R2 A sees no jump and no br1",
          !ftb_jmp_valid_p2 && !ftb_br1_valid_p2);
    check("R2 A end unchanged (one block above A)",
          ftb_pft_addr_p2 == pcA + VA_WIDTH'(FTB_BLOCK_BYTES));
    // A trains its branch; B is unchanged.
    upd_br(pcA, 1'b1, 2'd1, 1'b0, 1'b1, j1, 4'd2, pcA);
    predict(pcB);
    check("R2 after A trains: B unchanged (jump, end, hit)",
          ftb_hit_p2 && ftb_jmp_valid_p2 && (ftb_jmp_pos_p2 == 4'd3)
          && !ftb_br0_valid_p2
          && (ftb_pft_addr_p2 == base + VA_WIDTH'('d20)));
    predict(pcA);
    check("R2 A conf stepped 4 -> 5", ftb_br0_conf_p2 == 3'd5);

    // =============================================================
    // R2b: BP-140, Problem 1. STARTS THAT SHARE A SET UNDER THE
    // STARTING INDEX. Every start of one region indexes one set under
    // the region index VA[13:5]; the BP-140 index folds the start
    // offset into the top bits. Five starts of one region, offsets 0,
    // 2, 6, 10 and 30, each allocated with carried way 0: with one set
    // they would overwrite one another in way 0 (so per-start entries
    // under the starting index would keep one of five). All five stay
    // resident. Fails on the starting tree in the separate-field
    // checks (all five read the last writer's branch).
    // =============================================================
    do_reset();
    base     = make_pc(26'h000613, 9'd132);
    st_pc[0] = base;
    st_pc[1] = base + VA_WIDTH'('d2);
    st_pc[2] = base + VA_WIDTH'('d6);
    st_pc[3] = base + VA_WIDTH'('d10);
    st_pc[4] = base + VA_WIDTH'('d30);
    for (int i = 0; i < 5; i++) begin
      $display("R2b start %h: starting set %0d, BP-140 set %0d", st_pc[i],
               old_idx(st_pc[i]), new_idx(st_pc[i]));
      check($sformatf("R2b start %0d: one set under the starting index", i),
            old_idx(st_pc[i]) == old_idx(st_pc[0]));
      for (int j = 0; j < i; j++)
        check($sformatf("R2b starts %0d and %0d: different BP-140 sets", j, i),
              new_idx(st_pc[i]) != new_idx(st_pc[j]));
    end
    for (int i = 0; i < 5; i++)
      upd_br(st_pc[i], 1'b0, 2'd0, 1'b0, 1'b1,
             st_pc[i] + VA_WIDTH'('h200) + VA_WIDTH'(i << 4), 4'd1,
             st_pc[i]);
    for (int i = 0; i < 5; i++) begin
      predict(st_pc[i]);
      check($sformatf("R2b start %0d resident in way 0 of its set", i),
            ftb_hit_p2 && (ftb_way_p2 == 2'd0));
      check($sformatf("R2b start %0d reads its own branch", i),
            ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd1)
            && (ftb_br0_target_p2
                == st_pc[i] + VA_WIDTH'('h200) + VA_WIDTH'(i << 4)));
    end

    // =============================================================
    // R3: FTB-G1 and FTB-G3 (ftb_decisions.md 4.5, 4.6 O-2). Since
    // BP-140 an out-of-bounds end can be stored only from a jump's
    // resolved end; one that is out of bounds takes the FTB-G2
    // fallback, start + FTB_BLOCK_BYTES.
    // OLD (until BP-140): a start at region offset 30 recorded an end
    // 62 bytes above the region base, and the offset-0 start sharing
    // the entry read it as beyond start + 34 (FTB-G3) and did not see
    // the branch past its end; per-start entries have no such reader.
    // =============================================================
    do_reset();
    pc = make_pc(26'h000614, 9'd133);
    upd_jmp(pc, 1'b0, 2'd0, pc + VA_WIDTH'('h80), 1'b0, 1'b0, 1'b1, 4'd5,
            pc + VA_WIDTH'('d40));                 // end > start + 34
    predict(pc);
    check("R3 FTB-G3: end beyond start+34 falls back to start+32",
          ftb_pft_addr_p2 == pc + VA_WIDTH'(FTB_BLOCK_BYTES));
    upd_jmp(pc, 1'b1, 2'd0, pc + VA_WIDTH'('h80), 1'b0, 1'b0, 1'b1, 4'd5,
            pc);                                   // end == start
    predict(pc);
    check("R3 FTB-G1: end at the start falls back to start+32",
          ftb_pft_addr_p2 == pc + VA_WIDTH'(FTB_BLOCK_BYTES));
    check("R3 the jump itself is still reported",
          ftb_jmp_valid_p2 && (ftb_jmp_pos_p2 == 4'd5));

    // =============================================================
    // J1: TD#137. A jump target recorded from a start at region offset
    // 8; the jump sits at its pos 6, jump PC base+20, target jump PC +
    // 0x1000. In-reach, so it round-trips.
    // OLD (until BP-140): recorded from offset 0 and also read from
    // offset 8, the second start sharing the entry (now a miss, R2).
    // =============================================================
    do_reset();
    base = make_pc(26'h000615, 9'd134);
    pcB  = base + VA_WIDTH'('d8);
    jpc  = base + VA_WIDTH'('d20);
    j1   = jpc + VA_WIDTH'('h1000);
    upd_jmp(pcB, 1'b0, 2'd0, j1, 1'b0, 1'b0, 1'b1, 4'd6,
            base + VA_WIDTH'('d24));
    predict(pcB);
    check("J1 jmp valid, pos 6",
          ftb_jmp_valid_p2 && (ftb_jmp_pos_p2 == 4'd6));
    check("J1 jmp target round-trips", ftb_jmp_target_p2 == j1);

    // =============================================================
    // J2: TD#137. The displacement is measured from the JUMP PC, so
    // the forward reach ends at jump PC + 2**(FTB_JMP_TGT_BITS-1) - 2
    // wherever the jump sits. The jump is at pos 15 of a start at
    // region offset 2, jump PC base+32; the target is the last even
    // address in reach of the jump PC, 32 bytes past the last one in
    // reach of the region base.
    // OLD (until BP-140): also read from a second start at offset 30
    // sharing the entry (jump at its pos 1).
    // =============================================================
    do_reset();
    base = make_pc(26'h000616, 9'd135);
    pcA  = base + VA_WIDTH'('d2);
    jpc  = base + VA_WIDTH'('d32);
    j1   = jpc + VA_WIDTH'((1 << (FTB_JMP_TGT_BITS - 1)) - 2);
    upd_jmp(pcA, 1'b0, 2'd0, j1, 1'b0, 1'b0, 1'b1, 4'd15,
            base + VA_WIDTH'('d34));
    predict(pcA);
    $display("J2 A jmp target got %h exp %h", ftb_jmp_target_p2, j1);
    check("J2 jmp valid, pos 15",
          ftb_jmp_valid_p2 && (ftb_jmp_pos_p2 == 4'd15));
    check("J2 edge-of-reach target is exact",
          ftb_jmp_target_p2 == j1);

    // =============================================================
    // F: THE SAME BRANCH IS THE SAME POSITION (ftb_decisions.md 5.5,
    // IC-FTB-01, IC-FTB-15, ruled session-075, TD#156, BP-120). Every
    // case starts from reset and a driven sequence, from one start at
    // region offset 0 so every stored field is visible to it; the
    // pre-BP-120 rule kept a visible stored position for any update.
    // =============================================================

    // F1: two jumps of one START at different positions. J1 is a
    // RETURN_CALL at pos 4, J2 a RETURN at pos 9 (the coro shape,
    // BP-119). Since BP-140 the entry is one start's block, which ends
    // at its first jump: J2 after J1 is past the block and changes
    // nothing; J2 BEFORE the stored jump (pos 2) replaces it, with its
    // type, target and end. In coro the two jumps belong to two starts
    // of one region, each now with its own entry (R2, TD#168).
    // OLD (BP-120 to BP-140): J2 at pos 9 replaced J1 (the shared
    // region field held whichever jump trained last), and J1 again
    // replaced J2.
    do_reset();
    base = make_pc(26'h000701, 9'd140);
    j1   = base + VA_WIDTH'('h1200);
    j2   = base + VA_WIDTH'('h3400);
    upd_jmp(base, 1'b0, 2'd1, j1, 1'b1, 1'b1, 1'b1, 4'd4,
            base + VA_WIDTH'('d12));
    predict(base);
    check("F1 J1 holds the field: pos 4, call+ret+jalr",
          ftb_jmp_valid_p2 && (ftb_jmp_pos_p2 == 4'd4) && ftb_is_call_p2
          && ftb_is_ret_p2 && ftb_is_jalr_p2);
    upd_jmp(base, 1'b1, 2'd1, j2, 1'b0, 1'b1, 1'b1, 4'd9,
            base + VA_WIDTH'('d22));
    predict(base);
    check("F1 J2 after J1 is past the block: J1 kept (pos 4, type)",
          ftb_jmp_valid_p2 && (ftb_jmp_pos_p2 == 4'd4) && ftb_is_call_p2
          && ftb_is_ret_p2 && ftb_is_jalr_p2);
    check("F1 J2 after J1: the target is still J1's",
          ftb_jmp_target_p2
            == exp_jmp_tgt(j1, base + VA_WIDTH'(4 << POS_OFFSET_BITS)));
    check("F1 J2 after J1: the end is still J1's",
          ftb_pft_addr_p2 == base + VA_WIDTH'('d12));
    upd_jmp(base, 1'b1, 2'd1, j2, 1'b0, 1'b1, 1'b1, 4'd2,
            base + VA_WIDTH'('d8));
    predict(base);
    check("F1 a jump before the stored one replaces it: pos 2, RETURN",
          ftb_jmp_valid_p2 && (ftb_jmp_pos_p2 == 4'd2) && !ftb_is_call_p2
          && ftb_is_ret_p2 && ftb_is_jalr_p2);
    check("F1 its target, from its own PC",
          ftb_jmp_target_p2
            == exp_jmp_tgt(j2, base + VA_WIDTH'(2 << POS_OFFSET_BITS)));
    // 5.5: pftAddr recomputed when the boundary moves.
    check("F1 the block end moved to the new jump's end",
          ftb_pft_addr_p2 == base + VA_WIDTH'('d8));

    // F2: a conditional at a new position with every field filled.
    // Two slots: br0 at pos 3 (taken, trained to conf 6) and br1 at pos
    // 7; a branch at pos 9 resolves not taken on port slot 0. It is a
    // new branch above both: the entry keeps 3 and 7 untouched, and the
    // end becomes pos 9's PC (the split, BP-140). At one slot the entry
    // holds pos 3 alone after the pos 7 branch splits it, and pos 9 is
    // past that end and changes nothing.
    // OLD (BP-120 to BP-140): br0 refilled with pos 9 (weak not-taken,
    // its own target) and the order swap read the old br1 in slot 0
    // and the new branch in slot 1. Before BP-120 br0 was updated in
    // place: pos 3 kept, conf stepped 6 -> 5.
    do_reset();
    base = make_pc(26'h000702, 9'd141);
    tgt  = base + VA_WIDTH'('h500);
    upd_br(base, 1'b0, 2'd2, 1'b0, 1'b1, tgt, 4'd3, base + VA_WIDTH'('d32));
    train_br(base, 2'd2, 1'b0, 1'b1, 2, tgt, 4'd3, base + VA_WIDTH'('d32));
    upd_br(base, 1'b1, 2'd2, 1'b1, 1'b0, base + VA_WIDTH'('h700), 4'd7,
           base + VA_WIDTH'('d32));
    predict(base);
    check("F2 set-up: br0 pos 3 conf 6",
          ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd3)
          && (ftb_br0_conf_p2 == 3'd6));
    if (NS > 1)
      check("F2 set-up: br1 pos 7 conf 3", ftb_br1_valid_p2
            && (ftb_br1_pos_p2 == 4'd7)
            && (ftb_br1_conf_p2 == FTB_CONF_INIT_NTK));
    upd_br(base, 1'b1, 2'd2, 1'b0, 1'b0, base + VA_WIDTH'('h900), 4'd9,
           base + VA_WIDTH'('d32));
    predict(base);
    check("F2 br0 is still pos 3, conf 6, its target",
          ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd3)
          && (ftb_br0_conf_p2 == 3'd6) && (ftb_br0_target_p2 == tgt));
    if (NS > 1) begin
      check("F2 br1 is still pos 7, conf untouched",
            ftb_br1_valid_p2 && (ftb_br1_pos_p2 == 4'd7)
            && (ftb_br1_conf_p2 == FTB_CONF_INIT_NTK));
      check("F2 the pos 9 branch is not stored; the end is its PC",
            ftb_pft_addr_p2 == pos_pc(base, 4'd9));
    end else begin
      check("F2 one slot: the end stays at the pos 7 branch PC",
            ftb_pft_addr_p2 == pos_pc(base, 4'd7));
    end

    // F2b: a new position below a held branch. br0 at pos 5 alone; a
    // branch at pos 2 resolves on slot 0. Two slots: it fills a field
    // and the order is restored: slot 0 is the new branch (pos 2, weak
    // taken), slot 1 the pos 5 branch with its conf. One slot: the pos
    // 2 branch is kept and the pos 5 branch falls out (the end moves
    // to its PC, BP-140). Before BP-120 br0 was updated in place at
    // pos 5.
    do_reset();
    base = make_pc(26'h000703, 9'd142);
    upd_br(base, 1'b0, 2'd0, 1'b0, 1'b0, base + VA_WIDTH'('h300), 4'd5,
           base + VA_WIDTH'('d32));
    upd_br(base, 1'b1, 2'd0, 1'b0, 1'b1, base + VA_WIDTH'('h200), 4'd2,
           base + VA_WIDTH'('d32));
    predict(base);
    check("F2b slot 0 is the new branch: pos 2, weak taken",
          ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd2)
          && (ftb_br0_conf_p2 == FTB_CONF_INIT_TKN));
    if (NS > 1)
      check("F2b slot 1 is the pos 5 branch, conf 011 untouched",
            ftb_br1_valid_p2 && (ftb_br1_pos_p2 == 4'd5)
            && (ftb_br1_conf_p2 == FTB_CONF_INIT_NTK));
    else
      check("F2b one slot: the pos 5 branch fell out, end = its PC",
            !ftb_br1_valid_p2 && (ftb_pft_addr_p2 == pos_pc(base, 4'd5)));

    // F3: the same branch resolving again: conf steps, the target is
    // rewritten when it differs, the position is kept, as before
    // BP-120. Then (two slots) the pos 7 branch resolves on slot 0, the
    // wrong port slot (an entry read before the order changed): the
    // stored position, not the slot, names it, so br1 steps and br0
    // does not. Before BP-120 the slot named br0, which stepped in
    // place. At one slot pos 7 splits the entry (SP1) and is not
    // trained.
    do_reset();
    base = make_pc(26'h000704, 9'd143);
    upd_br(base, 1'b0, 2'd3, 1'b0, 1'b1, base + VA_WIDTH'('h100), 4'd3,
           base + VA_WIDTH'('d32));
    upd_br(base, 1'b1, 2'd3, 1'b1, 1'b0, base + VA_WIDTH'('h700), 4'd7,
           base + VA_WIDTH'('d32));
    upd_br(base, 1'b1, 2'd3, 1'b0, 1'b1, base + VA_WIDTH'('h180), 4'd3,
           base + VA_WIDTH'('d32));
    predict(base);
    check("F3 same branch: conf steps 4 -> 5",
          ftb_br0_conf_p2 == 3'd5);
    check("F3 same branch: target rewritten",
          ftb_br0_target_p2 == base + VA_WIDTH'('h180));
    check("F3 same branch: position kept (3)",
          ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd3));
    if (NS > 1) begin
      upd_br(base, 1'b1, 2'd3, 1'b0, 1'b0, base + VA_WIDTH'('h700), 4'd7,
             base + VA_WIDTH'('d32));
      predict(base);
      check("F3 pos 7 on slot 0: br1 steps 3 -> 2",
            ftb_br1_valid_p2 && (ftb_br1_pos_p2 == 4'd7)
            && (ftb_br1_conf_p2 == 3'd2));
      check("F3 and br0 is untouched (pos 3, conf 5)",
            ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd3)
            && (ftb_br0_conf_p2 == 3'd5));
    end

    // F4: the same jump resolving again keeps its position and
    // rewrites its target (5.5 jump target, IC-FTB-01).
    do_reset();
    base = make_pc(26'h000705, 9'd144);
    upd_jmp(base, 1'b0, 2'd0, base + VA_WIDTH'('h800), 1'b0, 1'b0, 1'b1,
            4'd6, base + VA_WIDTH'('d16));
    upd_jmp(base, 1'b1, 2'd0, base + VA_WIDTH'('h880), 1'b0, 1'b0, 1'b1,
            4'd6, base + VA_WIDTH'('d16));
    predict(base);
    check("F4 same jump: pos kept (6), target is the latest",
          ftb_jmp_valid_p2 && (ftb_jmp_pos_p2 == 4'd6)
          && (ftb_jmp_target_p2 == base + VA_WIDTH'('h880)));

    // =============================================================
    // Group G (BP-121). Each case from reset and a driven sequence.
    // =============================================================

    // G1, TD#163: an update carrying a stale MISS (its prediction did
    // not find the entry) names a way another update has since
    // allocated with the same tag. It merges: the entry keeps the
    // conditional the first update wrote and gains the jump. Before
    // BP-121 the carried miss re-allocated a zeroed entry over it and
    // the conditional was lost.
    do_reset();
    base = make_pc(26'h000710, 9'd150);
    upd_br(base, 1'b0, 2'd1, 1'b0, 1'b1, base + VA_WIDTH'('h100), 4'd3,
           base + VA_WIDTH'('d32));
    upd_jmp(base, 1'b0, 2'd1, base + VA_WIDTH'('h900), 1'b0, 1'b0, 1'b0,
            4'd9, base + VA_WIDTH'('d20));
    predict(base);
    check("G1 stale miss merges: the conditional (pos 3) is kept",
          ftb_hit_p2 && ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd3));
    // At one slot the jump is the second branch and is split off: the
    // merge is shown by the end at its PC (a re-allocation would hold
    // the jump alone). BP-140.
    if (NS > 1)
      check("G1 stale miss merges: the jump (pos 9) is added",
            ftb_jmp_valid_p2 && (ftb_jmp_pos_p2 == 4'd9));
    else
      check("G1 stale miss merges: one slot, the jump split off at its PC",
            !ftb_jmp_valid_p2 && (ftb_pft_addr_p2 == pos_pc(base, 4'd9)));

    // G2, TD#163: an update carrying a stale HIT names a way that
    // another region (same set, different tag) has since taken. It
    // allocates: region A's entry holds only A's update. Before BP-121
    // it wrote A's tag over region B's entry and kept B's jump, so A
    // read B's jump.
    do_reset();
    base = make_pc(26'h000711, 9'd151);           // region A
    pc   = make_pc(26'h000712, 9'd151);           // region B, same set
    upd_br(base, 1'b0, 2'd2, 1'b0, 1'b1, base + VA_WIDTH'('h100), 4'd2,
           base + VA_WIDTH'('d32));
    upd_jmp(pc, 1'b0, 2'd2, pc + VA_WIDTH'('h700), 1'b0, 1'b0, 1'b0,
            4'd5, pc + VA_WIDTH'('d14));          // B takes way 2
    upd_br(base, 1'b1, 2'd2, 1'b0, 1'b1, base + VA_WIDTH'('h100), 4'd2,
           base + VA_WIDTH'('d32));               // A's stale hit
    predict(base);
    check("G2 stale hit allocates: A has its conditional",
          ftb_hit_p2 && ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd2));
    check("G2 stale hit allocates: A does not read B's jump",
          !ftb_jmp_valid_p2);

    // G3, TD#164: the jump's rvc bit is stored and read back.
    do_reset();
    base = make_pc(26'h000713, 9'd152);
    jrvc_next = 1'b1;
    upd_jmp(base, 1'b0, 2'd0, base + VA_WIDTH'('h300), 1'b1, 1'b0, 1'b1,
            4'd5, base + VA_WIDTH'('d12));
    jrvc_next = 1'b0;
    predict(base);
    check("G3 a 16-bit jump reads rvc 1",
          ftb_jmp_valid_p2 && ftb_jmp_rvc_p2);
    upd_jmp(base, 1'b1, 2'd0, base + VA_WIDTH'('h300), 1'b1, 1'b0, 1'b1,
            4'd5, base + VA_WIDTH'('d14));
    predict(base);
    check("G3 a 32-bit jump reads rvc 0",
          ftb_jmp_valid_p2 && !ftb_jmp_rvc_p2);

    // G4: a conditional after the jump of a start's block is past that
    // block's end. From one start the jump at pos 4 ends the block, so
    // a conditional resolving at pos 11 (from a block predicted before
    // the jump was stored) changes nothing (BP-140). Before BP-121 the
    // conditional (then recorded by a later start of the region) was
    // reported in slot 0 with the jump after it.
    // OLD (BP-121 to BP-140): the conditional recorded by the start at
    // base+14 into the shared entry was hidden from the base and seen
    // from base+14; per-start entries keep the two apart (R2).
    do_reset();
    base = make_pc(26'h000714, 9'd153);
    upd_jmp(base, 1'b0, 2'd0, base + VA_WIDTH'('h400), 1'b1, 1'b0, 1'b0,
            4'd4, base + VA_WIDTH'('d12));
    upd_br(base, 1'b1, 2'd0, 1'b0, 1'b1, base + VA_WIDTH'('h40), 4'd11,
           base + VA_WIDTH'('d32));
    predict(base);
    check("G4 the jump (pos 4) is kept, with its end",
          ftb_jmp_valid_p2 && (ftb_jmp_pos_p2 == 4'd4)
          && (ftb_pft_addr_p2 == base + VA_WIDTH'('d12)));
    check("G4 the conditional past the jump is not stored",
          !ftb_br0_valid_p2 && !ftb_br1_valid_p2);

    // =============================================================
    // B1: br1 counterparts (BP-126, TD#81). Each br0-alone directed
    // case above whose rule is the same for br1 is repeated with the
    // branch under test in br1 (b1_setup). Cases with no br0/br1
    // specific rule are not repeated: S1 and FP4's miss half check
    // both fastpath bits already; S4 is the br1 not-taken init (the
    // br1 half of S5 and of D3's not-taken half); S6, S7, S9-S11 and
    // P/R/J/F/G are entry, jump or position rules.
    // Two slots only since BP-140: at one slot an entry holds one
    // branch, so br1 is never stored or reported (group SP).
    // =============================================================
    if (NS > 1) begin
      // B1-S2: allocate-then-hit, br1 valid, target round-trip.
      do_reset();
      pc   = make_pc(26'h000B01, 9'd200);
      b1pc = pc + VA_WIDTH'(B1_POS << POS_OFFSET_BITS);
      tgt  = b1pc + VA_WIDTH'('h100);
      b1_setup(pc, 2'd2, 1'b1, tgt);
      predict(pc);
      check("B1-S2 valid on hit, way 2", ftb_valid_p2 && (ftb_way_p2 == 2'd2));
      check("B1-S2 br1 valid",            ftb_br1_valid_p2 == 1'b1);
      check("B1-S2 br1 target round-trip",
            ftb_br1_target_p2 == exp_br_tgt(tgt, b1pc));

      // B1-S3: update in place, br1 conf steps 4 -> 5, no realloc.
      check("B1-S3 br1 alloc conf==INIT_TKN",
            ftb_br1_conf_p2 == FTB_CONF_INIT_TKN);
      upd_br(pc, 1'b1, 2'd2, 1'b1, 1'b1, tgt, B1_POS, pc);
      predict(pc);
      check("B1-S3 in-place: way unchanged, valid",
            (ftb_way_p2 == 2'd2) && ftb_valid_p2);
      check("B1-S3 br1 conf stepped 4->5", ftb_br1_conf_p2 == 3'd5);
      check("B1-S3 br0 untouched (conf INIT_TKN)",
            ftb_br0_conf_p2 == FTB_CONF_INIT_TKN);

      // B1-S8: br1 target encode from its own PC: in range, the fit
      // boundary, negative, and overflow wrapping per the encode.
      do_reset();
      pc   = make_pc(26'h000B08, 9'd201);
      b1pc = pc + VA_WIDTH'(B1_POS << POS_OFFSET_BITS);
      b1_setup(pc, 2'd0, 1'b1, b1pc + VA_WIDTH'('h400));
      predict(pc);
      check("B1-S8 in-range +0x400 lossless",
            ftb_br1_target_p2 == b1pc + VA_WIDTH'('h400));
      upd_br(pc, 1'b1, 2'd0, 1'b1, 1'b1, b1pc + VA_WIDTH'('h0FFF), B1_POS, pc);
      predict(pc);
      check("B1-S8 max in-range +0xFFF lossless",
            ftb_br1_target_p2 == b1pc + VA_WIDTH'('h0FFF));
      upd_br(pc, 1'b1, 2'd0, 1'b1, 1'b1, b1pc - VA_WIDTH'('h400), B1_POS, pc);
      predict(pc);
      check("B1-S8 negative in-range -0x400 lossless",
            ftb_br1_target_p2 == b1pc - VA_WIDTH'('h400));
      upd_br(pc, 1'b1, 2'd0, 1'b1, 1'b1, b1pc + VA_WIDTH'('h1000), B1_POS, pc);
      predict(pc);
      check("B1-S8 overflow +0x1000 wraps per encode",
            ftb_br1_target_p2 == exp_br_tgt(b1pc + VA_WIDTH'('h1000), b1pc));
      check("B1-S8 overflow read-back != true target",
            ftb_br1_target_p2 != (b1pc + VA_WIDTH'('h1000)));

      // B1-D1: br1 direction is its conf MSB, both polarities.
      do_reset();
      pc   = make_pc(26'h000B11, 9'd202);
      b1pc = pc + VA_WIDTH'(B1_POS << POS_OFFSET_BITS);
      tgt  = b1pc + VA_WIDTH'('h40);
      b1_setup(pc, 2'd0, 1'b1, tgt);                     // conf 4
      predict(pc);
      check("B1-D1 MSB=1 -> taken", ftb_br1_taken_p2 == 1'b1);
      check("B1-D1 taken == valid & conf MSB",
            ftb_br1_taken_p2 ==
              (ftb_br1_valid_p2 & ftb_br1_conf_p2[FTB_CONF_WIDTH-1]));
      upd_br(pc, 1'b1, 2'd0, 1'b1, 1'b0, tgt, B1_POS, pc);  // 4 -> 3
      predict(pc);
      check("B1-D1 MSB=0 -> not-taken", ftb_br1_taken_p2 == 1'b0);
      check("B1-D1 not-taken == valid & conf MSB",
            ftb_br1_taken_p2 ==
              (ftb_br1_valid_p2 & ftb_br1_conf_p2[FTB_CONF_WIDTH-1]));

      // B1-D2: br1 saturates at 111 and at 000, no wrap.
      do_reset();
      pc   = make_pc(26'h000B12, 9'd203);
      b1pc = pc + VA_WIDTH'(B1_POS << POS_OFFSET_BITS);
      tgt  = b1pc + VA_WIDTH'('h40);
      b1_setup(pc, 2'd0, 1'b1, tgt);
      train_br(pc, 2'd0, 1'b1, 1'b1, 4, tgt, B1_POS, pc); // 4 -> 7, +1
      predict(pc);
      check("B1-D2 taken saturates at 111, no wrap",
            ftb_br1_conf_p2 == CONF_SAT_T);
      train_br(pc, 2'd0, 1'b1, 1'b0, 8, tgt, B1_POS, pc); // 7 -> 0, +1
      predict(pc);
      check("B1-D2 not-taken saturates at 000, no wrap",
            ftb_br1_conf_p2 == CONF_SAT_N);

      // B1-D3: br1 taken alloc -> INIT_TKN; a fresh br1 does not fast-path
      // (both directions, en=1).
      do_reset();
      cfg_ftb_fastpath_en(1'b1);
      pc   = make_pc(26'h000B13, 9'd204);
      b1pc = pc + VA_WIDTH'(B1_POS << POS_OFFSET_BITS);
      b1_setup(pc, 2'd0, 1'b1, b1pc + VA_WIDTH'('h40));
      predict(pc);
      check("B1-D3 br1 taken init conf==3'b100",
            ftb_br1_conf_p2 == FTB_CONF_INIT_TKN);
      check("B1-D3 fresh taken br1 does NOT fast-path",
            ftb_fastpath_p2[1] == 1'b0);
      pc   = make_pc(26'h000B14, 9'd205);
      b1pc = pc + VA_WIDTH'(B1_POS << POS_OFFSET_BITS);
      b1_setup(pc, 2'd0, 1'b0, b1pc + VA_WIDTH'('h40));
      predict(pc);
      check("B1-D3 br1 ntkn init conf==3'b011",
            ftb_br1_conf_p2 == FTB_CONF_INIT_NTK);
      check("B1-D3 fresh ntkn br1 does NOT fast-path",
            ftb_fastpath_p2[1] == 1'b0);
      cfg_ftb_fastpath_en(1'b0);

      // B1-D4: br1 self-correction: 111 fires, 110 stops, 111 again.
      do_reset();
      pc   = make_pc(26'h000B15, 9'd206);
      b1pc = pc + VA_WIDTH'(B1_POS << POS_OFFSET_BITS);
      tgt  = b1pc + VA_WIDTH'('h40);
      b1_setup(pc, 2'd0, 1'b1, tgt);
      train_br(pc, 2'd0, 1'b1, 1'b1, 3, tgt, B1_POS, pc); // -> 7
      cfg_ftb_fastpath_en(1'b1);
      predict(pc);
      check("B1-D4 br1 saturated, fast-path[1] fires",
            (ftb_br1_conf_p2 == CONF_SAT_T) && (ftb_fastpath_p2[1] == 1'b1));
      upd_br(pc, 1'b1, 2'd0, 1'b1, 1'b0, tgt, B1_POS, pc); // 7 -> 6
      predict(pc);
      check("B1-D4 mispredict 111->110, fast-path[1] stops",
            (ftb_br1_conf_p2 == 3'd6) && (ftb_fastpath_p2[1] == 1'b0));
      upd_br(pc, 1'b1, 2'd0, 1'b1, 1'b1, tgt, B1_POS, pc); // 6 -> 7
      predict(pc);
      check("B1-D4 re-saturates, fast-path[1] fires again",
            (ftb_br1_conf_p2 == CONF_SAT_T) && (ftb_fastpath_p2[1] == 1'b1));
      cfg_ftb_fastpath_en(1'b0);

      // B1-D5: reallocation resets br1 conf to the new weak init.
      do_reset();
      pcA = make_pc(26'h000B1A, 9'd207);
      pcB = make_pc(26'h000B1B, 9'd207);    // same set, different tag
      b1pc = pcA + VA_WIDTH'(B1_POS << POS_OFFSET_BITS);
      b1_setup(pcA, 2'd0, 1'b1, b1pc + VA_WIDTH'('h40));
      train_br(pcA, 2'd0, 1'b1, 1'b1, 3, b1pc + VA_WIDTH'('h40), B1_POS, pcA);
      predict(pcA);
      check("B1-D5 A br1 saturated before realloc",
            ftb_br1_conf_p2 == CONF_SAT_T);
      b1pc = pcB + VA_WIDTH'(B1_POS << POS_OFFSET_BITS);
      upd_br(pcB, 1'b0, 2'd0, 1'b0, 1'b1, pcB + VA_WIDTH'('h40), 4'd0, pcB);
      upd_br(pcB, 1'b1, 2'd0, 1'b1, 1'b0, b1pc + VA_WIDTH'('h40), B1_POS, pcB);
      predict(pcB);
      check("B1-D5 B br1 conf == new weak init (011)",
            ftb_br1_valid_p2 && (ftb_br1_conf_p2 == FTB_CONF_INIT_NTK));
      predict(pcA);
      check("B1-D5 A evicted by realloc", ftb_valid_p2 == 1'b0);

      // B1-FP1, FP2, FP3, FP5: br1 fast-path only with en=1, conf
      // saturated, valid and br1_valid; direction-only (target intact).
      do_reset();
      pc   = make_pc(26'h000B21, 9'd208);
      b1pc = pc + VA_WIDTH'(B1_POS << POS_OFFSET_BITS);
      tgt  = b1pc + VA_WIDTH'('h300);
      b1_setup(pc, 2'd0, 1'b1, tgt);
      cfg_ftb_fastpath_en(1'b1);
      predict(pc);
      check("B1-FP3 no fire when br1 unsaturated (==4)",
            (ftb_br1_conf_p2 == FTB_CONF_INIT_TKN) && !ftb_fastpath_p2[1]);
      train_br(pc, 2'd0, 1'b1, 1'b1, 3, tgt, B1_POS, pc); // -> 7
      predict(pc);
      check("B1-FP1 fast-path[1] fires: valid+br1_valid+sat+en",
            ftb_valid_p2 && ftb_br1_valid_p2 && (ftb_br1_conf_p2 == CONF_SAT_T)
            && (ftb_fastpath_p2[1] == 1'b1));
      check("B1-FP1 br0 unsaturated: fast-path[0] clear",
            ftb_fastpath_p2[0] == 1'b0);
      check("B1-FP5 br1 target intact under fast-path",
            ftb_br1_target_p2 == tgt);
      cfg_ftb_fastpath_en(1'b0);
      predict(pc);
      check("B1-FP2 no fire at en=0, br1 still saturated",
            (ftb_br1_conf_p2 == CONF_SAT_T) && !ftb_fastpath_p2[1]);

      // B1-FP4: an empty br1 field never fast-paths, even with br0
      // saturated and en=1.
      do_reset();
      pc  = make_pc(26'h000B24, 9'd209);
      tgt = pc + VA_WIDTH'('h40);
      upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 4'd0, pc);
      train_br(pc, 2'd0, 1'b0, 1'b1, 3, tgt, 4'd0, pc);  // br0 -> 7
      cfg_ftb_fastpath_en(1'b1);
      predict(pc);
      check("B1-FP4 empty br1 field invalid", ftb_br1_valid_p2 == 1'b0);
      check("B1-FP4 empty br1: fast-path[1] clear, br0 fires",
            (ftb_fastpath_p2[1] == 1'b0) && (ftb_fastpath_p2[0] == 1'b1));
      cfg_ftb_fastpath_en(1'b0);
    end // NS > 1, group B1

    // =============================================================
    // SP: THE SPLIT AT UPDATE (BP-140, Problem 2, ruled by Jeff
    // 2026-10-18). An entry never holds more than NUM_PRED_SLOTS
    // branches. When an update would make it hold more, the lowest
    // positions are kept and the end becomes the PC of the lowest
    // position not kept; a jump not kept clears the jump field. The
    // result does not depend on the order in which the branches of a
    // block resolve. Every case: reset, then the updates named, carried
    // way 0 (carried hit 0 on the first, 1 after; the current-state
    // check of TD#163 decides). Each fails on the starting tree, which
    // stores up to two conditionals and a jump at both slot counts and
    // writes each update's end.
    // =============================================================
    begin
      ftb_view_t v_ref;
      ftb_view_t v_got;
      // The three conditional positions of SP3 and their resolution
      // orders: every permutation of {0, 1, 2}.
      int perm [6][3];
      logic [FTB_BR_POS_BITS-1:0] cpos [3];
      logic                       cdir [3];
      logic [VA_WIDTH-1:0]        ctgt [3];
      perm[0] = '{0, 1, 2}; perm[1] = '{0, 2, 1}; perm[2] = '{1, 0, 2};
      perm[3] = '{1, 2, 0}; perm[4] = '{2, 0, 1}; perm[5] = '{2, 1, 0};

      // SP1, one slot: {conditional at pos a} stored, then a
      // conditional at pos b > a resolves. The entry keeps a and the
      // end is the PC of b. The reverse order gives the same entry.
      if (NS == 1) begin
        pc = make_pc(26'h000801, 9'd160);
        do_reset();
        upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, pc + VA_WIDTH'('h100), 4'd2,
               pc + VA_WIDTH'(FTB_BLOCK_BYTES));
        upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b0, pc + VA_WIDTH'('h200), 4'd7,
               pc + VA_WIDTH'(FTB_BLOCK_BYTES));
        predict(pc);
        v_ref = view();
        check("SP1 a then b: a kept (pos 2, weak taken, its target)",
              ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd2)
              && (ftb_br0_conf_p2 == FTB_CONF_INIT_TKN)
              && (ftb_br0_target_p2 == pc + VA_WIDTH'('h100)));
        check("SP1 a then b: b not stored, no jump",
              !ftb_br1_valid_p2 && !ftb_jmp_valid_p2);
        check("SP1 a then b: the end is the PC of b",
              ftb_pft_addr_p2 == pos_pc(pc, 4'd7));
        do_reset();
        upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b0, pc + VA_WIDTH'('h200), 4'd7,
               pc + VA_WIDTH'(FTB_BLOCK_BYTES));
        upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, pc + VA_WIDTH'('h100), 4'd2,
               pc + VA_WIDTH'(FTB_BLOCK_BYTES));
        predict(pc);
        v_got = view();
        check("SP1 b then a: the same entry", v_got == v_ref);

        // SP2, one slot: {conditional at 2, jump at 6}. The end is the
        // jump PC and the jump field is cleared, in both orders.
        do_reset();
        upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, pc + VA_WIDTH'('h100), 4'd2,
               pc + VA_WIDTH'(FTB_BLOCK_BYTES));
        upd_jmp(pc, 1'b1, 2'd0, pc + VA_WIDTH'('h900), 1'b1, 1'b0, 1'b0,
                4'd6, pos_pc(pc, 4'd6) + VA_WIDTH'('d4));
        predict(pc);
        v_ref = view();
        check("SP2 cond then jump: the conditional kept",
              ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd2));
        check("SP2 cond then jump: the jump field is cleared",
              !ftb_jmp_valid_p2 && !ftb_is_call_p2);
        check("SP2 cond then jump: the end is the jump PC",
              ftb_pft_addr_p2 == pos_pc(pc, 4'd6));
        do_reset();
        upd_jmp(pc, 1'b0, 2'd0, pc + VA_WIDTH'('h900), 1'b1, 1'b0, 1'b0,
                4'd6, pos_pc(pc, 4'd6) + VA_WIDTH'('d4));
        predict(pc);
        check("SP2 jump alone: stored, end is its own end",
              ftb_jmp_valid_p2 && (ftb_jmp_pos_p2 == 4'd6)
              && (ftb_pft_addr_p2 == pos_pc(pc, 4'd6) + VA_WIDTH'('d4)));
        upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, pc + VA_WIDTH'('h100), 4'd2,
               pc + VA_WIDTH'(FTB_BLOCK_BYTES));
        predict(pc);
        v_got = view();
        check("SP2 jump then cond: the same entry", v_got == v_ref);
      end

      // SP3, two slots: three conditionals, all six resolution orders.
      // The entry keeps the two lowest positions and the end is the
      // third's PC.
      if (NS > 1) begin
        pc      = make_pc(26'h000802, 9'd161);
        cpos[0] = 4'd1;  cdir[0] = 1'b1; ctgt[0] = pc + VA_WIDTH'('h100);
        cpos[1] = 4'd4;  cdir[1] = 1'b0; ctgt[1] = pc + VA_WIDTH'('h200);
        cpos[2] = 4'd11; cdir[2] = 1'b1; ctgt[2] = pc + VA_WIDTH'('h300);
        for (int o = 0; o < 6; o++) begin
          do_reset();
          for (int i = 0; i < 3; i++)
            upd_br(pc, (i > 0), 2'd0, 1'b0, cdir[perm[o][i]],
                   ctgt[perm[o][i]], cpos[perm[o][i]],
                   pc + VA_WIDTH'(FTB_BLOCK_BYTES));
          predict(pc);
          v_got = view();
          if (o == 0) begin
            v_ref = v_got;
            check("SP3 br0 is pos 1, weak taken, its target",
                  ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd1)
                  && (ftb_br0_conf_p2 == FTB_CONF_INIT_TKN)
                  && (ftb_br0_target_p2 == ctgt[0]));
            check("SP3 br1 is pos 4, weak not taken, its target",
                  ftb_br1_valid_p2 && (ftb_br1_pos_p2 == 4'd4)
                  && (ftb_br1_conf_p2 == FTB_CONF_INIT_NTK)
                  && (ftb_br1_target_p2 == ctgt[1]));
            check("SP3 no jump; the end is the PC of pos 11",
                  !ftb_jmp_valid_p2
                  && (ftb_pft_addr_p2 == pos_pc(pc, 4'd11)));
          end else begin
            check($sformatf("SP3 order %0d%0d%0d: the same entry",
                            perm[o][0], perm[o][1], perm[o][2]),
                  v_got == v_ref);
          end
        end

        // SP4, two slots: {conditional, conditional, jump}, all six
        // orders. The end is the jump PC and the jump field is cleared.
        cpos[0] = 4'd1;  cpos[1] = 4'd4;  cpos[2] = 4'd9;
        for (int o = 0; o < 6; o++) begin
          do_reset();
          for (int i = 0; i < 3; i++) begin
            if (perm[o][i] == 2)
              upd_jmp(pc, (i > 0), 2'd0, pc + VA_WIDTH'('h900), 1'b0, 1'b0,
                      1'b0, 4'd9, pos_pc(pc, 4'd9) + VA_WIDTH'('d4));
            else
              upd_br(pc, (i > 0), 2'd0, 1'b0, cdir[perm[o][i]],
                     ctgt[perm[o][i]], cpos[perm[o][i]],
                     pc + VA_WIDTH'(FTB_BLOCK_BYTES));
          end
          predict(pc);
          v_got = view();
          if (o == 0) begin
            v_ref = v_got;
            check("SP4 the conditionals at 1 and 4 are kept",
                  ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd1)
                  && ftb_br1_valid_p2 && (ftb_br1_pos_p2 == 4'd4));
            check("SP4 the jump field is cleared",
                  !ftb_jmp_valid_p2);
            check("SP4 the end is the jump PC",
                  ftb_pft_addr_p2 == pos_pc(pc, 4'd9));
          end else begin
            check($sformatf("SP4 order %0d%0d%0d: the same entry",
                            perm[o][0], perm[o][1], perm[o][2]),
                  v_got == v_ref);
          end
        end
      end

      // SP5, both slot counts: a new branch below every held branch,
      // the entry full. It is kept, the highest held branch falls out,
      // and the end moves down to the PC of the one that fell out. Two
      // slots: {cond 3, jump 7} (end the jump's own, pos 7 + 4 bytes),
      // then cond 1: {1, 3}, the jump falls out, end PC(7). One slot:
      // {cond 5} (end start + 32), then cond 2: {2}, end PC(5).
      pc = make_pc(26'h000803, 9'd162);
      do_reset();
      if (NS > 1) begin
        upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, pc + VA_WIDTH'('h100), 4'd3,
               pc + VA_WIDTH'(FTB_BLOCK_BYTES));
        upd_jmp(pc, 1'b1, 2'd0, pc + VA_WIDTH'('h900), 1'b0, 1'b0, 1'b0,
                4'd7, pos_pc(pc, 4'd7) + VA_WIDTH'('d4));
        predict(pc);
        check("SP5 set-up: {cond 3, jump 7}, end after the jump",
              ftb_br0_valid_p2 && ftb_jmp_valid_p2
              && (ftb_pft_addr_p2 == pos_pc(pc, 4'd7) + VA_WIDTH'('d4)));
        upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b0, pc + VA_WIDTH'('h80), 4'd1,
               pc + VA_WIDTH'(FTB_BLOCK_BYTES));
        predict(pc);
        check("SP5 the new branch (pos 1) is kept in br0",
              ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd1));
        check("SP5 the pos 3 branch moves to br1",
              ftb_br1_valid_p2 && (ftb_br1_pos_p2 == 4'd3));
        check("SP5 the jump fell out; the end moved down to its PC",
              !ftb_jmp_valid_p2 && (ftb_pft_addr_p2 == pos_pc(pc, 4'd7)));
      end else begin
        upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, pc + VA_WIDTH'('h100), 4'd5,
               pc + VA_WIDTH'(FTB_BLOCK_BYTES));
        upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b0, pc + VA_WIDTH'('h80), 4'd2,
               pc + VA_WIDTH'(FTB_BLOCK_BYTES));
        predict(pc);
        check("SP5 the new branch (pos 2) is kept",
              ftb_br0_valid_p2 && (ftb_br0_pos_p2 == 4'd2));
        check("SP5 the pos 5 branch fell out; the end moved down to it",
              !ftb_br1_valid_p2 && (ftb_pft_addr_p2 == pos_pc(pc, 4'd5)));
      end
      v_ref = view();

      // SP6: the branch that falls out, resolving later in a block from
      // its own start, allocates its own entry there (pos 0) and is
      // predicted from it. The first start's entry is unchanged.
      jpc = (NS > 1) ? pos_pc(pc, 4'd7) : pos_pc(pc, 4'd5);
      if (NS > 1)
        upd_jmp(jpc, 1'b0, 2'd0, pc + VA_WIDTH'('h900), 1'b0, 1'b0, 1'b0,
                4'd0, jpc + VA_WIDTH'('d4));
      else
        upd_br(jpc, 1'b0, 2'd0, 1'b0, 1'b1, pc + VA_WIDTH'('h100), 4'd0,
               jpc + VA_WIDTH'(FTB_BLOCK_BYTES));
      predict(jpc);
      check("SP6 the fallen-out branch has its own entry at its PC",
            ftb_hit_p2 && ((NS > 1) ? (ftb_jmp_valid_p2
                                       && (ftb_jmp_pos_p2 == 4'd0)
                                       && (ftb_jmp_target_p2
                                           == pc + VA_WIDTH'('h900)))
                                    : (ftb_br0_valid_p2
                                       && (ftb_br0_pos_p2 == 4'd0)
                                       && (ftb_br0_target_p2
                                           == pc + VA_WIDTH'('h100)))));
      predict(pc);
      v_got = view();
      check("SP6 the first start's entry is unchanged", v_got == v_ref);

      // SP7: past the end. After SP5, a resolution of the fallen-out
      // branch from the first start (a block predicted before the
      // split), and a kept branch resolving again with that block's
      // longer predicted end, leave the entry as it is: the end only
      // moves down. On the starting tree each update rewrote the end.
      if (NS > 1)
        upd_jmp(pc, 1'b1, 2'd0, pc + VA_WIDTH'('h900), 1'b0, 1'b0, 1'b0,
                4'd7, pos_pc(pc, 4'd7) + VA_WIDTH'('d4));
      else
        upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, pc + VA_WIDTH'('h100), 4'd5,
               pc + VA_WIDTH'(FTB_BLOCK_BYTES));
      predict(pc);
      v_got = view();
      check("SP7 the fallen-out branch from the first start: no change",
            v_got == v_ref);
      upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b0, pc + VA_WIDTH'('h80),
             (NS > 1) ? 4'd1 : 4'd2, pc + VA_WIDTH'(FTB_BLOCK_BYTES));
      predict(pc);
      check("SP7 a kept branch with a longer predicted end: end kept",
            ftb_pft_addr_p2 == v_ref.pft);
      check("SP7 and it trained in place (conf 3 -> 2)",
            ftb_br0_conf_p2 == 3'd2);
    end

    // -------------------------------------------------------------
    $display("=================================================");
    $display("tb_ftb: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    $display("=================================================");
    if (fail_cnt != 0)
      $fatal(1, "tb_ftb: %0d checks failed", fail_cnt);
    else
      $finish;
  end

  // Watchdog
  initial begin
    #500000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "tb_ftb: timeout");
  end

endmodule
