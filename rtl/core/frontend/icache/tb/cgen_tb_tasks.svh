// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      cgen_tb_tasks.svh
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// The task set every testbench includes. `include this INSIDE
// the module, not at file scope: the tasks name clk and rstn
// and they resolve to the including module's own signals.
//
// Nothing here knows a protocol. R-5 asks for the tasks used
// by both the unit testbenches and the top level testbench,
// and what those have in common is counting, timing and
// reporting, not signalling.
//--------------------------------------------------------------------

  int unsigned cg_pass;
  int unsigned cg_fail;
  int unsigned cg_cycle;
  int unsigned cg_limit;

  // cycle counter and the run away guard. The limit is a
  // simulation control, so it is a plusarg and never a
  // configuration field. D-41.
  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) cg_cycle <= 0;
    else      cg_cycle <= cg_cycle + 1;
  end

  task automatic cg_init();
    cg_pass  = 0;
    cg_fail  = 0;
    cg_limit = 100000;
    void'($value$plusargs("cg_limit=%d", cg_limit));
  endtask

  task automatic cg_tick(input int unsigned n = 1);
    for(int unsigned k = 0; k < n; k++) begin
      @(posedge clk);
    end
  endtask

  task automatic cg_check(input string what,
                          input logic  ok);
    if(ok) begin
      cg_pass = cg_pass + 1;
      $display("PASS %0t %s", $time, what);
    end else begin
      cg_fail = cg_fail + 1;
      $display("FAIL %0t %s", $time, what);
    end
  endtask

  task automatic cg_check_eq(input string what,
                             input longint unsigned got,
                             input longint unsigned exp);
    if(got == exp) begin
      cg_pass = cg_pass + 1;
      $display("PASS %0t %s got 0x%0h", $time, what, got);
    end else begin
      cg_fail = cg_fail + 1;
      $display("FAIL %0t %s got 0x%0h want 0x%0h",
               $time, what, got, exp);
    end
  endtask

  // Wait for a condition or give up. A timeout is a failure
  // and it is reported as one, it does not stop the run.
  //
  // SAMPLING IS ON THE NEGEDGE, and every wait in every
  // testbench does the same. The design is posedge clocked,
  // so at the negedge the cycle's values have settled and
  // are unambiguous. Sampling on the posedge races the
  // design's own updates and drops one cycle pulses, which
  // is exactly what a response valid is.
  task automatic cg_wait(input string what, ref logic sig);
    int unsigned spent;
    spent = 0;
    while(sig !== 1'b1 && spent < cg_limit) begin
      @(negedge clk);
      spent = spent + 1;
    end
    if(spent >= cg_limit) begin
      cg_fail = cg_fail + 1;
      $display("FAIL %0t timeout waiting for %s",
               $time, what);
    end
  endtask

  // Reset is released on a negedge, for the reason cg_wait
  // gives: a testbench that drives on the same edge the
  // design clocks on races the design's own updates.
  task automatic cg_reset(output logic r);
    r = 1'b0;
    repeat(8) @(negedge clk);
    r = 1'b1;
    @(negedge clk);
  endtask

  function automatic int unsigned cg_report(input string who);
    $display("----------------------------------------");
    $display("%s: %0d passed, %0d failed, %0d cycles",
             who, cg_pass, cg_fail, cg_cycle);
    if(cg_fail == 0) $display("%s: PASS", who);
    else             $display("%s: FAIL", who);
    $display("----------------------------------------");
    cg_report = cg_fail;
  endfunction
