// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fe_demo_finish.cpp -- the $finish of tb_fe_demo, without a message
// (DOC-003, fe_demo_tb_decisions.md FDT-10a)
//
// The Verilator runtime prints "- <file>:<line>: Verilog $finish" when
// $finish runs, a line outside the format of FDT-10a. The Makefile
// compiles the runtime with VL_USER_FINISH defined, which removes its
// vl_finish (verilated.cpp), and links this one, which ends the run
// the same way and prints nothing. The runtime's end-of-run report is
// dropped by +verilator+quiet, also in the Makefile. A failing run ends
// in $fatal, which this does not change.
// ===================================================================
#include "verilated.h"

void vl_finish(const char* filename, int linenum,
               const char* hier) VL_MT_UNSAFE {
  (void)filename;
  (void)linenum;
  (void)hier;
  Verilated::threadContextp()->gotFinish(true);
}
