// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FTQ fast-path entry array (BP-107).
//
// Owns bp_ftq_entry_t x FTQ_DEPTH, ftq_entry_formats.md 1 and 2.
// 316 bits per entry at two slots (241 at one), 64 entries, 20,224 bits
// ($bits(bp_ftq_entry_t), measured by BP-152). BP-152 adds 12 bits, the
// RAS snapshot's depth and tag (RAS-4): 304 and 19,456 before. Until
// BP-152 this read 232 bits and 14,848, which was not $bits of the
// entry (BP-142 had added the recursion count, 4 bits, TD#194, to a
// 228 that was not either). It is the storage
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
//   p2  block-scalar correction (ftq_bpu_interfaces.md 4c). ras and
//       pft_addr of the named entry, for EVERY valid p2 block,
//       whether or not the FTB answered. ras becomes the post-op
//       snapshot (ras_decisions.md 4.2) and pft_addr the cluster's
//       corrected fall-through, TD#113 (BP-118).
//   p2  slot correction. The slot array only. NOT gated on a
//       redirect (FE-13) -- it carries the FTB classification and
//       the in-block positions into the entry on every prediction,
//       and without it a conditional the uBTB missed and the FTB
//       found not-taken would keep br_type NO_BRANCH for its whole
//       life and train nothing.
//   p3  slot correction. Same shape, SC direction applied.
//   pd  predecode correction. ONE slot, from the IFU writeback. The
//       third correction, later than both and superseding both for
//       the slot it names. Since BP-152 (C1) with it pft_addr for a
//       predecode-found jump and the RAS snapshot after a predecode
//       call or return.
//   rsv placement (BP-119). ONE slot per resolution channel: a
//       resolved branch the entry did not hold, placed by ftq_resolve,
//       or since BP-121 the resolved branch the entry did hold,
//       replacing its predicted slot. Architectural and the latest
//       event for the slot, so it lands last. A slot written taken
//       or mispredicted clears the slots after it by position (the
//       executed block ends there; BP-152, TD#211 b).
//   bkr  the backend redirect clear (BP-152, TD#211 a). A backend
//       redirect with _self clear clears the slots after its position.
//       Lands after everything.
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
// READ PORTS. Six, and ftq_decisions.md 1 counts three. The three it
// does not count are all named elsewhere in the same document set:
//
//   xlate    every cycle, at xlate_ptr, the block start pc ONLY. The
//            translation request of ftq_ifu_interfaces.md 4.1 carries
//            bp_ftq_entry_t.pc and nothing else from the entry, so the
//            port is VA_WIDTH wide rather than a whole entry. Added by
//            BP-112 (TD#127).
//   fetch    every cycle, at fetch_ptr. Section 1. It writes through
//            the p3 slot correction of the same cycle (BP-150, at the
//            reads below).
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

  // ---- p2 block-scalar correction write (ftq_bpu_interfaces.md 4c) -
  // blk_wr_val is the shadow-qualified bpu_blk_val_p2, so a write for
  // a squashed or reallocated index never arrives (4.6, 5.6).
  input  logic                      blk_wr_val,
  input  logic [FTQ_IDX_BITS-1:0]   blk_wr_idx,
  input  bp_ras_snapshot_t          blk_wr_ras,
  input  logic [VA_WIDTH-1:0]       blk_wr_pft_addr,

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
  // BP-152, C1. With the predecode slot: the block's new end, the
  // corrected jump's pc plus its length, into pft_addr (pd_wr_idx). And
  // the RAS snapshot after the restore's own operations (the undo of the
  // block's off-path push, the C1 call or return), into the ras field of
  // the entry the restore named, pd_ras_wr_idx: the predecode entry, or
  // the entry of a backend redirect with _self clear.
  input  logic                      pd_wr_pft_val,
  input  logic [VA_WIDTH-1:0]       pd_wr_pft,
  input  logic                      pd_ras_wr_val,
  input  logic [FTQ_IDX_BITS-1:0]   pd_ras_wr_idx,
  input  bp_ras_snapshot_t          pd_ras_wr,

  // ---- the backend redirect clear (BP-152, TD#211 a) ---------------
  // A backend redirect with _self clear names an entry that survives,
  // and the path leaves it at bkr_clr_pos: every slot after that
  // position is off the path and is cleared, as a resolved end clears
  // (ftq_decisions.md 5.4). A trap or a replay at a non-branch has no
  // resolution to do it.
  input  logic                      bkr_clr_val,
  input  logic [FTQ_IDX_BITS-1:0]   bkr_clr_idx,
  input  logic [FTB_BR_POS_BITS-1:0] bkr_clr_pos,

  // ---- placement write, one slot per resolution channel (BP-119) --
  input  logic [NUM_RESOLVE_PORTS-1:0] rsv_wr_val,
  input  logic [FTQ_IDX_BITS-1:0]   rsv_wr_idx  [0:NUM_RESOLVE_PORTS-1],
  input  logic [TRX_SLOT_BITS-1:0]  rsv_wr_sel  [0:NUM_RESOLVE_PORTS-1],
  input  bp_ftq_slot_t              rsv_wr_slot [0:NUM_RESOLVE_PORTS-1],
  // The resolved fall-through of a taken jump, pc + 2 or + 4 (BP-121,
  // TD#164). Written into pft_addr with a slot that resolved a taken
  // jump: the block ended there, so its end is the jump's end, which
  // the RAS commit pushes and the FTB update records.
  input  logic [VA_WIDTH-1:0]       rsv_wr_pft  [0:NUM_RESOLVE_PORTS-1],
  // The written slot ends the executed block: clear every slot whose
  // position is after it (BP-152, TD#211 b: by position, not by slot
  // index).
  input  logic [NUM_RESOLVE_PORTS-1:0] rsv_wr_end,

  // ---- reads -------------------------------------------------------
  input  logic [FTQ_IDX_BITS-1:0]   xlate_rd_idx,
  output logic [VA_WIDTH-1:0]       xlate_rd_pc,

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
  // THE FETCH PORT WRITES THROUGH THE p3 SLOT CORRECTION (BP-150,
  // TD#205). The fetch request for an entry is first presented in the
  // entry's p3 cycle: its translation is presented no earlier than p2,
  // once the p1 write has landed (the written frontier, 5.1), and the
  // fetch waits for a translation presented in an earlier cycle. The p3
  // slot write lands at the end of that cycle, so a request accepted in
  // it would carry the p2 slots. When p3 redirects, the flush discards
  // that request (ftq_ifu_interfaces.md 5). But bp_cluster redirects only
  // when the block SUCCESSOR changes, and SC can move the taken position
  // without changing it: a conditional whose taken target is the
  // block's fall-through, or a later slot taken to the same target. The
  // IFU truncates the block on taken_val and taken_pos, so the request
  // carrying the p2 view dropped the instructions between the branch and
  // the fall-through (SC to not taken) or delivered the ones after a
  // branch now taken. The port returns the slots p3 is writing, so the
  // request presented in the p3 cycle is the corrected one, as 7 W3
  // requires of a fetch of a corrected entry. Only the slot array: p3
  // writes nothing else. The p2 writes need no such path: p2 precedes
  // the first cycle a request for the entry can be presented. The pd
  // and rsv writes, which land after p3, are for an entry already
  // fetched, so they never name the fetch index in its p3 cycle.
  always_comb begin : reads
    xlate_rd_pc      = r_arr[xlate_rd_idx].pc;
    fetch_rd_entry   = r_arr[fetch_rd_idx];
    if (p3_wr_val && (p3_wr_idx == fetch_rd_idx)) begin
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        fetch_rd_entry.slot[s] = p3_wr_slot[s];
      end
    end
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
  // A RAS operation is a taken CALL, RETURN or RETURN_CALL (the JALR
  // that pops then pushes; the RAS applies both at commit, IC-RAS-10).
  // Every other type touches no stack, so ras_commit_val stays low and
  // the step frees the entry without a commit. Before BP-119 (TD#152)
  // 3'b111 was not qualified and committed nothing.
  //
  // ras_commit_ret_addr IS DRIVEN FROM pft_addr. ras_decisions.md 8
  // names the source: ret_addr is call_pc + 2 or + 4, and "the FTB
  // fallThroughAddr field provides this value". The RAS consumes it
  // and does NOT compute PC+2 or PC+4 itself.
  //
  // Until BP-118 the entry held the p1 view for its whole life, which
  // on a uBTB miss is the lookup PC plus FTB_BLOCK_BYTES, so a block
  // ended by a call earlier in it pushed an address past the call
  // (BP-107, TD#113). The 4c write now replaces pft_addr at p2 with
  // the cluster's corrected fall-through -- the FTB fall-through when
  // the FTB answered, else the p1 value carried forward -- so the
  // commit reads the corrected value. Since BP-152 (C1) a predecode
  // correction to a taken jump rewrites pft_addr with the jump's own
  // end (pd_wr_pft), as a resolved taken jump does (rsv_wr_pft).
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
           (commit_rd_entry.slot[s].br_type == RETURN)        ||
           (commit_rd_entry.slot[s].br_type == RETURN_CALL))) begin
        ras_commit_br_type = commit_rd_entry.slot[s].br_type;
        ras_commit_val     = commit_step_val;
      end
    end
  end

  // -----------------------------------------------------------------
  // THE CLEARS BY POSITION (BP-152, TD#211). ftq_decisions.md 5.4: the
  // walk commits only what executed, so every slot after the point the
  // path leaves the entry is cleared.
  //   (b) A resolved end (taken or mispredicted) clears every slot whose
  //       pos is after the resolved branch's pos, whatever its slot
  //       index. Before BP-152 it cleared the slots above rsv_wr_sel.
  //       ftq_resolve places a younger resolution of an entry on the
  //       view of the older's placement, and BP-139 may suppress the
  //       older's write, so the younger's slot can sit above a slot
  //       holding a later position: a predecode-placed call below it
  //       survived and was committed (BP-151, compress_1 idx 15).
  //   (a) A backend redirect with _self clear clears every slot whose
  //       pos is after the redirect's pos. Before BP-152 nothing did
  //       for a trap or replay at a non-branch (BP-151, web_11 idx 7: a
  //       predecode slot at pos 10, a trap at pos 0).
  // Each is judged on the slot as this cycle's earlier writes leave it
  // (the p2, p3 and predecode slot writes and every resolution's slot
  // write), so a slot another channel writes this cycle at an earlier
  // position is kept.
  // -----------------------------------------------------------------
  logic [NUM_PRED_SLOTS-1:0] w_rsv_clr [0:NUM_RESOLVE_PORTS-1];
  logic [NUM_PRED_SLOTS-1:0] w_bkr_clr;

  function automatic bp_ftq_slot_t f_eff(
      input logic [FTQ_IDX_BITS-1:0] idx, input int s);
    bp_ftq_slot_t r;
    r = r_arr[idx].slot[s];
    if (p2_wr_val && (p2_wr_idx == idx)) r = p2_wr_slot[s];
    if (p3_wr_val && (p3_wr_idx == idx)) r = p3_wr_slot[s];
    if (pd_wr_val && (pd_wr_idx == idx)) begin
      if (TRX_SLOT_BITS'(s) == pd_wr_sel) begin
        r = pd_wr_slot;
      end else if (pd_wr_kill && (TRX_SLOT_BITS'(s) > pd_wr_sel)) begin
        r.slot_valid = 1'b0;
        r.taken      = 1'b0;
      end
    end
    for (int q = 0; q < NUM_RESOLVE_PORTS; q++) begin
      if (rsv_wr_val[q] && (rsv_wr_idx[q] == idx) &&
          (rsv_wr_sel[q] == TRX_SLOT_BITS'(s)))
        r = rsv_wr_slot[q];
    end
    return r;
  endfunction

  always_comb begin : clears
    bp_ftq_slot_t e;
    for (int p = 0; p < NUM_RESOLVE_PORTS; p++) begin
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        e = f_eff(rsv_wr_idx[p], s);
        w_rsv_clr[p][s] = rsv_wr_val[p] && rsv_wr_end[p] &&
                          (TRX_SLOT_BITS'(s) != rsv_wr_sel[p]) &&
                          e.slot_valid && (e.pos > rsv_wr_slot[p].pos);
      end
    end
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      e = f_eff(bkr_clr_idx, s);
      w_bkr_clr[s] = bkr_clr_val && e.slot_valid && (e.pos > bkr_clr_pos);
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
      // p2: the block-scalar fields of the named entry. Before the
      // allocation write in text, so an allocation naming the same
      // index -- the newest event for it -- wins the block fields, as
      // the header orders.
      if (blk_wr_val) begin
        r_arr[blk_wr_idx].ras      <= blk_wr_ras;
        r_arr[blk_wr_idx].pft_addr <= blk_wr_pft_addr;
      end

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

      // pd: one slot, and the kill of every slot above it. BP-152 (C1):
      // the block's end for a predecode-found jump, and the RAS snapshot
      // after the predecode call or return the RAS applied.
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
        if (pd_wr_pft_val) r_arr[pd_wr_idx].pft_addr <= pd_wr_pft;
      end
      if (pd_ras_wr_val) r_arr[pd_ras_wr_idx].ras <= pd_ras_wr;

      // rsv: the resolved slot, last but for the redirect clear (see the
      // header). A slot that resolved TAKEN, or MISPREDICTED (the
      // backend redirects at it and fetch continues in a new entry),
      // ends the executed block, so every slot after it is off the path
      // and is cleared, as the predecode kill does (BP-121): the commit
      // walk then sees only executed branches. By position since BP-152
      // (TD#211 b, THE CLEARS BY POSITION above).
      for (int p = 0; p < NUM_RESOLVE_PORTS; p++) begin
        if (rsv_wr_val[p]) begin
          r_arr[rsv_wr_idx[p]].slot[rsv_wr_sel[p]] <= rsv_wr_slot[p];
          if (rsv_wr_slot[p].taken &&
              (rsv_wr_slot[p].br_type != COND) &&
              (rsv_wr_slot[p].br_type != NO_BRANCH)) begin
            r_arr[rsv_wr_idx[p]].pft_addr <= rsv_wr_pft[p];
          end
        end
      end
      for (int p = 0; p < NUM_RESOLVE_PORTS; p++) begin
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          if (w_rsv_clr[p][s]) begin
            r_arr[rsv_wr_idx[p]].slot[s].slot_valid <= 1'b0;
            r_arr[rsv_wr_idx[p]].slot[s].taken      <= 1'b0;
          end
        end
      end

      // The backend redirect clear (BP-152, TD#211 a), last.
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        if (w_bkr_clr[s]) begin
          r_arr[bkr_clr_idx].slot[s].slot_valid <= 1'b0;
          r_arr[bkr_clr_idx].slot[s].taken      <= 1'b0;
        end
      end
    end
  end

endmodule : ftq_entry
