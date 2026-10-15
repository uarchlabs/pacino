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
