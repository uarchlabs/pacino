// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ras (BP-122, TD#170): the BP-121 fix in this
// unit, ras_p2_keep (FE-14, BP-121 D8); and since BP-138 the p2 pop
// against the entries the speculative stack holds (RS2, RS3), since
// BP-143 the chain entries of ras_decisions.md 12.5 PO7 and 12.12 IV1,
// since BP-144 at every pop of every slot, in repair cycles too (IV2),
// and the converse of IV1 (RS4) and the fallback pop (RS5).
//
// BOUND BY MODULE NAME, never by instance name (TD#109). The bind
// connects the module's ports and its own state signals by name in
// its own scope (tosr, tosw, bos, p3_op_q, the arrays, the commit
// stack pointer and count, the p2, restore and commit snapshots); it
// makes no hierarchical reference.
//
// The source of RS1 is an earlier cycle: the pointers this module
// registered the cycle before, not the next-state expression of
// ras.sv. The source of RS2 to RS5 is a record this module keeps
// itself of which allocation TOSR, BOS and each link refer to (see THE
// CHAIN below), and its own walk of each cycle's operations by the
// rules of ras_decisions.md 12 (see THE SCAN below), not the empty test
// of ras.sv or its scan.
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
  // RS2 to RS5 (BP-138, BP-143, BP-144).
  input logic                    ras_pred_val_p2  [0:NUM_PRED_SLOTS-1],
  input bp_br_type_e             ras_br_type_p2   [0:NUM_PRED_SLOTS-1],
  input logic [VA_WIDTH-1:0]     ras_fall_through_p2 [0:NUM_PRED_SLOTS-1],
  input logic                    ras_pop_valid_p2 [0:NUM_PRED_SLOTS-1],
  input logic [VA_WIDTH-1:0]     ras_pop_addr_p2  [0:NUM_PRED_SLOTS-1],
  input bp_ras_snapshot_t        ras_snapshot_p2  [0:NUM_PRED_SLOTS-1],
  input bp_ras_snapshot_t        ras_restore_snapshot,
  input logic                    ras_commit_val,
  input bp_br_type_e             ras_commit_br_type,
  input bp_ras_snapshot_t        ras_commit_snapshot,
  input logic [RAS_PTR_BITS-1:0] bos,
  input logic [VA_WIDTH-1:0]     spec_ret_addr    [0:RAS_SPEC_ENTRIES-1],
  input logic [RAS_RCTR_WIDTH-1:0] spec_rctr      [0:RAS_SPEC_ENTRIES-1],
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
  // registered p2 operation (RS1).
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
  // THE CHAIN (RS2 to RS5; BP-143, BP-144, ras_decisions.md 3.2 TOSR
  // BELOW BOS, 12.5 PO7, 12.12 IV1). A chain entry is an entry a push
  // wrote, at TOSR or reached from it by the links, above BOS in
  // allocation order or below it. This module keeps:
  //   - r_seq[i]: the sequence number of index i's last allocation.
  //     TOSW only moves forward except on a restore, and every index it
  //     moves past is allocated in that order, except BOS: the sentinel
  //     skip moves TOSW past BOS without writing it (3.2). The sequence
  //     numbers start at 1 and do not wrap; 0 is none.
  //   - r_ref: the allocation TOSR named the cycle before, and r_ref2
  //     the cycle before that (an undo returns TOSR there).
  //   - r_pt, r_pref: the TOSR and the allocation it names that THE
  //     SCAN below derived for the end of the cycle before (BP-144).
  //   - r_nidx[i], r_nref[i]: the index and the allocation the link of
  //     index i's last allocation named, recorded when it was
  //     allocated (none for a bottom entry, whose pop goes to BOS).
  //   - r_bref (BP-144): the allocation BOS names, the entry whose
  //     commit made it the boundary. A commit that moves BOS takes the
  //     allocation its snapshot's TOSR named (none for a snapshot of an
  //     empty stack); a restore takes the record of its snapshot.
  //   - a record per snapshot value of the allocations its TOSR and its
  //     BOS named (m_ep / m_val / m_bval), read by a restore or a
  //     commit.
  // Each cycle w_ref, the allocation TOSR names now, is found from
  // these alone: after a restore, what the record of the snapshot
  // says, or for a snapshot this module never saw, the allocation the
  // index holds; a TOSR the scan of the cycle before left names what
  // the scan said; a TOSR allocated this cycle names that allocation;
  // a TOSR the cycle before named, or one its links reach, or the one
  // two cycles before (an undo), names what this record says. Anything
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
  //
  // THE CONVERSE (RS4, BP-144; IV1 "exactly when"). TOSR == BOS while
  // the record names a live chain entry at TOSR, one that is not the
  // allocation BOS names and whose index still holds it, is a fault:
  // BOS moved onto a live entry, or TOSR was left on one, and the stack
  // reads empty over it (BP-143 Problem 5: tb_ras TC-44 with c_bos
  // moving BOS on every RETURN commit). A chain entry at BOS that the
  // allocator has reused since is the wrap, counted in r_nbwrap.
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
  logic [SEQ_W-1:0]        r_bref;
  // The scan's end of the cycle before (BP-144).
  logic                    r_pv;
  logic [RAS_PTR_BITS-1:0] r_pt;
  logic [SEQ_W-1:0]        r_pref;
  // The restore at the edge into this cycle: the record of its snapshot.
  logic                    r_rfound;
  logic [SEQ_W-1:0]        r_rval;
  logic [SEQ_W-1:0]        r_rbval;
  logic [RAS_PTR_BITS-1:0] r_rtosr;
  logic                    r_rempty;
  // The commit at the edge into this cycle (BP-144).
  logic                    r_cv;      // a RETURN, call or RETURN_CALL
  logic                    r_cpush;   // with a call arm
  bp_ras_snapshot_t        r_csnap;
  logic                    r_cfound;
  logic [SEQ_W-1:0]        r_cval;
  // The last slot's p2 snapshot the cycle before (the FTQ's, 4.2), and
  // whether that cycle's p2 pass was kept.
  bp_ras_snapshot_t        r_snap;
  logic                    r_keep;
  // The snapshot record, by snapshot value. An entry is current when
  // its epoch is this reset's (r_ep); a reset advances r_ep, which
  // clears the record.
  logic [EP_W-1:0]         m_ep   [0:(1 << SNAP_W)-1];
  logic [SEQ_W-1:0]        m_val  [0:(1 << SNAP_W)-1];
  logic [SEQ_W-1:0]        m_bval [0:(1 << SNAP_W)-1];
  logic [EP_W-1:0]         r_ep;
  // Pops of a reused chain entry (the wrap) RS2 counted, and chain
  // entries at BOS reused since (the wrap) RS4 counted. Totals over the
  // whole run: set once at time 0, not cleared by a reset (BP-144; until
  // then r_nreuse counted from the last reset only).
  int unsigned             r_nreuse;
  int unsigned             r_nbwrap;
  // A stack no push built (BP-144): the last restore loaded a snapshot
  // this module never saw, whose TOSR index no push has allocated (a
  // testbench snapshot, tb_bp_cluster CB5b {5,6,4,3} after reset). No
  // entry on it is a chain entry, so a_state_chain, which judges the
  // state every cycle, would check the stimulus; it is not applied
  // until the stack is next empty, and the cycles are counted. The pop
  // checks RS2 and RS3 are applied as before.
  logic                    r_foreign;
  int unsigned             r_nforeign;

  logic [SEQ_W-1:0]        w_seq  [0:RAS_SPEC_ENTRIES-1];
  logic [RAS_PTR_BITS-1:0] w_nidx [0:RAS_SPEC_ENTRIES-1];
  logic [SEQ_W-1:0]        w_nref [0:RAS_SPEC_ENTRIES-1];
  logic [SEQ_W-1:0]        w_gen;
  logic [SEQ_W-1:0]        w_raw;     // w_ref before the empty test
  logic [SEQ_W-1:0]        w_ref;     // the allocation TOSR names
  logic [SEQ_W-1:0]        w_bref;    // the allocation BOS names
  logic                    w_chain;   // TOSR names a chain entry
  logic                    w_snap_we; // record r_snap's allocations
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
    logic                    cmoved;
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
    else if (r_pv && (tosr == r_pt))
      w_raw = r_pref;
    else if (nw_t)
      w_raw = w_seq[tosr];
    else
      w_raw = f_resolve(tosr);
    w_ref    = (tosr == bos) ? '0 : w_raw;
    w_chain  = (tosr != bos) && (w_ref != '0);

    // The allocation BOS names (BP-144). A commit moved BOS onto its
    // snapshot's TOSR when BOS is there now and either BOS changed or
    // the commit is one CO5 says moves it (a call arm, or a RETURN with
    // a non-empty snapshot). A snapshot of an empty stack names none.
    cmoved = r_cv && (bos == r_csnap.tosr) &&
             ((bos != r_bos) || r_cpush ||
              (r_csnap.tosr != r_csnap.bos));
    if (r_rst)
      w_bref = r_rfound ? r_rbval
                        : ((bos == r_bos) ? r_bref : r_seq[bos]);
    else if (cmoved)
      w_bref = (r_csnap.tosr == r_csnap.bos) ? '0
             : (r_cfound ? r_cval : r_seq[bos]);
    else
      w_bref = r_bref;

    // The snapshot the cycle before is this cycle's TOSR when the p2
    // pass was kept and no restore intervened.
    w_snap_we = !r_rst && r_keep && (r_snap.tosr == tosr);
    w_ctop = csp - RAS_COMMIT_PTR_BITS'(1);
  end

  // -----------------------------------------------------------------
  // THE SCAN (BP-144; ras_decisions.md 12.5, 12.10, 12.7 SL1, 12.12
  // IV2). This module walks each cycle's operations itself, by the
  // rules, from the TOSR the cycle starts with and the allocation the
  // record says it names: the p3 repair of every slot (RP0 to RP9),
  // then the p2 operation of every slot, slot 0 first (SL1, CL4), each
  // on the state the one before left. It keeps a working copy of every
  // entry (address, count, link, bottom, allocation, link allocation),
  // so a slot 1 pop after a slot 0 push in the same cycle reads the
  // pushed entry before the array holds it (IC-RAS-04). The operation
  // each slot made at p2 is registered here (q_*), not read from ras.sv,
  // for the next cycle's repair. At each pop, p2 or a missed pop of the
  // repair, it notes the TOSR the pop reads (e_t), the allocation it
  // names (e_ref) and the address there (e_addr); RS2, RS3, RS4 and RS5
  // check the DUT's pop at every slot against them. Until BP-144 RS2 and
  // RS3 were checked only for the first slot with a RAS operation in a
  // cycle with no repair, from the TOSR the cycle starts with.
  // -----------------------------------------------------------------
  localparam logic [1:0] PK_NONE  = 2'd0;
  localparam logic [1:0] PK_ALLOC = 2'd1;
  localparam logic [1:0] PK_INC   = 2'd2;
  localparam logic [1:0] PK_SAT   = 2'd3;
  localparam logic [RAS_RCTR_WIDTH-1:0] RCTR_MAX = {RAS_RCTR_WIDTH{1'b1}};

  typedef struct packed {
    logic [RAS_SPEC_ENTRIES-1:0][VA_WIDTH-1:0]       a;
    logic [RAS_SPEC_ENTRIES-1:0][RAS_RCTR_WIDTH-1:0] c;
    logic [RAS_SPEC_ENTRIES-1:0][RAS_PTR_BITS-1:0]   n;
    logic [RAS_SPEC_ENTRIES-1:0]                     b;
    logic [RAS_SPEC_ENTRIES-1:0][SEQ_W-1:0]          sq;
    logic [RAS_SPEC_ENTRIES-1:0][SEQ_W-1:0]          nr;
    logic [RAS_PTR_BITS-1:0]                         t;
    logic [RAS_PTR_BITS-1:0]                         tw;
    logic [SEQ_W-1:0]                                rf;
  } sc_t;

  // The registered p2 operation of each slot (RP0) and what it did.
  logic                    q_pop     [0:NUM_PRED_SLOTS-1];
  logic                    q_push    [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0]     q_ft      [0:NUM_PRED_SLOTS-1];
  logic [RAS_PTR_BITS-1:0] q_pre_t   [0:NUM_PRED_SLOTS-1];
  logic [SEQ_W-1:0]        q_pre_rf  [0:NUM_PRED_SLOTS-1];
  logic                    q_pre_emp [0:NUM_PRED_SLOTS-1];
  logic                    q_pop_dec [0:NUM_PRED_SLOTS-1];
  logic [1:0]              q_pk      [0:NUM_PRED_SLOTS-1];
  logic [RAS_PTR_BITS-1:0] q_pk_ptr  [0:NUM_PRED_SLOTS-1];
  logic                    n_pop     [0:NUM_PRED_SLOTS-1];
  logic                    n_push    [0:NUM_PRED_SLOTS-1];
  logic [RAS_PTR_BITS-1:0] n_pre_t   [0:NUM_PRED_SLOTS-1];
  logic [SEQ_W-1:0]        n_pre_rf  [0:NUM_PRED_SLOTS-1];
  logic                    n_pre_emp [0:NUM_PRED_SLOTS-1];
  logic                    n_pop_dec [0:NUM_PRED_SLOTS-1];
  logic [1:0]              n_pk      [0:NUM_PRED_SLOTS-1];
  logic [RAS_PTR_BITS-1:0] n_pk_ptr  [0:NUM_PRED_SLOTS-1];

  // Per slot: the p2 pop (e_*) and the repair's missed pop (e_m*).
  logic                    e_pop     [0:NUM_PRED_SLOTS-1];
  logic [RAS_PTR_BITS-1:0] e_t       [0:NUM_PRED_SLOTS-1];
  logic [SEQ_W-1:0]        e_ref     [0:NUM_PRED_SLOTS-1];
  logic [VA_WIDTH-1:0]     e_addr    [0:NUM_PRED_SLOTS-1];
  logic                    e_chain   [0:NUM_PRED_SLOTS-1];
  logic                    e_reused  [0:NUM_PRED_SLOTS-1];
  logic                    e_conv    [0:NUM_PRED_SLOTS-1];
  logic                    e_mpop    [0:NUM_PRED_SLOTS-1];
  logic [RAS_PTR_BITS-1:0] e_mt      [0:NUM_PRED_SLOTS-1];
  logic [SEQ_W-1:0]        e_mref    [0:NUM_PRED_SLOTS-1];
  logic                    e_mreused [0:NUM_PRED_SLOTS-1];
  logic                    e_mconv   [0:NUM_PRED_SLOTS-1];
  // The state the cycle starts with (IV1, RS2 and RS4 every cycle).
  logic                    w_conv0;
  logic                    w_bwrap;   // a converse hit on a reused index
  logic                    w_reuse_pop;
  logic [RAS_PTR_BITS-1:0] s_rep_t;   // after the repair alone (KP1)
  logic [SEQ_W-1:0]        s_rep_rf;
  logic [RAS_PTR_BITS-1:0] s_fin_t;   // after the p2 pass
  logic [SEQ_W-1:0]        s_fin_rf;

  function automatic logic f_ispush(input logic v, input bp_br_type_e t);
    return v && ((t == DIRECT_CALL) || (t == INDIRECT_CALL) ||
                 (t == RETURN_CALL));                    // CL1
  endfunction

  function automatic logic f_ispop(input logic v, input bp_br_type_e t);
    return v && ((t == RETURN) || (t == RETURN_CALL));   // CL2
  endfunction

  // Remove the top by its link (PO2, PO3, RP1): TOSR to nos, or to BOS
  // for a bottom entry; the allocation named follows the link record.
  function automatic sc_t f_unlink(input sc_t s);
    sc_t r;
    r = s;
    if (r.b[r.t]) begin                                  // PO3
      r.rf = '0;
      r.t  = bos;
    end else begin                                       // PO2
      r.rf = r.nr[r.t];
      r.t  = r.n[r.t];
    end
    return r;
  endfunction

  // A pop of a non-empty stack (PO1 to PO3).
  function automatic sc_t f_pop(input sc_t s, output logic dec);
    sc_t r;
    r   = s;
    dec = 1'b0;
    if (r.c[r.t] != '0) begin                            // PO1
      r.c[r.t] = r.c[r.t] - 1'b1;
      dec      = 1'b1;
    end else begin
      r = f_unlink(r);
    end
    return r;
  endfunction

  // A push (PU1 to PU7); recur 0 is the missed push of RP7. An
  // allocation at index al is numbered as THE CHAIN will number it the
  // next cycle: w_gen plus its position past this cycle's TOSW, plus 1.
  function automatic sc_t f_push(input sc_t s, input logic [VA_WIDTH-1:0] ft,
                                 input logic recur, output logic [1:0] kind,
                                 output logic [RAS_PTR_BITS-1:0] ptr);
    sc_t                     r;
    logic                    skip;
    logic                    emp;
    logic [RAS_PTR_BITS-1:0] al;
    r   = s;
    ptr = r.t;
    emp = (r.t == bos);
    if (recur && !emp && (ft == r.a[r.t])) begin         // PU5, PU7
      if (r.c[r.t] == RCTR_MAX) begin                    // PU6
        kind = PK_SAT;
      end else begin
        kind     = PK_INC;
        r.c[r.t] = r.c[r.t] + 1'b1;
      end
    end else begin
      kind      = PK_ALLOC;
      skip      = (r.tw == bos);                         // PU2
      al        = skip ? (bos + 1'b1) : r.tw;
      r.a[al]   = ft;                                    // PU1, PU8
      r.c[al]   = '0;
      r.n[al]   = skip ? bos : r.t;
      r.b[al]   = skip | emp;
      r.nr[al]  = (skip | emp) ? '0 : r.rf;
      r.sq[al]  = w_gen + SEQ_W'(RAS_PTR_BITS'(al - tosw)) + SEQ_W'(1);
      r.rf      = r.sq[al];
      r.t       = al;
      r.tw      = al + 1'b1;
    end
    return r;
  endfunction

  // Step the count of entry p by one, not past 0 or saturation (RP2,
  // RP4, RP8).
  function automatic sc_t f_adj(input sc_t s, input logic [RAS_PTR_BITS-1:0] p,
                                input logic inc);
    sc_t r;
    r = s;
    if (inc && (r.c[p] != RCTR_MAX))
      r.c[p] = r.c[p] + 1'b1;
    else if (!inc && (r.c[p] != '0))
      r.c[p] = r.c[p] - 1'b1;
    return r;
  endfunction

  // The converse of IV1 at a working state: TOSR == BOS over a live
  // chain entry that is not the allocation BOS names. live 1: the index
  // still holds it (a fault); live 0: reused since (the wrap).
  function automatic logic f_conv(input sc_t s, input logic live);
    return (s.t == bos) && (s.rf != '0) && (s.rf != w_bref) &&
           ((s.sq[s.t] == s.rf) == live);
  endfunction

  always_comb begin : scan
    sc_t                     s;
    logic                    vpop;
    logic                    vpush;
    logic                    d;
    logic [1:0]              k;
    logic [RAS_PTR_BITS-1:0] p;
    d = 1'b0;
    k = PK_NONE;
    p = '0;
    for (int i = 0; i < RAS_SPEC_ENTRIES; i++) begin
      s.a[i]  = spec_ret_addr[i];
      s.c[i]  = spec_rctr[i];
      s.n[i]  = spec_nos[i];
      s.b[i]  = spec_bot[i];
      s.sq[i] = w_seq[i];
      s.nr[i] = w_nref[i];
    end
    s.t  = tosr;
    s.tw = tosw;
    s.rf = w_raw;
    w_conv0 = f_conv(s, 1'b1);
    w_bwrap = f_conv(s, 1'b0);

    // ---- the p3 repair, slot 0 first (RP0 to RP9, RP11) ----
    for (int sl = 0; sl < NUM_PRED_SLOTS; sl++) begin
      vpop  = f_ispop(ras_pred_val_p3[sl], ras_br_type_p3[sl]);    // RP0
      vpush = f_ispush(ras_pred_val_p3[sl], ras_br_type_p3[sl]);
      e_mpop[sl]    = 1'b0;
      e_mt[sl]      = s.t;
      e_mref[sl]    = s.rf;
      e_mreused[sl] = 1'b0;
      e_mconv[sl]   = 1'b0;
      if ((vpop != q_pop[sl]) || (vpush != q_push[sl])) begin
        if (q_pop[sl] && q_push[sl] && !vpop && !vpush) begin
          // RP8 the undo of a whole RETURN_CALL, RP5.
          s.t  = q_pre_emp[sl] ? bos : q_pre_t[sl];
          s.rf = q_pre_emp[sl] ? '0 : q_pre_rf[sl];
          if (q_pop_dec[sl] && (q_pk[sl] == PK_INC)) begin
            // the pop and the push changed one count: they cancel
          end else if (q_pop_dec[sl]) begin
            s = f_adj(s, q_pre_t[sl], 1'b1);
          end else if (q_pk[sl] == PK_INC) begin
            s = f_adj(s, q_pk_ptr[sl], 1'b0);
          end
        end else begin
          if (q_push[sl] && !vpush) begin                  // RP1 to RP3
            if (q_pk[sl] == PK_INC)
              s = f_adj(s, s.t, 1'b0);                     // RP2
            else if ((q_pk[sl] == PK_ALLOC) && (s.t != bos))
              s = f_unlink(s);                             // RP1
          end
          if (q_pop[sl] && !vpop) begin                    // RP4, RP5
            s.t  = q_pre_emp[sl] ? bos : q_pre_t[sl];
            s.rf = q_pre_emp[sl] ? '0 : q_pre_rf[sl];
            if (q_pop_dec[sl]) s = f_adj(s, q_pre_t[sl], 1'b1);
          end else if (!q_pop[sl] && vpop) begin           // RP6
            e_mpop[sl]    = 1'b1;
            e_mt[sl]      = s.t;
            e_mref[sl]    = s.rf;
            e_mreused[sl] = (s.t != bos) && (s.rf != '0) &&
                            (s.sq[s.t] != s.rf);
            e_mconv[sl]   = f_conv(s, 1'b1);
            if (s.t != bos) s = f_pop(s, d);
          end
          if (!q_push[sl] && vpush)                        // RP7
            s = f_push(s, q_ft[sl], 1'b0, k, p);
        end
      end
    end
    s_rep_t  = s.t;
    s_rep_rf = s.rf;

    // ---- the p2 operation, slot 0 first (SL1, CL4) ----
    for (int sl = 0; sl < NUM_PRED_SLOTS; sl++) begin
      e_pop[sl]     = f_ispop(ras_pred_val_p2[sl], ras_br_type_p2[sl]);
      n_pop[sl]     = e_pop[sl];
      n_push[sl]    = f_ispush(ras_pred_val_p2[sl], ras_br_type_p2[sl]);
      n_pre_t[sl]   = s.t;
      n_pre_rf[sl]  = s.rf;
      n_pre_emp[sl] = (s.t == bos);
      n_pop_dec[sl] = 1'b0;
      n_pk[sl]      = PK_NONE;
      n_pk_ptr[sl]  = '0;
      e_t[sl]       = s.t;
      e_ref[sl]     = s.rf;
      e_addr[sl]    = s.a[s.t];
      e_chain[sl]   = (s.t != bos) && (s.rf != '0);
      e_reused[sl]  = e_chain[sl] && (s.sq[s.t] != s.rf);
      e_conv[sl]    = e_pop[sl] && f_conv(s, 1'b1);
      if (e_pop[sl] && (s.t != bos)) begin               // pop first
        s = f_pop(s, d);
        n_pop_dec[sl] = d;
      end
      if (n_push[sl]) begin                              // RC2
        s = f_push(s, ras_fall_through_p2[sl], 1'b1, k, p);
        n_pk[sl]     = k;
        n_pk_ptr[sl] = p;
      end
    end
    s_fin_t  = s.t;
    s_fin_rf = s.rf;

    w_reuse_pop = 1'b0;
    for (int sl = 0; sl < NUM_PRED_SLOTS; sl++)
      if ((e_pop[sl] && ras_pop_valid_p2[sl] && e_reused[sl]) ||
          e_mreused[sl])
        w_reuse_pop = 1'b1;
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
      r_bref   <= '0;
      r_pv     <= 1'b0;
      r_pt     <= '0;
      r_pref   <= '0;
      r_rfound <= 1'b0;
      r_rval   <= '0;
      r_rbval  <= '0;
      r_rtosr  <= '0;
      r_rempty <= 1'b0;
      r_cv     <= 1'b0;
      r_cpush  <= 1'b0;
      r_csnap  <= '0;
      r_cfound <= 1'b0;
      r_cval   <= '0;
      r_snap   <= '0;
      r_keep   <= 1'b0;
      r_ep     <= r_ep + EP_W'(1);
      r_foreign  <= 1'b0;
      for (int i = 0; i < RAS_SPEC_ENTRIES; i++) begin
        r_seq[i]  <= '0;
        r_nidx[i] <= '0;
        r_nref[i] <= '0;
      end
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        q_pop[s]     <= 1'b0;
        q_push[s]    <= 1'b0;
        q_ft[s]      <= '0;
        q_pre_t[s]   <= '0;
        q_pre_rf[s]  <= '0;
        q_pre_emp[s] <= 1'b0;
        q_pop_dec[s] <= 1'b0;
        q_pk[s]      <= PK_NONE;
        q_pk_ptr[s]  <= '0;
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
      r_bref   <= w_bref;
      r_pv     <= !ras_restore_val;
      r_pt     <= ras_p2_keep ? s_fin_t  : s_rep_t;
      r_pref   <= ras_p2_keep ? s_fin_rf : s_rep_rf;
      r_rfound <= (m_ep[ras_restore_snapshot] == r_ep);
      r_rval   <= m_val[ras_restore_snapshot];
      r_rbval  <= m_bval[ras_restore_snapshot];
      r_rtosr  <= ras_restore_snapshot.tosr;
      r_rempty <= (ras_restore_snapshot.tosr == ras_restore_snapshot.bos);
      r_cv     <= ras_commit_val &&
                  (f_ispush(1'b1, ras_commit_br_type) ||
                   f_ispop(1'b1, ras_commit_br_type));
      r_cpush  <= ras_commit_val && f_ispush(1'b1, ras_commit_br_type);
      r_csnap  <= ras_commit_snapshot;
      r_cfound <= (m_ep[ras_commit_snapshot] == r_ep);
      r_cval   <= m_val[ras_commit_snapshot];
      r_snap   <= ras_snapshot_p2[NUM_PRED_SLOTS-1];
      r_keep   <= ras_p2_keep && !ras_restore_val;
      if (w_snap_we) begin
        m_ep[r_snap]   <= r_ep;
        m_val[r_snap]  <= (r_snap.tosr == r_snap.bos) ? '0 : w_raw;
        m_bval[r_snap] <= r_bref;
      end
      if (ras_restore_val)
        r_foreign <= (m_ep[ras_restore_snapshot] != r_ep) &&
                     (ras_restore_snapshot.tosr != ras_restore_snapshot.bos) &&
                     (w_seq[ras_restore_snapshot.tosr] == '0);
      else if (tosr == bos)
        r_foreign <= 1'b0;
      for (int i = 0; i < RAS_SPEC_ENTRIES; i++) begin
        r_seq[i]  <= w_seq[i];
        r_nidx[i] <= w_nidx[i];
        r_nref[i] <= w_nref[i];
      end
      // The operation each slot made (RE3, KP1: none when dropped).
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        q_pop[s]     <= n_pop[s]  && ras_p2_keep && !ras_restore_val;
        q_push[s]    <= n_push[s] && ras_p2_keep && !ras_restore_val;
        q_ft[s]      <= ras_fall_through_p2[s];
        q_pre_t[s]   <= n_pre_t[s];
        q_pre_rf[s]  <= n_pre_rf[s];
        q_pre_emp[s] <= n_pre_emp[s];
        q_pop_dec[s] <= n_pop_dec[s];
        q_pk[s]      <= n_pk[s];
        q_pk_ptr[s]  <= n_pk_ptr[s];
      end
    end
  end

  // The run totals: zero at time 0, counted while rstn is high, not
  // cleared by a reset.
  initial begin
    r_nreuse   = 0;
    r_nbwrap   = 0;
    r_nforeign = 0;
  end

  always @(posedge clk) begin : totals
    if (rstn) begin
      if (w_reuse_pop) r_nreuse <= r_nreuse + 1;
      if (w_bwrap)     r_nbwrap <= r_nbwrap + 1;
      if (r_foreign && (tosr != bos)) r_nforeign <= r_nforeign + 1;
    end
  end

  final begin
    $display("ras_assert %m: RS2 pops of a reused chain entry (wrap) %0d",
             r_nreuse);
    $display("ras_assert %m: RS4 reused chain entries at BOS (wrap) %0d",
             r_nbwrap);
    $display("ras_assert %m: a_state_chain not applied, cycles on a %s %0d",
             "stack no push built", r_nforeign);
  end

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

  // RS2 BP-138 (D2), BP-143, BP-144; ras_decisions.md 12.5 PO7, 12.12
  //     IV1, IV2. A valid p2 pop returns a chain entry. With TOSR != BOS
  //     at the pop (THE SCAN's e_t), TOSR must name one by the record
  //     above (above or below BOS) and the pop returns the entry there:
  //     the chain entry, or, when its index was reallocated since, the
  //     reusing push's address (the wrap, counted in r_nreuse, not
  //     failed). With TOSR == BOS the pop is the commit-stack fallback:
  //     valid only with the commit stack non-empty, and its top. fd07
  //     (BP-138): a commit moved BOS past an empty stack and left TOSR
  //     != BOS on the old BOS slot, which no push on the chain wrote;
  //     the pop returned it (0x0). Until BP-143 RS2 also failed a chain
  //     entry below BOS (BP-142 TC-65); until BP-144 it was checked only
  //     for the first slot with a RAS operation in a cycle with no
  //     repair. a_rep_pop_held is the same rule for the missed pop of a
  //     p3 repair (RP6), which makes no output; a_state_chain is IV1 on
  //     the state every cycle.
  // RS3 BP-138, BP-143, BP-144. The converse: a chain entry at the TOSR
  //     a p2 pop reads pops valid and returns the entry there, so the
  //     fix for RS2 does not empty a stack that holds entries.
  // RS4 BP-144; IV1 "exactly when", PO7 "never the BOS sentinel". TOSR
  //     == BOS never holds over a live chain entry other than the one
  //     BOS names (THE CONVERSE above): every cycle, and at every pop.
  // RS5 BP-144; IV2, PO5, PO6, PO9. A p2 pop at TOSR == BOS is valid
  //     exactly when the commit stack holds an entry, and returns its
  //     top; a slot that does not pop drives valid 0.
  for (genvar gs = 0; gs < NUM_PRED_SLOTS; gs++) begin : g_rs
    a_pop_only_held: assert property (
      @(posedge clk) disable iff (!rstn)
        (e_pop[gs] && ras_pop_valid_p2[gs])
          |-> ((e_t[gs] != bos) && e_chain[gs] &&
               (ras_pop_addr_p2[gs] == e_addr[gs])) ||
              ((e_t[gs] == bos) && (c_cnt != '0) &&
               (ras_pop_addr_p2[gs] == commit_ret_addr[w_ctop])))
      else $error(
        "RS2 slot %0d popped tosr %0d bos %0d alloc %0d: %s",
        gs, e_t[gs], bos, e_ref[gs],
        "no chain entry, not the entry there, not fallback");

    a_rep_pop_held: assert property (
      @(posedge clk) disable iff (!rstn)
        (e_mpop[gs] && (e_mt[gs] != bos)) |-> (e_mref[gs] != '0))
      else $error("RS2 slot %0d repair missed pop at tosr %0d bos %0d: %s",
                  gs, e_mt[gs], bos, "no chain entry");

    a_held_pops_top: assert property (
      @(posedge clk) disable iff (!rstn)
        (e_pop[gs] && e_chain[gs])
          |-> ras_pop_valid_p2[gs] &&
              (ras_pop_addr_p2[gs] == e_addr[gs]))
      else $error(
        "RS3 slot %0d: chain entry tosr %0d bos %0d alloc %0d not popped",
        gs, e_t[gs], bos, e_ref[gs]);

    a_pop_not_on_live_bos: assert property (
      @(posedge clk) disable iff (!rstn)
        !e_conv[gs] && !e_mconv[gs])
      else $error(
        "RS4 slot %0d pop at tosr %0d == bos over live alloc %0d (bos %0d)",
        gs, e_conv[gs] ? e_t[gs] : e_mt[gs],
        e_conv[gs] ? e_ref[gs] : e_mref[gs], w_bref);

    a_fallback_pop: assert property (
      @(posedge clk) disable iff (!rstn)
        (e_pop[gs] && (e_t[gs] == bos))
          ? ((ras_pop_valid_p2[gs] == (c_cnt != '0)) &&
             (!ras_pop_valid_p2[gs] ||
              (ras_pop_addr_p2[gs] == commit_ret_addr[w_ctop])))
          : (e_pop[gs] || !ras_pop_valid_p2[gs]))
      else $error("RS5 slot %0d fallback pop valid %0d with count %0d",
                  gs, ras_pop_valid_p2[gs], c_cnt);
  end

  a_state_chain: assert property (
    @(posedge clk) disable iff (!rstn)
      ((tosr != bos) && !r_foreign) |-> w_chain)
    else $error("RS2 state: tosr %0d != bos %0d names no chain entry",
                tosr, bos);

  a_empty_not_chain: assert property (
    @(posedge clk) disable iff (!rstn)
      !w_conv0)
    else $error(
      "RS4 state: tosr %0d == bos reads empty over live alloc %0d (bos %0d)",
      tosr, w_raw, w_bref);

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
  .ras_fall_through_p2  (ras_fall_through_p2),
  .ras_pop_valid_p2     (ras_pop_valid_p2),
  .ras_pop_addr_p2      (ras_pop_addr_p2),
  .ras_snapshot_p2      (ras_snapshot_p2),
  .ras_restore_snapshot (ras_restore_snapshot),
  .ras_commit_val       (ras_commit_val),
  .ras_commit_br_type   (ras_commit_br_type),
  .ras_commit_snapshot  (ras_commit_snapshot),
  .bos                  (bos),
  .spec_ret_addr        (spec_ret_addr),
  .spec_rctr            (spec_rctr),
  .spec_nos             (spec_nos),
  .spec_bot             (spec_bot),
  .commit_ret_addr      (commit_ret_addr),
  .csp                  (csp),
  .c_cnt                (c_cnt)
);
