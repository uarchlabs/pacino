// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fe_demo_lib.svh -- what the scenario programs share (DOC-001)
//
// Included inside module tb by tb_fe_demo.sv, after the shared models.
// The start and end of every scenario run, the address map of the
// translated scenarios, and program pieces several scenarios use. The
// pieces follow tb_fe_top's (map_ch, run_at, smc_*), which are local
// to that file.
// ===================================================================

  // Cycles from the release of reset to the last retirement.
  int cyc_run;

  // Every model and monitor to its start; the program is written at
  // the reset vector next. use_sv39: S-mode under satp Sv39, else
  // M-mode, bare.
  task automatic begin_scen(input string nm, input logic use_sv39);
    tname = nm;
    $display("-- %s --", tname);
    models_reset(use_sv39);
    mon_reset();
    W.wp = RESET_VECTOR;
  endtask

  // The end of the program (jal x0, 0), the release of reset, and the
  // run: until the whole stream has retired, a stream error or
  // max_cyc. Then decode's output is no longer taken and the front end
  // runs on for a short drain, which the monitors do not count.
  task automatic demo_go(input int max_cyc);
    int c;
    W.halt();
    release_reset();
    c = 0;
    while ((ep < W.ne) && (c < max_cyc) && (n_err < 20)) begin
      @(posedge clk);
      #1;
      c++;
    end
    cyc_run = c;
    run_be  = 1'b0;
    repeat (100) @(posedge clk);
    #1;
  endtask

  // =================================================================
  // The translated scenarios' address map (as tb_fe_top's walker
  // programs): code C and handlers H mapped single-stage, VS code V and
  // its handlers mapped two-stage, targets T(k) each in its own 2 MiB
  // region.
  // =================================================================
  localparam logic [VA_WIDTH-1:0]  PC_C = VA_WIDTH'('h0_8001_0000);
  localparam logic [VA_WIDTH-1:0]  PC_H = VA_WIDTH'('h0_8002_0000);
  localparam logic [VA_WIDTH-1:0]  PC_V = VA_WIDTH'('h0_8005_0000);
  localparam logic [PA_WIDTH-1:0]  PA_C = PA_WIDTH'('h0_8100_0000);
  localparam logic [PA_WIDTH-1:0]  PA_H = PA_WIDTH'('h0_8130_0000);
  localparam logic [PA_WIDTH-1:0]  PA_V = PA_WIDTH'('h0_8160_0000);
  localparam logic [GPA_WIDTH-1:0] GP_V = GPA_WIDTH'('h0_1005_0000);

  function automatic logic [VA_WIDTH-1:0] tgt(input int k);
    return VA_WIDTH'('h0_8040_0000) + VA_WIDTH'(k) * VA_WIDTH'('h20_0000) +
           VA_WIDTH'('h10);
  endfunction

  function automatic logic [VA_WIDTH-1:0] hnd(input int k);
    return PC_H + VA_WIDTH'(k * 'h40);
  endfunction

  // Single stage: the reset vector mapped to itself, C and H; the
  // program starts at the reset vector and jumps to C.
  task automatic map_ch();
    W.map4k(RESET_VECTOR, PA_WIDTH'(RESET_VECTOR));
    W.map4k(PC_C, PA_C);
    W.map4k(PC_H, PA_H);
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, PC_C);
    W.mixed(2);
  endtask

  // The two-stage tables (as set_h2) with no CSR change: the G-stage
  // root, the VS root and the VS code page V. The CSRs change when the
  // trap of an entry in to_h2 retires (be_trap_hook).
  task automatic h2_tables();
    W.h2       = 1'b1;
    W.hg_root  = PA_WIDTH'('h0_8E00_0000);
    for (int i = 0; i < 2048; i++) W.wr64(W.hg_root + PA_WIDTH'(8 * i), '0);
    W.gpt_next = GPA_WIDTH'('h0_C000_0000);
    W.vs_root  = W.vs_alloc();
    W.h_map4k(PC_V, GP_V, PA_V);
  endtask

  // An ecall whose trap enters the two-stage regime at V.
  task automatic ecall_to_vs();
    W.ecall(PC_V);
    to_h2[W.ne-1] = 1'b1;
  endtask

  // A short body at a target, then an indirect jump to back.
  task automatic run_at(input logic [VA_WIDTH-1:0] at,
                        input logic [VA_WIDTH-1:0] back);
    W.jalr_to(5'd0, 5'd7, at);
    W.mixed(4);
    W.jalr_to(5'd0, 5'd7, back);
    W.mixed(2);
  endtask

  // =================================================================
  // Self-modifying code (FD-19), as tb_fe_top's smc_*: a function at
  // f, six c.addi and a return, called so the L1I holds it; one store
  // rewrites it (three addi t1 and the return), which lands when the
  // store retires; called again after the maintenance operation, the
  // stream expects the new body.
  // =================================================================
  task automatic smc_fn(input logic [VA_WIDTH-1:0] f, input int calls);
    logic [VA_WIDTH-1:0] link;
    for (int k = 0; k < calls; k++) begin
      link = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, f);
      for (int i = 0; i < 6; i++) W.i16();
      W.ret(link);
    end
  endtask

  task automatic smc_store(input logic [VA_WIDTH-1:0] f);
    logic [VA_WIDTH-1:0] w;
    logic                d;
    W.store();
    w     = W.wp;
    d     = W.dry;
    W.dry = 1'b1;
    W.wp  = f;
    for (int i = 0; i < 3; i++) W.i32(ADDI_T1);
    W.ret(f);
    W.dry = d;
    W.wp  = w;
    W.store_end();
  endtask

  task automatic smc_call_new(input logic [VA_WIDTH-1:0] f);
    logic [VA_WIDTH-1:0] link;
    link = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, f);
    W.nowrite = 1'b1;
    for (int i = 0; i < 3; i++) W.i32(ADDI_T1);
    W.ret(link);
    W.nowrite = 1'b0;
  endtask
