// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd05_p3_override.svh -- FD-5 p3 override
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     SC reversing the TAGE direction and the p3 redirect
//   program   tb_fe_top hist: two conditionals whose outcomes depend on
//             history (one alternates, one is taken every third pass),
//             96 passes; TAGE predicts them weakly while it learns and
//             SC reverses some of its directions
//   waveform  TAGE p2, SC p3, bpu_redir_p3
//   trace     p3 redirects whose slot SC decided
//   proof     a p3 redirect the FTQ accepted whose slot has pred_src
//             PRED_SC
// ===================================================================

  task automatic prog_fd05();
    logic [VA_WIDTH-1:0] top;
    begin_scen("fd05_p3_override", 1'b0);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 96; it++) begin
      W.wp = top;
      W.mixed(2);
      W.cskip((it % 2) == 1, 2);              // A
      W.mixed(1);
      W.cskip((it % 3) == 2, 2);              // B
      W.mixed(1);
      W.bcc(it != 95, top);
    end
    W.mixed(3);
    demo_go(80000);
  endtask
