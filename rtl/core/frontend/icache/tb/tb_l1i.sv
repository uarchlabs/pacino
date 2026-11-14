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

  // Address widths come from l1i_pkg (BP-147): a byte address is
  // l1i_addr_t, L1iPaBits wide, and a line address drops the offset.
  // They were written [35:0] and [29:0].
  typedef l1i_addr_t                          pa_t;
  typedef logic [L1iPaBits-L1iOffsetBits-1:0] ln_t;

  logic clk;
  logic rstn;
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ---- DUT ports -------------------------------------------------------
  logic         core_valid;
  pa_t          core_addr;
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
  pa_t          core_inv_addr;
  logic         core_inv_done;
  logic         mem_a_valid;
  logic         mem_a_ready;
  logic [2:0]   mem_a_opcode;
  logic [2:0]   mem_a_param;
  logic [2:0]   mem_a_size;
  logic [3:0]   mem_a_source;
  pa_t          mem_a_address;
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
  int ver   [ln_t];          // by line address
  int lat   [ln_t];          // per-line fill latency override
  int n_get [ln_t];
  int n_get_all;
  pa_t m_last;                       // the last Get's whole address, BP-147
  localparam int LAT_DFLT = 4;

  function automatic logic [511:0] line_val(input ln_t ln,
                                            input int v);
    logic [511:0] d;
    for (int w = 0; w < 16; w++)
      d[32*w +: 32] = {ln[23:0], 8'(v)} ^ 32'(w * 32'h0101_0101);
    return d;
  endfunction

  function automatic ln_t lnof(input pa_t a);
    return ln_t'(a >> L1iOffsetBits);
  endfunction

  function automatic int ver_of(input ln_t ln);
    return ver.exists(ln) ? ver[ln] : 0;
  endfunction

  function automatic int gets(input ln_t ln);
    return n_get.exists(ln) ? n_get[ln] : 0;
  endfunction

  logic        q_val  [0:15];
  ln_t         q_ln   [0:15];
  int          q_due  [0:15];
  logic        d_busy;
  logic [3:0]  d_src;
  logic        d_beat;
  logic [511:0] d_line;

  assign mem_a_ready = rstn;

  initial begin : tl_mem
    logic        s_a;
    logic [3:0]  s_src;
    ln_t         s_ln;
    logic        s_d;
    pa_t         s_addr;
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
      s_ln  = lnof(mem_a_address);
      s_addr = mem_a_address;
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
          m_last = s_addr;
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
  task automatic issue(input logic [3:0] id, input pa_t a,
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
  task automatic fetch(input logic [3:0] id, input pa_t a,
                       input logic unc, output int v);
    issue(id, a, unc);
    wait_rsp(id);
    v = -1;
    for (int k = 0; k < 256; k++)
      if (r_data[id] == line_val(lnof(a), k)) v = k;
  endtask

  task automatic inv(input logic all, input pa_t a);
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
  localparam pa_t BASE = pa_t'('h0_8000_0000);
  function automatic pa_t same_set(input int k);
    return BASE + pa_t'(k) * pa_t'('h2000);
  endfunction

  // =================================================================
  // Uncached (L1I-24).
  // =================================================================
  task automatic t_unc_resident();
    pa_t a;
    int v;
    a = BASE + pa_t'('h1C0);
    reset_all("unc_resident");
    fetch(0, a, 1'b0, v);
    chk("a cacheable miss fills version 0", v == 0);
    fetch(1, a, 1'b0, v);
    chk("a second cacheable request hits", gets(lnof(a)) == 1);
    ver[lnof(a)] = 1;                                  // memory changes
    fetch(2, a, 1'b1, v);
    chk("an uncached request to a resident line is a miss",
        gets(lnof(a)) == 2);
    chk("it is answered from memory, version 1", v == 1);
    fetch(3, a, 1'b0, v);
    chk("the array still holds version 0: not written", v == 0);
    chk("and that cacheable request hit", gets(lnof(a)) == 2);
  endtask

  task automatic t_unc_absent();
    pa_t a;
    int v;
    a = BASE + pa_t'('h240);
    reset_all("unc_absent");
    fetch(0, a, 1'b1, v);
    chk("an uncached miss is fetched", (gets(lnof(a)) == 1) && (v == 0));
    fetch(1, a, 1'b1, v);
    chk("a second uncached request is fetched again", gets(lnof(a)) == 2);
    fetch(2, a, 1'b0, v);
    chk("a cacheable request after it misses: never allocated",
        gets(lnof(a)) == 3);
    fetch(3, a, 1'b0, v);
    chk("and that one allocated", gets(lnof(a)) == 3);
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
    pa_t a;
    int v;
    a = BASE + pa_t'('h300);
    reset_all("unc_merge_c_onto_u");
    lat[lnof(a)] = 40;                                 // hold the fill
    issue(0, a, 1'b1);                                 // uncached
    repeat (3) @(posedge clk);
    #1;
    issue(1, a, 1'b0);                                 // cacheable
    wait_rsp(0);
    wait_rsp(1);
    chk("one fill for both", gets(lnof(a)) == 1);
    chk("both answered with the line", (r_data[0] == line_val(lnof(a), 0))
        && (r_data[1] == line_val(lnof(a), 0)));
    fetch(2, a, 1'b0, v);
    chk("the merged cacheable request allocated: a hit",
        gets(lnof(a)) == 1);

    reset_all("unc_merge_u_onto_c");
    lat[lnof(a)] = 40;
    issue(0, a, 1'b0);                                 // cacheable miss
    repeat (3) @(posedge clk);
    #1;
    ver[lnof(a)] = 2;                                  // before the fill
    issue(1, a, 1'b1);                                 // uncached
    wait_rsp(0);
    wait_rsp(1);
    chk("one fill for both", gets(lnof(a)) == 1);
    chk("the uncached request has the fill's data, from memory",
        r_data[1] == line_val(lnof(a), 2));

    // The cacheable lookup is still in flight (accepted last cycle): the
    // uncached request takes its own register rather than risk an
    // answer from the array.
    reset_all("unc_own_reg");
    lat[lnof(a)] = 20;
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
    chk($sformatf("two fills (%0d)", gets(lnof(a))), gets(lnof(a)) == 2);
    fetch(2, a, 1'b0, v);
    chk("the cacheable one allocated", gets(lnof(a)) == 2);
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

  // A cacheable request merged onto an uncached register, in the cycle
  // that register's fill lands (BP-125, TD#172; L1I-24, IF-44a) or
  // earlier. The set is full and line 0 is the tree-PLRU victim (cold
  // fill of ways 0 to 7, as plru_run's control shows). An uncached
  // request to line 0 names line 0's own way; memory then changes to
  // version 1 and the cacheable request merges onto the register. L1I-24
  // makes the merged request allocate: the fill is installed, so a later
  // hit returns version 1 (run "inst"), and the replacement state moves
  // as for any cacheable access, so a ninth line evicts some other line
  // and line 0 still hits (run "repl"). Each is its own run from reset:
  // the install check's hit would itself move the replacement state.
  //
  // THE FILL'S OWN CYCLE. The memory model completes a line on its
  // second D beat; l1i_mem_mst registers the line, so the fill lands in
  // the cycle after that beat's handshake. The cacheable request is
  // presented in exactly that cycle and accepted at its edge. l1i_mshr
  // still holds the register as not yet returned in that cycle, so the
  // request merges, and fil_alloc's second term is what installs the
  // fill. Observed at the ports: the request is accepted in the
  // presentation cycle, one Get is made for both, and the fill installs.
  task automatic unc_merge_fill(input string nm, input logic fill_cyc,
                                input logic repl);
    int v;
    int g0;
    int e_cyc;
    int a_cyc;
    logic last;
    logic rdy_at;
    reset_all(nm);
    for (int k = 0; k < 8; k++) fetch(4'(k), same_set(k), 1'b0, v);
    g0 = gets(lnof(same_set(0)));
    lat[lnof(same_set(0))] = 12;
    issue(8, same_set(0), 1'b1);                        // uncached
    ver[lnof(same_set(0))] = 1;                         // before the fill
    if (fill_cyc) begin
      // Wait for the handshake of the line's last D beat.
      last  = 1'b0;
      e_cyc = 0;
      for (int t = 0; (t < 100) && !last; t++) begin
        @(posedge clk);
        last  = mem_d_valid && mem_d_ready && d_beat;
        e_cyc = cyc;
        #1;
      end
      // The fill lands in this cycle: present the cacheable request.
      core_valid    = 1'b1;
      core_id       = 4'd9;
      core_addr     = same_set(0);
      core_uncached = 1'b0;
      r_got[9]      = 1'b0;
      rdy_at        = core_ready;
      @(posedge clk);
      a_cyc = cyc;
      #1;
      core_valid = 1'b0;
      chk("the last beat was seen", last);
      chk($sformatf("accepted in the fill's cycle (beat %0d, accept %0d)",
                    e_cyc, a_cyc), rdy_at && (a_cyc == e_cyc + 1));
    end else begin
      repeat (3) @(posedge clk);
      #1;
      issue(9, same_set(0), 1'b0);                      // merges early
    end
    wait_rsp(8);
    wait_rsp(9);
    chk("one fill for both", gets(lnof(same_set(0))) == g0 + 1);
    chk("both answered with the new line",
        (r_data[8] == line_val(lnof(same_set(0)), 1)) &&
        (r_data[9] == line_val(lnof(same_set(0)), 1)));
    if (!repl) begin
      fetch(10, same_set(0), 1'b0, v);
      chk("the fill was installed: a hit",
          gets(lnof(same_set(0))) == g0 + 1);
      chk($sformatf("of the new line, version 1 (%0d)", v), v == 1);
    end else begin
      fetch(11, same_set(8), 1'b0, v);                 // a ninth line
      chk("the ninth line was fetched", gets(lnof(same_set(8))) == 1);
      g0 = gets(lnof(same_set(0)));
      fetch(12, same_set(0), 1'b0, v);
      chk("the replacement state moved: line 0 was not the victim",
          gets(lnof(same_set(0))) == g0);
    end
  endtask

  // THE SAME SET MOVED TWICE IN ONE CYCLE (BP-125). The install's
  // replacement update and a lookup's compare-stage update can name one
  // set in one cycle: a cacheable hit to line 4 of the set is accepted
  // in the cycle of the fill's last beat, so its compare stage is the
  // fill's own cycle, in which the merged request makes the install
  // move way 0. Both updates must land. From the cold-filled set, whose
  // victim is way 0: way 0 moved alone leaves way 4 the victim; way 4
  // then way 0 leaves way 6. So the ninth line evicts line 6 and line 4
  // still hits; with either update lost it evicts line 4 or line 0.
  task automatic unc_merge_fill_cmp();
    int v;
    int g4;
    int g6;
    logic first;
    reset_all("unc_merge_fill_cycle_cmp");
    for (int k = 0; k < 8; k++) fetch(4'(k), same_set(k), 1'b0, v);
    lat[lnof(same_set(0))] = 12;
    issue(8, same_set(0), 1'b1);                        // uncached
    // Wait for the handshake of the line's FIRST D beat; the last beat
    // is the next cycle and the fill lands the cycle after that.
    first = 1'b0;
    for (int t = 0; (t < 100) && !first; t++) begin
      @(posedge clk);
      first = mem_d_valid && mem_d_ready && !d_beat;
      #1;
    end
    chk("the first beat was seen", first);
    // The last beat's cycle: a cacheable hit to line 4 of the set.
    core_valid    = 1'b1;
    core_id       = 4'd13;
    core_addr     = same_set(4);
    core_uncached = 1'b0;
    r_got[13]     = 1'b0;
    @(posedge clk);
    chk("the hit was accepted in the last beat's cycle",
        core_ready && mem_d_valid && d_beat);
    #1;
    // The fill's own cycle: the cacheable request merges.
    core_id       = 4'd9;
    core_addr     = same_set(0);
    r_got[9]      = 1'b0;
    @(posedge clk);
    chk("the merge was accepted in the fill's cycle", core_ready);
    #1;
    core_valid = 1'b0;
    wait_rsp(13);
    wait_rsp(8);
    wait_rsp(9);
    chk("line 4 hit", gets(lnof(same_set(4))) == 1);
    fetch(11, same_set(8), 1'b0, v);                    // a ninth line
    g4 = gets(lnof(same_set(4)));
    g6 = gets(lnof(same_set(6)));
    fetch(12, same_set(4), 1'b0, v);
    chk("both updates landed: line 4 was not the victim",
        gets(lnof(same_set(4))) == g4);
    fetch(14, same_set(6), 1'b0, v);
    chk("line 6 was the victim", gets(lnof(same_set(6))) == g6 + 1);
  endtask

  task automatic t_unc_merge_fill();
    unc_merge_fill("unc_merge_fill_cycle_inst",  1'b1, 1'b0);
    unc_merge_fill("unc_merge_fill_cycle_repl",  1'b1, 1'b1);
    unc_merge_fill("unc_merge_before_fill_inst", 1'b0, 1'b0);
    unc_merge_fill("unc_merge_before_fill_repl", 1'b0, 1'b1);
    unc_merge_fill_cmp();
  endtask

  // =================================================================
  // Install-time replacement (BP-132, TD#177; L1I-24).
  // =================================================================
  // A CACHEABLE MISS MOVES THE REPLACEMENT STATE ONCE, in its compare
  // stage, and not again when its fill installs: l1i_ctrl gates the
  // install-time update (meta_fp_en) to a register whose lookup was
  // uncached. The test puts an access to the set between a cacheable
  // miss's lookup and its fill, so a second update at the fill would
  // undo that access's.
  //
  // The set is cold-filled with lines 0 to 7 in ways 0 to 7 (D-40,
  // lowest invalid way first). The expected victims below are the
  // l1i_pkg replacement tables walked by hand from that state (the
  // tables are the encoding the control uses, D-39):
  //   cold fill, ways 0..7                     victim way 0
  //   line 8 misses, compare moves way 0       victim way 4
  //   line 4 hits, moves way 4                 victim way 2
  //   line 8's fill installs in way 0:
  //     no update (the gate)                   victim way 2
  //     a second update of way 0 (no gate)     victim way 6
  // Line 9, a tenth line, then evicts line 2 with the gate and line 6
  // without it. The hit to line 4 must be answered before line 8's
  // fill: line 8's fill is held for HOLD cycles and the order is
  // checked, not assumed.
  task automatic t_fill_rpl();
    localparam int HOLD = 20;
    int v;
    reset_all("fill_rpl_once");
    for (int k = 0; k < 8; k++) fetch(4'(k), same_set(k), 1'b0, v);
    for (int k = 0; k < 8; k++)
      chk($sformatf("cold fill: line %0d fetched once", k),
          gets(lnof(same_set(k))) == 1);
    lat[lnof(same_set(8))] = HOLD;
    issue(8, same_set(8), 1'b0);                       // cacheable miss
    repeat (2) @(posedge clk);
    #1;
    fetch(9, same_set(4), 1'b0, v);                    // hit, same set
    chk("line 4 hit: no Get", gets(lnof(same_set(4))) == 1);
    chk("line 4 answered before line 8's fill", !r_got[8]);
    wait_rsp(8);
    chk("line 8 fetched once", gets(lnof(same_set(8))) == 1);
    fetch(10, same_set(9), 1'b0, v);                   // a tenth line
    chk("line 9 fetched once", gets(lnof(same_set(9))) == 1);
    // Hits first: a hit moves the replacement state but evicts nothing.
    fetch(11, same_set(6), 1'b0, v);
    chk("line 6 still hits: the fill did not move the state again",
        gets(lnof(same_set(6))) == 1);
    fetch(12, same_set(8), 1'b0, v);
    chk("line 8 was installed: a hit", gets(lnof(same_set(8))) == 1);
    fetch(13, same_set(2), 1'b0, v);
    chk("line 2 was the victim of line 9", gets(lnof(same_set(2))) == 2);
    fetch(14, same_set(0), 1'b0, v);
    chk("line 0 was the victim of line 8", gets(lnof(same_set(0))) == 2);
  endtask

  // =================================================================
  // Maintenance (IF-28 to IF-32, IF-42).
  // =================================================================
  task automatic t_inv_all();
    int v;
    logic rdy_low;
    reset_all("inv_all");
    // Four resident lines, then four misses held in flight.
    for (int k = 0; k < 4; k++) fetch(4'(k), BASE + pa_t'(k * 64), 1'b0, v);
    for (int k = 4; k < 8; k++) lat[lnof(BASE + pa_t'(k * 64))] = 30;
    for (int k = 4; k < 8; k++) issue(4'(k), BASE + pa_t'(k * 64), 1'b0);
    inv(1'b1, pa_t'('h0));
    // Ready is low until done; the drained requests are still answered.
    // A request presented throughout the invalidate is taken only after
    // done (IF-30).
    r_got[12]  = 1'b0;
    core_valid = 1'b1;
    core_id    = 4'd12;
    core_addr  = BASE + pa_t'('h1000);
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
      g0 = gets(lnof((BASE + pa_t'(k * 64))));
      fetch(4'(k), BASE + pa_t'(k * 64), 1'b0, v);
      chk($sformatf("line %0d misses after inv_all", k),
          gets(lnof((BASE + pa_t'(k * 64)))) == g0 + 1);
    end
  endtask

  task automatic t_inv_idle_timing();
    int v;
    reset_all("inv_idle");
    fetch(0, BASE, 1'b0, v);
    inv(1'b1, pa_t'('h0));
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
    pa_t la;
    pa_t lb;
    pa_t lc;
    int v;
    reset_all("inv_line");
    la = BASE + pa_t'('h0400);
    lb = BASE + pa_t'('h0440);                         // other bank
    lc = BASE + pa_t'('h4800);                         // other set
    fetch(0, lc, 1'b0, v);                             // resident
    fetch(1, la, 1'b0, v);                             // resident
    lat[lnof(la)] = 8;
    lat[lnof(lb)] = 200;                                // held long
    ver[lnof(la)] = 1;
    issue(2, lb, 1'b0);
    inv(1'b0, la + pa_t'('h24));                       // not aligned
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
    pa_t la;
    int v;
    reset_all("inv_line_drain");
    la = BASE + pa_t'('h0800);
    lat[lnof(la)] = 25;
    issue(0, la, 1'b0);                                // in flight
    inv(1'b0, la + pa_t'('h3C));                       // not aligned, IF-29
    wait_done();
    chk("the line's own fill was drained before done",
        r_got[0] && (r_cyc[0] < done_cyc));
    @(posedge clk);
    #1;
    fetch(1, la, 1'b0, v);
    chk("the line drained in was then cleared", gets(lnof(la)) == 2);
  endtask

  // =================================================================
  // BP-147: the top physical address bit (IF-1, L1I-20).
  // =================================================================
  // A core address with bit PA_WIDTH - 1 set is a miss, leaves on the
  // memory port whole, fills, and hits. A second address that differs
  // only in that bit names the same set and bank and a tag that differs
  // only in its top bit: it is a second line, filled from its own memory
  // content (version 3), and each then hits on its own data. PA_WIDTH is
  // bp_defines_pkg's, the core interface's width, so an L1I narrower
  // than it fails here rather than dropping the bit unseen.
  localparam int PAW = bp_defines_pkg::PA_WIDTH;

  task automatic t_pa_top_bit();
    pa_t lo;
    pa_t hi;
    int  v;
    reset_all("pa_top_bit");
    chk($sformatf("the L1I address is PA_WIDTH (%0d) bits (%0d)", PAW,
                  $bits(pa_t)), $bits(pa_t) == PAW);
    lo = BASE + pa_t'('h0C40);
    hi = lo | (pa_t'(1) << (PAW - 1));
    chk("the two lines share a set and a bank",
        (l1i_set_of(lo) == l1i_set_of(hi)) &&
        (l1i_bank_of(lo) == l1i_bank_of(hi)));
    chk("their tags differ in the top tag bit only",
        (l1i_tag_of(lo) ^ l1i_tag_of(hi)) ==
        (l1i_tag_t'(1) << (L1iTagBits - 1)));
    ver[lnof(lo)] = 3;
    fetch(0, hi, 1'b0, v);
    chk("bit PA_WIDTH - 1: a miss, one Get for its own line",
        (gets(lnof(hi)) == 1) && (gets(lnof(lo)) == 0) && (v == 0));
    chk($sformatf("the memory port carried the whole address (%h)", m_last),
        m_last == l1i_line_base(hi));
    fetch(1, hi, 1'b0, v);
    chk("bit PA_WIDTH - 1: then a hit", (gets(lnof(hi)) == 1) && (v == 0));
    fetch(2, lo, 1'b0, v);
    chk("the address without the bit is a second line, from memory",
        (gets(lnof(lo)) == 1) && (v == 3) && (m_last == l1i_line_base(lo)));
    fetch(3, hi, 1'b0, v);
    chk("the top-bit line still hits on its own data",
        (gets(lnof(hi)) == 1) && (v == 0));
    fetch(4, lo, 1'b0, v);
    chk("and the other on its own", (gets(lnof(lo)) == 1) && (v == 3));
    chk("two Gets in all", n_get_all == 2);
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
    t_unc_merge_fill();
    t_fill_rpl();
    t_inv_all();
    t_inv_idle_timing();
    t_inv_line();
    t_inv_line_drain();
    t_pa_top_bit();
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
