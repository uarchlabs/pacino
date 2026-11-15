// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Unit testbench for ptw (BP-123). mmu_decisions.md, the client port
// of itlb_l2tlb_interfaces.md and the memory port of
// ptw_mem_interfaces.md.
//
// THE MEMORY MODEL answers ptw_mem_* from one store of 64-bit words.
// READ returns the word; CAS compares and stores atomically and returns
// the old word (WM-5). The model can
//   - hold ptw_mem_req_rdy low on a pattern and vary the latency
//     (WM-13)
//   - return mem_ptw_rsp_err on the n-th access (WM-12)
//   - overwrite a word just before a chosen CAS is performed, so the
//     compare fails (WM-11)
// and it checks WM-1 (8-byte aligned), WM-3 (one outstanding) and WM-2
// (fields stable while waiting) on every access.
//
// Every test builds its page tables from reset state: the store is
// cleared, the CSR group set, then the tables written, so no test
// depends on another (CLAUDE.md, no test debt). Expected results are
// derived here from the tables the test wrote, not read from the DUT.
//
// The data-side D update (MMU-8) is covered here: itlb_l2t_acc = W.
//
// BP-124. itlb_l2t_priv (IL-3d) is driven from req_priv, S unless a
// test sets it. The faulting GPA is FAULT_GPA_WIDTH bits and is
// returned whole (MMU-23): h_gpa_bit55_leaf and h_gpa_bit55_nonleaf.
// The cause follows the access type (MMU-24c). Every check MMU-8c names
// is made before the A/D update: t_leaf_checks fails each, at each
// stage it applies to, on a leaf with A clear under Svadu, and checks
// the fault, that no CAS was issued and that the PTE is unchanged.
// t_causes: the access-fault and guest-page-fault causes of a read
// and a store (5, 7, 21, 23).
//
// BP-146. Every mode (mmu_decisions.md MMU-20, MMU-32): t_m_a to t_m_k
// are the cases a to k of BP-146 Problem 4, and t_bld checks the page-
// table builder itself. Each builds its tables with pt_build_pkg (the
// builder writes an image; bsync drains it into the word store), from
// reset state. The tables of the earlier tests were written by hand for
// Sv39 and Sv39x4 (path3, gpath3, gmap, vspath) until BP-149.
//
// BP-149. THE KNOB, +PT_MODE=sv39|sv48|sv57, sv57 when absent
// (PROJECT_CORE.md, TRANSLATION MODES; the Makefile passes it from make
// variable PT_MODE). Every test before t_bld builds its tables with
// pt_build_pkg in the knob's mode: satp and vsatp take that mode, hgatp
// the x4 mode of the same depth. Every expected value that depends on
// the mode (the levels, the access counts and indices, the PTE
// addresses) is formed from it. Each test makes the checks it made at
// BP-148, in every mode, so the check count is the same at every knob.
// The tests that name their modes, in every run:
//   - t_bld and t_m_a to t_m_k (BP-146, BP-147): their subject is a mode
//     or a comparison of modes;
//   - t_wide and the five h_gpa_wide / h_gpa_bit55 cases of t_h_faults:
//     the Sv39x4 GPA bound, which no GPA reaches under Sv57x4 (a mode's
//     limit). hgatp is Sv39x4; vsatp, not their subject, follows the
//     knob.
// One PTE is written directly, not through the builder: h_gpf_read's
// zero at the G-stage leaf of a VS table page, a word the builder
// cannot place where its own backing leaf for that page is (bg.pte_addr
// gives the address). Every other bad PTE is placed by the builder;
// the G-stage leaf of a VS table page with given flags through
// vspath_tf (pt_stage back_f, as tb_fe_top's h_map_tf).
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;
import csr_pkg::*;

