// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    pt_gen.sv
// DATE:    2026-11-14
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// TESTBENCH PROGRAM (BP-149): the trace page-table generator of
// perf_decisions.md PF-17, built on pt_build_pkg. Not a testbench of a
// DUT: it is a program, run by rtl/mmu/ptw/Makefile (sim_pt_gen), and
// its module is named for its file.
//
// USE
//   Vpt_gen +IN=<pages file> +OUT=<image file> [+MEM_TOP=<hex>]
//
// INPUT (+IN). One hexadecimal virtual address per line, an optional 0x
// prefix allowed. Each address names its 4 KiB page. Pages are taken in
// the order they first appear; a repeated page is ignored. Blank lines
// and lines whose first character is # are skipped.
//
// MAPPING. The mode is Sv57 (mmu_decisions.md MMU-20). Each page gets a
// 4 KiB leaf, V R X A U set, W D G clear (PF_LEAF). Its physical page is
// allocated densely in first-touch order from MEM_BASE, the start of
// main memory
// (mmu_decisions.md MMU-15a). The table pages come from a pool that
// starts at the first page after the last code page: the root first,
// then each table in the order the builder asks for it.
//
// OUTPUT (+OUT), text, every value hexadecimal with no prefix:
//   # <the generator and the input>          header comments
//   satp <16 digits>                          MODE Sv57, ASID 0, the root
//   map <va> <pa>                             one per page, first touch
//   word <pa> <data>                          one per table word, in the
//                                             order pt_image pop gives
// PERF-002's gasket reads this file; rtl/mmu/ptw sim_ptw_img loads it
// into tb_ptw's memory model and walks every page with the walker.
//
// ERRORS, each $fatal naming the input: a line that is not a hexadecimal
// address, or an address not canonical under Sv57 (bits 63:57 not all
// equal to bit 56), naming the line; an input whose pages and tables do
// not fit main memory, MEM_BASE to MEM_TOP. MEM_TOP is 2^PA_WIDTH, the
// top of main memory (MMU-15a); +MEM_TOP lowers it, to show that error
// with a small input.
//
// THE TABLE COUNT is planned before the build, from the rule: one root,
// and at each level l from 0 to 3 one table per distinct value of VA
// bits 56 : 21 + 9l (MMU-32, nine index bits per level). The build is
// checked to allocate exactly that many.
// ===================================================================
import bp_defines_pkg::*;
import csr_pkg::*;

