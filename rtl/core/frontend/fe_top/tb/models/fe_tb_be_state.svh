// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fe_tb_be_state.svh -- the in-order backend's state
//
// A SHARED FRONT-END TESTBENCH MODEL (DOC-001, fe_demo_tb_decisions.md
// FDT-4). Not a compilation unit: it is included inside the body of
// module tb, after the package imports, by tb_fe_top
// (rtl/core/frontend/fe_top/tb) and tb_fe_demo (examples/fe_demo/tb),
// in the order those files give. The text was moved here from
// tb_fe_top.sv unchanged except where this header says otherwise.
//
// Holds: the backend model's state and its counters; the warm-up
// boundary; the FTQ fetch log (the block start the FTQ presented per
// index, the predecode redirect count, the per-index fetch and
// writeback flags of the eager mode); the RAS commit log; the +TRACE
// switch. Included before anything that reads them; the backend
// process itself is fe_tb_backend.svh.
//
// CHANGED FROM tb_fe_top.sv: be_rdy_pat is new (FD-20).
// ===================================================================

  // The warm-up boundary: mispredicts of expected entries from warm_e
  // on are reported as after warm-up. Programs set it.
  int warm_e;

  // BP-121: the RAS commit check. ras_exp holds the RAS operations of
  // the retired stream, in program order, with the link address a
  // push writes; ras_got holds the commits the cluster performed.
  typedef struct {
    bp_br_type_e         t;
    logic [VA_WIDTH-1:0] ra;
    logic [VA_WIDTH-1:0] pc;
  } rasev_t;
  rasev_t                  ras_exp [$];
  rasev_t                  ras_got [$];
  int                      n_ras_ok;
  int                      n_ras_bad;

  // =================================================================
  // The FTQ fetch log: the block start the FTQ presented for each
  // index, taken from the FTQ-to-IFU fetch handshake inside the top.
  // =================================================================
  logic [VA_WIDTH-1:0] fstart [0:FTQ_DEPTH-1];
  int                  n_pd_redir;
  // BP-125 (TD#174): predecode redirects whose mis_pos names a
  // conditional with uc_end clear. Predecode reports a conditional at
  // mis_pos only under M3 (M1 names a JAL, M2 a non-CFI, M4 an
  // unfetched position), so these are the M3 writebacks W1 now
  // rewrites with the entry's taken kept.
  int                  n_m3_cond;
  // BP-121, TD#167: the measurement window. Set by the backend after
  // every edge; high while a program runs and has not yet retired its
  // last expected instruction, so no count includes the drain.
  logic                meas;

  // BP-123: per index, a fetch of it since the last flush that covered
  // it (fseen), and the IFU's writeback of it since then (wbseen). The
  // eager backend resolves a branch from them; see the backend model.
  logic [FTQ_DEPTH-1:0] fseen;
  logic [FTQ_DEPTH-1:0] wbseen;

  function automatic logic fl_covers(input logic [FTQ_IDX_BITS-1:0] i);
    return FTQ_IDX_BITS'(i - dut.ftq_ifu_commit_ptr) >=
           FTQ_IDX_BITS'(dut.ftq_ifu_flush_idx - dut.ftq_ifu_commit_ptr);
  endfunction

  always @(posedge clk) begin : fetch_log
    if (rstn && dut.ftq_ifu_req_val && dut.ftq_ifu_req_rdy &&
        !dut.ftq_ifu_flush_val)
      fstart[dut.ftq_ifu_idx] <= dut.ftq_ifu_start_pc;
    if (meas && dut.u_ftq.w_pd_redir_val && !bkend_ftq_redir_val)
      n_pd_redir <= n_pd_redir + 1;
    if (meas && dut.u_ftq.w_pd_redir_val && !bkend_ftq_redir_val &&
        !dut.ifu_ftq_uc_end &&
        dut.ifu_ftq_pd[dut.ifu_ftq_mis_pos].valid &&
        (dut.ifu_ftq_pd[dut.ifu_ftq_mis_pos].br_type == 2'b01))
      n_m3_cond <= n_m3_cond + 1;
    if (!rstn) begin
      fseen  <= '0;
      wbseen <= '0;
    end else begin
      for (int i = 0; i < FTQ_DEPTH; i++) begin
        if (dut.ftq_ifu_flush_val && fl_covers(FTQ_IDX_BITS'(i))) begin
          fseen[i]  <= 1'b0;
          wbseen[i] <= 1'b0;
        end else begin
          if (dut.ftq_ifu_req_val && dut.ftq_ifu_req_rdy &&
              (dut.ftq_ifu_idx == FTQ_IDX_BITS'(i))) begin
            fseen[i]  <= 1'b1;
            wbseen[i] <= 1'b0;
          end
          if (dut.ifu_ftq_pdwb_val &&
              (dut.ifu_ftq_pdwb_idx == FTQ_IDX_BITS'(i)))
            wbseen[i] <= 1'b1;
        end
      end
    end
  end

  // +TRACE: the cycle trace for diagnosis (tb_fe_top's trace_log, and
  // the backend's RETIRE and MISP lines).
  logic trace;
  initial trace = $test$plusargs("TRACE");

  // BP-121: every RAS commit the cluster performs (after its type
  // qualification), compared in order with the retired stream by the
  // backend below.
  always @(posedge clk) begin : ras_commit_log
    if (rstn && dut.u_bpu.w_ras_commit_val) begin
      rasev_t g;
      g.t  = dut.ras_commit_br_type;
      g.ra = dut.ras_commit_ret_addr;
      g.pc = '0;
      ras_got.push_back(g);
    end
  end

  // =================================================================
  // The backend model.
  // =================================================================
  int                      ep;          // next expected entry
  logic                    run_be;      // take decode's output
  logic                    cfi_pend;    // last retired is a CFI
  int                      cfi_e;
  logic [FTQ_IDX_BITS-1:0] cfi_idx;
  logic [3:0]              cfi_pos;
  logic                    after_redir; // next retired starts an entry
  logic [FTQ_PTR_BITS-1:0] redir_next;  // its pointer
  logic                    cur_val;
  logic [FTQ_PTR_BITS-1:0] cur_ptr;
  logic                    wm_val;
  logic [FTQ_PTR_BITS-1:0] wm;
  int                      n_retired;
  int                      n_mispred;
  int                      n_trap;
  int                      n_err;
  int                      n_fault_ok;
  // BP-120: backend mispredicts of a return or a return-call, and of
  // the instruction at watch_pc (a program sets it; zero matches none).
  int                      n_mis_ras;
  int                      n_mis_watch;
  logic [VA_WIDTH-1:0]     watch_pc;
  // BP-121: mispredicts after warm-up, by branch type (indexed by the
  // bp_br_type_e encoding) and by PC; the PC's type is kept for the
  // report.
  int                      n_mis_warm;
  int                      n_mis_type [0:7];
  int                      mis_pc  [logic [VA_WIDTH-1:0]];
  bp_br_type_e             mis_typ [logic [VA_WIDTH-1:0]];
  // A resolution queue, presented on port 0.
  ftq_resolve_t            rq [0:255];
  int                      rq_hd;
  int                      rq_tl;
  // The redirect to present next cycle.
  logic                    rd_pend;
  logic [FTQ_IDX_BITS-1:0] rd_idx;
  logic [3:0]              rd_pos;
  logic [VA_WIDTH-1:0]     rd_pc;
  logic                    rd_self;
  ftq_redir_cause_e        rd_cause;
  logic                    rd_taken;
  // BP-121, the corrected history: a backend mispredict redirect of a
  // conditional was driven last cycle (h_chk), with its direction.
  // After the rollback the newest history bit must be that direction.
  logic                    rd_cond;
  logic                    h_chk;
  logic                    h_dir;
  int                      n_hist_ok;
  int                      n_hist_bad;
  // BP-123. The commit stage's maintenance: an operation retired and
  // waiting for its ack (mt_pend), presented and not yet taken
  // (mt_req), and the restart it holds. Delivery is not taken while
  // one is pending: the restart follows the ack (A1).
  logic                    mt_pend;
  logic                    mt_req;
  int                      mt_e;
  logic [FTQ_IDX_BITS-1:0] mt_idx;
  logic [3:0]              mt_pos;
  int                      n_maint;
  int                      n_maint_drain;   // L1I busy when it took one
  // Eager commit: commit the entry of the last retired instruction as
  // soon as nothing is in flight to the backend, and resolve a branch
  // that ended its block without waiting for the next instruction.
  // Uncached fetch needs it (IFU-22: an entry waits for every older one
  // to commit). Off for the BP-121 programs, so their timing is
  // unchanged.
  logic                    eager;
  logic                    cm_all;      // every retired entry committed
  int                      n_eager_res;
  int                      n_patch;
  int                      n_csrw;
  // DOC-001 (fe_demo_scenarios.md FD-20, FD-U2): decode's acceptance
  // pattern. 0, every program of tb_fe_top: the backend takes the
  // ibuf whenever it presents. N > 0: dec_ibuf_rdy is high only in a
  // cycle whose count is a multiple of N.
  int                      be_rdy_pat;
