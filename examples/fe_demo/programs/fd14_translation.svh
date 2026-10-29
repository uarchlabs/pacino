// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd14_translation.svh -- FD-14 Translation
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     an ITLB miss and an Sv39 walk; a nested Sv39x4 walk; a
//             Svadu A-bit update by compare-and-swap
//   program   S-mode under satp Sv39 with menvcfg.ADUE set: the code
//             page C has a leaf with A clear, so its walk sets A by CAS;
//             then an ecall whose trap enters VS-mode (V=1, vsatp Sv39,
//             hgatp Sv39x4) at page V, whose fetch walks both stages
//   waveform  the ITLB, the walker, the walker memory port
//   trace     walks by kind; the CAS
//   proof     a single-stage walk (V=0); a walk with V=1 in which the
//             walker evaluates G-stage PTEs; a compare-and-swap on the
//             walker memory port
//
// The regime change rides on the trap: be_trap_hook
// (tb/fe_demo_mon.svh) applies the V=1 CSRs when the ecall retires,
// standing in for the trap to M-mode and the return to VS-mode that
// software would run.
// ===================================================================

  task automatic prog_fd14();
    begin_scen("fd14_translation", 1'b1);
    csr_menv_adue(1'b1);                              // Svadu
    h2_tables();
    W.map4k(RESET_VECTOR, PA_WIDTH'(RESET_VECTOR));
    W.map4k(PC_H, PA_H);
    // C: a leaf with A clear.
    W.wr64(W.s_slot(PC_C, 0),
           W.mk_pte(44'(PA_C >> 12), PTE_LEAF & 8'hBF, 2'b00, 1'b0));
    W.vmap[PC_C[VA_WIDTH-1:12]] = PA_C[PA_WIDTH-1:12];
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, PC_C);
    W.mixed(8);
    ecall_to_vs();                                    // to VS-mode at V
    W.mixed(8);
    demo_go(40000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd14_translation.md, in table order. A
  // walk starts when the walker takes an ITLB request
  // (itlb_l2t_req_val and _rdy); it answers on l2t_itlb_rsp_val, status
  // 0 hit or 1 fault (IL-4). C is VPN 0x80010, V (PC_V) VPN 0x80050.
  // The walker and the ITLB are design registers; the backend's trap
  // redirect is driven by the testbench: late.
  // =================================================================
  // A walk taken for VPN vpn, with V = v.
  function automatic logic fd14_walk(input int vpn,
                                     input logic v);
    return itlb_l2t_req_val && itlb_l2t_req_rdy &&
           (itlb_l2t_vpn == (VA_WIDTH-12)'(vpn)) &&
           (itlb_l2t_v == v);
  endfunction

  function automatic void fd14_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("first_walk", EV_WINDOW);
    evt_def("walk_for_C", EV_WINDOW);
    evt_def("the_CAS", EV_WINDOW);
    evt_def("the_walk_for_C_answers_PPN", EV_WINDOW);
    evt_def("first_nested_walk", EV_WINDOW);
    evt_def("the_ecalls_trap_redirect_to_V", EV_WINDOW, 1);
    evt_def("the_nested_walk_for_C_ends", EV_WINDOW);
    evt_def("walk_for_V", EV_WINDOW);
    evt_def("the_walk_for_V_answers_PPN", EV_WINDOW);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd14_evt_now();
    logic [EV_MAX-1:0] e;
    e     = '0;
    e[0]  = ev_p0(RESET_VECTOR);
    e[1]  = fd14_walk('h80000, 1'b0);
    e[2]  = fd14_walk('h80010, 1'b0);
    // The walker's compare-and-swap (as the monitor's n_cas).
    e[3]  = ptw_mem_req_val && ptw_mem_req_rdy && ptw_mem_req_op;
    e[4]  = l2t_itlb_rsp_val && (l2t_itlb_status == 2'd0) &&
            (l2t_itlb_ppn == PPN_WIDTH'('h81000));
    e[5]  = fd14_walk('h80010, 1'b1);
    e[6]  = ev_redir_any(PC_V);
    e[7]  = l2t_itlb_rsp_val && (l2t_itlb_status == 2'd1) &&
            (l2t_itlb_cause == CAUSE_WIDTH'(12));
    e[8]  = fd14_walk('h80050, 1'b1);
    e[9]  = l2t_itlb_rsp_val && (l2t_itlb_status == 2'd0) &&
            (l2t_itlb_ppn == PPN_WIDTH'('h81600));
    return e;
  endfunction
