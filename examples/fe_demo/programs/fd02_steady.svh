// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd02_steady.svh -- FD-2 Steady-state prediction and fetch
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     one block per cycle: p0 request, uBTB answer at p1, FTQ
//             allocation, the next p0 the cycle after
//   program   straight-line code with no branches: 512 32-bit
//             instructions, 2 KiB, 32 lines, then the end
//   waveform  bp_cluster p0/p1, FTQ pointers, IFU F0-F3, ibuf, decode
//   trace     one allocation per cycle; full decode bundles
//   proof     at least 4 consecutive cycles of FTQ allocation, and at
//             least 4 consecutive cycles in which decode delivered SLOTS
//             (8) instructions
// ===================================================================

  task automatic prog_fd02();
    begin_scen("fd02_steady", 1'b0);
    for (int i = 0; i < 512; i++) W.i32(ADDI_T0);
    demo_go(20000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd02_steady.md, in table order. The code
  // is 64 blocks of eight 32-bit instructions from 0x8000_0000; the
  // halt block is 0x8000_0800. A full bundle is all SLOTS lanes of
  // pd_out valid, read from the design's output alone (dec_ibuf_rdy,
  // the backend's, is driven by the testbench).
  // =================================================================
  function automatic logic fd02_full(input logic [VA_WIDTH-1:0] pc);
    logic f;
    f = 1'b1;
    for (int i = 0; i < SLOTS; i++) f = f && pd_out[i].valid;
    return f && (pd_out[0].start_pc == pc);
  endfunction

  function automatic void fd02_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_p1_prediction_the_FTQ_accepts", EV_WINDOW);
    evt_def("first_full_decode_bundle", EV_WINDOW);
    evt_def("second_full_bundle", EV_WINDOW);
    evt_def("the_halt_block_reaches_decode", EV_WINDOW);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd02_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    e[1] = dut.u_ftq.w_ok_pred_p1;
    e[2] = fd02_full(RESET_VECTOR);
    e[3] = fd02_full(RESET_VECTOR + VA_WIDTH'('h20));
    // The halt block: one instruction, lane 0 only.
    e[4] = pd_out[0].valid && !pd_out[1].valid &&
           (pd_out[0].start_pc == RESET_VECTOR + VA_WIDTH'('h800));
    return e;
  endfunction
