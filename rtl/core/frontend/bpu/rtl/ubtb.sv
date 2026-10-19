// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    ubtb.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Micro Branch Target Buffer: 256-entry, 4-way set-associative.
// First predictor in the BP cluster pipeline. Its outputs carry the p1
// suffix of the stage that registers them; they are combinational from
// pred_pc_p0 and valid within the p0 cycle (mem is a flop array read
// combinationally, see uBTB timing below).
// Synchronous update on clk posedge when upd_u0[u].valid.
//
// Entry model (BP-086, ubtb_interfaces.md, ftb_decisions.md 4):
// ONE lookup per cycle returns ONE entry describing ONE
// UBTB_BLOCK_BYTES block. The entry mirrors the FTB entry: two
// conditional fields (br0, br1), one block-terminating jump field,
// and a partial fall-through address with no carry bit (TD#124).
// There is no second lookup and no slot-1 PC.
//
// ONE ENTRY PER START PC (BP-140, ruled by Jeff 2026-10-18). The
// entry describes the block from one start PC at 2-byte granularity
// within the partial tag: the tag carries the start's halfword offset
// pc[4:1] and the index folds it into its top bits (get_idx, get_tag,
// PROVISIONAL). Until BP-140 one entry was shared by every start of a
// 32-byte region, with region-relative positions and a read window
// (ftb_decisions.md 4.6). Positions are stored start-relative, the
// port width, and storage is kept in ascending position (br0 below
// br1, the jump last), so slot 0 is built from br0 and slot 1 from br1
// with no window and no reordering. The jump field is reported in the
// lowest slot that carries no conditional field.
//
// THE SPLIT AT UPDATE (BP-140, ruled by Jeff), the FTB's rule
// (ftb_cntrl.sv): an entry never holds more than N_SLOTS branches; when
// an update would make it hold more, the lowest positions are kept and
// the block end becomes the PC of the lowest-position branch not kept.
// The uBTB and the FTB then store the same end for each start, so the
// p1 end agrees with the p2 end. See apply_upd.
//
// N_SLOTS sizes the prediction and update port arrays and the number
// of branches an entry holds. It does not change the number of
// lookups.
//
// Targets are stored as displacements from the block start with a
// fit/overflow/underflow status (ftb_decisions.md 4.2) and are
// reconstructed to full width on read. The FTB measures a conditional
// target from the branch PC instead (4.6 O-1); the uBTB does not. The
// fall-through reconstructs from the start plus pftAddr and is NOT
// bounds checked here (see BP-110 Results Capture); the FTB result at
// p2 is authoritative.
//
// conf is a bimodal DIRECTION counter. Its most significant bit is
// the predicted direction for that conditional branch.
//
// Replacement is a per-set round-robin write pointer. Storage is a
// single array local to this module; it is not split into separate
// data and valid peers the way the FTB is.
//
// uBTB timing:
// The lookup is combinational. pred_p1 and blk_p1 are formed from
// pred_pc_p0 and the registered array in the same cycle, with no
// register between them; the module adds no cycle of latency. The
// p1 suffix names the cluster stage that consumes them: bp_cluster.sv
// registers them into r_ubtb_pred_p1 / r_ubtb_blk_p1.
// Update: synchronous write on clk posedge when upd_u0[u].valid.
// Read-during-write: prediction reflects the pre-update state; the
// new entry is visible on the following cycle (no bypass).
// ===================================================================

