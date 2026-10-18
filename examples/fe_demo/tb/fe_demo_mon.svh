// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fe_demo_mon.svh -- the scenario monitors of tb_fe_demo (DOC-001)
//
// Included inside module tb by tb_fe_demo.sv, after the shared models'
// state (fe_tb_be_state.svh) and before the backend. Every count here
// is read from RTL signals of fe_top and the walker, or from the
// testbench's own retirement, and is taken only while a scenario runs
// (meas: out of reset, the backend taking decode's output, and the
// expected stream not yet fully retired), except the FD-1 init
// figures, which start at the release of reset. The proof of each
// scenario (fe_demo_proofs.svh) is a condition on these counts.
//
// Also here: the backend's two hooks (models/fe_tb_backend.svh) and
// the record of each FTQ entry's final predicted slots that the
// retirement hook reads.
// ===================================================================

  // =================================================================
  // FD-1: the init walk. The first cycle after reset each predictor's
  // RAM-init ready is high, the first p0 request and the first p1
  // prediction the FTQ accepted. -1 until it happens.
  // =================================================================
  int c_tage_rdy;
  int c_it_rdy;
  int c_sc_rdy;
  int c_ras_rdy;
  int c_p0;
  int c_p1;
  // The first p2 (TAGE, ITTAGE) or p3 (SC) response of each queued
  // predictor at the cluster.
  int c_tage_p2;
  int c_it_p2;
  int c_sc_p3;
  // The first update each accepted (the valids after the cluster's
  // gates).
  int c_tage_u;
  int c_it_u;
  int c_sc_u;
  // A ready seen low after reset, so its rise is observed.
  logic lo_tage_rdy;
  logic lo_it_rdy;
  logic lo_sc_rdy;

  // =================================================================
  // FD-2: allocations and full decode bundles.
  // =================================================================
  int n_alloc;            // p1 predictions the FTQ accepted
  int run_alloc;          // the current run of consecutive ones
  int max_run_alloc;
  int n_dec8;             // cycles decode delivered SLOTS instructions
  int run_dec8;
  int max_run_dec8;

  // =================================================================
  // FD-3 to FD-5, FD-9: the BPU's groups and redirects.
  // =================================================================
  int n_two_p1;           // p1 predictions with both slots valid
  int n_two_p2;           // p2 groups with both slots valid
  int n_redir_p2;         // p2 redirects the FTQ accepted
  int n_redir_p3;         // p3 redirects the FTQ accepted
  int n_redir_p3_sc;      // ... whose slot SC decided
  int n_tage_alc;         // TAGE allocation writes
  int n_tage_prov;        // p2 predictions by a tagged provider
  int n_t0_uaon;          // p2 predictions by T0 through use_alt_on_na

  // =================================================================
  // FD-6 to FD-8: predictions checked at retirement (the hook below).
  // =================================================================
  int n_lp_exit_ok;       // loop exits the LP predicted not taken
  int n_ras_ret_ok;       // returns the RAS predicted, target right
  int n_itt_ok;           // indirects ITTAGE predicted, target right
  int n_ras_push;         // p2 RAS pushes and pops (any slot)
  int n_ras_pop;
  int n_rc_p2;            // p2 RETURN_CALL operations
  int max_rctr;           // the highest recursion count seen

  // =================================================================
  // FD-10 to FD-12: recovery and training.
  // =================================================================
  int n_be_misp;          // backend mispredict redirects
  int n_be_fix;           // ... whose first fetch was the corrected PC
  logic                be_wait;
  logic [VA_WIDTH-1:0] be_pc;
  int n_rollback;         // history rollbacks
  int n_ras_rest;         // RAS restores
  int n_upd_ubtb;
  int n_upd_lp;
  int n_upd_tage;
  int n_upd_itt;
  int n_upd_sc;
  int n_upd_ftb;
  int n_upd_ras;
  int n_ftb_bub;          // p0 requests held by an FTB update (H3)

  // =================================================================
  // FD-13 to FD-19: fetch and memory.
  // =================================================================
  int n_l1i_hit;
  int n_l1i_miss;
  int n_l1i_merge;
  int n_walk_s;           // single-stage walks (V=0)
  int n_walk_g;           // walks with a G-stage (V=1, hgatp Sv39x4)
  int n_g_eval;           // G-stage PTE evaluations
  int n_cas;              // walker compare-and-swaps
  int n_flt_page;         // faults delivered to decode with their cause
  int n_flt_guest;
  int n_flt_acc;
  int n_xq_cross;         // blocks translated twice (page crossing)
  int n_straddle;         // 32-bit instructions at block position 15
  int n_rvc;              // 16-bit instructions retired
  int n_uc_req_nc;        // uncached L1I requests to an NC page
  int n_uc_req_io;        // ... to an IO page (a PPN in io_ppn)
  int n_uc_alloc;         // uncached lines written into the L1I
  int n_inv_all;          // L1I invalidates taken: all, one line
  int n_inv_line;
  int n_inv_done;
  int n_mt_ack;
  int n_restart;          // first fetch after a maintenance ack is the
  logic                mt_wait;   // restart PC
  logic [VA_WIDTH-1:0] mt_pc;

  // =================================================================
  // FD-20, FD-21: flow control and commit.
  // =================================================================
  int n_ibuf_full;        // the IFU presents and the ibuf refuses
  int n_ftq_full;
  int n_dec_stall;        // decode holds a bundle, dec_ibuf_rdy low
  int n_p0_held;          // no p0 request
  int n_commit_adv;       // cycles the FTQ commit pointer moved
  int n_csp_chg;          // cycles the RAS commit stack changed
  logic [FTQ_PTR_BITS-1:0]        pv_commit;
  logic [RAS_COMMIT_PTR_BITS-1:0] pv_csp;
  logic [VA_WIDTH-1:0]            pv_ctop;

  // =================================================================
  // FD-22 to FD-24: the dual-slot scenarios (DOC-006). Each count needs
  // a second slot; on the one-slot model it stays 0.
  // =================================================================
  int n_sc_s1;            // p3 redirects: SC reversed slot 1, slot 0 a
                          // conditional TAGE predicted
  int n_sc_s0;            // p3 redirects: SC reversed slot 0
  int n_jmp_cut;          // p2 groups: two conditionals not taken and the
                          // block cut at the FTB jump's PC
  int n_jmp_next;         // ... the next p2 group, at that PC, with the
                          // jump in slot 0 and taken
  logic                cut_wait;
  logic [VA_WIDTH-1:0] cut_pc;
  int n_push_s1;          // p2 groups: a call in slot 1 behind a not-taken
                          // conditional in slot 0, presented to the RAS

  // The PPNs of the pages the program mapped with PBMT IO (FD-18). The
  // program writer's W.uc_ppn holds every uncached page, NC and IO
  // alike; this splits the uncached requests between the two.
  logic io_ppn [logic [PPN_WIDTH-1:0]];

  // Entries whose trap starts the two-stage regime (FD-14, FD-15):
  // the backend's trap hook applies it as the entry retires.
  logic to_h2 [int];

  task automatic mon_reset();
    c_tage_rdy    = -1;
    c_it_rdy      = -1;
    c_sc_rdy      = -1;
    c_ras_rdy     = -1;
    c_p0          = -1;
    c_p1          = -1;
    c_tage_p2     = -1;
    c_it_p2       = -1;
    c_sc_p3       = -1;
    c_tage_u      = -1;
    c_it_u        = -1;
    c_sc_u        = -1;
    lo_tage_rdy   = 1'b0;
    lo_it_rdy     = 1'b0;
    lo_sc_rdy     = 1'b0;
    n_alloc       = 0;
    run_alloc     = 0;
    max_run_alloc = 0;
    n_dec8        = 0;
    run_dec8      = 0;
    max_run_dec8  = 0;
    n_two_p1      = 0;
    n_two_p2      = 0;
    n_redir_p2    = 0;
    n_redir_p3    = 0;
    n_redir_p3_sc = 0;
    n_tage_alc    = 0;
    n_tage_prov   = 0;
    n_t0_uaon     = 0;
    n_lp_exit_ok  = 0;
    n_ras_ret_ok  = 0;
    n_itt_ok      = 0;
    n_ras_push    = 0;
    n_ras_pop     = 0;
    n_rc_p2       = 0;
    max_rctr      = 0;
    n_be_misp     = 0;
    n_be_fix      = 0;
    be_wait       = 1'b0;
    be_pc         = '0;
    n_rollback    = 0;
    n_ras_rest    = 0;
    n_upd_ubtb    = 0;
    n_upd_lp      = 0;
    n_upd_tage    = 0;
    n_upd_itt     = 0;
    n_upd_sc      = 0;
    n_upd_ftb     = 0;
    n_upd_ras     = 0;
    n_ftb_bub     = 0;
    n_l1i_hit     = 0;
    n_l1i_miss    = 0;
    n_l1i_merge   = 0;
    n_walk_s      = 0;
    n_walk_g      = 0;
    n_g_eval      = 0;
    n_cas         = 0;
    n_flt_page    = 0;
    n_flt_guest   = 0;
    n_flt_acc     = 0;
    n_xq_cross    = 0;
    n_straddle    = 0;
    n_rvc         = 0;
    n_uc_req_nc   = 0;
    n_uc_req_io   = 0;
    n_uc_alloc    = 0;
    n_inv_all     = 0;
    n_inv_line    = 0;
    n_inv_done    = 0;
    n_mt_ack      = 0;
    n_restart     = 0;
    mt_wait       = 1'b0;
    mt_pc         = '0;
    n_ibuf_full   = 0;
    n_ftq_full    = 0;
    n_dec_stall   = 0;
    n_p0_held     = 0;
    n_commit_adv  = 0;
    n_csp_chg     = 0;
    n_sc_s1       = 0;
    n_sc_s0       = 0;
    n_jmp_cut     = 0;
    n_jmp_next    = 0;
    cut_wait      = 1'b0;
    cut_pc        = '0;
    n_push_s1     = 0;
    to_h2.delete();
    io_ppn.delete();
  endtask

  // =================================================================
  // The final prediction of each FTQ entry: the slots of the last
  // group the FTQ accepted for it, p1 then p2 then p3. The retirement
  // hook compares a retired control transfer with the slot at its
  // position.
  // =================================================================
  bp_ftq_slot_t fin_slot [0:FTQ_DEPTH-1][0:NUM_PRED_SLOTS-1];

  // The last slot: slot 1 on the two-slot model (FD-22 to FD-24).
  localparam int S1 = NUM_PRED_SLOTS - 1;

  always @(posedge clk) begin : fin_log
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      if (rstn && dut.u_ftq.w_ok_pred_p1)
        fin_slot[dut.bpu_pred_idx_p1][s] <= dut.bpu_pred_slot_p1[s];
      if (rstn && dut.u_ftq.w_ok_slot_p2)
        fin_slot[dut.bpu_slot_idx_p2][s] <= dut.bpu_slot_p2[s];
      if (rstn && dut.u_ftq.w_ok_slot_p3)
        fin_slot[dut.bpu_slot_idx_p3][s] <= dut.bpu_slot_p3[s];
    end
  end

  // The slot of entry idx at position pos; slot_valid clear if none.
  function automatic bp_ftq_slot_t slot_at(
      input logic [FTQ_IDX_BITS-1:0] idx, input logic [3:0] pos);
    bp_ftq_slot_t r;
    r = '0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++)
      if (fin_slot[idx][s].slot_valid &&
          (fin_slot[idx][s].pos == FTB_BR_POS_BITS'(pos)))
        r = fin_slot[idx][s];
    return r;
  endfunction

  // =================================================================
  // The backend's hooks (models/fe_tb_backend.svh).
  // =================================================================
  // Retirement of expected entry e from packet s, before the
  // backend's checks.
  task automatic be_retire_hook(input ifu_pd_pkt_t s, input int e);
    bp_ftq_slot_t p;
    if (!meas) return;
    p = slot_at(s.ftq_idx, s.pos);
    // FD-6: a loop exit (not taken) the LP predicted not taken.
    if ((W.ex[e].btype == COND) && !W.ex[e].taken && p.slot_valid &&
        (p.pred_src == PRED_LOOP) && !p.taken)
      n_lp_exit_ok++;
    // FD-7: a return whose target the RAS supplied, and right.
    if (((W.ex[e].btype == RETURN) || (W.ex[e].btype == RETURN_CALL)) &&
        p.slot_valid && (p.pred_src == PRED_RAS) && p.taken &&
        (p.target == W.ex[e].target))
      n_ras_ret_ok++;
    // FD-8: an indirect jump or call whose target ITTAGE supplied.
    if (((W.ex[e].btype == INDIRECT_NONRET) ||
         (W.ex[e].btype == INDIRECT_CALL)) &&
        p.slot_valid && (p.pred_src == PRED_ITTAGE) && p.taken &&
        (p.target == W.ex[e].target))
      n_itt_ok++;
    // FD-15: a fault delivered with its expected cause and VA.
    if ((W.ex[e].fault != IFU_FAULT_NONE) &&
        (s.fault_cause == W.ex[e].fault) && (s.fault_va == W.ex[e].fva)) begin
      if (W.ex[e].fault == IFU_FAULT_PAGE)       n_flt_page++;
      if (W.ex[e].fault == IFU_FAULT_GUEST_PAGE) n_flt_guest++;
      if (W.ex[e].fault == IFU_FAULT_ACCESS)     n_flt_acc++;
    end
    // FD-17: a 32-bit instruction in the last halfword of its block
    // (it straddles the block's 32 bytes), delivered whole.
    if ((W.ex[e].fault == IFU_FAULT_NONE) && !s.is_rvc && (s.pos == 4'd15) &&
        (s.instr == W.ex[e].instr))
      n_straddle++;
    if ((W.ex[e].fault == IFU_FAULT_NONE) && s.is_rvc) n_rvc++;
  endtask

  // A trap or fault entry e retired. FD-14, FD-15: the trap of an
  // entry in to_h2 enters the two-stage regime, VS-mode (V=1) with
  // vsatp Sv39 and hgatp Sv39x4 over the tables h2_tables wrote; satp
  // is left as it was, unused under V=1.
  task automatic be_trap_hook(input int e);
    if (to_h2.exists(e)) begin
      csr_tb_pkg::set_v(1'b1);
      csr_tb_pkg::set_priv(CSR_PRV_S);
      csr_wr_vsatp(CSR_SATP_MODE_SV39, ASID_WIDTH'(1),
                   44'(W.vs_root >> 12));
      csr_wr_hgatp(CSR_HGATP_MODE_SV39X4, VMID_WIDTH'(3),
                   44'(W.hg_root >> 12));
    end
  endtask

  // =================================================================
  // The per-cycle monitors.
  // =================================================================
  always @(posedge clk) begin : mon_init
    if (rstn) begin
      if (!dut.bpu_tage_rdy)   lo_tage_rdy <= 1'b1;
      if (!dut.bpu_ittage_rdy) lo_it_rdy   <= 1'b1;
      if (!dut.bpu_sc_ready)   lo_sc_rdy   <= 1'b1;
      if (dut.bpu_tage_rdy && (c_tage_rdy < 0))   c_tage_rdy <= cyc;
      if (dut.bpu_ittage_rdy && (c_it_rdy < 0))   c_it_rdy   <= cyc;
      if (dut.bpu_sc_ready && (c_sc_rdy < 0))     c_sc_rdy   <= cyc;
      if (dut.u_bpu.u_ras.ras_rst_done && (c_ras_rdy < 0)) c_ras_rdy <= cyc;
      if (dut.ftq_pred_val_p0 && (c_p0 < 0))      c_p0       <= cyc;
      if (dut.u_ftq.w_ok_pred_p1 && (c_p1 < 0))   c_p1       <= cyc;
      if ((dut.u_bpu.w_tage_pred_rdy_p2 != '0) && (c_tage_p2 < 0))
        c_tage_p2 <= cyc;
      if ((dut.u_bpu.w_ittage_pred_rdy_p2 != '0) && (c_it_p2 < 0))
        c_it_p2 <= cyc;
      if ((dut.u_bpu.w_sc_pred_rdy_p3 != '0) && (c_sc_p3 < 0))
        c_sc_p3 <= cyc;
      if ((dut.u_bpu.w_tage_upd_val_u0 != '0) && (c_tage_u < 0))
        c_tage_u <= cyc;
      if ((dut.u_bpu.w_ittage_upd_val_u0 != '0) && (c_it_u < 0))
        c_it_u <= cyc;
      if ((dut.u_bpu.w_sc_upd_val_u0 != '0) && (c_sc_u < 0))
        c_sc_u <= cyc;
    end
  end

  always @(posedge clk) begin : mon_main
    int   nv;
    int   a;
    // Per-cycle sums of the counters taken per slot or per bank. Each
    // loop adds into one of these and the counter takes the sum once:
    // a nonblocking x <= x + 1 inside the loop reads the same x on
    // every iteration, so two slots in one cycle would count once
    // (DOC-002).
    int   n_prov;
    int   n_uaon;
    int   n_push;
    int   n_pop;
    int   n_rc;
    int   n_ubtb;
    int   n_hit;
    int   n_miss;
    int   n_ucal;
    logic r2;
    logic r3;
    logic r3sc;
    logic [RAS_RCTR_WIDTH-1:0] mx;
    if (meas) begin
      // FD-2.
      if (dut.u_ftq.w_ok_pred_p1) begin
        n_alloc   <= n_alloc + 1;
        run_alloc <= run_alloc + 1;
        if (run_alloc + 1 > max_run_alloc) max_run_alloc <= run_alloc + 1;
      end else begin
        run_alloc <= 0;
      end
      nv = 0;
      for (int i = 0; i < SLOTS; i++) if (pd_out[i].valid) nv++;
      if (dec_ibuf_rdy && (nv == SLOTS)) begin
        n_dec8   <= n_dec8 + 1;
        run_dec8 <= run_dec8 + 1;
        if (run_dec8 + 1 > max_run_dec8) max_run_dec8 <= run_dec8 + 1;
      end else begin
        run_dec8 <= 0;
      end
      // FD-3.
      if (dut.u_ftq.w_ok_pred_p1 && dut.bpu_pred_slot_p1[0].slot_valid &&
          dut.bpu_pred_slot_p1[NUM_PRED_SLOTS-1].slot_valid &&
          (NUM_PRED_SLOTS > 1))
        n_two_p1 <= n_two_p1 + 1;
      if (dut.u_ftq.w_ok_slot_p2 && dut.bpu_slot_p2[0].slot_valid &&
          dut.bpu_slot_p2[NUM_PRED_SLOTS-1].slot_valid &&
          (NUM_PRED_SLOTS > 1))
        n_two_p2 <= n_two_p2 + 1;
      // FD-4, FD-5.
      r2   = 1'b0;
      r3   = 1'b0;
      r3sc = 1'b0;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        r2 = r2 || dut.bpu_redir_p2[s].valid;
        r3 = r3 || dut.bpu_redir_p3[s].valid;
        r3sc = r3sc || (dut.bpu_redir_p3[s].valid && dut.bpu_slot_val_p3 &&
                        (dut.bpu_slot_idx_p3 == dut.bpu_redir_idx_p3) &&
                        (dut.bpu_slot_p3[s].pred_src == PRED_SC));
      end
      if (dut.u_ftq.w_ok_redir_p2 && r2) n_redir_p2 <= n_redir_p2 + 1;
      if (dut.u_ftq.w_ok_redir_p3 && r3) n_redir_p3 <= n_redir_p3 + 1;
      if (dut.u_ftq.w_ok_redir_p3 && r3sc)
        n_redir_p3_sc <= n_redir_p3_sc + 1;
      // FD-9. An allocation write applied (the arbiter grants the
      // cycle to updates, trx_type); a p2 prediction whose provider is
      // a tagged table; one whose primary is tagged but whose
      // prediction is T0's, chosen by use_alt_on_na.
      a      = 0;
      n_prov = 0;
      n_uaon = 0;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        tage_pred_meta_t m;
        if (dut.u_bpu.u_tage.u_tage_cntrl.trx_type &&
            dut.u_bpu.u_tage.u_tage_cntrl.tage_upd_val_u0[s] &&
            dut.u_bpu.u_tage.u_tage_cntrl.u_alc_wr[s])
          a++;
        m = dut.u_bpu.u_tage.u_tage_cntrl.tage_pred_meta_p2[s];
        if (dut.u_bpu.u_tage.u_tage_cntrl.tage_pred_rdy_p2[s]) begin
          if (m.tage_using_primary && (m.tage_prm_comp != '0))
            n_prov++;
          if (!m.tage_using_primary && (m.tage_prm_comp != '0) &&
              (m.tage_alt_comp == '0))
            n_uaon++;
        end
      end
      n_tage_alc  <= n_tage_alc + a;
      n_tage_prov <= n_tage_prov + n_prov;
      n_t0_uaon   <= n_t0_uaon + n_uaon;
      // FD-7. The p2 RAS operations, and the highest recursion count
      // in the speculative stack.
      n_push = 0;
      n_pop  = 0;
      n_rc   = 0;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        if (dut.u_bpu.w_ras_pred_val_p2[s]) begin
          if (dut.u_bpu.w_br_type_p2[s] inside {DIRECT_CALL, INDIRECT_CALL,
                                                RETURN_CALL})
            n_push++;
          if (dut.u_bpu.w_br_type_p2[s] inside {RETURN, RETURN_CALL})
            n_pop++;
          if (dut.u_bpu.w_br_type_p2[s] == RETURN_CALL)
            n_rc++;
        end
      end
      n_ras_push <= n_ras_push + n_push;
      n_ras_pop  <= n_ras_pop + n_pop;
      n_rc_p2    <= n_rc_p2 + n_rc;
      mx = '0;
      for (int i = 0; i < RAS_SPEC_ENTRIES; i++)
        if (dut.u_bpu.u_ras.spec_rctr[i] > mx)
          mx = dut.u_bpu.u_ras.spec_rctr[i];
      if (int'(mx) > max_rctr) max_rctr <= int'(mx);
      // FD-11. A backend mispredict redirect, and the next fetch the
      // FTQ presents after it.
      if (bkend_ftq_redir_val && (bkend_ftq_redir_cause == RC_MISPREDICT))
      begin
        n_be_misp <= n_be_misp + 1;
        be_wait   <= 1'b1;
        be_pc     <= bkend_ftq_redir_pc;
      end else if (be_wait && dut.ftq_ifu_req_val && dut.ftq_ifu_req_rdy &&
                   !dut.ftq_ifu_flush_val) begin
        be_wait <= 1'b0;
        if (dut.ftq_ifu_start_pc == be_pc) n_be_fix <= n_be_fix + 1;
      end
      if (dut.ftq_rollback_val) n_rollback <= n_rollback + 1;
      if (dut.ras_restore_val)  n_ras_rest <= n_ras_rest + 1;
      // FD-12. Updates each predictor accepted (the valids after the
      // cluster's gates), and the FTB update's p0 hold (ftq_npc H3).
      n_ubtb = 0;
      for (int s = 0; s < NUM_PRED_SLOTS; s++)
        if (dut.u_bpu.w_ubtb_upd_u0[s].valid) n_ubtb++;
      n_upd_ubtb <= n_upd_ubtb + n_ubtb;
      if (dut.u_bpu.w_lp_upd_val_p0 != '0)     n_upd_lp   <= n_upd_lp + 1;
      if (dut.u_bpu.w_tage_upd_val_u0 != '0)   n_upd_tage <= n_upd_tage + 1;
      if (dut.u_bpu.w_ittage_upd_val_u0 != '0) n_upd_itt  <= n_upd_itt + 1;
      if (dut.u_bpu.w_sc_upd_val_u0 != '0)     n_upd_sc   <= n_upd_sc + 1;
      if (dut.u_bpu.w_ftb_upd_val_u0)          n_upd_ftb  <= n_upd_ftb + 1;
      if (dut.u_bpu.w_ras_commit_val)          n_upd_ras  <= n_upd_ras + 1;
      if (dut.u_ftq.u_npc.h3_ftb_upd)          n_ftb_bub  <= n_ftb_bub + 1;
      // FD-13. A hit answered by a bank, a miss reported by a bank, a
      // request merged onto a register already fetching its line.
      n_hit  = 0;
      n_miss = 0;
      for (int b = 0; b < 2; b++) begin
        if (dut.u_l1i.b_rsp_valid[b]) n_hit++;
        if (dut.u_l1i.b_mis_valid[b]) n_miss++;
      end
      n_l1i_hit  <= n_l1i_hit + n_hit;
      n_l1i_miss <= n_l1i_miss + n_miss;
      if (dut.u_l1i.u_mshr.accept && dut.u_l1i.u_mshr.mrg_hit)
        n_l1i_merge <= n_l1i_merge + 1;
      // FD-14. Walks by kind, the G-stage evaluations, and CAS.
      if (itlb_l2t_req_val && itlb_l2t_req_rdy) begin
        if (itlb_l2t_v) n_walk_g <= n_walk_g + 1;
        else            n_walk_s <= n_walk_s + 1;
      end
      if (u_ptw.r_st == u_ptw.S_G_EVAL) n_g_eval <= n_g_eval + 1;
      if (ptw_mem_req_val && ptw_mem_req_rdy && ptw_mem_req_op)
        n_cas <= n_cas + 1;
      // FD-16. A translation-queue entry popped with two translations.
      if (dut.u_ifu.u_xlate.xq_val && dut.u_ifu.u_xlate.xq_pop &&
          dut.u_ifu.u_xlate.xq_cross &&
          (dut.u_ifu.u_xlate.xq_ppn0 != dut.u_ifu.u_xlate.xq_ppn1))
        n_xq_cross <= n_xq_cross + 1;
      // FD-18. Uncached requests the L1I took, by the memory type of the
      // page; uncached lines filled.
      if (dut.ifu_l1i_req_val && dut.ifu_l1i_req_rdy &&
          dut.ifu_l1i_req_uncached) begin
        if (io_ppn.exists(dut.ifu_l1i_req_paddr[PA_WIDTH-1:12]))
          n_uc_req_io <= n_uc_req_io + 1;
        else
          n_uc_req_nc <= n_uc_req_nc + 1;
      end
      n_ucal = 0;
      for (int b = 0; b < 2; b++)
        if (dut.u_l1i.u_mshr.b_fil_valid[b] &&
            W.uc_ppn.exists(dut.u_l1i.u_mshr.b_fil_line[b][PA_WIDTH-1:12]))
          n_ucal++;
      n_uc_alloc <= n_uc_alloc + n_ucal;
      // FD-19. The L1I invalidates, their done, the IFU's ack, and the
      // first fetch after the ack.
      if (dut.ifu_l1i_inv_val && dut.ifu_l1i_inv_rdy) begin
        if (dut.ifu_l1i_inv_all) n_inv_all  <= n_inv_all + 1;
        else                     n_inv_line <= n_inv_line + 1;
      end
      if (dut.l1i_ifu_inv_done) n_inv_done <= n_inv_done + 1;
      if (ifu_cmt_maint_ack) begin
        n_mt_ack <= n_mt_ack + 1;
        mt_wait  <= 1'b1;
        mt_pc    <= W.ex[mt_e].pc + VA_WIDTH'(4);
      end else if (mt_wait && dut.ftq_ifu_req_val && dut.ftq_ifu_req_rdy &&
                   !dut.ftq_ifu_flush_val) begin
        mt_wait <= 1'b0;
        if (dut.ftq_ifu_start_pc == mt_pc) n_restart <= n_restart + 1;
      end
      // FD-20. Where each stall is.
      if (dut.ifu_ibuf_val && !dut.ibuf_ifu_rdy)
        n_ibuf_full <= n_ibuf_full + 1;
      if (ftq_full) n_ftq_full <= n_ftq_full + 1;
      if (pd_out[0].valid && !dec_ibuf_rdy) n_dec_stall <= n_dec_stall + 1;
      if (!dut.ftq_pred_val_p0) n_p0_held <= n_p0_held + 1;
      // FD-21. The FTQ commit pointer and the RAS commit stack.
      if (dut.u_ftq.w_commit_ptr != pv_commit)
        n_commit_adv <= n_commit_adv + 1;
      if ((dut.u_bpu.u_ras.csp != pv_csp) ||
          (dut.u_bpu.u_ras.commit_top_addr != pv_ctop))
        n_csp_chg <= n_csp_chg + 1;
      // FD-22 to FD-24. S1 is the last slot, slot 1 on the two-slot
      // model; every condition also needs NUM_PRED_SLOTS > 1, so on the
      // one-slot model, where S1 is slot 0, nothing is counted.
      if ((NUM_PRED_SLOTS > 1) && dut.u_ftq.w_ok_redir_p3 &&
          dut.bpu_slot_val_p3 &&
          (dut.bpu_slot_idx_p3 == dut.bpu_redir_idx_p3)) begin
        // FD-22. SC reversed the slot (pred_src PRED_SC, p3_slot_comb)
        // and the slot's own p3 redirect is raised.
        if (dut.bpu_redir_p3[S1].valid && dut.bpu_slot_p3[S1].slot_valid &&
            (dut.bpu_slot_p3[S1].br_type == COND) &&
            (dut.bpu_slot_p3[S1].pred_src == PRED_SC) &&
            dut.bpu_slot_p3[0].slot_valid &&
            (dut.bpu_slot_p3[0].br_type == COND) &&
            (dut.bpu_slot_p3[0].pred_src == PRED_TAGE))
          n_sc_s1 <= n_sc_s1 + 1;
        if (dut.bpu_redir_p3[0].valid && dut.bpu_slot_p3[0].slot_valid &&
            (dut.bpu_slot_p3[0].pred_src == PRED_SC))
          n_sc_s0 <= n_sc_s0 + 1;
      end
      // FD-23. The cut (w_jmp_cut_p2, bp_cluster p2_class_comb): both
      // slots conditionals, neither taken, the block's end the jump PC.
      // The next accepted p2 group whose block starts at that PC
      // should carry the jump in slot 0, at position 0, taken.
      if ((NUM_PRED_SLOTS > 1) && dut.u_ftq.w_ok_slot_p2 &&
          dut.bpu_slot_val_p2) begin
        if (dut.u_bpu.w_jmp_cut_p2 &&
            dut.bpu_slot_p2[0].slot_valid && !dut.bpu_slot_p2[0].taken &&
            (dut.bpu_slot_p2[0].br_type == COND) &&
            dut.bpu_slot_p2[S1].slot_valid && !dut.bpu_slot_p2[S1].taken &&
            (dut.bpu_slot_p2[S1].br_type == COND)) begin
          n_jmp_cut <= n_jmp_cut + 1;
          cut_wait  <= 1'b1;
          cut_pc    <= dut.bpu_blk_pft_p2;
        end else if (cut_wait && (dut.u_bpu.r_pc_p2 == cut_pc)) begin
          cut_wait <= 1'b0;
          if (dut.bpu_slot_p2[0].slot_valid && dut.bpu_slot_p2[0].taken &&
              (dut.bpu_slot_p2[0].br_type == DIRECT_UNC) &&
              (dut.bpu_slot_p2[0].pos == '0))
            n_jmp_next <= n_jmp_next + 1;
        end
      end
      // FD-24. The p2 RAS presentation of slot 1 (w_ras_pred_val_p2,
      // bp_cluster p2_class_comb: reachable because slot 0 is not
      // taken), a call, in a p2 group the FTQ accepted.
      if ((NUM_PRED_SLOTS > 1) && dut.u_ftq.w_ok_slot_p2 &&
          dut.bpu_slot_val_p2 && dut.u_bpu.w_ras_pred_val_p2[S1] &&
          (dut.u_bpu.w_br_type_p2[S1] inside {DIRECT_CALL, INDIRECT_CALL}) &&
          dut.bpu_slot_p2[0].slot_valid && !dut.bpu_slot_p2[0].taken &&
          (dut.bpu_slot_p2[0].br_type == COND))
        n_push_s1 <= n_push_s1 + 1;
    end
    pv_commit <= dut.u_ftq.w_commit_ptr;
    pv_csp    <= dut.u_bpu.u_ras.csp;
    pv_ctop   <= dut.u_bpu.u_ras.commit_top_addr;
  end
