// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    ittage_arb.sv
// DATE:    2026-10-12
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// ITTAGE arbitration layer (bp_arb_spec.md). BP-132 (TD#52) moved it
// out of ittage.sv unchanged, so ittage.sv is structural: the
// prediction queue (PQ), the update queue (UQ), the arbiter with its
// starvation count, the competing stage mux to ittage_cntrl and the
// bp_arb_trx_t register. ITTAGE has no response buffer (BP-038b): its
// prediction results go from ittage_cntrl to the ittage ports
// directly. Every signal keeps the name it had in ittage.sv; the
// arbitration-internal ones are now reached as u_ittage_arb.<name>.
//
// The queue-status outputs carry the TD#49 names, ittage_pq_not_full
// and ittage_uq_not_full, given by BP-132.
// ===================================================================
`ifndef ITTAGE_ARB_SV
`define ITTAGE_ARB_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ittage_arb (
  input  logic                      clk,
  input  logic                      rstn,

  // requests, from the ittage ports
  input  logic [NUM_PRED_SLOTS-1:0] ittage_pred_val_p0,
  input  ittage_pred_inp_t          ittage_pred_inp_p0[0:NUM_PRED_SLOTS-1],
  input  logic [NUM_PRED_SLOTS-1:0] ittage_upd_val_u0,
  input  ittage_upd_inp_t           ittage_upd_inp_u0[0:NUM_PRED_SLOTS-1],

  // queue status (TD#49 names)
  output logic                      ittage_pq_not_full,
  output logic [NUM_PRED_SLOTS-1:0] ittage_uq_not_full,

  // competing stage, to ittage_cntrl
  output logic [NUM_PRED_SLOTS-1:0] cntrl_pred_val_p0,
  output ittage_pred_inp_t          cntrl_pred_inp_p0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0] cntrl_upd_val_u0,
  output ittage_upd_inp_t           cntrl_upd_inp_u0[0:NUM_PRED_SLOTS-1],
  output logic                      trx_type
);

  // -- Arbitration FIFO and counter sizing (BP-038)
  localparam int PQ_IDX_W    = $clog2(ITTAGE_PQ_DEPTH);
  localparam int PQ_PTR_W    = PQ_IDX_W + 1;
  localparam int UQ_IDX_W    = $clog2(ITTAGE_UQ_DEPTH);
  localparam int UQ_PTR_W    = UQ_IDX_W + 1;
  localparam int PRED_CRED_W =
    $clog2(ITTAGE_PRED_CREDITS + 1);
  localparam int UPD_CRED_W  =
    $clog2(ITTAGE_UPD_CREDITS  + 1);
  localparam int STARVE_W    =
    $clog2(ITTAGE_STARVE_THRESH + 1);

  // -- Arbiter outputs and trx_type
  logic arb_grant_pred, arb_grant_upd;
  // trx_type: combinational from arbiter (not registered).
  assign trx_type = arb_grant_upd;

  // -- pq_has_data / uq_has_data (include bypass candidates)
  logic pq_has_data_w, uq_has_data_w;
  assign pq_has_data_w =
    !pq_empty || (|ittage_pred_val_p0);
  assign uq_has_data_w =
    !uq_empty || (|ittage_upd_val_u0);

  // consumer_ready = 1'b1 internally; no downstream SC chain.

  // ----------------------------------------------------------------
  // Credit arbiter registers
  // ----------------------------------------------------------------
  // BP-121: the credit counters are retired (see the arbiter); the
  // starvation count remains.
  logic [STARVE_W-1:0]     starve_ctr_r;

  // ----------------------------------------------------------------
  // Prediction Queue (PQ) FIFO
  // ----------------------------------------------------------------
  ittage_pred_inp_t
    pq_inp_mem[ITTAGE_PQ_DEPTH][0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]
    pq_val_mem[ITTAGE_PQ_DEPTH];
  logic [PQ_PTR_W-1:0] pq_head_r, pq_tail_r;
  logic pq_full, pq_empty;

  assign pq_full  = (pq_tail_r[PQ_IDX_W-1:0]
                     == pq_head_r[PQ_IDX_W-1:0])
                 && (pq_tail_r[PQ_IDX_W]
                     != pq_head_r[PQ_IDX_W]);
  assign pq_empty   = (pq_head_r == pq_tail_r);

  always_ff @(posedge clk) begin : pq_ff
    if (!rstn) begin
      pq_head_r <= '0;
      pq_tail_r <= '0;
    end else begin
      // Dequeue on PRED grant from non-empty PQ
      if (arb_grant_pred && !pq_empty)
        pq_head_r <= pq_head_r + PQ_PTR_W'(1);
      // Enqueue: incoming pred, not in bypass (pq non-empty
      // or no grant this cycle)
      if ((|ittage_pred_val_p0) && !pq_full
          && (!pq_empty || !arb_grant_pred)) begin
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          pq_inp_mem[pq_tail_r[PQ_IDX_W-1:0]][s]
            <= ittage_pred_inp_p0[s];
        end
        pq_val_mem[pq_tail_r[PQ_IDX_W-1:0]]
          <= ittage_pred_val_p0;
        pq_tail_r <= pq_tail_r + PQ_PTR_W'(1);
      end
    end
  end

  // ----------------------------------------------------------------
  // Update Queue (UQ) FIFO
  // ----------------------------------------------------------------
  ittage_upd_inp_t
    uq_data_mem[ITTAGE_UQ_DEPTH][0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]
    uq_val_mem[ITTAGE_UQ_DEPTH];
  logic [UQ_PTR_W-1:0] uq_head_r, uq_tail_r;
  logic uq_full, uq_empty;

  assign uq_full  = (uq_tail_r[UQ_IDX_W-1:0]
                     == uq_head_r[UQ_IDX_W-1:0])
                 && (uq_tail_r[UQ_IDX_W]
                     != uq_head_r[UQ_IDX_W]);
  assign uq_empty = (uq_head_r == uq_tail_r);

  // Not full, and no starving update asking for this p0 cycle (see the
  // arbiter, BP-121). Registered terms only.
  assign ittage_pq_not_full = !pq_full &&
                              !(!uq_empty &&
                                (starve_ctr_r >=
                                 STARVE_W'(ITTAGE_STARVE_THRESH)));
  assign ittage_uq_not_full = {NUM_PRED_SLOTS{!uq_full}};

  always_ff @(posedge clk) begin : uq_ff
    if (!rstn) begin
      uq_head_r <= '0;
      uq_tail_r <= '0;
    end else begin
      // Dequeue on UPD grant from non-empty UQ
      if (arb_grant_upd && !uq_empty)
        uq_head_r <= uq_head_r + UQ_PTR_W'(1);
      // Enqueue: incoming upd, not in bypass (uq non-empty
      // or no grant this cycle)
      if ((|ittage_upd_val_u0) && !uq_full
          && (!uq_empty || !arb_grant_upd)) begin
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          uq_data_mem[uq_tail_r[UQ_IDX_W-1:0]][s]
            <= ittage_upd_inp_u0[s];
        end
        uq_val_mem[uq_tail_r[UQ_IDX_W-1:0]]
          <= ittage_upd_val_u0;
        uq_tail_r <= uq_tail_r + UQ_PTR_W'(1);
      end
    end
  end

  // ----------------------------------------------------------------
  // Arbiter: a prediction is never delayed by an update (BP-121,
  // ruled by Jeff), as in tage.sv: the cluster reads the ITTAGE result
  // at a fixed p2, matched by branch_id, and a prediction held back by
  // an update grant left every later result a cycle late.
  //   pred    a prediction is presented or queued: grant it
  //   upd     otherwise an update is presented or queued: grant it
  //   hold    an update that has waited ITTAGE_STARVE_THRESH cycles
  //           deasserts ittage_pq_not_full for a cycle (the FTQ's H1
  //           hold)
  // The credit counters of bp_arb_spec.md 4.5 are retired.
  // ----------------------------------------------------------------
  always_comb begin : arb_comb
    arb_grant_pred = 1'b0;
    arb_grant_upd  = 1'b0;
    if (pq_has_data_w)
      arb_grant_pred = 1'b1;
    else if (uq_has_data_w)
      arb_grant_upd = 1'b1;
  end

  // Starvation count: cycles an update has waited. Reset on a grant.
  always_ff @(posedge clk) begin : arb_starve_ff
    if (!rstn) begin
      starve_ctr_r <= '0;
    end else if (arb_grant_upd) begin
      starve_ctr_r <= '0;
    end else if (uq_has_data_w &&
                 (starve_ctr_r < STARVE_W'(ITTAGE_STARVE_THRESH))) begin
      starve_ctr_r <= starve_ctr_r + STARVE_W'(1);
    end
  end

  // ----------------------------------------------------------------
  // Competing stage mux: route PQ/bypass or UQ/bypass to ittage_cntrl
  // ----------------------------------------------------------------
  always_comb begin : comp_stage_mux_comb
    cntrl_pred_val_p0 = '0;
    cntrl_upd_val_u0  = '0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      cntrl_pred_inp_p0[s] = '0;
      cntrl_upd_inp_u0[s]  = '0;
    end

    if (arb_grant_pred) begin
      if (pq_empty) begin
        // PQ bypass: use incoming prediction directly
        cntrl_pred_val_p0 = ittage_pred_val_p0;
        for (int s = 0; s < NUM_PRED_SLOTS; s++)
          cntrl_pred_inp_p0[s] = ittage_pred_inp_p0[s];
      end else begin
        // From PQ head
        cntrl_pred_val_p0 =
          pq_val_mem[pq_head_r[PQ_IDX_W-1:0]];
        for (int s = 0; s < NUM_PRED_SLOTS; s++)
          cntrl_pred_inp_p0[s] =
            pq_inp_mem[pq_head_r[PQ_IDX_W-1:0]][s];
      end
    end else if (arb_grant_upd) begin
      if (uq_empty) begin
        // UQ bypass: route ittage_upd_inp_t directly
        cntrl_upd_val_u0 = ittage_upd_val_u0;
        for (int s = 0; s < NUM_PRED_SLOTS; s++)
          cntrl_upd_inp_u0[s] = ittage_upd_inp_u0[s];
      end else begin
        // From UQ head: ittage_upd_inp_t stored directly
        cntrl_upd_val_u0 =
          uq_val_mem[uq_head_r[UQ_IDX_W-1:0]];
        for (int s = 0; s < NUM_PRED_SLOTS; s++)
          cntrl_upd_inp_u0[s] =
            uq_data_mem[uq_head_r[UQ_IDX_W-1:0]][s];
      end
    end
  end

  // ----------------------------------------------------------------
  // bp_arb_trx_t pipeline register (p0/u0).
  // trx_type (not arb_trx_r) is the combinational grant signal.
  // ----------------------------------------------------------------
  bp_arb_trx_t              arb_trx_r;
  logic [TRX_SLOT_BITS-1:0] arb_trx_slot_w;

  // Lowest active slot for current grant
  always_comb begin : arb_slot_comb
    arb_trx_slot_w = '0;
    for (int s = NUM_PRED_SLOTS-1; s >= 0; s--) begin
      if (arb_grant_pred && ittage_pred_val_p0[s])
        arb_trx_slot_w = TRX_SLOT_BITS'(s);
      if (arb_grant_upd && ittage_upd_val_u0[s])
        arb_trx_slot_w = TRX_SLOT_BITS'(s);
    end
  end

  always_ff @(posedge clk) begin : arb_trx_ff
    if (!rstn) begin
      arb_trx_r <= '0;
    end else begin
      arb_trx_r.trx_type <= arb_grant_upd;
      arb_trx_r.trx_slot <= arb_trx_slot_w;
    end
  end

endmodule : ittage_arb

`endif // ITTAGE_ARB_SV

`default_nettype wire
