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
  input logic                     pd_wr_val,
  input logic                     pd_wr_kill
);

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

  // E6  A RAS commit is a call or a return and nothing else. FE-11
  //     bounds it to one operation per entry; this bounds it to the
  //     operations that exist. A commit carrying COND or NO_BRANCH
  //     would push or pop the stack for a branch that touches it.
  property p_ras_type;
    @(posedge clk) disable iff (!rstn)
      ras_commit_val |-> (ras_commit_br_type == DIRECT_CALL)   ||
                         (ras_commit_br_type == INDIRECT_CALL) ||
                         (ras_commit_br_type == RETURN);
  endproperty

  // E7  The payload comes from the entry being freed. Stated on the
  //     snapshot because that is the field 5.4 names as the reason
  //     commit and free cannot be two pointers.
  property p_ras_snapshot_src;
    @(posedge clk) disable iff (!rstn)
      ras_commit_val |-> (ras_commit_snapshot == commit_rd_entry.ras);
  endproperty

  // E8  A predecode slot write ALWAYS kills the slots above it. The
  //     branch predecode found at mis_pos is taken, so everything
  //     after it in the block is off the path
  //     (ftq_ifu_interfaces.md 7 W1). A write that left a later slot
  //     valid would leave the entry describing a branch the block
  //     never reaches, and the successor re-derivation of W3 would
  //     then pick that slot's target.
  property p_write_kills_above;
    @(posedge clk) disable iff (!rstn)
      pd_wr_val |-> pd_wr_kill;
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
  .pd_wr_val           (pd_wr_val),
  .pd_wr_kill          (pd_wr_kill)
);
