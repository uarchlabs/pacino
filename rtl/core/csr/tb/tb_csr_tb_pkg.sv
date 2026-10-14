// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for csr_tb_pkg (SYS-001 Problem 4). csr_decisions.md
// CSR-2, CSR-4, CSR-5, CSR-7.
//
// Every expected value is written out here from the rule text and the
// value the test wrote; the testbench calls the package only to write,
// read and pack, never to form an expectation. Each group starts from
// csr_reset(), so no group depends on another's state.
//
// Groups:
//   R  reset: every CSR read after csr_reset, and the shadow's values
//      before any call (the package's own initializers)
//   S  satp: supported MODE writes every field; unimplemented PPN bits
//      read 0; an unsupported MODE writes no field
//   V  vsatp: the same, PPN 28:0 (the PROPOSED row of CSR-5)
//   H  hgatp: unsupported MODE keeps MODE and writes VMID and PPN; PPN
//      1:0 read 0 in Sv39x4 and not in Bare; bits 59:58 read 0
//   E  menvcfg, henvcfg: only PBMTE and ADUE; henvcfg.ADUE reads 0
//      while menvcfg.ADUE is 0
//   P  pmpcfg: reserved bits read 0; NA4 stored as NAPOT; a locked
//      entry and its pmpaddr are not written, its unlocked neighbours
//      are; pmpcfg2 holds entries 8-15; csr_reset clears a lock
//   A  pmpaddr read-back: NAPOT bits 8:0 read 1, OFF and TOR bits 9:0
//      read 0, bits 63:34 read 0; set_pmp_g at G = 0 and G = 2
//   C  0x7C0 and 0x7C1: reserved bits; every named setter alone
//   X  set_ext_enable, set_priv, set_v
//   K  pack_fe_cfg, pack_fe_csr, pack_ptw_csr: every member against
//      the value derived from what was written
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;
import decode_pkg::*;
import csr_pkg::*;

