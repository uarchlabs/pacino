// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ftq_entry (BP-107).
//
// BOUND BY MODULE NAME, never by instance name (TD#109).
//
// WHAT IS PROVABLE FROM A PORT LIST. The array itself is not
// visible here and must not be: a property that reached into
// r_arr would be a hierarchical reference, which is the defect
// TD#109 records. What IS visible is the SELF-DESCRIBING part of
// every entry -- branch_id is written from the index the entry was
// allocated at, so a read port returning a valid entry whose
// branch_id disagrees with the index it was read at is an array
// indexing fault, a wrong allocation write, or a read port wired to
// the wrong index. E1 to E4 are that one invariant on the four
// index-driven read ports.
//
// The RAS commit payload is checkable outright: E5 and E6 state the
// two rules 5.4 and FE-11 give it.
//
// WRITES ARE CHECKED THROUGH THE READ PORTS (BP-116, TD#144). The
// array is still not reached into. A registered copy of the last
// predecode write is kept ARMED until a later p1, p2 or p3 write
// names the same index, and in every cycle it is armed it is
// compared with any read port addressing that index: the write
// inputs of an earlier cycle against the stored state, which no
// single RTL line drives both of. E8 and E9 are that form. E10
// compares the pc-only xlate port with the whole-entry ports in the
// same cycle.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_entry_assert (
  input logic                     clk,
  input logic                     rstn,
  input logic [FTQ_IDX_BITS-1:0]  fetch_rd_idx,
  input bp_ftq_entry_t            fetch_rd_entry,
  input logic [FTQ_IDX_BITS-1:0]  redir_rd_idx,
  input bp_ftq_entry_t            redir_rd_entry,
  input logic [FTQ_IDX_BITS-1:0]  pdwb_rd_idx,
  input bp_ftq_entry_t            pdwb_rd_entry,
  input logic [FTQ_IDX_BITS-1:0]  commit_rd_idx,
  input bp_ftq_entry_t            commit_rd_entry,
  input logic                     commit_step_val,
  input logic                     ras_commit_val,
  input bp_br_type_e              ras_commit_br_type,
  input bp_ras_snapshot_t         ras_commit_snapshot,
  input logic                     alloc_wr_val,
  input logic [FTQ_IDX_BITS-1:0]  alloc_wr_idx,
  input logic                     p2_wr_val,
  input logic [FTQ_IDX_BITS-1:0]  p2_wr_idx,
  input logic                     p3_wr_val,
  input logic [FTQ_IDX_BITS-1:0]  p3_wr_idx,
  input logic                     pd_wr_val,
  input logic [FTQ_IDX_BITS-1:0]  pd_wr_idx,
  input logic [TRX_SLOT_BITS-1:0] pd_wr_sel,
  input bp_ftq_slot_t             pd_wr_slot,
  input logic                     pd_wr_kill,
  input logic [NUM_RESOLVE_PORTS-1:0] rsv_wr_val,
  input logic [FTQ_IDX_BITS-1:0]  rsv_wr_idx [0:NUM_RESOLVE_PORTS-1],
  input logic [FTQ_IDX_BITS-1:0]  xlate_rd_idx,
  input logic [VA_WIDTH-1:0]      xlate_rd_pc
);

  // The four whole-entry read ports, as one array so E8 to E10 are
  // one loop each rather than four copies.
  localparam int NUM_EPORTS = 4;

  logic [FTQ_IDX_BITS-1:0] w_port_idx [0:NUM_EPORTS-1];
  bp_ftq_entry_t           w_port_ent [0:NUM_EPORTS-1];

  // The last predecode write, armed until a later p1, p2 or p3
  // write to its index replaces the slots. A p1/p2/p3 write in the
  // SAME cycle as the pd write does not disarm it: the pd write is
  // last in ftq_entry's write block and lands over them.
  logic                     w_pd_overwritten;
  // The placement write (BP-119) also replaces a slot of the entry.
  logic                     w_rsv_same;
  logic                     w_rsv_over;
  logic                     r_pd_val;
  logic                     r_pd_kill;
  logic [FTQ_IDX_BITS-1:0]  r_pd_idx;
  logic [TRX_SLOT_BITS-1:0] r_pd_sel;
  bp_ftq_slot_t             r_pd_slot;

  always_ff @(posedge clk or negedge rstn) begin : pd_hist
    if (!rstn) begin
      r_pd_val  <= 1'b0;
      r_pd_kill <= 1'b0;
      r_pd_idx  <= '0;
      r_pd_sel  <= '0;
      r_pd_slot <= '0;
    end else if (pd_wr_val) begin
      // A placement write to the same entry in the same cycle lands
      // after it (ftq_entry, BP-119), so the predecode slot is not
      // what the entry then holds: do not arm.
      r_pd_val  <= !w_rsv_same;
      r_pd_kill <= pd_wr_kill;
      r_pd_idx  <= pd_wr_idx;
      r_pd_sel  <= pd_wr_sel;
      r_pd_slot <= pd_wr_slot;
    end else if (w_pd_overwritten) begin
      r_pd_val  <= 1'b0;
    end
  end

  always_comb begin : pd_disarm
    w_rsv_same = 1'b0;
    w_rsv_over = 1'b0;
    for (int p = 0; p < NUM_RESOLVE_PORTS; p++) begin
      w_rsv_same = w_rsv_same | (rsv_wr_val[p] && (rsv_wr_idx[p] == pd_wr_idx));
      w_rsv_over = w_rsv_over | (rsv_wr_val[p] && (rsv_wr_idx[p] == r_pd_idx));
    end
    w_pd_overwritten = (alloc_wr_val && (alloc_wr_idx == r_pd_idx)) ||
                       (p2_wr_val    && (p2_wr_idx    == r_pd_idx)) ||
                       (p3_wr_val    && (p3_wr_idx    == r_pd_idx)) ||
                       w_rsv_over;
  end

  logic w_e8_bad;
  logic w_e9_bad;
  logic w_e10_bad;

  always_comb begin : port_checks
    w_port_idx[0] = fetch_rd_idx;
    w_port_ent[0] = fetch_rd_entry;
    w_port_idx[1] = redir_rd_idx;
    w_port_ent[1] = redir_rd_entry;
    w_port_idx[2] = pdwb_rd_idx;
    w_port_ent[2] = pdwb_rd_entry;
    w_port_idx[3] = commit_rd_idx;
    w_port_ent[3] = commit_rd_entry;

    w_e8_bad  = 1'b0;
    w_e9_bad  = 1'b0;
    w_e10_bad = 1'b0;
    for (int p = 0; p < NUM_EPORTS; p++) begin
      if (r_pd_val && (w_port_idx[p] == r_pd_idx)) begin
        if (w_port_ent[p].slot[r_pd_sel] != r_pd_slot) begin
          w_e9_bad = 1'b1;
        end
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          if (r_pd_kill && (TRX_SLOT_BITS'(s) > r_pd_sel) &&
              (w_port_ent[p].slot[s].slot_valid ||
               w_port_ent[p].slot[s].taken)) begin
            w_e8_bad = 1'b1;
          end
        end
      end
      if ((w_port_idx[p] == xlate_rd_idx) &&
          (w_port_ent[p].pc != xlate_rd_pc)) begin
        w_e10_bad = 1'b1;
      end
    end
  end

  // E1  The fetch read port returns the entry it addressed. This is
  //     the every-cycle read of section 1 and the one a wrong index
  //     would corrupt silently: the IFU would fetch the right PC for
  //     the wrong entry and the writeback would come back naming an
  //     index the FTQ did not request.
  property p_fetch_self;
    @(posedge clk) disable iff (!rstn)
      fetch_rd_entry.valid |-> (fetch_rd_entry.branch_id ==
                                fetch_rd_idx);
  endproperty

  // E2  The redirect read port. It supplies the checkpoint and the
  //     RAS snapshot to restore (3.2), so a wrong entry here
  //     restores the front end to a state that belongs to another
  //     block.
  property p_redir_self;
    @(posedge clk) disable iff (!rstn)
      redir_rd_entry.valid |-> (redir_rd_entry.branch_id ==
                                redir_rd_idx);
  endproperty

  // E3  The predecode writeback read port.
  property p_pdwb_self;
    @(posedge clk) disable iff (!rstn)
      pdwb_rd_entry.valid |-> (pdwb_rd_entry.branch_id ==
                               pdwb_rd_idx);
  endproperty

  // E4  The commit read port. The payload it forms frees the entry,
  //     so a wrong entry here issues a RAS commit for a block that
  //     did not retire.
  property p_commit_self;
    @(posedge clk) disable iff (!rstn)
      commit_rd_entry.valid |-> (commit_rd_entry.branch_id ==
                                 commit_rd_idx);
  endproperty

  // E5  No RAS commit without a commit step. 5.4 makes commit and
  //     free ONE pointer, so a commit issued outside a step would
  //     advance the RAS against an entry the FTQ is not freeing.
  //     It also carries the suppression: commit_step_val is low in
  //     any cycle a redirect restore fires (ras_decisions.md 4.5
  //     orders BOS restore > commit > hold), so this property is
  //     what makes the suppression reach the RAS port.
  property p_ras_needs_step;
    @(posedge clk) disable iff (!rstn)
      ras_commit_val |-> commit_step_val;
  endproperty

  // E6  A RAS commit is a call, a return or a return-call (TD#152,
  //     BP-119) and nothing else. FE-11
  //     bounds it to one operation per entry; this bounds it to the
  //     operations that exist. A commit carrying COND or NO_BRANCH
  //     would push or pop the stack for a branch that touches it.
  property p_ras_type;
    @(posedge clk) disable iff (!rstn)
      ras_commit_val |-> (ras_commit_br_type == DIRECT_CALL)   ||
                         (ras_commit_br_type == INDIRECT_CALL) ||
                         (ras_commit_br_type == RETURN)        ||
                         (ras_commit_br_type == RETURN_CALL);
  endproperty

  // E7  The payload comes from the entry being freed. Stated on the
  //     snapshot because that is the field 5.4 names as the reason
  //     commit and free cannot be two pointers.
  property p_ras_snapshot_src;
    @(posedge clk) disable iff (!rstn)
      ras_commit_val |-> (ras_commit_snapshot == commit_rd_entry.ras);
  endproperty

  // E8  A predecode slot write with the kill CLEARS the slots above
  //     it. The branch predecode found at mis_pos is taken, so
  //     everything after it in the block is off the path
  //     (ftq_ifu_interfaces.md 7 W1). A write that left a later slot
  //     valid would leave the entry describing a branch the block
  //     never reaches, and the successor re-derivation of W3 would
  //     then pick that slot's target.
  //     RESTATED BY BP-116 (TD#144). It read pd_wr_val |-> pd_wr_kill,
  //     which is a tie-off in the unit (ftq_ifu drives the kill 1)
  //     and testbench stimulus here. It now states the kill's EFFECT
  //     on the stored entry, read back while the write is armed:
  //     slot_valid and taken are clear on every slot above
  //     pd_wr_sel. The pd write is last in ftq_entry's write block,
  //     so a same-cycle p2 or p3 write to the index cannot override
  //     it and needs no exclusion.
  property p_write_kills_above;
    @(posedge clk) disable iff (!rstn)
      !w_e8_bad;
  endproperty

  // E9  The predecode slot write LANDS (BP-116, TD#144; the entry
  //     half of ftq_ifu I5). After pd_wr_val, and until a later
  //     write replaces the slots, a read port addressing pd_wr_idx
  //     returns pd_wr_slot in slot pd_wr_sel.
  //     Same precedence argument as E8. The redirect half of I5 is
  //     ftq_npc N5.
  property p_pd_write_lands;
    @(posedge clk) disable iff (!rstn)
      !w_e9_bad;
  endproperty

  // E10 The xlate read port returns the pc of the entry it addressed
  //     (BP-116, TD#144; replaces ftq_ifu I14). It carries no
  //     branch_id, so E1 to E4's self-description does not apply;
  //     instead any whole-entry port addressing the same index in the
  //     same cycle must return the same pc. A wrong pc here translates
  //     the wrong page and the fetch of the entry later misses.
  property p_xlate_pc_agrees;
    @(posedge clk) disable iff (!rstn)
      !w_e10_bad;
  endproperty

  a_fetch_self:        assert property (p_fetch_self)
    else $error("E1 fetch read returned a foreign entry");
  a_redir_self:        assert property (p_redir_self)
    else $error("E2 redirect read returned a foreign entry");
  a_pdwb_self:         assert property (p_pdwb_self)
    else $error("E3 writeback read returned a foreign entry");
  a_commit_self:       assert property (p_commit_self)
    else $error("E4 commit read returned a foreign entry");
  a_ras_needs_step:    assert property (p_ras_needs_step)
    else $error("E5 a RAS commit issued outside a commit step");
  a_ras_type:          assert property (p_ras_type)
    else $error("E6 a RAS commit for a type with no stack op");
  a_ras_snapshot_src:  assert property (p_ras_snapshot_src)
    else $error("E7 the RAS payload is not the freed entry's");
  a_write_kills_above: assert property (p_write_kills_above)
    else $error("E8 a predecode slot write did not kill above it");
  a_pd_write_lands:    assert property (p_pd_write_lands)
    else $error("E9 the predecode slot write did not land");
  a_xlate_pc_agrees:   assert property (p_xlate_pc_agrees)
    else $error("E10 the xlate read port returned a foreign pc");

endmodule : ftq_entry_assert

// Bind BY MODULE NAME.
bind ftq_entry ftq_entry_assert u_assert (
  .clk                 (clk),
  .rstn                (rstn),
  .fetch_rd_idx        (fetch_rd_idx),
  .fetch_rd_entry      (fetch_rd_entry),
  .redir_rd_idx        (redir_rd_idx),
  .redir_rd_entry      (redir_rd_entry),
  .pdwb_rd_idx         (pdwb_rd_idx),
  .pdwb_rd_entry       (pdwb_rd_entry),
  .commit_rd_idx       (commit_rd_idx),
  .commit_rd_entry     (commit_rd_entry),
  .commit_step_val     (commit_step_val),
  .ras_commit_val      (ras_commit_val),
  .ras_commit_br_type  (ras_commit_br_type),
  .ras_commit_snapshot (ras_commit_snapshot),
  .alloc_wr_val        (alloc_wr_val),
  .alloc_wr_idx        (alloc_wr_idx),
  .p2_wr_val           (p2_wr_val),
  .p2_wr_idx           (p2_wr_idx),
  .p3_wr_val           (p3_wr_val),
  .p3_wr_idx           (p3_wr_idx),
  .pd_wr_val           (pd_wr_val),
  .pd_wr_idx           (pd_wr_idx),
  .pd_wr_sel           (pd_wr_sel),
  .pd_wr_slot          (pd_wr_slot),
  .pd_wr_kill          (pd_wr_kill),
  .rsv_wr_val          (rsv_wr_val),
  .rsv_wr_idx          (rsv_wr_idx),
  .xlate_rd_idx        (xlate_rd_idx),
  .xlate_rd_pc         (xlate_rd_pc)
);
