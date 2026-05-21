// ===================================================================
// FILE:    tb_ubtb.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Self-checking testbench for ubtb.sv.
// TC1-TC10 cover reset, hit, miss, aliasing, replacement,
// br_type coverage, carry bit, update overwrite, dual-slot,
// and read-during-write same set.
//
// These results need to be checked against results from manual testbench
// ===================================================================

import bp_defines_pkg::*;
import bp_structs_pkg::*;
module tb;

  // ----------------------------------------------------------------
  // DUT signals: NUM_PRED_SLOTS=1
  // ----------------------------------------------------------------
  logic                          clk;
  logic                          rstn;
  logic [VA_WIDTH-1:0]           pred_pc;
  ubtb_pred_t [0:0]              pred1;
  ubtb_upd_t  [0:0]              upd1;

  ubtb #(.NUM_PRED_SLOTS(1)) dut1 (
    .clk        (clk),
    .rstn       (rstn),
    .pred_pc_p0 (pred_pc),
    .pred_p1    (pred1),
    .upd_u0     (upd1)
  );

  // ----------------------------------------------------------------
  // DUT signals: NUM_PRED_SLOTS=2 (TC9)
  // ----------------------------------------------------------------
  logic [VA_WIDTH-1:0]           pred_pc2;
  ubtb_pred_t [1:0]              pred2;
  ubtb_upd_t  [1:0]              upd2;

  ubtb #(.NUM_PRED_SLOTS(2)) dut2 (
    .clk        (clk),
    .rstn       (rstn),
    .pred_pc_p0 (pred_pc2),
    .pred_p1    (pred2),
    .upd_u0     (upd2)
  );

  // ----------------------------------------------------------------
  // Clock generation: 10ns period
  // ----------------------------------------------------------------
  initial clk = 0;
  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  // ----------------------------------------------------------------
  // Test infrastructure
  // ----------------------------------------------------------------
  int fail_count;

  task automatic check(
    input string  tc,
    input logic   cond,
    input string  msg
  );
    if (!cond) begin
      $display("FAIL [%s]: %s", tc, msg);
      fail_count++;
    end
  endtask

  // Pulse reset for 2 cycles
  task automatic do_reset;
    rstn = 0;
    pred_pc  = '0;
    pred_pc2 = '0;
    upd1[0]  = '0;
    upd2[0]  = '0;
    upd2[1]  = '0;
    @(posedge clk); #1;
    @(posedge clk); #1;
    rstn = 1;
    @(posedge clk); #1;
  endtask

  // Write one entry via upd1 (slot 0), then deassert
  task automatic write_entry(
    input logic [VA_WIDTH-1:0] pc,
    input bp_br_type_e         br_type,
    input logic [VA_WIDTH-1:0] target,
    input logic                br_taken,
    input logic                carry
  );
    upd1[0].valid    = 1'b1;
    upd1[0].pc       = pc;
    upd1[0].br_type  = br_type;
    upd1[0].target   = target;
    upd1[0].br_taken = br_taken;
    upd1[0].carry    = carry;
    @(posedge clk); #1;
    upd1[0].valid = 1'b0;
  endtask

  // ----------------------------------------------------------------
  // Test body
  // ----------------------------------------------------------------
  initial begin
    fail_count = 0;

    // ----------------------------------------------------------------
    // TC1 -- Reset state: no spurious hits after reset
    // ----------------------------------------------------------------
    do_reset();
    pred_pc = 40'h0000_1000;
    @(posedge clk); #1;  // wait one cycle for pred to settle
    check("TC1", pred1[0].valid == 1'b0,
          "Expected pred[0].valid=0 after reset");
    $display("TC1 -- Reset state: %s",
             (pred1[0].valid == 0) ? "PASS" : "FAIL");

    // ----------------------------------------------------------------
    // TC2 -- Single write, single hit
    // ----------------------------------------------------------------
    begin
      logic [VA_WIDTH-1:0] pc_a, tgt_a;
      pc_a  = 40'h0000_2000;
      tgt_a = 40'h0000_3000;
      write_entry(pc_a, COND, tgt_a, 1'b1, 1'b0);
      pred_pc = pc_a;
      @(posedge clk); #1;
      check("TC2a", pred1[0].valid    == 1'b1,  "valid should be 1");
      check("TC2b", pred1[0].target   == tgt_a, "target mismatch");
      check("TC2c", pred1[0].br_type  == COND,  "br_type mismatch");
      check("TC2d", pred1[0].br_taken == 1'b1,  "br_taken mismatch");
      $display("TC2 -- Single write/hit: %s",
               (pred1[0].valid && pred1[0].target == tgt_a &&
                pred1[0].br_type == COND &&
                pred1[0].br_taken) ? "PASS" : "FAIL");
    end

    // ----------------------------------------------------------------
    // TC3 -- Miss: different PC not written
    // ----------------------------------------------------------------
    begin
      logic [VA_WIDTH-1:0] miss_pc;
      miss_pc = 40'h0000_ABCD; // tag will differ
      pred_pc = miss_pc;
      @(posedge clk); #1;
      check("TC3", pred1[0].valid == 1'b0, "Expected miss, got hit");
      $display("TC3 -- Miss: %s",
               (pred1[0].valid == 0) ? "PASS" : "FAIL");
    end

    // ----------------------------------------------------------------
    // TC4 -- Tag collision (aliasing):
    //   Two PCs mapping to the same set, different tags.
    //   Construct by keeping PC[7:2] equal but differing PC[26:7].
    // ----------------------------------------------------------------
    begin
      // PC[7:2]=6'h01 for both; differ at bit 8
      logic [VA_WIDTH-1:0] pc_x, pc_y, tgt_x, tgt_y;
      pc_x  = 40'h0000_0004; // idx=1, tag from [26:7]
      pc_y  = 40'h0000_0104; // idx=1, tag differs (bit 8 set)
      tgt_x = 40'h0000_4000;
      tgt_y = 40'h0000_5000;
      write_entry(pc_x, DIRECT_UNC, tgt_x, 1'b0, 1'b0);
      write_entry(pc_y, DIRECT_UNC, tgt_y, 1'b0, 1'b0);
      // Check pc_x hits own target
      pred_pc = pc_x;
      @(posedge clk); #1;
      check("TC4a", pred1[0].valid  == 1'b1,  "TC4a: x miss unexpected");
      check("TC4b", pred1[0].target == tgt_x, "TC4b: x target wrong");
      // Check pc_y hits own target
      pred_pc = pc_y;
      @(posedge clk); #1;
      check("TC4c", pred1[0].valid  == 1'b1,  "TC4c: y miss unexpected");
      check("TC4d", pred1[0].target == tgt_y, "TC4d: y target wrong");
      $display("TC4 -- Tag collision: %s",
               (fail_count == 0) ? "PASS" : "FAIL");
    end

    // ----------------------------------------------------------------
    // TC5 -- Way replacement:
    //   Write UBTB_WAYS+1 entries to same set. Oldest should evict.
    // ----------------------------------------------------------------
    begin
      // Use set index 2 (pc[7:2]=2 -> pc[7:0]=8 -> pc=0x...008 + tag)
      // Keep [7:2]=6'd2, vary bits [26:8] for distinct tags.
      logic [VA_WIDTH-1:0] pcs[5];
      logic [VA_WIDTH-1:0] tgts[5];
      int tc5_fail;
      tc5_fail = 0;
      for (int i = 0; i < 5; i++) begin
        // bits [7:2] = 2, bits [26:8] vary by i*256 -> tag differs
        pcs[i]  = 40'h0000_0008 | (VA_WIDTH'(i) << 8);
        tgts[i] = 40'h0001_0000 + VA_WIDTH'(i);
        write_entry(pcs[i], COND, tgts[i], 1'b0, 1'b0);
      end
      // Oldest entry (pcs[0]) should have been evicted (way 0 reused)
      pred_pc = pcs[0];
      @(posedge clk); #1;
      if (pred1[0].valid && pred1[0].target == tgts[0])
        tc5_fail++;
      // Newest entry (pcs[4]) should hit
      pred_pc = pcs[4];
      @(posedge clk); #1;
      if (!pred1[0].valid || pred1[0].target != tgts[4])
        tc5_fail++;
      check("TC5", tc5_fail == 0, "Way replacement incorrect");
      $display("TC5 -- Way replacement: %s",
               (tc5_fail == 0) ? "PASS" : "FAIL");
    end

    // ----------------------------------------------------------------
    // TC6 -- br_type encoding coverage (all 7 bp_br_type_e values)
    // ----------------------------------------------------------------
    begin
      bp_br_type_e types[7];
      logic [VA_WIDTH-1:0] pc_base;
      int tc6_fail;
      tc6_fail = 0;
      types[0] = NO_BRANCH;
      types[1] = COND;
      types[2] = DIRECT_UNC;
      types[3] = DIRECT_CALL;
      types[4] = INDIRECT_CALL;
      types[5] = INDIRECT_NONRET;
      types[6] = RETURN;
      // Use distinct set indices (bits [7:2] vary): sets 10-16
      for (int i = 0; i < 7; i++) begin
        // Place each in a unique set: set = 10+i
        pc_base = (VA_WIDTH'(10) + VA_WIDTH'(i)) << 2;
        write_entry(pc_base, types[i],
                    40'h0002_0000 + VA_WIDTH'(i), 1'b0, 1'b0);
      end
      for (int i = 0; i < 7; i++) begin
        pc_base = (VA_WIDTH'(10) + VA_WIDTH'(i)) << 2;
        pred_pc = pc_base;
        @(posedge clk); #1;
        if (!pred1[0].valid || pred1[0].br_type != types[i])
          tc6_fail++;
      end
      check("TC6", tc6_fail == 0, "br_type encoding mismatch");
      $display("TC6 -- br_type coverage: %s",
               (tc6_fail == 0) ? "PASS" : "FAIL");
    end

    // ----------------------------------------------------------------
    // TC7 -- carry bit
    // ----------------------------------------------------------------
    begin
      // same-block: pc and target share bits [39:5]
      logic [VA_WIDTH-1:0] pc_same, tgt_same;
      logic [VA_WIDTH-1:0] pc_diff, tgt_diff;
      pc_same  = 40'h0000_5000; // set=(0x5000>>2)&63
      tgt_same = 40'h0000_5010; // same 32B block ([39:5] equal)
      pc_diff  = 40'h0000_5040; // different set to avoid collision
      tgt_diff = 40'h0000_6000; // different 32B block
      write_entry(pc_same, DIRECT_UNC, tgt_same, 1'b0, 1'b0);
      write_entry(pc_diff, DIRECT_UNC, tgt_diff, 1'b0, 1'b1);
      pred_pc = pc_same;
      @(posedge clk); #1;
      check("TC7a", pred1[0].valid == 1'b1,   "TC7a: same-block miss");
      check("TC7b", pred1[0].carry == 1'b0,   "TC7b: carry should be 0");
      pred_pc = pc_diff;
      @(posedge clk); #1;
      check("TC7c", pred1[0].valid == 1'b1,   "TC7c: diff-block miss");
      check("TC7d", pred1[0].carry == 1'b1,   "TC7d: carry should be 1");
      $display("TC7 -- carry bit: %s",
               (fail_count == 0) ? "PASS" : "FAIL");
    end

    // ----------------------------------------------------------------
    // TC8 -- Update to existing entry (overwrite)
    // ----------------------------------------------------------------
    begin
      logic [VA_WIDTH-1:0] pc_u, tgt1_u, tgt2_u;
      pc_u   = 40'h0000_7000;
      tgt1_u = 40'h0000_8000;
      tgt2_u = 40'h0000_9000;
      write_entry(pc_u, COND, tgt1_u, 1'b1, 1'b0);
      write_entry(pc_u, DIRECT_UNC, tgt2_u, 1'b0, 1'b0);
      pred_pc = pc_u;
      @(posedge clk); #1;
      check("TC8a", pred1[0].valid   == 1'b1,       "TC8a: miss");
      check("TC8b", pred1[0].target  == tgt2_u,     "TC8b: target wrong");
      check("TC8c", pred1[0].br_type == DIRECT_UNC, "TC8c: type wrong");
      check("TC8d", pred1[0].br_taken == 1'b0,       "TC8d: taken wrong");
      $display("TC8 -- Overwrite: %s",
               (fail_count == 0) ? "PASS" : "FAIL");
    end

    // ----------------------------------------------------------------
    // TC9 -- NUM_PRED_SLOTS=2 dual prediction
    //   Use dut2. Reset dut2 by toggling rstn briefly.
    // ----------------------------------------------------------------
    begin
      logic [VA_WIDTH-1:0] pc_a9, pc_b9, tgt_a9, tgt_b9;
      int tc9_fail;
      tc9_fail = 0;
      // Reset dut2 (rstn is shared)
      rstn = 0;
      @(posedge clk); #1;
      rstn = 1;
      @(posedge clk); #1;

      // pc_a9 in one 32B block, pc_b9 = pc_a9 + 32 (next block)
      pc_a9  = 40'h0000_A000;
      pc_b9  = pc_a9 + 40'd32;
      tgt_a9 = 40'h0000_B000;
      tgt_b9 = 40'h0000_C000;

      // Write via dut2 upd[0] and upd[1]
      upd2[0].valid    = 1'b1;
      upd2[0].pc       = pc_a9;
      upd2[0].br_type  = COND;
      upd2[0].target   = tgt_a9;
      upd2[0].br_taken = 1'b1;
      upd2[0].carry    = 1'b0;
      upd2[1].valid    = 1'b1;
      upd2[1].pc       = pc_b9;
      upd2[1].br_type  = DIRECT_UNC;
      upd2[1].target   = tgt_b9;
      upd2[1].br_taken = 1'b0;
      upd2[1].carry    = 1'b0;
      @(posedge clk); #1;
      upd2[0].valid = 1'b0;
      upd2[1].valid = 1'b0;

      // Present pred_pc=pc_a9; slot 0 -> pc_a9, slot 1 -> pc_a9+32
      pred_pc2 = pc_a9;
      @(posedge clk); #1;
      if (!pred2[0].valid || pred2[0].target != tgt_a9) tc9_fail++;
      if (!pred2[1].valid || pred2[1].target != tgt_b9) tc9_fail++;
      check("TC9", tc9_fail == 0, "Dual-slot prediction mismatch");
      $display("TC9 -- Dual prediction: %s",
               (tc9_fail == 0) ? "PASS" : "FAIL");
    end

    // ----------------------------------------------------------------
    // TC10 -- Read-during-write same set
    //   Cycle N: issue upd for new PC in set S; pred_pc also maps S.
    //   Expect pred[0] in cycle N is pre-update (no bypass).
    //   Expect new entry visible in cycle N+1.
    // ----------------------------------------------------------------
    begin
      // Re-assert reset to get a clean dut1 state
      rstn = 0;
      @(posedge clk); #1;
      rstn = 1;
      @(posedge clk); #1;

      begin
        logic [VA_WIDTH-1:0] pc_rdw, tgt_rdw;
        // Place in set 3: pc[7:2]=3 -> pc=0x00C
        pc_rdw  = 40'h0000_000C;
        tgt_rdw = 40'h0000_F000;
        // Cycle N: assert pred_pc and upd simultaneously.
        // Check pred BEFORE posedge: reflects pre-update mem (miss).
        // After posedge: write is committed; pred sees new entry.
        pred_pc          = pc_rdw;
        upd1[0].valid    = 1'b1;
        upd1[0].pc       = pc_rdw;
        upd1[0].br_type  = COND;
        upd1[0].target   = tgt_rdw;
        upd1[0].br_taken = 1'b1;
        upd1[0].carry    = 1'b0;
        // TC10a: combinational pred reads pre-update registered mem.
        // We are between clock edges; mem has not been written yet.
        check("TC10a", pred1[0].valid == 1'b0,
              "TC10a: pre-update bypass occurred unexpectedly");
        // Let posedge fire: write committed to mem.
        @(posedge clk); #1;
        upd1[0].valid = 1'b0;
        // TC10b/TC10c: combinational pred reads updated mem (cycle N+1).
        check("TC10b", pred1[0].valid  == 1'b1,  "TC10b: miss after write");
        check("TC10c", pred1[0].target == tgt_rdw,"TC10c: target wrong");
        $display("TC10 -- Read-during-write: %s",
                 (fail_count == 0) ? "PASS" : "FAIL");
      end
    end

    // ----------------------------------------------------------------
    // Final verdict
    // ----------------------------------------------------------------
    if (fail_count == 0) begin
      $display("ALL TESTS PASSED");
      $finish(0);
    end else begin
      $display("FAILURES DETECTED: %0d", fail_count);
      $finish(1);
    end
  end

endmodule : tb
