// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FTQ slow-path metadata array (BP-107).
//
// Owns bp_ftq_meta_t [NUM_PRED_SLOTS-1:0] x FTQ_DEPTH,
// ftq_entry_formats.md 3. 421 bits per slot, two slots per entry,
// 53,888 bits. It is read ONCE, at resolution, which is the whole
// reason it is a separate array from the fast path: the every-cycle
// read must not carry the width of update-only metadata.
//
// THE UNPACKED FORM IS BUILT. ftq_entry_formats.md 3.1 defines a
// two-arm union that takes the slot to 278 bits, and DEFERS it
// (TD-FE-2). The deferral is explicit that nothing else depends on
// the optimisation and that building unpacked preserves the
// disjointness of the p2 and p3 write groups, which the union
// narrows to a single arm. Built unpacked.
//
// TWO WRITE GROUPS, ftq_bpu_interfaces.md 7.1 and 7.2. They touch
// DISJOINT members, so no merge is ever needed:
//
//   p2  tage, ittage, lp, ftb
//   p3  sc
//
// The loop predictor finalises at p1, not p2; the cluster registers
// its p1 result and presents it in the p2 group so the FTQ performs
// ONE slow-path write per stage rather than two (7.1).
//
// bpu_meta_val_p3 is asserted whether or not SC is enabled, so the
// slow path is always complete. When SC is disabled the written
// value carries no prediction and the FTQ forms no SC update; that
// decision belongs to ftq_resolve, not here.
//
// TWO READ PORTS. ftq_backend_interfaces.md 4 fixes resolution at
// NUM_RESOLVE_PORTS per cycle and the two channels may name
// different entries, so one port cannot serve both. Each port
// returns BOTH slots of its entry: ftq_resolve maps position to
// slot and that mapping is not available here.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_meta (
  input  logic                     clk,
  input  logic                     rstn,

  // ---- p2 write group (ftq_bpu_interfaces.md 7.1) -----------------
  input  logic                     p2_wr_val,
  input  logic [FTQ_IDX_BITS-1:0]  p2_wr_idx,
  input  tage_pred_meta_t          p2_wr_tage   [0:NUM_PRED_SLOTS-1],
  input  ittage_pred_meta_t        p2_wr_ittage [0:NUM_PRED_SLOTS-1],
  input  lp_pred_t                 p2_wr_lp     [0:NUM_PRED_SLOTS-1],
  input  ftb_pred_meta_t           p2_wr_ftb    [0:NUM_PRED_SLOTS-1],

  // ---- p3 write group (ftq_bpu_interfaces.md 7.2) -----------------
  input  logic                     p3_wr_val,
  input  logic [FTQ_IDX_BITS-1:0]  p3_wr_idx,
  input  sc_pred_meta_t            p3_wr_sc     [0:NUM_PRED_SLOTS-1],

  // ---- resolution reads --------------------------------------------
  input  logic [FTQ_IDX_BITS-1:0]  rd_idx  [0:NUM_RESOLVE_PORTS-1],
  output bp_ftq_meta_t             rd_meta [0:NUM_RESOLVE_PORTS-1]
                                           [0:NUM_PRED_SLOTS-1]
);

  bp_ftq_meta_t r_arr [FTQ_DEPTH-1:0][NUM_PRED_SLOTS-1:0];

  // -----------------------------------------------------------------
  // Reads.
  // -----------------------------------------------------------------
  always_comb begin : reads
    for (int p = 0; p < NUM_RESOLVE_PORTS; p++) begin
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        rd_meta[p][s] = r_arr[rd_idx[p]][s];
      end
    end
  end

  // -----------------------------------------------------------------
  // Writes.
  // -----------------------------------------------------------------
  // Member-wise, not struct-wise, and that is the point: writing the
  // whole struct from either group would destroy the other group's
  // members and make the two writes ordered when 7.1 and 7.2 say
  // they are disjoint. Under the deferred union of 3.1 this stops
  // being true -- sc and ittage alias -- and W2 there requires the
  // p3 write to be SUPPRESSED on the indirect arm. That suppression
  // is not built, because the arm does not exist yet; when the union
  // lands it belongs here.
  //
  // No reset. The array is read only at resolution and a resolution
  // can only name an entry a prediction wrote, so there is no path
  // that reads an unwritten location. Clearing 53,888 bits at reset
  // would model a structure no SRAM provides.
  always_ff @(posedge clk) begin : writes
    if (p2_wr_val) begin
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        r_arr[p2_wr_idx][s].tage   <= p2_wr_tage[s];
        r_arr[p2_wr_idx][s].ittage <= p2_wr_ittage[s];
        r_arr[p2_wr_idx][s].lp     <= p2_wr_lp[s];
        r_arr[p2_wr_idx][s].ftb    <= p2_wr_ftb[s];
      end
    end
    if (p3_wr_val) begin
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        r_arr[p3_wr_idx][s].sc <= p3_wr_sc[s];
      end
    end
  end

  // rstn is on the port list for uniformity with every other module
  // in the unit and because a future union arm needs it; it drives
  // nothing here. See the no-reset note above.
  logic w_unused_rstn;
  assign w_unused_rstn = rstn;

endmodule : ftq_meta
