// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd18_uncached.svh -- FD-18 Uncached fetch
// (planning/showcase/fe_demo_scenarios.md, DOC-001, DOC-003)
//
//   shows     fetch from an NC page and from an IO page, one instruction
//             per FTQ entry
//   program   tb_fe_top uc_nc: S-mode under Sv39, a cacheable page c and
//             a page u with PBMT NC; jumps into u, branches, a loop and
//             a call within it, a jump and a return out. Then (DOC-003)
//             a page io with PBMT IO: a jump into io, a taken branch
//             within it, a jump out
//   waveform  the IFU uncached path, the L1I uncached request, the
//             commit gate
//   trace     uncached requests, by page
//   proof     uncached requests taken by the L1I from each page, and no
//             line of either page written into the L1I
// ===================================================================

  task automatic prog_fd18();
    logic [VA_WIDTH-1:0] c;
    logic [VA_WIDTH-1:0] u;
    logic [VA_WIDTH-1:0] io;
    logic [VA_WIDTH-1:0] link;
    logic [VA_WIDTH-1:0] top;
    int                  e0;
    begin_scen("fd18_uncached", 1'b1);
    eager = 1'b1;
    c = VA_WIDTH'('h0_8001_0000);
    u = VA_WIDTH'('h0_8001_1000);
    io = VA_WIDTH'('h0_8001_2000);
    W.map4k(RESET_VECTOR, PA_WIDTH'(RESET_VECTOR));
    W.map4k(c, PA_WIDTH'('h0_8100_0000));
    W.map4k_pbmt(u, PA_WIDTH'('h0_8120_3000), 2'd1);  // NC
    W.map4k_pbmt(io, PA_WIDTH'('h0_8120_4000), 2'd2); // IO
    io_ppn[PPN_WIDTH'('h8_1204)] = 1'b1;
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
    W.jal(5'd0, io + VA_WIDTH'('h10));      // into io
    W.mixed(3);
    W.cskip(1'b1, 2);                       // within: taken
    W.mixed(2);
    W.jal(5'd0, c + VA_WIDTH'('h300));      // out of io
    W.mixed(2);
    demo_go(40000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd18_uncached.md, in table order. Page u
  // (NC) is PA page 0x81203, page io (IO) 0x81204; the loop on u at
  // u+0x200 is line 0x8120_3200 and the function at u+0x400 line
  // 0x8120_3400. Every condition is on design registers.
  // =================================================================
  // An uncached L1I request taken, for the line at pa, or on PA page
  // pg when pa is 0.
  function automatic logic fd18_uc(input logic [PA_WIDTH-1:0] pa,
                                   input int pg);
    return dut.ifu_l1i_req_val && dut.ifu_l1i_req_rdy &&
           dut.ifu_l1i_req_uncached &&
           ((pa != '0) ? (dut.ifu_l1i_req_paddr == pa)
                       : (dut.ifu_l1i_req_paddr[PA_WIDTH-1:12] ==
                          (PA_WIDTH-12)'(pg)));
  endfunction

  function automatic void fd18_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_uncached_request", EV_WINDOW);
    evt_def("first_uncached_block_closed_after_one", EV_WINDOW);
    evt_def("first_request_for_0x8120_3200", EV_WINDOW);
    evt_def("first_request_for_0x8120_3400", EV_WINDOW);
    evt_def("first_uncached_request_from_the_IO", EV_WINDOW);
    evt_def("last_uncached_request", EV_WINDOW, 0, 1);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd18_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    e[1] = fd18_uc('0, 'h81203);
    // F3 ends an uncached block after its first instruction.
    e[2] = dut.ifu_ftq_pdwb_val && dut.ifu_ftq_uc_end;
    e[3] = fd18_uc(PA_WIDTH'('h8120_3200), 0);
    e[4] = fd18_uc(PA_WIDTH'('h8120_3400), 0);
    e[5] = fd18_uc('0, 'h81204);
    e[6] = dut.ifu_l1i_req_val && dut.ifu_l1i_req_rdy &&
           dut.ifu_l1i_req_uncached;
    return e;
  endfunction
