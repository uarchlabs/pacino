// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd21_commit.svh -- FD-21 Commit
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     the commit pointer advancing and the RAS commit stack
//   program   tb_fe_top calls: main calls f, f calls g then h, each
//             returns, six passes
//   waveform  the FTQ commit pointer, the RAS commit stack
//   trace     commits
//   proof     the FTQ commit pointer advances (in at least 16 cycles),
//             and the RAS commit stack changes
// ===================================================================

  task automatic prog_fd21();
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] g;
    logic [VA_WIDTH-1:0] h;
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] lm;
    logic [VA_WIDTH-1:0] lf1;
    logic [VA_WIDTH-1:0] lf2;
    int                  e0;
    begin_scen("fd21_commit", 1'b0);
    f = RESET_VECTOR + VA_WIDTH'('h800);
    g = RESET_VECTOR + VA_WIDTH'('hA00);
    h = RESET_VECTOR + VA_WIDTH'('hC00);
    W.mixed(3);
    top = W.wp;
    e0  = W.ne;
    while (W.wp != RESET_VECTOR + VA_WIDTH'('h1C)) W.i16();
    lm  = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, f);                          // main calls f
    W.mixed(3);
    while (W.wp != f + VA_WIDTH'('h1C)) W.i16();
    lf1 = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, g);                          // f calls g
    W.mixed(2);
    W.ret(lf1);                              // g returns
    W.mixed(1);
    while (W.wp != f + VA_WIDTH'('h3C)) W.i16();
    lf2 = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, h);                          // f calls h
    W.mixed(2);
    W.ret(lf2);                              // h returns
    W.mixed(1);
    W.ret(lm);                               // f returns to main
    W.mixed(1);
    W.loop_br(top);
    W.rep_iter(e0, 6);
    W.mixed(3);
    demo_go(40000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd21_commit.md, in table order. The
  // epilogue after the back edge is +0x26. The backend's commit
  // watermark and redirect are driven by the testbench: late. The
  // commit walk and the RAS commit stack are design registers.
  // =================================================================
  function automatic void fd21_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_commit_watermark_from_the_backend", EV_WINDOW, 1);
    evt_def("the_commit_pointer_first_moves", EV_WINDOW);
    evt_def("first_RAS_commit_of_a_call", EV_WINDOW);
    evt_def("the_commit_stack_reaches_depth_2", EV_WINDOW);
    evt_def("first_RAS_commit_of_a_return", EV_WINDOW);
    evt_def("back_edge_falls_through", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd21_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    e[1] = bkend_ftq_commit_val;
    e[2] = dut.u_ftq.w_commit_step_val;
    e[3] = dut.u_bpu.w_ras_commit_val &&
           (dut.ras_commit_br_type == DIRECT_CALL);
    e[4] = dut.u_bpu.u_ras.csp == 2;
    e[5] = dut.u_bpu.w_ras_commit_val && (dut.ras_commit_br_type == RETURN);
    e[6] = ev_redir(RESET_VECTOR + VA_WIDTH'('h26));
    return e;
  endfunction
