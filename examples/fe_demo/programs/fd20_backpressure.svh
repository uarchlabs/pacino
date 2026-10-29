// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd20_backpressure.svh -- FD-20 Backpressure
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     ibuf full, FTQ full and a stalled decode, and where each
//             stall starts
//   program   a loop of 40 passes over 24 instructions with the backend
//             accepting decode's output one cycle in four (be_rdy_pat 4,
//             the provisional answer to FD-U2)
//   waveform  the ibuf occupancy, the FTQ pointers, the p0 request
//   trace     the stalls
//   proof     cycles with the ibuf refusing the IFU, with the FTQ full,
//             with decode holding a bundle while dec_ibuf_rdy is low,
//             and with no p0 request
// ===================================================================

  task automatic prog_fd20();
    logic [VA_WIDTH-1:0] top;
    begin_scen("fd20_backpressure", 1'b0);
    be_rdy_pat = 4;
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 40; it++) begin
      W.wp = top;
      W.mixed(23);
      W.bcc(it != 39, top);
    end
    W.mixed(3);
    demo_go(80000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd20_backpressure.md, in table order. The
  // epilogue after the back edge is top + 66, 0x8000_004A. The
  // decode stall reads dec_ibuf_rdy, which the backend drives; the
  // monitor's n_dec_stall reads the same at the edge, so that check is
  // not late. The backend's redirect is late.
  // =================================================================
  function automatic void fd20_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("decode_first_holds_a_bundle", EV_WINDOW);
    evt_def("the_instruction_buffer_first_refuses_the", EV_WINDOW);
    evt_def("the_FTQ_first_full", EV_WINDOW);
    evt_def("back_edge_falls_through", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd20_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    e[1] = pd_out[0].valid && !dec_ibuf_rdy;
    // The ibuf refuses the IFU's block, at the occupancy the ready is
    // computed from.
    e[2] = dut.ifu_ibuf_val && !dut.ibuf_ifu_rdy &&
           (dut.u_ibuf.r_count == 52);
    e[3] = ftq_full && !dut.ftq_pred_val_p0;
    e[4] = ev_redir(RESET_VECTOR + VA_WIDTH'('h4A));
    return e;
  endfunction
