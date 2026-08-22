// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ftq_shadow (BP-107), ftq_decisions.md 5.6.
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
//
// The shadow's whole job is to DROP a response naming a squashed
// entry, and the failure mode is silent in both directions: accept
// one and the FTQ writes a squashed prediction into a live entry,
// drop a good one and the entry keeps its p1 view for ever. Neither
// shows up as a hang. H1 to H5 are the two directions plus the shift
// that makes them mean anything.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_shadow_assert (
  input logic                    clk,
  input logic                    rstn,
  input logic                    req_val,
  input logic [FTQ_PTR_BITS-1:0] req_ptr,
  input logic                    squash_val,
  input logic [FTQ_PTR_BITS-1:0] squash_start,
  input logic [FTQ_PTR_BITS-1:0] squash_end,
  input logic                    gv_pred_p1,
  input logic [FTQ_IDX_BITS-1:0] idx_pred_p1,
  input logic                    ok_pred_p1,
  input logic                    ok_slot_p2,
  input logic                    ok_redir_p2,
  input logic                    ok_slot_p3,
  input logic                    alloc_inflight,
  input logic [3:0]              shadow_val,
  input logic [FTQ_PTR_BITS-1:0] shadow_ptr [0:3]
);

  // An INDEPENDENT model of "is this stage squashed", recomputed
  // here rather than taken from the module, for the same reason
  // ftq_status_assert recomputes its mask: a property fed the
  // module's own answer agrees by construction.
  logic [FTQ_PTR_BITS-1:0] w_len;
  logic [3:0]              w_in_range;
  logic [3:0]              r_in_range;
  logic                    r_squash;

  always_comb begin : model
    w_len = squash_end - squash_start;
    for (int n = 0; n < 4; n++) begin
      w_in_range[n] = shadow_val[n] &&
                      ((shadow_ptr[n] - squash_start) < w_len);
    end
  end

  // A REGISTERED COPY OF THE STAGE POINTERS, not $past. shadow_ptr[0]
  // is COMBINATIONAL -- it is the presented request -- so it sits in
  // the same cone as the flops it feeds, and $past over that cone
  // does not reliably return what the flop captured. Same reason
  // ftq_npc_assert keeps r_prev_pc.
  logic [FTQ_PTR_BITS-1:0] r_prev_ptr [0:2];

  always_ff @(posedge clk or negedge rstn) begin : hist
    if (!rstn) begin
      r_in_range <= '0;
      r_squash   <= 1'b0;
      for (int n = 0; n < 3; n++) r_prev_ptr[n] <= '0;
    end else begin
      r_in_range <= w_in_range;
      r_squash   <= squash_val;
      for (int n = 0; n < 3; n++) r_prev_ptr[n] <= shadow_ptr[n];
    end
  end

  // H1  A qualified valid never outruns the group valid. The
  //     shadow may only DROP a response; it may not invent one.
  property p_ok_needs_gv;
    @(posedge clk) disable iff (!rstn)
      ok_pred_p1 |-> gv_pred_p1;
  endproperty

  // H2  A qualified valid requires BOTH terms of 5.6: the stage is
  //     valid AND the index matches. Valid alone would accept a
  //     response for a different entry after a rewind reallocated
  //     the stage; match alone would accept one for a stage the
  //     redirect cleared. This states both on the p1 group, which
  //     is the one that WRITES A WHOLE ENTRY and so has the most to
  //     lose.
  property p_ok_is_valid_and_match;
    @(posedge clk) disable iff (!rstn)
      ok_pred_p1 |-> shadow_val[1] &&
        (shadow_ptr[1][FTQ_IDX_BITS-1:0] == idx_pred_p1);
  endproperty

  // H3  THE DROP ACTUALLY HAPPENS. A stage holding an entry inside
  //     the squash range is not valid the next cycle. This is the
  //     property 4.6 exists for and the one that fails if a future
  //     change decides the shadow can be cleared by index rather
  //     than by wrap-aware age.
  //
  //     Compared one cycle on because the clear is applied to the
  //     SHIFTED value: a request at p1 when the redirect fires is at
  //     p2 the next cycle, and it is stage 2 that must be clear
  //     then. r_in_range[n] is therefore compared against
  //     shadow_val[n+1].
  property p_squashed_stage_clears;
    @(posedge clk) disable iff (!rstn)
      r_squash |-> ((shadow_val[3:1] & r_in_range[2:0]) == '0);
  endproperty

  // H4  IT SHIFTS UNCONDITIONALLY, in lockstep with the cluster's
  //     own stage registers. A shadow that stalled with the FTQ
  //     rather than with the cluster would drift by one stage per
  //     stall and start checking every response against the wrong
  //     stage -- which looks like correct behaviour until a
  //     redirect. Stated on the pointer, which shifts with no clear
  //     applied to it.
  property p_shifts_every_cycle;
    @(posedge clk) disable iff (!rstn)
      (shadow_ptr[1] == r_prev_ptr[0]) &&
      (shadow_ptr[2] == r_prev_ptr[1]) &&
      (shadow_ptr[3] == r_prev_ptr[2]);
  endproperty

  // H5  A request the redirect does not squash ENTERS the shadow.
  //     The complement of H3: without it a shadow that cleared
  //     everything on every redirect would satisfy H3 and drop every
  //     surviving response, which is the exact error the four-deep
  //     age comparison exists to avoid -- stage 3 holds an OLDER
  //     request than stage 2, so a p2 redirect leaves it alone.
  property p_request_enters;
    @(posedge clk) disable iff (!rstn)
      (req_val && !(squash_val &&
                    ((req_ptr - squash_start) < w_len))) |=>
        shadow_val[1];
  endproperty

  // H6  alloc_inflight IS THE STAGE AT p1. The gap ftq_ptr subtracts
  //     from the run-ahead is the request whose entry write has not
  //     landed, which is the one at p1 -- stage 1, not stage 0.
  //     Stage 0 is the request being PRESENTED; alloc_ptr has not
  //     advanced past it yet, so it is already outside the
  //     run-ahead.
  property p_inflight_is_p1_stage;
    @(posedge clk) disable iff (!rstn)
      alloc_inflight == shadow_val[1];
  endproperty

  a_ok_needs_gv:            assert property (p_ok_needs_gv)
    else $error("H1 a qualified valid outran its group valid");
  a_ok_is_valid_and_match:  assert property (p_ok_is_valid_and_match)
    else $error("H2 a response was accepted without both terms");
  a_squashed_stage_clears:  assert property (p_squashed_stage_clears)
    else $error("H3 a squashed stage survived the redirect");
  a_shifts_every_cycle:     assert property (p_shifts_every_cycle)
    else $error("H4 the shadow did not shift in lockstep");
  a_request_enters:         assert property (p_request_enters)
    else $error("H5 a surviving request did not enter the shadow");
  a_inflight_is_p1_stage:   assert property (p_inflight_is_p1_stage)
    else $error("H6 alloc_inflight is not the p1 stage");

  // On the port list so the bind covers every qualified valid the
  // module produces, and so a future property over the p2 and p3
  // groups needs no bind change.
  logic w_unused;
  assign w_unused = ok_slot_p2 | ok_redir_p2 | ok_slot_p3;

endmodule : ftq_shadow_assert

// Bind BY MODULE NAME.
bind ftq_shadow ftq_shadow_assert u_assert (
  .clk            (clk),
  .rstn           (rstn),
  .req_val        (req_val),
  .req_ptr        (req_ptr),
  .squash_val     (squash_val),
  .squash_start   (squash_start),
  .squash_end     (squash_end),
  .gv_pred_p1     (gv_pred_p1),
  .idx_pred_p1    (idx_pred_p1),
  .ok_pred_p1     (ok_pred_p1),
  .ok_slot_p2     (ok_slot_p2),
  .ok_redir_p2    (ok_redir_p2),
  .ok_slot_p3     (ok_slot_p3),
  .alloc_inflight (alloc_inflight),
  .shadow_val     (shadow_val),
  .shadow_ptr     (shadow_ptr)
);
