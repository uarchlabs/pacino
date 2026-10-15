// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fd09_tage.svh -- FD-9 TAGE provider, allocation and use_alt_on_na
// (planning/showcase/fe_demo_scenarios.md, DOC-001)
//
//   shows     a tagged provider hit, an allocation after a mispredict,
//             use_alt_on_na choosing T0
//   program   tb_fe_top t0_uaon: a conditional taken with probability
//             1/8 (LFSR seed ACE1), 256 passes
//   waveform  TAGE p2 provider, the update path, the allocation, uaon
//   trace     allocations; T0 predictions through use_alt_on_na
//   proof     a TAGE allocation write applied; a p2 prediction whose
//             primary is tagged but whose prediction is T0's through
//             use_alt_on_na
// ===================================================================

  task automatic prog_fd09();
    logic [VA_WIDTH-1:0] top;
    logic                tk;
    begin_scen("fd09_tage", 1'b0);
    W.lfsr = 16'hACE1;
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 256; it++) begin
      W.wp = top;
      W.mixed(2);
      tk = W.lfsr_bit() & W.lfsr_bit() & W.lfsr_bit();
      W.cskip(tk, 1);                         // B
      W.mixed(1);
      W.bcc(it != 255, top);
    end
    W.mixed(3);
    demo_go(200000);
  endtask
