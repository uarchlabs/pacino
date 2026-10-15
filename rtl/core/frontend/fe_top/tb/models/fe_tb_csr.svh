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
// helpers on it; set_h2, the two-stage regime; pmp_page and pmp_all.
// ===================================================================

  // ---- the CSR groups (SYS-001, csr_decisions.md CSR-2) -----------------
  // Every member of fe_cfg, fe_csr and ptw_csr comes from csr_tb_pkg: a
  // change is a csr_write (or set_priv, set_v), under the CSR-5 write
  // rules, and csr_sync drives the three groups from the pack functions
  // in the same time step, as the direct drive it replaced did. Every
  // helper below ends in csr_sync.
  task automatic csr_sync();
    fe_cfg  = csr_tb_pkg::pack_fe_cfg();
    fe_csr  = csr_tb_pkg::pack_fe_csr();
    ptw_csr = csr_tb_pkg::pack_ptw_csr();
  endtask

  task automatic csr_priv(input logic [1:0] p);
    csr_tb_pkg::set_priv(p);
    csr_sync();
  endtask

  task automatic csr_wr_satp(input logic [3:0] mode,
                             input logic [ASID_WIDTH-1:0] asid,
                             input logic [43:0] ppn);
    csr_tb_pkg::csr_write(CSR_SATP_ADDR, {mode, 16'(asid), ppn});
    csr_sync();
  endtask

  task automatic csr_wr_vsatp(input logic [3:0] mode,
                              input logic [ASID_WIDTH-1:0] asid,
                              input logic [43:0] ppn);
    csr_tb_pkg::csr_write(CSR_VSATP_ADDR, {mode, 16'(asid), ppn});
    csr_sync();
  endtask

  task automatic csr_wr_hgatp(input logic [3:0] mode,
                              input logic [VMID_WIDTH-1:0] vmid,
                              input logic [43:0] ppn);
    csr_tb_pkg::csr_write(CSR_HGATP_ADDR, {mode, 2'b00, 14'(vmid), ppn});
    csr_sync();
  endtask

  // MODE alone, the other fields as they read.
  task automatic csr_satp_mode(input logic [3:0] mode);
    satp_t r;
    r      = satp_t'(csr_tb_pkg::csr_read(CSR_SATP_ADDR));
    r.mode = mode;
    csr_tb_pkg::csr_write(CSR_SATP_ADDR, 64'(r));
    csr_sync();
  endtask

  task automatic csr_vsatp_mode(input logic [3:0] mode);
    vsatp_t r;
    r      = vsatp_t'(csr_tb_pkg::csr_read(CSR_VSATP_ADDR));
    r.mode = mode;
    csr_tb_pkg::csr_write(CSR_VSATP_ADDR, 64'(r));
    csr_sync();
  endtask

  task automatic csr_hgatp_mode_vmid(input logic [3:0] mode,
                                     input logic [VMID_WIDTH-1:0] vmid);
    hgatp_t r;
    r      = hgatp_t'(csr_tb_pkg::csr_read(CSR_HGATP_ADDR));
    r.mode = mode;
    r.vmid = 14'(vmid);
    csr_tb_pkg::csr_write(CSR_HGATP_ADDR, 64'(r));
    csr_sync();
  endtask

  // menvcfg.ADUE or henvcfg.ADUE alone.
  task automatic csr_menv_adue(input logic b);
    menvcfg_t r;
    r      = menvcfg_t'(csr_tb_pkg::csr_read(CSR_MENVCFG_ADDR));
    r.adue = b;
    csr_tb_pkg::csr_write(CSR_MENVCFG_ADDR, 64'(r));
    csr_sync();
  endtask

  task automatic csr_henv_adue(input logic b);
    henvcfg_t r;
    r      = henvcfg_t'(csr_tb_pkg::csr_read(CSR_HENVCFG_ADDR));
    r.adue = b;
    csr_tb_pkg::csr_write(CSR_HENVCFG_ADDR, 64'(r));
    csr_sync();
  endtask

  // The program's envcfg CSR write (W.csr_env): menvcfg, then henvcfg,
  // so henvcfg.ADUE reads under the new menvcfg.ADUE (CSR-5).
  task automatic csr_envcfg(input logic madue, input logic hadue,
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
    csr_sync();
  endtask

  // PMP entry k: its pmpaddr, then its pmpcfg byte by read-modify-write
  // of pmpcfg0 or pmpcfg2.
  task automatic csr_pmp(input int k, input logic [7:0] cfg,
                         input logic [63:0] addr);
    logic [11:0] ca;
    pmpcfg_t     c;
    ca = (k < 8) ? CSR_PMPCFG0_ADDR : CSR_PMPCFG2_ADDR;
    csr_tb_pkg::csr_write(CSR_PMPADDR0_ADDR + 12'(k), addr);
    c            = pmpcfg_t'(csr_tb_pkg::csr_read(ca));
    c.ent[k % 8] = pmpcfg_ent_t'(cfg);
    csr_tb_pkg::csr_write(ca, 64'(c));
    csr_sync();
  endtask

  // BP-123. The two-stage regime: V=1 in VS-mode, vsatp Sv39 and hgatp
  // Sv39x4, ASID 1 and VMID 3. The G-stage root is 16 KiB at
  // 0x8E00_0000; VS-stage tables take GPAs from 0xC000_0000. The reset
  // vector is mapped VA = GPA = SPA.
  task automatic set_h2();
    W.h2       = 1'b1;
    W.hg_root  = PA_WIDTH'('h0_8E00_0000);
    for (int i = 0; i < 2048; i++) W.wr64(W.hg_root + PA_WIDTH'(8 * i), '0);
    W.gpt_next = GPA_WIDTH'('h0_C000_0000);
    W.vs_root  = W.vs_alloc();
    csr_tb_pkg::set_v(1'b1);
    csr_tb_pkg::set_priv(CSR_PRV_S);
    csr_satp_mode(CSR_SATP_MODE_BARE);
    csr_wr_vsatp(CSR_SATP_MODE_SV39, ASID_WIDTH'(1),
                 44'(W.vs_root >> 12));
    csr_wr_hgatp(CSR_HGATP_MODE_SV39X4, VMID_WIDTH'(3),
                 44'(W.hg_root >> 12));
    W.h_map4k(RESET_VECTOR, GPA_WIDTH'(RESET_VECTOR), PA_WIDTH'(RESET_VECTOR));
  endtask

  // A PMP entry over one naturally aligned 4 KiB page (NAPOT), with the
  // permission bits given (R 1, W 2, X 4). Lower entries win.
  task automatic pmp_page(input int k, input logic [PA_WIDTH-1:0] pa,
                          input logic [2:0] rwx);
    csr_pmp(k, {5'b00011, rwx},                      // A = NAPOT
            64'((PA_WIDTH-2)'(pa >> 2) | (PA_WIDTH-2)'('h1FF)));
  endtask

  // The last PMP entry an S-mode fetch and walk may use: everything.
  task automatic pmp_all(input int k);
    csr_pmp(0, 8'h00, 64'h0);
    csr_pmp(k, 8'h1F, 64'(pmpaddr_imp_t'('1)));
  endtask
