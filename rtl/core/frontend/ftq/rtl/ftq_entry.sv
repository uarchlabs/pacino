// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FTQ fast-path entry array (BP-107).
//
// Owns bp_ftq_entry_t x FTQ_DEPTH, ftq_entry_formats.md 1 and 2.
// 224 bits per entry, 64 entries, 14,336 bits. It is the storage
// class read EVERY CYCLE, which is why it is its own module and not
// merged with ftq_status (ftq_decisions.md 7.4).
//
// WRITES, in the order a slot is corrected (ftq_ifu_interfaces.md 7,
// FE-3, FE-13):
//
//   p1  allocation. The WHOLE entry, from the cluster p1 group.
//       Unconditional: an entry is allocated for every prediction
//       block, including one the p1 predictors miss, so a later
//       stage has an entry to correct (5.2).
//   p2  slot correction. The slot array only. NOT gated on a
//       redirect (FE-13) -- it carries the FTB classification and
//       the in-block positions into the entry on every prediction,
//       and without it a conditional the uBTB missed and the FTB
//       found not-taken would keep br_type NO_BRANCH for its whole
//       life and train nothing.
//   p3  slot correction. Same shape, SC direction applied.
//   pd  predecode correction. ONE slot, from the IFU writeback. The
//       third correction, later than both and superseding both for
//       the slot it names.
//
// SAME-INDEX ORDER, resolved here because the array is this
// module's state: pd > p3 > p2 > allocation on the SLOT array, and
// allocation always writes the block-scalar fields. FE-3 gives
// p3 > p2; ftq_ifu_interfaces.md 7 puts predecode after both.
// Allocation naming the same index as a correction in the same
// cycle means the correction is for a stale use of that index; the
// shadow of 5.6 and the generation of 6.1 drop those before they
// reach here, so the case is an input error and allocation --
// the newest event for the index -- wins the block fields.
//
// READ PORTS. Five, and ftq_decisions.md 1 counts three. The two it
// does not count are both named elsewhere in the same document set:
//
//   fetch    every cycle, at fetch_ptr. Section 1.
//   redir    on redirect, for the checkpoint and the RAS snapshot
//            to restore, and to re-derive the block successor.
//            Section 1, 3.2.
//   rsv      at resolution, for pc and the slot's br_type and pos.
//            Section 1, fe_decisions.md 7.2. TWO of them:
//            ftq_backend_interfaces.md 4 fixes resolution at two
//            per cycle and the two channels may name DIFFERENT
//            entries, so one port cannot serve both.
//   commit   at commit_ptr, for the bp_ras_snapshot_t the commit
//            payload carries. Section 5.4 requires it; section 1
//            does not count it.
//   pdwb     at the writeback index, to form the predecode slot
//            correction and re-derive the successor from the
//            corrected entry (ftq_ifu_interfaces.md 7 W1, W3).
//
// Section 6.1 cites "the two-read-port decision of section 1".
// Section 1 makes no such decision and the read count it does give
// is three. Reported in the BP-107 Results Capture.
//
// The array is modelled with combinational reads. This is a
// BEHAVIOURAL model of an SRAM, not a synthesis directive: the
// physical form -- banking, read port count, registered outputs --
// is a physical-design choice this project cannot make without
// timing data (bp_cluster.md, Timing Methodology Gap).
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_entry (
  input  logic                      clk,
  input  logic                      rstn,

  // ---- p1 allocation write ----------------------------------------
  // THE ENTRY IS ASSEMBLED HERE, from the p1 group and the two
  // sources outside it, rather than arriving pre-built. ftq.sv is
  // purely structural (7.1) and building a struct out of eight
  // fields is not wiring, so it belongs in the module that owns the
  // array.
  //
  // Two of the fields do not come from the p1 group at all:
  //
  //   pc          the block start, which no p1 port carries. It is
  //               the ftq_pred_pc_p0 the FTQ issued a cycle earlier
  //               and arrives from ftq_npc as pred_pc_p1.
  //   ghist/phist the checkpoint, read out of bp_history on
  //               ckpt_ghist_ptr / ckpt_phist_ptr
  //               (ftq_bpu_interfaces.md 9). Written from the same
  //               p1 allocation as bp_history's own checkpoint
  //               array, which is what makes the two one to one
  //               against an index (ftq_decisions.md 3.2).
  //
  // branch_id is the entry's own index and valid is set: allocation
  // is unconditional (5.2), so an entry exists for every prediction
  // block including one the p1 predictors miss.
  input  logic                      alloc_wr_val,
  input  logic [FTQ_IDX_BITS-1:0]   alloc_wr_idx,
  input  logic [VA_WIDTH-1:0]       alloc_wr_pc,
  input  logic [VA_WIDTH-1:0]       alloc_wr_pft_addr,
  input  bp_ras_snapshot_t          alloc_wr_ras,
  input  logic [GHIST_PTR_BITS-1:0] alloc_wr_ghist_ptr,
  input  logic [PHIST_PTR_BITS-1:0] alloc_wr_phist_ptr,
  input  bp_ftq_slot_t              alloc_wr_slot [0:NUM_PRED_SLOTS-1],

  // ---- p2 slot correction write (ftq_bpu_interfaces.md 4a) --------
  input  logic                      p2_wr_val,
  input  logic [FTQ_IDX_BITS-1:0]   p2_wr_idx,
  input  bp_ftq_slot_t              p2_wr_slot [0:NUM_PRED_SLOTS-1],

  // ---- p3 slot correction write -----------------------------------
  input  logic                      p3_wr_val,
  input  logic [FTQ_IDX_BITS-1:0]   p3_wr_idx,
  input  bp_ftq_slot_t              p3_wr_slot [0:NUM_PRED_SLOTS-1],

  // ---- predecode correction write, one slot -----------------------
  // pd_wr_sel names the slot; pd_wr_kill clears every slot ABOVE it.
  // A predecode-found taken branch ends the block, so everything
  // after it is off the path (ftq_ifu_interfaces.md 7 W1).
  input  logic                      pd_wr_val,
  input  logic [FTQ_IDX_BITS-1:0]   pd_wr_idx,
  input  logic [TRX_SLOT_BITS-1:0]  pd_wr_sel,
  input  bp_ftq_slot_t              pd_wr_slot,
  input  logic                      pd_wr_kill,

  // ---- reads -------------------------------------------------------
  input  logic [FTQ_IDX_BITS-1:0]   fetch_rd_idx,
  output bp_ftq_entry_t             fetch_rd_entry,

  input  logic [FTQ_IDX_BITS-1:0]   redir_rd_idx,
  output bp_ftq_entry_t             redir_rd_entry,
  // D2 of ftq_backend_interfaces.md 5: the RAS snapshot of the
  // entry being corrected, straight onto ras_restore_snapshot.
  // Published as its own port so ftq.sv wires name to name.
  output bp_ras_snapshot_t          restore_snapshot,

  input  logic [FTQ_IDX_BITS-1:0]   pdwb_rd_idx,
  output bp_ftq_entry_t             pdwb_rd_entry,

  input  logic [FTQ_IDX_BITS-1:0]   commit_rd_idx,
  output bp_ftq_entry_t             commit_rd_entry,

  // ---- the RAS commit payload, ftq_decisions.md 5.4 ---------------
  // FORMED HERE, and ftq_commit.sv says why: FE-11 guarantees at
  // most one RAS operation per entry but does not say every entry
  // has one, and the has-a-RAS-operation fact lives in the entry.
  // ftq_commit issues the step; this module qualifies it and
  // supplies the payload.
  //
  // commit_step_val already carries the SUPPRESSION of 5.4: it is
  // low in any cycle a redirect restore fires, because
  // ras_decisions.md 4.5 orders BOS restore > commit > hold.
  input  logic                      commit_step_val,
  output logic                      ras_commit_val,
  output bp_br_type_e               ras_commit_br_type,
  output logic [VA_WIDTH-1:0]       ras_commit_ret_addr,
  output bp_ras_snapshot_t          ras_commit_snapshot,

  input  logic [FTQ_IDX_BITS-1:0]   rsv_rd_idx [0:NUM_RESOLVE_PORTS-1],
  output bp_ftq_entry_t             rsv_rd_entry [0:NUM_RESOLVE_PORTS-1]
);

  bp_ftq_entry_t r_arr [FTQ_DEPTH-1:0];
  bp_ftq_entry_t w_alloc_entry;

  // -----------------------------------------------------------------
  // Reads. Combinational, see the header.
  // -----------------------------------------------------------------
  always_comb begin : reads
    fetch_rd_entry   = r_arr[fetch_rd_idx];
    redir_rd_entry   = r_arr[redir_rd_idx];
    pdwb_rd_entry    = r_arr[pdwb_rd_idx];
    commit_rd_entry  = r_arr[commit_rd_idx];
    restore_snapshot = r_arr[redir_rd_idx].ras;
    for (int p = 0; p < NUM_RESOLVE_PORTS; p++) begin
      rsv_rd_entry[p] = r_arr[rsv_rd_idx[p]];
    end
  end

  // -----------------------------------------------------------------
  // The p1 entry, assembled. See the alloc_wr_* port comment.
  // -----------------------------------------------------------------
  always_comb begin : assemble
    w_alloc_entry            = '0;
    w_alloc_entry.pc         = alloc_wr_pc;
    w_alloc_entry.pft_addr   = alloc_wr_pft_addr;
    w_alloc_entry.branch_id  = alloc_wr_idx;
    w_alloc_entry.ras        = alloc_wr_ras;
    w_alloc_entry.ghist_ptr  = alloc_wr_ghist_ptr;
    w_alloc_entry.phist_ptr  = alloc_wr_phist_ptr;
    w_alloc_entry.valid      = 1'b1;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      w_alloc_entry.slot[s] = alloc_wr_slot[s];
    end
  end

  // -----------------------------------------------------------------
  // The RAS commit payload, ftq_decisions.md 5.4.
  // -----------------------------------------------------------------
  // FE-11: at most one RAS operation per block, because a RAS
  // operation is a TAKEN branch and a taken branch ends the block,
  // so an operation in slot 0 means slot 1 is off the path. One
  // snapshot per entry is therefore sufficient and one payload per
  // commit step is all the scalar ras_commit_* group can carry.
  //
  // A RAS operation is a taken CALL or RETURN. Every other resolved
  // type touches no stack, so ras_commit_val stays low and the step
  // frees the entry without a commit.
  //
  // ras_commit_ret_addr IS DRIVEN FROM pft_addr, AND THE ENTRY HOLDS
  // THE WRONG pft_addr. This is a KNOWN DEFECT, not a derivation
  // awaiting confirmation, and it cannot be fixed inside this unit.
  //
  // ras_decisions.md 8 names the source outright: ret_addr is
  // call_pc + 2 or + 4, and "the FTB fallThroughAddr field provides
  // this value". The RAS consumes it and explicitly does NOT compute
  // PC+2 or PC+4 itself, so the FTQ's job is to forward the right
  // field rather than to derive one.
  //
  // THE FTQ DOES NOT HAVE THAT FIELD. bp_ftq_entry_t.pft_addr is
  // written once, at p1, from bpu_pred_pft_p1, and
  // ftq_bpu_interfaces.md 4 says of it: "It is not the FTB pftAddr
  // of section 5.1, which arrives at p2." The FTB's own
  // ftb_pft_addr_p2 is consumed INSIDE the cluster and no port
  // carries it out; the p2 and p3 slot correction groups carry
  // bp_ftq_slot_t only, and pft_addr is a block scalar. So the entry
  // keeps the p1 view for its whole life.
  //
  // WHEN THE TWO DIFFER:
  //
  //   uBTB hit    they agree by construction -- blk_p1.pft_addr is
  //               the uBTB entry's fall-through and the uBTB entry
  //               mirrors the FTB entry.
  //   uBTB miss   they do NOT. The p1 value is the block-aligned PC
  //               plus FTB_BLOCK_BYTES, the FULL block end, so a
  //               block terminated by a call earlier in the block
  //               pushes an address past the call. Allocation is
  //               unconditional (5.2), so this entry exists and can
  //               commit.
  //   p2 fixed it the FTB found a branch the uBTB missed -- the
  //               FE-13 case -- and corrected the block end. The
  //               entry still holds the p1 value.
  //
  // A wrong ret_addr costs prediction accuracy on the matching
  // return, not correctness: the RAS is a predictor and the return
  // resolves against the real target. That is why this is reported
  // rather than worked around.
  //
  // pft_addr is driven anyway because it is the ONLY candidate the
  // entry offers -- pc, the slot targets and the slot positions
  // cannot reconstruct it, since nothing records whether the call
  // was RVC or RVI. THE FIX IS A PLANNING CHANGE, outside this
  // task: either the p2 group gains the FTB fall-through and the
  // entry gains a field for it, or the entry gains a ret_addr field
  // written at p2. Reported in the BP-107 Results Capture.
  always_comb begin : ras_commit_payload
    ras_commit_snapshot = commit_rd_entry.ras;
    ras_commit_ret_addr = commit_rd_entry.pft_addr;
    ras_commit_br_type  = NO_BRANCH;
    ras_commit_val      = 1'b0;

    for (int s = NUM_PRED_SLOTS - 1; s >= 0; s--) begin
      if (commit_rd_entry.slot[s].slot_valid &&
          commit_rd_entry.slot[s].taken &&
          ((commit_rd_entry.slot[s].br_type == DIRECT_CALL)   ||
           (commit_rd_entry.slot[s].br_type == INDIRECT_CALL) ||
           (commit_rd_entry.slot[s].br_type == RETURN))) begin
        ras_commit_br_type = commit_rd_entry.slot[s].br_type;
        ras_commit_val     = commit_step_val;
      end
    end
  end

  // -----------------------------------------------------------------
  // Writes.
  // -----------------------------------------------------------------
  // Written as one clocked block in priority order rather than as
  // four guarded blocks, so the same-index order of the header is
  // the textual order of the statements and cannot drift from it.
  //
  // Reset clears only the entry VALID bits. The payload is don't-
  // care until allocation writes it, and clearing 14,336 bits of
  // array at reset would model a structure no SRAM provides.
  always_ff @(posedge clk or negedge rstn) begin : writes
    if (!rstn) begin
      for (int e = 0; e < FTQ_DEPTH; e++) begin
        r_arr[e].valid <= 1'b0;
      end
    end else begin
      // p1: the whole entry, block-scalar fields included.
      if (alloc_wr_val) begin
        r_arr[alloc_wr_idx] <= w_alloc_entry;
      end

      // p2: the slot array of the named entry.
      if (p2_wr_val) begin
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          r_arr[p2_wr_idx].slot[s] <= p2_wr_slot[s];
        end
      end

      // p3: same, and later, so it lands over p2 for a shared index.
      if (p3_wr_val) begin
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          r_arr[p3_wr_idx].slot[s] <= p3_wr_slot[s];
        end
      end

      // pd: one slot, and the kill of every slot above it.
      if (pd_wr_val) begin
        r_arr[pd_wr_idx].slot[pd_wr_sel] <= pd_wr_slot;
        if (pd_wr_kill) begin
          for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
            if (TRX_SLOT_BITS'(s) > pd_wr_sel) begin
              r_arr[pd_wr_idx].slot[s].slot_valid <= 1'b0;
              r_arr[pd_wr_idx].slot[s].taken      <= 1'b0;
            end
          end
        end
      end
    end
  end

endmodule : ftq_entry
