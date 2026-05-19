// ===================================================================
// FILE:    tb_ittage.sv
// DATE:    2026-05-19
// -------------------------------------------------------------------
// Self-checking testbench for ittage.sv. BP-039.
// Uses FAST_INIT (+ITTAGE_FAST_INIT=1) for rapid init.
// Tests prediction, update, arbitration, and UAON gating.
// ===================================================================
`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  localparam int NPS  = NUM_PRED_SLOTS; // 2

  // ----------------------------------------------------------------
  // DUT port signals
  // ----------------------------------------------------------------
  logic                  clk, rstn;
  logic [NPS-1:0]        ittage_pred_val_p0;
  ittage_pred_inp_t      ittage_pred_inp_p0[0:NPS-1];
  logic [NPS-1:0]        ittage_pred_rdy_p2;
  ittage_pred_meta_t     ittage_pred_meta_p2[0:NPS-1];
  logic [NPS-1:0]        ittage_upd_val_u0;
  ittage_upd_inp_t       ittage_upd_inp_u0[0:NPS-1];
  logic [NPS-1:0]        ittage_upd_rdy_u1;
  logic                  pq_not_full;
  logic [NPS-1:0]        upd_rdy;
  logic                  ittage_enable_aging;
  logic [31:0]           ittage_aging_interval;
  bp_folded_hist_t       folded_hist;
  logic                  ittage_rdy;

  // ----------------------------------------------------------------
  // DUT
  // ----------------------------------------------------------------
  ittage dut (
    .clk                  (clk),
    .rstn                 (rstn),
    .ittage_pred_val_p0   (ittage_pred_val_p0),
    .ittage_pred_inp_p0   (ittage_pred_inp_p0),
    .ittage_pred_rdy_p2   (ittage_pred_rdy_p2),
    .ittage_pred_meta_p2  (ittage_pred_meta_p2),
    .ittage_upd_val_u0    (ittage_upd_val_u0),
    .ittage_upd_inp_u0    (ittage_upd_inp_u0),
    .ittage_upd_rdy_u1    (ittage_upd_rdy_u1),
    .pq_not_full          (pq_not_full),
    .upd_rdy              (upd_rdy),
    .ittage_enable_aging  (ittage_enable_aging),
    .ittage_aging_interval(ittage_aging_interval),
    .folded_hist          (folded_hist),
    .ittage_rdy           (ittage_rdy)
  );

  // ----------------------------------------------------------------
  // Clock: 10 ns period
  // ----------------------------------------------------------------
  initial begin clk = 1'b0; forever #5 clk = ~clk; end

  // ----------------------------------------------------------------
  // Monitors -- always_ff reads DUT FF outputs (nba_sequent per
  // CLAUDE.md stl_sequent rule).
  // ----------------------------------------------------------------
  longint  mon_prdy0_cnt;
  longint  mon_prdy1_cnt;
  longint  mon_u1_0_cnt;
  logic mon_saw_pq_full;
  logic mon_saw_uq_full;

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      mon_prdy0_cnt    <= 0;
      mon_prdy1_cnt    <= 0;
      mon_u1_0_cnt     <= 0;
      mon_saw_pq_full  <= 1'b0;
      mon_saw_uq_full  <= 1'b0;
    end else begin
      if (ittage_pred_rdy_p2[0])
        mon_prdy0_cnt  <= mon_prdy0_cnt + 1;
      if (ittage_pred_rdy_p2[1])
        mon_prdy1_cnt  <= mon_prdy1_cnt + 1;
      if (ittage_upd_rdy_u1[0])
        mon_u1_0_cnt   <= mon_u1_0_cnt  + 1;
      if (!pq_not_full)
        mon_saw_pq_full <= 1'b1;
      if (!upd_rdy[0])
        mon_saw_uq_full <= 1'b1;
    end
  end

  // ----------------------------------------------------------------
  // Pass/fail counters and cross-task state
  // ----------------------------------------------------------------
  int pass_cnt, fail_cnt;

  // TC-P03 captured fields -- used by P04 and UAON-01
  logic [IT_TBL_SEL_WIDTH-1:0] cap_alc_comp;
  logic [IT_MAX_IDX_WIDTH-1:0] cap_alc_idx;
  logic [IT_MAX_TAG_WIDTH-1:0] cap_alc_tag;
  ittage_pred_meta_t           cap_p3c; // P03 Phase C meta

  // ----------------------------------------------------------------
  // Helper tasks
  // ----------------------------------------------------------------
  task automatic clr();
    ittage_pred_val_p0    = '0;
    ittage_upd_val_u0     = '0;
    ittage_enable_aging   = 1'b0;
    ittage_aging_interval = 32'hFFFF_FFFF;
    folded_hist           = '0;
    for (int s = 0; s < NPS; s++) begin
      ittage_pred_inp_p0[s] = '0;
      ittage_upd_inp_u0[s]  = '0;
    end
  endtask

  task automatic chk(
    input string       nm,
    input logic [63:0] act,
    input logic [63:0] exp
  );
    if (act === exp) begin
      pass_cnt++;
      $display("  PASS %s", nm);
    end else begin
      fail_cnt++;
      $display("  FAIL %s  exp=%0h act=%0h", nm, exp, act);
    end
  endtask

  task automatic chk_nz(input string nm, input logic [63:0] v);
    if (v !== '0) begin
      pass_cnt++;
      $display("  PASS %s (val=%0h)", nm, v);
    end else begin
      fail_cnt++;
      $display("  FAIL %s  expected nonzero, got 0", nm);
    end
  endtask

  task automatic chk_seen(input string nm, input logic v);
    chk(nm, 64'(v), 64'h1);
  endtask

  // wait_prdy: poll pred_rdy_p2[slot], timeout 20 cycles
  task automatic wait_prdy(input int slot);
    automatic int n = 0;
    @(posedge clk);
    while (!ittage_pred_rdy_p2[slot] && n < 20) begin
      @(posedge clk); n++;
    end
    if (n >= 20)
      $display("  WARN: wait_prdy[%0d] timeout", slot);
  endtask

  // wait_u1: poll upd_rdy_u1[slot], timeout 20 cycles
  task automatic wait_u1(input int slot);
    automatic int n = 0;
    while (!ittage_upd_rdy_u1[slot] && n < 20) begin
      @(posedge clk); n++;
    end
    if (n >= 20)
      $display("  WARN: wait_u1[%0d] timeout", slot);
  endtask

  // do_pred: gate on pq_not_full, drive 1-cycle pred on slot
  task automatic do_pred(
    input logic [VA_WIDTH-1:0]     pc,
    input logic [FTQ_IDX_BITS-1:0] bid,
    input int                      slot
  );
    while (!pq_not_full) @(posedge clk);
    @(posedge clk);
    ittage_pred_val_p0                 = NPS'(1 << slot);
    ittage_pred_inp_p0[slot].pc        = pc;
    ittage_pred_inp_p0[slot].branch_id = bid;
    @(posedge clk);
    ittage_pred_val_p0    = '0;
    ittage_pred_inp_p0[0] = '0;
    ittage_pred_inp_p0[1] = '0;
  endtask

  // do_upd: gate on upd_rdy, drive 1-cycle update on slot, wait u1
  task automatic do_upd(
    input ittage_upd_inp_t inp,
    input int              slot
  );
    while (!upd_rdy[slot]) @(posedge clk);
    @(posedge clk);
    ittage_upd_val_u0          = NPS'(1 << slot);
    ittage_upd_inp_u0[slot]    = inp;
    @(posedge clk);
    ittage_upd_val_u0       = '0;
    ittage_upd_inp_u0[slot] = '0;
    wait_u1(slot);
  endtask

  // ================================================================
  // TC-P01: No-hit, slot 0 only
  // ================================================================
  task automatic tc_p01();
    $display("-- TC-P01 No-hit slot 0");
    clr();
    do_pred(40'h0000_1000, 6'h01, 0);
    wait_prdy(0);
    chk("P01:rdy0",
      64'(ittage_pred_rdy_p2[0]),                        64'h1);
    chk("P01:rdy1",
      64'(ittage_pred_rdy_p2[1]),                        64'h0);
    chk("P01:hit",
      64'(ittage_pred_meta_p2[0].ittage_hit),            64'h0);
    chk("P01:prm_comp",
      64'(ittage_pred_meta_p2[0].ittage_prm_comp),       64'h0);
    chk("P01:alt_comp",
      64'(ittage_pred_meta_p2[0].ittage_alt_comp),       64'h0);
    chk_nz("P01:alc_comp",
      64'(ittage_pred_meta_p2[0].ittage_alc_comp));
    chk("P01:using_prm",
      64'(ittage_pred_meta_p2[0].ittage_using_primary),  64'h1);
    chk("P01:bid",
      64'(ittage_pred_meta_p2[0].branch_id),             64'h01);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-P02: No-hit, both slots
  // ================================================================
  task automatic tc_p02();
    $display("-- TC-P02 No-hit both slots");
    clr();
    @(posedge clk);
    ittage_pred_val_p0              = 2'b11;
    ittage_pred_inp_p0[0].pc        = 40'h0000_2000;
    ittage_pred_inp_p0[0].branch_id = 6'h02;
    ittage_pred_inp_p0[1].pc        = 40'h0000_2020;
    ittage_pred_inp_p0[1].branch_id = 6'h03;
    @(posedge clk);
    ittage_pred_val_p0    = '0;
    ittage_pred_inp_p0[0] = '0;
    ittage_pred_inp_p0[1] = '0;
    wait_prdy(0);
    chk("P02:rdy",
      64'(ittage_pred_rdy_p2),                           64'h3);
    chk("P02:hit0",
      64'(ittage_pred_meta_p2[0].ittage_hit),            64'h0);
    chk("P02:hit1",
      64'(ittage_pred_meta_p2[1].ittage_hit),            64'h0);
    chk("P02:bid0",
      64'(ittage_pred_meta_p2[0].branch_id),             64'h02);
    chk("P02:bid1",
      64'(ittage_pred_meta_p2[1].branch_id),             64'h03);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-P03: Round-trip hit IT1, slot 0
  // ================================================================
  task automatic tc_p03();
    ittage_upd_inp_t upd;
    $display("-- TC-P03 Round-trip hit IT1");
    clr();

    // Phase A: seed prediction -- no hit, capture alc fields
    do_pred(40'h0000_3000, 6'h04, 0);
    wait_prdy(0);
    cap_alc_comp = ittage_pred_meta_p2[0].ittage_alc_comp;
    cap_alc_idx  = ittage_pred_meta_p2[0].ittage_alc_idx;
    cap_alc_tag  = ittage_pred_meta_p2[0].ittage_alc_tag;
    chk("P03-A:alc_comp", 64'(cap_alc_comp), 64'h1);

    // Phase B: indir_mispredict update -> allocation fires
    upd = '0;
    upd.ittage_pred_meta.ittage_hit           = 1'b0;
    upd.ittage_pred_meta.ittage_prm_comp      = '0;
    upd.ittage_pred_meta.ittage_using_primary = 1'b1;
    upd.ittage_pred_meta.ittage_prm_ctr       = '0;
    upd.ittage_pred_meta.ittage_alc_comp      = cap_alc_comp;
    upd.ittage_pred_meta.ittage_alc_idx       = cap_alc_idx;
    upd.ittage_pred_meta.ittage_alc_tag       = cap_alc_tag;
    upd.resolved_target                       = 38'h0_0000_4000;
    upd.indir_mispredict                      = 1'b1;
    do_upd(upd, 0);
    @(posedge clk); // ensure write commits before Phase C pred

    // Phase C: hit prediction -- same PC, same folded_hist=0
    do_pred(40'h0000_3000, 6'h05, 0);
    wait_prdy(0);
    cap_p3c = ittage_pred_meta_p2[0];
    chk("P03-C:hit",
      64'(ittage_pred_meta_p2[0].ittage_hit),            64'h1);
    chk("P03-C:prm_comp",
      64'(ittage_pred_meta_p2[0].ittage_prm_comp),
      64'(cap_alc_comp));
    chk("P03-C:prm_tgt",
      64'(ittage_pred_meta_p2[0].ittage_prm_tgt),
      64'h0_0000_4000);
    chk("P03-C:prm_ctr",
      64'(ittage_pred_meta_p2[0].ittage_prm_ctr),        64'h0);
    chk("P03-C:pred_strong",
      64'(ittage_pred_meta_p2[0].ittage_pred_strong),    64'h0);
    chk("P03-C:using_prm",
      64'(ittage_pred_meta_p2[0].ittage_using_primary),  64'h1);
    chk("P03-C:uaon",
      64'(ittage_pred_meta_p2[0].ittage_use_alt_on_na),  64'h0);
    chk("P03-C:bid",
      64'(ittage_pred_meta_p2[0].branch_id),             64'h05);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-P04: CTR increment after correct prediction
  // ================================================================
  task automatic tc_p04();
    ittage_upd_inp_t upd;
    $display("-- TC-P04 CTR increment");
    upd = '0;
    upd.ittage_pred_meta = cap_p3c;
    upd.resolved_target  = 38'h0_0000_4000;
    upd.indir_mispredict = 1'b0;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_3000, 6'h06, 0);
    wait_prdy(0);
    chk("P04:prm_ctr",
      64'(ittage_pred_meta_p2[0].ittage_prm_ctr),        64'h1);
    chk("P04:pred_strong",
      64'(ittage_pred_meta_p2[0].ittage_pred_strong),    64'h1);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-ARB-01: Prediction only, 10 consecutive preds, 1-cycle gaps
  // ================================================================
  task automatic tc_arb_01();
    automatic longint cnt_start;
    automatic int n;
    $display("-- TC-ARB-01 Prediction only x10");
    clr();
    cnt_start = mon_prdy0_cnt;
    for (int i = 0; i < 10; i++) begin
      do_pred(
        40'h0001_0000 + VA_WIDTH'(i * 32),
        FTQ_IDX_BITS'('h10 + i),
        0);
    end
    n = 0;
    while ((mon_prdy0_cnt - cnt_start < 10) && n < 60) begin
      @(posedge clk); n++;
    end
    chk("ARB01:10_rdy",
      64'(mon_prdy0_cnt - cnt_start), 64'd10);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-ARB-02: Update only, 5 no-op upds, 1-cycle gaps
  // ================================================================
  task automatic tc_arb_02();
    automatic longint cnt_start;
    automatic int n;
    ittage_upd_inp_t upd;
    $display("-- TC-ARB-02 Update only x5");
    clr();
    cnt_start = mon_u1_0_cnt;
    upd = '0;
    for (int i = 0; i < 5; i++) do_upd(upd, 0);
    n = 0;
    while ((mon_u1_0_cnt - cnt_start < 5) && n < 40) begin
      @(posedge clk); n++;
    end
    chk("ARB02:5_u1",
      64'(mon_u1_0_cnt - cnt_start), 64'd5);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-ARB-03: Simultaneous pred+upd, different entries
  // ================================================================
  task automatic tc_arb_03();
    automatic longint p_start, u_start;
    ittage_upd_inp_t upd;
    $display("-- TC-ARB-03 Simultaneous pred+upd");
    clr();
    p_start = mon_prdy0_cnt;
    u_start = mon_u1_0_cnt;
    upd = '0;
    @(posedge clk);
    ittage_pred_val_p0              = 2'b01;
    ittage_pred_inp_p0[0].pc        = 40'h0000_5000;
    ittage_pred_inp_p0[0].branch_id = 6'h20;
    ittage_upd_val_u0               = 2'b01;
    ittage_upd_inp_u0[0]            = upd;
    @(posedge clk);
    ittage_pred_val_p0    = '0;
    ittage_upd_val_u0     = '0;
    ittage_pred_inp_p0[0] = '0;
    ittage_upd_inp_u0[0]  = '0;
    repeat(15) @(posedge clk);
    chk("ARB03:pred_seen",
      64'(mon_prdy0_cnt - p_start), 64'd1);
    chk("ARB03:upd_seen",
      64'(mon_u1_0_cnt  - u_start), 64'd1);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-ARB-04: Simultaneous pred+upd, same entry (hits IT1 from P03)
  // ================================================================
  task automatic tc_arb_04();
    automatic longint p_start;
    ittage_upd_inp_t upd;
    $display("-- TC-ARB-04 Same-entry pred+upd");
    clr();
    p_start = mon_prdy0_cnt;
    upd = '0;
    upd.ittage_pred_meta = cap_p3c; // from TC-P03
    upd.resolved_target  = 38'h0_0000_4000;
    upd.indir_mispredict = 1'b0;
    @(posedge clk);
    ittage_pred_val_p0              = 2'b01;
    ittage_pred_inp_p0[0].pc        = 40'h0000_3000;
    ittage_pred_inp_p0[0].branch_id = 6'h07;
    ittage_upd_val_u0               = 2'b01;
    ittage_upd_inp_u0[0]            = upd;
    @(posedge clk);
    ittage_pred_val_p0    = '0;
    ittage_upd_val_u0     = '0;
    ittage_pred_inp_p0[0] = '0;
    ittage_upd_inp_u0[0]  = '0;
    // Wait for pred_rdy_p2 and capture meta for CTR check
    wait_prdy(0);
    chk("ARB04:pred_ctr",
      64'(ittage_pred_meta_p2[0].ittage_prm_ctr),        64'h1);
    repeat(10) @(posedge clk);
    chk("ARB04:pred_seen",
      64'(mon_prdy0_cnt - p_start), 64'd1);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-ARB-05: UQ burst fill
  // Assumption: continuous pred competition required to block upd
  // bypass so UQ fills. Drives pred_val=1 while issuing 4 upds.
  // ================================================================
  task automatic tc_arb_05();
    automatic longint u_start;
    automatic int upd_driven;
    automatic int n;
    $display("-- TC-ARB-05 UQ burst fill");
    clr();
    u_start    = mon_u1_0_cnt;
    upd_driven = 0;
    // 30-cycle window: pred competition + 4 upds when upd_rdy asserts
    for (int i = 0; i < 30; i++) begin
      @(posedge clk);
      ittage_pred_val_p0 =
        pq_not_full ? 2'b01 : 2'b00;
      if (pq_not_full) begin
        ittage_pred_inp_p0[0].pc        =
          40'h0002_0000 + VA_WIDTH'(i * 32);
        ittage_pred_inp_p0[0].branch_id =
          FTQ_IDX_BITS'('h30 + i);
      end
      if (upd_driven < 4 && upd_rdy[0]) begin
        ittage_upd_val_u0      = 2'b01;
        ittage_upd_inp_u0[0]   = '0;
        upd_driven++;
      end else begin
        ittage_upd_val_u0 = 2'b00;
      end
    end
    ittage_pred_val_p0 = '0;
    ittage_upd_val_u0  = '0;
    ittage_pred_inp_p0[0] = '0;
    // Drain remaining upds
    n = 0;
    while ((mon_u1_0_cnt - u_start < 4) && n < 60) begin
      @(posedge clk); n++;
    end
    chk_seen("ARB05:uq_full_seen", mon_saw_uq_full);
    chk("ARB05:4_u1",
      64'(mon_u1_0_cnt - u_start), 64'd4);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-ARB-06: PQ fills to ITTAGE_PQ_DEPTH=4
  // Continuous upd_val=1 competes; during upd grants preds queue in PQ.
  // ================================================================
  task automatic tc_arb_06();
    automatic longint p_start;
    automatic int n;
    $display("-- TC-ARB-06 PQ fills to depth 4");
    clr();
    p_start = mon_prdy0_cnt;
    // Drive both pred and upd for 30 cycles
    for (int i = 0; i < 30; i++) begin
      @(posedge clk);
      if (pq_not_full) begin
        ittage_pred_val_p0 = 2'b01;
        ittage_pred_inp_p0[0].pc        =
          40'h0003_0000 + VA_WIDTH'(i * 32);
        ittage_pred_inp_p0[0].branch_id =
          FTQ_IDX_BITS'('h40 + i);
      end else begin
        ittage_pred_val_p0 = '0;
      end
      if (upd_rdy[0]) begin
        ittage_upd_val_u0    = 2'b01;
        ittage_upd_inp_u0[0] = '0;
      end else begin
        ittage_upd_val_u0 = '0;
      end
    end
    ittage_pred_val_p0    = '0;
    ittage_upd_val_u0     = '0;
    ittage_pred_inp_p0[0] = '0;
    // Drain remaining preds
    n = 0;
    while ((mon_prdy0_cnt - p_start < 30) && n < 100) begin
      @(posedge clk); n++;
    end
    chk_seen("ARB06:pq_full_seen", mon_saw_pq_full);
    @(posedge clk);
  endtask

  // TC-ARB-07: N/A -- RB removed in BP-038b

  // ================================================================
  // TC-ARB-08: Starvation prevention
  // PRED_CREDITS=2, STARVE_THRESH=2.
  // 2 pred grants with UQ non-empty -> next grant is upd.
  // ================================================================
  task automatic tc_arb_08();
    automatic longint u_start;
    $display("-- TC-ARB-08 Starvation prevention");
    clr();
    u_start = mon_u1_0_cnt;
    // Cycle A: pred+upd simultaneously; pred grant (Rule 3),
    //          upd enqueued (not bypassed since grant went to pred).
    @(posedge clk);
    ittage_pred_val_p0              = 2'b01;
    ittage_pred_inp_p0[0].pc        = 40'h0004_0000;
    ittage_pred_inp_p0[0].branch_id = 6'h08;
    ittage_upd_val_u0               = 2'b01;
    ittage_upd_inp_u0[0]            = '0;
    // Cycle A+1: 2nd pred only; UQ has 1 entry -> Rule 3 again.
    //            After this grant: pred_credits=0, starve_ctr=2.
    @(posedge clk);
    ittage_pred_val_p0              = 2'b01;
    ittage_pred_inp_p0[0].pc        = 40'h0004_0020;
    ittage_pred_inp_p0[0].branch_id = 6'h09;
    ittage_upd_val_u0               = 2'b00;
    ittage_upd_inp_u0[0]            = '0;
    @(posedge clk);
    ittage_pred_val_p0    = '0;
    ittage_pred_inp_p0[0] = '0;
    // starve_ctr=2 >= STARVE_THRESH=2 -> Rule 2: upd grant this cycle
    repeat(15) @(posedge clk);
    chk("ARB08:upd_granted",
      64'(mon_u1_0_cnt - u_start), 64'd1);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-UAON-01: UAON gating at concurrent pred+upd
  // ================================================================
  task automatic tc_uaon_01();
    ittage_upd_inp_t upd;
    $display("-- TC-UAON-01 UAON gating");
    clr();
    // Use TC-P03 Phase C meta: hit=1, pred_strong=0 (CTR=0),
    // using_primary=1, alt_tgt=0, prm_tgt=38'h0_0000_4000.
    // resolved_target = prm_tgt -> prm_correct=1.
    // alt_tgt(0) != resolved(38'h0_0000_4000) -> alt_wrong=1.
    // Conditions for UAON DEC: hit, !strong, prm_correct, alt_wrong.
    // UAON: 8 -> 7.
    upd = '0;
    upd.ittage_pred_meta = cap_p3c;
    upd.resolved_target  = 38'h0_0000_4000;
    upd.indir_mispredict = 1'b0;
    // Issue pred+upd simultaneously; pred wins first (Rule 3)
    @(posedge clk);
    ittage_pred_val_p0              = 2'b01;
    ittage_pred_inp_p0[0].pc        = 40'h0000_3000;
    ittage_pred_inp_p0[0].branch_id = 6'h0A;
    ittage_upd_val_u0               = 2'b01;
    ittage_upd_inp_u0[0]            = upd;
    @(posedge clk);
    ittage_pred_val_p0    = '0;
    ittage_upd_val_u0     = '0;
    ittage_pred_inp_p0[0] = '0;
    ittage_upd_inp_u0[0]  = '0;
    // Wait for both pred and upd to complete
    repeat(15) @(posedge clk);
    // Follow-up prediction: UAON should be 7 < IT_UAON_THRES=8
    // -> ittage_use_alt_on_na = 0
    do_pred(40'h0000_3000, 6'h0B, 0);
    wait_prdy(0);
    chk("UAON01:use_alt_on_na",
      64'(ittage_pred_meta_p2[0].ittage_use_alt_on_na),  64'h0);
    @(posedge clk);
  endtask

  // ================================================================
  // Main simulation
  // ================================================================
  initial begin
    clr();
    rstn     = 1'b0;
    pass_cnt = 0;
    fail_cnt = 0;

    // Reset: 5 cycles low
    repeat(5) @(posedge clk);
    rstn = 1'b1;

    // Wait for ittage_rdy (immediate with +ITTAGE_FAST_INIT=1)
    @(posedge clk);
    begin
      automatic int tout = 0;
      while (!ittage_rdy && tout < 200) begin
        @(posedge clk); tout++;
      end
    end
    if (!ittage_rdy) begin
      $display("FATAL: ittage_rdy never asserted");
      $finish;
    end
    $display("ittage_rdy asserted -- starting tests");
    repeat(2) @(posedge clk);

    tc_p01();
    tc_p02();
    tc_p03();
    tc_p04();
    tc_arb_01();
    tc_arb_02();
    tc_arb_03();
    tc_arb_04();
    tc_arb_05();
    tc_arb_06();
    // TC-ARB-07: N/A -- RB removed in BP-038b
    tc_arb_08();
    tc_uaon_01();

    repeat(5) @(posedge clk);

    if (fail_cnt == 0)
      $display("PASS: all %0d checks passed", pass_cnt);
    else
      $display("FAIL: %0d passed, %0d failed", pass_cnt, fail_cnt);

    $finish;
  end

endmodule : tb

`default_nettype wire
