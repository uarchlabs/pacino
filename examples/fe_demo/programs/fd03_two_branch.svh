// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd03_two_branch.svh -- FD-3 Two branches in one block
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     both prediction slots used by one block
//   program   tb_fe_top twocond: two blocks, each alone in its 32-byte
//             region with two conditionals, in a loop of 24
//   waveform  uBTB p1 and FTB p2 slot outputs, both slots
//   trace     a block predicted with two slots
//   proof     a p1 prediction or a p2 slot group the FTQ accepted with
//             both slots valid
// ===================================================================

  task automatic prog_fd03();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] x;
    logic [VA_WIDTH-1:0] y;
    logic [VA_WIDTH-1:0] back;
    begin_scen("fd03_two_branch", 1'b0);
    x = RESET_VECTOR + VA_WIDTH'('h400);
    y = RESET_VECTOR + VA_WIDTH'('h440);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 24; it++) begin
      W.wp = top;
      W.i16();
      W.jal(5'd0, x);
      back = top + VA_WIDTH'(6);
      W.i16();
      W.cskip(1'b0, 1);                     // X c1, never taken
      W.cskip(1'b1, 1);                     // X c2, always taken
      W.i16();
      W.jal(5'd0, y);
      W.i16();
      W.cskip((it % 2) == 1, 1);            // Y c1, alternates
      W.cskip(1'b0, 1);                     // Y c2, never taken
      W.i16();
      W.jal(5'd0, back);
      W.mixed(1);
      W.bcc(it != 23, top);
    end
    W.mixed(3);
    demo_go(40000);
  endtask
