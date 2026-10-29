// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd03_two_branch.svh -- FD-3 Two branches in one block
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     both prediction slots used by one block
//   program   tb_fe_top twocond: two blocks, each alone in its 32-byte
//             region with two conditionals, in a loop of 24
//   waveform  uBTB p1 and FTB p2 slot outputs, both slots
//   trace     a block predicted with two slots
//   proof     a p1 prediction or a p2 slot group the FTQ accepted with
//             both slots valid
// ===================================================================

  task automatic prog_fd03();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] x;
    logic [VA_WIDTH-1:0] y;
    logic [VA_WIDTH-1:0] back;
    begin_scen("fd03_two_branch", 1'b0);
    x = RESET_VECTOR + VA_WIDTH'('h400);
    y = RESET_VECTOR + VA_WIDTH'('h440);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 24; it++) begin
      W.wp = top;
      W.i16();
      W.jal(5'd0, x);
      back = top + VA_WIDTH'(6);
      W.i16();
      W.cskip(1'b0, 1);                     // X c1, never taken
      W.cskip(1'b1, 1);                     // X c2, always taken
      W.i16();
      W.jal(5'd0, y);
      W.i16();
      W.cskip((it % 2) == 1, 1);            // Y c1, alternates
      W.cskip(1'b0, 1);                     // Y c2, never taken
      W.i16();
      W.jal(5'd0, back);
      W.mixed(1);
      W.bcc(it != 23, top);
    end
    W.mixed(3);
    demo_go(40000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd03_two_branch.md, in table order. X is
  // 0x8000_0400 and Y 0x8000_0440, each with conditionals at positions
  // 1 and 4; the epilogue after the back edge is top + 12, 0x8000_0014.
  // The backend's redirect is driven by the testbench: late.
  // =================================================================
  localparam logic [VA_WIDTH-1:0] FD03_X = RESET_VECTOR + VA_WIDTH'('h400);
  localparam logic [VA_WIDTH-1:0] FD03_Y = RESET_VECTOR + VA_WIDTH'('h440);

  // An accepted p2 group for block pc with conditionals at 1 and 4.
  function automatic logic fd03_two_p2(input logic [VA_WIDTH-1:0] pc);
    return dut.u_ftq.w_ok_slot_p2 && dut.bpu_slot_val_p2 &&
           (dut.u_bpu.r_pc_p2 == pc) &&
           dut.bpu_slot_p2[0].slot_valid && (dut.bpu_slot_p2[0].pos == 1) &&
           (dut.bpu_slot_p2[0].br_type == COND) &&
           dut.bpu_slot_p2[S1].slot_valid && (dut.bpu_slot_p2[S1].pos == 4) &&
           (dut.bpu_slot_p2[S1].br_type == COND) && (NUM_PRED_SLOTS > 1);
  endfunction

  function automatic void fd03_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_p1_prediction_for_X_with", EV_WINDOW);
    evt_def("first_p2_group_for_X_with", EV_WINDOW);
    evt_def("first_p2_group_for_Y_with", EV_WINDOW);
    evt_def("back_edge_falls_through", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd03_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    // An accepted p1 prediction for X with both slots valid (as the
    // monitor's n_two_p1, for X).
    e[1] = dut.u_ftq.w_ok_pred_p1 && (dut.u_bpu.r_pc_p1 == FD03_X) &&
           dut.bpu_pred_slot_p1[0].slot_valid &&
           dut.bpu_pred_slot_p1[S1].slot_valid && (NUM_PRED_SLOTS > 1);
    e[2] = fd03_two_p2(FD03_X);
    e[3] = fd03_two_p2(FD03_Y);
    e[4] = ev_redir(RESET_VECTOR + VA_WIDTH'('h14));
    return e;
  endfunction
