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
// and a partial fall-through address plus a carry bit. Prediction
// slot 0 is built from br0, slot 1 from br1. The jump field is
// reported in the lowest slot that carries no valid conditional
// field. There is no second lookup and no slot-1 PC.
//
// NUM_PRED_SLOTS sizes the prediction and update port arrays only.
// It does not change the number of lookups. At NUM_PRED_SLOTS = 1
// only the br0 field is reported.
//
// Targets are stored as displacements from block start with a
// fit/overflow/underflow status (ftb_decisions.md 4.2) and are
// reconstructed to full width on read. Reconstruction is
// unconditional; there is no fall-through error check and no error
// output (ftb_decisions.md 4.5).
//
// conf is a bimodal DIRECTION counter. Its most significant bit is
// the predicted direction for that conditional branch.
//
// Replacement is a per-set round-robin write pointer. Storage is a
// single array local to this module; it is not split into separate
// data and valid peers the way the FTB is.
//
// uBTB pipeline timing:
// p0: pred_pc_p0 presented. Index and tag derived comb.
// p1: mem is registered. pred_p1 and blk_p1 are comb from mem.
//     Both valid at the start of p1, one cycle after pred_pc_p0.
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

  // Block start address: the PC with the in-block offset cleared.
  // Every stored displacement is relative to this base.
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
  // displacement and the block-start base. Sign-extend; no error
  // check on reconstruction (4.5).
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
  // index and the carry bit (ftb_decisions.md 8.1). pft holds the
  // in-block instruction index at expanded granularity; carry adds
  // one whole block when the end crosses the block boundary.
  function automatic logic [VA_WIDTH-1:0] recon_pft(
      input logic [UBTB_PFTADDR_BITS-1:0] pft,
      input logic                         carry,
      input logic [VA_WIDTH-1:0]          base);
    recon_pft = base
      + ({{(VA_WIDTH-UBTB_PFTADDR_BITS){1'b0}}, pft} << UBTB_POS_OFFSET_BITS)
      + (carry ? VA_WIDTH'(UBTB_BLOCK_BYTES) : VA_WIDTH'(0));
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
  // - the fall-through is reduced and rewritten on every update
  // - a conditional field that is already occupied steps its bimodal
  //   conf toward the resolved direction and keeps its stored
  //   position; a free field fills with the weak init in the
  //   resolved direction and takes its position from the update
  // - the target displacement is re-encoded on every resolve, so an
  //   unchanged target simply stores the same value and "rewrite the
  //   target if it differs" falls out
  // - the jump field is written whenever is_jmp is set, and its
  //   target is rewritten on every such resolve
  function automatic ubtb_entry_t apply_upd(
      input ubtb_entry_t ent,
      input ubtb_upd_t   up);
    ubtb_entry_t         e;
    ubtb_cond_t          fld_old;
    ubtb_cond_t          fld_new;
    logic [VA_WIDTH-1:0] base;
    logic [VA_WIDTH-1:0] off;
    logic                fresh;
    logic                jfresh;

    e    = ent;
    base = get_base(up.pc);
    off  = up.pft_addr - base;

    // Fall-through reduce: pft is the in-block instruction index of
    // the block end at expanded granularity, carry is set when the
    // end crosses the block boundary.
    e.pft   = {{(UBTB_PFTADDR_BITS-(UBTB_OFFSET_BITS-UBTB_POS_OFFSET_BITS))
                {1'b0}}, off[UBTB_OFFSET_BITS-1:UBTB_POS_OFFSET_BITS]};
    e.carry = |off[VA_WIDTH-1:UBTB_OFFSET_BITS];

    fld_old = (up.br_idx == 1'b0) ? e.br0 : e.br1;
    fresh   = ~fld_old.valid;

    fld_new.valid = 1'b1;
    fld_new.pos   = fresh ? up.pos : fld_old.pos;
    fld_new.tgt   = enc_br_disp(up.target, base);
    fld_new.stat  = br_stat(up.target, base);
    fld_new.conf  = fresh
      ? (up.br_taken ? UBTB_CONF_INIT_TKN : UBTB_CONF_INIT_NTK)
      : conf_step(fld_old.conf, up.br_taken);

    if (up.is_br) begin
      if (up.br_idx == 1'b0) e.br0 = fld_new;
      else                   e.br1 = fld_new;
    end

    jfresh = ~e.jmp.valid;
    if (up.is_jmp) begin
      e.jmp.valid   = 1'b1;
      e.jmp.pos     = jfresh ? up.pos : e.jmp.pos;
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
  logic [UBTB_IDX_BITS-1:0] p_idx;
  logic [UBTB_TAG_BITS-1:0] p_tag;
  logic [VA_WIDTH-1:0]      p_base;

  assign p_idx  = get_idx(pred_pc_p0);
  assign p_tag  = get_tag(pred_pc_p0);
  assign p_base = get_base(pred_pc_p0);

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
      blk_p1.pft_addr = recon_pft(p_ent.pft, p_ent.carry, p_base);

      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        // Slot 0 takes br0, slot 1 takes br1. A slot above 1 carries
        // no conditional field (NUM_PRED_SLOTS 3+ is undefined per
        // ubtb_interfaces.md 2).
        if      (s == 0) p_cfld = p_ent.br0;
        else if (s == 1) p_cfld = p_ent.br1;
        else             p_cfld = '0;

        if (p_cfld.valid) begin
          pred_p1[s].valid    = 1'b1;
          pred_p1[s].target   = recon_br(p_cfld.tgt, p_base);
          pred_p1[s].br_type  = COND;
          pred_p1[s].br_taken = p_cfld.conf[UBTB_CONF_WIDTH-1];
          pred_p1[s].pos      = p_cfld.pos;
          pred_p1[s].conf     = p_cfld.conf;
          pred_p1[s].carry    = p_ent.carry;
        end else if (p_ent.jmp.valid && !p_jmp_used) begin
          // Block-terminating jump: reported in the LOWEST slot that
          // carries no valid conditional field. br_taken and conf
          // are not meaningful for a jump and are driven 0.
          p_jmp_used          = 1'b1;
          pred_p1[s].valid    = 1'b1;
          pred_p1[s].target   = recon_jmp(p_ent.jmp.tgt, p_base);
          pred_p1[s].br_type  = jmp_br_type(p_ent.jmp);
          pred_p1[s].br_taken = 1'b0;
          pred_p1[s].pos      = p_ent.jmp.pos;
          pred_p1[s].conf     = '0;
          pred_p1[s].carry    = p_ent.carry;
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
