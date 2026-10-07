// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// L1 instruction TLB (BP-118). itlb_decisions.md ITLB-1 to ITLB-17;
// itlb_ifu_interfaces.md IT-1 to IT-16; itlb_l2tlb_interfaces.md
// IL-1 to IL-14; mmu_decisions.md MMU-10a, MMU-U6, MMU-U7.
//
// ARRAY. ITLB_ENTRIES (64, ITLB-1) fully associative entries
// (ITLB-2), one array for every page size (ITLB-3): 4 KiB, 64 KiB
// Svnapot, 2 MiB, 1 GiB. An entry is matched on its VPN with the
// bits its size covers masked out of the compare, VPN[3:0] for
// 64 KiB, [8:0] for 2 MiB, [17:0] for 1 GiB, and on a hit those bits
// of the output PPN are the request's VPN bits, not the stored ones.
// For 64 KiB that is the MMU-U7 substitution: the stored PPN[3:0] is
// the Svnapot size marker. For 2 MiB and 1 GiB the stored low bits
// are zero on a legal PTE and the substitution is the usual
// superpage offset.
//
// TAG (ITLB-4, ITLB-4a). An entry holds V, VMID, ASID and the PTE G
// bit. A hit needs V equal to the current V; for V=1 the VMID equal
// to hgatp.VMID; and G set or the ASID equal to the current one,
// satp.ASID for V=0 and vsatp.ASID for V=1. G applies within a VMID.
//
// THE VPN TAG IS VA_WIDTH-12 = 29 BITS, the width of ifu_itlb_vpn
// (IT-16), not VPN_WIDTH. With V=1, vsatp.MODE=Bare and hgatp in
// Sv39x4 the lookup address is a 41-bit guest physical address and
// all 29 bits are significant (FE-19). itlb_l2t_vpn is built at the
// same width for the same reason; itlb_l2tlb_interfaces.md 2 declares
// it [VPN_WIDTH-1:0], which drops GPA bits 40:39. Reported.
//
// REGIMES (fe_decisions.md FE-19, ITLB-17). Read from the CSR input
// group every cycle; the ITLB holds no CSR.
//   physical    M-mode, V=0 with satp.MODE Bare, or V=1 with vsatp
//               and hgatp both Bare. PPN = the request VPN. A VPN
//               with any bit set above PPN_WIDTH is outside the
//               implemented physical space and faults cause 1.
//   Sv39        V=0 with satp in Sv39, or V=1 with vsatp in Sv39.
//               Address bits 40:39 must equal bit 38, else cause 12
//               before any lookup.
//   G only      V=1, vsatp Bare, hgatp Sv39x4. Every 41-bit pattern
//               is legal; looked up, walked by the L2 TLB.
// M-mode fetch is never translated, whatever satp holds; FE-19 lists
// the Bare regimes and does not name M-mode. Reported.
//
// RESPONSE (ITLB-5, IT-4). One cycle: a request taken in cycle T is
// answered in T+1 from the registered request, the array and the
// current CSR group. Every request is answered. Status:
//   hit    a physical-regime access, or an array hit, that passes
//          the ITLB-16 permission check and the PMP and PMA check
//   miss   no entry. A walk is started if none for this VA and
//          identity is in flight (ITLB-10, IT-9) and a tracker slot
//          is free; otherwise nothing is started (ITLB-9, IT-8)
//   fault  cause 12 from the address check or ITLB-16; cause 1 from
//          the PMP / PMA check or a physical address out of range;
//          or the cause a walk returned (1, 12 or 20, IL-10)
// The reserved status is never driven.
//
// PMP AND PMA (MMU-10a, ITLB-12, IT-10, IT-12). One pmp_pma_chk
// instance beside the array checks the output PA of every hit and
// every physical-regime access, at the current privilege, with the
// entry's PBMT. Its effective attributes are itlb_ifu_pma on a hit.
// A PMP denial or a non-executable region is a FAULT on this port,
// cause 1, since the port has no other way to carry it: ifu_xlate.sv
// treats status hit as no fault whatever itlb_ifu_pma holds, and
// MMU-10b has the ITLB-side instance drive itlb_ifu_cause. IT-12's
// "the checks do not gate this response" is about timing: the check
// is inside the one-cycle response. Reported. The PMP grain must be
// at least one page, so a check on the page base answers for every
// fetch in the page; an elaboration check enforces it.
//
// PERMISSIONS (ITLB-16). On every hit, against the CURRENT privilege:
// X clear faults; in U-mode (VU for a V=1 entry) U clear faults; in
// S-mode (VS) U set faults. SUM and MXR do not apply to fetch. The A
// bit is the walker's (Svade faults it, Svadu sets it, MMU-7), and
// G-stage permissions are the walker's too (MMU-26).
//
// WALK TRACKER (ITLB-8, ITLB-10, ITLB-15). WALK_DEPTH slots, default
// 1, at most 4 by the two-bit tag of IL-1; the slot number is the
// tag. A slot is
//   FREE
//   REQ    allocated, the L2 TLB request not yet taken
//   OUT    taken, the response outstanding
//   FLT    the walk returned a fault, held until the matching
//          re-request collects it. A walk's fault must reach the IFU
//          and the IFU only re-requests (IT-7, IT-8), so the fault is
//          answered on the re-request. A FLT slot is also free for a
//          new miss to take, so a fault nobody re-requests (its block
//          was flushed, IFU-31) cannot hold the tracker.
// L2 responses (IL-4): hit installs and frees; fault goes to FLT;
// retry goes back to REQ and is asked again (IL-6). A reserved
// status is taken as a fault with cause 1, and a fault whose cause
// is not 1, 12 or 20 is passed on as cause 1: the IT-4 rule, applied
// on this side.
//
// INVALIDATE (ITLB-13, ITLB-13a, ITLB-13b, ITLB-14). One cycle, no
// ready. Op field, rs1/rs2 nonzero flags, the address page and the
// ASID and VMID:
//   OP_VMA   SFENCE.VMA, SINVAL.VMA. V=0 entries. rs1 selects by
//            address, rs2 by ASID; global entries are excluded only
//            when rs2 is nonzero.
//   OP_VVMA  HFENCE.VVMA, HINVAL.VVMA. The same four forms over V=1
//            entries of the named VMID; global is per VMID.
//   OP_GVMA  HFENCE.GVMA, HINVAL.GVMA. V=1 entries; rs2 selects the
//            VMID. No global case. The address is NOT matched: an
//            entry holds the final PA of a two-stage translation and
//            not the guest physical address it went through, so every
//            V=1 entry of the VMID goes. Invalidating more than asked
//            is always legal.
//   2'b11    reserved, invalidates everything.
// An SFENCE.VMA executed in VS-mode is presented as OP_VVMA with the
// current VMID; SFENCE.W.INVAL and SFENCE.INVAL.IR are not presented.
// Every invalidate also releases every tracker slot: REQ and FLT
// slots free at once, OUT slots are marked killed, and a killed
// walk's response, or one returning in the invalidate cycle, frees
// its slot and installs nothing (IL-13, IL-14). A killed walk does not
// count as in flight for ITLB-10.
//
// REPLACEMENT (ITLB-6). An invalid entry if there is one; otherwise a
// rotating victim that skips the most recently used entry.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module itlb #(
  parameter int ITLB_ENTRIES = 64,                      // ITLB-1
  parameter int WALK_DEPTH   = 1,                       // ITLB-15
  parameter int PMP_ENTRIES  = 16,                      // MMU-11
  parameter int PMP_GRAN_LG2 = 12,
  parameter int PMA_REGIONS  = 1,                       // MMU-15a
  parameter logic [PMA_REGIONS-1:0][PA_WIDTH-1:0]  PMA_BASE =
    {36'h0_8000_0000},
  parameter logic [PMA_REGIONS-1:0][PA_WIDTH-1:0]  PMA_TOP  =
    {36'hF_FFFF_FFFF},
  parameter logic [PMA_REGIONS-1:0][PMA_WIDTH-1:0] PMA_ATTR = {4'b1111},
  parameter logic [PMA_WIDTH-1:0]                  PMA_DFLT = 4'b0000
) (
  input  logic                     clk,
  input  logic                     rstn,

  // ---- itlb_ifu_interfaces.md 2 ------------------------------------
  input  logic                     ifu_itlb_req_val,
  output logic                     ifu_itlb_req_rdy,
  input  logic [VA_WIDTH-13:0]     ifu_itlb_vpn,     // IT-16
  input  logic                     ifu_itlb_tag,
  output logic                     itlb_ifu_rsp_val,
  output logic                     itlb_ifu_tag,
  output logic [1:0]               itlb_ifu_status,
  output logic [PPN_WIDTH-1:0]     itlb_ifu_ppn,
  output logic [CAUSE_WIDTH-1:0]   itlb_ifu_cause,
  output logic [GPA_WIDTH-1:0]     itlb_ifu_gpa,
  output logic [PMA_WIDTH-1:0]     itlb_ifu_pma,

  // ---- itlb_l2tlb_interfaces.md 2 ----------------------------------
  output logic                     itlb_l2t_req_val,
  input  logic                     itlb_l2t_req_rdy,
  output logic [VA_WIDTH-13:0]     itlb_l2t_vpn,     // see header
  output logic [ASID_WIDTH-1:0]    itlb_l2t_asid,
  output logic [VMID_WIDTH-1:0]    itlb_l2t_vmid,
  output logic                     itlb_l2t_v,
  output logic [1:0]               itlb_l2t_tag,
  input  logic                     l2t_itlb_rsp_val,
  input  logic [1:0]               l2t_itlb_tag,
  input  logic [1:0]               l2t_itlb_status,
  input  logic [PPN_WIDTH-1:0]     l2t_itlb_ppn,
  input  logic [1:0]               l2t_itlb_size,    // IL-7
  input  logic [PERM_WIDTH-1:0]    l2t_itlb_perm,
  input  logic [1:0]               l2t_itlb_pbmt,
  input  logic [CAUSE_WIDTH-1:0]   l2t_itlb_cause,
  input  logic [GPA_WIDTH-1:0]     l2t_itlb_gpa,

  // ---- CSR input group, ITLB-17, MMU-11a, fe_decisions.md FE-20 ----
  input  logic                     csr_itlb_v,
  input  logic [1:0]               csr_itlb_priv,     // 0 U, 1 S, 3 M
  input  logic [3:0]               csr_itlb_satp_mode,
  input  logic [ASID_WIDTH-1:0]    csr_itlb_satp_asid,
  input  logic [3:0]               csr_itlb_vsatp_mode,
  input  logic [ASID_WIDTH-1:0]    csr_itlb_vsatp_asid,
  input  logic [3:0]               csr_itlb_hgatp_mode,
  input  logic [VMID_WIDTH-1:0]    csr_itlb_hgatp_vmid,
  input  logic [((PMP_ENTRIES > 0) ? PMP_ENTRIES : 1)-1:0][7:0]
                                   csr_itlb_pmpcfg,
  input  logic [((PMP_ENTRIES > 0) ? PMP_ENTRIES : 1)-1:0][PA_WIDTH-3:0]
                                   csr_itlb_pmpaddr,

  // ---- invalidate port, ITLB-14 ------------------------------------
  input  logic                     bkend_itlb_inv_val,
  input  logic [1:0]               bkend_itlb_inv_op,
  input  logic                     bkend_itlb_inv_rs1_nz,
  input  logic                     bkend_itlb_inv_rs2_nz,
  input  logic [VA_WIDTH-13:0]     bkend_itlb_inv_vpn,
  input  logic [ASID_WIDTH-1:0]    bkend_itlb_inv_asid,
  input  logic [VMID_WIDTH-1:0]    bkend_itlb_inv_vmid
);

  // -----------------------------------------------------------------
  // Constants.
  // -----------------------------------------------------------------
  localparam int VW     = VA_WIDTH - 12;                  // 29
  localparam int EI     = (ITLB_ENTRIES > 1) ? $clog2(ITLB_ENTRIES) : 1;
  localparam int TI     = 2;                              // IL-1

  // itlb_ifu_status, IT-4.
  localparam logic [1:0] ST_HIT   = 2'b00;
  localparam logic [1:0] ST_MISS  = 2'b01;
  localparam logic [1:0] ST_FAULT = 2'b10;

  // l2t_itlb_status, IL-4.
  localparam logic [1:0] L2_HIT   = 2'b00;
  localparam logic [1:0] L2_FAULT = 2'b01;
  localparam logic [1:0] L2_RETRY = 2'b10;

  // l2t_itlb_size, IL-7 (proposed encoding).
  localparam logic [1:0] SZ_4K  = 2'b00;
  localparam logic [1:0] SZ_64K = 2'b01;
  localparam logic [1:0] SZ_2M  = 2'b10;

  // Exception codes, IT-6.
  localparam logic [CAUSE_WIDTH-1:0] CAUSE_ACCESS = CAUSE_WIDTH'(1);
  localparam logic [CAUSE_WIDTH-1:0] CAUSE_PAGE   = CAUSE_WIDTH'(12);
  localparam logic [CAUSE_WIDTH-1:0] CAUSE_GUEST  = CAUSE_WIDTH'(20);

  localparam logic [1:0] PRV_U = 2'd0;
  localparam logic [1:0] PRV_S = 2'd1;
  localparam logic [1:0] PRV_M = 2'd3;
  localparam logic [3:0] MODE_BARE = 4'd0;

  // PTE permission byte, IL-8: V R W X U G A D.
  localparam int P_X = 3;
  localparam int P_U = 4;
  localparam int P_G = 5;

  // Invalidate operations, ITLB-14.
  localparam logic [1:0] OP_VMA  = 2'd0;
  localparam logic [1:0] OP_VVMA = 2'd1;
  localparam logic [1:0] OP_GVMA = 2'd2;

  // Tracker states.
  localparam logic [1:0] T_FREE = 2'd0;
  localparam logic [1:0] T_REQ  = 2'd1;
  localparam logic [1:0] T_OUT  = 2'd2;
  localparam logic [1:0] T_FLT  = 2'd3;

  localparam int PA_HI = PA_WIDTH - 12;   // = PPN_WIDTH

  initial begin
    if (WALK_DEPTH < 1 || WALK_DEPTH > 4)
      $error("itlb: WALK_DEPTH must be 1 to 4 (IL-1 two-bit tag)");
    if (PMP_GRAN_LG2 < 12)
      $error("itlb: PMP grain below one page; a page check is inexact");
  end

  typedef struct packed {
    logic                  val;
    logic                  v;
    logic                  g;
    logic [ASID_WIDTH-1:0] asid;
    logic [VMID_WIDTH-1:0] vmid;
    logic [VW-1:0]         vpn;
    logic [1:0]            size;
    logic [PPN_WIDTH-1:0]  ppn;
    logic [PERM_WIDTH-1:0] perm;
    logic [1:0]            pbmt;
  } itlb_ent_t;

  typedef struct packed {
    logic [1:0]             st;
    logic                   kill;
    logic                   v;
    logic [ASID_WIDTH-1:0]  asid;
    logic [VMID_WIDTH-1:0]  vmid;
    logic [VW-1:0]          vpn;
    logic [CAUSE_WIDTH-1:0] cause;
    logic [GPA_WIDTH-1:0]   gpa;
  } trk_t;

  // The VPN bits a page size leaves out of the compare.
  function automatic logic [VW-1:0] size_mask(input logic [1:0] sz);
    case (sz)
      SZ_4K:   return VW'(0);
      SZ_64K:  return VW'(18'h0000F);
      SZ_2M:   return VW'(18'h001FF);
      default: return VW'(18'h3FFFF);
    endcase
  endfunction

  function automatic logic covers(input itlb_ent_t e,
                                  input logic [VW-1:0] vpn);
    return ((e.vpn ^ vpn) & ~size_mask(e.size)) == '0;
  endfunction

  // -----------------------------------------------------------------
  // State.
  // -----------------------------------------------------------------
  itlb_ent_t            r_ent [0:ITLB_ENTRIES-1];
  // Declared over the whole two-bit tag space of IL-1 so a tag always
  // indexes it; slots at or above WALK_DEPTH stay FREE.
  trk_t                 r_trk [0:3];
  logic [EI-1:0]        r_mru;
  logic [EI-1:0]        r_vict;

  logic                 r_rq_val;
  logic                 r_rq_tag;
  logic [VW-1:0]        r_rq_vpn;

  // -----------------------------------------------------------------
  // This cycle.
  // -----------------------------------------------------------------
  logic                  w_phys;      // physical regime
  logic                  w_sv39;      // sign-extension check applies
  logic [ASID_WIDTH-1:0] w_asid;
  logic                  w_hit;
  logic [EI-1:0]         w_hit_idx;
  itlb_ent_t             w_hit_ent;
  logic [PPN_WIDTH-1:0]  w_ppn;
  logic [PA_WIDTH-1:0]   w_chk_pa;
  logic [1:0]            w_chk_pbmt;
  logic                  w_chk_fault;
  logic                  w_chk_pmp_ok;
  logic [PMA_WIDTH-1:0]  w_chk_pma;

  logic                  w_inflight;  // a live walk for this request
  logic                  w_flt_hit;
  logic [TI-1:0]         w_flt_idx;
  logic                  w_flt_take;  // the held fault answered now
  logic                  w_rsp_ok;    // an L2 response for a live tag
  logic [VW-1:0]         w_smask;
  logic                  w_alloc;
  logic [TI-1:0]         w_alloc_idx;
  logic                  w_l2_fire;
  logic [TI-1:0]         w_l2_idx;
  logic                  w_install;
  logic [EI-1:0]         w_inst_idx;
  itlb_ent_t             w_inst_ent;
  logic [ITLB_ENTRIES-1:0] w_inv_hit;

  // -----------------------------------------------------------------
  // Lookup. Gated on r_rq_val, a flop (CLAUDE.md stl_sequent rule).
  // -----------------------------------------------------------------
  always_comb begin : lookup
    logic sel;
    w_phys = (csr_itlb_priv == PRV_M) ||
             (!csr_itlb_v && (csr_itlb_satp_mode == MODE_BARE)) ||
             (csr_itlb_v && (csr_itlb_vsatp_mode == MODE_BARE) &&
              (csr_itlb_hgatp_mode == MODE_BARE));
    w_sv39 = !w_phys &&
             (!csr_itlb_v || (csr_itlb_vsatp_mode != MODE_BARE));
    w_asid = csr_itlb_v ? csr_itlb_vsatp_asid : csr_itlb_satp_asid;

    w_hit     = 1'b0;
    w_hit_idx = '0;
    w_hit_ent = '0;
    for (int i = 0; i < ITLB_ENTRIES; i++) begin
      sel = r_rq_val && r_ent[i].val &&
            (r_ent[i].v == csr_itlb_v) &&
            (!csr_itlb_v || (r_ent[i].vmid == csr_itlb_hgatp_vmid)) &&
            (r_ent[i].g || (r_ent[i].asid == w_asid)) &&
            covers(r_ent[i], r_rq_vpn);
      if (sel && !w_hit) begin
        w_hit     = 1'b1;
        w_hit_idx = EI'(i);
        w_hit_ent = r_ent[i];
      end
    end

    // Output PPN: the covered VPN bits replace the stored ones.
    w_smask = size_mask(w_hit_ent.size);
    w_ppn   = (w_hit_ent.ppn & ~w_smask[PPN_WIDTH-1:0]) |
              (r_rq_vpn[PPN_WIDTH-1:0] & w_smask[PPN_WIDTH-1:0]);
    if (w_phys) w_ppn = r_rq_vpn[PPN_WIDTH-1:0];

    w_chk_pa   = {w_ppn, 12'h000};
    w_chk_pbmt = (w_phys || !w_hit) ? 2'b00 : w_hit_ent.pbmt;
  end

  pmp_pma_chk #(
    .PMP_ENTRIES  (PMP_ENTRIES),
    .PMP_GRAN_LG2 (PMP_GRAN_LG2),
    .PMA_REGIONS  (PMA_REGIONS),
    .PMA_BASE     (PMA_BASE),
    .PMA_TOP      (PMA_TOP),
    .PMA_ATTR     (PMA_ATTR),
    .PMA_DFLT     (PMA_DFLT)
  ) u_chk (
    .chk_pa     (w_chk_pa),
    .chk_acc    (2'd2),                // execute
    .chk_priv   (csr_itlb_priv),
    .chk_pbmt   (w_chk_pbmt),
    .pmp_cfg    (csr_itlb_pmpcfg),
    .pmp_addr   (csr_itlb_pmpaddr),
    .chk_pmp_ok (w_chk_pmp_ok),
    .chk_pma    (w_chk_pma),
    .chk_fault  (w_chk_fault)
  );

  // -----------------------------------------------------------------
  // Response, tracker and install decisions. Gated on r_rq_val.
  // -----------------------------------------------------------------
  always_comb begin : respond
    logic perm_bad;
    logic sx_bad;
    logic pa_bad;
    logic live;

    // -- the tracker as it relates to this request --------------------
    w_inflight = 1'b0;
    w_flt_hit  = 1'b0;
    w_flt_idx  = '0;
    for (int t = 0; t < WALK_DEPTH; t++) begin
      live = (r_trk[t].v == csr_itlb_v) &&
             (r_trk[t].asid == w_asid) &&
             (r_trk[t].vmid == csr_itlb_hgatp_vmid) &&
             (r_trk[t].vpn == r_rq_vpn);
      if (live && !r_trk[t].kill &&
          ((r_trk[t].st == T_REQ) || (r_trk[t].st == T_OUT)))
        w_inflight = 1'b1;
      if (live && (r_trk[t].st == T_FLT) && !w_flt_hit) begin
        w_flt_hit = 1'b1;
        w_flt_idx = TI'(t);
      end
    end

    // -- the IFU response ---------------------------------------------
    perm_bad = !w_hit_ent.perm[P_X] ||
               ((csr_itlb_priv == PRV_U) && !w_hit_ent.perm[P_U]) ||
               ((csr_itlb_priv == PRV_S) &&  w_hit_ent.perm[P_U]);
    sx_bad   = w_sv39 &&
               (r_rq_vpn[VW-1:VW-2] != {2{r_rq_vpn[VW-3]}});
    pa_bad   = |r_rq_vpn[VW-1:PA_HI];

    itlb_ifu_rsp_val = r_rq_val;
    itlb_ifu_tag     = r_rq_tag;
    itlb_ifu_status  = ST_MISS;
    itlb_ifu_ppn     = '0;
    itlb_ifu_cause   = '0;
    itlb_ifu_gpa     = '0;
    itlb_ifu_pma     = '0;
    w_alloc          = 1'b0;
    w_flt_take       = 1'b0;

    if (w_phys) begin
      if (pa_bad || w_chk_fault) begin
        itlb_ifu_status = ST_FAULT;
        itlb_ifu_cause  = CAUSE_ACCESS;
      end else begin
        itlb_ifu_status = ST_HIT;
        itlb_ifu_ppn    = w_ppn;
        itlb_ifu_pma    = w_chk_pma;
      end
    end else if (sx_bad) begin
      itlb_ifu_status = ST_FAULT;
      itlb_ifu_cause  = CAUSE_PAGE;
    end else if (w_hit) begin
      if (perm_bad) begin
        itlb_ifu_status = ST_FAULT;
        itlb_ifu_cause  = CAUSE_PAGE;
      end else if (w_chk_fault) begin
        itlb_ifu_status = ST_FAULT;
        itlb_ifu_cause  = CAUSE_ACCESS;
      end else begin
        itlb_ifu_status = ST_HIT;
        itlb_ifu_ppn    = w_ppn;
        itlb_ifu_pma    = w_chk_pma;
      end
    end else if (w_flt_hit) begin
      w_flt_take      = r_rq_val;
      itlb_ifu_status = ST_FAULT;
      itlb_ifu_cause  = r_trk[w_flt_idx].cause;
      if (r_trk[w_flt_idx].cause == CAUSE_GUEST)
        itlb_ifu_gpa  = r_trk[w_flt_idx].gpa;
    end else begin
      itlb_ifu_status = ST_MISS;
      w_alloc         = r_rq_val && !w_inflight;
    end
    if (!r_rq_val) begin
      itlb_ifu_status = ST_MISS;
      w_alloc         = 1'b0;
      w_flt_take      = 1'b0;
    end

    // -- a slot for a new walk: FREE first, then a held fault ---------
    w_alloc_idx = '0;
    begin : pick
      logic found;
      found = 1'b0;
      for (int t = 0; t < WALK_DEPTH; t++) begin
        if (!found && (r_trk[t].st == T_FREE)) begin
          found = 1'b1;
          w_alloc_idx = TI'(t);
        end
      end
      for (int t = 0; t < WALK_DEPTH; t++) begin
        if (!found && (r_trk[t].st == T_FLT) &&
            !(w_flt_hit && (w_flt_idx == TI'(t)))) begin
          found = 1'b1;
          w_alloc_idx = TI'(t);
        end
      end
      if (!found) w_alloc = 1'b0;
    end
    // An invalidate this cycle releases the tracker; a walk for this
    // miss starts on the next re-request.
    if (bkend_itlb_inv_val) w_alloc = 1'b0;

    // -- the L2 TLB request: the lowest REQ slot -----------------------
    itlb_l2t_req_val = 1'b0;
    w_l2_idx         = '0;
    for (int t = WALK_DEPTH - 1; t >= 0; t--) begin
      if (r_trk[t].st == T_REQ) begin
        itlb_l2t_req_val = 1'b1;
        w_l2_idx         = TI'(t);
      end
    end
    itlb_l2t_vpn  = r_trk[w_l2_idx].vpn;
    itlb_l2t_asid = r_trk[w_l2_idx].asid;
    itlb_l2t_vmid = r_trk[w_l2_idx].vmid;
    itlb_l2t_v    = r_trk[w_l2_idx].v;
    itlb_l2t_tag  = w_l2_idx;
    w_l2_fire     = itlb_l2t_req_val && itlb_l2t_req_rdy &&
                    !bkend_itlb_inv_val;
    if (bkend_itlb_inv_val) itlb_l2t_req_val = 1'b0;

    // -- install on an L2 hit (IL-4, IL-14) -----------------------------
    // A response is taken only for a slot that exists and is OUT.
    w_rsp_ok    = l2t_itlb_rsp_val && (32'(l2t_itlb_tag) < WALK_DEPTH) &&
                  (r_trk[l2t_itlb_tag].st == T_OUT);
    w_install   = w_rsp_ok && (l2t_itlb_status == L2_HIT) &&
                  !r_trk[l2t_itlb_tag].kill && !bkend_itlb_inv_val;
    w_inst_ent      = '0;
    w_inst_ent.val  = 1'b1;
    w_inst_ent.v    = r_trk[l2t_itlb_tag].v;
    w_inst_ent.g    = l2t_itlb_perm[P_G];
    w_inst_ent.asid = r_trk[l2t_itlb_tag].asid;
    w_inst_ent.vmid = r_trk[l2t_itlb_tag].vmid;
    w_inst_ent.vpn  = r_trk[l2t_itlb_tag].vpn;
    w_inst_ent.size = l2t_itlb_size;
    w_inst_ent.ppn  = l2t_itlb_ppn;
    w_inst_ent.perm = l2t_itlb_perm;
    w_inst_ent.pbmt = l2t_itlb_pbmt;

    begin : victim
      logic found;
      found      = 1'b0;
      w_inst_idx = (r_vict == r_mru) ? EI'(r_vict + 1'b1) : r_vict;
      for (int i = 0; i < ITLB_ENTRIES; i++) begin
        if (!found && !r_ent[i].val) begin
          found      = 1'b1;
          w_inst_idx = EI'(i);
        end
      end
    end
    // EI'(r_vict + 1) wraps for a power-of-two array; any other size
    // is folded back into range.
    if (32'(w_inst_idx) >= ITLB_ENTRIES) w_inst_idx = '0;

    // -- invalidate matches, ITLB-13, 13a, 13b --------------------------
    for (int i = 0; i < ITLB_ENTRIES; i++) begin
      logic a_ok;
      logic s_ok;
      a_ok = !bkend_itlb_inv_rs1_nz || covers(r_ent[i], bkend_itlb_inv_vpn);
      s_ok = !bkend_itlb_inv_rs2_nz ||
             (!r_ent[i].g && (r_ent[i].asid == bkend_itlb_inv_asid));
      case (bkend_itlb_inv_op)
        OP_VMA:  w_inv_hit[i] = !r_ent[i].v && a_ok && s_ok;
        OP_VVMA: w_inv_hit[i] = r_ent[i].v &&
                                (r_ent[i].vmid == bkend_itlb_inv_vmid) &&
                                a_ok && s_ok;
        OP_GVMA: w_inv_hit[i] = r_ent[i].v &&
                                (!bkend_itlb_inv_rs2_nz ||
                                 (r_ent[i].vmid == bkend_itlb_inv_vmid));
        default: w_inv_hit[i] = 1'b1;
      endcase
      w_inv_hit[i] = w_inv_hit[i] && bkend_itlb_inv_val;
    end
  end

  assign ifu_itlb_req_rdy = 1'b1;

  // -----------------------------------------------------------------
  // Sequential.
  // -----------------------------------------------------------------
  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      r_rq_val <= 1'b0;
      r_rq_tag <= 1'b0;
      r_rq_vpn <= '0;
      r_mru    <= '0;
      r_vict   <= '0;
      for (int i = 0; i < ITLB_ENTRIES; i++) r_ent[i] <= '0;
      for (int t = 0; t < 4; t++)            r_trk[t] <= '0;
    end else begin
      r_rq_val <= ifu_itlb_req_val && ifu_itlb_req_rdy;
      if (ifu_itlb_req_val && ifu_itlb_req_rdy) begin
        r_rq_tag <= ifu_itlb_tag;
        r_rq_vpn <= ifu_itlb_vpn;
      end

      // ---- array: invalidate, then install, then MRU ----------------
      for (int i = 0; i < ITLB_ENTRIES; i++) begin
        if (w_inv_hit[i]) r_ent[i].val <= 1'b0;
      end
      if (w_install) begin
        r_ent[w_inst_idx] <= w_inst_ent;
        r_mru             <= w_inst_idx;
        r_vict            <= EI'(w_inst_idx + 1'b1);
      end else if (r_rq_val && w_hit &&
                   (itlb_ifu_status == ST_HIT)) begin
        r_mru <= w_hit_idx;
      end

      // ---- tracker -------------------------------------------------------
      if (w_flt_take) r_trk[w_flt_idx].st <= T_FREE;
      if (w_l2_fire) r_trk[w_l2_idx].st <= T_OUT;
      if (w_rsp_ok) begin
        if (r_trk[l2t_itlb_tag].kill || bkend_itlb_inv_val) begin
          r_trk[l2t_itlb_tag].st   <= T_FREE;
          r_trk[l2t_itlb_tag].kill <= 1'b0;
        end else begin
          case (l2t_itlb_status)
            L2_HIT:   r_trk[l2t_itlb_tag].st <= T_FREE;
            L2_RETRY: r_trk[l2t_itlb_tag].st <= T_REQ;
            default: begin                       // fault or reserved
              r_trk[l2t_itlb_tag].st    <= T_FLT;
              r_trk[l2t_itlb_tag].cause <=
                ((l2t_itlb_status == L2_FAULT) &&
                 ((l2t_itlb_cause == CAUSE_PAGE) ||
                  (l2t_itlb_cause == CAUSE_GUEST)))
                  ? l2t_itlb_cause : CAUSE_ACCESS;
              r_trk[l2t_itlb_tag].gpa   <= l2t_itlb_gpa;
            end
          endcase
        end
      end
      if (w_alloc) begin
        r_trk[w_alloc_idx].st    <= T_REQ;
        r_trk[w_alloc_idx].kill  <= 1'b0;
        r_trk[w_alloc_idx].v     <= csr_itlb_v;
        r_trk[w_alloc_idx].asid  <= w_asid;
        r_trk[w_alloc_idx].vmid  <= csr_itlb_hgatp_vmid;
        r_trk[w_alloc_idx].vpn   <= r_rq_vpn;
        r_trk[w_alloc_idx].cause <= '0;
        r_trk[w_alloc_idx].gpa   <= '0;
      end
      // An invalidate releases every slot (IL-13, IL-14).
      if (bkend_itlb_inv_val) begin
        for (int t = 0; t < WALK_DEPTH; t++) begin
          if (r_trk[t].st == T_OUT) begin
            if (!(w_rsp_ok && (l2t_itlb_tag == TI'(t))))
              r_trk[t].kill <= 1'b1;
          end else begin
            r_trk[t].st   <= T_FREE;
            r_trk[t].kill <= 1'b0;
          end
        end
      end
    end
  end

endmodule : itlb
