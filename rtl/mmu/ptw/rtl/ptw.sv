// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Page table walker (BP-123). mmu_decisions.md MMU-1 to MMU-30;
// client port itlb_l2tlb_interfaces.md IL-1 to IL-14; memory port
// ptw_mem_interfaces.md WM-1 to WM-9.
//
// PLACEMENT (MMU-1, MMU-1a). There is no L2 TLB. The walker serves the
// ITLB directly, outside the front-end top, on the itlb_l2t_* /
// l2t_itlb_* port (the names keep l2t, session-077). It holds no
// translation (MMU-17), so it has no invalidate port; a walk in
// progress when the ITLB is invalidated completes and is answered
// normally, and the ITLB installs nothing (IL-13, IL-14).
//
// ONE WALK AT A TIME (MMU-U2, IL-6). A request taken while a walk is
// in progress is answered RETRY. The retry is held until the response
// port is free; ready is low while one is held.
//
// REGIMES (MMU-19 to MMU-21). The CSR group (MMU-24a) is sampled when
// a walk starts and held for the walk.
//   V=0, satp Sv39            single-stage Sv39 from satp.PPN
//   V=1, vsatp Sv39, hgatp Sv39x4
//                             NESTED: every VS-stage PTE address is a
//                             guest physical address and is first
//                             translated by a G-stage walk (an
//                             implicit READ, kind 01); the final GPA
//                             is translated by a G-stage walk too
//                             (the fetch's own GPA, kind 00)
//   V=1, vsatp Bare, hgatp Sv39x4
//                             G-stage only; the GPA is the request
//                             address, 41 bits (MMU-20)
//   V=1, vsatp Sv39, hgatp Bare
//                             VS-stage only; GPA = SPA, so there is no
//                             guest-page fault and a VS-stage PPN is
//                             checked as a supervisor physical page
//   V=0 satp Bare, V=1 both Bare
//                             physical; the ITLB never asks (it answers
//                             these itself). Answered as an identity
//                             4 KiB hit, PA width checked, cause 1
//                             beyond it
//
// PTE CHECKS (privileged translation algorithm, Sv39 and Sv39x4,
// RISC-V Privileged ISA v1.13 chapter 11.3 and chapter 20.5). In the
// order the algorithm makes them, so a page fault found earlier in the
// walk is reported first (MMU-28):
//   - V clear, or W set with R clear                 page fault
//   - bits 60:54 set                                 page fault
//   - non-leaf: D, A, U, N or PBMT set (reserved for non-leaf PTEs),
//     or a non-leaf at level 0                       page fault
//   - leaf: PBMT 3 (reserved), or PBMT non-zero with PBMTE clear
//     (MMU-U6). PBMTE is menvcfg's for single-stage and G-stage and
//     henvcfg's for the VS-stage (privileged 3.1.18 and 20.2.13; spike
//     mmu.cc agrees). mmu_decisions.md MMU-U6 reads "henvcfg.PBMTE
//     clear for the G-stage"; reported                page fault
//   - leaf with N set: only level 0 with PPN[3:0] = 4'b1000 is
//     defined (Svnapot, 64 KiB); every other N encoding is reserved
//     (MMU-U7)                                       page fault
//   - leaf superpage whose low PPN bits are not zero (misaligned)
//                                                    page fault
//   - fetch: X clear. The U-against-privilege check of a single-stage
//     or VS-stage leaf is the ITLB's, on every hit (MMU-26, ITLB-16)
//                                                    page fault
//   - store (the data-side client, MMU-8): W clear    page fault
//   - A clear, or a store with D clear:
//       ADUE clear (Svade)                           page fault
//       ADUE set (Svadu)                             the update below
// At the G-stage every page fault is a GUEST page fault, cause 20
// (MMU-22), and the leaf must also have U set and grant the access
// type, as a user-mode access (MMU-26): X for the fetch's own GPA, R
// for a VS-stage PTE read, W for the VS-stage update (MMU-8a).
// ADUE is menvcfg's for single-stage and G-stage, henvcfg's for the
// VS-stage (MMU-7, MMU-7a); the two stages of one nested walk may be
// under different rules.
//
// THE SVADU UPDATE IS A COMPARE AND STORE (MMU-8, WM-5). The walker
// checks that a store to the PTE passes PMP and PMA (MMU-10d, MMU-12a)
// and issues one CAS with the PTE it read as the compare value and
// the PTE with A (and D for a store) set as the swap value. A response
// equal to the compare value means the store happened, and the PTE is
// evaluated again as updated. Otherwise the walk RESTARTS: a
// single-stage or VS-stage mismatch restarts the whole translation, a
// G-stage mismatch restarts that G-stage translation (step 2). A
// VS-stage PTE lives in guest physical memory, so its update is a
// store through the G-stage: the PTE's GPA is translated again as an
// implicit WRITE (kind 10), which needs W in the G-stage leaf and sets
// the G-stage A and D under menvcfg.ADUE (MMU-8a). The translation is
// answered only after every update has completed (MMU-8, WM-6).
//
// EVERY ACCESS IS CHECKED BEFORE IT IS PRESENTED (MMU-10d, MMU-12,
// MMU-12a, WM-8): PMP at privilege S, as a read for a PTE read and as
// a write for a CAS, and PMA cacheable and coherent (MMU-13 bits 0 and
// 1). A failure is an access fault, cause 1, and nothing is presented.
// An address that cannot be formed in PA_WIDTH bits is refused the same
// way (MMU-28). A memory-port error is cause 1 too (WM-7).
//
// A PPN IS NEVER TRUNCATED (MMU-28). All 44 PPN bits of every PTE are
// read:
//   - a supervisor physical page (single-stage, or G-stage, or a
//     VS-stage PTE when hgatp is Bare) with a bit set above bit
//     PPN_WIDTH-1: the access made with it, the next PTE read or the
//     fetch, is an access fault, cause 1
//   - a guest physical page (VS-stage with hgatp Sv39x4) with a bit
//     set above GPA bit 40: a guest-page fault, cause 20, with GPA 0
//     (MMU-30) and the kind of the access that needed it
// The fetch's own address is checked after the leaf's A update, where
// the algorithm puts the access it makes.
//
// THE RESPONSE (IL-4 to IL-11b).
//   hit    ppn, size, perm, pbmt. size is IL-7: 000 4 KiB, 001 64 KiB,
//          010 2 MiB, 011 1 GiB. A single-stage ppn is the leaf PTE's
//          (for 64 KiB its PPN[3:0] is the size marker, IL-7); a
//          two-stage ppn is the final supervisor physical page, and the
//          size is the smaller of the two stages' leaf sizes (MMU-27,
//          IL-7a). perm is the single-stage or VS-stage leaf's low byte
//          as updated; for a G-stage-only translation it is the G-stage
//          leaf's with G cleared (there is no VS-stage leaf, and the G
//          bit of a G-stage PTE is not a global mapping). pbmt is the
//          more restrictive of the two stages' (MMU-U6, IL-9a)
//   fault  cause 1, 12 or 20 (MMU-16). On cause 20 gpa is the faulting
//          guest physical address -- the VS-stage PTE address for an
//          implicit access, the fetch's page for the fetch's own -- or 0
//          when it does not fit 41 bits (MMU-30), and gpa_imp is the
//          kind (MMU-29): 00 the fetch's GPA, 01 an implicit read of a
//          VS-stage PTE, 10 an implicit write of one
//   retry  IL-6
//
// THE ACCESS TYPE. itlb_l2t_acc is not on itlb_l2tlb_interfaces.md 2:
// the walker needs it for the D update of a data-side client (MMU-8)
// and for the G-stage permission of the final GPA. The ITLB's request
// is always a fetch and tb_fe_top ties it to ACC_X. Reported (BP-123).
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ptw #(
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

  // ---- client, itlb_l2tlb_interfaces.md 2 ---------------------------
  input  logic                     itlb_l2t_req_val,
  output logic                     itlb_l2t_req_rdy,
  input  logic [VA_WIDTH-13:0]     itlb_l2t_vpn,     // IL-1a
  input  logic [ASID_WIDTH-1:0]    itlb_l2t_asid,
  input  logic [VMID_WIDTH-1:0]    itlb_l2t_vmid,
  input  logic                     itlb_l2t_v,
  input  logic [1:0]               itlb_l2t_tag,
  input  logic [1:0]               itlb_l2t_acc,     // see header
  output logic                     l2t_itlb_rsp_val,
  output logic [1:0]               l2t_itlb_tag,
  output logic [1:0]               l2t_itlb_status,
  output logic [PPN_WIDTH-1:0]     l2t_itlb_ppn,
  output logic [2:0]               l2t_itlb_size,    // IL-7
  output logic [PERM_WIDTH-1:0]    l2t_itlb_perm,
  output logic [1:0]               l2t_itlb_pbmt,
  output logic [CAUSE_WIDTH-1:0]   l2t_itlb_cause,
  output logic [GPA_WIDTH-1:0]     l2t_itlb_gpa,
  output logic [1:0]               l2t_itlb_gpa_imp, // IL-11b

  // ---- memory, ptw_mem_interfaces.md 3 -------------------------------
  output logic                     ptw_mem_req_val,
  input  logic                     ptw_mem_req_rdy,
  output logic                     ptw_mem_req_op,   // 0 READ, 1 CAS
  output logic [PA_WIDTH-1:0]      ptw_mem_req_paddr,
  output logic [63:0]              ptw_mem_req_cmp,
  output logic [63:0]              ptw_mem_req_swap,
  input  logic                     mem_ptw_rsp_val,
  input  logic [63:0]              mem_ptw_rsp_data,
  input  logic                     mem_ptw_rsp_err,

  // ---- CSR input group, MMU-24a, MMU-24b, MMU-11a --------------------
  input  logic [3:0]               csr_ptw_satp_mode,
  input  logic [PPN_WIDTH-1:0]     csr_ptw_satp_ppn,
  input  logic [3:0]               csr_ptw_vsatp_mode,
  input  logic [GPA_WIDTH-13:0]    csr_ptw_vsatp_ppn,
  input  logic [3:0]               csr_ptw_hgatp_mode,
  input  logic [PPN_WIDTH-1:0]     csr_ptw_hgatp_ppn,
  input  logic                     csr_ptw_menvcfg_adue,
  input  logic                     csr_ptw_henvcfg_adue,
  input  logic                     csr_ptw_menvcfg_pbmte,
  input  logic                     csr_ptw_henvcfg_pbmte,
  input  logic [((PMP_ENTRIES > 0) ? PMP_ENTRIES : 1)-1:0][7:0]
                                   csr_ptw_pmpcfg,
  input  logic [((PMP_ENTRIES > 0) ? PMP_ENTRIES : 1)-1:0][PA_WIDTH-3:0]
                                   csr_ptw_pmpaddr
);

  // -----------------------------------------------------------------
  // Constants.
  // -----------------------------------------------------------------
  localparam int VW   = VA_WIDTH - 12;        // 29, the request page
  localparam int GPW  = GPA_WIDTH - 12;       // 29, a guest page
  localparam int PTEP = 44;                   // PTE PPN field, 53:10

  // l2t_itlb_status, IL-4.
  localparam logic [1:0] ST_HIT   = 2'b00;
  localparam logic [1:0] ST_FAULT = 2'b01;
  localparam logic [1:0] ST_RETRY = 2'b10;

  // l2t_itlb_size, IL-7.
  localparam logic [2:0] SZ_4K  = 3'b000;
  localparam logic [2:0] SZ_64K = 3'b001;
  localparam logic [2:0] SZ_2M  = 3'b010;
  localparam logic [2:0] SZ_1G  = 3'b011;

  // Exception codes, MMU-16.
  localparam logic [CAUSE_WIDTH-1:0] CAUSE_ACCESS = CAUSE_WIDTH'(1);
  localparam logic [CAUSE_WIDTH-1:0] CAUSE_PAGE   = CAUSE_WIDTH'(12);
  localparam logic [CAUSE_WIDTH-1:0] CAUSE_GUEST  = CAUSE_WIDTH'(20);

  // Implicit-access kind, MMU-29.
  localparam logic [1:0] IMP_FETCH = 2'b00;
  localparam logic [1:0] IMP_READ  = 2'b01;
  localparam logic [1:0] IMP_WRITE = 2'b10;

  // Access types, the pmp_pma_chk encoding.
  localparam logic [1:0] ACC_R = 2'd0;
  localparam logic [1:0] ACC_W = 2'd1;
  localparam logic [1:0] ACC_X = 2'd2;

  localparam logic [1:0] PRV_S = 2'd1;        // MMU-10d

  localparam logic [3:0] MODE_BARE = 4'd0;

  localparam logic OP_READ = 1'b0;            // WM, section 3
  localparam logic OP_CAS  = 1'b1;

  // PTE bits.
  localparam int P_V = 0;
  localparam int P_R = 1;
  localparam int P_W = 2;
  localparam int P_X = 3;
  localparam int P_U = 4;
  localparam int P_G = 5;
  localparam int P_A = 6;
  localparam int P_D = 7;
  localparam int P_N = 63;

  // PBMT encodings.
  localparam logic [1:0] PBMT_RSV = 2'd3;

  // PMA bits, MMU-13.
  localparam int PMA_CACHEABLE = 0;
  localparam int PMA_COHERENT  = 1;

  // Svnapot 64 KiB marker, PPN[3:0].
  localparam logic [3:0] NAPOT_64K = 4'b1000;

  // -----------------------------------------------------------------
  // State.
  // -----------------------------------------------------------------
  typedef enum logic [3:0] {
    S_IDLE    = 4'd0,
    S_START   = 4'd1,    // begin (or restart) the translation
    S_S_ADDR  = 4'd2,    // form a single / VS-stage PTE address
    S_S_EVAL  = 4'd3,    // evaluate a single / VS-stage PTE
    S_S_UPD   = 4'd4,    // its Svadu update
    S_S_FINAL = 4'd5,    // its leaf is final; the fetch's address
    S_G_START = 4'd6,    // begin (or restart) a G-stage translation
    S_G_ADDR  = 4'd7,    // form a G-stage PTE address
    S_G_EVAL  = 4'd8,    // evaluate a G-stage PTE
    S_ISSUE   = 4'd9,    // check and present one memory access
    S_WAIT    = 4'd10,   // its response
    S_RSP     = 4'd11    // the client response, one cycle
  } st_e;

  // Where a memory response goes.
  typedef enum logic [1:0] {
    MR_SPTE = 2'd0,
    MR_GPTE = 2'd1,
    MR_SCAS = 2'd2,
    MR_GCAS = 2'd3
  } mret_e;

  // Where a finished G-stage translation goes.
  typedef enum logic [1:0] {
    GR_SREAD = 2'd0,     // read the VS-stage PTE at the result
    GR_SUPD  = 2'd1,     // update the VS-stage PTE at the result
    GR_FINAL = 2'd2      // the fetch's own GPA: answer
  } gret_e;

  st_e                     r_st;

  // The request and the regime it is walked under.
  logic                    r_v;
  logic [VW-1:0]           r_vpn;
  logic [1:0]              r_tag;
  logic [1:0]              r_acc;
  logic                    r_s_on;     // a single or VS stage walk
  logic                    r_g_on;     // V=1 and hgatp Sv39x4
  logic [PPN_WIDTH-1:0]    r_satp_ppn;
  logic [GPW-1:0]          r_vsatp_ppn;
  logic [PPN_WIDTH-1:0]    r_hgatp_ppn;
  logic                    r_s_adue;   // ADUE of the single / VS stage
  logic                    r_g_adue;   // menvcfg.ADUE, the G-stage
  logic                    r_s_pbmte;
  logic                    r_g_pbmte;

  // The single / VS stage.
  logic [1:0]              r_s_lvl;
  logic [PTEP-1:0]         r_s_base;   // table page (SPA, or GPA)
  logic [63:0]             r_s_pte;
  logic [GPA_WIDTH-1:0]    r_s_pte_gpa;
  logic [PA_WIDTH-1:0]     r_s_pte_spa;
  logic [63:0]             r_s_swap;

  // The G-stage translation in progress.
  logic [GPA_WIDTH-1:0]    r_g_gpa;
  logic [1:0]              r_g_kind;
  logic [1:0]              r_g_acc;
  gret_e                   r_g_ret;
  logic [1:0]              r_g_lvl;
  logic [PTEP-1:0]         r_g_base;
  logic [63:0]             r_g_pte;
  logic [PA_WIDTH-1:0]     r_g_pte_spa;
  // Its last result.
  logic [PPN_WIDTH-1:0]    r_g_res_ppn;
  logic [2:0]              r_g_res_size;
  logic [1:0]              r_g_res_pbmt;
  logic [PERM_WIDTH-1:0]   r_g_res_perm;

  // The memory access.
  logic                    r_m_op;
  logic [PA_WIDTH-1:0]     r_m_pa;
  logic [63:0]             r_m_cmp;
  logic [63:0]             r_m_swap;
  mret_e                   r_m_ret;

  // The response, and a retry waiting for the port.
  logic [1:0]              r_rsp_tag;
  logic [1:0]              r_rsp_st;
  logic [PPN_WIDTH-1:0]    r_rsp_ppn;
  logic [2:0]              r_rsp_size;
  logic [PERM_WIDTH-1:0]   r_rsp_perm;
  logic [1:0]              r_rsp_pbmt;
  logic [CAUSE_WIDTH-1:0]  r_rsp_cause;
  logic [GPA_WIDTH-1:0]    r_rsp_gpa;
  logic [1:0]              r_rsp_imp;
  logic                    r_rty_val;
  logic [1:0]              r_rty_tag;

  // -----------------------------------------------------------------
  // The checker of MMU-10a, site 2 (MMU-10d): every access the walker
  // presents, at privilege S, read or write, with no PBMT.
  // -----------------------------------------------------------------
  logic                    w_chk_pmp_ok;
  logic [PMA_WIDTH-1:0]    w_chk_pma;
  logic                    w_chk_fault;
  logic                    w_chk_bad;

  pmp_pma_chk #(
    .PMP_ENTRIES  (PMP_ENTRIES),
    .PMP_GRAN_LG2 (PMP_GRAN_LG2),
    .PMA_REGIONS  (PMA_REGIONS),
    .PMA_BASE     (PMA_BASE),
    .PMA_TOP      (PMA_TOP),
    .PMA_ATTR     (PMA_ATTR),
    .PMA_DFLT     (PMA_DFLT)
  ) u_chk (
    .chk_pa     (r_m_pa),
    .chk_acc    ((r_m_op == OP_CAS) ? ACC_W : ACC_R),
    .chk_priv   (PRV_S),
    .chk_pbmt   (2'b00),
    .pmp_cfg    (csr_ptw_pmpcfg),
    .pmp_addr   (csr_ptw_pmpaddr),
    .chk_pmp_ok (w_chk_pmp_ok),
    .chk_pma    (w_chk_pma),
    .chk_fault  (w_chk_fault)
  );

  // PMP denial, or a page table outside cacheable coherent memory
  // (MMU-12a). chk_fault adds only the execute check, which a read or a
  // write never makes.
  assign w_chk_bad = !w_chk_pmp_ok || !w_chk_pma[PMA_CACHEABLE] ||
                     !w_chk_pma[PMA_COHERENT];

  // -----------------------------------------------------------------
  // Helpers.
  // -----------------------------------------------------------------
  // The VPN bits a leaf at this level, or a 64 KiB NAPOT leaf, takes
  // from the address being translated.
  function automatic logic [PTEP-1:0] lvl_mask(input logic [1:0] lvl,
                                               input logic       napot);
    if (lvl == 2'd2)      return PTEP'(18'h3FFFF);
    else if (lvl == 2'd1) return PTEP'(9'h1FF);
    else if (napot)       return PTEP'(4'hF);
    else                  return '0;
  endfunction

  function automatic logic [2:0] lvl_size(input logic [1:0] lvl,
                                          input logic       napot);
    if (lvl == 2'd2)      return SZ_1G;
    else if (lvl == 2'd1) return SZ_2M;
    else if (napot)       return SZ_64K;
    else                  return SZ_4K;
  endfunction

  // The more restrictive memory type, PMA < NC < IO (MMU-U6).
  function automatic logic [1:0] pbmt_max(input logic [1:0] a,
                                          input logic [1:0] b);
    return (a > b) ? a : b;
  endfunction

  // -----------------------------------------------------------------
  // The single / VS-stage PTE, evaluated.
  // -----------------------------------------------------------------
  logic                    ws_pf;       // a page fault, cause 12
  logic                    ws_leaf;
  logic [PTEP-1:0]         ws_ppn;
  logic                    ws_next_wide;  // the next page cannot be formed
  logic                    ws_next_gwide; // a GPA above bit 40
  logic                    ws_upd;      // A, or A and D, to be set
  logic [PTEP-1:0]         ws_page;     // the translated page
  logic [2:0]              ws_size;

  always_comb begin : s_eval
    logic        v_bad;
    logic        rsv;
    logic        napot;
    logic [1:0]  pbmt;
    logic        perm_bad;
    logic        need_a;
    logic        need_d;
    logic [PTEP-1:0] mask;
    v_bad   = !r_s_pte[P_V] || (!r_s_pte[P_R] && r_s_pte[P_W]);
    rsv     = |r_s_pte[60:54];
    ws_leaf = r_s_pte[P_R] || r_s_pte[P_X];
    ws_ppn  = r_s_pte[53:10];
    napot   = r_s_pte[P_N];
    pbmt    = r_s_pte[62:61];
    mask    = lvl_mask(r_s_lvl, napot);

    // A supervisor physical page beyond PPN_WIDTH, or (nested) a guest
    // physical page beyond 41 bits. Read for the next table page of a
    // non-leaf, and for the translated page of a leaf.
    ws_next_wide  = |ws_ppn[PTEP-1:PPN_WIDTH];
    ws_next_gwide = |ws_ppn[PTEP-1:GPW];

    ws_page = (ws_ppn & ~mask) | (PTEP'(r_vpn) & mask);
    ws_size = lvl_size(r_s_lvl, napot);

    perm_bad = ((r_acc == ACC_X) && !r_s_pte[P_X]) ||
               ((r_acc == ACC_W) && !r_s_pte[P_W]);
    need_a   = !r_s_pte[P_A];
    need_d   = (r_acc == ACC_W) && !r_s_pte[P_D];

    ws_pf  = 1'b0;
    ws_upd = 1'b0;
    if (v_bad || rsv) begin
      ws_pf = 1'b1;
    end else if (!ws_leaf) begin
      if (r_s_pte[P_D] || r_s_pte[P_A] || r_s_pte[P_U] || napot ||
          (pbmt != 2'b00) || (r_s_lvl == 2'd0))
        ws_pf = 1'b1;
    end else begin
      if ((pbmt == PBMT_RSV) || (!r_s_pbmte && (pbmt != 2'b00)))
        ws_pf = 1'b1;
      else if (napot && ((r_s_lvl != 2'd0) ||
                         (ws_ppn[3:0] != NAPOT_64K)))
        ws_pf = 1'b1;
      else if (((r_s_lvl == 2'd2) && (ws_ppn[17:0] != '0)) ||
               ((r_s_lvl == 2'd1) && (ws_ppn[8:0]  != '0)))
        ws_pf = 1'b1;                      // misaligned superpage
      else if (perm_bad)
        ws_pf = 1'b1;
      else if (need_a || need_d) begin
        if (r_s_adue) ws_upd = 1'b1;       // Svadu
        else          ws_pf  = 1'b1;       // Svade
      end
    end
  end

  // -----------------------------------------------------------------
  // The G-stage PTE, evaluated. Every access is a user-mode one.
  // -----------------------------------------------------------------
  logic                    wg_gpf;      // a guest-page fault, cause 20
  logic                    wg_leaf;
  logic [PTEP-1:0]         wg_ppn;
  logic                    wg_next_wide;
  logic                    wg_upd;
  logic [PTEP-1:0]         wg_page;
  logic [2:0]              wg_size;

  always_comb begin : g_eval
    logic        v_bad;
    logic        rsv;
    logic        napot;
    logic [1:0]  pbmt;
    logic        perm_bad;
    logic        need_a;
    logic        need_d;
    logic [PTEP-1:0] mask;
    v_bad   = !r_g_pte[P_V] || (!r_g_pte[P_R] && r_g_pte[P_W]);
    rsv     = |r_g_pte[60:54];
    wg_leaf = r_g_pte[P_R] || r_g_pte[P_X];
    wg_ppn  = r_g_pte[53:10];
    napot   = r_g_pte[P_N];
    pbmt    = r_g_pte[62:61];
    mask    = lvl_mask(r_g_lvl, napot);

    wg_next_wide = |wg_ppn[PTEP-1:PPN_WIDTH];
    wg_page = (wg_ppn & ~mask) | (PTEP'(r_g_gpa[GPA_WIDTH-1:12]) & mask);
    wg_size = lvl_size(r_g_lvl, napot);

    perm_bad = !r_g_pte[P_U] ||
               ((r_g_acc == ACC_X) && !r_g_pte[P_X]) ||
               ((r_g_acc == ACC_R) && !r_g_pte[P_R]) ||
               ((r_g_acc == ACC_W) && !r_g_pte[P_W]);
    need_a   = !r_g_pte[P_A];
    need_d   = (r_g_acc == ACC_W) && !r_g_pte[P_D];

    wg_gpf = 1'b0;
    wg_upd = 1'b0;
    if (v_bad || rsv) begin
      wg_gpf = 1'b1;
    end else if (!wg_leaf) begin
      if (r_g_pte[P_D] || r_g_pte[P_A] || r_g_pte[P_U] || napot ||
          (pbmt != 2'b00) || (r_g_lvl == 2'd0))
        wg_gpf = 1'b1;
    end else begin
      if ((pbmt == PBMT_RSV) || (!r_g_pbmte && (pbmt != 2'b00)))
        wg_gpf = 1'b1;
      else if (napot && ((r_g_lvl != 2'd0) ||
                         (wg_ppn[3:0] != NAPOT_64K)))
        wg_gpf = 1'b1;
      else if (((r_g_lvl == 2'd2) && (wg_ppn[17:0] != '0)) ||
               ((r_g_lvl == 2'd1) && (wg_ppn[8:0]  != '0)))
        wg_gpf = 1'b1;
      else if (perm_bad)
        wg_gpf = 1'b1;
      else if (need_a || need_d) begin
        if (r_g_adue) wg_upd = 1'b1;
        else          wg_gpf = 1'b1;
      end
    end
  end

  // -----------------------------------------------------------------
  // PTE addresses. Formed wide, so an address that does not fit
  // PA_WIDTH is seen rather than wrapped (MMU-28).
  // -----------------------------------------------------------------
  logic [63:0]             w_s_addr;
  logic [63:0]             w_g_addr;
  logic [8:0]              w_s_idx;
  logic [10:0]             w_g_idx;

  always_comb begin : addrs
    case (r_s_lvl)
      2'd2:    w_s_idx = r_vpn[26:18];
      2'd1:    w_s_idx = r_vpn[17:9];
      default: w_s_idx = r_vpn[8:0];
    endcase
    // Sv39x4: the root index is GPA bits 40:30, eleven bits.
    case (r_g_lvl)
      2'd2:    w_g_idx = r_g_gpa[40:30];
      2'd1:    w_g_idx = {2'b00, r_g_gpa[29:21]};
      default: w_g_idx = {2'b00, r_g_gpa[20:12]};
    endcase
    w_s_addr = ({20'd0, r_s_base} << 12) + 64'({w_s_idx, 3'b000});
    w_g_addr = ({20'd0, r_g_base} << 12) + 64'({w_g_idx, 3'b000});
  end

  // -----------------------------------------------------------------
  // Outputs.
  // -----------------------------------------------------------------
  always_comb begin : outs
    // WM-8: an access that fails its check is never presented.
    ptw_mem_req_val   = (r_st == S_ISSUE) && !w_chk_bad;
    ptw_mem_req_op    = r_m_op;
    ptw_mem_req_paddr = r_m_pa;
    ptw_mem_req_cmp   = r_m_cmp;
    ptw_mem_req_swap  = r_m_swap;

    // One walk; a request during it is answered retry, one held at a
    // time.
    itlb_l2t_req_rdy  = rstn && !r_rty_val;

    l2t_itlb_rsp_val  = 1'b0;
    l2t_itlb_tag      = r_rsp_tag;
    l2t_itlb_status   = r_rsp_st;
    l2t_itlb_ppn      = r_rsp_ppn;
    l2t_itlb_size     = r_rsp_size;
    l2t_itlb_perm     = r_rsp_perm;
    l2t_itlb_pbmt     = r_rsp_pbmt;
    l2t_itlb_cause    = r_rsp_cause;
    l2t_itlb_gpa      = r_rsp_gpa;
    l2t_itlb_gpa_imp  = r_rsp_imp;
    if (r_st == S_RSP) begin
      l2t_itlb_rsp_val = 1'b1;
    end else if (r_rty_val) begin
      // The port is free: answer the held retry.
      l2t_itlb_rsp_val = 1'b1;
      l2t_itlb_tag     = r_rty_tag;
      l2t_itlb_status  = ST_RETRY;
      l2t_itlb_ppn     = '0;
      l2t_itlb_size    = SZ_4K;
      l2t_itlb_perm    = '0;
      l2t_itlb_pbmt    = '0;
      l2t_itlb_cause   = '0;
      l2t_itlb_gpa     = '0;
      l2t_itlb_gpa_imp = '0;
    end
  end

  // -----------------------------------------------------------------
  // The walk.
  // -----------------------------------------------------------------
  wire w_accept = itlb_l2t_req_val && itlb_l2t_req_rdy;

  always_ff @(posedge clk or negedge rstn) begin : seq
    if (!rstn) begin
      r_st         <= S_IDLE;
      r_v          <= 1'b0;
      r_vpn        <= '0;
      r_tag        <= '0;
      r_acc        <= ACC_X;
      r_s_on       <= 1'b0;
      r_g_on       <= 1'b0;
      r_satp_ppn   <= '0;
      r_vsatp_ppn  <= '0;
      r_hgatp_ppn  <= '0;
      r_s_adue     <= 1'b0;
      r_g_adue     <= 1'b0;
      r_s_pbmte    <= 1'b0;
      r_g_pbmte    <= 1'b0;
      r_s_lvl      <= '0;
      r_s_base     <= '0;
      r_s_pte      <= '0;
      r_s_pte_gpa  <= '0;
      r_s_pte_spa  <= '0;
      r_s_swap     <= '0;
      r_g_gpa      <= '0;
      r_g_kind     <= IMP_FETCH;
      r_g_acc      <= ACC_X;
      r_g_ret      <= GR_FINAL;
      r_g_lvl      <= '0;
      r_g_base     <= '0;
      r_g_pte      <= '0;
      r_g_pte_spa  <= '0;
      r_g_res_ppn  <= '0;
      r_g_res_size <= SZ_4K;
      r_g_res_pbmt <= '0;
      r_g_res_perm <= '0;
      r_m_op       <= OP_READ;
      r_m_pa       <= '0;
      r_m_cmp      <= '0;
      r_m_swap     <= '0;
      r_m_ret      <= MR_SPTE;
      r_rsp_tag    <= '0;
      r_rsp_st     <= ST_HIT;
      r_rsp_ppn    <= '0;
      r_rsp_size   <= SZ_4K;
      r_rsp_perm   <= '0;
      r_rsp_pbmt   <= '0;
      r_rsp_cause  <= '0;
      r_rsp_gpa    <= '0;
      r_rsp_imp    <= '0;
      r_rty_val    <= 1'b0;
      r_rty_tag    <= '0;
    end else begin
      // ---- a request while busy is answered retry (IL-6) ------------
      if (r_rty_val && (r_st != S_RSP)) r_rty_val <= 1'b0;
      if (w_accept && (r_st != S_IDLE)) begin
        r_rty_val <= 1'b1;
        r_rty_tag <= itlb_l2t_tag;
      end

      case (r_st)
        // ---------------------------------------------------------------
        S_IDLE: begin
          if (w_accept) begin
            r_v         <= itlb_l2t_v;
            r_vpn       <= itlb_l2t_vpn;
            r_tag       <= itlb_l2t_tag;
            r_acc       <= itlb_l2t_acc;
            r_satp_ppn  <= csr_ptw_satp_ppn;
            r_vsatp_ppn <= csr_ptw_vsatp_ppn;
            r_hgatp_ppn <= csr_ptw_hgatp_ppn;
            r_s_on      <= itlb_l2t_v ? (csr_ptw_vsatp_mode != MODE_BARE)
                                      : (csr_ptw_satp_mode  != MODE_BARE);
            r_g_on      <= itlb_l2t_v && (csr_ptw_hgatp_mode != MODE_BARE);
            // MMU-7, MMU-7a; the PBMTE pair the same way.
            r_s_adue    <= itlb_l2t_v ? csr_ptw_henvcfg_adue
                                      : csr_ptw_menvcfg_adue;
            r_g_adue    <= csr_ptw_menvcfg_adue;
            r_s_pbmte   <= itlb_l2t_v ? csr_ptw_henvcfg_pbmte
                                      : csr_ptw_menvcfg_pbmte;
            r_g_pbmte   <= csr_ptw_menvcfg_pbmte;
            r_st        <= S_START;
          end
        end

        // ---------------------------------------------------------------
        S_START: begin
          r_rsp_tag <= r_tag;
          if (r_s_on) begin
            r_s_lvl  <= 2'd2;
            r_s_base <= r_v ? PTEP'(r_vsatp_ppn) : PTEP'(r_satp_ppn);
            r_st     <= S_S_ADDR;
          end else if (r_g_on) begin
            // G-stage only: the request address is the GPA.
            r_g_gpa  <= {r_vpn, 12'h000};
            r_g_kind <= IMP_FETCH;
            r_g_acc  <= r_acc;
            r_g_ret  <= GR_FINAL;
            r_st     <= S_G_START;
          end else begin
            // Physical: never asked by the ITLB. Identity, 4 KiB.
            if (|r_vpn[VW-1:PPN_WIDTH]) begin
              r_rsp_st    <= ST_FAULT;
              r_rsp_cause <= CAUSE_ACCESS;
              r_rsp_gpa   <= '0;
              r_rsp_imp   <= '0;
            end else begin
              r_rsp_st    <= ST_HIT;
              r_rsp_ppn   <= r_vpn[PPN_WIDTH-1:0];
              r_rsp_size  <= SZ_4K;
              r_rsp_perm  <= 8'b1100_1111;     // D A - - X W R V
              r_rsp_pbmt  <= '0;
            end
            r_st <= S_RSP;
          end
        end

        // ---------------------------------------------------------------
        S_S_ADDR: begin
          if (r_g_on) begin
            // The VS-stage PTE address is a GPA (MMU-21): an implicit
            // read through the G-stage. It fits 41 bits: the base was
            // checked when it was formed (vsatp.PPN is 29 bits, MMU-24b).
            r_s_pte_gpa <= w_s_addr[GPA_WIDTH-1:0];
            r_g_gpa     <= w_s_addr[GPA_WIDTH-1:0];
            r_g_kind    <= IMP_READ;
            r_g_acc     <= ACC_R;
            r_g_ret     <= GR_SREAD;
            r_st        <= S_G_START;
          end else if (|w_s_addr[63:PA_WIDTH]) begin
            r_rsp_st    <= ST_FAULT;          // MMU-28
            r_rsp_cause <= CAUSE_ACCESS;
            r_rsp_gpa   <= '0;
            r_rsp_imp   <= '0;
            r_st        <= S_RSP;
          end else begin
            r_m_op  <= OP_READ;
            r_m_pa  <= w_s_addr[PA_WIDTH-1:0];
            r_m_ret <= MR_SPTE;
            r_st    <= S_ISSUE;
          end
        end

        // ---------------------------------------------------------------
        S_G_START: begin
          r_g_lvl  <= 2'd2;
          r_g_base <= PTEP'(r_hgatp_ppn);
          r_st     <= S_G_ADDR;
        end

        S_G_ADDR: begin
          if (|w_g_addr[63:PA_WIDTH]) begin
            r_rsp_st    <= ST_FAULT;          // MMU-28
            r_rsp_cause <= CAUSE_ACCESS;
            r_rsp_gpa   <= '0;
            r_rsp_imp   <= '0;
            r_st        <= S_RSP;
          end else begin
            r_m_op  <= OP_READ;
            r_m_pa  <= w_g_addr[PA_WIDTH-1:0];
            r_m_ret <= MR_GPTE;
            r_st    <= S_ISSUE;
          end
        end

        // ---------------------------------------------------------------
        // One access: checked, then presented until accepted (WM-2).
        // ---------------------------------------------------------------
        S_ISSUE: begin
          if (w_chk_bad) begin
            r_rsp_st    <= ST_FAULT;          // MMU-10d, MMU-12a
            r_rsp_cause <= CAUSE_ACCESS;
            r_rsp_gpa   <= '0;
            r_rsp_imp   <= '0;
            r_st        <= S_RSP;
          end else if (ptw_mem_req_rdy) begin
            r_st <= S_WAIT;
          end
        end

        S_WAIT: begin
          if (mem_ptw_rsp_val) begin
            if (mem_ptw_rsp_err) begin
              r_rsp_st    <= ST_FAULT;        // WM-7
              r_rsp_cause <= CAUSE_ACCESS;
              r_rsp_gpa   <= '0;
              r_rsp_imp   <= '0;
              r_st        <= S_RSP;
            end else begin
              case (r_m_ret)
                MR_SPTE: begin
                  r_s_pte     <= mem_ptw_rsp_data;
                  r_s_pte_spa <= r_m_pa;
                  r_st        <= S_S_EVAL;
                end
                MR_GPTE: begin
                  r_g_pte     <= mem_ptw_rsp_data;
                  r_g_pte_spa <= r_m_pa;
                  r_st        <= S_G_EVAL;
                end
                MR_SCAS: begin
                  // WM-5: the store happened exactly when the old value
                  // equals the compare value. Else restart (MMU-8).
                  if (mem_ptw_rsp_data == r_m_cmp) begin
                    r_s_pte <= r_m_swap;
                    r_st    <= S_S_EVAL;
                  end else begin
                    r_st    <= S_START;
                  end
                end
                default: begin                // MR_GCAS
                  if (mem_ptw_rsp_data == r_m_cmp) begin
                    r_g_pte <= r_m_swap;
                    r_st    <= S_G_EVAL;
                  end else begin
                    r_st    <= S_G_START;
                  end
                end
              endcase
            end
          end
        end

        // ---------------------------------------------------------------
        S_S_EVAL: begin
          if (ws_pf) begin
            r_rsp_st    <= ST_FAULT;
            r_rsp_cause <= CAUSE_PAGE;
            r_rsp_gpa   <= '0;
            r_rsp_imp   <= '0;
            r_st        <= S_RSP;
          end else if (!ws_leaf) begin
            if (r_g_on && ws_next_gwide) begin
              // MMU-28, MMU-30: the next VS-stage table's GPA does not
              // fit; its read is the implicit access that faults.
              r_rsp_st    <= ST_FAULT;
              r_rsp_cause <= CAUSE_GUEST;
              r_rsp_gpa   <= '0;
              r_rsp_imp   <= IMP_READ;
              r_st        <= S_RSP;
            end else if (!r_g_on && ws_next_wide) begin
              r_rsp_st    <= ST_FAULT;        // MMU-28
              r_rsp_cause <= CAUSE_ACCESS;
              r_rsp_gpa   <= '0;
              r_rsp_imp   <= '0;
              r_st        <= S_RSP;
            end else begin
              r_s_base <= ws_ppn;
              r_s_lvl  <= r_s_lvl - 2'd1;
              r_st     <= S_S_ADDR;
            end
          end else if (ws_upd) begin
            r_s_swap <= r_s_pte | (64'd1 << P_A) |
                        ((r_acc == ACC_W) ? (64'd1 << P_D) : 64'd0);
            r_st     <= S_S_UPD;
          end else begin
            r_st <= S_S_FINAL;
          end
        end

        S_S_UPD: begin
          if (r_g_on) begin
            // MMU-8a: a store through the G-stage, implicit WRITE.
            r_g_gpa  <= r_s_pte_gpa;
            r_g_kind <= IMP_WRITE;
            r_g_acc  <= ACC_W;
            r_g_ret  <= GR_SUPD;
            r_st     <= S_G_START;
          end else begin
            r_m_op   <= OP_CAS;
            r_m_pa   <= r_s_pte_spa;
            r_m_cmp  <= r_s_pte;
            r_m_swap <= r_s_swap;
            r_m_ret  <= MR_SCAS;
            r_st     <= S_ISSUE;
          end
        end

        S_S_FINAL: begin
          if (!r_v) begin
            // Single stage: the fetch's own address (MMU-28).
            if (ws_next_wide) begin
              r_rsp_st    <= ST_FAULT;
              r_rsp_cause <= CAUSE_ACCESS;
              r_rsp_gpa   <= '0;
              r_rsp_imp   <= '0;
            end else begin
              r_rsp_st    <= ST_HIT;
              r_rsp_ppn   <= ws_ppn[PPN_WIDTH-1:0];   // IL-7
              r_rsp_size  <= ws_size;
              r_rsp_perm  <= r_s_pte[7:0];
              r_rsp_pbmt  <= r_s_pte[62:61];
            end
            r_st <= S_RSP;
          end else if (!r_g_on) begin
            // VS-stage only: GPA = SPA.
            if (ws_next_wide) begin
              r_rsp_st    <= ST_FAULT;
              r_rsp_cause <= CAUSE_ACCESS;
              r_rsp_gpa   <= '0;
              r_rsp_imp   <= '0;
            end else begin
              r_rsp_st    <= ST_HIT;
              r_rsp_ppn   <= ws_page[PPN_WIDTH-1:0];
              r_rsp_size  <= ws_size;
              r_rsp_perm  <= r_s_pte[7:0];
              r_rsp_pbmt  <= r_s_pte[62:61];
            end
            r_st <= S_RSP;
          end else if (ws_next_gwide) begin
            // MMU-28, MMU-30: the fetch's GPA does not fit 41 bits.
            r_rsp_st    <= ST_FAULT;
            r_rsp_cause <= CAUSE_GUEST;
            r_rsp_gpa   <= '0;
            r_rsp_imp   <= IMP_FETCH;
            r_st        <= S_RSP;
          end else begin
            r_g_gpa  <= {ws_page[GPW-1:0], 12'h000};
            r_g_kind <= IMP_FETCH;
            r_g_acc  <= r_acc;
            r_g_ret  <= GR_FINAL;
            r_st     <= S_G_START;
          end
        end

        // ---------------------------------------------------------------
        S_G_EVAL: begin
          if (wg_gpf) begin
            r_rsp_st    <= ST_FAULT;
            r_rsp_cause <= CAUSE_GUEST;
            r_rsp_gpa   <= r_g_gpa;
            r_rsp_imp   <= r_g_kind;
            r_st        <= S_RSP;
          end else if (!wg_leaf) begin
            if (wg_next_wide) begin
              r_rsp_st    <= ST_FAULT;        // MMU-28
              r_rsp_cause <= CAUSE_ACCESS;
              r_rsp_gpa   <= '0;
              r_rsp_imp   <= '0;
              r_st        <= S_RSP;
            end else begin
              r_g_base <= wg_ppn;
              r_g_lvl  <= r_g_lvl - 2'd1;
              r_st     <= S_G_ADDR;
            end
          end else if (wg_upd) begin
            r_m_op   <= OP_CAS;
            r_m_pa   <= r_g_pte_spa;
            r_m_cmp  <= r_g_pte;
            r_m_swap <= r_g_pte | (64'd1 << P_A) |
                        ((r_g_acc == ACC_W) ? (64'd1 << P_D) : 64'd0);
            r_m_ret  <= MR_GCAS;
            r_st     <= S_ISSUE;
          end else if (|wg_page[PTEP-1:PPN_WIDTH]) begin
            // MMU-28: the result is a supervisor physical page this
            // implementation cannot form; the access made with it, the
            // VS-stage PTE access or the fetch, is an access fault.
            r_rsp_st    <= ST_FAULT;
            r_rsp_cause <= CAUSE_ACCESS;
            r_rsp_gpa   <= '0;
            r_rsp_imp   <= '0;
            r_st        <= S_RSP;
          end else begin
            r_g_res_ppn  <= wg_page[PPN_WIDTH-1:0];
            r_g_res_size <= wg_size;
            r_g_res_pbmt <= r_g_pte[62:61];
            r_g_res_perm <= r_g_pte[7:0];
            case (r_g_ret)
              GR_SREAD: begin
                r_m_op  <= OP_READ;
                r_m_pa  <= {wg_page[PPN_WIDTH-1:0], r_g_gpa[11:0]};
                r_m_ret <= MR_SPTE;
                r_st    <= S_ISSUE;
              end
              GR_SUPD: begin
                r_m_op   <= OP_CAS;
                r_m_pa   <= {wg_page[PPN_WIDTH-1:0], r_g_gpa[11:0]};
                r_m_cmp  <= r_s_pte;
                r_m_swap <= r_s_swap;
                r_m_ret  <= MR_SCAS;
                r_st     <= S_ISSUE;
              end
              default: begin                  // GR_FINAL
                r_rsp_st   <= ST_HIT;
                r_rsp_ppn  <= wg_page[PPN_WIDTH-1:0];
                if (r_s_on) begin
                  // MMU-27: the smaller of the two leaf sizes.
                  r_rsp_size <= (ws_size < wg_size) ? ws_size : wg_size;
                  r_rsp_perm <= r_s_pte[7:0];
                  r_rsp_pbmt <= pbmt_max(r_s_pte[62:61], r_g_pte[62:61]);
                end else begin
                  r_rsp_size <= wg_size;
                  r_rsp_perm <= r_g_pte[7:0] & ~(8'd1 << P_G);
                  r_rsp_pbmt <= r_g_pte[62:61];
                end
                r_st <= S_RSP;
              end
            endcase
          end
        end

        // ---------------------------------------------------------------
        S_RSP: begin
          r_st <= S_IDLE;
        end

        default: r_st <= S_IDLE;
      endcase
    end
  end

endmodule : ptw
