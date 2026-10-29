// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd15_faults.svh -- FD-15 Faults
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     a page fault, a guest-page fault and an access fault
//             carried into ifu_pd_pkt_t
//   program   S-mode under Sv39: a jump to an unmapped page (page
//             fault); a jump to a mapped page whose physical page PMP
//             entry 0 denies execute (access fault); then an ecall into
//             VS-mode (as FD-14) and a jump to a VA whose VS leaf names
//             a GPA the G-stage does not map (guest-page fault)
//   waveform  the ITLB response, the IFU fault path, the ibuf packet
//   trace     each fault at decode
//   proof     each of the three causes reaches decode on its packet with
//             the expected cause and VA
// ===================================================================

  task automatic prog_fd15();
    logic [PA_WIDTH-1:0]  pd;
    logic [GPA_WIDTH-1:0] g;
    begin_scen("fd15_faults", 1'b1);
    pmp_all(2);
    h2_tables();
    W.h_map4k(PC_V + VA_WIDTH'('h1000), GP_V + GPA_WIDTH'('h1000),
              PA_V + PA_WIDTH'('h1000));               // VS handlers
    map_ch();
    // Page fault: nothing mapped at T(0).
    W.jr_fault(tgt(0), IFU_FAULT_PAGE, hnd(0));
    W.mixed(2);
    // Access fault: T(1) mapped, its physical page without X in PMP.
    pd = PA_WIDTH'('h0_8140_0000);
    W.wr64(W.s_slot(tgt(1), 0), W.mk_pte(44'(pd >> 12), PTE_LEAF, 2'b00,
                                         1'b0));
    W.vmap[tgt(1)[VA_WIDTH-1:12]] = pd[PA_WIDTH-1:12];
    pmp_page(0, pd, 3'b011);
    W.jr_fault(tgt(1), IFU_FAULT_ACCESS, hnd(1));
    W.mixed(2);
    // To VS-mode at V; a guest-page fault at T(2): its VS leaf names
    // GPA g, which the G-stage does not map.
    ecall_to_vs();
    W.mixed(2);
    g = GPA_WIDTH'('h0_2000_0000);
    W.wr64(W.vs_slot(tgt(2), 0), W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00,
                                          1'b0));
    W.jr_gfault(tgt(2), FAULT_GPA_WIDTH'(g | GPA_WIDTH'('h10)), 2'b00,
                PC_V + VA_WIDTH'('h1000));
    W.mixed(4);
    demo_go(40000);
  endtask

  // =================================================================
  // The event checks (FDT-10c, tb/fe_demo_events.svh): one per row of
  // the Events table of docs/fd15_faults.md, in table order. The
  // targets tgt(0) 0x8040_0010 (VPN 0x80400, unmapped), tgt(1)
  // 0x8060_0010 (VPN 0x80600, PMP refuses), tgt(2) 0x8080_0010 (VPN
  // 0x80800, not G-mapped). A walk starts when the walker takes an ITLB
  // request; it answers on l2t_itlb_rsp_val, status 0 hit or 1 fault
  // (IL-4). The backend's trap redirect is driven by the testbench:
  // late.
  // =================================================================
  function automatic logic fd15_walk(input int vpn,
                                     input logic v);
    return itlb_l2t_req_val && itlb_l2t_req_rdy &&
           (itlb_l2t_vpn == (VA_WIDTH-12)'(vpn)) &&
           (itlb_l2t_v == v);
  endfunction

  // A walker answer: status st, and cause c on a fault or PPN p on a
  // hit.
  function automatic logic fd15_ans(input logic [1:0] st, input int c,
                                    input logic [PPN_WIDTH-1:0] p);
    return l2t_itlb_rsp_val && (l2t_itlb_status == st) &&
           ((st == 2'd1) ? (l2t_itlb_cause == CAUSE_WIDTH'(c))
                         : (l2t_itlb_ppn == p));
  endfunction

  // Decode's lane 0 holds the faulting fetch at pc with cause f.
  function automatic logic fd15_dec(input logic [VA_WIDTH-1:0] pc,
                                    input ifu_fault_e f);
    return pd_out[0].valid && (pd_out[0].start_pc == pc) &&
           (pd_out[0].fault_cause == f);
  endfunction

  function automatic void fd15_evt_defs();
    evt_def("reset_released", EV_EXACT);
    evt_def("walk_for_VPN_0x80400", EV_WINDOW);
    evt_def("the_walker_answers_a_page_fault", EV_WINDOW);
    evt_def("the_page_fault_reaches_decode", EV_WINDOW);
    evt_def("walk_for_VPN_0x80600", EV_WINDOW);
    evt_def("the_walker_answers_a_hit", EV_WINDOW);
    evt_def("the_access_fault_reaches_decode", EV_WINDOW);
    evt_def("the_ecalls_trap_redirect_to_V", EV_WINDOW, 1);
    evt_def("walk_for_VPN_0x80800", EV_WINDOW);
    evt_def("the_walker_answers_cause_20", EV_WINDOW);
    evt_def("the_third_fault_reaches_decode", EV_WINDOW);
    evt_def("the_run_ends", EV_WINDOW);
  endfunction

  function automatic logic [EV_MAX-1:0] fd15_evt_now();
    logic [EV_MAX-1:0] e;
    e     = '0;
    e[0]  = ev_p0(RESET_VECTOR);
    e[1]  = fd15_walk('h80400, 1'b0);
    e[2]  = fd15_ans(2'd1, 12, '0);
    e[3]  = fd15_dec(tgt(0), IFU_FAULT_PAGE);
    e[4]  = fd15_walk('h80600, 1'b0);
    e[5]  = fd15_ans(2'd0, 0, PPN_WIDTH'('h81400));
    e[6]  = fd15_dec(tgt(1), IFU_FAULT_ACCESS);
    e[7]  = ev_redir_any(PC_V);
    e[8]  = fd15_walk('h80800, 1'b1);
    e[9]  = fd15_ans(2'd1, 20, '0);
    e[10] = fd15_dec(tgt(2), IFU_FAULT_GUEST_PAGE);
    return e;
  endfunction
