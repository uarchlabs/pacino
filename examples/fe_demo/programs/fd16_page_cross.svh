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

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd16_page_cross.md, in table order. The
  // crossing block starts at b + 0xFF0, 0x8001_0FF0; its pages are VPN
  // 0x80010 (PPN 0x81000) and 0x80011 (PPN 0x81205). Every condition
  // is on design registers or the walker's.
  // =================================================================
  function automatic logic fd16_walk(input int vpn);
    return itlb_l2t_req_val && itlb_l2t_req_rdy &&
           (itlb_l2t_vpn == (VA_WIDTH-12)'(vpn));
  endfunction

  function automatic logic fd16_l1i(input logic [PA_WIDTH-1:0] pa);
    return dut.ifu_l1i_req_val && dut.ifu_l1i_req_rdy &&
           (dut.ifu_l1i_req_paddr == pa);
  endfunction

  function automatic void fd16_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("walk_for_VPN_0x80010", EV_WINDOW);
    evt_def("walk_for_VPN_0x80011", EV_WINDOW);
    evt_def("L1I_request_for_0x8100_0FC0", EV_WINDOW);
    evt_def("the_translation_queue_entry_of_the", EV_WINDOW);
    evt_def("the_second_line_returns", EV_WINDOW);
    evt_def("the_straddling_instruction_reaches_decode", EV_WINDOW);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd16_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    e[1] = fd16_walk('h80010);
    e[2] = fd16_walk('h80011);
    e[3] = fd16_l1i(PA_WIDTH'('h8100_0FC0));
    // As the monitor's n_xq_cross, with the two PPNs.
    e[4] = dut.u_ifu.u_xlate.xq_val && dut.u_ifu.u_xlate.xq_pop &&
           dut.u_ifu.u_xlate.xq_cross &&
           (dut.u_ifu.u_xlate.xq_ppn0 == PPN_WIDTH'('h81000)) &&
           (dut.u_ifu.u_xlate.xq_ppn1 == PPN_WIDTH'('h81205));
    // The response to the block's second line, id 1 in this run: the first
    // response with that id after the crossing entry is counted.
    e[5] = dut.l1i_ifu_rsp_val && (int'(dut.l1i_ifu_rsp_id) == 1) &&
           (n_xq_cross > 0);
    // The 32-bit instruction at b + 0xFFE, whole, in lane 7 of the bundle.
    e[6] = pd_out[7].valid && !pd_out[7].is_rvc &&
           (pd_out[7].start_pc == VA_WIDTH'('h0_8001_0FFE));
    return e;
  endfunction
