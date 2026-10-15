// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fe_demo_proofs.svh -- the proof of each scenario (FD-0b, FDT-10)
//
// Included inside module tb by tb_fe_demo.sv. proof() is evaluated at
// the end of a run, after the drain, from the monitor counts of
// fe_demo_mon.svh. msg names the figures the proof read, so a DEMO
// line says what was seen as well as whether it was enough.
// ===================================================================

  function automatic logic proof(input string nm, output string msg);
    case (nm)
      "fd01_reset_init": begin
        // The proof as fe_demo_scenarios.md FD-1 gives it: each ready
        // seen low after reset then rising, and the first prediction
        // the FTQ accepted at or after the last of them. The first
        // response and first update of each queued predictor are
        // reported beside it.
        int last;
        last = c_tage_rdy;
        if (c_it_rdy > last) last = c_it_rdy;
        if (c_sc_rdy > last) last = c_sc_rdy;
        msg = $sformatf({"ready rose at cycle TAGE %0d ITTAGE %0d SC %0d ",
                         "(seen low %0d%0d%0d), RAS %0d; first p0 %0d, ",
                         "first accepted p1 %0d; first response TAGE %0d ",
                         "ITTAGE %0d SC %0d; first update TAGE %0d ",
                         "ITTAGE %0d SC %0d"},
                        c_tage_rdy, c_it_rdy, c_sc_rdy, lo_tage_rdy,
                        lo_it_rdy, lo_sc_rdy, c_ras_rdy, c_p0, c_p1,
                        c_tage_p2, c_it_p2, c_sc_p3, c_tage_u, c_it_u,
                        c_sc_u);
        return lo_tage_rdy && lo_it_rdy && lo_sc_rdy && (c_tage_rdy > 0) &&
               (c_it_rdy > 0) && (c_sc_rdy > 0) && (c_p1 >= last);
      end
      "fd02_steady": begin
        msg = $sformatf({"%0d allocations, longest run %0d; %0d full ",
                         "decode bundles, longest run %0d"},
                        n_alloc, max_run_alloc, n_dec8, max_run_dec8);
        return (max_run_alloc >= 4) && (max_run_dec8 >= 4);
      end
      "fd03_two_branch": begin
        msg = $sformatf("blocks with both slots valid: p1 %0d, p2 %0d",
                        n_two_p1, n_two_p2);
        return (n_two_p1 + n_two_p2) > 0;
      end
      "fd04_p2_override": begin
        msg = $sformatf("p2 redirects %0d", n_redir_p2);
        return n_redir_p2 > 0;
      end
      "fd05_p3_override": begin
        msg = $sformatf("p3 redirects %0d, of them SC reversals %0d",
                        n_redir_p3, n_redir_p3_sc);
        return n_redir_p3_sc > 0;
      end
      "fd06_loop_pred": begin
        msg = $sformatf("loop exits the LP predicted not taken %0d",
                        n_lp_exit_ok);
        return n_lp_exit_ok > 0;
      end
      "fd07_calls_returns": begin
        msg = $sformatf({"returns predicted by the RAS %0d; p2 pushes %0d ",
                         "pops %0d return-calls %0d; highest recursion ",
                         "count %0d"}, n_ras_ret_ok, n_ras_push, n_ras_pop,
                        n_rc_p2, max_rctr);
        return (n_ras_ret_ok > 0) && (max_rctr > 1) && (n_rc_p2 > 0);
      end
      "fd08_indirect": begin
        msg = $sformatf("indirect targets predicted by ITTAGE %0d", n_itt_ok);
        return n_itt_ok > 0;
      end
      "fd09_tage": begin
        msg = $sformatf({"tagged-provider predictions %0d; allocations %0d; ",
                         "T0 by use_alt_on_na %0d"}, n_tage_prov,
                        n_tage_alc, n_t0_uaon);
        return (n_tage_alc > 0) && (n_t0_uaon > 0);
      end
      "fd10_pd_redirect": begin
        msg = $sformatf("predecode redirects %0d", n_pd_redir);
        return n_pd_redir > 0;
      end
      "fd11_be_mispredict": begin
        msg = $sformatf({"backend mispredict redirects %0d, followed by a ",
                         "fetch at the redirect PC %0d; rollbacks %0d, ",
                         "RAS restores %0d"}, n_be_misp, n_be_fix,
                        n_rollback, n_ras_rest);
        return n_be_fix > 0;
      end
      "fd12_training": begin
        msg = $sformatf({"update cycles uBTB %0d LP %0d FTB %0d TAGE %0d ",
                         "SC %0d ITTAGE %0d RAS commit %0d; FTB update ",
                         "p0 holds %0d"}, n_upd_ubtb, n_upd_lp, n_upd_ftb,
                        n_upd_tage, n_upd_sc, n_upd_itt, n_upd_ras,
                        n_ftb_bub);
        return (n_upd_ubtb > 0) && (n_upd_lp > 0) && (n_upd_ftb > 0) &&
               (n_upd_tage > 0) && (n_upd_sc > 0) && (n_upd_itt > 0) &&
               (n_upd_ras > 0) && (n_ftb_bub > 0);
      end
      "fd13_l1i": begin
        msg = $sformatf("L1I hits %0d, misses %0d, merges %0d",
                        n_l1i_hit, n_l1i_miss, n_l1i_merge);
        return (n_l1i_hit > 0) && (n_l1i_miss > 0) && (n_l1i_merge > 0);
      end
      "fd14_translation": begin
        msg = $sformatf({"walks V=0 %0d, V=1 %0d (G-stage PTE evaluations ",
                         "%0d); CAS %0d"}, n_walk_s, n_walk_g, n_g_eval,
                        n_cas);
        return (n_walk_s > 0) && (n_walk_g > 0) && (n_g_eval > 0) &&
               (n_cas > 0);
      end
      "fd15_faults": begin
        msg = $sformatf({"faults at decode: page %0d, guest-page %0d, ",
                         "access %0d"},
                        n_flt_page, n_flt_guest, n_flt_acc);
        return (n_flt_page > 0) && (n_flt_guest > 0) && (n_flt_acc > 0);
      end
      "fd16_page_cross": begin
        msg = $sformatf("blocks translated twice %0d", n_xq_cross);
        return n_xq_cross > 0;
      end
      "fd17_rvc": begin
        msg = $sformatf({"32-bit instructions at block position 15 ",
                         "delivered whole %0d; 16-bit instructions %0d"},
                        n_straddle, n_rvc);
        return (n_straddle > 0) && (n_rvc > 0);
      end
      "fd18_uncached": begin
        msg = $sformatf("uncached requests %0d; uncached lines filled %0d",
                        n_uc_req, n_uc_alloc);
        return (n_uc_req > 0) && (n_uc_alloc == 0);
      end
      "fd19_fencei_cbo": begin
        msg = $sformatf({"invalidates all %0d, line %0d; done %0d; acks %0d; ",
                         "restarts at the next instruction %0d"},
                        n_inv_all, n_inv_line, n_inv_done, n_mt_ack,
                        n_restart);
        return (n_inv_all > 0) && (n_inv_line > 0) && (n_inv_done >= 2) &&
               (n_restart >= 2);
      end
      "fd20_backpressure": begin
        msg = $sformatf({"stall cycles: ibuf full %0d, FTQ full %0d, ",
                         "decode held %0d, no p0 request %0d"},
                        n_ibuf_full, n_ftq_full, n_dec_stall, n_p0_held);
        return (n_ibuf_full > 0) && (n_ftq_full > 0) && (n_dec_stall > 0) &&
               (n_p0_held > 0);
      end
      "fd21_commit": begin
        msg = $sformatf({"cycles the commit pointer moved %0d; cycles the ",
                         "RAS commit stack changed %0d"}, n_commit_adv,
                        n_csp_chg);
        return (n_commit_adv >= 16) && (n_csp_chg > 0);
      end
      default: begin
        msg = "no such scenario";
        return 1'b0;
      end
    endcase
  endfunction
