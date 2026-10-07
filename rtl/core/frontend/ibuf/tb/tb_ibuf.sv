// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_ibuf.sv
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking testbench for ibuf (BP-118 Problem 3).
//
// Two instances: u_d64 at the default DEPTH of 64 (IBUF-11) and u_d48
// at DEPTH 48, which is not a power of two and so exercises the
// compare-and-subtract index wrap. Each has its own stimulus.
//
// THE REFERENCE IS A QUEUE MODEL in this file, one per instance,
// updated from the stimulus alone: an accepted block appends its
// enabled positions in position order, a ready pops the presented
// entries, the backend redirect valid empties it. Every cycle the
// scoreboard compares ibuf_ifu_rdy and every read slot against the
// model. The directed groups check named values on top of it.
//
//   T1  reset state
//   T2  compaction on write, in order (IBUF-3)
//   T3  up to 8 from the head, one ready dequeues all (IBUF-9, -12)
//   T4  ready only with 16 free, whatever the mask; full (IBUF-4)
//   T5  same-cycle bypass of an empty buffer (IBUF-7)
//   T6  the backend redirect valid clears, nothing else does
//       (IBUF-8, IBUF-13)
//   T7  wrap, write and read in one cycle, DEPTH 64
//   T8  DEPTH 48: ready at the floor, random stress with clears
//
// Every case starts from reset (no state carried across groups).
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  localparam int ND    = 2;
  localparam int RDW   = 8;
  localparam int NPOS  = FTQ_PD_WIDTH;
  localparam int DEP [ND] = '{64, 48};

  logic clk;
  logic rstn;

  // Per-instance stimulus and outputs.
  logic              val  [ND];
  logic [NPOS-1:0]   en   [ND];
  ifu_pd_pkt_t       slot [ND][0:NPOS-1];
  logic              clr  [ND];
  logic              drdy [ND];
  logic              rdy  [ND];
  ifu_pd_pkt_t       rd   [ND][0:RDW-1];

  ibuf u_d64 (
    .clk                 (clk),
    .rstn                (rstn),
    .ifu_ibuf_val        (val[0]),
    .ifu_ibuf_en         (en[0]),
    .ifu_ibuf_slot       (slot[0]),
    .ibuf_ifu_rdy        (rdy[0]),
    .bkend_ftq_redir_val (clr[0]),
    .ibuf_dec_slot       (rd[0]),
    .dec_ibuf_rdy        (drdy[0])
  );

  ibuf #(.DEPTH(48)) u_d48 (
    .clk                 (clk),
    .rstn                (rstn),
    .ifu_ibuf_val        (val[1]),
    .ifu_ibuf_en         (en[1]),
    .ifu_ibuf_slot       (slot[1]),
    .ibuf_ifu_rdy        (rdy[1]),
    .bkend_ftq_redir_val (clr[1]),
    .ibuf_dec_slot       (rd[1]),
    .dec_ibuf_rdy        (drdy[1])
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  int pass_cnt;
  int fail_cnt;
  int sb_cmp;       // scoreboard comparisons made
  int sb_fail;      // scoreboard mismatches
  int both_cycles;  // cycles with a write and a read on u_d64
  int popped [ND];  // entries popped since reset

  task automatic chk(input logic c, input string name);
    if (c) pass_cnt++;
    else begin
      fail_cnt++;
      $display("FAIL: %s", name);
    end
  endtask

  // A distinct, fully populated payload for block b, position i.
  // valid is left clear: the IFU does not drive it (IB-3).
  function automatic ifu_pd_pkt_t mk(input int b, input int i);
    ifu_pd_pkt_t p;
    p             = '0;
    p.instr       = {b[23:0], i[7:0]};
    p.start_pc    = VA_WIDTH'(64'h8000_0000 + b * 64 + i * 2);
    p.pos         = FTQ_PD_POS_BITS'(i);
    p.ftq_idx     = FTQ_IDX_BITS'(b);
    p.fault_cause = ifu_fault_e'(i % 4);
    p.fault_va    = ~p.start_pc;
    p.fault_gpa   = GPA_WIDTH'(b * 977 + i);
    p.is_rvc      = i[0];
    p.br_type     = i[2:1];
    p.is_call     = b[0];
    p.is_ret      = b[1];
    p.is_vsetvl   = i[2];
    p.needs_vtype = i[3];
    return p;
  endfunction

  // ---------------------------------------------------------------
  // The reference model and the scoreboard.
  // ---------------------------------------------------------------
  ifu_pd_pkt_t mq [ND][$];

  // A forever loop on the rising edge rather than an always block: it
  // samples the DUT before the edge's flop updates land, and keeps its
  // counters as blocking test state.
  initial begin : scoreboard
    forever begin
      @(posedge clk);
      if (rstn) begin
        for (int d = 0; d < ND; d++) begin
          ifu_pd_pkt_t wc [$];
          ifu_pd_pkt_t ex;
          int          n_pres;
          logic        acc;
          logic        e_rdy;

          e_rdy = (DEP[d] - mq[d].size()) >= NPOS;
          sb_cmp++;
          if (rdy[d] !== e_rdy) begin
            sb_fail++;
            $display("SB d%0d: rdy %0b exp %0b (held %0d)", d, rdy[d],
                     e_rdy, mq[d].size());
          end

          acc = val[d] && e_rdy && !clr[d];
          wc.delete();
          for (int i = 0; i < NPOS; i++) begin
            if (en[d][i]) begin
              ex       = slot[d][i];
              ex.valid = 1'b1;
              wc.push_back(ex);
            end
          end

          if (clr[d])                         n_pres = 0;
          else if ((mq[d].size() == 0) && acc) n_pres = wc.size();
          else                                n_pres = mq[d].size();
          if (n_pres > RDW) n_pres = RDW;

          for (int k = 0; k < RDW; k++) begin
            sb_cmp++;
            if (k < n_pres) begin
              ex       = (mq[d].size() == 0) ? wc[k] : mq[d][k];
              ex.valid = 1'b1;
              if (rd[d][k] !== ex) begin
                sb_fail++;
                $display("SB d%0d: slot %0d instr %h exp %h", d, k,
                         rd[d][k].instr, ex.instr);
              end
            end else if (rd[d][k].valid !== 1'b0) begin
              sb_fail++;
              $display("SB d%0d: slot %0d valid, exp empty", d, k);
            end
          end

          if (clr[d]) mq[d].delete();
          else begin
            if (acc) foreach (wc[j]) mq[d].push_back(wc[j]);
            if (drdy[d]) begin
              for (int k = 0; k < n_pres; k++) void'(mq[d].pop_front());
              popped[d] += n_pres;
              if ((d == 0) && acc && (n_pres > 0)) both_cycles++;
            end
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------
  // Stimulus helpers. Inputs change 1 time unit after a rising edge.
  // ---------------------------------------------------------------
  task automatic step(input int n = 1);
    repeat (n) @(posedge clk);
    #1;
  endtask

  task automatic idle(input int d);
    val[d]  = 1'b0;
    en[d]   = '0;
    clr[d]  = 1'b0;
    drdy[d] = 1'b0;
    for (int i = 0; i < NPOS; i++) slot[d][i] = '0;
  endtask

  // Offer block b with mask m on instance d.
  task automatic offer(input int d, input int b, input logic [NPOS-1:0] m);
    val[d] = 1'b1;
    en[d]  = m;
    for (int i = 0; i < NPOS; i++) slot[d][i] = mk(b, i);
  endtask

  task automatic reset_all();
    for (int d = 0; d < ND; d++) begin
      idle(d);
      mq[d].delete();
      popped[d] = 0;
    end
    rstn = 1'b0;
    step(2);
    rstn = 1'b1;
    step(1);
  endtask

  function automatic int n_valid(input int d);
    int n;
    n = 0;
    for (int k = 0; k < RDW; k++) if (rd[d][k].valid) n++;
    return n;
  endfunction

  // Write blocks of 16 enabled positions into instance d, no reads.
  task automatic fill_blocks(input int d, input int nblk, input int b0);
    for (int j = 0; j < nblk; j++) begin
      offer(d, b0 + j, '1);
      step();
    end
    idle(d);
  endtask

  // ---------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------
  initial begin : main
    logic [NPOS-1:0] m;
    int              ord [5];

    pass_cnt    = 0;
    fail_cnt    = 0;
    sb_cmp      = 0;
    sb_fail     = 0;
    both_cycles = 0;

    // T1 reset state.
    reset_all();
    chk(rdy[0] && rdy[1], "T1 ready out of reset");
    chk(n_valid(0) == 0 && n_valid(1) == 0, "T1 nothing presented");

    // T2 compaction (IBUF-3). Positions 0, 5, 6, 13, 15 enabled.
    reset_all();
    m   = 16'b1010_0000_0110_0001;
    ord = '{0, 5, 6, 13, 15};
    offer(0, 7, m);
    // Same cycle: the empty buffer bypasses, already compacted.
    #1;
    chk(n_valid(0) == 5, "T2 five slots presented");
    for (int k = 0; k < 5; k++)
      chk(rd[0][k].instr == mk(7, ord[k]).instr &&
          rd[0][k].pos == FTQ_PD_POS_BITS'(ord[k]),
          $sformatf("T2 bypass slot %0d is position %0d", k, ord[k]));
    step();
    idle(0);
    #1;
    // Stored: the same order from the array.
    chk(n_valid(0) == 5, "T2 five stored");
    for (int k = 0; k < 5; k++) begin
      ifu_pd_pkt_t e;
      e       = mk(7, ord[k]);
      e.valid = 1'b1;
      chk(rd[0][k] == e,
          $sformatf("T2 stored slot %0d whole payload", k));
    end
    for (int k = 5; k < RDW; k++)
      chk(!rd[0][k].valid, $sformatf("T2 slot %0d empty", k));

    // T3 read width and the single ready (IBUF-9, IBUF-12).
    reset_all();
    fill_blocks(0, 2, 20);          // 32 held: A = 20, B = 21
    #1;
    chk(n_valid(0) == 8, "T3 eight presented of 32");
    for (int k = 0; k < RDW; k++)
      chk(rd[0][k].instr == mk(20, k).instr,
          $sformatf("T3 slot %0d is A%0d", k, k));
    drdy[0] = 1'b1;
    step();
    drdy[0] = 1'b0;
    #1;
    chk(rd[0][0].instr == mk(20, 8).instr, "T3 one ready took eight");
    drdy[0] = 1'b1;
    step();
    drdy[0] = 1'b0;
    #1;
    chk(rd[0][0].instr == mk(21, 0).instr, "T3 head is now B0");
    drdy[0] = 1'b1;
    step(2);                        // B drained
    drdy[0] = 1'b0;
    offer(0, 22, 16'b0000_0100_1001_0011);   // five entries
    step();
    idle(0);
    #1;
    chk(n_valid(0) == 5, "T3 five of five presented");
    drdy[0] = 1'b1;
    step();
    drdy[0] = 1'b0;
    #1;
    chk(n_valid(0) == 0, "T3 one ready dequeued all five");

    // T4 the ready rule (IBUF-4, IB-6) and full.
    reset_all();
    fill_blocks(0, 3, 30);          // 48 held, 16 free
    #1;
    chk(rdy[0], "T4 ready at 16 free");
    offer(0, 33, 16'h0001);         // a one-entry block
    step();
    #1;
    chk(!rdy[0], "T4 not ready at 15 free, one-entry block");
    // Hold a one-entry offer while refused: it is not taken.
    offer(0, 34, 16'h0001);
    step(3);
    idle(0);
    #1;
    chk(!rdy[0], "T4 still not ready, refused block not taken");
    drdy[0] = 1'b1;
    step();                         // 49 -> 41
    drdy[0] = 1'b0;
    #1;
    chk(rdy[0], "T4 ready again at 23 free");
    reset_all();
    fill_blocks(0, 4, 40);          // 64 held: full
    #1;
    chk(!rdy[0], "T4 full: not ready");
    chk(n_valid(0) == 8 && rd[0][0].instr == mk(40, 0).instr,
        "T4 full: head presented");
    drdy[0] = 1'b1;
    step(8);                        // drain all 64 in order (scoreboard)
    drdy[0] = 1'b0;
    #1;
    chk(n_valid(0) == 0 && rdy[0] && popped[0] == 64,
        "T4 full buffer drained, 64 popped");

    // T5 bypass (IBUF-7), with the ready high in the same cycle.
    reset_all();
    offer(0, 50, 16'h03ff);         // ten entries
    drdy[0] = 1'b1;
    #1;
    chk(n_valid(0) == 8 && rd[0][0].instr == mk(50, 0).instr &&
        rd[0][7].instr == mk(50, 7).instr,
        "T5 empty buffer presents the write in the same cycle");
    step();
    idle(0);
    #1;
    chk(n_valid(0) == 2 && rd[0][0].instr == mk(50, 8).instr &&
        rd[0][1].instr == mk(50, 9).instr,
        "T5 remainder stored after the bypassed eight");
    // Not empty: a write does not bypass; the head is presented.
    offer(0, 51, 16'h00ff);
    #1;
    chk(n_valid(0) == 2 && rd[0][0].instr == mk(50, 8).instr,
        "T5 no bypass when not empty");
    step();
    idle(0);

    // T6 the clear (IBUF-8, IBUF-13).
    reset_all();
    fill_blocks(0, 2, 60);          // 32 held
    // Nothing else clears: idle cycles, and an empty-mask block.
    step(20);
    offer(0, 62, '0);
    step();
    idle(0);
    #1;
    chk(n_valid(0) == 8 && rd[0][0].instr == mk(60, 0).instr,
        "T6 contents kept without the backend redirect");
    // Clear cycle: a write offered and the ready high.
    clr[0]  = 1'b1;
    drdy[0] = 1'b1;
    offer(0, 63, '1);
    #1;
    chk(n_valid(0) == 0, "T6 nothing presented in the clear cycle");
    step();
    idle(0);
    #1;
    chk(n_valid(0) == 0 && rdy[0], "T6 empty after the clear");
    offer(0, 64, 16'h0003);
    step();
    idle(0);
    #1;
    chk(n_valid(0) == 2 && rd[0][0].instr == mk(64, 0).instr,
        "T6 clear write discarded, next block at the head");
    clr[0] = 1'b1;
    step();
    idle(0);
    #1;
    chk(n_valid(0) == 0, "T6 clear on a 2-entry buffer");

    // T7 wrap, and a write and a read in one cycle, DEPTH 64.
    reset_all();
    for (int c = 0; c < 200; c++) begin
      offer(0, 100 + c, (c % 3 == 0) ? 16'hffff : 16'h5a5a);
      drdy[0] = (c % 5 != 4);
      step();
    end
    idle(0);
    drdy[0] = 1'b1;
    step(20);
    idle(0);
    #1;
    chk(popped[0] > 4 * 64, "T7 head passed the array end four times");
    chk(both_cycles > 50, "T7 write and read in one cycle");
    chk(n_valid(0) == 0, "T7 drained");

    // T8 DEPTH 48: the ready at the floor, then random stress.
    reset_all();
    fill_blocks(1, 2, 200);         // 32 held, 16 free
    #1;
    chk(rdy[1], "T8 DEPTH 48 ready at 16 free");
    offer(1, 202, 16'h8000);
    step();
    idle(1);
    #1;
    chk(!rdy[1], "T8 DEPTH 48 not ready at 15 free");
    reset_all();
    for (int c = 0; c < 3000; c++) begin
      for (int d = 0; d < ND; d++) begin
        int r;
        r = $urandom_range(0, 99);
        offer(d, 1000 + c, NPOS'($urandom));
        val[d]  = (r < 70);
        drdy[d] = ($urandom_range(0, 99) < 55);
        clr[d]  = (r == 99);
      end
      step();
    end
    for (int d = 0; d < ND; d++) idle(d);
    step(2);
    chk(popped[0] > 4 * 64 && popped[1] > 4 * 48,
        "T8 random stress wrapped both instances");

    chk(sb_fail == 0, $sformatf("scoreboard: %0d of %0d mismatched",
                                sb_fail, sb_cmp));
    $display("tb_ibuf: scoreboard compares=%0d", sb_cmp);
    $display("tb_ibuf: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ibuf: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin : watchdog
    #2_000_000;
    $fatal(1, "tb_ibuf: timeout");
  end

endmodule : tb
