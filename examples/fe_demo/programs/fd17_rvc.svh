// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd17_rvc.svh -- FD-17 Compressed and unaligned code
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     a 34-byte block, and a 32-bit instruction straddling two
//             blocks
//   program   mixed 16- and 32-bit code from the reset vector with a
//             32-bit instruction at +0x3E, across the 64-byte line; then
//             a loop of compressed control transfers (c.bnez, c.jalr,
//             c.jr, c.j, c.beqz) entered at unaligned block starts
//   waveform  the IFU expansion, predecode, the ibuf slots
//   trace     the straddling instruction
//   proof     a 32-bit instruction in the last halfword of its block (a
//             34-byte block) delivered whole, with the expected
//             encoding; 16-bit instructions retired
// ===================================================================

  task automatic prog_fd17();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] l;
    logic [VA_WIDTH-1:0] b;
    begin_scen("fd17_rvc", 1'b0);
    fn = RESET_VECTOR + VA_WIDTH'('h400);
    W.mixed(20);
    while (W.wp != RESET_VECTOR + VA_WIDTH'('h3E)) W.i16();
    W.i32(ADDI_T0);                                   // straddles 0x40
    W.mixed(5);
    top = W.wp;
    for (int it = 0; it < 8; it++) begin
      W.wp = top;
      W.i16();
      b = W.wp;
      W.cbz(1'b1, (it % 2) == 1, b + VA_WIDTH'(4));   // skips one c.addi
      if ((it % 2) == 0) W.i16();
      else               W.fill_dry_at(b + VA_WIDTH'(2), 2);
      W.i32(ADDI_T0);
      l = W.wp + VA_WIDTH'(2);
      W.cjalr(5'd1, fn);
      W.i16();
      W.i32(ADDI_T0);
      W.cjr(5'd1, l);
      W.i16();
      b = W.wp;
      W.cj(b + VA_WIDTH'(8));
      W.fill_dry_at(b + VA_WIDTH'(2), 6);
      W.i16();
      W.cbz(1'b0, it != 7, top);
    end
    W.mixed(3);
    demo_go(40000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd17_rvc.md, in table order. The 32-bit
  // instruction at 0x8000_003E straddles the block end at 0x8000_0040;
  // fn is 0x8000_0400. Every condition is on design registers.
  // =================================================================
  function automatic void fd17_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("the_straddling_instruction_reaches_decode", EV_WINDOW);
    evt_def("the_next_bundle_starts_on_its", EV_WINDOW);
    evt_def("first_fetch_of_fn", EV_WINDOW);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd17_evt_now();
    logic [EV_MAX-1:0] e;
    e    = '0;
    e[0] = ev_p0(RESET_VECTOR);
    // Lane 4: the 32-bit instruction at position 15 of the block, with
    // the straddle register set for the next block's start.
    e[1] = pd_out[4].valid && !pd_out[4].is_rvc && (pd_out[4].pos == 4'd15) &&
           (pd_out[4].start_pc == RESET_VECTOR + VA_WIDTH'('h3E)) &&
           dut.u_ifu.u_f3.r_strad_val &&
           (dut.u_ifu.u_f3.r_strad_pc == RESET_VECTOR + VA_WIDTH'('h40));
    e[2] = pd_out[0].valid && (pd_out[0].pos == 4'd1) &&
           (pd_out[0].start_pc == RESET_VECTOR + VA_WIDTH'('h42));
    e[3] = dut.ftq_ifu_req_val && dut.ftq_ifu_req_rdy &&
           !dut.ftq_ifu_flush_val &&
           (dut.ftq_ifu_start_pc == RESET_VECTOR + VA_WIDTH'('h400));
    return e;
  endfunction
