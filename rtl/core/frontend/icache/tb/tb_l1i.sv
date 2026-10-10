// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for the pacino L1I's BP-123 additions: the maintenance port
// of l1i_ifu_interfaces.md 10 (IF-28 to IF-32, IF-42, L1I-18) and the
// uncached request of IF-44 / icache_decisions.md L1I-24. The emitted
// behaviour is tb/l1i_tb.sv's.
//
// THE MEMORY MODEL answers the TileLink link with Get, two 256-bit
// AccessAckData beats per line, from a store whose content is a
// function of the line address and a per-line VERSION the test bumps.
// A line returned by the cache therefore says which memory content it
// came from: an array hit returns the version the line had when it was
// filled, a fill the version memory holds now. Per-line latency can be
// set, so one fill can be held while another completes.
//
// WHAT IS OBSERVED: the core response (data, so the version), the
// number of Gets per line, and the core port handshakes. Nothing inside
// the L1I is read: a hit is a response with no Get, an allocation is a
// later hit, and the replacement victim is the line that misses again.
//
// Every test starts from reset (CLAUDE.md, no test debt). The bound
// properties of tb/l1i_assert.sv and tb/l1i_mshr_assert.sv run
// throughout.
// ===================================================================
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
/* verilator lint_on IMPORTSTAR */

