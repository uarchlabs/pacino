// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd01_reset_init.svh -- FD-1 Reset and SRAM initialization
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     the full init walk of the predictor tables, ending with
//             every predictor ready
//   program   a loop of 128 passes over 7 instructions, run after the
//             last ready; reset without the fast-init options (FDT-7:
//             this scenario alone)
//   waveform  the TAGE, ITTAGE and SC sram_init walks and readies, the
//             RAS reset done, the first p0 request and p1 prediction
//   trace     none until the trace writer (FDT-U1)
//   proof     as FD-1 gives it: each of the TAGE, ITTAGE and SC readies
//             is seen low after reset and then rises, and the first p1
//             prediction the FTQ accepts is no earlier than the last of
//             them. The first response and update of each queued
//             predictor are reported beside it
//
// DOC-001 found the FTQ predicting from the first cycle after reset,
// before the readies rose. BP-137 made ftq_npc hold its p0 request
// until all three readies are high; the proof is met since.
// ===================================================================

  // Passes of the loop. The p0 request is held for the whole walk, so
  // the loop runs only after the last ready; nothing in the loop
  // depends on the walk, so a short loop is enough.
  localparam int FD01_ITERS = 128;

  task automatic prog_fd01();
    logic [VA_WIDTH-1:0] top;
    begin_scen("fd01_reset_init", 1'b0);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < FD01_ITERS; it++) begin
      W.wp = top;
      W.mixed(6);
      W.bcc(it != FD01_ITERS - 1, top);
    end
    W.mixed(3);
    demo_go(40000);
  endtask

  // The console line (console(), tb_fe_demo.sv): the verdict and the
  // cycle count only; the full result line stays in the log.
  function automatic void fd01_console(input logic pass, input int c);
    $fdisplay(FD_STDERR, "-%s: fd01_reset_init : %s : cyc = %0d",
              pass ? "I" : "E", pass ? "PASS" : "FAIL", c);
  endfunction

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd01_reset_init.md, in table order. Every
  // condition is on registers of the design or logic they drive.
  // =================================================================
  function automatic void fd01_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("the_three_table_walks_start_at", EV_WINDOW);
    evt_def("ITTAGE_ready", EV_WINDOW);
    evt_def("SC_ready", EV_WINDOW);
    evt_def("TAGE_ready", EV_WINDOW);
    evt_def("first_p1_prediction_the_FTQ_accepts", EV_WINDOW);
    evt_def("first_TAGE_and_ITTAGE_responses_at", EV_WINDOW);
    evt_def("first_SC_response_at_p3", EV_WINDOW);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd01_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    // Out of reset with the p0 request withheld.
    e[0] = !dut.ftq_pred_val_p0 && dut.u_ftq.u_npc.w_hold;
    // Each sram_init in INIT (2'b10) writing address 0, and the RAS
    // reset done.
    e[1] = (2'(dut.u_bpu.u_tage.u_sram_init.state) == 2'b10) &&
           (dut.u_bpu.u_tage.u_sram_init.waddr == '0) &&
           (2'(dut.u_bpu.u_ittage.u_sram_init.state) == 2'b10) &&
           (dut.u_bpu.u_ittage.u_sram_init.waddr == '0) &&
           (2'(dut.u_bpu.u_sc.u_sram_init.state) == 2'b10) &&
           (dut.u_bpu.u_sc.u_sram_init.waddr == '0) &&
           dut.u_bpu.u_ras.ras_rst_done;
    e[2] = dut.bpu_ittage_rdy;
    e[3] = dut.bpu_sc_ready;
    // The last ready, with the first p0 request in the same cycle.
    e[4] = dut.bpu_tage_rdy && dut.ftq_pred_val_p0;
    e[5] = dut.u_ftq.w_ok_pred_p1;
    e[6] = (dut.u_bpu.w_tage_pred_rdy_p2 != '0) &&
           (dut.u_bpu.w_ittage_pred_rdy_p2 != '0);
    e[7] = dut.u_bpu.w_sc_pred_rdy_p3 != '0;
    return e;
  endfunction
