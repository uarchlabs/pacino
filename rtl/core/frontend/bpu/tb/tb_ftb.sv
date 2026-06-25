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
// P (position), I (invariant). WAIVED here (BP-068 Constraints):
// flush (IC-FTB-07), FTQ round-trip / carried-way timing (IC-FTB-10),
// concurrent same-cycle predict+update arbitration (IC-FTB-09).
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

  logic [VA_WIDTH-1:0]        ftb_pft_addr_p2;

  logic [1:0]                 ftb_fastpath_p2;
  logic                       ftb_fastpath_en;

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
    .ftb_pft_addr_p2       (ftb_pft_addr_p2),
    .ftb_fastpath_p2       (ftb_fastpath_p2),
    .ftb_fastpath_en       (ftb_fastpath_en),
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

  // Build a block-aligned PC from a tag and a set index. tag occupies
  // PC[39:14], idx PC[13:5], block offset PC[4:0] = 0.
  function automatic logic [VA_WIDTH-1:0] make_pc(
      input logic [FTB_TAG_BITS-1:0] tag,
      input logic [FTB_IDX_BITS-1:0] idx);
    make_pc = {tag, idx, {FTB_OFFSET_BITS{1'b0}}};
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
  function automatic logic [VA_WIDTH-1:0] exp_jmp_tgt(
      input logic [VA_WIDTH-1:0] tgt, input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0]         d;
    logic [FTB_JMP_TGT_BITS-1:0] disp;
    d    = tgt - base;
    disp = d[FTB_JMP_TGT_BITS-1:0];
    exp_jmp_tgt = base
      + {{(VA_WIDTH-FTB_JMP_TGT_BITS){disp[FTB_JMP_TGT_BITS-1]}}, disp};
  endfunction

  // Expected fallthrough read-back from a full-VA block end. Mirrors
  // the ftb_cntrl reduce (pftAddr + carry) and the reconstruct.
  function automatic logic [VA_WIDTH-1:0] exp_pft(
      input logic [VA_WIDTH-1:0] pft_in, input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0]    off;
    logic [PFTADDR_BITS-1:0] pidx;
    logic                   carry;
    off   = pft_in - base;
    pidx  = {{(PFTADDR_BITS-(FTB_OFFSET_BITS-INST_OFFSET)){1'b0}},
             off[FTB_OFFSET_BITS-1:INST_OFFSET]};
    carry = |off[VA_WIDTH-1:FTB_OFFSET_BITS];
    exp_pft = base
      + ({{(VA_WIDTH-PFTADDR_BITS){1'b0}}, pidx} << INST_OFFSET)
      + (carry ? VA_WIDTH'(FTB_BLOCK_BYTES) : VA_WIDTH'(0));
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
    ftb_fastpath_en = 1'b0;
    ftb_flush_px    = 1'b0;
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
  logic [VA_WIDTH-1:0] s6_pc [0:4];

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
    tgt = pc + 40'h100;
    upd_br(pc, 1'b0, 2'd2, 1'b0, 1'b1, tgt, 3'd1, pc); // alloc way2 br0 tkn
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
    tgt = pc + 40'h80;
    upd_br(pc, 1'b0, 2'd1, 1'b0, 1'b1, tgt, 3'd0, pc); // alloc way1 conf=4
    predict(pc);
    check("S3 alloc conf==INIT_TKN", ftb_br0_conf_p2 == FTB_CONF_INIT_TKN);
    upd_br(pc, 1'b1, 2'd1, 1'b0, 1'b1, tgt, 3'd0, pc); // in-place tkn ->5
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
    tgt = pc + 40'h40;
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 3'd2, pc); // alloc br0 tkn
    upd_br(pc, 1'b1, 2'd0, 1'b1, 1'b0, tgt, 3'd4, pc); // free br1 ntkn
    predict(pc);
    check("S4 br0 still valid",  ftb_br0_valid_p2 == 1'b1);
    check("S4 br1 now valid",    ftb_br1_valid_p2 == 1'b1);
    check("S4 br1 conf==INIT_NTK", ftb_br1_conf_p2 == FTB_CONF_INIT_NTK);
    check("S4 br1 not-taken (MSB=0)", ftb_br1_taken_p2 == 1'b0);

    // =============================================================
    // S5: track-every-branch -- a not-taken conditional is allocated
    // and tracked, not dropped (5.2).
    // =============================================================
    do_reset();
    pc  = make_pc(26'h0000D4, 9'd13);
    tgt = pc + 40'h60;
    upd_br(pc, 1'b0, 2'd3, 1'b0, 1'b0, tgt, 3'd1, pc); // alloc ntkn
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
      s6_pc[w] = make_pc(26'h000100 + FTB_TAG_BITS'(w), 9'd21);
    for (int w = 0; w < 4; w++)
      upd_br(s6_pc[w], 1'b0, w[FTB_WAY_BITS-1:0], 1'b0, 1'b1,
             s6_pc[w] + 40'h20, 3'd0, s6_pc[w]); // alloc way w
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
    upd_br(s6_pc[4], 1'b0, 2'd0, 1'b0, 1'b1, s6_pc[4] + 40'h20, 3'd0,
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
    j1 = pc + 40'h200;
    j2 = pc + 40'h2C0;
    upd_jmp(pc, 1'b0, 2'd0, j1, 1'b0, 1'b0, 1'b1, 3'd6, pc); // alloc jalr
    predict(pc);
    check("S7 jmp valid",            ftb_jmp_valid_p2 == 1'b1);
    check("S7 jmp target == first",  ftb_jmp_target_p2 == exp_jmp_tgt(j1, pc));
    upd_jmp(pc, 1'b1, 2'd0, j2, 1'b0, 1'b0, 1'b1, 3'd6, pc); // rewrite
    predict(pc);
    check("S7 jmp target == latest", ftb_jmp_target_p2 == exp_jmp_tgt(j2, pc));

    // =============================================================
    // S8: conditional target round-trip -- in-range lossless; beyond
    // the FTB_BR_TGT_BITS reach the read-back wraps (overflow). conf
    // does not gate the target (4.2). Rewritten in place each resolve.
    // =============================================================
    do_reset();
    pc   = make_pc(26'h000040, 9'd1);   // base 0x100020, room below
    base = pc;
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, base + 40'h400, 3'd0, pc);
    predict(pc);
    check("S8 in-range +0x400 lossless",
          ftb_br0_target_p2 == base + 40'h400);
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, base + 40'h0FFF, 3'd0, pc);
    predict(pc);
    check("S8 max in-range +0xFFF lossless (fit boundary)",
          ftb_br0_target_p2 == base + 40'h0FFF);
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, base - 40'h400, 3'd0, pc);
    predict(pc);
    check("S8 negative in-range -0x400 lossless",
          ftb_br0_target_p2 == base - 40'h400);
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, base + 40'h1000, 3'd0, pc);
    predict(pc);
    check("S8 overflow +0x1000 wraps per encode (status=overflow)",
          ftb_br0_target_p2 == exp_br_tgt(base + 40'h1000, base));
    check("S8 overflow read-back != true target (lossy past reach)",
          ftb_br0_target_p2 != (base + 40'h1000));

    // =============================================================
    // S9: jump target round-trip -- same for FTB_JMP_TGT_BITS.
    // =============================================================
    do_reset();
    pc   = make_pc(26'h000080, 9'd2);   // base 0x200040
    base = pc;
    upd_jmp(pc, 1'b0, 2'd0, base + 40'h1000, 1'b1, 1'b0, 1'b0, 3'd0, pc);
    predict(pc);
    check("S9 jmp in-range +0x1000 lossless",
          ftb_jmp_target_p2 == base + 40'h1000);
    upd_jmp(pc, 1'b1, 2'd0, base + 40'hF_FFFF, 1'b1, 1'b0, 1'b0, 3'd0, pc);
    predict(pc);
    check("S9 jmp max in-range +0xFFFFF lossless (fit boundary)",
          ftb_jmp_target_p2 == base + 40'hF_FFFF);
    upd_jmp(pc, 1'b1, 2'd0, base + 40'h10_0000, 1'b1, 1'b0, 1'b0, 3'd0, pc);
    predict(pc);
    check("S9 jmp overflow +0x100000 wraps per encode",
          ftb_jmp_target_p2 == exp_jmp_tgt(base + 40'h10_0000, base));

    // =============================================================
    // S10: fallthrough reduce/reconstruct -- in-block 4-byte-aligned
    // ends are lossless; a cross-block end carries (4.5, 5.5, 8.1).
    // =============================================================
    do_reset();
    pc   = make_pc(26'h0000F6, 9'd44);
    base = pc;
    tgt  = base + 40'h10;
    // in-block end at instruction index 3 (offset 12).
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 3'd0, base + 40'd12);
    predict(pc);
    check("S10 in-block end +12 lossless",
          ftb_pft_addr_p2 == base + 40'd12);
    check("S10 in-block end +12 == model",
          ftb_pft_addr_p2 == exp_pft(base + 40'd12, base));
    // in-block end at index 7 (offset 28), last in-block position.
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, tgt, 3'd0, base + 40'd28);
    predict(pc);
    check("S10 in-block end +28 lossless",
          ftb_pft_addr_p2 == base + 40'd28);
    // cross-block end at next block start (offset 32) -> carry.
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, tgt, 3'd0, base + 40'd32);
    predict(pc);
    check("S10 cross-block end +32 carries",
          ftb_pft_addr_p2 == base + 40'd32);
    check("S10 cross-block end +32 == model",
          ftb_pft_addr_p2 == exp_pft(base + 40'd32, base));

    // =============================================================
    // S11: branch-type classification -- jump type bits drive
    // ftb_is_call / ftb_is_ret / ftb_is_jalr (section 1).
    // =============================================================
    do_reset();
    pc = make_pc(26'h000111, 9'd55);
    j1 = pc + 40'h100;
    upd_jmp(pc, 1'b0, 2'd0, j1, 1'b1, 1'b0, 1'b0, 3'd0, pc); // call
    predict(pc);
    check("S11 call: is_call",  ftb_is_call_p2 == 1'b1);
    check("S11 call: !is_ret",  ftb_is_ret_p2  == 1'b0);
    check("S11 call: !is_jalr", ftb_is_jalr_p2 == 1'b0);
    upd_jmp(pc, 1'b1, 2'd0, j1, 1'b0, 1'b1, 1'b0, 3'd0, pc); // ret
    predict(pc);
    check("S11 ret: is_ret",   ftb_is_ret_p2  == 1'b1);
    check("S11 ret: !is_call", ftb_is_call_p2 == 1'b0);
    check("S11 ret: !is_jalr", ftb_is_jalr_p2 == 1'b0);
    upd_jmp(pc, 1'b1, 2'd0, j1, 1'b0, 1'b0, 1'b1, 3'd0, pc); // jalr
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
    tgt = pc + 40'h40;
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 3'd0, pc); // conf=4, MSB=1
    predict(pc);
    check("D1 MSB=1 -> taken", ftb_br0_taken_p2 == 1'b1);
    check("D1 taken == valid & conf MSB",
          ftb_br0_taken_p2 ==
            (ftb_br0_valid_p2 & ftb_br0_conf_p2[FTB_CONF_WIDTH-1]));
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b0, tgt, 3'd0, pc); // 4->3, MSB=0
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
    tgt = pc + 40'h40;
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 3'd0, pc); // conf=4
    train_br(pc, 2'd0, 1'b0, 1'b1, 3, tgt, 3'd0, pc);  // ->7
    predict(pc);
    check("D2 taken saturates at 111", ftb_br0_conf_p2 == CONF_SAT_T);
    train_br(pc, 2'd0, 1'b0, 1'b1, 1, tgt, 3'd0, pc);  // extra taken
    predict(pc);
    check("D2 taken no wrap (stays 111)", ftb_br0_conf_p2 == CONF_SAT_T);
    do_reset();
    pc  = make_pc(26'h000223, 9'd66);
    tgt = pc + 40'h40;
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b0, tgt, 3'd0, pc); // conf=3
    train_br(pc, 2'd0, 1'b0, 1'b0, 3, tgt, 3'd0, pc);  // ->0
    predict(pc);
    check("D2 not-taken saturates at 000", ftb_br0_conf_p2 == CONF_SAT_N);
    train_br(pc, 2'd0, 1'b0, 1'b0, 1, tgt, 3'd0, pc);  // extra not-taken
    predict(pc);
    check("D2 not-taken no wrap (stays 000)", ftb_br0_conf_p2 == CONF_SAT_N);

    // =============================================================
    // D3: weak init -- taken alloc -> INIT_TKN (3'b100), not-taken
    // alloc -> INIT_NTK (3'b011); a fresh entry does NOT fast-path
    // (override doc 7). en=1 to prove the unsaturated entry holds.
    // =============================================================
    do_reset();
    ftb_fastpath_en = 1'b1;
    pc  = make_pc(26'h000224, 9'd70);
    tgt = pc + 40'h40;
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 3'd0, pc); // taken alloc
    predict(pc);
    check("D3 taken init conf==3'b100", ftb_br0_conf_p2 == FTB_CONF_INIT_TKN);
    check("D3 taken init MSB=1",
          ftb_br0_conf_p2[FTB_CONF_WIDTH-1] == 1'b1);
    check("D3 fresh taken does NOT fast-path", ftb_fastpath_p2[0] == 1'b0);
    pc  = make_pc(26'h000225, 9'd71);
    tgt = pc + 40'h40;
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b0, tgt, 3'd0, pc); // not-taken alloc
    predict(pc);
    check("D3 ntkn init conf==3'b011", ftb_br0_conf_p2 == FTB_CONF_INIT_NTK);
    check("D3 ntkn init MSB=0",
          ftb_br0_conf_p2[FTB_CONF_WIDTH-1] == 1'b0);
    check("D3 fresh ntkn does NOT fast-path", ftb_fastpath_p2[0] == 1'b0);
    ftb_fastpath_en = 1'b0;

    // =============================================================
    // D4: self-correction -- saturate to 111 (fast-path eligible);
    // one opposite resolve steps to 110 and the fast-path stops until
    // re-saturation (override doc 3.4).
    // =============================================================
    do_reset();
    pc  = make_pc(26'h000226, 9'd80);
    tgt = pc + 40'h40;
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 3'd0, pc);
    train_br(pc, 2'd0, 1'b0, 1'b1, 3, tgt, 3'd0, pc);  // ->7
    ftb_fastpath_en = 1'b1;
    predict(pc);
    check("D4 saturated conf==111", ftb_br0_conf_p2 == CONF_SAT_T);
    check("D4 fast-path fires at 111", ftb_fastpath_p2[0] == 1'b1);
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b0, tgt, 3'd0, pc); // 7->6
    predict(pc);
    check("D4 mispredict steps 111->110", ftb_br0_conf_p2 == 3'd6);
    check("D4 fast-path stops at 110", ftb_fastpath_p2[0] == 1'b0);
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, tgt, 3'd0, pc); // 6->7
    predict(pc);
    check("D4 re-saturates to 111", ftb_br0_conf_p2 == CONF_SAT_T);
    check("D4 fast-path fires again", ftb_fastpath_p2[0] == 1'b1);
    ftb_fastpath_en = 1'b0;

    // =============================================================
    // D5: reallocation resets conf -- saturate a field, then evict
    // and reallocate the same way to a branch of the opposite
    // direction; conf = new weak init, not the old value (5.4 / 7).
    // =============================================================
    do_reset();
    pcA = make_pc(26'h00030A, 9'd90);
    pcB = make_pc(26'h00030B, 9'd90);   // same set, different tag
    tgt = pcA + 40'h40;
    upd_br(pcA, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 3'd0, pcA); // alloc tkn
    train_br(pcA, 2'd0, 1'b0, 1'b1, 3, tgt, 3'd0, pcA);  // ->7
    predict(pcA);
    check("D5 A saturated 111 before realloc", ftb_br0_conf_p2 == CONF_SAT_T);
    upd_br(pcB, 1'b0, 2'd0, 1'b0, 1'b0, pcB + 40'h40, 3'd0, pcB); // realloc
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
    tgt = pc + 40'h40;
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 3'd0, pc);
    train_br(pc, 2'd0, 1'b0, 1'b1, 3, tgt, 3'd0, pc);  // ->7
    ftb_fastpath_en = 1'b1;
    predict(pc);
    check("FP1 valid+br0_valid+sat+en", ftb_valid_p2 && ftb_br0_valid_p2 &&
          (ftb_br0_conf_p2 == CONF_SAT_T) && ftb_fastpath_en);
    check("FP1 fast-path[0] fires", ftb_fastpath_p2[0] == 1'b1);

    // =============================================================
    // FP2: does NOT fire at en=0, even at saturated conf.
    // =============================================================
    ftb_fastpath_en = 1'b0;
    predict(pc);
    check("FP2 conf still saturated",  ftb_br0_conf_p2 == CONF_SAT_T);
    check("FP2 no fire at en=0",       ftb_fastpath_p2[0] == 1'b0);

    // =============================================================
    // FP3: does NOT fire at an unsaturated conf, even with en=1.
    // =============================================================
    do_reset();
    pc  = make_pc(26'h000402, 9'd101);
    tgt = pc + 40'h40;
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 3'd0, pc); // conf=4 (unsat)
    ftb_fastpath_en = 1'b1;
    predict(pc);
    check("FP3 conf unsaturated (==4)", ftb_br0_conf_p2 == FTB_CONF_INIT_TKN);
    check("FP3 no fire when unsaturated", ftb_fastpath_p2[0] == 1'b0);
    ftb_fastpath_en = 1'b0;

    // =============================================================
    // FP4: does NOT fire on an FTB miss or an empty conditional field.
    // =============================================================
    do_reset();
    ftb_fastpath_en = 1'b1;
    predict(make_pc(26'h0009FF, 9'd102));            // unallocated -> miss
    check("FP4 miss: not valid",       ftb_valid_p2 == 1'b0);
    check("FP4 miss: no fast-path",    ftb_fastpath_p2 == 2'b00);
    pc = make_pc(26'h000403, 9'd103);
    upd_jmp(pc, 1'b0, 2'd0, pc + 40'h80, 1'b1, 1'b0, 1'b0, 3'd0, pc);
    predict(pc);                                     // jmp only, no br0
    check("FP4 empty br0 field invalid", ftb_br0_valid_p2 == 1'b0);
    check("FP4 empty field: br0 no fast-path", ftb_fastpath_p2[0] == 1'b0);
    ftb_fastpath_en = 1'b0;

    // =============================================================
    // FP5: fast-path is direction-only -- at a saturated conf the
    // branch target is unchanged; there is no target suppression
    // (override doc 4.2). Train to 111 with a known target.
    // =============================================================
    do_reset();
    pc   = make_pc(26'h000404, 9'd104);
    base = pc;
    tgt  = base + 40'h300;
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 3'd0, pc);
    train_br(pc, 2'd0, 1'b0, 1'b1, 3, tgt, 3'd0, pc);  // ->7
    ftb_fastpath_en = 1'b1;
    predict(pc);
    check("FP5 fast-path fires", ftb_fastpath_p2[0] == 1'b1);
    check("FP5 target intact under fast-path",
          ftb_br0_target_p2 == exp_br_tgt(tgt, base));
    check("FP5 target == true (in-range, direction-only)",
          ftb_br0_target_p2 == tgt);
    ftb_fastpath_en = 1'b0;

    // =============================================================
    // P1: position round-trip -- drive ftb_upd_pos_u0 on fills for
    // br0, br1, and the jump; read back the three pos outputs
    // (BP-066b, IC-FTB-15).
    // =============================================================
    do_reset();
    pc  = make_pc(26'h000501, 9'd120);
    tgt = pc + 40'h40;
    upd_br(pc, 1'b0, 2'd0, 1'b0, 1'b1, tgt, 3'd3, pc);            // br0 pos3
    upd_br(pc, 1'b1, 2'd0, 1'b1, 1'b1, tgt, 3'd5, pc);            // br1 pos5
    upd_jmp(pc, 1'b1, 2'd0, pc + 40'h80, 1'b1, 1'b0, 1'b0, 3'd7, pc); // jmp7
    predict(pc);
    check("P1 br0 pos round-trip ==3", ftb_br0_pos_p2 == 3'd3);
    check("P1 br1 pos round-trip ==5", ftb_br1_pos_p2 == 3'd5);
    check("P1 jmp pos round-trip ==7", ftb_jmp_pos_p2 == 3'd7);

    // =============================================================
    // P2: position static on in-place update -- resolve the same
    // branch again with a DIFFERENT pos; stored position unchanged
    // (5.5).
    // =============================================================
    upd_br(pc, 1'b1, 2'd0, 1'b0, 1'b1, tgt, 3'd2, pc); // br0 in-place pos2
    predict(pc);
    check("P2 br0 pos static on in-place (still 3)", ftb_br0_pos_p2 == 3'd3);

    // =============================================================
    // P3: reallocation overwrites position -- reallocate the field to
    // a new branch with a new position; the new position is stored.
    // =============================================================
    pcB = make_pc(26'h000502, 9'd120);  // same set, different tag
    upd_br(pcB, 1'b0, 2'd0, 1'b0, 1'b1, pcB + 40'h40, 3'd4, pcB); // realloc
    predict(pcB);
    check("P3 realloc stores new pos ==4", ftb_br0_pos_p2 == 3'd4);

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
