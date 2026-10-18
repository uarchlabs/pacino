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
