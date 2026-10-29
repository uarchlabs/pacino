// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd12_training.svh -- FD-12 Training
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     a resolution through ftq_upd_conv into the update queues,
//             the FTB update and its p0 bubble, the uBTB fill
//   program   tb_fe_top loops: nested counted loops (inner 6, outer 14)
//             with an always-taken conditional, an indirect jump and an
//             indirect call in the body, so every predictor is trained
//   waveform  ftq_resolve, ftq_upd_conv, the update queues, the FTB
//             update
//   trace     updates per predictor; FTB update bubbles
//   proof     an update reaches each of the uBTB, LP, FTB, TAGE, SC,
//             ITTAGE and the RAS commit; the FTB update holds p0
//             (ftq_npc H3) at least once
// ===================================================================

  task automatic prog_fd12();
    logic [VA_WIDTH-1:0] otop;
    logic [VA_WIDTH-1:0] itop;
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] link;
    int                  eo;
    int                  ei;
    begin_scen("fd12_training", 1'b0);
    W.mixed(4);
    fn   = RESET_VECTOR + VA_WIDTH'('h800);
    otop = W.wp;
    eo   = W.ne;
    W.mixed(2);
    itop = W.wp;
    ei   = W.ne;
    W.mixed(3);
    W.loop_br(itop);
    W.rep_iter(ei, 6);
    W.cond(1'b1, W.wp + VA_WIDTH'(12));            // always taken
    W.mixed(2);
    W.jalr_to(5'd0, 5'd7, W.wp + VA_WIDTH'('h40)); // indirect jump
    W.mixed(2);
    link = W.wp + VA_WIDTH'(4);
    W.jalr_to(5'd1, 5'd28, fn);                    // indirect call
    W.mixed(3);
    W.ret(link);
    W.mixed(1);
    W.loop_br(otop);
    W.rep_iter(eo, 14);
    W.mixed(3);
    demo_go(80000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd12_training.md, in table order. One
  // slot. The resolution and the updates formed from it in the same
  // cycle are driven by the testbench (late, per the FST); the FTB
  // update, its p0 hold and the RAS commit change at the edge.
  // =================================================================
  function automatic void fd12_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_p0_request_withheld_for_an", EV_WINDOW);
    evt_def("first_resolution_from_the_backend", EV_WINDOW, 1);
    evt_def("first_uBTB_update", EV_WINDOW, 1);
    evt_def("first_FTB_update", EV_WINDOW);
    evt_def("first_loop_predictor", EV_WINDOW, 1);
    evt_def("first_ITTAGE_update", EV_WINDOW, 1);
    evt_def("first_RAS_commit", EV_WINDOW);
    evt_def("the_beq_placed_in_an_occupied", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd12_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    e[1] = dut.u_ftq.u_npc.h3_ftb_upd;
    e[2] = bkend_ftq_rsv_val[0];
    e[3] = dut.u_bpu.w_ubtb_upd_u0[0].valid;
    e[4] = dut.u_bpu.w_ftb_upd_val_u0;
    e[5] = (dut.u_bpu.w_lp_upd_val_p0 != '0) &&
           (dut.u_bpu.w_tage_upd_val_u0 != '0) &&
           (dut.u_bpu.w_sc_upd_val_u0 != '0);
    e[6] = dut.u_bpu.w_ittage_upd_val_u0 != '0;
    e[7] = dut.u_bpu.w_ras_commit_val;
    // A resolution placed in an occupied slot (item C, BP-139).
    e[8] = dut.u_ftq.u_resolve.rsv_plc_occ[0];
    return e;
  endfunction
