// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd22_sc_slot1.svh -- FD-22 SC reversing slot 1
// (planning/showcase/fe_demo_scenarios.md, DOC-006)
//
//   shows     two conditionals in one block, slot 0 predicted by TAGE
//             and slot 1 reversed by SC at p3
//   program   a loop of 48 passes; its first block holds A, never
//             taken, and B, taken on odd passes, so A is slot 0 and B
//             slot 1 of one prediction block. B skips
//             one instruction, so its target is inside the block and
//             differs from the block's fall-through, and a reversal of
//             B changes the block's successor. The back edge is in the
//             next block
//   waveform  TAGE p2, SC p3, the p3 slots and redirect
//   trace     p3 redirects whose slot 1 SC decided
//   proof     a p3 redirect the FTQ accepted, raised by slot 1, a
//             conditional with pred_src PRED_SC, in a block whose slot 0
//             is a conditional with pred_src PRED_TAGE. Two-slot model only
//             (Makefile SCEN_2S): on the one-slot model the count is 0
// ===================================================================

  localparam int FD22_ITERS = 48;

  task automatic prog_fd22();
    logic [VA_WIDTH-1:0] top;
    begin_scen("fd22_sc_slot1", 1'b0);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < FD22_ITERS; it++) begin
      W.wp = top;
      W.mixed(2);
      W.cskip(1'b0, 1);                       // A, never taken
      W.mixed(1);
      W.cskip((it % 2) == 1, 1);              // B, on odd passes
      W.mixed(6);                             // to the next block
      W.bcc(it != FD22_ITERS - 1, top);
    end
    W.mixed(3);
    demo_go(80000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd22_sc_slot1.md, in table order. top is
  // 0x8000_0008: A at position 3, B at position 7, B's target
  // 0x8000_001C, the block's end 0x8000_0028; the epilogue 0x8000_0030.
  // The backend's redirects are driven by the testbench: late.
  // =================================================================
  localparam logic [VA_WIDTH-1:0] FD22_TOP = RESET_VECTOR + VA_WIDTH'('h08);

  function automatic logic [VA_WIDTH-1:0] fd22_at(input int off);
    return RESET_VECTOR + VA_WIDTH'(off);
  endfunction

  // An accepted p3 redirect raised by slot s, SC-decided, to pc.
  function automatic logic fd22_p3(input int s, input logic [VA_WIDTH-1:0] pc);
    return dut.u_ftq.w_ok_redir_p3 && dut.bpu_slot_val_p3 &&
           (dut.bpu_slot_idx_p3 == dut.bpu_redir_idx_p3) &&
           dut.bpu_redir_p3[s].valid && (dut.bpu_redir_p3[s].target_pc == pc) &&
           (dut.bpu_slot_p3[s].pred_src == PRED_SC);
  endfunction

  function automatic void fd22_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_backend_misprediction", EV_WINDOW, 1);
    evt_def("first_p2_group_for_the_block", EV_WINDOW);
    evt_def("first_p3_redirect", EV_WINDOW);
    evt_def("A_mispredicted", EV_WINDOW, 1);
    evt_def("first_p3_redirect_from_slot_1", EV_WINDOW);
    evt_def("SC_corrects_TAGEs_taken_for_B", EV_WINDOW);
    evt_def("last_backend_misprediction_of_B", EV_WINDOW, 1, 1);
    evt_def("back_edge_falls_through", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd22_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = dut.ftq_pred_val_p0 && (dut.ftq_pred_pc_p0 == RESET_VECTOR);
    e[1] = ev_redir(FD22_TOP);
    // top at p2 with A (position 3) in slot 0 and B (position 7) in
    // slot 1, both conditionals TAGE predicted.
    e[2] = dut.u_bpu.r_val_p2 && (dut.u_bpu.r_pc_p2 == FD22_TOP) &&
           dut.bpu_slot_p2[0].slot_valid && (dut.bpu_slot_p2[0].pos == 3) &&
           (dut.bpu_slot_p2[0].br_type == COND) &&
           (dut.bpu_slot_p2[0].pred_src == PRED_TAGE) &&
           dut.bpu_slot_p2[S1].slot_valid && (dut.bpu_slot_p2[S1].pos == 7) &&
           (dut.bpu_slot_p2[S1].br_type == COND) &&
           (dut.bpu_slot_p2[S1].pred_src == PRED_TAGE);
    e[3] = fd22_p3(0, fd22_at('h14));
    e[4] = ev_redir(fd22_at('h12));
    e[5] = fd22_p3(S1, fd22_at('h1C));
    e[6] = fd22_p3(S1, fd22_at('h28));
    e[7] = ev_redir(fd22_at('h1A));
    e[8] = ev_redir(fd22_at('h30));
    return e;
  endfunction
