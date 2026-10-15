// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd20_backpressure.svh -- FD-20 Backpressure
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     ibuf full, FTQ full and a stalled decode, and where each
//             stall starts
//   program   a loop of 40 passes over 24 instructions with the backend
//             accepting decode's output one cycle in four (be_rdy_pat 4,
//             the provisional answer to FD-U2)
//   waveform  the ibuf occupancy, the FTQ pointers, the p0 request
//   trace     the stalls
//   proof     cycles with the ibuf refusing the IFU, with the FTQ full,
//             with decode holding a bundle while dec_ibuf_rdy is low,
//             and with no p0 request
// ===================================================================

  task automatic prog_fd20();
    logic [VA_WIDTH-1:0] top;
    begin_scen("fd20_backpressure", 1'b0);
    be_rdy_pat = 4;
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 40; it++) begin
      W.wp = top;
      W.mixed(23);
      W.bcc(it != 39, top);
    end
    W.mixed(3);
    demo_go(80000);
  endtask
