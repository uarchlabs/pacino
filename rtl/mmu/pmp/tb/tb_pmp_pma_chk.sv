// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for pmp_pma_chk (BP-118 Problem 4).
//
// Five instances, each a parameter point:
//   u16   the default: 16 entries, 4 KiB grain, the MMU-15a table
//   u4    PMP_ENTRIES 4, the entry count as a parameter
//   u0    PMP_ENTRIES 0, no PMP implemented
//   ug0   PMP_GRAN_LG2 2 (G = 0), so NA4 and 4-byte TOR are exact
//   u2r   a two-region table, the region table as a parameter
//
// Every expected value is written out by hand from the rule it
// checks; the testbench has no model of the checker. pmpaddr values
// are formed from the privileged encoding (byte address >> 2, NAPOT
// size in the trailing ones), which is independent of the RTL.
//
// THE PMP REGISTERS AND THE PRIVILEGE COME FROM csr_tb_pkg (SYS-001,
// csr_decisions.md CSR-2): an entry is written with csr_write, under
// the CSR-5 rules, and every instance's pmp_cfg and pmp_addr are the
// first entries of pack_fe_csr's pmpcfg and pmpaddr; chk_priv is its
// priv, set by set_priv. One shadow feeds all five instances, so an
// instance sees the entries written for another; every check reads
// one instance. The read-back rules depend on the grain: ug0 (G = 0)
// is written and checked with csr_tb_pkg set_pmp_g(0), every other
// instance with G = 10. Since SYS-001 the checker therefore sees
// pmpaddr as software reads it: G5 (TOR) gets bits 9:0 already clear,
// G6-G7b (NA4 at G = 10) get NAPOT with bits 8:0 set, and G8-G8b
// (an 8-byte NAPOT) get bits 8:0 set. Each still checks the matched
// range; none checks the checker's own low-bit handling any more.
// E4 to E6 rewrote a locked entry, which csr_write ignores (CSR-5):
// they start from csr_reset and write the locked entry afresh.
//
// Groups:
//   A  PMP no-match: M allowed, S and U denied when implemented
//   B  NAPOT match across its range, both ends and just outside
//   C  TOR, entry 0 from address 0, entry i from entry i-1
//   D  lowest-numbered matching entry decides
//   E  the L bit
//   F  entry count 0 and 4
//   G  the granule: NA4 exact at G = 0, widened at G = 10, TOR low
//      bits cleared at G = 10
//   H  the MMU-15a region table at both ends of main memory
//   I  effective type with PBMT, MMU-U6
//   J  a two-region table
//   K  access types: R and W faulted by the PMP only
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;
import csr_pkg::*;