module pt_gen;

  localparam logic [63:0] MEM_BASE = 64'h0_8000_0000;     // MMU-15a
  localparam logic [63:0] PG       = 64'h1000;
  localparam logic [7:0]  PF_LEAF  = 8'h5B;               // A U X R V
  localparam int          SV57_LVL = 5;                   // MMU-32

  string       fin;
  string       fout;
  logic [63:0] mem_top;
  logic [63:0] pages [$];          // page VAs, first-touch order
  logic        seen [logic [63:0]];
  int          n_lines;
  int          n_addr;

  // The value of hex digit c, or -1.
  function automatic int hexval(input byte c);
    int v;
    v = int'(c);
    if ((v >= 48) && (v <= 57))  return v - 48;         // 0 to 9
    if ((v >= 97) && (v <= 102)) return v - 97 + 10;    // a to f
    if ((v >= 65) && (v <= 70))  return v - 65 + 10;    // A to F
    return -1;
  endfunction

  function automatic logic is_space(input byte c);
    return (c == " ") || (c == "\t") || (c == "\n") || (c == "\r");
  endfunction

  // Read the input: the distinct pages, in first-touch order.
  task automatic read_input();
    int          fd;
    int          r;
    int          b;
    int          e;
    int          v;
    int          nd;
    string       line;
    string       s;
    logic [63:0] a;
    logic [63:0] pg;
    fd = $fopen(fin, "r");
    if (fd == 0) $fatal(1, "pt_gen: cannot open the input %s", fin);
    n_lines = 0;
    n_addr  = 0;
    while (!$feof(fd)) begin
      line = "";
      r = $fgets(line, fd);
      if (r == 0) break;
      n_lines++;
      // Trim the leading and trailing white space.
      b = 0;
      e = line.len();
      while ((b < e) && is_space(line[b])) b++;
      while ((e > b) && is_space(line[e - 1])) e--;
      if (b == e) continue;
      if (line[b] == "#") continue;
      s = line.substr(b, e - 1);
      if ((s.len() > 2) && (s[0] == "0") && ((s[1] == "x") || (s[1] == "X")))
        s = s.substr(2, s.len() - 1);
      if ((s.len() == 0) || (s.len() > 16))
        $fatal(1, "pt_gen: %s line %0d: '%s' is not a hexadecimal address",
               fin, n_lines, line.substr(b, e - 1));
      a  = '0;
      nd = s.len();
      for (int k = 0; k < nd; k++) begin
        v = hexval(s[k]);
        if (v < 0)
          $fatal(1, "pt_gen: %s line %0d: '%s' is not a hexadecimal address",
                 fin, n_lines, line.substr(b, e - 1));
        a = (a << 4) | 64'(v);
      end
      // Canonical under Sv57: bits 63:57 equal bit 56.
      if ((a[63:56] != 8'h00) && (a[63:56] != 8'hFF))
        $fatal(1, "pt_gen: %s line %0d: address %016h is not canonical %s",
               fin, n_lines, a, "under Sv57 (bits 63:57 differ from bit 56)");
      n_addr++;
      pg = a & ~(PG - 64'd1);
      if (!seen.exists(pg)) begin
        seen[pg] = 1'b1;
        pages.push_back(pg);
      end
    end
    $fclose(fd);
  endtask

  // The table pages the pages need: one root, and at each level l from
  // 0 to 3 one per distinct VA[56 : 21 + 9l].
  function automatic int plan_tables();
    int          n;
    logic [63:0] key;
    logic        tk [logic [63:0]];
    n = 1;
    for (int l = 0; l < SV57_LVL - 1; l++) begin
      tk.delete();
      foreach (pages[i]) begin
        key = (pages[i] >> (21 + 9 * l)) &
              ((64'd1 << (57 - 21 - 9 * l)) - 64'd1);
        tk[key] = 1'b1;
      end
      n += tk.size();
    end
    return n;
  endfunction

  initial begin
    pt_build_pkg::pt_image img;
    pt_build_pkg::pt_stage st;
    logic [63:0] root;
    logic [63:0] pa;
    logic [63:0] a;
    logic [63:0] d;
    logic [63:0] satp;
    logic [63:0] cap;
    int          nt;
    int          used;
    int          nw;
    int          fd;
    if (!$value$plusargs("IN=%s", fin))
      $fatal(1, "pt_gen: +IN=<file of page addresses> is required");
    if (!$value$plusargs("OUT=%s", fout))
      $fatal(1, "pt_gen: +OUT=<image file> is required");
    mem_top = 64'd1 << PA_WIDTH;
    if ($value$plusargs("MEM_TOP=%h", mem_top))
      $display("pt_gen: main memory forced to end at %016h", mem_top);
    if ((mem_top[11:0] != '0) || (mem_top <= MEM_BASE))
      $fatal(1, "pt_gen: MEM_TOP %016h is not a page above %016h", mem_top,
             MEM_BASE);

    read_input();
    if (pages.size() == 0)
      $fatal(1, "pt_gen: %s names no page", fin);

    // The capacity check, before anything is built.
    nt  = plan_tables();
    cap = (mem_top - MEM_BASE) / PG;
    if (64'(pages.size() + nt) > cap)
      $fatal(1, "pt_gen: %s: %0d pages and %0d table pages do not fit %s",
             fin, pages.size(), nt,
             $sformatf("main memory, %016h to %016h, %0d pages", MEM_BASE,
                       mem_top, cap));

    // The build. The code pages from MEM_BASE, the root after them, the
    // other tables from the page after the root.
    root = MEM_BASE + 64'(pages.size()) * PG;
    img  = new();
    st   = new("pt_gen", img, CSR_SATP_MODE_SV57, 1'b0, root, root + PG,
               mem_top);
    foreach (pages[i]) begin
      pa = MEM_BASE + 64'(i) * PG;
      void'(st.map(pages[i], 0, pt_build_pkg::pt_pte(44'(pa >> 12),
                                                     PF_LEAF)));
    end
    used = 1 + int'((st.pool_nx - (root + PG)) / PG);
    if (used != nt)
      $fatal(1, "pt_gen: the build used %0d table pages, the plan %0d", used,
             nt);

    // The image.
    satp = {CSR_SATP_MODE_SV57, 16'd0, 44'(root >> 12)};
    fd = $fopen(fout, "w");
    if (fd == 0) $fatal(1, "pt_gen: cannot open the output %s", fout);
    $fdisplay(fd, "# pt_gen (BP-149, perf_decisions.md PF-17): Sv57 %s",
              "page tables, 4 KiB leaves V R X A U");
    $fdisplay(fd, "# input %s", fin);
    $fdisplay(fd, "# %0d pages from %0d addresses, %0d table pages",
              pages.size(), n_addr, nt);
    $fdisplay(fd, "satp %h", satp);
    foreach (pages[i]) begin
      pa = MEM_BASE + 64'(i) * PG;
      $fdisplay(fd, "map %h %h", pages[i], pa);
    end
    nw = 0;
    while (img.pop(a, d)) begin
      $fdisplay(fd, "word %h %h", a, d);
      nw++;
    end
    $fclose(fd);
    $display("pt_gen: %s: %0d lines, %0d addresses, %0d pages, %0d %s", fin,
             n_lines, n_addr, pages.size(), nt, "table pages");
    $display("pt_gen: %0d words, root %016h, satp %016h -> %s", nw, root,
             satp, fout);
    $finish;
  end

endmodule : pt_gen
