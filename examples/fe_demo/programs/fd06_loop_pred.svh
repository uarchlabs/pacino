// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd06_loop_pred.svh -- FD-6 Loop predictor
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     the loop predictor taking over a loop and predicting its
//             exit
//   program   tb_fe_top lp: an inner loop of 10 inside an outer loop of
//             16, so the inner loop branch has the same trip count every
//             time
//   waveform  the loop predictor entry, the p1 mux, the loop exit
//   trace     LP predictions; the exit
//   proof     a retired loop exit (not taken) whose FTQ entry's final
//             slot for it has pred_src PRED_LOOP and predicts not taken
// ===================================================================

  task automatic prog_fd06();
    logic [VA_WIDTH-1:0] otop;
    logic [VA_WIDTH-1:0] itop;
    begin_scen("fd06_loop_pred", 1'b0);
    W.mixed(3);
    otop = W.wp;
    for (int o = 0; o < 16; o++) begin
      W.wp = otop;
      W.mixed(2);
      itop = W.wp;
      for (int i = 0; i < 10; i++) begin
        W.wp = itop;
        W.mixed(3);
        W.bcc(i != 9, itop);
      end
      W.mixed(2);
      W.bcc(o != 15, otop);
    end
    W.mixed(3);
    demo_go(80000);
  endtask
