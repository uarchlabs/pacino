// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fe_tb_mem.svh -- the memory model
//
// A SHARED FRONT-END TESTBENCH MODEL (DOC-001, fe_demo_tb_decisions.md
// FDT-4). Not a compilation unit: it is included inside the body of
// module tb, after the package imports, by tb_fe_top
// (rtl/core/frontend/fe_top/tb) and tb_fe_demo (examples/fe_demo/tb),
// in the order those files give. The text was moved here from
// tb_fe_top.sv unchanged except where this header says otherwise.
//
// Holds: the one memory image's two ports, the L1I's l2-side
// TileLink link (two 256-bit beats per line, TL_LAT cycles) and the
// walker's memory port (WM-10 to WM-13); the walk counter; and the
// walk-range and ITLB-invalidate hooks a program arms. Requires
// fe_tb_dut.svh and fe_tb_writer.svh.
// ===================================================================

  localparam int TL_LAT  = 6;      // memory latency, request to beat 0

  // =================================================================
  // The memory model: the L1I's l2-side link (FE-21).
  // =================================================================
  logic                q_val  [0:15];
  logic [PA_WIDTH-1:0] q_addr [0:15];
  int                  q_due  [0:15];
  logic                d_busy;
  logic [3:0]          d_src;
  logic                d_beat;
  int                  n_fills;

  assign l1i_mem_a_ready = rstn;

  initial begin : tl_mem
    logic                s_a;
    logic [3:0]          s_src;
    logic [PA_WIDTH-1:0] s_addr;
    logic                s_d;
    int                  pick;
    l1i_mem_d_valid   = 1'b0;
    l1i_mem_d_opcode  = 3'd1;            // AccessAckData
    l1i_mem_d_param   = '0;
    l1i_mem_d_size    = 3'd6;            // 64 bytes
    l1i_mem_d_source  = '0;
    l1i_mem_d_sink    = '0;
    l1i_mem_d_denied  = 1'b0;
    l1i_mem_d_data    = '0;
    l1i_mem_d_corrupt = 1'b0;
    d_busy            = 1'b0;
    d_src             = '0;
    d_beat            = 1'b0;
    for (int i = 0; i < 16; i++) q_val[i] = 1'b0;
    forever begin
      @(posedge clk);
      s_a    = rstn && l1i_mem_a_valid && l1i_mem_a_ready;
      s_src  = l1i_mem_a_source;
      s_addr = l1i_mem_a_address;
      s_d    = l1i_mem_d_valid && l1i_mem_d_ready;
      #1;
      if (!rstn) begin
        for (int i = 0; i < 16; i++) q_val[i] = 1'b0;
        d_busy          = 1'b0;
        l1i_mem_d_valid = 1'b0;
      end else begin
        if (s_d) begin
          if (d_beat) begin
            d_busy       = 1'b0;
            q_val[d_src] = 1'b0;
          end
          d_beat = !d_beat;
        end
        if (s_a) begin
          if (q_val[s_src]) $display("tb_fe_top: source %0d reused", s_src);
          if (l1i_mem_a_opcode != 3'd4)
            $display("tb_fe_top: L1I opcode %0d is not a Get",
                     l1i_mem_a_opcode);
          q_val[s_src]  = 1'b1;
          q_addr[s_src] = s_addr;
          q_due[s_src]  = cyc + TL_LAT;
          n_fills++;
        end
        if (!d_busy) begin
          pick = -1;
          for (int i = 0; i < 16; i++)
            if (q_val[i] && (q_due[i] <= cyc) && (pick < 0)) pick = i;
          if (pick >= 0) begin
            d_busy = 1'b1;
            d_src  = 4'(pick);
            d_beat = 1'b0;
          end
        end
        l1i_mem_d_valid  = d_busy;
        l1i_mem_d_source = d_src;
        for (int b = 0; b < 32; b++) begin
          l1i_mem_d_data[8*b +: 8] =
            W.rd8(q_addr[d_src] + PA_WIDTH'(32 * int'(d_beat) + b));
        end
      end
    end
  end

  // =================================================================
  // The walker's memory port (ptw_mem_interfaces.md, BP-123). It reads
  // and writes the same image as the L1I's link above (WM-10). WM-11:
  // the PTE at chg_pa is overwritten with chg_val just before the next
  // CAS to it. WM-12: a read or CAS of err_pa is answered with
  // mem_ptw_rsp_err, once. WM-13: ready falls on a pattern and the
  // latency varies over [pw_lat_min, pw_lat_max].
  // =================================================================
  int                  n_walks;
  int                  n_pw_acc;
  int                  n_pw_cas;
  int                  n_pw_err;
  int                  n_pw_chg;
  int                  pw_lat_min;
  int                  pw_lat_max;
  int                  pw_rdy_pat;
  logic                err_arm;
  logic [PA_WIDTH-1:0] err_pa;
  logic                chg_arm;
  logic [PA_WIDTH-1:0] chg_pa;
  logic [63:0]         chg_val;
  int                  n_pw_bad;     // WM-1, WM-3 seen broken

  // Walks whose VPN lies in [walk_lo, walk_hi), for the NAPOT and
  // invalidate programs; and the invalidate-during-a-walk trigger: the
  // first walk for inv_vpn arms an ITLB invalidate (all, ITLB-14) four
  // cycles later, and the cycle it fires records whether the walker was
  // still walking.
  logic [VA_WIDTH-13:0] walk_lo;
  logic [VA_WIDTH-13:0] walk_hi;
  int                   n_walk_rng;
  logic [VA_WIDTH-13:0] walk2_lo;
  logic [VA_WIDTH-13:0] walk2_hi;
  int                   n_walk_rng2;
  logic                 inv_watch;
  logic [VA_WIDTH-13:0] inv_vpn;
  int                   inv_at;
  int                   n_inv_fired;
  int                   n_inv_busy;

  always @(posedge clk) begin : walk_count
    if (rstn && itlb_l2t_req_val && itlb_l2t_req_rdy) begin
      n_walks <= n_walks + 1;
      if ((itlb_l2t_vpn >= walk_lo) && (itlb_l2t_vpn < walk_hi))
        n_walk_rng <= n_walk_rng + 1;
      if ((itlb_l2t_vpn >= walk2_lo) && (itlb_l2t_vpn < walk2_hi))
        n_walk_rng2 <= n_walk_rng2 + 1;
    end
  end

  initial begin : ptw_mem
    logic                s_acc;
    logic                s_op;
    logic [PA_WIDTH-1:0] s_pa;
    logic [63:0]         s_cmp;
    logic [63:0]         s_swap;
    logic                o_val;
    int                  o_due;
    logic                o_op;
    logic [PA_WIDTH-1:0] o_pa;
    logic [63:0]         o_cmp;
    logic [63:0]         o_swap;
    logic [63:0]         old;
    int                  rc;
    ptw_mem_req_rdy  = 1'b0;
    mem_ptw_rsp_val  = 1'b0;
    mem_ptw_rsp_data = '0;
    mem_ptw_rsp_err  = 1'b0;
    o_val            = 1'b0;
    rc               = 0;
    forever begin
      @(posedge clk);
      s_acc  = rstn && ptw_mem_req_val && ptw_mem_req_rdy;
      s_op   = ptw_mem_req_op;
      s_pa   = ptw_mem_req_paddr;
      s_cmp  = ptw_mem_req_cmp;
      s_swap = ptw_mem_req_swap;
      #1;
      mem_ptw_rsp_val = 1'b0;
      mem_ptw_rsp_err = 1'b0;
      if (!rstn) begin
        o_val = 1'b0;
      end else begin
        if (o_val && (o_due <= cyc)) begin
          o_val           = 1'b0;
          mem_ptw_rsp_val = 1'b1;
          if (err_arm && (o_pa == err_pa)) begin
            err_arm          = 1'b0;
            mem_ptw_rsp_err  = 1'b1;
            mem_ptw_rsp_data = 64'hBAD0_BAD0_BAD0_BAD0;
            n_pw_err++;
          end else begin
            if (o_op && chg_arm && (o_pa == chg_pa)) begin
              chg_arm = 1'b0;
              W.wr64(o_pa, chg_val);
              n_pw_chg++;
            end
            old              = W.rd64(o_pa);
            mem_ptw_rsp_data = old;
            if (o_op && (old == o_cmp)) W.wr64(o_pa, o_swap);
          end
        end
        if (s_acc) begin
          if (s_pa[2:0] != 3'b000) n_pw_bad++;          // WM-1
          if (o_val) n_pw_bad++;                         // WM-3
          o_val  = 1'b1;
          o_op   = s_op;
          o_pa   = s_pa;
          o_cmp  = s_cmp;
          o_swap = s_swap;
          o_due  = cyc + pw_lat_min +
                   ((pw_lat_max > pw_lat_min)
                      ? int'($urandom % (pw_lat_max - pw_lat_min + 1)) : 0);
          n_pw_acc++;
          if (s_op) n_pw_cas++;
        end
      end
      // WM-13: ready from a counter, never from the request (WM-2).
      rc++;
      ptw_mem_req_rdy = rstn && ((pw_rdy_pat == 0) || ((rc % pw_rdy_pat) == 0));
    end
  end
