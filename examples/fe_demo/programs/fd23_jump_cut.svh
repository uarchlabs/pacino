// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd23_jump_cut.svh -- FD-23 A jump behind two conditionals
// (planning/showcase/fe_demo_scenarios.md, DOC-006)
//
//   shows     a block {conditional, conditional, jump} with both
//             conditionals not taken: the FTB entry of the block holds
//             the two conditionals and ends at the jump's PC (the split
//             at update, ftb_decisions.md 3, BP-140), and the next
//             block, which starts at the jump, predicts it in slot 0
//   program   a loop of 24 passes; its first block holds C1 and C2,
//             never taken, then J, a jal x0 to a block at +0x400 that
//             holds the back edge. jmp_pc (tb/fe_demo_mon.svh) records
//             J's address for the monitor
//   waveform  the FTB p2 fields, the p2 slots, the block end, the FTB
//             update that splits the entry
//   trace     blocks the FTB ends at the jump; the jump predicted next
//   proof     a p2 group the FTQ accepted with two not-taken
//             conditionals, ended at J's address by the FTB's stored end
//             (bpu_blk_pft_p2 equal to jmp_pc, the cluster's cut
//             w_cut_p2 clear), and the next accepted p2 group at that
//             address holding the jump in slot 0, at position 0, taken.
//             Two-slot model only (Makefile SCEN_2S): on the one-slot
//             model both are 0. DOC-007 re-pointed it from the BP-139
//             cut, which the split leaves unused
// ===================================================================

  localparam int FD23_ITERS = 24;

  task automatic prog_fd23();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] t;
    begin_scen("fd23_jump_cut", 1'b0);
    t = RESET_VECTOR + VA_WIDTH'('h400);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < FD23_ITERS; it++) begin
      W.wp = top;
      W.i16();
      W.cskip(1'b0, 1);                       // C1, never taken
      W.cskip(1'b0, 1);                       // C2, never taken
      jmp_pc = W.wp;                          // the monitor's end check
      W.jal(5'd0, t);                         // J
      W.mixed(2);
      W.bcc(it != FD23_ITERS - 1, top);       // back edge
    end
    W.mixed(3);
    demo_go(80000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd23_jump_cut.md, in table order. top is
  // 0x8000_0008: C1 at position 1, C2 at 4, J at 7 (0x8000_0016); J's
  // target 0x8000_0400; the epilogue 0x8000_040A. The backend's
  // redirects are driven by the testbench: late.
  // =================================================================
  localparam logic [VA_WIDTH-1:0] FD23_TOP = RESET_VECTOR + VA_WIDTH'('h08);
  localparam logic [VA_WIDTH-1:0] FD23_J   = RESET_VECTOR + VA_WIDTH'('h16);
  localparam logic [VA_WIDTH-1:0] FD23_F   = RESET_VECTOR + VA_WIDTH'('h400);

  // An FTB update this cycle for the block from start pc.
  function automatic logic fd23_upd(input logic [VA_WIDTH-1:0] pc);
    return dut.u_bpu.u_ftb.u_ftb_cntrl.upd_active &&
           (dut.ftb_upd_pc_u0 == pc);
  endfunction

  function automatic void fd23_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("predecode_redirect_to_0x8000_0400", EV_WINDOW);
    evt_def("first_backend_misprediction", EV_WINDOW, 1);
    evt_def("FTB_entry_for_top_allocated_with", EV_WINDOW);
    evt_def("first_p2_group_for_top", EV_WINDOW);
    evt_def("SC_reverses_both_at_p3", EV_WINDOW);
    evt_def("J_resolved_from_top", EV_WINDOW);
    evt_def("first_p2_group_for_top_ending", EV_WINDOW);
    evt_def("FTB_entry_for_0x8000_0016_allocated_with", EV_WINDOW);
    evt_def("the_block_at_0x8000_0016_predicts_J", EV_WINDOW);
    evt_def("back_edge_falls_through", EV_WINDOW, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd23_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = dut.ftq_pred_val_p0 && (dut.ftq_pred_pc_p0 == RESET_VECTOR);
    e[1] = ev_pd_redir(FD23_F);
    e[2] = ev_redir(FD23_TOP);
    // The entry for top allocated (no hit) by C1, a conditional at 1.
    e[3] = fd23_upd(FD23_TOP) && !dut.u_bpu.u_ftb.u_ftb_cntrl.upd_hit &&
           dut.ftb_upd_is_br_u0 && (dut.ftb_upd_pos_u0 == 1);
    // top at p2, C1 and C2 in slots 0 and 1, C1 predicted taken, the
    // block's end 0x8000_0028.
    e[4] = dut.u_bpu.r_val_p2 && (dut.u_bpu.r_pc_p2 == FD23_TOP) &&
           dut.bpu_slot_p2[0].slot_valid && (dut.bpu_slot_p2[0].pos == 1) &&
           dut.bpu_slot_p2[0].taken &&
           dut.bpu_slot_p2[S1].slot_valid && (dut.bpu_slot_p2[S1].pos == 4) &&
           (dut.bpu_blk_pft_p2 == RESET_VECTOR + VA_WIDTH'('h28));
    // Both slots redirect at p3, to the block's end.
    e[5] = dut.u_ftq.w_ok_redir_p3 && dut.bpu_redir_p3[0].valid &&
           dut.bpu_redir_p3[S1].valid &&
           (dut.bpu_redir_p3[0].target_pc == RESET_VECTOR + VA_WIDTH'('h28));
    // J, a jump at 7, resolved from top: the split, cut at 7.
    e[6] = fd23_upd(FD23_TOP) && dut.ftb_upd_is_jmp_u0 &&
           (dut.ftb_upd_pos_u0 == 7) &&
           dut.u_bpu.u_ftb.u_ftb_cntrl.upd_split &&
           (dut.u_bpu.u_ftb.u_ftb_cntrl.upd_cut_pos == 7);
    // As the monitor's n_jmp_end: an accepted p2 group for top, the cut
    // clear, the end at J, two conditionals not taken.
    e[7] = dut.u_ftq.w_ok_slot_p2 && dut.bpu_slot_val_p2 &&
           (dut.u_bpu.r_pc_p2 == FD23_TOP) && !dut.u_bpu.w_cut_p2 &&
           (dut.bpu_blk_pft_p2 == FD23_J) &&
           dut.bpu_slot_p2[0].slot_valid && !dut.bpu_slot_p2[0].taken &&
           (dut.bpu_slot_p2[0].br_type == COND) &&
           dut.bpu_slot_p2[S1].slot_valid && !dut.bpu_slot_p2[S1].taken &&
           (dut.bpu_slot_p2[S1].br_type == COND);
    // The entry for J's block allocated with J, a jump at 0.
    e[8] = fd23_upd(FD23_J) && !dut.u_bpu.u_ftb.u_ftb_cntrl.upd_hit &&
           dut.ftb_upd_is_jmp_u0 && (dut.ftb_upd_pos_u0 == 0);
    // As n_jmp_next: J's block at p2 with J in slot 0, taken, to f.
    e[9] = dut.u_ftq.w_ok_slot_p2 && dut.bpu_slot_val_p2 &&
           (dut.u_bpu.r_pc_p2 == FD23_J) && dut.bpu_slot_p2[0].slot_valid &&
           dut.bpu_slot_p2[0].taken &&
           (dut.bpu_slot_p2[0].br_type == DIRECT_UNC) &&
           (dut.bpu_slot_p2[0].pos == 0) &&
           (dut.bpu_slot_p2[0].target == FD23_F);
    e[10] = ev_redir(RESET_VECTOR + VA_WIDTH'('h40A));
    return e;
  endfunction
