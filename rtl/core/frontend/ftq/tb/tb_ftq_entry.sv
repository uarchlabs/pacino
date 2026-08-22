// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for ftq_entry (BP-107).
//
// Self-checking. Every case establishes its start state by reset
// plus a known driven sequence.
//
// WHAT THIS TESTBENCH MAY NOT ASSUME. ftq_entry does not clear its
// payload at reset -- only the 64 valid bits -- so nothing below
// reads a location before writing it, and every check that reads a
// field first writes that field. The one thing reset IS relied on
// is the valid bits, and A1 proves that rather than assuming it.
//
// The array is 64 x 224 bits and the write ports outnumber the read
// ports, so the cases are built around the SAME-INDEX ORDERING first
// and the storage second: a module that stored correctly and applied
// the four writes in the wrong order would pass a storage-only test
// and corrupt an entry on every p2/p3 collision.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  logic clk;
  logic rstn;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  logic                     alloc_wr_val;
  logic [FTQ_IDX_BITS-1:0]  alloc_wr_idx;
  logic [VA_WIDTH-1:0]      alloc_wr_pc;
  logic [VA_WIDTH-1:0]      alloc_wr_pft_addr;
  bp_ras_snapshot_t         alloc_wr_ras;
  logic [GHIST_PTR_BITS-1:0] alloc_wr_ghist_ptr;
  logic [PHIST_PTR_BITS-1:0] alloc_wr_phist_ptr;
  bp_ftq_slot_t             alloc_wr_slot [0:NUM_PRED_SLOTS-1];

  logic                     p2_wr_val;
  logic [FTQ_IDX_BITS-1:0]  p2_wr_idx;
  bp_ftq_slot_t             p2_wr_slot [0:NUM_PRED_SLOTS-1];
  logic                     p3_wr_val;
  logic [FTQ_IDX_BITS-1:0]  p3_wr_idx;
  bp_ftq_slot_t             p3_wr_slot [0:NUM_PRED_SLOTS-1];

  logic                     pd_wr_val;
  logic [FTQ_IDX_BITS-1:0]  pd_wr_idx;
  logic [TRX_SLOT_BITS-1:0] pd_wr_sel;
  bp_ftq_slot_t             pd_wr_slot;
  logic                     pd_wr_kill;

  logic [FTQ_IDX_BITS-1:0]  fetch_rd_idx;
  bp_ftq_entry_t            fetch_rd_entry;
  logic [FTQ_IDX_BITS-1:0]  redir_rd_idx;
  bp_ftq_entry_t            redir_rd_entry;
  bp_ras_snapshot_t         restore_snapshot;
  logic [FTQ_IDX_BITS-1:0]  pdwb_rd_idx;
  bp_ftq_entry_t            pdwb_rd_entry;
  logic [FTQ_IDX_BITS-1:0]  commit_rd_idx;
  bp_ftq_entry_t            commit_rd_entry;
  logic                     commit_step_val;
  logic                     ras_commit_val;
  bp_br_type_e              ras_commit_br_type;
  logic [VA_WIDTH-1:0]      ras_commit_ret_addr;
  bp_ras_snapshot_t         ras_commit_snapshot;
  logic [FTQ_IDX_BITS-1:0]  rsv_rd_idx [0:NUM_RESOLVE_PORTS-1];
  bp_ftq_entry_t            rsv_rd_entry [0:NUM_RESOLVE_PORTS-1];

  ftq_entry dut (
    .clk                 (clk),
    .rstn                (rstn),
    .alloc_wr_val        (alloc_wr_val),
    .alloc_wr_idx        (alloc_wr_idx),
    .alloc_wr_pc         (alloc_wr_pc),
    .alloc_wr_pft_addr   (alloc_wr_pft_addr),
    .alloc_wr_ras        (alloc_wr_ras),
    .alloc_wr_ghist_ptr  (alloc_wr_ghist_ptr),
    .alloc_wr_phist_ptr  (alloc_wr_phist_ptr),
    .alloc_wr_slot       (alloc_wr_slot),
    .p2_wr_val           (p2_wr_val),
    .p2_wr_idx           (p2_wr_idx),
    .p2_wr_slot          (p2_wr_slot),
    .p3_wr_val           (p3_wr_val),
    .p3_wr_idx           (p3_wr_idx),
    .p3_wr_slot          (p3_wr_slot),
    .pd_wr_val           (pd_wr_val),
    .pd_wr_idx           (pd_wr_idx),
    .pd_wr_sel           (pd_wr_sel),
    .pd_wr_slot          (pd_wr_slot),
    .pd_wr_kill          (pd_wr_kill),
    .fetch_rd_idx        (fetch_rd_idx),
    .fetch_rd_entry      (fetch_rd_entry),
    .redir_rd_idx        (redir_rd_idx),
    .redir_rd_entry      (redir_rd_entry),
    .restore_snapshot    (restore_snapshot),
    .pdwb_rd_idx         (pdwb_rd_idx),
    .pdwb_rd_entry       (pdwb_rd_entry),
    .commit_rd_idx       (commit_rd_idx),
    .commit_rd_entry     (commit_rd_entry),
    .commit_step_val     (commit_step_val),
    .ras_commit_val      (ras_commit_val),
    .ras_commit_br_type  (ras_commit_br_type),
    .ras_commit_ret_addr (ras_commit_ret_addr),
    .ras_commit_snapshot (ras_commit_snapshot),
    .rsv_rd_idx          (rsv_rd_idx),
    .rsv_rd_entry        (rsv_rd_entry)
  );

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

  task automatic clr();
    alloc_wr_val    = 1'b0;
    p2_wr_val       = 1'b0;
    p3_wr_val       = 1'b0;
    pd_wr_val       = 1'b0;
    pd_wr_kill      = 1'b0;
    commit_step_val = 1'b0;
  endtask

  // Build a slot. Every field is driven, so nothing below reads a
  // field this testbench never wrote.
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

  task automatic do_reset();
    rstn               = 1'b0;
    alloc_wr_idx       = '0;
    alloc_wr_pc        = '0;
    alloc_wr_pft_addr  = '0;
    alloc_wr_ras       = '0;
    alloc_wr_ghist_ptr = '0;
    alloc_wr_phist_ptr = '0;
    p2_wr_idx          = '0;
    p3_wr_idx          = '0;
    pd_wr_idx          = '0;
    pd_wr_sel          = '0;
    pd_wr_slot         = '0;
    fetch_rd_idx       = '0;
    redir_rd_idx       = '0;
    pdwb_rd_idx        = '0;
    commit_rd_idx      = '0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      alloc_wr_slot[s] = '0;
      p2_wr_slot[s]    = '0;
      p3_wr_slot[s]    = '0;
    end
    for (int p = 0; p < NUM_RESOLVE_PORTS; p++) rsv_rd_idx[p] = '0;
    clr();
    repeat (4) tick();
    rstn = 1'b1;
    repeat (2) tick();
  endtask

  // Allocate entry idx with a distinguishable payload. pc and
  // pft_addr are derived from the index so a read of the wrong
  // entry is visible as a value, not just as an inequality.
  task automatic alloc(input int idx);
    alloc_wr_val       = 1'b1;
    alloc_wr_idx       = FTQ_IDX_BITS'(idx);
    alloc_wr_pc        = VA_WIDTH'(40'h00_8000_0000 + idx * 32);
    alloc_wr_pft_addr  = VA_WIDTH'(40'h00_8000_0020 + idx * 32);
    alloc_wr_ras.tosr  = RAS_PTR_BITS'(idx);
    alloc_wr_ras.tosw  = RAS_PTR_BITS'(idx + 1);
    alloc_wr_ras.bos   = RAS_PTR_BITS'(idx + 2);
    alloc_wr_ghist_ptr = GHIST_PTR_BITS'(idx);
    alloc_wr_phist_ptr = PHIST_PTR_BITS'(idx);
    alloc_wr_slot[0]   = mk_slot(1'b1,
                           VA_WIDTH'(40'h00_9000_0000 + idx * 64),
                           COND, 1'b0, FTB_BR_POS_BITS'(2));
    alloc_wr_slot[1]   = mk_slot(1'b0, '0, NO_BRANCH, 1'b0, '0);
    tick();
    alloc_wr_val = 1'b0;
  endtask

  // -----------------------------------------------------------------
  // A. Reset, and the p1 allocation write.
  // -----------------------------------------------------------------
  // ACCEPTANCE, Problem 2: a p1 write lands in the entry the p0
  // index allocated.
  task automatic group_a();
    $display("-- A: reset and the p1 allocation write --");
    do_reset();

    // Reset clears the valid bits and nothing else. Checked, not
    // assumed: every later case relies on an unwritten entry
    // reading invalid.
    fetch_rd_idx = 6'd7;
    #1;
    chk("A1 an unwritten entry is invalid", !fetch_rd_entry.valid);

    alloc(7);
    fetch_rd_idx = 6'd7;
    #1;
    chk   ("A2 the allocated entry is valid", fetch_rd_entry.valid);
    chk_va("A3 pc landed",       fetch_rd_entry.pc,
           VA_WIDTH'(40'h00_8000_0000 + 7 * 32));
    chk_va("A4 pft_addr landed", fetch_rd_entry.pft_addr,
           VA_WIDTH'(40'h00_8000_0020 + 7 * 32));
    chk   ("A5 branch_id is the index",
           fetch_rd_entry.branch_id == 6'd7);
    chk   ("A6 ghist checkpoint landed",
           fetch_rd_entry.ghist_ptr == GHIST_PTR_BITS'(7));
    chk   ("A7 phist checkpoint landed",
           fetch_rd_entry.phist_ptr == PHIST_PTR_BITS'(7));
    chk   ("A8 RAS snapshot landed",
           fetch_rd_entry.ras.tosr == RAS_PTR_BITS'(7) &&
           fetch_rd_entry.ras.tosw == RAS_PTR_BITS'(8) &&
           fetch_rd_entry.ras.bos  == RAS_PTR_BITS'(9));
    chk_va("A9 slot 0 target landed", fetch_rd_entry.slot[0].target,
           VA_WIDTH'(40'h00_9000_0000 + 7 * 64));
    chk   ("A10 slot 1 is invalid",
           !fetch_rd_entry.slot[1].slot_valid);

    // AND NO OTHER ENTRY WAS TOUCHED. A write that landed in every
    // location, or in a location the index did not name, passes
    // every check above.
    fetch_rd_idx = 6'd6;
    #1;
    chk("A11 the entry below is untouched", !fetch_rd_entry.valid);
    fetch_rd_idx = 6'd8;
    #1;
    chk("A12 the entry above is untouched", !fetch_rd_entry.valid);
  endtask

  // -----------------------------------------------------------------
  // B. The four read ports are independent views of one array.
  // -----------------------------------------------------------------
  task automatic group_b();
    $display("-- B: read port independence --");
    do_reset();

    for (int i = 0; i < 6; i++) alloc(i);

    fetch_rd_idx  = 6'd1;
    redir_rd_idx  = 6'd2;
    pdwb_rd_idx   = 6'd3;
    commit_rd_idx = 6'd4;
    rsv_rd_idx[0] = 6'd5;
    rsv_rd_idx[1] = 6'd0;
    #1;
    chk_va("B1 fetch port",   fetch_rd_entry.pc,
           VA_WIDTH'(40'h00_8000_0000 + 1 * 32));
    chk_va("B2 redirect port", redir_rd_entry.pc,
           VA_WIDTH'(40'h00_8000_0000 + 2 * 32));
    chk_va("B3 writeback port", pdwb_rd_entry.pc,
           VA_WIDTH'(40'h00_8000_0000 + 3 * 32));
    chk_va("B4 commit port",  commit_rd_entry.pc,
           VA_WIDTH'(40'h00_8000_0000 + 4 * 32));
    chk_va("B5 resolve port 0", rsv_rd_entry[0].pc,
           VA_WIDTH'(40'h00_8000_0000 + 5 * 32));
    chk_va("B6 resolve port 1", rsv_rd_entry[1].pc,
           VA_WIDTH'(40'h00_8000_0000 + 0 * 32));

    // The restore snapshot is the redirect port's entry, which is
    // what D2 of backend_interfaces 5 requires.
    chk("B7 restore snapshot is the redirect entry's",
        restore_snapshot.tosr == RAS_PTR_BITS'(2));

    // TWO RESOLUTION PORTS NAMING ONE ENTRY agree. Both branches of
    // one block resolving together is ordinary traffic.
    rsv_rd_idx[0] = 6'd3;
    rsv_rd_idx[1] = 6'd3;
    #1;
    chk("B8 two resolve ports on one entry agree",
        rsv_rd_entry[0].pc === rsv_rd_entry[1].pc);
  endtask

  // -----------------------------------------------------------------
  // C. Slot correction, and the same-index ordering.
  // -----------------------------------------------------------------
  task automatic group_c();
    $display("-- C: slot correction and write ordering --");
    do_reset();

    alloc(11);

    // A p2 correction rewrites the slot array and LEAVES THE BLOCK
    // SCALARS ALONE. FE-13: the group is not gated on a redirect, so
    // it fires on every prediction and must not disturb the pc, the
    // checkpoint or the RAS snapshot.
    p2_wr_val     = 1'b1;
    p2_wr_idx     = 6'd11;
    p2_wr_slot[0] = mk_slot(1'b1, VA_WIDTH'(40'h00_A000_0000),
                            COND, 1'b1, FTB_BR_POS_BITS'(4));
    p2_wr_slot[1] = mk_slot(1'b1, VA_WIDTH'(40'h00_A000_1000),
                            DIRECT_UNC, 1'b0, FTB_BR_POS_BITS'(9));
    tick();
    p2_wr_val = 1'b0;

    fetch_rd_idx = 6'd11;
    #1;
    chk_va("C1 p2 rewrote slot 0", fetch_rd_entry.slot[0].target,
           VA_WIDTH'(40'h00_A000_0000));
    chk   ("C2 p2 rewrote slot 0 pos",
           fetch_rd_entry.slot[0].pos == FTB_BR_POS_BITS'(4));
    chk   ("C3 p2 made slot 1 valid",
           fetch_rd_entry.slot[1].slot_valid);
    chk_va("C4 block pc untouched by p2", fetch_rd_entry.pc,
           VA_WIDTH'(40'h00_8000_0000 + 11 * 32));
    chk   ("C5 checkpoint untouched by p2",
           fetch_rd_entry.ghist_ptr == GHIST_PTR_BITS'(11));

    // p3 SUPERSEDES p2 FOR THE SAME INDEX IN THE SAME CYCLE. FE-3:
    // the later stage wins, and the FTQ does not compare targets to
    // settle it.
    p2_wr_val     = 1'b1;
    p2_wr_idx     = 6'd11;
    p2_wr_slot[0] = mk_slot(1'b1, VA_WIDTH'(40'h00_B000_0000),
                            COND, 1'b1, FTB_BR_POS_BITS'(4));
    p3_wr_val     = 1'b1;
    p3_wr_idx     = 6'd11;
    p3_wr_slot[0] = mk_slot(1'b1, VA_WIDTH'(40'h00_C000_0000),
                            COND, 1'b0, FTB_BR_POS_BITS'(4));
    p3_wr_slot[1] = mk_slot(1'b0, '0, NO_BRANCH, 1'b0, '0);
    tick();
    clr();
    #1;
    chk_va("C6 p3 supersedes p2 on one index",
           fetch_rd_entry.slot[0].target, VA_WIDTH'(40'h00_C000_0000));
    chk   ("C7 p3 direction stands",
           !fetch_rd_entry.slot[0].taken);

    // TWO INDICES IN ONE CYCLE. p2 and p3 name DIFFERENT entries in
    // a moving stream -- p3 lags p2 by one block -- so both writes
    // must land, each in its own entry.
    alloc(12);
    p2_wr_val     = 1'b1;
    p2_wr_idx     = 6'd12;
    p2_wr_slot[0] = mk_slot(1'b1, VA_WIDTH'(40'h00_D000_0000),
                            COND, 1'b1, FTB_BR_POS_BITS'(1));
    p2_wr_slot[1] = mk_slot(1'b0, '0, NO_BRANCH, 1'b0, '0);
    p3_wr_val     = 1'b1;
    p3_wr_idx     = 6'd11;
    p3_wr_slot[0] = mk_slot(1'b1, VA_WIDTH'(40'h00_E000_0000),
                            COND, 1'b1, FTB_BR_POS_BITS'(4));
    tick();
    clr();
    fetch_rd_idx = 6'd12;
    #1;
    chk_va("C8 p2 landed in its own entry",
           fetch_rd_entry.slot[0].target, VA_WIDTH'(40'h00_D000_0000));
    fetch_rd_idx = 6'd11;
    #1;
    chk_va("C9 p3 landed in its own entry",
           fetch_rd_entry.slot[0].target, VA_WIDTH'(40'h00_E000_0000));
  endtask

  // -----------------------------------------------------------------
  // D. The predecode correction and the kill.
  // -----------------------------------------------------------------
  task automatic group_d();
    $display("-- D: predecode correction --");
    do_reset();

    alloc(20);
    // Two valid slots to start, so the kill has something to clear.
    p2_wr_val     = 1'b1;
    p2_wr_idx     = 6'd20;
    p2_wr_slot[0] = mk_slot(1'b1, VA_WIDTH'(40'h00_9100_0000),
                            COND, 1'b0, FTB_BR_POS_BITS'(3));
    p2_wr_slot[1] = mk_slot(1'b1, VA_WIDTH'(40'h00_9200_0000),
                            COND, 1'b1, FTB_BR_POS_BITS'(11));
    tick();
    p2_wr_val = 1'b0;
    fetch_rd_idx = 6'd20;
    #1;
    chk("D1 both slots valid before the correction",
        fetch_rd_entry.slot[0].slot_valid &&
        fetch_rd_entry.slot[1].slot_valid);

    // Predecode found an unconditional at position 5, which is
    // after slot 0 and before slot 1. It goes in slot 1 and there
    // is nothing above it to kill -- but the kill still fires and
    // must not disturb slot 0.
    pd_wr_val  = 1'b1;
    pd_wr_idx  = 6'd20;
    pd_wr_sel  = TRX_SLOT_BITS'(1);
    pd_wr_slot = mk_slot(1'b1, VA_WIDTH'(40'h00_9300_0000),
                         DIRECT_UNC, 1'b1, FTB_BR_POS_BITS'(5));
    pd_wr_kill = 1'b1;
    tick();
    clr();
    #1;
    chk_va("D2 the named slot was rewritten",
           fetch_rd_entry.slot[1].target, VA_WIDTH'(40'h00_9300_0000));
    chk   ("D3 the named slot took the predecode type",
           fetch_rd_entry.slot[1].br_type == DIRECT_UNC);
    chk_va("D4 the slot below is untouched",
           fetch_rd_entry.slot[0].target, VA_WIDTH'(40'h00_9100_0000));

    // Now the kill has work: correct slot 0 and slot 1 must go.
    pd_wr_val  = 1'b1;
    pd_wr_idx  = 6'd20;
    pd_wr_sel  = TRX_SLOT_BITS'(0);
    pd_wr_slot = mk_slot(1'b1, VA_WIDTH'(40'h00_9400_0000),
                         DIRECT_CALL, 1'b1, FTB_BR_POS_BITS'(1));
    pd_wr_kill = 1'b1;
    tick();
    clr();
    #1;
    chk_va("D5 slot 0 rewritten", fetch_rd_entry.slot[0].target,
           VA_WIDTH'(40'h00_9400_0000));
    chk   ("D6 slot 1 killed",
           !fetch_rd_entry.slot[1].slot_valid);
    chk   ("D7 slot 1 not taken after the kill",
           !fetch_rd_entry.slot[1].taken);
    chk_va("D8 the block pc survives the correction",
           fetch_rd_entry.pc,
           VA_WIDTH'(40'h00_8000_0000 + 20 * 32));
  endtask

  // -----------------------------------------------------------------
  // E. The RAS commit payload.
  // -----------------------------------------------------------------
  task automatic group_e();
    $display("-- E: the RAS commit payload --");
    do_reset();

    // An entry with no call and no return. FE-11 allows at most one
    // RAS operation per entry; this one has none, so the step frees
    // the entry and issues no commit.
    alloc(30);
    commit_rd_idx   = 6'd30;
    commit_step_val = 1'b1;
    #1;
    chk("E1 no RAS commit for a conditional block", !ras_commit_val);

    // A block ending in a taken call.
    p2_wr_val     = 1'b1;
    p2_wr_idx     = 6'd30;
    p2_wr_slot[0] = mk_slot(1'b1, VA_WIDTH'(40'h00_9500_0000),
                            DIRECT_CALL, 1'b1, FTB_BR_POS_BITS'(6));
    p2_wr_slot[1] = mk_slot(1'b0, '0, NO_BRANCH, 1'b0, '0);
    tick();
    p2_wr_val = 1'b0;
    commit_step_val = 1'b1;
    #1;
    chk   ("E2 a taken call commits the RAS", ras_commit_val);
    chk   ("E3 the type is the call",
           ras_commit_br_type == DIRECT_CALL);
    chk   ("E4 the snapshot is the entry's",
           ras_commit_snapshot.tosr == RAS_PTR_BITS'(30) &&
           ras_commit_snapshot.bos  == RAS_PTR_BITS'(32));
    chk_va("E5 the return address is the block fall-through",
           ras_commit_ret_addr,
           VA_WIDTH'(40'h00_8000_0020 + 30 * 32));

    // NO STEP, NO COMMIT. commit_step_val carries the suppression of
    // 5.4: ras_decisions.md 4.5 orders BOS restore > commit > hold,
    // so a redirect restore takes the cycle and ftq_commit holds the
    // step low. The payload must go with it.
    commit_step_val = 1'b0;
    #1;
    chk("E6 no commit without a step", !ras_commit_val);

    // A taken RETURN commits too.
    p2_wr_val     = 1'b1;
    p2_wr_idx     = 6'd30;
    p2_wr_slot[0] = mk_slot(1'b1, VA_WIDTH'(40'h00_9600_0000),
                            RETURN, 1'b1, FTB_BR_POS_BITS'(8));
    tick();
    p2_wr_val = 1'b0;
    commit_step_val = 1'b1;
    #1;
    chk("E7 a taken return commits the RAS",
        ras_commit_val && (ras_commit_br_type == RETURN));

    // A call that is NOT TAKEN is not on the path and pushes
    // nothing. FE-11's argument is that a RAS operation IS a taken
    // branch.
    p2_wr_val     = 1'b1;
    p2_wr_idx     = 6'd30;
    p2_wr_slot[0] = mk_slot(1'b1, VA_WIDTH'(40'h00_9700_0000),
                            DIRECT_CALL, 1'b0, FTB_BR_POS_BITS'(8));
    tick();
    p2_wr_val = 1'b0;
    commit_step_val = 1'b1;
    #1;
    chk("E8 a not-taken call does not commit", !ras_commit_val);
    clr();
  endtask

  // -----------------------------------------------------------------
  // F. Wrap. The index space is 64 and nothing above assumed it.
  // -----------------------------------------------------------------
  task automatic group_f();
    $display("-- F: the whole index space --");
    do_reset();

    for (int i = 0; i < FTQ_DEPTH; i++) alloc(i);

    // Every entry holds its own payload. An array that aliased two
    // indices, or a write that ignored the top bit of the index,
    // fails here and nowhere else in this file.
    begin
      int bad;
      bad = 0;
      for (int i = 0; i < FTQ_DEPTH; i++) begin
        fetch_rd_idx = FTQ_IDX_BITS'(i);
        #1;
        if (fetch_rd_entry.pc !==
              VA_WIDTH'(40'h00_8000_0000 + i * 32)) bad++;
        if (fetch_rd_entry.branch_id !== FTQ_IDX_BITS'(i)) bad++;
      end
      chk("F1 all 64 entries hold their own payload", bad == 0);
    end

    // Rewriting index 0 does not disturb index 63, which is the
    // adjacency an off-by-one in the write decode produces.
    alloc_wr_val      = 1'b1;
    alloc_wr_idx      = 6'd0;
    alloc_wr_pc       = VA_WIDTH'(40'h00_FFFF_0000);
    alloc_wr_pft_addr = VA_WIDTH'(40'h00_FFFF_0020);
    tick();
    alloc_wr_val = 1'b0;
    fetch_rd_idx = 6'd63;
    #1;
    chk_va("F2 entry 63 survives a write to entry 0",
           fetch_rd_entry.pc,
           VA_WIDTH'(40'h00_8000_0000 + 63 * 32));
    fetch_rd_idx = 6'd0;
    #1;
    chk_va("F3 entry 0 took the new payload", fetch_rd_entry.pc,
           VA_WIDTH'(40'h00_FFFF_0000));
  endtask

  // -----------------------------------------------------------------
  // Run
  // -----------------------------------------------------------------
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    if (FTQ_DEPTH != 64 || NUM_PRED_SLOTS != 2) begin
      $fatal(1, "tb_ftq_entry: written for FTQ_DEPTH 64, slots 2");
    end

    do_reset();
    group_a();
    group_b();
    group_c();
    group_d();
    group_e();
    group_f();

    $display("tb_ftq_entry: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ftq_entry: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  // Time based, not cycle based: a cycle-based watchdog waits on the
  // very clock a hang can stop (BP-097, TD#111).
  initial begin
    #400000;
    $fatal(1, "tb_ftq_entry: timeout");
  end

endmodule : tb
