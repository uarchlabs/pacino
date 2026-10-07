// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for itlb (BP-118 Problem 5).
//
// THE L2 TLB MODEL. A table of mappings, each a page of one of the
// four sizes under a V, VMID and ASID, with the PTE permission byte,
// the PBMT and either a translation or a fault. A request is
// answered after the mapping's latency, so responses can return out
// of order when WALK_DEPTH allows two walks; a mapping can answer
// retry a given number of times first (IL-6). The model counts the
// requests it accepts: that count is how ITLB-10 and IL-6 are
// checked, from outside the DUT.
//
// Every expected value is written from the documents, not from the
// RTL: PPN substitution from ITLB-3 / IL-7, the four invalidate forms
// from ITLB-13, permissions from ITLB-16, the attributes from MMU-13
// and MMU-U6. Each group starts from reset with its own mappings.
//
// WALK_DEPTH is a parameter of this testbench so the same file runs
// at the default 1 and at 2 (ITLB-15). Group M runs only at 2.
//
// Groups:
//   A  physical regimes: Bare, M-mode, V=1 Bare/Bare; PA range; PMP
//   B  miss, walk, hit; the identity on the L2 request (IL-3)
//   C  re-requests during a walk start no second walk (ITLB-10)
//   D  hits continue while a walk is outstanding (ITLB-8)
//   E  retry is asked again (IL-6)
//   F  walk faults: 12, 20 with GPA, 1, unexpected cause, reserved
//   G  page sizes: 64 KiB NAPOT, 2 MiB, 1 GiB, across their ranges
//   H  ASID, global, V and VMID matching
//   I  ITLB-16 permission check against the current privilege
//   J  effective PMA and PBMT; PMP and PMA faults on a hit
//   K  invalidate: every ITLB-13, 13a and 13b form; during a walk
//   L  a page-crossing block, two tags, finals out of order
//   M  two walks outstanding, responses out of order (depth 2 only)
//   N  a held fault releases the tracker; an invalidate drops it
//   P  the address check of Sv39 (bits 40:39 equal bit 38)
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb #(
  parameter int WALK_DEPTH = 1
);

  localparam int VW = VA_WIDTH - 12;

  localparam logic [1:0] ST_HIT = 2'b00, ST_MISS = 2'b01,
                         ST_FAULT = 2'b10;
  localparam logic [1:0] L2_HIT = 2'b00, L2_FAULT = 2'b01,
                         L2_RETRY = 2'b10, L2_RSVD = 2'b11;
  localparam logic [1:0] SZ4K = 2'd0, SZ64K = 2'd1, SZ2M = 2'd2,
                         SZ1G = 2'd3;
  localparam logic [1:0] PU = 2'd0, PS = 2'd1, PM = 2'd3;
  localparam logic [3:0] BARE = 4'd0, SV39 = 4'd8;
  localparam logic [1:0] OP_VMA = 2'd0, OP_VVMA = 2'd1, OP_GVMA = 2'd2;

  // PTE permission bytes: V R W X U G A D.
  localparam logic [7:0] PX  = 8'b0100_1001;  // V X A
  localparam logic [7:0] PXU = 8'b0101_1001;  // V X U A
  localparam logic [7:0] PXG = 8'b0110_1001;  // V X G A
  localparam logic [7:0] PR  = 8'b0100_0011;  // V R A, no X

  localparam logic [3:0] MM = 4'b1111;

  logic clk;
  logic rstn;
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // ---- DUT ports -----------------------------------------------------
  logic                    req_val;
  logic                    req_rdy;
  logic [VW-1:0]           req_vpn;
  logic                    req_tag;
  logic                    rsp_val;
  logic                    rsp_tag;
  logic [1:0]              rsp_st;
  logic [PPN_WIDTH-1:0]    rsp_ppn;
  logic [CAUSE_WIDTH-1:0]  rsp_cause;
  logic [GPA_WIDTH-1:0]    rsp_gpa;
  logic [PMA_WIDTH-1:0]    rsp_pma;

  logic                    l2_req_val;
  logic                    l2_req_rdy;
  logic [VW-1:0]           l2_req_vpn;
  logic [ASID_WIDTH-1:0]   l2_req_asid;
  logic [VMID_WIDTH-1:0]   l2_req_vmid;
  logic                    l2_req_v;
  logic [1:0]              l2_req_tag;
  logic                    l2_rsp_val;
  logic [1:0]              l2_rsp_tag;
  logic [1:0]              l2_rsp_st;
  logic [PPN_WIDTH-1:0]    l2_rsp_ppn;
  logic [1:0]              l2_rsp_size;
  logic [PERM_WIDTH-1:0]   l2_rsp_perm;
  logic [1:0]              l2_rsp_pbmt;
  logic [CAUSE_WIDTH-1:0]  l2_rsp_cause;
  logic [GPA_WIDTH-1:0]    l2_rsp_gpa;

  logic                    c_v;
  logic [1:0]              c_priv;
  logic [3:0]              c_satp_mode, c_vsatp_mode, c_hgatp_mode;
  logic [ASID_WIDTH-1:0]   c_satp_asid, c_vsatp_asid;
  logic [VMID_WIDTH-1:0]   c_vmid;
  logic [15:0][7:0]        c_pmpcfg;
  logic [15:0][PA_WIDTH-3:0] c_pmpaddr;

  logic                    inv_val;
  logic [1:0]              inv_op;
  logic                    inv_rs1, inv_rs2;
  logic [VW-1:0]           inv_vpn;
  logic [ASID_WIDTH-1:0]   inv_asid;
  logic [VMID_WIDTH-1:0]   inv_vmid;

  itlb #(.WALK_DEPTH (WALK_DEPTH)) dut (
    .clk                   (clk),
    .rstn                  (rstn),
    .ifu_itlb_req_val      (req_val),
    .ifu_itlb_req_rdy      (req_rdy),
    .ifu_itlb_vpn          (req_vpn),
    .ifu_itlb_tag          (req_tag),
    .itlb_ifu_rsp_val      (rsp_val),
    .itlb_ifu_tag          (rsp_tag),
    .itlb_ifu_status       (rsp_st),
    .itlb_ifu_ppn          (rsp_ppn),
    .itlb_ifu_cause        (rsp_cause),
    .itlb_ifu_gpa          (rsp_gpa),
    .itlb_ifu_pma          (rsp_pma),
    .itlb_l2t_req_val      (l2_req_val),
    .itlb_l2t_req_rdy      (l2_req_rdy),
    .itlb_l2t_vpn          (l2_req_vpn),
    .itlb_l2t_asid         (l2_req_asid),
    .itlb_l2t_vmid         (l2_req_vmid),
    .itlb_l2t_v            (l2_req_v),
    .itlb_l2t_tag          (l2_req_tag),
    .l2t_itlb_rsp_val      (l2_rsp_val),
    .l2t_itlb_tag          (l2_rsp_tag),
    .l2t_itlb_status       (l2_rsp_st),
    .l2t_itlb_ppn          (l2_rsp_ppn),
    .l2t_itlb_size         (l2_rsp_size),
    .l2t_itlb_perm         (l2_rsp_perm),
    .l2t_itlb_pbmt         (l2_rsp_pbmt),
    .l2t_itlb_cause        (l2_rsp_cause),
    .l2t_itlb_gpa          (l2_rsp_gpa),
    .csr_itlb_v            (c_v),
    .csr_itlb_priv         (c_priv),
    .csr_itlb_satp_mode    (c_satp_mode),
    .csr_itlb_satp_asid    (c_satp_asid),
    .csr_itlb_vsatp_mode   (c_vsatp_mode),
    .csr_itlb_vsatp_asid   (c_vsatp_asid),
    .csr_itlb_hgatp_mode   (c_hgatp_mode),
    .csr_itlb_hgatp_vmid   (c_vmid),
    .csr_itlb_pmpcfg       (c_pmpcfg),
    .csr_itlb_pmpaddr      (c_pmpaddr),
    .bkend_itlb_inv_val    (inv_val | inv_auto),
    .bkend_itlb_inv_op     (inv_op),
    .bkend_itlb_inv_rs1_nz (inv_rs1),
    .bkend_itlb_inv_rs2_nz (inv_rs2),
    .bkend_itlb_inv_vpn    (inv_vpn),
    .bkend_itlb_inv_asid   (inv_asid),
    .bkend_itlb_inv_vmid   (inv_vmid)
  );

  // =================================================================
  // L2 TLB model
  // =================================================================
  typedef struct {
    logic                   v;
    logic [VMID_WIDTH-1:0]  vmid;
    logic [ASID_WIDTH-1:0]  asid;
    logic [VW-1:0]          vbase;   // first 4 KiB VPN of the page
    logic [1:0]             size;
    logic [1:0]             st;      // L2_HIT or L2_FAULT
    logic [PPN_WIDTH-1:0]   ppn;     // as the PTE holds it
    logic [7:0]             perm;
    logic [1:0]             pbmt;
    logic [CAUSE_WIDTH-1:0] cause;
    logic [GPA_WIDTH-1:0]   gpa;
    int                     lat;
    int                     retries;
  } map_t;

  map_t  maps [$];
  int    l2_reqs;                    // requests the model accepted
  logic  [VW-1:0] last_vpn;
  logic  [ASID_WIDTH-1:0] last_asid;
  logic  [VMID_WIDTH-1:0] last_vmid;
  logic  last_v;

  typedef struct {
    logic [1:0] tag;
    int         due;
    int         mi;    // mapping index, -1 for none found
    logic       retry;
  } pend_t;
  pend_t pend [$];
  int    cyc;
  // K16: assert the invalidate with the next response.
  logic  inv_arm;
  logic  inv_auto;
  logic  inv_met;

  function automatic longint pages(input logic [1:0] sz);
    case (sz)
      SZ4K:    return 1;
      SZ64K:   return 16;
      SZ2M:    return 512;
      default: return 262144;
    endcase
  endfunction

  function automatic int find_map(input logic [VW-1:0] vpn,
                                  input logic v,
                                  input logic [VMID_WIDTH-1:0] vmid,
                                  input logic [ASID_WIDTH-1:0] asid);
    for (int i = 0; i < maps.size(); i++) begin
      if (maps[i].v == v && (!v || maps[i].vmid == vmid) &&
          (maps[i].perm[5] || maps[i].asid == asid) &&
          (longint'(vpn) >= longint'(maps[i].vbase)) &&
          (longint'(vpn) <  longint'(maps[i].vbase) + pages(maps[i].size)))
        return i;
    end
    return -1;
  endfunction

  task automatic add_map(input logic v, input logic [VMID_WIDTH-1:0] vm,
                         input logic [ASID_WIDTH-1:0] as,
                         input logic [VW-1:0] vb, input logic [1:0] sz,
                         input logic [PPN_WIDTH-1:0] pn,
                         input logic [7:0] pm, input logic [1:0] pb,
                         input int lat);
    map_t m;
    m.v = v; m.vmid = vm; m.asid = as; m.vbase = vb; m.size = sz;
    m.st = L2_HIT; m.ppn = pn; m.perm = pm; m.pbmt = pb;
    m.cause = '0; m.gpa = '0; m.lat = lat; m.retries = 0;
    maps.push_back(m);
  endtask

  task automatic add_fault(input logic [VW-1:0] vb, input logic [1:0] st,
                           input logic [CAUSE_WIDTH-1:0] cs,
                           input logic [GPA_WIDTH-1:0] ga, input int lat);
    map_t m;
    m.v = c_v; m.vmid = c_vmid;
    m.asid = c_v ? c_vsatp_asid : c_satp_asid;
    m.vbase = vb; m.size = SZ4K; m.st = st; m.ppn = '0; m.perm = 8'h00;
    m.pbmt = '0; m.cause = cs; m.gpa = ga; m.lat = lat; m.retries = 0;
    maps.push_back(m);
  endtask

  // Accept at posedge; answer at negedge, one response per cycle,
  // the earliest due first. Written as forever loops in initial
  // blocks: the model is behavioural and uses blocking updates on its
  // queues.
  initial forever begin
    @(posedge clk);
    if (!rstn) begin
      pend.delete();
      l2_reqs = 0;
      cyc     = 0;
    end else begin
      cyc++;
      if (l2_req_val && l2_req_rdy) begin
        pend_t p;
        int    mi;
        l2_reqs++;
        last_vpn = l2_req_vpn; last_asid = l2_req_asid;
        last_vmid = l2_req_vmid; last_v = l2_req_v;
        mi = find_map(l2_req_vpn, l2_req_v, l2_req_vmid, l2_req_asid);
        p.tag   = l2_req_tag;
        p.mi    = mi;
        p.retry = 1'b0;
        p.due   = cyc + ((mi >= 0) ? maps[mi].lat : 1);
        if (mi >= 0 && maps[mi].retries > 0) begin
          maps[mi].retries--;
          p.retry = 1'b1;
        end
        pend.push_back(p);
      end
    end
  end

  initial forever begin
    @(negedge clk);
    inv_auto     = 1'b0;
    l2_rsp_val   = 1'b0;
    l2_rsp_tag   = '0;
    l2_rsp_st    = '0;
    l2_rsp_ppn   = '0;
    l2_rsp_size  = '0;
    l2_rsp_perm  = '0;
    l2_rsp_pbmt  = '0;
    l2_rsp_cause = '0;
    l2_rsp_gpa   = '0;
    if (rstn) begin
      int best;
      best = -1;
      for (int i = 0; i < pend.size(); i++) begin
        if (pend[i].due <= cyc &&
            (best < 0 || pend[i].due < pend[best].due)) best = i;
      end
      if (best >= 0) begin
        pend_t p;
        p = pend[best];
        pend.delete(best);
        l2_rsp_val = 1'b1;
        if (inv_arm) begin
          inv_auto = 1'b1;
          inv_arm  =  1'b0;
          inv_met  =  1'b1;
        end
        l2_rsp_tag = p.tag;
        if (p.retry) begin
          l2_rsp_st = L2_RETRY;
        end else if (p.mi < 0) begin
          // An unmapped address answers a page fault.
          l2_rsp_st    = L2_FAULT;
          l2_rsp_cause = 5'd12;
        end else begin
          l2_rsp_st    = maps[p.mi].st;
          l2_rsp_ppn   = maps[p.mi].ppn;
          l2_rsp_size  = maps[p.mi].size;
          l2_rsp_perm  = maps[p.mi].perm;
          l2_rsp_pbmt  = maps[p.mi].pbmt;
          l2_rsp_cause = maps[p.mi].cause;
          l2_rsp_gpa   = maps[p.mi].gpa;
        end
      end
    end
  end

  // =================================================================
  // Stimulus helpers
  // =================================================================
  int pass_cnt = 0;
  int fail_cnt = 0;

  logic                   g_val, g_tag;
  logic [1:0]             g_st;
  logic [PPN_WIDTH-1:0]   g_ppn;
  logic [CAUSE_WIDTH-1:0] g_cause;
  logic [GPA_WIDTH-1:0]   g_gpa;
  logic [PMA_WIDTH-1:0]   g_pma;

  task automatic ok(input string nm, input logic c);
    if (c) pass_cnt++;
    else begin
      fail_cnt++;
      $display("FAIL %s  st=%b ppn=%h cause=%0d gpa=%h pma=%b tag=%b",
               nm, g_st, g_ppn, g_cause, g_gpa, g_pma, g_tag);
    end
  endtask

  task automatic reset_all();
    rstn         = 1'b0;
    req_val      = 1'b0; req_vpn = '0; req_tag = 1'b0;
    l2_req_rdy   = 1'b1;
    c_v          = 1'b0; c_priv = PS;
    c_satp_mode  = SV39; c_satp_asid = 16'd5;
    c_vsatp_mode = SV39; c_vsatp_asid = 16'd5;
    c_hgatp_mode = SV39; c_vmid = 14'd3;
    // PMP entry 0: NAPOT over the whole space, RWX, so the PMP
    // passes unless a test says otherwise.
    c_pmpcfg     = '0; c_pmpaddr = '0;
    c_pmpcfg[0]  = 8'h1F; c_pmpaddr[0] = '1;
    inv_val = 1'b0; inv_op = '0; inv_rs1 = 1'b0; inv_rs2 = 1'b0;
    inv_vpn = '0; inv_asid = '0; inv_vmid = '0;
    maps.delete();
    repeat (3) @(negedge clk);
    rstn = 1'b1;
    @(negedge clk);
  endtask

  // One lookup: present for one cycle, sample the answer the cycle
  // after (ITLB-5).
  task automatic look(input logic [VW-1:0] vpn, input logic tag = 1'b0);
    req_val = 1'b1; req_vpn = vpn; req_tag = tag;
    @(negedge clk);
    req_val = 1'b0;
    g_val = rsp_val; g_tag = rsp_tag; g_st = rsp_st; g_ppn = rsp_ppn;
    g_cause = rsp_cause; g_gpa = rsp_gpa; g_pma = rsp_pma;
    if (g_val !== 1'b1) begin
      fail_cnt++;
      $display("FAIL no response one cycle after the request");
    end
  endtask

  // Re-request every cycle until the answer is final, as the IFU does
  // (IT-8). Returns the number of miss answers seen.
  task automatic xlate(input logic [VW-1:0] vpn, output int misses,
                       input logic tag = 1'b0);
    misses = 0;
    req_val = 1'b1; req_vpn = vpn; req_tag = tag;
    for (int k = 0; k < 200; k++) begin
      @(negedge clk);
      g_val = rsp_val; g_tag = rsp_tag; g_st = rsp_st; g_ppn = rsp_ppn;
      g_cause = rsp_cause; g_gpa = rsp_gpa; g_pma = rsp_pma;
      if (g_st != ST_MISS) break;
      misses++;
    end
    req_val = 1'b0;
  endtask

  task automatic idle(input int n);
    repeat (n) @(negedge clk);
  endtask

  task automatic inval(input logic [1:0] op, input logic r1,
                       input logic r2, input logic [VW-1:0] vpn,
                       input logic [ASID_WIDTH-1:0] as,
                       input logic [VMID_WIDTH-1:0] vm);
    inv_val = 1'b1; inv_op = op; inv_rs1 = r1; inv_rs2 = r2;
    inv_vpn = vpn; inv_asid = as; inv_vmid = vm;
    @(negedge clk);
    inv_val = 1'b0;
  endtask

  // Hit / miss probes that leave no walk behind them: a probe miss
  // starts a walk only for an unmapped VPN, answered by a page fault,
  // which group N shows is harmless; the probes below run after the
  // walk queue is drained.
  task automatic expect_hit(input string nm, input logic [VW-1:0] vpn,
                            input logic [PPN_WIDTH-1:0] ppn);
    look(vpn);
    ok(nm, g_st == ST_HIT && g_ppn == ppn);
  endtask

  task automatic expect_miss(input string nm, input logic [VW-1:0] vpn);
    look(vpn);
    ok(nm, g_st == ST_MISS);
    idle(4);
  endtask

  // Install one mapping by walking it.
  task automatic install(input logic [VW-1:0] vpn);
    int m;
    xlate(vpn, m);
    if (g_st != ST_HIT) begin
      fail_cnt++;
      $display("FAIL install of %h did not hit (st=%b)", vpn, g_st);
    end
  endtask

  // =================================================================
  // Tests
  // =================================================================
  int m0, n0;

  // VPNs used below. Main memory starts at PPN 0x80000.
  localparam logic [VW-1:0] VA_A = 29'h0001000;
  localparam logic [VW-1:0] VA_B = 29'h0002000;
  localparam logic [VW-1:0] VA_C = 29'h0003000;

  initial begin
    inv_arm = 1'b0;
    inv_met = 1'b0;

    // ---- A: physical regimes ------------------------------------------
    reset_all();
    c_satp_mode = BARE;
    look(29'h0080000);
    ok("A1 Bare main memory base", g_st == ST_HIT &&
       g_ppn == 24'h080000 && g_pma == MM);
    look(29'h0FFFFFF);
    ok("A2 Bare top of PA space", g_st == ST_HIT && g_ppn == 24'hFFFFFF);
    look(29'h007FFFF);
    ok("A3 Bare below main memory", g_st == ST_FAULT && g_cause == 5'd1);
    // PA bit 36 set over a main-memory page: dropping bit 36 would
    // land in main memory, so only the range check faults it.
    look(29'h1080000);
    ok("A4 Bare above pa_bits", g_st == ST_FAULT && g_cause == 5'd1);
    look(29'h1008_0000);
    ok("A5 Bare bit 40 set", g_st == ST_FAULT && g_cause == 5'd1);
    c_satp_mode = SV39;
    c_priv = PM;
    look(29'h0080123);
    ok("A6 M-mode untranslated", g_st == ST_HIT && g_ppn == 24'h080123);
    c_priv = PS;
    c_v = 1'b1; c_vsatp_mode = BARE; c_hgatp_mode = BARE;
    look(29'h0090000);
    ok("A7 V=1 Bare/Bare physical", g_st == ST_HIT && g_ppn == 24'h090000);
    c_v = 1'b0; c_satp_mode = BARE;
    c_pmpcfg[0] = 8'h00;                    // PMP entry OFF
    look(29'h0080000);
    ok("A8 Bare S no PMP match", g_st == ST_FAULT && g_cause == 5'd1);
    c_priv = PM;
    look(29'h0080000);
    ok("A9 Bare M no PMP match", g_st == ST_HIT);
    ok("A10 no walk in any physical regime", l2_reqs == 0);

    // ---- B: miss, walk, hit ---------------------------------------------
    reset_all();
    add_map(1'b0, '0, 16'd5, VA_A, SZ4K, 24'h080010, PX, 2'd0, 5);
    look(VA_A);
    ok("B1 first lookup misses", g_st == ST_MISS);
    idle(2);
    ok("B2 one walk requested", l2_reqs == 1);
    ok("B3 L2 request identity", last_vpn == VA_A && last_asid == 16'd5 &&
       last_v == 1'b0);
    xlate(VA_A, m0);
    ok("B4 hit after the walk", g_st == ST_HIT && g_ppn == 24'h080010 &&
       g_pma == MM && g_cause == 5'd0);
    n0 = l2_reqs;
    look(VA_A);
    ok("B5 installed, one-cycle hit", g_st == ST_HIT &&
       g_ppn == 24'h080010);
    ok("B6 no second walk", l2_reqs == n0);

    // ---- C: ITLB-10, IT-9 -------------------------------------------------
    reset_all();
    add_map(1'b0, '0, 16'd5, VA_A, SZ4K, 24'h080010, PX, 2'd0, 12);
    xlate(VA_A, m0);
    ok("C1 re-requested while walking", m0 >= 8);
    ok("C2 hit at the end", g_st == ST_HIT);
    ok("C3 exactly one walk", l2_reqs == 1);

    // ---- D: ITLB-8 --------------------------------------------------------
    reset_all();
    add_map(1'b0, '0, 16'd5, VA_A, SZ4K, 24'h080010, PX, 2'd0, 2);
    add_map(1'b0, '0, 16'd5, VA_B, SZ4K, 24'h080020, PX, 2'd0, 30);
    install(VA_A);
    look(VA_B);
    ok("D1 VA_B misses", g_st == ST_MISS);
    idle(2);
    for (int k = 0; k < 5; k++) begin
      look(VA_A);
      ok("D2 hit during a walk", g_st == ST_HIT && g_ppn == 24'h080010);
    end
    ok("D3 the walk is still outstanding", pend.size() == 1);
    xlate(VA_B, m0);
    ok("D4 VA_B completes", g_st == ST_HIT && g_ppn == 24'h080020);

    // ---- E: IL-6 retry ----------------------------------------------------
    reset_all();
    add_map(1'b0, '0, 16'd5, VA_C, SZ4K, 24'h080030, PX, 2'd0, 3);
    maps[0].retries = 2;
    xlate(VA_C, m0);
    ok("E1 hit after two retries", g_st == ST_HIT && g_ppn == 24'h080030);
    ok("E2 three requests: two re-asked", l2_reqs == 3);
    // The ITLB re-asks by itself: one lookup, no IFU re-request.
    reset_all();
    add_map(1'b0, '0, 16'd5, VA_C, SZ4K, 24'h080030, PX, 2'd0, 3);
    maps[0].retries = 2;
    look(VA_C);
    ok("E3 one lookup misses", g_st == ST_MISS);
    idle(20);
    ok("E4 the ITLB asked three times", l2_reqs == 3);
    expect_hit("E5 installed with no re-request", VA_C, 24'h080030);

    // ---- F: faults from the walk ----------------------------------------
    reset_all();
    add_fault(VA_A, L2_FAULT, 5'd12, '0, 3);
    xlate(VA_A, m0);
    ok("F1 cause 12 delivered", g_st == ST_FAULT && g_cause == 5'd12 &&
       g_gpa == '0);
    n0 = l2_reqs;
    look(VA_A);
    ok("F2 a fault is not cached", g_st == ST_MISS);
    idle(2);
    ok("F3 the next lookup walks again", l2_reqs == n0 + 1);
    idle(6);
    reset_all();
    c_v = 1'b1;
    add_fault(VA_B, L2_FAULT, 5'd20, 41'h1_2345_6789A, 3);
    xlate(VA_B, m0);
    ok("F4 cause 20 with GPA", g_st == ST_FAULT && g_cause == 5'd20 &&
       g_gpa == 41'h1_2345_6789A);
    ok("F5 V=1 walk carries V and VMID", last_v == 1'b1 &&
       last_vmid == 14'd3);
    reset_all();
    add_fault(VA_C, L2_FAULT, 5'd1, 41'h0_0000_0FFF, 3);
    xlate(VA_C, m0);
    ok("F6 cause 1, no GPA", g_st == ST_FAULT && g_cause == 5'd1 &&
       g_gpa == '0);
    reset_all();
    add_fault(VA_A, L2_FAULT, 5'd7, '0, 3);
    xlate(VA_A, m0);
    ok("F7 unexpected cause as 1", g_st == ST_FAULT && g_cause == 5'd1);
    reset_all();
    add_fault(VA_A, L2_RSVD, 5'd12, '0, 3);
    xlate(VA_A, m0);
    ok("F8 reserved status as cause 1", g_st == ST_FAULT &&
       g_cause == 5'd1);

    // ---- G: page sizes ----------------------------------------------------
    reset_all();
    // 64 KiB NAPOT: the PTE PPN carries the 1000 marker in [3:0].
    add_map(1'b0, '0, 16'd5, 29'h0040000, SZ64K, 24'h081238, PX, 2'd0, 2);
    xlate(29'h0040005, m0);
    ok("G1 64K walk hit, PPN[3:0] = VPN[3:0]", g_st == ST_HIT &&
       g_ppn == 24'h081235);
    n0 = l2_reqs;
    expect_hit("G2 64K low end",  29'h0040000, 24'h081230);
    expect_hit("G3 64K high end", 29'h004000F, 24'h08123F);
    ok("G4 64K held once", l2_reqs == n0);
    expect_miss("G5 64K just above", 29'h0040010);
    expect_miss("G6 64K just below", 29'h003FFFF);
    reset_all();
    add_map(1'b0, '0, 16'd5, 29'h0000200, SZ2M, 24'h080200, PX, 2'd0, 2);
    install(29'h00003FF);
    n0 = l2_reqs;
    expect_hit("G7 2M low end",  29'h0000200, 24'h080200);
    expect_hit("G8 2M high end", 29'h00003FF, 24'h0803FF);
    ok("G9 2M held once", l2_reqs == n0);
    expect_miss("G10 2M just above", 29'h0000400);
    reset_all();
    add_map(1'b0, '0, 16'd5, 29'h00C0000, SZ1G, 24'h840000, PX, 2'd0, 2);
    install(29'h00C1234);
    n0 = l2_reqs;
    expect_hit("G11 1G low end",  29'h00C0000, 24'h840000);
    expect_hit("G12 1G high end", 29'h00FFFFF, 24'h87FFFF);
    ok("G13 1G held once", l2_reqs == n0);
    expect_miss("G14 1G just above", 29'h0100000);
    // Sv39 high half: bits 40:39 equal bit 38.
    reset_all();
    add_map(1'b0, '0, 16'd5, 29'h1FFF_FFFF, SZ4K, 24'h080400, PX, 2'd0, 2);
    install(29'h1FFF_FFFF);
    expect_hit("G15 Sv39 top page", 29'h1FFF_FFFF, 24'h080400);

    // ---- H: tag matching --------------------------------------------------
    reset_all();
    add_map(1'b0, '0, 16'd5, VA_A, SZ4K, 24'h080010, PX,  2'd0, 2);
    add_map(1'b0, '0, 16'd5, VA_B, SZ4K, 24'h080020, PXG, 2'd0, 2);
    install(VA_A);
    install(VA_B);
    c_satp_asid = 16'd6;
    expect_miss("H1 other ASID misses", VA_A);
    expect_hit("H2 global ignores ASID", VA_B, 24'h080020);
    c_satp_asid = 16'd5;
    expect_hit("H3 own ASID hits", VA_A, 24'h080010);
    // V: the V=0 entries do not serve V=1.
    c_v = 1'b1;
    look(VA_A);
    ok("H4 V=1 misses a V=0 entry", g_st == ST_MISS);
    idle(2);
    ok("H5 V=1 L2 identity", last_v == 1'b1 && last_vmid == 14'd3 &&
       last_asid == 16'd5);
    idle(4);
    reset_all();
    c_v = 1'b1;
    add_map(1'b1, 14'd3, 16'd5, VA_A, SZ4K, 24'h080110, PX,  2'd0, 2);
    add_map(1'b1, 14'd3, 16'd5, VA_B, SZ4K, 24'h080120, PXG, 2'd0, 2);
    install(VA_A);
    install(VA_B);
    expect_hit("H6 V=1 VMID 3 hit", VA_A, 24'h080110);
    c_vmid = 14'd4;
    expect_miss("H7 other VMID misses", VA_A);
    expect_miss("H8 global is per VMID", VA_B);
    c_vmid = 14'd3;
    c_vsatp_asid = 16'd9;
    expect_hit("H9 V=1 global ignores ASID", VA_B, 24'h080120);
    expect_miss("H10 V=1 other ASID misses", VA_A);
    c_vsatp_asid = 16'd5;
    c_v = 1'b0;
    expect_miss("H11 V=0 misses a V=1 entry", VA_A);

    // ---- I: ITLB-16 ------------------------------------------------------
    reset_all();
    add_map(1'b0, '0, 16'd5, VA_A, SZ4K, 24'h080010, PX,  2'd0, 2);
    add_map(1'b0, '0, 16'd5, VA_B, SZ4K, 24'h080020, PXU, 2'd0, 2);
    add_map(1'b0, '0, 16'd5, VA_C, SZ4K, 24'h080030, PR,  2'd0, 2);
    install(VA_A);
    c_priv = PU;
    install(VA_B);
    c_priv = PS;
    n0 = l2_reqs;
    expect_hit("I1 S, U clear: legal", VA_A, 24'h080010);
    c_priv = PU;
    look(VA_A);
    ok("I2 U, U clear: cause 12", g_st == ST_FAULT && g_cause == 5'd12);
    c_priv = PS;
    expect_hit("I3 back to S, no fence", VA_A, 24'h080010);
    look(VA_B);
    ok("I4 S, U set: cause 12", g_st == ST_FAULT && g_cause == 5'd12);
    c_priv = PU;
    expect_hit("I5 U, U set: legal", VA_B, 24'h080020);
    ok("I6 no walk for a permission change", l2_reqs == n0);
    c_priv = PS;
    xlate(VA_C, m0);
    ok("I7 X clear: cause 12", g_st == ST_FAULT && g_cause == 5'd12);
    // VU and VS for a V=1 entry.
    reset_all();
    c_v = 1'b1;
    add_map(1'b1, 14'd3, 16'd5, VA_A, SZ4K, 24'h080110, PX, 2'd0, 2);
    install(VA_A);
    c_priv = PU;
    look(VA_A);
    ok("I8 VU, U clear: cause 12", g_st == ST_FAULT && g_cause == 5'd12);

    // ---- J: effective attributes; PMP and PMA on a hit -------------------
    reset_all();
    add_map(1'b0, '0, 16'd5, VA_A, SZ4K, 24'h080010, PX, 2'd1, 2);   // NC
    add_map(1'b0, '0, 16'd5, VA_B, SZ4K, 24'h080020, PX, 2'd2, 2);   // IO
    add_map(1'b0, '0, 16'd5, VA_C, SZ4K, 24'h000010, PX, 2'd0, 2);   // dev
    install(VA_A);
    ok("J1 NC: not cacheable", g_pma == 4'b1110);
    install(VA_B);
    ok("J2 IO: not cacheable, not idempotent", g_pma == 4'b0110);
    xlate(VA_C, m0);
    ok("J3 PA outside main memory: cause 1", g_st == ST_FAULT &&
       g_cause == 5'd1);
    // PMP: entry 0 covers PA 0x8001_0000 4 KiB with no X, so VA_A's
    // page is denied; entry 1 still grants the rest.
    c_pmpcfg[1]  = 8'h1F; c_pmpaddr[1] = '1;
    c_pmpcfg[0]  = 8'h1B;                              // NAPOT R W
    c_pmpaddr[0] = 34'(36'h0_8001_0000 >> 2) | 34'h1FF;
    look(VA_A);
    ok("J4 PMP denies X: cause 1", g_st == ST_FAULT && g_cause == 5'd1);
    look(VA_B);
    ok("J5 PMP other page allowed", g_st == ST_HIT);
    // ITLB-16 outranks the PMP: a translation fault comes first.
    c_priv = PU;
    look(VA_A);
    ok("J6 permission fault before PMP", g_st == ST_FAULT &&
       g_cause == 5'd12);

    // ---- K: invalidate ---------------------------------------------------
    for (int f = 0; f < 13; f++) begin
      reset_all();
      // V=0: E1 asid5 @A, E2 global @B, E3 asid6 @C
      add_map(1'b0, '0, 16'd5, VA_A, SZ4K, 24'h080001, PX,  2'd0, 2);
      add_map(1'b0, '0, 16'd5, VA_B, SZ4K, 24'h080002, PXG, 2'd0, 2);
      add_map(1'b0, '0, 16'd6, VA_C, SZ4K, 24'h080003, PX,  2'd0, 2);
      // V=1: E4 vmid3 asid5 @A, E5 vmid4 asid5 @A, E6 vmid3 global @B
      add_map(1'b1, 14'd3, 16'd5, VA_A, SZ4K, 24'h080004, PX,  2'd0, 2);
      add_map(1'b1, 14'd4, 16'd5, VA_A, SZ4K, 24'h080005, PX,  2'd0, 2);
      add_map(1'b1, 14'd3, 16'd5, VA_B, SZ4K, 24'h080006, PXG, 2'd0, 2);
      // a 2 MiB V=0 entry for the superpage address form
      add_map(1'b0, '0, 16'd5, 29'h0000200, SZ2M, 24'h080200, PX, 2'd0, 2);
      install(VA_A); install(VA_B);
      c_satp_asid = 16'd6; install(VA_C); c_satp_asid = 16'd5;
      install(29'h0000210);
      c_v = 1'b1;
      install(VA_A); install(VA_B);
      c_vmid = 14'd4; install(VA_A); c_vmid = 14'd3;
      c_v = 1'b0;
      case (f)
        0:  inval(OP_VMA,  0, 0, '0,   '0,    '0);
        1:  inval(OP_VMA,  0, 1, '0,   16'd5, '0);
        2:  inval(OP_VMA,  1, 0, VA_B, '0,    '0);
        3:  inval(OP_VMA,  1, 1, VA_A, 16'd5, '0);
        4:  inval(OP_VMA,  1, 1, VA_B, 16'd5, '0);
        5:  inval(OP_VVMA, 0, 0, '0,   '0,    14'd3);
        6:  inval(OP_VVMA, 0, 1, '0,   16'd5, 14'd3);
        7:  inval(OP_VVMA, 1, 0, VA_B, '0,    14'd3);
        8:  inval(OP_VVMA, 1, 1, VA_B, 16'd5, 14'd3);
        9:  inval(OP_GVMA, 0, 1, '0,   '0,    14'd3);
        10: inval(OP_GVMA, 0, 0, '0,   '0,    '0);
        11: inval(OP_VMA,  1, 0, 29'h00003F0, '0, '0);
        default: inval(OP_VMA, 1, 0, 29'h0001FFF, '0, '0); // no match
      endcase
      // Expected survivors, from ITLB-13 / 13a / 13b. Bit order:
      // E1 E2 E3 E4 E5 E6 E7(2M).
      begin
        logic [6:0] exp;
        logic [6:0] got;
        case (f)
          0:  exp = 7'b0001110;   // all V=0 gone, global included
          1:  exp = 7'b0111110;   // asid5 V=0 non-global: E1, E7
          2:  exp = 7'b1011111;   // VA_B V=0 gone, global included
          3:  exp = 7'b0111111;   // VA_A asid5 V=0 gone
          4:  exp = 7'b1111111;   // VA_B asid5: global excluded
          5:  exp = 7'b1110101;   // vmid3 V=1 gone, global included
          6:  exp = 7'b1110111;   // vmid3 asid5 non-global gone
          7:  exp = 7'b1111101;   // vmid3 VA_B gone, global included
          8:  exp = 7'b1111111;   // VA_B asid5 vmid3: global excluded
          9:  exp = 7'b1110101;   // GVMA vmid3: E4 E6 gone
          10: exp = 7'b1110001;   // GVMA all: every V=1 entry gone
          11: exp = 7'b1111110;   // 2M entry covers the address
          default: exp = 7'b1111111;
        endcase
        // got[6:0] is E1..E7 in the order of exp.
        n0 = l2_reqs;
        look(29'h0000210); got[0] = (g_st == ST_HIT); idle(4);
        c_satp_asid = 16'd6;
        look(VA_C);        got[4] = (g_st == ST_HIT); idle(4);
        c_satp_asid = 16'd5;
        look(VA_B);        got[5] = (g_st == ST_HIT); idle(4);
        look(VA_A);        got[6] = (g_st == ST_HIT); idle(4);
        c_v = 1'b1;
        look(VA_A);        got[3] = (g_st == ST_HIT); idle(4);
        look(VA_B);        got[1] = (g_st == ST_HIT); idle(4);
        c_vmid = 14'd4;
        look(VA_A);        got[2] = (g_st == ST_HIT); idle(4);
        c_vmid = 14'd3; c_v = 1'b0;
        if (got == exp) pass_cnt++;
        else begin
          fail_cnt++;
          $display("FAIL K%0d survivors got %b exp %b", f, got, exp);
        end
      end
    end
    // IL-13 / IL-14: an invalidate during a walk installs nothing.
    reset_all();
    add_map(1'b0, '0, 16'd5, VA_A, SZ4K, 24'h080010, PX, 2'd0, 8);
    look(VA_A);
    idle(3);
    inval(OP_VMA, 1, 0, VA_C, '0, '0);      // unrelated address
    idle(10);
    n0 = l2_reqs;
    look(VA_A);
    ok("K13 killed walk installed nothing", g_st == ST_MISS);
    idle(2);
    ok("K14 tracker released, new walk", l2_reqs == n0 + 1);
    xlate(VA_A, m0);
    ok("K15 the new walk installs", g_st == ST_HIT);
    // the invalidate in the cycle the response returns
    reset_all();
    add_map(1'b0, '0, 16'd5, VA_B, SZ4K, 24'h080020, PX, 2'd0, 4);
    // The model raises the invalidate in the cycle it presents the
    // response (inv_arm), so the two reach the DUT on one edge.
    inv_op = OP_VMA; inv_rs1 = 1'b1; inv_vpn = VA_C;
    inv_arm = 1'b1;
    look(VA_B);
    idle(8);
    ok("K16a the invalidate met the response", inv_met);
    inv_rs1 = 1'b0;
    look(VA_B);
    ok("K16 invalidate with the response: no install", g_st == ST_MISS);
    idle(6);

    // ---- L: page-crossing block ------------------------------------------
    reset_all();
    add_map(1'b0, '0, 16'd5, VA_A,        SZ4K, 24'h080010, PX, 2'd0, 6);
    add_map(1'b0, '0, 16'd5, VA_A + 29'd1, SZ4K, 24'h080011, PX, 2'd0, 2);
    install(VA_A + 29'd1);
    // tag 0 misses, tag 1 hits: the tag-1 final arrives first.
    look(VA_A, 1'b0);
    ok("L1 tag 0 miss carries tag 0", g_st == ST_MISS && g_tag == 1'b0);
    look(VA_A + 29'd1, 1'b1);
    ok("L2 tag 1 hit carries tag 1", g_st == ST_HIT && g_tag == 1'b1 &&
       g_ppn == 24'h080011);
    xlate(VA_A, m0, 1'b0);
    ok("L3 tag 0 final later, tag 0", g_st == ST_HIT && g_tag == 1'b0 &&
       g_ppn == 24'h080010);
    // back to back, one per cycle, each answered the next cycle
    req_val = 1'b1; req_vpn = VA_A; req_tag = 1'b0;
    @(negedge clk);
    ok("L4 first answer tag 0", rsp_val && rsp_tag == 1'b0 &&
       rsp_ppn == 24'h080010);
    req_vpn = VA_A + 29'd1; req_tag = 1'b1;
    @(negedge clk);
    ok("L5 second answer tag 1", rsp_val && rsp_tag == 1'b1 &&
       rsp_ppn == 24'h080011);
    req_val = 1'b0;
    @(negedge clk);
    ok("L6 no answer without a request", !rsp_val);

    // ---- M: two walks, out of order (WALK_DEPTH 2) -------------------------
    reset_all();
    add_map(1'b0, '0, 16'd5, VA_A, SZ4K, 24'h080010, PX, 2'd0, 10);
    add_map(1'b0, '0, 16'd5, VA_B, SZ4K, 24'h080020, PX, 2'd0, 2);
    look(VA_A);
    look(VA_B);
    idle(2);
    if (WALK_DEPTH >= 2) begin
      ok("M1 depth 2: two walks", l2_reqs == 2);
      idle(4);
      expect_hit("M2 the later walk returned first", VA_B, 24'h080020);
      look(VA_A);
      ok("M3 the earlier still walking", g_st == ST_MISS);
      idle(10);
      expect_hit("M4 the earlier installs", VA_A, 24'h080010);
    end else begin
      ok("M1 depth 1: the second miss starts no walk", l2_reqs == 1);
      idle(12);
    end

    // ---- N: held faults ----------------------------------------------------
    reset_all();
    add_fault(VA_A, L2_FAULT, 5'd12, '0, 2);
    add_map(1'b0, '0, 16'd5, VA_B, SZ4K, 24'h080020, PX, 2'd0, 2);
    look(VA_A);                    // the fault is never collected
    idle(6);
    xlate(VA_B, m0);
    ok("N1 an uncollected fault does not block", g_st == ST_HIT);
    reset_all();
    add_fault(VA_A, L2_FAULT, 5'd12, '0, 2);
    look(VA_A);
    idle(6);
    inval(OP_VMA, 0, 0, '0, '0, '0);
    n0 = l2_reqs;
    look(VA_A);
    ok("N2 invalidate dropped the held fault", g_st == ST_MISS);
    idle(2);
    ok("N3 and a new walk starts", l2_reqs == n0 + 1);
    idle(6);

    // ---- P: Sv39 address check --------------------------------------------
    reset_all();
    look(29'h0800_0000);            // VA bit 39 set, bit 38 clear
    ok("P1 V=0 Sv39 bad sign: cause 12", g_st == ST_FAULT &&
       g_cause == 5'd12);
    look(29'h1000_0000);            // VA bit 40 set only
    ok("P2 bit 40 alone: cause 12", g_st == ST_FAULT && g_cause == 5'd12);
    c_v = 1'b1; c_vsatp_mode = BARE;
    add_map(1'b1, 14'd3, 16'd5, 29'h1000_0000, SZ4K, 24'h080500, PX,
            2'd0, 2);
    xlate(29'h1000_0000, m0);
    ok("P3 V=1 G-only: all 41 bits legal", g_st == ST_HIT &&
       g_ppn == 24'h080500);
    ok("P4 V=1 G-only: L2 sees bit 40", last_vpn == 29'h1000_0000);
    ok("P5 no walk for P1, P2", l2_reqs == 1);

    $display("tb_itlb (WALK_DEPTH=%0d): PASS=%0d FAIL=%0d", WALK_DEPTH,
             pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_itlb: %0d check(s) failed", fail_cnt);
    end else begin
      $finish;
    end
  end

  initial begin
    #2000000;
    $fatal(1, "tb_itlb: timeout");
  end

endmodule : tb
