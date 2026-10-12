// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tage_arb.sv
// DATE:    2026-10-12
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// TAGE arbitration layer (bp_arb_spec.md). BP-132 (TD#52) moved it out
// of tage.sv unchanged, so tage.sv is structural: the prediction queue
// (PQ), the update queue (UQ), the arbiter with its starvation count,
// the competing stage mux to tage_cntrl, the bp_arb_trx_t register and
// the prediction response buffer (RB). Every signal keeps the name it
// had in tage.sv; the arbitration-internal ones are now reached as
// u_tage_arb.<name>.
//
// The queue-status outputs carry the TD#49 names, tage_pq_not_full
// and tage_uq_not_full, given by BP-132.
// ===================================================================

`ifndef TAGE_ARB_SV
`define TAGE_ARB_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tage_arb (
  input  logic                           clk,
  input  logic                           rstn,
  // -- requests, from the tage ports
  input  logic [NUM_PRED_SLOTS-1:0]      tage_pred_val_p0,
  input  tage_pred_inp_t                 tage_pred_inp_p0[0:NUM_PRED_SLOTS-1],
  input  logic [NUM_PRED_SLOTS-1:0]      tage_upd_val_u0,
  input  tage_upd_inp_t                  tage_upd_inp_u0[0:NUM_PRED_SLOTS-1],
  // -- prediction results, to the tage ports
  output logic [NUM_PRED_SLOTS-1:0]      tage_pred_rdy_p2,
  output tage_pred_meta_t                tage_pred_meta_p2[0:NUM_PRED_SLOTS-1],
  // -- queue status (TD#49 names)
  output logic                           tage_pq_not_full,
  output logic [NUM_PRED_SLOTS-1:0]      tage_uq_not_full,
  // -- consumer ready (SC drives; 1=ready to accept result)
  input  logic                           consumer_ready,
  // -- competing stage, to tage_cntrl
  output logic [NUM_PRED_SLOTS-1:0]      cntrl_pred_val_p0,
  output tage_pred_inp_t                 cntrl_pred_inp_p0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]      cntrl_upd_val_u0,
  output tage_upd_inp_t                  cntrl_upd_inp_u0[0:NUM_PRED_SLOTS-1],
  output logic                           trx_type,
  // -- prediction results, from tage_cntrl
  input  logic [NUM_PRED_SLOTS-1:0]      cntrl_pred_rdy_p2,
  input  tage_pred_meta_t                cntrl_pred_meta_p2[0:NUM_PRED_SLOTS-1]
);

  // -- Arbitration FIFO and counter sizing (BP-023b)
  localparam int PQ_IDX_W    = $clog2(TAGE_PQ_DEPTH);
  localparam int PQ_PTR_W    = PQ_IDX_W + 1;
  localparam int UQ_IDX_W    = $clog2(TAGE_UQ_DEPTH);
  localparam int UQ_PTR_W    = UQ_IDX_W + 1;
  localparam int RB_IDX_W    = $clog2(TAGE_RESP_BUF_DEPTH);
  localparam int RB_PTR_W    = RB_IDX_W + 1;
  localparam int PRED_CRED_W =
    $clog2(TAGE_PRED_CREDITS + 1);  // 3b: holds 0..4
  localparam int UPD_CRED_W  =
    $clog2(TAGE_UPD_CREDITS  + 1);  // 1b: holds 0..1
  localparam int STARVE_W    =
    $clog2(TAGE_STARVE_THRESH + 1); // 4b: holds 0..8

  // -- Arbiter outputs and trx_type
  logic arb_grant_pred, arb_grant_upd;
  // trx_type: combinational from arbiter (not registered).
  // Using the registered arb_trx_r.trx_type would lag by 1 cycle,
  // causing write enables to fire on the wrong competing stage.
  assign trx_type = arb_grant_upd;

  // -- pq_has_data / uq_has_data (include bypass candidates)
  logic pq_has_data_w, uq_has_data_w;
  assign pq_has_data_w = !pq_empty || (|tage_pred_val_p0);
  assign uq_has_data_w = !uq_empty || (|tage_upd_val_u0);

  // -- consumer_ready: port input (SC drives; used by RB logic)

  // -- resp_buf_full: forwarded from RB (declared below)
  logic resp_buf_full_w;

  // ----------------------------------------------------------------
  // Arbiter registers
  // ----------------------------------------------------------------
  // BP-121: the credit counters are retired (see the arbiter); the
  // starvation count remains.
  logic [STARVE_W-1:0]     starve_ctr_r;

  // ----------------------------------------------------------------
  // Prediction Queue (PQ) FIFO
  // ----------------------------------------------------------------
  tage_pred_inp_t
    pq_inp_mem[TAGE_PQ_DEPTH][0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]
    pq_val_mem[TAGE_PQ_DEPTH];
  logic [PQ_PTR_W-1:0] pq_head_r, pq_tail_r;
  logic pq_full, pq_empty;

  assign pq_full  = (pq_tail_r[PQ_IDX_W-1:0]
                     == pq_head_r[PQ_IDX_W-1:0])
                 && (pq_tail_r[PQ_IDX_W]
                     != pq_head_r[PQ_IDX_W]);
  assign pq_empty = (pq_head_r == pq_tail_r);

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
      if ((|tage_pred_val_p0) && !pq_full
          && (!pq_empty || !arb_grant_pred)) begin
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          pq_inp_mem[pq_tail_r[PQ_IDX_W-1:0]][s]
            <= tage_pred_inp_p0[s];
        end
        pq_val_mem[pq_tail_r[PQ_IDX_W-1:0]]
          <= tage_pred_val_p0;
        pq_tail_r <= pq_tail_r + PQ_PTR_W'(1);
      end
    end
  end

  // ----------------------------------------------------------------
  // Update Queue (UQ) FIFO
  // ----------------------------------------------------------------
  tage_upd_inp_t
    uq_data_mem[TAGE_UQ_DEPTH][0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]
    uq_val_mem[TAGE_UQ_DEPTH];
  logic [UQ_PTR_W-1:0] uq_head_r, uq_tail_r;
  logic uq_full, uq_empty;

  assign uq_full  = (uq_tail_r[UQ_IDX_W-1:0]
                     == uq_head_r[UQ_IDX_W-1:0])
                 && (uq_tail_r[UQ_IDX_W]
                     != uq_head_r[UQ_IDX_W]);
  assign uq_empty = (uq_head_r == uq_tail_r);
  assign tage_uq_not_full = {NUM_PRED_SLOTS{!uq_full}};

  // Not full, and no starving update asking for this p0 cycle
  // (see the arbiter). Registered terms only.
  assign tage_pq_not_full = !pq_full &&
                            !(!uq_empty &&
                              (starve_ctr_r >=
                               STARVE_W'(TAGE_STARVE_THRESH)));

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
      if ((|tage_upd_val_u0) && !uq_full
          && (!uq_empty || !arb_grant_upd)) begin
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          // Whole-struct write: UQ element is the live tage_upd_inp_t.
          uq_data_mem[uq_tail_r[UQ_IDX_W-1:0]][s]
            <= tage_upd_inp_u0[s];
        end
        uq_val_mem[uq_tail_r[UQ_IDX_W-1:0]]
          <= tage_upd_val_u0;
        uq_tail_r <= uq_tail_r + UQ_PTR_W'(1);
      end
    end
  end

  // ----------------------------------------------------------------
  // Arbiter: a prediction is never delayed by an update (BP-121,
  // ruled by Jeff). The cluster reads the TAGE result at a fixed p2,
  // matched by branch_id, so a prediction held back one cycle by an
  // update grant (the 4.5 credit rules 3 and 4) is a lost prediction,
  // and every later one with it: the queue then answers each request
  // a cycle late until p0 idles. Measured before BP-121: 70 to 90
  // percent of p2 blocks saw a late TAGE result.
  //   rule 1  response buffer full: no prediction grant
  //   pred    a prediction is presented or queued: grant it
  //   upd     otherwise (none, or rule 1 blocks it) an update is
  //           presented or queued: grant it
  //   hold    an update that has waited TAGE_STARVE_THRESH cycles
  //           deasserts tage_pq_not_full for a cycle; the FTQ withholds
  //           the p0 request (its H1 hold) and the update takes that
  //           cycle
  // The credit counters of 4.5 are retired with rules 2 to 4.
  // ----------------------------------------------------------------
  always_comb begin : arb_comb
    arb_grant_pred = 1'b0;
    arb_grant_upd  = 1'b0;
    if (pq_has_data_w && !resp_buf_full_w)
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
                 (starve_ctr_r < STARVE_W'(TAGE_STARVE_THRESH))) begin
      starve_ctr_r <= starve_ctr_r + STARVE_W'(1);
    end
  end

  // ----------------------------------------------------------------
  // Competing stage mux: route PQ/bypass or UQ/bypass to tage_cntrl
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
        cntrl_pred_val_p0 = tage_pred_val_p0;
        for (int s = 0; s < NUM_PRED_SLOTS; s++)
          cntrl_pred_inp_p0[s] = tage_pred_inp_p0[s];
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
        // UQ bypass: use incoming update directly
        // Fan tage_upd_inp_t to cntrl_upd_inp_u0 (tage_upd_inp_t)
        cntrl_upd_val_u0 = tage_upd_val_u0;
        for (int s = 0; s < NUM_PRED_SLOTS; s++)
          cntrl_upd_inp_u0[s] = tage_upd_inp_u0[s];
      end else begin
        // From UQ head: whole-struct read (tage_upd_inp_t)
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
  // Captures the arbitration decision for pipeline tracking.
  // trx_type (not arb_trx_r) is forwarded to tage_cntrl.
  // ----------------------------------------------------------------
  bp_arb_trx_t              arb_trx_r;
  logic [TRX_SLOT_BITS-1:0] arb_trx_slot_w;

  // Lowest active slot for current grant
  always_comb begin : arb_slot_comb
    arb_trx_slot_w = '0;
    for (int s = NUM_PRED_SLOTS-1; s >= 0; s--) begin
      if (arb_grant_pred && tage_pred_val_p0[s])
        arb_trx_slot_w = TRX_SLOT_BITS'(s);
      if (arb_grant_upd && tage_upd_val_u0[s])
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

  // ----------------------------------------------------------------
  // Prediction response buffer (RB)
  // Depth TAGE_RESP_BUF_DEPTH. Entry: tage_pred_meta_t per slot.
  // Bypass when RB empty and consumer_ready (consumer_ready=1).
  // ----------------------------------------------------------------
  tage_pred_meta_t
    rb_meta_mem[TAGE_RESP_BUF_DEPTH][0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]
    rb_val_mem[TAGE_RESP_BUF_DEPTH];
  logic [RB_PTR_W-1:0] rb_head_r, rb_tail_r;
  logic rb_full, rb_empty;

  assign rb_full  = (rb_tail_r[RB_IDX_W-1:0]
                     == rb_head_r[RB_IDX_W-1:0])
                 && (rb_tail_r[RB_IDX_W]
                     != rb_head_r[RB_IDX_W]);
  assign rb_empty = (rb_head_r == rb_tail_r);
  assign resp_buf_full_w = rb_full;

  always_ff @(posedge clk) begin : rb_ff
    if (!rstn) begin
      rb_head_r <= '0;
      rb_tail_r <= '0;
    end else begin
      // Dequeue: RB non-empty and consumer ready
      if (!rb_empty && consumer_ready)
        rb_head_r <= rb_head_r + RB_PTR_W'(1);
      // Enqueue: cntrl produced result and bypass not active
      // (bypass fires when rb_empty && consumer_ready)
      if (|cntrl_pred_rdy_p2) begin
        if (!rb_empty || !consumer_ready) begin
          for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
            // Whole-struct write: RB element is tage_pred_meta_t.
            rb_meta_mem[rb_tail_r[RB_IDX_W-1:0]][s]
              <= cntrl_pred_meta_p2[s];
          end
          rb_val_mem[rb_tail_r[RB_IDX_W-1:0]]
            <= cntrl_pred_rdy_p2;
          rb_tail_r <= rb_tail_r + RB_PTR_W'(1);
        end
      end
    end
  end

  // -- Response buffer output mux (bypass or RB head)
  always_comb begin : rb_out_comb
    if (rb_empty && consumer_ready) begin
      // Bypass: pass tage_cntrl result directly
      tage_pred_rdy_p2 = cntrl_pred_rdy_p2;
      for (int s = 0; s < NUM_PRED_SLOTS; s++)
        tage_pred_meta_p2[s] = cntrl_pred_meta_p2[s];
    end else begin
      // From RB head (whole-struct read, tage_pred_meta_t)
      tage_pred_rdy_p2 =
        rb_val_mem[rb_head_r[RB_IDX_W-1:0]]
        & {NUM_PRED_SLOTS{consumer_ready}};
      for (int s = 0; s < NUM_PRED_SLOTS; s++)
        tage_pred_meta_p2[s] =
          rb_meta_mem[rb_head_r[RB_IDX_W-1:0]][s];
    end
  end

endmodule : tage_arb

`endif // TAGE_ARB_SV

`default_nettype wire
