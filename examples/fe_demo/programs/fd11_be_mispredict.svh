// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd11_be_mispredict.svh -- FD-11 Backend mispredict
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     the backend redirect: FTQ squash, IFU flush, history
//             rollback and correction, RAS restore
//   program   tb_fe_top misp_call: a conditional with a pseudo-random
//             outcome (LFSR seed ACE1), then a call and its return, 32
//             passes
//   waveform  the backend resolution, the FTQ squash, bp_history, the
//             RAS restore
//   trace     backend redirects; the fetch that follows
//   proof     a backend mispredict redirect whose first following fetch
//             from the FTQ starts at the redirect PC
// ===================================================================

  task automatic prog_fd11();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] l;
    begin_scen("fd11_be_mispredict", 1'b0);
    W.lfsr = 16'hACE1;
    fn = RESET_VECTOR + VA_WIDTH'('h400);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 32; it++) begin
      W.wp = top;
      W.mixed(1);
      W.cskip(W.lfsr_bit(), 1);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, fn);
      W.mixed(2);
      W.ret(l);
      W.mixed(1);
      W.bcc(it != 31, top);
    end
    W.mixed(3);
    demo_go(80000);
  endtask
