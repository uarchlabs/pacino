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
  // slot. The resolution, the backend redirect and the logic
  // combinational from them are late (per the FST); the FTB update, the
  // RAS commit and the p2 group change at the edge.
  // =================================================================
  function automatic void fd12_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_resolution_from_the_backend", EV_WINDOW, 1);
    evt_def("first_consecutive_FTB_updates", EV_WINDOW);
    evt_def("first_ITTAGE_update", EV_WINDOW, 1);
    evt_def("first_RAS_commit", EV_WINDOW);
    evt_def("first_RETURN_commit", EV_WINDOW);
    evt_def("backend_misprediction_of_the_alwaystaken_beq", EV_WINDOW, 1);
    evt_def("resolution_of_the_alwaystaken_beq", EV_WINDOW, 1);
    evt_def("first_accepted_p2_group_for_the", EV_WINDOW);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd12_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    e[1] = bkend_ftq_rsv_val[0];
    // An FTB update this cycle and, by the hold, another in the next.
    e[2] = dut.ftb_upd_valid_u0 && dut.u_ftq.u_npc.h3_ftb_upd;
    e[3] = dut.u_bpu.w_ittage_upd_val_u0 != '0;
    e[4] = dut.u_bpu.w_ras_commit_val;
    e[5] = dut.u_bpu.w_ras_commit_val && (dut.ras_commit_br_type == RETURN);
    // The beq at position 6 of the block at +0x10. Position separates it
    // from the same redirect target at position 0 of the block at +0x1C.
    e[6] = ev_redir(RESET_VECTOR + VA_WIDTH'('h28)) &&
           (bkend_ftq_redir_pos == 4'd6);
    // A resolution placed in an occupied slot (item C, BP-139).
    e[7] = dut.u_ftq.u_resolve.rsv_plc_occ[0];
    // The block at +0x10 after the FTB split, ending at +0x1C.
    e[8] = dut.u_ftq.w_ok_slot_p2 &&
           (dut.u_bpu.r_pc_p2 == RESET_VECTOR + VA_WIDTH'('h10)) &&
           (dut.bpu_blk_pft_p2 == RESET_VECTOR + VA_WIDTH'('h1C));
    return e;
  endfunction
