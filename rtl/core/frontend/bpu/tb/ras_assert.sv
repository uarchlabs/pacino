// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ras (BP-122, TD#170): the BP-121 fix in this
// unit, ras_p2_keep (FE-14, BP-121 D8); and since BP-138 the p2 pop
// against the entries the speculative stack holds (RS2, RS3), since
// BP-143 the chain entries of ras_decisions.md 12.5 PO7 and 12.12 IV1.
//
// BOUND BY MODULE NAME, never by instance name (TD#109). The bind
// connects the module's ports and its own state signals by name in
// its own scope (tosr, tosw, bos, p3_op_q, the arrays, the commit
// stack pointer and count, the p2 and restore snapshots); it makes no
// hierarchical reference.
//
// The source of RS1 is an earlier cycle: the pointers this module
// registered the cycle before, not the next-state expression of
// ras.sv. The source of RS2 and RS3 is a record this module keeps
// itself of which allocation TOSR and each link refer to (see THE
// CHAIN below), not the empty test of ras.sv (TOSR == BOS) or the
// order of TOSR and BOS.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ras_assert (
  input logic                    clk,
  input logic                    rstn,
  input logic                    ras_p2_keep,
  input logic                    ras_restore_val,
  input logic                    ras_pred_val_p3 [0:NUM_PRED_SLOTS-1],
  input bp_br_type_e             ras_br_type_p3  [0:NUM_PRED_SLOTS-1],
  input logic [RAS_PTR_BITS-1:0] tosr,
  input logic [RAS_PTR_BITS-1:0] tosw,
  input logic [1:0]              p3_op_q [0:NUM_PRED_SLOTS-1],
  // RS2, RS3 (BP-138, BP-143).
  input logic                    ras_pred_val_p2  [0:NUM_PRED_SLOTS-1],
  input bp_br_type_e             ras_br_type_p2   [0:NUM_PRED_SLOTS-1],
  input logic                    ras_pop_valid_p2 [0:NUM_PRED_SLOTS-1],
  input logic [VA_WIDTH-1:0]     ras_pop_addr_p2  [0:NUM_PRED_SLOTS-1],
  input bp_ras_snapshot_t        ras_snapshot_p2  [0:NUM_PRED_SLOTS-1],
  input bp_ras_snapshot_t        ras_restore_snapshot,
  input logic [RAS_PTR_BITS-1:0] bos,
  input logic [VA_WIDTH-1:0]     spec_ret_addr    [0:RAS_SPEC_ENTRIES-1],
  input logic [RAS_PTR_BITS-1:0] spec_nos         [0:RAS_SPEC_ENTRIES-1],
  input logic                    spec_bot         [0:RAS_SPEC_ENTRIES-1],
  input logic [VA_WIDTH-1:0]     commit_ret_addr  [0:RAS_COMMIT_ENTRIES-1],
  input logic [RAS_COMMIT_PTR_BITS-1:0] csp,
  input logic [RAS_COMMIT_PTR_BITS:0]   c_cnt
);

  // The cycle before: the p2 pass was dropped and nothing else could
  // move the speculative pointers: no restore, and no p3 repair. The
  // repair acts only where the p3 view of a slot (push for a call,
  // pop for a return, both for a return-call, ras_decisions.md 1)
  // differs from the operation registered at p2, so the view is
  // derived here from the p3 inputs and compared.
  logic                    r_quiet;
  logic [RAS_PTR_BITS-1:0] r_tosr;
  logic [RAS_PTR_BITS-1:0] r_tosw;
  logic                    w_quiet;
  // No p3 repair this cycle: every slot's p3 view equals its
  // registered p2 operation (RS1, RS2, RS3).
  logic                    w_rep_idle;

  always_comb begin : quiet
    logic [1:0] view;
    w_rep_idle = 1'b1;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      view = 2'b00;
      if (ras_pred_val_p3[s]) begin
        case (ras_br_type_p3[s])
          DIRECT_CALL, INDIRECT_CALL: view = 2'b01;
          RETURN:                     view = 2'b10;
          RETURN_CALL:                view = 2'b11;
          default:                    view = 2'b00;
        endcase
      end
      if (view != p3_op_q[s]) w_rep_idle = 1'b0;
    end
    w_quiet = !ras_p2_keep && !ras_restore_val && w_rep_idle;
  end

  // -----------------------------------------------------------------
  // THE CHAIN (RS2 / RS3; BP-143, ras_decisions.md 3.2 TOSR BELOW BOS,
  // 12.5 PO7, 12.12 IV1). A chain entry is an entry a push wrote, at
  // TOSR or reached from it by the links, above BOS in allocation order
  // or below it. This module keeps:
  //   - r_seq[i]: the sequence number of index i's last allocation.
  //     TOSW only moves forward except on a restore, and every index it
  //     moves past is allocated in that order, except BOS: the sentinel
  //     skip moves TOSW past BOS without writing it (3.2). The sequence
  //     numbers start at 1 and do not wrap; 0 is none.
  //   - r_ref: the allocation TOSR named the cycle before, and r_ref2
  //     the cycle before that (an undo returns TOSR there).
  //   - r_nidx[i], r_nref[i]: the index and the allocation the link of
  //     index i's last allocation named, recorded when it was
  //     allocated (none for a bottom entry, whose pop goes to BOS).
  //   - a record per snapshot value of the allocation its TOSR named
  //     (m_ep / m_val), read by a restore.
  // Each cycle w_ref, the allocation TOSR names now, is found from
  // these alone: a TOSR allocated this cycle names that allocation; a
  // TOSR the cycle before named, or one its links reach, or the one two
  // cycles before (an undo), names what this record says; after a
  // restore, what the record of the snapshot says, or for a snapshot
  // this module never saw, the allocation the index holds. Anything
  // else names none. ras.sv answers a different question (TOSR == BOS)
  // with its own rules; this record reads neither them nor the order
  // of TOSR and BOS. Only the index of a new entry's link is taken from
  // the array, when the entry is written, and it is resolved against
  // this record.
  //
  // TOSR == BOS is the empty stack: there w_ref is none (the entry at
  // BOS is the sentinel, PO7). A chain entry whose index was
  // reallocated since (r_seq[tosr] != w_ref) is the wrap: its pop
  // returns the reusing push's address, counted in r_nreuse, not
  // failed (PO7, PU3, RE7). Until BP-143 the stack held TOSR only when
  // TOSR was allocated after BOS (r_seq[tosr] > r_seq[bos]).
  // -----------------------------------------------------------------
  localparam int SEQ_W  = 32;
  localparam int SNAP_W = $bits(bp_ras_snapshot_t);
  localparam int EP_W   = 16;
  logic [SEQ_W-1:0]        r_seq  [0:RAS_SPEC_ENTRIES-1];
  logic [RAS_PTR_BITS-1:0] r_nidx [0:RAS_SPEC_ENTRIES-1];
  logic [SEQ_W-1:0]        r_nref [0:RAS_SPEC_ENTRIES-1];
  logic [SEQ_W-1:0]        r_gen;
  logic                    r_rst;
  logic [RAS_PTR_BITS-1:0] r_bos;
  logic [SEQ_W-1:0]        r_ref;
  logic [SEQ_W-1:0]        r_ref2;
  logic [RAS_PTR_BITS-1:0] r_tosr2;
  // The restore at the edge into this cycle: the record of its snapshot.
  logic                    r_rfound;
  logic [SEQ_W-1:0]        r_rval;
  logic [RAS_PTR_BITS-1:0] r_rtosr;
  logic                    r_rempty;
  // The last slot's p2 snapshot the cycle before (the FTQ's, 4.2), and
  // whether that cycle's p2 pass was kept.
  bp_ras_snapshot_t        r_snap;
  logic                    r_keep;
  // The snapshot record, by snapshot value. An entry is current when
  // its epoch is this reset's (r_ep); a reset advances r_ep, which
  // clears the record.
  logic [EP_W-1:0]         m_ep  [0:(1 << SNAP_W)-1];
  logic [SEQ_W-1:0]        m_val [0:(1 << SNAP_W)-1];
  logic [EP_W-1:0]         r_ep;
  // Pops of a reused chain entry (the wrap) RS2 counted.
  int unsigned             r_nreuse;

  logic [SEQ_W-1:0]        w_seq  [0:RAS_SPEC_ENTRIES-1];
  logic [RAS_PTR_BITS-1:0] w_nidx [0:RAS_SPEC_ENTRIES-1];
  logic [SEQ_W-1:0]        w_nref [0:RAS_SPEC_ENTRIES-1];
  logic [SEQ_W-1:0]        w_gen;
  logic [SEQ_W-1:0]        w_raw;     // w_ref before the empty test
  logic [SEQ_W-1:0]        w_ref;     // the allocation TOSR names
  logic                    w_chain;   // TOSR names a chain entry
  logic                    w_reused;  // ... whose index was reallocated
  logic                    w_snap_we; // record r_snap's allocation
  logic                    w_reuse_pop;
  // A slot whose pop reads TOSR as the cycle starts: no repair, and no
  // RAS operation in a lower slot.
  logic                    w_first [0:NUM_PRED_SLOTS-1];
  logic [RAS_COMMIT_PTR_BITS-1:0] w_ctop;

  // The allocation index j names, from the record of the cycle before:
  // TOSR then, the entries its links reach, TOSR two cycles before and
  // the entries its links reach. None when no record names j.
  function automatic logic [SEQ_W-1:0] f_resolve(
      input logic [RAS_PTR_BITS-1:0] j);
    logic [RAS_PTR_BITS-1:0] ci;
    logic [SEQ_W-1:0]        cr;
    logic [SEQ_W-1:0]        res;
    logic                    hit;
    res = '0;
    hit = 1'b0;
    for (int b = 0; b < 2; b++) begin
      ci = (b == 0) ? r_tosr : r_tosr2;
      cr = (b == 0) ? r_ref  : r_ref2;
      for (int k = 0; k <= RAS_SPEC_ENTRIES; k++) begin
        if (!hit && (cr != '0)) begin
          if (ci == j) begin
            res = cr;
            hit = 1'b1;
          end else begin
            cr = r_nref[ci];
            ci = r_nidx[ci];
          end
        end
      end
    end
    return res;
  endfunction

  always_comb begin : chain
    logic [RAS_PTR_BITS-1:0] n;
    logic [RAS_PTR_BITS-1:0] d;
    logic [RAS_PTR_BITS-1:0] dj;
    logic [RAS_PTR_BITS-1:0] j;
    logic                    nw_t;
    logic                    op;
    j  = '0;
    dj = '0;
    n  = r_rst ? '0 : (tosw - r_tosw);  // indices allocated
    for (int i = 0; i < RAS_SPEC_ENTRIES; i++) begin
      d = RAS_PTR_BITS'(i) - r_tosw;       // position past old TOSW
      w_seq[i]  = r_seq[i];
      w_nidx[i] = r_nidx[i];
      w_nref[i] = r_nref[i];
      if ((d < n) && (RAS_PTR_BITS'(i) != r_bos)) begin
        w_seq[i]  = r_gen + SEQ_W'(d) + SEQ_W'(1);
        // The new entry's link: none for a bottom entry; else the
        // allocation its link index names, an entry allocated earlier
        // this cycle or one the record of the cycle before names.
        j         = spec_nos[i];
        dj        = j - r_tosw;
        w_nidx[i] = j;
        if (spec_bot[i])
          w_nref[i] = '0;
        else if ((dj < d) && (j != r_bos))
          w_nref[i] = r_gen + SEQ_W'(dj) + SEQ_W'(1);
        else
          w_nref[i] = f_resolve(j);
      end
    end
    w_gen = r_gen + SEQ_W'(n);

    // The allocation TOSR names.
    d    = tosr - r_tosw;
    nw_t = (d < n) && (tosr != r_bos);
    if (r_rst)
      w_raw = r_rempty ? '0 : (r_rfound ? r_rval : r_seq[r_rtosr]);
    else if (nw_t)
      w_raw = w_seq[tosr];
    else
      w_raw = f_resolve(tosr);
    w_ref    = (tosr == bos) ? '0 : w_raw;
    w_chain  = (tosr != bos) && (w_ref != '0);
    w_reused = w_chain && (w_seq[tosr] != w_ref);
    // The snapshot the cycle before is this cycle's TOSR when the p2
    // pass was kept and no restore intervened.
    w_snap_we = !r_rst && r_keep && (r_snap.tosr == tosr) &&
                (r_snap.tosr != r_snap.bos) && (w_raw != '0);

    op = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      w_first[s] = w_rep_idle && !op;
      op = op || (ras_pred_val_p2[s] &&
                  (ras_br_type_p2[s] inside {DIRECT_CALL, INDIRECT_CALL,
                                             RETURN, RETURN_CALL}));
    end
    w_reuse_pop = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++)
      if (w_first[s] && ras_pop_valid_p2[s] && w_reused) w_reuse_pop = 1'b1;
    w_ctop = csp - RAS_COMMIT_PTR_BITS'(1);
  end

  always_ff @(posedge clk) begin : hist
    if (!rstn) begin
      r_quiet  <= 1'b0;
      r_tosr   <= '0;
      r_tosw   <= '0;
      r_rst    <= 1'b0;
      r_bos    <= '0;
      r_gen    <= '0;
      r_ref    <= '0;
      r_ref2   <= '0;
      r_tosr2  <= '0;
      r_rfound <= 1'b0;
      r_rval   <= '0;
      r_rtosr  <= '0;
      r_rempty <= 1'b0;
      r_snap   <= '0;
      r_keep   <= 1'b0;
      r_ep     <= r_ep + EP_W'(1);
      r_nreuse <= 0;
      for (int i = 0; i < RAS_SPEC_ENTRIES; i++) begin
        r_seq[i]  <= '0;
        r_nidx[i] <= '0;
        r_nref[i] <= '0;
      end
    end else begin
      r_quiet  <= w_quiet;
      r_tosr   <= tosr;
      r_tosw   <= tosw;
      r_rst    <= ras_restore_val;
      r_bos    <= bos;
      r_gen    <= w_gen;
      r_ref    <= w_raw;
      r_ref2   <= r_ref;
      r_tosr2  <= r_tosr;
      r_rfound <= (m_ep[ras_restore_snapshot] == r_ep);
      r_rval   <= m_val[ras_restore_snapshot];
      r_rtosr  <= ras_restore_snapshot.tosr;
      r_rempty <= (ras_restore_snapshot.tosr == ras_restore_snapshot.bos);
      r_snap   <= ras_snapshot_p2[NUM_PRED_SLOTS-1];
      r_keep   <= ras_p2_keep && !ras_restore_val;
      if (w_snap_we) begin
        m_ep[r_snap]  <= r_ep;
        m_val[r_snap] <= w_raw;
      end
      if (w_reuse_pop) r_nreuse <= r_nreuse + 1;
      for (int i = 0; i < RAS_SPEC_ENTRIES; i++) begin
        r_seq[i]  <= w_seq[i];
        r_nidx[i] <= w_nidx[i];
        r_nref[i] <= w_nref[i];
      end
    end
  end

  final $display("ras_assert %m: RS2 pops of a reused chain entry (wrap) %0d",
                 r_nreuse);

  // RS1 BP-121 D8 (m08), FE-14. A block a redirect squashes at p2
  //     makes no RAS operation: with ras_p2_keep low, and no restore
  //     and no p3 repair that cycle, the speculative pointers do not
  //     move, whatever the p2 inputs ask for. Before BP-121 the
  //     squashed block still pushed or popped on the restored stack.
  property p_dropped_p2_moves_nothing;
    @(posedge clk) disable iff (!rstn)
      r_quiet |-> (tosr == r_tosr) && (tosw == r_tosw);
  endproperty

  a_dropped_p2_moves_nothing: assert property (p_dropped_p2_moves_nothing)
    else $error("RS1 a squashed p2 block moved the RAS pointers");

  // RS2 BP-138 (D2), BP-143; ras_decisions.md 12.5 PO7, 12.12 IV1. A
  //     valid p2 pop returns a chain entry. With TOSR != BOS, TOSR must
  //     name one by the record above (above or below BOS) and the pop
  //     returns the entry at TOSR: the chain entry, or, when its index
  //     was reallocated since, the reusing push's address (the wrap,
  //     counted in r_nreuse, not failed). With TOSR == BOS the pop is
  //     the commit-stack fallback: valid only with the commit stack
  //     non-empty, and its top. fd07 (BP-138): a commit moved BOS past
  //     an empty stack and left TOSR != BOS on the old BOS slot, which
  //     no push on the chain wrote; the pop returned it (0x0). Until
  //     BP-143 RS2 also failed a chain entry below BOS (BP-142 TC-65).
  // RS3 BP-138, BP-143. The converse: a chain entry at TOSR pops valid
  //     and returns the entry at TOSR, so the fix for RS2 does not
  //     empty a stack that holds entries.
  // Checked for a slot whose pop reads TOSR as the cycle starts: the
  // first slot with a RAS operation, in a cycle with no repair.
  for (genvar gs = 0; gs < NUM_PRED_SLOTS; gs++) begin : g_rs
    a_pop_only_held: assert property (
      @(posedge clk) disable iff (!rstn)
        (w_first[gs] && ras_pop_valid_p2[gs])
          |-> ((tosr != bos) && w_chain &&
               (ras_pop_addr_p2[gs] == spec_ret_addr[tosr])) ||
              ((tosr == bos) && (c_cnt != '0) &&
               (ras_pop_addr_p2[gs] == commit_ret_addr[w_ctop])))
      else $error(
        "RS2 slot %0d popped tosr %0d bos %0d: no chain entry, not fallback",
        gs, tosr, bos);

    a_held_pops_top: assert property (
      @(posedge clk) disable iff (!rstn)
        (w_first[gs] && ras_pred_val_p2[gs] && w_chain &&
         (ras_br_type_p2[gs] inside {RETURN, RETURN_CALL}))
          |-> ras_pop_valid_p2[gs] &&
              (ras_pop_addr_p2[gs] == spec_ret_addr[tosr]))
      else $error(
        "RS3 slot %0d: chain entry tosr %0d bos %0d alloc %0d not popped",
        gs, tosr, bos, w_ref);
  end

endmodule : ras_assert

// Bind BY MODULE NAME.
bind ras ras_assert u_assert (
  .clk                  (clk),
  .rstn                 (rstn),
  .ras_p2_keep          (ras_p2_keep),
  .ras_restore_val      (ras_restore_val),
  .ras_pred_val_p3      (ras_pred_val_p3),
  .ras_br_type_p3       (ras_br_type_p3),
  .tosr                 (tosr),
  .tosw                 (tosw),
  .p3_op_q              (p3_op_q),
  .ras_pred_val_p2      (ras_pred_val_p2),
  .ras_br_type_p2       (ras_br_type_p2),
  .ras_pop_valid_p2     (ras_pop_valid_p2),
  .ras_pop_addr_p2      (ras_pop_addr_p2),
  .ras_snapshot_p2      (ras_snapshot_p2),
  .ras_restore_snapshot (ras_restore_snapshot),
  .bos                  (bos),
  .spec_ret_addr        (spec_ret_addr),
  .spec_nos             (spec_nos),
  .spec_bot             (spec_bot),
  .commit_ret_addr      (commit_ret_addr),
  .csp                  (csp),
  .c_cnt                (c_cnt)
);
