// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    pt_build_pkg.sv
// DATE:    2026-11-13
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// TESTBENCH ONLY (BP-146). A page-table builder for every mode of
// mmu_decisions.md MMU-20 and MMU-32: Sv39, Sv48, Sv57 and Sv39x4,
// Sv48x4, Sv57x4. It maps one page at a time: given a root, a mode, an
// address, a leaf level and a leaf PTE, it writes the path from the root
// to that level, allocating intermediate tables from a pool it owns.
//
// TWO CLASSES.
//   pt_image  the supervisor physical memory the builder has written:
//             every 8-byte word, by its supervisor physical address,
//             and the writes in order. ONE image is shared by every
//             stage of a test (ptw_mem_interfaces.md WM-10, one store).
//   pt_stage  one translation structure: a satp or vsatp structure
//             (x4 = 0) or an hgatp one (x4 = 1). It holds the mode, the
//             root, the table pool and, for a VS-stage, the G-stage
//             whose guest physical memory holds its tables.
//
// HOW A TESTBENCH GETS THE WORDS. The builder never touches a memory
// model. Every word it writes is put in the image and queued; the
// testbench drains the queue into its own model:
//     while (img.pop(a, d)) <write d at supervisor physical address a>;
// tb_ptw writes its word store; tb_fe_top writes its shared program
// image the same way, with no change here. img.get(a) reads back a word
// the builder wrote (0 if it wrote none at a).
//
// THE PATH. map(addr, lvl, pte) walks from the root down to level lvl,
// indexing level l by nine address bits, 12 + 9l + 8 : 12 + 9l, except an
// x4 root, indexed by eleven (MMU-32). At each level above lvl:
//   - no word written there: a table page is allocated from the pool
//     and a non-leaf PTE (V only) to it is written;
//   - a non-leaf PTE (V set, R W X clear): followed;
//   - anything else (a leaf, or an invalid word): a CONFLICT.
// At level lvl the given PTE is written, unless a word is there already:
// the same PTE is accepted and not written again, a different one is a
// CONFLICT. So the builder never overwrites a path already written. The
// PTE at level lvl may be a non-leaf too, so a test can place a bad
// pointer at any level.
// A CONFLICT is $fatal (fails loudly). set_soft(1) instead counts it in
// n_conflict and leaves memory unchanged, for a test of the builder
// itself. Every other misuse (a level above the root, a pool exhausted,
// a misaligned root, an x4 address beyond the mode's width) is always
// $fatal.
// map returns the supervisor physical address of the PTE at level lvl.
//
// A VS-STAGE (set_gstage(g)). Its root, pool and PTE addresses are guest
// physical. Each guest table page it writes is translated through g's
// tables (as written in the image); a page g does not map yet is mapped
// by g at level 0 to a supervisor page from g's backing pool
// (set_back), with the PTE flags given there (default D A U X W R V, so
// a G-stage walk to a VS table page needs no update). The VS-stage root
// page is mapped the first time the root table is written.
//
// The builder knows only the words it wrote: a word the testbench writes
// into its model itself is not seen, so a test that mixes the two keeps
// them apart.
//
// BP-148 ADDITIONS, for tb_fe_top's program writer (fe_tb_writer.svh).
// tb_ptw does not call them, and the paths it takes are the ones before.
//   pt_pool   a page pool several stages share. set_pool(p) makes a
//             stage take its table pages (alloc), and for a G-stage the
//             supervisor pages that back VS table pages (back), from p
//             instead of its own pool, in the order they are asked for.
//             tb_fe_top's writer has always placed every table page of
//             every stage from one bump allocator; this keeps them where
//             it placed them.
//   path(a, lvl)  builds the path to level lvl as map does and returns
//             the supervisor address of the slot at lvl, writing nothing
//             there. For a VS-stage the slot's table page is mapped by
//             the G-stage. map is path followed by the slot's write.
//
// Classes, not package functions, for the reason csr_tb_pkg gives: a
// class method is compiled once. No method calls itself, directly or
// through another object.
// ===================================================================
`ifndef PT_BUILD_PKG_SV
`define PT_BUILD_PKG_SV

