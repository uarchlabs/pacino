// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd02_steady.svh -- FD-2 Steady-state prediction and fetch
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     one block per cycle: p0 request, uBTB answer at p1, FTQ
//             allocation, the next p0 the cycle after
//   program   straight-line code with no branches: 512 32-bit
//             instructions, 2 KiB, 32 lines, then the end
//   waveform  bp_cluster p0/p1, FTQ pointers, IFU F0-F3, ibuf, decode
//   trace     one allocation per cycle; full decode bundles
//   proof     at least 4 consecutive cycles of FTQ allocation, and at
//             least 4 consecutive cycles in which decode delivered SLOTS
//             (8) instructions
// ===================================================================

  task automatic prog_fd02();
    begin_scen("fd02_steady", 1'b0);
    for (int i = 0; i < 512; i++) W.i32(ADDI_T0);
    demo_go(20000);
  endtask
