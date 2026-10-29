// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd13_l1i.svh -- FD-13 L1I hit and miss
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     a 2-cycle hit returning a full line; a miss with an MSHR
//             fill; a second request merged onto the miss
//   program   a loop of 8 passes that fits one 64-byte line (hits);
//             then a call to X+0x30, the upper half of a cold line X, a
//             JAL from there back to X+0x00 and a return, run three
//             times to train the predictors and once more after a
//             FENCE.I has made every line cold and FD13_FILL fillers
//             (one 64-byte line) have followed it. The block at X+0x30
//             requests lines X and X+1 (IFU-7); the predicted block at X
//             then requests X again while its miss is in flight. Its
//             first line differs from the previous request (X+1), so
//             the IFU does not reuse it (TD-IFU-8) and the L1I merges it.
//             The fillers keep the fetch that runs past the FENCE.I
//             before its restart from reaching the call: without them
//             that fetch requests X after the invalidate, the fill
//             completes before the fourth call fetches X, and its second
//             request hits instead of merging (DOC-007)
//   waveform  the L1I request and response, the MSHR, the fill
//   trace     hits, misses, merges
//   proof     a hit answered by a bank, a miss reported by a bank, and a
//             request merged onto an MSHR register already fetching its
//             line
// ===================================================================

  // Fillers after the FENCE.I: 24, one 64-byte line. 12 is the fewest
  // that give the merge in the DOC-007 run; 0 and 6 give none.
  localparam int FD13_FILL = 24;

  task automatic prog_fd13();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] x;
    logic [VA_WIDTH-1:0] back;
    begin_scen("fd13_l1i", 1'b0);
    x = RESET_VECTOR + VA_WIDTH'('h800);
    W.mixed(2);
    // Hits: a loop within one line.
    top = W.wp;
    for (int it = 0; it < 8; it++) begin
      W.wp = top;
      W.mixed(6);
      W.bcc(it != 7, top);
    end
    // Train the path main -> X+0x30 -> X+0x00 -> main, three times,
    // by a call to X+0x30 that returns from X+0x06. The block at X+0x30
    // starts in the upper half of line X, so it requests lines X and X+1
    // (IFU-7); the JAL there goes back to X, whose first line is then
    // not the previous request's.
    for (int it = 0; it < 4; it++) begin
      if (it == 3) begin
        W.fence_i();                   // every line cold, predictors not
        W.mixed(FD13_FILL);            // past the fetch before the restart
      end
      back = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, x + VA_WIDTH'('h30));
      W.i16();
      W.jal(5'd0, x);                  // back into line X
      W.mixed(2);
      W.ret(back);
      W.mixed(1);
    end
    W.mixed(3);
    demo_go(40000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd13_l1i.md, in table order. X is
  // 0x8000_0800; the block at X+0x30 is 0x8000_0830; the FENCE.I at
  // 0x8000_002C, the restart at 0x8000_0030. The backend's redirect is
  // driven by the testbench: late.
  // =================================================================
  localparam logic [VA_WIDTH-1:0] FD13_X = RESET_VECTOR + VA_WIDTH'('h800);

  function automatic void fd13_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_L1I_miss", EV_WINDOW);
    evt_def("first_L1I_hit", EV_WINDOW);
    evt_def("the_invalidate_is_done", EV_WINDOW);
    evt_def("the_restart_after_the_FENCEI", EV_WINDOW, 1);
    evt_def("the_fourth_call_found_at_F3", EV_WINDOW, 0, 1);
    evt_def("the_merge", EV_WINDOW);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd13_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    e[1] = dut.u_l1i.b_mis_valid[0] || dut.u_l1i.b_mis_valid[1];
    e[2] = dut.u_l1i.b_rsp_valid[0] || dut.u_l1i.b_rsp_valid[1];
    e[3] = dut.l1i_ifu_inv_done;
    e[4] = ev_redir_any(RESET_VECTOR + VA_WIDTH'('h30));
    // The last predecode redirect to X+0x30: the fourth call.
    e[5] = ev_pd_redir(FD13_X + VA_WIDTH'('h30));
    // As the monitor's n_l1i_merge.
    e[6] = dut.u_l1i.u_mshr.accept && dut.u_l1i.u_mshr.mrg_hit;
    return e;
  endfunction
