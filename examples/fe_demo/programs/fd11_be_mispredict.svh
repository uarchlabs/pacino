// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd11_be_mispredict.svh -- FD-11 Backend mispredict
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     the backend redirect: FTQ squash, IFU flush, history
//             rollback and correction, RAS restore
//   program   tb_fe_top misp_call: a conditional with a pseudo-random
//             outcome (LFSR seed ACE1), then a call and its return, 32
//             passes
//   waveform  the backend resolution, the FTQ squash, the IFU flush and
//             restart, bp_history, the RAS restore
//   trace     backend redirects; the fetch that follows
//   proof     a backend mispredict redirect whose first following fetch
//             from the FTQ starts at the redirect PC
// ===================================================================

  task automatic prog_fd11();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] l;
    begin_scen("fd11_be_mispredict", 1'b0);
    W.lfsr = 16'hACE1;
    fn = RESET_VECTOR + VA_WIDTH'('h400);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 32; it++) begin
      W.wp = top;
      W.mixed(1);
      W.cskip(W.lfsr_bit(), 1);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, fn);
      W.mixed(2);
      W.ret(l);
      W.mixed(1);
      W.bcc(it != 31, top);
    end
    W.mixed(3);
    demo_go(80000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd11_be_mispredict.md, in table order. top
  // is 0x8000_0008; A at 0x8000_000A, taken to 0x8000_0010 or falling
  // through to 0x8000_000E; the return address 0x8000_0014; the exit
  // 0x8000_001A. The backend's redirects are driven by the testbench:
  // late. The rollback, the RAS restore and the fetch are the design's.
  // =================================================================
  function automatic void fd11_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_history_rollback", EV_WINDOW);
    evt_def("first_misprediction_of_A_taken", EV_WINDOW, 1);
    evt_def("fetch_restarts_at_0x8000_0010", EV_WINDOW);
    evt_def("first_predecode_redirect", EV_WINDOW);
    evt_def("the_return_mispredicted", EV_WINDOW, 1);
    evt_def("fetch_restarts_at_0x8000_0014", EV_WINDOW);
    evt_def("the_back_edge_mispredicted", EV_WINDOW, 1);
    evt_def("first_p2_redirect", EV_WINDOW);
    evt_def("first_p3_redirect", EV_WINDOW);
    evt_def("the_FTB_splits_the_block_at", EV_WINDOW);
    evt_def("first_RAS_restore_moving_TOSW", EV_WINDOW, 1);
    evt_def("first_misprediction_of_A_not_taken", EV_WINDOW, 1);
    evt_def("fetch_restarts_at_0x8000_000E", EV_WINDOW);
    evt_def("first_RAS_restore_moving_BOS", EV_WINDOW, 1);
    evt_def("the_loop_exits", EV_WINDOW, 1);
    evt_def("fetch_restarts_at_0x8000_001A", EV_WINDOW);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  // A fetch the FTQ presents at pc, outside a flush. A block starts at
  // each of the checked addresses only after a redirect to it.
  function automatic logic fd11_fetch(input logic [VA_WIDTH-1:0] pc);
    return dut.ftq_ifu_req_val && dut.ftq_ifu_req_rdy &&
           !dut.ftq_ifu_flush_val && (dut.ftq_ifu_start_pc == pc);
  endfunction

  function automatic logic [EV_MAX-1:0] fd11_evt_now();
    logic [EV_MAX-1:0] e;
    e     = '0;
    e[0]  = ev_p0(RESET_VECTOR);
    e[1]  = dut.ftq_rollback_val && dut.ras_restore_val;
    e[2]  = ev_redir(RESET_VECTOR + VA_WIDTH'('h10));
    e[3]  = fd11_fetch(RESET_VECTOR + VA_WIDTH'('h10));
    e[4]  = ev_pd_redir(RESET_VECTOR + VA_WIDTH'('h400));
    e[5]  = ev_redir(RESET_VECTOR + VA_WIDTH'('h14));
    e[6]  = fd11_fetch(RESET_VECTOR + VA_WIDTH'('h14));
    e[7]  = ev_redir(RESET_VECTOR + VA_WIDTH'('h08));
    e[8]  = ev_p2_redir(RESET_VECTOR + VA_WIDTH'('h14));
    e[9]  = ev_p3_redir(RESET_VECTOR + VA_WIDTH'('h10));
    e[10] = dut.ftb_upd_valid_u0 && dut.u_bpu.u_ftb.u_ftb_cntrl.upd_split &&
            (dut.ftb_upd_pc_u0 == RESET_VECTOR + VA_WIDTH'('h08));
    // The restores bp_cluster passes to the RAS, not those it drops.
    e[11] = dut.u_bpu.w_ras_restore_val &&
            (dut.ras_restore_snapshot.tosw != dut.u_bpu.u_ras.tosw);
    e[12] = ev_redir(RESET_VECTOR + VA_WIDTH'('h0E));
    e[13] = fd11_fetch(RESET_VECTOR + VA_WIDTH'('h0E));
    e[14] = dut.u_bpu.w_ras_restore_val &&
            (dut.ras_restore_snapshot.bos != dut.u_bpu.u_ras.bos);
    e[15] = ev_redir(RESET_VECTOR + VA_WIDTH'('h1A));
    e[16] = fd11_fetch(RESET_VECTOR + VA_WIDTH'('h1A));
    return e;
  endfunction
