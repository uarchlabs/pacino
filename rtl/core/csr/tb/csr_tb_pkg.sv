// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    csr_tb_pkg.sv
// DATE:    2026-10-13
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// TESTBENCH ONLY (SYS-001, csr_decisions.md CSR-2). A shadow of every
// CSR in csr_pkg, written and read by address under the CSR-5 rules,
// and the pack functions that turn the shadow into the group structs
// a testbench drives:
//   csr_write(addr, value)    CSR-5 write rules
//   csr_read(addr)            the value software would read
//   pack_fe_cfg()             shadow -> fe_cfg_t
//   pack_fe_csr()             shadow -> fe_csr_t
//   pack_ptw_csr()            shadow -> ptw_csr_t
//   set_ext_enable(v)         ext_enable has no address (CSR-4)
//   set_<field>(v)            each field of 0x7C0 and 0x7C1
// SYS-001 additions, not in CSR-2 (provisional, see Results Capture):
//   csr_reset()               every CSR, priv, V and ext_enable to
//                             its csr_pkg reset value. A testbench
//                             calls it at its own reset; the shadow
//                             also starts at these values
//   set_priv(p), set_v(v)     priv and V are hart state, not CSRs
//                             (section 3), and are fe_csr_t members
//   set_pmp_g(g)              the PMP grain the read-back rules use,
//                             10 unless a PMP checker testbench builds
//                             an instance at another grain
//
// WRITE RULES (CSR-5), applied by csr_write:
//   satp     unsupported MODE (not Bare or Sv39): no field written
//   vsatp    unsupported MODE: no field written (PROPOSED in CSR-5)
//   hgatp    unsupported MODE (not Bare or Sv39x4): MODE unchanged,
//            VMID and PPN written
//   pmpcfg   locked entry (L = 1): entry and its pmpaddr not written
//   all      unimplemented bits read 0: they are never stored
// and by csr_read, since they depend on other state at read time:
//   pmpaddr  NAPOT entry: bits 8:0 read 1; OFF or TOR entry: bits 9:0
//            read 0 (G = 10; set_pmp_g gives the same rule at another
//            G)
//   hgatp    PPN 1:0 read 0 when MODE is Sv39x4 (section 3)
//   henvcfg  ADUE reads 0 when menvcfg.ADUE is 0 (section 3)
// A pmpcfg write of A = NA4 stores NAPOT: NA4 is not selectable at
// G = 10 (section 3; at any G >= 1), and the WARL result is not given
// there; spike maps it the same way (riscv/csrs.cc
// pmpcfg_csr_t::unlogged_write). Provisional.
//
// An address with no CSR here is a testbench error: csr_write and
// csr_read stop the simulation with $fatal.
//
// The pack functions read through csr_read, so a group member always
// carries the value software would read.
//
// THE SHADOW IS A CLASS, csr_shadow, with static state and static
// methods; the package functions at the end of the file are one-line
// calls into it. Package functions and tasks are inlined at each call
// site by the simulator, and a testbench that drives the groups from
// many places (tb_fe_top) then builds C++ that takes minutes to
// compile. A class method is compiled once (the reason tb_fe_top's
// program writer is a class).
// ===================================================================
`ifndef CSR_TB_PKG_SV
`define CSR_TB_PKG_SV

