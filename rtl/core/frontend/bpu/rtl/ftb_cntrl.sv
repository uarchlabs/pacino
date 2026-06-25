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
//   - ftb_array : pure 1R1W DATA RAM (FTB_RAM_ENTRY_WIDTH = 107/way)
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
//   - target encode/reconstruct (displacement-from-block-start)
//   - fallthrough reduce/reconstruct (pftAddr + carry, no error check)
//   - carried-writeWay allocate/evict with tree-PLRU
//   - update field writes (target / always_taken / conf / pft)
//   - confidence training and direction-suppression
//
// 107-bit RAM entry layout (ftb_entry_t below, private to ftb_cntrl;
// section 8 order minus the relocated entry-valid):
//   tag(26)
//   br0{valid,pos,tgt,stat,always_taken,conf} = 1+3+13+2+1+3 = 23
//   br1{...}                                   =               23
//   jmp{valid,pos,tgt,stat,isCall,isRet,isJalr}= 1+3+21+2+3  = 30
//   pftAddr(4) + carry(1)                      =                5
//   total                                      =              107
// The entry-valid bit is NOT in this layout; it lives in ftb_plru.
//
// Read-port arbitration (assumption, documented in Results Capture):
// ftb_array/ftb_plru each expose ONE read port. Prediction uses it in
// p1. The update path needs the carried way's current entry to
// read-modify-write conf / always_taken / target / pft, and the set's
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
  output logic                          ftb_br0_taken_p2,
  output logic                          ftb_br0_always_taken_p2,
  output logic [FTB_CONF_WIDTH-1:0]     ftb_br0_conf_p2,
  output logic [VA_WIDTH-1:0]           ftb_br0_target_p2,

  output logic                          ftb_br1_valid_p2,
  output logic                          ftb_br1_taken_p2,
  output logic                          ftb_br1_always_taken_p2,
  output logic [FTB_CONF_WIDTH-1:0]     ftb_br1_conf_p2,
  output logic [VA_WIDTH-1:0]           ftb_br1_target_p2,

  output logic                          ftb_jmp_valid_p2,
  output logic [VA_WIDTH-1:0]           ftb_jmp_target_p2,
  output logic                          ftb_is_call_p2,
  output logic                          ftb_is_ret_p2,
  output logic                          ftb_is_jalr_p2,

  output logic [VA_WIDTH-1:0]           ftb_pft_addr_p2,

  // -- confidence suppression (2.4); bit0 br0, bit1 br1
  output logic [1:0]                    ftb_suppress_dir_p2,

  // -- global chicken bit for suppression (confidence section 5/10)
  input  logic                          chicken_bit_enable,

  // -- update port (2.5; post-execute, single port)
  input  logic                          ftb_upd_valid_u0,
  input  logic [VA_WIDTH-1:0]           ftb_upd_pc_u0,
  input  logic                          ftb_upd_hit_u0,
  input  logic [FTB_WAY_BITS-1:0]       ftb_upd_way_u0,
  input  logic                          ftb_upd_is_br_u0,
  input  logic                          ftb_upd_br_idx_u0,
  input  logic                          ftb_upd_taken_u0,
  input  logic [VA_WIDTH-1:0]           ftb_upd_target_u0,
  input  logic                          ftb_upd_ftb_dir_u0,
  input  logic                          ftb_upd_is_jmp_u0,
  input  logic [VA_WIDTH-1:0]           ftb_upd_jmp_target_u0,
  input  logic                          ftb_upd_is_call_u0,
  input  logic                          ftb_upd_is_ret_u0,
  input  logic                          ftb_upd_is_jalr_u0,
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
  // Private RAM entry layout (107 bits/way). Packed in declaration
  // order: first member is the MSB. The exact within-way bit order is
  // private to ftb_cntrl; the only external contract with ftb_array is
  // the way slice [w*FTB_RAM_ENTRY_WIDTH +: FTB_RAM_ENTRY_WIDTH].
  // ----------------------------------------------------------------
  typedef struct packed {
    logic                          valid;        // field valid
    logic [FTB_BR_POS_BITS-1:0]    pos;          // in-block position
    logic [FTB_BR_TGT_BITS-1:0]    tgt;          // target displacement
    logic [TAR_STAT_BITS-1:0]      stat;         // fit/ovf/udf
    logic                          always_taken; // 5.5 set/clear
    logic [FTB_CONF_WIDTH-1:0]     conf;         // saturating conf
  } ftb_cond_t;                                  // 1+3+13+2+1+3 = 23

  typedef struct packed {
    logic                          valid;        // field valid
    logic [FTB_BR_POS_BITS-1:0]    pos;          // in-block position
    logic [FTB_JMP_TGT_BITS-1:0]   tgt;          // jump displacement
    logic [TAR_STAT_BITS-1:0]      stat;         // fit/ovf/udf
    logic                          is_call;
    logic                          is_ret;
    logic                          is_jalr;
  } ftb_jmp_t;                                   // 1+3+21+2+1+1+1 = 30

  typedef struct packed {
    logic [FTB_TAG_BITS-1:0]       tag;          // 26
    ftb_cond_t                     br0;          // 23
    ftb_cond_t                     br1;          // 23
    ftb_jmp_t                      jmp;          // 30
    logic [PFTADDR_BITS-1:0]       pft;          // 4
    logic                          carry;        // 1
  } ftb_entry_t;                                 // total 107

  // ----------------------------------------------------------------
  // Functions (combinational helpers). Declared before first use.
  // ----------------------------------------------------------------

  // Reconstruct a full-VA conditional target from the stored
  // displacement and the block-start base. Sign-extend the
  // displacement; no error check on reconstruction (4.5).
  function automatic logic [VA_WIDTH-1:0] recon_br(
      input logic [FTB_BR_TGT_BITS-1:0] disp,
      input logic [VA_WIDTH-1:0]        base);
    recon_br = base
      + {{(VA_WIDTH-FTB_BR_TGT_BITS){disp[FTB_BR_TGT_BITS-1]}}, disp};
  endfunction

  // Reconstruct a full-VA jump target from the stored displacement.
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

  // Saturating confidence step (3-bit, 0..7). up -> increment.
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
  // entry, the update set index/tag/base, and the readback of the
  // carried way (for read-modify-write of conf / always_taken /
  // target / pft on a hit). No tag re-lookup (IC-FTB-10).
  // ----------------------------------------------------------------
  logic [FTB_IDX_BITS-1:0]  upd_set_idx;
  logic [FTB_TAG_BITS-1:0]  upd_tag;
  logic [VA_WIDTH-1:0]      upd_base;
  logic [VA_WIDTH-1:0]      upd_off;
  ftb_entry_t               upd_old;
  ftb_entry_t               upd_new;
  ftb_cond_t                fld_old;
  ftb_cond_t                fld_new;
  logic                     fresh;
  logic                     upd_active;

  assign upd_active = ftb_upd_valid_u0;

  always_comb begin
    upd_set_idx = ftb_upd_pc_u0[FTB_OFFSET_BITS +: FTB_IDX_BITS];
    upd_tag     = ftb_upd_pc_u0[FTB_OFFSET_BITS+FTB_IDX_BITS
                                  +: FTB_TAG_BITS];
    upd_base    = {ftb_upd_pc_u0[VA_WIDTH-1:FTB_OFFSET_BITS],
                   {FTB_OFFSET_BITS{1'b0}}};
    upd_off     = ftb_upd_pft_addr_u0 - upd_base;

    // Readback of the carried way (read-old-on-collision in ftb_array
    // gives the pre-write contents for the RMW).
    upd_old = ftb_entry_t'(
      array_rd_data[ftb_upd_way_u0*FTB_RAM_ENTRY_WIDTH
                      +: FTB_RAM_ENTRY_WIDTH]);

    // Base entry: keep the old entry on a hit (preserve untouched
    // fields), or a fresh zero entry on a miss-allocate (5.4).
    upd_new       = ftb_upd_hit_u0 ? upd_old : '0;
    upd_new.tag   = upd_tag;

    // Fallthrough reduce (5.5 / 8.1): pftAddr = end[FTB_OFFSET_BITS-1:2]
    // (the in-block instruction index, expanded granularity) zero-
    // extended to PFTADDR_BITS; carry = end crosses the block boundary
    // above block start. Rewritten on every update; rewriting an
    // unchanged boundary stores the same value (harmless).
    upd_new.pft   =
      {{(PFTADDR_BITS-(FTB_OFFSET_BITS-INST_OFFSET)){1'b0}},
       upd_off[FTB_OFFSET_BITS-1:INST_OFFSET]};
    upd_new.carry = |upd_off[VA_WIDTH-1:FTB_OFFSET_BITS];

    // Conditional field RMW. A hit with the field already valid trains
    // (conf inc/dec, always_taken clear-on-not-taken). A hit with the
    // field free, or a miss-allocate, fills fresh (conf = INIT,
    // always_taken = resolved direction).
    fld_old = (ftb_upd_br_idx_u0 == 1'b0) ? upd_old.br0 : upd_old.br1;
    fresh   = ~ftb_upd_hit_u0 | ~fld_old.valid;

    fld_new.valid        = 1'b1;
    fld_new.pos          = '0;  // no in-block position on the upd port
    fld_new.tgt          = enc_br_disp(ftb_upd_target_u0, upd_base);
    fld_new.stat         = br_stat(ftb_upd_target_u0, upd_base);
    fld_new.always_taken = fresh ? ftb_upd_taken_u0
                         : (ftb_upd_taken_u0 ? fld_old.always_taken
                                             : 1'b0);
    fld_new.conf         = fresh ? FTB_CONF_INIT
                         : conf_step(fld_old.conf,
                             ftb_upd_ftb_dir_u0 == ftb_upd_taken_u0);

    if (ftb_upd_is_br_u0) begin
      if (ftb_upd_br_idx_u0 == 1'b0) upd_new.br0 = fld_new;
      else                            upd_new.br1 = fld_new;
    end

    // Jump field. Target rewritten unconditionally on every jump
    // resolve (5.5, IC-FTB-01); type bits from the resolved jump.
    if (ftb_upd_is_jmp_u0) begin
      upd_new.jmp.valid   = 1'b1;
      upd_new.jmp.pos     = '0;
      upd_new.jmp.tgt     = enc_jmp_disp(ftb_upd_jmp_target_u0, upd_base);
      upd_new.jmp.stat    = jmp_stat(ftb_upd_jmp_target_u0, upd_base);
      upd_new.jmp.is_call = ftb_upd_is_call_u0;
      upd_new.jmp.is_ret  = ftb_upd_is_ret_u0;
      upd_new.jmp.is_jalr = ftb_upd_is_jalr_u0;
    end
  end

  // ----------------------------------------------------------------
  // Shared read-port arbitration. Update borrows both read ports when
  // active (priority); otherwise prediction (p1) owns them.
  // ----------------------------------------------------------------
  logic [FTB_IDX_BITS-1:0] pred_set_idx_p1;
  logic [FTB_TAG_BITS-1:0] pred_tag_p1;
  logic [VA_WIDTH-1:0]     base_p1;

  assign pred_set_idx_p1 = pc_p1[FTB_OFFSET_BITS +: FTB_IDX_BITS];
  assign pred_tag_p1     = pc_p1[FTB_OFFSET_BITS+FTB_IDX_BITS
                                   +: FTB_TAG_BITS];
  assign base_p1         = {pc_p1[VA_WIDTH-1:FTB_OFFSET_BITS],
                            {FTB_OFFSET_BITS{1'b0}}};

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

  // p1 -> p2 next values
  logic                      n_valid_p2;
  logic                      n_hit_p2;
  logic [FTB_WAY_BITS-1:0]   n_way_p2;
  logic                      n_br0_valid, n_br0_taken, n_br0_at;
  logic [FTB_CONF_WIDTH-1:0] n_br0_conf;
  logic [VA_WIDTH-1:0]       n_br0_tgt;
  logic                      n_br1_valid, n_br1_taken, n_br1_at;
  logic [FTB_CONF_WIDTH-1:0] n_br1_conf;
  logic [VA_WIDTH-1:0]       n_br1_tgt;
  logic                      n_jmp_valid, n_is_call, n_is_ret, n_is_jalr;
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
    // Full 26-bit tag -> at most one way hits (no aliasing).
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

    // br0 / br1. FTB basic direction model: a present (valid)
    // conditional field is predicted taken (BTB presence semantics);
    // always_taken is the stronger bypass hint and conf measures how
    // reliably that taken prediction holds.
    n_br0_valid = n_valid_p2 & sel_entry.br0.valid;
    n_br0_taken = n_br0_valid;
    n_br0_at    = n_br0_valid & sel_entry.br0.always_taken;
    n_br0_conf  = sel_entry.br0.conf;
    n_br0_tgt   = recon_br(sel_entry.br0.tgt, base_p1);

    n_br1_valid = n_valid_p2 & sel_entry.br1.valid;
    n_br1_taken = n_br1_valid;
    n_br1_at    = n_br1_valid & sel_entry.br1.always_taken;
    n_br1_conf  = sel_entry.br1.conf;
    n_br1_tgt   = recon_br(sel_entry.br1.tgt, base_p1);

    // jump field + branch-type classification (3-way JALR split).
    n_jmp_valid = n_valid_p2 & sel_entry.jmp.valid;
    n_jmp_tgt   = recon_jmp(sel_entry.jmp.tgt, base_p1);
    n_is_call   = n_jmp_valid & sel_entry.jmp.is_call;
    n_is_ret    = n_jmp_valid & sel_entry.jmp.is_ret;
    n_is_jalr   = n_jmp_valid & sel_entry.jmp.is_jalr;

    // Fallthrough reconstruct (unconditional, no error check; 4.5).
    n_pft = base_p1
      + ({{(VA_WIDTH-PFTADDR_BITS){1'b0}}, sel_entry.pft} << INST_OFFSET)
      + (sel_entry.carry ? VA_WIDTH'(FTB_BLOCK_BYTES) : VA_WIDTH'(0));
  end

  // ----------------------------------------------------------------
  // p1 -> p2 output registers
  // ----------------------------------------------------------------
  logic                      q_valid_p2, q_hit_p2;
  logic [FTB_WAY_BITS-1:0]   q_way_p2;
  logic                      q_br0_valid, q_br0_taken, q_br0_at;
  logic [FTB_CONF_WIDTH-1:0] q_br0_conf;
  logic [VA_WIDTH-1:0]       q_br0_tgt;
  logic                      q_br1_valid, q_br1_taken, q_br1_at;
  logic [FTB_CONF_WIDTH-1:0] q_br1_conf;
  logic [VA_WIDTH-1:0]       q_br1_tgt;
  logic                      q_jmp_valid, q_is_call, q_is_ret, q_is_jalr;
  logic [VA_WIDTH-1:0]       q_jmp_tgt;
  logic [VA_WIDTH-1:0]       q_pft;

  always_ff @(posedge clk) begin
    if (!rstn) begin
      q_valid_p2  <= 1'b0;
      q_hit_p2    <= 1'b0;
      q_way_p2    <= '0;
      q_br0_valid <= 1'b0;
      q_br0_taken <= 1'b0;
      q_br0_at    <= 1'b0;
      q_br0_conf  <= '0;
      q_br0_tgt   <= '0;
      q_br1_valid <= 1'b0;
      q_br1_taken <= 1'b0;
      q_br1_at    <= 1'b0;
      q_br1_conf  <= '0;
      q_br1_tgt   <= '0;
      q_jmp_valid <= 1'b0;
      q_jmp_tgt   <= '0;
      q_is_call   <= 1'b0;
      q_is_ret    <= 1'b0;
      q_is_jalr   <= 1'b0;
      q_pft       <= '0;
    end else begin
      q_valid_p2  <= n_valid_p2;
      q_hit_p2    <= n_hit_p2;
      q_way_p2    <= n_way_p2;
      q_br0_valid <= n_br0_valid;
      q_br0_taken <= n_br0_taken;
      q_br0_at    <= n_br0_at;
      q_br0_conf  <= n_br0_conf;
      q_br0_tgt   <= n_br0_tgt;
      q_br1_valid <= n_br1_valid;
      q_br1_taken <= n_br1_taken;
      q_br1_at    <= n_br1_at;
      q_br1_conf  <= n_br1_conf;
      q_br1_tgt   <= n_br1_tgt;
      q_jmp_valid <= n_jmp_valid;
      q_jmp_tgt   <= n_jmp_tgt;
      q_is_call   <= n_is_call;
      q_is_ret    <= n_is_ret;
      q_is_jalr   <= n_is_jalr;
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
  assign ftb_br0_taken_p2        = q_br0_taken & flush_clr;
  assign ftb_br0_always_taken_p2 = q_br0_at    & flush_clr;
  assign ftb_br0_conf_p2         = q_br0_conf;
  assign ftb_br0_target_p2       = q_br0_tgt;

  assign ftb_br1_valid_p2        = q_br1_valid & flush_clr;
  assign ftb_br1_taken_p2        = q_br1_taken & flush_clr;
  assign ftb_br1_always_taken_p2 = q_br1_at    & flush_clr;
  assign ftb_br1_conf_p2         = q_br1_conf;
  assign ftb_br1_target_p2       = q_br1_tgt;

  assign ftb_jmp_valid_p2        = q_jmp_valid & flush_clr;
  assign ftb_jmp_target_p2       = q_jmp_tgt;
  assign ftb_is_call_p2          = q_is_call & flush_clr;
  assign ftb_is_ret_p2           = q_is_ret  & flush_clr;
  assign ftb_is_jalr_p2          = q_is_jalr & flush_clr;

  assign ftb_pft_addr_p2         = q_pft;

  // Confidence direction suppression (confidence section 4/5,
  // IC-FTB-02). Per branch: valid, field present, not always_taken,
  // conf at/above threshold, chicken bit enabled. Not asserted under
  // flush.
  assign ftb_suppress_dir_p2[0] =
      q_valid_p2 & q_br0_valid & ~q_br0_at
    & (q_br0_conf >= FTB_CONF_WIDTH'(FTB_CONF_SUPPRESS_THRESH))
    & chicken_bit_enable & flush_clr;
  assign ftb_suppress_dir_p2[1] =
      q_valid_p2 & q_br1_valid & ~q_br1_at
    & (q_br1_conf >= FTB_CONF_WIDTH'(FTB_CONF_SUPPRESS_THRESH))
    & chicken_bit_enable & flush_clr;

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
  assign plru_val_we_n = ~(ftb_upd_valid_u0 & ~ftb_upd_hit_u0);
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
  // Invariant assertion (IC-FTB-06 / confidence section 6): a fresh
  // entry must start below the suppression threshold.
  // ----------------------------------------------------------------
  initial begin
    if (FTB_CONF_INIT >= FTB_CONF_WIDTH'(FTB_CONF_SUPPRESS_THRESH))
      $error("FTB_CONF_INIT must be < FTB_CONF_SUPPRESS_THRESH");
  end

endmodule : ftb_cntrl

`endif // FTB_CNTRL_SV