package pt_build_pkg;

  import csr_pkg::*;

  typedef logic [63:0] pt_addr_t;
  typedef logic [63:0] pt_word_t;

  localparam int       PT_VPN_BITS  = 9;     // per level, PTESIZE 8
  localparam int       PT_ROOT4_BITS = 11;   // an x4 root's index
  localparam pt_addr_t PT_PAGE      = 64'h1000;
  localparam logic [7:0] PT_F_PTR   = 8'h01;   // a non-leaf: V
  localparam logic [7:0] PT_F_BACK  = 8'hDF;   // D A U X W R V

  // A PTE: PPN bits 53:10, flags 7:0, every other bit 0.
  function automatic pt_word_t pt_pte(input logic [43:0] ppn,
                                      input logic [7:0]  f);
    return {10'd0, ppn, 2'b00, f};
  endfunction

  // ================================================================
  // pt_image: the supervisor physical words written, and their order.
  // ================================================================
  class pt_image;
    pt_word_t w [pt_addr_t];   // by 8-byte aligned supervisor address
    pt_addr_t q_a [$];         // writes not yet drained
    pt_word_t q_d [$];

    function void put(input pt_addr_t a, input pt_word_t d);
      if (a[2:0] != 3'b000)
        $fatal(1, "pt_build_pkg: word address %016h not 8-byte aligned",
               a);
      w[a] = d;
      q_a.push_back(a);
      q_d.push_back(d);
    endfunction

    function logic has(input pt_addr_t a);
      return w.exists(a) ? 1'b1 : 1'b0;
    endfunction

    function pt_word_t get(input pt_addr_t a);
      return w.exists(a) ? w[a] : 64'd0;
    endfunction

    // The next undrained write, in order. 0 when none is left.
    function logic pop(output pt_addr_t a, output pt_word_t d);
      a = '0;
      d = '0;
      if (q_a.size() == 0) return 1'b0;
      a = q_a.pop_front();
      d = q_d.pop_front();
      return 1'b1;
    endfunction
  endclass : pt_image

  // ================================================================
  // pt_pool (BP-148): a page pool shared by several stages.
  // ================================================================
  class pt_pool;
    pt_addr_t nx;              // the next free page
    pt_addr_t top;             // the end of the pool

    function new(input pt_addr_t b, input pt_addr_t t);
      if ((b[11:0] != '0) || (t < b))
        $fatal(1, "pt_build_pkg: bad shared pool %016h to %016h", b, t);
      nx  = b;
      top = t;
    endfunction
  endclass : pt_pool

  // ================================================================
  // pt_stage: one translation structure.
  // ================================================================
  class pt_stage;
    string      name;
    pt_image    img;
    logic [3:0] mode;        // the MODE value, 8, 9 or 10
    logic       x4;          // an hgatp structure
    int         levels;      // 3, 4 or 5
    int         gpa_w;       // x4: the mode's GPA width, 41, 50, 59
    pt_addr_t   root;        // the root table (guest physical for a VS)
    pt_addr_t   pool_nx;     // the next free table page
    pt_addr_t   pool_top;    // the end of the table pool
    pt_stage    gst;         // a VS-stage's G-stage, or null
    pt_addr_t   back_nx;     // x4: supervisor pages for guest tables
    pt_addr_t   back_top;
    logic [7:0] back_f;
    logic       cf_count;    // a conflict is counted, not fatal
    int         n_conflict;
    pt_pool     shp;         // BP-148: a shared pool, or null

    function new(input string nm, input pt_image im, input logic [3:0] m,
                 input logic g, input pt_addr_t rt, input pt_addr_t pb,
                 input pt_addr_t pt);
      name     = nm;
      img      = im;
      mode     = m;
      x4       = g;
      root     = rt;
      pool_nx  = pb;
      pool_top = pt;
      gst      = null;
      back_nx  = '0;
      back_top = '0;
      back_f   = PT_F_BACK;
      cf_count = 1'b0;
      n_conflict = 0;
      shp      = null;
      // MMU-32: 3, 4 or 5 levels. satp, vsatp and hgatp share the values.
      if (m == CSR_SATP_MODE_SV39)      levels = 3;
      else if (m == CSR_SATP_MODE_SV48) levels = 4;
      else if (m == CSR_SATP_MODE_SV57) levels = 5;
      else $fatal(1, "pt_build_pkg %s: MODE %0d does not walk", nm, m);
      // 12 + 9 * levels, and two more at an x4 root: 41, 50, 59.
      gpa_w = 12 + PT_VPN_BITS * levels + 2;
      // The x4 root table is 16 KiB, aligned to 16 KiB (MMU-32).
      if (g && (rt[13:0] != '0))
        $fatal(1, "pt_build_pkg %s: x4 root %016h not 16 KiB aligned",
               nm, rt);
      if (rt[11:0] != '0)
        $fatal(1, "pt_build_pkg %s: root %016h not page aligned", nm, rt);
      if ((pb[11:0] != '0) || (pt < pb))
        $fatal(1, "pt_build_pkg %s: bad pool %016h to %016h", nm, pb, pt);
    endfunction

    // A VS-stage whose tables live in g's guest physical memory.
    function void set_gstage(input pt_stage g);
      if (x4 || (g == null) || !g.x4)
        $fatal(1, "pt_build_pkg %s: a G-stage serves a non-x4 stage",
               name);
      gst = g;
    endfunction

    // The supervisor pages a G-stage maps a VS table page to, and the
    // flags of that level-0 leaf.
    function void set_back(input pt_addr_t b, input pt_addr_t t,
                           input logic [7:0] f);
      if ((b[11:0] != '0) || (t < b))
        $fatal(1, "pt_build_pkg %s: bad backing pool", name);
      back_nx  = b;
      back_top = t;
      back_f   = f;
    endfunction

    function void set_soft(input logic s);
      cf_count = s;
    endfunction

    // BP-148: table pages, and a G-stage's backing pages, from p.
    function void set_pool(input pt_pool p);
      shp = p;
    endfunction

    // The index of addr at level l: nine bits, eleven at an x4 root.
    function int idx(input pt_addr_t a, input int l);
      int       nb;
      pt_addr_t s;
      nb = (x4 && (l == levels - 1)) ? PT_ROOT4_BITS : PT_VPN_BITS;
      s  = a >> (12 + PT_VPN_BITS * l);
      return int'(s & ((64'd1 << nb) - 64'd1));
    endfunction

    function pt_addr_t alloc();
      pt_addr_t r;
      if (shp != null) begin
        if (shp.nx + PT_PAGE > shp.top)
          $fatal(1, "pt_build_pkg %s: shared pool exhausted at %016h", name,
                 shp.nx);
        r      = shp.nx;
        shp.nx = shp.nx + PT_PAGE;
        return r;
      end
      if (pool_nx + PT_PAGE > pool_top)
        $fatal(1, "pt_build_pkg %s: table pool exhausted at %016h", name,
               pool_nx);
      r       = pool_nx;
      pool_nx = pool_nx + PT_PAGE;
      return r;
    endfunction

    function void conflict(input string what, input pt_addr_t a);
      n_conflict++;
      if (cf_count)
        $display("pt_build_pkg %s: conflict (counted): %s at %016h", name,
                 what, a);
      else
        $fatal(1, "pt_build_pkg %s: CONFLICT: %s at %016h", name, what, a);
    endfunction

    // ---- the table space ----------------------------------------------
    // Translate a G-stage-mapped address through this (x4) stage's
    // tables, as written in the image. ok is 0 when it is not mapped.
    // Called on a G-stage only; it reads the image and writes nothing.
    function pt_addr_t xlate(input pt_addr_t a, output logic ok);
      pt_addr_t t;
      pt_addr_t pa;
      pt_word_t e;
      pt_addr_t m;
      pt_addr_t pg;
      ok = 1'b0;
      t  = root;
      for (int l = levels - 1; l >= 0; l--) begin
        pa = t + pt_addr_t'(8 * idx(a, l));
        if (!img.has(pa)) return '0;
        e = img.get(pa);
        if (!e[0]) return '0;
        if (e[1] || e[3]) begin                  // a leaf: R or X
          m  = (64'd1 << (PT_VPN_BITS * l)) - 64'd1;
          pg = (pt_addr_t'(e[53:10]) & ~m) | ((a >> 12) & m);
          if (e[63] && (l == 0))                 // NAPOT 64 KiB
            pg = (pg & ~64'hF) | ((a >> 12) & 64'hF);
          ok = 1'b1;
          return (pg << 12) | (a & 64'hFFF);
        end
        t = pt_addr_t'(e[53:10]) << 12;
      end
      return '0;
    endfunction

    // A G-stage: map guest page ga at level 0 to a new backing page.
    // Called from a VS-stage's wr_t; it writes the image directly.
    function pt_addr_t back(input pt_addr_t ga);
      pt_addr_t sp;
      if (shp != null) begin
        sp = alloc();                          // BP-148, the shared pool
      end else begin
        if (back_nx + PT_PAGE > back_top)
          $fatal(1, "pt_build_pkg %s: backing pool exhausted", name);
        sp      = back_nx;
        back_nx = back_nx + PT_PAGE;
      end
      void'(map_phys(ga & ~64'hFFF, 0, pt_pte(44'(sp >> 12), back_f)));
      return sp;
    endfunction

    // The supervisor address of table-space address ta. A VS-stage maps
    // the guest page through its G-stage, backing it when mk is set.
    function pt_addr_t spa_of(input pt_addr_t ta, input logic mk,
                              output logic ok);
      pt_addr_t s;
      ok = 1'b1;
      if (gst == null) return ta;
      s = gst.xlate(ta, ok);
      if (!ok && mk) begin
        s  = gst.back(ta) | (ta & 64'hFFF);
        ok = 1'b1;
      end
      return s;
    endfunction

    // ---- the path -----------------------------------------------------
    // The path for a stage whose tables are in supervisor physical
    // memory (no G-stage). Used by map, and by back for a G-stage.
    // The path above level lvl, built (BP-148: split out of map_phys);
    // the address of the slot at lvl. ok is 0 on a conflict above lvl,
    // and the address is then that of the conflicting word.
    function pt_addr_t path_phys(input pt_addr_t a, input int lvl,
                                 output logic ok);
      pt_addr_t t;
      pt_addr_t pa;
      pt_word_t e;
      ok = 1'b0;
      chk_args(a, lvl);
      t = root;
      for (int l = levels - 1; l > lvl; l--) begin
        pa = t + pt_addr_t'(8 * idx(a, l));
        if (!img.has(pa)) begin
          e = pt_pte(44'(alloc() >> 12), PT_F_PTR);
          img.put(pa, e);
        end else begin
          e = img.get(pa);
          if (!e[0] || e[1] || e[2] || e[3]) begin
            conflict($sformatf("level %0d holds %016h, not a pointer", l,
                               e), pa);
            return pa;
          end
        end
        t = pt_addr_t'(e[53:10]) << 12;
      end
      ok = 1'b1;
      return t + pt_addr_t'(8 * idx(a, lvl));
    endfunction

    function pt_addr_t map_phys(input pt_addr_t a, input int lvl,
                                input pt_word_t pte);
      pt_addr_t pa;
      logic     ok;
      pa = path_phys(a, lvl, ok);
      if (!ok) return pa;
      if (img.has(pa)) begin
        if (img.get(pa) != pte)
          conflict($sformatf("level %0d holds %016h, not %016h", lvl,
                             img.get(pa), pte), pa);
      end else begin
        img.put(pa, pte);
      end
      return pa;
    endfunction

    // The path for a VS-stage: table addresses are guest physical and
    // each word is placed at its supervisor address through the G-stage.
    // The VS-stage path above level lvl, built (BP-148: split out of
    // map_guest); the supervisor address of the slot at lvl, its table
    // page mapped by the G-stage. ok as path_phys.
    function pt_addr_t path_guest(input pt_addr_t a, input int lvl,
                                  output logic ok);
      pt_addr_t t;
      pt_addr_t ta;
      pt_addr_t pa;
      pt_word_t e;
      logic     sok;
      ok = 1'b0;
      chk_args(a, lvl);
      t = root;
      for (int l = levels - 1; l > lvl; l--) begin
        ta = t + pt_addr_t'(8 * idx(a, l));
        pa = spa_of(ta, 1'b1, sok);
        if (!img.has(pa)) begin
          e = pt_pte(44'(alloc() >> 12), PT_F_PTR);
          img.put(pa, e);
        end else begin
          e = img.get(pa);
          if (!e[0] || e[1] || e[2] || e[3]) begin
            conflict($sformatf("level %0d holds %016h, not a pointer", l,
                               e), pa);
            return pa;
          end
        end
        t = pt_addr_t'(e[53:10]) << 12;
      end
      ta = t + pt_addr_t'(8 * idx(a, lvl));
      ok = 1'b1;
      return spa_of(ta, 1'b1, sok);
    endfunction

    function pt_addr_t map_guest(input pt_addr_t a, input int lvl,
                                 input pt_word_t pte);
      pt_addr_t pa;
      logic     ok;
      pa = path_guest(a, lvl, ok);
      if (!ok) return pa;
      if (img.has(pa)) begin
        if (img.get(pa) != pte)
          conflict($sformatf("level %0d holds %016h, not %016h", lvl,
                             img.get(pa), pte), pa);
      end else begin
        img.put(pa, pte);
      end
      return pa;
    endfunction

    function void chk_args(input pt_addr_t a, input int lvl);
      if ((lvl < 0) || (lvl >= levels))
        $fatal(1, "pt_build_pkg %s: level %0d, the root is %0d", name,
               lvl, levels - 1);
      // An x4 stage translates a GPA below its width only (MMU-20); the
      // eleven-bit root index would alias one above it.
      if (x4 && ((a >> gpa_w) != '0))
        $fatal(1, "pt_build_pkg %s: GPA %016h beyond %0d bits", name, a,
               gpa_w);
    endfunction

    // Map addr: the PTE pte at level lvl. Returns the supervisor address
    // of that PTE.
    function pt_addr_t map(input pt_addr_t a, input int lvl,
                           input pt_word_t pte);
      if (gst == null) return map_phys(a, lvl, pte);
      else             return map_guest(a, lvl, pte);
    endfunction

    // BP-148: the path to level lvl for addr, built as map builds it,
    // and the supervisor address of the slot at lvl; nothing is written
    // at the slot. A caller that writes there itself does so outside
    // the builder.
    function pt_addr_t path(input pt_addr_t a, input int lvl);
      logic ok;
      if (gst == null) return path_phys(a, lvl, ok);
      else             return path_guest(a, lvl, ok);
    endfunction

    // The supervisor address of the PTE at level lvl for addr, along
    // the path written; 0 when the path does not reach it.
    function pt_addr_t pte_addr(input pt_addr_t a, input int lvl);
      pt_addr_t t;
      pt_addr_t pa;
      pt_word_t e;
      logic     ok;
      t = root;
      for (int l = levels - 1; l >= lvl; l--) begin
        pa = spa_of(t + pt_addr_t'(8 * idx(a, l)), 1'b0, ok);
        if (!ok) return '0;
        if (l == lvl) return pa;
        if (!img.has(pa)) return '0;
        e = img.get(pa);
        t = pt_addr_t'(e[53:10]) << 12;
      end
      return '0;
    endfunction
  endclass : pt_stage

endpackage : pt_build_pkg

`endif // PT_BUILD_PKG_SV