module tb;

  localparam int AW = PA_WIDTH - 2;

  // cfg encodings
  localparam logic [7:0] R    = 8'h01;
  localparam logic [7:0] W    = 8'h02;
  localparam logic [7:0] X    = 8'h04;
  localparam logic [7:0] TOR  = 8'h08;
  localparam logic [7:0] NA4  = 8'h10;
  localparam logic [7:0] NAP  = 8'h18;
  localparam logic [7:0] L    = 8'h80;

  localparam logic [1:0] AR = 2'd0, AWR = 2'd1, AX = 2'd2;
  localparam logic [1:0] PU = 2'd0, PS = 2'd1, PM = 2'd3;

  // ---- shared access inputs ----------------------------------------
  logic [PA_WIDTH-1:0] pa;
  logic [1:0]          acc;
  logic [1:0]          prv;
  logic [1:0]          pbmt;

  // ---- per-instance PMP registers ----------------------------------
  logic [15:0][7:0]    cfg16;
  logic [15:0][AW-1:0] adr16;
  logic [3:0][7:0]     cfg4;
  logic [3:0][AW-1:0]  adr4;
  logic [0:0][7:0]     cfg0;
  logic [0:0][AW-1:0]  adr0;
  logic [3:0][7:0]     cfgg;
  logic [3:0][AW-1:0]  adrg;
  logic [15:0][7:0]    cfg2;
  logic [15:0][AW-1:0] adr2;

  logic                ok16, ok4, ok0, okg, ok2;
  logic                f16, f4, f0, fg, f2;
  logic [3:0]          a16, a4, a0, ag, a2;

  pmp_pma_chk u16 (
    .chk_pa (pa), .chk_acc (acc), .chk_priv (prv), .chk_pbmt (pbmt),
    .pmp_cfg (cfg16), .pmp_addr (adr16),
    .chk_pmp_ok (ok16), .chk_pma (a16), .chk_fault (f16));

  pmp_pma_chk #(.PMP_ENTRIES (4)) u4 (
    .chk_pa (pa), .chk_acc (acc), .chk_priv (prv), .chk_pbmt (pbmt),
    .pmp_cfg (cfg4), .pmp_addr (adr4),
    .chk_pmp_ok (ok4), .chk_pma (a4), .chk_fault (f4));

  pmp_pma_chk #(.PMP_ENTRIES (0)) u0 (
    .chk_pa (pa), .chk_acc (acc), .chk_priv (prv), .chk_pbmt (pbmt),
    .pmp_cfg (cfg0), .pmp_addr (adr0),
    .chk_pmp_ok (ok0), .chk_pma (a0), .chk_fault (f0));

  pmp_pma_chk #(.PMP_ENTRIES (4), .PMP_GRAN_LG2 (2)) ug0 (
    .chk_pa (pa), .chk_acc (acc), .chk_priv (prv), .chk_pbmt (pbmt),
    .pmp_cfg (cfgg), .pmp_addr (adrg),
    .chk_pmp_ok (okg), .chk_pma (ag), .chk_fault (fg));

  // A ROM region below main memory: executable and idempotent, neither
  // cacheable nor coherent. BP-123: this was 4'b0100, executable and
  // not idempotent, which MMU-15b forbids and the checker now rejects
  // at elaboration (lint_neg_pma); MMU-15b puts executable device
  // memory such as a boot ROM in an idempotent region.
  pmp_pma_chk #(
    .PMA_REGIONS (2),
    .PMA_BASE    ({36'h0_8000_0000, 36'h0_1000_0000}),
    .PMA_TOP     ({36'hF_FFFF_FFFF, 36'h0_1000_0FFF}),
    .PMA_ATTR    ({4'b1111,         4'b1100})
  ) u2r (
    .chk_pa (pa), .chk_acc (acc), .chk_priv (prv), .chk_pbmt (pbmt),
    .pmp_cfg (cfg2), .pmp_addr (adr2),
    .chk_pmp_ok (ok2), .chk_pma (a2), .chk_fault (f2));

  int pass_cnt = 0;
  int fail_cnt = 0;

  // NAPOT pmpaddr for a naturally aligned region of size bytes.
  function automatic logic [AW-1:0] napot(input logic [PA_WIDTH-1:0] b,
                                          input longint sz);
    return AW'(b >> 2) | AW'((sz / 8) - 1);
  endfunction

  function automatic logic [AW-1:0] tora(input logic [PA_WIDTH-1:0] a);
    return AW'(a >> 2);
  endfunction

  // ---- the PMP registers, from csr_tb_pkg (SYS-001) ----------------
  // Drive every instance's registers and the privilege from the pack.
  task automatic sync();
    fe_csr_t g;
    g     = csr_tb_pkg::pack_fe_csr();
    cfg16 = g.pmpcfg;            adr16 = g.pmpaddr;
    cfg4  = g.pmpcfg[3:0];       adr4  = g.pmpaddr[3:0];
    cfg0  = g.pmpcfg[0:0];       adr0  = g.pmpaddr[0:0];
    cfgg  = g.pmpcfg[3:0];       adrg  = g.pmpaddr[3:0];
    cfg2  = g.pmpcfg;            adr2  = g.pmpaddr;
    prv   = g.priv;
  endtask

  // pmpcfg byte k, by read-modify-write of pmpcfg0 or pmpcfg2, at grain
  // G (10 for every instance but ug0, 0 for ug0).
  task automatic wr_cfg_at(input int g, input int k, input logic [7:0] b);
    logic [11:0] ca;
    pmpcfg_t     c;
    csr_tb_pkg::set_pmp_g(g);
    ca = (k < 8) ? CSR_PMPCFG0_ADDR : CSR_PMPCFG2_ADDR;
    c  = pmpcfg_t'(csr_tb_pkg::csr_read(ca));
    c.ent[k % 8] = pmpcfg_ent_t'(b);
    csr_tb_pkg::csr_write(ca, 64'(c));
    sync();
  endtask

  task automatic wr_adr_at(input int g, input int k, input logic [AW-1:0] a);
    csr_tb_pkg::set_pmp_g(g);
    csr_tb_pkg::csr_write(CSR_PMPADDR0_ADDR + 12'(k), 64'(a));
    sync();
  endtask

  task automatic wr_cfg(input int k, input logic [7:0] b);
    wr_cfg_at(CSR_PMP_G, k, b);
  endtask
  task automatic wr_adr(input int k, input logic [AW-1:0] a);
    wr_adr_at(CSR_PMP_G, k, a);
  endtask
  task automatic wr_cfg_g0(input int k, input logic [7:0] b);
    wr_cfg_at(0, k, b);
  endtask
  task automatic wr_adr_g0(input int k, input logic [AW-1:0] a);
    wr_adr_at(0, k, a);
  endtask

  // Every entry OFF with pmpaddr 0 (csr_reset, then entry 0 cleared:
  // the reset value of entry 0 is NAPOT over all of memory).
  task automatic clr();
    csr_tb_pkg::csr_reset();
    csr_tb_pkg::csr_write(CSR_PMPCFG0_ADDR, 64'h0);
    csr_tb_pkg::csr_write(CSR_PMPADDR0_ADDR, 64'h0);
    sync();
    pbmt  = 2'd0;
    acc   = AX;
  endtask

  // Drive one access and compare one instance's outputs.
  task automatic chk(input string nm, input int inst,
                     input logic [PA_WIDTH-1:0] a, input logic [1:0] p,
                     input logic e_ok, input logic e_f,
                     input logic [3:0] e_pma);
    logic g_ok, g_f;
    logic [3:0] g_pma;
    pa  = a;
    // the instance's grain for the read-back, and the privilege
    csr_tb_pkg::set_pmp_g((inst == 1) ? 0 : CSR_PMP_G);
    csr_tb_pkg::set_priv(p);
    sync();
    #1;
    case (inst)
      16:      begin g_ok = ok16; g_f = f16; g_pma = a16; end
      4:       begin g_ok = ok4;  g_f = f4;  g_pma = a4;  end
      0:       begin g_ok = ok0;  g_f = f0;  g_pma = a0;  end
      1:       begin g_ok = okg;  g_f = fg;  g_pma = ag;  end
      default: begin g_ok = ok2;  g_f = f2;  g_pma = a2;  end
    endcase
    if (g_ok === e_ok && g_f === e_f && g_pma === e_pma) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL %s: pa=%h prv=%0d ok=%b/%b fault=%b/%b pma=%b/%b",
               nm, a, p, g_ok, e_ok, g_f, e_f, g_pma, e_pma);
    end
  endtask

  // Main memory and outside it, MMU-15a.
  localparam logic [3:0] MM = 4'b1111;
  localparam logic [3:0] NO = 4'b0000;

  initial begin
    clr();

    // ---- A: no match ------------------------------------------------
    // 16 entries implemented, all OFF. Main memory so PMA allows X.
    chk("A1 M no match allowed",  16, 36'h0_8000_0000, PM, 1, 0, MM);
    chk("A2 S no match denied",   16, 36'h0_8000_0000, PS, 0, 1, MM);
    chk("A3 U no match denied",   16, 36'h0_8000_0000, PU, 0, 1, MM);

    // ---- B: NAPOT 64 KiB at 0x8000_0000, X only --------------------
    wr_cfg(0, NAP | X);
    wr_adr(0, napot(36'h0_8000_0000, 64'h1_0000));
    chk("B1 NAPOT low end",       16, 36'h0_8000_0000, PS, 1, 0, MM);
    chk("B2 NAPOT high page",     16, 36'h0_8000_F000, PS, 1, 0, MM);
    chk("B3 NAPOT just above",    16, 36'h0_8001_0000, PS, 0, 1, MM);
    chk("B4 NAPOT just below",    16, 36'h0_7FFF_F000, PS, 0, 1, NO);
    chk("B5 NAPOT U mode",        16, 36'h0_8000_8000, PU, 1, 0, MM);
    acc = AR;
    chk("B6 NAPOT read, R clear", 16, 36'h0_8000_0000, PS, 0, 1, MM);
    acc = AX;
    // the whole space: every pmpaddr bit set
    wr_adr(0, '1);
    wr_cfg(0, NAP | R | W | X);
    chk("B7 NAPOT all, bottom",   16, 36'h0_0000_0000, PS, 1, 1, NO);
    chk("B8 NAPOT all, top",      16, 36'hF_FFFF_F000, PS, 1, 0, MM);

    // ---- C: TOR -------------------------------------------------------
    clr();
    wr_cfg(0, TOR | X);
    wr_adr(0, tora(36'h0_9000_0000));
    chk("C1 TOR e0 base 0",       16, 36'h0_0000_0000, PS, 1, 1, NO);
    chk("C2 TOR e0 last page",    16, 36'h0_8FFF_F000, PS, 1, 0, MM);
    chk("C3 TOR e0 top excl",     16, 36'h0_9000_0000, PS, 0, 1, MM);
    clr();
    // entry 0 OFF still supplies entry 1's base
    wr_adr(0, tora(36'h0_8000_2000));
    wr_cfg(1, TOR | X);
    wr_adr(1, tora(36'h0_8000_4000));
    chk("C4 TOR e1 base incl",    16, 36'h0_8000_2000, PS, 1, 0, MM);
    chk("C5 TOR e1 last page",    16, 36'h0_8000_3000, PS, 1, 0, MM);
    chk("C6 TOR e1 below base",   16, 36'h0_8000_1000, PS, 0, 1, MM);
    chk("C7 TOR e1 top excl",     16, 36'h0_8000_4000, PS, 0, 1, MM);
    // top <= base matches nothing
    wr_adr(1, tora(36'h0_8000_1000));
    chk("C8 TOR empty range",     16, 36'h0_8000_1000, PS, 0, 1, MM);

    // ---- D: priority --------------------------------------------------
    clr();
    wr_cfg(0, NAP);                              // no permission
    wr_adr(0, napot(36'h0_8000_0000, 64'h1000));
    wr_cfg(1, NAP | R | W | X);
    wr_adr(1, '1);
    chk("D1 e0 decides, denies",  16, 36'h0_8000_0000, PS, 0, 1, MM);
    chk("D2 e1 decides outside",  16, 36'h0_8000_1000, PS, 1, 0, MM);
    clr();
    wr_cfg(0, NAP | R | W | X);
    wr_adr(0, '1);
    wr_cfg(1, NAP);
    wr_adr(1, napot(36'h0_8000_0000, 64'h1000));
    chk("D3 e0 decides, allows",  16, 36'h0_8000_0000, PS, 1, 0, MM);
    clr();
    // the match is at entry 15, the last implemented
    wr_cfg(15, NAP | X);
    wr_adr(15, napot(36'h0_8000_0000, 64'h1000));
    chk("D4 entry 15 matches",    16, 36'h0_8000_0000, PS, 1, 0, MM);

    // ---- E: the L bit -------------------------------------------------
    clr();
    wr_cfg(0, NAP | R);                          // X clear
    wr_adr(0, napot(36'h0_8000_0000, 64'h1000));
    chk("E1 L clear, M bypass",   16, 36'h0_8000_0000, PM, 1, 0, MM);
    chk("E2 L clear, S denied",   16, 36'h0_8000_0000, PS, 0, 1, MM);
    wr_cfg(0, L | NAP | R);
    chk("E3 L set, M denied",     16, 36'h0_8000_0000, PM, 0, 1, MM);
    // A locked entry is not written (CSR-5): reset, then lock it with X.
    clr();
    wr_adr(0, napot(36'h0_8000_0000, 64'h1000));
    wr_cfg(0, L | NAP | X);
    chk("E4 L set X, M allowed",  16, 36'h0_8000_0000, PM, 1, 0, MM);
    chk("E5 L set X, S allowed",  16, 36'h0_8000_0000, PS, 1, 0, MM);
    // a locked entry that does not match leaves M no-match allowed
    chk("E6 L set, M no match",   16, 36'h0_8000_1000, PM, 1, 0, MM);

    // ---- F: entry count ----------------------------------------------
    clr();
    chk("F1 none impl, S ok",      0, 36'h0_8000_0000, PS, 1, 0, MM);
    chk("F2 none impl, U ok",      0, 36'h0_0000_0000, PU, 1, 1, NO);
    chk("F3 four impl, S denied",  4, 36'h0_8000_0000, PS, 0, 1, MM);
    wr_cfg(3, NAP | X);
    wr_adr(3, napot(36'h0_8000_0000, 64'h1000));
    chk("F4 four impl, e3",        4, 36'h0_8000_0000, PS, 1, 0, MM);

    // ---- G: the granule -----------------------------------------------
    clr();
    // G = 0: NA4 is exact.
    wr_cfg_g0(0, NA4 | X);
    wr_adr_g0(0, tora(36'h0_8000_0004));
    chk("G1 NA4 exact hit",        1, 36'h0_8000_0004, PS, 1, 0, MM);
    chk("G2 NA4 below",            1, 36'h0_8000_0000, PS, 0, 1, MM);
    chk("G3 NA4 above",            1, 36'h0_8000_0008, PS, 0, 1, MM);
    // G = 0: a TOR top keeps its low bits.
    wr_cfg_g0(0, TOR | X);
    wr_adr_g0(0, tora(36'h0_1000_0800));
    chk("G4 G0 TOR top exact",     1, 36'h0_1000_0000, PS, 1, 1, NO);
    // G = 10: the same TOR top loses bits below 4 KiB, so 0x1000_0000
    // is at the top and excluded.
    wr_cfg(0, TOR | X);
    wr_adr(0, tora(36'h0_1000_0800));
    chk("G5 G10 TOR top cleared", 16, 36'h0_1000_0000, PS, 0, 1, NO);
    // G = 10: NA4 widens to one 4 KiB granule.
    wr_cfg(0, NA4 | X);
    wr_adr(0, tora(36'h0_8000_0004));
    chk("G6 G10 NA4 granule",     16, 36'h0_8000_0000, PS, 1, 0, MM);
    chk("G7 G10 NA4 next page",   16, 36'h0_8000_1000, PS, 0, 1, MM);
    // the granule's last word: not matched by an exact 4-byte NA4
    chk("G7b G10 NA4 granule end",16, 36'h0_8000_0FFC, PS, 1, 0, MM);
    // G = 10: an 8-byte NAPOT widens to the granule as well.
    wr_cfg(0, NAP | X);
    wr_adr(0, napot(36'h0_8000_0008, 64'd8));
    chk("G8 G10 NAPOT8 granule",  16, 36'h0_8000_0000, PS, 1, 0, MM);
    chk("G8b G10 NAPOT8 gran end",16, 36'h0_8000_0FF0, PS, 1, 0, MM);

    // ---- H: the MMU-15a region table ---------------------------------
    // PMP allows everything; only the PMA decides.
    clr();
    wr_cfg(0, NAP | R | W | X);
    wr_adr(0, '1);
    chk("H1 below main memory",   16, 36'h0_7FFF_F000, PS, 1, 1, NO);
    chk("H2 main memory base",    16, 36'h0_8000_0000, PS, 1, 0, MM);
    chk("H3 main memory top pg",  16, 36'hF_FFFF_F000, PS, 1, 0, MM);
    chk("H4 main memory top B",   16, 36'hF_FFFF_FFFF, PS, 1, 0, MM);
    chk("H5 address zero",        16, 36'h0_0000_0000, PS, 1, 1, NO);
    chk("H6 M below main memory", 16, 36'h0_7FFF_FFFF, PM, 1, 1, NO);

    // ---- I: effective type, MMU-U6 ------------------------------------
    pbmt = 2'd1;  // NC
    chk("I1 NC clears cacheable", 16, 36'h0_8000_0000, PS, 1, 0, 4'b1110);
    pbmt = 2'd2;  // IO
    chk("I2 IO clears c and i",   16, 36'h0_8000_0000, PS, 1, 0, 4'b0110);
    pbmt = 2'd3;  // reserved, taken as IO
    chk("I3 rsvd as IO",          16, 36'h0_8000_0000, PS, 1, 0, 4'b0110);
    pbmt = 2'd1;
    chk("I4 NC outside memory",   16, 36'h0_0000_0000, PS, 1, 1, NO);
    pbmt = 2'd0;

    // ---- J: a two-region table ---------------------------------------
    wr_cfg(0, NAP | R | W | X);
    wr_adr(0, '1);
    chk("J1 device base",          2, 36'h0_1000_0000, PS, 1, 0, 4'b1100);
    chk("J2 device top byte",      2, 36'h0_1000_0FFF, PS, 1, 0, 4'b1100);
    chk("J3 above device",         2, 36'h0_1000_1000, PS, 1, 1, NO);
    chk("J4 main memory",          2, 36'h0_8000_0000, PS, 1, 0, MM);
    pbmt = 2'd0;

    // ---- K: access types ----------------------------------------------
    acc = AR;
    chk("K1 read non-exec region",16, 36'h0_0000_0000, PS, 1, 0, NO);
    acc = AWR;
    chk("K2 write non-exec",      16, 36'h0_0000_0000, PS, 1, 0, NO);
    wr_cfg(0, NAP | R);
    chk("K3 write, W clear",      16, 36'h0_8000_0000, PS, 0, 1, MM);
    acc = AX;

    $display("tb_pmp_pma_chk: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_pmp_pma_chk: %0d check(s) failed", fail_cnt);
    end else begin
      $finish;
    end
  end

endmodule : tb
