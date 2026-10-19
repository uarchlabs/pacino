// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    ftb_cntrl.sv
// DATE:    2026-06-25
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// FTB control logic (BP-066).
//
// ftb_cntrl is the ONLY logic in the FTB. It drives two storage peers:
//   - ftb_array : pure 1R1W DATA RAM (FTB_RAM_ENTRY_WIDTH per way,
//                 ftb_decisions.md 8)
//   - ftb_plru  : per-set entry-valid bits + tree-PLRU state (flops)
// It instantiates neither; the FTB top (BP-067) wires array_* to
// ftb_array and plru_* to ftb_plru. The two storage-facing port groups
// carry DISTINCT prefixes (array_* / plru_*) because both storage
// modules expose rd_en_n / rd_addr (ftb_interfaces.md 3 / 3a,
// IC-FTB-12/13).
//
// Behaviors owned here (ftb_decisions.md 1, 2.4, 3, 4, 4.2, 4.5, 5,
// 8, 8.1; ftb_confidence_override_rules.md):
//   - prediction read + way-match (ftb_plru valid AND ftb_array tag)
//   - branch-type classification (call/ret/jalr)
//   - ONE ENTRY PER START PC (BP-140, ruled by Jeff 2026-10-18; it
//     replaces the region-shared entry of 4.6). The tag carries the
//     start's halfword offset VA[4:1] above the region tag VA[39:14],
//     and the index folds the offset into its top bits (ftb_idx,
//     ftb_tag; PROVISIONAL). Positions, targets and pftAddr are stored
//     start-relative, so the region window, the region offset k and
//     the read compaction of 4.6 R-1, R-2, O-3b are gone (PROVISIONAL)
//   - storage in ascending position: br0 below br1, the jump last
//     (O-3a, kept)
//   - THE SPLIT AT UPDATE (BP-140, ruled by Jeff): an entry never holds
//     more than NUM_PRED_SLOTS branches. When an update would make it
//     hold more, the lowest positions are kept and the block end
//     becomes the PC of the lowest-position branch not kept; a jump not
//     kept clears the jump field. See the update decode below
//   - target encode/reconstruct: every target is a displacement from
//     its own instruction: a conditional target from the BRANCH PC
//     (4.6 O-1), a jump target from the JUMP PC (4.2, TD#137); both
//     PCs are the start plus the field's stored position
//   - fallthrough reduce/reconstruct: pftAddr from the block start, no
//     carry (5.5), bounds checked by FTB-G1 and FTB-G3 with the FTB-G2
//     fallback (4.5, 4.6 O-2)
//   - carried-writeWay allocate/evict with tree-PLRU
//   - update field writes (target / conf / pft)
//   - confidence training and saturated-endpoint fast-path
//
// RAM entry layout (ftb_entry_t below, private to ftb_cntrl): the
// ftb_decisions.md 8 entry in section 8 order minus the relocated
// entry-valid, FTB_RAM_ENTRY_WIDTH bits. Widths, from section 8, the
// sole home of the field widths and their sum:
//   - entry (logical, FTB_ENTRY_WIDTH):       114 bits per way,
//     including the entry-valid held in ftb_plru
//   - RAM entry (FTB_RAM_ENTRY_WIDTH):        113 bits per way, the
//     entry minus the entry-valid; what ftb_array stores
// BP-140 left both widths unchanged: the tag grew by FTB_BR_POS_BITS
// (4) and the three positions and pftAddr each lost one bit.
// The elaboration check below holds $bits(ftb_entry_t) to the second.
//   tag
//   br0{valid,pos,tgt,stat,conf}
//   br1{valid,pos,tgt,stat,conf}
//   jmp{valid,pos,tgt,stat,isCall,isRet,isJalr}
//   pftAddr
// The entry-valid bit is NOT in this layout; it lives in ftb_plru.
//
// Read-port arbitration (assumption, documented in Results Capture):
// ftb_array/ftb_plru each expose ONE read port. Prediction uses it in
// p1. The update path needs the carried way's current entry to
// read-modify-write conf / target / pft, and the set's
// current PLRU to mark-used -- so an active update BORROWS both read
// ports (addressed by the carried set, NOT a tag re-lookup: IC-FTB-10).
// Update borrows have priority; a prediction in the same cycle is
// dropped (its p2 outputs read invalid). This is tolerated -- FTB is
// already a bubble-costing s2 structure and update-channel scheduling
// is an FTQ concern (IC-FTB-09, deferred). Because update owns the read
// ports when active, the two PLRU-touch events (prediction-hit vs
// update/allocate) are mutually exclusive on the single PLRU write
// port, so the funnel "update/allocate wins" falls out for free
// (ftb_decisions.md 5.3).
//
// Pipeline: p0 request registered to p1; p1 reads + computes; results
// registered to p2 (s0 send, s1 registered, s2 valid). The p1 compute
// references the registered valid_p1 so the way-match block is
// nba_sequent, not stl_sequent (CLAUDE.md Verilator note).
//
// Flush is a stub (IC-FTB-07): ftb_flush_px clears the combinational
// prediction outputs while asserted; no flush state machine, and the
// ftb_plru valid-clear path is not driven.
// ===================================================================
`ifndef FTB_CNTRL_SV
`define FTB_CNTRL_SV

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftb_cntrl (
  input  logic                          clk,
  input  logic                          rstn,

  // ================================================================
  // FTB top functional ports (ftb_interfaces.md 2)
  // ================================================================
  // -- prediction request (2.2; s0 in, registered s1)
  input  logic                          pred_valid_p0,
  input  logic [VA_WIDTH-1:0]           pred_pc_p0,

  // -- prediction outputs (2.3; at s2)
  output logic                          ftb_valid_p2,
  output logic                          ftb_hit_p2,
  output logic [FTB_WAY_BITS-1:0]       ftb_way_p2,

  output logic                          ftb_br0_valid_p2,
  output logic [FTB_BR_POS_BITS-1:0]    ftb_br0_pos_p2,
  output logic                          ftb_br0_taken_p2,
  output logic [FTB_CONF_WIDTH-1:0]     ftb_br0_conf_p2,
  output logic [VA_WIDTH-1:0]           ftb_br0_target_p2,

  output logic                          ftb_br1_valid_p2,
  output logic [FTB_BR_POS_BITS-1:0]    ftb_br1_pos_p2,
  output logic                          ftb_br1_taken_p2,
  output logic [FTB_CONF_WIDTH-1:0]     ftb_br1_conf_p2,
  output logic [VA_WIDTH-1:0]           ftb_br1_target_p2,

  output logic                          ftb_jmp_valid_p2,
  output logic [FTB_BR_POS_BITS-1:0]    ftb_jmp_pos_p2,
  output logic [VA_WIDTH-1:0]           ftb_jmp_target_p2,
  output logic                          ftb_is_call_p2,
  output logic                          ftb_is_ret_p2,
  output logic                          ftb_is_jalr_p2,
  // The jump is a 16-bit instruction (BP-121, TD#164).
  output logic                          ftb_jmp_rvc_p2,

  output logic [VA_WIDTH-1:0]           ftb_pft_addr_p2,

  // -- confidence fast-path (2.4); bit0 br0, bit1 br1
  output logic [1:0]                    ftb_fastpath_p2,

  // -- global fast-path enable (confidence section 5; 1 enables the
  //    bypass, inverse-sense of a classic chicken bit, source TBD)
  input  logic                          ftb_fastpath_en,

  // -- update port (2.5; post-execute, single port)
  input  logic                          ftb_upd_valid_u0,
  input  logic [VA_WIDTH-1:0]           ftb_upd_pc_u0,
  input  logic                          ftb_upd_hit_u0,
  input  logic [FTB_WAY_BITS-1:0]       ftb_upd_way_u0,
  input  logic                          ftb_upd_is_br_u0,
  input  logic                          ftb_upd_br_idx_u0,
  input  logic                          ftb_upd_taken_u0,
  input  logic [VA_WIDTH-1:0]           ftb_upd_target_u0,
  input  logic [FTB_BR_POS_BITS-1:0]    ftb_upd_pos_u0,
  input  logic                          ftb_upd_is_jmp_u0,
  input  logic [VA_WIDTH-1:0]           ftb_upd_jmp_target_u0,
  input  logic                          ftb_upd_is_call_u0,
  input  logic                          ftb_upd_is_ret_u0,
  input  logic                          ftb_upd_is_jalr_u0,
  input  logic                          ftb_upd_jmp_rvc_u0,
  input  logic [VA_WIDTH-1:0]           ftb_upd_pft_addr_u0,

  // -- flush (2.6; stub, IC-FTB-07)
  input  logic                          ftb_flush_px,

  // ================================================================
  // ftb_array-facing ports (ftb_interfaces.md 3); active-low enables
  // ================================================================
  output logic                          array_rd_en_n,
  output logic [FTB_IDX_BITS-1:0]       array_rd_addr,
  input  logic [FTB_RAM_SET_WIDTH-1:0]  array_rd_data,
  output logic                          array_wr_en_n,
  output logic [FTB_IDX_BITS-1:0]       array_wr_addr,
  output logic [FTB_WAYS-1:0]           array_wr_way,
  output logic [FTB_RAM_ENTRY_WIDTH-1:0] array_wr_data,

  // ================================================================
  // ftb_plru-facing ports (ftb_interfaces.md 3a); active-low enables
  // ================================================================
  output logic                          plru_rd_en_n,
  output logic [FTB_IDX_BITS-1:0]       plru_rd_addr,
  input  logic [FTB_WAYS-1:0]           plru_rd_valid,
  input  logic [PLRU_BITS-1:0]          plru_rd_plru,
  output logic                          plru_val_we_n,
  output logic [FTB_IDX_BITS-1:0]       plru_val_addr,
  output logic [FTB_WAYS-1:0]           plru_val_way,
  output logic                          plru_val_set,
  output logic                          plru_plru_we_n,
  output logic [FTB_IDX_BITS-1:0]       plru_plru_addr,
  output logic [PLRU_BITS-1:0]          plru_plru_wdata
);

  // ----------------------------------------------------------------
  // Private RAM entry layout (FTB_RAM_ENTRY_WIDTH bits/way,
  // ftb_decisions.md 8). Packed in declaration order: first member is
  // the MSB. The exact within-way bit order is private to ftb_cntrl;
  // the only external contract with ftb_array is the way slice
  // [w*FTB_RAM_ENTRY_WIDTH +: FTB_RAM_ENTRY_WIDTH].
  //
  // pos is the start-relative position, 0..15 (BP-140; it was the
  // region position, 4.6 R-1). br0 always holds the lower position of
  // the two conditional fields and the jump is after both (4.6 O-3a):
  // a jump ends the block, so no branch of the block follows it.
  // ----------------------------------------------------------------
  typedef struct packed {
    logic                          valid;        // field valid
    logic [FTB_BR_POS_BITS-1:0]    pos;          // start position
    logic [FTB_BR_TGT_BITS-1:0]    tgt;          // target displacement
    logic [TAR_STAT_BITS-1:0]      stat;         // fit/ovf/udf
    logic [FTB_CONF_WIDTH-1:0]     conf;         // bimodal direction
  } ftb_cond_t;

  typedef struct packed {
    logic                          valid;        // field valid
    logic [FTB_BR_POS_BITS-1:0]    pos;          // start position
    logic [FTB_JMP_TGT_BITS-1:0]   tgt;          // jump displacement
    logic [TAR_STAT_BITS-1:0]      stat;         // fit/ovf/udf
    logic                          is_call;
    logic                          is_ret;
    logic                          is_jalr;
    // The jump is 16 bits: its fall-through is the jump PC + 2, else
    // + 4 (BP-121, TD#164, ruled by Jeff; ftb_decisions.md 8).
    logic                          is_rvc;
  } ftb_jmp_t;

  typedef struct packed {
    logic [FTB_TAG_BITS-1:0]       tag;
    ftb_cond_t                     br0;
    ftb_cond_t                     br1;
    ftb_jmp_t                      jmp;
    logic [PFTADDR_BITS-1:0]       pft;          // end from the start
  } ftb_entry_t;

  // ----------------------------------------------------------------
  // Local constants
  // ----------------------------------------------------------------
  // FTB-G3 bound (ftb_decisions.md 4.6 O-2): the furthest legal block
  // end is one prediction block plus one straddling halfword position
  // above the start.
  localparam logic [VA_WIDTH-1:0] PFT_MAX_SPAN =
    VA_WIDTH'(FTB_BLOCK_BYTES) + (VA_WIDTH'(1) << POS_OFFSET_BITS);

  // The end of a block that holds no jump and was never split: one
  // prediction block above the start, in positions (the FTB-G2 value,
  // and the cluster's p1 end on a uBTB miss). BP-140.
  localparam logic [PFTADDR_BITS-1:0] PFT_NAT =
    PFTADDR_BITS'(FTB_BLOCK_BYTES >> POS_OFFSET_BITS);       // = 16

  // Conditional candidates the split orders: the two stored fields and
  // the resolving branch.
  localparam int N_CAND = 3;

  // ----------------------------------------------------------------
  // Functions (combinational helpers). Declared before first use.
  // ----------------------------------------------------------------

  // Reconstruct a full-VA conditional target from the stored
  // displacement and its base, the branch PC (4.6 O-1). Sign-extend
  // the displacement. A target has no bounds check; the fall-through
  // does (4.5).
  function automatic logic [VA_WIDTH-1:0] recon_br(
      input logic [FTB_BR_TGT_BITS-1:0] disp,
      input logic [VA_WIDTH-1:0]        base);
    recon_br = base
      + {{(VA_WIDTH-FTB_BR_TGT_BITS){disp[FTB_BR_TGT_BITS-1]}}, disp};
  endfunction

  // Reconstruct a full-VA jump target from the stored displacement
  // and its base, the jump PC (4.2, TD#137). Sign-extend the
  // displacement.
  function automatic logic [VA_WIDTH-1:0] recon_jmp(
      input logic [FTB_JMP_TGT_BITS-1:0] disp,
      input logic [VA_WIDTH-1:0]         base);
    recon_jmp = base
      + {{(VA_WIDTH-FTB_JMP_TGT_BITS){disp[FTB_JMP_TGT_BITS-1]}}, disp};
  endfunction

  // Encode a full-VA conditional target to the stored displacement
  // (low FTB_BR_TGT_BITS of target-base). Lossless when the branch is
  // in reach; status (br_stat) records fit/overflow/underflow.
  function automatic logic [FTB_BR_TGT_BITS-1:0] enc_br_disp(
      input logic [VA_WIDTH-1:0] tgt, input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0] d;
    d = tgt - base;
    enc_br_disp = d[FTB_BR_TGT_BITS-1:0];
  endfunction

  function automatic logic [FTB_JMP_TGT_BITS-1:0] enc_jmp_disp(
      input logic [VA_WIDTH-1:0] tgt, input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0] d;
    d = tgt - base;
    enc_jmp_disp = d[FTB_JMP_TGT_BITS-1:0];
  endfunction

  // Target status: 00 fit, 01 overflow (too far forward), 10 underflow
  // (too far backward). fit when the sign-extended displacement
  // reconstructs the target exactly.
  function automatic logic [TAR_STAT_BITS-1:0] br_stat(
      input logic [VA_WIDTH-1:0] tgt, input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0] d;
    d = tgt - base;
    if (recon_br(d[FTB_BR_TGT_BITS-1:0], base) == tgt) br_stat = 2'b00;
    else if (d[VA_WIDTH-1])                            br_stat = 2'b10;
    else                                               br_stat = 2'b01;
  endfunction

  function automatic logic [TAR_STAT_BITS-1:0] jmp_stat(
      input logic [VA_WIDTH-1:0] tgt, input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0] d;
    d = tgt - base;
    if (recon_jmp(d[FTB_JMP_TGT_BITS-1:0], base) == tgt) jmp_stat = 2'b00;
    else if (d[VA_WIDTH-1])                              jmp_stat = 2'b10;
    else                                                 jmp_stat = 2'b01;
  endfunction

  // The start's halfword offset in its 32-byte region, VA[4:1].
  function automatic logic [FTB_BR_POS_BITS-1:0] start_off(
      input logic [VA_WIDTH-1:0] pc);
    start_off = pc[FTB_OFFSET_BITS-1:POS_OFFSET_BITS];
  endfunction

  // Entry identity (BP-140, PROVISIONAL; bp_defines_pkg FTB_TAG_BITS,
  // FTB_SOFF_SHIFT). Index: the region index VA[13:5] with the start
  // offset XORed into its top bits, so the starts of one region index
  // different sets. Tag: the region tag VA[39:14] and the start offset,
  // so (index, tag) is unique for every VA[39:1].
  function automatic logic [FTB_IDX_BITS-1:0] ftb_idx(
      input logic [VA_WIDTH-1:0] pc);
    ftb_idx = pc[FTB_OFFSET_BITS +: FTB_IDX_BITS]
            ^ (FTB_IDX_BITS'(start_off(pc)) << FTB_SOFF_SHIFT);
  endfunction

  function automatic logic [FTB_TAG_BITS-1:0] ftb_tag(
      input logic [VA_WIDTH-1:0] pc);
    ftb_tag = {pc[FTB_OFFSET_BITS+FTB_IDX_BITS +: FTB_RTAG_BITS],
               start_off(pc)};
  endfunction

  // Instruction PC from the block start and a stored position: the
  // branch PC of a conditional field (4.6 O-1) and the jump PC of the
  // jump field (4.2, TD#137).
  function automatic logic [VA_WIDTH-1:0] branch_pc(
      input logic [VA_WIDTH-1:0]        start,
      input logic [FTB_BR_POS_BITS-1:0] pos);
    branch_pc = start + (VA_WIDTH'(pos) << POS_OFFSET_BITS);
  endfunction

  // The end the read reports, in positions from the start: pftAddr,
  // or PFT_NAT when pftAddr fails FTB-G1 (at the start) or FTB-G3
  // (beyond start + FTB_BLOCK_BYTES + one halfword), the FTB-G2
  // fallback. The update's past-the-end test uses the same end.
  function automatic logic [PFTADDR_BITS-1:0] eff_end(
      input logic [PFTADDR_BITS-1:0] pft);
    eff_end = ((pft == '0) || (pft > PFT_NAT + PFTADDR_BITS'(1)))
            ? PFT_NAT : pft;
  endfunction

  // Sort key of a conditional candidate: an empty field sorts after
  // every filled one, filled fields by ascending position.
  function automatic logic [FTB_BR_POS_BITS:0] cand_key(
      input ftb_cond_t c);
    cand_key = {~c.valid, c.pos};
  endfunction

  // Saturating bimodal step (3-bit, 0..7). up = resolved taken ->
  // increment toward 111; down -> decrement toward 000.
  function automatic logic [FTB_CONF_WIDTH-1:0] conf_step(
      input logic [FTB_CONF_WIDTH-1:0] cur, input logic up);
    if (up) conf_step = (cur == {FTB_CONF_WIDTH{1'b1}})
                          ? cur : cur + 1'b1;
    else    conf_step = (cur == '0) ? cur : cur - 1'b1;
  endfunction

  // 4-way tree-PLRU (PLRU_BITS = 3). Bit assignment:
  //   st[0] = root  : 0 -> victim in {way0,way1}, 1 -> {way2,way3}
  //   st[1] = left  : 0 -> way0, 1 -> way1
  //   st[2] = right : 0 -> way2, 1 -> way3
  // Each node points toward the victim subtree/leaf.
  function automatic logic [FTB_WAY_BITS-1:0] plru_victim(
      input logic [PLRU_BITS-1:0] st);
    if (st[0] == 1'b0) plru_victim = st[1] ? 2'd1 : 2'd0;
    else               plru_victim = st[2] ? 2'd3 : 2'd2;
  endfunction

  // Mark a way used: steer every node on the path AWAY from that way.
  function automatic logic [PLRU_BITS-1:0] plru_touch(
      input logic [PLRU_BITS-1:0]     st,
      input logic [FTB_WAY_BITS-1:0]  way);
    logic [PLRU_BITS-1:0] nx;
    nx = st;
    if (way[1] == 1'b0) begin
      nx[0] = 1'b1;        // root points right, away from {0,1}
      nx[1] = ~way[0];     // left node points to the other of {0,1}
    end else begin
      nx[0] = 1'b0;        // root points left, away from {2,3}
      nx[2] = ~way[0];     // right node points to the other of {2,3}
    end
    plru_touch = nx;
  endfunction

  // ----------------------------------------------------------------
  // p0 -> p1 request pipeline registers
  // ----------------------------------------------------------------
  logic [VA_WIDTH-1:0] pc_p1;
  logic                valid_p1;

  always_ff @(posedge clk) begin
    if (!rstn) begin
      pc_p1    <= '0;
      valid_p1 <= 1'b0;
    end else begin
      pc_p1    <= pred_pc_p0;
      valid_p1 <= pred_valid_p0;
    end
  end

  // ----------------------------------------------------------------
  // Update-side combinational decode (u0). Produces the write-back
  // entry, the update set index/tag, and the readback of the carried
  // way (for read-modify-write of conf / target / pft on a hit). No tag
  // re-lookup (IC-FTB-10).
  // ----------------------------------------------------------------
  logic [FTB_IDX_BITS-1:0]    upd_set_idx;
  logic [FTB_TAG_BITS-1:0]    upd_tag;
  logic [VA_WIDTH-1:0]        upd_off;
  logic [FTB_BR_POS_BITS-1:0] upd_pos;
  ftb_entry_t                 upd_old;
  ftb_entry_t                 upd_cur;
  ftb_entry_t                 upd_new;
  ftb_cond_t                  fld_old;
  ftb_cond_t                  fld_new;
  ftb_cond_t                  fld_tmp;
  ftb_jmp_t                   jmp_new;
  // The conditional candidates in ascending position (cand[0] lowest),
  // empty ones last, and the jump candidate.
  ftb_cond_t                  cand [N_CAND];
  ftb_jmp_t                   jcand;
  logic                       upd_m0;
  logic                       upd_m1;
  logic                       upd_mj;
  logic                       upd_past;
  logic                       upd_isb;
  logic                       upd_isj;
  logic                       inplace;
  logic [$clog2(N_CAND+2)-1:0] n_cand;
  // The update makes the entry hold more than NUM_PRED_SLOTS branches:
  // the split (BP-140), and the position of the first branch not kept.
  logic                       upd_split;
  logic [FTB_BR_POS_BITS-1:0] upd_cut_pos;
  logic                       upd_active;
  // The carried way as it is NOW (BP-121, TD#163, ruled by Jeff): valid
  // with the update's tag. The update reads that way anyway for its
  // read-modify-write; checking its tag is not an associative re-lookup
  // (IC-FTB-10). It replaces the predict-time hit: a carried miss whose
  // way another update has since allocated with this tag merges into
  // it instead of re-allocating over it (which discarded its other
  // fields), and a carried hit whose way was since evicted and reused
  // by another start allocates instead of writing this start's fields
  // under the other start's tag.
  logic                       upd_hit;

  assign upd_active = ftb_upd_valid_u0;

  // THE UPDATE (BP-140; ftb_decisions.md 5.5 field mapping, ruled by
  // Jeff 2026-10-18). The entry is the block from one start, so every
  // field it holds is a branch of that block, in position order.
  //   1. THE SAME BRANCH IS THE SAME POSITION (5.5, TD#156). A
  //      conditional at a stored conditional's position updates it in
  //      place (conf step, target rewritten). A jump at the stored
  //      jump's position rewrites the jump field. A resolution of the
  //      other kind at a stored position replaces that field (the
  //      stored classification was wrong).
  //   2. PAST THE END. A resolution at or after the end the read
  //      reports (eff_end), or after the stored jump, is not in this
  //      block as the entry now
  //      describes it (it came from a block predicted before the entry
  //      was shortened) and changes nothing.
  //   3. A NEW BRANCH joins the held ones. A new jump also removes every
  //      conditional after it: a jump ends the block.
  //   4. THE SPLIT. If the entry would then hold more than
  //      NUM_PRED_SLOTS branches, the lowest NUM_PRED_SLOTS positions
  //      are kept, and the block end becomes the PC of the lowest
  //      position not kept. A jump not kept clears the jump field.
  //   5. THE END otherwise: a written jump's own end (the update's
  //      pftAddr, the resolved fall-through of the taken jump, TD#164);
  //      else the stored end, or on an allocation one prediction block
  //      above the start (PFT_NAT). The update's pftAddr for a
  //      conditional is the PREDICTED end of the block it resolved in
  //      and is not written: an end only moves down, to a branch or a
  //      jump the entry has seen, so the result does not depend on the
  //      order in which the branches of a block resolve (PROVISIONAL).
  // The end positions of 2 and 4 make every held branch lie below the
  // end, and every branch resolved from this start and not held lie at
  // or above it (ftb_assert.sv FA1).
  always_comb begin
    fld_tmp     = '0;
    upd_set_idx = ftb_idx(ftb_upd_pc_u0);
    upd_tag     = ftb_tag(ftb_upd_pc_u0);
    upd_pos     = ftb_upd_pos_u0;
    upd_off     = ftb_upd_pft_addr_u0 - ftb_upd_pc_u0;

    // Readback of the carried way (read-old-on-collision in ftb_array
    // gives the pre-write contents for the RMW).
    upd_old = ftb_entry_t'(
      array_rd_data[ftb_upd_way_u0*FTB_RAM_ENTRY_WIDTH
                      +: FTB_RAM_ENTRY_WIDTH]);

    // The carried way's current state decides hit or allocate (TD#163).
    upd_hit = plru_rd_valid[ftb_upd_way_u0] & (upd_old.tag == upd_tag);

    // Base entry: the old entry on a hit (preserve untouched fields), or
    // a fresh empty entry ending one block above the start (5.4).
    if (upd_hit) begin
      upd_cur = upd_old;
    end else begin
      upd_cur     = '0;
      upd_cur.pft = PFT_NAT;
    end
    upd_cur.tag = upd_tag;

    // 1 and 2.
    upd_m0   = upd_cur.br0.valid & (upd_cur.br0.pos == upd_pos);
    upd_m1   = upd_cur.br1.valid & (upd_cur.br1.pos == upd_pos);
    upd_mj   = upd_cur.jmp.valid & (upd_cur.jmp.pos == upd_pos);
    upd_past = (PFTADDR_BITS'(upd_pos) >= eff_end(upd_cur.pft))
             | (upd_cur.jmp.valid & (upd_cur.jmp.pos < upd_pos));
    upd_isb  = ftb_upd_is_br_u0 & ~upd_past;
    upd_isj  = ftb_upd_is_jmp_u0 & ~ftb_upd_is_br_u0 & ~upd_past;
    inplace  = upd_m0 | upd_m1;

    // The conditional field the update writes. The same branch trains
    // the bimodal conf toward the resolved outcome; a new branch takes
    // the weak init in the observed direction (TKN -> 100, NTK -> 011)
    // (5.4, conf section 3.2 / 7). The target base is the branch PC
    // (4.6 O-1).
    fld_old       = upd_m0 ? upd_cur.br0 : upd_cur.br1;
    fld_new.valid = 1'b1;
    fld_new.pos   = upd_pos;
    fld_new.tgt   = enc_br_disp(ftb_upd_target_u0,
                                branch_pc(ftb_upd_pc_u0, upd_pos));
    fld_new.stat  = br_stat(ftb_upd_target_u0,
                            branch_pc(ftb_upd_pc_u0, upd_pos));
    fld_new.conf  = inplace
                  ? conf_step(fld_old.conf, ftb_upd_taken_u0)
                  : (ftb_upd_taken_u0 ? FTB_CONF_INIT_TKN
                                      : FTB_CONF_INIT_NTK);

    // The jump field the update writes, whole (5.5, IC-FTB-01): a
    // resolve of the stored jump writes the position it holds; the
    // target base is the jump PC (4.2, TD#137).
    jmp_new.valid   = 1'b1;
    jmp_new.pos     = upd_pos;
    jmp_new.tgt     = enc_jmp_disp(ftb_upd_jmp_target_u0,
                                   branch_pc(ftb_upd_pc_u0, upd_pos));
    jmp_new.stat    = jmp_stat(ftb_upd_jmp_target_u0,
                               branch_pc(ftb_upd_pc_u0, upd_pos));
    jmp_new.is_call = ftb_upd_is_call_u0;
    jmp_new.is_ret  = ftb_upd_is_ret_u0;
    jmp_new.is_jalr = ftb_upd_is_jalr_u0;
    jmp_new.is_rvc  = ftb_upd_jmp_rvc_u0;

    // 1 and 3: the candidates. The stored fields, less the one this
    // resolution replaces, and the resolving branch.
    cand[0] = upd_cur.br0;
    cand[1] = upd_cur.br1;
    cand[2] = '0;
    jcand   = upd_cur.jmp;
    if (upd_isb) begin
      if (upd_m0) cand[0] = '0;
      if (upd_m1) cand[1] = '0;
      cand[2] = fld_new;
      if (upd_mj) jcand = '0;
    end else if (upd_isj) begin
      // A jump ends the block: a conditional at or after it is not in
      // the block. It replaces any stored jump, which is after it (2).
      if (upd_cur.br0.valid && (upd_cur.br0.pos >= upd_pos)) cand[0] = '0;
      if (upd_cur.br1.valid && (upd_cur.br1.pos >= upd_pos)) cand[1] = '0;
      jcand = jmp_new;
    end

    // Ascending position, empty last: a three-element sorting network.
    if (cand_key(cand[1]) < cand_key(cand[0])) begin
      fld_tmp = cand[0]; cand[0] = cand[1]; cand[1] = fld_tmp;
    end
    if (cand_key(cand[2]) < cand_key(cand[1])) begin
      fld_tmp = cand[1]; cand[1] = cand[2]; cand[2] = fld_tmp;
    end
    if (cand_key(cand[1]) < cand_key(cand[0])) begin
      fld_tmp = cand[0]; cand[0] = cand[1]; cand[1] = fld_tmp;
    end

    // 4. The split. The branches in program order are the conditional
    // candidates then the jump. The first not kept is cand[N] when more
    // than NUM_PRED_SLOTS conditionals remain, else the jump.
    n_cand = '0;
    for (int i = 0; i < N_CAND; i++) begin
      if (cand[i].valid) n_cand = n_cand + 1'b1;
    end
    upd_split   = (int'(n_cand) + int'(jcand.valid)) > NUM_PRED_SLOTS;
    upd_cut_pos = (int'(n_cand) > NUM_PRED_SLOTS)
                ? cand[NUM_PRED_SLOTS].pos : jcand.pos;

    upd_new     = upd_cur;
    upd_new.br0 = cand[0];
    upd_new.br1 = (NUM_PRED_SLOTS > 1) ? cand[1] : '0;
    upd_new.jmp = (int'(n_cand) < NUM_PRED_SLOTS) ? jcand : '0;

    // 4 and 5. The end.
    if (upd_split)
      upd_new.pft = PFTADDR_BITS'(upd_cut_pos);
    else if (upd_isj)
      upd_new.pft = upd_off[POS_OFFSET_BITS +: PFTADDR_BITS];
    else
      upd_new.pft = upd_cur.pft;
  end

  // ----------------------------------------------------------------
  // Shared read-port arbitration. Update borrows both read ports when
  // active (priority); otherwise prediction (p1) owns them.
  // ----------------------------------------------------------------
  logic [FTB_IDX_BITS-1:0]    pred_set_idx_p1;
  logic [FTB_TAG_BITS-1:0]    pred_tag_p1;

  // The lookup PC's set and tag (ftb_idx, ftb_tag, BP-140).
  assign pred_set_idx_p1 = ftb_idx(pc_p1);
  assign pred_tag_p1     = ftb_tag(pc_p1);

  assign array_rd_en_n = ~(upd_active | valid_p1);
  assign array_rd_addr = upd_active ? upd_set_idx : pred_set_idx_p1;
  assign plru_rd_en_n  = ~(upd_active | valid_p1);
  assign plru_rd_addr  = upd_active ? upd_set_idx : pred_set_idx_p1;

  // ----------------------------------------------------------------
  // Prediction compute (p1). way-match over FTB_WAYS, victim select,
  // entry reconstruct. Gated on valid_p1 (a flop) so the block is
  // nba_sequent. pred_grant_p1 is 0 when an update has borrowed the
  // read ports -> the prediction self-bubbles.
  // ----------------------------------------------------------------
  ftb_entry_t              way_entry [FTB_WAYS];
  logic [FTB_WAYS-1:0]     hit_vec;
  logic [FTB_WAY_BITS-1:0] hit_way;
  logic [FTB_WAY_BITS-1:0] victim;
  logic [FTB_WAY_BITS-1:0] sel_way;
  ftb_entry_t              sel_entry;
  logic                    hit_any;
  logic                    pred_grant_p1;
  logic [VA_WIDTH-1:0]     pft_full;

  // p1 -> p2 next values
  logic                      n_valid_p2;
  logic                      n_hit_p2;
  logic [FTB_WAY_BITS-1:0]   n_way_p2;
  logic                      n_br0_valid, n_br0_taken;
  logic [FTB_BR_POS_BITS-1:0] n_br0_pos;
  logic [FTB_CONF_WIDTH-1:0] n_br0_conf;
  logic [VA_WIDTH-1:0]       n_br0_tgt;
  logic                      n_br1_valid, n_br1_taken;
  logic [FTB_BR_POS_BITS-1:0] n_br1_pos;
  logic [FTB_CONF_WIDTH-1:0] n_br1_conf;
  logic [VA_WIDTH-1:0]       n_br1_tgt;
  logic                      n_jmp_valid, n_is_call, n_is_ret, n_is_jalr;
  logic                      n_jmp_rvc;
  logic [FTB_BR_POS_BITS-1:0] n_jmp_pos;
  logic [VA_WIDTH-1:0]       n_jmp_tgt;
  logic [VA_WIDTH-1:0]       n_pft;

  always_comb begin
    hit_vec = '0;
    hit_way = '0;
    for (int unsigned w = 0; w < FTB_WAYS; w++) begin
      way_entry[w] = ftb_entry_t'(
        array_rd_data[w*FTB_RAM_ENTRY_WIDTH +: FTB_RAM_ENTRY_WIDTH]);
      hit_vec[w] = plru_rd_valid[w]
                   && (way_entry[w].tag == pred_tag_p1);
    end
    // Full tag -> at most one way hits (no aliasing below VA bit 40).
    for (int unsigned w = 0; w < FTB_WAYS; w++) begin
      if (hit_vec[w]) hit_way = FTB_WAY_BITS'(w);
    end

    hit_any       = |hit_vec;
    victim        = plru_victim(plru_rd_plru);
    sel_way       = hit_any ? hit_way : victim;
    sel_entry     = way_entry[hit_way];
    pred_grant_p1 = valid_p1 & ~upd_active;

    n_valid_p2 = pred_grant_p1 & hit_any;
    n_hit_p2   = pred_grant_p1 & hit_any;
    n_way_p2   = sel_way;             // hit way, or tree-PLRU victim

    // The entry is this start's block (BP-140), stored start-relative
    // in ascending position, so its fields go to the ports as stored:
    // br0 to port br0, br1 to port br1, the jump to the jump port. The
    // region window, the hiding of a conditional past the jump and the
    // compaction of 4.6 R-1 and O-3b had other starts' fields to remove
    // and are gone. br1 is reported only with br0, the compaction
    // invariant the cluster relies on (IC-FTB-16).
    // FTB direction is the bimodal conf MSB, qualified by field valid
    // (conf section 3.1). Targets reconstruct from the branch PC (4.6
    // O-1) and the jump PC (4.2).
    n_br0_valid = n_valid_p2 & sel_entry.br0.valid;
    n_br0_taken = n_br0_valid & sel_entry.br0.conf[FTB_CONF_WIDTH-1];
    n_br0_pos   = sel_entry.br0.pos;
    n_br0_conf  = sel_entry.br0.conf;
    n_br0_tgt   = recon_br(sel_entry.br0.tgt,
                           branch_pc(pc_p1, sel_entry.br0.pos));

    n_br1_valid = n_br0_valid & sel_entry.br1.valid;
    n_br1_taken = n_br1_valid & sel_entry.br1.conf[FTB_CONF_WIDTH-1];
    n_br1_pos   = sel_entry.br1.pos;
    n_br1_conf  = sel_entry.br1.conf;
    n_br1_tgt   = recon_br(sel_entry.br1.tgt,
                           branch_pc(pc_p1, sel_entry.br1.pos));

    // jump field + branch-type classification (3-way JALR split).
    n_jmp_valid = n_valid_p2 & sel_entry.jmp.valid;
    n_jmp_pos   = sel_entry.jmp.pos;
    n_jmp_tgt   = recon_jmp(sel_entry.jmp.tgt,
                            branch_pc(pc_p1, sel_entry.jmp.pos));
    n_is_call   = n_jmp_valid & sel_entry.jmp.is_call;
    n_is_ret    = n_jmp_valid & sel_entry.jmp.is_ret;
    n_is_jalr   = n_jmp_valid & sel_entry.jmp.is_jalr;
    n_jmp_rvc   = n_jmp_valid & sel_entry.jmp.is_rvc;

    // Fallthrough reconstruct (4.5, 5.5): the start plus pftAddr in
    // positions, no carry (BP-140; it was the aligned region base).
    // Bounds checked against the lookup PC:
    //   FTB-G1  an end at or below the start
    //   FTB-G3  an end beyond start + FTB_BLOCK_BYTES + one halfword
    // both take the FTB-G2 fallback, start + FTB_BLOCK_BYTES (one
    // prediction block, never FETCH_BLOCK_BYTES). The update writes an
    // end in bounds unless a jump's resolved end is out of them.
    pft_full = pc_p1
      + (VA_WIDTH'(sel_entry.pft) << POS_OFFSET_BITS);
    if ((pft_full <= pc_p1) || (pft_full > pc_p1 + PFT_MAX_SPAN))
      n_pft = pc_p1 + VA_WIDTH'(FTB_BLOCK_BYTES);
    else
      n_pft = pft_full;
  end

  // ----------------------------------------------------------------
  // p1 -> p2 output registers
  // ----------------------------------------------------------------
  logic                      q_valid_p2, q_hit_p2;
  logic [FTB_WAY_BITS-1:0]   q_way_p2;
  logic                      q_br0_valid, q_br0_taken;
  logic [FTB_BR_POS_BITS-1:0] q_br0_pos;
  logic [FTB_CONF_WIDTH-1:0] q_br0_conf;
  logic [VA_WIDTH-1:0]       q_br0_tgt;
  logic                      q_br1_valid, q_br1_taken;
  logic [FTB_BR_POS_BITS-1:0] q_br1_pos;
  logic [FTB_CONF_WIDTH-1:0] q_br1_conf;
  logic [VA_WIDTH-1:0]       q_br1_tgt;
  logic                      q_jmp_valid, q_is_call, q_is_ret, q_is_jalr;
  logic                      q_jmp_rvc;
  logic [FTB_BR_POS_BITS-1:0] q_jmp_pos;
  logic [VA_WIDTH-1:0]       q_jmp_tgt;
  logic [VA_WIDTH-1:0]       q_pft;

  always_ff @(posedge clk) begin
    if (!rstn) begin
      q_valid_p2  <= 1'b0;
      q_hit_p2    <= 1'b0;
      q_way_p2    <= '0;
      q_br0_valid <= 1'b0;
      q_br0_taken <= 1'b0;
      q_br0_pos   <= '0;
      q_br0_conf  <= '0;
      q_br0_tgt   <= '0;
      q_br1_valid <= 1'b0;
      q_br1_taken <= 1'b0;
      q_br1_pos   <= '0;
      q_br1_conf  <= '0;
      q_br1_tgt   <= '0;
      q_jmp_valid <= 1'b0;
      q_jmp_pos   <= '0;
      q_jmp_tgt   <= '0;
      q_is_call   <= 1'b0;
      q_is_ret    <= 1'b0;
      q_is_jalr   <= 1'b0;
      q_jmp_rvc   <= 1'b0;
      q_pft       <= '0;
    end else begin
      q_valid_p2  <= n_valid_p2;
      q_hit_p2    <= n_hit_p2;
      q_way_p2    <= n_way_p2;
      q_br0_valid <= n_br0_valid;
      q_br0_taken <= n_br0_taken;
      q_br0_pos   <= n_br0_pos;
      q_br0_conf  <= n_br0_conf;
      q_br0_tgt   <= n_br0_tgt;
      q_br1_valid <= n_br1_valid;
      q_br1_taken <= n_br1_taken;
      q_br1_pos   <= n_br1_pos;
      q_br1_conf  <= n_br1_conf;
      q_br1_tgt   <= n_br1_tgt;
      q_jmp_valid <= n_jmp_valid;
      q_jmp_pos   <= n_jmp_pos;
      q_jmp_tgt   <= n_jmp_tgt;
      q_is_call   <= n_is_call;
      q_is_ret    <= n_is_ret;
      q_is_jalr   <= n_is_jalr;
      q_jmp_rvc   <= n_jmp_rvc;
      q_pft       <= n_pft;
    end
  end

  // ----------------------------------------------------------------
  // p2 output drive. Flush stub (IC-FTB-07): clear the valid-class
  // prediction outputs while ftb_flush_px is asserted. Data outputs
  // (targets, conf, pft) pass through, qualified downstream by the
  // gated valids.
  // ----------------------------------------------------------------
  logic flush_clr;
  assign flush_clr = ~ftb_flush_px;

  assign ftb_valid_p2            = q_valid_p2 & flush_clr;
  assign ftb_hit_p2             = q_hit_p2   & flush_clr;
  assign ftb_way_p2             = q_way_p2;

  assign ftb_br0_valid_p2        = q_br0_valid & flush_clr;
  assign ftb_br0_pos_p2          = q_br0_pos;
  assign ftb_br0_taken_p2        = q_br0_taken & flush_clr;
  assign ftb_br0_conf_p2         = q_br0_conf;
  assign ftb_br0_target_p2       = q_br0_tgt;

  assign ftb_br1_valid_p2        = q_br1_valid & flush_clr;
  assign ftb_br1_pos_p2          = q_br1_pos;
  assign ftb_br1_taken_p2        = q_br1_taken & flush_clr;
  assign ftb_br1_conf_p2         = q_br1_conf;
  assign ftb_br1_target_p2       = q_br1_tgt;

  assign ftb_jmp_valid_p2        = q_jmp_valid & flush_clr;
  assign ftb_jmp_pos_p2          = q_jmp_pos;
  assign ftb_jmp_target_p2       = q_jmp_tgt;
  assign ftb_is_call_p2          = q_is_call & flush_clr;
  assign ftb_is_ret_p2           = q_is_ret  & flush_clr;
  assign ftb_is_jalr_p2          = q_is_jalr & flush_clr;
  assign ftb_jmp_rvc_p2          = q_jmp_rvc & flush_clr;

  assign ftb_pft_addr_p2         = q_pft;

  // Confidence fast-path (confidence section 4, IC-FTB-08). Per branch:
  // valid entry, field present, fast-path enabled, conf saturated (all
  // -ones or all-zeros). Direction only -- never a target override. Not
  // asserted under flush.
  assign ftb_fastpath_p2[0] =
      q_valid_p2 & q_br0_valid & ftb_fastpath_en & flush_clr
    & ((q_br0_conf == '1) | (q_br0_conf == '0));
  assign ftb_fastpath_p2[1] =
      q_valid_p2 & q_br1_valid & ftb_fastpath_en & flush_clr
    & ((q_br1_conf == '1) | (q_br1_conf == '0));

  // ----------------------------------------------------------------
  // ftb_array write port. Write on any valid update (hit overwrite or
  // miss allocate), to the carried way (one-hot decode of the carried
  // encoded way).
  // ----------------------------------------------------------------
  assign array_wr_en_n = ~ftb_upd_valid_u0;
  assign array_wr_addr = upd_set_idx;
  assign array_wr_data = upd_new;

  always_comb begin
    for (int unsigned w = 0; w < FTB_WAYS; w++) begin
      array_wr_way[w] = (ftb_upd_way_u0 == FTB_WAY_BITS'(w));
    end
  end

  // ----------------------------------------------------------------
  // ftb_plru valid write port. Set the carried way's valid on a
  // miss-allocate only. The valid-clear path (val_set = 0) is reserved
  // for the flush protocol and is NOT driven (IC-FTB-07).
  // ----------------------------------------------------------------
  assign plru_val_we_n = ~(ftb_upd_valid_u0 & ~upd_hit);
  assign plru_val_addr = upd_set_idx;
  assign plru_val_set  = 1'b1;

  always_comb begin
    for (int unsigned w = 0; w < FTB_WAYS; w++) begin
      plru_val_way[w] = (ftb_upd_way_u0 == FTB_WAY_BITS'(w));
    end
  end

  // ----------------------------------------------------------------
  // ftb_plru PLRU write port. Two mark-used touch events funneled onto
  // the single port (5.3): an update/allocate write marks the carried
  // way used; a prediction hit marks the hit way used. Update wins on a
  // same-set conflict -- and because an active update borrows the read
  // ports, pred_grant_p1 is 0 whenever upd_active, so the two touches
  // are mutually exclusive and the priority is automatic. plru_rd_plru
  // is the current state of whichever set owns the read port this
  // cycle (update set or prediction set).
  // ----------------------------------------------------------------
  logic [PLRU_BITS-1:0] upd_plru_next;
  logic [PLRU_BITS-1:0] pred_plru_next;
  logic                 pred_touch;

  always_comb begin
    upd_plru_next  = plru_touch(plru_rd_plru, ftb_upd_way_u0);
    pred_plru_next = plru_touch(plru_rd_plru, hit_way);
    pred_touch     = pred_grant_p1 & hit_any & ~upd_active;

    if (upd_active) begin
      plru_plru_we_n  = 1'b0;
      plru_plru_addr  = upd_set_idx;
      plru_plru_wdata = upd_plru_next;
    end else if (pred_touch) begin
      plru_plru_we_n  = 1'b0;
      plru_plru_addr  = pred_set_idx_p1;
      plru_plru_wdata = pred_plru_next;
    end else begin
      plru_plru_we_n  = 1'b1;
      plru_plru_addr  = '0;
      plru_plru_wdata = '0;
    end
  end

  // ----------------------------------------------------------------
  // Invariant assertion (IC-FTB-06 / confidence section 7): the weak
  // allocate values must be unsaturated with the MSB matching their
  // direction, so a fresh entry cannot fast-path on first use.
  // ----------------------------------------------------------------
  initial begin
    if (FTB_CONF_INIT_TKN == {FTB_CONF_WIDTH{1'b1}}
        || FTB_CONF_INIT_TKN[FTB_CONF_WIDTH-1] != 1'b1)
      $error("FTB_CONF_INIT_TKN must be unsaturated with MSB=1");
    if (FTB_CONF_INIT_NTK == {FTB_CONF_WIDTH{1'b0}}
        || FTB_CONF_INIT_NTK[FTB_CONF_WIDTH-1] != 1'b0)
      $error("FTB_CONF_INIT_NTK must be unsaturated with MSB=0");
    // The private layout must fill exactly one ftb_array way, whose
    // width the package derives from ftb_decisions.md 8.
    if ($bits(ftb_entry_t) != FTB_RAM_ENTRY_WIDTH)
      $error("ftb_entry_t width differs from FTB_RAM_ENTRY_WIDTH");
    // The index folds the start offset into its top bits (BP-140), and
    // the split orders the two conditional fields and one new branch,
    // so it keeps at most two (NUM_PRED_SLOTS 1 or 2, ruled
    // session-078).
    if (FTB_SOFF_SHIFT < 0)
      $error("FTB_IDX_BITS is narrower than FTB_BR_POS_BITS");
    if (NUM_PRED_SLOTS >= N_CAND)
      $error("the split keeps at most N_CAND-1 conditionals");
  end

endmodule : ftb_cntrl

`endif // FTB_CNTRL_SV
