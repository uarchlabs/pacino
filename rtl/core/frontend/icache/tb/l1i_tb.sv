// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      l1i_tb.sv
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// Unit testbench for node 'l1i'.
//
// The node under test, a driver on each of its 1 slave
// interface and a responder on its downstream link. Every port list
// here comes from the same link bundle the RTL came from, so
// this testbench cannot be driving a different design from the
// one that was emitted.
//
// PACINO CHANGES (BP-123, cachegen_decisions.md CG-D1). The ports
// BP-123 added to the copy are tied off here: no uncached request and
// no invalidate, so every test below runs the emitted behaviour. The
// run ends with $fatal when a check failed, so the simulator's exit
// status carries the result (CLAUDE.md, Verification Expectations).
// The BP-123 behaviour is tested by tb/tb_l1i.sv.
//--------------------------------------------------------------------
// The import is at file scope and before the module, which is what
// the project verilog style asks for. Verilator's IMPORTSTAR objects
// to a wildcard in $unit scope, so it is turned off across these
// lines and nowhere else.
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
import cgen_tl_pkg::*;
/* verilator lint_on IMPORTSTAR */

module l1i_tb;

  logic clk;
  logic rstn;

  // Clock period is simulation control, not configuration,
  // D-41. It is a build time parameter, overridable with
  // -GHalfPeriod=<n>, and never an input field. A run time
  // variable here would make the delay statically unknown.
  parameter int unsigned HalfPeriod = 5;

  initial begin
    clk = 1'b0;
    forever #HalfPeriod clk = ~clk;
  end

  // interface 'core', link 'pe_port_i'
  logic                 core_valid;
  logic [35:0]          core_addr;
  logic [3:0]           core_id;
  logic                 core_prefetch;
  logic [511:0]         core_rdata;
  logic                 core_ready;
  logic                 core_rvalid;
  logic [3:0]           core_rid;
  logic                 core_rerr;
  logic                 core_inv_rdy;
  logic                 core_inv_done;

  // interface 'mem', link 'tl_l1i_l2'
  logic                 mem_a_valid;
  logic                 mem_a_ready;
  logic [2:0]           mem_a_opcode;
  logic [2:0]           mem_a_param;
  logic [2:0]           mem_a_size;
  logic [3:0]           mem_a_source;
  logic [35:0]          mem_a_address;
  logic [31:0]          mem_a_mask;
  logic [255:0]         mem_a_data;
  logic                 mem_a_corrupt;
  logic                 mem_d_valid;
  logic                 mem_d_ready;
  logic [2:0]           mem_d_opcode;
  logic [2:0]           mem_d_param;
  logic [2:0]           mem_d_size;
  logic [3:0]           mem_d_source;
  logic [1:0]           mem_d_sink;
  logic                 mem_d_denied;
  logic [255:0]         mem_d_data;
  logic                 mem_d_corrupt;

