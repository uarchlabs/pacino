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
