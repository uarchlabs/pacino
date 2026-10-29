// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd05_p3_override.svh -- FD-5 p3 override
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     SC reversing the TAGE direction and the p3 redirect
//   program   tb_fe_top hist: two conditionals whose outcomes depend on
//             history (one alternates, one is taken every third pass),
//             96 passes; TAGE predicts them weakly while it learns and
//             SC reverses some of its directions
//   waveform  TAGE p2, SC p3, bpu_redir_p3
//   trace     p3 redirects whose slot SC decided
//   proof     a p3 redirect the FTQ accepted whose slot has pred_src
//             PRED_SC
// ===================================================================

  task automatic prog_fd05();
    logic [VA_WIDTH-1:0] top;
    begin_scen("fd05_p3_override", 1'b0);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 96; it++) begin
      W.wp = top;
      W.mixed(2);
      W.cskip((it % 2) == 1, 2);              // A
      W.mixed(1);
      W.cskip((it % 3) == 2, 2);              // B
      W.mixed(1);
      W.bcc(it != 95, top);
    end
    W.mixed(3);
    demo_go(80000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd05_p3_override.md, in table order. top
  // is 0x8000_0008, A at position 3; B's PC 0x8000_001A, at position 9
  // from top; B's target 0x8000_0024; the epilogue 0x8000_002A. The
  // backend's redirect is driven by the testbench: late.
  // =================================================================
  localparam logic [VA_WIDTH-1:0] FD05_TOP = RESET_VECTOR + VA_WIDTH'('h08);

  // An accepted p3 redirect from slot 0, SC-decided (as the monitor's
  // n_redir_p3_sc), to pc.
  function automatic logic fd05_sc(input logic [VA_WIDTH-1:0] pc);
    return dut.u_ftq.w_ok_redir_p3 && dut.bpu_slot_val_p3 &&
           (dut.bpu_slot_idx_p3 == dut.bpu_redir_idx_p3) &&
           dut.bpu_redir_p3[0].valid && (dut.bpu_redir_p3[0].target_pc == pc) &&
           (dut.bpu_slot_p3[0].pred_src == PRED_SC);
  endfunction

  function automatic void fd05_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_p3_redirect_from_an_SC", EV_WINDOW);
    evt_def("A_reversed_to_not_taken_before", EV_WINDOW);
    evt_def("the_split", EV_WINDOW);
    evt_def("A_reversed_to_not_taken_after", EV_WINDOW);
    evt_def("last_p3_redirect_from_an_SC", EV_WINDOW, 0, 1);
    evt_def("back_edge_falls_through", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd05_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    // B reversed to taken, to its target.
    e[1] = fd05_sc(RESET_VECTOR + VA_WIDTH'('h24));
    // A reversed to not taken, to top + 0x20 before the split.
    e[2] = fd05_sc(FD05_TOP + VA_WIDTH'('h20)) &&
           (dut.u_bpu.r_pc_p3 == FD05_TOP);
    // The FTB update for top that splits its entry at B, position 9.
    e[3] = dut.u_bpu.u_ftb.u_ftb_cntrl.upd_active &&
           (dut.ftb_upd_pc_u0 == FD05_TOP) && (dut.ftb_upd_pos_u0 == 9) &&
           dut.u_bpu.u_ftb.u_ftb_cntrl.upd_split;
    // ... and after it, to B's PC.
    e[4] = fd05_sc(RESET_VECTOR + VA_WIDTH'('h1A)) &&
           (dut.u_bpu.r_pc_p3 == FD05_TOP);
    e[5] = fd05_sc(dut.bpu_redir_p3[0].target_pc);
    e[6] = ev_redir(RESET_VECTOR + VA_WIDTH'('h2A));
    return e;
  endfunction
