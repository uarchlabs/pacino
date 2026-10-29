// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd24_call_slot1.svh -- FD-24 A call in slot 1
// (planning/showcase/fe_demo_scenarios.md, DOC-006)
//
//   shows     a call in slot 1 behind a not-taken conditional in slot
//             0, the RAS push made from slot 1
//   program   a loop of 24 passes; its first block holds C, never
//             taken, then a jal x1 to f at +0x400; f returns to the
//             block that holds the back edge
//   waveform  the p2 slots, the RAS p2 operation and pointers
//   trace     RAS pushes from slot 1
//   proof     a p2 group the FTQ accepted whose slot 0 is a not-taken
//             conditional and whose slot 1, a call, is presented to the
//             RAS (w_ras_pred_val_p2); and a retired return whose
//             target the RAS supplied. Two-slot model only (Makefile
//             SCEN_2S): on the one-slot model the first count is 0
// ===================================================================

  localparam int FD24_ITERS = 24;

  task automatic prog_fd24();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] l;
    begin_scen("fd24_call_slot1", 1'b0);
    f = RESET_VECTOR + VA_WIDTH'('h400);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < FD24_ITERS; it++) begin
      W.wp = top;
      W.i16();
      W.cskip(1'b0, 1);                       // C, never taken
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, f);                         // the call
      W.mixed(2);                             // f
      W.ret(l);
      W.mixed(2);
      W.bcc(it != FD24_ITERS - 1, top);       // back edge
    end
    W.mixed(3);
    demo_go(80000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd24_call_slot1.md, in table order. top is
  // 0x8000_0008: C at position 1, the call at 4 to f, 0x8000_0400; the
  // return address 0x8000_0014; C's target 0x8000_0010 and fall-through
  // 0x8000_000E; the epilogue 0x8000_001E. The backend's redirects are
  // driven by the testbench: late.
  // =================================================================
  localparam logic [VA_WIDTH-1:0] FD24_TOP = RESET_VECTOR + VA_WIDTH'('h08);
  localparam logic [VA_WIDTH-1:0] FD24_F   = RESET_VECTOR + VA_WIDTH'('h400);
  localparam logic [VA_WIDTH-1:0] FD24_RA  = RESET_VECTOR + VA_WIDTH'('h14);

  function automatic void fd24_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("predecode_redirect_to_0x8000_0400", EV_WINDOW);
    evt_def("first_return_mispredicted", EV_WINDOW, 1);
    evt_def("back_edge_mispredicted", EV_WINDOW, 1);
    evt_def("C_mispredicted_taken", EV_WINDOW, 1);
    evt_def("first_RAS_push_from_slot_1", EV_WINDOW);
    evt_def("TOSR_1", EV_WINDOW);
    evt_def("back_edge_falls_through", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd24_evt_now();
    logic [EV_MAX-1:0] e;
    logic              ras_ret;
    e    = '0;
    e[0] = dut.ftq_pred_val_p0 && (dut.ftq_pred_pc_p0 == RESET_VECTOR);
    e[1] = ev_pd_redir(FD24_F);
    e[2] = ev_redir(FD24_RA);
    e[3] = ev_redir(FD24_TOP);
    e[4] = ev_redir(RESET_VECTOR + VA_WIDTH'('h0E));
    // As the monitor's n_push_s1: a call in slot 1, behind a not-taken
    // conditional in slot 0, presented to the RAS in an accepted group.
    e[5] = dut.u_ftq.w_ok_slot_p2 && dut.bpu_slot_val_p2 &&
           dut.u_bpu.w_ras_pred_val_p2[S1] &&
           (dut.u_bpu.w_br_type_p2[S1] == DIRECT_CALL) &&
           dut.bpu_slot_p2[0].slot_valid && !dut.bpu_slot_p2[0].taken &&
           (dut.bpu_slot_p2[0].br_type == COND);
    // The pointers after the push, the return address in entry 1, and a
    // return in f predicted from the RAS to it.
    ras_ret = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++)
      ras_ret = ras_ret || (dut.bpu_slot_p2[s].slot_valid &&
                            (dut.bpu_slot_p2[s].pred_src == PRED_RAS) &&
                            (dut.bpu_slot_p2[s].target == FD24_RA));
    e[6] = (dut.u_bpu.u_ras.tosr == 1) && (dut.u_bpu.u_ras.tosw == 2) &&
           (dut.u_bpu.u_ras.spec_ret_addr[1] == FD24_RA) &&
           dut.u_bpu.r_val_p2 && (dut.u_bpu.r_pc_p2 == FD24_F) && ras_ret;
    e[7] = ev_redir(RESET_VECTOR + VA_WIDTH'('h1E));
    return e;
  endfunction
