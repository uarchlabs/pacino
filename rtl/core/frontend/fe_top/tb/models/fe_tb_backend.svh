// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fe_tb_backend.svh -- the in-order backend
//
// A SHARED FRONT-END TESTBENCH MODEL (DOC-001, fe_demo_tb_decisions.md
// FDT-4). Not a compilation unit: it is included inside the body of
// module tb, after the package imports, by tb_fe_top
// (rtl/core/frontend/fe_top/tb) and tb_fe_demo (examples/fe_demo/tb),
// in the order those files give. The text was moved here from
// tb_fe_top.sv unchanged except where this header says otherwise.
//
// Holds: the backend process (take decode's output, compare it in
// order against the expected stream, resolve, redirect, commit by
// watermark, the FENCE.I / cbo.inval handshake, the RAS commit and
// history checks, the ITLB-invalidate trigger); models_reset, the
// reset of every model's state; release_reset.
//
// CHANGED FROM tb_fe_top.sv:
// - the WBR line of tb_fe_top's +TRACE is now its be_retire_hook
// - be_trap_hook is called after a trap's privilege change
// - dec_ibuf_rdy also follows be_rdy_pat (FD-20); 0 leaves it as it
//   was
// THE INCLUDING TESTBENCH DEFINES two tasks:
//   be_retire_hook(input ifu_pd_pkt_t s, input int e)
//       called for every expected instruction as it retires, before
//       any of its checks, with its ibuf packet and stream entry
//   be_trap_hook(input int e)
//       called when a trap or fault entry e retires, after the
//       privilege change its entry names
// Requires every other fe_tb_*.svh.
// ===================================================================

  // The taken target of a conditional, from its (expanded) B-type
  // encoding: pc + the sign-extended immediate.
  function automatic logic [VA_WIDTH-1:0] br_target(
      input logic [VA_WIDTH-1:0] pc, input logic [31:0] w);
    logic [12:0] imm;
    imm = {w[31], w[7], w[30:25], w[11:8], 1'b0};
    return pc + {{(VA_WIDTH-13){imm[12]}}, imm};
  endfunction

  // A resolution carries the RESOLVED TAKEN TARGET of a conditional
  // whatever its direction (ftb_decisions.md 5.5, "conditional target:
  // rewrite if the resolved taken target differs"). BP-121: before, a
  // not-taken conditional resolved with its fall-through as target, so
  // the FTB stored the fall-through and the next taken instance of the
  // branch was fetched to it (hist: the alternating branch).
  task automatic resolve(input int e, input logic [FTQ_IDX_BITS-1:0] idx,
                         input logic [3:0] pos, input logic mis);
    rq[rq_tl % 256].ftq_idx    = idx;
    rq[rq_tl % 256].pos        = pos;
    rq[rq_tl % 256].taken      = W.ex[e].taken;
    rq[rq_tl % 256].target     = (W.ex[e].btype == COND)
                               ? br_target(W.ex[e].pc, W.ex[e].instr)
                               : W.ex[e].target;
    rq[rq_tl % 256].br_type    = W.ex[e].btype;
    rq[rq_tl % 256].mispredict = mis;
`ifndef BASE_RTL
    rq[rq_tl % 256].is_rvc     = W.ex[e].rvc;
`endif
    rq_tl++;
  endtask

  // The entry pointer of a retired instruction (FTQ_PTR_BITS, the
  // commit watermark's width). A redirect fixes the next one; past
  // that, a new index advances the pointer by its distance.
  task automatic track_entry(input logic [FTQ_IDX_BITS-1:0] idx);
    logic [FTQ_PTR_BITS-1:0] np;
    if (after_redir) begin
      np = redir_next;
      if (np[FTQ_IDX_BITS-1:0] != idx) begin
        n_err++;
        $display("ERROR: [%s] first index after a redirect %0d, exp %0d",
                 tname, idx, np[FTQ_IDX_BITS-1:0]);
      end
      cur_ptr     = np;
      cur_val     = 1'b1;
      after_redir = 1'b0;
      wm          = np - FTQ_PTR_BITS'(1);
      wm_val      = (np != '0) || wm_val;
    end else if (!cur_val) begin
      cur_ptr = {1'b0, idx};
      cur_val = 1'b1;
    end else if (idx != cur_ptr[FTQ_IDX_BITS-1:0]) begin
      np      = cur_ptr + FTQ_PTR_BITS'(FTQ_IDX_BITS'(idx -
                cur_ptr[FTQ_IDX_BITS-1:0]));
      wm      = np - FTQ_PTR_BITS'(1);
      wm_val  = 1'b1;
      cur_ptr = np;
    end
  endtask

  task automatic redirect(input logic [FTQ_IDX_BITS-1:0] idx,
                          input logic [3:0] pos,
                          input logic [VA_WIDTH-1:0] pc,
                          input logic self, input ftq_redir_cause_e c);
    logic [FTQ_PTR_BITS-1:0] kp;
    rd_pend  = 1'b1;
    rd_idx   = idx;
    rd_pos   = pos;
    rd_pc    = pc;
    rd_self  = self;
    rd_cause = c;
    rd_taken = 1'b0;
    rd_cond  = 1'b0;
    // The pointer of entry idx: the current entry's, or one behind it
    // for a mispredict named by the previous entry's branch.
    kp = cur_ptr - FTQ_PTR_BITS'(FTQ_IDX_BITS'(cur_ptr[FTQ_IDX_BITS-1:0]
                                                - idx));
    redir_next  = self ? kp : kp + FTQ_PTR_BITS'(1);
    after_redir = 1'b1;
    // Every entry before the restart point has retired.
    wm     = redir_next - FTQ_PTR_BITS'(1);
    wm_val = 1'b1;
  endtask

  initial begin : backend
    ifu_pd_pkt_t s;
    decode_pkt_t d;
    logic        stop;
    logic        prsnt;
    bkend_ftq_redir_val   = 1'b0;
    bkend_ftq_redir_idx   = '0;
    bkend_ftq_redir_pos   = '0;
    bkend_ftq_redir_pc    = '0;
    bkend_ftq_redir_self  = 1'b0;
    bkend_ftq_redir_cause = RC_MISPREDICT;
    bkend_ftq_redir_taken = 1'b0;
    bkend_ftq_commit_val  = 1'b0;
    bkend_ftq_commit_idx  = '0;
    bkend_ftq_rsv_val     = '0;
    for (int p = 0; p < NUM_RESOLVE_PORTS; p++)   // BP-128: [0], [1]
      bkend_ftq_rsv[p]    = '0;
    dec_ibuf_rdy          = 1'b0;
    cmt_ifu_maint_val     = 1'b0;
    cmt_ifu_maint_op      = 1'b0;
    cmt_ifu_maint_paddr   = '0;
    forever begin
      @(posedge clk);
      // ---- sample at the edge -----------------------------------
      if (rstn && bkend_ftq_rsv_val[0] && ftq_bkend_rsv_rdy[0]) rq_hd++;
      stop  = 1'b0;
      prsnt = rstn && run_be && dec_ibuf_rdy && !bkend_ftq_redir_val &&
              !mt_pend;
      // BP-123: the maintenance handshake, sampled at the edge.
      if (rstn && mt_req && cmt_ifu_maint_val && cmt_ifu_maint_rdy)
        mt_req = 1'b0;
      // An invalidate the L1I took with fills in flight: the drain of
      // IF-31 had something to wait for.
      if (rstn && dut.ifu_l1i_inv_val && dut.ifu_l1i_inv_rdy &&
          dut.u_l1i.mt_busy_any)
        n_maint_drain++;
      if (rstn && mt_pend && !mt_req && ifu_cmt_maint_ack) begin
        mt_pend = 1'b0;
        stop    = 1'b1;
        redirect(mt_idx, mt_pos, W.ex[mt_e].pc + VA_WIDTH'(4), 1'b1,
                 RC_REPLAY);
      end
      // BP-123, eager mode. With nothing presented this cycle, a branch
      // that ended its block is resolved against the block the FTQ
      // fetched after it (its predicted successor), once that block was
      // fetched after the branch's own writeback, as a backend resolves
      // a branch against the FTQ's predicted target. Then the entry of
      // the last retired instruction commits.
      if (prsnt && eager && !pd_out[0].valid && cfi_pend && (ep < W.ne) &&
          fseen[FTQ_IDX_BITS'(cfi_idx + 1)] && wbseen[cfi_idx]) begin
        n_eager_res++;
        if (fstart[FTQ_IDX_BITS'(cfi_idx + 1)] == W.ex[ep].pc) begin
          resolve(cfi_e, cfi_idx, cfi_pos, 1'b0);
          cfi_pend = 1'b0;
        end else begin
          n_mispred++;
          if (cfi_e >= warm_e) begin
            n_mis_warm++;
            n_mis_type[int'(W.ex[cfi_e].btype)]++;
          end
          resolve(cfi_e, cfi_idx, cfi_pos, 1'b1);
          cfi_pend = 1'b0;
          redirect(cfi_idx, cfi_pos, W.ex[ep].pc, 1'b0, RC_MISPREDICT);
          rd_taken = W.ex[cfi_e].taken;
          rd_cond  = (W.ex[cfi_e].btype == COND);
          stop     = 1'b1;
        end
      end
      if (prsnt && eager && !pd_out[0].valid && !cfi_pend && cur_val &&
          !after_redir) begin
        wm     = cur_ptr;
        wm_val = 1'b1;
      end
      if (prsnt) begin
        for (int i = 0; i < SLOTS; i++) begin
          s = pd_out[i];
          d = decode_bundle[i];
          if (!s.valid || stop) continue;
          if (ep >= W.ne) continue;                 // past the end
          if (s.start_pc != W.ex[ep].pc) begin
            stop = 1'b1;
            // A direct jump or call never has a wrong path after it:
            // predecode truncates the bundle at a JAL (M1, M3, IB-2),
            // so what follows one is its target. Only a conditional's
            // direction and an indirect's target can be wrong here.
            if (cfi_pend && ((W.ex[cfi_e].btype == DIRECT_UNC) ||
                             (W.ex[cfi_e].btype == DIRECT_CALL))) begin
              n_err++;
              $display("ERROR: [%s] pc %011h after a JAL at %011h",
                       tname, s.start_pc, W.ex[cfi_e].pc);
            end else if (cfi_pend) begin
              if (trace)
                $display("%0d MISP pc %0h act %0d got %0h exp %0h e %0d", cyc,
                         W.ex[cfi_e].pc[15:0], W.ex[cfi_e].taken,
                         s.start_pc[15:0], W.ex[ep].pc[15:0], cfi_e);
              n_mispred++;
              if ((W.ex[cfi_e].btype == RETURN) ||
                  (W.ex[cfi_e].btype == RETURN_CALL))
                n_mis_ras++;
              if (W.ex[cfi_e].pc == watch_pc) n_mis_watch++;
              if (cfi_e >= warm_e) begin
                n_mis_warm++;
                n_mis_type[int'(W.ex[cfi_e].btype)]++;
                if (mis_pc.exists(W.ex[cfi_e].pc))
                  mis_pc[W.ex[cfi_e].pc]++;
                else
                  mis_pc[W.ex[cfi_e].pc] = 1;
                mis_typ[W.ex[cfi_e].pc] = W.ex[cfi_e].btype;
              end
              resolve(cfi_e, cfi_idx, cfi_pos, 1'b1);
              cfi_pend = 1'b0;
              redirect(cfi_idx, cfi_pos, W.ex[ep].pc, 1'b0, RC_MISPREDICT);
              // The resolved direction rides with the redirect (BP-121).
              rd_taken = W.ex[cfi_e].taken;
              rd_cond  = (W.ex[cfi_e].btype == COND);
            end else begin
              n_err++;
              $display("%s", $sformatf(
                {"ERROR: [%s] stream: got pc %011h exp %011h ",
                 "(entry %0d), not after a control transfer"},
                tname, s.start_pc, W.ex[ep].pc, ep));
            end
            continue;
          end
          // The expected instruction.
          if (trace) $display("%0d RETIRE %0h idx %0d pos %0d e %0d", cyc,
                              s.start_pc[15:0], s.ftq_idx, s.pos, ep);
          // The including testbench's retirement hook (tb_fe_top: the
          // WBR line of its +TRACE).
          be_retire_hook(s, ep);
          n_retired++;
          if (cfi_pend) begin
            resolve(cfi_e, cfi_idx, cfi_pos, 1'b0);
            cfi_pend = 1'b0;
          end
          track_entry(s.ftq_idx);
          // A faulting slot has no encoding; no document says what
          // its is_rvc holds (reported, BP-118), so it is not checked.
          if ((W.ex[ep].fault == IFU_FAULT_NONE) &&
              (s.is_rvc != W.ex[ep].rvc)) begin
            n_err++;
            $display("ERROR: [%s] pc %011h is_rvc %0d", tname, s.start_pc,
                     s.is_rvc);
          end
          if (d.is_illegal) begin
            n_err++;
            $display("ERROR: [%s] pc %011h decode raised illegal", tname,
                     s.start_pc);
          end
          // BP-123: decode's operation, where the program names one.
          if ((W.ex[ep].aluop >= 0) && (int'(d.alu_op) != W.ex[ep].aluop)) begin
            n_err++;
            $display("ERROR: [%s] pc %011h instr %08h alu_op %0d exp %0d",
                     tname, s.start_pc, s.instr, d.alu_op, W.ex[ep].aluop);
          end
          // BP-123: predecode classes a non-control-transfer as none
          // (prefetch.i is an ORI, Zicbop).
          if ((W.ex[ep].fault == IFU_FAULT_NONE) &&
              (W.ex[ep].btype == NO_BRANCH) && !W.ex[ep].trap &&
              (s.br_type != 2'b00)) begin
            n_err++;
            $display("ERROR: [%s] pc %011h instr %08h predecode class %0d",
                     tname, s.start_pc, s.instr, s.br_type);
          end
          if (fstart[s.ftq_idx] + VA_WIDTH'(2 * int'(s.pos)) != s.start_pc)
          begin
            n_err++;
            $display("%s", $sformatf(
              {"ERROR: [%s] pc %011h ftq_idx %0d pos %0d does not ",
               "name its block (start %011h)"}, tname, s.start_pc,
              s.ftq_idx, s.pos, fstart[s.ftq_idx]));
          end
          if (W.ex[ep].fault != IFU_FAULT_NONE) begin
            if ((s.fault_cause != W.ex[ep].fault) ||
                (s.fault_va != W.ex[ep].fva) ||
                ((W.ex[ep].fault == IFU_FAULT_GUEST_PAGE) &&
                 ((s.fault_gpa != W.ex[ep].fgpa) ||
                  (s.fault_gpa_imp != W.ex[ep].fimp)))) begin
              n_err++;
              $display("%s", $sformatf(
                {"ERROR: [%s] pc %011h fault %0d va %011h gpa %011h ",
                 "kind %0d; expected %0d %011h %011h %0d"}, tname,
                s.start_pc, s.fault_cause, s.fault_va, s.fault_gpa,
                s.fault_gpa_imp, W.ex[ep].fault, W.ex[ep].fva,
                W.ex[ep].fgpa, W.ex[ep].fimp));
            end else begin
              n_fault_ok++;
            end
            n_trap++;
            stop = 1'b1;
            // BP-124: a trap taken to S (pt_upriv).
            if (W.ex[ep].npriv >= 0) csr_priv(2'(W.ex[ep].npriv));
            be_trap_hook(ep);
            redirect(s.ftq_idx, s.pos, W.ex[ep].target, 1'b1, RC_TRAP);
            ep++;
            continue;
          end
          if ((s.fault_cause != IFU_FAULT_NONE) ||
              (s.instr != W.ex[ep].instr)) begin
            n_err++;
            $display("ERROR: [%s] pc %011h instr %08h exp %08h fault %0d",
                     tname, s.start_pc, s.instr, W.ex[ep].instr,
                     s.fault_cause);
          end
          if (W.ex[ep].trap) begin
            n_trap++;
            stop = 1'b1;
            // BP-124: an ecall to S or an sret to U (pt_upriv).
            if (W.ex[ep].npriv >= 0) csr_priv(2'(W.ex[ep].npriv));
            be_trap_hook(ep);
            redirect(s.ftq_idx, s.pos, W.ex[ep].target, 1'b1, RC_TRAP);
            ep++;
            continue;
          end
          // BP-123. A store's memory effect lands as it retires.
          for (int k = 0; k < W.ex[ep].pn; k++) begin
            W.mem[W.pat_a[W.ex[ep].p0 + k]] =
              W.pat_h[W.ex[ep].p0 + k][7:0];
            W.mem[W.pat_a[W.ex[ep].p0 + k] + PA_WIDTH'(1)] =
              W.pat_h[W.ex[ep].p0 + k][15:8];
            n_patch++;
          end
          // BP-123. FENCE.I or cbo.inval: nothing after it is taken
          // until the IFU acknowledges, then fetch restarts after it
          // (l1i_ifu_interfaces.md 11, A1).
          if (W.ex[ep].maint == 3) begin
            // A CSR write: the new envcfg bits, then the restart.
            csr_envcfg(W.act_madue[W.ex[ep].p0], W.act_hadue[W.ex[ep].p0],
                       W.act_mpbmte[W.ex[ep].p0],
                       W.act_hpbmte[W.ex[ep].p0]);
            n_csrw++;
            stop = 1'b1;
            redirect(s.ftq_idx, s.pos, W.ex[ep].pc + VA_WIDTH'(4), 1'b1,
                     RC_REPLAY);
            ep++;
            continue;
          end
          if (W.ex[ep].maint != 0) begin
            stop    = 1'b1;
            mt_pend = 1'b1;
            mt_req  = 1'b1;
            mt_e    = ep;
            mt_idx  = s.ftq_idx;
            mt_pos  = s.pos;
            n_maint++;
            ep++;
            continue;
          end
          if (W.ex[ep].btype != NO_BRANCH) begin
            cfi_pend = 1'b1;
            cfi_e    = ep;
            cfi_idx  = s.ftq_idx;
            cfi_pos  = s.pos;
          end
          // The architectural RAS operation of this instruction, if any
          // (ras_decisions.md 2): a call pushes its link, the address
          // after it; a return pops; a return-call pops then pushes.
          if ((W.ex[ep].btype == DIRECT_CALL)   ||
              (W.ex[ep].btype == INDIRECT_CALL) ||
              (W.ex[ep].btype == RETURN)        ||
              (W.ex[ep].btype == RETURN_CALL)) begin
            rasev_t ev;
            ev.t  = W.ex[ep].btype;
            ev.pc = W.ex[ep].pc;
            ev.ra = W.ex[ep].pc + (W.ex[ep].rvc ? VA_WIDTH'(2) : VA_WIDTH'(4));
            ras_exp.push_back(ev);
          end
          ep++;
        end
      end
      #1;
      // ---- the RAS commit check (BP-121) ------------------------
      while ((ras_got.size() > 0) && (ras_exp.size() > 0)) begin
        rasev_t g;
        rasev_t x;
        g = ras_got.pop_front();
        x = ras_exp.pop_front();
        if ((g.t != x.t) ||
            ((x.t != RETURN) && (g.ra != x.ra))) begin
          n_ras_bad++;
          if (n_ras_bad <= 4) $display("%s", $sformatf(
            {"ERROR: [%s] RAS commit %0d ret %011h, expected %0d ret ",
             "%011h (the instruction at %011h)"}, tname, g.t, g.ra, x.t,
            x.ra, x.pc));
        end else begin
          n_ras_ok++;
        end
      end
      if (ras_got.size() > 0) begin
        rasev_t g;
        g = ras_got.pop_front();
        n_ras_bad++;
        if (n_ras_bad <= 4)
          $display("ERROR: [%s] RAS commit %0d ret %011h with none retired",
                   tname, g.t, g.ra);
      end
      meas = rstn && run_be && (ep < W.ne);
      // ---- the history check (BP-121) --------------------------
      if (h_chk) begin
        if (dut.bpu_ghr_buf[dut.bpu_ghist_ptr - GHIST_PTR_BITS'(1)] == h_dir)
          n_hist_ok++;
        else
          n_hist_bad++;
      end
      h_chk = rd_pend && rd_cond && (rd_cause == RC_MISPREDICT) && !rd_self;
      h_dir = rd_taken;
      // ---- BP-123: the invalidate-during-a-walk trigger ----------
      bkend_itlb_inv_val = 1'b0;
      if (rstn && inv_watch && (inv_at < 0) && itlb_l2t_req_val &&
          itlb_l2t_req_rdy && (itlb_l2t_vpn == inv_vpn))
        inv_at = cyc + 4;
      if (rstn && (inv_at >= 0) && (cyc >= inv_at)) begin
        bkend_itlb_inv_val    = 1'b1;
        bkend_itlb_inv_op     = 2'd0;              // VMA, all
        bkend_itlb_inv_rs1_nz = 1'b0;
        bkend_itlb_inv_rs2_nz = 1'b0;
        inv_at    = -1;
        inv_watch = 1'b0;
        n_inv_fired++;
        if (u_ptw.r_st != u_ptw.S_IDLE) n_inv_busy++;
      end
      // ---- drive for the next cycle -----------------------------
      bkend_ftq_redir_val = rd_pend;
      if (rd_pend) begin
        bkend_ftq_redir_idx   = rd_idx;
        bkend_ftq_redir_pos   = rd_pos;
        bkend_ftq_redir_pc    = rd_pc;
        bkend_ftq_redir_self  = rd_self;
        bkend_ftq_redir_cause = rd_cause;
        bkend_ftq_redir_taken = rd_taken;
      end
      rd_pend = 1'b0;
      // BP-121: an entry commits only after the resolutions of its
      // branches were accepted (a branch resolves before it retires).
      // The commit walk reads the entry's resolved slots (ftq_resolve
      // writes them), so the watermark waits while the resolution
      // queue holds anything.
      if (rq_hd == rq_tl) begin
        bkend_ftq_commit_val = wm_val;
        bkend_ftq_commit_idx = wm;
      end
      bkend_ftq_rsv_val[0] = (rq_hd != rq_tl);
      bkend_ftq_rsv[0]     = rq[rq_hd % 256];
      dec_ibuf_rdy         = rstn && run_be && !mt_pend &&
                             ((be_rdy_pat == 0) ||
                              ((cyc % be_rdy_pat) == 0));
      // BP-123.
      cmt_ifu_maint_val    = mt_req;
      cmt_ifu_maint_op     = (W.ex[mt_e].maint == 1) ? MAINT_FENCE_I
                                                     : MAINT_CBO_INVAL;
      cmt_ifu_maint_paddr  = W.ex[mt_e].mpa;
      // Every entry with a retired instruction has been committed (as
      // driven to the FTQ this cycle).
      cm_all = !cur_val ||
               (wm_val && bkend_ftq_commit_val &&
                (bkend_ftq_commit_idx == wm) &&
                (after_redir || (wm == cur_ptr)));
    end
  end

  // Every model's state to its start, the memory image empty and the
  // CSRs at their csr_tb_pkg reset values (CSR-7) with the privilege
  // and satp of the regime: bare runs in M-mode, Sv39 in S-mode with
  // ASID 1. rstn is held low until release_reset.
  task automatic models_reset(input logic use_sv39);
    rstn         = 1'b0;
    run_be       = 1'b0;
    W.ne           = 0;
    ep           = 0;
    cfi_pend     = 1'b0;
    after_redir  = 1'b0;
    cur_val      = 1'b0;
    cur_ptr      = '0;
    wm_val       = 1'b0;
    wm           = '0;
    n_retired    = 0;
    n_mispred    = 0;
    n_trap       = 0;
    n_err        = 0;
    n_fault_ok   = 0;
    n_mis_ras    = 0;
    n_mis_watch  = 0;
    watch_pc     = '0;
    n_mis_warm   = 0;
    for (int t = 0; t < 8; t++) n_mis_type[t] = 0;
    mis_pc.delete();
    mis_typ.delete();
    ras_exp.delete();
    ras_got.delete();
    n_ras_ok     = 0;
    n_ras_bad    = 0;
    n_hist_ok    = 0;
    n_hist_bad   = 0;
    h_chk        = 1'b0;
    h_dir        = 1'b0;
    warm_e       = 0;
    W.dry          = 1'b0;
    meas         = 1'b0;
    n_fills      = 0;
    n_walks      = 0;
    n_pd_redir   = 0;
    n_m3_cond    = 0;
    rq_hd        = 0;
    rq_tl        = 0;
    rd_pend      = 1'b0;
    // BP-123.
    mt_pend       = 1'b0;
    mt_req        = 1'b0;
    mt_e          = 0;
    n_maint       = 0;
    n_maint_drain = 0;
    eager         = 1'b0;
    be_rdy_pat    = 0;
    cm_all        = 1'b1;
    n_eager_res   = 0;
    n_patch       = 0;
    n_csrw        = 0;
    n_pw_acc      = 0;
    n_pw_cas      = 0;
    n_pw_err      = 0;
    n_pw_chg      = 0;
    n_pw_bad      = 0;
    pw_lat_min    = 2;
    pw_lat_max    = 2;
    pw_rdy_pat    = 0;
    err_arm       = 1'b0;
    err_pa        = '0;
    chg_arm       = 1'b0;
    chg_pa        = '0;
    chg_val       = '0;
    W.pat_a.delete();
    W.pat_h.delete();
    W.act_madue.delete();
    W.act_hadue.delete();
    W.act_mpbmte.delete();
    W.act_hpbmte.delete();
    W.patching    = 1'b0;
    W.nowrite     = 1'b0;
    W.uc_ppn.delete();
    W.uc_vpn.delete();
    W.h2          = 1'b0;
    W.g_bare      = 1'b0;
    W.gmap.delete();
    walk_lo       = '0;
    walk_hi       = '0;
    n_walk_rng    = 0;
    walk2_lo      = '0;
    walk2_hi      = '0;
    n_walk_rng2   = 0;
    inv_watch     = 1'b0;
    inv_vpn       = '0;
    inv_at        = -1;
    n_inv_fired   = 0;
    n_inv_busy    = 0;
    W.mem.delete();
    W.vmap.delete();
    W.sv39         = use_sv39;
    W.satp_root    = PA_WIDTH'('h0_8F00_0000);
    W.pt_next      = PA_WIDTH'('h0_8F00_1000);
    for (int i = 0; i < 512; i++) W.wr64(W.satp_root + PA_WIDTH'(8 * i), '0);
    for (int i = 0; i < FTQ_DEPTH; i++) fstart[i] = '0;
    // csr (SYS-001, csr_tb_pkg). Bare runs in M-mode; Sv39 runs in
    // S-mode with ASID 1. csr_reset gives the rest, the csr_pkg reset
    // values (CSR-7), which are this testbench's settings: V 0, vsatp
    // and hgatp 0, PMP entry 0 NAPOT over all of memory with R, W and
    // X (so S-mode fetch is not denied by the no-match rule) and every
    // other entry OFF, menvcfg and henvcfg PBMTE 1 and ADUE 0, and the
    // config group: sc_enable 1, the FTB fast path and both agings
    // off, intervals 0, ext_enable RVA23_ENABLE. The walker's group
    // (MMU-24a, BP-123) is packed from the same CSRs.
    csr_tb_pkg::csr_reset();
    csr_tb_pkg::set_priv(use_sv39 ? CSR_PRV_S : CSR_PRV_M);
    csr_wr_satp(use_sv39 ? CSR_SATP_MODE_SV39 : CSR_SATP_MODE_BARE,
                use_sv39 ? ASID_WIDTH'(1) : '0,
                44'(W.satp_root >> 12));
    // maintenance
    bkend_itlb_inv_val    = 1'b0;
    bkend_itlb_inv_op     = '0;
    bkend_itlb_inv_rs1_nz = 1'b0;
    bkend_itlb_inv_rs2_nz = 1'b0;
    bkend_itlb_inv_vpn    = '0;
    bkend_itlb_inv_asid   = '0;
    bkend_itlb_inv_vmid   = '0;
  endtask

  task automatic release_reset();
    repeat (4) @(posedge clk);
    #1;
    rstn   = 1'b1;
    run_be = 1'b1;
  endtask