module tb;

  logic clk;
  logic rstn;
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ---- DUT ports -------------------------------------------------------
  logic         core_valid;
  logic [35:0]  core_addr;
  logic [3:0]   core_id;
  logic         core_prefetch;
  logic         core_uncached;
  logic [511:0] core_rdata;
  logic         core_ready;
  logic         core_rvalid;
  logic [3:0]   core_rid;
  logic         core_rerr;
  logic         core_inv_val;
  logic         core_inv_rdy;
  logic         core_inv_all;
  logic [35:0]  core_inv_addr;
  logic         core_inv_done;
  logic         mem_a_valid;
  logic         mem_a_ready;
  logic [2:0]   mem_a_opcode;
  logic [2:0]   mem_a_param;
  logic [2:0]   mem_a_size;
  logic [3:0]   mem_a_source;
  logic [35:0]  mem_a_address;
  logic [31:0]  mem_a_mask;
  logic [255:0] mem_a_data;
  logic         mem_a_corrupt;
  logic         mem_d_valid;
  logic         mem_d_ready;
  logic [2:0]   mem_d_opcode;
  logic [2:0]   mem_d_param;
  logic [2:0]   mem_d_size;
  logic [3:0]   mem_d_source;
  logic [1:0]   mem_d_sink;
  logic         mem_d_denied;
  logic [255:0] mem_d_data;
  logic         mem_d_corrupt;

  l1i dut (.*);

  // ---- bookkeeping -----------------------------------------------------
  int    pass_cnt;
  int    fail_cnt;
  string tname;
  int    cyc;

  always @(posedge clk) cyc <= rstn ? cyc + 1 : 0;

  task automatic chk(input string nm, input logic ok);
    if (ok) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: [%s] %s", tname, nm);
    end
  endtask

  // =================================================================
  // Memory: versioned lines.
  // =================================================================
  int ver   [logic [29:0]];          // by line address
  int lat   [logic [29:0]];          // per-line fill latency override
  int n_get [logic [29:0]];
  int n_get_all;
  localparam int LAT_DFLT = 4;

  function automatic logic [511:0] line_val(input logic [29:0] ln,
                                            input int v);
    logic [511:0] d;
    for (int w = 0; w < 16; w++)
      d[32*w +: 32] = {ln[23:0], 8'(v)} ^ 32'(w * 32'h0101_0101);
    return d;
  endfunction

  function automatic logic [29:0] lnof(input logic [35:0] a);
    return a[35:6];
  endfunction

  function automatic int ver_of(input logic [29:0] ln);
    return ver.exists(ln) ? ver[ln] : 0;
  endfunction

  function automatic int gets(input logic [29:0] ln);
    return n_get.exists(ln) ? n_get[ln] : 0;
  endfunction

  logic        q_val  [0:15];
  logic [29:0] q_ln   [0:15];
  int          q_due  [0:15];
  logic        d_busy;
  logic [3:0]  d_src;
  logic        d_beat;
  logic [511:0] d_line;

  assign mem_a_ready = rstn;

  initial begin : tl_mem
    logic        s_a;
    logic [3:0]  s_src;
    logic [29:0] s_ln;
    logic        s_d;
    int          pick;
    mem_d_valid   = 1'b0;
    mem_d_opcode  = 3'd1;                // AccessAckData
    mem_d_param   = '0;
    mem_d_size    = 3'd6;
    mem_d_source  = '0;
    mem_d_sink    = '0;
    mem_d_denied  = 1'b0;
    mem_d_data    = '0;
    mem_d_corrupt = 1'b0;
    d_busy        = 1'b0;
    d_beat        = 1'b0;
    for (int i = 0; i < 16; i++) q_val[i] = 1'b0;
    forever begin
      @(posedge clk);
      s_a   = rstn && mem_a_valid && mem_a_ready;
      s_src = mem_a_source;
      s_ln  = mem_a_address[35:6];
      s_d   = mem_d_valid && mem_d_ready;
      #1;
      if (!rstn) begin
        for (int i = 0; i < 16; i++) q_val[i] = 1'b0;
        d_busy      = 1'b0;
        mem_d_valid = 1'b0;
      end else begin
        if (s_d) begin
          if (d_beat) begin
            d_busy       = 1'b0;
            q_val[d_src] = 1'b0;
          end
          d_beat = !d_beat;
        end
        if (s_a) begin
          q_val[s_src] = 1'b1;
          q_ln[s_src]  = s_ln;
          q_due[s_src] = cyc + (lat.exists(s_ln) ? lat[s_ln] : LAT_DFLT);
          if (n_get.exists(s_ln)) n_get[s_ln]++;
          else                    n_get[s_ln] = 1;
          n_get_all++;
        end
        if (!d_busy) begin
          pick = -1;
          for (int i = 0; i < 16; i++)
            if (q_val[i] && (q_due[i] <= cyc) && (pick < 0)) pick = i;
          if (pick >= 0) begin
            d_busy = 1'b1;
            d_src  = 4'(pick);
            d_beat = 1'b0;
            // The content is sampled when the fill is answered.
            d_line = line_val(q_ln[pick], ver_of(q_ln[pick]));
          end
        end
        mem_d_valid  = d_busy;
        mem_d_source = d_src;
        mem_d_data   = d_beat ? d_line[511:256] : d_line[255:0];
      end
    end
  end

  // =================================================================
  // Core port: requests and responses.
  // =================================================================
  logic         r_got  [0:15];
  logic [511:0] r_data [0:15];
  int           r_cyc  [0:15];
  int           n_acc_inv;   // requests accepted while an inv pending
  logic         inv_pend;
  int           inv_take_cyc;
  int           done_cyc;
  int           n_done;

  always @(posedge clk) begin
    if (rstn && core_rvalid) begin
      r_got[core_rid]  <= 1'b1;
      r_data[core_rid] <= core_rdata;
      r_cyc[core_rid]  <= cyc;
    end
    if (rstn && core_inv_done) begin
      n_done   <= n_done + 1;
      done_cyc <= cyc;
    end
  end

  task automatic reset_all(input string nm);
    tname = nm;
    rstn  = 1'b0;
    core_valid    = 1'b0;
    core_addr     = '0;
    core_id       = '0;
    core_prefetch = 1'b0;
    core_uncached = 1'b0;
    core_inv_val  = 1'b0;
    core_inv_all  = 1'b0;
    core_inv_addr = '0;
    ver.delete();
    lat.delete();
    n_get.delete();
    n_get_all = 0;
    n_done    = 0;
    for (int i = 0; i < 16; i++) r_got[i] = 1'b0;
    repeat (4) @(posedge clk);
    #1;
    rstn = 1'b1;
    @(posedge clk);
    #1;
  endtask

  // Present one request until it is accepted; returns at #1 after the
  // accepting edge.
  task automatic issue(input logic [3:0] id, input logic [35:0] a,
                       input logic unc);
    r_got[id]     = 1'b0;
    core_valid    = 1'b1;
    core_id       = id;
    core_addr     = a;
    core_uncached = unc;
    do @(posedge clk); while (!core_ready);
    #1;
    core_valid    = 1'b0;
    core_uncached = 1'b0;
  endtask

  task automatic wait_rsp(input logic [3:0] id);
    int t;
    t = 0;
    while (!r_got[id] && (t < 500)) begin
      @(posedge clk);
      #1;
      t++;
    end
    chk($sformatf("request %0d answered", id), r_got[id]);
  endtask

  // One request, answered, and its line's version.
  task automatic fetch(input logic [3:0] id, input logic [35:0] a,
                       input logic unc, output int v);
    issue(id, a, unc);
    wait_rsp(id);
    v = -1;
    for (int k = 0; k < 256; k++)
      if (r_data[id] == line_val(a[35:6], k)) v = k;
  endtask

  task automatic inv(input logic all, input logic [35:0] a);
    core_inv_val  = 1'b1;
    core_inv_all  = all;
    core_inv_addr = a;
    do @(posedge clk); while (!core_inv_rdy);
    inv_take_cyc = cyc;
    #1;
    core_inv_val = 1'b0;
  endtask

  task automatic wait_done();
    int t;
    t = 0;
    while ((n_done == 0) && (t < 500)) begin
      @(posedge clk);
      #1;
      t++;
    end
    chk("the invalidate completed", n_done == 1);
  endtask

  // Addresses. Bank select is bit 6, set index bits 12:7, so lines
  // 0x2000 apart share a set and a bank.
  localparam logic [35:0] BASE = 36'h0_8000_0000;
  function automatic logic [35:0] same_set(input int k);
    return BASE + 36'(k) * 36'h2000;
  endfunction

  // =================================================================
  // Uncached (L1I-24).
  // =================================================================
  task automatic t_unc_resident();
    logic [35:0] a;
    int v;
    a = BASE + 36'h1C0;
    reset_all("unc_resident");
    fetch(0, a, 1'b0, v);
    chk("a cacheable miss fills version 0", v == 0);
    fetch(1, a, 1'b0, v);
    chk("a second cacheable request hits", gets(a[35:6]) == 1);
    ver[a[35:6]] = 1;                                  // memory changes
    fetch(2, a, 1'b1, v);
    chk("an uncached request to a resident line is a miss",
        gets(a[35:6]) == 2);
    chk("it is answered from memory, version 1", v == 1);
    fetch(3, a, 1'b0, v);
    chk("the array still holds version 0: not written", v == 0);
    chk("and that cacheable request hit", gets(a[35:6]) == 2);
  endtask

  task automatic t_unc_absent();
    logic [35:0] a;
    int v;
    a = BASE + 36'h240;
    reset_all("unc_absent");
    fetch(0, a, 1'b1, v);
    chk("an uncached miss is fetched", (gets(a[35:6]) == 1) && (v == 0));
    fetch(1, a, 1'b1, v);
    chk("a second uncached request is fetched again", gets(a[35:6]) == 2);
    fetch(2, a, 1'b0, v);
    chk("a cacheable request after it misses: never allocated",
        gets(a[35:6]) == 3);
    fetch(3, a, 1'b0, v);
    chk("and that one allocated", gets(a[35:6]) == 3);
  endtask

  // The replacement state. Fill one set's eight ways cold (ways 0 to 7,
  // D-40), then touch the line in the way the tree-PLRU would evict
  // next, uncached; then fill a ninth line. The uncached touch must not
  // have protected it: it is the line evicted, exactly as with no touch.
  // A cacheable touch would protect it, which the control run shows.
  task automatic plru_run(input string nm, input int touch,
                          output int evicted);
    int v;
    reset_all(nm);
    for (int k = 0; k < 8; k++) fetch(4'(k), same_set(k), 1'b0, v);
    if (touch == 1) fetch(8, same_set(0), 1'b1, v);    // uncached
    if (touch == 2) fetch(8, same_set(0), 1'b0, v);    // cacheable
    fetch(9, same_set(8), 1'b0, v);                    // ninth line
    evicted = -1;
    for (int k = 0; k < 8; k++) begin
      int g0;
      g0 = gets(lnof(same_set(k)));
      fetch(10, same_set(k), 1'b0, v);
      if ((gets(lnof(same_set(k))) != g0) && (evicted < 0)) evicted = k;
    end
  endtask

  task automatic t_unc_plru();
    int e_none;
    int e_unc;
    int e_cach;
    plru_run("unc_plru_none", 0, e_none);
    plru_run("unc_plru_unc",  1, e_unc);
    plru_run("unc_plru_cach", 2, e_cach);
    tname = "unc_plru";
    chk($sformatf("with no touch line %0d is evicted", e_none), e_none == 0);
    chk($sformatf("an uncached touch of it leaves it the victim (%0d)",
                  e_unc), e_unc == e_none);
    chk($sformatf("a cacheable touch protects it (%0d)", e_cach),
        e_cach != e_none);
  endtask

  // A cacheable request merged onto an uncached register still
  // allocates; an uncached request merges onto a cacheable miss.
  task automatic t_unc_merge();
    logic [35:0] a;
    int v;
    a = BASE + 36'h300;
    reset_all("unc_merge_c_onto_u");
    lat[a[35:6]] = 40;                                 // hold the fill
    issue(0, a, 1'b1);                                 // uncached
    repeat (3) @(posedge clk);
    #1;
    issue(1, a, 1'b0);                                 // cacheable
    wait_rsp(0);
    wait_rsp(1);
    chk("one fill for both", gets(a[35:6]) == 1);
    chk("both answered with the line", (r_data[0] == line_val(a[35:6], 0))
        && (r_data[1] == line_val(a[35:6], 0)));
    fetch(2, a, 1'b0, v);
    chk("the merged cacheable request allocated: a hit",
        gets(a[35:6]) == 1);

    reset_all("unc_merge_u_onto_c");
    lat[a[35:6]] = 40;
    issue(0, a, 1'b0);                                 // cacheable miss
    repeat (3) @(posedge clk);
    #1;
    ver[a[35:6]] = 2;                                  // before the fill
    issue(1, a, 1'b1);                                 // uncached
    wait_rsp(0);
    wait_rsp(1);
    chk("one fill for both", gets(a[35:6]) == 1);
    chk("the uncached request has the fill's data, from memory",
        r_data[1] == line_val(a[35:6], 2));

    // The cacheable lookup is still in flight (accepted last cycle): the
    // uncached request takes its own register rather than risk an
    // answer from the array.
    reset_all("unc_own_reg");
    lat[a[35:6]] = 20;
    core_valid = 1'b1;
    core_id    = 4'd0;
    core_addr  = a;
    @(posedge clk);
    #1;
    core_id       = 4'd1;
    core_uncached = 1'b1;
    @(posedge clk);
    #1;
    core_valid    = 1'b0;
    core_uncached = 1'b0;
    wait_rsp(0);
    wait_rsp(1);
    chk($sformatf("two fills (%0d)", gets(a[35:6])), gets(a[35:6]) == 2);
    fetch(2, a, 1'b0, v);
    chk("the cacheable one allocated", gets(a[35:6]) == 2);
  endtask

  // An uncached request to a line resident in a full set, with a
  // cacheable request merged onto its register: the fill installs over
  // the line's own way, so the set still holds all eight lines and
  // every one hits. Installed at the replacement victim instead, the
  // line would sit in two ways and evict line 0.
  task automatic t_unc_merge_resident();
    int v;
    int g0;
    reset_all("unc_merge_resident");
    for (int k = 0; k < 8; k++) fetch(4'(k), same_set(k), 1'b0, v);
    lat[lnof(same_set(7))] = 30;
    issue(8, same_set(7), 1'b1);                       // uncached
    repeat (3) @(posedge clk);
    #1;
    issue(9, same_set(7), 1'b0);                       // cacheable, merges
    wait_rsp(8);
    wait_rsp(9);
    chk("one fill for both", gets(lnof(same_set(7))) == 2);
    for (int k = 0; k < 8; k++) begin
      g0 = gets(lnof(same_set(k)));
      fetch(10, same_set(k), 1'b0, v);
      chk($sformatf("line %0d of the set still hits", k),
          gets(lnof(same_set(k))) == g0);
    end
  endtask

  // =================================================================
  // Maintenance (IF-28 to IF-32, IF-42).
  // =================================================================
  task automatic t_inv_all();
    int v;
    logic rdy_low;
    reset_all("inv_all");
    // Four resident lines, then four misses held in flight.
    for (int k = 0; k < 4; k++) fetch(4'(k), BASE + 36'(k * 64), 1'b0, v);
    for (int k = 4; k < 8; k++) lat[lnof(BASE + 36'(k * 64))] = 30;
    for (int k = 4; k < 8; k++) issue(4'(k), BASE + 36'(k * 64), 1'b0);
    inv(1'b1, 36'h0);
    // Ready is low until done; the drained requests are still answered.
    // A request presented throughout the invalidate is taken only after
    // done (IF-30).
    r_got[12]  = 1'b0;
    core_valid = 1'b1;
    core_id    = 4'd12;
    core_addr  = BASE + 36'h1000;
    rdy_low = 1'b1;
    begin
      int t;
      int tk;
      t  = 0;
      tk = -1;
      while ((tk < 0) && (t < 500)) begin
        if (core_ready && (n_done == 0)) rdy_low = 1'b0;
        @(posedge clk);
        if (core_ready) tk = cyc;
        #1;
        t++;
      end
      core_valid = 1'b0;
      chk($sformatf("the held request was taken after done (%0d > %0d)",
                    tk, done_cyc), (n_done == 1) && (tk > done_cyc));
    end
    wait_done();
    wait_rsp(12);
    chk("ready was low until done", rdy_low);
    for (int k = 4; k < 8; k++)
      chk($sformatf("drained request %0d answered before done", k),
          r_got[k] && (r_cyc[k] < done_cyc));
    chk("done is one cycle wide", !core_inv_done);
    @(posedge clk);
    #1;
    for (int k = 0; k < 8; k++) begin
      int g0;
      g0 = gets(lnof((BASE + 36'(k * 64))));
      fetch(4'(k), BASE + 36'(k * 64), 1'b0, v);
      chk($sformatf("line %0d misses after inv_all", k),
          gets(lnof((BASE + 36'(k * 64)))) == g0 + 1);
    end
  endtask

  task automatic t_inv_idle_timing();
    int v;
    reset_all("inv_idle");
    fetch(0, BASE, 1'b0, v);
    inv(1'b1, 36'h0);
    // A second operation presented at once is held until the first's
    // done (IF-28): it is taken only after it.
    chk("inv_rdy low while one is in progress", !core_inv_rdy);
    core_inv_val  = 1'b1;
    core_inv_all  = 1'b0;
    core_inv_addr = BASE;
    begin
      int t;
      int tk;
      int d1;
      t  = 0;
      tk = -1;
      d1 = -1;
      while ((tk < 0) && (t < 200)) begin
        @(posedge clk);
        if (core_inv_done) d1 = cyc;
        if (core_inv_rdy) tk = cyc;
        #1;
        t++;
      end
      core_inv_val = 1'b0;
      // Accept in T, drain seen empty in T+1, clear in T+2, done in T+3.
      chk($sformatf("idle inv_all: done 3 cycles after accept (%0d)",
                    d1 - inv_take_cyc), d1 - inv_take_cyc == 3);
      chk($sformatf({"the second operation was taken after the first's ",
                     "done (%0d > %0d)"}, tk, d1), (d1 >= 0) && (tk > d1));
    end
    begin
      int t;
      t = 0;
      while ((n_done < 2) && (t < 200)) begin
        @(posedge clk);
        #1;
        t++;
      end
      chk("the second operation completed", n_done == 2);
    end
  endtask

  // inv_line drains only its own register and masks the offset.
  task automatic t_inv_line();
    logic [35:0] la;
    logic [35:0] lb;
    logic [35:0] lc;
    int v;
    reset_all("inv_line");
    la = BASE + 36'h0400;
    lb = BASE + 36'h0440;                              // other bank
    lc = BASE + 36'h4800;                              // other set
    fetch(0, lc, 1'b0, v);                             // resident
    fetch(1, la, 1'b0, v);                             // resident
    lat[lnof(la)] = 8;
    lat[lnof(lb)] = 200;                                // held long
    ver[lnof(la)] = 1;
    issue(2, lb, 1'b0);
    inv(1'b0, la + 36'h24);                            // not aligned
    wait_done();
    chk("inv_line did not wait for another line's fill", !r_got[2]);
    @(posedge clk);
    #1;
    fetch(3, la, 1'b0, v);
    chk("the named line misses after inv_line", gets(lnof(la)) == 2);
    chk("and is refilled from memory", v == 1);
    fetch(4, lc, 1'b0, v);
    chk("a line in another set still hits", gets(lnof(lc)) == 1);
    wait_rsp(2);
  endtask

  task automatic t_inv_line_drain();
    logic [35:0] la;
    int v;
    reset_all("inv_line_drain");
    la = BASE + 36'h0800;
    lat[lnof(la)] = 25;
    issue(0, la, 1'b0);                                // in flight
    inv(1'b0, la + 36'h3C);                            // not aligned, IF-29
    wait_done();
    chk("the line's own fill was drained before done",
        r_got[0] && (r_cyc[0] < done_cyc));
    @(posedge clk);
    #1;
    fetch(1, la, 1'b0, v);
    chk("the line drained in was then cleared", gets(lnof(la)) == 2);
  endtask

  // =================================================================
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    cyc      = 0;
    rstn     = 1'b0;
    t_unc_resident();
    t_unc_absent();
    t_unc_plru();
    t_unc_merge();
    t_unc_merge_resident();
    t_inv_all();
    t_inv_idle_timing();
    t_inv_line();
    t_inv_line_drain();
    $display("tb_l1i: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_l1i: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #2000000;
    $fatal(1, "tb_l1i: timeout");
  end

endmodule : tb
