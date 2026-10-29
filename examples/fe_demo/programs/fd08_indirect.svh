// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd08_indirect.svh -- FD-8 Indirect jump
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     ITTAGE predicting an indirect target
//   program   tb_fe_top indir: an indirect jump and an indirect call
//             whose targets alternate, each after a conditional that
//             alternates with them, 40 passes
//   waveform  ITTAGE p2, the FTB target, the p2 target selection
//   trace     ITTAGE-supplied targets
//   proof     a retired indirect jump or call whose FTQ entry's final
//             slot for it has pred_src PRED_ITTAGE and the right target
// ===================================================================

  task automatic prog_fd08();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] ta;
    logic [VA_WIDTH-1:0] tb;
    logic [VA_WIDTH-1:0] jn;
    logic [VA_WIDTH-1:0] fa;
    logic [VA_WIDTH-1:0] fb;
    logic [VA_WIDTH-1:0] l;
    logic                odd;
    begin_scen("fd08_indirect", 1'b0);
    ta = RESET_VECTOR + VA_WIDTH'('h400);
    tb = RESET_VECTOR + VA_WIDTH'('h480);
    jn = RESET_VECTOR + VA_WIDTH'('h500);
    fa = RESET_VECTOR + VA_WIDTH'('h600);
    fb = RESET_VECTOR + VA_WIDTH'('h680);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 40; it++) begin
      odd = (it % 2) == 1;
      W.wp = top;
      W.mixed(1);
      W.cskip(odd, 1);
      W.jalr_to(5'd0, 5'd7, odd ? ta : tb);   // indirect jump
      if (odd) W.mixed(2);
      else     W.mixed(1);
      W.jal(5'd0, jn);
      W.mixed(1);
      W.cskip(!odd, 1);
      l = W.wp + VA_WIDTH'(4);
      W.jalr_to(5'd1, 5'd28, odd ? fa : fb);  // indirect call
      if (odd) W.mixed(2);
      else     W.mixed(1);
      W.ret(l);
      W.mixed(1);
      W.exit_or_jal(it == 39, top);
    end
    W.mixed(3);
    demo_go(80000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd08_indirect.md, in table order. J is the
  // jalr at top + 8 (0x8000_0010), to ta 0x8000_0400 or tb 0x8000_0480;
  // K the jalr call at 0x8000_0508, to fa 0x8000_0600 or fb
  // 0x8000_0680; the loop exit's target 0x8000_0516. One slot. The
  // backend's redirects are driven by the testbench: late.
  // =================================================================
  function automatic void fd08_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_misprediction_of_J", EV_WINDOW, 1);
    evt_def("first_ITTAGE_tagged_hit_at_p2", EV_WINDOW);
    evt_def("first_target_of_K_from_ITTAGE", EV_WINDOW);
    evt_def("first_target_of_J_from_ITTAGE", EV_WINDOW);
    evt_def("the_loop_exits", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd08_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    e[1] = ev_redir(RESET_VECTOR + VA_WIDTH'('h480));
    e[2] = dut.u_bpu.w_ittage_pred_rdy_p2[0] &&
           dut.u_bpu.w_ittage_pred_meta_p2[0].ittage_hit;
    e[3] = dut.u_ftq.w_ok_slot_p2 && dut.bpu_slot_val_p2 &&
           dut.bpu_slot_p2[0].slot_valid &&
           (dut.bpu_slot_p2[0].br_type == INDIRECT_CALL) &&
           (dut.bpu_slot_p2[0].pred_src == PRED_ITTAGE);
    e[4] = dut.u_ftq.w_ok_slot_p2 && dut.bpu_slot_val_p2 &&
           dut.bpu_slot_p2[0].slot_valid &&
           (dut.bpu_slot_p2[0].br_type == INDIRECT_NONRET) &&
           (dut.bpu_slot_p2[0].pred_src == PRED_ITTAGE);
    e[5] = ev_redir(RESET_VECTOR + VA_WIDTH'('h516));
    return e;
  endfunction
