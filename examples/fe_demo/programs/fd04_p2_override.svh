// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd04_p2_override.svh -- FD-4 p2 override
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     the FTB disagreeing with the uBTB and the p2 redirect
//   program   tb_fe_top ftbonly: eight blocks 0x800 apart chained by
//             taken conditionals; they share one 4-way uBTB set, so the
//             uBTB holds at most four of them while the FTB holds all
//             eight
//   waveform  uBTB p1, FTB p2, bpu_redir_p2, the FTQ rewrite
//   trace     p2 redirects
//   proof     a p2 redirect the FTQ accepted
// ===================================================================

  task automatic prog_fd04();
    logic [VA_WIDTH-1:0] b [0:7];
    logic [VA_WIDTH-1:0] ex_pc;
    begin_scen("fd04_p2_override", 1'b0);
    for (int k = 0; k < 8; k++)
      b[k] = RESET_VECTOR + VA_WIDTH'('h1000 + k * 'h800);
    W.mixed(3);
    W.jal(5'd0, b[0]);
    for (int it = 0; it < 16; it++) begin
      for (int k = 0; k < 7; k++) begin
        W.wp = b[k];
        W.mixed(2);
        W.bcc(1'b1, b[k+1]);
      end
      W.wp = b[7];
      W.mixed(1);
      ex_pc = W.wp + VA_WIDTH'(8);
      W.bcc(it == 15, ex_pc);                 // exit on the last pass
      if (it != 15) W.jal(5'd0, b[0]);
      else          W.d_jal_fill();
    end
    W.mixed(3);
    demo_go(40000);
  endtask
