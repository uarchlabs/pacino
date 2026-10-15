// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd16_page_cross.svh -- FD-16 Page-crossing block
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     a block crossing a page, with two translations
//   program   S-mode under Sv39: two virtually adjacent, physically
//             discontiguous code pages; a jump to 16 bytes before the
//             first page's end, c.addi to its last halfword and a 32-bit
//             instruction straddling the page boundary
//   waveform  the IFU translation queue, the two ITLB lookups
//   trace     a block with two translations
//   proof     a translation-queue entry popped with xq_cross set and two
//             different PPNs
// ===================================================================

  task automatic prog_fd16();
    logic [VA_WIDTH-1:0] b;
    begin_scen("fd16_page_cross", 1'b1);
    b = VA_WIDTH'('h0_8001_0000);
    W.map4k(RESET_VECTOR, PA_WIDTH'(RESET_VECTOR));
    W.map4k(b,                     PA_WIDTH'('h0_8100_0000));
    W.map4k(b + VA_WIDTH'('h1000), PA_WIDTH'('h0_8120_5000));
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, b + VA_WIDTH'('hFF0));
    while (W.wp != b + VA_WIDTH'('hFFE)) W.i16();
    W.i32(ADDI_T0);                                   // straddles the page
    W.mixed(8);
    demo_go(40000);
  endtask
