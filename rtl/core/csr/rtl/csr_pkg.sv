// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    csr_pkg.sv
// DATE:    2026-10-13
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// CSR layouts and the CSR group structs (SYS-001). csr_decisions.md
// CSR-1: for each CSR of sections 2 and 3
//   CSR_<NAME>_ADDR   12-bit address
//   <name>_t          packed struct, the full XLEN (64-bit) layout,
//                     most significant field first
//   encodings         MODE values, PMP A-field values
//   CSR_<NAME>_RESET  reset value
// and the three group structs of section 4, fe_cfg_t, fe_csr_t and
// ptw_csr_t, whose members are named and sized as the ports they
// replaced (CSR-6).
//
// WHICH BITS ARE IMPLEMENTED is section 3's table. The structs give
// the architectural layout; a field wider than the implemented subset
// (a PPN, pmpaddr ADDR) is declared at its architectural width and
// the unimplemented high bits read 0. The write rules (CSR-5) are the
// testbench's, csr_tb_pkg.sv; no RTL holds a CSR yet (CSR-U2).
//
// RESET VALUES (CSR-7) are the values tb_fe_top drove at reset when
// the group ports were introduced (SYS-001), its M-mode Bare case:
//   0x7C0    sc_enable 1, every other enable 0
//   0x7C1    0
//   satp     MODE Bare, ASID 0, PPN 0x8F000 (the testbench's root
//            page table, 0x8F00_0000)
//   vsatp    0
//   hgatp    0
//   menvcfg  PBMTE 1, ADUE 0
//   henvcfg  PBMTE 1, ADUE 0
//   pmpcfg0  entry 0 NAPOT with R, W and X (0x1F), entries 1-7 OFF
//   pmpcfg2  0
//   pmpaddr0 every implemented bit set (all of memory)
//   pmpaddr1-15  0
// and the hart state: priv M, V 0. ext_enable is RVA23_ENABLE (CSR-4).
//
// NAMES. Every name here is prefixed CSR_ or ends in _t, so a wildcard
// import cannot shadow a module-local declaration (CLAUDE.md,
// Packages). The custom CSRs are CSR_7C0 and CSR_7C1 until named
// (CSR-U1).
// ===================================================================
`ifndef CSR_PKG_SV
`define CSR_PKG_SV