module tb;

  int pass_cnt = 0;
  int fail_cnt = 0;

  task automatic chk(input string nm, input logic [63:0] got,
                     input logic [63:0] exp);
    if (got === exp) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL %s: got %016h exp %016h", nm, got, exp);
    end
  endtask

  // Address of pmpaddr k.
  function automatic logic [11:0] pa_addr(input int k);
    return 12'h3B0 + 12'(k);
  endfunction

  localparam logic [63:0] ONES34 = 64'h0000_0003_FFFF_FFFF;

  initial begin
    fe_cfg_t     gc;
    fe_csr_t     gf;
    ptw_csr_t    gp;
    ext_enable_t ee;

    // ---- R: reset ---------------------------------------------------
    // Before any call: the package initializers are the reset values.
    chk("R0 7C0 before any call",   csr_tb_pkg::csr_read(12'h7C0), 64'h1);
    chk("R0 pmpaddr0 before call",  csr_tb_pkg::csr_read(12'h3B0), ONES34);
    csr_tb_pkg::csr_write(12'h7C0, 64'h0);
    csr_tb_pkg::csr_write(12'h180, {4'd8, 16'h1234, 44'h12345});
    csr_tb_pkg::csr_reset();
    chk("R1 7C0",     csr_tb_pkg::csr_read(12'h7C0), 64'h0000_0000_0000_0001);
    chk("R2 7C1",     csr_tb_pkg::csr_read(12'h7C1), 64'h0);
    chk("R3 satp",    csr_tb_pkg::csr_read(12'h180), 64'h0000_0000_0008_F000);
    chk("R4 vsatp",   csr_tb_pkg::csr_read(12'h280), 64'h0);
    chk("R5 hgatp",   csr_tb_pkg::csr_read(12'h680), 64'h0);
    chk("R6 menvcfg", csr_tb_pkg::csr_read(12'h30A), 64'h4000_0000_0000_0000);
    chk("R7 henvcfg", csr_tb_pkg::csr_read(12'h60A), 64'h4000_0000_0000_0000);
    chk("R8 pmpcfg0", csr_tb_pkg::csr_read(12'h3A0), 64'h0000_0000_0000_001F);
    chk("R9 pmpcfg2", csr_tb_pkg::csr_read(12'h3A2), 64'h0);
    chk("R10 pmpaddr0", csr_tb_pkg::csr_read(12'h3B0), ONES34);
    for (int k = 1; k < 16; k++) begin
      // OFF entries: bits 9:0 read 0 of a 0 value.
      chk($sformatf("R11 pmpaddr%0d", k), csr_tb_pkg::csr_read(pa_addr(k)),
          64'h0);
    end
    gf = csr_tb_pkg::pack_fe_csr();
    chk("R12 priv M", 64'(gf.priv), 64'd3);
    chk("R13 V 0",    64'(gf.v),    64'd0);
    gc = csr_tb_pkg::pack_fe_cfg();
    chk("R14 ext_enable RVA23", 64'(gc.ext_enable), 64'(16'hFFFF));

    // ---- S: satp ----------------------------------------------------
    csr_tb_pkg::csr_reset();
    // Sv39, every bit set elsewhere: PPN 43:24 read 0.
    csr_tb_pkg::csr_write(12'h180, {4'd8, 16'hFFFF, 44'hFFF_FFFF_FFFF});
    chk("S1 Sv39 all fields", csr_tb_pkg::csr_read(12'h180),
        {4'd8, 16'hFFFF, 20'h0, 24'hFF_FFFF});
    csr_tb_pkg::csr_write(12'h180, {4'd0, 16'h0012, 44'h0_0000_0345});
    chk("S2 Bare written", csr_tb_pkg::csr_read(12'h180),
        {4'd0, 16'h0012, 44'h345});
    // Unsupported MODEs: no field written.
    csr_tb_pkg::csr_write(12'h180, {4'd9, 16'hAAAA, 44'h0_0000_0BBB});
    chk("S3 MODE 9 ignored", csr_tb_pkg::csr_read(12'h180),
        {4'd0, 16'h0012, 44'h345});
    csr_tb_pkg::csr_write(12'h180, {4'd1, 16'hAAAA, 44'h0_0000_0BBB});
    chk("S4 MODE 1 ignored", csr_tb_pkg::csr_read(12'h180),
        {4'd0, 16'h0012, 44'h345});
    csr_tb_pkg::csr_write(12'h180, {4'd10, 16'hAAAA, 44'h0_0000_0BBB});
    chk("S5 MODE Sv57 ignored", csr_tb_pkg::csr_read(12'h180),
        {4'd0, 16'h0012, 44'h345});

    // ---- V: vsatp ---------------------------------------------------
    csr_tb_pkg::csr_reset();
    csr_tb_pkg::csr_write(12'h280, {4'd8, 16'hFFFF, 44'hFFF_FFFF_FFFF});
    chk("V1 Sv39 all fields", csr_tb_pkg::csr_read(12'h280),
        {4'd8, 16'hFFFF, 15'h0, 29'h1FFF_FFFF});
    csr_tb_pkg::csr_write(12'h280, {4'd9, 16'h0001, 44'h1});
    chk("V2 MODE 9 ignored", csr_tb_pkg::csr_read(12'h280),
        {4'd8, 16'hFFFF, 15'h0, 29'h1FFF_FFFF});
    csr_tb_pkg::csr_write(12'h280, {4'd0, 16'h0003, 44'h4});
    chk("V3 Bare written", csr_tb_pkg::csr_read(12'h280),
        {4'd0, 16'h0003, 44'h4});

    // ---- H: hgatp ---------------------------------------------------
    csr_tb_pkg::csr_reset();
    // Bare, PPN low bits set: readable in Bare. 59:58 written 1 read 0.
    csr_tb_pkg::csr_write(12'h680,
                          {4'd0, 2'b11, 14'h3FFF, 44'hFFF_FFFF_FFFF});
    chk("H1 Bare, 59:58 read 0, PPN 23:0", csr_tb_pkg::csr_read(12'h680),
        {4'd0, 2'b00, 14'h3FFF, 20'h0, 24'hFF_FFFF});
    // Unsupported MODE: MODE unchanged (Bare), VMID and PPN written.
    csr_tb_pkg::csr_write(12'h680, {4'd9, 2'b00, 14'h0005, 44'h0_0000_0103});
    chk("H2 MODE 9: MODE kept, VMID PPN written",
        csr_tb_pkg::csr_read(12'h680),
        {4'd0, 2'b00, 14'h0005, 44'h103});
    // Sv39x4: PPN 1:0 read 0.
    csr_tb_pkg::csr_write(12'h680, {4'd8, 2'b00, 14'h0003, 44'h0_0008_E003});
    chk("H3 Sv39x4: PPN 1:0 read 0", csr_tb_pkg::csr_read(12'h680),
        {4'd8, 2'b00, 14'h0003, 44'h8_E000});
    // Unsupported MODE from Sv39x4: MODE stays Sv39x4.
    csr_tb_pkg::csr_write(12'h680, {4'd10, 2'b00, 14'h0007, 44'h0_0008_F001});
    chk("H4 MODE 10: stays Sv39x4", csr_tb_pkg::csr_read(12'h680),
        {4'd8, 2'b00, 14'h0007, 44'h8_F000});

    // ---- E: menvcfg, henvcfg ----------------------------------------
    csr_tb_pkg::csr_reset();
    csr_tb_pkg::csr_write(12'h30A, 64'hFFFF_FFFF_FFFF_FFFF);
    chk("E1 menvcfg: only 62 and 61", csr_tb_pkg::csr_read(12'h30A),
        64'h6000_0000_0000_0000);
    csr_tb_pkg::csr_write(12'h60A, 64'hFFFF_FFFF_FFFF_FFFF);
    chk("E2 henvcfg: only 62 and 61", csr_tb_pkg::csr_read(12'h60A),
        64'h6000_0000_0000_0000);
    // menvcfg.ADUE cleared: henvcfg.ADUE reads 0, PBMTE unaffected.
    csr_tb_pkg::csr_write(12'h30A, 64'h4000_0000_0000_0000);
    chk("E3 henvcfg.ADUE read 0 under menvcfg.ADUE 0",
        csr_tb_pkg::csr_read(12'h60A), 64'h4000_0000_0000_0000);
    gp = csr_tb_pkg::pack_ptw_csr();
    chk("E4 ptw henvcfg_adue 0", 64'(gp.henvcfg_adue), 64'd0);
    chk("E5 ptw menvcfg_adue 0", 64'(gp.menvcfg_adue), 64'd0);
    // The rule is a read rule: menvcfg.ADUE set again shows it.
    csr_tb_pkg::csr_write(12'h30A, 64'h2000_0000_0000_0000);
    chk("E6 henvcfg.ADUE visible again", csr_tb_pkg::csr_read(12'h60A),
        64'h6000_0000_0000_0000);
    chk("E7 menvcfg PBMTE 0 ADUE 1", csr_tb_pkg::csr_read(12'h30A),
        64'h2000_0000_0000_0000);

    // ---- P: pmpcfg --------------------------------------------------
    csr_tb_pkg::csr_reset();
    // Reserved bits 6:5 read 0; entry 1 TOR R, entry 2 NA4 -> NAPOT.
    csr_tb_pkg::csr_write(12'h3A0, 64'h0000_0000_0010_6F1F);
    chk("P1 rsvd 6:5 0, NA4 as NAPOT", csr_tb_pkg::csr_read(12'h3A0),
        64'h0000_0000_0018_0F1F);
    // Lock entry 3 (TOR X) after writing its pmpaddr, then try to
    // rewrite entries 2-4.
    csr_tb_pkg::csr_write(pa_addr(3), 64'h0000_0000_0000_4000);
    csr_tb_pkg::csr_write(12'h3A0, 64'h0000_0000_8C18_0F1F);
    csr_tb_pkg::csr_write(12'h3A0, 64'h0000_0019_0019_0F1F);
    chk("P2 entry 3 locked, 2 and 4 written", csr_tb_pkg::csr_read(12'h3A0),
        64'h0000_0019_8C19_0F1F);
    // Its pmpaddr is not written; a neighbour's is. TOR: 9:0 read 0.
    csr_tb_pkg::csr_write(pa_addr(3), 64'h0000_0000_0000_8000);
    chk("P3 locked pmpaddr3 kept", csr_tb_pkg::csr_read(pa_addr(3)),
        64'h0000_0000_0000_4000);
    csr_tb_pkg::csr_write(pa_addr(5), 64'h0000_0000_0000_8000);
    chk("P4 unlocked pmpaddr5 written", csr_tb_pkg::csr_read(pa_addr(5)),
        64'h0000_0000_0000_8000);
    // A lock cannot be cleared by a write.
    csr_tb_pkg::csr_write(12'h3A0, 64'h0);
    chk("P5 lock not cleared by a write", csr_tb_pkg::csr_read(12'h3A0),
        64'h0000_0000_8C00_0000);
    // pmpcfg2 holds entries 8-15.
    csr_tb_pkg::csr_write(12'h3A2, 64'h1F00_0000_0000_0019);
    chk("P6 pmpcfg2", csr_tb_pkg::csr_read(12'h3A2), 64'h1F00_0000_0000_0019);
    gf = csr_tb_pkg::pack_fe_csr();
    chk("P7 entry 8 in pack",  64'(gf.pmpcfg[8]),  64'h19);
    chk("P8 entry 15 in pack", 64'(gf.pmpcfg[15]), 64'h1F);
    chk("P9 entry 3 in pack",  64'(gf.pmpcfg[3]),  64'h8C);
    // csr_reset clears the lock (a hart reset).
    csr_tb_pkg::csr_reset();
    csr_tb_pkg::csr_write(12'h3A0, 64'h0000_0000_0000_0000);
    chk("P10 reset clears the lock", csr_tb_pkg::csr_read(12'h3A0), 64'h0);

    // ---- A: pmpaddr read-back ---------------------------------------
    csr_tb_pkg::csr_reset();
    csr_tb_pkg::csr_write(12'h3A0, 64'h0000_0000_0000_0000);  // all OFF
    csr_tb_pkg::csr_write(pa_addr(0), 64'hFFFF_FFFF_FFFF_FFFF);
    chk("A1 OFF: 9:0 read 0, 63:34 read 0",
        csr_tb_pkg::csr_read(pa_addr(0)), 64'h0000_0003_FFFF_FC00);
    csr_tb_pkg::csr_write(pa_addr(1), 64'h0000_0000_2000_0000);
    csr_tb_pkg::csr_write(12'h3A0, 64'h0000_0000_0000_1800); // e1 NAPOT
    chk("A2 NAPOT: 8:0 read 1", csr_tb_pkg::csr_read(pa_addr(1)),
        64'h0000_0000_2000_01FF);
    csr_tb_pkg::csr_write(pa_addr(1), 64'h0000_0000_2000_03FF);
    chk("A3 NAPOT: bit 9 as written", csr_tb_pkg::csr_read(pa_addr(1)),
        64'h0000_0000_2000_03FF);
    csr_tb_pkg::csr_write(12'h3A0, 64'h0000_0000_0000_0800); // e1 TOR
    chk("A4 TOR: 9:0 read 0", csr_tb_pkg::csr_read(pa_addr(1)),
        64'h0000_0000_2000_0000);
    // The stored bits return when the entry is NAPOT again.
    csr_tb_pkg::csr_write(12'h3A0, 64'h0000_0000_0000_1800);
    chk("A5 stored bits kept", csr_tb_pkg::csr_read(pa_addr(1)),
        64'h0000_0000_2000_03FF);
    // G = 0: NA4 selectable, no bit forced.
    csr_tb_pkg::set_pmp_g(0);
    csr_tb_pkg::csr_write(12'h3A0, 64'h0000_0000_0000_1000); // e1 NA4
    csr_tb_pkg::csr_write(pa_addr(1), 64'h0000_0000_2000_0001);
    chk("A6 G0 NA4 kept", csr_tb_pkg::csr_read(12'h3A0),
        64'h0000_0000_0000_1000);
    chk("A7 G0 NA4 address exact", csr_tb_pkg::csr_read(pa_addr(1)),
        64'h0000_0000_2000_0001);
    csr_tb_pkg::csr_write(12'h3A0, 64'h0000_0000_0000_0800); // e1 TOR
    chk("A8 G0 TOR address exact", csr_tb_pkg::csr_read(pa_addr(1)),
        64'h0000_0000_2000_0001);
    // G = 2: NAPOT bit 0 reads 1, TOR bits 1:0 read 0.
    csr_tb_pkg::set_pmp_g(2);
    csr_tb_pkg::csr_write(pa_addr(1), 64'h0000_0000_2000_0006);
    chk("A9 G2 TOR 1:0 read 0", csr_tb_pkg::csr_read(pa_addr(1)),
        64'h0000_0000_2000_0004);
    csr_tb_pkg::csr_write(12'h3A0, 64'h0000_0000_0000_1800); // e1 NAPOT
    chk("A10 G2 NAPOT 0 reads 1", csr_tb_pkg::csr_read(pa_addr(1)),
        64'h0000_0000_2000_0007);
    // csr_reset restores G = 10.
    csr_tb_pkg::csr_reset();
    csr_tb_pkg::csr_write(12'h3A0, 64'h0000_0000_0000_1000); // e1 NA4
    chk("A11 reset restores G 10: NA4 as NAPOT",
        csr_tb_pkg::csr_read(12'h3A0), 64'h0000_0000_0000_1800);

    // ---- C: 0x7C0, 0x7C1, named setters -----------------------------
    csr_tb_pkg::csr_reset();
    csr_tb_pkg::csr_write(12'h7C0, 64'hFFFF_FFFF_FFFF_FFFF);
    chk("C1 7C0: 63:4 read 0", csr_tb_pkg::csr_read(12'h7C0), 64'hF);
    csr_tb_pkg::csr_write(12'h7C0, 64'h0);
    csr_tb_pkg::set_sc_enable(1'b1);
    chk("C2 set_sc_enable",          csr_tb_pkg::csr_read(12'h7C0), 64'h1);
    csr_tb_pkg::set_sc_enable(1'b0);
    csr_tb_pkg::set_ftb_fastpath_en(1'b1);
    chk("C3 set_ftb_fastpath_en",    csr_tb_pkg::csr_read(12'h7C0), 64'h2);
    csr_tb_pkg::set_ftb_fastpath_en(1'b0);
    csr_tb_pkg::set_tage_enable_aging(1'b1);
    chk("C4 set_tage_enable_aging",  csr_tb_pkg::csr_read(12'h7C0), 64'h4);
    csr_tb_pkg::set_tage_enable_aging(1'b0);
    csr_tb_pkg::set_ittage_enable_aging(1'b1);
    chk("C5 set_ittage_enable_aging", csr_tb_pkg::csr_read(12'h7C0), 64'h8);
    csr_tb_pkg::set_ittage_enable_aging(1'b0);
    chk("C6 each setter clears its bit", csr_tb_pkg::csr_read(12'h7C0),
        64'h0);
    csr_tb_pkg::set_tage_aging_interval(32'h1234_5678);
    chk("C7 set_tage_aging_interval", csr_tb_pkg::csr_read(12'h7C1),
        64'h0000_0000_1234_5678);
    csr_tb_pkg::set_ittage_aging_interval(32'h9ABC_DEF0);
    chk("C8 set_ittage_aging_interval", csr_tb_pkg::csr_read(12'h7C1),
        64'h9ABC_DEF0_1234_5678);
    csr_tb_pkg::set_tage_aging_interval(32'h0);
    chk("C9 setters leave the other field", csr_tb_pkg::csr_read(12'h7C1),
        64'h9ABC_DEF0_0000_0000);
    csr_tb_pkg::csr_write(12'h7C1, 64'hFFFF_FFFF_FFFF_FFFF);
    chk("C10 7C1 all 64 bits", csr_tb_pkg::csr_read(12'h7C1),
        64'hFFFF_FFFF_FFFF_FFFF);

    // ---- X: ext_enable, priv, V -------------------------------------
    csr_tb_pkg::csr_reset();
    ee      = RVA23_ENABLE;
    ee.en_m = 1'b0;
    ee.en_h = 1'b0;
    csr_tb_pkg::set_ext_enable(ee);
    gc = csr_tb_pkg::pack_fe_cfg();
    chk("X1 set_ext_enable", 64'(gc.ext_enable), 64'(16'h7FFE));
    csr_tb_pkg::set_priv(2'b01);
    csr_tb_pkg::set_v(1'b1);
    gf = csr_tb_pkg::pack_fe_csr();
    chk("X2 set_priv S", 64'(gf.priv), 64'd1);
    chk("X3 set_v 1",    64'(gf.v),    64'd1);
    csr_tb_pkg::set_priv(2'b00);
    gf = csr_tb_pkg::pack_fe_csr();
    chk("X4 set_priv U", 64'(gf.priv), 64'd0);
    csr_tb_pkg::csr_reset();
    gc = csr_tb_pkg::pack_fe_cfg();
    gf = csr_tb_pkg::pack_fe_csr();
    chk("X5 reset ext_enable", 64'(gc.ext_enable), 64'(16'hFFFF));
    chk("X6 reset priv",       64'(gf.priv),       64'd3);
    chk("X7 reset V",          64'(gf.v),          64'd0);

    // ---- K: the pack functions --------------------------------------
    csr_tb_pkg::csr_reset();
    csr_tb_pkg::csr_write(12'h7C0, 64'h0000_0000_0000_000A);
    csr_tb_pkg::csr_write(12'h7C1, 64'h0000_0021_0000_0011);
    gc = csr_tb_pkg::pack_fe_cfg();
    chk("K1 sc_enable",             64'(gc.sc_enable),             64'd0);
    chk("K2 ftb_fastpath_en",       64'(gc.ftb_fastpath_en),       64'd1);
    chk("K3 tage_enable_aging",     64'(gc.tage_enable_aging),     64'd0);
    chk("K4 tage_aging_interval",   64'(gc.tage_aging_interval),   64'h11);
    chk("K5 ittage_enable_aging",   64'(gc.ittage_enable_aging),   64'd1);
    chk("K6 ittage_aging_interval", 64'(gc.ittage_aging_interval), 64'h21);
    chk("K7 ext_enable",            64'(gc.ext_enable),      64'(16'hFFFF));

    csr_tb_pkg::set_v(1'b1);
    csr_tb_pkg::set_priv(2'b01);
    csr_tb_pkg::csr_write(12'h180, {4'd8, 16'h0001, 44'h0_0008_1000});
    csr_tb_pkg::csr_write(12'h280, {4'd8, 16'h0002, 44'h0_1000_0003});
    csr_tb_pkg::csr_write(12'h680, {4'd8, 2'b00, 14'h0003, 44'h0_0008_E002});
    csr_tb_pkg::csr_write(12'h30A, 64'h6000_0000_0000_0000);
    csr_tb_pkg::csr_write(12'h60A, 64'h2000_0000_0000_0000);
    // e0 NAPOT RWX at 0x8000_0000 64 KiB, e1 TOR X, e9 NAPOT R.
    csr_tb_pkg::csr_write(12'h3A0, 64'h0000_0000_0000_0C1F);
    csr_tb_pkg::csr_write(12'h3A2, 64'h0000_0000_0000_1900);
    csr_tb_pkg::csr_write(pa_addr(0), 64'h0000_0000_2000_0FFF);
    csr_tb_pkg::csr_write(pa_addr(1), 64'h0000_0000_2400_0123);
    csr_tb_pkg::csr_write(pa_addr(9), 64'h0000_0000_3000_0000);
    gf = csr_tb_pkg::pack_fe_csr();
    chk("K8 v",          64'(gf.v),          64'd1);
    chk("K9 priv",       64'(gf.priv),       64'd1);
    chk("K10 satp_mode", 64'(gf.satp_mode),  64'd8);
    chk("K11 satp_asid", 64'(gf.satp_asid),  64'h1);
    chk("K12 vsatp_mode", 64'(gf.vsatp_mode), 64'd8);
    chk("K13 vsatp_asid", 64'(gf.vsatp_asid), 64'h2);
    chk("K14 hgatp_mode", 64'(gf.hgatp_mode), 64'd8);
    chk("K15 hgatp_vmid", 64'(gf.hgatp_vmid), 64'h3);
    chk("K16 pmpcfg0",    64'(gf.pmpcfg[0]),  64'h1F);
    chk("K17 pmpcfg1",    64'(gf.pmpcfg[1]),  64'h0C);
    chk("K18 pmpcfg9",    64'(gf.pmpcfg[9]),  64'h19);
    chk("K19 pmpcfg2 OFF", 64'(gf.pmpcfg[2]), 64'h00);
    chk("K20 pmpaddr0 NAPOT", 64'(gf.pmpaddr[0]), 64'h2000_0FFF);
    chk("K21 pmpaddr1 TOR",   64'(gf.pmpaddr[1]), 64'h2400_0000);
    chk("K22 pmpaddr9 NAPOT", 64'(gf.pmpaddr[9]), 64'h3000_01FF);
    chk("K23 pmpaddr2 OFF",   64'(gf.pmpaddr[2]), 64'h0);
    gp = csr_tb_pkg::pack_ptw_csr();
    chk("K24 satp_mode",  64'(gp.satp_mode),  64'd8);
    chk("K25 satp_ppn",   64'(gp.satp_ppn),   64'h8_1000);
    chk("K26 vsatp_mode", 64'(gp.vsatp_mode), 64'd8);
    // vsatp PPN 28:0 of 0x1000_0003
    chk("K27 vsatp_ppn",  64'(gp.vsatp_ppn),  64'h1000_0003);
    chk("K28 hgatp_mode", 64'(gp.hgatp_mode), 64'd8);
    // hgatp PPN 1:0 read 0 in Sv39x4
    chk("K29 hgatp_ppn",  64'(gp.hgatp_ppn),  64'h8_E000);
    chk("K30 menvcfg_adue",  64'(gp.menvcfg_adue),  64'd1);
    chk("K31 menvcfg_pbmte", 64'(gp.menvcfg_pbmte), 64'd1);
    chk("K32 henvcfg_adue",  64'(gp.henvcfg_adue),  64'd1);
    chk("K33 henvcfg_pbmte", 64'(gp.henvcfg_pbmte), 64'd0);
    chk("K34 ptw pmpcfg same as fe_csr", 64'(gp.pmpcfg == gf.pmpcfg),
        64'd1);
    chk("K35 ptw pmpaddr same as fe_csr", 64'(gp.pmpaddr == gf.pmpaddr),
        64'd1);
    chk("K36 ptw pmpaddr1", 64'(gp.pmpaddr[1]), 64'h2400_0000);
    // The widths of the group members (CSR-6, the replaced ports).
    chk("K37 fe_cfg_t width",  64'($bits(fe_cfg_t)),  64'(1+1+1+32+1+32+16));
    chk("K38 fe_csr_t width",  64'($bits(fe_csr_t)),
        64'(1 + 2 + 4 + 16 + 4 + 16 + 4 + 14 + 16*8 + 16*34));
    chk("K39 ptw_csr_t width", 64'($bits(ptw_csr_t)),
        64'(4 + 24 + 4 + 29 + 4 + 24 + 4 + 16*8 + 16*34));

    $display("tb_csr_tb_pkg: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_csr_tb_pkg: %0d check(s) failed", fail_cnt);
    end else begin
      $finish;
    end
  end

endmodule : tb