`include "cgen_tb_tasks.svh"

  l1i u_dut (
    .clk  (clk),
    .rstn (rstn),
    .core_valid          (core_valid),
    .core_addr           (core_addr),
    .core_id             (core_id),
    .core_prefetch       (core_prefetch),
    .core_uncached       (1'b0),
    .core_rdata          (core_rdata),
    .core_ready          (core_ready),
    .core_rvalid         (core_rvalid),
    .core_rid            (core_rid),
    .core_rerr           (core_rerr),
    .core_inv_val        (1'b0),
    .core_inv_rdy        (core_inv_rdy),
    .core_inv_all        (1'b0),
    .core_inv_addr       (36'h0),
    .core_inv_done       (core_inv_done),
    .mem_a_valid         (mem_a_valid),
    .mem_a_ready         (mem_a_ready),
    .mem_a_opcode        (mem_a_opcode),
    .mem_a_param         (mem_a_param),
    .mem_a_size          (mem_a_size),
    .mem_a_source        (mem_a_source),
    .mem_a_address       (mem_a_address),
    .mem_a_mask          (mem_a_mask),
    .mem_a_data          (mem_a_data),
    .mem_a_corrupt       (mem_a_corrupt),
    .mem_d_valid         (mem_d_valid),
    .mem_d_ready         (mem_d_ready),
    .mem_d_opcode        (mem_d_opcode),
    .mem_d_param         (mem_d_param),
    .mem_d_size          (mem_d_size),
    .mem_d_source        (mem_d_source),
    .mem_d_sink          (mem_d_sink),
    .mem_d_denied        (mem_d_denied),
    .mem_d_data          (mem_d_data),
    .mem_d_corrupt       (mem_d_corrupt)
  );

  // held high, the responder takes no request. See the note
  // on the responder for why a test needs that.
  logic tb_hold;

  // the rest of what a test can ask the responder for:
  // hold channel D so fills accumulate, interleave their
  // beats, and serve the highest numbered source first
  // so a later fill completes before an earlier one
  logic tb_dhold;
  logic tb_ilv;
  logic tb_rev;

  l1i_tb_mem u_mem_mem (
    .clk     (clk),
    .rstn    (rstn),
    .tb_hold (tb_hold),
    .tb_dhold(tb_dhold),
    .tb_ilv  (tb_ilv),
    .tb_rev  (tb_rev),
    .mem_a_valid         (mem_a_valid),
    .mem_a_ready         (mem_a_ready),
    .mem_a_opcode        (mem_a_opcode),
    .mem_a_param         (mem_a_param),
    .mem_a_size          (mem_a_size),
    .mem_a_source        (mem_a_source),
    .mem_a_address       (mem_a_address),
    .mem_a_mask          (mem_a_mask),
    .mem_a_data          (mem_a_data),
    .mem_a_corrupt       (mem_a_corrupt),
    .mem_d_valid         (mem_d_valid),
    .mem_d_ready         (mem_d_ready),
    .mem_d_opcode        (mem_d_opcode),
    .mem_d_param         (mem_d_param),
    .mem_d_size          (mem_d_size),
    .mem_d_source        (mem_d_source),
    .mem_d_sink          (mem_d_sink),
    .mem_d_denied        (mem_d_denied),
    .mem_d_data          (mem_d_data),
    .mem_d_corrupt       (mem_d_corrupt)
  );

  // -------------------------------------------------------
  // The response collector. IT STANDS ON THE PORT rather
  // than being called, because a response may arrive for an
  // identifier no task is currently waiting on, which is
  // what out of order return means.
  //
  // nb_ord is the ARRIVAL ORDER of each identifier's
  // answer. Two identifiers whose order is the reverse of
  // the order they were presented in is the whole of the
  // out of order proof.
  // -------------------------------------------------------
  int unsigned nb_n;
  logic        nb_seen [L1iMaxOutstanding];
  l1i_word_t       nb_data [L1iMaxOutstanding];
  logic        nb_err  [L1iMaxOutstanding];
  int unsigned nb_ord  [L1iMaxOutstanding];
  int unsigned nb_fill;   // fills the responder was asked for

  // WHEN each identifier was accepted and when it was
  // answered, in cycles, so a test can MEASURE a latency
  // rather than assume one.
  int unsigned nb_acc [L1iMaxOutstanding];
  int unsigned nb_rsp [L1iMaxOutstanding];

  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) begin
      nb_n    <= 0;
      nb_fill <= 0;
    end else begin
      if(core_rvalid) begin
        nb_seen[core_rid] <= 1'b1;
        nb_data[core_rid] <= l1i_word_t'(core_rdata);
        nb_err [core_rid] <= core_rerr;
        nb_ord [core_rid] <= nb_n;
        nb_rsp [core_rid] <= cg_cycle;
        nb_n <= nb_n + 1;
      end
      if(core_valid && core_ready) begin
        nb_acc[core_id] <= cg_cycle;
      end
      // one count of what actually left for memory, so a
      // merge can be shown to have asked for ONE fill
      if(mem_a_valid && mem_a_ready) begin
        nb_fill <= nb_fill + 1;
      end
    end
  end

  // -----------------------------------------------------
  // THE MEMORY SIDE, COUNTED AT THE LINK. A fill is in
  // flight from the cycle its A beat is taken to the
  // cycle ITS last D beat arrives, so this counts what
  // the node actually has outstanding rather than what
  // it is allowed to.
  //
  // nb_ilv counts the beats that arrived for one fill
  // WHILE ANOTHER was part way through its own line,
  // which is the whole of what interleaving is. A
  // responder that finishes one line before starting the
  // next leaves it at zero.
  // -----------------------------------------------------
  int unsigned nb_flt;    // in flight right now
  int unsigned nb_pk;     // the most there ever were
  int unsigned nb_ilv;    // interleaved beats
  int unsigned nb_bt [L1iMshrs];  // beats of each fill so far

  wire nb_a_fire = mem_a_valid && mem_a_ready;
  wire nb_d_fire = mem_d_valid && mem_d_ready;
  wire nb_d_last = nb_d_fire &&
      (nb_bt[mem_d_source] == L1iBeats-1);

  logic        nb_other;
  int unsigned nb_flt_nx;

  always_comb begin
    nb_other = 1'b0;
    for(int unsigned m = 0; m < L1iMshrs; m++) begin
      if((m != int'(mem_d_source)) &&
         (nb_bt[m] != 0)) nb_other = 1'b1;
    end

    // one net change, so an A and the last D of another
    // fill in the same cycle do not lose each other
    nb_flt_nx = nb_flt;
    if(nb_a_fire) nb_flt_nx = nb_flt_nx + 1;
    if(nb_d_last) nb_flt_nx = nb_flt_nx - 1;
  end

  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) begin
      nb_flt <= 0;
      nb_pk  <= 0;
      nb_ilv <= 0;
      for(int unsigned m = 0; m < L1iMshrs; m++) begin
        nb_bt[m] <= 0;
      end
    end else begin
      nb_flt <= nb_flt_nx;
      if(nb_flt_nx > nb_pk) nb_pk <= nb_flt_nx;
      if(nb_d_fire && nb_other) nb_ilv <= nb_ilv + 1;
      if(nb_d_fire) begin
        nb_bt[mem_d_source] <=
            nb_d_last ? 0 : nb_bt[mem_d_source] + 1;
      end
    end
  end

  // forget every answer so far, so a test starts clean
  task automatic nb_clear();
    nb_n    = 0;
    nb_fill = 0;
    for(int unsigned k = 0; k < L1iMaxOutstanding; k++) begin
      nb_seen[k] = 1'b0;
      nb_data[k] = '0;
      nb_err [k] = 1'b0;
      nb_ord [k] = 0;
      nb_acc [k] = 0;
      nb_rsp [k] = 0;
    end
    nb_pk  = 0;
    nb_ilv = 0;
  endtask

  // -------------------------------------------------------
  // Present one request and return as soon as it has been
  // ACCEPTED, not when it has been answered. valid is left
  // standing, so calls back to back are accepted one per
  // cycle. Call nb_idle when there are no more.
  // -------------------------------------------------------
  task automatic nb_req(input l1i_addr_t a,
                        input l1i_req_id_t id,
                        input logic pf,
                        output logic took);
    int unsigned spin;
    core_valid = 1'b1;
    core_addr  = a;
    core_id    = id;
    core_prefetch = pf;
    spin = 0;
    while(!core_ready && spin < cg_limit) begin
      @(negedge clk);
      spin = spin + 1;
    end
    took = core_ready;
    // the posedge that ends this cycle is the transfer
    @(negedge clk);
  endtask

  // take the request down and stop asking
  task automatic nb_idle();
    core_valid = 1'b0;
    core_prefetch = 1'b0;
    @(negedge clk);
  endtask

  // -------------------------------------------------------
  // Ready, WITH NO REQUEST PRESENTED. The node's ready must
  // not read valid, so this is a legitimate question and
  // the answer is what a request would meet.
  // -------------------------------------------------------
  task automatic nb_ready(input logic pf, output logic r);
    core_valid = 1'b0;
    core_prefetch = pf;
    @(negedge clk);
    r = core_ready;
    core_prefetch = 1'b0;
  endtask

  // -------------------------------------------------------
  // Present a request for a BOUNDED number of cycles and
  // say whether it was taken. A refusal is the answer this
  // is asked for, so it gives up quickly and a timeout is
  // not counted as a failure.
  // -------------------------------------------------------
  task automatic nb_try(input l1i_addr_t a,
                        input l1i_req_id_t id,
                        input logic pf,
                        input int unsigned n,
                        output logic took);
    int unsigned spin;
    core_valid = 1'b1;
    core_addr  = a;
    core_id    = id;
    core_prefetch = pf;
    took = 1'b0;
    spin = 0;
    while(!took && spin < n) begin
      took = core_ready;
      if(!took) @(negedge clk);
      spin = spin + 1;
    end
    if(took) @(negedge clk);   // past the transfer edge
    core_valid = 1'b0;
    core_prefetch = 1'b0;
    @(negedge clk);
  endtask

  // wait until an identifier's answer has arrived
  task automatic nb_wait(input l1i_req_id_t id,
                         output logic ok);
    int unsigned spin;
    spin = 0;
    while(!nb_seen[id] && spin < cg_limit) begin
      @(negedge clk);
      spin = spin + 1;
    end
    ok = nb_seen[id];
  endtask

  // -------------------------------------------------------
  // Drive one request into interface 'core'.
  //
  // EVERY EDGE HERE IS A NEGEDGE. The design clocks on the
  // posedge, so a testbench that drives or samples there is
  // racing it: the request can be taken in the same instant
  // it is presented, and a one cycle response can be gone
  // before it is looked at. Driving and sampling mid cycle
  // removes both races and needs no clocking block.
  // -------------------------------------------------------
  //
  // This is the BLOCKING form, on identifier 0. It is what
  // the tests that do not care about ordering use. The
  // nb_ tasks above are the ones that hold several in
  // flight.
  task automatic drv_core(input l1i_addr_t a,
                       input logic  wr,
                       input l1i_word_t d,
                       input logic [L1iWordBytes-1:0] be,
                       output l1i_word_t r);
    logic ok;
    int unsigned spin;

    @(negedge clk);
    core_valid = 1'b1;
    core_addr  = a;
    core_id    = '0;
    core_prefetch = 1'b0;

    ok   = core_ready;
    spin = 0;
    while(!ok && spin < cg_limit) begin
      @(negedge clk);
      ok   = core_ready;
      spin = spin + 1;
    end
    if(spin >= cg_limit) begin
      cg_fail = cg_fail + 1;
      $display("FAIL %0t drv_core request never accepted", $time);
    end

    @(negedge clk);
    core_valid = 1'b0;

    // the answer is the one carrying this identifier, and
    // nothing else about the response says which it is
    r    = '0;
    ok   = 1'b0;
    spin = 0;
    while(!ok && spin < cg_limit) begin
      ok = core_rvalid && (core_rid == '0);
      if(ok) r = l1i_word_t'(core_rdata);
      if(!ok) @(negedge clk);
      spin = spin + 1;
    end
    if(spin >= cg_limit) begin
      cg_fail = cg_fail + 1;
      $display("FAIL %0t drv_core no response", $time);
    end

    // PAST THE PRESENTATION. The identifier is retired by
    // the response being presented and may be reissued in
    // the NEXT cycle, so a caller that reissued the moment
    // this returned would be presenting it twice in one.
    @(negedge clk);

    // the write arguments are what every other node's
    // driver takes; this link declares no write channel
    /* verilator lint_off UNUSEDSIGNAL */
    if(wr || (|d) || (|be)) begin
      cg_fail = cg_fail + 1;
      $display("FAIL %0t drv_core asked for a write on a read only link",
               $time);
    end
    /* verilator lint_on UNUSEDSIGNAL */
  endtask

`include "l1i_tests.svh"

  // Everything the node does not drive on a slave interface
  // is driven here. The channels this design never runs are
  // held at zero rather than left floating, R-5.
  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_tb = |{
      core_rdata,
      core_ready,
      core_rvalid,
      core_rid,
      core_rerr,
      core_inv_rdy,
      core_inv_done
  };
  /* verilator lint_on UNUSEDSIGNAL */

  initial begin
    cg_init();
    tb_hold = 1'b0;
    tb_dhold = 1'b0;
    tb_ilv   = 1'b0;
    tb_rev   = 1'b0;
    core_valid = 1'b0;
    core_addr = '0;
    core_id = '0;
    core_prefetch = 1'b0;
    nb_clear();
    cg_reset(rstn);
    run_tests();
    cg_tick(8);
    if(cg_report("l1i_tb") != 0) $fatal(1, "l1i_tb: a check failed");
    $finish;
  end

endmodule
