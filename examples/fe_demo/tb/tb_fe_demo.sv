// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// The front-end demonstration testbench (DOC-001). Each run is one
// scenario of planning/showcase/fe_demo_scenarios.md, FD-1 to FD-21,
// named by +SCEN=<name>; the testbench is
// planning/testbenches/fe_demo_tb_decisions.md.
//
// A DEMONSTRATION, NOT A VERIFICATION TESTBENCH (FDT intro, FD-0c).
// It runs fe_top with the walker beside it (FDT-3) on the models
// tb_fe_top uses, included from rtl/core/frontend/fe_top/tb/models
// (FDT-4): the DUT and walker hookup, the program writer, the memory
// model, the in-order backend and the CSR setup through csr_tb_pkg.
// The backend still compares every retired instruction with the
// program's executed stream, so a run whose stream does not retire is
// reported, but nothing else is checked: each run ends by evaluating
// its scenario's proof, a condition on RTL signals that shows the
// behaviour occurred, and prints one line,
//   DEMO PASS <scenario>: <what the proof read> (cycles <n>)
// or DEMO FAIL, which exits non-zero (FDT-10).
//
// PLUSARGS
//   +SCEN=<name>   the scenario (fdNN_<name>, the make target names)
//   +FST=<file>    write the waveform there (FDT-11); none without it
//   +TRACE         the shared backend's RETIRE / MISP lines
//   +TAGE_FAST_INIT=1 +ITTAGE_FAST_INIT=1 +SC_FAST_INIT=1
//                  the fast SRAM init, every scenario but FD-1 (FDT-7);
//                  the Makefile passes them
//
// FILES
//   tb/fe_demo_mon.svh     the monitors the proofs read, and the
//                          backend's hooks
//   tb/fe_demo_lib.svh     the start and end of a run, the address map
//                          and shared program pieces
//   programs/fdNN_*.svh    one program per scenario, its FD-0b entry in
//                          its header
//   tb/fe_demo_proofs.svh  the proofs
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;
import decode_pkg::*;
import csr_pkg::*;

module tb;

  `include "fe_tb_dut.svh"
  `include "fe_tb_writer.svh"
  `include "fe_tb_mem.svh"
  `include "fe_tb_be_state.svh"
  `include "fe_demo_mon.svh"
  `include "fe_tb_backend.svh"
  `include "fe_tb_csr.svh"
  `include "fe_demo_lib.svh"

  `include "fd01_reset_init.svh"
  `include "fd02_steady.svh"
  `include "fd03_two_branch.svh"
  `include "fd04_p2_override.svh"
  `include "fd05_p3_override.svh"
  `include "fd06_loop_pred.svh"
  `include "fd07_calls_returns.svh"
  `include "fd08_indirect.svh"
  `include "fd09_tage.svh"
  `include "fd10_pd_redirect.svh"
  `include "fd11_be_mispredict.svh"
  `include "fd12_training.svh"
  `include "fd13_l1i.svh"
  `include "fd14_translation.svh"
  `include "fd15_faults.svh"
  `include "fd16_page_cross.svh"
  `include "fd17_rvc.svh"
  `include "fd18_uncached.svh"
  `include "fd19_fencei_cbo.svh"
  `include "fd20_backpressure.svh"
  `include "fd21_commit.svh"

  `include "fe_demo_proofs.svh"

  // The scenarios, in FD order (FDT-9).
  string scens [0:20] = '{"fd01_reset_init", "fd02_steady",
                          "fd03_two_branch", "fd04_p2_override",
                          "fd05_p3_override", "fd06_loop_pred",
                          "fd07_calls_returns", "fd08_indirect",
                          "fd09_tage", "fd10_pd_redirect",
                          "fd11_be_mispredict", "fd12_training",
                          "fd13_l1i", "fd14_translation", "fd15_faults",
                          "fd16_page_cross", "fd17_rvc", "fd18_uncached",
                          "fd19_fencei_cbo", "fd20_backpressure",
                          "fd21_commit"};

  // Build and run one scenario's program. 0 for an unknown name.
  function automatic logic known(input string nm);
    foreach (scens[i]) if (scens[i] == nm) return 1'b1;
    return 1'b0;
  endfunction

  task automatic run_scen(input string nm);
    case (nm)
      "fd01_reset_init":    prog_fd01();
      "fd02_steady":        prog_fd02();
      "fd03_two_branch":    prog_fd03();
      "fd04_p2_override":   prog_fd04();
      "fd05_p3_override":   prog_fd05();
      "fd06_loop_pred":     prog_fd06();
      "fd07_calls_returns": prog_fd07();
      "fd08_indirect":      prog_fd08();
      "fd09_tage":          prog_fd09();
      "fd10_pd_redirect":   prog_fd10();
      "fd11_be_mispredict": prog_fd11();
      "fd12_training":      prog_fd12();
      "fd13_l1i":           prog_fd13();
      "fd14_translation":   prog_fd14();
      "fd15_faults":        prog_fd15();
      "fd16_page_cross":    prog_fd16();
      "fd17_rvc":           prog_fd17();
      "fd18_uncached":      prog_fd18();
      "fd19_fencei_cbo":    prog_fd19();
      "fd20_backpressure":  prog_fd20();
      "fd21_commit":        prog_fd21();
      default: ;
    endcase
  endtask

  // =================================================================
  initial begin
    string scen;
    string fst;
    string msg;
    logic  ok;
    logic  ran;
    if (!$value$plusargs("SCEN=%s", scen) || !known(scen)) begin
      $display("tb_fe_demo: +SCEN=<name> is required; scenarios:");
      foreach (scens[i]) $display("  %s", scens[i]);
      $fatal(1, "DEMO FAIL: no scenario");
    end
    if ($value$plusargs("FST=%s", fst)) begin
      $dumpfile(fst);
      $dumpvars(0, tb);
    end
    run_scen(scen);
    // The stream must have retired whole for the run to show anything.
    ran = (ep == W.ne) && (n_err == 0) && (n_retired == W.ne);
    ok  = proof(scen, msg);
    if (!ran)
      msg = $sformatf("the stream did not retire (%0d of %0d, %0d errors); %s",
                      ep, W.ne, n_err, msg);
    if (ran && ok) begin
      $display("DEMO PASS %s: %s (cycles %0d)", scen, msg, cyc_run);
      $finish;
    end else begin
      $display("DEMO FAIL %s: %s (cycles %0d)", scen, msg, cyc_run);
      $fatal(1, "DEMO FAIL %s", scen);
    end
  end

  initial begin
    #30000000;
    $fatal(1, "DEMO FAIL: timeout");
  end

endmodule : tb
