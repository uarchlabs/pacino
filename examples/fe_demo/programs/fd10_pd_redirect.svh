// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd10_pd_redirect.svh -- FD-10 Predecode redirect
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     a JAL the predictors did not report, found at F3
//   program   tb_fe_top jals: a chain of twelve JALs to distinct blocks,
//             run three times; on the first pass none is known to the
//             uBTB or FTB
//   waveform  IFU F3, the predecode writeback, the FTQ redirect, the IFU
//             flush
//   trace     predecode redirects
//   proof     a predecode redirect the FTQ took (no backend redirect
//             that cycle)
// ===================================================================

  task automatic prog_fd10();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] t;
    begin_scen("fd10_pd_redirect", 1'b0);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 3; it++) begin
      W.wp = top;
      W.mixed(1);
      for (int k = 0; k < 12; k++) begin
        t = RESET_VECTOR + VA_WIDTH'('h200 + k * 'h60);
        W.jal(5'd0, t);
        W.mixed(2);
      end
      W.jal(5'd0, top + VA_WIDTH'('h100));
      W.wp = top + VA_WIDTH'('h100);
      W.mixed(1);
      W.bcc(it != 2, top);
    end
    W.mixed(3);
    demo_go(40000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd10_pd_redirect.md, in table order. T(0)
  // is 0x8000_0200; the jal of T(11) targets 0x8000_0108; the halt jal
  // is at 0x8000_0116; the epilogue after the back edge 0x8000_010E.
  // The predecode redirect is the design's (it changes at the edge);
  // the backend's redirects are driven by the testbench: late.
  // =================================================================
  function automatic void fd10_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_predecode_redirect", EV_WINDOW);
    evt_def("the_13th_predecode_redirect", EV_WINDOW);
    evt_def("a_predecode_redirect_to_0x8000_0116", EV_WINDOW);
    evt_def("the_back_edge_mispredicted", EV_WINDOW, 1);
    evt_def("last_predecode_redirect", EV_WINDOW, 0, 1);
    evt_def("back_edge_falls_through", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd10_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    e[1] = ev_pd_redir(RESET_VECTOR + VA_WIDTH'('h200));
    e[2] = ev_pd_redir(RESET_VECTOR + VA_WIDTH'('h108));
    // The halt's predecode redirect, whatever the backend does.
    e[3] = dut.u_ftq.w_pd_redir_val &&
           (dut.u_ftq.w_pd_redir_pc == RESET_VECTOR + VA_WIDTH'('h116));
    e[4] = ev_redir(RESET_VECTOR + VA_WIDTH'('h08));
    // The jal at top + 2 found again, to T(0).
    e[5] = ev_pd_redir(RESET_VECTOR + VA_WIDTH'('h200));
    e[6] = ev_redir(RESET_VECTOR + VA_WIDTH'('h10E));
    return e;
  endfunction
