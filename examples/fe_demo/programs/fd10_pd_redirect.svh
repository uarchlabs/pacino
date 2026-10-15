// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd10_pd_redirect.svh -- FD-10 Predecode redirect
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     a JAL the predictors did not report, found at F3
//   program   tb_fe_top jals: a chain of twelve JALs to distinct blocks,
//             run three times; on the first pass none is known to the
//             uBTB or FTB
//   waveform  IFU F3, the predecode writeback, the FTQ redirect, the IFU
//             flush
//   trace     predecode redirects
//   proof     a predecode redirect the FTQ took (no backend redirect
//             that cycle)
// ===================================================================

  task automatic prog_fd10();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] t;
    begin_scen("fd10_pd_redirect", 1'b0);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 3; it++) begin
      W.wp = top;
      W.mixed(1);
      for (int k = 0; k < 12; k++) begin
        t = RESET_VECTOR + VA_WIDTH'('h200 + k * 'h60);
        W.jal(5'd0, t);
        W.mixed(2);
      end
      W.jal(5'd0, top + VA_WIDTH'('h100));
      W.wp = top + VA_WIDTH'('h100);
      W.mixed(1);
      W.bcc(it != 2, top);
    end
    W.mixed(3);
    demo_go(40000);
  endtask
