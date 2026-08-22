// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ftq_meta (BP-107).
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
//
// ONE PROPERTY, and that is the honest count. ftq_meta is an array
// with two write groups and two read ports and nothing else; the
// disjointness of the p2 and p3 groups (ftq_bpu_interfaces.md 7.1,
// 7.2) is a property of the write DATA and is not visible on the
// port list at all, so it is proved by the testbench writing one
// group and reading the other back, not by a bound property. Adding
// a property that could not fail would be the inert-assertion
// defect this project has shipped twice.
//
// What IS visible is that the two read ports are two views of ONE
// array. M1 says so, and it is the fault a per-port indexing error
// produces: the two resolution channels may name the same entry --
// two branches of one block resolving in the same cycle is ordinary
// traffic, not a corner -- and when they do they must see the same
// metadata.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_meta_assert (
  input logic                    clk,
  input logic                    rstn,
  input logic [FTQ_IDX_BITS-1:0] rd_idx  [0:NUM_RESOLVE_PORTS-1],
  input bp_ftq_meta_t            rd_meta [0:NUM_RESOLVE_PORTS-1]
                                         [0:NUM_PRED_SLOTS-1]
);

  // M1  Two read ports naming one entry return one answer. The
  //     resolution ports are independent and either may name any
  //     entry (ftq_backend_interfaces.md 4), so this is reachable on
  //     ordinary traffic: both branches of one fetch block resolving
  //     together. A port wired to the wrong index, or an array
  //     replicated per port rather than shared, fails here.
  //
  //     Written over the slots explicitly rather than comparing the
  //     unpacked arrays, because an unpacked array equality is not
  //     what the two-state comparison in a property gives.
  genvar gs;
  generate
    for (gs = 0; gs < NUM_PRED_SLOTS; gs++) begin : g_slot
      property p_ports_agree;
        @(posedge clk) disable iff (!rstn)
          (rd_idx[0] == rd_idx[1]) |->
            (rd_meta[0][gs] == rd_meta[1][gs]);
      endproperty
      a_ports_agree: assert property (p_ports_agree)
        else $error("M1 the two read ports disagree on one entry");
    end
  endgenerate

endmodule : ftq_meta_assert

// Bind BY MODULE NAME.
bind ftq_meta ftq_meta_assert u_assert (
  .clk     (clk),
  .rstn    (rstn),
  .rd_idx  (rd_idx),
  .rd_meta (rd_meta)
);
