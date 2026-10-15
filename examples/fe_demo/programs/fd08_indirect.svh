// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd08_indirect.svh -- FD-8 Indirect jump
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     ITTAGE predicting an indirect target
//   program   tb_fe_top indir: an indirect jump and an indirect call
//             whose targets alternate, each after a conditional that
//             alternates with them, 40 passes
//   waveform  ITTAGE p2, the FTB target, the p2 target selection
//   trace     ITTAGE-supplied targets
//   proof     a retired indirect jump or call whose FTQ entry's final
//             slot for it has pred_src PRED_ITTAGE and the right target
// ===================================================================

  task automatic prog_fd08();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] ta;
    logic [VA_WIDTH-1:0] tb;
    logic [VA_WIDTH-1:0] jn;
    logic [VA_WIDTH-1:0] fa;
    logic [VA_WIDTH-1:0] fb;
    logic [VA_WIDTH-1:0] l;
    logic                odd;
    begin_scen("fd08_indirect", 1'b0);
    ta = RESET_VECTOR + VA_WIDTH'('h400);
    tb = RESET_VECTOR + VA_WIDTH'('h480);
    jn = RESET_VECTOR + VA_WIDTH'('h500);
    fa = RESET_VECTOR + VA_WIDTH'('h600);
    fb = RESET_VECTOR + VA_WIDTH'('h680);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 40; it++) begin
      odd = (it % 2) == 1;
      W.wp = top;
      W.mixed(1);
      W.cskip(odd, 1);
      W.jalr_to(5'd0, 5'd7, odd ? ta : tb);   // indirect jump
      if (odd) W.mixed(2);
      else     W.mixed(1);
      W.jal(5'd0, jn);
      W.mixed(1);
      W.cskip(!odd, 1);
      l = W.wp + VA_WIDTH'(4);
      W.jalr_to(5'd1, 5'd28, odd ? fa : fb);  // indirect call
      if (odd) W.mixed(2);
      else     W.mixed(1);
      W.ret(l);
      W.mixed(1);
      W.exit_or_jal(it == 39, top);
    end
    W.mixed(3);
    demo_go(80000);
  endtask
