// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for the ifu unit (BP-116). Drives all four boundaries.
//
//   FTQ    a block list per test. Translation requests go in order;
//          a fetch request is presented only for a block whose
//          translation was accepted in an EARLIER cycle (FQ-1, the
//          FTQ's fetch_pending). Handshakes in a flush cycle are
//          discarded, as the FTQ does (ftq_ifu_interfaces.md 5).
//   ITLB   a page map this file controls: PPN, PMA, fault cause and
//          GPA, and a miss count per page (IT-7, IT-8). Per-tag
//          latency, so a page-crossing block's two responses can
//          return in either order (IT-3).
//   L1I    a memory image, per-request latency, and return-order
//          policies that hold responses until K are outstanding and
//          then release them forward, reversed, odd-first or in a
//          seeded random order. rsp_err per line (IF-15).
//   ibuf   a sink of 32 entries draining a set number per cycle,
//          ready only when 16 entries are free (IB-6), with a forced
//          stall for the backpressure test.
//
// THE EXPECTED RESULT IS DERIVED HERE from the memory image and the
// request, never from the RTL. ref_block() translates each of the
// 17 halfwords through this file's own page map, walks the
// instruction starts sequentially, cuts the range at the predicted
// taken position, the block end and the first faulting instruction,
// classifies each start from the expansion this file recorded when it
// wrote the instruction, and runs M1 to M4 itself. It tracks the
// straddle tail across blocks the same way the IFU must.
//
// Each test resets the unit and the models and builds its own state;
// nothing carries across tests.
//
// BP-117 (TD#146): ref_block's M1 is the session-074 rule, the first
// JAL before the predicted taken position or anywhere when none is
// predicted, ahead of M2 to M4. The ITLB model keys its page map on
// the IT-16 lookup width, VA_WIDTH-12, and logs every lookup.
// t_m1_jal and t_vpn_high are the two rulings' directed tests.
//
// BP-118 (TD#134): the flush with requests in flight, IFU-28 to
// IFU-32. The FTQ model takes a flush index and a commit pointer and
// rewinds its translation and fetch positions to the flush position
// when they were past it (ftq_decisions.md 5.5 R1); a test replaces
// the blocks from the flush position on with the corrected stream,
// each carrying the toggled generation. Indices start at idx0, so a
// test can place the block list across the FTQ index wrap. The L1I
// model can hold every response, or the responses of named lines,
// and can hold its ready low. The ITLB model logs the cycle of every
// lookup and response. A delivered block k is still checked against
// blk[k]: after a flush, rx[k] for k at or past the flush position
// must be the corrected block, which a delivered dropped block fails.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  localparam int NPD   = FTQ_PD_WIDTH;
  localparam int NPOS  = FTQ_PD_WIDTH + 1;
  localparam int MAXB  = 64;
  localparam int IBCAP = 32;
  localparam int LKV   = VA_WIDTH - 12;   // IT-16 lookup VPN width

  logic clk;
  logic rstn;
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ---- DUT ports ------------------------------------------------------
  logic                     ftq_ifu_xlate_val;
  logic                     ftq_ifu_xlate_rdy;
  logic [VA_WIDTH-1:0]      ftq_ifu_xlate_pc;
  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_xlate_idx;
  logic                     ftq_ifu_req_val;
  logic                     ftq_ifu_req_rdy;
  logic [VA_WIDTH-1:0]      ftq_ifu_start_pc;
  logic [VA_WIDTH-1:0]      ftq_ifu_next_pc;
  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_idx;
  logic                     ftq_ifu_taken_val;
  logic [FTB_BR_POS_BITS-1:0] ftq_ifu_taken_pos;
  logic                     ftq_ifu_gen;
  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_commit_ptr;
  logic                     ftq_ifu_flush_val;
  logic [FTQ_IDX_BITS-1:0]  ftq_ifu_flush_idx;
  logic                     ifu_ftq_pdwb_val;
  logic [FTQ_IDX_BITS-1:0]  ifu_ftq_pdwb_idx;
  logic                     ifu_ftq_pdwb_gen;
  ftq_pd_info_t             ifu_ftq_pd [0:FTQ_PD_WIDTH-1];
  logic [FTQ_PD_WIDTH-1:0]  ifu_ftq_pd_range;
  logic                     ifu_ftq_cfi_val;
  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_cfi_pos;
  logic                     ifu_ftq_mis_val;
  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_mis_pos;
  logic [VA_WIDTH-1:0]      ifu_ftq_target;
  logic                     ifu_ftq_fault_val;
  logic [FTQ_PD_POS_BITS-1:0] ifu_ftq_fault_pos;
  logic                     ifu_l1i_req_val;
  logic                     ifu_l1i_req_rdy;
  logic [REQ_ID_BITS-1:0]   ifu_l1i_req_id;
  logic [PA_WIDTH-1:0]      ifu_l1i_req_paddr;
  logic                     ifu_l1i_req_prefetch;
  logic                     l1i_ifu_rsp_val;
  logic [REQ_ID_BITS-1:0]   l1i_ifu_rsp_id;
  logic [L1I_LINE_BITS-1:0] l1i_ifu_rsp_data;
  logic                     l1i_ifu_rsp_err;
  logic                     ifu_itlb_req_val;
  logic                     ifu_itlb_req_rdy;
  logic [LKV-1:0]           ifu_itlb_vpn;
  logic                     ifu_itlb_tag;
  logic                     itlb_ifu_rsp_val;
  logic                     itlb_ifu_tag;
  logic [1:0]               itlb_ifu_status;
  logic [PPN_WIDTH-1:0]     itlb_ifu_ppn;
  logic [CAUSE_WIDTH-1:0]   itlb_ifu_cause;
  logic [GPA_WIDTH-1:0]     itlb_ifu_gpa;
  logic [PMA_WIDTH-1:0]     itlb_ifu_pma;
  logic                     ifu_ibuf_val;
  logic [FTQ_PD_WIDTH-1:0]  ifu_ibuf_en;
  ifu_pd_pkt_t              ifu_ibuf_slot [0:FTQ_PD_WIDTH-1];
  logic                     ibuf_ifu_rdy;

  ifu dut (.*);

  // ---- test bookkeeping ---------------------------------------------
  int pass_cnt;
  int fail_cnt;
  string tname;

  task automatic chk(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: [%s] %s", tname, nm);
    end
  endtask

  // =================================================================
  // Memory image and page map.
  // =================================================================
  typedef struct {
    logic [PPN_WIDTH-1:0] ppn;
    ifu_fault_e           fault;
    logic [GPA_WIDTH-1:0] gpa;
    int                   misses;
  } page_t;

  page_t                 pmap   [logic [LKV-1:0]];
  logic [15:0]           mem_hw [logic [PA_WIDTH-2:0]];
  logic [31:0]           exp_of [logic [PA_WIDTH-2:0]];
  logic                  err_ln [logic [PA_WIDTH-L1I_OFFSET_BITS-1:0]];

  localparam logic [15:0] FILL_HW  = 16'h0001;        // c.nop
  localparam logic [31:0] FILL_EXP = 32'h0000_0013;   // addi x0,x0,0

  function automatic logic [LKV-1:0] vpn_of(
      input logic [VA_WIDTH-1:0] va);
    return va[VA_WIDTH-1:12];
  endfunction

  // This file's translation. Unmapped pages are identity-mapped.
  function automatic void xlate_va(input  logic [VA_WIDTH-1:0] va,
                                   output ifu_fault_e          f,
                                   output logic [PA_WIDTH-1:0] pa,
                                   output logic [GPA_WIDTH-1:0] gpa);
    logic [LKV-1:0] v;
    v   = vpn_of(va);
    gpa = '0;
    if (pmap.exists(v)) begin
      f   = pmap[v].fault;
      gpa = pmap[v].gpa;
      pa  = {pmap[v].ppn, va[11:0]};
    end else begin
      f  = IFU_FAULT_NONE;
      pa = {v[PPN_WIDTH-1:0], va[11:0]};
    end
  endfunction

  function automatic logic [15:0] rd_hw(input logic [PA_WIDTH-1:0] pa);
    return mem_hw.exists(pa[PA_WIDTH-1:1]) ? mem_hw[pa[PA_WIDTH-1:1]]
                                           : FILL_HW;
  endfunction

  function automatic logic [31:0] rd_exp(input logic [PA_WIDTH-1:0] pa);
    return exp_of.exists(pa[PA_WIDTH-1:1]) ? exp_of[pa[PA_WIDTH-1:1]]
                                           : FILL_EXP;
  endfunction

  task automatic map_page(input logic [VA_WIDTH-1:0] va,
                          input logic [PPN_WIDTH-1:0] ppn,
                          input ifu_fault_e f, input int misses,
                          input logic [GPA_WIDTH-1:0] gpa);
    page_t p;
    p.ppn    = ppn;
    p.fault  = f;
    p.gpa    = gpa;
    p.misses = misses;
    pmap[vpn_of(va)] = p;
  endtask

  // Instructions are written through the page map; the page must be
  // non-faulting. exp_of records each start's expansion.
  task automatic put32(input logic [VA_WIDTH-1:0] va,
                       input logic [31:0] w);
    ifu_fault_e f; logic [PA_WIDTH-1:0] pa; logic [GPA_WIDTH-1:0] g;
    logic [PA_WIDTH-1:0] pa2;
    xlate_va(va, f, pa, g);
    mem_hw[pa[PA_WIDTH-1:1]] = w[15:0];
    exp_of[pa[PA_WIDTH-1:1]] = w;
    xlate_va(va + VA_WIDTH'(2), f, pa2, g);
    mem_hw[pa2[PA_WIDTH-1:1]] = w[31:16];
  endtask

  task automatic put16(input logic [VA_WIDTH-1:0] va,
                       input logic [15:0] c, input logic [31:0] e);
    ifu_fault_e f; logic [PA_WIDTH-1:0] pa; logic [GPA_WIDTH-1:0] g;
    xlate_va(va, f, pa, g);
    mem_hw[pa[PA_WIDTH-1:1]] = c;
    exp_of[pa[PA_WIDTH-1:1]] = e;
  endtask

  // Encoders.
  function automatic logic [31:0] enc_jal(input logic [4:0] rd,
                                          input int imm);
    logic [20:0] o;
    o = 21'(imm);
    return {o[20], o[10:1], o[11], o[19:12], rd, 7'b1101111};
  endfunction

  function automatic logic [31:0] enc_beq(input int imm);
    logic [12:0] o;
    o = 13'(imm);
    return {o[12], o[10:5], 5'd0, 5'd10, 3'b000, o[4:1], o[11],
            7'b1100011};
  endfunction

  localparam logic [31:0] ADDI = 32'h0010_0093;   // addi x1,x0,1

  // =================================================================
  // The FTQ model.
  // =================================================================
  typedef struct packed {
    logic [FTQ_IDX_BITS-1:0]    idx;
    logic                       gen;
    logic [VA_WIDTH-1:0]        start_pc;
    logic [VA_WIDTH-1:0]        next_pc;
    logic                       taken_val;
    logic [FTB_BR_POS_BITS-1:0] taken_pos;
  } blk_t;

  blk_t blk [0:MAXB-1];
  int   nblk;
  int   xptr;
  int   fptr;
  logic run;
  logic flush_req;
  int   n_xlate_acc;
  int   n_req_acc;
  // BP-118. The flush: the list position of F and its index, the
  // commit pointer, a fetch hold, and the predecode redirect the FTQ
  // derives from a writeback (ftq_ifu_interfaces.md 7 W3: F = K+1).
  int                      fl_pos;
  logic [FTQ_IDX_BITS-1:0] fl_idx;
  logic [FTQ_IDX_BITS-1:0] cptr;
  int                      idx0;
  logic                    fetch_hold;
  logic                    pd_auto;
  logic [FTQ_IDX_BITS-1:0] pd_k_idx;
  int                      pd_k_pos;
  logic                    pd_fire;
  int                      n_flush;

  always_comb begin : ftq_pd
    pd_fire = pd_auto && ifu_ftq_pdwb_val && ifu_ftq_mis_val &&
              (ifu_ftq_pdwb_idx == pd_k_idx);
  end

  always_comb begin : ftq_drive
    ftq_ifu_xlate_val  = run && (xptr < nblk);
    ftq_ifu_xlate_pc   = blk[(xptr < nblk) ? xptr : 0].start_pc;
    ftq_ifu_xlate_idx  = blk[(xptr < nblk) ? xptr : 0].idx;
    ftq_ifu_req_val    = run && (fptr < xptr) && !fetch_hold;
    ftq_ifu_start_pc   = blk[(fptr < nblk) ? fptr : 0].start_pc;
    ftq_ifu_next_pc    = blk[(fptr < nblk) ? fptr : 0].next_pc;
    ftq_ifu_idx        = blk[(fptr < nblk) ? fptr : 0].idx;
    ftq_ifu_taken_val  = blk[(fptr < nblk) ? fptr : 0].taken_val;
    ftq_ifu_taken_pos  = blk[(fptr < nblk) ? fptr : 0].taken_pos;
    ftq_ifu_gen        = blk[(fptr < nblk) ? fptr : 0].gen;
    ftq_ifu_commit_ptr = cptr;
    ftq_ifu_flush_val  = flush_req || pd_fire;
    ftq_ifu_flush_idx  = pd_fire ? (pd_k_idx + FTQ_IDX_BITS'(1)) : fl_idx;
  end

  always @(posedge clk) begin : ftq_model
    if (!rstn) begin
      xptr <= 0;
      fptr <= 0;
    end else if (ftq_ifu_flush_val) begin
      // 5.5 R1: each position moves back to F if it was past it. The
      // handshakes of the flush cycle are discarded.
      n_flush <= n_flush + 1;
      if (xptr > (pd_fire ? pd_k_pos + 1 : fl_pos))
        xptr <= pd_fire ? pd_k_pos + 1 : fl_pos;
      if (fptr > (pd_fire ? pd_k_pos + 1 : fl_pos))
        fptr <= pd_fire ? pd_k_pos + 1 : fl_pos;
    end else begin
      if (ftq_ifu_xlate_val && ftq_ifu_xlate_rdy) begin
        xptr        <= xptr + 1;
        n_xlate_acc <= n_xlate_acc + 1;
      end
      if (ftq_ifu_req_val && ftq_ifu_req_rdy) begin
        fptr      <= fptr + 1;
        n_req_acc <= n_req_acc + 1;
      end
    end
  end

  // =================================================================
  // The ITLB model.
  // =================================================================
  int   itlb_lat [0:1];
  logic itlb_stall_odd;            // ready low on odd cycles
  logic p_val [0:1];
  int   p_cnt [0:1];
  logic [LKV-1:0] p_vpn [0:1];
  int   n_itlb_req;
  // Every lookup the ITLB took, in order: its VPN and tag.
  logic [LKV-1:0] lk_vpn [0:255];
  logic           lk_tag [0:255];
  int             lk_cyc [0:255];
  // Every response presented, in order: its tag and cycle.
  int             n_itlb_rsp;
  logic           rs_tag [0:255];
  int             rs_cyc [0:255];
  int   cyc;

  assign ifu_itlb_req_rdy = rstn && !(itlb_stall_odd && cyc[0]);

  // The models are timing processes, not clocked always blocks: their
  // bookkeeping is blocking by design and the DUT-facing outputs are
  // nonblocking.
  // The models are timing processes: each samples the DUT at the
  // clock edge, waits #1, then updates its own state and the DUT's
  // inputs with blocking assignments, so nothing races the DUT's
  // flops at the edge.
  initial begin : itlb_model
    int r;
    logic [LKV-1:0] v;
    page_t pg;
    logic s_fire;
    logic s_tag;
    logic [LKV-1:0] s_vpn;
    itlb_ifu_rsp_val = 1'b0;
    itlb_ifu_tag     = 1'b0;
    itlb_ifu_status  = 2'b00;
    itlb_ifu_ppn     = '0;
    itlb_ifu_cause   = '0;
    itlb_ifu_gpa     = '0;
    itlb_ifu_pma     = '0;
    forever begin
      @(posedge clk);
      s_fire = rstn && ifu_itlb_req_val && ifu_itlb_req_rdy;
      s_tag  = ifu_itlb_tag;
      s_vpn  = ifu_itlb_vpn;
      #1;
      itlb_ifu_rsp_val = 1'b0;
      if (!rstn) begin
        for (int t = 0; t < 2; t++) begin
          p_val[t] = 1'b0;
          p_cnt[t] = 0;
        end
      end else begin
        r = -1;
        for (int t = 0; t < 2; t++) begin
          if (p_val[t] && (p_cnt[t] <= 1) && (r < 0)) r = t;
        end
        for (int t = 0; t < 2; t++) begin
          if (p_val[t] && (p_cnt[t] > 1)) p_cnt[t] = p_cnt[t] - 1;
        end
        if (r >= 0) begin
          v = p_vpn[r];
          p_val[r] = 1'b0;
          itlb_ifu_rsp_val = 1'b1;
          itlb_ifu_tag     = r[0];
          if (n_itlb_rsp < 256) begin
            rs_tag[n_itlb_rsp] = r[0];
            rs_cyc[n_itlb_rsp] = cyc;
          end
          n_itlb_rsp = n_itlb_rsp + 1;
          itlb_ifu_cause   = '0;
          itlb_ifu_gpa     = '0;
          itlb_ifu_ppn     = v[PPN_WIDTH-1:0];
          itlb_ifu_pma     = 4'b1111;
          itlb_ifu_status  = 2'b00;
          if (pmap.exists(v)) begin
            pg = pmap[v];
            if (pg.misses > 0) begin
              pg.misses = pg.misses - 1;
              pmap[v]   = pg;
              itlb_ifu_status = 2'b01;
            end else if (pg.fault != IFU_FAULT_NONE) begin
              itlb_ifu_status = 2'b10;
              itlb_ifu_ppn    = '0;
              case (pg.fault)
                IFU_FAULT_ACCESS: itlb_ifu_cause = CAUSE_WIDTH'(1);
                IFU_FAULT_PAGE:   itlb_ifu_cause = CAUSE_WIDTH'(12);
                default: begin
                  itlb_ifu_cause = CAUSE_WIDTH'(20);
                  itlb_ifu_gpa   = pg.gpa;
                end
              endcase
            end else begin
              itlb_ifu_ppn = pg.ppn;
            end
          end
        end
        if (s_fire) begin
          p_val[s_tag] = 1'b1;
          p_cnt[s_tag] = itlb_lat[s_tag];
          p_vpn[s_tag] = s_vpn;
          if (n_itlb_req < 256) begin
            lk_vpn[n_itlb_req] = s_vpn;
            lk_tag[n_itlb_req] = s_tag;
            lk_cyc[n_itlb_req] = cyc;
          end
          n_itlb_req   = n_itlb_req + 1;
        end
      end
    end
  end

  // =================================================================
  // The L1I model.
  // =================================================================
  typedef enum int { ORD_FWD, ORD_REV, ORD_ODD, ORD_RAND } ord_e;

  int    l1i_lat;
  int    l1i_hold_k;        // 0: no hold; else hold until K pending
  ord_e  l1i_ord;
  logic  l1i_releasing;
  logic  q_val  [0:MAX_OUTSTANDING-1];
  logic [REQ_ID_BITS-1:0] q_id [0:MAX_OUTSTANDING-1];
  logic [PA_WIDTH-1:0]    q_pa [0:MAX_OUTSTANDING-1];
  int    q_due  [0:MAX_OUTSTANDING-1];
  int    q_seq  [0:MAX_OUTSTANDING-1];
  int    q_key  [0:MAX_OUTSTANDING-1];
  int    l1i_seq;
  int    n_l1i_req;
  int    max_pend;
  logic [PA_WIDTH-1:0] req_pa_log [0:255];
  // BP-118. Hold every response, or those of the named lines, and
  // hold the request ready low. A response log: the id and the cycle.
  logic  l1i_hold_all;
  logic  l1i_hold_ln [logic [PA_WIDTH-L1I_OFFSET_BITS-1:0]];
  logic  l1i_rdy_low;
  int    n_l1i_rsp;
  logic [REQ_ID_BITS-1:0] rsp_id_log [0:255];

  assign ifu_l1i_req_rdy = rstn && !l1i_rdy_low;

  function automatic logic [L1I_LINE_BITS-1:0] line_data(
      input logic [PA_WIDTH-1:0] pa);
    logic [L1I_LINE_BITS-1:0] d;
    for (int h = 0; h < L1I_LINE_BYTES / 2; h++) begin
      d[16*h +: 16] = rd_hw(pa + PA_WIDTH'(2 * h));
    end
    return d;
  endfunction

  function automatic int npend();
    int n;
    n = 0;
    for (int i = 0; i < MAX_OUTSTANDING; i++) if (q_val[i]) n++;
    return n;
  endfunction

  initial begin : l1i_model
    int pick;
    int best;
    int k;
    logic s_fire;
    logic [REQ_ID_BITS-1:0] s_id;
    logic [PA_WIDTH-1:0]    s_pa;
    int idle;
    idle             = 0;
    l1i_ifu_rsp_val  = 1'b0;
    l1i_ifu_rsp_id   = '0;
    l1i_ifu_rsp_data = '0;
    l1i_ifu_rsp_err  = 1'b0;
    forever begin
      @(posedge clk);
      s_fire = rstn && ifu_l1i_req_val && ifu_l1i_req_rdy;
      s_id   = ifu_l1i_req_id;
      s_pa   = ifu_l1i_req_paddr;
      #1;
      l1i_ifu_rsp_val = 1'b0;
      if (!rstn) begin
        l1i_releasing = 1'b0;
        for (int i = 0; i < MAX_OUTSTANDING; i++) q_val[i] = 1'b0;
      end else begin
        // Release at K pending, or when the requests have stopped with
        // fewer than K held (the tail of the test's traffic).
        idle = s_fire ? 0 : idle + 1;
        if ((l1i_hold_k > 0) &&
            ((npend() >= l1i_hold_k) || ((npend() > 0) && (idle > 20))))
          l1i_releasing = 1'b1;
        if ((l1i_hold_k > 0) && (npend() == 0))
          l1i_releasing = 1'b0;
        pick = -1;
        best = 0;
        if ((l1i_hold_k == 0) || l1i_releasing) begin
          for (int i = 0; i < MAX_OUTSTANDING; i++) begin
            if (q_val[i] && (q_due[i] <= cyc) && !l1i_hold_all &&
                !l1i_hold_ln.exists(q_pa[i][PA_WIDTH-1:L1I_OFFSET_BITS]))
            begin
              case (l1i_ord)
                ORD_REV:  k = -q_seq[i];
                ORD_ODD:  k = (q_seq[i] % 2 == 1) ? q_seq[i]
                                                  : q_seq[i] + 100000;
                ORD_RAND: k = q_key[i];
                default:  k = q_seq[i];
              endcase
              if ((pick < 0) || (k < best)) begin
                pick = i;
                best = k;
              end
            end
          end
        end
        if (pick >= 0) begin
          q_val[pick]      = 1'b0;
          l1i_ifu_rsp_val  = 1'b1;
          l1i_ifu_rsp_id   = q_id[pick];
          l1i_ifu_rsp_data = line_data(q_pa[pick]);
          l1i_ifu_rsp_err  =
            err_ln.exists(q_pa[pick][PA_WIDTH-1:L1I_OFFSET_BITS]);
          if (n_l1i_rsp < 256) rsp_id_log[n_l1i_rsp] = q_id[pick];
          n_l1i_rsp = n_l1i_rsp + 1;
        end
        if (s_fire) begin
          for (int i = 0; i < MAX_OUTSTANDING; i++) begin
            if (!q_val[i]) begin
              q_val[i] = 1'b1;
              q_id[i]  = s_id;
              q_pa[i]  = s_pa;
              q_due[i] = cyc + l1i_lat;
              q_seq[i] = l1i_seq;
              q_key[i] = $urandom_range(0, 1000);
              break;
            end
          end
          if (n_l1i_req < 256) req_pa_log[n_l1i_req] = s_pa;
          l1i_seq   = l1i_seq + 1;
          n_l1i_req = n_l1i_req + 1;
        end
        if (npend() > max_pend) max_pend = npend();
      end
    end
  end

  always @(posedge clk) cyc <= rstn ? cyc + 1 : 0;

  // =================================================================
  // The ibuf model, and the capture of what crosses the boundaries.
  // =================================================================
  int   ib_occ;
  int   ib_drain;
  logic ib_force_stall;
  int   nrx;
  int   nwb;
  logic [NPD-1:0] rx_en   [0:MAXB-1];
  ifu_pd_pkt_t    rx_slot [0:MAXB-1][0:NPD-1];
  logic [FTQ_IDX_BITS-1:0] wb_idx [0:MAXB-1];
  logic           wb_gen  [0:MAXB-1];
  ftq_pd_info_t   wb_pd   [0:MAXB-1][0:NPD-1];
  logic [NPD-1:0] wb_rng  [0:MAXB-1];
  logic           wb_cfiv [0:MAXB-1];
  logic [3:0]     wb_cfip [0:MAXB-1];
  logic           wb_misv [0:MAXB-1];
  logic [3:0]     wb_misp [0:MAXB-1];
  logic [VA_WIDTH-1:0] wb_tgt [0:MAXB-1];
  logic           wb_fltv [0:MAXB-1];
  logic [3:0]     wb_fltp [0:MAXB-1];
  int   n_stall_cyc;
  int   n_hold_ok;
  int   n_hold_bad;

  assign ibuf_ifu_rdy = rstn && !ib_force_stall && ((IBCAP - ib_occ) >= NPD);

  // IB-7 at the boundary: the block refused last cycle is offered
  // again unchanged.
  logic                    h_refused;
  logic [NPD-1:0]          h_en;
  ifu_pd_pkt_t             h_slot [0:NPD-1];

  initial begin : ibuf_model
    int n;
    logic same;
    ib_occ    = 0;
    h_refused = 1'b0;
    forever begin
      @(posedge clk);
      // Capture at the edge: the DUT's outputs are this cycle's.
      n = 0;
      if (rstn) begin
        if (ifu_ibuf_val && ibuf_ifu_rdy) begin
          for (int i = 0; i < NPD; i++) if (ifu_ibuf_en[i]) n++;
          if (nrx < MAXB) begin
            rx_en[nrx] = ifu_ibuf_en;
            for (int i = 0; i < NPD; i++)
              rx_slot[nrx][i] = ifu_ibuf_slot[i];
          end
          nrx = nrx + 1;
        end
        if (h_refused && !ftq_ifu_flush_val) begin
          same = ifu_ibuf_val && (ifu_ibuf_en == h_en);
          for (int i = 0; i < NPD; i++)
            if (ifu_ibuf_slot[i] != h_slot[i]) same = 1'b0;
          if (same) n_hold_ok++;
          else      n_hold_bad++;
        end
        if (ifu_ibuf_val && !ibuf_ifu_rdy) n_stall_cyc++;
        h_refused = ifu_ibuf_val && !ibuf_ifu_rdy;
        h_en      = ifu_ibuf_en;
        for (int i = 0; i < NPD; i++) h_slot[i] = ifu_ibuf_slot[i];

        if (ifu_ftq_pdwb_val) begin
          if (nwb < MAXB) begin
            wb_idx[nwb]  = ifu_ftq_pdwb_idx;
            wb_gen[nwb]  = ifu_ftq_pdwb_gen;
            for (int i = 0; i < NPD; i++) wb_pd[nwb][i] = ifu_ftq_pd[i];
            wb_rng[nwb]  = ifu_ftq_pd_range;
            wb_cfiv[nwb] = ifu_ftq_cfi_val;
            wb_cfip[nwb] = ifu_ftq_cfi_pos;
            wb_misv[nwb] = ifu_ftq_mis_val;
            wb_misp[nwb] = ifu_ftq_mis_pos;
            wb_tgt[nwb]  = ifu_ftq_target;
            wb_fltv[nwb] = ifu_ftq_fault_val;
            wb_fltp[nwb] = ifu_ftq_fault_pos;
          end
          nwb = nwb + 1;
        end
      end else begin
        h_refused = 1'b0;
      end
      #1;
      // ibuf_ifu_rdy follows the occupancy, so it moves after the edge.
      if (!rstn) ib_occ = 0;
      else ib_occ = ((ib_occ + n - ib_drain) < 0) ? 0
                                                  : (ib_occ + n - ib_drain);
    end
  end

  // =================================================================
  // The reference: one block, from the memory image and the request.
  // =================================================================
  typedef struct {
    logic [NPD-1:0]      en;
    logic [NPD-1:0]      valid;
    logic [NPD-1:0]      rng;
    logic [31:0]         instr [0:NPD-1];
    logic [VA_WIDTH-1:0] pc    [0:NPD-1];
    ifu_fault_e          flt   [0:NPD-1];
    logic [VA_WIDTH-1:0] fva   [0:NPD-1];
    logic [GPA_WIDTH-1:0] fgpa [0:NPD-1];
    logic [NPD-1:0]      rvc;
    logic [1:0]          br    [0:NPD-1];
    logic [NPD-1:0]      call;
    logic [NPD-1:0]      ret;
    logic [VA_WIDTH-1:0] tgt   [0:NPD-1];
    logic                cfi_val;
    int                  cfi_pos;
    logic                mis_val;
    int                  mis_pos;
    logic                tgt_cmp;   // the writeback target is defined
    logic [VA_WIDTH-1:0] wb_tgt;
    logic                flt_val;
    int                  flt_pos;
  } exp_t;

  logic                ref_tail_val;
  logic [VA_WIDTH-1:0] ref_tail_pc;
  // BP-118. The list position of the first block of a corrected
  // stream: the reference straddle state does not carry into it,
  // because the unit drops the straddle with the block after the one
  // that set it. -1 for none.
  int                  ref_cut_pos;

  function automatic logic lnk(input logic [4:0] r);
    return (r == 5'd1) || (r == 5'd5);
  endfunction

  task automatic ref_block(input blk_t b, output exp_t e);
    logic [15:0]          hw  [0:NPOS-1];
    ifu_fault_e           hf  [0:NPOS-1];
    logic [GPA_WIDTH-1:0] hg  [0:NPOS-1];
    logic [PA_WIDTH-1:0]  hpa [0:NPOS-1];
    logic [VA_WIDTH-1:0]  va;
    logic [PA_WIDTH-1:0]  pa;
    logic [NPD-1:0]       st;
    logic [NPD-1:0]       base;
    logic [VA_WIDTH-1:0]  d;
    int                   lim;
    int                   p;
    int                   last;
    logic [31:0]          w;
    logic [6:0]           op;
    logic [4:0]           rd;
    logic [4:0]           rs1;
    logic [12:0]          bi;
    logic [20:0]          ji;

    // Halfwords, through this file's page map. A memory-side error on
    // the line is an access fault (IF-15).
    for (int i = 0; i < NPOS; i++) begin
      va = b.start_pc + VA_WIDTH'(2 * i);
      xlate_va(va, hf[i], pa, hg[i]);
      hpa[i] = pa;
      hw[i]  = rd_hw(pa);
      if ((hf[i] == IFU_FAULT_NONE) &&
          err_ln.exists(pa[PA_WIDTH-1:L1I_OFFSET_BITS]))
        hf[i] = IFU_FAULT_ACCESS;
    end

    // Base range: the predicted taken position, else the block end.
    d   = b.next_pc - b.start_pc;
    lim = ((d != '0) && (d <= VA_WIDTH'(32))) ? int'(d) : 32;
    for (int i = 0; i < NPD; i++) begin
      base[i] = b.taken_val ? (i <= int'(b.taken_pos)) : (2 * i < lim);
      e.pc[i] = b.start_pc + VA_WIDTH'(2 * i);
    end

    // Sequential start walk; stop at the first faulting instruction.
    st        = '0;
    e.flt_val = 1'b0;
    e.flt_pos = 0;
    for (int i = 0; i < NPD; i++) begin
      e.flt[i]  = IFU_FAULT_NONE;
      e.fva[i]  = '0;
      e.fgpa[i] = '0;
      e.rvc[i]  = (hw[i][1:0] != 2'b11);
    end
    p = (ref_tail_val && (b.start_pc == ref_tail_pc)) ? 1 : 0;
    while (p < NPD) begin
      st[p] = 1'b1;
      if (hf[p] != IFU_FAULT_NONE) begin
        e.flt[p] = hf[p];
        e.fva[p] = e.pc[p];
        e.fgpa[p] = (hf[p] == IFU_FAULT_GUEST_PAGE) ? hg[p] : '0;
      end else if (!e.rvc[p] && (hf[p+1] != IFU_FAULT_NONE)) begin
        e.flt[p] = hf[p+1];
        e.fva[p] = e.pc[p] + VA_WIDTH'(2);
        e.fgpa[p] = (hf[p+1] == IFU_FAULT_GUEST_PAGE) ? hg[p+1] : '0;
      end
      if ((e.flt[p] != IFU_FAULT_NONE) && base[p] && !e.flt_val) begin
        e.flt_val = 1'b1;
        e.flt_pos = p;
      end
      if (e.flt[p] != IFU_FAULT_NONE) break;
      p += e.rvc[p] ? 1 : 2;
    end

    for (int i = 0; i < NPD; i++) begin
      e.rng[i]   = base[i] && (!e.flt_val || (i <= e.flt_pos));
      e.valid[i] = st[i] && e.rng[i];
      e.br[i]    = 2'b00;
      e.call[i]  = 1'b0;
      e.ret[i]   = 1'b0;
      e.tgt[i]   = '0;
      e.instr[i] = '0;
      if (e.valid[i] && (e.flt[i] == IFU_FAULT_NONE)) begin
        w  = rd_exp(hpa[i]);
        e.instr[i] = w;
        op  = w[6:0];
        rd  = w[11:7];
        rs1 = w[19:15];
        bi  = {w[31], w[7], w[30:25], w[11:8], 1'b0};
        ji  = {w[31], w[19:12], w[20], w[30:21], 1'b0};
        if ((op == 7'b1100011) && (w[14:13] != 2'b01)) begin
          e.br[i]  = 2'b01;
          e.tgt[i] = e.pc[i] + {{(VA_WIDTH-13){bi[12]}}, bi};
        end else if (op == 7'b1101111) begin
          e.br[i]   = 2'b10;
          e.call[i] = lnk(rd);
          e.tgt[i]  = e.pc[i] + {{(VA_WIDTH-21){ji[20]}}, ji};
        end else if ((op == 7'b1100111) && (w[14:12] == 3'b000)) begin
          e.br[i]   = 2'b11;
          e.call[i] = lnk(rd);
          e.ret[i]  = lnk(rs1) && (!lnk(rd) || (rd != rs1));
        end
      end
    end

    e.cfi_val = 1'b0;
    e.cfi_pos = 0;
    for (int i = 0; i < NPD; i++) begin
      if (!e.cfi_val && e.valid[i] && (e.br[i] != 2'b00)) begin
        e.cfi_val = 1'b1;
        e.cfi_pos = i;
      end
    end

    // M1 to M4 (ftq_ifu_interfaces.md 6). M1 is the first JAL, call
    // or not, BEFORE the predicted taken position, or anywhere when
    // none is predicted; never a JALR. It is earlier in program order
    // than anything at the taken position, so it is tested first.
    // CHANGED BY BP-117 (TD#146): M1 was tested only when no taken
    // position was predicted.
    e.mis_val = 1'b0;
    e.mis_pos = 0;
    e.tgt_cmp = 1'b0;
    e.wb_tgt  = '0;
    for (int i = 0; i < NPD; i++) begin
      if (!e.mis_val && e.valid[i] && (e.br[i] == 2'b10) &&
          (!b.taken_val || (i < int'(b.taken_pos)))) begin
        e.mis_val = 1'b1;                                           // M1
        e.mis_pos = i;
      end
    end
    if (e.mis_val) begin
      // M1 found; nothing at the taken position is on the path.
    end else if (b.taken_val) begin
      p = int'(b.taken_pos);
      e.mis_pos = p;
      if (!e.rng[p])                              e.mis_val = 1'b1; // M4
      else if (!e.valid[p])                       e.mis_val = 1'b1; // M2
      else if (e.flt[p] != IFU_FAULT_NONE)        e.mis_val = 1'b0;
      else if (e.br[p] == 2'b00)                  e.mis_val = 1'b1; // M2
      else if ((e.br[p] != 2'b11) && (e.tgt[p] != b.next_pc))
                                                  e.mis_val = 1'b1; // M3
    end
    if (e.mis_val && (e.br[e.mis_pos] == 2'b01 || e.br[e.mis_pos] == 2'b10))
    begin
      e.tgt_cmp = 1'b1;
      e.wb_tgt  = e.tgt[e.mis_pos];
    end else if (!e.mis_val && e.cfi_val && (e.br[e.cfi_pos] != 2'b11))
    begin
      e.tgt_cmp = 1'b1;
      e.wb_tgt  = e.tgt[e.cfi_pos];
    end

    for (int i = 0; i < NPD; i++) begin
      e.en[i] = e.valid[i] && (!e.mis_val || (i <= e.mis_pos));
    end

    // The straddle into the next block.
    last = -1;
    for (int i = 0; i < NPD; i++) if (e.valid[i]) last = i;
    ref_tail_val = !b.taken_val && !e.mis_val && !e.flt_val &&
                   (last >= 0) && !e.rvc[last] &&
                   ((e.pc[last] + VA_WIDTH'(2)) == b.next_pc);
    ref_tail_pc  = b.next_pc;
  endtask

  // Compare block k as delivered and written back.
  task automatic check_block(input int k);
    exp_t        e;
    ifu_pd_pkt_t s;
    logic        ok;
    string       why;
    ref_block(blk[k], e);
    ok  = 1'b1;
    why = "";
    if (rx_en[k] != e.en) begin
      ok = 1'b0;
      why = $sformatf("en got %04h exp %04h", rx_en[k], e.en);
    end
    for (int i = 0; i < NPD; i++) begin
      s = rx_slot[k][i];
      if (s.valid !== 1'b0) begin
        ok = 1'b0; why = $sformatf("%s slot %0d valid driven", why, i);
      end
      if (e.en[i]) begin
        if ((s.start_pc != e.pc[i]) || (s.pos != 4'(i)) ||
            (s.ftq_idx != blk[k].idx) || (s.fault_cause != e.flt[i])) begin
          ok = 1'b0;
          why = $sformatf("%s slot %0d pc/pos/idx/cause", why, i);
        end
        if (e.flt[i] == IFU_FAULT_NONE) begin
          if ((s.instr != e.instr[i]) || (s.is_rvc != e.rvc[i]) ||
              (s.br_type != e.br[i]) || (s.is_call != e.call[i]) ||
              (s.is_ret != e.ret[i]) || s.is_vsetvl || s.needs_vtype)
          begin
            ok = 1'b0;
            why = $sformatf("%s slot %0d instr %08h/%08h class", why, i,
                            s.instr, e.instr[i]);
          end
        end else if ((s.fault_va != e.fva[i]) ||
                     (s.fault_gpa != e.fgpa[i]) || (s.br_type != 2'b00))
        begin
          ok = 1'b0;
          why = $sformatf("%s slot %0d fault_va %011h exp %011h gpa", why,
                          i, s.fault_va, e.fva[i]);
        end
      end
    end
    chk($sformatf("block %0d slots %s", k, why), ok);

    ok  = (wb_idx[k] == blk[k].idx) && (wb_gen[k] == blk[k].gen) &&
          (wb_rng[k] == e.rng) && (wb_cfiv[k] == e.cfi_val) &&
          (!e.cfi_val || (int'(wb_cfip[k]) == e.cfi_pos)) &&
          (wb_misv[k] == e.mis_val) &&
          (!e.mis_val || (int'(wb_misp[k]) == e.mis_pos)) &&
          (wb_fltv[k] == e.flt_val) &&
          (!e.flt_val || (int'(wb_fltp[k]) == e.flt_pos)) &&
          (!e.tgt_cmp || (wb_tgt[k] == e.wb_tgt));
    for (int i = 0; i < NPD; i++) begin
      if (wb_pd[k][i].valid != e.valid[i]) ok = 1'b0;
      if (e.valid[i] && (e.flt[i] == IFU_FAULT_NONE) &&
          ((wb_pd[k][i].br_type != e.br[i]) ||
           (wb_pd[k][i].is_call != e.call[i]) ||
           (wb_pd[k][i].is_ret != e.ret[i]) ||
           (wb_pd[k][i].is_rvc != e.rvc[i]))) ok = 1'b0;
    end
    chk($sformatf({"block %0d writeback: rng %04h/%04h ",
                   "mis %0d@%0d/%0d@%0d flt %0d@%0d/%0d@%0d"},
                  k, wb_rng[k], e.rng, wb_misv[k], wb_misp[k], e.mis_val,
                  e.mis_pos, wb_fltv[k], wb_fltp[k], e.flt_val, e.flt_pos),
        ok);
  endtask

  // =================================================================
  // Test scaffolding.
  // =================================================================
  task automatic reset_all();
    rstn           = 1'b0;
    run            = 1'b0;
    flush_req      = 1'b0;
    nblk           = 0;
    nrx            = 0;
    nwb            = 0;
    n_itlb_req     = 0;
    n_l1i_req      = 0;
    n_xlate_acc    = 0;
    n_req_acc      = 0;
    max_pend       = 0;
    l1i_seq        = 0;
    l1i_lat        = 2;
    l1i_hold_k     = 0;
    l1i_ord        = ORD_FWD;
    itlb_lat[0]    = 1;
    itlb_lat[1]    = 1;
    itlb_stall_odd = 1'b0;
    ib_drain       = NPD;
    ib_force_stall = 1'b0;
    n_stall_cyc    = 0;
    n_hold_ok      = 0;
    n_hold_bad     = 0;
    ref_tail_val   = 1'b0;
    ref_tail_pc    = '0;
    fl_pos         = 0;
    fl_idx         = '0;
    ref_cut_pos    = -1;
    cptr           = '0;
    idx0           = 0;
    fetch_hold     = 1'b0;
    pd_auto        = 1'b0;
    pd_k_idx       = '0;
    pd_k_pos       = 0;
    n_flush        = 0;
    n_itlb_rsp     = 0;
    l1i_hold_all   = 1'b0;
    l1i_rdy_low    = 1'b0;
    n_l1i_rsp      = 0;
    l1i_hold_ln.delete();
    pmap.delete();
    mem_hw.delete();
    exp_of.delete();
    err_ln.delete();
    for (int i = 0; i < MAXB; i++) blk[i] = '0;
    repeat (3) @(posedge clk);
    #1;
    rstn = 1'b1;
    @(posedge clk);
    #1;
  endtask

  task automatic add_blk(input logic [VA_WIDTH-1:0] spc,
                         input logic [VA_WIDTH-1:0] npc,
                         input logic tv, input int tp);
    blk[nblk].idx       = FTQ_IDX_BITS'(idx0 + nblk);
    blk[nblk].gen       = nblk[0];
    blk[nblk].start_pc  = spc;
    blk[nblk].next_pc   = npc;
    blk[nblk].taken_val = tv;
    blk[nblk].taken_pos = FTB_BR_POS_BITS'(tp);
    nblk++;
  endtask

  // Run the block list to completion and check blocks k0 onward.
  task automatic run_and_check(input int max_cyc, input int k0 = 0);
    int c;
    run = 1'b1;
    c   = 0;
    while (((nrx < nblk) || (nwb < nblk)) && (c < max_cyc)) begin
      @(posedge clk);
      #1;
      c++;
    end
    repeat (4) @(posedge clk);
    #1;
    chk($sformatf("all %0d blocks delivered (%0d) and written back (%0d)",
                  nblk, nrx, nwb), (nrx == nblk) && (nwb == nblk));
    for (int k = k0; k < nblk && k < nrx && k < nwb; k++) begin
      if (k == ref_cut_pos) ref_tail_val = 1'b0;
      check_block(k);
    end
    run = 1'b0;
  endtask

  // A program of mixed lengths. Each 32-byte chunk from base holds the
  // same twelve instructions, 16 and 32 bits, none crossing the chunk
  // edge, so a block starting at a chunk edge starts on an
  // instruction. The straddle test builds its crossings by hand.
  task automatic fill_mixed(input logic [VA_WIDTH-1:0] base, input int nb);
    int len [0:11];
    logic [VA_WIDTH-1:0] a;
    len = '{1, 2, 1, 1, 2, 1, 2, 2, 1, 1, 1, 1};   // halfwords, sum 16
    for (int c = 0; c < nb / 32; c++) begin
      a = base + VA_WIDTH'(32 * c);
      for (int j = 0; j < 12; j++) begin
        if (len[j] == 1) begin
          put16(a, 16'h0505, 32'h0015_0513);    // c.addi a0,1
          a += 2;
        end else begin
          put32(a, ADDI);
          a += 4;
        end
      end
    end
  endtask

  // =================================================================
  // The tests (B6).
  // =================================================================
  task automatic t_seq_coalesce();
    int lines;
    logic [VA_WIDTH-1:0] b;
    tname = "seq_coalesce";
    $display("-- %s --", tname);
    reset_all();
    b = VA_WIDTH'('h0_8001_0000);
    fill_mixed(b, 512);
    // Eight sequential 32-byte blocks from a line start: four lines,
    // the last block's 17th halfword reaching a fifth.
    for (int i = 0; i < 8; i++)
      add_blk(b + VA_WIDTH'(32 * i), b + VA_WIDTH'(32 * i + 32), 1'b0, 0);
    run_and_check(400);
    lines = 5;
    chk($sformatf("one L1I request per line: %0d requests, %0d lines",
                  n_l1i_req, lines), n_l1i_req == lines);
    for (int i = 0; i < n_l1i_req && i < 256; i++) begin
      chk($sformatf("request %0d is line %0d", i, i),
          req_pa_log[i] == {b[PA_WIDTH-1:0] + PA_WIDTH'(64 * i)});
    end
  endtask

  task automatic t_ooo(input ord_e o, input int k, input string nm);
    logic [VA_WIDTH-1:0] b;
    tname = nm;
    $display("-- %s --", tname);
    reset_all();
    b = VA_WIDTH'('h0_8002_0000);
    fill_mixed(b, 128 * 24);
    l1i_ord    = o;
    l1i_hold_k = k;
    l1i_lat    = 1;
    // Twenty blocks, each in its own line: twenty distinct requests.
    for (int i = 0; i < 20; i++)
      add_blk(b + VA_WIDTH'(128 * i), b + VA_WIDTH'(128 * i + 32),
              1'b0, 0);
    run_and_check(2000);
    chk($sformatf("pending responses reached %0d (target %0d)",
                  max_pend, k), max_pend >= k);
    chk("twenty requests issued", n_l1i_req == 20);
  endtask

  task automatic t_straddle();
    logic [VA_WIDTH-1:0] b;
    tname = "straddle";
    $display("-- %s --", tname);
    reset_all();
    // Across a block: a 32-bit instruction at position 15 of a block
    // starting at a line start; the next block starts on its tail.
    b = VA_WIDTH'('h0_8003_0000);
    fill_mixed(b, 128);
    for (int i = 0; i < 15; i++) put16(b + VA_WIDTH'(2 * i), 16'h0505,
                                       32'h0015_0513);
    put32(b + VA_WIDTH'(30), ADDI);
    add_blk(b, b + VA_WIDTH'(32), 1'b0, 0);
    add_blk(b + VA_WIDTH'(32), b + VA_WIDTH'(64), 1'b0, 0);
    // Across a line: the same at a block starting at offset 32, so
    // position 15 is at 62 and position 16 in the next line.
    b = VA_WIDTH'('h0_8003_1000);
    fill_mixed(b, 256);
    for (int i = 0; i < 15; i++) put16(b + VA_WIDTH'(32 + 2 * i), 16'h0505,
                                       32'h0015_0513);
    put32(b + VA_WIDTH'(62), enc_jal(5'd0, 64));
    add_blk(b + VA_WIDTH'(32), b + VA_WIDTH'(64), 1'b1, 15);
    blk[nblk-1].next_pc = b + VA_WIDTH'(62 + 64);   // the JAL's target
    add_blk(b + VA_WIDTH'(126), b + VA_WIDTH'(158), 1'b0, 0);
    // Across a page: position 15 at 0xFFE, position 16 at the next
    // page, which maps to a different physical page.
    b = VA_WIDTH'('h0_8004_0FE0);
    map_page(b, 24'h00_0A00, IFU_FAULT_NONE, 0, '0);
    map_page(b + VA_WIDTH'(32), 24'h00_0B37, IFU_FAULT_NONE, 0, '0);
    for (int i = 0; i < 15; i++) put16(b + VA_WIDTH'(2 * i), 16'h0505,
                                       32'h0015_0513);
    put32(b + VA_WIDTH'(30), 32'h0020_0113);         // addi x2,x0,2
    fill_mixed(b + VA_WIDTH'(34), 64);
    add_blk(b, b + VA_WIDTH'(32), 1'b0, 0);
    add_blk(b + VA_WIDTH'(32), b + VA_WIDTH'(64), 1'b0, 0);
    run_and_check(600);
    chk("block 1 begins on the straddle tail (position 0 masked)",
        (nrx > 1) && !rx_en[1][0] && rx_en[1][1]);
    chk("block 5 begins on the page-crossing tail",
        (nrx > 5) && !rx_en[5][0] && rx_en[5][1]);
    chk("the page-crossing instruction is delivered whole from block 4",
        (nrx > 4) && rx_en[4][15] && (rx_slot[4][15].instr == 32'h0020_0113));
  endtask

  task automatic t_page_faults();
    logic [VA_WIDTH-1:0] b;
    tname = "page_faults";
    $display("-- %s --", tname);
    reset_all();
    // A crossing block whose SECOND page faults (IFU-25): a 32-bit
    // instruction at 0xFFE straddles into it.
    b = VA_WIDTH'('h0_8005_0FE0);
    map_page(b, 24'h00_0C00, IFU_FAULT_NONE, 0, '0);
    map_page(b + VA_WIDTH'(32), '0, IFU_FAULT_PAGE, 0, '0);
    for (int i = 0; i < 15; i++) put16(b + VA_WIDTH'(2 * i), 16'h0505,
                                       32'h0015_0513);
    put32(b + VA_WIDTH'(30), ADDI);
    add_blk(b, b + VA_WIDTH'(32), 1'b0, 0);
    // Each cause on the FIRST page.
    b = VA_WIDTH'('h0_8006_0010);
    map_page(b, '0, IFU_FAULT_ACCESS, 0, '0);
    add_blk(b, b + VA_WIDTH'(32), 1'b0, 0);
    b = VA_WIDTH'('h0_8007_0020);
    map_page(b, '0, IFU_FAULT_PAGE, 0, '0);
    add_blk(b, b + VA_WIDTH'(32), 1'b0, 0);
    b = VA_WIDTH'('h0_8008_0030);
    map_page(b, '0, IFU_FAULT_GUEST_PAGE, 0, GPA_WIDTH'('h1_2345_6000));
    add_blk(b, b + VA_WIDTH'(32), 1'b0, 0);
    itlb_lat[1] = 3;                       // tag 1 returns after tag 0
    run_and_check(600);
    chk("second-page fault: the straddling instruction faults at 0x1000",
        (nrx > 0) && rx_en[0][15] &&
        (rx_slot[0][15].fault_cause == IFU_FAULT_PAGE) &&
        (rx_slot[0][15].fault_va == VA_WIDTH'('h0_8005_1000)));
    chk("cause 1 on the first page",
        (nrx > 1) && (rx_en[1] == 16'h0001) &&
        (rx_slot[1][0].fault_cause == IFU_FAULT_ACCESS));
    chk("cause 12 on the first page",
        (nrx > 2) && (rx_slot[2][0].fault_cause == IFU_FAULT_PAGE));
    chk("cause 20 on the first page carries the GPA",
        (nrx > 3) && (rx_slot[3][0].fault_cause == IFU_FAULT_GUEST_PAGE) &&
        (rx_slot[3][0].fault_gpa == GPA_WIDTH'('h1_2345_6000)));
    chk("a faulting first page issues no L1I request (one line in all)",
        n_l1i_req == 1);
  endtask

  task automatic t_itlb_miss();
    logic [VA_WIDTH-1:0] b;
    tname = "itlb_miss";
    $display("-- %s --", tname);
    reset_all();
    b = VA_WIDTH'('h0_8009_0040);
    map_page(b, 24'h00_0D11, IFU_FAULT_NONE, 3, '0);
    fill_mixed(b, 64);
    add_blk(b, b + VA_WIDTH'(32), 1'b0, 0);
    // A second, crossing block, and the ITLB refusing on odd cycles,
    // so lookups are held (IT-13) and re-requested after a miss.
    b = VA_WIDTH'('h0_8009_1FE0);
    fill_mixed(b, 64);
    add_blk(b, b + VA_WIDTH'(32), 1'b0, 0);
    itlb_lat[0]    = 2;
    itlb_lat[1]    = 3;
    itlb_stall_odd = 1'b1;
    run_and_check(400);
    chk($sformatf("three misses then a hit, then two: %0d lookups",
                  n_itlb_req), n_itlb_req == 6);
  endtask

  task automatic t_l1i_error();
    logic [VA_WIDTH-1:0] b;
    tname = "l1i_error";
    $display("-- %s --", tname);
    reset_all();
    // A two-line block starting at offset 40; the second line errors.
    b = VA_WIDTH'('h0_800A_0000);
    fill_mixed(b, 256);
    err_ln[b[PA_WIDTH-1:L1I_OFFSET_BITS] +
           (PA_WIDTH-L1I_OFFSET_BITS)'(1)] = 1'b1;
    add_blk(b + VA_WIDTH'(40), b + VA_WIDTH'(72), 1'b0, 0);
    run_and_check(400);
    chk("the first instruction in the errored line is an access fault",
        (nrx > 0) && (wb_fltv[0]) &&
        (rx_slot[0][wb_fltp[0]].fault_cause == IFU_FAULT_ACCESS));
  endtask

  task automatic t_taken_trunc();
    logic [VA_WIDTH-1:0] b;
    tname = "taken_truncation";
    $display("-- %s --", tname);
    reset_all();
    b = VA_WIDTH'('h0_800B_0000);
    for (int i = 0; i < 16; i++) put16(b + VA_WIDTH'(2 * i), 16'h0505,
                                       32'h0015_0513);
    put32(b + VA_WIDTH'(10), enc_beq(-10));
    add_blk(b, b, 1'b1, 5);                // BEQ at position 5, to b
    run_and_check(400);
    chk("nothing after the predicted taken position is enabled",
        (nrx > 0) && (rx_en[0] == 16'h003F) && !wb_misv[0]);
  endtask

  task automatic t_mispredicts();
    logic [VA_WIDTH-1:0] b;
    logic [VA_WIDTH-1:0] m1_tgt;
    tname = "m1_to_m4";
    $display("-- %s --", tname);
    reset_all();
    // M1: no taken predicted, a JAL at position 4.
    b = VA_WIDTH'('h0_800C_0000);
    for (int i = 0; i < 16; i++) put16(b + VA_WIDTH'(2 * i), 16'h0505,
                                       32'h0015_0513);
    put32(b + VA_WIDTH'(8), enc_jal(5'd1, 256));
    m1_tgt = b + VA_WIDTH'(8 + 256);
    add_blk(b, b + VA_WIDTH'(32), 1'b0, 0);
    // M2: taken at position 3, which holds a c.addi.
    b = VA_WIDTH'('h0_800C_1000);
    for (int i = 0; i < 16; i++) put16(b + VA_WIDTH'(2 * i), 16'h0505,
                                       32'h0015_0513);
    add_blk(b, b + VA_WIDTH'(400), 1'b1, 3);
    // M3: taken at position 2, a JAL whose target is not next_pc.
    b = VA_WIDTH'('h0_800C_2000);
    for (int i = 0; i < 16; i++) put16(b + VA_WIDTH'(2 * i), 16'h0505,
                                       32'h0015_0513);
    put32(b + VA_WIDTH'(4), enc_jal(5'd0, 128));
    add_blk(b, b + VA_WIDTH'(4 + 64), 1'b1, 2);
    // M4: a crossing block starting 16 bytes before a page end, its
    // second page faulting, taken at position 12 in that page: the
    // fault at position 8 cuts the range before the taken position.
    b = VA_WIDTH'('h0_800C_3FF0);
    map_page(b, 24'h00_0E00, IFU_FAULT_NONE, 0, '0);
    map_page(b + VA_WIDTH'(16), '0, IFU_FAULT_PAGE, 0, '0);
    for (int i = 0; i < 8; i++) put16(b + VA_WIDTH'(2 * i), 16'h0505,
                                      32'h0015_0513);
    add_blk(b, b + VA_WIDTH'(500), 1'b1, 12);
    run_and_check(600);
    chk("M1 at the JAL, truncated after it, target is the JAL's",
        (nwb > 0) && wb_misv[0] && (wb_misp[0] == 4'd4) &&
        (rx_en[0] == 16'h001F) && (wb_tgt[0] == m1_tgt));
    chk("M2 at the taken position", (nwb > 1) && wb_misv[1] &&
        (wb_misp[1] == 4'd3));
    chk("M3 at the taken position", (nwb > 2) && wb_misv[2] &&
        (wb_misp[2] == 4'd2));
    chk("M4: taken position outside the range, fault reported",
        (nwb > 3) && wb_misv[3] && (wb_misp[3] == 4'd12) && wb_fltv[3] &&
        (wb_fltp[3] == 4'd8) && !wb_rng[3][12]);
  endtask

  // M1 under a predicted taken position (C5, TD#146, BP-117). Each
  // block is sixteen c.addi with the instructions under test written
  // over them, on its own page, so nothing aliases between blocks.
  localparam logic [31:0] JALR_T0 = 32'h0002_8067;   // jalr x0,0(t0)

  task automatic t_m1_jal();
    logic [VA_WIDTH-1:0] b [0:4];
    logic [VA_WIDTH-1:0] jal_tgt [0:1];
    tname = "m1_jal_before_taken";
    $display("-- %s --", tname);
    reset_all();
    for (int k = 0; k < 5; k++) begin
      b[k] = VA_WIDTH'('h0_8010_0000) + VA_WIDTH'(k * 'h1000);
      for (int i = 0; i < 16; i++) put16(b[k] + VA_WIDTH'(2 * i),
                                         16'h0505, 32'h0015_0513);
    end
    // 0: a call JAL at position 2, then a BEQ at position 8 that is
    //    predicted taken with its correct target. Only M1 can fire.
    put32(b[0] + VA_WIDTH'(4),  enc_jal(5'd1, 512));
    put32(b[0] + VA_WIDTH'(16), enc_beq(-16));
    jal_tgt[0] = b[0] + VA_WIDTH'(4 + 512);
    add_blk(b[0], b[0], 1'b1, 8);
    // 1: a non-call JAL at position 1, predicted taken at position 6,
    //    which holds a c.addi: M2 would fire at 6, M1 fires at 1.
    put32(b[1] + VA_WIDTH'(2), enc_jal(5'd0, 64));
    jal_tgt[1] = b[1] + VA_WIDTH'(2 + 64);
    add_blk(b[1], b[1] + VA_WIDTH'(400), 1'b1, 6);
    // 2: a JALR at position 2 before a correctly predicted BEQ at 8.
    put32(b[2] + VA_WIDTH'(4),  JALR_T0);
    put32(b[2] + VA_WIDTH'(16), enc_beq(-16));
    add_blk(b[2], b[2], 1'b1, 8);
    // 3: a JALR at position 3 with no taken position predicted.
    put32(b[3] + VA_WIDTH'(6), JALR_T0);
    add_blk(b[3], b[3] + VA_WIDTH'(32), 1'b0, 0);
    // 4: a JAL AT the predicted taken position, target correct. Not
    //    before it, so M1 does not apply and M3 finds nothing.
    put32(b[4] + VA_WIDTH'(8), enc_jal(5'd0, 100));
    add_blk(b[4], b[4] + VA_WIDTH'(8 + 100), 1'b1, 4);
    run_and_check(800);
    chk("C5a M1 at a call JAL before the predicted taken branch",
        (nwb > 0) && wb_misv[0] && (wb_misp[0] == 4'd2) &&
        (wb_tgt[0] == jal_tgt[0]));
    chk("C5b the ibuf enable truncates at the JAL (IB-2)",
        (nrx > 0) && (rx_en[0] == 16'h0007));
    chk("C5c M1 at a non-call JAL outranks M2 at the taken position",
        (nwb > 1) && wb_misv[1] && (wb_misp[1] == 4'd1) &&
        (wb_tgt[1] == jal_tgt[1]) && (rx_en[1] == 16'h0003));
    chk("C5d a JALR before the predicted taken position is not M1",
        (nwb > 2) && !wb_misv[2] && (rx_en[2] == 16'h01F7));
    chk("C5e a JALR with none predicted is not M1",
        (nwb > 3) && !wb_misv[3] && (rx_en[3] == 16'hFFEF));
    chk("C5f a JAL at the taken position is not M1",
        (nwb > 4) && !wb_misv[4]);
  endtask

  // The lookup carries every fetch address bit above the page offset
  // (C19, IT-16, TD#146, BP-117). A crossing block whose PC has bits
  // 40 and 39 set, above the Sv39 VPN's top bit VPN_WIDTH+11 = 38,
  // then the block after it on the next page.
  task automatic t_vpn_high();
    logic [VA_WIDTH-1:0] b;
    logic [LKV-1:0]      v;
    tname = "vpn_high_bits";
    $display("-- %s --", tname);
    reset_all();
    b = VA_WIDTH'('h180_8011_0FE0);
    v = b[VA_WIDTH-1:12];
    fill_mixed(b, 64);
    add_blk(b, b + VA_WIDTH'(32), 1'b0, 0);
    add_blk(b + VA_WIDTH'(32), b + VA_WIDTH'(64), 1'b0, 0);
    run_and_check(400);
    chk($sformatf("C19a three lookups, two for the crossing block: %0d",
                  n_itlb_req), n_itlb_req == 3);
    chk($sformatf("C19b first lookup is the block's page %08h, got %08h",
                  v, lk_vpn[0]), (lk_vpn[0] == v) && !lk_tag[0]);
    chk($sformatf("C19c second lookup is the next page %08h, got %08h",
                  v + LKV'(1), lk_vpn[1]),
        (lk_vpn[1] == v + LKV'(1)) && lk_tag[1]);
    chk($sformatf("C19d next block's lookup keeps the high bits, %08h",
                  lk_vpn[2]), (lk_vpn[2] == v + LKV'(1)) && !lk_tag[2]);
  endtask

  task automatic t_gen();
    logic [VA_WIDTH-1:0] b;
    tname = "gen_carried";
    $display("-- %s --", tname);
    reset_all();
    b = VA_WIDTH'('h0_800D_0000);
    fill_mixed(b, 256);
    for (int i = 0; i < 6; i++)
      add_blk(b + VA_WIDTH'(32 * i), b + VA_WIDTH'(32 * i + 32), 1'b0, 0);
    blk[2].gen = 1'b1;
    blk[3].gen = 1'b1;
    run_and_check(400);
    for (int i = 0; i < 6 && i < nwb; i++)
      chk($sformatf("block %0d gen %0d returned", i, blk[i].gen),
          wb_gen[i] == blk[i].gen);
  endtask

  task automatic t_backpressure();
    logic [VA_WIDTH-1:0] b;
    tname = "ibuf_backpressure";
    $display("-- %s --", tname);
    reset_all();
    b = VA_WIDTH'('h0_800E_0000);
    fill_mixed(b, 256);
    for (int i = 0; i < 6; i++)
      add_blk(b + VA_WIDTH'(32 * i), b + VA_WIDTH'(32 * i + 32), 1'b0, 0);
    ib_drain = 2;                          // slow drain: IB-6 throttles
    fork
      begin
        repeat (12) @(posedge clk);
        #1;
        ib_force_stall = 1'b1;
        repeat (10) @(posedge clk);
        #1;
        ib_force_stall = 1'b0;
      end
    join_none
    run_and_check(800);
    chk($sformatf("the ibuf refused for %0d cycles", n_stall_cyc),
        n_stall_cyc >= 10);
    chk($sformatf("payload held on every refused cycle (%0d ok, %0d bad)",
                  n_hold_ok, n_hold_bad), (n_hold_ok >= 10) &&
                                          (n_hold_bad == 0));
  endtask

  task automatic t_flush();
    logic [VA_WIDTH-1:0] b;
    int n0;
    tname = "flush_idle";
    $display("-- %s --", tname);
    reset_all();
    b = VA_WIDTH'('h0_800F_0000);
    fill_mixed(b, 512);
    for (int i = 0; i < 3; i++)
      add_blk(b + VA_WIDTH'(32 * i), b + VA_WIDTH'(32 * i + 32), 1'b0, 0);
    run_and_check(400);
    // Nothing outstanding: the next block's translation request is
    // presented in the flush cycle and must be ignored.
    add_blk(b + VA_WIDTH'(256), b + VA_WIDTH'(288), 1'b0, 0);
    add_blk(b + VA_WIDTH'(288), b + VA_WIDTH'(320), 1'b0, 0);
    n0 = n_xlate_acc;
    run = 1'b1;
    fl_pos = 3;
    fl_idx = blk[3].idx;
    flush_req = 1'b1;
    @(posedge clk);
    #1;
    flush_req = 1'b0;
    chk("no request accepted in the flush cycle", n_xlate_acc == n0);
    ref_tail_val = 1'b0;                   // a flush clears the straddle
    for (int k = 0; k < 3; k++) begin
      exp_t e;
      ref_block(blk[k], e);                // replay the reference state
    end
    ref_tail_val = 1'b0;
    run_and_check(400, 3);
  endtask


  // =================================================================
  // BP-118 (TD#134): the flush with requests in flight, IFU-28 to 32.
  // =================================================================
  // Line buffer bookkeeping read back for IFU-29 and IFU-30.
  function automatic int lb_rc_sum();
    int n;
    n = 0;
    for (int s = 0; s < 16; s++) n += int'(dut.u_lbuf.r_rc[s]);
    return n;
  endfunction

  function automatic int lb_busy_cnt();
    int n;
    n = 0;
    for (int s = 0; s < 16; s++) n += int'(dut.u_lbuf.r_busy[s]);
    return n;
  endfunction

  function automatic int lb_id_cnt();
    int n;
    n = 0;
    for (int i = 0; i < MAX_OUTSTANDING; i++)
      n += int'(dut.u_lbuf.r_id_busy[i]);
    return n;
  endfunction

  // Replace blocks pos onward with a corrected stream of sequential
  // 32-byte blocks from base, each with its index kept and its
  // generation toggled (the FTQ reallocates F onward, X2).
  task automatic restream(input int pos, input logic [VA_WIDTH-1:0] base);
    int d;
    for (int k = pos; k < nblk; k++) begin
      d                = 32 * (k - pos);
      blk[k].start_pc  = base + VA_WIDTH'(d);
      blk[k].next_pc   = base + VA_WIDTH'(d + 32);
      blk[k].taken_val = 1'b0;
      blk[k].taken_pos = '0;
      blk[k].gen       = !blk[k].gen;
    end
  endtask

  // Present one flush naming position fpos.
  task automatic flush_at(input int fpos);
    fl_pos    = fpos;
    fl_idx    = (fpos < nblk) ? blk[fpos].idx
                              : FTQ_IDX_BITS'(idx0 + fpos);
    flush_req = 1'b1;
    @(posedge clk);
    #1;
    flush_req = 1'b0;
  endtask

  // IFU-28, IFU-29, IFU-30. Eight half blocks in six lines; blocks 0
  // and 1 share a line, and so do 2 and 3. Every L1I response is held
  // until after the flush, so every block is in the unit when it
  // arrives. The flush names position fpos with the commit pointer at
  // the first block. Survivors are delivered and written back in
  // order; blocks at or after F never appear; the held responses are
  // released in reverse, and every identifier and slot is free once
  // they are in.
  task automatic t_flush_inflight(input int i0, input int fpos,
                                  input string nm);
    logic [VA_WIDTH-1:0] a;
    logic [VA_WIDTH-1:0] n;
    int c;
    int off [0:7];
    tname = nm;
    $display("-- %s --", tname);
    reset_all();
    idx0 = i0;
    cptr = FTQ_IDX_BITS'(i0);
    a = VA_WIDTH'('h0_8020_0000);
    n = VA_WIDTH'('h0_8021_0000);
    fill_mixed(a, 512);
    fill_mixed(n, 512);
    off = '{0, 16, 64, 80, 192, 256, 320, 384};
    for (int k = 0; k < 8; k++)
      add_blk(a + VA_WIDTH'(off[k]), a + VA_WIDTH'(off[k] + 16), 1'b0, 0);
    l1i_hold_all = 1'b1;
    run = 1'b1;
    c = 0;
    while (((n_req_acc < 8) || (n_l1i_req < 6)) && (c < 200)) begin
      @(posedge clk);
      #1;
      c++;
    end
    repeat (3) @(posedge clk);
    #1;
    chk("all eight blocks fetched, six lines requested, none landed",
        (n_req_acc == 8) && (n_l1i_req == 6) && (n_l1i_rsp == 0) &&
        (nrx == 0));
    chk("six identifiers in flight before the flush", lb_id_cnt() == 6);
    run = 1'b0;
    restream(fpos, n);
    flush_at(fpos);
    chk($sformatf("IFU-30 survivors keep %0d references, got %0d", fpos,
                  lb_rc_sum()), lb_rc_sum() == fpos);
    chk("IFU-29 every identifier stays in flight across the flush",
        lb_id_cnt() == 6);
    chk("IFU-29 every slot stays reserved for its response",
        lb_busy_cnt() == 6);
    // Release in reverse: the dropped lines land first and out of
    // order, among the survivors'.
    l1i_ord      = ORD_REV;
    l1i_hold_all = 1'b0;
    c = 0;
    while (((n_l1i_rsp < 6) || (nrx < fpos) || (nwb < fpos)) &&
           (c < 200)) begin
      @(posedge clk);
      #1;
      c++;
    end
    repeat (4) @(posedge clk);
    #1;
    chk($sformatf("IFU-28 only the %0d survivors delivered (%0d) and "
                  , fpos, nrx), (nrx == fpos) && (nwb == fpos));
    chk("IFU-29 every identifier is free once the responses are in",
        lb_id_cnt() == 0);
    chk("IFU-29 every slot is free once the responses are in",
        (lb_busy_cnt() == 0) && (lb_rc_sum() == 0));
    chk("no L1I request issued after the flush while stopped",
        n_l1i_req == 6);
    run_and_check(600);
  endtask

  // IFU-28 in the translation queue, and a dropped block whose L1I
  // request is held by ready (IF-4).
  task automatic t_flush_xq_zombie();
    logic [VA_WIDTH-1:0] a;
    logic [VA_WIDTH-1:0] n;
    logic [REQ_ID_BITS-1:0] zid;
    logic [PA_WIDTH-1:0]    zpa;
    logic                   held;
    int c;
    tname = "flush_xq_and_zombie";
    $display("-- %s --", tname);
    reset_all();
    a = VA_WIDTH'('h0_8022_0000);
    n = VA_WIDTH'('h0_8023_0000);
    fill_mixed(a, 1024);
    fill_mixed(n, 512);
    for (int k = 0; k < 6; k++)
      add_blk(a + VA_WIDTH'(128 * k), a + VA_WIDTH'(128 * k + 32), 1'b0, 0);
    fetch_hold = 1'b1;
    run = 1'b1;
    repeat (20) @(posedge clk);
    #1;
    chk($sformatf("the translation queue fills behind a held fetch: %0d",
                  int'(dut.u_xlate.r_cnt)), dut.u_xlate.r_cnt == 4);
    restream(2, n);
    flush_at(2);
    chk($sformatf("IFU-28 the queue keeps its two survivors: %0d",
                  int'(dut.u_xlate.r_cnt)), dut.u_xlate.r_cnt == 2);
    chk("the kept head is block 0", dut.u_xlate.xq_idx == blk[0].idx);
    fetch_hold = 1'b0;
    run_and_check(600);

    // The zombie. One block, ready held low, so its request is
    // presented and not accepted when the flush drops the block.
    reset_all();
    fill_mixed(a, 512);
    fill_mixed(n, 512);
    add_blk(a, a + VA_WIDTH'(32), 1'b0, 0);
    add_blk(a + VA_WIDTH'(32), a + VA_WIDTH'(64), 1'b0, 0);
    l1i_rdy_low = 1'b1;
    run = 1'b1;
    c = 0;
    while (!ifu_l1i_req_val && (c < 50)) begin
      @(posedge clk);
      #1;
      c++;
    end
    repeat (2) @(posedge clk);
    #1;
    zid  = ifu_l1i_req_id;
    zpa  = ifu_l1i_req_paddr;
    chk("a request is presented and refused", ifu_l1i_req_val);
    run = 1'b0;
    restream(0, n);
    fl_pos    = 0;
    fl_idx    = blk[0].idx;
    flush_req = 1'b1;
    #1;
    held = ifu_l1i_req_val && (ifu_l1i_req_id == zid) &&
           (ifu_l1i_req_paddr == zpa);
    @(posedge clk);
    #1;
    flush_req = 1'b0;
    for (int k = 0; k < 4; k++) begin
      if (!(ifu_l1i_req_val && (ifu_l1i_req_id == zid) &&
            (ifu_l1i_req_paddr == zpa))) held = 1'b0;
      if (ftq_ifu_req_rdy) held = 1'b0;
      @(posedge clk);
      #1;
    end
    chk("IF-4 the dropped block's request stays presented, unchanged, "
        , held);
    l1i_rdy_low = 1'b0;
    repeat (8) @(posedge clk);
    #1;
    chk("its response came and was discarded: nothing delivered",
        (n_l1i_rsp >= 1) && (nrx == 0) && (nwb == 0) &&
        (lb_id_cnt() == 0));
    run_and_check(600);
    chk("the zombie line was fetched once, then the new stream",
        req_pa_log[0] == zpa);
  endtask

  // IFU-31. A page-crossing block has both lookups in flight when the
  // flush drops it; the ITLB answers tag 1 at 4 cycles and tag 0 at
  // 9, out of order and late. The next block's translation starts
  // the cycle after the last dead response and not before, and the
  // dead responses are not taken as the new block's.
  task automatic t_flush_itlb_dead();
    logic [VA_WIDTH-1:0] a;
    logic [VA_WIDTH-1:0] n;
    int c;
    tname = "flush_itlb_dead";
    $display("-- %s --", tname);
    reset_all();
    a = VA_WIDTH'('h0_8024_0FE0);
    n = VA_WIDTH'('h0_8025_0040);
    map_page(n, 24'h00_0F55, IFU_FAULT_NONE, 0, '0);
    fill_mixed(a, 64);
    fill_mixed(n, 128);
    add_blk(a, a + VA_WIDTH'(32), 1'b0, 0);
    add_blk(a + VA_WIDTH'(32), a + VA_WIDTH'(64), 1'b0, 0);
    itlb_lat[0] = 9;
    itlb_lat[1] = 4;
    run = 1'b1;
    c = 0;
    while ((n_itlb_req < 2) && (c < 50)) begin
      @(posedge clk);
      #1;
      c++;
    end
    chk("both lookups of the crossing block are in flight",
        (n_itlb_req == 2) && (n_itlb_rsp == 0));
    restream(0, n);
    flush_at(0);
    itlb_lat[0] = 1;
    itlb_lat[1] = 1;
    c = 0;
    while ((n_itlb_req < 3) && (c < 50)) begin
      @(posedge clk);
      #1;
      c++;
    end
    chk("the dead responses came out of order, tag 1 first",
        (n_itlb_rsp >= 2) && rs_tag[0] && !rs_tag[1]);
    chk($sformatf({"IFU-31 the new lookup follows the last dead response",
                   " by one cycle: rsp %0d lookup %0d"}, rs_cyc[1],
                  lk_cyc[2]), lk_cyc[2] == rs_cyc[1] + 2);
    chk("and it is the new block's page",
        lk_vpn[2] == n[VA_WIDTH-1:12]);
    run_and_check(400);

    // The block in lookup SURVIVES: translation continues.
    reset_all();
    fill_mixed(a, 64);
    fill_mixed(n, 128);
    fill_mixed(VA_WIDTH'('h0_8023_0040), 64);
    add_blk(VA_WIDTH'('h0_8023_0040), VA_WIDTH'('h0_8023_0060), 1'b0, 0);
    add_blk(a, a + VA_WIDTH'(32), 1'b0, 0);
    add_blk(a + VA_WIDTH'(32), a + VA_WIDTH'(64), 1'b0, 0);
    itlb_lat[0] = 6;
    itlb_lat[1] = 6;
    run = 1'b1;
    c = 0;
    while ((n_itlb_req < 3) && (c < 50)) begin
      @(posedge clk);
      #1;
      c++;
    end
    restream(2, n);
    flush_at(2);
    itlb_lat[0] = 1;
    itlb_lat[1] = 1;
    run_and_check(400);
    chk($sformatf("the surviving block's two lookups were not repeated: %0d",
                  n_itlb_req), n_itlb_req == 4);

  endtask


  // IFU-28 at F3, and the straddle register across a flush. The ibuf
  // refuses, so a block sits in F3 when the flush arrives. Block 0
  // ends in a 32-bit instruction straddling into block 1, whose upper
  // halfword is itself a recorded c.addi, so a walk from position 0
  // of block 1's start is well defined.
  //   A  block 0 transferred and set the straddle; block 1 is held in
  //      F3; the flush is at 2. Block 1 survives with the straddle
  //      kept: it begins at position 1.
  //   B  the same, the flush at 1. Block 1 is dropped from F3 and the
  //      straddle with it; the corrected block 1 starts at the same
  //      address and walks from position 0.
  task automatic t_flush_f3(input logic part_b);
    logic [VA_WIDTH-1:0] b;
    logic [VA_WIDTH-1:0] n;
    int c;
    tname = part_b ? "flush_f3_dropped" : "flush_f3_survives";
    $display("-- %s --", tname);
    reset_all();
    b = VA_WIDTH'('h0_8028_0000);
    n = VA_WIDTH'('h0_8029_0000);
    fill_mixed(n, 256);
    for (int i = 0; i < 64; i++) put16(b + VA_WIDTH'(2 * i), 16'h0505,
                                       32'h0015_0513);
    put32(b + VA_WIDTH'(30), 32'h0505_0513);         // addi a0,a0,80
    put16(b + VA_WIDTH'(32), 16'h0505, 32'h0015_0513);
    for (int k = 0; k < 4; k++)
      add_blk(b + VA_WIDTH'(32 * k), b + VA_WIDTH'(32 * k + 32), 1'b0, 0);
    run = 1'b1;
    c = 0;
    while ((nrx < 1) && (c < 100)) begin
      @(posedge clk);
      #1;
      c++;
    end
    ib_force_stall = 1'b1;
    repeat (6) @(posedge clk);
    #1;
    chk("block 0 delivered, block 1 held in F3 by the ibuf",
        (nrx == 1) && ifu_ibuf_val && (ifu_ibuf_slot[0].ftq_idx ==
                                       blk[1].idx));
    chk("the straddle is set for block 1", dut.u_f3.r_strad_val);
    run = 1'b0;
    if (part_b) begin
      restream(1, b + VA_WIDTH'(32));
      ref_cut_pos = 1;
      flush_at(1);
    end else begin
      restream(2, n);
      flush_at(2);
    end
    chk(part_b ? "IFU-28 the dropped block leaves F3"
               : "IFU-28 the surviving block stays in F3",
        dut.u_f3.r_val == !part_b);
    chk(part_b ? "the straddle is dropped with the block after its setter"
               : "the straddle is kept: the block after its setter survives",
        dut.u_f3.r_strad_val == !part_b);
    ib_force_stall = 1'b0;
    run_and_check(600);
    chk(part_b ? "the corrected block 1 walks from position 0"
               : "the surviving block 1 begins on the straddle tail",
        (nrx > 1) && (rx_en[1][0] == part_b));
  endtask

  // The predecode redirect: K's writeback carries an M1 and the FTQ
  // flushes at K+1 in the same cycle (ftq_ifu_interfaces.md 7 W3).
  // K+1 and K+2 have their lines held, so they are in flight at the
  // flush. K is delivered and written back once; K+1 and K+2 are
  // dropped and the corrected stream follows.
  task automatic t_flush_predecode();
    logic [VA_WIDTH-1:0] a;
    logic [VA_WIDTH-1:0] x;
    logic [VA_WIDTH-1:0] t;
    int c;
    logic seen;
    tname = "flush_predecode_k";
    $display("-- %s --", tname);
    reset_all();
    a = VA_WIDTH'('h0_8026_0000);
    x = VA_WIDTH'('h0_8026_0400);
    t = VA_WIDTH'('h0_8027_0000);
    fill_mixed(a, 1024);
    fill_mixed(t, 256);
    for (int i = 0; i < 16; i++) put16(x + VA_WIDTH'(2 * i), 16'h0505,
                                       32'h0015_0513);
    put32(x + VA_WIDTH'(8), enc_jal(5'd0, int'(t - (x + VA_WIDTH'(8)))));
    add_blk(a, a + VA_WIDTH'(32), 1'b0, 0);
    add_blk(a + VA_WIDTH'(128), a + VA_WIDTH'(160), 1'b0, 0);
    add_blk(x, x + VA_WIDTH'(32), 1'b0, 0);                      // K
    add_blk(a + VA_WIDTH'(256), a + VA_WIDTH'(288), 1'b0, 0);
    add_blk(a + VA_WIDTH'(384), a + VA_WIDTH'(416), 1'b0, 0);
    l1i_hold_ln[a[PA_WIDTH-1:L1I_OFFSET_BITS] +
                (PA_WIDTH-L1I_OFFSET_BITS)'(4)] = 1'b1;
    l1i_hold_ln[a[PA_WIDTH-1:L1I_OFFSET_BITS] +
                (PA_WIDTH-L1I_OFFSET_BITS)'(6)] = 1'b1;
    pd_auto  = 1'b1;
    pd_k_idx = blk[2].idx;
    pd_k_pos = 2;
    run = 1'b1;
    c    = 0;
    seen = 1'b0;
    while (!seen && (c < 300)) begin
      if (pd_fire) begin
        seen = 1'b1;
        chk("the flush is at K+1",
            ftq_ifu_flush_idx == blk[2].idx + FTQ_IDX_BITS'(1));
        chk("K+1 and K+2 are in flight at the flush",
            (n_l1i_req >= 5) && (n_l1i_rsp <= 3));
        restream(3, t);
      end
      @(posedge clk);
      #1;
      c++;
    end
    pd_auto = 1'b0;
    chk("the predecode redirect fired once", seen && (n_flush == 1));
    repeat (6) @(posedge clk);
    #1;
    l1i_hold_ln.delete();
    run_and_check(600);
    chk("K was not dropped by its own flush: delivered and written back",
        (nwb > 2) && (wb_idx[2] == blk[2].idx) && wb_misv[2] &&
        (wb_misp[2] == 4'd4) && (rx_en[2] == 16'h001F));
    chk($sformatf("five blocks delivered, none twice: %0d", nrx),
        nrx == 5);
  endtask

  // =================================================================
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    t_seq_coalesce();
    t_ooo(ORD_REV,  6,  "ooo_reverse_partial");
    t_ooo(ORD_REV,  16, "ooo_reverse_full");
    t_ooo(ORD_ODD,  6,  "ooo_oddfirst_partial");
    t_ooo(ORD_ODD,  16, "ooo_oddfirst_full");
    t_ooo(ORD_RAND, 6,  "ooo_random_partial");
    t_ooo(ORD_RAND, 16, "ooo_random_full");
    t_straddle();
    t_page_faults();
    t_itlb_miss();
    t_l1i_error();
    t_taken_trunc();
    t_mispredicts();
    t_m1_jal();
    t_vpn_high();
    t_gen();
    t_backpressure();
    t_flush();
    t_flush_inflight(0,  3, "flush_inflight");
    t_flush_inflight(61, 3, "flush_inflight_wrap");
    t_flush_inflight(20, 0, "flush_inflight_rc_unspec");
    t_flush_xq_zombie();
    t_flush_itlb_dead();
    t_flush_predecode();
    t_flush_f3(1'b0);
    t_flush_f3(1'b1);
    $display("tb_ifu: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_ifu: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #2000000;
    $fatal(1, "tb_ifu: timeout");
  end

endmodule : tb
