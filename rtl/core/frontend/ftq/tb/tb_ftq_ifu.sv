// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ftq_ifu (BP-107), ftq_ifu_interfaces.md.
//
// THE IFU DOES NOT EXIST -- rtl/core/frontend/ifu/rtl holds a
// .gitkeep -- so this file models it. Only the FTQ side is under
// test; the model presents requests' acceptances and writebacks and
// checks what comes back.
//
// Problem 5's three acceptance criteria:
//
//   the generation bit rejects a stale writeback and accepts a
//   current one                          -> group C
//   a predecode disagreement corrects the entry and redirects
//   WITHOUT forming a predictor update   -> group D, and see below
//   the flush of section 5 bounds stale writebacks to one
//                                        -> group E
//
// HOW "NO PREDICTOR UPDATE" IS CHECKED, since a negative is easy to
// claim and hard to test. ftq_ifu HAS NO UPDATE PORT AT ALL: the
// module's outputs are the request group, the flush group, the two
// status sets, the entry slot correction and the redirect, and
// nothing else. FE-8 is therefore structural here rather than
// behavioural: the instantiation below names every port, so a future
// change that added an update path would leave it unconnected and
// the PINMISSING warning would report it. There is no runtime check
// for it, because a check that can never fail is a comment.
//
// EVERY MECHANISM THE CASES RELY ON IS DRIVEN, not assumed. The
// entry contents, the gen bit and wb_rcvd are all module INPUTS,
// owned by ftq_entry and ftq_status, so each case sets them
// explicitly rather than depending on another module's behaviour.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  logic [FTQ_IDX_BITS-1:0]   fetch_idx;
  logic                      fetch_pending;
  bp_ftq_entry_t             fetch_entry;
  logic                      gen_fetch;
  logic                      gen_pdwb;
  logic                      wb_rcvd_pdwb;
  bp_ftq_entry_t             pdwb_entry;
  logic                      redir_val;
  logic [FTQ_IDX_BITS-1:0]   redir_idx;
  logic                      redir_self;
  ftq_redir_cause_e          redir_cause;
  logic                      ftq_ifu_req_val;
  logic                      ftq_ifu_req_rdy;
  logic [VA_WIDTH-1:0]       ftq_ifu_start_pc;
  logic [VA_WIDTH-1:0]       ftq_ifu_next_pc;
  logic [FTQ_IDX_BITS-1:0]   ftq_ifu_idx;
  logic                      ftq_ifu_taken_val;
  logic [FTB_BR_POS_BITS-1:0] ftq_ifu_taken_pos;
  logic                      ftq_ifu_gen;
  logic                      ftq_ifu_flush_val;
  logic [FTQ_IDX_BITS-1:0]   ftq_ifu_flush_idx;
  logic                      ifu_ftq_pdwb_val;
  logic [FTQ_IDX_BITS-1:0]   ifu_ftq_pdwb_idx;
  logic                      ifu_ftq_pdwb_gen;
  ftq_pd_info_t              ifu_ftq_pd [0:FTQ_PD_WIDTH-1];
  logic [FTQ_PD_WIDTH-1:0]   ifu_ftq_pd_range;
  logic                      ifu_ftq_cfi_val;
  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_cfi_pos;
  logic                      ifu_ftq_mis_val;
  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_mis_pos;
  logic [VA_WIDTH-1:0]       ifu_ftq_target;
  logic                      ifu_ftq_fault_val;
  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_fault_pos;
  logic                      wb_set_val;
  logic [FTQ_IDX_BITS-1:0]   wb_set_idx;
  logic                      fault_set_val;
  logic [FTQ_IDX_BITS-1:0]   fault_set_idx;
  logic                      pd_wr_val;
  logic [FTQ_IDX_BITS-1:0]   pd_wr_idx;
  logic [TRX_SLOT_BITS-1:0]  pd_wr_sel;
  bp_ftq_slot_t              pd_wr_slot;
  logic                      pd_wr_kill;
  logic                      pd_redir_val;
  logic [FTQ_IDX_BITS-1:0]   pd_redir_idx;
  logic [VA_WIDTH-1:0]       pd_redir_pc;
  logic                      wb_accept;
  logic                      wb_drop_gen;

  ftq_ifu dut (
    .clk               (clk),
    .rstn              (rstn),
    .fetch_idx         (fetch_idx),
    .fetch_pending     (fetch_pending),
    .fetch_entry       (fetch_entry),
    .gen_fetch         (gen_fetch),
    .gen_pdwb          (gen_pdwb),
    .wb_rcvd_pdwb      (wb_rcvd_pdwb),
    .pdwb_entry        (pdwb_entry),
    .redir_val         (redir_val),
    .redir_idx         (redir_idx),
    .redir_self        (redir_self),
    .redir_cause       (redir_cause),
    .ftq_ifu_req_val   (ftq_ifu_req_val),
    .ftq_ifu_req_rdy   (ftq_ifu_req_rdy),
    .ftq_ifu_start_pc  (ftq_ifu_start_pc),
    .ftq_ifu_next_pc   (ftq_ifu_next_pc),
    .ftq_ifu_idx       (ftq_ifu_idx),
    .ftq_ifu_taken_val (ftq_ifu_taken_val),
    .ftq_ifu_taken_pos (ftq_ifu_taken_pos),
    .ftq_ifu_gen       (ftq_ifu_gen),
    .ftq_ifu_flush_val (ftq_ifu_flush_val),
    .ftq_ifu_flush_idx (ftq_ifu_flush_idx),
    .ifu_ftq_pdwb_val  (ifu_ftq_pdwb_val),
    .ifu_ftq_pdwb_idx  (ifu_ftq_pdwb_idx),
    .ifu_ftq_pdwb_gen  (ifu_ftq_pdwb_gen),
    .ifu_ftq_pd        (ifu_ftq_pd),
    .ifu_ftq_pd_range  (ifu_ftq_pd_range),
    .ifu_ftq_cfi_val   (ifu_ftq_cfi_val),
    .ifu_ftq_cfi_pos   (ifu_ftq_cfi_pos),
    .ifu_ftq_mis_val   (ifu_ftq_mis_val),
    .ifu_ftq_mis_pos   (ifu_ftq_mis_pos),
    .ifu_ftq_target    (ifu_ftq_target),
    .ifu_ftq_fault_val (ifu_ftq_fault_val),
    .ifu_ftq_fault_pos (ifu_ftq_fault_pos),
    .wb_set_val        (wb_set_val),
    .wb_set_idx        (wb_set_idx),
    .fault_set_val     (fault_set_val),
    .fault_set_idx     (fault_set_idx),
    .pd_wr_val         (pd_wr_val),
    .pd_wr_idx         (pd_wr_idx),
    .pd_wr_sel         (pd_wr_sel),
    .pd_wr_slot        (pd_wr_slot),
    .pd_wr_kill        (pd_wr_kill),
    .pd_redir_val      (pd_redir_val),
    .pd_redir_idx      (pd_redir_idx),
    .pd_redir_pc       (pd_redir_pc),
    .wb_accept         (wb_accept),
    .wb_drop_gen       (wb_drop_gen)
  );

  localparam logic [VA_WIDTH-1:0] BLK_PC  = 40'h00_8000_0100;
  localparam logic [VA_WIDTH-1:0] BLK_PFT = 40'h00_8000_0120;
  localparam logic [VA_WIDTH-1:0] TGT0    = 40'h00_9000_0000;
  localparam logic [VA_WIDTH-1:0] TGT1    = 40'h00_A000_0000;
  localparam logic [VA_WIDTH-1:0] PD_TGT  = 40'h00_B000_0000;

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
      input logic                       tk,
      input logic [FTB_BR_POS_BITS-1:0] ps);
    bp_ftq_slot_t s;
    s.slot_valid = sv;
    s.target     = tgt;
    s.br_type    = bt;
    s.taken      = tk;
    s.pos        = ps;
    s.pred_src   = PRED_UBTB;
    s.confidence = '0;
    return s;
  endfunction

  function automatic ftq_pd_info_t mk_pd(
      input logic       vld,
      input logic       rvc,
      input logic [1:0] bt,
      input logic       cal,
      input logic       ret);
    ftq_pd_info_t p;
    p.valid   = vld;
    p.is_rvc  = rvc;
    p.br_type = bt;
    p.is_call = cal;
    p.is_ret  = ret;
    return p;
  endfunction

  // A whole entry with named slots.
  function automatic bp_ftq_entry_t mk_entry(
      input logic [FTQ_IDX_BITS-1:0] idx,
      input bp_ftq_slot_t            s0,
      input bp_ftq_slot_t            s1);
    bp_ftq_entry_t e;
    e            = '0;
    e.pc         = BLK_PC;
    e.pft_addr   = BLK_PFT;
    e.branch_id  = idx;
    e.valid      = 1'b1;
    e.slot[0]    = s0;
    e.slot[1]    = s1;
    return e;
  endfunction

  task automatic clr_wb();
    ifu_ftq_pdwb_val  = 1'b0;
    ifu_ftq_mis_val   = 1'b0;
    ifu_ftq_fault_val = 1'b0;
    ifu_ftq_cfi_val   = 1'b0;
  endtask

  task automatic do_reset();
    rstn              = 1'b0;
    fetch_idx         = '0;
    fetch_pending     = 1'b0;
    fetch_entry       = '0;
    gen_fetch         = 1'b0;
    gen_pdwb          = 1'b0;
    wb_rcvd_pdwb      = 1'b0;
    pdwb_entry        = '0;
    redir_val         = 1'b0;
    redir_idx         = '0;
    redir_self        = 1'b0;
    redir_cause       = RC_MISPREDICT;
    ftq_ifu_req_rdy   = 1'b1;
    ifu_ftq_pdwb_idx  = '0;
    ifu_ftq_pdwb_gen  = 1'b0;
    ifu_ftq_pd_range  = '0;
    ifu_ftq_cfi_pos   = '0;
    ifu_ftq_mis_pos   = '0;
    ifu_ftq_target    = '0;
    ifu_ftq_fault_pos = '0;
    for (int i = 0; i < FTQ_PD_WIDTH; i++) begin
      ifu_ftq_pd[i] = mk_pd(1'b0, 1'b0, 2'b00, 1'b0, 1'b0);
    end
    clr_wb();
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
  // A. Section 4, the fetch request.
  // -----------------------------------------------------------------
  task automatic group_a();
    $display("-- A: the fetch request --");
    do_reset();

    // No pending entry: no request. Presenting one for an entry the
    // FTQ has not allocated, or whose p1 write has not landed,
    // sends the IFU an address that does not exist yet.
    fetch_entry   = mk_entry(6'd5,
                      mk_slot(1'b1, TGT0, COND, 1'b0,
                              FTB_BR_POS_BITS'(3)),
                      mk_slot(1'b0, '0, NO_BRANCH, 1'b0, '0));
    fetch_idx     = 6'd5;
    gen_fetch     = 1'b1;
    fetch_pending = 1'b0;
    settle();
    chk("A1 no request with nothing pending", !ftq_ifu_req_val);

    fetch_pending = 1'b1;
    settle();
    chk   ("A2 a request is presented", ftq_ifu_req_val);
    chk   ("A3 it carries the entry index", ftq_ifu_idx == 6'd5);
    chk   ("A4 it carries the generation tag", ftq_ifu_gen);
    chk_va("A5 start_pc is the block start", ftq_ifu_start_pc,
           BLK_PC);

    // NO TAKEN SLOT: fetch the whole block, and the successor is
    // the fall-through -- fe_decisions.md 2.4's third arm read off
    // the stored entry.
    chk   ("A6 taken_val clear with no taken slot",
           !ftq_ifu_taken_val);
    chk_va("A7 next_pc is the fall-through", ftq_ifu_next_pc,
           BLK_PFT);

    // A TAKEN SLOT 0: truncate there and follow its target.
    fetch_entry = mk_entry(6'd5,
                    mk_slot(1'b1, TGT0, COND, 1'b1,
                            FTB_BR_POS_BITS'(3)),
                    mk_slot(1'b1, TGT1, COND, 1'b0,
                            FTB_BR_POS_BITS'(9)));
    settle();
    chk   ("A8 taken_val set",  ftq_ifu_taken_val);
    chk   ("A9 taken_pos is the slot's",
           ftq_ifu_taken_pos == FTB_BR_POS_BITS'(3));
    chk_va("A10 next_pc is the slot target", ftq_ifu_next_pc, TGT0);

    // TAKEN SLOT 1 ONLY.
    fetch_entry = mk_entry(6'd5,
                    mk_slot(1'b1, TGT0, COND, 1'b0,
                            FTB_BR_POS_BITS'(3)),
                    mk_slot(1'b1, TGT1, COND, 1'b1,
                            FTB_BR_POS_BITS'(9)));
    settle();
    chk   ("A11 slot 1 supplies the successor",
           ftq_ifu_taken_pos == FTB_BR_POS_BITS'(9));
    chk_va("A12 and its target", ftq_ifu_next_pc, TGT1);

    // BOTH TAKEN: slot 0 wins. Program order -- a taken branch ends
    // the block, so slot 1 is off the path.
    fetch_entry.slot[0].taken = 1'b1;
    settle();
    chk_va("A13 both taken, slot 0 wins", ftq_ifu_next_pc, TGT0);

    // ftq_ifu_req_rdy is NOT a condition on the request. It is the
    // IFU's acceptance, consumed by ftq_ptr to advance fetch_ptr.
    ftq_ifu_req_rdy = 1'b0;
    settle();
    chk("A14 req_rdy low does not withdraw the request",
        ftq_ifu_req_val);
    ftq_ifu_req_rdy = 1'b1;
  endtask

  // -----------------------------------------------------------------
  // B. Section 5, the flush.
  // -----------------------------------------------------------------
  task automatic group_b();
    $display("-- B: the flush --");
    do_reset();

    fetch_idx = 6'd30;
    settle();
    chk("B1 no flush with no redirect", !ftq_ifu_flush_val);

    // _self CLEAR: the naming entry survives, so the flush starts
    // one past it.
    redir_val   = 1'b1;
    redir_idx   = 6'd12;
    redir_self  = 1'b0;
    redir_cause = RC_MISPREDICT;
    settle();
    chk("B2 a flush is presented",       ftq_ifu_flush_val);
    chk("B3 _self clear starts at K+1",  ftq_ifu_flush_idx == 6'd13);

    // _self SET: the naming entry does not survive.
    redir_self = 1'b1;
    settle();
    chk("B4 _self set starts at K", ftq_ifu_flush_idx == 6'd12);

    // ACROSS THE WRAP. Index 63 with _self clear is index 0.
    redir_idx  = 6'd63;
    redir_self = 1'b0;
    settle();
    chk("B5 the flush index wraps", ftq_ifu_flush_idx == 6'd0);

    // RC_UNSPEC squashes EVERY entry and _idx and _self are
    // meaningless on it (U1, U2), so the flush index cannot come
    // from them. It comes from fetch_idx, so nothing the IFU holds
    // survives. Both meaningless fields are driven to values that
    // would give a different answer if read.
    redir_idx   = 6'd44;
    redir_self  = 1'b1;
    redir_cause = RC_UNSPEC;
    settle();
    chk("B6 RC_UNSPEC does not read _idx or _self",
        ftq_ifu_flush_idx == 6'd30);

    // ONE GROUP, and every source resolves into it before it
    // arrives: the flush tracks the winning redirect and nothing
    // else. A p2, a p3, a predecode and a backend redirect all
    // arrive on the same three ports.
    redir_cause = RC_TRAP;
    redir_idx   = 6'd9;
    redir_self  = 1'b0;
    settle();
    chk("B7 RC_TRAP flushes on the same group",
        ftq_ifu_flush_val && (ftq_ifu_flush_idx == 6'd10));
    redir_val = 1'b0;
    settle();
    chk("B8 the flush deasserts with the redirect",
        !ftq_ifu_flush_val);
  endtask

  // -----------------------------------------------------------------
  // C. Section 6.1, the generation test. TD-FE-8.
  // -----------------------------------------------------------------
  // ACCEPTANCE: the generation bit rejects a stale writeback and
  // accepts a current one.
  task automatic group_c();
    $display("-- C: the generation test --");
    do_reset();

    pdwb_entry = mk_entry(6'd8,
                   mk_slot(1'b1, TGT0, COND, 1'b0,
                           FTB_BR_POS_BITS'(3)),
                   mk_slot(1'b0, '0, NO_BRANCH, 1'b0, '0));
    ifu_ftq_pdwb_idx = 6'd8;

    // A CURRENT writeback: the tag matches the entry's gen bit.
    gen_pdwb         = 1'b1;
    ifu_ftq_pdwb_gen = 1'b1;
    ifu_ftq_pdwb_val = 1'b1;
    settle();
    chk("C1 a matching writeback is accepted", wb_accept);
    chk("C2 and is not reported as dropped",   !wb_drop_gen);
    chk("C3 wb_rcvd is set",
        wb_set_val && (wb_set_idx == 6'd8));

    // A STALE writeback: the entry has been reallocated since, so
    // the toggle moved the tag. Everything about it is dropped --
    // no status bit, no redirect, no field rewritten (X3).
    ifu_ftq_pdwb_gen  = 1'b0;
    ifu_ftq_mis_val   = 1'b1;
    ifu_ftq_mis_pos   = FTQ_PD_POS_BITS'(4);
    ifu_ftq_fault_val = 1'b1;
    ifu_ftq_pd[4]     = mk_pd(1'b1, 1'b0, 2'b10, 1'b0, 1'b0);
    ifu_ftq_target    = PD_TGT;
    settle();
    chk("C4 a stale writeback is not accepted",  !wb_accept);
    chk("C5 and IS reported as dropped",         wb_drop_gen);
    chk("C6 no status bit is set",
        !wb_set_val && !fault_set_val);
    chk("C7 no redirect is derived",             !pd_redir_val);
    chk("C8 no field is rewritten",              !pd_wr_val);

    // The other polarity, so the test is a COMPARE and not a
    // constant. A gen of 0 on both sides is a match too.
    gen_pdwb         = 1'b0;
    ifu_ftq_pdwb_gen = 1'b0;
    settle();
    chk("C9 a zero-zero match is accepted", wb_accept);
    gen_pdwb = 1'b1;
    settle();
    chk("C10 a zero-one mismatch is dropped", wb_drop_gen);

    // NO WRITEBACK PRESENTED: neither accepted nor dropped. A
    // module that reported a drop on an idle port would have
    // ftq_status clearing bits on every cycle.
    clr_wb();
    settle();
    chk("C11 an idle port is neither accepted nor dropped",
        !wb_accept && !wb_drop_gen);
  endtask

  // -----------------------------------------------------------------
  // D. Section 7, the predecode correction and redirect.
  // -----------------------------------------------------------------
  // ACCEPTANCE: a predecode disagreement corrects the entry and
  // redirects WITHOUT forming a predictor update.
  task automatic group_d();
    $display("-- D: the predecode correction --");
    do_reset();

    gen_pdwb         = 1'b1;
    ifu_ftq_pdwb_gen = 1'b1;
    ifu_ftq_pdwb_idx = 6'd8;
    wb_rcvd_pdwb     = 1'b0;

    // M1. The block was predicted to have no taken branch and
    // predecode found a JAL at position 6. Slot 0 holds a
    // not-taken conditional at position 3, so program order puts
    // the JAL in slot 1.
    pdwb_entry = mk_entry(6'd8,
                   mk_slot(1'b1, TGT0, COND, 1'b0,
                           FTB_BR_POS_BITS'(3)),
                   mk_slot(1'b0, '0, NO_BRANCH, 1'b0, '0));
    ifu_ftq_pd[6]    = mk_pd(1'b1, 1'b0, 2'b10, 1'b0, 1'b0);
    ifu_ftq_mis_val  = 1'b1;
    ifu_ftq_mis_pos  = FTQ_PD_POS_BITS'(6);
    ifu_ftq_target   = PD_TGT;
    ifu_ftq_pdwb_val = 1'b1;
    settle();
    chk   ("D1 the entry is corrected", pd_wr_val);
    chk   ("D2 in program order, slot 1",
           pd_wr_sel == TRX_SLOT_BITS'(1));
    chk   ("D3 the slot is valid",      pd_wr_slot.slot_valid);
    chk   ("D4 the type is the JAL",
           pd_wr_slot.br_type == DIRECT_UNC);
    chk   ("D5 an unconditional is taken", pd_wr_slot.taken);
    chk_va("D6 the target is predecode's", pd_wr_slot.target,
           PD_TGT);
    chk   ("D7 W2 is the identity conversion",
           pd_wr_slot.pos == FTB_BR_POS_BITS'(6));
    chk   ("D8 pred_src is PRED_NONE",
           pd_wr_slot.pred_src == PRED_NONE);
    chk   ("D9 the slots above are killed", pd_wr_kill);

    // AND IT REDIRECTS, to the successor of the CORRECTED entry.
    chk   ("D10 a redirect is derived", pd_redir_val);
    chk   ("D11 naming this entry",     pd_redir_idx == 6'd8);
    chk_va("D12 to the corrected successor", pd_redir_pc, PD_TGT);

    // NO PREDICTOR UPDATE IS FORMED. FE-8, and it is STRUCTURAL:
    // this module has no update port at all. There is no runtime
    // check for it here, because a check of the form chk(name, 1'b1)
    // is a comment wearing an assertion -- it can never fail. What
    // enforces FE-8 is the instantiation above, which names every
    // port of ftq_ifu; adding an update output would leave it
    // unconnected and Verilator's PINMISSING would report it.

    // M1 WHERE THE FOUND BRANCH IS EARLIER THAN AN EXISTING SLOT.
    // Position 1 is before slot 0's position 3, so it takes slot 0
    // and slot 1 is killed: a taken branch at 1 puts everything
    // after it off the path.
    pdwb_entry = mk_entry(6'd8,
                   mk_slot(1'b1, TGT0, COND, 1'b1,
                           FTB_BR_POS_BITS'(3)),
                   mk_slot(1'b1, TGT1, COND, 1'b0,
                           FTB_BR_POS_BITS'(9)));
    ifu_ftq_pd[1]   = mk_pd(1'b1, 1'b1, 2'b10, 1'b1, 1'b0);
    ifu_ftq_mis_pos = FTQ_PD_POS_BITS'(1);
    settle();
    chk("D14 an earlier branch takes slot 0",
        pd_wr_sel == TRX_SLOT_BITS'(0));
    chk("D15 a JAL with is_call is a DIRECT_CALL",
        pd_wr_slot.br_type == DIRECT_CALL);
    chk("D16 the kill fires", pd_wr_kill);

    // M2. The predicted taken position holds NO CONTROL TRANSFER.
    // The slot becomes invalid and the block runs to its
    // fall-through.
    ifu_ftq_pd[1]   = mk_pd(1'b1, 1'b0, 2'b00, 1'b0, 1'b0);
    settle();
    chk   ("D17 a non-CFI position invalidates the slot",
           !pd_wr_slot.slot_valid);
    chk_va("D18 and fetch resumes at the fall-through",
           pd_redir_pc, BLK_PFT);

    // M4. The position was never fetched, so its predecode slot is
    // not valid. Same outcome.
    ifu_ftq_pd[1] = mk_pd(1'b0, 1'b0, 2'b01, 1'b0, 1'b0);
    settle();
    chk("D19 an unfetched position invalidates the slot",
        !pd_wr_slot.slot_valid);

    // A JALR carries no computed target (section 6), so the entry's
    // own target stands rather than ifu_ftq_target.
    ifu_ftq_pd[1] = mk_pd(1'b1, 1'b0, 2'b11, 1'b0, 1'b1);
    settle();
    chk   ("D20 a JALR with is_ret is a RETURN",
           pd_wr_slot.br_type == RETURN);
    chk_va("D21 and does not take the predecode target",
           pd_wr_slot.target, TGT0);

    ifu_ftq_pd[1] = mk_pd(1'b1, 1'b0, 2'b11, 1'b1, 1'b0);
    settle();
    chk("D22 a JALR with is_call is an INDIRECT_CALL",
        pd_wr_slot.br_type == INDIRECT_CALL);
    ifu_ftq_pd[1] = mk_pd(1'b1, 1'b0, 2'b11, 1'b0, 1'b0);
    settle();
    chk("D23 a plain JALR is INDIRECT_NONRET",
        pd_wr_slot.br_type == INDIRECT_NONRET);

    // A CONDITIONAL predecode found is not proved taken. Predecode
    // cannot know a direction, and TAGE and SC own it.
    ifu_ftq_pd[1] = mk_pd(1'b1, 1'b0, 2'b01, 1'b0, 1'b0);
    settle();
    chk("D24 a conditional is not marked taken by predecode",
        pd_wr_slot.slot_valid && !pd_wr_slot.taken &&
        (pd_wr_slot.br_type == COND));

    // NO mis_val: an accepted writeback with no structural
    // mispredict sets wb_rcvd and does nothing else. This is the
    // ordinary case -- most blocks predecode exactly as predicted.
    ifu_ftq_mis_val = 1'b0;
    settle();
    chk("D25 no mispredict, no correction",
        wb_accept && wb_set_val && !pd_wr_val && !pd_redir_val);
    clr_wb();
  endtask

  // -----------------------------------------------------------------
  // E. R3, and the bound the one-bit generation rests on.
  // -----------------------------------------------------------------
  task automatic group_e();
    $display("-- E: one redirect per entry, and the fault --");
    do_reset();

    gen_pdwb         = 1'b1;
    ifu_ftq_pdwb_gen = 1'b1;
    ifu_ftq_pdwb_idx = 6'd8;
    pdwb_entry       = mk_entry(6'd8,
                         mk_slot(1'b1, TGT0, COND, 1'b0,
                                 FTB_BR_POS_BITS'(3)),
                         mk_slot(1'b0, '0, NO_BRANCH, 1'b0, '0));
    ifu_ftq_pd[6]    = mk_pd(1'b1, 1'b0, 2'b10, 1'b0, 1'b0);
    ifu_ftq_mis_val  = 1'b1;
    ifu_ftq_mis_pos  = FTQ_PD_POS_BITS'(6);
    ifu_ftq_target   = PD_TGT;
    ifu_ftq_pdwb_val = 1'b1;

    // The first writeback for this entry: wb_rcvd is clear, so the
    // redirect is derived.
    wb_rcvd_pdwb = 1'b0;
    settle();
    chk("E1 the first writeback redirects", pd_redir_val);

    // A SECOND writeback naming an entry that already has the bit
    // set is a PROTOCOL VIOLATION, not a second redirect
    // (ftq_entry_formats.md 4.3 R3). Acting on it would resteer the
    // front end to a block it has already fetched past. The status
    // set is idempotent and is not gated.
    wb_rcvd_pdwb = 1'b1;
    settle();
    chk("E2 a second writeback derives no redirect", !pd_redir_val);
    chk("E3 and rewrites no field",                  !pd_wr_val);
    chk("E4 but the status set is still idempotent", wb_set_val);

    // THE FAULT. W3: fault SETS on ifu_ftq_fault_val naming this
    // index, and the writeback carries both so W2 and W3 can fire
    // together. The fault CODE is not carried at all -- the
    // architectural exception travels with the instruction stream
    // to the backend.
    wb_rcvd_pdwb      = 1'b0;
    ifu_ftq_fault_val = 1'b1;
    ifu_ftq_fault_pos = FTQ_PD_POS_BITS'(11);
    settle();
    chk("E5 the fault is reported",
        fault_set_val && (fault_set_idx == 6'd8));
    chk("E6 W2 and W3 fire together",
        wb_set_val && fault_set_val);

    // A fault on a STALE writeback is dropped with the rest of it.
    ifu_ftq_pdwb_gen = 1'b0;
    settle();
    chk("E7 a stale fault is dropped too", !fault_set_val);
    ifu_ftq_pdwb_gen = 1'b1;

    // A fault with NO mispredict still sets the bit and derives no
    // redirect: the block ended early, but nothing about the
    // prediction was disproved.
    ifu_ftq_mis_val = 1'b0;
    settle();
    chk("E8 a fault alone derives no redirect",
        fault_set_val && !pd_redir_val);
    clr_wb();

    // A FLUSH AND A WRITEBACK IN THE SAME CYCLE. Section 5 has the
    // IFU discard everything it holds for flushed entries, so the
    // only stale writeback that survives a redirect is one already
    // presented in the flush cycle -- and that one arrives
    // immediately. This is the BOUND that makes one generation bit
    // sufficient; the FTQ side is that the flush and the writeback
    // are independent outputs and neither suppresses the other.
    redir_val        = 1'b1;
    redir_idx        = 6'd3;
    redir_self       = 1'b0;
    redir_cause      = RC_MISPREDICT;
    ifu_ftq_pdwb_val = 1'b1;
    ifu_ftq_mis_val  = 1'b0;
    settle();
    chk("E9 the flush is presented", ftq_ifu_flush_val);
    chk("E10 and the writeback is still evaluated", wb_accept);
    redir_val = 1'b0;
    clr_wb();
  endtask

  // -----------------------------------------------------------------
  // Run
  // -----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    if (FTQ_PD_POS_BITS != FTB_BR_POS_BITS) begin
      $fatal(1, "tb_ftq_ifu: the position conversion is not the identity");
    end

    do_reset();
    group_a();
    group_b();
    group_c();
    group_d();
    group_e();

    $display("tb_ftq_ifu: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ftq_ifu: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #400000;
    $fatal(1, "tb_ftq_ifu: timeout");
  end

endmodule : tb
