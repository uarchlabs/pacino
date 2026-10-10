// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Concurrent SVA for ptw (BP-123, BP-124). ptw_mem_interfaces.md WM-1
// to WM-8; itlb_l2tlb_interfaces.md IL-3d, IL-4, IL-6, IL-11b;
// mmu_decisions.md MMU-7, MMU-8c, MMU-10d, MMU-12a, MMU-24c, MMU-29.
//
// BOUND BY MODULE NAME (TD#109). Every input is a ptw port, except the
// four walker registers W11 reads (BP-124): the level of each stage's
// PTE, where the memory response goes (which stage a CAS updates) and
// the G-stage access type. They name WHICH leaf a CAS updates; the
// checks W11 makes on that leaf are its own, evaluated on the CAS's
// compare value. No hierarchical reference.
//
// Each property compares a port against something this file derives
// itself: the walks and memory accesses it has seen taken and not yet
// answered, the request held from an earlier cycle, the V bit and
// access type of the request being walked, or an independent instance
// of the PMP / PMA checker evaluated on the presented address. None
// restates the RTL that drives the checked signal.
//
//   W1  a_mem_aligned    every presented access is 8-byte aligned
//                        (WM-1)
//   W2  a_mem_stable     a presented access not yet accepted is
//                        presented again, unchanged, the next cycle
//                        (WM-2)
//   W3  a_mem_one        no access is presented while one is
//                        outstanding (WM-3)
//   W4  a_mem_checked    no presented access fails PMP at privilege S
//                        for its type, or names memory that is not
//                        cacheable and coherent (WM-8, MMU-10d,
//                        MMU-12a): a second checker instance here
//                        evaluates the presented address
//   W5  a_rsp_one        no client response without a request taken
//                        and not yet answered (IL-4, IL-6)
//   W6  a_hit_has_a      a hit's perm has A set, and D set for a store
//                        (MMU-7, MMU-8: Svade faults, Svadu updates
//                        before it answers)
//   W7  a_guest_needs_v  cause 20 only for a V=1 request (MMU-22)
//   W8  a_imp_legal      gpa_imp is never 2'b11 on a guest-page fault
//                        (MMU-29)
//   W9  a_cas_sets_ad    a CAS's swap value is its compare value with
//                        A set and no other bit cleared (MMU-8)
//   W10 a_retry_busy     a retry answers a request taken while another
//                        walk was in progress (IL-6)
//   W11 a_cas_permitted  no CAS that sets A or D is presented for a
//                        leaf that fails any check MMU-8c names: the
//                        reserved encodings (V, W without R, bits
//                        60:54, PBMT 3 or PBMTE clear, N), the
//                        misaligned superpage, the access type, and U
//                        (at a single or VS stage against the request's
//                        privilege; at the G-stage, set). This file
//                        evaluates them on the compare value (BP-124)
//   W12 a_priv_legal     no request is accepted with itlb_l2t_priv
//                        2'b10 (reserved) or 2'b11 (M) (IL-3d,
//                        MMU-24c; BP-124)
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ptw_assert #(
  parameter int PMP_ENTRIES  = 16,
  parameter int PMP_GRAN_LG2 = 12,
  parameter int PMA_REGIONS  = 1,
  parameter logic [PMA_REGIONS-1:0][PA_WIDTH-1:0]  PMA_BASE =
    {36'h0_8000_0000},
  parameter logic [PMA_REGIONS-1:0][PA_WIDTH-1:0]  PMA_TOP  =
    {36'hF_FFFF_FFFF},
  parameter logic [PMA_REGIONS-1:0][PMA_WIDTH-1:0] PMA_ATTR = {4'b1111},
  parameter logic [PMA_WIDTH-1:0]                  PMA_DFLT = 4'b0000
) (
  input logic                    clk,
  input logic                    rstn,
  input logic                    itlb_l2t_req_val,
  input logic                    itlb_l2t_req_rdy,
  input logic                    itlb_l2t_v,
  input logic [1:0]              itlb_l2t_acc,
  input logic [1:0]              itlb_l2t_priv,
  input logic [1:0]              itlb_l2t_tag,
  input logic                    l2t_itlb_rsp_val,
  input logic [1:0]              l2t_itlb_tag,
  input logic [1:0]              l2t_itlb_status,
  input logic [PERM_WIDTH-1:0]   l2t_itlb_perm,
  input logic [CAUSE_WIDTH-1:0]  l2t_itlb_cause,
  input logic [1:0]              l2t_itlb_gpa_imp,
  input logic                    ptw_mem_req_val,
  input logic                    ptw_mem_req_rdy,
  input logic                    ptw_mem_req_op,
  input logic [PA_WIDTH-1:0]     ptw_mem_req_paddr,
  input logic [63:0]             ptw_mem_req_cmp,
  input logic [63:0]             ptw_mem_req_swap,
  input logic                    mem_ptw_rsp_val,
  input logic                    csr_ptw_menvcfg_pbmte,
  input logic                    csr_ptw_henvcfg_pbmte,
  // W11: which leaf a CAS updates (see the header)
  input logic [1:0]              w_s_lvl,
  input logic [1:0]              w_g_lvl,
  input logic [1:0]              w_m_ret,
  input logic [1:0]              w_g_acc,
  input logic [((PMP_ENTRIES > 0) ? PMP_ENTRIES : 1)-1:0][7:0]
                                 csr_ptw_pmpcfg,
  input logic [((PMP_ENTRIES > 0) ? PMP_ENTRIES : 1)-1:0][PA_WIDTH-3:0]
                                 csr_ptw_pmpaddr
);

  localparam logic [1:0] ST_HIT   = 2'b00;
  localparam logic [1:0] ST_RETRY = 2'b10;
  localparam logic [1:0] ACC_R    = 2'd0;
  localparam logic [1:0] ACC_W    = 2'd1;
  localparam logic [1:0] ACC_X    = 2'd2;
  localparam logic [1:0] PRV_U    = 2'd0;
  localparam logic [1:0] MR_SCAS  = 2'd2;   // the walker's mret_e
  localparam logic [1:0] MR_GCAS  = 2'd3;
  localparam int P_V = 0;
  localparam int P_R = 1;
  localparam int P_W = 2;
  localparam int P_X = 3;
  localparam int P_U = 4;
  localparam int P_A = 6;
  localparam int P_D = 7;
  localparam int P_N = 63;

  // W11. Does leaf PTE p, at level lvl, fail a check the translation
  // algorithm makes before the A/D update (MMU-8c)? g is the G-stage
  // (U must be set, every access a user one, MMU-26); otherwise U is
  // checked against priv (U needs U set, S needs it clear).
  function automatic logic leaf_bad(input logic [63:0] p,
                                    input logic [1:0]  lvl,
                                    input logic        g,
                                    input logic [1:0]  acc,
                                    input logic [1:0]  priv,
                                    input logic        pbmte);
    logic bad;
    bad = !p[P_V] || (!p[P_R] && p[P_W]) || (p[60:54] != '0) ||
          !(p[P_R] || p[P_X]);
    bad = bad || (p[62:61] == 2'd3) || (!pbmte && (p[62:61] != 2'd0));
    bad = bad || (p[P_N] && ((lvl != 2'd0) || (p[13:10] != 4'b1000)));
    bad = bad || ((lvl == 2'd2) && (p[27:10] != '0)) ||
                 ((lvl == 2'd1) && (p[18:10] != '0));
    bad = bad || ((acc == ACC_X) && !p[P_X]) ||
                 ((acc == ACC_R) && !p[P_R]) ||
                 ((acc == ACC_W) && !p[P_W]);
    if (g) bad = bad || !p[P_U];
    else   bad = bad || ((priv == PRV_U) ? !p[P_U] : p[P_U]);
    return bad;
  endfunction

  // ---- the walk in progress, from the client port ----------------------
  logic       r_busy;       // a walk was taken and is not answered
  logic       r_v;
  logic [1:0] r_acc;
  logic [1:0] r_priv;
  logic       r_s_pbmte;    // PBMTE of the single / VS stage, at take
  logic       r_g_pbmte;
  logic [1:0] r_tag;
  logic       r_rty;        // a request taken while busy, unanswered
  logic [1:0] r_rty_tag;

  // ---- the memory port ---------------------------------------------------
  logic       r_mout;       // an access accepted, not yet answered
  logic       r_mwait;      // presented last cycle, not accepted
  logic       r_mop;
  logic [PA_WIDTH-1:0] r_mpa;
  logic [63:0] r_mcmp;
  logic [63:0] r_mswap;

  // ---- W4: an independent evaluation of the presented address ----------
  logic                 w_pmp_ok;
  logic [PMA_WIDTH-1:0] w_pma;
  logic                 w_fault;

  pmp_pma_chk #(
    .PMP_ENTRIES  (PMP_ENTRIES),
    .PMP_GRAN_LG2 (PMP_GRAN_LG2),
    .PMA_REGIONS  (PMA_REGIONS),
    .PMA_BASE     (PMA_BASE),
    .PMA_TOP      (PMA_TOP),
    .PMA_ATTR     (PMA_ATTR),
    .PMA_DFLT     (PMA_DFLT)
  ) u_ref_chk (
    .chk_pa     (ptw_mem_req_paddr),
    .chk_acc    (ptw_mem_req_op ? 2'd1 : 2'd0),
    .chk_priv   (2'd1),
    .chk_pbmt   (2'd0),
    .pmp_cfg    (csr_ptw_pmpcfg),
    .pmp_addr   (csr_ptw_pmpaddr),
    .chk_pmp_ok (w_pmp_ok),
    .chk_pma    (w_pma),
    .chk_fault  (w_fault)
  );

  wire w_take  = itlb_l2t_req_val && itlb_l2t_req_rdy;
  wire w_macc  = ptw_mem_req_val && ptw_mem_req_rdy;
  // The response names the walk unless it answers the held retry.
  wire w_rsp_walk = l2t_itlb_rsp_val && (l2t_itlb_status != ST_RETRY);

  always_ff @(posedge clk or negedge rstn) begin : track
    if (!rstn) begin
      r_busy    <= 1'b0;
      r_v       <= 1'b0;
      r_acc     <= '0;
      r_priv    <= '0;
      r_s_pbmte <= 1'b0;
      r_g_pbmte <= 1'b0;
      r_tag     <= '0;
      r_rty     <= 1'b0;
      r_rty_tag <= '0;
      r_mout    <= 1'b0;
      r_mwait   <= 1'b0;
      r_mop     <= 1'b0;
      r_mpa     <= '0;
      r_mcmp    <= '0;
      r_mswap   <= '0;
    end else begin
      if (w_rsp_walk) r_busy <= 1'b0;
      if (l2t_itlb_rsp_val && (l2t_itlb_status == ST_RETRY)) r_rty <= 1'b0;
      if (w_take) begin
        if (r_busy && !w_rsp_walk) begin
          r_rty     <= 1'b1;
          r_rty_tag <= itlb_l2t_tag;
        end else if (!r_busy || w_rsp_walk) begin
          if (!r_busy) begin
            r_busy <= 1'b1;
            r_v    <= itlb_l2t_v;
            r_acc  <= itlb_l2t_acc;
            r_priv <= itlb_l2t_priv;
            // MMU-U6: menvcfg for single-stage and the G-stage,
            // henvcfg for the VS-stage.
            r_s_pbmte <= itlb_l2t_v ? csr_ptw_henvcfg_pbmte
                                    : csr_ptw_menvcfg_pbmte;
            r_g_pbmte <= csr_ptw_menvcfg_pbmte;
            r_tag  <= itlb_l2t_tag;
          end else begin
            // taken in the cycle the walk is answered: still busy then
            r_rty     <= 1'b1;
            r_rty_tag <= itlb_l2t_tag;
          end
        end
      end
      if (mem_ptw_rsp_val) r_mout <= 1'b0;
      if (w_macc)          r_mout <= 1'b1;
      r_mwait <= ptw_mem_req_val && !ptw_mem_req_rdy;
      r_mop   <= ptw_mem_req_op;
      r_mpa   <= ptw_mem_req_paddr;
      r_mcmp  <= ptw_mem_req_cmp;
      r_mswap <= ptw_mem_req_swap;
    end
  end

  property p_mem_aligned;
    @(posedge clk) disable iff (!rstn)
      ptw_mem_req_val |-> (ptw_mem_req_paddr[2:0] == 3'b000);
  endproperty
  a_mem_aligned: assert property (p_mem_aligned)
    else $error("W1 walker access not 8-byte aligned");

  property p_mem_stable;
    @(posedge clk) disable iff (!rstn)
      r_mwait |-> (ptw_mem_req_val && (ptw_mem_req_op == r_mop) &&
                   (ptw_mem_req_paddr == r_mpa) &&
                   (ptw_mem_req_cmp == r_mcmp) &&
                   (ptw_mem_req_swap == r_mswap));
  endproperty
  a_mem_stable: assert property (p_mem_stable)
    else $error("W2 walker access changed or withdrawn before acceptance");

  property p_mem_one;
    @(posedge clk) disable iff (!rstn)
      r_mout |-> !ptw_mem_req_val;
  endproperty
  a_mem_one: assert property (p_mem_one)
    else $error("W3 walker access presented while one is outstanding");

  property p_mem_checked;
    @(posedge clk) disable iff (!rstn)
      ptw_mem_req_val |-> (w_pmp_ok && w_pma[0] && w_pma[1]);
  endproperty
  a_mem_checked: assert property (p_mem_checked)
    else $error("W4 walker presented an access that fails PMP or PMA");

  property p_rsp_one;
    @(posedge clk) disable iff (!rstn)
      l2t_itlb_rsp_val |->
        ((l2t_itlb_status == ST_RETRY) ? r_rty : r_busy);
  endproperty
  a_rsp_one: assert property (p_rsp_one)
    else $error("W5 walker response with no request outstanding");

  property p_hit_has_a;
    @(posedge clk) disable iff (!rstn)
      (w_rsp_walk && (l2t_itlb_status == ST_HIT)) |->
        (l2t_itlb_perm[P_A] && ((r_acc != ACC_W) || l2t_itlb_perm[P_D]));
  endproperty
  a_hit_has_a: assert property (p_hit_has_a)
    else $error("W6 walker hit without A (or D for a store)");

  property p_guest_needs_v;
    @(posedge clk) disable iff (!rstn)
      (w_rsp_walk && (l2t_itlb_cause == CAUSE_WIDTH'(20)) &&
       (l2t_itlb_status != ST_HIT)) |-> r_v;
  endproperty
  a_guest_needs_v: assert property (p_guest_needs_v)
    else $error("W7 guest-page fault for a V=0 walk");

  property p_imp_legal;
    @(posedge clk) disable iff (!rstn)
      (w_rsp_walk && (l2t_itlb_cause == CAUSE_WIDTH'(20)) &&
       (l2t_itlb_status != ST_HIT)) |-> (l2t_itlb_gpa_imp != 2'b11);
  endproperty
  a_imp_legal: assert property (p_imp_legal)
    else $error("W8 reserved implicit-access kind");

  property p_cas_sets_ad;
    @(posedge clk) disable iff (!rstn)
      (ptw_mem_req_val && ptw_mem_req_op) |->
        ptw_mem_req_swap[P_A]
        && ((ptw_mem_req_swap & ~(64'd1 << P_A) & ~(64'd1 << P_D)) ==
            (ptw_mem_req_cmp  & ~(64'd1 << P_A) & ~(64'd1 << P_D)))
        && ((ptw_mem_req_swap & ptw_mem_req_cmp) == ptw_mem_req_cmp)
        && (ptw_mem_req_swap != ptw_mem_req_cmp);
  endproperty
  a_cas_sets_ad: assert property (p_cas_sets_ad)
    else $error("W9 walker CAS does more than set A or D");

  property p_retry_busy;
    @(posedge clk) disable iff (!rstn)
      (l2t_itlb_rsp_val && (l2t_itlb_status == ST_RETRY)) |->
        (r_rty && (l2t_itlb_tag == r_rty_tag));
  endproperty
  a_retry_busy: assert property (p_retry_busy)
    else $error("W10 walker retry with no request taken while busy");

  // W11 (MMU-8c). A CAS updates the leaf it compares against: the
  // single / VS-stage leaf (MR_SCAS) at its level, against the request's
  // access type and privilege, or the G-stage leaf (MR_GCAS) at its
  // level, against the G-stage access type.
  property p_cas_permitted;
    @(posedge clk) disable iff (!rstn)
      (ptw_mem_req_val && ptw_mem_req_op) |->
        ((w_m_ret == MR_GCAS)
           ? !leaf_bad(ptw_mem_req_cmp, w_g_lvl, 1'b1, w_g_acc, r_priv,
                       r_g_pbmte)
           : ((w_m_ret == MR_SCAS) &&
              !leaf_bad(ptw_mem_req_cmp, w_s_lvl, 1'b0, r_acc, r_priv,
                        r_s_pbmte)));
  endproperty
  a_cas_permitted: assert property (p_cas_permitted)
    else $error("W11 walker CAS sets A or D on a leaf that fails a check");

  // W12 (IL-3d). Only U and S are presented; M-mode fetch is not
  // translated (MMU-19a).
  property p_priv_legal;
    @(posedge clk) disable iff (!rstn)
      w_take |-> (itlb_l2t_priv inside {2'b00, 2'b01});
  endproperty
  a_priv_legal: assert property (p_priv_legal)
    else $error("W12 walk request with a reserved or M privilege");

endmodule : ptw_assert

// Bind BY MODULE NAME.
bind ptw ptw_assert #(
  .PMP_ENTRIES  (PMP_ENTRIES),
  .PMP_GRAN_LG2 (PMP_GRAN_LG2),
  .PMA_REGIONS  (PMA_REGIONS),
  .PMA_BASE     (PMA_BASE),
  .PMA_TOP      (PMA_TOP),
  .PMA_ATTR     (PMA_ATTR),
  .PMA_DFLT     (PMA_DFLT)
) u_assert (
  .clk               (clk),
  .rstn              (rstn),
  .itlb_l2t_req_val  (itlb_l2t_req_val),
  .itlb_l2t_req_rdy  (itlb_l2t_req_rdy),
  .itlb_l2t_v        (itlb_l2t_v),
  .itlb_l2t_acc      (itlb_l2t_acc),
  .itlb_l2t_priv     (itlb_l2t_priv),
  .itlb_l2t_tag      (itlb_l2t_tag),
  .l2t_itlb_rsp_val  (l2t_itlb_rsp_val),
  .l2t_itlb_tag      (l2t_itlb_tag),
  .l2t_itlb_status   (l2t_itlb_status),
  .l2t_itlb_perm     (l2t_itlb_perm),
  .l2t_itlb_cause    (l2t_itlb_cause),
  .l2t_itlb_gpa_imp  (l2t_itlb_gpa_imp),
  .ptw_mem_req_val   (ptw_mem_req_val),
  .ptw_mem_req_rdy   (ptw_mem_req_rdy),
  .ptw_mem_req_op    (ptw_mem_req_op),
  .ptw_mem_req_paddr (ptw_mem_req_paddr),
  .ptw_mem_req_cmp   (ptw_mem_req_cmp),
  .ptw_mem_req_swap  (ptw_mem_req_swap),
  .mem_ptw_rsp_val   (mem_ptw_rsp_val),
  .csr_ptw_menvcfg_pbmte (csr_ptw_menvcfg_pbmte),
  .csr_ptw_henvcfg_pbmte (csr_ptw_henvcfg_pbmte),
  .w_s_lvl           (r_s_lvl),
  .w_g_lvl           (r_g_lvl),
  .w_m_ret           (r_m_ret),
  .w_g_acc           (r_g_acc),
  .csr_ptw_pmpcfg    (csr_ptw_pmpcfg),
  .csr_ptw_pmpaddr   (csr_ptw_pmpaddr)
);
