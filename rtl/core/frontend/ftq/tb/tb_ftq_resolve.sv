// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ftq_resolve (BP-107),
// ftq_backend_interfaces.md 4 and fe_decisions.md 7.2.
//
// NOTHING IN THE BACKEND EXISTS, so this file models it. Only the
// FTQ side is under test.
//
// Problem 6's three acceptance criteria:
//
//   a position naming EITHER slot maps correctly   -> group B
//   a position naming NO slot is REPORTED rather
//   than silently dropped                          -> group C
//   the update reaches ftq_ftb_sched UNCHANGED     -> group E
//
// WHAT THE STIMULUS MUST SUPPLY, and why none of it is assumed. The
// entry and the metadata are module INPUTS, read from ftq_entry and
// ftq_meta through the index this module drives, so this file plays
// both arrays: it drives rsv_entry and rsv_meta as a function of
// rsv_rd_idx, which also checks R6 -- the read index IS the
// resolution's index -- continuously rather than at one point.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  logic [FTQ_PTR_BITS-1:0] commit_ptr;
  logic [FTQ_PTR_BITS-1:0] alloc_ptr;
  logic [NUM_RESOLVE_PORTS-1:0] bkend_rsv_val;
  ftq_resolve_t            bkend_rsv [0:NUM_RESOLVE_PORTS-1];
  logic [NUM_RESOLVE_PORTS-1:0] ftq_bkend_rsv_rdy;
  logic [FTQ_IDX_BITS-1:0] rsv_rd_idx [0:NUM_RESOLVE_PORTS-1];
  bp_ftq_entry_t           rsv_entry  [0:NUM_RESOLVE_PORTS-1];
  bp_ftq_meta_t            rsv_meta   [0:NUM_RESOLVE_PORTS-1]
                                      [0:NUM_PRED_SLOTS-1];
  logic [NUM_RESOLVE_PORTS-1:0] ftb_sched_rdy;
  logic                    tage_upd_rdy;
  logic                    ittage_upd_rdy;
  logic                    sc_upd_rdy;
  bp_update_t              upd [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] upd_ubtb_val;
  logic [NUM_PRED_SLOTS-1:0] upd_lp_val;
  logic [NUM_PRED_SLOTS-1:0] upd_tage_val;
  logic [NUM_PRED_SLOTS-1:0] upd_ittage_val;
  logic [NUM_PRED_SLOTS-1:0] upd_sc_val;
  bp_ftq_meta_t            upd_meta [0:NUM_PRED_SLOTS-1];
  logic [NUM_RESOLVE_PORTS-1:0] ftb_upd_val;
  ftb_upd_t                ftb_upd [0:NUM_RESOLVE_PORTS-1];
  logic [NUM_RESOLVE_PORTS-1:0] ftb_upd_hit;
  logic [NUM_RESOLVE_PORTS-1:0] ftb_upd_mispred;
  logic [NUM_RESOLVE_PORTS-1:0] rsv_nomap;
  logic [NUM_RESOLVE_PORTS-1:0] rsv_drop_sq;
  logic [NUM_RESOLVE_PORTS-1:0] rsv_type_dis;
  logic [NUM_RESOLVE_PORTS-1:0] rsv_accept;
  logic [TRX_SLOT_BITS-1:0] rsv_slot [0:NUM_RESOLVE_PORTS-1];

  ftq_resolve dut (
    .clk               (clk),
    .rstn              (rstn),
    .commit_ptr        (commit_ptr),
    .alloc_ptr         (alloc_ptr),
    .bkend_rsv_val     (bkend_rsv_val),
    .bkend_rsv         (bkend_rsv),
    .ftq_bkend_rsv_rdy (ftq_bkend_rsv_rdy),
    .rsv_rd_idx        (rsv_rd_idx),
    .rsv_entry         (rsv_entry),
    .rsv_meta          (rsv_meta),
    .ftb_sched_rdy     (ftb_sched_rdy),
    .tage_upd_rdy      (tage_upd_rdy),
    .ittage_upd_rdy    (ittage_upd_rdy),
    .sc_upd_rdy        (sc_upd_rdy),
    .upd               (upd),
    .upd_ubtb_val      (upd_ubtb_val),
    .upd_lp_val        (upd_lp_val),
    .upd_tage_val      (upd_tage_val),
    .upd_ittage_val    (upd_ittage_val),
    .upd_sc_val        (upd_sc_val),
    .upd_meta          (upd_meta),
    .ftb_upd_val       (ftb_upd_val),
    .ftb_upd           (ftb_upd),
    .ftb_upd_hit       (ftb_upd_hit),
    .ftb_upd_mispred   (ftb_upd_mispred),
    .rsv_nomap         (rsv_nomap),
    .rsv_drop_sq       (rsv_drop_sq),
    .rsv_type_dis      (rsv_type_dis),
    .rsv_accept        (rsv_accept),
    .rsv_slot          (rsv_slot)
  );

  // The modelled entry and metadata arrays. Driven combinationally
  // from rsv_rd_idx, exactly as ftq_entry and ftq_meta drive their
  // read ports, so the whole path from the resolution index through
  // the array read to the update is exercised.
  bp_ftq_entry_t m_entry [FTQ_DEPTH-1:0];
  bp_ftq_meta_t  m_meta  [FTQ_DEPTH-1:0][NUM_PRED_SLOTS-1:0];

  always_comb begin : model_arrays
    for (int p = 0; p < NUM_RESOLVE_PORTS; p++) begin
      rsv_entry[p] = m_entry[rsv_rd_idx[p]];
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        rsv_meta[p][s] = m_meta[rsv_rd_idx[p]][s];
      end
    end
  end

  localparam logic [VA_WIDTH-1:0] BASE_PC = 40'h00_8000_0000;

  int pass_cnt;
  int fail_cnt;

  task automatic chk(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
      $display("PASS: %s", nm);
    end else begin
      fail_cnt++;
      $display("FAIL: %s", nm);
    end
  endtask

  task automatic chk_va(input string nm,
                        input logic [VA_WIDTH-1:0] got,
                        input logic [VA_WIDTH-1:0] exp);
    if (got === exp) begin
      pass_cnt++;
      $display("PASS: %s", nm);
    end else begin
      fail_cnt++;
      $display("FAIL: %s  got %010h exp %010h", nm, got, exp);
    end
  endtask

  task automatic tick();
    @(posedge clk);
    #1;
  endtask

  function automatic bp_ftq_slot_t mk_slot(
      input logic                       sv,
      input logic [VA_WIDTH-1:0]        tgt,
      input bp_br_type_e                bt,
      input logic [FTB_BR_POS_BITS-1:0] ps);
    bp_ftq_slot_t s;
    s.slot_valid = sv;
    s.target     = tgt;
    s.br_type    = bt;
    s.taken      = 1'b0;
    s.pos        = ps;
    s.pred_src   = PRED_FTB;
    s.confidence = '0;
    return s;
  endfunction

  // Write one modelled entry: two slots at named positions and
  // types, and metadata whose ftb.hit and ftb.way are set per slot
  // so the carried writeWay scheme is visible in the update.
  task automatic put_entry(input int idx,
                           input bp_ftq_slot_t s0,
                           input bp_ftq_slot_t s1,
                           input logic         hit,
                           input int           way);
    m_entry[idx]           = '0;
    m_entry[idx].pc        = VA_WIDTH'(BASE_PC + idx * 32);
    m_entry[idx].pft_addr  = VA_WIDTH'(BASE_PC + idx * 32 + 32);
    m_entry[idx].branch_id = FTQ_IDX_BITS'(idx);
    m_entry[idx].valid     = 1'b1;
    m_entry[idx].slot[0]   = s0;
    m_entry[idx].slot[1]   = s1;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      m_meta[idx][s]                 = '0;
      m_meta[idx][s].ftb.hit         = hit;
      m_meta[idx][s].ftb.way         = FTB_WAY_BITS'(way);
      m_meta[idx][s].tage.branch_id  = FTQ_IDX_BITS'(idx);
      m_meta[idx][s].sc.branch_id    = FTQ_IDX_BITS'(idx + s);
    end
  endtask

  task automatic present(input int                        ch,
                         input int                        idx,
                         input logic [FTB_BR_POS_BITS-1:0] pos,
                         input bp_br_type_e               bt,
                         input logic                      tkn,
                         input logic [VA_WIDTH-1:0]       tgt,
                         input logic                      mis);
    bkend_rsv_val[ch]       = 1'b1;
    bkend_rsv[ch].ftq_idx    = FTQ_IDX_BITS'(idx);
    bkend_rsv[ch].pos        = pos;
    bkend_rsv[ch].taken      = tkn;
    bkend_rsv[ch].target     = tgt;
    bkend_rsv[ch].br_type    = bt;
    bkend_rsv[ch].mispredict = mis;
  endtask

  task automatic clr_ch(input int ch);
    bkend_rsv_val[ch] = 1'b0;
    bkend_rsv[ch]     = '0;
  endtask

  task automatic clr();
    for (int c = 0; c < NUM_RESOLVE_PORTS; c++) clr_ch(c);
  endtask

  task automatic all_rdy();
    ftb_sched_rdy  = '1;
    tage_upd_rdy   = 1'b1;
    ittage_upd_rdy = 1'b1;
    sc_upd_rdy     = 1'b1;
  endtask

  task automatic do_reset();
    rstn       = 1'b0;
    commit_ptr = '0;
    alloc_ptr  = FTQ_PTR_BITS'(FTQ_DEPTH);
    for (int i = 0; i < FTQ_DEPTH; i++) begin
      m_entry[i] = '0;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) m_meta[i][s] = '0;
    end
    clr();
    all_rdy();
    repeat (4) tick();
    rstn = 1'b1;
    settle();
  endtask


  // PRESENT THE STIMULUS ACROSS A CLOCK EDGE. A concurrent property
  // samples at posedge clk, so a case that drives its inputs, checks
  // with a delta delay and moves on never presents that state at an
  // edge -- and every property bound to this module is then inert,
  // which is the defect class TD#109 records and this project has
  // shipped twice. The DUT is COMBINATIONAL, so the edge changes
  // nothing it drives; what it changes is whether the properties see
  // the state at all.
  task automatic settle();
    #1;
    @(posedge clk);
    #1;
  endtask
  // -----------------------------------------------------------------
  // A. The intake buckets.
  // -----------------------------------------------------------------
  task automatic group_a();
    $display("-- A: the intake buckets --");
    do_reset();

    put_entry(4,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(3)),
      mk_slot(1'b1, 40'h00_9100_0000, COND, FTB_BR_POS_BITS'(11)),
      1'b1, 2);
    settle();
    chk("A1 no bucket fires with no resolution",
        !(|rsv_accept) && !(|rsv_nomap) && !(|rsv_drop_sq));

    present(0, 4, FTB_BR_POS_BITS'(3), COND, 1'b1,
            40'h00_9000_0000, 1'b0);
    settle();
    chk("A2 a live mapped resolution is accepted", rsv_accept[0]);
    chk("A3 and nothing else fires",
        !rsv_nomap[0] && !rsv_drop_sq[0]);
    chk("A4 the other channel is idle",
        !rsv_accept[1] && !rsv_nomap[1] && !rsv_drop_sq[1]);

    // R6, and it is checked continuously by the modelled arrays:
    // the read index IS the resolution's index, so the entry that
    // came back is the one the resolution named.
    chk   ("A5 the read index is the resolution's",
           rsv_rd_idx[0] == 6'd4);
    chk_va("A6 the entry that came back is that entry",
           rsv_entry[0].pc, VA_WIDTH'(BASE_PC + 4 * 32));
    clr();
  endtask

  // -----------------------------------------------------------------
  // B. Position to slot, both slots. Problem 6's first criterion.
  // -----------------------------------------------------------------
  task automatic group_b();
    $display("-- B: position to slot --");
    do_reset();

    // Positions 3 and 11, program ordered: the lower position is
    // slot 0 (IC-FTB-16). The two are far apart so a mapping that
    // matched on a truncated compare would still separate them; a
    // second pair one apart is used below to catch that.
    put_entry(9,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(3)),
      mk_slot(1'b1, 40'h00_9100_0000, INDIRECT_NONRET,
              FTB_BR_POS_BITS'(11)),
      1'b1, 1);

    present(0, 9, FTB_BR_POS_BITS'(3), COND, 1'b1,
            40'h00_9000_0000, 1'b0);
    settle();
    chk("B1 the lower position maps to slot 0",
        rsv_accept[0] && (rsv_slot[0] == TRX_SLOT_BITS'(0)));

    present(0, 9, FTB_BR_POS_BITS'(11), INDIRECT_NONRET, 1'b1,
            40'h00_9200_0000, 1'b0);
    settle();
    chk("B2 the higher position maps to slot 1",
        rsv_accept[0] && (rsv_slot[0] == TRX_SLOT_BITS'(1)));

    // ADJACENT POSITIONS. The mapping is EXACT because positions
    // are unique within an entry -- one per 2-byte slot, so no two
    // branches in a block can share one. It was ambiguous until the
    // field was widened to 4 bits, and adjacent positions are what
    // the old 3-bit field collided.
    put_entry(9,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(6)),
      mk_slot(1'b1, 40'h00_9100_0000, COND, FTB_BR_POS_BITS'(7)),
      1'b1, 1);
    present(0, 9, FTB_BR_POS_BITS'(6), COND, 1'b1,
            40'h00_9000_0000, 1'b0);
    settle();
    chk("B3 adjacent positions separate, slot 0",
        rsv_slot[0] == TRX_SLOT_BITS'(0));
    present(0, 9, FTB_BR_POS_BITS'(7), COND, 1'b1,
            40'h00_9100_0000, 1'b0);
    settle();
    chk("B4 adjacent positions separate, slot 1",
        rsv_slot[0] == TRX_SLOT_BITS'(1));

    // POSITION 0 AND POSITION 15, the two ends of the field.
    put_entry(9,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(0)),
      mk_slot(1'b1, 40'h00_9100_0000, COND, FTB_BR_POS_BITS'(15)),
      1'b1, 1);
    present(0, 9, FTB_BR_POS_BITS'(0), COND, 1'b1,
            40'h00_9000_0000, 1'b0);
    settle();
    chk("B5 position 0 maps", rsv_slot[0] == TRX_SLOT_BITS'(0));
    present(0, 9, FTB_BR_POS_BITS'(15), COND, 1'b1,
            40'h00_9100_0000, 1'b0);
    settle();
    chk("B6 position 15 maps", rsv_slot[0] == TRX_SLOT_BITS'(1));

    // AN INVALID SLOT AT A MATCHING POSITION does not map. Slot
    // validity is part of the match: a slot the FTB never filled
    // holds a stale position from a previous use of the entry.
    put_entry(9,
      mk_slot(1'b0, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(6)),
      mk_slot(1'b1, 40'h00_9100_0000, COND, FTB_BR_POS_BITS'(7)),
      1'b1, 1);
    present(0, 9, FTB_BR_POS_BITS'(6), COND, 1'b1,
            40'h00_9000_0000, 1'b0);
    settle();
    chk("B7 an invalid slot does not map", rsv_nomap[0]);
    clr();

    // THE TWO CHANNELS MAP INDEPENDENTLY, on different entries.
    put_entry(9,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(2)),
      mk_slot(1'b1, 40'h00_9100_0000, COND, FTB_BR_POS_BITS'(8)),
      1'b1, 1);
    put_entry(20,
      mk_slot(1'b1, 40'h00_9200_0000, COND, FTB_BR_POS_BITS'(5)),
      mk_slot(1'b1, 40'h00_9300_0000, COND, FTB_BR_POS_BITS'(13)),
      1'b0, 3);
    present(0, 9,  FTB_BR_POS_BITS'(8),  COND, 1'b1,
            40'h00_9100_0000, 1'b0);
    present(1, 20, FTB_BR_POS_BITS'(5),  COND, 1'b0,
            40'h00_9200_0000, 1'b1);
    settle();
    chk   ("B8 channel 0 maps to slot 1",
           rsv_accept[0] && (rsv_slot[0] == TRX_SLOT_BITS'(1)));
    chk   ("B9 channel 1 maps to slot 0",
           rsv_accept[1] && (rsv_slot[1] == TRX_SLOT_BITS'(0)));
    chk_va("B10 and each read its own entry", rsv_entry[1].pc,
           VA_WIDTH'(BASE_PC + 20 * 32));
    clr();
  endtask

  // -----------------------------------------------------------------
  // C. An unmapped position is REPORTED. Problem 6's second.
  // -----------------------------------------------------------------
  task automatic group_c();
    $display("-- C: the unmapped position --");
    do_reset();

    put_entry(9,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(3)),
      mk_slot(1'b1, 40'h00_9100_0000, COND, FTB_BR_POS_BITS'(11)),
      1'b1, 1);

    // Position 7 names neither slot. The entry describes a
    // different set of branches than the one that executed -- a
    // stale or aliased FTB entry -- and it is NOT the same
    // condition as a squashed entry.
    present(0, 9, FTB_BR_POS_BITS'(7), COND, 1'b1,
            40'h00_9400_0000, 1'b0);
    settle();
    chk("C1 an unmapped position is REPORTED", rsv_nomap[0]);
    chk("C2 it is not reported as a squash",   !rsv_drop_sq[0]);
    chk("C3 it is not accepted",               !rsv_accept[0]);
    chk("C4 and it forms no FTB update",       !ftb_upd_val[0]);
    chk("C5 and no predictor update",
        (upd_tage_val == '0) && (upd_ubtb_val == '0) &&
        (upd_ittage_val == '0) && (upd_sc_val == '0) &&
        (upd_lp_val == '0));

    // AN ENTRY WITH NO VALID SLOTS AT ALL. Allocation is
    // unconditional (5.2), so an entry exists for a block the p1
    // predictors missed and no later stage corrected; a resolution
    // for a branch in it maps to nothing.
    put_entry(9,
      mk_slot(1'b0, '0, NO_BRANCH, '0),
      mk_slot(1'b0, '0, NO_BRANCH, '0), 1'b0, 0);
    settle();
    chk("C6 an entry with no valid slots reports nomap",
        rsv_nomap[0]);

    // The two channels report independently: one maps, one does
    // not, and the mapping one still forms its update.
    put_entry(9,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(3)),
      mk_slot(1'b0, '0, NO_BRANCH, '0), 1'b1, 1);
    present(0, 9, FTB_BR_POS_BITS'(3), COND, 1'b1,
            40'h00_9000_0000, 1'b0);
    present(1, 9, FTB_BR_POS_BITS'(12), COND, 1'b1,
            40'h00_9500_0000, 1'b0);
    settle();
    chk("C7 one channel maps and the other reports",
        rsv_accept[0] && rsv_nomap[1]);
    chk("C8 the mapping channel still updates", ftb_upd_val[0]);
    clr();
  endtask

  // -----------------------------------------------------------------
  // D. R3, the squashed resolution.
  // -----------------------------------------------------------------
  task automatic group_d();
    $display("-- D: the squashed resolution --");
    do_reset();

    put_entry(9,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(3)),
      mk_slot(1'b0, '0, NO_BRANCH, '0), 1'b1, 1);

    // A live window of 5 through 19.
    commit_ptr = FTQ_PTR_BITS'(5);
    alloc_ptr  = FTQ_PTR_BITS'(20);
    present(0, 9, FTB_BR_POS_BITS'(3), COND, 1'b1,
            40'h00_9000_0000, 1'b0);
    settle();
    chk("D1 an entry inside the window is accepted", rsv_accept[0]);

    // The window moves past it. The resolution is DROPPED SILENTLY
    // -- normal traffic, not an error: a branch in flight when an
    // older branch redirects resolves after the squash.
    commit_ptr = FTQ_PTR_BITS'(12);
    settle();
    chk("D2 an entry behind commit_ptr is dropped", rsv_drop_sq[0]);
    chk("D3 it is not reported as unmapped",        !rsv_nomap[0]);
    chk("D4 and it forms no update",                !ftb_upd_val[0]);

    // An entry AHEAD of alloc_ptr is not live either.
    commit_ptr = FTQ_PTR_BITS'(5);
    alloc_ptr  = FTQ_PTR_BITS'(8);
    settle();
    chk("D5 an entry past alloc_ptr is dropped", rsv_drop_sq[0]);

    // AN EMPTY QUEUE drops everything: no index is live.
    commit_ptr = FTQ_PTR_BITS'(9);
    alloc_ptr  = FTQ_PTR_BITS'(9);
    settle();
    chk("D6 an empty queue drops every resolution", rsv_drop_sq[0]);

    // ACROSS THE WRAP. A window from 60 to 68 covers indices 60..63
    // and 0..3. A raw index compare reports the complement.
    put_entry(2,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(3)),
      mk_slot(1'b0, '0, NO_BRANCH, '0), 1'b1, 1);
    put_entry(30,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(3)),
      mk_slot(1'b0, '0, NO_BRANCH, '0), 1'b1, 1);
    commit_ptr = FTQ_PTR_BITS'(60);
    alloc_ptr  = FTQ_PTR_BITS'(68);
    present(0, 2, FTB_BR_POS_BITS'(3), COND, 1'b1,
            40'h00_9000_0000, 1'b0);
    settle();
    chk("D7 index 2 is inside the wrapping window", rsv_accept[0]);
    present(0, 30, FTB_BR_POS_BITS'(3), COND, 1'b1,
            40'h00_9000_0000, 1'b0);
    settle();
    chk("D8 index 30 is outside it", rsv_drop_sq[0]);
    clr();
    commit_ptr = '0;
    alloc_ptr  = FTQ_PTR_BITS'(FTQ_DEPTH);
  endtask

  // -----------------------------------------------------------------
  // E. THE FTB UPDATE, UNCHANGED. Problem 6's third criterion.
  // -----------------------------------------------------------------
  task automatic group_e();
    $display("-- E: the FTB update --");
    do_reset();

    put_entry(17,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(3)),
      mk_slot(1'b1, 40'h00_9100_0000, COND, FTB_BR_POS_BITS'(11)),
      1'b1, 2);

    present(0, 17, FTB_BR_POS_BITS'(11), COND, 1'b1,
            40'h00_ABCD_0000, 1'b1);
    settle();
    chk   ("E1 the update is presented",  ftb_upd_val[0]);
    chk_va("E2 the PC is the entry's",    ftb_upd[0].pc,
           VA_WIDTH'(BASE_PC + 17 * 32));
    chk   ("E3 the direction passes through", ftb_upd[0].taken);
    chk_va("E4 the target passes through", ftb_upd[0].target,
           40'h00_ABCD_0000);
    chk   ("E5 the position passes through",
           ftb_upd[0].pos == FTB_BR_POS_BITS'(11));
    chk_va("E6 the fall-through is the entry's",
           ftb_upd[0].pft_addr,
           VA_WIDTH'(BASE_PC + 17 * 32 + 32));
    chk   ("E7 the mispredict bit passes through",
           ftb_upd_mispred[0]);

    // The carried writeWay scheme (IC-FTB-10): the FTB determines
    // hit and way at the prediction read and does not re-look-up
    // the tag at update, so they come out of the SLOW PATH.
    chk("E8 hit comes from the metadata",
        ftb_upd_hit[0] && ftb_upd[0].hit);
    chk("E9 way comes from the metadata",
        ftb_upd[0].way == FTB_WAY_BITS'(2));

    // A CONDITIONAL fills a branch field; br_idx IS the slot,
    // because the slot array is program ordered and br0 maps to
    // slot 0 at the cluster boundary.
    chk("E10 a conditional sets is_br",
        ftb_upd[0].is_br && !ftb_upd[0].is_jmp);
    chk("E11 br_idx is the mapped slot", ftb_upd[0].br_idx == 1'b1);

    // A JUMP fills the jump field instead.
    present(0, 17, FTB_BR_POS_BITS'(3), DIRECT_UNC, 1'b1,
            40'h00_BEEF_0000, 1'b0);
    settle();
    chk("E12 a jump sets is_jmp",
        ftb_upd[0].is_jmp && !ftb_upd[0].is_br);
    chk("E13 and not is_call or is_ret",
        !ftb_upd[0].is_call && !ftb_upd[0].is_ret);

    present(0, 17, FTB_BR_POS_BITS'(3), DIRECT_CALL, 1'b1,
            40'h00_BEEF_0000, 1'b0);
    settle();
    chk("E14 a direct call sets is_call",
        ftb_upd[0].is_call && !ftb_upd[0].is_jalr);

    present(0, 17, FTB_BR_POS_BITS'(3), RETURN, 1'b1,
            40'h00_BEEF_0000, 1'b0);
    settle();
    chk("E15 a return sets is_ret and is_jalr",
        ftb_upd[0].is_ret && ftb_upd[0].is_jalr);

    present(0, 17, FTB_BR_POS_BITS'(3), INDIRECT_CALL, 1'b1,
            40'h00_BEEF_0000, 1'b0);
    settle();
    chk("E16 an indirect call is both call and jalr",
        ftb_upd[0].is_call && ftb_upd[0].is_jalr);

    // NO_BRANCH FORMS NO FTB UPDATE. S1 of 5.7.3 reads is_br |
    // is_jmp, so an update that set neither would be presented as
    // valid and classified as not FTB-bound -- accepted and then
    // ignored, with no drop reported.
    present(0, 17, FTB_BR_POS_BITS'(3), NO_BRANCH, 1'b0,
            40'h0, 1'b0);
    settle();
    chk("E17 NO_BRANCH forms no FTB update", !ftb_upd_val[0]);
    clr();
  endtask

  // -----------------------------------------------------------------
  // F. Fan-out by resolved br_type, fe_decisions.md 7.2.
  // -----------------------------------------------------------------
  task automatic group_f();
    $display("-- F: the update fan-out --");
    do_reset();

    put_entry(21,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(4)),
      mk_slot(1'b1, 40'h00_9100_0000, INDIRECT_NONRET,
              FTB_BR_POS_BITS'(12)),
      1'b1, 0);

    // conditional -> uBTB, LP, FTB, TAGE, SC.
    present(0, 21, FTB_BR_POS_BITS'(4), COND, 1'b1,
            40'h00_9000_0000, 1'b0);
    settle();
    chk("F1 a conditional updates tage, sc and lp",
        upd_tage_val[0] && upd_sc_val[0] && upd_lp_val[0]);
    chk("F2 and the uBTB and the FTB",
        upd_ubtb_val[0] && ftb_upd_val[0]);
    chk("F3 and NOT ittage",              !upd_ittage_val[0]);
    chk("F4 the payload is on the mapped slot",
        upd[0].valid && !upd[1].valid);
    chk("F5 the payload carries the resolution",
        (upd[0].actual_taken == 1'b1) &&
        (upd[0].br_type == COND) &&
        (upd[0].branch_id == 6'd21));
    chk("F6 the metadata goes with it",
        upd_meta[0].tage.branch_id == FTQ_IDX_BITS'(21));

    // indirect -> uBTB, FTB, ITTAGE.
    present(0, 21, FTB_BR_POS_BITS'(12), INDIRECT_NONRET, 1'b1,
            40'h00_9100_0000, 1'b0);
    settle();
    chk("F7 an indirect updates ittage",  upd_ittage_val[1]);
    chk("F8 and not tage, sc or lp",
        !upd_tage_val[1] && !upd_sc_val[1] && !upd_lp_val[1]);
    chk("F9 and the uBTB and the FTB",
        upd_ubtb_val[1] && ftb_upd_val[0]);
    chk("F10 on slot 1, which is where the position mapped",
        upd[1].valid && !upd[0].valid);

    // INDIRECT_CALL takes the indirect arm: it updates ITTAGE for
    // the TARGET (FE-U9). Its RAS push reads the fast-path
    // snapshot, not the metadata, so no RAS traffic forms here.
    m_entry[21].slot[1].br_type = INDIRECT_CALL;
    present(0, 21, FTB_BR_POS_BITS'(12), INDIRECT_CALL, 1'b1,
            40'h00_9100_0000, 1'b0);
    settle();
    chk("F11 an indirect call updates ittage", upd_ittage_val[1]);

    // return -> uBTB, FTB, RAS. The RAS update is the COMMIT group,
    // fed from the commit walk of 5.4, so a return forms no
    // predictor update on this path at all.
    m_entry[21].slot[1].br_type = RETURN;
    present(0, 21, FTB_BR_POS_BITS'(12), RETURN, 1'b1,
            40'h00_9100_0000, 1'b0);
    settle();
    chk("F12 a return updates the uBTB and the FTB",
        upd_ubtb_val[1] && ftb_upd_val[0]);
    chk("F13 and no queued predictor",
        !upd_tage_val[1] && !upd_sc_val[1] &&
        !upd_lp_val[1]   && !upd_ittage_val[1]);

    // direct unconditional -> uBTB, FTB only.
    m_entry[21].slot[1].br_type = DIRECT_UNC;
    present(0, 21, FTB_BR_POS_BITS'(12), DIRECT_UNC, 1'b1,
            40'h00_9100_0000, 1'b0);
    settle();
    chk("F14 a direct unconditional updates the uBTB and FTB only",
        upd_ubtb_val[1] && ftb_upd_val[0] &&
        !upd_tage_val[1] && !upd_ittage_val[1]);

    // NO_BRANCH forms NO update at all.
    m_entry[21].slot[1].br_type = NO_BRANCH;
    present(0, 21, FTB_BR_POS_BITS'(12), NO_BRANCH, 1'b0,
            40'h0, 1'b0);
    settle();
    chk("F15 NO_BRANCH forms no update",
        !upd_ubtb_val[1] && !ftb_upd_val[0]);

    // BOTH CHANNELS AT ONCE, on the two slots of one entry. This is
    // the ordinary two-per-cycle case ftq_ftb_sched exists for.
    put_entry(21,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(4)),
      mk_slot(1'b1, 40'h00_9100_0000, COND, FTB_BR_POS_BITS'(12)),
      1'b1, 0);
    present(0, 21, FTB_BR_POS_BITS'(4),  COND, 1'b1,
            40'h00_9000_0000, 1'b0);
    present(1, 21, FTB_BR_POS_BITS'(12), COND, 1'b0,
            40'h00_9100_0000, 1'b1);
    settle();
    chk("F16 both slots update in one cycle",
        upd[0].valid && upd[1].valid);
    chk("F17 each carries its own direction",
        upd[0].actual_taken && !upd[1].actual_taken);
    chk("F18 both FTB channels are presented",
        ftb_upd_val[0] && ftb_upd_val[1]);
    clr();
  endtask

  // -----------------------------------------------------------------
  // G. R2 of ftq_entry_formats.md 3.1, and the ready.
  // -----------------------------------------------------------------
  task automatic group_g();
    $display("-- G: type disagreement and backpressure --");
    do_reset();

    // The entry says COND; the branch resolved INDIRECT_NONRET. The
    // metadata describes a different predictor set than the branch
    // that executed, so only the uBTB and the FTB form -- both
    // derive from the RESOLVED facts and from ftb, which lies
    // outside the deferred union.
    put_entry(25,
      mk_slot(1'b1, 40'h00_9000_0000, COND, FTB_BR_POS_BITS'(4)),
      mk_slot(1'b0, '0, NO_BRANCH, '0), 1'b1, 1);
    present(0, 25, FTB_BR_POS_BITS'(4), INDIRECT_NONRET, 1'b1,
            40'h00_9900_0000, 1'b1);
    settle();
    chk("G1 the disagreement is reported", rsv_type_dis[0]);
    chk("G2 the resolution is still accepted", rsv_accept[0]);
    chk("G3 ittage is suppressed",  !upd_ittage_val[0]);
    chk("G4 tage, sc and lp too",
        !upd_tage_val[0] && !upd_sc_val[0] && !upd_lp_val[0]);
    chk("G5 the uBTB still updates", upd_ubtb_val[0]);
    chk("G6 the FTB still updates",  ftb_upd_val[0]);
    chk("G7 and it corrects the classification",
        ftb_upd[0].is_jalr && !ftb_upd[0].is_br);

    // AGREEING types do not suppress, so G3 is not a constant.
    present(0, 25, FTB_BR_POS_BITS'(4), COND, 1'b1,
            40'h00_9900_0000, 1'b0);
    settle();
    chk("G8 an agreeing type does not suppress",
        !rsv_type_dis[0] && upd_tage_val[0]);

    // THE READY. FE-5: a full update queue stalls the update path
    // and the backend holds the resolution. A resolution is never
    // dropped for capacity.
    chk("G9 ready with every queue free", &ftq_bkend_rsv_rdy);

    tage_upd_rdy = 1'b0;
    settle();
    chk("G10 a full tage queue deasserts ready",
        !ftq_bkend_rsv_rdy[0] && !ftq_bkend_rsv_rdy[1]);
    chk("G11 and no update is formed",
        !upd_tage_val[0] && !upd_ubtb_val[0]);
    tage_upd_rdy = 1'b1;

    ittage_upd_rdy = 1'b0;
    settle();
    chk("G12 a full ittage queue deasserts ready",
        !ftq_bkend_rsv_rdy[0]);
    ittage_upd_rdy = 1'b1;

    sc_upd_rdy = 1'b0;
    settle();
    chk("G13 a full sc queue deasserts ready",
        !ftq_bkend_rsv_rdy[0]);
    sc_upd_rdy = 1'b1;

    // THE SCHEDULER'S READY IS PER CHANNEL (5.7.3 S6): it deasserts
    // only to stop a HIGH-value FTB update being dropped, and it
    // does so for one channel at a time.
    ftb_sched_rdy = 2'b01;
    settle();
    chk("G14 the scheduler ready is per channel",
        ftq_bkend_rsv_rdy[0] && !ftq_bkend_rsv_rdy[1]);
    all_rdy();
    settle();
    chk("G15 ready recovers", &ftq_bkend_rsv_rdy);
    clr();
  endtask

  // -----------------------------------------------------------------
  // Run
  // -----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    if (NUM_RESOLVE_PORTS != 2 || NUM_PRED_SLOTS != 2) begin
      $fatal(1, "tb_ftq_resolve: written for two ports, two slots");
    end

    do_reset();
    group_a();
    group_b();
    group_c();
    group_d();
    group_e();
    group_f();
    group_g();

    $display("tb_ftq_resolve: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ftq_resolve: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #400000;
    $fatal(1, "tb_ftq_resolve: timeout");
  end

endmodule : tb
