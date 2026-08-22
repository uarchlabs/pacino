// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FTQ in-flight response shadow (BP-107), ftq_decisions.md 5.6.
//
// THE PROBLEM. A redirect does not reach into the cluster. bp_cluster
// has no flush input (FE-14: a flush is a redirect, and clearing a
// predictor is done by withholding its stage valid), so requests
// already at p0, p1, p2 and p3 for entries the redirect squashed
// still complete and still present their results. The FTQ drops
// them (4.6).
//
// It cannot drop them by index alone. Every response carries an
// FTQ_IDX_BITS index with NO wrap bit, and a rewind can reallocate
// an index while a response for the squashed use of that same index
// is still in flight. 5.6 rejects widening the carried index --
// it would change FTQ_IDX_BITS at every bp_cluster port and widen
// branch_id in three predictor metadata structs -- and rejects
// draining the cluster, which would add up to three cycles to every
// redirect. The shadow is what it takes instead.
//
// FOUR DEEP, AND NOT A PARAMETER. p0 through p3, fixed by cluster
// pipeline depth (5.6). A parameter would advertise a tunable that
// does not exist.
//
// IT SHIFTS UNCONDITIONALLY, in lockstep with the cluster's own
// stage registers, which advance unconditionally. That is the whole
// mechanism: stage n of the shadow describes the request the
// cluster has at stage n, so a response at stage n is checked
// against shadow stage n.
//
//   stage 0   the request presented at p0 THIS CYCLE. It is
//             COMBINATIONAL -- req_val and req_ptr themselves --
//             because a p0 request has not been registered
//             anywhere yet, in the cluster or here.
//   stage 1   the request at p1, whose bpu_pred_* group is arriving
//   stage 2   the request at p2, whose slot / redirect / meta
//             groups are arriving
//   stage 3   the request at p3
//
// SO IT IS FOUR STAGES AND THREE FLOPS. 5.6 sizes it as four deep,
// one per cluster stage p0 through p3, and that is what is built --
// but the p0 stage holds the request being presented, which the
// cluster has not latched either, so it needs no register. A design
// with four registers puts the p1 response one stage too late and
// checks every response against the stage behind it, which reads as
// "every response is dropped" and stops the front end dead. Found
// by the unit testbench, which is the only place the lockstep is
// visible; reported in the BP-107 Results Capture.
//
// THE SHADOW HOLDS A FULL POINTER, not an index. 5.6 sizes it at
// 4 x 7 bits, one valid plus FTQ_IDX_BITS. It is built at 4 x 8,
// carrying FTQ_PTR_BITS, because deciding WHICH STAGES A REDIRECT
// CLEARS is a wrap-aware age comparison and an index cannot make
// it. The alternative -- clearing all four stages on any redirect
// -- is wrong: stage 3 holds an OLDER request than stage 2, so a
// p2 redirect naming the stage 2 entry squashes stages 1 and 0 and
// leaves stage 3 alone. Clearing it would drop a p3 response for a
// surviving entry.
//
// This is NOT the widening 5.6 rejects. That was FTQ_IDX_BITS at
// every bp_cluster port and inside four metadata structs. This is
// four bits inside the FTQ. Reported in the BP-107 Results Capture.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_shadow (
  input  logic                     clk,
  input  logic                     rstn,

  // ---- the request the FTQ presents at p0 --------------------------
  // ACCEPTED, not merely presented: the cluster stages a request
  // only when it takes one, so a held request must not enter the
  // shadow or the two would drift apart by one stage per stall.
  input  logic                     req_val,
  input  logic [FTQ_PTR_BITS-1:0]  req_ptr,

  // ---- the squash range, from ftq_ptr ------------------------------
  // Half open, [squash_start, squash_end), the same range
  // ftq_status masks with. A stage is cleared when the entry it
  // names lies in it.
  input  logic                     squash_val,
  input  logic [FTQ_PTR_BITS-1:0]  squash_start,
  input  logic [FTQ_PTR_BITS-1:0]  squash_end,

  // ---- the cluster response groups ---------------------------------
  // Each group is presented with its own index, and 5.6 lists all
  // seven by name. The p2 groups all name one entry and the p3
  // groups likewise, but each is checked against its own index
  // rather than against a shared one: that costs a comparator and
  // catches a cluster that ever presented two p2 groups for
  // different entries, which the interface forbids and nothing
  // else would detect.
  //
  // The redirect groups carry no group valid -- bp_redirect_t has a
  // per-slot valid and ftq_npc reduces across the slots -- so only
  // their index arrives here and only the stage term goes back.
  input  logic                     gv_pred_p1,
  input  logic [FTQ_IDX_BITS-1:0]  idx_pred_p1,
  input  logic                     gv_slot_p2,
  input  logic [FTQ_IDX_BITS-1:0]  idx_slot_p2,
  input  logic                     gv_meta_p2,
  input  logic [FTQ_IDX_BITS-1:0]  idx_meta_p2,
  input  logic [FTQ_IDX_BITS-1:0]  idx_redir_p2,
  input  logic                     gv_slot_p3,
  input  logic [FTQ_IDX_BITS-1:0]  idx_slot_p3,
  input  logic                     gv_meta_p3,
  input  logic [FTQ_IDX_BITS-1:0]  idx_meta_p3,
  input  logic [FTQ_IDX_BITS-1:0]  idx_redir_p3,

  // ---- the qualified group valids ----------------------------------
  // A response is accepted only if its stage's shadow is VALID and
  // its index MATCHES. Both terms are needed: valid alone would
  // accept a response for a different entry after a rewind
  // reallocated the stage, and match alone would accept one for a
  // stage the redirect cleared.
  //
  // The QUALIFIED valid leaves this module rather than a bare
  // accept term, so ftq.sv can wire it straight to the consumer's
  // enable and stays purely structural (7.1). Dropping a stale
  // response is this module's whole job; making the consumer AND
  // two signals would put a piece of that job in the top.
  output logic                     ok_pred_p1,
  output logic                     ok_slot_p2,
  output logic                     ok_meta_p2,
  output logic                     ok_redir_p2,
  output logic                     ok_slot_p3,
  output logic                     ok_meta_p3,
  output logic                     ok_redir_p3,

  // ---- the p0-to-p1 allocation gap, to ftq_ptr ---------------------
  // A PORT 7.3 DOES NOT ANTICIPATE, and the reason is a hole in
  // 5.1's statement of the run-ahead.
  //
  // 5.1 gives the gap between fetch_ptr and alloc_ptr as the
  // predicted-but-unfetched run-ahead. alloc_ptr advances at p0
  // (5.2) and the entry CONTENT is written at p1, one cycle later,
  // so for that one cycle the newest entry inside the gap has an
  // index and no content. A fetch issued on the raw gap reads it
  // and presents an unwritten pc to the IFU. It is reachable in the
  // first two cycles out of reset, not in a corner.
  //
  // This module already knows: stage 0 holds the request accepted
  // last cycle, which is the request at p1 now, whose entry write
  // lands at the end of this cycle. So the WRITTEN frontier is
  // alloc_ptr minus this bit, and ftq_ptr subtracts it before
  // forming fetch_pending. Reported in the BP-107 Results Capture.
  output logic                     alloc_inflight,

  // ---- observation, for the bound properties -----------------------
  output logic [3:0]               shadow_val,
  output logic [FTQ_PTR_BITS-1:0]  shadow_ptr [0:3]
);

  // The stage clear decision, one bit per stage.
  logic [3:0]              w_clr;
  logic [FTQ_PTR_BITS-1:0] w_squash_len;
  logic [FTQ_PTR_BITS-1:0] w_age [0:3];

  // The three registered stages, p1 through p3. Stage 0 is
  // combinational; see the header.
  logic [3:1]              r_val;
  logic [FTQ_PTR_BITS-1:0] r_ptr [1:3];

  // -----------------------------------------------------------------
  // Which stages the redirect squashes, and the accept terms.
  // -----------------------------------------------------------------
  // Membership of [squash_start, squash_end) is an AGE taken against
  // squash_start, exactly as in ftq_status: entry P is in the range
  // when (P - start) is below the length. Ages, not raw pointers,
  // because a raw compare reports the wrong set on every range that
  // crosses the wrap.
  // THE ACCEPT TERMS READ ONLY THE FLOPS. They are in their own
  // always_comb, separate from the stage-0 view below, and that
  // separation is structural rather than cosmetic: stage 0 is the
  // request ftq_npc is presenting THIS CYCLE, and the accept terms
  // feed ftq_npc's own arbitration. Computing both in one block
  // makes ftq_npc depend on a block that depends on ftq_npc, and
  // the lint reports that as UNOPTFLAT even though no signal
  // actually closes the loop. Stage 0 takes part in the CLEAR and
  // in nothing else, and the clear goes only to the flops.
  always_comb begin : accepts
    ok_pred_p1  = gv_pred_p1 && r_val[1] &&
      (r_ptr[1][FTQ_IDX_BITS-1:0] == idx_pred_p1);

    ok_slot_p2  = gv_slot_p2 && r_val[2] &&
      (r_ptr[2][FTQ_IDX_BITS-1:0] == idx_slot_p2);
    ok_meta_p2  = gv_meta_p2 && r_val[2] &&
      (r_ptr[2][FTQ_IDX_BITS-1:0] == idx_meta_p2);
    ok_redir_p2 = r_val[2] &&
      (r_ptr[2][FTQ_IDX_BITS-1:0] == idx_redir_p2);

    ok_slot_p3  = gv_slot_p3 && r_val[3] &&
      (r_ptr[3][FTQ_IDX_BITS-1:0] == idx_slot_p3);
    ok_meta_p3  = gv_meta_p3 && r_val[3] &&
      (r_ptr[3][FTQ_IDX_BITS-1:0] == idx_meta_p3);
    ok_redir_p3 = r_val[3] &&
      (r_ptr[3][FTQ_IDX_BITS-1:0] == idx_redir_p3);

    // The request whose p1 write has not landed is the one AT p1.
    // See the alloc_inflight port comment.
    alloc_inflight = r_val[1];
  end

  // -----------------------------------------------------------------
  // The stage view, and which stages the redirect squashes.
  // -----------------------------------------------------------------
  // Membership of [squash_start, squash_end) is an AGE taken against
  // squash_start, exactly as in ftq_status: entry P is in the range
  // when (P - start) is below the length. Ages, not raw pointers,
  // because a raw compare reports the wrong set on every range that
  // crosses the wrap.
  //
  // Stage 0 IS the presented request -- a p0 request has not been
  // registered anywhere yet, in the cluster or here -- so it is
  // taken straight from the port. Stages 1 to 3 are the flops.
  always_comb begin : classify
    w_squash_len  = squash_end - squash_start;

    shadow_val[0] = req_val;
    shadow_ptr[0] = req_ptr;
    for (int n = 1; n < 4; n++) begin
      shadow_val[n] = r_val[n];
      shadow_ptr[n] = r_ptr[n];
    end

    for (int n = 0; n < 4; n++) begin
      w_age[n] = shadow_ptr[n] - squash_start;
      w_clr[n] = squash_val && shadow_val[n] &&
                 (w_age[n] < w_squash_len);
    end
  end

  // -----------------------------------------------------------------
  // The shift.
  // -----------------------------------------------------------------
  // Unconditional, every cycle. The clear is applied to the value
  // AFTER the shift, because the cluster's stage registers also
  // advance in the redirect cycle: a request at p1 when the redirect
  // fires is at p2 the next cycle, and it is stage 2 that must be
  // clear then. Stage 0 is combinational and is cleared on the way
  // in by the same test.
  always_ff @(posedge clk or negedge rstn) begin : shift
    if (!rstn) begin
      r_val <= '0;
      for (int n = 1; n < 4; n++) begin
        r_ptr[n] <= '0;
      end
    end else begin
      for (int n = 1; n < 4; n++) begin
        r_val[n] <= shadow_val[n-1] && !w_clr[n-1];
        r_ptr[n] <= shadow_ptr[n-1];
      end
    end
  end

endmodule : ftq_shadow
