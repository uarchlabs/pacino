// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd24_call_slot1.svh -- FD-24 A call in slot 1
// (planning/showcase/fe_demo_scenarios.md, DOC-006)
//
//   shows     a call in slot 1 behind a not-taken conditional in slot
//             0, the RAS push made from slot 1
//   program   a loop of 24 passes; its first block holds C, never
//             taken, then a jal x1 to f at +0x400; f returns to the
//             block that holds the back edge
//   waveform  the p2 slots, the RAS p2 operation and pointers
//   trace     RAS pushes from slot 1
//   proof     a p2 group the FTQ accepted whose slot 0 is a not-taken
//             conditional and whose slot 1, a call, is presented to the
//             RAS (w_ras_pred_val_p2); and a retired return whose
//             target the RAS supplied. Two-slot model only (Makefile
//             SCEN_2S): on the one-slot model the first count is 0
// ===================================================================

  localparam int FD24_ITERS = 24;

  task automatic prog_fd24();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] l;
    begin_scen("fd24_call_slot1", 1'b0);
    f = RESET_VECTOR + VA_WIDTH'('h400);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < FD24_ITERS; it++) begin
      W.wp = top;
      W.i16();
      W.cskip(1'b0, 1);                       // C, never taken
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, f);                         // the call
      W.mixed(2);                             // f
      W.ret(l);
      W.mixed(2);
      W.bcc(it != FD24_ITERS - 1, top);       // back edge
    end
    W.mixed(3);
    demo_go(80000);
  endtask
