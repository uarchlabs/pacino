// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd07_calls_returns.svh -- FD-7 Calls and returns
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     RAS push and pop, a return predicted from the stack,
//             recursion compression, a return-call
//   program   a loop of 8: main calls f1, f1 calls f2 (nested); then f
//             calls itself four deep from one call site (recursion);
//             then two coroutines switch by return-call (jalr x1, 0(x5)
//             and jalr x5, 0(x1))
//   waveform  the RAS pointers and top of stack, the p2 operations, the
//             commit stack
//   trace     pushes, pops, return-calls, recursion counts
//   proof     a retired return whose target the RAS supplied (pred_src
//             PRED_RAS, target right); a recursion count above 1 in the
//             speculative stack; a p2 RETURN_CALL operation
// ===================================================================

  task automatic prog_fd07();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] l;
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] b;
    logic [VA_WIDTH-1:0] b1;
    logic [VA_WIDTH-1:0] a1;
    logic [VA_WIDTH-1:0] lc;
    begin_scen("fd07_calls_returns", 1'b0);
    for (int k = 1; k <= 2; k++)
      W.fnv[k] = RESET_VECTOR + VA_WIDTH'('h400 + k * 'h100);
    f = RESET_VECTOR + VA_WIDTH'('h800);
    b = RESET_VECTOR + VA_WIDTH'('hA00);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 8; it++) begin
      W.wp = top;
      // Nested: main -> f1 -> f2.
      W.mixed(2);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, W.fnv[1]);
      W.emit_nest(1, 2, l);
      // Recursion: f calls itself four deep from one call site.
      W.mixed(1);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, f);
      W.emit_rec(f, 4, l);
      // Coroutines: L calls B with x5; B and A switch by return-call.
      W.mixed(1);
      lc = W.wp;
      W.jal(5'd5, b);                          // L
      W.mixed(2);                              // B prologue
      b1 = W.wp;
      W.jalr_to(5'd1, 5'd5, lc + VA_WIDTH'(4)); // B1: RETURN_CALL
      W.mixed(2);                              // A at L+4
      a1 = W.wp;
      W.jalr_to(5'd5, 5'd1, b1 + VA_WIDTH'(4)); // A1: RETURN_CALL
      W.mixed(2);                              // B at B1+4
      W.jalr_to(5'd0, 5'd5, a1 + VA_WIDTH'(4)); // B2: RETURN
      W.mixed(1);
      W.bcc(it != 7, top);
    end
    W.mixed(3);
    demo_go(80000);
  endtask
