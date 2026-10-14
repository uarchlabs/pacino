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
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;
import csr_pkg::*;

module tb;

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

  // Write the three-level Sv39 path for vpn, tables at t2 (root), t1,
  // t0, leaf PTE at level 0.
  task automatic path3(input logic [PA_WIDTH-1:0] t2,
                       input logic [PA_WIDTH-1:0] t1,
                       input logic [PA_WIDTH-1:0] t0,
                       input logic [26:0] vpn,
                       input logic [63:0] leaf);
    wrw(t2 + 36'(8 * vpn[26:18]), pte(44'(t1 >> 12), F_PTR));
    wrw(t1 + 36'(8 * vpn[17:9]),  pte(44'(t0 >> 12), F_PTR));
    wrw(t0 + 36'(8 * vpn[8:0]),   leaf);
  endtask

  // The G-stage path for a guest page (Sv39x4: an 11-bit root index).
  task automatic gpath3(input logic [PA_WIDTH-1:0] t2,
                        input logic [PA_WIDTH-1:0] t1,
                        input logic [PA_WIDTH-1:0] t0,
                        input logic [28:0] gpn,
                        input logic [63:0] leaf);
    wrw(t2 + 36'(8 * gpn[28:18]), pte(44'(t1 >> 12), F_PTR));
    wrw(t1 + 36'(8 * gpn[17:9]),  pte(44'(t0 >> 12), F_PTR));
    wrw(t0 + 36'(8 * gpn[8:0]),   leaf);
  endtask

  // =================================================================
  // Reset to a known state, and one walk.
  // =================================================================
  // ---- the CSR group (SYS-001) ------------------------------------------
  // Each task changes one field by a read-modify-write through
  // csr_tb_pkg (the CSR-5 rules apply) and drives ptw_csr again.
  task automatic cs_sync();
    ptw_csr = csr_tb_pkg::pack_ptw_csr();
  endtask
  task automatic cs_satp_mode(input logic [3:0] m);
    satp_t r;
    r = satp_t'(csr_tb_pkg::csr_read(CSR_SATP_ADDR)); r.mode = m;
    csr_tb_pkg::csr_write(CSR_SATP_ADDR, 64'(r)); cs_sync();
  endtask
  task automatic cs_satp_ppn(input logic [PPN_WIDTH-1:0] n);
    satp_t r;
    r = satp_t'(csr_tb_pkg::csr_read(CSR_SATP_ADDR)); r.ppn = 44'(n);
    csr_tb_pkg::csr_write(CSR_SATP_ADDR, 64'(r)); cs_sync();
  endtask
  task automatic cs_vsatp_mode(input logic [3:0] m);
    vsatp_t r;
    r = vsatp_t'(csr_tb_pkg::csr_read(CSR_VSATP_ADDR)); r.mode = m;
    csr_tb_pkg::csr_write(CSR_VSATP_ADDR, 64'(r)); cs_sync();
  endtask
  task automatic cs_vsatp_ppn(input logic [GPA_WIDTH-13:0] n);
    vsatp_t r;
    r = vsatp_t'(csr_tb_pkg::csr_read(CSR_VSATP_ADDR)); r.ppn = 44'(n);
    csr_tb_pkg::csr_write(CSR_VSATP_ADDR, 64'(r)); cs_sync();
  endtask
  // hgatp.MODE: MODE_SV39 (8) is Sv39x4 in hgatp.
  task automatic cs_hgatp_mode(input logic [3:0] m);
    hgatp_t r;
    r = hgatp_t'(csr_tb_pkg::csr_read(CSR_HGATP_ADDR)); r.mode = m;
    csr_tb_pkg::csr_write(CSR_HGATP_ADDR, 64'(r)); cs_sync();
  endtask
  task automatic cs_hgatp_ppn(input logic [PPN_WIDTH-1:0] n);
    hgatp_t r;
    r = hgatp_t'(csr_tb_pkg::csr_read(CSR_HGATP_ADDR)); r.ppn = 44'(n);
    csr_tb_pkg::csr_write(CSR_HGATP_ADDR, 64'(r)); cs_sync();
  endtask
  task automatic cs_menvcfg_adue(input logic b);
    menvcfg_t r;
    r = menvcfg_t'(csr_tb_pkg::csr_read(CSR_MENVCFG_ADDR)); r.adue = b;
    csr_tb_pkg::csr_write(CSR_MENVCFG_ADDR, 64'(r)); cs_sync();
  endtask
  task automatic cs_menvcfg_pbmte(input logic b);
    menvcfg_t r;
    r = menvcfg_t'(csr_tb_pkg::csr_read(CSR_MENVCFG_ADDR)); r.pbmte = b;
    csr_tb_pkg::csr_write(CSR_MENVCFG_ADDR, 64'(r)); cs_sync();
  endtask
  task automatic cs_henvcfg_adue(input logic b);
    henvcfg_t r;
    r = henvcfg_t'(csr_tb_pkg::csr_read(CSR_HENVCFG_ADDR)); r.adue = b;
    csr_tb_pkg::csr_write(CSR_HENVCFG_ADDR, 64'(r)); cs_sync();
  endtask
  task automatic cs_henvcfg_pbmte(input logic b);
    henvcfg_t r;
    r = henvcfg_t'(csr_tb_pkg::csr_read(CSR_HENVCFG_ADDR)); r.pbmte = b;
    csr_tb_pkg::csr_write(CSR_HENVCFG_ADDR, 64'(r)); cs_sync();
  endtask
  // pmpcfg byte k, by read-modify-write of pmpcfg0 or pmpcfg2.
  task automatic cs_pmpcfg(input int k, input logic [7:0] b);
    logic [11:0] ca;
    pmpcfg_t     c;
    ca = (k < 8) ? CSR_PMPCFG0_ADDR : CSR_PMPCFG2_ADDR;
    c  = pmpcfg_t'(csr_tb_pkg::csr_read(ca));
    c.ent[k % 8] = pmpcfg_ent_t'(b);
    csr_tb_pkg::csr_write(ca, 64'(c)); cs_sync();
  endtask
  task automatic cs_pmpaddr(input int k, input pmpaddr_imp_t a);
    csr_tb_pkg::csr_write(CSR_PMPADDR0_ADDR + 12'(k), 64'(a)); cs_sync();
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
    // testbench's satp: Sv39, root 0x8100_0000.
    csr_tb_pkg::csr_reset();
    cs_satp_mode(MODE_SV39);
    cs_satp_ppn(PPN_WIDTH'(36'h0_8100_0000 >> 12));
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

  task automatic walk(input logic v, input logic [28:0] vpn,
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

  // A guest-page fault whose GPA fits GPA_WIDTH, zero-extended.
  task automatic exp_gpf41(input string nm,
                           input logic [GPA_WIDTH-1:0] gpa,
                           input logic [1:0] imp);
    exp_gpf(nm, FAULT_GPA_WIDTH'(gpa), imp);
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
  localparam logic [PA_WIDTH-1:0] T2 = 36'h0_8100_0000;
  localparam logic [PA_WIDTH-1:0] T1 = 36'h0_8100_1000;
  localparam logic [PA_WIDTH-1:0] T0 = 36'h0_8100_2000;
  localparam logic [26:0]         VA = 27'h012_3456;

  task automatic t_s_4k();
    setup("s_4k");
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RXAD));
    walk(1'b0, 29'(VA), ACC_X);
    exp_hit("4k", 24'h8_2345, SZ_4K, 2'd0);
    chk("4k: perm is the leaf's low byte", r_perm == F_RXAD);
    chk($sformatf("4k: three reads (%0d)", n_acc), n_acc == 3);
    chk("4k: root PTE address", acc_pa[0] == T2 + 36'(8 * VA[26:18]));
    chk("4k: level 1 PTE address", acc_pa[1] == T1 + 36'(8 * VA[17:9]));
    chk("4k: level 0 PTE address", acc_pa[2] == T0 + 36'(8 * VA[8:0]));
    chk("4k: all reads", !acc_op[0] && !acc_op[1] && !acc_op[2]);
  endtask

  task automatic t_s_super();
    setup("s_2m");
    wrw(T2 + 36'(8 * VA[26:18]), pte(44'(T1 >> 12), F_PTR));
    wrw(T1 + 36'(8 * VA[17:9]),  pte(44'h8_2200, F_RXAD));
    walk(1'b0, 29'(VA), ACC_X);
    exp_hit("2m", 24'h8_2200, SZ_2M, 2'd0);
    chk("2m: two reads", n_acc == 2);

    setup("s_1g");
    wrw(T2 + 36'(8 * VA[26:18]), pte(44'h8_0000, F_RXAD));
    walk(1'b0, 29'(VA), ACC_X);
    exp_hit("1g", 24'h8_0000, SZ_1G, 2'd0);

    setup("s_2m_misaligned");
    wrw(T2 + 36'(8 * VA[26:18]), pte(44'(T1 >> 12), F_PTR));
    wrw(T1 + 36'(8 * VA[17:9]),  pte(44'h8_2201, F_RXAD));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("misaligned 2m", 12);

    setup("s_1g_misaligned");
    wrw(T2 + 36'(8 * VA[26:18]), pte(44'h8_0200, F_RXAD));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("misaligned 1g", 12);
  endtask

  // Svnapot: the one defined encoding and every reserved one.
  task automatic t_s_napot();
    logic [3:0] lo;
    setup("s_napot_64k");
    path3(T2, T1, T0, VA, pte_x(44'h8_2348, F_RXAD, 2'd0, 1'b1));
    walk(1'b0, 29'(VA), ACC_X);
    exp_hit("napot 64k", 24'h8_2348, SZ_64K, 2'd0);
    for (int k = 0; k < 16; k++) begin
      lo = 4'(k);
      if (lo == 4'b1000) continue;
      setup($sformatf("s_napot_rsv_%0h", lo));
      path3(T2, T1, T0, VA, pte_x({40'h8_234, lo}, F_RXAD, 2'd0, 1'b1));
      walk(1'b0, 29'(VA), ACC_X);
      exp_flt("reserved N encoding", 12);
    end
    setup("s_napot_on_2m");
    wrw(T2 + 36'(8 * VA[26:18]), pte(44'(T1 >> 12), F_PTR));
    wrw(T1 + 36'(8 * VA[17:9]),  pte_x(44'h8_2208, F_RXAD, 2'd0, 1'b1));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("N on a superpage", 12);
    setup("s_napot_nonleaf");
    wrw(T2 + 36'(8 * VA[26:18]), pte_x(44'(T1 >> 12), F_PTR, 2'd0, 1'b1));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("N on a non-leaf", 12);
  endtask

  // Svpbmt.
  task automatic t_s_pbmt();
    for (int p = 1; p < 3; p++) begin
      setup($sformatf("s_pbmt_%0d", p));
      path3(T2, T1, T0, VA, pte_x(44'h8_2345, F_RXAD, 2'(p), 1'b0));
      walk(1'b0, 29'(VA), ACC_X);
      exp_hit("pbmt", 24'h8_2345, SZ_4K, 2'(p));
    end
    setup("s_pbmt_rsv");
    path3(T2, T1, T0, VA, pte_x(44'h8_2345, F_RXAD, 2'd3, 1'b0));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("PBMT 3", 12);
    setup("s_pbmte_clear");
    cs_menvcfg_pbmte(1'b0);
    path3(T2, T1, T0, VA, pte_x(44'h8_2345, F_RXAD, 2'd1, 1'b0));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("PBMT with menvcfg.PBMTE clear", 12);
    setup("s_pbmte_clear_zero");
    cs_menvcfg_pbmte(1'b0);
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RXAD));
    walk(1'b0, 29'(VA), ACC_X);
    exp_hit("PBMT 0 with PBMTE clear", 24'h8_2345, SZ_4K, 2'd0);
    setup("s_pbmt_nonleaf");
    wrw(T2 + 36'(8 * VA[26:18]), pte_x(44'(T1 >> 12), F_PTR, 2'd1, 1'b0));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("PBMT on a non-leaf", 12);
  endtask

  // The other page faults.
  task automatic t_s_pf();
    setup("s_invalid");
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("V clear at the root", 12);
    setup("s_w_no_r");
    path3(T2, T1, T0, VA, pte(44'h8_2345, 8'hC5));   // V W, R clear
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("W without R", 12);
    setup("s_rsv_bits");
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RXAD) | (64'd1 << 54));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("bits 60:54", 12);
    setup("s_nonleaf_l0");
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_PTR));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("non-leaf at level 0", 12);
    setup("s_nonleaf_a");
    wrw(T2 + 36'(8 * VA[26:18]), pte(44'(T1 >> 12), 8'h41));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("A on a non-leaf", 12);
    setup("s_no_x");
    path3(T2, T1, T0, VA, pte(44'h8_2345, 8'hC3));   // V R A D
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("fetch from a leaf without X", 12);
  endtask

  // Svade and Svadu, single stage, with the D update a store needs.
  task automatic t_s_ad();
    logic [PA_WIDTH-1:0] la;
    la = T0 + 36'(8 * VA[8:0]);
    setup("s_svade");
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RX));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("Svade, A clear", 12);
    chk("Svade: no CAS", n_cas == 0);
    chk("Svade: PTE unchanged", rdw(la) == pte(44'h8_2345, F_RX));

    setup("s_svadu");
    cs_menvcfg_adue(1'b1);
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RX));
    walk(1'b0, 29'(VA), ACC_X);
    exp_hit("Svadu", 24'h8_2345, SZ_4K, 2'd0);
    chk("Svadu: one CAS, last", (n_cas == 1) && acc_op[3] && (n_acc == 4));
    chk("Svadu: the CAS is at the leaf", acc_pa[3] == la);
    chk("Svadu: memory holds A set, D clear",
        rdw(la) == pte(44'h8_2345, F_RXA));
    chk("Svadu: the response perm has A", r_perm == F_RXA);

    setup("s_svadu_store");
    cs_menvcfg_adue(1'b1);
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RWX));
    walk(1'b0, 29'(VA), ACC_W);
    exp_hit("store", 24'h8_2345, SZ_4K, 2'd0);
    chk("store: A and D set in memory", rdw(la) == pte(44'h8_2345, 8'hCF));
    setup("s_svadu_store_dset");
    cs_menvcfg_adue(1'b1);
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RWXA));
    walk(1'b0, 29'(VA), ACC_W);
    exp_hit("store, D only", 24'h8_2345, SZ_4K, 2'd0);
    chk("store: D set", rdw(la) == pte(44'h8_2345, 8'hCF));
    setup("s_svade_store");
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RWXA));
    walk(1'b0, 29'(VA), ACC_W);
    exp_flt("Svade store, D clear", 15);         // MMU-24c
    setup("s_store_no_w");
    cs_menvcfg_adue(1'b1);
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RX));
    walk(1'b0, 29'(VA), ACC_W);
    exp_flt("store to a page without W", 15);    // MMU-24c
    chk("store without W: no CAS", n_cas == 0);

    // WM-11: memory changes the PTE before the CAS; the walk restarts
    // and reads the new PTE.
    setup("s_cas_mismatch");
    cs_menvcfg_adue(1'b1);
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RX));
    chg_at  = 0;
    chg_val = pte(44'h8_6789, F_RXAD);
    walk(1'b0, 29'(VA), ACC_X);
    exp_hit("restart after mismatch", 24'h8_6789, SZ_4K, 2'd0);
    chk($sformatf("mismatch: 3 reads, CAS, 3 reads (%0d)", n_acc),
        (n_acc == 7) && (n_cas == 1));
    chk("mismatch: memory keeps the other agent's value",
        rdw(la) == pte(44'h8_6789, F_RXAD));
  endtask

  // Access faults, cause 1.
  task automatic t_s_access();
    // PMP: entry 0 covers the table page T0 with no read (NAPOT 4 KiB),
    // entry 1 everything else.
    setup("s_pmp_read");
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RXAD));
    cs_pmpcfg(0, 8'h18);                      // NAPOT, no R W X
    cs_pmpaddr(0, 34'((T0 >> 2) | 36'h1FF));
    cs_pmpcfg(1, 8'h1F);
    cs_pmpaddr(1, '1);
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("PMP on a PTE read", 1);
    chk("PMP read: the denied read is never presented", n_acc == 2);

    setup("s_pmp_cas");
    cs_menvcfg_adue(1'b1);
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RX));
    cs_pmpcfg(0, 8'h19);                      // NAPOT, R only
    cs_pmpaddr(0, 34'((T0 >> 2) | 36'h1FF));
    cs_pmpcfg(1, 8'h1F);
    cs_pmpaddr(1, '1);
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("PMP on the Svadu write", 1);
    chk("PMP write: no CAS presented", (n_cas == 0) && (n_acc == 3));

    setup("s_pt_not_cc");
    cs_satp_ppn(PPN_WIDTH'(36'h0_4000_0000 >> 12));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("page table outside cacheable coherent memory", 1);
    chk("not cacheable: nothing presented", n_acc == 0);

    setup("s_ppn_wide_nonleaf");
    wrw(T2 + 36'(8 * VA[26:18]), pte(44'h100_0000 | 44'(T1 >> 12), F_PTR));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("non-leaf PPN above bit 23", 1);
    chk("wide non-leaf: one read", n_acc == 1);

    setup("s_ppn_wide_leaf");
    path3(T2, T1, T0, VA, pte(44'h800_0000_0123, F_RXAD));
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("leaf PPN above bit 23", 1);

    setup("s_err_read");
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RXAD));
    err_at = 1;
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("memory error on a read", 1);
    chk("read error: the walk stops", n_acc == 2);

    setup("s_err_cas");
    cs_menvcfg_adue(1'b1);
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RX));
    err_at = 3;
    walk(1'b0, 29'(VA), ACC_X);
    exp_flt("memory error on the CAS", 1);
    chk("CAS error: nothing stored",
        rdw(T0 + 36'(8 * VA[8:0])) == pte(44'h8_2345, F_RX));
  endtask

  // WM-13 and IL-6.
  task automatic t_s_timing();
    setup("s_slow");
    lat_min = 1;
    lat_max = 9;
    rdy_pat = 3;
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RXAD));
    walk(1'b0, 29'(VA), ACC_X);
    exp_hit("slow memory", 24'h8_2345, SZ_4K, 2'd0);

    // A second request while a walk is in progress is answered retry.
    setup("s_retry");
    lat_min = 6;
    lat_max = 6;
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_RXAD));
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
      itlb_l2t_vpn     = 29'(VA);
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
      chk("retry: one walk's accesses", n_acc == 3);
    end
  endtask

  // =================================================================
  // Two-stage tests. VS tables in guest physical memory at GPA
  // VT2/VT1/VT0, mapped by the G-stage to SPA via G tables at G2/G1/G0.
  // =================================================================
  localparam logic [PA_WIDTH-1:0] G2 = 36'h0_8200_0000;  // 16 KiB root
  localparam logic [PA_WIDTH-1:0] G1 = 36'h0_8200_4000;
  localparam logic [PA_WIDTH-1:0] G0 = 36'h0_8200_5000;
  localparam logic [PA_WIDTH-1:0] G1B = 36'h0_8200_6000;
  localparam logic [PA_WIDTH-1:0] G0B = 36'h0_8200_7000;
  // Guest pages of the VS tables, and their supervisor pages.
  localparam logic [28:0] GP_VT2 = 29'h0_0040;   // GPA 0x40000
  localparam logic [28:0] GP_VT1 = 29'h0_0041;
  localparam logic [28:0] GP_VT0 = 29'h0_0042;
  localparam logic [PA_WIDTH-1:0] SP_VT2 = 36'h0_8300_0000;
  localparam logic [PA_WIDTH-1:0] SP_VT1 = 36'h0_8300_1000;
  localparam logic [PA_WIDTH-1:0] SP_VT0 = 36'h0_8300_2000;
  // The fetch's guest page and its supervisor page.
  localparam logic [28:0] GP_CODE = 29'h0_0123;
  localparam logic [23:0] SP_CODE = 24'h8_4567;

  task automatic setup2(input string nm);
    setup(nm);
    cs_satp_mode(MODE_BARE);
    cs_vsatp_mode(MODE_SV39);
    cs_vsatp_ppn(GP_VT2);
    cs_hgatp_mode(MODE_SV39);            // Sv39x4
    cs_hgatp_ppn(PPN_WIDTH'(G2 >> 12));
    gt_next            = 36'h0_8201_0000;
    // The G-stage maps the three VS table pages (one level-0 table:
    // they share GPA bits 40:21) and the code page.
    gpath3(G2, G1, G0, GP_VT2, pte(44'(SP_VT2 >> 12), F_URWXAD));
    wrw(G0 + 36'(8 * GP_VT1[8:0]), pte(44'(SP_VT1 >> 12), F_URWXAD));
    wrw(G0 + 36'(8 * GP_VT0[8:0]), pte(44'(SP_VT0 >> 12), F_URWXAD));
    wrw(G0 + 36'(8 * GP_CODE[8:0]), pte(44'(SP_CODE), F_URWXAD));
  endtask

  // Map one guest page in the G-stage tables rooted at G2, allocating
  // level-1 and level-0 tables as needed (from GT_NEXT up), so a test
  // mapping never overwrites a path setup2 wrote.
  logic [PA_WIDTH-1:0] gt_next;
  task automatic gmap(input logic [28:0] gpn, input logic [63:0] leaf);
    logic [PA_WIDTH-1:0] t;
    logic [63:0]         e;
    logic [10:0]         ix [0:2];
    ix[2] = gpn[28:18];
    ix[1] = {2'b00, gpn[17:9]};
    ix[0] = {2'b00, gpn[8:0]};
    t = G2;
    for (int l = 2; l > 0; l--) begin
      e = rdw(t + 36'(8 * ix[l]));
      if (!e[0]) begin
        e = pte(44'(gt_next >> 12), F_PTR);
        wrw(t + 36'(8 * ix[l]), e);
        gt_next = gt_next + 36'h1000;
      end
      t = 36'(e[53:10]) << 12;
    end
    wrw(t + 36'(8 * ix[0]), leaf);
  endtask

  // The VS path for VA, in the VS tables' supervisor pages.
  task automatic vspath(input logic [63:0] leaf);
    wrw(SP_VT2 + 36'(8 * VA[26:18]), pte(44'(GP_VT1), F_PTR));
    wrw(SP_VT1 + 36'(8 * VA[17:9]),  pte(44'(GP_VT0), F_PTR));
    wrw(SP_VT0 + 36'(8 * VA[8:0]),   leaf);
  endtask

  task automatic t_h_basic();
    setup2("h_4k_4k");
    vspath(pte(44'(GP_CODE), F_RXAD));
    walk(1'b1, 29'(VA), ACC_X);
    exp_hit("nested 4k/4k", SP_CODE, SZ_4K, 2'd0);
    chk("nested: perm is the VS leaf's", r_perm == F_RXAD);
    chk($sformatf("nested: 4 G walks of 3 plus 3 VS reads (%0d)", n_acc),
        n_acc == 15);
    chk("nested: first access is the G root for the VS root's GPA",
        acc_pa[0] == G2 + 36'(8 * GP_VT2[28:18]));
    chk("nested: fourth access is the VS root PTE",
        acc_pa[3] == SP_VT2 + 36'(8 * VA[26:18]));

    // G-stage only: vsatp Bare, the request page is the GPA.
    setup2("h_g_only");
    cs_vsatp_mode(MODE_BARE);
    walk(1'b1, 29'(GP_CODE), ACC_X);
    exp_hit("G only", SP_CODE, SZ_4K, 2'd0);
    chk("G only: perm is the G leaf's without G", r_perm == (F_URWXAD & 8'hDF));
    chk("G only: three reads", n_acc == 3);

    // VS-stage only: hgatp Bare, GPA = SPA.
    setup2("h_vs_only");
    cs_hgatp_mode(MODE_BARE);
    cs_vsatp_ppn(29'(SP_VT2 >> 12));
    wrw(SP_VT2 + 36'(8 * VA[26:18]), pte(44'(SP_VT1 >> 12), F_PTR));
    wrw(SP_VT1 + 36'(8 * VA[17:9]),  pte(44'(SP_VT0 >> 12), F_PTR));
    wrw(SP_VT0 + 36'(8 * VA[8:0]),   pte(44'(SP_CODE), F_RXAD));
    walk(1'b1, 29'(VA), ACC_X);
    exp_hit("VS only", SP_CODE, SZ_4K, 2'd0);
    chk("VS only: three reads", n_acc == 3);

    // The G-only regime with a GPA using bits 40:39 (FE-19).
    setup2("h_g_only_high");
    cs_vsatp_mode(MODE_BARE);
    gmap(29'h1FF_0123, pte(44'h8_4444, F_URXA));
    walk(1'b1, 29'h1FF_0123, ACC_X);
    exp_hit("G only, GPA bit 40", 24'h8_4444, SZ_4K, 2'd0);
  endtask

  // MMU-27, sizes, and NAPOT at each stage.
  task automatic t_h_size();
    // VS 2 MiB, G 4 KiB -> 4 KiB.
    setup2("h_vs2m_g4k");
    wrw(SP_VT2 + 36'(8 * VA[26:18]), pte(44'(GP_VT1), F_PTR));
    // VS 2 MiB leaf at guest page 0x200 aligned: GPA page = 0x200 + VA[8:0]
    wrw(SP_VT1 + 36'(8 * VA[17:9]), pte(44'h200, F_RXAD));
    gmap(29'h200 | 29'(VA[8:0]), pte(44'h8_5555, F_URXA));
    walk(1'b1, 29'(VA), ACC_X);
    exp_hit("VS 2M over G 4K", 24'h8_5555, SZ_4K, 2'd0);

    // VS 4 KiB, G 1 GiB -> 4 KiB; the SPA is the G superpage plus GPA
    // bits.
    setup2("h_vs4k_g1g");
    vspath(pte(44'h4_0123, F_RXAD));                 // GPA page 0x40123
    // G root index for 0x40123 is 1 (bits 28:18 of the page).
    wrw(G2 + 36'(8 * 11'h1), pte(44'h8_0000 | 44'h4_0000, F_URXA));
    walk(1'b1, 29'(VA), ACC_X);
    exp_hit("VS 4K over G 1G", 24'hC_0123, SZ_4K, 2'd0);

    // VS 1 GiB, G 2 MiB -> 2 MiB.
    setup2("h_vs1g_g2m");
    wrw(SP_VT2 + 36'(8 * VA[26:18]), pte(44'h8_0000, F_RXAD)); // GPA 2 GiB
    begin
      logic [28:0] gp;
      gp = 29'h8_0000 | 29'(VA[17:0]);
      wrw(G2 + 36'(8 * gp[28:18]), pte(44'(G1B >> 12), F_PTR));
      wrw(G1B + 36'(8 * gp[17:9]), pte(44'h9_0000, F_URXA));
      walk(1'b1, 29'(VA), ACC_X);
      exp_hit("VS 1G over G 2M", 24'h9_0000 | 24'(VA[8:0]), SZ_2M, 2'd0);
    end

    // NAPOT at the G-stage, VS 2 MiB above it -> 64 KiB.
    setup2("h_g_napot");
    wrw(SP_VT2 + 36'(8 * VA[26:18]), pte(44'(GP_VT1), F_PTR));
    wrw(SP_VT1 + 36'(8 * VA[17:9]), pte(44'h200, F_RXAD));
    begin
      logic [28:0] gp;
      gp = 29'h200 | 29'(VA[8:0]);
      gmap(gp,
             pte_x(44'h8_6608, F_URXA, 2'd0, 1'b1));
      walk(1'b1, 29'(VA), ACC_X);
      exp_hit("G NAPOT under VS 2M", 24'h8_6600 | 24'(gp[3:0]), SZ_64K,
              2'd0);
    end

    // NAPOT at the VS-stage, G 4 KiB -> 4 KiB, PA page from GPA[15:12].
    setup2("h_vs_napot");
    vspath(pte_x(44'h0128, F_RXAD, 2'd0, 1'b1));
    begin
      logic [28:0] gp;
      gp = 29'h0120 | 29'(VA[3:0]);
      gmap(gp, pte(44'h8_7777, F_URXA));
      walk(1'b1, 29'(VA), ACC_X);
      exp_hit("VS NAPOT over G 4K", 24'h8_7777, SZ_4K, 2'd0);
    end

    // NAPOT at both stages -> 64 KiB.
    setup2("h_both_napot");
    vspath(pte_x(44'h0128, F_RXAD, 2'd0, 1'b1));
    begin
      logic [28:0] gp;
      gp = 29'h0120 | 29'(VA[3:0]);
      gmap(gp, pte_x(44'h8_7708, F_URXA, 2'd0, 1'b1));
      walk(1'b1, 29'(VA), ACC_X);
      exp_hit("NAPOT both", 24'h8_7700 | 24'(VA[3:0]), SZ_64K, 2'd0);
    end

    // Reserved N at the G-stage.
    setup2("h_g_napot_rsv");
    vspath(pte(44'(GP_CODE), F_RXAD));
    wrw(G0 + 36'(8 * GP_CODE[8:0]), pte_x(44'h8_4564, F_URXA, 2'd0, 1'b1));
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf41("reserved N at the G-stage", {GP_CODE, 12'h000}, 2'b00);
  endtask

  // Guest-page faults of each kind, PBMT, U and the GPA width.
  task automatic t_h_faults();
    setup2("h_gpf_fetch");
    vspath(pte(44'(GP_CODE), F_RXAD));
    wrw(G0 + 36'(8 * GP_CODE[8:0]), 64'd0);
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf41("unmapped final GPA", {GP_CODE, 12'h000}, 2'b00);

    setup2("h_gpf_read");
    vspath(pte(44'(GP_CODE), F_RXAD));
    wrw(G0 + 36'(8 * GP_VT1[8:0]), 64'd0);           // VS level-1 table
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf41("unmapped VS table page", {GP_VT1, 12'h000} +
            41'(8 * VA[17:9]), 2'b01);

    setup2("h_gpf_write");
    cs_henvcfg_adue(1'b1);
    cs_menvcfg_adue(1'b1);
    vspath(pte(44'(GP_CODE), F_RX));                 // VS A clear
    wrw(G0 + 36'(8 * GP_VT0[8:0]), pte(44'(SP_VT0 >> 12), F_URXA)); // no W
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf41("G leaf without W for the VS update",
            {GP_VT0, 12'h000} + 41'(8 * VA[8:0]), 2'b10);
    chk("no W: VS PTE unchanged",
        rdw(SP_VT0 + 36'(8 * VA[8:0])) == pte(44'(GP_CODE), F_RX));

    setup2("h_g_no_u");
    vspath(pte(44'(GP_CODE), F_RXAD));
    wrw(G0 + 36'(8 * GP_CODE[8:0]), pte(44'(SP_CODE), F_RXAD));  // U clear
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf41("G leaf with U clear", {GP_CODE, 12'h000}, 2'b00);

    setup2("h_g_no_x");
    vspath(pte(44'(GP_CODE), F_RXAD));
    wrw(G0 + 36'(8 * GP_CODE[8:0]), pte(44'(SP_CODE), 8'hD3)); // U R A D
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf41("G leaf without X for the fetch", {GP_CODE, 12'h000}, 2'b00);

    // MMU-23 (BP-124): a GPA above bit 40 is returned whole. MMU-30's
    // zero is withdrawn. Kind 00: the leaf's page, bits 11:0 zero.
    setup2("h_gpa_wide_leaf");
    vspath(pte(44'h2000_0123, F_RXAD));              // GPA bit 41
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf("VS leaf GPA above bit 40", {44'h2000_0123, 12'h000}, 2'b00);

    setup2("h_gpa_bit55_leaf");
    vspath(pte(44'h800_0000_0123, F_RXAD));          // GPA bit 55
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf("VS leaf GPA bit 55", {44'h800_0000_0123, 12'h000}, 2'b00);
    chk("bit 55 leaf: the GPA's bit 55 is set", r_gpa[55]);

    // Kind 01: the GPA of the VS PTE the next level would read.
    setup2("h_gpa_wide_nonleaf");
    wrw(SP_VT2 + 36'(8 * VA[26:18]), pte(44'h2000_0041, F_PTR));
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf("VS non-leaf GPA above bit 40",
            {44'h2000_0041, 12'h000} + 56'(8 * VA[17:9]), 2'b01);

    setup2("h_gpa_bit55_nonleaf");
    wrw(SP_VT2 + 36'(8 * VA[26:18]), pte(44'h800_0000_0041, F_PTR));
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf("VS non-leaf GPA bit 55",
            {44'h800_0000_0041, 12'h000} + 56'(8 * VA[17:9]), 2'b01);
    chk("bit 55 non-leaf: the GPA's bit 55 is set", r_gpa[55]);

    // The same at level 1: the GPA indexes with VA[8:0].
    setup2("h_gpa_bit55_nonleaf_l1");
    wrw(SP_VT2 + 36'(8 * VA[26:18]), pte(44'(GP_VT1), F_PTR));
    wrw(SP_VT1 + 36'(8 * VA[17:9]),  pte(44'h800_0000_0042, F_PTR));
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf("VS level-1 non-leaf GPA bit 55",
            {44'h800_0000_0042, 12'h000} + 56'(8 * VA[8:0]), 2'b01);

    setup2("h_g_ppn_wide");
    vspath(pte(44'(GP_CODE), F_RXAD));
    wrw(G0 + 36'(8 * GP_CODE[8:0]), pte(44'h100_0000 | 44'(SP_CODE), F_URXA));
    walk(1'b1, 29'(VA), ACC_X);
    exp_flt("G leaf PPN above bit 23", 1);

    setup2("h_vs_pbmte");
    cs_henvcfg_pbmte(1'b0);                    // menvcfg's stays set
    vspath(pte_x(44'(GP_CODE), F_RXAD, 2'd1, 1'b0));
    walk(1'b1, 29'(VA), ACC_X);
    exp_flt("VS PBMT with henvcfg.PBMTE clear", 12);

    // menvcfg.PBMTE clear. henvcfg.PBMTE stays written 1 but reads 0
    // while menvcfg.PBMTE is 0 (csr_decisions.md CSR-5, SYS-002), so
    // the walker sees both clear; until SYS-002 it was given henvcfg's
    // 1. The VS leaf's PBMT is 0, so the result is the same either way.
    setup2("h_g_pbmte");
    cs_menvcfg_pbmte(1'b0);
    chk("g pbmte: henvcfg.PBMTE reads 0", ptw_csr.henvcfg_pbmte == 1'b0);
    vspath(pte(44'(GP_CODE), F_RXAD));
    wrw(G0 + 36'(8 * GP_CODE[8:0]), pte_x(44'(SP_CODE), F_URXA, 2'd2, 1'b0));
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf41("G PBMT with menvcfg.PBMTE clear", {GP_CODE, 12'h000}, 2'b00);

    setup2("h_g_pbmt_rsv");
    vspath(pte(44'(GP_CODE), F_RXAD));
    wrw(G0 + 36'(8 * GP_CODE[8:0]), pte_x(44'(SP_CODE), F_URXA, 2'd3, 1'b0));
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf41("G PBMT 3", {GP_CODE, 12'h000}, 2'b00);

    setup2("h_pbmt_max");
    vspath(pte_x(44'(GP_CODE), F_RXAD, 2'd1, 1'b0));         // NC
    wrw(G0 + 36'(8 * GP_CODE[8:0]), pte_x(44'(SP_CODE), F_URXA, 2'd2, 1'b0));
    walk(1'b1, 29'(VA), ACC_X);
    exp_hit("VS NC over G IO", SP_CODE, SZ_4K, 2'd2);
    setup2("h_pbmt_max2");
    vspath(pte_x(44'(GP_CODE), F_RXAD, 2'd2, 1'b0));         // IO
    wrw(G0 + 36'(8 * GP_CODE[8:0]), pte_x(44'(SP_CODE), F_URXA, 2'd1, 1'b0));
    walk(1'b1, 29'(VA), ACC_X);
    exp_hit("VS IO over G NC", SP_CODE, SZ_4K, 2'd2);

    setup2("h_err_g");
    vspath(pte(44'(GP_CODE), F_RXAD));
    err_at = 13;                                     // a final G read
    walk(1'b1, 29'(VA), ACC_X);
    exp_flt("memory error in a G-stage walk", 1);
  endtask

  // Svade and Svadu at each stage, chosen separately.
  task automatic t_h_ad();
    logic [PA_WIDTH-1:0] vl;
    logic [PA_WIDTH-1:0] gl;
    vl = SP_VT0 + 36'(8 * VA[8:0]);
    gl = G0 + 36'(8 * GP_VT0[8:0]);

    // henvcfg.ADUE set, menvcfg.ADUE set: the VS update writes through
    // the G-stage and sets the G leaf's D.
    setup2("h_vs_upd_sets_g_d");
    cs_henvcfg_adue(1'b1);
    cs_menvcfg_adue(1'b1);
    vspath(pte(44'(GP_CODE), F_RX));
    wrw(gl, pte(44'(SP_VT0 >> 12), F_URWXA));        // D clear
    walk(1'b1, 29'(VA), ACC_X);
    exp_hit("VS update through the G-stage", SP_CODE, SZ_4K, 2'd0);
    chk("the VS leaf has A", rdw(vl) == pte(44'(GP_CODE), F_RXA));
    chk("the G leaf of the VS table page has D",
        rdw(gl) == pte(44'(SP_VT0 >> 12), F_URWXAD));
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
    vspath(pte(44'(GP_CODE), F_RX));
    wrw(gl, pte(44'(SP_VT0 >> 12), F_URWXA));
    walk(1'b1, 29'(VA), ACC_X);
    exp_flt("Svade at VS, henvcfg.ADUE read 0", 12);
    chk("h1 m0: no CAS", n_cas == 0);

    // henvcfg.ADUE clear, menvcfg.ADUE set: VS Svade faults on A, while
    // the G-stage updates its own A on the way.
    setup2("h_h0_m1");
    cs_henvcfg_adue(1'b0);
    cs_menvcfg_adue(1'b1);
    vspath(pte(44'(GP_CODE), F_RX));
    wrw(G0 + 36'(8 * GP_VT2[8:0]), pte(44'(SP_VT2 >> 12), F_URWX)); // A clear
    walk(1'b1, 29'(VA), ACC_X);
    exp_flt("Svade at VS, A clear", 12);
    chk("h0 m1: the G leaf got A", rdw(G0 + 36'(8 * GP_VT2[8:0])) ==
        pte(44'(SP_VT2 >> 12), F_URWXA));

    // Svade at the G-stage for the fetch's own GPA.
    setup2("h_g_svade");
    vspath(pte(44'(GP_CODE), F_RXAD));
    wrw(G0 + 36'(8 * GP_CODE[8:0]), pte(44'(SP_CODE), F_URX));
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf41("Svade at G, fetch", {GP_CODE, 12'h000}, 2'b00);

    // Svadu at the G-stage for the fetch's own GPA, with a mismatch.
    setup2("h_g_svadu_mismatch");
    cs_menvcfg_adue(1'b1);
    vspath(pte(44'(GP_CODE), F_RXAD));
    wrw(G0 + 36'(8 * GP_CODE[8:0]), pte(44'(SP_CODE), F_URX));
    chg_at  = 0;
    chg_val = pte(44'h8_9999, F_URXA);
    walk(1'b1, 29'(VA), ACC_X);
    exp_hit("G restart after mismatch", 24'h8_9999, SZ_4K, 2'd0);
    chk("G mismatch: one CAS", n_cas == 1);

    // VS mismatch: the whole translation restarts.
    setup2("h_vs_mismatch");
    cs_henvcfg_adue(1'b1);
    cs_menvcfg_adue(1'b1);
    vspath(pte(44'(GP_CODE), F_RX));
    chg_at  = 0;
    chg_val = pte(44'(GP_CODE), F_RXAD);
    walk(1'b1, 29'(VA), ACC_X);
    exp_hit("VS restart after mismatch", SP_CODE, SZ_4K, 2'd0);
    chk("VS mismatch: the restart walks again (31 accesses)", n_acc == 31);
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
    if (lvl == 2'd0) begin
      path3(T2, T1, T0, VA, leaf);
      la = T0 + 36'(8 * VA[8:0]);
    end else begin
      wrw(T2 + 36'(8 * VA[26:18]), pte(44'(T1 >> 12), F_PTR));
      wrw(T1 + 36'(8 * VA[17:9]), leaf);
      la = T1 + 36'(8 * VA[17:9]);
    end
    walk(1'b0, 29'(VA), acc);
    exp_flt(nm, CAUSE_WIDTH'(cause));
    chk({nm, ": no CAS"}, n_cas == 0);
    chk({nm, ": leaf unchanged"}, rdw(la) == leaf);
  endtask

  // A VS-stage leaf (nested, hgatp Sv39x4), at level 0 or 1. The
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
    if (lvl == 2'd0) begin
      vspath(leaf);
      la = SP_VT0 + 36'(8 * VA[8:0]);
    end else begin
      wrw(SP_VT2 + 36'(8 * VA[26:18]), pte(44'(GP_VT1), F_PTR));
      wrw(SP_VT1 + 36'(8 * VA[17:9]), leaf);
      la = SP_VT1 + 36'(8 * VA[17:9]);
    end
    walk(1'b1, 29'(VA), acc);
    exp_flt(nm, CAUSE_WIDTH'(cause));
    chk({nm, ": no CAS"}, n_cas == 0);
    chk({nm, ": leaf unchanged"}, rdw(la) == leaf);
  endtask

  // A G-stage leaf for the fetch's own GPA. The VS leaf has A and D,
  // so it needs no update; menvcfg.ADUE is set for the G-stage. lvl 1
  // maps guest page 0x200 (a 2 MiB G leaf in G1[1]); lvl 0 replaces
  // the G leaf of GP_CODE.
  task automatic lc_g(input string nm, input logic [63:0] leaf,
                      input logic [1:0] lvl, input logic pbmte);
    logic [PA_WIDTH-1:0]        la;
    logic [28:0]                gp;
    setup2(nm);
    cs_menvcfg_adue(1'b1);
    cs_menvcfg_pbmte(pbmte);
    if (lvl == 2'd0) begin
      gp = GP_CODE;
      vspath(pte(44'(GP_CODE), F_RXAD));
      la = G0 + 36'(8 * GP_CODE[8:0]);
    end else begin
      gp = 29'h200;
      vspath(pte(44'h200, F_RXAD));
      la = G1 + 36'(8 * 11'h1);
    end
    wrw(la, leaf);
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf41(nm, {gp, 12'h000}, 2'b00);
    chk({nm, ": no CAS"}, n_cas == 0);
    chk({nm, ": leaf unchanged"}, rdw(la) == leaf);
  endtask

  // MMU-24c (BP-124): the access fault and the guest-page fault take
  // the cause of the original access type, as the page fault does.
  task automatic t_causes();
    for (int a = 0; a < 2; a++) begin
      // PMP denies the read of the level-0 table: 5 for a read, 7 for a
      // store.
      setup(a == 0 ? "c_pmp_read_r" : "c_pmp_read_w");
      path3(T2, T1, T0, VA, pte(44'h8_2345, 8'hCF));  // D A X W R V
      cs_pmpcfg(0, 8'h18);
      cs_pmpaddr(0, 34'((T0 >> 2) | 36'h1FF));
      cs_pmpcfg(1, 8'h1F);
      cs_pmpaddr(1, '1);
      walk(1'b0, 29'(VA), a == 0 ? ACC_R : ACC_W);
      exp_flt(tname, a == 0 ? 5 : 7);
      // The final GPA is unmapped by the G-stage: 21 for a read, 23
      // for a store, kind 00.
      setup2(a == 0 ? "c_gpf_r" : "c_gpf_w");
      vspath(pte(44'(GP_CODE), 8'hCF));
      wrw(G0 + 36'(8 * GP_CODE[8:0]), 64'd0);
      walk(1'b1, 29'(VA), a == 0 ? ACC_R : ACC_W);
      exp_flt(tname, a == 0 ? 21 : 23);
      chk({tname, ": kind 00, the page"}, (r_imp == 2'b00) &&
          (r_gpa == FAULT_GPA_WIDTH'({GP_CODE, 12'h000})));
    end
  endtask

  task automatic t_leaf_checks();
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
    path3(T2, T1, T0, VA, pte(44'h8_2345, F_URX_NA));
    walk(1'b0, 29'(VA), ACC_X);
    exp_hit("U fetch from a U leaf", 24'h8_2345, SZ_4K, 2'd0);
    chk("U fetch from a U leaf: A set by one CAS", (n_cas == 1) &&
        (rdw(T0 + 36'(8 * VA[8:0])) == pte(44'h8_2345, F_URXA)));
    setup2("lc_vs_vu_fetch_uset_ok");
    cs_henvcfg_adue(1'b1);
    cs_menvcfg_adue(1'b1);
    req_priv = PRV_U;
    vspath(pte(44'(GP_CODE), F_URX_NA));
    walk(1'b1, 29'(VA), ACC_X);
    exp_hit("VU fetch from a U leaf", SP_CODE, SZ_4K, 2'd0);
    chk("VU fetch from a U leaf: A set",
        rdw(SP_VT0 + 36'(8 * VA[8:0])) == pte(44'(GP_CODE), F_URXA));

    // ---- the access type (MMU-26a) --------------------------------
    lc_s("lc_s_no_x", pte(44'h8_2345, 8'h03), 0, ACC_X, PRV_S, 1'b1, 12);
    lc_s("lc_s_no_w", pte(44'h8_2345, F_RX), 0, ACC_W, PRV_S, 1'b1, 15);
    lc_s("lc_s_no_r", pte(44'h8_2345, 8'h09), 0, ACC_R, PRV_S, 1'b1, 13);
    lc_vs("lc_vs_no_x", pte(44'(GP_CODE), 8'h03), 0, ACC_X, PRV_S, 1'b1,
          12);
    lc_vs("lc_vs_no_w", pte(44'(GP_CODE), F_RX), 0, ACC_W, PRV_S, 1'b1,
          15);
    lc_vs("lc_vs_no_r", pte(44'(GP_CODE), 8'h09), 0, ACC_R, PRV_S, 1'b1,
          13);
    lc_g("lc_g_no_x", pte(44'(SP_CODE), 8'h13), 0, 1'b1);   // U R, A clear
    lc_g("lc_g_no_u", pte(44'(SP_CODE), F_RX), 0, 1'b1);    // R X, A clear
    // A G leaf without R for the implicit read of a VS table page:
    // kind 01, and nothing is updated.
    setup2("lc_g_no_r_implicit");
    cs_menvcfg_adue(1'b1);
    vspath(pte(44'(GP_CODE), F_RXAD));
    wrw(G0 + 36'(8 * GP_VT1[8:0]), pte(44'(SP_VT1 >> 12), 8'h19)); // U X
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf41("G leaf without R, VS table read",
            {GP_VT1, 12'h000} + 41'(8 * VA[17:9]), 2'b01);
    chk("no R implicit: no CAS", n_cas == 0);
    chk("no R implicit: leaf unchanged",
        rdw(G0 + 36'(8 * GP_VT1[8:0])) == pte(44'(SP_VT1 >> 12), 8'h19));
    // A G leaf without W for the VS update. The leaf is read first (R
    // granted, A set, so no update for the read); the write needs W
    // and D: neither is set and nothing is stored.
    setup2("lc_g_no_w_update");
    cs_henvcfg_adue(1'b1);
    cs_menvcfg_adue(1'b1);
    vspath(pte(44'(GP_CODE), F_RX));                 // VS A clear
    wrw(G0 + 36'(8 * GP_VT0[8:0]), pte(44'(SP_VT0 >> 12), F_URXA));
    walk(1'b1, 29'(VA), ACC_X);
    exp_gpf41("G leaf without W, VS update",
            {GP_VT0, 12'h000} + 41'(8 * VA[8:0]), 2'b10);
    chk("no W update: no CAS", n_cas == 0);
    chk("no W update: G leaf unchanged",
        rdw(G0 + 36'(8 * GP_VT0[8:0])) == pte(44'(SP_VT0 >> 12), F_URXA));
    chk("no W update: VS leaf unchanged",
        rdw(SP_VT0 + 36'(8 * VA[8:0])) == pte(44'(GP_CODE), F_RX));

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
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    n_rsp    = 0;
    cyc      = 0;
    rstn     = 1'b0;
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
    $display("tb_ptw: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ptw: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #5000000;
    $fatal(1, "tb_ptw: timeout");
  end

endmodule : tb
