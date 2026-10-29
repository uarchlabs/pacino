// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd04_p2_override.svh -- FD-4 p2 override
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     the FTB disagreeing with the uBTB and the p2 redirect
//   program   tb_fe_top ftbonly: eight blocks 0x800 apart chained by
//             taken conditionals; they share one 4-way uBTB set, so the
//             uBTB holds at most four of them while the FTB holds all
//             eight
//   waveform  uBTB p1, FTB p2, bpu_redir_p2, the FTQ rewrite
//   trace     p2 redirects
//   proof     a p2 redirect the FTQ accepted
// ===================================================================

  task automatic prog_fd04();
    logic [VA_WIDTH-1:0] b [0:7];
    logic [VA_WIDTH-1:0] ex_pc;
    begin_scen("fd04_p2_override", 1'b0);
    for (int k = 0; k < 8; k++)
      b[k] = RESET_VECTOR + VA_WIDTH'('h1000 + k * 'h800);
    W.mixed(3);
    W.jal(5'd0, b[0]);
    for (int it = 0; it < 16; it++) begin
      for (int k = 0; k < 7; k++) begin
        W.wp = b[k];
        W.mixed(2);
        W.bcc(1'b1, b[k+1]);
      end
      W.wp = b[7];
      W.mixed(1);
      ex_pc = W.wp + VA_WIDTH'(8);
      W.bcc(it == 15, ex_pc);                 // exit on the last pass
      if (it != 15) W.jal(5'd0, b[0]);
      else          W.d_jal_fill();
    end
    W.mixed(3);
    demo_go(40000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd04_p2_override.md, in table order.
  // b[k] = 0x8000_1000 + k * 0x800; b[7] is 0x8000_4800, its jal at
  // 0x8000_4806 and the exit 0x8000_480A. The backend's redirect is
  // driven by the testbench: late.
  // =================================================================
  localparam logic [VA_WIDTH-1:0] FD04_B7 = RESET_VECTOR + VA_WIDTH'('h4800);

  function automatic void fd04_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_p2_redirect", EV_WINDOW);
    evt_def("first_p2_redirect_to_0x8000_480A", EV_WINDOW);
    evt_def("first_p2_redirect_to_the_jal", EV_WINDOW);
    evt_def("the_chain_exits", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd04_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    // b[0] redirected to b[1] (0x8000_1800) after a uBTB miss.
    e[1] = ev_p2_redir(RESET_VECTOR + VA_WIDTH'('h1800)) &&
           (dut.u_bpu.r_pc_p2 == RESET_VECTOR + VA_WIDTH'('h1000));
    e[2] = ev_p2_redir(FD04_B7 + VA_WIDTH'('hA)) &&
           (dut.u_bpu.r_pc_p2 == FD04_B7);
    e[3] = ev_p2_redir(FD04_B7 + VA_WIDTH'('h6)) &&
           (dut.u_bpu.r_pc_p2 == FD04_B7);
    e[4] = ev_redir(FD04_B7 + VA_WIDTH'('hA));
    return e;
  endfunction