package csr_pkg;

  // ================================================================
  // Widths. The implemented subsets of section 3, from the existing
  // port widths (bp_defines_pkg).
  // ================================================================
  localparam int CSR_XLEN        = 64;
  localparam int CSR_ADDR_W      = 12;
  localparam int CSR_PMP_ENTRIES = 16;                     // MMU-11
  localparam int CSR_PMP_G       = 10;                     // 4 KiB grain
  // satp.PPN and hgatp.PPN: 23:0, PPN_WIDTH 24
  localparam int CSR_PPN_W       = bp_defines_pkg::PPN_WIDTH;
  // vsatp.PPN: 28:0, GPA_WIDTH 41 - 12
  localparam int CSR_VSATP_PPN_W = bp_defines_pkg::GPA_WIDTH - 12;
  localparam int CSR_ASID_W      = bp_defines_pkg::ASID_WIDTH;  // 16
  localparam int CSR_VMID_W      = bp_defines_pkg::VMID_WIDTH;  // 14
  // pmpaddr.ADDR: 33:0, PA_WIDTH 36 - 2
  localparam int CSR_PMPADDR_W   = bp_defines_pkg::PA_WIDTH - 2;

  // ================================================================
  // Addresses (sections 2 and 3)
  // ================================================================
  localparam logic [CSR_ADDR_W-1:0] CSR_7C0_ADDR      = 12'h7C0;
  localparam logic [CSR_ADDR_W-1:0] CSR_7C1_ADDR      = 12'h7C1;
  localparam logic [CSR_ADDR_W-1:0] CSR_SATP_ADDR     = 12'h180;
  localparam logic [CSR_ADDR_W-1:0] CSR_VSATP_ADDR    = 12'h280;
  localparam logic [CSR_ADDR_W-1:0] CSR_HGATP_ADDR    = 12'h680;
  localparam logic [CSR_ADDR_W-1:0] CSR_MENVCFG_ADDR  = 12'h30A;
  localparam logic [CSR_ADDR_W-1:0] CSR_HENVCFG_ADDR  = 12'h60A;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPCFG0_ADDR  = 12'h3A0;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPCFG2_ADDR  = 12'h3A2;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR0_ADDR  = 12'h3B0;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR1_ADDR  = 12'h3B1;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR2_ADDR  = 12'h3B2;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR3_ADDR  = 12'h3B3;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR4_ADDR  = 12'h3B4;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR5_ADDR  = 12'h3B5;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR6_ADDR  = 12'h3B6;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR7_ADDR  = 12'h3B7;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR8_ADDR  = 12'h3B8;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR9_ADDR  = 12'h3B9;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR10_ADDR = 12'h3BA;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR11_ADDR = 12'h3BB;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR12_ADDR = 12'h3BC;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR13_ADDR = 12'h3BD;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR14_ADDR = 12'h3BE;
  localparam logic [CSR_ADDR_W-1:0] CSR_PMPADDR15_ADDR = 12'h3BF;

  // ================================================================
  // Encodings
  // ================================================================
  // satp.MODE and vsatp.MODE
  localparam logic [3:0] CSR_SATP_MODE_BARE    = 4'd0;
  localparam logic [3:0] CSR_SATP_MODE_SV39    = 4'd8;
  // hgatp.MODE
  localparam logic [3:0] CSR_HGATP_MODE_BARE   = 4'd0;
  localparam logic [3:0] CSR_HGATP_MODE_SV39X4 = 4'd8;
  // pmpcfg A field. NA4 is not selectable at G = 10 (section 3).
  localparam logic [1:0] CSR_PMP_A_OFF   = 2'd0;
  localparam logic [1:0] CSR_PMP_A_TOR   = 2'd1;
  localparam logic [1:0] CSR_PMP_A_NA4   = 2'd2;
  localparam logic [1:0] CSR_PMP_A_NAPOT = 2'd3;
  // priv, hart state and not a CSR (section 3)
  localparam logic [1:0] CSR_PRV_U = 2'b00;
  localparam logic [1:0] CSR_PRV_S = 2'b01;
  localparam logic [1:0] CSR_PRV_M = 2'b11;

  // ================================================================
  // Layouts. Full XLEN, most significant field first.
  // ================================================================
  // 0x7C0 CSR_7C0, predictor enables (section 2)
  typedef struct packed {
    logic [63:4] rsvd;                 // read 0, writes ignored
    logic        ittage_enable_aging;  // 3
    logic        tage_enable_aging;    // 2
    logic        ftb_fastpath_en;      // 1
    logic        sc_enable;            // 0, CSR-3
  } csr_7c0_t;

  // 0x7C1 CSR_7C1, aging intervals (section 2)
  typedef struct packed {
    logic [31:0] ittage_aging_interval;  // 63:32
    logic [31:0] tage_aging_interval;    // 31:0
  } csr_7c1_t;

  // 0x180 satp. PPN 23:0 implemented.
  typedef struct packed {
    logic [3:0]  mode;                 // 63:60
    logic [15:0] asid;                 // 59:44
    logic [43:0] ppn;                  // 43:0
  } satp_t;

  // 0x280 vsatp. PPN 28:0 implemented.
  typedef struct packed {
    logic [3:0]  mode;                 // 63:60
    logic [15:0] asid;                 // 59:44
    logic [43:0] ppn;                  // 43:0
  } vsatp_t;

  // 0x680 hgatp. PPN 23:0 implemented; 1:0 read 0 in Sv39x4.
  typedef struct packed {
    logic [3:0]  mode;                 // 63:60
    logic [1:0]  rsvd;                 // 59:58, read 0
    logic [13:0] vmid;                 // 57:44
    logic [43:0] ppn;                  // 43:0
  } hgatp_t;

  // 0x30A menvcfg. PBMTE and ADUE implemented.
  typedef struct packed {
    logic        stce;                 // 63, not implemented, read 0
    logic        pbmte;                // 62
    logic        adue;                 // 61
    logic [60:0] rsvd;                 // 60:0, not implemented, read 0
  } menvcfg_t;

  // 0x60A henvcfg. PBMTE and ADUE implemented; ADUE reads 0 when
  // menvcfg.ADUE is 0 (CSR-5).
  typedef struct packed {
    logic        stce;                 // 63, not implemented, read 0
    logic        pbmte;                // 62
    logic        adue;                 // 61
    logic [60:0] rsvd;                 // 60:0, not implemented, read 0
  } henvcfg_t;

  // One pmpcfg entry, one byte.
  typedef struct packed {
    logic       l;                     // 7
    logic [1:0] rsvd;                  // 6:5, read 0
    logic [1:0] a;                     // 4:3, CSR_PMP_A_*
    logic       x;                     // 2
    logic       w;                     // 1
    logic       r;                     // 0
  } pmpcfg_ent_t;

  // 0x3A0 pmpcfg0 (entries 0-7), 0x3A2 pmpcfg2 (entries 8-15). Entry
  // k of the register is byte k.
  typedef struct packed {
    pmpcfg_ent_t [7:0] ent;
  } pmpcfg_t;

  // 0x3B0-0x3BF pmpaddr0-15. ADDR 33:0 implemented (PA_WIDTH 36).
  typedef struct packed {
    logic [9:0]  rsvd;                 // 63:54, read 0
    logic [53:0] addr;                 // 53:0
  } pmpaddr_t;

  // The implemented pmpaddr field, the width of the group members and
  // of the PMP checker's address input.
  typedef logic [CSR_PMPADDR_W-1:0] pmpaddr_imp_t;

  // ================================================================
  // Reset values (CSR-7). See the header.
  // ================================================================
  localparam logic [63:0] CSR_7C0_RESET     = 64'h0000_0000_0000_0001;
  localparam logic [63:0] CSR_7C1_RESET     = 64'h0;
  localparam logic [63:0] CSR_SATP_RESET    = 64'h0000_0000_0008_F000;
  localparam logic [63:0] CSR_VSATP_RESET   = 64'h0;
  localparam logic [63:0] CSR_HGATP_RESET   = 64'h0;
  localparam logic [63:0] CSR_MENVCFG_RESET = 64'h4000_0000_0000_0000;
  localparam logic [63:0] CSR_HENVCFG_RESET = 64'h4000_0000_0000_0000;
  localparam logic [63:0] CSR_PMPCFG0_RESET = 64'h0000_0000_0000_001F;
  localparam logic [63:0] CSR_PMPCFG2_RESET = 64'h0;
  localparam logic [63:0] CSR_PMPADDR0_RESET =
    64'(pmpaddr_imp_t'('1));
  localparam logic [63:0] CSR_PMPADDRN_RESET = 64'h0;   // 1 to 15
  localparam logic [1:0]  CSR_PRV_RESET     = CSR_PRV_M;
  localparam logic        CSR_V_RESET       = 1'b0;

  // ================================================================
  // Group structs (section 4, CSR-6). Members are named and sized as
  // the ports they replaced, in the same order.
  // ================================================================
  // Source 0x7C0, 0x7C1, ext_enable. fe_top distributes it.
  typedef struct packed {
    logic                      sc_enable;              // bp_cluster, FTQ
    logic                      ftb_fastpath_en;        // bp_cluster
    logic                      tage_enable_aging;      // tage
    logic [31:0]               tage_aging_interval;    // tage
    logic                      ittage_enable_aging;    // ittage
    logic [31:0]               ittage_aging_interval;  // ittage
    decode_pkg::ext_enable_t   ext_enable;             // decode, CSR-4
  } fe_cfg_t;

  // Source satp, vsatp, hgatp, pmpcfg, pmpaddr, priv, V. fe_top passes
  // it to the ITLB, whose PMP checker takes priv, pmpcfg and pmpaddr.
  typedef struct packed {
    logic                                    v;
    logic [1:0]                              priv;     // CSR_PRV_*
    logic [3:0]                              satp_mode;
    logic [CSR_ASID_W-1:0]                   satp_asid;
    logic [3:0]                              vsatp_mode;
    logic [CSR_ASID_W-1:0]                   vsatp_asid;
    logic [3:0]                              hgatp_mode;
    logic [CSR_VMID_W-1:0]                   hgatp_vmid;
    pmpcfg_ent_t  [CSR_PMP_ENTRIES-1:0]      pmpcfg;
    pmpaddr_imp_t [CSR_PMP_ENTRIES-1:0]      pmpaddr;
  } fe_csr_t;

  // Source satp, vsatp, hgatp, menvcfg, henvcfg, pmpcfg, pmpaddr. The
  // walker takes it directly; its PMP checker takes pmpcfg and pmpaddr.
  typedef struct packed {
    logic [3:0]                              satp_mode;
    logic [CSR_PPN_W-1:0]                    satp_ppn;
    logic [3:0]                              vsatp_mode;
    logic [CSR_VSATP_PPN_W-1:0]              vsatp_ppn;
    logic [3:0]                              hgatp_mode;
    logic [CSR_PPN_W-1:0]                    hgatp_ppn;
    logic                                    menvcfg_adue;
    logic                                    henvcfg_adue;
    logic                                    menvcfg_pbmte;
    logic                                    henvcfg_pbmte;
    pmpcfg_ent_t  [CSR_PMP_ENTRIES-1:0]      pmpcfg;
    pmpaddr_imp_t [CSR_PMP_ENTRIES-1:0]      pmpaddr;
  } ptw_csr_t;

endpackage : csr_pkg

`endif // CSR_PKG_SV
