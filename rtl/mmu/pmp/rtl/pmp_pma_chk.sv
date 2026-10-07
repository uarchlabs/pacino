// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// PMP and PMA checker (BP-118). mmu_decisions.md MMU-10, MMU-10a,
// MMU-10b, MMU-11, MMU-11a, MMU-12 to MMU-15a, MMU-U6.
//
// ONE CHECKER, INSTANTIATED TWICE (MMU-10a). Site 1 is beside the
// ITLB, on the translated physical address of every hit and every
// Bare fetch. Site 2 will be inside the walker, on every address it
// issues. The module holds no state: the PMP registers and the
// privilege arrive on an input group (MMU-11a) and the region table
// is a parameter (MMU-15a). Combinational, so no clk or rstn.
//
// ONE GRANULE PER CHECK. chk_pa names one PMP granule,
// 2**PMP_GRAN_LG2 bytes. The default grain is 4 KiB (PMP G = 10), so
// every PMP region boundary is page aligned and a check on a page
// base answers for the whole page. That is what lets the ITLB check
// a page it knows only by its PPN (itlb_ifu_interfaces.md IT-16
// carries no offset). The caller must not span granules. The
// privileged specification lets the platform choose G; spike models
// it as lg_pmp_granularity (tools/spike/riscv/mmu.cc pmp_ok).
//
// PMP RULES, each from tools/spike/riscv as the reference the task
// permits:
//   - TOR: entry i matches base <= pa < top, base the previous
//     entry's pmpaddr (0 for entry 0) and top its own, both with the
//     low G bits cleared. csrs.cc pmpaddr_csr_t::match4,
//     tor_base_paddr, tor_paddr.
//   - NAPOT: the trailing ones of {pmpaddr, 1}, widened by the G low
//     ones the granule forces, give the ignored address bits.
//     csrs.cc pmpaddr_csr_t::napot_mask. NA4 is not selectable for
//     G >= 1 and is matched the way napot_mask computes it, which at
//     G >= 1 is the same mask as NAPOT.
//   - OFF (A = 0) never matches. csrs.cc match4.
//   - the LOWEST-NUMBERED matching entry decides. mmu.cc pmp_ok, the
//     first any_match returns.
//   - L: a matching entry with L clear grants M-mode everything; with
//     L set M-mode is held to R, W and X like S and U.
//     csrs.cc pmpaddr_csr_t::access_ok, m_bypass.
//   - no match: M-mode allowed, S and U denied when at least one
//     entry is implemented; with none implemented every access is
//     allowed. mmu.cc pmp_ok, the n_pmp == 0 return and the final
//     return. mseccfg (Smepmp) is not implemented (MMU-U4).
//
// PMA (MMU-13, MMU-15, MMU-15a). The first region whose inclusive
// range [PMA_BASE, PMA_TOP] holds chk_pa gives its PMA_ATTR, and an
// address in no region takes PMA_DFLT. Bit positions are MMU-13:
// [0] cacheable, [1] coherent, [2] executable, [3] idempotent.
// Region bounds must be granule aligned for the same reason as the
// PMP grain.
//
// EFFECTIVE TYPE (MMU-U6, IT-10). The most restrictive of the region
// and chk_pbmt, ordered PMA < NC < IO. NC clears cacheable; IO
// clears cacheable and idempotent. Executable and coherent come from
// the region alone. PBMT 2'b11 is reserved and never reaches the
// ITLB (IL-9a); if it did it is taken as IO, the most restrictive.
//
// chk_fault is the instruction access fault of MMU-16, cause 1: the
// PMP denies the access, or an execute access lands in a region
// that is not executable. A read or write is faulted by the PMP
// only; MMU-13 has no readable or writable attribute.
//
// Written as single continuous assigns over one function so no
// assign reads another (CLAUDE.md, combinational logic style).
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module pmp_pma_chk #(
  parameter int PMP_ENTRIES  = 16,                      // MMU-11
  parameter int PMP_GRAN_LG2 = 12,                      // 4 KiB grain
  parameter int PMA_REGIONS  = 1,                       // MMU-15a
  parameter logic [PMA_REGIONS-1:0][PA_WIDTH-1:0]  PMA_BASE =
    {36'h0_8000_0000},
  parameter logic [PMA_REGIONS-1:0][PA_WIDTH-1:0]  PMA_TOP  =
    {36'hF_FFFF_FFFF},
  parameter logic [PMA_REGIONS-1:0][PMA_WIDTH-1:0] PMA_ATTR = {4'b1111},
  parameter logic [PMA_WIDTH-1:0]                  PMA_DFLT = 4'b0000
) (
  // ---- the access ---------------------------------------------------
  input  logic [PA_WIDTH-1:0]   chk_pa,
  input  logic [1:0]            chk_acc,   // ACC_R, ACC_W, ACC_X
  input  logic [1:0]            chk_priv,  // 0 U, 1 S, 3 M
  input  logic [1:0]            chk_pbmt,  // 0 PMA, 1 NC, 2 IO

  // ---- MMU-11a, the PMP registers ----------------------------------
  // pmpaddr holds PA[PA_WIDTH-1:2]; higher pmpaddr bits are WARL zero
  // at PA_WIDTH 36. One entry is declared when PMP_ENTRIES is 0 so
  // the ports keep a legal shape; it is never read.
  input  logic [((PMP_ENTRIES > 0) ? PMP_ENTRIES : 1)-1:0][7:0]
                                pmp_cfg,
  input  logic [((PMP_ENTRIES > 0) ? PMP_ENTRIES : 1)-1:0][PA_WIDTH-3:0]
                                pmp_addr,

  // ---- results ------------------------------------------------------
  output logic                  chk_pmp_ok,
  output logic [PMA_WIDTH-1:0]  chk_pma,   // effective, MMU-U6
  output logic                  chk_fault  // cause 1
);

  localparam int PMP_N  = (PMP_ENTRIES > 0) ? PMP_ENTRIES : 1;
  localparam int AW     = PA_WIDTH - 2;     // pmpaddr width
  localparam int G      = PMP_GRAN_LG2 - 2; // the specification's G

  // Access types.
  localparam logic [1:0] ACC_R = 2'd0;
  localparam logic [1:0] ACC_W = 2'd1;
  localparam logic [1:0] ACC_X = 2'd2;

  localparam logic [1:0] PRV_M = 2'd3;

  // pmpcfg fields.
  localparam int CFG_R = 0;
  localparam int CFG_W = 1;
  localparam int CFG_X = 2;
  localparam int CFG_L = 7;
  localparam logic [1:0] A_OFF = 2'd0;
  localparam logic [1:0] A_TOR = 2'd1;
  localparam logic [1:0] A_NA4 = 2'd2;

  // PBMT encodings, Svpbmt.
  localparam logic [1:0] PBMT_NC = 2'd1;

  localparam int PMA_CACHEABLE  = 0;
  localparam int PMA_EXECUTABLE = 2;
  localparam int PMA_IDEMPOTENT = 3;

  // The low G pmpaddr bits: cleared for TOR, forced to ones in the
  // NAPOT mask (spike pmp_tor_mask and its complement).
  localparam logic [AW-1:0] TOR_MASK = ~AW'((64'd1 << G) - 64'd1);
  localparam logic [AW:0]   LOW_G    = (AW+1)'((64'd1 << G) - 64'd1);

  initial begin
    if (PMP_GRAN_LG2 < 2) $error("pmp_pma_chk: PMP_GRAN_LG2 below 2");
  end

  // -----------------------------------------------------------------
  // PMP. Returns {ok}. See the header for the rule references.
  // -----------------------------------------------------------------
  function automatic logic pmp_decide(
      input logic [PA_WIDTH-1:0]          pa,
      input logic [1:0]                   acc,
      input logic [1:0]                   prv,
      input logic [PMP_N-1:0][7:0]        cfg,
      input logic [PMP_N-1:0][AW-1:0]     addr);
    logic          found;
    logic          ok;
    logic          match;
    logic          rwx;
    logic [1:0]    a;
    logic [PA_WIDTH-1:0] base;
    logic [PA_WIDTH-1:0] top;
    logic [AW:0]   mk;
    logic [AW:0]   t;
    logic [PA_WIDTH-1:0] keep;

    found = 1'b0;
    ok    = 1'b0;
    for (int i = 0; i < PMP_ENTRIES; i++) begin
      a     = cfg[i][4:3];
      top   = {addr[i] & TOR_MASK, 2'b00};
      base  = (i == 0) ? '0
                       : {addr[(i == 0) ? 0 : i-1] & TOR_MASK, 2'b00};
      // NAPOT / NA4: ignored bits are the trailing ones of mk.
      mk    = {addr[i], (a != A_NA4)} | LOW_G;
      t     = mk & ~(mk + 1'b1);
      keep  = {~t[AW-1:0], 2'b00};
      if (a == A_OFF)      match = 1'b0;
      else if (a == A_TOR) match = (pa >= base) && (pa < top);
      else                 match = ((pa ^ top) & keep) == '0;

      rwx = ((acc == ACC_R) && cfg[i][CFG_R]) ||
            ((acc == ACC_W) && cfg[i][CFG_W]) ||
            ((acc == ACC_X) && cfg[i][CFG_X]);
      if (match && !found) begin
        found = 1'b1;
        ok    = ((prv == PRV_M) && !cfg[i][CFG_L]) || rwx;
      end
    end
    if (!found) ok = (PMP_ENTRIES == 0) || (prv == PRV_M);
    return ok;
  endfunction

  // -----------------------------------------------------------------
  // PMA. The region attribute combined with the PBMT.
  // -----------------------------------------------------------------
  function automatic logic [PMA_WIDTH-1:0] pma_eff(
      input logic [PA_WIDTH-1:0] pa,
      input logic [1:0]          pbmt);
    logic                 found;
    logic [PMA_WIDTH-1:0] r;
    found = 1'b0;
    r     = PMA_DFLT;
    for (int k = 0; k < PMA_REGIONS; k++) begin
      if (!found && (pa >= PMA_BASE[k]) && (pa <= PMA_TOP[k])) begin
        found = 1'b1;
        r     = PMA_ATTR[k];
      end
    end
    // MMU-U6: NC and IO are never cacheable; IO (and the reserved
    // encoding) is never idempotent.
    if (pbmt != 2'd0)    r[PMA_CACHEABLE]  = 1'b0;
    if (pbmt > PBMT_NC)  r[PMA_IDEMPOTENT] = 1'b0;
    return r;
  endfunction

  // The cause-1 decision of the header: PMP denial, or an execute
  // access to a region that is not executable.
  function automatic logic fault_of(
      input logic                 pmp_ok,
      input logic [1:0]           acc,
      input logic [PMA_WIDTH-1:0] pma);
    return !pmp_ok || ((acc == ACC_X) && !pma[PMA_EXECUTABLE]);
  endfunction

  assign chk_pmp_ok = pmp_decide(chk_pa, chk_acc, chk_priv, pmp_cfg,
                                 pmp_addr);
  assign chk_pma    = pma_eff(chk_pa, chk_pbmt);
  assign chk_fault  = fault_of(pmp_decide(chk_pa, chk_acc, chk_priv,
                                          pmp_cfg, pmp_addr),
                               chk_acc, pma_eff(chk_pa, chk_pbmt));

endmodule : pmp_pma_chk