module tb;

  // BP-145: the widths the literals below stand for.
  //   VW   the request VPN, VA_WIDTH - 12 (IL-1a)
  // BP-149 removed S39V, G4 and G4P, the Sv39 and Sv39x4 bounds the
  // hand-built tables were typed by; t_wide names SV39X4_GPA_WIDTH.
  localparam int VW   = VA_WIDTH - 12;
  // Short names for the implementation widths, so a cast fits a line:
  // PW the PA, PNW the PPN, FW a faulting GPA, PMW pmpaddr.
  localparam int PW   = PA_WIDTH;
  localparam int PNW  = PPN_WIDTH;
  localparam int FW   = FAULT_GPA_WIDTH;
  localparam int PMW  = CSR_PMPADDR_W;

  logic clk;
  logic rstn;
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ---- DUT ports -------------------------------------------------------
  logic                     itlb_l2t_req_val;
  logic                     itlb_l2t_req_rdy;
  logic [VA_WIDTH-13:0]     itlb_l2t_vpn;
  logic [ASID_WIDTH-1:0]    itlb_l2t_asid;
  logic [VMID_WIDTH-1:0]    itlb_l2t_vmid;
  logic                     itlb_l2t_v;
  logic [1:0]               itlb_l2t_tag;
  logic [1:0]               itlb_l2t_acc;
  logic [1:0]               itlb_l2t_priv;
  logic                     l2t_itlb_rsp_val;
  logic [1:0]               l2t_itlb_tag;
  logic [1:0]               l2t_itlb_status;
  logic [PPN_WIDTH-1:0]     l2t_itlb_ppn;
  logic [2:0]               l2t_itlb_size;
  logic [PERM_WIDTH-1:0]    l2t_itlb_perm;
  logic [1:0]               l2t_itlb_pbmt;
  logic [CAUSE_WIDTH-1:0]   l2t_itlb_cause;
  logic [FAULT_GPA_WIDTH-1:0] l2t_itlb_gpa;
  logic [1:0]               l2t_itlb_gpa_imp;
  logic                     ptw_mem_req_val;
  logic                     ptw_mem_req_rdy;
  logic                     ptw_mem_req_op;
  logic [PA_WIDTH-1:0]      ptw_mem_req_paddr;
  logic [63:0]              ptw_mem_req_cmp;
  logic [63:0]              ptw_mem_req_swap;
  logic                     mem_ptw_rsp_val;
  logic [63:0]              mem_ptw_rsp_data;
  logic                     mem_ptw_rsp_err;
  // The CSR group (SYS-001, csr_decisions.md CSR-2): driven only by
  // cs_sync() from csr_tb_pkg pack_ptw_csr. The cs_* tasks change one
  // field through csr_tb_pkg and drive the group again.
  ptw_csr_t                 ptw_csr;

  ptw dut (.*);

  // ---- constants -------------------------------------------------------
  localparam logic [1:0] ACC_R = 2'd0;
  localparam logic [1:0] ACC_W = 2'd1;
  localparam logic [1:0] ACC_X = 2'd2;
  localparam logic [1:0] PRV_U = 2'd0;
  localparam logic [1:0] PRV_S = 2'd1;
  localparam logic [1:0] ST_HIT   = 2'b00;
  localparam logic [1:0] ST_FAULT = 2'b01;
  localparam logic [1:0] ST_RETRY = 2'b10;
  localparam logic [2:0] SZ_4K  = 3'b000;
  localparam logic [2:0] SZ_64K = 3'b001;
  localparam logic [2:0] SZ_2M  = 3'b010;
  localparam logic [2:0] SZ_1G  = 3'b011;
  localparam logic [3:0] MODE_SV39 = 4'd8;
  localparam logic [3:0] MODE_BARE = 4'd0;

  // PTE flag bytes: D A G U X W R V.
  localparam logic [7:0] F_PTR  = 8'h01;          // non-leaf
  localparam logic [7:0] F_RX   = 8'h0B;          // V R X, A clear
  localparam logic [7:0] F_RXA  = 8'h4B;          // V R X A
  localparam logic [7:0] F_RXAD = 8'hCB;
  localparam logic [7:0] F_RWX  = 8'h0F;
  localparam logic [7:0] F_RWXA = 8'h4F;
  localparam logic [7:0] F_URX  = 8'h1B;          // G-stage leaves need U
  localparam logic [7:0] F_URXA = 8'h5B;
  localparam logic [7:0] F_URWX   = 8'h1F;
  localparam logic [7:0] F_URWXA  = 8'h5F;
  localparam logic [7:0] F_URWXAD = 8'hDF;

  // ---- bookkeeping -----------------------------------------------------
  int    pass_cnt;
  int    fail_cnt;
  string tname;
  logic [1:0] req_priv;   // itlb_l2t_priv of the next walk (BP-124)

  task automatic chk(input string nm, input logic ok);
    if (ok) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: [%s] %s", tname, nm);
    end
  endtask

  // =================================================================
  // Memory model.
  // =================================================================
  logic [63:0] mem [logic [PA_WIDTH-4:0]];   // 8-byte words

  function automatic logic [63:0] rdw(input logic [PA_WIDTH-1:0] a);
    return mem.exists(a[PA_WIDTH-1:3]) ? mem[a[PA_WIDTH-1:3]] : 64'd0;
  endfunction

  function automatic void wrw(input logic [PA_WIDTH-1:0] a,
                              input logic [63:0] d);
    mem[a[PA_WIDTH-1:3]] = d;
  endfunction

  // Controls.
  int          lat_min;        // response latency, cycles after accept
  int          lat_max;
  int          rdy_pat;        // 0 always ready, else ready 1 in rdy_pat
  int          err_at;         // access number to answer with an error
  int          chg_at;         // CAS number before which to overwrite
  logic [63:0] chg_val;
  // Observation.
  int          n_acc;          // accesses accepted
  int          n_cas;          // CAS accesses accepted
  int          n_mem_err;      // protocol errors seen by the model
  logic        acc_op  [0:255];
  logic [PA_WIDTH-1:0] acc_pa [0:255];
  logic [63:0] acc_swap [0:255];

  logic                o_val;
  int                  o_due;
  logic                o_op;
  logic [PA_WIDTH-1:0] o_pa;
  logic [63:0]         o_cmp;
  logic [63:0]         o_swap;
  logic                o_err;
  int                  cyc;
  int                  rdy_cnt;
  logic                p_val;   // previous cycle presented, not taken
  logic                p_op;
  logic [PA_WIDTH-1:0] p_pa;
  logic [63:0]         p_cmp;
  logic [63:0]         p_swap;

  always @(posedge clk) cyc <= rstn ? cyc + 1 : 0;

  initial begin : mem_model
    logic                acc;
    logic [63:0]         old;
    ptw_mem_req_rdy  = 1'b0;
    mem_ptw_rsp_val  = 1'b0;
    mem_ptw_rsp_data = '0;
    mem_ptw_rsp_err  = 1'b0;
    o_val            = 1'b0;
    p_val            = 1'b0;
    rdy_cnt          = 0;
    forever begin
      @(posedge clk);
      acc = rstn && ptw_mem_req_val && ptw_mem_req_rdy;
      // WM-2: fields held from the cycle val rose until acceptance.
      if (rstn && p_val && !ptw_mem_req_val) begin
        n_mem_err++;
        $display("tb_ptw: request withdrawn before acceptance");
      end
      if (rstn && p_val && ptw_mem_req_val &&
          ((p_op != ptw_mem_req_op) || (p_pa != ptw_mem_req_paddr) ||
           (p_cmp != ptw_mem_req_cmp) || (p_swap != ptw_mem_req_swap))) begin
        n_mem_err++;
        $display("tb_ptw: request fields changed before acceptance");
      end
      p_val  = rstn && ptw_mem_req_val && !ptw_mem_req_rdy;
      p_op   = ptw_mem_req_op;
      p_pa   = ptw_mem_req_paddr;
      p_cmp  = ptw_mem_req_cmp;
      p_swap = ptw_mem_req_swap;
      if (acc) begin
        // WM-1 and WM-3.
        if (ptw_mem_req_paddr[2:0] != 3'b000) begin
          n_mem_err++;
          $display("tb_ptw: unaligned access %09h", ptw_mem_req_paddr);
        end
        if (o_val) begin
          n_mem_err++;
          $display("tb_ptw: second access while one is outstanding");
        end
        o_val  = 1'b1;
        o_due  = cyc + lat_min +
                 ((lat_max > lat_min) ? ($urandom % (lat_max - lat_min + 1))
                                      : 0);
        o_op   = ptw_mem_req_op;
        o_pa   = ptw_mem_req_paddr;
        o_cmp  = ptw_mem_req_cmp;
        o_swap = ptw_mem_req_swap;
        o_err  = (n_acc == err_at);
        if (n_acc < 256) begin
          acc_op[n_acc]   = ptw_mem_req_op;
          acc_pa[n_acc]   = ptw_mem_req_paddr;
          acc_swap[n_acc] = ptw_mem_req_swap;
        end
        n_acc++;
        if (ptw_mem_req_op) begin
          if (n_cas == chg_at) wrw(ptw_mem_req_paddr, chg_val);  // WM-11
          n_cas++;
        end
      end
      #1;
      mem_ptw_rsp_val = 1'b0;
      mem_ptw_rsp_err = 1'b0;
      if (!rstn) begin
        o_val = 1'b0;
      end else if (o_val && (o_due <= cyc)) begin
        o_val           = 1'b0;
        mem_ptw_rsp_val = 1'b1;
        mem_ptw_rsp_err = o_err;
        old             = rdw(o_pa);
        mem_ptw_rsp_data = o_err ? 64'hDEAD_BEEF_DEAD_BEEF : old;
        if (o_op && !o_err && (old == o_cmp)) wrw(o_pa, o_swap);
      end
      // WM-13. Ready from a counter, never from req_val (WM-2).
      rdy_cnt++;
      ptw_mem_req_rdy = rstn &&
                        ((rdy_pat == 0) || ((rdy_cnt % rdy_pat) == 0));
    end
  end

  // =================================================================
  // PTE builders.
  // =================================================================
  function automatic logic [63:0] pte(input logic [43:0] ppn,
                                      input logic [7:0] f);
    return {10'd0, ppn, 2'b00, f};
  endfunction

  function automatic logic [63:0] pte_x(input logic [43:0] ppn,
                                        input logic [7:0] f,
                                        input logic [1:0] pbmt,
                                        input logic n);
    return {n, pbmt, 7'd0, ppn, 2'b00, f};
  endfunction

  // =================================================================
  // BP-149: THE KNOB, and the page-table builder every test uses.
  // =================================================================
  // The MODE values. satp, vsatp and hgatp share them (MMU-20): 8 is
  // Sv39 in satp and vsatp and Sv39x4 in hgatp, and so on.
  localparam logic [3:0] M_BARE = CSR_SATP_MODE_BARE;
  localparam logic [3:0] M_39   = CSR_SATP_MODE_SV39;   // and Sv39x4
  localparam logic [3:0] M_48   = CSR_SATP_MODE_SV48;   // and Sv48x4
  localparam logic [3:0] M_57   = CSR_SATP_MODE_SV57;   // and Sv57x4

  // The levels of a MODE value (MMU-32).
  function automatic int nlev(input logic [3:0] m);
    return (m == M_57) ? 5 : (m == M_48) ? 4 : 3;
  endfunction

  // The GPA width of an hgatp MODE value (MMU-20).
  function automatic int gwid(input logic [3:0] m);
    return (m == M_57) ? 59 : (m == M_48) ? 50 : 41;
  endfunction

  // THE KNOB. km: the satp and vsatp MODE of every test that does not
  // name its modes; hgatp takes km too, the x4 mode of the same depth.
  // kl: its levels. Read once by knob_read, before the first test.
  logic [3:0] km;
  int         kl;

  task automatic knob_read();
    string s;
    if (!$value$plusargs("PT_MODE=%s", s)) s = "sv57";
    if (s == "sv39")      km = M_39;
    else if (s == "sv48") km = M_48;
    else if (s == "sv57") km = M_57;
    else $fatal(1, "tb_ptw: +PT_MODE=%s is not sv39, sv48 or sv57", s);
    kl = nlev(km);
    $display("tb_ptw: PT_MODE %s: satp, vsatp MODE %0d, hgatp its x4, %0d %s",
             s, km, kl, "levels");
  endtask

  pt_build_pkg::pt_image img;
  pt_build_pkg::pt_stage bs;     // the single or VS stage
  pt_build_pkg::pt_stage bg;     // the G-stage

  // The 64-bit address of a request page, the builder's address type.
  function automatic logic [63:0] va64(input logic [VW-1:0] v);
    return 64'({v, 12'h000});
  endfunction

  // The index of request page v at level l of a satp or vsatp structure:
  // nine bits per level (MMU-32). From the rule, not from the builder.
  function automatic int vidx(input logic [VW-1:0] v, input int l);
    return int'((64'(v) >> (9 * l)) & 64'h1FF);
  endfunction

  // The root index of GPA g in an x4 structure of nl levels: eleven bits
  // (MMU-32).
  function automatic int x4ridx(input logic [63:0] g, input int nl);
    return int'((g >> (12 + 9 * (nl - 1))) & 64'h7FF);
  endfunction

  // Drain the builder's writes into the word store.
  function automatic void bsync();
    logic [63:0] a;
    logic [63:0] d;
    logic        got;
    got = img.pop(a, d);
    while (got) begin
      if ((a >> PA_WIDTH) != 64'd0)
        $fatal(1, "tb_ptw: builder word at %016h beyond PA_WIDTH", a);
      wrw(PW'(a), d);
      got = img.pop(a, d);
    end
  endfunction

  // ---- the knob tests' tables -----------------------------------------
  // The request page every knob test walks. Its indices above level 2
  // are zero in every mode, so it is canonical under each.
  localparam logic [VW-1:0] VA = VW'('h012_3456);

  // The regions. At Sv39 the builder places every table where path3,
  // gpath3 and vspath placed it by hand until BP-149: the single-stage
  // root at 0x8100_0000 and its tables from 0x8100_1000; the G-stage
  // root (16 KiB) at 0x8200_0000 and its tables from 0x8200_4000; the
  // VS-stage root at GPA 0x4_0000, its tables from GPA 0x4_1000, each VS
  // table page backed by a supervisor page from 0x8300_0000 in the order
  // the builder asks for it.
  localparam logic [63:0] K_SROOT = 64'h0_8100_0000;
  localparam logic [63:0] K_SPOOL = 64'h0_8100_1000;
  localparam logic [63:0] K_STOP  = 64'h0_8102_0000;
  localparam logic [63:0] K_GROOT = 64'h0_8200_0000;
  localparam logic [63:0] K_GPOOL = 64'h0_8200_4000;
  localparam logic [63:0] K_GTOP  = 64'h0_8202_0000;
  localparam logic [63:0] K_BACK  = 64'h0_8300_0000;
  localparam logic [63:0] K_BTOP  = 64'h0_8302_0000;
  localparam logic [63:0] K_VROOT = 64'h0_0004_0000;     // guest physical
  localparam logic [63:0] K_VPOOL = 64'h0_0004_1000;
  localparam logic [63:0] K_VTOP  = 64'h0_0005_0000;

  // The single or VS stage: pte p at level lvl for VA, the path built in
  // the stage's mode, drained into the store. The PTE's address.
  function automatic logic [PA_WIDTH-1:0] bmap(input int lvl,
                                               input logic [63:0] p);
    logic [63:0] a;
    a = bs.map(va64(VA), lvl, p);
    bsync();
    return PW'(a);
  endfunction

  // The G-stage: pte p at level lvl for the guest page of gpa.
  function automatic logic [PA_WIDTH-1:0] gput(input logic [63:0] gpa,
                                               input int lvl,
                                               input logic [63:0] p);
    logic [63:0] a;
    a = bg.map(gpa & ~64'hFFF, lvl, p);
    bsync();
    return PW'(a);
  endfunction

  // BP-149: the two-stage table helpers are methods of bh_c, so each is
  // compiled once rather than inlined at every call (see cs_c below).
  // They take the stages as arguments and hold no member, so the
  // self-store loop rule (rtl/CLAUDE.md, TOOLS-007) does not arise; the
  // loop in vs_tbl calls methods of another object. The module functions
  // after the class keep the names the tests call.
  class bh_c;
    // The GPA of VS-stage s's table at level l on page v's path, read
    // from the tables the builder wrote (its image).
    function logic [63:0] vs_tbl(input pt_build_pkg::pt_stage s,
                                 input logic [63:0] v, input int l);
      logic [63:0] t;
      logic [63:0] e;
      logic        ok;
      t = s.root;
      for (int k = s.levels - 1; k > l; k--) begin
        e = s.img.get(s.spa_of(t + ((v >> (12 + 9 * k)) & 64'h1FF) * 8,
                               1'b0, ok));
        t = 64'(e[53:10]) << 12;
      end
      return t;
    endfunction

    // The supervisor page that backs that table, through G-stage g.
    function logic [63:0] vs_spa(input pt_build_pkg::pt_stage s,
                                 input pt_build_pkg::pt_stage g,
                                 input logic [63:0] v, input int l);
      logic ok;
      return g.xlate(vs_tbl(s, v, l), ok);
    endfunction

    // The SPA of the G-stage leaf that maps that table.
    function logic [63:0] vs_gleaf(input pt_build_pkg::pt_stage s,
                                   input pt_build_pkg::pt_stage g,
                                   input logic [63:0] v, input int l);
      return g.pte_addr(vs_tbl(s, v, l), 0);
    endfunction

    // The VS path for v, leaf at level 0, the G-stage leaf of the table
    // page at level tl written with flags tf (pt_stage back_f), every
    // other backing leaf with bf. The path above tl is built first, so
    // tf reaches that one page only. Nothing is drained.
    function void path_tf(input pt_build_pkg::pt_stage s,
                          input pt_build_pkg::pt_stage g,
                          input logic [63:0] v, input logic [63:0] leaf,
                          input int tl, input logic [7:0] tf,
                          input logic [7:0] bf);
      if (tl < s.levels - 1) void'(s.path(v, tl + 1));
      g.back_f = tf;
      void'(s.path(v, tl));
      g.back_f = bf;
      void'(s.map(v, 0, leaf));
    endfunction
  endclass : bh_c

  bh_c BH = new;

  // The GPA of the VS-stage table at level l on VA's path.
  function automatic logic [63:0] vs_tbl(input int l);
    return BH.vs_tbl(bs, va64(VA), l);
  endfunction

  // The supervisor page that backs the VS-stage table at level l.
  function automatic logic [63:0] vs_spa(input int l);
    return BH.vs_spa(bs, bg, va64(VA), l);
  endfunction

  // The SPA of the G-stage leaf that maps the VS-stage table at level l.
  function automatic logic [PA_WIDTH-1:0] vs_gleaf(input int l);
    return PW'(BH.vs_gleaf(bs, bg, va64(VA), l));
  endfunction

  // The VS path for VA, leaf at level 0, with the G-stage leaf of the VS
  // table page at level tl given flags tf: the builder writes it with tf
  // (pt_stage back_f), every other backing leaf U R W X A D. The leaf
  // is checked to be there, so the stimulus is what the case says.
  function automatic void vspath_tf(input logic [63:0] leaf, input int tl,
                                    input logic [7:0] tf);
    logic [63:0] sp;
    BH.path_tf(bs, bg, va64(VA), leaf, tl, tf, F_URWXAD);
    bsync();
    sp = vs_spa(tl);
    if (rdw(vs_gleaf(tl)) != pte(44'(sp >> 12), tf))
      $fatal(1, "tb_ptw: vspath_tf: the level-%0d table page is not %02h",
             tl, tf);
  endfunction

  // =================================================================
  // Reset to a known state, and one walk.
  // =================================================================
  // ---- the CSR group (SYS-001) ------------------------------------------
  // Each task changes one field by a read-modify-write through
  // csr_tb_pkg (the CSR-5 rules apply) and drives ptw_csr again.
  //
  // BP-149: the read-modify-write and the pack are methods of cs_c, so
  // each is compiled once. Verilator inlines a module task at every call,
  // and setup and setup2m, inlined at every test, held six of these
  // tasks each: the inlined package calls were 1574 copies of
  // pack_ptw_csr, most of a 141,000-line C++ file that took gcc over 30
  // minutes. Each task is now one call and the assignment of ptw_csr.
  class cs_c;
    function ptw_csr_t pack();
      return csr_tb_pkg::pack_ptw_csr();
    endfunction
    function ptw_csr_t reset();
      csr_tb_pkg::csr_reset();
      return pack();
    endfunction
    function ptw_csr_t satp_mode(input logic [3:0] m);
      satp_t r;
      r = satp_t'(csr_tb_pkg::csr_read(CSR_SATP_ADDR)); r.mode = m;
      csr_tb_pkg::csr_write(CSR_SATP_ADDR, 64'(r));
      return pack();
    endfunction
    function ptw_csr_t satp_ppn(input logic [PPN_WIDTH-1:0] n);
      satp_t r;
      r = satp_t'(csr_tb_pkg::csr_read(CSR_SATP_ADDR)); r.ppn = 44'(n);
      csr_tb_pkg::csr_write(CSR_SATP_ADDR, 64'(r));
      return pack();
    endfunction
    function ptw_csr_t vsatp_mode(input logic [3:0] m);
      vsatp_t r;
      r = vsatp_t'(csr_tb_pkg::csr_read(CSR_VSATP_ADDR)); r.mode = m;
      csr_tb_pkg::csr_write(CSR_VSATP_ADDR, 64'(r));
      return pack();
    endfunction
    function ptw_csr_t vsatp_ppn(input logic [CSR_VSATP_PPN_W-1:0] n);
      vsatp_t r;
      r = vsatp_t'(csr_tb_pkg::csr_read(CSR_VSATP_ADDR)); r.ppn = 44'(n);
      csr_tb_pkg::csr_write(CSR_VSATP_ADDR, 64'(r));
      return pack();
    endfunction
    function ptw_csr_t hgatp_mode(input logic [3:0] m);
      hgatp_t r;
      r = hgatp_t'(csr_tb_pkg::csr_read(CSR_HGATP_ADDR)); r.mode = m;
      csr_tb_pkg::csr_write(CSR_HGATP_ADDR, 64'(r));
      return pack();
    endfunction
    function ptw_csr_t hgatp_ppn(input logic [PPN_WIDTH-1:0] n);
      hgatp_t r;
      r = hgatp_t'(csr_tb_pkg::csr_read(CSR_HGATP_ADDR)); r.ppn = 44'(n);
      csr_tb_pkg::csr_write(CSR_HGATP_ADDR, 64'(r));
      return pack();
    endfunction
    function ptw_csr_t menv_adue(input logic b);
      menvcfg_t r;
      r = menvcfg_t'(csr_tb_pkg::csr_read(CSR_MENVCFG_ADDR)); r.adue = b;
      csr_tb_pkg::csr_write(CSR_MENVCFG_ADDR, 64'(r));
      return pack();
    endfunction
    function ptw_csr_t menv_pbmte(input logic b);
      menvcfg_t r;
      r = menvcfg_t'(csr_tb_pkg::csr_read(CSR_MENVCFG_ADDR)); r.pbmte = b;
      csr_tb_pkg::csr_write(CSR_MENVCFG_ADDR, 64'(r));
      return pack();
    endfunction
    function ptw_csr_t henv_adue(input logic b);
      henvcfg_t r;
      r = henvcfg_t'(csr_tb_pkg::csr_read(CSR_HENVCFG_ADDR)); r.adue = b;
      csr_tb_pkg::csr_write(CSR_HENVCFG_ADDR, 64'(r));
      return pack();
    endfunction
    function ptw_csr_t henv_pbmte(input logic b);
      henvcfg_t r;
      r = henvcfg_t'(csr_tb_pkg::csr_read(CSR_HENVCFG_ADDR)); r.pbmte = b;
      csr_tb_pkg::csr_write(CSR_HENVCFG_ADDR, 64'(r));
      return pack();
    endfunction
    // pmpcfg byte k, by read-modify-write of pmpcfg0 or pmpcfg2.
    function ptw_csr_t pmpcfg(input int k, input logic [7:0] b);
      logic [11:0] ca;
      pmpcfg_t     c;
      ca = (k < 8) ? CSR_PMPCFG0_ADDR : CSR_PMPCFG2_ADDR;
      c  = pmpcfg_t'(csr_tb_pkg::csr_read(ca));
      c.ent[k % 8] = pmpcfg_ent_t'(b);
      csr_tb_pkg::csr_write(ca, 64'(c));
      return pack();
    endfunction
    function ptw_csr_t pmpaddr(input int k, input pmpaddr_imp_t a);
      csr_tb_pkg::csr_write(CSR_PMPADDR0_ADDR + 12'(k), 64'(a));
      return pack();
    endfunction
  endclass : cs_c

  cs_c CS = new;

  task automatic cs_sync();
    ptw_csr = CS.pack();
  endtask
  task automatic cs_satp_mode(input logic [3:0] m);
    ptw_csr = CS.satp_mode(m);
  endtask
  task automatic cs_satp_ppn(input logic [PPN_WIDTH-1:0] n);
    ptw_csr = CS.satp_ppn(n);
  endtask
  task automatic cs_vsatp_mode(input logic [3:0] m);
    ptw_csr = CS.vsatp_mode(m);
  endtask
  task automatic cs_vsatp_ppn(input logic [CSR_VSATP_PPN_W-1:0] n);
    ptw_csr = CS.vsatp_ppn(n);
  endtask
  // hgatp.MODE: MODE_SV39 (8) is Sv39x4 in hgatp.
  task automatic cs_hgatp_mode(input logic [3:0] m);
    ptw_csr = CS.hgatp_mode(m);
  endtask
  task automatic cs_hgatp_ppn(input logic [PPN_WIDTH-1:0] n);
    ptw_csr = CS.hgatp_ppn(n);
  endtask
  task automatic cs_menvcfg_adue(input logic b);
    ptw_csr = CS.menv_adue(b);
  endtask
  task automatic cs_menvcfg_pbmte(input logic b);
    ptw_csr = CS.menv_pbmte(b);
  endtask
  task automatic cs_henvcfg_adue(input logic b);
    ptw_csr = CS.henv_adue(b);
  endtask
  task automatic cs_henvcfg_pbmte(input logic b);
    ptw_csr = CS.henv_pbmte(b);
  endtask
  task automatic cs_pmpcfg(input int k, input logic [7:0] b);
    ptw_csr = CS.pmpcfg(k, b);
  endtask
  task automatic cs_pmpaddr(input int k, input pmpaddr_imp_t a);
    ptw_csr = CS.pmpaddr(k, a);
  endtask

  task automatic setup(input string nm);
    tname = nm;
    rstn  = 1'b0;
    itlb_l2t_req_val = 1'b0;
    itlb_l2t_vpn     = '0;
    itlb_l2t_asid    = '0;
    itlb_l2t_vmid    = '0;
    itlb_l2t_v       = 1'b0;
    itlb_l2t_tag     = '0;
    itlb_l2t_acc     = ACC_X;
    itlb_l2t_priv    = PRV_S;
    req_priv         = PRV_S;
    mem.delete();
    lat_min = 2;
    lat_max = 2;
    rdy_pat = 0;
    err_at  = -1;
    chg_at  = -1;
    chg_val = '0;
    n_acc   = 0;
    n_cas   = 0;
    n_mem_err = 0;
    // CSRs from the csr_pkg reset values (CSR-7): vsatp and hgatp
    // Bare, menvcfg and henvcfg PBMTE 1 and ADUE 0, and PMP entry 0
    // NAPOT over everything, R W X, so S-mode is allowed. Then this
    // testbench's satp: the knob's mode (BP-149; Sv39 until then), root
    // K_SROOT, and the builder's single stage there, with no table yet.
    ptw_csr = CS.reset();
    cs_satp_mode(km);
    cs_satp_ppn(PPN_WIDTH'(K_SROOT >> 12));
    img = new();
    bs  = new("s", img, km, 1'b0, K_SROOT, K_SPOOL, K_STOP);
    bg  = null;
    repeat (3) @(posedge clk);
    #1;
    rstn = 1'b1;
    @(posedge clk);
    #1;
  endtask

  // The response of one walk.
  logic [1:0]             r_st;
  logic [PPN_WIDTH-1:0]   r_ppn;
  logic [2:0]             r_size;
  logic [7:0]             r_perm;
  logic [1:0]             r_pbmt;
  logic [CAUSE_WIDTH-1:0] r_cause;
  logic [FAULT_GPA_WIDTH-1:0] r_gpa;
  logic [1:0]             r_imp;
  logic [1:0]             r_tag;
  int                     n_rsp;

  always @(posedge clk) begin
    if (rstn && l2t_itlb_rsp_val) begin
      n_rsp   <= n_rsp + 1;
      r_st    <= l2t_itlb_status;
      r_ppn   <= l2t_itlb_ppn;
      r_size  <= l2t_itlb_size;
      r_perm  <= l2t_itlb_perm;
      r_pbmt  <= l2t_itlb_pbmt;
      r_cause <= l2t_itlb_cause;
      r_gpa   <= l2t_itlb_gpa;
      r_imp   <= l2t_itlb_gpa_imp;
      r_tag   <= l2t_itlb_tag;
    end
  end

  task automatic walk(input logic v, input logic [VW-1:0] vpn,
                      input logic [1:0] acc);
    int n0;
    int t;
    n0 = n_rsp;
    itlb_l2t_req_val = 1'b1;
    itlb_l2t_v       = v;
    itlb_l2t_vpn     = vpn;
    itlb_l2t_acc     = acc;
    itlb_l2t_priv    = req_priv;
    itlb_l2t_tag     = 2'd1;
    do @(posedge clk); while (!itlb_l2t_req_rdy);
    #1;
    itlb_l2t_req_val = 1'b0;
    t = 0;
    while ((n_rsp == n0) && (t < 2000)) begin
      @(posedge clk);
      #1;
      t++;
    end
    if (n_rsp == n0) begin
      fail_cnt++;
      $display("FAIL: [%s] no response", tname);
    end
    chk("one response per request", n_rsp == n0 + 1);
    chk("the response carries the tag", r_tag == 2'd1);
    chk(tname == "" ? "" : "no memory protocol error", n_mem_err == 0);
  endtask

  task automatic exp_hit(input string nm, input logic [PPN_WIDTH-1:0] ppn,
                         input logic [2:0] sz, input logic [1:0] pbmt);
    chk({nm, ": hit"}, r_st == ST_HIT);
    chk($sformatf("%s: ppn %06h exp %06h", nm, r_ppn, ppn), r_ppn == ppn);
    chk($sformatf("%s: size %0d exp %0d", nm, r_size, sz), r_size == sz);
    chk($sformatf("%s: pbmt %0d exp %0d", nm, r_pbmt, pbmt), r_pbmt == pbmt);
  endtask

  task automatic exp_flt(input string nm, input logic [CAUSE_WIDTH-1:0] c);
    chk($sformatf("%s: fault (st %0d)", nm, r_st), r_st == ST_FAULT);
    chk($sformatf("%s: cause %0d exp %0d", nm, r_cause, c), r_cause == c);
  endtask

  task automatic exp_gpf(input string nm,
                         input logic [FAULT_GPA_WIDTH-1:0] gpa,
                         input logic [1:0] imp);
    exp_flt(nm, CAUSE_WIDTH'(20));
    chk($sformatf("%s: gpa %014h exp %014h", nm, r_gpa, gpa), r_gpa == gpa);
    chk($sformatf("%s: kind %0d exp %0d", nm, r_imp, imp), r_imp == imp);
  endtask

  // =================================================================
  // Single-stage tests.
  // =================================================================
  // BP-149: every table through the builder, in the knob's mode (bmap).
  // A leaf or a bad PTE "at the root" is at level kl - 1; a 2 MiB leaf
  // is at level 1 and a 1 GiB leaf at level 2 in every mode. A bad
  // pointer at the root names K_SPOOL, the page the builder would give
  // the next level (T1 until BP-149); no case reaches it.
  localparam logic [43:0] K_PTR = 44'(K_SPOOL >> 12);

  task automatic t_s_4k();
    logic [PA_WIDTH-1:0] la;
    logic                rd;
    setup("s_4k");
    la = bmap(0, pte(44'h8_2345, F_RXAD));
    walk(1'b0, VW'(VA), ACC_X);
    exp_hit("4k", PNW'('h8_2345), SZ_4K, 2'd0);
    chk("4k: perm is the leaf's low byte", r_perm == F_RXAD);
    chk($sformatf("4k: %0d reads (%0d)", kl, n_acc), n_acc == kl);
    chk("4k: root PTE address",
        acc_pa[0] == PW'(K_SROOT) + PW'(8 * vidx(VA, kl - 1)));
    chk("4k: level 1 PTE address",
        acc_pa[kl - 2] == PW'(bs.pte_addr(va64(VA), 1)));
    chk("4k: level 0 PTE address", acc_pa[kl - 1] == la);
    rd = 1'b1;
    for (int k = 0; k < kl; k++) if (acc_op[k]) rd = 1'b0;
    chk("4k: all reads", rd);
  endtask

  task automatic t_s_super();
    setup("s_2m");
    void'(bmap(1, pte(44'h8_2200, F_RXAD)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_hit("2m", PNW'('h8_2200), SZ_2M, 2'd0);
    chk($sformatf("2m: %0d reads", kl - 1), n_acc == kl - 1);

    setup("s_1g");
    void'(bmap(2, pte(44'h8_0000, F_RXAD)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_hit("1g", PNW'('h8_0000), SZ_1G, 2'd0);

    setup("s_2m_misaligned");
    void'(bmap(1, pte(44'h8_2201, F_RXAD)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("misaligned 2m", 12);

    setup("s_1g_misaligned");
    void'(bmap(2, pte(44'h8_0200, F_RXAD)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("misaligned 1g", 12);
  endtask

  // Svnapot: the one defined encoding and every reserved one.
  task automatic t_s_napot();
    logic [3:0] lo;
    setup("s_napot_64k");
    void'(bmap(0, pte_x(44'h8_2348, F_RXAD, 2'd0, 1'b1)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_hit("napot 64k", PNW'('h8_2348), SZ_64K, 2'd0);
    for (int k = 0; k < 16; k++) begin
      lo = 4'(k);
      if (lo == 4'b1000) continue;
      setup($sformatf("s_napot_rsv_%0h", lo));
      void'(bmap(0, pte_x({40'h8_234, lo}, F_RXAD, 2'd0, 1'b1)));
      walk(1'b0, VW'(VA), ACC_X);
      exp_flt("reserved N encoding", 12);
    end
    setup("s_napot_on_2m");
    void'(bmap(1, pte_x(44'h8_2208, F_RXAD, 2'd0, 1'b1)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("N on a superpage", 12);
    setup("s_napot_nonleaf");
    void'(bmap(kl - 1, pte_x(K_PTR, F_PTR, 2'd0, 1'b1)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("N on a non-leaf", 12);
  endtask

  // Svpbmt.
  task automatic t_s_pbmt();
    for (int p = 1; p < 3; p++) begin
      setup($sformatf("s_pbmt_%0d", p));
      void'(bmap(0, pte_x(44'h8_2345, F_RXAD, 2'(p), 1'b0)));
      walk(1'b0, VW'(VA), ACC_X);
      exp_hit("pbmt", PNW'('h8_2345), SZ_4K, 2'(p));
    end
    setup("s_pbmt_rsv");
    void'(bmap(0, pte_x(44'h8_2345, F_RXAD, 2'd3, 1'b0)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("PBMT 3", 12);
    setup("s_pbmte_clear");
    cs_menvcfg_pbmte(1'b0);
    void'(bmap(0, pte_x(44'h8_2345, F_RXAD, 2'd1, 1'b0)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("PBMT with menvcfg.PBMTE clear", 12);
    setup("s_pbmte_clear_zero");
    cs_menvcfg_pbmte(1'b0);
    void'(bmap(0, pte(44'h8_2345, F_RXAD)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_hit("PBMT 0 with PBMTE clear", PNW'('h8_2345), SZ_4K, 2'd0);
    setup("s_pbmt_nonleaf");
    void'(bmap(kl - 1, pte_x(K_PTR, F_PTR, 2'd1, 1'b0)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("PBMT on a non-leaf", 12);
  endtask

  // The other page faults.
  task automatic t_s_pf();
    setup("s_invalid");
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("V clear at the root", 12);
    setup("s_w_no_r");
    void'(bmap(0, pte(44'h8_2345, 8'hC5)));          // V W, R clear
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("W without R", 12);
    setup("s_rsv_bits");
    void'(bmap(0, pte(44'h8_2345, F_RXAD) | (64'd1 << 54)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("bits 60:54", 12);
    setup("s_nonleaf_l0");
    void'(bmap(0, pte(44'h8_2345, F_PTR)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("non-leaf at level 0", 12);
    setup("s_nonleaf_a");
    void'(bmap(kl - 1, pte(K_PTR, 8'h41)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("A on a non-leaf", 12);
    setup("s_no_x");
    void'(bmap(0, pte(44'h8_2345, 8'hC3)));          // V R A D
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("fetch from a leaf without X", 12);
  endtask

  // Svade and Svadu, single stage, with the D update a store needs.
  // la is the leaf's address, the same in every case (the builder places
  // the path the same way from reset state).
  task automatic t_s_ad();
    logic [PA_WIDTH-1:0] la;
    setup("s_svade");
    la = bmap(0, pte(44'h8_2345, F_RX));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("Svade, A clear", 12);
    chk("Svade: no CAS", n_cas == 0);
    chk("Svade: PTE unchanged", rdw(la) == pte(44'h8_2345, F_RX));

    setup("s_svadu");
    cs_menvcfg_adue(1'b1);
    la = bmap(0, pte(44'h8_2345, F_RX));
    walk(1'b0, VW'(VA), ACC_X);
    exp_hit("Svadu", PNW'('h8_2345), SZ_4K, 2'd0);
    chk("Svadu: one CAS, last",
        (n_cas == 1) && acc_op[kl] && (n_acc == kl + 1));
    chk("Svadu: the CAS is at the leaf", acc_pa[kl] == la);
    chk("Svadu: memory holds A set, D clear",
        rdw(la) == pte(44'h8_2345, F_RXA));
    chk("Svadu: the response perm has A", r_perm == F_RXA);

    setup("s_svadu_store");
    cs_menvcfg_adue(1'b1);
    la = bmap(0, pte(44'h8_2345, F_RWX));
    walk(1'b0, VW'(VA), ACC_W);
    exp_hit("store", PNW'('h8_2345), SZ_4K, 2'd0);
    chk("store: A and D set in memory", rdw(la) == pte(44'h8_2345, 8'hCF));
    setup("s_svadu_store_dset");
    cs_menvcfg_adue(1'b1);
    la = bmap(0, pte(44'h8_2345, F_RWXA));
    walk(1'b0, VW'(VA), ACC_W);
    exp_hit("store, D only", PNW'('h8_2345), SZ_4K, 2'd0);
    chk("store: D set", rdw(la) == pte(44'h8_2345, 8'hCF));
    setup("s_svade_store");
    void'(bmap(0, pte(44'h8_2345, F_RWXA)));
    walk(1'b0, VW'(VA), ACC_W);
    exp_flt("Svade store, D clear", 15);         // MMU-24c
    setup("s_store_no_w");
    cs_menvcfg_adue(1'b1);
    void'(bmap(0, pte(44'h8_2345, F_RX)));
    walk(1'b0, VW'(VA), ACC_W);
    exp_flt("store to a page without W", 15);    // MMU-24c
    chk("store without W: no CAS", n_cas == 0);

    // WM-11: memory changes the PTE before the CAS; the walk restarts
    // and reads the new PTE.
    setup("s_cas_mismatch");
    cs_menvcfg_adue(1'b1);
    la = bmap(0, pte(44'h8_2345, F_RX));
    chg_at  = 0;
    chg_val = pte(44'h8_6789, F_RXAD);
    walk(1'b0, VW'(VA), ACC_X);
    exp_hit("restart after mismatch", PNW'('h8_6789), SZ_4K, 2'd0);
    chk($sformatf("mismatch: %0d reads, CAS, %0d reads (%0d)", kl, kl,
                  n_acc), (n_acc == 2 * kl + 1) && (n_cas == 1));
    chk("mismatch: memory keeps the other agent's value",
        rdw(la) == pte(44'h8_6789, F_RXAD));
  endtask

  // Access faults, cause 1.
  task automatic t_s_access();
    logic [PA_WIDTH-1:0] la;
    logic [PA_WIDTH-1:0] t0;
    // PMP: entry 0 covers the level-0 table page t0 with no read (NAPOT
    // 4 KiB), entry 1 everything else.
    setup("s_pmp_read");
    la = bmap(0, pte(44'h8_2345, F_RXAD));
    t0 = la & ~PW'('hFFF);
    cs_pmpcfg(0, 8'h18);                      // NAPOT, no R W X
    cs_pmpaddr(0, PMW'((t0 >> 2) | PW'('h1FF)));
    cs_pmpcfg(1, 8'h1F);
    cs_pmpaddr(1, '1);
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("PMP on a PTE read", 1);
    chk($sformatf("PMP read: the denied read is never presented (%0d)",
                  n_acc), n_acc == kl - 1);

    setup("s_pmp_cas");
    cs_menvcfg_adue(1'b1);
    la = bmap(0, pte(44'h8_2345, F_RX));
    t0 = la & ~PW'('hFFF);
    cs_pmpcfg(0, 8'h19);                      // NAPOT, R only
    cs_pmpaddr(0, PMW'((t0 >> 2) | PW'('h1FF)));
    cs_pmpcfg(1, 8'h1F);
    cs_pmpaddr(1, '1);
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("PMP on the Svadu write", 1);
    chk("PMP write: no CAS presented", (n_cas == 0) && (n_acc == kl));

    setup("s_pt_not_cc");
    cs_satp_ppn(PPN_WIDTH'(PW'('h0_4000_0000) >> 12));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("page table outside cacheable coherent memory", 1);
    chk("not cacheable: nothing presented", n_acc == 0);

    // BP-147: the PPN bit outside the physical space is PPN_WIDTH, the
    // first bit a PPN cannot have (it was bit 24, PPN_WIDTH only at
    // PA_WIDTH 36). The leaf case sets bit 43, outside at any PA_WIDTH
    // up to 55.
    setup("s_ppn_wide_nonleaf");
    void'(bmap(kl - 1, pte((44'd1 << PNW) | K_PTR, F_PTR)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("non-leaf PPN bit PPN_WIDTH", 1);
    chk("wide non-leaf: one read", n_acc == 1);

    setup("s_ppn_wide_leaf");
    void'(bmap(0, pte(44'h800_0000_0123, F_RXAD)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("leaf PPN bit 43", 1);

    setup("s_err_read");
    void'(bmap(0, pte(44'h8_2345, F_RXAD)));
    err_at = 1;
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("memory error on a read", 1);
    chk("read error: the walk stops", n_acc == 2);

    // The CAS follows the kl reads: access kl.
    setup("s_err_cas");
    cs_menvcfg_adue(1'b1);
    la = bmap(0, pte(44'h8_2345, F_RX));
    err_at = kl;
    walk(1'b0, VW'(VA), ACC_X);
    exp_flt("memory error on the CAS", 1);
    chk("CAS error: nothing stored", rdw(la) == pte(44'h8_2345, F_RX));
  endtask

  // WM-13 and IL-6.
  task automatic t_s_timing();
    setup("s_slow");
    lat_min = 1;
    lat_max = 9;
    rdy_pat = 3;
    void'(bmap(0, pte(44'h8_2345, F_RXAD)));
    walk(1'b0, VW'(VA), ACC_X);
    exp_hit("slow memory", PNW'('h8_2345), SZ_4K, 2'd0);

    // A second request while a walk is in progress is answered retry.
    setup("s_retry");
    lat_min = 6;
    lat_max = 6;
    void'(bmap(0, pte(44'h8_2345, F_RXAD)));
    begin
      int n0;
      int nr;
      logic got_rty;
      logic got_hit;
      n0 = n_rsp;
      got_rty = 1'b0;
      got_hit = 1'b0;
      itlb_l2t_req_val = 1'b1;
      itlb_l2t_v       = 1'b0;
      itlb_l2t_vpn     = VW'(VA);
      itlb_l2t_acc     = ACC_X;
      itlb_l2t_tag     = 2'd0;
      @(posedge clk);
      #1;
      itlb_l2t_tag     = 2'd2;                       // the second one
      @(posedge clk);
      #1;
      itlb_l2t_req_val = 1'b0;
      for (int c = 0; c < 200; c++) begin
        @(posedge clk);
        if (l2t_itlb_rsp_val && (l2t_itlb_status == ST_RETRY) &&
            (l2t_itlb_tag == 2'd2)) got_rty = 1'b1;
        if (l2t_itlb_rsp_val && (l2t_itlb_status == ST_HIT) &&
            (l2t_itlb_tag == 2'd0)) got_hit = 1'b1;
        #1;
      end
      nr = n_rsp - n0;
      chk("retry: the second request is answered retry", got_rty);
      chk("retry: the first completes", got_hit);
      chk($sformatf("retry: two responses (%0d)", nr), nr == 2);
      chk("retry: one walk's accesses", n_acc == kl);
    end
  endtask

  // =================================================================
  // Two-stage tests. BP-149: the VS-stage in the knob's mode, its tables
  // in guest physical memory from K_VROOT, each table page backed by the
  // G-stage (the x4 mode of the same depth) with a level-0 leaf, U R W
  // X A D (pt_build_pkg back), as setup2 mapped GP_VT2, GP_VT1 and
  // GP_VT0 until BP-149. The code page GP_CODE is mapped by each case
  // that reaches it (gcode), with the leaf the case gives.
  // =================================================================
  localparam logic [43:0]          GP_CODE = 44'h123;   // guest page
  localparam logic [PPN_WIDTH-1:0] SP_CODE = PNW'('h8_4567);

  // A V=1 walk, vsatp mode vm (root K_VROOT, guest physical) over hgatp
  // mode gm (root K_GROOT). No table is written.
  task automatic setup2m(input string nm, input logic [3:0] vm,
                         input logic [3:0] gm);
    setup(nm);
    cs_satp_mode(MODE_BARE);
    bg = new("g", img, gm, 1'b1, K_GROOT, K_GPOOL, K_GTOP);
    bg.set_back(K_BACK, K_BTOP, F_URWXAD);
    bs = new("vs", img, vm, 1'b0, K_VROOT, K_VPOOL, K_VTOP);
    bs.set_gstage(bg);
    cs_vsatp_mode(vm);
    cs_vsatp_ppn(CSR_VSATP_PPN_W'(K_VROOT >> 12));
    cs_hgatp_mode(gm);
    cs_hgatp_ppn(PPN_WIDTH'(K_GROOT >> 12));
  endtask

  // Under the knob: vsatp km, hgatp its x4 mode.
  task automatic setup2(input string nm);
    setup2m(nm, km, km);
  endtask

  // The VS path for VA, leaf at level 0. Its address.
  function automatic logic [PA_WIDTH-1:0] vspath(input logic [63:0] leaf);
    return bmap(0, leaf);
  endfunction

  // The G-stage leaf of the code page; its address.
  function automatic logic [PA_WIDTH-1:0] gcode(input logic [63:0] leaf);
    return gput(64'(GP_CODE) << 12, 0, leaf);
  endfunction

  // The code page mapped as setup2 mapped it until BP-149.
  function automatic void gcode_ok();
    void'(gcode(pte(44'(SP_CODE), F_URWXAD)));
  endfunction

  task automatic t_h_basic();
    setup2("h_4k_4k");
    void'(vspath(pte(GP_CODE, F_RXAD)));
    gcode_ok();
    walk(1'b1, VW'(VA), ACC_X);
    exp_hit("nested 4k/4k", SP_CODE, SZ_4K, 2'd0);
    chk("nested: perm is the VS leaf's", r_perm == F_RXAD);
    // MMU-21: a G walk of kl reads before each of the kl VS reads, and
    // one for the final GPA.
    chk($sformatf("nested: %0d G walks of %0d plus %0d VS reads (%0d)",
                  kl + 1, kl, kl, n_acc), n_acc == (kl + 1) * (kl + 1) - 1);
    chk("nested: first access is the G root for the VS root's GPA",
        acc_pa[0] == PW'(K_GROOT) + PW'(8 * x4ridx(K_VROOT, kl)));
    chk("nested: the access after the first G walk is the VS root PTE",
        acc_pa[kl] == PW'(bs.pte_addr(va64(VA), kl - 1)));

    // G-stage only: vsatp Bare, the request page is the GPA.
    setup2("h_g_only");
    cs_vsatp_mode(MODE_BARE);
    gcode_ok();
    walk(1'b1, VW'(GP_CODE), ACC_X);
    exp_hit("G only", SP_CODE, SZ_4K, 2'd0);
    chk("G only: perm is the G leaf's without G", r_perm == (F_URWXAD & 8'hDF));
    chk($sformatf("G only: %0d reads", kl), n_acc == kl);

    // VS-stage only: hgatp Bare, GPA = SPA. The VS tables in supervisor
    // memory from K_BACK (SP_VT2 until BP-149).
    setup2("h_vs_only");
    cs_hgatp_mode(MODE_BARE);
    bs = new("vs", img, km, 1'b0, K_BACK, K_BACK + 64'h1000, K_BTOP);
    cs_vsatp_ppn(CSR_VSATP_PPN_W'(K_BACK >> 12));
    void'(bmap(0, pte(44'(SP_CODE), F_RXAD)));
    walk(1'b1, VW'(VA), ACC_X);
    exp_hit("VS only", SP_CODE, SZ_4K, 2'd0);
    chk($sformatf("VS only: %0d reads", kl), n_acc == kl);

    // The G-only regime with a GPA using bits 40:39 (FE-19).
    setup2("h_g_only_high");
    cs_vsatp_mode(MODE_BARE);
    void'(gput(64'h1FF_0123 << 12, 0, pte(44'h8_4444, F_URXA)));
    walk(1'b1, VW'('h1FF_0123), ACC_X);
    exp_hit("G only, GPA bit 40", PNW'('h8_4444), SZ_4K, 2'd0);
  endtask

  // MMU-27, sizes, and NAPOT at each stage.
  task automatic t_h_size();
    // VS 2 MiB, G 4 KiB -> 4 KiB.
    setup2("h_vs2m_g4k");
    // VS 2 MiB leaf at guest page 0x200 aligned: GPA page = 0x200 + the
    // level-0 index.
    void'(bmap(1, pte(44'h200, F_RXAD)));
    void'(gput((64'h200 | 64'(vidx(VA, 0))) << 12, 0,
               pte(44'h8_5555, F_URXA)));
    walk(1'b1, VW'(VA), ACC_X);
    exp_hit("VS 2M over G 4K", PNW'('h8_5555), SZ_4K, 2'd0);

    // VS 4 KiB, G 1 GiB -> 4 KiB; the SPA is the G superpage plus GPA
    // bits. The 1 GiB G leaf is at level 2 (the root under Sv39x4).
    setup2("h_vs4k_g1g");
    void'(vspath(pte(44'h4_0123, F_RXAD)));          // GPA page 0x40123
    void'(gput(64'h4_0123 << 12, 2, pte(44'h8_0000 | 44'h4_0000, F_URXA)));
    walk(1'b1, VW'(VA), ACC_X);
    exp_hit("VS 4K over G 1G", PNW'('hC_0123), SZ_4K, 2'd0);

    // VS 1 GiB, G 2 MiB -> 2 MiB.
    setup2("h_vs1g_g2m");
    void'(bmap(2, pte(44'h8_0000, F_RXAD)));         // GPA 2 GiB
    begin
      logic [63:0] gp;
      gp = 64'h8_0000 | (64'(VA) & 64'h3_FFFF);
      void'(gput(gp << 12, 1, pte(44'h9_0000, F_URXA)));
      walk(1'b1, VW'(VA), ACC_X);
      exp_hit("VS 1G over G 2M", PNW'('h9_0000) | PNW'(vidx(VA, 0)), SZ_2M,
              2'd0);
    end

    // NAPOT at the G-stage, VS 2 MiB above it -> 64 KiB.
    setup2("h_g_napot");
    void'(bmap(1, pte(44'h200, F_RXAD)));
    begin
      logic [63:0] gp;
      gp = 64'h200 | 64'(vidx(VA, 0));
      void'(gput(gp << 12, 0, pte_x(44'h8_6608, F_URXA, 2'd0, 1'b1)));
      walk(1'b1, VW'(VA), ACC_X);
      exp_hit("G NAPOT under VS 2M", PNW'('h8_6600) | PNW'(gp[3:0]), SZ_64K,
              2'd0);
    end

    // NAPOT at the VS-stage, G 4 KiB -> 4 KiB, PA page from GPA[15:12].
    setup2("h_vs_napot");
    void'(vspath(pte_x(44'h0128, F_RXAD, 2'd0, 1'b1)));
    begin
      logic [63:0] gp;
      gp = 64'h0120 | (64'(VA) & 64'hF);
      void'(gput(gp << 12, 0, pte(44'h8_7777, F_URXA)));
      walk(1'b1, VW'(VA), ACC_X);
      exp_hit("VS NAPOT over G 4K", PNW'('h8_7777), SZ_4K, 2'd0);
    end

    // NAPOT at both stages -> 64 KiB.
    setup2("h_both_napot");
    void'(vspath(pte_x(44'h0128, F_RXAD, 2'd0, 1'b1)));
    begin
      logic [63:0] gp;
      gp = 64'h0120 | (64'(VA) & 64'hF);
      void'(gput(gp << 12, 0, pte_x(44'h8_7708, F_URXA, 2'd0, 1'b1)));
      walk(1'b1, VW'(VA), ACC_X);
      exp_hit("NAPOT both", PNW'('h8_7700) | PNW'(64'(VA) & 64'hF), SZ_64K,
              2'd0);
    end

    // Reserved N at the G-stage.
    setup2("h_g_napot_rsv");
    void'(vspath(pte(GP_CODE, F_RXAD)));
    void'(gcode(pte_x(44'h8_4564, F_URXA, 2'd0, 1'b1)));
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("reserved N at the G-stage", FW'({GP_CODE, 12'h000}), 2'b00);
  endtask

  // Guest-page faults of each kind, PBMT, U and the GPA width.
  task automatic t_h_faults();
    logic [PA_WIDTH-1:0] vl;
    setup2("h_gpf_fetch");
    void'(vspath(pte(GP_CODE, F_RXAD)));
    void'(gcode(64'd0));
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("unmapped final GPA", FW'({GP_CODE, 12'h000}), 2'b00);

    // THE ONE DIRECT WRITE (BP-149): the G-stage leaf of the VS level-1
    // table page is zeroed at the address bg.pte_addr gives. The builder
    // writes that leaf itself when it backs the page, and cannot build
    // the path through the page without it.
    setup2("h_gpf_read");
    void'(vspath(pte(GP_CODE, F_RXAD)));
    gcode_ok();
    wrw(vs_gleaf(1), 64'd0);                          // VS level-1 table
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("unmapped VS table page",
            FW'(vs_tbl(1)) + FW'(8 * vidx(VA, 1)), 2'b01);

    setup2("h_gpf_write");
    cs_henvcfg_adue(1'b1);
    cs_menvcfg_adue(1'b1);
    vspath_tf(pte(GP_CODE, F_RX), 0, F_URXA);        // VS A clear; no W
    gcode_ok();
    vl = PW'(bs.pte_addr(va64(VA), 0));
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("G leaf without W for the VS update",
            FW'(vs_tbl(0)) + FW'(8 * vidx(VA, 0)), 2'b10);
    chk("no W: VS PTE unchanged", rdw(vl) == pte(GP_CODE, F_RX));

    setup2("h_g_no_u");
    void'(vspath(pte(GP_CODE, F_RXAD)));
    void'(gcode(pte(44'(SP_CODE), F_RXAD)));          // U clear
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("G leaf with U clear", FW'({GP_CODE, 12'h000}), 2'b00);

    setup2("h_g_no_x");
    void'(vspath(pte(GP_CODE, F_RXAD)));
    void'(gcode(pte(44'(SP_CODE), 8'hD3)));           // U R A D
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("G leaf without X for the fetch", FW'({GP_CODE, 12'h000}),
            2'b00);

    // MMU-23 (BP-124): a GPA above bit 40 is returned whole. MMU-30's
    // zero is withdrawn. Kind 00: the leaf's page, bits 11:0 zero.
    // BP-149: these five cases are BP-145's case e of the Sv39x4 GPA
    // bound (see t_wide), so hgatp names Sv39x4 in every run; under
    // Sv57x4 no such GPA is out of bounds. vsatp follows the knob.
    setup2m("h_gpa_wide_leaf", km, M_39);
    void'(vspath(pte(44'h2000_0123, F_RXAD)));       // GPA bit 41
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("VS leaf GPA above bit 40", FW'({44'h2000_0123, 12'h000}), 2'b00);

    setup2m("h_gpa_bit55_leaf", km, M_39);
    void'(vspath(pte(44'h800_0000_0123, F_RXAD)));   // GPA bit 55
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("VS leaf GPA bit 55", FW'({44'h800_0000_0123, 12'h000}), 2'b00);
    chk("bit 55 leaf: the GPA's bit 55 is set", r_gpa[55]);

    // Kind 01: the GPA of the VS PTE the next level would read. The bad
    // pointer is at the VS root, level kl - 1; the next level's index is
    // that of level kl - 2.
    setup2m("h_gpa_wide_nonleaf", km, M_39);
    void'(bmap(kl - 1, pte(44'h2000_0041, F_PTR)));
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("VS non-leaf GPA above bit 40",
            FW'({44'h2000_0041, 12'h000}) + FW'(8 * vidx(VA, kl - 2)), 2'b01);

    setup2m("h_gpa_bit55_nonleaf", km, M_39);
    void'(bmap(kl - 1, pte(44'h800_0000_0041, F_PTR)));
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("VS non-leaf GPA bit 55",
            FW'({44'h800_0000_0041, 12'h000}) + FW'(8 * vidx(VA, kl - 2)),
            2'b01);
    chk("bit 55 non-leaf: the GPA's bit 55 is set", r_gpa[55]);

    // The same at level 1: the GPA indexes with the level-0 index.
    setup2m("h_gpa_bit55_nonleaf_l1", km, M_39);
    void'(bmap(1, pte(44'h800_0000_0042, F_PTR)));
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("VS level-1 non-leaf GPA bit 55",
            FW'({44'h800_0000_0042, 12'h000}) + FW'(8 * vidx(VA, 0)), 2'b01);

    setup2("h_g_ppn_wide");
    void'(vspath(pte(GP_CODE, F_RXAD)));
    // BP-147: PPN bit PPN_WIDTH, as s_ppn_wide_nonleaf (it was bit 24).
    void'(gcode(pte((44'd1 << PNW) | 44'(SP_CODE), F_URXA)));
    walk(1'b1, VW'(VA), ACC_X);
    exp_flt("G leaf PPN bit PPN_WIDTH", 1);

    setup2("h_vs_pbmte");
    cs_henvcfg_pbmte(1'b0);                    // menvcfg's stays set
    void'(vspath(pte_x(GP_CODE, F_RXAD, 2'd1, 1'b0)));
    gcode_ok();
    walk(1'b1, VW'(VA), ACC_X);
    exp_flt("VS PBMT with henvcfg.PBMTE clear", 12);

    // menvcfg.PBMTE clear. henvcfg.PBMTE stays written 1 but reads 0
    // while menvcfg.PBMTE is 0 (csr_decisions.md CSR-5, SYS-002), so
    // the walker sees both clear; until SYS-002 it was given henvcfg's
    // 1. The VS leaf's PBMT is 0, so the result is the same either way.
    setup2("h_g_pbmte");
    cs_menvcfg_pbmte(1'b0);
    chk("g pbmte: henvcfg.PBMTE reads 0", ptw_csr.henvcfg_pbmte == 1'b0);
    void'(vspath(pte(GP_CODE, F_RXAD)));
    void'(gcode(pte_x(44'(SP_CODE), F_URXA, 2'd2, 1'b0)));
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("G PBMT with menvcfg.PBMTE clear", FW'({GP_CODE, 12'h000}),
            2'b00);

    setup2("h_g_pbmt_rsv");
    void'(vspath(pte(GP_CODE, F_RXAD)));
    void'(gcode(pte_x(44'(SP_CODE), F_URXA, 2'd3, 1'b0)));
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("G PBMT 3", FW'({GP_CODE, 12'h000}), 2'b00);

    setup2("h_pbmt_max");
    void'(vspath(pte_x(GP_CODE, F_RXAD, 2'd1, 1'b0)));       // NC
    void'(gcode(pte_x(44'(SP_CODE), F_URXA, 2'd2, 1'b0)));
    walk(1'b1, VW'(VA), ACC_X);
    exp_hit("VS NC over G IO", SP_CODE, SZ_4K, 2'd2);
    setup2("h_pbmt_max2");
    void'(vspath(pte_x(GP_CODE, F_RXAD, 2'd2, 1'b0)));       // IO
    void'(gcode(pte_x(44'(SP_CODE), F_URXA, 2'd1, 1'b0)));
    walk(1'b1, VW'(VA), ACC_X);
    exp_hit("VS IO over G NC", SP_CODE, SZ_4K, 2'd2);

    // The second read of the final G walk, which follows the kl VS reads
    // and their kl G walks: access kl * (kl + 1) + 1 (13 at Sv39).
    setup2("h_err_g");
    void'(vspath(pte(GP_CODE, F_RXAD)));
    gcode_ok();
    err_at = kl * (kl + 1) + 1;
    walk(1'b1, VW'(VA), ACC_X);
    exp_flt("memory error in a G-stage walk", 1);
  endtask

  // Svade and Svadu at each stage, chosen separately.
  // vl: the VS leaf's SPA. gl: the G leaf of the VS level-0 table page,
  // and sp that page's SPA. The same in every case (the builder places
  // the path the same way from reset state), formed after each build.
  task automatic t_h_ad();
    logic [PA_WIDTH-1:0] vl;
    logic [PA_WIDTH-1:0] gl;
    logic [63:0]         sp;

    // henvcfg.ADUE set, menvcfg.ADUE set: the VS update writes through
    // the G-stage and sets the G leaf's D.
    setup2("h_vs_upd_sets_g_d");
    cs_henvcfg_adue(1'b1);
    cs_menvcfg_adue(1'b1);
    vspath_tf(pte(GP_CODE, F_RX), 0, F_URWXA);       // G leaf D clear
    gcode_ok();
    vl = PW'(bs.pte_addr(va64(VA), 0));
    gl = vs_gleaf(0);
    sp = vs_spa(0);
    walk(1'b1, VW'(VA), ACC_X);
    exp_hit("VS update through the G-stage", SP_CODE, SZ_4K, 2'd0);
    chk("the VS leaf has A", rdw(vl) == pte(GP_CODE, F_RXA));
    chk("the G leaf of the VS table page has D",
        rdw(gl) == pte(44'(sp >> 12), F_URWXAD));
    chk("two CAS", n_cas == 2);

    // henvcfg.ADUE written 1, menvcfg.ADUE clear. SYS-001: henvcfg.ADUE
    // reads 0 while menvcfg.ADUE is 0 (csr_decisions.md CSR-5, the
    // privileged rule), so the walker sees both stages Svade and the VS
    // leaf's clear A is a page fault. Until SYS-001 the walker was given
    // henvcfg.ADUE 1 here, a VS-stage Svadu over a G-stage Svade that no
    // CSR write can produce, and the case expected the G-stage D fault
    // of the VS update (cause 20, kind 10).
    setup2("h_h1_m0");
    cs_henvcfg_adue(1'b1);
    cs_menvcfg_adue(1'b0);
    chk("h1 m0: henvcfg.ADUE reads 0", ptw_csr.henvcfg_adue == 1'b0);
    vspath_tf(pte(GP_CODE, F_RX), 0, F_URWXA);
    gcode_ok();
    walk(1'b1, VW'(VA), ACC_X);
    exp_flt("Svade at VS, henvcfg.ADUE read 0", 12);
    chk("h1 m0: no CAS", n_cas == 0);

    // henvcfg.ADUE clear, menvcfg.ADUE set: VS Svade faults on A, while
    // the G-stage updates its own A on the way. The G leaf of the VS root
    // page (level kl - 1) has A clear.
    setup2("h_h0_m1");
    cs_henvcfg_adue(1'b0);
    cs_menvcfg_adue(1'b1);
    vspath_tf(pte(GP_CODE, F_RX), kl - 1, F_URWX);   // A clear
    gcode_ok();
    gl = vs_gleaf(kl - 1);
    sp = vs_spa(kl - 1);
    walk(1'b1, VW'(VA), ACC_X);
    exp_flt("Svade at VS, A clear", 12);
    chk("h0 m1: the G leaf got A", rdw(gl) == pte(44'(sp >> 12), F_URWXA));

    // Svade at the G-stage for the fetch's own GPA.
    setup2("h_g_svade");
    void'(vspath(pte(GP_CODE, F_RXAD)));
    void'(gcode(pte(44'(SP_CODE), F_URX)));
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("Svade at G, fetch", FW'({GP_CODE, 12'h000}), 2'b00);

    // Svadu at the G-stage for the fetch's own GPA, with a mismatch.
    setup2("h_g_svadu_mismatch");
    cs_menvcfg_adue(1'b1);
    void'(vspath(pte(GP_CODE, F_RXAD)));
    void'(gcode(pte(44'(SP_CODE), F_URX)));
    chg_at  = 0;
    chg_val = pte(44'h8_9999, F_URXA);
    walk(1'b1, VW'(VA), ACC_X);
    exp_hit("G restart after mismatch", PNW'('h8_9999), SZ_4K, 2'd0);
    chk("G mismatch: one CAS", n_cas == 1);

    // VS mismatch: the whole translation restarts. The VS walk, kl reads
    // each after a G walk of kl; the VS update, a G walk and the CAS;
    // then the restart, the VS walk again and the final G walk (MMU-21,
    // MMU-8a): (2 kl + 1)(kl + 1) + kl accesses, 31 at Sv39.
    setup2("h_vs_mismatch");
    cs_henvcfg_adue(1'b1);
    cs_menvcfg_adue(1'b1);
    void'(vspath(pte(GP_CODE, F_RX)));
    gcode_ok();
    chg_at  = 0;
    chg_val = pte(GP_CODE, F_RXAD);
    walk(1'b1, VW'(VA), ACC_X);
    exp_hit("VS restart after mismatch", SP_CODE, SZ_4K, 2'd0);
    chk($sformatf("VS mismatch: the restart walks again (%0d accesses)",
                  (2 * kl + 1) * (kl + 1) + kl),
        n_acc == (2 * kl + 1) * (kl + 1) + kl);
  endtask

  // =================================================================
  // MMU-8c (BP-124). Every check the algorithm makes on a leaf comes
  // before its A/D update. Each case below enables Svadu at the stage
  // of the leaf under test, gives that leaf A clear, makes exactly one
  // check fail, and checks the fault, that NO CAS was issued and that
  // the leaf in memory is unchanged.
  // =================================================================
  localparam logic [7:0] F_URX_NA = 8'h1B;          // U R X, A clear

  // A single-stage leaf at level lvl (0, or 1 for a 2 MiB leaf).
  task automatic lc_s(input string nm, input logic [63:0] leaf,
                      input logic [1:0] lvl, input logic [1:0] acc,
                      input logic [1:0] priv, input logic pbmte,
                      input int cause);
    logic [PA_WIDTH-1:0] la;
    setup(nm);
    cs_menvcfg_adue(1'b1);
    cs_menvcfg_pbmte(pbmte);
    req_priv = priv;
    la = bmap(int'(lvl), leaf);
    walk(1'b0, VW'(VA), acc);
    exp_flt(nm, CAUSE_WIDTH'(cause));
    chk({nm, ": no CAS"}, n_cas == 0);
    chk({nm, ": leaf unchanged"}, rdw(la) == leaf);
  endtask

  // A VS-stage leaf (nested, the knob's modes), at level 0 or 1. The
  // G-stage leaves of the VS table pages have A and D, so the only
  // update a walk could make is the VS leaf's.
  task automatic lc_vs(input string nm, input logic [63:0] leaf,
                       input logic [1:0] lvl, input logic [1:0] acc,
                       input logic [1:0] priv, input logic pbmte,
                       input int cause);
    logic [PA_WIDTH-1:0] la;
    setup2(nm);
    cs_henvcfg_adue(1'b1);
    cs_menvcfg_adue(1'b1);
    cs_henvcfg_pbmte(pbmte);
    req_priv = priv;
    la = bmap(int'(lvl), leaf);
    gcode_ok();
    walk(1'b1, VW'(VA), acc);
    exp_flt(nm, CAUSE_WIDTH'(cause));
    chk({nm, ": no CAS"}, n_cas == 0);
    chk({nm, ": leaf unchanged"}, rdw(la) == leaf);
  endtask

  // A G-stage leaf for the fetch's own GPA. The VS leaf has A and D,
  // so it needs no update; menvcfg.ADUE is set for the G-stage. lvl 1
  // maps guest page 0x200 (a 2 MiB G leaf at level 1); lvl 0 is the G
  // leaf of GP_CODE.
  task automatic lc_g(input string nm, input logic [63:0] leaf,
                      input logic [1:0] lvl, input logic pbmte);
    logic [PA_WIDTH-1:0] la;
    logic [43:0]         gp;
    setup2(nm);
    cs_menvcfg_adue(1'b1);
    cs_menvcfg_pbmte(pbmte);
    gp = (lvl == 2'd0) ? GP_CODE : 44'h200;
    void'(vspath(pte(gp, F_RXAD)));
    la = gput(64'(gp) << 12, int'(lvl), leaf);
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf(nm, FW'({gp, 12'h000}), 2'b00);
    chk({nm, ": no CAS"}, n_cas == 0);
    chk({nm, ": leaf unchanged"}, rdw(la) == leaf);
  endtask

  // MMU-24c (BP-124): the access fault and the guest-page fault take
  // the cause of the original access type, as the page fault does.
  // BP-145, Problem 2: the cases VA_WIDTH and GPA_WIDTH 59 make
  // reachable. The walker walks Sv39x4 only, so a GPA with a bit set at
  // or above SV39X4_GPA_WIDTH (41) is a guest-page fault, cause 20,
  // found before any G-stage PTE is read (MMU-20, MMU-24b, MMU-28). At
  // GPA_WIDTH 41 there is no such address, and the cases are skipped.
  //   c  G-stage only (vsatp Bare, hgatp Sv39x4): the fetch address is
  //      the GPA. Kind 00, the GPA the whole fetch page (MMU-23). Its
  //      low 41 bits are GP_CODE, a mapped page, so a walker that
  //      ignored bits 58:41 would hit.
  //   d  vsatp Sv39 over Sv39x4, vsatp.PPN naming a root at or above
  //      2^41. Kind 01, the GPA the root PTE's (MMU-24b, MMU-29). Its
  //      low 29 PPN bits are K_VROOT's (GP_VT2 until BP-149), the mapped
  //      root, so a walker that ignored the high bits would walk.
  //   e  a VS-stage PTE whose PPN forms a GPA at or above 2^41 is
  //      h_gpa_wide_leaf and h_gpa_wide_nonleaf (GPA bit 41) and the
  //      bit-55 cases in t_h_faults, unchanged.
  // BP-149: a test of the Sv39x4 limit, which no GPA reaches under
  // Sv57x4, so hgatp names Sv39x4 in every run (A MODE'S LIMIT IS A
  // NAMED MODE). vsatp, not its subject, follows the knob, and the root
  // PTE's index in d is that of its root level.
  task automatic t_wide();
    logic [VW-1:0]              vpn;
    logic [CSR_VSATP_PPN_W-1:0] root;
    int                         hi [0:1];
    if (GPA_WIDTH <= SV39X4_GPA_WIDTH) begin
      $display("SKIP t_wide: GPA_WIDTH %0d leaves no GPA above Sv39x4",
               GPA_WIDTH);
      return;
    end
    // c: the lowest and the highest address bit above the Sv39x4 width.
    hi[0] = SV39X4_GPA_WIDTH;
    hi[1] = VA_WIDTH - 1;
    for (int k = 0; k < 2; k++) begin
      setup2m($sformatf("w_c_gonly_bit%0d", hi[k]), km, M_39);
      cs_vsatp_mode(MODE_BARE);
      gcode_ok();
      vpn = VW'(GP_CODE) | (VW'(1) << (hi[k] - 12));
      walk(1'b1, vpn, ACC_X);
      exp_gpf($sformatf("c G-only fetch, GPA bit %0d", hi[k]),
              FW'({vpn, 12'h000}), 2'b00);
      chk($sformatf("c G-only fetch, GPA bit %0d: no PTE read", hi[k]),
          n_acc == 0);
    end
    // d: the lowest root GPA bit above the Sv39x4 width, and the
    // highest root bit vsatp.PPN holds.
    hi[0] = SV39X4_GPA_WIDTH;
    hi[1] = CSR_VSATP_PPN_W + 11;
    for (int k = 0; k < 2; k++) begin
      setup2m($sformatf("w_d_root_bit%0d", hi[k]), km, M_39);
      void'(vspath(pte(GP_CODE, F_RXAD)));
      gcode_ok();
      root = CSR_VSATP_PPN_W'(K_VROOT >> 12) |
             (CSR_VSATP_PPN_W'(1) << (hi[k] - 12));
      cs_vsatp_ppn(root);
      chk($sformatf("d root bit %0d: vsatp.PPN holds it", hi[k]),
          ptw_csr.vsatp_ppn == root);
      walk(1'b1, VW'(VA), ACC_X);
      exp_gpf($sformatf("d vsatp root, GPA bit %0d", hi[k]),
              FW'({root, 12'h000}) + FW'(8 * vidx(VA, kl - 1)), 2'b01);
      chk($sformatf("d vsatp root, GPA bit %0d: no PTE read", hi[k]),
          n_acc == 0);
    end
  endtask

  task automatic t_causes();
    logic [PA_WIDTH-1:0] t0;
    for (int a = 0; a < 2; a++) begin
      // PMP denies the read of the level-0 table: 5 for a read, 7 for a
      // store.
      setup(a == 0 ? "c_pmp_read_r" : "c_pmp_read_w");
      t0 = bmap(0, pte(44'h8_2345, 8'hCF)) & ~PW'('hFFF);  // D A X W R V
      cs_pmpcfg(0, 8'h18);
      cs_pmpaddr(0, PMW'((t0 >> 2) | PW'('h1FF)));
      cs_pmpcfg(1, 8'h1F);
      cs_pmpaddr(1, '1);
      walk(1'b0, VW'(VA), a == 0 ? ACC_R : ACC_W);
      exp_flt(tname, a == 0 ? 5 : 7);
      // The final GPA is unmapped by the G-stage: 21 for a read, 23
      // for a store, kind 00.
      setup2(a == 0 ? "c_gpf_r" : "c_gpf_w");
      void'(vspath(pte(GP_CODE, 8'hCF)));
      void'(gcode(64'd0));
      walk(1'b1, VW'(VA), a == 0 ? ACC_R : ACC_W);
      exp_flt(tname, a == 0 ? 21 : 23);
      chk({tname, ": kind 00, the page"}, (r_imp == 2'b00) &&
          (r_gpa == FAULT_GPA_WIDTH'({GP_CODE, 12'h000})));
    end
  endtask

  task automatic t_leaf_checks();
    logic [PA_WIDTH-1:0] la;
    logic [63:0]         sp;
    // ---- U against the privilege (MMU-8c, ITLB-16) ----------------
    lc_s("lc_s_u_fetch_ucl", pte(44'h8_2345, F_RX), 0, ACC_X, PRV_U,
         1'b1, 12);                                  // U fetch, U clear
    lc_s("lc_s_s_fetch_uset", pte(44'h8_2345, F_URX_NA), 0, ACC_X, PRV_S,
         1'b1, 12);                                  // S fetch, U set
    lc_vs("lc_vs_vu_fetch_ucl", pte(44'(GP_CODE), F_RX), 0, ACC_X, PRV_U,
          1'b1, 12);                                 // VU fetch, U clear
    lc_vs("lc_vs_vs_fetch_uset", pte(44'(GP_CODE), F_URX_NA), 0, ACC_X,
          PRV_S, 1'b1, 12);                          // VS fetch, U set
    lc_s("lc_s_s_read_uset", pte(44'h8_2345, F_URX_NA), 0, ACC_R, PRV_S,
         1'b1, 13);                                  // SUM clear
    lc_s("lc_s_s_store_uset", pte(44'h8_2345, F_URWX), 0, ACC_W,
         PRV_S, 1'b1, 15);                           // SUM clear
    // The permitted cases, so the U rule is not "always fault": a U
    // fetch from a U leaf and an S fetch from a non-U leaf update A.
    setup("lc_s_u_fetch_uset_ok");
    cs_menvcfg_adue(1'b1);
    req_priv = PRV_U;
    la = bmap(0, pte(44'h8_2345, F_URX_NA));
    walk(1'b0, VW'(VA), ACC_X);
    exp_hit("U fetch from a U leaf", PNW'('h8_2345), SZ_4K, 2'd0);
    chk("U fetch from a U leaf: A set by one CAS", (n_cas == 1) &&
        (rdw(la) == pte(44'h8_2345, F_URXA)));
    setup2("lc_vs_vu_fetch_uset_ok");
    cs_henvcfg_adue(1'b1);
    cs_menvcfg_adue(1'b1);
    req_priv = PRV_U;
    la = vspath(pte(GP_CODE, F_URX_NA));
    gcode_ok();
    walk(1'b1, VW'(VA), ACC_X);
    exp_hit("VU fetch from a U leaf", SP_CODE, SZ_4K, 2'd0);
    chk("VU fetch from a U leaf: A set", rdw(la) == pte(GP_CODE, F_URXA));

    // ---- the access type (MMU-26a) --------------------------------
    lc_s("lc_s_no_x", pte(44'h8_2345, 8'h03), 0, ACC_X, PRV_S, 1'b1, 12);
    lc_s("lc_s_no_w", pte(44'h8_2345, F_RX), 0, ACC_W, PRV_S, 1'b1, 15);
    lc_s("lc_s_no_r", pte(44'h8_2345, 8'h09), 0, ACC_R, PRV_S, 1'b1, 13);
    lc_vs("lc_vs_no_x", pte(GP_CODE, 8'h03), 0, ACC_X, PRV_S, 1'b1, 12);
    lc_vs("lc_vs_no_w", pte(GP_CODE, F_RX), 0, ACC_W, PRV_S, 1'b1, 15);
    lc_vs("lc_vs_no_r", pte(GP_CODE, 8'h09), 0, ACC_R, PRV_S, 1'b1, 13);
    lc_g("lc_g_no_x", pte(44'(SP_CODE), 8'h13), 0, 1'b1);   // U R, A clear
    lc_g("lc_g_no_u", pte(44'(SP_CODE), F_RX), 0, 1'b1);    // R X, A clear
    // A G leaf without R for the implicit read of a VS table page (the
    // level-1 table): kind 01, and nothing is updated.
    setup2("lc_g_no_r_implicit");
    cs_menvcfg_adue(1'b1);
    vspath_tf(pte(GP_CODE, F_RXAD), 1, 8'h19);       // U X
    gcode_ok();
    la = vs_gleaf(1);
    sp = vs_spa(1);
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("G leaf without R, VS table read",
            FW'(vs_tbl(1)) + FW'(8 * vidx(VA, 1)), 2'b01);
    chk("no R implicit: no CAS", n_cas == 0);
    chk("no R implicit: leaf unchanged",
        rdw(la) == pte(44'(sp >> 12), 8'h19));
    // A G leaf without W for the VS update. The leaf is read first (R
    // granted, A set, so no update for the read); the write needs W
    // and D: neither is set and nothing is stored.
    setup2("lc_g_no_w_update");
    cs_henvcfg_adue(1'b1);
    cs_menvcfg_adue(1'b1);
    vspath_tf(pte(GP_CODE, F_RX), 0, F_URXA);        // VS A clear
    gcode_ok();
    la = vs_gleaf(0);
    sp = vs_spa(0);
    walk(1'b1, VW'(VA), ACC_X);
    exp_gpf("G leaf without W, VS update",
            FW'(vs_tbl(0)) + FW'(8 * vidx(VA, 0)), 2'b10);
    chk("no W update: no CAS", n_cas == 0);
    chk("no W update: G leaf unchanged",
        rdw(la) == pte(44'(sp >> 12), F_URXA));
    chk("no W update: VS leaf unchanged",
        rdw(PW'(bs.pte_addr(va64(VA), 0))) == pte(GP_CODE, F_RX));

    // ---- reserved encodings (MMU-U6, MMU-U7) ----------------------
    lc_s("lc_s_pbmt3", pte_x(44'h8_2345, F_RX, 2'd3, 1'b0), 0, ACC_X,
         PRV_S, 1'b1, 12);
    lc_s("lc_s_pbmte", pte_x(44'h8_2345, F_RX, 2'd1, 1'b0), 0, ACC_X,
         PRV_S, 1'b0, 12);
    lc_s("lc_s_napot_rsv", pte_x(44'h8_2344, F_RX, 2'd0, 1'b1), 0, ACC_X,
         PRV_S, 1'b1, 12);
    lc_s("lc_s_rsv_bits", pte(44'h8_2345, F_RX) | (64'd1 << 57), 0,
         ACC_X, PRV_S, 1'b1, 12);
    lc_vs("lc_vs_pbmt3", pte_x(44'(GP_CODE), F_RX, 2'd3, 1'b0), 0, ACC_X,
          PRV_S, 1'b1, 12);
    lc_vs("lc_vs_pbmte", pte_x(44'(GP_CODE), F_RX, 2'd1, 1'b0), 0, ACC_X,
          PRV_S, 1'b0, 12);
    lc_vs("lc_vs_napot_rsv", pte_x(44'h0124, F_RX, 2'd0, 1'b1), 0, ACC_X,
          PRV_S, 1'b1, 12);
    lc_g("lc_g_pbmt3", pte_x(44'(SP_CODE), F_URX_NA, 2'd3, 1'b0), 0, 1'b1);
    lc_g("lc_g_pbmte", pte_x(44'(SP_CODE), F_URX_NA, 2'd1, 1'b0), 0, 1'b0);
    lc_g("lc_g_napot_rsv", pte_x(44'h8_4564, F_URX_NA, 2'd0, 1'b1), 0,
         1'b1);

    // ---- the misaligned superpage ---------------------------------
    lc_s("lc_s_misaligned", pte(44'h8_2201, F_RX), 1, ACC_X, PRV_S, 1'b1,
         12);
    lc_vs("lc_vs_misaligned", pte(44'h201, F_RX), 1, ACC_X, PRV_S, 1'b1,
          12);
    lc_g("lc_g_misaligned", pte(44'h8_4401, F_URX_NA), 1, 1'b1);
  endtask

  // =================================================================
  // BP-146: every mode, with the page-table builder (pt_build_pkg).
  // =================================================================
  // The builder's regions. Supervisor physical: the single-stage root and
  // table pool, the G-stage root (16 KiB) and pool, and the supervisor
  // pages that back the VS-stage tables. Guest physical: the VS-stage
  // root and pool, at GPA bit 40, below every x4 width. Every builder
  // region is apart from the hand-written tables above (0x8100_0000 to
  // 0x8300_2FFF) and from the leaf pages the cases map.
  localparam logic [63:0] B_SROOT = 64'h0_9000_0000;
  localparam logic [63:0] B_SPOOL = 64'h0_9000_1000;
  localparam logic [63:0] B_STOP  = 64'h0_9010_0000;
  localparam logic [63:0] B_GROOT = 64'h0_9100_0000;
  localparam logic [63:0] B_GPOOL = 64'h0_9100_4000;
  localparam logic [63:0] B_GTOP  = 64'h0_9120_0000;
  localparam logic [63:0] B_BACK  = 64'h0_9200_0000;
  localparam logic [63:0] B_BTOP  = 64'h0_9230_0000;
  localparam logic [63:0] B_VROOT = 64'h100_0000_0000;
  localparam logic [63:0] B_VPOOL = 64'h100_0000_1000;
  localparam logic [63:0] B_VTOP  = 64'h100_0010_0000;
  // A table page no case follows (a bad pointer's target).
  localparam logic [43:0] B_NOWHERE = 44'h9_5000;
  // The MODE values M_BARE to M_57, nlev, gwid, va64, bsync and the
  // objects img, bs and bg are declared with the knob (BP-149).

  // PTE flag bytes, D A G U X W R V.
  localparam logic [7:0] F_GLEAF = 8'hDB;     // G-stage leaf: D A U X R V
  localparam logic [7:0] F_BACK  = 8'hDF;     // a VS table page's G leaf

  // The five address indices the cases use, level 4 to level 0. I2's
  // bits 8:6 are zero, so a 512 GiB leaf's page (VPN 26:0) is below bit
  // 24, inside PPN_WIDTH at any PA_WIDTH from 36; a 256 TiB leaf's page
  // (VPN 35:0) is inside it only with I3 = 0 while PPN_WIDTH is below 36.
  localparam logic [8:0] I4 = 9'h0A5;
  localparam logic [8:0] I3 = 9'h0C3;
  localparam logic [8:0] I2 = 9'h02B;
  localparam logic [8:0] I1 = 9'h155;
  localparam logic [8:0] I0 = 9'h0AA;

  // ---- expected values, from the rule text --------------------------
  // IL-7: the size code of a leaf at level l.
  function automatic logic [2:0] sz_of(input int l, input logic napot);
    case (l)
      4:       return 3'b101;       // 256 TiB
      3:       return 3'b100;       // 512 GiB
      2:       return 3'b011;       // 1 GiB
      1:       return 3'b010;       // 2 MiB
      default: return napot ? 3'b001 : 3'b000;
    endcase
  endfunction

  // The page bits a leaf at level l takes from the address.
  function automatic logic [63:0] lmask(input int l);
    return (64'd1 << (9 * l)) - 64'd1;
  endfunction

  // A VPN of nl levels from five indices (level 4 first).
  function automatic logic [VW-1:0] vpn_n(input int nl,
                                          input logic [8:0] i4,
                                          input logic [8:0] i3,
                                          input logic [8:0] i2,
                                          input logic [8:0] i1,
                                          input logic [8:0] i0);
    logic [44:0] v;
    v = {i4, i3, i2, i1, i0};
    v = v & ((45'd1 << (9 * nl)) - 45'd1);
    return VW'(v);
  endfunction

  // An aligned leaf PPN for each level, every one inside PPN_WIDTH.
  function automatic logic [43:0] lppn(input int l);
    case (l)
      0:       return 44'h8_2345;
      1:       return 44'h8_2200;
      2:       return 44'h8_0000;
      default: return 44'h0;         // 512 GiB, 256 TiB: aligned is 0
    endcase
  endfunction

  // ---- builder set-up -------------------------------------------------
  // A single-stage walk in mode m, root B_SROOT.
  task automatic bsetup_s(input string nm, input logic [3:0] m);
    setup(nm);
    img = new();
    bs  = new("s", img, m, 1'b0, B_SROOT, B_SPOOL, B_STOP);
    cs_satp_mode(m);
    cs_satp_ppn(PNW'(B_SROOT >> 12));
  endtask

  // A V=1 walk: hgatp mode gm (root B_GROOT), vsatp mode vm (root
  // B_VROOT, guest physical), or vsatp Bare.
  task automatic bsetup_h(input string nm, input logic [3:0] vm,
                          input logic [3:0] gm);
    setup(nm);
    cs_satp_mode(M_BARE);
    img = new();
    bg  = new("g", img, gm, 1'b1, B_GROOT, B_GPOOL, B_GTOP);
    bg.set_back(B_BACK, B_BTOP, F_BACK);
    cs_hgatp_mode(gm);
    cs_hgatp_ppn(PNW'(B_GROOT >> 12));
    if (vm != M_BARE) begin
      bs = new("vs", img, vm, 1'b0, B_VROOT, B_VPOOL, B_VTOP);
      bs.set_gstage(bg);
    end
    cs_vsatp_mode(vm);
    cs_vsatp_ppn(CSR_VSATP_PPN_W'(B_VROOT >> 12));
  endtask

  // ---- t_bld: the builder itself ---------------------------------------
  task automatic t_bld();
    logic [63:0] la;
    logic [63:0] lb;
    logic [63:0] g;
    logic        ok;
    logic [VW-1:0] v;
    int          np;
    bsetup_s("bld_soft", M_48);
    bs.set_soft(1'b1);
    v  = vpn_n(4, I4, I3, I2, I1, I0);
    la = bs.map(va64(v), 0, pte(44'h8_2345, F_RXAD));
    chk("bld: three tables allocated",
        bs.pool_nx == B_SPOOL + 64'h3000);
    chk("bld: the leaf PTE address is the level-0 table's",
        la == B_SPOOL + 64'h2000 + 64'(8 * I0));
    chk("bld: the root PTE points at the first table",
        img.get(B_SROOT + 64'(8 * I3)) == pte(44'(B_SPOOL >> 12), F_PTR));
    lb = bs.map(va64(v), 0, pte(44'h8_2345, F_RXAD));
    chk("bld: the same PTE again is no conflict",
        (bs.n_conflict == 0) && (lb == la));
    void'(bs.map(va64(v), 0, pte(44'h8_6666, F_RXAD)));
    chk("bld: a different leaf is a conflict", bs.n_conflict == 1);
    chk("bld: and the leaf is not overwritten",
        img.get(la) == pte(44'h8_2345, F_RXAD));
    void'(bs.map(va64(v), 1, pte(44'h8_2200, F_RXAD)));
    chk("bld: a leaf over a pointer is a conflict", bs.n_conflict == 2);
    // A neighbour in the same level-0 table allocates nothing.
    np = int'(bs.pool_nx - B_SPOOL);
    void'(bs.map(va64(v ^ VW'(1)), 0, pte(44'h8_2346, F_RXAD)));
    chk("bld: a neighbour shares the path",
        int'(bs.pool_nx - B_SPOOL) == np);
    // A path through a leaf is a conflict.
    void'(bs.map(va64(vpn_n(4, I4, 9'h001, I2, I1, I0)), 2,
                 pte(44'h8_0000, F_RXAD)));
    void'(bs.map(va64(vpn_n(4, I4, 9'h001, I2, I1, I0)), 0,
                 pte(44'h8_2345, F_RXAD)));
    chk("bld: a path through a leaf is a conflict", bs.n_conflict == 3);
    chk("bld: pte_addr finds the leaf", bs.pte_addr(va64(v), 0) == la);

    // The x4 root: 16 KiB, eleven index bits; the top index is in the
    // fourth page.
    bsetup_h("bld_x4_root", M_BARE, M_48);
    g  = (64'h7FF << 39) | 64'h123_4000;
    la = bg.map(g, 0, pte(44'h8_2345, F_GLEAF));
    chk("bld: x4 root index 0x7FF", bg.idx(g, 3) == 32'h7FF);
    chk("bld: x4 root PTE in the root's fourth page",
        bg.pte_addr(g, 3) == B_GROOT + 64'h3FF8);
    chk("bld: x4 translates its own mapping",
        (bg.xlate(g, ok) == 64'h8_2345_000) && ok);
    // A VS stage's tables are guest physical: its root page is backed by
    // the first backing page, mapped by the G-stage.
    bsetup_h("bld_vs", M_39, M_39);
    la = bs.map(va64(vpn_n(3, 0, 0, I2, I1, I0)), 0,
                pte(44'h4_0123, F_RXAD));
    g  = bg.xlate(B_VROOT, ok);
    chk("bld: the VS root page is mapped to the first backing page",
        ok && (g == B_BACK));
    g  = bg.xlate(B_VPOOL + 64'h1000, ok);
    chk("bld: the VS level-0 table page is mapped",
        ok && (g == B_BACK + 64'h2000));
    chk("bld: the VS leaf is written at its supervisor address",
        la == B_BACK + 64'h2000 + 64'(8 * I0));
  endtask

  // ---- a: single stage, Sv48 and Sv57, a leaf at every level ----------
  task automatic t_m_a();
    logic [3:0]    m;
    int            nl;
    logic [VW-1:0] v;
    logic [63:0]   la;
    for (int k = 0; k < 2; k++) begin
      m  = (k == 0) ? M_48 : M_57;
      nl = nlev(m);
      for (int l = 0; l < nl; l++) begin
        bsetup_s($sformatf("a_sv%0d_l%0d", (k == 0) ? 48 : 57, l), m);
        v  = vpn_n(nl, I4, (l == 4) ? 9'h000 : I3, I2, I1, I0);
        la = bs.map(va64(v), l, pte(lppn(l), F_RXAD));
        bsync();
        walk(1'b0, v, ACC_X);
        exp_hit(tname, PNW'(lppn(l)), sz_of(l, 1'b0), 2'd0);
        chk($sformatf("%s: %0d reads (%0d)", tname, nl - l, n_acc),
            n_acc == nl - l);
        chk($sformatf("%s: root PTE address", tname),
            acc_pa[0] == PW'(B_SROOT +
                             8 * ((64'(v) >> (9 * (nl - 1))) & 64'h1FF)));
        chk($sformatf("%s: leaf PTE address", tname),
            acc_pa[nl - l - 1] == PW'(la));
        chk($sformatf("%s: perm", tname), r_perm == F_RXAD);
      end
    end
  endtask

  // ---- b: G-stage only, Sv48x4 and Sv57x4, a leaf at every level -------
  task automatic t_m_b();
    logic [3:0]    m;
    int            nl;
    int            gw;
    logic [VW-1:0] v;
    logic [63:0]   la;
    logic [63:0]   ri;
    for (int k = 0; k < 2; k++) begin
      m  = (k == 0) ? M_48 : M_57;
      nl = nlev(m);
      gw = gwid(m);
      for (int l = 0; l < nl; l++) begin
        bsetup_h($sformatf("b_sv%0dx4_l%0d", (k == 0) ? 48 : 57, l),
                 M_BARE, m);
        // The GPA's top bit, gw - 1, is the root index's bit 10.
        v  = vpn_n(nl, I4, (l == 4) ? 9'h000 : I3, I2, I1, I0) |
             (VW'(1) << (gw - 13));
        ri = 64'(v >> (9 * (nl - 1)));
        la = bg.map(va64(v), l, pte(lppn(l), F_GLEAF));
        bsync();
        walk(1'b1, v, ACC_X);
        exp_hit(tname, PNW'(64'(lppn(l)) | (64'(v) & lmask(l))),
                sz_of(l, 1'b0), 2'd0);
        chk($sformatf("%s: root index bit 10 set (%03h)", tname, ri),
            (ri >> 10) == 64'd1);
        chk($sformatf("%s: root PTE address, eleven-bit index", tname),
            acc_pa[0] == PW'(B_GROOT + 8 * ri));
        chk($sformatf("%s: %0d reads (%0d)", tname, nl - l, n_acc),
            n_acc == nl - l);
        chk($sformatf("%s: leaf PTE address", tname),
            acc_pa[nl - l - 1] == PW'(la));
        chk($sformatf("%s: perm, the G leaf's", tname), r_perm == F_GLEAF);
      end
    end
  endtask

  // ---- c: nested, every VS-stage / G-stage mode pair --------------------
  task automatic t_m_c();
    logic [3:0]    vm;
    logic [3:0]    gm;
    int            nv;
    int            ng;
    int            lv;
    int            lg;
    logic [VW-1:0] v;
    logic [43:0]   gl;       // the VS leaf's guest page
    logic [43:0]   sl;       // the G leaf's supervisor page
    logic [63:0]   gp;       // the final guest page
    logic [63:0]   sp;
    logic [2:0]    sz;
    for (int k = 0; k < 9; k++) begin
      vm = (k / 3 == 0) ? M_39 : (k / 3 == 1) ? M_48 : M_57;
      gm = (k % 3 == 0) ? M_39 : (k % 3 == 1) ? M_48 : M_57;
      nv = nlev(vm);
      ng = nlev(gm);
      // The leaf levels, so the nine pairs see every size pair of
      // levels 0 to 2 at the two stages.
      lv = k % 3;
      lg = (k / 3 + 1) % 3;
      bsetup_h($sformatf("c_vs%0d_g%0d_l%0d%0d", 9 * nv + 12,
                         9 * ng + 14, lv, lg), vm, gm);
      v  = vpn_n(nv, I4, I3, I2, I1, I0);
      gl = (lv == 0) ? 44'hC_0123 : (lv == 1) ? 44'hC_0200 : 44'hC_0000;
      sl = (lg == 0) ? 44'h8_4567 : (lg == 1) ? 44'h8_4400 : 44'h8_0000;
      gp = 64'(gl) | (64'(v) & lmask(lv));
      sp = 64'(sl) | (gp & lmask(lg));
      void'(bs.map(va64(v), lv, pte(gl, F_RXAD)));
      void'(bg.map(gp << 12, lg, pte(sl, F_GLEAF)));
      bsync();
      walk(1'b1, v, ACC_X);
      // MMU-27: the smaller of the two leaf sizes.
      sz = (sz_of(lv, 1'b0) < sz_of(lg, 1'b0)) ? sz_of(lv, 1'b0)
                                               : sz_of(lg, 1'b0);
      exp_hit(tname, PNW'(sp), sz, 2'd0);
      chk($sformatf("%s: perm, the VS leaf's", tname), r_perm == F_RXAD);
      // MMU-21: a G-stage walk of ng reads before each VS-stage read,
      // and one for the final GPA to its leaf.
      chk($sformatf("%s: reads %0d exp %0d", tname, n_acc,
                    (nv - lv) * (ng + 1) + (ng - lg)),
          n_acc == (nv - lv) * (ng + 1) + (ng - lg));
    end
  endtask

  // ---- d: the misaligned superpage at levels 3 and 4 ---------------------
  // A PPN bit inside the leaf's mask that a leaf one level lower would
  // not have: bit 20 at level 3 (mask 26:0), bit 30 at level 4 (35:0).
  task automatic t_m_d();
    logic [3:0]    m;
    int            l;
    int            nl;
    logic [43:0]   p;
    logic [VW-1:0] v;
    for (int k = 0; k < 3; k++) begin
      m  = (k == 0) ? M_48 : M_57;
      l  = (k == 2) ? 4 : 3;
      nl = nlev(m);
      p  = (l == 4) ? 44'h4000_0000 : 44'h10_0000;
      v  = vpn_n(nl, I4, (l == 4) ? 9'h000 : I3, I2, I1, I0);
      bsetup_s($sformatf("d_s_sv%0d_l%0d", 9 * nl + 12, l), m);
      void'(bs.map(va64(v), l, pte(p, F_RXAD)));
      bsync();
      walk(1'b0, v, ACC_X);
      exp_flt(tname, 12);
      chk($sformatf("%s: %0d reads", tname, nl - l), n_acc == nl - l);
      bsetup_h($sformatf("d_g_sv%0dx4_l%0d", 9 * nl + 12, l), M_BARE, m);
      void'(bg.map(va64(v), l, pte(p, F_GLEAF)));
      bsync();
      walk(1'b1, v, ACC_X);
      exp_gpf(tname, FW'({v, 12'h000}), 2'b00);
      chk($sformatf("%s: %0d reads", tname, nl - l), n_acc == nl - l);
    end
  endtask

  // ---- e: a non-leaf PTE breaking a non-leaf rule at levels 3 and 4 -----
  // Sv57 and Sv57x4: the root (level 4) and level 3. Rules: D, A, U, N,
  // PBMT set on a non-leaf (privileged 11.3.2; MMU-U6, MMU-U7).
  task automatic t_m_e();
    logic [63:0]   bad;
    logic [63:0]   la;
    logic [VW-1:0] v;
    string         rn;
    v = vpn_n(5, I4, I3, I2, I1, I0);
    for (int l = 3; l <= 4; l++) begin
      for (int r = 0; r < 5; r++) begin
        case (r)
          0: begin rn = "d";    bad = pte(B_NOWHERE, 8'h81); end
          1: begin rn = "a";    bad = pte(B_NOWHERE, 8'h41); end
          2: begin rn = "u";    bad = pte(B_NOWHERE, 8'h11); end
          3: begin rn = "n";    bad = pte_x(B_NOWHERE, F_PTR, 2'd0, 1'b1);
             end
          default: begin
             rn = "pbmt"; bad = pte_x(B_NOWHERE, F_PTR, 2'd1, 1'b0);
          end
        endcase
        bsetup_s($sformatf("e_s_l%0d_%s", l, rn), M_57);
        la = bs.map(va64(v), l, bad);
        bsync();
        walk(1'b0, v, ACC_X);
        exp_flt(tname, 12);
        chk($sformatf("%s: %0d reads, the last the bad PTE", tname, 5 - l),
            (n_acc == 5 - l) && (acc_pa[4 - l] == PW'(la)));
        bsetup_h($sformatf("e_g_l%0d_%s", l, rn), M_BARE, M_57);
        la = bg.map(va64(v), l, bad);
        bsync();
        walk(1'b1, v, ACC_X);
        exp_gpf(tname, FW'({v, 12'h000}), 2'b00);
        chk($sformatf("%s: %0d reads, the last the bad PTE", tname, 5 - l),
            (n_acc == 5 - l) && (acc_pa[4 - l] == PW'(la)));
      end
    end
  endtask

  // ---- f: N at levels 1 to 4 (Sv57), and 64 KiB NAPOT at level 0 --------
  task automatic t_m_f();
    logic [63:0]   la;
    logic [VW-1:0] v;
    for (int l = 1; l <= 4; l++) begin
      bsetup_s($sformatf("f_n_l%0d", l), M_57);
      v  = vpn_n(5, I4, (l == 4) ? 9'h000 : I3, I2, I1, I0);
      la = bs.map(va64(v), l, pte_x(lppn(l), F_RXAD, 2'd0, 1'b1));
      bsync();
      walk(1'b0, v, ACC_X);
      exp_flt(tname, 12);
      chk($sformatf("%s: %0d reads, the last the N leaf", tname, 5 - l),
          (n_acc == 5 - l) && (acc_pa[4 - l] == PW'(la)));
    end
    for (int k = 0; k < 2; k++) begin
      bsetup_s((k == 0) ? "f_napot_sv48" : "f_napot_sv57",
               (k == 0) ? M_48 : M_57);
      v = vpn_n((k == 0) ? 4 : 5, I4, I3, I2, I1, I0);
      void'(bs.map(va64(v), 0, pte_x(44'h8_2348, F_RXAD, 2'd0, 1'b1)));
      bsync();
      walk(1'b0, v, ACC_X);
      exp_hit(tname, PNW'('h8_2348), SZ_64K, 2'd0);
      chk($sformatf("%s: %0d reads", tname, (k == 0) ? 4 : 5),
          n_acc == ((k == 0) ? 4 : 5));
    end
  endtask

  // ---- g: the GPA bound of each x4 mode ----------------------------------
  // Sv39x4 rejects GPA bit 41 and Sv48x4 bit 50, with the GPA whole
  // (MMU-23); Sv57x4 translates a GPA with its top bit set. For the
  // fetch address (kind 00), the vsatp root (kind 01) and a VS-stage
  // PTE's GPA (kind 01 for a non-leaf, 00 for a leaf).
  task automatic t_m_g();
    logic [3:0]    gm;
    int            gw;
    logic [VW-1:0] v;
    logic [VW-1:0] vh;
    logic [63:0]   hi;
    logic [43:0]   p;
    logic [CSR_VSATP_PPN_W-1:0] rt;
    for (int k = 0; k < 2; k++) begin
      gm = (k == 0) ? M_39 : M_48;
      gw = gwid(gm);
      // kind 00: the G-stage-only fetch address. The GPA without the
      // high bit is mapped, so a walker that ignored it would hit.
      bsetup_h($sformatf("g_fetch_x4_%0d_bit%0d", gw, gw), M_BARE, gm);
      v  = vpn_n(nlev(gm), I4, I3, I2, I1, I0);
      vh = v | (VW'(1) << (gw - 12));
      void'(bg.map(va64(v), 0, pte(lppn(0), F_GLEAF)));
      bsync();
      walk(1'b1, vh, ACC_X);
      exp_gpf(tname, FW'({vh, 12'h000}), 2'b00);
      chk($sformatf("%s: no PTE read", tname), n_acc == 0);
      // kind 01: the vsatp root at the bound. The path is built at the
      // root without the bit, which the walker would otherwise read.
      bsetup_h($sformatf("g_root_x4_%0d_bit%0d", gw, gw), M_39, gm);
      v = vpn_n(3, I4, I3, I2, I1, I0);
      void'(bs.map(va64(v), 0, pte(44'hC_0123, F_RXAD)));
      void'(bg.map(64'hC_0123 << 12, 0, pte(44'h8_4567, F_GLEAF)));
      bsync();
      rt = CSR_VSATP_PPN_W'(B_VROOT >> 12) |
           (CSR_VSATP_PPN_W'(1) << (gw - 12));
      cs_vsatp_ppn(rt);
      walk(1'b1, v, ACC_X);
      exp_gpf(tname, FW'({rt, 12'h000}) + FW'(8 * I2), 2'b01);
      chk($sformatf("%s: no PTE read", tname), n_acc == 0);
      // A VS-stage PTE's GPA: a non-leaf at the VS root (kind 01, the next
      // PTE's GPA) and a leaf (kind 00, the page).
      p = 44'h4_0041 | (44'd1 << (gw - 12));
      bsetup_h($sformatf("g_vsptr_x4_%0d_bit%0d", gw, gw), M_48, gm);
      v = vpn_n(4, I4, I3, I2, I1, I0);
      void'(bs.map(va64(v), 3, pte(p, F_PTR)));
      bsync();
      walk(1'b1, v, ACC_X);
      exp_gpf(tname, FW'({p, 12'h000}) + FW'(8 * I2), 2'b01);
      // The fault is found on the VS root PTE, before the G-stage walk
      // for the next table: one G walk and the VS root read.
      chk($sformatf("%s: %0d reads, none for the faulting GPA (%0d)",
                    tname, nlev(gm) + 1, n_acc), n_acc == nlev(gm) + 1);
      p = 44'h4_0123 | (44'd1 << (gw - 12));
      bsetup_h($sformatf("g_vsleaf_x4_%0d_bit%0d", gw, gw), M_48, gm);
      void'(bs.map(va64(v), 0, pte(p, F_RXAD)));
      bsync();
      walk(1'b1, v, ACC_X);
      exp_gpf(tname, FW'({p, 12'h000}), 2'b00);
      // Four VS reads, each after its G walk; none for the final GPA.
      chk($sformatf("%s: %0d reads, none for the faulting GPA (%0d)",
                    tname, 4 * (nlev(gm) + 1), n_acc),
          n_acc == 4 * (nlev(gm) + 1));
    end

    // Sv57x4 translates. The fetch address with bit 58 set (kind 00).
    bsetup_h("g_fetch_x4_59_bit58", M_BARE, M_57);
    v = vpn_n(5, I4, I3, I2, I1, I0) | (VW'(1) << (58 - 12));
    void'(bg.map(va64(v), 0, pte(lppn(0), F_GLEAF)));
    bsync();
    walk(1'b1, v, ACC_X);
    exp_hit(tname, PNW'(lppn(0)), SZ_4K, 2'd0);
    chk($sformatf("%s: 5 reads", tname), n_acc == 5);
    // The vsatp root at the highest bit vsatp.PPN holds, bit
    // CSR_VSATP_PPN_W + 11 (55): every VS table is above 2^50.
    hi = 64'd1 << (CSR_VSATP_PPN_W + 11);
    bsetup_h("g_root_x4_59_high", M_39, M_57);
    bs = new("vs", img, M_39, 1'b0, hi | B_VROOT, hi | B_VPOOL,
             hi | B_VTOP);
    bs.set_gstage(bg);
    cs_vsatp_ppn(CSR_VSATP_PPN_W'((hi | B_VROOT) >> 12));
    v = vpn_n(3, I4, I3, I2, I1, I0);
    // The VS leaf's guest page has the same high bit (kind 00 side).
    p = 44'(hi >> 12) | 44'h123;
    void'(bs.map(va64(v), 0, pte(p, F_RXAD)));
    void'(bg.map(64'(p) << 12, 0, pte(44'h8_4567, F_GLEAF)));
    bsync();
    walk(1'b1, v, ACC_X);
    exp_hit(tname, PNW'('h8_4567), SZ_4K, 2'd0);
    chk($sformatf("%s: 3 x 6 + 5 reads (%0d)", tname, n_acc), n_acc == 23);
    chk($sformatf("%s: the vsatp root's bit 55 is set", tname),
        ptw_csr.vsatp_ppn[CSR_VSATP_PPN_W - 1]);
  endtask

  // ---- h: A and D under Svadu, 5 levels and Sv57 over Sv57x4 -------------
  task automatic t_m_h();
    logic [VW-1:0] v;
    logic [63:0]   la;
    logic [63:0]   ga;
    logic [63:0]   vl;
    logic [63:0]   gl;
    // A store to a level-0 leaf with A and D clear: one CAS, last.
    bsetup_s("h_s57_store", M_57);
    cs_menvcfg_adue(1'b1);
    v  = vpn_n(5, I4, I3, I2, I1, I0);
    la = bs.map(va64(v), 0, pte(44'h8_2345, F_RWX));
    bsync();
    walk(1'b0, v, ACC_W);
    exp_hit(tname, PNW'('h8_2345), SZ_4K, 2'd0);
    chk($sformatf("%s: five reads and one CAS (%0d, %0d)", tname, n_acc,
                  n_cas), (n_acc == 6) && (n_cas == 1) && acc_op[5]);
    chk($sformatf("%s: CAS address", tname), acc_pa[5] == PW'(la));
    chk($sformatf("%s: CAS value sets A and D", tname),
        acc_swap[5] == pte(44'h8_2345, 8'hCF));
    chk($sformatf("%s: memory holds it", tname),
        rdw(PW'(la)) == pte(44'h8_2345, 8'hCF));
    // A 256 TiB leaf at the root with A clear: the CAS is at the root.
    bsetup_s("h_s57_root_leaf", M_57);
    cs_menvcfg_adue(1'b1);
    v  = vpn_n(5, I4, 9'h000, I2, I1, I0);
    la = bs.map(va64(v), 4, pte(44'h0, F_RX));
    bsync();
    walk(1'b0, v, ACC_X);
    exp_hit(tname, PNW'(0), 3'b101, 2'd0);
    chk($sformatf("%s: one read, one CAS at the root PTE", tname),
        (n_acc == 2) && (n_cas == 1) && acc_op[1] &&
        (acc_pa[1] == PW'(la)) && (acc_swap[1] == pte(44'h0, F_RXA)));
    // Sv57 over Sv57x4: the VS leaf and the G leaf of the final GPA have
    // A clear. The VS update is a store through the G-stage (MMU-8a),
    // whose leaf for the VS table page has W, A and D (F_BACK).
    bsetup_h("h_vs57_g57", M_57, M_57);
    cs_henvcfg_adue(1'b1);
    cs_menvcfg_adue(1'b1);
    v  = vpn_n(5, I4, I3, I2, I1, I0);
    vl = pte(44'hC_0123, F_RX);
    gl = pte(44'h8_4567, F_URX);
    la = bs.map(va64(v), 0, vl);
    ga = bg.map(64'hC_0123 << 12, 0, gl);
    bsync();
    walk(1'b1, v, ACC_X);
    exp_hit(tname, PNW'('h8_4567), SZ_4K, 2'd0);
    chk($sformatf("%s: perm has A", tname), r_perm == F_RXA);
    // 5 x (5 + 1) for the VS walk, 5 + CAS for the VS update, 5 + CAS for
    // the final GPA: 42, the CASes at 35 and 41.
    chk($sformatf("%s: 42 accesses, 2 CAS (%0d, %0d)", tname, n_acc, n_cas),
        (n_acc == 42) && (n_cas == 2));
    chk($sformatf("%s: VS CAS at 35: address, value", tname),
        acc_op[35] && (acc_pa[35] == PW'(la)) &&
        (acc_swap[35] == (vl | 64'h40)));
    chk($sformatf("%s: G CAS at 41: address, value", tname),
        acc_op[41] && (acc_pa[41] == PW'(ga)) &&
        (acc_swap[41] == (gl | 64'h40)));
    chk($sformatf("%s: memory holds both", tname),
        (rdw(PW'(la)) == (vl | 64'h40)) && (rdw(PW'(ga)) == (gl | 64'h40)));
  endtask

  // ---- i: MMU-21, Sv57 over Sv57x4 reads memory 35 times -------------
  task automatic t_m_i();
    logic [VW-1:0] v;
    int            nr;
    bsetup_h("i_vs57_g57_35", M_57, M_57);
    v = vpn_n(5, I4, I3, I2, I1, I0);
    void'(bs.map(va64(v), 0, pte(44'hC_0123, F_RXAD)));
    void'(bg.map(64'hC_0123 << 12, 0, pte(44'h8_4567, F_GLEAF)));
    bsync();
    walk(1'b1, v, ACC_X);
    exp_hit(tname, PNW'('h8_4567), SZ_4K, 2'd0);
    nr = 0;
    for (int k = 0; k < n_acc; k++) if (!acc_op[k]) nr++;
    chk($sformatf("%s: (5+1)(5+1)-1 = 35 reads (%0d of %0d)", tname, nr,
                  n_acc), (nr == 35) && (n_acc == 35) && (n_cas == 0));
  endtask

  // ---- j: a 512 GiB and a 256 TiB leaf whose page may pass PPN_WIDTH ----
  // The leaf PPN is 0 and aligned; the page takes VPN 26:0 (35:0). A page
  // with a bit at or above PPN_WIDTH is outside: access fault (MMU-28).
  // BP-147, rewritten by ruling: the expected answer is computed from
  // PPN_WIDTH. At PA_WIDTH 36 (PPN_WIDTH 24) both stimuli reach bit 24
  // and fault; at 48 (PPN_WIDTH 36) neither page can reach bit 36, so
  // both hit and the fault half is unreachable (it said fault at any
  // width until BP-147).
  task automatic j_leaf(input logic g, input int l, input logic [VW-1:0] v);
    logic [63:0] pg;
    pg = 64'(v) & lmask(l);                    // the leaf PPN is 0
    walk(g, v, ACC_X);
    if ((pg >> PNW) != 64'd0) begin
      exp_flt(tname, 1);
    end else begin
      // The single stage returns the leaf PPN, the G-stage only walk the
      // translated page (as cases a and b).
      exp_hit(tname, g ? PNW'(pg) : PNW'(0), sz_of(l, 1'b0), 2'd0);
    end
    chk($sformatf("%s: one read", tname), n_acc == 1);
  endtask

  task automatic t_m_j();
    logic [VW-1:0] v;
    bsetup_s("j_512g_wide", M_48);
    v = vpn_n(4, 0, I3, I2 | 9'h040, I1, I0);          // VPN bit 24
    void'(bs.map(va64(v), 3, pte(44'h0, F_RXAD)));
    bsync();
    j_leaf(1'b0, 3, v);
    bsetup_s("j_256t_wide", M_57);
    v = vpn_n(5, I4, I3, I2, I1, I0);                   // VPN bits 35:27
    void'(bs.map(va64(v), 4, pte(44'h0, F_RXAD)));
    bsync();
    j_leaf(1'b0, 4, v);
    // The same at the G-stage (G-stage only, Sv57x4).
    bsetup_h("j_g_256t_wide", M_BARE, M_57);
    void'(bg.map(va64(v), 4, pte(44'h0, F_GLEAF)));
    bsync();
    j_leaf(1'b1, 4, v);
  endtask

  // ---- BP-147 d: a 512 GiB page at a non-zero physical address ---------
  // A Sv48 leaf at level 3 (the root) whose PPN has every bit from 27 up
  // to PPN_WIDTH - 1 set, and PPN 26:0 zero (aligned): a hit. The single
  // stage returns the leaf PPN, checked whole; the G-stage only walk
  // (Sv48x4) returns the translated page, the PPN with VPN 26:0, checked
  // whole. PPN_WIDTH 24 (PA_WIDTH 36) has no bit at or above 27 to set.
  task automatic t_m_bp147_d();
    logic [VW-1:0] v;
    logic [43:0]   p;
    logic [63:0]   pg;
    if (PNW <= 27) begin
      $display("SKIP d_512g_high: PPN_WIDTH %0d has no bit 27", PNW);
      return;
    end
    p  = 44'(((64'd1 << PNW) - 64'd1) & ~((64'd1 << 27) - 64'd1));
    v  = vpn_n(4, 0, I3, I2, I1, I0);
    pg = 64'(p) | (64'(v) & lmask(3));
    bsetup_s("d_512g_high", M_48);
    void'(bs.map(va64(v), 3, pte(p, F_RXAD)));
    bsync();
    walk(1'b0, v, ACC_X);
    exp_hit(tname, PNW'(p), sz_of(3, 1'b0), 2'd0);
    chk($sformatf("%s: PPN bit %0d set", tname, PNW - 1), r_ppn[PNW - 1]);
    chk($sformatf("%s: one read", tname), n_acc == 1);
    bsetup_h("d_g_512g_high", M_BARE, M_48);
    void'(bg.map(va64(v), 3, pte(p, F_GLEAF)));
    bsync();
    walk(1'b1, v, ACC_X);
    exp_hit(tname, PNW'(pg), sz_of(3, 1'b0), 2'd0);
    chk($sformatf("%s: one read", tname), n_acc == 1);
  endtask

  // ---- BP-147 e: a 256 TiB leaf whose PPN has bit 36 or above set ------
  // Aligned (PPN 35:0 zero), so not a misaligned superpage. Bit 36 is at
  // or above PPN_WIDTH at every PA_WIDTH up to 48: the page names an
  // address outside every PMA region, an access fault, cause 1 (MMU-28).
  // Single stage, Sv57, with bit 36 and with bit 43, the PTE's top PPN
  // bit; and G-stage only, Sv57x4, with bit 36.
  task automatic t_m_bp147_e();
    logic [VW-1:0] v;
    v = vpn_n(5, I4, I3, I2, I1, I0);
    for (int b = 36; b <= 43; b += 7) begin
      bsetup_s($sformatf("e_256t_ppn_bit%0d", b), M_57);
      void'(bs.map(va64(v), 4, pte(44'd1 << b, F_RXAD)));
      bsync();
      walk(1'b0, v, ACC_X);
      exp_flt(tname, 1);
      chk($sformatf("%s: one read", tname), n_acc == 1);
    end
    bsetup_h("e_g_256t_ppn_bit36", M_BARE, M_57);
    void'(bg.map(va64(v), 4, pte(44'd1 << 36, F_GLEAF)));
    bsync();
    walk(1'b1, v, ACC_X);
    exp_flt(tname, 1);
    chk($sformatf("%s: one read", tname), n_acc == 1);
  endtask

  // ---- k: MODE is sampled when the walk starts (MMU-24a) ------------------
  // which 0: satp.MODE Sv57 -> Sv39 in the cycle after the request is
  // taken, before the walk's first step. which 1: hgatp.MODE Sv57x4 ->
  // Sv39x4 once the first memory access has been taken.
  task automatic walk_k(input logic v, input logic [VW-1:0] vpn,
                        input int which);
    int   n0;
    int   t;
    logic done;
    n0 = n_rsp;
    itlb_l2t_req_val = 1'b1;
    itlb_l2t_v       = v;
    itlb_l2t_vpn     = vpn;
    itlb_l2t_acc     = ACC_X;
    itlb_l2t_priv    = req_priv;
    itlb_l2t_tag     = 2'd1;
    do @(posedge clk); while (!itlb_l2t_req_rdy);
    #1;
    itlb_l2t_req_val = 1'b0;
    done = 1'b0;
    if (which == 0) begin
      cs_satp_mode(M_39);
      done = 1'b1;
    end
    t = 0;
    while ((n_rsp == n0) && (t < 4000)) begin
      @(posedge clk);
      #1;
      t++;
      if (!done && (n_rsp == n0) && (n_acc >= 1)) begin
        cs_hgatp_mode(M_39);
        done = 1'b1;
      end
    end
    chk({tname, ": one response"}, n_rsp == n0 + 1);
    chk({tname, ": the MODE changed during the walk"}, done);
    chk({tname, ": no memory protocol error"}, n_mem_err == 0);
  endtask

  task automatic t_m_k();
    logic [VW-1:0] v;
    bsetup_s("k_satp_57_to_39", M_57);
    v = vpn_n(5, I4, I3, I2, I1, I0);
    void'(bs.map(va64(v), 0, pte(44'h8_2345, F_RXAD)));
    bsync();
    walk_k(1'b0, v, 0);
    exp_hit(tname, PNW'('h8_2345), SZ_4K, 2'd0);
    chk($sformatf("%s: five reads, Sv57 (%0d)", tname, n_acc), n_acc == 5);
    chk($sformatf("%s: satp now Sv39", tname), ptw_csr.satp_mode == M_39);
    bsetup_h("k_hgatp_57x4_to_39x4", M_39, M_57);
    v = vpn_n(3, I4, I3, I2, I1, I0);
    void'(bs.map(va64(v), 0, pte(44'hC_0123, F_RXAD)));
    void'(bg.map(64'hC_0123 << 12, 0, pte(44'h8_4567, F_GLEAF)));
    bsync();
    walk_k(1'b1, v, 1);
    exp_hit(tname, PNW'('h8_4567), SZ_4K, 2'd0);
    chk($sformatf("%s: 3 x (5 + 1) + 5 reads, Sv57x4 (%0d)", tname, n_acc),
        n_acc == 23);
    chk($sformatf("%s: hgatp now Sv39x4", tname),
        ptw_csr.hgatp_mode == M_39);
  endtask

  // =================================================================
  // THE IMAGE CHECK (BP-149, perf_decisions.md PF-17). +IMG=<file>, an
  // image tb/pt_gen.sv wrote: its word lines are loaded into the memory
  // model, satp is set from its satp line, and every page of its map
  // lines is walked by the walker. Each walk must hit with the map
  // line's PA, a 4 KiB size and PBMT 0, and the leaf the rule gives
  // (PF-17: V R X A U, so PERM 5B), after five reads, one per Sv57 level,
  // and no CAS (A is set; no D update for a fetch). The fetch is at U,
  // the privilege of a trace's code. Nothing but the image is read: a
  // word missing from it, a wrong map line or a wrong root fails.
  // =================================================================
  localparam logic [7:0] F_IMG = 8'h5B;              // A U X R V

  task automatic t_img(input string f);
    int          fd;
    int          r;
    int          n;
    int          nw;
    string       line;
    string       key;
    logic [63:0] x;
    logic [63:0] y;
    logic [63:0] satp;
    logic        got_satp;
    logic [63:0] mva [$];
    logic [63:0] mpa [$];
    setup("img");
    fd = $fopen(f, "r");
    if (fd == 0) $fatal(1, "tb_ptw: cannot open the image %s", f);
    got_satp = 1'b0;
    satp     = '0;
    nw       = 0;
    while (!$feof(fd)) begin
      line = "";
      r = $fgets(line, fd);
      if (r == 0) break;
      if ((line.len() == 0) || (line[0] == "#") || (line[0] == "\n"))
        continue;
      key = "";
      x   = '0;
      y   = '0;
      // The key first, then the fields its kind has.
      n   = $sscanf(line, "%s", key);
      if (key == "satp") n = $sscanf(line, "%s %h", key, x) + 1;
      else               n = $sscanf(line, "%s %h %h", key, x, y);
      if ((key == "satp") && (n == 3)) begin
        satp     = x;
        got_satp = 1'b1;
      end else if ((key == "map") && (n == 3)) begin
        mva.push_back(x);
        mpa.push_back(y);
      end else if ((key == "word") && (n == 3)) begin
        if ((x >> PA_WIDTH) != 64'd0)
          $fatal(1, "tb_ptw: image word at %016h beyond PA_WIDTH", x);
        wrw(PW'(x), y);
        nw++;
      end else begin
        $fatal(1, "tb_ptw: image %s: a line not satp, map or word: %s", f,
               line);
      end
    end
    $fclose(fd);
    $display("tb_ptw: image %s: satp %016h, %0d map lines, %0d words", f,
             satp, mva.size(), nw);
    chk("img: one satp line, MODE Sv57, ASID 0",
        got_satp && (satp[63:60] == M_57) && (satp[59:44] == 16'd0));
    chk("img: map lines", mva.size() > 0);
    cs_satp_mode(satp[63:60]);
    cs_satp_ppn(PNW'(satp[43:0]));
    req_priv = PRV_U;
    foreach (mva[i]) begin
      tname = $sformatf("img %016h", mva[i]);
      walk(1'b0, VW'(mva[i] >> 12), ACC_X);
      exp_hit(tname, PNW'(mpa[i] >> 12), SZ_4K, 2'd0);
      chk($sformatf("%s: perm %02h exp %02h", tname, r_perm, F_IMG),
          r_perm == F_IMG);
      chk($sformatf("%s: five reads, no CAS (%0d, %0d)", tname, n_acc,
                    n_cas), (n_acc == 5) && (n_cas == 0));
      n_acc = 0;
      n_cas = 0;
    end
  endtask

  // The end of a run: the totals, then $fatal on a failure, else $finish.
  task automatic report();
    $display("tb_ptw: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ptw: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  endtask

  // =================================================================
  // BP-149: with +IMG the image check runs alone, reports and waits for
  // the end of the simulation. The test list stays at the top level of
  // the block, not inside a branch: inside one, Verilator emitted the
  // whole list as one C++ function, which gcc took over 30 minutes to
  // compile.
  initial begin
    string imgf;
    pass_cnt = 0;
    fail_cnt = 0;
    n_rsp    = 0;
    cyc      = 0;
    rstn     = 1'b0;
    knob_read();
    if ($value$plusargs("IMG=%s", imgf)) begin
      t_img(imgf);
      report();
      forever @(posedge clk);
    end
    t_s_4k();
    t_s_super();
    t_s_napot();
    t_s_pbmt();
    t_s_pf();
    t_s_ad();
    t_s_access();
    t_s_timing();
    t_h_basic();
    t_h_size();
    t_h_faults();
    t_h_ad();
    t_leaf_checks();
    t_causes();
    t_wide();
    t_bld();
    t_m_a();
    t_m_b();
    t_m_c();
    t_m_d();
    t_m_e();
    t_m_f();
    t_m_g();
    t_m_h();
    t_m_i();
    t_m_j();
    t_m_bp147_d();
    t_m_bp147_e();
    t_m_k();
    report();
  end

  initial begin
    #5000000;
    $fatal(1, "tb_ptw: timeout");
  end

endmodule : tb
