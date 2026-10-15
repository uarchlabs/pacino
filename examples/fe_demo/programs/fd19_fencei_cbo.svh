// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd19_fencei_cbo.svh -- FD-19 FENCE.I and cbo.inval
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     the drain, the invalidate and the restart
//   program   a function called twice, rewritten by a store, a FENCE.I,
//             and called again (the new code runs); then a second
//             function the same way with a cbo.inval of its line, after
//             a mispredicted branch and before cold code, so fills are
//             in flight when the L1I takes the invalidate
//   waveform  the IFU maintenance, the L1I invalidate, done, the restart
//   trace     the maintenance handshake
//   proof     an invalidate of all lines (FENCE.I) and of one line
//             (cbo.inval) taken by the L1I, two invalidate done pulses,
//             and after each IFU ack the first fetch starts at the
//             instruction after the maintenance operation
// ===================================================================

  task automatic prog_fd19();
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] g;
    begin_scen("fd19_fencei_cbo", 1'b0);
    f = RESET_VECTOR + VA_WIDTH'('h800);
    g = RESET_VECTOR + VA_WIDTH'('hC40);
    W.mixed(3);
    smc_fn(f, 2);
    W.mixed(2);
    smc_store(f);
    W.mixed(2);
    W.fence_i();
    W.mixed(2);
    smc_call_new(f);
    W.mixed(2);
    smc_fn(g, 2);
    smc_store(g);
    W.cskip(1'b1, 1);                       // taken, cold: mispredicted
    W.cbo_inval(5'd10, PA_WIDTH'(g) + PA_WIDTH'('h24));
    W.mixed(60);                            // cold lines after it
    smc_call_new(g);
    W.mixed(2);
    demo_go(40000);
  endtask
