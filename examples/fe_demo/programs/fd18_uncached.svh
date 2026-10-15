// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd18_uncached.svh -- FD-18 Uncached fetch
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     fetch from an NC page, one instruction per FTQ entry
//   program   tb_fe_top uc_nc: S-mode under Sv39, a cacheable page c and
//             a page u with PBMT NC; jumps into u, branches, a loop and
//             a call within it, a jump and a return out
//   waveform  the IFU uncached path, the L1I uncached request, the
//             commit gate
//   trace     uncached requests
//   proof     uncached requests taken by the L1I, and no line of the NC
//             page written into the L1I
// ===================================================================

  task automatic prog_fd18();
    logic [VA_WIDTH-1:0] c;
    logic [VA_WIDTH-1:0] u;
    logic [VA_WIDTH-1:0] link;
    logic [VA_WIDTH-1:0] top;
    int                  e0;
    begin_scen("fd18_uncached", 1'b1);
    eager = 1'b1;
    c = VA_WIDTH'('h0_8001_0000);
    u = VA_WIDTH'('h0_8001_1000);
    W.map4k(RESET_VECTOR, PA_WIDTH'(RESET_VECTOR));
    W.map4k(c, PA_WIDTH'('h0_8100_0000));
    W.map4k_pbmt(u, PA_WIDTH'('h0_8120_3000), 2'd1);  // NC
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, c);
    W.mixed(4);
    W.jal(5'd0, u + VA_WIDTH'('h10));       // into u
    W.mixed(3);
    W.cskip(1'b1, 2);                       // within: taken
    W.mixed(2);
    W.cskip(1'b0, 1);                       // within: not taken
    W.jal(5'd0, u + VA_WIDTH'('h200));      // within: a jump
    top = W.wp;
    e0  = W.ne;
    W.mixed(2);
    W.loop_br(top);
    W.rep_iter(e0, 3);                      // within: a loop
    W.mixed(2);
    W.jal(5'd0, c + VA_WIDTH'('h200));      // out of u
    W.mixed(3);
    link = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, u + VA_WIDTH'('h400));      // a call into u
    W.mixed(2);
    W.ret(link);                            // a return out of it
    W.mixed(2);
    demo_go(40000);
  endtask
