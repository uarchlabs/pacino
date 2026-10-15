// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd01_reset_init.svh -- FD-1 Reset and SRAM initialization
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     the full init walk of the predictor tables, ending with
//             every predictor ready
//   program   a loop of 3000 passes over 7 instructions, long enough
//             to outlast the longest walk; reset without the fast-init
//             options (FDT-7: this scenario alone)
//   waveform  the TAGE, ITTAGE and SC sram_init walks and readies, the
//             RAS reset walk, the first p0 request and p1 prediction
//   trace     none until DOC-002
//   proof     as FD-1 gives it: each of the TAGE, ITTAGE and SC readies
//             is seen low after reset and then rises, and the first p1
//             prediction the FTQ accepts is no earlier than the last of
//             them. The first response and update of each queued
//             predictor are reported beside it
//
// THIS DESIGN DOES NOT MEET THE PROOF (DOC-001 Results Capture). The
// FTQ predicts from the first cycle after reset: nothing reads the
// three readies (fe_top ends them on unread wires), and ITTAGE and TAGE
// answer predictions before their own walks end.
// ===================================================================

  // Passes of the loop: enough to outlast the longest walk, TAGE's
  // 2048 entries (TAGE_MAX_IDX_WIDTH 11), at about one pass a cycle.
  localparam int FD01_ITERS = 3000;

  task automatic prog_fd01();
    logic [VA_WIDTH-1:0] top;
    begin_scen("fd01_reset_init", 1'b0);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < FD01_ITERS; it++) begin
      W.wp = top;
      W.mixed(6);
      W.bcc(it != FD01_ITERS - 1, top);
    end
    W.mixed(3);
    demo_go(40000);
  endtask
