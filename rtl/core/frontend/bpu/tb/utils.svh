// ===================================================================
// FILE:    utils.svh
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Shared utility tasks for manual testbenches. Included inside the
// module scope of tb_<dut>_manual.sv. References module-scope
// signals: clk, rstn, test_name.
// ===================================================================
task automatic tb_msg(
  input string prefix, input string msg, input int t = 0
);
  if (t) $display("-%0s: %t : %s", prefix, $time, msg);
  else   $display("-%0s: %s", prefix, msg);
endtask
// -------------------------------------------------------------------
task automatic tb_info(input string msg, input int t = 0);
  tb_msg("I", msg, t);
endtask

// -------------------------------------------------------------------
task automatic tb_warn(input string msg, input int t = 0);
  tb_msg("W", msg, t);
endtask

// -------------------------------------------------------------------
task automatic tb_error(input string msg, input int t = 0);
  tb_msg("E", msg, t);
endtask

// -------------------------------------------------------------------
// -------------------------------------------------------------------
task automatic tb_pf(input string testname, input int errs);
  if (errs > 0)
    tb_error({testname, " : FAIL"});
  else
    tb_info({testname, " : PASS"});
endtask
// -------------------------------------------------------------------
// -------------------------------------------------------------------
task automatic start_test(input string name);
  test_name = name;
  tb_info({"START ", name});
endtask

// -------------------------------------------------------------------
task automatic stop_test(input string name, input int errs);
  tb_info({"STOP  ", name});
//  tb_pf(name, errs);
  test_name = "";
endtask

// -------------------------------------------------------------------
task automatic assert_reset(input int n);
  rstn = 1'b0;
  repeat (n) @(posedge clk);
  rstn = 1'b1;
endtask

task automatic terminate();
  $finish;
endtask
