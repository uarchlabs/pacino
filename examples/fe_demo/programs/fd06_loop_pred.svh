// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd06_loop_pred.svh -- FD-6 Loop predictor
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     the loop predictor taking over a loop and predicting its
//             exit
//   program   tb_fe_top lp: an inner loop of 10 inside an outer loop of
//             16, so the inner loop branch has the same trip count every
//             time
//   waveform  the loop predictor entry, the p1 mux, the loop exit
//   trace     LP predictions; the exit
//   proof     a retired loop exit (not taken) whose FTQ entry's final
//             slot for it has pred_src PRED_LOOP and predicts not taken
// ===================================================================

  task automatic prog_fd06();
    logic [VA_WIDTH-1:0] otop;
    logic [VA_WIDTH-1:0] itop;
    begin_scen("fd06_loop_pred", 1'b0);
    W.mixed(3);
    otop = W.wp;
    for (int o = 0; o < 16; o++) begin
      W.wp = otop;
      W.mixed(2);
      itop = W.wp;
      for (int i = 0; i < 10; i++) begin
        W.wp = itop;
        W.mixed(3);
        W.bcc(i != 9, itop);
      end
      W.mixed(2);
      W.bcc(o != 15, otop);
    end
    W.mixed(3);
    demo_go(80000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd06_loop_pred.md, in table order. I, the
  // inner loop's branch, is at 0x8000_0016 in the block from itop,
  // 0x8000_000E; its exit falls through to 0x8000_001A; the epilogue
  // after O is 0x8000_0024. One slot. The backend's redirects are
  // driven by the testbench: late.
  // =================================================================
  localparam logic [VA_WIDTH-1:0] FD06_ITOP = RESET_VECTOR + VA_WIDTH'('h0E);

  function automatic void fd06_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_inner_exit_mispredicted", EV_WINDOW, 1);
    evt_def("the_loop_predictor_learns_the_trip", EV_WINDOW);
    evt_def("confidence_reaches_3", EV_WINDOW);
    evt_def("first_p1_slot_from_the_loop", EV_WINDOW);
    evt_def("the_loop_predictor_first_trusted_at", EV_WINDOW);
    evt_def("first_exit_predicted_not_taken", EV_WINDOW);
    evt_def("outer_loop_falls_through", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd06_evt_now();
    logic [EV_MAX-1:0] e;
    lp_pred_t          lp;
    e    = '0;
    lp   = dut.u_bpu.w_lp_pred_p2[0];
    e[0] = ev_p0(RESET_VECTOR);
    e[1] = ev_redir(RESET_VECTOR + VA_WIDTH'('h1A));
    e[2] = lp.lp_past_itr == 8;
    e[3] = lp.lp_conf == 3;
    e[4] = dut.u_ftq.w_ok_pred_p1 && dut.bpu_pred_slot_p1[0].slot_valid &&
           (dut.bpu_pred_slot_p1[0].pred_src == PRED_LOOP);
    e[5] = lp.lp_pred_is_loop && dut.bpu_slot_p2[0].slot_valid &&
           (dut.bpu_slot_p2[0].pred_src == PRED_LOOP);
    // I's slot at p2 from the loop predictor, not taken: the exit.
    e[6] = dut.u_bpu.r_val_p2 && (dut.u_bpu.r_pc_p2 == FD06_ITOP) &&
           dut.bpu_slot_p2[0].slot_valid && !dut.bpu_slot_p2[0].taken &&
           (dut.bpu_slot_p2[0].pred_src == PRED_LOOP);
    e[7] = ev_redir(RESET_VECTOR + VA_WIDTH'('h24));
    return e;
  endfunction
