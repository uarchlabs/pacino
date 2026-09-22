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
// First predictor in the BP cluster pipeline (p1 output).
// Combinational prediction from the registered entry array.
// Synchronous update on clk posedge when upd_u0[u].valid.
//
// Entry model (BP-086, ubtb_interfaces.md, ftb_decisions.md 4):
// ONE lookup per cycle returns ONE entry describing ONE
// UBTB_BLOCK_BYTES block. The entry mirrors the FTB entry: two
// conditional fields (br0, br1), one block-terminating jump field,
// and a partial fall-through address with no carry bit (TD#124).
// There is no second lookup and no slot-1 PC.
//
// Positions are STORED region-relative and PRESENTED start-relative
// (ftb_decisions.md 4.6, ubtb_interfaces.md pos). The entry is shared
// by every lookup PC in its 32-byte region. The write adds the update
// PC's region offset k to upd_u0[u].pos; the read reports a field
// only when its stored position lies in [k, k+16) of the lookup PC,
// and subtracts k. A field outside that window reports its slot
// invalid (ubtb_interfaces.md pos). Slot 0 is built from br0, slot 1
// from br1: the uBTB does NOT pack visible fields onto the slots or
// reorder storage; that is the FTB read path (4.6 O-3), and
// ubtb_interfaces.md still assigns slot 0 to br0. The jump field is
// reported in the lowest slot that carries no visible conditional
// field.
//
// NUM_PRED_SLOTS sizes the prediction and update port arrays only.
// It does not change the number of lookups. At NUM_PRED_SLOTS = 1
// only the br0 field is reported.
//
// Targets are stored as displacements from the 32-byte-aligned region
// base with a fit/overflow/underflow status (ftb_decisions.md 4.2)
// and are reconstructed to full width on read. The FTB measures a
// conditional target from the branch PC instead (4.6 O-1); the uBTB
// does not. The fall-through reconstructs from the region base plus
// pftAddr and is NOT bounds checked here (see BP-110 Results
// Capture); the FTB result at p2 is authoritative.
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
  parameter int NUM_PRED_SLOTS = 1
)(
  input  logic                             clk,
  input  logic                             rstn,
  input  logic [VA_WIDTH-1:0]              pred_pc_p0,
  output ubtb_pred_t [NUM_PRED_SLOTS-1:0]  pred_p1,
  output ubtb_blk_t                        blk_p1,
  input  ubtb_upd_t  [NUM_PRED_SLOTS-1:0]  upd_u0
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

  // ----------------------------------------------------------------
  // Index, tag and block-base extraction (ubtb_interfaces.md 4)
  // ----------------------------------------------------------------
  // The uBTB indexes at block granularity, the same way the FTB does:
  //   index : pc[UBTB_IDX_BITS+UBTB_OFFSET_BITS-1 : UBTB_OFFSET_BITS]
  //   tag   : the UBTB_TAG_BITS VA bits directly above the index
  // The uBTB tag is narrower than the FTB tag (20 vs 26), so two PCs
  // can alias to one entry. That is a uBTB accuracy property, not a
  // correctness one: the FTB result at p2 is authoritative.

  function automatic logic [UBTB_IDX_BITS-1:0] get_idx(
    input logic [VA_WIDTH-1:0] pc
  );
    return pc[UBTB_OFFSET_BITS +: UBTB_IDX_BITS];
  endfunction

  function automatic logic [UBTB_TAG_BITS-1:0] get_tag(
    input logic [VA_WIDTH-1:0] pc
  );
    return pc[UBTB_OFFSET_BITS+UBTB_IDX_BITS +: UBTB_TAG_BITS];
  endfunction

  // Region base: the PC with the in-block offset cleared. Every stored
  // target displacement and the stored pftAddr are relative to it.
  function automatic logic [VA_WIDTH-1:0] get_base(
    input logic [VA_WIDTH-1:0] pc
  );
    return {pc[VA_WIDTH-1:UBTB_OFFSET_BITS], {UBTB_OFFSET_BITS{1'b0}}};
  endfunction

  // ----------------------------------------------------------------
  // Target encode / reconstruct helpers. Same encoding as the FTB
  // (ftb_cntrl.sv, ftb_decisions.md 4.2) against identical widths.
  // ----------------------------------------------------------------

  // Reconstruct a full-VA conditional target from the stored
  // displacement and the region base. Sign-extend.
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
  // pftAddr (ftb_decisions.md 5.5, 8.1): the region base plus pftAddr
  // in positions. No carry term.
  function automatic logic [VA_WIDTH-1:0] recon_pft(
      input logic [UBTB_PFTADDR_BITS-1:0] pft,
      input logic [VA_WIDTH-1:0]          base);
    recon_pft = base + (VA_WIDTH'(pft) << UBTB_POS_OFFSET_BITS);
  endfunction

  // Region window test (ftb_decisions.md 4.6 R-1). A stored region
  // position is visible to a start at region offset k when it lies in
  // [k, k+16). The difference is one bit wider than a stored position
  // so it carries a sign.
  function automatic logic in_window(
      input logic [UBTB_BR_RPOS_BITS-1:0] rpos,
      input logic [UBTB_BR_POS_BITS-1:0]  k);
    logic [UBTB_BR_RPOS_BITS:0] d;
    d         = (UBTB_BR_RPOS_BITS+1)'(rpos) - (UBTB_BR_RPOS_BITS+1)'(k);
    in_window = (d[UBTB_BR_RPOS_BITS:UBTB_BR_POS_BITS] == '0);
  endfunction

  // Stored region position -> start-relative slot position (4.6 R-2).
  // Meaningful only when in_window() holds.
  function automatic logic [UBTB_BR_POS_BITS-1:0] to_start_pos(
      input logic [UBTB_BR_RPOS_BITS-1:0] rpos,
      input logic [UBTB_BR_POS_BITS-1:0]  k);
    logic [UBTB_BR_RPOS_BITS-1:0] d;
    d            = rpos - UBTB_BR_RPOS_BITS'(k);
    to_start_pos = d[UBTB_BR_POS_BITS-1:0];
  endfunction

  // Region offset of a PC in positions.
  function automatic logic [UBTB_BR_POS_BITS-1:0] get_k(
    input logic [VA_WIDTH-1:0] pc
  );
    return pc[UBTB_OFFSET_BITS-1:UBTB_POS_OFFSET_BITS];
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

  // Decode the stored jump type bits to bp_br_type_e. A return is
  // also a JALR, so is_ret is tested first; a call is indirect when
  // is_jalr is also set (ubtb_interfaces.md, pred_p1 br_type).
  function automatic bp_br_type_e jmp_br_type(input ubtb_jmp_t j);
    if      (j.is_ret)  jmp_br_type = RETURN;
    else if (j.is_call) jmp_br_type = j.is_jalr ? INDIRECT_CALL
                                                : DIRECT_CALL;
    else if (j.is_jalr) jmp_br_type = INDIRECT_NONRET;
    else                jmp_br_type = DIRECT_UNC;
  endfunction

  // Apply one resolved update channel to an entry and return the
  // result. Pure: the caller supplies the entry to modify, so the
  // same helper serves both the single-channel case and the merge of
  // two channels landing on one entry in one cycle.
  //
  // - the fall-through is reduced from the region base and rewritten
  //   on every update, with no carry (TD#124)
  // - a conditional field that is occupied AND visible from this
  //   update start steps its bimodal conf toward the resolved
  //   direction and keeps its stored position. A free field, or one
  //   whose stored position lies outside this start's window (it was
  //   recorded by another start in the region), fills with the weak
  //   init in the resolved direction and takes the REGION position
  //   up.pos + k (ftb_decisions.md 4.6 R-2)
  // - the target displacement is re-encoded on every resolve, so an
  //   unchanged target simply stores the same value and "rewrite the
  //   target if it differs" falls out
  // - the jump field is written whenever is_jmp is set, and its
  //   target is rewritten on every such resolve; its position follows
  //   the same fill rule as a conditional field
  function automatic ubtb_entry_t apply_upd(
      input ubtb_entry_t ent,
      input ubtb_upd_t   up);
    ubtb_entry_t                  e;
    ubtb_cond_t                   fld_old;
    ubtb_cond_t                   fld_new;
    logic [VA_WIDTH-1:0]          base;
    logic [VA_WIDTH-1:0]          off;
    logic [UBTB_BR_POS_BITS-1:0]  k;
    logic [UBTB_BR_RPOS_BITS-1:0] rpos;
    logic                         fresh;
    logic                         jfresh;

    e    = ent;
    base = get_base(up.pc);
    off  = up.pft_addr - base;
    k    = get_k(up.pc);
    rpos = UBTB_BR_RPOS_BITS'(up.pos) + UBTB_BR_RPOS_BITS'(k);

    // Fall-through reduce: the block end as a position offset from
    // the region base.
    e.pft = off[UBTB_POS_OFFSET_BITS +: UBTB_PFTADDR_BITS];

    fld_old = (up.br_idx == 1'b0) ? e.br0 : e.br1;
    fresh   = ~(fld_old.valid & in_window(fld_old.pos, k));

    fld_new.valid = 1'b1;
    fld_new.pos   = fresh ? rpos : fld_old.pos;
    fld_new.tgt   = enc_br_disp(up.target, base);
    fld_new.stat  = br_stat(up.target, base);
    fld_new.conf  = fresh
      ? (up.br_taken ? UBTB_CONF_INIT_TKN : UBTB_CONF_INIT_NTK)
      : conf_step(fld_old.conf, up.br_taken);

    if (up.is_br) begin
      if (up.br_idx == 1'b0) e.br0 = fld_new;
      else                   e.br1 = fld_new;
    end

    jfresh = ~(e.jmp.valid & in_window(e.jmp.pos, k));
    if (up.is_jmp) begin
      e.jmp.valid   = 1'b1;
      e.jmp.pos     = jfresh ? rpos : e.jmp.pos;
      e.jmp.tgt     = enc_jmp_disp(up.jmp_target, base);
      e.jmp.stat    = jmp_stat(up.jmp_target, base);
      e.jmp.is_call = up.is_call;
      e.jmp.is_ret  = up.is_ret;
      e.jmp.is_jalr = up.is_jalr;
    end

    apply_upd = e;
  endfunction

  // ----------------------------------------------------------------
  // Prediction path (combinational from registered mem)
  // ----------------------------------------------------------------
  // One index, one tag, one way search. The matched entry supplies
  // every prediction slot. The block reads mem (a flop array), so it
  // is nba_sequent and re-evaluates after FF updates (the CLAUDE.md
  // stl_sequent workaround note).
  logic [UBTB_IDX_BITS-1:0]    p_idx;
  logic [UBTB_TAG_BITS-1:0]    p_tag;
  logic [VA_WIDTH-1:0]         p_base;
  logic [UBTB_BR_POS_BITS-1:0] p_k;

  assign p_idx  = get_idx(pred_pc_p0);
  assign p_tag  = get_tag(pred_pc_p0);
  assign p_base = get_base(pred_pc_p0);
  assign p_k    = get_k(pred_pc_p0);

  logic [UBTB_WAYS-1:0]   p_hit_vec;
  logic [WR_PTR_BITS-1:0] p_hit_way;
  logic                   p_hit;
  ubtb_entry_t            p_ent;
  ubtb_cond_t             p_cfld;
  logic                   p_cval;
  logic                   p_vis0;
  logic                   p_vis1;
  logic                   p_visj;
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
    p_cval     = 1'b0;
    p_jmp_used = 1'b0;

    // Region window (4.6 R-1): only fields whose stored position lies
    // in [k, k+16) of the lookup PC are reported.
    p_vis0 = p_ent.br0.valid & in_window(p_ent.br0.pos, p_k);
    p_vis1 = p_ent.br1.valid & in_window(p_ent.br1.pos, p_k);
    p_visj = p_ent.jmp.valid & in_window(p_ent.jmp.pos, p_k);

    if (p_hit) begin
      blk_p1.hit      = 1'b1;
      blk_p1.pft_addr = recon_pft(p_ent.pft, p_base);

      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        // Slot 0 takes br0, slot 1 takes br1, each only when visible
        // from this lookup PC. A slot above 1 carries no conditional
        // field (NUM_PRED_SLOTS 3+ is undefined per
        // ubtb_interfaces.md 2).
        if (s == 0) begin
          p_cfld = p_ent.br0;
          p_cval = p_vis0;
        end else if (s == 1) begin
          p_cfld = p_ent.br1;
          p_cval = p_vis1;
        end else begin
          p_cfld = '0;
          p_cval = 1'b0;
        end

        if (p_cval) begin
          pred_p1[s].valid    = 1'b1;
          pred_p1[s].target   = recon_br(p_cfld.tgt, p_base);
          pred_p1[s].br_type  = COND;
          pred_p1[s].br_taken = p_cfld.conf[UBTB_CONF_WIDTH-1];
          pred_p1[s].pos      = to_start_pos(p_cfld.pos, p_k);
          pred_p1[s].conf     = p_cfld.conf;
        end else if (p_visj && !p_jmp_used) begin
          // Block-terminating jump: reported in the LOWEST slot that
          // carries no conditional field. br_taken and conf are not
          // meaningful for a jump and are driven 0.
          p_jmp_used          = 1'b1;
          pred_p1[s].valid    = 1'b1;
          pred_p1[s].target   = recon_jmp(p_ent.jmp.tgt, p_base);
          pred_p1[s].br_type  = jmp_br_type(p_ent.jmp);
          pred_p1[s].br_taken = 1'b0;
          pred_p1[s].pos      = to_start_pos(p_ent.jmp.pos, p_k);
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
  logic                     u_act    [NUM_PRED_SLOTS];
  logic [UBTB_IDX_BITS-1:0] u_idx    [NUM_PRED_SLOTS];
  logic [UBTB_TAG_BITS-1:0] u_tag    [NUM_PRED_SLOTS];
  logic [VA_WIDTH-1:0]      u_base   [NUM_PRED_SLOTS];
  logic                     u_hit    [NUM_PRED_SLOTS];
  logic [WR_PTR_BITS-1:0]   u_way    [NUM_PRED_SLOTS];
  ubtb_entry_t              u_new    [NUM_PRED_SLOTS];
  ubtb_entry_t              u_ent;
  logic                     u_wr     [NUM_PRED_SLOTS];

  always_comb begin
    // Pass 1: per-channel address decode and way search.
    for (int u = 0; u < NUM_PRED_SLOTS; u++) begin
      u_act[u]  = upd_u0[u].valid;
      u_idx[u]  = get_idx(upd_u0[u].pc);
      u_tag[u]  = get_tag(upd_u0[u].pc);
      u_base[u] = get_base(upd_u0[u].pc);

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
    // the stored entry; a tag miss allocates a zeroed entry so every
    // field the channel does not write reads back empty. When an
    // earlier channel this cycle already rewrote this exact entry --
    // same set, same way, same tag -- that channel's field writes are
    // replayed first, so both survive in the single write below.
    for (int u = 0; u < NUM_PRED_SLOTS; u++) begin
      u_ent       = u_hit[u] ? mem[u_idx[u]][u_way[u]] : '0;
      u_ent.valid = 1'b1;
      u_ent.tag   = u_tag[u];
      for (int k = 0; k < NUM_PRED_SLOTS; k++) begin
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
    for (int u = 0; u < NUM_PRED_SLOTS; u++) begin
      u_wr[u] = u_act[u];
      for (int k = 0; k < NUM_PRED_SLOTS; k++) begin
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
      for (int u = 0; u < NUM_PRED_SLOTS; u++) begin
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
  end

endmodule : ubtb

`endif // UBTB_SV
