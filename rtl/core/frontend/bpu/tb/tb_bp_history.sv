// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_bp_history.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------
// Testbench for bp_history (BP-069 module-owned pointer interface,
// BP-071 / BP-072 increment-oriented fold geometry). Self-checking.
// Module name: tb (Verilator convention for testbenches).
// Clock period: 10 ns.
//
// BP-073 adds external-anchor tests (TC14-TC16): three DUT folds are
// tied to hand-derived literal constants and to xs_fold_ref, a from-
// the-spec Xiangshan FoldedHistory reference that is independent of the
// DUT GEOMETRY (age-indexed history; no ghr_buf, no DUT anchor, no
// fold_step/fold_ghr, not the BP-072 fold_ref). See xs_fold_ref below
// for the source-of-truth / documentation-gap note.
//
// Golden model (the single, DUT-independent reference, TD #74):
//   fold_ref(mem, anchor, H, W) folds H GHR bits, walked DOWNWARD
//   from anchor (offset i -> bit mem[anchor - i]), into W bits with
//   the BP-071 position mapping posmap(i) = (i + W - 1) % W (newest
//   at the high end). This mirrors the geometry definition only; it
//   does NOT call, bind to, or copy the DUT fold_step / fold_ghr.
//
//   The module-owned pointer increments and the newest history bit
//   sits one position behind the live pointer, so the fold anchor for
//   the CURRENT folded output is always (ghist_ptr - 1). One reference
//   is checked against BOTH DUT paths:
//     - incremental update: folded == fold_ref(ghr_buf, ghist_ptr-1)
//     - rollback recompute: folded == fold_ref(ghr_buf, ghist_ptr-1)
//   after the pointer is restored. incremental == fold_ref AND
//   recompute == fold_ref together prove incremental == recompute.
// ===================================================================
module tb;
  import bp_defines_pkg::*;
  import bp_structs_pkg::*;

  // ----------------------------------------------------------------
  // Clock and reset
  // ----------------------------------------------------------------
  logic clk;
  logic rstn;

  initial clk = 0;
  // verilator lint_off BLKSEQ
  always #5 clk = ~clk;
  // verilator lint_on BLKSEQ

  // ----------------------------------------------------------------
  // DUT signals (BP-069 interface: pointer is a module OUTPUT, the
  // testbench drives NO pointer; rollback supplies an index)
  // ----------------------------------------------------------------
  logic [1:0]                  pred_taken;
  logic [VA_WIDTH-1:0]         pred_pc [2];
  logic [1:0]                  num_branches;
  logic                        ckpt_wr_en;
  logic [FTQ_IDX_BITS-1:0]    ckpt_wr_idx;
  logic                        rollback_valid;
  logic [FTQ_IDX_BITS-1:0]    rollback_ckpt_idx;
  logic [GHIST_PTR_BITS-1:0]  ghist_ptr;
  logic [PHIST_PTR_BITS-1:0]  phist_ptr;
  logic [GHIST_PTR_BITS-1:0]  ckpt_ghist_ptr;
  logic [PHIST_PTR_BITS-1:0]  ckpt_phist_ptr;
  logic [GHR_WIDTH-1:0]        ghr_buf;
  logic [PHR_WIDTH-1:0]        phr_buf;
  bp_folded_hist_t             folded;

  // ----------------------------------------------------------------
  // DUT instantiation
  // ----------------------------------------------------------------
  bp_history dut (
    .clk               (clk),
    .rstn              (rstn),
    .pred_taken        (pred_taken),
    .pred_pc           (pred_pc),
    .num_branches      (num_branches),
    .ckpt_wr_en        (ckpt_wr_en),
    .ckpt_wr_idx       (ckpt_wr_idx),
    .rollback_valid    (rollback_valid),
    .rollback_ckpt_idx (rollback_ckpt_idx),
    .ghist_ptr         (ghist_ptr),
    .phist_ptr         (phist_ptr),
    .ckpt_ghist_ptr    (ckpt_ghist_ptr),
    .ckpt_phist_ptr    (ckpt_phist_ptr),
    .ghr_buf           (ghr_buf),
    .phr_buf           (phr_buf),
    .folded            (folded)
  );

  // ----------------------------------------------------------------
  // Counters
  // ----------------------------------------------------------------
  int pass_count;    // directed test cases passed
  int fold_checks;   // individual golden fold comparisons passed
  int anchor_checks; // BP-073 external-reference anchor comparisons

  // ----------------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------------
  task drive_idle;
    pred_taken        = 2'b00;
    pred_pc[0]        = '0;
    pred_pc[1]        = '0;
    num_branches      = 2'd0;
    ckpt_wr_en        = 1'b0;
    ckpt_wr_idx       = '0;
    rollback_valid    = 1'b0;
    rollback_ckpt_idx = '0;
  endtask

  task tick;
    @(posedge clk);
    #1;
  endtask

  task do_reset;
    drive_idle();
    rstn = 1'b0;
    repeat(2) tick();
    rstn = 1'b1;
    tick();
  endtask

  // ----------------------------------------------------------------
  // Single independent golden fold (BP-071 geometry, increment-
  // oriented downward walk). NOT bound to any DUT internal.
  // ----------------------------------------------------------------
  function automatic logic [63:0] fold_ref(
    input logic [GHR_WIDTH-1:0] mem,
    input int                   anchor,
    input int                   H,
    input int                   W
  );
    logic [63:0] acc;
    int          i, bit_idx, pos;
    acc = 64'b0;
    for (i = 0; i < H; i++) begin
      bit_idx = (anchor - i + GHR_WIDTH) % GHR_WIDTH;
      pos     = (i + W - 1) % W;
      if (mem[bit_idx]) acc[pos] = acc[pos] ^ 1'b1;
    end
    return acc;
  endfunction

  // ----------------------------------------------------------------
  // BP-073 EXTERNAL reference (table-side / Xiangshan anchor).
  //
  // Independence from the DUT GEOMETRY (BP-073 requirement, beyond
  // BP-072's independence from DUT INTERNALS):
  //   - xs_fold_ref takes an AGE-INDEXED known history (khist[i] = the
  //     history bit at age i, age 0 = newest) -- NOT the GHR circular
  //     buffer and NOT a DUT anchor. It never reads ghr_buf, never
  //     reconstructs the (anchor - i) circular index, never calls
  //     fold_step / fold_ghr, and is NOT the BP-072 fold_ref above.
  //   - It folds H age-ordered bits into W bits by the Xiangshan
  //     FoldedHistory definition: the newest bit folds into the W-wide
  //     register and the bit leaving the H-deep window is removed at
  //     (H-1) % W. For a fully-known H-bit window this reduces to
  //     position(i) = (i + W - 1) % W (newest at the high end).
  //
  // Source-of-truth note (flagged documentation gap):
  //   tage_table_hash_rules.md and ittage_table_hash_rules.md define
  //   only how the fold is CONSUMED -- tmpA = (PC >> INST_OFFSET) ^ fh
  //   (index) and tmpB = (PC >> THIS_INDEX_BITS) ^ fh1 ^ (fh2 << 1)
  //   (tag). Neither doc defines how fh / fh1 / fh2 are COMPUTED from
  //   the global history. They therefore do NOT supply a table-side
  //   fold definition independent of bp_history. Per BP-073 Binding
  //   Decision 3, the external reference falls back to the Xiangshan
  //   FoldedHistory definition (newest folded in, leaving bit at
  //   (H-1) % W). The three committed literal anchors below are the
  //   real external tie: hand-derived fixed constants that a future
  //   shared-geometry drift cannot co-move with.
  // ----------------------------------------------------------------
  function automatic logic [63:0] xs_fold_ref(
    input logic [GHR_WIDTH-1:0] khist, // khist[i] = history bit at age i
    input int                   H,
    input int                   W
  );
    logic [63:0] acc;
    int          i, pos;
    acc = 64'b0;
    for (i = 0; i < H; i++) begin
      pos = (i + W - 1) % W;
      if (khist[i]) acc[pos] = acc[pos] ^ 1'b1;
    end
    return acc;
  endfunction

  // Check one DUT fold field against BOTH the external Xiangshan
  // reference (over the age-indexed known history) AND the committed
  // hand-derived literal. $fatal on any mismatch (self-checking).
  // A DUT-vs-literal mismatch is the BP-073 requirement-4 finding.
  task automatic chk_anchor(
    input logic [63:0]          dv,
    input logic [GHR_WIDTH-1:0] khist,
    input int                   H,
    input int                   W,
    input logic [63:0]          lit,
    input string                nm
  );
    logic [63:0] ref_val, got, m;
    m       = (64'b1 << W) - 64'b1;
    ref_val = xs_fold_ref(khist, H, W) & m;
    got     = dv & m;
    anchor_checks++;
    // the external reference must reproduce the hand-derived literal
    if (ref_val !== (lit & m))
      $fatal(1,
        "%s FAIL: xs_fold_ref %h != literal %h (H=%0d W=%0d)",
        nm, ref_val, lit & m, H, W);
    // DUT folded must equal the committed literal (req 3) ...
    if (got !== (lit & m))
      $fatal(1,
        "%s FAIL: DUT fold %h != external literal %h (H=%0d W=%0d)",
        nm, got, lit & m, H, W);
    // ... and the external reference (req 3)
    if (got !== ref_val)
      $fatal(1,
        "%s FAIL: DUT fold %h != xs_fold_ref %h (H=%0d W=%0d)",
        nm, got, ref_val, H, W);
  endtask

  // Compare one DUT fold field against the golden at the current
  // anchor (ghist_ptr - 1). $fatal on mismatch (self-checking).
  task automatic chk(
    input logic [63:0] dv,
    input int          H,
    input int          W,
    input string       nm
  );
    logic [63:0] exp, got, m;
    int          anchor;
    anchor = (int'(ghist_ptr) - 1 + GHR_WIDTH) % GHR_WIDTH;
    m      = (64'b1 << W) - 64'b1;
    exp    = fold_ref(ghr_buf, anchor, H, W) & m;
    got    = dv & m;
    fold_checks++;
    if (got !== exp)
      $fatal(1,
        "%s FAIL: fold got %h exp %h (anchor=%0d H=%0d W=%0d)",
        nm, got, exp, anchor, H, W);
  endtask

  // Check every tagged-table fold against the one golden reference.
  task automatic check_all_folds(input string ctx);
    // TAGE T1-T4 (idx, tag_fh1, tag_fh2)
    chk(64'(folded.tage_t1_idx_fh),  TAGE_TBL_HIST[1], TAGE_TBL_FH[1],
        {ctx, ".tage_t1_idx"});
    chk(64'(folded.tage_t1_tag_fh1), TAGE_TBL_HIST[1], TAGE_TBL_FH1[1],
        {ctx, ".tage_t1_fh1"});
    chk(64'(folded.tage_t1_tag_fh2), TAGE_TBL_HIST[1], TAGE_TBL_FH2[1],
        {ctx, ".tage_t1_fh2"});
    chk(64'(folded.tage_t2_idx_fh),  TAGE_TBL_HIST[2], TAGE_TBL_FH[2],
        {ctx, ".tage_t2_idx"});
    chk(64'(folded.tage_t2_tag_fh1), TAGE_TBL_HIST[2], TAGE_TBL_FH1[2],
        {ctx, ".tage_t2_fh1"});
    chk(64'(folded.tage_t2_tag_fh2), TAGE_TBL_HIST[2], TAGE_TBL_FH2[2],
        {ctx, ".tage_t2_fh2"});
    chk(64'(folded.tage_t3_idx_fh),  TAGE_TBL_HIST[3], TAGE_TBL_FH[3],
        {ctx, ".tage_t3_idx"});
    chk(64'(folded.tage_t3_tag_fh1), TAGE_TBL_HIST[3], TAGE_TBL_FH1[3],
        {ctx, ".tage_t3_fh1"});
    chk(64'(folded.tage_t3_tag_fh2), TAGE_TBL_HIST[3], TAGE_TBL_FH2[3],
        {ctx, ".tage_t3_fh2"});
    chk(64'(folded.tage_t4_idx_fh),  TAGE_TBL_HIST[4], TAGE_TBL_FH[4],
        {ctx, ".tage_t4_idx"});
    chk(64'(folded.tage_t4_tag_fh1), TAGE_TBL_HIST[4], TAGE_TBL_FH1[4],
        {ctx, ".tage_t4_fh1"});
    chk(64'(folded.tage_t4_tag_fh2), TAGE_TBL_HIST[4], TAGE_TBL_FH2[4],
        {ctx, ".tage_t4_fh2"});
    // ITTAGE IT1-IT4 (idx, tag_fh1, tag_fh2)
    chk(64'(folded.it_t1_idx_fh),  IT_TBL_HIST[1], IT_TBL_FH[1],
        {ctx, ".it_t1_idx"});
    chk(64'(folded.it_t1_tag_fh1), IT_TBL_HIST[1], IT_TBL_FH1[1],
        {ctx, ".it_t1_fh1"});
    chk(64'(folded.it_t1_tag_fh2), IT_TBL_HIST[1], IT_TBL_FH2[1],
        {ctx, ".it_t1_fh2"});
    chk(64'(folded.it_t2_idx_fh),  IT_TBL_HIST[2], IT_TBL_FH[2],
        {ctx, ".it_t2_idx"});
    chk(64'(folded.it_t2_tag_fh1), IT_TBL_HIST[2], IT_TBL_FH1[2],
        {ctx, ".it_t2_fh1"});
    chk(64'(folded.it_t2_tag_fh2), IT_TBL_HIST[2], IT_TBL_FH2[2],
        {ctx, ".it_t2_fh2"});
    chk(64'(folded.it_t3_idx_fh),  IT_TBL_HIST[3], IT_TBL_FH[3],
        {ctx, ".it_t3_idx"});
    chk(64'(folded.it_t3_tag_fh1), IT_TBL_HIST[3], IT_TBL_FH1[3],
        {ctx, ".it_t3_fh1"});
    chk(64'(folded.it_t3_tag_fh2), IT_TBL_HIST[3], IT_TBL_FH2[3],
        {ctx, ".it_t3_fh2"});
    chk(64'(folded.it_t4_idx_fh),  IT_TBL_HIST[4], IT_TBL_FH[4],
        {ctx, ".it_t4_idx"});
    chk(64'(folded.it_t4_tag_fh1), IT_TBL_HIST[4], IT_TBL_FH1[4],
        {ctx, ".it_t4_fh1"});
    chk(64'(folded.it_t4_tag_fh2), IT_TBL_HIST[4], IT_TBL_FH2[4],
        {ctx, ".it_t4_fh2"});
    // SC ST1-ST3 (idx only, H = W)
    chk(64'(folded.sc_t1_idx_fh), SC_TBL_HIST[1], SC_TBL_HIST[1],
        {ctx, ".sc_t1_idx"});
    chk(64'(folded.sc_t2_idx_fh), SC_TBL_HIST[2], SC_TBL_HIST[2],
        {ctx, ".sc_t2_idx"});
    chk(64'(folded.sc_t3_idx_fh), SC_TBL_HIST[3], SC_TBL_HIST[3],
        {ctx, ".sc_t3_idx"});
  endtask

  // Drive one prediction bundle (no checkpoint, no rollback).
  task automatic upd(
    input int                  nb,
    input logic                s0,
    input logic                s1,
    input logic [VA_WIDTH-1:0] pc0,
    input logic [VA_WIDTH-1:0] pc1
  );
    pred_taken   = {s1, s0};
    pred_pc[0]   = pc0;
    pred_pc[1]   = pc1;
    num_branches = nb[1:0];
    tick();
    drive_idle();
  endtask

  // Simple 32-bit LFSR for directed-random stimulus (deterministic).
  logic [31:0] lfsr;
  function automatic logic nextbit;
    logic b;
    b    = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];
    lfsr = {lfsr[30:0], b};
    return b;
  endfunction

  // ----------------------------------------------------------------
  // Test body
  // ----------------------------------------------------------------
  initial begin
    pass_count    = 0;
    fold_checks   = 0;
    anchor_checks = 0;
    lfsr          = 32'hACE1_2345;
    drive_idle();
    rstn = 1'b0;

    // ---- TC1: Reset -- all outputs zero -------------------------
    repeat(3) tick();
    rstn = 1'b1;
    tick();
    if (ghr_buf !== {GHR_WIDTH{1'b0}})
      $fatal(1, "TC1 FAIL: ghr_buf non-zero after reset");
    if (phr_buf !== {PHR_WIDTH{1'b0}})
      $fatal(1, "TC1 FAIL: phr_buf non-zero after reset");
    if (folded !== '0)
      $fatal(1, "TC1 FAIL: folded non-zero after reset");
    if (ghist_ptr !== '0 || phist_ptr !== '0)
      $fatal(1, "TC1 FAIL: pointer non-zero after reset");
    check_all_folds("TC1");
    pass_count++;
    $display("TC1 pass (reset)");

    // ---- TC2: single branch write, pointer advances by 1 --------
    do_reset();
    upd(1, 1'b1, 1'b0, 40'h0, 40'h0);
    if (ghr_buf[0] !== 1'b1)
      $fatal(1, "TC2 FAIL: ghr_buf[0] expected 1");
    if (ghist_ptr !== 8'd1)
      $fatal(1, "TC2 FAIL: ghist_ptr expected 1, got %0d", ghist_ptr);
    check_all_folds("TC2");
    pass_count++;
    $display("TC2 pass (single write, ptr=1)");

    // ---- TC3: dual branch write, slot0 at ptr, slot1 at ptr+1 ---
    do_reset();
    upd(2, 1'b0, 1'b1, 40'h0, 40'h0); // slot0=0, slot1=1
    if (ghr_buf[0] !== 1'b0)
      $fatal(1, "TC3 FAIL: ghr_buf[0] expected 0");
    if (ghr_buf[1] !== 1'b1)
      $fatal(1, "TC3 FAIL: ghr_buf[1] expected 1");
    if (ghist_ptr !== 8'd2)
      $fatal(1, "TC3 FAIL: ghist_ptr expected 2, got %0d", ghist_ptr);
    check_all_folds("TC3");
    pass_count++;
    $display("TC3 pass (dual write, ptr=2)");

    // ---- TC4: PHR path bit write --------------------------------
    do_reset();
    // pc[2]^pc[3]=1 -> path bit 1 at phist_ptr=0
    upd(1, 1'b1, 1'b0, 40'h4, 40'h0); // bit2=1 bit3=0
    if (phr_buf[0] !== 1'b1)
      $fatal(1, "TC4 FAIL: phr_buf[0] expected 1 (path=1)");
    if (phist_ptr !== 5'd1)
      $fatal(1, "TC4 FAIL: phist_ptr expected 1");
    // pc[2]^pc[3]=0 -> path bit 0 at phist_ptr=1
    upd(1, 1'b1, 1'b0, 40'hC, 40'h0); // bit2=1 bit3=1
    if (phr_buf[1] !== 1'b0)
      $fatal(1, "TC4 FAIL: phr_buf[1] expected 0 (path=0)");
    check_all_folds("TC4");
    pass_count++;
    $display("TC4 pass (PHR path bits)");

    // ---- TC5: num_branches semantics (req 5) --------------------
    // 0 holds; 1 advances by 1; 2 advances by 2.
    do_reset();
    // hold
    upd(0, 1'b1, 1'b1, 40'h0, 40'h0);
    if (ghist_ptr !== 8'd0 || phist_ptr !== 5'd0)
      $fatal(1, "TC5 FAIL: nb=0 advanced the pointer");
    if (ghr_buf !== '0)
      $fatal(1, "TC5 FAIL: nb=0 wrote GHR");
    // by 1
    upd(1, 1'b1, 1'b0, 40'h0, 40'h0);
    if (ghist_ptr !== 8'd1)
      $fatal(1, "TC5 FAIL: nb=1 ptr expected 1");
    // by 2
    upd(2, 1'b1, 1'b1, 40'h0, 40'h0);
    if (ghist_ptr !== 8'd3)
      $fatal(1, "TC5 FAIL: nb=2 ptr expected 3");
    if (ghr_buf[1] !== 1'b1 || ghr_buf[2] !== 1'b1)
      $fatal(1, "TC5 FAIL: nb=2 slot0@1 slot1@2 not written");
    check_all_folds("TC5");
    pass_count++;
    $display("TC5 pass (num_branches semantics)");

    // ---- TC6: single-slot equivalence, FILL+WRAP windows (req 3)-
    // Long directed-random single-slot run. After every update the
    // DUT folded must equal the one golden for every table, including
    // after each fold window (up to T4 H=119) fills and wraps.
    do_reset();
    begin
      int k;
      for (k = 0; k < 400; k++) begin
        upd(1, nextbit(), 1'b0, 40'h0, 40'h0);
        check_all_folds("TC6");
      end
    end
    if (folded.tage_t4_idx_fh === {TAGE_MAX_FH{1'b0}})
      $fatal(1, "TC6 FAIL: tage_t4 fold still zero after 400 updates");
    pass_count++;
    $display("TC6 pass (single-slot equivalence, windows filled)");

    // ---- TC7: dual-slot equivalence, TD #74 centerpiece ---------
    // Random dual bundles; slot1 frequently differs from slot0. After
    // each bundle the incremental folded must equal the one golden.
    do_reset();
    begin
      int k;
      for (k = 0; k < 300; k++) begin
        upd(2, nextbit(), nextbit(), 40'h0, 40'h0);
        check_all_folds("TC7");
      end
    end
    pass_count++;
    $display("TC7 pass (dual-slot equivalence, incremental==golden)");

    // ---- TC8: dual-slot incremental == recompute (TD #74) -------
    // Drive dual bundles, checkpoint a bundle, idle (no contamination
    // of the window), capture incremental fold, rollback, and confirm
    // the recompute equals BOTH the golden and the captured
    // incremental value. incr==golden AND recompute==golden together
    // prove incremental==recompute in simulation.
    do_reset();
    begin
      int k;
      logic [TAGE_MAX_FH-1:0] inc_t4;
      logic [SC_MAX_FH-1:0]   inc_sc3;
      // prime well past the longest window so T4/SC3 are meaningful
      for (k = 0; k < 80; k++) upd(2, nextbit(), nextbit(), 40'h0, 40'h0);
      // checkpointed dual bundle, slot1 differs from slot0
      pred_taken   = 2'b01;        // slot0=1, slot1=0
      num_branches = 2'd2;
      ckpt_wr_en   = 1'b1;
      ckpt_wr_idx  = FTQ_IDX_BITS'(9);
      tick();
      drive_idle();
      check_all_folds("TC8.incr");
      inc_t4  = folded.tage_t4_idx_fh;
      inc_sc3 = folded.sc_t3_idx_fh;
      // idle (no writes -> window not contaminated)
      repeat(2) tick();
      // rollback to the checkpoint
      rollback_valid    = 1'b1;
      rollback_ckpt_idx = FTQ_IDX_BITS'(9);
      tick();
      rollback_valid = 1'b0;
      tick();
      check_all_folds("TC8.recompute");
      if (folded.tage_t4_idx_fh !== inc_t4)
        $fatal(1, "TC8 FAIL: T4 recompute %h != incremental %h",
               folded.tage_t4_idx_fh, inc_t4);
      if (folded.sc_t3_idx_fh !== inc_sc3)
        $fatal(1, "TC8 FAIL: SC ST3 recompute %h != incremental %h",
               folded.sc_t3_idx_fh, inc_sc3);
    end
    pass_count++;
    $display("TC8 pass (dual-slot incremental==recompute, T4 + SC ST3)");

    // ---- TC9: dual bundle crossing the GHR_WIDTH boundary -------
    // Advance to ptr=255, then a dual bundle: slot0 at 255, slot1 at
    // 0 (wrap). Golden must still hold across the wrap.
    do_reset();
    begin
      int guard;
      guard = 0;
      while (ghist_ptr != 8'(GHR_WIDTH-1) && guard < 1000) begin
        upd(1, nextbit(), 1'b0, 40'h0, 40'h0);
        guard++;
      end
      if (ghist_ptr !== 8'(GHR_WIDTH-1))
        $fatal(1, "TC9 FAIL: could not reach ptr=255");
      // dual bundle across the boundary
      upd(2, 1'b1, 1'b1, 40'h0, 40'h0);
      if (ghr_buf[GHR_WIDTH-1] !== 1'b1)
        $fatal(1, "TC9 FAIL: slot0 @255 not written");
      if (ghr_buf[0] !== 1'b1)
        $fatal(1, "TC9 FAIL: slot1 wrap @0 not written");
      if (ghist_ptr !== 8'd1)
        $fatal(1, "TC9 FAIL: ptr expected 1 after wrap, got %0d",
               ghist_ptr);
      check_all_folds("TC9");
    end
    pass_count++;
    $display("TC9 pass (dual bundle crosses GHR_WIDTH boundary)");

    // ---- TC10: checkpoint + rollback by index (req 6) -----------
    // Checkpoint reports the POST-advance pointer; rollback restores
    // it and folds match the golden from the restored anchor.
    do_reset();
    begin
      int k;
      logic [GHIST_PTR_BITS-1:0] pre_g;
      logic [PHIST_PTR_BITS-1:0] pre_p;
      for (k = 0; k < 12; k++)
        upd(1, nextbit(), 1'b0, 40'h4, 40'h0);  // also advance PHR
      // a checkpointed single bundle at index 3
      pre_g        = ghist_ptr;
      pre_p        = phist_ptr;
      pred_taken   = 2'b01;
      pred_pc[0]   = 40'h4;
      num_branches = 2'd1;
      ckpt_wr_en   = 1'b1;
      ckpt_wr_idx  = FTQ_IDX_BITS'(3);
      tick();
      drive_idle();
      // post-advance pointer captured
      if (ckpt_ghist_ptr !== 8'((int'(pre_g)+1) % GHR_WIDTH))
        $fatal(1, "TC10 FAIL: ckpt_ghist_ptr post-advance expected %0d got %0d",
               (int'(pre_g)+1) % GHR_WIDTH, ckpt_ghist_ptr);
      if (ckpt_phist_ptr !== 5'((int'(pre_p)+1) % PHR_WIDTH))
        $fatal(1, "TC10 FAIL: ckpt_phist_ptr post-advance mismatch");
      // diverge, then rollback to the checkpoint
      for (k = 0; k < 5; k++) upd(1, nextbit(), 1'b0, 40'h0, 40'h0);
      rollback_valid    = 1'b1;
      rollback_ckpt_idx = FTQ_IDX_BITS'(3);
      tick();
      rollback_valid = 1'b0;
      tick();
      if (ghist_ptr !== 8'((int'(pre_g)+1) % GHR_WIDTH))
        $fatal(1, "TC10 FAIL: pointer not restored after rollback");
      check_all_folds("TC10");
    end
    pass_count++;
    $display("TC10 pass (checkpoint + rollback by index)");

    // ---- TC11: rollback wins, G21 (req 7) -----------------------
    // rollback_valid and num_branches=2 in the same cycle: the
    // prediction update and checkpoint write are dropped; pointer and
    // folds reflect the rollback; the targeted ckpt slot is unchanged.
    do_reset();
    begin
      int k;
      logic [GHIST_PTR_BITS-1:0] g_at_ck;
      logic [GHIST_PTR_BITS-1:0] v5;
      logic [GHR_WIDTH-1:0]      ghr_before;
      for (k = 0; k < 20; k++) upd(1, nextbit(), 1'b0, 40'h0, 40'h0);
      // checkpoint at index 7
      pred_taken   = 2'b01;
      num_branches = 2'd1;
      ckpt_wr_en   = 1'b1;
      ckpt_wr_idx  = FTQ_IDX_BITS'(7);
      tick();
      drive_idle();
      g_at_ck = ckpt_ghist_ptr;  // post-advance ckpt value
      // diverge a little, also write a different ckpt slot (5)
      for (k = 0; k < 4; k++) upd(1, nextbit(), 1'b0, 40'h0, 40'h0);
      pred_taken   = 2'b01;
      num_branches = 2'd1;
      ckpt_wr_en   = 1'b1;
      ckpt_wr_idx  = FTQ_IDX_BITS'(5);
      tick();
      drive_idle();
      v5         = ckpt_ghist_ptr;  // value stored in ckpt slot 5
      ghr_before = ghr_buf;
      // SAME-CYCLE rollback(idx 7) + prediction(nb=2) + ckpt write(5).
      // Rollback must win: no GHR write, no ckpt(5) overwrite.
      pred_taken        = 2'b11;
      num_branches      = 2'd2;
      ckpt_wr_en        = 1'b1;
      ckpt_wr_idx       = FTQ_IDX_BITS'(5);
      rollback_valid    = 1'b1;
      rollback_ckpt_idx = FTQ_IDX_BITS'(7);
      tick();
      drive_idle();
      tick();
      // pointer reflects rollback (restored to ckpt 7 post-advance)
      if (ghist_ptr !== g_at_ck)
        $fatal(1, "TC11 FAIL: rollback did not win on pointer (got %0d exp %0d)",
               ghist_ptr, g_at_ck);
      // GHR not written by the dropped prediction
      if (ghr_buf !== ghr_before)
        $fatal(1, "TC11 FAIL: dropped prediction still wrote GHR");
      // folds reflect the rollback recompute
      check_all_folds("TC11");
      // targeted ckpt slot 5 unchanged: roll back to it and confirm the
      // stored pointer is the pre-rollback value, not the dropped write.
      rollback_valid    = 1'b1;
      rollback_ckpt_idx = FTQ_IDX_BITS'(5);
      tick();
      rollback_valid = 1'b0;
      tick();
      if (ghist_ptr !== v5)
        $fatal(1, "TC11 FAIL: dropped write overwrote ckpt slot 5 (got %0d exp %0d)",
               ghist_ptr, v5);
    end
    pass_count++;
    $display("TC11 pass (rollback wins over same-cycle update)");

    // ---- TC12: stale fold, G22 (req 8) --------------------------
    // In the rollback cycle the fold outputs HOLD their prior value;
    // the recomputed value appears the next cycle. Timing observation.
    do_reset();
    begin
      int k;
      bp_folded_hist_t pre_fold;
      for (k = 0; k < 30; k++) upd(1, nextbit(), 1'b0, 40'h0, 40'h0);
      // checkpoint at index 2
      pred_taken   = 2'b01;
      num_branches = 2'd1;
      ckpt_wr_en   = 1'b1;
      ckpt_wr_idx  = FTQ_IDX_BITS'(2);
      tick();
      drive_idle();
      // diverge so the recompute will differ from current fold
      for (k = 0; k < 6; k++) upd(1, nextbit(), 1'b0, 40'h0, 40'h0);
      pre_fold = folded;
      // Assert rollback combinationally. folded is registered, so
      // within this same (rollback) cycle -- before the next posedge --
      // it must still hold its prior value (stale, not invalid).
      rollback_valid    = 1'b1;
      rollback_ckpt_idx = FTQ_IDX_BITS'(2);
      #1;              // settle, still pre-edge in the rollback cycle
      if (folded !== pre_fold)
        $fatal(1, "TC12 FAIL: folded not stable in the rollback cycle (stale)");
      tick();          // posedge samples rollback -> recompute registers
      rollback_valid = 1'b0;
      if (folded === pre_fold)
        $fatal(1, "TC12 FAIL: folded did not recompute after rollback");
      tick();
      check_all_folds("TC12");
    end
    pass_count++;
    $display("TC12 pass (stale fold in rollback cycle, recompute next)");

    // ---- TC13: unrelated checkpoint preserved across rollback ---
    do_reset();
    begin
      int k;
      logic [GHIST_PTR_BITS-1:0] g6;
      for (k = 0; k < 8; k++) upd(1, nextbit(), 1'b0, 40'h0, 40'h0);
      // checkpoint idx 2
      pred_taken   = 2'b01; num_branches = 2'd1;
      ckpt_wr_en   = 1'b1; ckpt_wr_idx = FTQ_IDX_BITS'(2);
      tick(); drive_idle();
      // checkpoint idx 6
      pred_taken   = 2'b01; num_branches = 2'd1;
      ckpt_wr_en   = 1'b1; ckpt_wr_idx = FTQ_IDX_BITS'(6);
      tick(); drive_idle();
      g6 = ckpt_ghist_ptr;  // post-advance value stored at idx 6
      // rollback to idx 2
      rollback_valid = 1'b1; rollback_ckpt_idx = FTQ_IDX_BITS'(2);
      tick(); rollback_valid = 1'b0; tick();
      // rollback to idx 6 -- must still hold its value
      rollback_valid = 1'b1; rollback_ckpt_idx = FTQ_IDX_BITS'(6);
      tick(); rollback_valid = 1'b0; tick();
      if (ghist_ptr !== g6)
        $fatal(1, "TC13 FAIL: ckpt idx 6 not preserved (got %0d exp %0d)",
               ghist_ptr, g6);
      check_all_folds("TC13");
    end
    pass_count++;
    $display("TC13 pass (unrelated checkpoint preserved)");

    // ================================================================
    // BP-073 external-anchor tests (TC14-TC16).
    // Each anchors a DUT fold to a hand-derived literal computed from
    // the Xiangshan FoldedHistory definition over an age-indexed known
    // history, AND to xs_fold_ref (which is independent of the GHR
    // buffer, the DUT anchor, fold_step/fold_ghr, and the BP-072
    // fold_ref). Histories are DRIVEN (reset + directed pred_taken),
    // and ghr_buf is confirmed before the fold is checked.
    // ================================================================

    // ---- TC14: TAGE T1 idx, FULL 8-bit window (req 2, req 3) -----
    // Driven single-slot pushes, p0 first(oldest)..p7 newest:
    //   p = 1 1 0 0 1 0 1 1  -> ghr_buf[7:0] = 0xD3, ghist_ptr = 8.
    // Age-indexed history (age0 newest = p7): ages with 1 = {0,1,3,6,7}.
    // H = W = TAGE_TBL_HIST[1] = TAGE_TBL_FH[1] = 8, posmap(i)=(i+7)%8:
    //   age0->b7 age1->b0 age3->b2 age6->b5 age7->b6
    //   -> fold bits {7,6,5,2,0} = 1110_0101 = 0xE5.
    do_reset();
    begin
      logic [GHR_WIDTH-1:0] kh;
      upd(1, 1'b1, 1'b0, 40'h0, 40'h0); // p0 = 1 (oldest)
      upd(1, 1'b1, 1'b0, 40'h0, 40'h0); // p1 = 1
      upd(1, 1'b0, 1'b0, 40'h0, 40'h0); // p2 = 0
      upd(1, 1'b0, 1'b0, 40'h0, 40'h0); // p3 = 0
      upd(1, 1'b1, 1'b0, 40'h0, 40'h0); // p4 = 1
      upd(1, 1'b0, 1'b0, 40'h0, 40'h0); // p5 = 0
      upd(1, 1'b1, 1'b0, 40'h0, 40'h0); // p6 = 1
      upd(1, 1'b1, 1'b0, 40'h0, 40'h0); // p7 = 1 (newest)
      if (ghr_buf[7:0] !== 8'hD3)
        $fatal(1, "TC14 FAIL: ghr_buf[7:0]=%h exp D3", ghr_buf[7:0]);
      if (ghist_ptr !== 8'd8)
        $fatal(1, "TC14 FAIL: ghist_ptr=%0d exp 8", ghist_ptr);
      kh = '0;
      kh[0] = 1'b1; kh[1] = 1'b1; kh[3] = 1'b1; kh[6] = 1'b1; kh[7] = 1'b1;
      chk_anchor(64'(folded.tage_t1_idx_fh), kh,
                 TAGE_TBL_HIST[1], TAGE_TBL_FH[1],
                 64'h0000_0000_0000_00E5, "TC14.tage_t1_idx_FULL8");
    end
    pass_count++;
    $display("TC14 pass (BP-073 anchor: TAGE T1 idx, full 8b = 0xE5)");

    // ---- TC15: ITTAGE IT1 idx, SHORT sub-window (req 2, req 3) ---
    // Drive only 2 single-slot pushes into a H=4 window (2 bits filled,
    // 2 reset zeros): p0=1, p1=1 -> ghr_buf[1:0]=0x3, ghist_ptr=2.
    // Age history age0=p1=1, age1=p0=1, age2=age3=0.
    // H = W = IT_TBL_HIST[1] = IT_TBL_FH[1] = 4, posmap(i)=(i+3)%4:
    //   age0->b3 age1->b0 -> fold bits {3,0} = 1001 = 0x9.
    do_reset();
    begin
      logic [GHR_WIDTH-1:0] kh;
      upd(1, 1'b1, 1'b0, 40'h0, 40'h0); // p0 = 1 (oldest in window)
      upd(1, 1'b1, 1'b0, 40'h0, 40'h0); // p1 = 1 (newest)
      if (ghr_buf[1:0] !== 2'b11)
        $fatal(1, "TC15 FAIL: ghr_buf[1:0]=%b exp 11", ghr_buf[1:0]);
      if (ghist_ptr !== 8'd2)
        $fatal(1, "TC15 FAIL: ghist_ptr=%0d exp 2", ghist_ptr);
      kh = '0;
      kh[0] = 1'b1; kh[1] = 1'b1;
      chk_anchor(64'(folded.it_t1_idx_fh), kh,
                 IT_TBL_HIST[1], IT_TBL_FH[1],
                 64'h0000_0000_0000_0009, "TC15.it_t1_idx_SHORT2");
    end
    pass_count++;
    $display("TC15 pass (BP-073 anchor: ITTAGE IT1 idx, short 2b = 0x9)");

    // ---- TC16: SC ST3 idx, FULL + WRAPPED 64-bit window ----------
    // (req 2 SC ST3 boundary, req 3 full/wrapped). H = W = 64, the
    // case that forced the 64b helpers and cannot be held at 32b.
    // Advance the pointer to 250 with zero pushes (GHR stays zero),
    // then drive a 64-bit window that wraps 255->0: first push = 1
    // (lands at pos 250, becomes age63), 62 zero pushes, last push = 1
    // (pos 57, age0). Final ghist_ptr = (250+64) % 256 = 58.
    // Age history: age0=1, age63=1, rest 0. posmap(i)=(i+63)%64:
    //   age0 ->(63)%64=63, age63->(126)%64=62 -> fold bits {63,62}
    //   = 0xC000_0000_0000_0000 (the literal cannot fit in 32b).
    do_reset();
    begin
      int                   k;
      logic [GHR_WIDTH-1:0] kh;
      for (k = 0; k < 250; k++) upd(1, 1'b0, 1'b0, 40'h0, 40'h0);
      upd(1, 1'b1, 1'b0, 40'h0, 40'h0);                 // pos 250 = 1
      for (k = 0; k < 62; k++) upd(1, 1'b0, 1'b0, 40'h0, 40'h0);
      upd(1, 1'b1, 1'b0, 40'h0, 40'h0);                 // pos 57  = 1
      if (ghist_ptr !== 8'd58)
        $fatal(1, "TC16 FAIL: ghist_ptr=%0d exp 58", ghist_ptr);
      if (ghr_buf[250] !== 1'b1 || ghr_buf[57] !== 1'b1)
        $fatal(1, "TC16 FAIL: wrapped window endpoints not set");
      if ($countones(ghr_buf) !== 2)
        $fatal(1, "TC16 FAIL: ghr has %0d ones exp 2",
               $countones(ghr_buf));
      kh = '0;
      kh[0] = 1'b1; kh[63] = 1'b1;
      chk_anchor(64'(folded.sc_t3_idx_fh), kh,
                 SC_TBL_HIST[3], SC_TBL_HIST[3],
                 64'hC000_0000_0000_0000, "TC16.sc_t3_idx_WRAP64");
    end
    pass_count++;
    $display("TC16 pass (BP-073 anchor: SC ST3 idx, wrap 64b = 0xC..0)");

    $display("----------------------------------------------------");
    $display("BP-072: %0d directed test cases passed", pass_count);
    $display("BP-072: %0d golden fold comparisons passed", fold_checks);
    $display("BP-073: %0d external anchor checks passed", anchor_checks);
    $display("BP-072: ALL TESTS PASSED");
    $display("BP-073: ALL EXTERNAL ANCHORS MATCH (TAGE T1, IT1, SC ST3)");
    $finish;
  end

endmodule : tb
