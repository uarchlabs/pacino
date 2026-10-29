// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd09_tage.svh -- FD-9 TAGE provider, allocation and use_alt_on_na
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     a tagged provider hit, an allocation after a mispredict,
//             use_alt_on_na choosing T0
//   program   tb_fe_top t0_uaon: a conditional taken with probability
//             1/8 (LFSR seed ACE1), 256 passes
//   waveform  TAGE p2 provider, the update path, the allocation, uaon
//   trace     allocations; T0 predictions through use_alt_on_na
//   proof     a TAGE allocation write applied; a p2 prediction whose
//             primary is tagged but whose prediction is T0's through
//             use_alt_on_na
// ===================================================================

  task automatic prog_fd09();
    logic [VA_WIDTH-1:0] top;
    logic                tk;
    begin_scen("fd09_tage", 1'b0);
    W.lfsr = 16'hACE1;
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 256; it++) begin
      W.wp = top;
      W.mixed(2);
      tk = W.lfsr_bit() & W.lfsr_bit() & W.lfsr_bit();
      W.cskip(tk, 1);                         // B
      W.mixed(1);
      W.bcc(it != 255, top);
    end
    W.mixed(3);
    demo_go(200000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd09_tage.md, in table order. The block
  // at top is 0x8000_0008; B is at 0x8000_000E, its target 0x8000_0014;
  // the back edge's block starts at 0x8000_0016; the epilogue at
  // 0x8000_001A. One slot, so every per-slot signal is [0]. The
  // backend's redirect and the update path it feeds (the allocation)
  // are driven by the testbench, so those checks are late.
  // =================================================================
  localparam logic [VA_WIDTH-1:0] FD09_TOP  = RESET_VECTOR + VA_WIDTH'('h08);
  localparam logic [VA_WIDTH-1:0] FD09_BTGT = RESET_VECTOR + VA_WIDTH'('h14);
  localparam logic [VA_WIDTH-1:0] FD09_BEB  = RESET_VECTOR + VA_WIDTH'('h16);
  localparam logic [VA_WIDTH-1:0] FD09_EPI  = RESET_VECTOR + VA_WIDTH'('h1A);

  function automatic void fd09_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_TAGE_response_at_p2", EV_WINDOW);
    evt_def("first_allocation_write", EV_WINDOW, 1);
    evt_def("first_backend_misprediction", EV_WINDOW, 1);
    evt_def("the_back_edge_resolved_from_top", EV_WINDOW);
    evt_def("first_FTB_hit_at_p2", EV_WINDOW);
    evt_def("first_p2_group_at_0x8000_0016", EV_WINDOW);
    evt_def("first_taken_B_resolved", EV_WINDOW, 1);
    evt_def("its_allocation_write", EV_WINDOW, 1);
    evt_def("first_prediction_from_a_tagged_table", EV_WINDOW);
    evt_def("uaon_first_increments", EV_WINDOW);
    evt_def("uaon_reaches_8", EV_WINDOW);
    evt_def("first_prediction_from_T0", EV_WINDOW);
    evt_def("back_edge_falls_through", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd09_evt_now();
    logic [EV_MAX-1:0] e;
    logic              alc;
    tage_pred_meta_t   m;
    tage_upd_inp_t     u;
    e   = '0;
    u   = dut.u_bpu.u_tage.u_tage_cntrl.tage_upd_inp_u0[0];
    m   = dut.u_bpu.u_tage.u_tage_cntrl.tage_pred_meta_p2[0];
    // An allocation write applied (as the monitor's n_tage_alc).
    alc = dut.u_bpu.u_tage.u_tage_cntrl.trx_type &&
          dut.u_bpu.u_tage.u_tage_cntrl.tage_upd_val_u0[0] &&
          dut.u_bpu.u_tage.u_tage_cntrl.u_alc_wr[0];
    // Reset released, and the FTQ's first p0 request at the reset
    // vector in the same cycle.
    e[0]  = dut.ftq_pred_val_p0 && (dut.ftq_pred_pc_p0 == RESET_VECTOR);
    e[1]  = dut.u_bpu.r_val_p2 && (dut.u_bpu.w_tage_pred_rdy_p2 != '0);
    // B not taken, predicted taken by T0 (provider 0), into T1.
    e[2]  = alc && !u.resolved_taken && (u.tage_pred_meta.tage_prm_comp == '0)
            && (dut.u_bpu.u_tage.u_tage_cntrl.u_alc_comp[0] == 1);
    e[3]  = ev_redir(FD09_TOP);
    // The FTB update for top that splits the entry (the back edge).
    e[4]  = dut.u_bpu.u_ftb.u_ftb_cntrl.upd_active &&
            dut.u_bpu.u_ftb.u_ftb_cntrl.upd_split &&
            (dut.u_bpu.ftb_upd_pc_u0 == FD09_TOP);
    e[5]  = dut.u_bpu.r_val_p2 && (dut.u_bpu.r_pc_p2 == FD09_TOP) &&
            dut.u_bpu.w_ftb_hit_p2 && dut.bpu_slot_p2[0].slot_valid &&
            (dut.bpu_slot_p2[0].pred_src == PRED_TAGE) &&
            !dut.bpu_slot_p2[0].taken;
    e[6]  = dut.u_bpu.r_val_p2 && (dut.u_bpu.r_pc_p2 == FD09_BEB) &&
            dut.bpu_slot_p2[0].slot_valid && dut.bpu_slot_p2[0].taken &&
            (dut.bpu_slot_p2[0].pred_src == PRED_TAGE);
    e[7]  = ev_redir(FD09_BTGT);
    // B taken: its allocation, into T1.
    e[8]  = alc && u.resolved_taken &&
            (dut.u_bpu.u_tage.u_tage_cntrl.u_alc_comp[0] == 1);
    e[9]  = dut.u_bpu.u_tage.u_tage_cntrl.tage_pred_rdy_p2[0] &&
            m.tage_using_primary && (m.tage_prm_comp == 1);
    e[10] = dut.u_bpu.u_tage.u_tage_cntrl.uaon[0] == 4'd1;
    e[11] = dut.u_bpu.u_tage.u_tage_cntrl.uaon[0] == 4'd8;
    // Provider T1, prediction T0's through use_alt_on_na (as n_t0_uaon).
    e[12] = dut.u_bpu.u_tage.u_tage_cntrl.tage_pred_rdy_p2[0] &&
            !m.tage_using_primary && (m.tage_prm_comp == 1) &&
            (m.tage_alt_comp == '0);
    e[13] = ev_redir(FD09_EPI);
    return e;
  endfunction
