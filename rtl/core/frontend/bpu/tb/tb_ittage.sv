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
  // bw_write: backdoor write to ittage_table RAM.
  // tbl : 1-5 (IT1-IT5).
  // slot: 0 -> u_ram_s0 (pred slot 0), 1 -> u_ram_s1 (pred slot 1).
  // bank: MSB of full index hash (0 or 1).
  // ent : remaining index bits (0..RAM_ENTRIES-1).
  // Entry packing: VAL[0],CTR[3:1],USE[5:4],EPC[7:6],TGT[45:8],
  //   TAG[ALLOC_DATA_WIDTH-1:46]. Max ALLOC_DATA_WIDTH=57 (IT5).
  // Tag is stored at d[56:46]; write truncates to table width.
  // Backdoor path: dut.gen_ittage_tables[T].gen_active.u_table
  //   .u_ram_s{slot}.mem[bank][ent].
  // ================================================================
  task automatic bw_write(
    input int tbl, input int slot,
    input int bank, input int ent,
    input logic                        val,
    input logic [IT_MAX_CTR_WIDTH-1:0] ctr,
    input logic [IT_MAX_USE_WIDTH-1:0] use_fld,
    input logic [IT_MAX_EPC_WIDTH-1:0] epc,
    input logic [IT_MAX_TGT_WIDTH-1:0] tgt,
    input logic [IT_MAX_TAG_WIDTH-1:0] tag
  );
    automatic logic [56:0] d;
    d        = '0;
    d[0]     = val;
    d[3:1]   = ctr;
    d[5:4]   = use_fld;
    d[7:6]   = epc;
    d[45:8]  = tgt;
    d[56:46] = IT_MAX_TAG_WIDTH'(tag);
    if (slot == 0) begin
      case (tbl)
        // IT1/IT2: ALLOC_DATA_WIDTH=54, TAG=8b -> d[53:0]
        1: dut.gen_ittage_tables[1].gen_active.u_table.u_ram_s0.mem[bank][ent] = d[53:0];
        2: dut.gen_ittage_tables[2].gen_active.u_table.u_ram_s0.mem[bank][ent] = d[53:0];
        // IT3/IT4: ALLOC_DATA_WIDTH=55, TAG=9b -> d[54:0]
        3: dut.gen_ittage_tables[3].gen_active.u_table.u_ram_s0.mem[bank][ent] = d[54:0];
        4: dut.gen_ittage_tables[4].gen_active.u_table.u_ram_s0.mem[bank][ent] = d[54:0];
        // IT5: ALLOC_DATA_WIDTH=57, TAG=11b -> d[56:0]
        5: dut.gen_ittage_tables[5].gen_active.u_table.u_ram_s0.mem[bank][ent] = d[56:0];
        default:
          $display("  WARN: bw_write: invalid tbl %0d", tbl);
      endcase
    end else begin
      case (tbl)
        1: dut.gen_ittage_tables[1].gen_active.u_table.u_ram_s1.mem[bank][ent] = d[53:0];
        2: dut.gen_ittage_tables[2].gen_active.u_table.u_ram_s1.mem[bank][ent] = d[53:0];
        3: dut.gen_ittage_tables[3].gen_active.u_table.u_ram_s1.mem[bank][ent] = d[54:0];
        4: dut.gen_ittage_tables[4].gen_active.u_table.u_ram_s1.mem[bank][ent] = d[54:0];
        5: dut.gen_ittage_tables[5].gen_active.u_table.u_ram_s1.mem[bank][ent] = d[56:0];
        default:
          $display("  WARN: bw_write: invalid tbl %0d", tbl);
      endcase
    end
  endtask

  // do_reset: apply reset pulse; wait for ittage_rdy.
  // RAM contents are preserved (fast_init runs at time 0 only).
  // UAON registers reset to IT_UAON_THRES; monitor counters reset.
  task automatic do_reset();
    automatic int t;
    clr();
    rstn = 1'b0;
    repeat(3) @(posedge clk);
    rstn = 1'b1;
    t    = 0;
    @(posedge clk);
    while (!ittage_rdy && t < 200) begin
      @(posedge clk); t++;
    end
    repeat(2) @(posedge clk);
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
  // TC-CTR-R01: CTR table row 1 (H=0, no CTR update)
  // Coverage: ittage_cntrl_ctr_update_rules.md row 1.
  // Captures CTR before the H=0 update and verifies no change.
  // ================================================================
  task automatic tc_ctr_r01();
    ittage_upd_inp_t upd;
    automatic logic [IT_MAX_CTR_WIDTH-1:0] ctr_pre;
    $display("-- TC-CTR-R01 CTR row 1 H=0 no update");
    do_pred(40'h0000_3000, 6'h40, 0);
    wait_prdy(0);
    ctr_pre = ittage_pred_meta_p2[0].ittage_prm_ctr;
    upd = '0;
    upd.ittage_pred_meta = ittage_pred_meta_p2[0];
    upd.ittage_pred_meta.ittage_hit = 1'b0; // force H=0 -> row 1
    upd.resolved_target  = 38'h0_0000_4000;
    upd.indir_mispredict = 1'b0;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_3000, 6'h41, 0);
    wait_prdy(0);
    chk("CTR-R01:no_ctr_chg",
      64'(ittage_pred_meta_p2[0].ittage_prm_ctr),
      64'(ctr_pre));
    @(posedge clk);
  endtask

  // ================================================================
  // TC-USE-R01: USE table row 1 (DIFF=0, uWR=0)
  // Coverage: ittage_cntrl_use_update_rules.md row 1.
  // prm_tgt == alt_tgt -> DIFF=0 -> no USE write.
  // Captures USE before update and verifies no change; the prior
  // test history (TC-P04/ARB04/UAON-01) may have left USE non-zero
  // via DIFF=1 updates, so checking for no-change not zero.
  // ================================================================
  task automatic tc_use_r01();
    ittage_upd_inp_t upd;
    automatic logic [IT_MAX_USE_WIDTH-1:0] use_before;
    $display("-- TC-USE-R01 USE row 1 DIFF=0 no USE write");
    do_pred(40'h0000_3000, 6'h50, 0);
    wait_prdy(0);
    use_before = ittage_pred_meta_p2[0].ittage_prm_useful;
    upd = '0;
    upd.ittage_pred_meta = ittage_pred_meta_p2[0];
    upd.ittage_pred_meta.ittage_hit           = 1'b1;
    upd.ittage_pred_meta.ittage_using_primary = 1'b1;
    // DIFF=0: prm_tgt == alt_tgt -> suppress USE write
    upd.ittage_pred_meta.ittage_prm_tgt =
      38'h0_0000_4000;
    upd.ittage_pred_meta.ittage_alt_tgt =
      38'h0_0000_4000;
    upd.resolved_target  = 38'h0_0000_4000;
    upd.indir_mispredict = 1'b0;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_3000, 6'h51, 0);
    wait_prdy(0);
    chk("USE-R01:no_use_chg",
      64'(ittage_pred_meta_p2[0].ittage_prm_useful),
      64'(use_before));
    @(posedge clk);
  endtask

  // ================================================================
  // TC-USE-R02: USE table row 2 (HIT=0, uWR=0)
  // Coverage: ittage_cntrl_use_update_rules.md row 2.
  // ittage_hit=0 -> no USE write regardless of DIFF.
  // Same no-change pattern as TC-USE-R01.
  // ================================================================
  task automatic tc_use_r02();
    ittage_upd_inp_t upd;
    automatic logic [IT_MAX_USE_WIDTH-1:0] use_before;
    $display("-- TC-USE-R02 USE row 2 HIT=0 no USE write");
    do_pred(40'h0000_3000, 6'h52, 0);
    wait_prdy(0);
    use_before = ittage_pred_meta_p2[0].ittage_prm_useful;
    upd = '0;
    upd.ittage_pred_meta = ittage_pred_meta_p2[0];
    upd.ittage_pred_meta.ittage_hit     = 1'b0; // HIT=0 -> row 2
    upd.ittage_pred_meta.ittage_prm_tgt = 38'h0_0000_4000;
    // DIFF=1 but HIT=0 takes precedence: uWR stays 0
    upd.ittage_pred_meta.ittage_alt_tgt = 38'h0_0000_5000;
    upd.resolved_target  = 38'h0_0000_4000;
    upd.indir_mispredict = 1'b0;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_3000, 6'h53, 0);
    wait_prdy(0);
    chk("USE-R02:no_use_chg",
      64'(ittage_pred_meta_p2[0].ittage_prm_useful),
      64'(use_before));
    @(posedge clk);
  endtask

  // ================================================================
  // TC-USE-R03: USE table row 3
  // DIFF=1, HIT=1, UP=1, MISP=0 -> INC prm_useful (0 -> 1)
  // Coverage: ittage_cntrl_use_update_rules.md row 3.
  // ================================================================
  task automatic tc_use_r03();
    ittage_upd_inp_t upd;
    $display("-- TC-USE-R03 USE row 3 DIFF=1 HIT=1 UP=1 INC");
    do_pred(40'h0000_3000, 6'h54, 0);
    wait_prdy(0);
    upd = '0;
    upd.ittage_pred_meta = ittage_pred_meta_p2[0];
    upd.ittage_pred_meta.ittage_hit         = 1'b1;
    upd.ittage_pred_meta.ittage_using_primary = 1'b1;
    // DIFF=1: prm_tgt != alt_tgt
    upd.ittage_pred_meta.ittage_prm_tgt     =
      38'h0_0000_4000;
    upd.ittage_pred_meta.ittage_alt_tgt     =
      38'h0_0000_5000;
    upd.ittage_pred_meta.ittage_prm_useful  = 2'h0;
    upd.resolved_target  = 38'h0_0000_4000;
    upd.indir_mispredict = 1'b0;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_3000, 6'h55, 0);
    wait_prdy(0);
    chk("USE-R03:prm_use_inc",
      64'(ittage_pred_meta_p2[0].ittage_prm_useful), 64'h1);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-USE-R04: USE table row 4
  // DIFF=1, HIT=1, UP=1, MISP=1 -> DEC prm_useful (1 -> 0)
  // Runs after TC-USE-R03; expects prm_useful=1 in RAM.
  // If R03 failed (useful still 0), DEC saturates at 0 -- check
  // still passes (0 == 0). Saturation confirmed either way.
  // Coverage: ittage_cntrl_use_update_rules.md row 4.
  // ================================================================
  task automatic tc_use_r04();
    ittage_upd_inp_t upd;
    $display("-- TC-USE-R04 USE row 4 DIFF=1 HIT=1 UP=1 DEC");
    do_pred(40'h0000_3000, 6'h56, 0);
    wait_prdy(0);
    upd = '0;
    upd.ittage_pred_meta = ittage_pred_meta_p2[0];
    upd.ittage_pred_meta.ittage_hit         = 1'b1;
    upd.ittage_pred_meta.ittage_using_primary = 1'b1;
    upd.ittage_pred_meta.ittage_prm_tgt     =
      38'h0_0000_4000;
    upd.ittage_pred_meta.ittage_alt_tgt     =
      38'h0_0000_5000;
    // Force prm_useful=1 so DEC writes 0 to RAM regardless
    // of whether TC-USE-R03 previously wrote 1.
    upd.ittage_pred_meta.ittage_prm_useful  = 2'h1;
    upd.resolved_target  = 38'h0_0000_6000; // mispredict
    upd.indir_mispredict = 1'b1;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_3000, 6'h57, 0);
    wait_prdy(0);
    chk("USE-R04:prm_use_dec",
      64'(ittage_pred_meta_p2[0].ittage_prm_useful), 64'h0);
    @(posedge clk);
  endtask

  // ================================================================
  // CTR backdoor tests: use PC=40'h0000_0200, folded_hist=0.
  // IT1 and IT2 at this PC (both idx=8'h80, tag=8'h02):
  //   bank = idx[7] = 1, entry = idx[6:0] = 0, tag_ext = 11'h002.
  // Seeded TGT = 38'h0_0000_5000 throughout.
  // ================================================================

  // ================================================================
  // TC-CTR-UP1-INC: primary CTR INC observed via readback.
  // Representative for rows 18,19,20,21,30,31,32,33 (UP=1 correct).
  // All share the same RTL path: prm_ctr_wr + prm_ctr_wd = ctr+1.
  // ================================================================
  task automatic tc_ctr_up1_inc();
    ittage_upd_inp_t   upd;
    ittage_pred_meta_t m;
    $display("-- TC-CTR-UP1-INC rows 18-33 representative");
    clr();
    // IT1 slot-0: CTR=1, USE=1, VAL=1. No IT2+ entry at this idx.
    bw_write(1, 0, 1, 0, 1'b1, 3'h1, 2'h1, 2'h0,
             38'h0_0000_5000, 11'h002);
    do_pred(40'h0000_0200, 6'h60, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("CTR-UP1-INC:hit",
      64'(m.ittage_hit),           64'h1);
    chk("CTR-UP1-INC:using_prm",
      64'(m.ittage_using_primary), 64'h1);
    chk("CTR-UP1-INC:ctr_pre",
      64'(m.ittage_prm_ctr),       64'h1);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_5000;
    upd.indir_mispredict = 1'b0;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_0200, 6'h61, 0);
    wait_prdy(0);
    chk("CTR-UP1-INC:ctr_post",
      64'(ittage_pred_meta_p2[0].ittage_prm_ctr), 64'h2);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-CTR-UP1-DEC: primary CTR DEC observed via readback.
  // Representative for rows 22,23,24,25,26,27,28,29 (UP=1 mis).
  // ================================================================
  task automatic tc_ctr_up1_dec();
    ittage_upd_inp_t   upd;
    ittage_pred_meta_t m;
    $display("-- TC-CTR-UP1-DEC rows 22-29 representative");
    clr();
    bw_write(1, 0, 1, 0, 1'b1, 3'h3, 2'h1, 2'h0,
             38'h0_0000_5000, 11'h002);
    do_pred(40'h0000_0200, 6'h62, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("CTR-UP1-DEC:ctr_pre",
      64'(m.ittage_prm_ctr),       64'h3);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_6000;
    upd.indir_mispredict = 1'b1;
    do_upd(upd, 0);
    @(posedge clk);
    // Mispredict triggers alloc to IT2 at {1,0}. Invalidate so IT2
    // does not preempt IT1 as primary in the readback prediction.
    bw_write(2, 0, 1, 0, 1'b0, 3'h0, 2'h0, 2'h0, 38'h0, 11'h0);
    do_pred(40'h0000_0200, 6'h63, 0);
    wait_prdy(0);
    chk("CTR-UP1-DEC:ctr_post",
      64'(ittage_pred_meta_p2[0].ittage_prm_ctr), 64'h2);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-CTR-UP0-INC: alternate CTR INC observed via readback.
  // Representative for rows 2,3,4,5,14,15,16,17 (UP=0 correct).
  // IT2=primary(CTR=0) -> not_null=0, UAON=8>=8 -> use_alt=1.
  // IT1=alternate(CTR=1) -> alt_ctr_wr fires, wd=2.
  // ================================================================
  task automatic tc_ctr_up0_inc();
    ittage_upd_inp_t   upd;
    ittage_pred_meta_t m;
    $display("-- TC-CTR-UP0-INC rows 2-17 representative");
    clr();
    // IT2 primary: CTR=0 triggers UAON use_alt.
    bw_write(2, 0, 1, 0, 1'b1, 3'h0, 2'h1, 2'h0,
             38'h0_0000_5000, 11'h002);
    // IT1 alternate: CTR=1.
    bw_write(1, 0, 1, 0, 1'b1, 3'h1, 2'h1, 2'h0,
             38'h0_0000_5000, 11'h002);
    do_pred(40'h0000_0200, 6'h64, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("CTR-UP0-INC:hit",
      64'(m.ittage_hit),           64'h1);
    chk("CTR-UP0-INC:using_prm",
      64'(m.ittage_using_primary), 64'h0);
    chk("CTR-UP0-INC:alt_ctr_pre",
      64'(m.ittage_alt_ctr),       64'h1);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_5000;
    upd.indir_mispredict = 1'b0;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_0200, 6'h65, 0);
    wait_prdy(0);
    chk("CTR-UP0-INC:alt_ctr_post",
      64'(ittage_pred_meta_p2[0].ittage_alt_ctr), 64'h2);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-CTR-UP0-DEC: alternate CTR DEC observed via readback.
  // Representative for rows 6,7,8,9,10,11,12,13 (UP=0 mis).
  // ================================================================
  task automatic tc_ctr_up0_dec();
    ittage_upd_inp_t   upd;
    ittage_pred_meta_t m;
    $display("-- TC-CTR-UP0-DEC rows 6-13 representative");
    clr();
    bw_write(2, 0, 1, 0, 1'b1, 3'h0, 2'h1, 2'h0,
             38'h0_0000_5000, 11'h002);
    bw_write(1, 0, 1, 0, 1'b1, 3'h3, 2'h1, 2'h0,
             38'h0_0000_5000, 11'h002);
    do_pred(40'h0000_0200, 6'h66, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("CTR-UP0-DEC:using_prm",
      64'(m.ittage_using_primary), 64'h0);
    chk("CTR-UP0-DEC:alt_ctr_pre",
      64'(m.ittage_alt_ctr),       64'h3);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_6000;
    upd.indir_mispredict = 1'b1;
    do_upd(upd, 0);
    @(posedge clk);
    // Mispredict (prm=IT2) triggers alloc to IT3 at {bank=0,ent=128}.
    // Invalidate so IT3 does not preempt as primary in the readback.
    bw_write(3, 0, 0, 128, 1'b0, 3'h0, 2'h0, 2'h0, 38'h0, 11'h0);
    do_pred(40'h0000_0200, 6'h67, 0);
    wait_prdy(0);
    chk("CTR-UP0-DEC:alt_ctr_post",
      64'(ittage_pred_meta_p2[0].ittage_alt_ctr), 64'h2);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-CTR-SAT: saturation holds for primary and alternate CTR.
  // - prm INC at max (CTR=7): held at 7.
  // - prm DEC at 0  (CTR=0, no alt): held at 0.
  // - alt INC at max (CTR=7): held at 7.
  // - alt DEC at 0  (CTR=0): held at 0.
  // ================================================================
  task automatic tc_ctr_sat();
    ittage_upd_inp_t   upd;
    ittage_pred_meta_t m;
    $display("-- TC-CTR-SAT saturation");

    // prm INC at max
    // Clear alloc residues from prior DEC tests at the two PC=0x200
    // addresses: IT2 at {1,0}, IT3-IT5 at {0,128} (9-bit idx=0x080).
    clr();
    bw_write(2, 0, 1, 0, 1'b0, 3'h0, 2'h0, 2'h0, 38'h0, 11'h0);
    bw_write(3, 0, 0, 128, 1'b0, 3'h0, 2'h0, 2'h0, 38'h0, 11'h0);
    bw_write(4, 0, 0, 128, 1'b0, 3'h0, 2'h0, 2'h0, 38'h0, 11'h0);
    bw_write(5, 0, 0, 128, 1'b0, 3'h0, 2'h0, 2'h0, 38'h0, 11'h0);
    bw_write(1, 0, 1, 0, 1'b1, 3'h7, 2'h1, 2'h0,
             38'h0_0000_5000, 11'h002);
    do_pred(40'h0000_0200, 6'h68, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("CTR-SAT:prm_max_pre",  64'(m.ittage_prm_ctr), 64'h7);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_5000;
    upd.indir_mispredict = 1'b0;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_0200, 6'h69, 0);
    wait_prdy(0);
    chk("CTR-SAT:prm_max_post",
      64'(ittage_pred_meta_p2[0].ittage_prm_ctr), 64'h7);

    // prm DEC at 0; invalidate IT2 so no alternate fires
    clr();
    bw_write(2, 0, 1, 0, 1'b0, 3'h0, 2'h0, 2'h0, 38'h0, 11'h0);
    bw_write(1, 0, 1, 0, 1'b1, 3'h0, 2'h1, 2'h0,
             38'h0_0000_5000, 11'h002);
    do_pred(40'h0000_0200, 6'h6A, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("CTR-SAT:prm_zero_pre", 64'(m.ittage_prm_ctr),       64'h0);
    chk("CTR-SAT:prm_zero_prm", 64'(m.ittage_using_primary), 64'h1);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_6000;
    upd.indir_mispredict = 1'b1;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_0200, 6'h6B, 0);
    wait_prdy(0);
    chk("CTR-SAT:prm_zero_post",
      64'(ittage_pred_meta_p2[0].ittage_prm_ctr), 64'h0);

    // alt INC at max
    clr();
    bw_write(2, 0, 1, 0, 1'b1, 3'h0, 2'h1, 2'h0,
             38'h0_0000_5000, 11'h002);
    bw_write(1, 0, 1, 0, 1'b1, 3'h7, 2'h1, 2'h0,
             38'h0_0000_5000, 11'h002);
    do_pred(40'h0000_0200, 6'h6C, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("CTR-SAT:alt_max_pre",  64'(m.ittage_alt_ctr), 64'h7);
    chk("CTR-SAT:alt_max_prm",
      64'(m.ittage_using_primary), 64'h0);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_5000;
    upd.indir_mispredict = 1'b0;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_0200, 6'h6D, 0);
    wait_prdy(0);
    chk("CTR-SAT:alt_max_post",
      64'(ittage_pred_meta_p2[0].ittage_alt_ctr), 64'h7);

    // alt DEC at 0
    clr();
    bw_write(2, 0, 1, 0, 1'b1, 3'h0, 2'h1, 2'h0,
             38'h0_0000_5000, 11'h002);
    bw_write(1, 0, 1, 0, 1'b1, 3'h0, 2'h1, 2'h0,
             38'h0_0000_5000, 11'h002);
    do_pred(40'h0000_0200, 6'h6E, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("CTR-SAT:alt_zero_pre", 64'(m.ittage_alt_ctr), 64'h0);
    chk("CTR-SAT:alt_zero_prm",
      64'(m.ittage_using_primary), 64'h0);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_6000;
    upd.indir_mispredict = 1'b1;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_0200, 6'h6F, 0);
    wait_prdy(0);
    chk("CTR-SAT:alt_zero_post",
      64'(ittage_pred_meta_p2[0].ittage_alt_ctr), 64'h0);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-USE-R05: USE table row 5
  // DIFF=1, HIT=1, UP=0, MISP=0 -> INC alt_useful (1 -> 2).
  // IT2=prm(CTR=0)->UAON fires use_alt; IT1=alt(CTR=1,USE=1).
  // Coverage: ittage_cntrl_use_update_rules.md row 5.
  // ================================================================
  task automatic tc_use_r05();
    ittage_upd_inp_t   upd;
    ittage_pred_meta_t m;
    $display("-- TC-USE-R05 USE row 5 DIFF=1 HIT=1 UP=0 INC");
    clr();
    // PC=40'h0000_0300: IT1/IT2 idx=8'hC0 bank=1 ent=64 tag=8'h03.
    // IT2 prm: CTR=0 -> not_null=0 -> UAON use_alt fires.
    bw_write(2, 0, 1, 64, 1'b1, 3'h0, 2'h0, 2'h0,
             38'h0_0000_A000, 11'h003);
    // IT1 alt: CTR=1, USE=1, TGT!=IT2.TGT -> DIFF=1.
    bw_write(1, 0, 1, 64, 1'b1, 3'h1, 2'h1, 2'h0,
             38'h0_0000_B000, 11'h003);
    do_pred(40'h0000_0300, 6'h70, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("USE-R05:hit",
      64'(m.ittage_hit),             64'h1);
    chk("USE-R05:using_prm",
      64'(m.ittage_using_primary),   64'h0);
    chk("USE-R05:alt_use_pre",
      64'(m.ittage_alt_useful),      64'h1);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_B000;
    upd.indir_mispredict = 1'b0;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_0300, 6'h71, 0);
    wait_prdy(0);
    chk("USE-R05:alt_use_post",
      64'(ittage_pred_meta_p2[0].ittage_alt_useful), 64'h2);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-USE-R06: USE table row 6
  // DIFF=1, HIT=1, UP=0, MISP=1 -> DEC alt_useful (2 -> 1).
  // IT2=prm(CTR=0)->use_alt fires; IT1=alt(CTR=1,USE=2).
  // Coverage: ittage_cntrl_use_update_rules.md row 6.
  // ================================================================
  task automatic tc_use_r06();
    ittage_upd_inp_t   upd;
    ittage_pred_meta_t m;
    $display("-- TC-USE-R06 USE row 6 DIFF=1 HIT=1 UP=0 DEC");
    clr();
    // Reseed PC=0x0300 entries. IT1 USE=2 for DEC -> 1.
    bw_write(2, 0, 1, 64, 1'b1, 3'h0, 2'h0, 2'h0,
             38'h0_0000_A000, 11'h003);
    bw_write(1, 0, 1, 64, 1'b1, 3'h1, 2'h2, 2'h0,
             38'h0_0000_B000, 11'h003);
    do_pred(40'h0000_0300, 6'h72, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("USE-R06:using_prm",
      64'(m.ittage_using_primary),   64'h0);
    chk("USE-R06:alt_use_pre",
      64'(m.ittage_alt_useful),      64'h2);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_1234_5678;
    upd.indir_mispredict = 1'b1;
    do_upd(upd, 0);
    @(posedge clk);
    // MISP=1, prm_comp=IT2=2<5: alloc fires to IT3.
    // IT3 at PC=0x300: 9-bit idx=9'hC0 -> bank=0 ent=192. Invalidate.
    bw_write(3, 0, 0, 192, 1'b0, 3'h0, 2'h0, 2'h0, 38'h0, 11'h0);
    do_pred(40'h0000_0300, 6'h73, 0);
    wait_prdy(0);
    chk("USE-R06:alt_use_post",
      64'(ittage_pred_meta_p2[0].ittage_alt_useful), 64'h1);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-USE-SAT: USE saturation: INC at max(2'b11) holds;
  //             DEC at 0 holds. Covers UP=1 prm and UP=0 alt.
  // Collapsed rows: alt INC -> row 5 path; alt DEC -> row 6 path;
  //                 prm INC -> row 3 path; prm DEC -> row 4 path.
  // ================================================================
  task automatic tc_use_sat();
    ittage_upd_inp_t   upd;
    ittage_pred_meta_t m;
    $display("-- TC-USE-SAT USE saturation prm and alt");

    // alt INC at max (USE=3 -> 3, UP=0)
    clr();
    bw_write(2, 0, 1, 64, 1'b1, 3'h0, 2'h0, 2'h0,
             38'h0_0000_A000, 11'h003);
    bw_write(1, 0, 1, 64, 1'b1, 3'h1, 2'h3, 2'h0,
             38'h0_0000_B000, 11'h003);
    do_pred(40'h0000_0300, 6'h74, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("USE-SAT:alt_max_pre",
      64'(m.ittage_alt_useful),      64'h3);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_B000;
    upd.indir_mispredict = 1'b0;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_0300, 6'h75, 0);
    wait_prdy(0);
    chk("USE-SAT:alt_max_post",
      64'(ittage_pred_meta_p2[0].ittage_alt_useful), 64'h3);

    // alt DEC at 0 (USE=0 -> 0, UP=0)
    clr();
    bw_write(2, 0, 1, 64, 1'b1, 3'h0, 2'h0, 2'h0,
             38'h0_0000_A000, 11'h003);
    bw_write(1, 0, 1, 64, 1'b1, 3'h1, 2'h0, 2'h0,
             38'h0_0000_B000, 11'h003);
    do_pred(40'h0000_0300, 6'h76, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("USE-SAT:alt_zero_pre",
      64'(m.ittage_alt_useful),      64'h0);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_1234_5678;
    upd.indir_mispredict = 1'b1;
    do_upd(upd, 0);
    @(posedge clk);
    // MISP=1: alloc to IT3 at PC=0x300. Invalidate.
    bw_write(3, 0, 0, 192, 1'b0, 3'h0, 2'h0, 2'h0, 38'h0, 11'h0);
    do_pred(40'h0000_0300, 6'h77, 0);
    wait_prdy(0);
    chk("USE-SAT:alt_zero_post",
      64'(ittage_pred_meta_p2[0].ittage_alt_useful), 64'h0);

    // prm INC at max (USE=3 -> 3, UP=1)
    // PC=40'h0000_0500: IT1 idx=8'h40 bank=0 ent=64 tag=8'h05.
    clr();
    bw_write(2, 0, 0, 64, 1'b0, 3'h0, 2'h0, 2'h0, 38'h0, 11'h0);
    bw_write(1, 0, 0, 64, 1'b1, 3'h3, 2'h3, 2'h0,
             38'h0_0000_C000, 11'h005);
    do_pred(40'h0000_0500, 6'h78, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("USE-SAT:prm_max_pre",
      64'(m.ittage_prm_useful),      64'h3);
    chk("USE-SAT:prm_max_prm",
      64'(m.ittage_using_primary),   64'h1);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_C000;
    upd.indir_mispredict = 1'b0;
    do_upd(upd, 0);
    @(posedge clk);
    do_pred(40'h0000_0500, 6'h79, 0);
    wait_prdy(0);
    chk("USE-SAT:prm_max_post",
      64'(ittage_pred_meta_p2[0].ittage_prm_useful), 64'h3);

    // prm DEC at 0 (USE=0 -> 0, UP=1)
    clr();
    bw_write(2, 0, 0, 64, 1'b0, 3'h0, 2'h0, 2'h0, 38'h0, 11'h0);
    bw_write(1, 0, 0, 64, 1'b1, 3'h1, 2'h0, 2'h0,
             38'h0_0000_C000, 11'h005);
    do_pred(40'h0000_0500, 6'h7A, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("USE-SAT:prm_zero_pre",
      64'(m.ittage_prm_useful),      64'h0);
    chk("USE-SAT:prm_zero_prm",
      64'(m.ittage_using_primary),   64'h1);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_1234_5678;
    upd.indir_mispredict = 1'b1;
    do_upd(upd, 0);
    @(posedge clk);
    // MISP=1, prm_comp=IT1=1<5: alloc to IT2 at PC=0x500
    // IT2 idx=8'h40 -> bank=0 ent=64. Invalidate.
    bw_write(2, 0, 0, 64, 1'b0, 3'h0, 2'h0, 2'h0, 38'h0, 11'h0);
    do_pred(40'h0000_0500, 6'h7B, 0);
    wait_prdy(0);
    chk("USE-SAT:prm_zero_post",
      64'(ittage_pred_meta_p2[0].ittage_prm_useful), 64'h0);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-TGT-A: UP=1, primary CTR non-zero, misprediction.
  // Spec: CTR decremented by 1. Target field unchanged.
  // PC=0x0700: IT1/IT2 bank=1 ent=64 tag=11'h007.
  // TGT_SEED=0xA000 and TGT_NEW=0xB000 differ: missed write fails.
  // ================================================================
  task automatic tc_tgt_a();
    ittage_upd_inp_t   upd;
    ittage_pred_meta_t m;
    $display(
      "-- TC-TGT-A UP=1 CTR nonzero mispredict no tgt write");
    clr();
    // IT2 invalid: IT1 is the only primary at PC=0x0700.
    bw_write(2, 0, 1, 64, 1'b0, 3'h0, 2'h0, 2'h0,
             38'h0, 11'h0);
    bw_write(1, 0, 1, 64, 1'b1, 3'h2, 2'h1, 2'h0,
             38'h0_0000_A000, 11'h007);
    do_pred(40'h0000_0700, 6'h01, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("TGT-A:hit",
      64'(m.ittage_hit),           64'h1);
    chk("TGT-A:using_prm",
      64'(m.ittage_using_primary), 64'h1);
    chk("TGT-A:ctr_pre",
      64'(m.ittage_prm_ctr),       64'h2);
    chk("TGT-A:tgt_pre",
      64'(m.ittage_prm_tgt),       64'h0_0000_A000);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_B000;
    upd.indir_mispredict = 1'b1;
    do_upd(upd, 0);
    @(posedge clk);
    // Alloc committed to IT2 at (1,64). Invalidate for readback.
    bw_write(2, 0, 1, 64, 1'b0, 3'h0, 2'h0, 2'h0,
             38'h0, 11'h0);
    do_pred(40'h0000_0700, 6'h02, 0);
    wait_prdy(0);
    chk("TGT-A:ctr_post",
      64'(ittage_pred_meta_p2[0].ittage_prm_ctr), 64'h1);
    chk("TGT-A:tgt_post",
      64'(ittage_pred_meta_p2[0].ittage_prm_tgt),
      64'h0_0000_A000);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-TGT-B: UP=1, primary CTR zero, misprediction.
  // Spec: CTR stays at zero (zero-to-zero write). Target replaced.
  // PC=0x0700: IT1/IT2 bank=1 ent=64 tag=11'h007.
  // TGT_SEED=0xA000 and TGT_NEW=0xB000 differ: missed write fails.
  // ================================================================
  task automatic tc_tgt_b();
    ittage_upd_inp_t   upd;
    ittage_pred_meta_t m;
    $display("-- TC-TGT-B UP=1 CTR zero mispredict: tgt replaced");
    clr();
    bw_write(2, 0, 1, 64, 1'b0, 3'h0, 2'h0, 2'h0,
             38'h0, 11'h0);
    bw_write(1, 0, 1, 64, 1'b1, 3'h0, 2'h1, 2'h0,
             38'h0_0000_A000, 11'h007);
    do_pred(40'h0000_0700, 6'h03, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("TGT-B:hit",
      64'(m.ittage_hit),           64'h1);
    chk("TGT-B:using_prm",
      64'(m.ittage_using_primary), 64'h1);
    chk("TGT-B:ctr_pre",
      64'(m.ittage_prm_ctr),       64'h0);
    chk("TGT-B:tgt_pre",
      64'(m.ittage_prm_tgt),       64'h0_0000_A000);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_B000;
    upd.indir_mispredict = 1'b1;
    do_upd(upd, 0);
    @(posedge clk);
    bw_write(2, 0, 1, 64, 1'b0, 3'h0, 2'h0, 2'h0,
             38'h0, 11'h0);
    do_pred(40'h0000_0700, 6'h04, 0);
    wait_prdy(0);
    chk("TGT-B:ctr_post",
      64'(ittage_pred_meta_p2[0].ittage_prm_ctr), 64'h0);
    chk("TGT-B:tgt_post",
      64'(ittage_pred_meta_p2[0].ittage_prm_tgt),
      64'h0_0000_B000);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-TGT-C: UP=0, alternate CTR non-zero, misprediction.
  // Spec: alt CTR decremented by 1. Alternate target unchanged.
  // PC=0x0900: IT2=prm(CTR=0) IT1=alt(CTR=2).
  // IT1/IT2 bank=0 ent=64 tag=11'h009. IT3 alloc bank=0 ent=64.
  // TGT_SEED=0xD000 and TGT_NEW=0xE000 differ: missed write fails.
  // ================================================================
  task automatic tc_tgt_c();
    ittage_upd_inp_t   upd;
    ittage_pred_meta_t m;
    $display(
      "-- TC-TGT-C UP=0 alt CTR nonzero mispredict no tgt write");
    clr();
    // Pre-invalidate IT3 alloc slot so alc_comp selects IT3.
    bw_write(3, 0, 0, 64, 1'b0, 3'h0, 2'h0, 2'h0,
             38'h0, 11'h0);
    // IT2 primary: CTR=0 -> UAON use_alt fires (UAON=8>=8).
    bw_write(2, 0, 0, 64, 1'b1, 3'h0, 2'h1, 2'h0,
             38'h0_0000_C000, 11'h009);
    // IT1 alternate: CTR=2 (non-zero). TGT distinct from resolved.
    bw_write(1, 0, 0, 64, 1'b1, 3'h2, 2'h1, 2'h0,
             38'h0_0000_D000, 11'h009);
    do_pred(40'h0000_0900, 6'h05, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("TGT-C:hit",
      64'(m.ittage_hit),           64'h1);
    chk("TGT-C:using_prm",
      64'(m.ittage_using_primary), 64'h0);
    chk("TGT-C:alt_ctr_pre",
      64'(m.ittage_alt_ctr),       64'h2);
    chk("TGT-C:alt_tgt_pre",
      64'(m.ittage_alt_tgt),       64'h0_0000_D000);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_E000;
    upd.indir_mispredict = 1'b1;
    do_upd(upd, 0);
    @(posedge clk);
    // IT3 alloc committed at (0,64). Invalidate to expose IT2/IT1.
    bw_write(3, 0, 0, 64, 1'b0, 3'h0, 2'h0, 2'h0,
             38'h0, 11'h0);
    do_pred(40'h0000_0900, 6'h06, 0);
    wait_prdy(0);
    chk("TGT-C:alt_ctr_post",
      64'(ittage_pred_meta_p2[0].ittage_alt_ctr), 64'h1);
    chk("TGT-C:alt_tgt_post",
      64'(ittage_pred_meta_p2[0].ittage_alt_tgt),
      64'h0_0000_D000);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-TGT-D: UP=0, alternate CTR zero, misprediction.
  // Spec: alt CTR stays at zero. Alternate target replaced.
  // PC=0x0900: IT2=prm(CTR=0) IT1=alt(CTR=0).
  // TGT_SEED=0xD000 and TGT_NEW=0xE000 differ: missed write fails.
  // ================================================================
  task automatic tc_tgt_d();
    ittage_upd_inp_t   upd;
    ittage_pred_meta_t m;
    $display(
      "-- TC-TGT-D UP=0 alt CTR zero mispredict: tgt replaced");
    clr();
    bw_write(3, 0, 0, 64, 1'b0, 3'h0, 2'h0, 2'h0,
             38'h0, 11'h0);
    // IT2 primary: CTR=0 -> UAON use_alt fires.
    bw_write(2, 0, 0, 64, 1'b1, 3'h0, 2'h1, 2'h0,
             38'h0_0000_C000, 11'h009);
    // IT1 alternate: CTR=0. TGT distinct from resolved.
    bw_write(1, 0, 0, 64, 1'b1, 3'h0, 2'h1, 2'h0,
             38'h0_0000_D000, 11'h009);
    do_pred(40'h0000_0900, 6'h07, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("TGT-D:hit",
      64'(m.ittage_hit),           64'h1);
    chk("TGT-D:using_prm",
      64'(m.ittage_using_primary), 64'h0);
    chk("TGT-D:alt_ctr_pre",
      64'(m.ittage_alt_ctr),       64'h0);
    chk("TGT-D:alt_tgt_pre",
      64'(m.ittage_alt_tgt),       64'h0_0000_D000);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_E000;
    upd.indir_mispredict = 1'b1;
    do_upd(upd, 0);
    @(posedge clk);
    bw_write(3, 0, 0, 64, 1'b0, 3'h0, 2'h0, 2'h0,
             38'h0, 11'h0);
    do_pred(40'h0000_0900, 6'h08, 0);
    wait_prdy(0);
    chk("TGT-D:alt_ctr_post",
      64'(ittage_pred_meta_p2[0].ittage_alt_ctr), 64'h0);
    chk("TGT-D:alt_tgt_post",
      64'(ittage_pred_meta_p2[0].ittage_alt_tgt),
      64'h0_0000_E000);
    // Non-provider (IT2/primary, seeded 0xC000) must be unchanged.
    chk("TGT-D:prm_tgt_post",
      64'(ittage_pred_meta_p2[0].ittage_prm_tgt),
      64'h0_0000_C000);
    @(posedge clk);
  endtask

  // ================================================================
  // TC-TGT-B-ext: UP=1 CTR zero mispredict. Non-provider (alternate)
  // target must be unchanged.
  // UAON decremented 8->7 via a correct prediction so that use_alt
  // stays 0 with alt present (uaon=7 < IT_UAON_THRES=8).
  // IT2=prm (CTR=0, TGT=0xA000), IT1=alt (CTR=1, TGT=0xC000),
  // both at PC=0x0700 bank=1 ent=64 tag=0x007.
  // Resolved=0xB000. After fix: prm_tgt->0xB000; alt_tgt unchanged.
  // ================================================================
  task automatic tc_tgt_b_ext();
    ittage_upd_inp_t   upd;
    ittage_pred_meta_t m;
    $display(
      "-- TC-TGT-B-ext UP=1 CTR zero: non-provider alt tgt unchanged");
    clr();
    // UAON decrement: IT1 sole provider at PC=0x1000 (bank=0 ent=0
    // tag=0x010). Correct prediction: prm_correct, alt_wrong(0) ->
    // DEC. uaon 8->7.
    bw_write(2, 0, 0, 0, 1'b0, 3'h0, 2'h0, 2'h0, 38'h0, 11'h0);
    bw_write(1, 0, 0, 0, 1'b1, 3'h0, 2'h1, 2'h0,
             38'h0_0000_F000, 11'h010);
    do_pred(40'h0000_1000, 6'h10, 0);
    wait_prdy(0);
    m   = ittage_pred_meta_p2[0];
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_F000;
    upd.indir_mispredict = 1'b0;
    do_upd(upd, 0);
    @(posedge clk);
    // uaon[0]=7 < 8: use_alt will not fire even with alt present.
    // IT2=prm (CTR=0, TGT=0xA000), IT1=alt (CTR=1, TGT=0xC000).
    bw_write(2, 0, 1, 64, 1'b1, 3'h0, 2'h1, 2'h0,
             38'h0_0000_A000, 11'h007);
    bw_write(1, 0, 1, 64, 1'b1, 3'h1, 2'h1, 2'h0,
             38'h0_0000_C000, 11'h007);
    do_pred(40'h0000_0700, 6'h11, 0);
    wait_prdy(0);
    m = ittage_pred_meta_p2[0];
    chk("TGT-B-ext:hit",
      64'(m.ittage_hit),           64'h1);
    chk("TGT-B-ext:using_prm",
      64'(m.ittage_using_primary), 64'h1);
    chk("TGT-B-ext:prm_ctr_pre",
      64'(m.ittage_prm_ctr),       64'h0);
    chk("TGT-B-ext:prm_tgt_pre",
      64'(m.ittage_prm_tgt),       64'h0_0000_A000);
    chk("TGT-B-ext:alt_tgt_pre",
      64'(m.ittage_alt_tgt),       64'h0_0000_C000);
    upd = '0;
    upd.ittage_pred_meta = m;
    upd.resolved_target  = 38'h0_0000_B000;
    upd.indir_mispredict = 1'b1;
    do_upd(upd, 0);
    @(posedge clk);
    // Direct RAM readback avoids alloc interference. Entry packing:
    // TGT = d[45:8]. IT2 prm_tgt must update; IT1 alt_tgt unchanged.
    begin
      automatic logic [53:0] it2_ent, it1_ent;
      automatic logic [37:0] it2_tgt, it1_tgt;
      it2_ent = dut.gen_ittage_tables[2].gen_active
                  .u_table.u_ram_s0.mem[1][64];
      it1_ent = dut.gen_ittage_tables[1].gen_active
                  .u_table.u_ram_s0.mem[1][64];
      it2_tgt = it2_ent[45:8];
      it1_tgt = it1_ent[45:8];
      chk("TGT-B-ext:prm_tgt_post", 64'(it2_tgt), 64'h0_0000_B000);
      chk("TGT-B-ext:alt_tgt_post", 64'(it1_tgt), 64'h0_0000_C000);
    end
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
    tc_ctr_r01();
    tc_use_r01();
    tc_use_r02();
    tc_use_r03();
    tc_use_r04();

    // CTR fix proof: reset DUT (RAM preserved), then backdoor tests.
    // UAON resets to IT_UAON_THRES=8 so use_alt fires on prm_ctr=0.
    do_reset();
    tc_ctr_up1_inc();
    tc_ctr_up1_dec();
    tc_ctr_up0_inc();
    tc_ctr_up0_dec();
    tc_ctr_sat();

    do_reset();
    tc_use_r05();
    tc_use_r06();
    tc_use_sat();

    do_reset();
    tc_tgt_a();
    tc_tgt_b();
    tc_tgt_c();
    tc_tgt_d();
    tc_tgt_b_ext();

    repeat(5) @(posedge clk);

    if (fail_cnt == 0)
      $display("PASS: all %0d checks passed", pass_cnt);
    else
      $display("FAIL: %0d passed, %0d failed", pass_cnt, fail_cnt);

    $finish;
  end

endmodule : tb

bind ittage ittage_assert #(
    .NUM_PRED_SLOTS(NUM_PRED_SLOTS)
  ) u_ittage_assert (
    .clk                  (clk),
    .rstn                 (rstn),
    .ittage_pred_rdy_p2   (ittage_pred_rdy_p2),
    .ittage_pred_meta_p2  (ittage_pred_meta_p2),
    .ittage_upd_val_u0    (ittage_upd_val_u0),
    .ittage_upd_inp_u0    (ittage_upd_inp_u0)
  );

`default_nettype wire
