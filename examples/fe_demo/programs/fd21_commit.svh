// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd21_commit.svh -- FD-21 Commit
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     the commit pointer advancing and the RAS commit stack
//   program   tb_fe_top calls: main calls f, f calls g then h, each
//             returns, six passes
//   waveform  the FTQ commit pointer, the RAS commit stack
//   trace     commits
//   proof     the FTQ commit pointer advances (in at least 16 cycles),
//             and the RAS commit stack changes
// ===================================================================

  task automatic prog_fd21();
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] g;
    logic [VA_WIDTH-1:0] h;
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] lm;
    logic [VA_WIDTH-1:0] lf1;
    logic [VA_WIDTH-1:0] lf2;
    int                  e0;
    begin_scen("fd21_commit", 1'b0);
    f = RESET_VECTOR + VA_WIDTH'('h800);
    g = RESET_VECTOR + VA_WIDTH'('hA00);
    h = RESET_VECTOR + VA_WIDTH'('hC00);
    W.mixed(3);
    top = W.wp;
    e0  = W.ne;
    while (W.wp != RESET_VECTOR + VA_WIDTH'('h1C)) W.i16();
    lm  = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, f);                          // main calls f
    W.mixed(3);
    while (W.wp != f + VA_WIDTH'('h1C)) W.i16();
    lf1 = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, g);                          // f calls g
    W.mixed(2);
    W.ret(lf1);                              // g returns
    W.mixed(1);
    while (W.wp != f + VA_WIDTH'('h3C)) W.i16();
    lf2 = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, h);                          // f calls h
    W.mixed(2);
    W.ret(lf2);                              // h returns
    W.mixed(1);
    W.ret(lm);                               // f returns to main
    W.mixed(1);
    W.loop_br(top);
    W.rep_iter(e0, 6);
    W.mixed(3);
    demo_go(40000);
  endtask
