// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd12_training.svh -- FD-12 Training
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     a resolution through ftq_upd_conv into the update queues,
//             the FTB update and its p0 bubble, the uBTB fill
//   program   tb_fe_top loops: nested counted loops (inner 6, outer 14)
//             with an always-taken conditional, an indirect jump and an
//             indirect call in the body, so every predictor is trained
//   waveform  ftq_resolve, ftq_upd_conv, the update queues, the FTB
//             update
//   trace     updates per predictor; FTB update bubbles
//   proof     an update reaches each of the uBTB, LP, FTB, TAGE, SC,
//             ITTAGE and the RAS commit; the FTB update holds p0
//             (ftq_npc H3) at least once
// ===================================================================

  task automatic prog_fd12();
    logic [VA_WIDTH-1:0] otop;
    logic [VA_WIDTH-1:0] itop;
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] link;
    int                  eo;
    int                  ei;
    begin_scen("fd12_training", 1'b0);
    W.mixed(4);
    fn   = RESET_VECTOR + VA_WIDTH'('h800);
    otop = W.wp;
    eo   = W.ne;
    W.mixed(2);
    itop = W.wp;
    ei   = W.ne;
    W.mixed(3);
    W.loop_br(itop);
    W.rep_iter(ei, 6);
    W.cond(1'b1, W.wp + VA_WIDTH'(12));            // always taken
    W.mixed(2);
    W.jalr_to(5'd0, 5'd7, W.wp + VA_WIDTH'('h40)); // indirect jump
    W.mixed(2);
    link = W.wp + VA_WIDTH'(4);
    W.jalr_to(5'd1, 5'd28, fn);                    // indirect call
    W.mixed(3);
    W.ret(link);
    W.mixed(1);
    W.loop_br(otop);
    W.rep_iter(eo, 14);
    W.mixed(3);
    demo_go(80000);
  endtask
