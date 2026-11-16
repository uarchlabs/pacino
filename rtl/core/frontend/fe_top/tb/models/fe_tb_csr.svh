// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fe_tb_csr.svh -- CSR setup through csr_tb_pkg
//
// A SHARED FRONT-END TESTBENCH MODEL (DOC-001, fe_demo_tb_decisions.md
// FDT-4). Not a compilation unit: it is included inside the body of
// module tb, after the package imports, by tb_fe_top
// (rtl/core/frontend/fe_top/tb) and tb_fe_demo (examples/fe_demo/tb),
// in the order those files give. The text was moved here from
// tb_fe_top.sv unchanged except where this header says otherwise.
//
// Holds: csr_sync, which drives fe_cfg, fe_csr and ptw_csr from the
// csr_tb_pkg pack functions (csr_decisions.md CSR-2), and the write
// helpers on it; set_h2, the two-stage regime (BP-148: set_h2_at in any
// mode, use_smode for the single stage); pmp_page and pmp_all.
//
// CHANGED FROM tb_fe_top.sv (INFRA-015): each task's body is a method
// of class csr_hlp_c, and the task is one call to it on the handle CSH.
// A module task is inlined at every call (Verilator 5.048), so a body
// called from 42 programs was compiled 42 times or more into one C++
// function; a class method is compiled once and called. Every task keeps
// its name, its arguments and its effect. The class has no members: its
// methods read and write this module's signals (fe_cfg, fe_csr,
// ptw_csr) and the writer W, as the tasks did, so the TOOLS-007
// self-store loop rule (rtl/CLAUDE.md) does not arise.
// ===================================================================

  // ---- the CSR groups (SYS-001, csr_decisions.md CSR-2) -----------------
  // Every member of fe_cfg, fe_csr and ptw_csr comes from csr_tb_pkg: a
  // change is a csr_write (or set_priv, set_v), under the CSR-5 write
  // rules, and csr_sync drives the three groups from the pack functions
  // in the same time step, as the direct drive it replaced did. Every
  // helper below ends in csr_sync.
  class csr_hlp_c;
    function void sync();
      fe_cfg  = csr_tb_pkg::pack_fe_cfg();
      fe_csr  = csr_tb_pkg::pack_fe_csr();
      ptw_csr = csr_tb_pkg::pack_ptw_csr();
    endfunction

    function void priv(input logic [1:0] p);
      csr_tb_pkg::set_priv(p);
      sync();
    endfunction

    function void wr_satp(input logic [3:0] mode,
                          input logic [ASID_WIDTH-1:0] asid,
                          input logic [43:0] ppn);
      csr_tb_pkg::csr_write(CSR_SATP_ADDR, {mode, 16'(asid), ppn});
      sync();
    endfunction

    function void wr_vsatp(input logic [3:0] mode,
                           input logic [ASID_WIDTH-1:0] asid,
                           input logic [43:0] ppn);
      csr_tb_pkg::csr_write(CSR_VSATP_ADDR, {mode, 16'(asid), ppn});
      sync();
    endfunction

    function void wr_hgatp(input logic [3:0] mode,
                           input logic [VMID_WIDTH-1:0] vmid,
                           input logic [43:0] ppn);
      csr_tb_pkg::csr_write(CSR_HGATP_ADDR, {mode, 2'b00, 14'(vmid), ppn});
      sync();
    endfunction

    // MODE alone, the other fields as they read.
    function void satp_mode(input logic [3:0] mode);
      satp_t r;
      r      = satp_t'(csr_tb_pkg::csr_read(CSR_SATP_ADDR));
      r.mode = mode;
      csr_tb_pkg::csr_write(CSR_SATP_ADDR, 64'(r));
      sync();
    endfunction

    function void vsatp_mode(input logic [3:0] mode);
      vsatp_t r;
      r      = vsatp_t'(csr_tb_pkg::csr_read(CSR_VSATP_ADDR));
      r.mode = mode;
      csr_tb_pkg::csr_write(CSR_VSATP_ADDR, 64'(r));
      sync();
    endfunction

    function void hgatp_mode_vmid(input logic [3:0] mode,
                                  input logic [VMID_WIDTH-1:0] vmid);
      hgatp_t r;
      r      = hgatp_t'(csr_tb_pkg::csr_read(CSR_HGATP_ADDR));
      r.mode = mode;
      r.vmid = 14'(vmid);
      csr_tb_pkg::csr_write(CSR_HGATP_ADDR, 64'(r));
      sync();
    endfunction

    // menvcfg.ADUE or henvcfg.ADUE alone.
    function void menv_adue(input logic b);
      menvcfg_t r;
      r      = menvcfg_t'(csr_tb_pkg::csr_read(CSR_MENVCFG_ADDR));
      r.adue = b;
      csr_tb_pkg::csr_write(CSR_MENVCFG_ADDR, 64'(r));
      sync();
    endfunction

    function void henv_adue(input logic b);
      henvcfg_t r;
      r      = henvcfg_t'(csr_tb_pkg::csr_read(CSR_HENVCFG_ADDR));
      r.adue = b;
      csr_tb_pkg::csr_write(CSR_HENVCFG_ADDR, 64'(r));
      sync();
    endfunction

    // The program's envcfg CSR write (W.csr_env): menvcfg, then henvcfg,
    // so henvcfg.ADUE reads under the new menvcfg.ADUE (CSR-5).
    function void envcfg(input logic madue, input logic hadue,
                         input logic mpbmte, input logic hpbmte);
      menvcfg_t m;
      henvcfg_t h;
      m       = '0;
      m.adue  = madue;
      m.pbmte = mpbmte;
      h       = '0;
      h.adue  = hadue;
      h.pbmte = hpbmte;
      csr_tb_pkg::csr_write(CSR_MENVCFG_ADDR, 64'(m));
      csr_tb_pkg::csr_write(CSR_HENVCFG_ADDR, 64'(h));
      sync();
    endfunction

    // PMP entry k: its pmpaddr, then its pmpcfg byte by read-modify-write
    // of pmpcfg0 or pmpcfg2.
    function void pmp(input int k, input logic [7:0] cfg,
                      input logic [63:0] addr);
      logic [11:0] ca;
      pmpcfg_t     c;
      ca = (k < 8) ? CSR_PMPCFG0_ADDR : CSR_PMPCFG2_ADDR;
      csr_tb_pkg::csr_write(CSR_PMPADDR0_ADDR + 12'(k), addr);
      c            = pmpcfg_t'(csr_tb_pkg::csr_read(ca));
      c.ent[k % 8] = pmpcfg_ent_t'(cfg);
      csr_tb_pkg::csr_write(ca, 64'(c));
      sync();
    endfunction

    // BP-148. The two-stage regime in any vsatp and hgatp mode, the
    // VS-stage tables from GPA gpt. The writer builds the stages in those
    // modes (W.vs_mode, W.hg_mode), and vsatp and hgatp are written from
    // the built stages.
    // A task: W.h_map4k is one.
    task h2_at(input logic [3:0] vsm, input logic [3:0] hgm,
               input logic [GPA_WIDTH-1:0] gpt);
      W.h2       = 1'b1;
      W.hg_root  = PA_WIDTH'('h0_8E00_0000);
      for (int i = 0; i < 2048; i++) W.wr64(W.hg_root + PA_WIDTH'(8 * i), '0);
      W.gpt_next = gpt;
      W.vs_mode  = vsm;
      W.hg_mode  = hgm;
      W.vs_root  = W.vs_alloc();
      csr_tb_pkg::set_v(1'b1);
      csr_tb_pkg::set_priv(CSR_PRV_S);
      satp_mode(CSR_SATP_MODE_BARE);
      wr_vsatp(W.vs.mode, ASID_WIDTH'(1), 44'(W.vs_root >> 12));
      wr_hgatp(W.gs.mode, VMID_WIDTH'(3), 44'(W.hg_root >> 12));
      W.h_map4k(RESET_VECTOR, GPA_WIDTH'(RESET_VECTOR),
                PA_WIDTH'(RESET_VECTOR));
    endtask

    // BP-148. The single stage in mode m (satp), before any table word is
    // placed: the writer rebuilds its stage, and satp.MODE is written
    // from it.
    function void smode(input logic [3:0] m);
      W.set_smode(m);
      satp_mode(W.ss.mode);
    endfunction

    // A PMP entry over one naturally aligned 4 KiB page (NAPOT), with the
    // permission bits given (R 1, W 2, X 4). Lower entries win.
    function void page(input int k, input logic [PA_WIDTH-1:0] pa,
                       input logic [2:0] rwx);
      pmp(k, {5'b00011, rwx},                        // A = NAPOT
          64'((PA_WIDTH-2)'(pa >> 2) | (PA_WIDTH-2)'('h1FF)));
    endfunction

    // The last PMP entry an S-mode fetch and walk may use: everything.
    function void all(input int k);
      pmp(0, 8'h00, 64'h0);
      pmp(k, 8'h1F, 64'(pmpaddr_imp_t'('1)));
    endfunction
  endclass

  csr_hlp_c CSH = new;

  // The tasks, each one call (INFRA-015).
  task automatic csr_sync();
    CSH.sync();
  endtask

  task automatic csr_priv(input logic [1:0] p);
    CSH.priv(p);
  endtask

  task automatic csr_wr_satp(input logic [3:0] mode,
                             input logic [ASID_WIDTH-1:0] asid,
                             input logic [43:0] ppn);
    CSH.wr_satp(mode, asid, ppn);
  endtask

  task automatic csr_wr_vsatp(input logic [3:0] mode,
                              input logic [ASID_WIDTH-1:0] asid,
                              input logic [43:0] ppn);
    CSH.wr_vsatp(mode, asid, ppn);
  endtask

  task automatic csr_wr_hgatp(input logic [3:0] mode,
                              input logic [VMID_WIDTH-1:0] vmid,
                              input logic [43:0] ppn);
    CSH.wr_hgatp(mode, vmid, ppn);
  endtask

  task automatic csr_satp_mode(input logic [3:0] mode);
    CSH.satp_mode(mode);
  endtask

  task automatic csr_vsatp_mode(input logic [3:0] mode);
    CSH.vsatp_mode(mode);
  endtask

  task automatic csr_hgatp_mode_vmid(input logic [3:0] mode,
                                     input logic [VMID_WIDTH-1:0] vmid);
    CSH.hgatp_mode_vmid(mode, vmid);
  endtask

  task automatic csr_menv_adue(input logic b);
    CSH.menv_adue(b);
  endtask

  task automatic csr_henv_adue(input logic b);
    CSH.henv_adue(b);
  endtask

  task automatic csr_envcfg(input logic madue, input logic hadue,
                            input logic mpbmte, input logic hpbmte);
    CSH.envcfg(madue, hadue, mpbmte, hpbmte);
  endtask

  task automatic csr_pmp(input int k, input logic [7:0] cfg,
                         input logic [63:0] addr);
    CSH.pmp(k, cfg, addr);
  endtask

  // BP-123. The two-stage regime: V=1 in VS-mode, vsatp Sv39 and hgatp
  // Sv39x4, ASID 1 and VMID 3. The G-stage root is 16 KiB at
  // 0x8E00_0000; VS-stage tables take GPAs from 0xC000_0000. The reset
  // vector is mapped VA = GPA = SPA.
  task automatic set_h2();
    CSH.h2_at(CSR_SATP_MODE_SV39, CSR_HGATP_MODE_SV39X4,
              GPA_WIDTH'('h0_C000_0000));
  endtask

  task automatic set_h2_at(input logic [3:0] vsm, input logic [3:0] hgm,
                           input logic [GPA_WIDTH-1:0] gpt);
    CSH.h2_at(vsm, hgm, gpt);
  endtask

  task automatic use_smode(input logic [3:0] m);
    CSH.smode(m);
  endtask

  task automatic pmp_page(input int k, input logic [PA_WIDTH-1:0] pa,
                          input logic [2:0] rwx);
    CSH.page(k, pa, rwx);
  endtask

  task automatic pmp_all(input int k);
    CSH.all(k);
  endtask