package csr_tb_pkg;

  import csr_pkg::*;

  class csr_shadow;

    // ================================================================
    // The shadow. Only implemented bits are ever set.
    // ================================================================
    static csr_7c0_t                 r_7c0     = csr_7c0_t'(CSR_7C0_RESET);
    static csr_7c1_t                 r_7c1     = csr_7c1_t'(CSR_7C1_RESET);
    static satp_t                    r_satp    = satp_t'(CSR_SATP_RESET);
    static vsatp_t                   r_vsatp   = vsatp_t'(CSR_VSATP_RESET);
    static hgatp_t                   r_hgatp   = hgatp_t'(CSR_HGATP_RESET);
    static menvcfg_t                 r_menvcfg = menvcfg_t'(CSR_MENVCFG_RESET);
    static henvcfg_t                 r_henvcfg = henvcfg_t'(CSR_HENVCFG_RESET);
    static pmpcfg_ent_t  [CSR_PMP_ENTRIES-1:0] r_pmpcfg =
      {pmpcfg_t'(CSR_PMPCFG2_RESET), pmpcfg_t'(CSR_PMPCFG0_RESET)};
    static pmpaddr_imp_t [CSR_PMP_ENTRIES-1:0] r_pmpaddr =
      {{(CSR_PMP_ENTRIES-1){pmpaddr_imp_t'(CSR_PMPADDRN_RESET)}},
       pmpaddr_imp_t'(CSR_PMPADDR0_RESET)};
    static logic [1:0]               r_priv    = CSR_PRV_RESET;
    static logic                     r_v       = CSR_V_RESET;
    static decode_pkg::ext_enable_t  r_ext     = decode_pkg::RVA23_ENABLE;
    static int                       r_pmp_g   = CSR_PMP_G;

    // ================================================================
    // Helpers
    // ================================================================
    static function logic is_pmpaddr(input logic [CSR_ADDR_W-1:0] a);
      return (a >= CSR_PMPADDR0_ADDR) && (a <= CSR_PMPADDR15_ADDR);
    endfunction

    // The pmpaddr read-back of entry k (CSR-5): with G = 10, a NAPOT
    // entry reads bits 8:0 as 1 and an OFF or TOR entry bits 9:0 as 0.
    // The privileged rule in G: NAPOT bits G-2:0 read 1 when G >= 2,
    // OFF and TOR bits G-1:0 read 0 when G >= 1.
    static function pmpaddr_imp_t pmpaddr_rd(input int k);
      pmpaddr_imp_t v;
      pmpaddr_imp_t m;
      v = r_pmpaddr[k];
      if (r_pmpcfg[k].a == CSR_PMP_A_NAPOT) begin
        m = (r_pmp_g >= 2) ? pmpaddr_imp_t'((64'd1 << (r_pmp_g - 1)) - 1)
                           : '0;
        v = v | m;
      end else if (r_pmpcfg[k].a != CSR_PMP_A_NA4) begin
        m = (r_pmp_g >= 1) ? pmpaddr_imp_t'((64'd1 << r_pmp_g) - 1) : '0;
        v = v & ~m;
      end
      return v;
    endfunction

    // One pmpcfg byte as stored: reserved bits 0, and NA4 taken as NAPOT
    // when NA4 is not selectable (G >= 1).
    static function pmpcfg_ent_t pmpcfg_legal(input logic [7:0] b);
      pmpcfg_ent_t e;
      e      = pmpcfg_ent_t'(b);
      e.rsvd = '0;
      if ((e.a == CSR_PMP_A_NA4) && (r_pmp_g >= 1)) e.a = CSR_PMP_A_NAPOT;
      return e;
    endfunction

    // The PMP grain G (SYS-001 addition, provisional). csr_pkg's is 10,
    // the 4 KiB grain of this implementation. Only a testbench of the
    // PMP checker built at another PMP_GRAN_LG2 sets it, to that
    // instance's PMP_GRAN_LG2 - 2; csr_reset restores 10.
    static function void set_pmp_g(input int g);
      if ((g < 0) || (g > CSR_PMPADDR_W))
        $fatal(1, "csr_tb_pkg: set_pmp_g(%0d) out of range", g);
      r_pmp_g = g;
    endfunction

    // ================================================================
    // csr_reset (SYS-001 addition)
    // ================================================================
    static function void csr_reset();
      r_7c0     = csr_7c0_t'(CSR_7C0_RESET);
      r_7c1     = csr_7c1_t'(CSR_7C1_RESET);
      r_satp    = satp_t'(CSR_SATP_RESET);
      r_vsatp   = vsatp_t'(CSR_VSATP_RESET);
      r_hgatp   = hgatp_t'(CSR_HGATP_RESET);
      r_menvcfg = menvcfg_t'(CSR_MENVCFG_RESET);
      r_henvcfg = henvcfg_t'(CSR_HENVCFG_RESET);
      r_pmpcfg  = {pmpcfg_t'(CSR_PMPCFG2_RESET),
                   pmpcfg_t'(CSR_PMPCFG0_RESET)};
      for (int k = 0; k < CSR_PMP_ENTRIES; k++) begin
        r_pmpaddr[k] = pmpaddr_imp_t'(CSR_PMPADDRN_RESET);
      end
      r_pmpaddr[0] = pmpaddr_imp_t'(CSR_PMPADDR0_RESET);
      r_priv    = CSR_PRV_RESET;
      r_v       = CSR_V_RESET;
      r_ext     = decode_pkg::RVA23_ENABLE;
      r_pmp_g   = CSR_PMP_G;
    endfunction

    // ================================================================
    // csr_write (CSR-5)
    // ================================================================
    static function void csr_write(input logic [CSR_ADDR_W-1:0] addr,
                                   input logic [63:0] value);
      logic [3:0] mode;
      int         k;
      int         base;
      mode = value[63:60];
      if (is_pmpaddr(addr)) begin
        k = int'(addr[3:0]);
        if (!r_pmpcfg[k].l) r_pmpaddr[k] = value[CSR_PMPADDR_W-1:0];
        return;
      end
      case (addr)
        CSR_7C0_ADDR: begin
          r_7c0      = csr_7c0_t'(value);
          r_7c0.rsvd = '0;                         // 63:4 writes ignored
        end
        CSR_7C1_ADDR: r_7c1 = csr_7c1_t'(value);
        CSR_SATP_ADDR: begin
          // unsupported MODE: no field written
          if ((mode == CSR_SATP_MODE_BARE) || (mode == CSR_SATP_MODE_SV39))
          begin
            r_satp      = '0;
            r_satp.mode = mode;
            r_satp.asid = value[59:44];
            r_satp.ppn  = 44'(value[CSR_PPN_W-1:0]);
          end
        end
        CSR_VSATP_ADDR: begin
          // unsupported MODE: no field written (PROPOSED)
          if ((mode == CSR_SATP_MODE_BARE) || (mode == CSR_SATP_MODE_SV39))
          begin
            r_vsatp      = '0;
            r_vsatp.mode = mode;
            r_vsatp.asid = value[59:44];
            r_vsatp.ppn  = 44'(value[CSR_VSATP_PPN_W-1:0]);
          end
        end
        CSR_HGATP_ADDR: begin
          // unsupported MODE: MODE unchanged, VMID and PPN written
          if ((mode == CSR_HGATP_MODE_BARE) ||
              (mode == CSR_HGATP_MODE_SV39X4)) begin
            r_hgatp.mode = mode;
          end
          r_hgatp.rsvd = '0;
          r_hgatp.vmid = value[57:44];
          r_hgatp.ppn  = 44'(value[CSR_PPN_W-1:0]);
        end
        CSR_MENVCFG_ADDR: begin
          r_menvcfg       = '0;
          r_menvcfg.pbmte = value[62];
          r_menvcfg.adue  = value[61];
        end
        CSR_HENVCFG_ADDR: begin
          r_henvcfg       = '0;
          r_henvcfg.pbmte = value[62];
          r_henvcfg.adue  = value[61];
        end
        CSR_PMPCFG0_ADDR, CSR_PMPCFG2_ADDR: begin
          // locked entry: not written
          base = (addr == CSR_PMPCFG0_ADDR) ? 0 : 8;
          for (int i = 0; i < 8; i++) begin
            if (!r_pmpcfg[base + i].l) begin
              r_pmpcfg[base + i] = pmpcfg_legal(value[8*i +: 8]);
            end
          end
        end
        default: $fatal(1, "csr_tb_pkg: csr_write to 0x%03h, no such CSR",
                        addr);
      endcase
    endfunction

    // ================================================================
    // csr_read
    // ================================================================
    static function logic [63:0] csr_read(
        input logic [CSR_ADDR_W-1:0] addr);
      logic [63:0] v;
      hgatp_t      hg;
      henvcfg_t    he;
      pmpcfg_t     pc;
      int          base;
      if (is_pmpaddr(addr)) begin
        return 64'(pmpaddr_rd(int'(addr[3:0])));
      end
      v = '0;
      case (addr)
        CSR_7C0_ADDR:     v = 64'(r_7c0);
        CSR_7C1_ADDR:     v = 64'(r_7c1);
        CSR_SATP_ADDR:    v = 64'(r_satp);
        CSR_VSATP_ADDR:   v = 64'(r_vsatp);
        CSR_HGATP_ADDR: begin
          hg = r_hgatp;
          if (hg.mode == CSR_HGATP_MODE_SV39X4) hg.ppn[1:0] = 2'b00;
          v = 64'(hg);
        end
        CSR_MENVCFG_ADDR: v = 64'(r_menvcfg);
        CSR_HENVCFG_ADDR: begin
          he = r_henvcfg;
          if (!r_menvcfg.adue) he.adue = 1'b0;
          v = 64'(he);
        end
        CSR_PMPCFG0_ADDR, CSR_PMPCFG2_ADDR: begin
          base = (addr == CSR_PMPCFG0_ADDR) ? 0 : 8;
          for (int i = 0; i < 8; i++) pc.ent[i] = r_pmpcfg[base + i];
          v = 64'(pc);
        end
        default: $fatal(1, "csr_tb_pkg: csr_read of 0x%03h, no such CSR",
                        addr);
      endcase
      return v;
    endfunction

    // ================================================================
    // Hart state and ext_enable (no address)
    // ================================================================
    static function void set_priv(input logic [1:0] p);
      if (p == 2'b10) $fatal(1, "csr_tb_pkg: set_priv 2'b10 is reserved");
      r_priv = p;
    endfunction

    static function void set_v(input logic v);
      r_v = v;
    endfunction

    static function void set_ext_enable(
        input decode_pkg::ext_enable_t v);
      r_ext = v;
    endfunction

    // ================================================================
    // Named setters, 0x7C0 and 0x7C1. Each is a read-modify-write
    // through csr_write.
    // ================================================================
    static function void set_sc_enable(input logic b);
      csr_7c0_t c;
      c = csr_7c0_t'(csr_read(CSR_7C0_ADDR));
      c.sc_enable = b;
      csr_write(CSR_7C0_ADDR, 64'(c));
    endfunction

    static function void set_ftb_fastpath_en(input logic b);
      csr_7c0_t c;
      c = csr_7c0_t'(csr_read(CSR_7C0_ADDR));
      c.ftb_fastpath_en = b;
      csr_write(CSR_7C0_ADDR, 64'(c));
    endfunction

    static function void set_tage_enable_aging(input logic b);
      csr_7c0_t c;
      c = csr_7c0_t'(csr_read(CSR_7C0_ADDR));
      c.tage_enable_aging = b;
      csr_write(CSR_7C0_ADDR, 64'(c));
    endfunction

    static function void set_ittage_enable_aging(input logic b);
      csr_7c0_t c;
      c = csr_7c0_t'(csr_read(CSR_7C0_ADDR));
      c.ittage_enable_aging = b;
      csr_write(CSR_7C0_ADDR, 64'(c));
    endfunction

    static function void set_tage_aging_interval(input logic [31:0] n);
      csr_7c1_t c;
      c = csr_7c1_t'(csr_read(CSR_7C1_ADDR));
      c.tage_aging_interval = n;
      csr_write(CSR_7C1_ADDR, 64'(c));
    endfunction

    static function void set_ittage_aging_interval(
        input logic [31:0] n);
      csr_7c1_t c;
      c = csr_7c1_t'(csr_read(CSR_7C1_ADDR));
      c.ittage_aging_interval = n;
      csr_write(CSR_7C1_ADDR, 64'(c));
    endfunction

    // ================================================================
    // Pack functions. Every member is taken from csr_read, the value
    // software would read.
    // ================================================================
    static function fe_cfg_t pack_fe_cfg();
      fe_cfg_t  g;
      csr_7c0_t c0;
      csr_7c1_t c1;
      c0 = csr_7c0_t'(csr_read(CSR_7C0_ADDR));
      c1 = csr_7c1_t'(csr_read(CSR_7C1_ADDR));
      g.sc_enable             = c0.sc_enable;
      g.ftb_fastpath_en       = c0.ftb_fastpath_en;
      g.tage_enable_aging     = c0.tage_enable_aging;
      g.tage_aging_interval   = c1.tage_aging_interval;
      g.ittage_enable_aging   = c0.ittage_enable_aging;
      g.ittage_aging_interval = c1.ittage_aging_interval;
      g.ext_enable            = r_ext;
      return g;
    endfunction

    // pmpcfg entry k as read.
    static function pmpcfg_ent_t pmpcfg_rd(input int k);
      pmpcfg_t pc;
      pc = pmpcfg_t'(csr_read((k < 8) ? CSR_PMPCFG0_ADDR
                                      : CSR_PMPCFG2_ADDR));
      return pc.ent[k % 8];
    endfunction

    static function fe_csr_t pack_fe_csr();
      fe_csr_t g;
      satp_t   s;
      vsatp_t  vs;
      hgatp_t  hg;
      s  = satp_t'(csr_read(CSR_SATP_ADDR));
      vs = vsatp_t'(csr_read(CSR_VSATP_ADDR));
      hg = hgatp_t'(csr_read(CSR_HGATP_ADDR));
      g.v          = r_v;
      g.priv       = r_priv;
      g.satp_mode  = s.mode;
      g.satp_asid  = s.asid[CSR_ASID_W-1:0];
      g.vsatp_mode = vs.mode;
      g.vsatp_asid = vs.asid[CSR_ASID_W-1:0];
      g.hgatp_mode = hg.mode;
      g.hgatp_vmid = hg.vmid[CSR_VMID_W-1:0];
      for (int k = 0; k < CSR_PMP_ENTRIES; k++) begin
        g.pmpcfg[k]  = pmpcfg_rd(k);
        g.pmpaddr[k] = pmpaddr_imp_t'(csr_read(
                         CSR_PMPADDR0_ADDR + CSR_ADDR_W'(k)));
      end
      return g;
    endfunction

    static function ptw_csr_t pack_ptw_csr();
      ptw_csr_t g;
      satp_t    s;
      vsatp_t   vs;
      hgatp_t   hg;
      menvcfg_t me;
      henvcfg_t he;
      s  = satp_t'(csr_read(CSR_SATP_ADDR));
      vs = vsatp_t'(csr_read(CSR_VSATP_ADDR));
      hg = hgatp_t'(csr_read(CSR_HGATP_ADDR));
      me = menvcfg_t'(csr_read(CSR_MENVCFG_ADDR));
      he = henvcfg_t'(csr_read(CSR_HENVCFG_ADDR));
      g.satp_mode     = s.mode;
      g.satp_ppn      = s.ppn[CSR_PPN_W-1:0];
      g.vsatp_mode    = vs.mode;
      g.vsatp_ppn     = vs.ppn[CSR_VSATP_PPN_W-1:0];
      g.hgatp_mode    = hg.mode;
      g.hgatp_ppn     = hg.ppn[CSR_PPN_W-1:0];
      g.menvcfg_adue  = me.adue;
      g.henvcfg_adue  = he.adue;
      g.menvcfg_pbmte = me.pbmte;
      g.henvcfg_pbmte = he.pbmte;
      for (int k = 0; k < CSR_PMP_ENTRIES; k++) begin
        g.pmpcfg[k]  = pmpcfg_rd(k);
        g.pmpaddr[k] = pmpaddr_imp_t'(csr_read(
                         CSR_PMPADDR0_ADDR + CSR_ADDR_W'(k)));
      end
      return g;
    endfunction

  endclass : csr_shadow

  // ================================================================
  // The interface (CSR-2 and the SYS-001 additions). Each is one call
  // into csr_shadow.
  // ================================================================
  function automatic void csr_reset();
    csr_shadow::csr_reset();
  endfunction
  function automatic void csr_write(input logic [CSR_ADDR_W-1:0] addr,
                                    input logic [63:0] value);
    csr_shadow::csr_write(addr, value);
  endfunction
  function automatic logic [63:0] csr_read(
      input logic [CSR_ADDR_W-1:0] addr);
    return csr_shadow::csr_read(addr);
  endfunction
  function automatic fe_cfg_t pack_fe_cfg();
    return csr_shadow::pack_fe_cfg();
  endfunction
  function automatic fe_csr_t pack_fe_csr();
    return csr_shadow::pack_fe_csr();
  endfunction
  function automatic ptw_csr_t pack_ptw_csr();
    return csr_shadow::pack_ptw_csr();
  endfunction
  function automatic void set_ext_enable(
      input decode_pkg::ext_enable_t v);
    csr_shadow::set_ext_enable(v);
  endfunction
  function automatic void set_priv(input logic [1:0] p);
    csr_shadow::set_priv(p);
  endfunction
  function automatic void set_v(input logic v);
    csr_shadow::set_v(v);
  endfunction
  function automatic void set_pmp_g(input int g);
    csr_shadow::set_pmp_g(g);
  endfunction
  function automatic void set_sc_enable(input logic b);
    csr_shadow::set_sc_enable(b);
  endfunction
  function automatic void set_ftb_fastpath_en(input logic b);
    csr_shadow::set_ftb_fastpath_en(b);
  endfunction
  function automatic void set_tage_enable_aging(input logic b);
    csr_shadow::set_tage_enable_aging(b);
  endfunction
  function automatic void set_ittage_enable_aging(input logic b);
    csr_shadow::set_ittage_enable_aging(b);
  endfunction
  function automatic void set_tage_aging_interval(input logic [31:0] n);
    csr_shadow::set_tage_aging_interval(n);
  endfunction
  function automatic void set_ittage_aging_interval(
      input logic [31:0] n);
    csr_shadow::set_ittage_aging_interval(n);
  endfunction

endpackage : csr_tb_pkg

`endif // CSR_TB_PKG_SV
