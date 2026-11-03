// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd07_calls_returns.svh -- FD-7 Calls and returns
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     RAS push and pop, a return predicted from the stack,
//             recursion compression, a return-call
//   program   a loop of 8: main calls f1, f1 calls f2 (nested); then f
//             calls itself four deep from one call site (recursion);
//             then two coroutines switch by return-call (jalr x1, 0(x5)
//             and jalr x5, 0(x1))
//   waveform  the RAS pointers and top of stack, the p2 operations, the
//             commit stack
//   trace     pushes, pops, return-calls, recursion counts
//   proof     a retired return whose target the RAS supplied (pred_src
//             PRED_RAS, target right); a recursion count above 1 in the
//             speculative stack; a p2 RETURN_CALL operation
// ===================================================================

  task automatic prog_fd07();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] l;
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] b;
    logic [VA_WIDTH-1:0] b1;
    logic [VA_WIDTH-1:0] a1;
    logic [VA_WIDTH-1:0] lc;
    begin_scen("fd07_calls_returns", 1'b0);
    for (int k = 1; k <= 2; k++)
      W.fnv[k] = RESET_VECTOR + VA_WIDTH'('h400 + k * 'h100);
    f = RESET_VECTOR + VA_WIDTH'('h800);
    b = RESET_VECTOR + VA_WIDTH'('hA00);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 8; it++) begin
      W.wp = top;
      // Nested: main -> f1 -> f2.
      W.mixed(2);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, W.fnv[1]);
      W.emit_nest(1, 2, l);
      // Recursion: f calls itself four deep from one call site.
      W.mixed(1);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, f);
      W.emit_rec(f, 4, l);
      // Coroutines: L calls B with x5; B and A switch by return-call.
      W.mixed(1);
      lc = W.wp;
      W.jal(5'd5, b);                          // L
      W.mixed(2);                              // B prologue
      b1 = W.wp;
      W.jalr_to(5'd1, 5'd5, lc + VA_WIDTH'(4)); // B1: RETURN_CALL
      W.mixed(2);                              // A at L+4
      a1 = W.wp;
      W.jalr_to(5'd5, 5'd1, b1 + VA_WIDTH'(4)); // A1: RETURN_CALL
      W.mixed(2);                              // B at B1+4
      W.jalr_to(5'd0, 5'd5, a1 + VA_WIDTH'(4)); // B2: RETURN
      W.mixed(1);
      W.bcc(it != 7, top);
    end
    W.mixed(3);
    demo_go(80000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd07_calls_returns.md, in table order. One
  // slot. The backend's redirects are driven by the testbench: late. The
  // others are on registers of the design or logic they drive.
  // =================================================================
  // Retired instructions by the time the first RETURN_CALL of the
  // retired path reaches p2 (pass 1). The first two reach p2 at cyc 256
  // and 259, on a path the redirect at cyc 261 squashes, with fewer
  // retired.
  localparam int FD07_RC_RETIRED = 90;

  function automatic void fd07_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_RAS_commit", EV_WINDOW);
    evt_def("first_RAS_push_at_p2", EV_WINDOW);
    evt_def("entry_1s_recursion_count_reads_1", EV_WINDOW);
    evt_def("entry_1s_count_reaches_4", EV_WINDOW);
    evt_def("the_backend_corrects_the_bottom_branch", EV_WINDOW, 1);
    evt_def("first_p1_slot_from_the_RAS", EV_WINDOW);
    evt_def("first_return_predicted_from_the_RAS", EV_WINDOW);
    evt_def("first_retired_return_the_RAS_predicted", EV_WINDOW);
    evt_def("last_return_of_f_mispredicted", EV_WINDOW, 1);
    evt_def("first_pop_of_the_speculative_stack", EV_WINDOW);
    evt_def("first_RETURN_CALL_at_p2", EV_WINDOW);
    evt_def("first_RETURN_CALL_on_the_retired_path", EV_WINDOW);
    evt_def("first_pop_that_decrements_a_recursion", EV_WINDOW);
    evt_def("entry_1_is_reallocated", EV_WINDOW);
    evt_def("final_return_of_f_mispredicted", EV_WINDOW, 1, 1);
    evt_def("the_back_edge_falls_through", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd07_evt_now();
    logic [EV_MAX-1:0] e;
    logic              pop;
    logic              rc;
    e     = '0;
    pop   = dut.u_bpu.w_ras_pred_val_p2[0] &&
            (dut.u_bpu.w_br_type_p2[0] inside {RETURN, RETURN_CALL});
    rc    = dut.u_bpu.w_ras_pred_val_p2[0] &&
            (dut.u_bpu.w_br_type_p2[0] == RETURN_CALL);
    e[0]  = ev_p0(RESET_VECTOR);
    e[1]  = dut.u_bpu.w_ras_commit_val;
    e[2]  = dut.u_bpu.w_ras_pred_val_p2[0] &&
            (dut.u_bpu.w_br_type_p2[0] inside {DIRECT_CALL, INDIRECT_CALL});
    e[3]  = dut.u_bpu.u_ras.spec_rctr[1] == 1;
    e[4]  = dut.u_bpu.u_ras.spec_rctr[1] == 4;
    // The branch at f+6, taken at the bottom of the recursion.
    e[5]  = ev_redir(RESET_VECTOR + VA_WIDTH'('h810));
    e[6]  = dut.u_ftq.w_ok_pred_p1 && dut.bpu_pred_slot_p1[0].slot_valid &&
            (dut.bpu_pred_slot_p1[0].pred_src == PRED_RAS);
    e[7]  = dut.u_ftq.w_ok_slot_p2 && dut.bpu_slot_val_p2 &&
            dut.bpu_slot_p2[0].slot_valid &&
            (dut.bpu_slot_p2[0].pred_src == PRED_RAS);
    e[8]  = n_ras_ret_ok != 0;
    // f's last return, to main.
    e[9]  = ev_redir(RESET_VECTOR + VA_WIDTH'('h18));
    e[10] = dut.u_ftq.w_ok_slot_p2 && pop &&
            dut.u_bpu.w_ras_pop_valid_p2[0] &&
            !dut.u_bpu.u_ras.p2_pre_empty[0];
    e[11] = rc;
    e[12] = rc && (n_retired >= FD07_RC_RETIRED);
    e[13] = pop && dut.u_bpu.u_ras.p2_pop_dec[0] && !dut.u_bpu.w_kill_p2;
    // Entry 1, count 4 until f1's call to f2 reallocates it.
    e[14] = (dut.u_bpu.u_ras.spec_ret_addr[1] ==
             RESET_VECTOR + VA_WIDTH'('h50A)) &&
            (dut.u_bpu.u_ras.spec_rctr[1] == 0);
    e[15] = ev_redir(RESET_VECTOR + VA_WIDTH'('h18));
    e[16] = ev_redir(RESET_VECTOR + VA_WIDTH'('h2E));
    return e;
  endfunction