`ifndef UBTB_SV
`define UBTB_SV

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ubtb #(
  // N_SLOTS: the slot count of this instance. It defaults to
  // bp_defines_pkg::NUM_PRED_SLOTS; tb_ubtb overrides it to build one
  // uBTB at each of 1 and 2 in one simulation. Renamed from
  // NUM_PRED_SLOTS, which shadowed the package parameter, and no longer
  // a literal 1 (BP-128).
  parameter int N_SLOTS = NUM_PRED_SLOTS
)(
  input  logic                             clk,
  input  logic                             rstn,
  input  logic [VA_WIDTH-1:0]              pred_pc_p0,
  output ubtb_pred_t [N_SLOTS-1:0]  pred_p1,
  output ubtb_blk_t                        blk_p1,
  input  ubtb_upd_t  [N_SLOTS-1:0]  upd_u0
);

  // ----------------------------------------------------------------
  // Storage
  // ----------------------------------------------------------------
  // mem[set][way]: UBTB_SETS=64, UBTB_WAYS=4
  ubtb_entry_t mem[UBTB_SETS][UBTB_WAYS];

  // Per-set write pointer for round-robin replacement on miss. The
  // same width also indexes a way. $clog2(UBTB_WAYS) = 2.
  localparam int WR_PTR_BITS = $clog2(UBTB_WAYS);
  logic [WR_PTR_BITS-1:0] wr_ptr[UBTB_SETS];

  // The end of a block that holds no jump and was never split: one
  // block above the start, in positions, the cluster's p1 end on a
  // miss and the FTB's (BP-140).
  localparam logic [UBTB_PFTADDR_BITS-1:0] PFT_NAT =
    UBTB_PFTADDR_BITS'(UBTB_BLOCK_BYTES >> UBTB_POS_OFFSET_BITS); // 16

  // Conditional candidates the split orders: the two stored fields and
  // the resolving branch.
  localparam int N_CAND = 3;

  // ----------------------------------------------------------------
  // Index and tag extraction (ubtb_interfaces.md 4; BP-140)
  // ----------------------------------------------------------------
  // The uBTB indexes at block granularity with the start offset folded
  // in, the same way the FTB does (bp_defines_pkg UBTB_SOFF_SHIFT):
  //   index : pc[10:5] ^ (pc[4:1] << UBTB_SOFF_SHIFT)
  //   tag   : {pc[30:11], pc[4:1]}
  // The region part of the uBTB tag is narrower than the FTB's (20 vs
  // 26), so two starts can alias to one entry. That is a uBTB accuracy
  // property, not a correctness one: the FTB result at p2 is
  // authoritative.

  // The start's halfword offset in its 32-byte region.
  function automatic logic [UBTB_BR_POS_BITS-1:0] get_off(
    input logic [VA_WIDTH-1:0] pc
  );
    return pc[UBTB_OFFSET_BITS-1:UBTB_POS_OFFSET_BITS];
  endfunction

  function automatic logic [UBTB_IDX_BITS-1:0] get_idx(
    input logic [VA_WIDTH-1:0] pc
  );
    return pc[UBTB_OFFSET_BITS +: UBTB_IDX_BITS]
         ^ (UBTB_IDX_BITS'(get_off(pc)) << UBTB_SOFF_SHIFT);
  endfunction

  function automatic logic [UBTB_TAG_BITS-1:0] get_tag(
    input logic [VA_WIDTH-1:0] pc
  );
    return {pc[UBTB_OFFSET_BITS+UBTB_IDX_BITS +: UBTB_RTAG_BITS],
            get_off(pc)};
  endfunction

  // ----------------------------------------------------------------
  // Target encode / reconstruct helpers. Same encoding as the FTB
  // (ftb_cntrl.sv, ftb_decisions.md 4.2) against identical widths.
  // ----------------------------------------------------------------

  // Reconstruct a full-VA conditional target from the stored
  // displacement and the block start. Sign-extend.
  function automatic logic [VA_WIDTH-1:0] recon_br(
      input logic [UBTB_BR_TGT_BITS-1:0] disp,
      input logic [VA_WIDTH-1:0]         base);
    recon_br = base
      + {{(VA_WIDTH-UBTB_BR_TGT_BITS){disp[UBTB_BR_TGT_BITS-1]}}, disp};
  endfunction

  // Reconstruct a full-VA jump target from the stored displacement.
  function automatic logic [VA_WIDTH-1:0] recon_jmp(
      input logic [UBTB_JMP_TGT_BITS-1:0] disp,
      input logic [VA_WIDTH-1:0]          base);
    recon_jmp = base
      + {{(VA_WIDTH-UBTB_JMP_TGT_BITS){disp[UBTB_JMP_TGT_BITS-1]}},
         disp};
  endfunction

  // Encode a full-VA conditional target to the stored displacement.
  // Lossless when the branch is in reach; br_stat records the status.
  function automatic logic [UBTB_BR_TGT_BITS-1:0] enc_br_disp(
      input logic [VA_WIDTH-1:0] tgt, input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0] d;
    d = tgt - base;
    enc_br_disp = d[UBTB_BR_TGT_BITS-1:0];
  endfunction

  function automatic logic [UBTB_JMP_TGT_BITS-1:0] enc_jmp_disp(
      input logic [VA_WIDTH-1:0] tgt, input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0] d;
    d = tgt - base;
    enc_jmp_disp = d[UBTB_JMP_TGT_BITS-1:0];
  endfunction

  // Target status: 00 fit, 01 overflow (too far forward), 10
  // underflow (too far backward). fit when the sign-extended
  // displacement reconstructs the target exactly.
  function automatic logic [TAR_STAT_BITS-1:0] br_stat(
      input logic [VA_WIDTH-1:0] tgt, input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0] d;
    d = tgt - base;
    if (recon_br(d[UBTB_BR_TGT_BITS-1:0], base) == tgt)
      br_stat = 2'b00;
    else if (d[VA_WIDTH-1]) br_stat = 2'b10;
    else                    br_stat = 2'b01;
  endfunction

  function automatic logic [TAR_STAT_BITS-1:0] jmp_stat(
      input logic [VA_WIDTH-1:0] tgt, input logic [VA_WIDTH-1:0] base);
    logic [VA_WIDTH-1:0] d;
    d = tgt - base;
    if (recon_jmp(d[UBTB_JMP_TGT_BITS-1:0], base) == tgt)
      jmp_stat = 2'b00;
    else if (d[VA_WIDTH-1]) jmp_stat = 2'b10;
    else                    jmp_stat = 2'b01;
  endfunction

  // Reconstruct the full-width fall-through from the stored partial
  // pftAddr (ftb_decisions.md 5.5, 8.1): the block start plus pftAddr
  // in positions (BP-140; it was the region base). No carry term.
  function automatic logic [VA_WIDTH-1:0] recon_pft(
      input logic [UBTB_PFTADDR_BITS-1:0] pft,
      input logic [VA_WIDTH-1:0]          start);
    recon_pft = start + (VA_WIDTH'(pft) << UBTB_POS_OFFSET_BITS);
  endfunction

  // The end in positions from the start that the FTB read would
  // report: pftAddr, or PFT_NAT when it fails FTB-G1 or FTB-G3
  // (ftb_cntrl.sv eff_end). The update's past-the-end test uses it, so
  // the uBTB and the FTB keep the same branches. The uBTB read itself
  // is not bounds checked (header).
  function automatic logic [UBTB_PFTADDR_BITS-1:0] eff_end(
      input logic [UBTB_PFTADDR_BITS-1:0] pft);
    return ((pft == '0) || (pft > PFT_NAT + UBTB_PFTADDR_BITS'(1)))
         ? PFT_NAT : pft;
  endfunction

  // Sort key of a conditional candidate: an empty field sorts after
  // every filled one, filled fields by ascending position.
  function automatic logic [UBTB_BR_POS_BITS:0] cand_key(
      input ubtb_cond_t c);
    return {~c.valid, c.pos};
  endfunction

  // Saturating bimodal step (UBTB_CONF_WIDTH bits). up = resolved
  // taken -> increment toward all-ones; down -> decrement toward
  // all-zeros. Saturates at both ends.
  function automatic logic [UBTB_CONF_WIDTH-1:0] conf_step(
      input logic [UBTB_CONF_WIDTH-1:0] cur, input logic up);
    if (up) conf_step = (cur == {UBTB_CONF_WIDTH{1'b1}})
                          ? cur : cur + 1'b1;
    else    conf_step = (cur == '0) ? cur : cur - 1'b1;
  endfunction

  // Decode the stored jump type bits to bp_br_type_e. is_ret and
  // is_call both set is the JALR that pops then pushes, RETURN_CALL
  // (ubtb_interfaces.md, pred_p1 br_type; TD#152), tested first. A
  // return is also a JALR, so is_ret is tested next; a call is
  // indirect when is_jalr is also set.
  function automatic bp_br_type_e jmp_br_type(input ubtb_jmp_t j);
    if      (j.is_ret && j.is_call) jmp_br_type = RETURN_CALL;
    else if (j.is_ret)  jmp_br_type = RETURN;
    else if (j.is_call) jmp_br_type = j.is_jalr ? INDIRECT_CALL
                                                : DIRECT_CALL;
    else if (j.is_jalr) jmp_br_type = INDIRECT_NONRET;
    else                jmp_br_type = DIRECT_UNC;
  endfunction

  // Apply one resolved update channel to an entry and return the
  // result. Pure: the caller supplies the entry to modify (the stored
  // entry on a hit, an empty one ending PFT_NAT above the start on a
  // miss), so the same helper serves both the single-channel case and
  // the merge of two channels landing on one entry in one cycle.
  //
  // The rule is the FTB's (ftb_cntrl.sv, THE UPDATE; BP-140):
  // - THE SAME BRANCH IS THE SAME POSITION (ubtb_interfaces.md
  //   Allocation and field writes, ftb_decisions.md 5.5, TD#156). A
  //   conditional at a stored conditional's position steps its conf
  //   toward the resolved direction and rewrites its target; a jump at
  //   the stored jump's position rewrites the jump field. The other
  //   kind at a stored position replaces that field. The field br_idx
  //   names is not used: storage is in position order, so a field is
  //   named by its position (BP-140; the uBTB filled the field br_idx
  //   named until then)
  // - a resolution at or after the stored end, or after the stored
  //   jump, is past this block as the entry describes it and changes
  //   nothing
  // - a new branch joins the held ones, weak init in the resolved
  //   direction; a new jump removes every conditional after it
  // - THE SPLIT: more than N_SLOTS branches keep the lowest N_SLOTS
  //   positions, and the end becomes the PC of the lowest position not
  //   kept; a jump not kept clears the jump field
  // - otherwise the end is a written jump's resolved end (the update's
  //   pft_addr, TD#164), else the stored end. A conditional's pft_addr
  //   is its block's predicted end and is not written (PROVISIONAL)
  // - the target displacement is re-encoded on every resolve, so an
  //   unchanged target simply stores the same value
  function automatic ubtb_entry_t apply_upd(
      input ubtb_entry_t ent,
      input ubtb_upd_t   up);
    ubtb_entry_t                  e;
    ubtb_cond_t                   fld_old;
    ubtb_cond_t                   fld_new;
    ubtb_cond_t                   tmp;
    ubtb_jmp_t                    jnew;
    ubtb_cond_t                   cand [N_CAND];
    ubtb_jmp_t                    jcand;
    logic [VA_WIDTH-1:0]          off;
    logic                         m0, m1, mj, past, isb, isj;
    int                           nc;
    logic                         split;
    logic [UBTB_BR_POS_BITS-1:0]  cut;

    e    = ent;
    off  = up.pft_addr - up.pc;

    m0   = e.br0.valid & (e.br0.pos == up.pos);
    m1   = e.br1.valid & (e.br1.pos == up.pos);
    mj   = e.jmp.valid & (e.jmp.pos == up.pos);
    past = (UBTB_PFTADDR_BITS'(up.pos) >= eff_end(e.pft))
         | (e.jmp.valid & (e.jmp.pos < up.pos));
    isb  = up.is_br & ~past;
    isj  = up.is_jmp & ~up.is_br & ~past;

    fld_old       = m0 ? e.br0 : e.br1;
    fld_new.valid = 1'b1;
    fld_new.pos   = up.pos;
    fld_new.tgt   = enc_br_disp(up.target, up.pc);
    fld_new.stat  = br_stat(up.target, up.pc);
    fld_new.conf  = (m0 | m1)
      ? conf_step(fld_old.conf, up.br_taken)
      : (up.br_taken ? UBTB_CONF_INIT_TKN : UBTB_CONF_INIT_NTK);

    jnew.valid   = 1'b1;
    jnew.pos     = up.pos;
    jnew.tgt     = enc_jmp_disp(up.jmp_target, up.pc);
    jnew.stat    = jmp_stat(up.jmp_target, up.pc);
    jnew.is_call = up.is_call;
    jnew.is_ret  = up.is_ret;
    jnew.is_jalr = up.is_jalr;

    cand[0] = e.br0;
    cand[1] = e.br1;
    cand[2] = '0;
    jcand   = e.jmp;
    if (isb) begin
      if (m0) cand[0] = '0;
      if (m1) cand[1] = '0;
      cand[2] = fld_new;
      if (mj) jcand = '0;
    end else if (isj) begin
      if (e.br0.valid && (e.br0.pos >= up.pos)) cand[0] = '0;
      if (e.br1.valid && (e.br1.pos >= up.pos)) cand[1] = '0;
      jcand = jnew;
    end

    // Ascending position, empty last.
    if (cand_key(cand[1]) < cand_key(cand[0])) begin
      tmp = cand[0]; cand[0] = cand[1]; cand[1] = tmp;
    end
    if (cand_key(cand[2]) < cand_key(cand[1])) begin
      tmp = cand[1]; cand[1] = cand[2]; cand[2] = tmp;
    end
    if (cand_key(cand[1]) < cand_key(cand[0])) begin
      tmp = cand[0]; cand[0] = cand[1]; cand[1] = tmp;
    end

    nc = 0;
    for (int i = 0; i < N_CAND; i++) begin
      if (cand[i].valid) nc++;
    end
    split = (nc + int'(jcand.valid)) > N_SLOTS;
    cut   = (nc > N_SLOTS) ? cand[N_SLOTS].pos : jcand.pos;

    e.br0 = cand[0];
    e.br1 = (N_SLOTS > 1) ? cand[1] : '0;
    e.jmp = (nc < N_SLOTS) ? jcand : '0;

    if (split)    e.pft = UBTB_PFTADDR_BITS'(cut);
    else if (isj) e.pft = off[UBTB_POS_OFFSET_BITS +: UBTB_PFTADDR_BITS];

    apply_upd = e;
  endfunction

  // ----------------------------------------------------------------
  // Prediction path (combinational in p0, from pred_pc_p0 and mem)
  // ----------------------------------------------------------------
  // One index, one tag, one way search. The matched entry supplies
  // every prediction slot. The block reads mem (a flop array), so it
  // is nba_sequent and re-evaluates after FF updates (the CLAUDE.md
  // stl_sequent workaround note).
  logic [UBTB_IDX_BITS-1:0]    p_idx;
  logic [UBTB_TAG_BITS-1:0]    p_tag;

  assign p_idx  = get_idx(pred_pc_p0);
  assign p_tag  = get_tag(pred_pc_p0);

  logic [UBTB_WAYS-1:0]   p_hit_vec;
  logic [WR_PTR_BITS-1:0] p_hit_way;
  logic                   p_hit;
  ubtb_entry_t            p_ent;
  ubtb_cond_t             p_cfld;
  logic                   p_jmp_used;

  always_comb begin
    p_hit_vec = '0;
    p_hit_way = '0;
    for (int unsigned w = 0; w < UBTB_WAYS; w++) begin
      p_hit_vec[w] = mem[p_idx][w].valid
                     && (mem[p_idx][w].tag == p_tag);
    end
    for (int unsigned w = 0; w < UBTB_WAYS; w++) begin
      if (p_hit_vec[w]) p_hit_way = WR_PTR_BITS'(w);
    end
    p_hit = |p_hit_vec;
    p_ent = mem[p_idx][p_hit_way];

    // Miss: every prediction slot and the whole block sideband are
    // driven to zero (ubtb_interfaces.md, Semantics).
    pred_p1    = '0;
    blk_p1     = '0;
    p_cfld     = '0;
    p_jmp_used = 1'b0;

    if (p_hit) begin
      blk_p1.hit      = 1'b1;
      blk_p1.pft_addr = recon_pft(p_ent.pft, pred_pc_p0);

      for (int s = 0; s < N_SLOTS; s++) begin
        // Slot 0 takes br0, slot 1 takes br1. Every field is this
        // start's (BP-140), so there is no window. A slot above 1
        // carries no conditional field (N_SLOTS 3+ is undefined per
        // ubtb_interfaces.md 2).
        if (s == 0)      p_cfld = p_ent.br0;
        else if (s == 1) p_cfld = p_ent.br1;
        else             p_cfld = '0;

        if (p_cfld.valid) begin
          pred_p1[s].valid    = 1'b1;
          pred_p1[s].target   = recon_br(p_cfld.tgt, pred_pc_p0);
          pred_p1[s].br_type  = COND;
          pred_p1[s].br_taken = p_cfld.conf[UBTB_CONF_WIDTH-1];
          pred_p1[s].pos      = p_cfld.pos;
          pred_p1[s].conf     = p_cfld.conf;
        end else if (p_ent.jmp.valid && !p_jmp_used) begin
          // Block-terminating jump: reported in the LOWEST slot that
          // carries no conditional field. br_taken and conf are not
          // meaningful for a jump and are driven 0.
          p_jmp_used          = 1'b1;
          pred_p1[s].valid    = 1'b1;
          pred_p1[s].target   = recon_jmp(p_ent.jmp.tgt, pred_pc_p0);
          pred_p1[s].br_type  = jmp_br_type(p_ent.jmp);
          pred_p1[s].br_taken = 1'b0;
          pred_p1[s].pos      = p_ent.jmp.pos;
          pred_p1[s].conf     = '0;
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // Update path decode (combinational)
  // ----------------------------------------------------------------
  // Each channel derives its own set index and tag from its own pc.
  // Both channels may target the same entry in the same cycle and
  // write different fields of it: the channels are merged here, in
  // channel order, and only the last channel targeting a given
  // (set, way) actually writes.
  logic                     u_act    [N_SLOTS];
  logic [UBTB_IDX_BITS-1:0] u_idx    [N_SLOTS];
  logic [UBTB_TAG_BITS-1:0] u_tag    [N_SLOTS];
  logic                     u_hit    [N_SLOTS];
  logic [WR_PTR_BITS-1:0]   u_way    [N_SLOTS];
  ubtb_entry_t              u_new    [N_SLOTS];
  ubtb_entry_t              u_ent;
  logic                     u_wr     [N_SLOTS];

  always_comb begin
    // Pass 1: per-channel address decode and way search.
    for (int u = 0; u < N_SLOTS; u++) begin
      u_act[u]  = upd_u0[u].valid;
      u_idx[u]  = get_idx(upd_u0[u].pc);
      u_tag[u]  = get_tag(upd_u0[u].pc);

      // Way search against the registered array (pre-update state).
      // On a miss the round-robin write pointer names the victim.
      u_hit[u] = 1'b0;
      u_way[u] = wr_ptr[u_idx[u]];
      for (int unsigned w = 0; w < UBTB_WAYS; w++) begin
        if (mem[u_idx[u]][w].valid
            && mem[u_idx[u]][w].tag == u_tag[u]) begin
          u_hit[u] = 1'b1;
          u_way[u] = WR_PTR_BITS'(w);
        end
      end
    end

    // Pass 2: build each channel's write-back entry. A tag hit reads
    // the stored entry; a tag miss allocates an empty entry ending one
    // block above the start (PFT_NAT, BP-140), so every field the
    // channel does not write reads back empty. When an earlier channel
    // this cycle already rewrote this exact entry -- same set, same
    // way, same tag -- that channel's field writes are replayed first,
    // so both survive in the single write below. The split gives the
    // same entry in either order (BP-140).
    for (int u = 0; u < N_SLOTS; u++) begin
      if (u_hit[u]) begin
        u_ent = mem[u_idx[u]][u_way[u]];
      end else begin
        u_ent     = '0;
        u_ent.pft = PFT_NAT;
      end
      u_ent.valid = 1'b1;
      u_ent.tag   = u_tag[u];
      for (int k = 0; k < N_SLOTS; k++) begin
        if (k < u && u_act[k] && u_idx[k] == u_idx[u]
            && u_way[k] == u_way[u] && u_tag[k] == u_tag[u]) begin
          u_ent = apply_upd(u_ent, upd_u0[k]);
        end
      end
      u_new[u] = apply_upd(u_ent, upd_u0[u]);
    end

    // Pass 3: write suppression. A later active channel targeting
    // the same set and way already carries this channel's result
    // forward (or, on a tag conflict at one way, deliberately
    // overrides it), so only the last such channel drives the array.
    for (int u = 0; u < N_SLOTS; u++) begin
      u_wr[u] = u_act[u];
      for (int k = 0; k < N_SLOTS; k++) begin
        if (k > u && u_act[k] && u_idx[k] == u_idx[u]
            && u_way[k] == u_way[u]) begin
          u_wr[u] = 1'b0;
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // Reset and array write (synchronous)
  // ----------------------------------------------------------------
  // Reset clears the entry valid bits only; the remaining fields are
  // don't-care while valid is 0 and are not reset (power saving).
  // The write pointer advances once per surviving miss-allocate. Two
  // channels missing in one set land on the same way and therefore
  // collapse to a single write and a single pointer step.
  integer s, w;
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      for (s = 0; s < UBTB_SETS; s++) begin
        for (w = 0; w < UBTB_WAYS; w++) begin
          mem[s][w].valid <= 1'b0;
        end
        wr_ptr[s] <= '0;
      end
    end else begin
      for (int u = 0; u < N_SLOTS; u++) begin
        if (u_wr[u]) begin
          mem[u_idx[u]][u_way[u]] <= u_new[u];
          if (!u_hit[u]) begin
            wr_ptr[u_idx[u]] <= wr_ptr[u_idx[u]] + 1'b1;
          end
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // Invariant check: the weak allocate values must be unsaturated
  // with the MSB matching their direction, so a freshly filled field
  // predicts the observed direction without reading as strong.
  // ----------------------------------------------------------------
  initial begin
    if (UBTB_CONF_INIT_TKN == {UBTB_CONF_WIDTH{1'b1}}
        || UBTB_CONF_INIT_TKN[UBTB_CONF_WIDTH-1] != 1'b1)
      $error("UBTB_CONF_INIT_TKN must be unsaturated with MSB=1");
    if (UBTB_CONF_INIT_NTK == {UBTB_CONF_WIDTH{1'b0}}
        || UBTB_CONF_INIT_NTK[UBTB_CONF_WIDTH-1] != 1'b0)
      $error("UBTB_CONF_INIT_NTK must be unsaturated with MSB=0");
    // The split orders the two conditional fields and one new branch,
    // so it keeps at most two; the index folds the start offset into
    // its top bits (BP-140).
    if (N_SLOTS >= N_CAND)
      $error("the split keeps at most N_CAND-1 conditionals");
    if (UBTB_SOFF_SHIFT < 0)
      $error("UBTB_IDX_BITS is narrower than UBTB_BR_POS_BITS");
  end

endmodule : ubtb

`endif // UBTB_SV
