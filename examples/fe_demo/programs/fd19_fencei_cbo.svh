// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd19_fencei_cbo.svh -- FD-19 FENCE.I and cbo.inval
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     the drain, the invalidate and the restart
//   program   a function called twice, rewritten by a store, a FENCE.I,
//             and called again (the new code runs); then a second
//             function the same way with a cbo.inval of its line, after
//             a mispredicted branch and before cold code, so fills are
//             in flight when the L1I takes the invalidate
//   waveform  the IFU maintenance, the L1I invalidate, done, the restart
//   trace     the maintenance handshake
//   proof     an invalidate of all lines (FENCE.I) and of one line
//             (cbo.inval) taken by the L1I, two invalidate done pulses,
//             and after each IFU ack the first fetch starts at the
//             instruction after the maintenance operation
// ===================================================================

  task automatic prog_fd19();
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] g;
    begin_scen("fd19_fencei_cbo", 1'b0);
    f = RESET_VECTOR + VA_WIDTH'('h800);
    g = RESET_VECTOR + VA_WIDTH'('hC40);
    W.mixed(3);
    smc_fn(f, 2);
    W.mixed(2);
    smc_store(f);
    W.mixed(2);
    W.fence_i();
    W.mixed(2);
    smc_call_new(f);
    W.mixed(2);
    smc_fn(g, 2);
    smc_store(g);
    W.cskip(1'b1, 1);                       // taken, cold: mispredicted
    W.cbo_inval(5'd10, PA_WIDTH'(g) + PA_WIDTH'('h24));
    W.mixed(60);                            // cold lines after it
    smc_call_new(g);
    W.mixed(2);
    demo_go(40000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd19_fencei_cbo.md, in table order. The
  // FENCE.I is at +0x20, the next instruction +0x24; the taken branch
  // at +0x40 targets +0x46, the cbo.inval; the next instruction +0x4A.
  // The IFU's and the L1I's maintenance signals are design registers;
  // the backend's redirects (RC_REPLAY after a maintenance ack, and the
  // mispredict) are driven by the testbench: late.
  // =================================================================
  function automatic logic fd19_fetch(input logic [VA_WIDTH-1:0] pc);
    return dut.ftq_ifu_req_val && dut.ftq_ifu_req_rdy &&
           !dut.ftq_ifu_flush_val && (dut.ftq_ifu_start_pc == pc);
  endfunction

  function automatic void fd19_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("the_FENCEI_reaches_the_L1I", EV_WINDOW);
    evt_def("first_invalidate_done", EV_WINDOW);
    evt_def("first_maintenance_acknowledgement", EV_WINDOW);
    evt_def("the_restart_after_the_FENCEI", EV_WINDOW, 1);
    evt_def("fetch_starts_at_0x8000_0024", EV_WINDOW);
    evt_def("the_branch_at_0x8000_0040_mispredicted", EV_WINDOW, 1);
    evt_def("the_cboinval_reaches_the_L1I", EV_WINDOW);
    evt_def("second_invalidate_done", EV_WINDOW, 0, 1);
    evt_def("second_maintenance_acknowledgement", EV_WINDOW, 0, 1);
    evt_def("the_restart_after_the_cboinval", EV_WINDOW, 1);
    evt_def("fetch_starts_at_0x8000_004A", EV_WINDOW);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd19_evt_now();
    logic [EV_MAX-1:0] e;
    e     = '0;
    e[0]  = ev_p0(RESET_VECTOR);
    e[1]  = dut.ifu_l1i_inv_val && dut.ifu_l1i_inv_rdy && dut.ifu_l1i_inv_all;
    e[2]  = dut.l1i_ifu_inv_done;
    e[3]  = ifu_cmt_maint_ack;
    e[4]  = ev_redir_any(RESET_VECTOR + VA_WIDTH'('h24));
    e[5]  = fd19_fetch(RESET_VECTOR + VA_WIDTH'('h24));
    e[6]  = ev_redir(RESET_VECTOR + VA_WIDTH'('h46));
    e[7]  = dut.ifu_l1i_inv_val && dut.ifu_l1i_inv_rdy &&
            !dut.ifu_l1i_inv_all;
    // The last of the two dones and acks: the cbo.inval's.
    e[8]  = dut.l1i_ifu_inv_done;
    e[9]  = ifu_cmt_maint_ack;
    e[10] = ev_redir_any(RESET_VECTOR + VA_WIDTH'('h4A));
    e[11] = fd19_fetch(RESET_VECTOR + VA_WIDTH'('h4A));
    return e;
  endfunction
