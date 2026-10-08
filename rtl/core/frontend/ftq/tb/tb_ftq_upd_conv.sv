// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ftq_upd_conv (BP-119, TD#151, TD#150),
// ftq_bpu_interfaces.md 8 and fe_decisions.md 7.2.
//
// The converter's inputs are ftq_resolve's per-slot record and
// requests, and the cluster's per-slot readies. This file plays both:
//
//   ftq_resolve  the requests for a resolved type are formed here from
//                this file's own copy of the 7.2 table (req_for), not
//                read from ftq_resolve, so the table is checked against
//                the converter rather than assumed
//   bp_cluster   tage_upd_rdy and ittage_upd_rdy are queue-not-full,
//                driven directly. sc_upd_rdy is MODELLED the way
//                bp_cluster drives it: asserted only when an SC update
//                is presented and the credit arbiter grants it
//                (m_sc_grant), so the combinational dependency of the
//                SC ready on the SC valid is exercised
//
// Groups:
//   A  idle: nothing presented, every slot accepted
//   B  all eight bp_br_type_e encodings on both slots: which
//      predictors receive the update and the uBTB structural bits
//   C  every payload field of every predictor against values this
//      file derives (branch PC, mispredict flags, SC range)
//   D  TD#150: a queue ready held low on ONE slot stalls the
//      predictor on both slots; a type that does not train it is not
//      stalled
//   E  the SC grant: presented, not granted, nothing accepted; granted,
//      everything accepted
//   S  SC disabled: no SC update, and the slot does not wait on SC
//   T  two slots in one cycle, both conditionals
//
// Every case starts from do_reset() and drives every input it reads.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  logic                          sc_enable;
  bp_update_t                    upd       [0:NUM_PRED_SLOTS-1];
  bp_ftq_meta_t                  upd_meta  [0:NUM_PRED_SLOTS-1];
  bp_ftq_entry_t                 upd_entry [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]     upd_ubtb_val;
  logic [NUM_PRED_SLOTS-1:0]     upd_lp_val;
  logic [NUM_PRED_SLOTS-1:0]     upd_tage_val;
  logic [NUM_PRED_SLOTS-1:0]     upd_ittage_val;
  logic [NUM_PRED_SLOTS-1:0]     upd_sc_val;
  logic [NUM_PRED_SLOTS-1:0]     upd_acc;
  logic [NUM_PRED_SLOTS-1:0]     tage_upd_rdy;
  logic [NUM_PRED_SLOTS-1:0]     ittage_upd_rdy;
  logic [NUM_PRED_SLOTS-1:0]     sc_upd_rdy;
  ubtb_upd_t [NUM_PRED_SLOTS-1:0] ubtb_upd_u0;
  logic [NUM_PRED_SLOTS-1:0]     lp_upd_valid_p0;
  lp_upd_t                       lp_upd_p0         [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]     tage_upd_val_u0;
  tage_upd_inp_t                 tage_upd_inp_u0   [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]     ittage_upd_val_u0;
  ittage_upd_inp_t               ittage_upd_inp_u0 [0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]     sc_upd_val_u0;
  sc_upd_inp_t                   sc_upd_inp_u0     [0:NUM_PRED_SLOTS-1];

  ftq_upd_conv dut (
    .clk               (clk),
    .rstn              (rstn),
    .sc_enable         (sc_enable),
    .upd               (upd),
    .upd_meta          (upd_meta),
    .upd_entry         (upd_entry),
    .upd_ubtb_val      (upd_ubtb_val),
    .upd_lp_val        (upd_lp_val),
    .upd_tage_val      (upd_tage_val),
    .upd_ittage_val    (upd_ittage_val),
    .upd_sc_val        (upd_sc_val),
    .upd_acc           (upd_acc),
    .tage_upd_rdy      (tage_upd_rdy),
    .ittage_upd_rdy    (ittage_upd_rdy),
    .sc_upd_rdy        (sc_upd_rdy),
    .ubtb_upd_u0       (ubtb_upd_u0),
    .lp_upd_valid_p0   (lp_upd_valid_p0),
    .lp_upd_p0         (lp_upd_p0),
    .tage_upd_val_u0   (tage_upd_val_u0),
    .tage_upd_inp_u0   (tage_upd_inp_u0),
    .ittage_upd_val_u0 (ittage_upd_val_u0),
    .ittage_upd_inp_u0 (ittage_upd_inp_u0),
    .sc_upd_val_u0     (sc_upd_val_u0),
    .sc_upd_inp_u0     (sc_upd_inp_u0)
  );

  // -----------------------------------------------------------------
  // The cluster's SC ready, modelled (bp_cluster sc_upd_rdy): the
  // per-slot SC queue ready ANDed with the arbiter's grant, and the
  // arbiter grants only a presented update. m_sc_rdy_int is the per
  // slot queue ready, m_sc_grant whether the arbiter would grant.
  // -----------------------------------------------------------------
  logic [NUM_PRED_SLOTS-1:0] m_sc_rdy_int;
  logic                      m_sc_grant;

  always_comb begin : sc_rdy_model
    sc_upd_rdy = m_sc_rdy_int
               & {NUM_PRED_SLOTS{m_sc_grant & sc_enable
                                 & (|sc_upd_val_u0)}};
  end

  int pass_cnt;
  int fail_cnt;

  task automatic chk(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: %s", nm);
    end
  endtask

  task automatic chk_va(input string nm, input logic [VA_WIDTH-1:0] got,
                        input logic [VA_WIDTH-1:0] exp);
    if (got === exp) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: %s  got %h exp %h", nm, got, exp);
    end
  endtask

  // A concurrent property samples at posedge clk; present the state
  // across an edge so the bound properties see it (TD#109).
  task automatic settle();
    #1;
    @(posedge clk);
    #1;
  endtask

  // -----------------------------------------------------------------
  // This file's copy of the fe_decisions.md 7.2 table: which
  // predictors a resolved type trains through this path. RAS is the
  // commit group and FTB the scheduler, neither of them here.
  // -----------------------------------------------------------------
  typedef struct packed {
    logic ubtb;
    logic lp;
    logic tage;
    logic ittage;
    logic sc;
  } req_t;

  function automatic req_t req_for(input bp_br_type_e bt);
    req_t r;
    r = '0;
    case (bt)
      COND:            begin r.ubtb = 1'b1; r.lp = 1'b1; r.tage = 1'b1;
                             r.sc = 1'b1; end
      INDIRECT_NONRET: begin r.ubtb = 1'b1; r.ittage = 1'b1; end
      INDIRECT_CALL:   begin r.ubtb = 1'b1; r.ittage = 1'b1; end
      RETURN:          r.ubtb = 1'b1;
      DIRECT_UNC:      r.ubtb = 1'b1;
      DIRECT_CALL:     r.ubtb = 1'b1;
      RETURN_CALL:     r.ubtb = 1'b1;
      default:         ;                         // NO_BRANCH
    endcase
    return r;
  endfunction

  // The uBTB structural bits for each type, a literal table
  // (ubtb_interfaces.md upd_u0; ftq_resolve sets the FTB's the same
  // way). Order: {is_br, is_jmp, is_call, is_ret, is_jalr}.
  function automatic logic [4:0] bits_for(input bp_br_type_e bt);
    case (bt)
      COND:            return 5'b10000;
      DIRECT_CALL:     return 5'b01100;
      INDIRECT_CALL:   return 5'b01101;
      RETURN:          return 5'b01011;
      INDIRECT_NONRET: return 5'b01001;
      DIRECT_UNC:      return 5'b01000;
      RETURN_CALL:     return 5'b01111;
      default:         return 5'b00000;          // NO_BRANCH
    endcase
  endfunction

  // A fixed bit pattern for the metadata, so a payload field that
  // takes the wrong source cannot match by being zero.
  localparam logic [1023:0] PAT_A = {32{32'h5A3C_96E1}};
  localparam logic [1023:0] PAT_B = {32{32'hC3A5_1E78}};

  localparam logic [VA_WIDTH-1:0] PC0 = VA_WIDTH'('h00_8123_4440);

  task automatic clr_slot(input int s);
    upd[s]            = '0;
    upd_meta[s]       = '0;
    upd_entry[s]      = '0;
    upd_ubtb_val[s]   = 1'b0;
    upd_lp_val[s]     = 1'b0;
    upd_tage_val[s]   = 1'b0;
    upd_ittage_val[s] = 1'b0;
    upd_sc_val[s]     = 1'b0;
  endtask

  task automatic all_rdy();
    tage_upd_rdy   = '1;
    ittage_upd_rdy = '1;
    m_sc_rdy_int   = '1;
    m_sc_grant     = 1'b1;
  endtask

  task automatic do_reset();
    rstn      = 1'b0;
    sc_enable = 1'b1;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) clr_slot(s);
    all_rdy();
    repeat (3) @(posedge clk);
    rstn = 1'b1;
    settle();
  endtask

  // Present one resolution on slot s, as ftq_resolve would: the
  // record, the metadata and entry of its block, and the requests the
  // 7.2 table gives its type. pos is the slot's start-relative
  // position in the entry.
  task automatic present(input int                         s,
                         input bp_br_type_e                bt,
                         input logic [VA_WIDTH-1:0]        pc,
                         input logic [FTB_BR_POS_BITS-1:0] pos,
                         input logic                       tkn,
                         input logic [VA_WIDTH-1:0]        tgt,
                         input logic [VA_WIDTH-1:0]        pft,
                         input logic [1023:0]              pat);
    req_t r;
    r = req_for(bt);
    upd[s]               = '0;
    upd[s].branch_id     = FTQ_IDX_BITS'(9 + s);
    upd[s].pc            = pc;
    upd[s].actual_taken  = tkn;
    upd[s].actual_target = tgt;
    upd[s].br_type       = bt;
    upd[s].mispredicted  = 1'b0;
    upd[s].valid         = 1'b1;
    upd_meta[s].tage     = pat[$bits(tage_pred_meta_t)-1:0];
    upd_meta[s].sc       = pat[$bits(sc_pred_meta_t)-1:0];
    upd_meta[s].lp       = pat[$bits(lp_pred_t)-1:0];
    upd_meta[s].ittage   = pat[$bits(ittage_pred_meta_t)-1:0];
    upd_meta[s].ftb      = '0;
    upd_entry[s]         = '0;
    upd_entry[s].pc      = pc;
    upd_entry[s].pft_addr = pft;
    upd_entry[s].valid   = 1'b1;
    upd_entry[s].slot[s].slot_valid = 1'b1;
    upd_entry[s].slot[s].br_type    = bt;
    upd_entry[s].slot[s].pos        = pos;
    upd_ubtb_val[s]      = r.ubtb;
    upd_lp_val[s]        = r.lp;
    upd_tage_val[s]      = r.tage;
    upd_ittage_val[s]    = r.ittage;
    upd_sc_val[s]        = r.sc;
  endtask

  // The branch PC this file expects: start plus pos two-byte units.
  function automatic logic [VA_WIDTH-1:0] br_pc(
      input logic [VA_WIDTH-1:0] pc, input logic [FTB_BR_POS_BITS-1:0] pos);
    return pc + VA_WIDTH'({pos, 1'b0});
  endfunction

  // -----------------------------------------------------------------
  // A. Idle.
  // -----------------------------------------------------------------
  task automatic group_a();
    $display("-- A: idle --");
    do_reset();
    chk("A1 nothing presented to any predictor",
        (ubtb_upd_u0[0].valid === 1'b0) && (ubtb_upd_u0[1].valid === 1'b0)
     && (lp_upd_valid_p0 === '0) && (tage_upd_val_u0 === '0)
     && (ittage_upd_val_u0 === '0) && (sc_upd_val_u0 === '0));
    chk("A2 a slot with no request is accepted", upd_acc === '1);
    chk("A3 no payload without a record",
        (ubtb_upd_u0 === '0) && (lp_upd_p0[0] === '0)
     && (tage_upd_inp_u0[0] === '0) && (sc_upd_inp_u0[1] === '0));
  endtask

  // -----------------------------------------------------------------
  // B. All eight encodings, both slots.
  // -----------------------------------------------------------------
  task automatic group_b();
    bp_br_type_e bt;
    req_t        r;
    logic [4:0]  b;
    $display("-- B: all eight encodings, both slots --");
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      for (int t = 0; t < 8; t++) begin
        do_reset();
        bt = bp_br_type_e'(t);
        r  = req_for(bt);
        b  = bits_for(bt);
        present(s, bt, PC0, FTB_BR_POS_BITS'(5), 1'b1,
                VA_WIDTH'('h00_8000_0100), PC0 + VA_WIDTH'(14), PAT_A);
        settle();
        chk($sformatf("B slot %0d %s: accepted", s, bt.name()),
            upd_acc[s] === 1'b1);
        chk($sformatf("B slot %0d %s: uBTB valid as 7.2", s, bt.name()),
            ubtb_upd_u0[s].valid === r.ubtb);
        chk($sformatf("B slot %0d %s: LP valid as 7.2", s, bt.name()),
            lp_upd_valid_p0[s] === r.lp);
        chk($sformatf("B slot %0d %s: TAGE valid as 7.2", s, bt.name()),
            tage_upd_val_u0[s] === r.tage);
        chk($sformatf("B slot %0d %s: ITTAGE valid as 7.2", s, bt.name()),
            ittage_upd_val_u0[s] === r.ittage);
        chk($sformatf("B slot %0d %s: SC valid as 7.2", s, bt.name()),
            sc_upd_val_u0[s] === r.sc);
        chk($sformatf("B slot %0d %s: uBTB structural bits", s, bt.name()),
            {ubtb_upd_u0[s].is_br, ubtb_upd_u0[s].is_jmp,
             ubtb_upd_u0[s].is_call, ubtb_upd_u0[s].is_ret,
             ubtb_upd_u0[s].is_jalr} === b);
        chk($sformatf("B slot %0d %s: the other slot is untouched",
                      s, bt.name()),
            (ubtb_upd_u0[1-s] === '0) && (lp_upd_valid_p0[1-s] === 1'b0)
         && (tage_upd_val_u0[1-s] === 1'b0)
         && (ittage_upd_val_u0[1-s] === 1'b0)
         && (sc_upd_val_u0[1-s] === 1'b0));
      end
    end
  endtask

  // -----------------------------------------------------------------
  // C. Every payload field.
  // -----------------------------------------------------------------
  task automatic group_c();
    logic [VA_WIDTH-1:0] pc;
    logic [VA_WIDTH-1:0] tgt;
    logic [VA_WIDTH-1:0] pft;
    logic [VA_WIDTH-1:0] bpc;
    $display("-- C: payload fields --");

    // C1-C5: a conditional on slot 1, backward, taken. Position 6.
    do_reset();
    pc  = VA_WIDTH'('h00_8124_FFC0);
    tgt = VA_WIDTH'('h00_8124_FF80);
    pft = pc + VA_WIDTH'(18);
    bpc = br_pc(pc, FTB_BR_POS_BITS'(6));
    present(1, COND, pc, FTB_BR_POS_BITS'(6), 1'b1, tgt, pft, PAT_A);
    upd_meta[1].tage.tage_pred_tkn = 1'b0;     // TAGE said not taken
    upd_meta[1].sc.sc_pred_tkn     = 1'b1;     // SC said taken
    settle();
    // uBTB, every field.
    chk("C1 uBTB valid", ubtb_upd_u0[1].valid === 1'b1);
    chk_va("C1 uBTB pc is the block start", ubtb_upd_u0[1].pc, pc);
    chk("C1 uBTB is_br, br_idx 1 (slot 1), br_taken",
        (ubtb_upd_u0[1].is_br === 1'b1) && (ubtb_upd_u0[1].br_idx === 1'b1)
     && (ubtb_upd_u0[1].br_taken === 1'b1));
    chk_va("C1 uBTB target", ubtb_upd_u0[1].target, tgt);
    chk("C1 uBTB pos is the entry's", ubtb_upd_u0[1].pos === 4'd6);
    chk_va("C1 uBTB jmp_target is the resolved target",
           ubtb_upd_u0[1].jmp_target, tgt);
    chk_va("C1 uBTB pft_addr is the entry's", ubtb_upd_u0[1].pft_addr, pft);
    // LP.
    chk("C2 LP valid", lp_upd_valid_p0[1] === 1'b1);
    chk_va("C2 LP pc is the BRANCH pc (start + 2*pos)",
           lp_upd_p0[1].pc, bpc);
    chk_va("C2 LP target", lp_upd_p0[1].target, tgt);
    chk("C2 LP actual_taken", lp_upd_p0[1].actual_taken === 1'b1);
    chk("C2 LP table coordinates are the predict-time metadata",
        (lp_upd_p0[1].lp_idx === upd_meta[1].lp.lp_idx)
     && (lp_upd_p0[1].lp_tag === upd_meta[1].lp.lp_tag)
     && (lp_upd_p0[1].lp_way === upd_meta[1].lp.lp_way)
     && (lp_upd_p0[1].lp_hit === upd_meta[1].lp.lp_hit)
     && (lp_upd_p0[1].lp_pred_is_loop === upd_meta[1].lp.lp_pred_is_loop)
     && (lp_upd_p0[1].lp_pred_taken === upd_meta[1].lp.lp_pred_taken)
     && (lp_upd_p0[1].lp_age === upd_meta[1].lp.lp_age)
     && (lp_upd_p0[1].lp_conf === upd_meta[1].lp.lp_conf)
     && (lp_upd_p0[1].lp_past_itr === upd_meta[1].lp.lp_past_itr)
     && (lp_upd_p0[1].lp_curr_itr === upd_meta[1].lp.lp_curr_itr)
     && (lp_upd_p0[1].lp_curs === upd_meta[1].lp.lp_curs)
     && (lp_upd_p0[1].lp_curs_v === upd_meta[1].lp.lp_curs_v)
     && (lp_upd_p0[1].lp_victim === upd_meta[1].lp.lp_victim));
    // TAGE.
    chk("C3 TAGE valid", tage_upd_val_u0[1] === 1'b1);
    chk("C3 TAGE metadata", tage_upd_inp_u0[1].tage_pred_meta
                            === upd_meta[1].tage);
    chk("C3 TAGE resolved_taken", tage_upd_inp_u0[1].resolved_taken
                                  === 1'b1);
    chk("C3 TAGE cond_mispredict: TAGE said not taken, it was taken",
        tage_upd_inp_u0[1].cond_mispredict === 1'b1);
    // SC.
    chk("C4 SC valid", sc_upd_val_u0[1] === 1'b1);
    chk("C4 SC metadata", sc_upd_inp_u0[1].sc_pred_meta === upd_meta[1].sc);
    chk("C4 SC resolved_taken", sc_upd_inp_u0[1].resolved_taken === 1'b1);
    chk("C4 SC cond_mispredict: SC said taken, it was taken",
        sc_upd_inp_u0[1].cond_mispredict === 1'b0);
    chk("C4 SC backwards_branch: target below the branch PC",
        sc_upd_inp_u0[1].backwards_branch === 1'b1);
    chk("C4 SC branch_range is branch PC bits 15:6",
        sc_upd_inp_u0[1].branch_range === bpc[15:6]);
    chk("C5 ITTAGE not requested, not valid", ittage_upd_val_u0[1] === 1'b0);

    // C6: the same branch forward and not taken; TAGE right, SC wrong.
    tgt = pc + VA_WIDTH'('h200);
    present(1, COND, pc, FTB_BR_POS_BITS'(6), 1'b0, tgt, pft, PAT_B);
    upd_meta[1].tage.tage_pred_tkn = 1'b0;
    upd_meta[1].sc.sc_pred_tkn     = 1'b1;
    settle();
    chk("C6 TAGE cond_mispredict clear when TAGE was right",
        tage_upd_inp_u0[1].cond_mispredict === 1'b0);
    chk("C6 SC cond_mispredict set when SC was wrong",
        sc_upd_inp_u0[1].cond_mispredict === 1'b1);
    chk("C6 SC backwards_branch clear for a forward target",
        sc_upd_inp_u0[1].backwards_branch === 1'b0);
    chk("C6 metadata follows the record (pattern B)",
        tage_upd_inp_u0[1].tage_pred_meta === upd_meta[1].tage);

    // C7-C9: an indirect on slot 0. ITTAGE fields and indir_mispredict
    // for a hit that was right, a hit that was wrong, and a miss.
    do_reset();
    pc  = VA_WIDTH'('h00_8200_0000);
    tgt = VA_WIDTH'('h01_2345_6788);
    present(0, INDIRECT_NONRET, pc, FTB_BR_POS_BITS'(2), 1'b1, tgt,
            pc + VA_WIDTH'(8), PAT_A);
    upd_meta[0].ittage.ittage_hit           = 1'b1;
    upd_meta[0].ittage.ittage_using_primary = 1'b1;
    upd_meta[0].ittage.ittage_prm_tgt       = tgt[VA_WIDTH-1:1];
    upd_meta[0].ittage.ittage_alt_tgt       = '0;
    settle();
    chk("C7 ITTAGE valid", ittage_upd_val_u0[0] === 1'b1);
    chk("C7 ITTAGE metadata",
        ittage_upd_inp_u0[0].ittage_pred_meta === upd_meta[0].ittage);
    chk("C7 ITTAGE resolved_target is VA[40:1]",
        ittage_upd_inp_u0[0].resolved_target === tgt[VA_WIDTH-1:1]);
    chk("C7 primary hit on the right target: no mispredict",
        ittage_upd_inp_u0[0].indir_mispredict === 1'b0);
    chk("C7 uBTB jmp: is_jmp, is_jalr, jmp_target",
        (ubtb_upd_u0[0].is_jmp === 1'b1) && (ubtb_upd_u0[0].is_jalr === 1'b1)
     && (ubtb_upd_u0[0].jmp_target === tgt)
     && (ubtb_upd_u0[0].br_idx === 1'b0));
    upd_meta[0].ittage.ittage_using_primary = 1'b0;   // alt provides
    settle();
    chk("C8 alternate provided a different target: mispredict",
        ittage_upd_inp_u0[0].indir_mispredict === 1'b1);
    upd_meta[0].ittage.ittage_alt_tgt = tgt[VA_WIDTH-1:1];
    settle();
    chk("C8 alternate provided the right target: no mispredict",
        ittage_upd_inp_u0[0].indir_mispredict === 1'b0);
    upd_meta[0].ittage.ittage_hit = 1'b0;
    settle();
    chk("C9 a miss is a mispredict (so ITTAGE can allocate)",
        ittage_upd_inp_u0[0].indir_mispredict === 1'b1);
  endtask

  // -----------------------------------------------------------------
  // D. TD#150: readies ANDed per predictor.
  // -----------------------------------------------------------------
  task automatic group_d();
    $display("-- D: per-slot readies ANDed per predictor --");

    // D1: TAGE queue full on slot 1 only; a conditional on slot 0.
    do_reset();
    present(0, COND, PC0, FTB_BR_POS_BITS'(3), 1'b1,
            VA_WIDTH'('h00_8000_0040), PC0 + VA_WIDTH'(8), PAT_A);
    tage_upd_rdy = 2'b01;
    settle();
    chk("D1 slot 0 not accepted though its own TAGE ready is high",
        upd_acc[0] === 1'b0);
    chk("D1 nothing presented for slot 0: uBTB, LP, TAGE",
        (ubtb_upd_u0[0].valid === 1'b0) && (lp_upd_valid_p0[0] === 1'b0)
     && (tage_upd_val_u0[0] === 1'b0));
    chk("D1 and SC is not asked (no grant can be taken)",
        sc_upd_val_u0[0] === 1'b0);
    tage_upd_rdy = 2'b11;
    settle();
    chk("D1 both TAGE readies high: accepted, all presented",
        (upd_acc[0] === 1'b1) && (ubtb_upd_u0[0].valid === 1'b1)
     && (lp_upd_valid_p0[0] === 1'b1) && (tage_upd_val_u0[0] === 1'b1)
     && (sc_upd_val_u0[0] === 1'b1));

    // D2: ITTAGE queue full on slot 0 only; an indirect call on slot 1.
    do_reset();
    present(1, INDIRECT_CALL, PC0, FTB_BR_POS_BITS'(9), 1'b1,
            VA_WIDTH'('h00_9000_0000), PC0 + VA_WIDTH'(20), PAT_B);
    ittage_upd_rdy = 2'b10;
    settle();
    chk("D2 slot 1 not accepted on slot 0's full ITTAGE queue",
        (upd_acc[1] === 1'b0) && (ittage_upd_val_u0[1] === 1'b0)
     && (ubtb_upd_u0[1].valid === 1'b0));
    ittage_upd_rdy = 2'b11;
    settle();
    chk("D2 accepted once both are ready",
        (upd_acc[1] === 1'b1) && (ittage_upd_val_u0[1] === 1'b1)
     && (ubtb_upd_u0[1].valid === 1'b1));

    // D3: a type that trains no queued predictor does not wait on one.
    do_reset();
    present(0, DIRECT_UNC, PC0, FTB_BR_POS_BITS'(1), 1'b1,
            VA_WIDTH'('h00_8000_0800), PC0 + VA_WIDTH'(6), PAT_A);
    tage_upd_rdy   = 2'b00;
    ittage_upd_rdy = 2'b00;
    m_sc_grant     = 1'b0;
    settle();
    chk("D3 a JAL is accepted with every queue full",
        (upd_acc[0] === 1'b1) && (ubtb_upd_u0[0].valid === 1'b1));

    // D4: the SC queue ready low on one slot (the arbiter would grant).
    do_reset();
    present(0, COND, PC0, FTB_BR_POS_BITS'(3), 1'b0,
            VA_WIDTH'('h00_8000_0040), PC0 + VA_WIDTH'(8), PAT_A);
    m_sc_rdy_int = 2'b01;
    settle();
    chk("D4 SC asked, its slot-1 ready low: slot 0 not accepted",
        (sc_upd_val_u0[0] === 1'b1) && (upd_acc[0] === 1'b0)
     && (tage_upd_val_u0[0] === 1'b0) && (ubtb_upd_u0[0].valid === 1'b0));
  endtask

  // -----------------------------------------------------------------
  // E. The SC grant.
  // -----------------------------------------------------------------
  task automatic group_e();
    $display("-- E: the SC grant --");
    do_reset();
    present(1, COND, PC0, FTB_BR_POS_BITS'(4), 1'b1,
            VA_WIDTH'('h00_8000_0100), PC0 + VA_WIDTH'(10), PAT_B);
    m_sc_grant = 1'b0;        // the arbiter gives the port to a prediction
    settle();
    chk("E1 the SC update is presented, so the arbiter sees a request",
        sc_upd_val_u0[1] === 1'b1);
    chk("E1 not granted: the slot is not accepted",
        upd_acc[1] === 1'b0);
    chk("E1 and no other predictor takes it",
        (tage_upd_val_u0[1] === 1'b0) && (lp_upd_valid_p0[1] === 1'b0)
     && (ubtb_upd_u0[1].valid === 1'b0));
    m_sc_grant = 1'b1;
    settle();
    chk("E2 granted: accepted and every predictor takes it",
        (upd_acc[1] === 1'b1) && (sc_upd_val_u0[1] === 1'b1)
     && (sc_upd_rdy === 2'b11) && (tage_upd_val_u0[1] === 1'b1)
     && (lp_upd_valid_p0[1] === 1'b1) && (ubtb_upd_u0[1].valid === 1'b1));
  endtask

  // -----------------------------------------------------------------
  // S. SC disabled.
  // -----------------------------------------------------------------
  task automatic group_s();
    $display("-- S: SC disabled --");
    do_reset();
    present(0, COND, PC0, FTB_BR_POS_BITS'(3), 1'b1,
            VA_WIDTH'('h00_8000_0040), PC0 + VA_WIDTH'(8), PAT_A);
    sc_enable  = 1'b0;
    m_sc_grant = 1'b0;
    settle();
    chk("S1 no SC update is formed", sc_upd_val_u0[0] === 1'b0);
    chk("S2 the slot does not wait on SC: accepted",
        upd_acc[0] === 1'b1);
    chk("S3 TAGE, LP and the uBTB take the conditional",
        (tage_upd_val_u0[0] === 1'b1) && (lp_upd_valid_p0[0] === 1'b1)
     && (ubtb_upd_u0[0].valid === 1'b1));
    sc_enable = 1'b1;
    settle();
    chk("S4 SC re-enabled, no grant: the slot waits again",
        (sc_upd_val_u0[0] === 1'b1) && (upd_acc[0] === 1'b0));
  endtask

  // -----------------------------------------------------------------
  // T. Two conditionals, one per slot, in one cycle.
  // -----------------------------------------------------------------
  task automatic group_t();
    $display("-- T: two slots in one cycle --");
    do_reset();
    present(0, COND, PC0, FTB_BR_POS_BITS'(2), 1'b1,
            VA_WIDTH'('h00_8000_0040), PC0 + VA_WIDTH'(30), PAT_A);
    present(1, COND, PC0, FTB_BR_POS_BITS'(11), 1'b0,
            VA_WIDTH'('h00_8000_0400), PC0 + VA_WIDTH'(30), PAT_B);
    settle();
    chk("T1 both accepted", upd_acc === 2'b11);
    chk("T1 both slots train TAGE, SC and the LP",
        (tage_upd_val_u0 === 2'b11) && (sc_upd_val_u0 === 2'b11)
     && (lp_upd_valid_p0 === 2'b11));
    chk("T1 each carries its own direction and branch PC",
        (tage_upd_inp_u0[0].resolved_taken === 1'b1)
     && (tage_upd_inp_u0[1].resolved_taken === 1'b0)
     && (lp_upd_p0[0].pc === br_pc(PC0, 4'd2))
     && (lp_upd_p0[1].pc === br_pc(PC0, 4'd11)));
    chk("T1 br_idx names the slot", (ubtb_upd_u0[0].br_idx === 1'b0)
                                 && (ubtb_upd_u0[1].br_idx === 1'b1));
  endtask

  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    if (NUM_PRED_SLOTS != 2) begin
      $fatal(1, "tb_ftq_upd_conv: written for two slots");
    end
    group_a();
    group_b();
    group_c();
    group_d();
    group_e();
    group_s();
    group_t();
    $display("tb_ftq_upd_conv: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ftq_upd_conv: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #200000;
    $fatal(1, "tb_ftq_upd_conv: timeout");
  end

endmodule : tb
