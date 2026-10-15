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
